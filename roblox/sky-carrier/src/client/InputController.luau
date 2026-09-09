-- DualShock4 (Gamepad1) とキーボードの両方をポーリングし、FlightModel.Input の
-- 形に変換してサーバへ送る。設計図はガンパッド専用だが、Studio でのテストや
-- コントローラを持たないプレイヤーのために、キーボードでも同じ操作を一通り
-- できるようにしてある(両方同時に繋いでいても干渉しないよう単純に加算する)。
--
-- 02/操作系統のとおり:
--   左スティック  … ロール(左右) / ピッチ(上下)     … キーボード: A/D ロール, W/S ピッチ
--   右スティック  … ヨー(左右)     ※視点(上下)は CameraController が扱う  … キーボード: Q/E ヨー
--   R2 / L2       … スロットル増加 / 減速            … キーボード: ↑/↓ (または Shift/Ctrl)
--   L1 / R1       … フラップ上げ/下げ (このMVPでは未実装。turnRate には影響しない)
--   ×             … 加速ブースト                     … キーボード: Space
--   ○             … 着陸装置トグル                   … キーボード: G
--   □             … 荷物投下 / 決定 (MissionController が処理) … キーボード: F

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("SkyCarrier").Config)

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

	-- キーボードは全部デジタル入力(押した/離した)なので、-1/0/1 の3値だけ持つ。
	local keyState = {
		roll = 0, -- A/D
		pitch = 0, -- W/S (Wで機首上げ)
		yaw = 0, -- Q/E
		throttle = 0, -- ↑/↓
		boost = false, -- Space
		gear = false, -- G
	}
	local heldKeys = {} -- KeyCode → true。複数キー(例:AとD同時)の解決に使う

	local function axisFromKeys(negative: Enum.KeyCode, positive: Enum.KeyCode): number
		local v = 0
		if heldKeys[positive] then
			v += 1
		end
		if heldKeys[negative] then
			v -= 1
		end
		return v
	end

	local function refreshKeyState()
		keyState.roll = axisFromKeys(Enum.KeyCode.A, Enum.KeyCode.D)
		keyState.pitch = axisFromKeys(Enum.KeyCode.S, Enum.KeyCode.W)
		keyState.yaw = axisFromKeys(Enum.KeyCode.Q, Enum.KeyCode.E)
		keyState.throttle = axisFromKeys(Enum.KeyCode.Down, Enum.KeyCode.Up)
		keyState.boost = heldKeys[Enum.KeyCode.Space] == true
		keyState.gear = heldKeys[Enum.KeyCode.G] == true
	end

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
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if input.UserInputType == Enum.UserInputType.Gamepad1 then
				if input.KeyCode == Enum.KeyCode.ButtonA then
					gamepadState.ButtonA = true
				elseif input.KeyCode == Enum.KeyCode.ButtonB then
					gamepadState.ButtonB = true
				elseif input.KeyCode == Enum.KeyCode.ButtonX and self.onDropPressed then
					self.onDropPressed()
				end
				return
			end
			if input.UserInputType ~= Enum.UserInputType.Keyboard or gameProcessed then
				return
			end
			heldKeys[input.KeyCode] = true
			if input.KeyCode == Enum.KeyCode.F and self.onDropPressed then
				self.onDropPressed()
			end
			refreshKeyState()
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Gamepad1 then
				if input.KeyCode == Enum.KeyCode.ButtonA then
					gamepadState.ButtonA = false
				elseif input.KeyCode == Enum.KeyCode.ButtonB then
					gamepadState.ButtonB = false
				end
				return
			end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			heldKeys[input.KeyCode] = nil
			refreshKeyState()
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
			local gearPressed = gamepadState.ButtonB or keyState.gear
			local gearToggle = gearPressed and not self.prevGearButton
			self.prevGearButton = gearPressed
			if gearToggle and self.onGearToggle then
				self.onGearToggle(true)
			end

			self.seq += 1
			local builtInput = {
				seq = self.seq,
				rollStick = math.clamp(applyDeadzone(gamepadState.Thumbstick1.X, deadzone) + keyState.roll, -1, 1),
				pitchStick = math.clamp(applyDeadzone(gamepadState.Thumbstick1.Y, deadzone) + keyState.pitch, -1, 1),
				yawStick = math.clamp(applyDeadzone(gamepadState.Thumbstick2.X, deadzone) + keyState.yaw, -1, 1),
				throttleInput = math.clamp((gamepadState.ButtonR2 - gamepadState.ButtonL2) + keyState.throttle, -1, 1),
				boost = gamepadState.ButtonA or keyState.boost,
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
