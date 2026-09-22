--!strict
-- Dino Catchers の全設定値（唯一の置き場）。
--
-- ルール（CLAUDE.md 5章）:
--   ・数値・種類などの設定値はここ1か所だけに書く。他のスクリプトで数値を直書きしない。
--   ・値の追加・変更は data-architect に依頼する（各セクションの「担当」は主な利用者の目安）。
--
-- Roblox API（Color3 / Vector3 / RunService など）を一切参照しない純データにしている。
-- そのためサーバー・クライアント・CLI の検証スクリプトすべてで同じ値を読める。
--   色   … { R, G, B }（0〜255）。使う側で Color3.fromRGB(table.unpack(c)) に変換する
--   大きさ … { X, Y, Z }（studs）。使う側で Vector3.new(table.unpack(s)) に変換する
--
-- 単位: 距離 = studs、時間 = 秒、速さ = studs/秒、お金 = 整数（コイン）

local DinoConfig = {}

-- ── 所持上限（決定B） ────────────────────────────────────
-- プレイヤーごとの保存データ MaxOwnedDinos の初期値。
-- 所持上限の判定は必ずプレイヤーデータの MaxOwnedDinos を見ること（この値を直接比較しない）。
DinoConfig.BaseMaxOwnedDinos = 10

-- ── プレイヤー ──────────────────────────────────────────
DinoConfig.Player = {
	StartingMoney = 100, -- 初期所持金
	StartingLevel = 1, -- 初期プレイヤーLv
	MaxLevel = 100, -- プレイヤーLv上限（上げ方はフェーズ1では未定）
	MaxMoney = 999999999, -- 所持金の上限（桁あふれ・不正値対策）
	-- MaxOwnedDinos を将来増やせる上限の安全弁（壊れた値で巨大化しないように）
	MaxOwnedDinosHardCap = 200,
}

-- ── 恐竜の種類 ──────────────────────────────────────────
-- キー（= Id）はセーブデータに保存される。一度公開したら名前を変えないこと。
-- 担当: dino-ai（見た目・移動）/ capture-system（テイム・報酬）/ ui-designer（表示名）
export type SpeciesDef = {
	Id: string,
	DisplayName: string, -- 画面に出す名前
	Diet: string, -- "Herbivore"（草食）/ "Carnivore"（肉食）
	SizeClass: string, -- "Small" / "Medium" / "Large"
	-- 仮モデル（ブロック組み）用。本番モデル差し替え後は ModelName で ServerStorage.DinoModels から探す
	ModelName: string,
	PlaceholderColor: { number }, -- 胴体の色 { R, G, B }
	PlaceholderAccentColor: { number }, -- 頭・模様などの差し色 { R, G, B }
	PlaceholderBodySize: { number }, -- 胴体の大きさ { X, Y, Z }
	-- 移動（サーバー側で動かす）
	WalkSpeed: number, -- 通常の歩く速さ
	RunSpeed: number, -- 逃げる・急ぐときの速さ（フェーズ1で使わなくてもよい）
	WanderRadius: number, -- 野生時: 出現地点からうろつく半径
	RanchWanderRadius: number, -- 飼育時: 拠点の中心からうろつく半径。うろつく先は RanchWorld.clampToRanch で柵の内側に切り詰める
	WanderPauseMin: number, -- 目的地に着いてから次に歩き出すまでの待ち時間（最小）
	WanderPauseMax: number, -- 同（最大）
	-- テイム
	TameTime: number, -- 狙い続けて 0→100% になるまでの秒数（進捗の溜まる速さ = 100 / TameTime）
	TameRange: number, -- テイム銃の有効射程（この種を狙えるプレイヤーとの距離）
	-- 成長
	InitialLevel: number, -- 捕獲直後のLv
	MaxLevel: number, -- この種のLv上限
	-- 報酬
	CaptureReward: number, -- 捕獲成功時にもらえるお金
	-- 出現
	SpawnWeight: number, -- 野生出現の重み（大きいほど出やすい）
}

