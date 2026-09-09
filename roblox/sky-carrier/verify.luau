--!nonstrict
-- 「スカイキャリア」の純ロジック検証器。
--
--   luau roblox/sky-carrier/verify.luau
--
-- roblox/domino-crash/verify.luau と同じ考え方で、ゲーム本体が実際に使う
-- Config / FlightModel / Mission / AntiCheat を そのまま require して回す。
-- Roblox Studio を開かずに、
--   * 飛行モデルが物理的に破綻しないこと (高度上限・失速・燃料切れ・着陸/墜落判定)
--   * 同じ入力列からは必ず同じ結果が出ること (クライアント予測とサーバ権威が一致する前提)
--   * ミッションの報酬・制限時間の計算式が仕様どおりであること
--   * 不正な移動申告 (テレポート・フラッド) を弾けること
-- を CI で担保するのが目的。

local Config = require("./src/shared/Config")
local FlightModel = require("./src/shared/FlightModel")
local Mission = require("./src/shared/Mission")
local AntiCheat = require("./src/shared/AntiCheat")

local failures = 0
local checks = 0

local function check(ok: boolean, label: string, detail: string?)
	checks += 1
	local suffix = if detail then "  (" .. detail .. ")" else ""
	if ok then
		print(string.format("  ok    %s%s", label, suffix))
	else
		failures += 1
		print(string.format("  FAIL  %s%s", label, suffix))
	end
end

local function section(name: string)
	print("\n▸ " .. name)
end

local TRAINER = Config.aircraft.Trainer

local function noInput(seq: number)
	local i = FlightModel.emptyInput()
	i.seq = seq
	return i
end

-- ── 1. 離陸・失速・燃料 ─────────────────────────────────
section("離陸・失速・燃料")
do
	-- 地上でスロットルを上げ続ければ、いずれ滑走して離陸する
	local state = FlightModel.newState(0, 0, 0, TRAINER)
	local tookOff = false
	local seq = 0
	for _ = 1, 400 do
		seq += 1
		local input = FlightModel.emptyInput()
		input.seq = seq
		input.throttleInput = 1
		local events = FlightModel.step(state, input, 0.1, TRAINER, Config)
		if table.find(events, "Takeoff") then
			tookOff = true
			break
		end
	end
	check(tookOff, "全速スロットルを続ければ離陸する (Takeoff イベント)", string.format("高度 %.1f", state.y))
	check(state.y >= 0, "離陸後の高度は負にならない")

	-- 地上でスティックを倒しても、離陸速度未満ではロール・ピッチが変化しない
	-- (滑走路上で勝手にひっくり返らない)
	local ground = FlightModel.newState(0, 0, 0, TRAINER)
	local input = FlightModel.emptyInput()
	input.seq = 1
	input.rollStick = 1
	input.pitchStick = 1
	FlightModel.step(ground, input, 0.1, TRAINER, Config)
	check(ground.roll == 0 and ground.pitch == 0, "静止した地上機はスティック入力だけでは姿勢が変わらない")

	-- 低速で空中にいると失速 (Stall) イベントが出る
	local stallState = FlightModel.newState(0, 50, 0, TRAINER)
	stallState.grounded = false
	local stallEvents = FlightModel.step(stallState, noInput(1), 0.1, TRAINER, Config)
	check(table.find(stallEvents, "Stall") ~= nil, "最低速度未満の空中機は失速する (Stall イベント)")

	-- 燃料が尽きると FuelOut が一度だけ発生し、以降スロットルが効かなくなる
	local fuelState = FlightModel.newState(0, 200, 0, TRAINER)
	fuelState.grounded = false
	fuelState.throttle = 1
	fuelState.fuel = 0.4
	local fuelInput = noInput(1)
	fuelInput.throttleInput = 0 -- スロットルは維持するだけで上げない
	local ev1 = FlightModel.step(fuelState, fuelInput, 0.5, TRAINER, Config)
	local out1 = table.find(ev1, "FuelOut") ~= nil
	local ev2 = FlightModel.step(fuelState, fuelInput, 0.5, TRAINER, Config)
	local out2 = table.find(ev2, "FuelOut") ~= nil
	check(fuelState.fuel == 0, "燃料は0未満にならない")
	check(out1 and not out2, "FuelOut イベントは燃料切れの瞬間に一度だけ発生する")

	-- 高度上限を超えない
	local ceilState = FlightModel.newState(0, Config.world.ceiling - 1, 0, TRAINER)
	ceilState.grounded = false
	ceilState.vy = 5000
	local ceilEvents = FlightModel.step(ceilState, noInput(1), 1, TRAINER, Config)
	check(ceilState.y <= Config.world.ceiling, "高度は上限を超えない", string.format("%.1f", ceilState.y))
	check(table.find(ceilEvents, "CeilingLimit") ~= nil, "上限到達で CeilingLimit イベントが出る")
