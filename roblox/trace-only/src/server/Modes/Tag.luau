-- 鬼ごっこ型 (感染式): 最初は1人の鬼。捕まった人も鬼になり、最後の1人を目指す。
--
-- バランス調整の肝: 鬼は一定間隔で自動的に波紋を発する (aura)。
-- 完全に無音の鬼が増殖すると逃げ手に情報が無くなって一方的になるため、
-- 「鬼は近づくと気配で分かる」ことをルールとして保証している。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)

local Mode = {}
Mode.name = "鬼ごっこ"

local AURA_INTERVAL = 2.5 -- 鬼の気配が出る間隔 (秒)
local START_DELAY = 5 -- 鬼が動き出すまでの猶予

local state = { auraTimer = 0, startTimer = 0, released = false }

function Mode.objective(entry): string
	if entry.role == "Hunter" then
		return "逃げ手を追い詰めろ (気配が漏れる)"
	end
	return "最後まで捕まるな"
end

local function shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = Grid.nextInt(rng, i) + 1
		list[i], list[j] = list[j], list[i]
	end
end

function Mode.start(ctx)
	local entries = ctx.registry:filter(function(e)
		return e.ready
	end)
	shuffle(entries, ctx.rng)
	local tiles = ctx.pickTiles(#entries)

	for i, entry in entries do
		ctx.spawn(entry, tiles[i] or tiles[1])
		entry.active = true
		if i == 1 then
			ctx.setRole(entry, "Hunter")
			ctx.freeze(entry, true)
		else
			ctx.setRole(entry, "Runner")
			ctx.freeze(entry, false)
		end
	end

	state.auraTimer = 0
	state.startTimer = START_DELAY
	state.released = false
	ctx.message(string.format("%d 秒後に鬼が動き出す", START_DELAY))
end

function Mode.playerJoined(ctx, entry)
	ctx.setRole(entry, "Hunter") -- 途中参加は鬼側に回して人数バランスを保つ
end

function Mode.tick(ctx, dt): string?
	if not state.released then
		state.startTimer -= dt
		if state.startTimer <= 0 then
			state.released = true
			for _, entry in ctx.registry:all() do
				if entry.role == "Hunter" then
					ctx.freeze(entry, false)
				end
			end
			ctx.message("鬼が動き出した")
		end
		return nil
	end

	-- 鬼の気配 (一定間隔で本人の位置から波紋)
	state.auraTimer -= dt
	local emitAura = state.auraTimer <= 0
	if emitAura then
		state.auraTimer = AURA_INTERVAL
	end

	for _, hunter in ctx.registry:all() do
		if hunter.role ~= "Hunter" or not hunter.active then
			continue
		end
		if emitAura then
			ctx.traces:emitAt("Jump", hunter.state.x, hunter.state.z, hunter)
		end
		local caught = ctx.registry:near(hunter.state.x, hunter.state.z, Config.round.tagRadius, function(e)
			return e.role == "Runner" and e.active
		end)
		for _, victim in caught do
			ctx.setRole(victim, "Hunter") -- 感染
			hunter.score += 1
			ctx.traces:emitAt("Tag", victim.state.x, victim.state.z, nil)
			ctx.message(string.format("%s が捕まった", victim.player.DisplayName))
		end
	end

	local runners = ctx.registry:count(function(e)
		return e.role == "Runner" and e.active
	end)
	if runners == 0 then
		return "鬼の勝ち: 全員が捕まった"
	end
	return nil
end

function Mode.finish(ctx, reason: string): string
	local survivors = {}
	for _, entry in ctx.registry:all() do
		if entry.role == "Runner" and entry.active then
			table.insert(survivors, entry.player.DisplayName)
		end
	end
	if #survivors > 0 then
		return string.format("%s — 逃げ切り: %s", reason, table.concat(survivors, ", "))
	end
	return reason
end

return Mode
