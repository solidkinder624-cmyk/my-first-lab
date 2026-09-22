-- ワールド（草原の地形・拠点スロット・野生の出現範囲）の「計算だけ」を行うモジュール。
--
-- Roblox API（Instance / Vector3 / Enum など）を一切使わない純ロジックにしている。
-- そのため Studio でも Luau CLI のテストでも同じ結果になり、
-- 地形（TerrainGen）・柵（RanchBuilder）・外部向けAPI（RanchWorld）がすべて同じ座標を使う。
--
-- 座標系: +X = 東、-Z = 北（野生エリア側）、+Z = 南（拠点側）。Y = 高さ。単位は studs。
--
-- 設定値はすべて DinoConfig（World / Ranch / Wild）から読む（CLAUDE.md 5章）。
-- 起動時に必要なキーがそろっているかを確かめ、足りなければその場でエラーにする。

local WorldLayout = {}
WorldLayout.__index = WorldLayout

-- Terrain のボクセル1マスの大きさ（Roblox の仕様で 4 固定。設定値ではない）
local VOXEL = 4

-- ── 小さな道具 ────────────────────────────────────────
-- 必要な設定キー（DinoConfig.<セクション>.<キー>）
local REQUIRED_KEYS = {
	World = {
		"Seed", "MapSizeX", "MapSizeZ", "GroundLevel", "TerrainBottom",
		"HillAmplitude", "HillScale", "DetailAmplitude", "DetailScale",
		"EdgeHillWidth", "EdgeHillHeight", "FlattenBlend", "BoundaryWallHeight",
		"RockMaterialSlope", "GroundMaterialSlope",
		"WaterLevel", "PondCount", "PondRadiusMin", "PondRadiusMax", "PondDepth",
		"PondEdgeMargin", "PondSpacing", "PondShoreSlope",
		"RockCount", "RockRadiusMin", "RockRadiusMax", "RockEdgeMargin", "RockPondGap", "RockSpacing",
		"TreeCount", "TreeEdgeMargin", "TreePondGap", "TreeRockGap", "TreeSpacing", "TreeTrunkRadius",
		"TreeTrunkHeightMin", "TreeTrunkHeightMax", "TreeCanopySizeMin", "TreeCanopySizeMax",
		"WildMaxSlope", "WildSpawnObstacleMargin",
		"SlotSpawnHeightOffset", "PlayerSpawnHeightOffset", "PlayerSpawnPadSize",
		"RanchSignMaxDistance", "ReadyTimeout", "ReadyPollInterval",
	},
	Ranch = {
		"FencePlotSize", "InitialPlotsX", "InitialPlotsZ", "FenceHeight", "FenceMargin",
		"SlotCount", "SlotSpacing", "RanchBackGap", "PlazaDepth", "WildEdgeBuffer",
		"GateWidth", "PostSpacing", "SpawnOffsetFromGate",
	},
	Wild = { "MinSpawnDistanceFromRanch" },
}

-- 必要なキーがすべて数値で入っているか確かめる（足りなければ assert でエラー）
function WorldLayout.validateConfig(dinoConfig)
	for section, keys in REQUIRED_KEYS do
		local values = dinoConfig[section]
		assert(type(values) == "table", "DinoConfig." .. section .. " がありません")
		for _, key in keys do
			assert(
				type(values[key]) == "number",
				"DinoConfig." .. section .. "." .. key .. " がありません（数値が必要）"
			)
		end
	end
	assert(type(dinoConfig.Text) == "table" and type(dinoConfig.Text.VacantRanchLabel) == "string",
		"DinoConfig.Text.VacantRanchLabel がありません（文字列が必要）")
end

local function clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

local function smoothstep(t: number): number
	t = clamp01(t)
	return t * t * (3 - 2 * t)
end

local function snap(value: number): number
	return math.floor(value / VOXEL + 0.5) * VOXEL
end

-- 点 (x, z) から長方形までの距離（内側なら 0）
local function distToRect(x: number, z: number, r): number
	local dx = math.max(r.MinX - x, 0, x - r.MaxX)
	local dz = math.max(r.MinZ - z, 0, z - r.MaxZ)
	return math.sqrt(dx * dx + dz * dz)
end

local function inRect(x: number, z: number, r): boolean
	return x >= r.MinX and x <= r.MaxX and z >= r.MinZ and z <= r.MaxZ
