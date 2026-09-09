-- 天候名を受け取り、Lighting へ反映する。演出の下地なので、霧の距離・色・
-- 明るさ・環境光だけを緩やかに補間する (突然切り替わるとブースト中などに驚くため)。

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent.Shared
local Config = require(Shared.Config)

local TRANSITION_SECONDS = 6

local WeatherController = {}
WeatherController.__index = WeatherController

local function toColor3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function WeatherController.new()
	local preset = Config.weather.presets[Config.weather.order[1]]
	return setmetatable({
		current = preset,
		target = preset,
		elapsed = TRANSITION_SECONDS,
		connection = nil :: RBXScriptConnection?,
	}, WeatherController)
end

function WeatherController:apply(weatherName: string)
	local preset = Config.weather.presets[weatherName]
	if not preset then
		return
	end
	self.target = preset
	self.elapsed = 0
end

function WeatherController:start()
	self.connection = RunService.Heartbeat:Connect(function(dt)
		if self.elapsed >= TRANSITION_SECONDS then
			return
		end
		self.elapsed = math.min(TRANSITION_SECONDS, self.elapsed + dt)
		local alpha = self.elapsed / TRANSITION_SECONDS

		Lighting.FogEnd = self.current.fogEnd + (self.target.fogEnd - self.current.fogEnd) * alpha
		Lighting.FogColor = toColor3(self.current.fogColor):Lerp(toColor3(self.target.fogColor), alpha)
		Lighting.Brightness = self.current.brightness + (self.target.brightness - self.current.brightness) * alpha
		Lighting.Ambient = toColor3(self.current.ambient):Lerp(toColor3(self.target.ambient), alpha)

		if alpha >= 1 then
			self.current = self.target
		end
	end)
end

function WeatherController:stop()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

return WeatherController
