-- プレイヤーデータ（所持恐竜・Lv・所持金・所持上限）のロード／セーブと、変更の窓口。
-- サーバー専用 ModuleScript。起動は同じフォルダの PlayerDataBoot（Script）が start() を呼ぶ。
--
-- ■ 他のサーバースクリプト（Capture / DinoAI など）からの使い方
--   local PlayerData = require(game:GetService("ServerScriptService").Data.PlayerData)
--   local ok, reason = PlayerData.canAddDino(player)
--   local ok, dinoOrReason = PlayerData.addDino(player, "Protoceratops")
--   PlayerData.addMoney(player, species.CaptureReward)
--   PlayerData.DinoAdded:Connect(function(player, dino) ... end)
--
-- ■ ルール
--   ・データの変更は必ずこのモジュールの関数を通す（get() が返すのは複製なので書き換えても保存されない）。
--   ・変更すると、本人のクライアントへ Remotes（ProfileChanged / DinoAdded / DinoRemoved / DinoUpdated）を自動で送る。
--   ・所持上限はプレイヤーデータの MaxOwnedDinos で判定する（数値の直書き禁止）。
--   ・変更系の関数は (成功したか, 結果 or 失敗理由) を返す。失敗理由は下の文字列:
--       "NotLoaded"（まだロード中 / 退出済み）, "Releasing"（退出処理中）, "OwnedLimit"（所持上限）,
--       "UnknownSpecies", "UnknownDino", "InvalidAmount", "InsufficientFunds"
--
-- ■ 保存の方針（CLAUDE.md 5章: 本番キーを消す・上書きする操作は禁止）
--   ・読み書きはすべて UpdateAsync + pcall + リトライ。SetAsync / RemoveAsync は使わない。
--   ・Studio では別のストア名（DinoConfig.Save.StudioDataStoreName）を使う。
--   ・セッションロック: 別サーバーが同じプレイヤーのデータを使っている間は待つ。
--     自分のロックが別サーバーに引き継がれていたら、古いデータで上書きしないよう保存をやめる。
--   ・読み込みに失敗した／未知の形式だったときは、仮の初期データで遊べるが一切保存しない。
--   ・保存タイミング: 自動保存（AutoSaveInterval）/ 捕獲などの直後 / 退出時 / サーバー終了時（BindToClose）

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DinoConfig = require(Shared:WaitForChild("DinoConfig"))
local RemoteSpec = require(Shared:WaitForChild("RemoteSpec"))
local Signal = require(Shared:WaitForChild("Signal"))
local ProfileSchema = require(script.Parent:WaitForChild("ProfileSchema"))

local SaveConfig = DinoConfig.Save

local PlayerData = {}

-- ── サーバー内向けシグナル（Connect して使う） ──────────────
-- 引数のテーブルは複製なので、書き換えても保存データには影響しない。
PlayerData.ProfileLoaded = Signal.new() -- (player, profile)  ロード完了（仮データのときも発火）
PlayerData.ProfileReleasing = Signal.new() -- (player)       退出・終了で手放す直前
PlayerData.ProfileChanged = Signal.new() -- (player, view)   Lv・所持金・上限・頭数が変わった（view = ProfileView）
PlayerData.DinoAdded = Signal.new() -- (player, dino)        所持恐竜が増えた
PlayerData.DinoRemoved = Signal.new() -- (player, dinoId)    所持恐竜が減った
PlayerData.DinoUpdated = Signal.new() -- (player, dino)      所持恐竜の中身（Lvなど）が変わった

-- ── 内部状態 ─────────────────────────────────────────────
type Entry = {
	Profile: ProfileSchema.Profile,
	Token: string, -- このサーバーでのセッションID（ロック用）
	CanSave: boolean, -- false なら一切保存しない
	Releasing: boolean,
	Saving: boolean,
	SaveScheduled: boolean,
}

