--[[
	House3DScene (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DScene

	Construit la "maison de poupée" 3D d'UNE pièce pour la vue 3D (House3D),
	loin du monde (autour de ORIGIN), dans un Folder du Workspace. v9.1 :
	TOUT est en vraie géométrie 3D, avec des Parts OPAQUES de taille
	normale (aucune pièce géante, aucune pièce invisible qui porte le
	décor) :
	  - studio : grande boîte pastel (Parts opaques) + pelouse sur un socle ;
	  - pièce : dalle, sol (couleur + matière du sol de la pièce), mur du
	    fond et murs de côté (coque + "peau" couleur du papier peint),
	    plinthes, moulures, poutre, fenêtre en relief (cadre, croisillon,
	    rebord, tringle, rideaux, vue dessinée sur la vitre), prise ;
	    les motifs (papier peint, sol) ne sont qu'une DÉCORATION facultative
	    (SurfaceGui de taille fixe sur la face d'une pièce normale) : la
	    couleur de la pièce suffit déjà ;
	  - objets (v9.3) : TOUS en vrais modèles 3D (House3DRecipes +
	    House3DCritters / House3DObjects / House3DToys), aux couleurs du
	    dessin 2D de l'objet (et de sa variante de couleur), jamais de carton
	    découpé ; placés par House3DLayout (posés SUR le vrai dessus 3D des
	    meubles, chaises tournées vers leur table, F = miroir, R = rotation) ;
	    arrivée en douceur et respiration des animaux (BulkMoveTo, ≤ 30 Hz) ;
	  - lumières : plafonnier, soleil de la fenêtre (SpotLight), lampes
	    (PointLight), ambiance de la pièce (Room.Mood : couleur, intensité,
	    petites particules) ; l'éclairage du lieu est réglé par House3D
	    (scene.Lighting) et remis à la fermeture.

	v9.6 ("le mode 3D c'est n'importe quoi") : la maquette a les MÊMES
	mesures que la pièce de la maison en ville (WorldLayout.PX / DEPTH /
	WALL_H) : mêmes places d'objets qu'en ville (écart mesuré 0 stud au lieu
	de 2,5), fenêtre à la place de la fenêtre 2D (aperçu et ville) ; lumières
	douces (≤ 1,2, soleil 1,6 au plus, exposition ≤ 0, éclair d'orage doux).

	Champs de pièce lus (tous facultatifs, valeurs par défaut sinon) :
	  Wallpaper, Floor, Trim (Config.HouseTrimsById), Mood
	  (Config.HouseMoodsById), View (Config.HouseViewsById) ; objets :
	  { I, X, Y, S, Z, F, C, R } (C = variante de couleur, HouseTints ;
	  R = rotation en degrés, multiple de 15, monde "Dopamine Town").

	API :
	  House3DScene.new(room, sizeId, night) -> Scene   (décor construit tout de suite)
	  scene.BuildItems(alive, progress?)   objets, étalés sur plusieurs images (yield)
	  scene.SetNight(night)
	  scene.Lighting(night) -> { [propriété de Lighting]: valeur }
	  scene.UpdateWalls(eye)   baisse le mur de côté entre la caméra et la pièce
	  scene.Step(dt)           arrivée des objets, ambiance (appelé chaque image)
	  scene.Destroy()

	API du monde (v9.3, Dopamine Town : n'utilise ni la vue 3D, ni la
	caméra, ni l'interface ; utilisable depuis n'importe quel script client) :
	  House3DScene.BuildRoomShell(roomData, sizeDef?, options?) -> Model "RoomShell"
	    options : Scale (studs par px de la pièce 2D ; 32/760 = ~32 studs de
	    large), Depth (24), WallHeight (14), Doors ({ "Front" } ; "Left",
	    "Right", "Back"), DoorWidth (6), DoorHeight (9), Front (true = mur
	    avant), Ceiling (false), Patterns (true = motifs décoratifs).
	    PrimaryPart "Floor" ; pivot = centre du dessus du sol ; mur du fond
	    vers -Z, avant (porte) vers +Z ; sol et murs solides (CanCollide),
	    vraies ouvertures de porte ; attributs Width, Depth, WallHeight,
	    Scale, RoomWpx.
	  House3DScene.PlaceItems(roomModel, roomData, options?) -> { Model }
	    options : Night, Collide, Query, Yield. Construit les objets (voir
	    House3DRecipes.BuildItem) dans roomModel.Items, avec le même passage
	    2D -> 3D que la vue 3D (au pivot ACTUEL de la coque) ; attribut
	    "EntryIndex" = index dans roomData.Placed ; entry.R = rotation.
	  Devant d'un modèle d'objet = -Z (convention LookVector de Roblox).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseCommon = require(script.Parent.HouseCommon)

-- v9.5 🖥️ objets "Dopamine Setup" vivants dans l'aperçu (World/LiveProps, chargé à la demande)
local liveProps: any = nil
local function getLiveProps(): any
	if liveProps == nil then
		local ok, result = pcall(function()
			local world = script.Parent.Parent.Parent:FindFirstChild("World")
			local module = world and world:FindFirstChild("LiveProps")
			return module and require(module :: ModuleScript) or false
		end)
		liveProps = ok and result or false
	end
	return liveProps or nil
end
local HousePatterns = require(script.Parent.HousePatterns)
local House3DFloor = require(script.Parent.House3DFloor)
local House3DKit = require(script.Parent.House3DKit)
local House3DLayout = require(script.Parent.House3DLayout)

type Placed = HouseCommon.Placed

local House3DScene = {}

House3DScene.ORIGIN = Vector3.new(0, 5000, 0) -- loin du monde (au-dessus de tout)
House3DScene.FOLDER_NAME = "House3DPreview"

-- v9.6 (PREVIEW96) : la maquette a EXACTEMENT les mesures d'une pièce de la
-- maison en ville (WorldLayout : 0,036 stud / px, 24 de profondeur, 12 sous
-- plafond). Avant : 0,05 / 22 / 10,1 -> pièce 1,4 fois plus large mais
-- moins profonde, objets tassés vers l'avant et décalés jusqu'à 2,5 studs
-- par rapport à la même pièce en ville.
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local PX = tonumber(WorldLayout.PX) or 0.036 -- studs par px de maquette de la pièce 2D
local ROOM_BASE_WIDTH = 760 -- (= HouseRoom.BASE_WIDTH)
local ROOM_HEIGHT = 440 -- (= HouseRoom.HEIGHT)
local SIDE_PX = 42 -- murs de côté en perspective de la pièce 2D (HouseRoom)
local DEPTH = tonumber(WorldLayout.DEPTH) or 24 -- (studs) profondeur de la pièce
local WALL_H = tonumber(WorldLayout.WALL_H) or 12 -- (studs) hauteur des murs
local DEPTH_PX = math.floor(DEPTH / PX)
local WALL_PX = math.floor(WALL_H / PX) -- hauteur des toiles des murs (motifs non étirés)
local WALL_T = 0.8 -- épaisseur de la coque
local SKIN = 0.1 -- épaisseur de la "peau" papier peint
local SLAB = 1.2
local LAWN_SIDE = 4
local LAWN_FRONT = 5
local LAWN_BACK = 3
local MAX_LAMPS = 8 -- vraies lumières d'objets au plus
-- v9.6 ("flash bang") : lumières douces, jamais plus de 1,2 de luminosité
local LIGHT_MAX = 1.2
local function soft(brightness: number): number
	return math.clamp(brightness, 0, LIGHT_MAX)
end
local DROP = 1.4 -- (studs) les objets tombent doucement à leur place
local DROP_TIME = 0.45
local BATCH_ITEMS = 4
local BATCH_TIME = 0.008

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local SHELL = Color3.fromRGB(252, 214, 232)
local BASE_PINK = Color3.fromRGB(242, 188, 216)
local GRASS = Color3.fromRGB(140, 214, 140)
local CREAM = Color3.fromRGB(255, 247, 236)
local M = Enum.Material

-- Studio (fond) : bandes du bas vers le haut (jour / nuit)
local SKY_DAY = { Color3.fromRGB(255, 236, 228), Color3.fromRGB(255, 222, 238), Color3.fromRGB(226, 226, 255), Color3.fromRGB(196, 222, 255), Color3.fromRGB(176, 212, 255) }
local SKY_NIGHT = { Color3.fromRGB(120, 84, 150), Color3.fromRGB(86, 62, 132), Color3.fromRGB(58, 46, 112), Color3.fromRGB(36, 32, 86), Color3.fromRGB(22, 20, 62) }

local DEFAULT_MOOD = { Tint = WHITE, Amount = 0, Light = Color3.fromRGB(255, 244, 230), Brightness = 1, Effect = "None" }

export type Scene = {
	Folder: Folder,
	Width: number,
	Depth: number,
	WallHeight: number,
	Focus: Vector3,
	BoundsMin: Vector3,
	BoundsMax: Vector3,
	FrontZ: number,
	ItemCount: number,
	BuildItems: (alive: () -> boolean, progress: ((done: number, total: number) -> ())?) -> (),
	SetNight: (night: boolean) -> (),
	Lighting: (night: boolean) -> { [string]: any },
	UpdateWalls: (eye: Vector3) -> (),
	Step: (dt: number) -> (),
	Destroy: () -> (),
}

type Build = House3DLayout.Build
type Pet = { Parts: { BasePart }, Finals: { CFrame }, Phase: number, Amount: number }

type SideWall = {
	Side: number,
	Shell: BasePart,
	Skin: BasePart,
	Crown: BasePart,
	Skirt: BasePart,
	Edge: BasePart,
	Gui: SurfaceGui?,
	Lowered: boolean,
	-- (v9.6) écarts anti-scintillement de la pose "levée" (gardés en baissant / relevant)
	Deltas: { [BasePart]: { P: Vector3, S: Vector3 } }?,
}

type Arrival = { Parts: { BasePart }, Finals: { CFrame }, Delay: number, Clock: number }

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local newPart = House3DKit.NewPart

-- Déplace beaucoup de pièces d'un coup (BulkMoveTo ; sinon une par une)
local function moveParts(parts: { BasePart }, cframes: { CFrame })
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for index, p in ipairs(parts) do
			p.CFrame = cframes[index]
		end
	end
end

local function noise(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

local function finite(value: any, default: number): number
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return default
	end
	return number
end

local function requireSibling(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

local function configTable(name: string): { [string]: any }
	local okConfig, Config = pcall(function()
		return require(ReplicatedStorage.Shared.Config)
	end)
	if okConfig and type(Config) == "table" and type((Config :: any)[name]) == "table" then
		return (Config :: any)[name]
	end
	return {}
end

local function asColor(value: any, default: Color3): Color3
	if typeof(value) == "Color3" then
		return value
	end
	return default
end

-- Fenêtre de la pièce 2D (HouseRoom : à gauche, 104 x 92 px, 36 px sous le
-- haut du mur) -> rectangle sur le mur du fond, avec le MÊME passage 2D -> 3D
-- que les objets muraux (House3DLayout) : (centre x, centre y, largeur,
-- hauteur) en studs. v9.6 : aperçu ET ville (un tableau posé à côté de la
-- fenêtre en 2D ne la chevauche plus en 3D)
local function windowRect(roomWpx: number, scale: number): (number, number, number, number)
	local wallPx = math.floor(ROOM_HEIGHT * (tonumber(HouseCommon.Config.WallRatio) or 0.46) + 0.5)
	local k = roomWpx / math.max(1, roomWpx - 2 * SIDE_PX)
	local x2D = SIDE_PX + math.floor(roomWpx * 0.1) + 52
	local cx = ((x2D - SIDE_PX) * k - roomWpx / 2) * scale
	local ww, wh = 104 * k * scale, 92 * scale
	local cy = (wallPx - 36) * scale - wh / 2
	return cx, cy, ww, wh
end

-- Matière d'un mur / d'un sol selon son motif (la couleur suffit déjà)
local WALL_MATERIAL: { [string]: Enum.Material } = {
	Bricks = M.Brick,
	Wood = M.WoodPlanks,
}
local FLOOR_MATERIAL: { [string]: Enum.Material } = {
	Wood = M.WoodPlanks,
	Herringbone = M.WoodPlanks,
	Carpet = M.Fabric,
	Marble = M.Marble,
	Tiles = M.SmoothPlastic,
	Checker = M.SmoothPlastic,
	Grass = M.Grass,
	Terrazzo = M.Marble,
	Mosaic = M.SmoothPlastic,
	Clouds = M.Fabric,
	Starry = M.SmoothPlastic,
	Concrete = M.Concrete,
	Court = M.WoodPlanks,
	Turf = M.Grass,
	TreadPlate = M.DiamondPlate,
	Road = M.Asphalt,
	Lava = M.CrackedLava,
}

----------------------------------------------------------------------
-- Scène
----------------------------------------------------------------------

function House3DScene.new(room: any, sizeId: string?, startNight: boolean?): Scene
	local config = HouseCommon.Config
	local size = HouseCommon.SizesById[sizeId or ""] or config.Sizes[1]
	local widthFactor = tonumber(size and size.Width) or 1
	local roomWpx = math.floor(ROOM_BASE_WIDTH * widthFactor + 0.5)
	local W = roomWpx * PX
	-- (murs de la ville : la bande murale 2D en occupe le bas, comme en ville)
	local WH = WALL_H
	local D = DEPTH
	local origin = House3DScene.ORIGIN
	local roomData = type(room) == "table" and room or {}
	local wallpaper = HouseCommon.GetRoomWallpaper(roomData)
	local floorStyle = HouseCommon.GetRoomFloor(roomData)
	local wallA = wallpaper and wallpaper.A or C.PinkSoft
	local floorA = floorStyle and floorStyle.A or C.Lilac
	local night = startNight == true
	local destroyed = false

	-- Personnalisation (v9.1) : moulures, ambiance, vue de la fenêtre
	local trimEntry = configTable("HouseTrimsById")[tostring(roomData.Trim or "Cream")]
	local trim = asColor(type(trimEntry) == "table" and trimEntry.Color, CREAM)
	local moodRaw = configTable("HouseMoodsById")[tostring(roomData.Mood or "Sunny")]
	local mood = {
		Tint = asColor(type(moodRaw) == "table" and moodRaw.Tint, DEFAULT_MOOD.Tint),
		Amount = math.clamp(finite(type(moodRaw) == "table" and moodRaw.Amount, 0), 0, 1),
		Light = asColor(type(moodRaw) == "table" and moodRaw.Light, DEFAULT_MOOD.Light),
		Brightness = math.clamp(finite(type(moodRaw) == "table" and moodRaw.Brightness, 1), 0.2, 2),
		Effect = type(moodRaw) == "table" and type(moodRaw.Effect) == "string" and moodRaw.Effect or "None",
	}
	local views = configTable("HouseViewsById")
	local viewEntry = views[tostring(roomData.View or "Garden")] or views.Garden
	local HouseViews = requireSibling("HouseViews")

	local folder = Instance.new("Folder")
	folder.Name = House3DScene.FOLDER_NAME

	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end
	local X_AXIS = Vector3.new(1, 0, 0)
	local Y_AXIS = Vector3.new(0, 1, 0)
	local BACKWARD = Vector3.new(0, 0, -1)

	local function part(name: string, sizeV: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
		local p = newPart("Part", name, sizeV, cframe, color, material)
		p.CastShadow = shadow == true
		p.Parent = folder
		return p
	end
	-- Pièce orientée (droite, haut) : la face Back (+Z local) regarde `right x up`
	local function facing(name: string, center: Vector3, right: Vector3, up: Vector3, w: number, h: number, t: number, color: Color3, material: Enum.Material?): BasePart
		local normal = right:Cross(up)
		return part(name, Vector3.new(w, h, t), CFrame.fromMatrix(center - normal * (t / 2), right, up), color, material)
	end

	-- Ce qui change la nuit / avec l'ambiance
	local skyBands: { { Part: BasePart, Index: number } } = {}
	local viewHolders: { Frame } = {}
	local itemLights: { { Light: PointLight, Base: number } } = {}
	local glowParts: { BasePart } = {}
	local ceilingLight: PointLight? = nil
	local fillLight: PointLight? = nil
	local sunLight: SpotLight? = nil
	local sideWalls: { SideWall } = {}
	local arrivals: { Arrival } = {}
	local effects: { ParticleEmitter } = {}
	local discoClock = 0
	local stormClock = 0

	------------------------------------------------------------------
	-- Studio : boîte pastel en bandes (Parts opaques, pas d'ombre)
	------------------------------------------------------------------
	local centerZ = D / 2
	local HX, HZ = 110, 110
	local yMin, yMax = -40, 110
	local bands = #SKY_DAY
	local bandH = (yMax - yMin) / bands
	for index = 1, bands do
		local y = yMin + (index - 0.5) * bandH
		for _, spec in ipairs({
			{ "Back", Vector3.new(0, y, centerZ - HZ), Vector3.new(HX * 2 + 2, bandH + 0.2, 1) },
			{ "Front", Vector3.new(0, y, centerZ + HZ), Vector3.new(HX * 2 + 2, bandH + 0.2, 1) },
			{ "Left", Vector3.new(-HX, y, centerZ), Vector3.new(1, bandH + 0.2, HZ * 2 + 2) },
			{ "Right", Vector3.new(HX, y, centerZ), Vector3.new(1, bandH + 0.2, HZ * 2 + 2) },
		}) do
			local p = part("Studio" .. spec[1] .. index, spec[3], CFrame.new(at(spec[2].X, spec[2].Y, spec[2].Z)), SKY_DAY[index], M.SmoothPlastic, false)
			table.insert(skyBands, { Part = p, Index = index })
		end
	end
	table.insert(skyBands, { Part = part("StudioTop", Vector3.new(HX * 2 + 2, 1, HZ * 2 + 2), CFrame.new(at(0, yMax, centerZ)), SKY_DAY[bands], M.SmoothPlastic, false), Index = bands })
	table.insert(skyBands, { Part = part("StudioBottom", Vector3.new(HX * 2 + 2, 1, HZ * 2 + 2), CFrame.new(at(0, yMin, centerZ)), SKY_DAY[1], M.SmoothPlastic, false), Index = 1 })
	-- Nuages (boules blanches, derrière la maison)
	for index = 1, 6 do
		local cx = -90 + index * 26 + (noise(index, 1) - 0.5) * 12
		local cy = -2 + noise(index, 2) * 8
		local cz = centerZ - HZ + 6 + noise(index, 3) * 8
		for puff = 0, 2 do
			local ball = part("Cloud", Vector3.new(1, 1, 1) * (5 + puff % 2 * 2), CFrame.new(at(cx + (puff - 1) * 4, cy + (puff % 2) * 1.5, cz)), WHITE, M.SmoothPlastic, false)
			;(ball :: Part).Shape = Enum.PartType.Ball
			table.insert(skyBands, { Part = ball, Index = 0 })
		end
	end

	------------------------------------------------------------------
	-- Socle : pelouse sur un gâteau rose
	------------------------------------------------------------------
	local lawnW = W + WALL_T * 2 + LAWN_SIDE * 2
	local lawnZ0 = -WALL_T - LAWN_BACK
	local lawnZ1 = D + LAWN_FRONT
	local lawnD = lawnZ1 - lawnZ0
	local lawnTop = -SLAB
	part("Lawn", Vector3.new(lawnW, 0.8, lawnD), CFrame.new(at(0, lawnTop - 0.4, (lawnZ0 + lawnZ1) / 2)), GRASS, M.Grass, false)
	part("Base", Vector3.new(lawnW - 0.9, 2.6, lawnD - 0.9), CFrame.new(at(0, lawnTop - 0.8 - 1.3, (lawnZ0 + lawnZ1) / 2)), BASE_PINK, M.SmoothPlastic, false)
	part("BaseTrim", Vector3.new(lawnW - 0.3, 0.35, lawnD - 0.3), CFrame.new(at(0, lawnTop - 0.8 - 2.5, (lawnZ0 + lawnZ1) / 2)), CREAM, M.SmoothPlastic, false)
	-- Petites fleurs et buissons sur la pelouse (autour de la maison)
	local flowerColors = { C.Pink, Color3.fromRGB(255, 226, 130), WHITE, C.Lilac }
	for index = 1, 26 do
		local side = index % 3
		local x, z
		if side == 0 then
			x = -lawnW / 2 + 1 + noise(index, 1) * (lawnW - 2)
			z = D + 1 + noise(index, 2) * (LAWN_FRONT - 2)
		elseif side == 1 then
			x = -W / 2 - WALL_T - 1 - noise(index, 3) * (LAWN_SIDE - 2)
			z = lawnZ0 + 1 + noise(index, 4) * (lawnD - 2)
		else
			x = W / 2 + WALL_T + 1 + noise(index, 5) * (LAWN_SIDE - 2)
			z = lawnZ0 + 1 + noise(index, 6) * (lawnD - 2)
		end
		if index % 4 == 0 then
			local bush = part("Bush", Vector3.new(1.6, 1.6, 1.6), CFrame.new(at(x, lawnTop + 0.5, z)), Color3.fromRGB(110, 190, 110), M.SmoothPlastic, true)
			;(bush :: Part).Shape = Enum.PartType.Ball
		else
			part("Stem", Vector3.new(0.12, 0.6, 0.12), CFrame.new(at(x, lawnTop + 0.3, z)), Color3.fromRGB(90, 170, 90), M.SmoothPlastic, false)
			local flower = part("Flower", Vector3.new(0.5, 0.5, 0.5), CFrame.new(at(x, lawnTop + 0.7, z)), flowerColors[index % #flowerColors + 1], M.SmoothPlastic, false)
			;(flower :: Part).Shape = Enum.PartType.Ball
		end
	end

	------------------------------------------------------------------
	-- Dalle, sol
	------------------------------------------------------------------
	-- (le dessus de la dalle reste sous le sol : pas de faces confondues)
	part("Slab", Vector3.new(W + WALL_T * 2, SLAB - 0.3, D + WALL_T), CFrame.new(at(0, -0.3 - (SLAB - 0.3) / 2, (D - WALL_T) / 2)), SHELL, M.SmoothPlastic, false)
	part("SlabTrim", Vector3.new(W + WALL_T * 2 + 0.1, 0.25, 0.25), CFrame.new(at(0, -0.12, D + 0.02)), trim, M.SmoothPlastic, false)
	do
		local pattern = floorStyle and floorStyle.Pattern or "Plain"
		-- (la "face du dessus" est la face Back d'une dalle tournée : le haut de la toile = le mur du fond)
		local floorPart = facing("Floor", at(0, 0, D / 2), X_AXIS, BACKWARD, W, D, 0.3, floorA, FLOOR_MATERIAL[pattern] or M.SmoothPlastic)
		local gui = House3DKit.Surface(floorPart, Enum.NormalId.Back, Vector2.new(roomWpx, DEPTH_PX), 1)
		local sheet = Instance.new("Frame")
		sheet.Name = "Floor"
		sheet.BackgroundTransparency = 1
		sheet.BorderSizePixel = 0
		sheet.Size = UDim2.fromScale(1, 1)
		sheet.ClipsDescendants = true
		sheet.Parent = gui
		local ok, err = pcall(House3DFloor.Paint, sheet, roomWpx, DEPTH_PX, floorStyle, 1)
		if not ok then
			warn("[House3D] Sol : " .. tostring(err))
		end
		-- (la couleur vient de la pièce : le fond de la toile reste transparent)
		sheet.BackgroundTransparency = 1
		if pattern == "Lava" then
			-- la lave éclaire la pièce par en dessous
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 130, 60)
			glow.Range = 16
			glow.Brightness = 1
			glow.Shadows = false
			glow.Parent = floorPart
		end
		-- ombres douces au pied des murs
		local back = HousePatterns.Box(sheet, 0, 0, roomWpx, 40, BLACK, 0.75, 20)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = back
	end

	------------------------------------------------------------------
	-- Murs : coque + peau (papier peint), plinthes, moulures, poutre
	------------------------------------------------------------------
	local function paper(gui: SurfaceGui, widthPx: number)
		local sheet = Instance.new("Frame")
		sheet.Name = "Paper"
		sheet.BackgroundTransparency = 1
		sheet.BorderSizePixel = 0
		sheet.Size = UDim2.fromScale(1, 1)
		sheet.ClipsDescendants = true
		sheet.Parent = gui
		local ok, err = pcall(HousePatterns.BuildWall, sheet, widthPx, WALL_PX, wallpaper, 1)
		if not ok then
			warn("[House3D] Papier peint : " .. tostring(err))
		end
		sheet.BackgroundTransparency = 1
		-- ombre au pied du mur
		local ao = HousePatterns.Box(sheet, 0, WALL_PX - 30, widthPx, 30, BLACK, 0.8, 20)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(1, 0)
		fade.Parent = ao
	end
	local wallMaterial = WALL_MATERIAL[wallpaper and wallpaper.Pattern or ""] or M.SmoothPlastic
	-- Mur du fond
	part("WallBack", Vector3.new(W + WALL_T * 2, WH + 0.4, WALL_T), CFrame.new(at(0, (WH + 0.4) / 2 - 0.2, -WALL_T / 2 - SKIN)), SHELL, M.SmoothPlastic, false)
	do
		local skin = facing("WallBackPaper", at(0, WH / 2, 0), X_AXIS, Y_AXIS, W, WH, SKIN, wallA, wallMaterial)
		local gui = House3DKit.Surface(skin, Enum.NormalId.Back, Vector2.new(roomWpx, WALL_PX), 1)
		paper(gui, roomWpx)
	end
	-- Murs de côté (se baissent quand la caméra passe derrière eux)
	local crownH = 0.45
	for _, side in ipairs({ -1, 1 }) do
		local shellPart = part(side < 0 and "WallLeft" or "WallRight", Vector3.new(WALL_T, WH + 0.4, D + WALL_T + SKIN),
			CFrame.new(at(side * (W / 2 + SKIN + WALL_T / 2), (WH + 0.4) / 2 - 0.2, (D - WALL_T - SKIN) / 2)), SHELL, M.SmoothPlastic, false)
		local right = side < 0 and BACKWARD or -BACKWARD
		local skin = facing(side < 0 and "WallLeftPaper" or "WallRightPaper", at(side * W / 2, WH / 2, D / 2), right, Y_AXIS, D, WH, SKIN, wallA:Lerp(BLACK, 0.04), wallMaterial)
		local gui = House3DKit.Surface(skin, Enum.NormalId.Back, Vector2.new(DEPTH_PX, WALL_PX), 1)
		paper(gui, DEPTH_PX)
		local crown = part("TrimCrownSide", Vector3.new(0.36, crownH, D), CFrame.new(at(side * (W / 2 - 0.18), WH - crownH / 2, D / 2)), trim, M.SmoothPlastic, false)
		local skirt = part("TrimSkirtSide", Vector3.new(0.2, 0.6, D), CFrame.new(at(side * (W / 2 - 0.1), 0.3, D / 2)), trim, M.SmoothPlastic, false)
		-- chant avant du mur (liseré)
		local edge = part("TrimEdge", Vector3.new(WALL_T + SKIN + 0.1, WH + 0.4, 0.2), CFrame.new(at(side * (W / 2 + (WALL_T + SKIN) / 2), (WH + 0.4) / 2 - 0.2, D + 0.05)), trim, M.SmoothPlastic, false)
		table.insert(sideWalls, { Side = side, Shell = shellPart, Skin = skin, Crown = crown, Skirt = skirt, Edge = edge, Gui = gui, Lowered = false })
	end
	part("TrimSkirtBack", Vector3.new(W, 0.6, 0.2), CFrame.new(at(0, 0.3, 0.1)), trim, M.SmoothPlastic, false)
	part("TrimCrownBack", Vector3.new(W, crownH, 0.36), CFrame.new(at(0, WH - crownH / 2, 0.18)), trim, M.SmoothPlastic, false)
	-- Poutre du plafond (au-dessus du mur du fond) et petits corbeaux
	part("CeilingBeam", Vector3.new(W + WALL_T * 2 + 0.4, 0.7, 1.4), CFrame.new(at(0, WH + 0.35, 0.3)), trim:Lerp(Color3.fromRGB(160, 110, 78), 0.35), M.Wood, false)
	for index = -2, 2 do
		part("BeamBracket", Vector3.new(0.5, 0.5, 0.9), CFrame.new(at(index * W / 5, WH - 0.2, 0.9)), trim:Lerp(Color3.fromRGB(160, 110, 78), 0.35), M.Wood, false)
	end

	------------------------------------------------------------------
	-- Fenêtre fixe (à gauche, comme la pièce 2D) : vraie fenêtre en relief
	------------------------------------------------------------------
	-- (v9.6 : place et taille de la fenêtre 2D, comme la pièce en ville)
	local windowCX, windowCY, windowW, windowH = windowRect(roomWpx, PX)
	do
		-- vue (panneau opaque derrière la vitre, dessiné par HouseViews)
		local view = facing("WindowView", at(windowCX, windowCY, 0.02), X_AXIS, Y_AXIS, windowW - 0.5, windowH - 0.5, 0.05, Color3.fromRGB(170, 214, 255), M.SmoothPlastic)
		view.Color = viewEntry and asColor(viewEntry.Sky, Color3.fromRGB(170, 214, 255)) or Color3.fromRGB(170, 214, 255)
		local gui = House3DKit.Surface(view, Enum.NormalId.Back, Vector2.new(200, 180), 0)
		local holder = Instance.new("Frame")
		holder.Name = "View"
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.fromScale(1, 1)
		holder.ClipsDescendants = true
		holder.Parent = gui
		table.insert(viewHolders, holder)
		-- cadre (couleur des moulures), croisillon, rebord, tringle
		local fw = 0.32
		for _, spec in ipairs({
			{ 0, windowH / 2 + fw / 2, windowW + fw * 2, fw },
			{ 0, -windowH / 2 - fw / 2, windowW + fw * 2, fw },
			{ -windowW / 2 - fw / 2, 0, fw, windowH },
			{ windowW / 2 + fw / 2, 0, fw, windowH },
			{ 0, 0, 0.16, windowH },
			{ 0, 0, windowW, 0.16 },
		}) do
			part("WindowFrame", Vector3.new(spec[3], spec[4], 0.3), CFrame.new(at(windowCX + spec[1], windowCY + spec[2], 0.15)), trim, M.SmoothPlastic, true)
		end
		local glass = part("WindowGlass", Vector3.new(windowW, windowH, 0.05), CFrame.new(at(windowCX, windowCY, 0.1)), Color3.fromRGB(220, 240, 255), M.Glass, false)
		glass.Transparency = 0.8
		part("WindowSill", Vector3.new(windowW + 1, 0.3, 0.8), CFrame.new(at(windowCX, windowCY - windowH / 2 - 0.3, 0.4)), trim, M.SmoothPlastic, true)
		local rodY = windowCY + windowH / 2 + 0.5
		local rod = part("CurtainRod", Vector3.new(windowW + 2.4, 0.16, 0.16), CFrame.new(at(windowCX, rodY, 0.5)), Color3.fromRGB(160, 110, 78), M.Wood, false)
		;(rod :: Part).Shape = Enum.PartType.Cylinder
		for _, side in ipairs({ -1, 1 }) do
			local knob = part("CurtainKnob", Vector3.new(0.4, 0.4, 0.4), CFrame.new(at(windowCX + side * (windowW / 2 + 1.2), rodY, 0.5)), C.PinkDeep, M.SmoothPlastic, false)
			;(knob :: Part).Shape = Enum.PartType.Ball
			-- rideau (tissu) retenu par une embrasse
			local cx = windowCX + side * (windowW / 2 + 0.3)
			local curtain = C.Pink:Lerp(trim, 0.15)
			for fold = 0, 2 do
				part("Curtain", Vector3.new(0.42, windowH + 0.6, 0.3), CFrame.new(at(cx + side * (fold - 1) * 0.36, rodY - (windowH + 0.6) / 2 - 0.1, 0.42 + (fold % 2) * 0.12)),
					fold % 2 == 0 and curtain or curtain:Lerp(WHITE, 0.2), M.Fabric, true)
			end
			part("CurtainTie", Vector3.new(1.4, 0.3, 0.5), CFrame.new(at(cx, windowCY - windowH * 0.08, 0.62)), C.PinkDeep, M.Fabric, false)
		end
		-- soleil de la fenêtre
		local sunAnchor = newPart("Part", "WindowLight", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(at(windowCX, windowCY, 0.9), at(windowCX + 4, 0, D * 0.6)), WHITE, nil, 1)
		sunAnchor.CastShadow = false
		sunAnchor.Parent = folder
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 70
		spot.Range = 30
		spot.Shadows = true
		spot.Parent = sunAnchor
		sunLight = spot
	end
	-- Prise électrique (à droite)
	do
		local ox = ((roomWpx - SIDE_PX - 70 + 11 - SIDE_PX) / math.max(1, roomWpx - 2 * SIDE_PX) * roomWpx - roomWpx / 2) * PX
		part("Outlet", Vector3.new(0.8, 0.95, 0.12), CFrame.new(at(ox, 1.2, 0.06)), WHITE, M.SmoothPlastic, false)
		for _, dx in ipairs({ -0.15, 0.15 }) do
			part("OutletHole", Vector3.new(0.1, 0.24, 0.05), CFrame.new(at(ox + dx, 1.26, 0.14)), Color3.fromRGB(90, 70, 90), M.SmoothPlastic, false)
		end
	end

	------------------------------------------------------------------
	-- Lumières de la pièce + ambiance
	------------------------------------------------------------------
	do
		local lamp = newPart("Part", "CeilingLight", Vector3.new(0.3, 0.3, 0.3), CFrame.new(at(0, WH - 0.6, D * 0.45)), WHITE, nil, 1)
		lamp.CastShadow = false
		lamp.Parent = folder
		local light = Instance.new("PointLight")
		light.Range = 36
		light.Shadows = false
		light.Parent = lamp
		ceilingLight = light
		local fill = Instance.new("PointLight")
		fill.Range = 40
		fill.Shadows = false
		fill.Parent = lamp
		fillLight = fill
	end
	-- Petites particules d'ambiance (Room.Mood.Effect), dans le volume de la pièce
	do
		local specs: { [string]: { Colors: { Color3 }, Rate: number, Size: number, Speed: number, Up: number, Life: number, Emission: number } } = {
			Neon = { Colors = { Color3.fromRGB(255, 80, 200), Color3.fromRGB(80, 230, 255) }, Rate = 8, Size = 0.3, Speed = 0.3, Up = 0.1, Life = 3, Emission = 1 },
			Floodlights = { Colors = { WHITE, Color3.fromRGB(230, 240, 255) }, Rate = 5, Size = 0.22, Speed = 0.2, Up = 0.05, Life = 5, Emission = 1 },
			RGB = { Colors = { Color3.fromRGB(255, 60, 90), Color3.fromRGB(90, 255, 120), Color3.fromRGB(80, 140, 255) }, Rate = 10, Size = 0.3, Speed = 0.8, Up = 0, Life = 2, Emission = 1 },
			Storm = { Colors = { Color3.fromRGB(170, 200, 255), Color3.fromRGB(120, 140, 200) }, Rate = 14, Size = 0.18, Speed = 3, Up = -6, Life = 1.2, Emission = 0.6 },
			Embers = { Colors = { Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 90, 30) }, Rate = 9, Size = 0.28, Speed = 0.6, Up = 0.8, Life = 3, Emission = 1 },
			Sparkles = { Colors = { Color3.fromRGB(255, 244, 190), WHITE }, Rate = 6, Size = 0.35, Speed = 0.3, Up = 0.2, Life = 3, Emission = 1 },
			Bubbles = { Colors = { Color3.fromRGB(190, 230, 255), WHITE }, Rate = 5, Size = 0.5, Speed = 0.6, Up = 0.5, Life = 5, Emission = 0.4 },
			Hearts = { Colors = { C.Pink, C.PinkDeep }, Rate = 5, Size = 0.45, Speed = 0.5, Up = 0.4, Life = 4, Emission = 0.7 },
			Disco = { Colors = { C.Pink, Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 226, 130), C.Lilac }, Rate = 14, Size = 0.3, Speed = 1.5, Up = 0, Life = 1.6, Emission = 1 },
			Aurora = { Colors = { Color3.fromRGB(120, 255, 200), Color3.fromRGB(170, 140, 255) }, Rate = 3, Size = 1.4, Speed = 0.2, Up = 0.1, Life = 6, Emission = 0.8 },
			Rays = { Colors = { Color3.fromRGB(255, 236, 170) }, Rate = 5, Size = 0.25, Speed = 0.15, Up = 0.05, Life = 5, Emission = 1 },
			Leaves = { Colors = { Color3.fromRGB(140, 210, 110), Color3.fromRGB(240, 190, 90) }, Rate = 4, Size = 0.45, Speed = 0.4, Up = -0.6, Life = 5, Emission = 0.2 },
			Rainbow = { Colors = { Color3.fromRGB(255, 120, 140), Color3.fromRGB(255, 210, 110), Color3.fromRGB(140, 230, 150), Color3.fromRGB(130, 190, 255), C.Lilac }, Rate = 8, Size = 0.35, Speed = 0.4, Up = 0.2, Life = 4, Emission = 1 },
		}
		local spec = specs[mood.Effect]
		if spec then
			local volume = newPart("Part", "MoodVolume", Vector3.new(W - 1, WH - 1.5, D - 2), CFrame.new(at(0, WH / 2 + 0.3, D / 2)), WHITE, nil, 1)
			volume.CastShadow = false
			volume.Parent = folder
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Mood" .. mood.Effect
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			emitter.EmissionDirection = Enum.NormalId.Top
			emitter.Rate = spec.Rate
			emitter.Lifetime = NumberRange.new(spec.Life * 0.7, spec.Life)
			emitter.Speed = NumberRange.new(spec.Speed * 0.5, spec.Speed)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Acceleration = Vector3.new(0, spec.Up, 0)
			-- (particules douces : peu d'émission, pas d'éblouissement)
			emitter.LightEmission = spec.Emission * 0.4
			emitter.LightInfluence = 0
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.2, spec.Size),
				NumberSequenceKeypoint.new(0.8, spec.Size),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.15),
				NumberSequenceKeypoint.new(0.8, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			local keys = {}
			local n = #spec.Colors
			for index, color in ipairs(spec.Colors) do
				table.insert(keys, ColorSequenceKeypoint.new(n == 1 and (index - 1) or (index - 1) / (n - 1), color))
			end
			if n == 1 then
				table.insert(keys, ColorSequenceKeypoint.new(1, spec.Colors[1]))
			end
			emitter.Color = ColorSequence.new(keys)
			emitter.RotSpeed = NumberRange.new(-60, 60)
			emitter.Parent = volume
			table.insert(effects, emitter)
		end
	end

	------------------------------------------------------------------
	-- Nuit / jour, ambiance
	------------------------------------------------------------------
	local function paintViews()
		for _, holder in ipairs(viewHolders) do
			for _, child in ipairs(holder:GetChildren()) do
				child:Destroy()
			end
			local painted = false
			if HouseViews and type(HouseViews.Paint) == "function" and type(viewEntry) == "table" then
				local ok, err = pcall(HouseViews.Paint, holder, 200, 180, viewEntry, night)
				painted = ok
				if not ok then
					warn("[House3D] Vue : " .. tostring(err))
				end
			end
			if not painted then
				-- ciel dégradé + soleil / lune + nuage
				local sky = HousePatterns.Box(holder, 0, 0, 200, 180, WHITE, 0, 1)
				local gradient = Instance.new("UIGradient")
				gradient.Rotation = 90
				gradient.Color = night and ColorSequence.new(Color3.fromRGB(24, 22, 70), Color3.fromRGB(80, 60, 150))
					or ColorSequence.new(Color3.fromRGB(150, 214, 255), Color3.fromRGB(255, 214, 236))
				gradient.Parent = sky
				HousePatterns.Circle(holder, 140, 46, 40, 40, night and Color3.fromRGB(255, 244, 200) or Color3.fromRGB(255, 230, 130), 0, 2)
				if not night then
					HousePatterns.Cloud(holder, 60, 130, 80, WHITE, 0.05, 3)
				end
				local hill = HousePatterns.Circle(holder, 100, 200, 300, 90, night and Color3.fromRGB(60, 90, 90) or Color3.fromRGB(140, 214, 140), 0, 2)
				hill.Name = "Hill"
			end
		end
	end

	local function applyNight()
		for _, band in ipairs(skyBands) do
			if band.Index == 0 then
				band.Part.Color = night and Color3.fromRGB(96, 82, 150) or WHITE
			else
				band.Part.Color = (night and SKY_NIGHT or SKY_DAY)[band.Index]
			end
		end
		paintViews()
		local lampBoost = night and 1.25 or 0.8
		for _, entry in ipairs(itemLights) do
			entry.Light.Brightness = soft(entry.Base * lampBoost * mood.Brightness)
			entry.Light.Color = entry.Light.Color
		end
		local ceiling = ceilingLight
		if ceiling then
			ceiling.Brightness = soft((night and 0.75 or 0.55) * mood.Brightness)
			ceiling.Color = night and Color3.fromRGB(255, 214, 170):Lerp(mood.Light, 0.5) or mood.Light
		end
		local fill = fillLight
		if fill then
			fill.Enabled = mood.Amount > 0.01
			fill.Color = mood.Tint
			fill.Brightness = soft(mood.Amount * 1.2)
		end
		local spot = sunLight
		if spot then
			spot.Brightness = soft((night and 0.5 or 1.1) * math.clamp(mood.Brightness, 0.4, 1))
			spot.Color = night and Color3.fromRGB(150, 170, 255) or Color3.fromRGB(255, 236, 200)
		end
	end
	applyNight()
	-- (v9.6) anti-scintillement du décor : moulures, fenêtre, rideaux...
	-- écartés des murs / du sol / du studio (qui ne bougent pas)
	pcall(House3DScene.SeparateShell, folder, nil)
	folder.Parent = workspace

	------------------------------------------------------------------
	-- Objets : vrais modèles 3D (House3DRecipes), placés par House3DLayout
	------------------------------------------------------------------
	local entries = House3DLayout.Entries(roomData)
	local dims = House3DLayout.Dims(size, PX, D, WH)
	local frame = CFrame.new(origin)
	local itemFolder = Instance.new("Folder")
	itemFolder.Name = "Items"
	itemFolder.Parent = folder
	local pets: { Pet } = {}
	local petClock = 0
	local liveHandles: { any } = {}

	-- montage dans la pièce (+ arrivée en douceur)
	local lampCount = 0
	local function mount(build: Build, delay: number)
		local model = build.Model
		model.Name = "Item_" .. tostring(build.Item.Id)
		local data = build.Data
		for _, light in ipairs(data.Lights) do
			lampCount += 1
			if lampCount > MAX_LAMPS then
				light.Enabled = false
			end
			table.insert(itemLights, { Light = light, Base = light.Brightness })
			light.Brightness = soft(light.Brightness * (night and 1.25 or 0.8) * mood.Brightness)
		end
		for _, glow in ipairs(data.Glows) do
			table.insert(glowParts, glow)
		end
		model:PivotTo(build.Pivot)
		local parts: { BasePart } = {}
		local finals: { CFrame } = {}
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				-- petit tapis : pas d'ombre
				if build.Kind == "Flat" then
					p.CastShadow = false
				end
				table.insert(parts, p)
				table.insert(finals, p.CFrame)
			end
		end
		if data.Info.Pet then
			table.insert(pets, { Parts = parts, Finals = finals, Phase = #pets * 1.7, Amount = math.clamp(data.H * 0.035, 0.03, 0.12) })
		end
		local lifted = table.create(#finals)
		for index, final in ipairs(finals) do
			lifted[index] = final + Vector3.new(0, DROP, 0)
		end
		moveParts(parts, lifted)
		model.Parent = itemFolder
		table.insert(arrivals, { Parts = parts, Finals = finals, Delay = delay, Clock = 0 })
	end

	------------------------------------------------------------------
	-- Scène (objet renvoyé)
	------------------------------------------------------------------
	local scene: Scene
	scene = {
		Folder = folder,
		Width = W,
		Depth = D,
		WallHeight = WH,
		Focus = at(0, WH * 0.36, D * 0.5),
		BoundsMin = at(-W / 2 - WALL_T, -SLAB, -WALL_T),
		BoundsMax = at(W / 2 + WALL_T, WH + 0.7, D + 0.3),
		FrontZ = origin.Z + D,
		ItemCount = #entries,
		BuildItems = function(alive: () -> boolean, progress: ((done: number, total: number) -> ())?)
			local total = #entries * 2
			local done = 0
			local builds: { Build } = {}
			local started = os.clock()
			local count = 0
			local function breathe(): boolean
				count += 1
				if count >= BATCH_ITEMS or os.clock() - started > BATCH_TIME then
					if progress then
						pcall(progress, done, total)
					end
					task.wait()
					started = os.clock()
					count = 0
				end
				return alive() and not destroyed
			end
			local function discard()
				for _, build in ipairs(builds) do
					if build.Model.Parent == nil then
						build.Model:Destroy()
					end
				end
			end
			for index, entry in ipairs(entries) do
				local ok, result = pcall(House3DLayout.Prepare, entry, index, dims, { Collide = false, Query = false, Trim = trim })
				if ok and result then
					table.insert(builds, result)
				elseif not ok then
					warn("[House3D] Objet " .. tostring(entry.I) .. " : " .. tostring(result))
				end
				done += 1
				if not breathe() then
					discard()
					return
				end
			end
			local okLayout, err = pcall(House3DLayout.Layout, builds, dims, frame)
			if not okLayout then
				warn("[House3D] Disposition : " .. tostring(err))
				for _, build in ipairs(builds) do
					if not build.Placed then
						build.Pivot = frame * CFrame.new(0, 0, D * 0.6) * CFrame.Angles(0, math.pi, 0)
					end
				end
			end
			if not alive() or destroyed then
				discard()
				return
			end
			-- (v9.6) anti-scintillement entre objets voisins et avec le décor
			-- (avant l'arrivée en douceur, qui garde les places finales)
			pcall(function()
				local models: { Instance } = {}
				for _, build in ipairs(builds) do
					build.Model:PivotTo(build.Pivot)
					table.insert(models, build.Model)
				end
				House3DScene.SeparateShell(folder, models)
			end)
			local order = table.clone(builds)
			table.sort(order, function(a, b)
				if a.Entry.Y ~= b.Entry.Y then
					return a.Entry.Y < b.Entry.Y
				end
				return a.Order < b.Order
			end)
			for index, build in ipairs(order) do
				local ok, mountErr = pcall(mount, build, 0.05 + math.min(1.2, index * 0.04))
				if not ok then
					warn("[House3D] Objet " .. tostring(build.Entry.I) .. " : " .. tostring(mountErr))
					pcall(function()
						build.Model:Destroy()
					end)
				end
				done += 1
				if not breathe() then
					discard()
					return
				end
			end
			local live = getLiveProps()
			if live then
				local okLive, handles = pcall(live.AttachAll, itemFolder:GetChildren(), { Interactive = false })
				if okLive and type(handles) == "table" then
					liveHandles = handles
				end
				-- (v9.6 : un point de focus laissé par la ville, ~2 s après la
				-- sortie, mettait les écrans de l'aperçu en pause : focus = caméra)
				if #liveHandles > 0 and type(live.SetFocus) == "function" then
					pcall(live.SetFocus, nil)
				end
			end
			applyNight()
			if progress then
				pcall(progress, total, total)
			end
		end,
		SetNight = function(value: boolean)
			if night == value then
				return
			end
			night = value
			applyNight()
		end,
		-- Éclairage du lieu pendant la vue (House3D le remet à la fermeture)
		Lighting = function(isNight: boolean): { [string]: any }
			local tint = mood.Tint
			local amount = mood.Amount
			-- v9.6 ("flash bang") : soleil plus doux, lumière ambiante moins
			-- forte (150 délavait tout dans le vrai Roblox), exposition ≤ 0
			local ambientDay = Color3.fromRGB(118, 110, 128):Lerp(tint, amount * 0.5)
			local ambientNight = Color3.fromRGB(64, 56, 110):Lerp(tint, amount * 0.4)
			local bright = mood.Brightness
			return {
				ClockTime = isNight and 0.5 or 14.5,
				Brightness = (isNight and 0.35 or 1.6) * math.clamp(bright, 0.6, 1.1),
				Ambient = isNight and ambientNight or ambientDay,
				OutdoorAmbient = isNight and Color3.fromRGB(70, 64, 120):Lerp(tint, amount * 0.4) or Color3.fromRGB(138, 132, 150):Lerp(tint, amount * 0.5),
				ColorShift_Top = isNight and Color3.fromRGB(40, 40, 90) or tint:Lerp(BLACK, 1 - amount * 0.35),
				ColorShift_Bottom = BLACK,
				EnvironmentDiffuseScale = 0.4,
				EnvironmentSpecularScale = 0.3,
				ExposureCompensation = isNight and 0 or -0.1,
				GlobalShadows = true,
				ShadowSoftness = 0.35,
				FogStart = 0,
				FogEnd = 100000,
				GeographicLatitude = 23,
			}
		end,
		UpdateWalls = function(eye: Vector3)
			local localX = eye.X - origin.X
			for _, wall in ipairs(sideWalls) do
				local outside = wall.Side * localX > W / 2 + 0.6
				local inside = wall.Side * localX < W / 2 - 1.2
				local lower = nil
				if outside and not wall.Lowered then
					lower = true
				elseif inside and wall.Lowered then
					lower = false
				end
				if lower ~= nil then
					wall.Lowered = lower
					local x = wall.Side * (W / 2 + SKIN + WALL_T / 2)
					local right = wall.Side < 0 and BACKWARD or -BACKWARD
					local normal = right:Cross(Y_AXIS)
					-- pose d'un mur de hauteur `height` (tailles, repères)
					local function pose(height: number): { { Part: BasePart, S: Vector3, C: CFrame } }
						return {
							{ Part = wall.Shell, S = Vector3.new(WALL_T, height + 0.4, D + WALL_T + SKIN), C = CFrame.new(at(x, (height + 0.4) / 2 - 0.2, (D - WALL_T - SKIN) / 2)) },
							{ Part = wall.Skin, S = Vector3.new(D, height, SKIN), C = CFrame.fromMatrix(at(wall.Side * W / 2, height / 2, D / 2) - normal * (SKIN / 2), right, Y_AXIS) },
							{ Part = wall.Crown, S = wall.Crown.Size, C = CFrame.new(at(wall.Side * (W / 2 - 0.18), height - crownH / 2, D / 2)) },
							{ Part = wall.Edge, S = Vector3.new(WALL_T + SKIN + 0.1, height + 0.4, 0.2), C = CFrame.new(at(wall.Side * (W / 2 + (WALL_T + SKIN) / 2), (height + 0.4) / 2 - 0.2, D + 0.05)) },
						}
					end
					-- (v9.6) écarts anti-scintillement de la pose levée, gardés dans les deux poses
					local deltas = wall.Deltas
					if not deltas then
						local fresh: { [BasePart]: { P: Vector3, S: Vector3 } } = {}
						for _, spec in ipairs(pose(WH)) do
							fresh[spec.Part] = { P = spec.Part.Position - spec.C.Position, S = spec.Part.Size - spec.S }
						end
						wall.Deltas = fresh
						deltas = fresh
					end
					for _, spec in ipairs(pose(lower and 1.2 or WH)) do
						local delta = (deltas :: any)[spec.Part]
						spec.Part.Size = spec.S + (delta and delta.S or Vector3.zero)
						spec.Part.CFrame = spec.C + (delta and delta.P or Vector3.zero)
					end
					local gui = wall.Gui
					if gui then
						gui.Enabled = not lower
					end
				end
			end
		end,
		Step = function(dt: number)
			if #arrivals > 0 then
				for index = #arrivals, 1, -1 do
					local arrival = arrivals[index]
					arrival.Clock += dt
					local t = math.clamp((arrival.Clock - arrival.Delay) / DROP_TIME, 0, 1)
					-- (petit rebond à l'arrivée)
					local s = 1.70158
					local eased = 1 + (s + 1) * (t - 1) ^ 3 + s * (t - 1) ^ 2
					local offset = Vector3.new(0, DROP * (1 - eased), 0)
					if t >= 1 then
						moveParts(arrival.Parts, arrival.Finals)
						table.remove(arrivals, index)
					elseif arrival.Clock >= arrival.Delay then
						local moved = table.create(#arrival.Finals)
						for i, final in ipairs(arrival.Finals) do
							moved[i] = final + offset
						end
						moveParts(arrival.Parts, moved)
					end
				end
			end
			-- Animaux : petite respiration (≤ 30 fois par seconde, une fois tous arrivés)
			petClock += dt
			if #pets > 0 and petClock >= 1 / 30 and #arrivals == 0 then
				petClock = 0
				local now = os.clock()
				for _, pet in ipairs(pets) do
					local lift = Vector3.new(0, (math.sin(now * 2.4 + pet.Phase) * 0.5 + 0.5) * pet.Amount, 0)
					local moved = table.create(#pet.Finals)
					for i, final in ipairs(pet.Finals) do
						moved[i] = final + lift
					end
					moveParts(pet.Parts, moved)
				end
			end
			if mood.Effect == "Storm" then
				-- éclair de temps en temps (lumière de remplissage)
				stormClock += dt
				local fill = fillLight
				if fill then
					if stormClock > 6 then
						stormClock = 0
					end
					-- (éclair doux : plus d'éblouissement, luminosité ≤ 1,2)
					local flash = (stormClock < 0.12 or (stormClock > 0.25 and stormClock < 0.33)) and 0.8 or 0
					fill.Enabled = true
					fill.Color = Color3.fromRGB(210, 225, 255)
					fill.Brightness = soft(mood.Amount * 1.2 + flash)
				end
			end
			if mood.Effect == "Disco" or mood.Effect == "RGB" or mood.Effect == "Neon" then
				discoClock += dt
				local ceiling = ceilingLight
				if ceiling and discoClock > 0.25 then
					discoClock = 0
					ceiling.Color = Color3.fromHSV((os.clock() * 0.2) % 1, 0.5, 1)
				end
			end
		end,
		Destroy = function()
			destroyed = true
			for _, emitter in ipairs(effects) do
				pcall(function()
					emitter.Enabled = false
				end)
			end
			local live = getLiveProps()
			if live then
				pcall(live.DetachAll, liveHandles)
			end
			folder:Destroy()
		end,
	}
	return scene
end

----------------------------------------------------------------------
-- Monde (v9.3, Dopamine Town) : coque de pièce à taille de personnage et
-- objets placés comme dans la vue 3D (voir l'en-tête)
----------------------------------------------------------------------

export type ShellOptions = {
	Scale: number?, -- studs par px de la pièce 2D (32 / 760 par défaut : ~32 studs de large)
	Depth: number?, -- (studs) profondeur intérieure (24)
	WallHeight: number?, -- hauteur des murs (14)
	Doors: { string }?, -- côtés avec une porte ouverte : "Front" | "Left" | "Right" | "Back" ({ "Front" })
	DoorWidth: number?, -- (6)
	DoorHeight: number?, -- (9)
	Front: boolean?, -- mur avant (avec sa porte) ; true par défaut
	Ceiling: boolean?, -- plafond ; false par défaut
	Patterns: boolean?, -- motifs du papier peint / du sol (SurfaceGui décoratives) ; true par défaut
	-- (v9.8 HOUSE98) VRAIE fenêtre dans le mur du fond (ville) : { x0, x1, y0, y1 }
	-- (x depuis le milieu de la pièce, y depuis le sol) : trou dans le mur,
	-- chambranle + appui intérieurs, PAS de vue peinte ni de vitre (la vitre
	-- est dans le mur du fond de la façade, HouseFacade) ; nil = fenêtre décor
	BackWindow: { number }?,
}

local SHELL_WALL_T = 1

-- Pièce solide d'une coque (collision + rayons)
local function shellPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, solid: boolean): BasePart
	local p = newPart("Part", name, size, cframe, color, material)
	p.CanCollide = solid
	p.CanQuery = solid
	p.CastShadow = solid
	p.Parent = parent
	return p
end

function House3DScene.BuildRoomShell(roomData: any, sizeDef: any?, options: ShellOptions?): Model
	local opts: ShellOptions = type(options) == "table" and options or {}
	local room = type(roomData) == "table" and roomData or {}
	local widthFactor = type(sizeDef) == "table" and tonumber(sizeDef.Width) or 1
	local roomWpx = math.floor(ROOM_BASE_WIDTH * (widthFactor or 1) + 0.5)
	local scale = tonumber(opts.Scale) or 32 / ROOM_BASE_WIDTH
	local W = roomWpx * scale
	local D = tonumber(opts.Depth) or 24
	local WH = tonumber(opts.WallHeight) or 14
	local T = SHELL_WALL_T
	local doorW = math.clamp(tonumber(opts.DoorWidth) or 6, 3, W - 2)
	local doorH = math.clamp(tonumber(opts.DoorHeight) or 9, 6, WH - 1)
	local doors: { [string]: boolean } = {}
	for _, side in ipairs(type(opts.Doors) == "table" and opts.Doors or { "Front" }) do
		doors[tostring(side)] = true
	end
	local wallpaper = HouseCommon.GetRoomWallpaper(room)
	local floorStyle = HouseCommon.GetRoomFloor(room)
	local wallA = wallpaper and wallpaper.A or C.PinkSoft
	local floorA = floorStyle and floorStyle.A or C.Lilac
	local trimEntry = configTable("HouseTrimsById")[tostring(room.Trim or "Cream")]
	local trim = asColor(type(trimEntry) == "table" and trimEntry.Color, CREAM)
	local wallMaterial = WALL_MATERIAL[wallpaper and wallpaper.Pattern or ""] or M.SmoothPlastic
	local floorMaterial = FLOOR_MATERIAL[floorStyle and floorStyle.Pattern or ""] or M.SmoothPlastic
	local patterns = opts.Patterns ~= false

	local model = Instance.new("Model")
	model.Name = "RoomShell"
	-- Repère : pivot au centre du dessus du sol, mur du fond vers -Z, avant (+Z)
	local floorPart = shellPart(model, "Floor", Vector3.new(W + 2 * T, 1, D + 2 * T), CFrame.new(0, -0.5, 0), floorA, floorMaterial, true)
	floorPart.CastShadow = false
	floorPart.PivotOffset = CFrame.new(0, 0.5, 0)
	model.PrimaryPart = floorPart
	if patterns then
		-- motif du sol (décoration : la couleur de la pièce suffit déjà)
		local skin = shellPart(model, "FloorPattern", Vector3.new(W, D, 0.05), CFrame.fromMatrix(Vector3.new(0, 0.025 - 0.05, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1)), floorA, floorMaterial, false)
		skin.CastShadow = false
		local canvasW, canvasH = math.floor(W / PX), math.floor(D / PX)
		local gui = House3DKit.Surface(skin, Enum.NormalId.Back, Vector2.new(canvasW, canvasH), 1)
		local sheet = Instance.new("Frame")
		sheet.Name = "Floor"
		sheet.BackgroundTransparency = 1
		sheet.BorderSizePixel = 0
		sheet.Size = UDim2.fromScale(1, 1)
		sheet.ClipsDescendants = true
		sheet.Parent = gui
		pcall(House3DFloor.Paint, sheet, canvasW, canvasH, floorStyle, 1)
		sheet.BackgroundTransparency = 1
	end

	-- Un mur (avec une porte ouverte au milieu si demandé) ; `along` = axe du mur
	-- (v9.8 HOUSE98) `hole` = { a0, a1, y0, y1 } : vraie fenêtre (a le long de `along`)
	local function wall(name: string, center: Vector3, along: Vector3, length: number, inward: Vector3, withDoor: boolean, hole: { number }?)
		local across = Vector3.new(math.abs(inward.X), 0, math.abs(inward.Z)) * T
		local lengthVec = Vector3.new(math.abs(along.X), 0, math.abs(along.Z))
		local function segment(offset: number, segLength: number, y0: number, y1: number)
			if segLength <= 0.05 or y1 - y0 <= 0.05 then
				return
			end
			local size = lengthVec * segLength + across + Vector3.new(0, y1 - y0, 0)
			shellPart(model, name, size, CFrame.new(center + along * offset + Vector3.new(0, (y0 + y1) / 2, 0)), wallA, wallMaterial, true)
		end
		if withDoor then
			local side = (length - doorW) / 2
			segment(-(doorW / 2 + side / 2), side, 0, WH)
			segment(doorW / 2 + side / 2, side, 0, WH)
			segment(0, doorW, doorH, WH)
			-- chambranle (moulures)
			local face = center + inward * (T / 2 + 0.1)
			local trimSize = lengthVec * 0.5 + Vector3.new(math.abs(inward.X), 0, math.abs(inward.Z)) * 0.3
			for _, sx in ipairs({ -1, 1 }) do
				shellPart(model, "DoorFrame", trimSize + Vector3.new(0, doorH + 0.5, 0), CFrame.new(face + along * sx * (doorW / 2 + 0.25) + Vector3.new(0, (doorH + 0.5) / 2, 0)), trim, M.Wood, false)
			end
			shellPart(model, "DoorFrame", lengthVec * (doorW + 1) + Vector3.new(math.abs(inward.X), 0, math.abs(inward.Z)) * 0.3 + Vector3.new(0, 0.5, 0),
				CFrame.new(face + Vector3.new(0, doorH + 0.25, 0)), trim, M.Wood, false)
		elseif hole then
			-- mur percé d'une vraie fenêtre : gauche, droite (pleine hauteur), dessous, dessus
			local a0, a1 = math.max(-length / 2, hole[1]), math.min(length / 2, hole[2])
			segment((-length / 2 + a0) / 2, a0 + length / 2, 0, WH)
			segment((a1 + length / 2) / 2, length / 2 - a1, 0, WH)
			segment((a0 + a1) / 2, a1 - a0, 0, hole[3])
			segment((a0 + a1) / 2, a1 - a0, hole[4], WH)
		else
			segment(0, length, 0, WH)
		end
		-- plinthe et moulure du haut (côté intérieur)
		local inner = center + inward * (T / 2 + 0.1)
		local stripDepth = Vector3.new(math.abs(inward.X), 0, math.abs(inward.Z)) * 0.2
		local function strip(stripName: string, y: number, h: number)
			if withDoor and y < doorH then
				local side = (length - doorW) / 2
				for _, sx in ipairs({ -1, 1 }) do
					shellPart(model, stripName, lengthVec * side + stripDepth + Vector3.new(0, h, 0), CFrame.new(inner + along * sx * (doorW / 2 + side / 2) + Vector3.new(0, y + h / 2, 0)), trim, M.SmoothPlastic, false)
				end
			else
				shellPart(model, stripName, lengthVec * length + stripDepth + Vector3.new(0, h, 0), CFrame.new(inner + Vector3.new(0, y + h / 2, 0)), trim, M.SmoothPlastic, false)
			end
		end
		strip("Skirting", 0, 0.7)
		strip("Crown", WH - 0.5, 0.5)
	end
	local X = Vector3.new(1, 0, 0)
	local Z = Vector3.new(0, 0, 1)
	local backWindow: { number }? = nil
	if type(opts.BackWindow) == "table" and #opts.BackWindow >= 4 then
		local b = opts.BackWindow :: { number }
		local bx0, bx1 = math.clamp(tonumber(b[1]) or 0, -W / 2 + 0.6, W / 2 - 1.6), math.clamp(tonumber(b[2]) or 0, -W / 2 + 1.6, W / 2 - 0.6)
		local by0, by1 = math.clamp(tonumber(b[3]) or 0, 0.8, WH - 2), math.clamp(tonumber(b[4]) or 0, 1.8, WH - 1)
		if bx1 - bx0 > 1 and by1 - by0 > 1 then
			backWindow = { bx0, bx1, by0, by1 }
		end
	end
	wall("WallBack", Vector3.new(0, 0, -D / 2 - T / 2), X, W + 2 * T, Z, doors.Back == true, backWindow)
	wall("WallLeft", Vector3.new(-W / 2 - T / 2, 0, 0), Z, D, X, doors.Left == true)
	wall("WallRight", Vector3.new(W / 2 + T / 2, 0, 0), Z, D, -X, doors.Right == true)
	if opts.Front ~= false then
		wall("WallFront", Vector3.new(0, 0, D / 2 + T / 2), X, W + 2 * T, -Z, doors.Front == true)
	end
	if opts.Ceiling == true then
		-- (v9.6 : dessous 0,04 plus bas que le dessous du plancher de l'étage :
		-- plus de faces confondues avec lui, ni avec la dalle de la façade)
		-- (v11 SCALE11 : côtés rentrés de 0,06 dans l'épaisseur des murs : ses
		-- faces de côté étaient dans le plan des faces extérieures des murs et
		-- du plancher de la pièce du dessus -> scintillement)
		shellPart(model, "Ceiling", Vector3.new(W + 2 * T - 0.12, 0.56, D + 2 * T - 0.12), CFrame.new(0, WH + 0.24, 0), trim:Lerp(WHITE, 0.5), M.SmoothPlastic, true)
	end
	-- Papier peint (décoration) sur le mur du fond
	if patterns and backWindow then
		-- (v9.8) peau percée : à gauche / à droite de la fenêtre (motif : la même
		-- feuille décalée, donc raccord parfait), dessous / dessus (couleur unie)
		local bw = backWindow :: { number }
		local wallPx = math.floor(ROOM_HEIGHT * (tonumber(HouseCommon.Config.WallRatio) or 0.46) + 0.5)
		local s = wallPx / WH -- px de feuille par stud
		local canvasW = math.floor(W * s)
		local function piece(x0: number, x1: number, y0: number, y1: number, painted: boolean)
			if x1 - x0 < 0.05 or y1 - y0 < 0.05 then
				return
			end
			local skin = shellPart(model, "WallPattern", Vector3.new(x1 - x0, y1 - y0, 0.05), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, -D / 2 + 0.03), wallA, wallMaterial, false)
			skin.CastShadow = false
			if not painted then
				return
			end
			local gui = House3DKit.Surface(skin, Enum.NormalId.Back, Vector2.new((x1 - x0) * s, (y1 - y0) * s), 1)
			local sheet = Instance.new("Frame")
			sheet.Name = "Paper"
			sheet.BackgroundTransparency = 1
			sheet.BorderSizePixel = 0
			sheet.Position = UDim2.fromOffset(-math.floor((x0 + W / 2) * s + 0.5), -math.floor((WH - y1) * s + 0.5))
			sheet.Size = UDim2.fromOffset(canvasW, wallPx)
			sheet.ClipsDescendants = true
			sheet.Parent = gui
			pcall(HousePatterns.BuildWall, sheet, canvasW, wallPx, wallpaper, 1)
			sheet.BackgroundTransparency = 1
		end
		piece(-W / 2, bw[1], 0, WH, true)
		piece(bw[2], W / 2, 0, WH, true)
		piece(bw[1], bw[2], 0, bw[3], false)
		piece(bw[1], bw[2], bw[4], WH, false)
	elseif patterns then
		local wallPx = math.floor(ROOM_HEIGHT * (tonumber(HouseCommon.Config.WallRatio) or 0.46) + 0.5)
		local skin = shellPart(model, "WallPattern", Vector3.new(W, WH, 0.05), CFrame.new(0, WH / 2, -D / 2 + 0.03), wallA, wallMaterial, false)
		skin.CastShadow = false
		local canvasW = math.floor(W / (WH / wallPx))
		local gui = House3DKit.Surface(skin, Enum.NormalId.Back, Vector2.new(canvasW, wallPx), 1)
		local sheet = Instance.new("Frame")
		sheet.Name = "Paper"
		sheet.BackgroundTransparency = 1
		sheet.BorderSizePixel = 0
		sheet.Size = UDim2.fromScale(1, 1)
		sheet.ClipsDescendants = true
		sheet.Parent = gui
		pcall(HousePatterns.BuildWall, sheet, canvasW, wallPx, wallpaper, 1)
		sheet.BackgroundTransparency = 1
	end
	-- Fenêtre du mur du fond (cadre, vitre, rebord ; décor)
	if backWindow then
		-- (v9.8) vraie fenêtre : chambranle mouluré (4 pièces, 0,05 dans le trou :
		-- jamais coplanaire avec les tranches du mur) + appui intérieur en bois
		local bw = backWindow :: { number }
		local z = -D / 2
		local f = 0.4
		local x0, x1, y0, y1 = bw[1], bw[2], bw[3], bw[4]
		local ww = x1 - x0
		shellPart(model, "WindowFrame", Vector3.new(ww + 2 * f, f, 0.3), CFrame.new((x0 + x1) / 2, y1 + f / 2 - 0.05, z + 0.12), trim, M.Wood, false)
		shellPart(model, "WindowFrame", Vector3.new(f, y1 - y0, 0.3), CFrame.new(x0 - f / 2 + 0.05, (y0 + y1) / 2, z + 0.12), trim, M.Wood, false)
		shellPart(model, "WindowFrame", Vector3.new(f, y1 - y0, 0.3), CFrame.new(x1 + f / 2 - 0.05, (y0 + y1) / 2, z + 0.12), trim, M.Wood, false)
		shellPart(model, "WindowSill", Vector3.new(ww + 1.3, 0.28, 0.75), CFrame.new((x0 + x1) / 2, y0 - 0.1, z + 0.3), trim, M.Wood, false)
		model:SetAttribute("BackWindow", Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, 0))
	else
		-- (fenêtre décor de la vue 3D de la maison 2D : vue peinte derrière une vitre)
		-- (v9.6 : place et taille de la fenêtre de la pièce 2D, comme les objets muraux)
		local cx, cy, ww, wh = windowRect(roomWpx, scale)
		local z = -D / 2
		local views = configTable("HouseViewsById")
		local viewEntry = views[tostring(room.View or "Garden")] or views.Garden
		local sky = type(viewEntry) == "table" and asColor(viewEntry.Sky, Color3.fromRGB(170, 214, 255)) or Color3.fromRGB(170, 214, 255)
		shellPart(model, "WindowView", Vector3.new(ww, wh, 0.1), CFrame.new(cx, cy, z + 0.1), sky, M.SmoothPlastic, false).CastShadow = false
		shellPart(model, "WindowHill", Vector3.new(ww, wh * 0.28, 0.1), CFrame.new(cx, cy - wh * 0.36, z + 0.15), GRASS, M.SmoothPlastic, false).CastShadow = false
		local glass = shellPart(model, "WindowGlass", Vector3.new(ww, wh, 0.08), CFrame.new(cx, cy, z + 0.35), Color3.fromRGB(220, 240, 255), M.Glass, false)
		glass.Transparency = 0.75
		glass.CastShadow = false
		local f = 0.35
		for _, spec in ipairs({
			{ 0, wh / 2 + f / 2, ww + 2 * f, f }, { 0, -wh / 2 - f / 2, ww + 2 * f, f },
			{ -ww / 2 - f / 2, 0, f, wh }, { ww / 2 + f / 2, 0, f, wh }, { 0, 0, 0.18, wh }, { 0, 0, ww, 0.18 },
		}) do
			shellPart(model, "WindowFrame", Vector3.new(spec[3], spec[4], 0.4), CFrame.new(cx + spec[1], cy + spec[2], z + 0.25), trim, M.Wood, false)
		end
		shellPart(model, "WindowSill", Vector3.new(ww + 1.2, 0.3, 0.9), CFrame.new(cx, cy - wh / 2 - 0.35, z + 0.45), trim, M.Wood, false)
	end
	model:SetAttribute("Width", W)
	model:SetAttribute("Depth", D)
	model:SetAttribute("WallHeight", WH)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("RoomWpx", roomWpx)
	model.WorldPivot = CFrame.new()
	-- (v9.6) anti-scintillement : moulures, chambranles, fenêtre écartés des
	-- murs / du sol (qui ne bougent pas : collisions et portes intactes)
	pcall(House3DScene.SeparateShell, model, nil)
	return model
end

export type PlaceOptions = {
	Night: boolean?,
	Collide: boolean?, -- (true) gros meubles solides
	Query: boolean?, -- (true) objets visibles aux rayons (déplacer à la souris)
	Yield: boolean?, -- (false) task.wait() entre deux lots d'objets
}

-- Place les objets d'une pièce dans une coque (BuildRoomShell) : dossier
-- "Items" de la coque (vidé d'abord). Renvoie les modèles ; chaque modèle a
-- l'attribut "EntryIndex" (= index dans roomData.Placed).
function House3DScene.PlaceItems(roomModel: Model, roomData: any, options: PlaceOptions?): { Model }
	local opts: PlaceOptions = type(options) == "table" and options or {}
	local scale = tonumber(roomModel:GetAttribute("Scale")) or 32 / ROOM_BASE_WIDTH
	local roomWpx = tonumber(roomModel:GetAttribute("RoomWpx")) or ROOM_BASE_WIDTH
	local D = tonumber(roomModel:GetAttribute("Depth")) or 24
	local WH = tonumber(roomModel:GetAttribute("WallHeight")) or 14
	local dims = House3DLayout.Dims({ Width = roomWpx / ROOM_BASE_WIDTH }, scale, D, WH)
	local frame = roomModel:GetPivot() * CFrame.new(0, 0, -D / 2)
	local folder = roomModel:FindFirstChild("Items")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "Items"
		folder.Parent = roomModel
	end
	local room = type(roomData) == "table" and roomData or {}
	local trimEntry = configTable("HouseTrimsById")[tostring(room.Trim or "Cream")]
	local trim = asColor(type(trimEntry) == "table" and trimEntry.Color, CREAM)
	local entries, indices = House3DLayout.Entries(room)
	local builds: { House3DLayout.Build } = {}
	for index, entry in ipairs(entries) do
		local ok, build = pcall(House3DLayout.Prepare, entry, index, dims, { Night = opts.Night == true, Collide = opts.Collide, Query = opts.Query, Trim = trim })
		if ok and build then
			build.Model:SetAttribute("EntryIndex", indices[index])
			table.insert(builds, build)
		elseif not ok then
			warn("[House3D] Objet " .. tostring(entry.I) .. " : " .. tostring(build))
		end
		if opts.Yield == true and index % 6 == 0 then
			task.wait()
		end
	end
	local okLayout, err = pcall(House3DLayout.Layout, builds, dims, frame)
	if not okLayout then
		warn("[House3D] Disposition : " .. tostring(err))
	end
	local models: { Model } = {}
	for _, build in ipairs(builds) do
		pcall(function()
			build.Model:PivotTo(build.Pivot)
		end)
		build.Model.Parent = folder
		table.insert(models, build.Model)
	end
	-- (v9.6) anti-scintillement entre objets voisins et avec la coque
	pcall(House3DScene.SeparateShell, roomModel, models)
	return models
end

-- v9.6 : faces confondues (z-fighting) d'une coque et de ses objets. Les
-- grandes pièces de la coque (sol, murs, plafond, motifs) restent fixes ;
-- les moulures et les pièces des objets s'écartent de 0,035 stud.
local SHELL_FIXED: { [string]: boolean } = {
	Floor = true, FloorPattern = true, WallPattern = true, Ceiling = true,
	WallBack = true, WallLeft = true, WallRight = true, WallFront = true,
	-- (maquette de la vue 3D : coque, peaux papier peint, socle, studio)
	WallBackPaper = true, WallLeftPaper = true, WallRightPaper = true, Slab = true, Lawn = true, Base = true,
}
function House3DScene.SeparateShell(shell: Instance, items: { any }?)
	local parts: { BasePart } = {}
	local fixed: { [BasePart]: boolean } = {}
	for _, child in ipairs(shell:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
			if SHELL_FIXED[child.Name] or string.sub(child.Name, 1, 6) == "Studio" then
				fixed[child] = true
			end
		end
	end
	for _, model in ipairs(items or {}) do
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	House3DKit.Separate(parts, fixed)
end

return House3DScene
