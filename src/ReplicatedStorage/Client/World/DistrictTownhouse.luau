--[[
	DistrictTownhouse (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DistrictTownhouse

	🏘️ Dopamine Town (v10, CITY10) : l'identité des RUES DE MAISONS DE VILLE,
	construite côté CLIENT, en flux (TownStreetLife ; emplacements calculés
	par CityPlan dans le quartier "Townhouse") :
	  - "TwnTree"      : arbre d'alignement dans sa fosse (grille en fonte,
	    corset de protection), le long des trottoirs ;
	  - "TwnCornerShop": épicerie de quartier (immeuble de 3 niveaux en
	    brique, devanture verte, store, étals de fruits et légumes, présentoir
	    à journaux, glacière "Glaces") ; l'épicier sur le pas de la porte ;
	  - "TwnCafe"      : café du coin (façade crème, grande vitrine allumée
	    le soir, enseigne, terrasse : tables bistrot, chaises, parasols,
	    jardinières) ; des clients assis qui discutent, un serveur qui fait
	    des allers-retours avec son plateau ;
	  - "TwnSquare"    : petit square (dalles, fontaine Wallace, bancs,
	    4 arbres, parterres, lampadaires, kiosque à musique miniature) ;
	  - "TwnBikes"     : station de vélos en libre-service (borne, vélos) ;
	  - "TwnBusStop"   : arrêt de bus (abri vitré, banc, plan, poteau) avec
	    des gens qui attendent ;
	  - "TwnLamp"      : lampadaire double de style "ville".
	Repère F : au sol, au centre de l'emprise, -Z = côté rue.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Greenery = require(ReplicatedStorage.Shared.Greenery)
local CityKit = require(script.Parent.CityKit)

local DistrictTownhouse = {}

local M = CityKit.M
local rgb = CityKit.rgb
local Box, Part, Column, Wedge, Egg, Glow, Text = CityKit.Box, CityKit.Part, CityKit.Column, CityKit.Wedge, CityKit.Egg, CityKit.Glow, CityKit.Text
local hash = CityKit.Hash

local BRICK = rgb(166, 92, 70)
local BRICK_D = rgb(128, 70, 54)
local STONE = rgb(222, 214, 196)
local CREAM = rgb(240, 228, 200)
local IRON = rgb(40, 44, 50)
local GREEN_SHOP = rgb(30, 90, 64)
local WOOD = rgb(150, 104, 66)
local WHITE = rgb(250, 250, 248)
local GLASS = rgb(150, 180, 200)
local WARM = rgb(255, 232, 186)
local PAVER = rgb(206, 200, 190)

DistrictTownhouse.FOOT = {
	TwnCornerShop = Vector2.new(22, 22),
	TwnCafe = Vector2.new(24, 24),
	TwnSquare = Vector2.new(36, 36),
	TwnBikes = Vector2.new(14, 5),
	TwnBusStop = Vector2.new(10, 5),
	TwnTerrace = Vector2.new(36, 20),
}

local function tree(m: Model, F: CFrame, x: number, z: number, h: number, seed: number, species: string)
	pcall(Greenery.Tree, m, (F * CFrame.new(x, 0, z)).Position, h, seed, species, 1)
end

-- façade d'immeuble (3 niveaux) : corps, bandeaux, fenêtres, corniche
local function building(m: Model, F: CFrame, W: number, D: number, H: number, wall: Color3, mat: Enum.Material, seed: number)
	Box(m, "Block", F, -W / 2, W / 2, 0, H, -D / 2, D / 2, wall, mat, true)
	Box(m, "Cornice", F, -W / 2 - 0.5, W / 2 + 0.5, H, H + 0.8, -D / 2 - 0.5, D / 2 + 0.5, STONE, M.Concrete)
	Box(m, "Parapet", F, -W / 2 - 0.2, W / 2 + 0.2, H + 0.8, H + 2, -D / 2 - 0.2, -D / 2 + 0.4, wall, mat)
	Box(m, "RoofTop", F, -W / 2 + 0.2, W / 2 - 0.2, H + 0.7, H + 1.1, -D / 2 + 0.3, D / 2 - 0.1, rgb(90, 92, 100), M.Concrete)
	Box(m, "Chimney", F, W / 2 - 3, W / 2 - 1.4, H - 0.5, H + 4.2, 1, 3, BRICK_D, M.Brick)
	-- arrière et côtés : fenêtres simples (vues de loin et d'en haut)
	for floor = 0, 2 do
		local y0 = 1.6 + floor * 9 + (floor == 0 and 0.8 or 0)
		local n = math.max(2, math.floor(W / 6))
		for i = 0, n - 1 do
			local x = -W / 2 + (i + 0.5) * W / n
			Box(m, "BackWindow", F, x - 1.2, x + 1.2, y0 + 2, y0 + 6.4, D / 2, D / 2 + 0.08, GLASS, M.Glass)
		end
		for _, sx in ipairs({ -1, 1 }) do
			Box(m, "SideWindow", F, sx > 0 and W / 2 or -W / 2 - 0.08, sx > 0 and W / 2 + 0.08 or -W / 2, y0 + 2, y0 + 6.4, -1.2, 1.2, GLASS, M.Glass)
		end
	end
	-- étages : fenêtres à encadrement et appui, une sur deux avec jardinière
	for floor = 1, 2 do
		local y0 = 10 + (floor - 1) * 9
		Box(m, "Band", F, -W / 2 - 0.15, W / 2 + 0.15, y0 - 1.1, y0 - 0.7, -D / 2 - 0.15, -D / 2, STONE, M.Concrete)
		local n = math.max(2, math.floor(W / 6))
		for i = 0, n - 1 do
			local x = -W / 2 + (i + 0.5) * W / n
			local lit = hash(seed, floor * 10 + i) < 0.35
			local g = Box(m, "Window", F, x - 1.3, x + 1.3, y0, y0 + 5.2, -D / 2 - 0.08, -D / 2, lit and WARM or GLASS, M.Glass)
			if lit then
				Glow(g)
			end
			Box(m, "WindowTrim", F, x - 1.6, x + 1.6, y0 + 5.2, y0 + 5.7, -D / 2 - 0.2, -D / 2, STONE, M.Concrete)
			Box(m, "WindowSill", F, x - 1.6, x + 1.6, y0 - 0.35, y0, -D / 2 - 0.4, -D / 2, STONE, M.Concrete)
			Box(m, "WindowBar", F, x - 0.06, x + 0.06, y0, y0 + 5.2, -D / 2 - 0.14, -D / 2 - 0.08, WHITE, M.Wood)
			if (i + floor) % 2 == 0 then
				Box(m, "Railing", F, x - 1.5, x + 1.5, y0 + 1.6, y0 + 1.75, -D / 2 - 0.9, -D / 2 - 0.75, IRON, M.Metal)
				for k = 0, 4 do
					Box(m, "RailingBar", F, x - 1.4 + k * 0.7, x - 1.3 + k * 0.7, y0 + 0.05, y0 + 1.6, -D / 2 - 0.86, -D / 2 - 0.78, IRON, M.Metal)
				end
				Egg(m, "Geranium", F * CFrame.new(x, y0 + 0.35, -D / 2 - 0.5), Vector3.new(2.6, 0.7, 0.6), CityKit.Pick({ rgb(230, 40, 60), rgb(255, 120, 170), WHITE }, seed, i), M.SmoothPlastic)
			end
		end
	end
end

----------------------------------------------------------------------
-- 🌳 Arbre d'alignement
----------------------------------------------------------------------

local function buildTree(m: Model, F: CFrame, seed: number)
	-- grille de pied d'arbre (4 quarts) + cadre, corset en fer
	Box(m, "PitFrame", F, -1.8, 1.8, -0.1, 0.06, -1.8, 1.8, IRON, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Box(m, "PitGrate", F, sx * 0.2, sx * 1.6, 0.06, 0.1, sz * 0.2, sz * 1.6, rgb(60, 62, 70), M.DiamondPlate)
		end
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local base = (F * CFrame.new(math.cos(a) * 1.4, 0.1, math.sin(a) * 1.4)).Position
		local top = (F * CFrame.new(math.cos(a) * 0.9, 5, math.sin(a) * 0.9)).Position
		CityKit.Rod(m, "GuardBar", base, top, 0.12, IRON, M.Metal)
	end
	Column(m, "GuardRing", F, 0, 0, 4.2, 4.35, 2.1, IRON, M.Metal)
	tree(m, F, 0, 0, 15 + hash(seed, 1) * 5, seed, hash(seed, 2) < 0.5 and "Maple" or "Oak")
end

----------------------------------------------------------------------
-- 🥬 Épicerie de quartier
----------------------------------------------------------------------

local function buildCornerShop(m: Model, F: CFrame, seed: number)
	local W, D, H = 18, 14, 28
	local B = F * CFrame.new(0, 0, 3)
	building(m, B, W, D, H, BRICK, M.Brick, seed)
	-- devanture en bois peint (rez-de-chaussée)
	local zf = -D / 2
	Box(m, "Shopfront", B, -W / 2, W / 2, 0, 8.4, zf - 0.4, zf, GREEN_SHOP, M.Wood)
	Glow(Box(m, "ShopGlass", B, -W / 2 + 1, 2.5, 1.4, 6.8, zf - 0.46, zf - 0.4, WARM, M.Glass))
	Box(m, "ShopDoor", B, 3.4, 7.2, 0, 7.6, zf - 0.46, zf - 0.4, rgb(24, 70, 50), M.Wood)
	Glow(Box(m, "DoorGlass", B, 3.9, 6.7, 3, 7.1, zf - 0.52, zf - 0.46, WARM, M.Glass))
	local sign = Box(m, "ShopSign", B, -W / 2 + 0.4, W / 2 - 0.4, 8.4, 9.9, zf - 0.6, zf - 0.4, GREEN_SHOP, M.Wood)
	Text(sign, Enum.NormalId.Front, "🍎 " .. Locale.T("Corner grocery"), rgb(250, 220, 140), nil, Enum.Font.Fantasy, 150)
	-- store banne déroulé (lambrequin)
	Wedge(m, "Awning", Vector3.new(W, 1.4, 3.6), B * CFrame.new(0, 8.9, zf - 2.2), rgb(40, 120, 80), M.Fabric)
	for i = 0, 8 do
		local x = -W / 2 + (i + 0.5) * W / 9
		Box(m, "AwningStripe", B, x - 0.5, x + 0.5, 8.24, 8.3, zf - 4.02, zf - 3.96, WHITE, M.Fabric)
	end
	Box(m, "Valance", B, -W / 2, W / 2, 7.6, 8.2, zf - 4.02, zf - 3.94, rgb(40, 120, 80), M.Fabric)
	-- étals inclinés (caisses de fruits et légumes)
	local fruits = { rgb(230, 40, 40), rgb(255, 160, 30), rgb(250, 220, 60), rgb(110, 180, 60), rgb(150, 60, 160), rgb(60, 140, 50) }
	for row = 0, 1 do
		for i = 0, 3 do
			local x = -W / 2 + 1.6 + i * 2.2
			local z = zf - 1.2 - row * 1.6
			local y = 2.6 - row * 0.8
			Box(m, "Crate", B, x - 1, x + 1, y - 0.8, y, z - 0.75, z + 0.75, WOOD, M.WoodPlanks)
			local c = fruits[1 + (i + row * 4 + math.floor(hash(seed, i) * 6)) % #fruits]
			for k = 0, 2 do
				CityKit.Ball(m, "Fruit", (B * CFrame.new(x - 0.55 + k * 0.55, y + 0.25, z + (k % 2) * 0.3 - 0.15)).Position, 0.55, c, M.SmoothPlastic)
			end
		end
	end
	Box(m, "StallLegs", B, -W / 2 + 0.6, -W / 2 + 9.6, 0, 1.2, zf - 3.4, zf - 0.6, WOOD, M.Wood)
	-- présentoir à journaux, glacière
	local N = B * CFrame.new(8, 0, zf - 1.4)
	Box(m, "NewsRack", N, -0.8, 0.8, 0, 4.2, -0.5, 0.5, IRON, M.Metal)
	for k = 0, 2 do
		Box(m, "Paper", N, -0.7, 0.7, 1.4 + k * 1, 2.2 + k * 1, -0.62, -0.5, CityKit.Pick({ WHITE, rgb(250, 230, 200), rgb(220, 236, 250) }, seed, k), M.SmoothPlastic)
	end
	local ice = Box(m, "IceChest", B, W / 2 - 4.4, W / 2 - 0.8, 0, 3, zf - 2.4, zf - 0.6, WHITE, M.SmoothPlastic, true)
	Text(ice, Enum.NormalId.Front, "🍦 " .. Locale.T("Ice creams"), rgb(40, 120, 200), nil, Enum.Font.GothamBlack, 60)
	-- l'épicier
	local grocer = CityKit.Npc(m, "salesperson", seed * 3 + 5, B * CFrame.new(1, 0, zf - 1.6) * CFrame.Angles(0, math.pi, 0), "none", true)
	CityKit.Idle(grocer, "talk", hash(seed, 3) * 8)
end

----------------------------------------------------------------------
-- ☕ Café et sa terrasse
----------------------------------------------------------------------

local function bistroChair(m: Model, T: CFrame, a: number)
	local C = T * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 1.6)
	Box(m, "ChairSeat", C, -0.6, 0.6, 1.3, 1.45, -0.6, 0.6, rgb(180, 60, 50), M.Fabric)
	Box(m, "ChairBack", C, -0.6, 0.6, 1.45, 2.8, 0.5, 0.62, rgb(180, 60, 50), M.Fabric)
	for _, sx in ipairs({ -0.5, 0.5 }) do
		for _, sz in ipairs({ -0.5, 0.5 }) do
			Column(m, "ChairLeg", C, sx, sz, 0, 1.3, 0.1, IRON, M.Metal)
		end
	end
end

local function buildCafe(m: Model, F: CFrame, seed: number)
	local W, D, H = 18, 12, 26
	local B = F * CFrame.new(0, 0, 6)
	building(m, B, W, D, H, CREAM, M.Plaster, seed + 3)
	local zf = -D / 2
	Box(m, "CafeFront", B, -W / 2, W / 2, 0, 8.6, zf - 0.35, zf, rgb(120, 30, 40), M.Wood)
	Glow(Box(m, "CafeGlass", B, -W / 2 + 0.8, W / 2 - 5, 1.2, 7.2, zf - 0.42, zf - 0.35, WARM, M.Glass))
	Box(m, "CafeDoor", B, W / 2 - 4.2, W / 2 - 0.8, 0, 7.8, zf - 0.42, zf - 0.35, rgb(90, 20, 30), M.Wood)
	Glow(Box(m, "CafeDoorGlass", B, W / 2 - 3.8, W / 2 - 1.2, 3.2, 7.3, zf - 0.48, zf - 0.42, WARM, M.Glass))
	local sign = Box(m, "CafeSign", B, -W / 2 + 0.3, W / 2 - 0.3, 8.6, 10, zf - 0.55, zf - 0.35, rgb(120, 30, 40), M.Wood)
	Text(sign, Enum.NormalId.Front, "☕ " .. Locale.T("Café du Coin"), rgb(250, 226, 160), nil, Enum.Font.Fantasy, 150)
	-- comptoir visible derrière la vitrine
	Box(m, "Counter", B, -W / 2 + 1, -1, 0, 3.6, zf + 1, zf + 2.2, WOOD, M.Wood)
	Box(m, "Espresso", B, -4, -2, 3.6, 5, zf + 1.2, zf + 2, rgb(190, 192, 200), M.Metal)
	-- terrasse : plancher, jardinières, 3 tables, parasols
	Box(m, "Deck", F, -W / 2, W / 2, 0.02, 0.3, -12, -0.4, rgb(170, 130, 96), M.WoodPlanks, true)
	for _, x in ipairs({ -W / 2 + 0.6, W / 2 - 0.6 }) do
		Box(m, "Planter", F, x - 0.6, x + 0.6, 0.3, 2, -11.6, -1, rgb(70, 70, 76), M.Concrete, true)
		for k = 0, 4 do
			Egg(m, "PlanterBush", F * CFrame.new(x, 2.3, -10.6 + k * 2.2), Vector3.new(1.4, 1.2, 2.2), rgb(70, 130, 64), M.Grass)
		end
	end
	local sitters = {}
	for i = 0, 2 do
		local T = F * CFrame.new(-5.4 + i * 5.4, 0.3, -6.4 + (i % 2) * 1.2)
		Column(m, "TableFoot", T, 0, 0, 0, 0.12, 1.4, IRON, M.Metal)
		Column(m, "TableLeg", T, 0, 0, 0.12, 2.3, 0.16, IRON, M.Metal)
		Column(m, "TableTop", T, 0, 0, 2.3, 2.42, 2.4, WHITE, M.Marble)
		Column(m, "Cup", T, 0.4, 0.2, 2.42, 2.82, 0.36, WHITE, M.SmoothPlastic)
		for k = 0, 1 do
			bistroChair(m, T, k * math.pi)
		end
		-- parasol
		Column(m, "ParasolPole", T, 0, 0, 2.42, 8.2, 0.14, WOOD, M.Wood)
		local color = i % 2 == 0 and rgb(200, 50, 60) or rgb(250, 244, 230)
		for k = 0, 3 do
			local R = T * CFrame.Angles(0, k * math.pi / 2, 0)
			Wedge(m, "Parasol", Vector3.new(3.4, 1, 1.9), R * CFrame.new(0, 7.9 + k * 0.03, -0.95), color, M.Fabric)
		end
		-- des clients assis (table du milieu : deux clients, la 3e libre)
		for k = 0, (i == 1 and 1 or (i == 0 and 0 or -1)) do
			local seat = T * CFrame.Angles(0, k * math.pi, 0) * CFrame.new(0, 0, 1.6)
			local p = CityKit.Npc(m, CityKit.Pick({ "pedestrian", "shopper", "elder" }, seed, i * 3 + k), seed * 11 + i * 3 + k, seat * CFrame.new(0, 0.1, 0.1), k == 0 and "coffee" or "phone", false)
			if p then
				table.insert(sitters, p)
				CityKit.Idle(p, "sit", hash(seed, i + k * 5) * 10)
			end
		end
	end
	-- serveur : aller-retour entre la porte et les tables
	local waiter = CityKit.Npc(m, "salesperson", seed * 13 + 1, F * CFrame.new(W / 2 - 2.5, 0.3, -1.5), "none", true)
	if waiter then
		local tray = Column(m, "Tray", F, 0, 0, 0, 0.1, 1.4, rgb(200, 200, 208), M.Metal)
		local path = { Vector3.new(W / 2 - 2.5, 0.3, -1.5), Vector3.new(4, 0.3, -9.6), Vector3.new(-3, 0.3, -9.8), Vector3.new(-6.5, 0.3, -3.2) }
		CityKit.Actor(waiter, F.Position, function(t: number)
			local total = 16
			local u = (t % total) / total * #path
			local i = math.floor(u)
			local f = u - i
			local a, b = path[i + 1], path[(i + 1) % #path + 1]
			-- marche, puis petite pause à chaque point
			local walk = math.clamp(f / 0.7, 0, 1)
			local p = a:Lerp(b, walk * walk * (3 - 2 * walk))
			local cf = F * CFrame.lookAt(p, p + (b - a).Unit * Vector3.new(1, 0, 1) + Vector3.new(0, 0, 0.001))
			waiter:PivotTo(cf)
			CityKit.Animate(waiter, walk < 1 and "walk" or "talk", t)
			tray.CFrame = cf * CFrame.new(0.9, 4.1, -0.9) * CityKit.UPRIGHT
		end, seed)
	end
	local _ = sitters
end

----------------------------------------------------------------------
-- ⛲ Square
----------------------------------------------------------------------

local function buildSquare(m: Model, F: CFrame, seed: number)
	local S = 34
	Box(m, "SquarePave", F, -S / 2, S / 2, -0.1, 0.22, -S / 2, S / 2, PAVER, M.Pavement, true)
	-- joints en damier (bandes sombres)
	for i = 1, 5 do
		local v = -S / 2 + i * S / 6
		Box(m, "PaveJoint", F, v - 0.08, v + 0.08, 0.22, 0.26, -S / 2, S / 2, rgb(170, 164, 154), M.SmoothPlastic)
	end
	-- parterres aux 4 coins + arbres
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local cx, cz = sx * (S / 2 - 5), sz * (S / 2 - 5)
			Box(m, "BedCurb", F, cx - 3.6, cx + 3.6, 0.22, 0.8, cz - 3.6, cz + 3.6, STONE, M.Concrete, true)
			Box(m, "BedLawn", F, cx - 3.2, cx + 3.2, 0.8, 0.9, cz - 3.2, cz + 3.2, rgb(100, 160, 80), M.Grass)
			tree(m, F * CFrame.new(0, 0.9, 0), cx, cz, 14 + hash(seed, cx) * 4, seed + math.floor(cx * 7 + cz), "Round")
			for k = 0, 5 do
				local a = k / 6 * math.pi * 2
				Egg(m, "Tulip", F * CFrame.new(cx + math.cos(a) * 2.4, 1.25, cz + math.sin(a) * 2.4), Vector3.new(0.6, 0.7, 0.6), CityKit.Pick({ rgb(255, 80, 90), rgb(255, 200, 60), rgb(250, 140, 200) }, seed, k), M.SmoothPlastic)
			end
		end
	end
	-- fontaine Wallace (4 cariatides simplifiées, dôme, filet d'eau)
	local W = F * CFrame.new(0, 0.22, 0)
	local green = rgb(28, 76, 52)
	Column(m, "WallaceBase", W, 0, 0, 0, 1.2, 3.2, green, M.Metal, true)
	for k = 0, 3 do
		local a = k * math.pi / 2
		Column(m, "Caryatid", W, math.cos(a) * 0.9, math.sin(a) * 0.9, 1.2, 5.6, 0.5, green, M.Metal)
		CityKit.Ball(m, "CaryatidHead", (W * CFrame.new(math.cos(a) * 0.9, 5.8, math.sin(a) * 0.9)).Position, 0.5, green, M.Metal)
	end
	Egg(m, "WallaceDome", W * CFrame.new(0, 6.6, 0), Vector3.new(2.8, 1.6, 2.8), green, M.Metal)
	CityKit.Ball(m, "WallaceFinial", (W * CFrame.new(0, 7.5, 0)).Position, 0.4, green, M.Metal)
	local jet = Column(m, "WallaceWater", W, 0, 0, 1.2, 6, 0.16, rgb(170, 220, 240), M.Glass)
	jet.Transparency = 0.4
	-- bancs face à la fontaine + lampadaires
	for k = 0, 3 do
		local a = k * math.pi / 2
		CityKit.Bench(m, F * CFrame.new(math.cos(a) * 8, 0.22, math.sin(a) * 8) * CFrame.Angles(0, -a + math.pi / 2, 0), 4.6)
		local b = k * math.pi / 2 + math.pi / 4
		CityKit.Lantern(m, F * CFrame.new(math.cos(b) * 12, 0.22, math.sin(b) * 12), 10)
	end
	-- promeneurs assis / debout
	local reader = CityKit.Npc(m, "elder", seed * 7 + 1, F * CFrame.new(0, 0.22 + 0.05, 8.1) * CFrame.Angles(0, 0, 0), "none", false)
	CityKit.Idle(reader, "sit", 2)
	local mom = CityKit.Npc(m, "pedestrian", seed * 7 + 2, F * CFrame.new(-4, 0.22, -6) * CFrame.Angles(0, 0.6, 0), "bag", true)
	CityKit.Idle(mom, "talk", 4)
	local kid = CityKit.Npc(m, "kid", seed * 7 + 3, F * CFrame.new(-2.6, 0.22, -6.6) * CFrame.Angles(0, -2.4, 0), "none", true)
	CityKit.Idle(kid, "wave", 1)
end

----------------------------------------------------------------------
-- 🚲 Vélos en libre-service, 🚌 arrêt de bus, lampadaire double
----------------------------------------------------------------------

local function buildBikes(m: Model, F: CFrame, seed: number)
	local kiosk = Box(m, "BikeKiosk", F, -6.6, -5.4, 0, 5.6, -0.6, 0.6, rgb(60, 140, 200), M.SmoothPlastic, true)
	Glow(Box(m, "BikeScreen", F, -6.64, -5.4, 3.4, 4.8, -0.4, 0.4, rgb(200, 236, 255), M.Glass))
	Text(kiosk, Enum.NormalId.Front, "🚲", WHITE, nil, Enum.Font.GothamBlack, 60)
	Box(m, "DockRail", F, -5, 6, 0, 0.3, -0.3, 0.3, rgb(90, 94, 100), M.Metal, true)
	for i = 0, 4 do
		local x = -4 + i * 2.4
		Box(m, "Dock", F, x - 0.2, x + 0.2, 0.3, 2.4, -0.2, 0.2, rgb(60, 140, 200), M.Metal)
		if hash(seed, i) < 0.75 then
			local bike = F * CFrame.new(x, 0, -1.4) * CFrame.Angles(0, math.pi / 2, 0)
			for _, bx in ipairs({ -1.4, 1.4 }) do
				Part(m, "Wheel", Vector3.new(0.12, 2.2, 2.2), bike * CFrame.new(bx, 1.1, 0), rgb(30, 30, 34), M.Rubber, "Cyl")
			end
			CityKit.Beam(m, "Frame", (bike * CFrame.new(-1.4, 1.1, 0)).Position, (bike * CFrame.new(0.3, 2.3, 0)).Position, 0.16, 0.16, rgb(60, 140, 200), M.Metal)
			CityKit.Beam(m, "Frame", (bike * CFrame.new(1.4, 1.1, 0)).Position, (bike * CFrame.new(0.3, 2.3, 0)).Position, 0.16, 0.16, rgb(60, 140, 200), M.Metal)
			Box(m, "Saddle", bike, -0.5, 0.2, 2.6, 2.8, -0.2, 0.2, rgb(30, 30, 34), M.Fabric)
			Box(m, "Basket", bike, 1.3, 2.1, 2.2, 2.9, -0.4, 0.4, rgb(90, 94, 100), M.Metal)
		end
	end
end

local function buildBusStop(m: Model, F: CFrame, seed: number)
	local glass = rgb(200, 226, 236)
	Box(m, "ShelterRoof", F, -5, 5, 8.2, 8.6, -1.6, 2.4, rgb(60, 64, 72), M.Metal)
	for _, x in ipairs({ -4.8, 4.8 }) do
		Box(m, "ShelterPost", F, x - 0.15, x + 0.15, 0, 8.2, 2, 2.3, rgb(60, 64, 72), M.Metal, true)
	end
	local back = Part(m, "ShelterBack", Vector3.new(9.4, 7, 0.14), F * CFrame.new(0, 4.3, 2.15), glass, M.Glass, nil, true)
	back.Transparency = 0.55
	local ad = Box(m, "ShelterAd", F, 2.2, 4.6, 1.2, 7.2, 1.4, 1.9, WHITE, M.SmoothPlastic)
	Glow(ad)
	Text(ad, Enum.NormalId.Front, "🧠 " .. Locale.T("Dopamine Clicker"), rgb(230, 60, 140), rgb(255, 240, 250), Enum.Font.FredokaOne, 60)
	Box(m, "ShelterBench", F, -3.8, 1.6, 1.3, 1.5, 1.2, 2, WOOD, M.Wood)
	local pole = Column(m, "StopPole", F, -6, -1.2, 0, 9.6, 0.24, rgb(60, 64, 72), M.Metal, true)
	local _ = pole
	local plate = Box(m, "StopPlate", F, -6.9, -5.1, 8, 9.8, -1.3, -1.1, rgb(250, 200, 40), M.SmoothPlastic)
	Text(plate, Enum.NormalId.Front, "🚌", rgb(40, 40, 50), nil, Enum.Font.GothamBlack, 80)
	-- deux personnes qui attendent
	local a = CityKit.Npc(m, "shopper", seed * 5 + 1, F * CFrame.new(-2, 1.35, 1.45) * CFrame.Angles(0, math.pi, 0), "bag", false)
	CityKit.Idle(a, "sit", 3)
	local b = CityKit.Npc(m, "pedestrian", seed * 5 + 2, F * CFrame.new(3, 0, -0.6) * CFrame.Angles(0, math.pi - 0.4, 0), "phone", true)
	CityKit.Idle(b, "idle", 6)
end

local function buildLamp(m: Model, F: CFrame, _seed: number)
	local c = rgb(30, 50, 44)
	Column(m, "LampFoot", F, 0, 0, 0, 1.2, 1.1, c, M.Metal, true)
	Column(m, "LampPole", F, 0, 0, 1.2, 12, 0.36, c, M.Metal, true)
	for _, sx in ipairs({ -1, 1 }) do
		CityKit.Rod(m, "LampArm", (F * CFrame.new(0, 11.4, 0)).Position, (F * CFrame.new(sx * 2, 12.4, 0)).Position, 0.18, c, M.Metal)
		Glow(Box(m, "LampGlobe", F * CFrame.new(sx * 2, 12, 0), -0.4, 0.4, -0.9, 0, -0.4, 0.4, WARM, M.Glass))
		Wedge(m, "LampHat", Vector3.new(1.1, 0.5, 0.55), F * CFrame.new(sx * 2, 12.25, 0.275), c, M.Metal)
		Wedge(m, "LampHat", Vector3.new(1.1, 0.5, 0.55), F * CFrame.new(sx * 2, 12.25, -0.275) * CFrame.Angles(0, math.pi, 0), c, M.Metal)
	end
end

----------------------------------------------------------------------
-- 🏘️ Rangée de maisons de ville (décor, on n'y entre pas)
----------------------------------------------------------------------

-- 3 maisons étroites mitoyennes de 3 niveaux : perron à marches et rampe,
-- porte peinte à imposte, bow-window au rez-de-chaussée, fenêtres à
-- guillotine, corniche, toit en mansarde d'ardoise avec lucarnes, cheminées
local TERRACE_COLORS = { rgb(170, 96, 72), rgb(226, 214, 190), rgb(120, 136, 150), rgb(190, 120, 96), rgb(236, 226, 206) }
local DOOR_COLORS = { rgb(30, 60, 110), rgb(140, 30, 40), rgb(30, 90, 60), rgb(40, 40, 46), rgb(230, 180, 40) }

local function buildTerrace(m: Model, F: CFrame, seed: number)
	local HW, D, H = 11.6, 12, 25
	for i = 0, 2 do
		local x = (i - 1) * HW
		local H0 = F * CFrame.new(x, 0, 1)
		local wall = CityKit.Pick(TERRACE_COLORS, seed, i)
		local brick = wall.R > wall.B * 1.3
		Box(m, "HouseBody", H0, -HW / 2, HW / 2, 0, H, -D / 2, D / 2, wall, brick and M.Brick or M.Plaster, true)
		Box(m, "Basement", H0, -HW / 2 - 0.05, HW / 2 + 0.05, 0, 2.4, -D / 2 - 0.1, D / 2, STONE, M.Concrete, true)
		-- mansarde (pente avant) + lucarne
		Wedge(m, "Mansard", Vector3.new(HW, 5, 3), H0 * CFrame.new(0, H + 2.5, -D / 2 + 1.5), rgb(70, 74, 86), M.Slate)
		Box(m, "RoofFlat", H0, -HW / 2, HW / 2, H, H + 5, -D / 2 + 3, D / 2, rgb(80, 82, 92), M.Slate)
		Box(m, "Dormer", H0, -1.4, 1.4, H + 1.2, H + 4.2, -D / 2 + 0.6, -D / 2 + 2.4, WHITE, M.Wood)
		Box(m, "DormerGlass", H0, -1, 1, H + 1.6, H + 3.8, -D / 2 + 0.52, -D / 2 + 0.6, GLASS, M.Glass)
		Box(m, "Cornice", H0, -HW / 2, HW / 2, H - 0.8, H, -D / 2 - 0.5, -D / 2, STONE, M.Concrete)
		Box(m, "ChimneyStack", H0, HW / 2 - 1.4, HW / 2 + 0.2, H + 4, H + 7, 1, 3, BRICK_D, M.Brick)
		-- perron + porte à imposte (à gauche) ; bow-window (à droite)
		local dx = -HW / 2 + 2.6
		for k = 0, 3 do
			Box(m, "Stoop", H0, dx - 1.6, dx + 1.6, 0, 0.6 + k * 0.6, -D / 2 - 3.6 + k * 0.9, -D / 2, STONE, M.Concrete, true)
		end
		for _, sx in ipairs({ -1, 1 }) do
			CityKit.Rod(m, "StoopRail", (H0 * CFrame.new(dx + sx * 1.6, 1.4, -D / 2 - 3.4)).Position, (H0 * CFrame.new(dx + sx * 1.6, 4.4, -D / 2 - 0.4)).Position, 0.12, IRON, M.Metal)
		end
		Box(m, "Door", H0, dx - 1.3, dx + 1.3, 2.4, 9.8, -D / 2 - 0.12, -D / 2, CityKit.Pick(DOOR_COLORS, seed, i + 7), M.Wood)
		Glow(Box(m, "Fanlight", H0, dx - 1.3, dx + 1.3, 10.1, 11.1, -D / 2 - 0.12, -D / 2, WARM, M.Glass))
		Box(m, "DoorKnob", H0, dx + 0.8, dx + 1, 5.8, 6, -D / 2 - 0.24, -D / 2 - 0.12, rgb(214, 176, 80), M.Metal)
		local bx = HW / 2 - 3.6
		Box(m, "BayBase", H0, bx - 2.6, bx + 2.6, 2.4, 3.8, -D / 2 - 1.6, -D / 2, STONE, M.Concrete, true)
		Glow(Box(m, "BayGlass", H0, bx - 2.4, bx + 2.4, 3.8, 9.4, -D / 2 - 1.5, -D / 2 - 1.4, hash(seed, i) < 0.5 and WARM or GLASS, M.Glass))
		Box(m, "BayMullion", H0, bx - 0.08, bx + 0.08, 3.8, 9.4, -D / 2 - 1.58, -D / 2 - 1.5, WHITE, M.Wood)
		Box(m, "BayRoof", H0, bx - 2.7, bx + 2.7, 9.4, 10, -D / 2 - 1.7, -D / 2, rgb(70, 74, 86), M.Slate)
		-- étages : 2 fenêtres à guillotine par niveau
		for f = 0, 1 do
			local y0 = 12.6 + f * 6
			for _, wx in ipairs({ -2.6, 2.6 }) do
				local lit = hash(seed, i * 10 + f * 3 + wx) < 0.3
				local g = Box(m, "Sash", H0, wx - 1.2, wx + 1.2, y0, y0 + 4.2, -D / 2 - 0.08, -D / 2, lit and WARM or GLASS, M.Glass)
				if lit then
					Glow(g)
				end
				Box(m, "SashBar", H0, wx - 1.2, wx + 1.2, y0 + 2.05, y0 + 2.2, -D / 2 - 0.14, -D / 2 - 0.08, WHITE, M.Wood)
				Box(m, "SashLintel", H0, wx - 1.5, wx + 1.5, y0 + 4.2, y0 + 4.7, -D / 2 - 0.2, -D / 2, STONE, M.Concrete)
				Box(m, "SashSill", H0, wx - 1.5, wx + 1.5, y0 - 0.3, y0, -D / 2 - 0.35, -D / 2, STONE, M.Concrete)
			end
		end
		-- fenêtres de l'arrière (côté cour)
		for f = 0, 2 do
			Box(m, "BackWindow", H0, -1.4, 1.4, 4 + f * 7, 8 + f * 7, D / 2, D / 2 + 0.08, GLASS, M.Glass)
		end
		-- poubelle et jardinière devant
		if i ~= 1 then
			Egg(m, "Planter", H0 * CFrame.new(bx, 0.5, -D / 2 - 3), Vector3.new(3, 1.2, 1.4), rgb(70, 130, 64), M.Grass)
		end
	end
	-- murs pignons aux deux bouts : fenêtres étroites
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * HW * 1.5
		for f = 0, 2 do
			Box(m, "GableWindow", F * CFrame.new(x, 0, 1), sx > 0 and 0 or -0.08, sx > 0 and 0.08 or 0, 4 + f * 7, 8 + f * 7, -1.2, 1.2, GLASS, M.Glass)
		end
	end
	local neighbour = CityKit.Npc(m, "elder", seed * 7 + 2, F * CFrame.new(-HW + 2.6, 0, -D / 2 - 3.8 + 1) * CFrame.Angles(0, math.pi, 0), "none", true)
	CityKit.Idle(neighbour, "wave", 1.5)
end

DistrictTownhouse.BUILDERS = {
	TwnTerrace = buildTerrace,
	TwnTree = buildTree,
	TwnCornerShop = buildCornerShop,
	TwnCafe = buildCafe,
	TwnSquare = buildSquare,
	TwnBikes = buildBikes,
	TwnBusStop = buildBusStop,
	TwnLamp = buildLamp,
}
DistrictTownhouse.BIG = { TwnCornerShop = true, TwnSquare = true }
DistrictTownhouse.IMPOSTORS = {
	TwnTerrace = function(m: Model, F: CFrame, seed: number)
		for i = 0, 2 do
			Box(m, "ImpHouse", F * CFrame.new((i - 1) * 11.6, 0, 1), -5.8, 5.8, 0, 30, -6, 6, CityKit.Pick(TERRACE_COLORS, seed, i), M.Plaster, true)
		end
	end,
	TwnCornerShop = function(m: Model, F: CFrame)
		Box(m, "ImpBlock", F * CFrame.new(0, 0, 3), -9, 9, 0, 30, -7, 7, BRICK, M.Brick, true)
	end,
	TwnCafe = function(m: Model, F: CFrame)
		Box(m, "ImpBlock", F * CFrame.new(0, 0, 6), -9, 9, 0, 28, -6, 6, CREAM, M.Plaster, true)
	end,
}

return DistrictTownhouse
