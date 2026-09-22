-- 野生恐竜の出現・うろつき・補充。
--
--   ・同時に最大 DinoConfig.Wild.MaxWildDinos 頭（捕獲待ちの補充予約も数に入れる）
--   ・種は SpawnWeight の重みで選ぶ（DinoConfig.SpeciesOrder の種だけが対象）
--   ・出現地点は RanchWorld.getRandomWildSpawnPoint。プレイヤーから MinSpawnDistanceFromPlayer 以上離す
--   ・うろつき先は出現地点から WanderRadius の円の中で RanchWorld.isWildWalkable を満たす点。
--     歩いている途中も1歩ごとに isWildWalkable を確かめ、ダメなら立ち止まって別の目的地を選ぶ
--     （水・拠点・広場・外周の丘に入らない）
--   ・捕獲などで消えたら RespawnDelay 秒後に1頭補充する。出現地点が見つからなければ同じ間隔で再挑戦
--
-- モデル: Workspace.Dinos.Wild.<DinoId>
--   属性 "DinoId"（一意の文字列 = モデル名）/ "Species"（DinoConfig.Species のキー）/
--        "Wild" = true / "Taming"（テイム中か）/ "State"（Idle / Walking / Taming）/ "GroundOffset"
-- 外から使う窓口は DinoService（capture-system はそちらを require する）。

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DinoConfig = require(Shared:WaitForChild("DinoConfig"))
local Signal = require(Shared:WaitForChild("Signal"))
local RanchWorld = require(workspace:WaitForChild("Ranch"):WaitForChild("RanchWorld"))
local WanderLogic = require(script.Parent:WaitForChild("WanderLogic"))
local DinoMover = require(script.Parent:WaitForChild("DinoMover"))
local DinoModelFactory = require(script.Parent:WaitForChild("DinoModelFactory"))

local WildConfig = DinoConfig.Wild

local WildDinos = {}

-- (dinoId: string, reason: string)  野生恐竜が消えたとき。reason は removeWildDino に渡された文字列
--   （例 "Captured"）/ 外から Destroy されたときは "Destroyed"
WildDinos.Removed = Signal.new()
-- (dinoId: string, model: Model)  野生恐竜が出現したとき
WildDinos.Spawned = Signal.new()

type WildInfo = {
	Model: Model,
	Species: string,
}

local KEY_PREFIX = "W:" -- DinoMover の登録キー（飼育恐竜と重ならないように）

local wild: { [string]: WildInfo } = {}
local aliveCount = 0
local pendingRespawns = 0
local rng = Random.new()
local folder: Folder? = nil
local started = false

local function logWarn(message: string)
	warn("[WildDinos] " .. message)
end

local function isWalkable(x: number, z: number): boolean
	return RanchWorld.isWildWalkable(Vector3.new(x, 0, z))
end

-- プレイヤー（キャラクター）の今の位置
local function getPlayerPositions(): { Vector3 }
	local positions = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character.PrimaryPart
		if root then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local scheduleRespawn: () -> ()

