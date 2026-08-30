"""Pure workflow steps.

Split by design principle 1 ("AIへ渡すのは判断だけ"):
  - filter_recent / dedupe / validate_summary_schema -> mechanical, in code
  - rank_importance / summarize                       -> "judgement", where an
    LLM call belongs. They are implemented here as small deterministic
    heuristics so the whole pipeline runs offline in this lab; swap the body
    of ``rank_importance``/``summarize`` for a real Claude API call to make
    this a genuine AI-judgement step without touching anything else.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from . import guardrails
from .errors import ValidationError

Article = dict[str, Any]
Summary = dict[str, Any]

_IMPORTANCE_KEYWORDS = ("release", "launch", "funding", "benchmark", "safety", "update")


def filter_recent(articles: list[Article], hours: int = guardrails.LOOKBACK_HOURS) -> list[Article]:
    """Keep only articles published within the lookback window (design principle 2: 完了条件)."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    kept = []
    for article in articles:
        published = datetime.fromisoformat(article["published_at"])
        if published.tzinfo is None:
            published = published.replace(tzinfo=timezone.utc)
        if published >= cutoff:
            kept.append(article)
    return kept


def dedupe(articles: list[Article]) -> list[Article]:
    """Drop duplicates by URL first, then by title (design principle 2: URL重複除去済み)."""
    seen_urls: set[str] = set()
    seen_titles: set[str] = set()
    unique: list[Article] = []
    for article in articles:
        url = article.get("url")
        title = article.get("title")
        if url in seen_urls or title in seen_titles:
            continue
        seen_urls.add(url)
        seen_titles.add(title)
        unique.append(article)
    return unique


def rank_importance(articles: list[Article], top_n: int = guardrails.TOP_N_ARTICLES) -> list[Article]:
    """AI-judgement step (stubbed): score and keep the top N.

    Real implementation: one LLM call that returns an ordered list of
    article ids with an importance score and a reason -- called at most
    once per job (guardrails.RANKING_MAX_CALLS), never in a retry loop.
    """
    def score(article: Article) -> int:
        title = article["title"].lower()
        return sum(1 for kw in _IMPORTANCE_KEYWORDS if kw in title)

    ranked = sorted(articles, key=score, reverse=True)
    return ranked[:top_n]


def summarize(article: Article) -> Summary:
    """AI-judgement step (stubbed): produce a <=200 char summary with a reason.

    Real implementation: one LLM call per article (or one batched call),
    returning JSON matching the schema checked by ``validate_summary_schema``.
    """
    reason = "Selected for relevance to AI industry readers based on topic keywords."
    summary_text = f"{article['title']}."[: guardrails.SUMMARY_MAX_CHARS]
    return {
        "title": article["title"],
        "url": article.get("url"),
        "summary": summary_text,
        "reason": reason,
    }


def validate_summary_schema(summary: Summary) -> None:
    """Guardrail: 元URLなし要約は送信しない + JSON検証 (design principle 2/6)."""
    required = ("title", "url", "summary", "reason")
    missing = [key for key in required if not summary.get(key)]
    if missing:
        raise ValidationError(f"summary missing required fields: {missing}")
    if len(summary["summary"]) > guardrails.SUMMARY_MAX_CHARS:
        raise ValidationError("summary exceeds max length")
