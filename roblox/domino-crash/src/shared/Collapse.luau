--!strict
-- 崩壊シミュレーションの「頭脳」。Roblox の物理エンジンは絵を描くだけで、
-- 何が崩れるかを決めるのはこのモジュール。Roblox API を一切参照しない。
--
-- なぜ物理任せにしないのか:
--   * Anchored を半径で外すだけだと「宙に浮いた壁がその場に残る」絵になり、
--     ドミノ崩しの快感が出ない。荷重の伝わり方をこちらで持つ必要がある。
--   * 崩壊率を数えるのに毎フレーム全パーツを走査したくない。何が落ちたかを
--     論理側が知っていれば、走査は「実際に動いているパーツ」だけで済む。
--   * Studio を開かずに「この構造物は必ず崩せるか」を CI で検査したい。
--
-- 支持モデル (トラスの粗い近似):
--   * 荷重を伝えるブロック (柱・床) の真上に乗っている … 荷重経路コスト 0
--   * 同じ高さで横に繋がっている                       … 片持ち。コスト +1
--   * 地面に接している                                 … コスト 0 の起点
--   壁 (Block.bearing == false) は詰め物。自分は支えられるが上を支えないので、
--   壁をいくら壊しても上階は落ちてこない。柱を折って初めて崩れる。
--   コストが maxCantilever を超える / どこからも到達できない ブロックは自重で落ちる。
--   だから「柱を1本折る」と、その柱が支えていた範囲が張り出し限界を超えて総崩れになる。

local Collapse = {}

export type Vec3 = { x: number, y: number, z: number }

export type Structure = {
	blocks: { any },
	count: number,
	up: { { number } }, -- up[i]   = i の上に乗っているブロック
	side: { { number } }, -- side[i] = i と横で繋がっているブロック
	grounded: { boolean },
	maxCantilever: number,
	cellSize: number,
	buckets: { [string]: { number } },
	-- 走査用の使い回しバッファ (毎回テーブルを作らない)
	dist: { number },
	seen: { number },
	epoch: number,
}

export type Run = {
	structure: Structure,
	freed: { boolean }, -- アンカーが外れた (= もう構造の一部ではない)
	freedCount: number,
}

export type HitResult = {
	direct: { number }, -- 打撃で直接吹き飛んだブロック
	chain: { number }, -- 支えを失って連鎖崩壊したブロック
	impulse: { [number]: { vx: number, vy: number, vz: number, wx: number, wy: number, wz: number } },
	keyHit: boolean, -- キーパーツを巻き込んだか (演出の強さに使う)
	freedCount: number,
}

-- ── 空間ハッシュ ────────────────────────────────────────
-- 隣接判定と打撃範囲判定を O(n^2) から落とすためだけの内部構造。

local function bucketKey(ix: number, iy: number, iz: number): string
	return string.format("%d:%d:%d", ix, iy, iz)
end

local function insertBox(structure: Structure, id: number)
	local b = structure.blocks[id]
	local s = structure.cellSize
	local x0 = math.floor((b.cx - b.sx * 0.5) / s)
	local x1 = math.floor((b.cx + b.sx * 0.5) / s)
	local y0 = math.floor((b.cy - b.sy * 0.5) / s)
	local y1 = math.floor((b.cy + b.sy * 0.5) / s)
	local z0 = math.floor((b.cz - b.sz * 0.5) / s)
	local z1 = math.floor((b.cz + b.sz * 0.5) / s)
	for ix = x0, x1 do
		for iy = y0, y1 do
			for iz = z0, z1 do
				local key = bucketKey(ix, iy, iz)
				local bucket = structure.buckets[key]
				if not bucket then
					bucket = {}
					structure.buckets[key] = bucket
				end
				table.insert(bucket, id)
			end
		end
	end
end

-- AABB に触れうるブロック id を out に集める (重複なし)
local function queryBox(structure: Structure, minX, minY, minZ, maxX, maxY, maxZ, out: { number }): { number }
	table.clear(out)
	structure.epoch += 1
	local epoch = structure.epoch
	local seen = structure.seen
	local s = structure.cellSize
	for ix = math.floor(minX / s), math.floor(maxX / s) do
		for iy = math.floor(minY / s), math.floor(maxY / s) do
			for iz = math.floor(minZ / s), math.floor(maxZ / s) do
				local bucket = structure.buckets[bucketKey(ix, iy, iz)]
				if bucket then
					for _, id in bucket do
						if seen[id] ~= epoch then
							seen[id] = epoch
							table.insert(out, id)
						end
					end
				end
			end
		end
	end
	return out
end

