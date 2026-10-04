--[[
	CityBuildings (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > CityBuildings

	🏙️ Dopamine Town (v11, CITY11) : le CATALOGUE DES BÂTIMENTS de la ville
	(fini les mêmes immeubles doublés / triplés). Construits côté CLIENT, en
	flux (TownStreetLife), aux emplacements choisis par CityPlan dans les
	zones libres des quartiers : chaque type a sa silhouette, ses matériaux,
	son enseigne et son INTÉRIEUR où l'on ENTRE (porte ≥ 5 x 9, rez-de-
	chaussée de 12 : cibles SCALE11), aménagé par CityInteriors avec ses PNJ
	animés. Variation déterministe (graine) : couleurs, étages, toits,
	métier des petites boutiques. Types :
	  💊 Pharmacie (croix verte lumineuse en drapeau)   🥖 Boulangerie (toit à la Mansart)
	  📖 Bibliothèque (portique à colonnes, fronton)     🏫 École (horloge, mât, marelle)
	  🚓 Commissariat (lanterne bleue, bandeau)          🚒 Caserne (portes de garage, tour de séchage)
	  🩺 Centre médical (auvent, croix rouge)            📮 Bureau de poste (bandeau jaune, boîte)
	  💪 Salle de sport (façade vitrée)                  🏨 Hôtel (6 étages, balcons, marquise)
	  🏛️ Musée (dôme, colonnes, bannières)               ⛪ Église (nef, clocher et flèche, rosace)
	  🎬 Cinéma (marquise à ampoules, enseigne verticale) 🔧 Garage (rideau levé, pneus)
	  🏢 Immeuble de bureaux (mur-rideau)                🏘️ Immeuble d'habitation (balcons, commerce)
	  🛍️ Petite boutique (21 métiers)                    ☕ Café / 🍝 Restaurant
	Fenêtres de côté / de dos : une seule pièce peinte par face (SurfaceGui :
	budget de pièces), façade : vraies fenêtres (appuis, linteaux, lumières
	"NightGlow" la nuit). Repère F : au sol, au centre de l'emprise, -Z = rue.

	API (CityPlan) :
	  CityBuildings.TYPES : { [type]: Spec }   CityBuildings.ORDER : { type }
	  CityBuildings.BUILDERS / FOOT / BIG / IMPOSTORS : clés "Bld<Type>"
	  CityBuildings.FOR_STYLE : { [districtStyle]: { type } }
	  CityBuildings.CAP : { [type]: number } (exemplaires au plus dans la ville)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local CityKit = require(script.Parent.CityKit)
local CityInteriors = require(script.Parent.CityInteriors)

local CityBuildings = {}

local M = CityKit.M
local rgb = CityKit.rgb
local Box, Part, Column, Wedge, Egg, Glow, Text = CityKit.Box, CityKit.Part, CityKit.Column, CityKit.Wedge, CityKit.Egg, CityKit.Glow, CityKit.Text
local hash = CityKit.Hash
local Pick = CityKit.Pick

local WHITE = rgb(250, 250, 248)
local INK = rgb(36, 34, 44)
local GLASS = rgb(150, 182, 206)
local WARM = rgb(255, 230, 182)
local STONE = rgb(226, 218, 200)
local IRON = rgb(44, 46, 54)
local GOLD = rgb(214, 180, 92)

local FLOOR = 0.3 -- dessus du sol fini du rez-de-chaussée
local GROUND = 12 -- hauteur du rez-de-chaussée (plafond ≥ 12 : SCALE11)
local STOREY = 10
local WALL = 0.4

type Spec = {
	W: number,
	D: number,
	Floors: { number }, -- min, max
	Walls: { Color3 },
	Mat: Enum.Material,
	Trim: Color3,
	Roof: string, -- Flat | Gable | Mansard | Dome | Custom
	RoofColors: { Color3 }?,
	Front: string, -- Shop | Grand | Garage | Glass
	Kind: string?, -- métier de l'intérieur (nil : tiré dans STREET_SHOPS)
	Sign: string?, -- nom anglais (Locale) ; nil : celui du métier
	Ground: number?,
}

local PASTEL = { rgb(255, 214, 214), rgb(214, 236, 222), rgb(255, 236, 190), rgb(222, 214, 248), rgb(200, 226, 246), rgb(255, 222, 196), rgb(236, 230, 220) }
local BRICKS = { rgb(170, 88, 68), rgb(150, 96, 80), rgb(196, 128, 96), rgb(128, 74, 66) }

CityBuildings.TYPES = {
	Pharmacy = { W = 20, D = 18, Floors = { 2, 3 }, Walls = { WHITE, rgb(236, 244, 240) }, Mat = M.Plaster, Trim = rgb(40, 150, 90), Roof = "Flat", Front = "Shop", Kind = "Pharmacy" },
	Bakery = { W = 20, D = 18, Floors = { 3, 3 }, Walls = { rgb(250, 236, 206), rgb(244, 226, 196) }, Mat = M.Plaster, Trim = rgb(120, 40, 50), Roof = "Mansard", RoofColors = { rgb(104, 112, 132) }, Front = "Shop", Kind = "Bakery" },
	Library = { W = 34, D = 24, Floors = { 2, 2 }, Walls = { STONE }, Mat = M.Limestone, Trim = rgb(246, 240, 228), Roof = "Flat", Front = "Grand", Kind = "Library", Ground = 14 },
	School = { W = 40, D = 24, Floors = { 2, 2 }, Walls = BRICKS, Mat = M.Brick, Trim = rgb(246, 242, 236), Roof = "Gable", RoofColors = { rgb(92, 84, 96), rgb(150, 80, 70) }, Front = "Grand", Kind = "School" },
	Police = { W = 28, D = 22, Floors = { 2, 3 }, Walls = { rgb(214, 220, 232), rgb(190, 200, 216) }, Mat = M.Concrete, Trim = rgb(30, 60, 140), Roof = "Flat", Front = "Glass", Kind = "Police" },
	Fire = { W = 30, D = 24, Floors = { 2, 2 }, Walls = BRICKS, Mat = M.Brick, Trim = rgb(200, 40, 40), Roof = "Flat", Front = "Garage", Kind = "Fire", Ground = 13 },
	Clinic = { W = 30, D = 22, Floors = { 3, 4 }, Walls = { WHITE, rgb(232, 242, 246) }, Mat = M.SmoothPlastic, Trim = rgb(220, 60, 70), Roof = "Flat", Front = "Glass", Kind = "Clinic" },
	Post = { W = 22, D = 18, Floors = { 2, 2 }, Walls = { rgb(240, 236, 222), STONE }, Mat = M.Limestone, Trim = rgb(250, 196, 30), Roof = "Gable", RoofColors = { rgb(140, 86, 72) }, Front = "Shop", Kind = "Post" },
	Gym = { W = 28, D = 22, Floors = { 2, 2 }, Walls = { rgb(60, 64, 80), rgb(40, 44, 56) }, Mat = M.Concrete, Trim = rgb(255, 120, 40), Roof = "Flat", Front = "Glass", Kind = "Gym" },
	Hotel = { W = 26, D = 22, Floors = { 5, 6 }, Walls = { rgb(240, 228, 206), rgb(226, 214, 196), rgb(214, 200, 220) }, Mat = M.Limestone, Trim = GOLD, Roof = "Mansard", RoofColors = { rgb(70, 76, 96) }, Front = "Grand", Kind = "Hotel" },
	Museum = { W = 36, D = 24, Floors = { 2, 2 }, Walls = { rgb(246, 240, 228) }, Mat = M.Marble, Trim = rgb(250, 248, 240), Roof = "Dome", RoofColors = { rgb(110, 160, 150) }, Front = "Grand", Kind = "Museum", Ground = 16 },
	Church = { W = 26, D = 24, Floors = { 1, 1 }, Walls = { rgb(222, 212, 192), rgb(200, 190, 176) }, Mat = M.Cobblestone, Trim = rgb(236, 228, 212), Roof = "Custom", RoofColors = { rgb(84, 88, 104) }, Front = "Custom", Kind = "Church", Ground = 18 },
	Cinema = { W = 30, D = 24, Floors = { 2, 2 }, Walls = { rgb(120, 30, 46), rgb(60, 40, 70) }, Mat = M.Concrete, Trim = rgb(255, 214, 96), Roof = "Flat", Front = "Glass", Kind = "Cinema", Ground = 13 },
	Garage = { W = 26, D = 22, Floors = { 1, 1 }, Walls = { rgb(180, 186, 196), rgb(140, 150, 160) }, Mat = M.CorrodedMetal, Trim = rgb(230, 120, 30), Roof = "Flat", Front = "Garage", Kind = "Garage", Ground = 13 },
	Office = { W = 24, D = 22, Floors = { 6, 8 }, Walls = { rgb(120, 150, 180), rgb(90, 120, 150), rgb(150, 170, 186) }, Mat = M.Glass, Trim = rgb(220, 224, 232), Roof = "Flat", Front = "Glass", Kind = "Office" },
	Apartments = { W = 24, D = 18, Floors = { 4, 5 }, Walls = PASTEL, Mat = M.Plaster, Trim = WHITE, Roof = "Gable", RoofColors = { rgb(176, 96, 82), rgb(92, 84, 96) }, Front = "Shop" },
	Shop = { W = 18, D = 16, Floors = { 2, 3 }, Walls = PASTEL, Mat = M.Plaster, Trim = WHITE, Roof = "Gable", RoofColors = { rgb(176, 96, 82), rgb(104, 112, 132), rgb(150, 80, 70) }, Front = "Shop" },
	Cafe = { W = 20, D = 18, Floors = { 2, 3 }, Walls = BRICKS, Mat = M.Brick, Trim = rgb(246, 242, 236), Roof = "Flat", Front = "Shop", Kind = "Cafe" },
	Restaurant = { W = 22, D = 18, Floors = { 2, 3 }, Walls = { rgb(244, 230, 210), rgb(236, 214, 196) }, Mat = M.Plaster, Trim = rgb(150, 40, 50), Roof = "Gable", RoofColors = { rgb(176, 96, 82) }, Front = "Shop", Kind = "Restaurant" },
} :: { [string]: Spec }

-- ordre du catalogue (CityPlan tire le type le MOINS utilisé qui tient)
CityBuildings.ORDER = {
	"Library", "Pharmacy", "School", "Cafe", "Police", "Bakery", "Fire", "Shop", "Clinic", "Post", "Hotel", "Restaurant",
	"Museum", "Gym", "Church", "Cinema", "Apartments", "Garage", "Office", "Shop", "Apartments",
}
-- nombre maximal dans la ville (8 parcelles ; +1 à 25 et à 50 parcelles) :
-- un seul exemplaire de chaque lieu public, les commerces se déclinent
CityBuildings.CAP = {
	Library = 1, School = 1, Police = 1, Fire = 1, Clinic = 1, Post = 1, Gym = 1, Hotel = 1, Museum = 1, Church = 1,
	Cinema = 1, Garage = 2, Office = 3, Pharmacy = 2, Bakery = 2, Cafe = 3, Restaurant = 3, Apartments = 6, Shop = 10,
}
CityBuildings.FOR_STYLE = {
	Townhouse = { "Pharmacy", "Bakery", "Library", "School", "Police", "Clinic", "Post", "Hotel", "Museum", "Church", "Cinema", "Cafe", "Restaurant", "Shop", "Apartments" },
	Loft = { "Fire", "Gym", "Garage", "Office", "Cinema", "Apartments", "Restaurant", "Shop", "Cafe" },
	Mixed = { "Fire", "Police", "School", "Clinic", "Gym", "Hotel", "Office", "Garage", "Cafe", "Shop", "Apartments", "Post", "Museum" },
	Cottage = { "Post", "Shop", "Cafe", "Pharmacy", "Bakery", "Library" },
	Mansion = {},
}

----------------------------------------------------------------------
-- Pièces communes
----------------------------------------------------------------------

type Ctx = { Podium: boolean?, M: Model, F: CFrame, Spec: Spec, Seed: number, W: number, D: number, G: number, H: number, Floors: number, Wall: Color3, Trim: Color3, Roof: Color3, Kind: string, Sign: string, FZ: number, DoorX: number }

-- fenêtre de façade (verre, appui, linteau) ; une sur trois allumée la nuit
local function frontWindow(c: Ctx, x: number, y0: number, ww: number, hh: number, k: number)
	local z = c.FZ
	local lit = hash(c.Seed, k) < 0.33
	local g = Box(c.M, "Window", c.F, x - ww / 2, x + ww / 2, y0, y0 + hh, z - 0.08, z, lit and WARM or GLASS, M.Glass)
	g.Reflectance = 0.12
	if lit then
		Glow(g)
	end
	Box(c.M, "WindowSill", c.F, x - ww / 2 - 0.3, x + ww / 2 + 0.3, y0 - 0.35, y0, z - 0.45, z, c.Trim, M.Concrete)
	Box(c.M, "WindowHead", c.F, x - ww / 2 - 0.25, x + ww / 2 + 0.25, y0 + hh, y0 + hh + 0.4, z - 0.3, z, c.Trim, M.Concrete)
end

-- fenêtres peintes sur une face (côtés / dos) : une pièce + SurfaceGui
local function paintedFace(c: Ctx, R: CFrame, w: number, y0: number, y1: number, cols: number, rows: number, storey: number)
	local skin = Box(c.M, "FaceSkin", R, -w / 2, w / 2, y0, y1, -0.06, -0.01, c.Wall, c.Spec.Mat)
	local gui = CityKit.Canvas(skin, Enum.NormalId.Front, 320, 3)
	local H = y1 - y0
	for r = 0, rows - 1 do
		-- milieu de la fenêtre : rez-de-chaussée à mi-hauteur, étages à 55 %
		local y = r == 0 and c.G * 0.5 or c.G + (r - 1) * storey + storey * 0.55
		local yc = 1 - (y - y0) / H
		for k = 0, cols - 1 do
			local xc = (k + 0.5) / cols
			local lit = hash(c.Seed + k * 3, r + 50) < 0.25
			CityKit.Blob(gui, xc, yc, 0.55 / cols, 4.6 / H, c.Trim:Lerp(WHITE, 0.3))
			CityKit.Blob(gui, xc, yc, 0.45 / cols, 4.0 / H, lit and WARM or GLASS:Lerp(INK, 0.15))
		end
	end
	return skin
end

-- enseigne principale (bandeau au-dessus du rez-de-chaussée)
local function signBoard(c: Ctx, w: number, y: number, fg: Color3, bg: Color3)
	local info = CityInteriors.Info(c.Kind)
	local text = info.Emoji .. " " .. Locale.T(c.Sign)
	local b = Box(c.M, "SignBoard", c.F, -w / 2, w / 2, y, y + 2.2, c.FZ - 0.35, c.FZ - 0.05, bg, M.SmoothPlastic)
	Text(b, Enum.NormalId.Front, text, fg, bg, Enum.Font.FredokaOne, 140, 24)
	return b
end

-- enseigne en drapeau (perpendiculaire à la façade)
local function bladeSign(c: Ctx, x: number, y: number, text: string, fg: Color3, bg: Color3, glow: boolean?)
	local R = c.F * CFrame.new(x, y, c.FZ - 1.6)
	Box(c.M, "BladeArm", c.F, x - 0.08, x + 0.08, y + 1.5, y + 1.7, c.FZ - 2.9, c.FZ, IRON, M.Metal)
	local b = Box(c.M, "BladeSign", R, -0.12, 0.12, -1.4, 1.4, -1.2, 1.2, bg, M.SmoothPlastic)
	if glow then
		Glow(b)
	end
	Text(b, Enum.NormalId.Right, text, fg, bg, Enum.Font.GothamBlack, 120, 30)
	Text(b, Enum.NormalId.Left, text, fg, bg, Enum.Font.GothamBlack, 120, 30)
end

----------------------------------------------------------------------
-- Rez-de-chaussée : coque, façade percée, intérieur
----------------------------------------------------------------------

local function groundShell(c: Ctx)
	local W, D, G = c.W, c.D, c.G
	local hw, hd = W / 2, D / 2
	local info = CityInteriors.Info(c.Kind)
	-- murs latéraux et du fond (couleur de façade) + doublage intérieur
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx * hw, sx * (hw - WALL)
		Box(c.M, "Wall", c.F, math.min(a, b), math.max(a, b), 0, G, -hd + WALL, hd - WALL, c.Wall, c.Spec.Mat, true)
		local la, lb = sx * (hw - WALL), sx * (hw - WALL - 0.05)
		Box(c.M, "Lining", c.F, math.min(la, lb), math.max(la, lb), FLOOR, G - 0.3, -hd + WALL + 0.05, hd - WALL - 0.05, info.Wall, M.SmoothPlastic)
	end
	Box(c.M, "Wall", c.F, -hw, hw, 0, G, hd - WALL, hd, c.Wall, c.Spec.Mat, true)
	Box(c.M, "Lining", c.F, -hw + WALL + 0.05, hw - WALL - 0.05, FLOOR, G - 0.3, hd - WALL - 0.05, hd - WALL, info.Wall, M.SmoothPlastic)
	-- sol fini + plafond
	Box(c.M, "InFloor", c.F, -hw + WALL, hw - WALL, FLOOR - 0.45, FLOOR, -hd + WALL, hd - WALL, info.Floor, info.FloorMat, true)
	Box(c.M, "InCeiling", c.F, -hw + WALL, hw - WALL, G - 0.3, G - 0.04, -hd + WALL, hd - WALL, rgb(246, 244, 240), M.SmoothPlastic)
	CityInteriors.Lamps(c.M, c.F * CFrame.new(0, FLOOR, -hd), W - 1, D - 0.5, G - FLOOR, c.Kind)
	-- socle (bandeau de pierre en bas des murs, dehors)
	Box(c.M, "Plinth", c.F, -hw - 0.2, hw + 0.2, -0.1, 1.0, hd, hd + 0.2, STONE:Lerp(INK, 0.25), M.Granite)
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx * hw, sx * (hw + 0.2)
		Box(c.M, "Plinth", c.F, math.min(a, b), math.max(a, b), -0.1, 1.0, -hd, hd, STONE:Lerp(INK, 0.25), M.Granite)
	end
end

-- façade avant percée : ouvertures { {x0, x1, y0, y1, kind} } (glass | door | garage)
local function pierced(c: Ctx, holes: { { any } }, color: Color3, mat: Enum.Material)
	local z0, z1 = c.FZ, c.FZ + WALL
	local hw = c.W / 2
	local list = {}
	for _, h in ipairs(holes) do
		table.insert(list, { h[1], h[2], h[3], h[4] })
	end
	for i, h in ipairs(holes) do
		-- (porte / garage : percée jusqu'au sol, le seuil fait le sol)
		if h[5] ~= "glass" then
			list[i][3] = 0
		end
	end
	CityKit.WallWithHoles(c.M, "Front", c.F, -hw, hw, 0, c.G, z0, z1, list, color, mat, true)
	for i, h in ipairs(holes) do
		local x0, x1, y0, y1, kind = h[1] :: number, h[2] :: number, h[3] :: number, h[4] :: number, h[5] :: string
		-- encadrement (4 baguettes devant le mur)
		local t = c.Trim
		Box(c.M, "Frame", c.F, x0 - 0.25, x1 + 0.25, y1, y1 + 0.3, z0 - 0.12, z0 + 0.02, t, M.SmoothPlastic)
		for _, x in ipairs({ x0 - 0.25, x1 }) do
			Box(c.M, "Frame", c.F, x, x + 0.25, math.max(0, y0 - (kind == "glass" and 0.3 or 0)), y1, z0 - 0.12, z0 + 0.02, t, M.SmoothPlastic)
		end
		if kind == "glass" then
			Box(c.M, "Frame", c.F, x0, x1, y0 - 0.3, y0, z0 - 0.12, z0 + 0.02, t, M.SmoothPlastic)
			local g = Box(c.M, "ShopGlass", c.F, x0, x1, y0, y1, z0 + 0.15, z0 + 0.25, GLASS, M.Glass, true)
			g.Transparency = 0.7
			g.Reflectance = 0.1
			if x1 - x0 > 6 then
				local mx = (x0 + x1) / 2
				Box(c.M, "Mullion", c.F, mx - 0.1, mx + 0.1, y0, y1, z0 + 0.1, z0 + 0.3, t, M.SmoothPlastic)
			end
		elseif kind == "door" then
			-- deux battants ouverts vers l'intérieur
			for _, sx in ipairs({ -1, 1 }) do
				local hx = sx < 0 and x0 or x1
				local leaf = (x1 - x0) / 2 - 0.05
				local Hn = c.F * CFrame.new(hx, 0, z1 + 0.1) * CFrame.Angles(0, sx < 0 and math.rad(-100) or math.rad(100), 0)
				Box(c.M, "DoorLeaf", Hn, sx < 0 and 0 or -leaf, sx < 0 and leaf or 0, FLOOR, y1 - 0.1, -0.08, 0.08, c.Trim:Lerp(INK, 0.3), M.Wood)
				local dg = Box(c.M, "DoorGlass", Hn, sx < 0 and 0.3 or -leaf + 0.3, sx < 0 and leaf - 0.3 or -0.3, FLOOR + 2.2, y1 - 0.7, -0.1, -0.08, GLASS, M.Glass)
				dg.Transparency = 0.5
			end
			-- seuil
			Box(c.M, "Threshold", c.F, x0, x1, 0, FLOOR, z0 - 1.2, z1, STONE:Lerp(INK, 0.2), M.Granite, true)
		elseif kind == "garage" then
			-- rideau métallique ENROULÉ en haut (porte ouverte)
			local drum = Part(c.M, "RollDrum", Vector3.new(x1 - x0 + 0.4, 1.3, 1.3), c.F * CFrame.new((x0 + x1) / 2, y1 + 0.55, z1 + 0.7), c.Trim:Lerp(INK, 0.2), M.Metal, "Cyl")
			local _ = drum
			Box(c.M, "Threshold", c.F, x0, x1, 0, FLOOR, z0 - 1.2, z1, rgb(120, 122, 126), M.Concrete, true)
		end
		local _ = i
	end
end

local function furnish(c: Ctx)
	local ok, err = pcall(CityInteriors.Furnish, c.M, c.F * CFrame.new(0, FLOOR, c.FZ), c.W - 0.1, c.D - 0.05, c.G - FLOOR, c.Kind, c.Seed, { DoorX = c.DoorX, MaxNpc = 3 })
	if not ok then
		warn("[CityBuildings] intérieur : " .. tostring(err))
	end
end

----------------------------------------------------------------------
-- Étages, faces, toits
----------------------------------------------------------------------

local function upper(c: Ctx, perFloor: number?)
	local W, D, G, H = c.W, c.D, c.G, c.H
	local hw, hd = W / 2, D / 2
	if H > G + 0.5 then
		Box(c.M, "Block", c.F, -hw, hw, G, H, -hd, hd, c.Wall, c.Spec.Mat, true)
		-- bandeau d'étage + fenêtres de façade
		local n = perFloor or math.max(2, math.floor(W / 5.5))
		for f = 1, c.Floors - 1 do
			local yb = G + (f - 1) * STOREY
			Box(c.M, "Band", c.F, -hw - 0.15, hw + 0.15, yb, yb + 0.45, -hd - 0.15, -hd, c.Trim, M.Concrete)
			for i = 0, n - 1 do
				local x = -hw + (i + 0.5) * W / n
				frontWindow(c, x, yb + 2.4, math.min(3.2, W / n - 1.6), 5.4, f * 20 + i)
			end
		end
	end
	-- côtés et dos peints (toute la hauteur)
	local rows = c.Floors
	paintedFace(c, c.F * CFrame.new(0, 0, hd) * CFrame.Angles(0, math.pi, 0), W - 0.2, 1.0, H, math.max(2, math.floor(W / 6)), rows, STOREY)
	for _, sx in ipairs({ -1, 1 }) do
		paintedFace(c, c.F * CFrame.new(sx * hw, 0, 0) * CFrame.Angles(0, sx * -math.pi / 2, 0), D - 0.2, 1.0, H, math.max(2, math.floor(D / 7)), rows, STOREY)
	end
end

local function roof(c: Ctx)
	local W, D, H = c.W, c.D, c.H
	local hw, hd = W / 2, D / 2
	local kind = c.Spec.Roof
	Box(c.M, "Cornice", c.F, -hw - 0.5, hw + 0.5, H, H + 0.7, -hd - 0.5, hd + 0.5, c.Trim, M.Concrete)
	local top = H + 0.7
	if kind == "Gable" then
		local h = math.min(9, D * 0.42)
		-- (pignons : le haut au faîtage, z = 0)
		Wedge(c.M, "Gable", Vector3.new(W, h, hd), c.F * CFrame.new(0, top + h / 2, -hd / 2), c.Wall, c.Spec.Mat)
		Wedge(c.M, "Gable", Vector3.new(W, h, hd), c.F * CFrame.new(0, top + h / 2, hd / 2) * CFrame.Angles(0, math.pi, 0), c.Wall, c.Spec.Mat)
		local len = math.sqrt(hd * hd + h * h)
		local a = math.atan2(h, hd)
		for _, s in ipairs({ -1, 1 }) do
			local cf = c.F * CFrame.new(0, top + h / 2, s * hd / 2) * CFrame.Angles(s * a, 0, 0) * CFrame.new(0, 0.25, 0)
			Part(c.M, "RoofPlane", Vector3.new(W + 1.2, 0.35, len + 0.9), cf, c.Roof, M.ClayRoofTiles)
		end
		Box(c.M, "Ridge", c.F, -hw - 0.7, hw + 0.7, top + h + 0.05, top + h + 0.5, -0.45, 0.45, c.Roof:Lerp(INK, 0.3), M.Slate)
		Box(c.M, "Chimney", c.F, hw * 0.4, hw * 0.4 + 1.8, top + h * 0.3, top + h + 2, hd * 0.35, hd * 0.35 + 1.8, rgb(170, 100, 84), M.Brick)
	elseif kind == "Mansard" then
		local mh, md = 6, 2.2
		Box(c.M, "MansardCore", c.F, -hw + 0.1, hw - 0.1, top, top + mh, -hd + md, hd - md, c.Roof, M.Slate)
		Wedge(c.M, "Mansard", Vector3.new(W - 0.2, mh, md), c.F * CFrame.new(0, top + mh / 2, -hd + md / 2), c.Roof, M.Slate)
		Wedge(c.M, "Mansard", Vector3.new(W - 0.2, mh, md), c.F * CFrame.new(0, top + mh / 2, hd - md / 2) * CFrame.Angles(0, math.pi, 0), c.Roof, M.Slate)
		Box(c.M, "MansardCap", c.F, -hw + 0.3, hw - 0.3, top + mh, top + mh + 0.4, -hd + md - 0.2, hd - md + 0.2, c.Roof:Lerp(WHITE, 0.2), M.Metal)
		-- lucarnes
		local n = math.max(2, math.floor(W / 7))
		for i = 0, n - 1 do
			local x = -hw + (i + 0.5) * W / n
			Box(c.M, "Dormer", c.F, x - 1.3, x + 1.3, top + 1.2, top + 4.6, -hd + 0.6, -hd + 2.4, c.Wall, c.Spec.Mat)
			Box(c.M, "DormerGlass", c.F, x - 0.8, x + 0.8, top + 1.8, top + 4.0, -hd + 0.52, -hd + 0.6, GLASS, M.Glass)
			Box(c.M, "DormerRoof", c.F, x - 1.6, x + 1.6, top + 4.6, top + 5.0, -hd + 0.4, -hd + 2.6, c.Roof, M.Slate)
		end
	elseif kind == "Dome" then
		Box(c.M, "Attic", c.F, -hw + 1, hw - 1, top, top + 2, -hd + 1, hd - 1, c.Wall, c.Spec.Mat)
		Column(c.M, "Drum", c.F, 0, 0, top + 2, top + 6, math.min(W, D) * 0.55, c.Wall, c.Spec.Mat)
		local r = math.min(W, D) * 0.55
		Egg(c.M, "Dome", c.F * CFrame.new(0, top + 6, 0), Vector3.new(r, r * 0.9, r), c.Roof, M.Metal)
		Column(c.M, "Lantern", c.F, 0, 0, top + 6 + r * 0.42, top + 8 + r * 0.42, 1.6, c.Trim, M.Marble)
		CityKit.Ball(c.M, "Finial", (c.F * CFrame.new(0, top + 8.6 + r * 0.42, 0)).Position, 1.0, GOLD, M.Metal)
	elseif kind == "Flat" then
		Box(c.M, "RoofDeck", c.F, -hw + 0.3, hw - 0.3, top, top + 0.3, -hd + 0.3, hd - 0.3, rgb(96, 98, 106), M.Concrete)
		Box(c.M, "Parapet", c.F, -hw - 0.2, hw + 0.2, top, top + 1.4, -hd - 0.2, -hd + 0.3, c.Wall, c.Spec.Mat)
		Box(c.M, "RoofUnit", c.F, -hw * 0.5, -hw * 0.5 + 3.6, top + 0.3, top + 2.6, hd * 0.2, hd * 0.2 + 2.6, rgb(200, 204, 210), M.Metal)
		if hash(c.Seed, 77) < 0.5 then
			Column(c.M, "WaterTank", c.F, hw * 0.45, hd * 0.3, top + 0.3, top + 4.6, 3.4, rgb(150, 110, 80), M.WoodPlanks)
			Egg(c.M, "TankCap", c.F * CFrame.new(hw * 0.45, top + 4.6, hd * 0.3), Vector3.new(3.6, 1.4, 3.6), rgb(90, 90, 96), M.Metal)
		end
	end
end

----------------------------------------------------------------------
-- Façades par style
----------------------------------------------------------------------

-- boutique : vitrines, porte, bandeau d'enseigne, store
local function shopFront(c: Ctx, awning: Color3?)
	local W, G = c.W, c.G
	local hw = W / 2
	local dw = 5
	local doorRight = hash(c.Seed, 5) < 0.5
	local dx = (doorRight and 1 or -1) * (hw - 1.4 - dw / 2)
	c.DoorX = dx
	local top = G - 3
	local holes = { { dx - dw / 2, dx + dw / 2, FLOOR, 9.3, "door" } }
	local a, b = -hw + 1.4, hw - 1.4
	if doorRight then
		table.insert(holes, { a, dx - dw / 2 - 1.0, 2.2, top, "glass" })
	else
		table.insert(holes, { dx + dw / 2 + 1.0, b, 2.2, top, "glass" })
	end
	pierced(c, holes, c.Spec.Front == "Shop" and c.Trim:Lerp(INK, 0.45) or c.Wall, M.Wood)
	signBoard(c, W - 3.2, G - 2.6, CityInteriors.Info(c.Kind).Sign, rgb(252, 246, 232))
	if awning then
		local n = math.max(4, math.floor((W - 3) / 2.4))
		local sw = (W - 3) / n
		for i = 1, n do
			local x = -hw + 1.5 + (i - 0.5) * sw
			Part(c.M, "Awning", Vector3.new(sw, 0.12, 3.2), c.F * CFrame.new(x, G - 3.4, c.FZ - 1.55) * CFrame.Angles(math.rad(20), 0, 0), i % 2 == 0 and WHITE or awning, M.Fabric)
		end
	end
end

-- façade vitrée (verre du sol au plafond, porte au milieu)
local function glassFront(c: Ctx)
	local W, G = c.W, c.G
	local hw = W / 2
	local dw = 5.2
	c.DoorX = 0
	local top = G - 2.8
	local holes = { { -dw / 2, dw / 2, FLOOR, 9.4, "door" } }
	table.insert(holes, { -hw + 1.2, -dw / 2 - 0.8, 1.0, top, "glass" })
	table.insert(holes, { dw / 2 + 0.8, hw - 1.2, 1.0, top, "glass" })
	pierced(c, holes, c.Trim:Lerp(c.Wall, 0.5), M.Concrete)
	signBoard(c, math.min(W - 4, 16), G - 2.5, WHITE, c.Trim)
end

-- façade "noble" : porte haute au centre, hautes fenêtres, marches
local function grandFront(c: Ctx)
	local W, G = c.W, c.G
	local hw = W / 2
	local dw = 5.4
	c.DoorX = 0
	local holes = { { -dw / 2, dw / 2, FLOOR, math.min(G - 1.6, 10), "door" } }
	local n = math.max(1, math.floor((hw - dw / 2 - 2) / 5))
	for _, sx in ipairs({ -1, 1 }) do
		for i = 1, n do
			local x = sx * (dw / 2 + 1.0 + (i - 0.5) * (hw - dw / 2 - 2) / n)
			table.insert(holes, { x - 1.6, x + 1.6, 2.6, G - 2.4, "glass" })
		end
	end
	pierced(c, holes, c.Wall, c.Spec.Mat)
	-- marches devant la porte (sauf sur un podium / stylobate)
	if not c.Podium then
		Box(c.M, "Steps", c.F, -dw / 2 - 2, dw / 2 + 2, -0.1, 0.15, c.FZ - 3, c.FZ - 1.8, STONE, M.Marble, true)
		Box(c.M, "Steps", c.F, -dw / 2 - 1.4, dw / 2 + 1.4, -0.1, 0.3, c.FZ - 1.8, c.FZ - 1.2, STONE, M.Marble, true)
	end
	signBoard(c, math.min(W - 6, 18), G - 2.2, c.Spec.Front == "Grand" and INK or WHITE, c.Trim)
end

-- façade de garage : grandes portes (≥ 9 x 7,5) + porte de bureau
local function garageFront(c: Ctx, doors: number)
	local W, G = c.W, c.G
	local hw = W / 2
	local holes = {}
	local gw = 9.6
	local x0 = -hw + 1.2
	for _ = 1, doors do
		table.insert(holes, { x0, x0 + gw, FLOOR, FLOOR + 8.4, "garage" })
		x0 += gw + 1.2
	end
	local dx = math.min(hw - 3.4, x0 + 2.6)
	c.DoorX = dx
	table.insert(holes, { dx - 2.4, dx + 2.4, FLOOR, 9.2, "door" })
	pierced(c, holes, c.Wall, c.Spec.Mat)
	signBoard(c, math.min(W - 4, 16), G - 2.4, WHITE, c.Trim)
end

----------------------------------------------------------------------
-- Signatures de chaque type
----------------------------------------------------------------------

local EXTRAS: { [string]: (c: Ctx) -> () } = {}

EXTRAS.Pharmacy = function(c)
	local R = c.F * CFrame.new(c.W / 2 - 1.5, c.G + 1.2, c.FZ - 1.6)
	Box(c.M, "CrossArm", c.F, c.W / 2 - 1.6, c.W / 2 - 1.4, c.G + 2.6, c.G + 2.8, c.FZ - 2.6, c.FZ, IRON, M.Metal)
	Glow(Box(c.M, "CrossV", R, -0.15, 0.15, -1.3, 1.3, -0.45, 0.45, rgb(40, 200, 100), M.SmoothPlastic))
	Glow(Box(c.M, "CrossH", R, -0.14, 0.14, -0.45, 0.45, -1.3, 1.3, rgb(40, 200, 100), M.SmoothPlastic))
end
EXTRAS.Bakery = function(c)
	bladeSign(c, -c.W / 2 + 1.6, c.G + 1.5, "🥖", rgb(120, 40, 50), rgb(250, 236, 206))
end
EXTRAS.Library = function(c)
	-- portique : 4 colonnes, entablement, fronton
	local z = c.FZ - 3.2
	for i = 0, 3 do
		local x = -7.5 + i * 5
		Column(c.M, "Column", c.F, x, z, 0.3, c.G - 0.4, 1.4, c.Trim, M.Marble, true)
		Box(c.M, "Capital", c.F, x - 1, x + 1, c.G - 0.4, c.G, z - 1, z + 1, c.Trim, M.Marble)
	end
	Box(c.M, "Entablature", c.F, -9.5, 9.5, c.G, c.G + 1.8, z - 1.3, c.FZ, c.Trim, M.Marble)
	-- fronton : deux coins (triangle dans le plan de la façade), le haut au milieu
	local pz = (z - 1.3 + c.FZ) / 2
	local pd = c.FZ - (z - 1.3)
	Wedge(c.M, "Pediment", Vector3.new(pd, 4.5, 9.5), c.F * CFrame.new(-4.75, c.G + 1.8 + 2.25, pz) * CFrame.Angles(0, math.pi / 2, 0), c.Trim, M.Marble)
	Wedge(c.M, "Pediment", Vector3.new(pd, 4.5, 9.5), c.F * CFrame.new(4.75, c.G + 1.8 + 2.25, pz) * CFrame.Angles(0, -math.pi / 2, 0), c.Trim, M.Marble)
	Box(c.M, "Podium", c.F, -9.8, 9.8, -0.1, 0.3, z - 1.6, c.FZ, STONE, M.Marble, true)
	for _, x in ipairs({ -11.5, 11.5 }) do
		CityKit.Lantern(c.M, c.F * CFrame.new(x, 0, c.FZ - 2.5), 9)
	end
end
EXTRAS.School = function(c)
	-- pignon central avec horloge (vraie horloge : TownDisplays), mât et drapeau, marelle
	local z = c.FZ
	Box(c.M, "Gable", c.F, -5, 5, c.H + 0.7, c.H + 6, z - 0.4, z + 0.6, c.Wall, c.Spec.Mat)
	Box(c.M, "GableCap", c.F, -5.4, 5.4, c.H + 6, c.H + 6.5, z - 0.6, z + 0.8, c.Trim, M.Concrete)
	local clock = Box(c.M, "SchoolClock", c.F, -2, 2, c.H + 1.2, c.H + 5.2, z - 0.5, z - 0.4, WHITE, M.SmoothPlastic)
	clock:SetAttribute("TownClock", "Wall")
	Column(c.M, "FlagPole", c.F, c.W / 2 + 1.5, z - 2, 0, 16, 0.25, rgb(200, 204, 210), M.Metal, true)
	Box(c.M, "Flag", c.F, c.W / 2 + 1.6, c.W / 2 + 4.6, 13.4, 15.6, z - 2.05, z - 1.95, rgb(60, 120, 220), M.Fabric)
	-- marelle peinte devant l'école
	for k = 0, 5 do
		local x = -c.W / 2 + 4 + (k % 2) * 1.6
		Box(c.M, "Hopscotch", c.F, x - 0.7, x + 0.7, 0.02, 0.06, z - 2.6 - k * 1.5, z - 1.2 - k * 1.5, ({ rgb(255, 120, 140), rgb(120, 200, 255), rgb(250, 220, 90) })[k % 3 + 1], M.SmoothPlastic)
	end
end
EXTRAS.Police = function(c)
	Box(c.M, "BlueBand", c.F, -c.W / 2 - 0.1, c.W / 2 + 0.1, c.G + 0.5, c.G + 1.2, c.FZ - 0.12, c.FZ, rgb(30, 60, 140), M.SmoothPlastic)
	local x = 4.2
	Box(c.M, "LampArm", c.F, x - 0.1, x + 0.1, 9.8, 10.0, c.FZ - 1.2, c.FZ, IRON, M.Metal)
	Glow(Box(c.M, "BlueLamp", c.F, x - 0.55, x + 0.55, 8.8, 9.9, c.FZ - 1.75, c.FZ - 0.65, rgb(60, 110, 255), M.Glass))
	for k = 0, 3 do
		local bx = -c.W / 2 + 2 + k * 2.4
		Column(c.M, "Bollard", c.F, bx, c.FZ - 2.4, 0, 2.6, 0.5, k % 2 == 0 and WHITE or rgb(30, 60, 140), M.Metal, true)
	end
end
EXTRAS.Fire = function(c)
	-- tour de séchage des tuyaux (côté droit, au-dessus du toit)
	local x0, x1 = c.W / 2 - 6.5, c.W / 2 - 0.5
	Box(c.M, "HoseTower", c.F, x0, x1, c.H, c.H + 14, -c.D / 2, -c.D / 2 + 6, c.Wall, c.Spec.Mat)
	Box(c.M, "TowerCap", c.F, x0 - 0.4, x1 + 0.4, c.H + 14, c.H + 14.8, -c.D / 2 - 0.4, -c.D / 2 + 6.4, c.Trim, M.Concrete)
	for k = 0, 1 do
		Box(c.M, "TowerWindow", c.F, x0 + 2, x1 - 2, c.H + 4 + k * 5, c.H + 7 + k * 5, -c.D / 2 - 0.08, -c.D / 2, GLASS, M.Glass)
	end
	Glow(CityKit.Ball(c.M, "Siren", (c.F * CFrame.new((x0 + x1) / 2, c.H + 15.4, -c.D / 2 + 3)).Position, 1.2, rgb(255, 60, 50), M.Glass))
	-- traits rouges sur le seuil
	Box(c.M, "BayLine", c.F, -c.W / 2 + 1.2, -c.W / 2 + 22, 0.02, 0.06, c.FZ - 5, c.FZ - 4.6, rgb(220, 50, 50), M.SmoothPlastic)
end
EXTRAS.Clinic = function(c)
	-- auvent sur 2 poteaux + croix rouge
	Box(c.M, "Canopy", c.F, -4.5, 4.5, 10.4, 10.9, c.FZ - 5, c.FZ, WHITE, M.SmoothPlastic)
	for _, x in ipairs({ -4, 4 }) do
		Column(c.M, "CanopyPost", c.F, x, c.FZ - 4.5, 0, 10.4, 0.35, rgb(200, 204, 210), M.Metal, true)
	end
	local R = c.F * CFrame.new(0, c.H - 3, c.FZ - 0.3)
	Glow(Box(c.M, "CrossV", R, -0.6, 0.6, -1.8, 1.8, -0.2, 0, rgb(230, 50, 60), M.SmoothPlastic))
	Glow(Box(c.M, "CrossH", R, -1.8, 1.8, -0.6, 0.6, -0.25, -0.02, rgb(230, 50, 60), M.SmoothPlastic))
end
EXTRAS.Post = function(c)
	Box(c.M, "YellowBand", c.F, -c.W / 2 - 0.1, c.W / 2 + 0.1, c.G + 0.5, c.G + 1.1, c.FZ - 0.12, c.FZ, rgb(250, 196, 30), M.SmoothPlastic)
	local x = c.DoorX > 0 and -c.W / 4 or c.W / 4
	Box(c.M, "MailboxBody", c.F, x - 0.8, x + 0.8, 3.0, 5.2, c.FZ - 1.0, c.FZ, rgb(250, 196, 30), M.Metal, true)
	Box(c.M, "MailboxSlot", c.F, x - 0.5, x + 0.5, 4.6, 4.75, c.FZ - 1.02, c.FZ - 0.98, INK, M.SmoothPlastic)
	Column(c.M, "MailboxPost", c.F, x, c.FZ - 0.5, 0, 3.0, 0.35, IRON, M.Metal)
end
EXTRAS.Gym = function(c)
	local t = Box(c.M, "GymSign", c.F, -6, 6, c.H - 4, c.H - 0.6, c.FZ - 0.3, c.FZ - 0.05, INK, M.SmoothPlastic)
	Glow(t)
	Text(t, Enum.NormalId.Front, "💪 " .. Locale.T("GYM"), rgb(255, 140, 60), INK, Enum.Font.GothamBlack, 160, 24)
end
EXTRAS.Hotel = function(c)
	-- balcons (3 par étage), marquise, drapeaux, enseigne du toit
	for f = 1, c.Floors - 1 do
		local yb = c.G + (f - 1) * STOREY
		for _, x in ipairs({ -c.W / 3, 0, c.W / 3 }) do
			Box(c.M, "Balcony", c.F, x - 2.4, x + 2.4, yb + 1.6, yb + 2.0, c.FZ - 2.2, c.FZ, c.Trim:Lerp(WHITE, 0.4), M.Marble)
			local g = Box(c.M, "BalconyGlass", c.F, x - 2.35, x + 2.35, yb + 2.0, yb + 5.5, c.FZ - 2.2, c.FZ - 2.1, GLASS, M.Glass)
			g.Transparency = 0.5
			Box(c.M, "BalconyRail", c.F, x - 2.4, x + 2.4, yb + 5.5, yb + 5.7, c.FZ - 2.25, c.FZ - 2.05, GOLD, M.Metal)
		end
	end
	Box(c.M, "Marquee", c.F, -5, 5, 10.2, 10.8, c.FZ - 5.5, c.FZ, INK, M.Metal)
	Box(c.M, "MarqueeTrim", c.F, -5.05, 5.05, 9.9, 10.2, c.FZ - 5.55, c.FZ - 5.4, GOLD, M.Metal)
	for _, x in ipairs({ -4.6, 4.6 }) do
		Column(c.M, "MarqueePost", c.F, x, c.FZ - 5.1, 0, 9.9, 0.3, GOLD, M.Metal, true)
	end
	Box(c.M, "Carpet", c.F, -2.4, 2.4, 0.02, 0.07, c.FZ - 5.5, c.FZ, rgb(150, 30, 46), M.Fabric)
	local s = Box(c.M, "RoofSign", c.F, -7, 7, c.H + 7.5, c.H + 10.5, -0.2, 0.2, INK, M.SmoothPlastic)
	Glow(s)
	Text(s, Enum.NormalId.Front, "🏨 " .. Locale.T("HOTEL") .. " ★★★", GOLD, INK, Enum.Font.GothamBlack, 400, 16)
	for _, x in ipairs({ -5, 5 }) do
		Column(c.M, "SignLeg", c.F, x, 0, c.H + 0.7, c.H + 7.5, 0.3, IRON, M.Metal)
	end
end
EXTRAS.Museum = function(c)
	local z = c.FZ - 3.6
	for i = 0, 5 do
		local x = -12.5 + i * 5
		Column(c.M, "Column", c.F, x, z, 0.4, c.G - 0.5, 1.5, c.Trim, M.Marble, true)
	end
	Box(c.M, "Entablature", c.F, -14.2, 14.2, c.G - 0.5, c.G + 1.6, z - 1.2, c.FZ, c.Trim, M.Marble)
	Box(c.M, "Stylobate", c.F, -14.5, 14.5, -0.1, 0.4, z - 1.6, c.FZ, STONE, M.Marble, true)
	for _, x in ipairs({ -9, 9 }) do
		local b = Box(c.M, "Banner", c.F, x - 1.2, x + 1.2, 3, 9.5, z + 0.9, z + 1.0, x < 0 and rgb(150, 30, 46) or rgb(30, 60, 120), M.Fabric)
		Text(b, Enum.NormalId.Front, x < 0 and "🦖" or "🖼️", WHITE, nil, Enum.Font.GothamBlack, 100, 12)
	end
end
EXTRAS.Cinema = function(c)
	-- marquise à ampoules + enseigne verticale
	Box(c.M, "Marquee", c.F, -c.W / 2 + 2, c.W / 2 - 2, c.G - 1.4, c.G + 0.6, c.FZ - 4.5, c.FZ, INK, M.Metal)
	local bulbs = Box(c.M, "MarqueeBulbs", c.F, -c.W / 2 + 2.1, c.W / 2 - 2.1, c.G - 1.3, c.G + 0.5, c.FZ - 4.56, c.FZ - 4.5, rgb(255, 230, 150), M.SmoothPlastic)
	Glow(bulbs)
	Text(bulbs, Enum.NormalId.Front, "🎬 " .. Locale.T("NOW SHOWING") .. " · 🦖 · 🚀 · 👻", INK, rgb(255, 230, 150), Enum.Font.GothamBlack, 120, 20)
	local V = c.F * CFrame.new(-c.W / 2 + 1.2, c.G + 6, c.FZ - 1.4)
	local v = Box(c.M, "VerticalSign", V, -0.3, 0.3, -5, 5, -1.3, 1.3, rgb(200, 40, 60), M.SmoothPlastic)
	Glow(v)
	local letters = {}
	for _, code in utf8.codes(Locale.T("CINEMA")) do
		table.insert(letters, utf8.char(code))
	end
	local word = table.concat(letters, "\n")
	Text(v, Enum.NormalId.Left, word, rgb(255, 230, 150), rgb(200, 40, 60), Enum.Font.GothamBlack, 120, 20)
	Text(v, Enum.NormalId.Right, word, rgb(255, 230, 150), rgb(200, 40, 60), Enum.Font.GothamBlack, 120, 20)
end
EXTRAS.Garage = function(c)
	for k = 0, 3 do
		Part(c.M, "Tire", Vector3.new(0.9, 2.6, 2.6), c.F * CFrame.new(c.W / 2 - 2, 0.5 + k * 0.92, c.FZ - 2.2) * CityKit.UPRIGHT, INK, M.Rubber, "Cyl")
	end
	Box(c.M, "OilSign", c.F, -c.W / 2 + 1, -c.W / 2 + 3.4, 3, 5.4, c.FZ - 0.1, c.FZ - 0.02, rgb(230, 120, 30), M.Metal)
end
EXTRAS.Cafe = function(c)
	-- deux tables de terrasse contre la façade
	for _, x in ipairs({ -c.W / 4, c.W / 4 }) do
		if math.abs(x - c.DoorX) > 4 then
			local T = c.F * CFrame.new(x, 0, c.FZ - 2.2)
			Column(c.M, "TableLeg", T, 0, 0, 0, 2.98, 0.2, IRON, M.Metal)
			Column(c.M, "TableTop", T, 0, 0, 2.98, 3.1, 2.0, WHITE, M.Marble, true)
			for _, sx in ipairs({ -1, 1 }) do
				Box(c.M, "ChairSeat", T, sx * 1.6 - 0.7, sx * 1.6 + 0.7, 1.68, 1.85, -0.7, 0.7, rgb(170, 60, 50), M.Wood)
				Box(c.M, "ChairLeg", T, sx * 1.6 - 0.06, sx * 1.6 + 0.06, 0, 1.68, -0.06, 0.06, IRON, M.Metal)
			end
		end
	end
end

----------------------------------------------------------------------
-- Église (forme à part : nef + clocher)
----------------------------------------------------------------------

local function church(c: Ctx)
	local W, D = c.W, c.D
	local hw, hd = W / 2, D / 2
	local tw = 6 -- clocher carré (devant, au centre)
	local nave = { -hw, hw }
	c.FZ = -hd + tw -- façade de la nef, contre le dos du clocher
	c.G = 16
	c.H = 16
	-- nef : murs (fenêtres hautes en ogive peintes), toit à forte pente
	local G = c.G
	local fz = c.FZ
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = sx * hw, sx * (hw - WALL)
		Box(c.M, "Wall", c.F, math.min(a, b), math.max(a, b), 0, G, fz, hd - WALL, c.Wall, c.Spec.Mat, true)
		local skin = Box(c.M, "FaceSkin", c.F * CFrame.new(sx * hw, 0, (fz + hd) / 2) * CFrame.Angles(0, sx * -math.pi / 2, 0), -(hd - fz) / 2 + 0.3, (hd - fz) / 2 - 0.3, 3, G - 2, -0.06, -0.01, c.Wall, c.Spec.Mat)
		local gui = CityKit.Canvas(skin, Enum.NormalId.Front, 300, 3)
		for k = 0, 2 do
			local x = (k + 0.5) / 3
			CityKit.Blob(gui, x, 0.5, 0.1, 0.7, rgb(90, 120, 200), 0.45)
		end
	end
	Box(c.M, "Wall", c.F, -hw, hw, 0, G, hd - WALL, hd, c.Wall, c.Spec.Mat, true)
	local info = CityInteriors.Info("Church")
	Box(c.M, "InFloor", c.F, -hw + WALL, hw - WALL, FLOOR - 0.45, FLOOR, fz + WALL, hd - WALL, info.Floor, info.FloorMat, true)
	Box(c.M, "InCeiling", c.F, -hw + WALL, hw - WALL, G - 0.3, G - 0.04, fz + WALL, hd - WALL, rgb(236, 230, 214), M.Wood)
	-- façade de la nef (porte dans le clocher) : mur percé
	CityKit.WallWithHoles(c.M, "Front", c.F, -hw, hw, 0, G, fz, fz + WALL, { { -2.6, 2.6, FLOOR, 10 } }, c.Wall, c.Spec.Mat, true)
	-- toit en bâtière (pente raide)
	local h = 10
	local len = math.sqrt(hw * hw + h * h)
	local a = math.atan2(h, hw)
	local mid = (fz + hd) / 2
	local L = hd - fz
	-- (pignons : le haut au faîtage, x = 0)
	Wedge(c.M, "Gable", Vector3.new(L, h, hw), c.F * CFrame.new(-hw / 2, G + h / 2, mid) * CFrame.Angles(0, math.pi / 2, 0), c.Wall, c.Spec.Mat)
	Wedge(c.M, "Gable", Vector3.new(L, h, hw), c.F * CFrame.new(hw / 2, G + h / 2, mid) * CFrame.Angles(0, -math.pi / 2, 0), c.Wall, c.Spec.Mat)
	for _, s in ipairs({ -1, 1 }) do
		local cf = c.F * CFrame.new(s * hw / 2, G + h / 2, mid) * CFrame.Angles(0, 0, -s * a) * CFrame.new(0, 0.25, 0)
		Part(c.M, "RoofPlane", Vector3.new(len + 0.9, 0.35, L + 1), cf, c.Roof, M.Slate)
	end
	-- clocher : base percée (porte), étages, abat-sons, flèche
	local tz0, tz1 = -hd, fz
	local tx0, tx1 = -tw / 2, tw / 2
	CityKit.WallWithHoles(c.M, "Tower", c.F, tx0, tx1, 0, G + 4, tz0, tz0 + WALL, { { -2.4, 2.4, FLOOR, 10 } }, c.Wall, c.Spec.Mat, true)
	for _, sx in ipairs({ -1, 1 }) do
		local a2, b2 = sx * tw / 2, sx * (tw / 2 - WALL)
		Box(c.M, "Tower", c.F, math.min(a2, b2), math.max(a2, b2), 0, G + 14, tz0 + WALL, tz1, c.Wall, c.Spec.Mat, true)
	end
	Box(c.M, "TowerUpper", c.F, tx0, tx1, G + 4, G + 14, tz0, tz0 + WALL, c.Wall, c.Spec.Mat)
	Box(c.M, "TowerBack", c.F, tx0 + WALL, tx1 - WALL, G, G + 14, tz1 - WALL, tz1, c.Wall, c.Spec.Mat)
	Box(c.M, "TowerFloor", c.F, tx0 + WALL, tx1 - WALL, FLOOR - 0.45, FLOOR, tz0 + WALL, tz1, info.Floor, info.FloorMat, true)
	Box(c.M, "TowerCeiling", c.F, tx0 + WALL, tx1 - WALL, 11.5, 11.9, tz0 + WALL, tz1, c.Wall, c.Spec.Mat)
	-- abat-sons + horloge
	for k = 0, 3 do
		local R = c.F * CFrame.new(0, 0, (tz0 + tz1) / 2) * CFrame.Angles(0, k * math.pi / 2, 0)
		Box(c.M, "Louvre", R, -1.4, 1.4, G + 9, G + 12.5, -tw / 2 - 0.12, -tw / 2 - 0.02, rgb(70, 60, 50), M.WoodPlanks)
	end
	local clk = Box(c.M, "ChurchClock", c.F, -1.8, 1.8, G + 4.6, G + 8.2, tz0 - 0.1, tz0 - 0.02, WHITE, M.SmoothPlastic)
	clk:SetAttribute("TownClock", "Tower")
	Box(c.M, "TowerCornice", c.F, tx0 - 0.4, tx1 + 0.4, G + 14, G + 14.6, tz0 - 0.4, tz1 + 0.4, c.Trim, M.Concrete)
	for r = 0, 1 do
		local rot = CFrame.Angles(0, r * math.pi / 2, 0)
		local T = c.F * CFrame.new(0, G + 14.6 + 6, (tz0 + tz1) / 2) * rot
		Wedge(c.M, "Spire", Vector3.new(tw, 12, tw / 2), T * CFrame.new(0, 0, -tw / 4), c.Roof, M.Slate)
		Wedge(c.M, "Spire", Vector3.new(tw, 12, tw / 2), T * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -tw / 4), c.Roof, M.Slate)
	end
	CityKit.Ball(c.M, "SpireBall", (c.F * CFrame.new(0, G + 27, (tz0 + tz1) / 2)).Position, 0.8, GOLD, M.Metal)
	-- rosace sur la façade de la nef (de part et d'autre du clocher)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (tw / 2 + (hw - tw / 2) / 2)
		local rose = Part(c.M, "RoseWindow", Vector3.new(0.12, 3.2, 3.2), c.F * CFrame.new(x, G - 5, fz - 0.06) * CFrame.Angles(0, math.pi / 2, 0), rgb(110, 140, 220), M.Glass, "Cyl")
		Glow(rose)
	end
	-- porte de bois ouverte + intérieur
	for _, sx in ipairs({ -1, 1 }) do
		local Hn = c.F * CFrame.new(sx * 2.4, 0, tz0 + WALL + 0.1) * CFrame.Angles(0, sx < 0 and math.rad(-100) or math.rad(100), 0)
		Box(c.M, "DoorLeaf", Hn, sx < 0 and 0 or -2.3, sx < 0 and 2.3 or 0, FLOOR, 9.9, -0.1, 0.1, rgb(110, 70, 46), M.Wood)
	end
	c.DoorX = 0
	pcall(CityInteriors.Furnish, c.M, c.F * CFrame.new(0, FLOOR, fz), W - 0.1, hd - fz - 0.05, G - FLOOR, "Church", c.Seed, { DoorX = 0, MaxNpc = 2 })
	CityInteriors.Lamps(c.M, c.F * CFrame.new(0, FLOOR, fz), W - 1, hd - fz - 0.5, G - FLOOR, "Church")
	local _ = nave
end

----------------------------------------------------------------------
-- Fabrique d'un type
----------------------------------------------------------------------

local function build(typ: string, m: Model, F: CFrame, seed: number)
	local spec = CityBuildings.TYPES[typ]
	if not spec then
		return
	end
	local floors = spec.Floors[1] + math.floor(hash(seed, 1) * (spec.Floors[2] - spec.Floors[1] + 1))
	floors = math.clamp(floors, spec.Floors[1], spec.Floors[2])
	local G = spec.Ground or GROUND
	local kind = spec.Kind or CityInteriors.STREET_SHOPS[math.floor(hash(seed, 2) * #CityInteriors.STREET_SHOPS) + 1]
	local c: Ctx = {
		M = m,
		F = F,
		Spec = spec,
		Seed = seed,
		W = spec.W,
		D = spec.D,
		G = G,
		H = G + (floors - 1) * STOREY,
		Floors = floors,
		Wall = Pick(spec.Walls, seed, 3),
		Trim = spec.Trim,
		Roof = Pick(spec.RoofColors or { rgb(96, 98, 106) }, seed, 4),
		Kind = kind,
		Sign = spec.Sign or CityInteriors.Info(kind).Name,
		FZ = -spec.D / 2,
		DoorX = 0,
	}
	if spec.Front == "Custom" then
		church(c)
		return
	end
	c.Podium = typ == "Library" or typ == "Museum"
	groundShell(c)
	if spec.Front == "Shop" then
		shopFront(c, (typ == "Cafe" or typ == "Restaurant" or typ == "Bakery" or typ == "Shop") and CityInteriors.Info(kind).Sign or nil)
	elseif spec.Front == "Glass" then
		glassFront(c)
	elseif spec.Front == "Grand" then
		grandFront(c)
	elseif spec.Front == "Garage" then
		garageFront(c, typ == "Fire" and 2 or 1)
	end
	upper(c, typ == "Office" and math.floor(c.W / 3.2) or nil)
	roof(c)
	local extra = EXTRAS[typ]
	if extra then
		local ok, err = pcall(extra, c)
		if not ok then
			warn("[CityBuildings] " .. typ .. " : " .. tostring(err))
		end
	end
	furnish(c)
end

-- silhouette de loin : volume + toit + (clocher / dôme)
local function impostor(typ: string, m: Model, F: CFrame, seed: number)
	local spec = CityBuildings.TYPES[typ]
	if not spec then
		return
	end
	local floors = spec.Floors[1] + math.floor(hash(seed, 1) * (spec.Floors[2] - spec.Floors[1] + 1))
	local G = spec.Ground or GROUND
	local H = typ == "Church" and 16 or G + (math.clamp(floors, spec.Floors[1], spec.Floors[2]) - 1) * STOREY
	local wall = Pick(spec.Walls, seed, 3)
	local roofC = Pick(spec.RoofColors or { rgb(96, 98, 106) }, seed, 4)
	Box(m, "ImpBlock", F, -spec.W / 2, spec.W / 2, 0, H, -spec.D / 2, spec.D / 2, wall, spec.Mat)
	Box(m, "ImpRoof", F, -spec.W / 2 - 0.3, spec.W / 2 + 0.3, H, H + 1.2, -spec.D / 2 - 0.3, spec.D / 2 + 0.3, roofC, M.Slate)
	if typ == "Church" then
		Box(m, "ImpTower", F, -3.5, 3.5, 0, 30, -spec.D / 2, -spec.D / 2 + 7, wall, spec.Mat)
	elseif typ == "Museum" then
		Egg(m, "ImpDome", F * CFrame.new(0, H + 4, 0), Vector3.new(12, 10, 12), roofC, M.Metal)
	elseif typ == "Fire" then
		Box(m, "ImpTower", F, spec.W / 2 - 6.5, spec.W / 2 - 0.5, H, H + 14, -spec.D / 2, -spec.D / 2 + 6, wall, spec.Mat)
	end
end

CityBuildings.BUILDERS = {}
CityBuildings.IMPOSTORS = {}
CityBuildings.FOOT = {}
CityBuildings.BIG = {}
CityBuildings.NEAR = {}
for typ, spec in pairs(CityBuildings.TYPES) do
	local key = "Bld" .. typ
	CityBuildings.BUILDERS[key] = function(m: Model, F: CFrame, seed: number)
		build(typ, m, F, seed)
	end
	CityBuildings.IMPOSTORS[key] = function(m: Model, F: CFrame, seed: number)
		impostor(typ, m, F, seed)
	end
	CityBuildings.FOOT[key] = Vector2.new(spec.W + (typ == "Library" and 0 or 0), spec.D + ((typ == "Library" or typ == "Museum" or typ == "Clinic" or typ == "Hotel" or typ == "Cinema") and 6 or 2))
	CityBuildings.BIG[key] = true
	CityBuildings.NEAR[key] = 150
end

return CityBuildings
