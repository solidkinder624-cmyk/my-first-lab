--!strict
-- 破壊対象の構造物を手続き生成する純モジュール。
--
-- Roblox API を一切参照しない (Instance も Vector3 も使わない)。返すのは
-- 「どこに・どんなサイズの・どういう役割のブロックを置くか」という数値の配列だけ。
-- Part を実際に作るのはサーバの StructureManager の仕事。この分離のおかげで
--   * verify.luau が Studio 抜きで構造の健全性を検査できる
--   * 同じシードから両プレイヤーにビット単位で同一の構造物を渡せる (対戦の公平性)
-- という2つが同時に成り立つ。
--
-- 座標系: 構造物のローカル原点は「底面の中心」。cy は必ず正で、cy - sy/2 == 0 の
-- ブロックが接地ブロック (= 支持の起点) になる。

local Blueprint = {}

export type Block = {
	id: number,
	ix: number, -- セル座標 (デバッグ・生成用。物理には使わない)
	iz: number,
	level: number,
	cx: number, -- 中心座標 (studs, 構造物ローカル)
	cy: number,
	cz: number,
	sx: number, -- サイズ (studs)
	sy: number,
	sz: number,
	kind: string, -- "Pillar" | "Wall" | "Slab" | "Core" | "Lintel" | "Pier" | "Deck"
	key: boolean, -- true = 弱点。壊すと上の荷重が一気に行き場を失う
	bearing: boolean, -- true = 荷重を上へ伝える。false (Wall) は詰め物で上を支えない
}

export type Structure = {
	kind: string,
	seed: number,
	blocks: { Block },
	keyCount: number,
	bounds: { minX: number, minY: number, minZ: number, maxX: number, maxY: number, maxZ: number },
}

-- ── 決定的な擬似乱数 (32bit LCG) ────────────────────────
-- Roblox の Random ではなく自前で持つのは、Luau CLI から同じ数列を再現するため。
local function makeRng(seed: number)
	local state = math.floor(math.abs(seed)) % 2147483647
	if state == 0 then
		state = 1 -- 0 は LCG の吸収状態
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- ── 生成キャンバス ──────────────────────────────────────
-- セル (ix, level, iz) は最大1ブロック。二重置きを弾くことで、
-- 「櫓と外壁が角で重なる」といった生成バグがそのまま物理の暴発になるのを防ぐ。
type Canvas = {
	unit: { x: number, y: number, z: number },
	gap: number,
	bearingKinds: { [string]: boolean },
	originX: number,
	originZ: number,
	cells: { [string]: Block },
	blocks: { Block },
	holes: { [string]: boolean }, -- 意図的に空けた穴 (窓・門)
}

local function newCanvas(build, originX: number, originZ: number): Canvas
	return {
		unit = build.unit,
		gap = build.gap,
		bearingKinds = build.bearingKinds,
		originX = originX,
		originZ = originZ,
		cells = {},
		blocks = {},
		holes = {},
	}
end

local function put(canvas: Canvas, ix: number, level: number, iz: number, kind: string, key: boolean): Block
	local cellKey = string.format("%d:%d:%d", ix, level, iz)
	local existing = canvas.cells[cellKey]
	if existing then
		-- 既に置かれている場合、より重要な役割 (キーパーツ) で上書きする
		if key and not existing.key then
			existing.key = true
			existing.kind = kind
			existing.bearing = canvas.bearingKinds[kind] == true
		end
		return existing
	end

	local u = canvas.unit
	local g = canvas.gap
	local block: Block = {
		id = #canvas.blocks + 1,
		ix = ix,
		iz = iz,
		level = level,
		cx = (ix - canvas.originX) * u.x,
		cy = level * u.y + u.y * 0.5,
		cz = (iz - canvas.originZ) * u.z,
		sx = u.x - g,
		sy = u.y - g,
		sz = u.z - g,
		kind = kind,
		key = key,
		bearing = canvas.bearingKinds[kind] == true,
	}
	canvas.cells[cellKey] = block
	table.insert(canvas.blocks, block)
	return block
