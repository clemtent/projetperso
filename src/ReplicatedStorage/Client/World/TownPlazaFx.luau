--[[
	TownPlazaFx (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownPlazaFx

	🎠 La place centrale de Dopamine Town, côté CLIENT (v9.7, PLAZA97) :
	ce qui BOUGE (et le petit décor en plus) est construit ici, en local,
	à partir des repères que le serveur (TownPlaza) pose en attributs sur
	le dossier DopamineTown > Decor > Plaza ("FxCarouselCF", "FxBalloonTie",
	"FxBandstandCF", "FxLamps", "FxFlock1..3"…) :
	  - le MANÈGE : plateau en bois, jupe à panneaux, fût central à 8
	    miroirs encadrés d'or, 10 chevaux (corps, poitrail, croupe, encolure
	    + crinière, tête + museau + oreilles + yeux + bride + plumet, selle
	    + tapis, queue, 4 jambes au galop + sabots dorés) sur leurs barres
	    de laiton, 2 carrosses, plafond à rayons dorés, bandeau festonné à
	    32 ampoules, auvent rayé rose / crème (pyramide à 16 pans) et
	    couronne à fanion. Le plateau TOURNE (un tour en 16 s, synchronisé
	    sur l'heure du serveur : tout le monde voit la même chose) et les
	    chevaux MONTENT et DESCENDENT (déphasés) ;
	  - 9 BALLONS attachés au mât du chariot, qui se balancent ;
	  - guirlandes lumineuses entre les lampadaires, FANIONS colorés sur 4
	    travées, ampoules sous la frise du kiosque (verre mat le jour, Neon
	    la nuit : attribut "NightGlow", géré par TownAtmosphere) ;
	  - 9 PIGEONS en 3 groupes : ils picorent, marchent, se retournent, et
	    s'envolent quand l'avatar approche (puis se reposent plus loin).
	Tout est ancré, sans collision (sauf le plateau et le fût du manège,
	localement), sans ombre pour les petites pièces, SANS son. Animation
	par CFrame (workspace:BulkMoveTo), 30 fois par seconde au plus, et en
	PAUSE quand l'avatar (ou la caméra) est loin : manège > 170 studs,
	ballons / pigeons > 110 studs, toute la place > 260 studs.
	Aucune création / destruction d'instance par image.

	API (TownClient, via optionalModule) :
	  TownPlazaFx.Start()        à l'entrée en ville (construit ; si la
	                             place n'est pas encore là, Step réessaie)
	  TownPlazaFx.Step(dt)       à chaque image (limité à 30 Hz ici)
	  TownPlazaFx.Stop()         à la sortie (tout est détruit)
	  TownPlazaFx.Debug() -> table
]]

local Players = game:GetService("Players")

local TownPlazaFx = {}

local LocalPlayer = Players.LocalPlayer

local STEP = 1 / 30
local RETRY = 1 -- (s) place pas encore répliquée : on réessaie
local FAR_PLAZA = 260
local FAR_CAROUSEL = 170
local FAR_SMALL = 110
local SPIN = math.pi * 2 / 16 -- (rad/s) un tour en 16 s
local BOB_SPEED = math.pi * 2 / 2.6 -- (rad/s) une montée-descente en 2,6 s
local BOB_AMP = 0.5 -- (studs)
local FLEE_R = 5.5 -- (studs) un avatar plus près : les pigeons s'envolent

local M = Enum.Material
local UP = Vector3.new(0, 1, 0)
local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)

type Mover = { Parts: { BasePart }, Locals: { CFrame }, Group: { number }, Frames: { CFrame } }

local state: any = nil

----------------------------------------------------------------------
-- Fabrique de pièces (locales)
----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		(p :: Part).Shape = shape
	end
	p.Parent = parent
	return p
end

-- Ampoule : mate le jour, Neon la nuit (TownAtmosphere, attribut NightGlow)
local function glow(p: BasePart): BasePart
	p.Material = M.SmoothPlastic
	p:SetAttribute("NightGlow", true)
	return p
end

-- Triangle rectangle (WedgePart) : angle droit en p0, côtés le long de u
-- (l1) et de v (l2) ; renvoie taille + CFrame (dans le repère de p0/u/v)
local function triCF(p0: Vector3, u: Vector3, v: Vector3, l1: number, l2: number, t: number): (Vector3, CFrame)
	local Z = -v
	local X = u:Cross(Z)
	return Vector3.new(t, l1, l2), CFrame.fromMatrix(p0 + u * (l1 / 2) + v * (l2 / 2), X, u, Z)
end

