-- 自分以外の機体の見た目。BroadcastFlightState (約12Hz) で届く値をそのまま
-- 描画すると出力間隔ぶんカクつくので、毎フレーム目標値へ指数的に近づけて
-- 補間する (05/マルチプレイ構成の「他機体は補間表示」に対応)。

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)
local AircraftRig = require(script.Parent.AircraftRig)

local RemotePlayers = {}
RemotePlayers.__index = RemotePlayers

local COLORS = {
	Color3.fromRGB(210, 90, 70),
	Color3.fromRGB(90, 150, 210),
	Color3.fromRGB(90, 190, 120),
	Color3.fromRGB(220, 170, 60),
}

local function colorFor(userId: number): Color3
	return COLORS[(userId % #COLORS) + 1]
end

function RemotePlayers.new(parent: Instance)
	return setmetatable({
		parent = parent,
		rigs = {}, -- userId → Model
		targets = {}, -- userId → 最新のサーバ値
		current = {}, -- userId → 補間中の表示値
	}, RemotePlayers)
end

function RemotePlayers:onSnapshot(payload: { any }, localUserId: number)
	local seen = {}
	for _, entry in payload do
		if entry.userId == localUserId then
			continue
		end
		seen[entry.userId] = true
		if not self.rigs[entry.userId] then
			local rig = AircraftRig.build(colorFor(entry.userId), false)
			rig.Parent = self.parent
			self.rigs[entry.userId] = rig
			self.current[entry.userId] = entry
		end
		self.targets[entry.userId] = entry
	end

	-- ブロードキャストに含まれなくなった (離脱した) プレイヤーの機体を消す
	for userId in self.rigs do
		if not seen[userId] then
			self:remove(userId)
		end
	end
end

function RemotePlayers:remove(userId: number)
	local rig = self.rigs[userId]
	if rig then
		rig:Destroy()
	end
	self.rigs[userId] = nil
	self.targets[userId] = nil
	self.current[userId] = nil
end

local function lerpAngle(a: number, b: number, alpha: number): number
	local diff = (b - a + 540) % 360 - 180
	return a + diff * alpha
end

function RemotePlayers:step(dt: number)
	local alpha = math.clamp(dt * Config.broadcast.rateHz * 1.5, 0, 1)
	for userId, target in self.targets do
		local rig = self.rigs[userId]
		local cur = self.current[userId] or target
		local nx = cur.x + (target.x - cur.x) * alpha
		local ny = cur.y + (target.y - cur.y) * alpha
		local nz = cur.z + (target.z - cur.z) * alpha
		local npitch = lerpAngle(cur.pitch, target.pitch, alpha)
		local nyaw = lerpAngle(cur.yaw, target.yaw, alpha)
		local nroll = lerpAngle(cur.roll, target.roll, alpha)
		self.current[userId] = { x = nx, y = ny, z = nz, pitch = npitch, yaw = nyaw, roll = nroll }
		if rig then
			AircraftRig.setPose(rig, nx, ny, nz, npitch, nyaw, nroll)
		end
	end
end

return RemotePlayers
