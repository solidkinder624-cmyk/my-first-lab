-- 草原バイオームの Terrain を手続き生成する（サーバー起動時に WorldBoot から1回だけ呼ぶ）。
--
-- 高さ・地表の素材はすべて WorldLayout の計算どおりに作るので、
-- WorldLayout:getGroundHeight(x, z) で「その場所の地面の高さ」を後から取り出せる。
-- 生成は WriteVoxels をチャンク（128x128 studs）ごとに行い、合間に task.wait() で処理を譲る。

local TerrainGen = {}

local VOXEL = 4 -- Terrain のボクセルの大きさ（Roblox の仕様）
local CHUNK_CELLS = 32 -- 1チャンクの一辺のマス数（32マス = 128 studs）

-- 草原らしい明るめの色（素材の色は Terrain 全体の設定）
local MATERIAL_COLORS = {
	Grass = Color3.fromRGB(111, 170, 76),
	LeafyGrass = Color3.fromRGB(96, 156, 64),
	Ground = Color3.fromRGB(135, 110, 80),
	Sand = Color3.fromRGB(214, 198, 150),
	Rock = Color3.fromRGB(128, 124, 116),
	Mud = Color3.fromRGB(96, 78, 58),
}

local function applyMaterialColors(terrain: Terrain)
	for name, color in MATERIAL_COLORS do
		terrain:SetMaterialColor(Enum.Material[name], color)
	end
	terrain.WaterColor = Color3.fromRGB(60, 140, 170)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.08
	terrain.WaterReflectance = 0.2
end

-- 1チャンク分の地面を書き込む
local function writeChunk(terrain: Terrain, layout, x0: number, z0: number, cellsX: number, cellsZ: number)
	local world = layout.World
	local bottom = world.TerrainBottom

	-- 各列（x, z）の高さと地表の素材を先に計算
	local heights = table.create(cellsX)
	local surface = table.create(cellsX)
	local maxH = bottom
	for ix = 1, cellsX do
		local hx = table.create(cellsZ)
		local sx = table.create(cellsZ)
		local x = x0 + (ix - 0.5) * VOXEL
		for iz = 1, cellsZ do
			local z = z0 + (iz - 0.5) * VOXEL
			local h = layout:getGroundHeight(x, z)
			hx[iz] = h
			sx[iz] = Enum.Material[layout:getSurfaceMaterialName(x, z, h)]
			maxH = math.max(maxH, h)
		end
		heights[ix] = hx
		surface[ix] = sx
	end

	local cellsY = math.max(1, math.ceil((maxH - bottom) / VOXEL))
	local materials = table.create(cellsX)
	local occupancies = table.create(cellsX)
	for ix = 1, cellsX do
		local matX = table.create(cellsY)
		local occX = table.create(cellsY)
		for iy = 1, cellsY do
			local cellBottom = bottom + (iy - 1) * VOXEL
			local matY = table.create(cellsZ)
			local occY = table.create(cellsZ)
			for iz = 1, cellsZ do
				local h = heights[ix][iz]
				local occ = math.clamp((h - cellBottom) / VOXEL, 0, 1)
				if occ <= 0.02 then
					matY[iz] = Enum.Material.Air
					occY[iz] = 0
				else
					-- 地表から 8 studs までは地表の素材、それより深いところは土
					matY[iz] = if h - cellBottom <= VOXEL * 2 then surface[ix][iz] else Enum.Material.Ground
					occY[iz] = occ
				end
			end
			matX[iy] = matY
			occX[iy] = occY
		end
		materials[ix] = matX
		occupancies[ix] = occX
	end

	local region = Region3.new(
		Vector3.new(x0, bottom, z0),
		Vector3.new(x0 + cellsX * VOXEL, bottom + cellsY * VOXEL, z0 + cellsZ * VOXEL)
	)
	terrain:WriteVoxels(region, VOXEL, materials, occupancies)
end

-- 池に水を張る（池のくぼみの空気を水に置きかえる）
local function fillPonds(terrain: Terrain, layout)
	local world = layout.World
	for _, pond in layout.Ponds do
		local r = pond.Radius + VOXEL * 2
		local region = Region3.new(
			Vector3.new(pond.X - r, world.TerrainBottom, pond.Z - r),
			Vector3.new(pond.X + r, world.WaterLevel, pond.Z + r)
		):ExpandToGrid(VOXEL)
		terrain:ReplaceMaterial(region, VOXEL, Enum.Material.Air, Enum.Material.Water)
	end
end

-- 岩（Terrain の Rock の球。パーツを使わないので軽い）
local function placeRocks(terrain: Terrain, layout)
	for _, rock in layout.Rocks do
		local y = layout:getGroundHeight(rock.X, rock.Z)
		terrain:FillBall(Vector3.new(rock.X, y + rock.Radius * 0.15, rock.Z), rock.Radius, Enum.Material.Rock)
	end
end

-- Terrain をすべて作り直す。既存の Terrain は消える（毎回同じ地形にするため）。
-- 飛ばしたいときは Workspace.Ranch に属性 SkipProceduralTerrain = true を付ける（WorldBoot が見る）。
function TerrainGen.generate(terrain: Terrain, layout)
	-- ★このワールドの地形は手続き生成（プログラムで自動生成）。Studio で手作業で編集した Terrain は
	--   ここで消えて、WorldLayout の計算どおりに作り直される。地形を変えたいときは
	--   DinoConfig.World の値を変えること（手作業の地形を残したいなら SkipProceduralTerrain を使う）。
	terrain:Clear()
	applyMaterialColors(terrain)

	local minX = -layout.HalfX
	local minZ = -layout.HalfZ
	local totalX = math.ceil(layout.World.MapSizeX / VOXEL)
	local totalZ = math.ceil(layout.World.MapSizeZ / VOXEL)

	for cx = 0, totalX - 1, CHUNK_CELLS do
		for cz = 0, totalZ - 1, CHUNK_CELLS do
			local cellsX = math.min(CHUNK_CELLS, totalX - cx)
			local cellsZ = math.min(CHUNK_CELLS, totalZ - cz)
			writeChunk(terrain, layout, minX + cx * VOXEL, minZ + cz * VOXEL, cellsX, cellsZ)
		end
		task.wait() -- 1列（東西方向のチャンク1本）ごとに処理を譲る
	end

	fillPonds(terrain, layout)
	placeRocks(terrain, layout)
end

-- 1区画分の床を牧草（LeafyGrass）で塗る。区画を追加したときにも呼ぶ。
-- 地面は GroundLevel ちょうどで平らなので、その下1マスだけを塗り替える。
function TerrainGen.paintPlot(terrain: Terrain, layout, rect)
	local g = layout.World.GroundLevel
	local sizeX = rect.MaxX - rect.MinX
	local sizeZ = rect.MaxZ - rect.MinZ
	terrain:FillBlock(
		CFrame.new((rect.MinX + rect.MaxX) / 2, g - VOXEL / 2, (rect.MinZ + rect.MaxZ) / 2),
		Vector3.new(sizeX, VOXEL, sizeZ),
		Enum.Material.LeafyGrass
	)
end

return TerrainGen
