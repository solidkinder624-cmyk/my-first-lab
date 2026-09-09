-- 06/UI・HUD: 飛行中に必要な情報だけを出す。
-- 高度計・速度計 (左下)、ミッションバー (上部)、着陸装置・ブースト状態を表示する。
-- ミニマップ (タッチパッド切替) は今回のMVPでは未実装 (README の既知の割り切り参照)。

local Players = game:GetService("Players")

local Shared = script.Parent.Parent.Shared
local FlightModel = require(Shared.FlightModel)

local Hud = {}
Hud.__index = Hud

local function label(parent: Instance, position: UDim2, size: UDim2, textSize: number, alignRight: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize
	l.TextColor3 = Color3.fromRGB(235, 240, 245)
	l.TextStrokeTransparency = 0.3
	l.TextXAlignment = if alignRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = parent
	return l
end

function Hud.new()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkyCarrierHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local self = setmetatable({
		gui = gui,
		altitude = label(gui, UDim2.new(0, 24, 1, -110), UDim2.new(0, 260, 0, 34), 26),
		speed = label(gui, UDim2.new(0, 24, 1, -76), UDim2.new(0, 260, 0, 34), 26),
		fuel = label(gui, UDim2.new(0, 24, 1, -42), UDim2.new(0, 260, 0, 30), 20),
		gear = label(gui, UDim2.new(1, -220, 1, -42), UDim2.new(0, 196, 0, 30), 20, true),
		money = label(gui, UDim2.new(1, -220, 1, -76), UDim2.new(0, 196, 0, 30), 20, true),
		mission = label(gui, UDim2.new(0.5, -320, 0, 16), UDim2.new(0, 640, 0, 46), 22),
		message = label(gui, UDim2.new(0.5, -320, 0, 68), UDim2.new(0, 640, 0, 30), 20),
	}, Hud)
	self.mission.TextXAlignment = Enum.TextXAlignment.Center
	self.message.TextXAlignment = Enum.TextXAlignment.Center
	self.message.TextColor3 = Color3.fromRGB(255, 214, 120)

	return self
end

function Hud:updateFlight(state)
	self.altitude.Text = string.format("高度  %4d studs", math.floor(state.y))
	self.speed.Text = string.format("速度  %4d studs/s", math.floor(FlightModel.speed(state)))
	local fuelPercent = math.floor(state.fuel <= 0 and 0 or state.fuel)
	self.fuel.Text = string.format("燃料  %d", fuelPercent)
	self.gear.Text = if state.gearDown then "着陸装置: 展開" else "着陸装置: 格納"
	self.gear.TextColor3 = if state.gearDown then Color3.fromRGB(150, 220, 150) else Color3.fromRGB(220, 150, 120)
end

function Hud:updateMoney(profile)
	self.money.Text = string.format("所持金 %d", math.floor(profile.money))
end

function Hud:updateMission(missionController)
	local mission = missionController.active[1]
	if mission then
		self.mission.Text =
			string.format("配達中: %s → %s   積載 %d   報酬 %d", mission.originId, mission.destId, mission.cargoWeight, math.floor(mission.reward))
	else
		self.mission.Text = "ターミナルでミッションを受注してください"
	end
end

function Hud:flash(text: string)
	self.message.Text = text
	task.delay(3, function()
		if self.message.Text == text then
			self.message.Text = ""
		end
	end)
end

return Hud
