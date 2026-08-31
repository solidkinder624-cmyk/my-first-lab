-- HUD。画像アセットを使わず Frame と TextLabel だけで組む。
--
-- 表示するのは3つだけ:
--   * 自分の崩壊率 (大きく・太く・遅延なしで)
--   * 残り時間
--   * 相手の崩壊率 (自分のすぐ横に並べる)
--
-- 相手のバーを自分のバーの真横に置いているのは意図的で、
-- 「あと少しで抜かれる」が視線を動かさずに分かる位置に無いと、
-- スピード勝負の緊張感が生まれないため。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("DominoCrash").Config)

local HUDController = {}
HUDController.__index = HUDController

local MINE = Color3.fromRGB(255, 176, 64)
local THEIRS = Color3.fromRGB(96, 168, 232)
local DIM = Color3.fromRGB(226, 232, 245)

local PHASE_TEXT = {
	Waiting = "対戦相手を待っています",
	Countdown = "構造物を確認せよ",
	Playing = "",
	Result = "",
}

local function label(parent: Instance, size: UDim2, position: UDim2, textSize: number, font: Enum.Font?): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = size
	text.Position = position
	text.Font = font or Enum.Font.GothamMedium
	text.TextSize = textSize
	text.TextColor3 = DIM
	text.TextStrokeTransparency = 0.55
	text.Text = ""
	text.Parent = parent
	return text
end

local function bar(parent: Instance, size: UDim2, position: UDim2, color: Color3)
	local back = Instance.new("Frame")
	back.Size = size
	back.Position = position
	back.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	return fill
end

function HUDController.new()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DominoCrashHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- 上部: 残り時間
	local timer = label(gui, UDim2.new(1, 0, 0, 52), UDim2.new(0, 0, 0, 14), 40, Enum.Font.GothamBold)
	timer.TextColor3 = Color3.fromRGB(255, 255, 255)

	-- 中央: フェーズの合図 (カウントダウン・結果)
	local banner = label(gui, UDim2.new(1, 0, 0, 90), UDim2.new(0, 0, 0.34, 0), 64, Enum.Font.GothamBold)
	local subtitle = label(gui, UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 0.34, 92), 22)

	-- 左下: 自分の崩壊率
	local mineFrame = Instance.new("Frame")
	mineFrame.BackgroundTransparency = 1
	mineFrame.Size = UDim2.new(0, 380, 0, 108)
	mineFrame.Position = UDim2.new(0, 26, 1, -134)
	mineFrame.Parent = gui

	local mineCaption = label(mineFrame, UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 0), 18)
	mineCaption.TextXAlignment = Enum.TextXAlignment.Left
	mineCaption.Text = "崩壊率"

	local minePercent = label(mineFrame, UDim2.new(1, 0, 0, 58), UDim2.new(0, 0, 0, 18), 54, Enum.Font.GothamBold)
	minePercent.TextXAlignment = Enum.TextXAlignment.Left
	minePercent.TextColor3 = MINE
	minePercent.Text = "0.0%"

	local mineFill = bar(mineFrame, UDim2.new(1, 0, 0, 14), UDim2.new(0, 0, 0, 84), MINE)

	-- 右下: 相手たち
	local rivals = Instance.new("Frame")
	rivals.BackgroundTransparency = 1
	rivals.Size = UDim2.new(0, 300, 0, 160)
	rivals.Position = UDim2.new(1, -326, 1, -186)
	rivals.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = rivals

	return setmetatable({
		player = player,
		gui = gui,
		timer = timer,
		banner = banner,
		subtitle = subtitle,
		minePercent = minePercent,
		mineFill = mineFill,
		rivals = rivals,
		rows = {}, -- slotIndex → { frame, name, fill, percent }
		mySlot = nil :: number?,
		names = {},
	}, HUDController)
end

