# 痕跡だけの迷路 (Trace Only)

姿が見えないプレイヤー同士が、**床に残る足跡と振動波紋だけ**を頼りに探り合う
Roblox のマルチプレイ。3Dモデル・テクスチャ・音源アセットを一切使わず、
Part と既定パーティクル、そして手続き生成の迷路だけで成立させている。

```
歩く   → 足跡が残る (数秒でフェード)          … 位置がバレる
ダッシュ → 足跡が濃く・頻繁・遠くまで届く       … 速いが目立つ
しゃがみ → 足跡が出ない / 移動速度は半分以下     … 安全だが遅い
ジャンプ・着地 → 広範囲に一瞬の波紋            … 壁越しでも気配が伝わる
```

## 遊び方 (操作)

| 入力 | 動作 |
|---|---|
| `W` `A` `S` `D` | 移動 |
| `Shift` | ダッシュ (スタミナ消費・痕跡が強くなる) |
| `Ctrl` / `C` | しゃがみ (無音・低速・スタミナ回復が速い) |
| `Space` | ジャンプ (踏み切りと着地の2回、波紋が出る) |
| マウス | 視点 |

モードは自動で順番に切り替わる。

| モード | 内容 |
|---|---|
| かくれんぼ | 鬼1人が痕跡を追う。隠れ手は制限時間まで逃げ切る |
| 宝探し | 迷路の宝を集める。**拾うとマップ全体に波紋が出る**ので、取るほど狙われる |
| 鬼ごっこ | 感染式。捕まると鬼になる。鬼は2.5秒ごとに気配が漏れる (逃げ手への救済) |

## 動かす

