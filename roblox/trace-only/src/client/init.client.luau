-- クライアント側エントリポイント。
--
-- このクライアントが持っている他プレイヤーの情報は、サーバから届いた
-- 痕跡パケット (座標と種類だけ・誰のものかは不明) が全て。
-- 迷路の形だけは seed から自前で再生成し、移動予測の当たり判定に使う。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)

local Predictor = require(script.Predictor)
local InputController = require(script.InputController)
local CameraController = require(script.CameraController)
local TraceRenderer = require(script.TraceRenderer)
local Hud = require(script.Hud)

local TICK = 1 / Config.net.tickRate

-- Roblox 標準のカメラ/移動コントロールを止める。CharacterAutoLoads=false でも
-- このデフォルトスクリプト自体は動き続けており、毎フレーム
-- workspace.CurrentCamera を自分の判断で書き換えてしまうことがあるため、
-- 自前の CameraController(Scriptable) と競合しないよう明示的に無効化する。
do
	local localPlayer = Players.LocalPlayer
	local playerScripts = localPlayer:WaitForChild("PlayerScripts")
	local ok, playerModule = pcall(function()
		return require(playerScripts:WaitForChild("PlayerModule", 5))
	end)
	if ok and playerModule then
		pcall(function()
			playerModule:GetControls():Disable()
		end)
		pcall(function()
			playerModule:GetCameraModule():SetCameraMovementMode(Enum.CameraMovementMode.Classic)
		end)
	else
		warn("[TraceOnly] PlayerModule を無効化できませんでした:", playerModule)
	end
end

local remotes = Net.client()
local predictor = Predictor.new()
local camera = CameraController.new()
local renderer = TraceRenderer.new()
local hud = Hud.new()

local accumulator = 0
local loggedFirstReconcile = false

-- ── サーバからの受信 ────────────────────────────────────
remotes.Round.OnClientEvent:Connect(function(payload)
	if payload.event == "Map" then
		-- 迷路そのものは秘密ではない。seed だけ受け取って同じものを再生成する。
		local grid = Grid.generate(payload.cellsW, payload.cellsH, payload.seed, payload.braid, Config.tileSize)
		predictor:setGrid(grid)
		print(string.format(
			"[TraceOnly] client grid: %dx%d tiles = %.0fx%.0f studs, seed=%d",
			grid.w,
			grid.h,
			grid.w * grid.tileSize,
			grid.h * grid.tileSize,
			payload.seed
		))
	elseif payload.event == "State" then
		hud:applyState(payload)
	end
end)

remotes.Reconcile.OnClientEvent:Connect(function(snapshot)
	predictor:reconcile(snapshot, TICK)
	if not loggedFirstReconcile then
		loggedFirstReconcile = true
		print(string.format("[TraceOnly] first reconcile at (%.1f, %.1f, %.1f)", snapshot.x, snapshot.y, snapshot.z))
	end
end)

remotes.Trace.OnClientEvent:Connect(function(payload)
	renderer:spawn(payload)
end)

remotes.Ready:FireServer()

-- ── 送信 + 予測 (固定30Hz) ──────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	accumulator += math.min(dt, TICK * 5)
	while accumulator >= TICK do
		accumulator -= TICK
		local input = InputController.gather(camera:cframe(), predictor:nextSeq())
		predictor:step(input, TICK)
		remotes.Input:FireServer(input)
	end
end)

-- ── 描画 (フレームレートに合わせて補間) ────────────────
local lastDiagLog = 0
RunService:BindToRenderStep("TraceOnlyCamera", Enum.RenderPriority.Camera.Value, function(dt)
	local position = predictor:renderPosition(accumulator / TICK)
	camera:update(position, predictor.state.stance, dt)
	hud:applyLocal(predictor.state)

	-- 診断用: 実際にレンダリングされているカメラの位置が、こちらが計算した
	-- 位置と一致しているかを1.5秒おきに確認する (何かが横からカメラを
	-- 上書きしていないかを見るため)
	lastDiagLog += dt
	if lastDiagLog >= 1.5 then
		lastDiagLog = 0
		local cam = workspace.CurrentCamera
		print(string.format(
			"[TraceOnly] camera actual=(%.1f,%.1f,%.1f) type=%s | predictor=(%.1f,%.1f,%.1f)",
			cam.CFrame.Position.X,
			cam.CFrame.Position.Y,
			cam.CFrame.Position.Z,
			tostring(cam.CameraType),
			position.X,
			position.Y,
			position.Z
		))

		-- 診断用: ジオメトリが本当にクライアント側の Workspace に存在し、
		-- 見える設定になっているかを直接確認する。
		local maze = workspace:FindFirstChild("Maze")
		if not maze then
			print("[TraceOnly] Workspace に Maze フォルダが見つかりません")
		else
			local nearest, nearestDist = nil, math.huge
			for _, part in maze:GetChildren() do
				if part:IsA("BasePart") and part.Name:match("^Wall") then
					local d = (part.Position - position).Magnitude
					if d < nearestDist then
						nearest, nearestDist = part, d
					end
				end
			end
			if nearest then
				print(string.format(
					"[TraceOnly] Maze children=%d, nearest %s dist=%.1f Transparency=%.2f Size=(%.1f,%.1f,%.1f) Parent=%s",
					#maze:GetChildren(),
					nearest.Name,
					nearestDist,
					nearest.Transparency,
					nearest.Size.X,
					nearest.Size.Y,
					nearest.Size.Z,
					tostring(nearest.Parent and nearest.Parent.Name)
				))
			else
				print(string.format("[TraceOnly] Maze children=%d だが Wall が1つも見つかりません", #maze:GetChildren()))
			end
		end
	end
end)

-- キャラクターが存在しない構成なので、Roblox 既定の
-- 「リセット」による再スポーンは意味がない。念のため無効化しておく。
local StarterGui = game:GetService("StarterGui")
task.defer(function()
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)
end)

print("[TraceOnly] クライアント起動: ", Players.LocalPlayer.DisplayName)
