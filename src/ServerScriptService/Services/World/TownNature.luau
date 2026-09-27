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
	local column = TownKit.Egg(model, "JetColumn", L * CFrame.new(jx, LAKE.WaterTop + 3.2, jz), Vector3.new(0.8, 6.4, 0.8), Color3.fromRGB(226, 244, 255), M.Glass, "deco")
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
-- Sol souple en couleurs, petite clôture avec portillon (côté place),
-- toboggan (tour, toit, échelle, glissière à rebords), balançoires à
-- chaînes (vrais Seat), cage à grimper, bac à sable (jouets : client),
-- tape-cul, lapin à ressort, tourniquet. `cf` : centre au sol, -Z vers la
-- place. Tout ce qui se touche est solide, le reste est du décor.

local PW, PD = 38, 30 -- (largeur, profondeur de l'aire)

local function playground(folder: Instance, geo: TownKit.Geo, cf: CFrame)
	local model = TownKit.Model(folder, "Playground")
	local g = cf * CFrame.new(0, GROUND_Y, 0)
	model:SetAttribute("NearDetail", "Playground")
	model:SetAttribute("DetailCF", g)
	-- sol souple + taches de couleur (à des hauteurs distinctes)
	TownKit.Part(model, "SoftFloor", Vector3.new(PW, 0.3, PD), g * CFrame.new(0, 0.05, 0), Color3.fromRGB(236, 150, 128), M.Rubber, "solid")
	local patches = { { -9, -6, 5.2, C.Mint }, { 9, 6, 5.6, C.Lilac }, { 1, 0, 6.4, C.Lemon }, { -11, 8, 4.6, C.Sky } }
	for i, pt in ipairs(patches) do
		TownKit.Disc(model, "SoftPatch", (g * CFrame.new(pt[1], 0.22 + i * 0.03, pt[2])).Position, pt[3], 0.1, pt[4], M.Rubber, "deco")
	end
	-- clôture basse (poteaux + 2 lisses) avec portillon ouvert face à la place
	local fence = Color3.fromRGB(255, 255, 255)
	local rail = Color3.fromRGB(120, 196, 226)
	local hw, hd = PW / 2 + 0.6, PD / 2 + 0.6
	local sides = {
		{ Vector3.new(-hw, 0, hd), Vector3.new(hw, 0, hd) },
		{ Vector3.new(-hw, 0, -hd), Vector3.new(hw, 0, -hd) },
		{ Vector3.new(-hw, 0, -hd), Vector3.new(-hw, 0, hd) },
		{ Vector3.new(hw, 0, -hd), Vector3.new(hw, 0, hd) },
	}
	local gate = 2.4 -- (demi-largeur du portillon)
	for si, s in ipairs(sides) do
		local runs = { s }
		if si == 2 then
			runs = { { s[1], Vector3.new(-gate, 0, -hd) }, { Vector3.new(gate, 0, -hd), s[2] } }
		end
		for _, r in ipairs(runs) do
			local a, b = (g * CFrame.new(r[1])).Position, (g * CFrame.new(r[2])).Position
			for _, y in ipairs({ 1.1, 2.3 }) do
				TownKit.Beam(model, "FenceRail", a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), 0.18, 0.24, rail, M.Wood, "prop")
			end
			local len = (b - a).Magnitude
			local n = math.max(1, math.floor(len / 12 + 0.5))
			for k = 0, n do
				local p = a:Lerp(b, k / n)
				TownKit.Column(model, "FencePost", p, 2.7, 0.4, fence, M.Wood, "prop")
			end
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		local p = (g * CFrame.new(sx * gate, 0, -hd)).Position
		TownKit.Column(model, "GatePost", p, 3.2, 0.6, fence, M.Wood, "prop")
		TownKit.Ball(model, "GateCap", p + Vector3.new(0, 3.4, 0), 0.8, C.Pink, M.SmoothPlastic, "deco")
	end
	-- (battant ouvert vers l'extérieur)
	TownKit.Part(model, "Gate", Vector3.new(0.16, 1.6, 2.2), g * CFrame.new(-gate - 0.1, 1.6, -hd - 1.2), rail, M.Wood, "deco")
	-- TOBOGGAN : tour 4 poteaux, plancher, toit à 2 pans, échelle, glissière
	local tower = g * CFrame.new(-10, 0, 3)
	local deckY = 4.6
	for _, x in ipairs({ -1.5, 1.5 }) do
		for _, z in ipairs({ -1.5, 1.5 }) do
			TownKit.Column(model, "TowerPost", (tower * CFrame.new(x, 0, z)).Position, 8.2, 0.5, C.Sky, M.Metal, "prop")
		end
	end
	TownKit.Part(model, "TowerDeck", Vector3.new(3.6, 0.4, 3.6), tower * CFrame.new(0, deckY - 0.2, 0), C.WoodLight, M.WoodPlanks, "solid")
	for _, s in ipairs({ -1, 1 }) do
		TownKit.Wedge(model, "TowerRoof", Vector3.new(4.4, 1.6, 2.3), tower * CFrame.new(0, 9, s * 1.15) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), C.HotPink, M.SmoothPlastic, "deco")
	end
	-- échelle (côté -X) : 2 montants + 5 barreaux
	for _, z in ipairs({ -0.8, 0.8 }) do
		TownKit.Part(model, "LadderSide", Vector3.new(0.25, deckY + 1, 0.25), tower * CFrame.new(-2.4, (deckY + 1) / 2, z), C.Metal, M.Metal, "prop")
	end
	for k = 1, 5 do
		TownKit.Part(model, "Rung", Vector3.new(0.22, 0.22, 1.6), tower * CFrame.new(-2.4, k * deckY / 6 + 0.1, 0), C.Metal, M.Metal, "deco")
	end
	-- glissière (+Z) : pente continue, rebords, sortie à plat
	local top = (tower * CFrame.new(0, deckY, 1.8)).Position
	local foot = (tower * CFrame.new(0, 0.9, 8.6)).Position
	TownKit.Beam(model, "Chute", top - Vector3.new(0, 0.15, 0), foot - Vector3.new(0, 0.15, 0), 1.8, 0.3, C.Lemon, M.SmoothPlastic, "solid")
	local right = (tower.RightVector)
	for _, s in ipairs({ -1, 1 }) do
		TownKit.Beam(model, "ChuteRim", top + right * s * 1.0 + Vector3.new(0, 0.2, 0), foot + right * s * 1.0 + Vector3.new(0, 0.2, 0), 0.2, 0.6, C.Peach, M.SmoothPlastic, "deco")
	end
	TownKit.Part(model, "ChuteOut", Vector3.new(1.8, 0.3, 1.6), tower * CFrame.new(0, 0.6, 9.3), C.Lemon, M.SmoothPlastic, "prop")
	-- BALANÇOIRES : portique en A, barre, 2 sièges (vrais Seat) sur chaînes
	local swing = g * CFrame.new(9, 0, -5)
	for _, x in ipairs({ -4.6, 4.6 }) do
		for _, z in ipairs({ -1, 1 }) do
			local foot2 = (swing * CFrame.new(x, 0, z * 1.6)).Position
			local head = (swing * CFrame.new(x, 7.6, 0)).Position
			TownKit.Rod(model, "SwingLeg", foot2, head, 0.42, C.Mint, M.Metal, "prop")
		end
	end
	local bar = TownKit.Rod(model, "SwingBar", (swing * CFrame.new(-4.9, 7.6, 0)).Position, (swing * CFrame.new(4.9, 7.6, 0)).Position, 0.45, C.Mint, M.Metal, "deco")
	bar.CastShadow = true
	for _, x in ipairs({ -2, 2 }) do
		for _, dx in ipairs({ -0.7, 0.7 }) do
			TownKit.Rod(model, "Chain", (swing * CFrame.new(x + dx, 7.4, 0)).Position, (swing * CFrame.new(x + dx, 2.1, 0)).Position, 0.1, C.MetalLight, M.Metal, "deco")
		end
		local seat = TownKit.Part(model, "SwingSeat", Vector3.new(1.7, 0.3, 0.9), swing * CFrame.new(x, 1.95, 0), C.Pink, M.Rubber, "solid", "Seat")
		seat.CanTouch = true
		seat.CanQuery = true
	end
	-- CAGE À GRIMPER : cube de barres + plateforme
	local gym = g * CFrame.new(9, 0, 7.5)
	for _, x in ipairs({ -2.2, 2.2 }) do
		for _, z in ipairs({ -2.2, 2.2 }) do
			TownKit.Column(model, "GymPost", (gym * CFrame.new(x, 0, z)).Position, 4.5, 0.36, C.Lilac, M.Metal, "prop")
		end
	end
	TownKit.Part(model, "GymTop", Vector3.new(4.8, 0.3, 4.8), gym * CFrame.new(0, 4.45, 0), C.Sky, M.Rubber, "solid")
	for _, y in ipairs({ 1.5, 3 }) do
		for _, s in ipairs({ -1, 1 }) do
			TownKit.Part(model, "GymBar", Vector3.new(4.4, 0.22, 0.22), gym * CFrame.new(0, y, s * 2.2), C.Lemon, M.Metal, "deco")
		end
	end
	TownKit.Part(model, "GymBar", Vector3.new(0.22, 0.22, 4.4), gym * CFrame.new(-2.2, 2.25, 0), C.Lemon, M.Metal, "deco")
	-- BAC À SABLE : 4 planches + sable (jouets : client)
	local box = g * CFrame.new(-8, 0, -7.5)
	TownKit.Part(model, "SandPit", Vector3.new(7, 0.5, 7), box * CFrame.new(0, 0.3, 0), C.Sand, M.Sand, "deco")
	for _, s in ipairs({ -1, 1 }) do
		TownKit.Part(model, "SandBorder", Vector3.new(7.8, 0.8, 0.4), box * CFrame.new(0, 0.42, s * 3.7), C.WoodLight, M.WoodPlanks, "prop")
		TownKit.Part(model, "SandBorder", Vector3.new(0.4, 0.78, 7), box * CFrame.new(s * 3.7, 0.41, 0), C.WoodLight, M.WoodPlanks, "prop")
	end
	-- TAPE-CUL
	local seesaw = g * CFrame.new(0, 0, 10) * CFrame.Angles(0, math.rad(90), 0)
	TownKit.Part(model, "Pivot", Vector3.new(0.9, 1.3, 0.9), seesaw * CFrame.new(0, 0.65, 0), C.Metal, M.Metal, "prop")
	local plankCF = seesaw * CFrame.new(0, 1.45, 0) * CFrame.Angles(math.rad(11), 0, 0)
	TownKit.Part(model, "Plank", Vector3.new(0.9, 0.3, 9), plankCF, C.Peach, M.WoodPlanks, "deco")
	for _, z in ipairs({ -3.6, 3.6 }) do
		TownKit.Part(model, "Handle", Vector3.new(1.2, 0.8, 0.16), plankCF * CFrame.new(0, 0.55, z), C.Metal, M.Metal, "deco")
	end
	-- LAPIN À RESSORT
	local rider = g * CFrame.new(-1, 0, -8) * CFrame.Angles(0, math.rad(30), 0)
	TownKit.Column(model, "Spring", rider.Position, 1.3, 0.45, C.MetalLight, M.Metal, "deco")
	TownKit.Egg(model, "BunnyBody", rider * CFrame.new(0, 2, 0), Vector3.new(1.3, 1.5, 2.4), C.White, M.SmoothPlastic, "prop")
	TownKit.Ball(model, "BunnyHead", (rider * CFrame.new(0, 2.9, -1.1)).Position, 1.4, C.White, M.SmoothPlastic, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		TownKit.Egg(model, "BunnyEar", rider * CFrame.new(sx * 0.3, 4, -1.1) * CFrame.Angles(0, 0, math.rad(-sx * 10)), Vector3.new(0.35, 1.3, 0.25), C.Pink, M.SmoothPlastic, "deco")
	end
	-- TOURNIQUET
	local mg = g * CFrame.new(0, 0, 1)
	TownKit.Disc(model, "RoundPlate", (mg * CFrame.new(0, 0.85, 0)).Position, 3.2, 0.5, C.Pink, M.Metal, "solid")
	TownKit.Disc(model, "RoundInner", (mg * CFrame.new(0, 0.9, 0)).Position, 2.2, 0.1, C.White, M.Metal, "deco")
	TownKit.Column(model, "RoundPole", (mg * CFrame.new(0, 0.9, 0)).Position, 2.6, 0.4, C.Metal, M.Metal, "prop")
	for k = 0, 3 do
		local a = k * math.pi / 2
		TownKit.Rod(model, "RoundBar", (mg * CFrame.new(0, 3.3, 0)).Position, (mg * CFrame.new(math.cos(a) * 2.7, 0.95, math.sin(a) * 2.7)).Position, 0.18, C.Sky, M.Metal, "deco")
	end
	-- un banc pour les parents + une poubelle, dehors, près du portillon
	TownKit.Bench(model, CFrame.lookAt((g * CFrame.new(-9, 0, -hd - 4.5)).Position, (g * CFrame.new(-9, 0, 0)).Position))
	TownKit.Bin(model, (g * CFrame.new(gate + 3.2, 0, -hd - 2.4)).Position, Color3.fromRGB(96, 150, 110))
	geo.Reserve(cf.Position, 23)
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
	-- (v9.7) planches de terre + vraies touffes de fleurs (ovales en bouquets)
	for i = 0, 4 do
		local row = cf * CFrame.new(0, GROUND_Y, -9 + i * 4.4)
		part(model, "Soil", Vector3.new(20, 0.6, 2.4), row * CFrame.new(0, 0.3, 0), Color3.fromRGB(120, 86, 64), M.Ground, "prop")
		-- feuillage de la planche, puis des bouquets ronds qui dépassent
		TownKit.Egg(model, "Leaves", row * CFrame.new(0, 0.75, 0), Vector3.new(19.4, 1.1, 2), Color3.fromRGB(92, 156, 80), M.Grass, "deco")
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
	TownKit.Egg(model, "Vine", p * CFrame.new(-2, 8.9, 0), Vector3.new(6, 1.4, 7.4), Color3.fromRGB(120, 176, 96), M.Grass, "deco")
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
		local r = r0 + math.sqrt(hash(i, 72)) * (r1 - r0)
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

-- Bois derrière les parcelles + arbres dans les coins entre deux parcelles
local function belt(folder: Instance, geo: TownKit.Geo)
	local model = TownKit.Model(folder, "Woods")
	local O = geo.Origin
	local m = geo.Slots
	local back = geo.PlotR + WorldLayout.PLOT_D / 2
	local perSlot = m >= 11 and 2 or (m >= 8 and 3 or 5) -- (v9.7 : arbres plus riches, un peu moins nombreux)
	for k = 0, m - 1 do
		for j = 1, perSlot do
			local a = geo.SlotAngle(k) + (j - 0.5 - perSlot / 2) / perSlot * (math.pi * 2 / m) + (hash(k, j) - 0.5) * 0.05
			local r = back + 10 + hash(j, k + 40) * (WorldLayout.TOWN_MARGIN - 22)
			local p = O + Vector3.new(math.sin(a) * r, GROUND_Y, math.cos(a) * r)
			-- (pas d'arbre sur la route d'arrivée derrière la porte)
			local rel = p - O
			if not (math.abs(rel.X) < 58 and rel.Z > 0 and rel.Z < geo.Gate + 110) then
				-- (v9.7 NATURE97) bois : sapins, chênes, peupliers, bouleaux
				local h = hash(k, j + 20)
				TownKit.Tree(model, p, 14 + hash(k, j + 9) * 10, k * 50 + j, h < 0.4 and "Fir" or (h < 0.65 and "Oak" or (h < 0.85 and "Poplar" or "Birch")), { Lawn = true })
			end
		end
		-- coin entre deux parcelles (sommet du boulevard), côté extérieur
		local va = geo.SlotAngle(k) + geo.HalfAngle
		local vr = (geo.Front + 16) / math.cos(geo.HalfAngle)
		TownKit.Tree(model, O + Vector3.new(math.sin(va) * vr, GROUND_Y, math.cos(va) * vr), 13, k * 91, k % 2 == 0 and "Oak" or "Maple", { Lawn = true })
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
	playground(nature, geo, frame(aR * 0.42, r0 + 22))
	picnic(nature, geo, frame(aR * 0.62, math.min(geo.Inner - 14, r0 + 50)), 3)
	market(nature, geo, frame((aL + math.pi * 2) / 2, r0 + 24))
	flowerGarden(nature, geo, frame((math.pi + aL) / 2 + 0.06, r0 + 22))
	if depth > 70 then
		court(nature, geo, frame((math.pi + aL) / 2 - 0.05, geo.Inner - 18))
	end
	-- grandes villes : terrain de foot + champ de tulipes là où il y a de la place
	if depth > 110 then
		for _, spot in ipairs({ { (aL + math.pi * 2) / 2 + 0.04, geo.Inner - 34 }, { aR * 0.55, geo.Inner - 34 }, { (aR + math.pi) / 2, geo.Inner - 30 } }) do
			local p = geo.At(spot[1], spot[2])
			if geo.IsFree(p, 26) then
				soccer(nature, geo, frame(spot[1], spot[2]))
				table.insert(anchors, { spot[1], spot[2] - 24 })
				break
			end
		end
		for _, spot in ipairs({ { aR * 0.3, geo.Inner - 30 }, { (math.pi + aL) / 2 - 0.1, mid + 10 }, { (aL + math.pi * 2) / 2 - 0.12, mid + 16 } }) do
			local p = geo.At(spot[1], spot[2])
			if geo.IsFree(p, 22) then
				tulips(nature, geo, frame(spot[1], spot[2]))
				break
			end
		end
	end
	-- allées en gravier : de l'arrière des boutiques de la place vers chaque lieu
	local paths = TownKit.Model(nature, "Footpaths")
	for i, anchor in ipairs(anchors) do
		footpath(paths, geo, geo.At(anchor[1], r0 - 1), anchor[3] or geo.At(anchor[1], anchor[2]), i)
	end
	-- (v9.7) kiosque du parc + massif fleuri et buissons au départ des allées
	for _, spot in ipairs({ { aR * 0.86, r0 + 18 }, { lakeAngle - 0.3, r0 + 14 }, { aR * 0.2, r0 + 44 } }) do
		local p = geo.At(spot[1], spot[2])
		if geo.IsFree(p, 11) then
			gazebo(nature, geo, frame(spot[1], spot[2]))
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
	local trees = scatterTrees(nature, geo, math.clamp(math.floor(depth * 0.28), 22, geo.Slots >= 11 and 46 or 36))
	belt(nature, geo)
	hills(nature, geo)
	TownBuildings.Skyline(nature, O, math.rad(125), math.rad(235), geo.Town + 320, 20)
	return trees
end

return TownNature
