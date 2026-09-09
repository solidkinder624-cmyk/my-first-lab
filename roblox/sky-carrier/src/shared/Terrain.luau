--!strict
-- 自由飛行エリア (山岳・海洋・都市) の地形を手続き生成する。Roblox API を
-- 一切参照しない純関数なので、サーバ (TerrainBuilder) と検証器 (verify.luau)
-- が同じ配置を共有できる。実際の Part 生成は Roblox 依存の TerrainBuilder が行う。

local Terrain = {}

export type Feature = {
	kind: string, -- "Mountain" | "Island" | "Building"
	cx: number,
	cy: number, -- 中心の高さ (底面ではない)
	cz: number,
	sx: number,
	sy: number,
	sz: number,
}

-- ── 決定的な擬似乱数 (32bit LCG) ────────────────────────
-- Mission.luau / domino-crash/Blueprint.luau と同じもの。Luau CLI からも
-- 同じ数列を再現するために Roblox の Random ではなく自前で持つ。
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

-- 山: 裾野を少し地面に埋めた楕円体 (Ball を非一様スケールした見た目)。
function Terrain.mountains(seed: number, zoneCfg): { Feature }
	local rng = makeRng(seed)
	local features: { Feature } = {}
	for _ = 1, zoneCfg.count do
		local angle = rng() * math.pi * 2
		local dist = zoneCfg.minDistance + rng() * (zoneCfg.radius - zoneCfg.minDistance)
		local height = zoneCfg.minHeight + rng() * (zoneCfg.maxHeight - zoneCfg.minHeight)
		local radius = zoneCfg.minRadius + rng() * (zoneCfg.maxRadius - zoneCfg.minRadius)
		table.insert(features, {
			kind = "Mountain",
			cx = zoneCfg.centerX + math.cos(angle) * dist,
			cy = height * 0.38, -- 裾野を地面へ少し埋め込み、宙に浮いて見えないようにする
			cz = zoneCfg.centerZ + math.sin(angle) * dist,
			sx = radius * 2,
			sy = height,
			sz = radius * 2,
		})
	end
	return features
end

-- 島: 海洋エリア内に点在する小さな丘。形はMountainと同じ生成式を低めのスケールで使う。
function Terrain.islands(seed: number, zoneCfg): { Feature }
	local rng = makeRng(seed)
	local features: { Feature } = {}
	for _ = 1, zoneCfg.islandCount do
		local angle = rng() * math.pi * 2
		local dist = zoneCfg.minDistance + rng() * (zoneCfg.radius - zoneCfg.minDistance)
		local height = zoneCfg.minHeight + rng() * (zoneCfg.maxHeight - zoneCfg.minHeight)
		local radius = zoneCfg.minRadius + rng() * (zoneCfg.maxRadius - zoneCfg.minRadius)
		table.insert(features, {
			kind = "Island",
			cx = zoneCfg.centerX + math.cos(angle) * dist,
			cy = height * 0.3,
			cz = zoneCfg.centerZ + math.sin(angle) * dist,
			sx = radius * 2,
			sy = height,
			sz = radius * 2,
		})
	end
	return features
end

-- ビル: ジッターを掛けた格子状に配置し、確率で間引いて自然な密度にする。
function Terrain.buildings(seed: number, zoneCfg): { Feature }
	local rng = makeRng(seed)
	local features: { Feature } = {}
	local cellSize = zoneCfg.footprintMax + 10
	local steps = math.max(1, math.floor((zoneCfg.radius * 2) / cellSize))

	for i = 0, steps * steps - 1 do
		if #features >= zoneCfg.buildingCount then
			break
		end
		local gx = i % steps
		local gz = math.floor(i / steps)
		local px = -zoneCfg.radius + (gx + 0.5) * cellSize + (rng() - 0.5) * cellSize * 0.4
		local pz = -zoneCfg.radius + (gz + 0.5) * cellSize + (rng() - 0.5) * cellSize * 0.4
		local distFromCenter = math.sqrt(px * px + pz * pz)
		local place = rng() < 0.6
		if distFromCenter <= zoneCfg.radius and distFromCenter >= zoneCfg.minDistance and place then
			local height = zoneCfg.minHeight + rng() * (zoneCfg.maxHeight - zoneCfg.minHeight)
			local footprint = zoneCfg.footprintMin + rng() * (zoneCfg.footprintMax - zoneCfg.footprintMin)
			table.insert(features, {
				kind = "Building",
				cx = zoneCfg.centerX + px,
				cy = height * 0.5,
				cz = zoneCfg.centerZ + pz,
				sx = footprint,
				sy = height,
				sz = footprint,
			})
		end
	end
	return features
end

-- kind: "Mountain" | "Ocean" | "Urban"。ゾーンの種類に応じた生成関数へ振り分ける。
function Terrain.generate(kind: string, seed: number, zoneCfg): { Feature }
	if kind == "Mountain" then
		return Terrain.mountains(seed, zoneCfg)
	elseif kind == "Ocean" then
		return Terrain.islands(seed, zoneCfg)
	elseif kind == "Urban" then
		return Terrain.buildings(seed, zoneCfg)
	end
	error("未知のゾーン種別: " .. tostring(kind))
end

return Terrain