このリポジトリには **ソースだけ** が入っている (`.rbxl` はバイナリなので Git と相性が悪い)。
[Rojo](https://rojo.space/) で Studio に同期する。

```bash
# 1. ツールを入れる (rokit: https://github.com/rojo-rbx/rokit)
rokit install

# 2. 同期サーバを起動
rojo serve roblox/trace-only/default.project.json

# 3. Roblox Studio で新規 Baseplate を開き、Rojo プラグインの Connect を押す
#    → ReplicatedStorage / ServerScriptService / StarterPlayerScripts に反映される

# 4. Studio の Test タブ → Players を2以上にして "Start" (ローカルサーバでマルチ検証)
```

`rojo build roblox/trace-only/default.project.json -o TraceOnly.rbxl` で
`.rbxl` を書き出して直接開くこともできる。

## Studio を開かずに検証する

ゲームロジックの中核 (`Config` / `Grid` / `Motion`) は Roblox API を一切
参照しない純関数として書いてあり、[Luau CLI](https://github.com/luau-lang/luau/releases)
だけで実行できる。`games/geometry-dash/verify.mjs` と同じ考え方。

```bash
luau roblox/trace-only/verify.luau
```

現在 31 項目を検証している。主なもの:

- **迷路**: 全タイルが必ず連結 (到達不能な部屋ができない) / 外周に穴が開かない /
  同じ seed なら全マシンで同一 (クライアント予測が成立する前提) /
  壁のマージ結果が元の壁集合と完全一致する
- **移動**: ランダム入力25本×20秒で壁にめり込まない / 速度400 studs/s でもすり抜けない /
  同一入力なら軌跡が完全一致 (決定論)
- **ゲーム性のルール**: しゃがみは足跡ゼロ / しゃがみは歩きより遅い /
  ダッシュは歩きより痕跡が多く遠い / 着地は踏み切りより広く伝わる /
  しゃがんで距離を貯めてから立っても足跡がまとめて出ない
- **チート対策**: 長さ>1 の移動ベクトルは丸められる / NaN・非テーブル入力で落ちない /
  巨大な dt を送っても1tick分しか進めない

`.github/workflows/trace-only-verify.yml` が push のたびにこれを回す。

## 構造

```
src/shared/    サーバとクライアントが共有する層
  Config.luau    全チューニング値 (純データ)
  Grid.luau      迷路生成・当たり判定・経路 (純関数)
  Motion.luau    移動シミュレーションと痕跡の発生 (純関数・ゲームの権威ロジック)
  Net.luau       リモート定義
src/server/
  init.server.luau     エントリポイント
  MapBuilder.luau      Grid から Part を組む / 暗闇と霧の設定
  PlayerRegistry.luau  プレイヤー状態
  SimulationService.luau  固定30Hzの権威シミュレーション
  TraceService.luau    痕跡の可聴半径フィルタと配信
  RoundService.luau    ラウンド進行・スポーン配置
  Modes/               かくれんぼ / 宝探し / 鬼ごっこ
src/client/
  init.client.luau     エントリポイント
  Predictor.luau       Motion を使った移動予測とリコンサイル
  InputController.luau 入力収集 (送るのは方向であって座標ではない)
  CameraController.luau 一人称カメラ (キャラモデルが無いのでカメラが体)
  TraceRenderer.luau   足跡と波紋の描画
  Hud.luau             HUD
```

### 「本当に見えない」ための設計

透明な `Part` を置く実装では、キャラクターモデルが Workspace にある以上
**全クライアントへ座標がレプリケートされる**。透明度はクライアント側の見た目にすぎず、
改造クライアントからは丸見えになる。

そこでこのプロジェクトは `Players.CharacterAutoLoads = false` にして、
**キャラクターモデルを一切生成しない**。

```
クライアント                     サーバ
  入力 (方向/ボタン)  ──────────▶  Motion.step で権威シミュレーション
                                   │
  自分の権威座標      ◀────────────┤ 本人にだけ 10Hz で返す
  痕跡 (種類/座標)    ◀────────────┘ 可聴半径内のプレイヤーにだけ送る
```

他プレイヤーについてネットワークに流れるのは痕跡パケットだけで、**誰の痕跡かも送らない**。
可聴半径の外の情報はそもそも送信されないため、クライアントを改造しても
「聞こえない足音」は聞けない。情報の非対称性がネットワーク層で保証されている。

操作の遅延は、クライアントがサーバと同一の `Motion.luau` を実行する予測で消している
(`Predictor.luau`)。両者の結果が一致することは verify.luau の決定論テストで担保している。

### チート対策として効いている点

| 手口 | 対策 |
|---|---|
| 他人の座標を読む | そもそも送っていない (キャラクターモデルが存在しない) |
| 移動ベクトルを巨大にする | `Motion.sanitize` が長さ1に丸める |
| 巨大な dt を申告する | dt はサーバが決める。`maxStepDelta` で頭打ち |
| 入力を大量に送って加速する | 1tickで消化する入力は `maxCatchUpPerTick` 個まで、バッファは8個まで |
| 壁抜け | 当たり判定はサーバ側の `Grid.resolve`。クライアントの位置申告は一切受けない |

## チューニング

ゲームバランスはすべて `src/shared/Config.luau` に集約してある。
`trace.Step.distance` (足跡の間隔)、`trace.*.radius` (可聴半径)、
`move.crouchSpeed` (しゃがみ速度) あたりが体感を大きく変える。
値を変えたら `luau roblox/trace-only/verify.luau` を流せば、
「しゃがみが歩きより速くなっている」等の壊れた設定に気付ける。

## ここから先の伸びしろ

- 波紋を円盤ではなくリング状のメッシュにする (現在は Neon の円盤で代用)
- 足跡・波紋の Part をプール化する (現在は `Debris` 任せ。多人数だと生成コストが乗る)
- 痕跡に**方向の曖昧さ**を足す (遠いほど座標に誤差を乗せる) と、索敵の駆け引きが深くなる
- モバイル操作 (現状はキーボード+マウス前提)
- 効果音。`SoundService` で波紋に合わせた低音を鳴らすと体感がかなり変わる (要アセットID)
- `DataStore` での戦績保存、ゲームパスによる痕跡カラーの販売
