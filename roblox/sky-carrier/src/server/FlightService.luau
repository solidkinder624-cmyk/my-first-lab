-- 飛行位置の権威。04/マルチプレイ構成のとおり、位置はサーバが正とし、
-- クライアントは入力送信と見た目の補間だけを担当する。
--
-- 1プレイヤーぶんの FlightModel.State + AntiCheat.Record を持ち、
-- UpdateFlightInput が届くたびに1ステップ進める。物理的に不可能な結果
-- (AntiCheat.check が reject) は直前の正規状態へ戻す。

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local FlightModel = require(Shared.FlightModel)
local AntiCheat = require(Shared.AntiCheat)

local FlightService = {}
FlightService.__index = FlightService

function FlightService.new(remotes, playerData, worldBuilder)
	local self = setmetatable({
		remotes = remotes,
		playerData = playerData,
		spawnCFrame = worldBuilder.spawnCFrame,
		states = {}, -- Player → FlightModel.State
		records = {}, -- Player → AntiCheat.Record
		lastBroadcast = 0,
	}, FlightService)
	return self
end

function FlightService:spawnFor(player: Player)
	local aircraftStats = self.playerData:effectiveStats(player)
	local origin = self.spawnCFrame.Position
	local state = FlightModel.newState(origin.X, origin.Y, origin.Z, aircraftStats)
	self.states[player] = state
	self.records[player] = AntiCheat.newRecord()
	AntiCheat.commit(self.records[player], os.clock(), state.x, state.y, state.z)
	return state
end

function FlightService:remove(player: Player)
	self.states[player] = nil
	self.records[player] = nil
end

function FlightService:get(player: Player)
	return self.states[player]
end

-- クライアントから届いた生入力を1ステップぶん適用する。
-- 戻り値: 発生したイベント ({string}) 。不正な移動として却下された場合は空配列。
function FlightService:applyInput(player: Player, rawInput: any, now: number): { string }
	local state = self.states[player]
	local record = self.records[player]
	if not (state and record) then
		return {}
	end

	local aircraftStats = self.playerData:effectiveStats(player)
	local input = FlightModel.sanitize(rawInput)

	-- dt はクライアント申告ではなくサーバの時計から計算する (時刻ハック対策)
	local dt = if record.hasLast then now - record.lastTime else 1 / Config.gamepad.inputHz
	dt = math.max(dt, 0)

	local beforeSnapshot = FlightModel.snapshot(state)
	local events = FlightModel.step(state, input, dt, aircraftStats, Config)

	local maxSpeed = aircraftStats.maxSpeed * Config.flight.boost.multiplier
	local ok, reason = AntiCheat.check(record, now, state.x, state.y, state.z, maxSpeed, Config.anticheat)
	if not ok then
		-- 物理的に不可能な結果は直前の正規状態へ巻き戻す。理由は返さない
		-- (どこまでなら通るかを改造クライアントに探らせないため)。
		FlightModel.applySnapshot(state, beforeSnapshot)
		return {}
	end
	AntiCheat.commit(record, now, state.x, state.y, state.z)

	if table.find(events, "Crash") then
		self:respawn(player)
	end

	return events
end

-- 墜落時は中央空港へ強制帰還させる (燃料はそのまま。ペナルティは所持金ではなく時間ロス)
function FlightService:respawn(player: Player)
	local aircraftStats = self.playerData:effectiveStats(player)
	local state = self.states[player]
	if not state then
		return
	end
	local origin = self.spawnCFrame.Position
	local fuel = state.fuel
	local fresh = FlightModel.newState(origin.X, origin.Y, origin.Z, aircraftStats)
	fresh.fuel = fuel
	self.states[player] = fresh
	if self.records[player] then
		AntiCheat.commit(self.records[player], os.clock(), fresh.x, fresh.y, fresh.z)
	end
end

-- 全員ぶんの位置を1パケットにまとめて配信する。
function FlightService:broadcastStep(now: number)
	if now - self.lastBroadcast < 1 / Config.broadcast.rateHz then
		return
	end
	self.lastBroadcast = now

	local payload = {}
	for player, state in self.states do
		table.insert(payload, {
			userId = player.UserId,
			x = state.x,
			y = state.y,
			z = state.z,
			pitch = state.pitch,
			yaw = state.yaw,
			roll = state.roll,
			throttle = state.throttle,
			fuel = state.fuel,
			grounded = state.grounded,
			gearDown = state.gearDown,
		})
	end
	self.remotes.BroadcastFlightState:FireAllClients(payload)
end

return FlightService
