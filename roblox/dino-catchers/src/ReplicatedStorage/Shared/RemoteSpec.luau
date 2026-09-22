-- 通信（ReplicatedStorage.Remotes）の一覧と使い方。
--
-- 実体（RemoteEvent / RemoteFunction）は Rojo が
-- src/ReplicatedStorage/Remotes/<名前>.model.json から作る。スクリプトで Instance.new はしない。
-- 新しい Remote が必要なら data-architect に依頼する（ここと .model.json の両方を足す）。
--
-- 取り出し方（サーバー・クライアント共通）:
--   local RemoteSpec = require(ReplicatedStorage.Shared.RemoteSpec)
--   local requestTame = RemoteSpec.get("RequestTame")   -- 名前の打ち間違いはここでエラーになる
--
-- ┌──────────────────────┬────────────────┬──────┬───────────────────────────────────────────┐
-- │ 名前                  │ 種類            │ 向き  │ 引数 / 戻り値                                │
-- ├──────────────────────┼────────────────┼──────┼───────────────────────────────────────────┤
-- │ RequestTame           │ RemoteEvent    │ C→S  │ (dinoId: string?)                           │
-- │ TameProgressChanged   │ RemoteEvent    │ S→C  │ (dinoId, progress, state, reason?)          │
-- │ DinoAdded             │ RemoteEvent    │ S→C  │ (dino: OwnedDino)                           │
-- │ DinoRemoved           │ RemoteEvent    │ S→C  │ (dinoId: string)                            │
-- │ DinoUpdated           │ RemoteEvent    │ S→C  │ (dino: OwnedDino)                           │
-- │ ProfileChanged        │ RemoteEvent    │ S→C  │ (profile: ProfileView)                      │
-- │ NotifyPlayer          │ RemoteEvent    │ S→C  │ (kind: string, text: string)                │
-- │ RequestInitialData    │ RemoteFunction │ C→S→C│ () → InitialData                            │
-- └──────────────────────┴────────────────┴──────┴───────────────────────────────────────────┘
--
-- ■ RequestTame（C→S）… 担当: capture-system（送信: TamingGun / 受信: Capture）
--   テイム銃で野生恐竜を「狙っている間」、DinoConfig.Taming.ClientReportInterval ごとに送る。
--   dinoId = 狙っている野生恐竜の個体ID（Workspace.Dinos 内モデルの属性 "DinoId" を想定）。
--   狙いを外した・銃をしまったときは nil を1回送る（送らなくても DecayDelay 後に減衰が始まる）。
--   サーバーは値を信用しない: 間隔(MinRequestInterval)・距離(TameRange + RangeTolerance、
--   上限 MaxServerRange)・射線・対象が野生か・所持上限(MaxOwnedDinos) をすべてサーバーで確認する。
--   位置や進捗などの数値はクライアントから送らない（サーバーがキャラ位置から計算する）。
--
-- ■ TameProgressChanged（S→C）… 送信: Capture / 受信: UI（進捗バー）
--   テイム中のプレイヤー本人にだけ送る。
--   dinoId: string / progress: number（0〜DinoConfig.Taming.ProgressMax）
--   state: TameState（下記） / reason: string?（state が "Cancelled" / "Blocked" のときの理由）
--     "Taming"    … 狙えていて進捗が増えている
--     "Decaying"  … 狙いが外れて減衰中
--     "Captured"  … 100% になり捕獲成功（この後 DinoAdded が届く）
--     "Cancelled" … 進捗 0 に戻った / 対象が消えた（reason 例: "Lost", "Despawned"）
--     "Blocked"   … テイムできない（reason 例: "OwnedLimit"=所持上限, "OutOfRange"=射程外）
--
-- ■ DinoAdded（S→C）… 送信: Data（PlayerData.addDino の中で自動）/ 受信: UI（テイムリスト）
--   所持恐竜が1頭増えたとき本人に送る。dino は OwnedDino（下記）。
--
-- ■ DinoRemoved（S→C）… 送信: Data（PlayerData.removeDino の中で自動）/ 受信: UI
--   所持恐竜が1頭減ったとき本人に送る（フェーズ1には手放す機能がないので基本は届かない）。
--
-- ■ DinoUpdated（S→C）… 送信: Data（PlayerData.setDinoLevel などの中で自動）/ 受信: UI
--   所持恐竜1頭の中身（Lv など）が変わったとき本人に送る。dino.Id で一覧の該当行を差し替える。
--
-- ■ ProfileChanged（S→C）… 送信: Data（所持金・Lv・上限・頭数が変わるたび自動）/ 受信: UI（HUD）
--   profile は ProfileView（下記）。毎回すべての項目が入った最新の状態を送る（差分ではない）。
--
-- ■ NotifyPlayer（S→C）… 送信: どのサーバースクリプトでも / 受信: UI（トースト表示など）
--   kind: "Info" / "Success" / "Warning" / "Error"（色だけでなくアイコン・文字でも区別すること）
--   text: 表示する文章（日本語）
--
-- ■ RequestInitialData（RemoteFunction, C→S→C）… 受信: Data / 呼び出し: UI（起動時に1回）
--   引数なし。戻り値は InitialData（下記）。ロード完了を最大 Save.InitialDataWaitTimeout 秒待つ。
--   Loaded = false が返ったら少し待って再度呼ぶ。以降の変化は上の S→C イベントで受け取る。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DinoConfig = require(script.Parent:WaitForChild("DinoConfig"))

