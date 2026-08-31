--!strict
-- ゲーム全体のチューニング値。Roblox API を一切参照しない純データなので、
-- サーバ・クライアント・検証器 (verify.luau) の三者がまったく同じ値を共有できる。

local Config = {}

-- ── 試合 ────────────────────────────────────────────────
Config.match = {
	intermission = 8, -- 結果表示〜次の試合までの待ち時間 (秒)
	countdown = 3, -- "3・2・1・GO"
	duration = 60, -- 破壊フェーズの制限時間 (秒)
	resultHold = 5, -- 勝敗演出の長さ (秒)
	minPlayers = 1, -- 1人でもタイムアタックとして成立させる
	maxPlayers = 4, -- アリーナのスロット数
	winPercent = 100, -- ここに到達したら即勝利
}

-- ── アリーナ ────────────────────────────────────────────
-- プレイヤーごとに1スロット。スロットは X 方向に並べ、間隔は
-- 構造物の最大対角より広く取る (瓦礫が隣のスロットへ飛び込まないように)。
Config.arena = {
	slotSpacing = 220, -- スロット中心間の距離 (studs)
	floorY = 0, -- 床の上面 Y。ブロックの底面 0 はここ
	floorSize = 180, -- 1スロットぶんの床の一辺
	spawnBack = 34, -- 構造物中心からどれだけ手前にプレイヤーを出すか
	killY = -18, -- ここより下に落ちた破片は「崩壊済み」として即消去
	fenceHeight = 26, -- 瓦礫の飛散を止める見えない壁の高さ
}

-- ── 構造物 ──────────────────────────────────────────────
-- unit: ブロック1個の基準サイズ。すべてのブロックはこのサイズの直方体。
-- pillarEvery: 何セルおきに柱 (荷重を上へ伝えるブロック) を立てるか。
--   柱と柱の間を埋める壁は「荷重を伝えない詰め物」なので、壁をいくら叩いても
--   上の階は落ちてこない。柱を折って初めて崩れる ＝ これが弱点の見極めになる。
--   support.maxCantilever >= pillarEvery でないと生成直後に自壊するので注意
--   (1辺 pillarEvery の升目の中心が、いちばん柱から遠い点になる)。
Config.build = {
	unit = { x = 3, y = 2.5, z = 3 },
	gap = 0.02, -- 隣接ブロックの間に入れる微小な隙間 (めり込み由来の初期振動を防ぐ)
	kinds = { "Tower", "Fortress", "Aqueduct" }, -- ラウンドごとに巡回する構造物

	-- 荷重を上へ伝えられるブロック種別。ここに無い種別 (= Wall) は詰め物で、
	-- 自分は支えられるが、上のブロックを支えることはできない。
	bearingKinds = {
		Pillar = true,
		Core = true,
		Pier = true,
		Lintel = true,
		Slab = true,
		Deck = true,
		Wall = false,
	},

	Tower = {
		floors = 13,
		cells = { w = 13, d = 13 },
		coursesPerFloor = 2, -- 1フロアあたりの壁の段数
		pillarEvery = 4,
		coreFloors = 7, -- 内側のコア柱が立っている下層フロア数
		taperEvery = 7, -- 何フロアごとに柱1スパンぶん内側へ寄せるか (段塔のシルエット)
		windowChance = 0.10, -- 各フロア下段の壁をこの確率で抜く (見た目 + 局所的な弱点)
	},
	Fortress = {
		floors = 6,
		cells = { w = 13, d = 13 },
		coursesPerFloor = 2,
		pillarEvery = 4,
		towerFloors = 9, -- 四隅の櫓の高さ (フロア数)
		towerCells = 3, -- 櫓の一辺のセル数
		gateFloors = 2, -- 正面の門の高さ (フロア数)。真上のブロックがまぐさ石=弱点になる
		windowChance = 0.08,
	},
	Aqueduct = {
		floors = 8, -- 段数 (アーチの層)
		cells = { w = 31, d = 3 },
		coursesPerFloor = 2,
		archSpan = 5, -- 何セルおきに橋脚を立てるか。archSpan-1 が張り出し幅になる
	},
}

-- ── 支持構造 (Collapse.luau のモデル) ───────────────────
-- vertical: 真下に接している = 支持されている (コスト0)
-- lateral : 同じ段で横に繋がっている = 片持ちで持ちこたえる (コスト1)
-- maxCantilever を超えて張り出した部分は自重で落ちる。
-- この値が小さいほど「柱を1本折るだけで上が総崩れ」になりやすい。
Config.support = {
	maxCantilever = 4,
	contactEpsilon = 0.05, -- 上下の面が接していると見なす許容差 (studs)
	overlapEpsilon = 0.01, -- 平面の重なりを接触と見なす最小面積の代わりの許容差
}