end

-- 決まった並びの乱数（Park–Miller）。Roblox の Random と同じ呼び方
-- （:NextNumber(min, max) / :NextInteger(min, max)）ができる。
local Prng = {}
Prng.__index = Prng

function Prng.new(seed: number)
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	return setmetatable({ State = state }, Prng)
end

function Prng:NextNumber(minValue: number?, maxValue: number?): number
	self.State = (self.State * 48271) % 2147483647
	local u = (self.State - 1) / 2147483646
	local lo = minValue or 0
	local hi = maxValue or 1
	return lo + (hi - lo) * u
end

function Prng:NextInteger(minValue: number, maxValue: number): number
	return math.min(maxValue, minValue + math.floor(self:NextNumber() * (maxValue - minValue + 1)))
end

WorldLayout.Prng = Prng

-- ── 生成 ─────────────────────────────────────────────
-- dinoConfig: ReplicatedStorage.Shared.DinoConfig の中身（テーブル）
function WorldLayout.new(dinoConfig)
	WorldLayout.validateConfig(dinoConfig)
	local self = setmetatable({}, WorldLayout)
	self.World = dinoConfig.World
	self.Ranch = dinoConfig.Ranch
	self.Wild = dinoConfig.Wild
	self.Text = dinoConfig.Text

	local w, r = self.World, self.Ranch
	self.HalfX = w.MapSizeX / 2
	self.HalfZ = w.MapSizeZ / 2
	-- 外周の丘の内側（歩き回れる範囲）
	self.PlayArea = {
		MinX = -self.HalfX + w.EdgeHillWidth,
		MaxX = self.HalfX - w.EdgeHillWidth,
		MinZ = -self.HalfZ + w.EdgeHillWidth,
		MaxZ = self.HalfZ - w.EdgeHillWidth,
	}

	-- 拠点スロット: マップの南側に東西一列に並べる
	local slotHalf = r.SlotSpacing / 2
	local slotZ = snap(self.PlayArea.MaxZ - r.RanchBackGap - slotHalf)
	self.Slots = {}
	for index = 1, r.SlotCount do
		local cx = snap((index - (r.SlotCount + 1) / 2) * r.SlotSpacing)
		table.insert(self.Slots, {
			Index = index,
			CenterX = cx,
			CenterZ = slotZ,
			-- 敷地（将来区画を増やしてよい範囲）
			Reserve = { MinX = cx - slotHalf, MaxX = cx + slotHalf, MinZ = slotZ - slotHalf, MaxZ = slotZ + slotHalf },
		})
	end

	local rowHalfWidth = r.SlotCount * r.SlotSpacing / 2
	-- 拠点エリア（スロットの敷地の帯）と、その北側の広場
	self.RanchStrip = { MinX = -rowHalfWidth, MaxX = rowHalfWidth, MinZ = slotZ - slotHalf, MaxZ = slotZ + slotHalf }
	self.Plaza = {
		MinX = -rowHalfWidth,
		MaxX = rowHalfWidth,
		MinZ = slotZ - slotHalf - r.PlazaDepth,
		MaxZ = slotZ - slotHalf,
	}
	-- 地面を平らにする範囲 = 拠点エリア + 広場
	self.FlatArea = {
		MinX = self.RanchStrip.MinX,
		MaxX = self.RanchStrip.MaxX,
		MinZ = self.Plaza.MinZ,
		MaxZ = self.RanchStrip.MaxZ,
	}

	-- プレイヤーの出現地点（広場の中央）
	self.PlayerSpawn = { X = 0, Y = w.GroundLevel, Z = snap((self.Plaza.MinZ + self.Plaza.MaxZ) / 2) }

	-- 野生恐竜の出現範囲（北側の草原）。拠点の中心から MinSpawnDistanceFromRanch 以上、
	-- かつ広場から WildEdgeBuffer 以上離れるように南端を決める
	local wildMaxZ = math.min(self.Plaza.MinZ - r.WildEdgeBuffer, slotZ - self.Wild.MinSpawnDistanceFromRanch)
	self.WildArea = { MinX = self.PlayArea.MinX, MaxX = self.PlayArea.MaxX, MinZ = self.PlayArea.MinZ, MaxZ = wildMaxZ }

	-- 地形ノイズの位置ずらし（シードで決まる。格子点でノイズが 0 になるのを避ける）
	local rng = Prng.new(w.Seed)
	self.NoiseOffset = { rng:NextNumber(100, 900) + 0.37, rng:NextNumber(100, 900) + 0.61 }

	-- 池・岩・木の配置（すべて野生エリア内、シードで決定）
	self.Ponds = {}
	self.Rocks = {}
	self.Trees = {}
	local wild = self.WildArea
	local function farFromAll(list, x, z, extra)
		for _, item in list do
			local dx, dz = item.X - x, item.Z - z
			if math.sqrt(dx * dx + dz * dz) < item.Radius + extra then
				return false
			end
		end
		return true
	end
	local attempts = 0
	while #self.Ponds < w.PondCount and attempts < 500 do
		attempts += 1
		local radius = rng:NextNumber(w.PondRadiusMin, w.PondRadiusMax)
		local margin = radius + w.PondEdgeMargin
		local x = rng:NextNumber(wild.MinX + margin, wild.MaxX - margin)
		local z = rng:NextNumber(wild.MinZ + margin, wild.MaxZ - margin)
		if farFromAll(self.Ponds, x, z, radius + w.PondSpacing) then
			table.insert(self.Ponds, { X = x, Z = z, Radius = radius })
		end
	end
	attempts = 0
	while #self.Rocks < w.RockCount and attempts < 2000 do
		attempts += 1
		local radius = rng:NextNumber(w.RockRadiusMin, w.RockRadiusMax)
		local x = rng:NextNumber(wild.MinX + w.RockEdgeMargin, wild.MaxX - w.RockEdgeMargin)
		local z = rng:NextNumber(wild.MinZ + w.RockEdgeMargin, wild.MaxZ - w.RockEdgeMargin)
		if
			farFromAll(self.Ponds, x, z, radius + w.RockPondGap)
			and farFromAll(self.Rocks, x, z, radius + w.RockSpacing)
		then
			table.insert(self.Rocks, { X = x, Z = z, Radius = radius })
		end
	end
	attempts = 0
	while #self.Trees < w.TreeCount and attempts < 2000 do
		attempts += 1
		local x = rng:NextNumber(wild.MinX + w.TreeEdgeMargin, wild.MaxX - w.TreeEdgeMargin)
		local z = rng:NextNumber(wild.MinZ + w.TreeEdgeMargin, wild.MaxZ - w.TreeEdgeMargin)
		if
			farFromAll(self.Ponds, x, z, w.TreePondGap)
			and farFromAll(self.Rocks, x, z, w.TreeRockGap)
			and farFromAll(self.Trees, x, z, w.TreeSpacing)
		then
			table.insert(self.Trees, {
				X = x,
				Z = z,
				Radius = w.TreeTrunkRadius, -- 幹の半径（出現判定用）
				TrunkHeight = rng:NextNumber(w.TreeTrunkHeightMin, w.TreeTrunkHeightMax),
				CanopySize = rng:NextNumber(w.TreeCanopySizeMin, w.TreeCanopySizeMax),
				Shade = rng:NextNumber(0, 1),
			})
		end
	end

	return self
