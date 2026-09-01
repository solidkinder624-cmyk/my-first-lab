"""Article collection -- a "code" step, not an "AI judgement" step
(design principle 1: mechanical work stays in code).

Real usage: point AI_NEWS_SOURCE_URL at one or more comma-separated feed
URLs. Each is auto-detected as either an RSS 2.0 feed (most tech news
sites, e.g. TechCrunch AI, VentureBeat AI -- no API key needed) or a JSON
endpoint returning a list of ``{"title", "url", "published_at"}`` objects
(for a real news API). With no URL configured (the default for this lab) a
small fixed demo dataset is used instead, so the whole pipeline runs end to
end with no external credentials.

``AI_NEWS_SIMULATE`` lets tests/demos exercise the guardrails without real
network flakiness:
  - "network_error" -> raise TransientError every call (tests the 3x retry)
  - "auth_error"     -> raise AuthError (tests the immediate-stop path)
  - "no_articles"    -> return an empty list (tests the zero-articles guardrail)
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
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

    source_urls = os.environ.get("AI_NEWS_SOURCE_URL")
    if not source_urls:
        return _demo_articles()

    articles: list[Article] = []
    for url in (u.strip() for u in source_urls.split(",")):
        if url:
            articles.extend(_fetch_one_source(url))
    return articles


def _fetch_one_source(url: str) -> list[Article]:
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.URLError as exc:
        raise TransientError(f"{url}: {exc}") from exc
    except TimeoutError as exc:
        raise TransientError(f"{url}: {exc}") from exc

    if raw.lstrip().startswith("<"):
        try:
            return _parse_rss(raw)
        except ET.ParseError as exc:
            raise TransientError(f"{url}: invalid RSS/XML response ({exc})") from exc

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise TransientError(f"{url}: unrecognized response format ({exc})") from exc

    if isinstance(payload, dict) and payload.get("error") == "unauthorized":
        raise AuthError(f"{url}: source API rejected credentials")
    return payload if isinstance(payload, list) else payload.get("articles", [])


def _parse_rss(xml_text: str) -> list[Article]:
    """Parse a standard RSS 2.0 feed's <item> entries into our article shape."""
    root = ET.fromstring(xml_text)
    articles: list[Article] = []
    for item in root.iter("item"):
        title_el = item.find("title")
        link_el = item.find("link")
        if title_el is None or link_el is None or not title_el.text or not link_el.text:
            continue

        published_at = datetime.now(timezone.utc).isoformat()
        pubdate_el = item.find("pubDate")
        if pubdate_el is not None and pubdate_el.text:
            try:
                published_at = parsedate_to_datetime(pubdate_el.text).astimezone(timezone.utc).isoformat()
            except (TypeError, ValueError):
                pass  # keep the "now" fallback rather than dropping the article

        articles.append({
            "title": title_el.text.strip(),
            "url": link_el.text.strip(),
            "published_at": published_at,
        })
    return articles
