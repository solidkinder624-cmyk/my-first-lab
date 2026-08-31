--!strict
-- 迷路の生成・当たり判定・経路計算。すべて純関数 (Roblox API 非依存) なので
-- サーバ／クライアント予測／verify.luau のどこからでも同じ結果になる。
--
-- 座標系: タイル (tx, tz) は世界座標 [tx*T, (tx+1)*T] × [tz*T, (tz+1)*T] を占める。
-- セル格子 (cellsW × cellsH) を 2n+1 のタイル格子へ展開し、奇数座標がセル、
-- 偶数座標が壁になる古典的な表現を使う。3Dモデルは一切不要。

local Grid = {}

export type Grid = {
	w: number, -- タイル数 (X方向)
	h: number, -- タイル数 (Z方向)
	tileSize: number,
	solid: { boolean }, -- 1-based: index = tz * w + tx + 1
	cellsW: number,
	cellsH: number,
	seed: number,
	-- 当たり判定を grid 自身に生やしておく。こうしておくと Motion.luau が
	-- Grid モジュールを require せずに済み、純モジュールのまま保てる。
	resolve: (x: number, z: number, radius: number) -> (number, number, boolean, boolean),
}

export type Tile = { x: number, z: number }

-- ── 決定論的な乱数 (xorshift32) ────────────────────────
-- math.random に依存しないので、同じ seed なら全マシンで同じ迷路になる。
export type Rng = { state: number }

local function newRng(seed: number): Rng
	local s = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if s == 0 then
		s = 0x9E3779B9 -- xorshift は 0 で固定点になるため回避
	end
	return { state = s }
end

local function nextUint(rng: Rng): number
	local s = rng.state
	s = bit32.bxor(s, bit32.lshift(s, 13))
	s = bit32.bxor(s, bit32.rshift(s, 17))
	s = bit32.bxor(s, bit32.lshift(s, 5))
	rng.state = s
	return s
end

-- [0, n) の整数
local function nextInt(rng: Rng, n: number): number
	return nextUint(rng) % n
end

local function nextFloat(rng: Rng): number
	return nextUint(rng) / 4294967296
end

Grid.newRng = newRng
Grid.nextInt = nextInt
Grid.nextFloat = nextFloat

-- ── アクセサ ──────────────────────────────────────────
local function index(grid: Grid, tx: number, tz: number): number
	return tz * grid.w + tx + 1
end

-- 範囲外は壁扱い。これで外周の穴あき事故が構造的に起きない。
function Grid.isSolid(grid: Grid, tx: number, tz: number): boolean
	if tx < 0 or tz < 0 or tx >= grid.w or tz >= grid.h then
		return true
	end
	return grid.solid[index(grid, tx, tz)]
end

local function setSolid(grid: Grid, tx: number, tz: number, value: boolean)
	grid.solid[index(grid, tx, tz)] = value
end

function Grid.tileOf(grid: Grid, x: number, z: number): (number, number)
	return math.floor(x / grid.tileSize), math.floor(z / grid.tileSize)
end

function Grid.center(grid: Grid, tx: number, tz: number): (number, number)
	local t = grid.tileSize
	return (tx + 0.5) * t, (tz + 0.5) * t
end

function Grid.isSolidAtWorld(grid: Grid, x: number, z: number): boolean
	local tx, tz = Grid.tileOf(grid, x, z)
	return Grid.isSolid(grid, tx, tz)
end

-- 通行可能なタイルの一覧 (スポーン地点や宝の配置候補)
function Grid.openTiles(grid: Grid): { Tile }
	local out: { Tile } = {}
	for tz = 0, grid.h - 1 do
		for tx = 0, grid.w - 1 do
			if not Grid.isSolid(grid, tx, tz) then
				table.insert(out, { x = tx, z = tz })
			end
		end
	end
	return out
end