local entries: { [Player]: Entry } = {}
local loading: { [Player]: boolean } = {}
local store: DataStore? = nil
local started = false
local closing = false
local pendingReleases = 0
local initialDataWaiting: { [Player]: boolean } = {} -- RequestInitialData の待機中（1人1本まで）

local remotes = {}

local function logWarn(message: string)
	warn("[PlayerData] " .. message)
end

local function keyFor(player: Player): string
	return SaveConfig.KeyPrefix .. tostring(player.UserId)
end

-- pcall + リトライ（待ち時間は試行ごとに倍）。戻り値: (成功したか, 結果 or エラー)
local function withRetries(label: string, callback: () -> any): (boolean, any)
	local lastError
	for attempt = 1, SaveConfig.MaxRetries do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		logWarn(string.format("%s 失敗 (%d/%d): %s", label, attempt, SaveConfig.MaxRetries, tostring(result)))
		if attempt < SaveConfig.MaxRetries then
			task.wait(SaveConfig.RetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

local function sendNotice(player: Player, kind: string, text: string)
	if remotes.NotifyPlayer and player.Parent then
		remotes.NotifyPlayer:FireClient(player, kind, text)
	end
end

-- ── ロード ────────────────────────────────────────────
-- 戻り値: (Profile, 保存してよいか, token)
local function loadProfile(player: Player): (ProfileSchema.Profile, boolean, string)
	local token = HttpService:GenerateGUID(false)
	if not store then
		return ProfileSchema.createDefault(DinoConfig), false, token
	end

	local key = keyFor(player)
	local maxLockAttempts = SaveConfig.SessionLockRetryCount + 1
	for lockAttempt = 1, maxLockAttempts do
		local result = "Error"
		local loadedProfile: ProfileSchema.Profile? = nil
		local notes: { string } = {}
		local canWait = lockAttempt < maxLockAttempts

		local ok, err = withRetries("ロード " .. key, function()
			return (store :: DataStore):UpdateAsync(key, function(stored)
				-- UpdateAsync の中では待たない（yield 禁止）。何度呼ばれてもよい作りにする
				local now = os.time()
				local status = ProfileSchema.sessionStatus(stored, token, now, SaveConfig.SessionLockTimeout)
				if status == "Other" and canWait then
					result = "Locked"
					return nil -- 書き込まずに中止
				end
				local profile, issues = ProfileSchema.profileFromStored(DinoConfig, stored, now)
				notes = issues
				if not profile then
					result = "Bad"
					return nil -- 読めない形式は絶対に上書きしない
				end
				result = "Loaded"
				loadedProfile = profile
				return {
					Profile = ProfileSchema.deepCopy(profile),
					Session = { Token = token, JobId = game.JobId, Time = now },
					SavedAt = if type(stored) == "table" then stored.SavedAt else nil,
				}
			end)
		end)

		if not ok then
			logWarn(string.format("%s のロードに失敗（保存しない仮データで続行）: %s", player.Name, tostring(err)))
			return ProfileSchema.createDefault(DinoConfig), false, token
		end
		if result == "Loaded" and loadedProfile then
			if #notes > 0 then
				logWarn(player.Name .. " のデータを修正: " .. table.concat(notes, " / "))
			end
			return loadedProfile, true, token
		end
		if result == "Bad" then
			logWarn(
				string.format(
					"%s の保存データが読めない形式です（上書きせず、保存しない仮データで続行）: %s",
					player.Name,
					table.concat(notes, " / ")
				)
			)
			return ProfileSchema.createDefault(DinoConfig), false, token
		end
		-- 他サーバーが使用中 → 少し待って再挑戦（最後の回はロックを引き継ぐ）
		if not player.Parent then
			break
		end
		task.wait(SaveConfig.SessionLockRetryDelay)
	end
	return ProfileSchema.createDefault(DinoConfig), false, token
end

-- ── セーブ ────────────────────────────────────────────
-- release = true なら保存と同時にロックを外す（退出・終了時）。戻り値: 保存できたか
local function saveEntry(player: Player, entry: Entry, release: boolean): boolean
	if not (store and entry.CanSave) then
		return false
	end
	-- 同じプレイヤーの保存を重ねない（古い内容が後から書かれるのを防ぐ）
	while entry.Saving do
		task.wait(SaveConfig.PollInterval)
	end
	if not entry.CanSave then
		return false
	end
	entry.Saving = true

	local snapshot = ProfileSchema.deepCopy(entry.Profile)
	local key = keyFor(player)
	local lostLock = false
	local ok, err = withRetries("セーブ " .. key, function()
		return (store :: DataStore):UpdateAsync(key, function(stored)
			local now = os.time()
			local status = ProfileSchema.sessionStatus(stored, entry.Token, now, SaveConfig.SessionLockTimeout)
			if status ~= "Ours" then
				lostLock = true
				return nil -- 他サーバーに引き継がれている。古い内容で上書きしない
			end
			lostLock = false
			return {
				Profile = snapshot,
				Session = if release then nil else { Token = entry.Token, JobId = game.JobId, Time = now },
				SavedAt = now,
			}
		end)
	end)
	entry.Saving = false

	if lostLock then
		entry.CanSave = false
		logWarn(player.Name .. " のデータは別サーバーに引き継がれたため、このサーバーでは保存を止めます")
		return false
	end
	if not ok then
		logWarn(string.format("%s の保存に失敗: %s", player.Name, tostring(err)))
		return false
	end
	return true
end

-- 大事な変化（捕獲など）のあと、少し待ってまとめて保存する
local function scheduleSave(player: Player, entry: Entry)
	if entry.SaveScheduled or not entry.CanSave then
		return
	end
	entry.SaveScheduled = true
	task.delay(SaveConfig.ImportantChangeSaveDelay, function()
		entry.SaveScheduled = false
		if entries[player] == entry and not entry.Releasing then
			saveEntry(player, entry, false)
		end
	end)
end

-- ── 通知 ──────────────────────────────────────────────
local function notifyProfileChanged(player: Player, entry: Entry)
	local view = ProfileSchema.toView(entry.Profile)
	if remotes.ProfileChanged and player.Parent then
		remotes.ProfileChanged:FireClient(player, view)
	end
	PlayerData.ProfileChanged:Fire(player, ProfileSchema.deepCopy(view))
end

-- 変更してよい状態の Entry を返す
local function getWritableEntry(player: Player): (Entry?, string?)
	local entry = entries[player]
	if not entry then
		return nil, "NotLoaded"
	end
	if entry.Releasing then
		return nil, "Releasing"
	end
	return entry, nil
end

-- 正の整数か（お金などの入力チェック）
local function isPositiveInteger(value: any): boolean
	return ProfileSchema.isFiniteNumber(value) and value > 0 and math.floor(value) == value
end

-- ── 参加・退出 ─────────────────────────────────────────
local function releasePlayer(player: Player)
	local entry = entries[player]
	if not entry or entry.Releasing then
		return
	end
	entry.Releasing = true
	pendingReleases += 1
	PlayerData.ProfileReleasing:Fire(player)
	saveEntry(player, entry, true)
	if entries[player] == entry then
		entries[player] = nil
	end
	pendingReleases -= 1
end

local function onPlayerAdded(player: Player)
	if entries[player] or loading[player] then
		return
	end
	loading[player] = true
	local profile, canSave, token = loadProfile(player)
	loading[player] = nil

	local entry: Entry = {
		Profile = profile,
		Token = token,
		CanSave = canSave,
		Releasing = false,
		Saving = false,
		SaveScheduled = false,
	}
	entries[player] = entry

	if not player.Parent or closing then
		-- ロード中に退出した / サーバー終了中。ロックを外すために保存して手放す
		releasePlayer(player)
		return
	end

	PlayerData.ProfileLoaded:Fire(player, ProfileSchema.deepCopy(profile))
	notifyProfileChanged(player, entry)
	if not canSave then
		if RunService:IsStudio() then
			sendNotice(player, RemoteSpec.NoticeKinds.Info, "Studio テスト: データは保存されません。")
		else
			sendNotice(
				player,
				RemoteSpec.NoticeKinds.Error,
				"データを読み込めませんでした。今回の進行は保存されません。入り直してください。"
			)
		end
	end
end

-- ── 公開API: 読み取り ───────────────────────────────────

function PlayerData.isLoaded(player: Player): boolean
	return entries[player] ~= nil
end

-- ロード完了まで待つ（最大 timeout 秒）。戻り値: ロード済みか
function PlayerData.waitForProfile(player: Player, timeout: number?): boolean
	local deadline = os.clock() + (timeout or SaveConfig.InitialDataWaitTimeout)
	while not entries[player] do
		if not player.Parent or os.clock() >= deadline then
			return false
		end
		task.wait(SaveConfig.PollInterval)
	end
	return true
end

-- Profile 全体の複製（未ロードなら nil）
function PlayerData.get(player: Player): ProfileSchema.Profile?
	local entry = entries[player]
	return if entry then ProfileSchema.deepCopy(entry.Profile) else nil
end

-- HUD 用の情報（RemoteSpec.ProfileView の形）
function PlayerData.getView(player: Player)
	local entry = entries[player]
	return if entry then ProfileSchema.toView(entry.Profile) else nil
end

function PlayerData.getDinos(player: Player): { ProfileSchema.OwnedDino }
	local entry = entries[player]
	return if entry then ProfileSchema.deepCopy(entry.Profile.Dinos) else {}
end

function PlayerData.getDino(player: Player, dinoId: string): ProfileSchema.OwnedDino?
	local entry = entries[player]
	if not entry then
		return nil
	end
	local index = ProfileSchema.findDinoIndex(entry.Profile, dinoId)
	return if index then ProfileSchema.deepCopy(entry.Profile.Dinos[index]) else nil
end

function PlayerData.getMoney(player: Player): number?
	local entry = entries[player]
	return if entry then entry.Profile.Money else nil
end

function PlayerData.getLevel(player: Player): number?
	local entry = entries[player]
	return if entry then entry.Profile.Level else nil
end

function PlayerData.getMaxOwnedDinos(player: Player): number?
	local entry = entries[player]
	return if entry then entry.Profile.MaxOwnedDinos else nil
end

function PlayerData.getOwnedCount(player: Player): number
	local entry = entries[player]
	return if entry then #entry.Profile.Dinos else 0
end

-- もう1頭持てるか（テイム開始前・捕獲確定前に必ず確認する）
function PlayerData.canAddDino(player: Player): (boolean, string?)
	local entry, reason = getWritableEntry(player)
	if not entry then
		return false, reason
	end
	return ProfileSchema.canAddDino(entry.Profile)
end

-- ── 公開API: 変更（サーバー権威） ─────────────────────────

-- 恐竜を所持に加える（捕獲成功時に Capture が呼ぶ）。level 省略時は種の InitialLevel。
-- 戻り値: (true, 追加した恐竜の複製) / (false, 理由)
function PlayerData.addDino(player: Player, speciesId: string, level: number?): (boolean, any)
	local entry, reason = getWritableEntry(player)
	if not entry then
		return false, reason
	end
	if type(speciesId) ~= "string" or not DinoConfig.Species[speciesId] then
		return false, "UnknownSpecies"
	end
	local canAdd, limitReason = ProfileSchema.canAddDino(entry.Profile)
	if not canAdd then
		return false, limitReason
	end
	local dino = ProfileSchema.createDino(DinoConfig, HttpService:GenerateGUID(false), speciesId, level, os.time())
	if not dino then
		return false, "UnknownSpecies"
	end
	table.insert(entry.Profile.Dinos, dino)

	if remotes.DinoAdded and player.Parent then
		remotes.DinoAdded:FireClient(player, ProfileSchema.deepCopy(dino))
	end
	PlayerData.DinoAdded:Fire(player, ProfileSchema.deepCopy(dino))
	notifyProfileChanged(player, entry)
	scheduleSave(player, entry)
	return true, ProfileSchema.deepCopy(dino)
end

-- 所持恐竜を手放す（フェーズ1では使う機能なし。将来の「逃がす」等のため）
function PlayerData.removeDino(player: Player, dinoId: string): (boolean, string?)
	local entry, reason = getWritableEntry(player)
	if not entry then
		return false, reason
	end
	local index = if type(dinoId) == "string" then ProfileSchema.findDinoIndex(entry.Profile, dinoId) else nil
	if not index then
		return false, "UnknownDino"
	end
	table.remove(entry.Profile.Dinos, index)

	if remotes.DinoRemoved and player.Parent then
		remotes.DinoRemoved:FireClient(player, dinoId)
	end
	PlayerData.DinoRemoved:Fire(player, dinoId)
	notifyProfileChanged(player, entry)
	scheduleSave(player, entry)
	return true, nil
end

-- 所持恐竜のLvを設定する（種の MaxLevel で頭打ち）。戻り値: (true, 設定後のLv) / (false, 理由)
function PlayerData.setDinoLevel(player: Player, dinoId: string, level: number): (boolean, any)
	local entry, reason = getWritableEntry(player)
	if not entry then
		return false, reason
	end
	local index = if type(dinoId) == "string" then ProfileSchema.findDinoIndex(entry.Profile, dinoId) else nil
	if not index then
		return false, "UnknownDino"
	end
	if not ProfileSchema.isFiniteNumber(level) then
		return false, "InvalidAmount"
	end
	local dino = entry.Profile.Dinos[index]
	-- 種の MaxLevel を超えて上げない。ただし MaxLevel を後から下げた場合でも、今のLvより下へは削らない
	local maxLevel = math.max(ProfileSchema.maxDinoLevel(DinoConfig, dino.Species), dino.Level)
	dino.Level = ProfileSchema.toClampedInteger(level, 1, maxLevel, dino.Level)
	if remotes.DinoUpdated and player.Parent then
		remotes.DinoUpdated:FireClient(player, ProfileSchema.deepCopy(dino))
	end
	PlayerData.DinoUpdated:Fire(player, ProfileSchema.deepCopy(dino))
	scheduleSave(player, entry)
	return true, dino.Level
end

-- お金を増やす（amount は正の整数）。戻り値: (true, 新しい所持金) / (false, 理由)
function PlayerData.addMoney(player: Player, amount: number): (boolean, any)
	local entry, reason = getWritableEntry(player)
	if not entry then
		return false, reason
	end
	if not isPositiveInteger(amount) then
		return false, "InvalidAmount"
	end
	entry.Profile.Money = math.min(entry.Profile.Money + amount, DinoConfig.Player.MaxMoney)
	notifyProfileChanged(player, entry)
	scheduleSave(player, entry)
	return true, entry.Profile.Money
end

-- お金を使う（足りなければ失敗して何も変えない）。戻り値: (true, 新しい所持金) / (false, 理由)
function PlayerData.spendMoney(player: Player, amount: number): (boolean, any)
	local entry, reason = getWritableEntry(player)
	if not entry then
		return false, reason
	end
	if not isPositiveInteger(amount) then
		return false, "InvalidAmount"
	end
	if entry.Profile.Money < amount then
		return false, "InsufficientFunds"
	end
	entry.Profile.Money -= amount
	notifyProfileChanged(player, entry)
	scheduleSave(player, entry)
	return true, entry.Profile.Money
end

-- プレイヤーLvを設定する（上げ方はフェーズ1では未定。1〜Player.MaxLevel に収める）
function PlayerData.setLevel(player: Player, level: number): (boolean, any)
	local entry, reason = getWritableEntry(player)
	if not entry then
		return false, reason
	end
	if not ProfileSchema.isFiniteNumber(level) then
		return false, "InvalidAmount"
	end
	entry.Profile.Level = ProfileSchema.toClampedInteger(level, 1, DinoConfig.Player.MaxLevel, entry.Profile.Level)
	notifyProfileChanged(player, entry)
	scheduleSave(player, entry)
	return true, entry.Profile.Level
end

-- 所持上限を設定する（「拠点の成長」の仕組みが決まったらそこから呼ぶ。未決C）
function PlayerData.setMaxOwnedDinos(player: Player, value: number): (boolean, any)
	local entry, reason = getWritableEntry(player)
	if not entry then
		return false, reason
	end
	if not ProfileSchema.isFiniteNumber(value) then
		return false, "InvalidAmount"
	end
	entry.Profile.MaxOwnedDinos = ProfileSchema.toClampedInteger(
		value,
		1,
		DinoConfig.Player.MaxOwnedDinosHardCap,
		entry.Profile.MaxOwnedDinos
	)
	notifyProfileChanged(player, entry)
	scheduleSave(player, entry)
	return true, entry.Profile.MaxOwnedDinos
end

-- すぐ保存する（待つ）。戻り値: 保存できたか
function PlayerData.saveNow(player: Player): boolean
	local entry = entries[player]
	if not entry or entry.Releasing then
		return false
	end
	return saveEntry(player, entry, false)
end

-- ── 起動 ──────────────────────────────────────────────
function PlayerData.start()
	assert(RunService:IsServer(), "PlayerData はサーバー専用です")
	if started then
		return
	end
	started = true

	for name in RemoteSpec.Definitions do
		remotes[name] = RemoteSpec.get(name)
	end

	local storeName = if RunService:IsStudio() then SaveConfig.StudioDataStoreName else SaveConfig.DataStoreName
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(storeName)
	end)
	if ok then
		store = result
	else
		logWarn("DataStore を取得できません。データは保存されません: " .. tostring(result))
	end

	-- 初期データの問い合わせ（クライアント起動時）
	remotes.RequestInitialData.OnServerInvoke = function(player: Player)
		if not entries[player] then
			-- ロード完了前の連打で待機スレッドが増えないよう、1人につき待機は1本だけにする
			if initialDataWaiting[player] then
				return { Loaded = false }
			end
			initialDataWaiting[player] = true
			local loaded = PlayerData.waitForProfile(player, SaveConfig.InitialDataWaitTimeout)
			initialDataWaiting[player] = nil
			if not loaded then
				return { Loaded = false }
			end
		end
		local entry = entries[player]
		if not entry then
			return { Loaded = false }
		end
		return {
			Loaded = true,
			Profile = ProfileSchema.toView(entry.Profile),
			Dinos = ProfileSchema.deepCopy(entry.Profile.Dinos),
		}
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		releasePlayer(player) -- ロード中なら onPlayerAdded 側が完了後に手放す
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- 自動保存
	task.spawn(function()
		while not closing do
			task.wait(SaveConfig.AutoSaveInterval)
			for player, entry in entries do
				if not entry.Releasing then
					task.spawn(saveEntry, player, entry, false)
				end
			end
		end
	end)

	-- サーバー終了時: 全員分を並行して保存し、終わるまで（最大 BindToCloseTimeout 秒）待つ
	game:BindToClose(function()
		closing = true
		for player in entries do
			task.spawn(releasePlayer, player)
		end
		local deadline = os.clock() + SaveConfig.BindToCloseTimeout
		while (pendingReleases > 0 or next(loading) ~= nil) and os.clock() < deadline do
			task.wait(SaveConfig.PollInterval)
		end
	end)
end

return PlayerData
