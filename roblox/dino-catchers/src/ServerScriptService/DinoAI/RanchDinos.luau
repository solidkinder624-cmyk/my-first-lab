-- 飼育恐竜（プレイヤーの所持恐竜）を拠点の柵の内側に出して歩かせる。
-- あわせて、拠点スロットの割り当て（RanchWorld.claimSlot）も行う（リーダー判断による暫定担当）。
--
-- ■ 拠点スロット
--   ・プレイヤー参加時に RanchWorld.claimSlot(player) を呼ぶ。
--   ・nil が返り、ワールドが未完成（待ち時間切れ）なら DinoConfig.World.ReadyPollInterval 秒待って再挑戦。
--   ・ワールドは完成しているのに nil（= 満員）なら warn して飼育恐竜は出さない。
--     その後だれかのスロットが空いたら（RanchWorld.SlotReleased）もう一度割り当てを試す。
--   ・スロットの解放は RanchWorld が退出時に自動で行う。SlotReleased を受けて恐竜を片付ける。
--
-- ■ 飼育恐竜
--   ・スロットが決まり、かつ PlayerData のロードが済んだら、所持恐竜を全員柵の内側に出す。
--   ・PlayerData.DinoAdded → 1頭追加 / DinoRemoved → 1頭消す / DinoUpdated → 属性 "Level" を更新
--   ・PlayerData.ProfileReleasing / 退出 / SlotReleased → その人の恐竜を全部片付ける
--   ・出す位置: RanchWorld.getRandomPointInRanch（柵の内側のランダムな点）
--   ・うろつき先: 拠点の中心（RanchWorld.getSlotCenter）から種の RanchWanderRadius の円の中の点を、
--     必ず RanchWorld.clampToRanch で柵の内側に切り詰めて決める（DinoConfig の RanchWanderRadius の定義どおり）。
--     さらに1歩ごとに clampToRanch で柵の内側へ戻すので、区画の形（L字など）が変わっても外に出ない。
--
-- モデル: Workspace.Dinos.Ranch.<UserId>.<DinoId>
--   属性 "DinoId"（= OwnedDino.Id = モデル名）/ "Species" / "OwnerUserId" / "Level" /
--        "Wild" = false / "State"（Idle / Walking）/ "GroundOffset"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DinoConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DinoConfig"))
local RanchWorld = require(workspace:WaitForChild("Ranch"):WaitForChild("RanchWorld"))
local PlayerData = require(ServerScriptService:WaitForChild("Data"):WaitForChild("PlayerData"))
local WanderLogic = require(script.Parent:WaitForChild("WanderLogic"))
local DinoMover = require(script.Parent:WaitForChild("DinoMover"))
local DinoModelFactory = require(script.Parent:WaitForChild("DinoModelFactory"))

local RanchDinos = {}

local KEY_PREFIX = "R:" -- DinoMover の登録キー（野生恐竜と重ならないように）

type PlayerState = {
	Player: Player,
	Slot: number?,
	Dinos: { [string]: Model }, -- DinoId → モデル
	Folder: Folder?,
	Claiming: boolean,
	WaitingForSlot: boolean, -- 満員で空き待ち
	Released: boolean, -- ProfileReleasing 以降は何も出さない
}

local states: { [Player]: PlayerState } = {}
local rng = Random.new()
local ranchFolder: Folder? = nil
local started = false

local function logWarn(message: string)
	warn("[RanchDinos] " .. message)
end

