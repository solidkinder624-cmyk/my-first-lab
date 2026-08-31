-- 宝探し型: 迷路に置かれた宝を集める。
-- 拾った瞬間にマップ全体へ届く波紋が出るので、「取ると居場所がバレる」。
-- 静かに歩けば安全だが遅い、という中心的なリスク/リターンがそのまま得点競争になる。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)

local Mode = {}
Mode.name = "宝探し"

local state = { treasures = {}, folder = nil }

function Mode.objective(entry): string
	return string.format("宝を集めろ (所持 %d)", entry.score)
end

local function clearTreasures()
	if state.folder then
		state.folder:Destroy()
	end
	state.folder = nil
	state.treasures = {}
end

-- 宝そのものは隠す必要がない (むしろ暗闇の中の道標になる)。
-- 小さく淡い Neon の球で、周囲を照らしすぎないようにする。
local function spawnTreasure(x: number, z: number)
	local part = Instance.new("Part")
	part.Name = "Treasure"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Position = Vector3.new(x, 1.4, z)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 214, 120)
	part.Transparency = 0.15
	part.Parent = state.folder
	return { part = part, x = x, z = z, taken = false }
end

function Mode.start(ctx)
	clearTreasures()
	state.folder = Instance.new("Folder")
	state.folder.Name = "Treasures"
	state.folder.Parent = workspace

	local entries = ctx.registry:filter(function(e)
		return e.ready
	end)
	-- プレイヤーと宝をまとめて散らす。先頭を宝、後ろをスポーンに割り当てる。
	local tiles = ctx.pickTiles(Config.round.treasureCount + #entries)
	for i = 1, Config.round.treasureCount do
		local tile = tiles[i]
		if tile then
			local x, z = Grid.center(ctx.grid, tile.x, tile.z)
			table.insert(state.treasures, spawnTreasure(x, z))
		end
	end
	for i, entry in entries do
		ctx.spawn(entry, tiles[Config.round.treasureCount + i] or tiles[1])
		ctx.setRole(entry, "Hunter")
		ctx.freeze(entry, false)
		entry.active = true
	end
	ctx.message(string.format("宝 %d 個。拾うと波紋で位置がバレる", #state.treasures))
end

function Mode.playerJoined(ctx, entry)
	ctx.setRole(entry, "Hunter")
end

function Mode.tick(ctx, _dt): string?
	local remaining = 0
	local justTaken = false
	for _, treasure in state.treasures do
		if treasure.taken then
			continue
		end
		local takers = ctx.registry:near(treasure.x, treasure.z, Config.round.pickupRadius, function(e)
			return e.active and not e.frozen
		end)
		local taker = takers[1]
		if taker then
			treasure.taken = true
			treasure.part:Destroy()
			taker.score += 1
			ctx.traces:emitAt("Pickup", treasure.x, treasure.z, nil)
			justTaken = true
		else
			remaining += 1
		end
	end

	if justTaken then
		ctx.message(string.format("宝が取られた (残り %d)", remaining))
	end

	if remaining == 0 then
		return "すべての宝が回収された"
	end
	return nil
end

function Mode.finish(ctx, reason: string): string
	local best, bestScore = nil, 0
	for _, entry in ctx.registry:all() do
		if entry.score > bestScore then
			best, bestScore = entry, entry.score
		end
	end
	clearTreasures()
	if best then
		return string.format("%s — 勝者 %s (%d個)", reason, best.player.DisplayName, bestScore)
	end
	return reason
end

return Mode
