import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from ai_news_agent import guardrails, orchestrator, pipeline, sinks, sources, state
from ai_news_agent.errors import ValidationError


class SourcesTests(unittest.TestCase):
    def test_parse_rss_extracts_title_url_and_published_at(self):
        xml_text = """<?xml version="1.0"?>
        <rss version="2.0"><channel>
          <item>
            <title>Anthropic ships new agent tooling</title>
            <link>https://example.com/a</link>
            <pubDate>Tue, 01 Sep 2026 08:07:00 GMT</pubDate>
          </item>
          <item>
            <title>No pubDate article</title>
            <link>https://example.com/b</link>
          </item>
        </channel></rss>"""
        articles = sources._parse_rss(xml_text)
        self.assertEqual(len(articles), 2)
        self.assertEqual(articles[0]["title"], "Anthropic ships new agent tooling")
        self.assertEqual(articles[0]["url"], "https://example.com/a")
        self.assertEqual(articles[0]["published_at"], "2026-09-01T08:07:00+00:00")
        self.assertIn("published_at", articles[1])  # falls back to "now" rather than dropping

    def test_parse_rss_skips_items_missing_title_or_link(self):
        xml_text = """<rss version="2.0"><channel>
          <item><title>Has no link</title></item>
          <item><link>https://example.com/only-link</link></item>
        </channel></rss>"""
        self.assertEqual(sources._parse_rss(xml_text), [])


class PipelineTests(unittest.TestCase):
    def test_filter_recent_drops_old_articles(self):
        now = datetime.now(timezone.utc)
        articles = [
            {"title": "fresh", "url": "https://x/1", "published_at": (now - timedelta(hours=1)).isoformat()},
            {"title": "stale", "url": "https://x/2", "published_at": (now - timedelta(hours=48)).isoformat()},
        ]
        kept = pipeline.filter_recent(articles)
        self.assertEqual([a["title"] for a in kept], ["fresh"])

    def test_dedupe_by_url_and_title(self):
        articles = [
            {"title": "a", "url": "https://x/1"},
            {"title": "a", "url": "https://x/1"},
            {"title": "a different title", "url": "https://x/1"},  # same url
            {"title": "b", "url": "https://x/2"},
        ]
        unique = pipeline.dedupe(articles)
        self.assertEqual(len(unique), 2)

    def test_validate_summary_schema_rejects_missing_url(self):
        with self.assertRaises(ValidationError):
            pipeline.validate_summary_schema(
                {"title": "t", "url": "", "summary": "s", "reason": "r"}
            )

    def test_validate_summary_schema_accepts_well_formed(self):
        pipeline.validate_summary_schema(
            {"title": "t", "url": "https://x/1", "summary": "s", "reason": "r"}
        )


class OrchestratorTests(unittest.TestCase):
    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self._patched_state_dir = mock.patch.object(state, "STATE_DIR", self._tmpdir.name)
        self._patched_state_dir.start()
        os.environ.pop("AI_NEWS_SIMULATE", None)

    def tearDown(self):
        self._patched_state_dir.stop()
        self._tmpdir.cleanup()
        os.environ.pop("AI_NEWS_SIMULATE", None)

    def test_end_to_end_dry_run_completes(self):
        result = orchestrator.run_job(target_date="2026-08-30")
        self.assertEqual(result.status, "completed")
        self.assertEqual(result.selected_count, guardrails.TOP_N_ARTICLES)
        self.assertTrue(result.notion_saved)
        self.assertTrue(result.slack_sent)
        self.assertLessEqual(result.cost_usd, guardrails.COST_CAP_USD)

    def test_rerun_of_completed_job_is_idempotent_noop(self):
        orchestrator.run_job(target_date="2026-08-31")
        with mock.patch.object(sinks, "send_slack") as send_slack:
            second = orchestrator.run_job(target_date="2026-08-31")
        send_slack.assert_not_called()
        self.assertEqual(second.status, "completed")

    def test_zero_articles_guardrail_stops_with_warning(self):
        os.environ["AI_NEWS_SIMULATE"] = "no_articles"
        result = orchestrator.run_job(target_date="2026-09-01")
        self.assertEqual(result.status, "failed")
        self.assertFalse(result.retryable)
        self.assertIn("zero articles", result.last_error)

    def test_network_error_retries_then_fails_retryably(self):
        os.environ["AI_NEWS_SIMULATE"] = "network_error"
        result = orchestrator.run_job(target_date="2026-09-02")
        self.assertEqual(result.status, "failed")
        self.assertTrue(result.retryable)
        self.assertEqual(result.fetch_attempts, guardrails.FETCH_MAX_RETRIES)

    def test_auth_error_stops_immediately_without_retry(self):
        os.environ["AI_NEWS_SIMULATE"] = "auth_error"
        result = orchestrator.run_job(target_date="2026-09-03")
        self.assertEqual(result.status, "failed")
        self.assertFalse(result.retryable)
        self.assertEqual(result.fetch_attempts, 1)

    def test_slack_failure_only_retries_notify_step_not_notion(self):
        with mock.patch.object(sinks, "send_slack", side_effect=RuntimeError("boom")):
            first = orchestrator.run_job(target_date="2026-09-04")
        self.assertEqual(first.status, "failed")
        self.assertTrue(first.retryable)
        self.assertTrue(first.notion_saved)
        self.assertFalse(first.slack_sent)

        with mock.patch.object(sinks, "save_to_notion") as save_to_notion:
            result = orchestrator.run_job(target_date="2026-09-04")
        save_to_notion.assert_not_called()
        self.assertTrue(result.slack_sent)
        self.assertEqual(result.status, "completed")


if __name__ == "__main__":
    unittest.main()
