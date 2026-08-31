-- 構造物の生成・アンカー一括制御・瓦礫の後始末。
--
-- 「何が崩れるか」を決めるのは Collapse (純ロジック)。ここがやるのは
-- その決定を Roblox の Part に反映することと、それを何フレームかに分けて
-- 実行することだけ。ラグ対策の実体はこの分割にある:
--
--   * 1回の打撃で数百個のアンカーが同時に外れると、その1フレームで
--     物理エンジンが数百個の剛体を新規に受け入れることになり必ずカクつく。
--     Config.physics.unanchorBudget 個ずつに分けて、打撃点から近い順に外す。
--     副作用として、崩壊が外へ波紋のように広がって見える (演出としても得)。
--   * 同時に動く破片が増えすぎたら、新しい破片の当たり判定を切る。
--     衝突ペアは個数の2乗で増えるので、ここを抑えるのがいちばん効く。
--   * 落ちきった破片は即座に消す。放置すると床の上に数千個の剛体が残る。
--   * 破片の物理演算の所有権は「その構造物の持ち主」に渡す。4人対戦なら
--     4台のクライアントに物理が分散し、サーバは判定だけを持つ。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DominoCrash")
local Config = require(Shared.Config)
local Blueprint = require(Shared.Blueprint)
local Collapse = require(Shared.Collapse)

local ArenaBuilder = require(script.Parent.ArenaBuilder)

local StructureManager = {}
StructureManager.__index = StructureManager

-- 同時に保持するテンプレート数。現ラウンド + 先読み1件 + 余裕1件。
local TEMPLATE_CACHE = 3

local function materialOf(name: string): Enum.Material
	local ok, material = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and material then material else Enum.Material.Concrete
end

local function colorOf(spec, jitterSeed: number, jitter: number): Color3
	-- id から決まるゆらぎ。乱数を使わないので、同じ構造物は必ず同じ見た目になる。
	local n = (jitterSeed * 2654435761) % 1024 / 1024 - 0.5
	local delta = n * jitter
	return Color3.fromRGB(
		math.clamp(spec.color[1] + delta, 0, 255),
		math.clamp(spec.color[2] + delta, 0, 255),
		math.clamp(spec.color[3] + delta, 0, 255)
	)
end

function StructureManager.new(remotes)
	return setmetatable({
		remotes = remotes,
		templates = {}, -- "kind:seed" → { model, structure }
		templateOrder = {}, -- 作った順。古いものから捨てる
		live = {}, -- slotIndex → 生きている構造物
	}, StructureManager)
end

-- ── テンプレートの用意 ──────────────────────────────────
-- 同じラウンドでは全員が同じ構造物を壊すので、Part を1組だけ作って
-- 人数ぶん Clone する。Instance.new を数千回まわすのは Clone より桁で遅い。
function StructureManager:prepare(kind: string, seed: number)
	local key = kind .. ":" .. seed
	local cached = self.templates[key]
	if cached then
		return cached
	end

	local blueprint = Blueprint.generate(kind, seed, Config.build)
	local structure = Collapse.compile(blueprint.blocks, Config.support)

	local model = Instance.new("Model")
	model.Name = "Structure_" .. key
	for _, block in blueprint.blocks do
		local spec = Config.appearance.blocks[block.kind] or Config.appearance.fallback
		local part = Instance.new("Part")
		part.Name = "B" .. block.id
		part.Size = Vector3.new(block.sx, block.sy, block.sz)
		part.Position = Vector3.new(block.cx, block.cy, block.cz)
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false -- Touched を一切使わないので切る (数千個ぶんの節約)
		part.CastShadow = false -- 影の計算も数千個ぶんは重い。アリーナ全体の影で十分
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = materialOf(spec.material)
		part.Color = colorOf(spec, block.id, Config.appearance.colorJitter)
		part.CollisionGroup = ArenaBuilder.GROUP_STRUCTURE
		part.Parent = model
	end
	-- Clone 後に PivotTo でスロットへ運ぶ。原点を明示しておく。
	model.WorldPivot = CFrame.new(0, 0, 0)

	local entry = { model = model, structure = structure, blueprint = blueprint }
	self.templates[key] = entry
	table.insert(self.templateOrder, key)

	-- テンプレートは数千個の Part を抱えているので、貯め込むとサーバのメモリが
	-- 際限なく増える。「今のラウンド」と「先読みした次のラウンド」があれば十分。
	-- Clone 済みの構造物はテンプレートを参照していないので、破棄しても影響しない。
	while #self.templateOrder > TEMPLATE_CACHE do
		local oldest = table.remove(self.templateOrder, 1) :: string
		local victim = self.templates[oldest]
		if victim then
			victim.model:Destroy()
			self.templates[oldest] = nil
		end
	end

	return entry
end

-- ── 設置 ────────────────────────────────────────────────
function StructureManager:spawn(slotIndex: number, kind: string, seed: number, owner: Player?, parent: Instance)
	self:despawn(slotIndex)

	local template = self:prepare(kind, seed)
	local origin = ArenaBuilder.slotOrigin(slotIndex)
	local model = template.model:Clone()
	model.Name = "Slot" .. slotIndex .. "_" .. kind

	local partOf = table.create(template.structure.count)
	local idOf = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local id = tonumber(string.sub(child.Name, 2))
			if id then
				partOf[id] = child
				idOf[child] = id
			end
		end
	end

	model:PivotTo(CFrame.new(origin))
	model.Parent = parent

	local live = {
		slotIndex = slotIndex,
		kind = kind,
		seed = seed,
		owner = owner,
		origin = origin,
		model = model,
		structure = template.structure,
		run = Collapse.newRun(template.structure),
		partOf = partOf,
		idOf = idOf,
		queue = {}, -- アンカー解除待ち { id, impulse }
		queueHead = 1,
		active = {}, -- 落下中の破片 { part, at }
		total = template.structure.count,
		fallen = 0,
	}
	self.live[slotIndex] = live
	return live
