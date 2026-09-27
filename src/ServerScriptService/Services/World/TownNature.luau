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

local TownNature = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part
local hash = TownKit.Hash

local GROUND_Y = WorldLayout.GROUND_Y

----------------------------------------------------------------------
-- Lac
----------------------------------------------------------------------

local function lake(folder: Instance, geo: TownKit.Geo, center: Vector3, radius: number)
	local model = TownKit.Model(folder, "Lake")
	local towardPlaza = (Vector3.new(geo.Origin.X, center.Y, geo.Origin.Z) - center).Unit
	local side = Vector3.new(-towardPlaza.Z, 0, towardPlaza.X)
	local lobes = {
		{ center, radius },
		{ center + side * radius * 0.75 + towardPlaza * radius * 0.2, radius * 0.62 },
		{ center - side * radius * 0.7 - towardPlaza * radius * 0.15, radius * 0.55 },
	}
	-- rives (sable), fond, eau : trois couches de disques
	for _, lobe in ipairs(lobes) do
		TownKit.Disc(model, "Shore", lobe[1] + Vector3.new(0, GROUND_Y + 0.08, 0), lobe[2] + 3, 0.4, C.Sand, M.Sand, "solid")
	end
	for _, lobe in ipairs(lobes) do
		TownKit.Disc(model, "LakeBed", lobe[1] + Vector3.new(0, GROUND_Y + 0.12, 0), lobe[2], 0.4, C.WaterDeep, M.Slate, "deco")
	end
	for _, lobe in ipairs(lobes) do
		local water = TownKit.Disc(model, "Water", lobe[1] + Vector3.new(0, GROUND_Y + 0.35, 0), lobe[2] - 0.1, 0.2, C.Water, M.Glass, "deco")
		water.Transparency = 0.3
		water.Reflectance = 0.15
	end
	-- nénuphars, roseaux, canards
	for i = 1, 7 do
		local a = hash(i, 51) * math.pi * 2
		local r = radius * (0.35 + hash(i, 52) * 0.5)
		local p = center + Vector3.new(math.cos(a) * r, GROUND_Y + 0.5, math.sin(a) * r)
		TownKit.Disc(model, "LilyPad", p, 1.1 + hash(i, 53) * 0.6, 0.1, Color3.fromRGB(110, 190, 110), M.Grass, "deco")
		if i % 3 == 0 then
			TownKit.Ball(model, "Lily", p + Vector3.new(0, 0.3, 0), 0.7, Color3.fromRGB(255, 190, 220), M.SmoothPlastic, "deco")
		end
	end
	for i = 1, 10 do
		local a = hash(i, 54) * math.pi * 2
		local lobe = lobes[i % 3 + 1]
		local p = lobe[1] + Vector3.new(math.cos(a) * (lobe[2] - 0.8), GROUND_Y, math.sin(a) * (lobe[2] - 0.8))
		TownKit.Column(model, "Reed", p, 3 + hash(i, 55) * 2, 0.25, Color3.fromRGB(96, 150, 80), M.Grass, "deco")
		TownKit.Column(model, "ReedTop", p + Vector3.new(0, 3 + hash(i, 55) * 2, 0), 1, 0.45, Color3.fromRGB(130, 90, 60), M.Fabric, "deco")
	end
	for i = 1, 3 do
		local p = center + side * (i - 2) * radius * 0.35 - towardPlaza * radius * 0.35 + Vector3.new(0, GROUND_Y + 0.8, 0)
		local look = CFrame.lookAt(p, p + side)
		TownKit.Ball(model, "Duck", p, 1.3, i == 2 and C.White or Color3.fromRGB(255, 230, 120), M.SmoothPlastic, "deco")
		TownKit.Ball(model, "DuckHead", (look * CFrame.new(0, 0.7, -0.55)).Position, 0.8, i == 2 and C.White or Color3.fromRGB(255, 230, 120), M.SmoothPlastic, "deco")
		part(model, "Beak", Vector3.new(0.3, 0.15, 0.4), look * CFrame.new(0, 0.65, -1.05), Color3.fromRGB(255, 150, 60), M.SmoothPlastic, "deco")
	end
	-- pont en bois en arc sur le lac (du côté de la place vers le fond)
	local a = center - towardPlaza * (radius + 4) + side * radius * 0.1
	local b = center + towardPlaza * (radius + 4) + side * radius * 0.1
	local n = 7
	local bridge = TownKit.Model(model, "Bridge")
	local prev = a + Vector3.new(0, GROUND_Y + 0.4, 0)
	for i = 1, n do
		local t = i / n
		local p = a:Lerp(b, t) + Vector3.new(0, GROUND_Y + 0.4 + math.sin(t * math.pi) * 2.8, 0)
		local deck = TownKit.Beam(bridge, "Deck", prev, p, 6, 0.5, C.Wood, M.WoodPlanks, "solid")
		deck.CastShadow = true
		for _, sx in ipairs({ -1, 1 }) do
			local off = side * sx * 2.9
			TownKit.Beam(bridge, "Rail", prev + off + Vector3.new(0, 2.6, 0), p + off + Vector3.new(0, 2.6, 0), 0.3, 0.3, C.WoodLight, M.Wood, "deco")
			TownKit.Column(bridge, "Baluster", p + off, 2.6, 0.35, C.WoodLight, M.Wood, "deco")
		end
		prev = p
	end
	-- ponton + barque
	local dockDir = side
	local dock = center + dockDir * (radius * 0.9) + Vector3.new(0, GROUND_Y + 0.9, 0)
	part(model, "Dock", Vector3.new(4, 0.4, 10), CFrame.lookAt(dock, dock - dockDir), C.Wood, M.WoodPlanks, "solid")
	for _, dz in ipairs({ -4, 0, 4 }) do
		TownKit.Column(model, "DockPost", (CFrame.lookAt(dock, dock - dockDir) * CFrame.new(1.8, -0.9, dz)).Position, 1.8, 0.5, C.Bark, M.Wood, "deco")
	end
	local boat = CFrame.lookAt(dock, dock - dockDir) * CFrame.new(-4.4, -0.3, 2.5)
	part(model, "Boat", Vector3.new(3, 1.2, 7), boat, Color3.fromRGB(255, 170, 190), M.WoodPlanks, "deco")
	part(model, "BoatSeat", Vector3.new(2.8, 0.2, 1), boat * CFrame.new(0, 0.4, 0), C.WoodLight, M.WoodPlanks, "deco")
	geo.Reserve(center, radius + 4)
	for i = 2, 3 do
		geo.Reserve(lobes[i][1], lobes[i][2] + 4)
	end
