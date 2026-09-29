--[[
	TownPlaza (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownPlaza

	⛲ La place centrale de Dopamine Town (v9.4) :
	  - pavage en pierre avec anneaux et soleil rayonnant (motifs de pavés) ;
	  - FONTAINE monumentale : bassin à margelle, eau transparente, deux
	    vasques, jets animés (particules) et, au sommet, la mascotte :
	    un CERVEAU rose kawaii qui crache de l'eau ;
	  - kiosque à musique, manège, chariot à ballons, parterres de fleurs,
	    arbres en bacs, bancs (vrais Seat), lampadaires reliés par des
	    guirlandes lumineuses ;
	  - couronne de BOUTIQUES tout autour (TownBuildings) en laissant libres
	    les débouchés des rues et la mairie (au fond, face à l'avenue).
	v9.6 (SHOPS96) : la couronne commence par les 6 BOUTIQUES OÙ L'ON ENTRE
	(TownShops : animalerie, jouets, cuisine, meubles, setup, jardinerie ;
	intérieurs construits par le client, ShopInteriors), complétées par des
	boutiques de décor fermées ; lumières adoucies (plus de "flash") :
	lumière de la fontaine 1, ampoules des guirlandes plus petites, plus de
	néon sur les grandes surfaces.
v9.7 (PLAZA97) : chaque pièce maîtresse refaite, "10x mieux", réaliste
et stylisée :
  - pavage : rose des vents en mosaïque (8 pointes bicolores), pastilles
    de pierre sous le manège et le kiosque ;
  - FONTAINE à trois niveaux : margelle à 12 pans (pierre + couronnement
    rose), bassin, pied, vasque basse à bord festonné et rideau d'eau,
    balustre, vasque haute, et la mascotte CERVEAU refaite (deux lobes,
    circonvolutions, grands yeux brillants, joues, bouche ouverte, bras
    levés, petits pieds) ; 8 jets en arc, ronds dans l'eau, pupitre ;
  - KIOSQUE à musique octogonal : socle, plancher, marches, 8 colonnes,
    garde-corps à balustres, frise, toit en pyramide à 8 pans bicolores,
    épi de faîtage, pupitres et grosse caisse ;
  - MANÈGE : socle à deux marches + guérite "🎠" ; la partie qui TOURNE
    (plateau, jupe, fût à miroirs, 10 chevaux qui montent et descendent,
    2 carrosses, auvent rayé festonné, ampoules) est construite et animée
    par le client (Client/World/TownPlazaFx) : attributs "Fx…" du dossier
    Plaza ;
  - chariot à ballons (ballons animés côté client), stand de GLACES, stand
    de BARBE À PAPA, coin du musicien de rue (sans PNJ), dessins à la
    craie (marelle, cœurs), parterres de fleurs en vrais massifs,
    lampadaires à deux lanternes (TownKit.Light la nuit, TownKit.Glow) ;
  - guirlandes lumineuses, fanions, pigeons : côté client (TownPlazaFx).
  Budget : 5 vraies lumières (fontaine, kiosque, manège, 2 lampadaires).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)
local TownBuildings = require(script.Parent.TownBuildings)
local TownShops = require(script.Parent.TownShops)
local TownFair = require(script.Parent.TownFair) -- (v9.8, FAIR98) manège où l'on monte, bornes des stands

local TownPlaza = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part

local WALK_Y = WorldLayout.WALK_Y
local R = WorldLayout.PLAZA_R
local FACADE_R = R + 4 -- façades des boutiques de la place

local function emitter(host: BasePart, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = "Water"
	e.Color = ColorSequence.new(Color3.fromRGB(214, 244, 255), Color3.fromRGB(255, 255, 255))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.8) })
	e.LightEmission = 0.15
	e.Acceleration = Vector3.new(0, -24, 0)
	for key, value in pairs(props) do
		(e :: any)[key] = value
	end
	e.Parent = host
	return e
end

-- (v9.7) Triangle rectangle en WedgePart : angle droit en `p0`, un côté le
-- long de `u` (longueur l1), l'autre le long de `v` (longueur l2, v ⟂ u),
-- épaisseur `t` de part et d'autre du plan. (Un WedgePart a son angle droit
-- en (y = -h/2, z = +d/2) et ses côtés le long de +Y et de -Z.)
local function tri(parent: Instance, name: string, p0: Vector3, u: Vector3, v: Vector3, l1: number, l2: number, t: number, color: Color3, material: Enum.Material?, profile: string?): BasePart
	local Y = u
	local Z = -v
	local X = Y:Cross(Z)
	local center = p0 + u * (l1 / 2) + v * (l2 / 2)
	return TownKit.Wedge(parent, name, Vector3.new(t, l1, l2), CFrame.fromMatrix(center, X, Y, Z), color, material, profile)
end

-- Direction horizontale d'angle `a` dans le repère `F` (0 = avant, -Z local)
local function dirIn(F: CFrame, a: number): Vector3
	return F:VectorToWorldSpace(Vector3.new(math.sin(a), 0, -math.cos(a)))
end

