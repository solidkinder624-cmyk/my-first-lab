--!strict
-- 天候の決定 (演出の下地)。実際に画面へ反映する Lighting の値は
-- Config.weather.presets が持ち、ここでは「今どの天候か」だけを純関数で決める。
-- サーバ時刻から決定的に求まるので、途中から見ても・複数のサーバでも同じ
-- 周期で同じ天候になる (検証しやすく、再現もできる)。

local Weather = {}

-- Mission.luau / Terrain.luau と同じ 32bit LCG。周期の番号をシードにするので、
-- 同じ周期番号からは常に同じ天候が選ばれる (決定的)。
local function makeRng(seed: number)
	local state = math.floor(math.abs(seed)) % 2147483647
	if state == 0 then
		state = 1
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- どの周期にいるか (0始まり)。
function Weather.cycleIndex(serverSeconds: number, cfg): number
	return math.floor(math.max(serverSeconds, 0) / cfg.periodSeconds)
end

-- serverSeconds 時点の天候名を返す。同じ周期の間はずっと同じ値。
-- 連続2回同じ天候にならないよう、直前の周期の結果を除外して選ぶ。
-- 周期0から順に辿る (再帰にすると、稼働時間が長いサーバでコールスタックが
-- 周期数ぶん深くなってしまうため)。
function Weather.at(serverSeconds: number, cfg): string
	local cycle = Weather.cycleIndex(serverSeconds, cfg)
	local order = cfg.order
	local current = order[1]

	for c = 1, cycle do
		local candidates = {}
		for _, name in order do
			if name ~= current then
				table.insert(candidates, name)
			end
		end
		if #candidates == 0 then
			candidates = order
		end
		local rng = makeRng(c * 7919 + 1)
		local index = math.floor(rng() * #candidates) + 1
		current = candidates[index]
	end

	return current
end

return Weather
