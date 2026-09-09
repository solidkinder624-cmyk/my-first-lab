--!strict
-- 1機ぶんの飛行シミュレーション。ここがゲームの権威 (authority) 本体。
--
-- ・Roblox API を一切使わない純関数なので、サーバ (権威) とクライアント (予測) が
--   まったく同じコードを実行でき、ズレの原因を「入力の差」だけに絞り込める。
-- ・dt は呼び出し側の申告ではなく Config.anticheat.maxStepDelta で必ず頭打ちにする
--   (クライアントが巨大な dt を送って一気に加速する速度ハックへの対策)。
-- ・向きは pitch/yaw/roll (度) で持つ。CFrame への変換は Roblox 依存側 (client) が行う。

local FlightModel = {}

export type State = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	pitch: number, -- 度。機首上げが正
	yaw: number, -- 度。0..360 に正規化
	roll: number, -- 度。0..360 に正規化 (バレルロールを許すので折り返す)
	throttle: number, -- 0..1
	fuel: number,
	grounded: boolean,
	gearDown: boolean,
	boostRemaining: number, -- 秒。>0 ならブースト中
	boostCooldown: number, -- 秒。>0 なら再発動不可
	lastSeq: number,
}

export type Input = {
	seq: number,
	rollStick: number, -- -1..1 左スティック 左右
	pitchStick: number, -- -1..1 左スティック 上下 (上に倒す = 機首上げ = 正)
	yawStick: number, -- -1..1 右スティック 左右
	throttleInput: number, -- -1..1 (R2 - L2 相当。正で加速、負で減速)
	boost: boolean,
	gearToggle: boolean,
}

local function clampAngle(deg: number): number
	deg %= 360
	if deg < 0 then
		deg += 360
	end
	return deg
end

function FlightModel.newState(x: number, y: number, z: number, aircraftStats: any): State
	return {
		x = x,
		y = y,
		z = z,
		vx = 0,
		vy = 0,
		vz = 0,
		pitch = 0,
		yaw = 0,
		roll = 0,
		throttle = 0,
		fuel = aircraftStats.fuelCapacity,
		grounded = true,
		gearDown = true,
		boostRemaining = 0,
		boostCooldown = 0,
		lastSeq = 0,
	}
end

function FlightModel.emptyInput(): Input
	return {
		seq = 0,
		rollStick = 0,
		pitchStick = 0,
		yawStick = 0,
		throttleInput = 0,
		boost = false,
		gearToggle = false,
	}
end

-- クライアントから来た生データを信用できる形に落とす。
-- 「入力の正規化」をサーバとクライアント予測の両方で通すことで、
-- 予測ズレとチート対策を同時に満たす。
function FlightModel.sanitize(raw: any): Input
	if type(raw) ~= "table" then
		return FlightModel.emptyInput()
	end
	local function axis(v: any): number
		local n = tonumber(v) or 0
		if n ~= n then -- NaN 弾き
			return 0
		end
		return math.clamp(n, -1, 1)
	end
	local seq = tonumber(raw.seq) or 0
	return {
		seq = math.floor(math.clamp(seq, 0, 2 ^ 31)),
		rollStick = axis(raw.rollStick),
		pitchStick = axis(raw.pitchStick),
		yawStick = axis(raw.yawStick),
		throttleInput = axis(raw.throttleInput),
		boost = raw.boost == true,
		gearToggle = raw.gearToggle == true,
	}
end

-- 前方ベクトル (pitch/yaw から。roll は機体の見た目にのみ影響し、進行方向には影響しない)
function FlightModel.forwardVector(state: State): (number, number, number)
	local pitchRad = math.rad(state.pitch)
	local yawRad = math.rad(state.yaw)
	local horizontal = math.cos(pitchRad)
	return math.sin(yawRad) * horizontal, math.sin(pitchRad), math.cos(yawRad) * horizontal
end

function FlightModel.speed(state: State): number
	return math.sqrt(state.vx ^ 2 + state.vy ^ 2 + state.vz ^ 2)
end

