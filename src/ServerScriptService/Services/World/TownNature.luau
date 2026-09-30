--[[
	TownNature (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownNature

	🌳 Parcs et paysage de Dopamine Town (v9.4) :
	  - le pré (un grand disque d'herbe) et les murs invisibles du bord ;
	  - dans l'anneau entre la place et le boulevard, un quartier par secteur :
	      avant droit  : aire de jeux (toboggan, balançoires, tape-cul) +
	                     tables de pique-nique ;
	      arrière droit: LAC (rives de sable, eau transparente, nénuphars,
	                     roseaux, canards, ponton + barque, pont en bois) ;
	      arrière gauche : jardin fleuri sous pergola + terrain de basket ;
	      avant gauche : petit marché (étals rayés) + food truck ;
	    puis des arbres semés sans jamais toucher les rues ni les zones ;
	  - une ceinture de bois derrière les parcelles, des collines, des
	    montagnes enneigées et une ville lointaine (TownBuildings.Skyline).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)
local TownBuildings = require(script.Parent.TownBuildings)
local TownVehicles = require(script.Parent.TownVehicles) -- (v9.7, VEHICLES97) food truck
local Greenery = require(ReplicatedStorage.Shared.Greenery) -- (v9.7, NATURE97) plan du lac

local TownNature = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part
local hash = TownKit.Hash

local GROUND_Y = WorldLayout.GROUND_Y

----------------------------------------------------------------------
-- Lac (v9.7, NATURE97) : un vrai lac de parc
----------------------------------------------------------------------
-- Une seule nappe d'eau (disque transparent : pas de recouvrements qui
-- assombrissent l'eau), bord peu profond (sable visible sous l'eau), fond
-- plus sombre au milieu ; la rive IRRÉGULIÈRE vient des berges (monticules
-- d'herbe / criques de sable qui mordent sur l'eau), des pierres, des
-- roseaux, d'une île avec son saule. Pont en arc en bois (tablier = vraie
-- rampe continue, sans marche), ponton sur pilotis, barque, pédalo cygne,
-- jet d'eau. Les petits détails (nénuphars fleuris, canards, cygnes,
-- roseaux en plus) sont ajoutés côté CLIENT près de l'avatar
-- (TownGreenery, attributs NearDetail / DetailCF / DetailR).

local LAKE = Greenery.LAKE
local SAND = Color3.fromRGB(232, 210, 164)
local ROCK = Color3.fromRGB(150, 146, 150)
local PLANK = Color3.fromRGB(186, 134, 90)
local PLANK_DARK = Color3.fromRGB(140, 98, 66)

-- Tablier en arc (points du DESSUS, du bord a au bord b) : poutres jointives
-- qui dépassent un peu à chaque joint (pas de trou ; arête < 0,03 stud)
local function arch(a: Vector3, b: Vector3, rise: number, n: number): { Vector3 }
	local pts = {}
	for i = 0, n do
		local t = i / n
		table.insert(pts, a:Lerp(b, t) + Vector3.new(0, rise * math.sin(t * math.pi), 0))
	end
	return pts
end

