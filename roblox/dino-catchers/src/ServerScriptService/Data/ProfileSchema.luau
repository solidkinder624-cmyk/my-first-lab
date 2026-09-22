--!strict
-- プレイヤーデータの「形」を決める純ロジック。
-- 初期値の生成・保存データの検証（壊れた値の修正）・バージョン移行・セッションロックの判定を行う。
--
-- Roblox API（DataStore / Players / HttpService など）には一切依存しない。
-- 設定値（DinoConfig）は引数で受け取るので、Luau CLI からもそのまま検証できる。
-- DataStore の読み書きそのものは PlayerData.luau が行う。
--
-- DataStore に入る値（Record）の形:
--   {
--     Profile = Profile,                 -- 下記
--     Session = { Token, JobId, Time }?, -- どのサーバーが今このデータを使っているか（ロック）
--     SavedAt = number?,                 -- 最後に保存した時刻（os.time()）
--   }
-- Profile の形:
--   {
--     SchemaVersion = number,   -- データ形式のバージョン（移行用）
--     Level = number,           -- プレイヤーLv
--     Money = number,           -- 所持金（整数）
--     MaxOwnedDinos = number,   -- 所持上限（初期値 DinoConfig.BaseMaxOwnedDinos）
--     Dinos = { OwnedDino },    -- 所持恐竜（捕獲順）。OwnedDino は Shared.RemoteSpec を参照
--   }

local ProfileSchema = {}

-- データ形式を変えたら上げて、migrate() に移行処理を足す。
ProfileSchema.CURRENT_SCHEMA_VERSION = 1

export type OwnedDino = {
	Id: string,
	Species: string,
	Level: number,
	CapturedAt: number,
}

export type Profile = {
	SchemaVersion: number,
	Level: number,
	Money: number,
	MaxOwnedDinos: number,
	Dinos: { OwnedDino },
}

export type Session = {
	Token: string,
	JobId: string,
	Time: number,
}

export type Record = {
	Profile: Profile,
	Session: Session?,
	SavedAt: number?,
}

-- ── 小道具 ─────────────────────────────────────────────

-- 有限の数値か（NaN・無限大・文字列などを弾く）
local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- 整数に丸めて範囲に収める。不正な値なら fallback。
local function toClampedInteger(value: any, minValue: number, maxValue: number, fallback: number): number
	if not isFiniteNumber(value) then
		return fallback
	end
	return math.clamp(math.floor(value), minValue, maxValue)
end

ProfileSchema.isFiniteNumber = isFiniteNumber
ProfileSchema.toClampedInteger = toClampedInteger

function ProfileSchema.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[ProfileSchema.deepCopy(key)] = ProfileSchema.deepCopy(item)
	end
	return copy
end

-- 恐竜の種ごとのLv上限（未知の種は全体の上限）
function ProfileSchema.maxDinoLevel(config: any, speciesId: string): number
	local species = config.Species[speciesId]
	local absoluteMax = config.DinoGrowth.AbsoluteMaxLevel
	if species then
		return math.min(species.MaxLevel, absoluteMax)
	end
	return absoluteMax
end

-- ── 初期値 ─────────────────────────────────────────────

function ProfileSchema.createDefault(config: any): Profile
	return {
		SchemaVersion = ProfileSchema.CURRENT_SCHEMA_VERSION,
		Level = config.Player.StartingLevel,
		Money = config.Player.StartingMoney,
		MaxOwnedDinos = config.BaseMaxOwnedDinos,
		Dinos = {},
	}
end

-- 新しく捕獲した恐竜の記録を作る。id（GUID）と now（os.time()）は呼び出し側が渡す。
function ProfileSchema.createDino(config: any, id: string, speciesId: string, level: number?, now: number): OwnedDino?
	local species = config.Species[speciesId]
	if not species or type(id) ~= "string" or id == "" then
		return nil
	end
	local maxLevel = ProfileSchema.maxDinoLevel(config, speciesId)
	return {
		Id = id,
		Species = speciesId,
		Level = toClampedInteger(level or species.InitialLevel, 1, maxLevel, species.InitialLevel),
		CapturedAt = toClampedInteger(now, 0, math.huge, 0),
	}
end

-- ── 検証 ─────────────────────────────────────────────
-- 保存データ（や将来の手作業の修正）に壊れた値が入っていても、ゲームが落ちない形に直す。
-- 方針: 値を「消す」のは形として使えないものだけ。知らない種の恐竜も消さずに残す
--       （設定から種を外してもプレイヤーの所持が消えないように）。

local function sanitizeDino(config: any, raw: any, now: number): OwnedDino?
	if type(raw) ~= "table" then
		return nil
	end
	if type(raw.Id) ~= "string" or raw.Id == "" or type(raw.Species) ~= "string" or raw.Species == "" then
		return nil
	end
	local maxLevel = ProfileSchema.maxDinoLevel(config, raw.Species)
	return {
		Id = raw.Id,
		Species = raw.Species,
		Level = toClampedInteger(raw.Level, 1, maxLevel, 1),
		CapturedAt = toClampedInteger(raw.CapturedAt, 0, math.huge, now),
	}
end

