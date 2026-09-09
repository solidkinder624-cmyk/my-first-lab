-- 機体の見た目を Part だけで組む (3Dモデル・テクスチャ資産を使わない方針)。
-- 胴体・主翼・尾翼の3パーツだけの簡易形状。役目は「向きと位置が伝わること」で、
-- 見栄えは Config.appearance 的な色分けで最低限担保する。

local AircraftRig = {}

local function part(size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CastShadow = false
	return p
end

function AircraftRig.build(color: Color3, isLocal: boolean): Model
	local model = Instance.new("Model")
	model.Name = if isLocal then "LocalAircraft" else "RemoteAircraft"

	local fuselage = part(Vector3.new(4, 3, 16), color)
	fuselage.Name = "Fuselage"
	fuselage.Parent = model

	local wing = part(Vector3.new(20, 1, 5), color:Lerp(Color3.new(1, 1, 1), 0.15))
	wing.Name = "Wing"
	wing.CFrame = fuselage.CFrame * CFrame.new(0, 0, 1)
	wing.Parent = model

	local tail = part(Vector3.new(8, 4, 2), color:Lerp(Color3.new(1, 1, 1), 0.15))
	tail.Name = "Tail"
	tail.CFrame = fuselage.CFrame * CFrame.new(0, 1.5, 7)
	tail.Parent = model

	local weldWing = Instance.new("WeldConstraint")
	weldWing.Part0 = fuselage
	weldWing.Part1 = wing
	weldWing.Parent = fuselage

	local weldTail = Instance.new("WeldConstraint")
	weldTail.Part0 = fuselage
	weldTail.Part1 = tail
	weldTail.Parent = fuselage

	model.PrimaryPart = fuselage
	return model
end

function AircraftRig.setPose(model: Model, x: number, y: number, z: number, pitch: number, yaw: number, roll: number)
	if not model.PrimaryPart then
		return
	end
	local cframe = CFrame.new(x, y, z) * CFrame.fromOrientation(math.rad(pitch), math.rad(yaw), math.rad(roll))
	model:PivotTo(cframe)
end

return AircraftRig
