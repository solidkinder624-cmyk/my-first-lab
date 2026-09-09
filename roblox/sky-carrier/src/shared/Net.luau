--!strict
-- リモートの定義を1か所に集約する。サーバが生成し、クライアントは待つだけ。
--
-- 流れるものは9種類:
--   UpdateFlightInput   C→S  スティック/トリガー値 (約20Hz)
--   BroadcastFlightState S→C  各機体の位置・速度・向き (約12Hz、最新値だけ意味を持つ)
--   MissionUpdate        S→C  受注可能ミッション・進行状況・期限の通知
--   ProfileUpdate         S→C  所持金・所有機体・アップグレードレベルの通知 (ショップUI用)
--   RequestTakeoff        C→S→C  離陸許可判定 (RemoteFunction)
--   RequestAcceptMission   C→S→C  提示ミッションの受注 (RemoteFunction)
--   RequestDelivery        C→S→C  荷物受け渡しの正当性確認 (RemoteFunction)
--   RequestPurchaseAircraft C→S→C  機体の購入 (RemoteFunction)
--   RequestSelectAircraft   C→S→C  所有機体への乗り換え (RemoteFunction)
--   RequestPurchaseUpgrade  C→S→C  エンジン/燃料/貨物ベイの強化購入 (RemoteFunction)
--
-- UpdateFlightInput と BroadcastFlightState だけ UnreliableRemoteEvent なのは、
-- 高頻度で上書きされる「最新の値だけが意味を持つ」データだから。1発落ちても次で追いつく。
-- MissionUpdate は取りこぼすと画面が古いミッションのまま固まるので信頼性のある方を使う。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "SkyCarrierNet"

local DEFINITIONS = {
	UpdateFlightInput = "UnreliableRemoteEvent",
	BroadcastFlightState = "UnreliableRemoteEvent",
	MissionUpdate = "RemoteEvent",
	ProfileUpdate = "RemoteEvent",
	RequestTakeoff = "RemoteFunction",
	RequestAcceptMission = "RemoteFunction",
	RequestDelivery = "RemoteFunction",
	RequestPurchaseAircraft = "RemoteFunction",
	RequestSelectAircraft = "RemoteFunction",
	RequestPurchaseUpgrade = "RemoteFunction",
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
