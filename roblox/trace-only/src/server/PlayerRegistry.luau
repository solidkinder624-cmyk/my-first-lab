-- プレイヤーごとのサーバ権威状態。
-- Player.Character は使わない (Players.CharacterAutoLoads = false)。
-- キャラクターモデルを Workspace に置かない = そもそも座標がレプリケートされないので、
-- 「透明にしただけ」の実装と違い、クライアント側で位置を覗く手段が存在しない。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)
local Motion = require(Shared.Motion)

local PlayerRegistry = {}
PlayerRegistry.__index = PlayerRegistry

export type Entry = {
	player: Player,
	state: any, -- Motion.State
	inputs: { any }, -- 未消化の入力バッファ
	lastInput: any,
	starvedTicks: number, -- 入力が途切れている連続tick数
	role: string, -- "Hider" | "Seeker" | "Runner" | "Hunter" | "Free"
	score: number,
	active: boolean, -- false ならシミュレーション対象外 (観戦/捕まった後)
	frozen: boolean, -- 準備時間などで動きを止める
	ready: boolean,
}

function PlayerRegistry.new()
	return setmetatable({ entries = {} :: { [Player]: Entry } }, PlayerRegistry)
end

function PlayerRegistry:add(player: Player): Entry
	local entry: Entry = {
		player = player,
		state = Motion.newState(0, 0, Config),
		inputs = {},
		lastInput = Motion.emptyInput(),
		starvedTicks = 0,
		role = "Free",
		score = 0,
		active = false,
		frozen = true,
		ready = false,
	}
	self.entries[player] = entry
	return entry
end

function PlayerRegistry:remove(player: Player)
	self.entries[player] = nil
end

function PlayerRegistry:get(player: Player): Entry?
	return self.entries[player]
end

function PlayerRegistry:all(): { [Player]: Entry }
	return self.entries
end

-- 条件に合うエントリを配列で返す
function PlayerRegistry:filter(predicate: (Entry) -> boolean): { Entry }
	local out: { Entry } = {}
	for _, entry in self.entries do
		if predicate(entry) then
			table.insert(out, entry)
		end
	end
	return out
end

function PlayerRegistry:count(predicate: ((Entry) -> boolean)?): number
	local n = 0
	for _, entry in self.entries do
		if predicate == nil or predicate(entry) then
			n += 1
		end
	end
	return n
end

-- 指定座標から半径内にいるエントリ (鬼のタッチ判定・宝の取得判定に使う)
function PlayerRegistry:near(x: number, z: number, radius: number, filter: ((Entry) -> boolean)?): { Entry }
	local out: { Entry } = {}
	local r2 = radius * radius
	for _, entry in self.entries do
		if filter and not filter(entry) then
			continue
		end
		local dx, dz = entry.state.x - x, entry.state.z - z
		if dx * dx + dz * dz <= r2 then
			table.insert(out, entry)
		end
	end
	return out
end

return PlayerRegistry
