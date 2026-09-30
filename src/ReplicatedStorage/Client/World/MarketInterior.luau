--[[
	MarketInterior (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MarketInterior

	🛒 Dopamine Town : l'INTÉRIEUR du supermarché « MégaDopa » (et la vie de
	son parking), construit côté client, en flux. Le serveur (TownMarket) a
	posé la coque dans DopamineTown.Market ("Supermarket" : attributs
	MarketCF, InteriorCF, InteriorSize, DoorCF… ; vantaux "DoorPanel" +
	SlideX ; écrans "LeaderScreen" + Board).

	v9.7 (BUILDINGS97) : premier supermarché (70 x 48).
	v9.8 (MARKET98) : 10x mieux et plus grand (104 x 68) :
	  - ENTRÉE : deux grands ÉCRANS DE CLASSEMENT sur la façade (🏆 top
	    Dopamine / ♻️ top Renaissances : podium avec photos, rangs 4 à 10,
	    ta place, « ● EN DIRECT », alternance 🌍 Monde / 🏠 Ce serveur),
	    mis à jour en direct (ClientState.LeaderboardChanged) ; dedans, un
	    écran suspendu « En direct sur le serveur » ; portiques, chariots,
	    hôte·sse d'accueil qui salue ;
	  - 💎 BOUTIQUE ROBUX : les vrais Game Passes sur des socles vitrés
	    (emblème qui tourne), les produits Robux en « cartes cadeaux » sur un
	    présentoir, le coin « 🔜 Bientôt », un·e vendeur·se ; chaque offre a
	    son invite « Acheter — R$ prix » qui ouvre la fenêtre d'achat Roblox
	    EXACTEMENT comme le panneau 💎 Boutique Robux
	    (MarketplaceService:PromptGamePassPurchase / PromptProductPurchase ;
	    le serveur MonetizationService donne l'achat : aucun reçu en double) ;
	  - ☕ CAFÉ + 🍕 AIRE DE RESTAURATION : comptoirs, machine à expresso,
	    four à pizza, menus, tables et chaises, clients attablés ;
	  - ÉPICERIE : 4 gondoles (8 faces) de vrais « produits » : boîtes à
	    étiquettes imprimées (SurfaceGui, plafonnées, visibles de près),
	    bouteilles à goulot, canettes, bocaux de bonbons, sachets… ;
	    fruits & légumes, boulangerie, frigos vitrés, bacs de surgelés ;
	  - MAISON : 3 gondoles (6 faces) et 3 espaces avec les VRAIS objets de
	    la maison (House3DRecipes.BuildItem) : cuisine, déco, luminaires,
	    animaux, jeux vidéo, sport ; 🧸 jouets sur tables à gradins,
	    📺 électronique devant un mur de télés animées, 🛋️ SALONS D'EXPO
	    (deux pièces meublées en taille réelle), 🪴 jardinerie ;
	    étiquettes (BillboardGui, ancre INVISIBLE, AlwaysOnTop, les 5 plus
	    proches, seulement dans le magasin) et invite « Acheter — 🧠 prix » ;
	  - CAISSES : 6 caisses dont 4 ouvertes (TAPIS ROULANT ANIMÉ, articles
	    qui avancent, passage au scanner avec éclair rouge et « BIP ! »
	    visuel — aucun son —, caissier·ère qui scanne), 4 caisses
	    automatiques ; l'invite
	    « 🛒 Passer en caisse » ouvre le catalogue complet (ShopUI "Market") ;
	  - PERSONNAGES (NPCModels, CITY98) : caissier·ères, boulanger·ère,
	    barista, pizzaïolo, vendeur·se Robux, hôte·sse, clients attablés et
	    clients qui POUSSENT LEUR CHARIOT dans les allées ;
	  - lumières : 3 PointLights douces + 8 SurfaceLights, allumées
	    SEULEMENT quand on est dedans (luminosité ≤ 1), aucun Neon.
	Flux (budget de temps par image, jamais de création / destruction par
	image ensuite) :
	  1. "Dehors" (≤ 260 studs du bâtiment) : marquages et voitures du
	     parking, abris à chariots, camion au quai, affiches, écrans ;
	  2. "Complet" (≤ 45 studs du bâtiment, gardé jusqu'à 75) : structure
	     de tout le magasin, rayons en « bandes » de produits vues de loin,
	     clients aux chariots ;
	  3. "Détail" par ZONE (dedans, ≤ 34 studs de la zone, gardé jusqu'à
	     50) : produits un par un, vrais objets + étiquettes + invites,
	     personnages de la zone, présentoirs Robux.
	Animations (≤ 30 Hz, seulement à ≤ 70 studs) : personnages, tapis,
	scanners, emblèmes Robux, télés, écrans de classement.

	API (TownClient, via optionalModule) :
	  MarketInterior.Start({ Toast = fn(text, color?) }?)   à l'entrée en ville
	  MarketInterior.Step(position: Vector3)                 flux (facultatif)
	  MarketInterior.Stop()                                  à la sortie
	  MarketInterior.Debug() -> table                        (tests / rendus)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local HouseCommon = require(Client.Components.House.HouseCommon)
local ShopUI = require(script.Parent.ShopUI)
local BoardKit = require(script.Parent.BoardKit)
local ClockKit = require(script.Parent.ClockKit)

local MarketInterior = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = rgb(92, 58, 96)
local BRAND = rgb(236, 72, 140)
local BRAND2 = rgb(120, 90, 200)
local YELLOW = rgb(255, 208, 72)
local GOLD = rgb(236, 190, 90)
local STEEL = rgb(176, 180, 190)
local DARKSTEEL = rgb(90, 92, 104)
local ROBUX = rgb(110, 60, 200)
local ROBUX_DARK = rgb(52, 30, 96)
local SOONPINK = rgb(255, 60, 140)

local FOLDER_NAME = "TownMarketInterior"
local OUT_RANGE, OUT_DROP = 260, 320 -- (distance au bâtiment)
local FULL_RANGE, FULL_DROP = 45, 75
local ZONE_RANGE, ZONE_DROP = 34, 50
local ANIM_RANGE = 70
local ANIM_EVERY = 1 / 30
local STEP_BUDGET = 0.004
local STEP_EVERY = 0.25
local DOOR_RANGE = 12
local TAG_DISTANCE = 16
local PROMPT_DISTANCE = 5.5
local MAX_TAGS = 5
local PX = WorldLayout.PX
local GAP = 0.05
local FLOOR_TOP = 0.07 -- dessus du revêtement de sol (repère F)
local INLAY_TOP = 0.1 -- dessus des tapis / parquets (au-dessus du revêtement)
local MAX_ITEM_PARTS = 40 -- (budget) un objet exposé plus lourd laisse sa place au suivant
local MAX_SHOWROOM_PARTS = 80
local MAX_LABELS = 240 -- étiquettes imprimées (SurfaceGui) des produits
local LABEL_DISTANCE = 30
local PROMPT_COOLDOWN = 1 -- (comme le panneau 💎 Boutique Robux)
local PAGE_TIME = 10 -- (s) alternance 🌍 Monde / 🏠 Ce serveur des écrans

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

local partCount = 0
local labelCount = 0

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

-- Cylindre couché d'axe Z (repère F)
local function cylZ(parent: Instance, name: string, F: CFrame, x: number, y: number, z0: number, z1: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(parent, name, Vector3.new(math.abs(z1 - z0), diameter, diameter), F * CFrame.new(x, y, (z0 + z1) / 2) * CFrame.Angles(0, math.rad(90), 0), color, material)
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

-- Petit texte libre dans un conteneur (écrans, étiquettes)
local function text(parent: Instance, name: string, value: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font?, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(x, y)
	l.Size = UDim2.fromScale(w, h)
	l.Font = font or Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = value
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = parent
end

local function hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function pick<T>(list: { T }, seed: number, salt: number): T
	return list[math.floor(hash(seed, salt) * #list) + 1]
end

local function countParts(root: Instance): number
	local n = 0
	for _, x in ipairs(root:GetDescendants()) do
		if x:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- Modules paresseux (l'intérieur marche sans eux)
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

local function sharedModule(name: string): any?
	local module = ReplicatedStorage.Shared:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return ok and type(result) == "table" and result or nil
end

local npcCache: any = nil
local function NPC(): any?
	if npcCache == nil then
		npcCache = sharedModule("NPCModels") or false
	end
	return npcCache or nil
end

local arcadeFeature: string? = nil
local function ticketsLocked(def: any): boolean
	if def.Kind ~= "Tickets" then
		return false
	end
	if arcadeFeature == nil then
		local arcade = sharedModule("ArcadeConfig")
		arcadeFeature = arcade and tostring(arcade.Feature) or "Minigames"
	end
	return not ClientState.HasFeature(arcadeFeature :: string)
end

----------------------------------------------------------------------
-- État
----------------------------------------------------------------------

type Slot = { CF: CFrame, MaxW: number, MaxH: number, MaxD: number, Tag: CFrame, WallZ: number?, Flank: number?, Tint: Color3?, Heavy: boolean? }

type Display = {
	Entry: ShopUI.Entry,
	Model: Model?,
	Tag: BasePart?,
	Billboard: BillboardGui?,
	Prompt: ProximityPrompt?,
	Labels: { [string]: TextLabel },
	Owner: string,
}

type Door = { Part: BasePart, Closed: CFrame, Open: CFrame, IsOpen: boolean }

-- Personnage animé (fixe ou sur un parcours)
type Actor = {
	Model: Model,
	Anim: string,
	Offset: number,
	Owner: string,
	Base: CFrame?,
	Path: { Vector3 }?,
	Length: number?,
	Speed: number?,
	Cart: Model?,
	CartParts: { BasePart }?,
	CartOffsets: { CFrame }?,
	Pos: Vector3,
	Custom: boolean?, -- (v9.9) animé par sa caisse, pas par la boucle générale
}

-- Groupe de pièces déplacées d'un bloc (articles, carrousel, panier)
type Group = { Parts: { BasePart }, Offsets: { CFrame }, Shown: boolean }

-- Client de la file d'une caisse (v9.9)
type Customer = { Actor: Actor, Slot: number, Basket: Group, Parts: { BasePart }, Alpha: number, Owner: string }

-- Caisse animée (v9.9) : tapis, articles, scanner, carrousel, écrans, personnages
type Belt = {
	Owner: string,
	F: CFrame, -- repère de la caisse (x = centre du tapis, axes du magasin)
	Index: number,
	Slats: { BasePart },
	Items: { Group },
	Rest: CFrame,
	Scanner: BasePart,
	Lasers: { BasePart },
	Beep: BillboardGui,
	Carousel: Group,
	CarouselCF: CFrame,
	Bags: { BasePart },
	Pole: TextLabel?,
	Screen: TextLabel?,
	Terminal: TextLabel?,
	Paper: BasePart?,
	PaperCF: CFrame?,
	Pos: Vector3,
	Offset: number,
	Flash: number,
	Cashier: Actor?,
	Customers: { Customer },
	Last: { [string]: any },
}

type Spinner = { Part: BasePart, Base: CFrame, Owner: string, Offset: number, Pos: Vector3 }

type RobuxOffer = { Key: string, Def: any, IsPass: boolean, Id: number, Soon: boolean }

type RobuxDisplay = {
	Offer: RobuxOffer,
	Prompt: ProximityPrompt?,
	Price: TextLabel?,
	Owner: string,
}

-- Écran de classement (v9.9 : dessiné par BoardKit, façon régie télé)
type Board = {
	Kind: string, -- "Dopamine" | "Rebirths" | "Server"
	Kit: any, -- BoardKit.Board
	Gui: SurfaceGui,
	Owner: string,
	Pos: Vector3,
	LastScope: string?,
	LastRefresh: number,
}

type Builder = { Name: string, Folder: Folder?, Jobs: { () -> () }?, Index: number, Built: boolean }

type Zone = {
	Name: string,
	X: number,
	Z: number,
	Build: (m: any, parent: Instance, jobs: { () -> () }) -> (),
	B: Builder,
	Hide: { BasePart }, -- bandes "vues de loin" masquées quand le détail est là
}

type Market = {
	Model: Model,
	MCF: CFrame, -- pied de la façade (milieu), LookVector vers le parking
	F: CFrame, -- sol intérieur, milieu de la face intérieure de la façade, +Z vers le fond
	Size: Vector3,
	InteriorCF: CFrame,
	DoorCF: CFrame,
	Level: number,
	Outside: Builder,
	Full: Builder,
	Zones: { Zone },
	Displays: { Display },
	Lights: { Light },
	LightsOn: boolean,
	Doors: { Door },
	Checkouts: { Vector3 },
	Actors: { Actor },
	Belts: { Belt },
	Spinners: { Spinner },
	Kiosks: { any }, -- (v9.9) caisses automatiques animées
	Clocks: { any }, -- (v9.9) horloges { Clock, Owner }
	Dates: { any }, -- (v9.9) médaillons de date { Refresh, Owner }
	Robux: { RobuxDisplay },
	Boards: { Board },
	TVs: { UIGradient },
	Bands: { [string]: { BasePart } },
}

local started = false
local market: Market? = nil
local folder: Folder? = nil
local conns: { RBXScriptConnection } = {}
local clock = 0
local animClock = 0
local boardClock = 0
local dirty = false
local boardsDirty = true
local focus: Vector3? = nil
local lastPrompt = 0
local toastFn: ((string, Color3?) -> ())? = nil
local priceCache: { [string]: number } = {}
local priceFetching: { [string]: boolean } = {}
local stats = { Built = 0, Destroyed = 0, Items = 0, Purchases = 0, Parts = 0, Products = 0, Labels = 0, Actors = 0, RobuxPrompts = 0, ZonesBuilt = 0, Animated = 0 }

local function toast(message: string, color: Color3?)
	local fn = toastFn
	if fn then
		pcall(fn, message, color)
	end
end

----------------------------------------------------------------------
-- Géométrie du magasin (repère F : x ∈ [-51, 51], z ∈ [0, 66])
----------------------------------------------------------------------

local GONDOLA_X = { -32, -24, -16, -8, 0, 8, 16 }
local GZ0, GZ1 = 22, 42 -- gondoles (le long de Z)
local GHALF = 1.3 -- demi-profondeur d'une gondole
local LEVELS = { 0.42, 1.98, 3.54, 5.1 } -- dessus des tablettes
local CLEAR = 1.4 -- hauteur libre au-dessus d'une tablette
local GTOP = 6.6 -- haut des montants
local LANES = { 13.5, 20.3, 27.1, 33.9, 40.7 } -- caisses (x du tapis) ; v9.9 : 5 caisses plus larges
local OPEN_LANES = 4 -- (la caisse 5 est fermée)

-- Faces de gondole : { gondole, côté (-1 ouest / +1 est), contenu }
-- contenu : générique ("Cereal"...) ou catégories de la maison ("Real:Kitchen")
local FACES = {
	{ 1, -1, "Cereal" },
	{ 1, 1, "Breakfast" },
	{ 2, -1, "Drinks" },
	{ 2, 1, "Sodas" },
	{ 3, -1, "Pantry" },
	{ 3, 1, "Snacks" },
	{ 4, -1, "Candy" },
	{ 4, 1, "Care" },
	{ 5, -1, "Real:Kitchen" },
	{ 5, 1, "Real:Decor" },
	{ 6, -1, "Real:Lights" },
	{ 6, 1, "Real:Pets" },
	{ 7, -1, "Real:Gaming,Setup" },
	{ 7, 1, "Real:Sports,Adventure" },
}

-- Nom de rayon affiché (panneaux, chapeaux de gondole)
local FACE_NAMES: { [string]: string } = {
	Cereal = "🥣 Cereal",
	Breakfast = "🍯 Breakfast",
	Drinks = "🧃 Juice & water",
	Sodas = "🥤 Sodas",
	Pantry = "🥫 Pantry",
	Snacks = "🍿 Snacks",
	Candy = "🍬 Sweets",
	Care = "🧼 Home care",
	["Real:Kitchen"] = "🍳 Cookware",
	["Real:Decor"] = "🖼️ Home decor",
	["Real:Lights"] = "💡 Lamps",
	["Real:Pets"] = "🐾 Pets",
	["Real:Gaming,Setup"] = "🎮 Video games",
	["Real:Sports,Adventure"] = "⚽ Sports",
}

-- Panneaux d'allées : x, numéro, rayon de gauche, rayon de droite
local AISLES = {
	{ -37.5, "1", "🍎 Fruit & veg", "🥣 Cereal" },
	{ -28, "2", "🍯 Breakfast", "🧃 Juice & water" },
	{ -20, "3", "🥤 Sodas", "🥫 Pantry" },
	{ -12, "4", "🍿 Snacks", "🍬 Sweets" },
	{ -4, "5", "🧼 Home care", "🍳 Cookware" },
	{ 4, "6", "🖼️ Home decor", "💡 Lamps" },
	{ 12, "7", "🐾 Pets", "🎮 Video games" },
	{ 20.5, "8", "⚽ Sports", "🧸 Toys" },
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
	{ rgb(250, 120, 40), 0.44 }, -- mandarines
	{ rgb(70, 150, 60), 0.9 }, -- choux
	{ rgb(230, 60, 60), 0.5 }, -- tomates
	{ rgb(250, 214, 70), 0.7 }, -- melons jaunes
	{ rgb(110, 60, 40), 0.46 }, -- kiwis
}

-- Marques inventées des produits (jamais une vraie marque)
local BRANDS: { [string]: { string } } = {
	Cereal = { "Crunchy Brain", "Choco Pops", "Honey Loops", "Oat Joy", "Star Flakes" },
	Snack = { "Chips!", "Popcorn", "Pretzel", "Nacho", "Cookie" },
	Boxed = { "MegaDopa", "Dopa Home", "Brainy", "Happy Co" },
	Pack = { "Fizz x6", "Bubbly x6", "Water x6", "Cola x6" },
	Care = { "Sparkle", "Fresh", "Soft", "Clean" },
	Pasta = { "Pasta", "Rice", "Flour", "Sugar" },
}
local ICONS: { [string]: { string } } = {
	Cereal = { "🥣", "🍫", "🍯", "🌾", "⭐" },
	Snack = { "🥔", "🍿", "🥨", "🌮", "🍪" },
	Boxed = { "🧠", "🏠", "📦", "🎁" },
	Pack = { "🥤", "🫧", "💧", "🥤" },
	Care = { "✨", "🌸", "🧴", "🧽" },
	Pasta = { "🍝", "🍚", "🌾", "🍬" },
}

local FACE_PX = CFrame.Angles(0, -math.pi / 2, 0) -- LookVector = +X
local FACE_NX = CFrame.Angles(0, math.pi / 2, 0) -- LookVector = -X
local FACE_BACK = CFrame.Angles(0, math.pi, 0) -- LookVector = +Z (vers le fond)

-- Repère d'une face de gondole : origine sur le bord des tablettes, au
-- milieu de la gondole, au sol ; LookVector vers l'allée ; x le long de la
-- gondole ; +Z vers la cloison du milieu
local function faceFrame(F: CFrame, gondola: number, side: number): CFrame
	local x = GONDOLA_X[gondola] + side * GHALF
	return F * CFrame.new(x, 0, (GZ0 + GZ1) / 2) * (side > 0 and FACE_PX or FACE_NX)
end

----------------------------------------------------------------------
-- Produits (une pièce par produit, étiquette imprimée sur le 1er d'un lot)
----------------------------------------------------------------------

-- Étiquette imprimée (SurfaceGui) sur la face avant d'un produit : bande de
-- couleur, icône, marque ; plafonnée (MAX_LABELS), visible de près
local function printLabel(p: BasePart, face: Enum.NormalId, brand: string, icon: string, color: Color3, pps: number)
	if labelCount >= MAX_LABELS then
		return
	end
	labelCount += 1
	stats.Labels = labelCount
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Print"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.8
	gui.MaxDistance = LABEL_DISTANCE
	gui.Parent = p
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BorderSizePixel = 0
	band.BackgroundColor3 = WHITE
	band.BackgroundTransparency = 0.05
	band.Position = UDim2.fromScale(0.06, 0.3)
	band.Size = UDim2.fromScale(0.88, 0.36)
	band.Parent = gui
	corner(band, 0.25)
	text(band, "Brand", brand, 0.05, 0.08, 0.9, 0.84, color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Font.FredokaOne)
	text(gui, "Icon", icon, 0.2, 0.68, 0.6, 0.28, WHITE, Enum.Font.GothamBold)
end

-- Une rangée de produits sur une tablette (repère S de la face)
local function productRow(parent: Instance, S: CFrame, y: number, kind: string, seed: number, x0: number, x1: number, tint: Color3?): number
	local n = 0
	local w, h, d, pitch, shape
	if kind == "Cereal" then
		w, h, d, pitch, shape = 0.95, 1.3, 0.38, 1.05, "Box"
	elseif kind == "Bottle" then
		w, h, d, pitch, shape = 0.46, 0.85, 0.46, 0.82, "Bottle"
	elseif kind == "Can" then
		w, h, d, pitch, shape = 0.5, 0.78, 0.5, 0.62, "Can"
	elseif kind == "Snack" then
		w, h, d, pitch, shape = 0.92, 1.1, 0.42, 1.04, "Bag"
	elseif kind == "Care" then
		w, h, d, pitch, shape = 0.5, 0.95, 0.5, 0.72, "Can"
	elseif kind == "Pack" then
		w, h, d, pitch, shape = 1.3, 1, 0.85, 1.42, "Box"
	elseif kind == "Jar" then
		w, h, d, pitch, shape = 0.62, 0.8, 0.62, 0.8, "Jar"
	elseif kind == "Pasta" then
		w, h, d, pitch, shape = 0.8, 1.15, 0.5, 0.92, "Bag"
	else
		w, h, d, pitch, shape = 1.25, 1.08, 0.9, 1.4, "Box"
	end
	local count = math.floor((x1 - x0) / pitch)
	local start = x0 + ((x1 - x0) - count * pitch) / 2 + pitch / 2
	-- (lots de 2 à 4 produits identiques, comme en vrai)
	local group, color, first = 0, WHITE, true
	local labelKind = (kind == "Cereal" or kind == "Snack" or kind == "Pack" or kind == "Pasta" or kind == "Boxed") and kind or nil
	for i = 0, count - 1 do
		if group <= 0 then
			group = 2 + math.floor(hash(seed + i, 3) * 3)
			first = true
			if tint then
				-- (cartons "maison" : couleurs vives teintées par le rayon)
				color = pick(PALETTE, seed + i, 5):Lerp(tint, 0.35 + hash(seed + i, 7) * 0.2)
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
		if shape == "Bottle" then
			-- bouteille : corps + goulot + bouchon
			local body = newPart(parent, kind, Vector3.new(h, w, w), S * CFrame.new(x, y + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, kind == "Care" and M.SmoothPlastic or M.Glass)
			;(body :: Part).Shape = Enum.PartType.Cylinder
			if kind == "Bottle" then
				body.Transparency = 0.12
			end
			local neck = newPart(parent, "Neck", Vector3.new(0.3, w * 0.45, w * 0.45), S * CFrame.new(x, y + h + 0.15, z) * CFrame.Angles(0, 0, math.rad(90)), kind == "Care" and WHITE or color:Lerp(WHITE, 0.3), M.SmoothPlastic)
			;(neck :: Part).Shape = Enum.PartType.Cylinder
		elseif shape == "Can" then
			local can = newPart(parent, kind, Vector3.new(h, w, w), S * CFrame.new(x, y + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, kind == "Care" and M.SmoothPlastic or M.Metal)
			;(can :: Part).Shape = Enum.PartType.Cylinder
		elseif shape == "Jar" then
			-- bocal de bonbons : verre + couvercle, bonbons de couleur dedans
			local jar = newPart(parent, "Jar", Vector3.new(h, w, w), S * CFrame.new(x, y + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color:Lerp(WHITE, 0.25), M.Glass)
			;(jar :: Part).Shape = Enum.PartType.Cylinder
			jar.Transparency = 0.25
			local lid = newPart(parent, "Lid", Vector3.new(0.14, w + 0.06, w + 0.06), S * CFrame.new(x, y + h + 0.07, z) * CFrame.Angles(0, 0, math.rad(90)), pick(PALETTE, seed + i, 11), M.SmoothPlastic)
			;(lid :: Part).Shape = Enum.PartType.Cylinder
		else
			local p = box(parent, kind, S, x - w / 2, x + w / 2, y, y + h, z - d / 2, z + d / 2, color, shape == "Bag" and M.Fabric or M.SmoothPlastic)
			if first and labelKind then
				local brands = BRANDS[labelKind] or BRANDS.Boxed
				local icons = ICONS[labelKind] or ICONS.Boxed
				local k = math.floor(hash(seed + i, 13) * #brands) + 1
				printLabel(p, Enum.NormalId.Front, Locale.T(brands[k]), icons[math.min(k, #icons)], color, 60)
			end
		end
		first = false
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
-- Personnages (NPCModels de CITY98 ; repli : petit personnage en blocs)
----------------------------------------------------------------------

-- Repli si NPCModels manque : `P` = sol, LookVector = regard
local function figure(parent: Instance, P: CFrame, shirt: Color3, hair: Color3)
	local skin = rgb(255, 216, 186)
	box(parent, "Legs", P, -0.5, 0.5, 0, 2.2, -0.32, 0.32, rgb(80, 78, 110), M.SmoothPlastic)
	box(parent, "Body", P, -0.9, 0.9, 2.2, 4.2, -0.42, 0.42, shirt, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "Arm", P, sx < 0 and -1.35 or 0.95, sx < 0 and -0.95 or 1.35, 2.5, 4.1, -0.28, 0.28, shirt, M.Fabric)
	end
	ball(parent, "Head", P, 0, 4.95, 0, 1.5, skin, M.SmoothPlastic)
	ball(parent, "Hair", P, 0, 5.35, 0.18, 1.45, hair, M.SmoothPlastic)
end

-- Personnage fixe animé (anim NPCModels) ; `cf` : sol, LookVector = regard
local function actor(m: Market, parent: Instance, owner: string, style: string, seed: number, cf: CFrame, anim: string, opts: { [string]: any }?): Actor?
	local N = NPC()
	if not N or type(N.Build) ~= "function" then
		figure(parent, cf, pick(PALETTE, seed, 3), pick({ rgb(60, 40, 30), rgb(200, 150, 90), rgb(30, 30, 36) }, seed, 5))
		return nil
	end
	local o: { [string]: any } = { Seed = seed }
	for k, v in pairs(opts or {}) do
		o[k] = v
	end
	local ok, model = pcall(N.Build, style, o)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	model:PivotTo(cf)
	model.Parent = parent
	partCount += countParts(model)
	local a: Actor = { Model = model, Anim = anim, Offset = seed * 1.37, Owner = owner, Base = cf, Pos = cf.Position }
	pcall(N.Animate, model, anim, a.Offset)
	table.insert(m.Actors, a)
	stats.Actors += 1
	return a
end

----------------------------------------------------------------------
-- Chariot (Model : pivot au sol, LookVector = avant du chariot) ; ~13 pièces
----------------------------------------------------------------------

local function cart(parent: Instance, P: CFrame, handle: Color3?, goods: number?): Model
	local model = Instance.new("Model")
	model.Name = "Cart"
	local wire = rgb(186, 190, 200)
	box(model, "CartBottom", P, -0.85, 0.85, 1.3, 1.4, -1.35, 1.2, wire, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		local side = box(model, "CartSide", P, sx * 0.85 - 0.03, sx * 0.85 + 0.03, 1.4, 2.9, -1.35, 1.2, wire, M.Metal)
		side.Transparency = 0.35
		box(model, "CartPost", P, sx * 0.55 - 0.06, sx * 0.55 + 0.06, 0.35, 1.3, 1.02, 1.14, wire, M.Metal)
	end
	-- roues (une pièce par essieu : les deux roues d'un même côté vues de face)
	for _, z in ipairs({ -1.05, 0.95 }) do
		cylX(model, "Wheels", P, -0.72, 0.72, 0.26, z, 0.44, rgb(50, 50, 58), M.Rubber)
	end
	local front = box(model, "CartFront", P, -0.82, 0.82, 1.4, 2.9, -1.38, -1.32, wire, M.Metal)
	front.Transparency = 0.35
	local back = box(model, "CartBack", P, -0.82, 0.82, 1.4, 2.9, 1.17, 1.23, wire, M.Metal)
	back.Transparency = 0.35
	box(model, "CartTray", P, -0.6, 0.6, 0.45, 0.55, -1.1, 1.1, wire, M.Metal)
	cylX(model, "CartHandle", P, -0.9, 0.9, 3.05, 1.45, 0.24, handle or BRAND, M.SmoothPlastic)
	-- quelques courses dedans
	for k = 0, (goods or 0) - 1 do
		box(model, "Groceries", P, -0.55 + (k % 3) * 0.4 - 0.18, -0.55 + (k % 3) * 0.4 + 0.18, 1.4, 1.95 + (k % 2) * 0.35, -1 + k * 0.42, -0.5 + k * 0.42, pick(PALETTE, k + (goods or 0) * 3, 61), M.SmoothPlastic)
	end
	model.WorldPivot = P
	model.Parent = parent
	return model
end

-- Client qui pousse son chariot le long d'un parcours fermé (points x, z du repère F)
local function shopper(m: Market, parent: Instance, owner: string, seed: number, points: { { number } }, speed: number)
	local world = {}
	for _, p in ipairs(points) do
		table.insert(world, (m.F * CFrame.new(p[1], FLOOR_TOP, p[2])).Position)
	end
	local length = 0
	for i = 1, #world do
		length += (world[i % #world + 1] - world[i]).Magnitude
	end
	local start = CFrame.lookAt(world[1], world[2])
	local a = actor(m, parent, owner, "shopper", seed, start, "push", { Prop = "none" })
	if not a then
		return
	end
	a.Path = world
	a.Length = length
	a.Speed = speed
	local c = cart(parent, start * CFrame.new(0, 0, -2.3), pick({ BRAND, BRAND2, rgb(64, 180, 150) }, seed, 9), 2 + seed % 3)
	a.Cart = c
	-- (pièces du chariot rangées par rapport à son pivot : placées exactement
	-- à chaque image, jamais d'erreur qui s'accumule)
	local parts, offsets = {}, {}
	local pivot = start * CFrame.new(0, 0, -2.3)
	for _, x in ipairs(c:GetDescendants()) do
		if x:IsA("BasePart") then
			table.insert(parts, x)
			table.insert(offsets, pivot:ToObjectSpace(x.CFrame))
		end
	end
	a.CartParts, a.CartOffsets = parts, offsets
	partCount += #parts
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

local function sparkle(at: BasePart)
	local s = Instance.new("ParticleEmitter")
	s.Name = "Bought"
	s.Color = ColorSequence.new(rgb(255, 150, 200), rgb(255, 230, 120))
	s.LightEmission = 0.2
	s.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	s.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	s.Lifetime = NumberRange.new(0.6, 1.1)
	s.Speed = NumberRange.new(4, 8)
	s.SpreadAngle = Vector2.new(60, 60)
	s.EmissionDirection = Enum.NormalId.Top
	s.Acceleration = Vector3.new(0, -10, 0)
	s.Rate = 0
	s.Parent = at
	s:Emit(28)
	task.delay(1.6, function()
		s:Destroy()
	end)
end

local function buyDisplay(d: Display)
	local ok = ShopUI.Purchase(d.Entry)
	if ok then
		stats.Purchases += 1
		local tag = d.Tag
		if tag and tag.Parent then
			sparkle(tag)
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
	corner(card, 0.22)
	local stroke = Instance.new("UIStroke")
	stroke.Color = BRAND
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	d.Labels.Name = text(card, "Name", d.Entry.Icon .. " " .. Locale.T(d.Entry.Name), 0.06, 0.08, 0.88, 0.42, INK, Enum.Font.GothamBold)
	d.Labels.Price = text(card, "Price", "", 0.06, 0.52, 0.88, 0.4, BRAND, Enum.Font.FredokaOne)
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
	corner(owned, 1)
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
	local opts = { Scale = scale, Collide = slot.Heavy == true, Query = false, Shadows = slot.Heavy == true }
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

local function placeDisplay(m: Market, parent: Instance, owner: string, slot: Slot, entry: ShopUI.Entry, force: boolean?): boolean
	local model = buildItem(entry, slot)
	local limit = slot.Heavy and MAX_SHOWROOM_PARTS or MAX_ITEM_PARTS
	if model and not force and countParts(model) > limit then
		model:Destroy()
		return false
	end
	local d: Display = { Entry = entry, Model = model, Labels = {}, Owner = owner }
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
		-- (rayon plein : la boîte de l'objet de part et d'autre de l'objet exposé)
		local flank = slot.Flank
		if flank and typeof(fp) == "Vector3" then
			local half = math.min(fp.X, slot.MaxW) / 2
			local tint = slot.Tint or rgb(236, 226, 214)
			local seed = #m.Displays * 7
			for _, sx in ipairs({ -1, 1 }) do
				local x = half + 0.35
				if x + 0.85 <= flank then
					local c = pick(PALETTE, seed + sx, 71):Lerp(tint, 0.3)
					local b = box(parent, "ItemBox", slot.CF, math.min(sx * x, sx * (x + 0.8)), math.max(sx * x, sx * (x + 0.8)), 0.02, 0.95, -0.34, 0.34, c, M.SmoothPlastic)
					if sx > 0 then
						printLabel(b, Enum.NormalId.Front, entry.Icon, "📦", c, 60)
					end
				end
			end
		end
		stats.Items += 1
		partCount += countParts(model)
	end
	local center = (slot.CF * CFrame.new(0, math.max(0.5, height / 2), 0)).Position
	addTag(parent, d, slot.Tag, center)
	table.insert(m.Displays, d)
	return true
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

local function categoryEntries(categories: { string }, filter: ((any) -> boolean)?): { ShopUI.Entry }
	local list = {}
	local fn = (ShopUI :: any).TabEntries
	for _, id in ipairs(categories) do
		local ok, entries = false, nil
		if type(fn) == "function" then
			ok, entries = pcall(fn, id)
		end
		if ok and type(entries) == "table" then
			for _, e in ipairs(entries) do
				if e.Kind == "Item" and (not filter or filter(e.Def)) then
					table.insert(list, e)
				end
			end
		end
	end
	return list
end

-- Remplit des emplacements avec les objets d'une liste (échantillon
-- régulier du moins cher au plus cher) ; un objet trop lourd cède sa place
-- au suivant de la liste ; jamais deux fois le même objet
local function fillJobs(m: Market, parent: Instance, owner: string, jobs: { () -> () }, slots: { Slot }, entries: { ShopUI.Entry }, ordered: boolean?)
	local pool = ordered and entries or spread(entries, math.min(#entries, #slots * 3))
	local cursor = 1
	for i, slot in ipairs(slots) do
		table.insert(jobs, function()
			if not ordered then
				cursor = math.max(cursor, math.floor(1 + (i - 1) * #pool / #slots))
			end
			for _ = 1, 4 do
				local entry = pool[cursor]
				if not entry then
					return
				end
				cursor += 1
				if placeDisplay(m, parent, owner, slot, entry, false) then
					return
				end
			end
		end)
	end
end

----------------------------------------------------------------------
-- 💎 Offres Robux (Config.Monetization, comme le panneau 💎 Boutique Robux)
----------------------------------------------------------------------

local function robuxOffers(): { RobuxOffer }
	local list: { RobuxOffer } = {}
	local mon = (Config :: any).Monetization
	if type(mon) ~= "table" then
		return list
	end
	local ready = type(mon.ReadyKinds) == "table" and mon.ReadyKinds or {}
	for _, pass in ipairs(mon.GamePasses or {}) do
		table.insert(list, { Key = "Pass:" .. tostring(pass.Id), Def = pass, IsPass = true, Id = tonumber(pass.GamePassId) or 0, Soon = pass.ComingSoon == true })
	end
	for _, product in ipairs(mon.Products or {}) do
		local soon = product.ComingSoon == true or ready[product.Kind] ~= true
		table.insert(list, { Key = "Product:" .. tostring(product.Id), Def = product, IsPass = false, Id = tonumber(product.ProductId) or 0, Soon = soon })
	end
	return list
end

-- Vrai prix Roblox (MarketplaceService, jamais sur le fil de rendu ; cache)
local function fetchPrice(offer: RobuxOffer)
	local key = offer.Key
	if priceCache[key] or priceFetching[key] or offer.Id == 0 or offer.Soon then
		return
	end
	priceFetching[key] = true
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(offer.Id, offer.IsPass and Enum.InfoType.GamePass or Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			priceCache[key] = info.PriceInRobux
			dirty = true
		end
		priceFetching[key] = nil
	end)
end

local function robuxPriceText(offer: RobuxOffer): string
	local price = priceCache[offer.Key] or tonumber(offer.Def.PriceHint) or 0
	return "R$ " .. NumberFormatter.WithSpaces(price)
end

-- Texte de l'invite / du bouton d'une offre
local function robuxAction(offer: RobuxOffer): (string, boolean)
	if offer.Soon then
		return "🔜 " .. Locale.T("Coming soon!"), false
	end
	if offer.IsPass and ClientState.HasPass(tostring(offer.Def.Id)) then
		return "✅ " .. Locale.T("Already yours!"), false
	end
	if ticketsLocked(offer.Def) then
		return "🔒 " .. Locale.T("Locked"), false
	end
	return Locale.T("Buy — %s", robuxPriceText(offer)), true
end

-- Achat : mêmes vérifications que le panneau 💎 Boutique Robux, puis la
-- fenêtre d'achat Roblox ; le SERVEUR (MonetizationService : ProcessReceipt
-- / PromptGamePassPurchaseFinished) donne l'achat, jamais le client
local function robuxPrompt(offer: RobuxOffer)
	if os.clock() - lastPrompt < PROMPT_COOLDOWN then
		return
	end
	lastPrompt = os.clock()
	if offer.Soon then
		toast("🔜 " .. Locale.T("Coming soon!"), rgb(150, 110, 220))
		return
	end
	if offer.Id == 0 then
		toast("🛠️ " .. Locale.T("Paste the ID of “%s” in Config.Monetization to sell it.", Locale.T(tostring(offer.Def.Name))), rgb(255, 170, 60))
		return
	end
	if offer.IsPass and ClientState.HasPass(tostring(offer.Def.Id)) then
		toast("✅ " .. Locale.T("Already yours!"), rgb(64, 196, 150))
		return
	end
	if ticketsLocked(offer.Def) then
		toast("🔒 " .. Locale.T("Unlock the 🕹️ Arcade first: tickets are spent there."), rgb(150, 110, 220))
		return
	end
	stats.RobuxPrompts += 1
	local ok, err = pcall(function()
		if offer.IsPass then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, offer.Id)
		else
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, offer.Id)
		end
	end)
	if not ok then
		warn("[MarketInterior] Impossible d'ouvrir l'achat : " .. tostring(err))
		toast(Locale.T("Can't buy right now, try again."), rgb(236, 72, 90))
	end
end

local function refreshRobux(d: RobuxDisplay)
	local action, enabled = robuxAction(d.Offer)
	if d.Prompt then
		d.Prompt.ActionText = action
		d.Prompt.Enabled = enabled or d.Offer.Soon == false
	end
	if d.Price then
		if d.Offer.Soon then
			d.Price.Text = "🔜 " .. Locale.T("Soon")
		elseif d.Offer.IsPass and ClientState.HasPass(tostring(d.Offer.Def.Id)) then
			d.Price.Text = "✅ " .. Locale.T("Owned")
		else
			d.Price.Text = robuxPriceText(d.Offer)
		end
	end
end

-- Invite d'achat Robux sur une pièce (ancre invisible)
local function robuxDisplay(m: Market, parent: Instance, owner: string, offer: RobuxOffer, at: CFrame, priceLabel: TextLabel?)
	local d: RobuxDisplay = { Offer = offer, Price = priceLabel, Owner = owner }
	if not offer.Soon then
		local anchor = newPart(parent, "RobuxPoint", Vector3.new(0.6, 0.6, 0.6), at, WHITE, M.SmoothPlastic)
		anchor.Transparency = 1
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RobuxPrompt"
		prompt.ObjectText = tostring(offer.Def.Icon or "💎") .. " " .. Locale.T(tostring(offer.Def.Name))
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
		prompt.Triggered:Connect(function()
			robuxPrompt(offer)
		end)
		d.Prompt = prompt
	end
	fetchPrice(offer)
	refreshRobux(d)
	table.insert(m.Robux, d)
end

----------------------------------------------------------------------
-- 🏆 Écrans de classement (Dopamine / Renaissances / serveur en direct)
----------------------------------------------------------------------


local function num(value: any, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

local function formatValue(value: number): string
	if value < 1e6 then
		return NumberFormatter.WithSpaces(math.floor(value))
	end
	return NumberFormatter.Format(value)
end

local function myStats(): (number, number, number)
	local data = ClientState.Data
	if type(data) ~= "table" then
		return 0, 0, 0
	end
	local s = type(data.Stats) == "table" and data.Stats or {}
	return num(data.Dopamine, 0), num(s.LifetimeDopamine, 0), math.floor(num(data.Rebirths, 0))
end

type Row = { UserId: number, Name: string, Value: number, Rank: number }

-- Entrées d'un écran : `kind` Dopamine / Rebirths / Server, `scope` World / Server
local function boardEntries(kind: string, scope: string): { Row }
	local rows: { Row } = {}
	local me = Players.LocalPlayer
	local dopamine, lifetime, rebirths = myStats()
	if scope == "World" then
		local source = kind == "Rebirths" and ClientState.RebirthLeaderboard or ClientState.Leaderboard
		for i, raw in ipairs(type(source) == "table" and source or {}) do
			if type(raw) == "table" then
				local userId = math.floor(num(raw.UserId, 0))
				local value = num(raw.Value, 0)
				if userId == me.UserId and ClientState.Data then
					value = kind == "Rebirths" and math.max(value, rebirths) or math.max(value, lifetime)
				end
				table.insert(rows, { UserId = userId, Name = tostring(raw.Name or "?"), Value = kind == "Rebirths" and math.floor(value) or value, Rank = math.floor(num(raw.Rank, i)) })
			end
		end
		table.sort(rows, function(a, b)
			return a.Rank < b.Rank
		end)
		return rows
	end
	local found = false
	for _, raw in ipairs(type(ClientState.ServerLeaderboard) == "table" and ClientState.ServerLeaderboard or {}) do
		if type(raw) == "table" then
			local userId = math.floor(num(raw.UserId, 0))
			local value = kind == "Rebirths" and math.floor(num(raw.Rebirths, 0)) or num(raw.Dopamine, num(raw.Value, 0))
			if userId == me.UserId and ClientState.Data then
				-- (ta ligne suit tes compteurs en direct)
				found = true
				value = kind == "Rebirths" and rebirths or dopamine
			end
			table.insert(rows, { UserId = userId, Name = tostring(raw.Name or "?"), Value = value, Rank = 0 })
		end
	end
	if not found and ClientState.Data then
		table.insert(rows, { UserId = me.UserId, Name = me.DisplayName, Value = kind == "Rebirths" and rebirths or dopamine, Rank = 0 })
	end
	table.sort(rows, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
	for i, r in ipairs(rows) do
		r.Rank = i
	end
	return rows
end

local function valueText(kind: string, value: number): string
	if kind == "Rebirths" then
		return formatValue(value) .. " ♻️"
	end
	return formatValue(value) .. " 💧"
end

local function ordinal(rank: number): string
	if Locale.IsFrench() then
		return rank == 1 and "1er" or (tostring(rank) .. "e")
	end
	local lastTwo = rank % 100
	local suffix = "th"
	if lastTwo < 11 or lastTwo > 13 then
		local last = rank % 10
		suffix = last == 1 and "st" or (last == 2 and "nd" or (last == 3 and "rd" or "th"))
	end
	return tostring(rank) .. suffix
end

local BOARD_TITLES = {
	Dopamine = "🏆 Top Dopamine",
	Rebirths = "♻️ Top Rebirths",
	Server = "🏠 Live on this server",
}

-- Écran de classement sur la face avant d'une pièce (v9.9 : BoardKit)
local function buildBoard(m: Market, screen: BasePart, kind: string, owner: string, pps: number, face: Enum.NormalId?): Board
	local kit = BoardKit.Build(screen, {
		Face = face or Enum.NormalId.Front,
		PPS = pps,
		MaxDistance = 320,
		Title = BOARD_TITLES[kind] or kind,
		Theme = kind,
		Rows = 6,
		HeroCaption = "⭐ Best player on the server",
		Ticker = {
			"🧠 MegaDopa: everything for your home",
			"🏆 Climb the leaderboard: click, buy, rebirth!",
			"💎 Robux Shop inside",
			"☕ Café & food court",
		},
	})
	local board: Board = { Kind = kind, Kit = kit, Gui = kit.Gui, Owner = owner, Pos = screen.Position, LastScope = nil, LastRefresh = -10 }
	table.insert(m.Boards, board)
	boardsDirty = true
	return board
end

-- Page en cours d'un écran : 🌍 monde et 🏠 serveur alternent (le monde
-- n'existe pas encore : serveur seulement)
local function boardScope(board: Board, now: number): string
	if board.Kind == "Server" then
		return "Server"
	end
	local world = board.Kind == "Rebirths" and ClientState.RebirthLeaderboard or ClientState.Leaderboard
	if type(world) ~= "table" or #world == 0 then
		return "Server"
	end
	local offset = board.Kind == "Rebirths" and PAGE_TIME / 2 or 0
	return math.floor((now + offset) / PAGE_TIME) % 2 == 0 and "World" or "Server"
end

local function refreshBoard(board: Board, now: number)
	local scope = boardScope(board, now)
	local valueKind = board.Kind == "Rebirths" and "Rebirths" or "Dopamine"
	local entries = boardEntries(valueKind, scope)
	local me = Players.LocalPlayer.UserId
	local rows = {}
	local mine: Row? = nil
	for _, r in ipairs(entries) do
		table.insert(rows, { UserId = r.UserId, Name = r.Name, Value = r.Value, ValueText = valueText(valueKind, r.Value), Rank = r.Rank, Mine = r.UserId == me })
		if r.UserId == me then
			mine = r
		end
	end
	-- ta place (même hors du top 10)
	local dopamine, lifetime, rebirths = myStats()
	local myValue = valueKind == "Rebirths" and rebirths or (scope == "World" and lifetime or dopamine)
	local footer
	if mine then
		footer = Locale.T("You: %s · %s", ordinal(mine.Rank), valueText(valueKind, mine.Value))
	else
		footer = Locale.T("You: not in the top yet · %s", valueText(valueKind, myValue))
	end
	local caption
	if scope == "World" then
		caption = valueKind == "Rebirths" and Locale.T("♻️ World rebirth champion") or Locale.T("🌍 World champion")
	else
		caption = Locale.T("⭐ Best player on the server")
	end
	BoardKit.SetData(board.Kit, {
		Rows = rows,
		Scope = scope == "World" and ("🌍 " .. Locale.T("World")) or ("🏠 " .. Locale.T("This server")),
		Footer = footer,
		HeroCaption = caption,
	})
end

----------------------------------------------------------------------
-- Niveau 1 : dehors (parking, chariots, camion, vitrines, écrans)
----------------------------------------------------------------------

local CAR_KINDS = { "CityCar", "Hatchback", "SUV", "BubbleCar", "Van", "Hatchback", "Pickup", "CityCar", "Hatchback", "SUV" }
local CAR_COLORS = {
	rgb(255, 150, 190), rgb(130, 200, 255), rgb(255, 236, 150), rgb(170, 230, 190), rgb(250, 250, 250),
	rgb(236, 72, 90), rgb(200, 170, 250), rgb(60, 64, 80), rgb(236, 96, 110), rgb(96, 170, 120),
}
local LOT_Y = -0.5
local STALLS, STALL_W = 15, 6.4 -- places par rangée (6,4 de large : même les SUV y tiennent)
local ROW_A = { -46, -35.5 }
local ROW_B = { -28, -17.5 }

----------------------------------------------------------------------
-- v9.9 (SHOPS99) : magasin ÉCLAIRÉ vu de dehors + horloges
----------------------------------------------------------------------

-- (un seul local de plus : le module est proche de la limite de 200 registres)
local V99: any = { Timers = { Clock = 0, Date = 0 } }

-- Surface « lumineuse » (SurfaceGui peu sensible à la lumière : visible
-- éclairée la nuit, sans vraie lumière ni Neon) sur une face d'une pièce
function V99.glowFace(p: BasePart, face: Enum.NormalId, top: Color3, bottom: Color3, influence: number, maxDistance: number, pps: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Glow"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps or 4
	gui.LightInfluence = influence
	gui.Brightness = 1
	gui.MaxDistance = maxDistance
	gui.Parent = p
	local f = Instance.new("Frame")
	f.Name = "Wash"
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = WHITE
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = f
	return gui
end

-- Plafonniers (toujours là dès 260 studs : le magasin est éclairé de loin),
-- sols / murs « éclairés » et silhouettes des gondoles (dossier Night, retiré
-- quand l'intérieur complet est construit : il a ses vraies lumières)
function V99.nightShell(m: Market, parent: Instance)
	local F = m.F
	local hw, H, D = m.Size.X / 2, m.Size.Y, m.Size.Z
	for _, x in ipairs({ -36, -18, 0, 18, 36 }) do
		for _, z in ipairs({ 10, 24, 38, 54 }) do
			box(parent, "LampHanger", F, x - 0.05, x + 0.05, H - 2.3, H - 0.8, z - 0.05, z + 0.05, DARKSTEEL, M.Metal)
			local panel = box(parent, "LampPanel", F, x - 3, x + 3, H - 2.6, H - 2.3, z - 0.6, z + 0.6, rgb(236, 236, 240), M.Metal)
			V99.glowFace(panel, Enum.NormalId.Bottom, rgb(255, 252, 244), rgb(255, 244, 222), 0, 420, 6)
		end
	end
	local night = Instance.new("Folder")
	night.Name = "Night"
	night.Parent = parent
	;(m :: any).Night = night
	;(m :: any).NightParent = parent
	local floorGlow = box(night, "FloorGlow", F, -hw + 0.3, hw - 0.3, 0.02, 0.05, 0.3, D - 0.3, WHITE, M.SmoothPlastic)
	floorGlow.Transparency = 1
	V99.glowFace(floorGlow, Enum.NormalId.Top, rgb(236, 234, 230), rgb(214, 212, 210), 0.25, 400, 1)
	local back = box(night, "WallGlow", F, -hw + 0.4, hw - 0.4, 0.2, 12.2, D - 0.08, D - 0.06, WHITE, M.SmoothPlastic)
	back.Transparency = 1
	V99.glowFace(back, Enum.NormalId.Front, rgb(250, 236, 244), rgb(236, 232, 240), 0.25, 400, 2)
	for _, sx in ipairs({ -1, 1 }) do
		local side = box(night, "WallGlow", F * CFrame.new(sx * (hw - 0.07), 0, D / 2) * (sx < 0 and FACE_PX or FACE_NX), -D / 2 + 0.4, D / 2 - 0.4, 0.2, 12.2, -0.01, 0.01, WHITE, M.SmoothPlastic)
		side.Transparency = 1
		V99.glowFace(side, Enum.NormalId.Front, rgb(250, 240, 246), rgb(236, 232, 240), 0.25, 400, 2)
	end
	-- silhouettes des gondoles (produits « éclairés » en bandes de couleur)
	for g, x in ipairs(GONDOLA_X) do
		local body = box(night, "GondolaShape", F, x - GHALF + 0.05, x + GHALF - 0.05, 0.05, GTOP, GZ0 + 0.1, GZ1 - 0.1, rgb(236, 236, 240), M.SmoothPlastic)
		for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Stock"
			gui.Face = face
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 3
			gui.LightInfluence = 0.3
			gui.MaxDistance = 400
			gui.Parent = body
			for k = 1, 4 do
				local band = Instance.new("Frame")
				band.BorderSizePixel = 0
				band.Position = UDim2.fromScale(0.02, 1 - (LEVELS[k] + 1.2) / GTOP)
				band.Size = UDim2.fromScale(0.96, 1.05 / GTOP)
				band.BackgroundColor3 = pick(PALETTE, g * 7 + k, face == Enum.NormalId.Left and 91 or 97)
				band.Parent = gui
				local grad = Instance.new("UIGradient")
				grad.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, WHITE),
					ColorSequenceKeypoint.new(0.3, rgb(220, 220, 220)),
					ColorSequenceKeypoint.new(0.6, WHITE),
					ColorSequenceKeypoint.new(1, rgb(210, 210, 210)),
				})
				grad.Parent = band
			end
		end
	end
end

-- Horloges du magasin : murale sur le pilier gauche de la tour, médaillon
-- « date du jour » sur le pilier droit (dehors) ; horloge de gare au-dessus
-- des caisses (dedans)
function V99.addClock(m: Market, parent: Instance, owner: string, frame: CFrame, diameter: number, opts: { [string]: any })
	local ok, clock = pcall(ClockKit.Build, parent, frame, diameter, opts)
	if ok and clock then
		table.insert((m :: any).Clocks, { Clock = clock, Owner = owner })
		partCount += countParts(clock.Model)
	end
end

V99.MONTHS_FR = { "janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre" }
V99.MONTHS_EN = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
V99.DAYS_FR = { "dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi" }
V99.DAYS_EN = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

function V99.dateParts(): (string, string, string)
	local ok, now = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	local t = os.date("*t", math.floor(ok and type(now) == "number" and now > 1e8 and now or os.time())) :: any
	local fr = Locale.IsFrench()
	local day = (fr and V99.DAYS_FR or V99.DAYS_EN)[tonumber(t.wday) or 1] or ""
	local month = (fr and V99.MONTHS_FR or V99.MONTHS_EN)[tonumber(t.month) or 1] or ""
	return string.upper(day), tostring(t.day), string.upper(month)
end

function V99.facadeClocks(m: Market, parent: Instance)
	local cf = m.MCF
	-- horloge murale (boîtier laqué, verre) sur le pilier gauche
	V99.addClock(m, parent, "outside", cf * CFrame.new(-19, 23.2, -1.6 - 0.36), 3.2, { Style = "Wall", Numerals = "Arabic", Brand = "MegaDopa", Case = rgb(40, 38, 52), CaseMaterial = M.Metal, MaxDistance = 400, Name = "MarketClock" })
	-- médaillon « date du jour » sur le pilier droit (même boîtier)
	local P = cf * CFrame.new(19, 23.2, -1.6 - 0.36)
	local case = newPart(parent, "DateCase", Vector3.new(0.38, 3.52, 3.52), P * CFrame.new(0, 0, 0.19) * CFrame.Angles(0, math.rad(90), 0), rgb(40, 38, 52), M.Metal)
	;(case :: Part).Shape = Enum.PartType.Cylinder
	local carrier = newPart(parent, "DateDial", Vector3.new(3.14, 3.14, 0.02), P * CFrame.new(0, 0, -0.03), WHITE, M.SmoothPlastic)
	carrier.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Date"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.35
	gui.MaxDistance = 400
	gui.Parent = carrier
	local disc = Instance.new("Frame")
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = rgb(250, 244, 226)
	disc.BorderSizePixel = 0
	disc.Parent = gui
	corner(disc, 0.5)
	local top = Instance.new("Frame")
	top.Position = UDim2.fromScale(0.15, 0.16)
	top.Size = UDim2.fromScale(0.7, 0.2)
	top.BackgroundColor3 = BRAND
	top.BorderSizePixel = 0
	top.Parent = disc
	corner(top, 0.3)
	local wday = text(top, "Day", "", 0.05, 0.1, 0.9, 0.8, WHITE, Enum.Font.GothamBlack)
	local num = text(disc, "Number", "", 0.2, 0.36, 0.6, 0.34, rgb(40, 36, 52), Enum.Font.GothamBlack)
	local month = text(disc, "Month", "", 0.2, 0.7, 0.6, 0.12, rgb(120, 90, 200), Enum.Font.GothamBold)
	local function refresh()
		local d, n, mo = V99.dateParts()
		wday.Text, num.Text, month.Text = d, n, mo
	end
	refresh()
	table.insert((m :: any).Dates, { Refresh = refresh, Owner = "outside" })
	partCount += 2
end

local function outsideJobs(m: Market, parent: Instance): { () -> () }
	local jobs: { () -> () } = {}
	local cf = m.MCF
	local hw = m.Size.X / 2 + 2
	local lineY0, lineY1 = LOT_Y + 0.03, LOT_Y + 0.07
	local line = rgb(236, 236, 230)
	-- marquages : places (2 rangées), passage piéton, flèches, voie le long de la route
	table.insert(jobs, function()
		for _, row in ipairs({ ROW_A, ROW_B }) do
			for i = 0, STALLS do
				local x = -48 + i * STALL_W
				box(parent, "StallLine", cf, x - 0.15, x + 0.15, lineY0, lineY1, row[1] + 0.3, row[2] - 0.3, line, M.SmoothPlastic)
			end
			-- ligne de fond de place (en T)
			box(parent, "StallEnd", cf, -48.15, 48.15, lineY0, lineY1, row[1] + 0.3, row[1] + 0.55, line, M.SmoothPlastic)
		end
		for i = 0, 5 do
			local x = -5.5 + i * 2.2
			box(parent, "Zebra", cf, x - 0.6, x + 0.6, lineY0, lineY1, -17, -10.6, line, M.SmoothPlastic)
		end
		for _, x in ipairs({ -26, 26 }) do
			box(parent, "Arrow", cf, x - 2.4, x + 2.4, lineY0, lineY1, -32, -31.4, line, M.SmoothPlastic)
			local wedge = Instance.new("WedgePart")
			wedge.Name = "ArrowHead"
			wedge.Anchored = true
			wedge.CanCollide = false
			wedge.CanQuery = false
			wedge.CanTouch = false
			wedge.CastShadow = false
			wedge.Size = Vector3.new(1.8, 0.04, 1.6)
			wedge.CFrame = cf * CFrame.new(x + (x > 0 and -3.2 or 3.2), (lineY0 + lineY1) / 2, -31.7) * CFrame.Angles(0, x > 0 and math.pi / 2 or -math.pi / 2, 0)
			wedge.Color = line
			wedge.Material = M.SmoothPlastic
			wedge.Parent = parent
			partCount += 1
		end
		-- voie le long de la route : tirets
		for i = 0, 12 do
			local x = -hw + 6 + i * 8
			box(parent, "LaneDash", cf, x - 1.6, x + 1.6, lineY0, lineY1, -49.1, -48.8, line, M.SmoothPlastic)
		end
		-- places « famille » (pictogramme bleu) près de l'entrée
		for _, x in ipairs({ -STALL_W, STALL_W }) do
			local p = box(parent, "FamilyBay", cf, x - 2.3, x + 2.3, lineY0, lineY1 - 0.03, ROW_B[2] - 4.6, ROW_B[2] - 0.6, rgb(90, 140, 220), M.SmoothPlastic)
			label(p, Enum.NormalId.Top, "👪", WHITE, nil, 30, 120)
		end
	end)
	-- voitures garées (rangée A : nez vers la route ; rangée B : nez vers le magasin)
	local spots = { { "A", 3 }, { "A", 9 }, { "A", 13 }, { "B", 2 }, { "B", 6 }, { "B", 12 } }
	for index, spot in ipairs(spots) do
		table.insert(jobs, function()
			local cm = sharedModule("CarModels")
			if not cm or type(cm.Build) ~= "function" then
				return
			end
			local row, i = spot[1], spot[2]
			local x = -48 + (i - 0.5) * STALL_W
			local z = row == "A" and (ROW_A[1] + ROW_A[2]) / 2 or (ROW_B[1] + ROW_B[2]) / 2
			local rot = row == "A" and CFrame.new() or CFrame.Angles(0, math.pi, 0)
			local ok, model = pcall(cm.Build, CAR_KINDS[index], CAR_COLORS[index], { Detail = "Mid" })
			if ok and typeof(model) == "Instance" and model:IsA("Model") then
				model:PivotTo(cf * CFrame.new(x, LOT_Y, z) * rot)
				model.Parent = parent
				partCount += countParts(model)
			end
		end)
	end
	-- abris à chariots (2) : barrières + toit + chariots emboîtés
	for _, spot in ipairs({ { -32, (ROW_B[1] + ROW_B[2]) / 2 }, { 38.4, (ROW_A[1] + ROW_A[2]) / 2 } }) do
		table.insert(jobs, function()
			local P = cf * CFrame.new(spot[1], LOT_Y, spot[2])
			for _, sx in ipairs({ -1, 1 }) do
				box(parent, "CorralRail", P, sx * 1.4 - 0.08, sx * 1.4 + 0.08, 0, 2.6, -4.4, 4.4, STEEL, M.Metal)
			end
			box(parent, "CorralBack", P, -1.4, 1.4, 0, 2.6, 4.32, 4.48, STEEL, M.Metal)
			local roof = box(parent, "CorralSign", P, -1.6, 1.6, 2.6, 3.4, 4.2, 4.6, BRAND, M.SmoothPlastic)
			label(roof, Enum.NormalId.Front, "🛒", WHITE, nil, 30, 120)
			for k = 0, 1 do
				partCount += countParts(cart(parent, P * CFrame.new(0, 0, -1.6 + k * 1.4) * CFrame.Angles(0, math.pi, 0)))
			end
		end)
	end
	-- bacs fleuris de part et d'autre de l'atrium + chariot oublié
	table.insert(jobs, function()
		partCount += countParts(cart(parent, cf * CFrame.new(-19.5, 0, -6.4) * CFrame.Angles(0, math.rad(200), 0)))
		for _, sx in ipairs({ -1, 1 }) do
			local P = cf * CFrame.new(sx * 15.2, 0, -3.4)
			box(parent, "Planter", P, -1.4, 1.4, 0, 1.4, -1, 1, rgb(250, 250, 252), M.SmoothPlastic, true)
			ball(parent, "Bush", P, 0, 2.1, 0, 2.2, rgb(96, 170, 100), M.Grass)
			for k = -1, 1, 2 do
				ball(parent, "Flower", P, k * 0.7, 2.5, -0.6, 0.7, k < 0 and rgb(255, 130, 180) or YELLOW, M.SmoothPlastic)
			end
		end
	end)
	-- affiches collées sur les vitrines (dehors, entre les meneaux)
	table.insert(jobs, function()
		local posters = {
			{ 42.4, "🧸 New toys!", BRAND },
			{ 48.1, "🛋️ Home deals", rgb(230, 130, 60) },
			{ -42.4, "💎 Robux Shop", ROBUX },
			{ -48.1, "☕ Café & food court", rgb(170, 110, 60) },
		}
		for _, p in ipairs(posters) do
			local x = p[1] :: number
			local board = box(parent, "Poster", cf, x - 1.05, x + 1.05, 4, 8.6, -0.34, -0.29, WHITE, M.SmoothPlastic)
			label(board, Enum.NormalId.Front, Locale.T(p[2] :: string), WHITE, p[3] :: Color3, 30, 160)
		end
	end)
	-- camion de livraison au quai (à l'arrière)
	table.insert(jobs, function()
		local cm = sharedModule("CarModels")
		if not cm or type(cm.Build) ~= "function" then
			return
		end
		local B = cf * CFrame.new(0, 0, m.Size.Z + 2) * CFrame.Angles(0, math.pi, 0)
		local ok, model = pcall(cm.Build, "Van", rgb(250, 250, 252), { Detail = "Mid", Scale = Vector3.new(1.1, 1.15, 1.2) })
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			model:PivotTo(B * CFrame.new(14, -0.6, -12.15)) -- (v9.9) 0,15 de plus : l'avant ne touche plus le quai
			model.Parent = parent
			partCount += countParts(model)
		end
	end)
	-- (v9.9) plafonniers, intérieur « éclairé » vu de dehors, horloges de la façade
	table.insert(jobs, function()
		V99.nightShell(m, parent)
	end)
	table.insert(jobs, function()
		V99.facadeClocks(m, parent)
	end)
	-- 🏆 écrans de classement de la façade (pièces du serveur, contenu ici)
	table.insert(jobs, function()
		for _, child in ipairs(m.Model:GetChildren()) do
			local kind = child:GetAttribute("Board")
			if child:IsA("BasePart") and child.Name == "LeaderScreen" and type(kind) == "string" then
				buildBoard(m, child, kind, "outside", 40)
				-- (v9.9) vrai cadre de téléviseur : liseré chromé + plaque
				for _, p in ipairs(BoardKit.Frame(parent, child, { Lip = 0.2, PlateH = 0.34 })) do
					local _ = p
					partCount += 1
				end
			end
		end
	end)
	return jobs
end

----------------------------------------------------------------------
-- Niveau 2 : structure de tout le magasin
----------------------------------------------------------------------

-- Bande « produits vus de loin » (une pièce par tablette), masquée quand
-- le détail de la zone est construit
local function band(m: Market, parent: Instance, key: string, S: CFrame, x0: number, x1: number, y: number, h: number, color: Color3)
	local p = box(parent, "ProductBand", S, x0, x1, y + 0.02, y + h, 0.14, 1.02, color, M.SmoothPlastic)
	local list = m.Bands[key]
	if not list then
		list = {}
		m.Bands[key] = list
	end
	table.insert(list, p)
end

-- Sol, zones, bandeau aux murs, charpente, gaines, rampes lumineuses
local function shell(m: Market, parent: Instance)
	local F = m.F
	local hw, H, D = m.Size.X / 2, m.Size.Y, m.Size.Z
	box(parent, "FloorFinish", F, -hw + GAP, hw - GAP, 0.02, FLOOR_TOP, GAP, D - GAP, rgb(244, 242, 238), M.Marble)
	-- allée principale (clair) et allée du fond
	box(parent, "PowerAisle", F, -hw + 0.5, hw - 0.5, FLOOR_TOP, INLAY_TOP, 15.2, 19.8, rgb(226, 232, 240), M.SmoothPlastic)
	box(parent, "BackAisle", F, -hw + 0.5, hw - 0.5, FLOOR_TOP, INLAY_TOP, 44.4, 48.6, rgb(232, 228, 238), M.SmoothPlastic)
	-- bandeau de l'enseigne tout autour (murs)
	local y0, y1, y2 = 12.4, 13.2, 13.5
	box(parent, "WallStripe", F, -hw + 0.1, hw - 0.1, y0, y1, D - 0.1, D - 0.05, BRAND, M.SmoothPlastic)
	box(parent, "WallStripe", F, -hw + 0.1, hw - 0.1, y1, y2, D - 0.1, D - 0.05, YELLOW, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "WallStripe", F, sx * (hw - 0.1), sx * (hw - 0.05), y0, y1, 0.2, D - 0.2, BRAND, M.SmoothPlastic)
		box(parent, "WallStripe", F, sx * (hw - 0.1), sx * (hw - 0.05), y1, y2, 0.2, D - 0.2, YELLOW, M.SmoothPlastic)
		box(parent, "WallStripe", F, sx * 21.1, sx * (hw - 0.2), y0, y1, 0.05, 0.1, BRAND, M.SmoothPlastic)
	end
	-- charpente apparente (poutres), gaines de ventilation
	for i = 1, 6 do
		local z = i * D / 7
		box(parent, "Truss", F, -hw + 0.1, hw - 0.1, H - 0.8, H - 0.1, z - 0.25, z + 0.25, rgb(214, 216, 224), M.Metal)
	end
	for _, x in ipairs({ -30, 30 }) do
		cylZ(parent, "Duct", F, x, H - 1.9, 1, D - 1, 1.4, rgb(200, 204, 214), M.Metal)
	end
	-- rampes d'éclairage : les plafonniers (lumineux) sont au niveau 1 (vus
	-- de dehors, v9.9) ; ici, 8 SurfaceLights douces sur des supports invisibles
	local lit = 0
	for _, x in ipairs({ -36, -18, 0, 18, 36 }) do
		for _, z in ipairs({ 10, 24, 38, 54 }) do
			if (z == 10 or z == 38) and x ~= 0 and lit < 8 then
				local panel = box(parent, "LightAnchor", F, x - 2.9, x + 2.9, H - 2.75, H - 2.7, z - 0.5, z + 0.5, WHITE, M.SmoothPlastic)
				panel.Transparency = 1
				lit += 1
				local sl = Instance.new("SurfaceLight")
				sl.Name = "MarketLight"
				sl.Face = Enum.NormalId.Bottom
				sl.Angle = 120
				sl.Range = 18
				sl.Brightness = 0.6
				sl.Color = rgb(255, 246, 232)
				sl.Shadows = false
				sl.Enabled = m.LightsOn
				sl.Parent = panel
				table.insert(m.Lights, sl)
			end
		end
	end
	-- 3 vraies lumières douces (hautes) : épicerie, allée centrale, boutique Robux
	for _, spot in ipairs({ { -20, 32, rgb(255, 244, 226) }, { 14, 32, rgb(255, 244, 226) }, { -41, 7, rgb(236, 220, 255) } }) do
		local anchor = box(parent, "LightAnchor", F, spot[1] - 0.2, spot[1] + 0.2, H - 3.4, H - 3, spot[2] - 0.2, spot[2] + 0.2, WHITE, M.SmoothPlastic)
		anchor.Transparency = 1
		local pl = Instance.new("PointLight")
		pl.Name = "MarketLight"
		pl.Brightness = 0.9
		pl.Range = 28
		pl.Color = spot[3] :: Color3
		pl.Shadows = false
		pl.Enabled = m.LightsOn
		pl.Parent = anchor
		table.insert(m.Lights, pl)
	end
end

-- Structure d'une gondole (socle, cloison, montants, tablettes, chapeau
-- avec le nom des rayons, tête de gondole promo, joue au fond) + bandes
local function gondola(m: Market, parent: Instance, g: number)
	local F = m.F
	local x = GONDOLA_X[g]
	local grey = rgb(236, 236, 240)
	box(parent, "GondolaBase", F, x - GHALF, x + GHALF, FLOOR_TOP, LEVELS[1], GZ0, GZ1, rgb(96, 100, 116), M.Metal, true)
	box(parent, "GondolaBack", F, x - 0.06, x + 0.06, LEVELS[1], GTOP - 0.1, GZ0 + 0.15, GZ1 - 0.15, g % 2 == 0 and rgb(214, 226, 246) or rgb(250, 226, 236), M.SmoothPlastic, true)
	for _, z in ipairs({ GZ0, GZ1 - 0.15 }) do
		box(parent, "Upright", F, x - GHALF, x + GHALF, LEVELS[1], GTOP, z, z + 0.15, grey, M.Metal, true)
	end
	box(parent, "GondolaTop", F, x - GHALF - 0.05, x + GHALF + 0.05, GTOP, GTOP + 0.15, GZ0 - 0.05, GZ1 + 0.05, BRAND, M.SmoothPlastic)
	-- chapeau : nom des deux rayons (deux faces)
	local topper = box(parent, "Topper", F, x - 0.08, x + 0.08, GTOP + 0.15, GTOP + 1.25, GZ0 + 3, GZ1 - 3, WHITE, M.SmoothPlastic)
	for _, spec in ipairs(FACES) do
		if spec[1] == g then
			local name = Locale.T(FACE_NAMES[spec[3] :: string] or "")
			label(topper, spec[2] == 1 and Enum.NormalId.Right or Enum.NormalId.Left, name, BRAND2, WHITE, 24, 80)
		end
	end
	for side = -1, 1, 2 do
		for level = 2, 4 do
			local y = LEVELS[level]
			local x0, x1 = x + side * 0.06, x + side * GHALF
			local board = box(parent, "Shelf", F, math.min(x0, x1), math.max(x0, x1), y - 0.12, y, GZ0 + 0.15, GZ1 - 0.15, grey, M.Metal)
			board:SetAttribute("Side", side)
			board:SetAttribute("Gondola", g)
		end
	end
	-- tête de gondole côté allée principale (promo)
	local z0 = GZ0
	box(parent, "EndCap", F, x - GHALF, x + GHALF, FLOOR_TOP, 0.9, z0 - 1.5, z0 - 0.02, rgb(96, 100, 116), M.Metal, true)
	box(parent, "EndCapShelf", F, x - GHALF, x + GHALF, 2.6, 2.72, z0 - 1.3, z0 - 0.02, grey, M.Metal)
	local sign = box(parent, "PromoSign", F, x - 1.2, x + 1.2, 5.2, 6.4, z0 - 0.3, z0 - 0.22, YELLOW, M.SmoothPlastic)
	label(sign, Enum.NormalId.Front, g <= 4 and "PROMO -30%" or Locale.T("NEW!"), rgb(200, 40, 60), nil, 40, 60)
	local seed = g * 17
	for k = 0, 1 do
		local xx = x - 0.62 + k * 1.24
		local c1 = pick(PALETTE, seed + k, 9)
		local b1 = box(parent, "PromoBox", F, xx - 0.55, xx + 0.55, 0.9, 2.1, z0 - 1.25, z0 - 0.15, c1, M.SmoothPlastic)
		printLabel(b1, Enum.NormalId.Front, "-30%", "🔥", c1, 50)
		box(parent, "PromoBox", F, xx - 0.5, xx + 0.5, 2.72, 3.9, z0 - 1.2, z0 - 0.2, pick(PALETTE, seed + k + 5, 9), M.SmoothPlastic)
	end
	-- joue du fond (vers l'allée du fond) : couleur du rayon
	box(parent, "EndPanel", F, x - GHALF, x + GHALF, LEVELS[1], GTOP, GZ1 + 0.02, GZ1 + 0.12, g <= 4 and rgb(96, 186, 110) or BRAND2, M.SmoothPlastic)
	-- bandes « produits vus de loin » sur chaque niveau des deux faces
	for index, spec in ipairs(FACES) do
		if spec[1] == g then
			local S = faceFrame(F, g, spec[2] :: number)
			local half = (GZ1 - GZ0) / 2 - 0.35
			local kind = spec[3] :: string
			local tint = string.sub(kind, 1, 5) == "Real:" and rgb(236, 226, 214) or nil
			for level = 1, 4 do
				local c = tint and pick(PALETTE, index * 5 + level, 17):Lerp(tint, 0.45) or pick(PALETTE, index * 5 + level, 17):Lerp(WHITE, 0.15)
				band(m, parent, "Face" .. index, S, -half, half, LEVELS[level], level == 1 and 1.0 or 1.15, c)
			end
		end
	end
end

-- Étiquettes de prix sur les tablettes des faces génériques
local function priceTags(m: Market, parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "Shelf" then
			local side = child:GetAttribute("Side")
			local gi = child:GetAttribute("Gondola")
			local content = ""
			for _, f in ipairs(FACES) do
				if f[1] == gi and f[2] == side then
					content = f[3] :: string
				end
			end
			if content ~= "" and string.sub(content, 1, 5) ~= "Real:" then
				local rel = m.F:PointToObjectSpace(child.Position)
				priceStrip(child, side == 1 and Enum.NormalId.Right or Enum.NormalId.Left, math.floor(rel.Y * 10 + (tonumber(gi) or 1) * 7), 8)
			end
		end
	end
end

-- Panneaux d'allées suspendus (numéro + rayons, deux faces)
local function aisleSigns(m: Market, parent: Instance)
	local F = m.F
	local H = m.Size.Y
	for _, a in ipairs(AISLES) do
		local x = a[1] :: number
		local z = (GZ0 + GZ1) / 2
		for _, dz in ipairs({ -0.6, 0.6 }) do
			box(parent, "SignCord", F, x + dz * 2 - 0.03, x + dz * 2 + 0.03, 11.6, H - 0.8, z - 0.03, z + 0.03, DARKSTEEL, M.Metal)
		end
		local board = box(parent, "AisleSign", F, x - 2.8, x + 2.8, 9.6, 11.6, z - 0.08, z + 0.08, BRAND2, M.SmoothPlastic)
		local caption = a[2] .. "  " .. Locale.T(a[3] :: string) .. " · " .. Locale.T(a[4] :: string)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			label(board, face, caption, WHITE, nil, 24, 120)
		end
		local number = box(parent, "AisleNumber", F, x - 0.7, x + 0.7, 11.6, 12.9, z - 0.1, z + 0.1, YELLOW, M.SmoothPlastic)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			label(number, face, a[2] :: string, BRAND2, nil, 30, 120)
		end
	end
end

-- Panneau de rayon suspendu (deux faces)
local function hangingSign(m: Market, parent: Instance, x: number, z: number, w: number, caption: string, color: Color3, rotated: boolean?)
	local F = m.F * CFrame.new(x, 0, z) * (rotated and CFrame.Angles(0, math.pi / 2, 0) or CFrame.new())
	local H = m.Size.Y
	for _, dx in ipairs({ -w / 2 + 0.6, w / 2 - 0.6 }) do
		box(parent, "SignCord", F, dx - 0.03, dx + 0.03, 11.8, H - 0.8, -0.03, 0.03, DARKSTEEL, M.Metal)
	end
	local board = box(parent, "DeptSign", F, -w / 2, w / 2, 10, 11.8, -0.09, 0.09, color, M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		label(board, face, caption, WHITE, nil, 22, 140)
	end
end

-- Fruits & légumes : étals inclinés le long du mur gauche + 2 bacs ronds
local function produce(m: Market, parent: Instance)
	local F = m.F
	local wood = rgb(196, 150, 104)
	for t, seg in ipairs({ { 21, 27.8 }, { 28.6, 35.4 }, { 36.2, 43 } }) do
		local z0, z1 = seg[1], seg[2]
		box(parent, "ProduceBase", F, -50.9, -45, FLOOR_TOP, 2.6, z0, z1, rgb(120, 170, 96), M.WoodPlanks, true)
		local top = newPart(parent, "ProduceTable", Vector3.new(5.6, 0.25, z1 - z0 - 0.1), F * CFrame.new(-48, 3.05, (z0 + z1) / 2) * CFrame.Angles(0, 0, math.rad(-14)), wood, M.WoodPlanks)
		top.CanCollide = true
		-- cagettes (les fruits : détail de la zone ; de loin, un tas coloré)
		local nz = math.floor((z1 - z0) / 2)
		for k = 0, nz - 1 do
			for c = 0, 1 do
				local zc = z0 + 0.1 + (k + 0.5) * (z1 - z0 - 0.2) / nz
				local P = F * CFrame.new(-48, 3.05, 0) * CFrame.Angles(0, 0, math.rad(-14)) * CFrame.new(-1.2 + c * 2.3, 0.13, zc)
				local fruit = FRUITS[((t * 5 + k * 2 + c) % #FRUITS) + 1]
				newPart(parent, "Crate", Vector3.new(2.1, 0.5, (z1 - z0 - 0.2) / nz - 0.15), P * CFrame.new(0, 0.25, 0), wood:Lerp(WHITE, 0.2), M.WoodPlanks)
				local heap = newPart(parent, "FruitHeap", Vector3.new(1.8, 0.3, (z1 - z0 - 0.2) / nz - 0.35), P * CFrame.new(0, 0.62, 0), fruit[1] :: Color3, M.SmoothPlastic)
				local list = m.Bands.Produce or {}
				m.Bands.Produce = list
				table.insert(list, heap)
			end
		end
		-- panneau prix au-dessus de chaque étal
		local tag = box(parent, "ProducePrice", F, -45.2, -45.1, 5.2, 6.4, (z0 + z1) / 2 - 1.2, (z0 + z1) / 2 + 1.2, YELLOW, M.SmoothPlastic)
		label(tag, Enum.NormalId.Right, ({ "🍎 1.99", "🍊 2.49", "🥬 0.99" })[t], rgb(200, 40, 60), nil, 40, 60)
		box(parent, "PricePost", F, -45.2, -45.1, 3.4, 5.2, (z0 + z1) / 2 - 0.05, (z0 + z1) / 2 + 0.05, DARKSTEEL, M.Metal)
	end
	-- bacs ronds (pastèques, courges)
	for i, z in ipairs({ 26, 37 }) do
		cyl(parent, "ProduceBin", F, -40.5, FLOOR_TOP, z, 2.4, 3, rgb(150, 110, 70), M.WoodPlanks, true)
		cyl(parent, "BinRim", F, -40.5, 2.47, z, 0.15, 3.2, rgb(120, 170, 96), M.SmoothPlastic)
		local heap = cyl(parent, "BinHeap", F, -40.5, 2.62, z, 0.3, 2.6, i == 1 and rgb(60, 140, 60) or rgb(255, 150, 40), M.SmoothPlastic)
		local list = m.Bands.Produce or {}
		m.Bands.Produce = list
		table.insert(list, heap)
	end
	-- balance + panneau
	box(parent, "Scale", F, -45.4, -44.4, 2.6, 3, 28.1, 28.7, rgb(236, 236, 240), M.Metal)
	local sign = box(parent, "DeptSign", F, -50.95, -50.9, 7, 9.4, 24, 40, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Right, Locale.T("🍎 Fruit & veg"), rgb(64, 150, 90), WHITE, 20, 90)
end

-- Boulangerie (coin arrière gauche) : vitrine, étagères à pain, four
local function bakery(m: Market, parent: Instance)
	local F = m.F
	local wood = rgb(206, 160, 110)
	box(parent, "BakeryFloor", F, -50.8, -37.2, FLOOR_TOP, INLAY_TOP, 49, 65.8, rgb(236, 214, 180), M.WoodPlanks)
	box(parent, "BakeryCounter", F, -50.5, -38, FLOOR_TOP, 3.2, 55, 56.8, wood, M.Wood, true)
	box(parent, "BakeryFront", F, -50.3, -38.2, 0.5, 2.9, 54.93, 54.98, rgb(255, 230, 200), M.SmoothPlastic)
	box(parent, "CaseBase", F, -50.2, -38.3, 3.2, 3.3, 55.1, 56.7, WHITE, M.SmoothPlastic)
	local case = box(parent, "BakeryCase", F, -50.2, -38.3, 3.3, 5.1, 55.1, 56.7, rgb(220, 240, 250), M.Glass)
	case.Transparency = 0.6
	-- étagères à pain contre le mur du fond + four
	box(parent, "BreadRack", F, -50, -41, FLOOR_TOP, 7.2, 64.2, 65.9, wood, M.Wood, true)
	for level = 0, 3 do
		local y = 2 + level * 1.5
		box(parent, "BreadShelf", F, -50, -41, y - 0.1, y, 63.7, 64.2, wood:Lerp(WHITE, 0.2), M.Wood)
	end
	box(parent, "Oven", F, -40.4, -37.4, FLOOR_TOP, 6.4, 63.4, 65.9, rgb(200, 204, 214), M.Metal, true)
	box(parent, "OvenDoor", F, -40, -37.8, 1.4, 3.6, 63.3, 63.4, rgb(40, 38, 50), M.Glass)
	box(parent, "OvenGlow", F, -39.8, -38, 1.6, 3.4, 63.36, 63.39, rgb(255, 170, 90), M.SmoothPlastic)
	local sign = box(parent, "DeptSign", F, -50, -41, 8, 10, 65.9, 65.95, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Front, Locale.T("🥖 Bakery"), rgb(170, 110, 60), WHITE, 20, 90)
	hangingSign(m, parent, -44, 52, 8, Locale.T("🥐 Fresh every morning"), rgb(200, 140, 80))
end

-- Frigos à portes vitrées (mur du fond) + bacs de surgelés
local function fridges(m: Market, parent: Instance)
	local F = m.F
	local x0, x1 = -35, -5
	local units = 8
	local uw = (x1 - x0) / units
	box(parent, "FridgeBody", F, x0, x1, FLOOR_TOP, 8.2, 63.4, 65.95, rgb(246, 246, 250), M.SmoothPlastic, true)
	box(parent, "FridgeInside", F, x0 + 0.2, x1 - 0.2, 0.6, 7.6, 63.35, 63.4, rgb(226, 236, 246), M.SmoothPlastic)
	local header = box(parent, "FridgeHeader", F, x0, x1, 8.2, 9.4, 63.2, 65.95, rgb(80, 150, 230), M.SmoothPlastic)
	label(header, Enum.NormalId.Front, Locale.T("❄️ Fresh & frozen"), WHITE, nil, 20, 90)
	for u = 0, units - 1 do
		local ux0 = x0 + u * uw
		local cx = ux0 + uw / 2
		for level = 0, 2 do
			local y = 1.1 + level * 2.2
			box(parent, "FridgeShelf", F, ux0 + 0.25, ux0 + uw - 0.25, y - 0.1, y, 62.2, 63.35, rgb(220, 226, 236), M.Metal)
		end
		local door = box(parent, "FridgeDoor", F, ux0 + 0.08, ux0 + uw - 0.08, 0.5, 7.8, 62, 62.1, rgb(214, 234, 250), M.Glass)
		door.Transparency = 0.6
		box(parent, "FridgeFrame", F, ux0, ux0 + 0.08, 0.4, 7.9, 61.95, 63.4, rgb(200, 204, 214), M.Metal)
		box(parent, "FridgeHandle", F, cx + uw / 2 - 0.5, cx + uw / 2 - 0.35, 3, 5.4, 61.8, 61.95, STEEL, M.Metal)
	end
	box(parent, "FridgeFrame", F, x1 - 0.08, x1, 0.4, 7.9, 61.95, 63.4, rgb(200, 204, 214), M.Metal)
	box(parent, "FridgeKick", F, x0 + 0.1, x1 - 0.1, FLOOR_TOP, 0.5, 61.97, 63.38, rgb(96, 100, 116), M.Metal)
	-- bacs de surgelés (couvercles vitrés)
	for i = 0, 2 do
		local bx0 = -33 + i * 9.4
		box(parent, "Freezer", F, bx0, bx0 + 8, FLOOR_TOP, 2.8, 53.9, 56.3, rgb(236, 240, 246), M.SmoothPlastic, true)
		box(parent, "FreezerBand", F, bx0 + 0.2, bx0 + 7.8, 1.2, 1.7, 53.85, 53.9, rgb(80, 150, 230), M.SmoothPlastic)
		local lid = box(parent, "FreezerLid", F, bx0 + 0.1, bx0 + 7.9, 3.35, 3.45, 54, 56.2, rgb(214, 234, 250), M.Glass)
		lid.Transparency = 0.6
		local heap = box(parent, "FrozenHeap", F, bx0 + 0.3, bx0 + 7.7, 2.8, 3.1, 54.3, 55.9, pick(PASTEL, i, 23), M.SmoothPlastic)
		local list = m.Bands.Back or {}
		m.Bands.Back = list
		table.insert(list, heap)
	end
end

-- Électronique + jouets : mur de télés animées, comptoir, tables à gradins
local TOY_TABLES = { { 30, 26 }, { 30, 38 }, { 39.5, 32 } }
local function showroom(m: Market, parent: Instance)
	local F = m.F
	local hw = m.Size.X / 2
	box(parent, "ShowroomFloor", F, 22.5, hw - 0.2, FLOOR_TOP, INLAY_TOP, 20.2, 44.2, rgb(234, 236, 246), M.SmoothPlastic)
	-- mur de télés (écrans animés : dégradés qui défilent)
	for row = 0, 1 do
		for i = 0, 5 do
			local z = 22.4 + i * 3.4
			local y0 = 5.4 + row * 3
			box(parent, "TVFrame", F, hw - 0.3, hw - 0.05, y0, y0 + 2.4, z, z + 3, rgb(30, 30, 38), M.SmoothPlastic)
			local screen = box(parent, "TVScreen", F, hw - 0.35, hw - 0.3, y0 + 0.12, y0 + 2.28, z + 0.12, z + 2.88, rgb(20, 20, 30), M.SmoothPlastic)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "TV"
			gui.Face = Enum.NormalId.Left
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 16
			gui.LightInfluence = 0
			gui.Brightness = 1
			gui.MaxDistance = 60
			gui.Parent = screen
			local f = Instance.new("Frame")
			f.Size = UDim2.fromScale(1, 1)
			f.BackgroundColor3 = WHITE
			f.BorderSizePixel = 0
			f.Parent = gui
			local g = Instance.new("UIGradient")
			local k = (row * 6 + i) % 4
			local palettes = {
				{ rgb(255, 120, 180), rgb(120, 90, 200), rgb(80, 200, 255) },
				{ rgb(255, 200, 80), rgb(255, 110, 90), rgb(236, 72, 140) },
				{ rgb(90, 220, 170), rgb(70, 150, 230), rgb(150, 110, 220) },
				{ rgb(40, 60, 120), rgb(90, 160, 240), rgb(250, 250, 255) },
			}
			local p = palettes[k + 1]
			g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, p[1]), ColorSequenceKeypoint.new(0.5, p[2]), ColorSequenceKeypoint.new(1, p[3]) })
			g.Rotation = 20 + k * 40
			g.Parent = f
			text(f, "Logo", k == 0 and "🧠" or (k == 1 and "🎮" or (k == 2 and "🌊" or "⭐")), 0.35, 0.25, 0.3, 0.5, WHITE, Enum.Font.GothamBold)
			table.insert(m.TVs, g)
		end
	end
	-- comptoir de l'électronique (vrais objets posés dessus : zone)
	box(parent, "TechCounter", F, 45.4, 48.6, FLOOR_TOP, 2.6, 22, 42.4, rgb(60, 64, 80), M.SmoothPlastic, true)
	box(parent, "TechTop", F, 45.2, 48.8, 2.6, 2.75, 21.8, 42.6, rgb(236, 236, 240), M.Metal)
	box(parent, "TechStripe", F, 45.3, 45.35, 1.2, 1.6, 22.2, 42.2, rgb(80, 200, 255), M.SmoothPlastic)
	local sign = box(parent, "DeptSign", F, hw - 0.1, hw - 0.05, 11.4, 12.3, 24, 40, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Left, Locale.T("📺 Electronics"), rgb(60, 90, 180), WHITE, 20, 90)
	-- tables à gradins des jouets
	for _, t in ipairs(TOY_TABLES) do
		cyl(parent, "ToyTable", F, t[1], FLOOR_TOP, t[2], 1.2, 6, rgb(255, 214, 120), M.SmoothPlastic, true)
		cyl(parent, "ToyTableRim", F, t[1], FLOOR_TOP + 1.2, t[2], 0.1, 6.2, rgb(255, 150, 180), M.SmoothPlastic)
		cyl(parent, "ToyTier", F, t[1], FLOOR_TOP + 1.3, t[2], 1.2, 3.2, rgb(150, 200, 255), M.SmoothPlastic, true)
	end
	hangingSign(m, parent, 34.5, 32, 9, Locale.T("🧸 Toys"), rgb(236, 104, 140), true)
end

local function electronicsSlots(m: Market): { Slot }
	local slots = {}
	for i = 1, 6 do
		local z = 22.2 + (i - 0.5) * 20.2 / 6
		local S = m.F * CFrame.new(47, 2.75, z) * FACE_NX
		table.insert(slots, { CF = S, MaxW = 2.6, MaxH = 2.8, MaxD = 2.4, Tag = m.F * CFrame.new(45.1, 2.3, z) * FACE_NX, WallZ = 1.2 })
	end
	return slots
end

local function toySlots(m: Market): { Slot }
	local slots = {}
	for _, t in ipairs(TOY_TABLES) do
		local x, z = t[1], t[2]
		-- dessus du gradin : face vers l'allée principale / l'allée 8
		table.insert(slots, { CF = m.F * CFrame.new(x, FLOOR_TOP + 2.5, z) * FACE_NX, MaxW = 2.4, MaxH = 3, MaxD = 2.4, Tag = m.F * CFrame.new(x - 1.7, FLOOR_TOP + 2.2, z) * FACE_NX })
		for k = 0, 1 do
			local a = math.rad(200 + k * 140)
			local px, pz = x + math.cos(a) * 2.35, z + math.sin(a) * 2.35
			local P = CFrame.lookAt((m.F * CFrame.new(px, FLOOR_TOP + 1.3, pz)).Position, (m.F * CFrame.new(px + math.cos(a), FLOOR_TOP + 1.3, pz + math.sin(a))).Position)
			table.insert(slots, { CF = P, MaxW = 1.4, MaxH = 2, MaxD = 1.2, Tag = P * CFrame.new(0, -0.3, -0.75) })
		end
	end
	return slots
end

-- 🛋️ Salons d'exposition : deux pièces meublées en taille réelle
local VIGNETTES = {
	{ -2, 12.5, "🛋️ Cozy living room", rgb(236, 214, 200), { "Furniture" },
		{ "SectionalSofa", "Chesterfield", "Sofa", "Fireplace", "BookshelfWall", "TVStand" }, { "GlassCoffeeTable", "Armchair", "CoffeeTable", "EggChair" } },
	{ 14.5, 29, "👑 Luxury suite", rgb(226, 214, 246), { "Luxury", "Furniture" },
		{ "KingBed", "WhitePiano", "AquariumWall", "CanopyBed", "PoolTable" }, { "GoldThrone", "MarbleStatue", "VelvetChaise", "AmethystGeode" } },
}
local function furnitureRooms(m: Market, parent: Instance)
	local F = m.F
	for i, v in ipairs(VIGNETTES) do
		local x0, x1 = v[1] :: number, v[2] :: number
		box(parent, "RoomPlatform", F, x0, x1, FLOOR_TOP, 0.5, 51.5, 65.6, rgb(206, 170, 130), M.WoodPlanks, true)
		box(parent, "RoomRug", F, x0 + 2, x1 - 2, 0.5, 0.56, 53.5, 60.5, (v[4] :: Color3):Lerp(BRAND, 0.15), M.Fabric)
		box(parent, "RoomWall", F, x0 + 0.2, x1 - 0.2, 0.5, 10, 65.6, 65.85, v[4] :: Color3, M.SmoothPlastic)
		box(parent, "RoomTrim", F, x0 + 0.2, x1 - 0.2, 0.5, 1.2, 65.45, 65.6, WHITE, M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			local xx = sx < 0 and x0 + 0.1 or x1 - 0.1
			box(parent, "RoomSide", F, xx - 0.1, xx + 0.1, 0.5, 8, 59, 65.6, WHITE, M.SmoothPlastic)
		end
		local cx = (x0 + x1) / 2
		box(parent, "PlaquePost", F, cx - 0.06, cx + 0.06, 0.5, 1.2, 51.9, 52.02, DARKSTEEL, M.Metal)
		local plaque = box(parent, "RoomPlaque", F, cx - 2.6, cx + 2.6, 1.2, 2.1, 51.8, 51.9, WHITE, M.SmoothPlastic)
		label(plaque, Enum.NormalId.Front, Locale.T(v[3] :: string), BRAND2, WHITE, 40, 60)
		local _ = i
	end
	hangingSign(m, parent, 13.5, 50, 12, Locale.T("🛋️ Furniture showroom"), rgb(160, 116, 84))
end

local function furnitureSlots(m: Market, vignette: number): ({ Slot }, { Slot })
	local v = VIGNETTES[vignette]
	local x0, x1 = v[1] :: number, v[2] :: number
	local cx = (x0 + x1) / 2
	local floor, wall = {}, {}
	-- rang du fond (2 grands meubles contre le mur), rang de devant (2 plus petits)
	for k = -1, 1, 2 do
		local S = m.F * CFrame.new(cx + k * 3.45, 0.56, 62.5) -- LookVector -Z : vers le visiteur
		table.insert(floor, { CF = S, MaxW = 6.2, MaxH = 7.5, MaxD = 5.6, Tag = m.F * CFrame.new(cx + k * 3.45, 1.4, 51.2), Heavy = true })
	end
	for k = -1, 1, 2 do
		local S = m.F * CFrame.new(cx + k * 3.9, 0.56, 55.6)
		table.insert(floor, { CF = S, MaxW = 3.6, MaxH = 5, MaxD = 3.4, Tag = m.F * CFrame.new(cx + k * 3.9, 1.4, 51.2), Heavy = true })
	end
	for k = -1, 1, 2 do
		local S = m.F * CFrame.new(cx + k * 3.6, 6.6, 65.35)
		table.insert(wall, { CF = S, MaxW = 3.4, MaxH = 2.6, MaxD = 1, Tag = m.F * CFrame.new(cx + k * 3.6, 5.8, 64.9), WallZ = 0.2 })
	end
	return floor, wall
end

-- 🪴 Jardinerie : gradins le long du mur droit, sacs de terreau, arrosoirs
local function gardenDecor(m: Market, parent: Instance)
	local F = m.F
	local hw = m.Size.X / 2
	local green = rgb(96, 150, 96)
	box(parent, "GardenFloor", F, 31.2, hw - 0.2, FLOOR_TOP, INLAY_TOP, 49, 65.8, rgb(206, 186, 160), M.Slate)
	for s, seg in ipairs({ { 49.5, 55.5 }, { 56.5, 65.5 } }) do
		local z0, z1 = seg[1], seg[2]
		for step = 0, 2 do
			local x0 = hw - 5.9 + step * 1.8
			box(parent, "GardenStep", F, x0, hw - 0.1 - step * 0.04, FLOOR_TOP, 0.9 + step * 1.3, z0 + step * 0.05, z1 - step * 0.05, green:Lerp(WHITE, step * 0.08), M.WoodPlanks, true)
		end
		for k = 0, 2 do
			local z = z0 + 1 + k * (z1 - z0 - 2) / 2
			cyl(parent, "Pot", F, hw - 0.9, 3.5, z, 0.9, 0.9, rgb(206, 124, 90), M.Slate)
			ball(parent, "Leaves", F, hw - 0.9, 4.8, z, 1.4, rgb(90, 170, 90):Lerp(YELLOW, hash(s, k) * 0.3), M.Grass)
		end
	end
	-- sacs de terreau + arrosoirs
	for i = 0, 2 do
		box(parent, "SoilBag", F, 32.5, 35, FLOOR_TOP + i * 0.72, FLOOR_TOP + 0.7 + i * 0.72, 62.2 + i * 0.1, 65.4 - i * 0.1, i % 2 == 0 and rgb(96, 70, 50) or rgb(120, 160, 80), M.Fabric)
	end
	for k = 0, 2 do
		cyl(parent, "WateringCan", F, 36.5 + k * 1.4, FLOOR_TOP, 64.6, 1, 0.9, pick({ rgb(120, 180, 230), rgb(255, 150, 90), rgb(120, 200, 120) }, k, 3), M.Metal)
	end
	local sign = box(parent, "DeptSign", F, hw - 0.1, hw - 0.05, 11.4, 12.3, 50, 64, WHITE, M.SmoothPlastic)
	label(sign, Enum.NormalId.Left, Locale.T("🪴 Garden"), rgb(64, 140, 80), WHITE, 20, 90)
end

local function gardenSlots(m: Market): { Slot }
	local slots = {}
	local hw = m.Size.X / 2
	for _, seg in ipairs({ { 49.5, 55.5 }, { 56.5, 65.5 } }) do
		local z0, z1 = seg[1], seg[2]
		for k = 0, 1 do
			local x = hw - 5.9 + 1.8 + 0.9
			local z = z0 + 1.8 + k * (z1 - z0 - 3.6)
			local y = 0.9 + 1.3
			local S = m.F * CFrame.new(x, y, z) * FACE_NX
			table.insert(slots, { CF = S, MaxW = 1.6, MaxH = 2.6, MaxD = 1.6, Tag = m.F * CFrame.new(x - 1, y - 0.2, z) * FACE_NX })
		end
	end
	-- îlot de grandes plantes au milieu
	for k = 0, 1 do
		local S = m.F * CFrame.new(38 + k * 5, FLOOR_TOP, 53) -- (LookVector -Z : vers le visiteur)
		table.insert(slots, { CF = S, MaxW = 3, MaxH = 6, MaxD = 3, Tag = m.F * CFrame.new(38 + k * 5, 0.4, 51.2), Heavy = true })
	end
	return slots
end

-- Caisses : 6 caisses tenues (tapis animé) + 4 caisses automatiques ;
-- invites « Passer en caisse »
----------------------------------------------------------------------
-- 🛒 CAISSES (v9.9, SHOPS99) : module MarketCheckout (5 vraies caisses,
-- 4 caisses automatiques, file de clients, animations)
----------------------------------------------------------------------

local function Checkout(): any
	if not V99.Checkout then
		V99.Checkout = require(script.Parent.MarketCheckout)
		V99.Checkout.Init({
			box = box,
			cyl = cyl,
			cylX = cylX,
			newPart = newPart,
			label = label,
			text = text,
			corner = corner,
			printLabel = printLabel,
			pick = pick,
			hash = hash,
			actor = actor,
			hangingSign = hangingSign,
			NPC = NPC,
			PALETTE = PALETTE,
			FLOOR_TOP = FLOOR_TOP,
			LANES = LANES,
			OPEN_LANES = OPEN_LANES,
			AddParts = function(n: number)
				partCount += n
			end,
		})
	end
	return V99.Checkout
end


-- Entrée : portiques, chariots, paniers, tapis, palette promo, écran « en direct »
local function entrance(m: Market, parent: Instance)
	local F = m.F
	for k = 0, 5 do
		partCount += countParts(cart(parent, F * CFrame.new(-10, FLOOR_TOP, 1.6 + k * 1.3), rgb(236, 72, 140)))
	end
	box(parent, "CartRail", F, -11.1, -10.95, FLOOR_TOP, 2.8, 0.6, 9.6, STEEL, M.Metal)
	-- paniers empilés
	box(parent, "Baskets", F, -10.6, -9.4, FLOOR_TOP, 1.8, 10.6, 11.6, rgb(236, 72, 90), M.SmoothPlastic)
	box(parent, "BasketHandles", F, -10.65, -9.35, 1.8, 2.1, 11, 11.2, rgb(40, 40, 50), M.SmoothPlastic)
	-- portiques antivol
	for _, x in ipairs({ -7.6, 7.6 }) do
		box(parent, "Gate", F, x - 0.12, x + 0.12, FLOOR_TOP, 5.2, 0.8, 2.2, rgb(200, 204, 214), M.Metal)
		box(parent, "GateFoot", F, x - 0.3, x + 0.3, FLOOR_TOP, 0.3, 0.7, 2.3, DARKSTEEL, M.Metal)
	end
	-- tapis d'accueil
	box(parent, "Welcome", F, -5.4, 5.4, INLAY_TOP, 0.14, 0.3, 3.6, BRAND2, M.Fabric)
	-- palette promo au milieu de l'allée principale
	box(parent, "Pallet", F, -2.2, 2.2, INLAY_TOP, 0.55, 15.6, 19.4, rgb(196, 150, 104), M.WoodPlanks, true)
	for i = 0, 5 do
		local x = -1.4 + (i % 3) * 1.4
		local zz = 16.6 + math.floor(i / 3) * 1.8
		local c = pick(PALETTE, i + 60, 51)
		local b = box(parent, "PromoCase", F, x - 0.62, x + 0.62, 0.55, 1.65, zz - 0.8, zz + 0.8, c, M.SmoothPlastic)
		if i < 3 then
			printLabel(b, Enum.NormalId.Front, "MegaDopa", "🧠", c, 50)
		end
	end
	box(parent, "PalletTop", F, -1.3, 1.3, 1.65, 2.65, 16.8, 18.2, YELLOW, M.SmoothPlastic)
	box(parent, "PalletPole", F, -0.06, 0.06, 2.65, 3.25, 17.44, 17.56, DARKSTEEL, M.Metal)
	local sign = box(parent, "PalletSign", F, -1.6, 1.6, 3.25, 5.05, 17.45, 17.55, WHITE, M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		label(sign, face, Locale.T("🧠 Brainy deals!"), BRAND, WHITE, 40, 70)
	end
	-- écran suspendu « en direct sur le serveur » (face vers l'entrée)
	local H = m.Size.Y
	for _, dx in ipairs({ -3, 3 }) do
		box(parent, "ScreenCord", F, dx - 0.03, dx + 0.03, 14.6, H - 0.8, 12.47, 12.53, DARKSTEEL, M.Metal)
	end
	box(parent, "LiveBezel", F, -4.1, 4.1, 9.6, 14.6, 12.5, 12.9, rgb(30, 28, 40), M.Metal)
	local screen = box(parent, "LiveScreen", F, -3.9, 3.9, 9.8, 14.4, 12.44, 12.5, rgb(24, 20, 40), M.SmoothPlastic)
	buildBoard(m, screen, "Server", "full", 60)
	-- dos de l'écran : logo
	local backLogo = box(parent, "LiveBack", F, -3.9, 3.9, 9.8, 14.4, 12.9, 12.96, BRAND2, M.SmoothPlastic)
	label(backLogo, Enum.NormalId.Back, "🧠 MegaDopa", WHITE, nil, 20, 90)
end

-- 💎 Boutique Robux : structure (moquette, cloisons, socles, présentoir)
local PASS_X = { -48.4, -44.4, -40.4, -36.4 }
local PASS_Z = 10.3

local function robuxShell(m: Market, parent: Instance)
	local F = m.F
	-- moquette violette + bordure dorée (4 bandes autour, jamais superposées)
	box(parent, "RobuxCarpet", F, -50.3, -33.3, FLOOR_TOP, INLAY_TOP, 0.7, 13.8, rgb(86, 52, 150), M.Fabric)
	box(parent, "RobuxBorder", F, -50.8, -50.3, FLOOR_TOP, INLAY_TOP, 0.2, 14.3, GOLD, M.SmoothPlastic)
	box(parent, "RobuxBorder", F, -33.3, -32.8, FLOOR_TOP, INLAY_TOP, 0.2, 14.3, GOLD, M.SmoothPlastic)
	box(parent, "RobuxBorder", F, -50.3, -33.3, FLOOR_TOP, INLAY_TOP, 0.2, 0.7, GOLD, M.SmoothPlastic)
	box(parent, "RobuxBorder", F, -50.3, -33.3, FLOOR_TOP, INLAY_TOP, 13.8, 14.3, GOLD, M.SmoothPlastic)
	-- cloisons basses vitrées (ouvertes vers l'entrée et l'allée principale)
	local function partition(x0: number, x1: number, z0: number, z1: number)
		box(parent, "PartitionBase", F, x0, x1, INLAY_TOP, 0.8, z0, z1, ROBUX_DARK, M.SmoothPlastic, true)
		local g = box(parent, "PartitionGlass", F, x0 + 0.02, x1 - 0.02, 0.8, 3.4, z0 + 0.03, z1 - 0.03, rgb(200, 190, 250), M.Glass, true)
		g.Transparency = 0.55
		box(parent, "PartitionRail", F, x0, x1, 3.4, 3.55, z0 - 0.02, z1 + 0.02, GOLD, M.Metal)
	end
	partition(-50.8, -41, 14.3, 14.6)
	partition(-32.8, -32.5, 0.3, 6.5)
	-- grand panneau suspendu
	hangingSign(m, parent, -45.5, 14.1, 10, Locale.T("💎 Robux Shop"), ROBUX)
	-- présentoir mural des cartes cadeaux
	box(parent, "Pegboard", F, -50.2, -37.2, 0.8, 9.6, 0.1, 0.3, rgb(120, 90, 200), M.SmoothPlastic)
	local head = box(parent, "PegHeader", F, -50.2, -37.2, 9.6, 10.8, 0.1, 0.34, ROBUX_DARK, M.SmoothPlastic)
	label(head, Enum.NormalId.Back, Locale.T("🎁 Robux gift cards"), rgb(255, 214, 120), nil, 24, 80)
	-- socles des Game Passes (cloche vitrée, bordure dorée)
	for i, x in ipairs(PASS_X) do
		local c = ({ rgb(150, 110, 220), rgb(80, 150, 230), rgb(70, 200, 200), rgb(236, 190, 90) })[i]
		cyl(parent, "PassPedestal", F, x, INLAY_TOP, PASS_Z, 3, 2.4, c:Lerp(ROBUX_DARK, 0.35), M.SmoothPlastic, true)
		cyl(parent, "PassRim", F, x, INLAY_TOP + 3, PASS_Z, 0.12, 2.6, GOLD, M.Metal)
		local case = box(parent, "PassCase", F, x - 1.05, x + 1.05, INLAY_TOP + 3.12, INLAY_TOP + 5.3, PASS_Z - 1.05, PASS_Z + 1.05, rgb(220, 230, 255), M.Glass)
		case.Transparency = 0.55
		case.Reflectance = 0.1
		box(parent, "PassCaseTop", F, x - 1.1, x + 1.1, INLAY_TOP + 5.3, INLAY_TOP + 5.38, PASS_Z - 1.1, PASS_Z + 1.1, GOLD, M.Metal)
	end
	-- coin « Bientôt » (étagère contre le mur de gauche)
	box(parent, "SoonShelf", F, -50.9, -49.4, INLAY_TOP, 6.2, 3, 12.6, rgb(236, 226, 250), M.SmoothPlastic, true)
	for level = 0, 1 do
		box(parent, "SoonBoard", F, -50.85, -49.2, 2.2 + level * 2.4, 2.32 + level * 2.4, 3.05, 12.55, GOLD, M.Metal)
	end
	local soon = box(parent, "SoonSign", F, -49.35, -49.3, 6.4, 7.6, 4, 11.6, SOONPINK, M.SmoothPlastic)
	label(soon, Enum.NormalId.Right, Locale.T("🔜 Coming soon"), WHITE, nil, 30, 60)
	-- comptoir du vendeur
	box(parent, "RobuxDesk", F, -36.2, -33.4, INLAY_TOP, 3.2, 1.4, 2.8, ROBUX_DARK, M.SmoothPlastic, true)
	box(parent, "RobuxDeskTop", F, -36.4, -33.2, 3.2, 3.35, 1.25, 2.95, GOLD, M.Marble)
end

-- ☕ Café + 🍕 aire de restauration : comptoirs, machines, menus, tables
local CAFE_TABLES = { { -27, 9.8 }, { -21, 11.8 }, { -15.5, 9.3 } }
local KIOSKS = {
	{ -30, -22.6, "☕ Café Dopa", rgb(170, 110, 60), "Cafe" },
	{ -20.6, -13, "🍕 Pizza Brain", rgb(214, 70, 60), "Pizza" },
}
local cafeSeats: { CFrame } = {}

local function cafeShell(m: Market, parent: Instance)
	local F = m.F
	box(parent, "CafeFloor", F, -30.8, -12.2, FLOOR_TOP, INLAY_TOP, 0.2, 14.3, rgb(214, 170, 124), M.WoodPlanks)
	for _, k in ipairs(KIOSKS) do
		local x0, x1, accent = k[1] :: number, k[2] :: number, k[4] :: Color3
		box(parent, "BackCounter", F, x0, x1, INLAY_TOP, 3.4, 0.3, 1.8, rgb(90, 70, 60), M.Wood, true)
		box(parent, "BackTop", F, x0, x1, 3.4, 3.5, 0.3, 1.9, rgb(236, 236, 240), M.Marble)
		box(parent, "FrontCounter", F, x0, x1, INLAY_TOP, 3.4, 3.6, 5.2, rgb(250, 244, 236), M.SmoothPlastic, true)
		box(parent, "FrontPanel", F, x0 + 0.2, x1 - 0.2, 0.5, 3, 3.52, 3.57, accent, M.WoodPlanks)
		box(parent, "FrontTop", F, x0 - 0.1, x1 + 0.1, 3.4, 3.55, 3.5, 5.3, rgb(236, 236, 240), M.Marble)
		-- auvent rayé
		local n = 4
		for i = 0, n - 1 do
			local a = x0 + i * (x1 - x0) / n
			box(parent, "Awning", F, a, a + (x1 - x0) / n, 8.8, 9.3, 0.2, 5.8, i % 2 == 0 and accent or WHITE, M.Fabric)
		end
		-- menu au mur
		local menu = box(parent, "MenuBoard", F, x0 + 0.5, x1 - 0.5, 5.2, 8.4, 0.1, 0.18, rgb(40, 36, 44), M.SmoothPlastic)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Menu"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0.3
		gui.MaxDistance = 60
		gui.Parent = menu
		text(gui, "Title", Locale.T(k[3] :: string), 0.05, 0.04, 0.9, 0.26, rgb(255, 214, 120), Enum.Font.FredokaOne)
		local lines = k[5] == "Cafe" and { "☕ Espresso · 2.20", "🥛 Latte · 3.50", "🧋 Bubble tea · 4.20", "🥐 Croissant · 1.60" }
			or { "🍕 Margherita · 8.90", "🍕 4 cheeses · 10.50", "🥗 Salad · 6.40", "🥤 Soda · 2.00" }
		for i, line in ipairs(lines) do
			text(gui, "Line" .. i, Locale.T(line), 0.08, 0.3 + (i - 1) * 0.165, 0.84, 0.14, WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
		end
		if k[5] == "Cafe" then
			-- machine à expresso + vitrine à viennoiseries
			box(parent, "Espresso", F, x0 + 0.8, x0 + 3, 3.5, 5.1, 0.5, 1.6, STEEL, M.Metal)
			box(parent, "EspressoTop", F, x0 + 0.8, x0 + 3, 5.1, 5.3, 0.5, 1.6, rgb(60, 50, 50), M.SmoothPlastic)
			for c = 0, 1 do
				cyl(parent, "Cup", F, x0 + 1.4 + c * 1, 3.5, 1.75, 0.35, 0.3, WHITE, M.SmoothPlastic)
			end
			box(parent, "Grinder", F, x0 + 3.5, x0 + 4.3, 3.5, 5, 0.6, 1.4, rgb(40, 40, 46), M.SmoothPlastic)
			local case = box(parent, "PastryCase", F, x1 - 3.4, x1 - 0.4, 3.55, 4.9, 3.8, 5, rgb(220, 240, 250), M.Glass)
			case.Transparency = 0.55
		else
			-- four à pizza (dôme en briques)
			ball(parent, "PizzaOven", F, x1 - 2, 3.5, 1.3, 2.4, rgb(176, 96, 70), M.Brick)
			box(parent, "OvenMouth", F, x1 - 2.6, x1 - 1.4, 3.55, 4.25, 2.3, 2.46, rgb(120, 52, 30), M.SmoothPlastic)
			box(parent, "PizzaPeel", F, x0 + 0.8, x0 + 1.2, 3.5, 6.2, 0.4, 0.6, rgb(190, 140, 90), M.Wood)
		end
	end
	-- tables rondes + chaises (assise à 1,9 : hauteur des bancs de la ville)
	table.clear(cafeSeats)
	for _, t in ipairs(CAFE_TABLES) do
		local tx, tz = t[1], t[2]
		cyl(parent, "TableFoot", F, tx, INLAY_TOP, tz, 0.1, 1.4, rgb(60, 56, 66), M.Metal)
		cyl(parent, "TableLeg", F, tx, INLAY_TOP + 0.1, tz, 2.35, 0.3, rgb(60, 56, 66), M.Metal, true)
		cyl(parent, "TableTop", F, tx, 2.55, tz, 0.15, 2.8, WHITE, M.Marble)
		for c = 0, 2 do
			local a = math.rad(90 + c * 120)
			local px, pz = tx + math.cos(a) * 2, tz + math.sin(a) * 2
			local pos = (F * CFrame.new(px, INLAY_TOP, pz)).Position
			local C = CFrame.lookAt(pos, (F * CFrame.new(tx, INLAY_TOP, tz)).Position)
			newPart(parent, "ChairSeat", Vector3.new(1.3, 0.18, 1.3), C * CFrame.new(0, 1.9 - INLAY_TOP - 0.09, 0), rgb(236, 110, 140), M.SmoothPlastic, true)
			newPart(parent, "ChairBack", Vector3.new(1.3, 1.5, 0.14), C * CFrame.new(0, 1.9 - INLAY_TOP + 0.75, 0.6), rgb(236, 110, 140), M.SmoothPlastic)
			local leg = newPart(parent, "ChairLeg", Vector3.new(1.72 - INLAY_TOP, 0.22, 0.22), C * CFrame.new(0, (1.72 - INLAY_TOP) / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(60, 56, 66), M.Metal)
			;(leg :: Part).Shape = Enum.PartType.Cylinder
			table.insert(cafeSeats, C)
		end
	end
	hangingSign(m, parent, -21.4, 14.1, 10, Locale.T("🍽️ Food court"), rgb(214, 110, 70))
end

----------------------------------------------------------------------
-- Détail par zone (produits, vrais objets, personnages)
----------------------------------------------------------------------

-- Produits d'une face (générique : 4 niveaux ; "Real:" : niveaux 1 et 4 en cartons)
local function faceProducts(m: Market, parent: Instance, index: number, level: number)
	local spec = FACES[index]
	local S = faceFrame(m.F, spec[1] :: number, spec[2] :: number)
	local kind = spec[3] :: string
	local half = (GZ1 - GZ0) / 2 - 0.35
	local seed = index * 101
	local real = string.sub(kind, 1, 5) == "Real:"
	local tint = nil
	if real then
		local first = string.split(string.sub(kind, 6), ",")[1]
		tint = HouseCommon.CategoryTint(first)
	end
	local y = LEVELS[level]
	local rowKind
	if real then
		if level == 2 or level == 3 then
			return
		end
		rowKind = "Boxed"
	elseif kind == "Cereal" then
		rowKind = level == 1 and "Boxed" or "Cereal"
	elseif kind == "Breakfast" then
		rowKind = ({ "Boxed", "Jar", "Pasta", "Cereal" })[level]
	elseif kind == "Drinks" then
		rowKind = level == 1 and "Pack" or "Bottle"
	elseif kind == "Sodas" then
		rowKind = ({ "Pack", "Can", "Can", "Bottle" })[level]
	elseif kind == "Pantry" then
		rowKind = ({ "Boxed", "Can", "Pasta", "Can" })[level]
	elseif kind == "Snacks" then
		rowKind = level == 1 and "Boxed" or "Snack"
	elseif kind == "Candy" then
		rowKind = level == 1 and "Boxed" or "Jar"
	else
		rowKind = level == 1 and "Pack" or "Care"
	end
	productRow(parent, S, y, rowKind, seed + level * 13, -half, half, tint)
end

-- Vrais objets de la maison sur une face "Real:" (2 niveaux x 3 objets)
local function realSlots(m: Market, index: number): { Slot }
	local spec = FACES[index]
	local S = faceFrame(m.F, spec[1] :: number, spec[2] :: number)
	local slots = {}
	local len = GZ1 - GZ0 - 0.8
	local first = string.split(string.sub(spec[3] :: string, 6), ",")[1]
	local tint = HouseCommon.CategoryTint(first)
	for _, level in ipairs({ 2, 3 }) do
		local y = LEVELS[level]
		for i = 1, 3 do
			local x = -len / 2 + (i - 0.5) * len / 3
			table.insert(slots, {
				CF = S * CFrame.new(x, y, 0.62),
				MaxW = 3.2,
				MaxH = CLEAR - 0.1,
				MaxD = 1.05,
				Tag = S * CFrame.new(x, y - 0.25, -0.14),
				WallZ = 1.24 - 0.62 - 0.06 - GAP,
				Flank = len / 3 / 2 - 0.12,
				Tint = tint,
			})
		end
	end
	return slots
end

local function isWall(def: any): boolean
	return def.Placement == "Wall"
end

local ZONE_SPECS: { { any } } -- (rempli plus bas : nom, x, z, constructeur)

local function groceryZone(g: number): (Market, Instance, { () -> () }) -> ()
	return function(m: Market, parent: Instance, jobs: { () -> () })
		for index, spec in ipairs(FACES) do
			if spec[1] == g then
				for level = 1, 4 do
					table.insert(jobs, function()
						faceProducts(m, parent, index, level)
					end)
				end
			end
		end
	end
end

local function homeZone(g: number): (Market, Instance, { () -> () }) -> ()
	return function(m: Market, parent: Instance, jobs: { () -> () })
		for index, spec in ipairs(FACES) do
			if spec[1] == g then
				for _, level in ipairs({ 1, 4 }) do
					table.insert(jobs, function()
						faceProducts(m, parent, index, level)
					end)
				end
				local categories = string.split(string.sub(spec[3] :: string, 6), ",")
				fillJobs(m, parent, "Home" .. g, jobs, realSlots(m, index), categoryEntries(categories))
			end
		end
	end
end

local function produceZone(m: Market, parent: Instance, jobs: { () -> () })
	local F = m.F
	for t, seg in ipairs({ { 21, 27.8 }, { 28.6, 35.4 }, { 36.2, 43 } }) do
		table.insert(jobs, function()
			local z0, z1 = seg[1], seg[2]
			local nz = math.floor((z1 - z0) / 2)
			for k = 0, nz - 1 do
				for c = 0, 1 do
					local zc = z0 + 0.1 + (k + 0.5) * (z1 - z0 - 0.2) / nz
					local P = F * CFrame.new(-48, 3.05, 0) * CFrame.Angles(0, 0, math.rad(-14)) * CFrame.new(-1.2 + c * 2.3, 0.13, zc)
					local fruit = FRUITS[((t * 5 + k * 2 + c) % #FRUITS) + 1]
					local color, dia = fruit[1] :: Color3, fruit[2] :: number
					local cols = math.max(2, math.floor(1.7 / dia))
					local rows = math.max(1, math.floor(((z1 - z0 - 0.2) / nz - 0.4) / dia))
					for q = 0, cols - 1 do
						for r = 0, rows - 1 do
							local qx = -0.85 + (q + 0.5) * 1.7 / cols
							local qz = -((rows - 1) * dia) / 2 + r * dia
							ball(parent, "Fruit", P, qx, 0.5 + dia / 2 - 0.05, qz, dia * 0.96, color:Lerp(WHITE, hash(q + r, t) * 0.1), M.SmoothPlastic)
						end
					end
				end
			end
		end)
	end
	table.insert(jobs, function()
		for i, z in ipairs({ 26, 37 }) do
			for k = 0, 4 do
				local a = k / 5 * math.pi * 2
				local d = i == 1 and 1.1 or 0.8
				ball(parent, "BigFruit", F, -40.5 + math.cos(a) * 0.75, 2.62 + d / 2, z + math.sin(a) * 0.75, d, i == 1 and rgb(60, 140, 60) or rgb(255, 150, 40), M.SmoothPlastic)
			end
		end
	end)
end

local function backLeftZone(m: Market, parent: Instance, jobs: { () -> () })
	local F = m.F
	-- pains sur les étagères, gâteaux et viennoiseries en vitrine
	table.insert(jobs, function()
		for level = 0, 3 do
			local y = 2 + level * 1.5
			for k = 0, 5 do
				local x = -49.2 + k * 1.45
				local loaf = newPart(parent, "Loaf", Vector3.new(1.2, 0.5, 0.5), F * CFrame.new(x, y + 0.25, 63.95) * CFrame.Angles(0, math.rad(15 + (k % 2) * 20), 0), rgb(214, 150, 80):Lerp(rgb(170, 110, 60), (level % 2) * 0.4), M.SmoothPlastic)
				;(loaf :: Part).Shape = Enum.PartType.Cylinder
			end
		end
		for i = 0, 8 do
			local x = -49.4 + i * 1.3
			if i % 3 == 0 then
				ball(parent, "Pastry", F, x, 3.6, 55.9, 0.62, rgb(236, 170, 90), M.SmoothPlastic)
			elseif i % 3 == 1 then
				cyl(parent, "Cake", F, x, 3.3, 55.9, 0.6, 1, i == 4 and rgb(255, 180, 210) or rgb(250, 240, 220), M.SmoothPlastic)
				ball(parent, "Cherry", F, x, 4, 55.9, 0.2, rgb(220, 40, 60), M.SmoothPlastic)
			else
				box(parent, "Tart", F, x - 0.45, x + 0.45, 3.3, 3.55, 55.5, 56.3, rgb(255, 214, 120), M.SmoothPlastic)
			end
		end
	end)
	-- produits des frigos (lait, jus, yaourts)
	table.insert(jobs, function()
		local x0, x1, units = -35, -5, 8
		local uw = (x1 - x0) / units
		for u = 0, units - 1 do
			local ux0 = x0 + u * uw
			for level = 0, 2 do
				local y = 1.1 + level * 2.2
				for k = 0, 3 do
					local x = ux0 + 0.6 + k * (uw - 1.2) / 3
					local color = pick(PASTEL, u * 11 + level * 3 + k, 21)
					if (u + level) % 2 == 0 then
						cyl(parent, "Milk", F, x, y, 62.75, 1.2, 0.5, color, M.SmoothPlastic)
					else
						box(parent, "Yogurt", F, x - 0.28, x + 0.28, y, y + 0.7, 62.45, 63.05, color, M.SmoothPlastic)
					end
				end
			end
		end
		for i = 0, 2 do
			local bx0 = -33 + i * 9.4
			for k = 0, 5 do
				local x = bx0 + 0.8 + k * 1.28
				box(parent, "FrozenBox", F, x - 0.55, x + 0.55, 2.8, 3.25, 54.3, 55.9, pick(PALETTE, i * 7 + k, 23), M.SmoothPlastic)
			end
		end
	end)
	table.insert(jobs, function()
		actor(m, parent, "BackLeft", "baker", 31, F * CFrame.new(-44, INLAY_TOP, 59.5), "idle")
	end)
end


local function entranceZone(m: Market, parent: Instance, jobs: { () -> () })
	table.insert(jobs, function()
		actor(m, parent, "Entrance", "salesperson", 5, m.F * CFrame.new(5.5, INLAY_TOP, 4.6), "wave", { Prop = "none" })
	end)
end

local PASS_COLORS = { rgb(150, 110, 220), rgb(80, 150, 230), rgb(70, 200, 200), rgb(236, 190, 90) }

local function robuxZone(m: Market, parent: Instance, jobs: { () -> () })
	local F = m.F
	local offers = robuxOffers()
	local passes, ready, soon = {}, {}, {}
	for _, o in ipairs(offers) do
		if o.IsPass then
			table.insert(passes, o)
		elseif o.Soon then
			table.insert(soon, o)
		elseif o.Id ~= 0 then
			table.insert(ready, o)
		end
	end
	-- Game Passes : emblème qui tourne dans la cloche, plaque, invite
	table.insert(jobs, function()
		for i, o in ipairs(passes) do
			local x = PASS_X[i]
			if not x then
				break
			end
			local c = PASS_COLORS[i] or ROBUX
			local gem = newPart(parent, "PassGem", Vector3.new(1, 1, 1), F * CFrame.new(x, INLAY_TOP + 4.2, PASS_Z) * CFrame.Angles(math.rad(45), 0, math.rad(45)), c, M.Glass)
			gem.Transparency = 0.15
			gem.Reflectance = 0.2
			table.insert(m.Spinners, { Part = gem, Base = F * CFrame.new(x, INLAY_TOP + 4.2, PASS_Z), Owner = "Robux", Offset = i * 0.9, Pos = gem.Position })
			local bb = Instance.new("BillboardGui")
			bb.Name = "Icon"
			bb.Size = UDim2.fromScale(1.2, 1.2)
			bb.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
			bb.MaxDistance = 45
			bb.LightInfluence = 0
			bb.Parent = gem
			text(bb, "Icon", tostring(o.Def.Icon or "💎"), 0, 0, 1, 1, WHITE, Enum.Font.GothamBold)
			-- plaque devant le socle (nom, effet, prix)
			local plaque = box(parent, "PassPlaque", F, x - 1.1, x + 1.1, 0.7, 2.9, PASS_Z - 1.36, PASS_Z - 1.26, ROBUX_DARK, M.SmoothPlastic)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Plaque"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 60
			gui.LightInfluence = 0.2
			gui.MaxDistance = 40
			gui.Parent = plaque
			local head = Instance.new("Frame")
			head.Size = UDim2.fromScale(1, 0.26)
			head.BackgroundColor3 = c
			head.BorderSizePixel = 0
			head.Parent = gui
			text(head, "Name", tostring(o.Def.Icon or "") .. " " .. Locale.T(tostring(o.Def.Name)), 0.04, 0.1, 0.92, 0.8, WHITE, Enum.Font.FredokaOne)
			text(gui, "Desc", Locale.T(tostring(o.Def.Description or "")), 0.06, 0.3, 0.88, 0.36, WHITE, Enum.Font.Gotham)
			text(gui, "Forever", "♾️ " .. Locale.T("Bought once, yours forever"), 0.06, 0.64, 0.88, 0.12, rgb(200, 190, 240), Enum.Font.Gotham)
			local price = text(gui, "Price", "", 0.1, 0.78, 0.8, 0.18, rgb(255, 214, 120), Enum.Font.FredokaOne)
			robuxDisplay(m, parent, "Robux", o, F * CFrame.new(x, 2.6, PASS_Z - 1.8), price)
		end
	end)
	-- cartes cadeaux (produits Robux prêts à la vente) : 6 colonnes x 2 rangées
	table.insert(jobs, function()
		local cols, x0, x1 = 6, -50, -37.4
		local cw = (x1 - x0) / cols
		for i, o in ipairs(ready) do
			if i > cols * 2 then
				break
			end
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local cx = x0 + (col + 0.5) * cw
			local y0 = row == 0 and 5.4 or 1.4
			local kind = tostring(o.Def.Kind)
			local color = kind == "Tickets" and rgb(255, 176, 32) or (kind == "Boost" and rgb(255, 110, 90) or (kind == "ServerRush" and rgb(236, 72, 140) or rgb(80, 150, 230)))
			local card = box(parent, "GiftCard", F, cx - cw / 2 + 0.2, cx + cw / 2 - 0.2, y0, y0 + 3.2, 0.34, 0.66, color, M.SmoothPlastic)
			box(parent, "Peg", F, cx - 0.05, cx + 0.05, y0 + 3.25, y0 + 3.35, 0.3, 0.9, STEEL, M.Metal)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Card"
			gui.Face = Enum.NormalId.Back
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 60
			gui.LightInfluence = 0.2
			gui.MaxDistance = 40
			gui.Parent = card
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(WHITE, rgb(220, 210, 255))
			g.Rotation = 90
			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromScale(0.9, 0.62)
			bg.Position = UDim2.fromScale(0.05, 0.05)
			bg.BackgroundColor3 = WHITE
			bg.BackgroundTransparency = 0.2
			bg.Parent = gui
			g.Parent = bg
			corner(bg, 0.1)
			text(bg, "Icon", tostring(o.Def.Icon or "💎"), 0.2, 0.04, 0.6, 0.5, WHITE, Enum.Font.GothamBold)
			text(bg, "Name", Locale.T(tostring(o.Def.Name)), 0.05, 0.56, 0.9, 0.2, ROBUX_DARK, Enum.Font.FredokaOne)
			text(bg, "Desc", Locale.T(tostring(o.Def.Description or "")), 0.05, 0.77, 0.9, 0.19, INK, Enum.Font.Gotham)
			local price = text(gui, "Price", "", 0.08, 0.72, 0.84, 0.16, WHITE, Enum.Font.FredokaOne)
			if type(o.Def.Tag) == "string" then
				text(gui, "Ribbon", Locale.T(o.Def.Tag), 0.05, 0.89, 0.9, 0.09, rgb(255, 236, 150), Enum.Font.GothamBold)
			end
			robuxDisplay(m, parent, "Robux", o, F * CFrame.new(cx, y0 + 1.6, 1.2), price)
		end
	end)
	-- coin « Bientôt » : boîtes emballées (sans invite d'achat)
	table.insert(jobs, function()
		for i, o in ipairs(soon) do
			if i > 8 then
				break
			end
			local level = math.floor((i - 1) / 4)
			local z = 3.6 + ((i - 1) % 4) * 2.3
			local y = 2.32 + level * 2.4
			local c = pick(PASTEL, i, 81)
			local gift = box(parent, "SoonBox", F, -50.8, -49.5, y, y + 1.6, z - 0.9, z + 0.9, c, M.SmoothPlastic)
			box(parent, "SoonRibbon", F, -49.5, -49.46, y, y + 1.6, z - 0.12, z + 0.12, SOONPINK, M.SmoothPlastic)
			local gui = label(gift, Enum.NormalId.Right, tostring(o.Def.Icon or "🎁") .. " " .. Locale.T(tostring(o.Def.Name)), ROBUX_DARK, nil, 40, 30)
			gui.Name = "Soon"
			robuxDisplay(m, parent, "Robux", o, F * CFrame.new(-49, y + 0.8, z), nil)
		end
	end)
	table.insert(jobs, function()
		actor(m, parent, "Robux", "salesperson", 44, F * CFrame.new(-34.8, INLAY_TOP, 0.75) * FACE_BACK, "type", { Shirt = ROBUX })
	end)
end

local function cafeZone(m: Market, parent: Instance, jobs: { () -> () })
	local F = m.F
	table.insert(jobs, function()
		actor(m, parent, "Cafe", "baker", 52, F * CFrame.new(-26.3, INLAY_TOP, 2.6) * FACE_BACK, "talk", { Prop = "none" })
		actor(m, parent, "Cafe", "baker", 58, F * CFrame.new(-18.6, INLAY_TOP, 2.6) * FACE_BACK, "idle", { Prop = "none", Shirt = rgb(214, 70, 60) })
	end)
	table.insert(jobs, function()
		-- clients attablés (assis) + tasses / parts de pizza sur les tables
		for i, index in ipairs({ 1, 8 }) do
			local seat = cafeSeats[index]
			if seat then
				actor(m, parent, "Cafe", i == 2 and "elder" or "shopper", 60 + i * 3, seat, "sit", { Prop = i == 1 and "coffee" or "none", SitHeight = 1.9 - INLAY_TOP })
			end
		end
		for i, t in ipairs(CAFE_TABLES) do
			cyl(parent, "Cup", F, t[1] + 0.5, 2.7, t[2] - 0.3, 0.35, 0.3, WHITE, M.SmoothPlastic)
			if i ~= 2 then
				cyl(parent, "Plate", F, t[1] - 0.4, 2.7, t[2] + 0.3, 0.06, 1, WHITE, M.SmoothPlastic)
				local slice = Instance.new("WedgePart")
				slice.Name = "PizzaSlice"
				slice.Anchored = true
				slice.CanCollide = false
				slice.CanQuery = false
				slice.CanTouch = false
				slice.CastShadow = false
				slice.Size = Vector3.new(0.1, 0.5, 0.7)
				slice.CFrame = F * CFrame.new(t[1] - 0.4, 2.81, t[2] + 0.3) * CFrame.Angles(0, 0, math.rad(90))
				slice.Color = rgb(255, 196, 90)
				slice.Material = M.SmoothPlastic
				slice.Parent = parent
				partCount += 1
			end
		end
		-- pizzas sur le comptoir, croissants en vitrine
		for k = 0, 1 do
			cyl(parent, "Pizza", F, -19.6 + k * 2.2, 3.55, 4.4, 0.12, 1.8, rgb(236, 120, 70), M.SmoothPlastic)
		end
		for k = 0, 3 do
			ball(parent, "Croissant", F, -26.3 + k * 0.7, 3.8, 4.4, 0.45, rgb(236, 170, 90), M.SmoothPlastic)
		end
	end)
end

local function showroomZone(m: Market, parent: Instance, jobs: { () -> () })
	fillJobs(m, parent, "Showroom", jobs, electronicsSlots(m), categoryEntries({ "Electronics" }))
	fillJobs(m, parent, "Showroom", jobs, toySlots(m), categoryEntries({ "Toys" }))
	table.insert(jobs, function()
		actor(m, parent, "Showroom", "kid", 71, m.F * CFrame.new(25.6, INLAY_TOP, 30) * FACE_PX, "idle", { Prop = "none" })
	end)
end

-- Entrées choisies (dans l'ordre), puis la catégorie en secours
local function curated(ids: { string }, fallback: { ShopUI.Entry }): { ShopUI.Entry }
	local list, seen = {}, {}
	for _, id in ipairs(ids) do
		local e = ShopUI.Entry("Item", id)
		if e then
			table.insert(list, e)
			seen[id] = true
		end
	end
	for _, e in ipairs(fallback) do
		if not seen[e.Id] then
			table.insert(list, e)
		end
	end
	return list
end

local function furnitureZone(m: Market, parent: Instance, jobs: { () -> () })
	for i, v in ipairs(VIGNETTES) do
		local floor, wall = furnitureSlots(m, i)
		local cats = v[5] :: { string }
		local big = curated(v[6] :: { string }, categoryEntries(cats, function(def)
			return not isWall(def) and (tonumber(def.Size) or 80) >= 120
		end))
		local small = curated(v[7] :: { string }, categoryEntries(cats, function(def)
			return not isWall(def) and (tonumber(def.Size) or 80) < 120 and (tonumber(def.Size) or 80) >= 60
		end))
		fillJobs(m, parent, "Furniture", jobs, { floor[1], floor[2] }, big, true)
		fillJobs(m, parent, "Furniture", jobs, { floor[3], floor[4] }, small, true)
		local walls = categoryEntries(i == 2 and { "Luxury", "Decor", "Lights" } or { "Decor", "Lights" }, isWall)
		fillJobs(m, parent, "Furniture", jobs, wall, i == 2 and walls or spread(walls, #walls), i == 2)
	end
	table.insert(jobs, function()
		actor(m, parent, "Furniture", "salesperson", 91, m.F * CFrame.new(13.5, FLOOR_TOP, 50.6), "talk")
	end)
end

local function gardenZone(m: Market, parent: Instance, jobs: { () -> () })
	fillJobs(m, parent, "Garden", jobs, gardenSlots(m), categoryEntries({ "Plants" }))
end

ZONE_SPECS = {
	{ "Groc1", GONDOLA_X[1], 32, groceryZone(1), { "Face1", "Face2" } },
	{ "Groc2", GONDOLA_X[2], 32, groceryZone(2), { "Face3", "Face4" } },
	{ "Groc3", GONDOLA_X[3], 32, groceryZone(3), { "Face5", "Face6" } },
	{ "Groc4", GONDOLA_X[4], 32, groceryZone(4), { "Face7", "Face8" } },
	{ "Home5", GONDOLA_X[5], 32, homeZone(5), { "Face9", "Face10" } },
	{ "Home6", GONDOLA_X[6], 32, homeZone(6), { "Face11", "Face12" } },
	{ "Home7", GONDOLA_X[7], 32, homeZone(7), { "Face13", "Face14" } },
	{ "Produce", -45, 32, produceZone, { "Produce" } },
	{ "Checkout", 27, 8, function(m: Market, parent: Instance, jobs: { () -> () })
		Checkout().Zone(m, parent, jobs)
	end, {} },
	{ "Entrance", 0, 5, entranceZone, {} },
	{ "Robux", -41, 7, robuxZone, {} },
	{ "Cafe", -21, 7, cafeZone, {} },
	{ "Showroom", 37, 32, showroomZone, {} },
	{ "BackLeft", -24, 58, backLeftZone, { "Back" } },
	{ "Furniture", 13, 58, furnitureZone, {} },
	{ "Garden", 42, 57, gardenZone, {} },
}

-- Clients qui poussent leur chariot (parcours fermés dans les allées)
local function shoppers(m: Market, parent: Instance, jobs: { () -> () })
	local routes = {
		{ { -20, 17.5 }, { -20, 45.5 }, { -12, 45.5 }, { -12, 17.5 } },
		{ { -36, 17.5 }, { 20.3, 17.5 }, { 20.3, 45.5 }, { -36, 45.5 } },
		{ { -44, 47 }, { 28, 47 }, { 28, 49.5 }, { -44, 49.5 } },
		{ { 35, 21 }, { 43.5, 21 }, { 43.5, 43 }, { 35, 43 } },
	}
	for i, route in ipairs(routes) do
		table.insert(jobs, function()
			shopper(m, parent, "full", 100 + i * 11, route, 2.4 + (i % 3) * 0.4)
		end)
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
	table.insert(jobs, function()
		priceTags(m, parent)
		aisleSigns(m, parent)
	end)
	for i = 1, #LANES do
		table.insert(jobs, function()
			Checkout().Lane(m, parent, i)
		end)
	end
	table.insert(jobs, function()
		Checkout().SelfCheckout(m, parent)
	end)
	table.insert(jobs, function()
		-- (v9.9) horloge de gare à deux faces au-dessus des caisses
		local H = m.Size.Y
		local at = m.F * CFrame.new(30.5, 10.4, 9.25)
		V99.addClock(m, parent, "full", at, 2.4, { Style = "Station", Numerals = "Arabic", Brand = "MegaDopa", MaxDistance = 160, Name = "StationClock" })
		box(parent, "ClockRod", at, -0.05, 0.05, 1.9, H - 10.4 - 0.4, 0.14, 0.24, DARKSTEEL, M.Metal)
	end)
	table.insert(jobs, function()
		entrance(m, parent)
	end)
	table.insert(jobs, function()
		robuxShell(m, parent)
	end)
	table.insert(jobs, function()
		cafeShell(m, parent)
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
		showroom(m, parent)
	end)
	table.insert(jobs, function()
		furnitureRooms(m, parent)
	end)
	table.insert(jobs, function()
		gardenDecor(m, parent)
	end)
	shoppers(m, parent, jobs)
	return jobs
end

----------------------------------------------------------------------
-- Construction par niveaux et par zones / destruction
----------------------------------------------------------------------

local function newBuilder(name: string): Builder
	return { Name = name, Folder = nil, Jobs = nil, Index = 1, Built = false }
end

local function startBuilder(b: Builder, parent: Instance, name: string, make: (Instance) -> { () -> () })
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	b.Folder = f
	b.Built = false
	b.Index = 1
	b.Jobs = make(f)
end

local function stopBuilder(b: Builder)
	if b.Folder then
		b.Folder:Destroy()
	end
	b.Folder = nil
	b.Jobs = nil
	b.Index = 1
	b.Built = false
end

-- Retire des listes tout ce qui appartient à `owner` (zone, "full", "outside")
local function purge(m: Market, owner: string)
	local function keep<T>(list: { T }, drop: ((T) -> ())?): { T }
		local out = {}
		for _, x in ipairs(list) do
			if (x :: any).Owner == owner then
				if drop then
					drop(x)
				end
			else
				table.insert(out, x)
			end
		end
		return out
	end
	m.Displays = keep(m.Displays)
	m.Actors = keep(m.Actors)
	m.Belts = keep(m.Belts)
	for _, belt in ipairs(m.Belts) do
		if belt.Cashier and belt.Cashier.Owner == owner then
			belt.Cashier = nil
		end
		belt.Customers = keep(belt.Customers)
	end
	local mm: any = m
	mm.Kiosks = keep(mm.Kiosks)
	mm.Clocks = keep(mm.Clocks)
	mm.Dates = keep(mm.Dates)
	for _, k in ipairs(mm.Kiosks) do
		if k.Customer and k.Customer.Owner == owner then
			k.Customer = nil
		end
	end
	m.Spinners = keep(m.Spinners)
	m.Robux = keep(m.Robux)
	m.Boards = keep(m.Boards, function(b: Board)
		b.Gui:Destroy()
	end)
end

local function recount()
	local parts, labels = 0, 0
	if folder then
		for _, x in ipairs(folder:GetDescendants()) do
			if x:IsA("BasePart") then
				parts += 1
			elseif x:IsA("SurfaceGui") and x.Name == "Print" then
				labels += 1
			end
		end
	end
	partCount, labelCount = parts, labels
	stats.Parts, stats.Labels = parts, labels
end

local function setBands(m: Market, zone: Zone, visible: boolean)
	for _, key in ipairs(zone.Hide) do
		for _, p in ipairs(m.Bands[key :: any] or {}) do
			if p.Parent then
				p.Transparency = visible and 0 or 1
			end
		end
	end
end

local function destroyZone(m: Market, zone: Zone)
	if not zone.B.Folder then
		return
	end
	purge(m, zone.Name)
	stopBuilder(zone.B)
	setBands(m, zone, true)
	stats.Destroyed += 1
end

local function destroyFull(m: Market)
	for _, zone in ipairs(m.Zones) do
		destroyZone(m, zone)
	end
	if m.Full.Folder then
		purge(m, "full")
		stopBuilder(m.Full)
		table.clear(m.Lights)
		table.clear(m.Checkouts)
		table.clear(m.Bands)
		table.clear(m.TVs)
		table.clear(cafeSeats)
		m.LightsOn = false
		local mm: any = m
		if mm.Night and mm.NightParent and mm.NightParent.Parent then
			mm.Night.Parent = mm.NightParent
		end
		stats.Destroyed += 1
		recount()
	end
end

local function destroyOutside(m: Market)
	if m.Outside.Folder then
		purge(m, "outside")
		local mm: any = m
		if mm.Night then
			mm.Night:Destroy()
		end
		mm.Night, mm.NightParent = nil, nil
		stopBuilder(m.Outside)
		stats.Destroyed += 1
		recount()
	end
end

local function updateLevel(m: Market)
	m.Level = (m.Full.Built and 2) or (m.Outside.Built and 1) or 0
	local tiers = (m :: any).Tiers
	tiers[1] = m.Outside.Folder
	tiers[2] = m.Full.Folder
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

-- Distance (à plat) au bâtiment (avec le parking si `withLot`) ; 0 dedans
local function boxDistance(m: Market, p: Vector3, withLot: boolean): number
	local rel = m.MCF:PointToObjectSpace(p)
	local hw = m.Size.X / 2 + 1
	local z0, z1 = withLot and -52 or 0, m.Size.Z + 2
	local dx = math.max(math.abs(rel.X) - hw, 0)
	local dz = rel.Z < z0 and z0 - rel.Z or (rel.Z > z1 and rel.Z - z1 or 0)
	return math.sqrt(dx * dx + dz * dz)
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

local function zoneCenter(m: Market, zone: Zone): Vector3
	return (m.F * CFrame.new(zone.X, 0, zone.Z)).Position
end

local function decide(m: Market, position: Vector3)
	local dOut = boxDistance(m, position, true)
	local dIn = boxDistance(m, position, false)
	local target = 0
	if dIn <= FULL_RANGE or (m.Full.Folder ~= nil and dIn <= FULL_DROP) then
		target = 2
	elseif dOut <= OUT_RANGE or (m.Outside.Folder ~= nil and dOut <= OUT_DROP) then
		target = 1
	end
	if target < 2 and m.Full.Folder then
		destroyFull(m)
	end
	if target < 1 and m.Outside.Folder then
		destroyOutside(m)
	end
	local root = folder :: Folder
	if target >= 1 and not m.Outside.Folder then
		startBuilder(m.Outside, root, "Market_Outside", function(f)
			return outsideJobs(m, f)
		end)
	end
	if target >= 2 and m.Outside.Built and not m.Full.Folder then
		startBuilder(m.Full, root, "Market_Full", function(f)
			return fullJobs(m, f)
		end)
	end
	-- détail par zone : dedans (ou sur le seuil), près de la zone
	local here = inside(m, position) or dIn <= 3
	if m.Full.Built and m.Full.Folder then
		for _, zone in ipairs(m.Zones) do
			local d = flatDistance(position, zoneCenter(m, zone))
			local want = here and (d <= ZONE_RANGE or (zone.B.Folder ~= nil and d <= ZONE_DROP))
			if want and not zone.B.Folder then
				startBuilder(zone.B, m.Full.Folder :: Folder, "Zone_" .. zone.Name, function(f)
					local jobs = {}
					zone.Build(m, f, jobs)
					return jobs
				end)
			elseif not want and zone.B.Folder then
				destroyZone(m, zone)
			end
		end
		-- zones les plus proches construites d'abord
		table.sort(m.Zones, function(a, b)
			return flatDistance(position, zoneCenter(m, a)) < flatDistance(position, zoneCenter(m, b))
		end)
	end
	-- (v9.9) vraies lumières allumées dès qu'on s'approche (≤ 20 studs du
	-- bâtiment), pas seulement une fois dedans : le magasin est éclairé avant d'entrer
	local on = m.Full.Folder ~= nil and (inside(m, position) or dIn <= 20)
	if on ~= m.LightsOn then
		m.LightsOn = on
		for _, light in ipairs(m.Lights) do
			light.Enabled = on
		end
	end
	updateLevel(m)
end

local function runJobs(m: Market): boolean
	local t0 = os.clock()
	local order: { Builder } = { m.Outside, m.Full }
	for _, zone in ipairs(m.Zones) do
		table.insert(order, zone.B)
	end
	local pending = false
	for _, b in ipairs(order) do
		local jobs = b.Jobs
		if jobs then
			pending = true
			repeat
				local job = jobs[b.Index]
				if job then
					local ok, err = pcall(job)
					if not ok then
						warn("[MarketInterior] " .. b.Name .. " : " .. tostring(err))
					end
				end
				b.Index += 1
			until b.Index > #jobs or os.clock() - t0 > STEP_BUDGET
			stats.Parts = partCount
			if b.Index > #jobs then
				b.Jobs = nil
				b.Built = true
				stats.Built += 1
				dirty = true
				boardsDirty = true
				if b == m.Full then
					for _, light in ipairs(m.Lights) do
						light.Enabled = m.LightsOn
					end
					-- (v9.9) l'intérieur complet a ses vraies lumières : la « lueur
					-- vue de dehors » (sols, murs, silhouettes) se retire
					local night = (m :: any).Night
					if night then
						night.Parent = nil
					end
				else
					for _, zone in ipairs(m.Zones) do
						if zone.B == b then
							setBands(m, zone, false)
							stats.ZonesBuilt += 1
						end
					end
				end
				updateLevel(m)
			end
			if os.clock() - t0 > STEP_BUDGET then
				return true
			end
		end
	end
	return pending
end

-- Point et direction (lissée aux virages) sur un parcours fermé
local function pathAt(path: { Vector3 }, s: number): (Vector3, Vector3)
	local n = #path
	for i = 1, n do
		local a, b = path[i], path[i % n + 1]
		local seg = (b - a).Magnitude
		if s <= seg or i == n then
			local dir = seg > 0 and (b - a) / seg or Vector3.new(0, 0, -1)
			local p = a + dir * math.min(s, seg)
			local turn = 1.2
			if seg - s < turn then
				local c = path[(i + 1) % n + 1]
				local nd = (c - b).Magnitude > 0 and (c - b).Unit or dir
				dir = dir:Lerp(nd, (turn - (seg - s)) / (turn * 2))
			elseif s < turn then
				local z = path[(i - 2) % n + 1]
				local pd = (a - z).Magnitude > 0 and (a - z).Unit or dir
				dir = dir:Lerp(pd, (turn - s) / (turn * 2))
			end
			if dir.Magnitude < 1e-3 then
				dir = Vector3.new(0, 0, -1)
			end
			return p, dir.Unit
		end
		s -= seg
	end
	return path[1], Vector3.new(0, 0, -1)
end

-- Animations (personnages, tapis, scanners, emblèmes, télés)
local function animate(m: Market, position: Vector3, now: number)
	if boxDistance(m, position, false) > ANIM_RANGE then
		return
	end
	local N = NPC()
	local count = 0
	for _, a in ipairs(m.Actors) do
		local path = a.Path
		if a.Custom then
			-- (caisses : animés par animateLane / animateKiosk)
			continue
		elseif path and a.Length and a.Speed then
			local s = ((now + a.Offset) * a.Speed) % a.Length
			local p, dir = pathAt(path, s)
			if (p - position).Magnitude <= 60 then
				local cf = CFrame.lookAt(p, p + Vector3.new(dir.X, 0, dir.Z))
				-- (racine du personnage placée directement, puis la pose : exact,
				-- jamais de PivotTo répété qui accumulerait des erreurs)
				local root = a.Model.PrimaryPart
				if root then
					root.CFrame = cf
				else
					a.Model:PivotTo(cf)
				end
				local cartParts, offsets = a.CartParts, a.CartOffsets
				if cartParts and offsets then
					local ccf = cf * CFrame.new(0, 0, -2.3)
					local frames = table.create(#cartParts)
					for i, o in ipairs(offsets) do
						frames[i] = ccf * o
					end
					workspace:BulkMoveTo(cartParts, frames, Enum.BulkMoveMode.FireCFrameChanged)
				end
				a.Pos = p
				if N then
					pcall(N.Animate, a.Model, a.Anim, now + a.Offset)
				end
				count += 1
			end
		elseif (a.Pos - position).Magnitude <= 60 and N then
			pcall(N.Animate, a.Model, a.Anim, now + a.Offset)
			count += 1
		end
	end
	stats.Animated = count
	-- caisses (v9.9) : tapis, articles, scanner, carrousel, écrans, file de clients
	for _, belt in ipairs(m.Belts) do
		if (belt.Pos - position).Magnitude <= 55 then
			Checkout().AnimateLane(belt, now)
		end
	end
	for _, k in ipairs((m :: any).Kiosks) do
		if (k.Pos - position).Magnitude <= 45 then
			Checkout().AnimateKiosk(k, now)
		end
	end
	for _, s in ipairs(m.Spinners) do
		if (s.Pos - position).Magnitude <= 60 then
			s.Part.CFrame = s.Base * CFrame.new(0, math.sin(now * 1.6 + s.Offset) * 0.15, 0) * CFrame.Angles(0, now * 1.2 + s.Offset, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		end
	end
	for i, g in ipairs(m.TVs) do
		g.Offset = Vector2.new(math.sin(now * 0.45 + i) * 0.35, 0)
	end
end

-- Écrans de classement (v9.9) : animations à 30 i/s de près (≤ 160 studs),
-- 2 i/s plus loin ; contenu relu toutes les 2 s ou au changement de page
local function stepBoards(m: Market, now: number, position: Vector3?)
	for _, board in ipairs(m.Boards) do
		if board.Gui.Parent then
			local d = position and (board.Pos - position).Magnitude or 0
			local b: any = board
			if d <= 160 or now - (b.LastStep or 0) >= 0.5 then
				b.LastStep = now
				local scope = boardScope(board, now)
				if boardsDirty or board.LastScope ~= scope or now - board.LastRefresh > 2 then
					board.LastScope = scope
					board.LastRefresh = now
					pcall(refreshBoard, board, now)
				end
				BoardKit.SetProgress(board.Kit, (now % PAGE_TIME) / PAGE_TIME)
				BoardKit.Step(board.Kit, now)
			end
		end
	end
	boardsDirty = false
end

local function refreshAll(m: Market)
	for _, d in ipairs(m.Displays) do
		if d.Tag then
			refreshDisplay(d)
		end
	end
	for _, r in ipairs(m.Robux) do
		refreshRobux(r)
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
	local now = os.clock()
	animClock += dt
	if animClock >= ANIM_EVERY then
		animClock = 0
		local position = localPosition()
		if position and m.Level >= 2 then
			animate(m, position, now)
		end
	end
	boardClock += dt
	if boardClock >= 1 / 30 then
		boardClock = 0
		local position = localPosition()
		stepBoards(m, now, position)
		-- (v9.9) horloges : 30 i/s de près, 4 i/s plus loin ; date chaque minute
		V99.Timers.Clock += 1 / 30
		for _, c in ipairs((m :: any).Clocks) do
			local d = position and (c.Clock.Pos - position).Magnitude or 0
			if d <= 120 or V99.Timers.Clock >= 0.25 then
				ClockKit.Update(c.Clock)
			end
		end
		if V99.Timers.Clock >= 0.25 then
			V99.Timers.Clock = 0
		end
		V99.Timers.Date += 1 / 30
		if V99.Timers.Date >= 30 then
			V99.Timers.Date = 0
			for _, dte in ipairs((m :: any).Dates) do
				pcall(dte.Refresh)
			end
		end
	end
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
		Level = 0,
		Outside = newBuilder("Outside"),
		Full = newBuilder("Full"),
		Zones = {},
		Displays = {},
		Lights = {},
		LightsOn = false,
		Doors = {},
		Checkouts = {},
		Actors = {},
		Belts = {},
		Spinners = {},
		Kiosks = {},
		Clocks = {},
		Dates = {},
		Robux = {},
		Boards = {},
		TVs = {},
		Bands = {},
	}
	;(m :: any).Tiers = {}
	for _, spec in ipairs(ZONE_SPECS) do
		table.insert(m.Zones, { Name = spec[1], X = spec[2], Z = spec[3], Build = spec[4], B = newBuilder(spec[1]), Hide = spec[5] })
	end
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
	toastFn = options and options.Toast or nil
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
	partCount, labelCount = 0, 0
	market = discover()
	clock = STEP_EVERY
	boardsDirty = true
	table.insert(conns, RunService.Heartbeat:Connect(heartbeat))
	table.insert(conns, ClientState.Changed:Connect(function()
		dirty = true
	end))
	table.insert(conns, ClientState.LeaderboardChanged:Connect(function()
		boardsDirty = true
	end))
	table.insert(conns, ShopUI.Bought:Connect(function()
		dirty = true
	end))
	table.insert(conns, MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, _passId: number, purchased: boolean)
		if who == Players.LocalPlayer and purchased then
			-- (le serveur confirme le pass : l'invite passera à « Déjà à toi »)
			toast("💎 " .. Locale.T("Thank you! Activating…"), rgb(150, 110, 220))
			dirty = true
		end
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
		destroyFull(m)
		destroyOutside(m)
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
	toastFn = nil
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
			for _ = 1, 20000 do
				if not m or not runJobs(m) then
					break
				end
			end
		end,
		-- (rendus) construit toutes les zones, où que soit l'avatar
		BuildZones = function()
			local m = market
			if not m or not m.Full.Built then
				return
			end
			for _, zone in ipairs(m.Zones) do
				if not zone.B.Folder then
					startBuilder(zone.B, m.Full.Folder :: Folder, "Zone_" .. zone.Name, function(f)
						local jobs = {}
						zone.Build(m, f, jobs)
						return jobs
					end)
				end
			end
			for _ = 1, 20000 do
				if not runJobs(m) then
					break
				end
			end
		end,
		Animate = function(position: Vector3, now: number)
			if market then
				animate(market, position, now)
				stepBoards(market, now, position)
			end
		end,
		Buy = function(index: number)
			local m = market
			local d = m and m.Displays[index]
			if d then
				buyDisplay(d)
			end
		end,
		PromptRobux = function(index: number)
			local m = market
			local r = m and m.Robux[index]
			if r then
				lastPrompt = 0
				robuxPrompt(r.Offer)
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
		BoardEntries = boardEntries,
		Parts = function(): number
			recount()
			return partCount
		end,
	}
end

return MarketInterior
