--[[
	HouseFacade (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseFacade

	🚶 Dopamine Town (v9.4) : l'EXTÉRIEUR 3D d'une maison, dessiné comme la
	maison 2D (Components/House/HouseExterior) : même style par taille,
	mêmes couleurs (façade / toit choisis), même motif de toit, même entrée.
	  - Cottage (studio) : chaumière crème à colombages, toit de tuiles roses,
	    cheminée qui fume, chat sur le toit, lucarne ronde, porche à pignon.
	  - Townhouse (appartement) : maison de ville menthe, chaînes d'angle,
	    pilastres, corniche à modillons, toit mansardé d'ardoises, lucarnes,
	    balcons en fer forgé, porte vitrée à pilastres.
	  - Loft : entrepôt de briques, fenêtres d'usine en acier, toit-terrasse
	    (acrotère, château d'eau, guirlande, parasol), enseigne "LOFT",
	    escalier de secours.
	  - Mansion : manoir, colonnes, balustrades, toit mansardé, fronton à
	    horloge, 2 tours rondes, grand escalier double, fontaine, grille.
	(v9.8 HOUSE98) portes doubles 6,5 x 9,5, plaque au nom toujours visible,
	côté jardin percé de vraies fenêtres + porte de derrière.
	(v9.9 HOUSE99) lueurs de nuit des fenêtres, fontaine du manoir refaite.

	(v10 HOUSE10) 🏡 10x plus réaliste + PERSONNALISABLE (Shared/HouseOptions,
	looks.Ext) :
	  - DEUX vraies fenêtres par pièce (proportions réelles ; loft : grande
	    baie d'usine, villa moderne : baie vitrée), cadres, petits bois,
	    appuis de pierre à larmier, linteaux / clés, volets (persiennes,
	    pleins, en Z), jardinières ;
	  - toits réalistes (HouseDetail) : 2 pans, croupe, mansarde, terrasse ;
	    rangs de tuiles / ardoises / bardeaux, joints debout, chaume, cuivre,
	    faîtage, arêtiers, rives, sous-faces, gouttières et descentes ;
	  - portes (panneaux, vitrée, rustique, moderne, sculptée) et couleur,
	    auvents / porche à colonnes / pergola, balcons (fer, verre, bois,
	    pierre), cheminées (briques, pierre, conduit) avec chapeau ;
	  - jardin de devant : clôtures (piquets, haie, lisses, fer forgé,
	    muret, lames) avec portillon FERMÉ (Micro = "Swing" : CONSTRUCT10),
	    allées (pas japonais, gravier, pavés, briques, caillebotis), boîte
	    aux lettres (drapeau animable), plaque du numéro, luminaires doux,
	    garage / abri à voiture (sauf manoir : son aile de garage) ;
	  - 2 NOUVELLES architectures, sur n'importe quelle taille : 🏔️ chalet
	    de montagne (bois, pierre, grand toit à 2 pans, pignon sur rue,
	    balcons de bois) et 🏙️ villa moderne (enduit blanc, bardage bois,
	    baies vitrées, toit plat en débord, garde-corps de verre) ;
	  - attribut BuildPhase sur chaque pièce (CONSTRUCT10).
	Fenêtres : trous = HouseFacade.WindowRects (le mur avant intérieur des
	pièces est percé pareil, HouseBuilder). Perrons : rampe invisible.

	API :
	  HouseFacade.Build(kit, size, looks) -> Built
	    looks = { Wall, Roof, Pattern, Garden, Rooms (par emplacement), Name,
	      Garage?, Ext? (options HouseOptions), Plot? }
	    Built = { Door, Hinge, Lock, Fills[slot], Chimneys, ChimneysExpected,
	      Style, Arch, Spec, Leaves, BackLeaves, BackFills[slot], Glows }
	  HouseFacade.Resolve(size, looks) -> Spec (options + look du style)
	  HouseFacade.WindowRects(size, column, floor, spec?) -> { { x0, x1, y0, y1 } }
	  HouseFacade.WindowRect / BackWindowRect(size, column, floor) -> { x0, x1, y0, y1 }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Config = require(ReplicatedStorage.Shared.Config)
local GarageLayout = require(ReplicatedStorage.Shared.GarageLayout) -- (v9.6, GARAGE96) 🏎️ aile du garage
local HouseOptions = require(ReplicatedStorage.Shared.HouseOptions) -- (v10 HOUSE10)
local HouseGarden = require(script.Parent.HouseGarden)
local HouseKit = require(script.Parent.HouseKit)
local HouseDetail = require(script.Parent.HouseDetail)

local HouseFacade = {}

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
-- (même palette que HouseCommon.Colors / HouseExterior)
local C = {
	Pink = Color3.fromRGB(255, 126, 182),
	PinkDeep = Color3.fromRGB(236, 72, 140),
	PinkSoft = Color3.fromRGB(255, 214, 232),
	Lilac = Color3.fromRGB(183, 148, 246),
	Mint = Color3.fromRGB(110, 214, 176),
	Cream = Color3.fromRGB(255, 247, 236),
	Peach = Color3.fromRGB(255, 190, 160),
	Sky = Color3.fromRGB(150, 205, 255),
	Butter = Color3.fromRGB(255, 226, 130),
	Heart = Color3.fromRGB(255, 79, 139),
	Wood = Color3.fromRGB(214, 164, 120),
	WoodDark = Color3.fromRGB(160, 110, 78),
	Ink = Color3.fromRGB(92, 58, 96),
}
local P = {
	Grass = Color3.fromRGB(150, 222, 150),
	Leaf = Color3.fromRGB(116, 180, 104),
	LeafDark = Color3.fromRGB(76, 136, 84),
	Trunk = Color3.fromRGB(128, 96, 74),
	Stone = Color3.fromRGB(226, 220, 212),
	StoneDark = Color3.fromRGB(176, 170, 166),
	Pave = Color3.fromRGB(214, 208, 202),
	RoofPink = Color3.fromRGB(255, 150, 190),
	Slate = Color3.fromRGB(190, 170, 240),
	Brick = Color3.fromRGB(236, 152, 146),
	Steel = Color3.fromRGB(128, 106, 156),
	SteelDark = Color3.fromRGB(96, 78, 124),
	Glass = Color3.fromRGB(196, 230, 255),
	Gold = Color3.fromRGB(246, 196, 84),
	Water = Color3.fromRGB(150, 215, 255),
	Lamp = Color3.fromRGB(255, 226, 170),
}
local DEFAULT_WALL: { [string]: Color3 } = {
	Cottage = Color3.fromRGB(255, 242, 228),
	Townhouse = Color3.fromRGB(196, 238, 220),
	Loft = P.Brick,
	Mansion = Color3.fromRGB(255, 232, 242),
}
local DEFAULT_ROOF: { [string]: Color3 } = {
	Cottage = P.RoofPink,
	Townhouse = P.Slate,
	Loft = P.Slate,
	Mansion = P.Slate,
}
-- (compat : nombre de cheminées du look d'origine ; le vrai nombre attendu
-- est Built.ChimneysExpected, qui suit l'option "Chimney")
local CHIMNEYS: { [string]: number } = { Cottage = 1, Townhouse = 2, Loft = 0, Mansion = 2 }
HouseFacade.Chimneys = CHIMNEYS

export type Looks = {
	Wall: Color3?,
	Roof: Color3?,
	Pattern: string?,
	Garden: { string },
	Rooms: { [number]: any },
	Name: string,
	Garage: boolean?,
	Ext: { [string]: any }?, -- (v10) options d'extérieur (HouseOptions)
	Plot: number?, -- (v10) numéro de la parcelle (numéro de maison automatique)
}
-- (v9.8 HOUSE98) un battant de porte : pivote autour de `Hinge` (bas du
-- chant côté gonds) ; Sign = +1 battant gauche (s'étend vers +x), -1 droit
export type Leaf = { Part: BasePart, Hinge: CFrame, Sign: number, Width: number, Height: number }

-- (v10) Look résolu : options du joueur + look de son style / architecture
export type Spec = {
	Style: string,
	Arch: string, -- "Classic" | "Chalet" | "Modern"
	Wall: Color3,
	WallMat: Enum.Material,
	Trim: Color3,
	TrimMat: Enum.Material,
	Roof: Color3,
	RoofMat: Enum.Material,
	RoofKind: string,
	RoofShape: string,
	Parapet: boolean,
	Chimney: string,
	ChimneyColor: Color3?,
	Window: string,
	Shutters: string,
	ShutterColor: Color3,
	Door: string,
	DoorColor: Color3,
	Porch: string,
	Balcony: string,
	Garage: string,
	Fence: string,
	Path: string,
	Mailbox: string,
	MailColor: Color3,
	Lights: string,
	Num: string,
	Key: string, -- signature (reconstruire si elle change)
}

export type Built = {
	Door: BasePart?,
	Hinge: CFrame?,
	Lock: TextLabel?,
	Fills: { [number]: BasePart },
	Chimneys: number,
	ChimneysExpected: number?, -- (v10) cheminées voulues par l'option
	Style: string,
	Arch: string?,
	Spec: Spec?,
	Leaves: { Leaf }?, -- (v9.8) porte d'entrée DOUBLE (2 battants)
	BackLeaves: { Leaf }?, -- (v9.8) porte de derrière (jardin)
	BackFills: { [number]: BasePart }?, -- (v9.8) "rideau" des fenêtres du fond tant que la pièce n'est pas construite
	Glows: { [number]: { Glow } }?, -- (v9.9) lueurs de nuit par emplacement (0 = cage)
}

type Ctx = {
	Kit: any,
	G: any, -- kit du jardin (posé sur la pelouse de la parcelle)
	Size: any,
	Dims: any,
	Style: string,
	Looks: Looks,
	Spec: Spec,
	Wall: Color3,
	WallMat: Enum.Material,
	WallDark: Color3,
	Roof: Color3,
	RoofDark: Color3,
	Trim: Color3,
	Left: number,
	Right: number,
	Top: number, -- haut des murs (plafond du dernier étage)
	Depth: number,
	Hall0: number,
	Hall1: number,
	DoorX: number,
	Built: Built,
	Garage: boolean, -- (v9.6) 🏎️ aile du garage (manoir)
	SideGarage: boolean, -- (v10) garage / abri attenant (autres styles)
}

----------------------------------------------------------------------
-- (v10) Look résolu (options + style)
----------------------------------------------------------------------

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function material(name: string?, default: Enum.Material): Enum.Material
	if type(name) ~= "string" then
		return default
	end
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and typeof(value) == "EnumItem" then value else default
end

-- Look d'origine de chaque style / architecture ("Auto" de chaque option)
local BASE: { [string]: { [string]: any } } = {
	Cottage = { Wall = DEFAULT_WALL.Cottage, WallMat = "Plaster", Trim = C.Cream, Roof = P.RoofPink, RoofMat = "ClayRoofTiles", RoofKind = "Tiles", RoofShape = "Hip",
		Chimney = "Brick", ChimneyColor = rgb(214, 128, 118), Window = "Cross", Shutters = "Board", ShutterColor = rgb(150, 176, 140), Door = "Panel", DoorColor = C.Pink,
		Porch = "Hood", Balcony = "None", Fence = "Picket", Path = "Stones", Mailbox = "Classic", MailColor = rgb(236, 110, 150), Lights = "Lanterns" },
	Townhouse = { Wall = DEFAULT_WALL.Townhouse, WallMat = "Plaster", Trim = C.Cream, Roof = P.Slate, RoofMat = "Slate", RoofKind = "Slate", RoofShape = "Mansard",
		Chimney = "Brick", ChimneyColor = rgb(214, 140, 146), Window = "Tall", Shutters = "Louvered", ShutterColor = rgb(250, 250, 244), Door = "Glazed",
		DoorColor = C.PinkDeep:Lerp(C.Pink, 0.5), Porch = "Surround", Balcony = "Iron", Fence = "Picket", Path = "Pavers", Mailbox = "Classic", MailColor = rgb(60, 110, 96),
		Lights = "Lanterns" },
	Loft = { Wall = DEFAULT_WALL.Loft, WallMat = "Brick", Trim = P.SteelDark, TrimMat = "Metal", Roof = P.Slate, RoofMat = "Slate", RoofKind = "Slate", RoofShape = "Flat",
		Parapet = true, Chimney = "None", Window = "Industrial", Shutters = "None", ShutterColor = rgb(60, 60, 66), Door = "Glazed", DoorColor = P.Steel:Lerp(C.Mint, 0.35),
		Porch = "Steel", Balcony = "None", Fence = "Picket", Path = "Pavers", Mailbox = "American", MailColor = rgb(70, 74, 84), Lights = "Lanterns" },
	Mansion = { Wall = DEFAULT_WALL.Mansion, WallMat = "Plaster", Trim = rgb(255, 250, 244), Roof = P.Slate, RoofMat = "Slate", RoofKind = "Slate", RoofShape = "Mansard",
		Chimney = "Brick", ChimneyColor = rgb(232, 170, 186), Window = "Tall", Shutters = "None", ShutterColor = rgb(250, 250, 244), Door = "Grand",
		DoorColor = C.PinkDeep:Lerp(C.Pink, 0.45), Porch = "Grand", Balcony = "Stone", Fence = "Iron", Path = "Pavers", Mailbox = "Pillar", MailColor = rgb(64, 66, 72),
		Lights = "Lanterns" },
	Chalet = { Wall = rgb(170, 118, 74), WallMat = "WoodPlanks", Trim = rgb(96, 64, 44), TrimMat = "Wood", Roof = rgb(84, 74, 68), RoofMat = "RoofShingles",
		RoofKind = "Shingles", RoofShape = "Gable", Chimney = "Stone", Window = "Cross", Shutters = "Board", ShutterColor = rgb(64, 112, 70), Door = "Rustic",
		DoorColor = rgb(150, 104, 64), Porch = "Chalet", Balcony = "Wood", Fence = "Rail", Path = "Stones", Mailbox = "Birdhouse", MailColor = rgb(170, 60, 50),
		Lights = "Lanterns" },
	Modern = { Wall = rgb(242, 242, 238), WallMat = "Plaster", Trim = rgb(52, 54, 60), TrimMat = "Metal", Roof = rgb(70, 72, 78), RoofMat = "Slate", RoofKind = "Metal",
		RoofShape = "Flat", Parapet = false, Chimney = "Flue", Window = "Modern", Shutters = "None", ShutterColor = rgb(52, 54, 60), Door = "Modern",
		DoorColor = rgb(46, 48, 54), Porch = "Canopy", Balcony = "Glass", Fence = "Slats", Path = "Pavers", Mailbox = "Pillar", MailColor = rgb(64, 66, 72),
		Lights = "Sconces" },
}

-- Choix d'une option (nil = "Auto" / par défaut)
local function optionOf(ext: any, kind: string): any?
	local id = type(ext) == "table" and ext[kind] or nil
	if type(id) ~= "string" or id == HouseOptions.Default(kind) then
		return nil
	end
	local def = HouseOptions.ByKind[kind]
	return def and def.ById[id] or nil
end

local ROOF_KIND = { Tiles = "Tiles", Slate = "Slate", Shingles = "Shingles", Metal = "Metal", Thatch = "Thatch", Copper = "Copper" }

function HouseFacade.Resolve(size: any, looks: Looks?): Spec
	local style = WorldLayout.StyleOf(size)
	if not BASE[style] then
		style = "Cottage"
	end
	local ext = looks and looks.Ext or nil
	local archChoice = optionOf(ext, "Arch")
	local arch = if archChoice then archChoice.Id else "Classic"
	local base = BASE[arch] or BASE[style]
	local classic = arch == "Classic"
	local function pick(kind: string, field: string): any
		local choice = optionOf(ext, kind)
		return if choice then choice.Id else base[field]
	end
	local function color(kind: string, fallback: Color3): Color3
		local choice = optionOf(ext, kind)
		return if choice and typeof(choice.Color) == "Color3" then choice.Color :: Color3 else fallback
	end
	-- couleurs : option > ancienne couleur de façade / toit (style d'origine) > style
	local wall = color("WallColor", if classic and looks and looks.Wall then (looks.Wall :: Color3) else base.Wall)
	local roof = color("RoofColor", if classic and looks and looks.Roof then (looks.Roof :: Color3) else base.Roof)
	local wallChoice = optionOf(ext, "WallMat")
	local wallMat = material(if wallChoice then wallChoice.Material else base.WallMat, M.Plaster)
	local roofChoice = optionOf(ext, "RoofMat")
	local roofKind = if roofChoice then (ROOF_KIND[roofChoice.Id] or "Tiles") else base.RoofKind
	if roofChoice and not optionOf(ext, "RoofColor") then
		if roofChoice.Id == "Thatch" then
			roof = rgb(190, 158, 96)
		elseif roofChoice.Id == "Copper" then
			roof = rgb(104, 158, 138)
		end
	end
	local shapeChoice = optionOf(ext, "RoofShape")
	local shape = if shapeChoice then tostring(shapeChoice.Value) else base.RoofShape
	local trim = color("Trim", base.Trim)
	local trimChosen = optionOf(ext, "Trim") ~= nil
	local num = HouseOptions.ValidNumber(type(ext) == "table" and ext.Num or 0)
	if num <= 0 then
		num = math.max(1, math.floor(tonumber(looks and looks.Plot) or 1))
	end
	local spec: Spec = {
		Style = style,
		Arch = arch,
		Wall = wall,
		WallMat = wallMat,
		Trim = trim,
		TrimMat = if trimChosen then (if trim == rgb(214, 172, 84) then M.Metal else M.Wood) else material(base.TrimMat, M.Wood),
		Roof = roof,
		RoofMat = material(if roofChoice then roofChoice.Material else base.RoofMat, M.Slate),
		RoofKind = roofKind,
		RoofShape = shape,
		Parapet = base.Parapet == true and shape == "Flat",
		Chimney = pick("Chimney", "Chimney"),
		ChimneyColor = base.ChimneyColor,
		Window = pick("Window", "Window"),
		Shutters = pick("Shutters", "Shutters"),
		ShutterColor = color("ShutterColor", base.ShutterColor),
		Door = pick("Door", "Door"),
		DoorColor = color("DoorColor", base.DoorColor),
		Porch = pick("Porch", "Porch"),
		Balcony = pick("Balcony", "Balcony"),
		Garage = if style == "Mansion" then "None" else (optionOf(ext, "Garage") or { Id = "None" }).Id,
		Fence = pick("Fence", "Fence"),
		Path = pick("Path", "Path"),
		Mailbox = if optionOf(ext, "Mailbox") then (optionOf(ext, "Mailbox") :: any).Id else base.Mailbox,
		MailColor = base.MailColor,
		Lights = pick("Lights", "Lights"),
		Num = tostring(num),
		Key = "",
	}
	-- volets "Auto" : ceux du style ; couleur "Auto" = style
	spec.Key = table.concat({ spec.Arch, tostring(spec.Wall), tostring(spec.WallMat), tostring(spec.Trim), tostring(spec.Roof), tostring(spec.RoofMat), spec.RoofKind,
		spec.RoofShape, spec.Chimney, spec.Window, spec.Shutters, tostring(spec.ShutterColor), spec.Door, tostring(spec.DoorColor), spec.Porch, spec.Balcony, spec.Garage,
		spec.Fence, spec.Path, spec.Mailbox, spec.Lights, spec.Num }, "|")
	return spec
end

----------------------------------------------------------------------
-- Petits éléments
----------------------------------------------------------------------

-- (v9.8 HOUSE98) couleur des rideaux d'une pièce (= HouseBuilder : 2e
-- couleur du papier peint) ; une pièce pas encore construite montre ses
-- rideaux tirés derrière la vitre au lieu d'un aplat opaque
local function curtainColor(room: any): Color3
	local style = room and Config.HouseWallpapersById[room.Wallpaper]
	local color = style and style.B
	return typeof(color) == "Color3" and color or Color3.fromRGB(255, 190, 214)
end

-- (v9.9 HOUSE99) Lueur de nuit d'une fenêtre, vue de DEHORS seulement : une
-- SurfaceGui (une seule face : invisible de l'intérieur) sur la vitre, sans
-- influence de la lumière (elle "brille") ; HouseBuilder l'allume la nuit
-- quand la lumière de la pièce est allumée (état sauvegardé du propriétaire :
-- la même pour tout le monde), teintée par les rideaux s'ils sont fermés.
-- (v10) LOD : Part = vitre simplifiée (couleur changée au lieu d'une SurfaceGui)
export type Glow = { Gui: SurfaceGui?, Fill: Frame?, Part: BasePart?, Day: Color3?, DayMat: Enum.Material? }
local function windowGlow(part: BasePart, face: Enum.NormalId): Glow
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NightGlow"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(64, 64)
	gui.LightInfluence = 0
	gui.MaxDistance = 600
	gui.Enabled = false
	gui.Parent = part
	local fill = Instance.new("Frame")
	fill.Name = "Glow"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 206, 140)
	fill.BackgroundTransparency = 0.3
	fill.Parent = gui
	-- plus lumineux en haut (plafonnier), plus doux en bas
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.55, 0.3), NumberSequenceKeypoint.new(1, 0.55) })
	grad.Parent = fill
	return { Gui = gui, Fill = fill }
end
local function addGlow(ctx: Ctx, slot: number?, glow: Glow)
	local glows = ctx.Built.Glows
	if not glows then
		glows = {}
		ctx.Built.Glows = glows
	end
	local key = slot or 0 -- 0 = fenêtres de la cage (toujours allumées la nuit)
	local list = glows[key]
	if not list then
		list = {}
		glows[key] = list
	end
	table.insert(list, glow)
end
-- Fenêtre cintrée : imposte en demi-cercle dessinée (SurfaceGui) au-dessus
-- d'une vitre rectangulaire (le mur n'est percé que du rectangle)
local function archTop(ctx: Ctx, x0: number, x1: number, y1: number, frame: Color3, maxH: number?)
	local kit = ctx.Kit
	local w = x1 - x0 + 0.7
	-- arc surbaissé (demi-ellipse) : ne monte jamais sur l'étage du dessus
	-- (v9.8 : `maxH` = imposte plus basse au-dessus des grandes portes)
	local h = math.min(w / 2, maxH or 2.3)
	local panel = kit:Box("ArchTop", x0 - 0.35, x1 + 0.35, y1, y1 + h, -0.42, -0.38, WHITE, M.SmoothPlastic, { T = 1, Shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Arch"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.MaxDistance = 260
	gui.Parent = panel
	local clip = Instance.new("Frame")
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.Size = UDim2.fromScale(1, 1)
	clip.ClipsDescendants = true
	clip.Parent = gui
	local ring = Instance.new("Frame")
	ring.BorderSizePixel = 0
	ring.BackgroundColor3 = frame
	ring.Size = UDim2.fromScale(1, 2)
	ring.Parent = clip
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local pane = Instance.new("Frame")
	pane.BorderSizePixel = 0
	pane.BackgroundColor3 = P.Glass:Lerp(C.Sky, 0.3)
	pane.AnchorPoint = Vector2.new(0.5, 0.5)
	pane.Position = UDim2.fromScale(0.5, 0.5)
	pane.Size = UDim2.new(1, -16, 1, -16)
	pane.Parent = ring
	local paneCorner = Instance.new("UICorner")
	paneCorner.CornerRadius = UDim.new(0.5, 0)
	paneCorner.Parent = pane
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 220, 255))
	grad.Rotation = 90
	grad.Parent = pane
	-- rayons (croisillons de l'imposte)
	for _, angle in ipairs({ -50, 0, 50 }) do
		local ray = Instance.new("Frame")
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = frame
		ray.AnchorPoint = Vector2.new(0.5, 1)
		ray.Position = UDim2.fromScale(0.5, 1)
		ray.Size = UDim2.new(0, 6, 1, 0)
		ray.Rotation = angle
		ray.Parent = clip
	end
end
-- (v9.9 HOUSE99) Tête de lanterne réaliste (au lieu d'un gros bloc Neon qui
-- éblouissait) : socle, 4 montants, verre dépoli ambré, petite ampoule
-- chaude, chapeau à pans + bouton. (x, y = bas du socle, d = centre) ;
-- renvoie l'ampoule (pour la vraie lumière). `half` = demi-largeur.
local function lanternHead(kit: any, x: number, y: number, d: number, half: number): BasePart
	local metal = C.Ink
	local h = half * 3.1
	kit:Box("LanternBase", x - half - 0.08, x + half + 0.08, y, y + 0.14, d - half - 0.08, d + half + 0.08, metal, M.Metal, { Shadow = false })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sd in ipairs({ -1, 1 }) do
			kit:Box("LanternPost", x + sx * half - 0.05, x + sx * half + 0.05, y + 0.14, y + h, d + sd * half - 0.05, d + sd * half + 0.05, metal, M.Metal,
				{ Shadow = false })
		end
	end
	kit:Box("LanternGlass", x - half + 0.05, x + half - 0.05, y + 0.14, y + h, d - half + 0.05, d + half - 0.05, Color3.fromRGB(255, 236, 196), M.Glass,
		{ T = 0.4, Shadow = false })
	local bulb = kit:Ball("LanternBulb", x, y + h * 0.5, d, half * 0.7, Color3.fromRGB(255, 214, 150), M.Neon, { Shadow = false })
	kit:Box("LanternRoof", x - half - 0.15, x + half + 0.15, y + h, y + h + 0.16, d - half - 0.15, d + half + 0.15, metal, M.Metal, { Shadow = false })
	kit:Box("LanternRoofTop", x - half * 0.55, x + half * 0.55, y + h + 0.16, y + h + 0.34, d - half * 0.55, d + half * 0.55, metal, M.Metal, { Shadow = false })
	kit:Ball("LanternFinial", x, y + h + 0.46, d, 0.24, P.Gold, M.Metal, { Shadow = false })
	return bulb
end
-- Lanterne murale (x, y = bas de la lanterne), vraie lumière si le budget le permet
local function wallLantern(ctx: Ctx, x: number, y: number, withLight: boolean)
	local kit = ctx.Kit
	-- (platine décollée de 0,02 des enduits de façade posés à -0,36 : pas de faces confondues)
	kit:Box("LanternPlate", x - 0.25, x + 0.25, y + 0.6, y + 1.6, -0.44, -0.38, C.Ink, M.Metal, { Shadow = false })
	kit:Box("LanternArm", x - 0.07, x + 0.07, y + 1.25, y + 1.39, -0.72, -0.44, C.Ink, M.Metal, { Shadow = false })
	local bulb = lanternHead(kit, x, y, -1.0, 0.36)
	if withLight then
		kit:Light(bulb, Color3.fromRGB(255, 214, 150), 16, 0.8)
	end
end
-- Lanterne sur poteau (pied en y0)
local function postLantern(ctx: Ctx, x: number, d: number, y0: number, height: number, withLight: boolean, onKit: any?)
	local kit = onKit or ctx.Kit
	kit:CylY("LampPost", x, y0, d, 0.35, height, C.Ink, M.Metal, { Solid = true, Shadow = false })
	local bulb = lanternHead(kit, x, y0 + height, d, 0.42)
	if withLight then
		kit:Light(bulb, Color3.fromRGB(255, 214, 150), 18, 0.85)
	end
end
-- (v9.9 HOUSE99) Fontaine de la cour d'honneur du manoir ("les trucs fontaine
-- de l'entrée sont cassés" : l'ancienne était un empilement de cylindres, l'eau
-- DÉPASSAIT du bassin, un gros jet blanc) : bassin octogonal en pierre
-- (8 murets + margelle), eau sous la margelle, fût mouluré, 2 vasques avec
-- nappes d'eau translucides qui retombent, jet fin qui pétille, pièces au
-- fond ; parvis rond pavé autour (le chemin fait le tour).
local function courtFountain(ctx: Ctx, x: number, d: number)
	local kit = ctx.G
	local STONE = Color3.fromRGB(236, 230, 226)
	local WATER = Color3.fromRGB(120, 190, 225)
	kit:CylY("FountainPlaza", x, -0.06, d, 15, 0.13, P.Pave:Lerp(P.Stone, 0.4), M.Pavement, { Shadow = false })
	local apothem, wallT, wallH = 4.6, 0.6, 1.5
	local sideLen = 2 * apothem * math.tan(math.pi / 8) + 0.02
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local cf = CFrame.new(x, 0, -d) * CFrame.Angles(0, a, 0)
		kit:Part("FountainWall", Vector3.new(sideLen, wallH, wallT), cf * CFrame.new(0, wallH / 2, apothem - wallT / 2), STONE, M.Limestone, { Solid = true })
		kit:Part("FountainCoping", Vector3.new(sideLen + 0.34, 0.26, wallT + 0.36), cf * CFrame.new(0, wallH + 0.13, apothem - wallT / 2), STONE:Lerp(WHITE, 0.3),
			M.Limestone, { Shadow = false })
	end
	-- eau du bassin (sous la margelle) + fond + pièces
	kit:CylY("FountainFloor", x, 0.05, d, 2 * (apothem - wallT) + 0.1, 0.25, Color3.fromRGB(96, 150, 170), M.Slate, { Shadow = false })
	local basinWater = kit:CylY("FountainWater", x, 0.3, d, 2 * (apothem - wallT) + 0.08, 0.9, WATER, M.SmoothPlastic, { T = 0.35, Shadow = false })
	basinWater.Reflectance = 0.2
	for k = 0, 4 do
		local a = k * 1.7 + 0.4
		kit:CylY("FountainCoin", x + math.cos(a) * (1.8 + k * 0.35), 0.3, d + math.sin(a) * (1.8 + k * 0.35), 0.3, 0.04, P.Gold, M.Metal, { Shadow = false })
	end
	-- fût mouluré + vasque basse (eau dedans) + nappe qui retombe
	kit:CylY("FountainPlinth", x, 0.3, d, 2.2, 0.6, STONE, M.Limestone, { Shadow = false })
	kit:CylY("FountainShaft", x, 0.9, d, 1.3, 2.2, STONE, M.Limestone, { Solid = true, Shadow = false })
	kit:CylY("FountainCollar", x, 2.9, d, 1.7, 0.3, STONE:Lerp(WHITE, 0.3), M.Limestone, { Shadow = false })
	kit:CylY("FountainBowl", x, 3.2, d, 5.2, 0.4, STONE, M.Limestone, { Shadow = false })
	kit:CylY("FountainBowlWater", x, 3.6, d, 4.7, 0.1, WATER, M.SmoothPlastic, { T = 0.3, Shadow = false })
	kit:CylY("FountainSheet", x, 1.2, d, 5.25, 2.0, Color3.fromRGB(200, 232, 250), M.SmoothPlastic, { T = 0.84, Shadow = false })
	-- vasque haute + sa nappe + jet
	kit:CylY("FountainUpperShaft", x, 3.74, d, 0.8, 1.5, STONE, M.Limestone, { Shadow = false })
	kit:CylY("FountainUpperBowl", x, 5.24, d, 2.8, 0.34, STONE, M.Limestone, { Shadow = false })
	kit:CylY("FountainUpperWater", x, 5.58, d, 2.5, 0.08, WATER, M.SmoothPlastic, { T = 0.3, Shadow = false })
	kit:CylY("FountainUpperSheet", x, 3.76, d, 2.85, 1.46, Color3.fromRGB(200, 232, 250), M.SmoothPlastic, { T = 0.86, Shadow = false })
	local spout = kit:Ball("FountainSpout", x, 5.85, d, 0.55, C.Pink, M.SmoothPlastic, { Shadow = false })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FountainSpray"
	emitter.Color = ColorSequence.new(Color3.fromRGB(235, 248, 255), Color3.fromRGB(170, 215, 245))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0.06) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.55, 0.75)
	emitter.Speed = NumberRange.new(7, 8)
	emitter.SpreadAngle = Vector2.new(6, 6)
	emitter.Acceleration = Vector3.new(0, -24, 0)
	emitter.Rate = 36
	emitter.LightInfluence = 1
	emitter.Parent = spout
end
local function bush(ctx: Ctx, x: number, d: number, w: number, h: number, color: Color3)
	local kit = ctx.G
	kit:Ball("Bush", x, h * 0.42, d, h, color, M.Grass)
	if w > h * 1.2 then
		kit:Ball("Bush", x - w * 0.3, h * 0.34, d + 0.1, h * 0.8, color:Lerp(P.LeafDark, 0.15), M.Grass)
		kit:Ball("Bush", x + w * 0.3, h * 0.34, d - 0.1, h * 0.8, color:Lerp(WHITE, 0.08), M.Grass)
	end
end
local function flowerDots(ctx: Ctx, x0: number, x1: number, d: number, count: number)
	local colors = { C.Pink, C.Butter, WHITE, C.Lilac, C.Peach }
	for k = 0, count - 1 do
		local x = x0 + (k + 0.5) * (x1 - x0) / count
		ctx.G:Ball("Flower", x, 0.55 + (k % 2) * 0.15, d + (k % 3 - 1) * 0.35, 0.6, colors[k % #colors + 1], M.SmoothPlastic, { Shadow = false })
	end
end

-- Arbre (tronc + feuillage en grappe + fruits) ; (v10) plus naturel : tronc
-- plus fin, branches, feuillage en 5 masses de verts différents
local function tree(ctx: Ctx, x: number, d: number, s: number, fruit: Color3?)
	local kit = ctx.G
	kit:CylY("Trunk", x, 0, d, 0.9 * s, 6.4 * s, P.Trunk, M.Wood, { Solid = true })
	HouseDetail.Tube(kit, "Branch", { x, 5 * s, d }, { x - 1.8 * s, 7.2 * s, d + 0.4 }, 0.45 * s, P.Trunk, M.Wood)
	HouseDetail.Tube(kit, "Branch", { x, 5.4 * s, d }, { x + 1.7 * s, 7.6 * s, d - 0.3 }, 0.42 * s, P.Trunk, M.Wood)
	local greens = { P.Leaf, P.Leaf:Lerp(P.LeafDark, 0.3), P.Leaf:Lerp(WHITE, 0.06), P.LeafDark:Lerp(P.Leaf, 0.5), P.Leaf:Lerp(P.LeafDark, 0.15) }
	local blobs = { { 0, 8.6, 0, 6 }, { -2.4, 7.6, 0.6, 4.6 }, { 2.3, 7.8, -0.5, 4.8 }, { -0.6, 10.2, -0.4, 4.2 }, { 1, 7, 1.6, 3.8 } }
	for index, b in ipairs(blobs) do
		kit:Ball("Leaves", x + b[1] * s, b[2] * s, d + b[3], b[4] * s, greens[index], M.Grass, { Shadow = true })
	end
	if fruit then
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			kit:Ball("Fruit", x + math.cos(a) * 2.6 * s, 7.6 * s + math.sin(a * 2) * 1.2 * s, d - 2.3 * s - math.sin(a) * 0.8, 0.6 * s, fruit, M.SmoothPlastic,
				{ Shadow = false })
		end
	end
end

-- (v10) Sapin (chalet) : tronc + 4 étages coniques
local function pine(ctx: Ctx, x: number, d: number, s: number)
	local kit = ctx.G
	kit:CylY("Trunk", x, 0, d, 0.8 * s, 3 * s, P.Trunk, M.Wood, { Solid = true })
	for k = 0, 3 do
		local r = (3.6 - k * 0.75) * s
		kit:Cone("PineTier", x, (2.2 + k * 2.3) * s, d, r, 3.6 * s, 6, Color3.fromRGB(58, 104, 70):Lerp(Color3.fromRGB(86, 136, 90), k * 0.2), M.Grass)
	end
end

-- Cœur plat (face à la rue) : carré tourné + 2 disques ; (x, y) = centre
local function heart(ctx: Ctx, x: number, y: number, d: number, size: number, color: Color3, material: Enum.Material?)
	local kit = ctx.Kit
	local side = size / 1.707
	local oy = y - side * 0.0735
	kit:Part("Heart", Vector3.new(side, side, 0.3), CFrame.new(x, oy, -d) * CFrame.Angles(0, 0, math.pi / 4), color, material or M.SmoothPlastic, { Shadow = false })
	local offset = side / (2 * math.sqrt(2))
	for _, sx in ipairs({ -1, 1 }) do
		kit:CylD("Heart", x + sx * offset, oy + offset, d, side, 0.3, color, material or M.SmoothPlastic, { Shadow = false })
	end
end
-- Motif du toit (RoofStyle.Pattern) : dessiné sur le dessus d'un pan (SurfaceGui)
local function roofPattern(ctx: Ctx, slab: BasePart, pattern: string)
	if pattern == "None" or pattern == "" then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "RoofPattern"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 6
	gui.LightInfluence = 1
	gui.MaxDistance = 400
	gui.Parent = slab
	local w, h = slab.Size.X * 6, slab.Size.Z * 6
	local light = ctx.Roof:Lerp(WHITE, 0.55)
	local function dot(x: number, y: number, size: number, color: Color3, round: boolean, rotation: number?)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(size, size)
		f.Rotation = rotation or 0
		f.Parent = gui
		if round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = f
		end
		return f
	end
	local stepX, stepY = 17, 14
	if pattern == "Stripes" or pattern == "Checkered" or pattern == "Snow" then
		stepX = 13
	end
	local row = 0
	local y = stepY * 0.6
	local index = 0
	while y < h - 4 do
		local x = (row % 2) * stepX / 2 + stepX * 0.5
		while x < w - 4 do
			index += 1
			if pattern == "Hearts" then
				local color = if index % 3 == 0 then C.Heart else light
				dot(x, y + 1, 7, color, false, 45)
				dot(x - 2.6, y - 2, 6, color, true)
				dot(x + 2.6, y - 2, 6, color, true)
			elseif pattern == "Dots" then
				dot(x, y, 6, if index % 2 == 0 then WHITE else light, true)
			elseif pattern == "Stars" then
				local color = if index % 3 == 0 then C.Butter else WHITE
				dot(x, y, 6, color, false, 45)
				dot(x, y, 6, color, false)
			elseif pattern == "Flowers" then
				local color = if index % 3 == 0 then C.Butter elseif index % 3 == 1 then C.Pink else WHITE
				for k = 0, 4 do
					local a = k / 5 * math.pi * 2
					dot(x + math.cos(a) * 2.6, y + math.sin(a) * 2.6, 4, color, true)
				end
				dot(x, y, 3, C.Butter, true)
			elseif pattern == "Scales" then
				dot(x, y, 12, if index % 2 == 0 then light else ctx.Roof:Lerp(C.Mint, 0.4), true)
			elseif pattern == "Bolts" then
				dot(x, y, 3, C.Butter, false, 30).Size = UDim2.fromOffset(3, 10)
			elseif pattern == "Camo" then
				dot(x + (index % 3) * 3, y, 9 + (index % 2) * 4, if index % 2 == 0 then Color3.fromRGB(96, 120, 80) else Color3.fromRGB(140, 150, 100), true)
			elseif pattern == "Flames" then
				dot(x, y, 7, if index % 2 == 0 then Color3.fromRGB(255, 120, 50) else Color3.fromRGB(255, 200, 80), true)
			elseif pattern == "Checkered" then
				if index % 2 == 0 then
					dot(x, y, 12, Color3.fromRGB(40, 40, 50), false)
				end
			elseif pattern == "Stripes" then
				if row == 0 and index % 2 == 0 then
					local stripe = dot(x, h / 2, 6, WHITE, false)
					stripe.Size = UDim2.fromOffset(6, h)
				end
			elseif pattern == "Snow" then
				if row == 0 then
					dot(x, h - 5, 14, WHITE, true)
				end
			end
			x += stepX
		end
		y += stepY
		row += 1
	end
end

-- Lucarne sur un pan avant (pied à `yBase`, face avant en `d`)
local function dormer(ctx: Ctx, x: number, yBase: number, d: number, w: number, h: number, round: boolean)
	local kit = ctx.Kit
	local body = if ctx.Spec.Arch == "Chalet" then ctx.Wall else ctx.Trim
	local bodyMat = if ctx.Spec.Arch == "Chalet" then ctx.WallMat else M.Plaster
	kit:Box("Dormer", x - w / 2, x + w / 2, yBase, yBase + h, d, d + 3.5, body, bodyMat, { Solid = true })
	local cy = yBase + h * 0.5
	local frame = if ctx.Spec.Arch == "Chalet" then C.Cream else C.Cream:Lerp(ctx.Trim, 0.3)
	if round then
		kit:CylD("DormerRing", x, cy, d - 0.12, w * 0.7, 0.3, frame, M.Wood, { Shadow = false })
		kit:CylD("DormerGlass", x, cy, d - 0.3, w * 0.52, 0.12, P.Glass, M.Glass, { Shadow = false })
	else
		kit:Box("DormerGlass", x - w * 0.28, x + w * 0.28, yBase + 0.8, yBase + h - 1, d - 0.14, d + 0.05, P.Glass, M.Glass, { Shadow = false })
		kit:Box("DormerFrame", x - w * 0.33, x + w * 0.33, yBase + 0.6, yBase + 0.8, d - 0.3, d + 0.05, frame, M.Wood, { Shadow = false })
		kit:Box("DormerFrame", x - w * 0.33, x + w * 0.33, yBase + h - 1, yBase + h - 0.8, d - 0.3, d + 0.05, frame, M.Wood, { Shadow = false })
		kit:Box("DormerBar", x - 0.08, x + 0.08, yBase + 0.8, yBase + h - 1, d - 0.2, d - 0.1, frame, M.Wood, { Shadow = false })
	end
	-- petit toit à deux pans (même couverture que le toit) + rives
	local rise = w * 0.42
	for _, s in ipairs({ -1, 1 }) do
		kit:Part("DormerRoof", Vector3.new(4, rise, w / 2 + 0.4), CFrame.new(x + s * (w / 4 + 0.1), yBase + h + rise / 2, -(d + 1.6)) * CFrame.Angles(0, -s * math.pi / 2, 0),
			ctx.Roof, ctx.Spec.RoofMat, { Solid = true }, "WedgePart")
	end
	HouseDetail.GableX(kit, "DormerBarge", d - 0.42, d - 0.3, x - w / 2 - 0.4, x + w / 2 + 0.4, yBase + h - 0.1, yBase + h + rise + 0.1, ctx.Trim:Lerp(WHITE, 0.2), M.Wood,
		{ Shadow = false })
end

-- Perron : palier devant la porte + `steps` marches vers la rue, rampe invisible
local function porch(ctx: Ctx, x0: number, x1: number, landingD: number, steps: number, color: Color3, material: Enum.Material)
	local kit = ctx.Kit
	local yTop = WorldLayout.FloorY(1)
	local tread = 1.25
	-- (v9.6 : 0,04 sous le seuil : pas coplanaire avec le mur sous la porte)
	-- (v9.8 : pied 0,06 sous le sol : jamais coplanaire avec le soubassement)
	kit:Box("Porch", x0, x1, -0.06, yTop - 0.04, -landingD, 0, color, material, { Solid = true })
	-- `steps` contremarches : la dernière arrive sur la pelouse
	local rise = yTop / steps
	for k = 1, steps - 1 do
		local top = yTop - k * rise
		local d0 = -landingD - k * tread
		kit:Box("PorchStep", x0 + 0.3, x1 - 0.3, 0, top, d0, d0 + tread, color:Lerp(WHITE, (k % 2) * 0.12), material, { Shadow = false })
	end
	-- rampe lisse (invisible) par le nez des marches, jusqu'à la pelouse
	local run = (steps - 0.5) * tread
	local lawn = HouseKit.LAWN
	local slope = (yTop - lawn) / run
	kit:Slab("PorchRamp", (x0 + x1) / 2, { lawn - 0.6 * slope, -landingD - run - 0.6 }, { yTop, -landingD }, x1 - x0 - 0.8, 1, WHITE, M.SmoothPlastic,
		{ Solid = true, Query = true, T = 1, Shadow = false })
	return -landingD - (steps - 1) * tread
end
local PLATE_H = 1.7
local function namePlate(ctx: Ctx, x: number, y: number, dWall: number, w: number)
	local kit = ctx.Kit
	local board = Color3.fromRGB(122, 80, 62)
	kit:Box("NamePlateBoard", x - w / 2 - 0.3, x + w / 2 + 0.3, y - 0.3, y + PLATE_H + 0.3, dWall - 0.22, dWall - 0.02, board, M.Wood, { Shadow = false })
	kit:Box("NamePlateRim", x - w / 2 - 0.1, x + w / 2 + 0.1, y - 0.1, y + PLATE_H + 0.1, dWall - 0.27, dWall - 0.2, P.Gold, M.Metal, { Shadow = false })
	local plate = kit:Box("NamePlate", x - w / 2, x + w / 2, y, y + PLATE_H, dWall - 0.33, dWall - 0.24, Color3.fromRGB(255, 250, 238), M.SmoothPlastic, { Shadow = false })
	for _, s in ipairs({ -1, 1 }) do
		kit:Ball("NamePlateScrew", x + s * (w / 2 + 0.16), y + PLATE_H / 2, dWall - 0.23, 0.16, P.Gold, M.Metal, { Shadow = false })
	end
	local label = kit:Text(plate, Enum.NormalId.Back, "🏠 " .. ctx.Looks.Name, Color3.fromRGB(110, 52, 86), Enum.Font.FredokaOne, 40, 260)
	label.Size = UDim2.fromScale(0.94, 0.86)
	label.Position = UDim2.fromScale(0.03, 0.07)
	label.TextStrokeColor3 = Color3.fromRGB(255, 214, 232)
	label.TextStrokeTransparency = 0.4
	plate:SetAttribute("NamePlate", true)
end

----------------------------------------------------------------------
-- Porte d'entrée (battants qui pivotent : HouseBuilder.StepDoor)
----------------------------------------------------------------------

-- (v9.8 HOUSE98) porte DOUBLE (2 battants de DOOR_W / 2) dans le mur de
-- devant (back = false : s'ouvre vers l'intérieur) ou du fond (back = true :
-- s'ouvre vers le jardin). Repère "devant" : d = o ; "fond" : d = Depth - o
-- (miroir : la face extérieure du mur du fond = celle de la façade).
-- Décor de chaque battant soudé (WeldConstraint) : il pivote avec lui.
-- (v10) décor selon le style de porte (option "Door")
local function doorLeaves(ctx: Ctx, x: number, back: boolean, leafColor: Color3, frameColor: Color3, style: string): { Leaf }
	local kit = ctx.Kit
	local y0 = WorldLayout.FloorY(1)
	local w, h = WorldLayout.DOOR_W, WorldLayout.DOOR_H
	local depth = ctx.Depth
	local function D(o: number): number
		return if back then depth - o else o
	end
	local function box(name: string, x0: number, x1: number, y1: number, y2: number, o0: number, o1: number, color: Color3, mat: Enum.Material, opts: any): BasePart
		local a, b = D(o0), D(o1)
		return kit:Box(name, x0, x1, y1, y2, math.min(a, b), math.max(a, b), color, mat, opts)
	end
	-- chambranle (0,05 dans l'ouverture : jamais coplanaire avec les tranches du mur)
	for _, sx in ipairs({ -1, 1 }) do
		box("DoorFrame", x + sx * (w / 2) - 0.3, x + sx * (w / 2) + 0.3, y0, y0 + h + 0.4, -0.7, 0.25, frameColor, M.Wood, { Solid = true })
	end
	box("DoorFrame", x - w / 2 - 0.45, x + w / 2 + 0.45, y0 + h - 0.05, y0 + h + 0.6, -0.75, 0.25, frameColor, M.Wood)
	-- seuil de pierre
	box("DoorThreshold", x - w / 2 - 0.2, x + w / 2 + 0.2, y0 - 0.12, y0 + 0.04, -0.9, 0.2, Color3.fromRGB(200, 196, 190), M.Limestone, { Shadow = false })
	local leaves: { Leaf } = {}
	local lw = w / 2 - 0.08 -- largeur d'un battant
	local lh = h - 0.05
	local brass = Color3.fromRGB(214, 176, 92)
	for _, sign in ipairs({ 1, -1 }) do
		-- sign = +1 : battant gauche (gonds à gauche) ; -1 : battant droit
		local hingeX = x - sign * (w / 2 - 0.05)
		local x0, x1 = math.min(hingeX, hingeX + sign * lw), math.max(hingeX, hingeX + sign * lw)
		local leaf = box("DoorLeaf", x0, x1, y0 + 0.04, y0 + lh, 0.15, 0.55, leafColor, M.Wood, { Solid = true, Shadow = true })
		local function add(part: BasePart)
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = leaf
			weld.Part1 = part
			weld.Parent = leaf
		end
		local tint = leafColor:Lerp(WHITE, 0.14)
		local shade = leafColor:Lerp(BLACK, 0.2)
		local knobX = hingeX + sign * (lw - 0.45)
		local fy0, fy1 = y0 + 0.04, y0 + lh
		local lhh = fy1 - fy0
		if style == "Glazed" then
			add(box("DoorPanel", x0 + 0.45, x1 - 0.45, fy0 + 0.6, fy0 + lhh * 0.3, 0.05, 0.16, tint, M.Wood, { Shadow = false }))
			add(box("DoorGlass", x0 + 0.5, x1 - 0.5, fy0 + lhh * 0.36, fy1 - 0.5, 0.05, 0.16, P.Glass, M.Glass, { T = 0.35, Shadow = false }))
			for k = 1, 2 do
				local y = fy0 + lhh * 0.36 + k * (fy1 - 0.5 - fy0 - lhh * 0.36) / 3
				add(box("DoorMuntin", x0 + 0.5, x1 - 0.5, y - 0.07, y + 0.07, 0.02, 0.16, leafColor, M.Wood, { Shadow = false }))
			end
		elseif style == "Rustic" then
			for k = 1, 2 do
				local px = x0 + k * (x1 - x0) / 3
				add(box("DoorPlankJoint", px - 0.05, px + 0.05, fy0 + 0.2, fy1 - 0.2, 0.08, 0.16, shade, M.Wood, { Shadow = false }))
			end
			for _, by in ipairs({ fy0 + lhh * 0.18, fy0 + lhh * 0.78 }) do
				local sx0 = if sign > 0 then x0 + 0.08 else x0 + 0.5
				local sx1 = if sign > 0 then x1 - 0.5 else x1 - 0.08
				add(box("DoorStrap", sx0, sx1, by - 0.18, by + 0.18, 0.02, 0.16, HouseDetail.IRON, M.Metal, { Shadow = false }))
			end
			add(box("DoorPeep", x0 + 0.9, x1 - 0.9, fy0 + lhh * 0.62, fy0 + lhh * 0.72, 0.06, 0.16, P.Glass, M.Glass, { T = 0.3, Shadow = false }))
		elseif style == "Modern" then
			local gx0 = if sign > 0 then x0 + 0.5 else x1 - 0.85
			add(box("DoorGlass", gx0, gx0 + 0.35, fy0 + 1, fy1 - 1, 0.06, 0.16, P.Glass, M.Glass, { T = 0.3, Shadow = false }))
			add(box("DoorPullBar", knobX - 0.1, knobX + 0.1, fy0 + 2.2, fy0 + 6.8, -0.28, -0.08, Color3.fromRGB(206, 210, 216), M.Metal, { Shadow = false }))
			for _, by in ipairs({ fy0 + 2.4, fy0 + 6.6 }) do
				add(box("DoorPullFoot", knobX - 0.06, knobX + 0.06, by - 0.06, by + 0.06, -0.1, 0.16, Color3.fromRGB(206, 210, 216), M.Metal, { Shadow = false }))
			end
		elseif style == "Grand" then
			add(box("DoorPanel", x0 + 0.4, x1 - 0.4, fy0 + 0.6, fy0 + lhh * 0.28, 0.05, 0.16, tint, M.Wood, { Shadow = false }))
			add(box("DoorPanel", x0 + 0.4, x1 - 0.4, fy0 + lhh * 0.34, fy0 + lhh * 0.6, 0.05, 0.16, tint, M.Wood, { Shadow = false }))
			add(box("DoorGlass", x0 + 0.55, x1 - 0.55, fy0 + lhh * 0.66, fy1 - 0.45, 0.05, 0.16, P.Glass, M.Glass, { T = 0.35, Shadow = false }))
			add(box("DoorCarving", x0 + 0.8, x1 - 0.8, fy0 + lhh * 0.44, fy0 + lhh * 0.5, 0.0, 0.16, brass, M.Metal, { Shadow = false }))
		else
			-- "Panel" : 3 panneaux en relief
			add(box("DoorPanel", x0 + 0.45, x1 - 0.45, fy0 + 0.7, fy0 + lhh * 0.36, 0.05, 0.16, tint, M.Wood, { Shadow = false }))
			add(box("DoorPanel", x0 + 0.45, x1 - 0.45, fy0 + lhh * 0.42, fy0 + lhh * 0.62, 0.05, 0.16, tint, M.Wood, { Shadow = false }))
			add(box("DoorPanel", x0 + 0.45, x1 - 0.45, fy0 + lhh * 0.68, fy1 - 0.6, 0.05, 0.16, tint, M.Wood, { Shadow = false }))
		end
		if style ~= "Modern" then
			add(box("DoorEscutcheon", knobX - 0.14, knobX + 0.14, y0 + 3.7, y0 + 4.6, 0.0, 0.16, brass, M.Metal, { Shadow = false }))
			-- poignée (boule qui traverse le battant : visible des deux côtés)
			add(kit:Ball("DoorKnob", knobX, y0 + 4.1, D(0.35), 0.62, brass, M.Metal, { Shadow = false }))
		end
		table.insert(leaves, { Part = leaf, Hinge = kit.CF * CFrame.new(hingeX, y0, -D(0.35)), Sign = sign, Width = lw, Height = lh })
	end
	return leaves
end

local function frontDoor(ctx: Ctx)
	local spec = ctx.Spec
	local leaves = doorLeaves(ctx, ctx.DoorX, false, spec.DoorColor, if spec.Arch == "Modern" then ctx.Trim else ctx.Trim:Lerp(C.WoodDark, 0.15), spec.Door)
	ctx.Built.Leaves = leaves
	local leaf = leaves[1].Part
	ctx.Built.Door = leaf
	ctx.Built.Hinge = leaves[1].Hinge
	-- 🔒 sur la porte (propriétaire qui ne reçoit pas ce joueur)
	local lockGui = Instance.new("SurfaceGui")
	lockGui.Name = "Lock"
	lockGui.Face = Enum.NormalId.Back
	lockGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	lockGui.PixelsPerStud = 30
	lockGui.LightInfluence = 0
	lockGui.MaxDistance = 120
	lockGui.Parent = leaf
	local lock = Instance.new("TextLabel")
	lock.Name = "Text"
	lock.BackgroundTransparency = 1
	lock.Size = UDim2.fromScale(1, 0.3)
	lock.Position = UDim2.fromScale(0, 0.25)
	lock.Font = Enum.Font.GothamBold
	lock.Text = ""
	lock.TextScaled = true
	lock.TextColor3 = WHITE
	lock.Parent = lockGui
	ctx.Built.Lock = lock
end

-- (v10) Abri au-dessus de la porte selon l'option "Porch" (hors styles qui
-- ont leur propre entrée) ; yTop = haut de l'encadrement / imposte ; maxY =
-- plafond à ne pas dépasser (bandeau d'étage...) ; landingD = profondeur du perron
local function porchCover(ctx: Ctx, kind: string, yTop: number, maxY: number, landingD: number)
	local kit = ctx.Kit
	local gx = ctx.DoorX
	local trim = ctx.Trim
	if kind == "Canopy" then
		-- auvent : dalle / verre sur consoles d'acier
		local y = math.min(yTop + 0.6, maxY - 0.6)
		local steel = Color3.fromRGB(58, 60, 66)
		if ctx.Spec.Arch == "Modern" then
			kit:Box("Canopy", gx - 5.2, gx + 5.2, y, y + 0.6, -landingD - 0.4, -0.3, trim, M.SmoothPlastic, { Solid = true })
			local spot = kit:Box("CanopySpot", gx - 0.4, gx + 0.4, y - 0.05, y + 0.02, -2.2, -1.4, P.Lamp, M.Neon, { Shadow = false })
			local _ = spot
		else
			kit:Box("CanopyGlass", gx - 4.4, gx + 4.4, y + 0.3, y + 0.45, -2.9, -0.35, P.Glass, M.Glass, { T = 0.45, Shadow = false })
			kit:Box("CanopyFrame", gx - 4.5, gx + 4.5, y + 0.2, y + 0.3, -3, -0.35, steel, M.Metal, { Shadow = false })
			for _, s in ipairs({ -1, 1 }) do
				HouseDetail.Rod(kit, "CanopyTie", { gx + s * 4, y + 0.3, -2.8 }, { gx + s * 4, y + 2.1, -0.35 }, 0.12, 0.12, steel, M.Metal, { Shadow = false })
			end
		end
		return
	end
	if kind == "Columns" then
		-- porche à colonnes : fronton sur 2 colonnes, au bord du perron
		local y = math.min(yTop + 1.2, maxY - 1.2)
		local d0 = -landingD + 0.2
		for _, s in ipairs({ -1, 1 }) do
			local cx = gx + s * 4.4
			kit:Box("PorchPlinth", cx - 0.6, cx + 0.6, WorldLayout.FloorY(1) - 0.04, WorldLayout.FloorY(1) + 0.5, d0 - 0.6, d0 + 0.6, trim, M.Limestone, { Shadow = false })
			kit:CylY("PorchColumn", cx, WorldLayout.FloorY(1) + 0.5, d0, 0.9, y - WorldLayout.FloorY(1) - 0.9, trim, M.Marble, { Solid = true, Shadow = false })
			kit:Box("PorchCapital", cx - 0.62, cx + 0.62, y - 0.4, y, d0 - 0.62, d0 + 0.62, trim, M.Limestone, { Shadow = false })
		end
		kit:Box("PorchBeam", gx - 5.2, gx + 5.2, y, y + 0.9, d0 - 0.8, -0.3, trim, M.Limestone, { Solid = true })
		HouseDetail.GableX(kit, "PorchPediment", d0 - 0.6, d0 - 0.2, gx - 5.4, gx + 5.4, y + 0.9, y + 2.7, trim, M.Limestone, { Shadow = false })
		for _, s in ipairs({ -1, 1 }) do
			HouseDetail.Rod(kit, "PorchRoof", { gx + s * 5.6, y + 0.8, (d0 - 1 - 0.3) / 2 }, { gx, y + 2.9, (d0 - 1 - 0.3) / 2 }, -d0 + 0.3 + 0.9, 0.3, ctx.Roof, ctx.Spec.RoofMat,
				{ Solid = true }, Vector3.new(0, 0, 1))
		end
		return
	end
	if kind == "Pergola" or kind == "Chalet" then
		-- pergola / avant-toit de chalet : poteaux de bois, poutres, chevrons (+ vigne ou petit toit)
		local wood = if kind == "Chalet" then ctx.Trim else Color3.fromRGB(150, 110, 76)
		local y = math.min(yTop + 1, maxY - 0.8)
		local d0 = -landingD + 0.3
		for _, s in ipairs({ -1, 1 }) do
			local cx = gx + s * 4.6
			kit:Box("PergolaPost", cx - 0.3, cx + 0.3, WorldLayout.FloorY(1) - 0.04, y, d0 - 0.3, d0 + 0.3, wood, M.Wood, { Solid = true, Shadow = false })
			HouseDetail.Rod(kit, "PergolaBrace", { cx, y - 1.4, d0 }, { cx - s * 1.2, y - 0.1, d0 }, 0.22, 0.22, wood, M.Wood, { Shadow = false }, Vector3.new(0, 0, 1))
		end
		kit:Box("PergolaBeam", gx - 5.4, gx + 5.4, y, y + 0.55, d0 - 0.35, d0 + 0.2, wood, M.Wood, { Shadow = false })
		if kind == "Chalet" then
			HouseDetail.GableX(kit, "PorchGable", d0 - 0.3, d0 - 0.1, gx - 5.6, gx + 5.6, y + 0.55, y + 3.2, ctx.Wall, ctx.WallMat, { Shadow = false })
			for _, s in ipairs({ -1, 1 }) do
				local mid = (d0 - 0.9 - 0.3) / 2
				HouseDetail.Rod(kit, "PorchRoof", { gx + s * 6.2, y + 0.4, mid }, { gx, y + 3.4, mid }, -d0 + 0.3 + 1.2, 0.35, ctx.Roof, ctx.Spec.RoofMat, { Solid = true },
					Vector3.new(0, 0, 1))
			end
		else
			local n = 6
			for k = 0, n do
				local x = gx - 5 + k * 10 / n
				kit:Box("PergolaRafter", x - 0.12, x + 0.12, y + 0.55, y + 0.95, d0 - 0.8, -0.3, wood, M.Wood, { Shadow = false })
			end
			for k = 0, 4 do
				ctx.Kit:Ball("Vine", gx - 4.5 + k * 2.25, y + 1.05, d0 + 0.6 + (k % 2) * 0.8, 1.3, P.Leaf:Lerp(P.LeafDark, (k % 2) * 0.3), M.Grass, { Shadow = false })
			end
		end
		return
	end
	if kind == "Hood" then
		-- auvent à pignon sur consoles (chaumière)
		local y = math.min(yTop + 1.9, maxY - 2.6)
		local hood = ctx.Roof
		for _, s in ipairs({ -1, 1 }) do
			HouseDetail.Rod(kit, "HoodBracket", { gx + s * 3.9, y - 1.6, -0.35 }, { gx + s * 3.9, y, -1.9 }, 0.3, 0.3, C.WoodDark, M.Wood, { Shadow = false }, Vector3.new(1, 0, 0))
			HouseDetail.Rod(kit, "HoodRoof", { gx + s * 4.6, y, -1.25 }, { gx, y + 1.5, -1.25 }, 2.3, 0.3, hood, ctx.Spec.RoofMat, { Shadow = true }, Vector3.new(0, 0, 1))
		end
		HouseDetail.GableX(kit, "HoodGable", -0.6, -0.36, gx - 4.2, gx + 4.2, y, y + 1.3, ctx.Wall:Lerp(C.Pink, 0.1), M.Plaster, { Shadow = false })
		return
	end
end

----------------------------------------------------------------------
-- (v9.8 HOUSE98) Le côté JARDIN : mur du fond percé de vraies fenêtres
-- (une par pièce : WorldLayout.BackWindowRect ; la coque de la pièce est
-- percée au même endroit : House3DScene BackWindow), fenêtres de palier,
-- porte double de derrière + perron à marches vers le jardin (rampe invisible).
----------------------------------------------------------------------

-- Rectangle de la fenêtre du fond d'une pièce (repère local de la maison) :
-- { x0, x1, y0, y1 } = exactement le trou de la coque
function HouseFacade.BackWindowRect(size: any, column: number, floor: number): { number }
	local x0, x1 = WorldLayout.ColumnSpan(size, column)
	local cx = (x0 + x1) / 2
	local yFloor = WorldLayout.FloorY(floor)
	local a, b, c, d = WorldLayout.BackWindowRect(size, Config.House.WallRatio)
	return { cx + a, cx + b, yFloor + c, yFloor + d }
end

local function backSide(ctx: Ctx, material: Enum.Material)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local T = WorldLayout.WALL_T
	local L, R = ctx.Left - T, ctx.Right + T
	local depth = ctx.Depth
	local out = depth + WorldLayout.BACK_WALL_OUT -- face extérieure
	-- (v10) cadres = couleur des boiseries (option "Trim")
	local frame = ctx.Trim
	local frameMat = if ctx.Spec.TrimMat == M.Metal then M.Metal else M.Wood
	local backX = WorldLayout.BackDoorX(ctx.Size)
	local W, H = WorldLayout.DOOR_W, WorldLayout.DOOR_H
	local backFills: { [number]: BasePart } = ctx.Built.BackFills or {}
	ctx.Built.BackFills = backFills
	for floor = 1, dims.Floors do
		local yFloor = WorldLayout.FloorY(floor)
		local y0 = if floor == 1 then 0 else yFloor - WorldLayout.SLAB
		local y1 = if floor == dims.Floors then ctx.Top else yFloor + WorldLayout.WALL_H
		local holes = {}
		local windows = {}
		for column = 1, dims.Columns do
			local r = HouseFacade.BackWindowRect(ctx.Size, column, floor)
			-- (trou de la façade 0,05 plus grand que celui de la coque : tranches jamais confondues)
			table.insert(holes, { r[1] - 0.05, r[2] + 0.05, r[3] - 0.05, r[4] + 0.05 })
			table.insert(windows, { r, (floor - 1) * dims.Columns + column })
		end
		if floor == 1 then
			table.insert(holes, { backX - W / 2, backX + W / 2, yFloor, yFloor + H })
		else
			-- fenêtre du palier (cage)
			local r = { backX - 2, backX + 2, yFloor + 3.2, yFloor + 9.4 }
			table.insert(holes, { r[1] - 0.05, r[2] + 0.05, r[3] - 0.05, r[4] + 0.05 })
			table.insert(windows, { r, nil })
		end
		-- (bandes pleines sous / sur les ouvertures + trumeaux : moins de pièces)
		local lo, hi = math.huge, -math.huge
		for _, h in ipairs(holes) do
			lo, hi = math.min(lo, h[3]), math.max(hi, h[4])
		end
		lo, hi = math.max(y0, lo), math.min(y1, hi)
		if lo > y0 + 0.05 then
			kit:Box("Back", L, R, y0, lo, depth - T + 0.05, out, ctx.Wall, material, { Solid = true })
		end
		if hi < y1 - 0.05 then
			kit:Box("Back", L, R, hi, y1, depth - T + 0.05, out, ctx.Wall, material, { Solid = true })
		end
		kit:WallX("Back", L, R, lo, hi, depth - T + 0.05, out, holes, ctx.Wall, material, { Solid = true })
		for _, w in ipairs(windows) do
			local r, slot = w[1], w[2]
			local x0, x1, wy0, wy1 = r[1], r[2], r[3], r[4]
			-- vitre (vraie, transparente) dans l'épaisseur du mur de la façade
			local glass = kit:Box("BackGlass", x0, x1, wy0, wy1, depth + 0.05, depth + 0.13, P.Glass, M.Glass, { T = 0.72, Shadow = false })
			glass.CastShadow = false
			addGlow(ctx, slot, windowGlow(glass, Enum.NormalId.Front)) -- (face côté jardin)
			-- cadre extérieur (déborde de 0,1 dans le trou) : linteau, 2 montants,
			-- appui (bas du cadre, qui avance), imposte (budget : 6 pièces par fenêtre)
			local f = 0.38
			kit:Box("BackFrame", x0 - f, x1 + f, wy1 - 0.1, wy1 + f, out - 0.2, out + 0.22, frame, frameMat)
			kit:Box("BackFrame", x0 - f, x0 + 0.1, wy0 + 0.1, wy1 - 0.1, out - 0.2, out + 0.22, frame, frameMat)
			kit:Box("BackFrame", x1 - 0.1, x1 + f, wy0 + 0.1, wy1 - 0.1, out - 0.2, out + 0.22, frame, frameMat)
			kit:Box("BackSill", x0 - 0.6, x1 + 0.6, wy0 - 0.45, wy0 + 0.1, depth + 0.16, out + 0.7, frame:Lerp(WHITE, 0.2), frameMat, { Shadow = false })
			local ym = wy0 + (wy1 - wy0) * 0.66
			kit:Box("BackMullion", x0 + 0.1, x1 - 0.1, ym - 0.1, ym + 0.1, depth + 0.13, depth + 0.33, frame, frameMat, { Shadow = false })
			-- pièce pas encore construite : rideaux tirés (masqués quand la pièce est là)
			if slot then
				local room = ctx.Looks.Rooms[slot]
				local fill = kit:Box("BackFill", x0 - 0.3, x1 + 0.3, wy0 - 0.3, wy1 + 0.3, depth - T - 1.6, depth - T - 1.45,
					if room then curtainColor(room) else Color3.fromRGB(236, 232, 242), M.Fabric, { Shadow = false })
				backFills[slot] = fill
			end
		end
	end
	-- Porte de derrière (double, s'ouvre vers le jardin) + imposte + lanterne
	local leafColor = if ctx.Style == "Loft" then P.Steel:Lerp(C.Mint, 0.35) else ctx.Wall:Lerp(C.PinkDeep, 0.35)
	HouseDetail.Phase(kit, "Openings")
	ctx.Built.BackLeaves = doorLeaves(ctx, backX, true, leafColor, frame, "Glazed")
	local yDoor = WorldLayout.FloorY(1)
	kit:Box("BackDoorHood", backX - W / 2 - 1.2, backX + W / 2 + 1.2, yDoor + H + 0.75, yDoor + H + 1.1, out, out + 2.2, frame, frameMat, { Shadow = false })
	for _, s in ipairs({ -1, 1 }) do
		kit:Slab("BackHoodBrace", backX + s * (W / 2 + 0.9), { yDoor + H - 0.9, out + 0.02 }, { yDoor + H + 0.75, out + 1.9 }, 0.18, 0.18, frame, frameMat, { Shadow = false })
		-- lanterne murale (sans vraie lumière : budget de la maison)
		local lx = backX + s * (W / 2 + 1.5)
		kit:Box("BackLanternArm", lx - 0.1, lx + 0.1, yDoor + 5.5, yDoor + 5.7, out, out + 0.7, C.Ink, M.Metal, { Shadow = false })
		kit:Box("BackLantern", lx - 0.35, lx + 0.35, yDoor + 4.2, yDoor + 5.5, out + 0.35, out + 1.05, P.Lamp, M.SmoothPlastic, { Shadow = false })
		kit:Box("BackLanternCap", lx - 0.45, lx + 0.45, yDoor + 5.5, yDoor + 5.8, out + 0.25, out + 1.15, C.Ink, M.Metal, { Shadow = false })
	end
	-- perron : palier + marches + rampe lisse invisible jusqu'à la pelouse
	local landing = WorldLayout.BACK_LANDING
	local steps = WorldLayout.BACK_STEPS
	local tread = WorldLayout.BACK_TREAD
	local px0, px1 = backX - W / 2 - 1.6, backX + W / 2 + 1.6
	local stone = if ctx.Style == "Loft" then Color3.fromRGB(226, 216, 232) else P.Stone
	kit:Box("BackPorch", px0, px1, 0, yDoor - 0.04, out, out + landing, stone, M.Limestone, { Solid = true })
	kit:Box("BackPorchEdge", px0 - 0.1, px1 + 0.1, yDoor - 0.3, yDoor - 0.02, out + landing - 0.35, out + landing + 0.1, frame:Lerp(WHITE, 0.3), M.Limestone, { Shadow = false })
	local rise = yDoor / steps
	for k = 1, steps - 1 do
		local top = yDoor - k * rise
		local d0 = out + landing + (k - 1) * tread
		kit:Box("BackStep", px0 + 0.3 + k * 0.2, px1 - 0.3 - k * 0.2, 0, top, d0 + 0.1, d0 + tread, stone:Lerp(WHITE, (k % 2) * 0.12), M.Limestone, { Shadow = false })
	end
	local run = (steps - 0.5) * tread
	local lawn = HouseKit.LAWN
	local slope = (yDoor - lawn) / run
	kit:Slab("BackRamp", backX, { yDoor, out + landing }, { lawn - 0.6 * slope, out + landing + run + 0.6 }, px1 - px0 - 0.8, 1, WHITE, M.SmoothPlastic,
		{ Solid = true, Query = true, T = 1, Shadow = false })
	-- deux pots fleuris sur le palier
	for _, s in ipairs({ -1, 1 }) do
		HouseGarden.PottedBall(kit:Sub(CFrame.new(0, yDoor - 0.04, 0)), backX + s * (W / 2 + 0.9), out + landing - 0.9, 0.8, if s < 0 then C.Pink else C.Lilac)
	end
end

-- Façade (une par étage, trous = fenêtres + porte), murs des bouts, mur du
-- fond, soubassement, dalle du toit. `holes[floor]` = { { x0, x1, y0, y1 } }
local function bodyWalls(ctx: Ctx, holes: { [number]: { { number } } }, plinthColor: Color3, plinthMaterial: Enum.Material)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local T = WorldLayout.WALL_T
	local L, R = ctx.Left - T, ctx.Right + T
	local material = ctx.WallMat
	-- soubassement (devant) + fondations pleines sous les pièces
	HouseDetail.Phase(kit, "Foundation")
	kit:WallX("Plinth", L - 0.3, R + 0.3, 0, WorldLayout.PLINTH, -0.6, T, {}, plinthColor, plinthMaterial, { Solid = true })
	kit:Box("Foundation", ctx.Left, ctx.Right, -0.05, WorldLayout.PLINTH, T, ctx.Depth - T, plinthColor:Lerp(BLACK, 0.1), M.Concrete, { Solid = true, Shadow = false })
	kit:Box("PlinthCap", L - 0.4, R + 0.4, WorldLayout.PLINTH - 0.25, WorldLayout.PLINTH + 0.1, -0.75, 0, ctx.Trim:Lerp(P.Stone, 0.5), M.Limestone, { Shadow = false })
	-- soupiraux (aération du vide sanitaire)
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		local cx = (x0 + x1) / 2
		kit:Box("Vent", cx - 0.8, cx + 0.8, 0.6, 1.2, -0.66, -0.58, Color3.fromRGB(70, 68, 72), M.Metal, { Shadow = false })
	end
	HouseDetail.Phase(kit, "Walls")
	for floor = 1, dims.Floors do
		local yFloor = WorldLayout.FloorY(floor)
		local y0 = if floor == 1 then WorldLayout.PLINTH else yFloor - WorldLayout.SLAB
		kit:WallX("Facade", L, R, y0, yFloor + WorldLayout.WALL_H, -0.3, T, holes[floor] or {}, ctx.Wall, material, { Solid = true })
	end
	-- bouts (à l'extérieur des colonnes) et fond (derrière les coques)
	-- (v9.6 : pieds 0,1 sous le sol : pas coplanaires avec le soubassement)
	kit:Box("EndLeft", L, ctx.Left, -0.1, ctx.Top, -0.3, ctx.Depth, ctx.Wall, material, { Solid = true })
	kit:Box("EndRight", ctx.Right, R, -0.1, ctx.Top, -0.3, ctx.Depth, ctx.Wall, material, { Solid = true })
	-- (v9.8 HOUSE98) mur du fond PERCÉ : une vraie fenêtre par pièce (côté
	-- jardin), une fenêtre de palier aux étages de la cage, la porte de derrière
	backSide(ctx, material)
	HouseDetail.Phase(kit, "Walls")
	-- dalle du toit (ferme la maison par le haut)
	-- (v9.6 : décalée de 0,05 : jamais coplanaire avec les plafonds des pièces du dernier étage)
	-- (et 0,05 en retrait sur les 4 côtés : jamais coplanaire avec les parapets du loft)
	kit:Box("TopSlab", L + 0.05, R - 0.05, ctx.Top + 0.05, ctx.Top + 0.65, -0.25, ctx.Depth + 0.25, ctx.Trim, M.SmoothPlastic, { Solid = true, Shadow = false })
end

----------------------------------------------------------------------
-- (v10) Fenêtres des pièces : DEUX vraies fenêtres par pièce (proportions
-- réelles), une grande baie d'usine au loft, une baie vitrée à la villa
----------------------------------------------------------------------

-- { largeur, bas (au-dessus du sol), hauteur, nombre }
local WINDOWS: { [string]: { number } } = {
	Cottage = { 5.6, 3.2, 6.6, 2 },
	Townhouse = { 5.2, 2.2, 7.4, 2 },
	Loft = { 0.7, 1.8, 7.2, 1 }, -- (1 seule : part de la largeur)
	Mansion = { 5.6, 2.4, 7, 2 },
	Chalet = { 5.4, 3, 6.4, 2 },
	Modern = { 0.66, 1.4, 8.6, 1 },
}

-- Trous des fenêtres d'une pièce (repère local) : { { x0, x1, y0, y1 }, ... }
-- (aussi utilisé par HouseBuilder pour le mur avant intérieur de la pièce)
function HouseFacade.WindowRects(size: any, column: number, floor: number, spec: any?): { { number } }
	local style = WorldLayout.StyleOf(size)
	local arch = type(spec) == "table" and spec.Arch or "Classic"
	local key = if arch == "Chalet" or arch == "Modern" then arch else style
	local w = WINDOWS[key] or WINDOWS.Cottage
	local x0, x1 = WorldLayout.ColumnSpan(size, column)
	local cx = (x0 + x1) / 2
	local roomW = x1 - x0 - 2 * WorldLayout.WALL_T
	local yFloor = WorldLayout.FloorY(floor)
	local y0, y1 = yFloor + w[2], yFloor + w[2] + w[3]
	if w[4] == 1 then
		local width = math.clamp(roomW * w[1], 7, 26)
		return { { cx - width / 2, cx + width / 2, y0, y1 } }
	end
	local off = roomW * 0.24
	return {
		{ cx - off - w[1] / 2, cx - off + w[1] / 2, y0, y1 },
		{ cx + off - w[1] / 2, cx + off + w[1] / 2, y0, y1 },
	}
end

-- (compat) 1re fenêtre d'une pièce
function HouseFacade.WindowRect(size: any, column: number, floor: number): { number }
	return HouseFacade.WindowRects(size, column, floor, nil)[1]
end

type Opening = { Rect: { number }, Slot: number?, Floor: number }

-- Trous de la façade avant : fenêtres des pièces + ouvertures de la cage
-- (porte au rez-de-chaussée ; `hallWindow(floor)` = fenêtre de palier ou nil)
local function openings(ctx: Ctx, hallWindow: (floor: number) -> { number }?): ({ [number]: { { number } } }, { Opening }, { { number } })
	local dims = ctx.Dims
	local holes: { [number]: { { number } } } = {}
	local list: { Opening } = {}
	local hallHoles: { { number } } = {}
	for floor = 1, dims.Floors do
		holes[floor] = {}
		for column = 1, dims.Columns do
			local slot = (floor - 1) * dims.Columns + column
			for _, r in ipairs(HouseFacade.WindowRects(ctx.Size, column, floor, ctx.Spec)) do
				table.insert(holes[floor], r)
				table.insert(list, { Rect = r, Slot = slot, Floor = floor })
			end
		end
		local yFloor = WorldLayout.FloorY(floor)
		if floor == 1 then
			local r = { ctx.DoorX - WorldLayout.DOOR_W / 2, ctx.DoorX + WorldLayout.DOOR_W / 2, yFloor, yFloor + WorldLayout.DOOR_H }
			table.insert(holes[floor], r)
			table.insert(hallHoles, r)
		else
			local r = hallWindow(floor)
			if r then
				table.insert(holes[floor], r)
				table.insert(hallHoles, r)
				table.insert(list, { Rect = r, Slot = nil, Floor = floor })
			end
		end
	end
	return holes, list, hallHoles
end

-- Place libre (volets) à gauche / à droite d'une ouverture : jusqu'aux
-- ouvertures voisines et aux bords des colonnes (pilastres, colombages...)
local function sideRoom(ctx: Ctx, list: { Opening }, o: Opening): number
	local r = o.Rect
	local left, right = math.huge, math.huge
	for _, other in ipairs(list) do
		if other ~= o and other.Floor == o.Floor then
			local q = other.Rect
			if q[2] <= r[1] then
				left = math.min(left, (r[1] - q[2]) / 2)
			elseif q[1] >= r[2] then
				right = math.min(right, (q[1] - r[2]) / 2)
			end
		end
	end
	local edges = { ctx.Left - WorldLayout.WALL_T, ctx.Right + WorldLayout.WALL_T, ctx.Hall0, ctx.Hall1 + WorldLayout.WALL_T }
	for column = 1, ctx.Dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		table.insert(edges, x0)
		table.insert(edges, x1)
	end
	for _, e in ipairs(edges) do
		if e <= r[1] then
			left = math.min(left, r[1] - e - 1.2)
		elseif e >= r[2] then
			right = math.min(right, e - r[2] - 1.2)
		end
	end
	return math.min(left, right) - 0.5
end

-- Vitres + décor des fenêtres + "lueur" des pièces pas encore construites
local function frontWindows(ctx: Ctx, list: { Opening }, frame: Color3, frameMat: Enum.Material, opts: { [string]: any }?)
	local kit = ctx.Kit
	local o = opts or {}
	local spec = ctx.Spec
	local bySlot: { [number]: { { number } } } = {}
	HouseDetail.Phase(kit, "Openings")
	for _, op in ipairs(list) do
		local r = op.Rect
		local x0, x1, y0, y1 = r[1], r[2], r[3], r[4]
		local glass = kit:Box("Glass", x0, x1, y0, y1, 0.35, 0.5, P.Glass, M.Glass, { T = 0.72, Shadow = false })
		glass.CastShadow = false
		addGlow(ctx, op.Slot, windowGlow(glass, Enum.NormalId.Back)) -- (face côté rue)
		local isHall = op.Slot == nil
		local style = if isHall and o.HallStyle then o.HallStyle else spec.Window
		local arched = style == "Tall" or style == "Arched"
		HouseDetail.Window(kit, x0, x1, y0, y1, {
			Style = style,
			Frame = frame,
			FrameMat = frameMat,
			Sill = o.Sill,
			SillMat = o.SillMat,
			Lintel = o.Lintel,
			LintelColor = o.LintelColor,
			Shutters = if isHall and not o.HallShutters then "None" else spec.Shutters,
			ShutterColor = spec.ShutterColor,
			ShutterRoom = sideRoom(ctx, list, op),
			Arch = if arched and not o.NoArch then function(a: number, b: number, top: number)
				archTop(ctx, a, b, top, frame, o.ArchMax)
			end else nil,
			FlowerBox = if o.FlowerBox and (not isHall or o.HallFlowerBox) then o.FlowerBox else nil,
		})
		if op.Slot then
			local set = bySlot[op.Slot]
			if not set then
				set = {}
				bySlot[op.Slot] = set
			end
			table.insert(set, r)
		end
	end
	-- lueur de la pièce (masquée quand la pièce est construite) : une seule
	-- plaque derrière toutes les fenêtres de la pièce
	for slot, rects in pairs(bySlot) do
		local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
		for _, r in ipairs(rects) do
			x0, x1 = math.min(x0, r[1]), math.max(x1, r[2])
			y0, y1 = math.min(y0, r[3]), math.max(y1, r[4])
		end
		local room = ctx.Looks.Rooms[slot]
		local fill = kit:Box("Fill", x0 - 0.4, x1 + 0.4, y0 - 0.4, y1 + 0.4, 1.4, 1.6, if room then curtainColor(room) else Color3.fromRGB(236, 232, 242), M.Fabric,
			{ Shadow = false })
		ctx.Built.Fills[slot] = fill
	end
end

----------------------------------------------------------------------
-- (v10) Toit principal, cheminées, lucarnes (selon l'option de forme)
----------------------------------------------------------------------

local function mainRoof(ctx: Ctx, x0: number, x1: number, o: { [string]: any }): HouseDetail.RoofInfo
	local spec = ctx.Spec
	HouseDetail.Phase(ctx.Kit, "Roof")
	local info = HouseDetail.Roof(ctx.Kit, x0, x1, -0.3, ctx.Depth + WorldLayout.BACK_WALL_OUT, ctx.Top + 0.65, {
		Shape = spec.RoofShape,
		Color = ctx.Roof,
		Dark = ctx.RoofDark,
		Material = spec.RoofMat,
		Kind = spec.RoofKind,
		Over = o.Over,
		Pitch = o.Pitch,
		Rise = if spec.RoofShape == "Mansard" then o.MansardRise else nil,
		Inset = o.Inset,
		Fascia = o.Fascia or ctx.Trim,
		Wall = ctx.Wall,
		WallMat = ctx.WallMat,
		Detail = true,
		Pipes = o.Pipes,
		Parapet = spec.Parapet,
		Eaves = o.Eaves,
	} :: any)
	if spec.RoofShape ~= "Flat" then
		local band = HouseDetail.PatternBand(ctx.Kit, info, ctx.Roof, spec.RoofMat)
		if band then
			roofPattern(ctx, band, ctx.Looks.Pattern or "None")
		end
	end
	return info
end

-- Cheminée posée sur le toit (x, d) ; smoke = fumée
local function roofChimney(ctx: Ctx, info: HouseDetail.RoofInfo, x: number, d: number, smoke: boolean)
	local kind = ctx.Spec.Chimney
	if kind == "None" then
		return
	end
	HouseDetail.Phase(ctx.Kit, "Roof")
	local surface = info.Surface(x, d)
	local yTop = math.max(info.Ridge + 2.2, surface + 3.2)
	if info.Shape == "Flat" then
		yTop = info.Ridge + 3.5
	end
	local top = HouseDetail.Chimney(ctx.Kit, kind, x, d, ctx.Top + 0.7, yTop, if kind == "Brick" then ctx.Spec.ChimneyColor else nil)
	if smoke then
		HouseDetail.Smoke(ctx.Kit, x, top, d)
	end
	ctx.Built.Chimneys += 1
	ctx.Built.ChimneysExpected = (ctx.Built.ChimneysExpected or 0) + 1
end

-- Lucarne sur le pan avant (sauf toit-terrasse)
local function roofDormer(ctx: Ctx, info: HouseDetail.RoofInfo, x: number, w: number, h: number, round: boolean, k: number?)
	if info.Shape == "Flat" then
		return
	end
	HouseDetail.Phase(ctx.Kit, "Roof")
	local e0 = info.D0 - (if info.Shape == "Mansard" then 0.7 else info.Over)
	local top = if info.Shape == "Mansard" then info.D0 + 4.8 else (info.D0 + info.D1) / 2
	local d = e0 + (k or 0.3) * (top - e0)
	local y = info.Surface(x, d)
	dormer(ctx, x, y - 1.1, d - 0.4, w, h, round)
end

----------------------------------------------------------------------
-- (v10) Jardin de devant : clôture + portillon, allée, boîte aux lettres,
-- numéro, luminaires, garage attenant
----------------------------------------------------------------------

local FENCE_D = -21

local function gardenFront(ctx: Ctx, fence0: number, fence1: number, gateX: number, pathPoints: { { number } }, pathW: number)
	local spec = ctx.Spec
	HouseDetail.Phase(ctx.Kit, "Garden")
	local right = fence1
	if ctx.SideGarage then
		right = math.min(right, ctx.Right + WorldLayout.WALL_T + 1.2)
	end
	HouseDetail.Fence(ctx.G, fence0, right, FENCE_D, { Kind = spec.Fence, Gate0 = gateX - 2.2, Gate1 = gateX + 2.2 })
	HouseDetail.Path(ctx.G, pathPoints, pathW, spec.Path)
	-- boîte aux lettres : côté rue, à gauche du portillon
	if spec.Mailbox ~= "Wall" then
		HouseDetail.Mailbox(ctx.G, spec.Mailbox, gateX - 4.4, FENCE_D - 1.6, spec.MailColor, spec.Num)
	end
end

-- Numéro près de la porte + luminaires de l'entrée (option "Lights")
local function entranceLights(ctx: Ctx, yDoor: number, faceD: number, numberSide: number?)
	local spec = ctx.Spec
	local kit = ctx.Kit
	local gx = ctx.DoorX
	local side = numberSide or 1
	HouseDetail.Phase(kit, "Openings")
	local lx = gx + side * (WorldLayout.DOOR_W / 2 + 1.5)
	local kind = spec.Lights
	if kind == "Lanterns" or kind == "String" then
		wallLantern(ctx, lx, yDoor + 4.2, true)
	elseif kind == "Sconces" or kind == "Bollards" then
		HouseDetail.Sconce(kit, gx - (WorldLayout.DOOR_W / 2 + 1.4), yDoor + 6, faceD, true)
		HouseDetail.Sconce(kit, gx + (WorldLayout.DOOR_W / 2 + 1.4), yDoor + 6, faceD, false)
	end
	-- plaque du numéro (au-dessus de la lanterne) ; boîte aux lettres murale
	HouseDetail.NumberPlate(kit, lx, yDoor + 7.7, faceD, spec.Num, spec.Arch == "Modern")
	if spec.Mailbox == "Wall" then
		local mx = gx - side * (WorldLayout.DOOR_W / 2 + 1.6)
		local box = kit:Box("MailBox", mx - 0.8, mx + 0.8, yDoor + 3.2, yDoor + 4.8, faceD - 0.6, faceD - 0.02, spec.MailColor, M.Metal, { Shadow = false })
		kit:Box("MailSlot", mx - 0.55, mx + 0.55, yDoor + 4.3, yDoor + 4.42, faceD - 0.64, faceD - 0.58, Color3.fromRGB(30, 26, 30), M.Metal, { Shadow = false })
		local _ = box
	end
end

-- Luminaires de jardin (bornes / guirlande) le long de l'allée
local function gardenLights(ctx: Ctx, pathPoints: { { number } })
	local spec = ctx.Spec
	HouseDetail.Phase(ctx.Kit, "Garden")
	if spec.Lights == "Bollards" then
		local a, b = pathPoints[1], pathPoints[#pathPoints]
		for k = 0, 2 do
			local t = (k + 0.5) / 3
			local x = a[1] + (b[1] - a[1]) * t
			local d = a[2] + (b[2] - a[2]) * t
			for _, s in ipairs({ -1, 1 }) do
				HouseDetail.Bollard(ctx.G, x + s * 2.6, d, k == 1 and s > 0)
			end
		end
	elseif spec.Lights == "String" then
		local gx = ctx.DoorX
		for _, s in ipairs({ -1, 1 }) do
			ctx.G:CylY("LightPole", gx + s * 7, 0, -12, 0.3, 8, Color3.fromRGB(70, 60, 56), M.Wood, { Shadow = false })
		end
		HouseDetail.StringLights(ctx.G, { gx - 7, 7.8, -12 }, { gx + 7, 7.8, -12 }, 10, 1.2)
		HouseDetail.StringLights(ctx.G, { gx - 7, 7.8, -12 }, { gx - 5, WorldLayout.FloorY(1) + 10, -0.6 }, 6, 0.6)
	end
end

-- Garage / abri attenant (à droite de la maison), allée carrossable jusqu'à la rue
local function sideGarage(ctx: Ctx)
	if not ctx.SideGarage then
		return
	end
	HouseDetail.Phase(ctx.Kit, "Walls")
	local x0 = ctx.Right + WorldLayout.WALL_T + 0.05
	local x1 = x0 + 17
	HouseDetail.Garage(ctx.Kit, x0, x1, 1.2, 21, {
		Kind = ctx.Spec.Garage,
		Wall = ctx.Wall,
		WallMat = ctx.WallMat,
		Trim = ctx.Trim,
		Roof = ctx.Roof,
		RoofMat = ctx.Spec.RoofMat,
		Door = ctx.Trim:Lerp(WHITE, 0.5),
	})
	HouseDetail.Phase(ctx.Kit, "Garden")
	ctx.G:Box("Driveway", x0 + 1.5, x1 - 1.5, -0.1, 0.1, -29.5, 1.1, Color3.fromRGB(196, 192, 188), M.Pavement, { Shadow = false })
	for _, x in ipairs({ x0 + 1.2, x1 - 1.2 }) do
		ctx.G:Box("DrivewayEdge", x - 0.3, x + 0.3, -0.1, 0.16, -29.5, 1.1, Color3.fromRGB(170, 166, 162), M.Concrete, { Shadow = false })
	end
end

----------------------------------------------------------------------
-- Styles
----------------------------------------------------------------------

local STYLES: { [string]: (ctx: Ctx) -> () } = {}

-- ░░ Cottage : chaumière de conte ░░
STYLES.Cottage = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local spec = ctx.Spec
	local TIMBER = Color3.fromRGB(150, 104, 72)
	local T = WorldLayout.WALL_T
	local holes, list, hallHoles = openings(ctx, function(floor)
		local yFloor = WorldLayout.FloorY(floor)
		return { ctx.DoorX - 2.2, ctx.DoorX + 2.2, yFloor + 3.5, yFloor + 8.5 }
	end)
	bodyWalls(ctx, holes, P.Stone, M.Cobblestone)
	-- porche (travée de la cage) : enduit rosé devant la façade
	-- (v9.8 HOUSE98 : la travée de l'entrée monte de ANNEX_RAISE au-dessus du
	-- toit des pièces : grande porte + imposte + plaque au nom SOUS son pignon)
	local ANNEX_RAISE = 2.6
	local annex = ctx.Wall:Lerp(C.Pink, 0.1)
	local annexTop = ctx.Top + 0.6 + ANNEX_RAISE
	kit:WallX("AnnexSkin", ctx.Hall0 + 0.3, ctx.Hall1 + T - 0.3, WorldLayout.PLINTH, annexTop, -0.36, -0.3, hallHoles, annex, ctx.WallMat, { Shadow = false })
	kit:Box("AnnexUpper", ctx.Hall0, ctx.Hall1 + T, ctx.Top + 0.4, annexTop, -0.3, ctx.Depth + WorldLayout.BACK_WALL_OUT, annex, ctx.WallMat, { Solid = true })
	frontWindows(ctx, list, ctx.Trim, M.Wood, { FlowerBox = C.WoodDark, Sill = P.Stone, Lintel = if ctx.WallMat == M.Brick then "Brick" else nil })
	-- colombages : poteaux, sablières, écharpes (croix de Saint-André) aux bouts
	HouseDetail.Phase(kit, "Walls")
	local posts = { ctx.Left - T, ctx.Right + T }
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		table.insert(posts, x0)
		table.insert(posts, x1)
	end
	table.sort(posts)
	local last = -math.huge
	for _, x in ipairs(posts) do
		if x - last > 1.5 then
			local postTop = if x > ctx.Hall0 + 1 then annexTop - 0.35 else ctx.Top
			kit:Box("Timber", x - 0.5, x + 0.5, WorldLayout.PLINTH, postTop, -0.62, -0.3, TIMBER, M.Wood, { Shadow = false })
			last = x
		end
	end
	kit:Box("Beam", ctx.Left - T - 0.3, ctx.Hall0 + 0.45, ctx.Top - 1, ctx.Top + 0.05, -0.66, -0.3, TIMBER, M.Wood, { Shadow = false })
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor) - WorldLayout.SLAB
		kit:Box("Beam", ctx.Left - T - 0.3, ctx.Right + T + 0.3, y - 0.3, y + 0.75, -0.66, -0.3, TIMBER, M.Wood, { Shadow = false })
	end
	kit:Box("Beam", ctx.Left - T - 0.3, ctx.Right + T + 0.3, WorldLayout.PLINTH - 0.1, WorldLayout.PLINTH + 0.5, -0.7, -0.3, TIMBER, M.Wood, { Shadow = false })
	-- écharpes entre les fenêtres (panneaux pleins du milieu de chaque pièce)
	for _, floor in ipairs({ 1 }) do
		for column = 1, dims.Columns do
			local rects = HouseFacade.WindowRects(ctx.Size, column, floor, spec)
			if #rects == 2 then
				local a, b = rects[1][2] + 0.9, rects[2][1] - 0.9
				local y0, y1 = WorldLayout.PLINTH + 0.5, ctx.Top - 1
				if b - a > 2 then
					HouseDetail.Rod(kit, "Brace", { a, y0, -0.46 }, { b, y1, -0.46 }, 0.6, 0.3, TIMBER, M.Wood, { Shadow = false }, Vector3.new(0, 0, 1))
					HouseDetail.Rod(kit, "Brace", { b, y0, -0.47 }, { a, y1, -0.47 }, 0.6, 0.3, TIMBER, M.Wood, { Shadow = false }, Vector3.new(0, 0, 1))
				end
			end
		end
	end
	-- toit des pièces (croupe de tuiles par défaut)
	local roofX0, roofX1 = ctx.Left - T, ctx.Hall0 + 0.4
	local info = mainRoof(ctx, roofX0, roofX1, { Over = 1.8, Pitch = 0.78, Hip = 10, Pipes = { roofX0 + 1.4, roofX1 - 1.2 }, MansardRise = 8.5 })
	local roomsX = (WorldLayout.ColumnSpan(ctx.Size, 1) + select(2, WorldLayout.ColumnSpan(ctx.Size, dims.Columns))) / 2
	roofDormer(ctx, info, roomsX, 5, 5, true, 0.32)
	roofChimney(ctx, info, roomsX + (roofX1 - roofX0) * 0.28, ctx.Depth / 2 + 1.6, true)
	if info.Shape ~= "Flat" then
		-- chat assis sur le pan gauche
		local cx = roomsX - (ctx.Right - ctx.Left) * 0.26
		local cd = info.D0 - info.Over + 0.55 * ((info.D0 + info.D1) / 2 - info.D0 + info.Over)
		HouseGarden.Cat(kit, cx, info.Surface(cx, cd) + 0.2, cd - 0.3)
	end
	-- porche (cage) : son propre pignon face à la rue, œil-de-bœuf
	local gx = ctx.DoorX
	local hx0, hx1 = ctx.Hall0, ctx.Hall1 + T
	local hcx = (hx0 + hx1) / 2
	local hRise = 5.5
	local yEave = annexTop
	HouseDetail.Phase(kit, "Roof")
	for _, s in ipairs({ -1, 1 }) do
		local edge = if s < 0 then hx0 - 0.9 else hx1 + 0.9
		kit:SlabX("PorchRoof", ctx.Depth / 2 - 0.5, { edge, yEave - 0.9 * hRise / ((hx1 - hx0) / 2) }, { hcx, yEave + hRise }, ctx.Depth + 2.4, 0.6, ctx.Roof, spec.RoofMat,
			{ Solid = true, Shadow = true })
		kit:Part("PorchGable", Vector3.new(1, hRise, (hx1 - hx0) / 2), CFrame.new(hcx + s * (hx1 - hx0) / 4, yEave + hRise / 2 - 0.3, 0.2) * CFrame.Angles(0, -s * math.pi / 2, 0),
			annex, ctx.WallMat, { Solid = true }, "WedgePart")
		kit:Part("PorchGable", Vector3.new(1, hRise, (hx1 - hx0) / 2), CFrame.new(hcx + s * (hx1 - hx0) / 4, yEave + hRise / 2 - 0.3, -(ctx.Depth - 0.2)) * CFrame.Angles(0, -s * math.pi / 2, 0),
			annex, ctx.WallMat, { Solid = true }, "WedgePart")
		kit:SlabX("PorchBarge", -1.6, { edge - 0.1, yEave - 0.9 * hRise / ((hx1 - hx0) / 2) + 0.3 }, { hcx, yEave + hRise + 0.35 }, 0.5, 0.9, TIMBER, M.Wood,
			{ Shadow = false })
	end
	kit:CylX("PorchGutter", hcx, yEave - 0.9, -1.5, 0.5, hx1 - hx0 + 1.4, Color3.fromRGB(226, 228, 232), M.Metal, { Shadow = false })
	kit:CylD("GableWindowRing", hcx, yEave + hRise * 0.42, -0.35, 2.6, 0.3, C.Cream, M.Wood, { Shadow = false })
	kit:CylD("GableWindow", hcx, yEave + hRise * 0.42, -0.52, 1.9, 0.1, P.Glass, M.Glass, { Shadow = false })
	heart(ctx, hcx, yEave + hRise + 1.1, -0.6, 1.1, C.Heart)
	-- porte double + imposte cintrée ; plaque au nom sous le pignon
	HouseDetail.Phase(kit, "Openings")
	local yTopDoor = WorldLayout.FloorY(1) + WorldLayout.DOOR_H
	frontDoor(ctx)
	archTop(ctx, gx - WorldLayout.DOOR_W / 2, gx + WorldLayout.DOOR_W / 2, yTopDoor + 0.6, TIMBER, 1.5)
	porchCover(ctx, if spec.Porch == "Hood" then "None" else spec.Porch, yTopDoor + 1.2, yTopDoor + 2.35, 3.2)
	entranceLights(ctx, WorldLayout.FloorY(1), -0.36, 1)
	HouseDetail.Phase(kit, "Foundation")
	local foot = porch(ctx, gx - 5, gx + 5, 3.2, 3, P.StoneDark, M.Slate)
	HouseDetail.Phase(kit, "Openings")
	namePlate(ctx, gx, yTopDoor + 2.45, -0.36, 6.4)
	-- jardin : pommier, buissons, fleurs, allée, clôture
	HouseDetail.Phase(kit, "Garden")
	tree(ctx, ctx.Left - 9, 6, 1.2, C.Pink)
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		bush(ctx, x0 + 3, -2.2, 3.4, 2.4, P.Leaf)
		bush(ctx, x1 - 3, -2.2, 3, 2.2, if column % 2 == 0 then C.Pink:Lerp(P.Leaf, 0.5) else P.Leaf)
		flowerDots(ctx, x0 + 5, x1 - 5, -1.8, 6)
	end
	sideGarage(ctx)
	local gateX = 0
	local pathPoints = { { gateX, -21.5 }, { gateX * 0.5 + gx * 0.5, -13 }, { gx, foot - 1.2 } }
	gardenFront(ctx, ctx.Left - 4, ctx.Right + 4, gateX, pathPoints, 3)
	HouseDetail.Path(ctx.G, { { gateX, -29.5 }, { gateX, -21.6 } }, 3, if spec.Path == "Stones" then "Gravel" else spec.Path)
	gardenLights(ctx, pathPoints)
	flowerDots(ctx, ctx.Left - 3, gateX - 6, -20, 10)
	flowerDots(ctx, gateX + 3, ctx.Right + 3, -20, 10)
end

-- ░░ Townhouse : maison de ville pastel ░░
STYLES.Townhouse = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local spec = ctx.Spec
	local T = WorldLayout.WALL_T
	local TRIM = ctx.Trim
	-- (v9.8 : fenêtre du palier un peu plus haute : la plaque au nom tient au-dessus de la grande porte)
	local holes, list, hallHoles = openings(ctx, function(floor)
		local yFloor = WorldLayout.FloorY(floor)
		return { ctx.DoorX - 1.9, ctx.DoorX + 1.9, yFloor + 4, yFloor + 9.2 }
	end)
	bodyWalls(ctx, holes, P.Stone, M.Limestone)
	kit:WallX("AnnexSkin", ctx.Hall0 + 0.4, ctx.Hall1 + T - 0.4, WorldLayout.PLINTH, ctx.Top, -0.36, -0.3, hallHoles, ctx.Wall:Lerp(C.Sky, 0.2), ctx.WallMat, { Shadow = false })
	frontWindows(ctx, list, TRIM, M.Wood, { Sill = TRIM:Lerp(P.Stone, 0.4), HallFlowerBox = true, FlowerBox = nil, Lintel = if ctx.WallMat == M.Brick then "Stone" else nil })
	-- chaînes d'angle + pilastres entre les pièces
	HouseDetail.Phase(kit, "Walls")
	for _, x in ipairs({ ctx.Left - T, ctx.Right + T }) do
		local y = WorldLayout.PLINTH + 0.4
		local index = 0
		while y < ctx.Top - 1.2 do
			local w = if index % 2 == 0 then 2 else 1.3
			local x0 = if x < 0 then x else x - w
			kit:Box("Quoin", x0, x0 + w, y, y + 1.05, -0.55, -0.3, WHITE:Lerp(TRIM, 0.5), M.Limestone, { Shadow = false })
			y += 1.45
			index += 1
		end
	end
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		for _, x in ipairs({ x0, x1 }) do
			kit:Box("Pilaster", x - 0.6, x + 0.6, WorldLayout.PLINTH, ctx.Top, -0.65, -0.3, TRIM, M.Plaster, { Shadow = false })
		end
	end
	-- corniche + modillons
	kit:Box("Cornice", ctx.Left - T - 0.9, ctx.Right + T + 0.9, ctx.Top - 0.2, ctx.Top + 1.1, -1.3, 0, TRIM, M.Plaster)
	kit:Box("CorniceLine", ctx.Left - T - 0.6, ctx.Right + T + 0.6, ctx.Top + 0.45, ctx.Top + 0.65, -1.35, -1.25, TRIM:Lerp(BLACK, 0.12), M.SmoothPlastic, { Shadow = false })
	local modCount = math.floor((ctx.Right - ctx.Left) / 2.6)
	for k = 0, modCount do
		local x = ctx.Left + k * (ctx.Right - ctx.Left) / modCount
		kit:Box("Modillion", x - 0.3, x + 0.3, ctx.Top - 0.8, ctx.Top - 0.2, -0.9, -0.3, TRIM, M.Plaster, { Shadow = false })
	end
	-- bandeaux + balcons (à la française, un par fenêtre) aux étages
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor)
		kit:Box("Band", ctx.Left - T - 0.4, ctx.Right + T + 0.4, y - 1.3, y - 0.2, -0.7, -0.3, TRIM, M.Plaster, { Shadow = false })
		HouseDetail.Phase(kit, "Openings")
		for column = 1, dims.Columns do
			for _, r in ipairs(HouseFacade.WindowRects(ctx.Size, column, floor, spec)) do
				HouseDetail.Balcony(kit, if spec.Balcony == "Stone" then "Stone" else spec.Balcony, r[1] - 0.7, r[2] + 0.7, y, 1.5, -0.3, TRIM)
			end
		end
		HouseDetail.Phase(kit, "Walls")
	end
	-- toit (mansarde d'ardoises par défaut) + lucarnes + crête + cheminées
	local r0, r1 = ctx.Left - T, ctx.Hall0 + 0.4
	local info = mainRoof(ctx, r0, r1, { Over = 1.2, Pitch = 0.7, MansardRise = 8.5 + (dims.Floors - 1) * 0.5, Inset = 4.6, Eaves = false })
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		roofDormer(ctx, info, (x0 + x1) / 2, 4.6, 5.2, false, 0.2)
	end
	if info.Shape == "Mansard" then
		HouseDetail.Phase(kit, "Roof")
		local crest = math.max(2, math.floor((r1 - r0 - 2 * 4.6) / 5))
		for k = 0, crest do
			local x = r0 + 4.6 + k * (r1 - r0 - 2 * 4.6) / crest
			kit:Box("CrestPost", x - 0.1, x + 0.1, info.Ridge, info.Ridge + 1.4, 4.14, 4.46, HouseDetail.IRON, M.Metal, { Shadow = false })
			kit:Ball("CrestBall", x, info.Ridge + 1.5, 4.3, 0.4, P.Gold, M.Metal, { Shadow = false })
		end
	end
	local span = r1 - r0
	for _, s in ipairs({ -1, 1 }) do
		roofChimney(ctx, info, (r0 + r1) / 2 + s * span * 0.36, ctx.Depth * 0.55, s > 0)
	end
	-- toit plat de l'entrée : garde-corps + plante
	HouseDetail.Phase(kit, "Roof")
	local hx0, hx1 = ctx.Hall0 + 0.6, ctx.Hall1 + T
	local yr = ctx.Top + 1.1
	kit:Box("AnnexRail", hx0, hx1, yr + 2.2, yr + 2.45, -1.1, -0.9, WHITE, M.Metal, { Shadow = false })
	kit:Box("AnnexRail", hx1 - 0.2, hx1, yr + 2.2, yr + 2.45, -1.1, ctx.Depth, WHITE, M.Metal, { Shadow = false })
	for k = 0, 6 do
		local x = hx0 + k * (hx1 - hx0) / 6
		kit:Box("AnnexBar", x - 0.07, x + 0.07, yr, yr + 2.2, -1.05, -0.95, WHITE, M.Metal, { Shadow = false })
	end
	HouseGarden.PottedBall(kit:Sub(CFrame.new(0, yr, 0)), hx1 - 2, 1.5, 0.8, C.Peach)
	-- entrée : porte à imposte, pilastres, perron, lanterne, plaque au nom
	HouseDetail.Phase(kit, "Openings")
	local gx = ctx.DoorX
	local yDoor = WorldLayout.FloorY(1)
	local yTopDoor = yDoor + WorldLayout.DOOR_H
	frontDoor(ctx)
	archTop(ctx, gx - WorldLayout.DOOR_W / 2, gx + WorldLayout.DOOR_W / 2, yTopDoor + 0.6, TRIM, 1.3)
	local pilX = WorldLayout.DOOR_W / 2 + 0.95
	local bandY = WorldLayout.FloorY(2) - 1.3
	for _, s in ipairs({ -1, 1 }) do
		kit:Box("DoorPilaster", gx + s * pilX - 0.45, gx + s * pilX + 0.45, yDoor, bandY, -0.72, -0.36, TRIM, M.Plaster, { Shadow = false })
		kit:Box("DoorPilasterCap", gx + s * pilX - 0.6, gx + s * pilX + 0.6, bandY - 0.45, bandY, -0.8, -0.36, TRIM:Lerp(P.Stone, 0.2), M.Limestone, { Shadow = false })
	end
	porchCover(ctx, spec.Porch, yTopDoor + 1.9, bandY, 3)
	entranceLights(ctx, yDoor + 0.8, -0.72, 1)
	HouseDetail.Phase(kit, "Foundation")
	local foot = porch(ctx, gx - 5, gx + 5, 3, 3, P.Stone, M.Limestone)
	HouseDetail.Phase(kit, "Openings")
	local plateY = bandY + 1.4
	namePlate(ctx, gx, plateY, -0.36, 6.4)
	kit:Box("NamePlateCornice", gx - 3.9, gx + 3.9, plateY + PLATE_H + 0.32, plateY + PLATE_H + 0.58, -0.8, -0.36, TRIM, M.Limestone, { Shadow = false })
	-- trottoir, lampadaire, vélo, allée, jardinet
	HouseDetail.Phase(kit, "Garden")
	for _, s in ipairs({ -1, 1 }) do
		HouseGarden.PottedBall(ctx.G, gx + s * 6.3, -1.3, 1, C.Lilac)
	end
	ctx.G:Box("Sidewalk", ctx.Left - 6, ctx.Right + 6, -0.1, 0.12, -6, -0.6, P.Pave, M.Pavement, { Shadow = false })
	if spec.Lights == "Lanterns" then
		postLantern(ctx, ctx.Left + 3, -5, 0, 8, false, ctx.G)
	end
	HouseGarden.Bike(ctx.G, ctx.Left + 7, -4.2, C.Mint:Lerp(C.Sky, 0.3))
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		bush(ctx, (x0 + x1) / 2, -7.3, 5, 2, P.Leaf)
	end
	sideGarage(ctx)
	local pathPoints = { { 0, -21.5 }, { 0, -8 }, { gx, -8 }, { gx, foot } }
	gardenFront(ctx, ctx.Left - 4, ctx.Right + 4, 0, pathPoints, 3.2)
	HouseDetail.Path(ctx.G, { { 0, -29.5 }, { 0, -21.6 } }, 3.2, spec.Path)
	gardenLights(ctx, { { 0, -21 }, { 0, -9 } })
end

-- ░░ Loft : entrepôt de briques reconverti ░░
STYLES.Loft = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local spec = ctx.Spec
	local T = WorldLayout.WALL_T
	local steel = ctx.Trim
	local holes, list = openings(ctx, function(floor)
		local yFloor = WorldLayout.FloorY(floor)
		-- verrière d'atelier (travée de droite)
		return { ctx.DoorX - 3, ctx.DoorX + 3, yFloor + 1.5, yFloor + 10.5 }
	end)
	bodyWalls(ctx, holes, Color3.fromRGB(214, 208, 204), M.Concrete)
	frontWindows(ctx, list, steel, M.Metal, { HallStyle = "Industrial", Sill = Color3.fromRGB(214, 208, 200), Lintel = if ctx.WallMat == M.Brick then "Brick" else nil,
		LintelColor = ctx.Wall:Lerp(BLACK, 0.12) })
	-- imposte : rangée de petits carreaux au-dessus des grandes baies
	for _, op in ipairs(list) do
		local r = op.Rect
		if op.Slot and spec.Window == "Industrial" then
			local ty = r[4] + 1.05
			kit:Box("Transom", r[1] + 0.3, r[2] - 0.3, ty, ty + 1.4, -0.5, -0.3, steel, M.Metal, { Shadow = false })
			local n = 6
			for k = 0, n - 1 do
				local x = r[1] + 0.6 + (k + 0.5) * (r[2] - r[1] - 1.2) / n
				kit:Box("TransomPane", x - (r[2] - r[1] - 1.2) / n / 2 + 0.15, x + (r[2] - r[1] - 1.2) / n / 2 - 0.15, ty + 0.25, ty + 1.15, -0.56, -0.5, P.Glass, M.Glass,
					{ Shadow = false })
			end
		end
	end
	-- poutres d'acier entre les étages + tirants (ancres en X)
	HouseDetail.Phase(kit, "Walls")
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor) - WorldLayout.SLAB
		kit:Box("SteelBeam", ctx.Left - T - 0.3, ctx.Right + T + 0.3, y - 0.2, y + 1.1, -0.8, -0.3, steel, M.Metal)
		for column = 1, dims.Columns + 1 do
			local x = if column <= dims.Columns then (WorldLayout.ColumnSpan(ctx.Size, column)) else ctx.Right
			kit:CylD("TieRod", x, y + 0.45, -0.9, 0.9, 0.2, steel:Lerp(BLACK, 0.2), M.Metal, { Shadow = false })
		end
	end
	local info
	if spec.RoofShape == "Flat" then
		-- acrotère (toit-terrasse) + couronnement
		HouseDetail.Phase(kit, "Roof")
		kit:WallX("Parapet", ctx.Left - T, ctx.Right + T, ctx.Top + 0.6, ctx.Top + 3.2, -0.3, 0.5, {}, ctx.Wall, ctx.WallMat, { Solid = true })
		kit:Box("ParapetBack", ctx.Left - T, ctx.Right + T, ctx.Top + 0.6, ctx.Top + 3.2, ctx.Depth - 0.5, ctx.Depth + 0.3, ctx.Wall, ctx.WallMat, { Solid = true })
		for _, x in ipairs({ ctx.Left - T, ctx.Right + T - 0.8 }) do
			kit:Box("ParapetSide", x, x + 0.8, ctx.Top + 0.6, ctx.Top + 3.2, 0.5, ctx.Depth - 0.5, ctx.Wall, ctx.WallMat, { Solid = true })
		end
		kit:Box("Coping", ctx.Left - T - 0.4, ctx.Right + T + 0.4, ctx.Top + 3.2, ctx.Top + 3.7, -0.7, 0.9, Color3.fromRGB(216, 212, 208), M.Concrete, { Shadow = false })
		for _, x in ipairs({ ctx.Left + 2, ctx.Right - 2 }) do
			kit:CylY("Downpipe", x, 0.9, -0.62, 0.4, ctx.Top + 2.2, Color3.fromRGB(120, 124, 130), M.Metal, { Shadow = false })
			kit:Box("RainHead", x - 0.5, x + 0.5, ctx.Top + 2.4, ctx.Top + 3.2, -1, -0.3, Color3.fromRGB(120, 124, 130), M.Metal, { Shadow = false })
		end
		info = { Shape = "Flat", Ridge = ctx.Top + 3.2, Surface = function()
			return ctx.Top + 0.65
		end }
		-- terrasse : château d'eau, guirlande, parasol, jardinières
		local yRoof = ctx.Top + 0.6
		local wtX = ctx.Left + (ctx.Right - ctx.Left) * 0.2
		local wtD = ctx.Depth * 0.5
		for _, dx in ipairs({ -2.2, 2.2 }) do
			for _, dd in ipairs({ -2.2, 2.2 }) do
				kit:Box("TowerLeg", wtX + dx - 0.2, wtX + dx + 0.2, yRoof, yRoof + 6, wtD + dd - 0.2, wtD + dd + 0.2, steel, M.Metal, { Solid = true, Shadow = false })
			end
		end
		kit:CylY("WaterTank", wtX, yRoof + 6, wtD, 6.4, 6, Color3.fromRGB(150, 110, 78), M.WoodPlanks, { Solid = true })
		for _, band in ipairs({ 1.2, 3, 4.8 }) do
			kit:CylY("TankBand", wtX, yRoof + 6 + band, wtD, 6.55, 0.25, steel, M.Metal, { Shadow = false })
		end
		kit:Cone("TankRoof", wtX, yRoof + 12, wtD, 3.8, 3, 8, ctx.Roof, M.Slate)
		kit:Ball("TankTop", wtX, yRoof + 15.2, wtD, 0.6, P.Gold, M.Metal, { Shadow = false })
		local p1, p2 = ctx.Left + (ctx.Right - ctx.Left) * 0.42, ctx.Right - (ctx.Right - ctx.Left) * 0.24
		local poleD = ctx.Depth * 0.35
		for _, px in ipairs({ p1, p2 }) do
			kit:Box("LightPole", px - 0.12, px + 0.12, yRoof, yRoof + 6.5, poleD - 0.12, poleD + 0.12, steel, M.Metal, { Shadow = false })
		end
		HouseDetail.StringLights(kit, { p1, yRoof + 6.4, poleD }, { p2, yRoof + 6.4, poleD }, 12, 1.8)
		local umX = ctx.Right - (ctx.Right - ctx.Left) * 0.14
		kit:CylY("ParasolPole", umX, yRoof, poleD + 3, 0.2, 4.6, WHITE, M.Metal, { Shadow = false })
		kit:Cone("Parasol", umX, yRoof + 4.2, poleD + 3, 3.4, 1.4, 8, C.Pink, M.Fabric)
		for index = 0, 4 do
			local bx = ctx.Left + 4 + index * (ctx.Right - ctx.Left - 8) / 4
			kit:Box("Planter", bx - 1.8, bx + 1.8, yRoof, yRoof + 1.2, 1.2, 3, Color3.fromRGB(150, 110, 78), M.WoodPlanks, { Shadow = false })
			kit:Ball("Shrub", bx, yRoof + 1.9, 2.1, 2.2, P.Leaf, M.Grass)
		end
	else
		info = mainRoof(ctx, ctx.Left - T, ctx.Right + T, { Over = 1.6, Pitch = 0.6, Pipes = { ctx.Left + 1, ctx.Right - 1 }, MansardRise = 9, Inset = 5 })
	end
	roofChimney(ctx, info :: any, ctx.Left + (ctx.Right - ctx.Left) * 0.7, ctx.Depth * 0.55, false)
	-- porte d'acier + auvent + lanterne
	HouseDetail.Phase(kit, "Openings")
	local gx = ctx.DoorX
	local yDoor = WorldLayout.FloorY(1)
	frontDoor(ctx)
	-- (v9.8 HOUSE98) la plaque au nom se dresse sur le bord avant de l'auvent
	local yTopDoor = yDoor + WorldLayout.DOOR_H
	if spec.Porch == "Steel" then
		kit:Box("DoorCanopy", gx - 4.6, gx + 4.6, yTopDoor + 1.1, yTopDoor + 1.5, -2.8, -0.3, steel, M.Metal)
		for _, s in ipairs({ -1, 1 }) do
			kit:Slab("CanopyRod", gx + s * 4.2, { yTopDoor + 1.3, -2.6 }, { yTopDoor + 3.2, -0.3 }, 0.12, 0.12, steel, M.Metal, { Shadow = false })
		end
		namePlate(ctx, gx, yTopDoor + 1.65, -2.55, 6.4)
	else
		porchCover(ctx, spec.Porch, yTopDoor + 0.6, yTopDoor + 3, 2.6)
		namePlate(ctx, gx, yTopDoor + 3.6, -0.36, 6.4)
	end
	entranceLights(ctx, yDoor, -0.36, -1)
	HouseDetail.Phase(kit, "Foundation")
	local foot = porch(ctx, gx - 5, gx + 5, 2.6, 3, Color3.fromRGB(214, 208, 204), M.Concrete)
	-- enseigne néon verticale "LOFT" (à gauche, sur consoles)
	HouseDetail.Phase(kit, "Openings")
	local sx = ctx.Left - T - 3.4
	for _, by in ipairs({ ctx.Top - 4, ctx.Top - 12 }) do
		kit:Box("SignBracket", sx + 1.4, ctx.Left - T, by, by + 0.3, -0.9, -0.5, steel, M.Metal, { Shadow = false })
	end
	local board = kit:Box("NeonSign", sx - 1.6, sx + 1.6, ctx.Top - 14, ctx.Top - 2, -1.2, -0.4, Color3.fromRGB(86, 64, 120), M.SmoothPlastic, { Solid = true })
	local sign = Instance.new("SurfaceGui")
	sign.Name = "Neon"
	sign.Face = Enum.NormalId.Back
	sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sign.PixelsPerStud = 20
	sign.LightInfluence = 0
	sign.Brightness = 1 -- (v9.6 FIXES96 : 2 -> 1, enseigne pas éblouissante)
	sign.MaxDistance = 400
	sign.Parent = board
	for index, letter in ipairs({ "L", "O", "F", "T" }) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.2 + (index - 1) * 0.2)
		label.Size = UDim2.fromScale(1, 0.18)
		label.Font = Enum.Font.FredokaOne
		label.Text = letter
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(190, 250, 255)
		label.TextStrokeColor3 = Color3.fromRGB(80, 200, 255)
		label.TextStrokeTransparency = 0.3
		label.Parent = sign
	end
	-- escalier de secours devant la travée de droite (décor)
	if dims.Floors >= 2 then
		local ly = WorldLayout.FloorY(dims.Floors)
		local f0, f1 = gx + 4.9, ctx.Right + T + 7.5
		if ctx.SideGarage then
			f1 = ctx.Right + T - 0.5
		end
		kit:Box("FireLanding", f0, f1, ly - 0.3, ly, -3.2, -0.36, steel, M.DiamondPlate, { Shadow = false })
		kit:Box("FireRail", f0, f1, ly + 2.8, ly + 3, -3.2, -3, steel, M.Metal, { Shadow = false })
		for k = 0, 6 do
			local x = f0 + k * (f1 - f0) / 6
			kit:Box("FireBar", x - 0.06, x + 0.06, ly, ly + 2.8, -3.15, -3.05, steel, M.Metal, { Shadow = false })
		end
		kit:SlabX("FireStair", -2, { f0 + 1, ly }, { f1 - 0.6, ctx.Top + 0.6 }, 2.2, 0.3, steel, M.DiamondPlate, { Shadow = false })
		for _, lx in ipairs({ f1 - 2.2, f1 - 1 }) do
			kit:Box("Ladder", lx - 0.08, lx + 0.08, ly - 8, ly, -2.6, -2.45, steel, M.Metal, { Shadow = false })
		end
		for k = 1, 6 do
			kit:Box("LadderRung", f1 - 2.2, f1 - 1, ly - k * 1.25, ly - k * 1.25 + 0.12, -2.6, -2.45, steel, M.Metal, { Shadow = false })
		end
	end
	-- trottoir : caisses fleuries, banc, plantes
	HouseDetail.Phase(kit, "Garden")
	ctx.G:Box("Sidewalk", ctx.Left - 8, ctx.Right + 6, -0.1, 0.12, -6, -0.6, P.Pave, M.Pavement, { Shadow = false })
	for index, c in ipairs({ { ctx.Left + 2, -3 }, { ctx.Left + 5, -3.4 }, { ctx.Left + 3.2, -4.9 } }) do
		ctx.G:Box("Crate", c[1] - 1.2, c[1] + 1.2, 0, 1.8 - (index % 2) * 0.3, c[2] - 1, c[2] + 1, Color3.fromRGB(170, 124, 86), M.WoodPlanks, { Shadow = false })
		ctx.G:Ball("CrateBush", c[1], 2.2, c[2], 1.8, P.Leaf, M.Grass, { Shadow = false })
	end
	local benchX = (WorldLayout.ColumnSpan(ctx.Size, 1) + select(2, WorldLayout.ColumnSpan(ctx.Size, 1))) / 2 + 12
	HouseGarden.Bench(ctx.G, benchX, -3, C.Pink)
	HouseGarden.PottedBall(ctx.G, gx - 6.5, -2, 1.2, C.Peach)
	sideGarage(ctx)
	local pathPoints = { { 0, -21.5 }, { 0, -7 }, { gx, -7 }, { gx, foot } }
	gardenFront(ctx, ctx.Left - 8, ctx.Right + 4, 0, pathPoints, 3.2)
	HouseDetail.Path(ctx.G, { { 0, -29.5 }, { 0, -21.6 } }, 3.2, spec.Path)
	gardenLights(ctx, { { 0, -21 }, { 0, -8 } })
end

----------------------------------------------------------------------
-- (v9.6, GARAGE96) 🏎️ Aile du garage du manoir (GarageLayout) : 3 places
-- côte à côte dans la cour de devant (côté droit vu de la rue). Model
-- "Garage" étiqueté "DopamineGarage", attribut HouseCF ; portes "Door_<n>"
-- (attribut OpenCF, animées par CarClient).
----------------------------------------------------------------------

-- Garage possédé ? (instantané -> looks.Garage ; sinon attribut répliqué du propriétaire)
local function hasGarage(kit: any, looks: Looks): boolean
	if looks.Garage == true then
		return true
	end
	if looks.Garage == false then
		return false
	end
	local ok, result = pcall(function()
		local folder = kit.Folder
		local model = folder and folder.Parent
		local ownerId = model and model:GetAttribute("OwnerId")
		local owner = type(ownerId) == "number" and Players:GetPlayerByUserId(ownerId) or nil
		return owner ~= nil and owner:GetAttribute("DopamineGarage") == true
	end)
	return ok and result == true
end
-- Grille sans portail (reprise de la grille à droite du garage)
local function fenceRun(ctx: Ctx, a: number, b: number, d: number)
	if b - a < 1 then
		return
	end
	local kit = ctx.G
	local iron = C.Ink:Lerp(C.Lilac, 0.25)
	kit:Box("FenceRail", a, b, 0.6, 0.8, d - 0.1, d + 0.1, iron, M.Metal, { Solid = true, Shadow = false })
	kit:Box("FenceRail", a, b, 3.0, 3.2, d - 0.1, d + 0.1, iron, M.Metal, { Shadow = false })
	local count = math.max(2, math.floor((b - a) / 3.3)) -- (v9.8 : budget de pièces)
	for k = 0, count do
		local x = a + k * (b - a) / count
		kit:Box("FenceBar", x - 0.1, x + 0.1, 0, 3.8, d - 0.1, d + 0.1, iron, M.Metal, { Shadow = false })
	end
end
local function garageWing(ctx: Ctx)
	local model = Instance.new("Model")
	model.Name = "Garage"
	model:SetAttribute("HouseCF", ctx.Kit.CF)
	model.Parent = ctx.Kit.Folder
	local kit = ctx.Kit:Sub(CFrame.new(), model)
	local G = GarageLayout
	local X0, X1, D0, D1, W = G.X0, G.X1, G.D0, G.D1, G.WALL
	local H, FLOOR = G.HEIGHT, G.FLOOR
	local TRIM = Color3.fromRGB(255, 250, 244)
	local wall = ctx.Wall
	local stone = P.Stone
	-- dalle, allée pavée jusqu'à la rue (+ bordures), rampe invisible vers le trottoir
	kit:Box("GarageSlab", X0 + 0.05, X1 - 0.05, 0.2, FLOOR, D0 + 0.05, D1 - 0.05, Color3.fromRGB(214, 210, 216), M.Concrete, { Solid = true })
	local street = G.STREET_D
	kit:Box("Driveway", X0 + 1.2, X1 - 1.2, 0.3, 0.62, street, D0, P.Pave, M.Pavement, { Solid = true })
	for _, x in ipairs({ X0 + 0.7, X1 - 0.7 }) do
		kit:Box("DrivewayEdge", x - 0.5, x + 0.5, 0.3, 0.75, street, D0, TRIM, M.Limestone, { Solid = true, Shadow = false })
	end
	kit:Part("DrivewayRamp", Vector3.new(X1 - X0 - 2.4, 0.42, 1.6), CFrame.new((X0 + X1) / 2, 0.62 + 0.21, -(street + 0.8)), WHITE, M.SmoothPlastic,
		{ Solid = true, Query = false, T = 1, Shadow = false }, "WedgePart")
	-- murs (enduit de la façade) : fond, côtés (fenêtre cintrée côté fontaine), façade percée de 3 portes
	kit:Box("GarageBack", X0, X1, 0, H, D1 - W, D1, wall, M.Plaster, { Solid = true })
	local winD0, winD1, winY0, winY1 = -17.5, -12.5, 3.2, 7
	kit:WallD("GarageSide", X0, X0 + W, 0, H, D0, D1, { { winD0, winD1, winY0, winY1 } }, wall, M.Plaster, { Solid = true })
	kit:Box("GarageSideGlass", X0 + 0.25, X0 + 0.55, winY0, winY1, winD0, winD1, P.Glass, M.Glass, { T = 0.35, Shadow = false })
	kit:Box("GarageSideSill", X0 - 0.35, X0 + 0.1, winY0 - 0.35, winY0 + 0.06, winD0 - 0.4, winD1 + 0.4, TRIM, M.Limestone, { Shadow = false })
	kit:Box("GarageSideR", X1 - W, X1, 0, H, D0, D1, wall, M.Plaster, { Solid = true })
	local holes = {}
	for bay = 1, G.BAYS do
		local cx = G.BayX(bay)
		table.insert(holes, { cx - G.DOOR_W / 2, cx + G.DOOR_W / 2, FLOOR, FLOOR + G.DOOR_H })
	end
	kit:WallX("GarageFront", X0, X1, FLOOR, H, D0, D0 + W, holes, wall, M.Plaster, { Solid = true })
	-- soubassement, chaînes d'angle, corniche, bandeau doré
	kit:Box("GaragePlinth", X0 - 0.15, X0 + 0.9, -0.05, 1.2, D0 - 0.15, D1 + 0.08, stone, M.Limestone, { Shadow = false })
	kit:Box("GaragePlinth", X1 - 0.9, X1 + 0.15, -0.05, 1.2, D0 - 0.15, D1 + 0.08, stone, M.Limestone, { Shadow = false })
	for _, x in ipairs({ X0, X1 }) do
		for k = 0, 3 do
			local y = 1.2 + k * 2.2
			kit:Box("Quoin", x - 0.55, x + 0.55, y, y + 1.2, D0 - 0.2, D0 + 1.1, TRIM, M.Limestone, { Shadow = false })
		end
	end
	kit:Box("GarageCornice", X0 - 0.6, X1 + 0.6, H - 0.2, H + 0.7, D0 - 0.7, D1 + 0.12, TRIM, M.Limestone, { Solid = true })
	kit:Box("GarageBand", X0 - 0.2, X1 + 0.2, H - 1.4, H - 1.2, D0 - 0.24, D0 - 0.02, P.Gold, M.Metal, { Shadow = false })
	-- toit-terrasse : parapet plein + lisse + pots à boule
	kit:Box("GarageParapet", X0 - 0.4, X1 + 0.4, H + 0.7, H + 2.1, D0 - 0.5, D0 + 0.3, TRIM, M.Limestone, { Shadow = false })
	kit:Box("GarageParapet", X0 - 0.4, X0 + 0.4, H + 0.7, H + 2.1, D0 + 0.3, D1, TRIM, M.Limestone, { Shadow = false })
	kit:Box("GarageParapet", X1 - 0.4, X1 + 0.4, H + 0.7, H + 2.1, D0 + 0.3, D1, TRIM, M.Limestone, { Shadow = false })
	kit:Box("GarageRail", X0 - 0.5, X1 + 0.5, H + 2.1, H + 2.35, D0 - 0.6, D0 + 0.4, P.Gold, M.Metal, { Shadow = false })
	for _, x in ipairs({ X0, X1 }) do
		kit:Box("GarageUrn", x - 0.5, x + 0.5, H + 2.35, H + 3.1, D0 - 0.3, D0 + 0.5, TRIM, M.Limestone, { Shadow = false })
		kit:Ball("GarageUrnBall", x, H + 3.5, D0 + 0.1, 0.9, P.Gold, M.Metal, { Shadow = false })
	end
	-- enseigne "GARAGE" (au-dessus de la porte du milieu) + cœur
	local sign = kit:Box("GarageSign", G.BayX(2) - 4.2, G.BayX(2) + 4.2, FLOOR + G.DOOR_H + 0.55, FLOOR + G.DOOR_H + 1.6, D0 - 0.3, D0 - 0.05, TRIM, M.SmoothPlastic,
		{ Shadow = false })
	kit:Text(sign, Enum.NormalId.Back, "🏎️ GARAGE", C.PinkDeep, Enum.Font.FredokaOne, 30, 160)
	-- encadrements, clés de voûte, portes basculantes
	local doorColor = TRIM:Lerp(C.Pink, 0.12)
	local rib = C.PinkSoft:Lerp(C.Pink, 0.25)
	for bay = 1, G.BAYS do
		local cx = G.BayX(bay)
		local x0, x1 = cx - G.DOOR_W / 2, cx + G.DOOR_W / 2
		local top = FLOOR + G.DOOR_H
		-- (encadrement : 0,05 dans l'ouverture et en retrait du nu intérieur -> aucune face coplanaire)
		kit:Box("DoorJamb", x0 - 0.45, x0 + 0.05, FLOOR, top, D0 - 0.25, D0 + W - 0.05, TRIM, M.Limestone, { Shadow = false })
		kit:Box("DoorJamb", x1 - 0.05, x1 + 0.45, FLOOR, top, D0 - 0.25, D0 + W - 0.05, TRIM, M.Limestone, { Shadow = false })
		kit:Box("DoorHeader", x0 - 0.45, x1 + 0.45, top - 0.05, top + 0.45, D0 - 0.25, D0 + W - 0.05, TRIM, M.Limestone, { Shadow = false })
		if bay ~= 2 then
			kit:Box("Keystone", cx - 0.5, cx + 0.5, top + 0.45, top + 1.4, D0 - 0.35, D0 + 0.2, TRIM, M.Limestone, { Shadow = false })
		end
		local door = Instance.new("Model")
		door.Name = "Door_" .. bay
		door.Parent = model
		local dk = ctx.Kit:Sub(CFrame.new(), door)
		local dz = D0 + W * 0.5
		local panel = dk:Box("Panel", x0 + 0.05, x1 - 0.05, FLOOR + 0.02, top - 0.02, dz - 0.12, dz + 0.12, doorColor, M.SmoothPlastic, { Solid = true })
		for k = 1, 3 do
			local y = FLOOR + k * G.DOOR_H / 4
			dk:Box("Rib", x0 + 0.2, x1 - 0.2, y - 0.08, y + 0.08, dz - 0.2, dz - 0.12, rib, M.SmoothPlastic, { Shadow = false })
		end
		dk:Box("DoorWindows", x0 + 0.9, x1 - 0.9, top - 1.5, top - 0.7, dz - 0.18, dz - 0.1, P.Glass, M.Glass, { Shadow = false })
		dk:Box("DoorHandle", cx - 0.6, cx + 0.6, FLOOR + 0.9, FLOOR + 1.1, dz - 0.3, dz - 0.12, P.Gold, M.Metal, { Shadow = false })
		-- ouverte : couchée sous le plafond, vers l'intérieur (porte basculante)
		local openLocal = CFrame.new(cx, top + 0.45, -(D0 + W + G.DOOR_H / 2)) * CFrame.Angles(math.rad(90), 0, 0)
		door:SetAttribute("OpenCF", ctx.Kit.CF * openLocal)
		door.PrimaryPart = panel
	end
	-- lanternes entre les portes (sans vraie lumière)
	for k = 1, G.BAYS - 1 do
		local x = (G.BayX(k) + G.BayX(k + 1)) / 2
		kit:Box("LanternArm", x - 0.1, x + 0.1, FLOOR + 5.4, FLOOR + 5.6, D0 - 0.8, D0, C.Ink, M.Metal, { Shadow = false })
		kit:Box("Lantern", x - 0.35, x + 0.35, FLOOR + 4.1, FLOOR + 5.4, D0 - 1.15, D0 - 0.45, P.Lamp, M.SmoothPlastic, { Shadow = false })
		kit:Box("LanternCap", x - 0.45, x + 0.45, FLOOR + 5.4, FLOOR + 5.7, D0 - 1.25, D0 - 0.35, C.Ink, M.Metal, { Shadow = false })
	end
	-- intérieur : plafond, marquages, étagère, plafonnier (lumière douce, éteinte)
	kit:Box("GarageCeiling", X0 + W, X1 - W, H - 0.45, H - 0.25, D0 + W, D1 - W, Color3.fromRGB(246, 240, 244), M.SmoothPlastic, { Shadow = false })
	for k = 1, G.BAYS - 1 do
		local x = (G.BayX(k) + G.BayX(k + 1)) / 2
		kit:Box("BayLine", x - 0.12, x + 0.12, FLOOR, FLOOR + 0.03, D0 + W + 1, D1 - W - 1, WHITE, M.SmoothPlastic, { Shadow = false })
	end
	kit:Box("Shelf", X0 + 3, X1 - 3, 5.2, 5.4, D1 - W - 1.1, D1 - W, Color3.fromRGB(214, 164, 120), M.Wood, { Shadow = false })
	kit:Box("ShelfBox", X0 + 4, X0 + 6, 5.4, 6.6, D1 - W - 1, D1 - W - 0.1, C.Pink, M.SmoothPlastic, { Shadow = false })
	kit:Box("ShelfBox", X1 - 7, X1 - 4.5, 5.4, 6.2, D1 - W - 1, D1 - W - 0.1, C.Sky, M.SmoothPlastic, { Shadow = false })
	local lamp = kit:Box("CeilingLamp", (X0 + X1) / 2 - 3, (X0 + X1) / 2 + 3, H - 0.75, H - 0.47, (D0 + D1) / 2 - 0.6, (D0 + D1) / 2 + 0.6, Color3.fromRGB(255, 246, 226),
		M.SmoothPlastic, { Shadow = false })
	local light = ctx.Kit:Light(lamp, Color3.fromRGB(255, 226, 190), 18, 0.9)
	if light then
		light.Enabled = false
	end
	-- grille qui reprend à droite (les voitures garées : CarClient, dossier "GarageCars" de la maison)
	fenceRun(ctx, X1, ctx.Right + WorldLayout.WALL_T + 7, -21)
	CollectionService:AddTag(model, "DopamineGarage")
end

-- ░░ Mansion : le grand manoir ░░
STYLES.Mansion = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local spec = ctx.Spec
	local T = WorldLayout.WALL_T
	local TRIM = ctx.Trim
	local TOWER = ctx.Wall:Lerp(C.Pink, 0.06)
	local holes, list = openings(ctx, function(floor)
		local yFloor = WorldLayout.FloorY(floor)
		if floor == 2 then
			-- (v9.8 : un peu plus haute : le panneau au nom du balcon ne la cache pas)
			return { ctx.DoorX - 2, ctx.DoorX + 2, yFloor + 2.7, yFloor + 8.9 }
		end
		return nil
	end)
	bodyWalls(ctx, holes, P.Stone, M.Limestone)
	frontWindows(ctx, list, TRIM, M.Wood, { Sill = TRIM:Lerp(P.Stone, 0.3), Lintel = "Stone", LintelColor = TRIM, NoArch = spec.Window ~= "Tall" and spec.Window ~= "Arched" })
	-- œil-de-bœuf du dernier étage (travée centrale)
	HouseDetail.Phase(kit, "Walls")
	if dims.Floors >= 3 then
		local y = WorldLayout.FloorY(dims.Floors) + 5.5
		kit:CylD("Oculus", ctx.DoorX, y, -0.45, 3.6, 0.3, TRIM, M.Limestone, { Shadow = false })
		kit:CylD("OculusGlass", ctx.DoorX, y, -0.62, 2.6, 0.1, P.Glass, M.Glass, { Shadow = false })
	end
	-- colonnes engagées (bords, murs entre les pièces)
	local xs = { ctx.Left - T + 0.6, ctx.Right + T - 0.6 }
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		table.insert(xs, x0)
		table.insert(xs, x1)
	end
	table.sort(xs)
	local cols: { number } = {}
	for _, x in ipairs(xs) do
		if #cols == 0 or x - cols[#cols] > 1.4 then
			table.insert(cols, x)
		end
	end
	for floor = 1, dims.Floors do
		local y0 = WorldLayout.FloorY(floor)
		for _, x in ipairs(cols) do
			kit:CylY("Column", x, y0 + 0.5, -0.9, 1.3, WorldLayout.WALL_H - 1.4, TRIM, M.Marble, { Shadow = false })
			kit:Box("ColumnBase", x - 0.9, x + 0.9, y0, y0 + 0.55, -1.8, -0.3, TRIM, M.Limestone, { Shadow = false })
			kit:Box("ColumnCap", x - 0.95, x + 0.95, y0 + WorldLayout.WALL_H - 0.95, y0 + WorldLayout.WALL_H - 0.35, -1.85, -0.3, TRIM, M.Limestone, { Shadow = false })
		end
	end
	-- bandeaux + balustrades devant les pièces des étages
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor)
		kit:Box("Band", ctx.Left - T - 0.4, ctx.Right + T + 0.4, y - 1.4, y - 0.1, -0.9, -0.3, TRIM, M.Limestone, { Shadow = false })
		kit:Box("BandGold", ctx.Left - T - 0.4, ctx.Right + T + 0.4, y - 0.8, y - 0.6, -0.95, -0.9, P.Gold, M.Metal, { Shadow = false })
		HouseDetail.Phase(kit, "Openings")
		for column = 1, dims.Columns do
			local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
			HouseDetail.Balcony(kit, spec.Balcony, x0 + 1.4, x1 - 1.4, y, 1.3, -0.3, TRIM)
		end
		HouseDetail.Phase(kit, "Walls")
		if floor == 2 then
			-- balcon central sur 2 consoles ; son garde-corps avant = panneau de la plaque au nom
			kit:Box("CenterBalcony", ctx.DoorX - 4.6, ctx.DoorX + 4.6, y - 0.45, y - 0.05, -3.6, -0.3, TRIM, M.Limestone, { Solid = true })
			for _, s in ipairs({ -1, 1 }) do
				kit:Box("BalconyCorbel", ctx.DoorX + s * 3.9 - 0.3, ctx.DoorX + s * 3.9 + 0.3, y - 1.7, y - 0.45, -2.7, -0.3, TRIM, M.Limestone, { Shadow = false })
			end
		end
	end
	-- corniche + modillons + liseré doré
	kit:Box("Cornice", ctx.Left - T - 1, ctx.Right + T + 1, ctx.Top - 0.2, ctx.Top + 1.3, -1.5, 0, TRIM, M.Limestone)
	kit:Box("CorniceGold", ctx.Left - T - 0.7, ctx.Right + T + 0.7, ctx.Top + 0.6, ctx.Top + 0.8, -1.55, -1.5, P.Gold, M.Metal, { Shadow = false })
	local modCount = math.floor((ctx.Right - ctx.Left) / 4)
	for k = 0, modCount do
		local x = ctx.Left + k * (ctx.Right - ctx.Left) / modCount
		kit:Box("Modillion", x - 0.35, x + 0.35, ctx.Top - 0.9, ctx.Top - 0.2, -1.1, -0.3, TRIM, M.Limestone, { Shadow = false })
	end
	-- toit (mansarde par défaut), crête, lucarnes, œils-de-bœuf, cheminées
	local info = mainRoof(ctx, ctx.Left - T, ctx.Right + T, { Over = 1.6, Pitch = 0.6, MansardRise = 10, Inset = 5.5, Eaves = false })
	if info.Shape == "Mansard" then
		HouseDetail.Phase(kit, "Roof")
		local crest = math.max(2, math.floor((ctx.Right - ctx.Left - 11) / 12))
		for k = 0, crest do
			local x = ctx.Left + 5.5 + k * (ctx.Right - ctx.Left - 11) / crest
			kit:Box("CrestPost", x - 0.12, x + 0.12, info.Ridge, info.Ridge + 1.6, 5.02, 5.38, P.Gold:Lerp(C.Ink, 0.2), M.Metal, { Shadow = false })
			kit:Ball("CrestBall", x, info.Ridge + 1.75, 5.2, 0.6, P.Gold, M.Metal, { Shadow = false })
		end
	end
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		roofDormer(ctx, info, (x0 + x1) / 2, 5.4, 6, false, 0.18)
	end
	for _, s in ipairs({ -1, 1 }) do
		roofChimney(ctx, info, ctx.DoorX + s * (ctx.Right - ctx.Left) * 0.3, ctx.Depth * 0.55, s > 0)
	end
	-- fronton central + horloge
	HouseDetail.Phase(kit, "Roof")
	local pedW, pedH = 34, 11
	local pedY = ctx.Top + 1.3
	for _, s in ipairs({ -1, 1 }) do
		kit:Part("Pediment", Vector3.new(1.2, pedH, pedW / 2), CFrame.new(ctx.DoorX + s * pedW / 4, pedY + pedH / 2, 0.9) * CFrame.Angles(0, -s * math.pi / 2, 0), TRIM,
			M.Limestone, { Solid = true }, "WedgePart")
		kit:Part("PedimentInner", Vector3.new(0.3, pedH - 3, pedW / 2 - 4.5), CFrame.new(ctx.DoorX + s * (pedW / 2 - 4.5) / 2, pedY + 0.9 + (pedH - 3) / 2, 0.4)
			* CFrame.Angles(0, -s * math.pi / 2, 0), ctx.Wall:Lerp(TRIM, 0.3), ctx.WallMat, { Shadow = false }, "WedgePart")
	end
	local clockY = pedY + pedH * 0.38
	kit:CylD("ClockRim", ctx.DoorX, clockY - 0.1, -1.95, 4.2, 0.3, P.Gold, M.Metal, { Shadow = false })
	kit:CylD("ClockFace", ctx.DoorX, clockY - 0.1, -2.05, 3.6, 0.2, C.Cream, M.SmoothPlastic, { Shadow = false })
	kit:Part("ClockHand", Vector3.new(0.2, 1.3, 0.1), CFrame.new(ctx.DoorX + 0.2, clockY + 0.45, 2.2) * CFrame.Angles(0, 0, math.rad(-20)), C.Ink, M.Metal, { Shadow = false })
	kit:Part("ClockHand", Vector3.new(0.16, 0.9, 0.1), CFrame.new(ctx.DoorX + 0.35, clockY - 0.3, 2.22) * CFrame.Angles(0, 0, math.rad(115)), C.Ink, M.Metal, { Shadow = false })
	kit:Box("ClockBase", ctx.DoorX - 3, ctx.DoorX + 3, clockY - 2.8, clockY - 2.4, -2.2, -0.4, TRIM, M.Limestone, { Shadow = false })
	-- tours rondes aux deux bouts, toits coniques (architecture classique seulement)
	HouseDetail.Phase(kit, "Walls")
	local radius = 7
	for index, s in ipairs({ -1, 1 }) do
		local tx = if s < 0 then ctx.Left - T - 1 else ctx.Right + T + 1
		local td = 0.5
		local top = ctx.Top + 3
		kit:CylY("Tower", tx, -0.15, td, radius * 2, top + 0.15, TOWER, ctx.WallMat, { Solid = true })
		kit:CylY("TowerPlinth", tx, -0.2, td, radius * 2 + 0.6, WorldLayout.PLINTH + 0.6, P.Stone, M.Limestone, { Solid = true })
		for floor = 1, dims.Floors do
			local y = WorldLayout.FloorY(floor)
			if floor > 1 then
				kit:CylY("TowerBand", tx, y - 1.2, td, radius * 2 + 0.5, 0.9, TRIM, M.Limestone, { Shadow = false })
			end
			local wx0, wx1 = tx - 1.8, tx + 1.8
			local wy0, wy1 = y + 2.4, y + 8
			local face = td - radius
			kit:Box("TowerGlass", wx0, wx1, wy0, wy1, face - 0.35, face + 0.2, P.Glass, M.Glass, { Shadow = false })
			kit:Box("TowerWinFrame", wx0 - 0.35, wx1 + 0.35, wy0 - 0.35, wy0, face - 0.45, face + 0.2, TRIM, M.Wood, { Shadow = false })
			kit:Box("TowerSill", wx0 - 0.6, wx1 + 0.6, wy0 - 0.75, wy0 - 0.35, face - 0.85, face + 0.1, TRIM:Lerp(P.Stone, 0.3), M.Limestone, { Shadow = false })
			kit:Box("TowerMullion", tx - 0.1, tx + 0.1, wy0, wy1, face - 0.42, face - 0.3, TRIM, M.Wood, { Shadow = false })
			kit:CylD("TowerArch", tx, wy1, face - 0.25, 3.6, 0.35, P.Glass, M.Glass, { Shadow = false })
			kit:CylD("TowerArchRim", tx, wy1, face - 0.1, 4.3, 0.2, TRIM, M.Wood, { Shadow = false })
		end
		kit:CylD("TowerOculus", tx, top - 2.2, td - radius - 0.1, 2.4, 0.3, P.Glass, M.Glass, { Shadow = false })
		kit:CylY("TowerCrown", tx, top - 0.3, td, radius * 2 + 1.6, 1.2, TRIM, M.Limestone, { Solid = true })
		HouseDetail.Phase(kit, "Roof")
		kit:Cone("TowerRoof", tx, top + 0.9, td, radius + 1.6, 12, 8, ctx.Roof, spec.RoofMat)
		kit:CylY("TowerEave", tx, top + 0.7, td, radius * 2 + 3.4, 0.3, ctx.RoofDark, M.Metal, { Shadow = false })
		kit:Ball("TowerTop", tx, top + 13.1, td, 0.9, P.Gold, M.Metal, { Shadow = false })
		kit:Box("FlagPole", tx - 0.1, tx + 0.1, top + 13.3, top + 17.5, td - 0.1, td + 0.1, WHITE, M.Metal, { Shadow = false })
		kit:Box("Flag", tx + 0.1, tx + 2.6, top + 15.8, top + 17.4, td - 0.06, td + 0.06, if index == 1 then C.Pink else C.Lilac, M.Fabric, { Shadow = false })
		HouseDetail.Phase(kit, "Walls")
	end
	-- porte d'honneur + grand escalier double
	HouseDetail.Phase(kit, "Openings")
	local gx = ctx.DoorX
	local yDoor = WorldLayout.FloorY(1)
	frontDoor(ctx)
	archTop(ctx, gx - WorldLayout.DOOR_W / 2, gx + WorldLayout.DOOR_W / 2, yDoor + WorldLayout.DOOR_H + 0.6, TRIM, 1.2)
	if dims.Floors >= 2 then
		local balY = WorldLayout.FloorY(2) - 0.05 -- dessus du balcon central
		kit:Box("NamePanel", gx - 4.3, gx + 4.3, balY, balY + 2.4, -3.52, -3.22, TRIM, M.Limestone, { Solid = true, Shadow = false })
		kit:Box("NamePanelCap", gx - 4.5, gx + 4.5, balY + 2.4, balY + 2.65, -3.62, -3.12, TRIM:Lerp(P.Stone, 0.12), M.Limestone, { Shadow = false })
		namePlate(ctx, gx, balY + 0.38, -3.52, 6.8)
	else
		namePlate(ctx, gx, yDoor + WorldLayout.DOOR_H + 2.1, -0.4, 6.4)
	end
	entranceLights(ctx, yDoor, -0.36, 1)
	HouseDetail.Phase(kit, "Foundation")
	local landD, landW = 5, 11
	kit:Box("Landing", gx - landW / 2, gx + landW / 2, 0, yDoor, -landD, 0, P.Stone, M.Limestone, { Solid = true })
	kit:Box("LandingEdge", gx - landW / 2 - 0.2, gx + landW / 2 + 0.2, yDoor - 0.3, yDoor + 0.1, -landD - 0.2, 0, TRIM, M.Limestone, { Shadow = false })
	local steps = 3
	local tread = 1.3
	local stepRise = yDoor / steps
	for _, s in ipairs({ -1, 1 }) do
		local x0 = gx + s * landW / 2
		for k = 1, steps - 1 do
			local top = yDoor - k * stepRise
			local a, b = x0 + s * (k - 1) * tread, x0 + s * k * tread
			kit:Box("GrandStep", math.min(a, b), math.max(a, b), 0, top, -landD + 0.2, -0.3, P.Stone:Lerp(WHITE, (k % 2) * 0.15), M.Limestone, { Shadow = false })
		end
		local run = (steps - 0.5) * tread
		local xEnd = x0 + s * run
		local lawn = HouseKit.LAWN
		local slope = (yDoor - lawn) / run
		kit:SlabX("GrandRamp", -landD / 2, { xEnd + s * 0.6, lawn - 0.6 * slope }, { x0, yDoor }, landD - 0.6, 1, WHITE, M.SmoothPlastic,
			{ Solid = true, Query = true, T = 1, Shadow = false })
		kit:SlabX("StairRail", -landD - 0.1, { x0, yDoor + 2.6 }, { xEnd, 2.6 }, 0.4, 0.35, TRIM, M.Limestone, { Shadow = false })
		for k = 1, steps - 1 do
			local x = x0 + s * (k - 0.5) * tread
			kit:CylY("StairBaluster", x, yDoor - k * stepRise, -landD - 0.1, 0.45, 2.6, TRIM, M.Limestone, { Shadow = false })
		end
		kit:Box("StairPillar", xEnd - 0.7, xEnd + 0.7, 0, 3.4, -landD - 0.8, -landD + 0.6, TRIM, M.Limestone, { Solid = true })
		if spec.Lights ~= "None" then
			postLantern(ctx, xEnd, -landD - 0.1, 3.4, 0.6, s > 0)
		end
		kit:Ball("PillarBall", x0, yDoor + 3, -landD - 0.1, 0.8, P.Gold, M.Metal, { Shadow = false })
	end
	-- parvis, fontaine, parterres, haies, topiaires, grille
	HouseDetail.Phase(kit, "Garden")
	local court0, court1 = gx - landW / 2 - steps * tread - 3, gx + landW / 2 + steps * tread + 3
	ctx.G:Box("Forecourt", court0, court1, -0.1, 0.1, -9, -landD, P.Pave, M.Pavement, { Shadow = false })
	courtFountain(ctx, gx, -13.5)
	for _, s in ipairs({ -1, 1 }) do
		local x1 = if s < 0 then ctx.Left - T - 1 + 7.5 else court1 + 1
		local x2 = if s < 0 then court0 - 1 else ctx.Right + T + 1 - 7.5
		ctx.G:Box("Hedge", x1, x2, 0, 1.6, -3.4, -1.4, P.Leaf, M.Grass)
		local bumps = math.max(1, math.floor((x2 - x1) / 6.5))
		for k = 0, bumps - 1 do
			ctx.G:CylX("HedgeTop", x1 + (k + 0.5) * (x2 - x1) / bumps, 1.6, -2.4, 2, (x2 - x1) / bumps - 0.4, P.Leaf:Lerp(WHITE, 0.06), M.Grass, { Shadow = false })
		end
		flowerDots(ctx, x1 + 1, x2 - 1, -3.8, 6)
		local tcx = if s < 0 then ctx.Left - T - 1 else ctx.Right + T + 1
		if not (ctx.Garage and s > 0) then
			HouseGarden.Topiary(ctx.G, tcx, -10)
		end
		local bx = gx + s * (ctx.Right - ctx.Left) * 0.24
		HouseGarden.FlowerBed(ctx.G, bx, -12, 5)
	end
	local fenceRight = if ctx.Garage then GarageLayout.X0 else ctx.Right + T + 7
	HouseDetail.Fence(ctx.G, ctx.Left - T - 7, fenceRight, FENCE_D, { Kind = spec.Fence, Gate0 = gx - 3.5, Gate1 = gx + 3.5 })
	HouseDetail.Path(ctx.G, { { gx, -29.5 }, { gx, -19.2 } }, 4, spec.Path)
	if spec.Mailbox ~= "Wall" then
		HouseDetail.Mailbox(ctx.G, spec.Mailbox, gx - 6.2, FENCE_D - 1.8, spec.MailColor, spec.Num)
	end
	gardenLights(ctx, { { gx, -21 }, { gx, -19.5 } })
	if ctx.Garage then
		HouseDetail.Phase(kit, "Walls")
		garageWing(ctx)
	end
end

----------------------------------------------------------------------
-- (v10) 🏔️ Chalet de montagne (toutes tailles)
----------------------------------------------------------------------

STYLES.Chalet = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local spec = ctx.Spec
	local T = WorldLayout.WALL_T
	local L, R = ctx.Left - T, ctx.Right + T
	local stone = Color3.fromRGB(168, 160, 150)
	local holes, list, hallHoles = openings(ctx, function(floor)
		local yFloor = WorldLayout.FloorY(floor)
		return { ctx.DoorX - 2.2, ctx.DoorX + 2.2, yFloor + 3.2, yFloor + 8.6 }
	end)
	bodyWalls(ctx, holes, stone, M.Cobblestone)
	-- soubassement de pierre jusqu'aux appuis du rez-de-chaussée
	HouseDetail.Phase(kit, "Walls")
	local stoneTop = WorldLayout.FloorY(1) + 2.3
	local skinHoles = {}
	for _, h in ipairs(holes[1]) do
		table.insert(skinHoles, { h[1] - 0.05, h[2] + 0.05, h[3] - 0.05, h[4] })
	end
	kit:WallX("StoneSkin", L, R, WorldLayout.PLINTH, stoneTop, -0.5, -0.3, skinHoles, stone, M.Cobblestone, { Shadow = false })
	kit:Box("StoneSkinCap", L - 0.1, R + 0.1, stoneTop, stoneTop + 0.3, -0.62, -0.3, stone:Lerp(WHITE, 0.2), M.Limestone, { Shadow = false })
	-- poteaux d'angle + lisses d'étage en bois foncé
	for _, x in ipairs({ L + 0.45, R - 0.45 }) do
		kit:Box("CornerBoard", x - 0.55, x + 0.55, stoneTop + 0.3, ctx.Top, -0.62, -0.3, ctx.Trim, M.Wood, { Shadow = false })
	end
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor) - WorldLayout.SLAB
		kit:Box("FloorBand", L - 0.2, R + 0.2, y - 0.2, y + 0.6, -0.66, -0.3, ctx.Trim, M.Wood, { Shadow = false })
	end
	frontWindows(ctx, list, ctx.Trim, M.Wood, { FlowerBox = Color3.fromRGB(120, 82, 56), Sill = ctx.Trim:Lerp(WHITE, 0.15), SillMat = M.Wood, HallShutters = true })
	-- balcons de bois courant le long de chaque étage
	HouseDetail.Phase(kit, "Openings")
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor)
		for column = 1, dims.Columns do
			local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
			HouseDetail.Balcony(kit, spec.Balcony, x0 + 0.8, x1 - 0.8, y, 2.4, -0.3, ctx.Trim)
		end
	end
	-- grand toit à deux pans, gros débords, rives
	local info = mainRoof(ctx, L, R, { Over = 3.2, Pitch = 0.62, Hip = 12, Pipes = { L + 1.4, R - 1.4 }, MansardRise = 9, Inset = 5, Fascia = ctx.Trim })
	-- pignon sur rue au-dessus de l'entrée (fausse croupe)
	local gx = ctx.DoorX
	if info.Shape ~= "Flat" then
		HouseDetail.Phase(kit, "Roof")
		local gw = WorldLayout.HALL_W / 2 + 3
		local yb = ctx.Top + 0.65
		local rise = gw * 0.75
		HouseDetail.GableX(kit, "CrossGable", -0.3, 0.7, gx - gw, gx + gw, yb, yb + rise, ctx.Wall, ctx.WallMat, { Solid = true, Shadow = true })
		for _, s in ipairs({ -1, 1 }) do
			HouseDetail.Rod(kit, "CrossRoof", { gx + s * (gw + 1.2), yb - 0.6, 3.2 }, { gx, yb + rise + 0.35, 3.2 }, 8.6, 0.55, ctx.Roof, spec.RoofMat, { Solid = true },
				Vector3.new(0, 0, 1))
			HouseDetail.Rod(kit, "CrossBarge", { gx + s * (gw + 1.2), yb - 0.75, -1.05 }, { gx, yb + rise + 0.2, -1.05 }, 0.9, 0.4, ctx.Trim, M.Wood, { Shadow = false },
				Vector3.new(0, 0, 1))
		end
		-- fenêtre ronde + balconnet du pignon
		kit:CylD("GableWindowRing", gx, yb + rise * 0.42, -0.4, 3, 0.3, ctx.Trim, M.Wood, { Shadow = false })
		kit:CylD("GableWindow", gx, yb + rise * 0.42, -0.56, 2.2, 0.1, P.Glass, M.Glass, { Shadow = false })
		-- faux-entrait sculpté (croix)
		kit:Box("GableTie", gx - gw + 1, gx + gw - 1, yb + 0.6, yb + 1.1, -0.5, -0.3, ctx.Trim, M.Wood, { Shadow = false })
	end
	roofChimney(ctx, info, ctx.Left + (ctx.Right - ctx.Left) * 0.25, ctx.Depth * 0.6, true)
	-- entrée : porte rustique, avant-toit de chalet
	HouseDetail.Phase(kit, "Openings")
	local yDoor = WorldLayout.FloorY(1)
	local yTopDoor = yDoor + WorldLayout.DOOR_H
	frontDoor(ctx)
	porchCover(ctx, spec.Porch, yTopDoor + 0.3, yTopDoor + 2.3, 3.2)
	entranceLights(ctx, yDoor, -0.5, 1)
	HouseDetail.Phase(kit, "Foundation")
	local foot = porch(ctx, gx - 5, gx + 5, 3.2, 3, stone, M.Slate)
	HouseDetail.Phase(kit, "Openings")
	local plateY = if dims.Floors >= 2 then WorldLayout.FloorY(2) + 1 else yTopDoor + 2.6
	if dims.Floors >= 2 then
		namePlate(ctx, gx, WorldLayout.FloorY(2) - 3.3, -0.66, 6.4)
	else
		namePlate(ctx, gx, math.min(plateY, ctx.Top + 1.2), -0.36, 6.4)
	end
	-- jardin : sapins, bûcher, rocher, allée, clôture
	HouseDetail.Phase(kit, "Garden")
	pine(ctx, ctx.Left - 10, 4, 1.25)
	pine(ctx, ctx.Left - 5, 14, 0.9)
	-- bûcher (tas de bûches sous auvent) contre le pignon gauche
	local wx = L - 1.6
	ctx.G:Box("WoodpileRoof", wx - 1.6, wx + 0.9, 5.2, 5.5, 4, 14, ctx.Roof, spec.RoofMat, { Shadow = false })
	for row = 0, 3 do
		for k = 0, 4 do
			ctx.G:CylD("Log", wx - 0.4 + (row % 2) * 0.25, 0.45 + row * 0.85, 5 + k * 1.9 + (row % 2) * 0.9, 0.85, 1.8, Color3.fromRGB(150, 108, 70):Lerp(Color3.fromRGB(196, 150, 104), (k + row) % 3 * 0.25), M.Wood,
				{ Shadow = false })
		end
	end
	ctx.G:Ball("Boulder", ctx.Right + 5, 0.5, -8, 3.2, Color3.fromRGB(150, 146, 140), M.Rock, { Solid = true })
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		bush(ctx, x0 + 3, -2.4, 3, 2.2, P.LeafDark)
		flowerDots(ctx, x0 + 5, x1 - 5, -1.8, 5)
	end
	sideGarage(ctx)
	local pathPoints = { { 0, -21.5 }, { gx * 0.5, -12 }, { gx, foot - 1.2 } }
	gardenFront(ctx, ctx.Left - 4, ctx.Right + 4, 0, pathPoints, 3)
	HouseDetail.Path(ctx.G, { { 0, -29.5 }, { 0, -21.6 } }, 3, if spec.Path == "Stones" then "Gravel" else spec.Path)
	gardenLights(ctx, pathPoints)
	local _ = hallHoles
end

----------------------------------------------------------------------
-- (v10) 🏙️ Villa moderne (toutes tailles)
----------------------------------------------------------------------

STYLES.Modern = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local spec = ctx.Spec
	local T = WorldLayout.WALL_T
	local L, R = ctx.Left - T, ctx.Right + T
	local dark = ctx.Trim
	local cladding = Color3.fromRGB(176, 124, 82)
	local holes, list, hallHoles = openings(ctx, function(floor)
		local yFloor = WorldLayout.FloorY(floor)
		-- fente vitrée de la cage, presque toute la hauteur de l'étage
		return { ctx.DoorX - 1.6, ctx.DoorX + 1.6, yFloor + 0.8, yFloor + 11 }
	end)
	bodyWalls(ctx, holes, Color3.fromRGB(96, 98, 104), M.Concrete)
	-- volume de l'entrée en saillie, bardé de bois (lames verticales)
	HouseDetail.Phase(kit, "Walls")
	local hx0, hx1 = ctx.Hall0 - 0.4, ctx.Hall1 + T + 0.4
	local cladTop = ctx.Top + 2.4
	kit:WallX("Cladding", hx0, hx1, WorldLayout.PLINTH, cladTop, -1.1, -0.3, hallHoles, cladding, M.WoodPlanks, { Solid = true })
	for _, x in ipairs({ hx0, hx1 - 0.8 }) do
		kit:Box("CladdingSide", x, x + 0.8, WorldLayout.PLINTH, cladTop, -1.1, -0.3, cladding, M.WoodPlanks, { Shadow = false })
	end
	kit:Box("CladdingCap", hx0 - 0.15, hx1 + 0.15, cladTop, cladTop + 0.4, -1.3, ctx.Depth + 0.3, dark, M.Metal, { Solid = true })
	kit:Box("CladdingUpper", hx0, hx1, ctx.Top + 0.65, cladTop, -0.3, ctx.Depth + 0.3, cladding, M.WoodPlanks, { Solid = true })
	local n = math.floor((hx1 - hx0) / 1.2)
	for k = 1, n - 1 do
		local x = hx0 + k * (hx1 - hx0) / n
		kit:Box("CladdingJoint", x - 0.05, x + 0.05, WorldLayout.PLINTH + 0.1, cladTop - 0.1, -1.18, -1.08, cladding:Lerp(BLACK, 0.3), M.Wood, { Shadow = false })
	end
	frontWindows(ctx, list, dark, M.Metal, { HallStyle = "Modern", Sill = dark, NoArch = true })
	-- ailettes horizontales (brise-soleil) entre les étages + balcons de verre
	HouseDetail.Phase(kit, "Walls")
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor) - WorldLayout.SLAB
		kit:Box("Fin", L - 0.4, hx0, y - 0.25, y + 0.35, -1.6, -0.3, dark, M.SmoothPlastic, { Shadow = true })
		kit:Box("Fin", hx1, R + 0.4, y - 0.25, y + 0.35, -1.6, -0.3, dark, M.SmoothPlastic, { Shadow = true })
		HouseDetail.Phase(kit, "Openings")
		for column = 1, dims.Columns do
			for _, r in ipairs(HouseFacade.WindowRects(ctx.Size, column, floor, spec)) do
				HouseDetail.Balcony(kit, spec.Balcony, r[1] - 0.6, r[2] + 0.6, y + WorldLayout.SLAB, 2, -1.6, dark)
			end
		end
		HouseDetail.Phase(kit, "Walls")
	end
	-- toit plat en débord (ou l'option choisie)
	local info = mainRoof(ctx, L, R, { Over = 1.6, Pitch = 0.35, Hip = 12, Pipes = { L + 0.9 }, MansardRise = 8, Inset = 5, Fascia = dark })
	roofChimney(ctx, info, ctx.Left + (ctx.Right - ctx.Left) * 0.3, ctx.Depth * 0.6, false)
	-- entrée
	HouseDetail.Phase(kit, "Openings")
	local gx = ctx.DoorX
	local yDoor = WorldLayout.FloorY(1)
	local yTopDoor = yDoor + WorldLayout.DOOR_H
	frontDoor(ctx)
	porchCover(ctx, spec.Porch, yTopDoor + 0.4, yTopDoor + 1.6, 3.2)
	entranceLights(ctx, yDoor, -1.1, 1)
	HouseDetail.Phase(kit, "Foundation")
	local foot = porch(ctx, gx - 5, gx + 5, 3.2, 3, Color3.fromRGB(200, 198, 194), M.Concrete)
	HouseDetail.Phase(kit, "Openings")
	-- lettres du nom sur le bardage (au-dessus de l'auvent)
	namePlate(ctx, gx, yTopDoor + 2.2, -1.1, 6.4)
	-- jardin : gazon, massifs de graminées, olivier en bac, allée de dalles
	HouseDetail.Phase(kit, "Garden")
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		ctx.G:Box("GravelBed", x0 + 2, x1 - 2, -0.08, 0.06, -4.4, -1.2, Color3.fromRGB(220, 214, 204), M.Pebble, { Shadow = false })
		for k = 0, 4 do
			local x = x0 + 4 + k * (x1 - x0 - 8) / 4
			ctx.G:Cone("Grass", x, 0, -2.8, 0.9, 1.9, 6, Color3.fromRGB(150, 170, 110):Lerp(Color3.fromRGB(196, 186, 130), (k % 2) * 0.4), M.Grass)
		end
	end
	local ox = ctx.Left - 7
	ctx.G:Box("Planter", ox - 2, ox + 2, 0, 1.6, -9, -5, Color3.fromRGB(80, 82, 88), M.Concrete, { Solid = true })
	ctx.G:CylY("OliveTrunk", ox, 1.6, -7, 0.5, 3.6, Color3.fromRGB(120, 110, 96), M.Wood, { Shadow = false })
	for index, b in ipairs({ { 0, 6.2, 0, 3.4 }, { -1.3, 5.6, 0.4, 2.4 }, { 1.2, 5.8, -0.3, 2.6 } }) do
		ctx.G:Ball("OliveLeaves", ox + b[1], b[2], -7 + b[3], b[4], Color3.fromRGB(130, 150, 110):Lerp(Color3.fromRGB(160, 170, 140), index * 0.15), M.Grass, { Shadow = true })
	end
	sideGarage(ctx)
	local pathPoints = { { 0, -21.5 }, { 0, -9 }, { gx, -9 }, { gx, foot } }
	gardenFront(ctx, ctx.Left - 4, ctx.Right + 4, 0, pathPoints, 3.6)
	HouseDetail.Path(ctx.G, { { 0, -29.5 }, { 0, -21.6 } }, 3.6, spec.Path)
	gardenLights(ctx, { { 0, -21 }, { 0, -10 } })
end

----------------------------------------------------------------------
-- (v10) Limites de la parcelle (côtés + haie du fond) : construites ICI
-- (client, avec la maison et ses LOD) depuis que le serveur ne les fait plus
----------------------------------------------------------------------

local PLOT_HALF = WorldLayout.PLOT_W / 2 - 0.4 -- 87,6
local PLOT_FRONT = -WorldLayout.GARDEN_D + 6 -- -24 : les côtés commencent après le jardin de devant
local PLOT_BACK = WorldLayout.PLOT_D - WorldLayout.GARDEN_D - 1.35 -- 52,65 : haie du fond

local function plotBounds(ctx: Ctx)
	HouseDetail.Phase(ctx.Kit, "Garden")
	local kind = ctx.Spec.Fence
	local sideKind = if kind == "Iron" then "Rail" else kind
	if kind ~= "None" then
		for _, s in ipairs({ -1, 1 }) do
			-- sous-kit tourné : son axe x suit la profondeur d de la maison
			local sub = ctx.G:Sub(CFrame.new(s * PLOT_HALF, 0, 0) * CFrame.Angles(0, math.pi / 2, 0))
			HouseDetail.Fence(sub, PLOT_FRONT, PLOT_BACK - 1.2, 0, { Kind = sideKind, Gate0 = 0, Gate1 = 0, NoGate = true })
		end
	end
	HouseDetail.Fence(ctx.G, -PLOT_HALF + 0.4, PLOT_HALF - 0.4, PLOT_BACK, { Kind = "Hedge", Gate0 = 0, Gate1 = 0, NoGate = true })
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function HouseFacade.Build(kit: any, size: any, looks: Looks): Built
	local dims = WorldLayout.Dims(size)
	local spec = HouseFacade.Resolve(size, looks)
	local style = spec.Style
	local hall0, hall1 = WorldLayout.HallSpan(size)
	local built: Built = { Door = nil, Hinge = nil, Lock = nil, Fills = {}, Chimneys = 0, ChimneysExpected = 0, Style = style, Arch = spec.Arch, Spec = spec, Leaves = nil,
		BackLeaves = nil, BackFills = {} }
	local wall = spec.Wall
	local ctx: Ctx = {
		Kit = kit,
		G = kit:Sub(CFrame.new(0, HouseKit.LAWN, 0)),
		Size = size,
		Dims = dims,
		Style = style,
		Looks = looks,
		Spec = spec,
		Wall = if style == "Loft" and spec.Arch == "Classic" and looks.Wall then (looks.Wall :: Color3):Lerp(BLACK, 0.06) else wall,
		WallMat = spec.WallMat,
		WallDark = wall:Lerp(C.Ink, 0.22),
		Roof = spec.Roof,
		RoofDark = spec.Roof:Lerp(BLACK, 0.28),
		Trim = spec.Trim,
		Left = dims.Left,
		Right = dims.Left + dims.Width,
		Top = WorldLayout.FloorY(dims.Floors) + WorldLayout.WALL_H,
		Depth = dims.Depth,
		Hall0 = hall0,
		Hall1 = hall1,
		DoorX = WorldLayout.DoorX(size),
		Built = built,
		Garage = style == "Mansion" and GarageLayout.Supports(size) and hasGarage(kit, looks),
		SideGarage = style ~= "Mansion" and spec.Garage ~= "None",
	}
	local builder = if spec.Arch ~= "Classic" then STYLES[spec.Arch] else STYLES[style]
	;(builder or STYLES.Cottage)(ctx)
	-- déco du jardin choisie dans la maison 2D : mêmes places (de gauche à droite)
	-- (v9.6 : avec le garage, elle s'arrête avant l'aile)
	HouseDetail.Phase(kit, "Garden")
	local decoRight = if ctx.Garage then GarageLayout.X0 - 3 elseif ctx.SideGarage then ctx.Right + 1 else dims.Left + dims.Width + 4
	HouseGarden.Decorations(ctx.G, looks.Garden, dims.Left - 4, decoRight, -15, style == "Mansion")
	plotBounds(ctx)
	HouseDetail.Phase(kit, nil)
	return built
end

return HouseFacade
