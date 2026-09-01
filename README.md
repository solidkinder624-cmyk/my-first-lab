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

- `AI_NEWS_SOURCE_URL` — ニュース取得元。**RSSフィード**(標準ライブラリのみで解析、APIキー不要)
  または `{"title","url","published_at"}` のリストを返すJSONエンドポイントのどちらかを
  自動判別。カンマ区切りで複数指定すると全ソースをまとめて取得する。未設定時は同梱のデモ記事を使用。
  例:
  ```
  AI_NEWS_SOURCE_URL=https://techcrunch.com/category/artificial-intelligence/feed/,https://venturebeat.com/category/ai/feed/
  ```
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

## ジオメトリーダッシュ風アクション "NEON RUSH" (games/geometry-dash/)

外部ライブラリなしの HTML5 Canvas 製。`games/geometry-dash/index.html` を
ブラウザで開くだけで遊べる（ビルド不要・ファイルを直接開いてOK）。

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

---

## 痕跡だけの迷路 "Trace Only" (roblox/trace-only/)

Roblox のマルチプレイ。プレイヤーの姿は描画されず、床に残る**足跡**と
ジャンプ・着地の**振動波紋**だけを頼りに相手の位置を推測する。
3Dモデル・テクスチャ・音源アセットを一切使わず、Part と手続き生成の迷路だけで成立する。

```bash
rokit install                                          # rojo/stylua/selene を導入
rojo serve roblox/trace-only/default.project.json      # Studio の Rojo プラグインから Connect
luau roblox/trace-only/verify.luau                     # Studio 無しでロジックを検証 (31項目)
```

- **しゃがみ**は足跡が出ないが速度は半分以下、**ダッシュ**は速いが痕跡が濃く遠くまで届く、
  というリスク/リターンが中心のルール
- モードは「かくれんぼ / 宝探し / 鬼ごっこ(感染式)」を自動で切り替え

### 「透明にする」ではなく「そもそも送らない」

Roblox は Workspace の中身を全クライアントへレプリケートするので、キャラクターを
透明にしただけでは改造クライアントから座標が読める。そこで
`Players.CharacterAutoLoads = false` にしてキャラクターモデルを作らず、位置はサーバの
メモリ上のデータとしてだけ持ち、外へ出すのは痕跡パケット (種類と座標のみ・誰のものかは
送らない) だけにしている。可聴半径の外へは送信すらしないため、情報の非対称性が
ネットワーク層で保証される。

### Studio を開かずに回るテスト

ロジックの中核 (`Config` / `Grid` / `Motion`) は Roblox API 非依存の純関数として書いてあり、
サーバ・クライアント予測・検証器の三者がまったく同じコードを実行する。`verify.luau` は
迷路が必ず連結であること、速度400 studs/s でも壁をすり抜けないこと、しゃがみが本当に
無音であること、巨大な `dt` を送っても1tick分しか進めないことなどを検査し、
`.github/workflows/trace-only-verify.yml` が push ごとに実行する。

詳細は `roblox/trace-only/README.md`。

---

## 「全パーツ一斉爆破」ドミノ・クラッシュ PvP (roblox/domino-crash/)

Roblox のマルチプレイ。千数百個のブロックで組まれた建造物の**弱点を見極めて叩き、
連鎖崩壊させる速さ**を競う。全員が同じ構造物を1つずつ持ち、先に100%崩し切った方が勝つ
（1試合最長60秒）。3Dモデル・テクスチャ・音源アセットは一切使わず、
Part と手続き生成だけで成立させている。

```bash
rokit install                                            # rojo/stylua/selene を導入
rojo serve roblox/domino-crash/default.project.json      # Studio の Rojo プラグインから Connect
cd roblox/domino-crash && luau verify.luau               # Studio 無しでロジックを検証 (117項目)
```

- 構造物は 塔 / 要塞 / 水道橋 の3種類をラウンドごとに巡回（約1000〜2200ブロック）
- **壁を叩いても崩れない。柱を折って初めて崩れる** というルールが中心

### 「崩れる範囲」を物理エンジンに決めさせない

半径 R のパーツの `Anchored` を外すだけだと、宙に浮いた壁がその場に残る絵になって
ドミノ崩しにならない。そこで荷重の伝わり方を `Collapse.luau` が明示的に持っている
（真上に乗る = コスト0、横に繋がる = コスト+1、地面が起点）。打撃のたびに接地ブロックから
0-1 BFS で荷重経路を引き直し、到達できなくなったブロックをまとめて崩す。柱を1本折ると
上のフロアが張り出し限界を超えて落ち、その上がまた支えを失う——「一斉爆破」はこの
再計算の副産物として出てくる。

壁だけを「上を支えられない詰め物」にしてあるので、同じ高さでも柱を狙うと詰め物の
10〜30倍崩れる。弱点の見極めが実際のリターンになっている。

