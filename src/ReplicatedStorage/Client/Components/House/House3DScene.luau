--[[
	House3DScene (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DScene

	Construit la "maison de poupée" 3D d'UNE pièce pour la vue 3D (House3D),
	loin du monde (autour de ORIGIN), dans un Folder du Workspace :
	  - un studio : grande boîte fermée tapissée d'un ciel pastel en dégradé,
	    nuages et étincelles (la nuit : ciel bleu nuit et étoiles) ; on ne
	    voit jamais le reste du monde ;
	  - un socle : pelouse fleurie posée sur un "gâteau" rose ;
	  - la pièce : dalle du sol, mur du fond, murs de côté (papier peint de
	    la pièce avec les MÊMES dessins que la pièce 2D : HousePatterns),
	    sol (mêmes motifs, dessinés à plat : House3DFloor), plinthes et
	    moulures en relief, fenêtre à rideaux avec rebord et tringle,
	    prise, tache de soleil au sol, lumières (plafonnier, soleil de la
	    fenêtre, lampes) ;
	  - les objets : chaque objet posé devient un "carton découpé" vertical
	    (SurfaceGui sur une pièce invisible) dessiné avec HouseArt.Paint,
	    debout à la profondeur donnée par son Y (Y = pieds : au fond près
	    du mur, devant près de la caméra) ; objets muraux à plat sur le
	    mur, tapis à plat sur le sol, objets posés SUR un meuble à la
	    hauteur de son dessus, chaises rangées à une table autour d'elle,
	    ombre douce au sol sous chaque objet debout.

	Ordre d'affichage : Roblox trie les SurfaceGui par DISTANCE entre la
	caméra et le centre de leur pièce (pas au pixel près). On règle donc
	l'épaisseur des pièces porteuses (elles s'étendent derrière leur face) :
	décor (ciel, murs, sol) très loin -> dessiné en premier ; puis tapis,
	ombres ; puis les cartons dans l'ordre de leur profondeur réelle (tous
	parallèles au mur du fond). Deux cartons qui se chevauchent sont
	toujours séparés d'au moins GAP studs en profondeur.

	Toutes les toiles utilisent la face Back (+Z local) d'une pièce orientée
	par CFrame.fromMatrix(centre, droite, haut) : la toile s'affiche à
	l'endroit pour qui la regarde de face.

	API :
	  House3DScene.new(room, sizeId, night) -> Scene   (décor construit tout de suite)
	  scene.BuildItems(alive, progress?)   objets, étalés sur plusieurs images (yield)
	  scene.SetNight(night)
	  scene.UpdateWalls(eye)   baisse le mur de côté entre la caméra et la pièce
	  scene.Destroy()
]]

local TweenService = game:GetService("TweenService")

local HouseCommon = require(script.Parent.HouseCommon)
local HousePatterns = require(script.Parent.HousePatterns)
local HouseArt = require(script.Parent.HouseArt)
local HouseSurfaces = require(script.Parent.HouseSurfaces)
local House3DFloor = require(script.Parent.House3DFloor)

type Placed = HouseCommon.Placed
type Item = HouseCommon.Item

local House3DScene = {}

House3DScene.ORIGIN = Vector3.new(0, 5000, 0) -- loin du monde (au-dessus de tout)
House3DScene.FOLDER_NAME = "House3DPreview"

local PX = 0.05 -- studs par px de maquette de la pièce 2D
local PPS = 48 -- pixels de SurfaceGui par stud (murs, sol, objets)
local ROOM_BASE_WIDTH = 760 -- (= HouseRoom.BASE_WIDTH)
local ROOM_HEIGHT = 440 -- (= HouseRoom.HEIGHT)
local SIDE_PX = 42 -- murs de côté en perspective de la pièce 2D (HouseRoom)
local DEPTH_PX = 520 -- profondeur du sol (px de maquette) : 26 studs
local WALL_T = 0.8 -- épaisseur des murs
local SLAB = 1.4 -- épaisseur de la dalle
local LAWN_SIDE = 3.4 -- pelouse autour de la maison
local LAWN_FRONT = 4
local LAWN_BACK = 2.2

-- Épaisseur (derrière leur face) des pièces qui portent des SurfaceGui :
-- elle fixe l'ordre d'affichage (voir l'en-tête)
local DEPTH_FAR = 2040
local DEPTH_RUG = 1500
local DEPTH_SHADOW = 1300
local DEPTH_CARD = 900

local GAP = 0.45 -- écart minimal de profondeur entre deux cartons qui se chevauchent
local Z_FLOOR_MIN = 1.0 -- les objets au sol restent devant les plinthes
local Z_WALL = 0.42 -- objets muraux : devant le rebord de fenêtre et les rideaux
local Z_WALL_STEP = 0.03
local FLAT_STRETCH = 2.6 -- tapis : le dessin 2D (écrasé par la perspective) est rallongé en profondeur
local CARD_MARGIN_X = 28 -- marges des cartons (unités de la boîte 100 x 100) : halos, débords
local CARD_MARGIN_TOP = 36
local CARD_MARGIN_BOTTOM = 6
local CARD_MARGIN_WALL = 28
local FLAT_RES = 4 -- résolution des toiles FixedSize (px par unité)
local MAX_ITEM_LIGHTS = 6
local DROP = 1.6 -- (studs) les objets tombent doucement à leur place à l'ouverture
local BATCH_ITEMS = 6 -- objets préparés par image au plus
local BATCH_TIME = 0.008 -- (s) temps de préparation par image

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local SHELL = Color3.fromRGB(252, 220, 236)
local BASE_PINK = Color3.fromRGB(242, 188, 216)
local GRASS = Color3.fromRGB(150, 222, 150)
local NIGHT_VEIL = Color3.fromRGB(34, 26, 92)
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle
local Round = HousePatterns.Round

local SKY_DAY = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(172, 212, 255)),
	ColorSequenceKeypoint.new(0.42, Color3.fromRGB(208, 224, 255)),
	ColorSequenceKeypoint.new(0.68, Color3.fromRGB(255, 222, 240)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 238, 226)),
})
local SKY_NIGHT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 18, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(54, 42, 116)),
	ColorSequenceKeypoint.new(0.76, Color3.fromRGB(104, 70, 156)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(146, 94, 166)),
})
local SKY_TOP_DAY = Color3.fromRGB(172, 212, 255)
local SKY_TOP_NIGHT = Color3.fromRGB(20, 18, 60)
local SKY_BOTTOM_DAY = Color3.fromRGB(255, 238, 226)
local SKY_BOTTOM_NIGHT = Color3.fromRGB(146, 94, 166)

-- Halo des lumières (même dessin que la pièce 2D)
local GLOW_RINGS = {
	{ Size = 1, Day = 0.96, Night = 0.9 },
	{ Size = 0.8, Day = 0.94, Night = 0.86 },
	{ Size = 0.62, Day = 0.91, Night = 0.8 },
	{ Size = 0.46, Day = 0.88, Night = 0.74 },
	{ Size = 0.32, Day = 0.85, Night = 0.68 },
}

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
	UpdateWalls: (eye: Vector3) -> (),
	Destroy: () -> (),
}

