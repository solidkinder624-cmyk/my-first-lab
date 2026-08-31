-- リモートの定義を1か所に集約する。サーバが生成し、クライアントは待つだけ。
--
-- 送るものは3種類しかない:
--   Input     C→S  入力意思 (座標ではない)
--   Reconcile S→C  "本人にだけ" 返す権威座標
--   Trace     S→C  痕跡。他人について送られる唯一の情報
--   Round     S→C  ラウンド/役割/目的の通知
--   Ready     C→S  クライアントの準備完了通知

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "TraceOnlyNet"

-- 頻度が高く、1発落ちても致命的でないものは UnreliableRemoteEvent にする
-- (入力は毎tick、リコンサイルは毎0.1秒送るため)
local DEFINITIONS = {
	Input = "UnreliableRemoteEvent",
	Reconcile = "UnreliableRemoteEvent",
	Trace = "RemoteEvent", -- 痕跡はゲームの情報そのものなので取りこぼさない
	Round = "RemoteEvent",
	Ready = "RemoteEvent",
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
