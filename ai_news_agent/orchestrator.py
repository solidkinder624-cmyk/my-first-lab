"""The orchestrator: Trigger -> Workflow -> Agent -> Guardrail, wired together.

This is the only module with control flow / side effects; every step it
calls is either a pure function (pipeline.py) or an isolated I/O call
(sources.py, sinks.py), each independently retryable and idempotent per
JobState. See README.md for the state diagram this implements.
"""
from __future__ import annotations

import time
from datetime import date
from typing import Any

from . import guardrails, pipeline, sinks, sources
from .errors import AuthError, GuardrailStop, TransientError, ValidationError
from .state import JobState

# Rough per-call cost estimates (USD) for the guardrail cost cap; real
# implementation would read actual token usage from the LLM response.
_RANKING_CALL_COST = 0.05
_SUMMARY_CALL_COST = 0.02


def _job_id_for(target_date: str) -> str:
    return f"daily-ai-news-{target_date}"


def _check_cost_cap(state: JobState) -> None:
    if state.cost_usd > guardrails.COST_CAP_USD:
        raise GuardrailStop(f"cost cap exceeded: ${state.cost_usd} > ${guardrails.COST_CAP_USD}")


def _fetch_with_retry(state: JobState) -> list[dict[str, Any]]:
    last_error: Exception | None = None
    for attempt in range(guardrails.FETCH_MAX_RETRIES):
        state.fetch_attempts = attempt + 1
        try:
            return sources.fetch_articles()
        except TransientError as exc:
            last_error = exc
            delay = guardrails.FETCH_RETRY_BACKOFF_SECONDS[
                min(attempt, len(guardrails.FETCH_RETRY_BACKOFF_SECONDS) - 1)
            ]
            if delay:
                time.sleep(delay)
    assert last_error is not None
    raise last_error


def run_job(target_date: str | None = None) -> JobState:
    """Run (or resume) one day's news digest job. Safe to call repeatedly."""
    target_date = target_date or date.today().isoformat()
    job_id = _job_id_for(target_date)
    state = JobState.load_or_create(job_id, idempotency_key=job_id)

    # Idempotency (design principle 4): a completed job is a no-op.
    if state.status == "completed":
        print(f"[skip] {job_id} already completed at {state.updated_at}")
        return state

    # A job that failed for a non-retryable reason (e.g. auth) needs a human.
    if state.status == "failed" and not state.retryable:
        print(f"[blocked] {job_id} failed non-retryably: {state.last_error}")
        return state

    try:
        articles = _resume_collect(state)
        articles = _resume_dedupe(state, articles)
        top_articles = _resume_rank(state, articles)
        summaries = _resume_summarize(state, top_articles)
        _resume_save_notion(state, summaries)
        _resume_notify_slack(state, summaries)
        state.complete()
        print(f"[done] {job_id}: {state.selected_count} articles notified, cost=${state.cost_usd}")
        return state

    except AuthError as exc:
        state.fail(f"auth_error: {exc}", retryable=False)
        sinks.send_slack_warning(job_id, f"authentication failed, stopped: {exc}")
        return state

    except TransientError as exc:
        state.fail(f"network_error after {guardrails.FETCH_MAX_RETRIES} retries: {exc}", retryable=True)
        return state

    except GuardrailStop as exc:
        state.fail(exc.reason, retryable=False)
        sinks.send_slack_warning(job_id, exc.reason)
        return state

    except Exception as exc:  # noqa: BLE001 -- last resort: stop safely, never crash silently
        # Covers e.g. a Notion/Slack outage during saving_notion/notifying_slack:
        # whatever step already recorded notion_saved/slack_sent stays done, so
        # the next invocation resumes from exactly the step that failed.
        state.fail(f"unexpected_error at {state.current_step}: {exc}", retryable=True)
        return state


# -- per-step helpers, each a resumable checkpoint (design principle 3) -----

def _resume_collect(state: JobState) -> list[dict[str, Any]]:
    # Fetch/filter/dedupe/rank/summarize are side-effect free, so a resumed
    # run simply redoes them; only the steps below with real side effects
    # (Notion save, Slack notify) need an explicit "already done" guard.
    # (A non-deterministic real LLM would need the recomputed summaries
    # cached in JobState instead of redone, to keep Notion and Slack in
    # sync across a resume -- out of scope for this lab's deterministic stub.)
    articles = _fetch_with_retry(state)
    if len(articles) < guardrails.MIN_ARTICLES_REQUIRED:
        raise GuardrailStop("zero articles fetched", warning=True)
    recent = pipeline.filter_recent(articles)
    state.advance("collecting_sources", article_count=len(recent))
    return recent


def _resume_dedupe(state: JobState, articles: list[dict[str, Any]]) -> list[dict[str, Any]]:
    unique = pipeline.dedupe(articles)
    state.advance("deduplicating", article_count=len(unique))
    return unique


def _resume_rank(state: JobState, articles: list[dict[str, Any]]) -> list[dict[str, Any]]:
    # guardrails.RANKING_MAX_CALLS is enforced structurally: this function is
    # called at most once per run_job() attempt, with no retry loop around
    # it (an AI ranking failure is not treated as transient).
    state.ranking_calls += 1
    top = pipeline.rank_importance(articles)
    state.add_cost(_RANKING_CALL_COST)
    _check_cost_cap(state)
    state.advance("ranking", selected_count=len(top))
    return top


def _resume_summarize(state: JobState, articles: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries = []
    for article in articles:
        summary = _summarize_with_regeneration(state, article)
        if summary is not None:
            summaries.append(summary)
    if not summaries:
        raise GuardrailStop("no valid summaries after regeneration budget exhausted")
    state.advance("validating", selected_count=len(summaries))
    return summaries


def _summarize_with_regeneration(state: JobState, article: dict[str, Any]):
    attempts = 0
    while True:
        summary = pipeline.summarize(article)
        state.add_cost(_SUMMARY_CALL_COST)
        _check_cost_cap(state)
        try:
            pipeline.validate_summary_schema(summary)
            return summary
        except ValidationError:
            attempts += 1
            state.summary_regenerations += 1
            if attempts > guardrails.SUMMARY_MAX_REGENERATIONS:
                # drop this one article rather than fail the whole job
                return None


def _resume_save_notion(state: JobState, summaries: list[dict[str, Any]]) -> None:
    if state.notion_saved:
        return
    sinks.save_to_notion(state.job_id, summaries)
    state.advance("saving_notion", notion_saved=True)


def _resume_notify_slack(state: JobState, summaries: list[dict[str, Any]]) -> None:
    # Guardrail: Slack送信は1ジョブ1回. If Notion already succeeded but Slack
    # previously failed, only this step re-runs on the next invocation.
    if state.slack_sent:
        return
    sinks.send_slack(state.job_id, summaries)
    state.advance("notifying_slack", slack_sent=True)
