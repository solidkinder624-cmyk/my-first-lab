# my-first-lab
this is test
初めてのリポジトリ
わからない

## AIニュース日次エージェント (ai_news_agent/)

共有された設計図（Trigger / Workflow / Agent / Guardrail の4層設計、外部状態管理、
冪等性、リトライ種別ごとの扱い）を、実際に動くPythonコードに落とし込んだ実装。
外部APIキーが無くても dry-run で最後まで実行できる。

### 実行

```bash
python3 run_daily_news_agent.py --date 2026-08-30   # 省略時は今日の日付
python3 -m unittest discover -s tests -v
```

### 4層設計との対応

| 層 | このリポジトリでの実装 |
|---|---|
| **Trigger** (いつ始めるか) | `run_daily_news_agent.py`。`.github/workflows/daily-ai-news.yml` が毎朝8時(JST)にこれを呼ぶだけ。判断は一切持たない |
| **Workflow** (何をどの順で) | `ai_news_agent/orchestrator.py` の `run_job()`。取得→24h以内に絞る→重複除去→AIが重要度評価→上位5件要約→JSON検証→Notion保存→Slack通知 |
| **Agent** (どこで考えさせるか) | `ai_news_agent/pipeline.py` の `rank_importance()` / `summarize()` のみ。他はすべて機械的処理としてコード側に置く（設計原則1） |
| **Guardrail** (どこで止めるか) | `ai_news_agent/guardrails.py` の定数と、`orchestrator.py` 内の各チェック |

### 状態遷移とジョブ状態

`ai_news_agent/state.py` の `JobState` が `state/<job_id>.json` に永続化される
（会話やメモリではなく外部状態、設計原則3）。フィールドは元図の JSON 例
(`job_id` / `status` / `current_step` / `retry_count` / `cost_usd` / ...) に対応している。

状態遷移: `queued → collecting_sources → deduplicating → ranking → summarizing
→ validating → saving_notion → notifying_slack → completed`。失敗時は
`failed` になり、`retryable` フラグでリトライ可否を区別する。

`idempotency_key` は `daily-ai-news-<date>` 固定（設計原則4）。同じ日付で
再実行しても:
- 既に `completed` なら何もしない
- `saving_notion` まで済んでいれば Notion への再保存はスキップし、
  失敗していた Slack 通知だけをやり直す

### ガードレール (guardrails.py)

| ガードレール | 実装 |
|---|---|
| 取得0件なら停止（warning通知） | `MIN_ARTICLES_REQUIRED` |
| AI評価（重要度ランキング）は最大1回 | ループを持たず1呼び出しのみで構造的に保証 |
| JSON不正時のみ最大2回まで再生成 | `SUMMARY_MAX_REGENERATIONS` |
| Slack送信は1ジョブ1回 | `JobState.slack_sent` |
| 1回の実行コスト上限 | `COST_CAP_USD` |
| 元URLなし要約は送信しない | `pipeline.validate_summary_schema()` |

### 失敗時の処理 (エラー種別ごと)

`ai_news_agent/errors.py` でエラーを型として分け、`orchestrator.py` が種別ごとに扱う:

- **通信エラー** (`TransientError`) → 最大3回まで自動リトライ (`FETCH_MAX_RETRIES`)
- **認証エラー** (`AuthError`) → 即座に停止し `retryable=False`、Slackへ警告通知
- **記事0件** → 停止しSlackへ警告通知（`GuardrailStop`）
- **要約JSON不正** → 記事単位で最大2回まで再生成、それでも失敗した記事だけ除外
- **Slack送信失敗** → Notion保存済みの状態は保持したまま失敗を記録し、
  次回実行時は通知工程だけをやり直す（テスト:
  `tests/test_agent.py::OrchestratorTests::test_slack_failure_only_retries_notify_step_not_notion`）

### 本番接続への切り替え

すべて環境変数で有効化。未設定なら dry-run（標準出力に表示するだけ）で動く。

- `AI_NEWS_SOURCE_URL` — 記事一覧を返すJSON APIのURL（未設定時は同梱のデモ記事を使用）
- `NOTION_TOKEN` / `NOTION_DATABASE_ID` — Notion保存を実データで行う
- `SLACK_WEBHOOK_URL` — Slack通知を実際に送る
- `AI_NEWS_SIMULATE` — テスト/デモ用。`network_error` / `auth_error` / `no_articles`
  を指定するとその障害を強制的に発生させ、ガードレールの挙動を確認できる

### 毎朝8時の自動実行 (.github/workflows/daily-ai-news.yml)

GitHub Actionsのscheduled workflowが Trigger 層。`cron: "7 23 * * *"`
(UTC) = 毎朝8:07頃 JST に `run_daily_news_agent.py` を実行する。分をわざと
`:00`からずらしているのは、GitHubのscheduled workflowは毎時00分に世界中の
リポジトリが集中して混雑しやすく、実行が大幅に遅延・スキップされることが
あるため(実測: `0 23 * * *`のままだと、予定時刻から50分以上経っても
`schedule`イベントの実行が1件も記録されないことがあった)。

