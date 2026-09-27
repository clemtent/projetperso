--[[
	HouseGarden (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseGarden

	🚶 Dopamine Town (v9.4) : le jardin de devant des maisons 3D.
	  - Decorations(kit, ids, x0, x1, d, avoidCenter) : la déco choisie dans
	    la maison 2D (Config.House.GardenDecor), aux MÊMES places que la bande
	    de jardin 2D (GardenSlots places réparties de gauche à droite), en vrais
	    petits modèles 3D (tulipes, nain, flamant, bain d'oiseaux, ruche, mare
	    aux canards, citrouilles, bonhomme de neige, puits, trampoline,
	    arc-en-ciel, licorne, panier de basket, tente, barbecue, but, rampe
	    de skate, cabane dans l'arbre, dinosaure) ; objet inconnu : butte
	    fleurie + icône.
	  - Petits décors partagés : Cat, PottedBall, Bike, Bench, Fountain,
	    Topiary, FlowerBed.
	Repère local de la maison (HouseKit) ; tout est décor (pas de collision)
	sauf les gros volumes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HouseGarden = {}

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local PINK = Color3.fromRGB(255, 126, 182)
local LEAF = Color3.fromRGB(128, 206, 128)
local LEAF_DARK = Color3.fromRGB(84, 160, 100)
local STONE = Color3.fromRGB(236, 230, 240)
local WOOD = Color3.fromRGB(196, 146, 104)
local GOLD = Color3.fromRGB(246, 196, 84)
local INK = Color3.fromRGB(92, 58, 96)
local WATER = Color3.fromRGB(150, 215, 255)
local SOIL = Color3.fromRGB(150, 104, 80)

local DECO = { Shadow = false }
local SOLID = { Solid = true }

----------------------------------------------------------------------
-- Petits décors partagés
----------------------------------------------------------------------

-- Chat kawaii assis (sur un toit, dans un jardin) ; (x, y, d) = sous les pattes
function HouseGarden.Cat(kit: any, x: number, y: number, d: number)
	local fur = Color3.fromRGB(255, 214, 170)
	kit:Ball("Cat", x, y + 0.7, d, 1.5, fur, M.Fabric, DECO)
	kit:Ball("CatHead", x, y + 1.8, d - 0.3, 1.2, fur, M.Fabric, DECO)
	for _, s in ipairs({ -1, 1 }) do
		kit:Part("CatEar", Vector3.new(0.15, 0.5, 0.4), CFrame.new(x + s * 0.35, y + 2.45, -(d - 0.3)) * CFrame.Angles(0, math.pi / 2, 0), fur, M.Fabric, DECO, "WedgePart")
		kit:Ball("CatEye", x + s * 0.24, y + 1.9, d - 0.88, 0.18, INK, M.SmoothPlastic, DECO)
	end
	kit:Ball("CatNose", x, y + 1.72, d - 0.9, 0.12, PINK, M.SmoothPlastic, DECO)
	kit:Part("CatTail", Vector3.new(0.25, 1.3, 0.25), CFrame.new(x + 0.8, y + 0.9, -(d + 0.3)) * CFrame.Angles(0, 0, math.rad(-30)), fur, M.Fabric, DECO)
end

-- Pot + boule de buis
function HouseGarden.PottedBall(kit: any, x: number, d: number, s: number, pot: Color3)
	kit:CylY("Pot", x, 0, d, 1.4 * s, 1.2 * s, pot, M.SmoothPlastic, DECO)
	kit:CylY("PotRim", x, 1.1 * s, d, 1.6 * s, 0.25 * s, pot:Lerp(WHITE, 0.3), M.SmoothPlastic, DECO)
	kit:Box("Stem", x - 0.1 * s, x + 0.1 * s, 1.2 * s, 2 * s, d - 0.1, d + 0.1, WOOD, M.Wood, DECO)
	kit:Ball("Topiary", x, 2.6 * s, d, 1.8 * s, LEAF, M.Grass, DECO)
end

-- Vélo (roues, cadre, selle, panier fleuri)
function HouseGarden.Bike(kit: any, x: number, d: number, color: Color3)
	for _, wx in ipairs({ x - 1.3, x + 1.3 }) do
		kit:CylX("Wheel", wx, 0.9, d, 1.8, 0.15, INK, M.Rubber, DECO)
		kit:CylX("Hub", wx, 0.9, d, 0.5, 0.2, WHITE, M.Metal, DECO)
	end
	kit:SlabX("Frame", d, { x - 1.3, 0.95 }, { x - 0.1, 1.9 }, 0.15, 0.15, color, M.Metal, DECO)
	kit:SlabX("Frame", d, { x - 0.1, 1.9 }, { x + 1.1, 1.9 }, 0.15, 0.15, color, M.Metal, DECO)
	kit:SlabX("Frame", d, { x - 0.1, 0.95 }, { x + 1.1, 1.9 }, 0.15, 0.15, color, M.Metal, DECO)
	kit:Box("Saddle", x - 0.55, x + 0.05, 2, 2.2, d - 0.2, d + 0.2, PINK, M.Leather, DECO)
	kit:Box("Basket", x + 1.2, x + 2, 1.7, 2.3, d - 0.4, d + 0.4, WOOD, M.WoodPlanks, DECO)
	kit:Ball("Bloom", x + 1.6, 2.4, d, 0.5, PINK, M.SmoothPlastic, DECO)
end

-- Banc (assise + dossier roses, pieds d'acier)
function HouseGarden.Bench(kit: any, x: number, d: number, color: Color3)
	kit:Box("BenchSeat", x - 2.5, x + 2.5, 1.4, 1.7, d - 0.6, d + 0.6, color, M.Wood, SOLID)
	kit:Box("BenchBack", x - 2.5, x + 2.5, 1.9, 3, d + 0.5, d + 0.7, color, M.Wood, DECO)
	for _, lx in ipairs({ x - 2.1, x + 2.1 }) do
		kit:Box("BenchLeg", lx - 0.15, lx + 0.15, 0, 1.4, d - 0.5, d + 0.5, Color3.fromRGB(96, 78, 124), M.Metal, DECO)
	end
end

-- Fontaine à deux vasques (cœur au sommet), eau qui jaillit
function HouseGarden.Fountain(kit: any, x: number, d: number)
	kit:CylY("FountainBasin", x, 0, d, 9, 1.3, STONE, M.Limestone, SOLID)
	kit:CylY("FountainWater", x, 0.3, d, 8.2, 1.1, WATER, M.Glass, { Shadow = false, T = 0.25 })
	kit:CylY("FountainPillar", x, 1.2, d, 1.2, 2.4, STONE, M.Limestone, SOLID)
	kit:CylY("FountainBowl", x, 3.4, d, 4.2, 0.5, STONE, M.Limestone, DECO)
	kit:CylY("FountainBowlWater", x, 3.55, d, 3.6, 0.45, WATER, M.Glass, { Shadow = false, T = 0.2 })
	kit:CylY("FountainTop", x, 3.9, d, 0.6, 1.4, STONE, M.Limestone, DECO)
	kit:CylY("FountainCup", x, 5.3, d, 1.8, 0.3, STONE, M.Limestone, DECO)
	local spout = kit:Ball("FountainHeart", x, 5.9, d, 0.8, PINK, M.SmoothPlastic, DECO)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FountainSpray"
	emitter.Color = ColorSequence.new(Color3.fromRGB(220, 244, 255), WATER)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.1) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.8) })
	emitter.Lifetime = NumberRange.new(0.8, 1.1)
	emitter.Speed = NumberRange.new(5, 6)
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.Rate = 16
	emitter.LightInfluence = 1
	emitter.Parent = spout
end

-- Topiaire à étages dans un bac rose (comme la 2D du manoir)
function HouseGarden.Topiary(kit: any, x: number, d: number)
	kit:Box("TopiaryPot", x - 1.2, x + 1.2, 0, 1.8, d - 1.2, d + 1.2, PINK, M.SmoothPlastic, DECO)
	kit:Box("TopiaryRim", x - 1.4, x + 1.4, 1.8, 2.2, d - 1.4, d + 1.4, PINK:Lerp(WHITE, 0.3), M.SmoothPlastic, DECO)
	kit:CylY("TopiaryTrunk", x, 2.2, d, 0.35, 6.6, WOOD, M.Wood, DECO)
	for k = 0, 2 do
		kit:Ball("TopiaryBall", x, 3.8 + k * 2.3, d, 3 - k * 0.75, LEAF:Lerp(LEAF_DARK, k * 0.1), M.Grass, DECO)
	end
	kit:Ball("TopiaryHeart", x, 9.4, d, 0.8, Color3.fromRGB(255, 79, 139), M.SmoothPlastic, DECO)
end

-- Parterre rond fleuri (bordure + fleurs en couronne)
function HouseGarden.FlowerBed(kit: any, x: number, d: number, radius: number)
	kit:CylY("BedBorder", x, 0, d, radius * 2 + 0.6, 0.45, STONE, M.Limestone, DECO)
	kit:CylY("Bed", x, 0.1, d, radius * 2, 0.5, LEAF_DARK:Lerp(LEAF, 0.4), M.Grass, DECO)
	local colors = { PINK, Color3.fromRGB(255, 226, 130), WHITE, Color3.fromRGB(183, 148, 246) }
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		kit:Ball("BedFlower", x + math.cos(a) * radius * 0.62, 0.9, d + math.sin(a) * radius * 0.62, 0.9, colors[k % 4 + 1], M.SmoothPlastic, DECO)
	end
	kit:Ball("BedFlower", x, 1.1, d, 1.2, Color3.fromRGB(255, 79, 139), M.SmoothPlastic, DECO)
end

----------------------------------------------------------------------
-- Déco du jardin (Config.House.GardenDecor)
----------------------------------------------------------------------

type Maker = (kit: any, x: number, d: number) -> ()
local MAKERS: { [string]: Maker } = {}

MAKERS.TulipBed = function(kit, x, d)
	kit:Box("Soil", x - 2.2, x + 2.2, 0, 0.5, d - 1, d + 1, SOIL, M.Ground, DECO)
	local colors = { PINK, Color3.fromRGB(255, 226, 130), Color3.fromRGB(255, 120, 120), WHITE, Color3.fromRGB(183, 148, 246), PINK }
	for k = 0, 5 do
		local fx = x - 1.8 + k * 0.72
		local fd = d + (k % 2) * 0.6 - 0.3
		kit:Box("TulipStem", fx - 0.06, fx + 0.06, 0.5, 1.6, fd - 0.06, fd + 0.06, LEAF_DARK, M.Grass, DECO)
		kit:CylY("Tulip", fx, 1.5, fd, 0.55, 0.6, colors[k + 1], M.SmoothPlastic, DECO)
	end
end
MAKERS.GardenGnome = function(kit, x, d)
	kit:CylY("GnomeBody", x, 0, d, 1.3, 1.5, Color3.fromRGB(110, 150, 240), M.SmoothPlastic, DECO)
	kit:Ball("GnomeFace", x, 1.9, d, 0.9, Color3.fromRGB(255, 214, 190), M.SmoothPlastic, DECO)
	kit:Ball("GnomeBeard", x, 1.55, d - 0.25, 0.9, WHITE, M.Fabric, DECO)
	kit:CylY("GnomeHat", x, 2.2, d, 0.95, 0.6, Color3.fromRGB(236, 72, 90), M.Fabric, DECO)
	kit:CylY("GnomeHatTip", x, 2.8, d, 0.5, 0.6, Color3.fromRGB(236, 72, 90), M.Fabric, DECO)
	kit:Ball("GnomeNose", x, 1.95, d - 0.45, 0.3, Color3.fromRGB(255, 170, 160), M.SmoothPlastic, DECO)
end
MAKERS.PinkFlamingo = function(kit, x, d)
	local pink = Color3.fromRGB(255, 140, 180)
	for _, s in ipairs({ -0.15, 0.15 }) do
		kit:Box("FlamingoLeg", x + s - 0.05, x + s + 0.05, 0, 2, d - 0.05, d + 0.05, pink:Lerp(INK, 0.3), M.SmoothPlastic, DECO)
	end
	kit:Ball("FlamingoBody", x, 2.4, d, 1.4, pink, M.SmoothPlastic, DECO)
	kit:Part("FlamingoNeck", Vector3.new(0.25, 1.8, 0.25), CFrame.new(x + 0.35, 3.5, -d) * CFrame.Angles(0, 0, math.rad(-12)), pink, M.SmoothPlastic, DECO)
	kit:Ball("FlamingoHead", x + 0.5, 4.4, d, 0.6, pink, M.SmoothPlastic, DECO)
	kit:Box("FlamingoBeak", x + 0.7, x + 1.2, 4.2, 4.4, d - 0.08, d + 0.08, INK, M.SmoothPlastic, DECO)
end
MAKERS.Birdbath = function(kit, x, d)
	kit:CylY("BathPedestal", x, 0, d, 0.8, 2.2, STONE, M.Limestone, DECO)
	kit:CylY("BathBowl", x, 2.2, d, 2.6, 0.5, STONE, M.Limestone, DECO)
	kit:CylY("BathWater", x, 2.45, d, 2.2, 0.3, WATER, M.Glass, { Shadow = false, T = 0.2 })
	kit:Ball("Bird", x + 0.5, 3, d, 0.55, Color3.fromRGB(150, 205, 255), M.SmoothPlastic, DECO)
	kit:Ball("BirdHead", x + 0.8, 3.3, d, 0.35, Color3.fromRGB(150, 205, 255), M.SmoothPlastic, DECO)
end
MAKERS.Beehive = function(kit, x, d)
	kit:Box("HiveStand", x - 0.8, x + 0.8, 0, 0.8, d - 0.8, d + 0.8, WOOD, M.Wood, DECO)
	local honey = Color3.fromRGB(255, 206, 90)
	for k = 0, 2 do
		kit:CylY("Hive", x, 0.8 + k * 0.6, d, 2 - k * 0.45, 0.6, honey:Lerp(WOOD, k * 0.1), M.SmoothPlastic, DECO)
	end
	kit:CylD("HiveDoor", x, 1.1, d - 0.9, 0.5, 0.1, INK, M.SmoothPlastic, DECO)
	kit:Ball("Bee", x + 1, 2.6, d - 0.4, 0.3, Color3.fromRGB(255, 226, 90), M.SmoothPlastic, DECO)
end
MAKERS.DuckPond = function(kit, x, d)
	kit:CylY("PondRim", x, 0, d, 5.4, 0.35, STONE, M.Slate, DECO)
	kit:CylY("Pond", x, 0.05, d, 4.8, 0.35, WATER, M.Glass, { Shadow = false, T = 0.1 })
	for _, p in ipairs({ { -0.8, 0.2 }, { 0.9, -0.4 } }) do
		kit:Ball("Duck", x + p[1], 0.65, d + p[2], 0.8, Color3.fromRGB(255, 226, 90), M.SmoothPlastic, DECO)
		kit:Ball("DuckHead", x + p[1] + 0.3, 1.1, d + p[2], 0.5, Color3.fromRGB(255, 226, 90), M.SmoothPlastic, DECO)
		kit:Box("DuckBeak", x + p[1] + 0.5, x + p[1] + 0.75, 1.02, 1.12, d + p[2] - 0.08, d + p[2] + 0.08, Color3.fromRGB(255, 150, 60), M.SmoothPlastic, DECO)
	end
end
MAKERS.PumpkinPatch = function(kit, x, d)
	kit:Box("Soil", x - 2, x + 2, 0, 0.3, d - 1, d + 1, SOIL, M.Ground, DECO)
	for k, p in ipairs({ { -1.1, 0, 1.3 }, { 0.3, 0.3, 1.6 }, { 1.4, -0.2, 1.1 } }) do
		kit:Ball("Pumpkin", x + p[1], 0.3 + p[3] * 0.42, d + p[2], p[3], Color3.fromRGB(255, 150, 60), M.SmoothPlastic, DECO)
		kit:Box("PumpkinStem", x + p[1] - 0.08, x + p[1] + 0.08, 0.3 + p[3] * 0.8, 0.5 + p[3] * 0.9, d + p[2] - 0.08, d + p[2] + 0.08, LEAF_DARK, M.Grass, DECO)
		local _ = k
	end
end
MAKERS.Snowman = function(kit, x, d)
	kit:Ball("SnowBase", x, 0.9, d, 2, WHITE, M.Snow, DECO)
	kit:Ball("SnowBody", x, 2.4, d, 1.5, WHITE, M.Snow, DECO)
	kit:Ball("SnowHead", x, 3.5, d, 1.1, WHITE, M.Snow, DECO)
	kit:CylY("SnowHat", x, 3.95, d, 0.8, 0.7, INK, M.Fabric, DECO)
	kit:Box("SnowNose", x - 0.08, x + 0.08, 3.45, 3.6, d - 0.9, d - 0.45, Color3.fromRGB(255, 150, 60), M.SmoothPlastic, DECO)
	kit:CylY("SnowScarf", x, 2.95, d, 1.2, 0.25, Color3.fromRGB(236, 72, 140), M.Fabric, DECO)
end
MAKERS.WishingWell = function(kit, x, d)
	kit:CylY("WellWall", x, 0, d, 3, 1.6, STONE, M.Cobblestone, SOLID)
	kit:CylY("WellWater", x, 1.2, d, 2.3, 0.3, Color3.fromRGB(90, 150, 210), M.Glass, DECO)
	for _, s in ipairs({ -1, 1 }) do
		kit:Box("WellPost", x + s * 1.3 - 0.12, x + s * 1.3 + 0.12, 1.6, 4, d - 0.12, d + 0.12, WOOD, M.Wood, DECO)
		kit:SlabX("WellRoof", d, { x + s * 2, 3.8 }, { x, 4.8 }, 2.6, 0.2, PINK, M.ClayRoofTiles, DECO)
	end
	kit:Box("WellBucket", x - 0.3, x + 0.3, 2.4, 2.9, d - 0.3, d + 0.3, WOOD, M.Wood, DECO)
end
MAKERS.Trampoline = function(kit, x, d)
	for _, p in ipairs({ { -1.8, -1.8 }, { 1.8, -1.8 }, { -1.8, 1.8 }, { 1.8, 1.8 } }) do
		kit:Box("TrampLeg", x + p[1] - 0.1, x + p[1] + 0.1, 0, 1, d + p[2] - 0.1, d + p[2] + 0.1, INK, M.Metal, DECO)
	end
	kit:CylY("TrampFrame", x, 1, d, 5.4, 0.3, Color3.fromRGB(110, 150, 240), M.SmoothPlastic, DECO)
	kit:CylY("TrampMat", x, 1.05, d, 4.6, 0.3, INK, M.Fabric, DECO)
end
MAKERS.RainbowArch = function(kit, x, d)
	local colors = {
		Color3.fromRGB(255, 120, 130), Color3.fromRGB(255, 180, 110), Color3.fromRGB(255, 226, 120), Color3.fromRGB(150, 222, 150), Color3.fromRGB(150, 205, 255),
		Color3.fromRGB(183, 148, 246), WHITE,
	}
	for k, color in ipairs(colors) do
		kit:CylD("Rainbow", x, 0, d + k * 0.02, 5.6 - (k - 1) * 0.55, 0.3, color, M.SmoothPlastic, DECO)
	end
	for _, s in ipairs({ -1, 1 }) do
		kit:Ball("Cloud", x + s * 2.5, 0.5, d - 0.4, 1.3, WHITE, M.Fabric, DECO)
	end
end
MAKERS.UnicornStatue = function(kit, x, d)
	kit:Box("UnicornBase", x - 1.4, x + 1.4, 0, 1, d - 1, d + 1, STONE, M.Marble, SOLID)
	kit:Box("UnicornBody", x - 1, x + 1, 1.8, 2.8, d - 0.5, d + 0.5, WHITE, M.Marble, DECO)
	for _, p in ipairs({ { -0.7, -0.3 }, { 0.7, -0.3 }, { -0.7, 0.3 }, { 0.7, 0.3 } }) do
		kit:Box("UnicornLeg", x + p[1] - 0.15, x + p[1] + 0.15, 1, 1.9, d + p[2] - 0.15, d + p[2] + 0.15, WHITE, M.Marble, DECO)
	end
	kit:Box("UnicornHead", x + 0.9, x + 1.6, 2.7, 3.5, d - 0.35, d + 0.35, WHITE, M.Marble, DECO)
	kit:Part("UnicornHorn", Vector3.new(0.12, 0.9, 0.12), CFrame.new(x + 1.4, 3.9, -d) * CFrame.Angles(0, 0, math.rad(-25)), GOLD, M.Metal, DECO)
	kit:Ball("UnicornMane", x + 0.8, 3.3, d, 0.6, PINK, M.Fabric, DECO)
	kit:Ball("UnicornTail", x - 1.1, 2.4, d, 0.6, Color3.fromRGB(183, 148, 246), M.Fabric, DECO)
end
MAKERS.YardHoop = function(kit, x, d)
	kit:Box("HoopPole", x - 0.15, x + 0.15, 0, 6, d + 0.6, d + 0.9, INK, M.Metal, DECO)
	kit:Box("HoopBoard", x - 1.4, x + 1.4, 5, 6.8, d + 0.4, d + 0.6, WHITE, M.SmoothPlastic, DECO)
	kit:Box("HoopSquare", x - 0.5, x + 0.5, 5.4, 6.1, d + 0.36, d + 0.4, Color3.fromRGB(255, 120, 60), M.SmoothPlastic, DECO)
	kit:CylY("HoopRim", x, 5.3, d - 0.2, 1.3, 0.1, Color3.fromRGB(255, 120, 60), M.Metal, DECO)
	kit:Ball("Basketball", x + 1.4, 0.45, d - 1, 0.9, Color3.fromRGB(255, 140, 60), M.Rubber, DECO)
end
MAKERS.CampTent = function(kit, x, d)
	for _, s in ipairs({ -1, 1 }) do
		kit:SlabX("Tent", d, { x + s * 2.2, 0 }, { x, 3 }, 3.6, 0.15, Color3.fromRGB(110, 190, 150), M.Fabric, DECO)
	end
	kit:Part("TentDoor", Vector3.new(0.05, 2.2, 1.6), CFrame.new(x, 1.1, -(d - 1.8)) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(255, 226, 130), M.Fabric, DECO, "WedgePart")
end
MAKERS.BBQGrill = function(kit, x, d)
	for _, s in ipairs({ -0.6, 0.6 }) do
		kit:Box("GrillLeg", x + s - 0.08, x + s + 0.08, 0, 1.8, d - 0.08, d + 0.08, INK, M.Metal, DECO)
	end
	kit:CylY("GrillBowl", x, 1.8, d, 2, 0.8, Color3.fromRGB(60, 60, 70), M.Metal, DECO)
	kit:Ball("GrillLid", x, 2.6, d, 1.9, Color3.fromRGB(60, 60, 70), M.Metal, DECO)
	kit:Box("GrillHandle", x - 0.3, x + 0.3, 3.5, 3.65, d - 0.1, d + 0.1, WOOD, M.Wood, DECO)
end
MAKERS.YardGoal = function(kit, x, d)
	for _, s in ipairs({ -1, 1 }) do
		kit:Box("GoalPost", x + s * 2.4 - 0.12, x + s * 2.4 + 0.12, 0, 3, d - 0.12, d + 0.12, WHITE, M.Metal, DECO)
	end
	kit:Box("GoalBar", x - 2.5, x + 2.5, 2.9, 3.15, d - 0.12, d + 0.12, WHITE, M.Metal, DECO)
	kit:Box("GoalNet", x - 2.4, x + 2.4, 0, 2.9, d + 0.3, d + 1.6, Color3.fromRGB(230, 230, 240), M.Fabric, { Shadow = false, T = 0.55 })
	kit:Ball("Football", x + 1, 0.4, d - 1, 0.8, WHITE, M.SmoothPlastic, DECO)
end
MAKERS.SkateRamp = function(kit, x, d)
	kit:Part("SkateRamp", Vector3.new(4, 1.8, 3), CFrame.new(x, 0.9, -(d + 0.5)) * CFrame.Angles(0, math.pi, 0), WOOD, M.WoodPlanks, SOLID, "WedgePart")
	kit:Box("SkateDeck", x - 0.9, x + 0.9, 0.1, 0.25, d - 2.2, d - 1.6, Color3.fromRGB(236, 72, 140), M.Wood, DECO)
end
MAKERS.Treehouse = function(kit, x, d)
	kit:CylY("TreeTrunk", x, 0, d + 0.5, 1.2, 6, Color3.fromRGB(176, 124, 96), M.Wood, SOLID)
	kit:Ball("TreeLeaves", x, 8.2, d + 0.5, 5.5, LEAF, M.Grass, DECO)
	kit:Box("TreeHouse", x - 1.6, x + 1.6, 5.2, 7.4, d - 1.2, d + 1.4, WOOD, M.WoodPlanks, DECO)
	kit:Box("TreeHouseDoor", x - 0.5, x + 0.5, 5.2, 6.8, d - 1.25, d - 1.2, INK, M.Wood, DECO)
	for _, s in ipairs({ -1, 1 }) do
		kit:SlabX("TreeHouseRoof", d + 0.1, { x + s * 2.2, 7.2 }, { x, 8.6 }, 3.2, 0.25, PINK, M.ClayRoofTiles, DECO)
	end
	for k = 0, 3 do
		kit:Box("LadderRung", x - 0.5, x + 0.5, 1 + k * 1.1, 1.12 + k * 1.1, d - 1.6, d - 1.5, WOOD, M.Wood, DECO)
	end
end
MAKERS.DinoStatue = function(kit, x, d)
	local green = Color3.fromRGB(120, 200, 140)
	kit:Ball("DinoBody", x, 1.8, d, 2.6, green, M.SmoothPlastic, DECO)
	kit:Part("DinoNeck", Vector3.new(0.7, 2.2, 0.7), CFrame.new(x + 1.2, 3.4, -d) * CFrame.Angles(0, 0, math.rad(-30)), green, M.SmoothPlastic, DECO)
	kit:Ball("DinoHead", x + 1.9, 4.5, d, 1.1, green, M.SmoothPlastic, DECO)
	kit:Part("DinoTail", Vector3.new(2.4, 0.6, 0.6), CFrame.new(x - 2.1, 1.3, -d) * CFrame.Angles(0, 0, math.rad(20)), green, M.SmoothPlastic, DECO)
	for _, p in ipairs({ { -0.6, -0.5 }, { 0.6, -0.5 }, { -0.6, 0.5 }, { 0.6, 0.5 } }) do
		kit:Box("DinoLeg", x + p[1] - 0.25, x + p[1] + 0.25, 0, 1, d + p[2] - 0.25, d + p[2] + 0.25, green, M.SmoothPlastic, DECO)
	end
	for k = 0, 2 do
		kit:Ball("DinoSpike", x - 0.6 + k * 0.6, 3.1, d, 0.5, Color3.fromRGB(255, 180, 110), M.SmoothPlastic, DECO)
	end
end

-- Objet inconnu (future mise à jour) : butte fleurie + icône
local function fallback(kit: any, x: number, d: number, entry: any)
	local mound = kit:CylY("GardenMound", x, 0, d, 4, 0.8, LEAF, M.Grass, DECO)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GardenDecor"
	billboard.Size = UDim2.fromScale(4, 4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 160
	billboard.LightInfluence = 0
	billboard.Adornee = mound
	billboard.Parent = mound
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Font = Enum.Font.GothamBold
	icon.TextScaled = true
	icon.Text = tostring(entry and entry.Icon or "🌷")
	icon.Parent = billboard
end

function HouseGarden.Has(id: string): boolean
	return MAKERS[id] ~= nil
end

-- Déco choisie : GardenSlots places réparties entre x0 et x1 (comme la 2D),
-- à la profondeur d ; avoidCenter : on laisse la fontaine / l'allée libres
function HouseGarden.Decorations(kit: any, ids: { string }?, x0: number, x1: number, d: number, avoidCenter: boolean?)
	local list = type(ids) == "table" and ids or {}
	local slots = tonumber((Config.House :: any).GardenSlots) or 6
	local byId = Config.HouseLooksById and Config.HouseLooksById.Garden or {}
	local margin = (x1 - x0) * 0.07
	local spacing = (x1 - x0 - margin * 2) / math.max(1, slots)
	local clear = if avoidCenter then 9 else 4.5
	for index = 1, slots do
		local id = list[index]
		local entry = type(id) == "string" and byId[id] or nil
		if entry then
			local x = x0 + margin + (index - 0.5) * spacing
			if math.abs(x) < clear then
				x = (if x < 0 then -1 else 1) * clear
			end
			local maker = MAKERS[id :: string]
			if maker then
				local ok, err = pcall(maker, kit, x, d)
				if not ok then
					warn("[World] Jardin " .. tostring(id) .. " : " .. tostring(err))
				end
			else
				fallback(kit, x, d, entry)
			end
		end
	end
end

return HouseGarden
