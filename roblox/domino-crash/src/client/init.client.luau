-- クライアント側エントリポイント。
--
-- このクライアントが持つ権限は「サーバに打撃を申告すること」だけ。
-- 崩壊の判定も崩壊率もサーバが持っているので、ここを改造しても
-- 壊せる範囲は増えない。逆に、演出はすべてここで作る:
-- サーバから届く OnStructureExplode は「どこで・どれくらい崩れたか」の
-- 数個の数字だけで、粉塵もカメラ揺れもこのクライアントがローカルに生成する。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DominoCrash")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Effects = require(script.Effects)
local CameraEffects = require(script.Controller.CameraEffects)
local HammerController = require(script.Controller.HammerController)
local HUDController = require(script.UI.HUDController)

local player = Players.LocalPlayer
local remotes = Net.client()

local effects = Effects.new()
local camera = CameraEffects.new()
local hud = HUDController.new()
local hammer = HammerController.new(remotes, effects, camera)

camera:start()
hammer:start()

-- ── フェーズ ────────────────────────────────────────────
remotes.MatchStateChanged.OnClientEvent:Connect(function(payload)
	hud:applyState(payload)
	hammer:setEnabled(payload.phase == "Playing")
	if payload.phase == "Countdown" then
		hud:reset()
	elseif payload.phase == "Result" then
		local winner = payload.winner
		if winner and winner.slot == hud.mySlot then
			camera:impact(0.5, false)
			effects:play("win")
		end
	end
end)

remotes.ProgressSync.OnClientEvent:Connect(function(scores)
	hud:applyProgress(scores)
end)

-- ── 崩壊の演出 ──────────────────────────────────────────
remotes.OnStructureExplode.OnClientEvent:Connect(function(payload)
	local currentCamera = Workspace.CurrentCamera
	local position = payload.position

	-- 崩れた規模を 0..1 に正規化する。1回の打撃で 200個も崩れれば
	-- それはもう「一斉爆破」なので、そこで頭打ちにする。
	local scale = math.clamp((payload.direct + payload.chain) / 200, 0, 1)
	effects:collapseDust(position, scale, payload.keyHit)
	effects:play("collapse", position)

	if not currentCamera then
		return
	end

	-- 自分の崩壊はもちろん、隣のスロットの崩壊も距離に応じて薄く伝える。
	-- 「向こうで派手に崩れている音がする」が焦りを生む。
	local distance = (currentCamera.CFrame.Position - position).Magnitude
	local falloff = math.clamp(1 - distance / (Config.arena.slotSpacing * 0.8), 0, 1)
	if falloff <= 0 then
		return
	end

	local base = if payload.keyHit then Config.juice.shakeKeyTrauma else Config.juice.shakeTrauma
	local mine = payload.slot == hud.mySlot
	camera:impact(base * (0.35 + 0.65 * scale) * falloff, mine)
	if mine then
		effects:play("hit", position)
	end
end)

print(string.format("[DominoCrash] クライアント起動 (%s)", player.DisplayName))
