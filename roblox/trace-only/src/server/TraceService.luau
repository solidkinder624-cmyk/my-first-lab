-- 痕跡の配信。ここがこのゲームの「情報設計」の心臓部。
--
-- 他プレイヤーについてクライアントへ送られるのは、この Trace パケットだけ。
--   ・誰が出したかは送らない (匿名) → 足跡の主を推測するのがゲーム性
--   ・可聴半径 (Config.trace[kind].radius) の外には送らない
--     → 遠くの相手の情報はネットワーク上にも存在しないので、
--       クライアントを改造しても「聞こえない足音」は聞けない
--
-- 自分自身の痕跡は own=true を付けて本人にも返す (自分の足跡は見える)。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("TraceOnly")
local Config = require(Shared.Config)

local TraceService = {}
TraceService.__index = TraceService

function TraceService.new(registry, remotes)
	return setmetatable({ registry = registry, remotes = remotes }, TraceService)
end

-- source は Entry または nil (宝の取得音など、プレイヤーに紐づかない痕跡)
function TraceService:emit(source, trace)
	local spec = Config.trace[trace.kind]
	if not spec then
		return
	end
	local radius2 = spec.radius * spec.radius

	for _, entry in self.registry:all() do
		if not entry.ready then
			continue
		end
		local isSelf = source ~= nil and entry.player == source.player
		if not isSelf then
			-- 受け手の現在位置で可聴判定する (サーバだけが両者の位置を知っている)
			local dx = entry.state.x - trace.x
			local dz = entry.state.z - trace.z
			if dx * dx + dz * dz > radius2 then
				continue
			end
		end

		self.remotes.Trace:FireClient(entry.player, {
			k = trace.kind,
			x = trace.x,
			z = trace.z,
			dx = trace.dirX,
			dz = trace.dirZ,
			o = isSelf or nil,
		})
	end
end

-- 座標だけ指定して痕跡を鳴らす (宝の取得、タッチ成立など)
function TraceService:emitAt(kind: string, x: number, z: number, source)
	self:emit(source, { kind = kind, x = x, z = z, dirX = 0, dirZ = 0 })
end

return TraceService