end

-- ── 地形の高さ ────────────────────────────────────────
-- (x, z) の地面の高さ。TerrainGen はこの値どおりに Terrain を作るので、
-- レイキャストしなくても地面のだいたいの高さ（誤差1stud程度）がわかる。
function WorldLayout:getGroundHeight(x: number, z: number): number
	local w = self.World
	local ox, oz = self.NoiseOffset[1], self.NoiseOffset[2]
	local g = w.GroundLevel

	-- ゆるい起伏 + 細かいでこぼこ
	local h: number = g
		+ w.HillAmplitude * 2 * math.noise(x / w.HillScale + ox, z / w.HillScale + oz)
		+ w.DetailAmplitude * 2 * math.noise(x / w.DetailScale + oz, z / w.DetailScale + ox, 0.5)
	-- 池以外に水たまりができないよう、水面より少し上で止める
	h = math.max(h, w.WaterLevel + 2)

	-- 拠点エリアと広場は完全に平ら。周りはなめらかにつなぐ
	local d = distToRect(x, z, self.FlatArea)
	h = g + (h - g) * smoothstep(d / w.FlattenBlend)

	-- 池: すり鉢状に掘る
	for _, pond in self.Ponds do
		local dx, dz = x - pond.X, z - pond.Z
		local r = math.sqrt(dx * dx + dz * dz)
		local target: number
		if r < pond.Radius then
			local t = r / pond.Radius
			target = w.WaterLevel - w.PondDepth * (1 - t * t)
		else
			target = w.WaterLevel + (r - pond.Radius) * w.PondShoreSlope
		end
		h = math.min(h, target :: number)
	end

	-- 外周の丘（マップの外に出られない見た目の囲い）
	local edgeDist = math.min(self.HalfX - math.abs(x), self.HalfZ - math.abs(z))
	local t = clamp01((w.EdgeHillWidth - edgeDist) / w.EdgeHillWidth)
	if t > 0 then
		local wobble = 0.75 + 0.5 * (math.noise(x / 60 + ox, z / 60 + oz, 1.5) + 0.5)
		h += w.EdgeHillHeight * t * t * wobble
	end

	return math.clamp(h, w.TerrainBottom + 1, w.GroundLevel + w.EdgeHillHeight * 2)
