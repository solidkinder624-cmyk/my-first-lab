--!nonstrict
-- 「痕跡だけの迷路」の純ロジック検証器。
--
--   luau roblox/trace-only/verify.luau
--
-- games/geometry-dash/verify.mjs と同じ考え方で、ゲーム本体が実際に使う
-- Grid.luau / Motion.luau / Config.luau を そのまま require して回す。
-- Roblox Studio を開かずに、迷路が必ず連結であること・壁をすり抜けないこと・
-- しゃがみが本当に無音であること等を CI で担保するのが目的。

local Config = require("./src/shared/Config")
local Grid = require("./src/shared/Grid")
local Motion = require("./src/shared/Motion")

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

local function copyConfig(overrides)
	local out = {}
	for k, v in Config do
		if type(v) == "table" then
			local t = {}
			for k2, v2 in v do
				t[k2] = if type(v2) == "table" then table.clone(v2) else v2
			end
			out[k] = t
		else
			out[k] = v
		end
	end
	for k, v in overrides or {} do
		for k2, v2 in v do
			out[k][k2] = v2
		end
	end
	return out
end

-- ── 1. 迷路の生成 ──────────────────────────────────────
section("迷路生成")
do
	local perfectOk, connectedOk, boundaryOk = true, true, true
	local seedsTested = 0
	for seed = 1, 120 do
		local cw, ch = 8, 8
		local grid = Grid.generate(cw, ch, seed, 0) -- braid=0 = 完全迷路
		local open = Grid.openTiles(grid)
		-- 完全迷路: セル数 + 壁を壊した回数(セル数-1) だけ開通しているはず
		if #open ~= cw * ch + (cw * ch - 1) then
			perfectOk = false
		end
		local dist = Grid.distances(grid, open[1].x, open[1].z)
		local reached = 0
		for _, tile in open do
			if Grid.distanceAt(grid, dist, tile.x, tile.z) ~= nil then
				reached += 1
			end
		end
		if reached ~= #open then
			connectedOk = false
		end
		-- 外周は必ず壁 (外に出られる穴が無い)
		for tx = 0, grid.w - 1 do
			if not Grid.isSolid(grid, tx, 0) or not Grid.isSolid(grid, tx, grid.h - 1) then
				boundaryOk = false
			end
		end
		for tz = 0, grid.h - 1 do
			if not Grid.isSolid(grid, 0, tz) or not Grid.isSolid(grid, grid.w - 1, tz) then
				boundaryOk = false
			end
		end
		seedsTested += 1
	end
	check(perfectOk, "braid=0 のとき完全迷路 (開通タイル数が 2*cells-1)")
	check(connectedOk, string.format("全開通タイルが連結 (seed 1..%d)", seedsTested))
	check(boundaryOk, "外周がすべて壁 (マップ外へ出られない)")
end

do
	-- braid ありでも連結性は保たれ、ループが増えていること
	local loopOk, connectedOk = true, true
	local extraTotal = 0
	for seed = 1, 60 do
		local plain = Grid.generate(8, 8, seed, 0)
		local braided = Grid.generate(8, 8, seed, Config.braid)
		local extra = #Grid.openTiles(braided) - #Grid.openTiles(plain)
		extraTotal += extra
		if extra < 0 then
			loopOk = false
		end
		local open = Grid.openTiles(braided)
		local dist = Grid.distances(braided, open[1].x, open[1].z)
		for _, tile in open do
			if Grid.distanceAt(braided, dist, tile.x, tile.z) == nil then
				connectedOk = false
			end
		end
	end
	check(connectedOk, "braid 適用後も全タイルが連結")
	check(extraTotal > 0, "braid が実際に行き止まりを開通させている", string.format("追加開通 %d タイル/60seed", extraTotal))
end

do
	-- 同じ seed なら完全に同じ迷路 (サーバ/クライアントで一致することの保証)
	local a = Grid.generate(10, 10, 4242, Config.braid)
	local b = Grid.generate(10, 10, 4242, Config.braid)
	local same = true
	for i = 1, a.w * a.h do
		if a.solid[i] ~= b.solid[i] then
			same = false
		end
	end
	local c = Grid.generate(10, 10, 4243, Config.braid)
	local differs = false
	for i = 1, a.w * a.h do
		if a.solid[i] ~= c.solid[i] then
			differs = true
		end
	end
	check(same, "同一 seed は同一の迷路 (クライアント予測が成立する前提)")
	check(differs, "異なる seed では迷路が変わる")
