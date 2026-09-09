-- domino-crash と同じ「外部アセット0本」の方針。Config.sound の各IDが
-- 空文字のままなら何も鳴らない。rbxassetid:// を入れれば鳴るようになる。

local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SkyCarrier")
local Config = require(Shared.Config)

local SoundController = {}
SoundController.__index = SoundController

local function makeSound(id: string, looped: boolean): Sound?
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = looped
	sound.Parent = SoundService
	return sound
end

function SoundController.new()
	return setmetatable({
		oneShots = {
			Boost = Config.sound.boost,
			Land = Config.sound.land,
			Crash = Config.sound.crash,
		},
		deliverySuccess = Config.sound.deliverySuccess,
		ambient = makeSound(Config.sound.ambientWind, true),
	}, SoundController)
end

function SoundController:start()
	if self.ambient then
		self.ambient:Play()
	end
end

-- FlightPredictor.onEvents から渡されるイベント名の配列を受け取る。
function SoundController:onFlightEvents(events: { string })
	for _, name in events do
		local id = self.oneShots[name]
		if id and id ~= "" then
			local sound = makeSound(id, false)
			if sound then
				sound:Play()
				sound.Ended:Once(function()
					sound:Destroy()
				end)
			end
		end
	end
end

function SoundController:onDeliverySuccess()
	local sound = makeSound(self.deliverySuccess, false)
	if sound then
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
end

return SoundController