end

-- 地面の傾き（隣との高さの差 / 距離）
function WorldLayout:getSlope(x: number, z: number): number
	local h = self:getGroundHeight(x, z)
	local dx = math.abs(self:getGroundHeight(x + VOXEL, z) - h)
	local dz = math.abs(self:getGroundHeight(x, z + VOXEL) - h)
	return math.max(dx, dz) / VOXEL
end

-- 地表の素材名（Enum.Material の名前）。使う側で Enum.Material[name] に変換する
function WorldLayout:getSurfaceMaterialName(x: number, z: number, height: number?): string
	local w = self.World
	local h = height or self:getGroundHeight(x, z)
	if inRect(x, z, self.Plaza) then
		return "Ground" -- 広場・通路は土
	end
	if h < w.WaterLevel + 1.5 then
		return "Sand" -- 水辺
	end
	local slope = self:getSlope(x, z)
	if slope > w.RockMaterialSlope then
		return "Rock"
	elseif slope > w.GroundMaterialSlope then
		return "Ground"
	end
	return "Grass"
end

function WorldLayout:isInWater(x: number, z: number): boolean
	return self:getGroundHeight(x, z) < self.World.WaterLevel + 0.5
end

-- ── 拠点スロット・区画 ───────────────────────────────────
-- 区画（Plot）はスロットごとの格子番号 (PX, PZ) で表す。初期は
-- PX = 0..InitialPlotsX-1, PZ = 0..InitialPlotsZ-1 で、スロット中心に対して中央ぞろえ。
-- 後から (-1, 0) や (2, 1) などを足せば柵がその分広がる（RanchWorld.addPlot）。

function WorldLayout:getSlot(slotIndex: number)
	local slot = self.Slots[slotIndex]
	assert(slot, "拠点スロット番号が範囲外: " .. tostring(slotIndex))
	return slot
end

function WorldLayout:getInitialPlots(): { { PX: number, PZ: number } }
	local plots = {}
	for pz = 0, self.Ranch.InitialPlotsZ - 1 do
		for px = 0, self.Ranch.InitialPlotsX - 1 do
			table.insert(plots, { PX = px, PZ = pz })
		end
	end
	return plots
end

-- 区画の長方形（柵の線の位置）
function WorldLayout:getPlotRect(slotIndex: number, px: number, pz: number)
	local slot = self:getSlot(slotIndex)
	local size = self.Ranch.FencePlotSize
	local originX = slot.CenterX - self.Ranch.InitialPlotsX * size / 2
	local originZ = slot.CenterZ - self.Ranch.InitialPlotsZ * size / 2
	local minX = originX + px * size
	local minZ = originZ + pz * size
	return { MinX = minX, MaxX = minX + size, MinZ = minZ, MaxZ = minZ + size }
end

local function plotKey(px: number, pz: number): string
	return tostring(px) .. "_" .. tostring(pz)
end
WorldLayout.plotKey = plotKey

local function plotSet(plots)
	local set = {}
	for _, p in plots do
		set[plotKey(p.PX, p.PZ)] = true
	end
	return set
end