-- ── 生成 ──────────────────────────────────────────────
-- 深さ優先 (recursive backtracker) で完全迷路を掘り、そのあと braid の割合だけ
-- 行き止まりを開通させてループを作る。純粋な完全迷路は袋小路が多く、
-- 鬼ごっこでは逃げ手が一方的に詰むため。
function Grid.generate(cellsW: number, cellsH: number, seed: number, braid: number?, tileSize: number?): Grid
	local w, h = cellsW * 2 + 1, cellsH * 2 + 1
	local grid: Grid = {
		w = w,
		h = h,
		tileSize = tileSize or 8,
		solid = table.create(w * h, true),
		cellsW = cellsW,
		cellsH = cellsH,
		seed = seed,
		resolve = function(): (number, number, boolean, boolean)
			return 0, 0, false, false -- 直後に本体へ差し替える
		end,
	}
	grid.resolve = function(x: number, z: number, radius: number)
		return Grid.resolve(grid, x, z, radius)
	end

	local rng = newRng(seed)
	local visited: { boolean } = table.create(cellsW * cellsH, false)
	local function visitIndex(cx: number, cz: number): number
		return cz * cellsW + cx + 1
	end

	local startX, startZ = nextInt(rng, cellsW), nextInt(rng, cellsH)
	local stack: { Tile } = { { x = startX, z = startZ } }
	visited[visitIndex(startX, startZ)] = true
	setSolid(grid, startX * 2 + 1, startZ * 2 + 1, false)

	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

	while #stack > 0 do
		local cur = stack[#stack]
		-- 未訪問の隣接セルを集める
		local candidates: { { number } } = {}
		for _, d in dirs do
			local nx, nz = cur.x + d[1], cur.z + d[2]
			if nx >= 0 and nz >= 0 and nx < cellsW and nz < cellsH and not visited[visitIndex(nx, nz)] then
				table.insert(candidates, { nx, nz })
			end
		end

		if #candidates == 0 then
			table.remove(stack)
			continue
		end

		local pick = candidates[nextInt(rng, #candidates) + 1]
		local nx, nz = pick[1], pick[2]
		visited[visitIndex(nx, nz)] = true
		-- セル本体と、その間の壁タイルを開通させる
		setSolid(grid, nx * 2 + 1, nz * 2 + 1, false)
		setSolid(grid, cur.x + nx + 1, cur.z + nz + 1, false)
		table.insert(stack, { x = nx, z = nz })
	end

	-- braiding: 行き止まりのセルから外向きの壁を1枚壊す
	local braidRatio = braid or 0
	if braidRatio > 0 then
		for cz = 0, cellsH - 1 do
			for cx = 0, cellsW - 1 do
				local tx, tz = cx * 2 + 1, cz * 2 + 1
				local open = 0
				for _, d in dirs do
					if not Grid.isSolid(grid, tx + d[1], tz + d[2]) then
						open += 1
					end
				end
				if open <= 1 and nextFloat(rng) < braidRatio then
					-- まだ塞がっていて、かつ盤面の外周でない壁を選ぶ
					local walls: { { number } } = {}
					for _, d in dirs do
						local wx, wz = tx + d[1], tz + d[2]
						if Grid.isSolid(grid, wx, wz) and wx > 0 and wz > 0 and wx < w - 1 and wz < h - 1 then
							table.insert(walls, { wx, wz })
						end
					end
					if #walls > 0 then
						local pickWall = walls[nextInt(rng, #walls) + 1]
						setSolid(grid, pickWall[1], pickWall[2], false)
					end
				end
			end
		end
	end

	return grid
end

-- ── 当たり判定 (円 vs タイルAABB) ──────────────────────
-- 戻り値は補正後の座標と、各軸に補正が入ったかどうか。
-- 角に挟まった場合を考えて2パス回す。
function Grid.resolve(grid: Grid, x: number, z: number, radius: number): (number, number, boolean, boolean)
	local t = grid.tileSize
	local hitX, hitZ = false, false

	for _ = 1, 2 do
		local corrected = false
		local tx, tz = Grid.tileOf(grid, x, z)
		for dz = -1, 1 do
			for dx = -1, 1 do
				local cx, cz = tx + dx, tz + dz
				if not Grid.isSolid(grid, cx, cz) then
					continue
				end
				local minX, maxX = cx * t, (cx + 1) * t
				local minZ, maxZ = cz * t, (cz + 1) * t
				local nearX = math.clamp(x, minX, maxX)
				local nearZ = math.clamp(z, minZ, maxZ)
				local ox, oz = x - nearX, z - nearZ
				local d2 = ox * ox + oz * oz

				if d2 > radius * radius then
					continue
				end

				if d2 > 1e-9 then
					-- 面または角の外側: 最近接点から離す向きへ押し出す
					local d = math.sqrt(d2)
					local push = radius - d
					x += ox / d * push
					z += oz / d * push
					if math.abs(ox) > 1e-6 then
						hitX = true
					end
					if math.abs(oz) > 1e-6 then
						hitZ = true
					end
				else
					-- 完全にタイル内部: 最も浅い面へ逃がす
					local left, right = x - minX, maxX - x
					local up, down = z - minZ, maxZ - z
					local best = math.min(left, right, up, down)
					if best == left then
						x = minX - radius
						hitX = true
					elseif best == right then
						x = maxX + radius
						hitX = true
					elseif best == up then
						z = minZ - radius
						hitZ = true
					else
						z = maxZ + radius
						hitZ = true
					end
				end
				corrected = true
			end
		end
		if not corrected then
			break
		end
	end

	return x, z, hitX, hitZ
end

-- ── 経路 ──────────────────────────────────────────────
-- 全開通タイルへの歩数 (幅優先)。到達不能なタイルは nil のまま。
-- 迷路の連結性チェックと、宝をスポーンから遠くへ置く処理の両方で使う。
function Grid.distances(grid: Grid, fromX: number, fromZ: number): { number }
	local dist: { number } = {}
	if Grid.isSolid(grid, fromX, fromZ) then
		return dist
	end
	local start = index(grid, fromX, fromZ)
	dist[start] = 0
	local queue: { Tile } = { { x = fromX, z = fromZ } }
	local head = 1
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local base = dist[index(grid, cur.x, cur.z)]
		for _, d in dirs do
			local nx, nz = cur.x + d[1], cur.z + d[2]
			if not Grid.isSolid(grid, nx, nz) and dist[index(grid, nx, nz)] == nil then
				dist[index(grid, nx, nz)] = base + 1
				table.insert(queue, { x = nx, z = nz })
			end
		end
	end
	return dist
end

function Grid.distanceAt(grid: Grid, dist: { number }, tx: number, tz: number): number?
	return dist[index(grid, tx, tz)]
end

-- ── 壁のマージ ────────────────────────────────────────
-- 壁タイルを横方向の連続区間にまとめる。1タイル=1パーツだと 625 パーツ級に
-- なるところを 1/4 以下に減らせる (描画・物理コスト対策)。
export type WallRun = { x: number, z: number, length: number }

function Grid.wallRuns(grid: Grid): { WallRun }
	local runs: { WallRun } = {}
	for tz = 0, grid.h - 1 do
		local runStart: number? = nil
		for tx = 0, grid.w do
			local solid = tx < grid.w and Grid.isSolid(grid, tx, tz)
			if solid and runStart == nil then
				runStart = tx
			elseif not solid and runStart ~= nil then
				table.insert(runs, { x = runStart, z = tz, length = tx - runStart })
				runStart = nil
			end
		end
	end
	return runs
end

return Grid
