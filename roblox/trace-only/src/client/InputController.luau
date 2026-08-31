-- 入力収集。送るのは「進みたい方向」であって座標ではない。
-- カメラ相対への変換はクライアントで行い、サーバは長さ<=1 のベクトルとして扱う
-- (Motion.sanitize が最終的に丸めるので、ここが壊れてもチートにはならない)。

local UserInputService = game:GetService("UserInputService")

local InputController = {}

local KEYS = {
	forward = { Enum.KeyCode.W, Enum.KeyCode.Up },
	back = { Enum.KeyCode.S, Enum.KeyCode.Down },
	left = { Enum.KeyCode.A, Enum.KeyCode.Left },
	right = { Enum.KeyCode.D, Enum.KeyCode.Right },
	jump = { Enum.KeyCode.Space },
	sprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
	crouch = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl, Enum.KeyCode.C },
}

local function isDown(list): boolean
	for _, key in list do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

-- camCFrame の向きを基準に、水平面上の進行方向を作る
function InputController.gather(camCFrame: CFrame, seq: number)
	local look = camCFrame.LookVector
	local right = camCFrame.RightVector
	local forwardX, forwardZ = look.X, look.Z
	local rightX, rightZ = right.X, right.Z

	local fLen = math.sqrt(forwardX * forwardX + forwardZ * forwardZ)
	if fLen > 1e-4 then
		forwardX, forwardZ = forwardX / fLen, forwardZ / fLen
	end
	local rLen = math.sqrt(rightX * rightX + rightZ * rightZ)
	if rLen > 1e-4 then
		rightX, rightZ = rightX / rLen, rightZ / rLen
	end

	local ax = (if isDown(KEYS.right) then 1 else 0) - (if isDown(KEYS.left) then 1 else 0)
	local az = (if isDown(KEYS.forward) then 1 else 0) - (if isDown(KEYS.back) then 1 else 0)

	local moveX = rightX * ax + forwardX * az
	local moveZ = rightZ * ax + forwardZ * az
	local len = math.sqrt(moveX * moveX + moveZ * moveZ)
	if len > 1 then
		moveX, moveZ = moveX / len, moveZ / len
	end

	return {
		seq = seq,
		moveX = moveX,
		moveZ = moveZ,
		jump = isDown(KEYS.jump),
		sprint = isDown(KEYS.sprint),
		crouch = isDown(KEYS.crouch),
	}
end

return InputController
