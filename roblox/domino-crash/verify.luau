--!nonstrict
-- 「ドミノ・クラッシュ PvP」の純ロジック検証器。
--
--   luau roblox/domino-crash/verify.luau
--
-- roblox/trace-only/verify.luau と同じ考え方で、ゲーム本体が実際に使う
-- Config / Blueprint / Collapse / Progress / HitRules を そのまま require して回す。
-- Roblox Studio を開かずに、
--   * 構造物が生成直後に自壊しないこと (全ブロックが支持されている)
--   * 弱点を叩けば大きく崩れ、端を叩いても崩れないこと (= 見極めがゲームになる)
--   * 地上から届く範囲の打撃だけで必ず100%まで壊し切れること (詰み配置が無い)
--   * 両プレイヤーの構造物がビット単位で同一であること (対戦の公平性)
-- を CI で担保するのが目的。

local Config = require("./src/shared/Config")
local Blueprint = require("./src/shared/Blueprint")
local Collapse = require("./src/shared/Collapse")
local Progress = require("./src/shared/Progress")
local HitRules = require("./src/shared/HitRules")

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

local function pct(a: number, b: number): string
	return string.format("%.1f%%", a / b * 100)
end

-- 構造物を1回だけ作って使い回すためのキャッシュ (compile は安くはない)
local cache = {}
local function structureFor(kind: string, seed: number)
	local key = kind .. ":" .. seed
	if not cache[key] then
		local blueprint = Blueprint.generate(kind, seed, Config.build)
		cache[key] = {
			blueprint = blueprint,
			compiled = Collapse.compile(blueprint.blocks, Config.support),
		}
	end
	return cache[key]
end

local KINDS = Config.build.kinds
local SEEDS = { 1, 4242, 987654 }

