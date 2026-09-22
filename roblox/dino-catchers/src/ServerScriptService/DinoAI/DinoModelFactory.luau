-- 「種Id → 恐竜モデル」を返す唯一の窓口（仮モデル ⇔ 本番モデルの差し替え口）。
--
--   local model, groundOffset = DinoModelFactory.create("Protoceratops")
--
-- ■ 差し替えの仕方（本番モデルを入れるとき）
--   ServerStorage.DinoModels に、DinoConfig.Species[種].ModelName と同じ名前の Model を置くだけ。
--   置かれていればそれを複製して使い、無ければ PlaceholderDino（ブロック組み）で作る。
--   ここ以外（WildDinos / RanchDinos / DinoMover）は変更不要。
--   本番モデルの条件:
--     ・PrimaryPart を設定する（無い場合は "Root" という名前のパーツ → 最初のパーツの順で代わりに使い、警告を出す）
--     ・頭の向き = PrimaryPart の LookVector（-Z）。PrimaryPart は傾けずに置く
--     ・Humanoid は入れない（入っていたら警告を出して取り除く）。アニメーションが必要なら AnimationController を使う
--     ・スクリプトは入れない
--   読み込み時にここで次のように整える（仮モデルも同じ規約で作ってある）:
--     ・PrimaryPart だけ Anchored。ほかは Anchored = false / Massless = true にし、
--       ジョイント（Motor6D・Weld・WeldConstraint など）が付いていないパーツは PrimaryPart に WeldConstraint で溶接
--     ・全パーツ CanCollide = false / CanTouch = false / CanQuery = true
--   → サーバーは PrimaryPart の CFrame を動かすだけでモデル全体が動く（物理演算なし）。
--
-- ■ groundOffset
--   地面から PrimaryPart の中心までの高さ（モデルの一番下が地面に接する位置）。
--   モデルの属性 "GroundOffset" にも入れる（クライアントの演出用）。

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DinoConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DinoConfig"))
local PlaceholderDino = require(script.Parent:WaitForChild("PlaceholderDino"))

local DinoModelFactory = {}

type Template = {
	Model: Model,
	GroundOffset: number,
	Source: Instance?, -- 本番モデルの元（ServerStorage.DinoModels の中）。仮モデルなら nil
}

local templates: { [string]: Template } = {}

local JOINT_CLASSES = { "JointInstance", "WeldConstraint", "RigidConstraint" }

local function logWarn(message: string)
	warn("[DinoModelFactory] " .. message)
end

local function isJoint(instance: Instance): boolean
	for _, className in JOINT_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

-- ServerStorage.DinoModels（無ければ nil）
local function getModelsFolder(): Instance?
	return ServerStorage:FindFirstChild("DinoModels")
end

-- 本番モデル（あれば）
local function findProductionModel(species: any): Model?
	local folder = getModelsFolder()
	local found = folder and folder:FindFirstChild(species.ModelName)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

-- モデルを「PrimaryPart を動かすだけで全体が動く」形に整える。戻り値: 整えられたか
function DinoModelFactory.prepare(model: Model): boolean
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Humanoid") then
			logWarn(model.Name .. " に Humanoid が入っていたので取り除いた（性能のため使わない）")
			descendant:Destroy()
		end
	end

	local root = model.PrimaryPart
	if not root then
		local candidate = model:FindFirstChild("Root", true)
		if not (candidate and candidate:IsA("BasePart")) then
			candidate = model:FindFirstChildWhichIsA("BasePart", true)
		end
		if not candidate then
			logWarn(model.Name .. " にパーツがありません")
			return false
		end
		logWarn(model.Name .. " に PrimaryPart が無いので " .. candidate.Name .. " を代わりに使う")
		root = candidate :: BasePart
		model.PrimaryPart = root
	end
	local rootPart = root :: BasePart

	-- ジョイントでつながっているパーツ（本番モデルの Motor6D など）は溶接し直さない
	local jointed: { [BasePart]: boolean } = {}
	for _, descendant in model:GetDescendants() do
		if isJoint(descendant) then
			local d = descendant :: any
			if d.Part0 then
				jointed[d.Part0] = true
			end
			if d.Part1 then
				jointed[d.Part1] = true
			end
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = true
			if descendant ~= rootPart then
				descendant.Anchored = false
				descendant.Massless = true
				if not jointed[descendant] then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = rootPart
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
		end
	end
	rootPart.Anchored = true
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return true
end

-- 地面から PrimaryPart の中心までの高さ
local function computeGroundOffset(model: Model): number
	local root = model.PrimaryPart :: BasePart
	local boxCFrame, boxSize = model:GetBoundingBox()
	local relative = root.CFrame:ToObjectSpace(boxCFrame)
	return -(relative.Y - boxSize.Y / 2)
end

local function makeTemplate(speciesId: string): Template?
	local species = DinoConfig.Species[speciesId]
	if not species then
		logWarn("未知の種: " .. tostring(speciesId))
		return nil
	end

	local source = findProductionModel(species)
	local model: Model
	if source then
		model = source:Clone()
		model:SetAttribute("Placeholder", false)
	else
		model = PlaceholderDino.build(species)
	end
	if not DinoModelFactory.prepare(model) then
		if not source then
			return nil
		end
		logWarn(species.ModelName .. " の本番モデルが使えないので仮モデルを使う")
		source = nil
		model = PlaceholderDino.build(species)
		DinoModelFactory.prepare(model)
	end

	local groundOffset = computeGroundOffset(model)
	model:SetAttribute("GroundOffset", groundOffset)
	return { Model = model, GroundOffset = groundOffset, Source = source }
end

-- 種ごとの元モデル（複製の元。Parent なし）。本番モデルが置かれた・差し替わったら作り直す
local function getTemplate(speciesId: string): Template?
	local cached = templates[speciesId]
	local species = DinoConfig.Species[speciesId]
	if cached and species then
		local source = findProductionModel(species)
		if source == cached.Source then
			return cached
		end
		cached.Model:Destroy()
	end
	local template = makeTemplate(speciesId)
	templates[speciesId] = template
	return template
end

-- 種Id → 新しい恐竜モデル（Parent なし・原点付近）と groundOffset。未知の種なら nil
function DinoModelFactory.create(speciesId: string): (Model?, number)
	local template = getTemplate(speciesId)
	if not template then
		return nil, 0
	end
	local model = template.Model:Clone()
	model.Name = speciesId
	return model, template.GroundOffset
end

-- 本番モデルを使っているか（確認・デバッグ用）
function DinoModelFactory.isUsingProductionModel(speciesId: string): boolean
	local species = DinoConfig.Species[speciesId]
	return species ~= nil and findProductionModel(species) ~= nil
end

return DinoModelFactory
