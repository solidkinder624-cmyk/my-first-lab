# Dino Catchers: Rise & Raise — 制作バイブル（全員必読）

このファイルはプロデューサー（claude.ai側のClaude）が管理する「正」の仕様書。
Claude Code本体は【現場リーダー】として、下記の部下（サブエージェント）に作業を振り分け、
自分では実装しない。仕様に書かれていない判断が必要になったら、作業を止めて
「プロデューサー確認事項」として報告すること。

## 1. ゲーム概要
- ジャンル：恐竜の探索・捕獲（テイム）・育成。三人称視点。
- コアループ：探索 → 恐竜を発見 → テイム銃で捕獲 → 拠点で育成・レベルアップ → 次の探索へ
- プレイ形式：各プレイヤーが自分の拠点を持つ。他人の拠点への訪問はフェーズ3以降。
- 恐竜モデル：当面は仮モデル（ブロック組み）。後で本番モデルに差し替える前提で作る。

## 2. フェーズ1（MVP＝最小限遊べる版）の範囲
含む：
- 草原・平原バイオームの拠点（Terrain中心の自然地形）
- 野生恐竜1〜2種がうろつく
- テイム銃で狙い続けるとテイム進捗が溜まり、100%で捕獲
- 捕獲した恐竜が拠点を自由に歩く
- HUD：プレイヤー情報（名前・Lv・所持金）、テイムリスト、テイム進捗バー
- セーブ／ロード（所持恐竜・Lv・所持金）
含まない（後回し）：クエストログ、群れの一括テイム、建築ハンマー、卵の孵化、笛、他人の拠点訪問、火山など他バイオーム

## 3. 決定事項と未決事項
- [決定A] 拠点は柵あり（参考画像どおり）。飼育恐竜は柵の内側を自由に歩き回る。
  柵は後で広げられるよう、同じ部品（区画）を並べる作りにする。
- [決定B] 所持上限は最初10頭、拠点の成長で上限アップ。
  → 上限はプレイヤーごとの保存データ（MaxOwnedDinos、初期値 DinoConfig.BaseMaxOwnedDinos = 10）で持つ。
     数値の直書き禁止。フェーズ1では上限アップの仕組み自体は作らないが、値を変えれば即反映される作りにする。
- [未決C] 「拠点の成長」の方法（お金で拡張？レベル到達？柵エリアの拡張と連動？）
  → 決まるまで実装しない。

## 4. 担当フォルダ（他人の担当場所は編集禁止。必要なら依頼として報告）
| 担当 | 触ってよい場所 |
|---|---|
| world-builder | Workspace.Terrain / Workspace.Ranch / Lighting |
| data-architect | ReplicatedStorage.Shared / ReplicatedStorage.Remotes / ServerScriptService.Data |
| dino-ai | ServerScriptService.DinoAI / ServerStorage.DinoModels / Workspace.Dinos |
| capture-system | ServerScriptService.Capture / StarterPack.TamingGun |
| ui-designer | StarterGui / StarterPlayer.StarterPlayerScripts.UI |
| qa-reviewer | 読み取りのみ（修正は各担当へ差し戻し） |

## 5. 共通ルール
- 数値・種類などの設定値は ReplicatedStorage.Shared.DinoConfig（ModuleScript）1か所だけに書く。
- サーバーとクライアントの通信は ReplicatedStorage.Remotes 内の RemoteEvent / RemoteFunction のみ。
  名前は「動詞+対象」（例：RequestTame, TameProgressChanged, DinoAdded）。追加は data-architect に依頼。
- サーバー権威：捕獲成功・所持金・Lvの決定は必ずサーバー側。クライアントから来た値は信用せず検証する。
- 性能：拠点に恐竜30頭が同時にいても重くならない作りにする（移動はサーバー、見た目の演出はクライアント）。
- UIの色：赤と緑の対比だけで状態を区別しない。色＋文字・アイコン・形で区別する。
- 無料モデル（Toolbox）の挿入は禁止。どうしても必要なら候補を報告して許可を待つ。
- 本番のDataStoreキーを消す・上書きする操作は禁止。テストは Studio 上の別キー名で行う。

## 6. 作業報告フォーマット（各担当は作業の最後に必ずこの形で出力）
```
【担当】
【やったこと】（3行以内）
【作成・変更したもの】（Explorer上のパス）
【他担当への依頼】（なければ「なし」）
【プロデューサー確認事項】（なければ「なし」）
【テスト方法】（Studioで何をすれば確認できるか）
```
