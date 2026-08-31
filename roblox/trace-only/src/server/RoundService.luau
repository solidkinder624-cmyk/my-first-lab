-- ラウンド進行とモード切り替え。
-- 「準備時間 → 本番 → リザルト」を回し、モジュール化した各モードへ処理を委譲する。
-- 毎ラウンド迷路の seed を作り直すので、暗記ゲーにならない。

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)

local MapBuilder = require(script.Parent.MapBuilder)

local RoundService = {}
RoundService.__index = RoundService

function RoundService.new(registry, remotes, sim, traces)
	local self = setmetatable({
		registry = registry,
		remotes = remotes,
		sim = sim,
		traces = traces,
		modes = {
			require(script.Parent.Modes.HideAndSeek),
			require(script.Parent.Modes.TreasureHunt),
			require(script.Parent.Modes.Tag),
		},
		modeIndex = 0,
		mode = nil,
		phase = "Intermission",
		timeLeft = Config.round.intermission,
		message = "プレイヤーを待っています",
		grid = nil,
		seed = 0,
		rng = Grid.newRng(os.time() % 2 ^ 31),
		broadcastAccum = 0,
	}, RoundService)
	return self
end

-- ── クライアントへの通知 ────────────────────────────────
function RoundService:_context()
	return {
		grid = self.grid,
		registry = self.registry,
		sim = self.sim,
		traces = self.traces,
		rng = self.rng,
		config = Config,
		round = self,
		message = function(text: string)
			self.message = text
		end,
		setRole = function(entry, role: string)
			entry.role = role
		end,
		freeze = function(entry, frozen: boolean)
			entry.frozen = frozen
		end,
		spawn = function(entry, tile)
			local x, z = Grid.center(self.grid, tile.x, tile.z)
			self.sim:placeAt(entry, x, z)
		end,
		pickTiles = function(count: number)
			return self:pickSpreadTiles(count)
		end,
	}
end

function RoundService:broadcastState()
	for _, entry in self.registry:all() do
		if not entry.ready then
			continue
		end
		self.remotes.Round:FireClient(entry.player, {
			event = "State",
			phase = self.phase,
			timeLeft = math.max(0, math.floor(self.timeLeft)),
			mode = if self.mode then self.mode.name else "-",
			objective = if self.mode then self.mode.objective(entry) else "",
			role = entry.role,
			score = entry.score,
			message = self.message,
			playing = self.registry:count(function(e)
				return e.active
			end),
		})
	end
end

function RoundService:sendMap(player: Player)
	self.remotes.Round:FireClient(player, {
		event = "Map",
		seed = self.seed,
		cellsW = Config.mazeCells.w,
		cellsH = Config.mazeCells.h,
		braid = Config.braid,
	})
end

