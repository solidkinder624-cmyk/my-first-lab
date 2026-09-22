--!strict
-- 恐竜の「動きの計算だけ」を行う純ロジック。
--
-- Roblox API（Instance / Vector3 / CFrame / Random など）を一切使わない。
-- 座標は x, z の数値で扱い、乱数は :NextNumber(min, max) を持つもの（Roblox の Random など）を受け取る。
-- そのため Luau CLI のテストでも Studio でも同じ動きになる。
--
-- 使うのは DinoMover / WildDinos / RanchDinos（同じフォルダ）。
--
-- ■ 1頭分の状態（Agent）の動き方
--   待機（Target なし） → ResumeAt を過ぎたら env.chooseTarget で目的地を決める
--   歩行（Target あり） → 1回の更新で Speed * dt だけ目的地へ進む
--       ・env.canStepTo が false を返す場所へは進まない（止まって待機へ）… 野生の水・拠点よけ
--       ・env.constrain で進んだ先を必ず範囲内に戻す … 飼育恐竜の柵の内側
--       ・着いたら待機へ（待ち時間は種の WanderPauseMin〜WanderPauseMax）
--   テイム中（Frozen = true） → 一切動かない

local WanderLogic = {}

-- 目的地の候補を何回まで引き直すか（アルゴリズム上の試行回数。ゲームの調整値ではない）
local TARGET_ATTEMPTS = 12
-- これより近ければ「着いた」とみなす距離の下限（浮動小数の誤差よけ。ゲームの調整値ではない）
local ARRIVE_EPSILON = 1e-3

export type Rng = {
	NextNumber: (self: any, minValue: number, maxValue: number) -> number,
}

export type Agent = {
	X: number,
	Z: number,
	Yaw: number, -- 向き（ラジアン）。CFrame.Angles(0, Yaw, 0) の LookVector が進む向きになる
	TargetX: number?,
	TargetZ: number?,
	ResumeAt: number, -- 待機が終わる時刻（秒）
	Speed: number, -- studs/秒
	PauseMin: number,
	PauseMax: number,
	Frozen: boolean, -- テイム中など。true の間は動かない
	Moving: boolean, -- 直近の更新で動いたか（見た目の State 属性用）
}

export type Env = {
	-- 次の目的地を決める。見つからなければ nil（少し待って再挑戦する）
	chooseTarget: (agent: Agent, rng: Rng) -> (number?, number?),
	-- その場所へ1歩進んでよいか（省略可）
	canStepTo: ((x: number, z: number) -> boolean)?,
	-- 進んだ先を範囲内へ戻す（省略可）
	constrain: ((x: number, z: number) -> (number, number))?,
}

-- ── 設定の確認 ────────────────────────────────────────
-- DinoAI が使う DinoConfig のキーがそろっているか確かめる（足りなければ assert でエラー）。
local SPECIES_NUMBER_KEYS = {
	"WalkSpeed",
	"WanderRadius",
	"RanchWanderRadius",
	"WanderPauseMin",
	"WanderPauseMax",
	"SpawnWeight",
}
local SPECIES_COLOR_KEYS = { "PlaceholderColor", "PlaceholderAccentColor", "PlaceholderBodySize" }

function WanderLogic.validateConfig(config: any)
	assert(type(config) == "table", "DinoConfig がありません")
	assert(type(config.Species) == "table", "DinoConfig.Species がありません")
	assert(type(config.SpeciesOrder) == "table", "DinoConfig.SpeciesOrder がありません")
	for id, species in config.Species do
		local where = "DinoConfig.Species." .. tostring(id)
		assert(type(species.ModelName) == "string", where .. ".ModelName がありません（文字列が必要）")
		for _, key in SPECIES_NUMBER_KEYS do
			assert(type(species[key]) == "number", where .. "." .. key .. " がありません（数値が必要）")
		end
		for _, key in SPECIES_COLOR_KEYS do
			local value = species[key]
			assert(
				type(value) == "table" and #value == 3,
				where .. "." .. key .. " がありません（{ 数値, 数値, 数値 } が必要）"
			)
		end
	end
	local sections: { [string]: { string } } = {
		Wild = { "MaxWildDinos", "RespawnDelay", "MinSpawnDistanceFromPlayer" },
		Ranch = { "AIUpdateInterval", "FenceMargin" },
		World = { "ReadyPollInterval" },
	}
	for section, keys in sections do
		assert(type(config[section]) == "table", "DinoConfig." .. section .. " がありません")
		for _, key in keys do
			assert(
				type(config[section][key]) == "number",
				"DinoConfig." .. section .. "." .. key .. " がありません（数値が必要）"
			)
		end
	end
	assert(config.Ranch.AIUpdateInterval > 0, "DinoConfig.Ranch.AIUpdateInterval は 0 より大きくする")
end

-- ── 野生の種選び ──────────────────────────────────────
-- SpeciesOrder の順に SpawnWeight で重み付けして1種選ぶ。重みが 0 以下の種は出ない。
-- 全種の重みが 0 なら nil。
function WanderLogic.pickWeightedSpecies(speciesTable: { [string]: any }, order: { string }, rng: Rng): string?
	local total = 0
	for _, id in order do
		local species = speciesTable[id]
		if species and type(species.SpawnWeight) == "number" and species.SpawnWeight > 0 then
			total += species.SpawnWeight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, total)
	local accumulated = 0
	local last: string? = nil
	for _, id in order do
		local species = speciesTable[id]
		if species and type(species.SpawnWeight) == "number" and species.SpawnWeight > 0 then
			accumulated += species.SpawnWeight
			last = id
			if roll < accumulated then
				return id
			end
		end
	end
	return last -- roll == total のとき（端の値）
