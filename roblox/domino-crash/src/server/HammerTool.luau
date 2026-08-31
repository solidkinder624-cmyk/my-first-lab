-- ハンマー。外部モデルもアニメーションアセットも使わず Part だけで組む。
--
-- 振りのモーションはクライアント側で RightGrip.C0 を動かして作る
-- (HammerController.luau)。Animation インスタンスはアセット ID を要求するので、
-- 「アセット0本」の方針だとそもそも使えない。

local HammerTool = {}

local function weld(a: BasePart, b: BasePart, c0: CFrame)
	local motor = Instance.new("Weld")
	motor.Part0 = a
	motor.Part1 = b
	motor.C0 = c0
	motor.Parent = a
end

function HammerTool.create(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Hammer"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = "構造物の柱を叩いて崩す"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 4.2, 0.5)
	handle.Color = Color3.fromRGB(94, 70, 48)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanQuery = false -- 自分のハンマーにレイが当たらないように
	handle.CanTouch = false
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.9, 1.5, 1.5)
	head.Color = Color3.fromRGB(126, 132, 142)
	head.Material = Enum.Material.Metal
	head.CanCollide = false
	head.CanQuery = false
	head.CanTouch = false
	head.Massless = true
	head.Parent = tool
	weld(handle, head, CFrame.new(0, 2.2, 0))

	local band = Instance.new("Part")
	band.Name = "Band"
	band.Size = Vector3.new(2.0, 0.35, 1.6)
	band.Color = Color3.fromRGB(196, 138, 62)
	band.Material = Enum.Material.Metal
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.Massless = true
	band.Parent = tool
	weld(handle, band, CFrame.new(0, 2.2, 0))

	return tool
end

return HammerTool
