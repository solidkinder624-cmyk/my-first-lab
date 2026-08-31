-- 「痕跡だけの迷路 (Trace Only)」サーバ側エントリポイント。
--
-- 重要: Players.CharacterAutoLoads = false にして、キャラクターモデルを
-- そもそも Workspace に置かない。Roblox は Workspace の中身を全員に
-- レプリケートするため、「透明にしただけ」ではクライアント側から
-- 座標を読めてしまう。位置をサーバのメモリ上のデータとしてだけ持ち、
-- 外へ出すのは痕跡 (Trace) だけ、という構造にしている。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

-- StreamingEnabled は通常「プレイヤーのキャラクターの周囲」を基準に配信範囲を
-- 決める。このゲームはキャラクターを一切生成しないため、有効なままだと
-- 基準点を失って迷路のパーツが誰にも配信されず、クライアントには何も
-- 見えなくなる(真っ暗な空間だけが見える)。マップも小さいので不要なオフにする。
print(string.format("[TraceOnly] StreamingEnabled was %s, forcing off", tostring(workspace.StreamingEnabled)))
workspace.StreamingEnabled = false

local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Net = require(Shared.Net)

local PlayerRegistry = require(script.PlayerRegistry)
local MapBuilder = require(script.MapBuilder)
local TraceService = require(script.TraceService)
local SimulationService = require(script.SimulationService)
local RoundService = require(script.RoundService)

local remotes = Net.server()
local registry = PlayerRegistry.new()
local traces = TraceService.new(registry, remotes)
local sim = SimulationService.new(registry, remotes, traces)
local round = RoundService.new(registry, remotes, sim, traces)

-- イベント接続とゲームループの起動を先に済ませる。マップ生成や照明設定
-- (下の applyLighting/ensureMap) で万一エラーが起きても、プレイヤーの
-- 接続やハートビートまで巻き添えで止まらないようにするため。
Players.PlayerAdded:Connect(function(player)
	registry:add(player)
end)

-- スクリプトの実行開始前に参加していたプレイヤー (Studio のテスト起動など) を拾う
for _, player in Players:GetPlayers() do
	if not registry:get(player) then
		registry:add(player)
	end
end

Players.PlayerRemoving:Connect(function(player)
	registry:remove(player)
end)

-- クライアントの準備完了。ここで初めてシミュレーション対象に入る。
remotes.Ready.OnServerEvent:Connect(function(player)
	local entry = registry:get(player) or registry:add(player)
	if entry.ready then
		return
	end
	entry.ready = true
	round:playerJoined(entry)
end)

remotes.Input.OnServerEvent:Connect(function(player, packet)
	sim:onInput(player, packet)
end)

RunService.Heartbeat:Connect(function(dt)
	sim:advance(dt)
	round:update(dt)
end)

MapBuilder.applyLighting()
round:ensureMap()
