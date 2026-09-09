-- WorldBuilder が各ターミナルに置いた AcceptMissionPrompt (ProximityPrompt) を
-- 監視し、押されたらそのターミナル発のミッションを MissionController に受注させる。

local ProximityPromptService = game:GetService("ProximityPromptService")

local TerminalController = {}
TerminalController.__index = TerminalController

function TerminalController.new(missionController)
	local self = setmetatable({
		missionController = missionController,
		connection = nil :: RBXScriptConnection?,
	}, TerminalController)
	return self
end

function TerminalController:start()
	self.connection = ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= "AcceptMissionPrompt" then
			return
		end
		local terminalId = prompt:GetAttribute("TerminalId")
		if type(terminalId) == "string" then
			self.missionController:acceptFromTerminal(terminalId)
		end
	end)
end

function TerminalController:stop()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

return TerminalController
