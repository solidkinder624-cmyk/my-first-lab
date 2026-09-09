-- 天候の権威。Weather.luau (純ロジック) がサーバ時刻から決定的に天候名を
-- 求め、変わった時だけ全員へ通知する (据え置きの値を毎回送らない)。

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SkyCarrier")
local Weather = require(Shared.Weather)

local WeatherService = {}
WeatherService.__index = WeatherService

function WeatherService.new(remotes, cfg)
	local self = setmetatable({
		remotes = remotes,
		cfg = cfg,
		current = nil :: string?,
		startedAt = os.clock(),
	}, WeatherService)
	return self
end

function WeatherService:current_()
	return Weather.at(os.clock() - self.startedAt, self.cfg.weather)
end

-- 現在の天候が確定してから呼ぶ入室者向けの送信。
function WeatherService:sendTo(player: Player)
	self.remotes.WeatherUpdate:FireClient(player, self:current_())
end

-- 定期的に呼ぶ。変化があったときだけ全員に配信する。
function WeatherService:step()
	local weather = self:current_()
	if weather ~= self.current then
		self.current = weather
		self.remotes.WeatherUpdate:FireAllClients(weather)
	end
end

return WeatherService
