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

-- Banc de jardin (v9.6, refait comme le banc de la ville) : 3 lattes
-- d'assise à 1,9 stud, dossier de 2 lattes incliné de 12° vers l'ARRIÈRE
-- (+d, côté maison), 2 flasques en fonte avec accoudoirs ; on le regarde
-- depuis la rue (-d). (v9.4 : dossier flottant, pieds qui traversaient
-- l'assise.) Seule l'assise bloque (une seule grosse pièce invisible).
function HouseGarden.Bench(kit: any, x: number, d: number, color: Color3)
	local iron = Color3.fromRGB(86, 70, 110)
	local H = 1.9
	-- collision : un seul bloc invisible (rien de petit pour trébucher)
	local block = kit:Box("BenchBlock", x - 2.6, x + 2.6, 0, H, d - 0.7, d + 0.5, color, M.Wood, SOLID)
	block.Transparency = 1
	block.CastShadow = false
	for i = 0, 2 do
		local d0 = d - 0.7 + i * 0.42
		kit:Box("BenchSlat", x - 2.5, x + 2.5, H - 0.16, H, d0, d0 + 0.36, color, M.Wood, DECO)
	end
	local pivot = CFrame.new(x, H + 0.05, -(d + 0.5)) * CFrame.Angles(-math.rad(12), 0, 0)
	for _, h in ipairs({ 0.55, 1.2 }) do
		kit:Part("BenchBack", Vector3.new(5, 0.45, 0.14), pivot * CFrame.new(0, h, -0.07), color, M.Wood, DECO)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local fx = x + sx * 2.63
		kit:Box("BenchLeg", fx - 0.11, fx + 0.11, 0, H + 0.72, d - 0.58, d - 0.36, iron, M.Metal, DECO)
		kit:Box("BenchLeg", fx - 0.11, fx + 0.11, 0, H, d + 0.24, d + 0.46, iron, M.Metal, DECO)
		kit:Part("BenchPost", Vector3.new(0.22, 1.75, 0.2), CFrame.new(fx, H + 0.05, -(d + 0.5)) * CFrame.Angles(-math.rad(12), 0, 0) * CFrame.new(0, 0.755, 0.02),
			iron, M.Metal, DECO)
		kit:Box("BenchArm", fx - 0.15, fx + 0.15, H + 0.72, H + 0.86, d - 0.75, d + 0.45, iron, M.Metal, DECO)
		local r0, r1 = x + sx * 2.25, x + sx * 2.6
		kit:Box("BenchRail", math.min(r0, r1), math.max(r0, r1), H - 0.32, H - 0.16, d - 0.7, d + 0.54, iron, M.Metal, DECO)
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
		-- (v9.6 z-fighting : 0.02 d'écart -> 0.06, et le plus PETIT arc devant
		-- (côté rue) : on voit enfin les 7 bandes au lieu d'un disque qui scintille)
		kit:CylD("Rainbow", x, 0, d - k * 0.06, 5.6 - (k - 1) * 0.55, 0.3, color, M.SmoothPlastic, DECO)
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

-- (v9.8 GARDEN98) une déco du jardin dessinée au centre du repère du kit
-- (x = 0, d = 0, devant vers la rue = -d) : GardenBuilder la pose où le
-- joueur l'a mise (mode édition du jardin)
function HouseGarden.BuildDecor(kit: any, id: string)
	local maker = MAKERS[id]
	if maker then
		maker(kit, 0, 0)
	else
		local byId = Config.HouseLooksById and Config.HouseLooksById.Garden or {}
		fallback(kit, 0, 0, byId[id])
	end
end

-- (v9.8 GARDEN98) la déco du jardin n'est plus dessinée avec la façade :
-- GardenBuilder la pose (places libres choisies par le joueur, mêmes
-- modèles). HouseFacade garde l'appel : il ne fait plus rien.
HouseGarden.DECOR_IN_GARDEN = true

-- Déco choisie : GardenSlots places réparties entre x0 et x1 (comme la 2D),
-- à la profondeur d ; avoidCenter : on laisse la fontaine / l'allée libres
function HouseGarden.Decorations(kit: any, ids: { string }?, x0: number, x1: number, d: number, avoidCenter: boolean?)
	if HouseGarden.DECOR_IN_GARDEN then
		return
	end
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

----------------------------------------------------------------------
-- v9.8 (GARDEN98) 🪴 OBJETS DE JARDIN (Config.Garden.Pieces) : de vrais
-- modèles réalistes (pots en terre cuite, urne en pierre, rosiers,
-- hortensias, lavande, lanterne, nichoir, panier suspendu, massif rond,
-- banc, potager, table de pique-nique, cadran solaire, arche de roses,
-- balancelle, statue d'ange, kiosque blanc, fontaine à étages) + les
-- aménagements offerts par les agrandissements (serre, bassin aux carpes).
-- Dessinés au centre du repère du kit (x = 0, d = 0), devant vers la rue
-- (-d) ; `variant` (n° de l'exemplaire) change un peu les couleurs.
-- Anti-scintillement : jamais deux faces confondues (écarts >= 0,02).
----------------------------------------------------------------------

local TERRA = Color3.fromRGB(184, 92, 58)
local TERRA_DARK = Color3.fromRGB(146, 70, 46)
local EARTH = Color3.fromRGB(78, 54, 38)
local LEAF_D = Color3.fromRGB(52, 104, 50)
local LEAF_M = Color3.fromRGB(78, 136, 62)
local LEAF_L = Color3.fromRGB(116, 168, 78)
local PALE_STONE = Color3.fromRGB(204, 198, 186)
local GREY_STONE = Color3.fromRGB(150, 146, 140)
local BRONZE = Color3.fromRGB(146, 108, 58)
local WOOD_N = Color3.fromRGB(150, 104, 66)
local WOOD_W = Color3.fromRGB(136, 122, 104) -- bois grisé
local PAINT = Color3.fromRGB(244, 242, 236)
local IRON = Color3.fromRGB(44, 42, 48)
local GLASS = Color3.fromRGB(196, 226, 236)

local BLOOMS = {
	Color3.fromRGB(206, 36, 64), -- rouge
	Color3.fromRGB(250, 132, 170), -- rose
	Color3.fromRGB(252, 248, 240), -- blanc
	Color3.fromRGB(255, 200, 62), -- jaune
	Color3.fromRGB(150, 104, 206), -- violet
	Color3.fromRGB(255, 142, 64), -- orange
}

local function L(x: number, y: number, d: number): CFrame
	return CFrame.new(x, y, -d)
end

-- Repère en (x, y, d) dont l'axe X suit la direction (tx, td) du plan du sol
-- (pierres d'une margelle : le long du cercle)
local function along(x: number, y: number, d: number, tx: number, td: number): CFrame
	local dir = Vector3.new(tx, 0, -td)
	if dir.Magnitude < 1e-4 then
		return L(x, y, d)
	end
	dir = dir.Unit
	return CFrame.fromMatrix(Vector3.new(x, y, -d), dir, Vector3.new(0, 1, 0), dir:Cross(Vector3.new(0, 1, 0)))
end

-- Ovale (Part + SpecialMesh "Sphere")
local function egg(kit: any, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, opts: any?): BasePart
	local part = kit:Part(name, size, cf, color, material or M.SmoothPlastic, opts or DECO)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Tube d'un point à un autre (repère du kit : { x, y, d })
local function rod(kit: any, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?, opts: any?): BasePart
	local pa, pb = Vector3.new(a.X, a.Y, -a.Z), Vector3.new(b.X, b.Y, -b.Z)
	local delta = pb - pa
	local length = math.max(0.05, delta.Magnitude)
	local dir = delta.Magnitude > 0.01 and delta.Unit or Vector3.new(0, 1, 0)
	local up = math.abs(dir.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt((pa + pb) / 2, (pa + pb) / 2 + dir, up) * CFrame.Angles(0, math.pi / 2, 0)
	local o = table.clone(opts or DECO)
	o.Shape = Enum.PartType.Cylinder
	return kit:Part(name, Vector3.new(length, diameter, diameter), cf, color, material or M.SmoothPlastic, o)
end

-- Touffe de feuillage (plusieurs ovales) + fleurs piquées dessus
local function shrub(kit: any, rng: Random, x: number, y: number, d: number, w: number, h: number, leaves: { Color3 }, bloom: Color3?, blooms: number, bloomSize: number)
	local n = 4
	for k = 1, n do
		local a = k / n * math.pi * 2 + rng:NextNumber(0, 0.6)
		local r = w * 0.2
		egg(kit, "Leaves", Vector3.new(w * 0.62, h * 0.7, w * 0.62), L(x + math.cos(a) * r, y + h * 0.36, d + math.sin(a) * r), leaves[(k - 1) % #leaves + 1], M.LeafyGrass)
	end
	egg(kit, "Leaves", Vector3.new(w * 0.7, h * 0.8, w * 0.7), L(x, y + h * 0.5, d), leaves[1], M.LeafyGrass)
	if bloom then
		for k = 1, blooms do
			local a = rng:NextNumber(0, math.pi * 2)
			local t = rng:NextNumber(0.35, 1)
			local px = x + math.cos(a) * w * 0.38 * t
			local pd = d + math.sin(a) * w * 0.38 * t
			local py = y + h * (0.45 + 0.5 * math.sqrt(math.max(0, 1 - t * t * 0.8)))
			kit:Ball("Bloom", px, py, pd, bloomSize * rng:NextNumber(0.85, 1.15), bloom:Lerp(WHITE, rng:NextNumber(0, 0.15)), M.SmoothPlastic, DECO)
		end
	end
end

type PieceMaker = (kit: any, variant: number) -> ()
local PIECES: { [string]: PieceMaker } = {}

PIECES.TerracottaPot = function(kit, variant)
	local rng = Random.new(variant * 17 + 3)
	kit:CylY("Saucer", 0, 0, 0, 1.75, 0.12, TERRA_DARK, M.Concrete, DECO)
	kit:CylY("Pot", 0, 0.1, 0, 1.36, 1.02, TERRA, M.Concrete, DECO)
	kit:CylY("PotTaper", 0, 0.06, 0, 1.12, 0.3, TERRA:Lerp(EARTH, 0.1), M.Concrete, DECO)
	kit:CylY("PotRim", 0, 1.08, 0, 1.66, 0.3, TERRA:Lerp(WHITE, 0.08), M.Concrete, DECO)
	kit:CylY("Soil", 0, 1.2, 0, 1.44, 0.22, EARTH, M.Ground, DECO)
	local bloom = BLOOMS[(variant - 1) % #BLOOMS + 1]
	shrub(kit, rng, 0, 1.2, 0, 1.5, 1.2, { LEAF_M, LEAF_D }, bloom, 9, 0.3)
end

PIECES.SteppingStones = function(kit, variant)
	local rng = Random.new(variant * 31 + 5)
	for k = 0, 3 do
		local dk = -2.55 + k * 1.72
		local size = 1.55 + rng:NextNumber(0, 0.45)
		local x = (k % 2 == 0 and -0.25 or 0.25) + rng:NextNumber(-0.1, 0.1)
		local stone = kit:Part("SteppingStone", Vector3.new(0.14 + k * 0.004, size, size * rng:NextNumber(0.82, 0.95)), L(x, 0.02 + k * 0.004, dk) * CFrame.Angles(0, rng:NextNumber(0, 3), math.pi / 2),
			GREY_STONE:Lerp(PALE_STONE, rng:NextNumber(0, 0.6)), M.Slate, { Shadow = false, Shape = Enum.PartType.Cylinder })
		stone.CastShadow = false
	end
end

PIECES.FlowerUrn = function(kit, variant)
	local rng = Random.new(variant * 13 + 7)
	kit:Box("UrnPlinth", -0.7, 0.7, 0, 0.5, -0.7, 0.7, PALE_STONE, M.Limestone, SOLID)
	kit:Box("UrnPlinthCap", -0.78, 0.78, 0.5, 0.62, -0.78, 0.78, PALE_STONE:Lerp(WHITE, 0.15), M.Limestone, DECO)
	kit:CylY("UrnFoot", 0, 0.62, 0, 0.66, 0.5, PALE_STONE, M.Limestone, DECO)
	kit:CylY("UrnNeck", 0, 1.1, 0, 0.9, 0.2, PALE_STONE:Lerp(GREY_STONE, 0.3), M.Limestone, DECO)
	egg(kit, "UrnBowl", Vector3.new(2, 1.05, 2), L(0, 1.62, 0), PALE_STONE, M.Limestone)
	kit:CylY("UrnRim", 0, 1.98, 0, 2.14, 0.2, PALE_STONE:Lerp(WHITE, 0.2), M.Limestone, DECO)
	kit:CylY("Soil", 0, 2.02, 0, 1.86, 0.2, EARTH, M.Ground, DECO)
	local bloom = BLOOMS[(variant % #BLOOMS) + 1]
	shrub(kit, rng, 0, 2.1, 0, 1.7, 1.2, { LEAF_M, LEAF_D }, bloom, 10, 0.3)
	-- lierre qui retombe
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2 + 0.4
		egg(kit, "Ivy", Vector3.new(0.34, 0.9, 0.3), L(math.cos(a) * 0.98, 1.72, math.sin(a) * 0.98) * CFrame.Angles(0, -a, 0.15), LEAF_D:Lerp(LEAF_L, k % 2 * 0.3), M.LeafyGrass)
	end
end

PIECES.RoseBush = function(kit, variant)
	local rng = Random.new(variant * 7 + 11)
	local bloom = ({ BLOOMS[1], BLOOMS[2], BLOOMS[3], Color3.fromRGB(255, 176, 120) })[(variant - 1) % 4 + 1]
	egg(kit, "Mulch", Vector3.new(2.7, 0.2, 2.6), L(0, 0.02, 0), EARTH:Lerp(WOOD_N, 0.3), M.Ground)
	shrub(kit, rng, 0, 0, 0, 2.5, 2.2, { LEAF_D, LEAF_M, LEAF_D }, bloom, 14, 0.4)
	-- quelques boutons plus clairs
	for _ = 1, 4 do
		local a = rng:NextNumber(0, math.pi * 2)
		kit:Ball("Bud", math.cos(a) * 0.8, 1.7 + rng:NextNumber(0, 0.4), math.sin(a) * 0.8, 0.22, bloom:Lerp(WHITE, 0.35), M.SmoothPlastic, DECO)
	end
end

PIECES.GardenLantern = function(kit, _variant)
	kit:CylY("LanternBase", 0, 0, 0, 0.9, 0.24, IRON, M.Metal, SOLID)
	kit:CylY("LanternPost", 0, 0.2, 0, 0.22, 2.9, IRON, M.Metal, DECO)
	kit:CylY("LanternCollar", 0, 3.05, 0, 0.5, 0.14, IRON, M.Metal, DECO)
	kit:Box("LanternFloor", -0.36, 0.36, 3.17, 3.27, -0.36, 0.36, IRON, M.Metal, DECO)
	kit:Box("LanternGlass", -0.3, 0.3, 3.27, 4.03, -0.3, 0.3, Color3.fromRGB(255, 232, 180), M.Glass, { Shadow = false, T = 0.35 })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			kit:Box("LanternFrame", sx * 0.34 - 0.04, sx * 0.34 + 0.04, 3.27, 4.03, sz * 0.34 - 0.04, sz * 0.34 + 0.04, IRON, M.Metal, DECO)
		end
	end
	local bulb = kit:Ball("LanternBulb", 0, 3.6, 0, 0.3, Color3.fromRGB(255, 214, 150), M.SmoothPlastic, DECO)
	bulb:SetAttribute("NightGlow", true)
	kit:Box("LanternCap", -0.44, 0.44, 4.03, 4.13, -0.44, 0.44, IRON, M.Metal, DECO)
	kit:Cone("LanternRoof", 0, 4.12, 0, 0.5, 0.42, 4, IRON, M.Metal)
	kit:Ball("LanternFinial", 0, 4.6, 0, 0.16, IRON, M.Metal, DECO)
end

PIECES.LavenderPlanter = function(kit, variant)
	local rng = Random.new(variant * 19 + 2)
	local wood = WOOD_W:Lerp(WOOD_N, (variant % 3) * 0.3)
	for _, sx in ipairs({ -1, 1 }) do
		kit:Box("PlanterFoot", sx * 2.1 - 0.2, sx * 2.1 + 0.2, 0, 0.23, -0.75, 0.75, wood:Lerp(IRON, 0.3), M.Wood, DECO)
	end
	for row = 0, 2 do
		local y0 = 0.2 + row * 0.34
		kit:Box("PlanterBoard", -2.3, 2.3, y0, y0 + 0.32, -0.85, -0.7, wood:Lerp(WHITE, row * 0.04), M.WoodPlanks, DECO)
		kit:Box("PlanterBoard", -2.3, 2.3, y0, y0 + 0.32, 0.7, 0.85, wood:Lerp(WHITE, row * 0.04), M.WoodPlanks, DECO)
		kit:Box("PlanterBoard", -2.3, -2.15, y0, y0 + 0.32, -0.7, 0.7, wood:Lerp(WHITE, row * 0.04), M.WoodPlanks, DECO)
		kit:Box("PlanterBoard", 2.15, 2.3, y0, y0 + 0.32, -0.7, 0.7, wood:Lerp(WHITE, row * 0.04), M.WoodPlanks, DECO)
	end
	kit:Box("PlanterCap", -2.38, 2.38, 1.22, 1.3, -0.93, -0.62, wood:Lerp(WHITE, 0.12), M.Wood, DECO)
	kit:Box("PlanterCap", -2.38, 2.38, 1.22, 1.3, 0.62, 0.93, wood:Lerp(WHITE, 0.12), M.Wood, DECO)
	kit:Box("Soil", -2.12, 2.12, 0.25, 1.12, -0.67, 0.67, EARTH, M.Ground, DECO)
	local lavender = Color3.fromRGB(146, 112, 196)
	for k = 0, 3 do
		local x = -1.6 + k * 1.07
		egg(kit, "LavenderTuft", Vector3.new(1.0, 0.7, 1.0), L(x, 1.3, 0), Color3.fromRGB(120, 150, 110), M.LeafyGrass)
		for s = 1, 5 do
			local a = s / 5 * math.pi * 2 + rng:NextNumber(0, 0.5)
			local lean = CFrame.Angles(math.sin(a) * 0.25, 0, math.cos(a) * 0.25)
			local base = L(x + math.cos(a) * 0.25, 1.45, math.sin(a) * 0.25) * lean
			kit:Part("LavenderStem", Vector3.new(0.06, 0.9, 0.06), base * CFrame.new(0, 0.45, 0), Color3.fromRGB(110, 140, 96), M.SmoothPlastic, DECO)
			egg(kit, "Lavender", Vector3.new(0.2, 0.62, 0.2), base * CFrame.new(0, 1.12, 0), lavender:Lerp(WHITE, rng:NextNumber(0, 0.2)), M.Fabric)
		end
	end
end

PIECES.HydrangeaBush = function(kit, variant)
	local rng = Random.new(variant * 23 + 1)
	local hues = { Color3.fromRGB(120, 150, 232), Color3.fromRGB(236, 150, 196), Color3.fromRGB(176, 136, 222), Color3.fromRGB(244, 244, 248) }
	local bloom = hues[(variant - 1) % #hues + 1]
	egg(kit, "Mulch", Vector3.new(3.2, 0.2, 3.1), L(0, 0.02, 0), EARTH:Lerp(WOOD_N, 0.3), M.Ground)
	shrub(kit, rng, 0, 0, 0, 3.0, 2.4, { LEAF_M, LEAF_D }, nil, 0, 0)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2 + rng:NextNumber(0, 0.4)
		local r = rng:NextNumber(0.6, 1.1)
		kit:Ball("Hydrangea", math.cos(a) * r, 1.7 + rng:NextNumber(0, 0.6), math.sin(a) * r, rng:NextNumber(0.75, 0.95), bloom:Lerp(WHITE, rng:NextNumber(0, 0.18)), M.Fabric, DECO)
	end
end

PIECES.BirdHouse = function(kit, variant)
	local paint = ({ Color3.fromRGB(120, 170, 200), Color3.fromRGB(226, 120, 110), PAINT, Color3.fromRGB(150, 190, 120) })[(variant - 1) % 4 + 1]
	kit:Box("BirdPost", -0.13, 0.13, 0, 3.5, -0.13, 0.13, WOOD_W, M.Wood, DECO)
	kit:Box("BirdFloor", -0.62, 0.62, 3.5, 3.6, -0.62, 0.62, WOOD_N, M.Wood, DECO)
	kit:Box("BirdBox", -0.5, 0.5, 3.6, 4.5, -0.5, 0.5, paint, M.WoodPlanks, DECO)
	-- pignon + toit à deux pentes
	kit:Part("BirdGable", Vector3.new(0.98, 0.45, 0.5), L(0.245, 4.72, 0) * CFrame.Angles(0, -math.pi / 2, 0), paint, M.WoodPlanks, DECO, "WedgePart")
	kit:Part("BirdGable", Vector3.new(0.98, 0.45, 0.5), L(-0.245, 4.72, 0) * CFrame.Angles(0, math.pi / 2, 0), paint, M.WoodPlanks, DECO, "WedgePart")
	for _, s in ipairs({ -1, 1 }) do
		kit:SlabX("BirdRoof", 0, { s * 0.72, 4.4 }, { 0, 5.0 }, 1.3, 0.1, Color3.fromRGB(96, 70, 60), M.WoodPlanks, DECO)
		local _ = s
	end
	kit:CylD("BirdHole", 0, 4.15, -0.52, 0.34, 0.06, Color3.fromRGB(30, 22, 18), M.SmoothPlastic, DECO)
	kit:CylD("BirdPerch", 0, 3.85, -0.62, 0.07, 0.3, WOOD_N, M.Wood, DECO)
	-- petite mésange posée
	local blue, yellow = Color3.fromRGB(70, 110, 180), Color3.fromRGB(240, 204, 70)
	egg(kit, "Bird", Vector3.new(0.3, 0.3, 0.44), L(0.25, 3.72, -0.72), yellow, M.SmoothPlastic)
	kit:Ball("BirdHead", 0.25, 3.94, -0.86, 0.22, blue, M.SmoothPlastic, DECO)
	kit:Part("BirdTail", Vector3.new(0.08, 0.06, 0.3), L(0.25, 3.76, -0.48), blue, M.SmoothPlastic, DECO)
end

PIECES.HangingBasket = function(kit, variant)
	local rng = Random.new(variant * 29 + 3)
	kit:CylY("HookPost", 0, 0, 0, 0.14, 4.4, IRON, M.Metal, DECO)
	-- crosse
	rod(kit, "Hook", Vector3.new(0, 4.4, 0), Vector3.new(0.35, 4.75, 0), 0.12, IRON, M.Metal)
	rod(kit, "Hook", Vector3.new(0.35, 4.75, 0), Vector3.new(0.8, 4.78, 0), 0.12, IRON, M.Metal)
	rod(kit, "Hook", Vector3.new(0.8, 4.78, 0), Vector3.new(0.95, 4.55, 0), 0.12, IRON, M.Metal)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		rod(kit, "Chain", Vector3.new(0.95, 4.5, 0), Vector3.new(0.95 + math.cos(a) * 0.5, 3.25, math.sin(a) * 0.5), 0.04, IRON, M.Metal)
	end
	egg(kit, "Basket", Vector3.new(1.2, 0.9, 1.2), L(0.95, 3.1, 0), Color3.fromRGB(150, 110, 70), M.Fabric)
	local bloom = BLOOMS[(variant + 1) % #BLOOMS + 1]
	shrub(kit, rng, 0.95, 3.1, 0, 1.3, 0.8, { LEAF_M }, bloom, 8, 0.24)
	for k = 1, 4 do
		local a = k / 4 * math.pi * 2 + 0.3
		egg(kit, "Trailing", Vector3.new(0.3, 0.8, 0.3), L(0.95 + math.cos(a) * 0.55, 2.8, math.sin(a) * 0.55), LEAF_D, M.LeafyGrass)
		kit:Ball("Bloom", 0.95 + math.cos(a) * 0.6, 2.55, math.sin(a) * 0.6, 0.22, bloom, M.SmoothPlastic, DECO)
	end
end

PIECES.RoundFlowerBed = function(kit, variant)
	local rng = Random.new(variant * 37 + 9)
	local radius = 2.7
	for k = 0, 13 do
		local a = k / 14 * math.pi * 2
		local cf = along(math.cos(a) * radius, 0.22, math.sin(a) * radius, -math.sin(a), math.cos(a))
		kit:Part("BedStone", Vector3.new(1.18, 0.44 + (k % 3) * 0.03, 0.42), cf, GREY_STONE:Lerp(PALE_STONE, (k % 4) / 4), M.Slate, DECO)
	end
	kit:CylY("BedSoil", 0, 0, 0, radius * 2 - 0.3, 0.36, EARTH, M.Ground, DECO)
	-- cercle extérieur de petites fleurs, puis un cœur plus haut
	local outer = BLOOMS[(variant - 1) % #BLOOMS + 1]
	local inner = BLOOMS[(variant + 2) % #BLOOMS + 1]
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		egg(kit, "Tuft", Vector3.new(0.8, 0.5, 0.8), L(math.cos(a) * 1.95, 0.45, math.sin(a) * 1.95), LEAF_M, M.LeafyGrass)
		kit:Ball("Bloom", math.cos(a) * 1.95, 0.72, math.sin(a) * 1.95, 0.34, outer:Lerp(WHITE, rng:NextNumber(0, 0.15)), M.SmoothPlastic, DECO)
	end
	shrub(kit, rng, 0, 0.3, 0, 2.2, 1.6, { LEAF_D, LEAF_M }, inner, 10, 0.34)
end

PIECES.GardenBench = function(kit, variant)
	local wood = ({ Color3.fromRGB(170, 120, 78), WOOD_W, Color3.fromRGB(120, 150, 110) })[(variant - 1) % 3 + 1]
	HouseGarden.Bench(kit, 0, 0, wood)
end

PIECES.VegetablePatch = function(kit, variant)
	local rng = Random.new(variant * 41 + 4)
	local wood = WOOD_W
	for _, side in ipairs({ -1, 1 }) do
		kit:Box("PatchBoard", -3.2, 3.2, 0, 0.6, side * 1.9 - 0.12, side * 1.9 + 0.12, wood, M.WoodPlanks, SOLID)
		kit:Box("PatchBoard", side * 3.08 - 0.12, side * 3.08 + 0.12, 0, 0.6, -1.78, 1.78, wood, M.WoodPlanks, SOLID)
	end
	kit:Box("PatchSoil", -2.94, 2.94, 0.02, 0.5, -1.76, 1.76, EARTH:Lerp(Color3.new(0, 0, 0), 0.1), M.Ground, DECO)
	-- rangée 1 : salades ; rangée 2 : carottes ; rangée 3 : tomates tuteurées
	for k = 0, 4 do
		local x = -2.4 + k * 1.2
		egg(kit, "Lettuce", Vector3.new(0.9, 0.55, 0.9), L(x, 0.62, -1.15), Color3.fromRGB(150, 200, 96):Lerp(LEAF_M, rng:NextNumber(0, 0.4)), M.LeafyGrass)
		for s = 0, 2 do
			kit:Part("CarrotLeaf", Vector3.new(0.06, 0.7, 0.18), L(x + (s - 1) * 0.16, 0.85, 0) * CFrame.Angles(0, s, (s - 1) * 0.35), Color3.fromRGB(96, 170, 70), M.LeafyGrass, DECO)
		end
		kit:Ball("Carrot", x, 0.5, 0, 0.22, Color3.fromRGB(240, 130, 40), M.SmoothPlastic, DECO)
	end
	for k = 0, 2 do
		local x = -2 + k * 2
		kit:Box("TomatoStake", x - 0.05, x + 0.05, 0.4, 2.6, 1.15, 1.25, WOOD_N, M.Wood, DECO)
		egg(kit, "TomatoPlant", Vector3.new(0.9, 1.8, 0.8), L(x, 1.4, 1.1), LEAF_D, M.LeafyGrass)
		for s = 1, 4 do
			local a = s * 1.7 + k
			kit:Ball("Tomato", x + math.cos(a) * 0.36, 0.9 + s * 0.32, 1.1 + math.sin(a) * 0.32, 0.26, Color3.fromRGB(214, 44, 36), M.SmoothPlastic, DECO)
		end
	end
end

PIECES.PicnicTable = function(kit, variant)
	local wood = ({ Color3.fromRGB(166, 116, 74), WOOD_W })[(variant - 1) % 2 + 1]
	-- plateau (5 planches) et bancs (2 planches de chaque côté)
	for k = 0, 4 do
		local d0 = -1.3 + k * 0.53
		kit:Box("TableBoard", -2.6, 2.6, 2.5, 2.66, d0, d0 + 0.49, wood:Lerp(WHITE, (k % 2) * 0.05), M.WoodPlanks, if k == 2 then SOLID else DECO)
	end
	for _, side in ipairs({ -1, 1 }) do
		for k = 0, 1 do
			local d0 = side * 2.05 - 0.45 + k * 0.46
			kit:Box("BenchBoard", -2.6, 2.6, 1.5, 1.64, d0, d0 + 0.42, wood, M.WoodPlanks, DECO)
		end
	end
	-- pieds en A + traverses
	for _, sx in ipairs({ -1.9, 1.9 }) do
		for _, side in ipairs({ -1, 1 }) do
			rod(kit, "TableLeg", Vector3.new(sx, 0, side * 1.95), Vector3.new(sx, 2.5, side * 0.35), 0.24, wood:Lerp(IRON, 0.15), M.Wood)
		end
		kit:Box("TableBrace", sx - 0.12, sx + 0.12, 1.36, 1.5, -2.4, 2.4, wood:Lerp(IRON, 0.15), M.Wood, DECO)
	end
	local block = kit:Box("TableBlock", -2.6, 2.6, 0, 1.5, -2.4, 2.4, wood, M.Wood, SOLID)
	block.Transparency = 1
	block.CastShadow = false
end

PIECES.Sundial = function(kit, _variant)
	kit:CylY("SundialStep", 0, 0, 0, 2.3, 0.3, GREY_STONE, M.Slate, SOLID)
	kit:CylY("SundialBase", 0, 0.3, 0, 1.3, 0.3, PALE_STONE, M.Limestone, DECO)
	kit:CylY("SundialColumn", 0, 0.6, 0, 0.8, 1.9, PALE_STONE, M.Limestone, DECO)
	kit:CylY("SundialTop", 0, 2.5, 0, 1.4, 0.24, PALE_STONE:Lerp(WHITE, 0.2), M.Limestone, DECO)
	kit:CylY("SundialDial", 0, 2.74, 0, 1.2, 0.07, BRONZE, M.Metal, DECO)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		kit:Box("HourMark", math.cos(a) * 0.5 - 0.035, math.cos(a) * 0.5 + 0.035, 2.82, 2.85, math.sin(a) * 0.5 - 0.035, math.sin(a) * 0.5 + 0.035, BRONZE:Lerp(IRON, 0.5), M.Metal, DECO)
	end
	kit:Part("Gnomon", Vector3.new(0.05, 0.5, 0.55), L(0, 3.06, 0.05), BRONZE, M.Metal, DECO, "WedgePart")
end

-- Arche de roses (on passe dessous, le long de d)
local function roseArch(kit: any, variant: number, width: number)
	local rng = Random.new(variant * 43 + 8)
	local half = width / 2
	local bloom = ({ BLOOMS[2], BLOOMS[1], BLOOMS[3] })[(variant - 1) % 3 + 1]
	for _, sx in ipairs({ -1, 1 }) do
		for _, sd in ipairs({ -0.75, 0.75 }) do
			kit:Box("ArchPost", sx * half - 0.1, sx * half + 0.1, 0, 5.2, sd - 0.1, sd + 0.1, PAINT, M.Wood, if sd < 0 then SOLID else DECO)
		end
		for k = 0, 4 do
			kit:Box("ArchLattice", sx * half - 0.05, sx * half + 0.05, 0.6 + k * 1, 0.68 + k * 1, -0.68, 0.68, PAINT, M.Wood, DECO)
		end
	end
	-- arc : 9 segments
	local n = 9
	for k = 0, n - 1 do
		local a0, a1 = k / n * math.pi, (k + 1) / n * math.pi
		for _, sd in ipairs({ -0.75, 0.75 }) do
			rod(kit, "ArchBow", Vector3.new(math.cos(a0) * half, 5.2 + math.sin(a0) * 1.4, sd), Vector3.new(math.cos(a1) * half, 5.2 + math.sin(a1) * 1.4, sd), 0.16, PAINT, M.Wood)
		end
		local am = (a0 + a1) / 2
		kit:Box("ArchSlat", math.cos(am) * half - 0.06, math.cos(am) * half + 0.06, 5.12 + math.sin(am) * 1.4, 5.24 + math.sin(am) * 1.4, -0.85, 0.85, PAINT, M.Wood, DECO)
	end
	-- rosier grimpant
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 4 do
			local y = 0.8 + k * 1.1
			egg(kit, "ClimbingLeaves", Vector3.new(0.7, 1.2, 1.5), L(sx * (half + 0.05), y, rng:NextNumber(-0.3, 0.3)), k % 2 == 0 and LEAF_D or LEAF_M, M.LeafyGrass)
			kit:Ball("Rose", sx * (half + 0.35), y + 0.2, rng:NextNumber(-0.6, 0.6), 0.3, bloom, M.SmoothPlastic, DECO)
		end
	end
	for k = 1, 7 do
		local a = k / 8 * math.pi
		egg(kit, "ClimbingLeaves", Vector3.new(1.1, 0.6, 1.6), L(math.cos(a) * half, 5.35 + math.sin(a) * 1.4, 0), LEAF_M, M.LeafyGrass)
		kit:Ball("Rose", math.cos(a) * half, 5.7 + math.sin(a) * 1.4, rng:NextNumber(-0.6, 0.6), 0.32, bloom, M.SmoothPlastic, DECO)
	end
end

PIECES.RoseArbor = function(kit, variant)
	roseArch(kit, variant, 4.6)
end

PIECES.GardenSwing = function(kit, variant)
	local wood = ({ Color3.fromRGB(170, 120, 78), PAINT })[(variant - 1) % 2 + 1]
	-- portique en A
	for _, sx in ipairs({ -2.6, 2.6 }) do
		for _, side in ipairs({ -1, 1 }) do
			rod(kit, "SwingLeg", Vector3.new(sx, 0, side * 1.55), Vector3.new(sx, 5.3, 0), 0.3, wood, M.Wood)
		end
		kit:Box("SwingBrace", sx - 0.1, sx + 0.1, 1.6, 1.8, -1.1, 1.1, wood, M.Wood, DECO)
	end
	kit:Box("SwingBeam", -2.9, 2.9, 5.3, 5.62, -0.16, 0.16, wood, M.Wood, DECO)
	-- balancelle (assise + dossier + coussins) suspendue par 4 cordes
	local cushion = ({ Color3.fromRGB(230, 120, 120), Color3.fromRGB(120, 170, 210), Color3.fromRGB(240, 220, 150) })[(variant - 1) % 3 + 1]
	kit:Box("SwingSeat", -1.6, 1.6, 1.6, 1.78, -0.55, 0.55, wood, M.WoodPlanks, DECO)
	kit:Box("SwingCushion", -1.5, 1.5, 1.78, 1.98, -0.48, 0.48, cushion, M.Fabric, DECO)
	kit:Part("SwingBack", Vector3.new(3.2, 1.1, 0.14), L(0, 2.35, 0.62) * CFrame.Angles(-math.rad(12), 0, 0), wood, M.WoodPlanks, DECO)
	kit:Part("SwingBackCushion", Vector3.new(3.0, 0.9, 0.16), L(0, 2.4, 0.46) * CFrame.Angles(-math.rad(12), 0, 0), cushion:Lerp(WHITE, 0.1), M.Fabric, DECO)
	for _, sx in ipairs({ -1.5, 1.5 }) do
		for _, sd in ipairs({ -0.45, 0.45 }) do
			rod(kit, "SwingRope", Vector3.new(sx, 5.3, 0), Vector3.new(sx, 1.78, sd), 0.06, Color3.fromRGB(200, 180, 140), M.Fabric)
		end
	end
end

PIECES.StoneStatue = function(kit, _variant)
	local stone = Color3.fromRGB(214, 210, 202)
	kit:Box("StatuePlinth", -1.1, 1.1, 0, 1.5, -1.1, 1.1, GREY_STONE:Lerp(PALE_STONE, 0.4), M.Limestone, SOLID)
	kit:Box("StatueCap", -1.22, 1.22, 1.5, 1.7, -1.22, 1.22, PALE_STONE, M.Limestone, DECO)
	-- robe (cône par tranches), buste, tête, bras croisés, ailes
	for k = 0, 3 do
		kit:CylY("StatueRobe", 0, 1.7 + k * 0.55, 0, 1.4 - k * 0.2, 0.58, stone, M.Marble, DECO)
	end
	egg(kit, "StatueChest", Vector3.new(0.9, 0.9, 0.7), L(0, 4.2, 0), stone, M.Marble)
	kit:Ball("StatueHead", 0, 4.95, -0.05, 0.62, stone, M.Marble, DECO)
	egg(kit, "StatueHair", Vector3.new(0.68, 0.5, 0.66), L(0, 5.1, 0.04), stone:Lerp(GREY_STONE, 0.15), M.Marble)
	for _, s in ipairs({ -1, 1 }) do
		kit:Part("StatueArm", Vector3.new(0.22, 0.8, 0.24), L(s * 0.3, 4.05, -0.3) * CFrame.Angles(math.rad(50), 0, s * math.rad(55)), stone, M.Marble, DECO)
		egg(kit, "StatueWing", Vector3.new(0.18, 1.9, 1.1), L(s * 0.62, 4.4, 0.55) * CFrame.Angles(math.rad(-20), s * math.rad(-25), s * math.rad(-18)), stone:Lerp(WHITE, 0.1), M.Marble)
	end
	-- mousse au pied
	for k = 0, 3 do
		local a = k * 1.6
		egg(kit, "Moss", Vector3.new(0.9, 0.3, 0.6), L(math.cos(a) * 1.15, 0.1, math.sin(a) * 1.15), LEAF_D, M.Grass)
	end
end

PIECES.Gazebo = function(kit, _variant)
	local sides = 8
	local r = 4.7
	kit:CylY("GazeboBase", 0, 0, 0, r * 2 + 0.6, 0.4, GREY_STONE, M.Slate, SOLID)
	kit:CylY("GazeboDeck", 0, 0.38, 0, r * 2, 0.3, Color3.fromRGB(176, 136, 96), M.WoodPlanks, SOLID)
	for k = 0, sides - 1 do
		local a = (k + 0.5) / sides * math.pi * 2
		local x, dd = math.cos(a) * (r - 0.3), math.sin(a) * (r - 0.3)
		kit:Box("GazeboPost", x - 0.16, x + 0.16, 0.68, 6.2, dd - 0.16, dd + 0.16, PAINT, M.Wood, SOLID)
		-- garde-corps (sauf l'entrée, face à la rue : côté -d)
		local a2 = (k + 1.5) / sides * math.pi * 2
		local x2, d2 = math.cos(a2) * (r - 0.3), math.sin(a2) * (r - 0.3)
		local midA = (k + 1) / sides * math.pi * 2
		local isEntrance = math.sin(midA) < -0.9
		if not isEntrance then
			rod(kit, "GazeboRail", Vector3.new(x, 2.4, dd), Vector3.new(x2, 2.4, d2), 0.14, PAINT, M.Wood)
			rod(kit, "GazeboRail", Vector3.new(x, 1.2, dd), Vector3.new(x2, 1.2, d2), 0.1, PAINT, M.Wood)
			for s = 1, 3 do
				local t = s / 4
				local bx, bd = x + (x2 - x) * t, dd + (d2 - dd) * t
				kit:Box("GazeboBaluster", bx - 0.05, bx + 0.05, 0.68, 2.34, bd - 0.05, bd + 0.05, PAINT, M.Wood, DECO)
			end
		end
		-- lambrequin sous le toit
		rod(kit, "GazeboFascia", Vector3.new(x, 6.1, dd), Vector3.new(x2, 6.1, d2), 0.3, PAINT, M.Wood)
	end
	kit:CylY("GazeboRing", 0, 6.1, 0, r * 2 + 0.2, 0.3, PAINT, M.Wood, DECO)
	kit:Cone("GazeboRoof", 0, 6.4, 0, r + 0.8, 3.2, sides, Color3.fromRGB(96, 130, 120), M.Slate)
	kit:CylY("GazeboFinialBase", 0, 9.45, 0, 0.5, 0.3, PAINT, M.Wood, DECO)
	kit:Ball("GazeboFinial", 0, 9.9, 0, 0.44, BRONZE, M.Metal, DECO)
	-- banc circulaire au fond
	for k = 1, 3 do
		local a = (k + 1) / sides * math.pi * 2
		local x, dd = math.cos(a) * (r - 1.1), math.sin(a) * (r - 1.1)
		kit:Part("GazeboSeat", Vector3.new(2.6, 0.16, 0.8), along(x, 1.9, dd, -math.sin(a), math.cos(a)), Color3.fromRGB(176, 136, 96), M.WoodPlanks, DECO)
	end
end

PIECES.TieredFountain = function(kit, _variant)
	local stone = PALE_STONE
	local water = Color3.fromRGB(120, 180, 210)
	-- bassin octogonal (8 margelles) + eau
	local r = 4.3
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local side = 2 * r * math.tan(math.pi / 8) + 0.02 * (k % 2)
		kit:Part("FountainRim", Vector3.new(side, 1.1 + (k % 2) * 0.03, 0.6), along(math.cos(a) * r, 0.55, math.sin(a) * r, -math.sin(a), math.cos(a)), stone, M.Limestone, SOLID)
	end
	kit:CylY("FountainFloor", 0, 0, 0, r * 2 - 0.2, 0.3, GREY_STONE, M.Slate, DECO)
	kit:CylY("FountainWater", 0, 0.3, 0, r * 2 - 0.3, 0.55, water, M.Glass, { Shadow = false, T = 0.3 })
	kit:CylY("FountainColumn", 0, 0.3, 0, 1.1, 2.6, stone, M.Limestone, SOLID)
	egg(kit, "FountainBowl1", Vector3.new(4.4, 1.0, 4.4), L(0, 2.9, 0), stone, M.Limestone)
	kit:CylY("FountainRim1", 0, 3.2, 0, 4.5, 0.22, stone:Lerp(WHITE, 0.2), M.Limestone, DECO)
	kit:CylY("FountainWater1", 0, 3.22, 0, 4.1, 0.26, water, M.Glass, { Shadow = false, T = 0.25 })
	kit:CylY("FountainColumn2", 0, 3.45, 0, 0.6, 1.5, stone, M.Limestone, DECO)
	egg(kit, "FountainBowl2", Vector3.new(2.2, 0.6, 2.2), L(0, 5.0, 0), stone, M.Limestone)
	kit:CylY("FountainRim2", 0, 5.18, 0, 2.3, 0.16, stone:Lerp(WHITE, 0.2), M.Limestone, DECO)
	kit:CylY("FountainWater2", 0, 5.2, 0, 2.0, 0.2, water, M.Glass, { Shadow = false, T = 0.25 })
	kit:CylY("FountainTop", 0, 5.4, 0, 0.36, 0.8, stone, M.Limestone, DECO)
	local spout = kit:Ball("FountainSpout", 0, 6.3, 0, 0.44, stone, M.Limestone, DECO)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FountainSpray"
	emitter.Color = ColorSequence.new(Color3.fromRGB(230, 246, 255), Color3.fromRGB(170, 214, 240))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0.08) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.85) })
	emitter.Lifetime = NumberRange.new(0.7, 0.95)
	emitter.Speed = NumberRange.new(4.5, 5.5)
	emitter.SpreadAngle = Vector2.new(16, 16)
	emitter.Acceleration = Vector3.new(0, -16, 0)
	emitter.Rate = 14
	emitter.LightInfluence = 1
	emitter.Parent = spout
	-- rideaux d'eau des vasques (fines gouttes)
	for index, y in ipairs({ 3.3, 5.25 }) do
		local anchor = kit:Ball("FountainDrip", 0, y, 0, 0.2, stone, M.Limestone, { Shadow = false, T = 1 })
		local drip = Instance.new("ParticleEmitter")
		drip.Name = "FountainCurtain"
		drip.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
		drip.Size = NumberSequence.new(0.1)
		drip.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.9) })
		drip.Lifetime = NumberRange.new(0.35, 0.5)
		drip.Speed = NumberRange.new(index == 1 and 5 or 3, index == 1 and 5.5 or 3.4)
		drip.SpreadAngle = Vector2.new(180, 0)
		drip.EmissionDirection = Enum.NormalId.Right
		drip.Acceleration = Vector3.new(0, -18, 0)
		drip.Rate = 16
		drip.LightInfluence = 1
		drip.Parent = anchor
	end
end

-- Serre (bonus du niveau 2) : armature, vitres, toit à deux pans, étagères de pots
PIECES.Greenhouse = function(kit, _variant)
	local frame = Color3.fromRGB(236, 238, 236)
	local w, dp, h = 9.6, 6.6, 4.6
	kit:Box("GreenhouseBase", -w / 2 - 0.2, w / 2 + 0.2, 0, 0.5, -dp / 2 - 0.2, dp / 2 + 0.2, Color3.fromRGB(170, 110, 90), M.Brick, SOLID)
	kit:Box("GreenhouseFloor", -w / 2 + 0.2, w / 2 - 0.2, 0.5, 0.56, -dp / 2 + 0.2, dp / 2 - 0.2, GREY_STONE, M.Slate, DECO)
	local glassOpts = { Shadow = false, T = 0.6 }
	-- murs vitrés (porte au milieu de la face avant)
	for _, side in ipairs({ -1, 1 }) do
		kit:Box("GreenhouseGlass", -w / 2 + 0.1, w / 2 - 0.1, 0.5, h, side * dp / 2 - 0.04, side * dp / 2 + 0.04, GLASS, M.Glass, if side > 0 then glassOpts else { Shadow = false, T = 0.62 })
		kit:Box("GreenhouseGlass", side * w / 2 - 0.04, side * w / 2 + 0.04, 0.5, h, -dp / 2 + 0.1, dp / 2 - 0.1, GLASS, M.Glass, glassOpts)
	end
	-- montants
	for k = 0, 6 do
		local x = -w / 2 + k * w / 6
		for _, side in ipairs({ -1, 1 }) do
			kit:Box("GreenhouseMullion", x - 0.08, x + 0.08, 0.5, h, side * dp / 2 - 0.1, side * dp / 2 + 0.1, frame, M.Metal, DECO)
		end
	end
	for k = 1, 3 do
		local dk = -dp / 2 + k * dp / 4
		for _, sx in ipairs({ -1, 1 }) do
			kit:Box("GreenhouseMullion", sx * w / 2 - 0.1, sx * w / 2 + 0.1, 0.5, h, dk - 0.08, dk + 0.08, frame, M.Metal, DECO)
		end
	end
	for _, y in ipairs({ 0.55, h - 0.1 }) do
		kit:Box("GreenhouseRail", -w / 2 - 0.12, w / 2 + 0.12, y, y + 0.14, -dp / 2 - 0.12, -dp / 2 + 0.12, frame, M.Metal, DECO)
		kit:Box("GreenhouseRail", -w / 2 - 0.12, w / 2 + 0.12, y, y + 0.14, dp / 2 - 0.12, dp / 2 + 0.12, frame, M.Metal, DECO)
	end
	-- toit vitré à deux pans + faîtage
	for _, side in ipairs({ -1, 1 }) do
		kit:Slab("GreenhouseRoof", 0, { h, side * (dp / 2 + 0.25) }, { h + 2, 0 }, w + 0.3, 0.08, GLASS, M.Glass, { Shadow = false, T = 0.55 })
		for k = 0, 6 do
			local x = -w / 2 + k * w / 6
			kit:Slab("GreenhouseRafter", x, { h + 0.14, side * (dp / 2 + 0.25) }, { h + 2.14, 0 }, 0.14, 0.14, frame, M.Metal, DECO)
		end
		kit:Triangle("GreenhouseGable", { side * w / 2, h, -dp / 2 }, { side * w / 2, h, dp / 2 }, { side * w / 2, h + 2, 0 }, 0.06, GLASS, M.Glass, { Shadow = false, T = 0.6 })
	end
	kit:Box("GreenhouseRidge", -w / 2 - 0.2, w / 2 + 0.2, h + 1.98, h + 2.18, -0.12, 0.12, frame, M.Metal, DECO)
	-- étagères + pots à l'intérieur
	for _, side in ipairs({ -1, 1 }) do
		local dd = side * (dp / 2 - 0.9)
		kit:Box("GreenhouseShelf", -w / 2 + 0.6, w / 2 - 0.6, 1.9, 2.02, dd - 0.6, dd + 0.6, WOOD_N, M.WoodPlanks, DECO)
		for _, sx in ipairs({ -1, 1 }) do
			kit:Box("GreenhouseShelfLeg", sx * (w / 2 - 0.8) - 0.08, sx * (w / 2 - 0.8) + 0.08, 0.56, 1.9, dd - 0.08, dd + 0.08, WOOD_N, M.Wood, DECO)
		end
		for k = 0, 5 do
			local x = -w / 2 + 1.3 + k * (w - 2.6) / 5
			kit:CylY("GreenhousePot", x, 2.02, dd, 0.6, 0.5, TERRA, M.Concrete, DECO)
			egg(kit, "GreenhousePlant", Vector3.new(0.8, 0.8 + (k % 3) * 0.25, 0.8), L(x, 2.75, dd), (k % 2 == 0) and LEAF_M or LEAF_L, M.LeafyGrass)
			if k % 2 == 1 then
				kit:Ball("Bloom", x + 0.15, 3.1, dd, 0.26, BLOOMS[k % #BLOOMS + 1], M.SmoothPlastic, DECO)
			end
		end
	end
end

-- Bassin aux carpes (bonus du niveau 3) : margelle de pierres, eau, nénuphars ;
-- les carpes (modèles "Koi") nagent (GardenBuilder les anime)
PIECES.KoiPond = function(kit, variant)
	local rng = Random.new(variant * 53 + 6)
	local rx, rd = 4.2, 2.7
	for k = 0, 17 do
		local a = k / 18 * math.pi * 2
		local cf = along(math.cos(a) * rx, 0.22, math.sin(a) * rd, -math.sin(a) * rx, math.cos(a) * rd)
		kit:Part("PondStone", Vector3.new(1.3, 0.44 + (k % 3) * 0.04, 0.7), cf, GREY_STONE:Lerp(PALE_STONE, rng:NextNumber(0, 0.7)), M.Slate, DECO)
	end
	egg(kit, "PondBed", Vector3.new(rx * 2 - 0.2, 0.3, rd * 2 - 0.2), L(0, -0.05, 0), Color3.fromRGB(52, 76, 70), M.Slate)
	local water = kit:Part("PondWater", Vector3.new(rx * 2 - 0.4, 0.06, rd * 2 - 0.4), L(0, 0.3, 0), Color3.fromRGB(70, 130, 140), M.Glass, { Shadow = false, T = 0.35 })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = water
	for k = 1, 5 do
		local x, dd = rng:NextNumber(-2.8, 2.8), rng:NextNumber(-1.6, 1.6)
		kit:Part("LilyPad", Vector3.new(0.05, 1.0, 1.0), L(x, 0.35 + k * 0.004, dd) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 140, 70), M.SmoothPlastic, { Shadow = false, Shape = Enum.PartType.Cylinder })
		if k % 2 == 1 then
			kit:Ball("LilyFlower", x + 0.1, 0.48, dd, 0.3, Color3.fromRGB(255, 200, 220), M.SmoothPlastic, DECO)
		end
	end
	-- iris au bord
	for _, spot in ipairs({ { -4.2, 1.8 }, { 4.0, -2.0 } }) do
		for s = 0, 4 do
			kit:Part("Iris", Vector3.new(0.08, 1.4, 0.24), L(spot[1] + (s - 2) * 0.16, 0.9, spot[2]) * CFrame.Angles(0, s, (s - 2) * 0.12), LEAF_M, M.LeafyGrass, DECO)
		end
		kit:Ball("IrisFlower", spot[1], 1.7, spot[2], 0.34, Color3.fromRGB(120, 100, 210), M.SmoothPlastic, DECO)
	end
	-- carpes koï (animées)
	for k = 1, 3 do
		local color = ({ Color3.fromRGB(255, 120, 40), Color3.fromRGB(250, 246, 240), Color3.fromRGB(240, 70, 50) })[k]
		local fish = egg(kit, "Koi", Vector3.new(0.34, 0.2, 0.9), L(0, 0.2, 0), color, M.SmoothPlastic)
		fish:SetAttribute("KoiIndex", k)
	end
end

-- Arche de roses offerte (niveau 1) : plus large, on y passe à deux
PIECES.RoseArch = function(kit, variant)
	roseArch(kit, variant + 1, 4.8)
end

function HouseGarden.HasPiece(id: string): boolean
	return PIECES[id] ~= nil
end

-- (v9.8 GARDEN98) objet de jardin (ou aménagement bonus) au centre du kit
function HouseGarden.BuildPiece(kit: any, id: string, variant: number?)
	local maker = PIECES[id]
	if maker then
		maker(kit, math.max(1, math.floor(tonumber(variant) or 1)))
	else
		fallback(kit, 0, 0, { Icon = "🪴" })
	end
end

return HouseGarden
