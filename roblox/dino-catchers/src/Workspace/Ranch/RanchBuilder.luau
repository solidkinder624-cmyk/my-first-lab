-- 拠点（柵）・目印・景観のパーツを組み立てる。無料モデルは使わず Part だけで作る。
--
-- 性能の方針（恐竜30頭がいても重くしない）:
--   ・すべて Anchored。物理演算の対象にならない。
--   ・柵の見た目（杭・横木）は CanCollide / CanQuery / CanTouch をすべて false。
--     ぶつかり判定は柵の1辺につき透明な壁（Collider）1枚だけにまとめる。
--     Collider も CanQuery = false なので、テイム銃の射線や地面探しのレイキャストを邪魔しない。
--   ・区画どうしが接する辺には柵を作らない（外周だけ）。
--
-- 作るもの（Workspace.Ranch の下）:
--   Slots/Slot<N>                … 拠点スロット（Folder）。属性は RanchWorld のコメント参照
--     Plots/Plot_<PX>_<PZ>      … 区画1つ分（Folder）= 同じ部品を並べる単位
--       Area                    … 区画の床の範囲を表す透明パーツ
--       Post / Rail / Collider  … その区画が受け持つ柵
--     GateSign                  … 入口の上の看板（持ち主の名前を表示）
--   Markers/PlayerSpawn         … プレイヤーの出現地点（SpawnLocation）
--   Markers/WildSpawnArea       … 野生恐竜の出現範囲を表す透明パーツ
--   Scenery/Trees, Scenery/Bounds … 木と、マップ端の見えない壁

local RanchBuilder = {}

-- 見た目用の色（設定値ではなく見た目の調整値）
local WOOD_POST = Color3.fromRGB(110, 78, 50)
local WOOD_RAIL = Color3.fromRGB(150, 110, 70)
local TRUNK = Color3.fromRGB(105, 76, 52)
local LEAVES_A = Color3.fromRGB(70, 140, 60)
local LEAVES_B = Color3.fromRGB(100, 165, 70)

local POST_WIDTH = 1
local RAIL_THICKNESS = 0.5
local RAIL_HEIGHT = 0.7
local COLLIDER_THICKNESS = 1

