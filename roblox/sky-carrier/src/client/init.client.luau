-- クライアント側エントリポイント。
--
-- このクライアントが持つ権限は「入力をサーバに送ること」だけ。位置の確定・
-- ミッションの成否・所持金はすべてサーバ (FlightService / MissionService /
-- PlayerDataService) が権威を持つ。ここでの FlightModel 実行は見た目を
-- 遅延なく追従させるための予測でしかなく、改造しても届け先まで飛べる範囲は
-- 増えない (サーバの座標だけが判定材料のため)。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SkyCarrier")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local FlightModel = require(Shared.FlightModel)

local InputController = require(script.InputController)
local FlightPredictor = require(script.FlightPredictor)
local AircraftRig = require(script.AircraftRig)
local RemotePlayers = require(script.RemotePlayers)
local CameraController = require(script.CameraController)
local MissionController = require(script.MissionController)
local Hud = require(script.Hud)

local player = Players.LocalPlayer
local remotes = Net.client()

-- サーバ側の初期スポーン地点 (中央空港) と、既定機体のステータスをそのまま使う。
-- 実際の機体・アップグレードはサーバの PlayerDataService が権威を持つので、
-- ここではズレたら reconcile で合わせるだけの初期値として扱う。
local spawnPosition = Vector3.new(0, Config.flight.groundHeight + 6, 40)
local aircraftStats = Config.aircraft[Config.defaultAircraft]

local predictor = FlightPredictor.new(spawnPosition, aircraftStats)
local rig = AircraftRig.build(Color3.fromRGB(230, 230, 235), true)
rig.Parent = Workspace

local remotePlayers = RemotePlayers.new(Workspace)
local camera = CameraController.new(predictor)
local input = InputController.new(remotes)
local missions = MissionController.new(remotes)
local hud = Hud.new()

predictor.onEvents = function(events)
	if table.find(events, "Land") then
		hud:flash("着陸")
	elseif table.find(events, "Crash") then
		hud:flash("墜落した！ 中央空港へ帰還します")
	elseif table.find(events, "FuelOut") then
		hud:flash("燃料切れ")
	elseif table.find(events, "Boost") then
		hud:flash("ブースト！")
	end
end

input.onGearToggle = function()
	-- 見た目はローカルで即座に切り替える (サーバの判定は次のブロードキャストで追従)
	predictor.state.gearDown = not predictor.state.gearDown
end
input.onDropPressed = function()
	missions:attemptDelivery()
end
-- InputController が組み立てた入力をそのまま FlightPredictor にも渡し、
-- サーバへ送るのと同じ値でローカルの見た目を進める (入力への追従を遅延なくする)。
input.onInput = function(rawInput)
	predictor:setInput(FlightModel.sanitize(rawInput))
end
missions.onResult = function(success, reason, payout)
	if success then
		hud:flash(string.format("配達成功！ +%d", math.floor(payout or 0)))
	elseif reason == "not_at_destination" then
		hud:flash("まだ目的地に到着していません")
	elseif reason == "time_expired" then
		hud:flash("時間切れ...")
	end
end

predictor:start()
camera:start()
input:start()
input:setEnabled(true)

remotes.BroadcastFlightState.OnClientEvent:Connect(function(payload)
	remotePlayers:onSnapshot(payload, player.UserId)
	for _, entry in payload do
		if entry.userId == player.UserId then
			predictor:reconcile(entry)
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	AircraftRig.setPose(rig, predictor.state.x, predictor.state.y, predictor.state.z, predictor.state.pitch, predictor.state.yaw, predictor.state.roll)
	remotePlayers:step(dt)
	hud:updateFlight(predictor.state)
	hud:updateMission(missions)
end)

print(string.format("[SkyCarrier] クライアント起動 (%s)", player.DisplayName))
