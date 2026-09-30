--[[
	DistrictParks (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DistrictParks

	🌳 Dopamine Town (v10, CITY10) : "PAS DE ZONE MORTE" dans la grande
	ville. Les lieux qui remplissent les espaces libres des quartiers, les
	cases nature (bois des collines, parc des sports, parc du sud) et les
	bouts de l'autoroute, construits côté CLIENT, en flux (TownStreetLife ;
	emplacements calculés par CityPlan) :
	  - "PocketPark"  : square de quartier (pelouse, allée en boucle, bancs,
	    arbres, massifs, fontaine à boire, lampadaires, promeneurs) ;
	  - "BasketCourt" : terrain de basket (bitume, lignes, 2 paniers,
	    grillage) avec 2 joueurs qui dribblent (ballon qui rebondit) ;
	  - "FootPitch"   : terrain de foot à 5 (gazon synthétique rayé, lignes,
	    buts avec filets, grillage, projecteurs éteints) ;
	  - "Tennis"      : 2 courts de tennis (terre battue / dur, filets) ;
	  - "Stadium"     : stade du parc des sports (pelouse rayée, piste
	    d'athlétisme rouge à couloirs, tribune couverte à gradins, tableau
	    d'affichage, projecteurs) ;
	  - "Grove"       : bosquet (4 à 6 arbres d'essences variées, sous-bois) ;
	  - "Meadow"      : prairie fleurie (herbes hautes, fleurs sauvages,
	    ruche, papillons immobiles) ;
	  - "Orchard"     : verger (pommiers en rangs, échelle, paniers) ;
	  - "Cabin"       : cabane forestière (rondins, toit, cheminée, tas de
	    bois, table de pique-nique) ;
	  - "ShopRow"     : rangée de 3 petites boutiques (pharmacie à croix
	    verte, coiffeur à enseigne tournante, fleuriste) ;
	  - "ParkingLot"  : parking (places tracées, bordures, horodateur,
	    arbres, voitures garées simples) ;
	  - "BusStation"  : gare routière du parc du sud (quais couverts,
	    horloge, tableau des départs, bus garé) ;
	  - "Lookout"     : belvédère au bout d'une route extérieure (plate-forme,
	    longue-vue, drapeau, table de pique-nique) ;
	  - "DistrictSign": panneau d'entrée d'un quartier (nom + emoji du
	    quartier : spot.Data.Text, couleur spot.Data.Style).
	Repère F : au sol, au centre de l'emprise, -Z = côté rue.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Greenery = require(ReplicatedStorage.Shared.Greenery)
local CityKit = require(script.Parent.CityKit)

local DistrictParks = {}

local M = CityKit.M
local rgb = CityKit.rgb
local Box, Part, Column, Wedge, Egg, Glow, Text = CityKit.Box, CityKit.Part, CityKit.Column, CityKit.Wedge, CityKit.Egg, CityKit.Glow, CityKit.Text
local hash = CityKit.Hash

local LAWN = rgb(108, 164, 86)
local PATH = rgb(214, 200, 176)
local WHITE = rgb(250, 250, 248)
local STEEL = rgb(150, 156, 164)
local IRON = rgb(46, 48, 56)
local WOOD = rgb(150, 104, 66)
local WOOD_D = rgb(104, 70, 44)
local WARM = rgb(255, 232, 186)
local ASPHALT = rgb(84, 86, 94)
local FLOWERS = { rgb(255, 120, 170), rgb(255, 200, 70), rgb(190, 140, 255), rgb(255, 150, 100), rgb(250, 250, 250), rgb(255, 90, 110), rgb(120, 170, 255) }
local SPECIES = { "Oak", "Maple", "Birch", "Cherry", "Poplar", "Fir", "Round" }

DistrictParks.FOOT = {
	PocketPark = Vector2.new(44, 44),
	BasketCourt = Vector2.new(34, 22),
	FootPitch = Vector2.new(50, 32),
	Tennis = Vector2.new(46, 40),
	Stadium = Vector2.new(150, 110),
	Grove = Vector2.new(34, 34),
	Meadow = Vector2.new(40, 40),
	Orchard = Vector2.new(46, 40),
	Cabin = Vector2.new(28, 24),
	ShopRow = Vector2.new(48, 18),
	ParkingLot = Vector2.new(48, 30),
	BusStation = Vector2.new(70, 40),
	Lookout = Vector2.new(30, 24),
	DistrictSign = Vector2.new(10, 4),
}

local function tree(m: Model, F: CFrame, x: number, z: number, h: number, seed: number, species: string, tier: number?)
	pcall(Greenery.Tree, m, (F * CFrame.new(x, 0, z)).Position, h, seed, species, tier or 1)
end

local function lawn(m: Model, F: CFrame, w: number, d: number, color: Color3?)
	Box(m, "Lawn", F, -w / 2, w / 2, -0.2, 0.06, -d / 2, d / 2, color or LAWN, M.Grass)
end

----------------------------------------------------------------------
-- Square, sports
----------------------------------------------------------------------

local function buildPocketPark(m: Model, F: CFrame, seed: number)
	local S = 42
	lawn(m, F, S, S)
	-- allée en boucle (8 dalles en anneau) + entrée côté rue
	local n = 12
	for i = 0, n - 1 do
		local a0, a1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
		local r = 12
		local p0 = Vector3.new(math.cos(a0) * r, 0, math.sin(a0) * r)
		local p1 = Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r)
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude + 1.2
		Part(m, "Path", Vector3.new(3.4, 0.12, len), F * CFrame.lookAt(mid + Vector3.new(0, 0.1 + (i % 2) * 0.03, 0), p1 + Vector3.new(0, 0.1 + (i % 2) * 0.03, 0)), PATH, M.Pavement)
	end
	Box(m, "PathIn", F, -1.7, 1.7, 0.06, 0.2, -S / 2, -13.4, PATH, M.Pavement)
	-- massif central + arbres + bancs
	Column(m, "BedRing", F, 0, 0, 0, 0.7, 9, rgb(190, 184, 176), M.Concrete)
	Column(m, "BedSoil", F, 0, 0, 0.7, 0.8, 8.2, rgb(96, 70, 52), M.Ground)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		Egg(m, "Bloom", F * CFrame.new(math.cos(a) * 2.8, 1.2, math.sin(a) * 2.8), Vector3.new(1.1, 0.8, 1.1), CityKit.Pick(FLOWERS, seed, k), M.SmoothPlastic)
	end
	tree(m, F * CFrame.new(0, 0.8, 0), 0, 0, 11, seed + 1, "Cherry")
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		tree(m, F, math.cos(a) * 18, math.sin(a) * 18, 14 + hash(seed, k) * 5, seed + k * 7, CityKit.Pick(SPECIES, seed, k))
		local b = k * math.pi / 2
		if k ~= 3 then
			CityKit.Bench(m, F * CFrame.new(math.cos(b) * 15, 0.06, math.sin(b) * 15) * CFrame.Angles(0, -b + math.pi / 2, 0), 4.6)
		end
		CityKit.StreetLamp(m, F * CFrame.new(math.cos(a) * 12.5, 0.06, math.sin(a) * 12.5) * CFrame.Angles(0, -a - math.pi / 2, 0), 10)
	end
	-- fontaine à boire, poubelle
	Column(m, "DrinkFountain", F, 4, -15, 0, 3.2, 0.8, rgb(40, 80, 60), M.Metal, true)
	Egg(m, "DrinkBowl", F * CFrame.new(4, 3.3, -15), Vector3.new(1.6, 0.5, 1.6), rgb(40, 80, 60), M.Metal)
	CityKit.Bin(m, F * CFrame.new(-4, 0.06, -15))
	-- promeneurs
	local p1 = CityKit.Npc(m, "elder", seed * 3 + 1, F * CFrame.new(15, 0.06 + 0.05, 0.1) * CFrame.Angles(0, math.pi / 2, 0), "none", false)
	CityKit.Idle(p1, "sit", 1)
	local p2 = CityKit.Npc(m, "jogger", seed * 3 + 2, F * CFrame.new(-8, 0.2, -9) * CFrame.Angles(0, 2.4, 0), "none", true)
	CityKit.Idle(p2, "idle", 3)
end

local function fence(m: Model, F: CFrame, w: number, d: number, h: number)
	for _, sz in ipairs({ -1, 1 }) do
		local mesh = Box(m, "Mesh", F, -w / 2, w / 2, 0, h, sz * d / 2 - 0.03, sz * d / 2 + 0.03, STEEL, M.DiamondPlate, true)
		mesh.Transparency = 0.65
	end
	for _, sx in ipairs({ -1, 1 }) do
		local mesh = Box(m, "Mesh", F, sx * w / 2 - 0.03, sx * w / 2 + 0.03, 0, h, -d / 2 + 0.04, d / 2 - 0.04, STEEL, M.DiamondPlate, true)
		mesh.Transparency = 0.65
	end
	local posts = {}
	for i = 0, math.floor(w / 8) do
		local x = -w / 2 + i * w / math.floor(w / 8)
		table.insert(posts, { x, -d / 2 })
		table.insert(posts, { x, d / 2 })
	end
	for i = 1, math.floor(d / 8) - 1 do
		local z = -d / 2 + i * d / math.floor(d / 8)
		table.insert(posts, { -w / 2, z })
		table.insert(posts, { w / 2, z })
	end
	for _, p in ipairs(posts) do
		Column(m, "FencePost", F, p[1], p[2], 0, h + 0.2, 0.26, rgb(60, 110, 80), M.Metal, true)
	end
end

local function hoop(m: Model, F: CFrame)
	Column(m, "HoopPole", F, 0, 0, 0, 11, 0.6, rgb(40, 60, 110), M.Metal, true)
	Box(m, "HoopArm", F, -0.2, 0.2, 10.4, 10.8, -2.6, 0, rgb(40, 60, 110), M.Metal)
	local board = Box(m, "Backboard", F, -2.6, 2.6, 9.2, 12.4, -2.8, -2.64, WHITE, M.Glass)
	board.Transparency = 0.2
	Box(m, "BoardSquare", F, -0.9, 0.9, 9.6, 10.8, -2.86, -2.8, rgb(220, 60, 40), M.SmoothPlastic)
	Part(m, "Rim", Vector3.new(0.12, 1.8, 1.8), F * CFrame.new(0, 9.4, -3.8) * CityKit.UPRIGHT, rgb(240, 110, 30), M.Metal, "Cyl")
	local net = Part(m, "Net", Vector3.new(1.2, 1.5, 1.5), F * CFrame.new(0, 8.7, -3.8) * CityKit.UPRIGHT, WHITE, M.Fabric, "Cyl")
	net.Transparency = 0.5
end

local function buildBasketCourt(m: Model, F: CFrame, seed: number)
	local W, D = 32, 20
	Box(m, "Court", F, -W / 2, W / 2, -0.1, 0.2, -D / 2, D / 2, rgb(70, 110, 150), M.Concrete, true)
	Box(m, "CourtInner", F, -W / 2 + 1.2, W / 2 - 1.2, 0.2, 0.24, -D / 2 + 1.2, D / 2 - 1.2, rgb(200, 90, 60), M.Concrete)
	Box(m, "Midline", F, -0.12, 0.12, 0.24, 0.3, -D / 2 + 1.2, D / 2 - 1.2, WHITE, M.SmoothPlastic)
	Column(m, "CenterCircle", F, 0, 0, 0.24, 0.28, 6, WHITE, M.SmoothPlastic)
	Column(m, "CenterDot", F, 0, 0, 0.28, 0.35, 5.5, rgb(200, 90, 60), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "Key", F, sx * (W / 2 - 1.2), sx * (W / 2 - 7.2), 0.24, 0.28, -2.6, 2.6, rgb(70, 110, 150), M.SmoothPlastic)
		hoop(m, F * CFrame.new(sx * (W / 2 + 0.4), 0.2, 0) * CFrame.Angles(0, sx > 0 and math.pi / 2 or -math.pi / 2, 0))
	end
	fence(m, F * CFrame.new(0, 0.2, 0), W + 1, D + 1, 9)
	-- 2 joueurs, ballon qui rebondit entre eux
	local a = CityKit.Npc(m, "jogger", seed * 3 + 1, F * CFrame.new(-4, 0.2, 1) * CFrame.Angles(0, -math.pi / 2, 0), "none", true)
	local b = CityKit.Npc(m, "kid", seed * 3 + 2, F * CFrame.new(4, 0.2, -1) * CFrame.Angles(0, math.pi / 2, 0), "none", true)
	local ball = Part(m, "Basketball", Vector3.new(0.9, 0.9, 0.9), F * CFrame.new(0, 1, 0), rgb(230, 110, 40), M.SmoothPlastic, "Ball")
	CityKit.Actor(m, F.Position, function(t: number)
		local cycle = (t * 0.5) % 2
		local dir = cycle < 1 and 1 or -1
		local u = cycle % 1
		local x = -3.4 * dir + 6.8 * dir * u
		local bounce = math.abs(math.sin(u * math.pi * 3)) * 2.6
		ball.CFrame = F * CFrame.new(x, 0.65 + bounce, (dir > 0 and 1 or -1) * (0.5 - u))
		if a then
			CityKit.Animate(a, dir > 0 and u < 0.2 and "wave" or "idle", t)
		end
		if b then
			CityKit.Animate(b, dir < 0 and u < 0.2 and "wave" or "idle", t + 1)
		end
	end, seed)
end

local function goal(m: Model, G: CFrame)
	for _, sx in ipairs({ -3, 3 }) do
		Column(m, "GoalPost", G, sx, 0, 0, 6.4, 0.3, WHITE, M.Metal, true)
	end
	Box(m, "GoalBar", G, -3.15, 3.15, 6.25, 6.55, -0.15, 0.15, WHITE, M.Metal)
	local net = Box(m, "GoalNet", G, -3, 3, 0, 6.3, 2.4, 2.46, WHITE, M.Fabric)
	net.Transparency = 0.6
	for _, sx in ipairs({ -3, 3 }) do
		local side = Box(m, "GoalNetSide", G, sx - 0.03, sx + 0.03, 0, 6.3, 0.15, 2.4, WHITE, M.Fabric)
		side.Transparency = 0.6
	end
	local top = Box(m, "GoalNetTop", G, -3, 3, 6.27, 6.33, 0.15, 2.4, WHITE, M.Fabric)
	top.Transparency = 0.6
end

local function buildFootPitch(m: Model, F: CFrame, seed: number)
	local W, D = 48, 30
	Box(m, "Turf", F, -W / 2, W / 2, -0.1, 0.16, -D / 2, D / 2, rgb(70, 150, 70), M.Grass, true)
	for i = 0, 5 do
		if i % 2 == 0 then
			local x = -W / 2 + 2 + i * (W - 4) / 6
			Box(m, "TurfStripe", F, x, x + (W - 4) / 6, 0.16, 0.19, -D / 2 + 2, D / 2 - 2, rgb(84, 168, 80), M.Grass)
		end
	end
	local function lineZ(x: number)
		Box(m, "Line", F, x - 0.15, x + 0.15, 0.19, 0.24, -D / 2 + 2, D / 2 - 2, WHITE, M.SmoothPlastic)
	end
	lineZ(-W / 2 + 2)
	lineZ(W / 2 - 2)
	lineZ(0)
	for _, sz in ipairs({ -1, 1 }) do
		Box(m, "Line", F, -W / 2 + 2, W / 2 - 2, 0.19, 0.24, sz * (D / 2 - 2) - 0.15, sz * (D / 2 - 2) + 0.15, WHITE, M.SmoothPlastic)
	end
	-- (rond central au-dessus de la ligne médiane : 0,28 / 0,31, jamais confondus)
	Column(m, "CenterCircle", F, 0, 0, 0.19, 0.28, 8, WHITE, M.SmoothPlastic)
	Column(m, "CenterInner", F, 0, 0, 0.28, 0.31, 7.4, rgb(70, 150, 70), M.Grass)
	for _, sx in ipairs({ -1, 1 }) do
		goal(m, F * CFrame.new(sx * (W / 2 - 2), 0.16, 0) * CFrame.Angles(0, sx > 0 and -math.pi / 2 or math.pi / 2, 0))
	end
	fence(m, F * CFrame.new(0, 0.16, 0), W + 1, D + 1, 8)
	-- projecteurs (éteints de jour, lentilles "NightGlow")
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W / 2 + 2)
		Column(m, "FloodPole", F, x, -D / 2 - 2, 0, 20, 0.6, STEEL, M.Metal, true)
		Box(m, "FloodHead", F, x - 1.4, x + 1.4, 19.4, 21, -D / 2 - 2.6, -D / 2 - 1.4, IRON, M.Metal)
		Glow(Box(m, "FloodLens", F, x - 1.2, x + 1.2, 19.6, 20.8, -D / 2 - 1.4, -D / 2 - 1.34, rgb(236, 240, 250), M.Glass))
	end
	-- un gardien, un tireur, un ballon
	local keeper = CityKit.Npc(m, "kid", seed * 5 + 1, F * CFrame.new(W / 2 - 4, 0.16, 0) * CFrame.Angles(0, math.pi / 2, 0), "none", true)
	CityKit.Idle(keeper, "idle", 1)
	local striker = CityKit.Npc(m, "jogger", seed * 5 + 2, F * CFrame.new(W / 2 - 14, 0.16, 2) * CFrame.Angles(0, -math.pi / 2, 0), "none", true)
	local ball = Part(m, "Football", Vector3.new(0.9, 0.9, 0.9), F * CFrame.new(W / 2 - 12.8, 0.6, 2), WHITE, M.SmoothPlastic, "Ball")
	CityKit.Actor(m, F.Position, function(t: number)
		local u = (t * 0.35) % 1
		local x = W / 2 - 12.8 + u * 8.4
		ball.CFrame = F * CFrame.new(x, 0.61 + math.sin(u * math.pi) * 2.2, 2 - u * 1.6)
		if striker then
			CityKit.Animate(striker, u < 0.15 and "wave" or "idle", t)
		end
	end, seed)
end

local function buildTennis(m: Model, F: CFrame, seed: number)
	local W, D = 44, 38
	Box(m, "TennisBase", F, -W / 2, W / 2, -0.1, 0.18, -D / 2, D / 2, rgb(70, 120, 90), M.Concrete, true)
	for i, sz in ipairs({ -1, 1 }) do
		local C = F * CFrame.new(0, 0.18, sz * D / 4)
		local clay = i == 1
		Box(m, "Court", C, -18, 18, 0, 0.04, -8, 8, clay and rgb(196, 110, 70) or rgb(60, 110, 170), clay and M.Sand or M.Concrete)
		for _, z in ipairs({ -8, 8, -6.2, 6.2 }) do
			Box(m, "TLine", C, -18, 18, 0.04, 0.08, z - 0.1, z + 0.1, WHITE, M.SmoothPlastic)
		end
		for _, x in ipairs({ -18, 18, -10, 10 }) do
			Box(m, "TLine", C, x - 0.1, x + 0.1, 0.04, 0.08, -8, 8, WHITE, M.SmoothPlastic)
		end
		Box(m, "TLine", C, -10, 10, 0.04, 0.08, -0.1, 0.1, WHITE, M.SmoothPlastic)
		-- filet
		for _, z in ipairs({ -8.6, 8.6 }) do
			Column(m, "NetPost", C, 0, z, 0, 3.4, 0.24, IRON, M.Metal)
		end
		local net = Box(m, "TennisNet", C, -0.03, 0.03, 0.2, 3, -8.6, 8.6, rgb(30, 30, 34), M.Fabric)
		net.Transparency = 0.45
		Box(m, "NetTape", C, -0.06, 0.06, 3, 3.24, -8.6, 8.6, WHITE, M.Fabric)
	end
	fence(m, F * CFrame.new(0, 0.18, 0), W, D, 10)
	local p = CityKit.Npc(m, "jogger", seed * 3 + 1, F * CFrame.new(-14, 0.22, -D / 4) * CFrame.Angles(0, -math.pi / 2, 0), "none", true)
	CityKit.Idle(p, "wave", 0.5)
	local q = CityKit.Npc(m, "pedestrian", seed * 3 + 2, F * CFrame.new(14, 0.22, -D / 4 + 2) * CFrame.Angles(0, math.pi / 2, 0), "none", true)
	CityKit.Idle(q, "wave", 2.1)
end

local function buildStadium(m: Model, F: CFrame, seed: number)
	local TW, TD = 140, 96 -- piste
	-- piste rouge (fond) + pelouse au centre (ovale approximé : rectangle + 2 bouts ronds)
	Box(m, "Track", F, -TW / 2 + TD / 2, TW / 2 - TD / 2, -0.1, 0.2, -TD / 2, TD / 2, rgb(190, 80, 60), M.Rubber, true)
	for _, sx in ipairs({ -1, 1 }) do
		Part(m, "TrackEnd", Vector3.new(0.3, TD, TD), F * CFrame.new(sx * (TW / 2 - TD / 2), 0.05, 0) * CityKit.UPRIGHT, rgb(190, 80, 60), M.Rubber, "Cyl")
	end
	local IW, ID = TW - 24, TD - 24
	Box(m, "Pitch", F, -IW / 2 + ID / 2, IW / 2 - ID / 2, 0.2, 0.26, -ID / 2, ID / 2, rgb(80, 160, 76), M.Grass, true)
	for _, sx in ipairs({ -1, 1 }) do
		Part(m, "PitchEnd", Vector3.new(0.3, ID, ID), F * CFrame.new(sx * (IW / 2 - ID / 2), 0.11, 0) * CityKit.UPRIGHT, rgb(80, 160, 76), M.Grass, "Cyl")
	end
	-- couloirs (lignes blanches) sur les lignes droites
	for k = 1, 5 do
		for _, sz in ipairs({ -1, 1 }) do
			local z = sz * (ID / 2 + k * 2)
			Box(m, "LaneLine", F, -TW / 2 + TD / 2, TW / 2 - TD / 2, 0.2, 0.24, z - 0.1, z + 0.1, WHITE, M.SmoothPlastic)
		end
	end
	-- terrain de foot (lignes) + buts
	local PW, PD = 80, 52
	for _, sz in ipairs({ -1, 1 }) do
		Box(m, "PLine", F, -PW / 2, PW / 2, 0.26, 0.3, sz * PD / 2 - 0.15, sz * PD / 2 + 0.15, WHITE, M.SmoothPlastic)
	end
	for _, x in ipairs({ -PW / 2, 0, PW / 2 }) do
		Box(m, "PLine", F, x - 0.15, x + 0.15, 0.26, 0.3, -PD / 2, PD / 2, WHITE, M.SmoothPlastic)
	end
	for _, sx in ipairs({ -1, 1 }) do
		goal(m, F * CFrame.new(sx * PW / 2, 0.26, 0) * CFrame.Angles(0, sx > 0 and -math.pi / 2 or math.pi / 2, 0))
	end
	-- tribune couverte (côté +Z) : gradins + toit en porte-à-faux
	local S = F * CFrame.new(0, 0, TD / 2 + 8)
	for k = 0, 7 do
		Box(m, "Terrace", S, -40, 40, 0, 1.2 + k * 1.4, -4 + k * 1.8, -2.2 + k * 1.8, rgb(200, 200, 206), M.Concrete, true)
		-- sièges colorés (bandes)
		Box(m, "Seats", S, -39, 39, 1.2 + k * 1.4, 1.7 + k * 1.4, -3.4 + k * 1.8, -2.8 + k * 1.8, k % 2 == 0 and rgb(40, 110, 200) or rgb(230, 60, 90), M.SmoothPlastic)
	end
	Box(m, "StandBack", S, -40, 40, 0, 16, 10.4, 11.2, rgb(180, 180, 186), M.Concrete, true)
	Box(m, "StandRoof", S, -42, 42, 16, 16.8, -8, 11.2, rgb(90, 94, 104), M.Metal)
	for i = 0, 4 do
		local x = -40 + i * 20
		Box(m, "RoofColumn", S, x - 0.4, x + 0.4, 0, 16, 10.4, 11.2, STEEL, M.Metal, true)
	end
	local sign = Box(m, "StadiumSign", S, -18, 18, 16.8, 20, 10.4, 11, rgb(40, 110, 200), M.SmoothPlastic)
	Text(sign, Enum.NormalId.Front, "🏟️ " .. Locale.T("Dopamine Stadium"), WHITE, nil, Enum.Font.GothamBlack, 400)
	-- quelques supporters
	for k = 0, 5 do
		local fan = CityKit.Npc(m, CityKit.Pick({ "pedestrian", "kid", "shopper", "jogger" }, seed, k), seed * 41 + k, S * CFrame.new(-20 + k * 7, 1.2 + (k % 3 + 1) * 1.4, -3.6 + (k % 3 + 1) * 1.8 + 0.4) * CFrame.Angles(0, math.pi, 0), "none", false)
		CityKit.Idle(fan, k % 2 == 0 and "wave" or "sit", k * 0.9)
	end
	-- tableau d'affichage (côté -X)
	local B = F * CFrame.new(-TW / 2 - 6, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	for _, x in ipairs({ -6, 6 }) do
		Column(m, "BoardLeg", B, x, 0, 0, 14, 0.8, STEEL, M.Metal, true)
	end
	local board = Box(m, "Scoreboard", B, -8, 8, 12, 20, -0.6, 0.6, rgb(20, 20, 26), M.SmoothPlastic)
	Glow(board)
	Text(board, Enum.NormalId.Back, "DOPA 2 - 1 FC CLIC", rgb(255, 200, 60), rgb(20, 20, 26), Enum.Font.Arcade, 400)
	-- 4 grands projecteurs
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = sx * (TW / 2 + 4), sz * (TD / 2 + 4)
			Column(m, "MastPole", F, x, z, 0, 34, 1.2, STEEL, M.Metal, true)
			Box(m, "MastHead", F, x - 3, x + 3, 33, 38, z - 0.8, z + 0.8, IRON, M.Metal)
			Glow(Box(m, "MastLamps", F, x - 2.6, x + 2.6, 33.4, 37.6, z - sz * 0.86, z - sz * 0.8, rgb(236, 240, 250), M.Glass))
		end
	end
end

----------------------------------------------------------------------
-- Nature : bosquet, prairie, verger, cabane
----------------------------------------------------------------------

local function buildGrove(m: Model, F: CFrame, seed: number)
	local n = 4 + math.floor(hash(seed, 1) * 3)
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2 + hash(seed, i) * 0.8
		local r = 5 + hash(seed, i + 10) * 9
		local sp = CityKit.Pick({ "Oak", "Fir", "Birch", "Maple", "Fir", "Poplar" }, seed, i)
		tree(m, F, math.cos(a) * r, math.sin(a) * r, 14 + hash(seed, i + 20) * 10, seed * 7 + i, sp)
	end
	-- sous-bois : buissons, fougères, souche, rocher
	for i = 0, 4 do
		local a = hash(seed, i + 30) * math.pi * 2
		local r = 3 + hash(seed, i + 40) * 12
		Egg(m, "Bush", F * CFrame.new(math.cos(a) * r, 0.7, math.sin(a) * r), Vector3.new(3, 1.8, 2.6), rgb(64, 120, 60):Lerp(rgb(90, 140, 70), hash(seed, i)), M.Grass)
	end
	if hash(seed, 50) < 0.5 then
		Column(m, "Stump", F, 2, -3, 0, 1.2, 1.8, WOOD_D, M.Wood)
	else
		Egg(m, "Rock", F * CFrame.new(-2, 0.6, 3), Vector3.new(3.4, 2, 2.6), rgb(140, 138, 134), M.Slate)
	end
end

local function buildMeadow(m: Model, F: CFrame, seed: number)
	Egg(m, "Meadow", F * CFrame.new(0, -0.1, 0), Vector3.new(38, 0.5, 38), rgb(122, 170, 90), M.Grass)
	for i = 0, 22 do
		local x, z = (hash(seed, i) - 0.5) * 32, (hash(seed, i + 50) - 0.5) * 32
		Egg(m, "TallGrass", F * CFrame.new(x, 0.8, z), Vector3.new(1.4, 1.6, 1.4), rgb(110, 160, 80):Lerp(rgb(170, 180, 90), hash(seed, i + 9)), M.Grass)
		if i % 2 == 0 then
			Egg(m, "Wildflower", F * CFrame.new(x + 0.5, 1.5, z), Vector3.new(0.6, 0.4, 0.6), CityKit.Pick(FLOWERS, seed, i), M.SmoothPlastic)
		end
	end
	-- ruche en bois sur pieds
	local H = F * CFrame.new(10, 0, -8)
	for _, x in ipairs({ -0.8, 0.8 }) do
		Box(m, "HiveLeg", H, x - 0.15, x + 0.15, 0, 1.4, -0.8, 0.8, WOOD_D, M.Wood)
	end
	for k = 0, 2 do
		Box(m, "HiveBox", H, -1.3, 1.3, 1.4 + k * 1.1, 2.4 + k * 1.1, -1.1, 1.1, k % 2 == 0 and rgb(250, 220, 120) or rgb(240, 200, 90), M.WoodPlanks)
	end
	Box(m, "HiveRoof", H, -1.5, 1.5, 4.7, 5.1, -1.3, 1.3, rgb(160, 160, 166), M.Metal)
	-- un épouvantail / panneau "prairie fleurie"
	local sign = Box(m, "MeadowSign", F, -2, 2, 2, 3.6, -17.2, -17, WOOD, M.Wood)
	Text(sign, Enum.NormalId.Front, "🌼 " .. Locale.T("Wildflower meadow"), rgb(60, 40, 20), rgb(250, 240, 214), Enum.Font.Fantasy, 60)
	Column(m, "SignPost", F, 0, -17.1, 0, 2.2, 0.24, WOOD_D, M.Wood)
end

local function buildOrchard(m: Model, F: CFrame, seed: number)
	lawn(m, F, 44, 38, rgb(116, 166, 84))
	for i = 0, 3 do
		for j = 0, 2 do
			local x, z = -15 + i * 10, -11 + j * 11
			tree(m, F, x, z, 9 + hash(seed, i * 3 + j) * 2, seed * 3 + i * 7 + j, "Fruit")
		end
	end
	local L = F * CFrame.new(-10, 0.06, -5.5)
	CityKit.Rod(m, "LadderRail", (L * CFrame.new(-0.6, 0, 0)).Position, (L * CFrame.new(-0.6, 7, 1.6)).Position, 0.18, WOOD, M.Wood)
	CityKit.Rod(m, "LadderRail", (L * CFrame.new(0.6, 0, 0)).Position, (L * CFrame.new(0.6, 7, 1.6)).Position, 0.18, WOOD, M.Wood)
	for k = 1, 5 do
		local f = k / 6
		Box(m, "Rung", L * CFrame.new(0, 7 * f, 1.6 * f), -0.6, 0.6, -0.08, 0.08, -0.08, 0.08, WOOD, M.Wood)
	end
	for k = 0, 2 do
		local B = F * CFrame.new(-4 + k * 2.2, 0.06, -6.5)
		Column(m, "Basket", B, 0, 0, 0, 1.2, 1.8, rgb(190, 150, 90), M.Fabric)
		for q = 0, 2 do
			CityKit.Ball(m, "Apple", (B * CFrame.new((q - 1) * 0.45, 1.3, 0)).Position, 0.5, rgb(210, 40, 40), M.SmoothPlastic)
		end
	end
	local picker = CityKit.Npc(m, "elder", seed * 7 + 5, F * CFrame.new(-7, 0.06, -7.5) * CFrame.Angles(0, 0.6, 0), "none", true)
	CityKit.Idle(picker, "wave", 1.2)
end

local function buildCabin(m: Model, F: CFrame, seed: number)
	local W, D, H = 14, 10, 8
	local C = F * CFrame.new(0, 0, 3)
	-- rondins empilés
	for k = 0, 6 do
		local y = 0.6 + k * 1.05
		for _, sz in ipairs({ -1, 1 }) do
			Part(m, "Log", Vector3.new(W + 1.2, 1.1, 1.1), C * CFrame.new(0, y, sz * D / 2), rgb(130, 90, 58):Lerp(rgb(150, 104, 66), (k % 2) * 0.6), M.Wood, "Cyl", true)
		end
		for _, sx in ipairs({ -1, 1 }) do
			Part(m, "Log", Vector3.new(D + 1.2, 1.1, 1.1), C * CFrame.new(sx * W / 2, y + 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0), rgb(130, 90, 58):Lerp(rgb(150, 104, 66), (k % 2) * 0.6), M.Wood, "Cyl", true)
		end
	end
	Box(m, "CabinCore", C, -W / 2 + 0.3, W / 2 - 0.3, 0, H, -D / 2 + 0.3, D / 2 - 0.3, rgb(110, 76, 50), M.Wood, true)
	for _, sz in ipairs({ -1, 1 }) do
		Wedge(m, "CabinRoof", Vector3.new(W + 2.4, 4, D / 2 + 1.6), C * CFrame.new(0, H + 2, sz * (D / 4 + 0.8)) * CFrame.Angles(0, sz > 0 and math.pi or 0, 0), rgb(70, 90, 60), M.WoodPlanks)
	end
	Box(m, "CabinChimney", C, W / 2 - 3, W / 2 - 1.4, H - 1, H + 6, 1, 2.6, rgb(140, 136, 130), M.Cobblestone)
	Box(m, "CabinDoor", C, -1.4, 1.4, 0.6, 7.2, -D / 2 - 0.7, -D / 2 - 0.5, WOOD_D, M.WoodPlanks)
	Glow(Box(m, "CabinWindow", C, 2.6, 5, 3, 5.6, -D / 2 - 0.7, -D / 2 - 0.5, WARM, M.Glass))
	Box(m, "Porch", C, -W / 2, W / 2, 0, 0.6, -D / 2 - 3.4, -D / 2 - 0.5, WOOD, M.WoodPlanks, true)
	-- tas de bois, table de pique-nique, feu de camp éteint
	for k = 0, 5 do
		Part(m, "Firewood", Vector3.new(2.6, 0.6, 0.6), C * CFrame.new(-W / 2 - 1.5, 0.3 + math.floor(k / 3) * 0.55, -2 + (k % 3) * 0.65) * CFrame.Angles(0, math.pi / 2, 0), rgb(150, 104, 66), M.Wood, "Cyl")
	end
	local T = F * CFrame.new(6, 0, -8)
	Box(m, "PicnicTop", T, -3, 3, 2.2, 2.5, -1.2, 1.2, WOOD, M.WoodPlanks, true)
	for _, z in ipairs({ -2.1, 2.1 }) do
		Box(m, "PicnicSeat", T, -3, 3, 1.3, 1.55, z - 0.5, z + 0.5, WOOD, M.WoodPlanks, true)
	end
	for _, x in ipairs({ -2.3, 2.3 }) do
		Box(m, "PicnicLeg", T, x - 0.18, x + 0.18, 0, 2.2, -2.4, 2.4, WOOD_D, M.Wood)
	end
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		Egg(m, "FireStone", F * CFrame.new(-5 + math.cos(a) * 1.6, 0.3, -8 + math.sin(a) * 1.6), Vector3.new(0.9, 0.6, 0.8), rgb(130, 128, 124), M.Slate)
	end
	tree(m, F, -10, 8, 18, seed + 3, "Fir")
	tree(m, F, 10, 9, 16, seed + 4, "Fir")
end

----------------------------------------------------------------------
-- Ville : boutiques, parking, gare routière, belvédère, panneaux
----------------------------------------------------------------------

local function shop(m: Model, S: CFrame, w: number, color: Color3, label: string, seed: number)
	Box(m, "ShopBody", S, -w / 2, w / 2, 0, 12, -5, 5, color, M.Plaster, true)
	Box(m, "ShopCornice", S, -w / 2 - 0.3, w / 2 + 0.3, 12, 12.8, -5.3, 5.3, rgb(230, 226, 216), M.Concrete)
	Box(m, "ShopFront", S, -w / 2 + 0.4, w / 2 - 0.4, 0, 8, -5.2, -5, rgb(40, 44, 50), M.Metal)
	Glow(Box(m, "ShopGlass", S, -w / 2 + 0.8, w / 2 - 3.6, 1, 7.4, -5.26, -5.2, WARM, M.Glass))
	Box(m, "ShopDoor", S, w / 2 - 3.2, w / 2 - 0.8, 0, 7.4, -5.26, -5.2, rgb(60, 64, 70), M.Metal)
	local sign = Box(m, "ShopSign", S, -w / 2 + 0.6, w / 2 - 0.6, 8.4, 10.2, -5.4, -5, WHITE, M.SmoothPlastic)
	Text(sign, Enum.NormalId.Front, label, color:Lerp(Color3.new(0, 0, 0), 0.4), nil, Enum.Font.GothamBold, 120)
	local _ = seed
end

local function buildShopRow(m: Model, F: CFrame, seed: number)
	local B = F * CFrame.new(0, 0, 3)
	shop(m, B * CFrame.new(-15, 0, 0), 15.6, rgb(220, 240, 226), "✚ " .. Locale.T("Pharmacy"), seed)
	shop(m, B * CFrame.new(0, 0, 0), 14, rgb(236, 226, 244), "✂️ " .. Locale.T("Hair salon"), seed + 1)
	shop(m, B * CFrame.new(15, 0, 0), 15.6, rgb(250, 232, 236), "💐 " .. Locale.T("Florist"), seed + 2)
	-- croix verte de pharmacie (lumineuse)
	local C = B * CFrame.new(-15, 10.6, -6.2)
	Glow(Box(m, "PharmaCross", C, -0.4, 0.4, -1.3, 1.3, -0.2, 0.2, rgb(60, 220, 110), M.SmoothPlastic))
	Glow(Box(m, "PharmaCross", C, -1.3, -0.4, -0.4, 0.4, -0.2, 0.2, rgb(60, 220, 110), M.SmoothPlastic))
	Glow(Box(m, "PharmaCross", C, 0.4, 1.3, -0.4, 0.4, -0.2, 0.2, rgb(60, 220, 110), M.SmoothPlastic))
	Box(m, "CrossArm", B * CFrame.new(-15, 0, 0), -0.1, 0.1, 10.5, 10.7, -6.1, -5, IRON, M.Metal)
	-- enseigne tournante du coiffeur (bandes) : tourne lentement
	local pole = Part(m, "BarberPole", Vector3.new(2.4, 0.7, 0.7), B * CFrame.new(6, 5, -5.8) * CityKit.UPRIGHT, WHITE, M.Glass, "Cyl")
	local stripes = {}
	for k = 0, 2 do
		local s = Part(m, "BarberStripe", Vector3.new(0.35, 0.74, 0.74), B * CFrame.new(6, 4.2 + k * 0.8, -5.8) * CityKit.UPRIGHT, rgb(220, 40, 50), M.SmoothPlastic, "Cyl")
		table.insert(stripes, s)
	end
	local _ = pole
	local base = B * CFrame.new(6, 0, -5.8)
	CityKit.Actor(m, base.Position, function(t: number)
		for k, s in ipairs(stripes) do
			local y = 4.2 + ((k - 1) * 0.8 + t * 0.6) % 2.4 - 0.4
			s.CFrame = base * CFrame.new(0, y + 0.4, 0) * CityKit.UPRIGHT
		end
	end, seed)
	-- étal du fleuriste
	for k = 0, 3 do
		local P = B * CFrame.new(11 + k * 1.8, 0, -6.6)
		Column(m, "FlowerBucket", P, 0, 0, 0, 1.4, 1.2, rgb(90, 94, 100), M.Metal)
		Egg(m, "Bouquet", P * CFrame.new(0, 1.9, 0), Vector3.new(1.3, 1.2, 1.3), CityKit.Pick(FLOWERS, seed, k), M.SmoothPlastic)
	end
	local florist = CityKit.Npc(m, "salesperson", seed * 3 + 9, B * CFrame.new(14, 0, -8.2) * CFrame.Angles(0, math.pi, 0), "none", true)
	CityKit.Idle(florist, "talk", 2)
end

local function parkedCar(m: Model, C: CFrame, color: Color3)
	Box(m, "CarBody", C, -2.3, 2.3, 0.8, 2.8, -4.8, 4.8, color, M.SmoothPlastic, true)
	Box(m, "CarCabin", C, -2, 2, 2.8, 4.4, -2.2, 2.4, color:Lerp(Color3.new(1, 1, 1), 0.05), M.SmoothPlastic)
	Box(m, "CarGlass", C, -2.05, 2.05, 3, 4.2, -2.1, 2.3, rgb(60, 80, 100), M.Glass)
	for _, x in ipairs({ -2.2, 2.2 }) do
		for _, z in ipairs({ -3.2, 3.2 }) do
			Part(m, "CarWheel", Vector3.new(0.7, 1.8, 1.8), C * CFrame.new(x, 0.9, z), rgb(30, 30, 34), M.Rubber, "Cyl")
		end
	end
	Glow(Box(m, "CarLights", C, -1.9, 1.9, 1.8, 2.3, -4.86, -4.8, rgb(255, 250, 230), M.Glass))
end

local function buildParkingLot(m: Model, F: CFrame, seed: number)
	local W, D = 46, 28
	Box(m, "Lot", F, -W / 2, W / 2, -0.1, 0.2, -D / 2, D / 2, ASPHALT, M.Asphalt, true)
	for i = 0, 8 do
		local x = -W / 2 + 3 + i * 5
		for _, sz in ipairs({ -1, 1 }) do
			Box(m, "Bay", F, x - 0.15, x + 0.15, 0.2, 0.26, sz * 3.5, sz * (D / 2 - 1), WHITE, M.SmoothPlastic)
		end
	end
	for _, sz in ipairs({ -1, 1 }) do
		Box(m, "Kerb", F, -W / 2, W / 2, 0, 0.7, sz * (D / 2) - 0.4, sz * (D / 2) + 0.4, rgb(200, 198, 192), M.Concrete, true)
	end
	local colors = { rgb(200, 40, 50), rgb(40, 90, 170), rgb(230, 230, 230), rgb(40, 40, 46), rgb(90, 150, 90), rgb(240, 190, 60) }
	for i = 0, 7 do
		if hash(seed, i) < 0.6 then
			local sz = i % 2 == 0 and 1 or -1
			local x = -W / 2 + 5.5 + math.floor(i / 2) * 10
			parkedCar(m, F * CFrame.new(x, 0.2, sz * 8.6) * CFrame.Angles(0, sz > 0 and math.pi or 0, 0), CityKit.Pick(colors, seed, i))
		end
	end
	local P = F * CFrame.new(W / 2 - 2, 0.2, 0)
	Column(m, "MeterPost", P, 0, 0, 0, 3.6, 0.3, IRON, M.Metal, true)
	Box(m, "Meter", P, -0.5, 0.5, 3.6, 5.2, -0.4, 0.4, rgb(40, 90, 160), M.Metal)
	Glow(Box(m, "MeterScreen", P, -0.36, 0.36, 4.4, 4.9, -0.44, -0.4, rgb(180, 230, 255), M.Glass))
	local sign = Box(m, "PSign", F, -W / 2 + 0.6, -W / 2 + 3.4, 5, 7.8, -D / 2 - 0.9, -D / 2 - 0.7, rgb(40, 90, 170), M.SmoothPlastic)
	Text(sign, Enum.NormalId.Front, "P", WHITE, nil, Enum.Font.GothamBlack, 90)
	Column(m, "PSignPost", F, -W / 2 + 2, -D / 2 - 0.6, 0, 5, 0.24, IRON, M.Metal, true)
	for _, x in ipairs({ -W / 2 - 3, W / 2 + 3 }) do
		tree(m, F, x, 0, 13, seed + math.floor(x), "Round")
	end
end

local function buildBusStation(m: Model, F: CFrame, seed: number)
	local W, D = 66, 36
	Box(m, "Apron", F, -W / 2, W / 2, -0.1, 0.2, -D / 2, D / 2, ASPHALT, M.Asphalt, true)
	-- 3 quais en îlot, couverts (auvent en ailes)
	for k = 0, 2 do
		local z = -10 + k * 10
		local Q = F * CFrame.new(0, 0.2, z)
		Box(m, "Platform", Q, -26, 26, 0, 0.9, -1.6, 1.6, rgb(200, 196, 188), M.Concrete, true)
		Box(m, "PlatformEdge", Q, -26, 26, 0.9, 0.96, -1.6, -1.3, rgb(250, 210, 40), M.SmoothPlastic)
		for i = 0, 4 do
			local x = -22 + i * 11
			Column(m, "CanopyPost", Q, x, 0, 0.9, 9, 0.4, STEEL, M.Metal, true)
		end
		for _, sz in ipairs({ -1, 1 }) do
			Wedge(m, "CanopyWing", Vector3.new(50, 1, 3.4), Q * CFrame.new(0, 9.5, sz * 1.7) * CFrame.Angles(0, sz > 0 and math.pi or 0, 0), rgb(220, 226, 232), M.Glass)
		end
		local board = Box(m, "QuaiSign", Q, -1.4, 1.4, 6.4, 8.2, -0.12, 0.12, rgb(40, 90, 170), M.SmoothPlastic)
		Text(board, Enum.NormalId.Front, tostring(k + 1), WHITE, nil, Enum.Font.GothamBlack, 90)
		Text(board, Enum.NormalId.Back, tostring(k + 1), WHITE, nil, Enum.Font.GothamBlack, 90)
		CityKit.Bench(m, Q * CFrame.new(-12, 0.9, 0.5), 5)
		local w = CityKit.Npc(m, CityKit.Pick({ "pedestrian", "shopper", "elder", "kid" }, seed, k), seed * 13 + k, Q * CFrame.new(6 - k * 5, 0.9, -0.4) * CFrame.Angles(0, math.pi, 0), k == 1 and "bag" or "phone", true)
		CityKit.Idle(w, "idle", k * 1.3)
	end
	-- tableau des départs (écran) + horloge
	local T = F * CFrame.new(-W / 2 + 4, 0.2, D / 2 - 3)
	Column(m, "BoardPost", T, 0, 0, 0, 8, 0.5, STEEL, M.Metal, true)
	local board = Box(m, "Departures", T, -3.6, 3.6, 8, 12, -0.3, 0.3, rgb(20, 22, 30), M.SmoothPlastic)
	Glow(board)
	Text(board, Enum.NormalId.Front, "🚌 " .. Locale.T("Departures") .. "\n1 · " .. Locale.T("City centre") .. "\n2 · " .. Locale.T("Highway"), rgb(255, 200, 60), rgb(20, 22, 30), Enum.Font.Code, 140)
	-- bus garé au quai 2 (gros volumes simples)
	local Bz = F * CFrame.new(4, 0.2, 5)
	Box(m, "BusBody", Bz, -18, 18, 1, 10, -3.8, -0.4, rgb(250, 190, 40), M.SmoothPlastic, true)
	Box(m, "BusWindows", Bz, -16, 16, 5.6, 9, -3.86, -3.8, rgb(40, 60, 80), M.Glass)
	Box(m, "BusRoof", Bz, -17.6, 17.6, 10, 10.6, -3.6, -0.6, rgb(230, 230, 236), M.SmoothPlastic)
	for _, x in ipairs({ -11, 11 }) do
		Part(m, "BusWheel", Vector3.new(0.8, 2.6, 2.6), Bz * CFrame.new(x, 1.3, -3.9), rgb(30, 30, 34), M.Rubber, "Cyl")
	end
	local dest = Box(m, "BusDest", Bz, 13, 17.6, 8.8, 9.8, -3.9, -3.86, rgb(20, 20, 24), M.SmoothPlastic)
	Text(dest, Enum.NormalId.Front, Locale.T("City centre"), rgb(255, 180, 40), nil, Enum.Font.Code, 80)
	Glow(dest)
end

local function buildLookout(m: Model, F: CFrame, seed: number)
	-- plate-forme en bois sur pilotis (vue vers +Z = hors de la ville)
	Box(m, "Deck", F, -12, 12, 1.8, 2.2, -8, 8, WOOD, M.WoodPlanks, true)
	for _, x in ipairs({ -11, 0, 11 }) do
		for _, z in ipairs({ -7, 7 }) do
			Column(m, "Pile", F, x, z, -0.4, 1.8, 0.8, WOOD_D, M.Wood, true)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "Rail", F, sx * 12 - 0.15, sx * 12 + 0.15, 2.2, 5.4, -8, 8, WOOD_D, M.Wood, true)
	end
	Box(m, "Rail", F, -12, 12, 2.2, 5.4, 7.85, 8.15, WOOD_D, M.Wood, true)
	Box(m, "Steps", F, -2, 2, 0, 1.2, -10, -8, WOOD, M.WoodPlanks, true)
	Box(m, "Steps", F, -2, 2, 0, 0.6, -11.2, -10, WOOD, M.WoodPlanks, true)
	local T = F * CFrame.new(0, 2.2, 6)
	Column(m, "ScopePost", T, 0, 0, 0, 3.4, 0.5, rgb(40, 80, 60), M.Metal)
	Part(m, "Scope", Vector3.new(2.2, 0.8, 0.8), T * CFrame.new(0, 4, 0.2) * CFrame.Angles(0, math.pi / 2, math.rad(8)), rgb(40, 80, 60), M.Metal, "Cyl")
	-- mât avec drapeau (rose, logo)
	Column(m, "FlagPole", F, 10, -6, 2.2, 20, 0.3, STEEL, M.Metal, true)
	local flag = Box(m, "Flag", F, 10.15, 15.5, 16.2, 19.6, -6.05, -5.95, rgb(255, 110, 170), M.Fabric)
	Text(flag, Enum.NormalId.Front, "🧠", WHITE, nil, Enum.Font.GothamBlack, 200)
	local flagBase = flag.CFrame
	CityKit.Actor(m, F.Position, function(t: number)
		flag.CFrame = flagBase * CFrame.new(-2.67, 0, 0) * CFrame.Angles(0, math.sin(t * 2.2) * 0.12, 0) * CFrame.new(2.67, 0, 0)
	end, seed)
	-- table de pique-nique et visiteur
	local P = F * CFrame.new(-7, 2.2, -3)
	Box(m, "PicnicTop", P, -3, 3, 2.2, 2.5, -1.2, 1.2, WOOD, M.WoodPlanks, true)
	for _, z in ipairs({ -2.1, 2.1 }) do
		Box(m, "PicnicSeat", P, -3, 3, 1.3, 1.55, z - 0.5, z + 0.5, WOOD, M.WoodPlanks, true)
	end
	local v = CityKit.Npc(m, "pedestrian", seed * 3 + 1, F * CFrame.new(2, 2.2, 6.4) * CFrame.Angles(0, math.pi, 0), "phone", true)
	CityKit.Idle(v, "idle", 0)
	local sign = Box(m, "LookoutSign", F, -3, 3, 4, 6, -11.6, -11.4, rgb(250, 240, 214), M.WoodPlanks)
	Text(sign, Enum.NormalId.Front, "🔭 " .. Locale.T("Lookout"), rgb(60, 40, 20), nil, Enum.Font.Fantasy, 80)
	Column(m, "LookoutSignPost", F, 0, -11.5, 0, 4, 0.3, WOOD_D, M.Wood)
end

local STYLE_COLORS = {
	Cottage = { rgb(250, 240, 214), rgb(80, 60, 36) },
	Townhouse = { rgb(30, 90, 64), rgb(250, 230, 170) },
	Loft = { rgb(40, 40, 46), rgb(255, 200, 60) },
	Mansion = { rgb(30, 50, 40), rgb(214, 176, 80) },
	Mixed = { rgb(40, 90, 170), WHITE },
}

local function buildDistrictSign(m: Model, F: CFrame, seed: number, spot: any)
	local d = spot and spot.Data or {}
	local cols = STYLE_COLORS[d.Style or "Mixed"] or STYLE_COLORS.Mixed
	for _, x in ipairs({ -4, 4 }) do
		Column(m, "SignPost", F, x, 0, 0, 7.4, 0.4, IRON, M.Metal, true)
		CityKit.Ball(m, "SignFinial", (F * CFrame.new(x, 7.6, 0)).Position, 0.5, IRON, M.Metal)
	end
	local board = Box(m, "DistrictBoard", F, -4.6, 4.6, 4, 7, -0.15, 0.15, cols[1], M.SmoothPlastic)
	Box(m, "DistrictBoardRim", F, -4.8, 4.8, 3.8, 7.2, -0.1, 0.1, cols[2], M.Metal)
	Text(board, Enum.NormalId.Front, tostring(d.Text or ""), cols[2], nil, Enum.Font.GothamBold, 140)
	Text(board, Enum.NormalId.Back, tostring(d.Text or ""), cols[2], nil, Enum.Font.GothamBold, 140)
	-- petit massif fleuri au pied
	for i = 0, 5 do
		Egg(m, "SignBloom", F * CFrame.new(-3.8 + i * 1.5, 0.5, -1), Vector3.new(1.2, 0.9, 1.2), CityKit.Pick(FLOWERS, seed, i), M.SmoothPlastic)
	end
end

-- arbre d'alignement sur l'accotement engazonné d'une avenue (paillis, tuteurs)
local function buildVergeTree(m: Model, F: CFrame, seed: number)
	Column(m, "Mulch", F, 0, 0, -0.1, 0.12, 3.4, rgb(110, 76, 52), M.Ground)
	for _, sx in ipairs({ -1, 1 }) do
		CityKit.Rod(m, "Stake", (F * CFrame.new(sx * 1, 0, 0)).Position, (F * CFrame.new(sx * 0.7, 4.2, 0)).Position, 0.16, rgb(170, 130, 90), M.Wood)
	end
	tree(m, F, 0, 0, 15 + hash(seed, 1) * 6, seed, CityKit.Pick({ "Oak", "Maple", "Poplar", "Birch", "Oak" }, seed, 2))
end

DistrictParks.BUILDERS = {
	VergeTree = buildVergeTree,
	PocketPark = buildPocketPark,
	BasketCourt = buildBasketCourt,
	FootPitch = buildFootPitch,
	Tennis = buildTennis,
	Stadium = buildStadium,
	Grove = buildGrove,
	Meadow = buildMeadow,
	Orchard = buildOrchard,
	Cabin = buildCabin,
	ShopRow = buildShopRow,
	ParkingLot = buildParkingLot,
	BusStation = buildBusStation,
	Lookout = buildLookout,
	DistrictSign = buildDistrictSign,
}
-- (bosquets, vergers, cabanes : rayon normal ; leurs imposteurs prennent le relais)
DistrictParks.BIG = { FootPitch = true, Tennis = true, Stadium = true, ShopRow = true, BusStation = true, Lookout = true }
-- imposteurs (loin) : silhouettes de quelques pièces
DistrictParks.IMPOSTORS = {
	VergeTree = function(m: Model, F: CFrame, seed: number)
		local h = 15 + hash(seed, 1) * 6
		Column(m, "ImpTrunk", F, 0, 0, 0, h * 0.45, 0.9, rgb(100, 72, 50), M.Wood)
		Egg(m, "ImpCrown", F * CFrame.new(0, h * 0.68, 0), Vector3.new(h * 0.55, h * 0.5, h * 0.55), rgb(84, 142, 70), M.Grass)
	end,
	Grove = function(m: Model, F: CFrame, seed: number)
		-- (de loin : une couronne + un tronc par arbre, 2 pièces)
		local n = 4 + math.floor(hash(seed, 1) * 3)
		for i = 0, n - 1 do
			local a = i / n * math.pi * 2 + hash(seed, i) * 0.8
			local r = 5 + hash(seed, i + 10) * 9
			local h = 14 + hash(seed, i + 20) * 10
			local x, z = math.cos(a) * r, math.sin(a) * r
			local fir = CityKit.Pick({ "Oak", "Fir", "Birch", "Maple", "Fir", "Poplar" }, seed, i) == "Fir"
			Column(m, "ImpTrunk", F, x, z, 0, h * 0.45, 1, rgb(100, 72, 50), M.Wood)
			Egg(m, "ImpCrown", F * CFrame.new(x, h * (fir and 0.55 or 0.68), z), fir and Vector3.new(h * 0.35, h * 0.8, h * 0.35) or Vector3.new(h * 0.6, h * 0.5, h * 0.6), fir and rgb(40, 90, 60) or rgb(80, 140, 70):Lerp(rgb(120, 150, 70), hash(seed, i + 3)), M.Grass)
		end
	end,
	Stadium = function(m: Model, F: CFrame)
		Box(m, "ImpTrack", F, -46, 46, -0.1, 0.2, -48, 48, rgb(190, 80, 60), M.Rubber)
		Box(m, "ImpStand", F * CFrame.new(0, 0, 56), -42, 42, 0, 16.8, -8, 11.2, rgb(180, 180, 186), M.Concrete)
	end,
	ShopRow = function(m: Model, F: CFrame)
		Box(m, "ImpShops", F * CFrame.new(0, 0, 3), -23, 23, 0, 12.8, -5, 5, rgb(236, 230, 236), M.Plaster)
	end,
	Orchard = function(m: Model, F: CFrame, seed: number)
		for i = 0, 3 do
			for j = 0, 2 do
				Egg(m, "ImpCrown", F * CFrame.new(-15 + i * 10, 6.5, -11 + j * 11), Vector3.new(7, 5.5, 7), rgb(90, 150, 70):Lerp(rgb(120, 160, 70), hash(seed, i * 3 + j)), M.Grass)
			end
		end
	end,
	BusStation = function(m: Model, F: CFrame)
		Box(m, "ImpBus", F * CFrame.new(4, 0.2, 5), -18, 18, 1, 10.6, -3.8, -0.4, rgb(250, 190, 40), M.SmoothPlastic)
	end,
	Cabin = function(m: Model, F: CFrame)
		Box(m, "ImpCabin", F * CFrame.new(0, 0, 3), -7, 7, 0, 8, -5, 5, rgb(130, 90, 58), M.Wood)
	end,
}

return DistrictParks
