-- ヒットストップとカメラシェイク。全部クライアントローカル。
--
-- ヒットストップ (0.05秒だけ画面を止める) は、格闘ゲームで「当たった」感を
-- 出す常套手段をそのまま持ち込んだもの。Roblox にはタイムスケールが無いので、
-- 「その瞬間のカメラ CFrame を保持し続ける」ことで代用する。世界は動き続けて
-- いるのに視点だけ止まるので、打撃の瞬間だけ時間が詰まったように見える。
--
-- シェイクは trauma 方式 (Jan Kaluza の GDC 講演で有名になったやり方)。
-- 揺れの強さを trauma^2 に比例させると、小さい揺れは静かで、大きい揺れだけが
-- 派手になる。ランダム値ではなく math.noise を使うのは、乱数だと1フレームごとに
-- 飛んで「震え」ではなく「ちらつき」に見えるため。
--
-- 割り込む優先度は RenderPriority.Camera + 1。既定のカメラスクリプトが
-- CFrame を決めた直後に、その結果へ揺れを上乗せする。

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("DominoCrash").Config)

local CameraEffects = {}
CameraEffects.__index = CameraEffects

local BIND_NAME = "DominoCrashCameraEffects"

function CameraEffects.new()
	return setmetatable({
		trauma = 0,
		clock = 0,
		freezeUntil = 0,
		frozenCFrame = nil :: CFrame?,
		fovOffset = 0,
		baseFov = nil :: number?,
	}, CameraEffects)
end

-- strength: 0..1。1 で最大の揺れ。
function CameraEffects:impact(strength: number, freeze: boolean?)
	self.trauma = math.clamp(self.trauma + strength, 0, 1)
	self.fovOffset = math.min(self.fovOffset + Config.juice.fovPunch * strength, Config.juice.fovPunch * 2)
	if freeze then
		self.freezeUntil = math.max(self.freezeUntil, self.clock + Config.juice.hitStop)
		self.frozenCFrame = nil -- 次のフレームで掴み直す
	end
end

function CameraEffects:_update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	self.clock += dt

	if self.baseFov == nil then
		self.baseFov = camera.FieldOfView
	end

	-- ヒットストップ: 止めている間は最初に掴んだ CFrame を返し続ける
	if self.clock < self.freezeUntil then
		if self.frozenCFrame == nil then
			self.frozenCFrame = camera.CFrame
		end
		camera.CFrame = self.frozenCFrame :: CFrame
	else
		self.frozenCFrame = nil
	end

	-- FOV パンチ
	self.fovOffset = math.max(self.fovOffset - self.fovOffset * Config.juice.fovRecover * dt, 0)
	camera.FieldOfView = (self.baseFov :: number) + self.fovOffset

	if self.trauma <= 0 then
		return
	end
	self.trauma = math.max(self.trauma - Config.juice.shakeDecay * dt, 0)

	-- shake は trauma の2乗。小さい揺れを静かに保つため
	local shake = self.trauma * self.trauma
	local t = self.clock * Config.juice.shakeFrequency
	local amplitude = Config.juice.shakeAmplitude * shake
	local angle = math.rad(Config.juice.shakeAngle) * shake

	local offset = Vector3.new(
		math.noise(t, 0, 0) * amplitude,
		math.noise(0, t, 0) * amplitude,
		math.noise(0, 0, t) * amplitude * 0.5
	)
	local twist =
		CFrame.Angles(math.noise(t, 11.3, 0) * angle, math.noise(0, t, 7.1) * angle, math.noise(3.7, 0, t) * angle)
	camera.CFrame = camera.CFrame * CFrame.new(offset) * twist
end

function CameraEffects:start()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_update(dt)
	end)
end

function CameraEffects:stop()
	RunService:UnbindFromRenderStep(BIND_NAME)
end

return CameraEffects
