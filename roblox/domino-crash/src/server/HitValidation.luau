-- 打撃リクエストの検証。クライアントが送ってくるのは「この Part をここで叩いた」
-- という主張だけで、何が壊れるかを決めるのはサーバ。
--
-- 弾く条件は HitRules (純ロジック・verify.luau と共有) に置いてあり、
-- ここが担当するのは Roblox 側の事実確認だけ:
--   * そのプレイヤーのキャラクターが実在して生きているか
--   * 叩いた Part が本当に「そのプレイヤーの構造物」の一部か
--     (他人の構造物を壊して妨害する / 自分の進行度を稼ぐ の両方を防ぐ)
--   * そのブロックがまだ立っているか (落下中の破片は叩けない)
--   * 着弾点が Part の表面から離れすぎていないか (座標の捏造)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DominoCrash")
local Config = require(Shared.Config)
local HitRules = require(Shared.HitRules)

local HitValidation = {}
HitValidation.__index = HitValidation

-- 着弾点は叩いた Part の表面付近になければならない。
-- Part の対角線の半分 + 少しの余裕を許容範囲とする。
local SURFACE_SLACK = 3

function HitValidation.new()
	return setmetatable({ records = {} }, HitValidation)
end

function HitValidation:recordFor(player: Player)
	local record = self.records[player]
	if not record then
		record = HitRules.newRecord()
		self.records[player] = record
	end
	return record
end

function HitValidation:forget(player: Player)
	self.records[player] = nil
end

-- 戻り値: ok, reason, blockId
function HitValidation:validate(player: Player, live, part: any, point: any, now: number): (boolean, string, number?)
	if live == nil then
		return false, "no_structure", nil
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false, "bad_part", nil
	end
	if typeof(point) ~= "Vector3" then
		return false, "bad_point", nil
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false, "no_character", nil
	end

	local blockId = live.idOf[part]
	if blockId == nil then
		return false, "foreign_part", nil -- 自分の構造物ではない
	end
	if live.run.freed[blockId] then
		return false, "already_broken", nil
	end

	-- 着弾点の捏造チェック。Part から遠すぎる点は受け付けない。
	local half = part.Size.Magnitude * 0.5 + SURFACE_SLACK
	if (point - part.Position).Magnitude > half then
		return false, "point_off_part", nil
	end

	local distance = (point - root.Position).Magnitude
	local record = self:recordFor(player)
	local allowed, reason = HitRules.check(record, now, distance, Config.hammer)
	if not allowed then
		return false, reason, nil
	end

	HitRules.commit(record, now)
	return true, "ok", blockId
end

return HitValidation
