"""External job state (design principle 3 / page 4: "会話ではなく外部状態で管理する").

State lives on disk as one JSON file per job_id, keyed by an idempotency
key, so:
  - a crash mid-run can be resumed from `current_step`, not from scratch
  - re-running a completed job is a safe no-op
  - "what happened, and why" survives after the process exits
"""
from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any

STATE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "state")

# Ordered so `STEPS.index(step)` gives a resumption point (page 3 state diagram).
STEPS = [
    "queued",
    "collecting_sources",
    "deduplicating",
    "ranking",
    "summarizing",
    "validating",
    "saving_notion",
    "notifying_slack",
    "completed",
]


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass
class JobState:
    job_id: str
    idempotency_key: str
    status: str = "queued"          # queued|running|completed|failed
    current_step: str = "queued"
    retryable: bool = True
    article_count: int = 0
    selected_count: int = 0
    ranking_calls: int = 0
    summary_regenerations: int = 0
    fetch_attempts: int = 0
    cost_usd: float = 0.0
    notion_saved: bool = False
    slack_sent: bool = False
    last_error: str | None = None
    next_action: str = "collect_sources"
    updated_at: str = field(default_factory=_now)

    # -- persistence -----------------------------------------------------
    @classmethod
    def _path(cls, job_id: str) -> str:
        os.makedirs(STATE_DIR, exist_ok=True)
        return os.path.join(STATE_DIR, f"{job_id}.json")

    @classmethod
    def load_or_create(cls, job_id: str, idempotency_key: str) -> "JobState":
        path = cls._path(job_id)
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return cls(**data)
        return cls(job_id=job_id, idempotency_key=idempotency_key)

    def save(self) -> None:
        self.updated_at = _now()
        with open(self._path(self.job_id), "w", encoding="utf-8") as f:
            json.dump(asdict(self), f, ensure_ascii=False, indent=2)

    # -- transitions -------------------------------------------------------
    def advance(self, step: str, **fields: Any) -> None:
        self.current_step = step
        for key, value in fields.items():
            setattr(self, key, value)
        self.status = "running"
        self.save()

    def complete(self) -> None:
        self.status = "completed"
        self.current_step = "completed"
        self.next_action = "none"
        self.save()

    def fail(self, reason: str, retryable: bool) -> None:
        self.status = "failed"
        self.last_error = reason
        self.retryable = retryable
        self.save()

    def add_cost(self, usd: float) -> None:
        self.cost_usd = round(self.cost_usd + usd, 4)
        self.save()
