--!strict
-- プレイヤー1人ぶんの移動シミュレーション。ここがゲームの権威 (authority) 本体。
--
-- ・Roblox API を一切使わない純関数なので、サーバ (権威) とクライアント (予測) が
--   まったく同じコードを実行でき、ズレの原因を「入力の差」だけに絞り込める。
-- ・出力される Trace が、他プレイヤーへ送られる唯一の情報。座標そのものは送らない。
-- ・dt は呼び出し側の申告ではなく Config.move.maxStepDelta で必ず頭打ちにする
--   (クライアントが巨大な dt を送って一気に移動する速度ハックへの対策)。

local Motion = {}

export type Stance = "Stand" | "Crouch" | "Sprint"

export type State = {
	x: number,
	z: number,
	y: number, -- 床からの高さ。迷路は平坦なので床は y = 0
	vx: number,
	vz: number,
	vy: number,
	grounded: boolean,
	stance: Stance,
	stamina: number,
	stepAccum: number, -- 次の足跡までの移動距離の蓄積
	lastSeq: number,
}

export type Input = {
	seq: number,
	moveX: number, -- カメラ相対に変換済みの進行方向 (長さ<=1)
	moveZ: number,
	jump: boolean,
	sprint: boolean,
	crouch: boolean,
}

-- 他プレイヤーへ配信される「気配」。位置と向きだけを持つ。
export type Trace = {
	kind: string, -- "Step" | "SprintStep" | "Jump" | "Land"
	x: number,
	z: number,
	dirX: number,
	dirZ: number,
}

function Motion.newState(x: number, z: number, cfg: any): State
	return {
		x = x,
		z = z,
		y = 0,
		vx = 0,
		vz = 0,
		vy = 0,
		grounded = true,
		stance = "Stand" :: Stance,
		stamina = cfg.stamina.max,
		stepAccum = 0,
		lastSeq = 0,
	}
end

function Motion.emptyInput(): Input
	return { seq = 0, moveX = 0, moveZ = 0, jump = false, sprint = false, crouch = false }
end

-- クライアントから来た生データを信用できる形に落とす。
-- 「入力の正規化」をサーバとクライアント予測の両方で通すことで、
-- 予測ズレとチート対策を同時に満たす。
function Motion.sanitize(raw: any, cfg: any): Input
	if type(raw) ~= "table" then
		return Motion.emptyInput()
	end
	local mx = tonumber(raw.moveX) or 0
	local mz = tonumber(raw.moveZ) or 0
	if mx ~= mx or mz ~= mz then -- NaN 弾き
		mx, mz = 0, 0
	end
	local len = math.sqrt(mx * mx + mz * mz)
	if len > 1 then -- 長さ>1 のベクトルを送って速く動く手口を潰す
		mx, mz = mx / len, mz / len
	end
	local seq = tonumber(raw.seq) or 0
	return {
		seq = math.floor(math.clamp(seq, 0, 2 ^ 31)),
		moveX = mx,
		moveZ = mz,
		jump = raw.jump == true,
		sprint = raw.sprint == true,
		crouch = raw.crouch == true,
	}
end

local function decideStance(state: State, input: Input, cfg: any): Stance
	if input.crouch then
		return "Crouch"
	end
	local moving = (input.moveX ~= 0 or input.moveZ ~= 0)
	if input.sprint and moving and state.stamina > 0 then
		-- 一度切らしたら sprintMinimum まで回復しないと再ダッシュできない
		if state.stance == "Sprint" or state.stamina >= cfg.stamina.sprintMinimum then
			return "Sprint"
		end
	end
	return "Stand"
end

local function speedFor(stance: Stance, cfg: any): number
	if stance == "Crouch" then
		return cfg.move.crouchSpeed
	elseif stance == "Sprint" then
		return cfg.move.sprintSpeed
	end
	return cfg.move.walkSpeed
end

