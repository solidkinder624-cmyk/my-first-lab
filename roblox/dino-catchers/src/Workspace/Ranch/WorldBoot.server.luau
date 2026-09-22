-- ワールドの起動役（Script）。Workspace 内の Script はサーバーで実行される。
-- Terrain は Rojo でファイル化できないため、サーバー起動時にここで手続き生成する。
--
-- 順番:
--   1. プレイヤー出現地点（先に作って、生成中に入ってきたプレイヤーが落ちないようにする）
--   2. 草原の Terrain（起伏・池・岩）
--   3. 拠点スロット（区画ごとの柵・床の牧草）
--   4. 野生の出現範囲の目印・木・マップ端の壁
--   5. Workspace.Ranch の属性 WorldReady = true（RanchWorld.waitUntilReady() が返る）
-- 計算はすべて RanchWorld.Layout（= WorldLayout）が行う。

local Ranch = script.Parent

local RanchWorld = require(Ranch:WaitForChild("RanchWorld"))
local RanchBuilder = require(Ranch:WaitForChild("RanchBuilder"))
local TerrainGen = require(Ranch:WaitForChild("TerrainGen"))

local layout = RanchWorld.Layout

local function newFolder(name: string): Folder
	local old = Ranch:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Ranch
	return folder
end

Ranch:SetAttribute("WorldReady", false)
local started = os.clock()

-- 1. 出現地点
local markers = newFolder("Markers")
RanchBuilder.buildPlayerSpawn(layout, markers)

-- 2. 地形
TerrainGen.generate(workspace.Terrain, layout)

-- 3. 拠点スロット
local slots = newFolder("Slots")
for slotIndex = 1, RanchWorld.getSlotCount() do
	local plots = RanchWorld.getPlots(slotIndex)
	for _, plot in plots do
		TerrainGen.paintPlot(workspace.Terrain, layout, layout:getPlotRect(slotIndex, plot.PX, plot.PZ))
	end
	RanchBuilder.buildSlot(layout, slots, slotIndex, plots)
end

-- 4. 目印・景観
RanchBuilder.buildWildSpawnArea(layout, markers)
local scenery = newFolder("Scenery")
RanchBuilder.buildTrees(layout, scenery)
RanchBuilder.buildBounds(layout, scenery)

-- 5. 完成
Ranch:SetAttribute("WorldReady", true)
print(string.format("[WorldBoot] ワールド生成完了（%.2f 秒）", os.clock() - started))
