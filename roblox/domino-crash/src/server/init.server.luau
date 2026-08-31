-- サーバ側エントリポイント。各サービスを組み立てて配線するだけ。
--
-- 権威の所在:
--   * 何が壊れるか   … Collapse (純ロジック) をサーバが実行して決める
--   * 崩壊率         … サーバが数える。クライアントは表示するだけ
--   * 破片の動き     … 持ち主のクライアントに任せる (物理負荷の分散)
--   * 演出           … 完全にクライアント側。サーバは「崩れた」事実だけ送る

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("DominoCrash")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local ArenaBuilder = require(script.ArenaBuilder)
local StructureManager = require(script.StructureManager)
local HitValidation = require(script.HitValidation)
local ProgressTracker = require(script.ProgressTracker)
local GameManager = require(script.GameManager)

local remotes = Net.server()

local arena = ArenaBuilder.build(workspace)
local structures = StructureManager.new(remotes)
local validation = HitValidation.new()
local progress = ProgressTracker.new(structures, remotes)
local game_ = GameManager.new(structures, progress, remotes, arena)

-- ── 打撃 ────────────────────────────────────────────────
remotes.RequestHit.OnServerEvent:Connect(function(player, part, point)
	if game_.phase ~= "Playing" then
		return
	end
	local slotIndex = game_:slotFor(player)
	if not slotIndex then
		return
	end
	local live = structures:get(slotIndex)

	local ok, _reason, blockId = validation:validate(player, live, part, point, os.clock())
	if not ok or blockId == nil then
		-- 弾いた打撃には何も返さない。理由を返すと、改造クライアントに
		-- 「どこまでなら通るか」を総当たりで探らせる材料を与えてしまう。
		return
	end

	local result = structures:hit(live, point)

	-- 演出の材料だけを全員へ。座標と規模しか送らないので、
	-- 粉塵もカメラ揺れも各クライアントがローカルに生成できる。
	remotes.OnStructureExplode:FireAllClients({
		slot = slotIndex,
		position = point,
		keyHit = result.keyHit,
		direct = #result.direct,
		chain = #result.chain,
	})
end)

Players.PlayerRemoving:Connect(function(player)
	validation:forget(player)
end)

-- ── メインループ ────────────────────────────────────────
-- Heartbeat は物理ステップの後に走る。ここでアンカーを外すと、
-- その破片は次のステップから物理に乗る (同じフレーム内での二度手間がない)。
RunService.Heartbeat:Connect(function(dt)
	structures:step()
	if game_.phase == "Playing" or game_.phase == "Result" then
		progress:step(dt)
	end
end)

game_:start()

print(
	string.format(
		"[DominoCrash] サーバ起動: %d スロット / 制限時間 %d秒 / 構造物 %s",
		Config.match.maxPlayers,
		Config.match.duration,
		table.concat(Config.build.kinds, ", ")
	)
)
