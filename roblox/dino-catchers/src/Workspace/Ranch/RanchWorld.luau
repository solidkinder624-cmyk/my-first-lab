-- ワールド（拠点・プレイヤー出現地点・野生の出現範囲）を他の担当が使うための窓口。
--
-- 使い方（サーバーのスクリプトから）:
--   local RanchWorld = require(workspace:WaitForChild("Ranch"):WaitForChild("RanchWorld"))
--   RanchWorld.waitUntilReady()            -- 地形と柵ができあがるまで待つ（座標の計算だけなら待たなくてよい）
--       最大 DinoConfig.World.ReadyTimeout 秒。時間切れなら警告を出して false を返す
--
-- ■ 拠点スロット（1人1つ。6スロットを南側に東西一列で用意）
--   RanchWorld.getSlotCount() → number
--   RanchWorld.claimSlot(player) → slotIndex?      … 空きスロットを割り当てる（すでに持っていればそれを返す）
--       満員・ワールド完成待ちの時間切れ・待っている間に退出した場合は nil
--   RanchWorld.releaseSlot(player)                 … 返す。返したあと SlotReleased が発火する
--   RanchWorld.SlotReleased: Signal                … (player, slotIndex) スロットが空きに戻ったとき
--       退出時の自動解放について: Players.PlayerRemoving の中では releaseSlot を task.defer で遅らせて呼ぶ。
--       そのため他の担当は自分の PlayerRemoving 処理の中でまだ getSlotIndexForPlayer(player) を使える。
--       解放後に片付けをしたい場合は SlotReleased:Connect(function(player, slotIndex) ... end) を使う（推奨）
--   RanchWorld.getSlotIndexForPlayer(player) → slotIndex?
--   RanchWorld.getSlotOwnerUserId(slotIndex) → number（0 = 空き）
--   RanchWorld.getSlotFolder(slotIndex) → Folder   … Workspace.Ranch.Slots.Slot<N>
--   RanchWorld.getSlotCenter(slotIndex) → Vector3  … 拠点の中心（地面の高さ）
--   RanchWorld.getSlotSpawnCFrame(slotIndex) → CFrame … 入口の外側で入口の方を向いた位置（テレポート用）
--
-- ■ 柵の内側（飼育恐竜を歩かせる範囲）… margin を省略すると DinoConfig.Ranch.FenceMargin だけ柵から離す
--   RanchWorld.getRandomPointInRanch(slotIndex, rng?, margin?) → Vector3（y = 地面の高さ）
--   RanchWorld.isInsideRanch(slotIndex, position, margin?) → boolean
--   RanchWorld.clampToRanch(slotIndex, position, margin?) → Vector3（柵の内側に戻した位置）
--   RanchWorld.getFenceBounds(slotIndex, margin?) → { MinX, MaxX, MinZ, MaxZ, GroundY }
--   RanchWorld.getPlots(slotIndex) → { { PX, PZ } }（区画の一覧のコピー）
--
-- ■ プレイヤーの出現地点
--   RanchWorld.getPlayerSpawnCFrame() → CFrame（Workspace.Ranch.Markers.PlayerSpawn の上）
--
-- ■ 野生恐竜の出現範囲（拠点のどのスロットの中心からも DinoConfig.Wild.MinSpawnDistanceFromRanch 以上離れる）
--   RanchWorld.getRandomWildSpawnPoint(rng?, avoidPositions?, avoidDistance?) → Vector3?（y = 地面の高さ）
--       avoidPositions: { Vector3 }（例: 全プレイヤーの位置）, avoidDistance: 例 DinoConfig.Wild.MinSpawnDistanceFromPlayer
--   RanchWorld.isWildSpawnable(position) → boolean
--   RanchWorld.isWildWalkable(position) → boolean  … 野生恐竜のうろつき先に使ってよいか（拠点・広場・水・外周の丘は不可）
--   RanchWorld.getWildSpawnArea() → { MinX, MaxX, MinZ, MaxZ }
--
-- ■ 地面
--   RanchWorld.getGroundHeight(x, z) → number / RanchWorld.getGroundPosition(x, z) → Vector3
--
-- ■ 拠点の拡張（未決C のため、まだどこからも呼ばない。仕組みだけ用意）
--   RanchWorld.addPlot(slotIndex, px, pz) → (ok, reason?)
--
-- rng を省略するとこのモジュールの Random を使う。Random.new() を渡してもよい。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DinoConfig = require(Shared:WaitForChild("DinoConfig"))
local Signal = require(Shared:WaitForChild("Signal"))
local WorldLayout = require(script.Parent:WaitForChild("WorldLayout"))
local RanchBuilder = require(script.Parent:WaitForChild("RanchBuilder"))
local TerrainGen = require(script.Parent:WaitForChild("TerrainGen"))