-- Tige (cylindre) entre deux points
local function rodCF(a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
end

local function vec3Attr(folder: Instance, name: string): Vector3?
	local v = folder:GetAttribute(name)
	return typeof(v) == "Vector3" and v or nil
end

local function cfAttr(folder: Instance, name: string): CFrame?
	local v = folder:GetAttribute(name)
	return typeof(v) == "CFrame" and v or nil
end

----------------------------------------------------------------------
-- Le manège (tout ce qui tourne)
----------------------------------------------------------------------

local HORSE_COLORS = {
	{ Body = Color3.fromRGB(252, 250, 246), Mane = Color3.fromRGB(255, 150, 196), Saddle = Color3.fromRGB(214, 60, 96) },
	{ Body = Color3.fromRGB(200, 176, 240), Mane = Color3.fromRGB(255, 236, 170), Saddle = Color3.fromRGB(96, 70, 170) },
	{ Body = Color3.fromRGB(255, 206, 222), Mane = Color3.fromRGB(252, 250, 246), Saddle = Color3.fromRGB(236, 72, 140) },
	{ Body = Color3.fromRGB(170, 230, 206), Mane = Color3.fromRGB(255, 176, 120), Saddle = Color3.fromRGB(40, 140, 120) },
	{ Body = Color3.fromRGB(176, 214, 255), Mane = Color3.fromRGB(255, 255, 255), Saddle = Color3.fromRGB(56, 96, 196) },
	{ Body = Color3.fromRGB(96, 80, 90), Mane = Color3.fromRGB(255, 214, 96), Saddle = Color3.fromRGB(214, 60, 96) },
	{ Body = Color3.fromRGB(255, 226, 190), Mane = Color3.fromRGB(196, 120, 80), Saddle = Color3.fromRGB(150, 70, 170) },
	{ Body = Color3.fromRGB(226, 226, 232), Mane = Color3.fromRGB(120, 120, 140), Saddle = Color3.fromRGB(40, 140, 196) },
	{ Body = Color3.fromRGB(255, 240, 150), Mane = Color3.fromRGB(255, 130, 170), Saddle = Color3.fromRGB(214, 90, 60) },
	{ Body = Color3.fromRGB(236, 180, 255), Mane = Color3.fromRGB(150, 220, 255), Saddle = Color3.fromRGB(120, 60, 180) },
}
local GOLD = Color3.fromRGB(236, 196, 96)
local PINK = Color3.fromRGB(255, 150, 190)
local CREAM = Color3.fromRGB(255, 244, 226)

-- Un cheval de manège (repère : centre du corps, avant = -Z) ; `add`
-- enregistre chaque pièce avec son CFrame LOCAL (relatif au cheval)
local function horse(add: (string, Vector3, CFrame, Color3, Enum.Material?, Enum.PartType?, string?) -> (), colors: any, seed: number)
	local body, mane, saddle = colors.Body, colors.Mane, colors.Saddle
	add("Body", Vector3.new(2.5, 1.25, 1.25), CFrame.Angles(0, math.rad(90), 0), body, M.SmoothPlastic, Enum.PartType.Cylinder)
	add("Chest", Vector3.new(1.35, 1.35, 1.35), CFrame.new(0, 0.08, -1.15), body, M.SmoothPlastic, Enum.PartType.Ball)
	add("Rump", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 0.05, 1.1), body, M.SmoothPlastic, Enum.PartType.Ball)
	local neck = CFrame.new(0, 0.95, -1.55) * CFrame.Angles(math.rad(-28), 0, 0)
	add("Neck", Vector3.new(0.62, 1.7, 0.8), neck, body, M.SmoothPlastic)
	add("Mane", Vector3.new(0.22, 1.75, 0.3), neck * CFrame.new(0, 0.12, 0.42), mane, M.SmoothPlastic)
	local head = CFrame.new(0, 1.85, -2.2) * CFrame.Angles(math.rad(-18), 0, 0)
	add("Head", Vector3.new(0.6, 0.62, 1.3), head, body, M.SmoothPlastic)
	add("Muzzle", Vector3.new(0.55, 0.55, 0.55), head * CFrame.new(0, -0.08, -0.6), body, M.SmoothPlastic, Enum.PartType.Ball)
	add("Bridle", Vector3.new(0.66, 0.68, 0.1), head * CFrame.new(0, 0, -0.3), GOLD, M.Metal)
	add("Plume", Vector3.new(0.42, 0.42, 0.42), head * CFrame.new(0, 0.45, 0.12), mane, M.SmoothPlastic, Enum.PartType.Ball)
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", Vector3.new(0.14, 0.34, 0.16), head * CFrame.new(sx * 0.18, 0.42, 0.42), body, M.SmoothPlastic)
		add("Eye", Vector3.new(0.15, 0.15, 0.15), head * CFrame.new(sx * 0.3, 0.12, -0.22), Color3.fromRGB(40, 30, 44), M.SmoothPlastic, Enum.PartType.Ball)
	end
	add("Blanket", Vector3.new(1.36, 0.08, 1.3), CFrame.new(0, 0.62, -0.05), GOLD, M.Fabric)
	add("Saddle", Vector3.new(1, 0.25, 1.1), CFrame.new(0, 0.75, -0.05), saddle, M.Leather)
	add("Tail", Vector3.new(0.3, 1.3, 0.34), CFrame.new(0, -0.12, 1.85) * CFrame.Angles(math.rad(-25), 0, 0), mane, M.SmoothPlastic)
	-- jambes au galop (un peu différentes d'un cheval à l'autre)
	local lift = (seed % 3) * 8
	local legs = {
		{ -0.33, -1.1, 70 - lift },
		{ 0.33, -1.1, 42 + lift },
		{ -0.33, 1.1, -34 },
		{ 0.33, 1.1, -22 - lift / 2 },
	}
	for _, l in ipairs(legs) do
		local pivot = CFrame.new(l[1], -0.4, l[2]) * CFrame.Angles(math.rad(l[3]), 0, 0)
		add("Leg", Vector3.new(0.28, 1.4, 0.28), pivot * CFrame.new(0, -0.7, 0), body, M.SmoothPlastic)
		add("Hoof", Vector3.new(0.34, 0.24, 0.4), pivot * CFrame.new(0, -1.45, 0), GOLD, M.Metal)
	end
