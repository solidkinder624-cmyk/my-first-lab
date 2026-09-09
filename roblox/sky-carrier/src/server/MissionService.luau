-- 配達ミッションの受注・進行・成否判定。報酬・制限時間の計算式は
-- すべて Mission.luau (純ロジック) にあり、ここは受注状態の管理と
-- FlightService から見た「今どこにいるか」との突き合わせだけを行う。

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local Mission = require(Shared.Mission)

local MissionService = {}
MissionService.__index = MissionService

function MissionService.new(remotes, playerData, flightService, terminals)
	local self = setmetatable({
		remotes = remotes,
		playerData = playerData,
		flightService = flightService,
		terminals = terminals,
		terminalById = {},
		offers = {}, -- Player → { MissionData... } (受注前の提示一覧)
		active = {}, -- Player → { [missionId] = { mission = MissionData, acceptedAt = number } }
		nextIndex = {}, -- Player → 次に生成するミッションの連番 (決定的な id のため)
		sessionSeed = os.time() % 100000,
	}, MissionService)

	for _, terminal in terminals do
		self.terminalById[terminal.id] = terminal
	end

	return self
end

function MissionService:refreshOffersFor(player: Player)
	local stats = self.playerData:effectiveStats(player)
	local index = self.nextIndex[player] or 1
	local offers = {}
	for i = 0, 2 do
		table.insert(offers, Mission.generate(self.sessionSeed + player.UserId, index + i, self.terminals, math.max(stats.cargoCapacity, 1), Config.mission))
	end
	self.nextIndex[player] = index + 3
	self.offers[player] = offers
	self:pushUpdate(player)
end

function MissionService:pushUpdate(player: Player)
	local active = {}
	for _, entry in self.active[player] or {} do
		table.insert(active, entry.mission)
	end
	self.remotes.MissionUpdate:FireClient(player, {
		offers = self.offers[player] or {},
		active = active,
	})
end

function MissionService:onPlayerAdded(player: Player)
	self.active[player] = {}
	self:refreshOffersFor(player)
end

function MissionService:onPlayerRemoving(player: Player)
	self.offers[player] = nil
	self.active[player] = nil
	self.nextIndex[player] = nil
end

-- 受注。RequestTakeoff や UI から呼ばれる想定。
function MissionService:accept(player: Player, missionId: string): (boolean, string)
	local stats = self.playerData:effectiveStats(player)
	local active = self.active[player]
	if not active then
		return false, "no_profile"
	end
	local activeCount = 0
	for _ in active do
		activeCount += 1
	end
	if not Mission.canAccept(activeCount, stats.maxActiveMissions) then
		return false, "max_active"
	end

	local found = nil
	for _, offer in self.offers[player] or {} do
		if offer.id == missionId then
			found = offer
			break
		end
	end
	if not found then
		return false, "unknown_mission"
	end

	active[missionId] = { mission = found, acceptedAt = os.clock() }
	self:pushUpdate(player)
	return true, "ok"
end

-- RequestDelivery: 着地判定 + 制限時間の確認をして、成功なら支払いを行う。
-- サーバ側の flightState (位置・接地・着陸装置) が唯一の判定材料で、
-- クライアントは「届けた」と主張するだけ。
function MissionService:deliver(player: Player, missionId: string): (boolean, string, number?)
	local active = self.active[player]
	local entry = active and active[missionId]
	if not entry then
		return false, "unknown_mission", nil
	end

	local state = self.flightService:get(player)
	if not state then
		return false, "no_flight_state", nil
	end

	local dest = self.terminalById[entry.mission.destId]
	local dx, dy, dz = state.x - dest.x, state.y - dest.y, state.z - dest.z
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

	if not Mission.isValidDropoff(distance, state.grounded, state.gearDown, Config.mission) then
		return false, "not_at_destination", nil
	end

	local elapsed = os.clock() - entry.acceptedAt
	local result = Mission.evaluate(entry.mission, elapsed, Config.mission)
	active[missionId] = nil

	if result.success then
		self.playerData:addMoney(player, result.payout)
	end
	self:pushUpdate(player)

	return result.success, if result.success then "ok" else "time_expired", result.payout
end

return MissionService
