-- ワールドの地形と発着点を組み立てる。
--
-- 3Dモデル・テクスチャは使わず Part の色分けだけで「中央空港 / 貨物ターミナル3か所 /
-- 自由飛行3エリア」を作る。ターミナルの座標は Mission.luau が使う Terminal
-- (id, x, y, z) としてそのまま返すので、経路計算とワールドの見た目が必ず一致する。

local WorldBuilder = {}

local TERMINAL_SPECS = {
	{ id = "central", name = "中央空港", x = 0, z = 0, radius = 90, color = Color3.fromRGB(90, 130, 160) },
	{ id = "north", name = "北: 工業地帯", x = 0, z = -1400, radius = 60, color = Color3.fromRGB(200, 140, 70) },
	{ id = "east", name = "東: 港湾", x = 1400, z = 900, radius = 60, color = Color3.fromRGB(70, 150, 200) },
	{ id = "south", name = "南: 農地", x = -900, z = 1300, radius = 60, color = Color3.fromRGB(120, 170, 90) },
}

local function makePad(spec, groundHeight: number, folder: Instance)
	local part = Instance.new("Part")
	part.Name = spec.id
	part.Anchored = true
	part.CanCollide = true
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(4, spec.radius * 2, spec.radius * 2)
	part.CFrame = CFrame.new(spec.x, groundHeight - 2, spec.z) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = spec.color
	part.Material = Enum.Material.Concrete
	part.Parent = folder

	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.new(0, 200, 0, 40)
	label.StudsOffset = Vector3.new(0, spec.radius * 0.4 + 6, 0)
	label.AlwaysOnTop = true
	label.Parent = part
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.4
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Text = spec.name
	text.Parent = label

	-- 07/開発ロードマップ P3: ターミナルのProximityPrompt。□ (荷物投下) は
	-- 届け先での決定に使っているので、受注はまだ配線していない R1 に割り当てる。
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AcceptMissionPrompt"
	prompt.ActionText = "ミッション受注"
	prompt.ObjectText = spec.name
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 40
	prompt.RequiresLineOfSight = false
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonR1
	prompt:SetAttribute("TerminalId", spec.id)
	prompt.Parent = part

	return part
end

-- 戻り値: { terminals = {Mission.Terminal...}, parts = {[id]=Part}, spawnCFrame = CFrame }
function WorldBuilder.build(parentWorkspace: Instance, cfg): { terminals: any, parts: any, spawnCFrame: CFrame }
	local folder = Instance.new("Folder")
	folder.Name = "SkyCarrierWorld"
	folder.Parent = parentWorkspace

	local terminals = {}
	local parts = {}
	for _, spec in TERMINAL_SPECS do
		local part = makePad(spec, cfg.flight.groundHeight, folder)
		parts[spec.id] = part
		table.insert(terminals, { id = spec.id, x = spec.x, y = cfg.flight.groundHeight, z = spec.z })
	end

	local spawnCFrame = CFrame.new(0, cfg.flight.groundHeight + 6, 40)

	return { terminals = terminals, parts = parts, spawnCFrame = spawnCFrame }
end

return WorldBuilder