end

-- Un carrosse (repère au plancher du manège, avant = -Z)
local function carriage(add: (string, Vector3, CFrame, Color3, Enum.Material?, Enum.PartType?, string?) -> (), tint: Color3)
	add("CarriageFloor", Vector3.new(2.3, 0.3, 3.4), CFrame.new(0, 0.45, 0), GOLD, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		add("CarriageSide", Vector3.new(0.25, 1.4, 3.3), CFrame.new(sx * 1.08, 1.3, 0), tint, M.SmoothPlastic)
		add("CarriageKnob", Vector3.new(0.5, 0.5, 0.5), CFrame.new(sx * 1.08, 2.55, 1.5), GOLD, M.Metal, Enum.PartType.Ball)
	end
	add("CarriageBack", Vector3.new(2.1, 1.9, 0.3), CFrame.new(0, 1.55, 1.5), tint, M.SmoothPlastic)
	add("CarriageSeat", Vector3.new(1.9, 0.45, 1), CFrame.new(0, 0.825, 0.85), CREAM, M.Fabric)
	add("CarriageFront", Vector3.new(2.1, 1.2, 0.3), CFrame.new(0, 1.2, -1.5), tint, M.SmoothPlastic)
	add("CarriageSwan", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 2.1, -1.55), GOLD, M.Metal, Enum.PartType.Ball)
end