end

-- ── 目的地・待ち時間 ──────────────────────────────────
-- 中心 (cx, cz)・半径 radius の円の中に一様に散らばる点
function WanderLogic.randomPointInDisc(cx: number, cz: number, radius: number, rng: Rng): (number, number)
	local angle = rng:NextNumber(0, 2 * math.pi)
	local distance = radius * math.sqrt(rng:NextNumber(0, 1))
	return cx + math.cos(angle) * distance, cz + math.sin(angle) * distance
end

-- 円の中から accept(x, z) を満たす点を探す。TARGET_ATTEMPTS 回で見つからなければ nil
function WanderLogic.chooseDiscTarget(
	cx: number,
	cz: number,
	radius: number,
	rng: Rng,
	accept: (x: number, z: number) -> boolean
): (number?, number?)
	for _ = 1, TARGET_ATTEMPTS do
		local x, z = WanderLogic.randomPointInDisc(cx, cz, radius, rng)
		if accept(x, z) then
			return x, z
		end
	end
	return nil, nil
end

-- 飼育恐竜の目的地: 拠点の中心 (cx, cz) から radius（種の RanchWanderRadius）の円の中の点を、
-- clamp（RanchWorld.clampToRanch）で柵の内側に切り詰めたもの。必ず柵の内側になる
function WanderLogic.chooseRanchTarget(
	cx: number,
	cz: number,
	radius: number,
	rng: Rng,
	clamp: (x: number, z: number) -> (number, number)
): (number, number)
	local x, z = WanderLogic.randomPointInDisc(cx, cz, radius, rng)
	return clamp(x, z)
end

function WanderLogic.pauseDuration(agent: Agent, rng: Rng): number
	local minValue = math.max(0, math.min(agent.PauseMin, agent.PauseMax))
	local maxValue = math.max(minValue, agent.PauseMax)
	return rng:NextNumber(minValue, maxValue)
end

-- 進む向き (dx, dz) を向く Yaw（CFrame.Angles(0, yaw, 0) の LookVector = (-sin, 0, -cos)）
function WanderLogic.yawFromDirection(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

-- (x, z) から (tx, tz) へ最大 maxDistance だけ進む。
-- 戻り値: 新しい x, z, 着いたか, 進んだ向き dx, dz（正規化済み。動かなければ 0, 0）
function WanderLogic.stepToward(
	x: number,
	z: number,
	tx: number,
	tz: number,
	maxDistance: number
): (number, number, boolean, number, number)
	local dx, dz = tx - x, tz - z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance <= math.max(maxDistance, ARRIVE_EPSILON) then
		if distance <= ARRIVE_EPSILON then
			return tx, tz, true, 0, 0
		end
		return tx, tz, true, dx / distance, dz / distance
	end
	local ux, uz = dx / distance, dz / distance
	return x + ux * maxDistance, z + uz * maxDistance, false, ux, uz
end

-- ── 1頭分の生成・更新 ─────────────────────────────────
function WanderLogic.newAgent(x: number, z: number, species: any, now: number, rng: Rng): Agent
	local agent: Agent = {
		X = x,
		Z = z,
		Yaw = rng:NextNumber(-math.pi, math.pi),
		TargetX = nil,
		TargetZ = nil,
		ResumeAt = now,
		Speed = species.WalkSpeed,
		PauseMin = species.WanderPauseMin,
		PauseMax = species.WanderPauseMax,
		Frozen = false,
		Moving = false,
	}
	-- 出現直後に全員が同時に歩き出さないよう、最初の待ち時間をばらけさせる
	agent.ResumeAt = now + WanderLogic.pauseDuration(agent, rng)
	return agent
end

-- 立ち止まって待機に入る
function WanderLogic.stop(agent: Agent, now: number, rng: Rng)
	agent.TargetX = nil
	agent.TargetZ = nil
	agent.Moving = false
	agent.ResumeAt = now + WanderLogic.pauseDuration(agent, rng)
end

-- 1回分の更新。戻り値: 位置か向きが変わったか（true のときだけモデルを動かせばよい）
function WanderLogic.advance(agent: Agent, env: Env, dt: number, now: number, rng: Rng): boolean
	if agent.Frozen then
		agent.Moving = false
		return false
	end

	if agent.TargetX == nil or agent.TargetZ == nil then
		agent.Moving = false
		if now < agent.ResumeAt then
			return false
		end
		local tx, tz = env.chooseTarget(agent, rng)
		if tx == nil or tz == nil then
			WanderLogic.stop(agent, now, rng)
			return false
		end
		agent.TargetX, agent.TargetZ = tx, tz
	end

	local tx, tz = agent.TargetX :: number, agent.TargetZ :: number
	local nx, nz, arrived, dx, dz = WanderLogic.stepToward(agent.X, agent.Z, tx, tz, agent.Speed * dt)

	if env.canStepTo and not env.canStepTo(nx, nz) then
		WanderLogic.stop(agent, now, rng)
		return false
	end
	if env.constrain then
		nx, nz = env.constrain(nx, nz)
	end

	local moved = nx ~= agent.X or nz ~= agent.Z
	agent.X, agent.Z = nx, nz
	if dx ~= 0 or dz ~= 0 then
		agent.Yaw = WanderLogic.yawFromDirection(dx, dz)
	end
	agent.Moving = moved

	if arrived or not moved then
		-- 着いた / 範囲の端で押し戻されて進めない → 待機へ
		WanderLogic.stop(agent, now, rng)
	end
	return moved
end

return WanderLogic
