--[[
	TownBuildings (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownBuildings

	🏪 Les bâtiments du centre-ville (décor, v9.4) :
	  - BOUTIQUES autour de la place et le long de l'avenue : façade en
	    enduit / brique, rez-de-chaussée vitré (vitrines éclairées, porte),
	    store rayé, enseigne (SurfaceGui), étages avec fenêtres encadrées,
	    appuis, volets, jardinières, corniches, toit (tuiles, ardoises ou
	    toit-terrasse), cheminée, gouttière ; un détail par métier (terrasse
	    de café, cornet géant, néons de l'arcade, bretzel de la boulangerie,
	    seaux de fleurs, gobelet de bubble tea, marquise du cinéma...) ;
	  - la MAIRIE au fond de la place : portique à colonnes, fronton,
	    tour de l'horloge, et le GRAND ÉCRAN des meilleurs joueurs du serveur
	    (SurfaceGui mis à jour par TownMap) ;
	  - silhouette lointaine d'une ville (au-delà des collines) ;
	  - (v9.7, BUILDINGS97) IMMEUBLES DE RUE en 5 styles (Haussmann, briques,
	    pastel à pignon, moderne, colombages) : coque ici, détail en flux
	    côté client (Client/World/TownFacades) ; boutiques de décor et mairie
	    finies sur toutes leurs faces (arrière, côtés), pancarte "Fermé".
	v9.6 : ces boutiques restent du DÉCOR (portes fermées) ; celles où l'on
	entre sont dans TownShops (qui réutilise Window / GableRoof d'ici).
	Plus de néon sur les grandes surfaces (marquise, bandeaux, portail de la
	mairie, cœur de la flèche) : SmoothPlastic / verre ; lumière de l'écran
	adoucie (portée 18, luminosité 0,8).
	Repère d'un bâtiment : `cf` = milieu du pied de la façade, LookVector
	vers la rue ; le volume est derrière (+Z local).
]]

local TownKit = require(script.Parent.TownKit)

local TownBuildings = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part
local hash = TownKit.Hash

export type ShopSpec = {
	Kind: string,
	Sign: string,
	W: number,
	D: number,
	Floors: number,
	Wall: Color3,
	Material: Enum.Material?,
	Trim: Color3?,
	Awning: { Color3 },
	Roof: string, -- "Gable" | "Flat"
	RoofColor: Color3?,
	SignColor: Color3?,
	Shutters: Color3?,
}

-- Les boutiques (ordre de placement autour de la place puis sur l'avenue)
TownBuildings.SHOPS = {
	{ Kind = "Cafe", Sign = "☕ Café Mochi", W = 28, D = 20, Floors = 3, Wall = Color3.fromRGB(255, 214, 222), Material = M.Plaster, Awning = { Color3.fromRGB(236, 90, 130), C.White }, Roof = "Gable", RoofColor = Color3.fromRGB(150, 84, 90), Shutters = Color3.fromRGB(120, 190, 170) },
	{ Kind = "IceCream", Sign = "🍦 Gelato Cloud", W = 24, D = 18, Floors = 2, Wall = Color3.fromRGB(196, 240, 222), Material = M.Plaster, Awning = { Color3.fromRGB(120, 210, 190), C.White }, Roof = "Flat", SignColor = Color3.fromRGB(236, 90, 150) },
	{ Kind = "Arcade", Sign = "🕹️ Pixel Arcade", W = 30, D = 22, Floors = 2, Wall = Color3.fromRGB(96, 80, 150), Material = M.Brick, Awning = { Color3.fromRGB(80, 60, 130), Color3.fromRGB(255, 90, 200) }, Roof = "Flat", SignColor = Color3.fromRGB(90, 240, 255) },
	{ Kind = "Bakery", Sign = "🥐 Sweet Bakery", W = 26, D = 20, Floors = 3, Wall = Color3.fromRGB(255, 236, 196), Material = M.Plaster, Awning = { Color3.fromRGB(214, 150, 90), C.Cream }, Roof = "Gable", RoofColor = Color3.fromRGB(120, 110, 130), Shutters = Color3.fromRGB(150, 110, 200) },
	{ Kind = "Flowers", Sign = "🌷 Petal Shop", W = 22, D = 18, Floors = 2, Wall = Color3.fromRGB(226, 214, 255), Material = M.Plaster, Awning = { Color3.fromRGB(150, 200, 110), C.White }, Roof = "Gable", RoofColor = Color3.fromRGB(96, 110, 150), Shutters = Color3.fromRGB(236, 130, 170) },
	{ Kind = "Boba", Sign = "🧋 Boba Bubble", W = 24, D = 18, Floors = 2, Wall = Color3.fromRGB(255, 226, 180), Material = M.Brick, Awning = { Color3.fromRGB(170, 120, 90), C.Cream }, Roof = "Flat", SignColor = Color3.fromRGB(150, 90, 60) },
	{ Kind = "Books", Sign = "📚 Story Nook", W = 26, D = 20, Floors = 3, Wall = Color3.fromRGB(190, 222, 255), Material = M.Plaster, Awning = { Color3.fromRGB(80, 120, 200), C.White }, Roof = "Gable", RoofColor = Color3.fromRGB(90, 96, 120), Shutters = Color3.fromRGB(255, 255, 255) },
	{ Kind = "Toys", Sign = "🧸 Plushie Palace", W = 28, D = 20, Floors = 2, Wall = Color3.fromRGB(255, 196, 170), Material = M.Plaster, Awning = { Color3.fromRGB(255, 150, 90), C.White }, Roof = "Gable", RoofColor = Color3.fromRGB(170, 90, 100) },
	{ Kind = "Cinema", Sign = "🎬 Dream Cinema", W = 32, D = 24, Floors = 2, Wall = Color3.fromRGB(236, 96, 110), Material = M.Brick, Awning = { Color3.fromRGB(60, 50, 70), Color3.fromRGB(255, 214, 96) }, Roof = "Flat", SignColor = Color3.fromRGB(255, 214, 96) },
	{ Kind = "Pizza", Sign = "🍕 Pizza Luna", W = 24, D = 18, Floors = 3, Wall = Color3.fromRGB(255, 244, 214), Material = M.Plaster, Awning = { Color3.fromRGB(220, 70, 70), C.White }, Roof = "Gable", RoofColor = Color3.fromRGB(176, 96, 70), Shutters = Color3.fromRGB(90, 150, 100) },
	{ Kind = "Music", Sign = "🎧 Vinyl Vibes", W = 24, D = 18, Floors = 2, Wall = Color3.fromRGB(170, 214, 200), Material = M.Brick, Awning = { Color3.fromRGB(60, 60, 80), Color3.fromRGB(120, 230, 200) }, Roof = "Flat", SignColor = Color3.fromRGB(60, 60, 80) },
	{ Kind = "Candy", Sign = "🍭 Candy Pop", W = 24, D = 18, Floors = 2, Wall = Color3.fromRGB(255, 186, 222), Material = M.Plaster, Awning = { Color3.fromRGB(255, 110, 170), Color3.fromRGB(255, 240, 120) }, Roof = "Gable", RoofColor = Color3.fromRGB(130, 100, 170), Shutters = C.White },
	{ Kind = "Gym", Sign = "💪 Brain Gym", W = 28, D = 20, Floors = 2, Wall = Color3.fromRGB(210, 214, 226), Material = M.Concrete, Awning = { Color3.fromRGB(70, 80, 110), Color3.fromRGB(140, 200, 255) }, Roof = "Flat", SignColor = Color3.fromRGB(70, 80, 110) },
} :: { ShopSpec }

local GROUND_H = 10 -- rez-de-chaussée
local FLOOR_H = 8.5 -- étages

-- Fenêtre encadrée (cadre, vitre, appui ; volets / jardinière en option)
local function window(parent: Instance, cf: CFrame, w: number, h: number, trim: Color3, shutters: Color3?, flowers: boolean, seed: number)
	part(parent, "WinFrame", Vector3.new(w + 0.8, h + 0.8, 0.3), cf * CFrame.new(0, 0, -0.1), trim, M.SmoothPlastic, "deco")
	local glass = part(parent, "WinGlass", Vector3.new(w, h, 0.3), cf * CFrame.new(0, 0, -0.16), Color3.fromRGB(150, 196, 226), M.Glass, "deco")
	glass.Reflectance = 0.15
	part(parent, "WinBar", Vector3.new(0.25, h - 0.1, 0.35), cf * CFrame.new(0, 0, -0.18), trim, M.SmoothPlastic, "deco")
	part(parent, "Sill", Vector3.new(w + 1.4, 0.35, 0.8), cf * CFrame.new(0, -h / 2 - 0.5, -0.4), trim, M.Concrete, "deco")
	if shutters then
		for _, sx in ipairs({ -1, 1 }) do
			part(parent, "Shutter", Vector3.new(w / 2, h + 0.4, 0.2), cf * CFrame.new(sx * (w * 0.75 + 0.55), 0, -0.2), shutters, M.WoodPlanks, "deco")
		end
	end
	if flowers then
		part(parent, "FlowerBox", Vector3.new(w + 0.8, 0.8, 0.9), cf * CFrame.new(0, -h / 2 - 1.1, -0.6), C.Wood, M.WoodPlanks, "deco")
		part(parent, "Blooms", Vector3.new(w + 0.4, 0.7, 0.7), cf * CFrame.new(0, -h / 2 - 0.45, -0.6), TownKit.FLOWERS[seed % #TownKit.FLOWERS + 1], M.Grass, "deco")
	end
end

-- Toit à deux pans (faîtage parallèle à la façade), débord de 0,8
local function gableRoof(parent: Instance, cf: CFrame, w: number, d: number, h: number, color: Color3)
	local half = d / 2 + 0.8
	TownKit.Wedge(parent, "Roof", Vector3.new(w + 1.6, h, half), cf * CFrame.new(0, h / 2, d / 2 - half / 2), color, M.ClayRoofTiles, "decoS")
	TownKit.Wedge(parent, "Roof", Vector3.new(w + 1.6, h, half), cf * CFrame.new(0, h / 2, d / 2 + half / 2) * CFrame.Angles(0, math.pi, 0), color, M.ClayRoofTiles, "decoS")
	part(parent, "Ridge", Vector3.new(w + 1.8, 0.5, 0.8), cf * CFrame.new(0, h + 0.1, d / 2), color:Lerp(Color3.new(0, 0, 0), 0.25), M.Slate, "deco")
	-- (v9.7) plus de coins "pignon" : ils étaient ENFERMÉS dans le toit
	-- (invisibles) et leurs faces se confondaient avec celles du toit
end

-- (v9.6) partagés avec TownShops (boutiques où l'on entre)
TownBuildings.Window = window
TownBuildings.GableRoof = gableRoof
TownBuildings.GROUND_H = GROUND_H
TownBuildings.FLOOR_H = FLOOR_H

-- Détail propre à chaque métier (devant / sur la boutique)
local function shopExtras(parent: Instance, cf: CFrame, spec: ShopSpec, height: number)
	local kind = spec.Kind
	local w = spec.W
	if kind == "Cafe" or kind == "Pizza" then
		-- terrasse : tables rondes + parasols
		for i, x in ipairs({ -w * 0.3, w * 0.3 }) do
			local base = (cf * CFrame.new(x, 0, -7)).Position
			TownKit.Column(parent, "TableLeg", base, 2.6, 0.3, C.Metal, M.Metal, "prop")
			TownKit.Disc(parent, "TableTop", base + Vector3.new(0, 2.8, 0), 1.5, 0.2, C.White, M.Marble, "deco")
			TownKit.Column(parent, "UmbrellaPole", base + Vector3.new(0, 2.8, 0), 4.6, 0.2, C.White, M.Metal, "deco")
			local canopy = TownKit.Disc(parent, "Umbrella", base + Vector3.new(0, 7.3, 0), 3.8, 0.5, spec.Awning[1], M.Fabric, "deco")
			canopy.CastShadow = true
			TownKit.Disc(parent, "UmbrellaTop", base + Vector3.new(0, 7.8, 0), 2.2, 0.5, i == 1 and C.White or spec.Awning[1], M.Fabric, "deco")
			for _, cx in ipairs({ -2.2, 2.2 }) do
				part(parent, "Chair", Vector3.new(1.3, 0.3, 1.3), CFrame.new(base + Vector3.new(cx, 1.6, 0)), C.Metal, M.Metal, "prop")
				part(parent, "ChairBack", Vector3.new(0.2, 1.6, 1.3), CFrame.new(base + Vector3.new(cx + (cx > 0 and 0.6 or -0.6), 2.5, 0)), C.Metal, M.Metal, "deco")
			end
		end
	elseif kind == "IceCream" then
		local top = cf * CFrame.new(0, height + 0.6, 2)
		TownKit.Wedge(parent, "Cone", Vector3.new(1, 6, 2.2), top * CFrame.new(0, 3, 0) * CFrame.Angles(math.pi, 0, 0), Color3.fromRGB(226, 170, 100), M.WoodPlanks, "deco")
		TownKit.Column(parent, "ConeTop", (top * CFrame.new(0, 5.6, 0)).Position, 0.6, 3.6, Color3.fromRGB(226, 170, 100), M.WoodPlanks, "deco")
		TownKit.Ball(parent, "Scoop", (top * CFrame.new(0, 7.4, 0)).Position, 4.4, Color3.fromRGB(255, 170, 200), M.SmoothPlastic, "decoS")
		TownKit.Ball(parent, "Scoop2", (top * CFrame.new(0, 10, 0)).Position, 3.4, Color3.fromRGB(170, 236, 200), M.SmoothPlastic, "decoS")
		TownKit.Ball(parent, "Cherry", (top * CFrame.new(0, 12.1, 0)).Position, 1.1, Color3.fromRGB(230, 40, 70), M.SmoothPlastic, "deco")
	elseif kind == "Arcade" or kind == "Cinema" then
		-- cadre de néons autour de l'enseigne + marquise à ampoules
		local signY = GROUND_H + 1.6
		local neon = spec.SignColor or C.Pink
		part(parent, "NeonTop", Vector3.new(w * 0.78, 0.3, 0.3), cf * CFrame.new(0, signY + 1.6, -0.9), neon, M.SmoothPlastic, "deco")
		part(parent, "NeonBottom", Vector3.new(w * 0.78, 0.3, 0.3), cf * CFrame.new(0, signY - 1.6, -0.9), neon, M.SmoothPlastic, "deco")
		if kind == "Cinema" then
			part(parent, "Marquee", Vector3.new(w * 0.6, 1.2, 5), cf * CFrame.new(0, GROUND_H - 1.2, -3), Color3.fromRGB(60, 50, 70), M.Metal, "deco")
			part(parent, "MarqueeLights", Vector3.new(w * 0.6 + 0.2, 0.3, 5.2), cf * CFrame.new(0, GROUND_H - 1.9, -3), Color3.fromRGB(255, 226, 150), M.SmoothPlastic, "deco")
		else
			part(parent, "NeonStripe", Vector3.new(0.3, height - 2, 0.3), cf * CFrame.new(-w / 2 + 0.6, height / 2, -0.3), Color3.fromRGB(90, 240, 255), M.SmoothPlastic, "deco")
			part(parent, "NeonStripe", Vector3.new(0.3, height - 2, 0.3), cf * CFrame.new(w / 2 - 0.6, height / 2, -0.3), Color3.fromRGB(255, 90, 200), M.SmoothPlastic, "deco")
		end
	elseif kind == "Bakery" then
		-- enseigne suspendue (potence + médaillon)
		local anchor = cf * CFrame.new(w / 2 - 2, GROUND_H + 3.2, 0)
		part(parent, "Bracket", Vector3.new(0.25, 0.25, 3.4), anchor * CFrame.new(0, 0, -1.7), C.Metal, M.Metal, "deco")
		local medal = part(parent, "Medallion", Vector3.new(0.3, 2.6, 2.6), anchor * CFrame.new(0, -1.6, -2.6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(214, 160, 90), M.Wood, "deco")
		;(medal :: Part).Shape = Enum.PartType.Cylinder
		-- baguettes dans un panier devant la vitrine
		local basket = (cf * CFrame.new(-w * 0.28, 0, -1.6)).Position
		part(parent, "Basket", Vector3.new(3, 1.4, 1.4), CFrame.new(basket + Vector3.new(0, 0.7, 0)), C.WoodLight, M.Fabric, "prop")
		for i = -1, 1 do
			part(parent, "Baguette", Vector3.new(0.5, 3.4, 0.5), CFrame.new(basket + Vector3.new(i * 0.8, 2, 0)) * CFrame.Angles(0, 0, math.rad(i * 10)), Color3.fromRGB(226, 170, 100), M.SmoothPlastic, "deco")
		end
	elseif kind == "Flowers" then
		for i = -2, 2 do
			local base = (cf * CFrame.new(i * 2.2, 0, -1.8)).Position
			TownKit.Column(parent, "Bucket", base, 1.3, 1.4, C.MetalLight, M.Metal, "prop")
			TownKit.Ball(parent, "Bouquet", base + Vector3.new(0, 2, 0), 1.8, TownKit.FLOWERS[(i + 3) % #TownKit.FLOWERS + 1], M.SmoothPlastic, "deco")
		end
	elseif kind == "Boba" then
		local top = (cf * CFrame.new(w * 0.25, height + 0.6, 3)).Position
		TownKit.Column(parent, "Cup", top, 7, 4.2, Color3.fromRGB(255, 236, 214), M.Glass, "deco").Transparency = 0.15
		TownKit.Column(parent, "Tea", top + Vector3.new(0, 0.2, 0), 5, 3.9, Color3.fromRGB(200, 150, 110), M.SmoothPlastic, "deco")
		TownKit.Column(parent, "Lid", top + Vector3.new(0, 7, 0), 0.6, 4.4, C.White, M.SmoothPlastic, "deco")
		TownKit.Column(parent, "Straw", top + Vector3.new(0.6, 6, 0), 4.5, 0.6, Color3.fromRGB(255, 120, 170), M.SmoothPlastic, "deco")
		for i = 0, 3 do
			TownKit.Ball(parent, "Pearl", top + Vector3.new(math.cos(i * 1.6) * 1.1, 0.9, math.sin(i * 1.6) * 1.1), 1.1, Color3.fromRGB(60, 40, 40), M.SmoothPlastic, "deco")
		end
	elseif kind == "Candy" then
		local base = (cf * CFrame.new(-w / 2 + 1.5, 0, -1.8)).Position
		TownKit.Column(parent, "LollipopStick", base, 6, 0.4, C.White, M.SmoothPlastic, "prop")
		local lolly = part(parent, "Lollipop", Vector3.new(0.6, 3.4, 3.4), CFrame.new(base + Vector3.new(0, 7.4, 0)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 120, 180), M.SmoothPlastic, "deco")
		;(lolly :: Part).Shape = Enum.PartType.Cylinder
		local swirl = part(parent, "Swirl", Vector3.new(0.7, 1.8, 1.8), CFrame.new(base + Vector3.new(0, 7.4, 0)) * CFrame.Angles(0, math.rad(90), 0), C.White, M.SmoothPlastic, "deco")
		;(swirl :: Part).Shape = Enum.PartType.Cylinder
	end
end

-- Une boutique complète (≈ 40 à 55 pièces)
function TownBuildings.Shop(parent: Instance, cf: CFrame, spec: ShopSpec, seed: number): Model
	local model = TownKit.Model(parent, "Shop_" .. spec.Kind)
	local w, d = spec.W, spec.D
	local height = GROUND_H + (spec.Floors - 1) * FLOOR_H
	local trim = spec.Trim or C.White
	local mat = spec.Material or M.Plaster
	-- volume principal + socle
	part(model, "Body", Vector3.new(w, height, d), cf * CFrame.new(0, height / 2, d / 2), spec.Wall, mat, "solid")
	part(model, "Plinth", Vector3.new(w + 0.4, 1.2, d + 0.4), cf * CFrame.new(0, 0.6, d / 2), C.StoneDark, M.Granite, "prop")
	-- rez-de-chaussée : devanture (cadre sombre, vitrines éclairées, porte)
	local frameColor = spec.Awning[1]:Lerp(Color3.new(0, 0, 0), 0.35)
	part(model, "Shopfront", Vector3.new(w - 1.6, GROUND_H - 2.4, 0.4), cf * CFrame.new(0, 1.2 + (GROUND_H - 2.4) / 2, -0.15), frameColor, M.Wood, "deco")
	local doorW = 3.4
	for _, sx in ipairs({ -1, 1 }) do
		local ww = (w - 1.6 - doorW) / 2 - 1.2
		local x = sx * (doorW / 2 + 0.6 + ww / 2)
		part(model, "Interior", Vector3.new(ww, GROUND_H - 4.2, 0.2), cf * CFrame.new(x, 1.2 + (GROUND_H - 2.4) / 2 + 0.1, -0.38), Color3.fromRGB(255, 222, 178), M.SmoothPlastic, "deco")
		local glass = part(model, "ShopWindow", Vector3.new(ww, GROUND_H - 4.2, 0.2), cf * CFrame.new(x, 1.2 + (GROUND_H - 2.4) / 2 + 0.1, -0.5), Color3.fromRGB(190, 226, 246), M.Glass, "deco")
		glass.Transparency = 0.45
		glass.Reflectance = 0.2
	end
	part(model, "Door", Vector3.new(doorW, 7, 0.3), cf * CFrame.new(0, 1.2 + 3.5, -0.42), spec.Awning[1], M.Wood, "deco")
	part(model, "DoorGlass", Vector3.new(doorW - 1.2, 3.6, 0.3), cf * CFrame.new(0, 1.2 + 4.6, -0.5), Color3.fromRGB(190, 226, 246), M.Glass, "deco")
	part(model, "Knob", Vector3.new(0.35, 0.35, 0.35), cf * CFrame.new(doorW / 2 - 0.5, 1.2 + 3.2, -0.65), C.Yellow, M.Metal, "deco")
	part(model, "Step", Vector3.new(doorW + 1.2, 0.4, 1.2), cf * CFrame.new(0, 0.2, -0.6), C.Stone, M.Concrete, "prop")
	-- store rayé (lames inclinées) + lambrequin
	local stripes = math.max(4, math.floor((w - 2) / 2.6))
	local sw = (w - 2) / stripes
	local tilt = CFrame.Angles(math.rad(22), 0, 0)
	for i = 1, stripes do
		local x = -(w - 2) / 2 + (i - 0.5) * sw
		part(model, "Awning", Vector3.new(sw, 0.2, 3.6), cf * CFrame.new(x, GROUND_H - 1.1, -1.7) * tilt, spec.Awning[i % 2 + 1], M.Fabric, i == 1 and "decoS" or "deco")
	end
	part(model, "Valance", Vector3.new(w - 2, 0.7, 0.15), cf * CFrame.new(0, GROUND_H - 2.1, -3.4), spec.Awning[1], M.Fabric, "deco")
	-- enseigne (texte traduisible côté client)
	local signColor = spec.SignColor or C.HotPink
	local board = part(model, "SignBoard", Vector3.new(w * 0.72, 2.6, 0.4), cf * CFrame.new(0, GROUND_H + 1.6, -0.3), C.Cream, M.Wood, "deco")
	local _, body = TownKit.Surface(board, Enum.NormalId.Front, 30, nil, 360, 0.5)
	local label = TownKit.Label(body, "Title", spec.Sign, 0.03, 0.08, 0.94, 0.84, signColor, Enum.Font.FredokaOne, false)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.White
	stroke.Thickness = 2
	stroke.Parent = label
	-- étages : bandeaux + fenêtres
	local nWin = math.max(2, math.floor(w / 8.5))
	for f = 1, spec.Floors - 1 do
		local y = GROUND_H + (f - 1) * FLOOR_H
		part(model, "Band", Vector3.new(w + 0.6, 0.6, 0.7), cf * CFrame.new(0, y + 0.3, -0.05), trim, M.Concrete, "deco")
		for i = 1, nWin do
			local x = -w / 2 + (i - 0.5) * w / nWin
			local flowers = (i + f + seed) % 3 == 0
			window(model, cf * CFrame.new(x, y + FLOOR_H / 2 + 0.6, 0), 3.2, 4.4, trim, spec.Shutters, flowers, seed + i)
		end
	end
	-- corniche + toit
	part(model, "Cornice", Vector3.new(w + 1.2, 1, d + 1.2), cf * CFrame.new(0, height + 0.5, d / 2), trim, M.Concrete, "decoS")
	local top = cf * CFrame.new(0, height + 1, 0)
	if spec.Roof == "Gable" then
		gableRoof(model, top, w, d, math.min(9, d * 0.42), spec.RoofColor or Color3.fromRGB(150, 90, 90))
		part(model, "Chimney", Vector3.new(2, 5, 2), top * CFrame.new(w * 0.3, 4.5, d * 0.7), Color3.fromRGB(176, 110, 96), M.Brick, "deco")
		-- lucarne
		part(model, "Dormer", Vector3.new(4, 3.6, 3), top * CFrame.new(-w * 0.2, 2.2, d * 0.22), spec.Wall, mat, "deco")
		part(model, "DormerGlass", Vector3.new(2.2, 2, 0.2), top * CFrame.new(-w * 0.2, 2.2, d * 0.22 - 1.55), Color3.fromRGB(150, 196, 226), M.Glass, "deco")
		part(model, "DormerRoof", Vector3.new(4.8, 0.4, 3.6), top * CFrame.new(-w * 0.2, 4.2, d * 0.22), spec.RoofColor or Color3.fromRGB(150, 90, 90), M.Slate, "deco")
	else
		part(model, "Parapet", Vector3.new(w + 1.2, 1.4, 0.6), top * CFrame.new(0, 0.7, -0.3), trim, M.Concrete, "deco")
		part(model, "RoofUnit", Vector3.new(4, 2.4, 3), top * CFrame.new(w * 0.25, 1.2, d * 0.6), C.MetalLight, M.DiamondPlate, "deco")
		TownKit.Column(model, "WaterTank", (top * CFrame.new(-w * 0.25, 0, d * 0.55)).Position, 4, 3.6, C.WoodLight, M.WoodPlanks, "deco")
	end
	-- gouttière
	part(model, "Drainpipe", Vector3.new(0.4, height, 0.4), cf * CFrame.new(w / 2 - 0.3, height / 2, -0.25), C.MetalLight, M.Metal, "deco")
	shopExtras(model, cf, spec, height)
	return model
end

----------------------------------------------------------------------
-- Mairie + grand écran
----------------------------------------------------------------------

export type Screen = { Rows: { TextLabel }, Title: TextLabel, Footer: TextLabel }

function TownBuildings.TownHall(parent: Instance, cf: CFrame): (Model, Screen)
	local model = TownKit.Model(parent, "TownHall")
	local w, d, h = 64, 26, 34
	local wall = Color3.fromRGB(250, 238, 230)
	local trim = C.White
	local roof = Color3.fromRGB(110, 104, 140)
	part(model, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, d / 2 + 3), wall, M.Limestone, "solid")
	part(model, "Plinth", Vector3.new(w + 0.8, 1.6, d + 0.8), cf * CFrame.new(0, 0.75, d / 2 + 3), C.StoneDark, M.Granite, "prop")
	-- avant-corps central (portique) : marches, colonnes, fronton
	local cw = 28
	for i = 0, 2 do
		part(model, "Steps", Vector3.new(cw + 4 - i * 1.2, 0.6, 3.6 - i * 1.1), cf * CFrame.new(0, 0.3 + i * 0.6, -1.4 + i * 0.55), C.Stone, M.Marble, "solid")
	end
	part(model, "Porch", Vector3.new(cw, 0.6, 4), cf * CFrame.new(0, 2, 1), C.Stone, M.Marble, "solid")
	for i = 0, 5 do
		local x = -cw / 2 + 2 + i * (cw - 4) / 5
		TownKit.Column(model, "Column", (cf * CFrame.new(x, 2.3, 0)).Position, 9.4, 1.5, trim, M.Marble, "prop")
		part(model, "Capital", Vector3.new(2.2, 0.6, 2.2), cf * CFrame.new(x, 12, 0), trim, M.Marble, "deco")
	end
	part(model, "Entablature", Vector3.new(cw + 1, 1.6, 4.6), cf * CFrame.new(0, 13.1, 1.2), trim, M.Marble, "decoS")
	part(model, "PortalDoor", Vector3.new(6, 9, 0.4), cf * CFrame.new(0, 6.8, 2.85), Color3.fromRGB(120, 80, 70), M.Wood, "deco")
	part(model, "PortalGlass", Vector3.new(4.6, 2.9, 0.3), cf * CFrame.new(0, 12.35, 2.75), Color3.fromRGB(255, 226, 160), M.Glass, "deco")
	-- ailes : fenêtres hautes sur 2 étages
	for _, sx in ipairs({ -1, 1 }) do
		for f = 0, 1 do
			for i = 0, 2 do
				local x = sx * (cw / 2 + 3.5 + i * 6.4)
				window(model, cf * CFrame.new(x, 7 + f * 14, 3), 3.4, 6.4, trim, nil, f == 1, i + f)
			end
		end
		-- drapeaux sur la façade
		local flagBase = cf * CFrame.new(sx * (cw / 2 + 1.2), 16, 2.8)
		TownKit.Beam(model, "FlagPole", flagBase.Position, (flagBase * CFrame.new(0, 3.4, -5.8)).Position, 0.25, 0.25, C.MetalLight, M.Metal, "deco")
		part(model, "Flag", Vector3.new(0.15, 3.2, 3.4), flagBase * CFrame.new(0, 1.6, -3.9), sx < 0 and C.Pink or C.Lilac, M.Fabric, "deco")
	end
	part(model, "Cornice", Vector3.new(w + 1.6, 1.4, d + 1.6), cf * CFrame.new(0, h + 0.7, d / 2 + 3), trim, M.Marble, "decoS")
	-- toit à la Mansart (deux coins) + balustrade
	local top = cf * CFrame.new(0, h + 1.4, 3)
	TownKit.Wedge(model, "Roof", Vector3.new(w, 6, d / 2), top * CFrame.new(0, 3, d / 4), roof, M.Slate, "decoS")
	TownKit.Wedge(model, "Roof", Vector3.new(w, 6, d / 2), top * CFrame.new(0, 3, d * 3 / 4) * CFrame.Angles(0, math.pi, 0), roof, M.Slate, "decoS")
	-- tour de l'horloge (au-dessus du portique)
	local tower = cf * CFrame.new(0, h + 1.4, 8)
	-- (v9.7 : pied de la tour 0,1 au-dessus du bas du toit : faces non confondues)
	part(model, "Tower", Vector3.new(12, 15.9, 12), tower * CFrame.new(0, 8.05, 0), wall, M.Limestone, "solid")
	part(model, "TowerCornice", Vector3.new(13.4, 1, 13.4), tower * CFrame.new(0, 16.5, 0), trim, M.Marble, "deco")
	local clock = part(model, "Clock", Vector3.new(0.6, 8, 8), tower * CFrame.new(0, 9, -6.2) * CFrame.Angles(0, math.rad(90), 0), C.White, M.SmoothPlastic, "deco")
	;(clock :: Part).Shape = Enum.PartType.Cylinder
	local rim = part(model, "ClockRim", Vector3.new(0.4, 9, 9), tower * CFrame.new(0, 9, -6.05) * CFrame.Angles(0, math.rad(90), 0), C.Yellow, M.Metal, "deco")
	;(rim :: Part).Shape = Enum.PartType.Cylinder
	part(model, "HandHour", Vector3.new(0.4, 2.4, 0.2), tower * CFrame.new(0.6, 9.8, -6.6) * CFrame.Angles(0, 0, math.rad(-35)), C.Ink, M.Metal, "deco")
	part(model, "HandMinute", Vector3.new(0.3, 3.4, 0.2), tower * CFrame.new(-0.2, 10.6, -6.65) * CFrame.Angles(0, 0, math.rad(10)), C.Ink, M.Metal, "deco")
	-- flèche (pyramide approchée : deux paires de coins) + cœur
	for r = 0, 1 do
		local rot = CFrame.Angles(0, r * math.pi / 2, 0)
		TownKit.Wedge(model, "Spire", Vector3.new(12, 10, 6), tower * CFrame.new(0, 22, 0) * rot * CFrame.new(0, 0, -3), roof, M.Slate, "decoS")
		TownKit.Wedge(model, "Spire", Vector3.new(12, 10, 6), tower * CFrame.new(0, 22, 0) * rot * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -3), roof, M.Slate, "decoS")
	end
	TownKit.Ball(model, "SpireHeart", (tower * CFrame.new(0, 28, 0)).Position, 2.4, C.Pink, M.SmoothPlastic, "deco")
	-- GRAND ÉCRAN (au-dessus du portique, sous l'horloge)
	local screenCF = cf * CFrame.new(0, 24.5, 2.2)
	part(model, "ScreenFrame", Vector3.new(30, 14.2, 1.2), screenCF * CFrame.new(0, 0, 0.3), Color3.fromRGB(40, 36, 52), M.Metal, "deco")
	local screen = part(model, "Screen", Vector3.new(28.6, 12.8, 0.4), screenCF * CFrame.new(0, 0, -0.4), Color3.fromRGB(24, 20, 40), M.SmoothPlastic, "deco")
	part(model, "ScreenGlow", Vector3.new(30.4, 0.3, 0.3), screenCF * CFrame.new(0, 7.2, -0.5), C.Pink, M.SmoothPlastic, "deco")
	part(model, "ScreenGlow", Vector3.new(30.4, 0.3, 0.3), screenCF * CFrame.new(0, -7.2, -0.5), C.Lilac, M.SmoothPlastic, "deco")
	local light = part(model, "ScreenLight", Vector3.new(1, 1, 1), screenCF * CFrame.new(0, 0, -6), C.White, M.SmoothPlastic, "deco")
	light.Transparency = 1
	-- (v9.6 : lumière douce, pas d'éblouissement)
	TownKit.Light(light, Color3.fromRGB(255, 196, 232), 18, 0.8)
	local _, body = TownKit.Surface(screen, Enum.NormalId.Front, 24, Color3.fromRGB(24, 20, 44), 800, 0)
	TownKit.Gradient(body, Color3.fromRGB(40, 24, 70), Color3.fromRGB(16, 20, 44), 90)
	local title = TownKit.Label(body, "Title", "🏆 Top players of the server", 0.04, 0.04, 0.92, 0.17, Color3.fromRGB(255, 214, 96), Enum.Font.FredokaOne, true)
	local rows = {}
	for i = 1, 5 do
		local row = TownKit.Label(body, "Row" .. i, "", 0.08, 0.23 + (i - 1) * 0.13, 0.84, 0.115, i == 1 and Color3.fromRGB(255, 236, 150) or C.White, Enum.Font.GothamBold, false)
		row.TextXAlignment = Enum.TextXAlignment.Left
		rows[i] = row
	end
	local footer = TownKit.Label(body, "Footer", "❤️ Like houses to climb the board!", 0.06, 0.88, 0.88, 0.09, Color3.fromRGB(255, 160, 210), Enum.Font.GothamBold, true)
	return model, { Rows = rows, Title = title, Footer = footer }
end

----------------------------------------------------------------------
-- Immeubles de rue (v9.7) : COQUE serveur + DÉTAIL client (TownFacades)
----------------------------------------------------------------------
-- Cinq styles qui alternent le long d'une rue (deux voisins ne se
-- ressemblent jamais) :
--   Haussmann : pierre de taille crème, toit à la Mansart en zinc ;
--   Brick     : briques, toit à deux pans en tuiles, cheminée ;
--   Pastel    : enduit pastel, PIGNON SUR RUE (toit à deux pans tourné) ;
--   Modern    : béton clair ou anthracite, toit-terrasse ;
--   Timber    : colombages (enduit crème + poutres sombres), tuiles.
-- Le serveur ne pose que la coque (volume solide, socle, corniche, toit,
-- cheminées) et, pour la vue de loin, des bandeaux vitrés "FarLOD" que le
-- client masque (localement) dès qu'il a construit le vrai détail :
-- fenêtres encadrées, balcons, volets, vitrine FERMÉE (store roulé, stores
-- baissés, pancarte "Fermé"), porte et perron, arrière fini (fenêtres,
-- porte de service, jardinet), pignons exposés (fenêtres, réclame peinte).
-- Attributs lus par le client : FacadeStyle, FacadeCF, W, D, Floors,
-- Height, Seed, Wall, Trim, Accent, Detail, GroundH, FloorH.

TownBuildings.STYLES = { "Haussmann", "Brick", "Pastel", "Modern", "Timber" }

local PASTELS = {
	Color3.fromRGB(255, 206, 214),
	Color3.fromRGB(196, 234, 216),
	Color3.fromRGB(255, 234, 176),
	Color3.fromRGB(216, 204, 248),
	Color3.fromRGB(190, 222, 248),
	Color3.fromRGB(255, 212, 184),
}
local BRICKS = {
	Color3.fromRGB(172, 84, 66),
	Color3.fromRGB(150, 96, 80),
	Color3.fromRGB(196, 128, 96),
	Color3.fromRGB(128, 74, 66),
}
-- devantures (bois peint) et volets
local ACCENTS = {
	Color3.fromRGB(46, 92, 78),
	Color3.fromRGB(48, 62, 104),
	Color3.fromRGB(122, 44, 62),
	Color3.fromRGB(214, 110, 140),
	Color3.fromRGB(86, 150, 170),
	Color3.fromRGB(120, 90, 160),
}

export type RowPalette = { Wall: Color3, Material: Enum.Material, Trim: Color3, Roof: Color3, RoofMat: Enum.Material, Accent: Color3, Detail: Color3 }

-- Style + couleurs d'un immeuble (déterministe : même ville à chaque démarrage)
function TownBuildings.RowStyle(seed: number): (string, RowPalette)
	local style = TownBuildings.STYLES[seed % #TownBuildings.STYLES + 1]
	local accent = ACCENTS[math.floor(hash(seed, 83) * #ACCENTS) + 1]
	if style == "Haussmann" then
		return style, { Wall = Color3.fromRGB(238, 228, 208), Material = M.Limestone, Trim = Color3.fromRGB(248, 242, 230),
			Roof = Color3.fromRGB(104, 112, 132), RoofMat = M.Slate, Accent = accent, Detail = Color3.fromRGB(46, 48, 58) }
	elseif style == "Brick" then
		return style, { Wall = BRICKS[math.floor(hash(seed, 84) * #BRICKS) + 1], Material = M.Brick, Trim = Color3.fromRGB(246, 242, 236),
			Roof = Color3.fromRGB(92, 84, 96), RoofMat = M.Slate, Accent = accent, Detail = Color3.fromRGB(40, 40, 48) }
	elseif style == "Pastel" then
		local wall = PASTELS[math.floor(hash(seed, 85) * #PASTELS) + 1]
		return style, { Wall = wall, Material = M.Plaster, Trim = C.White, Roof = Color3.fromRGB(176, 96, 82), RoofMat = M.ClayRoofTiles,
			Accent = accent, Detail = wall:Lerp(Color3.fromRGB(60, 60, 90), 0.45) }
	elseif style == "Modern" then
		local dark = hash(seed, 86) < 0.4
		return style, { Wall = dark and Color3.fromRGB(74, 78, 92) or Color3.fromRGB(236, 238, 242), Material = M.Concrete,
			Trim = dark and Color3.fromRGB(214, 218, 226) or Color3.fromRGB(70, 74, 88), Roof = Color3.fromRGB(150, 150, 160), RoofMat = M.Concrete,
			Accent = accent, Detail = Color3.fromRGB(60, 64, 76) }
	end
	return style, { Wall = Color3.fromRGB(250, 244, 230), Material = M.Plaster, Trim = Color3.fromRGB(250, 244, 230), Roof = Color3.fromRGB(140, 86, 72),
		RoofMat = M.ClayRoofTiles, Accent = accent, Detail = Color3.fromRGB(92, 62, 46) }
end

-- Toit à deux pans : repère F = milieu de la ligne d'égout "avant", toit sur
-- x ∈ [-W/2, W/2], z ∈ [0, D] (faîtage à z = D/2). Pignons pleins (couleur
-- du mur) + deux pans de couverture qui débordent + faîtière.
local function pitchedRoof(parent: Instance, F: CFrame, W: number, D: number, h: number, wall: Color3, wallMat: Enum.Material, roof: Color3, roofMat: Enum.Material)
	TownKit.Wedge(parent, "Gable", Vector3.new(W, h, D / 2), F * CFrame.new(0, h / 2, D / 4), wall, wallMat, "decoS")
	TownKit.Wedge(parent, "Gable", Vector3.new(W, h, D / 2), F * CFrame.new(0, h / 2, D * 3 / 4) * CFrame.Angles(0, math.pi, 0), wall, wallMat, "decoS")
	local half = D / 2
	local a = math.atan2(h, half)
	local len = math.sqrt(half * half + h * h)
	local t = 0.35
	for _, back in ipairs({ false, true }) do
		local side = back and F * CFrame.new(0, 0, D) * CFrame.Angles(0, math.pi, 0) or F
		-- (pan posé 0,05 au-dessus de la pente : jamais de faces confondues)
		local cf = side * CFrame.new(0, h / 2, half / 2) * CFrame.Angles(-a, 0, 0) * CFrame.new(0, t / 2 + 0.05, -0.45)
		part(parent, "RoofPlane", Vector3.new(W + 1, t, len + 0.9), cf, roof, roofMat, "decoS")
	end
	part(parent, "Ridge", Vector3.new(W + 1.2, 0.45, 0.9), F * CFrame.new(0, h + 0.42, half), roof:Lerp(Color3.new(0, 0, 0), 0.25), M.Slate, "deco")
end
TownBuildings.PitchedRoof = pitchedRoof

function TownBuildings.RowHouse(parent: Instance, cf: CFrame, w: number, d: number, floors: number, seed: number): Model
	local model = TownKit.Model(parent, "RowHouse")
	local style, pal = TownBuildings.RowStyle(seed)
	local height = GROUND_H + (floors - 1) * FLOOR_H
	part(model, "Body", Vector3.new(w, height, d), cf * CFrame.new(0, height / 2, d / 2), pal.Wall, pal.Material, "solid")
	-- socle en pierre (déborde de 0,6 tout autour : les détails de façade tiennent au-dessus)
	part(model, "Plinth", Vector3.new(w + 0.5, 1.8, d + 1.2), cf * CFrame.new(0, 0.3, d / 2), C.StoneDark, M.Granite, "prop")
	-- vue de loin : bandeaux vitrés (masqués par le client quand le détail est là)
	local farGlass = Color3.fromRGB(120, 150, 180)
	local function far(name: string, size: Vector3, at: CFrame)
		local g = part(model, name, size, at, farGlass, M.Glass, "deco")
		g.Reflectance = 0.12
		g:SetAttribute("FarLOD", true)
	end
	far("FarShop", Vector3.new(w - 4, GROUND_H - 4.6, 0.2), cf * CFrame.new(0, 1.2 + (GROUND_H - 4.6) / 2 + 1, -0.1))
	for f = 1, floors - 1 do
		local y = GROUND_H + (f - 1) * FLOOR_H + FLOOR_H / 2 + 0.3
		far("FarFront", Vector3.new(w - 3, 4.4, 0.2), cf * CFrame.new(0, y, -0.1))
		far("FarBack", Vector3.new(w - 5, 3.8, 0.2), cf * CFrame.new(0, y, d + 0.1))
	end
	local top = cf * CFrame.new(0, height, 0)
	if style == "Haussmann" then
		-- corniche, puis toit à la Mansart (brisis raide + terrasson) en zinc, 2 souches de cheminée
		part(model, "Cornice", Vector3.new(w + 0.8, 0.9, d + 0.8), top * CFrame.new(0, 0.45, d / 2), pal.Trim, M.Limestone, "decoS")
		local mh, md = 5.2, 2
		local base = top * CFrame.new(0, 0.9, 0)
		part(model, "MansardCore", Vector3.new(w - 0.2, mh, d - 2 * md), base * CFrame.new(0, mh / 2, d / 2), pal.Roof, pal.RoofMat, "decoS")
		TownKit.Wedge(model, "Mansard", Vector3.new(w - 0.2, mh, md), base * CFrame.new(0, mh / 2, md / 2), pal.Roof, pal.RoofMat, "decoS")
		TownKit.Wedge(model, "Mansard", Vector3.new(w - 0.2, mh, md), base * CFrame.new(0, mh / 2, d - md / 2) * CFrame.Angles(0, math.pi, 0), pal.Roof, pal.RoofMat, "decoS")
		part(model, "MansardCap", Vector3.new(w - 0.4, 0.4, d - 2 * md + 0.6), base * CFrame.new(0, mh + 0.2, d / 2), pal.Roof:Lerp(C.White, 0.2), M.Metal, "deco")
		for _, sx in ipairs({ -1, 1 }) do
			part(model, "Chimney", Vector3.new(1.6, 3.2, 3.4), base * CFrame.new(sx * (w / 2 - 1.2), mh + 1.8, d * 0.55), pal.Wall, M.Limestone, "deco")
		end
	elseif style == "Pastel" then
		-- pignon sur rue : faîtage perpendiculaire à la rue
		part(model, "Cornice", Vector3.new(w + 0.6, 0.6, d + 0.6), top * CFrame.new(0, 0.3, d / 2), pal.Trim, M.SmoothPlastic, "decoS")
		local h = math.min(9, w * 0.4)
		local F = top * CFrame.new(-w / 2, 0.6, d / 2) * CFrame.Angles(0, math.pi / 2, 0)
		pitchedRoof(model, F, d, w, h, pal.Wall, pal.Material, pal.Roof, pal.RoofMat)
		part(model, "Chimney", Vector3.new(1.8, 4.4, 1.8), top * CFrame.new(w * 0.22, 0.6 + h * 0.55 + 1.6, d * 0.7), Color3.fromRGB(196, 120, 100), M.Brick, "deco")
	elseif style == "Modern" then
		-- toit-terrasse : acrotère + édicule
		part(model, "Parapet", Vector3.new(w + 0.4, 1.4, d + 0.4), top * CFrame.new(0, 0.7, d / 2), pal.Trim, M.Concrete, "decoS")
		part(model, "RoofDeck", Vector3.new(w * 0.36, 3, d * 0.34), top * CFrame.new(-w * 0.18, 2.9, d * 0.62), pal.Wall, pal.Material, "deco")
	else
		-- Brick / Timber : corniche + toit à deux pans (faîtage parallèle à la rue) + cheminée
		part(model, "Cornice", Vector3.new(w + 0.8, 0.9, d + 0.8), top * CFrame.new(0, 0.45, d / 2), style == "Brick" and pal.Trim or pal.Detail, style == "Brick" and M.Concrete or M.Wood, "decoS")
		local h = math.min(8, d * 0.42)
		pitchedRoof(model, top * CFrame.new(0, 0.9, 0), w, d, h, pal.Wall, pal.Material, pal.Roof, pal.RoofMat)
		part(model, "Chimney", Vector3.new(2, 4.8, 2), top * CFrame.new(w * 0.3 * (seed % 2 == 0 and 1 or -1), 0.9 + h * 0.6 + 1.4, d * 0.66), style == "Brick" and pal.Wall or Color3.fromRGB(176, 110, 96), M.Brick, "deco")
	end
	model:SetAttribute("FacadeStyle", style)
	model:SetAttribute("FacadeCF", cf)
	model:SetAttribute("W", w)
	model:SetAttribute("D", d)
	model:SetAttribute("Floors", floors)
	model:SetAttribute("Height", height)
	model:SetAttribute("Seed", seed)
	model:SetAttribute("Wall", pal.Wall)
	model:SetAttribute("Trim", pal.Trim)
	model:SetAttribute("Accent", pal.Accent)
	model:SetAttribute("Detail", pal.Detail)
	model:SetAttribute("GroundH", GROUND_H)
	model:SetAttribute("FloorH", FLOOR_H)
	return model
end

----------------------------------------------------------------------
-- Ville lointaine (silhouettes au-delà des collines)
----------------------------------------------------------------------

function TownBuildings.Skyline(parent: Instance, center: Vector3, fromAngle: number, toAngle: number, distance: number, count: number)
	local model = TownKit.Model(parent, "Skyline")
	for i = 1, count do
		local t = (i - 0.5) / count
		local a = fromAngle + (toAngle - fromAngle) * t + (hash(i, 41) - 0.5) * 0.04
		local dist = distance + hash(i, 42) * 90
		local h = 40 + hash(i, 43) * 90
		local w = 26 + hash(i, 44) * 30
		local p = center + Vector3.new(math.sin(a) * dist, h / 2 - 6, math.cos(a) * dist)
		local cf = CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z))
		local tone = Color3.fromRGB(176, 186, 222):Lerp(Color3.fromRGB(214, 196, 232), hash(i, 45))
		part(model, "Tower", Vector3.new(w, h, w * 0.8), cf, tone, M.SmoothPlastic, "deco")
		-- rangées de fenêtres (une bande lumineuse) + toit
		part(model, "Windows", Vector3.new(w * 0.7, h * 0.8, 0.2), cf * CFrame.new(0, -h * 0.02, -w * 0.4 - 0.1), tone:Lerp(Color3.fromRGB(255, 244, 214), 0.35), M.SmoothPlastic, "deco")
		if hash(i, 46) < 0.35 then
			part(model, "Antenna", Vector3.new(0.8, 16, 0.8), cf * CFrame.new(0, h / 2 + 8, 0), tone, M.Metal, "deco")
		end
	end
	return model
end

return TownBuildings
