--!strict
-- ゲーム全体のチューニング値。Roblox API を一切参照しない純データなので、
-- サーバ・クライアント・検証器 (verify.luau) の三者がまったく同じ値を共有できる。

local Config = {}

-- ── ワールド ────────────────────────────────────────────
Config.world = {
	size = 4000, -- マップ一辺 (studs)。中央空港が原点
	ceiling = 1500, -- 高度上限 (studs)。これを超えると強制的に機首が下がる
	killY = -400, -- ここより下に落ちたら中央空港へ強制帰還
}

-- ── 機体クラス ──────────────────────────────────────────
-- maxSpeed/accel: studs/s, studs/s^2。turnRate: 度/秒 (ピッチ・ロール・ヨー共通の基準値)
-- price は所持金 (お金の単位)。Trainer は初期所持機で price = 0。
Config.aircraft = {
	Trainer = {
		displayName = "練習機",
		price = 0,
		maxSpeed = 140,
		accel = 60,
		turnRate = 70,
		cargoCapacity = 0,
		fuelCapacity = 100,
	},
	Cargo = {
		displayName = "貨物輸送機",
		price = 8000,
		maxSpeed = 110,
		accel = 42,
		turnRate = 45,
		cargoCapacity = 4,
		fuelCapacity = 160,
	},
	Stunt = {
		displayName = "曲技機",
		price = 15000,
		maxSpeed = 175,
		accel = 78,
		turnRate = 130,
		cargoCapacity = 1,
		fuelCapacity = 90,
	},
}
Config.defaultAircraft = "Trainer"

-- ── 飛行モデル (FlightModel.luau が使う共通パラメータ) ────
Config.flight = {
	minSpeed = 8, -- これ未満は失速扱い (stall)。地上ではこの限りではない
	stallSinkRate = 26, -- 失速時に追加でかかる沈下速度 (studs/s^2)
	gravity = 24, -- 通常時の重力加速度
	drag = 0.02, -- 速度に比例する空気抵抗係数 (1/s)
	throttleRate = 0.9, -- R2/L2 を倒し続けたときの毎秒スロットル変化量 (0..1 スケール)
	pitchLimit = 75, -- ピッチ角の可動範囲 (度)。宙返りはさせない
	rollLimit = 180,
	boost = {
		multiplier = 1.6, -- スロットル出力倍率
		duration = 2.2, -- 秒
		cooldown = 6.5, -- 秒
	},
	fuelBurnRate = 1.1, -- スロットル1.0・通常巡航時の燃料消費 (単位/秒)
	fuelBurnBoostMultiplier = 2.4,
	groundHeight = 0, -- 地上判定の高さ (studs)
	takeoffMinSpeed = 34, -- これ未満では離陸(浮上)できない
	takeoffLiftVelocity = 8, -- 離陸速度到達時に与える上昇初速 (studs/s)
}

-- ── ガンパッド入力 (Roblox Enum は client 側でのみ解決) ───
Config.gamepad = {
	stickDeadzone = 0.12,
	inputHz = 20, -- Client → Server の送信頻度上限
}

-- ── 配達ミッション ──────────────────────────────────────
Config.mission = {
	baseReward = 60,
	rewardPerStud = 0.12,
	rewardPerCargo = 90, -- 積載1単位あたりの追加報酬
	timeBonusPerSecond = 1.5, -- 制限時間を余して届けたときのボーナス (秒あたり)
	timeLimitBase = 30, -- 秒
	timeLimitPerStud = 0.045, -- 距離に応じて制限時間を延ばす
	weatherMultiplierRange = { min = 0.85, max = 1.35 }, -- 天候による報酬倍率
	maxActiveMissions = 3, -- 同時受注上限 (貨物ベイ拡張で増える)
	dropRadius = 14, -- 着地判定半径 (studs)。この範囲内かつ着陸装置展開で成功
}

-- ── アップグレード ──────────────────────────────────────
Config.upgrades = {
	Engine = { maxLevel = 5, costBase = 1200, costGrowth = 1.55, accelBonusPerLevel = 0.12 },
	Fuel = { maxLevel = 5, costBase = 900, costGrowth = 1.5, capacityBonusPerLevel = 0.2 },
	Cargo = { maxLevel = 3, costBase = 2000, costGrowth = 1.7, missionSlotBonusPerLevel = 1 },
}

-- ── 不正対策 (AntiCheat.luau) ────────────────────────────
Config.anticheat = {
	speedTolerance = 1.25, -- 機体の maxSpeed に対して許容する倍率 (ラグ・ブースト込み)
	graceDistance = 20, -- 上の速度上限に加えて許容する固定距離 (studs)
	maxStepDelta = 0.5, -- 1回の入力適用で認める最大 dt (巨大 dt speedhack 対策)
	minInputInterval = 1 / Config.gamepad.inputHz * 0.5, -- これより短い間隔の連投は弾く
}

-- ── サーバー配信 ────────────────────────────────────────
Config.broadcast = {
	rateHz = 12, -- 他プレイヤーへの位置ブロードキャスト頻度
}

return Config