-- Toit en pyramide à `n` pans (2 coins par pan) : bord du toit à l'apothème
-- `e` (hauteur y0 dans F), sommet à la hauteur y1 ; couleurs alternées
local function pyramid(parent: Instance, name: string, F: CFrame, n: number, e: number, y0: number, y1: number, t: number, colors: { Color3 }, material: Enum.Material, profile: string?)
	local apex = (F * CFrame.new(0, y1, 0)).Position
	local half = e * math.tan(math.pi / n)
	for k = 0, n - 1 do
		local nrm = dirIn(F, k / n * math.pi * 2)
		local side = Vector3.new(0, 1, 0):Cross(nrm).Unit
		local M = (F * CFrame.new(0, y0, 0)).Position + nrm * e
		local w = apex - M
		local len = w.Magnitude
		local color = colors[k % #colors + 1]
		tri(parent, name, M, w.Unit, side, len, half, t, color, material, profile)
		tri(parent, name, M, w.Unit, -side, len, half, t, color, material, profile)
	end
end

----------------------------------------------------------------------
-- Pavage
----------------------------------------------------------------------

local function paving(folder: Instance, O: Vector3)
	local model = TownKit.Model(folder, "Paving")
	local base = O + Vector3.new(0, WALK_Y, 0)
	TownKit.Disc(model, "Plaza", base, R, 1.3, C.Paving, M.Cobblestone, "solid")
	TownKit.Disc(model, "RingRose", base + Vector3.new(0, 0.03, 0), R - 4, 0.4, C.PavingRose, M.Cobblestone, "deco")
	TownKit.Disc(model, "RingInner", base + Vector3.new(0, 0.06, 0), R - 5.5, 0.4, C.Paving, M.Cobblestone, "deco")
	-- (v9.7) ROSE DES VENTS en mosaïque autour de la fontaine : 8 pointes
	-- (4 longues vers l'avenue, les rues et la mairie, 4 courtes vers le
	-- manège / le kiosque), chacune en deux demi-pointes claire / foncée
	-- (effet de relief) ; le cœur est caché sous le parvis de la fontaine.
	-- Hauteurs des dessus : pavage 0,06 < rose 0,09 < anneau 0,12 < parvis
	-- 0,15 (jamais deux faces à moins de 0,03).
	local up = Vector3.new(0, 1, 0)
	local center = base + Vector3.new(0, 0.09 - 0.05, 0)
	local light = { Color3.fromRGB(246, 238, 250), Color3.fromRGB(252, 236, 238) }
	local dark = { Color3.fromRGB(176, 158, 216), Color3.fromRGB(222, 150, 170) }
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local side = up:Cross(d).Unit
		local long = k % 2 == 0
		local len, half = long and 45 or 31, long and 7.5 or 5.5
		tri(model, "Compass", center, d, side, len, half, 0.1, light[k % 2 + 1], M.Slate, "deco")
		tri(model, "Compass", center, d, -side, len, half, 0.1, dark[k % 2 + 1], M.Slate, "deco")
	end
	TownKit.Disc(model, "FountainRing", base + Vector3.new(0, 0.12, 0), 21.5, 0.4, C.PavingLilac, M.Cobblestone, "deco")
	TownKit.Disc(model, "FountainApron", base + Vector3.new(0, 0.15, 0), 20, 0.4, C.Stone, M.Slate, "deco")
end

-- Pastille de pierre (sous le manège / le kiosque) : dessus à +0,14
local function pad(folder: Instance, center: Vector3, radius: number)
	TownKit.Disc(folder, "Pad", center + Vector3.new(0, 0.14, 0), radius, 0.4, Color3.fromRGB(232, 220, 226), M.Slate, "deco")
end

----------------------------------------------------------------------
-- Fontaine + cerveau mascotte
----------------------------------------------------------------------

-- (v9.7) La mascotte refaite : un cerveau dodu et kawaii, debout sur la
-- vasque haute, bras levés ("youpi !"). `cf` = centre du cerveau, visage
-- vers -Z local. Deux lobes (2 boules chacun : un peu plus long que haut),
-- 18 circonvolutions en relief, 12 sillons, sillon central, grands yeux
-- brillants, joues, bouche ouverte + langue, bras, mains, jambes, pieds.
-- 53 pièces.
local BRAIN_FEET = 2.625 -- (studs) du centre du cerveau au dessous des pieds
local function brain(model: Instance, cf: CFrame)
	local pink = Color3.fromRGB(255, 152, 198)
	local pinkDeep = Color3.fromRGB(240, 116, 172)
	local fold = Color3.fromRGB(214, 88, 148)
	local R0 = 1.8 -- rayon des boules des lobes
	local function at(x: number, y: number, z: number): Vector3
		return (cf * CFrame.new(x, y, z)).Position
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local lobe = TownKit.Ball(model, "Lobe", at(sx * 1.05, 0, sz * 0.55), R0 * 2, pink, M.SmoothPlastic, "decoS")
			lobe.Reflectance = 0.04
		end
		-- circonvolutions : bosses posées sur la surface des lobes (depuis
		-- la boule avant (-) ou arrière (+)), jamais sur le visage
		local bumps = {
			{ -1, 0.25, 0.95, -0.3 },
			{ 1, 0.3, 0.95, 0.35 },
			{ -1, 0.8, 0.55, -0.25 },
			{ 1, 0.85, 0.5, 0.45 },
			{ 1, 0.2, 0.7, 0.7 },
			{ 1, 0.95, 0, 0.3 },
			{ 1, 0.5, 0.35, 0.8 },
			{ -1, 0.6, 0.8, 0.15 },
			{ 1, 0.65, 0.75, -0.1 },
		}
		for i, b in ipairs(bumps) do
			local c = Vector3.new(sx * 1.05, 0, b[1] * 0.55)
			local d = Vector3.new(sx * b[2], b[3], b[4]).Unit
			local p = c + d * (R0 - 0.35)
			TownKit.Ball(model, "Fold", at(p.X, p.Y, p.Z), i % 3 == 0 and 1.3 or 1.5, i % 2 == 0 and pinkDeep or pink, M.SmoothPlastic, "deco")
		end
		-- œil (noir) + 2 reflets (du même côté pour les deux yeux)
		TownKit.Ball(model, "Eye", at(sx * 0.95, 0, -2.1), 0.95, Color3.fromRGB(58, 34, 64), M.SmoothPlastic, "deco")
		TownKit.Ball(model, "Shine", at(sx * 0.95 + 0.17, 0.2, -2.45), 0.34, C.White, M.SmoothPlastic, "deco")
		TownKit.Ball(model, "Shine2", at(sx * 0.95 - 0.15, -0.16, -2.5), 0.16, C.White, M.SmoothPlastic, "deco")
		-- joue : pastille posée sur la courbe du lobe avant
		local lc = Vector3.new(sx * 1.05, 0, -0.55)
		local bd = Vector3.new(sx * 0.55, -0.35, -0.76).Unit
		local bp = at(lc.X + bd.X * (R0 + 0.03), lc.Y + bd.Y * (R0 + 0.03), lc.Z + bd.Z * (R0 + 0.03))
		local bw = cf:VectorToWorldSpace(bd)
		local blush = part(model, "Blush", Vector3.new(0.1, 0.8, 0.8), CFrame.lookAt(bp, bp + bw) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 112, 150), M.SmoothPlastic, "deco")
		;(blush :: Part).Shape = Enum.PartType.Cylinder
		-- bras levés + mains, jambes + pieds
		TownKit.Rod(model, "Arm", at(sx * 2.55, -0.5, -0.2), at(sx * 3.5, 0.9, -0.55), 0.5, pink, M.SmoothPlastic, "deco")
		TownKit.Ball(model, "Hand", at(sx * 3.6, 1.05, -0.6), 0.75, pink, M.SmoothPlastic, "deco")
		TownKit.Rod(model, "Leg", at(sx * 0.75, -1.3, -0.2), at(sx * 0.8, -2.2, -0.35), 0.55, pinkDeep, M.SmoothPlastic, "deco")
		TownKit.Ball(model, "Foot", at(sx * 0.82, -2.2, -0.45), 0.85, pinkDeep, M.SmoothPlastic, "deco")
	end
	-- sillons (petites tiges foncées posées sur la surface : on lit enfin
	-- un CERVEAU et pas deux boules) + sillon entre les deux hémisphères
	local grooves = {
		{ -1, { 0.15, 1, -0.35 }, { 0.7, 0.7, -0.2 } },
		{ -1, { 0.2, 0.62, -0.75 }, { 0.75, 0.45, -0.55 } },
		{ -1, { 0.9, 0.35, -0.25 }, { 0.95, -0.1, -0.3 } },
		{ 1, { 0.15, 1, 0.3 }, { 0.75, 0.65, 0.25 } },
		{ 1, { 0.4, 0.6, 0.7 }, { 0.85, 0.2, 0.5 } },
		{ 1, { 0.2, 0.3, 0.95 }, { 0.6, -0.2, 0.8 } },
	}
	for _, sx in ipairs({ -1, 1 }) do
		for _, gr in ipairs(grooves) do
			local c = Vector3.new(sx * 1.05, 0, gr[1] * 0.55)
			local a = c + Vector3.new(sx * gr[2][1], gr[2][2], gr[2][3]).Unit * (R0 + 0.05)
			local b = c + Vector3.new(sx * gr[3][1], gr[3][2], gr[3][3]).Unit * (R0 + 0.05)
			TownKit.Rod(model, "Groove", at(a.X, a.Y, a.Z), at(b.X, b.Y, b.Z), 0.2, fold, M.SmoothPlastic, "deco")
		end
	end
	part(model, "Fissure", Vector3.new(0.22, 0.3, 3.2), cf * CFrame.new(0, 1.3, 0.3), fold, M.SmoothPlastic, "deco")
	-- bouche ouverte + langue
	TownKit.Ball(model, "Mouth", at(0, -0.7, -1.85), 0.6, Color3.fromRGB(120, 36, 70), M.SmoothPlastic, "deco")
	TownKit.Ball(model, "Tongue", at(0, -0.86, -2.02), 0.34, Color3.fromRGB(255, 108, 132), M.SmoothPlastic, "deco")
end

