--[[
	TownFacades (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownFacades

	🏘️ Dopamine Town (v9.7, BUILDINGS97) : le DÉTAIL des immeubles de rue où
	l'on n'entre pas, construit côté client et en flux autour de l'avatar.
	Le serveur (TownBuildings.RowHouse) ne pose que la coque (volume, socle,
	corniche, toit, cheminées) et des bandeaux vitrés "FarLOD" pour la vue de
	loin ; ici, près de l'avatar (≤ 200 studs, gardé jusqu'à 260) :
	  - FAÇADE sur rue, selon le style (attribut FacadeStyle) :
	      Haussmann : pierre, bandeaux, hautes fenêtres à balconnets en fer,
	                  grand balcon filant, lucarnes dans le toit en zinc ;
	      Brick     : briques, linteaux et appuis blancs, fenêtres à
	                  guillotine, gouttières ;
	      Pastel    : enduit pastel, volets ouverts, jardinières fleuries,
	                  petit balcon sous le pignon, œil-de-bœuf ;
	      Modern    : mur-rideau vitré, ailettes, dalles blanches,
	                  garde-corps en verre ;
	      Timber    : colombages (poteaux, sablières, croix de Saint-André) ;
	  - REZ-DE-CHAUSSÉE : soit une BOUTIQUE FERMÉE (devanture en bois peint,
	    enseigne, vitrine sombre aux stores à demi baissés, petite vitrine
	    d'objets, store banne ROULÉ, porte vitrée avec pancarte "Fermé pour
	    le moment", marche), soit une ENTRÉE d'immeuble (porte à imposte,
	    encadrement, perron, lanterne éteinte) ; jamais de lumière allumée ;
	  - ARRIÈRE fini (côté parc) : fenêtres encadrées, porte de service et
	    son perron, petit balcon, bac de fleurs, climatiseur, descente d'eau ;
	  - CÔTÉS EXPOSÉS (bout de rangée, vus depuis le boulevard ou la place) :
	    fenêtres, réclame peinte sur le mur, œil-de-bœuf dans le pignon.
	Les bandeaux "FarLOD" du serveur sont masqués LOCALEMENT
	(LocalTransparencyModifier) tant que le détail est construit.
	Aucune face confondue avec la coque (décalages ≥ 0,03 stud) ; tout est
	ancré, sans collision (sauf marches), sans ombre pour les petites pièces.

	API (TownClient, via optionalModule) :
	  TownFacades.Start()            à l'entrée en ville
	  TownFacades.Step(position)     position de l'avatar (facultatif)
	  TownFacades.Stop()             à la sortie (tout est détruit)
	  TownFacades.Debug() -> table   (tests / rendus)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage.Shared.Locale)

local TownFacades = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

local FOLDER_NAME = "TownFacadeDetail"
local BUILD_RANGE, DROP_RANGE = 200, 260
local STEP_EVERY = 0.5
local STEP_BUDGET = 0.003 -- (s) de construction par image
local SIGN_DISTANCE = 90
local PLAQUE_DISTANCE = 30

local GLASS = rgb(74, 96, 124)
local GLASS_SHOP = rgb(96, 110, 128)
local INTERIOR = rgb(150, 128, 118) -- (boutique éteinte, mais on voit le fond : pas un trou noir)
local IRON = rgb(40, 42, 52)

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

local count = 0

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	count += 1
	return p
end

-- Boîte entre deux coins dans le repère F
local function box(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return newPart(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, solid)
end

-- Cylindre d'axe X (F) entre x0 et x1
local function rodX(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(parent, name, Vector3.new(math.abs(x1 - x0), diameter, diameter), F * CFrame.new((x0 + x1) / 2, y, z), color, material)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Cylindre vertical (F)
local function rodY(parent: Instance, name: string, F: CFrame, x: number, y0: number, y1: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(parent, name, Vector3.new(math.abs(y1 - y0), diameter, diameter), F * CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, F: CFrame, x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(parent, name, Vector3.new(diameter, diameter, diameter), F * CFrame.new(x, y, z), color, material)
	;(p :: Part).Shape = Enum.PartType.Ball
	return p
end

-- Panneau texte (SurfaceGui sur la face avant = -Z du panneau)
local function signText(board: BasePart, text: string, color: Color3, pps: number, maxDistance: number, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.6
	gui.MaxDistance = maxDistance
	gui.Parent = board
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(0.05, 0.1)
	l.Size = UDim2.fromScale(0.9, 0.8)
	l.Font = font or Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color
	l.Parent = gui
end

local function hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

-- Enseignes des boutiques fermées (clés anglaises, traduites)
local SHOP_NAMES = {
	"💐 Florist", "📖 Bookshop", "🥖 Bakery", "💊 Pharmacy", "✂️ Hair Salon", "🍫 Chocolatier", "🧀 Cheese Shop", "✏️ Stationery",
	"👓 Optician", "🚲 Bike Repair", "🍵 Tea Room", "🧺 Laundromat", "🎩 Hat Shop", "🍯 Fine Grocery", "🧶 Haberdashery", "🕰️ Watchmaker",
}
-- Réclames peintes sur les pignons
local MURALS = { "🥤 Dopamine Soda", "🍬 Candy Pop since 1998", "🧠 Think happy!", "☕ Mochi Café, 2nd street" }
local FLOWERS = { rgb(255, 110, 160), rgb(255, 214, 96), rgb(186, 140, 255), rgb(255, 150, 110), rgb(255, 255, 255) }

type Building = {
	Model: Model,
	Style: string,
	CF: CFrame, -- pied de la façade (milieu), LookVector vers la rue
	W: number,
	D: number,
	Floors: number,
	Height: number,
	Seed: number,
	GroundH: number,
	FloorH: number,
	Wall: Color3,
	Trim: Color3,
	Accent: Color3,
	Detail: Color3,
	Left: boolean, -- côté gauche (x < 0) exposé
	Right: boolean,
	LeftAbove: number, -- (côté masqué par un voisin) hauteur au-dessus de laquelle il est à nu
	RightAbove: number,
	Center: Vector3,
	Far: { BasePart },
	Detail_: Model?,
	Jobs: { () -> () }?,
	JobIndex: number,
	Built: boolean,
	Parts: number,
}

local started = false
local buildings: { Building } = {}
local folder: Folder? = nil
local conns: { RBXScriptConnection } = {}
local clock = 0
local focus: Vector3? = nil
local stats = { Built = 0, Destroyed = 0, Parts = 0 }

----------------------------------------------------------------------
-- Fenêtres (repère F : face de la coque à z = 0, dehors vers -Z)
----------------------------------------------------------------------

-- Couches (z) : verre [-0.12, -0.04] ; stores [-0.2, -0.13] ; meneaux
-- [-0.24, -0.16] ; traverse [-0.28, -0.2] ; parement [-SKIN, 0] ; appuis, linteaux,
-- volets, balcons : devant le parement
local SKIN = 0.45

type WinOpts = { Sill: boolean?, Hood: boolean?, Mullion: boolean?, Transom: boolean?, Shutters: Color3?, Box: boolean?, Curtain: boolean?, Seed: number }

local function windowTrim(parent: Instance, F: CFrame, x: number, y0: number, y1: number, ww: number, trim: Color3, opts: WinOpts)
	local hw = ww / 2
	local front = -SKIN
	if opts.Mullion then
		box(parent, "Mullion", F, x - 0.09, x + 0.09, y0, y1, -0.24, -0.16, trim, M.SmoothPlastic)
	end
	if opts.Transom then
		local ty = y0 + (y1 - y0) * 0.66
		box(parent, "Transom", F, x - hw, x + hw, ty - 0.09, ty + 0.09, -0.28, -0.2, trim, M.SmoothPlastic)
	end
	local r = hash(opts.Seed, 7)
	if opts.Curtain and r < 0.45 then
		-- store intérieur à demi baissé (pas de lumière derrière)
		local c = r < 0.2 and rgb(246, 236, 220) or rgb(236, 206, 214)
		box(parent, "Blind", F, x - hw + 0.05, x + hw - 0.05, y1 - (y1 - y0) * (0.3 + r), y1, -0.2, -0.13, c, M.Fabric)
	end
	if opts.Sill ~= false then
		box(parent, "Sill", F, x - hw - 0.35, x + hw + 0.35, y0 - 0.32, y0 + 0.03, front - 0.42, front, trim, M.Concrete)
	end
	if opts.Hood then
		box(parent, "Lintel", F, x - hw - 0.3, x + hw + 0.3, y1 + 0.05, y1 + 0.5, front - 0.3, front, trim, M.Concrete)
	end
	if opts.Shutters then
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = x + sx * (hw + 0.08)
			local x1 = x + sx * (hw + 0.08 + hw * 0.92)
			box(parent, "Shutter", F, math.min(x0, x1), math.max(x0, x1), y0 + 0.05, y1 - 0.05, front - 0.16, front - 0.03, opts.Shutters, M.WoodPlanks)
		end
	end
	if opts.Box then
		box(parent, "FlowerBox", F, x - hw - 0.1, x + hw + 0.1, y0 - 0.95, y0 - 0.3, front - 0.95, front - 0.03, rgb(176, 124, 84), M.WoodPlanks)
		local color = FLOWERS[math.floor(hash(opts.Seed, 9) * #FLOWERS) + 1]
		for k = -1, 1 do
			ball(parent, "Blooms", F, x + k * hw * 0.62, y0 - 0.12, front - 0.5, 0.9, k == 0 and rgb(104, 172, 96) or color, M.Grass)
		end
	end
end

-- Un étage de fenêtres percées dans un parement (piédroits + allège + linteau)
-- `openings` : liste de { X, W } ; `yb` : bas de l'étage ; `y0`/`y1` : baie
local function skinFloor(parent: Instance, F: CFrame, w: number, yb: number, yt: number, y0: number, y1: number, openings: { { number } }, color: Color3, material: Enum.Material, glassBand: boolean)
	local hw = w / 2
	box(parent, "Spandrel", F, -hw, hw, yb, y0, -SKIN, 0, color, material)
	box(parent, "Header", F, -hw, hw, y1, yt, -SKIN, 0, color, material)
	local x = -hw
	for _, o in ipairs(openings) do
		local a = o[1] - o[2] / 2
		if a - x > 0.05 then
			box(parent, "Pier", F, x, a, y0, y1, -SKIN, 0, color, material)
		end
		x = o[1] + o[2] / 2
	end
	if hw - x > 0.05 then
		box(parent, "Pier", F, x, hw, y0, y1, -SKIN, 0, color, material)
	end
	if glassBand then
		local g = box(parent, "Glass", F, -hw + 0.3, hw - 0.3, y0, y1, -0.12, -0.04, GLASS, M.Glass)
		g.Reflectance = 0.18
	end
end

local function windowXs(w: number, n: number): { number }
	local xs = {}
	for i = 1, n do
		xs[i] = -w / 2 + (i - 0.5) * w / n
	end
	return xs
end

----------------------------------------------------------------------
-- Rez-de-chaussée
----------------------------------------------------------------------

-- Boutique fermée : devanture en bois peint, vitrine sombre, store roulé,
-- porte vitrée et pancarte "Fermé"
local function shopFront(b: Building, parent: Instance, F: CFrame)
	local w, G = b.W, b.GroundH
	local hw = w / 2
	local accent = b.Accent
	local dark = accent:Lerp(Color3.new(0, 0, 0), 0.35)
	local seed = b.Seed
	local doorRight = hash(seed, 21) < 0.5
	local dx = (doorRight and 1 or -1) * (hw - 3.6)
	local dw = 2.8
	local base = 0 -- (pied des piliers : sur le trottoir, devant le socle)
	local top = G - 2.6 -- haut de la vitrine (bas du bandeau)
	-- piliers + bandeau d'enseigne
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "Pilaster", F, sx < 0 and -hw or hw - 1.1, sx < 0 and -hw + 1.1 or hw, base, G - 0.3, -1.0, 0, accent, M.Wood)
		box(parent, "PilasterCap", F, sx < 0 and -hw - 0.05 or hw - 1.25, sx < 0 and -hw + 1.25 or hw + 0.05, G - 3.05, G - 2.75, -1.12, -1.0, dark, M.Wood)
	end
	local fascia = box(parent, "Fascia", F, -hw + 0.15, hw - 0.15, G - 2.6, G - 0.35, -1.25, 0, accent, M.Wood)
	local name = SHOP_NAMES[math.floor(hash(seed, 23) * #SHOP_NAMES) + 1]
	-- enseigne : planche claire posée sur le bandeau
	local board = box(parent, "SignBoard", F, -hw + 2.2, hw - 2.2, G - 2.35, G - 0.6, -1.33, -1.25, rgb(252, 246, 232), M.Wood)
	signText(board, Locale.T(name), dark, 28, SIGN_DISTANCE)
	local _ = fascia
	-- allège + vitrine (sombre : boutique éteinte) + fond
	local gx0, gx1 = -hw + 1.1, hw - 1.1
	local dx0, dx1 = dx - dw / 2 - 0.25, dx + dw / 2 + 0.25
	box(parent, "Stallriser", F, gx0, dx0, base, 2.4, -0.85, 0, dark, M.Wood)
	box(parent, "Stallriser", F, dx1, gx1, base, 2.4, -0.85, 0, dark, M.Wood)
	box(parent, "ShopInside", F, gx0, gx1, 2.4, top, -0.09, -0.03, INTERIOR, M.SmoothPlastic)
	for _, seg in ipairs({ { gx0, dx0 }, { dx1, gx1 } }) do
		local a, c = seg[1], seg[2]
		if c - a > 0.8 then
			local g = box(parent, "ShopGlass", F, a, c, 2.4, top, -0.72, -0.64, GLASS_SHOP, M.Glass)
			g.Transparency = 0.55
			g.Reflectance = 0.2
			-- stores intérieurs à demi baissés (fermé)
			box(parent, "ShopBlind", F, a + 0.1, c - 0.1, top - (top - 2.4) * (0.35 + hash(seed, 25 + a) * 0.2), top, -0.6, -0.54, rgb(238, 226, 210), M.Fabric)
			-- tablette de vitrine + 3 petits objets
			box(parent, "DisplayShelf", F, a + 0.1, c - 0.1, 2.4, 2.65, -0.52, -0.12, rgb(236, 226, 214), M.Wood)
			local n = math.max(1, math.floor((c - a) / 2.4))
			for k = 1, math.min(3, n) do
				local x = a + (k - 0.5) * (c - a) / math.min(3, n)
				local color = FLOWERS[(math.floor(hash(seed + k, 27) * #FLOWERS) + k) % #FLOWERS + 1]
				if k % 2 == 1 then
					box(parent, "GiftBox", F, x - 0.45, x + 0.45, 2.65, 3.45, -0.46, -0.16, color, M.SmoothPlastic)
				else
					local jar = newPart(parent, "Jar", Vector3.new(1.1, 0.5, 0.5), F * CFrame.new(x, 3.2, -0.31) * CFrame.Angles(0, 0, math.rad(90)), color:Lerp(WHITE, 0.3), M.Glass)
					;(jar :: Part).Shape = Enum.PartType.Cylinder
				end
			end
		end
	end
	-- montants de la porte, porte vitrée, imposte, poignée, pancarte
	for _, x in ipairs({ dx0, dx1 }) do
		box(parent, "DoorPost", F, x - 0.25, x + 0.25, base, top, -0.9, 0, dark, M.Wood)
	end
	box(parent, "DoorLeaf", F, dx - dw / 2, dx + dw / 2, 1.2, 6.3, -0.32, -0.12, accent, M.Wood)
	local dg = box(parent, "DoorGlass", F, dx - dw / 2 + 0.4, dx + dw / 2 - 0.4, 3.4, 5.9, -0.38, -0.33, GLASS_SHOP, M.Glass)
	dg.Reflectance = 0.2
	box(parent, "DoorHead", F, dx0 + 0.25, dx1 - 0.25, 6.3, 6.6, -0.6, -0.1, dark, M.Wood)
	local tg = box(parent, "Transom", F, dx - dw / 2, dx + dw / 2, 6.6, top, -0.4, -0.3, GLASS_SHOP, M.Glass)
	tg.Transparency = 0.3
	box(parent, "Handle", F, dx + (doorRight and -1 or 1) * (dw / 2 - 0.4) - 0.07, dx + (doorRight and -1 or 1) * (dw / 2 - 0.4) + 0.07, 3.2, 4.2, -0.5, -0.38, rgb(214, 180, 90), M.Metal)
	local plaque = box(parent, "ClosedSign", F, dx - 0.8, dx + 0.8, 4.5, 5.4, -0.44, -0.39, WHITE, M.SmoothPlastic)
	signText(plaque, Locale.T("Closed for now 😴"), rgb(200, 70, 100), 60, PLAQUE_DISTANCE, Enum.Font.GothamBold)
	-- store banne ROULÉ sous l'enseigne (boutique fermée)
	rodX(parent, "RolledAwning", F, -hw + 1.3, hw - 1.3, G - 2.95, -1.55, 0.7, hash(seed, 29) < 0.5 and accent:Lerp(WHITE, 0.35) or rgb(246, 240, 230), M.Fabric)
	-- marche devant la porte (sur le trottoir, devant le socle)
	box(parent, "Step", F, dx - dw / 2 - 0.4, dx + dw / 2 + 0.4, 0, 0.6, -1.6, -0.62, rgb(206, 200, 194), M.Concrete, true)
end

-- Entrée d'immeuble : porte à imposte, encadrement, perron, lanterne
local function homeFront(b: Building, parent: Instance, F: CFrame, color: Color3, material: Enum.Material, n: number)
	local w, G = b.W, b.GroundH
	local xs = windowXs(w, n)
	local door = (b.Seed % n) + 1
	local ww = b.Style == "Modern" and 3.4 or 2.6
	local dw = 2.8
	local openings = {}
	for i, x in ipairs(xs) do
		table.insert(openings, { x, i == door and dw or ww })
	end
	local y0, y1 = 3.4, 8
	-- parement du rez-de-chaussée (le bas de la porte est dégagé)
	local hw = w / 2
	local dxDoor = xs[door]
	box(parent, "Header", F, -hw, hw, y1, G, -SKIN, 0, color, material)
	local x = -hw
	for i, o in ipairs(openings) do
		local a = o[1] - o[2] / 2
		if a - x > 0.05 then
			box(parent, "Pier", F, x, a, 1.2, y1, -SKIN, 0, color, material)
		end
		if o[1] ~= dxDoor then
			box(parent, "Spandrel", F, a, o[1] + o[2] / 2, 1.2, y0, -SKIN, 0, color, material)
			local g = box(parent, "Glass", F, a, o[1] + o[2] / 2, y0, y1, -0.12, -0.04, GLASS, M.Glass)
			g.Reflectance = 0.18
			windowTrim(parent, F, o[1], y0, y1, o[2], b.Trim, { Sill = true, Hood = b.Style ~= "Modern", Mullion = b.Style ~= "Modern", Curtain = true, Seed = b.Seed + i })
		end
		x = o[1] + o[2] / 2
	end
	if hw - x > 0.05 then
		box(parent, "Pier", F, x, hw, 1.2, y1, -SKIN, 0, color, material)
	end
	-- porte (bois laqué), imposte vitrée, encadrement en saillie, heurtoir
	local dx = dxDoor
	local leaf = b.Style == "Modern" and rgb(70, 74, 88) or b.Accent
	box(parent, "DoorLeaf", F, dx - dw / 2, dx + dw / 2, 1.2, 6.9, -0.28, -0.08, leaf, M.Wood)
	box(parent, "DoorPanel", F, dx - dw / 2 + 0.35, dx + dw / 2 - 0.35, 2, 4.2, -0.34, -0.29, leaf:Lerp(Color3.new(0, 0, 0), 0.15), M.Wood)
	local fan = box(parent, "Fanlight", F, dx - dw / 2, dx + dw / 2, 6.9, y1, -0.16, -0.08, GLASS, M.Glass)
	fan.Reflectance = 0.2
	box(parent, "Knob", F, dx + dw / 2 - 0.55, dx + dw / 2 - 0.3, 3.9, 4.15, -0.42, -0.29, rgb(214, 180, 90), M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "DoorCase", F, dx + sx * (dw / 2) + (sx < 0 and -0.45 or 0), dx + sx * (dw / 2) + (sx < 0 and 0 or 0.45), 1.2, y1 + 0.1, -SKIN - 0.25, -SKIN, b.Trim, M.Concrete)
	end
	box(parent, "DoorHood", F, dx - dw / 2 - 0.8, dx + dw / 2 + 0.8, y1 + 0.1, y1 + 0.55, -SKIN - 0.9, -SKIN, b.Trim, M.Concrete)
	-- perron (2 marches) sur le trottoir
	box(parent, "Stoop", F, dx - dw / 2 - 0.5, dx + dw / 2 + 0.5, 0, 0.6, -2.4, -0.62, rgb(206, 200, 194), M.Concrete, true)
	box(parent, "Stoop", F, dx - dw / 2 - 0.5, dx + dw / 2 + 0.5, 0.6, 1.17, -1.5, -0.62, rgb(214, 208, 202), M.Concrete, true)
	-- lanterne éteinte + numéro
	local lx = dx + (dw / 2 + 1.1) * (door == n and -1 or 1)
	box(parent, "LanternArm", F, lx - 0.08, lx + 0.08, 6.6, 6.76, -1.05, -SKIN, IRON, M.Metal)
	box(parent, "Lantern", F, lx - 0.3, lx + 0.3, 5.7, 6.6, -1.2, -0.7, rgb(250, 236, 200), M.Glass)
	-- paillasson
	box(parent, "Doormat", F, dx - 0.9, dx + 0.9, 1.17, 1.21, -1.3, -0.8, rgb(150, 110, 80), M.Fabric)
end

-- Hall vitré (moderne)
local function lobbyFront(b: Building, parent: Instance, F: CFrame)
	local w, G = b.W, b.GroundH
	local hw = w / 2
	local frame = b.Trim
	local deep = 1.5
	box(parent, "LobbyHeader", F, -hw, hw, G - 1.2, G, -deep, 0, b.Wall, M.Concrete)
	box(parent, "LobbyFloor", F, -hw + 1, hw - 1, 0, 1.2, -deep, -0.6, rgb(214, 214, 220), M.Concrete, true)
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "LobbyPier", F, sx < 0 and -hw or hw - 1, sx < 0 and -hw + 1 or hw, 0, G - 1.2, -deep, 0, b.Wall, M.Concrete)
	end
	box(parent, "LobbyInside", F, -hw + 1, hw - 1, 1.2, G - 1.2, -0.09, -0.03, rgb(206, 204, 200), M.SmoothPlastic)
	local g = box(parent, "LobbyGlass", F, -hw + 1, hw - 1, 1.2, G - 1.2, -deep + 0.1, -deep + 0.18, GLASS_SHOP, M.Glass)
	g.Transparency = 0.45
	g.Reflectance = 0.25
	local nf = math.max(3, math.floor((w - 2) / 3.2))
	for i = 1, nf - 1 do
		local x = -hw + 1 + i * (w - 2) / nf
		box(parent, "LobbyFin", F, x - 0.08, x + 0.08, 1.2, G - 1.2, -deep - 0.12, -deep + 0.1, frame, M.Metal)
	end
	-- plantes dans le hall
	for _, x in ipairs({ -hw + 3, hw - 3 }) do
		box(parent, "Planter", F, x - 0.5, x + 0.5, 1.2, 2.4, -1.15, -0.25, rgb(236, 236, 240), M.SmoothPlastic)
		ball(parent, "Plant", F, x, 3, -0.7, 0.85, rgb(96, 170, 100), M.Grass)
	end
	box(parent, "Canopy", F, -hw + 3, hw - 3, G - 1.6, G - 1.3, -3.4, -deep, frame, M.Metal)
	box(parent, "Step", F, -2, 2, 0, 0.6, -2.5, -deep, rgb(214, 214, 220), M.Concrete, true)
	local plate = box(parent, "HouseNumber", F, hw - 3.2, hw - 1.4, G - 3.3, G - 2.3, -deep - 0.08, -deep, frame, M.Metal)
	signText(plate, tostring(10 + b.Seed % 90), b.Wall, 40, PLAQUE_DISTANCE)
end

----------------------------------------------------------------------
-- Étages (façade sur rue)
----------------------------------------------------------------------

local function upperFloors(b: Building, parent: Instance, F: CFrame, n: number)
	local style = b.Style
	local w = b.W
	local hw = w / 2
	local xs = windowXs(w, n)
	local nf = b.Floors - 1
	for f = 1, nf do
		local yb = b.GroundH + (f - 1) * b.FloorH
		local yt = yb + b.FloorH
		local y0, y1 = yb + 1.6, yb + 6.4
		local seedF = b.Seed * 7 + f
		if style == "Modern" then
			-- mur-rideau : dalle blanche, vitrage toute hauteur, ailettes, garde-corps
			box(parent, "SlabEdge", F, -hw, hw, yb, yb + 0.8, -0.7, 0, b.Trim, M.Concrete)
			local g = box(parent, "CurtainGlass", F, -hw + 0.8, hw - 0.8, yb + 0.8, yt, -0.2, -0.1, GLASS, M.Glass)
			g.Reflectance = 0.28
			for _, sx in ipairs({ -1, 1 }) do
				box(parent, "EndFrame", F, sx < 0 and -hw or hw - 0.8, sx < 0 and -hw + 0.8 or hw, yb + 0.8, yt, -0.7, 0, b.Wall, M.Concrete)
			end
			local fins = math.max(3, math.floor((w - 1.6) / 3.4))
			for i = 1, fins - 1 do
				local x = -hw + 0.8 + i * (w - 1.6) / fins
				box(parent, "Fin", F, x - 0.1, x + 0.1, yb + 0.8, yt, -0.9, -0.2, rgb(176, 184, 196), M.Metal)
			end
			if f % 2 == 1 then
				local rail = box(parent, "GlassRail", F, -hw + 0.8, hw - 0.8, yb + 0.8, yb + 3.2, -1.02, -0.94, rgb(200, 226, 240), M.Glass)
				rail.Transparency = 0.55
				box(parent, "RailTop", F, -hw + 0.8, hw - 0.8, yb + 3.2, yb + 3.36, -1.06, -0.9, rgb(176, 184, 196), M.Metal)
			end
			-- stores intérieurs (quelques-uns à demi baissés)
			for i, x in ipairs(xs) do
				if hash(seedF, i) < 0.5 then
					box(parent, "Blind", F, x - w / n / 2 + 0.3, x + w / n / 2 - 0.3, yt - 2.6 - hash(seedF, i + 5) * 2, yt - 0.1, -0.09, -0.04, rgb(238, 238, 236), M.Fabric)
				end
			end
		elseif style == "Timber" then
			-- colombages : sablières, poteaux, croix, allèges enduites
			local beam = b.Detail
			box(parent, "Sill", F, -hw, hw, yb, yb + 0.55, -0.4, 0, beam, M.Wood)
			box(parent, "Rail", F, -hw, hw, y0 - 0.35, y0, -0.35, 0, beam, M.Wood)
			box(parent, "Rail", F, -hw, hw, y1, y1 + 0.35, -0.35, 0, beam, M.Wood)
			local posts = { -hw + 0.3, hw - 0.3 }
			for _, x in ipairs(xs) do
				table.insert(posts, x - 1.7)
				table.insert(posts, x + 1.7)
			end
			for _, x in ipairs(posts) do
				box(parent, "Post", F, x - 0.3, x + 0.3, yb + 0.55, yt, -0.35, 0, beam, M.Wood)
			end
			for i, x in ipairs(xs) do
				local g = box(parent, "Glass", F, x - 1.4, x + 1.4, y0, y1, -0.12, -0.04, GLASS, M.Glass)
				g.Reflectance = 0.18
				box(parent, "Mullion", F, x - 0.08, x + 0.08, y0, y1, -0.24, -0.16, WHITE, M.Wood)
				box(parent, "Transom", F, x - 1.4, x + 1.4, y0 + 3.1, y0 + 3.26, -0.28, -0.2, WHITE, M.Wood)
				-- croix de Saint-André dans l'allège, entre deux fenêtres
				if i < #xs then
					local mid = (x + xs[i + 1]) / 2
					local span = xs[i + 1] - x - 3.4 - 0.6
					if span > 1.2 then
						local len = math.sqrt(span * span + (y1 - y0) ^ 2)
						local ang = math.atan2(y1 - y0, span)
						local cy = (y0 + y1) / 2
						for _, sgn in ipairs({ -1, 1 }) do
							newPart(parent, "Brace", Vector3.new(len, 0.4, 0.3), F * CFrame.new(mid, cy, -0.17 - (sgn > 0 and 0.03 or 0)) * CFrame.Angles(0, 0, sgn * ang), beam, M.Wood)
						end
					end
				end
				box(parent, "FlowerBox", F, x - 1.4, x + 1.4, y0 - 0.95, y0 - 0.35, -1.2, -0.38, rgb(150, 100, 70), M.WoodPlanks)
				ball(parent, "Blooms", F, x, y0 - 0.2, -0.8, 1, FLOWERS[(i + f) % #FLOWERS + 1], M.Grass)
			end
		else
			local stone = style == "Haussmann"
			local ww = stone and 2.6 or 2.8
			local openings = {}
			for _, x in ipairs(xs) do
				table.insert(openings, { x, ww })
			end
			local skinColor = b.Wall
			local skinMat = style == "Brick" and M.Brick or (stone and M.Limestone or M.Plaster)
			skinFloor(parent, F, w, yb, yt, y0, y1, openings, skinColor, skinMat, true)
			-- bandeau d'étage (pierre / enduit clair)
			if style ~= "Brick" then
				box(parent, "Course", F, -hw - 0.1, hw + 0.1, yb - 0.05, yb + 0.35, -SKIN - 0.25, -SKIN + 0.01, b.Trim, M.Concrete)
			end
			local shutterColor = style == "Pastel" and b.Accent or nil
			local balcony = stone and (f == 1 or (f == nf and nf >= 3))
			for i, x in ipairs(xs) do
				windowTrim(parent, F, x, y0, y1, ww, b.Trim, {
					Sill = not balcony,
					Hood = stone or style == "Brick",
					Mullion = true,
					Transom = style == "Brick",
					Shutters = shutterColor,
					Box = style == "Pastel" and (i + f) % 2 == 0 and not (f == nf and #xs >= 3 and i == math.ceil(#xs / 2)),
					Curtain = true,
					Seed = seedF * 3 + i,
				})
				if stone and not balcony then
					-- balconnet en fer forgé devant la porte-fenêtre
					box(parent, "BalconetSlab", F, x - ww / 2 - 0.3, x + ww / 2 + 0.3, y0 - 0.25, y0, -SKIN - 0.9, -SKIN, b.Trim, M.Limestone)
					local rail = box(parent, "Balconet", F, x - ww / 2 - 0.2, x + ww / 2 + 0.2, y0, y0 + 1.5, -SKIN - 0.85, -SKIN - 0.77, IRON, M.Metal)
					rail.Transparency = 0.3
				end
			end
			if balcony then
				-- grand balcon filant (dalle + garde-corps ajouré + main courante)
				box(parent, "Balcony", F, -hw + 0.4, hw - 0.4, y0 - 0.3, y0, -SKIN - 1.3, -SKIN, b.Trim, M.Limestone)
				local rail = box(parent, "BalconyRail", F, -hw + 0.5, hw - 0.5, y0, y0 + 1.6, -SKIN - 1.22, -SKIN - 1.14, IRON, M.Metal)
				rail.Transparency = 0.35
				box(parent, "HandRail", F, -hw + 0.45, hw - 0.45, y0 + 1.6, y0 + 1.74, -SKIN - 1.28, -SKIN - 1.08, IRON, M.Metal)
			end
			-- petit balcon pastel sous le pignon (dernier étage, fenêtre du milieu)
			if style == "Pastel" and f == nf and #xs >= 3 then
				local x = xs[math.ceil(#xs / 2)]
				box(parent, "Balcony", F, x - 2.4, x + 2.4, y0 - 0.3, y0 - 0.02, -SKIN - 1.3, -SKIN, b.Trim, M.Concrete)
				local rail = box(parent, "BalconyRail", F, x - 2.3, x + 2.3, y0, y0 + 1.4, -SKIN - 1.22, -SKIN - 1.14, WHITE, M.SmoothPlastic)
				rail.Transparency = 0.4
			end
		end
	end
end

----------------------------------------------------------------------
-- Toit (lucarnes, gouttières, œil-de-bœuf, panneaux)
----------------------------------------------------------------------

local function roofExtras(b: Building, parent: Instance, F: CFrame)
	local w, d, h = b.W, b.D, b.Height
	local hw = w / 2
	local style = b.Style
	if style == "Haussmann" then
		-- lucarnes sur le brisis (côté rue)
		local n = math.max(2, math.floor(w / 8))
		local base = h + 0.9
		local md, mh = 2, 5.2
		for i = 1, n do
			local x = -hw + (i - 0.5) * w / n
			-- (boîte posée devant la pente du brisis)
			box(parent, "Dormer", F, x - 1.3, x + 1.3, base + 0.1, base + 3.8, md * 0.25 - 0.5, md + 0.4, b.Wall, M.Limestone)
			local g = box(parent, "DormerGlass", F, x - 0.8, x + 0.8, base + 1, base + 3.2, md * 0.25 - 0.56, md * 0.25 - 0.5 - 0.01, GLASS, M.Glass)
			g.Reflectance = 0.2
			local cap = newPart(parent, "DormerRoof", Vector3.new(3.1, 0.3, 2.9), F * CFrame.new(x, base + 4, md * 0.25 + 0.7) * CFrame.Angles(math.rad(12), 0, 0), rgb(104, 112, 132), M.Metal)
			cap.CastShadow = true
		end
		-- pots des souches de cheminée
		for _, sx in ipairs({ -1, 1 }) do
			for k = -1, 1, 2 do
				rodY(parent, "ChimneyPot", F, sx * (hw - 1.2), base + mh + 3.4, base + mh + 4.3, d * 0.55 + k * 0.8, 0.6, rgb(196, 120, 96), M.Brick)
			end
		end
	elseif style == "Brick" or style == "Timber" then
		-- gouttières (avant, arrière) + descente
		local y = h + 0.9 - 0.25
		rodX(parent, "Gutter", F, -hw - 0.4, hw + 0.4, y, -1.25, 0.4, rgb(90, 92, 104), M.Metal)
		rodX(parent, "Gutter", F, -hw - 0.4, hw + 0.4, y, d + 1.25, 0.4, rgb(90, 92, 104), M.Metal)
		-- lucarne à capucine (côté rue) pour une maison sur deux
		if hash(b.Seed, 41) < 0.6 then
			local roofH = math.min(8, d * 0.42)
			local zc = d * 0.18
			local yc = h + 0.9 + roofH * (zc / (d / 2))
			box(parent, "Dormer", F, -1.5, 1.5, yc - 0.6, yc + 2.4, zc - 0.9, zc + 1.6, b.Wall, style == "Brick" and M.Brick or M.Plaster)
			local g = box(parent, "DormerGlass", F, -0.9, 0.9, yc - 0.2, yc + 1.9, zc - 0.97, zc - 0.91, GLASS, M.Glass)
			g.Reflectance = 0.2
			newPart(parent, "DormerRoof", Vector3.new(3.6, 0.3, 3.2), F * CFrame.new(0, yc + 2.6, zc + 0.3) * CFrame.Angles(math.rad(14), 0, 0), rgb(92, 84, 96), M.Slate)
		end
		rodY(parent, "ChimneyPot", F, hw * 0.6 * (b.Seed % 2 == 0 and 1 or -1), h + 0.9 + math.min(8, d * 0.42) * 0.6 + 3.8, h + 0.9 + math.min(8, d * 0.42) * 0.6 + 4.7, d * 0.66, 0.7, rgb(196, 120, 96), M.Brick)
	elseif style == "Pastel" then
		-- pignon sur rue : œil-de-bœuf + gouttières sur les côtés + épi de faîtage
		local roofH = math.min(9, w * 0.4)
		local cy = h + 0.6 + roofH * 0.4
		local ring = newPart(parent, "Oculus", Vector3.new(0.3, 2.4, 2.4), F * CFrame.new(0, cy, -0.18) * CFrame.Angles(0, math.rad(90), 0), b.Trim, M.SmoothPlastic)
		;(ring :: Part).Shape = Enum.PartType.Cylinder
		local glass = newPart(parent, "OculusGlass", Vector3.new(0.3, 1.7, 1.7), F * CFrame.new(0, cy, -0.24) * CFrame.Angles(0, math.rad(90), 0), GLASS, M.Glass)
		;(glass :: Part).Shape = Enum.PartType.Cylinder
		for _, sx in ipairs({ -1, 1 }) do
			local gutter = newPart(parent, "Gutter", Vector3.new(d + 0.6, 0.4, 0.4), F * CFrame.new(sx * (hw + 0.85), h + 0.35, d / 2) * CFrame.Angles(0, math.rad(90), 0), rgb(236, 236, 240), M.Metal)
			;(gutter :: Part).Shape = Enum.PartType.Cylinder
		end
		rodY(parent, "Finial", F, 0, h + 0.6 + roofH + 0.4, h + 0.6 + roofH + 1.6, -0.2, 0.25, rgb(214, 180, 90), M.Metal)
	else
		-- toit-terrasse : garde-corps, panneaux solaires, antenne
		box(parent, "RoofRail", F, -hw + 0.4, hw - 0.4, h + 1.4, h + 2.4, 0.2, 0.3, rgb(176, 184, 196), M.Metal)
		for i = 0, 1 do
			local x = hw * 0.35 + (i - 0.5) * 3.4
			newPart(parent, "Solar", Vector3.new(3, 0.2, 2), F * CFrame.new(x, h + 2.1, d * 0.4) * CFrame.Angles(math.rad(-25), 0, 0), rgb(40, 52, 90), M.Glass)
		end
		rodY(parent, "Antenna", F, -hw * 0.18, h + 4.4, h + 8.4, d * 0.62, 0.2, rgb(150, 150, 164), M.Metal)
	end
	-- descente d'eau (coin avant droit)
	rodY(parent, "Downpipe", F, hw - 0.35, 1.2, h + 0.6, -0.72, 0.35, rgb(120, 122, 134), M.Metal)
end

----------------------------------------------------------------------
-- Arrière (côté parc) et côtés exposés
----------------------------------------------------------------------

-- Fenêtre "posée" sur une face : encadrement + vitre + appui (repère R :
-- face du mur à z = 0, dehors vers -Z)
local function flatWindow(parent: Instance, R: CFrame, x: number, y0: number, y1: number, ww: number, trim: Color3, seed: number)
	box(parent, "Frame", R, x - ww / 2 - 0.3, x + ww / 2 + 0.3, y0 - 0.3, y1 + 0.3, -0.16, 0, trim, M.SmoothPlastic)
	local g = box(parent, "Glass", R, x - ww / 2, x + ww / 2, y0, y1, -0.22, -0.16, GLASS, M.Glass)
	g.Reflectance = 0.18
	box(parent, "Sill", R, x - ww / 2 - 0.45, x + ww / 2 + 0.45, y0 - 0.62, y0 - 0.3, -0.62, -0.03, trim, M.Concrete)
	if hash(seed, 3) < 0.4 then
		box(parent, "Blind", R, x - ww / 2 + 0.05, x + ww / 2 - 0.05, y1 - (y1 - y0) * 0.45, y1, -0.28, -0.23, rgb(240, 230, 214), M.Fabric)
	end
end

local function backSide(b: Building, parent: Instance)
	local w, d = b.W, b.D
	local hw = w / 2
	-- repère de la face arrière : origine au pied du mur arrière, -Z vers le parc
	local R = b.CF * CFrame.new(0, 0, d) * CFrame.Angles(0, math.pi, 0)
	local trim = b.Style == "Brick" and b.Trim or b.Trim:Lerp(b.Wall, 0.25)
	local nf = b.Floors - 1
	local xs = { -w * 0.25, w * 0.25 }
	for f = 1, nf do
		local yb = b.GroundH + (f - 1) * b.FloorH
		for i, x in ipairs(xs) do
			flatWindow(parent, R, x, yb + 1.8, yb + 6, 2.6, trim, b.Seed * 5 + f * 3 + i)
		end
		-- petit balcon arrière (un étage sur deux, une maison sur deux)
		if f == 1 and hash(b.Seed, 51) < 0.5 then
			local x = xs[2]
			box(parent, "BackBalcony", R, x - 2.4, x + 2.4, yb + 1.1, yb + 1.4, -1.8, -0.62, trim, M.Concrete)
			local rail = box(parent, "BackRail", R, x - 2.3, x + 2.3, yb + 1.4, yb + 2.9, -1.74, -1.66, IRON, M.Metal)
			rail.Transparency = 0.35
		end
	end
	-- porte de service + perron + applique éteinte
	local dx = -w * 0.25
	box(parent, "BackDoorFrame", R, dx - 1.7, dx + 1.7, 1.2, 8.3, -0.16, 0, trim, M.SmoothPlastic)
	box(parent, "BackDoor", R, dx - 1.3, dx + 1.3, 1.2, 7.9, -0.3, -0.16, b.Accent:Lerp(WHITE, 0.15), M.Wood)
	box(parent, "BackStep", R, dx - 1.8, dx + 1.8, -0.6, 1.17, -1.9, -0.62, rgb(206, 200, 194), M.Concrete, true)
	box(parent, "BackLamp", R, dx + 2, dx + 2.5, 6.6, 7.4, -0.5, -0.03, rgb(250, 236, 200), M.Glass)
	flatWindow(parent, R, w * 0.25, 3.6, 7.4, 3.2, trim, b.Seed + 77)
	-- jardinet : bac de fleurs + buissons le long du mur (dans l'emprise du socle)
	box(parent, "Planter", R, w * 0.25 - 2.4, w * 0.25 + 2.4, -0.6, 1.9, -0.9, -0.1, rgb(176, 124, 84), M.WoodPlanks)
	for k = -1, 1 do
		ball(parent, "Shrub", R, w * 0.25 + k * 1.5, 2.2, -0.5, 1.3, k == 0 and FLOWERS[(b.Seed % #FLOWERS) + 1] or rgb(104, 172, 96), M.Grass)
	end
	-- climatiseur + descente d'eau
	box(parent, "AirCon", R, hw - 2.6, hw - 0.8, b.GroundH + 1, b.GroundH + 2.4, -1.2, -0.03, rgb(226, 228, 232), M.Metal)
	rodY(parent, "Downpipe", R, -hw + 0.4, 1.2, b.Height + 0.6, -0.3, 0.35, rgb(120, 122, 134), M.Metal)
end

-- Côté exposé (sx = -1 : gauche, +1 : droite vus de la rue) ; `above` > 0 :
-- seuls les étages au-dessus de cette hauteur sont visibles (voisin plus bas)
local function exposedSide(b: Building, parent: Instance, sx: number, above: number)
	local w, d = b.W, b.D
	-- repère de la face latérale : origine au pied du mur, milieu en profondeur
	local R = b.CF * CFrame.new(sx * w / 2, 0, d / 2) * CFrame.Angles(0, sx * -math.pi / 2, 0)
	local trim = b.Trim:Lerp(b.Wall, 0.2)
	local nf = b.Floors - 1
	for f = 1, nf do
		local yb = b.GroundH + (f - 1) * b.FloorH
		if yb + 1.5 >= above then
			local xs = d >= 18 and { -d * 0.22, d * 0.22 } or { 0 }
			for i, x in ipairs(xs) do
				flatWindow(parent, R, x, yb + 2, yb + 6, 2.2, trim, b.Seed * 11 + f * 2 + i)
			end
		end
	end
	-- œil-de-bœuf dans le pignon (toits à deux pans parallèles à la rue)
	if (b.Style == "Brick" or b.Style == "Timber") and above < b.Height + 1 then
		local roofH = math.min(8, d * 0.42)
		local cy = b.Height + 0.9 + roofH * 0.38
		local ring = newPart(parent, "Oculus", Vector3.new(0.3, 2, 2), R * CFrame.new(0, cy, -0.18) * CFrame.Angles(0, math.rad(90), 0), b.Trim, M.SmoothPlastic)
		;(ring :: Part).Shape = Enum.PartType.Cylinder
		local glass = newPart(parent, "OculusGlass", Vector3.new(0.3, 1.4, 1.4), R * CFrame.new(0, cy, -0.24) * CFrame.Angles(0, math.rad(90), 0), GLASS, M.Glass)
		;(glass :: Part).Shape = Enum.PartType.Cylinder
	end
	if above > 0 then
		return
	end
	-- rez-de-chaussée : réclame peinte (une maison sur deux) ou fenêtre
	if hash(b.Seed + sx, 61) < 0.55 then
		local mural = box(parent, "Mural", R, -d * 0.36, d * 0.36, 2.2, b.GroundH - 1.2, -0.08, -0.03, b.Accent:Lerp(WHITE, 0.2), M.SmoothPlastic)
		signText(mural, Locale.T(MURALS[math.floor(hash(b.Seed, 63) * #MURALS) + 1]), WHITE, 18, SIGN_DISTANCE)
	else
		flatWindow(parent, R, 0, 3.6, 7.4, 3, trim, b.Seed + 91)
	end
end

----------------------------------------------------------------------
-- Mairie (arrière + côtés) et boutiques de décor de la place (arrière,
-- côtés, pancarte "Fermé") : leur façade est construite par le serveur
----------------------------------------------------------------------

local function hallExtras(b: Building, parent: Instance)
	local w, d = b.W, b.D
	local trim = b.Trim
	-- arrière : 2 rangées de hautes fenêtres + porte à deux battants
	local R = b.CF * CFrame.new(0, 0, d) * CFrame.Angles(0, math.pi, 0)
	local n = 8
	for f = 0, 1 do
		local y0 = 3.8 + f * 14
		for i = 1, n do
			local x = -w / 2 + (i - 0.5) * w / n
			if not (f == 0 and (i == n / 2 or i == n / 2 + 1)) then
				flatWindow(parent, R, x, y0, y0 + 6.4, 3.2, trim, b.Seed * 13 + f * 9 + i)
			end
		end
		box(parent, "Course", R, -w / 2, w / 2, y0 + 7.4, y0 + 8, -0.4, 0, trim, M.Marble)
	end
	-- (le socle de la mairie monte à 1,55 et déborde de 0,4 : porte au-dessus)
	box(parent, "BackPortal", R, -3.6, 3.6, 1.55, 10.6, -0.55, 0, trim, M.Marble)
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "BackDoor", R, sx < 0 and -3 or 0.05, sx < 0 and -0.05 or 3, 1.6, 9.6, -0.7, -0.55, rgb(120, 80, 70), M.Wood)
		box(parent, "DoorKnob", R, sx * 0.45 - 0.12, sx * 0.45 + 0.12, 5.2, 5.5, -0.83, -0.7, rgb(214, 180, 90), M.Metal)
	end
	box(parent, "BackSteps", R, -4.4, 4.4, -0.6, 0.8, -2.6, -0.41, rgb(214, 208, 202), M.Marble, true)
	box(parent, "BackSteps", R, -4.4, 4.4, 0.8, 1.52, -1.5, -0.41, rgb(222, 216, 210), M.Marble, true)
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "Planter", R, sx * 8 - 1.6, sx * 8 + 1.6, -0.6, 1.4, -1.8, -0.2, trim, M.Marble)
		ball(parent, "Shrub", R, sx * 8, 2.1, -1, 2, rgb(96, 164, 96), M.Grass)
	end
	-- côtés : 2 rangées de 2 fenêtres
	for _, sx in ipairs({ -1, 1 }) do
		local S = b.CF * CFrame.new(sx * w / 2, 0, d / 2) * CFrame.Angles(0, sx * -math.pi / 2, 0)
		for f = 0, 1 do
			for _, x in ipairs({ -d * 0.25, d * 0.25 }) do
				flatWindow(parent, S, x, 3.8 + f * 14, 10.2 + f * 14, 3.2, trim, b.Seed + f * 3 + math.floor(x))
			end
		end
	end
end

local function decorShopExtras(b: Building, parent: Instance)
	backSide(b, parent)
	for _, sx in ipairs({ -1, 1 }) do
		local exposed = (sx < 0 and b.Left) or (sx > 0 and b.Right)
		if exposed then
			local R = b.CF * CFrame.new(sx * b.W / 2, 0, b.D / 2) * CFrame.Angles(0, sx * -math.pi / 2, 0)
			for f = 1, b.Floors - 1 do
				local yb = b.GroundH + (f - 1) * b.FloorH
				flatWindow(parent, R, 0, yb + 2, yb + 6, 2.2, b.Trim, b.Seed * 3 + f + sx)
			end
		end
	end
	-- pancarte "Fermé" sur la porte vitrée (porte au milieu de la devanture)
	local plaque = box(parent, "ClosedSign", b.CF, -0.8, 0.8, 5, 5.8, -0.73, -0.67, WHITE, M.SmoothPlastic)
	signText(plaque, Locale.T("Closed for now 😴"), rgb(200, 70, 100), 60, PLAQUE_DISTANCE, Enum.Font.GothamBold)
end

----------------------------------------------------------------------
-- Un immeuble : travaux découpés (façade, étages, arrière, côtés, toit)
----------------------------------------------------------------------

local function jobsFor(b: Building, parent: Model): { () -> () }
	local jobs: { () -> () } = {}
	local F = b.CF
	if b.Style == "Hall" then
		table.insert(jobs, function()
			hallExtras(b, parent)
		end)
		return jobs
	elseif b.Style == "DecorShop" then
		table.insert(jobs, function()
			decorShopExtras(b, parent)
		end)
		return jobs
	end
	local n = math.clamp(math.floor((b.W - 2) / 6.5), 2, 4)
	table.insert(jobs, function()
		local style = b.Style
		local r = hash(b.Seed, 91)
		if style == "Modern" and r < 0.5 then
			lobbyFront(b, parent, F)
		elseif r < 0.68 then
			shopFront(b, parent, F)
		else
			local mat = style == "Brick" and M.Brick or (style == "Haussmann" and M.Limestone or (style == "Modern" and M.Concrete or M.Plaster))
			homeFront(b, parent, F, b.Wall, mat, n)
		end
	end)
	table.insert(jobs, function()
		upperFloors(b, parent, F, n)
	end)
	table.insert(jobs, function()
		backSide(b, parent)
	end)
	table.insert(jobs, function()
		if b.Left or b.LeftAbove < b.Height - 2 then
			exposedSide(b, parent, -1, b.Left and 0 or b.LeftAbove)
		end
		if b.Right or b.RightAbove < b.Height - 2 then
			exposedSide(b, parent, 1, b.Right and 0 or b.RightAbove)
		end
		roofExtras(b, parent, F)
	end)
	return jobs
end

local function setFar(b: Building, hidden: boolean)
	for _, p in ipairs(b.Far) do
		if p.Parent then
			p.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function destroyDetail(b: Building)
	if b.Detail_ then
		b.Detail_:Destroy()
		b.Detail_ = nil
		stats.Destroyed += 1
	end
	b.Jobs = nil
	b.Built = false
	setFar(b, false)
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function localPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return focus
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function decide(position: Vector3)
	for _, b in ipairs(buildings) do
		local dist = flat(position, b.Center)
		if (b.Built or b.Jobs) and dist > DROP_RANGE then
			destroyDetail(b)
		end
	end
	-- un chantier à la fois : l'immeuble le plus proche qui en a besoin
	for _, b in ipairs(buildings) do
		if b.Jobs then
			return
		end
	end
	local best: Building? = nil
	local bestD = math.huge
	for _, b in ipairs(buildings) do
		local dist = flat(position, b.Center)
		if not b.Built and dist <= BUILD_RANGE and dist < bestD then
			best, bestD = b, dist
		end
	end
	if best and folder then
		local model = Instance.new("Model")
		model.Name = "Facade_" .. best.Style
		model.Parent = folder
		best.Detail_ = model
		best.Jobs = jobsFor(best, model)
		best.JobIndex = 1
		best.Parts = count
	end
end

local function runJobs()
	local t0 = os.clock()
	for _, b in ipairs(buildings) do
		local jobs = b.Jobs
		if jobs then
			repeat
				local job = jobs[b.JobIndex]
				if job then
					local ok, err = pcall(job)
					if not ok then
						warn("[TownFacades] " .. b.Style .. " : " .. tostring(err))
					end
				end
				b.JobIndex += 1
			until b.JobIndex > #jobs or os.clock() - t0 > STEP_BUDGET
			if b.JobIndex > #jobs then
				b.Jobs = nil
				b.Built = true
				b.Parts = count - b.Parts
				stats.Built += 1
				stats.Parts = count
				setFar(b, true)
			end
			return
		end
	end
end

local function heartbeat(dt: number)
	if not started then
		return
	end
	runJobs()
	clock += dt
	if clock < STEP_EVERY then
		return
	end
	clock = 0
	local position = localPosition()
	if position then
		decide(position)
	end
end

function TownFacades.Step(position: Vector3?)
	if typeof(position) == "Vector3" then
		focus = position
	end
end

----------------------------------------------------------------------
-- Démarrer / arrêter
----------------------------------------------------------------------

local function discover(): { Building }
	local list: { Building } = {}
	local town = workspace:FindFirstChild("DopamineTown")
	if not town then
		return list
	end
	for _, model in ipairs(town:GetDescendants()) do
		if model:IsA("Model") then
			local style = model:GetAttribute("FacadeStyle")
			local cf = model:GetAttribute("FacadeCF")
			local w, d = model:GetAttribute("W"), model:GetAttribute("D")
			if type(style) == "string" and typeof(cf) == "CFrame" and type(w) == "number" and type(d) == "number" then
				local function color(key: string, default: Color3): Color3
					local v = model:GetAttribute(key)
					return typeof(v) == "Color3" and v or default
				end
				local function num(key: string, default: number): number
					local v = model:GetAttribute(key)
					return type(v) == "number" and v or default
				end
				local far = {}
				for _, p in ipairs(model:GetChildren()) do
					if p:IsA("BasePart") and p:GetAttribute("FarLOD") == true then
						table.insert(far, p)
					end
				end
				table.insert(list, {
					Model = model,
					Style = style,
					CF = cf,
					W = w,
					D = d,
					Floors = math.max(1, math.floor(num("Floors", 2))),
					Height = num("Height", 18.5),
					Seed = math.floor(num("Seed", 1)),
					GroundH = num("GroundH", 10),
					FloorH = num("FloorH", 8.5),
					Wall = color("Wall", rgb(240, 232, 222)),
					Trim = color("Trim", WHITE),
					Accent = color("Accent", rgb(48, 62, 104)),
					Detail = color("Detail", rgb(60, 60, 70)),
					Left = true,
					Right = true,
					LeftAbove = 0,
					RightAbove = 0,
					Center = (cf * CFrame.new(0, 0, d / 2)).Position,
					Far = far,
					Detail_ = nil,
					Jobs = nil,
					JobIndex = 1,
					Built = false,
					Parts = 0,
				})
			end
		end
	end
	-- côtés exposés : pas de voisin aligné tout contre
	for _, b in ipairs(list) do
		for _, o in ipairs(list) do
			if o ~= b and b.CF.LookVector:Dot(o.CF.LookVector) > 0.98 then
				local rel = b.CF:PointToObjectSpace(o.CF.Position)
				local gap = math.abs(rel.X) - (b.W + o.W) / 2
				if math.abs(rel.Z) < 4 and gap < 6 then
					-- voisin collé : ce côté n'est à nu qu'au-dessus de lui
					local above = o.Height + 1
					if rel.X < 0 then
						b.Left = false
						b.LeftAbove = math.max(b.LeftAbove, above)
					else
						b.Right = false
						b.RightAbove = math.max(b.RightAbove, above)
					end
				end
			end
		end
	end
	return list
end

function TownFacades.Start()
	if started then
		return
	end
	started = true
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	folder = f
	buildings = discover()
	clock = STEP_EVERY
	table.insert(conns, RunService.Heartbeat:Connect(heartbeat))
end

function TownFacades.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	for _, b in ipairs(buildings) do
		destroyDetail(b)
	end
	table.clear(buildings)
	if folder then
		folder:Destroy()
		folder = nil
	end
	focus = nil
end

function TownFacades.Debug(): any
	return {
		Buildings = buildings,
		Stats = stats,
		Folder = folder,
		Decide = decide,
		RunAll = function()
			for _ = 1, 400 do
				local pending = false
				for _, b in ipairs(buildings) do
					if b.Jobs then
						pending = true
					end
				end
				if not pending then
					break
				end
				runJobs()
			end
		end,
		-- tout construire (rendus : vue d'ensemble)
		BuildAll = function()
			for _ = 1, #buildings do
				local target: Building? = nil
				for _, b in ipairs(buildings) do
					if not b.Built and not b.Jobs then
						target = b
						break
					end
				end
				if not target or not folder then
					break
				end
				local model = Instance.new("Model")
				model.Name = "Facade_" .. target.Style
				model.Parent = folder
				target.Detail_ = model
				target.Jobs = jobsFor(target, model)
				target.JobIndex = 1
				target.Parts = count
				for _ = 1, 50 do
					if not target.Jobs then
						break
					end
					runJobs()
				end
			end
		end,
	}
end

return TownFacades
