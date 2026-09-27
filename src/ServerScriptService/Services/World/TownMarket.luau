--[[
	TownMarket (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownMarket

	🛒 Dopamine Town (v9.7, BUILDINGS97) : le SUPERMARCHÉ « MégaDopa », hors
	de la porte de la ville, à droite de la route d'arrivée (en venant de la
	ville). Le serveur ne pose que la COQUE (collisions justes pour tout le
	monde) et le parking ; l'intérieur (rayons, produits, vrais objets de la
	maison à acheter, caisses, caissières, chariots, lumières) et les
	voitures garées sont construits par chaque client, en flux
	(Client/World/MarketInterior).
	  - grand bâtiment 70 x 48 (hauteur 16 sous toit) : façade en béton
	    clair, bandeau aux couleurs de l'enseigne, TOUR D'ENTRÉE rose avec la
	    grande enseigne, sas vitré à PORTES COULISSANTES (le client les ouvre
	    à l'approche), vitrines, enseignes "Épicerie" / "Maison & Jardin" ;
	    toit plat avec lanterneaux (la lumière du jour entre), groupes de
	    ventilation ; côtés finis (pilastres, bandeau, fenêtres hautes,
	    sorties de secours, descentes d'eau, logo) ; arrière : quais de
	    livraison (portes sectionnelles, butoirs, auvent) ;
	  - PARKING devant la façade : enrobé, 2 rangées de places marquées,
	    passage piéton devant l'entrée, îlots plantés, lampadaires, totem de
	    l'enseigne au bord de la route ; trottoir devant le magasin.
	Aucune vraie lumière ici ; aucune grande surface en Neon.

	Contrat (client MarketInterior) : Model "Supermarket" dans
	DopamineTown.Market, attributs
	  MarketCF     CFrame : pied de la façade (milieu), LookVector vers la route
	  InteriorCF   CFrame : centre du SOL intérieur (dessus), mêmes axes
	  InteriorSize Vector3 (largeur, hauteur sous toit, profondeur)
	  DoorCF       CFrame : seuil du sas (sol), LookVector vers le parking
	  LotCF        CFrame : centre du parking (dessus de l'enrobé)
	  LotSize      Vector3 (largeur, 0, profondeur)
	  StallsA / StallsB  nombre de places par rangée (x = -33 + 6·(i - 0.5))
	Vantaux vitrés "DoorPanel" (attribut SlideX), jamais bloquants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)

local TownMarket = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part

TownMarket.NAME = "MegaDopa" -- (clé anglaise ; en français : "MégaDopa")

local W = WorldLayout.MARKET_W -- 70
local D = WorldLayout.MARKET_D -- 48
local T = 1 -- épaisseur des murs
local ROOF = 16 -- dessous du toit
local TOP = 19 -- haut des murs (acrotère)
local FLOOR = 0.2 -- dessus du sol intérieur
local DOOR_W = 12 -- baie d'entrée dans la façade
local DOOR_H = 9
local LOT_Y = -0.5 -- dessus de l'enrobé (niveau de la route)
local LOT_Z0, LOT_Z1 = -52, -10 -- parking (z local)
local STALL_W = 6

TownMarket.BRAND = Color3.fromRGB(236, 72, 140)
TownMarket.BRAND2 = Color3.fromRGB(120, 90, 200)
local BRAND = TownMarket.BRAND
local BRAND2 = TownMarket.BRAND2
local FACADE = Color3.fromRGB(236, 228, 214)
local FACADE2 = Color3.fromRGB(214, 206, 194)
local GLASS = Color3.fromRGB(150, 196, 226)
local YELLOW = Color3.fromRGB(255, 208, 72)

-- Boîte entre deux coins (repère `cf`)
local function box(parent: Instance, name: string, cf: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material, profile: string?): BasePart
	return part(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, profile)
end

local function glassBox(parent: Instance, name: string, cf: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, transparency: number, profile: string?): BasePart
	local g = box(parent, name, cf, x0, x1, y0, y1, z0, z1, GLASS, M.Glass, profile or "prop")
	g.Transparency = transparency
	g.Reflectance = 0.15
	return g
end

-- Panneau texte (SurfaceGui) traduisible (attribut "LocText" : le client traduit)
local function sign(parent: Instance, name: string, cf: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, text: string, textColor: Color3, pps: number, maxDistance: number, face: Enum.NormalId?): BasePart
	local board = box(parent, name, cf, x0, x1, y0, y1, z0, z1, color, M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(board, face or Enum.NormalId.Front, pps, nil, maxDistance, 0.4)
	local label = TownKit.Label(body, "Text", text, 0.04, 0.08, 0.92, 0.84, textColor, Enum.Font.FredokaOne, true)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.White
	stroke.Thickness = 2
	stroke.Parent = label
	return board
end

----------------------------------------------------------------------
-- Bâtiment
----------------------------------------------------------------------

local function building(model: Model, cf: CFrame)
	local hw = W / 2
	-- dalle du sol (sous les murs)
	box(model, "Floor", cf, -hw, hw, -1.3, FLOOR, 0, D, Color3.fromRGB(226, 222, 216), M.Concrete, "solid")
	-- murs : façade (baie d'entrée), fond, côtés
	box(model, "FrontWall", cf, -hw, -DOOR_W / 2, FLOOR, TOP, 0, T, FACADE, M.Concrete, "solid")
	box(model, "FrontWall", cf, DOOR_W / 2, hw, FLOOR, TOP, 0, T, FACADE, M.Concrete, "solid")
	box(model, "FrontHeader", cf, -DOOR_W / 2, DOOR_W / 2, DOOR_H, TOP, 0, T, FACADE, M.Concrete, "solid")
	box(model, "BackWall", cf, -hw, hw, FLOOR, TOP, D - T, D, FACADE2, M.Concrete, "solid")
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "SideWall", cf, sx < 0 and -hw or hw - T, sx < 0 and -hw + T or hw, FLOOR, TOP, T, D - T, FACADE2, M.Concrete, "solid")
	end
	-- toit : bandes pleines + 3 lanterneaux vitrés (la lumière du jour entre)
	local sky = { 12, 24, 36 }
	local z = T
	for _, zc in ipairs(sky) do
		box(model, "Roof", cf, -hw + T, hw - T, ROOF, ROOF + 1, z, zc - 1.5, Color3.fromRGB(196, 196, 204), M.Concrete, "solid")
		for _, sx in ipairs({ -1, 1 }) do
			box(model, "Roof", cf, sx < 0 and -hw + T or 28, sx < 0 and -28 or hw - T, ROOF, ROOF + 1, zc - 1.5, zc + 1.5, Color3.fromRGB(196, 196, 204), M.Concrete, "solid")
		end
		local sk = glassBox(model, "Skylight", cf, -28, 28, ROOF + 0.2, ROOF + 0.8, zc - 1.5, zc + 1.5, 0.35, "prop")
		sk.CastShadow = false
		box(model, "SkylightCurb", cf, -28.2, 28.2, ROOF + 1, ROOF + 1.5, zc - 1.7, zc - 1.5, Color3.fromRGB(176, 180, 190), M.Metal, "deco")
		box(model, "SkylightCurb", cf, -28.2, 28.2, ROOF + 1, ROOF + 1.5, zc + 1.5, zc + 1.7, Color3.fromRGB(176, 180, 190), M.Metal, "deco")
		z = zc + 1.5
	end
	box(model, "Roof", cf, -hw + T, hw - T, ROOF, ROOF + 1, z, D - T, Color3.fromRGB(196, 196, 204), M.Concrete, "solid")
	-- couvertines (haut des murs)
	box(model, "Coping", cf, -hw - 0.2, hw + 0.2, TOP, TOP + 0.35, -0.2, T + 0.1, C.White, M.Concrete, "deco")
	box(model, "Coping", cf, -hw - 0.2, hw + 0.2, TOP, TOP + 0.35, D - T - 0.1, D + 0.2, C.White, M.Concrete, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "Coping", cf, sx < 0 and -hw - 0.2 or hw - T - 0.1, sx < 0 and -hw + T + 0.1 or hw + 0.2, TOP, TOP + 0.35, T + 0.1, D - T - 0.1, C.White, M.Concrete, "deco")
	end
	-- groupes de ventilation sur le toit
	for i, spot in ipairs({ { -18, 30 }, { 4, 42 }, { 22, 18 } }) do
		local x, zc = spot[1], spot[2]
		box(model, "HVAC", cf, x - 3, x + 3, ROOF + 1, ROOF + 3.6, zc - 2.2, zc + 2.2, Color3.fromRGB(206, 208, 214), M.DiamondPlate, "deco")
		local fan = part(model, "HVACFan", Vector3.new(0.3, 2.8, 2.8), cf * CFrame.new(x + (i % 2 == 0 and 1.3 or -1.3), ROOF + 3.75, zc) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 124, 136), M.Metal, "deco")
		;(fan :: Part).Shape = Enum.PartType.Cylinder
	end
end

-- Façade : bandeau, tour d'entrée + enseigne, sas vitré, vitrines, enseignes
local function facade(model: Model, cf: CFrame)
	local hw = W / 2
	-- bandeau aux couleurs de l'enseigne (sur la façade)
	box(model, "BrandBand", cf, -hw - 0.1, hw + 0.1, 14.6, TOP - 0.05, -0.35, 0, BRAND2, M.SmoothPlastic, "deco")
	box(model, "BrandStripe", cf, -hw - 0.1, hw + 0.1, 13.9, 14.6, -0.35, 0, YELLOW, M.SmoothPlastic, "deco")
	-- tour d'entrée (piliers + haut) et grande enseigne
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "TowerPier", cf, sx < 0 and -14 or 9, sx < 0 and -9 or 14, 0, 22, -1.6, 0, BRAND, M.Concrete, "solid")
	end
	box(model, "TowerTop", cf, -14, 14, 11, 26, -1.6, 0, BRAND, M.Concrete, "decoS")
	box(model, "TowerCap", cf, -14.4, 14.4, 26, 26.6, -2, 0.4, C.White, M.Concrete, "deco")
	sign(model, "BigSign", cf, -12.5, 12.5, 15.6, 24.6, -1.75, -1.6, C.White, "🧠 MegaDopa", BRAND, 20, 700)
	local tag = sign(model, "Tagline", cf, -11, 11, 12.1, 14.9, -1.75, -1.6, BRAND2, "Everything for your home!", C.White, 30, 250)
	tag.Color = BRAND2
	-- sas vitré (auvent au-dessus, portes coulissantes devant)
	local vx = 7
	local vz = -6
	for _, sx in ipairs({ -1, 1 }) do
		glassBox(model, "VestibuleSide", cf, sx < 0 and -vx or vx - 0.3, sx < 0 and -vx + 0.3 or vx, FLOOR, 10.2, vz, 0, 0.4, "prop")
		-- vitres fixes de part et d'autre des portes
		glassBox(model, "VestibuleLite", cf, sx < 0 and -vx + 0.3 or 3.7, sx < 0 and -3.7 or vx - 0.3, FLOOR, 8.2, vz, vz + 0.3, 0.4, "prop")
		box(model, "VestibulePost", cf, sx < 0 and -3.9 or 3.7, sx < 0 and -3.7 or 3.9, FLOOR, 8.4, vz - 0.1, vz + 0.4, Color3.fromRGB(176, 180, 190), M.Metal, "deco")
	end
	box(model, "VestibuleFloor", cf, -vx, vx, -1.3, FLOOR, vz, 0, Color3.fromRGB(206, 200, 196), M.Concrete, "solid")
	box(model, "VestibuleHeader", cf, -vx, vx, 8.2, 10.2, vz - 0.05, vz + 0.35, Color3.fromRGB(176, 180, 190), M.Metal, "deco")
	sign(model, "Welcome", cf, -4.5, 4.5, 8.5, 9.9, vz - 0.13, vz - 0.05, C.White, "Welcome! Open every day", BRAND, 40, 120)
	box(model, "Canopy", cf, -9.5, 9.5, 10.2, 10.9, vz - 2.6, -1.6, C.White, M.Concrete, "decoS")
	box(model, "CanopyEdge", cf, -9.6, 9.6, 10.2, 10.9, vz - 2.75, vz - 2.6, BRAND, M.SmoothPlastic, "deco")
	-- deux vantaux vitrés coulissants (le client les ouvre ; jamais bloquants)
	for _, sx in ipairs({ -1, 1 }) do
		local panel = box(model, "DoorPanel", cf, sx < 0 and -3.7 or 0.02, sx < 0 and -0.02 or 3.7, FLOOR, 8.2, vz + 0.35, vz + 0.5, GLASS, M.Glass, "deco")
		panel.Transparency = 0.4
		panel.Reflectance = 0.15
		panel:SetAttribute("SlideX", sx * 3.2)
	end
	-- vitrines de part et d'autre de la tour (menuiseries, allège)
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx < 0 and -hw + 3 or 15.5, sx < 0 and -15.5 or hw - 3
		box(model, "Storefront", cf, x0 - 0.4, x1 + 0.4, 0, 1.6, -0.5, 0, FACADE2, M.Concrete, "prop")
		local g = glassBox(model, "ShopWindow", cf, x0, x1, 1.6, 9, -0.26, -0.08, 0.1, "deco")
		g.Color = Color3.fromRGB(96, 124, 150)
		box(model, "WindowHead", cf, x0 - 0.4, x1 + 0.4, 9, 9.5, -0.5, 0, C.White, M.Concrete, "deco")
		local n = 4
		for i = 0, n do
			local x = x0 + i * (x1 - x0) / n
			box(model, "WindowMullion", cf, x - 0.15, x + 0.15, 1.6, 9, -0.42, -0.26, Color3.fromRGB(176, 180, 190), M.Metal, "deco")
		end
	end
	-- enseignes de rayons sur la façade
	sign(model, "SubSign", cf, -32, -17, 10.2, 13, -0.55, -0.35, C.White, "🥕 Groceries", Color3.fromRGB(64, 150, 90), 26, 250)
	sign(model, "SubSign", cf, 17, 32, 10.2, 13, -0.55, -0.35, C.White, "🏠 Home & Garden", BRAND2, 26, 250)
	-- trottoir devant le magasin (+ bordure)
	box(model, "Apron", cf, -hw - 1, hw + 1, -1.3, 0, LOT_Z1 + 0.4, 0, C.Walk, M.Pavement, "solid")
	box(model, "Curb", cf, -hw - 1, hw + 1, -1.3, 0, LOT_Z1, LOT_Z1 + 0.4, C.Curb, M.Concrete, "solid")
	-- bornes devant le sas (pas de voiture dans l'entrée)
	for _, x in ipairs({ -8.5, -4.5, 4.5, 8.5 }) do
		TownKit.Column(model, "Bollard", (cf * CFrame.new(x, 0, -8.6)).Position, 2.6, 0.7, YELLOW, M.Metal, "prop")
	end
end

-- Côtés et arrière (jamais de mur nu)
local function sides(model: Model, cf: CFrame)
	local hw = W / 2
	for _, sx in ipairs({ -1, 1 }) do
		-- repère de la face latérale : x le long du mur (profondeur), -Z vers dehors
		local R = cf * CFrame.new(sx * hw, 0, D / 2) * CFrame.Angles(0, sx * -math.pi / 2, 0)
		box(model, "SideBand", R, -D / 2 - 0.1, D / 2 + 0.1, 14.6, TOP - 0.05, -0.35, 0, BRAND2, M.SmoothPlastic, "deco")
		box(model, "SideStripe", R, -D / 2 - 0.1, D / 2 + 0.1, 13.9, 14.6, -0.35, 0, YELLOW, M.SmoothPlastic, "deco")
		for i = 0, 3 do
			local x = -D / 2 + 4 + i * (D - 8) / 3
			box(model, "Pilaster", R, x - 0.8, x + 0.8, -0.6, 13.9, -0.6, 0, FACADE, M.Concrete, "deco")
		end
		-- fenêtres hautes (entre les pilastres)
		for i = 0, 2 do
			local x = -D / 2 + 4 + (i + 0.5) * (D - 8) / 3
			if i ~= 1 then
				local g = glassBox(model, "HighWindow", R, x - 4.5, x + 4.5, 10, 12.6, -0.2, -0.05, 0.15, "deco")
				g.Color = Color3.fromRGB(110, 140, 170)
				box(model, "HighSill", R, x - 4.8, x + 4.8, 9.6, 10, -0.5, 0, C.White, M.Concrete, "deco")
			end
		end
		-- sortie de secours (porte, auvent, marche, panneau vert)
		local ex = 2
		box(model, "ExitFrame", R, ex - 2.1, ex + 2.1, 0, 8.3, -0.18, 0, Color3.fromRGB(176, 180, 190), M.Metal, "deco")
		box(model, "ExitDoor", R, ex - 1.7, ex + 1.7, 0.2, 7.9, -0.3, -0.18, Color3.fromRGB(150, 156, 170), M.Metal, "deco")
		box(model, "ExitBar", R, ex - 1.4, ex + 1.4, 3.6, 3.9, -0.42, -0.3, Color3.fromRGB(220, 60, 70), M.Metal, "deco")
		box(model, "ExitCanopy", R, ex - 2.8, ex + 2.8, 8.6, 9, -2.4, 0, Color3.fromRGB(176, 180, 190), M.Metal, "deco")
		box(model, "ExitSign", R, ex - 1, ex + 1, 8.4, 8.58, -0.8, -0.3, Color3.fromRGB(60, 180, 100), M.SmoothPlastic, "deco")
		box(model, "ExitStep", R, ex - 2.2, ex + 2.2, -1.3, 0.2, -2.2, 0, C.Walk, M.Concrete, "solid")
		-- descentes d'eau
		for _, x in ipairs({ -D / 2 + 1.2, D / 2 - 1.2 }) do
			TownKit.Column(model, "Downpipe", (R * CFrame.new(x, -0.4, -0.4)).Position, TOP - 0.2, 0.45, Color3.fromRGB(150, 154, 166), M.Metal, "deco")
		end
		-- logo peint (grand chariot) sur le côté
		sign(model, "SideLogo", R, 8.5, 18.5, 2, 8.4, -0.12, -0.04, BRAND, "🛒 MegaDopa", C.White, 14, 300)
	end
	-- arrière : quais de livraison
	local B = cf * CFrame.new(0, 0, D) * CFrame.Angles(0, math.pi, 0) -- -Z vers dehors (arrière)
	box(model, "DockPlatform", B, -8, 26, -1.3, 1.4, -4.5, 0, Color3.fromRGB(176, 172, 168), M.Concrete, "solid")
	for i, x in ipairs({ 2, 16 }) do
		box(model, "DockFrame", B, x - 4.6, x + 4.6, 1.4, 11, -0.2, 0, Color3.fromRGB(150, 156, 170), M.Metal, "deco")
		box(model, "DockDoor", B, x - 4.1, x + 4.1, 1.4, 10.6, -0.32, -0.2, Color3.fromRGB(206, 210, 218), M.CorrodedMetal, "deco")
		for _, sx in ipairs({ -1, 1 }) do
			box(model, "Bumper", B, x + sx * 3.4 - 0.4, x + sx * 3.4 + 0.4, 1.6, 3.2, -4.9, -4.5, Color3.fromRGB(40, 40, 46), M.Rubber, "deco")
		end
		sign(model, "DockNumber", B, x - 1, x + 1, 11.4, 12.8, -0.12, -0.04, YELLOW, tostring(i), Color3.fromRGB(40, 40, 46), 30, 150)
	end
	box(model, "DockCanopy", B, -8.5, 26.5, 12.8, 13.3, -5.5, 0, Color3.fromRGB(176, 180, 190), M.Metal, "decoS")
	sign(model, "DockSign", B, -24, -10, 9.6, 12, -0.12, -0.04, C.White, "🚚 Deliveries", BRAND2, 24, 200)
	box(model, "StaffDoor", B, -20, -16.8, 0.2, 7.6, -0.3, -0.05, Color3.fromRGB(150, 156, 170), M.Metal, "deco")
	box(model, "BackBand", B, -W / 2 - 0.1, W / 2 + 0.1, 14.6, TOP - 0.05, -0.35, 0, BRAND2, M.SmoothPlastic, "deco")
	for _, x in ipairs({ -W / 2 + 1.2, W / 2 - 1.2 }) do
		TownKit.Column(model, "Downpipe", (B * CFrame.new(x, -0.4, -0.4)).Position, TOP - 0.2, 0.45, Color3.fromRGB(150, 154, 166), M.Metal, "deco")
	end
end

----------------------------------------------------------------------
-- Parking
----------------------------------------------------------------------

local function parking(model: Model, cf: CFrame, geo: TownKit.Geo): (number, number)
	local hw = W / 2 + 1
	local lot = box(model, "Lot", cf, -hw, hw, LOT_Y - 0.7, LOT_Y, LOT_Z0, LOT_Z1, C.AsphaltDark, M.Asphalt, "solid")
	lot.CastShadow = false
	-- deux rangées de places (lignes blanches), allée au milieu, voie pompiers devant
	local rows = { { LOT_Z0 + 0.6, LOT_Z0 + 11 }, { -28, -17 } }
	local stalls = math.floor((2 * 33) / STALL_W)
	for _, row in ipairs(rows) do
		for i = 0, stalls do
			local x = -33 + i * STALL_W
			box(model, "StallLine", cf, x - 0.15, x + 0.15, LOT_Y, LOT_Y + 0.05, row[1], row[2], C.Line, M.SmoothPlastic, "deco")
		end
	end
	-- passage piéton (voie pompiers -> sas)
	for i = 0, 4 do
		local x = -4.4 + i * 2.2
		box(model, "Zebra", cf, x - 0.6, x + 0.6, LOT_Y, LOT_Y + 0.05, -16.4, LOT_Z1 - 0.3, C.Line, M.SmoothPlastic, "deco")
	end
	-- flèches de sens dans l'allée
	for _, x in ipairs({ -20, 20 }) do
		box(model, "Arrow", cf, x - 2.4, x + 2.4, LOT_Y, LOT_Y + 0.05, -34.8, -34.2, C.Line, M.SmoothPlastic, "deco")
		TownKit.Wedge(model, "ArrowHead", Vector3.new(1.8, 0.05, 1.6), cf * CFrame.new(x + (x > 0 and -3.2 or 3.2), LOT_Y + 0.025, -34.5) * CFrame.Angles(0, x > 0 and math.pi / 2 or -math.pi / 2, 0), C.Line, M.SmoothPlastic, "deco")
	end
	-- îlots plantés au bout des rangées + lampadaires
	for _, sx in ipairs({ -1, 1 }) do
		for _, row in ipairs(rows) do
			local x0, x1 = sx < 0 and -hw + 0.3 or 33.3, sx < 0 and -33.3 or hw - 0.3
			box(model, "Island", cf, x0, x1, LOT_Y - 0.1, LOT_Y + 0.5, row[1] + 0.5, row[2] - 0.5, C.Curb, M.Concrete, "prop")
			box(model, "IslandGrass", cf, x0 + 0.2, x1 - 0.2, LOT_Y + 0.5, LOT_Y + 0.55, row[1] + 0.7, row[2] - 0.7, C.Lawn, M.Grass, "deco")
		end
		-- (au bout d'une ligne de places, côté allée, sur un petit socle)
		local lx, lz = sx * 21, -40.6
		box(model, "LightBase", cf, lx - 0.6, lx + 0.6, LOT_Y, LOT_Y + 1, lz - 0.6, lz + 0.6, C.Curb, M.Concrete, "prop")
		TownKit.Column(model, "LightPole", (cf * CFrame.new(lx, LOT_Y + 1, lz)).Position, 15, 0.5, C.Metal, M.Metal, "prop")
		box(model, "LightArm", cf, lx - 2.6, lx + 2.6, LOT_Y + 15.6, LOT_Y + 16, lz - 0.2, lz + 0.2, C.Metal, M.Metal, "deco")
		for _, dx in ipairs({ -2.4, 2.4 }) do
			local head = box(model, "LightHead", cf, lx + dx - 0.7, lx + dx + 0.7, LOT_Y + 15.2, LOT_Y + 15.6, lz - 0.6, lz + 0.6, C.Glow, M.SmoothPlastic, "deco")
			TownKit.Glow(head)
		end
	end
	-- totem de l'enseigne au bord de la route
	-- (au coin du parking, côté route, loin de la porte)
	local totem = cf * CFrame.new(-W / 2 - 4.5, LOT_Y, LOT_Z0 + 4) * CFrame.Angles(0, math.rad(-90), 0)
	box(model, "PylonBase", totem, -3.4, 3.4, -0.3, 1.4, -1.4, 1.4, C.StoneDark, M.Granite, "prop")
	for _, x in ipairs({ -2, 2 }) do
		box(model, "PylonLeg", totem, x - 0.4, x + 0.4, 1.4, 14, -0.4, 0.4, C.MetalLight, M.Metal, "prop")
	end
	local panel = box(model, "PylonSign", totem, -4.4, 4.4, 14, 22.6, -0.8, 0.8, BRAND, M.SmoothPlastic, "deco")
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local _, body = TownKit.Surface(panel, face, 18, nil, 500, 0.4)
		TownKit.Gradient(body, BRAND, BRAND2, 90)
		body.BackgroundTransparency = 0
		TownKit.Label(body, "Brand", "🧠 MegaDopa", 0.05, 0.08, 0.9, 0.52, C.White, Enum.Font.FredokaOne, true)
		TownKit.Label(body, "Hours", "🛒 Open every day", 0.08, 0.64, 0.84, 0.26, Color3.fromRGB(255, 236, 150), Enum.Font.GothamBold, true)
	end
	box(model, "PylonCap", totem, -4.7, 4.7, 22.6, 23.1, -1, 1, C.White, M.Concrete, "deco")
	-- arbres des îlots (pas trop près des voitures)
	for _, sx in ipairs({ -1, 1 }) do
		for _, row in ipairs(rows) do
			local p = (cf * CFrame.new(sx * 34.4, LOT_Y + 0.5, (row[1] + row[2]) / 2)).Position
			pcall(TownKit.Tree, model, p, 11, math.floor(p.X + p.Z), nil)
		end
	end
	local _ = geo
	return stalls, stalls
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TownMarket.Build(folder: Instance, geo: TownKit.Geo): Model
	local cf = WorldLayout.MarketCFrame(geo.Count)
	local model = TownKit.Model(folder, "Supermarket")
	building(model, cf)
	facade(model, cf)
	sides(model, cf)
	local nA, nB = parking(model, cf, geo)
	model:SetAttribute("MarketCF", cf)
	model:SetAttribute("InteriorCF", cf * CFrame.new(0, FLOOR, D / 2))
	model:SetAttribute("InteriorSize", Vector3.new(W - 2 * T, ROOF - FLOOR, D - 2 * T))
	model:SetAttribute("DoorCF", cf * CFrame.new(0, FLOOR, -6))
	model:SetAttribute("LotCF", cf * CFrame.new(0, LOT_Y, (LOT_Z0 + LOT_Z1) / 2))
	model:SetAttribute("LotSize", Vector3.new(W + 2, 0, LOT_Z1 - LOT_Z0))
	model:SetAttribute("StallsA", nA)
	model:SetAttribute("StallsB", nB)
	model:SetAttribute("Name", TownMarket.NAME)
	-- (emprise réservée : aucun arbre ni objet semé dessus)
	geo.Reserve((cf * CFrame.new(0, 0, (LOT_Z0 + D) / 2)).Position, 52)
	return model
end

-- Zone du magasin + parking (repère MarketCF) : pour écarter les arbres
-- semés dessus par d'autres modules (bois autour de la ville...)
function TownMarket.InZone(cf: CFrame, p: Vector3, margin: number): boolean
	local rel = cf:PointToObjectSpace(p)
	return math.abs(rel.X) < W / 2 + 2 + margin and rel.Z > LOT_Z0 - 2 - margin and rel.Z < D + 6 + margin
end

-- Filet de sécurité : retire les ARBRES (modèles "Tree*") d'autres modules
-- plantés sur l'emprise (appelé par TownMap après la nature) ; renvoie le
-- nombre de pièces retirées (budget)
function TownMarket.ClearSite(decor: Instance, count: number): number
	local cf = WorldLayout.MarketCFrame(count)
	local removed = 0
	for _, d in ipairs(decor:GetDescendants()) do
		if d:IsA("Model") and string.sub(d.Name, 1, 4) == "Tree" and d.Parent and not d:FindFirstAncestor("Supermarket") then
			local pivot = d:GetPivot().Position
			local first = d:FindFirstChildWhichIsA("BasePart", true)
			local p = first and first.Position or pivot
			if TownMarket.InZone(cf, Vector3.new(p.X, cf.Position.Y, p.Z), 4) then
				for _, x in ipairs(d:GetDescendants()) do
					if x:IsA("BasePart") then
						removed += 1
					end
				end
				d:Destroy()
			end
		end
	end
	TownKit.Stats.Parts -= removed
	return removed
end

return TownMarket
