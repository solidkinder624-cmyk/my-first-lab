-- すべての恐竜（野生・飼育）をまとめて動かす、ただ1つの更新ループ。
--
-- 性能の方針（CLAUDE.md 5章: 拠点に恐竜30頭が同時にいても重くしない）:
--   ・恐竜ごとのスクリプト / while ループは作らない。Heartbeat 1本で、
--     DinoConfig.Ranch.AIUpdateInterval 秒ごとに全頭をまとめて更新する（毎フレームは動かさない）。
--   ・モデルは PrimaryPart だけ Anchored（他は溶接）。物理演算・Humanoid・PathfindingService は使わない。
--   ・高さは RanchWorld.getGroundHeight（計算だけ）で決める。レイキャストしない。
--   ・動いた恐竜の PrimaryPart を workspace:BulkMoveTo で1回にまとめて動かす。
--   ・見た目用の属性 "State" は状態が変わったときだけ書き換える（毎回は送らない）。
--   ※サーバーの更新は AIUpdateInterval ごと（初期値 0.25 秒）なので、なめらかに見せる補間・歩行アニメは
--     クライアント側の演出で行う（依頼事項。モデルの属性 "State" / "Species" / "GroundOffset" を使える）。
--
-- 計算そのもの（目的地選び・1歩の計算）は WanderLogic（純ロジック）が行う。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DinoConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DinoConfig"))
local RanchWorld = require(workspace:WaitForChild("Ranch"):WaitForChild("RanchWorld"))
local WanderLogic = require(script.Parent:WaitForChild("WanderLogic"))

local DinoMover = {}

-- 属性 "State" の値（クライアントの演出用）
DinoMover.States = {
	Idle = "Idle", -- 立ち止まっている
	Walking = "Walking", -- 歩いている
	Taming = "Taming", -- テイム中で止まっている
}

export type Entry = {
	Key: string,
	Model: Model,
	Root: BasePart,
	Agent: WanderLogic.Agent,
	Env: WanderLogic.Env,
	GroundOffset: number,
	State: string,
}

local entries: { [string]: Entry } = {}
local rng = Random.new()
local started = false

local function makeCFrame(entry: Entry): CFrame
	local agent = entry.Agent
	local y = RanchWorld.getGroundHeight(agent.X, agent.Z) + entry.GroundOffset
	return CFrame.new(agent.X, y, agent.Z) * CFrame.Angles(0, agent.Yaw, 0)
end

local function stateOf(agent: WanderLogic.Agent): string
	if agent.Frozen then
		return DinoMover.States.Taming
	elseif agent.Moving then
		return DinoMover.States.Walking
	end
	return DinoMover.States.Idle
end

local function refreshState(entry: Entry)
	local state = stateOf(entry.Agent)
	if state ~= entry.State then
		entry.State = state
		entry.Model:SetAttribute("State", state)
	end
end

-- 恐竜を登録してワールドに置く。key は野生・飼育で重ならない文字列（例 "W:<DinoId>"）
function DinoMover.add(
	key: string,
	model: Model,
	agent: WanderLogic.Agent,
	env: WanderLogic.Env,
	groundOffset: number,
	parent: Instance
): Entry
	assert(entries[key] == nil, "DinoMover: 同じキーの恐竜がすでにいます: " .. key)
	local root = model.PrimaryPart
	assert(root, "DinoMover: PrimaryPart がありません: " .. model.Name)
	local entry: Entry = {
		Key = key,
		Model = model,
		Root = root,
		Agent = agent,
		Env = env,
		GroundOffset = groundOffset,
		State = "",
	}
	-- Parent 前なので PivotTo で全パーツをまとめて置く（溶接はワールドに入ってから効くため）
	model:PivotTo(makeCFrame(entry) * root.PivotOffset)
	refreshState(entry)
	model.Parent = parent
	entries[key] = entry
	return entry
end

-- 登録を外してモデルを消す。戻り値: 登録されていたか
function DinoMover.remove(key: string): boolean
	local entry = entries[key]
	if not entry then
		return false
	end
	entries[key] = nil
	entry.Model:Destroy()
	return true
end

function DinoMover.get(key: string): Entry?
	return entries[key]
end

-- テイム中などで止める / 再開する
function DinoMover.setFrozen(key: string, frozen: boolean): boolean
	local entry = entries[key]
	if not entry then
		return false
	end
	entry.Agent.Frozen = frozen
	if frozen then
		entry.Agent.Moving = false
	end
	refreshState(entry)
	return true
end

-- 今の位置（地面の高さ + GroundOffset）。登録されていなければ nil
function DinoMover.getPosition(key: string): Vector3?
	local entry = entries[key]
	return if entry then entry.Root.Position else nil
end

function DinoMover.count(): number
	local n = 0
	for _ in entries do
		n += 1
	end
	return n
end

-- 全頭を1回更新する
local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local function updateAll(dt: number)
	local now = os.clock()
	local n = 0
	for key, entry in entries do
		if entry.Model.Parent == nil then
			-- 外から Destroy / 取り外しされた。動かさない（登録の後始末は各管理側が Destroying で行う）
			continue
		end
		local moved = WanderLogic.advance(entry.Agent, entry.Env, dt, now, rng)
		if moved then
			n += 1
			parts[n] = entry.Root
			cframes[n] = makeCFrame(entry)
		end
		refreshState(entry)
	end
	-- 前回の余りを切り詰める（消えた恐竜のパーツを持ち続けないように）
	for i = #parts, n + 1, -1 do
		parts[i] = nil
		cframes[i] = nil
	end
	if n > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function DinoMover.start()
	if started then
		return
	end
	started = true
	local interval = DinoConfig.Ranch.AIUpdateInterval
	local accumulated = 0
	RunService.Heartbeat:Connect(function(frameDt: number)
		accumulated += frameDt
		if accumulated < interval then
			return
		end
		-- サーバーが重くて間隔が空いても、1回で大きく飛ばない（ワープで水・柵を越えないように）
		local dt = math.min(accumulated, interval)
		accumulated = 0
		updateAll(dt)
	end)
end

return DinoMover
