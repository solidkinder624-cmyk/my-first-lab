-- 各プレイヤーの構造物の崩壊率を計算し、まとめてクライアントへ流す。
--
-- ブロックを毎フレーム走査したり、Touched を数千個に張ったりはしない。
-- 数えるのに必要な3つの数はすべてサーバが既に持っている:
--   total  … 生成時に確定する総ブロック数
--   fallen … StructureManager が破片を消すときに +1 した数
--   free   … アンカーが外れて、まだ落ちきっていない数 (freedCount - fallen)
-- 走査コストが乗るのは「いま動いている破片」だけで、その上限は
-- Config.physics.maxActiveParts で頭打ちにしてある。
--
-- 送信は Config.progress.interval (0.2秒) ごとに全員ぶんを1パケットで。
-- 毎フレーム送ると、4人 x 60fps = 240 パケット/秒 になって帯域が持たない。
--
-- 送るのは { slot, percent } だけに絞ってある。UnreliableRemoteEvent には
-- 1パケットのサイズ上限 (約900バイト) があり、名前などの文字列を毎回積むと
-- 人数が増えたときに黙って落ち始める。名前は MatchStateChanged が
-- フェーズ遷移のたびに送っているので、クライアントはそちらを引けばよい。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DominoCrash")
local Config = require(Shared.Config)
local Progress = require(Shared.Progress)

local ProgressTracker = {}
ProgressTracker.__index = ProgressTracker

function ProgressTracker.new(structures, remotes)
	return setmetatable({
		structures = structures,
		remotes = remotes,
		scores = {}, -- slotIndex → { percent, fallen, reachedAt, name, userId }
		accumulator = 0,
		elapsed = 0,
	}, ProgressTracker)
end

function ProgressTracker:reset()
	table.clear(self.scores)
	self.accumulator = 0
	self.elapsed = 0
end

function ProgressTracker:scoreFor(slotIndex: number)
	return self.scores[slotIndex]
end

function ProgressTracker:all()
	return self.scores
end

-- dt を溜めて interval ごとにだけ実際の集計を行う。
-- force = true で即時集計する (決着判定の直前など)。
function ProgressTracker:step(dt: number, force: boolean?): boolean
	self.elapsed += dt
	self.accumulator += dt
	if not force and self.accumulator < Config.progress.interval then
		return false
	end
	self.accumulator = 0

	self.structures:collect()

	local payload = {}
	for slotIndex, live in self.structures.live do
		local total, fallen, free = self.structures:counts(live)
		local percent = Progress.quantize(Progress.percent(total, fallen, free, Config.progress.freeWeight))
		local previous = self.scores[slotIndex]
		local reachedAt = if previous then previous.reachedAt else math.huge
		if percent >= Config.match.winPercent and reachedAt == math.huge then
			reachedAt = self.elapsed
		end

		self.scores[slotIndex] = {
			slot = slotIndex,
			percent = percent,
			fallen = fallen,
			reachedAt = reachedAt,
			name = if live.owner then live.owner.DisplayName else "—",
		}
		table.insert(payload, { slot = slotIndex, percent = percent })
	end

	table.sort(payload, function(a, b)
		return a.slot < b.slot
	end)
	self.remotes.ProgressSync:FireAllClients(payload)
	return true
end

-- 勝者 (slotIndex) と その崩壊率。誰もいなければ nil。
function ProgressTracker:leader()
	return Progress.leader(self.scores)
end

-- 誰かが 100% に到達したか
function ProgressTracker:hasWinner(): boolean
	for _, score in self.scores do
		if score.percent >= Config.match.winPercent then
			return true
		end
	end
	return false
end

return ProgressTracker
