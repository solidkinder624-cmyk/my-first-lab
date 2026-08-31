-- ハンマーの入力・振りのモーション・当たり判定 (クライアント側)。
--
-- ここでやるのは「サーバに何を叩いたかを伝えること」と「叩いた気持ちよさを
-- その場で出すこと」の2つだけ。何が壊れるかはサーバが決めるので、
-- このスクリプトを改造しても壊せる範囲は1ミリも増えない。
--
-- ただし演出はサーバの返事を待たない。返事を待つと、回線の往復ぶん
-- (体感で 60〜150ms) 打撃が遅れて、それだけで手応えが消える。
-- 「振り・カメラ揺れ・粉塵」は即座にローカルで出し、実際に崩れるのは
-- サーバから OnStructureExplode が返ってきたときにする。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("DominoCrash").Config)

local HammerController = {}
HammerController.__index = HammerController

local player = Players.LocalPlayer

function HammerController.new(remotes, effects, camera)
	local self = setmetatable({
		remotes = remotes,
		effects = effects,
		camera = camera,
		lastSwing = -math.huge,
		swingStart = -math.huge,
		tool = nil :: Tool?,
		baseGrip = nil :: CFrame?,
		enabled = false,
	}, HammerController)
	return self
end

function HammerController:setEnabled(enabled: boolean)
	self.enabled = enabled
end

-- 装備されたハンマーを掴まえて、振りのモーション用に初期姿勢を控えておく
function HammerController:_bindTool(tool: Tool)
	if not tool:IsA("Tool") or tool.Name ~= "Hammer" then
		return
	end
	self.tool = tool
	self.baseGrip = tool.Grip
	tool.Activated:Connect(function()
		self:swing()
	end)
	tool.Unequipped:Connect(function()
		if self.baseGrip then
			tool.Grip = self.baseGrip
		end
	end)
end

function HammerController:watchCharacter(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			self:_bindTool(child)
		end
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			self:_bindTool(child)
		end
	end)
end

-- 画面中央 (マウス位置) から reach 分のレイを飛ばす。
-- 崩れた破片は CanQuery = false になっているので、立っているブロックにしか当たらない。
function HammerController:_raycast(): RaycastResult?
	local currentCamera = Workspace.CurrentCamera
	local character = player.Character
	if not currentCamera or not character then
		return nil
	end

	local mouse = UserInputService:GetMouseLocation()
	local ray = currentCamera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	return Workspace:Raycast(ray.Origin, ray.Direction * Config.hammer.reach, params)
end

function HammerController:swing()
	if not self.enabled then
		return
	end
	local now = os.clock()
	if now - self.lastSwing < Config.hammer.cooldown then
		return -- サーバと同じクールダウンで先に弾く。無駄なパケットを出さない
	end
	self.lastSwing = now
	self.swingStart = now

	local result = self:_raycast()
	if not result then
		return -- 空振り。モーションだけ出して終わり
	end

	-- 演出はサーバの返事を待たずに即出す
	self.effects:swingSpark(result.Position, result.Normal)
	self.camera:impact(Config.juice.shakeTrauma * 0.35, true)

	self.remotes.RequestHit:FireServer(result.Instance, result.Position)
end

-- 振りかぶり → 振り下ろし。Animation アセットを使わず Tool.Grip を直接動かす。
-- Grip を触ると Roblox が RightGrip の Weld を追従させてくれる。
function HammerController:_animate()
	local tool = self.tool
	local base = self.baseGrip
	if not tool or not base or not tool.Parent then
		return
	end

	local elapsed = os.clock() - self.swingStart
	local duration = Config.hammer.swingTime
	if elapsed > duration * 2 then
		tool.Grip = base
		return
	end

	local phase: number
	if elapsed < duration then
		phase = -(elapsed / duration) * 0.9 -- 振りかぶり (ゆっくり)
	else
		local t = (elapsed - duration) / duration
		phase = -0.9 + t * t * 2.4 -- 振り下ろし (加速する)
	end
	tool.Grip = base * CFrame.Angles(phase, 0, 0)
end

function HammerController:start()
	local character = player.Character
	if character then
		self:watchCharacter(character)
	end
	player.CharacterAdded:Connect(function(added)
		self.tool = nil
		self:watchCharacter(added)
	end)

	-- モバイル/タッチでも撃てるように、Tool.Activated 以外の経路も拾う。
	-- Activated と二重に発火することがあるが、swing() のクールダウン判定が
	-- 同一フレームの2発目を落とすので実害はない。
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self.enabled then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if self.tool and self.tool.Parent == player.Character then
				self:swing()
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		self:_animate()
	end)
end

return HammerController