-- 入口を付ける区画: いちばん北（PZ 最小）の列の、列の真ん中に近い区画（同点は西側）
function WorldLayout:getGatePlot(plots)
	local minPZ = math.huge
	for _, p in plots do
		minPZ = math.min(minPZ, p.PZ)
	end
	local row = {}
	local sum = 0
	for _, p in plots do
		if p.PZ == minPZ then
			table.insert(row, p)
			sum += p.PX
		end
	end
	local mid = sum / #row
	local best = nil
	for _, p in row do
		if
			best == nil
			or math.abs(p.PX - mid) < math.abs(best.PX - mid) - 1e-9
			or (math.abs(math.abs(p.PX - mid) - math.abs(best.PX - mid)) <= 1e-9 and p.PX < best.PX)
		then
			best = p
		end
	end
	return best
end

-- 入口（北側の柵のすき間）の中心座標と、入口の外側の出入り地点
function WorldLayout:getGateInfo(slotIndex: number, plots)
	local gate = self:getGatePlot(plots)
	local rect = self:getPlotRect(slotIndex, gate.PX, gate.PZ)
	local gx = (rect.MinX + rect.MaxX) / 2
	local gz = rect.MinZ
	return {
		PX = gate.PX,
		PZ = gate.PZ,
		X = gx,
		Z = gz,
		OutsideX = gx,
		OutsideZ = gz - self.Ranch.SpawnOffsetFromGate,
	}
end

-- 柵の組み立て情報（区画ごと）。区画が隣り合う辺には柵を立てない。
-- 各区画の外周を同じ向き（上から見て時計回り）にたどり、辺の「始点側」の杭だけを
-- その区画が持つので、角の杭が重複しない。
-- 戻り値: { { PX, PZ, Key, Posts = {{X, Z}}, Segments = {{X0, Z0, X1, Z1}}, HasGate } }
function WorldLayout:computeFence(slotIndex: number, plots)
	local set = plotSet(plots)
	local gate = self:getGatePlot(plots)
	local spacing = self.Ranch.PostSpacing
	local gateHalf = self.Ranch.GateWidth / 2
	local result = {}

	for _, p in plots do
		local rect = self:getPlotRect(slotIndex, p.PX, p.PZ)
		-- 4辺: 始点, 終点, その辺の向こう側の区画
		local sides = {
			{ rect.MinX, rect.MinZ, rect.MaxX, rect.MinZ, p.PX, p.PZ - 1, true }, -- 北（入口の候補）
			{ rect.MaxX, rect.MinZ, rect.MaxX, rect.MaxZ, p.PX + 1, p.PZ, false }, -- 東
			{ rect.MaxX, rect.MaxZ, rect.MinX, rect.MaxZ, p.PX, p.PZ + 1, false }, -- 南
			{ rect.MinX, rect.MaxZ, rect.MinX, rect.MinZ, p.PX - 1, p.PZ, false }, -- 西
		}
		local posts = {}
		local segments = {}
		local hasGate = false
		for _, side in sides do
			local x0, z0, x1, z1, nx, nz, isNorth = side[1], side[2], side[3], side[4], side[5], side[6], side[7]
			if not set[plotKey(nx, nz)] then
				local length = math.abs(x1 - x0) + math.abs(z1 - z0)
				local ux, uz = (x1 - x0) / length, (z1 - z0) / length
				local withGate = isNorth and gate.PX == p.PX and gate.PZ == p.PZ
				local gapFrom, gapTo = math.huge, -math.huge
				if withGate then
					hasGate = true
					gapFrom = length / 2 - gateHalf
					gapTo = length / 2 + gateHalf
				end
				-- 杭: 始点から spacing ごと（終点は次の辺の始点なので置かない）。入口の中は置かない
				local s = 0
				while s < length - 1e-6 do
					if s < gapFrom - 1e-6 or s > gapTo + 1e-6 then
						table.insert(posts, { X = x0 + ux * s, Z = z0 + uz * s })
					end
					s += spacing
				end
				if withGate then
					-- 入口の両脇の杭（門柱）
					table.insert(posts, { X = x0 + ux * gapFrom, Z = z0 + uz * gapFrom, Gate = true })
					table.insert(posts, { X = x0 + ux * gapTo, Z = z0 + uz * gapTo, Gate = true })
					table.insert(segments, { X0 = x0, Z0 = z0, X1 = x0 + ux * gapFrom, Z1 = z0 + uz * gapFrom })
					table.insert(segments, { X0 = x0 + ux * gapTo, Z0 = z0 + uz * gapTo, X1 = x1, Z1 = z1 })
				else
					table.insert(segments, { X0 = x0, Z0 = z0, X1 = x1, Z1 = z1 })
				end
			end
		end
		table.insert(result, {
			PX = p.PX,
			PZ = p.PZ,
			Key = plotKey(p.PX, p.PZ),
			Posts = posts,
			Segments = segments,
			HasGate = hasGate,
		})
	end
	return result
