-- 破壊の演出。粉塵・火花・瓦礫の音は すべてこのクライアントの中だけで作る。
--
-- サーバから届くのは「どのスロットで・どこで・どれくらいの規模で崩れたか」
-- という数個の数字だけ。パーティクル1つ1つをサーバから複製すると、
-- 4人 x 毎秒6打撃ぶんのインスタンス生成がレプリケーションに乗って
-- 全員が同時にカクつく。演出をローカルに閉じるのはラグ対策そのもの。
--
-- 画像・音源アセットは使わない。パーティクルのテクスチャは Roblox
-- クライアントに同梱の rbxasset:// だけで、アップロード済みアセットは0本。

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("DominoCrash").Config)

local Effects = {}
Effects.__index = Effects

local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function anchor(position: Vector3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = parent
	return part
end

function Effects.new()
	local folder = Instance.new("Folder")
	folder.Name = "DominoCrashEffects"
	folder.Parent = Workspace

	return setmetatable({ folder = folder }, Effects)
end

-- 音は Config.juice.sounds に rbxassetid:// を入れたときだけ鳴る。
-- 空のままなら黙って何もしない (このリポジトリの既定)。
function Effects:play(name: string, position: Vector3?)
	local id = Config.juice.sounds[name]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.RollOffMaxDistance = 250
	if position then
		local emitter = anchor(position, self.folder)
		sound.Parent = emitter
		sound:Play()
		Debris:AddItem(emitter, 4)
	else
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

-- ハンマーが当たった瞬間の火花。サーバの返事を待たずに出す。
function Effects:swingSpark(position: Vector3, normal: Vector3)
	local part = anchor(position + normal * 0.4, self.folder)

	local spark = Instance.new("ParticleEmitter")
	spark.Texture = SPARK_TEXTURE
	spark.Color = ColorSequence.new(Color3.fromRGB(255, 226, 158), Color3.fromRGB(255, 150, 60))
	spark.Size = NumberSequence.new(0.55, 0)
	spark.Transparency = NumberSequence.new(0.1, 1)
	spark.Lifetime = NumberRange.new(0.16, 0.32)
	spark.Speed = NumberRange.new(14, 26)
	spark.SpreadAngle = Vector2.new(55, 55)
	spark.Acceleration = Vector3.new(0, -60, 0)
	spark.Rate = 0
	spark.Parent = part
	spark:Emit(14)

	Debris:AddItem(part, 1)
end

-- 崩壊の粉塵。規模 (崩れたブロック数) で量と広がりを変える。
function Effects:collapseDust(position: Vector3, scale: number, key: boolean)
	local part = anchor(position, self.folder)

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = DUST_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(196, 186, 170), Color3.fromRGB(140, 132, 122))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2 + 6 * scale),
		NumberSequenceKeypoint.new(1, 8 + 18 * scale),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.9, 2.1)
	dust.Speed = NumberRange.new(6, 14 + 26 * scale)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Acceleration = Vector3.new(0, 3, 0) -- 粉塵は少し上へ舞う
	dust.Rate = 0
	dust.Parent = part
	dust:Emit(math.floor(Config.juice.dustPerHit * (0.4 + scale)))

	if key then
		-- キーパーツを折ったときだけ、破断の閃光を足す
		local flash = Instance.new("PointLight")
		flash.Color = Color3.fromRGB(255, 196, 120)
		flash.Range = 26
		flash.Brightness = 3
		flash.Parent = part
	end

	Debris:AddItem(part, 3)
end

return Effects