-- 打撃点から半径 radius 以内の (まだ生きている) ブロック id
function Collapse.blocksInRadius(run: Run, x: number, y: number, z: number, radius: number): { number }
	local structure = run.structure
	local candidates = queryBox(structure, x - radius, y - radius, z - radius, x + radius, y + radius, z + radius, {})
	local result = {}
	local r2 = radius * radius
	for _, id in candidates do
		if not run.freed[id] then
			local b = structure.blocks[id]
			local dx, dy, dz = b.cx - x, b.cy - y, b.cz - z
			if dx * dx + dy * dy + dz * dz <= r2 then
				table.insert(result, id)
			end
		end
	end
	table.sort(result) -- 決定性のため (ハッシュの走査順に依存させない)
	return result
end

-- ── 支持グラフの構築 ────────────────────────────────────

local function overlap1d(aMin: number, aMax: number, bMin: number, bMax: number): number
	return math.min(aMax, bMax) - math.max(aMin, bMin)
end

-- blocks は Blueprint.Block の配列 (id が 1..n で連番であること)
function Collapse.compile(blocks: { any }, support): Structure
	local n = #blocks
	for i = 1, n do
		assert(blocks[i].id == i, "Collapse.compile: ブロック id は 1..n の連番である必要があります")
	end

	local cellSize = 0
	for _, b in blocks do
		cellSize = math.max(cellSize, b.sx, b.sy, b.sz)
	end
	cellSize = math.max(cellSize, 1)

	local structure: Structure = {
		blocks = blocks,
		count = n,
		up = table.create(n),
		side = table.create(n),
		grounded = table.create(n, false),
		maxCantilever = support.maxCantilever,
		cellSize = cellSize,
		buckets = {},
		dist = table.create(n, -1),
		seen = table.create(n, 0),
		epoch = 0,
	}
	for i = 1, n do
		structure.up[i] = {}
		structure.side[i] = {}
	end
	for i = 1, n do
		insertBox(structure, i)
	end

	local contactEps = support.contactEpsilon
	local overlapEps = support.overlapEpsilon
	local scratch = {}

	for i = 1, n do
		local a = blocks[i]
		local aMinX, aMaxX = a.cx - a.sx * 0.5, a.cx + a.sx * 0.5
		local aMinY, aMaxY = a.cy - a.sy * 0.5, a.cy + a.sy * 0.5
		local aMinZ, aMaxZ = a.cz - a.sz * 0.5, a.cz + a.sz * 0.5

		if aMinY <= contactEps then
			structure.grounded[i] = true
		end

		local pad = contactEps + 1e-3
		queryBox(structure, aMinX - pad, aMinY - pad, aMinZ - pad, aMaxX + pad, aMaxY + pad, aMaxZ + pad, scratch)
		for _, j in scratch do
			if j ~= i then
				local b = blocks[j]
				local bMinX, bMaxX = b.cx - b.sx * 0.5, b.cx + b.sx * 0.5
				local bMinY, bMaxY = b.cy - b.sy * 0.5, b.cy + b.sy * 0.5
				local bMinZ, bMaxZ = b.cz - b.sz * 0.5, b.cz + b.sz * 0.5
				local ox = overlap1d(aMinX, aMaxX, bMinX, bMaxX)
				local oy = overlap1d(aMinY, aMaxY, bMinY, bMaxY)
				local oz = overlap1d(aMinZ, aMaxZ, bMinZ, bMaxZ)

				-- b が a の真下に接していて、かつ b が荷重を伝えられる種別なら、
				-- a は b の上に乗っている。壁 (bearing == false) は詰め物なので
				-- ここで弾かれ、「壁を壊しても上階は落ちない」が成立する。
				if
					b.bearing ~= false
					and math.abs(aMinY - bMaxY) <= contactEps
					and ox > overlapEps
					and oz > overlapEps
				then
					table.insert(structure.up[j], i)
				end

				-- 横に接している (同じ高さ帯を共有し、X か Z のどちらか一方だけで接触)
				if oy > overlapEps then
					local touchX = math.abs(ox) <= contactEps and oz > overlapEps
					local touchZ = math.abs(oz) <= contactEps and ox > overlapEps
					if touchX or touchZ then
						table.insert(structure.side[i], j)
					end
				end
			end
		end
		table.sort(structure.side[i])
	end
	for i = 1, n do
		table.sort(structure.up[i])
	end

	return structure
end

function Collapse.newRun(structure: Structure): Run
	return {
		structure = structure,
		freed = table.create(structure.count, false),
		freedCount = 0,
	}
end

