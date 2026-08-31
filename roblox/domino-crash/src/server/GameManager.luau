-- 試合サイクル・勝敗判定・タイマー。
--
-- フェーズは4つで、常にこの順に回り続ける:
--   Waiting    人が来るのを待つ / 次の試合までの間
--   Countdown  構造物を配置し、全員を持ち場へ運び、3・2・1
--   Playing    破壊フェーズ。制限時間か、誰かが 100% に到達したら終わる
--   Result     勝者の発表。瓦礫を片付けて Waiting へ戻る
--
-- 次のラウンドの構造物テンプレートは Result の間に先読みして作っておく。
-- 数千個の Part を Instance.new する時間を、誰も操作していない数秒に隠す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DominoCrash")
local Config = require(Shared.Config)
local Blueprint = require(Shared.Blueprint)

local ArenaBuilder = require(script.Parent.ArenaBuilder)
local HammerTool = require(script.Parent.HammerTool)

local GameManager = {}
GameManager.__index = GameManager

function GameManager.new(structures, progress, remotes, arenaParent: Instance)
	local self = setmetatable({
		structures = structures,
		progress = progress,
		remotes = remotes,
		arenaParent = arenaParent,
		phase = "Waiting",
		round = 0,
		timeLeft = 0,
		slotOf = {}, -- Player → slotIndex
		winner = nil,
		-- サーバ起動ごとに構造物の見た目が変わるように。同じラウンドの中では
		-- 全員が同じシードを使うので、対戦相手と壊す物はまったく同じ。
		sessionSeed = os.time() % 100000,
	}, GameManager)
	return self
end

function GameManager:seedFor(round: number): number
	return self.sessionSeed + round * 7919
end

function GameManager:kindFor(round: number): string
	return Blueprint.kindForRound(round, Config.build)
end

-- ── 同期 ────────────────────────────────────────────────
function GameManager:broadcast(extra: { [string]: any }?)
	local payload = {
		phase = self.phase,
		round = self.round,
		timeLeft = math.max(self.timeLeft, 0),
		kind = if self.round > 0 then self:kindFor(self.round) else nil,
		winner = self.winner,
		slots = {},
	}
	for player, slotIndex in self.slotOf do
		table.insert(payload.slots, {
			slot = slotIndex,
			name = player.DisplayName,
			userId = player.UserId,
		})
	end
	for key, value in extra or {} do
		payload[key] = value
	end
	self.remotes.MatchStateChanged:FireAllClients(payload)
end

function GameManager:setPhase(phase: string, extra: { [string]: any }?)
	self.phase = phase
	self:broadcast(extra)
end

-- ── プレイヤーの持ち場 ──────────────────────────────────
function GameManager:assignSlots()
	table.clear(self.slotOf)
	local list = Players:GetPlayers()
	-- UserId 順に固定する。誰がどのスロットかが毎試合ふらつくと、
	-- 「自分の構造物はどれか」を毎回探し直すことになる。
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	for index, player in list do
		if index > Config.match.maxPlayers then
			break
		end
		self.slotOf[player] = index
	end
end

function GameManager:slotFor(player: Player): number?
	return self.slotOf[player]
end

function GameManager:equip(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	for _, item in backpack:GetChildren() do
		if item.Name == "Hammer" then
			item:Destroy()
		end
	end
	local character = player.Character
	if character then
		local held = character:FindFirstChild("Hammer")
		if held then
			held:Destroy()
		end
	end
	HammerTool.create().Parent = backpack
end

function GameManager:placeAtSlot(player: Player)
	local slotIndex = self.slotOf[player]
	if not slotIndex then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(ArenaBuilder.spawnCFrame(slotIndex))
end

-- 試合中に湧き直したプレイヤーも、すぐ自分の持ち場に戻す
function GameManager:onCharacterAdded(player: Player)
	if self.phase == "Playing" or self.phase == "Countdown" then
		task.defer(function()
			self:placeAtSlot(player)
			self:equip(player)
		end)
	end
end

function GameManager:onPlayerRemoving(player: Player)
	local slotIndex = self.slotOf[player]
	if slotIndex then
		self.structures:despawn(slotIndex)
		self.slotOf[player] = nil
	end
end

-- ── 試合サイクル ────────────────────────────────────────
function GameManager:waitForPlayers()
	self.timeLeft = 0
	self:setPhase("Waiting")
	while #Players:GetPlayers() < Config.match.minPlayers do
		task.wait(0.5)
	end
	-- 人が集まってからも少しだけ待つ (連続で入ってくる場合に取りこぼさない)
	for remaining = Config.match.intermission, 1, -1 do
		self.timeLeft = remaining
		self:broadcast()
		task.wait(1)
		if #Players:GetPlayers() < Config.match.minPlayers then
			return false
		end
	end
	return true
end

function GameManager:startRound()
	self.round += 1
	self.winner = nil
	self.progress:reset()
	self:assignSlots()

	local kind = self:kindFor(self.round)
	local seed = self:seedFor(self.round)

	for player, slotIndex in self.slotOf do
		self.structures:spawn(slotIndex, kind, seed, player, self.arenaParent)
		self:placeAtSlot(player)
		self:equip(player)
	end

	self:setPhase("Countdown")
	for remaining = Config.match.countdown, 1, -1 do
		self.timeLeft = remaining
		self:broadcast()
		task.wait(1)
	end
end

function GameManager:runRound()
	self.timeLeft = Config.match.duration
	self:setPhase("Playing")

	local deadline = os.clock() + Config.match.duration
	while os.clock() < deadline do
		task.wait(0.1)
		self.timeLeft = math.max(deadline - os.clock(), 0)
		if self.progress:hasWinner() then
			break
		end
		if #Players:GetPlayers() == 0 then
			break
		end
	end

	-- 決着直前にもう一度だけ集計して、最後の一撃を取りこぼさない
	self.progress:step(0, true)
end

function GameManager:finishRound()
	local slotIndex, percent = self.progress:leader()
	local name = nil
	for player, index in self.slotOf do
		if index == slotIndex then
			name = player.DisplayName
		end
	end
	self.winner = if slotIndex then { slot = slotIndex, name = name, percent = percent } else nil

	self.timeLeft = Config.match.resultHold
	self:setPhase("Result")

	-- 結果を見せている間に次のラウンドのテンプレートを作っておく。
	-- 数千個の Part の生成コストを、誰も操作していない時間に隠す。
	task.spawn(function()
		self.structures:prepare(self:kindFor(self.round + 1), self:seedFor(self.round + 1))
	end)

	for remaining = Config.match.resultHold, 1, -1 do
		self.timeLeft = remaining
		self:broadcast()
		task.wait(1)
	end

	self.structures:despawnAll()
end

function GameManager:start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			self:onCharacterAdded(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:onPlayerRemoving(player)
	end)

	task.spawn(function()
		while true do
			if self:waitForPlayers() then
				self:startRound()
				self:runRound()
				self:finishRound()
			end
			task.wait(0.25)
		end
	end)
end

return GameManager