DinoConfig.Species = {
	Protoceratops = {
		Id = "Protoceratops",
		DisplayName = "プロトケラトプス",
		Diet = "Herbivore",
		SizeClass = "Small",
		ModelName = "Protoceratops",
		PlaceholderColor = { 196, 164, 104 }, -- 砂色
		PlaceholderAccentColor = { 140, 96, 60 },
		PlaceholderBodySize = { 2, 2, 4 },
		WalkSpeed = 8,
		RunSpeed = 16,
		WanderRadius = 40,
		RanchWanderRadius = 30,
		WanderPauseMin = 2,
		WanderPauseMax = 6,
		TameTime = 5,
		TameRange = 80,
		InitialLevel = 1,
		MaxLevel = 30,
		CaptureReward = 20,
		SpawnWeight = 3,
	},
	Parasaurolophus = {
		Id = "Parasaurolophus",
		DisplayName = "パラサウロロフス",
		Diet = "Herbivore",
		SizeClass = "Medium",
		ModelName = "Parasaurolophus",
		PlaceholderColor = { 90, 140, 170 }, -- くすんだ青
		PlaceholderAccentColor = { 220, 120, 60 }, -- とさか
		PlaceholderBodySize = { 4, 4, 9 },
		WalkSpeed = 10,
		RunSpeed = 20,
		WanderRadius = 60,
		-- 初期の柵の内側は 40 - FenceMargin 4 = 36。うろつく先は RanchWorld.clampToRanch で柵の内側に切り詰める
		RanchWanderRadius = 36,
		WanderPauseMin = 3,
		WanderPauseMax = 8,
		TameTime = 10,
		TameRange = 100,
		InitialLevel = 1,
		MaxLevel = 30,
		CaptureReward = 50,
		SpawnWeight = 1,
	},
} :: { [string]: SpeciesDef }

-- 表示・一覧用の並び順（辞書は順番が保証されないため）
DinoConfig.SpeciesOrder = { "Protoceratops", "Parasaurolophus" }

-- ── 恐竜の成長 ──────────────────────────────────────────
-- 担当: 今後の育成機能。フェーズ1ではLvの保存だけ行い、上げ方は未定。
DinoConfig.DinoGrowth = {
	AbsoluteMaxLevel = 100, -- どの種でも超えない上限（保存データ検証用）
}

-- ── テイム（テイム銃） ──────────────────────────────────
-- 担当: capture-system（サーバー判定）/ ui-designer（進捗バー）
DinoConfig.Taming = {
	ProgressMax = 100, -- 進捗は 0〜ProgressMax。ProgressMax に達したら捕獲
	-- 狙いが外れたとき
	DecayDelay = 0.5, -- 最後に有効な報告を受けてから減衰が始まるまでの猶予（秒）
	DecayPerSecond = 25, -- 減衰の速さ（進捗/秒）。0 まで減ったらテイム状態を解除
	-- クライアント → サーバー の報告（RequestTame）
	ClientReportInterval = 0.2, -- クライアントが狙っている間に報告を送る間隔（秒）
	MinRequestInterval = 0.1, -- サーバーが受け付ける最小間隔（これより短い連打は無視）
	-- サーバー側の検証（不正対策）
	MaxServerRange = 120, -- サーバーが受け付ける最大射程。種の TameRange もこの値で頭打ちにする
	RangeTolerance = 6, -- 通信遅延による位置ズレの許容量（TameRange にこれを足して判定）
	MaxAimAngleDegrees = 25, -- キャラの向きと恐竜への方向のズレ許容（任意で使用）
	RequireLineOfSight = true, -- サーバーで射線（Raycast）を確認するか
	-- 同時テイム
	MaxSimultaneousTargetsPerPlayer = 1, -- 1人が同時に進捗を溜められる恐竜の数
	-- 通知（TameProgressChanged）
	ProgressBroadcastInterval = 0.1, -- 進捗変化をクライアントへ送る最短間隔（秒）
}

-- ── 野生恐竜の出現 ──────────────────────────────────────
-- 担当: dino-ai
DinoConfig.Wild = {
	MaxWildDinos = 12, -- ワールド全体で同時に出現している野生恐竜の上限
	RespawnDelay = 15, -- 捕獲などで減ってから補充されるまでの秒数
	MinSpawnDistanceFromRanch = 80, -- 拠点の中心から最低これだけ離れた場所に出す
	MinSpawnDistanceFromPlayer = 40, -- プレイヤーの目の前に急に湧かないための距離
	-- 出現地点は Workspace 内の出現範囲（world-builder が用意）から選ぶ想定
}