local RanchFolder = script.Parent

local RanchWorld = {}

-- スロットが空きに戻ったとき (player, slotIndex) で発火する
RanchWorld.SlotReleased = Signal.new()

-- 計算の本体（WorldBoot もこれを使って地形・柵を作る）
local layout = WorldLayout.new(DinoConfig)
RanchWorld.Layout = layout

local defaultRng = Random.new()

-- スロットごとの区画の一覧
local plotsBySlot: { [number]: { { PX: number, PZ: number } } } = {}
for index = 1, #layout.Slots do
	plotsBySlot[index] = layout:getInitialPlots()
end

local function checkSlot(slotIndex: number)
	assert(plotsBySlot[slotIndex], "拠点スロット番号が範囲外: " .. tostring(slotIndex))
end

local function ground(): number
	return layout.World.GroundLevel
end

-- ── 準備完了 ──────────────────────────────────────────
function RanchWorld.isReady(): boolean
	return RanchFolder:GetAttribute("WorldReady") == true
end

-- 地形・柵ができあがるまで待つ（属性 WorldReady の変化をイベントで待つ）。
-- timeout 秒（省略時 DinoConfig.World.ReadyTimeout）で諦めたら警告を出して false
function RanchWorld.waitUntilReady(timeout: number?): boolean
	if RanchWorld.isReady() then
		return true
	end
	local limit = timeout or DinoConfig.World.ReadyTimeout
	local thread = coroutine.running()
	local finished = false
	local connection
	local function resume(result: boolean)
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		task.spawn(thread, result)
	end
	connection = RanchFolder:GetAttributeChangedSignal("WorldReady"):Connect(function()
		if RanchWorld.isReady() then
			resume(true)
		end
	end)
	local timer = task.delay(limit, resume, false)
	local ok = coroutine.yield()
	if ok then
		task.cancel(timer)
	else
		warn(string.format("[RanchWorld] ワールドの完成を %s 秒待ったが完成しなかった", tostring(limit)))
	end
	return ok
end

-- ── スロット ──────────────────────────────────────────
function RanchWorld.getSlotCount(): number
	return #layout.Slots
end

function RanchWorld.getSlotFolder(slotIndex: number): Folder?
	checkSlot(slotIndex)
	local slots = RanchFolder:FindFirstChild("Slots")
	return slots and slots:FindFirstChild("Slot" .. slotIndex) :: Folder?
end

function RanchWorld.getSlotCenter(slotIndex: number): Vector3
	local slot = layout:getSlot(slotIndex)
	return Vector3.new(slot.CenterX, ground(), slot.CenterZ)
end

function RanchWorld.getSlotSpawnCFrame(slotIndex: number): CFrame
	checkSlot(slotIndex)
	local gate = layout:getGateInfo(slotIndex, plotsBySlot[slotIndex])
	local y = ground() + DinoConfig.World.SlotSpawnHeightOffset
	local position = Vector3.new(gate.OutsideX, y, gate.OutsideZ)
	return CFrame.lookAt(position, Vector3.new(gate.X, y, gate.Z))
end

-- 持ち主の管理はスロットの属性 OwnerUserId（0 = 空き）で行う
function RanchWorld.getSlotOwnerUserId(slotIndex: number): number
	local folder = RanchWorld.getSlotFolder(slotIndex)
	return if folder then (folder:GetAttribute("OwnerUserId") or 0) else 0
end

function RanchWorld.getSlotIndexForPlayer(player: Player): number?
	for index = 1, #layout.Slots do
		if RanchWorld.getSlotOwnerUserId(index) == player.UserId then
			return index
		end
	end
	return nil
end

function RanchWorld.claimSlot(player: Player): number?
	assert(RunService:IsServer(), "claimSlot はサーバーからだけ呼ぶ")
	if not RanchWorld.waitUntilReady() then
		return nil
	end
	if not player.Parent then
		return nil -- 待っている間に退出した
	end
	local existing = RanchWorld.getSlotIndexForPlayer(player)
	if existing then
		return existing
	end
	for index = 1, #layout.Slots do
		local folder = RanchWorld.getSlotFolder(index)
		if folder and (folder:GetAttribute("OwnerUserId") or 0) == 0 then
			folder:SetAttribute("OwnerUserId", player.UserId)
			RanchBuilder.setSignText(folder, player.DisplayName .. " の拠点")
			return index
		end
	end
	return nil
end

