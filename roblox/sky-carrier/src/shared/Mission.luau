--!strict
-- 配達ミッションの生成・報酬計算・成否判定。Roblox API を一切参照しない純関数なので、
-- サーバ (権威) と検証器 (verify.luau) が同じ数式を共有できる。

local Mission = {}

export type Terminal = {
	id: string,
	x: number,
	y: number,
	z: number,
}

export type MissionData = {
	id: string,
	originId: string,
	destId: string,
	distance: number,
	cargoWeight: number,
	weatherMultiplier: number,
	reward: number,
	timeLimit: number,
}

-- ── 決定的な擬似乱数 (32bit LCG) ────────────────────────
-- Roblox の Random ではなく自前で持つのは、Luau CLI から同じ数列を再現するため。
local function makeRng(seed: number)
	local state = math.floor(math.abs(seed)) % 2147483647
	if state == 0 then
		state = 1 -- 0 は LCG の吸収状態
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

function Mission.distance(a: Terminal, b: Terminal): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

function Mission.reward(distance: number, cargoWeight: number, weatherMultiplier: number, cfg): number
	local base = cfg.baseReward + cfg.rewardPerStud * distance + cfg.rewardPerCargo * cargoWeight
	return base * weatherMultiplier
end

function Mission.timeLimit(distance: number, cfg): number
	return cfg.timeLimitBase + cfg.timeLimitPerStud * distance
end

-- 同じ (seed, index) からは常に同じミッションが生成される (対戦相手との公平性は無いが、
-- リプレイ・検証・DataStore 復元のために決定的にしてある)。
function Mission.generate(seed: number, index: number, terminals: { Terminal }, maxCargo: number, cfg): MissionData
	assert(#terminals >= 2, "ターミナルが2つ以上必要です")
	local rng = makeRng(seed * 97 + index * 7919 + 1)

	local originIdx = math.floor(rng() * #terminals) + 1
	local destIdx = math.floor(rng() * (#terminals - 1)) + 1
	if destIdx >= originIdx then
		destIdx += 1
	end
	local origin = terminals[originIdx]
	local dest = terminals[destIdx]

	local distance = Mission.distance(origin, dest)
	local cargoWeight = math.max(1, math.floor(rng() * maxCargo) + 1)
	local weatherRange = cfg.weatherMultiplierRange
	local weatherMultiplier = weatherRange.min + rng() * (weatherRange.max - weatherRange.min)

	return {
		id = string.format("M-%d-%d", seed, index),
		originId = origin.id,
		destId = dest.id,
		distance = distance,
		cargoWeight = cargoWeight,
		weatherMultiplier = weatherMultiplier,
		reward = Mission.reward(distance, cargoWeight, weatherMultiplier, cfg),
		timeLimit = Mission.timeLimit(distance, cfg),
	}
end

-- 受注可能かどうか (貨物ベイ拡張で maxActiveMissions + upgrades.Cargo.missionSlotBonusPerLevel * level)
function Mission.canAccept(activeCount: number, maxActiveMissions: number): boolean
	return activeCount < maxActiveMissions
end

-- 制限時間内に届いたか判定し、支払額を返す。時間切れなら 0。
-- 余した秒数ぶんタイムボーナスが乗る (早く届けるほど得)。
function Mission.evaluate(mission: MissionData, elapsedSeconds: number, cfg): { success: boolean, payout: number }
	if elapsedSeconds > mission.timeLimit then
		return { success = false, payout = 0 }
	end
	local remaining = mission.timeLimit - elapsedSeconds
	local payout = mission.reward + remaining * cfg.timeBonusPerSecond
	return { success = true, payout = payout }
end

-- 着地判定: 着陸装置を出し、目的地から dropRadius 以内に、地上判定 (grounded) で
-- 到達していること。距離とグラウンド判定を分けて渡すのは AntiCheat 側で
-- 同じ座標を二重に検証させないため。
function Mission.isValidDropoff(distanceToDest: number, grounded: boolean, gearDown: boolean, cfg): boolean
	return grounded and gearDown and distanceToDest <= cfg.dropRadius
end

return Mission