local function buildCarousel(folder: Instance, R0: CFrame)
	local model = Instance.new("Model")
	model.Name = "Carousel"
	model.Parent = folder
	local c = { Base = R0, Parts = {}, Locals = {}, Group = {}, Frames = {}, HorseBase = {}, HorsePhase = {}, HorseCF = {} }
	-- pièce FIXE (symétrique autour de l'axe : inutile de la tourner)
	local function fixed(name: string, size: Vector3, loc: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, solid: boolean?): BasePart
		local p = newPart(model, name, size, R0 * loc, color, material, shape)
		if solid then
			p.CanCollide = true
			p.CanQuery = true
		end
		return p
	end
	-- pièce qui TOURNE (groupe 0) ou qui monte et descend (groupe = cheval)
	local function moving(group: number, name: string, size: Vector3, loc: CFrame, world: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
		local p = newPart(model, name, size, world, color, material, shape, className)
		table.insert(c.Parts, p)
		table.insert(c.Locals, loc)
		table.insert(c.Group, group)
		table.insert(c.Frames, world)
		return p
	end
	local function rotor(name: string, size: Vector3, loc: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
		return moving(0, name, size, loc, R0 * loc, color, material, shape, className)
	end
	local function ring(n: number, i: number, r: number, y: number): CFrame
		local a = (i + 0.5) / n * math.pi * 2
		local p = Vector3.new(math.sin(a) * r, y, math.cos(a) * r)
		return CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z)) -- (-Z local = vers l'extérieur)
	end
	-- plateau (bois), fût central, bagues dorées, plafond : fixes
	fixed("Deck", Vector3.new(0.3, 16.8, 16.8), CFrame.new(0, 0.15, 0) * VERTICAL, Color3.fromRGB(214, 164, 116), M.WoodPlanks, Enum.PartType.Cylinder, true)
	fixed("Drum", Vector3.new(7.8, 3.8, 3.8), CFrame.new(0, 4.1, 0) * VERTICAL, CREAM, M.SmoothPlastic, Enum.PartType.Cylinder, true)
	fixed("DrumBand", Vector3.new(0.4, 4.2, 4.2), CFrame.new(0, 0.5, 0) * VERTICAL, GOLD, M.Metal, Enum.PartType.Cylinder)
	fixed("DrumBand", Vector3.new(0.4, 4.2, 4.2), CFrame.new(0, 7.4, 0) * VERTICAL, GOLD, M.Metal, Enum.PartType.Cylinder)
	fixed("Ceiling", Vector3.new(0.25, 17.7, 17.7), CFrame.new(0, 8.025, 0) * VERTICAL, CREAM, M.SmoothPlastic, Enum.PartType.Cylinder)
	-- jupe du plateau : 16 panneaux or / rose
	for i = 0, 15 do
		rotor("Skirt", Vector3.new(3.38, 0.6, 0.12), ring(16, i, 8.45, 0.12), i % 2 == 0 and GOLD or PINK, i % 2 == 0 and M.Metal or M.SmoothPlastic)
	end
	-- fût : 8 miroirs encadrés + 8 pilastres dorés
	for i = 0, 7 do
		rotor("MirrorFrame", Vector3.new(1.5, 2.9, 0.12), ring(8, i, 1.98, 4.3), GOLD, M.Metal)
		local mirror = rotor("Mirror", Vector3.new(1.2, 2.6, 0.08), ring(8, i, 2.07, 4.3), Color3.fromRGB(224, 236, 248), M.SmoothPlastic)
		mirror.Reflectance = 0.5
		rotor("Pilaster", Vector3.new(0.28, 6.5, 0.28), ring(8, i + 0.5, 2, 3.95), GOLD, M.Metal)
	end
	-- plafond : 8 rayons dorés (ils tournent)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local mid = d * 5.4 + Vector3.new(0, 7.875, 0)
		rotor("Ray", Vector3.new(0.35, 0.05, 6.6), CFrame.lookAt(mid, mid + d), GOLD, M.Metal)
	end
	-- bandeau (16 panneaux crème / rose), 32 ampoules, 32 festons
	for i = 0, 15 do
		local board = ring(16, i, 9.05, 7.6)
		rotor("Board", Vector3.new(3.62, 1.1, 0.3), board, i % 2 == 0 and CREAM or PINK, M.SmoothPlastic)
		for _, x in ipairs({ -0.9, 0.9 }) do
			local bulb = rotor("Bulb", Vector3.new(0.32, 0.32, 0.32), board * CFrame.new(x, 0, -0.25), Color3.fromRGB(255, 232, 180), M.SmoothPlastic, Enum.PartType.Ball)
			glow(bulb)
			rotor("Scallop", Vector3.new(0.12, 1.2, 1.2), board * CFrame.new(x, -0.55, 0) * CFrame.Angles(0, math.rad(90), 0), x < 0 and PINK or CREAM, M.Fabric, Enum.PartType.Cylinder)
		end
	end
	-- auvent : pyramide à 16 pans rayés rose / crème
	local e, y0, y1 = 9.35, 8.15, 11.6
	local apex = Vector3.new(0, y1, 0)
	local half = e * math.tan(math.pi / 16)
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2
		local nrm = Vector3.new(math.sin(a), 0, math.cos(a))
		local side = UP:Cross(nrm).Unit
		local mid = nrm * e + Vector3.new(0, y0, 0)
		local w = apex - mid
		for _, sv in ipairs({ side, -side }) do
			local size, loc = triCF(mid, w.Unit, sv, w.Magnitude, half, 0.2)
			rotor("Canopy", size, loc, k % 2 == 0 and Color3.fromRGB(255, 132, 180) or CREAM, M.Fabric, nil, "WedgePart")
		end
	end
	-- couronne : tambour doré, boule rose, mât et fanion
	rotor("Crown", Vector3.new(0.8, 1.7, 1.7), CFrame.new(0, 11.6, 0) * VERTICAL, GOLD, M.Metal, Enum.PartType.Cylinder)
	rotor("CrownBall", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 12.4, 0), PINK, M.SmoothPlastic, Enum.PartType.Ball)
	rotor("FlagPole", Vector3.new(2.2, 0.12, 0.12), rodCF(Vector3.new(0, 12.9, 0), Vector3.new(0, 15.1, 0)), GOLD, M.Metal, Enum.PartType.Cylinder)
	local fSize, fLoc = triCF(Vector3.new(0, 15, 0), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0), 1.6, 0.9, 0.06)
	rotor("Flag", fSize, fLoc, Color3.fromRGB(236, 72, 140), M.Fabric, nil, "WedgePart")
	-- 10 chevaux (6 au bord, 4 à l'intérieur) + 2 carrosses, barres de laiton
	local spots = {}
	for k = 0, 7 do
		table.insert(spots, { A = k / 8 * math.pi * 2, R = 6.6, Carriage = k == 0 or k == 4 })
	end
	for k = 0, 3 do
		table.insert(spots, { A = (k + 0.25) / 4 * math.pi * 2, R = 4, Carriage = false })
	end
	local horseIndex = 0
	for _, s in ipairs(spots) do
		local pos = Vector3.new(math.sin(s.A) * s.R, 0, math.cos(s.A) * s.R)
		local fwd = Vector3.new(math.cos(s.A), 0, -math.sin(s.A)) -- sens de la rotation
		local base = CFrame.lookAt(pos, pos + fwd)
		if s.Carriage then
			carriage(function(name, size, loc, color, material, shape, className)
				rotor(name, size, base * loc, color, material, shape, className)
			end, horseIndex % 2 == 0 and PINK or Color3.fromRGB(190, 160, 240))
		else
			horseIndex += 1
			local k = horseIndex
			local hb = base * CFrame.new(0, 2.75, 0)
			c.HorseBase[k] = hb
			c.HorsePhase[k] = (k % 2) * math.pi + k * 0.35
			c.HorseCF[k] = R0 * hb
			rotor("Pole", Vector3.new(7.6, 0.24, 0.24), CFrame.new(pos.X, 4.1, pos.Z) * VERTICAL, GOLD, M.Metal, Enum.PartType.Cylinder)
			horse(function(name, size, loc, color, material, shape, className)
				moving(k, name, size, loc, R0 * hb * loc, color, material, shape, className)
			end, HORSE_COLORS[(k - 1) % #HORSE_COLORS + 1], k)
		end
	end
	return c
end

local function stepCarousel(c: any, now: number)
	local theta = (now * SPIN) % (math.pi * 2)
	local rot = c.Base * CFrame.Angles(0, theta, 0)
	local horseCF = c.HorseCF
	for k, hb in ipairs(c.HorseBase) do
		local bob = BOB_AMP * math.sin(now * BOB_SPEED + c.HorsePhase[k])
		horseCF[k] = rot * hb * CFrame.new(0, bob, 0)
	end
	local frames, locals, group = c.Frames, c.Locals, c.Group
	for i = 1, #frames do
		local g = group[i]
		frames[i] = (g == 0 and rot or horseCF[g]) * locals[i]
	end
	workspace:BulkMoveTo(c.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

----------------------------------------------------------------------
-- Ballons du chariot
----------------------------------------------------------------------

local BALLOON_COLORS = {
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(126, 196, 255),
	Color3.fromRGB(255, 222, 110),
	Color3.fromRGB(128, 222, 190),
	Color3.fromRGB(186, 150, 246),
	Color3.fromRGB(255, 110, 110),
	Color3.fromRGB(255, 186, 140),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(236, 72, 140),
}

local function buildBalloons(folder: Instance, tie: Vector3)
	local model = Instance.new("Model")
	model.Name = "Balloons"
	model.Parent = folder
	local b = { Tie = tie, Items = {}, Parts = {}, Frames = {} }
	for i, color in ipairs(BALLOON_COLORS) do
		local a = i / #BALLOON_COLORS * math.pi * 2 + (i % 2) * 0.3
		local spread = 0.28 + (i % 3) * 0.08
		local rest = Vector3.new(math.cos(a) * spread, 1, math.sin(a) * spread).Unit
		local len = 4.2 + (i % 3) * 0.9
		local item = {
			Rest = rest,
			Len = len,
			Phase = i * 1.7,
			String = newPart(model, "String", Vector3.new(0.05, 0.05, len), CFrame.new(tie), Color3.fromRGB(250, 250, 250)),
			Knot = newPart(model, "Knot", Vector3.new(0.28, 0.28, 0.28), CFrame.new(tie), color, M.SmoothPlastic, Enum.PartType.Ball),
			Ball = newPart(model, "Balloon", Vector3.new(1.55, 1.55, 1.55), CFrame.new(tie), color, M.SmoothPlastic, Enum.PartType.Ball),
		}
		item.Ball.Reflectance = 0.12
		table.insert(b.Items, item)
		table.insert(b.Parts, item.String)
		table.insert(b.Parts, item.Knot)
		table.insert(b.Parts, item.Ball)
		table.insert(b.Frames, CFrame.new(tie))
		table.insert(b.Frames, CFrame.new(tie))
		table.insert(b.Frames, CFrame.new(tie))
	end
	return b
end

local function stepBalloons(b: any, t: number)
	local tie = b.Tie
	local frames = b.Frames
	for i, item in ipairs(b.Items) do
		local ph = item.Phase
		local dir = (item.Rest + Vector3.new(math.sin(t * 0.9 + ph) * 0.1, 0, math.cos(t * 0.7 + ph * 2) * 0.1)).Unit
		local tip = tie + dir * item.Len
		frames[i * 3 - 2] = CFrame.lookAt((tie + tip) / 2, tip)
		frames[i * 3 - 1] = CFrame.new(tip + dir * 0.1)
		frames[i * 3] = CFrame.new(tip + dir * 0.86)
	end
	workspace:BulkMoveTo(b.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

----------------------------------------------------------------------
-- Guirlandes, fanions, ampoules du kiosque (fixes)
----------------------------------------------------------------------

local LIGHT_COLORS = {
	Color3.fromRGB(255, 232, 180),
	Color3.fromRGB(255, 176, 206),
	Color3.fromRGB(176, 214, 255),
	Color3.fromRGB(255, 236, 150),
	Color3.fromRGB(176, 236, 206),
}
local FLAG_COLORS = {
	Color3.fromRGB(255, 132, 184),
	Color3.fromRGB(126, 196, 255),
	Color3.fromRGB(255, 222, 110),
	Color3.fromRGB(128, 222, 190),
	Color3.fromRGB(186, 150, 246),
	Color3.fromRGB(255, 170, 130),
}

-- point d'une chaînette (parabole) entre a et b, flèche `sag`
local function sagAt(a: Vector3, b: Vector3, sag: number, t: number): Vector3
	return a:Lerp(b, t) - Vector3.new(0, sag * (1 - (2 * t - 1) ^ 2), 0)
end

local function wire(model: Instance, a: Vector3, b: Vector3, sag: number, color: Color3)
	local steps = 4
	for i = 0, steps - 1 do
		local p, q = sagAt(a, b, sag, i / steps), sagAt(a, b, sag, (i + 1) / steps)
		newPart(model, "Wire", Vector3.new((q - p).Magnitude, 0.08, 0.08), rodCF(p, q), color, M.SmoothPlastic, Enum.PartType.Cylinder)
	end
end

local function buildGarlands(folder: Instance, center: Vector3, lamps: Vector3)
	local model = Instance.new("Model")
	model.Name = "Garlands"
	model.Parent = folder
	local r, top, n = lamps.X, lamps.Y, math.floor(lamps.Z + 0.5)
	local tops, lows = {}, {}
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		tops[i + 1] = center + d * r + Vector3.new(0, top, 0)
		lows[i + 1] = center + d * (r - 0.3) + Vector3.new(0, 8.6, 0)
	end
	local ink = Color3.fromRGB(60, 56, 72)
	for i = 1, n do
		local a, b = tops[i], tops[i % n + 1]
		-- guirlande lumineuse : fil qui pend + 7 ampoules
		wire(model, a, b, 2.2, ink)
		for k = 1, 7 do
			local p = sagAt(a, b, 2.2, k / 8) - Vector3.new(0, 0.3, 0)
			glow(newPart(model, "Bulb", Vector3.new(0.42, 0.42, 0.42), CFrame.new(p), LIGHT_COLORS[(i + k) % #LIGHT_COLORS + 1], M.SmoothPlastic, Enum.PartType.Ball))
		end
		-- fanions (une travée sur deux, plus bas)
		if i % 2 == 0 then
			local la, lb = lows[i], lows[i % n + 1]
			wire(model, la, lb, 1.8, Color3.fromRGB(250, 250, 250))
			local flags = 12
			for k = 1, flags do
				local t = k / (flags + 1)
				local p = sagAt(la, lb, 1.8, t)
				local along = (sagAt(la, lb, 1.8, t + 0.01) - sagAt(la, lb, 1.8, t - 0.01)).Unit
				local color = FLAG_COLORS[(k + i) % #FLAG_COLORS + 1]
				for _, sv in ipairs({ along, -along }) do
					local size, cf = triCF(p, -UP, sv, 1.1, 0.42, 0.05)
					newPart(model, "Pennant", size, cf, color, M.Fabric, nil, "WedgePart")
				end
			end
		end
	end
end

local function buildBandstandLights(folder: Instance, F: CFrame, fascia: Vector2)
	local model = Instance.new("Model")
	model.Name = "BandstandLights"
	model.Parent = folder
	local e, y = fascia.X + 0.12, fascia.Y - 0.12
	local half = e * math.tan(math.pi / 8)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local nrm = F:VectorToWorldSpace(Vector3.new(math.sin(a), 0, -math.cos(a)))
		local side = UP:Cross(nrm).Unit
		local mid = F.Position + nrm * e + Vector3.new(0, y, 0)
		for q = -1, 1 do
			local p = mid + side * (q * half * 0.62) - Vector3.new(0, q == 0 and 0.35 or 0.15, 0)
			glow(newPart(model, "Bulb", Vector3.new(0.36, 0.36, 0.36), CFrame.new(p), LIGHT_COLORS[(k + q + 2) % #LIGHT_COLORS + 1], M.SmoothPlastic, Enum.PartType.Ball))
		end
	end
end

----------------------------------------------------------------------
-- Pigeons
----------------------------------------------------------------------

local NECK = CFrame.new(0, 0.5, -0.1) -- pivot de la tête (picorer : jusqu'au sol)
local NECK_INV = NECK:Inverse()
local SHOULDERS = { CFrame.new(-0.26, 0.6, 0.05), CFrame.new(0.26, 0.6, 0.05) }
local SHOULDERS_INV = { SHOULDERS[1]:Inverse(), SHOULDERS[2]:Inverse() }

type Pigeon = {
	Pos: Vector3,
	Yaw: number,
	Home: Vector3,
	Mode: string,
	Timer: number,
	Clock: number,
	Rng: Random,
	From: Vector3,
	To: Vector3,
	Calm: number,
	Parts: { BasePart },
	Locals: { CFrame },
	Kind: { number }, -- 0 corps, 1 tête, 2 aile gauche, 3 aile droite
}

local function buildPigeons(folder: Instance, homes: { Vector3 }): any
	local model = Instance.new("Model")
	model.Name = "Pigeons"
	model.Parent = folder
	local P = { List = {}, Parts = {}, Frames = {} }
	local gray = Color3.fromRGB(150, 154, 170)
	for h, home in ipairs(homes) do
		for j = 1, 3 do
			local rng = Random.new(h * 31 + j * 7)
			local a = rng:NextNumber(0, math.pi * 2)
			local pos = home + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(0.8, 3.2)
			local bird: Pigeon = {
				Pos = pos,
				Yaw = rng:NextNumber(0, math.pi * 2),
				Home = home,
				Mode = "idle",
				Timer = rng:NextNumber(0.2, 1.5),
				Clock = 0,
				Rng = rng,
				From = pos,
				To = pos,
				Calm = 0,
				Parts = {},
				Locals = {},
				Kind = {},
			}
			local tint = (h + j) % 3 == 0 and Color3.fromRGB(196, 190, 196) or gray
			local function add(name: string, size: Vector3, loc: CFrame, color: Color3, shape: Enum.PartType?, kind: number)
				local p = newPart(model, name, size, CFrame.new(pos) * loc, color, M.SmoothPlastic, shape)
				table.insert(bird.Parts, p)
				table.insert(bird.Locals, loc)
				table.insert(bird.Kind, kind)
				table.insert(P.Parts, p)
				table.insert(P.Frames, p.CFrame)
			end
			add("Body", Vector3.new(0.62, 0.62, 0.62), CFrame.new(0, 0.42, 0.05), tint, Enum.PartType.Ball, 0)
			add("Breast", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.5, -0.2), Color3.fromRGB(118, 142, 150), Enum.PartType.Ball, 0)
			add("Tail", Vector3.new(0.26, 0.05, 0.42), CFrame.new(0, 0.42, 0.45) * CFrame.Angles(math.rad(15), 0, 0), Color3.fromRGB(92, 96, 116), nil, 0)
			add("Head", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0, 0.82, -0.33), Color3.fromRGB(106, 112, 138), Enum.PartType.Ball, 1)
			add("Beak", Vector3.new(0.08, 0.08, 0.16), CFrame.new(0, 0.8, -0.53), Color3.fromRGB(70, 62, 66), nil, 1)
			add("Wing", Vector3.new(0.08, 0.3, 0.5), CFrame.new(-0.3, 0.47, 0.1), Color3.fromRGB(122, 126, 146), nil, 2)
			add("Wing", Vector3.new(0.08, 0.3, 0.5), CFrame.new(0.3, 0.47, 0.1), Color3.fromRGB(122, 126, 146), nil, 3)
			table.insert(P.List, bird)
		end
	end
	return P
end

local function stepPigeons(P: any, dt: number, focus: Vector3?)
	local frames = P.Frames
	local index = 0
	for _, bird in ipairs(P.List) do
		local rng = bird.Rng
		bird.Timer -= dt
		bird.Clock += dt
		bird.Calm = math.max(0, bird.Calm - dt)
		local lift, pitch, flap = 0, 0, 0
		-- un avatar approche : envol (loin de lui), atterrissage plus loin
		if focus and bird.Mode ~= "fly" and bird.Calm <= 0 then
			local away = Vector3.new(bird.Pos.X - focus.X, 0, bird.Pos.Z - focus.Z)
			if away.Magnitude < FLEE_R and math.abs(focus.Y - bird.Pos.Y) < 8 then
				local dir = away.Magnitude > 0.05 and away.Unit or Vector3.new(1, 0, 0)
				local target = bird.Pos + dir * rng:NextNumber(8, 12)
				local fromHome = target - bird.Home
				if fromHome.Magnitude > 9 then
					target = bird.Home + fromHome.Unit * 9
				end
				bird.Mode, bird.Timer, bird.Clock = "fly", 1.6, 0
				bird.From, bird.To = bird.Pos, Vector3.new(target.X, bird.Home.Y, target.Z)
				local flat = bird.To - bird.From
				if flat.Magnitude > 0.1 then
					bird.Yaw = math.atan2(-flat.X, -flat.Z)
				end
			end
		end
		if bird.Mode == "fly" then
			local t = math.clamp(bird.Clock / 1.6, 0, 1)
			bird.Pos = bird.From:Lerp(bird.To, t)
			lift = math.sin(t * math.pi) * 5
			flap = math.sin(bird.Clock * 50) * 1.1
			if t >= 1 then
				bird.Mode, bird.Timer, bird.Calm = "idle", rng:NextNumber(1.5, 3), 2
			end
		elseif bird.Mode == "walk" then
			local step = Vector3.new(-math.sin(bird.Yaw), 0, -math.cos(bird.Yaw)) * (1.1 * dt)
			local nextPos = bird.Pos + step
			if (nextPos - bird.Home).Magnitude > 5.5 then
				local back = bird.Home - bird.Pos
				bird.Yaw = math.atan2(-back.X, -back.Z)
			else
				bird.Pos = nextPos
			end
			pitch = math.sin(bird.Clock * 24) * 0.18
			lift = math.abs(math.sin(bird.Clock * 12)) * 0.04
		elseif bird.Mode == "peck" then
			pitch = math.sin(math.clamp(bird.Clock / 0.4, 0, 1) * math.pi) * 1.5
		end
		if bird.Mode ~= "fly" and bird.Timer <= 0 then
			local roll = rng:NextNumber()
			bird.Clock = 0
			if roll < 0.4 then
				bird.Mode, bird.Timer = "peck", 0.4
			elseif roll < 0.72 then
				bird.Mode, bird.Timer = "walk", rng:NextNumber(0.5, 1.4)
			elseif roll < 0.86 then
				bird.Mode, bird.Timer = "idle", rng:NextNumber(0.3, 0.8)
				bird.Yaw += rng:NextNumber(-1.4, 1.4)
			else
				bird.Mode, bird.Timer = "idle", rng:NextNumber(0.6, 1.8)
			end
		end
		local root = CFrame.new(bird.Pos + Vector3.new(0, lift, 0)) * CFrame.Angles(0, bird.Yaw, 0)
		local headCF = root * NECK * CFrame.Angles(-pitch, 0, 0) * NECK_INV
		for i = 1, #bird.Parts do
			index += 1
			local kind = bird.Kind[i]
			local loc = bird.Locals[i]
			if kind == 1 then
				frames[index] = headCF * loc
			elseif kind == 2 or kind == 3 then
				local sign = kind == 2 and 1 or -1
				frames[index] = root * SHOULDERS[kind - 1] * CFrame.Angles(0, 0, sign * flap) * SHOULDERS_INV[kind - 1] * loc
			else
				frames[index] = root * loc
			end
		end
	end
	workspace:BulkMoveTo(P.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

----------------------------------------------------------------------
-- Construction / boucle
----------------------------------------------------------------------

local function findPlaza(): (Instance?, Instance?)
	local town = workspace:FindFirstChild("DopamineTown")
	local decor = town and town:FindFirstChild("Decor")
	local plaza = decor and decor:FindFirstChild("Plaza")
	if plaza and plaza:GetAttribute("FxVersion") ~= nil then
		return town, plaza
	end
	return nil, nil
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and type(t) == "number" and t or os.clock()
end

local function build(): boolean
	local town, plaza = findPlaza()
	if not town or not plaza then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "TownPlazaFx"
	local s = state
	s.Folder = folder
	s.Center = vec3Attr(plaza, "FxCenter") or Vector3.new(0, 0, 0)
	local carCF = cfAttr(plaza, "FxCarouselCF")
	if carCF then
		s.Carousel = buildCarousel(folder, carCF)
	end
	local tie = vec3Attr(plaza, "FxBalloonTie")
	if tie then
		s.Balloons = buildBalloons(folder, tie)
	end
	local lamps = vec3Attr(plaza, "FxLamps")
	if lamps then
		buildGarlands(folder, s.Center, lamps)
	end
	local bandCF = cfAttr(plaza, "FxBandstandCF")
	local fascia = plaza:GetAttribute("FxBandstandFascia")
	if bandCF and typeof(fascia) == "Vector2" then
		buildBandstandLights(folder, bandCF, fascia)
	end
	local homes = {}
	for i = 1, 3 do
		local home = vec3Attr(plaza, "FxFlock" .. i)
		if home then
			table.insert(homes, home + Vector3.new(0, 0.12, 0))
		end
	end
	s.Pigeons = buildPigeons(folder, homes)
	-- (sous DopamineTown : TownAtmosphere suit les ampoules "NightGlow")
	folder.Parent = town
	s.Built = true
	return true
end

local function focusPoint(): Vector3?
	local character = LocalPlayer and LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

function TownPlazaFx.Start()
	if state then
		return
	end
	state = { Built = false, Acc = 0, Retry = 0, Time = 0, Fails = 0 }
	local ok, err = pcall(build)
	if not ok then
		state.Fails += 1
		warn("[TownPlazaFx] " .. tostring(err))
	end
end

function TownPlazaFx.Step(dt: number)
	local s = state
	if not s then
		return
	end
	s.Acc += dt
	if s.Acc < STEP then
		return
	end
	local elapsed = math.min(s.Acc, 0.25)
	s.Acc = 0
	s.Time += elapsed
	-- (la ville a été reconstruite : nos pièces sont parties avec elle)
	if s.Built and (s.Folder == nil or s.Folder.Parent == nil) then
		s.Built = false
		s.Carousel, s.Balloons, s.Pigeons = nil, nil, nil
	end
	if not s.Built then
		-- (3 échecs de construction : on abandonne, sans bruit ni coût)
		s.Retry -= elapsed
		if s.Retry <= 0 and s.Fails < 3 then
			s.Retry = RETRY
			local ok, err = pcall(build)
			if not ok then
				s.Fails += 1
				warn("[TownPlazaFx] " .. tostring(err))
				if s.Folder then
					s.Folder:Destroy()
					s.Folder = nil
				end
			end
		end
		return
	end
	local focus = focusPoint()
	if not focus then
		return
	end
	local fromCenter = Vector3.new(focus.X - s.Center.X, 0, focus.Z - s.Center.Z).Magnitude
	if fromCenter > FAR_PLAZA then
		return
	end
	local c = s.Carousel
	if c and (focus - c.Base.Position).Magnitude < FAR_CAROUSEL then
		stepCarousel(c, serverNow())
	end
	local b = s.Balloons
	if b and (focus - b.Tie).Magnitude < FAR_SMALL then
		stepBalloons(b, s.Time)
	end
	local p = s.Pigeons
	if p and fromCenter < FAR_SMALL + 40 then
		local character = LocalPlayer and LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		stepPigeons(p, elapsed, root and (root :: BasePart).Position or nil)
	end
end

function TownPlazaFx.Stop()
	local s = state
	state = nil
	if s and s.Folder then
		s.Folder:Destroy()
	end
end

function TownPlazaFx.Debug(): any
	return { State = state }
end

return TownPlazaFx