end

local function isPerimeter(ix: number, iz: number, x0: number, x1: number, z0: number, z1: number): boolean
	return ix == x0 or ix == x1 or iz == z0 or iz == z1
end

-- 柱の格子。x0 から every セルおき、そして必ず反対の端 (x1) にも立てる。
-- 「柱で囲まれた升目の中心」が構造上いちばん弱い点で、その片持ち距離が
-- Config.support.maxCantilever を超えないように every を決めてある。
local function onColumnLine(i: number, i0: number, i1: number, every: number): boolean
	return i == i0 or i == i1 or (i - i0) % every == 0
end

-- 窓や門の穴。壁は「横に繋がっていること」で立っているので、穴が近すぎると
-- 間の1枚が両隣を失って宙に浮く。穴同士を必ず3セル以上離すことでそれを防ぐ
-- (穴が2セル間隔だと、間の1枚が孤立する)。
local function markHole(canvas: Canvas, level: number, ix: number, iz: number)
	canvas.holes[string.format("%d:%d:%d", ix, level, iz)] = true
end

local function canPunch(canvas: Canvas, level: number, ix: number, iz: number): boolean
	for dx = -2, 2 do
		for dz = -2, 2 do
			if canvas.holes[string.format("%d:%d:%d", ix + dx, level, iz + dz)] then
				return false
			end
		end
	end
	return true
end

-- ── 1. 塔 (Tower) ───────────────────────────────────────
-- ラーメン構造の段塔。柱が格子状に立ち、その間を「荷重を伝えない壁」が埋める。
-- 壁を何枚壊しても上階は落ちてこない。柱を折って初めて床スラブが張り出し限界を
-- 超え、そのフロアが落ち、上のフロアが支えを失って連鎖する。
--
-- 段を細くするときは必ず柱1スパンぶん (pillarEvery セル) 内側に寄せる。
-- 中途半端に寄せると、上の段の柱が下の段の「柱と柱の間の床」に乗ることになり、
-- 段を重ねるたびに片持ち距離が積み上がって生成直後に自壊する。
local function buildTower(build, cfg, seed: number): { Block }
	local rng = makeRng(seed)
	local w, d = cfg.cells.w, cfg.cells.d
	local canvas = newCanvas(build, (w - 1) * 0.5, (d - 1) * 0.5)
	local courses = cfg.coursesPerFloor
	local levelsPerFloor = courses + 1
	local every = cfg.pillarEvery
	-- 内側に寄せられる段数。寄せたあとも1スパン以上残る範囲まで。
	local maxSteps = math.max(math.floor(((math.min(w, d) - 1) / every - 1) * 0.5), 0)

	for floor = 0, cfg.floors - 1 do
		local base = floor * levelsPerFloor
		local inset = math.min(math.floor(floor / cfg.taperEvery), maxSteps) * every
		local x0, x1 = inset, w - 1 - inset
		local z0, z1 = inset, d - 1 - inset

		for course = 0, courses - 1 do
			local level = base + course
			for ix = x0, x1 do
				for iz = z0, z1 do
					local column = onColumnLine(ix, x0, x1, every) and onColumnLine(iz, z0, z1, every)
					local perimeter = isPerimeter(ix, iz, x0, x1, z0, z1)
					if column then
						-- 外周の柱は "Pillar"、内側の柱は "Core"。コアは塔の中にあるので、
						-- まず外壁を崩して露出させないと叩けない = 最短ルートの入口になる。
						local isCore = not perimeter and floor < cfg.coreFloors
						put(canvas, ix, level, iz, if isCore then "Core" else "Pillar", true)
					elseif perimeter then
						-- 窓抜き: 各フロアの下段だけをランダムに空ける。見た目と、
						-- 「そこから内部の柱が覗く」という手掛かりを兼ねる。
						local punch = course == 0 and rng() < cfg.windowChance and canPunch(canvas, level, ix, iz)
						if punch then
							markHole(canvas, level, ix, iz)
						else
							put(canvas, ix, level, iz, "Wall", false)
						end
					end
				end
			end
		end

		-- 床スラブ。上の階の柱と壁はここに乗る
		local slabLevel = base + courses
		for ix = x0, x1 do
			for iz = z0, z1 do
				put(canvas, ix, slabLevel, iz, "Slab", false)
			end
		end
	end

	return canvas.blocks
