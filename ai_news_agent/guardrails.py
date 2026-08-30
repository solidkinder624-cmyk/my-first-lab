"""Guardrail constants -- "where the system stops itself" (design principle 6/7).

These are read by the orchestrator; they are plain data on purpose so the
limits are auditable without reading control flow.
"""

# 一時通信エラーのみ最大3回まで再試行
FETCH_MAX_RETRIES = 3
FETCH_RETRY_BACKOFF_SECONDS = (0.0, 0.0, 0.0)  # kept short for the lab/demo;
# production values from the infographic: 30s -> 2min -> 10min

# AI評価(重要度ランキング)は1ジョブにつき最大1回
RANKING_MAX_CALLS = 1

# 要約のJSON出力が不正な場合のみ、再生成を最大2回まで許可
SUMMARY_MAX_REGENERATIONS = 2

# 上位何件を要約するか
TOP_N_ARTICLES = 5

# 収集対象は過去24時間以内の記事のみ
LOOKBACK_HOURS = 24

# 1要約あたりの文字数上限
SUMMARY_MAX_CHARS = 200

# 1回の実行(ジョブ)にかけてよい推定コストの上限(USD)
COST_CAP_USD = 2.0

# 取得記事が最低これだけないと「収集完了」とみなさない
MIN_ARTICLES_REQUIRED = 1
