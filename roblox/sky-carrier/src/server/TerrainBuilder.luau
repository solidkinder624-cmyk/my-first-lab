-- Terrain.luau (純ロジック) が返す配置を実際の Part にする。3Dモデル・
-- テクスチャは使わず、Shape=Ball / Block の非一様スケールと色分けだけで
-- 山・島・ビルの見た目を作る。ゾーンの地形は毎セッション同じになるよう
-- 固定シードを使う (対戦の公平性ではなく、みんなが同じ地図を見るため)。

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SkyCarrier")
local Terrain = require(Shared.Terrain)

local TerrainBuilder = {}

local ZONE_SEEDS = { Mountain = 10007, Ocean = 20011, Urban = 30019 }
local ZONE_LABELS = { Mountain = "山岳エリア", Ocean = "海洋エリア", Urban = "都市エリア" }

local APPEARANCE = {
	Mountain = { color = Color3.fromRGB(120, 110, 100), material = Enum.Material.Rock },
	Island = { color = Color3.fromRGB(150, 160, 110), material = Enum.Material.Grass },
	Building = { color = Color3.fromRGB(150, 155, 165), material = Enum.Material.Concrete },
}

local function buildFeature(feature, folder: Instance)
	local appearance = APPEARANCE[feature.kind]
	local part = Instance.new("Part")
	part.Name = feature.kind
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = false -- 数十個規模になるので、影の計算コストを避ける
	part.Shape = if feature.kind == "Building" then Enum.PartType.Block else Enum.PartType.Ball
	part.Size = Vector3.new(feature.sx, feature.sy, feature.sz)
	part.CFrame = CFrame.new(feature.cx, feature.cy, feature.cz)
	part.Color = appearance.color:Lerp(Color3.new(1, 1, 1), (feature.cx % 17) / 17 * 0.15) -- 単調さを消す色ゆらぎ
	part.Material = appearance.material
	part.Parent = folder
end

local function buildLabel(centerX: number, centerZ: number, groundHeight: number, text: string, folder: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "ZoneLabelAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(centerX, groundHeight + 40, centerZ)
	anchor.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 260, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextColor3 = Color3.fromRGB(235, 240, 245)
	label.TextTransparency = 0.25
	label.TextStrokeTransparency = 0.6
	label.TextScaled = true
	label.Text = text
	label.Parent = billboard
end

-- 海洋エリアの水面 (非衝突。飛行機は上を通過するだけで、着水は扱わない)。
local function buildWater(zoneCfg, folder: Instance)
	local water = Instance.new("Part")
	water.Name = "Water"
	water.Anchored = true
	water.CanCollide = false
	water.CanQuery = false
	water.CastShadow = false
	water.Size = Vector3.new(zoneCfg.radius * 2, 2, zoneCfg.radius * 2)
	water.CFrame = CFrame.new(zoneCfg.centerX, zoneCfg.waterLevel, zoneCfg.centerZ)
	water.Color = Color3.fromRGB(50, 110, 160)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.35
	water.Parent = folder
end

function TerrainBuilder.build(parentWorkspace: Instance, cfg)
	local folder = Instance.new("Folder")
	folder.Name = "SkyCarrierTerrain"
	folder.Parent = parentWorkspace

	for kind, zoneCfg in cfg.world.zones do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = kind
		zoneFolder.Parent = folder

		local features = Terrain.generate(kind, ZONE_SEEDS[kind], zoneCfg)
		for _, feature in features do
			buildFeature(feature, zoneFolder)
		end
		if kind == "Ocean" then
			buildWater(zoneCfg, zoneFolder)
		end
		buildLabel(zoneCfg.centerX, zoneCfg.centerZ, cfg.flight.groundHeight, ZONE_LABELS[kind], zoneFolder)
	end

	return folder
end

return TerrainBuilder