-- ── 送受信するデータの形 ────────────────────────────────
export type TameState = "Taming" | "Decaying" | "Captured" | "Cancelled" | "Blocked"

-- 所持恐竜1頭（セーブデータにもこの形で入る）
export type OwnedDino = {
	Id: string, -- 個体ID（GUID）。所持恐竜の間で一意
	Species: string, -- DinoConfig.Species のキー
	Level: number,
	CapturedAt: number, -- 捕獲した時刻（os.time()、UTC秒）
}

-- HUD 用のプレイヤー情報（名前は Player.DisplayName をクライアントで使う）
export type ProfileView = {
	Level: number,
	Money: number,
	MaxOwnedDinos: number, -- 所持上限（プレイヤーごと）
	OwnedCount: number, -- 今の所持数
}

export type InitialData = {
	Loaded: boolean, -- false ならまだロード中（Profile / Dinos は入っていない）
	Profile: ProfileView?,
	Dinos: { OwnedDino }?, -- 捕獲順
}

-- ── 定義 ─────────────────────────────────────────────
local RemoteSpec = {}

RemoteSpec.Definitions = {
	RequestTame = { ClassName = "RemoteEvent", Direction = "C2S" },
	TameProgressChanged = { ClassName = "RemoteEvent", Direction = "S2C" },
	DinoAdded = { ClassName = "RemoteEvent", Direction = "S2C" },
	DinoRemoved = { ClassName = "RemoteEvent", Direction = "S2C" },
	DinoUpdated = { ClassName = "RemoteEvent", Direction = "S2C" },
	ProfileChanged = { ClassName = "RemoteEvent", Direction = "S2C" },
	NotifyPlayer = { ClassName = "RemoteEvent", Direction = "S2C" },
	RequestInitialData = { ClassName = "RemoteFunction", Direction = "C2S2C" },
}

RemoteSpec.TameStates = {
	Taming = "Taming",
	Decaying = "Decaying",
	Captured = "Captured",
	Cancelled = "Cancelled",
	Blocked = "Blocked",
}

RemoteSpec.NoticeKinds = {
	Info = "Info",
	Success = "Success",
	Warning = "Warning",
	Error = "Error",
}

local WAIT_TIMEOUT = DinoConfig.Net.RemoteWaitTimeout

-- 名前から Remote を取り出す。一覧にない名前はエラーにして打ち間違いに早く気づけるようにする。
function RemoteSpec.get(name: string): Instance
	local def = RemoteSpec.Definitions[name]
	assert(def, "RemoteSpec: 未定義の Remote です: " .. tostring(name))
	local folder = ReplicatedStorage:WaitForChild("Remotes", WAIT_TIMEOUT)
	assert(folder, "RemoteSpec: ReplicatedStorage.Remotes が見つかりません")
	local remote = folder:WaitForChild(name, WAIT_TIMEOUT)
	assert(remote, "RemoteSpec: Remote が見つかりません: " .. name)
	assert(remote:IsA(def.ClassName), "RemoteSpec: " .. name .. " は " .. def.ClassName .. " のはずです")
	return remote
end

return RemoteSpec
