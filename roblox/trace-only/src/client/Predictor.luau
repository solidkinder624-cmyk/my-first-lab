-- クライアント側の移動予測 (client-side prediction + reconciliation)。
--
-- サーバとまったく同じ Motion.luau / Grid.luau を実行するのがポイント。
-- 入力を送ってから権威座標が返るまで待つと 100ms 単位で操作が遅れるので、
-- 手元では即座に動かし、サーバのスナップショットが届いたら
-- 「その時点まで巻き戻して、未確定の入力を再適用する」ことでズレを畳む。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Motion = require(Shared.Motion)

local Predictor = {}
Predictor.__index = Predictor

function Predictor.new()
	return setmetatable({
		state = Motion.newState(0, 0, Config),
		pending = {}, -- サーバがまだ確定していない入力
		grid = nil,
		seq = 0,
		prevX = 0,
		prevZ = 0,
		prevY = 0,
	}, Predictor)
end

function Predictor:setGrid(grid)
	self.grid = grid
end

function Predictor:nextSeq(): number
	self.seq += 1
	return self.seq
end

-- 1tick ぶんの予測。予測中に発生する痕跡は捨てる:
-- 表示するのはサーバが承認して返してきた痕跡だけ、という一本化のため
-- (予測と権威で二重に足跡が出るのを防ぐ)。
function Predictor:step(input, dt: number)
	if not self.grid then
		return
	end
	self.prevX, self.prevZ, self.prevY = self.state.x, self.state.z, self.state.y
	Motion.step(self.state, input, dt, self.grid, Config)
	table.insert(self.pending, input)
	if #self.pending > 120 then -- 通信が死んでいるとき用の安全弁
		table.remove(self.pending, 1)
	end
end

-- サーバの権威スナップショットで巻き戻し、未確定入力を再適用する
function Predictor:reconcile(snapshot, dt: number)
	if not self.grid then
		Motion.applySnapshot(self.state, snapshot)
		return
	end
	Motion.applySnapshot(self.state, snapshot)
	while #self.pending > 0 and self.pending[1].seq <= snapshot.seq do
		table.remove(self.pending, 1)
	end
	for _, input in self.pending do
		Motion.step(self.state, input, dt, self.grid, Config)
	end
end

-- 描画用。tick(30Hz) と描画(60fps+) の差を補間して滑らかに見せる。
function Predictor:renderPosition(alpha: number): Vector3
	local a = math.clamp(alpha, 0, 1)
	return Vector3.new(
		self.prevX + (self.state.x - self.prevX) * a,
		self.prevY + (self.state.y - self.prevY) * a,
		self.prevZ + (self.state.z - self.prevZ) * a
	)
end

return Predictor