function HUDController:_row(slotIndex: number)
	local row = self.rows[slotIndex]
	if row then
		return row
	end

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 34)
	frame.LayoutOrder = slotIndex
	frame.Parent = self.rivals

	local name = label(frame, UDim2.new(0.6, 0, 0, 18), UDim2.new(0, 0, 0, 0), 16)
	name.TextXAlignment = Enum.TextXAlignment.Left

	local percent = label(frame, UDim2.new(0.4, 0, 0, 18), UDim2.new(0.6, 0, 0, 0), 16, Enum.Font.GothamBold)
	percent.TextXAlignment = Enum.TextXAlignment.Right

	local fill = bar(frame, UDim2.new(1, 0, 0, 8), UDim2.new(0, 0, 0, 22), THEIRS)

	row = { frame = frame, name = name, fill = fill, percent = percent }
	self.rows[slotIndex] = row
	return row
end

function HUDController:setMySlot(slotIndex: number?)
	self.mySlot = slotIndex
end

function HUDController:applyState(payload)
	for _, entry in payload.slots or {} do
		self.names[entry.slot] = entry.name
		if entry.userId == self.player.UserId then
			self.mySlot = entry.slot
		end
	end

	local phase = payload.phase
	if phase == "Playing" then
		self.timer.Text = string.format("%.1f", payload.timeLeft)
		self.timer.TextColor3 = if payload.timeLeft <= 10 then Color3.fromRGB(255, 110, 110) else Color3.new(1, 1, 1)
		self.banner.Text = ""
		self.subtitle.Text = ""
	elseif phase == "Countdown" then
		self.timer.Text = ""
		self.banner.Text = tostring(math.ceil(payload.timeLeft))
		self.subtitle.Text = string.format("%s / 柱を狙え", tostring(payload.kind))
	elseif phase == "Result" then
		self.timer.Text = ""
		local winner = payload.winner
		if winner then
			local mine = winner.slot == self.mySlot
			self.banner.Text = if mine then "WIN" else "LOSE"
			self.banner.TextColor3 = if mine then MINE else Color3.fromRGB(180, 186, 200)
			self.subtitle.Text = string.format("%s  %.1f%%", tostring(winner.name), winner.percent)
		else
			self.banner.Text = ""
			self.subtitle.Text = ""
		end
	else
		self.timer.Text = ""
		self.banner.Text = ""
		self.banner.TextColor3 = Color3.new(1, 1, 1)
		self.subtitle.Text = PHASE_TEXT[phase] or ""
	end
end

function HUDController:applyProgress(scores)
	local seen = {}
	for _, score in scores do
		if score.slot == self.mySlot then
			self.minePercent.Text = string.format("%.1f%%", score.percent)
			-- ゲージだけ少し補間する。0.2秒ごとの更新をそのまま反映すると
			-- 数字は正しいのにバーがカクカクして安っぽく見える。
			TweenService:Create(
				self.mineFill,
				TweenInfo.new(Config.progress.interval, Enum.EasingStyle.Linear),
				{ Size = UDim2.fromScale(score.percent / 100, 1) }
			):Play()
		else
			seen[score.slot] = true
			local row = self:_row(score.slot)
			row.name.Text = self.names[score.slot] or ("スロット " .. score.slot)
			row.percent.Text = string.format("%.1f%%", score.percent)
			TweenService:Create(
				row.fill,
				TweenInfo.new(Config.progress.interval, Enum.EasingStyle.Linear),
				{ Size = UDim2.fromScale(score.percent / 100, 1) }
			):Play()
		end
	end

	-- 抜けた相手の行を片付ける
	for slotIndex, row in self.rows do
		if not seen[slotIndex] then
			row.frame:Destroy()
			self.rows[slotIndex] = nil
		end
	end
end

function HUDController:reset()
	self.minePercent.Text = "0.0%"
	self.mineFill.Size = UDim2.fromScale(0, 1)
	for slotIndex, row in self.rows do
		row.frame:Destroy()
		self.rows[slotIndex] = nil
	end
end

return HUDController
