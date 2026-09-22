-- 恐竜AI（dino-ai）の外部向け窓口。サーバー専用 ModuleScript。
-- 起動は同じフォルダの DinoAIBoot（Script）が start() を呼ぶ。
--
-- ■ capture-system からの使い方
--   local DinoService = require(game:GetService("ServerScriptService").DinoAI.DinoService)
--
--   DinoService.getWildDino(dinoId) → Model?        … 野生恐竜のモデル（Workspace.Dinos.Wild.<DinoId>）
--   DinoService.isWild(dinoId) → boolean             … 今も野生として存在するか（飼育恐竜・消えた恐竜は false）
--   DinoService.getWildDinoSpecies(dinoId) → string? … 種Id（DinoConfig.Species のキー）
--   DinoService.getWildDinoPosition(dinoId) → Vector3? … PrimaryPart の位置（距離の判定に）
--   DinoService.getWildDinos() → { Model }            … 今いる野生恐竜の一覧
--   DinoService.setTaming(dinoId, bool) → boolean     … true の間は足を止める（属性 "Taming" / "State"="Taming"）
--                                                       テイムが終わった・中断したら必ず false に戻すこと
--   DinoService.removeWildDino(dinoId, reason?) → boolean
--       … 野生恐竜を消して DinoConfig.Wild.RespawnDelay 秒後の補充を予約する。
--         すでに消えていれば false（2人が同時に捕獲しても1回しか成功しない）
--   DinoService.WildDinoRemoved: Signal (dinoId, reason) … 野生恐竜が消えた（テイム状態の後始末に）
--   DinoService.WildDinoSpawned: Signal (dinoId, model)  … 野生恐竜が出た
--
--   捕獲確定の推奨手順（途中で待たない＝ yield しないので、この3行は割り込まれない）:
--     if DinoService.isWild(dinoId) then
--         local ok = PlayerData.addDino(player, DinoService.getWildDinoSpecies(dinoId))
--         if ok then DinoService.removeWildDino(dinoId, "Captured") end
--     end
--   → PlayerData.addDino が DinoAdded を発火し、DinoAI がその人の拠点（柵の内側）に飼育恐竜を出す。
--
-- ■ その他（ui-designer など）
--   DinoService.getRanchDino(dinoId) → Model?         … 飼育恐竜のモデル（Workspace.Dinos.Ranch.<UserId>.<DinoId>）
--   DinoService.getRanchSlot(player) → number?        … DinoAI が割り当てた拠点スロット番号
--
-- 恐竜の見分け方（Workspace.Dinos 内のモデルの属性）:
--   共通: "DinoId"（一意の文字列 = モデル名）, "Species", "Wild"（true = 野生 / false = 飼育）,
--         "State"（"Idle" / "Walking" / "Taming"）, "GroundOffset"（地面から PrimaryPart 中心までの高さ）
--   野生のみ: "Taming"（bool）
--   飼育のみ: "OwnerUserId", "Level"
--   ※飼育恐竜（Wild = false）はテイムの対象にしないこと。DinoService.isWild で必ず確かめる。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DinoConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DinoConfig"))
local WanderLogic = require(script.Parent:WaitForChild("WanderLogic"))
local DinoMover = require(script.Parent:WaitForChild("DinoMover"))
local WildDinos = require(script.Parent:WaitForChild("WildDinos"))
local RanchDinos = require(script.Parent:WaitForChild("RanchDinos"))

local DinoService = {}

DinoService.WildDinoRemoved = WildDinos.Removed
DinoService.WildDinoSpawned = WildDinos.Spawned
DinoService.States = DinoMover.States

local started = false

-- ── 野生（capture-system 向け） ─────────────────────────
function DinoService.getWildDino(dinoId: string): Model?
	if type(dinoId) ~= "string" then
		return nil
	end
	return WildDinos.getModel(dinoId)
end

function DinoService.isWild(dinoId: string): boolean
	return WildDinos.isWild(dinoId)
end

function DinoService.getWildDinoSpecies(dinoId: string): string?
	if type(dinoId) ~= "string" then
		return nil
	end
	return WildDinos.getSpecies(dinoId)
end

function DinoService.getWildDinoPosition(dinoId: string): Vector3?
	return WildDinos.getPosition(dinoId)
end

function DinoService.getWildDinos(): { Model }
	return WildDinos.getAll()
end

function DinoService.removeWildDino(dinoId: string, reason: string?): boolean
	return WildDinos.remove(dinoId, reason)
end

function DinoService.setTaming(dinoId: string, taming: boolean): boolean
	return WildDinos.setTaming(dinoId, taming)
end

-- ── 飼育・モデル ─────────────────────────────────────
function DinoService.getRanchDino(dinoId: string): Model?
	if type(dinoId) ~= "string" then
		return nil
	end
	return RanchDinos.getModel(dinoId)
end

function DinoService.getRanchSlot(player: Player): number?
	return RanchDinos.getSlot(player)
end

-- ── 起動 ─────────────────────────────────────────────
function DinoService.start()
	assert(RunService:IsServer(), "DinoService はサーバー専用です")
	if started then
		return
	end
	started = true
	WanderLogic.validateConfig(DinoConfig)

	local dinosFolder = workspace:FindFirstChild("Dinos")
	if not dinosFolder then
		dinosFolder = Instance.new("Folder")
		dinosFolder.Name = "Dinos"
		dinosFolder.Parent = workspace
	end

	DinoMover.start()
	WildDinos.start(dinosFolder)
	RanchDinos.start(dinosFolder)
end

return DinoService