-- ── 1. 構造物の生成 ─────────────────────────────────────
section("構造物の生成")
do
	for _, kind in KINDS do
		local blueprint = structureFor(kind, SEEDS[1]).blueprint
		local counts = Blueprint.countByKind(blueprint)
		local parts = {}
		for name, n in counts do
			table.insert(parts, string.format("%s=%d", name, n))
		end
		table.sort(parts)
		check(
			#blueprint.blocks >= 700 and #blueprint.blocks <= 4000,
			string.format("%s のブロック数が実用域 (700〜4000)", kind),
			string.format("%d個  %s", #blueprint.blocks, table.concat(parts, " "))
		)
		check(
			blueprint.keyCount > 0,
			string.format("%s にキーパーツがある", kind),
			tostring(blueprint.keyCount) .. "個"
		)
	end

	-- 同じシードなら完全に同じ構造物 = 対戦相手と同じ物を壊すことになる
	local identical = true
	local differs = false
	for _, kind in KINDS do
		local a = Blueprint.generate(kind, 777, Config.build)
		local b = Blueprint.generate(kind, 777, Config.build)
		if #a.blocks ~= #b.blocks then
			identical = false
		else
			for i, ba in a.blocks do
				local bb = b.blocks[i]
				if ba.cx ~= bb.cx or ba.cy ~= bb.cy or ba.cz ~= bb.cz or ba.kind ~= bb.kind or ba.key ~= bb.key then
					identical = false
					break
				end
			end
		end
	end
	check(identical, "同じシードなら両プレイヤーに完全同一の構造物が渡る")

	-- 乱数を使う構造物 (Tower/Fortress) はシードで見た目が変わる
	for _, kind in { "Tower", "Fortress" } do
		local a = Blueprint.generate(kind, 1, Config.build)
		local b = Blueprint.generate(kind, 2, Config.build)
		if #a.blocks ~= #b.blocks then
			differs = true
		else
			for i, ba in a.blocks do
				if ba.kind ~= b.blocks[i].kind then
					differs = true
					break
				end
			end
		end
	end
	check(differs, "シードを変えると Tower / Fortress の窓抜きが変わる")

	-- ブロック同士がめり込んでいない (めり込みは物理の暴発 = 生成直後の自壊になる)
	local overlapOk = true
	local worst = 0
	for _, kind in KINDS do
		local blocks = structureFor(kind, SEEDS[1]).blueprint.blocks
		for i = 1, #blocks do
			local a = blocks[i]
			for j = i + 1, #blocks do
				local b = blocks[j]
				local ox = math.min(a.cx + a.sx / 2, b.cx + b.sx / 2) - math.max(a.cx - a.sx / 2, b.cx - b.sx / 2)
				local oy = math.min(a.cy + a.sy / 2, b.cy + b.sy / 2) - math.max(a.cy - a.sy / 2, b.cy - b.sy / 2)
				local oz = math.min(a.cz + a.sz / 2, b.cz + b.sz / 2) - math.max(a.cz - a.sz / 2, b.cz - b.sz / 2)
				local penetration = math.min(ox, oy, oz)
				if penetration > 1e-6 then
					overlapOk = false
					worst = math.max(worst, penetration)
				end
			end
		end
	end
	check(
		overlapOk,
		"ブロック同士がめり込んでいない",
		if overlapOk then nil else string.format("最大 %.3f studs", worst)
	)

	-- 構造物がアリーナのスロットに収まる (瓦礫が隣の試合場へ飛び込まない)
	local fits = true
	local report = ""
	local half = Config.arena.floorSize * 0.5
	for _, kind in KINDS do
		local b = structureFor(kind, SEEDS[1]).blueprint.bounds
		local radius = math.max(math.abs(b.minX), math.abs(b.maxX), math.abs(b.minZ), math.abs(b.maxZ))
		if radius > half then
			fits = false
			report = string.format("%s が %.0f studs (床の半分 %.0f)", kind, radius, half)
		end
	end
	check(fits, "どの構造物もスロットの床に収まる", report ~= "" and report or nil)

	local spacingOk = true
	for _, kind in KINDS do
		local b = structureFor(kind, SEEDS[1]).blueprint.bounds
		local diagonal = math.sqrt((b.maxX - b.minX) ^ 2 + (b.maxZ - b.minZ) ^ 2)
		if Config.arena.slotSpacing <= diagonal then
			spacingOk = false
		end
	end
	check(
		spacingOk,
		"スロット間隔が構造物の対角より広い",
		string.format("%d studs", Config.arena.slotSpacing)
	)
end

-- ── 2. 支持構造 ─────────────────────────────────────────
section("支持構造 (生成直後の安定性)")
do
	for _, kind in KINDS do
		for _, seed in SEEDS do
			local entry = structureFor(kind, seed)
			local run = Collapse.newRun(entry.compiled)
			local standing = Collapse.standingCount(run)
			local total = entry.compiled.count
			check(
				standing == total,
				string.format("%s (seed %d) は生成直後に1個も落ちない", kind, seed),
				string.format("%d / %d", standing, total)
			)
		end
	end

	-- 接地ブロックが存在し、かつ全体の一部でしかない (= 上に積み上がっている)
	for _, kind in KINDS do
		local compiled = structureFor(kind, SEEDS[1]).compiled
		local grounded = 0
		for i = 1, compiled.count do
			if compiled.grounded[i] then
				grounded += 1
			end
		end
		check(
			grounded > 0 and grounded < compiled.count,
			string.format("%s に接地ブロックがある", kind),
			string.format("%d個 (%s)", grounded, pct(grounded, compiled.count))
		)
	end

	-- 詰め物 (Wall) を全部消しても構造は立っている = 壁は荷重を伝えていない。
	-- これが「壁をいくら叩いても崩れない / 柱を折れば崩れる」の裏付けになる。
	for _, kind in KINDS do
		local compiled = structureFor(kind, SEEDS[1]).compiled
		local run = Collapse.newRun(compiled)
		local removed = 0
		for i = 1, compiled.count do
			if not compiled.blocks[i].bearing then
				run.freed[i] = true
				run.freedCount += 1
				removed += 1
			end
		end
		local standing = Collapse.standingCount(run)
		check(
			standing == compiled.count - removed,
			string.format("%s: 詰め物を全部消しても骨組みは立っている", kind),
			string.format("詰め物 %d個を除去 → 残り %d個すべて自立", removed, standing)
		)
	end

	-- 接地ブロックを全部消したら全損する = 荷重は必ず地面へ向かっている
	for _, kind in KINDS do
		local compiled = structureFor(kind, SEEDS[1]).compiled
		local run = Collapse.newRun(compiled)
		for i = 1, compiled.count do
			if compiled.grounded[i] then
				run.freed[i] = true
				run.freedCount += 1
			end
		end
		check(Collapse.standingCount(run) == 0, string.format("%s は接地ブロックを失うと全損する", kind))
	end
end

-- ── 3. 弱点 (キーパーツ) が意味を持つか ─────────────────
section("弱点の見極めがゲームになるか")
do
	local hammer = Config.hammer
	local physics = Config.physics

	-- 「同じ高さで、柱を狙うか壁を狙うか」の差を見る。高さの差ではなく
	-- 狙う場所の差でリターンが変わることが、このゲームの唯一の腕前だから。
	local function lowestKey(blocks)
		local best = nil
		for _, b in blocks do
			if b.key and b.cy <= hammer.reach then
				if best == nil or b.cy < best.cy or (b.cy == best.cy and b.id < best.id) then
					best = b
				end
			end
		end
		return best
	end

	-- 比較対象の「壁」は、いちばん低い層のうち キーパーツからいちばん遠い ものを選ぶ。
	-- 柱の隣の壁を叩けば柱も爆発半径に入ってしまい、比較にならないため。
	local function farthestInfill(blocks)
		local floorY = math.huge
		for _, b in blocks do
			if not b.key then
				floorY = math.min(floorY, b.cy)
			end
		end
		local best, bestGap = nil, -1
		for _, b in blocks do
			if not b.key and b.cy <= floorY + 1e-6 then
				local gap = math.huge
				for _, k in blocks do
					if k.key then
						gap = math.min(gap, math.sqrt((b.cx - k.cx) ^ 2 + (b.cy - k.cy) ^ 2 + (b.cz - k.cz) ^ 2))
					end
				end
				if gap > bestGap then
					best, bestGap = b, gap
				end
			end
		end
		return best, bestGap
	end

	local function ratioOf(entry, target)
		local run = Collapse.newRun(entry.compiled)
		local result = Collapse.hit(run, target.cx, target.cy, target.cz, hammer.blastRadius, hammer, physics)
		return run.freedCount / entry.compiled.count, result
	end

	for _, kind in KINDS do
		local entry = structureFor(kind, SEEDS[1])
		local blocks = entry.blueprint.blocks

		local keyTarget = lowestKey(blocks)
		local wallTarget, wallGap = farthestInfill(blocks)
		assert(keyTarget and wallTarget, "足元に柱と詰め物の両方が無い: " .. kind)
		check(
			wallGap > hammer.blastRadius,
			string.format("%s: 柱から爆発半径ぶん離れた詰め物が存在する", kind),
			string.format("%.1f studs > %.1f", wallGap, hammer.blastRadius)
		)

		local keyRatio, keyResult = ratioOf(entry, keyTarget)
		local wallRatio = ratioOf(entry, wallTarget)

		-- 天辺の隅 = 構造的にどうでもいい場所
		local top = nil
		for _, b in blocks do
			if top == nil or b.cy > top.cy then
				top = b
			end
		end
		local topRatio = ratioOf(entry, top)

		check(
			keyResult.keyHit,
			string.format("%s: 足元の柱への打撃がキーパーツ判定になる", kind),
			string.format("%s (高さ %.1f)", keyTarget.kind, keyTarget.cy)
		)
		check(
			keyRatio > wallRatio * 3,
			string.format("%s: 同じ高さでも柱を狙えば詰め物の3倍以上崩れる", kind),
			string.format("柱 %.1f%% vs 詰め物 %.1f%%", keyRatio * 100, wallRatio * 100)
		)
		check(
			#keyResult.chain > #keyResult.direct,
			string.format("%s: 柱を折ると直撃より連鎖の方が多く崩れる", kind),
			string.format("直撃 %d → 連鎖 %d", #keyResult.direct, #keyResult.chain)
		)
		check(
			topRatio < 0.08,
			string.format("%s: 天辺を叩いても全体の8%%未満しか崩れない (近道にならない)", kind),
			string.format("%.1f%%", topRatio * 100)
		)
	end
end

-- ── 4. 必ず壊し切れるか (詰み配置が無いこと) ────────────
section("制限時間内に100%到達できるか")
do
	local hammer = Config.hammer
	local physics = Config.physics
	local maxHits = math.floor(Config.match.duration * hammer.maxHitsPerSecond)

	for _, kind in KINDS do
		for _, seed in SEEDS do
			local entry = structureFor(kind, seed)
			local run = Collapse.newRun(entry.compiled)
			local hits = 0
			local monotone = true
			local previous = 0
			local stalled = false

			while run.freedCount < entry.compiled.count and hits < maxHits do
				-- 地上のプレイヤーが実際に狙える範囲 (reach 以内の高さ) の
				-- いちばん低いブロックを叩く、という素朴な戦略
				local target = nil
				for i = 1, entry.compiled.count do
					if not run.freed[i] then
						local b = entry.compiled.blocks[i]
						if b.cy <= hammer.reach and (target == nil or b.cy < target.cy) then
							target = b
						end
					end
				end
				if target == nil then
					stalled = true
					break
				end
				Collapse.hit(run, target.cx, target.cy, target.cz, hammer.blastRadius, hammer, physics)
				hits += 1
				if run.freedCount < previous then
					monotone = false
				end
				previous = run.freedCount
			end

			check(
				not stalled,
				string.format("%s (seed %d): 地上から届かない浮遊ブロックが残らない", kind, seed),
				if stalled then string.format("%d個 残存", entry.compiled.count - run.freedCount) else nil
			)
			check(
				run.freedCount == entry.compiled.count,
				string.format("%s (seed %d): 100%% まで崩せる", kind, seed),
				string.format("%d手 / 上限%d手", hits, maxHits)
			)
			check(monotone, string.format("%s (seed %d): 崩壊数が減らない (単調増加)", kind, seed))
			-- 制限時間 60 秒・クールダウン 0.35 秒 = 最大171手。実際にはその1/4以下で
			-- 終わらないと「30〜60秒の勝負」にならない。
			check(
				hits <= 40,
				string.format("%s (seed %d): 40手以内で決着する", kind, seed),
				string.format("%d手 (約%.1f秒)", hits, hits * hammer.cooldown)
			)
		end
	end
end

-- ── 5. 打撃の範囲とインパルス ───────────────────────────
section("打撃の範囲とインパルス")
do
	local hammer = Config.hammer
	local physics = Config.physics
	local entry = structureFor("Tower", SEEDS[1])

	-- 直撃したブロックはすべて (キーパーツ倍率込みの) 半径以内にある
	local run = Collapse.newRun(entry.compiled)
	local origin = entry.compiled.blocks[1]
	local result = Collapse.hit(run, origin.cx, origin.cy, origin.cz, hammer.blastRadius, hammer, physics)
	local maxRadius = hammer.blastRadius * (if result.keyHit then hammer.keyPartBonus else 1)
	local withinRadius = true
	for _, id in result.direct do
		local b = entry.compiled.blocks[id]
		local d = math.sqrt((b.cx - origin.cx) ^ 2 + (b.cy - origin.cy) ^ 2 + (b.cz - origin.cz) ^ 2)
		if d > maxRadius + 1e-6 then
			withinRadius = false
		end
	end
	check(
		withinRadius,
		"直撃したブロックは必ず爆発半径の内側",
		string.format("半径 %.1f studs", maxRadius)
	)

	-- 崩れたブロックにはすべてインパルスが付く (付かないと「その場で消える」絵になる)
	local allHaveImpulse = true
	local maxMagnitude = 0
	local upwardOk = true
	for _, id in result.direct do
		local imp = result.impulse[id]
		if imp == nil then
			allHaveImpulse = false
		else
			local m = math.sqrt(imp.vx ^ 2 + imp.vy ^ 2 + imp.vz ^ 2)
			maxMagnitude = math.max(maxMagnitude, m)
			if imp.vy <= 0 then
				upwardOk = false
			end
		end
	end
	for _, id in result.chain do
		if result.impulse[id] == nil then
			allHaveImpulse = false
		end
	end
	check(allHaveImpulse, "崩れたブロックには必ずインパルスが付く")
	check(upwardOk, "直撃ぶんのインパルスは必ず上向き成分を持つ (爆散する)")
	check(
		maxMagnitude <= physics.impulse.max * 1.2 + 1e-6,
		"インパルスが上限を超えない (吹っ飛びすぎ防止)",
		string.format("最大 %.1f / 上限 %.1f", maxMagnitude, physics.impulse.max)
	)

	-- 連鎖崩壊ぶんは弱い (直撃と同じ勢いで飛ぶと「爆発」に見えて崩壊に見えない)
	local directAvg, chainAvg = 0, 0
	for _, id in result.direct do
		local imp = result.impulse[id]
		directAvg += math.sqrt(imp.vx ^ 2 + imp.vy ^ 2 + imp.vz ^ 2)
	end
	for _, id in result.chain do
		local imp = result.impulse[id]
		chainAvg += math.sqrt(imp.vx ^ 2 + imp.vy ^ 2 + imp.vz ^ 2)
	end
	directAvg /= math.max(#result.direct, 1)
	chainAvg /= math.max(#result.chain, 1)
	check(
		chainAvg < directAvg,
		"連鎖崩壊は直撃より弱く飛ぶ",
		string.format("直撃 %.1f vs 連鎖 %.1f", directAvg, chainAvg)
	)

	-- 決定的である (同じ打撃 → 同じインパルス)。リプレイ・録画・検証のため
	local runB = Collapse.newRun(entry.compiled)
	local resultB = Collapse.hit(runB, origin.cx, origin.cy, origin.cz, hammer.blastRadius, hammer, physics)
	local deterministic = #result.direct == #resultB.direct and #result.chain == #resultB.chain
	if deterministic then
		for _, id in result.direct do
			local a, b = result.impulse[id], resultB.impulse[id]
			if b == nil or a.vx ~= b.vx or a.vy ~= b.vy or a.vz ~= b.vz then
				deterministic = false
				break
			end
		end
	end
	check(deterministic, "同じ打撃からは必ず同じインパルスが出る")

	-- 空間ハッシュの結果が総当たりと一致する
	local bruteOk = true
	local runC = Collapse.newRun(entry.compiled)
	for _, radius in { 3, 9, 21, 60 } do
		local fast = Collapse.blocksInRadius(runC, 0, 10, 0, radius)
		local brute = {}
		for i = 1, entry.compiled.count do
			local b = entry.compiled.blocks[i]
			if (b.cx - 0) ^ 2 + (b.cy - 10) ^ 2 + (b.cz - 0) ^ 2 <= radius * radius then
				table.insert(brute, i)
			end
		end
		if #fast ~= #brute then
			bruteOk = false
		else
			for i, id in fast do
				if id ~= brute[i] then
					bruteOk = false
				end
			end
		end
	end
	check(bruteOk, "空間ハッシュの範囲検索が総当たりと一致する")
end

-- ── 6. 崩壊率 ───────────────────────────────────────────
section("崩壊率の計算")
do
	local w = Config.progress.freeWeight
	check(Progress.percent(1000, 0, 0, w) == 0, "1個も崩れていなければ 0%")
	check(Progress.percent(1000, 1000, 0, w) == 100, "全部落ちれば 100%")
	check(
		math.abs(Progress.percent(1000, 0, 1000, w) - w * 100) < 1e-9,
		"空中のブロックは freeWeight ぶんだけ数える",
		string.format("%.1f%%", Progress.percent(1000, 0, 1000, w))
	)
	check(Progress.percent(1000, 900, 900, w) == 100, "重み付けの合計が総数を超えても 100% で頭打ち")
	check(Progress.percent(0, 0, 0, w) == 0, "総数0で割り算が壊れない")

	local monotone = true
	local previous = -1
	for fallen = 0, 1000, 50 do
		local p = Progress.percent(1000, fallen, 0, w)
		if p < previous then
			monotone = false
		end
		previous = p
	end
	check(monotone, "落下数が増えれば崩壊率も必ず増える")
	check(Progress.quantize(33.3333) == 33.3, "表示用の丸めが 0.1% 刻み")

	-- 同率のときは 落下数 → 到達時刻 の順で勝者を決める
	local winner = Progress.leader({
		alice = { percent = 100, fallen = 900, reachedAt = 12.0 },
		bob = { percent = 100, fallen = 900, reachedAt = 11.5 },
		carol = { percent = 98, fallen = 880, reachedAt = 9.0 },
	})
	check(winner == "bob", "同率なら先に到達した方が勝ち", tostring(winner))
end

-- ── 7. 打撃の受理条件 (チート防止) ──────────────────────
section("打撃の受理条件")
do
	local hammer = Config.hammer

	local record = HitRules.newRecord()
	local ok, reason = HitRules.check(record, 0, hammer.reach - 1, hammer)
	check(ok and reason == "ok", "届く距離の1発目は通る")

	local _, farReason = HitRules.check(record, 0, hammer.reach + hammer.graceDistance + 1, hammer)
	check(farReason == "out_of_reach", "リーチ改造 (遠すぎる打撃) を弾く", farReason)

	local _, graceReason = HitRules.check(record, 0, hammer.reach + hammer.graceDistance - 0.1, hammer)
	check(
		graceReason == "ok",
		"レイテンシ許容ぶんは通す (回線が悪い人の正当な打撃を消さない)"
	)

	HitRules.commit(record, 0)
	local _, cdReason = HitRules.check(record, hammer.cooldown * 0.5, 1, hammer)
	check(cdReason == "cooldown", "クールダウン中の連打を弾く", cdReason)
	local _, afterReason = HitRules.check(record, hammer.cooldown, 1, hammer)
	check(afterReason == "ok", "クールダウンが明ければ通る")

	-- 1ミリ秒間隔で撃ち込んでくる改造クライアントを3秒ぶん流す。
	-- サーバは自分の時計で判定するので、通過するのはクールダウンぶんだけになる。
	local burst = HitRules.newRecord()
	local accepted = 0
	for i = 0, 3000 do
		local t = i * 0.001
		if HitRules.check(burst, t, 1, hammer) then
			HitRules.commit(burst, t)
			accepted += 1
		end
	end
	local ceiling = math.ceil(3 / (hammer.cooldown * 0.9)) + 1
	check(
		accepted <= ceiling,
		"連打マクロを流し込んでもクールダウンぶんしか通らない",
		string.format("3秒で %d発通過 (上限 %d発)", accepted, ceiling)
	)
	check(
		accepted <= 3 * hammer.maxHitsPerSecond,
		"1秒あたりの打撃数が上限を超えない",
		string.format("%.1f発/秒", accepted / 3)
	)

	-- 1秒経てば窓が空く
	local window = HitRules.newRecord()
	for i = 1, hammer.maxHitsPerSecond do
		HitRules.commit(window, i * 0.001)
	end
	local _, blocked = HitRules.check(window, 0.5, 1, hammer)
	check(blocked == "rate_limit", "窓が埋まっている間は弾かれる")
	local reopened = HitRules.check(window, 1.5, 1, hammer)
	check(reopened, "1秒経てば窓が空く")
end

-- ── 8. 設定値の整合性 ───────────────────────────────────
section("設定値の整合性")
do
	check(Config.physics.unanchorBudget > 0, "1ステップのアンカー解除予算が正の数")
	check(
		Config.physics.maxActiveParts >= Config.physics.unanchorBudget,
		"同時物理パーツ上限が1ステップの予算以上",
		string.format("%d >= %d", Config.physics.maxActiveParts, Config.physics.unanchorBudget)
	)
	check(Config.arena.killY < Config.arena.floorY, "キル平面が床より下にある")
	check(
		Config.progress.settleY > Config.arena.floorY,
		"静止判定の高さが床より上にある (床の上で止まった瓦礫を数え損ねない)"
	)
	check(
		Config.physics.debrisLifetime > Config.progress.settleDelay,
		"強制消去までの時間が静止待ちより長い (転がる前に消えない)",
		string.format("%.1f秒 > %.1f秒", Config.physics.debrisLifetime, Config.progress.settleDelay)
	)
	check(Config.progress.interval >= 0.1, "崩壊率の同期間隔が 0.1 秒以上 (毎フレーム送らない)")
	check(
		Config.hammer.cooldown * Config.hammer.maxHitsPerSecond >= 1,
		"クールダウンとレート制限が矛盾しない",
		string.format("%.2f秒 x %d回/秒", Config.hammer.cooldown, Config.hammer.maxHitsPerSecond)
	)
	check(
		Config.support.contactEpsilon > Config.build.gap,
		"接触判定の許容差がブロック間の隙間より大きい",
		string.format("%.3f > %.3f", Config.support.contactEpsilon, Config.build.gap)
	)
	check(#Config.build.kinds >= 2, "構造物が複数種類ある")
	for _, kind in { "Tower", "Fortress" } do
		local every = Config.build[kind].pillarEvery
		check(
			Config.support.maxCantilever >= every,
			string.format("%s: 片持ち限界が柱の間隔以上 (升目の中心が落ちない)", kind),
			string.format("maxCantilever %d >= pillarEvery %d", Config.support.maxCantilever, every)
		)
	end
	check(
		Config.support.maxCantilever >= Config.build.Aqueduct.archSpan - 1,
		"Aqueduct: 片持ち限界が径間の張り出し幅以上",
		string.format("%d >= %d", Config.support.maxCantilever, Config.build.Aqueduct.archSpan - 1)
	)
	check(Config.match.duration >= 30 and Config.match.duration <= 90, "制限時間が 30〜90 秒")
end

-- ── 結果 ──────────────────────────────────────────────
print(string.format("\n%d checks, %d failed", checks, failures))
if failures > 0 then
	error(string.format("%d 件の検証に失敗しました", failures), 0)
end
print("すべて通過")
