--[[
	DistrictCottage (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DistrictCottage

	🏡 Dopamine Town (v10, CITY10) : l'identité du VILLAGE DES COTTAGES,
	construite côté CLIENT, en flux (TownStreetLife ; emplacements calculés
	par CityPlan dans le quartier "Cottage") :
	  - "CtgChapel"  : petite église en pierre (nef, contreforts, clocher
	    carré à flèche en ardoise, horloge, cloche, coq, rosace et vitraux
	    qui s'allument le soir, portail en arc), enclos de muret, ifs, banc ;
	  - "CtgBakery"  : boulangerie à colombages (vitrine de pains, baguettes,
	    store rayé, enseigne potence, ardoise "Croissants chauds !",
	    jardinières, volets, vélo à panier) ; la boulangère sur le pas de
	    la porte ;
	  - "CtgPond"    : mare (berge, pierres, roseaux, nénuphars), ponton en
	    bois, saule pleureur, banc ; CANARDS qui nagent en rond ; un enfant
	    qui pêche ;
	  - "CtgWell"    : puits en pierre (toit, treuil, seau) ;
	  - "CtgGreen"   : pré communal (vieux chêne, bancs autour, table de
	    pique-nique, parterre) ;
	  - "CtgHedge"   : haie de buis bosselée (longueur spot.Size.X) avec
	    arbustes en fleurs ;
	  - "CtgFlowers" : demi-tonneau fleuri ;
	  - "CtgLantern" : lanterne de village ;
	  - "CtgWelcome" : panneau d'entrée "Village des Cottages" et massif.
	Repère F : au sol, au centre de l'emprise, -Z = façade côté rue.
	Emprises (CityPlan) : TownDistricts... voir DistrictCottage.FOOT.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Greenery = require(ReplicatedStorage.Shared.Greenery)
local CityKit = require(script.Parent.CityKit)

local DistrictCottage = {}

local M = CityKit.M
local rgb = CityKit.rgb
local Box, Part, Column, Wedge, Egg, Glow, Text = CityKit.Box, CityKit.Part, CityKit.Column, CityKit.Wedge, CityKit.Egg, CityKit.Glow, CityKit.Text
local hash = CityKit.Hash

local STONE = rgb(196, 186, 168)
local STONE_D = rgb(162, 152, 136)
local SLATE = rgb(76, 80, 92)
local WOOD = rgb(150, 104, 66)
local WOOD_D = rgb(104, 70, 44)
local PLASTER = rgb(244, 234, 214)
local TIMBER = rgb(92, 60, 40)
local TILE = rgb(176, 88, 64)
local GLASS = rgb(170, 200, 214)
local LAWN = rgb(104, 158, 84)
local WATER = rgb(72, 130, 150)
local WHITE = rgb(250, 250, 248)
local IRON = rgb(46, 48, 56)
local FLOWERS = { rgb(255, 120, 170), rgb(255, 200, 70), rgb(190, 140, 255), rgb(255, 150, 100), rgb(250, 250, 250), rgb(255, 90, 110) }

-- emprises (x, z) pour le placement (CityPlan)
DistrictCottage.FOOT = {
	CtgChapel = Vector2.new(30, 44),
	CtgBakery = Vector2.new(22, 20),
	CtgPond = Vector2.new(40, 32),
	CtgWell = Vector2.new(8, 8),
	CtgGreen = Vector2.new(30, 30),
	CtgWelcome = Vector2.new(12, 5),
}

local function tree(m: Model, F: CFrame, x: number, z: number, h: number, seed: number, species: string)
	pcall(Greenery.Tree, m, (F * CFrame.new(x, 0, z)).Position, h, seed, species, 1)
end

local function flowerBed(m: Model, F: CFrame, x0: number, x1: number, z0: number, z1: number, seed: number)
	Box(m, "BedSoil", F, x0, x1, -0.2, 0.25, z0, z1, rgb(96, 70, 52), M.Ground)
	local n = math.max(2, math.floor((x1 - x0) / 1.4))
	for i = 0, n - 1 do
		local x = x0 + (i + 0.5) * (x1 - x0) / n
		local zz = (z0 + z1) / 2 + (hash(seed, i) - 0.5) * (z1 - z0) * 0.5
		Egg(m, "BedLeaves", F * CFrame.new(x, 0.55, zz), Vector3.new(1.3, 0.8, 1.2), rgb(70, 130, 64), M.Grass)
		Egg(m, "BedBloom", F * CFrame.new(x, 1.0, zz), Vector3.new(0.7, 0.45, 0.7), CityKit.Pick(FLOWERS, seed, i), M.SmoothPlastic)
	end
end

----------------------------------------------------------------------
-- ⛪ Chapelle
----------------------------------------------------------------------

-- flèche octogonale effilée (étages de 2 prismes croisés à 45°) de base b,
-- hauteur h, posée en (0, y, 0) de F
local function spire(m: Model, F: CFrame, y: number, b: number, h: number, color: Color3)
	local n = 7
	for i = 0, n - 1 do
		local s = b * (1 - i / n) * 0.92 + 0.3
		local y0 = y + i * h / n
		local y1 = y0 + h / n + 0.02 * ((i % 2) * 2 - 1)
		Box(m, "Spire", F, -s / 2, s / 2, y0, y1, -s / 2, s / 2, color, M.Slate)
		Box(m, "Spire", F * CFrame.Angles(0, math.pi / 4, 0), -s * 0.46, s * 0.46, y0 + 0.03, y1 - 0.03, -s * 0.46, s * 0.46, color:Lerp(Color3.new(0, 0, 0), 0.08), M.Slate)
	end
end

local function buildChapel(m: Model, F: CFrame, seed: number)
	local NW, NL, WH = 16, 24, 13 -- nef : largeur, longueur, hauteur des murs
	local N = F * CFrame.new(0, 0, 6) -- nef derrière le clocher
	-- enclos : pelouse, muret bas, portillon
	Box(m, "YardLawn", F, -14.9, 14.9, -0.25, 0.08, -21.9, 21.9, LAWN, M.Grass)
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "YardWall", F, sx * 15 - 0.6, sx * 15 + 0.6, 0, 2.2, -22, 22, STONE_D, M.Cobblestone, true)
		Box(m, "YardWallCap", F, sx * 15 - 0.75, sx * 15 + 0.75, 2.2, 2.5, -22.1, 22.1, STONE, M.Slate)
	end
	Box(m, "YardWall", F, -14.4, 14.4, 0, 2.2, 21.4, 22, STONE_D, M.Cobblestone, true)
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "YardWall", F, sx * 3, sx * 14.4, 0, 2.2, -22, -21.4, STONE_D, M.Cobblestone, true)
		Box(m, "GatePier", F, sx * 3 - 0.8, sx * 3 + 0.8, -0.1, 3.4, -22.3, -21.1, STONE, M.Cobblestone, true)
		CityKit.Ball(m, "GateBall", (F * CFrame.new(sx * 3, 3.75, -21.7)).Position, 0.8, STONE, M.Slate)
	end
	-- allée pavée jusqu'au portail
	Box(m, "Path", F, -2.2, 2.2, 0.08, 0.2, -21.4, -13.6, rgb(208, 196, 178), M.Pavement)
	-- nef
	Box(m, "Nave", N, -NW / 2, NW / 2, 0, WH, -NL / 2, NL / 2, STONE, M.Cobblestone, true)
	Box(m, "NavePlinth", N, -NW / 2 - 0.3, NW / 2 + 0.3, 0, 1.2, -NL / 2 - 0.3, NL / 2 + 0.3, STONE_D, M.Slate, true)
	-- toit à deux pans (ardoise) + faîtage
	local roofH = 7
	for _, sx in ipairs({ -1, 1 }) do
		Wedge(m, "NaveRoof", Vector3.new(NL + 1.4, roofH, NW / 2 + 1), N * CFrame.new(sx * (NW / 4 + 0.5), WH + roofH / 2, 0) * CFrame.Angles(0, sx > 0 and -math.pi / 2 or math.pi / 2, 0), SLATE, M.Slate)
	end
	Box(m, "Ridge", N, -0.35, 0.35, WH + roofH - 0.2, WH + roofH + 0.25, -NL / 2 - 0.7, NL / 2 + 0.7, rgb(60, 62, 70), M.Slate)
	-- pignons (triangles en pierre) aux deux bouts de la nef
	for _, sz in ipairs({ -1, 1 }) do
		for _, sx in ipairs({ -1, 1 }) do
			Wedge(m, "Gable", Vector3.new(0.9, roofH, NW / 2), N * CFrame.new(sx * NW / 4, WH + roofH / 2, sz * (NL / 2 - 0.45)) * CFrame.Angles(0, sx > 0 and -math.pi / 2 or math.pi / 2, 0), STONE, M.Cobblestone)
		end
	end
	-- contreforts + vitraux en ogive (côtés)
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 3 do
			local z = -NL / 2 + 1.5 + i * (NL - 3) / 3
			Box(m, "Buttress", N, sx * NW / 2, sx * (NW / 2 + 1.2), 0, WH - 3, z - 0.6, z + 0.6, STONE_D, M.Cobblestone, true)
			Wedge(m, "ButtressTop", Vector3.new(1.2, 2.2, 1.2), N * CFrame.new(sx * (NW / 2 + 0.6), WH - 1.9, z) * CFrame.Angles(0, sx > 0 and -math.pi / 2 or math.pi / 2, 0), STONE_D, M.Cobblestone)
			if i < 3 then
				local zc = z + (NL - 3) / 6
				local win = Box(m, "Lancet", N, sx * (NW / 2 + 0.02), sx * (NW / 2 + 0.12), 3.4, 9.6, zc - 1, zc + 1, rgb(90, 120, 190), M.Glass)
				Glow(win)
				Box(m, "LancetSill", N, sx * (NW / 2), sx * (NW / 2 + 0.4), 3.1, 3.4, zc - 1.3, zc + 1.3, STONE_D, M.Slate)
				Wedge(m, "LancetArch", Vector3.new(0.26, 1.2, 1.1), N * CFrame.new(sx * (NW / 2 + 0.07), 10.2, zc - 0.55), STONE_D, M.Slate)
				Wedge(m, "LancetArch", Vector3.new(0.26, 1.2, 1.1), N * CFrame.new(sx * (NW / 2 + 0.07), 10.2, zc + 0.55) * CFrame.Angles(0, math.pi, 0), STONE_D, M.Slate)
				Box(m, "LancetBar", N, sx * (NW / 2 + 0.12), sx * (NW / 2 + 0.2), 3.4, 9.6, zc - 0.06, zc + 0.06, IRON, M.Metal)
			end
		end
	end
	-- rosace du chevet (arrière)
	local rose = Part(m, "RoseWindow", Vector3.new(0.2, 4.2, 4.2), N * CFrame.new(0, WH - 2.2, NL / 2 + 0.1) * CFrame.Angles(0, math.pi / 2, 0), rgb(180, 90, 150), M.Glass, "Cyl")
	Glow(rose)
	Part(m, "RoseRim", Vector3.new(0.14, 4.8, 4.8), N * CFrame.new(0, WH - 2.2, NL / 2 + 0.02) * CFrame.Angles(0, math.pi / 2, 0), STONE_D, M.Slate, "Cyl")
	-- clocher (devant la nef)
	local T = F * CFrame.new(0, 0, -10)
	local TW, TH = 8, 22
	Box(m, "Tower", T, -TW / 2, TW / 2, 0, TH, -TW / 2, TW / 2, STONE, M.Cobblestone, true)
	Box(m, "TowerPlinth", T, -TW / 2 - 0.3, TW / 2 + 0.3, 0, 1.4, -TW / 2 - 0.3, TW / 2 + 0.3, STONE_D, M.Slate, true)
	Box(m, "TowerCornice", T, -TW / 2 - 0.4, TW / 2 + 0.4, TH, TH + 0.6, -TW / 2 - 0.4, TW / 2 + 0.4, STONE_D, M.Slate)
	Box(m, "TowerBand", T, -TW / 2 - 0.2, TW / 2 + 0.2, 13.5, 13.9, -TW / 2 - 0.2, TW / 2 + 0.2, STONE_D, M.Slate)
	-- abat-sons (4 faces) + cloche visible
	for k = 0, 3 do
		local R = T * CFrame.Angles(0, k * math.pi / 2, 0)
		Box(m, "Belfry", R, -1.3, 1.3, 16, 20, -TW / 2 - 0.05, -TW / 2 + 0.3, rgb(40, 36, 34), M.SmoothPlastic)
		for j = 0, 3 do
			Box(m, "Louvre", R, -1.3, 1.3, 16.4 + j * 0.9, 16.6 + j * 0.9, -TW / 2 - 0.2, -TW / 2 + 0.1, WOOD_D, M.Wood)
		end
	end
	Egg(m, "Bell", T * CFrame.new(0, 17.4, 0), Vector3.new(2.2, 2.6, 2.2), rgb(190, 150, 70), M.Metal)
	-- horloge (face avant) : cadran, aiguilles
	local dial = Part(m, "ClockFace", Vector3.new(0.2, 3.2, 3.2), T * CFrame.new(0, 11.2, -TW / 2 - 0.1) * CFrame.Angles(0, math.pi / 2, 0), WHITE, M.SmoothPlastic, "Cyl")
	local _ = dial
	Part(m, "ClockRim", Vector3.new(0.12, 3.6, 3.6), T * CFrame.new(0, 11.2, -TW / 2 - 0.02) * CFrame.Angles(0, math.pi / 2, 0), rgb(200, 170, 80), M.Metal, "Cyl")
	local hands = T * CFrame.new(0, 11.2, -TW / 2 - 0.25)
	local hr = Box(m, "HourHand", hands, -0.09, 0.09, 0, 1.0, -0.03, 0.03, IRON, M.Metal)
	local mn = Box(m, "MinuteHand", hands, -0.07, 0.07, 0, 1.4, -0.09, -0.03, IRON, M.Metal)
	-- aiguilles à l'heure du serveur (acteur lent)
	CityKit.Actor(m, T.Position, function()
		local okT, now = pcall(function()
			return workspace:GetServerTimeNow()
		end)
		local t = (okT and now or os.clock()) % 43200
		local ah = -t / 43200 * math.pi * 2
		local am = -(t % 3600) / 3600 * math.pi * 2
		hr.CFrame = hands * CFrame.Angles(0, 0, ah) * CFrame.new(0, 0.5, 0)
		mn.CFrame = hands * CFrame.Angles(0, 0, am) * CFrame.new(0, 0.7, -0.03)
	end, 0)
	-- flèche en ardoise + coq
	spire(m, T, TH + 0.6, TW + 0.4, 11, SLATE)
	Column(m, "VaneRod", T, 0, 0, TH + 11, TH + 14.2, 0.14, IRON, M.Metal)
	Box(m, "Cockerel", T, -0.06, 0.06, TH + 13.2, TH + 14.2, -0.8, 0.6, rgb(200, 160, 60), M.Metal)
	Column(m, "VaneCross", T, 0, 0, TH + 12.6, TH + 12.7, 0.08, IRON, M.Metal)
	-- portail en arc (bois cloûté) + marches
	Box(m, "DoorArch", T, -2.4, 2.4, 0, 9.4, -TW / 2 - 0.5, -TW / 2, STONE_D, M.Slate)
	Box(m, "Door", T, -1.7, 1.7, 0.6, 7.8, -TW / 2 - 0.6, -TW / 2 - 0.5, WOOD_D, M.WoodPlanks)
	Box(m, "DoorSplit", T, -0.06, 0.06, 0.6, 7.8, -TW / 2 - 0.66, -TW / 2 - 0.6, IRON, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Wedge(m, "DoorPoint", Vector3.new(0.12, 1.4, 1.7), T * CFrame.new(sx * 0.85, 8.5, -TW / 2 - 0.55) * CFrame.Angles(0, sx > 0 and -math.pi / 2 or math.pi / 2, 0), WOOD_D, M.WoodPlanks)
	end
	for i = 0, 1 do
		Box(m, "Step", T, -3 + i * 0.4, 3 - i * 0.4, 0, 0.3 + i * 0.3, -TW / 2 - 2.2 + i * 0.7, -TW / 2 - 0.5, STONE_D, M.Slate, true)
	end
	-- ifs, banc, panneau d'affichage
	tree(m, F, -10, -16, 11, seed + 1, "Fir")
	tree(m, F, 10, 16, 12, seed + 2, "Fir")
	CityKit.Bench(m, F * CFrame.new(10, 0.08, -12) * CFrame.Angles(0, math.pi / 2, 0), 4.6)
	local board = Box(m, "NoticeBoard", F, -12.4, -9.6, 2.2, 4.4, -18.2, -18, WOOD_D, M.Wood)
	Text(board, Enum.NormalId.Front, "⛪ " .. Locale.T("Village chapel"), WHITE, rgb(60, 90, 60), Enum.Font.Fantasy, 70)
	Column(m, "BoardPost", F, -12.2, -18.1, 0, 4.4, 0.24, WOOD_D, M.Wood)
	Column(m, "BoardPost", F, -9.8, -18.1, 0, 4.4, 0.24, WOOD_D, M.Wood)
	flowerBed(m, F, 4, 12, -20.8, -19.2, seed)
end

local function impChapel(m: Model, F: CFrame)
	local N = F * CFrame.new(0, 0, 6)
	Box(m, "ImpNave", N, -8, 8, 0, 13, -12, 12, STONE, M.Cobblestone, true)
	for _, sx in ipairs({ -1, 1 }) do
		Wedge(m, "ImpRoof", Vector3.new(25.4, 7, 9), N * CFrame.new(sx * 4.5, 16.5, 0) * CFrame.Angles(0, sx > 0 and -math.pi / 2 or math.pi / 2, 0), SLATE, M.Slate)
	end
	local T = F * CFrame.new(0, 0, -10)
	Box(m, "ImpTower", T, -4, 4, 0, 22.6, -4, 4, STONE, M.Cobblestone, true)
	spire(m, T, 22.6, 8.4, 11, SLATE)
end

----------------------------------------------------------------------
-- 🥖 Boulangerie
----------------------------------------------------------------------

local function buildBakery(m: Model, F: CFrame, seed: number)
	local W, D, H1, H2 = 16, 12, 9, 17
	local B = F * CFrame.new(0, 0, 2)
	Box(m, "BakeryPlinth", B, -W / 2 - 0.2, W / 2 + 0.2, 0, 0.8, -D / 2 - 0.2, D / 2 + 0.2, STONE_D, M.Cobblestone, true)
	Box(m, "BakeryGround", B, -W / 2, W / 2, 0.8, H1, -D / 2, D / 2, rgb(120, 60, 50), M.WoodPlanks, true)
	Box(m, "BakeryUpper", B, -W / 2 - 0.4, W / 2 + 0.4, H1, H2, -D / 2 - 0.4, D / 2, PLASTER, M.Plaster, true)
	-- colombages (étage, face avant)
	local zf = -D / 2 - 0.42
	for i = 0, 4 do
		local x = -W / 2 - 0.2 + i * (W + 0.4) / 4
		Box(m, "Timber", B, x - 0.25, x + 0.25, H1, H2, zf - 0.08, zf, TIMBER, M.Wood)
	end
	Box(m, "TimberSill", B, -W / 2 - 0.4, W / 2 + 0.4, H1, H1 + 0.5, zf - 0.08, zf, TIMBER, M.Wood)
	Box(m, "TimberPlate", B, -W / 2 - 0.4, W / 2 + 0.4, H2 - 0.5, H2, zf - 0.08, zf, TIMBER, M.Wood)
	for _, x in ipairs({ -W / 2 - 0.2 + (W + 0.4) / 8, W / 2 + 0.2 - (W + 0.4) / 8 }) do
		CityKit.Beam(m, "TimberBrace", (B * CFrame.new(x - 1.6, H1 + 0.5, zf - 0.04)).Position, (B * CFrame.new(x + 1.6, H2 - 0.5, zf - 0.04)).Position, 0.4, 0.08, TIMBER, M.Wood)
	end
	-- toit en tuiles + cheminée
	for _, sz in ipairs({ -1, 1 }) do
		Wedge(m, "BakeryRoof", Vector3.new(W + 2, 5.5, D / 2 + 1.2), B * CFrame.new(0, H2 + 2.75, sz * (D / 4 + 0.4)) * CFrame.Angles(0, sz > 0 and math.pi or 0, 0), TILE, M.Slate)
	end
	Box(m, "BakeryRidge", B, -W / 2 - 1, W / 2 + 1, H2 + 5.3, H2 + 5.75, -0.35, 0.35, rgb(140, 70, 52), M.Slate)
	Box(m, "Chimney", B, 4, 5.6, H2 + 2, H2 + 8, 1, 2.6, rgb(150, 80, 64), M.Brick)
	Box(m, "ChimneyCap", B, 3.8, 5.8, H2 + 8, H2 + 8.35, 0.8, 2.8, STONE_D, M.Slate)
	-- vitrine (verre allumé le soir) + pains
	Box(m, "ShopFrame", B, -W / 2 + 0.6, 1.2, 1.6, 7.4, -D / 2 - 0.2, -D / 2, WOOD_D, M.Wood)
	Glow(Box(m, "ShopWindow", B, -W / 2 + 1, 0.8, 2, 7, -D / 2 - 0.26, -D / 2 - 0.2, rgb(255, 236, 190), M.Glass))
	Box(m, "Shelf", B, -W / 2 + 1, 0.8, 3.1, 3.3, -D / 2 - 0.1, -D / 2 + 1.4, WOOD, M.Wood)
	for i = 0, 4 do
		local x = -W / 2 + 1.7 + i * 1.3
		Egg(m, "Loaf", B * CFrame.new(x, 3.65, -D / 2 + 0.7), Vector3.new(1.1, 0.7, 0.8), rgb(210, 150, 80), M.SmoothPlastic)
	end
	for i = 0, 3 do
		CityKit.Rod(m, "Baguette", (B * CFrame.new(-W / 2 + 1.6 + i * 1.7, 4.4, -D / 2 + 1.2)).Position, (B * CFrame.new(-W / 2 + 2.2 + i * 1.7, 6.6, -D / 2 + 0.5)).Position, 0.4, rgb(220, 164, 88), M.SmoothPlastic)
	end
	-- porte vitrée
	Box(m, "Door", B, 2.6, 6.2, 0.8, 8.2, -D / 2 - 0.12, -D / 2, rgb(60, 110, 90), M.Wood)
	Glow(Box(m, "DoorGlass", B, 3.1, 5.7, 3.8, 7.6, -D / 2 - 0.18, -D / 2 - 0.12, rgb(255, 236, 190), M.Glass))
	-- store rayé (lambrequins)
	for i = 0, 7 do
		local x0 = -W / 2 + i * W / 8
		Wedge(m, "Awning", Vector3.new(W / 8, 1.6, 3.2), B * CFrame.new(x0 + W / 16, 8.25, -D / 2 - 1.62), i % 2 == 0 and rgb(200, 50, 60) or WHITE, M.Fabric)
		Box(m, "Valance", B, x0, x0 + W / 8, 6.9, 7.4, -D / 2 - 3.25, -D / 2 - 3.15, i % 2 == 0 and rgb(200, 50, 60) or WHITE, M.Fabric)
	end
	-- enseigne
	local sign = Box(m, "BakerySign", B, -W / 2 + 0.6, W / 2 - 0.6, 8.3, 8.95, -D / 2 - 0.5, -D / 2 - 0.44, rgb(40, 70, 60), M.Wood)
	Text(sign, Enum.NormalId.Front, "🥖 " .. Locale.T("Village bakery"), rgb(250, 220, 150), nil, Enum.Font.Fantasy, 140)
	-- enseigne potence
	Box(m, "BracketArm", B, W / 2, W / 2 + 2.4, 10.6, 10.8, -D / 2 - 0.56, -D / 2 - 0.36, IRON, M.Metal)
	local hang = Part(m, "HangSign", Vector3.new(1.8, 1.8, 0.14), B * CFrame.new(W / 2 + 1.5, 9.5, -D / 2 - 0.4) * CFrame.Angles(0, math.pi / 2, 0), rgb(220, 190, 110), M.Wood)
	Text(hang, Enum.NormalId.Front, "🥐", rgb(120, 70, 30), nil, Enum.Font.GothamBlack, 80)
	-- fenêtres de l'étage : volets, jardinières
	for _, x in ipairs({ -4.4, 4.4 }) do
		Box(m, "UpWindow", B, x - 1.3, x + 1.3, H1 + 2, H1 + 5.6, zf - 0.14, zf - 0.08, GLASS, M.Glass)
		Box(m, "UpMullion", B, x - 0.06, x + 0.06, H1 + 2, H1 + 5.6, zf - 0.2, zf - 0.14, WHITE, M.Wood)
		for _, sx in ipairs({ -1, 1 }) do
			Box(m, "Shutter", B, x + sx * 1.35, x + sx * 2.55, H1 + 2, H1 + 5.6, zf - 0.2, zf - 0.08, rgb(80, 130, 150), M.WoodPlanks)
		end
		Box(m, "WindowBox", B, x - 1.5, x + 1.5, H1 + 1.2, H1 + 1.9, zf - 1, zf - 0.14, WOOD_D, M.Wood)
		for i = 0, 3 do
			Egg(m, "BoxBloom", B * CFrame.new(x - 1.1 + i * 0.73, H1 + 2.05, zf - 0.6), Vector3.new(0.8, 0.5, 0.7), CityKit.Pick(FLOWERS, seed, i + x), M.SmoothPlastic)
		end
	end
	-- ardoise, banc, vélo à panier
	local A = F * CFrame.new(-4, 0, -7.5)
	CityKit.Beam(m, "Chalk", (A * CFrame.new(0, 0, -0.5)).Position, (A * CFrame.new(0, 3.2, 0)).Position, 2, 0.1, rgb(40, 44, 40), M.Slate)
	CityKit.Beam(m, "ChalkBack", (A * CFrame.new(0, 0, 0.5)).Position, (A * CFrame.new(0, 3.05, 0.04)).Position, 1.9, 0.1, WOOD, M.Wood)
	local chalk = Part(m, "ChalkText", Vector3.new(1.8, 2.6, 0.02), CFrame.lookAt((A * CFrame.new(0, 1.7, -0.33)).Position, (A * CFrame.new(0, 1.9, -2)).Position), rgb(40, 44, 40), M.SmoothPlastic)
	chalk.Transparency = 1
	Text(chalk, Enum.NormalId.Front, Locale.T("Hot croissants!"), WHITE, nil, Enum.Font.IndieFlower, 40)
	CityKit.Bench(m, F * CFrame.new(5, 0, -7) * CFrame.Angles(0, math.pi, 0), 4)
	local bike = F * CFrame.new(-9.2, 0, -5.4) * CFrame.Angles(0, math.rad(80), 0)
	for _, x in ipairs({ -1.4, 1.4 }) do
		Part(m, "BikeWheel", Vector3.new(0.12, 2.2, 2.2), bike * CFrame.new(x, 1.1, 0), rgb(30, 30, 34), M.Rubber, "Cyl")
	end
	CityKit.Beam(m, "BikeFrame", (bike * CFrame.new(-1.4, 1.1, 0)).Position, (bike * CFrame.new(0.2, 2.4, 0)).Position, 0.14, 0.14, rgb(80, 150, 160), M.Metal)
	CityKit.Beam(m, "BikeFrame", (bike * CFrame.new(1.4, 1.1, 0)).Position, (bike * CFrame.new(0.2, 2.4, 0)).Position, 0.14, 0.14, rgb(80, 150, 160), M.Metal)
	Box(m, "BikeBasket", bike, 1.2, 2.3, 2.4, 3.2, -0.5, 0.5, rgb(190, 150, 90), M.Fabric)
	-- la boulangère
	local baker = CityKit.Npc(m, "baker", seed * 7 + 3, B * CFrame.new(4.4, 0.8, -D / 2 - 1.2) * CFrame.Angles(0, math.pi, 0), "none", true)
	CityKit.Idle(baker, "wave", hash(seed, 9) * 10)
end

local function impBakery(m: Model, F: CFrame)
	local B = F * CFrame.new(0, 0, 2)
	Box(m, "ImpBakery", B, -8, 8, 0, 17, -6, 6, PLASTER, M.Plaster, true)
	for _, sz in ipairs({ -1, 1 }) do
		Wedge(m, "ImpRoof", Vector3.new(18, 5.5, 7.2), B * CFrame.new(0, 19.75, sz * 3.4) * CFrame.Angles(0, sz > 0 and math.pi or 0, 0), TILE, M.Slate)
	end
end

----------------------------------------------------------------------
-- 🦆 Mare
----------------------------------------------------------------------

local function buildPond(m: Model, F: CFrame, seed: number)
	local RX, RZ = 15, 11
	Egg(m, "PondBank", F * CFrame.new(0, 0.02, 0), Vector3.new(RX * 2 + 3, 0.5, RZ * 2 + 3), rgb(150, 130, 96), M.Mud)
	local water = Egg(m, "PondWater", F * CFrame.new(0, 0.12, 0), Vector3.new(RX * 2, 0.5, RZ * 2), WATER, M.Glass)
	water.Transparency = 0.15
	water.Reflectance = 0.1
	-- pierres de berge
	local n = 22
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2 + hash(seed, i) * 0.2
		local r = 1.02 + hash(seed, i + 50) * 0.06
		local s = 0.9 + hash(seed, i + 90) * 0.9
		Egg(m, "BankStone", F * CFrame.new(math.cos(a) * RX * r, 0.3, math.sin(a) * RZ * r) * CFrame.Angles(0, a, 0), Vector3.new(s * 1.3, s * 0.7, s), rgb(150, 146, 138):Lerp(rgb(110, 106, 100), hash(seed, i + 7)), M.Slate)
	end
	-- roseaux (quenouilles) en touffes
	for g = 0, 3 do
		local a = (g + 0.3) / 4 * math.pi * 2 + hash(seed, g) * 0.5
		local cx, cz = math.cos(a) * RX * 0.86, math.sin(a) * RZ * 0.86
		for k = 0, 4 do
			local x, z = cx + (hash(seed, g * 9 + k) - 0.5) * 2.2, cz + (hash(seed, g * 13 + k) - 0.5) * 2.2
			local h = 3 + hash(seed, g * 5 + k) * 1.6
			Column(m, "Reed", F, x, z, 0, h, 0.12, rgb(96, 140, 70), M.Grass)
			if k % 2 == 0 then
				Column(m, "Cattail", F, x, z, h - 0.1, h + 0.7, 0.28, rgb(110, 70, 40), M.Fabric)
			end
		end
	end
	-- nénuphars
	for i = 0, 6 do
		local a = hash(seed, i + 20) * math.pi * 2
		local r = 0.3 + hash(seed, i + 30) * 0.45
		Part(m, "LilyPad", Vector3.new(0.08, 1.8, 1.8), F * CFrame.new(math.cos(a) * RX * r, 0.39, math.sin(a) * RZ * r) * CityKit.UPRIGHT, rgb(70, 140, 60), M.SmoothPlastic, "Cyl")
		if i % 3 == 0 then
			Egg(m, "LilyFlower", F * CFrame.new(math.cos(a) * RX * r + 0.3, 0.6, math.sin(a) * RZ * r), Vector3.new(0.6, 0.4, 0.6), rgb(255, 190, 220), M.SmoothPlastic)
		end
	end
	-- ponton en bois (vers le nord-est de la mare)
	local J = F * CFrame.new(RX * 0.55, 0, -RZ * 0.55) * CFrame.Angles(0, math.rad(-35), 0)
	Box(m, "Jetty", J, -1.8, 1.8, 0.9, 1.2, -1, 9, WOOD, M.WoodPlanks, true)
	for _, x in ipairs({ -1.6, 1.6 }) do
		for _, z in ipairs({ 0, 4, 8.6 }) do
			Column(m, "JettyPile", J, x, z, -0.3, 1.6, 0.4, WOOD_D, M.Wood)
		end
	end
	-- saule pleureur + banc
	tree(m, F, -RX - 4, 3, 13, seed + 5, "Willow")
	CityKit.Bench(m, F * CFrame.new(-RX + 1, 0, -RZ - 2.4), 4.6)
	-- un enfant pêche au bout du ponton
	local kid = CityKit.Npc(m, "kid", seed * 3 + 1, J * CFrame.new(0, 1.2, 1.2) * CFrame.Angles(0, math.pi, 0), "none", false)
	if kid then
		local tip = (J * CFrame.new(0.6, 5.5, -3.2)).Position
		CityKit.Rod(m, "FishingRod", (J * CFrame.new(0.5, 3.2, 0.9)).Position, tip, 0.08, rgb(90, 60, 40), M.Wood)
		CityKit.Rod(m, "FishingLine", tip, tip - Vector3.new(0, 4.6, 0), 0.03, WHITE, M.SmoothPlastic)
		CityKit.Idle(kid, "idle", hash(seed, 4) * 10)
	end
	-- canards : nagent en rond (ellipse), tête qui plonge de temps en temps
	for d = 0, 2 do
		local duck = Instance.new("Model")
		duck.Name = "Duck"
		local white = d == 2
		local body = Egg(duck, "DuckBody", CFrame.new(), Vector3.new(0.9, 0.6, 1.5), white and WHITE or rgb(120, 96, 70), M.SmoothPlastic)
		local head = CityKit.Ball(duck, "DuckHead", Vector3.zero, 0.55, white and WHITE or rgb(40, 110, 70), M.SmoothPlastic)
		local bill = Box(duck, "DuckBill", CFrame.new(), -0.12, 0.12, -0.05, 0.05, -0.3, 0, rgb(250, 170, 40), M.SmoothPlastic)
		duck.Parent = m
		local r = 0.55 + d * 0.13
		local speed = 0.12 + d * 0.03
		local parts = { body, head, bill }
		local frames = { CFrame.new(), CFrame.new(), CFrame.new() }
		local function swim(t: number)
			local a = t * speed + d * 2.1
			local x, z = math.cos(a) * RX * r, math.sin(a) * RZ * r
			local dx, dz = -math.sin(a) * RX * r, math.cos(a) * RZ * r
			local bob = math.sin(t * 2.2 + d) * 0.04
			local C = F * CFrame.new(x, 0.62 + bob, z)
			C = CFrame.lookAt(C.Position, C.Position + (F:VectorToWorldSpace(Vector3.new(dx, 0, dz))))
			local dip = math.max(0, math.sin(t * 0.7 + d * 3)) ^ 12
			frames[1] = C
			frames[2] = C * CFrame.new(0, 0.45 - dip * 0.55, -0.62 - dip * 0.2)
			frames[3] = C * CFrame.new(0, 0.42 - dip * 0.55, -0.9 - dip * 0.2)
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		-- (posés tout de suite sur l'eau, même si la caméra est encore loin)
		swim(os.clock() + seed)
		CityKit.Actor(duck, F.Position, swim, seed)
	end
end

----------------------------------------------------------------------
-- Puits, pré communal, haie, fleurs, lanterne, panneau d'entrée
----------------------------------------------------------------------

local function buildWell(m: Model, F: CFrame, _seed: number)
	Column(m, "WellRing", F, 0, 0, 0, 2.6, 4.4, STONE, M.Cobblestone, true)
	Column(m, "WellLip", F, 0, 0, 2.6, 2.9, 4.8, STONE_D, M.Slate)
	Column(m, "WellWater", F, 0, 0, 2.2, 2.3, 3.6, rgb(40, 70, 80), M.Glass)
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "WellPost", F, sx * 1.9 - 0.2, sx * 1.9 + 0.2, 2.6, 7.4, -0.2, 0.2, WOOD_D, M.Wood)
	end
	Part(m, "Winch", Vector3.new(3.6, 0.5, 0.5), F * CFrame.new(0, 6, 0), WOOD, M.Wood, "Cyl")
	Box(m, "Crank", F, 2.1, 2.2, 5.4, 6.2, -0.05, 0.05, IRON, M.Metal)
	CityKit.Rod(m, "Rope", (F * CFrame.new(0, 5.8, 0)).Position, (F * CFrame.new(0, 4.3, 0)).Position, 0.06, rgb(200, 180, 140), M.Fabric)
	Column(m, "Bucket", F, 0, 0, 3.4, 4.3, 0.9, WOOD, M.WoodPlanks)
	for _, sz in ipairs({ -1, 1 }) do
		Wedge(m, "WellRoof", Vector3.new(5, 1.8, 2.4), F * CFrame.new(0, 8.3, sz * 1.2) * CFrame.Angles(0, sz > 0 and math.pi or 0, 0), TILE, M.Slate)
	end
end

local function buildGreen(m: Model, F: CFrame, seed: number)
	Egg(m, "GreenLawn", F * CFrame.new(0, -0.05, 0), Vector3.new(28, 0.3, 28), rgb(112, 168, 86), M.Grass)
	tree(m, F, 0, 0, 18, seed + 11, "Oak")
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		CityKit.Bench(m, F * CFrame.new(math.cos(a) * 7, 0.05, math.sin(a) * 7) * CFrame.Angles(0, -a - math.pi / 2, 0), 4.6)
	end
	-- table de pique-nique
	local T = F * CFrame.new(9, 0.05, -8) * CFrame.Angles(0, 0.4, 0)
	-- (v11, SCALE11 : échelle Roblox) plateau à 3,1, bancs à 1,85
	Box(m, "PicnicTop", T, -3, 3, 2.8, 3.1, -1.2, 1.2, WOOD, M.WoodPlanks, true)
	for _, z in ipairs({ -2.5, 2.5 }) do
		Box(m, "PicnicSeat", T, -3, 3, 1.6, 1.85, z - 0.55, z + 0.55, WOOD, M.WoodPlanks, true)
	end
	for _, x in ipairs({ -2.3, 2.3 }) do
		Box(m, "PicnicLeg", T, x - 0.18, x + 0.18, 0, 2.8, -2.9, 2.9, WOOD_D, M.Wood)
	end
	-- parterre rond de fleurs
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		Egg(m, "GreenBloom", F * CFrame.new(math.cos(a) * 11, 0.45, math.sin(a) * 11), Vector3.new(1.4, 0.9, 1.4), CityKit.Pick(FLOWERS, seed, i), M.SmoothPlastic)
	end
	-- deux villageois qui discutent
	local a1 = CityKit.Npc(m, "elder", seed * 5 + 1, F * CFrame.new(-6, 0.05, 9) * CFrame.Angles(0, math.rad(-70), 0), "cane", true)
	local a2 = CityKit.Npc(m, "pedestrian", seed * 5 + 2, F * CFrame.new(-4.4, 0.05, 9.6) * CFrame.Angles(0, math.rad(110), 0), "bag", true)
	CityKit.Idle(a1, "talk", 0)
	CityKit.Idle(a2, "talk", 1.7)
end

local function buildHedge(m: Model, F: CFrame, seed: number, spot: any)
	local L = spot and spot.Size and spot.Size.X or 12
	CityKit.Hedge(m, F, L, 3, 2, seed)
	-- quelques arbustes en fleurs (hortensias) posés devant
	local n = math.floor(L / 9)
	for i = 0, n - 1 do
		local x = -L / 2 + (i + 0.5) * L / n
		Egg(m, "Hydrangea", F * CFrame.new(x, 1.2, -1.6), Vector3.new(2, 1.8, 1.4), CityKit.Pick({ rgb(150, 170, 255), rgb(255, 170, 210), rgb(250, 250, 255) }, seed, i), M.Grass)
	end
end

local function buildFlowers(m: Model, F: CFrame, seed: number)
	Column(m, "Barrel", F, 0, 0, 0, 1.8, 2.6, WOOD, M.WoodPlanks, true)
	for _, y in ipairs({ 0.4, 1.4 }) do
		Column(m, "BarrelHoop", F, 0, 0, y, y + 0.14, 2.7, IRON, M.Metal)
	end
	Column(m, "BarrelSoil", F, 0, 0, 1.8, 1.86, 2.3, rgb(96, 70, 52), M.Ground)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		Egg(m, "BarrelBloom", F * CFrame.new(math.cos(a) * 0.65, 2.25, math.sin(a) * 0.65), Vector3.new(0.9, 0.8, 0.9), CityKit.Pick(FLOWERS, seed, i), M.SmoothPlastic)
	end
	Egg(m, "BarrelLeaves", F * CFrame.new(0, 2.1, 0), Vector3.new(2, 0.9, 2), rgb(70, 130, 64), M.Grass)
end

local function buildLantern(m: Model, F: CFrame, _seed: number)
	CityKit.Lantern(m, F, 10, rgb(40, 50, 44))
end

local function buildWelcome(m: Model, F: CFrame, seed: number)
	for _, x in ipairs({ -4.4, 4.4 }) do
		Box(m, "WelcomePost", F, x - 0.3, x + 0.3, 0, 5.4, -0.3, 0.3, WOOD_D, M.Wood, true)
		Wedge(m, "WelcomePostCap", Vector3.new(0.7, 0.5, 0.7), F * CFrame.new(x, 5.65, 0), WOOD_D, M.Wood)
	end
	local board = Box(m, "WelcomeBoard", F, -4.2, 4.2, 2.6, 5, -0.12, 0.12, rgb(250, 240, 214), M.WoodPlanks)
	Text(board, Enum.NormalId.Front, "🏡 " .. Locale.T("Cottage village"), rgb(70, 50, 30), nil, Enum.Font.Fantasy, 160)
	Text(board, Enum.NormalId.Back, Locale.T("See you soon!") .. " 👋", rgb(70, 50, 30), nil, Enum.Font.Fantasy, 160)
	flowerBed(m, F, -5, 5, -2.2, -0.6, seed)
end

DistrictCottage.BUILDERS = {
	CtgChapel = buildChapel,
	CtgBakery = buildBakery,
	CtgPond = buildPond,
	CtgWell = buildWell,
	CtgGreen = buildGreen,
	CtgHedge = buildHedge,
	CtgFlowers = buildFlowers,
	CtgLantern = buildLantern,
	CtgWelcome = buildWelcome,
}
DistrictCottage.BIG = { CtgChapel = true, CtgBakery = true, CtgPond = true, CtgGreen = true }
DistrictCottage.IMPOSTORS = {
	CtgChapel = impChapel,
	CtgBakery = impBakery,
}

return DistrictCottage
