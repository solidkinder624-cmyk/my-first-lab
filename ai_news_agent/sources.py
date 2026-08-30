"""Article collection -- a "code" step, not an "AI judgement" step
(design principle 1: mechanical work stays in code).

Real usage: point AI_NEWS_SOURCE_URL at a JSON endpoint returning a list of
``{"title", "url", "published_at"}`` objects. With no URL configured (the
default for this lab) a small fixed demo dataset is used instead, so the
whole pipeline runs end to end with no external credentials.

``AI_NEWS_SIMULATE`` lets tests/demos exercise the guardrails without real
network flakiness:
  - "network_error" -> raise TransientError every call (tests the 3x retry)
  - "auth_error"     -> raise AuthError (tests the immediate-stop path)
  - "no_articles"    -> return an empty list (tests the zero-articles guardrail)
"""
from __future__ import annotations

import json
import os
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any

from .errors import AuthError, TransientError

Article = dict[str, Any]


def _demo_articles() -> list[Article]:
    now = datetime.now(timezone.utc)
    return [
        {
            "title": "Anthropic releases new agent framework",
            "url": "https://example.com/news/anthropic-agent-framework",
            "published_at": (now - timedelta(hours=2)).isoformat(),
        },
        {
            "title": "Anthropic releases new agent framework",  # duplicate title
            "url": "https://example.com/news/anthropic-agent-framework",
            "published_at": (now - timedelta(hours=2, minutes=5)).isoformat(),
        },
        {
            "title": "OpenAI announces model update",
            "url": "https://example.com/news/openai-model-update",
            "published_at": (now - timedelta(hours=5)).isoformat(),
        },
        {
            "title": "Google DeepMind publishes new benchmark results",
            "url": "https://example.com/news/deepmind-benchmark",
            "published_at": (now - timedelta(hours=8)).isoformat(),
        },
        {
            "title": "Startup raises funding for AI safety research",
            "url": "https://example.com/news/ai-safety-funding",
            "published_at": (now - timedelta(hours=10)).isoformat(),
        },
        {
            "title": "New open-source LLM tops leaderboard",
            "url": "https://example.com/news/open-source-llm-leaderboard",
            "published_at": (now - timedelta(hours=14)).isoformat(),
        },
        {
            "title": "Conference recap: agentic workflows in production",
            "url": "https://example.com/news/agentic-workflows-conference",
            "published_at": (now - timedelta(hours=20)).isoformat(),
        },
        {
            "title": "Old article outside the lookback window",
            "url": "https://example.com/news/old-article",
            "published_at": (now - timedelta(hours=36)).isoformat(),
        },
    ]


def fetch_articles() -> list[Article]:
    simulate = os.environ.get("AI_NEWS_SIMULATE")
    if simulate == "network_error":
        raise TransientError("simulated connection timeout")
    if simulate == "auth_error":
        raise AuthError("simulated invalid API key")
    if simulate == "no_articles":
        return []

    source_url = os.environ.get("AI_NEWS_SOURCE_URL")
    if not source_url:
        return _demo_articles()

    try:
        with urllib.request.urlopen(source_url, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise TransientError(str(exc)) from exc
    except TimeoutError as exc:
        raise TransientError(str(exc)) from exc

    if isinstance(payload, dict) and payload.get("error") == "unauthorized":
        raise AuthError("source API rejected credentials")
    return payload if isinstance(payload, list) else payload.get("articles", [])
