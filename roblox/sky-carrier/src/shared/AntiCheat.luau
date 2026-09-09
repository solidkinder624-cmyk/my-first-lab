--!strict
-- 移動申告の受理条件。サーバの FlightService と verify.luau が共有する純ロジック。
--
-- 04/マルチプレイ構成の「速度・位置の急変をサーバ側で検知し、物理的に不可能な
-- 移動量ならリジェクトして直前の正規位置へ戻す」を実装したもの。ここで弾くのは:
--   1. 物理的に届かない距離の移動 (テレポート/速度ハック)
--   2. 送信間隔が短すぎる入力 (フラッド)
--
-- レイテンシのぶんだけ緩めてある (speedTolerance / graceDistance)。
-- 厳しすぎるとブースト直後や回線の悪いプレイヤーの正当な移動が弾かれる。

local AntiCheat = {}

export type Record = {
	hasLast: boolean,
	lastTime: number,
	lastX: number,
	lastY: number,
	lastZ: number,
}

function AntiCheat.newRecord(): Record
	return { hasLast = false, lastTime = 0, lastX = 0, lastY = 0, lastZ = 0 }
end

-- 受理してよいか。副作用なし。
--   now       : サーバ時刻 (秒)
--   x,y,z     : 申告された新しい位置
--   maxSpeed  : その機体の (ブースト込み) 最高速度
-- 戻り値: ok, reason ("ok" / "rate_limit" / "non_monotonic_time" / "impossible_move")
function AntiCheat.check(record: Record, now: number, x: number, y: number, z: number, maxSpeed: number, cfg): (boolean, string)
	if not record.hasLast then
		return true, "ok"
	end

	local dt = now - record.lastTime
	if dt <= 0 then
		return false, "non_monotonic_time"
	end
	if dt < cfg.minInputInterval then
		return false, "rate_limit"
	end

	local dx, dy, dz = x - record.lastX, y - record.lastY, z - record.lastZ
	local moved = math.sqrt(dx * dx + dy * dy + dz * dz)
	local allowed = maxSpeed * cfg.speedTolerance * math.min(dt, cfg.maxStepDelta) + cfg.graceDistance
	if moved > allowed then
		return false, "impossible_move"
	end

	return true, "ok"
end

-- 受理した位置を記録する。check が true を返したときだけ呼ぶこと。
function AntiCheat.commit(record: Record, now: number, x: number, y: number, z: number)
	record.hasLast = true
	record.lastTime = now
	record.lastX = x
	record.lastY = y
	record.lastZ = z
end

return AntiCheat
