-- アリーナの静的な部分を作る。プレイヤー数ぶんのスロットを X 方向に並べ、
-- 各スロットに床・見えない飛散防止フェンス・スポーン地点を置く。
--
-- 床を専用の衝突グループに入れているのがポイント。瓦礫はプレイヤーとは
-- 衝突しない (吹き飛ばされて操作不能にならない) が、床とは衝突してほしい。
-- 全部を Default に置くとこの2つを両立できない。

local PhysicsService = game:GetService("PhysicsService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("DominoCrash").Config)

local ArenaBuilder = {}

ArenaBuilder.GROUP_STRUCTURE = "DominoStructure" -- 床・立っている構造物
ArenaBuilder.GROUP_DEBRIS = "DominoDebris" -- アンカーが外れた瓦礫

local function registerGroups()
	-- 登録済みのグループを再登録すると例外になる (Studio でスクリプトを
	-- 動かし直したときに起きる) ので、そこだけ飲む。
	local function ensure(name: string)
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	ensure(ArenaBuilder.GROUP_STRUCTURE)
	ensure(ArenaBuilder.GROUP_DEBRIS)

	-- 瓦礫 ↔ プレイヤー(Default) は衝突させない。数百個の破片に押されると
	-- プレイヤーが場外まで飛ばされて操作不能になるため。
	PhysicsService:CollisionGroupSetCollidable(ArenaBuilder.GROUP_DEBRIS, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(ArenaBuilder.GROUP_DEBRIS, ArenaBuilder.GROUP_DEBRIS, true)
	PhysicsService:CollisionGroupSetCollidable(ArenaBuilder.GROUP_DEBRIS, ArenaBuilder.GROUP_STRUCTURE, true)
	PhysicsService:CollisionGroupSetCollidable(ArenaBuilder.GROUP_STRUCTURE, "Default", true)
end

-- スロット i (1..maxPlayers) の中心座標
function ArenaBuilder.slotOrigin(index: number): Vector3
	local span = (Config.match.maxPlayers - 1) * Config.arena.slotSpacing
	local x = -span * 0.5 + (index - 1) * Config.arena.slotSpacing
	return Vector3.new(x, Config.arena.floorY, 0)
end

-- 構造物の手前 (Z+ 側) に立たせる。全員が自分の構造物を正面に見る配置。
function ArenaBuilder.spawnCFrame(index: number): CFrame
	local origin = ArenaBuilder.slotOrigin(index)
	local position = origin + Vector3.new(0, 4, Config.arena.spawnBack)
	return CFrame.lookAt(position, origin + Vector3.new(0, 12, 0))
end

local function makePart(name: string, size: Vector3, position: Vector3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.Parent = parent
	return part
end

function ArenaBuilder.build(parent: Instance)
	registerGroups()

	local arena = Instance.new("Folder")
	arena.Name = "Arena"

	local size = Config.arena.floorSize
	local fence = Config.arena.fenceHeight

	for index = 1, Config.match.maxPlayers do
		local origin = ArenaBuilder.slotOrigin(index)
		local slot = Instance.new("Folder")
		slot.Name = "Slot" .. index

		local floor = makePart("Floor", Vector3.new(size, 4, size), origin - Vector3.new(0, 2, 0), slot)
		floor.Color = Color3.fromRGB(58, 62, 74)
		floor.Material = Enum.Material.Concrete
		floor.CollisionGroup = ArenaBuilder.GROUP_STRUCTURE

		-- スロット番号を足元に描いておく (誰の持ち場か分かるように)
		local marker =
			makePart("Marker", Vector3.new(size * 0.9, 0.1, size * 0.9), origin + Vector3.new(0, 0.06, 0), slot)
		marker.Color = Color3.fromRGB(78, 84, 100)
		marker.Material = Enum.Material.SmoothPlastic
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false

		-- 見えない飛散防止フェンス。瓦礫が隣のスロットへ飛び込まないようにする
		local half = size * 0.5
		local walls = {
			{ Vector3.new(size, fence, 2), Vector3.new(0, fence * 0.5, -half) },
			{ Vector3.new(size, fence, 2), Vector3.new(0, fence * 0.5, half) },
			{ Vector3.new(2, fence, size), Vector3.new(-half, fence * 0.5, 0) },
			{ Vector3.new(2, fence, size), Vector3.new(half, fence * 0.5, 0) },
		}
		for i, spec in walls do
			local wall = makePart("Fence" .. i, spec[1], origin + spec[2], slot)
			wall.Transparency = 1
			wall.CanQuery = false -- ハンマーのレイがフェンスに当たらないように
			wall.CanTouch = false
			wall.CollisionGroup = ArenaBuilder.GROUP_STRUCTURE
		end

		slot.Parent = arena
	end

	-- 中央のロビー台。スロットの床は間隔を空けて並んでいるので、
	-- ここが無いとラウンド外のプレイヤーが隙間から落ち続ける。
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"

	local pad = makePart("LobbyFloor", Vector3.new(64, 4, 64), Vector3.new(0, Config.arena.floorY - 2, 0), lobby)
	pad.Color = Color3.fromRGB(44, 48, 58)
	pad.Material = Enum.Material.Metal
	pad.CollisionGroup = ArenaBuilder.GROUP_STRUCTURE

	local spawnPoint = Instance.new("SpawnLocation")
	spawnPoint.Name = "LobbySpawn"
	spawnPoint.Anchored = true
	spawnPoint.CanCollide = false
	spawnPoint.CanQuery = false
	spawnPoint.Transparency = 1
	spawnPoint.Size = Vector3.new(24, 1, 24)
	spawnPoint.Position = Vector3.new(0, Config.arena.floorY + 0.5, 0)
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.Parent = lobby

	lobby.Parent = arena

	arena.Parent = parent
	return arena
end

return ArenaBuilder
