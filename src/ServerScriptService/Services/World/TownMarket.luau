--[[
	TownMarket (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownMarket

	🛒 Dopamine Town : le SUPERMARCHÉ « MégaDopa », hors de la porte de la
	ville, à droite de la route d'arrivée (en venant de la ville), l'entrée
	face au rond-point. Le serveur ne pose que la COQUE (collisions justes
	pour tout le monde) et le gros du parking ; l'intérieur (rayons,
	produits, vrais objets de la maison, caisses, café, aire de restauration,
	boutique Robux, personnages, lumières), les marquages du parking, les
	voitures garées et le CONTENU des écrans de classement sont construits
	par chaque client, en flux (Client/World/MarketInterior).

	v9.7 (BUILDINGS97) : 70 x 48. v9.8 (MARKET98) : 10x mieux et PLUS GRAND
	(WorldLayout.MARKET_W x MARKET_D = 104 x 68, sous toit à 18) :
	  - façade : grand ATRIUM vitré (mur-rideau à meneaux) dans une tour
	    rose qui porte l'enseigne, sas à portes coulissantes sous une
	    marquise sur deux colonnes, DEUX GRANDS ÉCRANS DE CLASSEMENT
	    (🏆 Dopamine / ♻️ Renaissances : cadres "LeaderScreen", le client y
	    affiche le top en direct), vitrines d'angle, enseignes des rayons
	    (Épicerie, Maison & Jardin, Café, Boutique Robux) ;
	  - toit : 3 lanterneaux sur toute la largeur, groupes de ventilation ;
	  - côtés finis (pilastres, bandeau, fenêtres hautes, sorties de
	    secours, descentes d'eau, logo) ; arrière : 3 quais de livraison ;
	  - PARKING : enrobé, allée d'accès depuis le rond-point, voie le long
	    de la route, îlots plantés, lampadaires, totem de l'enseigne près du
	    rond-point, trottoir et bornes devant l'entrée.
	Aucune vraie lumière ici ; aucune grande surface en Neon ; budget ~210
	pièces (v9.7 : ~200).

	Contrat (client MarketInterior) : Model "Supermarket" dans
	DopamineTown.Market, attributs
	  MarketCF     CFrame : pied de la façade (milieu), LookVector vers la route
	  InteriorCF   CFrame : centre du SOL intérieur (dessus), mêmes axes
	  InteriorSize Vector3 (largeur, hauteur sous toit, profondeur)
	  DoorCF       CFrame : seuil du sas (sol), LookVector vers le parking
	  LotCF        CFrame : centre du parking (dessus de l'enrobé)
	  LotSize      Vector3 (largeur, 0, profondeur)
	  StallsA / StallsB  nombre de places par rangée
	  Version      98
	Vantaux vitrés "DoorPanel" (attribut SlideX), jamais bloquants.
	Écrans "LeaderScreen" (attribut Board = "Dopamine" | "Rebirths" ; face
	avant = -Z de la pièce, vers le parking).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)

local TownMarket = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part

TownMarket.NAME = "MegaDopa" -- (clé anglaise ; en français : "MégaDopa")
TownMarket.VERSION = 98

local W = WorldLayout.MARKET_W -- 104
local D = WorldLayout.MARKET_D -- 68
local T = 1 -- épaisseur des murs
local ROOF = 18 -- dessous du toit
local TOP = 21 -- haut des murs (acrotère)
local FLOOR = 0.2 -- dessus du sol intérieur
local ATRIUM = 17 -- demi-largeur de l'atrium vitré
local ATRIUM_H = 17 -- haut du mur-rideau
local PIER = 4 -- largeur des piliers de la tour
local DOOR_W = 14 -- baie du sas
local DOOR_H = 10
local LOT_Y = -0.5 -- dessus de l'enrobé (niveau de la route)
local LOT_Z0, LOT_Z1 = -52, -10 -- parking (z local)
TownMarket.ROOF = ROOF
TownMarket.FLOOR = FLOOR
TownMarket.LOT_Z0 = LOT_Z0
TownMarket.LOT_Z1 = LOT_Z1
TownMarket.ATRIUM = ATRIUM

TownMarket.BRAND = Color3.fromRGB(236, 72, 140)
TownMarket.BRAND2 = Color3.fromRGB(120, 90, 200)
local BRAND = TownMarket.BRAND
local BRAND2 = TownMarket.BRAND2
local FACADE = Color3.fromRGB(236, 228, 214)
local FACADE2 = Color3.fromRGB(214, 206, 194)
local GLASS = Color3.fromRGB(150, 196, 226)
local FRAME = Color3.fromRGB(176, 180, 190)
local YELLOW = Color3.fromRGB(255, 208, 72)
local SCREEN = Color3.fromRGB(24, 20, 40)

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
	-- façade : murs pleins de part et d'autre de la tour (l'atrium est vitré)
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx < 0 and -hw or ATRIUM + PIER, sx < 0 and -ATRIUM - PIER or hw
		box(model, "FrontWall", cf, a, b, FLOOR, TOP, 0, T, FACADE, M.Concrete, "solid")
	end
	box(model, "BackWall", cf, -hw, hw, FLOOR, TOP, D - T, D, FACADE2, M.Concrete, "solid")
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "SideWall", cf, sx < 0 and -hw or hw - T, sx < 0 and -hw + T or hw, FLOOR, TOP, T, D - T, FACADE2, M.Concrete, "solid")
	end
	-- toit : bandes pleines + 3 lanterneaux sur toute la largeur utile
	local roofColor = Color3.fromRGB(196, 196, 204)
	local sky = { math.floor(D * 0.25), math.floor(D * 0.5), math.floor(D * 0.75) }
	local skyHalf = hw - 10
	local z = T
	for _, zc in ipairs(sky) do
		box(model, "Roof", cf, -hw + T, hw - T, ROOF, ROOF + 1, z, zc - 1.5, roofColor, M.Concrete, "solid")
		for _, sx in ipairs({ -1, 1 }) do
			box(model, "Roof", cf, sx < 0 and -hw + T or skyHalf, sx < 0 and -skyHalf or hw - T, ROOF, ROOF + 1, zc - 1.5, zc + 1.5, roofColor, M.Concrete, "solid")
		end
		local sk = glassBox(model, "Skylight", cf, -skyHalf, skyHalf, ROOF + 0.2, ROOF + 0.8, zc - 1.5, zc + 1.5, 0.35, "prop")
		sk.CastShadow = false
		box(model, "SkylightCurb", cf, -skyHalf - 0.2, skyHalf + 0.2, ROOF + 1, ROOF + 1.5, zc - 1.7, zc - 1.5, FRAME, M.Metal, "deco")
		box(model, "SkylightCurb", cf, -skyHalf - 0.2, skyHalf + 0.2, ROOF + 1, ROOF + 1.5, zc + 1.5, zc + 1.7, FRAME, M.Metal, "deco")
		z = zc + 1.5
	end
	box(model, "Roof", cf, -hw + T, hw - T, ROOF, ROOF + 1, z, D - T, roofColor, M.Concrete, "solid")
	-- couvertines (haut des murs ; la façade s'arrête aux piliers de la tour)
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx < 0 and -hw - 0.2 or ATRIUM + PIER + 0.2, sx < 0 and -ATRIUM - PIER - 0.2 or hw + 0.2
		box(model, "Coping", cf, a, b, TOP, TOP + 0.35, -0.2, T + 0.1, C.White, M.Concrete, "deco")
	end
	box(model, "Coping", cf, -hw - 0.2, hw + 0.2, TOP, TOP + 0.35, D - T - 0.1, D + 0.2, C.White, M.Concrete, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "Coping", cf, sx < 0 and -hw - 0.2 or hw - T - 0.1, sx < 0 and -hw + T + 0.1 or hw + 0.2, TOP, TOP + 0.35, T + 0.1, D - T - 0.1, C.White, M.Concrete, "deco")
	end
	-- groupes de ventilation sur le toit (entre les lanterneaux)
	for i, spot in ipairs({ { -30, D * 0.38 }, { 8, D * 0.62 }, { 32, D * 0.38 }, { -12, D * 0.88 } }) do
		local x, zc = spot[1], spot[2]
		box(model, "HVAC", cf, x - 3, x + 3, ROOF + 1, ROOF + 3.6, zc - 2.2, zc + 2.2, Color3.fromRGB(206, 208, 214), M.DiamondPlate, "deco")
		local fan = part(model, "HVACFan", Vector3.new(0.3, 2.8, 2.8), cf * CFrame.new(x + (i % 2 == 0 and 1.3 or -1.3), ROOF + 3.75, zc) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 124, 136), M.Metal, "deco")
		;(fan :: Part).Shape = Enum.PartType.Cylinder
	end
end

-- Tour d'entrée + atrium vitré + sas + marquise
local function entrance(model: Model, cf: CFrame)
	local ax = ATRIUM
	-- piliers de la tour (pleins : ils portent l'enseigne) + haut de la tour
	for _, sx in ipairs({ -1, 1 }) do
		box(model, "TowerPier", cf, sx < 0 and -ax - PIER or ax, sx < 0 and -ax or ax + PIER, 0, 27, -1.6, T, BRAND, M.Concrete, "solid")
	end
	box(model, "TowerTop", cf, -ax, ax, ATRIUM_H, 27, -1.6, T, BRAND, M.Concrete, "solid")
	box(model, "TowerCap", cf, -ax - PIER - 0.4, ax + PIER + 0.4, 27, 27.7, -2, T + 0.4, C.White, M.Concrete, "deco")
	sign(model, "BigSign", cf, -15, 15, 19.6, 26.2, -1.75, -1.6, C.White, "🧠 MegaDopa", BRAND, 18, 900)
	local tag = sign(model, "Tagline", cf, -13, 13, 17.4, 19.3, -1.75, -1.6, BRAND2, "Everything for your home!", C.White, 30, 300)
	tag.Color = BRAND2
	-- mur-rideau de l'atrium (deux pans de part et d'autre du sas + imposte)
	local dx = DOOR_W / 2
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx < 0 and -ax or dx + 0.3, sx < 0 and -dx - 0.3 or ax
		local g = glassBox(model, "Atrium", cf, a, b, FLOOR, ATRIUM_H, 0.3, 0.6, 0.45, "solid")
		g.Color = Color3.fromRGB(120, 160, 196)
		-- meneaux (4 par pan) + traverse
		for i = 0, 3 do
			local x = a + (i + 0.5) * (b - a) / 4
			box(model, "Mullion", cf, x - 0.15, x + 0.15, FLOOR, ATRIUM_H, 0.05, 0.3, FRAME, M.Metal, "deco")
		end
		box(model, "Transom", cf, a, b, 10.2, 10.6, 0.02, 0.3, FRAME, M.Metal, "deco")
	end
	glassBox(model, "AtriumHead", cf, -dx - 0.3, dx + 0.3, DOOR_H + 0.4, ATRIUM_H, 0.3, 0.6, 0.45, "prop").Color = Color3.fromRGB(120, 160, 196)
	box(model, "DoorHeader", cf, -dx - 0.3, dx + 0.3, DOOR_H, DOOR_H + 0.4, 0, T, FRAME, M.Metal, "solid")
	-- sas vitré (auvent au-dessus, portes coulissantes devant)
	local vz = -6
	for _, sx in ipairs({ -1, 1 }) do
		glassBox(model, "VestibuleSide", cf, sx < 0 and -dx or dx - 0.3, sx < 0 and -dx + 0.3 or dx, FLOOR, DOOR_H + 0.2, vz, 0, 0.4, "prop")
		-- vitres fixes de part et d'autre des portes
		glassBox(model, "VestibuleLite", cf, sx < 0 and -dx + 0.3 or 3.9, sx < 0 and -3.9 or dx - 0.3, FLOOR, 8.2, vz, vz + 0.3, 0.4, "prop")
		box(model, "VestibulePost", cf, sx < 0 and -3.9 or 3.7, sx < 0 and -3.7 or 3.9, FLOOR, 8.4, vz - 0.1, vz + 0.4, FRAME, M.Metal, "deco")
	end
	box(model, "VestibuleFloor", cf, -dx, dx, -1.3, FLOOR, vz, 0, Color3.fromRGB(206, 200, 196), M.Concrete, "solid")
	box(model, "VestibuleHeader", cf, -dx + 0.3, dx - 0.3, 8.2, DOOR_H + 0.2, vz - 0.05, vz + 0.35, FRAME, M.Metal, "deco")
	box(model, "VestibuleRoof", cf, -dx, dx, DOOR_H + 0.2, DOOR_H + 0.5, vz, 0, C.White, M.Concrete, "deco")
	sign(model, "Welcome", cf, -4.5, 4.5, 8.5, 9.9, vz - 0.13, vz - 0.05, C.White, "Welcome! Open every day", BRAND, 40, 140)
	-- marquise sur deux colonnes (au-dessus du trottoir)
	box(model, "Canopy", cf, -12.5, 12.5, 11.2, 11.9, -11, -1.6, C.White, M.Concrete, "decoS")
	box(model, "CanopyEdge", cf, -12.6, 12.6, 11.2, 11.9, -11.15, -11, BRAND, M.SmoothPlastic, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		TownKit.Column(model, "CanopyColumn", (cf * CFrame.new(sx * 11.4, 0, -10)).Position, 11.2, 0.8, FRAME, M.Metal, "prop")
	end
	-- deux vantaux vitrés coulissants (le client les ouvre ; jamais bloquants)
	for _, sx in ipairs({ -1, 1 }) do
		local panel = box(model, "DoorPanel", cf, sx < 0 and -3.7 or 0.02, sx < 0 and -0.02 or 3.7, FLOOR, 8.2, vz + 0.35, vz + 0.5, GLASS, M.Glass, "deco")
		panel.Transparency = 0.4
		panel.Reflectance = 0.15
		panel:SetAttribute("SlideX", sx * 3.2)
	end
	-- bornes devant le sas (pas de voiture dans l'entrée)
	for _, x in ipairs({ -8.5, -4.5, 4.5, 8.5 }) do
		TownKit.Column(model, "Bollard", (cf * CFrame.new(x, 0, -8.6)).Position, 2.6, 0.7, YELLOW, M.Metal, "prop")
	end
end

-- Façade : bandeau, ÉCRANS DE CLASSEMENT, vitrines d'angle, enseignes
local function facade(model: Model, cf: CFrame)
	local hw = W / 2
	local x0 = ATRIUM + PIER
	-- bandeau aux couleurs de l'enseigne (sur la façade, hors tour)
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx < 0 and -hw - 0.1 or x0, sx < 0 and -x0 or hw + 0.1
		box(model, "BrandBand", cf, a, b, 17.6, TOP - 0.05, -0.35, 0, BRAND2, M.SmoothPlastic, "deco")
		box(model, "BrandStripe", cf, a, b, 16.9, 17.6, -0.35, 0, YELLOW, M.SmoothPlastic, "deco")
	end
	-- deux grands écrans de classement (contenu : client MarketInterior)
	for _, spec in ipairs({ { 1, "Dopamine" }, { -1, "Rebirths" } }) do
		local sx = spec[1] :: number
		local cx = sx * (x0 + 9.5)
		box(model, "ScreenBezel", cf, cx - 8, cx + 8, 5.4, 15.8, -0.7, 0, Color3.fromRGB(40, 38, 52), M.Metal, "deco")
		local screen = box(model, "LeaderScreen", cf, cx - 7.5, cx + 7.5, 5.9, 15.3, -0.78, -0.7, SCREEN, M.SmoothPlastic, "deco")
		screen:SetAttribute("Board", spec[2])
		box(model, "ScreenFoot", cf, cx - 5, cx + 5, 4.9, 5.4, -1.1, 0, FRAME, M.Metal, "deco")
		box(model, "ScreenCap", cf, cx - 8.3, cx + 8.3, 15.8, 16.3, -1.1, 0, BRAND, M.SmoothPlastic, "deco")
	end
	-- vitrines d'angle (menuiseries, allège)
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx < 0 and -hw + 2.5 or x0 + 20, sx < 0 and -x0 - 20 or hw - 2.5
		box(model, "Storefront", cf, a - 0.4, b + 0.4, 0, 1.6, -0.5, 0, FACADE2, M.Concrete, "prop")
		local g = glassBox(model, "ShopWindow", cf, a, b, 1.6, 12.4, -0.26, -0.08, 0.1, "deco")
		g.Color = Color3.fromRGB(96, 124, 150)
		box(model, "WindowHead", cf, a - 0.4, b + 0.4, 12.4, 12.9, -0.5, 0, C.White, M.Concrete, "deco")
		for i = 0, 3 do
			local x = a + i * (b - a) / 3
			box(model, "WindowMullion", cf, x - 0.15, x + 0.15, 1.6, 12.4, -0.42, -0.26, FRAME, M.Metal, "deco")
		end
	end
	-- enseignes de rayons sur la façade (au-dessus des vitrines)
	sign(model, "SubSign", cf, x0 + 20, hw - 2.5, 13.3, 16.3, -0.55, -0.35, C.White, "🥕 Groceries", Color3.fromRGB(64, 150, 90), 26, 300)
	sign(model, "SubSign", cf, -hw + 2.5, -x0 - 20, 13.3, 16.3, -0.55, -0.35, C.White, "💎 Robux Shop & ☕ Café", BRAND2, 26, 300)
	-- trottoir devant le magasin (+ bordure)
	box(model, "Apron", cf, -hw - 1, hw + 1, -1.3, 0, LOT_Z1 + 0.4, 0, C.Walk, M.Pavement, "solid")
	box(model, "Curb", cf, -hw - 1, hw + 1, -1.3, 0, LOT_Z1, LOT_Z1 + 0.4, C.Curb, M.Concrete, "solid")
end

-- Côtés et arrière (jamais de mur nu)
local function sides(model: Model, cf: CFrame)
	local hw = W / 2
	for _, sx in ipairs({ -1, 1 }) do
		-- repère de la face latérale : x le long du mur (profondeur), -Z vers dehors
		local R = cf * CFrame.new(sx * hw, 0, D / 2) * CFrame.Angles(0, sx * -math.pi / 2, 0)
		box(model, "SideBand", R, -D / 2 - 0.1, D / 2 + 0.1, 17.6, TOP - 0.05, -0.35, 0, BRAND2, M.SmoothPlastic, "deco")
		box(model, "SideStripe", R, -D / 2 - 0.1, D / 2 + 0.1, 16.9, 17.6, -0.35, 0, YELLOW, M.SmoothPlastic, "deco")
		for i = 0, 4 do
			local x = -D / 2 + 4 + i * (D - 8) / 4
			box(model, "Pilaster", R, x - 0.8, x + 0.8, -0.6, 16.9, -0.6, 0, FACADE, M.Concrete, "deco")
		end
		-- fenêtres hautes (entre les pilastres ; la 2e laisse la place à la sortie)
		for i = 0, 3 do
			local x = -D / 2 + 4 + (i + 0.5) * (D - 8) / 4
			if i ~= 1 then
				local g = glassBox(model, "HighWindow", R, x - 5, x + 5, 12, 15.4, -0.2, -0.05, 0.15, "deco")
				g.Color = Color3.fromRGB(110, 140, 170)
				box(model, "HighSill", R, x - 5.3, x + 5.3, 11.6, 12, -0.5, 0, C.White, M.Concrete, "deco")
			end
		end
		-- sortie de secours (porte, auvent, marche, panneau vert)
		local ex = -D / 2 + 4 + 1.5 * (D - 8) / 4
		box(model, "ExitFrame", R, ex - 2.1, ex + 2.1, 0, 8.3, -0.18, 0, FRAME, M.Metal, "deco")
		box(model, "ExitDoor", R, ex - 1.7, ex + 1.7, 0.2, 7.9, -0.3, -0.18, Color3.fromRGB(150, 156, 170), M.Metal, "deco")
		box(model, "ExitBar", R, ex - 1.4, ex + 1.4, 3.6, 3.9, -0.42, -0.3, Color3.fromRGB(220, 60, 70), M.Metal, "deco")
		box(model, "ExitCanopy", R, ex - 2.8, ex + 2.8, 8.6, 9, -2.4, 0, FRAME, M.Metal, "deco")
		box(model, "ExitSign", R, ex - 1, ex + 1, 8.4, 8.58, -0.8, -0.3, Color3.fromRGB(60, 180, 100), M.SmoothPlastic, "deco")
		box(model, "ExitStep", R, ex - 2.2, ex + 2.2, -1.3, 0.2, -2.2, 0, C.Walk, M.Concrete, "solid")
		-- descentes d'eau
		for _, x in ipairs({ -D / 2 + 1.2, D / 2 - 1.2 }) do
			TownKit.Column(model, "Downpipe", (R * CFrame.new(x, -0.4, -0.4)).Position, TOP - 0.2, 0.45, Color3.fromRGB(150, 154, 166), M.Metal, "deco")
		end
		-- logo peint (grand chariot) sur le côté
		sign(model, "SideLogo", R, 10, 26, 2, 10.4, -0.12, -0.04, BRAND, "🛒 MegaDopa", C.White, 12, 400)
	end
	-- arrière : quais de livraison
	local B = cf * CFrame.new(0, 0, D) * CFrame.Angles(0, math.pi, 0) -- -Z vers dehors (arrière)
	box(model, "DockPlatform", B, -10, 38, -1.3, 1.4, -4.5, 0, Color3.fromRGB(176, 172, 168), M.Concrete, "solid")
	for i, x in ipairs({ 0, 14, 28 }) do
		box(model, "DockFrame", B, x - 4.6, x + 4.6, 1.4, 11, -0.2, 0, Color3.fromRGB(150, 156, 170), M.Metal, "deco")
		box(model, "DockDoor", B, x - 4.1, x + 4.1, 1.4, 10.6, -0.32, -0.2, Color3.fromRGB(206, 210, 218), M.CorrodedMetal, "deco")
		for _, sx in ipairs({ -1, 1 }) do
			box(model, "Bumper", B, x + sx * 3.4 - 0.4, x + sx * 3.4 + 0.4, 1.6, 3.2, -4.9, -4.5, Color3.fromRGB(40, 40, 46), M.Rubber, "deco")
		end
		sign(model, "DockNumber", B, x - 1, x + 1, 11.4, 12.8, -0.12, -0.04, YELLOW, tostring(i), Color3.fromRGB(40, 40, 46), 30, 150)
	end
	box(model, "DockCanopy", B, -10.5, 38.5, 12.8, 13.3, -5.5, 0, FRAME, M.Metal, "decoS")
	sign(model, "DockSign", B, -34, -18, 10.6, 13.4, -0.12, -0.04, C.White, "🚚 Deliveries", BRAND2, 24, 200)
	box(model, "StaffDoor", B, -30, -26.8, 0.2, 7.6, -0.3, -0.05, Color3.fromRGB(150, 156, 170), M.Metal, "deco")
	box(model, "BackBand", B, -W / 2 - 0.1, W / 2 + 0.1, 17.6, TOP - 0.05, -0.35, 0, BRAND2, M.SmoothPlastic, "deco")
	for _, x in ipairs({ -W / 2 + 1.2, W / 2 - 1.2 }) do
		TownKit.Column(model, "Downpipe", (B * CFrame.new(x, -0.4, -0.4)).Position, TOP - 0.2, 0.45, Color3.fromRGB(150, 154, 166), M.Metal, "deco")
	end
end

----------------------------------------------------------------------
-- Parking (le gros oeuvre ; marquages, voitures, chariots : client)
----------------------------------------------------------------------

local function parking(model: Model, cf: CFrame, geo: TownKit.Geo): (number, number)
	local hw = W / 2 + 1
	local lot = box(model, "Lot", cf, -hw, hw, LOT_Y - 0.7, LOT_Y, LOT_Z0, LOT_Z1, C.AsphaltDark, M.Asphalt, "solid")
	lot.CastShadow = false
	-- allée d'accès depuis le rond-point (même niveau que la route ; un peu
	-- plus basse que l'anneau du rond-point : jamais de faces confondues)
	local roadCF = WorldLayout.GateCFrame(geo.Count)
	local loop = roadCF.Position + Vector3.new(0, 0, 66) -- centre du rond-point (TownEntrance : porte + 50 + 16)
	local rel = cf:PointToObjectSpace(Vector3.new(loop.X, cf.Position.Y, loop.Z))
	local drive = box(model, "Driveway", cf, rel.X - 6.5, rel.X + 6.5, LOT_Y - 0.72, LOT_Y - 0.04, rel.Z + 16, LOT_Z0 + 0.5, C.AsphaltDark, M.Asphalt, "solid")
	drive.CastShadow = false
	-- îlots plantés aux bouts des rangées
	local rows = { { -46, -35.5 }, { -28, -17.5 } }
	for _, sx in ipairs({ -1, 1 }) do
		for _, row in ipairs(rows) do
			local x0, x1 = sx < 0 and -hw + 0.3 or hw - 4.3, sx < 0 and -hw + 4.3 or hw - 0.3
			box(model, "Island", cf, x0, x1, LOT_Y - 0.1, LOT_Y + 0.5, row[1] + 0.5, row[2] - 0.5, C.Curb, M.Concrete, "prop")
			box(model, "IslandGrass", cf, x0 + 0.2, x1 - 0.2, LOT_Y + 0.5, LOT_Y + 0.55, row[1] + 0.7, row[2] - 0.7, C.Lawn, M.Grass, "deco")
		end
		-- lampadaire au bout de l'allée centrale (sur un petit socle)
		local lx, lz = sx * 30, -31.8
		box(model, "LightBase", cf, lx - 0.6, lx + 0.6, LOT_Y, LOT_Y + 1, lz - 0.6, lz + 0.6, C.Curb, M.Concrete, "prop")
		TownKit.Column(model, "LightPole", (cf * CFrame.new(lx, LOT_Y + 1, lz)).Position, 15, 0.5, C.Metal, M.Metal, "prop")
		box(model, "LightArm", cf, lx - 2.6, lx + 2.6, LOT_Y + 15.6, LOT_Y + 16, lz - 0.2, lz + 0.2, C.Metal, M.Metal, "deco")
		for _, dx in ipairs({ -2.4, 2.4 }) do
			local head = box(model, "LightHead", cf, lx + dx - 0.7, lx + dx + 0.7, LOT_Y + 15.2, LOT_Y + 15.6, lz - 0.6, lz + 0.6, C.Glow, M.SmoothPlastic, "deco")
			TownKit.Glow(head)
		end
	end
	-- totem de l'enseigne près du rond-point (vu en arrivant en ville)
	local totem = cf * CFrame.new(rel.X + 13, LOT_Y, LOT_Z0 - 3) * CFrame.Angles(0, math.rad(-45), 0)
	box(model, "PylonBase", totem, -3.4, 3.4, -1.2, 1.4, -1.4, 1.4, C.StoneDark, M.Granite, "prop")
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
	-- arbres des îlots du fond (pas trop près des voitures)
	for _, sx in ipairs({ -1, 1 }) do
		local row = rows[2]
		local p = (cf * CFrame.new(sx * (hw - 2.3), LOT_Y + 0.5, (row[1] + row[2]) / 2)).Position
		pcall(TownKit.Tree, model, p, 12, math.floor(p.X + p.Z), nil)
	end
	local stalls = math.floor((W - 12) / 6)
	return stalls, stalls
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TownMarket.Build(folder: Instance, geo: TownKit.Geo): Model
	local cf = WorldLayout.MarketCFrame(geo.Count)
	local model = TownKit.Model(folder, "Supermarket")
	building(model, cf)
	entrance(model, cf)
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
	model:SetAttribute("Version", TownMarket.VERSION)
	-- (emprise réservée : aucun arbre ni objet semé dessus)
	geo.Reserve((cf * CFrame.new(0, 0, (LOT_Z0 + D) / 2)).Position, math.max(W, D - LOT_Z0) / 2 + 10)
	return model
end

-- Zone du magasin + parking (repère MarketCF) : pour écarter les arbres
-- semés dessus par d'autres modules (bois autour de la ville...)
function TownMarket.InZone(cf: CFrame, p: Vector3, margin: number): boolean
	local rel = cf:PointToObjectSpace(p)
	return math.abs(rel.X) < W / 2 + 2 + margin and rel.Z > LOT_Z0 - 6 - margin and rel.Z < D + 6 + margin
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
