#!/usr/bin/env python3
"""Trigger layer: this is what a scheduler (cron / Claude Routines, page 8's
"毎日8:00") invokes. All it does is call the orchestrator; every real
decision lives in ai_news_agent/.

Usage:
    python run_daily_news_agent.py                # run/resume today's job
    python run_daily_news_agent.py --date 2026-08-30
"""
from __future__ import annotations

import argparse
import sys

from ai_news_agent.orchestrator import run_job


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", help="target date (YYYY-MM-DD), defaults to today")
    args = parser.parse_args()

    state = run_job(target_date=args.date)
    return 0 if state.status == "completed" else 1


if __name__ == "__main__":
    sys.exit(main())