local function makePart(name: string, parent: Instance, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- 見た目だけのパーツ（当たり判定なし）
local function makeVisual(name: string, parent: Instance, size: Vector3, cframe: CFrame): Part
	local part = makePart(name, parent, size, cframe)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- 目印（透明・判定なし）
local function makeMarker(name: string, parent: Instance, size: Vector3, cframe: CFrame): Part
	local part = makeVisual(name, parent, size, cframe)
	part.Transparency = 1
	part.CastShadow = false
	return part
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = parent
	return newFolder
end

-- ── 柵 ───────────────────────────────────────────────
local function buildFenceForPlot(layout, plotFolder: Folder, spec)
	local g = layout.World.GroundLevel
	local height = layout.Ranch.FenceHeight

	for _, post in spec.Posts do
		local postHeight = if post.Gate then height + 1.5 else height + 0.4
		local part = makeVisual(
			if post.Gate then "GatePost" else "Post",
			plotFolder,
			Vector3.new(POST_WIDTH, postHeight, POST_WIDTH),
			CFrame.new(post.X, g + postHeight / 2, post.Z)
		)
		part.Color = WOOD_POST
		part.Material = Enum.Material.Wood
	end

	for _, seg in spec.Segments do
		local length = math.abs(seg.X1 - seg.X0) + math.abs(seg.Z1 - seg.Z0)
		local alongX = math.abs(seg.X1 - seg.X0) > 0
		local cx, cz = (seg.X0 + seg.X1) / 2, (seg.Z0 + seg.Z1) / 2
		local function sized(thickness: number, tall: number): Vector3
			return if alongX then Vector3.new(length, tall, thickness) else Vector3.new(thickness, tall, length)
		end
		-- 横木2本（下・上）
		for _, ratio in { 0.4, 0.85 } do
			local rail = makeVisual("Rail", plotFolder, sized(RAIL_THICKNESS, RAIL_HEIGHT), CFrame.new(cx, g + height * ratio, cz))
			rail.Color = WOOD_RAIL
			rail.Material = Enum.Material.Wood
			rail.CastShadow = false
		end
		-- 当たり判定（透明な壁1枚）
		local collider = makePart("Collider", plotFolder, sized(COLLIDER_THICKNESS, height), CFrame.new(cx, g + height / 2, cz))
		collider.Transparency = 1
		collider.CanQuery = false
		collider.CanTouch = false
		collider.CastShadow = false
	end
end

local function buildGateSign(layout, slotFolder: Folder, slotIndex: number, plots)
	local old = slotFolder:FindFirstChild("GateSign")
	local previousText = nil
	if old then
		local label = old:FindFirstChild("Label", true)
		if label and label:IsA("TextLabel") then
			previousText = label.Text
		end
		old:Destroy()
	end

	local gate = layout:getGateInfo(slotIndex, plots)
	local g = layout.World.GroundLevel
	local height = layout.Ranch.FenceHeight
	local width = layout.Ranch.GateWidth
	local beam = makeVisual(
		"GateSign",
		slotFolder,
		Vector3.new(width + POST_WIDTH, 1, POST_WIDTH),
		CFrame.new(gate.X, g + height + 1, gate.Z)
	)
	beam.Color = WOOD_POST
	beam.Material = Enum.Material.Wood

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Billboard"
	billboard.Size = UDim2.new(0, 220, 0, 36)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.MaxDistance = 120
	billboard.Parent = beam
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = previousText or string.format("空き拠点 %d", slotIndex)
	label.Parent = billboard
end

-- スロットの柵・区画を作り直す（初回と、区画を追加したとき）
function RanchBuilder.rebuildSlot(layout, slotFolder: Folder, slotIndex: number, plots)
	local plotsFolder = getOrCreateFolder(slotFolder, "Plots")
	plotsFolder:ClearAllChildren()

	local g = layout.World.GroundLevel
	for _, spec in layout:computeFence(slotIndex, plots) do
		local plotFolder = Instance.new("Folder")
		plotFolder.Name = "Plot_" .. spec.Key
		plotFolder:SetAttribute("PlotX", spec.PX)
		plotFolder:SetAttribute("PlotZ", spec.PZ)

		local rect = layout:getPlotRect(slotIndex, spec.PX, spec.PZ)
		local area = makeMarker(
			"Area",
			plotFolder,
			Vector3.new(rect.MaxX - rect.MinX, 1, rect.MaxZ - rect.MinZ),
			CFrame.new((rect.MinX + rect.MaxX) / 2, g + 0.5, (rect.MinZ + rect.MaxZ) / 2)
		)
		area:SetAttribute("PlotX", spec.PX)
		area:SetAttribute("PlotZ", spec.PZ)

		buildFenceForPlot(layout, plotFolder, spec)
		plotFolder.Parent = plotsFolder
	end

	buildGateSign(layout, slotFolder, slotIndex, plots)

	-- 範囲を属性にも書いておく（dino-ai などがパーツを探さずに読めるように）
	local bounds = layout:getRanchBounds(slotIndex, plots, 0)
	slotFolder:SetAttribute("FenceMinX", bounds.MinX)
	slotFolder:SetAttribute("FenceMaxX", bounds.MaxX)
	slotFolder:SetAttribute("FenceMinZ", bounds.MinZ)
	slotFolder:SetAttribute("FenceMaxZ", bounds.MaxZ)
	slotFolder:SetAttribute("FenceMargin", layout.Ranch.FenceMargin)
	slotFolder:SetAttribute("PlotCount", #plots)
	local gate = layout:getGateInfo(slotIndex, plots)
	slotFolder:SetAttribute("GatePosition", Vector3.new(gate.X, g, gate.Z))
	slotFolder:SetAttribute("SpawnPosition", Vector3.new(gate.OutsideX, g, gate.OutsideZ))
end

function RanchBuilder.buildSlot(layout, slotsFolder: Folder, slotIndex: number, plots): Folder
	local slot = layout:getSlot(slotIndex)
	local slotFolder = Instance.new("Folder")
	slotFolder.Name = "Slot" .. slotIndex
	slotFolder:SetAttribute("SlotIndex", slotIndex)
	slotFolder:SetAttribute("OwnerUserId", 0) -- 0 = 空き
	slotFolder:SetAttribute("Center", Vector3.new(slot.CenterX, layout.World.GroundLevel, slot.CenterZ))
	RanchBuilder.rebuildSlot(layout, slotFolder, slotIndex, plots)
	slotFolder.Parent = slotsFolder
	return slotFolder
end

-- 持ち主の表示を変える（RanchWorld.claimSlot / releaseSlot から呼ぶ）
function RanchBuilder.setSignText(slotFolder: Folder, text: string)
	local sign = slotFolder:FindFirstChild("GateSign")
	local label = sign and sign:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- ── 目印 ─────────────────────────────────────────────
-- プレイヤーの出現地点。地形生成より先に作り、生成中に入ってきたプレイヤーが落ちないようにする
function RanchBuilder.buildPlayerSpawn(layout, markersFolder: Folder): SpawnLocation
	local p = layout.PlayerSpawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- 出現直後の無敵（ForceField）なし
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(p.X, p.Y + 0.5, p.Z)
	spawn.Color = Color3.fromRGB(190, 170, 130)
	spawn.Material = Enum.Material.WoodPlanks
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = markersFolder
	return spawn
end

function RanchBuilder.buildWildSpawnArea(layout, markersFolder: Folder): Part
	local area = layout.WildArea
	local g = layout.World.GroundLevel
	local part = makeMarker(
		"WildSpawnArea",
		markersFolder,
		Vector3.new(area.MaxX - area.MinX, 1, area.MaxZ - area.MinZ),
		CFrame.new((area.MinX + area.MaxX) / 2, g, (area.MinZ + area.MaxZ) / 2)
	)
	part:SetAttribute("MinX", area.MinX)
	part:SetAttribute("MaxX", area.MaxX)
	part:SetAttribute("MinZ", area.MinZ)
	part:SetAttribute("MaxZ", area.MaxZ)
	part:SetAttribute("MinSpawnDistanceFromRanch", layout.Wild.MinSpawnDistanceFromRanch)
	return part
end

-- ── 景観 ─────────────────────────────────────────────
function RanchBuilder.buildTrees(layout, sceneryFolder: Folder)
	local folder = getOrCreateFolder(sceneryFolder, "Trees")
	for index, tree in layout.Trees do
		local y = layout:getGroundHeight(tree.X, tree.Z)
		local model = Instance.new("Model")
		model.Name = "Tree" .. index

		-- 幹（円柱は X 軸方向に伸びるので 90度 回して立てる）。プレイヤーがすり抜けないよう当たり判定あり
		local trunk = makePart(
			"Trunk",
			model,
			Vector3.new(tree.TrunkHeight + 2, tree.Radius * 2, tree.Radius * 2),
			CFrame.new(tree.X, y + tree.TrunkHeight / 2 - 1, tree.Z) * CFrame.Angles(0, 0, math.rad(90))
		)
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Color = TRUNK
		trunk.Material = Enum.Material.Wood
		trunk.CanTouch = false

		local canopy = makeVisual(
			"Canopy",
			model,
			Vector3.new(tree.CanopySize, tree.CanopySize * 0.8, tree.CanopySize),
			CFrame.new(tree.X, y + tree.TrunkHeight + tree.CanopySize * 0.25, tree.Z)
		)
		canopy.Shape = Enum.PartType.Ball
		canopy.Color = LEAVES_A:Lerp(LEAVES_B, tree.Shade)
		canopy.Material = Enum.Material.Grass

		model.PrimaryPart = trunk
		model.Parent = folder
	end
end

-- マップ端の見えない壁（外周の丘の頂上あたり）
function RanchBuilder.buildBounds(layout, sceneryFolder: Folder)
	local folder = getOrCreateFolder(sceneryFolder, "Bounds")
	local w = layout.World
	local height = w.BoundaryWallHeight
	local y = w.TerrainBottom + height / 2
	local hx, hz = layout.HalfX, layout.HalfZ
	local walls = {
		{ "North", Vector3.new(hx * 2, height, 2), Vector3.new(0, y, -hz) },
		{ "South", Vector3.new(hx * 2, height, 2), Vector3.new(0, y, hz) },
		{ "West", Vector3.new(2, height, hz * 2), Vector3.new(-hx, y, 0) },
		{ "East", Vector3.new(2, height, hz * 2), Vector3.new(hx, y, 0) },
	}
	for _, def in walls do
		local wall = makePart(def[1], folder, def[2], CFrame.new(def[3]))
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
	end
end

return RanchBuilder