end

-- 柵の内側か。margin（省略時 DinoConfig.Ranch.FenceMargin）だけ柵から離れた範囲で判定する。
-- 隣に区画がある辺には柵が無いので、そちら側には margin をとらない。
function WorldLayout:isInsideRanch(slotIndex: number, plots, x: number, z: number, margin: number?): boolean
	local m = if margin == nil then self.Ranch.FenceMargin else margin
	local set = plotSet(plots)
	for _, p in plots do
		local rect = self:getPlotRect(slotIndex, p.PX, p.PZ)
		local minX = rect.MinX + (if set[plotKey(p.PX - 1, p.PZ)] then 0 else m)
		local maxX = rect.MaxX - (if set[plotKey(p.PX + 1, p.PZ)] then 0 else m)
		local minZ = rect.MinZ + (if set[plotKey(p.PX, p.PZ - 1)] then 0 else m)
		local maxZ = rect.MaxZ - (if set[plotKey(p.PX, p.PZ + 1)] then 0 else m)
		if x >= minX and x <= maxX and z >= minZ and z <= maxZ then
			return true
		end
	end
	return false
end

-- 柵全体を囲む長方形（margin だけ内側）。区画が長方形に並んでいれば柵の内側とぴったり一致する
function WorldLayout:getRanchBounds(slotIndex: number, plots, margin: number?)
	local m = if margin == nil then self.Ranch.FenceMargin else margin
	local b = { MinX = math.huge, MaxX = -math.huge, MinZ = math.huge, MaxZ = -math.huge }
	for _, p in plots do
		local rect = self:getPlotRect(slotIndex, p.PX, p.PZ)
		b.MinX = math.min(b.MinX, rect.MinX)
		b.MaxX = math.max(b.MaxX, rect.MaxX)
		b.MinZ = math.min(b.MinZ, rect.MinZ)
		b.MaxZ = math.max(b.MaxZ, rect.MaxZ)
	end
	b.MinX += m
	b.MaxX -= m
	b.MinZ += m
	b.MaxZ -= m
	return b
end

-- 柵の内側（margin 付き）のランダムな1点。rng は Random（:NextNumber を持つもの）
function WorldLayout:getRandomPointInRanch(slotIndex: number, plots, rng, margin: number?): (number, number)
	local b = self:getRanchBounds(slotIndex, plots, margin)
	-- 長方形に並んでいれば1回目で必ず当たる。L字などでも数回で当たる
	for _ = 1, 30 do
		local x = rng:NextNumber(b.MinX, b.MaxX)
		local z = rng:NextNumber(b.MinZ, b.MaxZ)
		if self:isInsideRanch(slotIndex, plots, x, z, margin) then
			return x, z
		end
	end
	local slot = self:getSlot(slotIndex)
	return slot.CenterX, slot.CenterZ
end

-- 柵の内側（margin 付き）に収めた座標。外にはみ出た目的地を内側に戻すのに使う
function WorldLayout:clampToRanch(slotIndex: number, plots, x: number, z: number, margin: number?): (number, number)
	if self:isInsideRanch(slotIndex, plots, x, z, margin) then
		return x, z
	end
	local m = if margin == nil then self.Ranch.FenceMargin else margin
	local set = plotSet(plots)
	local bestX, bestZ, bestD = x, z, math.huge
	for _, p in plots do
		local rect = self:getPlotRect(slotIndex, p.PX, p.PZ)
		local minX = rect.MinX + (if set[plotKey(p.PX - 1, p.PZ)] then 0 else m)
		local maxX = rect.MaxX - (if set[plotKey(p.PX + 1, p.PZ)] then 0 else m)
		local minZ = rect.MinZ + (if set[plotKey(p.PX, p.PZ - 1)] then 0 else m)
		local maxZ = rect.MaxZ - (if set[plotKey(p.PX, p.PZ + 1)] then 0 else m)
		local cx = math.clamp(x, minX, maxX)
		local cz = math.clamp(z, minZ, maxZ)
		local d = (cx - x) ^ 2 + (cz - z) ^ 2
		if d < bestD then
			bestX, bestZ, bestD = cx, cz, d
		end
	end
	return bestX, bestZ
