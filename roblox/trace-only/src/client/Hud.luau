-- HUD。画像アセットを使わず、Frame と TextLabel だけで構成する。
-- 表示するのは「自分の状態」と「ラウンド情報」だけで、
-- 他プレイヤーの位置に関する情報は一切載せない。

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)

local Hud = {}
Hud.__index = Hud

local ROLE_TEXT = {
	Seeker = "鬼",
	Hider = "隠れ手",
	Found = "発見済み",
	Hunter = "鬼",
	Runner = "逃げ手",
	Free = "待機中",
}

local function label(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = size
	text.Position = position
	text.Font = Enum.Font.GothamMedium
	text.TextSize = textSize
	text.TextColor3 = Color3.fromRGB(226, 232, 245)
	text.TextStrokeTransparency = 0.6
	text.Text = ""
	text.Parent = parent
	return text
end

function Hud.new()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "TraceOnlyHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- 上部: モード・残り時間・アナウンス
	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 80)
	top.Position = UDim2.new(0, 0, 0, 12)
	top.Parent = gui

	local title = label(top, UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 0), 22)
	title.Font = Enum.Font.GothamBold
	local timer = label(top, UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 26), 18)
	timer.TextColor3 = Color3.fromRGB(160, 200, 255)
	local message = label(top, UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 50), 16)
	message.TextColor3 = Color3.fromRGB(255, 214, 140)

	-- 中央: 照準の点 (体が見えないので、視線の基準として必要)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 4, 0, 4)
	dot.Position = UDim2.new(0.5, -2, 0.5, -2)
	dot.BackgroundColor3 = Color3.fromRGB(200, 220, 255)
	dot.BackgroundTransparency = 0.4
	dot.BorderSizePixel = 0
	dot.Parent = gui

	-- 左下: 役割と目的
	local role = label(gui, UDim2.new(0, 340, 0, 24), UDim2.new(0, 24, 1, -96), 20)
	role.TextXAlignment = Enum.TextXAlignment.Left
	role.Font = Enum.Font.GothamBold
	local objective = label(gui, UDim2.new(0, 420, 0, 20), UDim2.new(0, 24, 1, -72), 16)
	objective.TextXAlignment = Enum.TextXAlignment.Left
	objective.TextColor3 = Color3.fromRGB(170, 178, 195)

	-- 下中央: スタミナ (ダッシュとジャンプ = 音を出す行為の残量)
	local barBack = Instance.new("Frame")
	barBack.Size = UDim2.new(0, 260, 0, 8)
	barBack.Position = UDim2.new(0.5, -130, 1, -40)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
	barBack.BorderSizePixel = 0
	barBack.Parent = gui

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(120, 220, 255)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack

	local stance = label(gui, UDim2.new(0, 260, 0, 18), UDim2.new(0.5, -130, 1, -66), 15)
	stance.TextColor3 = Color3.fromRGB(150, 160, 180)

	return setmetatable({
		gui = gui,
		title = title,
		timer = timer,
		message = message,
		role = role,
		objective = objective,
		barFill = barFill,
		stance = stance,
	}, Hud)
end

-- サーバからのラウンド情報
function Hud:applyState(state)
	self.title.Text = state.mode or "-"
	if state.phase == "Playing" then
		self.timer.Text = string.format("残り %d:%02d", math.floor(state.timeLeft / 60), state.timeLeft % 60)
	else
		self.timer.Text = string.format("次のラウンドまで %d 秒", state.timeLeft)
	end
	self.message.Text = state.message or ""
	self.role.Text = string.format("%s   スコア %d", ROLE_TEXT[state.role] or state.role, state.score or 0)
	self.objective.Text = state.objective or ""
end

-- 毎フレーム更新する自分の状態
function Hud:applyLocal(motionState)
	local ratio = motionState.stamina / Config.stamina.max
	self.barFill.Size = UDim2.fromScale(ratio, 1)
	self.barFill.BackgroundColor3 = if ratio < 0.25
		then Color3.fromRGB(255, 120, 120)
		else Color3.fromRGB(120, 220, 255)

	if motionState.stance == "Crouch" then
		self.stance.Text = "しゃがみ — 足跡は出ない / 移動が遅い"
	elseif motionState.stance == "Sprint" then
		self.stance.Text = "ダッシュ — 足跡が濃く、遠くまで届く"
	else
		self.stance.Text = "歩行 — Ctrl でしゃがみ / Shift でダッシュ"
	end
end

return Hud
