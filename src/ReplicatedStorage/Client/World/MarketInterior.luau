--[[
	MarketInterior (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MarketInterior

	🛒 Dopamine Town (v9.7, BUILDINGS97) : l'INTÉRIEUR du supermarché
	« MégaDopa » (et la vie de son parking), construit côté client, en flux.
	Le serveur (TownMarket) a posé la coque dans DopamineTown.Market
	("Supermarket" : attributs MarketCF, InteriorCF, InteriorSize, DoorCF,
	LotCF, StallsA/B ; vantaux "DoorPanel" + SlideX).
	  - Niveau 1 "Dehors" (≤ 240 studs, gardé jusqu'à 300) : voitures garées
	    sur les places (CarModels "Parked"), abris à chariots et chariots,
	    camion de livraison au quai, affiches dans les vitrines, bacs fleuris ;
	  - Niveau 2 "Complet" (≤ 75 studs, gardé jusqu'à 115) :
	      · sol clair, allée centrale, charpente apparente, gaines, rampes
	        d'éclairage (3 PointLights douces + 6 SurfaceLights, allumées
	        SEULEMENT quand on est dedans, luminosité ≤ 1, aucun Neon) ;
	      · 5 GONDOLES (10 faces, 4 niveaux) : céréales, boissons, conserves,
	        snacks, hygiène... des centaines de produits posés sur les
	        tablettes (une pièce par produit), étiquettes de prix sur le bord
	        des tablettes (SurfaceGui), têtes de gondole "PROMO" ;
	      · rayons MAISON avec les VRAIS objets de la maison (comme les
	        boutiques de la ville, House3DRecipes.BuildItem à petite échelle) :
	        Cuisine, Déco, Luminaires, Jouets, Jeux vidéo ; + comptoir
	        Électronique (mur de télés) et Jardin (gradins de plantes) ; chacun
	        avec son étiquette (BillboardGui, ancre INVISIBLE, AlwaysOnTop, les
	        5 plus proches seulement, seulement dans le magasin : leçon du
	        correctif v9.6.1) et son invite "Acheter — 🧠 prix" ;
	      · fruits & légumes (étals inclinés, cagettes), boulangerie (vitrine,
	        pains, boulanger·ère), frigos à portes vitrées, bacs de surgelés,
	        portants de vêtements, panneaux d'allées suspendus (numéro +
	        rayons) ;
	      · CAISSES : 4 caisses (tapis roulant, caisse enregistreuse, écran,
	        terminal de carte, lampe numérotée, caissier·ère kawaii), barrières
	        de file d'attente, 4 caisses automatiques ; à chaque caisse
	        l'invite "🛒 Passer en caisse" ouvre le CATALOGUE COMPLET
	        (ShopUI "Market" : toutes les catégories de la maison) ;
	      · chariots, paniers, portiques antivol, palette promo, clients.
	  - achats : ShopUI.Purchase (serveur House "buyItem"), comme les
	    boutiques ; réussi -> étincelles sur l'objet, étiquette à jour.
	  - portes coulissantes : s'ouvrent quand un avatar approche.
	Construction étalée (budget de temps par image), jamais de création ni
	de destruction par image ensuite. Aucune face confondue (écarts ≥ 0,03).

	API (TownClient, via optionalModule) :
	  MarketInterior.Start({ Toast = fn(text, color?) }?)   à l'entrée en ville
	  MarketInterior.Step(position: Vector3)                 flux (facultatif)
	  MarketInterior.Stop()                                  à la sortie
	  MarketInterior.Debug() -> table                        (tests / rendus)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Locale = require(ReplicatedStorage.Shared.Locale)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local HouseCommon = require(Client.Components.House.HouseCommon)
local ShopUI = require(script.Parent.ShopUI)

local MarketInterior = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = rgb(92, 58, 96)
local BRAND = rgb(236, 72, 140)
local BRAND2 = rgb(120, 90, 200)
local YELLOW = rgb(255, 208, 72)

local FOLDER_NAME = "TownMarketInterior"
local OUT_RANGE, OUT_DROP = 240, 300
local FULL_RANGE, FULL_DROP = 75, 115
local STEP_BUDGET = 0.004
local STEP_EVERY = 0.25
local DOOR_RANGE = 12
local TAG_DISTANCE = 16
local PROMPT_DISTANCE = 5.5
local MAX_TAGS = 5
local PX = WorldLayout.PX
local GAP = 0.05
local FLOOR_TOP = 0.07 -- dessus du revêtement de sol (repère F)

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

local partCount = 0

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
	partCount += 1
	return p
end

local function box(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return newPart(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, solid)
end

-- Cylindre debout (repère F)
local function cyl(parent: Instance, name: string, F: CFrame, x: number, y0: number, z: number, height: number, diameter: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = newPart(parent, name, Vector3.new(height, diameter, diameter), F * CFrame.new(x, y0 + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material, solid)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Cylindre couché d'axe X (repère F)
local function cylX(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(parent, name, Vector3.new(math.abs(x1 - x0), diameter, diameter), F * CFrame.new((x0 + x1) / 2, y, z), color, material)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, F: CFrame, x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(parent, name, Vector3.new(diameter, diameter, diameter), F * CFrame.new(x, y, z), color, material)
	;(p :: Part).Shape = Enum.PartType.Ball
	return p
end

-- Texte sur une face d'une pièce (SurfaceGui)
local function label(board: BasePart, face: Enum.NormalId, text: string, textColor: Color3, background: Color3?, pps: number, maxDistance: number, font: Enum.Font?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.4
	gui.Brightness = 1
	gui.MaxDistance = maxDistance
	gui.Parent = board
	if background then
		local bg = Instance.new("Frame")
		bg.Name = "Back"
		bg.BackgroundColor3 = background
		bg.BorderSizePixel = 0
		bg.Size = UDim2.fromScale(1, 1)
		bg.Parent = gui
	end
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.92, 0.8)
	l.Position = UDim2.fromScale(0.04, 0.1)
	l.Font = font or Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = textColor
	l.Parent = gui
	return gui
end

local function hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function pick<T>(list: { T }, seed: number, salt: number): T
	return list[math.floor(hash(seed, salt) * #list) + 1]
end

----------------------------------------------------------------------
-- Modèles 3D des objets (paresseux)
----------------------------------------------------------------------

local recipes: any = nil
local function Recipes(): any
	if recipes == nil then
		local module = Client.Components.House:FindFirstChild("House3DRecipes")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		recipes = ok and result or false
	end
	return recipes or nil
end

local function carModels(): any?
	local module = ReplicatedStorage.Shared:FindFirstChild("CarModels")
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return ok and type(result) == "table" and result or nil
end

----------------------------------------------------------------------
-- État
----------------------------------------------------------------------

type Slot = { CF: CFrame, MaxW: number, MaxH: number, MaxD: number, Tag: CFrame, WallZ: number? }

type Display = {
	Entry: ShopUI.Entry,
	Model: Model?,
	Tag: BasePart?,
	Billboard: BillboardGui?,
	Prompt: ProximityPrompt?,
	Labels: { [string]: TextLabel },
}

type Door = { Part: BasePart, Closed: CFrame, Open: CFrame, IsOpen: boolean }

type Market = {
	Model: Model,
	MCF: CFrame, -- pied de la façade (milieu), LookVector vers le parking
	F: CFrame, -- sol intérieur, milieu de la face intérieure de la façade, +Z vers le fond
	Size: Vector3,
	InteriorCF: CFrame,
	DoorCF: CFrame,
	StallsA: number,
	StallsB: number,
	Level: number,
	Target: number,
	Tiers: { [number]: Folder },
	Jobs: { () -> () }?,
	JobIndex: number,
	Building: number,
	Displays: { Display },
	Lights: { Light },
	LightsOn: boolean,
	Doors: { Door },
	Checkouts: { Vector3 },
}

local started = false
local market: Market? = nil
local folder: Folder? = nil
local conns: { RBXScriptConnection } = {}
local clock = 0
local dirty = false
local focus: Vector3? = nil
local stats = { Built = 0, Destroyed = 0, Items = 0, Purchases = 0, Parts = 0, Products = 0 }

----------------------------------------------------------------------
-- Géométrie du magasin (repère F : x ∈ [-34, 34], z ∈ [0, 46])
----------------------------------------------------------------------

local GONDOLA_X = { -20, -11.5, -3, 5.5, 14 }
local GZ0, GZ1 = 17, 36 -- gondoles (le long de Z)
local GHALF = 1.3 -- demi-profondeur d'une gondole
local LEVELS = { 0.42, 1.98, 3.54, 5.1 } -- dessus des tablettes
local CLEAR = 1.4 -- hauteur libre au-dessus d'une tablette
local LANES = { 9.5, 15.5, 21.5, 27.5 } -- caisses (x du tapis)

-- Faces de gondole : { gondole, côté (-1 ouest / +1 est), contenu }
-- contenu : générique ("Cereal"...) ou catégorie de la maison ("Real:Kitchen")
local FACES = {
	{ 1, -1, "Cereal" },
	{ 1, 1, "Drinks" },
	{ 2, -1, "Pantry" },
	{ 2, 1, "Real:Kitchen" },
	{ 3, -1, "Real:Decor" },
	{ 3, 1, "Real:Lights" },
	{ 4, -1, "Real:Toys" },
	{ 4, 1, "Real:Gaming" },
	{ 5, -1, "Snacks" },
	{ 5, 1, "Care" },
}

-- Panneaux d'allées : x, numéro, rayons (clés anglaises)
local AISLES = {
	{ -25.1, "1", "🍎 Fruit & veg", "🥣 Breakfast" },
	{ -15.75, "2", "🥤 Drinks", "🥫 Pantry" },
	{ -7.25, "3", "🍳 Cookware", "🖼️ Home decor" },
	{ 1.25, "4", "💡 Lamps", "🧸 Toy aisle" },
	{ 9.75, "5", "🎮 Video games", "🍬 Sweets" },
	{ 17.9, "6", "🧼 Home care", "👕 Clothes" },
	{ 27, "7", "🪴 Garden", "🌷 Plants" },
}

local PALETTE = {
	rgb(236, 72, 90), rgb(255, 170, 60), rgb(255, 214, 80), rgb(96, 186, 110), rgb(80, 150, 230), rgb(150, 110, 220),
	rgb(255, 130, 180), rgb(250, 250, 246), rgb(70, 200, 200), rgb(200, 90, 60),
}
local PASTEL = { rgb(190, 230, 250), rgb(255, 214, 230), rgb(214, 246, 214), rgb(255, 244, 196), rgb(226, 214, 255), rgb(250, 250, 252) }
local DRINKS = { rgb(120, 60, 40), rgb(255, 150, 40), rgb(110, 200, 90), rgb(140, 200, 255), rgb(236, 60, 80), rgb(250, 230, 120) }
local FRUITS = {
	{ rgb(220, 40, 50), 0.62 }, -- pommes
	{ rgb(255, 150, 30), 0.66 }, -- oranges
	{ rgb(255, 220, 60), 0.5 }, -- citrons
	{ rgb(120, 190, 60), 0.62 }, -- pommes vertes
	{ rgb(120, 60, 140), 0.36 }, -- raisin
	{ rgb(250, 120, 40), 0.44 }, -- carottes (boules)
	{ rgb(70, 150, 60), 0.9 }, -- choux
	{ rgb(230, 60, 60), 0.5 }, -- tomates
}

local FACE_PX = CFrame.Angles(0, -math.pi / 2, 0) -- LookVector = +X
local FACE_NX = CFrame.Angles(0, math.pi / 2, 0) -- LookVector = -X

-- Repère d'une face de gondole : origine sur le bord des tablettes, au
-- milieu de la gondole, au sol ; LookVector vers l'allée ; x le long de la
-- gondole ; +Z vers la cloison du milieu
local function faceFrame(F: CFrame, gondola: number, side: number): CFrame
	local x = GONDOLA_X[gondola] + side * GHALF
	return F * CFrame.new(x, 0, (GZ0 + GZ1) / 2) * (side > 0 and FACE_PX or FACE_NX)
end

----------------------------------------------------------------------
-- Produits génériques (une pièce par produit)
----------------------------------------------------------------------

-- Une rangée de produits sur une tablette (repère S de la face)
local function productRow(parent: Instance, S: CFrame, y: number, kind: string, seed: number, x0: number, x1: number, tint: Color3?): number
	local n = 0
	local w, h, d, pitch, shape
	if kind == "Cereal" then
		w, h, d, pitch, shape = 0.95, 1.3, 0.38, 1.12, "Box"
	elseif kind == "Bottle" then
		w, h, d, pitch, shape = 0.46, 1.15, 0.46, 0.78, "Cyl"
	elseif kind == "Can" then
		w, h, d, pitch, shape = 0.55, 1.2, 0.55, 0.8, "Cyl"
	elseif kind == "Snack" then
		w, h, d, pitch, shape = 0.92, 1.1, 0.42, 1.1, "Bag"
	elseif kind == "Care" then
		w, h, d, pitch, shape = 0.52, 1.12, 0.36, 0.8, "Box"
	elseif kind == "Pack" then
		w, h, d, pitch, shape = 1.3, 1, 0.85, 1.48, "Box"
	else
		w, h, d, pitch, shape = 1.25, 1.08, 0.9, 1.45, "Box"
	end
	local count = math.floor((x1 - x0) / pitch)
	local start = x0 + ((x1 - x0) - count * pitch) / 2 + pitch / 2
	-- (groupes de 2-4 produits identiques, comme en vrai)
	local group, color = 0, WHITE
	for i = 0, count - 1 do
		if group <= 0 then
			group = 2 + math.floor(hash(seed + i, 3) * 3)
			if tint then
				color = tint:Lerp(pick(PASTEL, seed + i, 5), 0.25 + hash(seed + i, 7) * 0.3)
			elseif kind == "Bottle" then
				color = pick(DRINKS, seed + i, 5)
			elseif kind == "Care" then
				color = pick(PASTEL, seed + i, 5)
			else
				color = pick(PALETTE, seed + i, 5)
			end
		end
		group -= 1
		local x = start + i * pitch
		local z = 0.12 + d / 2
		if shape == "Cyl" then
			local p = newPart(parent, kind, Vector3.new(h, w, w), S * CFrame.new(x, y + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, kind == "Bottle" and M.Glass or M.Metal)
			;(p :: Part).Shape = Enum.PartType.Cylinder
			if kind == "Bottle" then
				p.Transparency = 0.1
			end
		else
			box(parent, kind, S, x - w / 2, x + w / 2, y, y + h, z - d / 2, z + d / 2, color, shape == "Bag" and M.Fabric or M.SmoothPlastic)
		end
		n += 1
	end
	stats.Products += n
	return n
end

-- Étiquettes de prix sur le bord d'une tablette (une SurfaceGui par tablette)
local function priceStrip(board: BasePart, face: Enum.NormalId, seed: number, count: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Prices"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.5
	gui.MaxDistance = 26
	gui.Parent = board
	for i = 1, count do
		local t = Instance.new("TextLabel")
		t.Name = "Price"
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale((i - 0.5) / count, 0.5)
		t.Size = UDim2.fromScale(0.07, 0.92)
		t.BackgroundColor3 = i % 3 == 0 and YELLOW or WHITE
		t.BorderSizePixel = 0
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = i % 3 == 0 and rgb(200, 40, 60) or INK
		local cents = math.floor(hash(seed, i) * 90) + 9
		t.Text = tostring(math.floor(hash(seed, i + 30) * 8)) .. "." .. tostring(cents)
		t.Parent = gui
	end
end

----------------------------------------------------------------------
-- Personnages kawaii (caissier·ère, boulanger·ère, clients)
----------------------------------------------------------------------

-- `P` : sol, LookVector = regard du personnage
local function figure(parent: Instance, P: CFrame, shirt: Color3, apron: Color3?, hair: Color3, hat: Color3?)
	local skin = rgb(255, 216, 186)
	box(parent, "Legs", P, -0.5, 0.5, 0, 2.2, -0.32, 0.32, rgb(80, 78, 110), M.SmoothPlastic)
	box(parent, "Body", P, -0.9, 0.9, 2.2, 4.2, -0.42, 0.42, shirt, M.Fabric)
	if apron then
		box(parent, "Apron", P, -0.68, 0.68, 2.3, 3.9, -0.5, -0.44, apron, M.Fabric)
		box(parent, "Badge", P, 0.25, 0.6, 3.55, 3.75, -0.55, -0.5, WHITE, M.SmoothPlastic)
	end
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "Arm", P, sx < 0 and -1.35 or 0.95, sx < 0 and -0.95 or 1.35, 2.5, 4.1, -0.28, 0.28, shirt, M.Fabric)
	end
	ball(parent, "Head", P, 0, 4.95, 0, 1.5, skin, M.SmoothPlastic)
	ball(parent, "Hair", P, 0, 5.35, 0.18, 1.45, hair, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		ball(parent, "Eye", P, sx * 0.3, 5, -0.68, 0.2, INK, M.SmoothPlastic)
		ball(parent, "Blush", P, sx * 0.48, 4.72, -0.6, 0.22, rgb(255, 160, 170), M.SmoothPlastic)
	end
	box(parent, "Smile", P, -0.16, 0.16, 4.62, 4.68, -0.74, -0.7, rgb(220, 90, 110), M.SmoothPlastic)
	if hat then
		cyl(parent, "Hat", P, 0, 5.7, 0.05, 0.5, 1.2, hat, M.Fabric)
	end
end

-- Chariot (P : sol, LookVector = avant du chariot) ; ~13 pièces
local function cart(parent: Instance, P: CFrame, handle: Color3?)
	local wire = rgb(186, 190, 200)
	box(parent, "CartBottom", P, -0.85, 0.85, 1.3, 1.4, -1.35, 1.2, wire, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		local side = box(parent, "CartSide", P, sx * 0.85 - 0.03, sx * 0.85 + 0.03, 1.4, 2.9, -1.35, 1.2, wire, M.Metal)
		side.Transparency = 0.35
		box(parent, "CartPost", P, sx * 0.55 - 0.06, sx * 0.55 + 0.06, 0.35, 1.3, 1.02, 1.14, wire, M.Metal)
		cylX(parent, "Wheel", P, sx * 0.62 - 0.1, sx * 0.62 + 0.1, 0.26, -1.05, 0.44, rgb(50, 50, 58), M.Rubber)
		cylX(parent, "Wheel", P, sx * 0.62 - 0.1, sx * 0.62 + 0.1, 0.26, 0.95, 0.44, rgb(50, 50, 58), M.Rubber)
	end
	local front = box(parent, "CartFront", P, -0.82, 0.82, 1.4, 2.9, -1.38, -1.32, wire, M.Metal)
	front.Transparency = 0.35
	local back = box(parent, "CartBack", P, -0.82, 0.82, 1.4, 2.9, 1.17, 1.23, wire, M.Metal)
	back.Transparency = 0.35
	box(parent, "CartTray", P, -0.6, 0.6, 0.45, 0.55, -1.1, 1.1, wire, M.Metal)
	cylX(parent, "CartHandle", P, -0.9, 0.9, 3.05, 1.45, 0.24, handle or BRAND, M.SmoothPlastic)
end

----------------------------------------------------------------------
-- Étiquettes + invites des vrais objets (comme ShopInteriors, v9.6.1)
----------------------------------------------------------------------

local function promptText(entry: ShopUI.Entry): string
	if ShopUI.LockText(entry) then
		return "🔒 " .. Locale.T("Locked")
	end
	if ShopUI.IsMaxed(entry) then
		return "✅ " .. Locale.T("Already yours!")
	end
	return Locale.T("Buy — 🧠 %s", ShopUI.Format(ShopUI.Price(entry)))
end

local function refreshDisplay(d: Display)
	local entry = d.Entry
	local lock = ShopUI.LockText(entry)
	local owned = ShopUI.Owned(entry)
	local labels = d.Labels
	if labels.Price then
		if lock then
			labels.Price.Text = "🔒 " .. lock
			labels.Price.TextColor3 = rgb(130, 100, 200)
		else
			labels.Price.Text = "🧠 " .. ShopUI.Format(ShopUI.Price(entry))
			labels.Price.TextColor3 = HouseCommon.Dopamine() >= ShopUI.Price(entry) and BRAND or rgb(210, 120, 80)
		end
	end
	if labels.Owned then
		labels.Owned.Visible = owned > 0
		labels.Owned.Text = "x" .. tostring(owned)
	end
	if d.Prompt then
		d.Prompt.ActionText = promptText(entry)
	end
end

local function buyDisplay(d: Display)
	local ok = ShopUI.Purchase(d.Entry)
	if ok then
		stats.Purchases += 1
		local tag = d.Tag
		if tag and tag.Parent then
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Name = "Bought"
			sparkle.Color = ColorSequence.new(rgb(255, 150, 200), rgb(255, 230, 120))
			sparkle.LightEmission = 0.2
			sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			sparkle.Lifetime = NumberRange.new(0.6, 1.1)
			sparkle.Speed = NumberRange.new(4, 8)
			sparkle.SpreadAngle = Vector2.new(60, 60)
			sparkle.EmissionDirection = Enum.NormalId.Top
			sparkle.Acceleration = Vector3.new(0, -10, 0)
			sparkle.Rate = 0
			sparkle.Parent = tag
			sparkle:Emit(28)
			task.delay(1.6, function()
				sparkle:Destroy()
			end)
		end
	end
	dirty = true
end

local function addTag(parent: Instance, d: Display, tagCF: CFrame, center: Vector3)
	-- ancre INVISIBLE (v9.6.1 : une étiquette en pièce passait devant le texte)
	local tag = newPart(parent, "PriceTag", Vector3.new(0.4, 0.4, 0.08), tagCF, WHITE, M.SmoothPlastic)
	tag.Transparency = 1
	d.Tag = tag
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAt"
	attachment.WorldPosition = center
	attachment.Parent = tag
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ObjectText = d.Entry.Icon .. " " .. Locale.T(d.Entry.Name)
	prompt.ActionText = promptText(d.Entry)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = attachment
	prompt.Triggered:Connect(function()
		task.spawn(buyDisplay, d)
	end)
	d.Prompt = prompt
	local bb = Instance.new("BillboardGui")
	bb.Name = "PriceLabel"
	bb.Size = UDim2.fromScale(1.9, 0.86)
	bb.StudsOffsetWorldSpace = tagCF.LookVector * 0.25 + Vector3.new(0, -0.1, 0)
	bb.MaxDistance = TAG_DISTANCE
	bb.LightInfluence = 0
	bb.Brightness = 1
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.Parent = tag
	d.Billboard = bb
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = WHITE
	card.BackgroundTransparency = 0.04
	card.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.22, 0)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = BRAND
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	local function text(name: string, value: string, y: number, h: number, color: Color3, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.06, y)
		l.Size = UDim2.fromScale(0.88, h)
		l.Font = font
		l.TextScaled = true
		l.Text = value
		l.TextColor3 = color
		l.Parent = card
		return l
	end
	d.Labels.Name = text("Name", d.Entry.Icon .. " " .. Locale.T(d.Entry.Name), 0.08, 0.42, INK, Enum.Font.GothamBold)
	d.Labels.Price = text("Price", "", 0.52, 0.4, BRAND, Enum.Font.FredokaOne)
	local owned = Instance.new("TextLabel")
	owned.Name = "Owned"
	owned.AnchorPoint = Vector2.new(1, 0)
	owned.Position = UDim2.fromScale(1.02, -0.22)
	owned.Size = UDim2.fromScale(0.3, 0.42)
	owned.BackgroundColor3 = rgb(64, 196, 150)
	owned.Font = Enum.Font.FredokaOne
	owned.TextScaled = true
	owned.TextColor3 = WHITE
	owned.Text = ""
	owned.Visible = false
	owned.Parent = card
	local oc = Instance.new("UICorner")
	oc.CornerRadius = UDim.new(1, 0)
	oc.Parent = owned
	d.Labels.Owned = owned
	refreshDisplay(d)
end

-- Vrai objet de la maison, à la taille de son emplacement
local function buildItem(entry: ShopUI.Entry, slot: Slot): Model?
	local R = Recipes()
	if not R then
		return nil
	end
	local size = math.max(20, tonumber(entry.Def.Size) or 80)
	local scale = math.min(PX, slot.MaxW / size, slot.MaxH / size)
	local opts = { Scale = scale, Collide = false, Query = false, Shadows = false }
	local model: Model? = R.BuildItem(entry.Id, nil, opts)
	if not model then
		return nil
	end
	local fp = model:GetAttribute("Footprint")
	if typeof(fp) == "Vector3" then
		local ratio = math.min(1, slot.MaxW / math.max(0.1, fp.X), slot.MaxH / math.max(0.1, fp.Y), slot.MaxD / math.max(0.1, fp.Z))
		if ratio < 0.95 then
			model:Destroy()
			opts.Scale = scale * ratio
			model = R.BuildItem(entry.Id, nil, opts)
		end
	end
	if model then
		-- (≤ 3 vraies lumières dans le magasin : celles des lampes exposées s'éteignent)
		for _, x in ipairs(model:GetDescendants()) do
			if x:IsA("Light") then
				x:Destroy()
			end
		end
	end
	return model
end

local function placeDisplay(m: Market, parent: Instance, slot: Slot, entry: ShopUI.Entry)
	local model = buildItem(entry, slot)
	local d: Display = { Entry = entry, Model = model, Labels = {} }
	local height = 1
	if model then
		local pivot = slot.CF * CFrame.new(0, 0.02, 0)
		if model:GetAttribute("Wall") == true and slot.WallZ then
			pivot = slot.CF * CFrame.new(0, 0.05, slot.WallZ)
		end
		model:PivotTo(pivot)
		model.Parent = parent
		local fp = model:GetAttribute("Footprint")
		height = typeof(fp) == "Vector3" and fp.Y or height
		stats.Items += 1
		for _, x in ipairs(model:GetDescendants()) do
			if x:IsA("BasePart") then
				partCount += 1
			end
		end
	end
	local center = (slot.CF * CFrame.new(0, math.max(0.5, height / 2), 0)).Position
	addTag(parent, d, slot.Tag, center)
	table.insert(m.Displays, d)
end

-- Échantillon régulier de `k` éléments (du moins cher au plus cher)
local function spread<T>(list: { T }, k: number): { T }
	local n = #list
	if n <= k then
		return table.clone(list)
	end
	local out = {}
	if k <= 0 then
		return out
	end
	if k == 1 then
		out[1] = list[math.ceil(n / 2)]
		return out
	end
	for i = 1, k do
		out[i] = list[math.floor(1 + (i - 1) * (n - 1) / (k - 1) + 0.5)]
	end
	return out
end

local function categoryEntries(categories: { string }): { ShopUI.Entry }
	local list = {}
	local fn = (ShopUI :: any).TabEntries
	for _, id in ipairs(categories) do
		local ok, entries = false, nil
		if type(fn) == "function" then
			ok, entries = pcall(fn, id)
		end
		if ok and type(entries) == "table" then
			for _, e in ipairs(entries) do
				if e.Kind == "Item" then
					table.insert(list, e)
				end
			end
		end
	end
	return list
end

----------------------------------------------------------------------
-- Niveau 1 : dehors (parking, chariots, camion, vitrines)
----------------------------------------------------------------------

local CAR_KINDS = { "CityCar", "Hatchback", "SUV", "BubbleCar", "Van", "CityCar", "Hatchback" }
local CAR_COLORS = { rgb(255, 150, 190), rgb(130, 200, 255), rgb(255, 236, 150), rgb(170, 230, 190), rgb(250, 250, 250), rgb(200, 170, 250), rgb(236, 96, 110) }

local function outsideJobs(m: Market, parent: Instance): { () -> () }
	local jobs: { () -> () } = {}
	local cf = m.MCF
	local lotY = -0.5
	-- voitures garées (rangée A : nez vers le bord ; rangée B : nez vers le magasin)
	local spots = { { "A", 2 }, { "A", 5 }, { "A", 9 }, { "B", 1 }, { "B", 4 }, { "B", 8 }, { "B", 10 } }
	for index, spot in ipairs(spots) do
		table.insert(jobs, function()
			local cm = carModels()
			if not cm or type(cm.Build) ~= "function" then
				return
			end
			local row, i = spot[1], spot[2]
			local x = -33 + (i - 0.5) * 6
			local z = row == "A" and (-51.4 + -41) / 2 or (-28 + -17) / 2
			local rot = row == "A" and CFrame.new() or CFrame.Angles(0, math.pi, 0)
			local ok, model = pcall(cm.Build, CAR_KINDS[index], CAR_COLORS[index], { Detail = "Parked" })
			if ok and typeof(model) == "Instance" and model:IsA("Model") then
				model:PivotTo(cf * CFrame.new(x, lotY, z) * rot)
				model.Parent = parent
				for _, x2 in ipairs(model:GetDescendants()) do
					if x2:IsA("BasePart") then
						partCount += 1
					end
				end
			end
		end)
	end
	-- abris à chariots (2) : barrières + toit + chariots emboîtés
	for _, spot in ipairs({ { -27, -22.5 }, { 21, -46.2 } }) do
		table.insert(jobs, function()
			local x, z = spot[1], spot[2]
			local P = cf * CFrame.new(x, lotY, z)
			for _, sx in ipairs({ -1, 1 }) do
				box(parent, "CorralRail", P, sx * 1.4 - 0.08, sx * 1.4 + 0.08, 0, 2.6, -4.4, 4.4, rgb(176, 180, 190), M.Metal)
			end
			box(parent, "CorralBack", P, -1.4, 1.4, 0, 2.6, 4.32, 4.48, rgb(176, 180, 190), M.Metal)
			local roof = box(parent, "CorralSign", P, -1.6, 1.6, 2.6, 3.4, 4.2, 4.6, BRAND, M.SmoothPlastic)
			label(roof, Enum.NormalId.Front, "🛒", WHITE, nil, 30, 120)
			for k = 0, 2 do
				cart(parent, P * CFrame.new(0, 0, -2.4 + k * 1.4) * CFrame.Angles(0, math.pi, 0))
			end
		end)
	end
	-- chariots laissés devant l'entrée + bacs fleuris de part et d'autre du sas
	table.insert(jobs, function()
		cart(parent, cf * CFrame.new(-11, 0, -4) * CFrame.Angles(0, math.rad(200), 0))
		cart(parent, cf * CFrame.new(13, lotY, -14) * CFrame.Angles(0, math.rad(70), 0))
		for _, sx in ipairs({ -1, 1 }) do
			local P = cf * CFrame.new(sx * 11.2, 0, -3)
			box(parent, "Planter", P, -1.4, 1.4, 0, 1.4, -1, 1, rgb(250, 250, 252), M.SmoothPlastic, true)
			ball(parent, "Bush", P, 0, 2.1, 0, 2.2, rgb(96, 170, 100), M.Grass)
			for k = -1, 1, 2 do
				ball(parent, "Flower", P, k * 0.7, 2.5, -0.6, 0.7, k < 0 and rgb(255, 130, 180) or YELLOW, M.SmoothPlastic)
			end
		end
	end)
	-- affiches collées sur les vitrines (dehors)
	table.insert(jobs, function()
		local posters = {
			{ -29, "PROMO -30%", BRAND },
			{ -21, "🍓 Fresh fruit!", rgb(64, 160, 90) },
			{ 21, "🧸 New toys!", BRAND2 },
			{ 29, "🛋️ Home deals", rgb(230, 130, 60) },
		}
		for _, p in ipairs(posters) do
			local x = p[1] :: number
			local board = box(parent, "Poster", cf, x - 2.4, x + 2.4, 3, 7.6, -0.34, -0.29, WHITE, M.SmoothPlastic)
			label(board, Enum.NormalId.Front, Locale.T(p[2] :: string), WHITE, p[3] :: Color3, 30, 160)
		end
	end)
	-- camion de livraison au quai (à l'arrière)
	table.insert(jobs, function()
		local cm = carModels()
		if not cm or type(cm.Build) ~= "function" then
			return
		end
		local B = cf * CFrame.new(0, 0, m.Size.Z + 2) * CFrame.Angles(0, math.pi, 0)
		local ok, model = pcall(cm.Build, "Van", rgb(250, 250, 252), { Detail = "Parked", Scale = Vector3.new(1.1, 1.15, 1.2) })
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			model:PivotTo(B * CFrame.new(2, -0.6, -12))
			model.Parent = parent
		end
	end)
	return jobs
end

----------------------------------------------------------------------
-- Niveau 2 : l'intérieur complet
----------------------------------------------------------------------

-- Sol, allée centrale, bandeau aux murs, charpente, gaines, rampes lumineuses
local function shell(m: Market, parent: Instance)
	local F = m.F
	local hw, H, D = m.Size.X / 2, m.Size.Y, m.Size.Z
	box(parent, "FloorFinish", F, -hw + GAP, hw - GAP, 0.02, FLOOR_TOP, GAP, D - GAP, rgb(244, 242, 238), M.Marble)
	box(parent, "PowerAisle", F, -hw + 0.5, hw - 0.5, FLOOR_TOP, 0.1, 12, 16.2, rgb(226, 232, 240), M.SmoothPlastic)
	-- bandeau de l'enseigne tout autour (murs)
	box(parent, "WallStripe", F, -hw + 0.1, hw - 0.1, 10.4, 11.2, D - 0.1, D - 0.05, BRAND, M.SmoothPlastic)
	box(parent, "WallStripe", F, -hw + 0.1, hw - 0.1, 11.2, 11.5, D - 0.1, D - 0.05, YELLOW, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "WallStripe", F, sx * (hw - 0.1), sx * (hw - 0.05), 10.4, 11.2, 0.2, D - 0.2, BRAND, M.SmoothPlastic)
		box(parent, "WallStripe", F, sx * (hw - 0.1), sx * (hw - 0.05), 11.2, 11.5, 0.2, D - 0.2, YELLOW, M.SmoothPlastic)
	end
	box(parent, "WallStripe", F, -hw + 0.1, -6.2, 10.4, 11.2, 0.05, 0.1, BRAND, M.SmoothPlastic)
	box(parent, "WallStripe", F, 6.2, hw - 0.1, 10.4, 11.2, 0.05, 0.1, BRAND, M.SmoothPlastic)
	-- charpente apparente (poutres), gaines de ventilation
	for i = 1, 5 do
		local z = i * D / 6
		box(parent, "Truss", F, -hw + 0.1, hw - 0.1, H - 0.8, H - 0.1, z - 0.25, z + 0.25, rgb(214, 216, 224), M.Metal)
	end
	for _, x in ipairs({ -26, 26 }) do
		local duct = newPart(parent, "Duct", Vector3.new(D - 1, 1.4, 1.4), F * CFrame.new(x, H - 1.9, D / 2) * CFrame.Angles(0, math.rad(90), 0), rgb(200, 204, 214), M.Metal)
		;(duct :: Part).Shape = Enum.PartType.Cylinder
	end
	-- rampes d'éclairage (plafonniers blancs mats) : 6 SurfaceLights douces
	local lit = 0
	for _, x in ipairs({ -18, 0, 18 }) do
		for _, z in ipairs({ 10, 22, 33, 42 }) do
			box(parent, "LampHanger", F, x - 0.05, x + 0.05, H - 2.3, H - 0.8, z - 0.05, z + 0.05, rgb(90, 92, 104), M.Metal)
			local panel = box(parent, "LampPanel", F, x - 3, x + 3, H - 2.6, H - 2.3, z - 0.6, z + 0.6, rgb(250, 250, 246), M.SmoothPlastic)
			if (z == 10 or z == 33) and lit < 6 then
				lit += 1
				local sl = Instance.new("SurfaceLight")
				sl.Name = "MarketLight"
				sl.Face = Enum.NormalId.Bottom
				sl.Angle = 120
				sl.Range = 16
				sl.Brightness = 0.6
				sl.Color = rgb(255, 246, 232)
				sl.Shadows = false
				sl.Enabled = m.LightsOn
				sl.Parent = panel
				table.insert(m.Lights, sl)
			end
		end
	end
	-- 3 vraies lumières douces (hautes, au-dessus des allées)
	for _, x in ipairs({ -18, 2, 20 }) do
		local anchor = box(parent, "LightAnchor", F, x - 0.2, x + 0.2, H - 3.4, H - 3, 25.8, 26.2, WHITE, M.SmoothPlastic)
		anchor.Transparency = 1
		local pl = Instance.new("PointLight")
		pl.Name = "MarketLight"
		pl.Brightness = 0.9
		pl.Range = 26
		pl.Color = rgb(255, 244, 226)
		pl.Shadows = false
		pl.Enabled = m.LightsOn
		pl.Parent = anchor
		table.insert(m.Lights, pl)
	end
end

-- Structure d'une gondole (socle, cloison, montants, tablettes, chapeau, tête de gondole)
local function gondola(m: Market, parent: Instance, g: number)
	local F = m.F
	local x = GONDOLA_X[g]
	local grey = rgb(236, 236, 240)
	box(parent, "GondolaBase", F, x - GHALF, x + GHALF, FLOOR_TOP, LEVELS[1], GZ0, GZ1, rgb(96, 100, 116), M.Metal, true)
	box(parent, "GondolaBack", F, x - 0.06, x + 0.06, LEVELS[1], 6.5, GZ0 + 0.15, GZ1 - 0.15, g % 2 == 0 and rgb(214, 226, 246) or rgb(250, 226, 236), M.SmoothPlastic, true)
	for _, z in ipairs({ GZ0, GZ1 - 0.15 }) do
		box(parent, "Upright", F, x - GHALF, x + GHALF, LEVELS[1], 6.6, z, z + 0.15, grey, M.Metal, true)
	end
	box(parent, "GondolaTop", F, x - GHALF - 0.05, x + GHALF + 0.05, 6.6, 6.75, GZ0 - 0.05, GZ1 + 0.05, BRAND, M.SmoothPlastic)
	for side = -1, 1, 2 do
		for level = 2, 4 do
			local y = LEVELS[level]
			local x0, x1 = x + side * 0.06, x + side * GHALF
			local board = box(parent, "Shelf", F, math.min(x0, x1), math.max(x0, x1), y - 0.12, y, GZ0 + 0.15, GZ1 - 0.15, grey, M.Metal)
			board:SetAttribute("Side", side)
		end
	end
	-- tête de gondole côté caisses (promo)
	local z0 = GZ0
	box(parent, "EndCap", F, x - GHALF, x + GHALF, FLOOR_TOP, 0.9, z0 - 1.5, z0 - 0.02, rgb(96, 100, 116), M.Metal, true)
	box(parent, "EndCapShelf", F, x - GHALF, x + GHALF, 2.6, 2.72, z0 - 1.3, z0 - 0.02, rgb(236, 236, 240), M.Metal)
	local sign = box(parent, "PromoSign", F, x - 1.2, x + 1.2, 5.2, 6.4, z0 - 0.3, z0 - 0.22, YELLOW, M.SmoothPlastic)
	label(sign, Enum.NormalId.Front, "PROMO", rgb(200, 40, 60), nil, 40, 60)
	local seed = g * 17
	for k = 0, 1 do
		local xx = x - 0.62 + k * 1.24
		box(parent, "PromoBox", F, xx - 0.55, xx + 0.55, 0.9, 2.1, z0 - 1.25, z0 - 0.15, pick(PALETTE, seed + k, 9), M.SmoothPlastic)
		box(parent, "PromoBox", F, xx - 0.5, xx + 0.5, 2.72, 3.9, z0 - 1.2, z0 - 0.2, pick(PALETTE, seed + k + 5, 9), M.SmoothPlastic)
	end
end

-- Produits d'une face (générique : 4 niveaux ; "Real:" : niveaux 1 et 4 en cartons)
local function faceProducts(m: Market, parent: Instance, index: number)
	local spec = FACES[index]
	local S = faceFrame(m.F, spec[1], spec[2])
	local kind = spec[3] :: string
	local half = (GZ1 - GZ0) / 2 - 0.35
	local seed = index * 101
	local real = string.sub(kind, 1, 5) == "Real:"
	local tint = real and HouseCommon.CategoryTint(string.sub(kind, 6)) or nil
	for level = 1, 4 do
		local y = LEVELS[level]
		local rowKind
		if real then
			if level == 2 or level == 3 then
				continue
			end
			rowKind = "Boxed"
		elseif kind == "Cereal" then
			rowKind = level == 1 and "Boxed" or "Cereal"
		elseif kind == "Drinks" then
			rowKind = level == 1 and "Pack" or "Bottle"
		elseif kind == "Pantry" then
			rowKind = (level == 1 or level == 4) and "Boxed" or "Can"
		elseif kind == "Snacks" then
			rowKind = "Snack"
		else
			rowKind = level == 1 and "Pack" or "Care"
		end
		productRow(parent, S, y, rowKind, seed + level * 13, -half, half, tint)
	end
end

-- Étiquettes de prix sur les tablettes des faces génériques
local function priceTags(m: Market, parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "Shelf" then
			local side = child:GetAttribute("Side")
			local rel = m.F:PointToObjectSpace(child.Position)
			-- (face "Real:" : l'étiquette flottante de chaque objet suffit)
			local gi = 1
			local best = math.huge
			for i, x in ipairs(GONDOLA_X) do
				if math.abs(rel.X - x) < best then
					best, gi = math.abs(rel.X - x), i
				end
			end
			local content = ""
			for _, f in ipairs(FACES) do
				if f[1] == gi and f[2] == side then
					content = f[3] :: string
				end
			end
			if string.sub(content, 1, 5) ~= "Real:" then
				priceStrip(child, side == 1 and Enum.NormalId.Right or Enum.NormalId.Left, math.floor(rel.Y * 10 + gi * 7), 7)
			end
		end
	end
end

-- Vrais objets de la maison sur une face "Real:" (2 niveaux x 4 objets)
local function realSlots(m: Market, index: number): { Slot }
	local spec = FACES[index]
	local S = faceFrame(m.F, spec[1], spec[2])
	local slots = {}
	local len = GZ1 - GZ0 - 0.8
	for _, level in ipairs({ 2, 3 }) do
		local y = LEVELS[level]
		for i = 1, 4 do
			local x = -len / 2 + (i - 0.5) * len / 4
			table.insert(slots, {
				CF = S * CFrame.new(x, y, 0.62),
				MaxW = len / 4 - 0.8,
				MaxH = CLEAR - 0.1,
				MaxD = 1.05,
				Tag = S * CFrame.new(x, y - 0.25, -0.14),
				WallZ = 1.24 - 0.62 - 0.06 - GAP,
			})
		end
	end
	return slots
end

-- Fruits & légumes (étals inclinés le long du mur gauche)
local function produce(m: Market, parent: Instance)
	local F = m.F
	local wood = rgb(196, 150, 104)
	for t, seg in ipairs({ { 15, 21.2 }, { 22, 28.2 }, { 29, 35 } }) do
		local z0, z1 = seg[1], seg[2]
		box(parent, "ProduceBase", F, -33.9, -28, FLOOR_TOP, 2.6, z0, z1, rgb(120, 170, 96), M.WoodPlanks, true)
		-- plateau incliné vers l'allée
		local top = newPart(parent, "ProduceTable", Vector3.new(5.6, 0.25, z1 - z0), F * CFrame.new(-31, 3.05, (z0 + z1) / 2) * CFrame.Angles(0, 0, math.rad(-14)), wood, M.WoodPlanks)
		top.CanCollide = true
		-- cagettes + fruits
		local nz = math.floor((z1 - z0) / 2)
		for k = 0, nz - 1 do
			for c = 0, 1 do
				local zc = z0 + 0.1 + (k + 0.5) * (z1 - z0 - 0.2) / nz
				local xc = -32.2 + c * 2.3
				local lift = 3.35 + (c == 0 and 0.28 or -0.28)
				local crate = CFrame.new(xc, lift, zc)
				local P = F * CFrame.new(-31, 3.05, 0) * CFrame.Angles(0, 0, math.rad(-14)) * CFrame.new(xc + 31, 0.13, zc)
				local _ = crate
				local fruit = FRUITS[((t * 5 + k * 2 + c) % #FRUITS) + 1]
				newPart(parent, "Crate", Vector3.new(2.1, 0.5, (z1 - z0 - 0.2) / nz - 0.15), P * CFrame.new(0, 0.25, 0), wood:Lerp(WHITE, 0.2), M.WoodPlanks)
				local color, dia = fruit[1] :: Color3, fruit[2] :: number
				local count = math.max(2, math.floor(1.7 / dia))
				for q = 0, count - 1 do
					local qx = -0.85 + (q + 0.5) * 1.7 / count
					ball(parent, "Fruit", P * CFrame.new(0, 0, 0), qx, 0.5 + dia / 2 - 0.05, 0, dia, color, M.SmoothPlastic)
				end
			end
		end
	end
	-- balance + panneau
	box(parent, "Scale", F, -28.4, -27.4, 2.6, 3, 21.3, 21.9, rgb(236, 236, 240), M.Metal)
	local sign = box(parent, "DeptSign", F, -33.95, -33.9, 7, 9.2, 17, 31, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Right, Locale.T("🍎 Fruit & veg"), rgb(64, 150, 90), WHITE, 20, 90)
end

-- Boulangerie (coin arrière gauche) : vitrine, pains, boulanger·ère
local function bakery(m: Market, parent: Instance)
	local F = m.F
	local wood = rgb(206, 160, 110)
	box(parent, "BakeryCounter", F, -33.9, -23.5, FLOOR_TOP, 3.2, 38.4, 40.2, wood, M.Wood, true)
	box(parent, "BakeryFront", F, -33.7, -23.7, 0.5, 2.9, 38.33, 38.38, rgb(255, 230, 200), M.SmoothPlastic)
	local case = box(parent, "BakeryCase", F, -33.6, -24, 3.2, 5, 38.5, 40.1, rgb(220, 240, 250), M.Glass)
	case.Transparency = 0.55
	for i = 0, 6 do
		local x = -32.8 + i * 1.3
		if i % 2 == 0 then
			ball(parent, "Pastry", F, x, 3.55, 39.3, 0.7, rgb(236, 170, 90), M.SmoothPlastic)
		else
			box(parent, "Cake", F, x - 0.45, x + 0.45, 3.2, 3.8, 38.95, 39.65, i == 3 and rgb(255, 180, 210) or rgb(250, 240, 220), M.SmoothPlastic)
		end
	end
	-- étagères à pain contre le mur du fond
	box(parent, "BreadRack", F, -33, -25, FLOOR_TOP, 6.2, 44.4, 45.9, wood, M.Wood, true)
	for level = 0, 2 do
		local y = 2.2 + level * 1.5
		box(parent, "BreadShelf", F, -33, -25, y - 0.1, y, 43.9, 44.4, wood:Lerp(WHITE, 0.2), M.Wood)
		for k = 0, 4 do
			local x = -32.3 + k * 1.6
			local loaf = newPart(parent, "Loaf", Vector3.new(1.3, 0.55, 0.55), F * CFrame.new(x, y + 0.27, 44.15) * CFrame.Angles(0, math.rad(20), 0), rgb(214, 150, 80), M.SmoothPlastic)
			;(loaf :: Part).Shape = Enum.PartType.Cylinder
		end
	end
	figure(parent, F * CFrame.new(-28.5, FLOOR_TOP, 42) * CFrame.Angles(0, 0, 0), rgb(250, 250, 252), rgb(236, 180, 120), rgb(150, 100, 70), WHITE)
	local sign = box(parent, "DeptSign", F, -33, -24.5, 7.4, 9.4, 45.9, 45.95, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Front, Locale.T("🥖 Bakery"), rgb(170, 110, 60), WHITE, 20, 90)
end

-- Frigos à portes vitrées (mur du fond) + bacs de surgelés
local function fridges(m: Market, parent: Instance)
	local F = m.F
	local x0, x1 = -21, 7
	local units = 7
	local uw = (x1 - x0) / units
	box(parent, "FridgeBody", F, x0, x1, FLOOR_TOP, 8.2, 43.4, 45.95, rgb(246, 246, 250), M.SmoothPlastic, true)
	box(parent, "FridgeInside", F, x0 + 0.2, x1 - 0.2, 0.6, 7.6, 43.35, 43.4, rgb(226, 236, 246), M.SmoothPlastic)
	local header = box(parent, "FridgeHeader", F, x0, x1, 8.2, 9.4, 43.2, 45.95, rgb(80, 150, 230), M.SmoothPlastic)
	label(header, Enum.NormalId.Front, Locale.T("❄️ Fresh & frozen"), WHITE, nil, 20, 90)
	for u = 0, units - 1 do
		local ux0 = x0 + u * uw
		local cx = ux0 + uw / 2
		-- tablettes + produits (bouteilles de lait, jus, yaourts)
		for level = 0, 2 do
			local y = 1.1 + level * 2.2
			box(parent, "FridgeShelf", F, ux0 + 0.25, ux0 + uw - 0.25, y - 0.1, y, 42.2, 43.35, rgb(220, 226, 236), M.Metal)
			for k = 0, 3 do
				local x = ux0 + 0.62 + k * (uw - 1.24) / 3
				local color = pick(PASTEL, u * 11 + level * 3 + k, 21)
				if (u + level) % 2 == 0 then
					cyl(parent, "Milk", F, x, y, 42.75, 1.2, 0.5, color, M.SmoothPlastic)
				else
					box(parent, "Yogurt", F, x - 0.3, x + 0.3, y, y + 0.8, 42.45, 43.05, color, M.SmoothPlastic)
				end
			end
		end
		-- porte vitrée + poignée
		local door = box(parent, "FridgeDoor", F, ux0 + 0.08, ux0 + uw - 0.08, 0.5, 7.8, 42, 42.1, rgb(214, 234, 250), M.Glass)
		door.Transparency = 0.6
		box(parent, "FridgeFrame", F, ux0, ux0 + 0.08, 0.4, 7.9, 41.95, 43.4, rgb(200, 204, 214), M.Metal)
		box(parent, "FridgeHandle", F, cx + uw / 2 - 0.5, cx + uw / 2 - 0.35, 3, 5.4, 41.8, 41.95, rgb(176, 180, 190), M.Metal)
	end
	box(parent, "FridgeFrame", F, x1 - 0.08, x1, 0.4, 7.9, 41.95, 43.4, rgb(200, 204, 214), M.Metal)
	box(parent, "FridgeKick", F, x0, x1, FLOOR_TOP, 0.5, 41.95, 43.4, rgb(96, 100, 116), M.Metal)
	-- bacs de surgelés (couvercles vitrés)
	for i = 0, 2 do
		local bx0 = -19 + i * 8.6
		box(parent, "Freezer", F, bx0, bx0 + 7.6, FLOOR_TOP, 2.8, 37.9, 40.3, rgb(236, 240, 246), M.SmoothPlastic, true)
		box(parent, "FreezerBand", F, bx0 + 0.2, bx0 + 7.4, 1.2, 1.7, 37.85, 37.9, rgb(80, 150, 230), M.SmoothPlastic)
		for k = 0, 5 do
			local x = bx0 + 0.75 + k * 1.2
			box(parent, "FrozenBox", F, x - 0.5, x + 0.5, 2.8, 3.25, 38.3, 39.9, pick(PALETTE, i * 7 + k, 23), M.SmoothPlastic)
		end
		local lid = box(parent, "FreezerLid", F, bx0 + 0.1, bx0 + 7.5, 3.35, 3.45, 38, 40.2, rgb(214, 234, 250), M.Glass)
		lid.Transparency = 0.6
	end
end

-- Électronique : mur de télés + comptoir (vrais objets)
local function electronicsDecor(m: Market, parent: Instance)
	local F = m.F
	for i = 0, 5 do
		local x = 15.5 + i * 3.1
		local y0 = i % 2 == 0 and 5 or 5.4
		box(parent, "TVFrame", F, x - 1.4, x + 1.4, y0, y0 + 1.8, 45.7, 45.95, rgb(30, 30, 38), M.SmoothPlastic)
		local screen = box(parent, "TVScreen", F, x - 1.28, x + 1.28, y0 + 0.1, y0 + 1.7, 45.65, 45.7, rgb(60, 110, 190):Lerp(rgb(150, 230, 255), (i % 3) / 3), M.SmoothPlastic)
		local _ = screen
	end
	box(parent, "TechCounter", F, 15, 33.5, FLOOR_TOP, 2.6, 42.6, 44.8, rgb(60, 64, 80), M.SmoothPlastic, true)
	box(parent, "TechTop", F, 14.8, 33.7, 2.6, 2.75, 42.4, 45, rgb(236, 236, 240), M.Metal)
	local sign = box(parent, "DeptSign", F, 16, 33, 7.8, 9.6, 45.9, 45.95, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Front, Locale.T("📺 Electronics"), rgb(60, 90, 180), WHITE, 20, 90)
end

local function electronicsSlots(m: Market): { Slot }
	local slots = {}
	for i = 1, 6 do
		local x = 15.8 + (i - 0.5) * 17.6 / 6
		-- (repère tourné : LookVector vers l'allée, -Z monde intérieur)
		local S = m.F * CFrame.new(x, 2.75, 43.7)
		table.insert(slots, { CF = S, MaxW = 2.4, MaxH = 2.8, MaxD = 1.8, Tag = m.F * CFrame.new(x, 2.3, 42.45), WallZ = 1.0 })
	end
	return slots
end

-- Jardin : gradins le long du mur droit (vrais objets "Plants")
local function gardenDecor(m: Market, parent: Instance)
	local F = m.F
	local green = rgb(96, 150, 96)
	for s, seg in ipairs({ { 16, 22.5 }, { 23.5, 30 }, { 31, 37.5 } }) do
		local z0, z1 = seg[1], seg[2]
		for step = 0, 2 do
			local x0 = 29.6 + step * 1.45
			box(parent, "GardenStep", F, x0, 33.95, FLOOR_TOP, 0.9 + step * 1.3, z0, z1, green:Lerp(WHITE, step * 0.08), M.WoodPlanks, true)
		end
		-- pots en terre cuite sur la marche haute
		for k = 0, 1 do
			local z = z0 + 1.2 + k * (z1 - z0 - 2.4)
			cyl(parent, "Pot", F, 33.2, 3.5, z, 0.9, 0.9, rgb(206, 124, 90), M.Slate)
			ball(parent, "Leaves", F, 33.2, 4.8, z, 1.4, rgb(90, 170, 90):Lerp(YELLOW, hash(s, k) * 0.3), M.Grass)
		end
	end
	-- sacs de terreau
	for i = 0, 2 do
		box(parent, "SoilBag", F, 26.4, 28.4, FLOOR_TOP + i * 0.72, FLOOR_TOP + 0.7 + i * 0.72, 38.4 + i * 0.1, 40.8 - i * 0.1, i % 2 == 0 and rgb(96, 70, 50) or rgb(120, 160, 80), M.Fabric)
	end
	local sign = box(parent, "DeptSign", F, 33.9, 33.95, 7, 9.2, 18, 36, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Left, Locale.T("🪴 Garden"), rgb(64, 140, 80), WHITE, 20, 90)
end

local function gardenSlots(m: Market): { Slot }
	local slots = {}
	for _, seg in ipairs({ { 16, 22.5 }, { 23.5, 30 }, { 31, 37.5 } }) do
		local z0, z1 = seg[1], seg[2]
		for step = 0, 1 do
			for k = 0, 1 do
				local x = 29.6 + step * 1.45 + 0.72
				local z = z0 + 1.6 + k * (z1 - z0 - 3.2)
				local y = 0.9 + step * 1.3
				local S = m.F * CFrame.new(x, y, z) * FACE_NX
				table.insert(slots, { CF = S, MaxW = 1.4, MaxH = 2.4, MaxD = 1.3, Tag = m.F * CFrame.new(x - 0.8, y - 0.2, z) * FACE_NX })
			end
		end
	end
	return slots
end

-- Vêtements : 3 portants ronds
local function clothes(m: Market, parent: Instance)
	local F = m.F
	for r, z in ipairs({ 20, 26.5, 33 }) do
		local x = 20.5
		cyl(parent, "RackBase", F, x, FLOOR_TOP, z, 0.2, 1.6, rgb(176, 180, 190), M.Metal, true)
		cyl(parent, "RackPole", F, x, FLOOR_TOP + 0.2, z, 4.4, 0.18, rgb(176, 180, 190), M.Metal)
		local ring = newPart(parent, "RackRing", Vector3.new(0.12, 3, 3), F * CFrame.new(x, 4.55, z) * CFrame.Angles(0, 0, math.rad(90)), rgb(176, 180, 190), M.Metal)
		;(ring :: Part).Shape = Enum.PartType.Cylinder
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2 + r
			local px, pz = x + math.cos(a) * 1.4, z + math.sin(a) * 1.4
			local shirt = newPart(parent, "Shirt", Vector3.new(1.1, 1.7, 0.18), CFrame.new((F * CFrame.new(px, 3.65, pz)).Position) * (F - F.Position) * CFrame.Angles(0, -a + math.pi / 2, 0), pick(PALETTE, r * 9 + k, 31), M.Fabric)
			local _ = shirt
		end
	end
	local sign = box(parent, "ClothesSign", F, 19.3, 21.7, 5.3, 6.1, 25.9, 25.95, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Front, Locale.T("👕 Clothes"), BRAND2, WHITE, 30, 60)
end

-- Panneaux d'allées suspendus (numéro + rayons, deux faces)
local function aisleSigns(m: Market, parent: Instance)
	local F = m.F
	local H = m.Size.Y
	for _, a in ipairs(AISLES) do
		local x = a[1] :: number
		local z = (GZ0 + GZ1) / 2
		for _, dz in ipairs({ -0.6, 0.6 }) do
			box(parent, "SignCord", F, x + dz * 2 - 0.03, x + dz * 2 + 0.03, 11.6, H - 0.8, z - 0.03, z + 0.03, rgb(90, 92, 104), M.Metal)
		end
		local board = box(parent, "AisleSign", F, x - 2.6, x + 2.6, 9.6, 11.6, z - 0.08, z + 0.08, BRAND2, M.SmoothPlastic)
		local text = a[2] .. "  " .. Locale.T(a[3] :: string) .. " · " .. Locale.T(a[4] :: string)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			label(board, face, text, WHITE, nil, 24, 120)
		end
		local num = box(parent, "AisleNumber", F, x - 0.7, x + 0.7, 11.6, 12.9, z - 0.1, z + 0.1, YELLOW, M.SmoothPlastic)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			label(num, face, a[2] :: string, BRAND2, nil, 30, 120)
		end
	end
end

-- Caisses : 4 caisses tenues + 4 caisses automatiques ; invites "Passer en caisse"
local function checkoutPrompt(m: Market, parent: Instance, at: CFrame)
	local anchor = newPart(parent, "CheckoutPoint", Vector3.new(1, 1, 1), at, WHITE, M.SmoothPlastic)
	anchor.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CheckoutPrompt"
	prompt.ActionText = Locale.T("🛒 Checkout")
	prompt.ObjectText = Locale.T("🛒 MegaDopa")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	local pos = anchor.Position
	table.insert(m.Checkouts, pos)
	prompt.Triggered:Connect(function()
		ShopUI.OpenShop("Market", { Anchor = pos })
	end)
end

local CASHIERS = {
	{ rgb(236, 72, 140), rgb(90, 60, 50) },
	{ rgb(120, 90, 200), rgb(250, 210, 120) },
	{ rgb(64, 180, 150), rgb(40, 40, 50) },
	{ rgb(255, 150, 90), rgb(200, 110, 60) },
}

local function checkoutLane(m: Market, parent: Instance, i: number)
	local F = m.F
	local x = LANES[i]
	local z0, z1 = 3, 10.5
	-- meuble de caisse + bande de couleur + tapis roulant
	box(parent, "Checkout", F, x - 0.9, x + 0.9, FLOOR_TOP, 3, z0, z1, rgb(246, 246, 250), M.SmoothPlastic, true)
	box(parent, "CheckoutStripe", F, x + 0.9, x + 0.95, 1.2, 1.8, z0 + 0.2, z1 - 0.2, BRAND, M.SmoothPlastic)
	box(parent, "Belt", F, x - 0.72, x + 0.72, 3, 3.1, 5.4, z1 - 0.15, rgb(34, 34, 40), M.Rubber)
	cylX(parent, "BeltRoller", F, x - 0.74, x + 0.74, 3.05, z1 - 0.15, 0.22, rgb(150, 150, 164), M.Metal)
	box(parent, "Divider", F, x - 0.6, x + 0.6, 3.1, 3.35, 8.2, 8.5, BRAND2, M.SmoothPlastic)
	-- articles sur le tapis
	for k = 0, 2 do
		local zz = 6 + k * 0.9
		box(parent, "Groceries", F, x - 0.35, x + 0.35, 3.1, 3.6 + (k % 2) * 0.3, zz, zz + 0.6, pick(PALETTE, i * 5 + k, 41), M.SmoothPlastic)
	end
	-- caisse enregistreuse, écran incliné, terminal de carte, zone d'ensachage
	box(parent, "Register", F, x - 0.8, x + 0.1, 3, 3.7, z0 + 0.3, z0 + 1.6, rgb(70, 66, 90), M.SmoothPlastic)
	local screen = box(parent, "RegisterScreen", F, x - 0.75, x + 0.05, 3.9, 4.9, z0 + 1.1, z0 + 1.2, rgb(40, 38, 56), M.SmoothPlastic)
	screen.CFrame *= CFrame.Angles(math.rad(-12), 0, 0)
	box(parent, "ScreenStalk", F, x - 0.4, x - 0.3, 3.7, 3.95, z0 + 1.1, z0 + 1.2, rgb(90, 92, 104), M.Metal)
	box(parent, "CardPost", F, x + 0.95, x + 1.05, 3, 4, z0 + 2.5, z0 + 2.6, rgb(90, 92, 104), M.Metal)
	box(parent, "CardTerminal", F, x + 0.8, x + 1.2, 4, 4.7, z0 + 2.35, z0 + 2.75, rgb(40, 40, 50), M.SmoothPlastic)
	box(parent, "BagArea", F, x - 0.8, x + 0.8, 3, 3.08, z0 + 0.05, z0 + 0.3, rgb(214, 216, 224), M.Metal)
	-- lampe numérotée au bout de la caisse
	box(parent, "LanePole", F, x - 0.08, x + 0.08, 3, 8.4, z1 - 0.5, z1 - 0.34, rgb(176, 180, 190), M.Metal)
	local lamp = box(parent, "LaneLight", F, x - 0.6, x + 0.6, 8.4, 9.6, z1 - 0.62, z1 - 0.22, i == 3 and rgb(236, 110, 110) or rgb(120, 220, 150), M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		label(lamp, face, tostring(i), WHITE, nil, 40, 90)
	end
	-- caissier·ère (du côté -X, tourné vers le client)
	local c = CASHIERS[(i - 1) % #CASHIERS + 1]
	figure(parent, F * CFrame.new(x - 1.55, FLOOR_TOP, z0 + 3.2) * FACE_PX, rgb(250, 250, 252), c[1], c[2], nil)
	-- invite côté client
	checkoutPrompt(m, parent, F * CFrame.new(x + 1.9, 3.6, z0 + 2.4))
end

local function selfCheckout(m: Market, parent: Instance)
	local F = m.F
	for i = 0, 3 do
		local x = -31 + i * 4.4
		local z = 5
		box(parent, "SelfBase", F, x - 1, x + 1, FLOOR_TOP, 3, z - 0.8, z + 0.8, rgb(246, 246, 250), M.SmoothPlastic, true)
		box(parent, "Scanner", F, x - 0.8, x + 0.8, 3, 3.12, z - 0.6, z + 0.6, rgb(40, 40, 50), M.Glass)
		box(parent, "SelfPost", F, x - 0.1, x + 0.1, 3, 5, z + 0.55, z + 0.7, rgb(176, 180, 190), M.Metal)
		local screen = box(parent, "SelfScreen", F, x - 0.8, x + 0.8, 4.4, 5.6, z + 0.4, z + 0.52, rgb(80, 150, 230), M.SmoothPlastic)
		local _ = screen
		box(parent, "BagStand", F, x + 1, x + 1.9, FLOOR_TOP, 3, z - 0.6, z + 0.6, rgb(214, 216, 224), M.Metal)
		checkoutPrompt(m, parent, F * CFrame.new(x, 3.6, z - 1.4))
	end
	local sign = box(parent, "SelfSign", F, -32, -18, 9.2, 10.6, 5.9, 6.1, BRAND2, M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		label(sign, face, Locale.T("🤖 Self-checkout"), WHITE, nil, 24, 90)
	end
	for _, dz in ipairs({ -5, 5 }) do
		box(parent, "SelfSignCord", F, -25 + dz - 0.03, -25 + dz + 0.03, 10.6, m.Size.Y - 0.8, 5.97, 6.03, rgb(90, 92, 104), M.Metal)
	end
	-- pupitre de l'hôte·sse des caisses automatiques
	box(parent, "Podium", F, -16.4, -15.2, FLOOR_TOP, 3.4, 8, 9.2, BRAND, M.SmoothPlastic, true)
	figure(parent, F * CFrame.new(-15.8, FLOOR_TOP, 10.4) * CFrame.Angles(0, math.pi, 0), rgb(250, 250, 252), BRAND2, rgb(60, 40, 40), nil)
end

-- Entrée : chariots, paniers, portiques antivol, palette promo, file d'attente
local function entrance(m: Market, parent: Instance)
	local F = m.F
	for k = 0, 5 do
		cart(parent, F * CFrame.new(-10.5, FLOOR_TOP, 2.2 + k * 1.3), rgb(236, 72, 140))
	end
	-- paniers empilés
	box(parent, "Baskets", F, -8, -6.8, FLOOR_TOP, 1.8, 9.6, 10.6, rgb(236, 72, 90), M.SmoothPlastic)
	box(parent, "BasketHandles", F, -8.05, -6.75, 1.8, 2.1, 10, 10.2, rgb(40, 40, 50), M.SmoothPlastic)
	-- portiques antivol
	for _, x in ipairs({ -6.4, 6.4 }) do
		box(parent, "Gate", F, x - 0.12, x + 0.12, FLOOR_TOP, 5.2, 0.8, 2.2, rgb(200, 204, 214), M.Metal)
		box(parent, "GateFoot", F, x - 0.3, x + 0.3, FLOOR_TOP, 0.3, 0.7, 2.3, rgb(90, 92, 104), M.Metal)
	end
	-- palette promo dans l'axe de l'entrée
	box(parent, "Pallet", F, -2.2, 2.2, FLOOR_TOP, 0.5, 12.4, 15.8, rgb(196, 150, 104), M.WoodPlanks, true)
	for i = 0, 5 do
		local x = -1.4 + (i % 3) * 1.4
		local zz = 13.2 + math.floor(i / 3) * 1.7
		box(parent, "PromoCase", F, x - 0.62, x + 0.62, 0.5, 1.6, zz - 0.75, zz + 0.75, pick(PALETTE, i + 60, 51), M.SmoothPlastic)
	end
	box(parent, "PalletTop", F, -1.3, 1.3, 1.6, 2.6, 13.4, 14.8, YELLOW, M.SmoothPlastic)
	local sign = box(parent, "PalletSign", F, -1.6, 1.6, 3.2, 5, 14.05, 14.15, WHITE, M.SmoothPlastic)
	box(parent, "PalletPole", F, -0.06, 0.06, 2.6, 3.2, 14.04, 14.16, rgb(90, 92, 104), M.Metal)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		label(sign, face, Locale.T("🧠 Brainy deals!"), BRAND, WHITE, 40, 70)
	end
	-- barrières de file d'attente (caisse 1)
	local qx0, qx1 = LANES[1] + 1.2, LANES[1] + 4
	for _, x in ipairs({ qx0, qx1 }) do
		for _, z in ipairs({ 11.2, 13.4, 15.6 }) do
			cyl(parent, "QueuePost", F, x, FLOOR_TOP, z, 3, 0.25, rgb(176, 180, 190), M.Metal)
			cyl(parent, "QueueFoot", F, x, FLOOR_TOP, z, 0.12, 0.8, rgb(90, 92, 104), M.Metal)
		end
		box(parent, "QueueBelt", F, x - 0.04, x + 0.04, 2.55, 2.85, 11.2, 15.6, BRAND, M.Fabric)
	end
	-- tapis d'accueil
	box(parent, "Welcome", F, -5.4, 5.4, FLOOR_TOP, 0.11, 0.3, 3.6, BRAND2, M.Fabric)
end

-- Clients (statiques) qui poussent leur chariot dans les allées
local function shoppers(m: Market, parent: Instance)
	local F = m.F
	for _, s in ipairs({ { -7.25, 24, 0, rgb(120, 200, 250), rgb(250, 200, 120) }, { 9.75, 30, math.pi, rgb(255, 170, 200), rgb(80, 50, 40) } }) do
		local x, z, rot = s[1] :: number, s[2] :: number, s[3] :: number
		local P = F * CFrame.new(x, FLOOR_TOP, z) * CFrame.Angles(0, rot, 0)
		figure(parent, P * CFrame.new(0, 0, 1.8) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, math.pi, 0), s[4] :: Color3, nil, s[5] :: Color3, nil)
		cart(parent, P * CFrame.new(0, 0, -0.6) * CFrame.Angles(0, math.pi, 0), BRAND2)
		-- quelques courses dans le chariot
		for k = 0, 2 do
			box(parent, "Groceries", P, -0.5 + k * 0.5 - 0.2, -0.5 + k * 0.5 + 0.2, 1.4, 2.1 + (k % 2) * 0.3, -1.1 + k * 0.4, -0.5 + k * 0.4, pick(PALETTE, k + x, 61), M.SmoothPlastic)
		end
	end
end

local function fullJobs(m: Market, parent: Instance): { () -> () }
	local jobs: { () -> () } = {}
	table.insert(jobs, function()
		shell(m, parent)
	end)
	for g = 1, #GONDOLA_X do
		table.insert(jobs, function()
			gondola(m, parent, g)
		end)
	end
	for index = 1, #FACES do
		table.insert(jobs, function()
			faceProducts(m, parent, index)
		end)
	end
	table.insert(jobs, function()
		priceTags(m, parent)
	end)
	for i = 1, #LANES do
		table.insert(jobs, function()
			checkoutLane(m, parent, i)
		end)
	end
	table.insert(jobs, function()
		selfCheckout(m, parent)
	end)
	table.insert(jobs, function()
		entrance(m, parent)
	end)
	table.insert(jobs, function()
		produce(m, parent)
	end)
	table.insert(jobs, function()
		bakery(m, parent)
	end)
	table.insert(jobs, function()
		fridges(m, parent)
	end)
	table.insert(jobs, function()
		electronicsDecor(m, parent)
		gardenDecor(m, parent)
	end)
	table.insert(jobs, function()
		clothes(m, parent)
		aisleSigns(m, parent)
	end)
	table.insert(jobs, function()
		shoppers(m, parent)
	end)
	-- vrais objets de la maison : rayons, électronique, jardin
	local placements: { { Slot: Slot, Entry: ShopUI.Entry } } = {}
	for index, spec in ipairs(FACES) do
		local kind = spec[3] :: string
		if string.sub(kind, 1, 5) == "Real:" then
			local category = string.sub(kind, 6)
			local categories = category == "Gaming" and { "Gaming", "Setup" } or { category }
			local slots = realSlots(m, index)
			for i, entry in ipairs(spread(categoryEntries(categories), #slots)) do
				table.insert(placements, { Slot = slots[i], Entry = entry })
			end
		end
	end
	local tech = electronicsSlots(m)
	for i, entry in ipairs(spread(categoryEntries({ "Electronics" }), #tech)) do
		table.insert(placements, { Slot = tech[i], Entry = entry })
	end
	local garden = gardenSlots(m)
	for i, entry in ipairs(spread(categoryEntries({ "Plants" }), #garden)) do
		table.insert(placements, { Slot = garden[i], Entry = entry })
	end
	for _, p in ipairs(placements) do
		table.insert(jobs, function()
			placeDisplay(m, parent, p.Slot, p.Entry)
		end)
	end
	return jobs
end

----------------------------------------------------------------------
-- Construction par niveaux / destruction
----------------------------------------------------------------------

local function tierFolder(m: Market, level: number): Folder
	local existing = m.Tiers[level]
	if existing and existing.Parent then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = level == 1 and "Market_Outside" or "Market_Full"
	f.Parent = folder
	m.Tiers[level] = f
	return f
end

local function downgrade(m: Market, level: number)
	for tier = 2, level + 1, -1 do
		local f = m.Tiers[tier]
		if f then
			if tier == 2 then
				table.clear(m.Displays)
				table.clear(m.Lights)
				table.clear(m.Checkouts)
				m.LightsOn = false
			end
			f:Destroy()
			m.Tiers[tier] = nil
			stats.Destroyed += 1
		end
	end
	if m.Building > level then
		m.Jobs = nil
		m.Building = 0
	end
	m.Level = math.min(m.Level, level)
end

----------------------------------------------------------------------
-- Portes coulissantes
----------------------------------------------------------------------

local function stepDoors(m: Market, positions: { Vector3 })
	local door = m.DoorCF.Position
	local near = false
	for _, p in ipairs(positions) do
		if (p - door).Magnitude < DOOR_RANGE then
			near = true
			break
		end
	end
	for _, d in ipairs(m.Doors) do
		if d.IsOpen ~= near then
			d.IsOpen = near
			local goal = near and d.Open or d.Closed
			local ok = pcall(function()
				TweenService:Create(d.Part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal }):Play()
			end)
			if not ok then
				d.Part.CFrame = goal
			end
		end
	end
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function characterPositions(): { Vector3 }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(list, root.Position)
		end
	end
	return list
end

local function localPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return focus
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Dans le magasin (boîte intérieure, un peu élargie) ?
local function inside(m: Market, p: Vector3): boolean
	local rel = m.InteriorCF:PointToObjectSpace(p)
	local s = m.Size
	return math.abs(rel.X) < s.X / 2 + 0.5 and math.abs(rel.Z) < s.Z / 2 + 0.5 and rel.Y > -2 and rel.Y < s.Y + 2
end

-- Étiquettes : seulement dans le magasin, les MAX_TAGS plus proches (v9.6.1)
local function updateTags(m: Market, position: Vector3)
	local here = inside(m, position)
	local candidates: { { d: Display, dist: number } } = {}
	for _, d in ipairs(m.Displays) do
		local bb = d.Billboard
		if bb and bb.Parent and d.Tag then
			local dist = (d.Tag.Position - position).Magnitude
			if here and dist <= TAG_DISTANCE then
				table.insert(candidates, { d = d, dist = dist })
			else
				bb.Enabled = false
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)
	for i, c in ipairs(candidates) do
		(c.d.Billboard :: BillboardGui).Enabled = i <= MAX_TAGS
	end
end

local function decide(m: Market, position: Vector3)
	local d = flatDistance(position, m.InteriorCF.Position)
	local target = 0
	if d <= FULL_RANGE or (m.Level >= 2 and d <= FULL_DROP) then
		target = 2
	elseif d <= OUT_RANGE or (m.Level >= 1 and d <= OUT_DROP) then
		target = 1
	end
	m.Target = target
	if m.Level > target or m.Building > target then
		downgrade(m, target)
	end
	local on = inside(m, position)
	if on ~= m.LightsOn then
		m.LightsOn = on
		for _, light in ipairs(m.Lights) do
			light.Enabled = on
		end
	end
	if m.Building == 0 and target > m.Level then
		local level = m.Level + 1
		local parent = tierFolder(m, level)
		m.Building = level
		m.Jobs = level == 1 and outsideJobs(m, parent) or fullJobs(m, parent)
		m.JobIndex = 1
	end
end

local function runJobs(m: Market)
	local jobs = m.Jobs
	if not jobs then
		return
	end
	local t0 = os.clock()
	repeat
		local job = jobs[m.JobIndex]
		if job then
			local ok, err = pcall(job)
			if not ok then
				warn("[MarketInterior] " .. tostring(err))
			end
		end
		m.JobIndex += 1
	until m.JobIndex > #jobs or os.clock() - t0 > STEP_BUDGET
	stats.Parts = partCount
	if m.JobIndex > #jobs then
		m.Jobs = nil
		m.Level = m.Building
		m.Building = 0
		stats.Built += 1
		dirty = true
		-- lumières créées éteintes : on les allume si on est déjà dedans
		for _, light in ipairs(m.Lights) do
			light.Enabled = m.LightsOn
		end
	end
end

local function refreshAll(m: Market)
	for _, d in ipairs(m.Displays) do
		if d.Tag then
			refreshDisplay(d)
		end
	end
end

function MarketInterior.Step(position: Vector3?)
	if typeof(position) == "Vector3" then
		focus = position
	end
end

local function heartbeat(dt: number)
	local m = market
	if not started or not m then
		return
	end
	runJobs(m)
	clock += dt
	if clock < STEP_EVERY then
		return
	end
	clock = 0
	local position = localPosition()
	if position then
		decide(m, position)
		pcall(updateTags, m, position)
	end
	if m.Level >= 1 then
		stepDoors(m, characterPositions())
	end
	if dirty then
		dirty = false
		refreshAll(m)
	end
end

----------------------------------------------------------------------
-- Démarrer / arrêter
----------------------------------------------------------------------

local function discover(): Market?
	local town = workspace:FindFirstChild("DopamineTown")
	local container = town and town:FindFirstChild("Market")
	local model = container and container:FindFirstChild("Supermarket")
	if not model or not model:IsA("Model") then
		return nil
	end
	local mcf = model:GetAttribute("MarketCF")
	local icf = model:GetAttribute("InteriorCF")
	local size = model:GetAttribute("InteriorSize")
	local doorCF = model:GetAttribute("DoorCF")
	if typeof(mcf) ~= "CFrame" or typeof(icf) ~= "CFrame" or typeof(size) ~= "Vector3" or typeof(doorCF) ~= "CFrame" then
		return nil
	end
	local m: Market = {
		Model = model,
		MCF = mcf,
		F = icf * CFrame.new(0, 0, -size.Z / 2),
		Size = size,
		InteriorCF = icf,
		DoorCF = doorCF,
		StallsA = tonumber(model:GetAttribute("StallsA")) or 11,
		StallsB = tonumber(model:GetAttribute("StallsB")) or 11,
		Level = 0,
		Target = 0,
		Tiers = {},
		Jobs = nil,
		JobIndex = 1,
		Building = 0,
		Displays = {},
		Lights = {},
		LightsOn = false,
		Doors = {},
		Checkouts = {},
	}
	for _, child in ipairs(model:GetChildren()) do
		local slide = child:GetAttribute("SlideX")
		if child:IsA("BasePart") and child.Name == "DoorPanel" and type(slide) == "number" then
			local closed = child.CFrame
			table.insert(m.Doors, { Part = child, Closed = closed, Open = closed * CFrame.new(slide, 0, 0), IsOpen = false })
		end
	end
	return m
end

function MarketInterior.Start(options: { Toast: ((string, Color3?) -> ())? }?)
	if started then
		return
	end
	started = true
	if options and options.Toast then
		ShopUI.SetToast(options.Toast)
	end
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	folder = f
	market = discover()
	clock = STEP_EVERY
	table.insert(conns, RunService.Heartbeat:Connect(heartbeat))
	table.insert(conns, ClientState.Changed:Connect(function()
		dirty = true
	end))
	table.insert(conns, ShopUI.Bought:Connect(function()
		dirty = true
	end))
end

function MarketInterior.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	local m = market
	if m then
		downgrade(m, 0)
		local f1 = m.Tiers[1]
		if f1 then
			f1:Destroy()
			m.Tiers[1] = nil
		end
		m.Level = 0
		for _, d in ipairs(m.Doors) do
			if d.Part.Parent then
				d.Part.CFrame = d.Closed
			end
		end
	end
	market = nil
	if folder then
		folder:Destroy()
		folder = nil
	end
	focus = nil
end

function MarketInterior.Debug(): any
	return {
		Market = market,
		Stats = stats,
		Folder = folder,
		Decide = function(position: Vector3)
			if market then
				decide(market, position)
			end
		end,
		RunAll = function()
			local m = market
			for _ = 1, 4000 do
				if not m or not m.Jobs then
					break
				end
				runJobs(m)
			end
		end,
		Buy = function(index: number)
			local m = market
			local d = m and m.Displays[index]
			if d then
				buyDisplay(d)
			end
		end,
		Inside = function(p: Vector3): boolean
			return market ~= nil and inside(market :: Market, p)
		end,
		Tags = function(p: Vector3)
			if market then
				updateTags(market, p)
			end
		end,
	}
end

return MarketInterior
