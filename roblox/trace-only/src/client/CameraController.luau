-- 一人称カメラ。キャラクターモデルが存在しないので、カメラ自体が
-- プレイヤーの「体」になる (CameraType を Scriptable にして毎フレーム置く)。

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)

local CameraController = {}
CameraController.__index = CameraController

local SENSITIVITY = 0.0022
local PITCH_LIMIT = math.rad(80)

function CameraController.new()
	local self = setmetatable({
		yaw = 0,
		pitch = 0,
		eyeHeight = Config.player.eyeHeight,
	}, CameraController)

	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		self.yaw -= input.Delta.X * SENSITIVITY
		self.pitch = math.clamp(self.pitch - input.Delta.Y * SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	end)

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 78
	return self
end

function CameraController:cframe(): CFrame
	return CFrame.fromEulerAnglesYXZ(self.pitch, self.yaw, 0)
end

function CameraController:update(position: Vector3, stance: string, dt: number)
	-- しゃがみで視点を下げる。見た目のフィードバックが無いと
	-- 「今しゃがんでいるか」が分からなくなるため。
	local target = if stance == "Crouch" then Config.player.crouchEyeHeight else Config.player.eyeHeight
	self.eyeHeight += (target - self.eyeHeight) * math.min(1, dt * 12)

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(position + Vector3.new(0, self.eyeHeight, 0)) * self:cframe()

	if not GuiService.MenuIsOpen then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

return CameraController