-- ── 拠点（ワールド） ────────────────────────────────────
-- 担当: world-builder（配置）/ dino-ai（飼育恐竜の移動範囲）
-- ※下記は仮の値。world-builder の実装に合わせて data-architect に変更を依頼すること。
DinoConfig.Ranch = {
	-- 柵は同じ区画（Plot）を並べて広げる作り（決定A）
	FencePlotSize = 40, -- 区画1枚の一辺（studs、正方形）
	InitialPlotsX = 2, -- 初期の区画の並び（横）
	InitialPlotsZ = 2, -- 初期の区画の並び（縦）
	FenceHeight = 5, -- 柵の高さ
	FenceMargin = 4, -- 飼育恐竜が柵から離れて歩く余白
	-- 性能目標（CLAUDE.md 5章）: 拠点に恐竜30頭が同時にいても重くならないこと
	PerformanceTargetDinos = 30,
	-- 飼育恐竜の移動更新（サーバー）の間隔。30頭を毎フレーム動かさないための目安
	AIUpdateInterval = 0.25,
	-- 拠点スロット（1サーバー内の各プレイヤーの拠点の置き場）と入口
	SlotCount = 6, -- 拠点スロットの数（= 1サーバーで拠点を持てる最大人数）
	SlotSpacing = 168, -- スロット1つ分の敷地（正方形）の一辺。初期2x2区画の周りに1区画ずつ足せる広さ
	RanchBackGap = 16, -- スロット敷地の奥と外周の丘との間の余白
	PlazaDepth = 32, -- スロットの前（北側）を東西に走る広場・通路の奥行き
	WildEdgeBuffer = 40, -- 広場の端から野生の出現範囲までの最低距離
	GateWidth = 10, -- 柵の入口（すき間）の幅
	PostSpacing = 10, -- 柵の杭の間隔
	SpawnOffsetFromGate = 10, -- 入口の外側、この距離の位置を「そのスロットの出入り地点」にする
}

-- ── ワールド（地形・池・岩・木・出現位置） ─────────────────
-- 担当: world-builder（Workspace.Ranch の WorldLayout / RanchWorld / RanchBuilder が使う）
DinoConfig.World = {
	-- 地図の大きさ・地形
	Seed = 20260922, -- 地形・岩・木の配置の乱数シード（毎回同じ地図になる）
	MapSizeX = 1152, -- マップの東西の長さ（中心が原点）。8の倍数
	MapSizeZ = 896, -- マップの南北の長さ。8の倍数
	GroundLevel = 0, -- 拠点・広場の平らな地面の高さ。4の倍数
	TerrainBottom = -24, -- 地形の底。4の倍数
	HillAmplitude = 7, -- ゆるい起伏の高さ
	HillScale = 170, -- ゆるい起伏の横幅（大きいほどなだらか）
	DetailAmplitude = 2.5, -- 細かいでこぼこの高さ
	DetailScale = 45, -- 細かいでこぼこの横幅
	EdgeHillWidth = 64, -- マップの外周を囲う丘の幅（この内側が歩き回れる範囲）
	EdgeHillHeight = 34, -- 外周の丘の高さ
	FlattenBlend = 48, -- 拠点エリアの平地から自然地形へなめらかにつなぐ距離
	BoundaryWallHeight = 200, -- マップ端の見えない壁の高さ
	-- 地表の素材（傾き = 高さの差 / 距離）
	RockMaterialSlope = 0.9, -- これより急な斜面は岩肌（Rock）
	GroundMaterialSlope = 0.55, -- これより急な斜面は土（Ground）。それ以下は草（Grass）
	-- 池
	WaterLevel = -4, -- 池の水面の高さ（ボクセルの境目に合わせて4の倍数）
	PondCount = 2, -- 池の数
	PondRadiusMin = 22,
	PondRadiusMax = 36,
	PondDepth = 6, -- 水面から池の底までの深さ
	PondEdgeMargin = 40, -- 野生エリアの端から池の縁までの最低距離（池の半径に足す）
	PondSpacing = 80, -- 池どうしの間隔（池の半径に足す）
	PondShoreSlope = 0.25, -- 池の縁から外側へ地面が上がる傾き
	-- 岩（Terrain の Rock 球）
	RockCount = 14, -- 岩の数
	RockRadiusMin = 3,
	RockRadiusMax = 7,
	RockEdgeMargin = 16, -- 野生エリアの端から岩の中心までの最低距離
	RockPondGap = 16, -- 池と岩の間隔（岩の半径に足す）
	RockSpacing = 30, -- 岩どうしの間隔（岩の半径に足す）
	-- 木（パーツ2個）
	TreeCount = 26, -- 木の数
	TreeEdgeMargin = 8, -- 野生エリアの端から木までの最低距離
	TreePondGap = 14, -- 池と木の間隔
	TreeRockGap = 12, -- 岩と木の間隔
	TreeSpacing = 24, -- 木どうしの間隔
	TreeTrunkRadius = 1.5, -- 幹の半径（出現判定用）
	TreeTrunkHeightMin = 8, -- 幹の高さ（最小）
	TreeTrunkHeightMax = 13, -- 幹の高さ（最大）
	TreeCanopySizeMin = 9, -- 樹冠の大きさ（最小）
	TreeCanopySizeMax = 15, -- 樹冠の大きさ（最大）
	-- 野生恐竜の出現地点
	WildMaxSlope = 0.6, -- 野生恐竜を出してよい地面の傾きの上限
	WildSpawnObstacleMargin = 3, -- 岩・木から野生恐竜の出現地点までの余白（障害物の半径に足す）
	-- プレイヤーの出現位置
	SlotSpawnHeightOffset = 3, -- スロットの出入り地点に出すときの地面からの高さ
	PlayerSpawnHeightOffset = 4, -- 共通の出現地点に出すときの地面からの高さ
	PlayerSpawnPadSize = 12, -- 共通の出現地点（SpawnLocation）の一辺
	-- 看板
	RanchSignMaxDistance = 120, -- 拠点の看板（BillboardGui）が見える最大距離
	-- ワールドの完成待ち（RanchWorld.waitUntilReady など）
	ReadyTimeout = 60, -- ワールドの完成を待つ最大秒数
	ReadyPollInterval = 0.1, -- 完成したかを確認する間隔（秒）
}

