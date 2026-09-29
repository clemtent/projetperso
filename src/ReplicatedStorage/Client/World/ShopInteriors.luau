--[[
	ShopInteriors (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ShopInteriors

	🛍️ Dopamine Town (v9.6, SHOPS96) : l'INTÉRIEUR des boutiques où l'on
	entre, construit côté client (les modèles 3D des objets n'existent que
	côté client : House3DRecipes.BuildItem ; voitures : CarModels.Build).
	Le serveur a posé les coques (TownShops) dans DopamineTown.Shops, avec
	les attributs ShopId, InteriorCF, InteriorSize, DoorCF…
	  - FLUX à deux niveaux autour de l'avatar :
	      1. "Vitrine" (≤ 150 studs) : habillage (sol, murs, plafond,
	         lambris), estrades des vitrines et leurs 2 objets (vus depuis la
	         place) ; à la concession, les 8 voitures sur leurs plateaux ;
	      2. "Complet" (≤ 60 studs, gardé jusqu'à 100) : étagères, estrades,
	         comptoir + caisse + vendeur·se, enseigne, suspensions (2 VRAIES
	         lumières douces, allumées seulement quand on est dedans), déco
	         du métier, TOUS les objets exposés avec leur étiquette de prix
	         (BillboardGui, visible à ≤ 16 studs : icône, nom, prix, verrou,
	         exemplaires possédés) et une invite "Acheter — 🧠 prix" ; au
	         comptoir, l'invite "🛍️ Voir tout" ouvre le catalogue (ShopUI).
	    3 boutiques complètes au plus (les plus proches) ; construction
	    étalée : UNE boutique à la fois, quelques pièces par image (budget
	    de temps), jamais de création / destruction par image ensuite.
	  - portes vitrées coulissantes : s'ouvrent quand un avatar approche ;
	  - achat : ShopUI.Purchase (serveur House "buyItem" / Car "buy") ;
	    réussi -> petite pluie d'étincelles sur l'objet, étiquette à jour.
	Choix des objets exposés : chaque boutique a des emplacements (étagères,
	estrades, murs) ; s'il y a plus d'objets que de places, on en prend un
	échantillon régulier du moins cher au plus cher (le catalogue du
	comptoir montre TOUT). Taille réelle (WorldLayout.PX) réduite si
	besoin pour tenir dans l'emplacement.

	API (TownClient, via optionalModule) :
	  ShopInteriors.Start({ Toast = fn(text, color?) }?)   à l'entrée en ville
	  ShopInteriors.Step(position: Vector3)                 flux (4 fois / s)
	  ShopInteriors.Stop()                                  à la sortie
	  ShopInteriors.Debug() -> table                        (tests / rendus)
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

local ShopInteriors = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = rgb(92, 58, 96)

local FOLDER_NAME = "TownShopInteriors"
local FRONT_RANGE, FRONT_DROP = 150, 190 -- vitrine
local FULL_RANGE, FULL_DROP = 60, 100 -- intérieur complet
local MAX_FULL = 3
local STEP_BUDGET = 0.004 -- (s) de construction par image
local STEP_EVERY = 0.25
local DOOR_RANGE = 10
local TAG_DISTANCE = 16
local PROMPT_DISTANCE = 5.5
local PX = WorldLayout.PX
local GAP = 0.05 -- (studs) entre deux faces parallèles : jamais de faces confondues

----------------------------------------------------------------------
-- Thèmes (couleurs, matières, disposition des murs de côté)
----------------------------------------------------------------------

type Theme = {
	Floor: Color3,
	FloorMat: Enum.Material,
	Wall: Color3,
	Wainscot: Color3,
	Ceiling: Color3,
	Shelf: Color3,
	ShelfMat: Enum.Material,
	Back: Color3,
	Podium: Color3,
	Accent: Color3,
	Lamp: Color3,
	Sides: string, -- "Shelves" | "Platforms"
	Keeper: Color3,
}

local THEMES: { [string]: Theme } = {
	Pets = { Floor = rgb(226, 196, 160), FloorMat = M.WoodPlanks, Wall = rgb(255, 246, 232), Wainscot = rgb(150, 212, 190), Ceiling = rgb(255, 252, 246),
		Shelf = rgb(222, 184, 140), ShelfMat = M.Wood, Back = rgb(196, 236, 220), Podium = rgb(255, 222, 200), Accent = rgb(86, 176, 150), Lamp = rgb(255, 238, 204),
		Sides = "Shelves", Keeper = rgb(96, 186, 156) },
	Toys = { Floor = rgb(255, 232, 196), FloorMat = M.SmoothPlastic, Wall = rgb(255, 244, 250), Wainscot = rgb(255, 176, 196), Ceiling = rgb(255, 252, 255),
		Shelf = rgb(255, 255, 255), ShelfMat = M.SmoothPlastic, Back = rgb(200, 226, 255), Podium = rgb(255, 214, 120), Accent = rgb(236, 104, 140),
		Lamp = rgb(255, 240, 214), Sides = "Shelves", Keeper = rgb(255, 150, 90) },
	Kitchen = { Floor = rgb(250, 246, 240), FloorMat = M.Marble, Wall = rgb(255, 242, 240), Wainscot = rgb(236, 130, 146), Ceiling = rgb(255, 252, 250),
		Shelf = rgb(246, 240, 234), ShelfMat = M.SmoothPlastic, Back = rgb(214, 242, 230), Podium = rgb(214, 170, 124), Accent = rgb(214, 90, 110),
		Lamp = rgb(255, 238, 210), Sides = "Shelves", Keeper = rgb(236, 112, 132) },
	Furniture = { Floor = rgb(198, 152, 110), FloorMat = M.WoodPlanks, Wall = rgb(246, 238, 226), Wainscot = rgb(176, 150, 124), Ceiling = rgb(255, 252, 246),
		Shelf = rgb(160, 116, 84), ShelfMat = M.Wood, Back = rgb(236, 222, 204), Podium = rgb(236, 226, 214), Accent = rgb(160, 116, 84), Lamp = rgb(255, 232, 196),
		Sides = "Platforms", Keeper = rgb(190, 146, 108) },
	Setup = { Floor = rgb(64, 60, 84), FloorMat = M.SmoothPlastic, Wall = rgb(96, 90, 128), Wainscot = rgb(58, 54, 80), Ceiling = rgb(70, 66, 92),
		Shelf = rgb(48, 46, 62), ShelfMat = M.Metal, Back = rgb(120, 110, 170), Podium = rgb(46, 44, 60), Accent = rgb(120, 214, 250), Lamp = rgb(214, 226, 255),
		Sides = "Platforms", Keeper = rgb(106, 90, 210) },
	Garden = { Floor = rgb(206, 140, 108), FloorMat = M.Slate, Wall = rgb(236, 248, 228), Wainscot = rgb(120, 180, 110), Ceiling = rgb(248, 255, 244),
		Shelf = rgb(186, 140, 96), ShelfMat = M.WoodPlanks, Back = rgb(206, 236, 196), Podium = rgb(170, 120, 86), Accent = rgb(84, 160, 96), Lamp = rgb(255, 246, 210),
		Sides = "Shelves", Keeper = rgb(126, 192, 112) },
	Cars = { Floor = rgb(240, 240, 246), FloorMat = M.Marble, Wall = rgb(246, 246, 250), Wainscot = rgb(70, 74, 92), Ceiling = rgb(250, 250, 252),
		Shelf = rgb(70, 74, 92), ShelfMat = M.Metal, Back = rgb(236, 72, 120), Podium = rgb(250, 250, 252), Accent = rgb(236, 72, 120), Lamp = rgb(246, 248, 255),
		Sides = "Shelves", Keeper = rgb(236, 72, 120) },
}

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
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
	return p
end

-- Boîte entre deux coins dans le repère F (x, y, z)
local function box(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return newPart(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, solid)
end

local function cylinder(parent: Instance, name: string, F: CFrame, x: number, y0: number, z: number, height: number, diameter: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = newPart(parent, name, Vector3.new(height, diameter, diameter), F * CFrame.new(x, y0 + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material, solid)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, F: CFrame, x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(parent, name, Vector3.new(diameter, diameter, diameter), F * CFrame.new(x, y, z), color, material)
	;(p :: Part).Shape = Enum.PartType.Ball
	return p
end

-- Panneau texte (SurfaceGui, face avant = -Z du panneau)
local function sign(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, text: string, textColor: Color3, pps: number): BasePart
	local board = newPart(parent, name, size, cf, color, M.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.3
	gui.Brightness = 1
	gui.MaxDistance = 90
	gui.Parent = board
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.9, 0.8)
	l.Position = UDim2.fromScale(0.05, 0.1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = textColor
	l.Parent = gui
	return board
end

----------------------------------------------------------------------
-- Modèles 3D (paresseux : l'intérieur marche sans eux)
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

local function optional(parent: Instance, name: string): any?
	local module = parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return ok and type(result) == "table" and result or nil
end

----------------------------------------------------------------------
-- État
----------------------------------------------------------------------

type Slot = {
	CF: CFrame, -- sol de l'emplacement, LookVector = vers le visiteur
	MaxW: number,
	MaxH: number,
	MaxD: number,
	Kind: string, -- "Window" | "Podium" | "Platform" | "Shelf" | "Wall" | "Car"
	Tag: CFrame, -- étiquette (face vers le visiteur)
	WallZ: number?, -- (étagère) distance du fond depuis le centre de l'emplacement
}

type Display = {
	Entry: ShopUI.Entry,
	Model: Model?,
	Tag: BasePart?,
	Billboard: BillboardGui?,
	Prompt: ProximityPrompt?,
	Labels: { [string]: TextLabel },
	Key: string,
	Live: any?,
	SlotKind: string?,
}

type Door = { Part: BasePart, Closed: CFrame, Open: CFrame, IsOpen: boolean }

type Shop = {
	Model: Model,
	Id: string,
	Kind: string,
	Theme: Theme,
	InteriorCF: CFrame,
	Size: Vector3,
	DoorCF: CFrame,
	F: CFrame, -- repère : sol, milieu de la face intérieure de la façade, +Z vers le fond
	Level: number, -- 0 rien, 1 vitrine, 2 complet
	Tiers: { [number]: Folder },
	Jobs: { () -> () }?,
	Building: number, -- niveau en construction (0 = rien)
	Plan: any?,
	Displays: { Display },
	Lights: { Light },
	LightsOn: boolean,
	Doors: { Door },
	Counter: Vector3?,
}

local started = false
local shops: { Shop } = {}
local folder: Folder? = nil
local conns: { any } = {}
local clock = 0
local dirty = false
local focus: Vector3? = nil
local stats = { Built = 0, Destroyed = 0, Items = 0, Purchases = 0 }

----------------------------------------------------------------------
-- Emplacements (repère F de la boutique)
----------------------------------------------------------------------

-- Face vers +X (mur gauche vu de la porte... côté x < 0), -X, ou la porte (-Z)
local FACE_DOOR = CFrame.new()
local FACE_PX = CFrame.Angles(0, -math.pi / 2, 0) -- LookVector = +X
local FACE_NX = CFrame.Angles(0, math.pi / 2, 0) -- LookVector = -X

type Plan = {
	Window: { Slot },
	Podium: { Slot },
	Platform: { Slot },
	Wall: { Slot },
	Shelf: { Slot },
	ShelfUnits: { { CF: CFrame, L: number, Dp: number, H: number, Levels: { number } } },
	PodiumSpots: { { X: number, Z: number } },
	Platforms: { { CF: CFrame, W: number, Dp: number } },
}

local SHELF_DEPTH = 2.3
local SHELF_H = 8.6
local SHELF_LEVELS = { 0.55, 3.25, 5.95 } -- dessus des planches
local SHELF_CLEAR = 2.35 -- hauteur libre au-dessus d'une planche

-- Étagère murale : `cf` = milieu de la FACE AVANT au sol, LookVector vers
-- le visiteur ; renvoie ses emplacements
local function shelfSlots(plan: Plan, cf: CFrame, length: number, perLevel: number)
	table.insert(plan.ShelfUnits, { CF = cf, L = length, Dp = SHELF_DEPTH, H = SHELF_H, Levels = SHELF_LEVELS })
	local inner = length - 0.5
	local w = inner / perLevel
	for _, y in ipairs(SHELF_LEVELS) do
		for i = 1, perLevel do
			local x = -inner / 2 + (i - 0.5) * w
			-- (repère de l'étagère : -Z = vers le visiteur ; fond à +SHELF_DEPTH)
			local centerZ = (SHELF_DEPTH - 0.25) / 2
			table.insert(plan.Shelf, {
				CF = cf * CFrame.new(x, y, centerZ),
				MaxW = w - 0.35,
				MaxH = SHELF_CLEAR - 0.15,
				MaxD = SHELF_DEPTH - 0.45,
				Kind = "Shelf",
				Tag = cf * CFrame.new(x, y - 0.2, -0.12),
				WallZ = SHELF_DEPTH - 0.25 - centerZ - GAP,
			})
		end
	end
end

local function makePlan(shop: Shop): Plan
	local W, D = shop.Size.X, shop.Size.Z
	local hw = W / 2
	local F = shop.F
	local plan: Plan = { Window = {}, Podium = {}, Platform = {}, Wall = {}, Shelf = {}, ShelfUnits = {}, PodiumSpots = {}, Platforms = {} }
	-- vitrines : estrades derrière les deux grandes vitres (vues de la place)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * 8.55
		table.insert(plan.Window, { CF = F * CFrame.new(x, 1.72, 2.1), MaxW = 7, MaxH = 7, MaxD = 3, Kind = "Window", Tag = F * CFrame.new(x, 1.5, 0.35) })
	end
	-- estrades au centre : 4 de part et d'autre de l'allée, ou 2 dans l'axe
	-- quand les murs de côté ont des estrades "salon"
	local spots = shop.Theme.Sides == "Platforms" and { { 0, 8.6 }, { 0, 14.4 } } or { { -6.2, 8.4 }, { 6.2, 8.4 }, { -6.2, 14.2 }, { 6.2, 14.2 } }
	for _, spot in ipairs(spots) do
		local x, z = spot[1], spot[2]
		table.insert(plan.PodiumSpots, { X = x, Z = z })
		table.insert(plan.Podium, { CF = F * CFrame.new(x, 0.7, z), MaxW = 4.6, MaxH = 7.2, MaxD = 4.6, Kind = "Podium",
			Tag = F * CFrame.new(x, 0.45, z - 2.56) })
	end
	-- fond : deux étagères de part et d'autre du comptoir (devant le lambris)
	local back = hw - 0.45
	for _, sx in ipairs({ -1, 1 }) do
		shelfSlots(plan, F * CFrame.new(sx * (back - 4.2), 0, D - 0.35 - SHELF_DEPTH) * FACE_DOOR, 8.4, 2)
	end
	-- murs de côté : étagères, ou estrades "salon" + objets muraux au-dessus
	local z0, z1 = 3.4, D - 3.2
	for _, sx in ipairs({ -1, 1 }) do
		local face = sx < 0 and FACE_PX or FACE_NX
		local wallX = sx * back -- (devant la cimaise)
		if shop.Theme.Sides == "Platforms" then
			local n = 3
			local len = (z1 - z0) / n
			for i = 1, n do
				local z = z0 + (i - 0.5) * len
				local depth = 3.8
				local cf = F * CFrame.new(wallX - sx * depth / 2, 0, z) * face
				table.insert(plan.Platforms, { CF = cf, W = len - 0.4, Dp = depth })
				table.insert(plan.Platform, { CF = cf * CFrame.new(0, 0.58, 0), MaxW = len - 0.8, MaxH = 5.4, MaxD = depth - 0.5, Kind = "Platform",
					Tag = cf * CFrame.new(0, 0.3, -depth / 2 - 0.08) })
				-- objet mural au-dessus (pivot contre le mur), étiquette sous lui
				local wallCF = F * CFrame.new(sx * (hw - 0.2), 6.1, z) * face
				table.insert(plan.Wall, { CF = wallCF, MaxW = len - 1.2, MaxH = 3.4, MaxD = 1.5, Kind = "Wall", Tag = wallCF * CFrame.new(0, -0.45, -0.1) })
			end
		else
			local cf = F * CFrame.new(wallX - sx * SHELF_DEPTH, 0, (z0 + z1) / 2) * face
			shelfSlots(plan, cf, z1 - z0, 4)
		end
	end
	return plan
end

-- Échantillon régulier de `k` éléments (du premier au dernier)
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

-- Qui va où : { { Slot, Entry } }
local function assign(shop: Shop, plan: Plan): { { Slot: Slot, Entry: ShopUI.Entry } }
	local big, wall, small = {}, {}, {}
	for _, entry in ipairs(ShopUI.ShopEntries(shop.Id)) do
		if entry.Kind == "Item" then
			local item = entry.Def
			if item.Placement == "Wall" then
				table.insert(wall, entry)
			elseif (tonumber(item.Size) or 80) >= 100 and not HouseCommon.CanGoOnFurniture(item) then
				table.insert(big, entry)
			else
				table.insert(small, entry)
			end
		end
	end
	local result = {}
	local used: { [ShopUI.Entry]: boolean } = {}
	local function place(slots: { Slot }, pool: { ShopUI.Entry })
		local free = {}
		for _, entry in ipairs(pool) do
			if not used[entry] then
				table.insert(free, entry)
			end
		end
		local chosen = spread(free, #slots)
		for i, entry in ipairs(chosen) do
			used[entry] = true
			table.insert(result, { Slot = slots[i], Entry = entry })
		end
	end
	-- vitrines : deux beaux gros objets (milieu et haut de gamme)
	if #big >= 2 then
		local a, b = big[math.max(1, math.floor(#big * 0.4 + 0.5))], big[math.max(1, math.floor(#big * 0.8 + 0.5))]
		if a ~= b then
			used[a], used[b] = true, true
			table.insert(result, { Slot = plan.Window[1], Entry = a })
			table.insert(result, { Slot = plan.Window[2], Entry = b })
		end
	end
	place(plan.Podium, big)
	place(plan.Platform, big)
	place(plan.Wall, wall)
	-- étagères : petits objets + objets muraux restants, puis gros objets en
	-- miniature s'il reste de la place ; rangés du moins cher au plus cher
	local shelfPool = {}
	for _, list in ipairs({ small, wall }) do
		for _, entry in ipairs(list) do
			if not used[entry] then
				table.insert(shelfPool, entry)
			end
		end
	end
	local rest = #plan.Shelf - #shelfPool
	if rest > 0 then
		local freeBig = {}
		for _, entry in ipairs(big) do
			if not used[entry] then
				table.insert(freeBig, entry)
			end
		end
		for _, entry in ipairs(spread(freeBig, rest)) do
			table.insert(shelfPool, entry)
		end
	end
	local picked = spread(shelfPool, #plan.Shelf)
	local price: { [ShopUI.Entry]: number } = {}
	for i, entry in ipairs(picked) do
		price[entry] = (tonumber(entry.Def.Cost) or 0) + i * 1e-6
	end
	table.sort(picked, function(a, b)
		return price[a] < price[b]
	end)
	-- (répartis sur TOUTES les étagères, pas entassés au début)
	local indices = {}
	for i = 1, #plan.Shelf do
		indices[i] = i
	end
	local slotIndex = spread(indices, #picked)
	for i, entry in ipairs(picked) do
		table.insert(result, { Slot = plan.Shelf[slotIndex[i]], Entry = entry })
	end
	return result
end

----------------------------------------------------------------------
-- Étiquettes + invites
----------------------------------------------------------------------

local function promptText(entry: ShopUI.Entry): string
	if ShopUI.LockText(entry) then
		return "🔒 " .. Locale.T("Locked")
	end
	if entry.Kind == "Car" and ShopUI.Owned(entry) > 0 then
		return ShopUI.IsSelected(entry) and Locale.T("✅ Selected") or Locale.T("🚗 Choose")
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
		elseif ShopUI.IsMaxed(entry) and entry.Kind ~= "Item" then
			labels.Price.Text = "✅ " .. Locale.T("Already yours!")
			labels.Price.TextColor3 = rgb(40, 160, 110)
		else
			labels.Price.Text = "🧠 " .. ShopUI.Format(ShopUI.Price(entry))
			labels.Price.TextColor3 = HouseCommon.Dopamine() >= ShopUI.Price(entry) and rgb(236, 72, 140) or rgb(210, 120, 80)
		end
	end
	if labels.Owned then
		labels.Owned.Visible = owned > 0 and entry.Kind == "Item"
		labels.Owned.Text = "x" .. tostring(owned)
	end
	if d.Prompt then
		d.Prompt.ActionText = promptText(entry)
	end
end

local function buyDisplay(d: Display)
	local entry = d.Entry
	if entry.Kind == "Car" and ShopUI.Owned(entry) > 0 and ShopUI.LockText(entry) == nil then
		ShopUI.SelectCar(entry)
		return
	end
	local ok = ShopUI.Purchase(entry)
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

-- Étiquette de prix + invite "Acheter" d'un objet exposé
local function addTag(shop: Shop, parent: Instance, d: Display, tagCF: CFrame, center: Vector3)
	local theme = shop.Theme
	-- (v9.6.1) ancre INVISIBLE : l'ancienne étiquette en pièce (et son bandeau)
	-- passait DEVANT le panneau de prix et cachait le texte
	local tag = newPart(parent, "PriceTag", Vector3.new(0.4, 0.4, 0.08), tagCF, WHITE, M.SmoothPlastic)
	tag.Transparency = 1
	tag.CastShadow = false
	d.Tag = tag
	-- l'invite est posée au centre de l'objet (l'interface Roblox s'y affiche)
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
	prompt.MaxActivationDistance = d.Entry.Kind == "Car" and 11 or PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = attachment
	prompt.Triggered:Connect(function()
		task.spawn(buyDisplay, d)
	end)
	d.Prompt = prompt
	-- étiquette flottante (taille en studs : elle rapetisse avec la distance)
	local bb = Instance.new("BillboardGui")
	bb.Name = "PriceLabel"
	bb.Size = d.Entry.Kind == "Car" and UDim2.fromScale(3.6, 1.45) or UDim2.fromScale(1.9, 0.86)
	bb.StudsOffsetWorldSpace = tagCF.LookVector * 0.25 + Vector3.new(0, d.Entry.Kind == "Car" and 1.6 or -0.1, 0)
	bb.MaxDistance = d.Entry.Kind == "Car" and 40 or TAG_DISTANCE
	bb.LightInfluence = 0
	bb.Brightness = 1
	-- (v9.6.1) toujours lisible (jamais coupé par une étagère ou un objet) ;
	-- seules les étiquettes les plus proches s'affichent (updateTags)
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
	stroke.Color = theme.Accent
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
	d.Labels.Price = text("Price", "", 0.52, 0.4, rgb(236, 72, 140), Enum.Font.FredokaOne)
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

----------------------------------------------------------------------
-- Objets exposés
----------------------------------------------------------------------

-- Construit le modèle 3D d'un objet à la bonne taille pour son emplacement
local function buildItem(entry: ShopUI.Entry, slot: Slot): Model?
	local R = Recipes()
	if not R then
		return nil
	end
	local item = entry.Def
	local size = math.max(20, tonumber(item.Size) or 80)
	local scale = math.min(PX, slot.MaxW / size, slot.MaxH / size)
	local opts = { Scale = scale, Collide = slot.Kind == "Podium" or slot.Kind == "Platform", Query = false, Shadows = slot.Kind ~= "Shelf" }
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
		-- (≤ 2 vraies lumières par boutique : celles des lampes exposées s'éteignent)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Light") then
				d:Destroy()
			end
		end
	end
	return model
end

local function placeDisplay(shop: Shop, parent: Instance, slot: Slot, entry: ShopUI.Entry, withTag: boolean): Display?
	local model = buildItem(entry, slot)
	local d: Display = { Entry = entry, Model = model, Labels = {}, Key = entry.Kind .. ":" .. entry.Id, SlotKind = slot.Kind }
	local height = 1.5
	local lift = 0.02
	if model and slot.Kind == "Shelf" and model:GetAttribute("Wall") ~= true then
		-- 🐾 coussin sous chaque animal, 🪴 soucoupe en terre cuite sous les plantes
		local fp = model:GetAttribute("Footprint")
		local width = typeof(fp) == "Vector3" and math.clamp(math.max(fp.X, fp.Z) + 0.3, 1.2, slot.MaxW) or 1.8
		if shop.Id == "Pets" then
			local cushion = newPart(parent, "Cushion", Vector3.new(0.3, width, width), slot.CF * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)), shop.Theme.Podium, M.Fabric)
			;(cushion :: Part).Shape = Enum.PartType.Cylinder
			lift = 0.32
		elseif shop.Id == "Garden" then
			local saucer = newPart(parent, "Saucer", Vector3.new(0.14, width * 0.8, width * 0.8), slot.CF * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(206, 124, 90), M.Slate)
			;(saucer :: Part).Shape = Enum.PartType.Cylinder
			lift = 0.16
		end
	end
	if model then
		local pivot = slot.CF * CFrame.new(0, lift, 0)
		if model:GetAttribute("Wall") == true and slot.WallZ then
			pivot = slot.CF * CFrame.new(0, 0.05, slot.WallZ)
		end
		model:PivotTo(pivot)
		model.Parent = parent
		local fp = model:GetAttribute("Footprint")
		height = typeof(fp) == "Vector3" and fp.Y or height
		stats.Items += 1
		-- 🖥️ écrans vivants du Setup Store (LiveProps, aperçu non interactif)
		if shop.Id == "Setup" then
			local live = optional(script.Parent, "LiveProps")
			if live and type(live.Attach) == "function" then
				local ok, handle = pcall(live.Attach, model, entry.Id, { Interactive = false, PauseDistance = 60, ScreenDistance = 45 })
				if ok then
					d.Live = handle
				end
			end
		end
	end
	if withTag then
		local center = (slot.CF * CFrame.new(0, math.max(0.6, height / 2), 0)).Position
		if slot.Kind == "Wall" then
			center = (slot.CF * CFrame.new(0, height / 2, -0.6)).Position
		end
		addTag(shop, parent, d, slot.Tag, center)
	end
	table.insert(shop.Displays, d)
	return d
end

----------------------------------------------------------------------
-- Habillage (niveau 1) et mobilier (niveau 2)
----------------------------------------------------------------------

-- Sol, murs, lambris, plafond (tout à GAP des murs du serveur)
local function lining(shop: Shop, parent: Instance)
	local t = shop.Theme
	local F = shop.F
	local W, H, D = shop.Size.X, shop.Size.Y, shop.Size.Z
	local hw = W / 2
	local inset = GAP
	box(parent, "FloorFinish", F, -hw + inset, hw - inset, 0.05, 0.12, inset, D - inset, t.Floor, t.FloorMat)
	local wx = hw - inset - 0.1
	local top = H - 0.15
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "WallLining", F, sx * wx, sx * (wx + 0.1), 0.15, top, 0.2, D - 0.2, t.Wall, M.SmoothPlastic)
		box(parent, "Wainscot", F, sx * (wx - GAP - 0.1), sx * (wx - GAP), 0.15, 3.1, 0.4, D - 0.4, t.Wainscot, M.WoodPlanks)
		box(parent, "ChairRail", F, sx * (wx - GAP - 0.22), sx * (wx - GAP - 0.05), 3.05, 3.3, 0.4, D - 0.4, WHITE, M.SmoothPlastic)
	end
	box(parent, "BackLining", F, -wx + 0.15, wx - 0.15, 0.15, top, D - inset - 0.1, D - inset, t.Wall, M.SmoothPlastic)
	box(parent, "BackWainscot", F, -wx + 0.35, wx - 0.35, 0.15, 3.1, D - inset - 0.2 - GAP, D - inset - 0.1 - GAP, t.Wainscot, M.WoodPlanks)
	box(parent, "CeilingFinish", F, -hw + 0.3, hw - 0.3, H - 0.1, H - GAP, 0.3, D - 0.3, t.Ceiling, M.SmoothPlastic)
	if shop.Kind == "Items" then
		-- façade (côté intérieur) : bandeau au-dessus de la porte et des vitrines
		box(parent, "FrontLining", F, -12.5, 12.5, 9.1, top, inset, inset + 0.1, t.Wall, M.SmoothPlastic)
	end
end

local function windowDisplays(shop: Shop, parent: Instance, plan: Plan)
	local t = shop.Theme
	local F = shop.F
	for _, slot in ipairs(plan.Window) do
		local p = F:ToObjectSpace(slot.CF).Position
		box(parent, "WindowStage", F, p.X - 3.8, p.X + 3.8, 0.1, 1.64, 0.45, 3.8, t.Podium, M.SmoothPlastic, true)
		box(parent, "StageTrim", F, p.X - 3.85, p.X + 3.85, 1.68, 1.72, 0.4, 3.85, WHITE, M.SmoothPlastic)
	end
end

-- Étagère murale (planches, montants, fond coloré, socle)
local function shelfUnit(parent: Instance, unit: any, t: Theme)
	local cf, L, Dp, H = unit.CF, unit.L, unit.Dp, unit.H
	local hl = L / 2
	-- montants + dessus
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "ShelfSide", cf, sx * (hl - 0.2), sx * hl, 0.1, H, 0, Dp, t.Shelf, t.ShelfMat, true)
	end
	box(parent, "ShelfTop", cf, -hl, hl, H, H + 0.2, 0, Dp, t.Shelf, t.ShelfMat)
	box(parent, "ShelfBack", cf, -hl + 0.2 + GAP, hl - 0.2 - GAP, 0.1, H - GAP, Dp - 0.25, Dp - 0.1, t.Back, M.SmoothPlastic, true)
	for index, y in ipairs(unit.Levels) do
		local y0 = index == 1 and 0.1 or y - 0.2
		box(parent, index == 1 and "ShelfBase" or "ShelfBoard", cf, -hl + 0.2, hl - 0.2, y0, y, 0.05, Dp - 0.25 - GAP, t.Shelf, t.ShelfMat, index == 1)
	end
end

local function counter(shop: Shop, parent: Instance)
	local t = shop.Theme
	local F = shop.F
	local D = shop.Size.Z
	local z0, z1 = D - 4.6, D - 2.5
	box(parent, "Counter", F, -4.4, 4.4, 0.1, 3.3, z0, z1, t.Shelf, t.ShelfMat, true)
	box(parent, "CounterFront", F, -4.2, 4.2, 0.5, 3.0, z0 - GAP - 0.1, z0 - GAP, t.Accent, M.SmoothPlastic)
	box(parent, "CounterTop", F, -4.7, 4.7, 3.3, 3.55, z0 - 0.3, z1 + 0.2, WHITE, M.Marble)
	-- caisse enregistreuse
	box(parent, "Register", F, 1.4, 3.2, 3.55, 4.4, z0 + 0.4, z0 + 1.6, rgb(70, 66, 90), M.SmoothPlastic)
	local screen = box(parent, "RegisterScreen", F, 1.6, 3.0, 4.45, 5.35, z0 + 1.2, z0 + 1.35, rgb(40, 38, 56), M.SmoothPlastic)
	screen.CFrame *= CFrame.Angles(math.rad(-12), 0, 0)
	-- panneau "🛍️ Voir tout" (sur le comptoir)
	sign(parent, "SeeAll", Vector3.new(3.2, 1.3, 0.12), F * CFrame.new(-2, 4.25, z0 + 0.8) * CFrame.Angles(math.rad(-10), 0, 0), WHITE, Locale.T("🛍️ See everything"), t.Accent, 60)
	box(parent, "SignFoot", F, -2.6, -1.4, 3.55, 3.7, z0 + 0.6, z0 + 1.2, rgb(200, 196, 210), M.Metal)
	-- vendeur·se derrière le comptoir (petit personnage en blocs)
	local kz = D - 1.55
	local skin = rgb(255, 216, 186)
	box(parent, "KeeperLegs", F, -0.55, 0.55, 0.1, 2.3, kz - 0.35, kz + 0.35, rgb(80, 78, 110), M.SmoothPlastic)
	box(parent, "KeeperBody", F, -0.95, 0.95, 2.3, 4.4, kz - 0.45, kz + 0.45, t.Keeper, M.Fabric)
	box(parent, "KeeperApron", F, -0.7, 0.7, 2.4, 3.9, kz - 0.5 - GAP, kz - 0.45 - GAP, WHITE, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "KeeperArm", F, sx * 0.95 + (sx > 0 and 0.05 or -0.5), sx * 0.95 + (sx > 0 and 0.5 or -0.05), 2.5, 4.3, kz - 0.3, kz + 0.3, t.Keeper, M.Fabric)
	end
	ball(parent, "KeeperHead", F, 0, 5.15, kz, 1.55, skin, M.SmoothPlastic)
	ball(parent, "KeeperHair", F, 0, 5.55, kz + 0.2, 1.5, rgb(120, 80, 60), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		ball(parent, "KeeperEye", F, sx * 0.3, 5.2, kz - 0.7, 0.2, INK, M.SmoothPlastic)
	end
	box(parent, "KeeperSmile", F, -0.18, 0.18, 4.83, 4.9, kz - 0.74, kz - 0.7, rgb(220, 90, 110), M.SmoothPlastic)
	-- grande enseigne du fond
	local shopDef = ShopUI.SHOPS[shop.Id]
	sign(parent, "BackSign", Vector3.new(11, 2, 0.15), F * CFrame.new(0, 8.6, D - 0.2 - 2 * GAP - 0.2), WHITE, Locale.T(shopDef and shopDef.Name or shop.Id), t.Accent, 30)
	-- invite "🛍️ Voir tout" au comptoir
	local anchor = newPart(parent, "CatalogPoint", Vector3.new(1, 1, 1), F * CFrame.new(0, 3.9, z0 - 0.4), WHITE, M.SmoothPlastic)
	anchor.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CatalogPrompt"
	prompt.ActionText = Locale.T("🛍️ See everything")
	prompt.ObjectText = Locale.T(shopDef and shopDef.Name or shop.Id)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	local counterPos = anchor.Position
	shop.Counter = counterPos
	prompt.Triggered:Connect(function()
		ShopUI.OpenShop(shop.Id, { Anchor = counterPos })
	end)
end

-- Suspensions + les 2 vraies lumières (éteintes tant qu'on n'est pas dedans)
local function lamps(shop: Shop, parent: Instance, spots: { { number } })
	local t = shop.Theme
	local F = shop.F
	local H = shop.Size.Y
	for index, spot in ipairs(spots) do
		local x, z = spot[1], spot[2]
		box(parent, "LampCord", F, x - 0.05, x + 0.05, H - 1.6, H - 0.1, z - 0.05, z + 0.05, rgb(60, 60, 70), M.SmoothPlastic)
		local shade = cylinder(parent, "LampShade", F, x, H - 2.3, z, 0.8, 2.6, t.Accent, M.SmoothPlastic)
		shade.CastShadow = false
		local bulb = ball(parent, "LampBulb", F, x, H - 2.45, z, 0.9, t.Lamp, M.SmoothPlastic)
		if index <= 2 then
			local light = Instance.new("PointLight")
			light.Name = "ShopLight"
			light.Color = t.Lamp
			light.Brightness = 1
			light.Range = shop.Kind == "Cars" and 22 or 16
			light.Shadows = false
			light.Enabled = shop.LightsOn
			light.Parent = bulb
			table.insert(shop.Lights, light)
		end
	end
end

-- Déco propre à chaque métier
local function themeDecor(shop: Shop, parent: Instance)
	local t = shop.Theme
	local F = shop.F
	local D = shop.Size.Z
	local id = shop.Id
	-- tapis d'entrée
	box(parent, "EntryMat", F, -2.6, 2.6, 0.17, 0.22, 0.6, 3, t.Accent, M.Fabric)
	if id == "Pets" then
		-- empreintes de pattes au sol, bac à balles, coussin géant
		for i = 0, 5 do
			local x, z = (i % 2 == 0 and -0.9 or 0.9), 4 + i * 2.3
			cylinder(parent, "Paw", F, x, 0.17, z, 0.04, 0.8, rgb(170, 130, 96), M.SmoothPlastic)
		end
		cylinder(parent, "PetBed", F, 0, 0.1, D - 7, 0.5, 3.2, rgb(255, 196, 170), M.Fabric)
		ball(parent, "Yarn", F, 1.5, 0.55, D - 6.4, 0.9, rgb(236, 110, 150), M.Fabric)
		ball(parent, "Ball", F, -1.3, 0.5, D - 7.2, 0.8, rgb(120, 190, 255), M.SmoothPlastic)
	elseif id == "Toys" then
		-- dalles arc-en-ciel dans l'allée + gros nounours au coin
		local colors = { rgb(255, 150, 170), rgb(255, 214, 120), rgb(160, 226, 170), rgb(150, 200, 255), rgb(200, 170, 250) }
		for i = 1, 5 do
			box(parent, "RainbowTile", F, -2.6, 2.6, 0.17, 0.21, 3.2 + i * 2.6, 3.2 + i * 2.6 + 2.4, colors[i], M.SmoothPlastic)
		end
		local bx, bz = -3.6, D - 6.5
		ball(parent, "TeddyBody", F, bx, 1.4, bz, 2.6, rgb(206, 150, 104), M.Fabric)
		ball(parent, "TeddyHead", F, bx, 3.3, bz, 1.9, rgb(206, 150, 104), M.Fabric)
		for _, sx in ipairs({ -1, 1 }) do
			ball(parent, "TeddyEar", F, bx + sx * 0.75, 4.1, bz, 0.7, rgb(186, 130, 90), M.Fabric)
		end
		ball(parent, "TeddyMuzzle", F, bx, 3.1, bz - 0.85, 0.7, rgb(246, 214, 180), M.Fabric)
	elseif id == "Kitchen" then
		-- damier au sol + casseroles suspendues
		for i = 0, 5 do
			for j = 0, 1 do
				if (i + j) % 2 == 0 then
					box(parent, "FloorCheck", F, -2.6 + j * 2.6, j * 2.6, 0.17, 0.21, 4 + i * 2.4, 6.4 + i * 2.4, rgb(236, 130, 146), M.Marble)
				end
			end
		end
		local H = shop.Size.Y
		-- (au-dessus du comptoir, à droite : ne cache pas l'enseigne du fond)
		box(parent, "PotRail", F, 5.6, 10.4, H - 1.9, H - 1.75, D - 4.6, D - 4.45, rgb(200, 196, 210), M.Metal)
		for i = 0, 3 do
			cylinder(parent, "Pot", F, 6.3 + i * 1.2, H - 3.1, D - 4.52, 0.8, 1.05, rgb(214, 120, 90):Lerp(rgb(200, 196, 210), i % 2 * 0.6), M.Metal)
		end
	elseif id == "Furniture" then
		-- tapis sous les estrades du centre
		box(parent, "Runner", F, -2.2, 2.2, 0.17, 0.22, 3.4, D - 5.2, rgb(214, 170, 140), M.Fabric)
	elseif id == "Setup" then
		-- bandes "RGB" (couleurs douces, pas de néon) le long des murs
		local colors = { rgb(255, 120, 200), rgb(120, 200, 255), rgb(160, 255, 200) }
		for i, sx in ipairs({ -1, 1 }) do
			box(parent, "RGBStrip", F, sx * 13.55, sx * 13.6, 9.6, 9.8, 1, D - 1, colors[i], M.SmoothPlastic)
		end
		box(parent, "RGBStripBack", F, -13, 13, 9.6, 9.8, D - 0.45, D - 0.4, colors[3], M.SmoothPlastic)
	elseif id == "Garden" then
		-- paniers suspendus + arrosoir
		local H = shop.Size.Y
		for _, spot in ipairs({ { -9.6, 5.2 }, { 9.6, 5.2 }, { -9.6, 11.6 }, { 9.6, 11.6 } }) do
			local x, z = spot[1], spot[2]
			box(parent, "BasketCord", F, x - 0.04, x + 0.04, H - 2.2, H - 0.1, z - 0.04, z + 0.04, rgb(150, 120, 90), M.SmoothPlastic)
			cylinder(parent, "Basket", F, x, H - 3, z, 0.8, 1.6, rgb(190, 140, 90), M.WoodPlanks)
			ball(parent, "Trailing", F, x, H - 2.9, z, 1.9, rgb(96, 170, 92), M.Grass)
		end
		cylinder(parent, "WateringCan", F, 2.6, 0.15, D - 6.4, 1.1, 1, rgb(120, 180, 230), M.Metal)
	end
end

-- Estrades du centre (disques) et estrades "salon" le long des murs
local function stages(shop: Shop, parent: Instance, plan: Plan)
	local t = shop.Theme
	local F = shop.F
	for _, spot in ipairs(plan.PodiumSpots) do
		cylinder(parent, "Podium", F, spot.X, 0.1, spot.Z, 0.6, 5, t.Podium, M.SmoothPlastic, true)
		cylinder(parent, "PodiumRim", F, spot.X, 0.04, spot.Z, 0.29, 5.3, t.Accent, M.SmoothPlastic)
	end
	for _, pf in ipairs(plan.Platforms) do
		local hwid, hd = pf.W / 2, pf.Dp / 2
		box(parent, "Platform", pf.CF, -hwid, hwid, 0.1, 0.5, -hd, hd, t.Podium, M.WoodPlanks, true)
		box(parent, "PlatformRug", pf.CF, -hwid + 0.5, hwid - 0.5, 0.5, 0.5 + 0.06, -hd + 0.4, hd - 0.4, t.Accent:Lerp(WHITE, 0.55), M.Fabric)
	end
end

----------------------------------------------------------------------
-- Concession : voitures sur les plateaux, bureau de vente
----------------------------------------------------------------------

-- (v9.8, CARS98) le décor de la concession est dans DealerShowroom (grand
-- hall 70 x 50, plateau tournant, vendeur, pupitres…) : ici, on délègue
local dealerModule: any = nil
local function Dealer(): any
	if dealerModule == nil then
		dealerModule = optional(script.Parent, "DealerShowroom") or false
	end
	return dealerModule or nil
end

local function dealerCtx(): any
	return {
		AddTag = addTag,
		Entries = (ShopUI.ShopEntries("Cars")),
		Stats = stats,
		OpenCatalog = function(anchor: Vector3)
			ShopUI.OpenShop("Cars", { Anchor = anchor })
		end,
	}
end

local function carsFront(shop: Shop, parent: Instance): { () -> () }
	local dealer = Dealer()
	if dealer and type(dealer.FrontJobs) == "function" then
		local ok, jobs = pcall(dealer.FrontJobs, shop, parent, dealerCtx())
		if ok and type(jobs) == "table" then
			return jobs
		end
		warn("[ShopInteriors] concession : " .. tostring(jobs))
	end
	return {}
end

local function carsFull(shop: Shop, parent: Instance): { () -> () }
	local dealer = Dealer()
	if dealer and type(dealer.FullJobs) == "function" then
		local ok, jobs = pcall(dealer.FullJobs, shop, parent, dealerCtx())
		if ok and type(jobs) == "table" then
			return jobs
		end
		warn("[ShopInteriors] concession : " .. tostring(jobs))
	end
	return {}
end

----------------------------------------------------------------------
-- Construction par niveaux
----------------------------------------------------------------------

local function tierFolder(shop: Shop, level: number): Folder
	local existing = shop.Tiers[level]
	if existing and existing.Parent then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = shop.Id .. (level == 1 and "_Front" or "_Full")
	f.Parent = folder
	shop.Tiers[level] = f
	return f
end

local function jobsFor(shop: Shop, level: number): { () -> () }
	local parent = tierFolder(shop, level)
	local jobs: { () -> () } = {}
	if shop.Kind == "Cars" then
		if level == 1 then
			-- (v9.8) habillage propre à la concession (mur vitré côté porte de la ville)
			for _, job in ipairs(carsFront(shop, parent)) do
				table.insert(jobs, job)
			end
		else
			for _, job in ipairs(carsFull(shop, parent)) do
				table.insert(jobs, job)
			end
		end
		return jobs
	end
	local plan = shop.Plan
	if not plan then
		plan = makePlan(shop)
		shop.Plan = plan
	end
	local placements = assign(shop, plan)
	if level == 1 then
		table.insert(jobs, function()
			lining(shop, parent)
			windowDisplays(shop, parent, plan)
		end)
		for _, p in ipairs(placements) do
			if p.Slot.Kind == "Window" then
				table.insert(jobs, function()
					placeDisplay(shop, parent, p.Slot, p.Entry, false)
				end)
			end
		end
		return jobs
	end
	table.insert(jobs, function()
		for _, unit in ipairs(plan.ShelfUnits) do
			shelfUnit(parent, unit, shop.Theme)
		end
	end)
	table.insert(jobs, function()
		stages(shop, parent, plan)
		counter(shop, parent)
	end)
	table.insert(jobs, function()
		lamps(shop, parent, { { 0, 6.2 }, { 0, 13.6 } })
		themeDecor(shop, parent)
	end)
	-- étiquettes des objets des vitrines (déjà construits au niveau 1)
	table.insert(jobs, function()
		for _, d in ipairs(shop.Displays) do
			if not d.Tag then
				for _, p in ipairs(placements) do
					if p.Slot.Kind == "Window" and p.Entry == d.Entry then
						local height = 1.5
						local fp = d.Model and d.Model:GetAttribute("Footprint")
						if typeof(fp) == "Vector3" then
							height = fp.Y
						end
						addTag(shop, parent, d, p.Slot.Tag, (p.Slot.CF * CFrame.new(0, height / 2, 0)).Position)
					end
				end
			end
		end
	end)
	for _, p in ipairs(placements) do
		if p.Slot.Kind ~= "Window" then
			table.insert(jobs, function()
				placeDisplay(shop, parent, p.Slot, p.Entry, true)
			end)
		end
	end
	return jobs
end

local function detachDisplay(d: Display)
	if d.Live then
		local live = optional(script.Parent, "LiveProps")
		if live and type(live.Detach) == "function" then
			pcall(live.Detach, d.Live)
		end
		d.Live = nil
	end
end

-- Détruit les niveaux > `level`
local function downgrade(shop: Shop, level: number)
	for tier = 2, level + 1, -1 do
		local f = shop.Tiers[tier]
		if f then
			-- objets exposés de ce niveau
			local keep = {}
			for _, d in ipairs(shop.Displays) do
				local inTier = (d.Model and d.Model:IsDescendantOf(f)) or false
				if d.Tag and d.Tag:IsDescendantOf(f) then
					d.Tag = nil
					d.Prompt = nil
					d.Labels = {}
				end
				if inTier then
					detachDisplay(d)
				else
					table.insert(keep, d)
				end
			end
			shop.Displays = keep
			if tier == 2 then
				table.clear(shop.Lights)
				shop.LightsOn = false
				shop.Counter = nil
			end
			f:Destroy()
			shop.Tiers[tier] = nil
			stats.Destroyed += 1
		end
	end
	if shop.Building > level then
		shop.Jobs = nil
		shop.Building = 0
	end
	shop.Level = math.min(shop.Level, level)
end

----------------------------------------------------------------------
-- Portes coulissantes
----------------------------------------------------------------------

local function stepDoors(shop: Shop, positions: { Vector3 })
	if #shop.Doors == 0 then
		return
	end
	local door = shop.DoorCF.Position
	local near = false
	for _, p in ipairs(positions) do
		if (p - door).Magnitude < DOOR_RANGE then
			near = true
			break
		end
	end
	for _, d in ipairs(shop.Doors) do
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

-- Dans la boîte intérieure (un peu élargie) ?
local function inside(shop: Shop, p: Vector3): boolean
	local rel = shop.InteriorCF:PointToObjectSpace(p)
	local s = shop.Size
	return math.abs(rel.X) < s.X / 2 + 0.5 and math.abs(rel.Z) < s.Z / 2 + 0.5 and rel.Y > -2 and rel.Y < s.Y + 2
end

-- (v9.6.1) étiquettes de prix : seulement dans la boutique où l'on est, et
-- les MAX_TAGS plus proches (plus de panneaux empilés les uns sur les autres)
local MAX_TAGS = 5
local function updateTags(position: Vector3)
	local candidates: { { d: Display, dist: number } } = {}
	for _, shop in ipairs(shops) do
		local here = inside(shop, position)
		for _, d in ipairs(shop.Displays) do
			local bb = d.Billboard
			if bb and bb.Parent and d.Tag then
				local dist = (d.Tag.Position - position).Magnitude
				local isCar = d.Entry.Kind == "Car"
				if (here or isCar) and dist <= (isCar and 40 or TAG_DISTANCE) then
					table.insert(candidates, { d = d, dist = dist })
				else
					bb.Enabled = false
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)
	local shown = 0
	for _, c in ipairs(candidates) do
		local isCar = c.d.Entry.Kind == "Car"
		local show = isCar or shown < MAX_TAGS
		if show and not isCar then
			shown += 1
		end
		(c.d.Billboard :: BillboardGui).Enabled = show
	end
end

local function decide(position: Vector3)
	-- niveau voulu par boutique (hystérésis), 3 complètes au plus
	local wantFull = {}
	for _, shop in ipairs(shops) do
		local d = flatDistance(position, shop.InteriorCF.Position)
		local target = 0
		local s: any = shop
		if d <= FULL_RANGE or (shop.Level >= 2 and d <= FULL_DROP) then
			target = 2
		elseif d <= FRONT_RANGE or (shop.Level >= 1 and d <= FRONT_DROP) then
			target = 1
		end
		s.Target = target
		s.Distance = d
		if target == 2 then
			table.insert(wantFull, shop)
		end
	end
	table.sort(wantFull, function(a, b)
		return (a :: any).Distance < (b :: any).Distance
	end)
	for index = MAX_FULL + 1, #wantFull do
		local extra: any = wantFull[index]
		extra.Target = 1
	end
	for _, shop in ipairs(shops) do
		local target = (shop :: any).Target
		if shop.Level > target or shop.Building > target then
			downgrade(shop, target)
		end
		-- lumières : seulement quand on est dedans
		local on = inside(shop, position)
		if on ~= shop.LightsOn then
			shop.LightsOn = on
			for _, light in ipairs(shop.Lights) do
				light.Enabled = on
			end
		end
	end
	-- prochaine construction : la boutique la plus proche qui en a besoin
	local busy = false
	for _, shop in ipairs(shops) do
		if shop.Building > 0 then
			busy = true
		end
	end
	if not busy then
		local best: Shop? = nil
		for _, shop in ipairs(shops) do
			if (shop :: any).Target > shop.Level and (not best or (shop :: any).Distance < (best :: any).Distance) then
				best = shop
			end
		end
		if best then
			local level = best.Level + 1
			best.Building = level
			best.Jobs = jobsFor(best, level)
			;(best :: any).JobIndex = 1
		end
	end
end

local function runJobs()
	local started_ = os.clock()
	for _, shop in ipairs(shops) do
		local jobs = shop.Jobs
		if jobs then
			local index = (shop :: any).JobIndex or 1
			repeat
				local job = jobs[index]
				if job then
					local ok, err = pcall(job)
					if not ok then
						warn("[ShopInteriors] " .. shop.Id .. " : " .. tostring(err))
					end
				end
				index += 1
			until index > #jobs or os.clock() - started_ > STEP_BUDGET
			;(shop :: any).JobIndex = index
			if index > #jobs then
				shop.Jobs = nil
				shop.Level = shop.Building
				shop.Building = 0
				stats.Built += 1
				dirty = true
			end
			return -- (une boutique à la fois)
		end
	end
end

local function refreshAll()
	for _, shop in ipairs(shops) do
		for _, d in ipairs(shop.Displays) do
			if d.Tag then
				refreshDisplay(d)
			end
		end
	end
end

function ShopInteriors.Step(position: Vector3?)
	if typeof(position) == "Vector3" then
		focus = position
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
		pcall(updateTags, position)
	end
	local positions = characterPositions()
	for _, shop in ipairs(shops) do
		if shop.Level >= 1 or shop.Building >= 1 then
			stepDoors(shop, positions)
		end
	end
	if dirty then
		dirty = false
		refreshAll()
	end
end

----------------------------------------------------------------------
-- Démarrer / arrêter
----------------------------------------------------------------------

local function discover(): { Shop }
	local list = {}
	local town = workspace:FindFirstChild("DopamineTown")
	local container = town and town:FindFirstChild("Shops")
	if not container then
		return list
	end
	for _, model in ipairs(container:GetChildren()) do
		local id = model:GetAttribute("ShopId")
		local interiorCF = model:GetAttribute("InteriorCF")
		local size = model:GetAttribute("InteriorSize")
		local doorCF = model:GetAttribute("DoorCF")
		if model:IsA("Model") and type(id) == "string" and typeof(interiorCF) == "CFrame" and typeof(size) == "Vector3" and typeof(doorCF) == "CFrame" then
			local kind = model:GetAttribute("ShopKind") == "Cars" and "Cars" or "Items"
			local shop: Shop = {
				Model = model,
				Id = id,
				Kind = kind,
				Theme = THEMES[id] or THEMES.Pets,
				InteriorCF = interiorCF,
				Size = size,
				DoorCF = doorCF,
				F = interiorCF * CFrame.new(0, 0, -size.Z / 2),
				Level = 0,
				Tiers = {},
				Jobs = nil,
				Building = 0,
				Plan = nil,
				Displays = {},
				Lights = {},
				LightsOn = false,
				Doors = {},
				Counter = nil,
			}
			for _, child in ipairs(model:GetChildren()) do
				local slide = child:GetAttribute("SlideX")
				if child:IsA("BasePart") and child.Name == "DoorPanel" and type(slide) == "number" then
					local closed = child.CFrame
					table.insert(shop.Doors, { Part = child, Closed = closed, Open = closed * CFrame.new(slide, 0, 0), IsOpen = false })
				end
			end
			table.insert(list, shop)
		end
	end
	return list
end

function ShopInteriors.Start(options: { Toast: ((string, Color3?) -> ())? }?)
	if started then
		return
	end
	started = true
	ShopUI.SetToast(options and options.Toast or nil)
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	folder = f
	shops = discover()
	clock = STEP_EVERY
	table.insert(conns, RunService.Heartbeat:Connect(heartbeat))
	table.insert(conns, ClientState.Changed:Connect(function()
		dirty = true
	end))
	table.insert(conns, ShopUI.Bought:Connect(function()
		dirty = true
	end))
end

function ShopInteriors.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	ShopUI.Close()
	ShopUI.SetToast(nil)
	for _, shop in ipairs(shops) do
		downgrade(shop, 0)
		for _, d in ipairs(shop.Doors) do
			if d.Part.Parent then
				d.Part.CFrame = d.Closed
			end
		end
	end
	table.clear(shops)
	if folder then
		folder:Destroy()
		folder = nil
	end
	focus = nil
end

function ShopInteriors.Debug(): any
	return {
		Shops = shops,
		Stats = stats,
		Folder = folder,
		Refresh = refreshAll,
		Decide = function(position: Vector3)
			decide(position)
		end,
		RunAll = function()
			for _ = 1, 4000 do
				local pending = false
				for _, shop in ipairs(shops) do
					if shop.Jobs then
						pending = true
					end
				end
				if not pending then
					break
				end
				runJobs()
			end
		end,
		Buy = function(shop: any, index: number)
			local d = shop.Displays[index]
			if d then
				buyDisplay(d)
			end
		end,
	}
end

return ShopInteriors
