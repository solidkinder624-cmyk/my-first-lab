-- リモートの定義を1か所に集約する。サーバが生成し、クライアントは待つだけ。
--
-- 流れるものは4種類:
--   RequestHit         C→S  ハンマー打撃リクエスト (叩いた Part と着弾点)
--   OnStructureExplode S→C  崩壊イベントの通知。演出はこれを受けて各自が生成する
--   MatchStateChanged  S→C  フェーズ遷移 (待機/カウントダウン/破壊/結果)
--   ProgressSync       S→C  0.2秒ごとの全員ぶんの崩壊率
--
-- ProgressSync だけ UnreliableRemoteEvent なのは、0.2秒ごとに上書きされる
-- 「最新の値だけが意味を持つ」データだから。1発落ちても次で追いつく。
-- 逆に MatchStateChanged と OnStructureExplode は取りこぼすと画面が
-- 前のフェーズのまま固まったり演出が抜けたりするので信頼性のある方を使う。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "DominoCrashNet"

local DEFINITIONS = {
	RequestHit = "RemoteEvent",
	OnStructureExplode = "RemoteEvent",
	MatchStateChanged = "RemoteEvent",
	ProgressSync = "UnreliableRemoteEvent",
}

function Net.server()
	assert(RunService:IsServer(), "Net.server() はサーバ専用です")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	local remotes = {}
	for name, className in DEFINITIONS do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
	end
	return remotes
end

function Net.client()
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	local remotes = {}
	for name in DEFINITIONS do
		remotes[name] = folder:WaitForChild(name)
	end
	return remotes
end

return Net