end

do
	-- 壁のマージ結果が元の壁集合と完全一致するか (MapBuilder が作るパーツの正しさ)
	local grid = Grid.generate(9, 9, 77, Config.braid)
	local covered = {}
	local overlap = false
	for _, run in Grid.wallRuns(grid) do
		for i = 0, run.length - 1 do
			local key = run.z * grid.w + run.x + i
			if covered[key] then
				overlap = true
			end
			covered[key] = true
		end
	end
	local exact = not overlap
	for tz = 0, grid.h - 1 do
		for tx = 0, grid.w - 1 do
			local key = tz * grid.w + tx
			if Grid.isSolid(grid, tx, tz) ~= (covered[key] == true) then
				exact = false
			end
		end
	end
	local runs = #Grid.wallRuns(grid)
	local solidCount = 0
	for i = 1, grid.w * grid.h do
		if grid.solid[i] then
			solidCount += 1
		end
	end
	check(exact, "wallRuns が壁タイルを過不足なく被覆する")
	check(runs < solidCount * 0.6, "wallRuns でパーツ数が削減されている", string.format("%d パーツ / 壁 %d タイル", runs, solidCount))
end

-- ── 2. 移動と当たり判定 ────────────────────────────────
section("移動・当たり判定")

-- ランダムな入力で暴れさせ、壁にめり込まないかを見る
local function fuzz(cfg, seconds: number, seed: number, forceSprint: boolean?)
	local grid = Grid.generate(Config.mazeCells.w, Config.mazeCells.h, seed, Config.braid)
	local open = Grid.openTiles(grid)
	local rng = Grid.newRng(seed * 7919 + 13)
	local spawn = open[Grid.nextInt(rng, #open) + 1]
	local sx, sz = Grid.center(grid, spawn.x, spawn.z)
	local state = Motion.newState(sx, sz, cfg)
	local dt = 1 / cfg.net.tickRate
	local worst = 0
	local traces = {}
	local input = Motion.emptyInput()
	local steps = math.floor(seconds / dt)

	for i = 1, steps do
		if i % 12 == 1 then -- 数tickごとに方向転換
			local angle = Grid.nextFloat(rng) * math.pi * 2
			input = Motion.sanitize({
				seq = i,
				moveX = math.cos(angle),
				moveZ = math.sin(angle),
				jump = Grid.nextFloat(rng) < 0.15,
				sprint = forceSprint or Grid.nextFloat(rng) < 0.5,
				crouch = (not forceSprint) and Grid.nextFloat(rng) < 0.2,
			}, cfg)
		end
		for _, t in Motion.step(state, input, dt, grid, cfg) do
			traces[t.kind] = (traces[t.kind] or 0) + 1
		end

		-- 壁へのめり込み量を測る
		local tx, tz = Grid.tileOf(grid, state.x, state.z)
		for dz = -1, 1 do
			for dx = -1, 1 do
				if Grid.isSolid(grid, tx + dx, tz + dz) then
					local t = grid.tileSize
					local minX, maxX = (tx + dx) * t, (tx + dx + 1) * t
					local minZ, maxZ = (tz + dz) * t, (tz + dz + 1) * t
					local ox = state.x - math.clamp(state.x, minX, maxX)
					local oz = state.z - math.clamp(state.z, minZ, maxZ)
					local pen = cfg.player.radius - math.sqrt(ox * ox + oz * oz)
					if pen > worst then
						worst = pen
					end
				end
			end
		end
	end
	return state, worst, traces, grid
end

do
	local worstAll, outOfBounds, staminaOk = 0, false, true
	for seed = 1, 25 do
		local state, worst, _, grid = fuzz(Config, 20, seed)
		worstAll = math.max(worstAll, worst)
		if Grid.isSolidAtWorld(grid, state.x, state.z) then
			outOfBounds = true
		end
		if state.stamina < 0 or state.stamina > Config.stamina.max then
			staminaOk = false
		end
	end
	check(worstAll < 1e-3, "ランダム入力25本×20秒で壁にめり込まない", string.format("最大めり込み %.2e studs", worstAll))
	check(not outOfBounds, "プレイヤーが壁タイルの中に入り込まない")
	check(staminaOk, "スタミナが 0..max に収まる")
end

do
	-- 異常な速度でもすり抜けない (サブステップ分割の検証)
	local cfg = copyConfig({ move = { sprintSpeed = 400, walkSpeed = 400, accel = 4000 } })
	local worstAll = 0
	for seed = 1, 10 do
		local _, worst = fuzz(cfg, 12, seed + 500, true)
		worstAll = math.max(worstAll, worst)
	end
	check(worstAll < 1e-3, "速度400 studs/s でも壁をすり抜けない", string.format("最大めり込み %.2e studs", worstAll))
end

do
	-- 同じ入力列なら同じ軌跡 (クライアント予測とサーバ権威が一致する条件)
	local a = fuzz(Config, 10, 31)
	local b = fuzz(Config, 10, 31)
	check(
		math.abs(a.x - b.x) < 1e-12 and math.abs(a.z - b.z) < 1e-12,
		"同一入力・同一 seed で軌跡が完全一致 (決定論)"
	)
end

-- ── 3. 痕跡のルール (ゲーム性の核) ──────────────────────
section("痕跡のルール")

-- まっすぐ一定時間歩かせて、出た痕跡を数える
local function walkStraight(cfg, stanceInput, seconds: number)
	-- 壁のない広間で計測する (痕跡の数だけを見たいので迷路の影響を除く)
	local grid = Grid.generate(2, 2, 1, 0)
	grid.resolve = function(x, z)
		return x, z, false, false
	end
	local state = Motion.newState(100, 100, cfg)
	local dt = 1 / cfg.net.tickRate
	local counts = {}
	local startX = state.x
	local input = Motion.sanitize(stanceInput, cfg)
	for i = 1, math.floor(seconds / dt) do
		input.seq = i
		for _, t in Motion.step(state, input, dt, grid, cfg) do
			counts[t.kind] = (counts[t.kind] or 0) + 1
		end
	end
	return counts, math.abs(state.x - startX), state
end

do
	local walkCounts, walkDist = walkStraight(Config, { moveX = 1, moveZ = 0 }, 12)
	local sprint = walkStraight(Config, { moveX = 1, moveZ = 0, sprint = true }, 12)
	local crouch, crouchDist = walkStraight(Config, { moveX = 1, moveZ = 0, crouch = true }, 12)

	check((crouch.Step or 0) == 0 and (crouch.SprintStep or 0) == 0, "しゃがみ移動は足跡を一切出さない")
	check(crouchDist > 0, "しゃがみでもちゃんと前進する", string.format("%.1f studs/12s", crouchDist))
	check(crouchDist < walkDist, "しゃがみは歩きより遅い", string.format("%.1f < %.1f studs", crouchDist, walkDist))
	check((walkCounts.Step or 0) > 0, "歩行は足跡を出す", string.format("%d 個/12s", walkCounts.Step or 0))
	check(
		(sprint.SprintStep or 0) > (walkCounts.Step or 0),
		"ダッシュは歩行より多く痕跡を残す",
		string.format("sprint %d vs walk %d", sprint.SprintStep or 0, walkCounts.Step or 0)
	)
	check(
		Config.trace.SprintStep.radius > Config.trace.Step.radius,
		"ダッシュの痕跡はより遠くのプレイヤーにも届く"
	)
end

do
	-- 距離あたりの足跡密度が Config どおりか (Step.distance ごとに1個)
	local counts, dist = walkStraight(Config, { moveX = 1, moveZ = 0 }, 20)
	local expected = math.floor(dist / Config.trace.Step.distance)
	check(
		math.abs((counts.Step or 0) - expected) <= 1,
		"足跡は Config.trace.Step.distance ごとに1個",
		string.format("実測 %d / 期待 %d (移動 %.1f studs)", counts.Step or 0, expected, dist)
	)
end

do
	-- ジャンプ: 踏み切りと着地で波紋が1回ずつ、スタミナを消費
	local grid = Grid.generate(2, 2, 1, 0)
	grid.resolve = function(x, z)
		return x, z, false, false
	end
	local state = Motion.newState(100, 100, Config)
	local dt = 1 / Config.net.tickRate
	local counts = {}
	local before = state.stamina
	local afterTakeoff = before
	for i = 1, 60 do
		local input = Motion.sanitize({ seq = i, jump = i == 1 }, Config)
		for _, t in Motion.step(state, input, dt, grid, Config) do
			counts[t.kind] = (counts[t.kind] or 0) + 1
		end
		if i == 1 then
			afterTakeoff = state.stamina
		end
	end
	check((counts.Jump or 0) == 1, "ジャンプ踏み切りで波紋1回", string.format("%d 回", counts.Jump or 0))
	check((counts.Land or 0) == 1, "着地で波紋1回", string.format("%d 回", counts.Land or 0))
	check(Config.trace.Land.radius > Config.trace.Jump.radius, "着地の方が踏み切りより広く伝わる")
	check(
		afterTakeoff <= before - Config.stamina.jumpCost + 1,
		"ジャンプでスタミナを消費する",
		string.format("%.1f → %.1f", before, afterTakeoff)
	)
end

do
	-- しゃがみで距離を貯めてから立っても、足跡がまとめて出たりしない
	local grid = Grid.generate(2, 2, 1, 0)
	grid.resolve = function(x, z)
		return x, z, false, false
	end
	local state = Motion.newState(100, 100, Config)
	local dt = 1 / Config.net.tickRate
	for i = 1, 300 do
		Motion.step(state, Motion.sanitize({ seq = i, moveX = 1, crouch = true }, Config), dt, grid, Config)
	end
	local burst = 0
	for _, t in Motion.step(state, Motion.sanitize({ seq = 999, moveX = 1 }, Config), dt, grid, Config) do
		if t.kind == "Step" then
			burst += 1
		end
	end
	check(burst == 0, "しゃがみ後に立っても足跡がまとめて噴き出さない", string.format("%d 個", burst))
end

-- ── 4. 入力の正規化 (チート対策) ────────────────────────
section("入力の正規化")
do
	local hacked = Motion.sanitize({ seq = 1, moveX = 50, moveZ = 0 }, Config)
	check(math.abs(hacked.moveX) <= 1 + 1e-9, "長さ>1 の移動ベクトルは 1 に丸められる", string.format("%.3f", hacked.moveX))

	local nan = Motion.sanitize({ seq = 1, moveX = 0 / 0, moveZ = 0 / 0 }, Config)
	check(nan.moveX == 0 and nan.moveZ == 0, "NaN 入力は 0 に落とされる")

	local junk = Motion.sanitize("not a table", Config)
	check(junk.moveX == 0 and junk.jump == false, "テーブル以外が来ても落ちない")

	local truthy = Motion.sanitize({ seq = 1, jump = 1, sprint = "yes" }, Config)
	check(truthy.jump == false and truthy.sprint == false, "boolean 以外のボタン値は false 扱い")

	-- 巨大な dt を渡しても maxStepDelta で頭打ちになる
	local grid = Grid.generate(2, 2, 1, 0)
	grid.resolve = function(x, z)
		return x, z, false, false
	end
	local state = Motion.newState(100, 100, Config)
	Motion.step(state, Motion.sanitize({ seq = 1, moveX = 1 }, Config), 10, grid, Config)
	local moved = state.x - 100
	local bound = Config.move.sprintSpeed * Config.move.maxStepDelta
	check(moved <= bound + 1e-9, "巨大な dt を送っても 1tick 分しか進めない", string.format("%.3f <= %.3f studs", moved, bound))
end

-- ── 結果 ──────────────────────────────────────────────
print(string.format("\n%d checks, %d failed", checks, failures))
if failures > 0 then
	error(string.format("%d 件の検証に失敗しました", failures), 0)
end
print("すべて通過")
