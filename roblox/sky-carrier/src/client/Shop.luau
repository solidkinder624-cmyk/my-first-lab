-- 07/開発ロードマップ P4: 機体ショップ + アップグレードUI。
-- タッチパッド (ButtonSelect) で開閉する。設計図ではタッチパッドはミニマップ用に
-- 割り当てられていたが、ミニマップ自体は未実装 (README の既知の割り切り参照) なので、
-- 経済まわりのUIをここに割り当てている。

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SkyCarrier")
local Config = require(Shared.Config)

local Shop = {}
Shop.__index = Shop

local function button(parent: Instance, layoutOrder: number): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = layoutOrder
	b.Size = UDim2.new(1, 0, 0, 34)
	b.BackgroundColor3 = Color3.fromRGB(40, 46, 58)
	b.TextColor3 = Color3.fromRGB(235, 240, 245)
	b.Font = Enum.Font.Gotham
	b.TextSize = 18
	b.AutoButtonColor = true
	b.Text = ""
	b.Parent = parent
	return b
end

local function row(parent: Instance, layoutOrder: number): Frame
	local f = Instance.new("Frame")
	f.LayoutOrder = layoutOrder
	f.Size = UDim2.new(1, 0, 0, 34)
	f.BackgroundTransparency = 1
	f.Parent = parent
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.Padding = UDim.new(0, 8)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Parent = f
	return f
end

function Shop.new(remotes)
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkyCarrierShop"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 460, 0, 420)
	frame.Position = UDim2.new(0.5, -230, 0.5, -210)
	frame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	frame.BackgroundTransparency = 0.05
	frame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "機体ショップ"
	title.Parent = frame

	local money = Instance.new("TextLabel")
	money.Size = UDim2.new(1, 0, 0, 26)
	money.Position = UDim2.new(0, 0, 0, 40)
	money.BackgroundTransparency = 1
	money.Font = Enum.Font.GothamBold
	money.TextSize = 18
	money.TextColor3 = Color3.fromRGB(255, 214, 120)
	money.Text = "所持金: -"
	money.Parent = frame

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -24, 1, -80)
	list.Position = UDim2.new(0, 12, 0, 70)
	list.BackgroundTransparency = 1
	list.Parent = frame
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = list

	local self = setmetatable({
		remotes = remotes,
		gui = gui,
		money = money,
		list = list,
		profile = { money = 0, currentAircraft = Config.defaultAircraft, ownedAircraft = {}, upgrades = {} },
		connections = {},
	}, Shop)
	return self
end

function Shop:toggle()
	self.gui.Enabled = not self.gui.Enabled
	if self.gui.Enabled then
		self:render()
	end
end

function Shop:applyProfile(profile)
	self.profile = profile
	if self.gui.Enabled then
		self:render()
	end
end

function Shop:render()
	self.money.Text = string.format("所持金: %d", math.floor(self.profile.money))
	for _, child in self.list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local order = 0
	for name, stats in Config.aircraft do
		order += 1
		local r = row(self.list, order)
		local owned = self.profile.ownedAircraft[name] == true
		local current = self.profile.currentAircraft == name
		local b = button(r, 1)
		b.Size = UDim2.new(1, 0, 0, 34)
		if current then
			b.Text = string.format("%s (使用中)", stats.displayName)
			b.BackgroundColor3 = Color3.fromRGB(60, 110, 70)
		elseif owned then
			b.Text = string.format("%s → 乗り換え", stats.displayName)
			b.MouseButton1Click:Connect(function()
				self.remotes.RequestSelectAircraft:InvokeServer(name)
			end)
		else
			b.Text = string.format("%s 購入 (%d)", stats.displayName, stats.price)
			b.MouseButton1Click:Connect(function()
				self.remotes.RequestPurchaseAircraft:InvokeServer(name)
			end)
		end
	end

	for kind, spec in Config.upgrades do
		order += 1
		local r = row(self.list, order)
		local level = self.profile.upgrades[kind] or 0
		local b = button(r, 1)
		b.Size = UDim2.new(1, 0, 0, 34)
		if level >= spec.maxLevel then
			b.Text = string.format("%s Lv.%d (最大)", kind, level)
			b.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		else
			local cost = math.floor(spec.costBase * spec.costGrowth ^ level)
			b.Text = string.format("%s Lv.%d → Lv.%d 強化 (%d)", kind, level, level + 1, cost)
			b.MouseButton1Click:Connect(function()
				self.remotes.RequestPurchaseUpgrade:InvokeServer(kind)
			end)
		end
	end
end

function Shop:start()
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonSelect then
				self:toggle()
			end
		end)
	)
end

function Shop:stop()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}
end

return Shop