local function fountain(folder: Instance, O: Vector3): BasePart
	local model = TownKit.Model(folder, "Fountain")
	local base = O + Vector3.new(0, WALK_Y + 0.15, 0)
	local marble = Color3.fromRGB(250, 244, 240)
	local rose = Color3.fromRGB(232, 178, 188)
	local stone = Color3.fromRGB(206, 196, 192)
	local bronze = Color3.fromRGB(196, 150, 92)
	local basinR = 13.6
	local function y(h: number): Vector3
		return base + Vector3.new(0, h, 0)
	end
	-- (v9.7) Hauteurs (au-dessus du parvis) : marche 0,5 ; fond 0,8 ; eau
	-- 2,5 ; margelle 2,8 + couronnement 3,2 ; vasque basse 7,0 (eau 7,1) ;
	-- vasque haute 10,9 (eau 11,0) ; tambour 12,05 ; cerveau au-dessus.
	-- marche de pierre tout autour
	TownKit.Disc(model, "Step", y(0.5), 15.4, 0.5, stone, M.Slate, "solid")
	-- margelle à 12 pans + couronnement rose (on peut s'y asseoir / grimper)
	local n = 12
	local w = 2 * basinR * math.tan(math.pi / n)
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local p = base + d * basinR + Vector3.new(0, 1.65, 0)
		local wall = CFrame.lookAt(p, p + d)
		part(model, "Rim", Vector3.new(w + 0.5, 2.3, 1.4), wall, marble, M.Marble, "solid")
		part(model, "RimCap", Vector3.new(w + 0.9, 0.4, 2.1), wall * CFrame.new(0, 1.35, -0.1), rose, M.Marble, "decoS")
	end
	-- fond du bassin, eau transparente, ronds dans l'eau
	TownKit.Disc(model, "PoolFloor", y(0.8), 13.1, 0.3, C.WaterDeep, M.Slate, "solid")
	local water = TownKit.Disc(model, "Water", y(2.5), 13, 0.4, C.Water, M.Glass, "deco")
	water.Transparency = 0.35
	water.Reflectance = 0.1
	for k = 0, 3 do
		local a = (k + 0.5) / 4 * math.pi * 2
		local ripple = TownKit.Disc(model, "Ripple", y(2.54) + Vector3.new(math.sin(a) * 6.9, 0, math.cos(a) * 6.9), 1.1, 0.06, Color3.fromRGB(236, 248, 255), M.SmoothPlastic, "deco")
		ripple.Transparency = 0.45
	end
	-- pied central, vasque basse festonnée + rideau d'eau
	TownKit.Column(model, "PedestalFoot", y(0.8), 0.9, 5.4, marble, M.Marble, "solid")
	TownKit.Column(model, "Pedestal", y(1.7), 3.9, 3.4, marble, M.Marble, "solid")
	TownKit.Column(model, "PedestalRing", y(5.6), 0.4, 4, rose, M.Marble, "deco")
	TownKit.Column(model, "BowlFoot", y(6), 0.5, 5.4, marble, M.Marble, "deco")
	local bowl = TownKit.Disc(model, "Bowl", y(7), 6.2, 0.5, marble, M.Marble, "decoS")
	local bowlWater = TownKit.Disc(model, "BowlWater", y(7.1), 5.7, 0.08, C.Water, M.Glass, "deco")
	bowlWater.Transparency = 0.25
	for k = 0, 13 do
		local a = k / 14 * math.pi * 2
		TownKit.Ball(model, "Scallop", y(7.05) + Vector3.new(math.sin(a) * 5.95, 0, math.cos(a) * 5.95), 1, rose, M.Marble, "deco")
	end
	local curtain = TownKit.Column(model, "Curtain", y(2.5), 4.35, 12.6, Color3.fromRGB(200, 236, 255), M.Glass, "deco")
	curtain.Transparency = 0.8
	-- balustre, vasque haute festonnée + son rideau
	TownKit.Column(model, "Shaft", y(6.9), 2.9, 1.5, marble, M.Marble, "deco")
	TownKit.Ball(model, "Knob", y(8.4), 2.2, marble, M.Marble, "deco")
	TownKit.Column(model, "UpperFoot", y(9.8), 0.5, 3, marble, M.Marble, "deco")
	TownKit.Disc(model, "UpperBowl", y(10.9), 3.3, 0.6, marble, M.Marble, "deco")
	local upperWater = TownKit.Disc(model, "UpperWater", y(11), 2.9, 0.06, C.Water, M.Glass, "deco")
	upperWater.Transparency = 0.25
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		TownKit.Ball(model, "Scallop", y(10.95) + Vector3.new(math.sin(a) * 3.1, 0, math.cos(a) * 3.1), 0.7, rose, M.Marble, "deco")
	end
	local curtain2 = TownKit.Column(model, "Curtain", y(7.1), 3.65, 6.7, Color3.fromRGB(200, 236, 255), M.Glass, "deco")
	curtain2.Transparency = 0.8
	-- tambour doré, puis le cerveau mascotte (regarde l'entrée : +Z)
	TownKit.Column(model, "Drum", y(10.8), 1, 1.8, marble, M.Marble, "deco")
	TownKit.Column(model, "DrumTop", y(11.8), 0.25, 2.2, C.Yellow, M.Metal, "deco")
	local brainP = y(12.05 + BRAIN_FEET)
	brain(model, CFrame.lookAt(brainP, brainP + Vector3.new(0, 0, 10)))
	-- rideau d'eau de la vasque basse + jet du cerveau + 8 jets en arc
	emitter(bowl, {
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		EmissionDirection = Enum.NormalId.Top,
		Rate = 40,
		Speed = NumberRange.new(1, 2),
		Lifetime = NumberRange.new(0.9, 1.1),
		SpreadAngle = Vector2.new(8, 8),
	})
	-- (le cerveau crache un jet doux par le sommet du crâne)
	local nozzle = part(model, "Nozzle", Vector3.new(0.6, 0.6, 0.6), CFrame.new(brainP + Vector3.new(0, 2.1, 0)), C.White, M.SmoothPlastic, "deco")
	nozzle.Transparency = 1
	emitter(nozzle, {
		EmissionDirection = Enum.NormalId.Top,
		Rate = 26,
		Speed = NumberRange.new(10, 12),
		Lifetime = NumberRange.new(1.2, 1.4),
		SpreadAngle = Vector2.new(8, 8),
	})
	emitter(upperWater, {
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		EmissionDirection = Enum.NormalId.Top,
		Rate = 18,
		Speed = NumberRange.new(0.8, 1.4),
		Lifetime = NumberRange.new(0.7, 0.9),
		SpreadAngle = Vector2.new(8, 8),
	})
	-- 8 buses de bronze sur la margelle : jets en arc vers le centre
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = y(2.62) + Vector3.new(math.sin(a) * 12.3, 0, math.cos(a) * 12.3)
		local jet = part(model, "Jet", Vector3.new(0.55, 0.3, 0.55), CFrame.lookAt(p, Vector3.new(base.X, p.Y, base.Z)) * CFrame.Angles(math.rad(-40), 0, 0), bronze, M.Metal, "deco")
		emitter(jet, {
			EmissionDirection = Enum.NormalId.Top,
			Rate = 12,
			Speed = NumberRange.new(9, 10.5),
			Lifetime = NumberRange.new(0.95, 1.1),
			SpreadAngle = Vector2.new(3, 3),
		})
	end
	-- lumière sous l'eau (1 vraie lumière, douce, la nuit seulement)
	TownKit.Light(water, Color3.fromRGB(150, 220, 255), 18, 0.8)
	-- pupitre de pierre + plaque de bronze inclinée (face à l'avenue)
	local lp = y(0) + Vector3.new(0, 0, 17.2)
	local desk = CFrame.lookAt(lp, lp + Vector3.new(0, 0, 1))
	part(model, "Lectern", Vector3.new(1.3, 2.2, 0.8), desk * CFrame.new(0, 1.1, 0), stone, M.Slate, "prop")
	local plaque = part(model, "Plaque", Vector3.new(3.4, 1.5, 0.2), desk * CFrame.new(0, 2.75, 0.05) * CFrame.Angles(math.rad(35), 0, 0), bronze, M.Metal, "deco")
	local _, body = TownKit.Surface(plaque, Enum.NormalId.Front, 60, nil, 90, 0.4)
	TownKit.Label(body, "Text", "🧠 The Dopamine Fountain", 0.05, 0.12, 0.9, 0.76, Color3.fromRGB(84, 52, 36), Enum.Font.FredokaOne, true)
	return water
end

----------------------------------------------------------------------
-- Kiosque, manège, ballons, guirlandes
----------------------------------------------------------------------

-- (v9.7) Kiosque à musique OCTOGONAL. `F` au sol, au centre ; l'avant
-- (-Z) regarde le centre de la place : marches et entrée devant.
--   socle plein (4 bandes croisées = octogone), plancher en bois, 2
--   marches, 8 colonnes aux angles, garde-corps (main courante solide +
--   lisse basse + 3 balustres par côté), frise, plafond, toit en pyramide
--   à 8 pans bicolores (tuiles), épi de faîtage, 3 pupitres + grosse caisse.
--   Les guirlandes d'ampoules sous la frise : client (TownPlazaFx).
local BAND_A = 7.4 -- apothème du socle
local BAND_FASCIA = 8.3 -- apothème de la face extérieure de la frise
local BAND_FASCIA_Y = 10.2 -- bas de la frise
local function bandstand(folder: Instance, F: CFrame)
	local model = TownKit.Model(folder, "Bandstand")
	local cream = Color3.fromRGB(246, 238, 228)
	local white = Color3.fromRGB(252, 250, 246)
	local a = BAND_A
	local s = 2 * a * math.tan(math.pi / 8)
	-- socle (même couleur, lisse : les bandes qui se recouvrent ne scintillent pas)
	for j = 0, 3 do
		part(model, "Plinth", Vector3.new(s, 2, 2 * a), F * CFrame.Angles(0, j * math.pi / 4, 0) * CFrame.new(0, 1, 0), cream, M.SmoothPlastic, "solid")
	end
	TownKit.Disc(model, "Deck", (F * CFrame.new(0, 2.2, 0)).Position, a - 0.35, 0.25, C.WoodLight, M.WoodPlanks, "solid")
	part(model, "Step", Vector3.new(5, 1.47, 1.3), F * CFrame.new(0, 0.735, -(a + 0.65)), cream, M.SmoothPlastic, "solid")
	part(model, "Step", Vector3.new(5, 0.73, 1.3), F * CFrame.new(0, 0.365, -(a + 1.95)), cream, M.SmoothPlastic, "solid")
	-- colonnes aux 8 angles (sur le socle, autour du plancher)
	local vr = a / math.cos(math.pi / 8) - 0.55
	local posts = {}
	for k = 0, 7 do
		local p = F.Position + dirIn(F, (k + 0.5) / 8 * math.pi * 2) * vr
		posts[k] = p
		TownKit.Column(model, "Post", p + Vector3.new(0, 2, 0), 8.3, 0.5, white, M.SmoothPlastic, "prop")
	end
	-- garde-corps sur 7 côtés (le côté 0 = l'entrée, devant les marches)
	for k = 1, 7 do
		local p0, p1 = posts[k - 1], posts[k]
		TownKit.Beam(model, "Rail", p0 + Vector3.new(0, 4.7, 0), p1 + Vector3.new(0, 4.7, 0), 0.22, 0.2, white, M.SmoothPlastic, "prop")
		TownKit.Beam(model, "RailLow", p0 + Vector3.new(0, 2.55, 0), p1 + Vector3.new(0, 2.55, 0), 0.18, 0.16, white, M.SmoothPlastic, "deco")
		for q = 1, 3 do
			local p = p0:Lerp(p1, q / 4)
			part(model, "Baluster", Vector3.new(0.16, 2.05, 0.16), CFrame.new(p + Vector3.new(0, 3.625, 0)), white, M.SmoothPlastic, "deco")
		end
	end
	-- frise + plafond
	local fl = 2 * BAND_FASCIA * math.tan(math.pi / 8) + 0.1
	for k = 0, 7 do
		local d = dirIn(F, k / 8 * math.pi * 2)
		local p = F.Position + d * (BAND_FASCIA - 0.1) + Vector3.new(0, BAND_FASCIA_Y + 0.4, 0)
		part(model, "Fascia", Vector3.new(fl, 0.8, 0.2), CFrame.lookAt(p, p + d), white, M.SmoothPlastic, "decoS")
	end
	local ceiling = TownKit.Disc(model, "Ceiling", (F * CFrame.new(0, BAND_FASCIA_Y + 0.2, 0)).Position, BAND_FASCIA - 0.2, 0.2, white, M.SmoothPlastic, "decoS")
	-- toit : pyramide à 8 pans (lilas / crème), débord de 0,35
	pyramid(model, "Roof", F, 8, BAND_FASCIA + 0.35, BAND_FASCIA_Y + 0.8, 15.4, 0.3, { Color3.fromRGB(176, 136, 224), Color3.fromRGB(250, 230, 238) }, M.RoofShingles, "decoS")
	local top = F * CFrame.new(0, 15.4, 0)
	TownKit.Column(model, "FinialBase", (top * CFrame.new(0, -0.5, 0)).Position, 0.9, 0.9, white, M.SmoothPlastic, "deco")
	TownKit.Ball(model, "Finial", (top * CFrame.new(0, 0.75, 0)).Position, 1.1, C.Yellow, M.Metal, "deco")
	TownKit.Rod(model, "Spike", (top * CFrame.new(0, 1.2, 0)).Position, (top * CFrame.new(0, 2.6, 0)).Position, 0.16, C.Yellow, M.Metal, "deco")
	-- 3 pupitres (tournés vers les musiciens) + grosse caisse
	for _, x in ipairs({ -2.2, 0, 2.2 }) do
		local z = -0.8 - math.abs(x) * 0.25
		TownKit.Rod(model, "StandPole", (F * CFrame.new(x, 2.2, z)).Position, (F * CFrame.new(x, 4.35, z)).Position, 0.1, C.Metal, M.Metal, "deco")
		part(model, "StandDesk", Vector3.new(1.1, 0.8, 0.06), F * CFrame.new(x, 4.6, z) * CFrame.Angles(math.rad(-25), 0, 0), C.Metal, M.Metal, "deco")
	end
	local drumCF = F * CFrame.new(2.9, 3.3, 2.2) * CFrame.Angles(0, math.rad(90), 0)
	local shell = part(model, "BassDrum", Vector3.new(0.9, 2.2, 2.2), drumCF, Color3.fromRGB(226, 84, 118), M.SmoothPlastic, "deco")
	;(shell :: Part).Shape = Enum.PartType.Cylinder
	local head = part(model, "DrumHead", Vector3.new(1, 2, 2), drumCF, C.Cream, M.SmoothPlastic, "deco")
	;(head :: Part).Shape = Enum.PartType.Cylinder
	-- lumière douce sous le plafond (la nuit)
	TownKit.Light(ceiling, Color3.fromRGB(255, 214, 170), 16, 0.8)
end

-- (v9.7) MANÈGE : ici seulement ce qui NE tourne PAS (socle à deux
-- marches, guérite à tickets, lumière douce). Le plateau, les chevaux, les
-- carrosses et l'auvent sont construits et animés par chaque client
-- (TownPlazaFx) à partir de l'attribut "FxCarouselCF" du dossier Plaza
-- (centre du DESSUS du socle, avant vers le centre de la place).
local CAROUSEL_TOP = 1.2 -- (studs) dessus du socle (le plateau tournant pose dessus)
local function carousel(folder: Instance, F: CFrame): CFrame
	local model = TownKit.Model(folder, "Carousel")
	local center = F.Position
	TownKit.Column(model, "Plinth", center, 0.6, 20.4, Color3.fromRGB(196, 184, 214), M.Slate, "solid")
	TownKit.Column(model, "Platform", center + Vector3.new(0, 0.6, 0), CAROUSEL_TOP - 0.6, 18.6, C.PavingLilac, M.Marble, "solid")
	-- lumière douce au cœur de l'auvent (hôte invisible ; la nuit seulement)
	local anchor = part(model, "LightAnchor", Vector3.new(1, 1, 1), F * CFrame.new(0, CAROUSEL_TOP + 7.3, 0), C.White, M.SmoothPlastic, "deco")
	anchor.Transparency = 1
	TownKit.Light(anchor, Color3.fromRGB(255, 212, 170), 20, 0.9)
	-- guérite à tickets (devant, à droite en arrivant de la place)
	local booth = F * CFrame.new(-8.5, 0, -12) * CFrame.Angles(0, math.rad(20), 0)
	local pinkBooth = Color3.fromRGB(255, 176, 206)
	local boothPart = part(model, "Booth", Vector3.new(2.8, 3.2, 2.4), booth * CFrame.new(0, 1.6, 0), pinkBooth, M.WoodPlanks, "solid")
	part(model, "BoothWindow", Vector3.new(1.8, 1.1, 0.1), booth * CFrame.new(0, 2.25, -1.24), C.GlassDark, M.Glass, "deco").Transparency = 0.3
	part(model, "BoothShelf", Vector3.new(2.2, 0.14, 0.6), booth * CFrame.new(0, 1.62, -1.45), C.Cream, M.Wood, "deco")
	part(model, "BoothRoof", Vector3.new(3.4, 0.35, 3), booth * CFrame.new(0, 3.38, 0), C.Cream, M.SmoothPlastic, "deco")
	-- petit toit en pointe rayé (comme l'auvent du manège) + boule dorée
	pyramid(model, "BoothCap", booth * CFrame.new(0, 3.555, 0), 4, 1.45, 0, 1.7, 0.1, { Color3.fromRGB(255, 132, 180), C.Cream }, M.Fabric, "deco")
	TownKit.Ball(model, "BoothFinial", (booth * CFrame.new(0, 5.3, 0)).Position, 0.45, C.Yellow, M.Metal, "deco")
	local sign = part(model, "BoothSign", Vector3.new(2.6, 0.9, 0.12), booth * CFrame.new(0, 4.1, -1.62), C.Cream, M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(sign, Enum.NormalId.Front, 50, Color3.fromRGB(255, 244, 232), 120, 0.4)
	TownKit.Label(body, "Text", "🎠 Carousel", 0.04, 0.08, 0.92, 0.84, Color3.fromRGB(196, 64, 124), Enum.Font.FredokaOne, true)
	-- (v9.8, FAIR98) on MONTE sur le manège : 12 places (10 chevaux + 2
	-- carrosses, sièges ancrés qui suivent le plateau : TownFair / FairRides),
	-- invite "Monter" à la guérite ; le client (TownPlazaFx) les lisse
	local pcallOk, pcallErr = pcall(TownFair.AddPlazaCarousel, model, F * CFrame.new(0, CAROUSEL_TOP, 0), boothPart)
	if not pcallOk then
		warn("[TownPlaza] manège : " .. tostring(pcallErr))
	end
	return F * CFrame.new(0, CAROUSEL_TOP, 0)
end

-- (v9.7) Chariot du marchand de ballons : caisse en bois à bande rose,
-- 2 roues à moyeu, poignée, béquille, mât (les ballons, eux, flottent et
-- se balancent côté client, attachés au sommet du mât : attribut
-- "FxBalloonTie"), bouteille d'hélium, pancarte "🎈 Balloons".
-- `cf` au sol, avant (-Z) vers les clients. Renvoie le point d'attache.
local function balloonCart(folder: Instance, cf: CFrame): Vector3
	local model = TownKit.Model(folder, "BalloonCart")
	part(model, "Cart", Vector3.new(3.6, 2, 2.2), cf * CFrame.new(0, 1.9, 0), C.Cream, M.WoodPlanks, "solid")
	part(model, "Stripe", Vector3.new(3.7, 0.5, 2.3), cf * CFrame.new(0, 2.3, 0), C.Pink, M.SmoothPlastic, "deco")
	part(model, "Counter", Vector3.new(3.9, 0.2, 2.5), cf * CFrame.new(0, 3, 0), C.WoodLight, M.Wood, "deco")
	for _, x in ipairs({ -1.95, 1.95 }) do
		local w = part(model, "Wheel", Vector3.new(0.3, 2, 2), cf * CFrame.new(x, 1, 0.3), C.Metal, M.Rubber, "deco")
		;(w :: Part).Shape = Enum.PartType.Cylinder
		local hub = part(model, "Hub", Vector3.new(0.45, 0.5, 0.5), cf * CFrame.new(x, 1, 0.3), C.Yellow, M.Metal, "deco")
		;(hub :: Part).Shape = Enum.PartType.Cylinder
	end
	part(model, "Leg", Vector3.new(0.25, 0.9, 0.25), cf * CFrame.new(0, 0.45, -0.8), C.Metal, M.Metal, "deco")
	TownKit.Rod(model, "Handle", (cf * CFrame.new(-1.3, 3.1, 2)).Position, (cf * CFrame.new(1.3, 3.1, 2)).Position, 0.16, C.Metal, M.Metal, "deco")
	for _, x in ipairs({ -1.3, 1.3 }) do
		TownKit.Rod(model, "HandleArm", (cf * CFrame.new(x, 2.6, 1.05)).Position, (cf * CFrame.new(x, 3.1, 2)).Position, 0.14, C.Metal, M.Metal, "deco")
	end
	local tie = (cf * CFrame.new(0, 7.2, 0.4)).Position
	TownKit.Rod(model, "Mast", (cf * CFrame.new(0, 3.1, 0.4)).Position, tie, 0.2, C.Metal, M.Metal, "deco")
	TownKit.Ball(model, "MastKnob", tie, 0.4, C.Yellow, M.Metal, "deco")
	TownKit.Column(model, "Helium", (cf * CFrame.new(2.7, 0, -0.2)).Position, 1.8, 0.8, Color3.fromRGB(120, 196, 236), M.Metal, "prop")
	TownKit.Ball(model, "HeliumCap", (cf * CFrame.new(2.7, 1.85, -0.2)).Position, 0.5, C.MetalLight, M.Metal, "deco")
	local sign = part(model, "Sign", Vector3.new(3, 0.9, 0.12), cf * CFrame.new(0, 1.45, -1.19), C.White, M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(sign, Enum.NormalId.Front, 50, Color3.fromRGB(255, 244, 250), 100, 0.4)
	TownKit.Label(body, "Text", "🎈 Balloons", 0.04, 0.08, 0.92, 0.84, Color3.fromRGB(214, 70, 130), Enum.Font.FredokaOne, true)
	return tie
end

-- (v9.7) Auvent rayé (lames inclinées vers l'avant) : repère `cf` au bord
-- arrière, en haut ; `w` largeur, `depth` profondeur, n lames
local function awning(model: Instance, cf: CFrame, w: number, depth: number, n: number, a: Color3, b: Color3)
	local slope = CFrame.Angles(math.rad(-18), 0, 0)
	for i = 0, n - 1 do
		local x = -w / 2 + (i + 0.5) * w / n
		part(model, "Awning", Vector3.new(w / n, 0.14 + (i % 2) * 0.08, depth), cf * slope * CFrame.new(x, 0, -depth / 2), i % 2 == 0 and a or b, M.Fabric, "decoS")
	end
end

-- (v9.7) Stand de GLACES : comptoir menthe, vitrine réfrigérée (6 bacs de
-- parfums), auvent rayé sur 2 montants, cornet géant sur un mât, panneau.
-- `cf` au sol, avant (-Z) vers les clients.
local function iceCreamStall(folder: Instance, cf: CFrame)
	local model = TownKit.Model(folder, "IceCreamStall")
	local mint = Color3.fromRGB(150, 222, 200)
	part(model, "Counter", Vector3.new(5, 2.8, 2.4), cf * CFrame.new(0, 1.4, 0), mint, M.WoodPlanks, "solid")
	part(model, "Top", Vector3.new(5.4, 0.25, 2.8), cf * CFrame.new(0, 2.925, 0), C.White, M.Marble, "deco")
	local panel = part(model, "Panel", Vector3.new(4.2, 1.7, 0.1), cf * CFrame.new(0, 1.45, -1.25), Color3.fromRGB(255, 246, 236), M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(panel, Enum.NormalId.Front, 40, Color3.fromRGB(255, 246, 236), 100, 0.4)
	TownKit.Label(body, "Text", "🍦 Ice cream", 0.04, 0.12, 0.92, 0.76, Color3.fromRGB(64, 150, 128), Enum.Font.FredokaOne, true)
	-- vitrine (verre, un peu enfoncée dans le plateau) + 6 bacs de parfums
	local glass = part(model, "Case", Vector3.new(3.8, 0.95, 1.5), cf * CFrame.new(-0.4, 3.475, -0.3), Color3.fromRGB(214, 240, 250), M.Glass, "deco")
	glass.Transparency = 0.55
	local flavours = { Color3.fromRGB(255, 170, 196), Color3.fromRGB(170, 236, 200), Color3.fromRGB(150, 96, 70), Color3.fromRGB(255, 244, 214), Color3.fromRGB(255, 226, 120), Color3.fromRGB(176, 150, 240) }
	for i, color in ipairs(flavours) do
		local x = -1.6 + ((i - 1) % 3) * 0.8
		local z = i > 3 and 0 or -0.6
		TownKit.Column(model, "Tub", (cf * CFrame.new(x, 3.05, z)).Position, 0.55, 0.7, color, M.SmoothPlastic, "deco")
	end
	-- montants + auvent rayé rose / blanc
	for _, x in ipairs({ -2.5, 2.5 }) do
		part(model, "Post", Vector3.new(0.2, 3.6, 0.2), cf * CFrame.new(x, 4.85, 1.2), C.White, M.Metal, "deco")
	end
	awning(model, cf * CFrame.new(0, 6.65, 1.3), 5.6, 3.6, 6, Color3.fromRGB(255, 150, 190), C.White)
	-- cornet géant (mât à droite)
	local cone = cf * CFrame.new(2.9, 0, -0.9)
	TownKit.Column(model, "ConePole", cone.Position, 5.2, 0.2, C.White, M.Metal, "deco")
	TownKit.Column(model, "Cone3", (cone * CFrame.new(0, 5.2, 0)).Position, 0.5, 0.5, Color3.fromRGB(222, 168, 104), M.Wood, "deco")
	TownKit.Column(model, "Cone2", (cone * CFrame.new(0, 5.7, 0)).Position, 0.5, 0.9, Color3.fromRGB(226, 174, 110), M.Wood, "deco")
	TownKit.Column(model, "Cone1", (cone * CFrame.new(0, 6.2, 0)).Position, 0.5, 1.3, Color3.fromRGB(230, 180, 116), M.Wood, "deco")
	TownKit.Ball(model, "Scoop", (cone * CFrame.new(0, 7.05, 0)).Position, 1.5, Color3.fromRGB(255, 170, 200), M.SmoothPlastic, "deco")
	TownKit.Ball(model, "Scoop2", (cone * CFrame.new(0, 7.95, 0)).Position, 1.25, Color3.fromRGB(170, 236, 206), M.SmoothPlastic, "deco")
	TownKit.Ball(model, "Cherry", (cone * CFrame.new(0.1, 8.7, 0)).Position, 0.45, Color3.fromRGB(226, 40, 70), M.SmoothPlastic, "deco")
	-- (v9.8, FAIR98) on ACHÈTE ici : glaces et milkshakes (FoodService)
	TownFair.StallAnchor(model, cf * CFrame.new(0, 0, -2.6), "PlazaIce", { "IceCream", "Milkshake" }, "🍦 🥤 Snacks")
end

-- (v9.7) Stand de BARBE À PAPA : chariot rond rayé, machine (cuve + nuage
-- rose), parasol en pyramide à 8 pans rose / blanc, 4 barbes à papa sur
-- bâton plantées dans le plateau, panneau. `cf` au sol, avant (-Z).
local function candyStall(folder: Instance, cf: CFrame)
	local model = TownKit.Model(folder, "CandyStall")
	local p = cf.Position
	TownKit.Column(model, "Cart", p, 2.8, 3.6, Color3.fromRGB(255, 244, 250), M.WoodPlanks, "solid")
	TownKit.Column(model, "Band", p + Vector3.new(0, 1.9, 0), 0.5, 3.7, Color3.fromRGB(255, 140, 190), M.SmoothPlastic, "deco")
	TownKit.Disc(model, "Top", p + Vector3.new(0, 3, 0), 2.1, 0.2, C.White, M.Marble, "deco")
	TownKit.Column(model, "Machine", p + Vector3.new(0, 3, 0), 0.8, 2, C.MetalLight, M.Metal, "deco")
	TownKit.Ball(model, "Floss", p + Vector3.new(0, 3.85, 0), 1.7, Color3.fromRGB(255, 190, 222), M.SmoothPlastic, "deco")
	local floss = { Color3.fromRGB(255, 176, 214), Color3.fromRGB(170, 214, 255), Color3.fromRGB(214, 180, 255), Color3.fromRGB(255, 200, 226) }
	for i, color in ipairs(floss) do
		local a = (i - 0.5) / 4 * math.pi * 2
		local q = p + Vector3.new(math.sin(a) * 1.55, 3, math.cos(a) * 1.55)
		TownKit.Rod(model, "Stick", q, q + Vector3.new(0, 1.5, 0), 0.1, C.Cream, M.Wood, "deco")
		TownKit.Ball(model, "Candy", q + Vector3.new(0, 2, 0), 1.05, color, M.SmoothPlastic, "deco")
	end
	-- parasol (mât à l'arrière du chariot)
	local u = cf * CFrame.new(0, 0, 1.3)
	TownKit.Column(model, "UmbrellaPole", (u * CFrame.new(0, 3, 0)).Position, 4.2, 0.16, C.White, M.Metal, "deco")
	pyramid(model, "Umbrella", u, 8, 3.3, 6.6, 8, 0.12, { Color3.fromRGB(255, 150, 196), C.White }, M.Fabric, "decoS")
	TownKit.Ball(model, "UmbrellaTop", (u * CFrame.new(0, 8.05, 0)).Position, 0.45, C.Yellow, M.Metal, "deco")
	local sign = part(model, "Sign", Vector3.new(2.6, 0.8, 0.12), cf * CFrame.new(0, 1.2, -1.88), C.White, M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(sign, Enum.NormalId.Front, 50, Color3.fromRGB(255, 244, 250), 100, 0.4)
	TownKit.Label(body, "Text", "🍭 Candy floss", 0.04, 0.08, 0.92, 0.84, Color3.fromRGB(196, 64, 150), Enum.Font.FredokaOne, true)
	-- (v9.8, FAIR98) on ACHÈTE ici : barbe à papa et pommes d'amour (FoodService)
	TownFair.StallAnchor(model, cf * CFrame.new(0, 0, -2.9), "PlazaCandy", { "CandyFloss", "CandyApple" }, "🍭 🍎 Snacks")
end

-- (v9.7) Coin du MUSICIEN DE RUE (sans personnage : "je reviens dans 5
-- min") : tapis, tabouret, guitare posée, étui ouvert avec pièces, petit
-- ampli (muet !), pupitre, chevalet ardoise. `cf` au sol, avant (-Z) vers
-- le public.
local function busker(folder: Instance, cf: CFrame)
	local model = TownKit.Model(folder, "Busker")
	part(model, "Rug", Vector3.new(4.6, 0.06, 3.4), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(196, 72, 96), M.Fabric, "deco")
	TownKit.Column(model, "StoolLeg", (cf * CFrame.new(0.4, 0, 0.6)).Position, 1.7, 0.28, C.Metal, M.Metal, "prop")
	TownKit.Column(model, "StoolSeat", (cf * CFrame.new(0.4, 1.7, 0.6)).Position, 0.2, 1.3, C.Wood, M.Wood, "deco")
	-- guitare appuyée contre le tabouret
	local g = cf * CFrame.new(-1.5, 0.1, -0.3) * CFrame.Angles(math.rad(-10), math.rad(20), math.rad(-10))
	local wood = Color3.fromRGB(226, 160, 96)
	TownKit.Ball(model, "GuitarBody", (g * CFrame.new(0, 0.62, 0)).Position, 1.25, wood, M.Wood, "deco")
	TownKit.Ball(model, "GuitarBody2", (g * CFrame.new(0, 1.42, 0)).Position, 0.95, wood, M.Wood, "deco")
	part(model, "GuitarNeck", Vector3.new(0.22, 1.9, 0.14), g * CFrame.new(0, 2.6, 0), Color3.fromRGB(110, 70, 46), M.Wood, "deco")
	part(model, "GuitarHead", Vector3.new(0.34, 0.5, 0.16), g * CFrame.new(0, 3.75, 0), Color3.fromRGB(70, 44, 32), M.Wood, "deco")
	-- étui ouvert (doublure rouge + pièces), couvercle relevé
	local case = cf * CFrame.new(-0.3, 0, -2.3)
	part(model, "Case", Vector3.new(3.2, 0.3, 1.3), case * CFrame.new(0, 0.28, 0), Color3.fromRGB(46, 40, 52), M.Leather, "prop")
	part(model, "Lining", Vector3.new(3, 0.06, 1.1), case * CFrame.new(0, 0.44, 0), Color3.fromRGB(176, 30, 60), M.Fabric, "deco")
	part(model, "CaseLid", Vector3.new(3.2, 0.9, 0.12), case * CFrame.new(0, 0.75, 0.72) * CFrame.Angles(math.rad(12), 0, 0), Color3.fromRGB(46, 40, 52), M.Leather, "deco")
	for i, x in ipairs({ -0.6, 0.2, 0.7 }) do
		TownKit.Disc(model, "Coin", (case * CFrame.new(x, 0.5, (i - 2) * 0.25)).Position, 0.2, 0.05, C.Yellow, M.Metal, "deco")
	end
	-- ampli (sans son) + pupitre
	part(model, "Amp", Vector3.new(1.4, 1.5, 0.9), cf * CFrame.new(1.8, 0.75, 0.9), Color3.fromRGB(52, 48, 58), M.Leather, "prop")
	part(model, "AmpGrille", Vector3.new(1.1, 0.9, 0.1), cf * CFrame.new(1.8, 0.85, 0.42), Color3.fromRGB(96, 92, 104), M.Fabric, "deco")
	TownKit.Rod(model, "StandPole", (cf * CFrame.new(0.4, 0, -0.7)).Position, (cf * CFrame.new(0.4, 2.9, -0.7)).Position, 0.1, C.Metal, M.Metal, "deco")
	part(model, "StandDesk", Vector3.new(1.1, 0.8, 0.06), cf * CFrame.new(0.4, 3.15, -0.7) * CFrame.Angles(math.rad(-25), 0, 0), C.Metal, M.Metal, "deco")
	-- chevalet ardoise "je reviens"
	local easel = cf * CFrame.new(2.9, 0, -1.2) * CFrame.Angles(0, math.rad(-20), 0)
	local board = part(model, "Slate", Vector3.new(1.6, 2.2, 0.1), easel * CFrame.new(0, 1.05, 0) * CFrame.Angles(math.rad(12), 0, 0), Color3.fromRGB(58, 62, 66), M.Slate, "deco")
	part(model, "SlateBack", Vector3.new(1.4, 2.1, 0.08), easel * CFrame.new(0, 1.0, 0.45) * CFrame.Angles(math.rad(-14), 0, 0), C.Wood, M.Wood, "deco")
	local _, body = TownKit.Surface(board, Enum.NormalId.Front, 50, nil, 60, 0.6)
	TownKit.Label(body, "Text", "Back in 5 min ♪", 0.08, 0.1, 0.84, 0.6, Color3.fromRGB(250, 246, 236), Enum.Font.FredokaOne, true)
	TownKit.Label(body, "Heart", "♥", 0.3, 0.68, 0.4, 0.26, Color3.fromRGB(255, 150, 190), Enum.Font.FredokaOne, false)
end

-- (v9.7) DESSINS À LA CRAIE (une seule pièce plate chacun, SurfaceGui sur
-- le dessus, pièce invisible) : une marelle 1…8 + "Sky", et un dessin
-- (soleil, cœurs, fleurs, "Smile!"). Dessus à +0,13 au-dessus de la place.
local CHALK_Y = 0.13
local function chalkBoard(folder: Instance, name: string, cf: CFrame, size: Vector2): Frame
	local p = part(folder, name, Vector3.new(size.X, 0.04, size.Y), cf * CFrame.new(0, CHALK_Y - 0.02, 0), C.White, M.SmoothPlastic, "deco")
	p.Transparency = 1
	local _, body = TownKit.Surface(p, Enum.NormalId.Top, 40, nil, 110, 1)
	return body
end

local function chalkText(parent: Instance, text: string, x: number, y: number, w: number, h: number, color: Color3, localize: boolean?)
	local l = TownKit.Label(parent, "Chalk", text, x, y, w, h, color, Enum.Font.FredokaOne, localize)
	l.TextTransparency = 0.12
	return l
end

local function hopscotch(folder: Instance, cf: CFrame)
	local body = chalkBoard(folder, "Hopscotch", cf, Vector2.new(4.2, 11))
	local chalk = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 196, 222), Color3.fromRGB(196, 226, 255), Color3.fromRGB(255, 236, 160) }
	-- cases (du bas vers le haut) : 1, 2, 3, 4-5, 6, 7-8, puis "Sky"
	local rows = { { "1" }, { "2" }, { "3" }, { "4", "5" }, { "6" }, { "7", "8" } }
	local rowH = 1 / 7.4
	for r, row in ipairs(rows) do
		for c, label in ipairs(row) do
			local w = #row == 1 and 0.46 or 0.44
			local x = #row == 1 and 0.27 or (c == 1 and 0.05 or 0.51)
			local box = Instance.new("Frame")
			box.Name = "Box"
			box.BackgroundTransparency = 1
			box.Position = UDim2.fromScale(x, 1 - r * rowH - 0.02)
			box.Size = UDim2.fromScale(w, rowH - 0.012)
			box.Parent = body
			TownKit.Stroke(box, chalk[(r + c) % #chalk + 1], 5)
			chalkText(box, label, 0.1, 0.1, 0.8, 0.8, chalk[(r + c + 1) % #chalk + 1])
		end
	end
	chalkText(body, "Sky", 0.12, 0.02, 0.76, 0.1, Color3.fromRGB(196, 226, 255), true)
end

local function chalkArt(folder: Instance, cf: CFrame)
	local body = chalkBoard(folder, "ChalkArt", cf, Vector2.new(9, 7))
	chalkText(body, "☀", 0.02, 0.02, 0.3, 0.42, Color3.fromRGB(255, 226, 120))
	chalkText(body, "♥", 0.66, 0.05, 0.3, 0.36, Color3.fromRGB(255, 150, 190))
	chalkText(body, "✿", 0.34, 0.08, 0.3, 0.3, Color3.fromRGB(214, 180, 255))
	chalkText(body, "Smile!", 0.06, 0.48, 0.88, 0.3, Color3.fromRGB(255, 255, 255), true)
	chalkText(body, "♥ ✿ ♥", 0.2, 0.78, 0.6, 0.18, Color3.fromRGB(170, 236, 206))
end

-- (v9.7) Lampadaire de la place : socle, fût, bague, traverse et DEUX
-- lanternes (verre dépoli TownKit.Glow : Neon la nuit seulement), épi.
-- `light` : une vraie lumière douce (TownKit.Light, la nuit). Le fil des
-- guirlandes (client) part du sommet : PLAZA_LAMP_TOP.
local PLAZA_LAMP_TOP = 11.5
local function plazaLamp(folder: Instance, base: Vector3, along: Vector3, light: boolean)
	local model = TownKit.Model(folder, "Lamp")
	local iron = Color3.fromRGB(56, 52, 70)
	local rot = CFrame.lookAt(base, base + along)
	TownKit.Column(model, "Foot", base, 1, 1.5, iron, M.Metal, "prop")
	TownKit.Column(model, "Pole", base + Vector3.new(0, 1, 0), 10.2, 0.45, iron, M.Metal, "prop")
	TownKit.Ball(model, "Knob", base + Vector3.new(0, 4.2, 0), 0.8, iron, M.Metal, "deco")
	part(model, "Bar", Vector3.new(0.2, 0.22, 4.2), rot * CFrame.new(0, 10.9, 0), iron, M.Metal, "deco")
	TownKit.Ball(model, "Finial", base + Vector3.new(0, PLAZA_LAMP_TOP, 0), 0.6, C.Yellow, M.Metal, "deco")
	local first: BasePart? = nil
	for _, z in ipairs({ -1.9, 1.9 }) do
		local lcf = rot * CFrame.new(0, 10.5, z)
		part(model, "Hood", Vector3.new(0.95, 0.3, 0.95), lcf * CFrame.new(0, 0.35, 0), iron, M.Metal, "deco")
		local glow = TownKit.Glow(part(model, "Glow", Vector3.new(0.7, 0.9, 0.7), lcf * CFrame.new(0, -0.25, 0), C.Glow, M.SmoothPlastic, "deco"))
		first = first or glow
	end
	if light and first then
		TownKit.Light(first, C.Glow, 18, 0.8)
	end
end

----------------------------------------------------------------------
-- Couronne de boutiques
----------------------------------------------------------------------

-- Intervalles d'angles occupés (radians, 0..2π) -> intervalles libres
local function freeArcs(blocked: { { number } }): { { number } }
	local twoPi = math.pi * 2
	local list = {}
	for _, b in ipairs(blocked) do
		local a0, a1 = b[1] % twoPi, b[2] % twoPi
		if a0 <= a1 then
			table.insert(list, { a0, a1 })
		else
			table.insert(list, { a0, twoPi })
			table.insert(list, { 0, a1 })
		end
	end
	table.sort(list, function(x, y)
		return x[1] < y[1]
	end)
	local free = {}
	local cursor = 0
	for _, b in ipairs(list) do
		if b[1] > cursor then
			table.insert(free, { cursor, b[1] })
		end
		cursor = math.max(cursor, b[2])
	end
	if cursor < twoPi then
		table.insert(free, { cursor, twoPi })
	end
	-- (recolle l'arc qui passe par 0)
	if #free >= 2 and free[1][1] == 0 and free[#free][2] == twoPi then
		local last = table.remove(free) :: { number }
		free[1] = { last[1] - twoPi, free[1][2] }
	end
	return free
end

-- (v9.6) Couronne : d'abord les 6 BOUTIQUES OÙ L'ON ENTRE (TownShops,
-- 30 studs de large : elles tiennent toujours, de 4 à 12 parcelles), puis
-- des boutiques de décor (fermées) dans la place qui reste, de part et
-- d'autre. Renvoie (boutiques de décor, boutiques où l'on entre).
local SHOP_MARGIN = 1.2 -- (studs) de chaque côté d'une façade
local function angularWidth(w: number): number
	return 2 * math.atan((w / 2 + SHOP_MARGIN) / FACADE_R)
end

local function shopRing(folder: Instance, geo: TownKit.Geo, shopsFolder: Instance): (number, number)
	local O = geo.Origin
	local blocked = {}
	for _, slot in ipairs(geo.Streets) do
		local a = geo.SlotAngle(slot)
		local half = math.atan((slot == 0 and 23 or 15) / FACADE_R)
		table.insert(blocked, { a - half, a + half })
	end
	-- mairie (au fond, face à l'avenue)
	local hallHalf = math.atan(36 / FACADE_R)
	table.insert(blocked, { math.pi - hallHalf, math.pi + hallHalf })
	local enterQueue = table.clone(TownShops.SPECS)
	-- décor : pas de 2e magasin de jouets / de fleurs (la jardinerie en vend)
	local decor = {}
	for _, spec in ipairs(TownBuildings.SHOPS) do
		if spec.Kind ~= "Toys" and spec.Kind ~= "Flowers" then
			table.insert(decor, spec)
		end
	end
	local used, entered = 0, 0
	local enterWidth = angularWidth(TownShops.W)
	for _, arc in ipairs(freeArcs(blocked)) do
		local span = arc[2] - arc[1]
		local inner, sides = {}, {}
		local total = 0
		while enterQueue[1] and total + enterWidth <= span do
			table.insert(inner, { Enter = table.remove(enterQueue, 1), Width = enterWidth })
			total += enterWidth
		end
		while true do
			local spec = decor[(used + #sides) % #decor + 1]
			local width = angularWidth(spec.W)
			if total + width > span then
				break
			end
			table.insert(sides, { Spec = spec, Width = width })
			total += width
		end
		-- décor réparti des deux côtés des boutiques où l'on entre
		local chosen = {}
		for i = 1, #sides, 2 do
			table.insert(chosen, sides[i])
		end
		for _, item in ipairs(inner) do
			table.insert(chosen, item)
		end
		for i = 2, #sides, 2 do
			table.insert(chosen, sides[i])
		end
		local a = (arc[1] + arc[2]) / 2 - total / 2
		for _, item in ipairs(chosen) do
			local angle = a + item.Width / 2
			local d = Vector3.new(math.sin(angle), 0, math.cos(angle))
			local p = O + d * FACADE_R + Vector3.new(0, WALK_Y, 0)
			-- (façade vers la place : LookVector = vers le centre)
			local cf = CFrame.lookAt(p, Vector3.new(O.X, p.Y, O.Z))
			local w = item.Enter and TownShops.W or item.Spec.W
			-- trottoir devant la boutique (un poil au-dessus du pavage : pas de
			-- faces confondues avec la place)
			part(folder, "ShopApron", Vector3.new(w + 2, 1.3, 6), cf * CFrame.new(0, -0.65 + 0.04, -2.5), C.Walk, M.Pavement, "solid")
			if item.Enter then
				entered += 1
				TownShops.Shop(shopsFolder, cf, item.Enter, entered)
			else
				TownBuildings.Shop(folder, cf, item.Spec, used + 1)
				used += 1
			end
			a += item.Width
		end
	end
	if enterQueue[1] then
		warn("[TownPlaza] boutiques sans place : " .. #enterQueue)
	end
	return used, entered
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

export type PlazaResult = { Screen: TownBuildings.Screen, ShopsUsed: number, Enterable: number }

-- `shopsFolder` : dossier des boutiques où l'on entre (DopamineTown.Shops)
function TownPlaza.Build(folder: Instance, geo: TownKit.Geo, shopsFolder: Instance?): PlazaResult
	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = folder
	local O = geo.Origin
	local ground = O + Vector3.new(0, WALK_Y, 0)
	paving(plaza, O)
	fountain(plaza, O)
	-- (v9.7) 6 bancs (TownKit.Bench) autour de la fontaine, face au bassin,
	-- jamais dans l'axe de l'avenue ni de la mairie
	for i = 0, 5 do
		local a = (i + 0.5) / 6 * math.pi * 2
		local p = ground + Vector3.new(math.sin(a) * 19, 0, math.cos(a) * 19)
		TownKit.Bench(plaza, CFrame.lookAt(p, ground))
		TownKit.LifeSpot("SitBench", CFrame.lookAt(p, ground), 70 + i) -- (v9.8, CITY98) passants assis (client)
	end
	-- lampadaires à deux lanternes (anneau) ; 2 vraies lumières douces
	-- (les guirlandes lumineuses et les fanions entre eux : client)
	local lampR = R - 6
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		plazaLamp(plaza, ground + d * lampR, Vector3.new(d.Z, 0, -d.X), i == 0 or i == 7)
	end
	-- kiosque (arrière gauche), manège (arrière droit), ballons (avant
	-- droit), glaces (avant gauche), barbe à papa (droite), musicien (gauche)
	local function spot(angle: number, dist: number): Vector3
		return ground + Vector3.new(math.sin(angle) * dist, 0, math.cos(angle) * dist)
	end
	local bandF = CFrame.lookAt(spot(math.rad(225), 41), ground)
	pad(plaza, bandF.Position, 11.5)
	bandstand(plaza, bandF)
	local carF = CFrame.lookAt(spot(math.rad(135), 41), ground)
	pad(plaza, carF.Position, 12)
	local carouselCF = carousel(plaza, carF)
	local tie = balloonCart(plaza, CFrame.lookAt(spot(math.rad(38), 34), ground))
	iceCreamStall(plaza, CFrame.lookAt(spot(math.rad(-38), 34), ground))
	candyStall(plaza, CFrame.lookAt(spot(math.rad(104), 31), ground))
	busker(plaza, CFrame.lookAt(spot(math.rad(292), 33), ground))
	local hop = spot(math.rad(16), 27)
	hopscotch(plaza, CFrame.lookAt(hop, hop - (hop - ground).Unit)) -- ("1" côté avenue, "Sky" côté fontaine)
	chalkArt(plaza, CFrame.new(spot(math.rad(170), 28)))
	-- repères pour le client (TownPlazaFx : manège qui tourne, ballons,
	-- guirlandes, fanions, ampoules du kiosque, pigeons)
	plaza:SetAttribute("FxVersion", 1)
	plaza:SetAttribute("FxCenter", ground)
	plaza:SetAttribute("FxCarouselCF", carouselCF)
	plaza:SetAttribute("FxBalloonTie", tie)
	plaza:SetAttribute("FxBandstandCF", bandF)
	plaza:SetAttribute("FxBandstandFascia", Vector2.new(BAND_FASCIA, BAND_FASCIA_Y))
	plaza:SetAttribute("FxLamps", Vector3.new(lampR, PLAZA_LAMP_TOP, 8))
	plaza:SetAttribute("FxFlock1", spot(math.rad(8), 23))
	plaza:SetAttribute("FxFlock2", spot(math.rad(292), 27))
	plaza:SetAttribute("FxFlock3", spot(math.rad(-30), 27))
	-- (v9.8, CITY98) fontaine animée (eau, jets, pièces : TownFountainFx) et
	-- pigeons 10x (TownPigeons) : repères pour le client
	plaza:SetAttribute("FxFountainBase", ground + Vector3.new(0, 0.15, 0))
	plaza:SetAttribute("FxFlock4", spot(math.rad(200), 30))
	-- parterres fleuris + arbres en bacs
	for i, deg in ipairs({ 58, 110, 160, 200, 250, 302, 322 }) do
		local p = spot(math.rad(deg), 48)
		if i % 2 == 1 then
			TownKit.Column(plaza, "BedRim", p, 1.4, 9, C.Stone, M.Concrete, "prop")
			-- (v9.7 NATURE97) vrai massif : bordure, terre, feuillage, bouquets
			TownKit.FlowerBed(plaza, p + Vector3.new(0, 1, 0), 3.9, i)
		else
			TownKit.Column(plaza, "TreeBox", p, 2, 5, C.White, M.Concrete, "prop")
			TownKit.Tree(plaza, p + Vector3.new(0, 2, 0), 12, i * 13, "Round", { Tier = 1 }) -- (v9.7 NATURE97)
		end
	end
	-- mairie (au fond) + écran des meilleurs joueurs
	local hallP = ground + Vector3.new(0, 0, -(R + 4))
	local hallCF = CFrame.lookAt(hallP, ground)
	part(plaza, "HallApron", Vector3.new(70, 1.3, 8), hallCF * CFrame.new(0, -0.65 + 0.05, -1.5), C.Walk, M.Pavement, "solid")
	local _, screen = TownBuildings.TownHall(plaza, hallCF)
	local used, entered = shopRing(plaza, geo, shopsFolder or plaza)
	return { Screen = screen, ShopsUsed = used, Enterable = entered }
end

return TownPlaza
