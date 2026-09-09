-- 所持金・所有機体・アップグレードの永続化。
--
-- DataStore へのアクセスは Studio の "Enable Studio Access to API Services" が
-- 無いと失敗するので、pcall で必ず包み、失敗時は初期値のまま (保存されないだけ)
-- でプレイは続行できるようにする。

local DataStoreService = game:GetService("DataStoreService")

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)

local STORE_NAME = "SkyCarrier_PlayerData_v1"

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

local function defaultProfile()
	local upgrades = {}
	for name in Config.upgrades do
		upgrades[name] = 0
	end
	return {
		money = 500, -- 練習機だけでも配達で遊び始められるよう、少額の初期資金を持たせる
		currentAircraft = Config.defaultAircraft,
		ownedAircraft = { [Config.defaultAircraft] = true },
		upgrades = upgrades,
	}
end

function PlayerDataService.new()
	local self = setmetatable({
		store = nil :: DataStore?,
		profiles = {}, -- Player → profile
	}, PlayerDataService)

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		self.store = store
	else
		warn("[SkyCarrier] DataStore を取得できません。データは保存されません: " .. tostring(store))
	end

	return self
end

function PlayerDataService:load(player: Player)
	local profile = defaultProfile()
	if self.store then
		local ok, saved = pcall(function()
			return self.store:GetAsync("Player_" .. player.UserId)
		end)
		if ok and type(saved) == "table" then
			for key, value in saved do
				profile[key] = value
			end
		end
	end
	self.profiles[player] = profile
	return profile
end

function PlayerDataService:get(player: Player)
	return self.profiles[player]
end

function PlayerDataService:save(player: Player)
	local profile = self.profiles[player]
	if not (self.store and profile) then
		return
	end
	local ok, err = pcall(function()
		self.store:SetAsync("Player_" .. player.UserId, profile)
	end)
	if not ok then
		warn(string.format("[SkyCarrier] %s の保存に失敗: %s", player.Name, tostring(err)))
	end
end

function PlayerDataService:release(player: Player)
	self:save(player)
	self.profiles[player] = nil
end

function PlayerDataService:addMoney(player: Player, amount: number)
	local profile = self.profiles[player]
	if not profile then
		return
	end
	profile.money = math.max(0, profile.money + amount)
end

-- 機体購入。所持金が足りるか、既に持っていないかを見る。
function PlayerDataService:purchaseAircraft(player: Player, aircraftName: string): (boolean, string)
	local profile = self.profiles[player]
	local stats = Config.aircraft[aircraftName]
	if not (profile and stats) then
		return false, "unknown_aircraft"
	end
	if profile.ownedAircraft[aircraftName] then
		return false, "already_owned"
	end
	if profile.money < stats.price then
		return false, "insufficient_funds"
	end
	profile.money -= stats.price
	profile.ownedAircraft[aircraftName] = true
	return true, "ok"
end

function PlayerDataService:selectAircraft(player: Player, aircraftName: string): (boolean, string)
	local profile = self.profiles[player]
	if not profile then
		return false, "no_profile"
	end
	if not profile.ownedAircraft[aircraftName] then
		return false, "not_owned"
	end
	profile.currentAircraft = aircraftName
	return true, "ok"
end

-- アップグレード購入。レベルごとにコストが costGrowth 倍で増える。
function PlayerDataService:purchaseUpgrade(player: Player, kind: string): (boolean, string)
	local profile = self.profiles[player]
	local spec = Config.upgrades[kind]
	if not (profile and spec) then
		return false, "unknown_upgrade"
	end
	local level = profile.upgrades[kind] or 0
	if level >= spec.maxLevel then
		return false, "max_level"
	end
	local cost = math.floor(spec.costBase * spec.costGrowth ^ level)
	if profile.money < cost then
		return false, "insufficient_funds"
	end
	profile.money -= cost
	profile.upgrades[kind] = level + 1
	return true, "ok"
end

-- 現在の機体 + アップグレードを反映した実効ステータス。FlightService と
-- MissionService はこれだけを見ればよく、生の Config を直接参照しない。
function PlayerDataService:effectiveStats(player: Player)
	local profile = self.profiles[player]
	if not profile then
		return Config.aircraft[Config.defaultAircraft]
	end
	local base = Config.aircraft[profile.currentAircraft] or Config.aircraft[Config.defaultAircraft]
	local engineLevel = profile.upgrades.Engine or 0
	local fuelLevel = profile.upgrades.Fuel or 0
	local cargoLevel = profile.upgrades.Cargo or 0

	return {
		displayName = base.displayName,
		price = base.price,
		maxSpeed = base.maxSpeed,
		accel = base.accel * (1 + Config.upgrades.Engine.accelBonusPerLevel * engineLevel),
		turnRate = base.turnRate,
		cargoCapacity = base.cargoCapacity,
		fuelCapacity = base.fuelCapacity * (1 + Config.upgrades.Fuel.capacityBonusPerLevel * fuelLevel),
		maxActiveMissions = Config.mission.maxActiveMissions
			+ Config.upgrades.Cargo.missionSlotBonusPerLevel * cargoLevel,
	}
end

return PlayerDataService