-- 検証済みの新しい Profile を返す（引数は書き換えない）。2つ目の戻り値は直した箇所の一覧（ログ用）。
function ProfileSchema.sanitize(config: any, raw: any, now: number?): (Profile, { string })
	local issues = {}
	local nowValue = now or 0
	local defaults = ProfileSchema.createDefault(config)
	if type(raw) ~= "table" then
		table.insert(issues, "profile が table ではないため初期値を使用")
		return defaults, issues
	end

	local playerConfig = config.Player
	local profile: Profile = {
		SchemaVersion = ProfileSchema.CURRENT_SCHEMA_VERSION,
		Level = toClampedInteger(raw.Level, 1, playerConfig.MaxLevel, defaults.Level),
		Money = toClampedInteger(raw.Money, 0, playerConfig.MaxMoney, defaults.Money),
		-- 上限は「保存値」と「現在の BaseMaxOwnedDinos」の大きい方。
		-- Base を上げたとき既存プレイヤーにも即反映し、下げても既存プレイヤーの上限は減らさない。
		MaxOwnedDinos = math.max(
			toClampedInteger(raw.MaxOwnedDinos, 1, playerConfig.MaxOwnedDinosHardCap, defaults.MaxOwnedDinos),
			math.min(config.BaseMaxOwnedDinos, playerConfig.MaxOwnedDinosHardCap)
		),
		Dinos = {},
	}
	if profile.Level ~= raw.Level then
		table.insert(issues, "Level を修正: " .. tostring(raw.Level))
	end
	if profile.Money ~= raw.Money then
		table.insert(issues, "Money を修正: " .. tostring(raw.Money))
	end

	local seenIds = {}
	if type(raw.Dinos) == "table" then
		for index, rawDino in raw.Dinos do
			local dino = sanitizeDino(config, rawDino, nowValue)
			if not dino then
				table.insert(issues, "形の壊れた恐竜データを除外: " .. tostring(index))
			elseif seenIds[dino.Id] then
				table.insert(issues, "重複した恐竜IDを除外: " .. dino.Id)
			else
				seenIds[dino.Id] = true
				table.insert(profile.Dinos, dino)
			end
		end
	elseif raw.Dinos ~= nil then
		table.insert(issues, "Dinos が table ではないため空にした")
	end

	return profile, issues
end

-- ── バージョン移行 ─────────────────────────────────────
-- 古い形式の Profile を最新の形式にする。
-- 戻り値: (移行後の raw, nil) / (nil, 理由)
-- 保存データのほうが新しい（新しいサーバーが書いた）場合は触らずに失敗を返す。
function ProfileSchema.migrate(raw: any): (any, string?)
	if type(raw) ~= "table" then
		return nil, "not_table"
	end
	local version = raw.SchemaVersion
	if version == nil then
		version = 1 -- バージョン記録前のデータは v1 とみなす
	end
	if not isFiniteNumber(version) then
		return nil, "bad_version"
	end
	if version > ProfileSchema.CURRENT_SCHEMA_VERSION then
		return nil, "newer_version"
	end
	local migrated = ProfileSchema.deepCopy(raw)
	-- 例: if version < 2 then ...v1→v2 の変換...; version = 2 end
	migrated.SchemaVersion = ProfileSchema.CURRENT_SCHEMA_VERSION
	return migrated, nil
end

-- DataStore から読んだ値（nil = 新規プレイヤー）を Profile にする。
-- 戻り値: (Profile, 直した箇所) / (nil, { 理由 })
-- 失敗時は呼び出し側で保存を止めること（壊れた・未知の形式のデータを上書きしないため）。
function ProfileSchema.profileFromStored(config: any, stored: any, now: number): (Profile?, { string })
	if stored == nil then
		return ProfileSchema.createDefault(config), {}
	end
	if type(stored) ~= "table" or type(stored.Profile) ~= "table" then
		return nil, { "unknown_record_format" }
	end
	local migrated, err = ProfileSchema.migrate(stored.Profile)
	if not migrated then
		return nil, { err or "migrate_failed" }
	end
	return ProfileSchema.sanitize(config, migrated, now)
end

-- ── セッションロック ───────────────────────────────────
-- 戻り値:
--   "Free"  … 誰も使っていない
--   "Ours"  … 自分（token が一致）
--   "Stale" … 他サーバーのロックだが timeout 秒以上更新がない（放置）
--   "Other" … 他サーバーが使用中
function ProfileSchema.sessionStatus(stored: any, token: string, now: number, timeout: number): string
	if type(stored) ~= "table" or type(stored.Session) ~= "table" then
		return "Free"
	end
	local session = stored.Session
	if session.Token == token then
		return "Ours"
	end
	if not isFiniteNumber(session.Time) or now - session.Time >= timeout then
		return "Stale"
	end
	return "Other"
end

-- ── 所持上限・表示用 ───────────────────────────────────

-- 所持上限は必ずプレイヤーデータの MaxOwnedDinos を見る（数値の直書きをしない）。
function ProfileSchema.canAddDino(profile: Profile): (boolean, string?)
	if #profile.Dinos >= profile.MaxOwnedDinos then
		return false, "OwnedLimit"
	end
	return true, nil
end

function ProfileSchema.findDinoIndex(profile: Profile, dinoId: string): number?
	for index, dino in profile.Dinos do
		if dino.Id == dinoId then
			return index
		end
	end
	return nil
end

-- クライアントの HUD 向けの情報（RemoteSpec.ProfileView）
function ProfileSchema.toView(profile: Profile)
	return {
		Level = profile.Level,
		Money = profile.Money,
		MaxOwnedDinos = profile.MaxOwnedDinos,
		OwnedCount = #profile.Dinos,
	}
end

return ProfileSchema
