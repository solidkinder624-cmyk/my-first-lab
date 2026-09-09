-- 自機だけはローカルで FlightModel を実行し、入力の瞬間に反応させる (クライアント予測)。
-- サーバは同じ FlightModel.luau を権威として実行しており、BroadcastFlightState で
-- 届く自分ぶんの値とズレが大きい場合だけ静かに上書きする (簡易リコンサイル)。
--
-- 他プレイヤーの機体は予測せず、ブロードキャストされた値をそのまま補間表示する
-- (RemotePlayers.luau)。

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SkyCarrier")
local FlightModel = require(Shared.FlightModel)
local Config = require(Shared.Config)

local RECONCILE_DISTANCE = 12 -- studs。これを超えたらサーバ値へスナップする

local FlightPredictor = {}
FlightPredictor.__index = FlightPredictor

function FlightPredictor.new(spawnPosition: Vector3, aircraftStats)
	local self = setmetatable({
		state = FlightModel.newState(spawnPosition.X, spawnPosition.Y, spawnPosition.Z, aircraftStats),
		aircraftStats = aircraftStats,
		lastInput = FlightModel.emptyInput(),
		connection = nil :: RBXScriptConnection?,
		onEvents = nil :: (({ string }) -> ())?,
	}, FlightPredictor)
	return self
end

function FlightPredictor:setInput(input)
	self.lastInput = input
end

function FlightPredictor:start()
	self.connection = RunService.Heartbeat:Connect(function(dt)
		local events = FlightModel.step(self.state, self.lastInput, dt, self.aircraftStats, Config)
		if #events > 0 and self.onEvents then
			self.onEvents(events)
		end
	end)
end

function FlightPredictor:stop()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

-- サーバから届いた自分ぶんのスナップショットと大きくズレていたら合わせる。
-- 毎回上書きすると入力への追従が消えるので、閾値を超えたときだけにする。
function FlightPredictor:reconcile(serverSnapshot)
	local dx = self.state.x - serverSnapshot.x
	local dy = self.state.y - serverSnapshot.y
	local dz = self.state.z - serverSnapshot.z
	local drift = math.sqrt(dx * dx + dy * dy + dz * dz)
	if drift > RECONCILE_DISTANCE then
		self.state.x, self.state.y, self.state.z = serverSnapshot.x, serverSnapshot.y, serverSnapshot.z
	end
	-- 燃料・着陸装置はサーバの判定 (ミッション成否・墜落) が絡むので常に合わせる
	self.state.fuel = serverSnapshot.fuel
	self.state.gearDown = serverSnapshot.gearDown
	self.state.grounded = serverSnapshot.grounded
end

return FlightPredictor