end

-- ── 2. 着陸・墜落判定 ────────────────────────────────────
section("着陸・墜落判定")
do
	local function approach(vy: number, gearDown: boolean)
		local state = FlightModel.newState(0, 0.05, 0, TRAINER)
		state.grounded = false
		state.gearDown = gearDown
		state.vy = vy
		local events = FlightModel.step(state, noInput(1), 0.1, TRAINER, Config)
		return state, events
	end

	local softState, softEvents = approach(-1, true)
	check(table.find(softEvents, "Land") ~= nil, "低速降下 + 着陸装置展開は Land 判定になる")
	check(softState.grounded, "着陸後は grounded になる")

	local _, gearUpEvents = approach(-1, false)
	check(table.find(gearUpEvents, "Crash") ~= nil, "着陸装置を出していないと低速でも Crash 判定になる")

	local _, fastEvents = approach(-300, true)
	check(table.find(fastEvents, "Crash") ~= nil, "高速降下は着陸装置を出していても Crash 判定になる")
end

-- ── 3. 決定性・速度上限・ブースト ────────────────────────
section("決定性・速度上限・ブースト")
do
	local function simulate()
		local state = FlightModel.newState(0, 300, 0, TRAINER)
		state.grounded = false
		local maxSpeedSeen = 0
		for i = 1, 120 do
			local input = FlightModel.emptyInput()
			input.seq = i
			input.throttleInput = 1
			input.yawStick = 0.3
			input.boost = (i % 40 == 1)
			FlightModel.step(state, input, 0.1, TRAINER, Config)
			maxSpeedSeen = math.max(maxSpeedSeen, FlightModel.speed(state))
		end
		return state, maxSpeedSeen
	end

	local a, maxSpeedA = simulate()
	local b, maxSpeedB = simulate()
	check(
		a.x == b.x and a.y == b.y and a.z == b.z and a.vx == b.vx and a.vy == b.vy and a.vz == b.vz,
		"同じ入力列からは必ず同じ最終状態になる (クライアント予測との整合)"
	)
	local hardCap = TRAINER.maxSpeed * Config.flight.boost.multiplier + 1e-6
	check(
		maxSpeedA <= hardCap,
		"ブースト込みでも速度が上限 (maxSpeed * boost.multiplier) を超えない",
		string.format("%.1f <= %.1f", maxSpeedA, hardCap)
	)

	-- クールダウン中は連続でブーストを起動できない
	local boostState = FlightModel.newState(0, 300, 0, TRAINER)
	boostState.grounded = false
	local boostInput = noInput(1)
	boostInput.throttleInput = 1
	boostInput.boost = true
	FlightModel.step(boostState, boostInput, 0.1, TRAINER, Config)
	check(boostState.boostRemaining > 0, "ブースト入力で boostRemaining が立つ")
	local remainingBefore = boostState.boostCooldown
	-- step() は1回あたり maxStepDelta で dt を頭打ちにするので、複数回に分けて経過させる
	boostInput.boost = false
	local elapsed = 0
	while elapsed < Config.flight.boost.duration + 0.5 do
		FlightModel.step(boostState, boostInput, Config.anticheat.maxStepDelta, TRAINER, Config)
		elapsed += Config.anticheat.maxStepDelta
	end
	check(boostState.boostRemaining == 0, "ブースト時間が尽きると boostRemaining は0に戻る")
	check(boostState.boostCooldown < remainingBefore, "クールダウンは時間経過で減っていく")
end