-- ── 表示用の文字列 ──────────────────────────────────────
-- 担当: world-builder / ui-designer。string.format で使う
DinoConfig.Text = {
	VacantRanchLabel = "空き拠点 %d", -- 持ち主のいない拠点スロットの看板（%d = スロット番号）
}

-- ── セーブ（DataStore） ─────────────────────────────────
-- 担当: data-architect のみ（ServerScriptService.Data）
-- 本番とStudioテストでストア名を分ける。どちらを使うかはサーバー側で
-- RunService:IsStudio() を見て決める（このモジュールは純データのため）。
DinoConfig.Save = {
	DataStoreName = "DinoCatchers_PlayerData_v1", -- 本番。名前を変える・消す操作は禁止
	StudioDataStoreName = "DinoCatchers_PlayerData_STUDIO_v1", -- Studio テスト用
	KeyPrefix = "Player_", -- キー = KeyPrefix .. UserId
	AutoSaveInterval = 120, -- 自動保存の間隔（秒）
	ImportantChangeSaveDelay = 5, -- 捕獲など大事な変化のあと、まとめて保存するまでの秒数
	MaxRetries = 5, -- DataStore 呼び出しの最大試行回数
	RetryBaseDelay = 1, -- リトライ待ち時間の基準（試行ごとに倍）
	-- 別サーバーで同じプレイヤーのデータを同時に扱わないためのロック
	SessionLockTimeout = 1800, -- この秒数以上更新のないロックは放置されたものとみなす
	SessionLockRetryCount = 5, -- 他サーバーのロックが外れるのを待つ回数
	SessionLockRetryDelay = 4, -- 同待つ間隔（秒）。超えたらロックを引き継ぐ
	BindToCloseTimeout = 25, -- サーバー終了時に保存を待つ最大秒数（Roblox の上限は30秒）
	InitialDataWaitTimeout = 15, -- RequestInitialData でロード完了を待つ最大秒数
	PollInterval = 0.1, -- ロード完了・保存完了などを確認しながら待つときの間隔（秒）
}

-- ── 通信（Remotes） ─────────────────────────────────────
-- 担当: data-architect（Shared.RemoteSpec が使う）
DinoConfig.Net = {
	RemoteWaitTimeout = 30, -- RemoteSpec.get が ReplicatedStorage.Remotes 内の Remote を待つ最大秒数
}

return DinoConfig
