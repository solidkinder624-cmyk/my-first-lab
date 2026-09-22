-- 仮モデル（ブロック組み）の恐竜を作る。無料モデルは使わず Part だけで組む。
-- 本番モデルができたら ServerStorage.DinoModels に置くだけで差し替わる（DinoModelFactory 参照）。
-- このモジュールは DinoModelFactory からだけ使う。
--
-- 色・大きさは DinoConfig.Species の Placeholder* から読む:
--   PlaceholderColor       … 胴体・首・しっぽ・脚の色
--   PlaceholderAccentColor … 頭・とさか・背中の模様の色
--   PlaceholderBodySize    … 胴体の大きさ { X = 幅, Y = 高さ, Z = 長さ }。他の部品はこれを基準に比率で決める
--
-- 向き: 頭が -Z（PrimaryPart の LookVector の向き）。原点 = 胴体の中心。
-- PrimaryPart は胴体（Body）。Humanoid は使わない。
-- 組み立ての規約（本番モデルも同じ。DinoModelFactory.prepare が整える）:
--   ・PrimaryPart だけ Anchored、ほかは Anchored = false で PrimaryPart に溶接（WeldConstraint）
--   ・すべて CanCollide = false / CanTouch = false（ぶつかり判定・物理演算の負荷を出さない）
--   ・CanQuery = true（テイム銃の射線レイキャストで当たるように）

local PlaceholderDino = {}

-- 胴体の大きさに対する各部品の比率（仮モデルの見た目の調整値。ゲームの設定値ではない）
-- Size = 胴体の { X, Y, Z } に掛ける倍率 / Offset = 胴体の { X, Y, Z } に掛ける位置
local PARTS = {
	{ Name = "Neck", Accent = false, Size = { 0.45, 0.45, 0.35 }, Offset = { 0, 0.3, -0.6 } },
	{ Name = "Head", Accent = true, Size = { 0.7, 0.6, 0.4 }, Offset = { 0, 0.5, -0.85 } },
	{ Name = "Snout", Accent = true, Size = { 0.45, 0.35, 0.2 }, Offset = { 0, 0.4, -1.1 } },
	{ Name = "Crest", Accent = true, Size = { 0.15, 0.45, 0.35 }, Offset = { 0, 0.95, -0.75 } },
	{ Name = "BackStripe", Accent = true, Size = { 0.3, 0.1, 0.7 }, Offset = { 0, 0.52, 0 } },
	{ Name = "Tail", Accent = false, Size = { 0.5, 0.45, 0.45 }, Offset = { 0, 0.1, 0.7 } },
	{ Name = "TailTip", Accent = false, Size = { 0.25, 0.25, 0.4 }, Offset = { 0, 0.05, 1.1 } },
	{ Name = "LegFL", Accent = false, Size = { 0.28, 0.6, 0.18 }, Offset = { -0.36, -0.8, -0.3 } },
	{ Name = "LegFR", Accent = false, Size = { 0.28, 0.6, 0.18 }, Offset = { 0.36, -0.8, -0.3 } },
	{ Name = "LegBL", Accent = false, Size = { 0.32, 0.6, 0.22 }, Offset = { -0.34, -0.8, 0.3 } },
	{ Name = "LegBR", Accent = false, Size = { 0.32, 0.6, 0.22 }, Offset = { 0.34, -0.8, 0.3 } },
	-- 目（黒）。向きが一目で分かるように
	{ Name = "EyeL", Eye = true, Size = { 0.1, 0.12, 0.05 }, Offset = { -0.3, 0.6, -1.06 } },
	{ Name = "EyeR", Eye = true, Size = { 0.1, 0.12, 0.05 }, Offset = { 0.3, 0.6, -1.06 } },
}
local EYE_COLOR = Color3.fromRGB(20, 20, 20)

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Massless = true
	part.Parent = parent
	return part
end

-- 種の設定（DinoConfig.Species の1つ）から仮モデルを作る。原点に置いた状態で返す（Parent なし）
function PlaceholderDino.build(species: any): Model
	local model = Instance.new("Model")
	model.Name = species.ModelName

	local b = species.PlaceholderBodySize
	local bodySize = Vector3.new(b[1], b[2], b[3])
	local mainColor = toColor(species.PlaceholderColor)
	local accentColor = toColor(species.PlaceholderAccentColor)

	local body = makePart("Body", bodySize, CFrame.new(), mainColor, model)
	body.Anchored = true
	body.Massless = false
	model.PrimaryPart = body

	for _, def in PARTS do
		local size = Vector3.new(bodySize.X * def.Size[1], bodySize.Y * def.Size[2], bodySize.Z * def.Size[3])
		local offset = Vector3.new(bodySize.X * def.Offset[1], bodySize.Y * def.Offset[2], bodySize.Z * def.Offset[3])
		local color = if def.Eye then EYE_COLOR elseif def.Accent then accentColor else mainColor
		local part = makePart(def.Name, size, CFrame.new(offset), color, model)
		part.CastShadow = not def.Eye
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = part
		weld.Parent = part
	end

	model:SetAttribute("Placeholder", true)
	return model
end

return PlaceholderDino
