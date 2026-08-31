--!strict
-- ハンマー打撃の受理条件。サーバの HitValidation と verify.luau が共有する純ロジック。
--
-- クライアントは「叩いた」と主張するだけで、実際に何が壊れるかを決めるのは
-- サーバ。ここで弾くのは次の3種類:
--   1. 届かない距離からの打撃 (テレポート/リーチ改造)
--   2. クールダウンを無視した打撃 (連打マクロ)
--   3. 1秒あたりの回数が異常な打撃 (1 の抜け道を塞ぐ二重の網)
--
-- レイテンシのぶんだけ緩めてある (graceDistance / cooldown の 10% 許容)。
-- 厳しすぎると回線の悪いプレイヤーの正当な打撃が消える。

local HitRules = {}

export type Record = {
	lastHitAt: number,
	window: { number }, -- 直近1秒のヒット時刻
}

local WINDOW = 1.0
local COOLDOWN_TOLERANCE = 0.9 -- クールダウンの 90% 経過で受理する

function HitRules.newRecord(): Record
	return { lastHitAt = -math.huge, window = {} }
end

-- 受理してよいか。副作用なし。
--   now      : サーバ時刻 (秒)
--   distance : プレイヤーと打撃点の距離 (studs)
-- 戻り値: ok, reason ("ok" / "out_of_reach" / "cooldown" / "rate_limit")
function HitRules.check(record: Record, now: number, distance: number, hammer): (boolean, string)
	if distance > hammer.reach + hammer.graceDistance then
		return false, "out_of_reach"
	end
	if now - record.lastHitAt < hammer.cooldown * COOLDOWN_TOLERANCE then
		return false, "cooldown"
	end

	local recent = 0
	for _, t in record.window do
		if now - t < WINDOW then
			recent += 1
		end
	end
	if recent >= hammer.maxHitsPerSecond then
		return false, "rate_limit"
	end

	return true, "ok"
end

-- 受理した打撃を記録する。check が true を返したときだけ呼ぶこと。
function HitRules.commit(record: Record, now: number)
	record.lastHitAt = now
	local kept = {}
	for _, t in record.window do
		if now - t < WINDOW then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	record.window = kept
end

return HitRules