-- ── 4. ミッション生成 ────────────────────────────────────
section("ミッション生成")
do
	local terminals = {
		{ id = "central", x = 0, y = 0, z = 0 },
		{ id = "north", x = 0, y = 0, z = -1400 },
		{ id = "east", x = 1400, y = 0, z = 900 },
		{ id = "south", x = -900, y = 0, z = 1300 },
	}
	local cfg = Config.mission

	local a = Mission.generate(1, 1, terminals, 4, cfg)
	local b = Mission.generate(1, 1, terminals, 4, cfg)
	check(
		a.id == b.id and a.originId == b.originId and a.destId == b.destId and a.reward == b.reward,
		"同じ (seed, index) からは同じミッションが生成される"
	)

	local differs = false
	local prev = nil
	for i = 1, 8 do
		local m = Mission.generate(5, i, terminals, 4, cfg)
		check(m.originId ~= m.destId, string.format("ミッション#%d: 出発地と目的地は異なる", i))
		check(m.distance > 0, string.format("ミッション#%d: 距離は正の値", i))
		check(m.cargoWeight >= 1 and m.cargoWeight <= 4, string.format("ミッション#%d: 積載量が範囲内", i))
		check(
			m.weatherMultiplier >= cfg.weatherMultiplierRange.min and m.weatherMultiplier <= cfg.weatherMultiplierRange.max,
			string.format("ミッション#%d: 天候倍率が範囲内", i)
		)
		local expectedReward = Mission.reward(m.distance, m.cargoWeight, m.weatherMultiplier, cfg)
		check(math.abs(m.reward - expectedReward) < 1e-9, string.format("ミッション#%d: 報酬が計算式と一致", i))
		local expectedTime = Mission.timeLimit(m.distance, cfg)
		check(math.abs(m.timeLimit - expectedTime) < 1e-9, string.format("ミッション#%d: 制限時間が計算式と一致", i))
		if prev and (m.originId ~= prev.originId or m.destId ~= prev.destId) then
			differs = true
		end
		prev = m
	end
	check(differs, "index を変えると異なるミッションが生成される")

	-- 距離が長いほど報酬も制限時間も大きい
	check(
		Mission.reward(2000, 1, 1, cfg) > Mission.reward(500, 1, 1, cfg),
		"距離が長いほど報酬が大きい"
	)
	check(
		Mission.timeLimit(2000, cfg) > Mission.timeLimit(500, cfg),
		"距離が長いほど制限時間が長い"
	)
	check(
		Mission.reward(500, 4, 1, cfg) > Mission.reward(500, 1, 1, cfg),
		"積載量が多いほど報酬が大きい"
	)

	-- 成否判定
	local m = Mission.generate(9, 1, terminals, 4, cfg)
	local onTime = Mission.evaluate(m, m.timeLimit - 5, cfg)
	check(onTime.success and onTime.payout > m.reward, "制限時間内に届ければ成功し、タイムボーナスが乗る")
	local late = Mission.evaluate(m, m.timeLimit + 0.01, cfg)
	check(not late.success and late.payout == 0, "制限時間を過ぎると失敗扱いで支払いは0")
	local exact = Mission.evaluate(m, m.timeLimit, cfg)
	check(exact.success, "ちょうど制限時間ぴったりは成功扱い")

	-- 受注上限
	check(Mission.canAccept(2, 3), "上限未満なら受注できる")
	check(not Mission.canAccept(3, 3), "上限に達したら受注できない")

	-- 着地判定
	check(Mission.isValidDropoff(cfg.dropRadius, true, true, cfg), "半径ちょうどは成功")
	check(not Mission.isValidDropoff(cfg.dropRadius + 0.01, true, true, cfg), "半径を超えたら失敗")
	check(not Mission.isValidDropoff(0, false, true, cfg), "空中では着地扱いにならない")
	check(not Mission.isValidDropoff(0, true, false, cfg), "着陸装置を出していないと着地扱いにならない")
end

