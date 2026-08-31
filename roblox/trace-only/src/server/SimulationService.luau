-- 固定タイムステップのサーバ権威シミュレーション。
--
-- 設計の要点:
--   ・dt はサーバが決める (クライアントの申告を一切使わない)
--   ・1 tick で消化する入力は最大 maxCatchUpPerTick 個
--     → 入力を大量に送りつけても、進める距離に上限が掛かる (速度ハック対策)
--   ・入力が途切れたら数tickだけ直前の入力を継続し、その後停止する
--     (パケットロスでのカクつきと、放置での無限前進の折衷)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Motion = require(Shared.Motion)

local SimulationService = {}
SimulationService.__index = SimulationService

local TICK = 1 / Config.net.tickRate
local MAX_STARVED_REPEAT = 3

function SimulationService.new(registry, remotes, traces)
	local self = setmetatable({
		registry = registry,
		remotes = remotes,
		traces = traces,
		grid = nil,
		accumulator = 0,
		tickIndex = 0,
		onTraceHooks = {},
	}, SimulationService)
	return self
end

function SimulationService:setGrid(grid)
	self.grid = grid
end

-- 受信した入力をバッファへ積む。ここでは一切シミュレートしない。
function SimulationService:onInput(player: Player, packet: any)
	local entry = self.registry:get(player)
	if not entry then
		return
	end
	-- バッファ上限。溢れる = 送りすぎなので黙って捨てる (エラーを返すと攻撃者に情報を与える)
	if #entry.inputs >= Config.net.maxInputBuffer then
		table.remove(entry.inputs, 1)
	end
	table.insert(entry.inputs, Motion.sanitize(packet, Config))
end

-- 痕跡が発生したときに追加で呼びたい処理 (モード側のフック)
function SimulationService:onTrace(callback)
	table.insert(self.onTraceHooks, callback)
end

function SimulationService:_stepEntry(entry, dt: number)
	local consumed = 0
	local budget = math.min(#entry.inputs, Config.net.maxCatchUpPerTick)

	if budget == 0 then
		-- 入力が来ていない: 直前の入力を少しだけ継続する
		entry.starvedTicks += 1
		local input
		if entry.starvedTicks > MAX_STARVED_REPEAT then
			input = Motion.emptyInput()
		else
			input = table.clone(entry.lastInput)
			input.jump = false -- ジャンプの連打だけは絶対に継続させない
		end
		-- 補間で作った入力でも seq は最後に受理した値のまま進める。
		-- ここを 0 に戻すと、クライアントが「まだ未確定」と誤認して
		-- 確定済みの入力を再適用し、リコンサイルが暴れる。
		input.seq = entry.state.lastSeq
		self:_apply(entry, input, dt)
		return
	end

	entry.starvedTicks = 0
	while consumed < budget do
		local input = table.remove(entry.inputs, 1)
		consumed += 1
		entry.lastInput = input
		self:_apply(entry, input, dt)
	end
end

function SimulationService:_apply(entry, input, dt: number)
	if entry.frozen or not entry.active then
		-- 停止中でも重力とスタミナ回復だけは進めたいので、入力を空にして通す。
		-- seq は保持する (クライアント側の確定判定に使われるため)。
		local blocked = Motion.emptyInput()
		blocked.seq = input.seq
		input = blocked
	end
	local traces = Motion.step(entry.state, input, dt, self.grid, Config)
	for _, trace in traces do
		self.traces:emit(entry, trace)
		for _, hook in self.onTraceHooks do
			hook(entry, trace)
		end
	end
end

-- Heartbeat から呼ぶ。固定ステップに刻んで消化する。
function SimulationService:advance(deltaTime: number)
	if not self.grid then
		return
	end
	self.accumulator = math.min(self.accumulator + deltaTime, TICK * 5) -- ラグ後の一気進みを防ぐ
	while self.accumulator >= TICK do
		self.accumulator -= TICK
		self.tickIndex += 1
		for _, entry in self.registry:all() do
			if entry.ready then
				self:_stepEntry(entry, TICK)
			end
		end
		self:_maybeReconcile()
	end
end

-- 本人にだけ権威座標を返す。他人の座標は誰にも送らない。
function SimulationService:_maybeReconcile()
	local every = math.max(1, math.floor(Config.net.tickRate / Config.net.reconcileRate))
	if self.tickIndex % every ~= 0 then
		return
	end
	for _, entry in self.registry:all() do
		if entry.ready then
			self.remotes.Reconcile:FireClient(entry.player, Motion.snapshot(entry.state))
		end
	end
end

-- スポーン (ラウンド開始時にモードから呼ばれる)
function SimulationService:placeAt(entry, x: number, z: number)
	entry.state = Motion.newState(x, z, Config)
	entry.inputs = {}
	entry.lastInput = Motion.emptyInput()
	self.remotes.Reconcile:FireClient(entry.player, Motion.snapshot(entry.state))
end

return SimulationService
