-- ミッションの受注・届け先追跡。判定そのものはサーバの MissionService が
-- 座標だけを見て行うので、ここは「提示された一覧を覚えておいて、□ が押されたら
-- 一番上のミッションの受け渡しをサーバに申告する」だけの薄いラッパー。

local MissionController = {}
MissionController.__index = MissionController

function MissionController.new(remotes)
	local self = setmetatable({
		remotes = remotes,
		offers = {},
		active = {},
		onResult = nil :: ((boolean, string, number?) -> ())?,
	}, MissionController)

	remotes.MissionUpdate.OnClientEvent:Connect(function(payload)
		self.offers = payload.offers or {}
		self.active = payload.active or {}
		-- 手が空いていれば自動的に一番上の提示を受注する (簡易な受注UIの代わり)
		if #self.active == 0 and #self.offers > 0 then
			self:accept(self.offers[1].id)
		end
	end)

	return self
end

function MissionController:accept(missionId: string)
	task.spawn(function()
		self.remotes.RequestAcceptMission:InvokeServer(missionId)
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
