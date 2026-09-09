-- ミッションの受注・届け先追跡。判定そのものはサーバの MissionService が
-- 座標だけを見て行うので、ここは「提示された一覧を覚えておいて、ターミナルの
-- ProximityPrompt が押されたら受注、□ が押されたら受け渡しをサーバに申告する」
-- だけの薄いラッパー。

local MissionController = {}
MissionController.__index = MissionController

function MissionController.new(remotes)
	local self = setmetatable({
		remotes = remotes,
		offers = {},
		active = {},
		onResult = nil :: ((boolean, string, number?) -> ())?,
		onAcceptResult = nil :: ((boolean, string) -> ())?,
	}, MissionController)

	remotes.MissionUpdate.OnClientEvent:Connect(function(payload)
		self.offers = payload.offers or {}
		self.active = payload.active or {}
	end)

	return self
end

-- ターミナルの ProximityPrompt から呼ばれる。そのターミナル発の提示のうち
-- 一番早く生成されたもの (offers はサーバが index 昇順で積む) を受注する。
function MissionController:acceptFromTerminal(terminalId: string)
	local target = nil
	for _, offer in self.offers do
		if offer.originId == terminalId then
			target = offer
			break
		end
	end
	if not target then
		if self.onAcceptResult then
			self.onAcceptResult(false, "no_offer_here")
		end
		return
	end

	task.spawn(function()
		local result = self.remotes.RequestAcceptMission:InvokeServer(target.id)
		if self.onAcceptResult then
			self.onAcceptResult(result.ok, result.reason)
		end
	end)
end

-- □ (荷物投下 / 決定) が押されたときに呼ぶ。受注中の先頭ミッションを届ける。
function MissionController:attemptDelivery()
	local mission = self.active[1]
	if not mission then
		return
	end
	task.spawn(function()
		local result = self.remotes.RequestDelivery:InvokeServer(mission.id)
		if self.onResult then
			self.onResult(result.success, result.reason, result.payout)
		end
	end)
end

return MissionController
