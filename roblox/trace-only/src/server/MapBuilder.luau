-- Grid (純データ) から実際の Part を組み立てる。
-- 3Dモデル・テクスチャは一切使わず、Part の色と Lighting だけで
-- 「何も見えない迷路」の雰囲気を作る = 個人開発でも維持コストが低い。

local Lighting = game:GetService("Lighting")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)

local MapBuilder = {}

-- 壁は歩ける範囲が分かる程度に明るく、床はそれより暗く保つ。
-- 「相手が見えない」のはキャラクターモデル自体が存在しない構造上の仕組みなので、
-- 壁や床を見やすくしても他プレイヤーの位置が漏れることはない。
-- 床を暗いままにしておくのは、足跡(Neon)とのコントラストを保つため。
local WALL_COLOR = Color3.fromRGB(185, 190, 210)
local FLOOR_COLOR = Color3.fromRGB(14, 15, 20)

local function newPart(name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false -- 当たり判定は Motion.luau が持つので物理イベントは不要
	part.CanQuery = false
	part.CastShadow = false -- 影は真っ暗な空間ではほぼ見えず、コストだけ掛かる
	part.Material = Enum.Material.Slate
	part.Color = color
	part.Size = size
	part.Position = position
	return part
end

-- 暗闇と霧。壁の輪郭が見える程度の環境光は残しつつ、床は暗いままにして
-- 足跡(Neon)が唯一の目立つ光源になるようにする。
function MapBuilder.applyLighting()
	-- 最終的な明るさは Ambient × 表面の色 の掛け算で決まるため、両方を控えめにすると
	-- 実質ほぼ黒(数%の明るさ)まで潰れて画面上は真っ暗に見える。Ambient 自体を
	-- はっきり明るくすることで、掛け算後も壁がグレーとして視認できる水準を確保する。
	Lighting.Ambient = Color3.fromRGB(150, 156, 180)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 156, 180)
	Lighting.Brightness = 0.5
	Lighting.ClockTime = 0
	Lighting.GlobalShadows = false
	Lighting.FogColor = Color3.fromRGB(60, 63, 78)
	Lighting.FogStart = 20
	Lighting.FogEnd = 160 -- 遠くの痕跡は霧に沈む = 索敵に距離の概念が生まれる
end

-- grid から迷路を生成し、Workspace の Folder を返す。
-- 壁は Grid.wallRuns で横方向にマージ済みなので、1タイル1パーツより大幅に少ない。
function MapBuilder.build(grid): Folder
	local existing = workspace:FindFirstChild("Maze")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Maze"

	local t = grid.tileSize
	local worldW, worldH = grid.w * t, grid.h * t

	local floor = newPart("Floor", Vector3.new(worldW, 1, worldH), Vector3.new(worldW / 2, -0.5, worldH / 2), FLOOR_COLOR)
	floor.Parent = folder

	-- 天井。空が見えると明るくなってしまうので必ず閉じる。
	local ceiling = newPart(
		"Ceiling",
		Vector3.new(worldW, 1, worldH),
		Vector3.new(worldW / 2, Config.wallHeight + 0.5, worldH / 2),
		FLOOR_COLOR
	)
	ceiling.Parent = folder

	local runs = Grid.wallRuns(grid)
	for i, run in runs do
		local part = newPart(
			"Wall" .. i,
			Vector3.new(run.length * t, Config.wallHeight, t),
			Vector3.new((run.x + run.length / 2) * t, Config.wallHeight / 2, (run.z + 0.5) * t),
			WALL_COLOR
		)
		part.Parent = folder
	end

	folder.Parent = workspace
	return folder
end

return MapBuilder
