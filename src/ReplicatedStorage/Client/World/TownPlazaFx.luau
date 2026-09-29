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
	  - (v9.8, CITY98) 20 PIGEONS réalistes en 4 groupes (module
	    TownPigeons : picorent, marchent en hochant la tête, roucoulent,
	    s'envolent devant l'avatar ou les passants, se perchent sur les
	    lanternes et la margelle) et l'EAU animée de la fontaine (module
	    TownFountainFx : jets en arc, rideaux, ronds, pièces, sculptures).
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- (v9.8, FAIR98) pose du manège partagée avec le serveur (sièges où l'on monte)
local FairRides = require(ReplicatedStorage.Shared.FairRides)
local TownPigeons = require(script.Parent.TownPigeons) -- (v9.8, CITY98) pigeons 10x
local TownFountainFx = require(script.Parent.TownFountainFx) -- (v9.8, CITY98) eau de la fontaine

local TownPlazaFx = {}

local LocalPlayer = Players.LocalPlayer

local STEP = 1 / 30
local RETRY = 1 -- (s) place pas encore répliquée : on réessaie
local FAR_PLAZA = 260
local FAR_CAROUSEL = 170
local FAR_SMALL = 110
-- (v9.8) vitesse du manège et des chevaux : FairRides (PLAZA_SPIN, CAROUSEL_BOB_*)

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
	local c = { Base = R0, Parts = {}, Locals = {}, Group = {}, Frames = {}, HorseBase = {}, HorsePhase = {}, HorseCF = {},
		Groups = {}, Seats = {}, SeatIndex = {}, SeatFrames = {}, SeatCheck = 0 }
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
	-- (v9.8 : emplacements et pose partagés avec le serveur : FairRides)
	local horseIndex = 0
	for _, s in ipairs(FairRides.CarouselSpots()) do
		local pos = s.Pos
		local base = s.Base
		if s.Carriage then
			carriage(function(name, size, loc, color, material, shape, className)
				rotor(name, size, base * loc, color, material, shape, className)
			end, horseIndex % 2 == 0 and PINK or Color3.fromRGB(190, 160, 240))
		else
			horseIndex += 1
			local k = horseIndex
			local hb = base * CFrame.new(0, FairRides.HORSE_Y, 0)
			c.HorseBase[k] = hb
			c.HorsePhase[k] = s.Phase
			c.HorseCF[k] = R0 * hb
			rotor("Pole", Vector3.new(7.6, 0.24, 0.24), CFrame.new(pos.X, 4.1, pos.Z) * VERTICAL, GOLD, M.Metal, Enum.PartType.Cylinder)
			horse(function(name, size, loc, color, material, shape, className)
				moving(k, name, size, loc, R0 * hb * loc, color, material, shape, className)
			end, HORSE_COLORS[(k - 1) % #HORSE_COLORS + 1], k)
		end
	end
	return c
end

-- (v9.8) sièges du serveur (TownFair) sur les chevaux : on les déplace
-- aussi localement, à la même pose -> l'avatar assis suit en douceur
local PLAZA_RIDE = { Kind = "PlazaCarousel" }
local function stepCarousel(c: any, now: number)
	local groups = c.Groups
	FairRides.Pose(PLAZA_RIDE :: any, now, groups)
	local rot = c.Base * groups[1]
	local horseCF = c.HorseCF
	for k = 1, #c.HorseBase do
		horseCF[k] = c.Base * groups[1 + k]
	end
	local frames, locals, group = c.Frames, c.Locals, c.Group
	for i = 1, #frames do
		local g = group[i]
		frames[i] = (g == 0 and rot or horseCF[g]) * locals[i]
	end
	workspace:BulkMoveTo(c.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	local seats, seatFrames, seatIndex = c.Seats, c.SeatFrames, c.SeatIndex
	if #seats > 0 then
		for i = 1, #seats do
			seatFrames[i] = c.Base * FairRides.SeatLocal("PlazaCarousel", seatIndex[i], groups)
		end
		workspace:BulkMoveTo(seats, seatFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- (v9.8) sièges du manège de la place (répliqués par le serveur, peut-être
-- plus tard que la place) : Plaza > Carousel > RideSeats > RideSeat
local function findCarouselSeats(c: any, plaza: Instance)
	table.clear(c.Seats)
	table.clear(c.SeatIndex)
	table.clear(c.SeatFrames)
	local model = plaza:FindFirstChild("Carousel")
	local folder = model and model:FindFirstChild("RideSeats")
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetChildren()) do
		local index = d:GetAttribute("SeatIndex")
		if d:IsA("Seat") and type(index) == "number" then
			table.insert(c.Seats, d)
			table.insert(c.SeatIndex, index)
		end
	end
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
-- Pigeons (v9.8, CITY98) : module TownPigeons ; fontaine : TownFountainFx
----------------------------------------------------------------------

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
		findCarouselSeats(s.Carousel, plaza)
		s.Plaza = plaza
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
	-- (v9.8, CITY98) pigeons 10x (TownPigeons) + fontaine animée (TownFountainFx)
	s.Pigeons = TownPigeons.Build(folder, plaza)
	local fountainBase = vec3Attr(plaza, "FxFountainBase")
	if fountainBase then
		s.Fountain = TownFountainFx.Build(folder, fountainBase)
	end
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

-- (v9.8) l'avatar local est-il assis sur le manège de la place ?
local function ridingCarousel(c: any): boolean
	local character = LocalPlayer and LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return seat ~= nil and table.find(c.Seats, seat) ~= nil
end

function TownPlazaFx.Step(dt: number)
	local s = state
	if not s then
		return
	end
	-- (v9.8) sur le manège : plateau, chevaux et sièges à CHAQUE image
	-- (fluide sous la caméra) ; sinon 30 fois / s au plus comme avant
	local riding = false
	local rc = s.Built and s.Carousel
	if rc then
		rc.SeatCheck -= dt
		if #rc.Seats == 0 and rc.SeatCheck <= 0 and s.Plaza then
			rc.SeatCheck = 1
			findCarouselSeats(rc, s.Plaza)
		end
		riding = ridingCarousel(rc)
		if riding then
			stepCarousel(rc, serverNow())
		end
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
		s.Carousel, s.Balloons, s.Pigeons, s.Fountain = nil, nil, nil, nil
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
	if c and not riding and (focus - c.Base.Position).Magnitude < FAR_CAROUSEL then
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
		TownPigeons.Step(p, elapsed, root and (root :: BasePart).Position or nil)
	end
	if s.Fountain and fromCenter < FAR_SMALL + 30 then
		TownFountainFx.Step(s.Fountain, serverNow())
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