-- 1ステップ進める。state は破壊的に更新し、発生したイベントを返す。
function FlightModel.step(state: State, input: Input, dt: number, aircraftStats: any, cfg: any): { string }
	dt = math.clamp(dt, 0, cfg.anticheat.maxStepDelta)
	local events: { string } = {}
	if dt <= 0 then
		return events
	end
	local flight = cfg.flight

	state.lastSeq = input.seq

	-- ── 着陸装置トグル ──
	if input.gearToggle then
		state.gearDown = not state.gearDown
	end

	-- ── ブースト ──
	if state.boostCooldown > 0 then
		state.boostCooldown = math.max(0, state.boostCooldown - dt)
	end
	if state.boostRemaining > 0 then
		state.boostRemaining = math.max(0, state.boostRemaining - dt)
	elseif input.boost and state.boostCooldown <= 0 and state.fuel > 0 then
		state.boostRemaining = flight.boost.duration
		state.boostCooldown = flight.boost.duration + flight.boost.cooldown
		table.insert(events, "Boost")
	end
	local boosting = state.boostRemaining > 0

	-- ── 姿勢 (機体が地上にいる間はロール・ピッチを無視して直進のみ) ──
	if not state.grounded or FlightModel.speed(state) >= flight.takeoffMinSpeed then
		state.roll = clampAngle(state.roll + input.rollStick * aircraftStats.turnRate * dt)
		state.pitch =
			math.clamp(state.pitch + input.pitchStick * aircraftStats.turnRate * dt, -flight.pitchLimit, flight.pitchLimit)
	end
	state.yaw = clampAngle(state.yaw + input.yawStick * aircraftStats.turnRate * dt)

	-- ── スロットル ──
	state.throttle = math.clamp(state.throttle + input.throttleInput * flight.throttleRate * dt, 0, 1)

	-- ── 燃料 ──
	local burnRate = flight.fuelBurnRate * state.throttle
	if boosting then
		burnRate *= flight.fuelBurnBoostMultiplier
	end
	local hadFuel = state.fuel > 0
	state.fuel = math.max(0, state.fuel - burnRate * dt)
	if hadFuel and state.fuel <= 0 then
		table.insert(events, "FuelOut")
	end
	local effectiveThrottle = if state.fuel > 0 then state.throttle else 0

	-- ── 推力 (前方ベクトル方向) ──
	local fx, fy, fz = FlightModel.forwardVector(state)
	local thrust = aircraftStats.accel * effectiveThrottle
	if boosting then
		thrust *= flight.boost.multiplier
	end
	state.vx += fx * thrust * dt
	state.vy += fy * thrust * dt
	state.vz += fz * thrust * dt

	-- ── 滑走路上の離陸判定 ──
	-- 地上では滑走路が自重を支えているので沈下は起きない。滑走速度が離陸速度に
	-- 達したら、機首上げ (rotation) による浮き上がりとして明示的に浮上させる。
	if state.grounded then
		local groundSpeed = FlightModel.speed(state)
		if groundSpeed >= flight.takeoffMinSpeed then
			state.grounded = false
			state.vy = math.max(state.vy, flight.takeoffLiftVelocity)
			table.insert(events, "Takeoff")
		end
	end

	-- ── 重力・失速 (空中にいるときだけ) ──
	if not state.grounded then
		local speed = FlightModel.speed(state)
		local liftRatio = math.clamp(speed / flight.minSpeed, 0, 1)
		local sink = flight.gravity * (1 - liftRatio) + flight.stallSinkRate * (1 - liftRatio)
		if liftRatio < 1 then
			table.insert(events, "Stall")
		end
		state.vy -= sink * dt
	end

	-- ── 空気抵抗 ──
	local drag = math.clamp(1 - flight.drag * dt, 0, 1)
	state.vx *= drag
	state.vy *= drag
	state.vz *= drag

	-- ── 上限速度 (ブースト込み) ──
	local maxSpeed = aircraftStats.maxSpeed * (if boosting then flight.boost.multiplier else 1)
	local newSpeed = FlightModel.speed(state)
	if newSpeed > maxSpeed and newSpeed > 0 then
		local scale = maxSpeed / newSpeed
		state.vx *= scale
		state.vy *= scale
		state.vz *= scale
	end

	-- ── 位置積分 ──
	state.x += state.vx * dt
	state.y += state.vy * dt
	state.z += state.vz * dt

	-- ── 高度上限 (超えたら強制的に押し戻し、機首下げの余地だけ残す) ──
	if state.y > cfg.world.ceiling then
		state.y = cfg.world.ceiling
		state.vy = math.min(state.vy, 0)
		table.insert(events, "CeilingLimit")
	end

	-- ── 地面判定 ──
	if state.y <= flight.groundHeight then
		state.y = flight.groundHeight
		local landingSpeed = FlightModel.speed(state)
		if not state.grounded then
			if state.gearDown and landingSpeed <= aircraftStats.maxSpeed * 0.55 then
				table.insert(events, "Land")
			else
				table.insert(events, "Crash")
			end
		end
		state.grounded = true
		state.vy = 0
	end

	return events
end

-- 権威側の値でクライアントの予測状態を上書きする (リコンサイル用)
function FlightModel.applySnapshot(state: State, snap: any)
	state.x, state.y, state.z = snap.x, snap.y, snap.z
	state.vx, state.vy, state.vz = snap.vx, snap.vy, snap.vz
	state.pitch, state.yaw, state.roll = snap.pitch, snap.yaw, snap.roll
	state.throttle = snap.throttle
	state.fuel = snap.fuel
	state.grounded = snap.grounded
	state.gearDown = snap.gearDown
	state.boostRemaining = snap.boostRemaining
	state.boostCooldown = snap.boostCooldown
end

function FlightModel.snapshot(state: State): any
	return {
		x = state.x,
		y = state.y,
		z = state.z,
		vx = state.vx,
		vy = state.vy,
		vz = state.vz,
		pitch = state.pitch,
		yaw = state.yaw,
		roll = state.roll,
		throttle = state.throttle,
		fuel = state.fuel,
		grounded = state.grounded,
		gearDown = state.gearDown,
		boostRemaining = state.boostRemaining,
		boostCooldown = state.boostCooldown,
		seq = state.lastSeq,
	}
end

return FlightModel