type Build = {
	Entry: Placed,
	Item: Item,
	Order: number,
	SizePx: number,
	K: number, -- studs par unité de la boîte 100 x 100
	Content: Frame, -- boîte + marges (unités)
	Kind: string, -- "Wall" | "Flat" | "Floor"
	Glow: Color3?,
	Rings: { Frame },
	Parent: Build?,
	Relation: string?, -- "On" (posé sur un meuble) | "At" (chaise rangée à une table)
	Top: Build?, -- racine du groupe (meuble au sol / mural)
	X: number,
	H: number, -- hauteur des pieds (ou du centre pour un objet mural)
	Z: number,
	Done: boolean,
	Rank: number,
	Light: boolean, -- reçoit une vraie PointLight (les plus grosses lampes)
}

type SideWall = {
	Side: number, -- -1 = gauche, 1 = droite
	Solid: Part,
	Canvas: Part,
	Crown: Part,
	Lowered: boolean,
}

----------------------------------------------------------------------
-- Pièces et toiles
----------------------------------------------------------------------

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, transparency: number?, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material or Enum.Material.SmoothPlastic
	part.Color = color
	part.Transparency = transparency or 0
	part.Size = size
	part.CFrame = cframe
	return part
end

-- (Lumière : cartons à LightInfluence 0 = couleurs exactes du dessin 2D, et
-- Brightness agit alors à coup sûr pour la nuit ; murs / sol un peu éclairés
-- par les lampes, 0.18.)
-- Toile : SurfaceGui sur la face Back d'une pièce invisible dont la face
-- visible est centrée en `center`, orientée (right, up) ; la pièce s'étend
-- de `depth` studs DERRIÈRE sa face (ordre d'affichage). `canvasSize` :
-- toile FixedSize étirée sur la face (tapis, ombres) ; sinon PixelsPerStud.
local function newCanvas(name: string, center: Vector3, right: Vector3, up: Vector3, width: number, height: number, depth: number, light: number, canvasSize: Vector2?, pps: number?): (Part, SurfaceGui)
	local normal = right:Cross(up)
	local part = newPart(name, Vector3.new(width, height, depth), CFrame.fromMatrix(center - normal * (depth / 2), right, up), WHITE, 1)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Canvas"
	gui.Face = Enum.NormalId.Back
	if canvasSize then
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = canvasSize
	else
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = pps or PPS
	end
	gui.LightInfluence = light
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	return part, gui
end

-- Cadre transparent en px de maquette (UIScale -> px de la toile)
local function designFrame(parent: Instance, name: string, width: number, height: number, scale: number, z: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(width, height)
	frame.ZIndex = z or 1
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = frame
	frame.Parent = parent
	return frame
end

local function fadeGradient(frame: GuiObject, from: number, to: number, rotation: number)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new(from, to)
	gradient.Parent = frame
end

-- Pseudo-aléatoire stable
local function noise(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

----------------------------------------------------------------------
-- Scène
----------------------------------------------------------------------

function House3DScene.new(room: any, sizeId: string?, startNight: boolean?): Scene
	local config = HouseCommon.Config
	local size = HouseCommon.SizesById[sizeId or ""] or config.Sizes[1]
	local widthFactor = tonumber(size and size.Width) or 1
	local roomWpx = math.floor(ROOM_BASE_WIDTH * widthFactor + 0.5)
	local roomHpx = ROOM_HEIGHT
	local wallRatio = tonumber(config.WallRatio) or 0.46
	local wallPx = math.floor(roomHpx * wallRatio + 0.5)
	local W = roomWpx * PX
	local WH = wallPx * PX
	local D = DEPTH_PX * PX
	local origin = House3DScene.ORIGIN
	local wallpaper = HouseCommon.GetRoomWallpaper(room)
	local floorStyle = HouseCommon.GetRoomFloor(room)
	local wallA = wallpaper and wallpaper.A or C.PinkSoft
	local wallB = wallpaper and wallpaper.B or C.Pink
	local night = startNight == true
	local destroyed = false

	local folder = Instance.new("Folder")
	folder.Name = House3DScene.FOLDER_NAME

	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end
	local X_AXIS = Vector3.new(1, 0, 0)
	local Y_AXIS = Vector3.new(0, 1, 0)
	local BACKWARD = Vector3.new(0, 0, -1) -- "haut" d'une toile posée au sol : vers le mur du fond

	-- Ce qui change la nuit
	local veils: { Frame } = {}
	local skyGradients: { UIGradient } = {}
	local skyTops: { Frame } = {}
	local skyBottoms: { Frame } = {}
	local clouds: { Frame } = {}
	local stars: { Frame } = {}
	local dayDecor: { GuiObject } = {}
	local nightDecor: { GuiObject } = {}
	local beamSlices: { Frame } = {}
	local windowGlass: UIGradient? = nil
	local cardGuis: { SurfaceGui } = {}
	local lampGuis: { SurfaceGui } = {}
	local lampRings: { Frame } = {}
	local itemLights: { PointLight } = {}
	local ceilingLight: PointLight? = nil
	local sunLight: SpotLight? = nil
	local sideWalls: { SideWall } = {}

	local function addVeil(parent: Instance, transparency: number?, z: number?)
		local veil = Instance.new("Frame")
		veil.Name = "Night"
		veil.BackgroundColor3 = NIGHT_VEIL
		veil.BackgroundTransparency = transparency or 0.5
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = z or 50
		veil.Visible = night
		veil.Parent = parent
		table.insert(veils, veil)
	end

	-- 2D (px de la pièce) -> 3D : les murs de côté 2D prennent SIDE_PX en
	-- perspective ; on remet le fond de la pièce à sa vraie largeur
	local function mapX(x: number, t: number, half: number): number
		local side = SIDE_PX * (1 - math.clamp(t, 0, 1))
		local px = (x * roomWpx - side) / math.max(1, roomWpx - 2 * side) * roomWpx
		local studs = (px - roomWpx / 2) * PX
		local limit = math.max(0, W / 2 - half)
		return math.clamp(studs, -limit, limit)
	end
	-- Y (pieds) -> fraction de la profondeur (0 = mur du fond, 1 = bord avant)
	local function depthOf(y: number): number
		return math.clamp((y - wallRatio) / math.max(0.05, 1 - wallRatio), 0, 1)
	end
	-- x (px de maquette, pièce 2D) -> x sur la toile du mur du fond
	local function wallCanvasX(x2d: number): number
		return (x2d - SIDE_PX) / math.max(1, roomWpx - 2 * SIDE_PX) * roomWpx
	end

	------------------------------------------------------------------
	-- Studio : ciel pastel tout autour
	------------------------------------------------------------------
	local studioCenter = Vector3.new(0, 25, D / 2)
	local HX, HZ = 150, 150
	local yMin, yMax = -75, 125
	local skyPPS = 3

	local function skyWall(name: string, center: Vector3, right: Vector3, up: Vector3, width: number, height: number, kind: string)
		local normal = right:Cross(up)
		local solidColor = kind == "Top" and SKY_TOP_DAY or (kind == "Bottom" and SKY_BOTTOM_DAY or Color3.fromRGB(214, 226, 255))
		local solid = newPart("Backdrop" .. name, Vector3.new(width + 4, height + 4, 1), CFrame.fromMatrix(at(center.X, center.Y, center.Z) - normal * 0.6, right, up), solidColor)
		solid.Parent = folder
		-- (toile un peu plus grande que la face : pas de joint visible dans les coins)
		local part, gui = newCanvas("Sky" .. name, at(center.X, center.Y, center.Z), right, up, width + 3, height + 3, DEPTH_FAR, 0, nil, skyPPS)
		local cw, ch = (width + 3) * skyPPS, (height + 3) * skyPPS
		local fill = Instance.new("Frame")
		fill.Name = "Sky"
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(1, 1)
		fill.ZIndex = 1
		fill.Parent = gui
		if kind == "Top" then
			fill.BackgroundColor3 = SKY_TOP_DAY
			table.insert(skyTops, fill)
		elseif kind == "Bottom" then
			fill.BackgroundColor3 = SKY_BOTTOM_DAY
			table.insert(skyBottoms, fill)
		else
			fill.BackgroundColor3 = WHITE
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Color = SKY_DAY
			gradient.Parent = fill
			table.insert(skyGradients, gradient)
			-- Nuages (au-dessus de l'horizon de la maison) et étincelles
			local seed = #skyGradients * 7
			for index = 1, 6 do
				local n = noise(seed + index, 1)
				local cloudW = (30 + 26 * n) * skyPPS
				local cx = cw * ((index - 0.5) / 6) + (noise(seed + index, 2) - 0.5) * 20 * skyPPS
				-- (autour et un peu au-dessus de l'horizon de la maison : visibles derrière elle)
				local cy = ch * (0.36 + 0.26 * noise(seed + index, 3))
				local holder = Instance.new("Frame")
				holder.Name = "Cloud" .. index
				holder.BackgroundTransparency = 1
				holder.Size = UDim2.fromScale(1, 1)
				holder.ZIndex = 2
				holder.Parent = gui
				HousePatterns.Cloud(holder, cx, cy, cloudW, WHITE, 0.25 + 0.3 * n, 1)
				table.insert(clouds, holder)
			end
		end
		if kind ~= "Bottom" then
			local seed = #stars
			local count = kind == "Top" and 26 or 14
			for index = 1, count do
				local starSize = (2.2 + 3 * noise(seed + index, 5)) * skyPPS
				local holder = Instance.new("Frame")
				holder.Name = "Star" .. index
				holder.BackgroundTransparency = 1
				holder.Size = UDim2.fromOffset(starSize, starSize)
				holder.AnchorPoint = Vector2.new(0.5, 0.5)
				holder.Position = UDim2.fromOffset(cw * noise(seed + index, 6), ch * (kind == "Top" and noise(seed + index, 7) or 0.05 + 0.5 * noise(seed + index, 7)))
				holder.ZIndex = 3
				holder.Parent = gui
				HousePatterns.Sparkle(holder, starSize / 2, starSize / 2, starSize, WHITE, 0.2, 1)
				table.insert(stars, holder)
			end
		end
		part.Parent = folder
	end

	local sx, sz = studioCenter.X, studioCenter.Z
	local skyH = yMax - yMin
	local skyMid = (yMax + yMin) / 2
	skyWall("Back", Vector3.new(sx, skyMid, sz - HZ), X_AXIS, Y_AXIS, HX * 2, skyH, "Side")
	skyWall("Front", Vector3.new(sx, skyMid, sz + HZ), -X_AXIS, Y_AXIS, HX * 2, skyH, "Side")
	skyWall("Left", Vector3.new(sx - HX, skyMid, sz), BACKWARD, Y_AXIS, HZ * 2, skyH, "Side")
	skyWall("Right", Vector3.new(sx + HX, skyMid, sz), -BACKWARD, Y_AXIS, HZ * 2, skyH, "Side")
	skyWall("Top", Vector3.new(sx, yMax, sz), X_AXIS, Vector3.new(0, 0, 1), HX * 2, HZ * 2, "Top")
	skyWall("Bottom", Vector3.new(sx, yMin, sz), X_AXIS, BACKWARD, HX * 2, HZ * 2, "Bottom")

	------------------------------------------------------------------
	-- Socle : pelouse fleurie sur un gâteau rose
	------------------------------------------------------------------
	local lawnW = W + WALL_T * 2 + LAWN_SIDE * 2
	local lawnZ0 = -WALL_T - LAWN_BACK
	local lawnZ1 = D + LAWN_FRONT
	local lawnD = lawnZ1 - lawnZ0
	local lawnTop = -SLAB
	newPart("Lawn", Vector3.new(lawnW, 0.8, lawnD), CFrame.new(at(0, lawnTop - 0.4, (lawnZ0 + lawnZ1) / 2)), GRASS).Parent = folder
	newPart("Base", Vector3.new(lawnW - 0.9, 2.6, lawnD - 0.9), CFrame.new(at(0, lawnTop - 0.8 - 1.3, (lawnZ0 + lawnZ1) / 2)), BASE_PINK).Parent = folder
	newPart("BaseTrim", Vector3.new(lawnW - 0.5, 0.3, lawnD - 0.5), CFrame.new(at(0, lawnTop - 0.8 - 2.45, (lawnZ0 + lawnZ1) / 2)), C.Cream).Parent = folder
	do
		local lawnPPS = 16
		local part, gui = newCanvas("LawnTop", at(0, lawnTop + 0.02, (lawnZ0 + lawnZ1) / 2), X_AXIS, BACKWARD, lawnW, lawnD, DEPTH_FAR, 0.15, nil, lawnPPS)
		local lawn = Instance.new("Frame")
		lawn.Name = "Lawn"
		lawn.BorderSizePixel = 0
		lawn.Size = UDim2.fromScale(1, 1)
		lawn.Parent = gui
		House3DFloor.Lawn(lawn, lawnW * lawnPPS, lawnD * lawnPPS, LAWN_SIDE * lawnPPS)
		addVeil(gui, 0.55)
		part.Parent = folder
	end

	------------------------------------------------------------------
	-- Dalle, murs, plinthes, moulures
	------------------------------------------------------------------
	newPart("Slab", Vector3.new(W + WALL_T * 2, SLAB, D + WALL_T), CFrame.new(at(0, -SLAB / 2, (D - WALL_T) / 2)), SHELL).Parent = folder
	do
		-- Tranche avant de la dalle (dégradé rose de la coque 2D + liseré crème)
		local part, gui = newCanvas("SlabFront", at(0, -SLAB / 2, D + 0.02), X_AXIS, Y_AXIS, W + WALL_T * 2, SLAB, DEPTH_FAR, 0.2, nil, 24)
		local fill = Instance.new("Frame")
		fill.Name = "Edge"
		fill.BackgroundColor3 = WHITE
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(1, 1)
		fill.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(Color3.fromRGB(255, 225, 238), Color3.fromRGB(236, 200, 230))
		gradient.Parent = fill
		local trim = Instance.new("Frame")
		trim.Name = "Trim"
		trim.BackgroundColor3 = C.Cream
		trim.BorderSizePixel = 0
		trim.Size = UDim2.new(1, 0, 0, 5)
		trim.ZIndex = 2
		trim.Parent = gui
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.BackgroundColor3 = C.PinkDeep
		line.BackgroundTransparency = 0.6
		line.BorderSizePixel = 0
		line.AnchorPoint = Vector2.new(0, 1)
		line.Position = UDim2.fromScale(0, 1)
		line.Size = UDim2.new(1, 0, 0, 3)
		line.ZIndex = 2
		line.Parent = gui
		addVeil(gui, 0.55)
		part.Parent = folder
	end

	newPart("WallBack", Vector3.new(W + WALL_T * 2, WH, WALL_T), CFrame.new(at(0, WH / 2, -WALL_T / 2)), SHELL).Parent = folder

	-- Papier peint d'un mur : mêmes dessins que la pièce 2D (px de maquette)
	local wallScale = PX * PPS
	local function paper(gui: SurfaceGui, widthPx: number): Frame
		local sheet = designFrame(gui, "Paper", widthPx, wallPx, wallScale, 1)
		-- (collé en bas : quand le mur de côté se baisse, on garde la plinthe)
		sheet.AnchorPoint = Vector2.new(0, 1)
		sheet.Position = UDim2.fromScale(0, 1)
		sheet.BackgroundTransparency = 0
		sheet.BackgroundColor3 = wallA
		sheet.ClipsDescendants = true
		HousePatterns.BuildWall(sheet, widthPx, wallPx, wallpaper, 1)
		-- Ombre au pied du mur, festons sous la moulure
		local ao = Box(sheet, 0, wallPx - 30, widthPx, 30, BLACK, 0.72, 20)
		fadeGradient(ao, 1, 0, 90)
		local scallop = 20
		local scallopColor = C.Pink:Lerp(wallB, 0.4)
		local x = scallop / 2
		while x < widthPx do
			Circle(sheet, x, 9, scallop - 2, 12, scallopColor, 0, 21)
			x += scallop
		end
		local band = Box(sheet, 0, 0, widthPx, 9, C.Cream, 0, 22)
		Box(band, 0, 7, widthPx, 2, wallB:Lerp(BLACK, 0.25), 0.55, 23)
		return sheet
	end

	-- Mur du fond
	local windowLeft2D = math.floor(SIDE_PX + roomWpx * 0.1)
	local windowW, windowH, windowTop = 104, 92, 36
	local windowX = wallCanvasX(windowLeft2D + windowW / 2) - windowW / 2 -- (px sur la toile)
	do
		local part, gui = newCanvas("WallBackPaper", at(0, WH / 2, 0.02), X_AXIS, Y_AXIS, W, WH, DEPTH_FAR, 0.18)
		local sheet = paper(gui, roomWpx)
		-- Lumière douce du haut-gauche (comme la pièce 2D)
		local sun = Box(sheet, 0, 0, roomWpx, wallPx, WHITE, 0.55, 19)
		local sunGradient = Instance.new("UIGradient")
		sunGradient.Rotation = 35
		sunGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sunGradient.Parent = sun
		table.insert(dayDecor, sun)

		-- Fenêtre (vitre, soleil / lune, croisillon) ; rebord, tringle et rideaux en relief
		local wx, wy = windowX, windowTop
		local outer = Box(sheet, wx, wy, windowW, windowH, C.Cream, 0, 24)
		Round(outer, UDim.new(0, 14))
		local outerStroke = Instance.new("UIStroke")
		outerStroke.Color = C.WoodDark
		outerStroke.Thickness = 2
		outerStroke.Transparency = 0.4
		outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outerStroke.Parent = outer
		local glass = Box(sheet, wx + 8, wy + 8, windowW - 16, windowH - 16, WHITE, 0, 25)
		Round(glass, UDim.new(0, 9))
		glass.ClipsDescendants = true
		local glassGradient = Instance.new("UIGradient")
		glassGradient.Rotation = 90
		glassGradient.Color = ColorSequence.new(Color3.fromRGB(150, 214, 255), Color3.fromRGB(255, 214, 236))
		glassGradient.Parent = glass
		windowGlass = glassGradient
		local sunDisc = Circle(glass, 62, 18, 16, 16, Color3.fromRGB(255, 230, 130), 0, 2)
		local cloudHolder = Box(glass, 0, 0, windowW - 16, windowH - 16, WHITE, 1, 2)
		HousePatterns.Cloud(cloudHolder, 30, 58, 34, WHITE, 0.05, 3)
		table.insert(dayDecor, sunDisc)
		table.insert(dayDecor, cloudHolder)
		local moon = Circle(glass, 60, 20, 18, 18, Color3.fromRGB(255, 244, 200), 0, 2)
		Circle(moon, 13, 6, 14, 14, Color3.fromRGB(40, 34, 95), 0, 3)
		table.insert(nightDecor, moon)
		for index, point in ipairs({ Vector2.new(16, 16), Vector2.new(30, 44), Vector2.new(70, 52), Vector2.new(44, 12) }) do
			local star = Circle(glass, point.X, point.Y, 3 + index % 2, 3 + index % 2, WHITE, 0.1, 2)
			table.insert(nightDecor, star)
		end
		Box(sheet, wx + windowW / 2 - 2, wy + 8, 4, windowH - 16, C.Cream, 0, 26)
		Box(sheet, wx + 8, wy + windowH / 2 - 2, windowW - 16, 4, C.Cream, 0, 26)
		local shine = Box(sheet, wx + 14, wy + 14, 16, 5, WHITE, 0.45, 27)
		Round(shine)
		local sillShadow = Box(sheet, wx - 4, wy + windowH + 6, windowW + 8, 12, BLACK, 0.85, 24)
		fadeGradient(sillShadow, 0.2, 1, 90)

		-- Prise électrique rigolote (à droite)
		local outletX = wallCanvasX(roomWpx - SIDE_PX - 70)
		local outlet = Box(sheet, outletX, wallPx - 44, 22, 26, WHITE, 0, 24)
		Round(outlet, UDim.new(0, 5))
		local outletStroke = Instance.new("UIStroke")
		outletStroke.Color = wallB:Lerp(BLACK, 0.35)
		outletStroke.Thickness = 1.5
		outletStroke.Transparency = 0.4
		outletStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outletStroke.Parent = outlet
		Circle(outlet, 7, 9, 3, 5, Color3.fromRGB(90, 70, 90), 0, 2)
		Circle(outlet, 15, 9, 3, 5, Color3.fromRGB(90, 70, 90), 0, 2)
		Circle(outlet, 11, 18, 6, 3, C.Pink, 0, 2)

		addVeil(gui, 0.46)
		part.Parent = folder
	end

	-- Relief de la fenêtre : rebord, tringle + boules, rideaux (carton)
	local windowCenterX = (windowX + windowW / 2 - roomWpx / 2) * PX
	local function wallHeightOf(y2d: number): number
		return (wallPx - y2d) * PX
	end
	newPart("TrimSill", Vector3.new((windowW + 16) * PX, 0.45, 0.24), CFrame.new(at(windowCenterX, wallHeightOf(windowTop + windowH + 1), 0.12)), C.Cream).Parent = folder
	do
		local rodLength = (windowW + 36) * PX
		local rodY = wallHeightOf(windowTop - 7.5)
		local rod = newPart("TrimRod", Vector3.new(rodLength, 0.2, 0.2), CFrame.new(at(windowCenterX, rodY, 0.34)), C.WoodDark)
		rod.Shape = Enum.PartType.Cylinder
		rod.Parent = folder
		for _, side in ipairs({ -1, 1 }) do
			local knob = newPart("TrimKnob", Vector3.new(0.46, 0.46, 0.46), CFrame.new(at(windowCenterX + side * rodLength / 2, rodY, 0.34)), C.PinkDeep)
			knob.Shape = Enum.PartType.Ball
			knob.Parent = folder
		end
		-- Rideaux : un carton juste devant le mur (dessin de la pièce 2D)
		local curtainW, curtainH = windowW + 64, windowH + 24
		local cardW, cardH = curtainW * PX, curtainH * PX
		local part, gui = newCanvas("Curtains", at(windowCenterX, wallHeightOf(windowTop - 6 + curtainH / 2), 0.26), X_AXIS, Y_AXIS, cardW, cardH, DEPTH_CARD, 0)
		local holder = designFrame(gui, "Curtains", curtainW, curtainH, wallScale, 1)
		for _, side in ipairs({ -1, 1 }) do
			local x = side < 0 and 18 or curtainW - 48
			local curtain = Box(holder, x, 0, 30, windowH + 10, C.Pink, 0, 2)
			Round(curtain, UDim.new(0, 10))
			local folds = Instance.new("UIGradient")
			folds.Rotation = 0
			folds.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, WHITE),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 215, 225)),
				ColorSequenceKeypoint.new(1, WHITE),
			})
			folds.Parent = curtain
			Box(curtain, 9, 4, 2, windowH, C.PinkDeep, 0.7, 2)
			Box(curtain, 19, 4, 2, windowH, C.PinkDeep, 0.7, 2)
			local tie = Box(holder, x - 2, windowH * 0.56, 34, 7, C.PinkDeep, 0, 3)
			Round(tie)
			HousePatterns.Heart(holder, x + 15, windowH * 0.56 + 3, 12, WHITE, 0, 4)
		end
		table.insert(cardGuis, gui)
		part.Parent = folder
	end

	-- Murs de côté (se baissent quand la caméra passe derrière eux)
	local crownH = 0.4
	for _, side in ipairs({ -1, 1 }) do
		local solid = newPart(side < 0 and "WallLeft" or "WallRight", Vector3.new(WALL_T, WH, D), CFrame.new(at(side * (W / 2 + WALL_T / 2), WH / 2, D / 2)), SHELL)
		solid.Parent = folder
		-- toile tournée vers l'intérieur : gauche -> droite = vers le fond (gauche) / vers l'avant (droite)
		local right = side < 0 and BACKWARD or -BACKWARD
		local part, gui = newCanvas(side < 0 and "WallLeftPaper" or "WallRightPaper", at(side * (W / 2 - 0.02), WH / 2, D / 2), right, Y_AXIS, D, WH, DEPTH_FAR, 0.18)
		local sheet = paper(gui, DEPTH_PX)
		-- Un peu plus sombre que le fond (comme les murs de côté 2D), plus sombre vers l'avant
		local shade = Box(sheet, 0, 0, DEPTH_PX, wallPx, BLACK, side < 0 and 0.86 or 0.9, 19)
		local shadeGradient = Instance.new("UIGradient")
		shadeGradient.Rotation = 0
		shadeGradient.Transparency = side < 0 and NumberSequence.new(0, 0.5) or NumberSequence.new(0.5, 0)
		shadeGradient.Parent = shade
		addVeil(gui, 0.46)
		part.Parent = folder
		local crown = newPart("TrimCrownSide", Vector3.new(0.34, crownH, D), CFrame.new(at(side * (W / 2 - 0.17), WH - crownH / 2, D / 2)), C.Cream)
		crown.Parent = folder
		newPart("TrimSkirtSide", Vector3.new(0.2, 0.6, D), CFrame.new(at(side * (W / 2 - 0.1), 0.3, D / 2)), C.Cream).Parent = folder
		table.insert(sideWalls, { Side = side, Solid = solid, Canvas = part, Crown = crown, Lowered = false })
	end
	newPart("TrimSkirtBack", Vector3.new(W, 0.6, 0.2), CFrame.new(at(0, 0.3, 0.1)), C.Cream).Parent = folder
	newPart("TrimCrownBack", Vector3.new(W, crownH, 0.34), CFrame.new(at(0, WH - crownH / 2, 0.17)), C.Cream).Parent = folder

	------------------------------------------------------------------
	-- Sol
	------------------------------------------------------------------
	do
		local part, gui = newCanvas("Floor", at(0, 0.02, D / 2), X_AXIS, BACKWARD, W, D, DEPTH_FAR, 0.18)
		local floor = designFrame(gui, "Floor", roomWpx, DEPTH_PX, wallScale, 1)
		floor.BackgroundTransparency = 0
		floor.BackgroundColor3 = floorStyle and floorStyle.A or C.Lilac
		floor.ClipsDescendants = true
		House3DFloor.Paint(floor, roomWpx, DEPTH_PX, floorStyle, 1)
		-- Ombres douces au pied des murs
		local back = Box(floor, 0, 0, roomWpx, 34, BLACK, 0.7, 20)
		fadeGradient(back, 0, 1, 90)
		for _, side in ipairs({ -1, 1 }) do
			local strip = Box(floor, side < 0 and 0 or roomWpx - 26, 0, 26, DEPTH_PX, BLACK, 0.78, 20)
			fadeGradient(strip, side < 0 and 0 or 1, side < 0 and 1 or 0, 0)
		end
		-- Bord avant un peu plus sombre (la maison de poupée "en coupe")
		local front = Box(floor, 0, DEPTH_PX - 40, roomWpx, 40, BLACK, 0.82, 20)
		fadeGradient(front, 1, 0, 90)
		-- Tache de soleil de la fenêtre (tranches de plus en plus larges vers l'avant)
		local slices = 8
		for index = 1, slices do
			local t = (index - 1) / slices
			local sliceD = DEPTH_PX * 0.62 / slices
			local sliceW = windowW * (0.9 + t * 0.9)
			local x = windowX + windowW / 2 - sliceW / 2 + t * 70
			local slice = Box(floor, x, 12 + (index - 1) * sliceD, sliceW, sliceD + 0.5, WHITE, 0.7, 21)
			Round(slice, UDim.new(0, 6))
			table.insert(beamSlices, slice)
		end
		addVeil(gui, 0.46)
		part.Parent = folder
	end

	------------------------------------------------------------------
	-- Lumières
	------------------------------------------------------------------
	local function lightAnchor(name: string, position: Vector3, target: Vector3?): Part
		local cframe = target and CFrame.lookAt(position, target) or CFrame.new(position)
		local anchor = newPart(name, Vector3.new(0.2, 0.2, 0.2), cframe, WHITE, 1)
		anchor.Parent = folder
		return anchor
	end
	do
		local anchor = lightAnchor("CeilingLight", at(0, WH + 2.5, D * 0.45), nil)
		local light = Instance.new("PointLight")
		light.Range = 45
		light.Shadows = false
		light.Parent = anchor
		ceilingLight = light
		local sunAnchor = lightAnchor("WindowLight", at(windowCenterX, wallHeightOf(windowTop + windowH / 2), 0.9), at(windowCenterX + 5, 0, D * 0.62))
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 62
		spot.Range = 34
		spot.Shadows = false
		spot.Parent = sunAnchor
		sunLight = spot
	end

	------------------------------------------------------------------
	-- Nuit
	------------------------------------------------------------------
	local function applyNight()
		for _, veil in ipairs(veils) do
			veil.Visible = night
		end
		for _, gradient in ipairs(skyGradients) do
			gradient.Color = night and SKY_NIGHT or SKY_DAY
		end
		for _, fill in ipairs(skyTops) do
			fill.BackgroundColor3 = night and SKY_TOP_NIGHT or SKY_TOP_DAY
		end
		for _, fill in ipairs(skyBottoms) do
			fill.BackgroundColor3 = night and SKY_BOTTOM_NIGHT or SKY_BOTTOM_DAY
		end
		for _, holder in ipairs(clouds) do
			for _, child in ipairs(holder:GetDescendants()) do
				if child:IsA("Frame") and child.BackgroundTransparency < 1 then
					child.BackgroundColor3 = night and Color3.fromRGB(118, 104, 178) or WHITE
				end
			end
		end
		for _, holder in ipairs(stars) do
			for _, child in ipairs(holder:GetDescendants()) do
				if child:IsA("Frame") and child.BackgroundTransparency < 1 then
					child.BackgroundColor3 = night and Color3.fromRGB(255, 244, 190) or WHITE
					child.BackgroundTransparency = night and 0.05 or 0.55
				end
			end
		end
		for _, object in ipairs(dayDecor) do
			object.Visible = not night
		end
		for _, object in ipairs(nightDecor) do
			object.Visible = night
		end
		local glass = windowGlass
		if glass then
			glass.Color = night and ColorSequence.new(Color3.fromRGB(24, 22, 70), Color3.fromRGB(80, 60, 150))
				or ColorSequence.new(Color3.fromRGB(150, 214, 255), Color3.fromRGB(255, 214, 236))
		end
		for index, slice in ipairs(beamSlices) do
			slice.BackgroundColor3 = night and Color3.fromRGB(170, 190, 255) or Color3.fromRGB(255, 246, 220)
			slice.BackgroundTransparency = (night and 0.82 or 0.66) + index * 0.025
		end
		for _, gui in ipairs(cardGuis) do
			gui.Brightness = night and 0.72 or 1
		end
		for _, gui in ipairs(lampGuis) do
			gui.Brightness = night and 1.1 or 1
		end
		for _, ring in ipairs(lampRings) do
			local index = tonumber(ring:GetAttribute("Ring")) or 1
			local info = GLOW_RINGS[index] or GLOW_RINGS[1]
			ring.BackgroundTransparency = night and info.Night or info.Day
		end
		for _, light in ipairs(itemLights) do
			light.Brightness = night and 1.6 or 0.45
		end
		local ceiling = ceilingLight
		if ceiling then
			ceiling.Brightness = night and 0.55 or 0.9
			ceiling.Color = night and Color3.fromRGB(255, 214, 170) or Color3.fromRGB(255, 244, 230)
		end
		local spot = sunLight
		if spot then
			spot.Brightness = night and 0.6 or 1.5
			spot.Color = night and Color3.fromRGB(150, 170, 255) or Color3.fromRGB(255, 236, 200)
		end
	end
	applyNight()
	folder.Parent = workspace

	------------------------------------------------------------------
	-- Objets
	------------------------------------------------------------------
	-- (copie : la pièce peut changer pendant la vue ; valeurs invalides corrigées)
	local function finite(value: any, default: number): number
		local number = tonumber(value)
		if number == nil or number ~= number or number == math.huge or number == -math.huge then
			return default
		end
		return number
	end
	local entries: { Placed } = {}
	local roomPlaced = type(room) == "table" and room.Placed or nil
	if type(roomPlaced) == "table" then
		for _, raw in ipairs(roomPlaced) do
			if type(raw) == "table" and type(raw.I) == "string" and HouseCommon.ItemsById[raw.I] then
				table.insert(entries, {
					I = raw.I,
					X = math.clamp(finite(raw.X, 0.5), 0, 1),
					Y = math.clamp(finite(raw.Y, 0.8), 0, 1),
					S = math.clamp(finite(raw.S, 1), 0.2, 3),
					Z = finite(raw.Z, 0),
					F = raw.F == true or nil,
				})
			end
		end
	end

	-- Dessin d'un objet dans sa boîte (hors écran : monté plus tard)
	local function paintItem(entry: Placed, item: Item, order: number): Build
		local wall = item.Placement == "Wall"
		local marginTop = wall and CARD_MARGIN_WALL or CARD_MARGIN_TOP
		local marginBottom = wall and CARD_MARGIN_WALL or CARD_MARGIN_BOTTOM
		local content = Instance.new("Frame")
		content.Name = item.Id
		content.BackgroundTransparency = 1
		content.BorderSizePixel = 0
		content.Size = UDim2.fromOffset(100 + CARD_MARGIN_X * 2, 100 + marginTop + marginBottom)
		local body = Instance.new("Frame")
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.BorderSizePixel = 0
		body.Position = UDim2.fromOffset(CARD_MARGIN_X, marginTop)
		body.Size = UDim2.fromOffset(100, 100)
		body.ZIndex = 3
		body.Parent = content
		local painted = HouseArt.Paint(body, item, true)
		local detail: HouseArt.Result = painted or {}
		if painted == nil or detail.ShowEmoji == true then
			local emojiScale = detail.EmojiScale or 1
			local emoji = Instance.new("TextLabel")
			emoji.Name = "Emoji"
			emoji.AnchorPoint = Vector2.new(0.5, 0.5)
			emoji.Position = UDim2.fromScale(0.5, detail.EmojiY or (wall and 0.5 or 0.54))
			emoji.Size = UDim2.fromOffset(100 * emojiScale, 100 * emojiScale)
			emoji.BackgroundTransparency = 1
			emoji.Font = Enum.Font.BuilderSansMedium
			emoji.Text = item.Icon
			emoji.TextColor3 = WHITE
			emoji.TextSize = math.floor(88 * emojiScale)
			emoji.TextYAlignment = wall and Enum.TextYAlignment.Center or Enum.TextYAlignment.Bottom
			emoji.ZIndex = 9
			emoji.Parent = body
		end
		-- Objet retourné (chaise tournée vers la table...) : dessin en miroir
		if entry.F == true then
			HouseArt.Mirror(body, {}, 50)
		end
		local flat = detail.Flat == true and not wall
		-- Halo des lumières (derrière le dessin)
		local glowColor = detail.Glow or (item.Category == "Lights" and detail.Bulbs == nil and C.Butter or nil)
		local rings: { Frame } = {}
		if glowColor then
			local halo = Instance.new("Frame")
			halo.Name = "Glow"
			halo.AnchorPoint = Vector2.new(0.5, 0.5)
			halo.Position = UDim2.fromOffset(CARD_MARGIN_X + 50, marginTop + 50)
			halo.Size = UDim2.fromOffset(150, 150)
			halo.BackgroundTransparency = 1
			halo.ZIndex = 1
			halo.Parent = content
			for index, ring in ipairs(GLOW_RINGS) do
				local circle = Instance.new("Frame")
				circle.Name = "Ring" .. index
				circle.AnchorPoint = Vector2.new(0.5, 0.5)
				circle.Position = UDim2.fromScale(0.5, 0.5)
				circle.Size = UDim2.fromScale(ring.Size, ring.Size)
				circle.BackgroundColor3 = glowColor
				circle.BackgroundTransparency = night and ring.Night or ring.Day
				circle.BorderSizePixel = 0
				circle.ZIndex = 1
				circle:SetAttribute("Ring", index)
				circle.Parent = halo
				Round(circle)
				table.insert(rings, circle)
			end
		end
		-- Ombre douce d'un objet mural (sur le carton, décalée comme en 2D)
		if wall then
			local shadowSize = detail.WallShadow or Vector2.new(0.66, 0.66)
			if shadowSize.X > 0 then
				local soft = Instance.new("Frame")
				soft.Name = "WallShadow"
				soft.AnchorPoint = Vector2.new(0.5, 0.5)
				soft.Position = UDim2.fromOffset(CARD_MARGIN_X + 50 + 5, marginTop + 50 + 8)
				soft.Size = UDim2.fromOffset(100 * shadowSize.X, 100 * shadowSize.Y)
				soft.BackgroundColor3 = BLACK
				soft.BackgroundTransparency = 0.88
				soft.BorderSizePixel = 0
				soft.ZIndex = 2
				soft.Parent = content
				Round(soft, UDim.new(0.2, 0))
			end
		end
		local sizePx = item.Size * entry.S
		return {
			Entry = entry,
			Item = item,
			Order = order,
			SizePx = sizePx,
			K = sizePx * PX / 100,
			Content = content,
			Kind = wall and "Wall" or (flat and "Flat" or "Floor"),
			Glow = glowColor,
			Rings = rings,
			Parent = nil,
			Relation = nil,
			Top = nil,
			X = 0,
			H = 0,
			Z = 0,
			Done = false,
			Rank = 0,
			Light = false,
		}
	end

	-- Relations (posé sur / rangé à), groupes, positions 3D
	local function layout(builds: { Build })
		local byEntry: { [Placed]: Build } = {}
		local list: { Placed } = {}
		for _, build in ipairs(builds) do
			byEntry[build.Entry] = build
			table.insert(list, build.Entry)
		end
		local seatedAt = (HouseSurfaces :: any).SeatedAt
		for _, build in ipairs(builds) do
			if build.Kind ~= "Wall" then
				local okSupport, support = pcall(HouseSurfaces.SupportOf, build.Entry, list, roomWpx, roomHpx)
				local supportEntry = okSupport and type(support) == "table" and support.Entry or nil
				if supportEntry and byEntry[supportEntry] and supportEntry ~= build.Entry then
					build.Parent = byEntry[supportEntry]
					build.Relation = "On"
					if build.Kind == "Flat" then
						build.Kind = "Floor"
					end
				elseif type(seatedAt) == "function" then
					local okSeat, seat = pcall(seatedAt, build.Entry, list, roomWpx, roomHpx)
					local tableEntry = okSeat and type(seat) == "table" and seat.Table or nil
					if tableEntry and byEntry[tableEntry] and tableEntry ~= build.Entry and build.Kind == "Floor" then
						build.Parent = byEntry[tableEntry]
						build.Relation = "At"
					end
				end
			end
		end
		-- Racine de chaque groupe (chaîne courte ; une boucle éventuelle est coupée)
		for _, build in ipairs(builds) do
			local top = build
			local steps = 0
			while top.Parent and steps < 8 do
				top = top.Parent :: Build
				steps += 1
			end
			if steps >= 8 then
				build.Parent = nil
				build.Relation = nil
				top = build
			end
			build.Top = top
		end

		-- Ordre d'affichage 2D (muraux, tapis, sol ; couche Z puis Y)
		local okOrder, ordered = pcall(HouseSurfaces.Order, list, roomWpx, roomHpx, function(entry: Placed): number
			local build = byEntry[entry]
			if not build or build.Kind == "Wall" then
				return 0
			end
			return build.Kind == "Flat" and 1 or 2
		end)
		local order: { Build } = {}
		if okOrder and type(ordered) == "table" then
			for _, entry in ipairs(ordered) do
				local build = byEntry[entry]
				if build then
					table.insert(order, build)
				end
			end
		end
		if #order ~= #builds then
			order = table.clone(builds)
			table.sort(order, function(a, b)
				local ra = a.Kind == "Wall" and 0 or (a.Kind == "Flat" and 1 or 2)
				local rb = b.Kind == "Wall" and 0 or (b.Kind == "Flat" and 1 or 2)
				if ra ~= rb then
					return ra < rb
				end
				if a.Entry.Z ~= b.Entry.Z then
					return a.Entry.Z < b.Entry.Z
				end
				return a.Entry.Y < b.Entry.Y
			end)
		end

		-- Racines : position d'après X / Y
		local wallRank, flatRank = 0, 0
		local floorRoots: { Build } = {}
		for rank, build in ipairs(order) do
			build.Rank = rank
			if build.Top == build then
				local entry = build.Entry
				local half = math.min(build.SizePx * PX * 0.38, W / 2)
				if build.Kind == "Wall" then
					build.X = mapX(entry.X, 0, half)
					build.H = math.max(0.3, (wallPx - entry.Y * roomHpx) * PX)
					build.Z = Z_WALL + wallRank * Z_WALL_STEP
					wallRank += 1
				else
					local t = depthOf(entry.Y)
					build.X = mapX(entry.X, t, half)
					build.H = 0
					if build.Kind == "Flat" then
						build.Z = math.clamp(t * D, 0.6, D - 0.2)
						build.Rank = flatRank
						flatRank += 1
					else
						-- Profondeur réelle ; un carton qui chevauche un carton dessiné
						-- avant lui (en 2D) passe devant lui d'au moins GAP
						local z = math.clamp(t * D, Z_FLOOR_MIN, D - 0.3)
						for _, other in ipairs(floorRoots) do
							local reach = (build.SizePx + other.SizePx) * PX * 0.42
							if math.abs(other.X - build.X) < reach then
								z = math.max(z, other.Z + GAP)
							end
						end
						build.Z = math.min(z, D - 0.3)
						table.insert(floorRoots, build)
					end
				end
				build.Done = true
			end
		end

		-- Membres des groupes : même plan que leur meuble / leur table
		local function place(build: Build, guard: number)
			if build.Done or guard > 10 then
				return
			end
			local parent = build.Parent
			local top = build.Top
			if not parent or not top then
				build.Done = true
				return
			end
			place(parent, guard + 1)
			build.X = top.X + (build.Entry.X - top.Entry.X) * roomWpx * PX
			if build.Relation == "On" then
				build.Z = math.min(parent.Z + GAP, D - 0.1)
				-- pieds à la hauteur du dessus : repère du premier ancêtre posé au sol / au mur
				local ground = parent
				local steps = 0
				while ground.Relation == "On" and ground.Parent and steps < 8 do
					ground = ground.Parent :: Build
					steps += 1
				end
				if ground.Kind == "Wall" then
					build.H = (wallPx - build.Entry.Y * roomHpx) * PX
				else
					build.H = ground.H + (ground.Entry.Y - build.Entry.Y) * roomHpx * PX
				end
				build.H = math.max(0, build.H)
			else
				-- chaise rangée à une table : au sol, devant / derrière / à côté d'elle
				local dz = (depthOf(build.Entry.Y) - depthOf(parent.Entry.Y)) * D
				if dz >= 0 then
					dz = math.max(dz, GAP)
				else
					dz = math.min(dz, -GAP)
				end
				build.Z = math.clamp(parent.Z + dz, Z_FLOOR_MIN * 0.5, D - 0.2)
				build.H = 0
			end
			build.Done = true
		end
		for _, build in ipairs(order) do
			place(build, 0)
		end
		return order
	end

	-- Carton (ou tapis) + ombre au sol + lumière
	local itemFolder = Instance.new("Folder")
	itemFolder.Name = "Items"
	itemFolder.Parent = folder

	local function mount(build: Build, delay: number)
		local k = build.K
		local wall = build.Kind == "Wall"
		local marginTop = wall and CARD_MARGIN_WALL or CARD_MARGIN_TOP
		local marginBottom = wall and CARD_MARGIN_WALL or CARD_MARGIN_BOTTOM
		local unitsW = 100 + CARD_MARGIN_X * 2
		local unitsH = 100 + marginTop + marginBottom
		local content = build.Content
		local name = build.Item.Id
		if build.Kind == "Flat" then
			-- Tapis : à plat, rallongé en profondeur (le dessin 2D est "écrasé")
			local kz = k * FLAT_STRETCH
			local zCenter = build.Z + (marginBottom - (100 + marginTop)) / 2 * kz
			local part, gui = newCanvas("Rug_" .. name, at(build.X, 0.03 + build.Rank * 0.004, zCenter), X_AXIS, BACKWARD, unitsW * k, unitsH * kz,
				DEPTH_RUG - build.Rank * 4, 0, Vector2.new(unitsW * FLAT_RES, unitsH * FLAT_RES))
			local uiScale = Instance.new("UIScale")
			uiScale.Scale = FLAT_RES
			uiScale.Parent = content
			content.Parent = gui
			table.insert(cardGuis, gui)
			gui.Brightness = night and 0.72 or 1
			part.Parent = itemFolder
			return
		end
		-- Carton debout (pieds de la boîte en H) ou objet mural (centre en H)
		local centerH = wall and build.H + (marginTop - marginBottom) / 2 * k or build.H + (50 + (marginTop - marginBottom) / 2) * k
		local target = at(build.X, centerH, build.Z)
		local part, gui = newCanvas("Card_" .. name, target, X_AXIS, Y_AXIS, unitsW * k, unitsH * k, DEPTH_CARD, 0)
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = k * PPS
		uiScale.Parent = content
		content.Parent = gui
		if build.Glow then
			table.insert(lampGuis, gui)
			for _, ring in ipairs(build.Rings) do
				table.insert(lampRings, ring)
			end
			gui.Brightness = night and 1.1 or 1
		else
			table.insert(cardGuis, gui)
			gui.Brightness = night and 0.72 or 1
		end
		-- Ombre douce au sol (objets posés au sol)
		local grounded = not wall and build.Relation ~= "On"
		local shadowPart: Part? = nil
		if grounded then
			local sw = build.SizePx * PX * 0.95
			local sd = build.SizePx * PX * 0.36
			local shadow, shadowGui = newCanvas("Shadow_" .. name, at(build.X, 0.04, build.Z - sd * 0.12), X_AXIS, BACKWARD, sw, sd, DEPTH_SHADOW,
				0, Vector2.new(200, 80))
			for index, info in ipairs({ { 1, 0.9 }, { 0.74, 0.86 }, { 0.48, 0.8 } }) do
				local oval = Instance.new("Frame")
				oval.Name = "Oval" .. index
				oval.AnchorPoint = Vector2.new(0.5, 0.5)
				oval.Position = UDim2.fromScale(0.5, 0.5)
				oval.Size = UDim2.fromScale(info[1], info[1])
				oval.BackgroundColor3 = BLACK
				oval.BackgroundTransparency = info[2]
				oval.BorderSizePixel = 0
				oval.ZIndex = index
				oval.Parent = shadowGui
				Round(oval)
			end
			shadow.Parent = itemFolder
			shadowPart = shadow
		end
		-- Lumière des lampes (quelques-unes, les plus grosses d'abord)
		if build.Glow and build.Light then
			local lampCenter = wall and at(build.X, build.H, build.Z + 0.6) or at(build.X, build.H + 50 * k, build.Z + 0.6)
			local anchor = newPart("LampLight", Vector3.new(0.2, 0.2, 0.2), CFrame.new(lampCenter), WHITE, 1)
			local light = Instance.new("PointLight")
			light.Color = build.Glow :: Color3
			light.Range = math.clamp(6 + build.SizePx * PX * 1.4, 7, 16)
			light.Brightness = night and 1.6 or 0.45
			light.Shadows = false
			light.Parent = anchor
			anchor.Parent = itemFolder
			table.insert(itemLights, light)
		end
		-- Arrivée : l'objet tombe doucement à sa place, son ombre grandit
		local finalCFrame = part.CFrame
		part.CFrame = finalCFrame + Vector3.new(0, DROP, 0)
		part.Parent = itemFolder
		local info = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
		TweenService:Create(part, info, { CFrame = finalCFrame }):Play()
		local shadowNow = shadowPart
		if shadowNow then
			local fullSize = shadowNow.Size
			shadowNow.Size = Vector3.new(fullSize.X * 0.3, fullSize.Y * 0.3, fullSize.Z)
			TweenService:Create(shadowNow, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay), { Size = fullSize }):Play()
		end
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
		BoundsMax = at(W / 2 + WALL_T, WH + 0.4, D + 0.3),
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
			-- 1. dessins (hors écran)
			for index, entry in ipairs(entries) do
				local item = HouseCommon.ItemsById[entry.I]
				local ok, result = pcall(paintItem, entry, item, index)
				if ok then
					table.insert(builds, result)
				else
					warn("[House3D] Objet " .. tostring(entry.I) .. " : " .. tostring(result))
				end
				done += 1
				if not breathe() then
					return
				end
			end
			-- 2. positions
			local okLayout, order = pcall(layout, builds)
			if not okLayout then
				warn("[House3D] Disposition : " .. tostring(order))
				order = builds
				for _, build in ipairs(builds) do
					build.Top = build
					build.X = mapX(build.Entry.X, depthOf(build.Entry.Y), 0)
					build.Z = math.clamp(depthOf(build.Entry.Y) * D, Z_FLOOR_MIN, D - 0.3)
					build.H = build.Kind == "Wall" and (wallPx - build.Entry.Y * roomHpx) * PX or 0
				end
			end
			if not alive() or destroyed then
				return
			end
			-- 3. montage (les lampes les plus grosses reçoivent une vraie lumière)
			local lampOrder = {}
			for _, build in ipairs(order :: { Build }) do
				if build.Glow then
					table.insert(lampOrder, build)
				end
			end
			table.sort(lampOrder, function(a, b)
				return a.SizePx > b.SizePx
			end)
			for index, build in ipairs(lampOrder) do
				build.Light = index <= MAX_ITEM_LIGHTS
			end
			for index, build in ipairs(order :: { Build }) do
				local topRank = build.Top and build.Top.Rank or index
				local ok, err = pcall(mount, build, 0.05 + math.min(1.2, topRank * 0.035))
				if not ok then
					warn("[House3D] Objet " .. tostring(build.Entry.I) .. " : " .. tostring(err))
				end
				done += 1
				if not breathe() then
					return
				end
			end
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
					local height = lower and 1.3 or WH
					local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					local x = wall.Side * (W / 2 + WALL_T / 2)
					TweenService:Create(wall.Solid, info, {
						Size = Vector3.new(WALL_T, height, D),
						CFrame = CFrame.new(at(x, height / 2, D / 2)),
					}):Play()
					local right = wall.Side < 0 and BACKWARD or -BACKWARD
					local normal = right:Cross(Y_AXIS)
					TweenService:Create(wall.Canvas, info, {
						Size = Vector3.new(D, height, DEPTH_FAR),
						CFrame = CFrame.fromMatrix(at(wall.Side * (W / 2 - 0.02), height / 2, D / 2) - normal * (DEPTH_FAR / 2), right, Y_AXIS),
					}):Play()
					TweenService:Create(wall.Crown, info, {
						CFrame = CFrame.new(at(wall.Side * (W / 2 - 0.17), height - crownH / 2, D / 2)),
					}):Play()
				end
			end
		end,
		Destroy = function()
			destroyed = true
			folder:Destroy()
		end,
	}
	return scene
end

return House3DScene