end

function StructureManager:despawn(slotIndex: number)
	local live = self.live[slotIndex]
	if not live then
		return
	end
	live.model:Destroy()
	self.live[slotIndex] = nil
end

function StructureManager:despawnAll()
	for slotIndex in self.live do
		self:despawn(slotIndex)
	end
end

function StructureManager:get(slotIndex: number)
	return self.live[slotIndex]
end

function StructureManager:blockIdOf(live, part: BasePart): number?
	return live.idOf[part]
end

-- ── 打撃 ────────────────────────────────────────────────
-- worldPoint は着弾点 (ワールド座標)。構造物ローカルに直してから
-- 純ロジックへ渡し、返ってきた「崩れるブロック」をキューに積む。
function StructureManager:hit(live, worldPoint: Vector3)
	local p = worldPoint - live.origin
	local result = Collapse.hit(live.run, p.X, p.Y, p.Z, Config.hammer.blastRadius, Config.hammer, Config.physics)

	-- 打撃点から近い順に外す。予算で分割されるので、そのまま
	-- 「衝撃が外へ広がっていく」順序になる。
	local pending = {}
	local function push(ids)
		for _, id in ids do
			local block = live.structure.blocks[id]
			local dx, dy, dz = block.cx - p.X, block.cy - p.Y, block.cz - p.Z
			table.insert(pending, { id = id, d2 = dx * dx + dy * dy + dz * dz })
		end
	end
	push(result.direct)
	push(result.chain)
	table.sort(pending, function(a, b)
		if a.d2 == b.d2 then
			return a.id < b.id
		end
		return a.d2 < b.d2
	end)

	for _, entry in pending do
		table.insert(live.queue, { id = entry.id, impulse = result.impulse[entry.id] })
	end

	return result
end

-- ── アンカー解除 ────────────────────────────────────────
local function release(live, id: number, impulse): boolean
	local part = live.partOf[id]
	if not part or not part.Parent then
		-- Part が既に無い (何らかの理由で消えた) ぶんは、崩壊済みとして数えておく。
		-- ここを落とすと崩壊率が 100% に届かなくなり、決着がつかなくなる。
		live.fallen += 1
		return false
	end

	part.Anchored = false
	part.CanQuery = false -- 崩れた破片はハンマーのレイに映らない (立っている物だけ狙える)
	part.CollisionGroup = ArenaBuilder.GROUP_DEBRIS
	if #live.active >= Config.physics.noCollideAbove then
		part.CanCollide = false
	end

	if impulse then
		-- ApplyImpulse は「質量 x 速度」を要求するので、狙った初速に質量を掛ける
		local mass = part.AssemblyMass
		part:ApplyImpulse(Vector3.new(impulse.vx, impulse.vy, impulse.vz) * mass)
		part.AssemblyAngularVelocity = Vector3.new(impulse.wx, impulse.wy, impulse.wz)
	end

	-- 物理演算の所有権をその構造物の持ち主へ。自分の目の前の崩壊が
	-- ラウンドトリップ待ちにならないぶん、体感がまるで変わる。
	if live.owner and live.owner.Parent then
		pcall(function()
			part:SetNetworkOwner(live.owner)
		end)
	end

	table.insert(live.active, { part = part, at = os.clock() })
	return true
end

-- 1フレームぶんの処理。予算のぶんだけアンカーを外す。
function StructureManager:step()
	for _, live in self.live do
		local budget = Config.physics.unanchorBudget
		while budget > 0 and live.queueHead <= #live.queue do
			local entry = live.queue[live.queueHead]
			live.queueHead += 1
			if release(live, entry.id, entry.impulse) then
				budget -= 1
			end
		end
		-- キューを使い切ったら詰め直してメモリを解放する
		if live.queueHead > #live.queue and #live.queue > 0 then
			table.clear(live.queue)
			live.queueHead = 1
		end
	end
end

-- ── 瓦礫の回収 ──────────────────────────────────────────
-- 走査するのは「いま動いている破片」だけ。立っているブロックは一度も触らない。
-- 数千個のうち動いているのは多くても Config.physics.maxActiveParts 個なので、
-- 0.2 秒に1回のこの走査がフレーム時間に乗ることはない。
function StructureManager:collect()
	local now = os.clock()
	for _, live in self.live do
		local settleY = live.origin.Y + Config.progress.settleY
		local kept = {}
		local overflow = #live.active - Config.physics.maxActiveParts

		for index, entry in live.active do
			local part = entry.part
			local age = now - entry.at
			local settled = age > Config.progress.settleDelay
				and part.Position.Y < settleY
				and part.AssemblyLinearVelocity.Magnitude < Config.progress.settleSpeed
			local landed = not part.Parent
				or settled
				or part.Position.Y < Config.arena.killY -- 場外へ飛んだ
				or age > Config.physics.debrisLifetime -- 転がり続けているぶんの打ち切り
				-- 上限を超えたぶんは古い順に強制回収する。演出より
				-- フレームレートを優先する最後の砦。
				or index <= overflow

			if landed then
				live.fallen += 1
				part:Destroy()
			else
				table.insert(kept, entry)
			end
		end
		live.active = kept
	end
end

-- 崩壊率の材料。ProgressTracker がこれを読む。
function StructureManager:counts(live)
	return live.total, live.fallen, math.max(live.run.freedCount - live.fallen, 0)
end

return StructureManager
