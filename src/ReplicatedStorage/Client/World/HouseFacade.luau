--[[
	HouseFacade (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseFacade

	🚶 Dopamine Town (v9.4) : l'EXTÉRIEUR 3D d'une maison, dessiné comme la
	maison 2D (Components/House/HouseExterior) : même style par taille,
	mêmes couleurs (façade / toit choisis), même motif de toit, même entrée
	(à droite ou au milieu), mêmes éléments, en vrai volume et en matières
	réalistes (enduit, briques, tuiles, ardoises, bois, pierre, verre).
	  - Cottage (studio) : chaumière crème à colombages, grand toit de tuiles
	    roses festonné, cheminée qui fume, chat sur le toit, lucarne ronde
	    fleurie, porche rose à pignon avec porte ronde, soubassement de
	    pierres, pas japonais, barrière blanche, pommier (boîte aux lettres :
	    celle de la parcelle, TownMap).
	  - Townhouse (appartement) : maison de ville menthe, chaînes d'angle,
	    pilastres, corniche à modillons, toit mansardé d'ardoises lilas avec
	    lucarnes roses et crête dorée, 2 cheminées, balcons en fer forgé,
	    entrée cintrée avec marquise rayée et 3 marches, lampadaire, vélo.
	  - Loft : entrepôt de briques, cadres d'usine en acier et impostes,
	    poutres, toit-terrasse (parapet, château d'eau, guirlande, parasol,
	    plantes), porte d'acier + verrière d'atelier, enseigne néon "LOFT",
	    escalier de secours, caisses fleuries, banc.
	  - Mansion : manoir rose, colonnes, balustrades, corniche, toit mansardé
	    (crête dorée, lucarnes, œils-de-bœuf, 2 cheminées), fronton central à
	    horloge-cœur, 2 tours rondes à toits coniques et drapeaux, grand
	    escalier double, haies, topiaires, parterres, fontaine, grille dorée.
	Fenêtres : une par pièce (vraie vitre : on voit la pièce derrière ; une
	"lueur" de la couleur de la pièce tant qu'elle n'est pas construite).
	Perron à marches : rampe de collision invisible (on ne bute jamais).

	API :
	  HouseFacade.Build(kit, size, snapshot, looks) -> Built
	    looks = { Wall, Roof, Pattern, Garden, Rooms (par emplacement), Name }
	    Built = { Door, Hinge, Lock, Fills[slot], Chimneys, Style, Colors }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Config = require(ReplicatedStorage.Shared.Config)
local GarageLayout = require(ReplicatedStorage.Shared.GarageLayout) -- (v9.6, GARAGE96) 🏎️ aile du garage
local HouseGarden = require(script.Parent.HouseGarden)
local HouseKit = require(script.Parent.HouseKit)

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
	Leaf = Color3.fromRGB(128, 206, 128),
	LeafDark = Color3.fromRGB(84, 160, 100),
	Trunk = Color3.fromRGB(176, 124, 96),
	Stone = Color3.fromRGB(240, 232, 244),
	StoneDark = Color3.fromRGB(208, 194, 222),
	Pave = Color3.fromRGB(232, 222, 240),
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
local CHIMNEYS: { [string]: number } = { Cottage = 1, Townhouse = 2, Loft = 0, Mansion = 2 }
HouseFacade.Chimneys = CHIMNEYS

export type Looks = { Wall: Color3?, Roof: Color3?, Pattern: string?, Garden: { string }, Rooms: { [number]: any }, Name: string, Garage: boolean? }
export type Built = {
	Door: BasePart?,
	Hinge: CFrame?,
	Lock: TextLabel?,
	Fills: { [number]: BasePart },
	Chimneys: number,
	Style: string,
}

type Ctx = {
	Kit: any,
	G: any, -- kit du jardin (posé sur la pelouse de la parcelle)
	Size: any,
	Dims: any,
	Style: string,
	Looks: Looks,
	Wall: Color3,
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
}

----------------------------------------------------------------------
-- Petits éléments
----------------------------------------------------------------------

local function wallpaperColor(room: any): Color3
	local style = room and Config.HouseWallpapersById[room.Wallpaper]
	local color = style and style.A
	return typeof(color) == "Color3" and color or Color3.fromRGB(240, 236, 244)
end

-- Fenêtre d'une pièce (trou déjà percé dans le mur) : vitre, cadre, appui,
-- "lueur" de la pièce ; `kind` = "Cross" | "Grid" | "Tall"
local function roomWindow(ctx: Ctx, slot: number?, x0: number, x1: number, y0: number, y1: number, frame: Color3, kind: string)
	local kit = ctx.Kit
	local glass = kit:Box("Glass", x0, x1, y0, y1, 0.35, 0.5, P.Glass, M.Glass, { T = 0.62, Shadow = false })
	glass.CastShadow = false
	local f = if kind == "Grid" then 0.3 else 0.35
	kit:Box("WinFrame", x0 - f, x1 + f, y1, y1 + f, -0.45, 0.35, frame, M.Wood)
	kit:Box("WinFrame", x0 - f, x1 + f, y0 - f, y0, -0.45, 0.35, frame, M.Wood)
	kit:Box("WinFrame", x0 - f, x0, y0, y1, -0.45, 0.35, frame, M.Wood)
	kit:Box("WinFrame", x1, x1 + f, y0, y1, -0.45, 0.35, frame, M.Wood)
	local cx = (x0 + x1) / 2
	if kind == "Grid" then
		-- cadre d'usine : 3 x 2 carreaux
		for k = 1, 2 do
			local x = x0 + k * (x1 - x0) / 3
			kit:Box("Mullion", x - 0.12, x + 0.12, y0, y1, 0.2, 0.4, frame, M.Metal, { Shadow = false })
		end
		local ym = (y0 + y1) / 2
		kit:Box("Mullion", x0, x1, ym - 0.12, ym + 0.12, 0.2, 0.4, frame, M.Metal, { Shadow = false })
	else
		kit:Box("Mullion", cx - 0.12, cx + 0.12, y0, y1, 0.2, 0.4, frame, M.Wood, { Shadow = false })
		local ym = y0 + (y1 - y0) * (if kind == "Tall" then 0.7 else 0.55)
		kit:Box("Mullion", x0, x1, ym - 0.1, ym + 0.1, 0.2, 0.4, frame, M.Wood, { Shadow = false })
	end
	kit:Box("Sill", x0 - 0.6, x1 + 0.6, y0 - 0.55, y0 - 0.2, -0.85, 0.2, frame:Lerp(WHITE, 0.2), M.SmoothPlastic, { Shadow = false })
	-- lueur de la pièce (masquée quand la pièce est construite)
	if slot then
		local room = ctx.Looks.Rooms[slot]
		local fill = kit:Box("Fill", x0 - 0.4, x1 + 0.4, y0 - 0.4, y1 + 0.4, 1.4, 1.6, if room then wallpaperColor(room) else Color3.fromRGB(236, 232, 242), M.SmoothPlastic,
			{ Shadow = false })
		ctx.Built.Fills[slot] = fill
	end
end

-- Jardinière fleurie sous une fenêtre
local function flowerBox(ctx: Ctx, x0: number, x1: number, y: number, color: Color3)
	local kit = ctx.Kit
	kit:Box("FlowerBox", x0, x1, y - 1, y - 0.2, -1.5, -0.35, color, M.Wood, { Shadow = false })
	local count = math.clamp(math.floor((x1 - x0) / 1.4), 3, 7)
	local colors = { C.Pink, C.Butter, WHITE, C.Lilac, C.Peach }
	for k = 1, count do
		local fx = x0 + (k - 0.5) * (x1 - x0) / count
		kit:Ball("Bloom", fx, y - 0.05 + (k % 2) * 0.2, -0.95, 0.85, colors[k % #colors + 1], M.SmoothPlastic, { Shadow = false })
	end
end

-- Fenêtre cintrée : imposte en demi-cercle dessinée (SurfaceGui) au-dessus
-- d'une vitre rectangulaire (le mur n'est percé que du rectangle)
local function archTop(ctx: Ctx, x0: number, x1: number, y1: number, frame: Color3)
	local kit = ctx.Kit
	local w = x1 - x0 + 0.7
	-- arc surbaissé (demi-ellipse) : ne monte jamais sur l'étage du dessus
	local h = math.min(w / 2, 2.3)
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

-- Lanterne murale (x, y = bas de la lanterne), vraie lumière si le budget le permet
local function wallLantern(ctx: Ctx, x: number, y: number, withLight: boolean)
	local kit = ctx.Kit
	kit:Box("LanternArm", x - 0.1, x + 0.1, y + 1.3, y + 1.5, -1, -0.3, C.Ink, M.Metal, { Shadow = false })
	kit:Box("LanternCap", x - 0.45, x + 0.45, y + 1.3, y + 1.6, -1.45, -0.55, C.Ink, M.Metal, { Shadow = false })
	local glass = kit:Box("Lantern", x - 0.35, x + 0.35, y, y + 1.3, -1.35, -0.65, P.Lamp, M.Neon, { Shadow = false })
	if withLight then
		kit:Light(glass, Color3.fromRGB(255, 214, 150), 16, 0.9)
	end
end

-- Lanterne sur poteau (pied en y0)
local function postLantern(ctx: Ctx, x: number, d: number, y0: number, height: number, withLight: boolean, onKit: any?)
	local kit = onKit or ctx.Kit
	kit:CylY("LampPost", x, y0, d, 0.35, height, C.Ink, M.Metal, { Solid = true, Shadow = false })
	kit:Box("LampCap", x - 0.55, x + 0.55, y0 + height + 1.3, y0 + height + 1.6, d - 0.55, d + 0.55, C.Ink, M.Metal, { Shadow = false })
	local glass = kit:Box("LampGlass", x - 0.42, x + 0.42, y0 + height, y0 + height + 1.3, d - 0.42, d + 0.42, P.Lamp, M.Neon, { Shadow = false })
	kit:Ball("LampTop", x, y0 + height + 1.85, d, 0.4, P.Gold, M.Metal, { Shadow = false })
	if withLight then
		kit:Light(glass, Color3.fromRGB(255, 214, 150), 18, 1)
	end
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

-- Arbre (tronc + feuillage en grappe + fruits)
local function tree(ctx: Ctx, x: number, d: number, s: number, fruit: Color3?)
	local kit = ctx.G
	kit:CylY("Trunk", x, 0, d, 1.1 * s, 6 * s, P.Trunk, M.Wood, { Solid = true })
	kit:Ball("Leaves", x, 8 * s, d, 6.5 * s, P.Leaf, M.Grass, { Shadow = true })
	kit:Ball("Leaves", x - 2.4 * s, 7 * s, d + 0.6, 4.6 * s, P.Leaf:Lerp(P.LeafDark, 0.2), M.Grass, { Shadow = true })
	kit:Ball("Leaves", x + 2.3 * s, 7.3 * s, d - 0.5, 4.8 * s, P.Leaf:Lerp(WHITE, 0.08), M.Grass, { Shadow = true })
	if fruit then
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			kit:Ball("Fruit", x + math.cos(a) * 2.6 * s, 7.4 * s + math.sin(a * 2) * 1.2 * s, d - 2.2 * s - math.sin(a) * 0.8, 0.7 * s, fruit, M.SmoothPlastic,
				{ Shadow = false })
		end
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

-- Cheminée (briques) du toit, sortant à `yTop` ; fumée légère
local function chimney(ctx: Ctx, x: number, d: number, yBase: number, yTop: number, color: Color3, smoke: boolean)
	local kit = ctx.Kit
	kit:Box("Chimney", x - 1.3, x + 1.3, yBase, yTop, d - 1.3, d + 1.3, color, M.Brick, { Solid = true })
	kit:Box("ChimneyBand", x - 1.4, x + 1.4, yTop - 1.2, yTop - 0.9, d - 1.4, d + 1.4, color:Lerp(WHITE, 0.45), M.SmoothPlastic, { Shadow = false })
	kit:Box("ChimneyCap", x - 1.6, x + 1.6, yTop, yTop + 0.5, d - 1.6, d + 1.6, color:Lerp(C.Ink, 0.22), M.Concrete, { Shadow = false })
	kit:Box("ChimneyPot", x - 0.45, x + 0.45, yTop + 0.5, yTop + 1.4, d - 0.45, d + 0.45, Color3.fromRGB(226, 170, 150), M.Concrete, { Shadow = false })
	if smoke then
		local vent = kit:Box("Smoke", x - 0.3, x + 0.3, yTop + 1.4, yTop + 1.6, d - 0.3, d + 0.3, WHITE, M.SmoothPlastic, { T = 1, Shadow = false })
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "ChimneySmoke"
		emitter.Color = ColorSequence.new(Color3.fromRGB(250, 246, 252), Color3.fromRGB(226, 220, 236))
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.2) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(2.6, 3.6)
		emitter.Speed = NumberRange.new(2, 3)
		emitter.SpreadAngle = Vector2.new(12, 12)
		emitter.Acceleration = Vector3.new(0.6, 0.4, 0)
		emitter.Rate = 1.4
		emitter.LightInfluence = 0.6
		emitter.Parent = vent
	end
	ctx.Built.Chimneys += 1
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

-- Toit à croupes (comme la 2D de la chaumière : un trapèze vu de face, faîtage
-- court) : pans avant / arrière en trapèze, croupes triangulaires aux bouts
local function hipRoof(ctx: Ctx, x0: number, x1: number, yBase: number, rise: number, overhang: number, hip: number, material: Enum.Material): BasePart
	local kit = ctx.Kit
	local depth = ctx.Depth
	local d0, d1 = -overhang, depth + overhang
	local dm = depth / 2
	local drop = overhang * rise / (dm + overhang)
	local yb, yr = yBase - drop * 0.35, yBase + rise
	local a0, a1 = x0 - overhang, x1 + overhang
	local r0, r1 = a0 + hip, a1 - hip
	local th = 0.7
	local o = { Solid = true }
	-- avant, arrière (2 triangles chacun), croupes gauche / droite
	kit:Triangle("Roof", { a0, yb, d0 }, { a1, yb, d0 }, { r1, yr, dm }, th, ctx.Roof, material, o)
	kit:Triangle("Roof", { a0, yb, d0 }, { r1, yr, dm }, { r0, yr, dm }, th, ctx.Roof, material, o)
	kit:Triangle("Roof", { a0, yb, d1 }, { a1, yb, d1 }, { r1, yr, dm }, th, ctx.Roof, material, o)
	kit:Triangle("Roof", { a0, yb, d1 }, { r1, yr, dm }, { r0, yr, dm }, th, ctx.Roof, material, o)
	kit:Triangle("RoofHip", { a0, yb, d0 }, { a0, yb, d1 }, { r0, yr, dm }, th, ctx.Roof, material, o)
	kit:Triangle("RoofHip", { a1, yb, d0 }, { a1, yb, d1 }, { r1, yr, dm }, th, ctx.Roof, material, o)
	-- arêtiers (rives de la 2D) + faîtage + gouttière
	for _, e in ipairs({ { a0, d0, r0 }, { a1, d0, r1 } }) do
		local pa = Vector3.new(e[1], yb + 0.25, -e[2])
		local pb = Vector3.new(e[3], yr + 0.3, -dm)
		local len = (pb - pa).Magnitude
		kit:Part("Hip", Vector3.new(0.7, 0.6, len), CFrame.lookAt((pa + pb) / 2, pb), ctx.RoofDark, M.Wood, { Shadow = false })
	end
	kit:CylX("Ridge", (r0 + r1) / 2, yr + 0.1, dm, 1.1, r1 - r0 + 0.8, ctx.RoofDark, M.ClayRoofTiles, { Shadow = false })
	kit:CylX("Gutter", (a0 + a1) / 2, yb - 0.3, d0 + 0.1, 0.5, a1 - a0, Color3.fromRGB(236, 236, 244), M.Metal, { Shadow = false })
	-- (motif du toit : plaque invisible sur la partie centrale du pan avant)
	local band = kit:Slab("RoofPatternBand", (r0 + r1) / 2, { yb + 0.02, d0 }, { yr + 0.02, dm }, r1 - r0, 0.1, ctx.Roof, material, { T = 1, Shadow = false })
	return band
end

-- Toit mansardé : pentes raides devant / derrière / côtés + toit plat
local function mansardRoof(ctx: Ctx, x0: number, x1: number, yBase: number, rise: number, inset: number, material: Enum.Material): BasePart
	local kit = ctx.Kit
	local depth = ctx.Depth
	local cx = (x0 + x1) / 2
	local width = x1 - x0 + 1.2
	local front = kit:Slab("Roof", cx, { yBase, -0.6 }, { yBase + rise, inset }, width, 0.7, ctx.Roof, material, { Solid = true, Shadow = true })
	kit:Slab("Roof", cx, { yBase + rise, depth - inset }, { yBase, depth + 0.6 }, width, 0.7, ctx.Roof, material, { Solid = true, Shadow = true })
	kit:SlabX("RoofSide", depth / 2, { x0 - 0.6, yBase }, { x0 + inset, yBase + rise }, depth, 0.7, ctx.Roof, material, { Solid = true })
	kit:SlabX("RoofSide", depth / 2, { x1 - inset, yBase + rise }, { x1 + 0.6, yBase }, depth, 0.7, ctx.Roof, material, { Solid = true })
	kit:Box("RoofTop", x0 + inset - 0.2, x1 - inset + 0.2, yBase + rise - 0.6, yBase + rise, inset - 0.2, depth - inset + 0.2, ctx.RoofDark, M.Slate, { Solid = true })
	kit:Box("RoofEdge", x0 + inset - 0.5, x1 - inset + 0.5, yBase + rise - 0.2, yBase + rise + 0.3, inset - 0.5, inset + 0.1, ctx.RoofDark:Lerp(C.Ink, 0.2), M.Metal,
		{ Shadow = false })
	kit:CylX("Gutter", cx, yBase - 0.3, -0.7, 0.5, width, Color3.fromRGB(236, 236, 244), M.Metal, { Shadow = false })
	return front
end

-- Lucarne sur un pan avant (pied à `yBase`, face avant en `d`)
local function dormer(ctx: Ctx, x: number, yBase: number, d: number, w: number, h: number, round: boolean)
	local kit = ctx.Kit
	kit:Box("Dormer", x - w / 2, x + w / 2, yBase, yBase + h, d, d + 3.5, ctx.Trim, M.Plaster, { Solid = true })
	local cy = yBase + h * 0.5
	if round then
		kit:CylD("DormerRing", x, cy, d - 0.12, w * 0.7, 0.3, C.Cream, M.Wood, { Shadow = false })
		kit:CylD("DormerGlass", x, cy, d - 0.3, w * 0.52, 0.12, P.Glass, M.Glass, { Shadow = false })
	else
		kit:Box("DormerGlass", x - w * 0.28, x + w * 0.28, yBase + 0.8, yBase + h - 1, d - 0.14, d + 0.05, P.Glass, M.Glass, { Shadow = false })
		kit:Box("DormerBar", x - 0.08, x + 0.08, yBase + 0.8, yBase + h - 1, d - 0.2, d - 0.1, ctx.Trim, M.Wood, { Shadow = false })
	end
	-- petit pignon rose
	local rise = w * 0.42
	for _, s in ipairs({ -1, 1 }) do
		kit:Part("DormerRoof", Vector3.new(4, rise, w / 2 + 0.4), CFrame.new(x + s * (w / 4 + 0.1), yBase + h + rise / 2, -(d + 1.6)) * CFrame.Angles(0, -s * math.pi / 2, 0),
			C.Pink, M.ClayRoofTiles, { Solid = true }, "WedgePart")
	end
	kit:Ball("DormerTop", x, yBase + h + rise + 0.25, d + 0.1, 0.55, P.Gold, M.Metal, { Shadow = false })
end

-- Perron : palier devant la porte + `steps` marches vers la rue, rampe invisible
local function porch(ctx: Ctx, x0: number, x1: number, landingD: number, steps: number, color: Color3, material: Enum.Material)
	local kit = ctx.Kit
	local yTop = WorldLayout.FloorY(1)
	local tread = 1.25
	kit:Box("Porch", x0, x1, 0, yTop, -landingD, 0, color, material, { Solid = true })
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

-- Allée : suite de dalles d'un point (x, d) à l'autre
local function path(ctx: Ctx, points: { { number } }, width: number, color: Color3, material: Enum.Material)
	local kit = ctx.G
	for k = 1, #points - 1 do
		local a, b = points[k], points[k + 1]
		local x0, x1 = math.min(a[1], b[1]) - width / 2, math.max(a[1], b[1]) + width / 2
		local d0, d1 = math.min(a[2], b[2]) - width / 2, math.max(a[2], b[2]) + width / 2
		kit:Box("Path", x0, x1, -0.1, 0.1, d0, d1, color, material, { Shadow = false })
	end
end

-- Barrière blanche à piquets (le long de x, à `d`) avec un portillon ouvert
local function picketFence(ctx: Ctx, x0: number, x1: number, d: number, gate0: number, gate1: number)
	local kit = ctx.G
	for _, span in ipairs({ { x0, gate0 }, { gate1, x1 } }) do
		local a, b = span[1], span[2]
		if b - a > 1 then
			kit:Box("FenceRail", a, b, 1.1, 1.35, d - 0.1, d + 0.1, WHITE, M.Wood, { Solid = true, Shadow = false })
			kit:Box("FenceRail", a, b, 2.2, 2.45, d - 0.1, d + 0.1, WHITE, M.Wood, { Shadow = false })
			local count = math.max(2, math.floor((b - a) / 1.6))
			for k = 0, count do
				local x = a + k * (b - a) / count
				kit:Box("Picket", x - 0.2, x + 0.2, 0, 2.9, d - 0.06, d + 0.06, WHITE, M.Wood, { Shadow = false })
			end
		end
	end
	-- portillon entrouvert
	kit:Part("Gate", Vector3.new(gate1 - gate0 - 0.6, 2.4, 0.15), CFrame.new(gate0 + 0.3, 1.4, -d) * CFrame.Angles(0, math.rad(55), 0) * CFrame.new((gate1 - gate0 - 0.6) / 2, 0, 0),
		WHITE, M.Wood, { Shadow = false })
end

-- Grille en fer forgé + piliers à lanternes
local function ironFence(ctx: Ctx, x0: number, x1: number, d: number, gate0: number, gate1: number)
	local kit = ctx.G
	local iron = C.Ink:Lerp(C.Lilac, 0.25)
	for _, span in ipairs({ { x0, gate0 }, { gate1, x1 } }) do
		local a, b = span[1], span[2]
		if b - a > 1 then
			kit:Box("FenceRail", a, b, 0.6, 0.8, d - 0.1, d + 0.1, iron, M.Metal, { Solid = true, Shadow = false })
			kit:Box("FenceRail", a, b, 3.0, 3.2, d - 0.1, d + 0.1, iron, M.Metal, { Shadow = false })
			local count = math.max(2, math.floor((b - a) / 2.6))
			for k = 0, count do
				local x = a + k * (b - a) / count
				kit:Box("FenceBar", x - 0.1, x + 0.1, 0, 3.8, d - 0.1, d + 0.1, iron, M.Metal, { Shadow = false })
				if k % 3 == 1 then
					kit:Ball("FenceBall", x, 3.95, d, 0.35, P.Gold, M.Metal, { Shadow = false })
				end
			end
		end
	end
	for _, x in ipairs({ gate0 - 0.8, gate1 + 0.8 }) do
		kit:Box("GatePillar", x - 0.8, x + 0.8, 0, 4.6, d - 0.8, d + 0.8, P.Stone, M.Limestone, { Solid = true })
		kit:Box("GatePillarCap", x - 1, x + 1, 4.6, 5, d - 1, d + 1, C.Cream, M.Limestone, { Shadow = false })
		postLantern(ctx, x, d, 5, 0.6, false, kit)
	end
end

-- Plaque au nom du propriétaire
local function namePlate(ctx: Ctx, x: number, y: number, d: number, w: number)
	local kit = ctx.Kit
	local plate = kit:Box("NamePlate", x - w / 2, x + w / 2, y, y + 1.5, d - 0.25, d, WHITE, M.SmoothPlastic, { Shadow = false })
	kit:Box("NamePlateFrame", x - w / 2 - 0.15, x + w / 2 + 0.15, y - 0.15, y + 1.65, d - 0.1, d + 0.1, P.Gold, M.Metal, { Shadow = false })
	kit:Text(plate, Enum.NormalId.Back, "🏠 " .. ctx.Looks.Name, C.PinkDeep, Enum.Font.FredokaOne, 40, 220)
end

----------------------------------------------------------------------
-- Porte d'entrée (battant qui pivote : HouseBuilder.StepDoor)
----------------------------------------------------------------------

local function frontDoor(ctx: Ctx, leafColor: Color3, frameColor: Color3, withGlass: boolean)
	local kit = ctx.Kit
	local x = ctx.DoorX
	local y0 = WorldLayout.FloorY(1)
	local w, h = WorldLayout.DOOR_W, WorldLayout.DOOR_H
	for _, sx in ipairs({ -1, 1 }) do
		kit:Box("DoorFrame", x + sx * (w / 2) - 0.3, x + sx * (w / 2) + 0.3, y0, y0 + h + 0.4, -0.7, 0.25, frameColor, M.Wood, { Solid = true })
	end
	kit:Box("DoorFrame", x - w / 2 - 0.45, x + w / 2 + 0.45, y0 + h, y0 + h + 0.6, -0.75, 0.25, frameColor, M.Wood)
	local leaf = kit:Box("DoorLeaf", x - w / 2 + 0.05, x + w / 2 - 0.05, y0, y0 + h - 0.05, 0.15, 0.55, leafColor, M.Wood, { Solid = true, Shadow = true })
	ctx.Built.Door = leaf
	ctx.Built.Hinge = ctx.Kit.CF * CFrame.new(x - w / 2 + 0.05, y0, -0.35)
	-- décor soudé au battant (il pivote avec lui)
	local function welded(part: BasePart)
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = leaf
		weld.Part1 = part
		weld.Parent = leaf
	end
	welded(kit:Ball("DoorKnob", x + w / 2 - 0.75, y0 + h * 0.48, 0.05, 0.4, P.Gold, M.Metal, { Shadow = false }))
	welded(kit:Box("DoorPanel", x - w / 2 + 0.6, x + w / 2 - 0.6, y0 + 0.7, y0 + h * 0.42, 0.05, 0.16, leafColor:Lerp(WHITE, 0.18), M.Wood, { Shadow = false }))
	if withGlass then
		welded(kit:Box("DoorGlass", x - w / 2 + 0.9, x + w / 2 - 0.9, y0 + h * 0.55, y0 + h - 0.8, 0.05, 0.16, P.Glass, M.Glass, { Shadow = false }))
	else
		welded(kit:Box("DoorPanel", x - w / 2 + 0.6, x + w / 2 - 0.6, y0 + h * 0.5, y0 + h - 0.7, 0.05, 0.16, leafColor:Lerp(WHITE, 0.18), M.Wood, { Shadow = false }))
	end
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

----------------------------------------------------------------------
-- Murs du bâtiment
----------------------------------------------------------------------

-- Façade (une par étage, trous = fenêtres + porte), murs des bouts, mur du
-- fond, soubassement, dalle du toit. `holes[floor]` = { { x0, x1, y0, y1 } }
local function bodyWalls(ctx: Ctx, holes: { [number]: { { number } } }, material: Enum.Material, plinthColor: Color3, plinthMaterial: Enum.Material)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local T = WorldLayout.WALL_T
	local L, R = ctx.Left - T, ctx.Right + T
	for floor = 1, dims.Floors do
		local yFloor = WorldLayout.FloorY(floor)
		local y0 = if floor == 1 then WorldLayout.PLINTH else yFloor - WorldLayout.SLAB
		kit:WallX("Facade", L, R, y0, yFloor + WorldLayout.WALL_H, -0.3, T, holes[floor] or {}, ctx.Wall, material, { Solid = true })
	end
	-- soubassement (devant) + fondations pleines sous les pièces
	local yGround = WorldLayout.FloorY(1)
	kit:WallX("Plinth", L - 0.3, R + 0.3, 0, WorldLayout.PLINTH, -0.6, T, {}, plinthColor, plinthMaterial, { Solid = true })
	kit:Box("Foundation", ctx.Left, ctx.Right, 0, WorldLayout.PLINTH, T, ctx.Depth - T, plinthColor:Lerp(BLACK, 0.1), M.Concrete, { Solid = true, Shadow = false })
	kit:Box("PlinthCap", L - 0.4, R + 0.4, WorldLayout.PLINTH - 0.25, WorldLayout.PLINTH + 0.1, -0.75, 0, ctx.Trim, M.Limestone, { Shadow = false })
	local _ = yGround
	-- bouts (à l'extérieur des colonnes) et fond (derrière les coques)
	kit:Box("EndLeft", L, ctx.Left, 0, ctx.Top, -0.3, ctx.Depth, ctx.Wall, material, { Solid = true })
	kit:Box("EndRight", ctx.Right, R, 0, ctx.Top, -0.3, ctx.Depth, ctx.Wall, material, { Solid = true })
	kit:Box("Back", L, R, 0, ctx.Top, ctx.Depth - T + 0.05, ctx.Depth + 0.3, ctx.Wall, material, { Solid = true })
	-- dalle du toit (ferme la maison par le haut)
	kit:Box("TopSlab", L, R, ctx.Top, ctx.Top + 0.6, -0.3, ctx.Depth + 0.3, ctx.Trim, M.SmoothPlastic, { Solid = true, Shadow = false })
end

-- Fenêtre des pièces par style : { part de la largeur, bas (au-dessus du sol), hauteur }
local WINDOWS: { [string]: { number } } = {
	Cottage = { 0.56, 3.2, 6.6 },
	Townhouse = { 0.42, 2.2, 7.4 },
	Loft = { 0.7, 1.8, 7.2 },
	Mansion = { 0.4, 2.4, 7 },
}

-- Trou de fenêtre d'une pièce (repère local) : { x0, x1, y0, y1 } ; aussi
-- utilisé par HouseBuilder pour le mur avant intérieur de la pièce
function HouseFacade.WindowRect(size: any, column: number, floor: number): { number }
	local spec = WINDOWS[WorldLayout.StyleOf(size)] or WINDOWS.Cottage
	local x0, x1 = WorldLayout.ColumnSpan(size, column)
	local cx = (x0 + x1) / 2
	local w = math.clamp((x1 - x0) * spec[1], 7, 26)
	local yFloor = WorldLayout.FloorY(floor)
	return { cx - w / 2, cx + w / 2, yFloor + spec[2], yFloor + spec[2] + spec[3] }
end

local function windowRect(ctx: Ctx, column: number, floor: number): { number }
	return HouseFacade.WindowRect(ctx.Size, column, floor)
end

----------------------------------------------------------------------
-- Styles
----------------------------------------------------------------------

local STYLES: { [string]: (ctx: Ctx) -> () } = {}

-- ░░ Cottage : chaumière de conte ░░
STYLES.Cottage = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local TIMBER = Color3.fromRGB(206, 150, 112)
	local T = WorldLayout.WALL_T
	local holes: { [number]: { { number } } } = {}
	local hallHoles: { { number } } = {}
	local windows = {}
	for floor = 1, dims.Floors do
		holes[floor] = {}
		for column = 1, dims.Columns do
			local r = windowRect(ctx, column, floor)
			table.insert(holes[floor], r)
			table.insert(windows, { r, (floor - 1) * dims.Columns + column })
		end
		local yFloor = WorldLayout.FloorY(floor)
		local r = if floor == 1 then { ctx.DoorX - WorldLayout.DOOR_W / 2, ctx.DoorX + WorldLayout.DOOR_W / 2, yFloor, yFloor + WorldLayout.DOOR_H }
			else { ctx.DoorX - 2.2, ctx.DoorX + 2.2, yFloor + 3.5, yFloor + 8.5 }
		table.insert(holes[floor], r)
		table.insert(hallHoles, r)
		if floor > 1 then
			table.insert(windows, { r, nil })
		end
	end
	bodyWalls(ctx, holes, M.Plaster, P.Stone, M.Cobblestone)
	-- porche (travée de la cage) : enduit rosé devant la façade
	local annex = ctx.Wall:Lerp(C.Pink, 0.14)
	kit:WallX("AnnexSkin", ctx.Hall0 + 0.3, ctx.Hall1 + T - 0.3, WorldLayout.PLINTH, ctx.Top, -0.36, -0.3, hallHoles, annex, M.Plaster, { Shadow = false })
	for _, w in ipairs(windows) do
		local r = w[1]
		roomWindow(ctx, w[2], r[1], r[2], r[3], r[4], C.Cream, "Cross")
		if w[2] then
			flowerBox(ctx, r[1] + 0.4, r[2] - 0.4, r[3] - 0.5, C.Pink)
		end
	end
	-- colombages : poteaux, poutres (avant)
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
			kit:Box("Timber", x - 0.5, x + 0.5, WorldLayout.PLINTH, ctx.Top, -0.62, -0.3, TIMBER, M.Wood, { Shadow = false })
			last = x
			if x > ctx.Left and x < ctx.Right then
				heart(ctx, x, ctx.Top - 2.2, -0.75, 0.9, C.Pink)
			end
		end
	end
	kit:Box("Beam", ctx.Left - T - 0.3, ctx.Right + T + 0.3, ctx.Top - 1, ctx.Top, -0.66, -0.3, TIMBER, M.Wood, { Shadow = false })
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor) - WorldLayout.SLAB
		kit:Box("Beam", ctx.Left - T - 0.3, ctx.Right + T + 0.3, y - 0.3, y + 0.7, -0.66, -0.3, TIMBER, M.Wood, { Shadow = false })
	end
	kit:Box("Beam", ctx.Left - T - 0.3, ctx.Right + T + 0.3, WorldLayout.PLINTH - 0.1, WorldLayout.PLINTH + 0.5, -0.7, -0.3, TIMBER, M.Wood, { Shadow = false })

	-- toit de tuiles roses : grand pignon + festons + faîtage + cœur
	-- (comme la 2D : le grand toit couvre les pièces ; le porche a son pignon)
	local rise = 10 + (dims.Floors - 1) * 1.5
	local overhang = 1.8
	local roofX0, roofX1 = ctx.Left - T, ctx.Hall0 + 0.4
	local hip = math.clamp((roofX1 - roofX0) * 0.36, 6, 26)
	local front = hipRoof(ctx, roofX0, roofX1, ctx.Top + 0.6, rise, overhang, hip, M.ClayRoofTiles)
	roofPattern(ctx, front, ctx.Looks.Pattern or "None")
	local width = roofX1 - roofX0 + 2 * overhang
	local cx = (roofX0 + roofX1) / 2
	local count = math.floor(width / 1.9)
	for k = 0, count - 1 do
		local x = cx - width / 2 + (k + 0.5) * width / count
		kit:CylD("Scallop", x, ctx.Top + 0.35, -overhang - 0.05, 1.7, 0.35, ctx.RoofDark, M.ClayRoofTiles, { Shadow = false })
	end
	heart(ctx, cx, ctx.Top + 0.6 + rise + 1.4, ctx.Depth / 2, 1.8, C.Heart)
	-- lucarne ronde + jardinière (au milieu des pièces)
	local roomsX = (WorldLayout.ColumnSpan(ctx.Size, 1) + select(2, WorldLayout.ColumnSpan(ctx.Size, dims.Columns))) / 2
	local k = 0.3
	local ridgeD = ctx.Depth / 2
	local dFace = -overhang + k * (ridgeD + overhang) - 0.4
	local yFace = ctx.Top + 0.6 + k * rise
	dormer(ctx, roomsX, yFace - 1.2, dFace, 5, 5, true)
	kit:Box("DormerBox", roomsX - 2.8, roomsX + 2.8, yFace - 1.9, yFace - 1.1, dFace - 1.2, dFace, C.Pink, M.Wood, { Shadow = false })
	for index, color in ipairs({ C.Butter, WHITE, C.Lilac, C.Butter }) do
		kit:Ball("Bloom", roomsX - 2.4 + index * 0.96, yFace - 0.9, dFace - 0.6, 0.8, color, M.SmoothPlastic, { Shadow = false })
	end
	-- cheminée (à droite, derrière le faîtage) + fumée
	local chimneyX = roomsX + (roofX1 - roofX0) * 0.28
	chimney(ctx, chimneyX, ridgeD + 1.4, ctx.Top + 2, ctx.Top + 0.6 + rise + 3.8, Color3.fromRGB(226, 142, 142), true)
	-- chat assis sur le pan gauche
	HouseGarden.Cat(kit, roomsX - (ctx.Right - ctx.Left) * 0.26, ctx.Top + 0.6 + 0.55 * rise + 0.3, -overhang + 0.55 * (ridgeD + overhang) - 0.3)

	-- porche (cage) : son propre pignon rose face à la rue, œil-de-bœuf, cœur
	local gx = ctx.DoorX
	local hx0, hx1 = ctx.Hall0, ctx.Hall1 + T
	local hcx = (hx0 + hx1) / 2
	local hRise = 5.5
	local yEave = ctx.Top + 0.6
	for _, s in ipairs({ -1, 1 }) do
		local edge = if s < 0 then hx0 - 0.9 else hx1 + 0.9
		kit:SlabX("PorchRoof", ctx.Depth / 2 - 0.5, { edge, yEave - 0.9 * hRise / ((hx1 - hx0) / 2) }, { hcx, yEave + hRise }, ctx.Depth + 2.4, 0.6, ctx.Roof, M.ClayRoofTiles,
			{ Solid = true, Shadow = true })
		kit:Part("PorchGable", Vector3.new(1, hRise, (hx1 - hx0) / 2), CFrame.new(hcx + s * (hx1 - hx0) / 4, yEave + hRise / 2, 0.2) * CFrame.Angles(0, -s * math.pi / 2, 0),
			annex, M.Plaster, { Solid = true }, "WedgePart")
		kit:SlabX("PorchBarge", -1.6, { edge - 0.1, yEave - 0.9 * hRise / ((hx1 - hx0) / 2) + 0.3 }, { hcx, yEave + hRise + 0.35 }, 0.5, 0.9, ctx.RoofDark, M.Wood,
			{ Shadow = false })
	end
	kit:CylD("GableWindowRing", hcx, yEave + hRise * 0.42, -0.35, 2.6, 0.3, C.Cream, M.Wood, { Shadow = false })
	kit:CylD("GableWindow", hcx, yEave + hRise * 0.42, -0.52, 1.9, 0.1, P.Glass, M.Glass, { Shadow = false })
	heart(ctx, hcx, yEave + hRise + 1.1, -0.6, 1.2, C.Heart)
	local sc = math.floor((hx1 - hx0) / 1.9)
	for j = 0, sc - 1 do
		kit:CylD("Scallop", hx0 + (j + 0.5) * (hx1 - hx0) / sc, yEave - 0.25, -0.55, 1.6, 0.3, ctx.RoofDark, M.ClayRoofTiles, { Shadow = false })
	end
	-- porte ronde : cadre de bois + haut arrondi (disque)
	frontDoor(ctx, C.Pink, TIMBER, false)
	kit:CylD("DoorArch", gx, WorldLayout.FloorY(1) + WorldLayout.DOOR_H, -0.5, WorldLayout.DOOR_W + 1.2, 0.35, TIMBER, M.Wood, { Shadow = false })
	kit:CylD("DoorArchGlass", gx, WorldLayout.FloorY(1) + WorldLayout.DOOR_H + 0.1, -0.7, WorldLayout.DOOR_W - 0.6, 0.12, P.Glass, M.Glass, { Shadow = false })
	heart(ctx, gx, WorldLayout.FloorY(1) + WorldLayout.DOOR_H + 1, -0.85, 1.1, C.Heart, M.Neon)
	wallLantern(ctx, gx + WorldLayout.DOOR_W / 2 + 1.2, WorldLayout.FloorY(1) + 4.2, true)
	local foot = porch(ctx, gx - 3.5, gx + 3.5, 2.2, 3, P.StoneDark, M.Slate)
	namePlate(ctx, gx, WorldLayout.FloorY(1) + WorldLayout.DOOR_H + 3.6, -0.5, 7)

	-- jardin : pommier, buissons, pas japonais, barrière, fleurs
	tree(ctx, ctx.Left - 9, 6, 1.2, C.Pink)
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		bush(ctx, x0 + 3, -2, 3.4, 2.4, P.Leaf)
		bush(ctx, x1 - 3, -2, 3, 2.2, if column % 2 == 0 then C.Pink:Lerp(P.Leaf, 0.3) else P.Leaf)
		flowerDots(ctx, x0 + 5, x1 - 5, -1.6, 6)
	end
	local gateX = 0
	local stones = { { gateX, -20 }, { gateX * 0.8 + gx * 0.2, -16.5 }, { gateX * 0.5 + gx * 0.5, -13 }, { gateX * 0.2 + gx * 0.8, -10 }, { gx, foot - 1.2 } }
	for index, s in ipairs(stones) do
		ctx.G:CylY("SteppingStone", s[1], -0.1, s[2], 2.6 - index * 0.12, 0.2, P.Stone:Lerp(P.StoneDark, (index % 2) * 0.4), M.Slate, { Shadow = false })
	end
	path(ctx, { { gx, foot - 0.5 }, { gx, foot - 2.5 } }, 3, P.Pave, M.Pebble)
	path(ctx, { { gateX, -29.5 }, { gateX, -21.5 } }, 3, P.Pave, M.Pebble)
	local fence0, fence1 = ctx.Left - 4, ctx.Right + 4
	picketFence(ctx, fence0, fence1, -21, gateX - 2.2, gateX + 2.2)
	flowerDots(ctx, fence0 + 1, gateX - 6, -20.2, 10)
	flowerDots(ctx, gateX + 3, fence1 - 1, -20.2, 10)
end

-- ░░ Townhouse : maison de ville pastel ░░
STYLES.Townhouse = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local T = WorldLayout.WALL_T
	local TRIM = C.Cream
	local holes: { [number]: { { number } } } = {}
	local hallHoles: { { number } } = {}
	local windows = {}
	for floor = 1, dims.Floors do
		holes[floor] = {}
		for column = 1, dims.Columns do
			local r = windowRect(ctx, column, floor)
			table.insert(holes[floor], r)
			table.insert(windows, { r, (floor - 1) * dims.Columns + column })
		end
		local yFloor = WorldLayout.FloorY(floor)
		local r = if floor == 1 then { ctx.DoorX - WorldLayout.DOOR_W / 2, ctx.DoorX + WorldLayout.DOOR_W / 2, yFloor, yFloor + WorldLayout.DOOR_H }
			else { ctx.DoorX - 1.9, ctx.DoorX + 1.9, yFloor + 2.4, yFloor + 8.4 }
		table.insert(holes[floor], r)
		table.insert(hallHoles, r)
		if floor > 1 then
			table.insert(windows, { r, nil })
		end
	end
	bodyWalls(ctx, holes, M.Plaster, P.Stone, M.Limestone)
	-- entrée (cage) teintée ciel, comme la 2D
	kit:WallX("AnnexSkin", ctx.Hall0 + 0.4, ctx.Hall1 + T - 0.4, WorldLayout.PLINTH, ctx.Top, -0.36, -0.3, hallHoles, ctx.Wall:Lerp(C.Sky, 0.25), M.Plaster, { Shadow = false })
	for _, w in ipairs(windows) do
		local r = w[1]
		roomWindow(ctx, w[2], r[1], r[2], r[3], r[4], TRIM, "Tall")
		archTop(ctx, r[1], r[2], r[4], TRIM)
		if not w[2] then
			flowerBox(ctx, r[1] - 0.4, r[2] + 0.4, r[3] - 0.4, C.Pink)
		end
	end
	-- chaînes d'angle crème + pilastres entre les pièces
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
	-- corniche + modillons + liseré rose
	kit:Box("Cornice", ctx.Left - T - 0.9, ctx.Right + T + 0.9, ctx.Top - 0.2, ctx.Top + 1.1, -1.3, 0, TRIM, M.Plaster)
	kit:Box("CorniceLine", ctx.Left - T - 0.6, ctx.Right + T + 0.6, ctx.Top + 0.45, ctx.Top + 0.65, -1.35, -1.25, C.Pink, M.SmoothPlastic, { Shadow = false })
	local modCount = math.floor((ctx.Right - ctx.Left) / 2.6)
	for k = 0, modCount do
		local x = ctx.Left + k * (ctx.Right - ctx.Left) / modCount
		kit:Box("Modillion", x - 0.3, x + 0.3, ctx.Top - 0.8, ctx.Top - 0.2, -0.9, -0.3, TRIM, M.Plaster, { Shadow = false })
	end
	-- bandeaux + balcons en fer forgé aux étages
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor)
		kit:Box("Band", ctx.Left - T - 0.4, ctx.Right + T + 0.4, y - 1.3, y - 0.2, -0.7, -0.3, TRIM, M.Plaster, { Shadow = false })
		kit:Box("BandLine", ctx.Left - T - 0.4, ctx.Right + T + 0.4, y - 0.85, y - 0.65, -0.75, -0.7, C.Pink, M.SmoothPlastic, { Shadow = false })
		for column = 1, dims.Columns do
			local r = windowRect(ctx, column, floor)
			local b0, b1 = r[1] - 1.2, r[2] + 1.2
			kit:Box("Balcony", b0, b1, y - 0.4, y, -2.4, -0.3, TRIM, M.Limestone, { Solid = true })
			kit:Box("BalconyRail", b0, b1, y + 3, y + 3.2, -2.35, -2.15, WHITE, M.Metal, { Shadow = false })
			for _, x in ipairs({ b0 + 0.1, b1 - 0.1 }) do
				kit:Box("BalconyRail", x - 0.1, x + 0.1, y + 3, y + 3.2, -2.35, -0.3, WHITE, M.Metal, { Shadow = false })
			end
			local bars = math.floor((b1 - b0) / 0.8)
			for k = 0, bars do
				local x = b0 + 0.1 + k * (b1 - b0 - 0.2) / bars
				kit:Box("BalconyBar", x - 0.06, x + 0.06, y, y + 3, -2.3, -2.2, WHITE, M.Metal, { Shadow = false })
			end
			for _, hx in ipairs({ b0 + (b1 - b0) * 0.25, b0 + (b1 - b0) * 0.75 }) do
				heart(ctx, hx, y + 1.6, -2.45, 1, C.Pink)
			end
		end
	end
	-- toit mansardé d'ardoises (sur les pièces, comme la 2D) + lucarnes roses +
	-- crête dorée + cheminées ; l'entrée (cage) a un toit plat à garde-corps
	local rise = 8.5 + (dims.Floors - 1) * 0.5
	local inset = 4.6
	local yBase = ctx.Top + 1.1
	local r0, r1 = ctx.Left - T, ctx.Hall0 + 0.4
	local front = mansardRoof(ctx, r0, r1, yBase, rise, inset, M.Slate)
	roofPattern(ctx, front, ctx.Looks.Pattern or "None")
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		dormer(ctx, (x0 + x1) / 2, yBase + 1.4, -0.6 + inset * 1.4 / rise - 0.3, 4.6, 5.2, false)
	end
	local crest = math.max(2, math.floor((r1 - r0 - 2 * inset) / 5))
	for k = 0, crest do
		local x = r0 + inset + k * (r1 - r0 - 2 * inset) / crest
		kit:Box("CrestPost", x - 0.1, x + 0.1, yBase + rise, yBase + rise + 1.4, inset - 0.1, inset + 0.1, C.Ink:Lerp(C.Lilac, 0.3), M.Metal, { Shadow = false })
		kit:Ball("CrestBall", x, yBase + rise + 1.5, inset, 0.5, P.Gold, M.Metal, { Shadow = false })
	end
	heart(ctx, (r0 + r1) / 2, yBase + rise + 2.2, inset, 1.6, C.Heart)
	local span = r1 - r0
	for _, s in ipairs({ -1, 1 }) do
		local cx = (r0 + r1) / 2 + s * span * 0.36
		chimney(ctx, cx, ctx.Depth * 0.55, yBase + rise - 1, yBase + rise + 3.4, Color3.fromRGB(236, 160, 170), s > 0)
	end
	-- toit plat de l'entrée : garde-corps blanc + plante
	local hx0, hx1 = ctx.Hall0 + 0.6, ctx.Hall1 + T
	local yr = ctx.Top + 1.1
	kit:Box("AnnexRail", hx0, hx1, yr + 2.2, yr + 2.45, -1.1, -0.9, WHITE, M.Metal, { Shadow = false })
	kit:Box("AnnexRail", hx1 - 0.2, hx1, yr + 2.2, yr + 2.45, -1.1, ctx.Depth, WHITE, M.Metal, { Shadow = false })
	for k = 0, 6 do
		local x = hx0 + k * (hx1 - hx0) / 6
		kit:Box("AnnexBar", x - 0.07, x + 0.07, yr, yr + 2.2, -1.05, -0.95, WHITE, M.Metal, { Shadow = false })
	end
	HouseGarden.PottedBall(kit:Sub(CFrame.new(0, yr, 0)), hx1 - 2, 1.5, 0.8, C.Peach)
	-- entrée : porte cintrée, marquise rayée, 3 marches, lanterne, topiaires
	local gx = ctx.DoorX
	local yDoor = WorldLayout.FloorY(1)
	frontDoor(ctx, C.PinkDeep:Lerp(C.Pink, 0.5), TRIM, true)
	archTop(ctx, gx - WorldLayout.DOOR_W / 2, gx + WorldLayout.DOOR_W / 2, yDoor + WorldLayout.DOOR_H + 0.6, TRIM)
	heart(ctx, gx, yDoor + WorldLayout.DOOR_H + 1.6, -0.55, 0.9, C.Heart)
	local awW = WorldLayout.DOOR_W + 3.4
	local awY = yDoor + WorldLayout.DOOR_H + 3.6
	local awning = kit:Slab("Awning", gx, { awY - 1.8, -3 }, { awY, -0.3 }, awW, 0.3, WHITE, M.Fabric, { Shadow = true })
	local _ = awning
	for k = 0, 4 do
		local x = gx - awW / 2 + (k + 0.5) * awW / 5
		if k % 2 == 0 then
			kit:Slab("AwningStripe", x, { awY - 1.74, -3.02 }, { awY + 0.06, -0.3 }, awW / 5, 0.3, C.Pink, M.Fabric, { Shadow = false })
		end
		kit:CylD("AwningScallop", x, awY - 2.05, -3, awW / 5, 0.25, if k % 2 == 0 then C.Pink else WHITE, M.Fabric, { Shadow = false })
	end
	wallLantern(ctx, gx + WorldLayout.DOOR_W / 2 + 1.4, yDoor + 3.6, true)
	local foot = porch(ctx, gx - 3.8, gx + 3.8, 2, 3, P.Stone, M.Limestone)
	for _, s in ipairs({ -1, 1 }) do
		HouseGarden.PottedBall(ctx.G, gx + s * 5.2, -1.6, 1, C.Lilac)
	end
	namePlate(ctx, gx, yDoor + WorldLayout.DOOR_H + 4.8, -0.35, 6)
	-- trottoir, lampadaire, vélo, allée
	ctx.G:Box("Sidewalk", ctx.Left - 6, ctx.Right + 6, -0.1, 0.12, -6, -0.6, P.Pave, M.Pavement, { Shadow = false })
	postLantern(ctx, ctx.Left + 3, -5, 0, 8, false, ctx.G)
	HouseGarden.Bike(ctx.G, ctx.Left + 7, -4.2, C.Mint:Lerp(C.Sky, 0.3))
	path(ctx, { { 0, -29.5 }, { 0, -8 }, { gx, -8 }, { gx, foot } }, 3.2, P.Pave, M.Pavement)
	for column = 1, dims.Columns do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		bush(ctx, (x0 + x1) / 2, -7.3, 5, 2, P.Leaf)
	end
	picketFence(ctx, ctx.Left - 4, ctx.Right + 4, -21, -2.2, 2.2)
end

-- ░░ Loft : entrepôt de briques reconverti ░░
STYLES.Loft = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local T = WorldLayout.WALL_T
	local steel = P.SteelDark
	local holes: { [number]: { { number } } } = {}
	local windows = {}
	for floor = 1, dims.Floors do
		holes[floor] = {}
		for column = 1, dims.Columns do
			local r = windowRect(ctx, column, floor)
			table.insert(holes[floor], r)
			table.insert(windows, { r, (floor - 1) * dims.Columns + column })
		end
		local yFloor = WorldLayout.FloorY(floor)
		if floor == 1 then
			table.insert(holes[floor], { ctx.DoorX - WorldLayout.DOOR_W / 2, ctx.DoorX + WorldLayout.DOOR_W / 2, yFloor, yFloor + WorldLayout.DOOR_H })
		else
			-- verrière d'atelier (travée de droite)
			local r = { ctx.DoorX - 3, ctx.DoorX + 3, yFloor + 1.5, yFloor + 10.5 }
			table.insert(holes[floor], r)
			table.insert(windows, { r, nil })
		end
	end
	bodyWalls(ctx, holes, M.Brick, Color3.fromRGB(226, 216, 232), M.Concrete)
	for _, w in ipairs(windows) do
		local r = w[1]
		roomWindow(ctx, w[2], r[1], r[2], r[3], r[4], steel, "Grid")
		if w[2] then
			-- imposte : rangée de petits carreaux au-dessus
			local ty = r[4] + 0.6
			kit:Box("Transom", r[1] + 0.3, r[2] - 0.3, ty, ty + 1.6, -0.5, -0.3, steel, M.Metal, { Shadow = false })
			local n = 6
			for k = 0, n - 1 do
				local x = r[1] + 0.6 + (k + 0.5) * (r[2] - r[1] - 1.2) / n
				kit:Box("TransomPane", x - (r[2] - r[1] - 1.2) / n / 2 + 0.15, x + (r[2] - r[1] - 1.2) / n / 2 - 0.15, ty + 0.25, ty + 1.35, -0.56, -0.5, P.Glass, M.Glass,
					{ Shadow = false })
			end
		end
	end
	-- poutres d'acier entre les étages
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor) - WorldLayout.SLAB
		kit:Box("SteelBeam", ctx.Left - T - 0.3, ctx.Right + T + 0.3, y - 0.2, y + 1.1, -0.8, -0.3, steel, M.Metal)
	end
	-- parapet (toit-terrasse) + couronnement crème
	kit:WallX("Parapet", ctx.Left - T, ctx.Right + T, ctx.Top + 0.6, ctx.Top + 3.2, -0.3, 0.5, {}, ctx.Wall, M.Brick, { Solid = true })
	kit:Box("ParapetBack", ctx.Left - T, ctx.Right + T, ctx.Top + 0.6, ctx.Top + 3.2, ctx.Depth - 0.5, ctx.Depth + 0.3, ctx.Wall, M.Brick, { Solid = true })
	for _, x in ipairs({ ctx.Left - T, ctx.Right + T - 0.8 }) do
		kit:Box("ParapetSide", x, x + 0.8, ctx.Top + 0.6, ctx.Top + 3.2, 0.5, ctx.Depth - 0.5, ctx.Wall, M.Brick, { Solid = true })
	end
	kit:Box("Coping", ctx.Left - T - 0.4, ctx.Right + T + 0.4, ctx.Top + 3.2, ctx.Top + 3.7, -0.7, 0.9, C.Cream, M.Concrete, { Shadow = false })
	-- terrasse : château d'eau, guirlande, parasol, plantes
	local yRoof = ctx.Top + 0.6
	local wtX = ctx.Left + (ctx.Right - ctx.Left) * 0.2
	local wtD = ctx.Depth * 0.5
	for _, dx in ipairs({ -2.2, 2.2 }) do
		for _, dd in ipairs({ -2.2, 2.2 }) do
			kit:Box("TowerLeg", wtX + dx - 0.2, wtX + dx + 0.2, yRoof, yRoof + 6, wtD + dd - 0.2, wtD + dd + 0.2, steel, M.Metal, { Solid = true, Shadow = false })
		end
	end
	kit:CylY("WaterTank", wtX, yRoof + 6, wtD, 6.4, 6, C.Wood, M.WoodPlanks, { Solid = true })
	for _, band in ipairs({ 1.2, 3, 4.8 }) do
		kit:CylY("TankBand", wtX, yRoof + 6 + band, wtD, 6.55, 0.25, steel, M.Metal, { Shadow = false })
	end
	heart(ctx, wtX, yRoof + 9.2, wtD - 3.3, 1.8, C.Pink)
	kit:Cone("TankRoof", wtX, yRoof + 12, wtD, 3.8, 3, 8, ctx.Roof, M.Slate)
	kit:Ball("TankTop", wtX, yRoof + 15.2, wtD, 0.6, P.Gold, M.Metal, { Shadow = false })
	local p1, p2 = ctx.Left + (ctx.Right - ctx.Left) * 0.42, ctx.Right - (ctx.Right - ctx.Left) * 0.24
	local poleD = ctx.Depth * 0.35
	for _, px in ipairs({ p1, p2 }) do
		kit:Box("LightPole", px - 0.12, px + 0.12, yRoof, yRoof + 6.5, poleD - 0.12, poleD + 0.12, steel, M.Metal, { Shadow = false })
	end
	local bulbColors = { C.Pink, C.Butter, C.Mint, C.Sky, C.Lilac }
	local segments = 12
	for k = 1, segments - 1 do
		local t = k / segments
		local x = p1 + (p2 - p1) * t
		local y = yRoof + 6.3 - math.sin(t * math.pi) * 1.8
		kit:Ball("Bulb", x, y, poleD, 0.45, bulbColors[k % #bulbColors + 1], M.Neon, { Shadow = false })
	end
	kit:SlabX("LightString", poleD, { p1, yRoof + 6.5 }, { (p1 + p2) / 2, yRoof + 4.7 }, 0.06, 0.06, C.Ink, M.SmoothPlastic, { Shadow = false })
	kit:SlabX("LightString", poleD, { (p1 + p2) / 2, yRoof + 4.7 }, { p2, yRoof + 6.5 }, 0.06, 0.06, C.Ink, M.SmoothPlastic, { Shadow = false })
	local umX = ctx.Right - (ctx.Right - ctx.Left) * 0.14
	kit:CylY("ParasolPole", umX, yRoof, poleD + 3, 0.2, 4.6, WHITE, M.Metal, { Shadow = false })
	kit:Cone("Parasol", umX, yRoof + 4.2, poleD + 3, 3.4, 1.4, 8, C.Pink, M.Fabric)
	for index = 0, 4 do
		local bx = ctx.Left + 4 + index * (ctx.Right - ctx.Left - 8) / 4
		kit:Box("Planter", bx - 1.8, bx + 1.8, yRoof, yRoof + 1.2, 1.2, 3, C.Wood, M.WoodPlanks, { Shadow = false })
		kit:Ball("Shrub", bx, yRoof + 1.9, 2.1, 2.2, P.Leaf, M.Grass)
		if index % 2 == 1 then
			kit:CylY("Stalk", bx + 0.8, yRoof + 1.2, 2, 0.15, 2.4, P.LeafDark, M.Grass, { Shadow = false })
			kit:CylD("Sunflower", bx + 0.8, yRoof + 3.8, 1.8, 1.4, 0.2, C.Butter, M.SmoothPlastic, { Shadow = false })
		end
	end
	-- porte d'acier + auvent + lanterne
	local gx = ctx.DoorX
	local yDoor = WorldLayout.FloorY(1)
	frontDoor(ctx, P.Steel:Lerp(C.Mint, 0.35), steel, true)
	kit:Box("DoorCanopy", gx - 3.6, gx + 3.6, yDoor + WorldLayout.DOOR_H + 1.1, yDoor + WorldLayout.DOOR_H + 1.5, -2.4, -0.3, steel, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		kit:Slab("CanopyRod", gx + s * 3.2, { yDoor + WorldLayout.DOOR_H + 1.3, -2.2 }, { yDoor + WorldLayout.DOOR_H + 3.2, -0.3 }, 0.12, 0.12, steel, M.Metal, { Shadow = false })
	end
	wallLantern(ctx, gx - WorldLayout.DOOR_W / 2 - 1.6, yDoor + 3.6, true)
	local foot = porch(ctx, gx - 3.4, gx + 3.4, 1.6, 3, Color3.fromRGB(226, 216, 232), M.Concrete)
	namePlate(ctx, gx, yDoor + WorldLayout.DOOR_H + 1.8, -2.45, 6)
	-- enseigne néon verticale "LOFT" (à gauche, sur consoles)
	local sx = ctx.Left - T - 3.4
	for _, by in ipairs({ ctx.Top - 4, ctx.Top - 12 }) do
		kit:Box("SignBracket", sx + 1.4, ctx.Left - T, by, by + 0.3, -0.9, -0.5, steel, M.Metal, { Shadow = false })
	end
	local board = kit:Box("NeonSign", sx - 1.6, sx + 1.6, ctx.Top - 14, ctx.Top - 2, -1.2, -0.4, Color3.fromRGB(86, 64, 120), M.SmoothPlastic, { Solid = true })
	heart(ctx, sx, ctx.Top - 3.3, -1.35, 1.8, Color3.fromRGB(255, 150, 206), M.Neon)
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
		label.Position = UDim2.fromScale(0.5, 0.24 + (index - 1) * 0.19)
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
		local f0, f1 = gx - 5, ctx.Right + T + 2.5
		kit:Box("FireLanding", f0, f1, ly - 0.3, ly, -3.2, -0.3, steel, M.DiamondPlate, { Shadow = false })
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
	ctx.G:Box("Sidewalk", ctx.Left - 8, ctx.Right + 6, -0.1, 0.12, -6, -0.6, P.Pave, M.Pavement, { Shadow = false })
	for index, c in ipairs({ { ctx.Left + 2, -3 }, { ctx.Left + 5, -3.4 }, { ctx.Left + 3.2, -5 } }) do
		ctx.G:Box("Crate", c[1] - 1.2, c[1] + 1.2, 0, 1.8 - (index % 2) * 0.3, c[2] - 1, c[2] + 1, C.Wood, M.WoodPlanks, { Shadow = false })
		ctx.G:Ball("CrateBush", c[1], 2.2, c[2], 1.8, P.Leaf, M.Grass, { Shadow = false })
	end
	local benchX = (WorldLayout.ColumnSpan(ctx.Size, 1) + select(2, WorldLayout.ColumnSpan(ctx.Size, 1))) / 2 + 12
	HouseGarden.Bench(ctx.G, benchX, -3, C.Pink)
	HouseGarden.PottedBall(ctx.G, gx - 6.5, -2, 1.2, C.Peach)
	path(ctx, { { 0, -29.5 }, { 0, -7 }, { gx, -7 }, { gx, foot } }, 3.2, P.Pave, M.Pavement)
	picketFence(ctx, ctx.Left - 8, ctx.Right + 4, -21, -2.2, 2.2)
end

-- ░░ Mansion : le grand manoir kawaii ░░
STYLES.Mansion = function(ctx)
	local kit = ctx.Kit
	local dims = ctx.Dims
	local T = WorldLayout.WALL_T
	local TRIM = Color3.fromRGB(255, 250, 244)
	local TOWER = ctx.Wall:Lerp(C.Pink, 0.1)
	local holes: { [number]: { { number } } } = {}
	local windows = {}
	for floor = 1, dims.Floors do
		holes[floor] = {}
		for column = 1, dims.Columns do
			local r = windowRect(ctx, column, floor)
			table.insert(holes[floor], r)
			table.insert(windows, { r, (floor - 1) * dims.Columns + column })
		end
		local yFloor = WorldLayout.FloorY(floor)
		if floor == 1 then
			table.insert(holes[floor], { ctx.DoorX - WorldLayout.DOOR_W / 2, ctx.DoorX + WorldLayout.DOOR_W / 2, yFloor, yFloor + WorldLayout.DOOR_H })
		elseif floor == 2 then
			local r = { ctx.DoorX - 2, ctx.DoorX + 2, yFloor + 1.6, yFloor + 8.4 }
			table.insert(holes[floor], r)
			table.insert(windows, { r, nil })
		end
	end
	bodyWalls(ctx, holes, M.Plaster, P.Stone, M.Limestone)
	for _, w in ipairs(windows) do
		local r = w[1]
		roomWindow(ctx, w[2], r[1], r[2], r[3], r[4], TRIM, "Tall")
		archTop(ctx, r[1], r[2], r[4], TRIM)
		-- clé de voûte
		kit:Box("Keystone", (r[1] + r[2]) / 2 - 0.45, (r[1] + r[2]) / 2 + 0.45, r[4] + (r[2] - r[1]) / 2 - 0.2, r[4] + (r[2] - r[1]) / 2 + 0.9, -0.6, -0.3, TRIM, M.Limestone,
			{ Shadow = false })
	end
	-- œil-de-bœuf du dernier étage (travée centrale)
	if dims.Floors >= 3 then
		local y = WorldLayout.FloorY(dims.Floors) + 5.5
		kit:CylD("Oculus", ctx.DoorX, y, -0.45, 3.6, 0.3, TRIM, M.Limestone, { Shadow = false })
		kit:CylD("OculusGlass", ctx.DoorX, y, -0.62, 2.6, 0.1, P.Glass, M.Glass, { Shadow = false })
		heart(ctx, ctx.DoorX, WorldLayout.FloorY(dims.Floors) + 1.8, -0.5, 1.4, C.Pink)
	end
	-- colonnes rondes (bords, murs entre les pièces, travée centrale)
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
	-- dalles : bandeau + balustrades devant les pièces des étages
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor)
		kit:Box("Band", ctx.Left - T - 0.4, ctx.Right + T + 0.4, y - 1.4, y - 0.1, -0.9, -0.3, TRIM, M.Limestone, { Shadow = false })
		kit:Box("BandGold", ctx.Left - T - 0.4, ctx.Right + T + 0.4, y - 0.8, y - 0.6, -0.95, -0.9, P.Gold, M.Metal, { Shadow = false })
		for column = 1, dims.Columns do
			local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
			local b0, b1 = x0 + 1.4, x1 - 1.4
			kit:Box("Balustrade", b0, b1, y + 2.2, y + 2.6, -1.6, -0.3, TRIM, M.Limestone, { Shadow = false })
			kit:Box("BalustradeBase", b0, b1, y - 0.1, y + 0.3, -1.6, -0.3, TRIM, M.Limestone, { Solid = true, Shadow = false })
			local count = math.floor((b1 - b0) / 3.2)
			for k = 0, count do
				local x = b0 + 0.4 + k * (b1 - b0 - 0.8) / count
				kit:CylY("Baluster", x, y + 0.3, -0.95, 0.6, 1.9, TRIM, M.Limestone, { Shadow = false })
			end
		end
		if floor == 2 then
			-- petit balcon arrondi de la travée centrale
			kit:CylY("CenterBalcony", ctx.DoorX, y - 0.4, -0.6, 7, 0.4, TRIM, M.Limestone, { Solid = true })
		end
	end
	-- corniche + modillons + liseré doré
	kit:Box("Cornice", ctx.Left - T - 1, ctx.Right + T + 1, ctx.Top - 0.2, ctx.Top + 1.3, -1.5, 0, TRIM, M.Limestone)
	kit:Box("CorniceGold", ctx.Left - T - 0.7, ctx.Right + T + 0.7, ctx.Top + 0.6, ctx.Top + 0.8, -1.55, -1.5, P.Gold, M.Metal, { Shadow = false })
	local modCount = math.floor((ctx.Right - ctx.Left) / 8)
	for k = 0, modCount do
		local x = ctx.Left + k * (ctx.Right - ctx.Left) / modCount
		kit:Box("Modillion", x - 0.35, x + 0.35, ctx.Top - 0.9, ctx.Top - 0.2, -1.1, -0.3, TRIM, M.Limestone, { Shadow = false })
	end
	-- toit mansardé (ardoises lilas), crête dorée, lucarnes, œils-de-bœuf, cheminées
	local rise = 10
	local inset = 5.5
	local yBase = ctx.Top + 1.3
	local front = mansardRoof(ctx, ctx.Left - T, ctx.Right + T, yBase, rise, inset, M.Slate)
	roofPattern(ctx, front, ctx.Looks.Pattern or "None")
	local crest = math.max(2, math.floor((ctx.Right - ctx.Left - 2 * inset) / 12))
	for k = 0, crest do
		local x = ctx.Left + inset + k * (ctx.Right - ctx.Left - 2 * inset) / crest
		kit:Box("CrestPost", x - 0.12, x + 0.12, yBase + rise, yBase + rise + 1.6, inset - 0.12, inset + 0.12, P.Gold:Lerp(C.Ink, 0.2), M.Metal, { Shadow = false })
		kit:Ball("CrestBall", x, yBase + rise + 1.75, inset, 0.6, P.Gold, M.Metal, { Shadow = false })
	end
	for _, column in ipairs({ 1, dims.Columns }) do
		local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
		dormer(ctx, (x0 + x1) / 2, yBase + 1.6, -0.6 + inset * 1.6 / rise - 0.3, 5.4, 6, false)
	end
	for _, column in ipairs({ 2, dims.Columns - 1 }) do
		if column > 1 and column < dims.Columns then
			local x0, x1 = WorldLayout.ColumnSpan(ctx.Size, column)
			local ox = if column <= WorldLayout.HallAfter(ctx.Size) then x0 + (x1 - x0) * 0.3 else x1 - (x1 - x0) * 0.3
			local oy = yBase + 4.5
			local od = -0.6 + inset * 4.5 / rise
			kit:CylD("RoofOculus", ox, oy, od - 0.3, 3, 0.6, TRIM, M.Limestone, { Shadow = false })
			kit:CylD("RoofOculusGlass", ox, oy, od - 0.62, 2.1, 0.1, P.Glass, M.Glass, { Shadow = false })
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		local cx = ctx.DoorX + s * (ctx.Right - ctx.Left) * 0.3
		chimney(ctx, cx, ctx.Depth * 0.55, yBase + rise - 1, yBase + rise + 4, Color3.fromRGB(246, 180, 196), s > 0)
	end
	-- fronton central + horloge-cœur
	local pedW, pedH = 34, 11
	local pedY = ctx.Top + 1.3
	for _, s in ipairs({ -1, 1 }) do
		kit:Part("Pediment", Vector3.new(1.2, pedH, pedW / 2), CFrame.new(ctx.DoorX + s * pedW / 4, pedY + pedH / 2, 0.9) * CFrame.Angles(0, -s * math.pi / 2, 0), TRIM,
			M.Limestone, { Solid = true }, "WedgePart")
		kit:Part("PedimentInner", Vector3.new(0.3, pedH - 3, pedW / 2 - 4.5), CFrame.new(ctx.DoorX + s * (pedW / 2 - 4.5) / 2, pedY + 0.9 + (pedH - 3) / 2, 0.45)
			* CFrame.Angles(0, -s * math.pi / 2, 0), ctx.Wall:Lerp(C.Pink, 0.3), M.Plaster, { Shadow = false }, "WedgePart")
	end
	heart(ctx, ctx.DoorX, pedY + pedH + 1.1, -0.9, 2.2, C.Heart)
	-- (devant le fronton : face avant en d = -1,5)
	local clockY = pedY + pedH * 0.38
	heart(ctx, ctx.DoorX, clockY, -1.65, 6.4, C.PinkDeep:Lerp(C.Pink, 0.4))
	kit:CylD("ClockRim", ctx.DoorX, clockY - 0.1, -1.95, 3.8, 0.3, P.Gold, M.Metal, { Shadow = false })
	kit:CylD("ClockFace", ctx.DoorX, clockY - 0.1, -2.05, 3.3, 0.2, C.Cream, M.SmoothPlastic, { Shadow = false })
	kit:Part("ClockHand", Vector3.new(0.2, 1.3, 0.1), CFrame.new(ctx.DoorX + 0.2, clockY + 0.45, 2.2) * CFrame.Angles(0, 0, math.rad(-20)), C.Ink, M.Metal, { Shadow = false })
	kit:Part("ClockHand", Vector3.new(0.16, 0.9, 0.1), CFrame.new(ctx.DoorX + 0.35, clockY - 0.3, 2.22) * CFrame.Angles(0, 0, math.rad(115)), C.Ink, M.Metal, { Shadow = false })

	-- tours rondes aux deux bouts (devant les côtés du corps), toits coniques
	local radius = 7
	for index, s in ipairs({ -1, 1 }) do
		local tx = if s < 0 then ctx.Left - T - 1 else ctx.Right + T + 1
		local td = 0.5
		local top = ctx.Top + 3
		kit:CylY("Tower", tx, 0, td, radius * 2, top, TOWER, M.Plaster, { Solid = true })
		kit:CylY("TowerPlinth", tx, 0, td, radius * 2 + 0.6, WorldLayout.PLINTH + 0.4, P.Stone, M.Limestone, { Solid = true })
		for floor = 1, dims.Floors do
			local y = WorldLayout.FloorY(floor)
			if floor > 1 then
				kit:CylY("TowerBand", tx, y - 1.2, td, radius * 2 + 0.5, 0.9, TRIM, M.Limestone, { Shadow = false })
			end
			-- fenêtre cintrée face à la rue
			local wx0, wx1 = tx - 1.8, tx + 1.8
			local wy0, wy1 = y + 2.4, y + 8
			local face = td - radius
			kit:Box("TowerGlass", wx0, wx1, wy0, wy1, face - 0.35, face + 0.2, P.Glass, M.Glass, { Shadow = false })
			kit:Box("TowerWinFrame", wx0 - 0.35, wx1 + 0.35, wy0 - 0.35, wy0, face - 0.45, face + 0.2, TRIM, M.Wood, { Shadow = false })
			kit:CylD("TowerArch", tx, wy1, face - 0.25, 3.6, 0.35, P.Glass, M.Glass, { Shadow = false })
			kit:CylD("TowerArchRim", tx, wy1, face - 0.1, 4.3, 0.2, TRIM, M.Wood, { Shadow = false })
		end
		kit:CylD("TowerOculus", tx, top - 2.2, td - radius - 0.1, 2.4, 0.3, P.Glass, M.Glass, { Shadow = false })
		kit:CylY("TowerCrown", tx, top - 0.3, td, radius * 2 + 1.6, 1.2, TRIM, M.Limestone, { Solid = true })
		local scallops = 10
		for k = 0, scallops - 1 do
			local a = k / scallops * math.pi * 2
			kit:Ball("TowerScallop", tx + math.cos(a) * (radius + 0.5), top - 0.6, td + math.sin(a) * (radius + 0.5), 1.1, C.Pink, M.SmoothPlastic, { Shadow = false })
		end
		kit:Cone("TowerRoof", tx, top + 0.9, td, radius + 1.6, 12, 10, ctx.Roof, M.Slate)
		kit:Ball("TowerTop", tx, top + 13.1, td, 0.9, P.Gold, M.Metal, { Shadow = false })
		kit:Box("FlagPole", tx - 0.1, tx + 0.1, top + 13.3, top + 17.5, td - 0.1, td + 0.1, WHITE, M.Metal, { Shadow = false })
		kit:Box("Flag", tx + 0.1, tx + 2.6, top + 15.8, top + 17.4, td - 0.06, td + 0.06, if index == 1 then C.Pink else C.Lilac, M.Fabric, { Shadow = false })
	end

	-- porte d'honneur + grand escalier double
	local gx = ctx.DoorX
	local yDoor = WorldLayout.FloorY(1)
	frontDoor(ctx, C.PinkDeep:Lerp(C.Pink, 0.45), TRIM, true)
	archTop(ctx, gx - WorldLayout.DOOR_W / 2, gx + WorldLayout.DOOR_W / 2, yDoor + WorldLayout.DOOR_H + 0.6, TRIM)
	heart(ctx, gx, yDoor + WorldLayout.DOOR_H + 4.2, -0.5, 1.2, C.Heart)
	namePlate(ctx, gx, yDoor + WorldLayout.DOOR_H + 5.2, -0.4, 7)
	local landD, landW = 4, 9
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
		-- rampe à balustres + piliers + lanternes
		kit:SlabX("StairRail", -landD - 0.1, { x0, yDoor + 2.6 }, { xEnd, 2.6 }, 0.4, 0.35, TRIM, M.Limestone, { Shadow = false })
		for k = 1, steps - 1 do
			local x = x0 + s * (k - 0.5) * tread
			kit:CylY("StairBaluster", x, yDoor - k * stepRise, -landD - 0.1, 0.45, 2.6, TRIM, M.Limestone, { Shadow = false })
		end
		kit:Box("StairPillar", xEnd - 0.7, xEnd + 0.7, 0, 3.4, -landD - 0.8, -landD + 0.6, TRIM, M.Limestone, { Solid = true })
		postLantern(ctx, xEnd, -landD - 0.1, 3.4, 0.6, s > 0)
		kit:Ball("PillarBall", x0, yDoor + 3, -landD - 0.1, 0.8, P.Gold, M.Metal, { Shadow = false })
	end
	-- parvis, fontaine, parterres, haies, topiaires, grille
	local court0, court1 = gx - landW / 2 - steps * tread - 3, gx + landW / 2 + steps * tread + 3
	ctx.G:Box("Forecourt", court0, court1, -0.1, 0.1, -9, -landD, P.Pave, M.Pavement, { Shadow = false })
	path(ctx, { { gx, -29.5 }, { gx, -18 } }, 4, P.Pave, M.Pavement)
	HouseGarden.Fountain(ctx.G, gx, -13.5)
	for _, s in ipairs({ -1, 1 }) do
		local x1 = if s < 0 then ctx.Left - T - 1 + 7.5 else court1 + 1
		local x2 = if s < 0 then court0 - 1 else ctx.Right + T + 1 - 7.5
		ctx.G:Box("Hedge", x1, x2, 0, 1.6, -3.4, -1.4, P.Leaf, M.Grass)
		local bumps = math.max(1, math.floor((x2 - x1) / 5))
		for k = 0, bumps - 1 do
			ctx.G:CylX("HedgeTop", x1 + (k + 0.5) * (x2 - x1) / bumps, 1.6, -2.4, 2, (x2 - x1) / bumps - 0.4, P.Leaf:Lerp(WHITE, 0.06), M.Grass, { Shadow = false })
		end
		flowerDots(ctx, x1 + 1, x2 - 1, -3.8, 6)
		-- topiaire à étages près de la tour
		local tcx = if s < 0 then ctx.Left - T - 1 else ctx.Right + T + 1
		if not (ctx.Garage and s > 0) then -- (v9.6 : place du garage)
			HouseGarden.Topiary(ctx.G, tcx, -10)
		end
		-- parterre rond fleuri
		local bx = gx + s * (ctx.Right - ctx.Left) * 0.24
		HouseGarden.FlowerBed(ctx.G, bx, -12, 5)
	end
	if ctx.Garage then
		-- (v9.6) la grille s'arrête contre l'aile du garage, reprend après
		ironFence(ctx, ctx.Left - T - 7, GarageLayout.X0, -21, gx - 3.5, gx + 3.5)
		garageWing(ctx)
	else
		ironFence(ctx, ctx.Left - T - 7, ctx.Right + T + 7, -21, gx - 3.5, gx + 3.5)
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function HouseFacade.Build(kit: any, size: any, looks: Looks): Built
	local dims = WorldLayout.Dims(size)
	local style = WorldLayout.StyleOf(size)
	if not STYLES[style] then
		style = "Cottage"
	end
	local wall = looks.Wall or DEFAULT_WALL[style]
	local roof = looks.Roof or DEFAULT_ROOF[style]
	local hall0, hall1 = WorldLayout.HallSpan(size)
	local built: Built = { Door = nil, Hinge = nil, Lock = nil, Fills = {}, Chimneys = 0, Style = style }
	local ctx: Ctx = {
		Kit = kit,
		G = kit:Sub(CFrame.new(0, HouseKit.LAWN, 0)),
		Size = size,
		Dims = dims,
		Style = style,
		Looks = looks,
		Wall = if style == "Loft" and looks.Wall then (looks.Wall :: Color3):Lerp(BLACK, 0.06) else wall,
		WallDark = wall:Lerp(C.Ink, 0.22),
		Roof = roof,
		RoofDark = roof:Lerp(C.Ink, 0.28),
		Trim = C.Cream,
		Left = dims.Left,
		Right = dims.Left + dims.Width,
		Top = WorldLayout.FloorY(dims.Floors) + WorldLayout.WALL_H,
		Depth = dims.Depth,
		Hall0 = hall0,
		Hall1 = hall1,
		DoorX = WorldLayout.DoorX(size),
		Built = built,
		Garage = style == "Mansion" and GarageLayout.Supports(size) and hasGarage(kit, looks),
	}
	STYLES[style](ctx)
	-- déco du jardin choisie dans la maison 2D : mêmes places (de gauche à droite)
	-- (v9.6 : avec le garage, elle s'arrête avant l'aile)
	local decoRight = if ctx.Garage then GarageLayout.X0 - 3 else dims.Left + dims.Width + 4
	HouseGarden.Decorations(ctx.G, looks.Garden, dims.Left - 4, decoRight, -15, style == "Mansion")
	return built
end

return HouseFacade