end

-- 区画を足してよい位置か（スロットの敷地内・重複なし・既存の区画と辺で隣接）
function WorldLayout:canAddPlot(slotIndex: number, plots, px: number, pz: number): (boolean, string?)
	local set = plotSet(plots)
	if set[plotKey(px, pz)] then
		return false, "AlreadyExists"
	end
	local rect = self:getPlotRect(slotIndex, px, pz)
	local reserve = self:getSlot(slotIndex).Reserve
	if rect.MinX < reserve.MinX or rect.MaxX > reserve.MaxX or rect.MinZ < reserve.MinZ or rect.MaxZ > reserve.MaxZ then
		return false, "OutsideReserve"
	end
	if
		not (
			set[plotKey(px - 1, pz)]
			or set[plotKey(px + 1, pz)]
			or set[plotKey(px, pz - 1)]
			or set[plotKey(px, pz + 1)]
		)
	then
		return false, "NotAdjacent"
	end
	return true, nil
end

-- ── 野生恐竜の出現範囲 ─────────────────────────────────
-- (x, z) が野生恐竜を出してよい場所か。
-- 条件: 出現範囲の長方形の中 / どの拠点スロットの中心からも MinSpawnDistanceFromRanch 以上 /
--       水の中でない / 岩・木の幹に重ならない / 急な斜面でない
function WorldLayout:isWildSpawnable(x: number, z: number): (boolean, string?)
	if not inRect(x, z, self.WildArea) then
		return false, "OutsideWildArea"
	end
	local minDist = self.Wild.MinSpawnDistanceFromRanch
	for _, slot in self.Slots do
		local dx, dz = x - slot.CenterX, z - slot.CenterZ
		if math.sqrt(dx * dx + dz * dz) < minDist then
			return false, "NearRanch"
		end
	end
	if self:isInWater(x, z) then
		return false, "Water"
	end
	local obstacleMargin = self.World.WildSpawnObstacleMargin
	for _, rock in self.Rocks do
		local dx, dz = x - rock.X, z - rock.Z
		if math.sqrt(dx * dx + dz * dz) < rock.Radius + obstacleMargin then
			return false, "Rock"
		end
	end
	for _, tree in self.Trees do
		local dx, dz = x - tree.X, z - tree.Z
		if math.sqrt(dx * dx + dz * dz) < tree.Radius + obstacleMargin then
			return false, "Tree"
		end
	end
	if self:getSlope(x, z) > self.World.WildMaxSlope then
		return false, "Steep"
	end
	return true, nil
end

-- 野生恐竜の出現地点をランダムに1つ選ぶ。
-- avoidPoints: 近づけたくない点 { {X, Z} }（例: プレイヤーの位置）, avoidDistance: その距離
-- 戻り値: x, y(地面の高さ), z。見つからなければ nil
function WorldLayout:getRandomWildSpawnPoint(rng, avoidPoints, avoidDistance: number?): (number?, number?, number?)
	local area = self.WildArea
	for _ = 1, 60 do
		local x = rng:NextNumber(area.MinX, area.MaxX)
		local z = rng:NextNumber(area.MinZ, area.MaxZ)
		local ok = self:isWildSpawnable(x, z)
		if ok and avoidPoints and avoidDistance then
			for _, point in avoidPoints do
				local dx, dz = x - point.X, z - point.Z
				if math.sqrt(dx * dx + dz * dz) < avoidDistance then
					ok = false
					break
				end
			end
		end
		if ok then
			return x, self:getGroundHeight(x, z), z
		end
	end
	return nil, nil, nil
end

-- 野生恐竜が歩いてよい場所か（うろつきの目的地チェック用）。
-- 拠点エリア・広場とその周り WildEdgeBuffer には入らない。水・マップ外周の丘にも入らない。
function WorldLayout:isWildWalkable(x: number, z: number): boolean
	if not inRect(x, z, self.PlayArea) then
		return false
	end
	if distToRect(x, z, self.FlatArea) < self.Ranch.WildEdgeBuffer then
		return false
	end
	return not self:isInWater(x, z)
end

return WorldLayout