-- ── 5. 不正対策 (AntiCheat) ──────────────────────────────
section("移動申告の受理条件")
do
	local cfg = Config.anticheat
	local maxSpeed = TRAINER.maxSpeed

	local record = AntiCheat.newRecord()
	local ok1 = AntiCheat.check(record, 0, 0, 0, 0, maxSpeed, cfg)
	check(ok1, "初回の申告は無条件で通る (基準点がまだ無い)")
	AntiCheat.commit(record, 0, 0, 0, 0)

	local _, dupReason = AntiCheat.check(record, 0, 1, 0, 0, maxSpeed, cfg)
	check(dupReason == "non_monotonic_time", "同時刻・過去時刻の申告を弾く")

	local _, floodReason = AntiCheat.check(record, cfg.minInputInterval * 0.5, 0.1, 0, 0, maxSpeed, cfg)
	check(floodReason == "rate_limit", "送信間隔が短すぎる申告を弾く (フラッド対策)")

	local dt = 1.0
	local plausible = maxSpeed * cfg.speedTolerance * dt * 0.5
	local okReason = AntiCheat.check(record, dt, plausible, 0, 0, maxSpeed, cfg)
	check(okReason, "最高速度の範囲内の移動は通る")

	local _, teleportReason =
		AntiCheat.check(record, dt, maxSpeed * cfg.speedTolerance * dt + cfg.graceDistance + 50, 0, 0, maxSpeed, cfg)
	check(teleportReason == "impossible_move", "テレポート級の移動を弾く")

	-- グレース距離ぶんは超過扱いにしない (境界値)。check 内部でも dt は
	-- maxStepDelta で頭打ちにするので、期待値の計算でも同じ頭打ちを行う。
	local clampedDt = math.min(dt, cfg.maxStepDelta)
	local atBoundary = maxSpeed * cfg.speedTolerance * clampedDt + cfg.graceDistance
	local boundaryOk = AntiCheat.check(record, dt, atBoundary, 0, 0, maxSpeed, cfg)
	check(boundaryOk, "許容距離ちょうどは通る (境界値)")

	-- commit を挟んで連続移動しても正しく基準点が更新される
	local chain = AntiCheat.newRecord()
	AntiCheat.commit(chain, 0, 0, 0, 0)
	local t = 0
	local allOk = true
	for i = 1, 20 do
		t += 1.0
		local step = maxSpeed * 0.4 * 1.0
		local ok = AntiCheat.check(chain, t, step * i, 0, 0, maxSpeed, cfg)
		if not ok then
			allOk = false
		end
		AntiCheat.commit(chain, t, step * i, 0, 0)
	end
	check(allOk, "妥当な速度で連続移動しても弾かれない")
end

-- ── 6. 設定値の整合性 ────────────────────────────────────
section("設定値の整合性")
do
	check(Config.world.ceiling > Config.flight.groundHeight, "高度上限は地上より高い")
	check(Config.world.killY < Config.flight.groundHeight, "キル高度は地上より低い")
	check(Config.mission.dropRadius > 0, "着地判定半径は正の値")
	check(Config.mission.maxActiveMissions > 0, "同時受注上限は正の値")
	check(
		Config.anticheat.minInputInterval < 1 / Config.gamepad.inputHz,
		"移動申告の最小間隔は入力送信間隔より短い (正当な入力を弾かない)"
	)
	check(Config.aircraft[Config.defaultAircraft].price == 0, "初期所持機は無料")

	for name, stats in Config.aircraft do
		check(
			stats.maxSpeed > Config.flight.minSpeed,
			string.format("%s: 最高速度が失速速度より速い (飛行が成立する)", name)
		)
		check(
			stats.maxSpeed >= Config.flight.takeoffMinSpeed,
			string.format("%s: 最高速度が離陸速度以上 (離陸できる)", name)
		)
		check(stats.accel > 0, string.format("%s: 加速度は正の値", name))
		check(stats.turnRate > 0, string.format("%s: 旋回速度は正の値", name))
		check(stats.fuelCapacity > 0, string.format("%s: 燃料タンク容量は正の値", name))
	end

	for name, upgrade in Config.upgrades do
		check(upgrade.maxLevel >= 1, string.format("アップグレード %s: 最大レベルは1以上", name))
		check(upgrade.costBase > 0 and upgrade.costGrowth > 1, string.format("アップグレード %s: コスト設定が単調増加", name))
	end

	check(Config.flight.boost.multiplier > 1, "ブースト倍率は1より大きい")
	check(Config.flight.boost.cooldown > Config.flight.boost.duration, "ブーストのクールダウンは持続時間より長い")
	check(Config.broadcast.rateHz > 0 and Config.broadcast.rateHz <= Config.gamepad.inputHz, "配信頻度は入力送信頻度以下")
end

-- ── 結果 ──────────────────────────────────────────────
print(string.format("\n%d checks, %d failed", checks, failures))
if failures > 0 then
	error(string.format("%d 件の検証に失敗しました", failures), 0)
end
print("すべて通過")