-- ── スポーン地点選び ────────────────────────────────────
-- 貪欲な最遠点選択。互いにできるだけ離れたタイルを count 個返す。
-- (かくれんぼで鬼と隠れる側が隣接スタートする事故を防ぐ)
function RoundService:pickSpreadTiles(count: number)
	local open = Grid.openTiles(self.grid)
	local chosen = {}
	if #open == 0 or count <= 0 then
		return chosen
	end
	count = math.min(count, #open)

	-- open[i] から「既に選んだ点」までの最小歩数。点を1つ選ぶたびに更新するので、
	-- BFS は選ぶ個数ぶんしか走らない。
	local minDist = table.create(#open, math.huge)
	local function absorb(tile)
		local d = Grid.distances(self.grid, tile.x, tile.z)
		for i, t in open do
			local v = Grid.distanceAt(self.grid, d, t.x, t.z) or math.huge
			if v < minDist[i] then
				minDist[i] = v
			end
		end
	end

	local first = open[Grid.nextInt(self.rng, #open) + 1]
	table.insert(chosen, first)
	absorb(first)

	while #chosen < count do
		local bestIndex, bestScore = nil, -1
		for i in open do
			local v = minDist[i]
			if v ~= math.huge and v > bestScore then
				bestIndex, bestScore = i, v
			end
		end
		if not bestIndex then
			break
		end
		local tile = open[bestIndex]
		table.insert(chosen, tile)
		absorb(tile)
	end
	return chosen
end

-- ── フェーズ制御 ────────────────────────────────────────
function RoundService:newMap()
	self.seed = Grid.nextInt(self.rng, 2 ^ 30) + 1
	self.grid = Grid.generate(Config.mazeCells.w, Config.mazeCells.h, self.seed, Config.braid, Config.tileSize)
	MapBuilder.build(self.grid)
	self.sim:setGrid(self.grid)
	print(string.format(
		"[TraceOnly] maze built: %dx%d tiles = %.0fx%.0f studs, seed=%d",
		self.grid.w,
		self.grid.h,
		self.grid.w * self.grid.tileSize,
		self.grid.h * self.grid.tileSize,
		self.seed
	))
end

-- 起動直後や待機中でも歩き回れるように、最低1つは迷路を用意しておく
function RoundService:ensureMap()
	if not self.grid then
		self:newMap()
	end
end

function RoundService:startRound()
	self:newMap()

	self.modeIndex = self.modeIndex % #self.modes + 1
	self.mode = self.modes[self.modeIndex]
	self.phase = "Playing"
	self.timeLeft = Config.round.duration

	local readyCount = self.registry:count(function(e)
		return e.ready
	end)
	print(string.format(
		"[TraceOnly] startRound mode=%s readyPlayers=%d rawPlayers=%d",
		self.mode.name,
		readyCount,
		#Players:GetPlayers()
	))

	for _, entry in self.registry:all() do
		entry.score = 0
		entry.active = true
		entry.frozen = false
		entry.role = "Free"
		if entry.ready then
			self:sendMap(entry.player)
		end
	end

	self.mode.start(self:_context())
	self:broadcastState()
end

function RoundService:endRound(reason: string)
	print(string.format("[TraceOnly] endRound mode=%s reason=%s timeLeft=%.1f", if self.mode then self.mode.name else "-", reason, self.timeLeft))
	self.phase = "Intermission"
	self.timeLeft = Config.round.intermission
	self.message = if self.mode then self.mode.finish(self:_context(), reason) else reason
	-- 待機中は自由に歩ける (足跡の練習ができるので初心者に優しい)
	for _, entry in self.registry:all() do
		entry.frozen = false
		entry.active = true
		entry.role = "Free"
	end
	self:broadcastState()
end

function RoundService:playerJoined(entry)
	self:sendMap(entry.player)
	if self.grid then
		local tiles = self:pickSpreadTiles(1)
		if tiles[1] then
			local x, z = Grid.center(self.grid, tiles[1].x, tiles[1].z)
			self.sim:placeAt(entry, x, z)
		end
	end
	-- 進行中のラウンドには観戦として合流し、次ラウンドから参加する
	entry.active = self.phase ~= "Playing"
	entry.frozen = self.phase == "Playing"
	if self.mode and self.phase == "Playing" and self.mode.playerJoined then
		self.mode.playerJoined(self:_context(), entry)
	end
	self:broadcastState()
end

function RoundService:update(dt: number)
	self.timeLeft -= dt
	self.broadcastAccum += dt

	if self.phase == "Playing" then
		local over = self.mode.tick(self:_context(), dt)
		if over then
			self:endRound(over)
		elseif self.timeLeft <= 0 then
			self:endRound("時間切れ")
		end
	elseif self.timeLeft <= 0 then
		-- クライアントの読み込みが終わって Ready を送ってきた人数で判定する。
		-- 生の接続人数(#Players:GetPlayers())で判定すると、ロード中で
		-- まだ何も準備できていないプレイヤーだけでラウンドが始まってしまう。
		local readyCount = self.registry:count(function(e)
			return e.ready
		end)
		if readyCount >= Config.round.minPlayers then
			self:startRound()
		else
			self.timeLeft = Config.round.intermission
			self.message = string.format("あと %d 人でラウンド開始", Config.round.minPlayers - readyCount)
		end
	end

	if self.broadcastAccum >= 0.25 then
		self.broadcastAccum = 0
		self:broadcastState()
	end
end

return RoundService
