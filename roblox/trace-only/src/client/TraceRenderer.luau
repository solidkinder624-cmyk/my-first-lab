-- 痕跡の描画。ここだけが「他プレイヤーの存在」を画面に出す唯一の場所。
--
-- 3Dモデルもテクスチャアセットも使わず、Part と rbxasset の既定パーティクルだけで作る。
-- 色でクラス分けする:
--   自分の足跡      緑  (自分がどこを通ったか思い出せる)
--   他人の足跡      青白 / ダッシュは橙 (急いでいる相手ほど目立つ)
--   ジャンプ・着地  青   宝の取得 金   タッチ 赤

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)

local TraceRenderer = {}
TraceRenderer.__index = TraceRenderer

local COLORS = {
	Step = Color3.fromRGB(168, 196, 255),
	SprintStep = Color3.fromRGB(255, 168, 108),
	Jump = Color3.fromRGB(130, 180, 255),
	Land = Color3.fromRGB(150, 200, 255),
	Pickup = Color3.fromRGB(255, 208, 120),
	Tag = Color3.fromRGB(255, 96, 96),
	Own = Color3.fromRGB(120, 255, 190),
}

function TraceRenderer.new()
	local folder = workspace:FindFirstChild("Traces")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Traces" -- クライアントで作るのでローカル専用 (他人には送られない)
		folder.Parent = workspace
	end
	return setmetatable({ folder = folder, foot = 1 }, TraceRenderer)
end

local function dustEmitter(color: Color3, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.85
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new(0.4, 1.4)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3 * size),
		NumberSequenceKeypoint.new(1, 1.6 * size),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	return emitter
end

-- 足跡: 進行方向を向いた細長い痕 + 舞い上がる砂埃
function TraceRenderer:_footprint(payload, spec, color: Color3)
	local position = Vector3.new(payload.x, 0.04, payload.z)
	local dir = Vector3.new(payload.dx or 0, 0, payload.dz or 0)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 0, 1)
	end
	dir = dir.Unit

	local part = Instance.new("Part")
	part.Name = "Footprint"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(0.7 * spec.size, 0.05, 1.5 * spec.size)
	part.Transparency = 0.25

	-- 左右の足を交互にずらして置く
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local offset = right * (if self.foot == 1 then 0.55 else -0.55)
	self.foot = 3 - self.foot
	part.CFrame = CFrame.lookAt(position + offset, position + offset + dir)
	part.Parent = self.folder

	local emitter = dustEmitter(color, spec.size)
	emitter.Parent = part
	emitter:Emit(5)

	TweenService:Create(part, TweenInfo.new(spec.life, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	Debris:AddItem(part, spec.life + 1.2)
end

-- 振動波紋: 地面を這うように広がる円盤 + 一瞬の明かり
function TraceRenderer:_ripple(payload, spec, color: Color3)
	local position = Vector3.new(payload.x, 0.12, payload.z)

	local part = Instance.new("Part")
	part.Name = "Ripple"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.55
	part.Size = Vector3.new(0.15, 2, 2)
	-- Cylinder は X 軸が高さ方向なので、Z 周りに90度回して床に寝かせる
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = self.folder

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2.5
	light.Range = math.min(60, spec.size)
	light.Shadows = false
	light.Parent = part

	local info = TweenInfo.new(spec.life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(part, info, {
		Size = Vector3.new(0.15, spec.size, spec.size),
		Transparency = 1,
	}):Play()
	TweenService:Create(light, info, { Brightness = 0 }):Play()
	Debris:AddItem(part, spec.life + 0.5)
end

-- サーバから届いた痕跡を1つ描く
function TraceRenderer:spawn(payload)
	local spec = Config.trace[payload.k]
	if not spec then
		return
	end
	local color = if payload.o then COLORS.Own else COLORS[payload.k] or COLORS.Step

	if payload.k == "Step" or payload.k == "SprintStep" then
		self:_footprint(payload, spec, color)
	else
		self:_ripple(payload, spec, color)
	end
end

return TraceRenderer
