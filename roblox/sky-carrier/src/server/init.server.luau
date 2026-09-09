-- サーバ側エントリポイント。各サービスを組み立てて配線するだけ。
--
-- 権威の所在:
--   * 位置・速度・向き … FlightService (FlightModel を実行) がサーバで決める
--   * 何が届いたか      … MissionService がサーバの座標だけを見て判定する
--   * 所持金・機体・アップグレード … PlayerDataService が DataStore と同期する
--   * 演出・見た目        … 完全にクライアント側。サーバは数値だけ送る

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SkyCarrier")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local WorldBuilder = require(script.WorldBuilder)
local TerrainBuilder = require(script.TerrainBuilder)
local PlayerDataService = require(script.PlayerDataService)
local FlightService = require(script.FlightService)
local MissionService = require(script.MissionService)
local WeatherService = require(script.WeatherService)

local remotes = Net.server()
local world = WorldBuilder.build(workspace, Config)
TerrainBuilder.build(workspace, Config)
local playerData = PlayerDataService.new()
local flight = FlightService.new(remotes, playerData, world)
local missions = MissionService.new(remotes, playerData, flight, world.terminals)
local weather = WeatherService.new(remotes, Config)

-- ── 所持金・所有機体・アップグレードの通知 (ショップUI用) ─
local function pushProfile(player: Player)
	remotes.ProfileUpdate:FireClient(player, playerData:get(player))
end

-- ── プレイヤーの出入り ──────────────────────────────────
local function onPlayerAdded(player: Player)
	playerData:load(player)
	flight:spawnFor(player)
	missions:onPlayerAdded(player)
	pushProfile(player)
	weather:sendTo(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	flight:remove(player)
	missions:onPlayerRemoving(player)
	playerData:release(player)
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		playerData:save(player)
	end
end)

-- ── 入力 (Client → Server, 高頻度・UnreliableRemoteEvent) ─
remotes.UpdateFlightInput.OnServerEvent:Connect(function(player, rawInput)
	flight:applyInput(player, rawInput, os.clock())
end)

-- ── 離陸許可 (RemoteFunction) ────────────────────────────
remotes.RequestTakeoff.OnServerInvoke = function(player)
	local state = flight:get(player)
	if not state then
		return { ok = false, reason = "no_flight_state" }
	end
	if state.fuel <= 0 then
		return { ok = false, reason = "no_fuel" }
	end
	return { ok = true }
end

-- ── ミッション受注 (RemoteFunction) ──────────────────────
remotes.RequestAcceptMission.OnServerInvoke = function(player, missionId)
	local ok, reason = missions:accept(player, missionId)
	return { ok = ok, reason = reason }
end

-- ── 荷物受け渡し (RemoteFunction) ────────────────────────
remotes.RequestDelivery.OnServerInvoke = function(player, missionId)
	local success, reason, payout = missions:deliver(player, missionId)
	if success then
		pushProfile(player) -- 支払いで所持金が変わったのでショップUIへ反映する
	end
	return { success = success, reason = reason, payout = payout }
end

-- ── 機体購入・乗り換え・アップグレード (RemoteFunction) ──
remotes.RequestPurchaseAircraft.OnServerInvoke = function(player, aircraftName)
	local ok, reason = playerData:purchaseAircraft(player, aircraftName)
	if ok then
		pushProfile(player)
	end
	return { ok = ok, reason = reason }
end

remotes.RequestSelectAircraft.OnServerInvoke = function(player, aircraftName)
	local ok, reason = playerData:selectAircraft(player, aircraftName)
	if ok then
		pushProfile(player)
	end
	return { ok = ok, reason = reason }
end

remotes.RequestPurchaseUpgrade.OnServerInvoke = function(player, upgradeKind)
	local ok, reason = playerData:purchaseUpgrade(player, upgradeKind)
	if ok then
		pushProfile(player)
	end
	return { ok = ok, reason = reason }
end

-- ── メインループ ────────────────────────────────────────
RunService.Heartbeat:Connect(function()
	flight:broadcastStep(os.clock())
end)

-- ── 定期的な自動保存 ────────────────────────────────────
task.spawn(function()
	while true do
		task.wait(120)
		for _, player in Players:GetPlayers() do
			playerData:save(player)
		end
	end
end)

-- ── 天候の切り替わり監視 ────────────────────────────────
task.spawn(function()
	while true do
		weather:step()
		task.wait(10)
	end
end)

print(
	string.format(
		"[SkyCarrier] サーバ起動: ターミナル%d箇所 / 高度上限%d studs / 入力%dHz",
		#world.terminals,
		Config.world.ceiling,
		Config.gamepad.inputHz
	)
)