local function bridge(model: Instance, from: Vector3, to: Vector3, side: Vector3)
	local br = TownKit.Model(model, "Bridge")
	local n = 8
	local len = (Vector3.new(to.X, 0, to.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
	local rise = math.min(4.6, len * 0.075)
	local deck = arch(from + Vector3.new(0, 0.06, 0), to + Vector3.new(0, 0.06, 0), rise, n)
	local T = 0.6 -- épaisseur du tablier
	local halfW = LAKE.BridgeHalfW
	for i = 1, n do
		local a, b = deck[i], deck[i + 1]
		local axis = (b - a).Unit
		local up = axis:Cross(side).Unit
		if up.Y < 0 then
			up = -up
		end
		-- (le dessus de la poutre passe par a et b : centre abaissé de T/2)
		local a2, b2 = a - axis * 0.3 - up * T / 2, b + axis * 0.3 - up * T / 2
		-- (un tronçon sur deux 0,1 plus étroit : côtés des recouvrements jamais confondus)
		local plank = TownKit.Beam(br, "Deck", a2, b2, halfW * 2 - (i % 2) * 0.1, T, i % 2 == 0 and PLANK or PLANK:Lerp(PLANK_DARK, 0.25), M.WoodPlanks, "solid")
		plank.CastShadow = true
	end
	-- garde-corps : poteaux à chaque joint + main courante
	for i = 1, n + 1 do
		for _, s in ipairs({ -1, 1 }) do
			local p = deck[i] + side * s * (halfW - 0.2)
			local newel = i == 1 or i == n + 1
			TownKit.Column(br, newel and "Newel" or "Post", p - Vector3.new(0, 0.3, 0), newel and 3.5 or 3.2, newel and 0.7 or 0.36, PLANK_DARK, M.Wood, "prop")
			if newel then
				TownKit.Ball(br, "NewelCap", p + Vector3.new(0, 3.3, 0), 0.9, PLANK, M.Wood, "deco")
			end
			if i <= n then
				local q = deck[i + 1] + side * s * (halfW - 0.2)
				TownKit.Beam(br, "Handrail", p + Vector3.new(0, 2.95, 0), q + Vector3.new(0, 2.95, 0), 0.34, 0.22, PLANK, M.Wood, "deco")
			end
		end
	end
	-- culées en pierre (les pieds du pont, dans la berge)
	for _, e in ipairs({ { deck[1], deck[2] }, { deck[n + 1], deck[n] } }) do
		local dirIn = Vector3.new(e[2].X - e[1].X, 0, e[2].Z - e[1].Z).Unit
		local p = e[1] + dirIn * 2.2
		TownKit.Part(br, "Abutment", Vector3.new(halfW * 2 + 1.6, 1.4, 2.2), CFrame.lookAt(p, p + dirIn) * CFrame.new(0, -0.62, 0), ROCK, M.Cobblestone, "deco")
	end
	return deck
end

-- Barque (coque en 3 pièces + banc + rames)
local function rowBoat(model: Instance, cf: CFrame)
	local hull = Color3.fromRGB(96, 150, 196)
	TownKit.Part(model, "BoatBottom", Vector3.new(2.6, 0.5, 5.4), cf * CFrame.new(0, 0.25, 0), hull, M.WoodPlanks, "deco")
	for _, s in ipairs({ -1, 1 }) do
		TownKit.Part(model, "BoatSide", Vector3.new(0.25, 0.9, 5.6), cf * CFrame.new(s * 1.35, 0.7, 0) * CFrame.Angles(0, 0, math.rad(s * 12)), C.White, M.WoodPlanks, "deco")
	end
	TownKit.Egg(model, "BoatBow", cf * CFrame.new(0, 0.55, -2.7), Vector3.new(2.7, 1.1, 3.4), hull, M.WoodPlanks, "deco")
	TownKit.Part(model, "BoatSeat", Vector3.new(2.5, 0.2, 0.9), cf * CFrame.new(0, 0.95, 0.4), C.WoodLight, M.WoodPlanks, "deco")
	TownKit.Rod(model, "Oar", (cf * CFrame.new(-1.2, 1.1, 0.4)).Position, (cf * CFrame.new(-3.4, 0.3, 1.8)).Position, 0.18, C.WoodLight, M.Wood, "deco")
end

-- Pédalo cygne (coque blanche, cou courbé, tête, bec orange, banc rose)
local function swanBoat(model: Instance, cf: CFrame)
	local white = Color3.fromRGB(250, 250, 252)
	TownKit.Egg(model, "SwanHull", cf * CFrame.new(0, 0.6, 0), Vector3.new(3.8, 1.8, 6.2), white, M.SmoothPlastic, "decoS")
	TownKit.Egg(model, "SwanWing", cf * CFrame.new(0, 1.3, 0.9), Vector3.new(3.4, 1.2, 3.6), Color3.fromRGB(238, 240, 246), M.SmoothPlastic, "deco")
	TownKit.Part(model, "SwanSeat", Vector3.new(2.4, 0.5, 1.2), cf * CFrame.new(0, 1.5, -0.2), Color3.fromRGB(255, 150, 190), M.Fabric, "deco")
	local neck0 = (cf * CFrame.new(0, 1.2, -2.4)).Position
	local neck1 = (cf * CFrame.new(0, 3.6, -3.2)).Position
	local neck2 = (cf * CFrame.new(0, 4.6, -2.7)).Position
	TownKit.Rod(model, "SwanNeck", neck0, neck1, 0.8, white, M.SmoothPlastic, "deco")
	TownKit.Rod(model, "SwanNeck", neck1, neck2, 0.7, white, M.SmoothPlastic, "deco")
	TownKit.Ball(model, "SwanHead", neck2 + Vector3.new(0, 0.1, 0), 1.3, white, M.SmoothPlastic, "deco")
	TownKit.Egg(model, "SwanBeak", CFrame.lookAt(neck2, (cf * CFrame.new(0, 4.4, -4.2)).Position) * CFrame.new(0, -0.05, -0.8), Vector3.new(0.4, 0.35, 0.9), Color3.fromRGB(255, 150, 60), M.SmoothPlastic, "deco")
end

local function lake(folder: Instance, geo: TownKit.Geo, center: Vector3, radius: number)
	local model = TownKit.Model(folder, "Lake")
	local towardPlaza = (Vector3.new(geo.Origin.X, center.Y, geo.Origin.Z) - center).Unit
	local side = Vector3.new(-towardPlaza.Z, 0, towardPlaza.X)
	local G = center + Vector3.new(0, GROUND_Y, 0)
	-- repère du lac : X = side, Y = haut, Z = en s'éloignant de la place
	local L = CFrame.fromMatrix(G, side, Vector3.new(0, 1, 0))
	local R = radius
	local function P(x: number, z: number, y: number?): Vector3
		return (L * CFrame.new(x, y or 0, z)).Position
	end
	local function ang(a: number, r: number): (number, number)
		return math.sin(a) * r, math.cos(a) * r
	end
	model:SetAttribute("NearDetail", "Lake")
	model:SetAttribute("DetailCF", L)
	model:SetAttribute("DetailR", R)
	-- nappes : rive de sable (on y marche), bord peu profond, fond, eau
	TownKit.Disc(model, "Shore", G + Vector3.new(0, 0.06, 0), R + 1.2, 0.3, SAND, M.Sand, "solid")
	TownKit.Disc(model, "LakeBed", G + Vector3.new(0, 0.12, 0), R - 1.6, 0.2, Color3.fromRGB(70, 150, 176), M.Sand, "deco")
	TownKit.Disc(model, "LakeDeep", G + Vector3.new(0, 0.16, 0), R * 0.62, 0.2, C.WaterDeep, M.Slate, "deco")
	local water = TownKit.Disc(model, "Water", G + Vector3.new(0, LAKE.WaterTop, 0), R, 0.2, C.Water, M.Glass, "deco")
	water.Transparency = 0.35
	water.Reflectance = 0.12
	-- berges : une couronne d'ovales couchés le long de la rive, herbe et
	-- sable en alternance, qui mordent plus ou moins sur l'eau : le bord
	-- devient une ligne ondulée (on laisse libres les bouts du pont et le ponton)
	local bx = LAKE.BridgeX * R
	local n = 16
	for k = 0, n - 1 do
		local a = k / n * math.pi * 2 + (hash(k, 101) - 0.5) * 0.2
		local bite = (hash(k, 102) - 0.35) * 3.2
		local x, z = ang(a, R + 1 - bite)
		local nearBridge = math.abs(x - bx) < 7 and math.abs(z) > R * 0.6
		local nearDock = x > R * 0.6 and math.abs(z - LAKE.DockZ * R) < 6
		if not nearBridge and not nearDock then
			local beach = k % 3 == 1
			local len = 2 * math.pi * R / n * (1.25 + hash(k, 103) * 0.35)
			local wid = 5 + hash(k, 104) * 4 + math.max(0, bite) * 1.4
			local tall = beach and 0.95 or 1.3 + hash(k, 105) * 0.5
			local color = beach and SAND or C.Grass:Lerp(C.GrassDark, hash(k, 106) * 0.45)
			TownKit.Egg(model, beach and "Beach" or "Bank", L * CFrame.new(x, 0, z) * CFrame.Angles(0, a, 0), Vector3.new(len, tall, wid), color, beach and M.Sand or M.Grass, "deco")
		end
	end
	-- pierres de la rive
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2 + 0.2 + hash(k, 106) * 0.35
		local x, z = ang(a, R - 0.4 + hash(k, 107) * 1.2)
		if not (math.abs(x - bx) < 6 and math.abs(z) > R * 0.6) then
			local s = 1.1 + hash(k, 108) * 1.3
			TownKit.Egg(model, "Stone", L * CFrame.new(x, 0.3, z) * CFrame.Angles(0, hash(k, 109) * 6, 0), Vector3.new(s * 1.3, s * 0.8, s), ROCK:Lerp(C.White, hash(k, 110) * 0.25), M.Slate, "deco")
		end
	end
	-- roseaux + massettes (le reste des roseaux vient du client)
	for k = 0, 1 do
		local a = 0.7 + k * 1.55
		local x, z = ang(a, R - 1.2)
		if not (math.abs(x - bx) < 6 and math.abs(z) > R * 0.6) then
			local base = L * CFrame.new(x, 0, z)
			TownKit.Egg(model, "Reeds", base * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, a, math.rad(6)), Vector3.new(1.4, 4.2, 1.1), Color3.fromRGB(104, 158, 84), M.Grass, "deco")
			TownKit.Rod(model, "Cattail", (base * CFrame.new(0.5, 0.3, 0.3)).Position, (base * CFrame.new(0.7, 4.4, 0.4)).Position, 0.14, Color3.fromRGB(96, 146, 78), M.Grass, "deco")
			TownKit.Egg(model, "CattailHead", base * CFrame.new(0.72, 4.5, 0.4), Vector3.new(0.42, 1.2, 0.42), Color3.fromRGB(122, 84, 58), M.Fabric, "deco")
		end
	end
	-- l'île et son saule
	local ix, iz, ir = LAKE.Island[1] * R, LAKE.Island[2] * R, math.max(4.5, LAKE.Island[3] * R)
	TownKit.Egg(model, "IslandSand", L * CFrame.new(ix, 0.3, iz), Vector3.new(ir * 2 + 2.4, 1.2, ir * 2 + 1.6), SAND, M.Sand, "deco")
	TownKit.Egg(model, "Island", L * CFrame.new(ix, 0.4, iz), Vector3.new(ir * 2, 2.4, ir * 1.8), C.Grass, M.Grass, "deco")
	TownKit.Tree(model, P(ix, iz, 1.4), 13, 911, "Willow", { Tier = 1, Lawn = true })
	TownKit.Egg(model, "Stone", L * CFrame.new(ix - ir * 0.8, 0.5, iz + ir * 0.5), Vector3.new(1.8, 1.1, 1.4), ROCK, M.Slate, "deco")
	-- jet d'eau (colonne + gerbe, transparentes, + particules douces)
	local jx, jz = LAKE.Jet[1] * R, LAKE.Jet[2] * R
	TownKit.Disc(model, "JetRipple", P(jx, jz, LAKE.WaterTop + 0.04), 2.2, 0.06, Color3.fromRGB(214, 238, 252), M.SmoothPlastic, "deco").Transparency = 0.35
	local column = TownKit.Egg(model, "JetColumn", L * CFrame.new(jx, LAKE.WaterTop + 3.3, jz), Vector3.new(0.8, 6.4, 0.8), Color3.fromRGB(226, 244, 255), M.Glass, "deco")
	column.Transparency = 0.35
	local spray = TownKit.Egg(model, "JetSpray", L * CFrame.new(jx, LAKE.WaterTop + 6.2, jz), Vector3.new(3.2, 1.6, 3.2), Color3.fromRGB(236, 248, 255), M.Glass, "deco")
	spray.Transparency = 0.45
	local drops = Instance.new("ParticleEmitter")
	drops.Name = "JetDrops"
	drops.Color = ColorSequence.new(Color3.fromRGB(230, 246, 255))
	drops.LightEmission = 0
	drops.Transparency = NumberSequence.new(0.3, 1)
	drops.Size = NumberSequence.new(0.35, 0.1)
	drops.Lifetime = NumberRange.new(0.8, 1.2)
	drops.Rate = 18
	drops.Speed = NumberRange.new(4, 6)
	drops.SpreadAngle = Vector2.new(35, 35)
	drops.Acceleration = Vector3.new(0, -18, 0)
	drops.Parent = spray
	-- pont en arc (du côté de la place vers le fond)
	bridge(model, P(bx, -(R + 5)), P(bx, R + 5), side)
	-- ponton sur pilotis (depuis la rive +X, vers le milieu) + barque + pédalo
	local dz = LAKE.DockZ * R
	local dock = L * CFrame.new(R - 3, 0, dz) * CFrame.Angles(0, math.pi / 2, 0)
	-- (dessus à 0,85 : une petite marche depuis la rive)
	TownKit.Part(model, "Dock", Vector3.new(4, 0.4, 12), dock * CFrame.new(0, 0.65, 0), PLANK, M.WoodPlanks, "solid")
	for _, zz in ipairs({ -5.4, 0, 5.4 }) do
		for _, xx in ipairs({ -1.7, 1.7 }) do
			TownKit.Column(model, "DockPost", (dock * CFrame.new(xx, -0.2, zz)).Position, 1.8, 0.45, PLANK_DARK, M.Wood, "deco")
		end
	end
	rowBoat(model, dock * CFrame.new(-3.6, LAKE.WaterTop - 0.35, 2.4) * CFrame.Angles(0, math.rad(8), 0))
	swanBoat(model, dock * CFrame.new(3.8, LAKE.WaterTop - 0.3, 1.4) * CFrame.Angles(0, math.rad(-10), 0))
	-- arbres de la rive : saules pleureurs + deux palmiers sur la plage
	local rim = {
		{ -0.62, 0.9, "Willow" },
		{ -1.02, -0.2, "Willow" },
		{ 0.62, 0.94, "Palm" },
		{ 0.86, 0.72, "Palm" },
	}
	for i, t in ipairs(rim) do
		local p = P(t[1] * R + (t[1] > 0 and 3 or -3), t[2] * R + 3)
		TownKit.Tree(model, p, t[3] == "Palm" and 15 + i or 14, 131 * i, t[3], { Tier = 1, Lawn = true })
	end
	-- bancs face à l'eau (côté place) + lampadaires aux bouts du pont
	for _, bxx in ipairs({ 0.34, -0.72 }) do
		local p = P(bxx * R, -(R + 6))
		TownKit.Bench(model, CFrame.lookAt(p, P(bxx * R, 0)))
	end
	for _, s in ipairs({ -1, 1 }) do
		TownKit.Lamp(model, P(bx + 5.2, s * (R + 7)), TownKit.Facing(-side), false)
	end
	geo.Reserve(center, R + 9)
	-- (pied du pont côté place : l'allée du parc y arrive)
	return P(bx, -(R + 7))
end

----------------------------------------------------------------------
-- Aire de jeux (v9.7, NATURE97), pique-nique, coin du parc
----------------------------------------------------------------------
-- (v9.9, PARK99) 🛝 aire de jeux QUI MARCHE : ici, seulement le squelette
-- serveur (TownPark : sol souple, murs invisibles, volumes où l'on marche,
-- mur d'escalade, SIÈGES + invites E des balançoires, tape-cul, tourniquet,
-- jeux à ressort, bancs ; repères des invites Glisser / Traverser /
-- Creuser). Tout le décor réaliste et les animations sont côté CLIENT
-- (ParkPlay, via TownGreenery : NearDetail "Playground"). `cf` : centre au
-- sol, -Z vers la place. (v9.7 : ~110 pièces serveur, rien ne bougeait.)

local TownPark = require(script.Parent.TownPark)

local function playground(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "Playground")
	local g = cf * CFrame.new(0, GROUND_Y, 0)
	model:SetAttribute("NearDetail", "Playground")
	model:SetAttribute("DetailCF", g)
	TownPark.Build(model, g)
	-- un banc pour les parents + une poubelle, dehors, près du portillon
	local hd = 30 / 2 + 0.6
	TownKit.Bench(model, CFrame.lookAt((g * CFrame.new(-9, 0, -hd - 4.5)).Position, (g * CFrame.new(-9, 0, 0)).Position))
	TownKit.Bin(model, (g * CFrame.new(2.4 + 3.2, 0, -hd - 2.4)).Position, Color3.fromRGB(96, 150, 110))
	geo.Reserve(cf.Position, 23)
	-- (après toute la nature : invite "S'asseoir" sur les bancs du parc)
	task.defer(TownPark.BenchPrompts, folder)
end

local function picnic(folder: Instance, geo: TownKit.Geo, cf: CFrame, count: number)
	local model = TownKit.Model(folder, "Picnic")
	for i = 1, count do
		local t = cf * CFrame.new((i - (count + 1) / 2) * 9, GROUND_Y, (i % 2) * 3) * CFrame.Angles(0, math.rad(i * 25), 0)
		part(model, "TableTop", Vector3.new(6, 0.35, 2.6), t * CFrame.new(0, 2.6, 0), C.WoodLight, M.WoodPlanks, "solid")
		part(model, "Cloth", Vector3.new(3, 0.05, 2.7), t * CFrame.new(0, 2.8, 0), i % 2 == 0 and C.Pink or C.Sky, M.Fabric, "deco")
		for _, z in ipairs({ -2, 2 }) do
			part(model, "BenchPlank", Vector3.new(6, 0.3, 1), t * CFrame.new(0, 1.5, z), C.WoodLight, M.WoodPlanks, "solid")
		end
		for _, x in ipairs({ -2.4, 2.4 }) do
			part(model, "Legs", Vector3.new(0.4, 2.5, 4.6), t * CFrame.new(x, 1.25, 0), C.Wood, M.Wood, "prop")
		end
		geo.Reserve(t.Position, 5)
	end
	-- (v9.7) chariot à glaces sous son parasol, à côté des tables
	local cart = cf * CFrame.new((count + 1) / 2 * 9 + 4, GROUND_Y, -2) * CFrame.Angles(0, math.rad(-20), 0)
	part(model, "CartBody", Vector3.new(4.4, 2.2, 2.2), cart * CFrame.new(0, 1.9, 0), Color3.fromRGB(255, 236, 244), M.SmoothPlastic, "prop")
	part(model, "CartStripe", Vector3.new(4.5, 0.5, 2.3), cart * CFrame.new(0, 2.2, 0), C.Pink, M.SmoothPlastic, "deco")
	for _, x in ipairs({ -1.4, 1.4 }) do
		local wheel = part(model, "CartWheel", Vector3.new(0.3, 1.6, 1.6), cart * CFrame.new(x, 0.8, 1.2) * CFrame.Angles(0, math.rad(90), 0), C.Metal, M.Rubber, "deco")
		;(wheel :: Part).Shape = Enum.PartType.Cylinder
	end
	TownKit.Column(model, "CartPole", (cart * CFrame.new(0, 3, 0)).Position, 4.2, 0.2, C.White, M.Metal, "deco")
	TownKit.Egg(model, "Parasol", cart * CFrame.new(0, 7.2, 0), Vector3.new(6.4, 1.6, 6.4), C.Mint, M.Fabric, "decoS")
	TownKit.Ball(model, "Scoop", (cart * CFrame.new(-1, 3.4, 0)).Position, 0.9, C.Pink, M.SmoothPlastic, "deco")
	TownKit.Ball(model, "Scoop", (cart * CFrame.new(0.2, 3.4, 0.1)).Position, 0.9, C.Lemon, M.SmoothPlastic, "deco")
	geo.Reserve(cart.Position, 5)
end

-- Kiosque (gloriette) : plancher, 6 colonnes, dôme, épi de faîtage
local function gazebo(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "Gazebo")
	local g = cf * CFrame.new(0, GROUND_Y, 0)
	TownKit.Disc(model, "GazeboFloor", (g * CFrame.new(0, 0.5, 0)).Position, 6.2, 0.6, C.Stone, M.Marble, "solid")
	TownKit.Disc(model, "GazeboStep", (g * CFrame.new(0, 0.25, 0)).Position, 7, 0.3, C.StoneDark, M.Marble, "solid")
	for k = 0, 5 do
		local a = k * math.pi / 3 + math.pi / 6
		TownKit.Column(model, "GazeboPost", (g * CFrame.new(math.cos(a) * 5.4, 0.5, math.sin(a) * 5.4)).Position, 6.6, 0.5, C.White, M.Wood, "prop")
	end
	-- (dôme en lentille : dessous à 6,1 au centre, au-dessus des têtes)
	TownKit.Egg(model, "GazeboRoof", g * CFrame.new(0, 7.6, 0), Vector3.new(14.4, 3, 14.4), Color3.fromRGB(150, 196, 180), M.SmoothPlastic, "decoS")
	TownKit.Egg(model, "GazeboCrown", g * CFrame.new(0, 8.9, 0), Vector3.new(5, 1.4, 5), Color3.fromRGB(236, 246, 240), M.SmoothPlastic, "deco")
	TownKit.Ball(model, "GazeboFinial", (g * CFrame.new(0, 9.9, 0)).Position, 0.9, C.Yellow, M.Metal, "deco")
	TownKit.Bench(model, g * CFrame.new(0, 0.5, 2.6) * CFrame.Angles(0, math.pi, 0))
	geo.Reserve(cf.Position, 11)
end

----------------------------------------------------------------------
-- Marché + food truck
----------------------------------------------------------------------

local function market(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "Market")
	TownKit.Disc(model, "Square", (cf * CFrame.new(0, GROUND_Y + 0.15, 0)).Position, 17, 0.5, C.Paving, M.Cobblestone, "solid")
	local stalls = {
		{ C.Pink, Color3.fromRGB(255, 120, 120) }, -- fraises
		{ C.Mint, Color3.fromRGB(255, 190, 90) }, -- oranges
		{ C.Lemon, Color3.fromRGB(150, 210, 110) }, -- pommes
	}
	for i, colors in ipairs(stalls) do
		-- (v9.6 : posés SUR la place (dessus à +0.15), plus 0.25 au-dessus du sol)
		local s = cf * CFrame.Angles(0, math.rad((i - 2) * 50), 0) * CFrame.new(0, GROUND_Y + 0.15, -10)
		part(model, "Counter", Vector3.new(7, 2.6, 2.6), s * CFrame.new(0, 1.3, 0), C.WoodLight, M.WoodPlanks, "solid")
		part(model, "Goods", Vector3.new(6.4, 0.6, 2), s * CFrame.new(0, 2.9, 0), colors[2], M.SmoothPlastic, "deco")
		for _, x in ipairs({ -3.3, 3.3 }) do
			part(model, "Pole", Vector3.new(0.3, 7, 0.3), s * CFrame.new(x, 3.5, 1.2), C.White, M.Wood, "deco")
		end
		for k = 0, 5 do
			part(model, "Canopy", Vector3.new(7.6 / 6, 0.2, 4.4), s * CFrame.new(-3.8 + (k + 0.5) * 7.6 / 6, 7, -0.2) * CFrame.Angles(math.rad(-14), 0, 0), k % 2 == 0 and colors[1] or C.White, M.Fabric, k == 0 and "decoS" or "deco")
		end
	end
	-- food truck (v9.7, VEHICLES97) : vrai food truck posé SUR la place
	-- (cabine, passe-plat + comptoir tournés vers le marché, auvent rayé,
	-- menu, enseigne "🌮 Taco Party") ; version légère (~50 pièces)
	local truck = cf * CFrame.new(0, GROUND_Y + 0.15, 9) * CFrame.Angles(0, math.rad(90), 0)
	TownVehicles.FoodTruck(model, truck, Color3.fromRGB(255, 214, 120))
	geo.Reserve(cf.Position, 19)
end

----------------------------------------------------------------------
-- Jardin fleuri (pergola) + terrain de basket
----------------------------------------------------------------------

local function flowerGarden(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "FlowerGarden")
	-- (v9.7) planches de terre + vraies touffes de fleurs (ovales en bouquets)
	for i = 0, 4 do
		local row = cf * CFrame.new(0, GROUND_Y, -9 + i * 4.4)
		part(model, "Soil", Vector3.new(20, 0.6, 2.4), row * CFrame.new(0, 0.3, 0), Color3.fromRGB(120, 86, 64), M.Ground, "prop")
		-- feuillage de la planche, puis des bouquets ronds qui dépassent
		TownKit.Egg(model, "Leaves", row * CFrame.new(0, 0.75, 0), Vector3.new(19.4, 1.1, 2.12), Color3.fromRGB(92, 156, 80), M.Grass, "deco")
		for k = 0, 3 do
			local color = TownKit.FLOWERS[(i + (k % 2) * 2) % #TownKit.FLOWERS + 1]
			TownKit.Egg(model, "Flowers", row * CFrame.new(-7.2 + k * 4.8 + (hash(i, k + 120) - 0.5) * 0.8, 1.25 + hash(i, k + 126) * 0.15, (hash(i, k + 123) - 0.5) * 0.4), Vector3.new(3.4, 0.95, 1.7), color, M.SmoothPlastic, "deco")
		end
	end
	-- pergola couverte de glycine
	local p = cf * CFrame.new(0, GROUND_Y, 16)
	for _, x in ipairs({ -4, 4 }) do
		for _, z in ipairs({ -3, 3 }) do
			part(model, "PergolaPost", Vector3.new(0.7, 8, 0.7), p * CFrame.new(x, 4, z), C.White, M.Wood, "prop")
		end
	end
	for i = 0, 4 do
		part(model, "PergolaBeam", Vector3.new(10, 0.4, 0.5), p * CFrame.new(0, 8.2, -3 + i * 1.5), C.White, M.Wood, "deco")
	end
	local lilac = Color3.fromRGB(200, 150, 230)
	TownKit.Egg(model, "Vine", p * CFrame.new(-2, 8.9, 0), Vector3.new(6.3, 1.4, 7.4), Color3.fromRGB(120, 176, 96), M.Grass, "deco")
	TownKit.Egg(model, "Vine", p * CFrame.new(2.4, 8.8, 0.5), Vector3.new(5.6, 1.3, 6.6), lilac, M.Grass, "deco")
	for k = 0, 3 do
		local x = -3.3 + k * 2.2
		TownKit.Egg(model, "Wisteria", p * CFrame.new(x, 7.4, (k % 2 == 0) and -2.6 or 2.6), Vector3.new(0.9, 2.2, 0.9), lilac:Lerp(C.White, (k % 2) * 0.25), M.SmoothPlastic, "deco")
	end
	TownKit.Bench(model, p * CFrame.new(0, 0, 1.2))
	geo.Reserve((cf * CFrame.new(0, 0, 3)).Position, 16)
end

local function court(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "Court")
	part(model, "Floor", Vector3.new(30, 0.5, 17), cf * CFrame.new(0, GROUND_Y + 0.1, 0), Color3.fromRGB(120, 150, 214), M.Rubber, "solid")
	part(model, "Paint", Vector3.new(26, 0.1, 13), cf * CFrame.new(0, GROUND_Y + 0.38, 0), Color3.fromRGB(236, 150, 120), M.Rubber, "deco")
	part(model, "MidLine", Vector3.new(0.3, 0.12, 13), cf * CFrame.new(0, GROUND_Y + 0.4, 0), C.White, M.SmoothPlastic, "deco")
	-- (v9.6 z-fighting : dessus à +0.49, au-dessus de la peinture (+0.43) et de la ligne (+0.46))
	TownKit.Disc(model, "Circle", (cf * CFrame.new(0, GROUND_Y + 0.49, 0)).Position, 2.4, 0.1, C.White, M.SmoothPlastic, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		local hoop = cf * CFrame.new(sx * 13.8, GROUND_Y, 0)
		part(model, "HoopPole", Vector3.new(0.5, 10, 0.5), hoop * CFrame.new(sx * 1, 5, 0), C.Metal, M.Metal, "prop")
		part(model, "Backboard", Vector3.new(0.2, 3.4, 5), hoop * CFrame.new(sx * 0.6, 10, 0), C.White, M.Glass, "deco")
		local ring = part(model, "Rim", Vector3.new(0.2, 1.8, 1.8), hoop * CFrame.new(-sx * 0.4, 8.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 120, 60), M.Metal, "deco")
		;(ring :: Part).Shape = Enum.PartType.Cylinder
	end
	-- grillage (deux longs côtés)
	for _, sz in ipairs({ -1, 1 }) do
		local fence = part(model, "Fence", Vector3.new(30, 5, 0.2), cf * CFrame.new(0, GROUND_Y + 2.5, sz * 8.6), C.MetalLight, M.DiamondPlate, "prop")
		fence.Transparency = 0.55
	end
	TownKit.Ball(model, "Ball", (cf * CFrame.new(3, GROUND_Y + 1.2, 2)).Position, 1.6, Color3.fromRGB(240, 130, 60), M.Rubber, "deco")
	geo.Reserve(cf.Position, 17)
end

----------------------------------------------------------------------
-- Allées de parc, terrain de foot, champ de tulipes (grandes villes)
----------------------------------------------------------------------

local PATH = Color3.fromRGB(236, 222, 196)

-- Allée en gravier SINUEUSE de a à b (v9.7) : tronçons droits + disques
-- aux coudes (virages arrondis, un peu plus hauts : pas de faces confondues) ;
-- réserve son tracé (pas d'arbre dessus)
local function footpath(folder: Instance, geo: TownKit.Geo, a: Vector3, b: Vector3, seed: number?)
	local y = geo.Origin.Y + GROUND_Y + 0.06
	local flatA = Vector3.new(a.X, y, a.Z)
	local flatB = Vector3.new(b.X, y, b.Z)
	local len = (flatB - flatA).Magnitude
	if len < 6 then
		return
	end
	local along = (flatB - flatA).Unit
	local perp = Vector3.new(-along.Z, 0, along.X)
	local n = math.clamp(math.floor(len / 13), 1, 5)
	local amp = math.min(4, len * 0.08) * (hash(seed or 1, 130) < 0.5 and -1 or 1)
	local pts = {}
	for i = 0, n do
		local t = i / n
		local wiggle = (i == 0 or i == n) and 0 or math.sin(t * math.pi * 2) * amp
		table.insert(pts, flatA:Lerp(flatB, t) + perp * wiggle)
	end
	for i = 1, n do
		local p0, p1 = pts[i], pts[i + 1]
		local mid = (p0 + p1) / 2
		part(folder, "Footpath", Vector3.new(5, 0.2, (p1 - p0).Magnitude), CFrame.lookAt(mid, p1) * CFrame.new(0, -0.1, 0), PATH, M.Pebble, "deco")
		if i < n then
			TownKit.Disc(folder, "PathBend", p1 + Vector3.new(0, 0.03, 0), 2.5, 0.2, PATH, M.Pebble, "deco")
		end
	end
	for t = 0, len, 9 do
		geo.Reserve(flatA:Lerp(flatB, t / len), 4 + math.abs(amp))
	end
end

local function soccer(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "SoccerField")
	local L, W = 44, 28
	part(model, "Pitch", Vector3.new(W, 0.2, L), cf * CFrame.new(0, GROUND_Y + 0.02, 0), Color3.fromRGB(110, 190, 100), M.Grass, "deco")
	for i = -2, 2, 2 do
		part(model, "Stripe", Vector3.new(W - 2, 0.2, L / 7), cf * CFrame.new(0, GROUND_Y + 0.05, i * L / 7), Color3.fromRGB(130, 206, 116), M.Grass, "deco")
	end
	local line = C.White
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "Touchline", Vector3.new(0.4, 0.2, L - 2), cf * CFrame.new(sx * (W / 2 - 1), GROUND_Y + 0.08, 0), line, M.SmoothPlastic, "deco")
		part(model, "GoalLine", Vector3.new(W - 2, 0.2, 0.4), cf * CFrame.new(0, GROUND_Y + 0.08, sx * (L / 2 - 1)), line, M.SmoothPlastic, "deco")
		-- but : poteaux, barre, filet
		local goal = cf * CFrame.new(0, GROUND_Y, sx * (L / 2 - 0.6))
		for _, gx in ipairs({ -3.5, 3.5 }) do
			part(model, "Post", Vector3.new(0.3, 4, 0.3), goal * CFrame.new(gx, 2, 0), line, M.Metal, "prop")
		end
		part(model, "Bar", Vector3.new(7.3, 0.3, 0.3), goal * CFrame.new(0, 4, 0), line, M.Metal, "deco")
		local net = part(model, "Net", Vector3.new(7, 3.8, 2), goal * CFrame.new(0, 2, sx * 1.1), line, M.Fabric, "deco")
		net.Transparency = 0.6
	end
	part(model, "MidLine", Vector3.new(W - 2, 0.2, 0.4), cf * CFrame.new(0, GROUND_Y + 0.08, 0), line, M.SmoothPlastic, "deco")
	TownKit.Disc(model, "CenterRing", (cf * CFrame.new(0, GROUND_Y + 0.1, 0)).Position, 4.2, 0.1, line, M.SmoothPlastic, "deco")
	TownKit.Disc(model, "CenterIn", (cf * CFrame.new(0, GROUND_Y + 0.12, 0)).Position, 3.8, 0.1, Color3.fromRGB(110, 190, 100), M.Grass, "deco")
	TownKit.Ball(model, "Ball", (cf * CFrame.new(2, GROUND_Y + 0.9, 3)).Position, 1.4, C.White, M.SmoothPlastic, "deco")
	geo.Reserve(cf.Position, 27)
end

local function tulips(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "TulipField")
	for i = 0, 6 do
		part(model, "Tulips", Vector3.new(26, 1.1, 2.6), cf * CFrame.new(0, GROUND_Y + 0.5, -12 + i * 4), TownKit.FLOWERS[i % #TownKit.FLOWERS + 1], M.Grass, "deco")
	end
	-- petit moulin décoratif
	local mill = cf * CFrame.new(16, GROUND_Y, 0)
	TownKit.Column(model, "MillTower", mill.Position, 12, 5, C.Cream, M.Plaster, "solid")
	TownKit.Wedge(model, "MillRoof", Vector3.new(5.6, 3, 2.8), mill * CFrame.new(0, 13.5, -1.4), Color3.fromRGB(170, 96, 90), M.ClayRoofTiles, "deco")
	TownKit.Wedge(model, "MillRoof", Vector3.new(5.6, 3, 2.8), mill * CFrame.new(0, 13.5, 1.4) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(170, 96, 90), M.ClayRoofTiles, "deco")
	local hub = mill * CFrame.new(0, 10, -2.8)
	for k = 0, 1 do
		part(model, "Sail", Vector3.new(1.4, 14, 0.2), hub * CFrame.Angles(0, 0, math.rad(45 + k * 90)), C.White, M.Fabric, "deco")
	end
	geo.Reserve(cf.Position, 20)
	geo.Reserve(mill.Position, 5)
end

----------------------------------------------------------------------
-- Paysage lointain
----------------------------------------------------------------------

local function hills(folder: Instance, geo: TownKit.Geo)
	local model = TownKit.Model(folder, "Hills")
	local O = geo.Origin
	-- (grandes boules très enterrées : on ne voit qu'un dôme doux de 25 à 55 studs)
	local n = 18
	for i = 1, n do
		local a = (i + hash(i, 61) * 0.6) / n * math.pi * 2
		local d = 380 + hash(i, 63) * 260
		local rise = 25 + hash(i, 65) * 30
		local dist = geo.Town + 60 + math.sqrt(d * rise) * 0.9 + hash(i, 62) * 60
		local p = O + Vector3.new(math.sin(a) * dist, GROUND_Y - d / 2 + rise, math.cos(a) * dist)
		local tone = C.Grass:Lerp(Color3.fromRGB(106, 176, 98), hash(i, 64))
		TownKit.Ball(model, "Hill", p, d, tone, M.Grass, "deco")
		-- (v9.8, CITY98) éoliennes sur quelques sommets (client : pales qui tournent)
		if i % 4 == 1 then
			local top = O + Vector3.new(math.sin(a) * dist, GROUND_Y + rise - 0.6, math.cos(a) * dist)
			TownKit.LifeSpot("Turbine", CFrame.lookAt(top, Vector3.new(O.X, top.Y, O.Z)), i)
		end
	end
	-- montagnes enneigées (pyramides approchées) dans le dos de l'entrée
	for i = 1, 5 do
		local a = math.pi + (i - 3) * 0.36 + (hash(i, 65) - 0.5) * 0.1
		local dist = geo.Town + 360 + hash(i, 66) * 80
		local h = 90 + hash(i, 67) * 80
		local w = h * 1.5
		local base = O + Vector3.new(math.sin(a) * dist, GROUND_Y - 5, math.cos(a) * dist)
		local cf = CFrame.lookAt(base, Vector3.new(O.X, base.Y, O.Z))
		local rock = Color3.fromRGB(150, 150, 196):Lerp(Color3.fromRGB(176, 170, 214), hash(i, 68))
		for r = 0, 1 do
			local rot = CFrame.Angles(0, r * math.pi / 2, 0)
			TownKit.Wedge(model, "Mountain", Vector3.new(w, h, w / 2), cf * rot * CFrame.new(0, h / 2, -w / 4), rock, M.Rock, "deco")
			TownKit.Wedge(model, "Mountain", Vector3.new(w, h, w / 2), cf * rot * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, h / 2, -w / 4), rock, M.Rock, "deco")
		end
		local sh = h * 0.28
		local sw = w * 0.28
		for r = 0, 1 do
			local rot = CFrame.Angles(0, r * math.pi / 2, 0)
			TownKit.Wedge(model, "Snow", Vector3.new(sw + 0.4, sh, sw / 2 + 0.2), cf * rot * CFrame.new(0, h - sh / 2 + 0.3, -sw / 4), C.White, M.Snow, "deco")
			TownKit.Wedge(model, "Snow", Vector3.new(sw + 0.4, sh, sw / 2 + 0.2), cf * rot * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, h - sh / 2 + 0.3, -sw / 4), C.White, M.Snow, "deco")
		end
	end
end

-- Arbres semés dans les zones libres de l'anneau intérieur
local function scatterTrees(folder: Instance, geo: TownKit.Geo, target: number)
	local model = TownKit.Model(folder, "ParkTrees")
	-- (grandes villes : plus d'arbres, surtout des boules taillées à 2 pièces)
	local roundish = geo.Slots >= 11 and 0.65 or 0.3
	local placed = 0
	local r0 = WorldLayout.PLAZA_R + 30
	local r1 = geo.Inner
	for i = 1, target * 8 do
		if placed >= target then
			break
		end
		local a = hash(i, 71) * math.pi * 2
		-- (v10 : centre-ville CARRÉ, les coins aussi : r jusqu'à r1 / cos 45°)
		local r = r0 + math.sqrt(hash(i, 72)) * (r1 * 1.41 - r0)
		local p = geo.Origin + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
		local size = 10 + hash(i, 73) * 8
		if geo.IsFree(p, 4) then
			-- (v9.7 NATURE97) parc mélangé : chênes, érables, cerisiers, bouleaux,
			-- sapins, peupliers, pommiers (grandes villes : plus de peupliers, fins
			-- et à 3 pièces) ; silhouette côté serveur, détails de près côté client
			local h = hash(i, 74)
			local mix = roundish > 0.5 and { "Poplar", "Oak", "Poplar", "Birch", "Fir", "Cherry", "Poplar", "Maple" }
				or { "Oak", "Maple", "Cherry", "Birch", "Oak", "Fir", "Poplar", "Fruit", "Oak", "Cherry" }
			local kind = mix[1 + math.floor(h * #mix) % #mix]
			TownKit.Tree(model, p + Vector3.new(0, GROUND_Y, 0), size, i, kind, { Lawn = true })
			geo.Reserve(p, 6)
			placed += 1
		end
	end
	return placed
end

-- (v10, LAYOUT10) Ceinture verte de la grande ville : arbres (construits
-- côté client, 0 pièce serveur : TownKit.Tree) entre l'avenue de ceinture et
-- l'autoroute, et dans la campagne au-delà de l'autoroute. Jamais sur une
-- route, une parcelle, un lieu réservé ni dans les zones de quartier / nature
-- (celles-là sont habillées par CITY10, côté client).
local function belt(folder: Instance, geo: TownKit.Geo)
	local model = TownKit.Model(folder, "Woods")
	local O = geo.Origin
	local count = geo.Count
	local R = WorldLayout.BeltR(count)
	local H = WorldLayout.HighwayR(count)
	local town = WorldLayout.TownRadius(count)
	local zones = WorldLayout.Facilities(count)
	local function blocked(x: number, z: number, r: number): boolean
		if WorldLayout.OnRoad(count, x, z, r + 3) or WorldLayout.OnPlot(count, x, z, r + 2) then
			return true
		end
		for _, zone in ipairs(zones) do
			if WorldLayout.InZone(zone, x, z, r) then
				return true
			end
		end
		return false
	end
	local rings = {
		{ In = R + WorldLayout.GRID_HALF + 10, Out = H - WorldLayout.HIGHWAY_W / 2 - 14, Target = 90, Salt = 0 },
		{ In = H + WorldLayout.HIGHWAY_W / 2 + 18, Out = town - 40, Target = 70, Salt = 5000 },
	}
	local placed: { Vector3 } = {}
	for _, ring in ipairs(rings) do
		local n = 0
		for i = 1, ring.Target * 6 do
			if n >= ring.Target then
				break
			end
			local salt = ring.Salt + i
			-- point au hasard dans l'anneau carré : un côté, une position le long, une profondeur
			local side = math.floor(hash(salt, 11) * 4) % 4
			local along = (hash(salt, 12) * 2 - 1) * ring.Out
			local depth = ring.In + hash(salt, 13) * (ring.Out - ring.In)
			local x, z
			if side == 0 then
				x, z = along, depth
			elseif side == 1 then
				x, z = depth, along
			elseif side == 2 then
				x, z = along, -depth
			else
				x, z = -depth, along
			end
			local size = 13 + hash(salt, 14) * 9
			local ok = not blocked(x, z, 6)
			if ok then
				for _, q in ipairs(placed) do
					if (q.X - x) ^ 2 + (q.Z - z) ^ 2 < 14 * 14 then
						ok = false
						break
					end
				end
			end
			if ok then
				local h = hash(salt, 15)
				local kind = h < 0.35 and "Fir" or (h < 0.6 and "Oak" or (h < 0.8 and "Poplar" or (h < 0.92 and "Birch" or "Maple")))
				TownKit.Tree(model, O + Vector3.new(x, GROUND_Y, z), size, salt, kind, { Lawn = true })
				table.insert(placed, Vector3.new(x, 0, z))
				n += 1
			end
		end
	end
end

----------------------------------------------------------------------
-- (v9.8, CITY98) Parcs : emplacements du mobilier construit côté client
----------------------------------------------------------------------

-- Zones tenues libres pour les autres (fête foraine derrière la mairie et
-- son allée ; repère : centre de la ville, 8 parcelles, tailles fixes)
local function inKeepOut(geo: TownKit.Geo, p: Vector3, r: number): boolean
	local rel = p - geo.Origin
	-- fête foraine + allée derrière la mairie (FAIR98 : x -55..55, z -176..-92)
	if rel.X > -58 - r and rel.X < 58 + r and rel.Z > -179 - r and rel.Z < -89 + r then
		return true
	end
	-- chemins latéraux (x = ±39) et axe central jusqu'à la mairie
	if math.abs(rel.X) < 10 + r and rel.Z > -100 - r and rel.Z < -60 + r then
		return true
	end
	if math.abs(math.abs(rel.X) - 39) < 4 + r and rel.Z > -100 - r and rel.Z < -70 + r then
		return true
	end
	return false
end

local function lifeParks(geo: TownKit.Geo, r0: number): { any }
	local O = geo.Origin
	local placedList = {}
	local wanted = {
		{ Kind = "MarketSquare", R = 15, Count = 1 },
		{ Kind = "Statue", R = 6, Count = 2 },
		{ Kind = "ChessTables", R = 6, Count = 1 },
		{ Kind = "Statue", R = 6, Count = 1 },
	}
	local salt = 0
	for _, w in ipairs(wanted) do
		local placed = 0
		for _ = 1, 500 do
			if placed >= w.Count then
				break
			end
			salt += 1
			local a = hash(salt, 91) * math.pi * 2
			local r = r0 + w.R + math.sqrt(hash(salt, 92)) * (geo.Inner - r0 - 2 * w.R - 6)
			local p = O + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
			if geo.IsFree(p, w.R) and not inKeepOut(geo, p, w.R) then
				-- (tourné vers le centre de la ville)
				local cf = CFrame.lookAt(p + Vector3.new(0, GROUND_Y, 0), Vector3.new(O.X, O.Y + GROUND_Y, O.Z))
				TownKit.LifeSpot(w.Kind, cf, salt)
				geo.Reserve(p, w.R)
				placed += 1
				table.insert(placedList, { Pos = p, R = w.R, Name = w.Kind, Dest = w.Kind == "MarketSquare" and 16 or nil })
			end
		end
	end
	return placedList
end

----------------------------------------------------------------------
-- (v9.9, CITY99) PLUS DE ZONE MORTE : nouveaux lieux dans les coins vides
-- de l'anneau (construits côté client : TownDistricts, via TownStreetLife)
-- et ALLÉES qui relient chaque lieu au réseau (trottoirs du boulevard,
-- des rues, allées existantes) : on n'arrive plus nulle part par la pelouse.
----------------------------------------------------------------------

-- La place la plus VIDE de l'anneau intérieur pour un objet de rayon `r`
-- (le plus loin possible de tout ce qui est déjà réservé)
local function emptiest(geo: TownKit.Geo, r: number, r0: number): Vector3?
	local O = geo.Origin
	local best, bestScore = nil, -math.huge
	local rMin, rMax = r0 + r, geo.Inner - r - 4
	if rMax < rMin then
		return nil
	end
	for deg = 0, 358, 2 do
		local ang = math.rad(deg)
		local d = rMin
		while d <= rMax do
			local p = O + Vector3.new(math.sin(ang) * d, 0, math.cos(ang) * d)
			if geo.IsFree(p, r) and not inKeepOut(geo, p, r) then
				local clear = 60
				for _, z in ipairs(geo.Reserved) do
					local dd = Vector3.new(p.X - z.P.X, 0, p.Z - z.P.Z).Magnitude - z.R - r
					if dd < clear then
						clear = dd
					end
				end
				if clear > bestScore then
					best, bestScore = p, clear
				end
			end
			d += 4
		end
	end
	return best
end

type Feature = { Pos: Vector3, R: number, Name: string, Dest: number?, Sign: boolean? }
type Seg = { A: Vector3, B: Vector3 }

-- Réseau piéton existant (segments au sol)
local function networkSegments(geo: TownKit.Geo, footpaths: { Seg }): { Seg }
	local segs: { Seg } = {}
	local O = geo.Origin
	local m = geo.Slots
	-- trottoir intérieur du boulevard (polygone, au milieu du trottoir)
	local rv = (geo.Inner + 1.5) / math.cos(geo.HalfAngle)
	for k = 0, m - 1 do
		local a1 = geo.SlotAngle(k) - geo.HalfAngle
		local a2 = geo.SlotAngle(k) + geo.HalfAngle
		table.insert(segs, { A = O + Vector3.new(math.sin(a1) * rv, 0, math.cos(a1) * rv), B = O + Vector3.new(math.sin(a2) * rv, 0, math.cos(a2) * rv) })
	end
	-- trottoirs extérieurs des rues radiales
	for _, slot in ipairs(geo.Streets) do
		local d = geo.Dir(geo.SlotAngle(slot))
		local side = Vector3.new(d.Z, 0, -d.X)
		local w = slot == 0 and 20 or 12
		for _, sx in ipairs({ -1, 1 }) do
			table.insert(segs, { A = O + d * geo.StreetStart + side * (sx * w), B = O + d * geo.Inner + side * (sx * w) })
		end
	end
	for _, f in ipairs(footpaths) do
		table.insert(segs, f)
	end
	return segs
end

local function closestOnSeg(a: Vector3, b: Vector3, p: Vector3): Vector3
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local t = ab.Magnitude > 1e-3 and math.clamp(Vector3.new(p.X - a.X, 0, p.Z - a.Z):Dot(ab) / ab:Dot(ab), 0, 1) or 0
	return Vector3.new(a.X, 0, a.Z) + ab * t
end

-- Relie `f` au réseau par l'allée pavée la plus courte qui ne traverse rien
-- (réserves des autres lieux, rues) ; renvoie le point d'arrivée ou nil
local function connect(geo: TownKit.Geo, segs: { Seg }, f: Feature, seed: number): Vector3?
	local p = Vector3.new(f.Pos.X, 0, f.Pos.Z)
	local best: { Vector3 }? = nil
	local bestLen = math.huge
	-- (le point le plus proche de chaque segment, puis des points décalés
	-- le long du segment : une allée en biais contourne un obstacle)
	local cands = {}
	for _, sgm in ipairs(segs) do
		local q0 = closestOnSeg(sgm.A, sgm.B, p)
		local a0 = Vector3.new(sgm.A.X, 0, sgm.A.Z)
		local ab = Vector3.new(sgm.B.X - sgm.A.X, 0, sgm.B.Z - sgm.A.Z)
		local L = ab.Magnitude
		table.insert(cands, q0)
		if L > 1 then
			local t0 = (q0 - a0).Magnitude
			for _, dt in ipairs({ -8, 8, -16, 16, -26, 26 }) do
				local t = t0 + dt
				if t > 0 and t < L then
					table.insert(cands, a0 + ab.Unit * t)
				end
			end
		end
	end
	for _, q in ipairs(cands) do
		local dir = q - p
		local len = dir.Magnitude
		if len > f.R + 1 and len - f.R < bestLen and len - f.R < 130 then
			local e = p + dir.Unit * (f.R - 0.5)
			-- libre : aucune autre réserve traversée, ni rue (sauf aux deux bouts)
			local ok = true
			local total = (q - e).Magnitude
			local t = 2
			while t < total - 4 do
				local x = e + (q - e).Unit * t
				local wx = Vector3.new(x.X, geo.Origin.Y, x.Z)
				if not geo.IsFree(wx, 1.2) then
					-- (IsFree regarde aussi les réserves : on ignore celle du lieu lui-même)
					local own = true
					for _, z in ipairs(geo.Reserved) do
						local dz = Vector3.new(x.X - z.P.X, 0, x.Z - z.P.Z).Magnitude
						if dz < z.R + 1.2 and Vector3.new(z.P.X - p.X, 0, z.P.Z - p.Z).Magnitude > f.R + 1 then
							own = false
							break
						end
					end
					local flatX = Vector3.new(x.X - geo.Origin.X, 0, x.Z - geo.Origin.Z)
					local street = false
					for _, slot in ipairs(geo.Streets) do
						local d = geo.Dir(geo.SlotAngle(slot))
						local along = flatX:Dot(d)
						local sideD = math.abs(flatX.X * d.Z - flatX.Z * d.X)
						if along > 0 and sideD < (slot == 0 and 22 or 14) then
							street = true
							break
						end
					end
					if not own or street or flatX.Magnitude < WorldLayout.PLAZA_R + 26 or geo.PolyRadius(wx) > geo.Inner - 2 then
						ok = false
						break
					end
				end
				t += 2
			end
			if ok then
				best = { e, q }
				bestLen = len - f.R
			end
		end
	end
	if not best then
		return nil
	end
	local e, q = best[1], best[2]
	local y = geo.Origin.Y + GROUND_Y
	local total = (q - e).Magnitude
	local n = math.max(1, math.ceil(total / 30))
	for i = 0, n - 1 do
		local a = e:Lerp(q, i / n)
		local b = e:Lerp(q, (i + 1) / n)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z)) * CFrame.Angles(0, math.pi / 2, 0)
		TownKit.LifeSpot("Walkway", cf, seed * 10 + i, Vector3.new((b - a).Magnitude + 0.02, 2, 4.5))
	end
	for t = 0, total, 5 do
		local x = e:Lerp(q, t / math.max(total, 1))
		geo.Reserve(Vector3.new(x.X, geo.Origin.Y, x.Z), 3)
	end
	table.insert(segs, { A = e, B = q })
	-- poteau indicateur au départ de l'allée (côté réseau)
	if f.Sign then
		local side = Vector3.new(-(q - e).Unit.Z, 0, (q - e).Unit.X)
		local at = q - (q - e).Unit * 3 + side * 3.4
		TownKit.LifeSpot("Direction", CFrame.new(Vector3.new(at.X, y, at.Z)), seed)
	end
	return q
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TownNature.Build(folder: Instance, geo: TownKit.Geo): number
	local nature = Instance.new("Folder")
	nature.Name = "Nature"
	nature.Parent = folder
	local O = geo.Origin
	-- pré (sous tout le reste) et murs invisibles
	-- (v9.8, CITY98) 4 quarts de 2048 x 2048 (taille maximale d'une pièce)
	-- au lieu d'un disque de rayon 1000 : les montagnes et la ville
	-- lointaine des grandes villes (12 parcelles, jusqu'à ~1050 studs) ne
	-- dépassent plus du pré. Côtés jointifs, sans chevauchement.
	for _, qx in ipairs({ -1, 1 }) do
		for _, qz in ipairs({ -1, 1 }) do
			part(nature, "Meadow", Vector3.new(2048, 4, 2048), CFrame.new(O + Vector3.new(qx * 1024, GROUND_Y - 2, qz * 1024)), C.Grass, M.Grass, "solid")
		end
	end
	local walls = 40
	for i = 1, walls do
		local a = (i - 0.5) / walls * math.pi * 2
		local p = O + Vector3.new(math.sin(a) * geo.Town, 30, math.cos(a) * geo.Town)
		part(nature, "Edge", Vector3.new(2 * math.pi * geo.Town / walls + 4, 64, 2), CFrame.lookAt(p, O + Vector3.new(0, 30, 0)), C.White, M.SmoothPlastic, "ghost")
	end
	-- quartiers de l'anneau
	local aR = geo.SlotAngle(geo.SideR)
	local aL = geo.SlotAngle(geo.SideL)
	local r0 = WorldLayout.PLAZA_R + 30
	local depth = geo.Inner - r0
	local mid = r0 + depth / 2
	local function frame(angle: number, dist: number): CFrame
		local p = geo.At(angle, dist)
		return CFrame.lookAt(p, Vector3.new(O.X, p.Y, O.Z))
	end
	-- (v9.7) un seul grand plan d'eau, un peu plus large que l'ancien disque
	local lakeR = math.min(math.clamp(depth / 2 - 12, 20, 42) * 1.15, depth / 2 - 18)
	local lakeAngle, lakeDist = (aR + math.pi) / 2 + 0.05, mid + 4
	local bridgeFoot = lake(nature, geo, geo.At(lakeAngle, lakeDist), lakeR)
	local anchors = {
		{ lakeAngle, lakeDist - lakeR - 4, bridgeFoot },
		{ aR * 0.42, r0 + 22 - 16 },
		{ (aL + math.pi * 2) / 2, r0 + 24 - 18 },
		{ (math.pi + aL) / 2 + 0.06, r0 + 22 - 14 },
	}
	-- (v9.9, CITY99) lieux à relier au réseau par une allée + repères des
	-- poteaux indicateurs
	local features: { Feature } = {}
	local function faceCenter(p: Vector3): CFrame
		return CFrame.lookAt(p, Vector3.new(O.X, p.Y, O.Z))
	end
	playground(nature, geo, frame(aR * 0.42, r0 + 22))
	TownKit.LifeSpot("Dest", frame(aR * 0.42, r0 + 22), 5)
	local picnicCF = frame(aR * 0.62, math.min(geo.Inner - 14, r0 + 50))
	picnic(nature, geo, picnicCF, 3)
	table.insert(features, { Pos = picnicCF.Position, R = 9, Name = "Picnic" })
	market(nature, geo, frame((aL + math.pi * 2) / 2, r0 + 24))
	TownKit.LifeSpot("Dest", frame((aL + math.pi * 2) / 2, r0 + 24), 16)
	-- (v9.9, FAIR99 : la fête foraine réserve ses nouveaux manèges AVANT la
	-- nature ; jardin fleuri et terrain de basket vont ailleurs si leur place
	-- est prise)
	local gardenCF = frame((math.pi + aL) / 2 + 0.06, r0 + 22)
	local gardenMoved = false
	if not geo.IsFree((gardenCF * CFrame.new(0, 0, 3)).Position, 16) then
		local p = emptiest(geo, 16, r0)
		if p then
			gardenCF = faceCenter(p) * CFrame.new(0, 0, -3)
			gardenMoved = true
		else
			gardenCF = nil :: any
		end
	end
	if gardenCF then
		flowerGarden(nature, geo, gardenCF)
		TownKit.LifeSpot("Dest", gardenCF, 14)
		if gardenMoved then
			table.insert(features, { Pos = (gardenCF * CFrame.new(0, 0, 3)).Position, R = 16, Name = "FlowerGarden", Sign = true })
		end
	end
	if depth > 70 then
		local courtCF = frame((math.pi + aL) / 2 - 0.05, geo.Inner - 18)
		if not geo.IsFree(courtCF.Position, 17) then
			local p = emptiest(geo, 17, r0)
			courtCF = p and faceCenter(p) or nil :: any
		end
		if courtCF then
			court(nature, geo, courtCF)
			table.insert(features, { Pos = courtCF.Position, R = 17, Name = "Court", Dest = 12 })
		end
	end
	-- grandes villes : terrain de foot + champ de tulipes là où il y a de la place
	if depth > 110 then
		local soccerDone = false
		for _, spot in ipairs({ { (aL + math.pi * 2) / 2 + 0.04, geo.Inner - 34 }, { aR * 0.55, geo.Inner - 34 }, { (aR + math.pi) / 2, geo.Inner - 30 } }) do
			local p = geo.At(spot[1], spot[2])
			if geo.IsFree(p, 26) then
				soccer(nature, geo, frame(spot[1], spot[2]))
				TownKit.LifeSpot("Dest", frame(spot[1], spot[2]), 12)
				table.insert(anchors, { spot[1], spot[2] - 24 })
				soccerDone = true
				break
			end
		end
		-- (v9.9, CITY99) places prévues prises (nouveaux manèges de la fête) :
		-- le terrain de foot va dans le coin le plus vide, relié par une allée
		if not soccerDone then
			local p = emptiest(geo, 26, r0)
			if p then
				local cf = faceCenter(p + Vector3.new(0, 0, 0))
				soccer(nature, geo, cf)
				TownKit.LifeSpot("Dest", cf, 12)
				table.insert(features, { Pos = p, R = 23, Name = "Soccer", Sign = true })
			end
		end
		for _, spot in ipairs({ { aR * 0.3, geo.Inner - 30 }, { (math.pi + aL) / 2 - 0.1, mid + 10 }, { (aL + math.pi * 2) / 2 - 0.12, mid + 16 } }) do
			local p = geo.At(spot[1], spot[2])
			if geo.IsFree(p, 22) then
				tulips(nature, geo, frame(spot[1], spot[2]))
				table.insert(features, { Pos = p, R = 14, Name = "Tulips" })
				break
			end
		end
	end
	-- allées en gravier : de l'arrière des boutiques de la place vers chaque lieu
	local paths = TownKit.Model(nature, "Footpaths")
	local footSegs: { Seg } = {}
	for i, anchor in ipairs(anchors) do
		-- (v9.9 : pas d'allée vers l'ancienne place du jardin fleuri s'il a bougé)
		if not (i == 4 and (gardenMoved or not gardenCF)) then
			local a0, b0 = geo.At(anchor[1], r0 - 1), anchor[3] or geo.At(anchor[1], anchor[2])
			footpath(paths, geo, a0, b0, i)
			table.insert(footSegs, { A = Vector3.new(a0.X, 0, a0.Z), B = Vector3.new(b0.X, 0, b0.Z) })
		end
	end
	-- (v9.7) kiosque du parc + massif fleuri et buissons au départ des allées
	for _, spot in ipairs({ { aR * 0.86, r0 + 18 }, { lakeAngle - 0.3, r0 + 14 }, { aR * 0.2, r0 + 44 } }) do
		local p = geo.At(spot[1], spot[2])
		if geo.IsFree(p, 11) then
			gazebo(nature, geo, frame(spot[1], spot[2]))
			table.insert(features, { Pos = p, R = 8, Name = "Gazebo" })
			break
		end
	end
	local greens = TownKit.Model(nature, "ParkGreens")
	for i, anchor in ipairs(anchors) do
		for _, s in ipairs({ -1, 1 }) do
			local p = geo.At(anchor[1] + s * 0.05, r0 + 4)
			if i == 1 and s > 0 and geo.IsFree(p, 5) then
				TownKit.FlowerBed(greens, p + Vector3.new(0, GROUND_Y - 0.3, 0), 3.4, 40 + i)
				geo.Reserve(p, 5)
			elseif geo.IsFree(p, 3) then
				TownKit.Bush(greens, p + Vector3.new(0, GROUND_Y, 0), 2.4 + hash(i, s + 3), 30 + i * 2 + s, (i + s) % 2 == 0 and TownKit.FLOWERS[i % #TownKit.FLOWERS + 1] or nil)
				geo.Reserve(p, 3)
			end
		end
	end
	-- (v9.8, CITY98) statues, petit marché, tables d'échecs (construits côté client)
	for _, f in ipairs(lifeParks(geo, r0)) do
		table.insert(features, f)
	end
	-- (v9.9, CITY99) NOUVEAUX LIEUX dans les coins les plus vides : skatepark,
	-- jardins partagés, coin ping-pong / pétanque / fitness (client : TownDistricts)
	for i, d in ipairs({
		{ Kind = "SkatePark", R = 19, Dest = 9 },
		{ Kind = "CommunityGarden", R = 17, Dest = 10 },
		{ Kind = "SportsCorner", R = 15, Dest = 17 },
	}) do
		local p = emptiest(geo, d.R, r0)
		if p then
			local cf = faceCenter(p + Vector3.new(0, GROUND_Y, 0))
			TownKit.LifeSpot(d.Kind, cf, 900 + i)
			geo.Reserve(p, d.R)
			table.insert(features, { Pos = p, R = d.R, Name = d.Kind, Dest = d.Dest, Sign = true })
		end
	end
	-- repères des lieux (poteaux indicateurs) : lac, fête foraine
	TownKit.LifeSpot("Dest", CFrame.new(geo.At(lakeAngle, lakeDist)), 4)
	local fairCF = WorldLayout.FairCFrame()
	TownKit.LifeSpot("Dest", fairCF * CFrame.new(0, 0, -WorldLayout.FAIR_D / 2), 2)
	-- ALLÉES : chaque lieu est relié au réseau (du plus proche au plus loin)
	local segs = networkSegments(geo, footSegs)
	table.sort(features, function(a, b)
		return (a.Pos - O).Magnitude < (b.Pos - O).Magnitude
	end)
	local linked = 0
	local unlinked = {}
	for i, f in ipairs(features) do
		if f.Dest then
			TownKit.LifeSpot("Dest", CFrame.new(f.Pos), f.Dest)
		end
		if connect(geo, segs, f, 950 + i) then
			linked += 1
		else
			table.insert(unlinked, f.Name)
		end
	end
	nature:SetAttribute("Linked", linked)
	nature:SetAttribute("Unlinked", table.concat(unlinked, ","))
	nature:SetAttribute("Features", #features)
	local trees = scatterTrees(nature, geo, math.clamp(math.floor(depth * 0.28), 22, geo.Slots >= 11 and 46 or 36))
	belt(nature, geo)
	hills(nature, geo)
	TownBuildings.Skyline(nature, O, math.rad(125), math.rad(235), geo.Town + 320, 20)
	-- (v9.8, CITY98) publie les emplacements du mobilier client + chemins des passants
	TownKit.PublishLife(folder.Parent or folder)
	return trees
end

return TownNature