end

-- ── 2. 要塞 (Fortress) ──────────────────────────────────
-- 低くて広い城壁 + 四隅の櫓 + 正面の門。城壁は控え柱 (pillarEvery ごと) が
-- 歩廊を支えていて、門の上のまぐさ石 (Lintel) だけは荷重の逃げ場が無い。
-- 櫓は独立した4本足なので、足元の柱を折らないと落ちない。
local function buildFortress(build, cfg, seed: number): { Block }
	local rng = makeRng(seed)
	local w, d = cfg.cells.w, cfg.cells.d
	local canvas = newCanvas(build, (w - 1) * 0.5, (d - 1) * 0.5)
	local courses = cfg.coursesPerFloor
	local wallLevels = cfg.floors * courses
	local midX = math.floor((w - 1) * 0.5)
	local gateLevels = math.min(cfg.gateFloors * courses, wallLevels - 1)

	-- 門の開口を先に穴として登録しておく。こうしておくと窓抜きが門の両脇を
	-- 避けてくれるので、門柱の1枚が孤立して宙に浮くことがない。
	for level = 0, gateLevels - 1 do
		for offset = -1, 1 do
			markHole(canvas, level, midX + offset, 0)
		end
	end

	-- 城壁
	for level = 0, wallLevels - 1 do
		for ix = 0, w - 1 do
			for iz = 0, d - 1 do
				if isPerimeter(ix, iz, 0, w - 1, 0, d - 1) then
					local inGate = iz == 0 and math.abs(ix - midX) <= 1 and level < gateLevels
					local isLintel = iz == 0 and math.abs(ix - midX) <= 1 and level == gateLevels
					if isLintel then
						put(canvas, ix, level, iz, "Lintel", true)
					elseif not inGate then
						-- 控え柱は「辺に沿って pillarEvery ごと」。四隅は必ず柱。
						local column = onColumnLine(ix, 0, w - 1, cfg.pillarEvery)
							and onColumnLine(iz, 0, d - 1, cfg.pillarEvery)
						if column then
							put(canvas, ix, level, iz, "Pillar", true)
						else
							local punch = level % courses == 0
								and rng() < cfg.windowChance
								and canPunch(canvas, level, ix, iz)
							if punch then
								markHole(canvas, level, ix, iz)
							else
								put(canvas, ix, level, iz, "Wall", false)
							end
						end
					end
				end
			end
		end
	end

	-- 城壁上の歩廊 (幅2セルのリング)
	for ix = 0, w - 1 do
		for iz = 0, d - 1 do
			local ring = math.min(ix, iz, w - 1 - ix, d - 1 - iz)
			if ring < 2 then
				put(canvas, ix, wallLevels, iz, "Slab", false)
			end
		end
	end

	-- 四隅の櫓
	local t = cfg.towerCells
	local towerLevels = cfg.towerFloors * courses
	local corners = {
		{ 0, 0 },
		{ w - t, 0 },
		{ 0, d - t },
		{ w - t, d - t },
	}
	for _, corner in corners do
		local x0, z0 = corner[1], corner[2]
		local x1, z1 = x0 + t - 1, z0 + t - 1
		for level = 0, towerLevels - 1 do
			for ix = x0, x1 do
				for iz = z0, z1 do
					if isPerimeter(ix, iz, x0, x1, z0, z1) then
						local isCorner = (ix == x0 or ix == x1) and (iz == z0 or iz == z1)
						put(canvas, ix, level, iz, if isCorner then "Pillar" else "Wall", isCorner)
					end
				end
			end
		end
		-- 櫓の屋根
		for ix = x0, x1 do
			for iz = z0, z1 do
				put(canvas, ix, towerLevels, iz, "Slab", false)
			end
		end
	end

	return canvas.blocks
