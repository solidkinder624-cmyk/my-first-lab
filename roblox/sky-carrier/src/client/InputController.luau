-- DualShock4 (Gamepad1) をポーリングし、FlightModel.Input の形に変換してサーバへ送る。
--
-- 02/操作系統のとおり:
--   左スティック  … ロール(左右) / ピッチ(上下)
--   右スティック  … ヨー(左右)     ※視点(上下)は CameraController が扱う
--   R2 / L2       … スロットル増加 / 減速
--   L1 / R1       … フラップ上げ/下げ (このMVPでは未実装。turnRate には影響しない)
--   ×             … 加速ブースト
--   ○             … 着陸装置トグル
--   □             … 荷物投下 / 決定 (MissionController が処理)

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Shared.Config)

local InputController = {}
InputController.__index = InputController

local function applyDeadzone(v: number, deadzone: number): number
	if math.abs(v) < deadzone then
		return 0
	end
	return v
end

function InputController.new(remotes)
	local self = setmetatable({
		remotes = remotes,
		seq = 0,
		enabled = false,
		lastSend = 0,
		prevGearButton = false,
		connections = {},
		onGearToggle = nil :: ((boolean) -> ())?,
		onDropPressed = nil :: (() -> ())?,
		onInput = nil :: ((any) -> ())?, -- 送信するたびに、組み立てた入力テーブルを渡す
	}, InputController)
	return self
end

function InputController:setEnabled(enabled: boolean)
	self.enabled = enabled
end

function InputController:start()
	local gamepadState = {
		Thumbstick1 = Vector3.new(),
		Thumbstick2 = Vector3.new(),
		ButtonR2 = 0,
		ButtonL2 = 0,
		ButtonA = false,
		ButtonB = false,
	}

	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
				return
			end
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				gamepadState.Thumbstick1 = input.Position
			elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
				gamepadState.Thumbstick2 = input.Position
			elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
				gamepadState.ButtonR2 = input.Position.Z
			elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
				gamepadState.ButtonL2 = input.Position.Z
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
				return
			end
			if input.KeyCode == Enum.KeyCode.ButtonA then
				gamepadState.ButtonA = true
			elseif input.KeyCode == Enum.KeyCode.ButtonB then
				gamepadState.ButtonB = true
			elseif input.KeyCode == Enum.KeyCode.ButtonX and self.onDropPressed then
				self.onDropPressed()
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
				return
			end
			if input.KeyCode == Enum.KeyCode.ButtonA then
				gamepadState.ButtonA = false
			elseif input.KeyCode == Enum.KeyCode.ButtonB then
				gamepadState.ButtonB = false
			end
		end)
	)

	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(_dt)
			if not self.enabled then
				return
			end
			local now = os.clock()
			if now - self.lastSend < 1 / Config.gamepad.inputHz then
				return
			end
			self.lastSend = now

			local deadzone = Config.gamepad.stickDeadzone
			local gearPressed = gamepadState.ButtonB
			local gearToggle = gearPressed and not self.prevGearButton
			self.prevGearButton = gearPressed
			if gearToggle and self.onGearToggle then
				self.onGearToggle(true)
			end

			self.seq += 1
			local builtInput = {
				seq = self.seq,
				rollStick = applyDeadzone(gamepadState.Thumbstick1.X, deadzone),
				pitchStick = applyDeadzone(gamepadState.Thumbstick1.Y, deadzone),
				yawStick = applyDeadzone(gamepadState.Thumbstick2.X, deadzone),
				throttleInput = gamepadState.ButtonR2 - gamepadState.ButtonL2,
				boost = gamepadState.ButtonA,
				gearToggle = gearToggle,
			}
			self.remotes.UpdateFlightInput:FireServer(builtInput)
			if self.onInput then
				self.onInput(builtInput)
			end
		end)
	)
end

function InputController:stop()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}
end

return InputController
