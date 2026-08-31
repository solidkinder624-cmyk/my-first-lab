--!strict
-- ゲーム全体のチューニング値。Roblox API を一切参照しない純データなので、
-- サーバ・クライアント・検証器 (verify.luau) の三者がまったく同じ値を共有できる。

local Config = {}

-- ── マップ ──────────────────────────────────────────────
Config.tileSize = 8 -- 1タイルの一辺 (studs)
Config.mazeCells = { w = 12, h = 12 } -- 迷路のセル数 → タイル数は 2n+1
Config.braid = 0.28 -- 行き止まりをこの割合だけ潰してループを作る (鬼ごっこは袋小路が多いと詰むため)
Config.wallHeight = 14

-- ── プレイヤー ──────────────────────────────────────────
Config.player = {
	radius = 1.6,
	eyeHeight = 4.6,
	crouchEyeHeight = 2.6,
}

-- ── 移動 ────────────────────────────────────────────────
Config.move = {
	walkSpeed = 14,
	sprintSpeed = 24,
	crouchSpeed = 6.5,
	accel = 110, -- 目標速度への追従の速さ (studs/s^2)
	friction = 14, -- 入力が無いときの減速係数 (1/s)
	gravity = 130,
	jumpVelocity = 42,
	maxStepDelta = 1 / 20, -- 1ステップで進める最大時間。これ以上はサーバ側で切り捨てる
}

-- ── スタミナ (ダッシュ/ジャンプ = 音を出す行為 のコスト) ──
Config.stamina = {
	max = 100,
	sprintDrain = 19, -- /s
	jumpCost = 14,
	regen = 9, -- /s (立ち・歩き時)
	crouchRegen = 17, -- /s (しゃがみは静かで回復も速い = 潜伏の報酬)
	sprintMinimum = 8, -- これ未満ではダッシュを開始できない
}

-- ── 痕跡 (この情報だけが他プレイヤーへレプリケートされる) ──
-- distance: 何スタッド進むごとに足跡を出すか
-- radius  : この距離内のプレイヤーにだけ送信する (可聴半径)
-- life    : クライアント側での表示寿命 (秒)
Config.trace = {
	Step = { -- 歩き
		distance = 4.6,
		radius = 46,
		life = 3.4,
		size = 1.0,
	},
	SprintStep = { -- ダッシュ (足跡が濃く・広く・頻繁)
		distance = 3.1,
		radius = 74,
		life = 2.6,
		size = 1.45,
	},
	Jump = { -- 踏み切りの振動波紋
		radius = 105,
		life = 0.85,
		size = 7, -- 見た目の円盤直径(studs)。プレイヤーの目の高さ(約4.6)より大きくしすぎると
		-- 一人称視点で画面が波紋一色に覆われてしまうため、聴覚範囲(radius)とは独立して小さく保つ
	},
	Land = { -- 着地の振動波紋 (踏み切りより大きい = 飛ぶより降りる方が目立つ)
		radius = 125,
		life = 1.0,
		size = 9,
	},
	Pickup = { -- 宝を拾った瞬間の波紋 (取ると居場所がバレる = リスク/リターン)
		radius = 200,
		life = 1.4,
		size = 13,
	},
	Tag = { -- タッチ成立の波紋
		radius = 240,
		life = 1.6,
		size = 15,
	},
}

-- ── ネットワーク ────────────────────────────────────────
Config.net = {
	tickRate = 30, -- サーバのシミュレーション周波数 (固定ステップ)
	reconcileRate = 10, -- 自分の権威座標を本人へ送り返す頻度
	maxInputBuffer = 8, -- 入力バッファ上限。溢れたら捨てる (フラッド対策)
	maxCatchUpPerTick = 2, -- 1tickで消化する入力の上限 (速度ハック対策の要)
}

-- ── ラウンド ────────────────────────────────────────────
Config.round = {
	intermission = 12,
	hideTime = 20, -- かくれんぼ: 鬼が動けない時間
	duration = 210,
	tagRadius = 4.5, -- サーバ側の接触判定距離
	pickupRadius = 4.0,
	treasureCount = 6,
	minPlayers = 2,
}

return Config
