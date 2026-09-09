-- 追従カメラ。△ (ButtonY) / キーボードの C でチェイス視点とコックピット視点を切り替える。

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CHASE_OFFSET = CFrame.new(0, 6, 24) -- 機体後方・やや上から
local COCKPIT_OFFSET = CFrame.new(0, 1.5, -4)

local BIND_NAME = "SkyCarrierCamera"
-- 既定のカメラスクリプトは Enum.RenderPriority.Camera で毎フレーム
-- CameraType を Custom に戻してくる。start() で一度 Scriptable にするだけでは
-- 次のフレームで即座に上書きされてしまう(=機体を映せない)ので、それより
-- 後の優先度で毎フレーム Scriptable を再宣言し続けて確実に勝つ。
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

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
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			local isGamepadToggle = input.UserInputType == Enum.UserInputType.Gamepad1
				and input.KeyCode == Enum.KeyCode.ButtonY
			local isKeyboardToggle = not gameProcessed
				and input.UserInputType == Enum.UserInputType.Keyboard
				and input.KeyCode == Enum.KeyCode.C
			if isGamepadToggle or isKeyboardToggle then
				self.mode = if self.mode == "Chase" then "Cockpit" else "Chase"
			end
		end)
	)

	RunService:BindToRenderStep(BIND_NAME, RENDER_PRIORITY, function()
		camera.CameraType = Enum.CameraType.Scriptable -- 既定スクリプトの上書きに毎フレーム勝つ
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
end

function CameraController:stop()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}
	pcall(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end)
end

return CameraController
