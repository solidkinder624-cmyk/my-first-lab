# スカイキャリア (Sky Carrier)

パッドで操作する自由飛行 + 配達ミッションの Roblox マルチプレイ。制限のない
オープンワールドを飛び回る「自由飛行」と、貨物ターミナル間を時間内に運ぶ
「配達ミッション」の2本柱で、配達で稼いだお金が機体購入・アップグレードに
つながる設計になっている ([設計図](../../CLAUDE.md) 参照。元図は
[SKY-DES-001](https://claude.ai/code/artifact/375b06f3-8063-43da-9f9c-45d5a2e2ed42))。

3Dモデル・テクスチャ・音源アセットを一切使わず、`roblox/domino-crash` と同じ方針で
Part と手続き生成だけで機体・ターミナル・山岳/海洋/都市の3つの自由飛行エリアを組んでいる。

## 遊び方 (DualShock4 / Gamepad1、キーボードでも同様に操作可能)

設計図はガンパッド専用だが、コントローラを繋いでいなくても Studio でそのまま
遊べるよう、キーボードでも同じ操作を一通りできるようにしてある
(両方同時に繋いでいても干渉しない)。

| 入力 (ガンパッド) | キーボード | 動作 |
|---|---|---|
| 左スティック | A/D, W/S | ロール(左右) / ピッチ(上下) |
| 右スティック | Q/E | ヨー(左右) |
| R2 / L2 | ↑ / ↓ | スロットル増加 / 減速 |
| × | Space | 加速ブースト (クールダウンあり) |
| ○ | G | 着陸装置トグル |
| □ | F | 荷物投下 / ミッションの受け渡し |
| △ | C | カメラ切替 (チェイス ⇔ コックピット) |
| R1 | E (ProximityPromptのデフォルトキー) | ターミナルでミッション受注 |
| タッチパッド | B | 機体ショップの開閉 |

ガンパッドが無い環境では `UserInputService.GamepadEnabled` が `false` になり、
スティック入力が一切届かないため何をしても機体が反応しない。その場合は上表の
キーボード操作を使うこと。

離陸は滑走路 (中央空港) で R2 を入れ続け、離陸速度に達すると自動的に浮き上がる。
着陸は着陸装置を出した状態で速度を落として接地すること (速すぎる着地や
装置を格納したままの接地は墜落＝中央空港へ強制帰還になる)。

配達は貨物ターミナルに着陸して ProximityPrompt (R1) を押すとそのターミナル発の
ミッションを受注し、目的地ターミナルへ着陸装置を出して着地すると □ で届けられる。
制限時間を余して届けるほどタイムボーナスが乗る。すべてのターミナルに常に
ミッションがあるとは限らない (在庫は `MissionService` がプレイヤーごとに巡回生成する)。

## ワールド

中央空港を起点に、北 (工業地帯) / 東 (港湾) / 南 (農地) の貨物ターミナルへ
配達し、ターミナルの外側には自由飛行のための3エリアが手続き生成されている。

| エリア | 内容 | 生成 |
|---|---|---|
| 山岳 | 高さ70〜420 studsの山を22個、円環状に配置 | `Terrain.mountains` |
| 海洋 | 非衝突の水面 + 島6個。飛行機は水面上を通過するだけで着水は扱わない | `Terrain.islands` |
| 都市 | 高さ24〜220 studsのビル群 (最大46棟)。ジッターを掛けた格子配置 | `Terrain.buildings` |

天候は `Clear` / `Cloudy` / `Storm` を4分ごとに周期切り替え (連続で同じ天候には
ならない)。`Lighting` の霧・明るさ・環境光へ緩やかに反映されるだけの見た目の
演出で、ミッション報酬の天候倍率とは独立している (詳細は既知の割り切り参照)。

## 機体クラス

| 機体 | 特徴 |
|---|---|
| **練習機** (初期所持) | 低速・高安定性。操作を覚えやすい |
| **貨物輸送機** | 最大積載量が大きく速度は控えめ。高額ミッション向け |
| **曲技機** | 旋回速度が高く、狭いルートの配達で時短が可能 |

エンジン・燃料タンク・貨物ベイの3系統をアップグレードでき、稼いだお金は
`PlayerDataService` が DataStore へ保存する。機体購入・乗り換え・アップグレードは
タッチパッドで開く機体ショップ (`Shop.luau`) から行う。

## 動かす

このリポジトリには **ソースだけ** が入っている (`.rbxl` はバイナリなので Git と
相性が悪い)。[Rojo](https://rojo.space/) で Studio に同期する。

```bash
# 1. ツールを入れる (rokit: https://github.com/rojo-rbx/rokit)
rokit install

# 2. 同期サーバを起動
rojo serve roblox/sky-carrier/default.project.json

# 3. Roblox Studio で新規 Baseplate を開き、Rojo プラグインの Connect を押す
#    → ReplicatedStorage / ServerScriptService / StarterPlayerScripts に反映される

# 4. Studio の Test タブ → Players を2以上にして "Start" (マルチプレイの同期を確認)
```

`rojo build roblox/sky-carrier/default.project.json -o SkyCarrier.rbxl` で
`.rbxl` を書き出して直接開くこともできる。DataStore を使う機能 (所持金・
アップグレードの保存) を試すには、Studio の Game Settings で
"Enable Studio Access to API Services" を有効にすること。

## Studio を開かずに検証する

飛行の物理・ミッションの報酬計算・不正対策の判定条件・地形生成・天候の周期
(`FlightModel` / `Mission` / `AntiCheat` / `Terrain` / `Weather`) は
Roblox API を一切参照しない純関数として書いてあり、
[Luau CLI](https://github.com/luau-lang/luau/releases) だけで実行できる。

```bash
cd roblox/sky-carrier && luau verify.luau     # 155 項目
```

検査しているのは、Studio で目視しても気付きにくい種類のことだけ:

| 検査 | なぜ必要か |
|---|---|
| 全速スロットルを続ければ離陸する | 滑走 → 離陸速度到達 → 浮上、の一連が実際に成立するか |
| 低速の空中機は失速する / 高度上限を超えない | 物理モデルが暴走しないか |
| 着陸装置と降下速度の組み合わせで Land / Crash が正しく分かれる | 「丁寧に降りれば着陸、雑に落とせば墜落」がコード上で成立しているか |
| 同じ入力列からは必ず同じ最終状態になる | サーバ権威とクライアント予測が同じ結果に収束する前提が崩れていないか |
| ブースト込みでも速度上限を超えない | 上限速度のクランプが効いているか |
| ミッションの報酬・制限時間が計算式どおり | 距離・積載量・天候倍率のパラメータが実際に効いているか |
| テレポート級の移動・送信フラッドを弾く | 不正対策 (AntiCheat) が実際に効いているか |
| 地形が同じシードから同じ配置で生成される / ゾーン半径の内側に収まる | Studio を開かずに配置ミス (半径外にはみ出す等) を検出できるか |
| 天候が連続で同じにならない / 同じ時刻からは同じ天候になる | 周期の計算式が壊れて「ずっと同じ天候」「毎回ランダム」になっていないか |

`.github/workflows/sky-carrier-verify.yml` が push ごとにこれを実行する。

## 設計

### 権威はサーバ、クライアントは入力送信と予測だけ

`FlightModel.luau` は Roblox API を一切参照しない純関数として書いてあり、
サーバ (`FlightService`) とクライアント (`FlightPredictor`) がまったく同じ
コードを実行する。クライアントは入力の瞬間にローカルで1歩進めて見た目を
遅延なく追従させ (予測)、サーバから届く自分ぶんのスナップショットと
`RECONCILE_DISTANCE` (12 studs) 以上ズレたときだけ静かに位置を合わせる。

改造クライアントが `FlightModel` を書き換えても、実際にどこへ着地できたかを
決めるのはサーバの `FlightService` / `MissionService` であり、見た目が
先読みできるだけで判定は変わらない。

### 不正対策: 「物理的に不可能な移動」を距離と時間から弾く

`AntiCheat.luau` は打撃のクールダウンではなく移動そのものを検査する。
直近の正規位置・時刻を1組だけ持ち、次に届いた申告が

```
移動距離 > 最高速度 * speedTolerance * min(dt, maxStepDelta) + graceDistance
```

を超えたらテレポート・速度ハックとして却下し、直前の正規状態へ巻き戻す
(`FlightService:applyInput` 参照)。`speedTolerance` と `graceDistance` は
ブースト直後の一瞬の加速やレイテンシのぶんだけ緩めてあり、厳しすぎて
回線の悪いプレイヤーの正当な移動を消さないようにしてある。

### ミッションは座標だけで判定する

配達の成否をクライアントの自己申告 (「着いた」ボタン) だけで信じると、
届いていない場所からでも □ を押すだけで報酬が発生してしまう。
`MissionService:deliver` はサーバが持っている `FlightService` の位置を
直接見て `Mission.isValidDropoff` (着陸装置展開 + 接地 + 目的地から
`dropRadius` 以内) を満たすかどうかだけで判定し、クライアントの入力は
「今すぐ判定してほしい」という合図でしかない。

### 決定的なミッション生成

`Mission.generate(seed, index, ...)` は `domino-crash/Blueprint.luau` と同じ
自前の 32bit LCG を使っており、同じ `(seed, index)` からは必ず同じ
出発地・目的地・積載量・天候倍率が出る。Roblox の `Random` を使わないのは
Luau CLI からも同じ数列を再現するため (`verify.luau` の決定性検査)。

### 地形も天候も「配置だけ」を純関数が決める

`Terrain.luau` は `Mission.luau` / `domino-crash/Blueprint.luau` と同じ自前の
32bit LCG を使い、ゾーンの種類とシードから山・島・ビルの座標とサイズだけを
返す。実際に Part を生成する `TerrainBuilder.luau` は Roblox 依存の薄い層で、
Studio を開かなくても `verify.luau` が「同じシードから同じ配置になるか」
「全部ゾーン半径の内側に収まっているか」「最高点が高度上限を超えないか」を
検証できる。

天候も同じ考え方で、`Weather.at(serverSeconds, cfg)` は今が何周期目かを
`serverSeconds` から計算し、直前の天候を除外した候補から決定的に1つ選ぶ
(連続で同じ天候にならない)。サーバは変化があったときだけ `WeatherUpdate` を
送り、クライアント (`WeatherController`) は `Lighting` の値を6秒かけて
なめらかに補間する。

### 演出はサーバを介さない

サーバが送るのは位置・向き・燃料・接地状態などの数値だけ (`BroadcastFlightState`)。
粉塵やヒットストップに相当する演出はこのゲームには薄いが、方針は
`domino-crash` と同じで、見た目に関わる計算は極力クライアントローカルに置く。
他プレイヤーの機体は `RemotePlayers.luau` が約12Hzの更新を毎フレーム
指数補間して表示し、カクつきを隠す。

## 既知の割り切り

* **フラップ (L1/R1) は未実装。** 設計図の入力表には残してあるが、旋回性能や
  揚力への影響は今回のMVPでは配線していない。`InputController` はボタンの
  取得自体はしていないので、追加するときは `ButtonL1`/`ButtonR1` の状態を
  流し込むだけで済む。
* **ミニマップは未実装。** 設計図ではタッチパッドをミニマップ切替に割り当てて
  いたが、経済まわり (機体ショップ) を優先したためタッチパッドは
  `Shop.luau` の開閉に使っている。`Mission.Terminal` 一覧はサーバが既に
  持っているので、ミニマップ自体は表示だけを追加すれば良い。
* **提示ミッションはターミナルごとに絞り込まない生成。** `MissionService`
  はプレイヤーごとに出発地をランダムに含む提示を巡回生成するので、
  今いるターミナルに受注できるミッションが無いこともある
  (`no_offer_here`)。これは意図的な仕様で、常にどのターミナルでも
  受注できるようにしたい場合は `MissionService:refreshOffersFor` で
  ターミナルごとに最低1件を保証するよう変更する。
* **ミッションの天候倍率と、見た目の天候は連動していない。**
  `Config.mission.weatherMultiplierRange` はミッションごとに独立した
  ランダム値で「その配達ルートの天候」を表し、ワールド全体の見た目を
  変える `Weather.luau` の周期とは別物。連動させる場合は
  `MissionService:refreshOffersFor` が `WeatherService:current_()` を
  参照して倍率を決めるように変更する。
* **雲・雨・雷などの粒子演出は無い。** `WeatherController` は `Lighting`
  の霧・明るさ・環境光を補間するだけの下地で、Storm でも実際に雨は
  降らない。
* **音は鳴らない。** `domino-crash` と同じく外部アセット0本の方針のため。
  `Config.sound` に `rbxassetid://` を入れれば `SoundController` が
  ブースト・着陸・墜落・配達成功時に鳴らす (未設定分は無音のまま)。
* **海は着水判定を持たない。** `Ocean` ゾーンの水面パーツは非衝突。
  水没・浮力などの表現は今回のスコープ外。

## ファイル

```
src/shared/     Roblox API 非依存の純ロジック (verify.luau が直接 require する)
  Config        全チューニング値。サーバ・クライアント・検証器が同じ値を共有
  FlightModel   飛行の物理モデル (姿勢・推力・重力・失速・燃料・離着陸判定)
  Mission       配達ミッションの生成・報酬計算・成否判定
  AntiCheat     移動申告の受理条件 (テレポート・フラッド対策)
  Terrain       自由飛行エリア (山岳・海洋・都市) の地形配置の手続き生成
  Weather       天候の決定的な周期切り替え
  Net           リモートの定義 (ここだけ Roblox 依存)

src/server/
  init.server        配線 (ProfileUpdate / WeatherUpdate の送信もここでまとめて行う)
  FlightService      位置の権威。FlightModel を実行し、AntiCheat で検査してから確定
  MissionService      ミッションの提示・受注・配達判定
  PlayerDataService   所持金・所有機体・アップグレードの DataStore 永続化
  WorldBuilder        中央空港・貨物ターミナル3か所を Part + ProximityPrompt で組む
  TerrainBuilder       Terrain.luau の配置から山・島・ビルの Part を生成
  WeatherService       Weather.luau を実行し、変化があったときだけ全員へ配信

src/client/
  init.client       配線
  InputController   ガンパッド入力の取得・送信 (約20Hz)
  FlightPredictor    自機だけローカルで FlightModel を実行する予測 + リコンサイル
  AircraftRig        機体の見た目 (胴体・主翼・尾翼を Part だけで組む)
  RemotePlayers       他プレイヤーの機体をブロードキャストから補間表示
  CameraController    チェイス / コックピット視点
  MissionController    ミッションの受注・配達申告
  TerminalController   ターミナルの ProximityPrompt を MissionController につなぐ
  Shop                 機体購入・乗り換え・アップグレードUI (タッチパッドで開閉)
  WeatherController     Lighting (霧・明るさ・環境光) への反映
  SoundController       Config.sound の rbxassetid を鳴らす (未設定なら無音)
  Hud                 高度計・速度計・所持金・ミッションバー
```