end

-- ── 3. 水道橋 (Aqueduct) ────────────────────────────────
-- 橋脚 (Pier) と桁 (Deck) だけの、いちばん「ドミノ」らしい構造物。壁が無いので
-- 柱以外を叩く場所がほとんど無い代わりに、径間が maxCantilever ぎりぎりに
-- 設計してある。橋脚を1本折ると両隣の径間の端が張り出し限界を超えて落ち、
-- 上の層の橋脚がその桁に乗っているので、そのまま上まで連鎖する。
local function buildAqueduct(build, cfg, _seed: number): { Block }
	local w, d = cfg.cells.w, cfg.cells.d
	local canvas = newCanvas(build, (w - 1) * 0.5, (d - 1) * 0.5)
	local courses = cfg.coursesPerFloor
	local levelsPerFloor = courses + 1

	for floor = 0, cfg.floors - 1 do
		local base = floor * levelsPerFloor
		for course = 0, courses - 1 do
			local level = base + course
			for ix = 0, w - 1 do
				if ix % cfg.archSpan == 0 or ix == w - 1 then
					for iz = 0, d - 1 do
						put(canvas, ix, level, iz, "Pier", true)
					end
				end
			end
		end
		local deckLevel = base + courses
		for ix = 0, w - 1 do
			for iz = 0, d - 1 do
				put(canvas, ix, deckLevel, iz, "Deck", false)
			end
		end
	end

	return canvas.blocks
end

local GENERATORS = {
	Tower = buildTower,
	Fortress = buildFortress,
	Aqueduct = buildAqueduct,
}

function Blueprint.bounds(blocks: { Block })
	local b = {
		minX = math.huge,
		minY = math.huge,
		minZ = math.huge,
		maxX = -math.huge,
		maxY = -math.huge,
		maxZ = -math.huge,
	}
	for _, block in blocks do
		b.minX = math.min(b.minX, block.cx - block.sx * 0.5)
		b.maxX = math.max(b.maxX, block.cx + block.sx * 0.5)
		b.minY = math.min(b.minY, block.cy - block.sy * 0.5)
		b.maxY = math.max(b.maxY, block.cy + block.sy * 0.5)
		b.minZ = math.min(b.minZ, block.cz - block.sz * 0.5)
		b.maxZ = math.max(b.maxZ, block.cz + block.sz * 0.5)
	end
	return b
end

-- kind: Config.build.kinds のいずれか。seed: 同じ値なら必ず同じ構造物。
function Blueprint.generate(kind: string, seed: number, build): Structure
	local generator = GENERATORS[kind]
	assert(generator, string.format("未知の構造物 %q", tostring(kind)))
	local cfg = build[kind]
	assert(cfg, string.format("Config.build.%s がありません", tostring(kind)))

	local blocks = generator(build, cfg, seed)
	local keyCount = 0
	for _, block in blocks do
		if block.key then
			keyCount += 1
		end
	end

	return {
		kind = kind,
		seed = seed,
		blocks = blocks,
		keyCount = keyCount,
		bounds = Blueprint.bounds(blocks),
	}
end

-- ラウンド番号から構造物の種類を決める。全プレイヤーが同じ結果になる必要がある。
function Blueprint.kindForRound(round: number, build): string
	local kinds = build.kinds
	return kinds[(round - 1) % #kinds + 1]
end

function Blueprint.countByKind(structure: Structure): { [string]: number }
	local counts = {}
	for _, block in structure.blocks do
		counts[block.kind] = (counts[block.kind] or 0) + 1
	end
	return counts
end

return Blueprint