end

----------------------------------------------------------------------
-- Aire de jeux, pique-nique
----------------------------------------------------------------------

local function playground(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "Playground")
	TownKit.Disc(model, "Sand", (cf * CFrame.new(0, GROUND_Y + 0.12, 0)).Position, 15, 0.4, C.Sand, M.Sand, "solid")
	TownKit.Disc(model, "Border", (cf * CFrame.new(0, GROUND_Y + 0.05, 0)).Position, 15.8, 0.4, C.WoodLight, M.Wood, "deco")
	-- toboggan : tour, échelle, glissière
	local slide = cf * CFrame.new(-6, GROUND_Y, 0)
	for _, x in ipairs({ -1.4, 1.4 }) do
		for _, z in ipairs({ -1.4, 1.4 }) do
			part(model, "TowerPost", Vector3.new(0.5, 7, 0.5), slide * CFrame.new(x, 3.5, z), C.Sky, M.Metal, "prop")
		end
	end
	part(model, "TowerDeck", Vector3.new(3.6, 0.4, 3.6), slide * CFrame.new(0, 4.6, 0), C.WoodLight, M.WoodPlanks, "solid")
	part(model, "TowerRoof", Vector3.new(4.2, 0.4, 4.2), slide * CFrame.new(0, 7.2, 0), C.Pink, M.SmoothPlastic, "deco")
	TownKit.Wedge(model, "Chute", Vector3.new(2, 4.6, 7), slide * CFrame.new(0, 2.3, 5.3) * CFrame.Angles(0, math.pi, 0), C.Lemon, M.SmoothPlastic, "solid")
	for i = 0, 4 do
		part(model, "Rung", Vector3.new(2.4, 0.25, 0.25), slide * CFrame.new(0, 0.8 + i * 0.9, -2.2), C.Metal, M.Metal, "deco")
	end
	for _, x in ipairs({ -1.2, 1.2 }) do
		part(model, "Ladder", Vector3.new(0.25, 4.8, 0.25), slide * CFrame.new(x, 2.4, -2.2), C.Metal, M.Metal, "deco")
	end
	-- balançoires
	local swing = cf * CFrame.new(6, GROUND_Y, -2)
	for _, x in ipairs({ -4, 4 }) do
		part(model, "SwingLeg", Vector3.new(0.4, 8, 0.4), swing * CFrame.new(x, 4, -1.2) * CFrame.Angles(math.rad(-10), 0, 0), C.Mint, M.Metal, "prop")
		part(model, "SwingLeg", Vector3.new(0.4, 8, 0.4), swing * CFrame.new(x, 4, 1.2) * CFrame.Angles(math.rad(10), 0, 0), C.Mint, M.Metal, "prop")
	end
	part(model, "SwingBar", Vector3.new(8.6, 0.4, 0.4), swing * CFrame.new(0, 7.9, 0), C.Mint, M.Metal, "deco")
	for _, x in ipairs({ -1.8, 1.8 }) do
		for _, dx in ipairs({ -0.6, 0.6 }) do
			part(model, "Rope", Vector3.new(0.1, 5.6, 0.1), swing * CFrame.new(x + dx, 5, 0), C.MetalLight, M.Metal, "deco")
		end
		part(model, "SwingSeat", Vector3.new(1.6, 0.25, 0.8), swing * CFrame.new(x, 2.2, 0), C.Pink, M.Rubber, "deco")
	end
	-- tape-cul + animal à ressort
	local seesaw = cf * CFrame.new(1, GROUND_Y, 8) * CFrame.Angles(0, math.rad(20), 0)
	part(model, "Pivot", Vector3.new(0.8, 1.2, 0.8), seesaw * CFrame.new(0, 0.6, 0), C.Metal, M.Metal, "prop")
	part(model, "Plank", Vector3.new(0.9, 0.3, 9), seesaw * CFrame.new(0, 1.4, 0) * CFrame.Angles(math.rad(12), 0, 0), C.Peach, M.WoodPlanks, "deco")
	local rider = cf * CFrame.new(8, GROUND_Y, 7)
	TownKit.Column(model, "Spring", (rider).Position, 1.4, 0.5, C.MetalLight, M.Metal, "deco")
	part(model, "RiderBody", Vector3.new(1.2, 1.4, 2.6), rider * CFrame.new(0, 2.1, 0), C.Lilac, M.SmoothPlastic, "prop")
	TownKit.Ball(model, "RiderHead", (rider * CFrame.new(0, 3.2, -1.2)).Position, 1.6, C.Lilac, M.SmoothPlastic, "deco")
	geo.Reserve(cf.Position, 17)
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
		local s = cf * CFrame.Angles(0, math.rad((i - 2) * 50), 0) * CFrame.new(0, GROUND_Y + 0.4, -10)
		part(model, "Counter", Vector3.new(7, 2.6, 2.6), s * CFrame.new(0, 1.3, 0), C.WoodLight, M.WoodPlanks, "solid")
		part(model, "Goods", Vector3.new(6.4, 0.6, 2), s * CFrame.new(0, 2.9, 0), colors[2], M.SmoothPlastic, "deco")
		for _, x in ipairs({ -3.3, 3.3 }) do
			part(model, "Pole", Vector3.new(0.3, 7, 0.3), s * CFrame.new(x, 3.5, 1.2), C.White, M.Wood, "deco")
		end
		for k = 0, 5 do
			part(model, "Canopy", Vector3.new(7.6 / 6, 0.2, 4.4), s * CFrame.new(-3.8 + (k + 0.5) * 7.6 / 6, 7, -0.2) * CFrame.Angles(math.rad(-14), 0, 0), k % 2 == 0 and colors[1] or C.White, M.Fabric, k == 0 and "decoS" or "deco")
		end
	end
	-- food truck (camionnette + passe-plat + enseigne)
	local truck = cf * CFrame.new(0, GROUND_Y, 8) * CFrame.Angles(0, math.rad(90), 0)
	TownKit.Car(model, truck, Color3.fromRGB(255, 214, 120), "Van")
	part(model, "Hatch", Vector3.new(0.2, 1.8, 5), truck * CFrame.new(-2.4, 4.4, 0.8), Color3.fromRGB(60, 50, 70), M.SmoothPlastic, "deco")
	part(model, "HatchRoof", Vector3.new(2.2, 0.2, 5.4), truck * CFrame.new(-3.4, 5.6, 0.8) * CFrame.Angles(0, 0, math.rad(-15)), C.Pink, M.Fabric, "deco")
	local sign = part(model, "TruckSign", Vector3.new(0.3, 1.6, 6), truck * CFrame.new(0, 6.6, 0.8), C.White, M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(sign, Enum.NormalId.Left, 30, nil, 200, 0)
	TownKit.Label(body, "Text", "🌮 Taco Party", 0.03, 0.05, 0.94, 0.9, C.HotPink, Enum.Font.FredokaOne, false)
	geo.Reserve(cf.Position, 19)
end

----------------------------------------------------------------------
-- Jardin fleuri (pergola) + terrain de basket
----------------------------------------------------------------------

local function flowerGarden(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "FlowerGarden")
	for i = 0, 5 do
		local row = cf * CFrame.new(0, GROUND_Y, -10 + i * 4)
		part(model, "Soil", Vector3.new(20, 0.6, 2.4), row * CFrame.new(0, 0.3, 0), Color3.fromRGB(120, 86, 64), M.Ground, "prop")
		part(model, "Flowers", Vector3.new(19, 1, 1.8), row * CFrame.new(0, 1.1, 0), TownKit.FLOWERS[i % #TownKit.FLOWERS + 1], M.Grass, "deco")
	end
	-- pergola au milieu
	local p = cf * CFrame.new(0, GROUND_Y, 16)
	for _, x in ipairs({ -4, 4 }) do
		for _, z in ipairs({ -3, 3 }) do
			part(model, "PergolaPost", Vector3.new(0.7, 8, 0.7), p * CFrame.new(x, 4, z), C.White, M.Wood, "prop")
		end
	end
	for i = 0, 4 do
		part(model, "PergolaBeam", Vector3.new(10, 0.4, 0.5), p * CFrame.new(0, 8.2, -3 + i * 1.5), C.White, M.Wood, "deco")
	end
	part(model, "Vine", Vector3.new(9, 0.6, 7), p * CFrame.new(0, 8.7, 0), Color3.fromRGB(200, 150, 230), M.Grass, "deco")
	TownKit.Bench(model, p * CFrame.new(0, 0, 1.2))
	geo.Reserve((cf * CFrame.new(0, 0, 3)).Position, 16)
end

local function court(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "Court")
	part(model, "Floor", Vector3.new(30, 0.5, 17), cf * CFrame.new(0, GROUND_Y + 0.1, 0), Color3.fromRGB(120, 150, 214), M.Rubber, "solid")
	part(model, "Paint", Vector3.new(26, 0.1, 13), cf * CFrame.new(0, GROUND_Y + 0.38, 0), Color3.fromRGB(236, 150, 120), M.Rubber, "deco")
	part(model, "MidLine", Vector3.new(0.3, 0.12, 13), cf * CFrame.new(0, GROUND_Y + 0.4, 0), C.White, M.SmoothPlastic, "deco")
	TownKit.Disc(model, "Circle", (cf * CFrame.new(0, GROUND_Y + 0.42, 0)).Position, 2.4, 0.1, C.White, M.SmoothPlastic, "deco")
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
-- Paysage lointain
----------------------------------------------------------------------

local function hills(folder: Instance, geo: TownKit.Geo)
	local model = TownKit.Model(folder, "Hills")
	local O = geo.Origin
	local n = 20
	for i = 1, n do
		local a = (i + hash(i, 61) * 0.6) / n * math.pi * 2
		local dist = geo.Town + 90 + hash(i, 62) * 120
		local d = 160 + hash(i, 63) * 170
		local p = O + Vector3.new(math.sin(a) * (dist + d * 0.25), GROUND_Y - d * 0.42, math.cos(a) * (dist + d * 0.25))
		local tone = Color3.fromRGB(116, 186, 104):Lerp(Color3.fromRGB(150, 206, 130), hash(i, 64))
		TownKit.Ball(model, "Hill", p, d, tone, M.Grass, "deco")
	end
	-- montagnes enneigées (pyramides approchées) dans le dos de l'entrée
	for i = 1, 6 do
		local a = math.pi + (i - 3.5) * 0.32 + (hash(i, 65) - 0.5) * 0.1
		local dist = geo.Town + 360 + hash(i, 66) * 80
		local h = 90 + hash(i, 67) * 80
		local w = h * 1.5
		local base = O + Vector3.new(math.sin(a) * dist, GROUND_Y - 4, math.cos(a) * dist)
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
	local placed = 0
	local r0 = WorldLayout.PLAZA_R + 30
	local r1 = geo.Inner
	for i = 1, target * 8 do
		if placed >= target then
			break
		end
		local a = hash(i, 71) * math.pi * 2
		local r = r0 + math.sqrt(hash(i, 72)) * (r1 - r0)
		local p = geo.Origin + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
		local size = 10 + hash(i, 73) * 8
		if geo.IsFree(p, 4) then
			local kind = hash(i, 74) < 0.15 and 3 or (hash(i, 75) < 0.2 and 2 or (hash(i, 76) < 0.3 and 4 or 1))
			TownKit.Tree(model, p + Vector3.new(0, GROUND_Y, 0), size, i, kind)
			geo.Reserve(p, 6)
			placed += 1
		end
	end
	return placed
end

-- Bois derrière les parcelles + arbres dans les coins entre deux parcelles
local function belt(folder: Instance, geo: TownKit.Geo)
	local model = TownKit.Model(folder, "Woods")
	local O = geo.Origin
	local m = geo.Slots
	local back = geo.PlotR + WorldLayout.PLOT_D / 2
	local perSlot = 6
	for k = 0, m - 1 do
		for j = 1, perSlot do
			local a = geo.SlotAngle(k) + (j - 0.5 - perSlot / 2) / perSlot * (math.pi * 2 / m) + (hash(k, j) - 0.5) * 0.05
			local r = back + 10 + hash(j, k + 40) * (WorldLayout.TOWN_MARGIN - 22)
			local p = O + Vector3.new(math.sin(a) * r, GROUND_Y, math.cos(a) * r)
			-- (pas d'arbre sur la route d'arrivée derrière la porte)
			local rel = p - O
			if not (math.abs(rel.X) < 58 and rel.Z > 0 and rel.Z < geo.Gate + 110) then
				TownKit.Tree(model, p, 14 + hash(k, j + 9) * 10, k * 50 + j, hash(k, j + 20) < 0.4 and 3 or 4)
			end
		end
		-- coin entre deux parcelles (sommet du boulevard), côté extérieur
		local va = geo.SlotAngle(k) + geo.HalfAngle
		local vr = (geo.Front + 16) / math.cos(geo.HalfAngle)
		TownKit.Tree(model, O + Vector3.new(math.sin(va) * vr, GROUND_Y, math.cos(va) * vr), 13, k * 91, 1)
	end
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
	TownKit.Disc(nature, "Meadow", O + Vector3.new(0, GROUND_Y, 0), 1000, 4, C.Grass, M.Grass, "solid")
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
	local lakeR = math.clamp(depth / 2 - 12, 20, 42)
	lake(nature, geo, geo.At((aR + math.pi) / 2 + 0.05, mid + 4), lakeR)
	playground(nature, geo, frame(aR * 0.42, r0 + 22))
	picnic(nature, geo, frame(aR * 0.62, math.min(geo.Inner - 14, r0 + 50)), 3)
	market(nature, geo, frame((aL + math.pi * 2) / 2, r0 + 24))
	flowerGarden(nature, geo, frame((math.pi + aL) / 2 + 0.06, r0 + 22))
	if depth > 70 then
		court(nature, geo, frame((math.pi + aL) / 2 - 0.05, geo.Inner - 18))
	end
	local trees = scatterTrees(nature, geo, math.clamp(math.floor(depth * 0.35), 25, 55))
	belt(nature, geo)
	hills(nature, geo)
	TownBuildings.Skyline(nature, O, math.rad(125), math.rad(235), geo.Town + 200, 26)
	return trees
end

return TownNature