-- 1頭出す。戻り値: 出せたか
local function spawnOne(): boolean
	local speciesId = WanderLogic.pickWeightedSpecies(DinoConfig.Species, DinoConfig.SpeciesOrder, rng)
	if not speciesId then
		logWarn("SpawnWeight が 0 より大きい種がありません")
		return false
	end
	local point = RanchWorld.getRandomWildSpawnPoint(rng, getPlayerPositions(), WildConfig.MinSpawnDistanceFromPlayer)
	if not point then
		return false
	end
	local model, groundOffset = DinoModelFactory.create(speciesId)
	if not model then
		return false
	end
	local species = DinoConfig.Species[speciesId]
	local dinoId = HttpService:GenerateGUID(false)
	model.Name = dinoId
	model:SetAttribute("DinoId", dinoId)
	model:SetAttribute("Species", speciesId)
	model:SetAttribute("Wild", true)
	model:SetAttribute("Taming", false)

	local homeX, homeZ = point.X, point.Z
	local agent = WanderLogic.newAgent(homeX, homeZ, species, os.clock(), rng)
	local env: WanderLogic.Env = {
		chooseTarget = function(_agent, r)
			return WanderLogic.chooseDiscTarget(homeX, homeZ, species.WanderRadius, r, isWalkable)
		end,
		canStepTo = isWalkable,
	}

	wild[dinoId] = { Model = model, Species = speciesId }
	aliveCount += 1
	DinoMover.add(KEY_PREFIX .. dinoId, model, agent, env, groundOffset, folder :: Folder)

	-- 外から Destroy された場合も数を合わせて補充する
	model.Destroying:Connect(function()
		WildDinos.remove(dinoId, "Destroyed")
	end)
	WildDinos.Spawned:Fire(dinoId, model)
	return true
end

-- RespawnDelay 秒後に1頭補充する（失敗したら同じ間隔で再挑戦）
scheduleRespawn = function()
	pendingRespawns += 1
	task.delay(WildConfig.RespawnDelay, function()
		pendingRespawns -= 1
		if aliveCount + pendingRespawns >= WildConfig.MaxWildDinos then
			return
		end
		if not spawnOne() then
			scheduleRespawn()
		end
	end)
end

-- 上限まで埋める。出せなかった分は補充予約にする
local function fillUp()
	while aliveCount + pendingRespawns < WildConfig.MaxWildDinos do
		if not spawnOne() then
			scheduleRespawn()
		end
	end
end

-- ── 公開（DinoService から使う） ─────────────────────────

function WildDinos.getModel(dinoId: string): Model?
	local info = wild[dinoId]
	return if info then info.Model else nil
end

function WildDinos.isWild(dinoId: string): boolean
	return type(dinoId) == "string" and wild[dinoId] ~= nil
end

function WildDinos.getSpecies(dinoId: string): string?
	local info = wild[dinoId]
	return if info then info.Species else nil
end

function WildDinos.getPosition(dinoId: string): Vector3?
	if not WildDinos.isWild(dinoId) then
		return nil
	end
	return DinoMover.getPosition(KEY_PREFIX .. dinoId)
end

function WildDinos.getAll(): { Model }
	local list = {}
	for _, info in wild do
		table.insert(list, info.Model)
	end
	return list
end

-- 消して RespawnDelay 後の補充を予約する。戻り値: 消したか（すでにいなければ false）
function WildDinos.remove(dinoId: string, reason: string?): boolean
	if not WildDinos.isWild(dinoId) then
		return false
	end
	wild[dinoId] = nil
	aliveCount -= 1
	DinoMover.remove(KEY_PREFIX .. dinoId)
	WildDinos.Removed:Fire(dinoId, reason or "Removed")
	scheduleRespawn()
	return true
end

-- テイム中は足を止める（true）/ 再び歩かせる（false）。戻り値: 対象がいたか
function WildDinos.setTaming(dinoId: string, taming: boolean): boolean
	local info = if WildDinos.isWild(dinoId) then wild[dinoId] else nil
	if not info then
		return false
	end
	local value = taming == true
	DinoMover.setFrozen(KEY_PREFIX .. dinoId, value)
	info.Model:SetAttribute("Taming", value)
	return true
end

function WildDinos.start(dinosFolder: Instance)
	if started then
		return
	end
	started = true
	local existing = dinosFolder:FindFirstChild("Wild")
	if existing then
		existing:Destroy()
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Wild"
	newFolder.Parent = dinosFolder
	folder = newFolder

	task.spawn(function()
		-- 地形ができてから出す（時間切れなら待ち直す）
		while not RanchWorld.waitUntilReady() do
			logWarn("ワールドの完成待ちが時間切れ。野生恐竜の出現を待ち直す")
		end
		fillUp()
	end)
end

return WildDinos
