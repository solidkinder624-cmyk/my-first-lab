--!strict
-- 崩壊率の計算。純粋な算術だけ。
--
-- 「アンカーが外れて空中にある」ブロックを freeWeight (既定 0.35) で数えるのが
-- 味付けのポイント。柱を折った瞬間に上層が丸ごと free になるので、実際に瓦礫が
-- 床に着く前にゲージが跳ねる。プレイヤーの操作とゲージの反応の間に
-- 「落下時間ぶんの間」が入らない。

local Progress = {}

export type Snapshot = {
	total: number,
	fallen: number, -- 完全に落ちた (キル平面を切った / 静止した) 数
	free: number, -- アンカー解除済みでまだ落下中の数
	percent: number,
}

function Progress.percent(total: number, fallen: number, free: number, freeWeight: number): number
	if total <= 0 then
		return 0
	end
	local weighted = fallen + free * freeWeight
	return math.clamp(weighted / total * 100, 0, 100)
end

function Progress.snapshot(total: number, fallen: number, free: number, freeWeight: number): Snapshot
	return {
		total = total,
		fallen = fallen,
		free = free,
		percent = Progress.percent(total, fallen, free, freeWeight),
	}
end

-- 表示用。0.1% 刻みに丸めて、無意味な小数でネットワークとUIを汚さない。
function Progress.quantize(percent: number): number
	return math.floor(percent * 10 + 0.5) / 10
end

-- 勝者判定。崩壊率 → 落下数 → 到達時刻 の順で比較する。
-- scores は { [key] = { percent, fallen, reachedAt } } の形。
local function outranks(a, b): boolean
	if math.abs(a.percent - b.percent) > 1e-6 then
		return a.percent > b.percent
	end
	if a.fallen ~= b.fallen then
		return a.fallen > b.fallen
	end
	return a.reachedAt < b.reachedAt
end

function Progress.leader(scores: { [any]: { percent: number, fallen: number, reachedAt: number } }): (any?, number)
	local bestKey, best = nil, nil
	for key, score in scores do
		if best == nil or outranks(score, best) then
			bestKey, best = key, score
		end
	end
	return bestKey, if best then best.percent else 0
end

return Progress
