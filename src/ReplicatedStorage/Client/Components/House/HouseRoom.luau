--[[
	HouseRoom (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseRoom

	Dessin de la pièce kawaii "en coupe" (maison de poupée) :
	  - coque arrondie (plafond, côtés, dalle du sol) avec ombre douce et
	    festons sous le plafond ;
	  - mur du fond avec le papier peint (HousePatterns), murs de côté en
	    perspective (plus sombres), arêtes, plinthe et moulure ;
	  - sol en perspective (HousePatterns) avec ombre au pied du mur ;
	  - fenêtre à rideaux + tache de lumière sur le sol, prise électrique
	    rigolote, lumière douce du coin haut-gauche, vignettage ;
	  - mode nuit (mode sombre) : voile bleu nuit, lune et étoiles dans la
	    fenêtre, les lumières (catégorie "Lights") brillent davantage.
	  - objets = gros emojis "autocollants" (ombre portée, halo pour les
	    lumières, détails dessinés à la main pour certains objets : tapis,
	    guirlande, fenêtres, portes, cheminée, aquarium, frigo...).

	Coordonnées : la pièce fait (BASE_WIDTH x Width de la taille) x HEIGHT px
	de "maquette" ; un UIScale l'adapte à la place disponible (Stage).
	Un objet posé a X, Y entre 0 et 1 (fraction de la pièce) : objets "Floor"
	ancrés par le bas (leurs pieds), objets "Wall" par le centre.
	La pièce ignore l'habillage sombre automatique (DarkSkinIgnore) : elle
	gère elle-même son mode nuit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Signal = require(ReplicatedStorage.Shared.Signal)
local HouseCommon = require(script.Parent.HouseCommon)
local HousePatterns = require(script.Parent.HousePatterns)
local HouseArt = require(script.Parent.HouseArt)
local HouseScenery = require(script.Parent.HouseScenery)

type Item = HouseCommon.Item
type Placed = HouseCommon.Placed
type Style = HouseCommon.Style
type SizeDef = HouseCommon.SizeDef

local HouseRoom = {}

HouseRoom.BASE_WIDTH = 760 -- largeur de la plus petite maison (px de maquette)
HouseRoom.HEIGHT = 440
local SIDE = 42 -- profondeur apparente des murs de côté
local SHELL = 12 -- épaisseur de la coque (côtés, dalle du sol)
local CEIL = 20 -- épaisseur du plafond
local STICKER_BASE = 100 -- taille de base d'un autocollant (avant UIScale)

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle
local Round = HousePatterns.Round

export type Sticker = {
	Entry: Placed,
	Item: Item,
	Frame: Frame,
	Scale: UIScale,
	Body: Frame,
	Pop: UIScale,
	Shadow: Frame,
	Ring: Frame?, -- contour de sélection (créé à la première sélection)
	RingStroke: UIStroke?,
	Hit: TextButton,
	Glow: Frame?,
	Bulbs: { Frame },
	Anims: { HouseArt.Anim },
	Flat: boolean,
}

export type Room = {
	Stage: Frame,
	Frame: Frame,
	Items: Frame,
	Overlay: Frame,
	BackgroundHit: TextButton,
	Width: number,
	Height: number,
	WallHeight: number,
	Scale: number,
	Changed: any, -- Signal () : taille / échelle changée
	SetStyle: (size: SizeDef, wallpaper: Style?, floor: Style?) -> (),
	SetDark: (dark: boolean) -> (),
	IsDark: () -> boolean,
	ScreenToRoom: (position: Vector2) -> Vector2,
	CreateSticker: (item: Item, entry: Placed) -> Sticker,
	ApplySticker: (sticker: Sticker) -> (),
	ShowRing: (sticker: Sticker, visible: boolean) -> (),
	DestroySticker: (sticker: Sticker) -> (),
	SetZoneHint: (placement: string?) -> (),
	Update: (dt: number) -> (),
	Refit: () -> (),
}

----------------------------------------------------------------------
-- Construction de la pièce
----------------------------------------------------------------------

-- Halo de lumière : 3 cercles concentriques (un UIGradient ne fait que des
-- dégradés linéaires, pas radiaux). Plus visible et plus grand la nuit.
local GLOW_RINGS = {
	{ Size = 1, Day = 0.96, Night = 0.92 },
	{ Size = 0.8, Day = 0.94, Night = 0.88 },
	{ Size = 0.62, Day = 0.91, Night = 0.83 },
	{ Size = 0.46, Day = 0.88, Night = 0.77 },
	{ Size = 0.32, Day = 0.85, Night = 0.7 },
}

local function paintGlow(glow: Frame, dark: boolean)
	glow.Size = dark and UDim2.fromOffset(150, 150) or UDim2.fromOffset(120, 120)
	for index, ring in ipairs(GLOW_RINGS) do
		local circle = glow:FindFirstChild("Ring" .. index) :: Frame?
		if circle then
			circle.BackgroundTransparency = dark and ring.Night or ring.Day
		end
	end
end

local function gradientTransparency(frame: GuiObject, from: number, to: number, rotation: number)
	UIUtil.Create("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new(from, to),
		Parent = frame,
	})
end

function HouseRoom.new(stage: Frame): Room
	local room: Room
	local width = HouseRoom.BASE_WIDTH
	local height = HouseRoom.HEIGHT
	local wallHeight = math.floor(height * HouseCommon.Config.WallRatio + 0.5)
	local dark = false
	local styleKey = ""
	local stickers: { [Sticker]: boolean } = {}
	local clock = 0

	-- Sonde de taille fixe : sert à convertir AbsoluteSize en px de maquette
	local probe = UIUtil.Create("Frame", {
		Name = "Probe",
		Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1,
		Visible = true,
		Parent = stage,
	})

	local frame = UIUtil.Create("Frame", {
		Name = "Room",
		Size = UDim2.fromOffset(width, height),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	-- La pièce garde ses couleurs (mode nuit géré ici)
	frame:SetAttribute("DarkSkinIgnore", true)
	local scale = UIUtil.Create("UIScale", { Parent = frame })
	frame.Parent = stage

	-- Coque (derrière tout) : plafond, côtés, dalle du sol
	local shell = UIUtil.Create("Frame", {
		Name = "Shell",
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = frame,
	})
	Round(shell, UDim.new(0, 18))
	UIUtil.Stroke(shell, C.PinkDeep, 2, 0.45)
	UIUtil.Gradient(shell, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 238)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 206, 238)),
	}), 90)
	UIUtil.Shadow(shell, 8, 0.78, 5)

	local wall = UIUtil.Create("Frame", {
		Name = "Wall",
		BackgroundColor3 = C.PinkSoft,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = frame,
	})
	local floor = UIUtil.Create("Frame", {
		Name = "Floor",
		BackgroundColor3 = C.Lilac,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = frame,
	})
	local decor = UIUtil.Create("Frame", {
		Name = "Decor",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = frame,
	})
	local night = UIUtil.Create("Frame", {
		Name = "Night",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(34, 26, 92),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = frame,
	})
	-- Ciel, toit, pelouse et poussières de lumière (au-dessus du voile de nuit)
	local scenery = HouseScenery.new(stage, frame, SHELL, CEIL, 5)

	-- Clic dans le vide : désélectionne (branché par l'éditeur)
	local backgroundHit = UIUtil.Create("TextButton", {
		Name = "BackgroundHit",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 6,
		Parent = frame,
	})
	local zones = UIUtil.Create("Frame", {
		Name = "Zones",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = frame,
	})
	local items = UIUtil.Create("Frame", {
		Name = "Items",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = frame,
	})
	local overlay = UIUtil.Create("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = frame,
	})

	-- Zones mises en valeur pendant un glissement
	local wallZone = UIUtil.Create("Frame", {
		Name = "WallZone",
		BackgroundColor3 = C.Pink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = zones,
	})
	Round(wallZone, UDim.new(0, 10))
	local wallZoneStroke = UIUtil.Stroke(wallZone, WHITE, 3, 1)
	local floorZone = UIUtil.Create("Frame", {
		Name = "FloorZone",
		BackgroundColor3 = C.Pink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = zones,
	})
	Round(floorZone, UDim.new(0, 10))
	local floorZoneStroke = UIUtil.Stroke(floorZone, WHITE, 3, 1)

	-- Éléments de décor qui changent la nuit
	local windowGlassGradient: UIGradient? = nil
	local dayDecor: { GuiObject } = {}
	local nightDecor: { GuiObject } = {}
	local beamSlices: { Frame } = {}
	local sunLight: Frame? = nil

	local function applyNight()
		night.BackgroundTransparency = dark and 0.46 or 1
		scenery:SetDark(dark)
		local gradient = windowGlassGradient
		if gradient then
			if dark then
				gradient.Color = ColorSequence.new(Color3.fromRGB(24, 22, 70), Color3.fromRGB(80, 60, 150))
			else
				gradient.Color = ColorSequence.new(Color3.fromRGB(150, 214, 255), Color3.fromRGB(255, 214, 236))
			end
		end
		for _, object in ipairs(dayDecor) do
			object.Visible = not dark
		end
		for _, object in ipairs(nightDecor) do
			object.Visible = dark
		end
		for index, slice in ipairs(beamSlices) do
			slice.BackgroundColor3 = dark and Color3.fromRGB(170, 190, 255) or Color3.fromRGB(255, 246, 220)
			slice.BackgroundTransparency = (dark and 0.84 or 0.7) + index * 0.025
		end
		local sun = sunLight
		if sun then
			sun.Visible = not dark
		end
		for sticker in pairs(stickers) do
			local glow = sticker.Glow
			if glow then
				paintGlow(glow, dark)
			end
		end
	end

	-- Fenêtre fixe à rideaux (au mur, à gauche) + tache de lumière au sol
	local function buildWindow(windowX: number)
		local top = 36
		local w, h = 104, 92
		local outer = Box(decor, windowX, top, w, h, C.Cream, 0, 3)
		Round(outer, UDim.new(0, 14))
		UIUtil.Stroke(outer, C.WoodDark, 2, 0.4)
		local glass = Box(decor, windowX + 8, top + 8, w - 16, h - 16, WHITE, 0, 4)
		Round(glass, UDim.new(0, 9))
		windowGlassGradient = UIUtil.Gradient(glass, ColorSequence.new(WHITE, WHITE), 90)
		-- Jour : petit nuage et soleil ; nuit : lune et étoiles
		local sun = Circle(glass, 62, 18, 16, 16, Color3.fromRGB(255, 230, 130), 0, 5)
		local cloudHolder = Box(glass, 0, 0, w - 16, h - 16, WHITE, 1, 5)
		HousePatterns.Cloud(cloudHolder, 30, 58, 34, WHITE, 0.05, 6)
		table.insert(dayDecor, sun)
		table.insert(dayDecor, cloudHolder)
		local moon = Circle(glass, 60, 20, 18, 18, Color3.fromRGB(255, 244, 200), 0, 5)
		local moonBite = Circle(moon, 13, 6, 14, 14, Color3.fromRGB(40, 34, 95), 0, 6)
		moonBite.Name = "Bite"
		table.insert(nightDecor, moon)
		for index, point in ipairs({ Vector2.new(16, 16), Vector2.new(30, 44), Vector2.new(70, 52), Vector2.new(44, 12) }) do
			local star = Circle(glass, point.X, point.Y, 3 + index % 2, 3 + index % 2, WHITE, 0.1, 5)
			table.insert(nightDecor, star)
		end
		-- Croisillon
		Box(decor, windowX + w / 2 - 2, top + 8, 4, h - 16, C.Cream, 0, 5)
		Box(decor, windowX + 8, top + h / 2 - 2, w - 16, 4, C.Cream, 0, 5)
		local shine = Box(decor, windowX + 14, top + 14, 16, 5, WHITE, 0.45, 5)
		Round(shine)
		-- Rebord + ombre
		local sill = Box(decor, windowX - 8, top + h - 4, w + 16, 10, C.Cream, 0, 6)
		Round(sill, UDim.new(0, 4))
		UIUtil.Stroke(sill, C.WoodDark, 1.5, 0.5)
		local sillShadow = Box(decor, windowX - 4, top + h + 6, w + 8, 10, BLACK, 0.85, 3)
		gradientTransparency(sillShadow, 0.2, 1, 90)
		-- Tringle + rideaux
		local rod = Box(decor, windowX - 18, top - 10, w + 36, 5, C.WoodDark, 0, 7)
		Round(rod)
		Circle(decor, windowX - 18, top - 8, 10, 10, C.PinkDeep, 0, 7)
		Circle(decor, windowX + w + 18, top - 8, 10, 10, C.PinkDeep, 0, 7)
		for _, side in ipairs({ -1, 1 }) do
			local x = side < 0 and windowX - 14 or windowX + w - 16
			local curtain = Box(decor, x, top - 6, 30, h + 10, C.Pink, 0, 6)
			Round(curtain, UDim.new(0, 10))
			UIUtil.Gradient(curtain, ColorSequence.new({
				ColorSequenceKeypoint.new(0, WHITE),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 215, 225)),
				ColorSequenceKeypoint.new(1, WHITE),
			}), 0)
			-- Plis
			Box(curtain, 9, 4, 2, h, C.PinkDeep, 0.7, 6)
			Box(curtain, 19, 4, 2, h, C.PinkDeep, 0.7, 6)
			local tie = Box(decor, x - 2, top + h * 0.56, 34, 7, C.PinkDeep, 0, 7)
			Round(tie)
			HousePatterns.Heart(decor, x + 15, top + h * 0.56 + 3, 12, WHITE, 0, 8)
		end
		-- Tache de lumière au sol (tranches de plus en plus larges vers l'avant)
		table.clear(beamSlices)
		local slices = 8
		local floorHeight = height - wallHeight
		for index = 1, slices do
			local t = (index - 1) / slices
			local sliceH = floorHeight * 0.62 / slices
			local sliceW = w * (0.9 + t * 0.9)
			local x = windowX + w / 2 - sliceW / 2 + t * 70
			local slice = Box(decor, x, wallHeight + 6 + (index - 1) * sliceH, sliceW, sliceH + 0.5, WHITE, 0.7, 2)
			table.insert(beamSlices, slice)
		end
	end

	-- Reconstruit la coque, les murs, le sol et le décor fixe
	local function rebuild(wallpaper: Style?, floorStyle: Style?)
		for _, child in ipairs(decor:GetChildren()) do
			child:Destroy()
		end
		table.clear(dayDecor)
		table.clear(nightDecor)
		table.clear(beamSlices)
		windowGlassGradient = nil
		sunLight = nil

		frame.Size = UDim2.fromOffset(width, height)
		shell.Position = UDim2.fromOffset(-SHELL, -CEIL)
		shell.Size = UDim2.fromOffset(width + SHELL * 2, height + CEIL + SHELL)
		wall.Position = UDim2.fromOffset(0, 0)
		wall.Size = UDim2.fromOffset(width, wallHeight)
		floor.Position = UDim2.fromOffset(0, wallHeight)
		floor.Size = UDim2.fromOffset(width, height - wallHeight)
		wallZone.Position = UDim2.fromOffset(SIDE + 4, 4)
		wallZone.Size = UDim2.fromOffset(width - SIDE * 2 - 8, wallHeight - 8)
		floorZone.Position = UDim2.fromOffset(4, wallHeight + 4)
		floorZone.Size = UDim2.fromOffset(width - 8, height - wallHeight - 8)

		scenery:Rebuild(width, height, wallHeight)
		HousePatterns.BuildWall(wall, width, wallHeight, wallpaper, 1)
		HousePatterns.BuildFloor(floor, width, height - wallHeight, floorStyle, 1)

		local wallA = wallpaper and wallpaper.A or C.PinkSoft
		local wallB = wallpaper and wallpaper.B or C.Pink
		local floorB = floorStyle and floorStyle.B or C.Lilac

		-- Ombre au pied du mur + lumière douce du haut-gauche
		local ao = Box(decor, 0, wallHeight, width, 26, BLACK, 0.7, 1)
		gradientTransparency(ao, 0, 1, 90)
		local sun = Box(decor, 0, 0, width, height, WHITE, 0.55, 1)
		UIUtil.Create("UIGradient", {
			Rotation = 35,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.45, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = sun,
		})
		sunLight = sun
		local front = Box(decor, 0, height - 46, width, 46, BLACK, 0.8, 1)
		gradientTransparency(front, 1, 0.2, 90)

		-- Murs de côté en perspective (bande + triangle en tranches)
		local sideLeft = wallA:Lerp(wallB, 0.35):Lerp(BLACK, 0.12)
		local sideRight = wallA:Lerp(wallB, 0.25):Lerp(BLACK, 0.05)
		local floorHeight = height - wallHeight
		local slices = 14
		for _, info in ipairs({ { X = 0, Color = sideLeft, Dir = 1 }, { X = width - SIDE, Color = sideRight, Dir = -1 } }) do
			local strip = Box(decor, info.X, 0, SIDE, wallHeight, info.Color, 0, 3)
			UIUtil.Gradient(strip, ColorSequence.new(
				info.Dir > 0 and Color3.fromRGB(215, 215, 215) or WHITE,
				info.Dir > 0 and WHITE or Color3.fromRGB(225, 225, 225)
			), 0)
			for index = 0, slices - 1 do
				local sliceW = SIDE * (1 - index / slices)
				local x = info.Dir > 0 and 0 or width - sliceW
				Box(decor, x, wallHeight + index * floorHeight / slices, sliceW, floorHeight / slices + 0.6, info.Color, 0, 3)
			end
			-- Arête verticale du coin
			local edgeX = info.Dir > 0 and SIDE - 1 or width - SIDE - 1
			Box(decor, edgeX, 0, 2, wallHeight, wallB:Lerp(BLACK, 0.35), 0.45, 4)
			-- Arête du sol (diagonale)
			local startPoint = Vector2.new(info.Dir > 0 and SIDE or width - SIDE, wallHeight)
			local endPoint = Vector2.new(info.Dir > 0 and 0 or width, height)
			local delta = endPoint - startPoint
			local edge = Box(decor, 0, 0, delta.Magnitude, 2.5, floorB:Lerp(BLACK, 0.4), 0.3, 4)
			edge.AnchorPoint = Vector2.new(0.5, 0.5)
			edge.Position = UDim2.fromOffset((startPoint.X + endPoint.X) / 2, (startPoint.Y + endPoint.Y) / 2)
			edge.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		end

		-- Plinthe (mur du fond) + petite ombre
		local baseboard = Box(decor, SIDE, wallHeight - 11, width - SIDE * 2, 11, C.Cream, 0, 4)
		Box(baseboard, 0, 0, width - SIDE * 2, 2, WHITE, 0.2, 5)
		Box(baseboard, 0, 9, width - SIDE * 2, 2, wallB:Lerp(BLACK, 0.3), 0.5, 5)
		-- Moulure du plafond + festons
		local crown = Box(decor, 0, 0, width, 7, C.Cream, 0, 5)
		Box(crown, 0, 5, width, 2, wallB:Lerp(BLACK, 0.25), 0.55, 6)
		local scallop = 20
		local x = scallop / 2
		local scallopColor = C.Pink:Lerp(wallB, 0.4)
		while x < width do
			Circle(decor, x, 7, scallop - 2, 12, scallopColor, 0, 4)
			x += scallop
		end

		-- Fenêtre (à gauche) et prise électrique rigolote (à droite)
		buildWindow(math.floor(SIDE + width * 0.1))
		local outlet = Box(decor, width - SIDE - 70, wallHeight - 44, 22, 26, WHITE, 0, 4)
		Round(outlet, UDim.new(0, 5))
		UIUtil.Stroke(outlet, wallB:Lerp(BLACK, 0.35), 1.5, 0.4)
		Circle(outlet, 7, 9, 3, 5, Color3.fromRGB(90, 70, 90), 0, 5)
		Circle(outlet, 15, 9, 3, 5, Color3.fromRGB(90, 70, 90), 0, 5)
		Circle(outlet, 11, 18, 6, 3, C.Pink, 0, 5)

		applyNight()
	end

	-- Adapte l'échelle à la place disponible
	local function refit(force: boolean?)
		local factor = probe.AbsoluteSize.X / 100
		if factor <= 0 then
			return
		end
		local available = stage.AbsoluteSize / factor
		local fullW = width + SHELL * 2 + 76 -- (pelouse et toit débordent un peu)
		local roofH, groundH = HouseScenery.ROOF + 24, HouseScenery.GROUND
		local fullH = height + CEIL + SHELL + roofH + groundH + 16
		local newScale = math.max(0.2, math.min(available.X / fullW, available.Y / fullH))
		frame.Position = UDim2.new(0.5, 0, 0.5, (CEIL + roofH - SHELL - groundH) / 2 * newScale)
		if force == true or math.abs(newScale - room.Scale) > 1e-4 then
			room.Scale = newScale
			scale.Scale = newScale
			room.Changed:Fire()
		end
	end

	local function applySticker(sticker: Sticker)
		local entry = sticker.Entry
		local item = sticker.Item
		sticker.Frame.Position = UDim2.fromScale(entry.X, entry.Y)
		local stickerScale = item.Size * entry.S / STICKER_BASE
		sticker.Scale.Scale = stickerScale
		-- Contour de sélection : même épaisseur à l'écran quelle que soit la taille
		local stroke = sticker.RingStroke
		if stroke then
			stroke.Thickness = 3 / math.max(0.2, stickerScale)
		end
	end

	local function createSticker(item: Item, entry: Placed): Sticker
		local isWall = item.Placement == "Wall"
		local holder = UIUtil.Create("Frame", {
			Name = item.Id,
			Size = UDim2.fromOffset(STICKER_BASE, STICKER_BASE),
			AnchorPoint = isWall and Vector2.new(0.5, 0.5) or Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
		})
		local stickerScale = UIUtil.Create("UIScale", { Parent = holder })
		local shadow = UIUtil.Create("Frame", {
			Name = "Shadow",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
			Parent = holder,
		})
		local body = UIUtil.Create("Frame", {
			Name = "Body",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = holder,
		})
		local pop = UIUtil.Create("UIScale", { Name = "Pop", Parent = body })

		-- Dessin kawaii de l'objet (House/Art) ; sinon, l'emoji seul
		local painted, anims = HouseArt.Paint(body, item, false)
		local detail: HouseArt.Result = painted or {}
		local showEmoji = painted == nil or detail.ShowEmoji == true

		-- Halo des lumières
		local glowColor = detail.Glow or (item.Category == "Lights" and detail.Bulbs == nil and C.Butter or nil)
		local glow: Frame? = nil
		if glowColor then
			local halo = UIUtil.Create("Frame", {
				Name = "Glow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(150, 150),
				BackgroundTransparency = 1,
				ZIndex = 1,
				Parent = body,
			})
			for index, ring in ipairs(GLOW_RINGS) do
				local circle = UIUtil.Create("Frame", {
					Name = "Ring" .. index,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(ring.Size, ring.Size),
					BackgroundColor3 = glowColor,
					BackgroundTransparency = ring.Day,
					BorderSizePixel = 0,
					ZIndex = 1,
					Parent = halo,
				})
				Round(circle)
			end
			glow = halo
		end

		-- Emoji "autocollant"
		local emojiScale = detail.EmojiScale or 1
		UIUtil.Create("TextLabel", {
			Name = "Emoji",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, detail.EmojiY or (isWall and 0.5 or 0.54)),
			Size = UDim2.fromOffset(STICKER_BASE * emojiScale, STICKER_BASE * emojiScale),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = item.Icon,
			TextColor3 = WHITE,
			TextSize = math.floor(88 * emojiScale),
			TextYAlignment = isWall and Enum.TextYAlignment.Center or Enum.TextYAlignment.Bottom,
			Visible = showEmoji,
			ZIndex = 4,
			Parent = body,
		})

		-- Ombre portée : ovale au sol, ou ombre douce décalée au mur
		local flat = detail.Flat == true
		if isWall then
			local shadowSize = detail.WallShadow or Vector2.new(0.66, 0.66)
			if shadowSize.X > 0 then
				local soft = Box(shadow, 0, 0, 0, 0, BLACK, 0.9, 1)
				soft.AnchorPoint = Vector2.new(0.5, 0.5)
				soft.Position = UDim2.new(0.5, 5, 0.5, 8)
				soft.Size = UDim2.fromScale(shadowSize.X, shadowSize.Y)
				Round(soft, UDim.new(0.2, 0))
			end
		elseif not flat then
			Circle(shadow, 50, 97, 104, 18, BLACK, 0.9, 1)
			Circle(shadow, 50, 97, 70, 11, BLACK, 0.84, 1)
		end

		-- Zone de clic (un peu plus petite que la boîte, sauf les objets à plat)
		local hit = UIUtil.Create("TextButton", {
			Name = "Hit",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = flat and UDim2.fromScale(0.5, 0.8) or UDim2.fromScale(0.5, 0.52),
			Size = flat and UDim2.fromScale(1.4, 0.45) or UDim2.fromScale(0.84, 0.9),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			Parent = holder,
		})

		local sticker: Sticker = {
			Entry = entry,
			Item = item,
			Frame = holder,
			Scale = stickerScale,
			Body = body,
			Pop = pop,
			Shadow = shadow,
			Ring = nil,
			RingStroke = nil,
			Hit = hit,
			Glow = glow,
			Bulbs = detail.Bulbs or {},
			Anims = anims,
			Flat = flat,
		}
		stickers[sticker] = true
		if glow then
			paintGlow(glow, dark)
		end
		applySticker(sticker)
		holder.Parent = items
		return sticker
	end

	room = {
		Stage = stage,
		Frame = frame,
		Items = items,
		Overlay = overlay,
		BackgroundHit = backgroundHit,
		Width = width,
		Height = height,
		WallHeight = wallHeight,
		Scale = 1,
		Changed = Signal.new(),
		SetStyle = function(size: SizeDef, wallpaper: Style?, floorStyle: Style?)
			local newWidth = math.floor(HouseRoom.BASE_WIDTH * (tonumber(size.Width) or 1) + 0.5)
			local key = table.concat({
				tostring(newWidth),
				wallpaper and wallpaper.Id or "",
				floorStyle and floorStyle.Id or "",
			}, "|")
			if key == styleKey then
				return
			end
			local widthChanged = newWidth ~= width
			styleKey = key
			width = newWidth
			room.Width = newWidth
			rebuild(wallpaper, floorStyle)
			-- Nouvelle largeur : échelle recalculée (et signal Changed même si elle ne bouge pas)
			refit(widthChanged)
		end,
		SetDark = function(value: boolean)
			if dark == value then
				return
			end
			dark = value
			applyNight()
		end,
		IsDark = function(): boolean
			return dark
		end,
		ScreenToRoom = function(position: Vector2): Vector2
			local size = frame.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				return Vector2.new(0.5, 0.5)
			end
			return (position - frame.AbsolutePosition) / size
		end,
		CreateSticker = createSticker,
		ApplySticker = applySticker,
		ShowRing = function(sticker: Sticker, visible: boolean)
			local ring = sticker.Ring
			if not ring then
				if not visible then
					return
				end
				local flat = sticker.Flat
				local newRing = UIUtil.Create("Frame", {
					Name = "Ring",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = flat and UDim2.fromScale(0.5, 0.8) or UDim2.fromScale(0.5, 0.5),
					Size = flat and UDim2.fromScale(1.5, 0.5) or UDim2.fromScale(1.12, 1.12),
					BackgroundColor3 = C.Pink,
					BackgroundTransparency = 0.88,
					ZIndex = 3,
					Parent = sticker.Frame,
				})
				Round(newRing, UDim.new(0, 18))
				sticker.RingStroke = UIUtil.Stroke(newRing, C.PinkDeep, 3, 0)
				sticker.Ring = newRing
				ring = newRing
				applySticker(sticker)
			end
			(ring :: Frame).Visible = visible
		end,
		DestroySticker = function(sticker: Sticker)
			stickers[sticker] = nil
			sticker.Frame:Destroy()
		end,
		SetZoneHint = function(placement: string?)
			local function set(zone: Frame, stroke: UIStroke, state: string)
				local bg = state == "valid" and 0.82 or (state == "invalid" and 0.7 or 1)
				zone.BackgroundColor3 = state == "invalid" and Color3.fromRGB(30, 20, 50) or C.Pink
				UIUtil.Tween(zone, 0.18, { BackgroundTransparency = bg })
				UIUtil.Tween(stroke, 0.18, { Transparency = state == "valid" and 0.2 or 1 })
			end
			if placement == nil then
				set(wallZone, wallZoneStroke, "none")
				set(floorZone, floorZoneStroke, "none")
			elseif placement == "Wall" then
				set(wallZone, wallZoneStroke, "valid")
				set(floorZone, floorZoneStroke, "invalid")
			else
				set(wallZone, wallZoneStroke, "invalid")
				set(floorZone, floorZoneStroke, "valid")
			end
		end,
		Update = function(dt: number)
			clock += dt
			scenery:Update(dt)
			-- Petites animations des dessins (animaux, flammes, balanciers...)
			-- et guirlandes qui scintillent (les ampoules et leur halo)
			for sticker in pairs(stickers) do
				if #sticker.Anims > 0 then
					HouseArt.Step(sticker.Anims, clock)
				end
				local bulbs = sticker.Bulbs
				for index = 1, #bulbs, 2 do
					local bulb = bulbs[index]
					local halo = bulbs[index + 1]
					local phase = tonumber(bulb:GetAttribute("Phase")) or 0
					local wave = 0.5 + 0.5 * math.sin(clock * 3 + phase)
					bulb.BackgroundTransparency = 0.05 + wave * 0.3
					if halo then
						halo.BackgroundTransparency = (dark and 0.35 or 0.7) + wave * 0.25
					end
				end
			end
		end,
		Refit = function()
			refit(true)
		end,
	}

	stage:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		refit()
	end)
	probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		refit()
	end)
	rebuild(nil, nil)
	return room
end

return HouseRoom
