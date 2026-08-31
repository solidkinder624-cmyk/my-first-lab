-- かくれんぼ型: 1人の鬼が、姿の見えない隠れ手を痕跡だけを頼りに探す。
-- 隠れ手はしゃがめば無音だが遅い。動かなければ完全に安全だが、
-- 制限時間内は逃げ切れても加点されない設計にして「動く理由」を作っている。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)

local Mode = {}
Mode.name = "かくれんぼ"

local state = { hideTimer = 0, released = false }

function Mode.objective(entry): string
	if entry.role == "Seeker" then
		return "痕跡を追って全員を見つけろ"
	elseif entry.role == "Found" then
		return "見つかった (観戦中)"
	end
	return "しゃがんで足跡を消し、逃げ切れ"
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
			ctx.setRole(entry, "Seeker")
			ctx.freeze(entry, true) -- 鬼は準備時間のあいだ動けない
		else
			ctx.setRole(entry, "Hider")
			ctx.freeze(entry, false)
		end
	end

	state.hideTimer = Config.round.hideTime
	state.released = false
	ctx.message(string.format("隠れる時間 %d 秒", Config.round.hideTime))
end

function Mode.playerJoined(ctx, entry)
	ctx.setRole(entry, "Found") -- 途中参加は次ラウンドから
end

function Mode.tick(ctx, dt): string?
	if not state.released then
		state.hideTimer -= dt
		if state.hideTimer <= 0 then
			state.released = true
			for _, entry in ctx.registry:all() do
				if entry.role == "Seeker" then
					ctx.freeze(entry, false)
				end
			end
			ctx.message("鬼が動き出した")
		end
		return nil
	end

	-- 鬼の周囲を判定する。位置比較はサーバ内だけで完結する。
	for _, seeker in ctx.registry:all() do
		if seeker.role ~= "Seeker" then
			continue
		end
		local caught = ctx.registry:near(seeker.state.x, seeker.state.z, Config.round.tagRadius, function(e)
			return e.role == "Hider" and e.active
		end)
		for _, victim in caught do
			victim.active = false
			victim.frozen = true
			ctx.setRole(victim, "Found")
			seeker.score += 1
			-- 発見は全員に大きな波紋で伝える (残りの隠れ手への警告)
			ctx.traces:emitAt("Tag", victim.state.x, victim.state.z, nil)
			ctx.message(string.format("%s が見つかった", victim.player.DisplayName))
		end
	end

	local remaining = ctx.registry:count(function(e)
		return e.role == "Hider" and e.active
	end)
	if remaining == 0 then
		return "鬼の勝ち: 全員発見"
	end
	return nil
end

function Mode.finish(ctx, reason: string): string
	local remaining = ctx.registry:count(function(e)
		return e.role == "Hider" and e.active
	end)
	if remaining > 0 then
		return string.format("%s — 逃げ切り %d 人", reason, remaining)
	end
	return reason
end

return Mode