function RanchWorld.releaseSlot(player: Player)
	local index = RanchWorld.getSlotIndexForPlayer(player)
	if not index then
		return
	end
	local folder = RanchWorld.getSlotFolder(index)
	if folder then
		folder:SetAttribute("OwnerUserId", 0)
		RanchBuilder.setSignText(folder, string.format(DinoConfig.Text.VacantRanchLabel, index))
	end
	RanchWorld.SlotReleased:Fire(player, index)
end

-- ── 柵の内側 ──────────────────────────────────────────
function RanchWorld.getPlots(slotIndex: number): { { PX: number, PZ: number } }
	checkSlot(slotIndex)
	local copy = {}
	for _, p in plotsBySlot[slotIndex] do
		table.insert(copy, { PX = p.PX, PZ = p.PZ })
	end
	return copy
end

function RanchWorld.getFenceBounds(slotIndex: number, margin: number?)
	checkSlot(slotIndex)
	local b = layout:getRanchBounds(slotIndex, plotsBySlot[slotIndex], margin)
	b.GroundY = ground()
	return b
end

function RanchWorld.isInsideRanch(slotIndex: number, position: Vector3, margin: number?): boolean
	checkSlot(slotIndex)
	return layout:isInsideRanch(slotIndex, plotsBySlot[slotIndex], position.X, position.Z, margin)
end

function RanchWorld.getRandomPointInRanch(slotIndex: number, rng: Random?, margin: number?): Vector3
	checkSlot(slotIndex)
	local x, z = layout:getRandomPointInRanch(slotIndex, plotsBySlot[slotIndex], rng or defaultRng, margin)
	return Vector3.new(x, ground(), z)
end

function RanchWorld.clampToRanch(slotIndex: number, position: Vector3, margin: number?): Vector3
	checkSlot(slotIndex)
	local x, z = layout:clampToRanch(slotIndex, plotsBySlot[slotIndex], position.X, position.Z, margin)
	return Vector3.new(x, ground(), z)
end

-- ── プレイヤーの出現地点 ─────────────────────────────────
function RanchWorld.getPlayerSpawnCFrame(): CFrame
	local p = layout.PlayerSpawn
	return CFrame.new(p.X, p.Y + DinoConfig.World.PlayerSpawnHeightOffset, p.Z)
end

-- ── 野生 ─────────────────────────────────────────────
function RanchWorld.getWildSpawnArea()
	local a = layout.WildArea
	return { MinX = a.MinX, MaxX = a.MaxX, MinZ = a.MinZ, MaxZ = a.MaxZ }
end

function RanchWorld.getRandomWildSpawnPoint(rng: Random?, avoidPositions: { Vector3 }?, avoidDistance: number?): Vector3?
	local avoid = nil
	if avoidPositions then
		avoid = {}
		for _, pos in avoidPositions do
			table.insert(avoid, { X = pos.X, Z = pos.Z })
		end
	end
	local x, y, z = layout:getRandomWildSpawnPoint(rng or defaultRng, avoid, avoidDistance)
	if x == nil then
		return nil
	end
	return Vector3.new(x, y, z)
end

function RanchWorld.isWildSpawnable(position: Vector3): boolean
	return (layout:isWildSpawnable(position.X, position.Z))
end

function RanchWorld.isWildWalkable(position: Vector3): boolean
	return layout:isWildWalkable(position.X, position.Z)
end

-- ── 地面 ─────────────────────────────────────────────
function RanchWorld.getGroundHeight(x: number, z: number): number
	return layout:getGroundHeight(x, z)
end

function RanchWorld.getGroundPosition(x: number, z: number): Vector3
	return Vector3.new(x, layout:getGroundHeight(x, z), z)
end

-- ── 拠点の拡張（未決C: 呼び出し元はまだ無い） ──────────────────
function RanchWorld.addPlot(slotIndex: number, px: number, pz: number): (boolean, string?)
	assert(RunService:IsServer(), "addPlot はサーバーからだけ呼ぶ")
	checkSlot(slotIndex)
	local plots = plotsBySlot[slotIndex]
	local ok, reason = layout:canAddPlot(slotIndex, plots, px, pz)
	if not ok then
		return false, reason
	end
	table.insert(plots, { PX = px, PZ = pz })
	TerrainGen.paintPlot(workspace.Terrain, layout, layout:getPlotRect(slotIndex, px, pz))
	local folder = RanchWorld.getSlotFolder(slotIndex)
	if folder then
		RanchBuilder.rebuildSlot(layout, folder, slotIndex, plots)
	end
	return true, nil
end

-- 退出したプレイヤーのスロットは自動で空きに戻す。
-- task.defer で遅らせるので、他の担当の PlayerRemoving 処理ではまだ getSlotIndexForPlayer が使える
if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(RanchWorld.releaseSlot, player)
	end)
end

return RanchWorld