-- 1ステップ進める。state は破壊的に更新し、発生した痕跡を返す。
function Motion.step(state: State, input: Input, dt: number, grid: any, cfg: any): { Trace }
	dt = math.clamp(dt, 0, cfg.move.maxStepDelta)
	local traces: { Trace } = {}
	if dt <= 0 then
		return traces
	end

	state.lastSeq = input.seq
	state.stance = decideStance(state, input, cfg)

	-- ── ジャンプ (踏み切りの瞬間に波紋) ──
	if input.jump and state.grounded and state.stamina >= cfg.stamina.jumpCost then
		state.vy = cfg.move.jumpVelocity
		state.grounded = false
		state.stamina -= cfg.stamina.jumpCost
		table.insert(traces, { kind = "Jump", x = state.x, z = state.z, dirX = 0, dirZ = 0 })
	end

	-- ── 水平方向の加速 ──
	local speed = speedFor(state.stance, cfg)
	local control = state.grounded and 1 or 0.35 -- 空中では方向転換しにくい
	local desiredX, desiredZ = input.moveX * speed, input.moveZ * speed
	if input.moveX == 0 and input.moveZ == 0 then
		local damp = math.max(0, 1 - cfg.move.friction * dt * control)
		state.vx *= damp
		state.vz *= damp
	else
		local maxDelta = cfg.move.accel * dt * control
		local dx, dz = desiredX - state.vx, desiredZ - state.vz
		local dLen = math.sqrt(dx * dx + dz * dz)
		if dLen > maxDelta and dLen > 0 then
			dx, dz = dx / dLen * maxDelta, dz / dLen * maxDelta
		end
		state.vx += dx
		state.vz += dz
	end

	-- ── 垂直方向 ──
	state.vy -= cfg.move.gravity * dt
	state.y += state.vy * dt
	if state.y <= 0 then
		state.y = 0
		if not state.grounded then
			state.grounded = true
			table.insert(traces, { kind = "Land", x = state.x, z = state.z, dirX = 0, dirZ = 0 })
		end
		state.vy = 0
	end

	-- ── 水平移動 + 壁との判定 ──
	-- 高速時にすり抜けないよう、1サブステップの移動量を半径以下に刻む。
	local radius = cfg.player.radius
	local totalDx, totalDz = state.vx * dt, state.vz * dt
	local dist = math.sqrt(totalDx * totalDx + totalDz * totalDz)
	local steps = math.max(1, math.ceil(dist / (radius * 0.7)))
	local movedX, movedZ = 0, 0
	for _ = 1, steps do
		local beforeX, beforeZ = state.x, state.z
		state.x += totalDx / steps
		state.z += totalDz / steps
		local nx, nz, hitX, hitZ = grid.resolve(state.x, state.z, radius)
		state.x, state.z = nx, nz
		-- 壁に押し戻された軸の速度は殺す (壁ズリはもう片方の軸で継続する)
		if hitX and state.vx * (nx - beforeX) <= 0 then
			state.vx = 0
		end
		if hitZ and state.vz * (nz - beforeZ) <= 0 then
			state.vz = 0
		end
		movedX += state.x - beforeX
		movedZ += state.z - beforeZ
	end

	-- ── 痕跡の生成 ──
	local moved = math.sqrt(movedX * movedX + movedZ * movedZ)
	if state.grounded and state.stance ~= "Crouch" then
		local kind = if state.stance == "Sprint" then "SprintStep" else "Step"
		local spec = cfg.trace[kind]
		state.stepAccum += moved
		local guard = 0
		while state.stepAccum >= spec.distance and guard < 8 do
			state.stepAccum -= spec.distance
			guard += 1
			local dirLen = math.max(moved, 1e-6)
			table.insert(traces, {
				kind = kind,
				x = state.x,
				z = state.z,
				dirX = movedX / dirLen,
				dirZ = movedZ / dirLen,
			})
		end
	else
		-- しゃがみ・空中では蓄積を戻す。しゃがんで距離を貯めてから
		-- 立ち上がった瞬間に足跡が出る、という不自然さを防ぐ。
		state.stepAccum = math.max(0, state.stepAccum - moved)
	end

	-- ── スタミナ ──
	if state.stance == "Sprint" and moved > 0 then
		state.stamina -= cfg.stamina.sprintDrain * dt
	elseif state.stance == "Crouch" then
		state.stamina += cfg.stamina.crouchRegen * dt
	else
		state.stamina += cfg.stamina.regen * dt
	end
	state.stamina = math.clamp(state.stamina, 0, cfg.stamina.max)

	return traces
end

-- 権威側の値でクライアントの予測状態を上書きする (リコンサイル用)
function Motion.applySnapshot(state: State, snap: any)
	state.x = snap.x
	state.z = snap.z
	state.y = snap.y
	state.vx = snap.vx
	state.vz = snap.vz
	state.vy = snap.vy
	state.grounded = snap.grounded
	state.stamina = snap.stamina
	state.stance = snap.stance
	state.stepAccum = snap.stepAccum
end

function Motion.snapshot(state: State): any
	return {
		x = state.x,
		z = state.z,
		y = state.y,
		vx = state.vx,
		vz = state.vz,
		vy = state.vy,
		grounded = state.grounded,
		stamina = state.stamina,
		stance = state.stance,
		stepAccum = state.stepAccum,
		seq = state.lastSeq,
	}
end

return Motion
