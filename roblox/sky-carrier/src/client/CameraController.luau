-- 追従カメラ。△ (ButtonY) でチェイス視点とコックピット視点を切り替える。

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CHASE_OFFSET = CFrame.new(0, 6, 24) -- 機体後方・やや上から
local COCKPIT_OFFSET = CFrame.new(0, 1.5, -4)

local CameraController = {}
CameraController.__index = CameraController

function CameraController.new(predictor)
	return setmetatable({
		predictor = predictor,
		mode = "Chase",
		connections = {},
	}, CameraController)
end

function CameraController:start()
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonY then
				self.mode = if self.mode == "Chase" then "Cockpit" else "Chase"
			end
		end)
	)

	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function()
			local state = self.predictor.state
			local body = CFrame.new(state.x, state.y, state.z)
				* CFrame.fromOrientation(math.rad(state.pitch), math.rad(state.yaw), math.rad(state.roll))
			local offset = if self.mode == "Chase" then CHASE_OFFSET else COCKPIT_OFFSET
			local desired = body * offset
			if self.mode == "Chase" then
				camera.CFrame = CFrame.new(desired.Position, body.Position)
			else
				camera.CFrame = desired
			end
		end)
	)
end

function CameraController:stop()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}
end

return CameraController
