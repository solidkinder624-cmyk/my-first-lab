"""Output steps: save to Notion, notify Slack.

Both are side-effecting ("送信・公開・課金のような副作用処理には冪等性キーが必須",
design principle 4), so the orchestrator only calls these once per job and
records success in JobState (`notion_saved` / `slack_sent`) before moving on.

With no NOTION_TOKEN / SLACK_WEBHOOK_URL configured, both fall back to a
dry-run that prints what would be sent -- so the lab runs with zero external
credentials while staying a drop-in real integration when the env vars are set.
"""
from __future__ import annotations

import json
import os
import urllib.request
from typing import Any

Summary = dict[str, Any]


def save_to_notion(job_id: str, summaries: list[Summary]) -> None:
    token = os.environ.get("NOTION_TOKEN")
    database_id = os.environ.get("NOTION_DATABASE_ID")
    if not token or not database_id:
        print(f"[dry-run] would save {len(summaries)} summaries to Notion for job {job_id}")
        return

    for summary in summaries:
        payload = {
            "parent": {"database_id": database_id},
            "properties": {
                "Name": {"title": [{"text": {"content": summary["title"]}}]},
                "URL": {"url": summary["url"]},
                "Summary": {"rich_text": [{"text": {"content": summary["summary"]}}]},
            },
        }
        req = urllib.request.Request(
            "https://api.notion.com/v1/pages",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {token}",
                "Notion-Version": "2022-06-28",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        urllib.request.urlopen(req, timeout=10)


def send_slack(job_id: str, summaries: list[Summary]) -> None:
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    lines = [f"*Daily AI News* ({job_id})"] + [f"- <{s['url']}|{s['title']}>" for s in summaries]
    text = "\n".join(lines)

    if not webhook_url:
        print(f"[dry-run] would post to Slack for job {job_id}:\n{text}")
        return

    req = urllib.request.Request(
        webhook_url,
        data=json.dumps({"text": text}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=10)


def send_slack_warning(job_id: str, message: str) -> None:
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    text = f"*Daily AI News job {job_id} needs attention*: {message}"
    if not webhook_url:
        print(f"[dry-run] would post Slack warning for job {job_id}: {message}")
        return
    req = urllib.request.Request(
        webhook_url,
        data=json.dumps({"text": text}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=10)