### 数千個の剛体を捌く

1フレームあたりのアンカー解除数に予算を設けて打撃点から近い順に外す（崩壊が波紋状に
広がる副作用つき）、同時に動く破片が400個を超えたら以降は当たり判定を切る、落ちきった
破片は即消去、Part は1組だけ作って人数ぶん `Clone`、次ラウンドぶんは結果表示中に先読み、
破片の物理演算の所有権は持ち主のクライアントへ——といった対策を積んである。
崩壊率は毎フレーム走査せず、サーバが既に持っている3つの数から計算して0.2秒ごとに一括送信する。

### Studio を開かずに回るテスト

ロジックの中核（`Config` / `Blueprint` / `Collapse` / `Progress` / `HitRules`）は
Roblox API 非依存の純関数で、`verify.luau` が
「生成直後に1個も落ちないか」「柱を叩くと詰め物の3倍以上崩れるか」
「地上から届く打撃だけで100%まで壊し切れるか」「リーチ改造と連打マクロを弾けるか」
など117項目を検査する。`.github/workflows/domino-crash-verify.yml` が push ごとに実行する。

詳細は `roblox/domino-crash/README.md`。

---

## GRAZE & GRACE ― スワイプ弾幕壁 ＆ 回避シールド プロトタイプ (games/graze-and-grace/)

企画書 (`games/graze-and-grace/GAME_DESIGN.md`) の Phase 1「弾幕エンジンの基礎構築」と
Phase 2「回避側（勇者）のプロトタイプ実装」に対応するプロトタイプ。外部ライブラリなしの
HTML5 Canvas 製。`games/graze-and-grace/index.html` をブラウザで開くだけで遊べる
（ビルド不要）。

```bash
# ローカルで開く
xdg-open games/graze-and-grace/index.html    # macOS なら open

# 弾幕の壁 生成ロジック / シールドシステムだけを Node で検証する
node games/graze-and-grace/verify.mjs
```

### 操作

| 入力 | 動作 |
|---|---|
| 画面上をスワイプ（マウスドラッグ／タッチ） | その軌跡に沿って一定間隔の弾を並べ、「弾幕の壁」を生成する |
| `WASD` / 矢印キー | ヒーロー（勇者役のテスト用の水色の点）を動かし、壁の隙間（安置）を回避する |
| `Space` / 発動ボタン | シールドゲージがMAXのとき、無敵「イージス」を発動する（1プレイ5回まで） |

スワイプで壁を描くと、少し予告（テレグラフ）してから、スワイプの向きに対して
画面中央側へ直交する方向へ壁全体が一斉に飛び出す。HUD にはカスリ数・被弾数・
直近の壁の「規則性」（企画書 2.1 の Grace/規則性の最小限の下敷き）を表示する。
弾をカスるたびにシールドゲージが少しずつ溜まり、MAXになると `Space` で一定時間
（1.5秒）の無敵状態を発動できる。発動回数は企画書 3.1 のとおり1プレイにつき5回まで
で、使い切るとゲージがMAXでも発動できなくなる。

### 実装メモ

- ロジック（`core.js`）は DOM に一切触らない純関数群で、`resamplePathEven`
  （スワイプの点列を弧長ベースで等間隔にリサンプルする）と `buildBulletWall`
  （リサンプル結果から弾のリストと押し出し方向を作る）、および
  `createShieldState` / `chargeShield` / `activateShield` / `isShieldActive`
  （5回制限シールドの状態遷移、すべてイミュータブル）が中心。`index.html`
  からは `<script>` タグで、`verify.mjs` からは Node の `require` で
  同じファイルをそのまま読み込む。
- 押し出し方向はスワイプ全体の向きに直交する2方向のうち、画面中央に近づく側を
  自動選択する（壁が常に勇者側へ迫ってくるように）。
- 各弾は「スワイプした順に少し遅れて出現」→「一定時間の予告で静止」→
  「直進」の3段階を持ち、`advanceBullet` が経過時間から現在の状態を都度計算する
  （フレームレート非依存）。
- シールドは `usesLeft` と `charge`（0〜1）を持つだけの小さな状態機械。
  `activateShield` は発動条件（ゲージMAX かつ残り回数1以上）を満たさない場合、
  渡された state をそのまま返す（呼び出し側で事前チェック不要）。
- 当初 React での実装を想定していたが、このサンドボックス環境では CDN
  (unpkg/cdnjs/jsdelivr) への外向き通信がネットワークポリシーでブロックされており
  動作確認ができなかったため、本リポジトリの既存ゲーム（geometry-dash等）と同じ
  「外部ライブラリなし・ファイルを直接開くだけ」方針で実装した。`core.js` は
  フレームワーク非依存の純関数なので、React/Unity/Godot 等へ載せ替える場合も
  ロジックはそのまま流用できる。