local function flat(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end

local function getPlayerFolder(state: PlayerState): Folder
	if state.Folder and state.Folder.Parent then
		return state.Folder
	end
	local playerFolder = Instance.new("Folder")
	playerFolder.Name = tostring(state.Player.UserId)
	playerFolder:SetAttribute("OwnerUserId", state.Player.UserId)
	playerFolder.Parent = ranchFolder
	state.Folder = playerFolder
	return playerFolder
end

-- ── 1頭の出し入れ ─────────────────────────────────────
local function despawnDino(state: PlayerState, dinoId: string)
	if state.Dinos[dinoId] then
		state.Dinos[dinoId] = nil
		DinoMover.remove(KEY_PREFIX .. dinoId)
	end
end

local function despawnAll(state: PlayerState)
	for dinoId in table.clone(state.Dinos) do
		despawnDino(state, dinoId)
	end
	if state.Folder then
		state.Folder:Destroy()
		state.Folder = nil
	end
end

local function spawnDino(state: PlayerState, dino: any)
	local slot = state.Slot
	if not slot or state.Released or type(dino) ~= "table" or type(dino.Id) ~= "string" then
		return
	end
	if state.Dinos[dino.Id] then
		return -- すでに出ている
	end
	local species = DinoConfig.Species[dino.Species]
	local model, groundOffset = DinoModelFactory.create(dino.Species)
	if not (species and model) then
		logWarn(string.format("%s の恐竜 %s は未知の種 %s のため出さない", state.Player.Name, dino.Id, tostring(dino.Species)))
		return
	end
	model.Name = dino.Id
	model:SetAttribute("DinoId", dino.Id)
	model:SetAttribute("Species", dino.Species)
	model:SetAttribute("OwnerUserId", state.Player.UserId)
	model:SetAttribute("Level", dino.Level)
	model:SetAttribute("Wild", false)

	local center = RanchWorld.getSlotCenter(slot)
	local function clamp(x: number, z: number): (number, number)
		local point = RanchWorld.clampToRanch(slot, flat(x, z))
		return point.X, point.Z
	end
	local env: WanderLogic.Env = {
		chooseTarget = function(_agent, r)
			return WanderLogic.chooseRanchTarget(center.X, center.Z, species.RanchWanderRadius, r, clamp)
		end,
		constrain = clamp,
	}
	local start = RanchWorld.getRandomPointInRanch(slot, rng)
	local agent = WanderLogic.newAgent(start.X, start.Z, species, os.clock(), rng)

	state.Dinos[dino.Id] = model
	DinoMover.add(KEY_PREFIX .. dino.Id, model, agent, env, groundOffset, getPlayerFolder(state))
	model.Destroying:Connect(function()
		-- 外から Destroy された場合も登録を外す
		if state.Dinos[dino.Id] == model then
			state.Dinos[dino.Id] = nil
			DinoMover.remove(KEY_PREFIX .. dino.Id)
		end
	end)
end

-- スロットとデータがそろったら所持恐竜を全員出す
local function spawnAllIfReady(state: PlayerState)
	if not state.Slot or state.Released or not PlayerData.isLoaded(state.Player) then
		return
	end
	for _, dino in PlayerData.getDinos(state.Player) do
		spawnDino(state, dino)
	end
end

-- ── スロットの割り当て ─────────────────────────────────
local function isCurrent(state: PlayerState): boolean
	return states[state.Player] == state and state.Player.Parent ~= nil and not state.Released
end

local function claimLoop(state: PlayerState)
	if state.Claiming or state.Slot then
		return
	end
	state.Claiming = true
	state.WaitingForSlot = false
	while isCurrent(state) do
		local slot = RanchWorld.claimSlot(state.Player) -- ワールド完成まで最大 World.ReadyTimeout 秒待つ
		if not isCurrent(state) then
			break
		end
		if slot then
			state.Slot = slot
			spawnAllIfReady(state)
			break
		end
		if RanchWorld.isReady() then
			state.WaitingForSlot = true
			logWarn(state.Player.Name .. " に割り当てる拠点スロットがありません（満員）。空きが出るまで飼育恐竜は出しません")
			break
		end
		logWarn(state.Player.Name .. " の拠点スロットを割り当てられなかった（ワールド未完成）。再挑戦します")
		task.wait(DinoConfig.World.ReadyPollInterval)
	end
	state.Claiming = false
end

-- ── イベント ─────────────────────────────────────────
local function onPlayerAdded(player: Player)
	if states[player] then
		return
	end
	local state: PlayerState = {
		Player = player,
		Slot = nil,
		Dinos = {},
		Folder = nil,
		Claiming = false,
		WaitingForSlot = false,
		Released = false,
	}
	states[player] = state
	claimLoop(state)
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.Released = true
	despawnAll(state)
	states[player] = nil
end

local function onSlotReleased(player: Player, slotIndex: number)
	local state = states[player]
	if state and state.Slot == slotIndex then
		despawnAll(state)
		state.Slot = nil
	end
	-- 満員で待っていた人に割り当て直す
	for _, other in states do
		if other.WaitingForSlot and isCurrent(other) then
			task.spawn(claimLoop, other)
		end
	end
end

-- ── 公開（DinoService から使う） ─────────────────────────

-- 飼育恐竜のモデル（ownerは問わない）。いなければ nil
function RanchDinos.getModel(dinoId: string): Model?
	for _, state in states do
		local model = state.Dinos[dinoId]
		if model then
			return model
		end
	end
	return nil
end

-- そのプレイヤーの拠点スロット（DinoAI が割り当てたもの）
function RanchDinos.getSlot(player: Player): number?
	local state = states[player]
	return if state then state.Slot else nil
end

function RanchDinos.start(dinosFolder: Instance)
	if started then
		return
	end
	started = true
	local existing = dinosFolder:FindFirstChild("Ranch")
	if existing then
		existing:Destroy()
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Ranch"
	newFolder.Parent = dinosFolder
	ranchFolder = newFolder

	PlayerData.ProfileLoaded:Connect(function(player: Player)
		local state = states[player]
		if state then
			spawnAllIfReady(state)
		end
	end)
	PlayerData.DinoAdded:Connect(function(player: Player, dino)
		local state = states[player]
		if state then
			spawnDino(state, dino)
		end
	end)
	PlayerData.DinoRemoved:Connect(function(player: Player, dinoId: string)
		local state = states[player]
		if state then
			despawnDino(state, dinoId)
		end
	end)
	PlayerData.DinoUpdated:Connect(function(player: Player, dino)
		local state = states[player]
		local model = state and type(dino) == "table" and state.Dinos[dino.Id]
		if model then
			model:SetAttribute("Level", dino.Level)
		end
	end)
	PlayerData.ProfileReleasing:Connect(function(player: Player)
		local state = states[player]
		if state then
			state.Released = true
			despawnAll(state)
		end
	end)
	RanchWorld.SlotReleased:Connect(onSlotReleased)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return RanchDinos