-- ── ハンマー ────────────────────────────────────────────
Config.hammer = {
	reach = 22, -- サーバ側の距離判定 (studs)。クライアントのレイもこの長さ
	cooldown = 0.35, -- 連打の下限間隔 (秒)。サーバでも同じ値で弾く
	blastRadius = 5, -- 打撃点からこの半径のブロックを直接アンカー解除
	keyPartBonus = 2.4, -- キーパーツ (柱・コア) に当てたときの半径倍率
	swingTime = 0.28, -- 振りかぶり〜ヒットまでのクライアント演出の長さ
	graceDistance = 6, -- レイテンシ許容。サーバは reach + これ まで許す
	maxHitsPerSecond = 6, -- これを超える頻度のリクエストは無視 (連打マクロ対策)
}

-- ── 物理 (ラグ対策の要) ─────────────────────────────────
Config.physics = {
	unanchorBudget = 140, -- 1ステップでアンカー解除できる最大数。残りは次ステップへ繰り越す
	maxActiveParts = 900, -- 同時に物理計算するパーツ数の上限。超過分は即座に破片化して消す
	debrisLifetime = 5, -- アンカー解除から強制消去までの秒数
	-- 同時に動いている破片がこの数を超えたら、以降にアンカーを外す破片は
	-- CanCollide = false で落とす。衝突ペア数は個数の2乗で効いてくるので、
	-- 「全部消す」より「重なった時だけ当たり判定を捨てる」方が絵を保てる。
	noCollideAbove = 400,
	impulse = {
		base = 55, -- 打撃点直近に与える初速の大きさ (studs/s 相当 * 質量)
		falloff = 0.055, -- 距離減衰 1/(1+falloff*d)
		upBias = 0.45, -- 外向きベクトルに足す上方向成分
		spin = 22, -- ランダム回転の強さ
		max = 190, -- 1ブロックあたりの上限 (吹っ飛びすぎ防止)
		chain = 0.25, -- 支持を失って連鎖崩壊した (直接叩かれていない) ブロックの倍率
	},
}

-- ── 見た目 ──────────────────────────────────────────────
-- Roblox の Enum を直接持たない (このモジュールは Luau CLI からも読むため)。
-- material は Enum.Material のメンバ名を文字列で持ち、サーバ側で解決する。
-- キーパーツだけ色と材質をはっきり変えているのは演出ではなく仕様で、
-- 「どれが柱か」が見て分からないと弱点の見極めがただの運になる。
Config.appearance = {
	colorJitter = 10, -- ブロックごとの色ゆらぎ (0..255)。のっぺりした面を防ぐ
	blocks = {
		Pillar = { color = { 176, 118, 74 }, material = "Slate" },
		Core = { color = { 206, 138, 62 }, material = "Slate" },
		Pier = { color = { 176, 118, 74 }, material = "Slate" },
		Lintel = { color = { 206, 138, 62 }, material = "Slate" },
		Wall = { color = { 150, 152, 158 }, material = "Concrete" },
		Slab = { color = { 128, 130, 138 }, material = "Concrete" },
		Deck = { color = { 138, 140, 148 }, material = "Concrete" },
	},
	fallback = { color = { 140, 142, 150 }, material = "Concrete" },
}

-- ── 進行度 ──────────────────────────────────────────────
-- 崩壊率 = (完全に落ちた数 + アンカー解除済みだが空中にある数 * freeWeight) / 総数
-- freeWeight があるおかげで、崩れ始めた瞬間にゲージが跳ねて気持ちいい。
Config.progress = {
	interval = 0.2, -- サーバ→クライアントの一括通知間隔 (秒)
	freeWeight = 0.35,
	-- 「完全に落ちた」と見なす条件。低い位置のブロックは外した瞬間から
	-- settleY より下にいるので、高さだけで判定すると転がる前に消えてしまう。
	-- 落下時間と速度も見て、本当に落ち着いてから片付ける。
	settleY = 6, -- この高さ未満で、かつ
	settleSpeed = 6, -- この速度未満で、かつ
	settleDelay = 0.9, -- アンカー解除からこの秒数が経っていること
}

-- ── 演出 (すべてクライアント側でローカル生成) ───────────
Config.juice = {
	hitStop = 0.05, -- ヒット時にカメラを止める時間 (秒)
	shakeTrauma = 0.55, -- 通常ヒットで加算される trauma (0..1)
	shakeKeyTrauma = 0.95, -- キーパーツ破壊時
	shakeDecay = 1.7, -- trauma の減衰 (1/s)
	shakeAmplitude = 2.6, -- trauma=1 のときの最大並進 (studs)
	shakeAngle = 5.5, -- trauma=1 のときの最大回転 (度)
	shakeFrequency = 22, -- ノイズの進む速さ
	fovPunch = 6, -- ヒット時の FOV 変化量 (度)
	fovRecover = 7, -- FOV が戻る速さ (1/s)
	dustPerHit = 26, -- 1ヒットあたりの粉塵パーティクル数
	-- 音源アセットを持ち込みたい場合だけ rbxassetid:// を入れる。
	-- 空文字のままなら音は鳴らない (このリポジトリは外部アセット0本で成立させる方針)。
	sounds = { hit = "", collapse = "", win = "" },
}

return Config