-- ── 荷重経路の再計算 (Dial のバケット BFS) ──────────────
-- 辺のコストは 0 (縦) と 1 (横) の2種類しかなく、上限も maxCantilever と
-- 小さいので、優先度キューではなく固定長バケットで十分。O(V + E)。
local function recomputeSupport(run: Run): { number }
	local structure = run.structure
	local dist = structure.dist
	local freed = run.freed
	local maxC = structure.maxCantilever
	for i = 1, structure.count do
		dist[i] = -1
	end

	local buckets = table.create(maxC + 1)
	for k = 0, maxC do
		buckets[k + 1] = {}
	end

	for i = 1, structure.count do
		if not freed[i] and structure.grounded[i] then
			dist[i] = 0
			table.insert(buckets[1], i)
		end
	end

	for k = 0, maxC do
		local queue = buckets[k + 1]
		local i = 1
		while i <= #queue do
			local id = queue[i]
			i += 1
			if dist[id] == k then -- 後からより短い経路が見つかった場合の残骸を飛ばす
				for _, nb in structure.up[id] do
					if not freed[nb] and (dist[nb] < 0 or dist[nb] > k) then
						dist[nb] = k
						table.insert(queue, nb)
					end
				end
				if k < maxC then
					for _, nb in structure.side[id] do
						if not freed[nb] and (dist[nb] < 0 or dist[nb] > k + 1) then
							dist[nb] = k + 1
							table.insert(buckets[k + 2], nb)
						end
					end
				end
			end
		end
	end

	return dist
end

-- 現時点で構造として保たれているブロック数
function Collapse.standingCount(run: Run): number
	local dist = recomputeSupport(run)
	local standing = 0
	for i = 1, run.structure.count do
		if not run.freed[i] and dist[i] >= 0 then
			standing += 1
		end
	end
	return standing
end

-- ── 打撃 ────────────────────────────────────────────────

-- id から決まる 0..1 のジッタ。乱数を持ち回らずに済み、順序にも依存しない。
local function jitter(id: number, salt: number): number
	local h = (id * 2654435761 + salt * 40503 + 12345) % 2147483647
	return h / 2147483647
end

local function makeImpulse(block, hx: number, hy: number, hz: number, scale: number, physics)
	local imp = physics.impulse
	local dx, dy, dz = block.cx - hx, block.cy - hy, block.cz - hz
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-4 then
		dx, dy, dz, len = 0, 1, 0, 1
	end
	dx, dy, dz = dx / len, dy / len, dz / len

	-- 外向き + 上向きバイアス。単に落とすのではなく「爆散」させる
	local ux, uy, uz = dx, dy + imp.upBias, dz
	local ulen = math.sqrt(ux * ux + uy * uy + uz * uz)
	ux, uy, uz = ux / ulen, uy / ulen, uz / ulen

	local magnitude = math.min(imp.base / (1 + imp.falloff * len), imp.max) * scale
	local j = jitter(block.id, 1) * 0.4 + 0.8 -- 0.8..1.2 のばらつき

	return {
		vx = ux * magnitude * j,
		vy = uy * magnitude * j,
		vz = uz * magnitude * j,
		wx = (jitter(block.id, 2) - 0.5) * 2 * imp.spin,
		wy = (jitter(block.id, 3) - 0.5) * 2 * imp.spin,
		wz = (jitter(block.id, 4) - 0.5) * 2 * imp.spin,
	}
end

-- 打撃を1回適用する。run は破壊的に更新される。
--   x, y, z : 打撃点 (構造物ローカル座標)
--   radius  : 直接吹き飛ぶ半径。キーパーツを含むと自動で hammer.keyPartBonus 倍される
function Collapse.hit(run: Run, x: number, y: number, z: number, radius: number, hammer, physics): HitResult
	local structure = run.structure
	local freed = run.freed

	local hits = Collapse.blocksInRadius(run, x, y, z, radius)
	local keyHit = false
	for _, id in hits do
		if structure.blocks[id].key then
			keyHit = true
			break
		end
	end

	-- キーパーツ (柱・コア・まぐさ石) を捉えたら、そこを起点に爆発半径が広がる。
	-- 「弱点を見極めて叩く」ことが手数の差になるのはこの分岐のおかげ。
	if keyHit then
		hits = Collapse.blocksInRadius(run, x, y, z, radius * hammer.keyPartBonus)
	end

	local result: HitResult = {
		direct = {},
		chain = {},
		impulse = {},
		keyHit = keyHit,
		freedCount = 0,
	}

	for _, id in hits do
		freed[id] = true
		run.freedCount += 1
		table.insert(result.direct, id)
		result.impulse[id] = makeImpulse(structure.blocks[id], x, y, z, 1, physics)
	end

	-- 支えを失ったブロックを回収する。ここがドミノ倒しの本体。
	local dist = recomputeSupport(run)
	for id = 1, structure.count do
		if not freed[id] and dist[id] < 0 then
			freed[id] = true
			run.freedCount += 1
			table.insert(result.chain, id)
			result.impulse[id] = makeImpulse(structure.blocks[id], x, y, z, physics.impulse.chain, physics)
		end
	end

	result.freedCount = run.freedCount
	return result
end

return Collapse