- **状態の永続化**: Actionsのランナーは実行ごとに使い捨てなので、実行後に
  `state/*.json` をリポジトリへコミットして外部保存する（設計原則3をCI環境でも維持）
- **多重起動防止**: `concurrency` グループにより、前回の実行が終わるまで次の
  トリガーは待機する（p5「複数エージェントが同時に仕事を始める」への対策）
- **手動実行**: GitHub の Actions タブから `workflow_dispatch` で手動実行も可能
  （`date` 入力欄で任意の日付を指定してテストできる）
- **失敗の可視化**: エージェント自身が失敗すると `run_daily_news_agent.py` は
  exit code 1 を返しジョブが失敗扱いになる（GitHubのデフォルト通知で気付ける）。
  加えて `SLACK_WEBHOOK_URL` を設定していれば認証エラー・記事0件などの
  ガードレール発火時にSlackへも警告が飛ぶ

**セットアップ手順**（Notion/Slackに実際に送りたい場合）:
1. リポジトリの Settings → Secrets and variables → Actions で以下を登録
   - `NOTION_TOKEN` / `NOTION_DATABASE_ID`
   - `SLACK_WEBHOOK_URL`
   - `AI_NEWS_SOURCE_URL`（省略可。未設定なら同梱のデモ記事を使用）
2. 何も設定しなければ、毎朝dry-run（標準出力に表示するだけ）で動き続ける

---

## ジオメトリーダッシュ風アクション「ほたるメトリーダッシュ」 (games/geometry-dash/)

外部ライブラリなしの HTML5 Canvas 製。`games/geometry-dash/index.html` を
ブラウザで開くだけで遊べる（ビルド不要・ファイルを直接開いてOK）。プレイヤー
キャラクターは飼い犬「ほたる」の顔写真で、キューブ状態でもロケット
（宇宙船）状態でも常にほたるの顔がバッジのように表示される。

```bash
# ローカルで開く
xdg-open games/geometry-dash/index.html    # macOS なら open

# レベルがクリア可能かを検証する（後述）
node games/geometry-dash/verify.mjs
```

### 操作

| 入力 | 動作 |
|---|---|
| `SPACE` / `↑` / `W` / クリック / タップ | ジャンプ（押しっぱなしで連続ジャンプ・オーブ起動・宇宙船の上昇） |
| `P` | 練習モード（自動チェックポイントから復活） |
| `M` | サウンド ON/OFF　　`R` 最初から　　`ESC` 一時停止 |

### ゲーム内容

- 一定速度で右に進み続ける本家と同じルール。ジャンプのみで 408 タイル
  （約45秒）を走り抜ける
- ギミック: トゲ / ブロック / ジャンプパッド / ジャンプオーブ /
  重力反転ポータル / 宇宙船モード
- 死亡すると即リトライ（ATTEMPT カウント）、到達率をプログレスバーと
  `localStorage` のベスト記録で表示
- 背景の色相はステージ進行に合わせて変化し、WebAudio で BPM142 の
  ループとSEをその場で合成している（音源ファイルなし）
- キャラクターの顔写真 (`assets/hotaru.png`) は円形に切り抜いて
  `index.html` に base64 で埋め込み済み。単一ファイルのまま配布・実行できる

### 「絶対にクリアできない配置」を防ぐ検証器

`verify.mjs` は `index.html` の `CORE-BEGIN` 〜 `CORE-END` で囲まれた
**ゲーム本体とまったく同じ物理コード**だけを切り出し、「毎フレーム押す/押さない」
の入力をビームサーチしてゴールに到達できる入力列が存在するかを調べる。

```bash
node games/geometry-dash/verify.mjs            # 120Hz 精度で探索
GRID=6 SHIP=8 BEAM=1500 node games/geometry-dash/verify.mjs   # 入力を20Hz刻みに制限（人間寄り）
```

クリアできない場合は「何タイル付近で詰むか」を出力する。レベルを書き換えたら
これを流せば、理論上クリア不能な配置や、フレーム単位の精度を要求する
理不尽な配置に気付ける。現在のレベルは 20Hz 刻みの入力でもクリア可能
（＝どのジャンプにも 50ms 以上の猶予がある）ことを確認済み。

### 実装メモ

- ロジック（`CORE-BEGIN`〜`CORE-END`）は DOM に一切触らない純粋関数群にして、
  描画・入力・音を外側に分離している。検証器がロジックだけを再利用できるのは
  この分離のおかげ
- 当たり判定は本家同様に甘め: ブロックの側面は上下6px を除いた矩形、
  トゲは見た目の三角形より一回り小さい矩形で判定する
- 物理は固定タイムステップ 1/120 秒で回し、描画フレームレートに依存しない
