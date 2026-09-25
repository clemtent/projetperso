--[[
	HouseExterior (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseExterior

	Façade "maison de poupée" kawaii autour de la grille des pièces : le
	bâtiment est vu de face, mur avant retiré (coupe). Uniquement des Frames.
	Quatre styles (Config.House.Sizes[].Exterior) :
	  - Cottage   : petite chaumière de conte (toit de tuiles rondes,
	    cheminée qui fume, chat sur le toit, porche, barrière, boîte aux
	    lettres, pas japonais, arbre) ;
	  - Townhouse : maison de ville pastel (toit mansardé, lucarnes, balcons
	    en fer forgé, entrée avec marquise rayée, lampadaire, vélo) ;
	  - Loft      : entrepôt de briques (cadres d'usine en acier, toit-terrasse
	    fleuri avec château d'eau et guirlande, escalier de secours, néon) ;
	  - Mansion   : vrai manoir (tours rondes à toits coniques et drapeaux,
	    fronton avec horloge-cœur, lucarnes, balustrades, colonnes, grand
	    escalier double, jardin à la française, fontaine, grille, lanternes).
	Le mode nuit teinte tout en bleu nuit (comme HouseScenery), allume les
	fenêtres et les lanternes, fait sortir les lucioles.

	API (contrat A) :
	  HouseExterior.CELL_H                 hauteur d'une pièce (px de maquette)
	  HouseExterior.CellWidth(size)        largeur d'une pièce
	  HouseExterior.Build(parent, size) -> Exterior
	      Frame      : racine transparente (AnchorPoint 0.5, 0.5), taille
	                   Width x Height ; l'appelant la place et la met à
	                   l'échelle avec son propre UIScale
	      Cells      : [slot] = { X, Y, W, H } (intérieur de la pièce, relatif
	                   à Frame) ; slot = (étage - 1) * Columns + colonne,
	                   étage 1 en bas, colonne 1 à gauche
	      CellLayer  : calque (au-dessus du fond de façade, sous les détails
	                   avant : dalles, colonnes, garde-corps) pour les pièces
	      SetDark(dark), Update(dt), Destroy()
	  HouseExterior.BuildBackdrop(parent, size?) -> Backdrop (facultatif)
	      ciel pastel (dégradé, nuages, soleil / lune, étoiles, collines) qui
	      remplit `parent` ; { Frame, SetDark(dark), Update(dt), Destroy() }
]]

local HouseCommon = require(script.Parent.HouseCommon)

type SizeDef = HouseCommon.SizeDef

local HouseExterior = {}

HouseExterior.CELL_H = 190

function HouseExterior.CellWidth(size: SizeDef): number
	return math.floor(300 * (size.Width or 1))
end

export type Rect = { X: number, Y: number, W: number, H: number }

export type Exterior = {
	Frame: Frame,
	Width: number,
	Height: number,
	Cells: { [number]: Rect },
	CellLayer: Frame,
	SetDark: (dark: boolean) -> (),
	Update: (dt: number) -> (),
	Destroy: () -> (),
}

export type Backdrop = {
	Frame: Frame,
	SetDark: (dark: boolean) -> (),
	Update: (dt: number) -> (),
	Destroy: () -> (),
}

----------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local INK = C.Ink
local FONT = Enum.Font.FredokaOne

local NIGHT_TINT = Color3.fromRGB(40, 36, 100) -- même voile que HouseScenery
local NIGHT_AMOUNT = 0.42
local LIT = Color3.fromRGB(255, 214, 120) -- fenêtre allumée
local LIT_SOFT = Color3.fromRGB(255, 232, 170)
local GLOW = Color3.fromRGB(255, 222, 140)

local P = {
	Grass = Color3.fromRGB(150, 222, 150),
	GrassDark = Color3.fromRGB(108, 190, 118),
	Leaf = Color3.fromRGB(128, 206, 128),
	LeafDark = Color3.fromRGB(84, 160, 100),
	Trunk = Color3.fromRGB(176, 124, 96),
	Stone = Color3.fromRGB(240, 232, 244),
	StoneDark = Color3.fromRGB(208, 194, 222),
	Pave = Color3.fromRGB(232, 222, 240),
	RoofPink = Color3.fromRGB(255, 150, 190),
	RoofPinkDark = Color3.fromRGB(226, 104, 156),
	Slate = Color3.fromRGB(190, 170, 240),
	SlateDark = Color3.fromRGB(146, 120, 210),
	Brick = Color3.fromRGB(236, 152, 146),
	BrickDark = Color3.fromRGB(208, 116, 120),
	BrickLight = Color3.fromRGB(250, 186, 176),
	Steel = Color3.fromRGB(128, 106, 156),
	SteelDark = Color3.fromRGB(96, 78, 124),
	Glass = Color3.fromRGB(196, 230, 255),
	Gold = Color3.fromRGB(246, 196, 84),
	Water = Color3.fromRGB(150, 215, 255),
	Interior = Color3.fromRGB(232, 206, 230),
}

----------------------------------------------------------------------
-- Formes de base (même esprit que le kit de HouseArt)
----------------------------------------------------------------------

local function outlineOf(color: Color3): Color3
	return color:Lerp(INK, 0.55)
end

local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, t: number?, z: number?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = t or 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.ZIndex = z or 1
	frame.Parent = parent
	return frame
end

-- Coins arrondis ; r = nil ou négatif -> pilule / ovale
local function round(frame: GuiObject, r: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if r == nil or r < 0 then UDim.new(1, 0) else UDim.new(0, r)
	corner.Parent = frame
end

local function stroke(frame: GuiObject, color: Color3, thickness: number?, t: number?): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness or 2
	line.Transparency = t or 0
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.LineJoinMode = Enum.LineJoinMode.Round
	line.Parent = frame
	return line
end

-- Dégradé de couleur (multiplie le fond) ; rotation 90 = haut -> bas
local function grad(frame: GuiObject, a: Color3, b: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation or 90
	g.Parent = frame
	return g
end

-- Fondu de transparence ; rotation 90 = haut -> bas
local function fade(frame: GuiObject, from: number, to: number, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new(from, to)
	g.Rotation = rotation or 90
	g.Parent = frame
	return g
end

-- Ombrage vertical doux (clair en haut)
local function shade(frame: GuiObject, amount: number?)
	local k = 1 - (amount or 0.1)
	grad(frame, WHITE, Color3.new(k, k, k), 90)
end

local function circle(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, t: number?, z: number?): Frame
	local frame = box(parent, cx - w / 2, cy - h / 2, w, h, color, t, z)
	round(frame)
	return frame
end

type PartOpts = {
	R: number?, -- rayon (défaut 6) ; -1 = pilule
	Z: number?,
	T: number?,
	Line: any?, -- false = sans contour ; Color3 ; défaut = teinte foncée
	Th: number?, -- épaisseur du contour (défaut 2)
	Shade: any?, -- false = sans ombrage ; nombre = force (défaut 0.1)
}

-- Forme "autocollant" : fond + contour prune + ombrage
local function part(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, options: PartOpts?): Frame
	local o: PartOpts = options or {}
	local frame = box(parent, x, y, w, h, color, o.T, o.Z)
	local r = o.R
	if r == nil then
		r = 6
	end
	if r ~= 0 then
		round(frame, r)
	end
	if o.Line ~= false then
		stroke(frame, if typeof(o.Line) == "Color3" then o.Line else outlineOf(color), o.Th or 2, 0)
	end
	if o.Shade ~= false then
		shade(frame, if type(o.Shade) == "number" then o.Shade else 0.1)
	end
	return frame
end

local function blob(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, options: PartOpts?): Frame
	local o: PartOpts = options or {}
	return part(parent, cx - w / 2, cy - h / 2, w, h, color, { R = -1, Z = o.Z, T = o.T, Line = o.Line, Th = o.Th, Shade = o.Shade })
end

-- Trait arrondi entre deux points (cadre tourné : jamais dans un conteneur découpé)
local function line(parent: Instance, x1: number, y1: number, x2: number, y2: number, th: number, color: Color3, t: number?, z: number?): Frame
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	local frame = box(parent, 0, 0, length + th, th, color, t, z)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	frame.Rotation = math.deg(math.atan2(dy, dx))
	round(frame)
	return frame
end

local function diamond(parent: Instance, cx: number, cy: number, side: number, color: Color3, t: number?, z: number?): Frame
	local frame = box(parent, 0, 0, side, side, color, t, z)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(cx, cy)
	frame.Rotation = 45
	return frame
end

-- Conteneur transparent (groupe) ; clip = découpe (jamais de cadre tourné dedans)
local function group(parent: Instance, x: number, y: number, w: number, h: number, z: number?, clip: boolean?): Frame
	local frame = box(parent, x, y, w, h, WHITE, 1, z)
	frame.ClipsDescendants = clip == true
	return frame
end

-- Cœur (2 cercles + losange) dans un conteneur centré en (cx, cy)
local SQRT2 = math.sqrt(2)
local function heart(parent: Instance, cx: number, cy: number, width: number, color: Color3, t: number?, z: number?): Frame
	local holder = group(parent, cx - width / 2, cy - width / 2, width, width, z)
	local a = width / (1 + 1 / SQRT2)
	local centerY = width / 2 + a * 0.073
	local offset = a / (2 * SQRT2)
	diamond(holder, width / 2, centerY, a, color, t, 1)
	circle(holder, width / 2 - offset, centerY - offset, a, a, color, t, 1)
	circle(holder, width / 2 + offset, centerY - offset, a, a, color, t, 1)
	return holder
end

-- Étincelle à 4 branches (dans un conteneur)
local function sparkle(parent: Instance, cx: number, cy: number, size: number, color: Color3, t: number?, z: number?): Frame
	local holder = group(parent, cx - size / 2, cy - size / 2, size, size, z)
	diamond(holder, size / 2, size / 2, size * 0.36, color, t, 1)
	local thin = math.max(1, size * 0.14)
	round(box(holder, size / 2 - thin / 2, 0, thin, size, color, t, 1))
	round(box(holder, 0, size / 2 - thin / 2, size, thin, color, t, 1))
	return holder
end

-- Trapèze en tranches horizontales (toits, frontons, cônes) : largeur
-- `topW` en haut, `baseW` en bas ; teinte qui fonce doucement vers le bas
local function trapezoid(parent: Instance, cx: number, top: number, topW: number, baseW: number, h: number, color: Color3, bottomColor: Color3?, z: number?, slices: number?): Frame
	local holder = group(parent, cx - baseW / 2, top, baseW, h, z)
	local count = slices or math.clamp(math.floor(h / 7), 4, 30)
	for index = 1, count do
		local k = (index - 0.5) / count
		local w = topW + (baseW - topW) * k
		local slice = box(holder, baseW / 2 - w / 2, (index - 1) * h / count, w, h / count + 0.7, color, 0, 1)
		if bottomColor then
			slice.BackgroundColor3 = color:Lerp(bottomColor, k)
		end
	end
	return holder
end

-- Rangée de festons (demi-ovales) entre x1 et x2, centrés sur y
local function scallops(parent: Instance, x1: number, x2: number, y: number, step: number, h: number, color: Color3, t: number?, z: number?, offset: number?)
	local count = math.max(1, math.floor((x2 - x1) / step))
	local start = x1 + ((x2 - x1) - count * step) / 2 + step / 2 + (offset or 0)
	for index = 0, count - 1 do
		local x = start + index * step
		if x > x1 and x < x2 then
			circle(parent, x, y, step - 2, h, color, t, z)
		end
	end
end

-- Tuiles rondes à l'intérieur d'un trapèze (rangées décalées)
local function tileRows(parent: Instance, cx: number, top: number, topW: number, baseW: number, h: number, rows: number, tile: number, color: Color3, t: number?, z: number?)
	for row = 1, rows do
		local y = h * row / (rows + 1)
		local w = topW + (baseW - topW) * (y / h) - tile * 0.8
		scallops(parent, cx - w / 2, cx + w / 2, top + y, tile, tile * 0.5, color, t, z, (row % 2) * tile / 2)
	end
end

-- Silhouette de plusieurs ovales avec un contour commun (passe contour + passe fond)
local function cluster(parent: Instance, blobs: { { number } }, color: Color3, z: number, lineColor: Color3?, th: number?, light: boolean?)
	local ink = lineColor or outlineOf(color)
	local pad = (th or 2) * 2
	for _, b in ipairs(blobs) do
		circle(parent, b[1], b[2], b[3] + pad, b[4] + pad, ink, 0, z)
	end
	for _, b in ipairs(blobs) do
		local frame = circle(parent, b[1], b[2], b[3], b[4], color, 0, z + 1)
		shade(frame, 0.12)
	end
	if light then
		local b = blobs[1]
		circle(parent, b[1] - b[3] * 0.18, b[2] - b[4] * 0.2, b[3] * 0.34, b[4] * 0.22, WHITE, 0.55, z + 2)
	end
end

-- Pseudo-aléatoire stable
local function noise(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

----------------------------------------------------------------------
-- Contexte de construction (nuit, lumières, animations)
----------------------------------------------------------------------

type Anim = (clock: number, dark: boolean) -> ()

type Ctx = {
	Back: Frame,
	Front: Frame,
	Fx: Frame,
	Lit: { [Instance]: Color3 },
	Glows: { { Frame: Frame, Night: number } },
	Anims: { Anim },
	NightOnly: { GuiObject },
	DayOnly: { GuiObject },
}

-- Ce cadre prend une couleur "allumée" la nuit (au lieu du voile bleu)
local function lit(ctx: Ctx, frame: Frame, color: Color3?)
	ctx.Lit[frame] = color or LIT
end

-- Halo de lumière (cercles concentriques), visible seulement la nuit
local function glow(ctx: Ctx, parent: Instance, cx: number, cy: number, size: number, color: Color3?, z: number?)
	local tint = color or GLOW
	for index, ring in ipairs({ { 1, 0.86 }, { 0.66, 0.78 }, { 0.38, 0.66 } }) do
		local frame = circle(parent, cx, cy, size * ring[1], size * ring[1], tint, 1, (z or 1) + index - 1)
		frame.Visible = false
		ctx.Lit[frame] = tint
		table.insert(ctx.Glows, { Frame = frame, Night = ring[2] })
	end
end

type WindowOpts = {
	Arch: boolean?, -- haut en plein cintre
	Round: boolean?, -- œil-de-bœuf
	Frame: Color3?,
	Border: number?,
	Cross: string?, -- "+" (défaut) | "|" | "-" | "none"
	Sill: boolean?,
	Z: number?,
	Glass: Color3?,
	NightColor: Color3?,
}

-- Fenêtre kawaii : contour, cadre, vitre (allumée la nuit), croisillon, reflet
local function window(ctx: Ctx, parent: Instance, x: number, y: number, w: number, h: number, options: WindowOpts?)
	local o: WindowOpts = options or {}
	local z = o.Z or 3
	local fc = o.Frame or C.Cream
	local ink = outlineOf(fc)
	local b = o.Border or math.max(4, math.floor(w * 0.1))
	local glassColor = o.Glass or P.Glass
	local panes: { Frame } = {}
	if o.Round then
		circle(parent, x + w / 2, y + w / 2, w + 4, w + 4, ink, 0, z)
		circle(parent, x + w / 2, y + w / 2, w, w, fc, 0, z + 1)
		table.insert(panes, circle(parent, x + w / 2, y + w / 2, w - b * 2, w - b * 2, glassColor, 0, z + 2))
		h = w
	elseif o.Arch then
		local r = w / 2
		circle(parent, x + r, y + r, w + 4, w + 4, ink, 0, z)
		box(parent, x - 2, y + r, w + 4, h - r + 2, ink, 0, z)
		circle(parent, x + r, y + r, w, w, fc, 0, z + 1)
		box(parent, x, y + r, w, h - r, fc, 0, z + 1)
		table.insert(panes, circle(parent, x + r, y + r, w - b * 2, w - b * 2, glassColor, 0, z + 2))
		table.insert(panes, box(parent, x + b, y + r, w - b * 2, h - r - b, glassColor, 0, z + 2))
	else
		part(parent, x, y, w, h, fc, { R = 4, Z = z, Line = ink, Th = 2, Shade = false })
		local pane = box(parent, x + b, y + b, w - b * 2, h - b * 2, glassColor, 0, z + 2)
		round(pane, 2)
		grad(pane, WHITE, Color3.fromRGB(235, 225, 245), 90)
		table.insert(panes, pane)
	end
	for _, pane in ipairs(panes) do
		lit(ctx, pane, o.NightColor)
	end
	local cross = o.Cross or "+"
	local top = if o.Arch then y + w * 0.3 else y + b
	if cross == "+" or cross == "|" then
		box(parent, x + w / 2 - 1.5, top, 3, y + h - b - top, fc, 0, z + 3)
	end
	if cross == "+" or cross == "-" then
		local cy = if o.Arch then y + w / 2 + (h - w / 2) * 0.35 else y + h / 2
		box(parent, x + b, cy - 1.5, w - b * 2, 3, fc, 0, z + 3)
	end
	-- Reflet
	local shine = box(parent, x + b + 2, y + b + (if o.Arch or o.Round then w * 0.12 else 2), math.max(3, w * 0.16), math.max(3, h * 0.1), WHITE, 0.45, z + 3)
	round(shine)
	if o.Sill ~= false and not o.Round then
		part(parent, x - 5, y + h - 3, w + 10, 7, fc, { R = 3, Z = z + 4, Line = ink, Th = 1.5, Shade = false })
	end
end

-- Lanterne sur poteau (pied en bas à `bottom`), halo la nuit
local function postLantern(ctx: Ctx, parent: Instance, cx: number, bottom: number, height: number, z: number, color: Color3?)
	local metal = color or C.Ink:Lerp(C.Lilac, 0.35)
	part(parent, cx - 3, bottom - height, 6, height, metal, { R = 3, Z = z, Th = 1.5, Shade = false })
	part(parent, cx - 8, bottom - 8, 16, 8, metal, { R = 3, Z = z, Th = 1.5, Shade = false })
	local head = bottom - height
	glow(ctx, parent, cx, head - 12, 110, nil, z)
	part(parent, cx - 11, head - 26, 22, 26, metal, { R = 5, Z = z + 3, Th = 1.5, Shade = false })
	local glass = box(parent, cx - 7, head - 22, 14, 18, LIT_SOFT, 0, z + 4)
	round(glass, 3)
	lit(ctx, glass, LIT)
	part(parent, cx - 14, head - 32, 28, 8, metal, { R = -1, Z = z + 5, Th = 1.5, Shade = false })
	circle(parent, cx, head - 35, 7, 7, P.Gold, 0, z + 5)
end

-- Lanterne murale (accrochée à droite de x)
local function wallLantern(ctx: Ctx, parent: Instance, x: number, y: number, z: number)
	local metal = C.Ink:Lerp(C.Lilac, 0.35)
	box(parent, x, y - 2, 10, 4, metal, 0, z)
	glow(ctx, parent, x + 12, y + 8, 80, nil, z)
	part(parent, x + 4, y - 4, 16, 22, metal, { R = 4, Z = z + 3, Th = 1.5, Shade = false })
	local glass = box(parent, x + 7, y, 10, 14, LIT_SOFT, 0, z + 4)
	round(glass, 2)
	lit(ctx, glass, LIT)
	part(parent, x + 1, y - 9, 22, 7, metal, { R = -1, Z = z + 5, Th = 1.5, Shade = false })
end

-- Fumée de cheminée : 3 bouffées qui montent, grossissent et s'effacent
local function smoke(ctx: Ctx, parent: Instance, x: number, y: number, z: number)
	local puffs = {}
	for index = 1, 3 do
		table.insert(puffs, circle(parent, x, y, 14, 14, Color3.fromRGB(238, 232, 250), 0.1, z))
	end
	table.insert(ctx.Anims, function(clock)
		for index, puff in ipairs(puffs) do
			local t = (clock * 0.28 + (index - 1) / 3) % 1
			local s = 12 + t * 24
			puff.Size = UDim2.fromOffset(s, s)
			puff.Position = UDim2.fromOffset(x - s / 2 + math.sin(t * 6 + index) * 5, y - t * 64 - s / 2)
			puff.BackgroundTransparency = 0.05 + t * 0.9
		end
	end)
end

-- Drapeau qui ondule (mât + fanion en cœur) ; (x, y) = pied du mât
local function flag(ctx: Ctx, parent: Instance, x: number, y: number, height: number, color: Color3, z: number, phase: number)
	part(parent, x - 2.5, y - height, 5, height, C.Cream, { R = -1, Z = z, Th = 1.5, Shade = false })
	circle(parent, x, y - height - 2, 9, 9, P.Gold, 0, z + 1)
	local pivot = group(parent, x, y - height + 5, 0, 0, z + 2)
	local cloth = part(pivot, 1, -2, 46, 26, color, { R = 6, Z = 1, Th = 2, Shade = 0.15 })
	local tail = part(pivot, 34, 2, 22, 18, color:Lerp(BLACK, 0.06), { R = 5, Z = 0, Th = 2, Shade = false })
	heart(cloth, 20, 13, 13, WHITE, 0, 2)
	local _ = tail
	table.insert(ctx.Anims, function(clock)
		pivot.Rotation = math.sin(clock * 2.4 + phase) * 7 + math.sin(clock * 5.1 + phase) * 2
	end)
end

-- Lucioles (la nuit) qui flottent dans une zone
local function fireflies(ctx: Ctx, parent: Instance, x: number, y: number, w: number, h: number, count: number, z: number)
	local flies = {}
	for index = 1, count do
		local fly = circle(parent, 0, 0, 6, 6, Color3.fromRGB(255, 244, 150), 0.1, z)
		fly.Visible = false
		ctx.Lit[fly] = Color3.fromRGB(255, 244, 150)
		table.insert(ctx.NightOnly, fly)
		table.insert(flies, { Frame = fly, X = noise(index, 41), Y = noise(index, 42), Phase = noise(index, 43) * 6 })
	end
	table.insert(ctx.Anims, function(clock, dark)
		if not dark then
			return
		end
		for _, fly in ipairs(flies) do
			local fx = x + w * (fly.X + math.sin(clock * 0.35 + fly.Phase) * 0.08)
			local fy = y + h * (fly.Y + math.sin(clock * 0.5 + fly.Phase * 1.7) * 0.18)
			fly.Frame.Position = UDim2.fromOffset(fx - 3, fy - 3)
			fly.Frame.BackgroundTransparency = 0.1 + (0.5 + 0.5 * math.sin(clock * 3 + fly.Phase)) * 0.6
		end
	end)
end

-- Petite fleur (pétales + cœur)
local function flower(parent: Instance, cx: number, cy: number, size: number, color: Color3, z: number)
	blob(parent, cx, cy, size, size, color, { Z = z, Th = 1.5, Shade = false })
	circle(parent, cx, cy, size * 0.42, size * 0.42, C.Butter, 0, z + 1)
end

-- Buisson rond (3 bosses)
local function bush(parent: Instance, cx: number, bottom: number, w: number, h: number, color: Color3, z: number)
	cluster(parent, {
		{ cx, bottom - h * 0.45, w * 0.62, h * 0.9 },
		{ cx - w * 0.26, bottom - h * 0.32, w * 0.5, h * 0.64 },
		{ cx + w * 0.26, bottom - h * 0.32, w * 0.5, h * 0.64 },
	}, color, z, nil, 2, true)
end

-- Pot de fleurs + boule de buis
local function pottedBall(parent: Instance, cx: number, bottom: number, s: number, pot: Color3, z: number)
	part(parent, cx - 13 * s, bottom - 20 * s, 26 * s, 20 * s, pot, { R = 5, Z = z + 3, Th = 2 })
	part(parent, cx - 16 * s, bottom - 23 * s, 32 * s, 7 * s, pot:Lerp(WHITE, 0.2), { R = 3, Z = z + 4, Th = 2, Shade = false })
	box(parent, cx - 2 * s, bottom - 36 * s, 4 * s, 14 * s, P.Trunk, 0, z)
	blob(parent, cx, bottom - 44 * s, 36 * s, 34 * s, P.Leaf, { Z = z + 1, Line = P.LeafDark:Lerp(INK, 0.3), Shade = 0.15 })
	circle(parent, cx - 7 * s, bottom - 51 * s, 10 * s, 6 * s, WHITE, 0.55, z + 2)
end

-- Arbre (tronc + feuillage en grappe + petits fruits)
local function tree(parent: Instance, cx: number, bottom: number, s: number, z: number, fruit: Color3?)
	part(parent, cx - 9 * s, bottom - 90 * s, 18 * s, 90 * s, P.Trunk, { R = 6, Z = z, Th = 2 })
	cluster(parent, {
		{ cx, bottom - 138 * s, 120 * s, 104 * s },
		{ cx - 46 * s, bottom - 108 * s, 80 * s, 70 * s },
		{ cx + 46 * s, bottom - 108 * s, 80 * s, 70 * s },
		{ cx, bottom - 96 * s, 90 * s, 50 * s },
	}, P.Leaf, z + 1, P.LeafDark:Lerp(INK, 0.3), 2, true)
	if fruit then
		for index, point in ipairs({ { -30, -120 }, { 24, -148 }, { 40, -104 }, { -8, -100 }, { -52, -100 } }) do
			circle(parent, cx + point[1] * s, bottom + point[2] * s, 11 * s, 11 * s, fruit, 0, z + 4)
			local _ = index
		end
	end
end

-- Chat kawaii assis (pieds en bas à `bottom`, taille s), queue qui se balance
local function cat(ctx: Ctx, parent: Instance, cx: number, bottom: number, s: number, z: number)
	local fur = Color3.fromRGB(255, 236, 214)
	local ink = outlineOf(Color3.fromRGB(230, 170, 140))
	local tailPivot = group(parent, cx + 12 * s, bottom - 6 * s, 0, 0, z)
	part(tailPivot, -4 * s, -30 * s, 8 * s, 32 * s, fur, { R = -1, Z = 1, Line = ink, Th = 2, Shade = false })
	blob(parent, cx, bottom - 15 * s, 34 * s, 30 * s, fur, { Z = z + 1, Line = ink, Th = 2 })
	-- Oreilles (derrière la tête)
	for _, side in ipairs({ -1, 1 }) do
		local ear = diamond(parent, cx + side * 9 * s, bottom - 44 * s, 12 * s, fur, 0, z + 1)
		stroke(ear, ink, 2)
		diamond(parent, cx + side * 9 * s, bottom - 43 * s, 6 * s, C.PinkSoft, 0, z + 2)
	end
	blob(parent, cx, bottom - 34 * s, 32 * s, 26 * s, fur, { Z = z + 3, Line = ink, Th = 2 })
	-- Tache caramel
	circle(parent, cx + 7 * s, bottom - 41 * s, 10 * s, 7 * s, Color3.fromRGB(246, 186, 140), 0, z + 4)
	-- Yeux fermés heureux + museau + joues
	for _, side in ipairs({ -1, 1 }) do
		line(parent, cx + (side * 6 - 2.5) * s, bottom - 35 * s, cx + (side * 6 + 2.5) * s, bottom - 35 * s, 2 * s, INK, 0, z + 5)
		circle(parent, cx + side * 10 * s, bottom - 30 * s, 6 * s, 3.5 * s, C.Pink, 0.35, z + 5)
	end
	circle(parent, cx, bottom - 30 * s, 3 * s, 2 * s, INK, 0, z + 5)
	table.insert(ctx.Anims, function(clock)
		tailPivot.Rotation = math.sin(clock * 1.6) * 16 + 20
	end)
end

-- Voile d'ombre en haut de chaque pièce (intérieur du trou de la façade)
local function cellBacks(parent: Instance, cells: { [number]: Rect }, color: Color3, z: number)
	for _, r in pairs(cells) do
		local back = box(parent, r.X - 3, r.Y - 3, r.W + 6, r.H + 6, color, 0, z)
		round(back, 6)
		shade(back, 0.14)
		local shadow = box(parent, r.X - 3, r.Y - 3, r.W + 6, 34, BLACK, 0.78, z + 1)
		fade(shadow, 0, 1, 90)
	end
end

-- Grille des pièces : x0 = bord gauche de la colonne 1, yTop = haut de
-- l'étage le plus haut, gaps = écarts entre colonnes, slab = épaisseur des dalles
local function makeGrid(size: SizeDef, cellW: number, x0: number, yTop: number, gaps: { number }, slab: number): ({ [number]: Rect }, { number }, { number })
	local cells: { [number]: Rect } = {}
	local colX: { number } = {}
	local x = x0
	for column = 1, size.Columns do
		colX[column] = x
		x += cellW + (gaps[column] or 0)
	end
	local floorY: { number } = {}
	for floorIndex = 1, size.Floors do
		floorY[floorIndex] = yTop + (size.Floors - floorIndex) * (HouseExterior.CELL_H + slab)
		for column = 1, size.Columns do
			cells[(floorIndex - 1) * size.Columns + column] = { X = colX[column], Y = floorY[floorIndex], W = cellW, H = HouseExterior.CELL_H }
		end
	end
	return cells, colX, floorY
end

----------------------------------------------------------------------
-- Styles
----------------------------------------------------------------------

type Built = { Width: number, Height: number, Cells: { [number]: Rect } }

local STYLES: { [string]: (ctx: Ctx, size: SizeDef, cellW: number) -> Built } = {}

-- ░░ Cottage : chaumière de conte ░░
STYLES.Cottage = function(ctx, size, cellW)
	local back, front = ctx.Back, ctx.Front
	local cellH = HouseExterior.CELL_H
	local M, T, S = 30, 22, 26
	local left, right = 124, 170
	local cols, floors = size.Columns, size.Floors
	local bodyW = cols * cellW + (cols - 1) * T + M * 2
	local bodyX = left
	local roofTop = 86
	local roofH = 190
	local eaveY = roofTop + roofH
	local cellTop = eaveY + 18
	local gridH = floors * cellH + (floors - 1) * S
	local cellBottom = cellTop + gridH
	local groundY = cellBottom + 34
	local width = left + bodyW + right
	local height = groundY + 96
	local cx = bodyX + bodyW / 2
	local gaps = {}
	for index = 1, cols - 1 do
		gaps[index] = T
	end
	local cells, colX, floorY = makeGrid(size, cellW, bodyX + M, cellTop, gaps, S)

	local WALL = Color3.fromRGB(255, 242, 228)
	local TIMBER = Color3.fromRGB(206, 150, 112)

	-- Pelouse (derrière la maison)
	local lawn = part(back, 6, groundY - 14, width - 12, height - groundY + 8, P.Grass, { R = 24, Z = 1, Line = P.GrassDark, Shade = 0.12 })
	local _ = lawn
	-- Arbre à gauche (derrière le mur) avec des pommes roses
	tree(back, 62, groundY + 6, 1.05, 2, C.Pink)

	-- Cheminée (derrière le toit) + fumée
	local chimneyX = cx + 150
	part(back, chimneyX, roofTop + 4, 34, 110, Color3.fromRGB(226, 142, 142), { R = 4, Z = 3 })
	for row = 0, 2 do
		box(back, chimneyX + 3, roofTop + 14 + row * 14, 28, 2, Color3.fromRGB(255, 214, 204), 0.3, 4)
	end
	part(back, chimneyX - 5, roofTop - 4, 44, 12, Color3.fromRGB(200, 116, 124), { R = 4, Z = 4 })
	smoke(ctx, back, chimneyX + 17, roofTop - 8, 3)

	-- Mur crème (plâtre) + porche à droite (derrière)
	part(back, bodyX, eaveY - 24, bodyW, groundY - eaveY + 24, WALL, { R = 12, Z = 8, Th = 2.5 })
	local annexW = 128
	local annexX = bodyX + bodyW - 14
	local annexTop = cellTop + 64
	local annexCx = annexX + annexW / 2
	part(back, annexX, annexTop, annexW, groundY - annexTop, Color3.fromRGB(255, 226, 234), { R = 8, Z = 9, Th = 2.5 })
	-- Petit pignon rose du porche (tuiles, rives, cœur, lucarne ronde)
	local gableH = 64
	local gableTop = annexTop - gableH + 6
	trapezoid(back, annexCx, gableTop, 10, annexW + 40, gableH, P.RoofPink, P.RoofPink:Lerp(P.RoofPinkDark, 0.35), 10, 12)
	for _, side in ipairs({ -1, 1 }) do
		local rake = line(back, annexCx + side * 4, gableTop + 1, annexCx + side * (annexW / 2 + 22), annexTop + 7, 11, P.RoofPinkDark, 0, 11)
		stroke(rake, P.RoofPinkDark:Lerp(INK, 0.35), 2)
	end
	heart(back, annexCx, gableTop - 8, 18, C.Heart, 0, 12)
	window(ctx, back, annexCx - 14, gableTop + 24, 28, 28, { Round = true, Z = 12, Frame = C.Cream, Border = 5 })
	scallops(back, annexX - 16, annexX + annexW + 16, annexTop + 12, 24, 12, P.RoofPinkDark, 0, 10)
	-- Porte ronde (vitre en cœur), marche, lanterne
	local doorW, doorH = 60, 106
	local doorX = annexCx - doorW / 2 - 8
	local doorTop = groundY - doorH - 6
	circle(back, doorX + doorW / 2, doorTop + doorW / 2, doorW + 12, doorW + 12, TIMBER, 0, 11)
	box(back, doorX - 6, doorTop + doorW / 2, doorW + 12, doorH - doorW / 2, TIMBER, 0, 11)
	circle(back, doorX + doorW / 2, doorTop + doorW / 2, doorW, doorW, C.Pink, 0, 12)
	local doorLow = box(back, doorX, doorTop + doorW / 2, doorW, doorH - doorW / 2, C.Pink, 0, 12)
	shade(doorLow, 0.15)
	box(back, doorX + doorW / 2 - 1, doorTop + 10, 2, doorH - 12, C.PinkDeep, 0.4, 13)
	local heartGlass = heart(back, doorX + doorW / 2, doorTop + 30, 24, P.Glass, 0, 13)
	for _, child in ipairs(heartGlass:GetChildren()) do
		lit(ctx, child :: Frame)
	end
	circle(back, doorX + doorW - 10, doorTop + doorH * 0.62, 7, 7, P.Gold, 0, 13)
	part(back, doorX - 12, groundY - 8, doorW + 24, 10, P.StoneDark, { R = 4, Z = 13, Shade = false })
	wallLantern(ctx, back, doorX + doorW + 10, doorTop + 30, 13)

	-- Toit : pan de tuiles rondes, rives, festons, faîtage, cœur
	local overhang = 36
	local baseW = bodyW + overhang * 2
	local topW = 64
	trapezoid(back, cx, roofTop, topW, baseW, roofH, P.RoofPink, P.RoofPink:Lerp(P.RoofPinkDark, 0.35), 12, 26)
	tileRows(back, cx, roofTop, topW, baseW, roofH, 3, 34, P.RoofPinkDark, 0.5, 13)
	for _, side in ipairs({ -1, 1 }) do
		local rake = line(back, cx + side * (topW / 2 - 2), roofTop + 2, cx + side * (baseW / 2 + 2), eaveY + 2, 16, P.RoofPinkDark, 0, 15)
		stroke(rake, P.RoofPinkDark:Lerp(INK, 0.35), 2)
	end
	local eave = part(back, cx - baseW / 2 - 6, eaveY - 6, baseW + 12, 14, P.RoofPinkDark, { R = -1, Z = 15, Line = P.RoofPinkDark:Lerp(INK, 0.35) })
	local _ = eave
	scallops(back, cx - baseW / 2, cx + baseW / 2, eaveY + 8, 28, 16, P.RoofPinkDark, 0, 14)
	part(back, cx - topW / 2 - 12, roofTop - 7, topW + 24, 14, P.RoofPinkDark, { R = -1, Z = 16, Line = P.RoofPinkDark:Lerp(INK, 0.35) })
	heart(back, cx, roofTop - 16, 24, C.Heart, 0, 17)
	-- Reflet doux
	round(box(back, cx - topW / 2 - 6, roofTop + 14, 70, 6, WHITE, 0.6, 14))
	-- Lucarne ronde + jardinière
	local winY = roofTop + 70
	window(ctx, back, cx - 32, winY, 64, 64, { Round = true, Z = 20, Frame = C.Cream, Border = 8 })
	part(back, cx - 46, winY + 64, 92, 18, C.Pink, { R = 5, Z = 25, Th = 2 })
	heart(back, cx, winY + 73, 11, WHITE, 0, 26)
	for index, color in ipairs({ C.Butter, WHITE, C.Lilac, C.Butter }) do
		local fx = cx - 33 + (index - 1) * 22
		circle(back, fx, winY + 62, 14, 10, P.Leaf, 0, 22)
		flower(back, fx, winY + 56 - (index % 2) * 4, 15, color, 23)
	end
	-- Chat sur le pan gauche
	local catX = cx - 170
	local slopeY = roofTop + (math.abs(catX - cx) - topW / 2) / ((baseW - topW) / 2) * roofH
	cat(ctx, back, catX, slopeY - 2, 1.45, 26)

	-- Cellules (trous de la façade)
	cellBacks(back, cells, P.Interior, 30)

	-- ░ Détails avant : poutres, poteaux, soubassement ░
	part(front, bodyX + 4, cellTop - 16, bodyW - 8, 18, TIMBER, { R = 5, Z = 2, Th = 2 })
	for index = 0, cols do
		local x = if index == 0 then bodyX + 6 elseif index == cols then bodyX + bodyW - M + 1 else colX[index] + cellW - 3
		local w = if index == 0 or index == cols then M - 7 + 3 else T + 6
		part(front, x, cellTop - 4, w, gridH + 8, TIMBER, { R = 4, Z = 3, Th = 2 })
		if index > 0 and index < cols then
			heart(front, x + w / 2, cellTop + 24, 14, C.Pink, 0, 4)
		end
	end
	for floorIndex = 2, floors do
		part(front, bodyX + 4, floorY[floorIndex] + cellH - 3, bodyW - 8, S + 6, TIMBER, { R = 5, Z = 3 })
	end
	-- Soubassement en pierres rondes + seuil
	part(front, bodyX + 2, cellBottom - 4, bodyW - 4, groundY - cellBottom + 6, P.Stone, { R = 8, Z = 4, Line = P.StoneDark:Lerp(INK, 0.3) })
	part(front, bodyX - 2, cellBottom - 6, bodyW + 4, 10, TIMBER, { R = -1, Z = 6 })
	local stoneCount = math.floor((bodyW - 20) / 46)
	for index = 0, stoneCount - 1 do
		local sx = bodyX + 22 + index * (bodyW - 44) / math.max(1, stoneCount - 1)
		local sy = cellBottom + 16 + (index % 2) * 7
		circle(front, sx, sy, 32, 13, P.StoneDark, 0.35, 5)
	end

	-- Rosier grimpant sur le poteau de gauche
	for index = 0, 5 do
		local ly = groundY - 20 - index * 30
		local lx = bodyX + 18 + (if index % 2 == 0 then -6 else 8)
		blob(front, lx, ly, 22, 14, P.Leaf, { Z = 6, Line = P.LeafDark:Lerp(INK, 0.3), Th = 1.5, Shade = 0.15 })
		if index % 2 == 1 then
			flower(front, lx - 10, ly - 8, 14, C.Pink, 7)
		end
	end

	-- ░ Jardin : buissons, pas japonais, barrière, boîte aux lettres, fleurs ░
	bush(front, bodyX + 16, groundY + 6, 70, 46, P.Leaf, 7)
	bush(front, annexX + annexW - 6, groundY + 6, 60, 40, P.Leaf, 7)
	local gateX = cx + 40
	for index = 0, 4 do
		local k = index / 4
		local sx = gateX + (doorX + doorW / 2 - gateX) * (k ^ 0.8)
		local sy = groundY + 84 - k * 72
		blob(front, sx, sy, 48 - k * 18, 17 - k * 6, P.Stone, { Z = 5, Line = P.StoneDark:Lerp(INK, 0.25), Shade = 0.2 })
	end
	-- Barrière (piquets blancs) en deux morceaux autour du portillon
	local fenceTop, fenceH = groundY + 34, 40
	local function fence(x1: number, x2: number)
		part(front, x1, fenceTop + 10, x2 - x1, 7, WHITE, { R = 3, Z = 8, Line = C.Lilac:Lerp(INK, 0.3), Th = 1.5, Shade = false })
		part(front, x1, fenceTop + 26, x2 - x1, 7, WHITE, { R = 3, Z = 8, Line = C.Lilac:Lerp(INK, 0.3), Th = 1.5, Shade = false })
		local count = math.max(2, math.floor((x2 - x1) / 22))
		for index = 0, count do
			local px = x1 + index * (x2 - x1) / count
			part(front, px - 5, fenceTop, 10, fenceH, WHITE, { R = 5, Z = 9, Line = C.Lilac:Lerp(INK, 0.3), Th = 1.5, Shade = 0.08 })
		end
	end
	fence(14, gateX - 34)
	fence(gateX + 34, math.min(width - 14, gateX + 150))
	-- Fleurs le long de la barrière
	local flowerColors = { C.Pink, C.Butter, C.Lilac, WHITE, C.Peach }
	local count = 9
	for index = 0, count - 1 do
		local fx = 30 + index * (gateX - 80) / (count - 1)
		flower(front, fx, fenceTop + fenceH + 6 + (index % 2) * 5, 13, flowerColors[index % #flowerColors + 1], 11)
	end
	-- Boîte aux lettres (à gauche du portillon)
	local mbX = gateX - 64
	part(front, mbX - 3, fenceTop - 30, 6, 64, TIMBER, { R = 2, Z = 12, Th = 1.5 })
	part(front, mbX - 20, fenceTop - 52, 40, 26, C.Pink, { R = 10, Z = 13, Th = 2 })
	heart(front, mbX - 2, fenceTop - 39, 12, WHITE, 0, 14)
	part(front, mbX + 14, fenceTop - 62, 4, 18, C.Heart, { R = 2, Z = 12, Th = 1.5, Shade = false })

	fireflies(ctx, ctx.Fx, 20, groundY - 150, width - 40, 160, 7, 1)
	return { Width = width, Height = height, Cells = cells }
end

-- ░░ Townhouse : maison de ville pastel ░░
STYLES.Townhouse = function(ctx, size, cellW)
	local back, front = ctx.Back, ctx.Front
	local cellH = HouseExterior.CELL_H
	local M, T, S = 32, 22, 32
	local left, right = 132, 150
	local cols, floors = size.Columns, size.Floors
	local bodyW = cols * cellW + (cols - 1) * T + M * 2
	local bodyX = left
	local roofTop = 66
	local roofH = 132
	local corniceY = roofTop + roofH - 4
	local cellTop = corniceY + 44
	local gridH = floors * cellH + (floors - 1) * S
	local cellBottom = cellTop + gridH
	local groundY = cellBottom + 36
	local width = left + bodyW + right
	local height = groundY + 86
	local cx = bodyX + bodyW / 2
	local gaps = {}
	for index = 1, cols - 1 do
		gaps[index] = T
	end
	local cells, colX, floorY = makeGrid(size, cellW, bodyX + M, cellTop, gaps, S)

	local WALL = Color3.fromRGB(196, 238, 220)
	local WALL_DARK = Color3.fromRGB(150, 208, 186)
	local TRIM = C.Cream

	-- Trottoir, bordure, rue
	part(back, -4, groundY - 8, width + 8, 64, P.Pave, { R = 0, Z = 1, Line = false, Shade = 0.08 })
	for index = 0, math.floor(width / 72) do
		box(back, 30 + index * 72, groundY + 4, 3, 44, P.StoneDark, 0.4, 2)
	end
	part(back, -4, groundY + 50, width + 8, 12, P.StoneDark, { R = 0, Z = 2, Line = false, Shade = 0.15 })
	part(back, -4, groundY + 62, width + 8, height - groundY - 62, Color3.fromRGB(176, 164, 200), { R = 0, Z = 1, Line = false, Shade = 0.2 })
	for index = 0, math.floor(width / 90) do
		round(box(back, 20 + index * 90, groundY + 72, 40, 5, WHITE, 0.35, 2))
	end

	-- Cheminées (derrière le toit)
	for _, side in ipairs({ -1, 1 }) do
		local chx = cx + side * (bodyW / 2 - 90) - 18
		part(back, chx, roofTop - 30, 36, 70, Color3.fromRGB(236, 160, 170), { R = 4, Z = 3 })
		part(back, chx - 5, roofTop - 38, 46, 12, Color3.fromRGB(210, 126, 140), { R = 4, Z = 4 })
		part(back, chx + 6, roofTop - 50, 10, 14, Color3.fromRGB(226, 170, 150), { R = 3, Z = 3 })
	end
	smoke(ctx, back, cx + bodyW / 2 - 97, roofTop - 52, 2)

	-- Entrée à droite (cage d'escalier) derrière la façade
	local annexX = bodyX + bodyW - 8
	local annexW = 122
	local annexTop = cellTop + 60
	part(back, annexX, annexTop, annexW, groundY - annexTop, WALL:Lerp(C.Sky, 0.25), { R = 8, Z = 5, Th = 2.5 })
	part(back, annexX - 4, annexTop - 10, annexW + 12, 14, TRIM, { R = 4, Z = 6 })
	-- Garde-corps du toit du porche + plante
	part(back, annexX + 4, annexTop - 34, annexW - 4, 5, WHITE, { R = -1, Z = 5, Th = 1.5, Shade = false })
	for index = 0, 6 do
		box(back, annexX + 6 + index * (annexW - 12) / 6, annexTop - 32, 3, 24, WHITE, 0, 5)
	end
	pottedBall(back, annexX + annexW - 26, annexTop - 10, 0.7, C.Peach, 4)
	-- Fenêtre haute + jardinière
	local winX = annexX + annexW / 2 - 26
	window(ctx, back, winX, annexTop + 30, 52, 80, { Arch = true, Z = 7 })
	part(back, winX - 8, annexTop + 110, 68, 14, C.Pink, { R = 4, Z = 13 })
	for index, color in ipairs({ C.Butter, WHITE, C.Lilac }) do
		flower(back, winX + 6 + (index - 1) * 20, annexTop + 108, 12, color, 11)
	end
	-- Porte d'entrée cintrée, imposte, marquise rayée, marches
	local doorW, doorH = 60, 108
	local doorX = annexX + annexW / 2 - doorW / 2
	local doorTop = cellBottom - doorH
	window(ctx, back, doorX - 6, doorTop - 6, doorW + 12, doorH + 6, { Arch = true, Z = 7, Frame = TRIM, Cross = "none", Sill = false })
	local door = part(back, doorX + 3, doorTop + 32, doorW - 6, doorH - 34, C.PinkDeep:Lerp(C.Pink, 0.5), { R = 4, Z = 12, Th = 2 })
	for _, py in ipairs({ 8, 40 }) do
		part(door, 6, py, doorW - 18, 26, C.Pink, { R = 3, Z = 2, Th = 1.5, Shade = false })
	end
	circle(back, doorX + doorW - 14, doorTop + 76, 7, 7, P.Gold, 0, 13)
	heart(back, doorX + doorW / 2, doorTop + 18, 14, C.Heart, 0, 13)
	-- Marquise rayée
	local awY = doorTop - 40
	local awX = doorX - 24
	local awW = doorW + 48
	part(back, awX, awY, awW, 30, WHITE, { R = 5, Z = 14, Line = C.PinkDeep:Lerp(INK, 0.3) })
	for index = 0, 4 do
		box(back, awX + 5 + index * (awW - 10) / 5, awY + 2, (awW - 10) / 10, 26, C.Pink, 0, 15)
	end
	for index = 0, 4 do
		local sc = circle(back, awX + (index + 0.5) * awW / 5, awY + 30, awW / 5, 18, if index % 2 == 0 then C.Pink else WHITE, 0, 13)
		stroke(sc, C.PinkDeep:Lerp(INK, 0.3), 1.5)
	end
	-- Marches
	for step = 0, 2 do
		part(back, doorX - 14 - step * 10, cellBottom + step * 12, doorW + 28 + step * 20, 13, P.Stone, { R = 3, Z = 16 + step, Line = P.StoneDark:Lerp(INK, 0.3), Shade = 0.15 })
	end
	wallLantern(ctx, back, doorX + doorW + 12, doorTop + 20, 13)
	pottedBall(front, doorX - 40, groundY + 8, 1, C.Lilac, 20)
	pottedBall(front, doorX + doorW + 44, groundY + 8, 1, C.Lilac, 20)

	-- Façade menthe + chaînes d'angle crème
	part(back, bodyX, corniceY + 10, bodyW, groundY - corniceY - 10, WALL, { R = 8, Z = 8, Th = 2.5 })
	for _, x in ipairs({ bodyX + 3, bodyX + bodyW - M + 3 }) do
		local y = corniceY + 40
		local index = 0
		while y < groundY - 30 do
			local w = if index % 2 == 0 then M - 6 else M - 14
			box(back, if x < cx then x else x + (M - 6 - w), y, w, 16, WHITE, 0.35, 9)
			y += 22
			index += 1
		end
	end
	cellBacks(back, cells, P.Interior, 10)

	-- Toit mansardé en ardoises lilas + lucarnes + crête en fer forgé
	local baseW = bodyW + 20
	local topW = bodyW - 80
	trapezoid(back, cx, roofTop, topW, baseW, roofH, P.Slate, P.SlateDark, 20, 22)
	tileRows(back, cx, roofTop, topW, baseW, roofH, 3, 34, P.SlateDark, 0.45, 21)
	for _, side in ipairs({ -1, 1 }) do
		local rake = line(back, cx + side * (topW / 2), roofTop + 2, cx + side * (baseW / 2 - 2), corniceY, 12, P.SlateDark, 0, 22)
		stroke(rake, P.SlateDark:Lerp(INK, 0.35), 2)
	end
	part(back, cx - topW / 2 - 8, roofTop - 8, topW + 16, 12, P.SlateDark, { R = -1, Z = 23, Line = P.SlateDark:Lerp(INK, 0.35) })
	-- Crête : petits poteaux à boules
	local crestCount = math.floor(topW / 56)
	for index = 0, crestCount do
		local px = cx - topW / 2 + index * topW / crestCount
		box(back, px - 1.5, roofTop - 22, 3, 16, INK:Lerp(C.Lilac, 0.3), 0, 22)
		circle(back, px, roofTop - 24, 8, 8, P.Gold, 0, 22)
	end
	heart(back, cx, roofTop - 26, 22, C.Heart, 0, 24)
	-- Lucarnes (une par colonne)
	for column = 1, cols do
		local dx = colX[column] + cellW / 2
		local dw, dh = 70, 84
		local dy = roofTop + 34
		part(back, dx - dw / 2, dy, dw, dh, TRIM, { R = 6, Z = 24, Th = 2 })
		trapezoid(back, dx, dy - 30, 6, dw + 22, 34, C.Pink, C.PinkDeep:Lerp(C.Pink, 0.6), 25, 8)
		local rakeL = line(back, dx - 2, dy - 30, dx - dw / 2 - 12, dy + 4, 8, C.PinkDeep, 0, 26)
		local rakeR = line(back, dx + 2, dy - 30, dx + dw / 2 + 12, dy + 4, 8, C.PinkDeep, 0, 26)
		local _ = rakeL
		local __ = rakeR
		window(ctx, back, dx - 22, dy + 12, 44, 62, { Arch = true, Z = 27 })
	end

	-- Corniche (avant) + modillons
	part(front, bodyX - 14, corniceY, bodyW + 28, 20, TRIM, { R = 6, Z = 2, Th = 2.5 })
	box(front, bodyX - 8, corniceY + 13, bodyW + 16, 3, C.Pink, 0, 3)
	local modCount = math.floor(bodyW / 34)
	for index = 0, modCount do
		part(front, bodyX + 4 + index * (bodyW - 20) / modCount, corniceY + 20, 12, 12, TRIM, { R = 3, Z = 1, Th = 1.5, Shade = false })
	end
	part(front, bodyX + 6, corniceY + 32, bodyW - 12, 12, WALL_DARK, { R = 4, Z = 1, Line = false, Shade = false })

	-- Pilastres crème autour des pièces
	for index = 0, cols do
		local x = if index == 0 then bodyX + 8 elseif index == cols then bodyX + bodyW - M + 1 else colX[index] + cellW - 3
		local w = if index == 0 or index == cols then M - 9 + 3 else T + 6
		part(front, x, cellTop - 6, w, gridH + 10, TRIM, { R = 4, Z = 4, Th = 2 })
	end
	-- Dalles + balcons en fer forgé (étages supérieurs)
	for floorIndex = 2, floors do
		local y = floorY[floorIndex] + cellH
		part(front, bodyX + 2, y - 4, bodyW - 4, S + 8, TRIM, { R = 5, Z = 5, Th = 2.5 })
		box(front, bodyX + 8, y + S / 2 - 1, bodyW - 16, 3, C.Pink, 0, 6)
		for column = 1, cols do
			local rx = colX[column] - 4
			local rw = cellW + 8
			part(front, rx, y - 30, rw, 6, WHITE, { R = -1, Z = 8, Line = INK:Lerp(C.Lilac, 0.4), Th = 1.5, Shade = false })
			local bars = math.floor(rw / 18)
			for index = 1, bars - 1 do
				local bx = rx + index * rw / bars
				box(front, bx - 1.5, y - 26, 3, 24, WHITE, 0, 7)
			end
			for _, hx in ipairs({ rx + rw * 0.25, rx + rw * 0.75 }) do
				heart(front, hx, y - 14, 14, C.Pink, 0, 7)
			end
		end
	end
	-- Soubassement
	part(front, bodyX - 2, cellBottom - 5, bodyW + 4, groundY - cellBottom + 6, P.Stone, { R = 6, Z = 5, Line = P.StoneDark:Lerp(INK, 0.3) })
	box(front, bodyX + 6, cellBottom + 14, bodyW - 12, 2, P.StoneDark, 0.3, 6)

	-- Lampadaire + vélo (à gauche, sur le trottoir)
	postLantern(ctx, front, 100, groundY + 30, 250, 10)
	local bikeY = groundY + 38
	local bikeColor = C.Mint:Lerp(C.Sky, 0.3)
	for _, wx in ipairs({ 22, 86 }) do
		local wheel = circle(front, wx, bikeY - 20, 36, 36, WHITE, 1, 20)
		stroke(wheel, INK:Lerp(C.Lilac, 0.2), 4)
		circle(front, wx, bikeY - 20, 6, 6, INK:Lerp(C.Lilac, 0.2), 0, 21)
	end
	line(front, 22, bikeY - 20, 48, bikeY - 46, 5, bikeColor, 0, 22)
	line(front, 48, bikeY - 46, 78, bikeY - 46, 5, bikeColor, 0, 22)
	line(front, 48, bikeY - 20, 78, bikeY - 46, 5, bikeColor, 0, 22)
	line(front, 22, bikeY - 20, 48, bikeY - 20, 5, bikeColor, 0, 22)
	line(front, 86, bikeY - 20, 78, bikeY - 52, 5, bikeColor, 0, 22)
	part(front, 38, bikeY - 58, 20, 7, C.PinkDeep, { R = -1, Z = 23, Th = 1.5 })
	line(front, 70, bikeY - 56, 88, bikeY - 58, 4, INK:Lerp(C.Lilac, 0.2), 0, 23)
	part(front, 80, bikeY - 58, 30, 18, C.Wood, { R = 4, Z = 24, Th = 2 })
	for index, color in ipairs({ C.Pink, C.Butter, WHITE }) do
		flower(front, 84 + (index - 1) * 10, bikeY - 60, 10, color, 23)
	end

	fireflies(ctx, ctx.Fx, 20, groundY - 200, width - 40, 200, 6, 1)
	return { Width = width, Height = height, Cells = cells }
end

-- ░░ Loft : entrepôt de briques reconverti ░░
STYLES.Loft = function(ctx, size, cellW)
	local back, front = ctx.Back, ctx.Front
	local cellH = HouseExterior.CELL_H
	local ML, MR, T, S = 38, 112, 34, 46
	local left, right = 124, 64
	local cols, floors = size.Columns, size.Floors
	local bodyW = cols * cellW + (cols - 1) * T + ML + MR
	local bodyX = left
	local parapetY = 238
	local cellTop = parapetY + 80
	local gridH = floors * cellH + (floors - 1) * S
	local cellBottom = cellTop + gridH
	local groundY = cellBottom + 30
	local width = left + bodyW + right
	local height = groundY + 80
	local gaps = {}
	for index = 1, cols - 1 do
		gaps[index] = T
	end
	local cells, colX, floorY = makeGrid(size, cellW, bodyX + ML, cellTop, gaps, S)
	local bayX = bodyX + bodyW - MR

	-- Trottoir + bordure
	part(back, -4, groundY - 8, width + 8, 58, P.Pave, { R = 0, Z = 1, Line = false, Shade = 0.08 })
	for index = 0, math.floor(width / 80) do
		box(back, 40 + index * 80, groundY + 4, 3, 40, P.StoneDark, 0.4, 2)
	end
	part(back, -4, groundY + 48, width + 8, height - groundY - 48, P.StoneDark, { R = 0, Z = 2, Line = false, Shade = 0.25 })

	-- ░ Toit-terrasse (derrière le parapet) ░
	-- Château d'eau
	local wtX = bodyX + 170
	local legTop = parapetY - 88
	for _, dx in ipairs({ -40, -14, 14, 40 }) do
		line(back, wtX + dx * 0.8, legTop, wtX + dx * 1.05, parapetY + 4, 5, P.SteelDark, 0, 3)
	end
	line(back, wtX - 38, parapetY - 40, wtX + 38, parapetY - 40, 4, P.SteelDark, 0, 3)
	part(back, wtX - 56, legTop - 84, 112, 90, C.Wood, { R = 10, Z = 4, Th = 2.5, Shade = 0.18 })
	for _, by in ipairs({ 16, 44, 72 }) do
		box(back, wtX - 56, legTop - 84 + by, 112, 4, P.SteelDark, 0.2, 5)
	end
	heart(back, wtX, legTop - 50, 22, C.Pink, 0, 6)
	trapezoid(back, wtX, legTop - 128, 8, 132, 46, P.Slate, P.SlateDark, 5, 12)
	for _, side in ipairs({ -1, 1 }) do
		line(back, wtX + side * 4, legTop - 128, wtX + side * 68, legTop - 82, 8, P.SlateDark, 0, 6)
	end
	circle(back, wtX, legTop - 132, 10, 10, P.Gold, 0, 7)
	-- Guirlande lumineuse entre deux poteaux
	local p1, p2 = bodyX + 420, bodyX + bodyW - 250
	local poleTop = parapetY - 96
	for _, px in ipairs({ p1, p2 }) do
		part(back, px - 3, poleTop, 6, 100, P.SteelDark, { R = 2, Z = 3, Th = 1.5, Shade = false })
		circle(back, px, poleTop - 2, 9, 9, P.Gold, 0, 4)
	end
	local bulbs = {}
	local bulbColors = { C.Pink, C.Butter, C.Mint, C.Sky, C.Lilac }
	local segments = 16
	local prevX, prevY = p1, poleTop + 2
	for index = 1, segments do
		local k = index / segments
		local bx = p1 + (p2 - p1) * k
		local by = poleTop + 2 + math.sin(k * math.pi) * 44
		line(back, prevX, prevY, bx, by, 2, INK, 0.3, 3)
		prevX, prevY = bx, by
		if index < segments then
			local color = bulbColors[index % #bulbColors + 1]
			local bulb = circle(back, bx, by + 6, 10, 13, color, 0, 5)
			stroke(bulb, color:Lerp(INK, 0.5), 1.5)
			ctx.Lit[bulb] = color:Lerp(WHITE, 0.25)
			table.insert(bulbs, bulb)
		end
	end
	table.insert(ctx.Anims, function(clock, dark)
		for index, bulb in ipairs(bulbs) do
			local wave = 0.5 + 0.5 * math.sin(clock * 2.2 + index * 1.3)
			bulb.BackgroundTransparency = if dark then wave * 0.35 else 0.05 + wave * 0.15
		end
	end)
	-- Parasol + plantes qui dépassent du parapet
	local umX = bodyX + bodyW - 160
	part(back, umX - 2, parapetY - 78, 4, 80, WHITE, { R = 2, Z = 3, Th = 1.5, Shade = false })
	local canopy = group(back, umX - 58, parapetY - 112, 116, 36, 4, true)
	local dome = circle(canopy, 58, 40, 116, 76, C.Pink, 0, 1)
	stroke(dome, C.PinkDeep:Lerp(INK, 0.3), 2)
	for _, dx in ipairs({ -30, 0, 30 }) do
		box(canopy, 58 + dx - 7, 0, 14, 36, WHITE, 0, 2)
	end
	scallops(back, umX - 58, umX + 58, parapetY - 76, 29, 12, C.Pink, 0, 4)
	for index, bx in ipairs({ bodyX + 60, bodyX + 330, bodyX + 560, bodyX + 700, bodyX + 900 }) do
		bush(back, bx, parapetY + 12, 80 + (index % 2) * 20, 50 + (index % 3) * 8, P.Leaf, 6)
	end
	for index, fx in ipairs({ bodyX + 290, bodyX + 610, bodyX + 820 }) do
		line(back, fx, parapetY + 4, fx + 2, parapetY - 56, 4, P.LeafDark, 0, 5)
		circle(back, fx + 2, parapetY - 60, 30, 30, if index == 2 then C.Pink else C.Butter, 0, 6)
		circle(back, fx + 2, parapetY - 60, 13, 13, Color3.fromRGB(190, 120, 90), 0, 7)
	end

	-- ░ Façade de briques ░
	local wall = part(back, bodyX, parapetY + 6, bodyW, groundY - parapetY - 6, P.Brick, { R = 6, Z = 8, Th = 2.5, Shade = 0.12 })
	local _ = wall
	-- Quelques briques en relief (côtés, dalles, trumeaux)
	local spots = {}
	table.insert(spots, { bodyX + 8, cellTop + 20 })
	table.insert(spots, { bodyX + 6, cellTop + 120 })
	table.insert(spots, { bodyX + 10, cellBottom - 90 })
	for column = 1, cols - 1 do
		local x = colX[column] + cellW + 3
		table.insert(spots, { x, cellTop + 60 + column * 30 })
		table.insert(spots, { x, cellBottom - 60 - column * 20 })
	end
	for floorIndex = 2, floors do
		local y = floorY[floorIndex] + cellH + 12
		for index = 0, cols - 1 do
			table.insert(spots, { colX[index + 1] + 40 + index * 70, y })
			table.insert(spots, { colX[index + 1] + 250 - index * 30, y + 12 })
		end
	end
	for index, spot in ipairs(spots) do
		local bw = if spot[1] < bodyX + 20 or (index % 3 == 0) then 22 else 34
		part(back, spot[1], spot[2], bw, 11, if index % 2 == 0 then P.BrickLight else P.BrickDark, { R = 3, Z = 9, Line = false, Shade = false, T = 0.25 })
	end
	cellBacks(back, cells, Color3.fromRGB(226, 208, 226), 10)

	-- Travée de droite : porte métallique + grande fenêtre d'atelier
	local doorW, doorH = 62, 120
	local doorX = bayX + MR / 2 - doorW / 2 - 2
	local doorTop = cellBottom - doorH + 4
	part(back, doorX - 6, doorTop - 6, doorW + 12, doorH + 6, P.SteelDark, { R = 6, Z = 12, Th = 2 })
	part(back, doorX, doorTop, doorW, doorH - 2, P.Steel:Lerp(C.Mint, 0.35), { R = 4, Z = 13, Th = 2 })
	local doorWin = box(back, doorX + 12, doorTop + 14, doorW - 24, 34, P.Glass, 0, 14)
	round(doorWin, 4)
	lit(ctx, doorWin)
	circle(back, doorX + doorW - 12, doorTop + 70, 7, 7, P.Gold, 0, 14)
	part(back, doorX - 16, doorTop - 22, doorW + 32, 12, P.SteelDark, { R = 3, Z = 15, Th = 2 })
	line(back, doorX - 10, doorTop - 12, doorX + 2, doorTop + 2, 3, P.SteelDark, 0, 14)
	line(back, doorX + doorW + 10, doorTop - 12, doorX + doorW - 2, doorTop + 2, 3, P.SteelDark, 0, 14)
	wallLantern(ctx, back, doorX - 30, doorTop + 30, 14)
	local upperY = floorY[floors]
	local fw, fh = 70, 130
	local fx = bayX + MR / 2 - fw / 2 - 2
	part(back, fx - 5, upperY + 20, fw + 10, fh + 10, P.SteelDark, { R = 5, Z = 12, Th = 2 })
	for row = 0, 2 do
		for column = 0, 1 do
			local pane = box(back, fx + 3 + column * (fw / 2 - 1), upperY + 28 + row * (fh / 3), fw / 2 - 5, fh / 3 - 6, P.Glass, 0, 13)
			round(pane, 2)
			lit(ctx, pane)
		end
	end
	round(box(back, fx + 8, upperY + 34, 8, 20, WHITE, 0.45, 14))

	-- Enseigne néon verticale (à gauche)
	local signX, signY, signW, signH = 26, cellTop + 20, 74, 214
	for _, by in ipairs({ signY + 30, signY + signH - 30 }) do
		part(back, signX + signW - 6, by - 4, bodyX - signX - signW + 16, 8, P.SteelDark, { R = 2, Z = 11, Th = 1.5, Shade = false })
	end
	glow(ctx, back, signX + signW / 2, signY + signH / 2, 250, C.Pink, 12)
	local board = part(back, signX, signY, signW, signH, Color3.fromRGB(86, 64, 120), { R = 16, Z = 15, Line = INK, Th = 3, Shade = false })
	local neonA = Color3.fromRGB(255, 150, 206)
	local neonB = Color3.fromRGB(150, 236, 255)
	local tubes = {}
	local hb = heart(board, signW / 2, 30, 30, neonA, 0, 2)
	table.insert(tubes, hb)
	local letters = {}
	for index, letter in ipairs({ "L", "O", "F", "T" }) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(signW / 2, 64 + (index - 1) * 38)
		label.Size = UDim2.fromOffset(signW, 36)
		label.Font = FONT
		label.Text = letter
		label.TextSize = 34
		label.TextColor3 = neonB
		label.ZIndex = 3
		label.Parent = board
		table.insert(letters, label)
	end
	table.insert(ctx.Anims, function(clock, dark)
		local flick = dark and (math.sin(clock * 23) > 0.93 or (clock % 5) < 0.12)
		for index, label in ipairs(letters) do
			local on = if dark then not (flick and index == 3) else true
			label.TextColor3 = if on then (if dark then Color3.fromRGB(190, 250, 255) else neonB) else Color3.fromRGB(110, 100, 150)
		end
		for _, child in ipairs(hb:GetChildren()) do
			if child:IsA("Frame") then
				child.BackgroundColor3 = if dark then Color3.fromRGB(255, 176, 220) else neonA
			end
		end
	end)
	local _ = tubes

	-- ░ Parapet (avant du toit) ░
	part(back, bodyX - 6, parapetY - 6, bodyW + 12, 16, C.Cream, { R = 5, Z = 20, Th = 2.5 })
	for index = 0, math.floor(bodyW / 60) - 1 do
		part(back, bodyX + 16 + index * 60, parapetY + 18, 30, 10, P.BrickDark, { R = 3, Z = 21, Line = false, Shade = false, T = 0.3 })
	end
	box(back, bodyX + 4, parapetY + 36, bodyW - 8, 4, P.BrickDark, 0.35, 21)

	-- ░ Avant : cadres d'usine en acier + impostes vitrées, poutres rivetées ░
	for _, r in pairs(cells) do
		local frame = box(front, r.X - 3, r.Y - 3, r.W + 6, r.H + 6, WHITE, 1, 3)
		round(frame, 5)
		stroke(frame, P.SteelDark, 6)
		-- Imposte : rangée de petits carreaux au-dessus de la pièce (allumés la nuit)
		local sx, sw = r.X + 6, r.W - 12
		local sy, sh = r.Y - 36, 24
		part(front, sx, sy, sw, sh, P.SteelDark, { R = 3, Z = 4, Th = 1.5, Shade = false })
		local n = 6
		local pw = (sw - 4 * (n + 1)) / n
		for index = 0, n - 1 do
			local pane = box(front, sx + 4 + index * (pw + 4), sy + 4, pw, sh - 8, P.Glass, 0, 5)
			round(pane, 2)
			grad(pane, WHITE, Color3.fromRGB(226, 220, 246), 90)
			lit(ctx, pane)
		end
	end
	for floorIndex = 2, floors do
		local y = floorY[floorIndex] + cellH
		part(front, bodyX + 4, y + 1, bodyW - 8, 10, P.SteelDark, { R = 3, Z = 2, Th = 2 })
		for index = 0, math.floor(bodyW / 40) do
			circle(front, bodyX + 16 + index * 40, y + 6, 4, 4, P.Gold, 0, 3)
		end
	end
	-- Seuil en béton
	part(front, bodyX - 4, cellBottom + 2, bodyW + 8, groundY - cellBottom, Color3.fromRGB(226, 216, 232), { R = 4, Z = 2, Line = P.StoneDark:Lerp(INK, 0.3) })

	-- ░ Escalier de secours (devant la travée de droite) ░
	local steel = P.SteelDark
	local landingY = floorY[floors] + cellH
	local fx1, fx2 = bayX - 20, bodyX + bodyW + 40
	part(front, fx1, landingY - 4, fx2 - fx1, 9, steel, { R = 2, Z = 10, Th = 1.5, Shade = false })
	part(front, fx1, landingY - 60, fx2 - fx1, 5, steel, { R = 2, Z = 10, Th = 1.5, Shade = false })
	for index = 0, 6 do
		box(front, fx1 + 2 + index * (fx2 - fx1 - 4) / 6, landingY - 58, 3, 56, steel, 0, 10)
	end
	-- Volée vers le toit
	local sx1, sy1 = fx1 + 18, landingY - 6
	local sx2, sy2 = fx2 - 14, parapetY + 4
	line(front, sx1, sy1, sx2, sy2, 6, steel, 0, 11)
	line(front, sx1 + 22, sy1 - 6, sx2 + 12, sy2 - 20, 4, steel, 0, 11)
	for index = 1, 9 do
		local k = index / 10
		local tx = sx1 + (sx2 - sx1) * k
		local ty = sy1 + (sy2 - sy1) * k
		box(front, tx - 10, ty - 2, 20, 4, steel, 0, 11)
	end
	part(front, fx2 - 44, parapetY - 2, 60, 7, steel, { R = 2, Z = 11, Th = 1.5, Shade = false })
	-- Échelle repliée sous le palier
	local lx = fx2 - 30
	box(front, lx - 12, landingY + 4, 4, 130, steel, 0, 10)
	box(front, lx + 8, landingY + 4, 4, 130, steel, 0, 10)
	for index = 0, 6 do
		box(front, lx - 12, landingY + 14 + index * 18, 24, 3, steel, 0, 10)
	end

	-- ░ Trottoir : caisses fleuries, banc, grandes plantes ░
	for index, crate in ipairs({ { 20, groundY + 26, 54, 40 }, { 66, groundY + 26, 48, 34 }, { 36, groundY - 14, 44, 34 } }) do
		local c = part(front, crate[1], crate[2] - crate[4], crate[3], crate[4], C.Wood, { R = 4, Z = 14 + (if index == 3 then 2 else 0), Th = 2 })
		box(c, 4, crate[4] / 2 - 2, crate[3] - 8, 4, C.WoodDark, 0.4, 2)
	end
	bush(front, 58, groundY - 44, 50, 34, P.Leaf, 17)
	flower(front, 46, groundY - 60, 12, C.Pink, 20)
	flower(front, 70, groundY - 56, 12, C.Butter, 20)
	local benchX = colX[1] + cellW + T / 2 - 60
	part(front, benchX, groundY + 6, 120, 12, C.Pink, { R = 4, Z = 14, Th = 2 })
	part(front, benchX, groundY - 20, 120, 12, C.Pink, { R = 4, Z = 14, Th = 2 })
	for _, lx2 in ipairs({ benchX + 12, benchX + 100 }) do
		box(front, lx2, groundY + 16, 8, 20, P.SteelDark, 0, 13)
	end
	for index, px in ipairs({ colX[2] + cellW + T / 2, bayX - 50 }) do
		pottedBall(front, px, groundY + 38, 1.25, if index == 1 then C.Peach else C.Lilac, 14)
	end

	fireflies(ctx, ctx.Fx, 40, parapetY - 140, width - 80, 150, 7, 1)
	return { Width = width, Height = height, Cells = cells }
end

-- ░░ Mansion : le grand manoir kawaii ░░
STYLES.Mansion = function(ctx, size, cellW)
	local back, front = ctx.Back, ctx.Front
	local cellH = HouseExterior.CELL_H
	local cols, floors = size.Columns, size.Floors
	local M, T, BAY, S = 34, 24, 100, 36
	local towerW = 200
	local towerOut = 170 -- partie de la tour qui dépasse du corps
	local margin = 64
	local gaps = {}
	for index = 1, cols - 1 do
		gaps[index] = if index == math.floor(cols / 2) then BAY else T
	end
	local gridW = cols * cellW
	for _, g in ipairs(gaps) do
		gridW += g
	end
	local bodyW = gridW + M * 2
	local bodyX = margin + towerOut
	local cx = bodyX + bodyW / 2
	local roofTop = 196
	local roofH = 150
	local corniceY = roofTop + roofH - 6
	local cellTop = corniceY + 48
	local gridH = floors * cellH + (floors - 1) * S
	local cellBottom = cellTop + gridH
	local plinthH = 78
	local groundY = cellBottom + plinthH
	local width = bodyX + bodyW + towerOut + margin
	local height = groundY + 262
	local cells, colX, floorY = makeGrid(size, cellW, bodyX + M, cellTop, gaps, S)
	local bayX = colX[math.floor(cols / 2)] + cellW
	local bayCx = bayX + BAY / 2

	local WALL = Color3.fromRGB(255, 232, 242)
	local WALL_SHADE = Color3.fromRGB(246, 208, 228)
	local TRIM = Color3.fromRGB(255, 250, 244)
	local TOWER = Color3.fromRGB(255, 218, 234)
	local ROOF = P.Slate
	local ROOF_DARK = P.SlateDark

	-- ░ Jardin (fond) : pelouse, allée ░
	part(back, 10, groundY - 20, width - 20, height - groundY + 14, P.Grass, { R = 30, Z = 1, Line = P.GrassDark, Shade = 0.14 })
	local path = group(back, 0, 0, width, height, 2)
	local pathSlices = 8
	for index = 0, pathSlices - 1 do
		local k = index / pathSlices
		local w = 150 + k * 170
		local y = groundY + 2 + index * (height - groundY - 10) / pathSlices
		box(path, bayCx - w / 2, y, w, (height - groundY - 10) / pathSlices + 1, Color3.fromRGB(250, 236, 222), 0, 1)
	end

	-- ░ Toit principal mansardé (ardoises lilas) ░
	local roofBase = bodyW + 30
	local roofTopW = bodyW - 190
	-- Cheminées
	for _, side in ipairs({ -1, 1 }) do
		local chx = cx + side * (roofTopW / 2 - 70) - 20
		part(back, chx, roofTop - 50, 40, 80, Color3.fromRGB(246, 180, 196), { R = 4, Z = 3 })
		part(back, chx - 6, roofTop - 58, 52, 13, Color3.fromRGB(220, 140, 166), { R = 4, Z = 4 })
		if side > 0 then
			smoke(ctx, back, chx + 20, roofTop - 62, 2)
		end
	end
	trapezoid(back, cx, roofTop, roofTopW, roofBase, roofH, ROOF, ROOF_DARK, 5, 22)
	-- Tuiles (hors fronton)
	for row = 1, 3 do
		local y = roofH * row / 4
		local w = roofTopW + (roofBase - roofTopW) * (y / roofH) - 30
		local tile = 40
		scallops(back, cx - w / 2, cx - 300, roofTop + y, tile, 18, ROOF_DARK, 0.45, 6, (row % 2) * tile / 2)
		scallops(back, cx + 300, cx + w / 2, roofTop + y, tile, 18, ROOF_DARK, 0.45, 6, (row % 2) * tile / 2)
	end
	part(back, cx - roofTopW / 2 - 10, roofTop - 10, roofTopW + 20, 14, ROOF_DARK, { R = -1, Z = 8, Line = ROOF_DARK:Lerp(INK, 0.35) })
	-- Crête dorée
	local crestCount = math.floor(roofTopW / 96)
	for index = 0, crestCount do
		local px = cx - roofTopW / 2 + index * roofTopW / crestCount
		box(back, px - 1.5, roofTop - 24, 3, 16, P.Gold:Lerp(INK, 0.2), 0, 7)
		circle(back, px, roofTop - 26, 9, 9, P.Gold, 0, 7)
	end
	-- Lucarnes (colonnes extérieures)
	for _, column in ipairs({ 1, cols }) do
		local dx = colX[column] + cellW / 2
		local dw, dh = 84, 96
		local dy = roofTop + 30
		part(back, dx - dw / 2, dy, dw, dh + 20, TRIM, { R = 8, Z = 9, Th = 2.5 })
		trapezoid(back, dx, dy - 38, 8, dw + 26, 42, C.Pink, C.PinkDeep:Lerp(C.Pink, 0.55), 10, 9)
		line(back, dx - 2, dy - 38, dx - dw / 2 - 14, dy + 4, 9, C.PinkDeep, 0, 11)
		line(back, dx + 2, dy - 38, dx + dw / 2 + 14, dy + 4, 9, C.PinkDeep, 0, 11)
		circle(back, dx, dy - 42, 10, 10, P.Gold, 0, 12)
		window(ctx, back, dx - 26, dy + 14, 52, 76, { Arch = true, Z = 12 })
	end
	-- Petits œils-de-bœuf
	for _, column in ipairs({ 2, cols - 1 }) do
		local ox = if column == 2 then colX[column] + 70 else colX[column] + cellW - 70
		window(ctx, back, ox - 20, roofTop + 70, 40, 40, { Round = true, Z = 9, Frame = TRIM })
	end

	-- ░ Fronton central + horloge-cœur ░
	local pedW = 560
	local pedH = 190
	local pedTop = corniceY - pedH + 4
	trapezoid(back, cx, pedTop, 20, pedW, pedH, TRIM, WALL_SHADE, 13, 24)
	trapezoid(back, cx, pedTop + 34, 10, pedW - 110, pedH - 52, WALL, WALL:Lerp(C.Pink, 0.25), 14, 18)
	for _, side in ipairs({ -1, 1 }) do
		local rake = line(back, cx + side * 6, pedTop + 2, cx + side * (pedW / 2 + 6), corniceY + 2, 18, TRIM, 0, 15)
		stroke(rake, TRIM:Lerp(INK, 0.45), 2.5)
		shade(rake, 0.08)
	end
	heart(back, cx, pedTop - 12, 34, C.Heart, 0, 16)
	-- Horloge : cœur rose, cadran crème, aiguilles qui tournent
	local clockY = pedTop + pedH * 0.6
	local ch = heart(back, cx, clockY, 112, C.PinkDeep:Lerp(INK, 0.25), 0, 16)
	local _ = ch
	heart(back, cx, clockY, 102, C.Pink, 0, 17)
	local face = circle(back, cx, clockY + 2, 62, 62, C.Cream, 0, 18)
	stroke(face, P.Gold, 3)
	lit(ctx, face, LIT_SOFT)
	for index = 0, 3 do
		local a = index * math.pi / 2
		circle(back, cx + math.sin(a) * 23, clockY + 2 - math.cos(a) * 23, 6, 6, C.PinkDeep, 0, 19)
	end
	local hourPivot = group(back, cx, clockY + 2, 0, 0, 20)
	local minutePivot = group(back, cx, clockY + 2, 0, 0, 20)
	round(box(hourPivot, -2.5, -15, 5, 17, INK, 0, 1))
	round(box(minutePivot, -1.5, -23, 3, 25, INK, 0, 1))
	circle(back, cx, clockY + 2, 8, 8, P.Gold, 0, 21)
	table.insert(ctx.Anims, function(clock)
		minutePivot.Rotation = (clock * 36) % 360
		hourPivot.Rotation = (clock * 3 + 300) % 360
	end)

	-- ░ Corps du manoir ░
	part(back, bodyX, corniceY + 10, bodyW, groundY - corniceY - 10, WALL, { R = 8, Z = 22, Th = 2.5, Shade = 0.08 })
	cellBacks(back, cells, Color3.fromRGB(236, 210, 232), 23)
	-- Travée centrale : porte d'honneur, fenêtre à balcon, œil-de-bœuf
	local doorW, doorH = 78, 150
	local doorX = bayCx - doorW / 2
	local doorTop = cellBottom - doorH
	window(ctx, back, doorX - 8, doorTop - 8, doorW + 16, doorH + 8, { Arch = true, Z = 26, Frame = TRIM, Cross = "none", Sill = false, Border = 8 })
	for _, side in ipairs({ -1, 1 }) do
		local leaf = part(back, bayCx + (if side < 0 then -doorW / 2 + 2 else 1), doorTop + 40, doorW / 2 - 3, doorH - 40, C.PinkDeep:Lerp(C.Pink, 0.45), { R = 4, Z = 31, Th = 2 })
		part(leaf, 6, 10, doorW / 2 - 15, 40, C.Pink, { R = 4, Z = 2, Th = 1.5, Shade = false })
		part(leaf, 6, 60, doorW / 2 - 15, 40, C.Pink, { R = 4, Z = 2, Th = 1.5, Shade = false })
		circle(back, bayCx + side * 7, doorTop + 96, 7, 7, P.Gold, 0, 32)
	end
	heart(back, bayCx, doorTop + 24, 22, C.Heart, 0, 32)
	if floors >= 2 then
		local wy = floorY[2] + 34
		window(ctx, back, bayCx - 30, wy, 60, 120, { Arch = true, Z = 26, Frame = TRIM })
	end
	if floors >= 3 then
		window(ctx, back, bayCx - 30, floorY[floors] + 50, 60, 60, { Round = true, Z = 26, Frame = TRIM, Border = 7 })
		heart(back, bayCx, floorY[floors] + 136, 24, C.Pink, 0, 26)
	end

	-- ░ Tours rondes (devant les côtés du corps) ░
	local towerTop = roofTop + 100
	local coneH = 240
	for index, side in ipairs({ -1, 1 }) do
		local tx = if side < 0 then bodyX - towerOut else bodyX + bodyW + towerOut - towerW
		local tcx = tx + towerW / 2
		local bodyTop = towerTop
		local tower = part(back, tx, bodyTop, towerW, groundY - bodyTop, TOWER, { R = 14, Z = 40, Th = 2.5, Shade = false })
		-- Volume cylindrique : clair au centre, plus sombre sur les bords
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(222, 200, 222)),
			ColorSequenceKeypoint.new(0.4, WHITE),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 190, 216)),
		})
		g.Rotation = 0
		g.Parent = tower
		-- Bandeaux de pierre aux étages
		for floorIndex = 1, floors do
			local by = floorY[floorIndex] + cellH + S / 2 - 7
			part(back, tx - 6, by, towerW + 12, 14, TRIM, { R = 5, Z = 41, Th = 2 })
		end
		-- Fenêtres cintrées (une par étage) + œil-de-bœuf en haut
		for floorIndex = 1, floors do
			window(ctx, back, tcx - 30, floorY[floorIndex] + 36, 60, 106, { Arch = true, Z = 42, Frame = TRIM })
		end
		window(ctx, back, tcx - 22, bodyTop + 22, 44, 44, { Round = true, Z = 42, Frame = TRIM })
		-- Couronnement : corniche + festons
		part(back, tx - 14, bodyTop - 16, towerW + 28, 22, TRIM, { R = 8, Z = 47, Th = 2.5 })
		scallops(back, tx - 8, tx + towerW + 8, bodyTop + 8, 26, 14, C.Pink, 0, 46)
		-- Toit conique + tuiles + rives + drapeau
		local coneBase = towerW + 44
		trapezoid(back, tcx, bodyTop - 16 - coneH, 6, coneBase, coneH, ROOF, ROOF_DARK, 48, 26)
		tileRows(back, tcx, bodyTop - 16 - coneH, 6, coneBase, coneH, 4, 36, ROOF_DARK, 0.45, 49)
		for _, s2 in ipairs({ -1, 1 }) do
			local rake = line(back, tcx + s2 * 2, bodyTop - 14 - coneH, tcx + s2 * (coneBase / 2 + 2), bodyTop - 12, 12, ROOF_DARK, 0, 50)
			stroke(rake, ROOF_DARK:Lerp(INK, 0.35), 2)
		end
		part(back, tcx - coneBase / 2 - 4, bodyTop - 24, coneBase + 8, 14, ROOF_DARK, { R = -1, Z = 51, Line = ROOF_DARK:Lerp(INK, 0.35) })
		circle(back, tcx, bodyTop - 18 - coneH, 14, 14, P.Gold, 0, 51)
		flag(ctx, back, tcx, bodyTop - 22 - coneH, 62, if index == 1 then C.Pink else C.Lilac, 52, index * 1.7)
	end

	-- ░ Avant : corniche, colonnes, balustrades ░
	part(front, bodyX - 18, corniceY, bodyW + 36, 24, TRIM, { R = 6, Z = 2, Th = 2.5 })
	box(front, bodyX - 10, corniceY + 16, bodyW + 20, 3, P.Gold, 0, 3)
	local modCount = math.floor(bodyW / 62)
	for index = 0, modCount do
		part(front, bodyX + 2 + index * (bodyW - 16) / modCount, corniceY + 24, 12, 13, TRIM, { R = 3, Z = 1, Th = 1.5, Shade = false })
	end
	part(front, bodyX + 6, corniceY + 37, bodyW - 12, 11, WALL_SHADE, { R = 4, Z = 1, Line = false, Shade = false })

	-- Colonnes (murs intérieurs) et pilastres (bords, travée centrale)
	local function column(x: number, w: number, top: number, h: number)
		local shaft = part(front, x + 3, top + 12, w - 6, h - 24, TRIM, { R = 4, Z = 6, Th = 2, Shade = false })
		-- Fût arrondi : plus sombre sur les bords
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(236, 222, 236)),
			ColorSequenceKeypoint.new(0.45, WHITE),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(228, 212, 230)),
		})
		g.Parent = shaft
		part(front, x - 2, top, w + 4, 14, TRIM, { R = 4, Z = 7, Th = 2 })
		part(front, x - 2, top + h - 14, w + 4, 14, TRIM, { R = 4, Z = 7, Th = 2 })
	end
	for floorIndex = 1, floors do
		local top = floorY[floorIndex] - 4
		local h = cellH + 8
		column(bodyX + 6, M - 3, top, h)
		column(bodyX + bodyW - M - 3, M - 3, top, h)
		for c = 1, cols - 1 do
			local gx = colX[c] + cellW
			local gw = gaps[c]
			if gw == BAY then
				column(gx - 3, 26, top, h)
				column(gx + gw - 23, 26, top, h)
			else
				column(gx - 3, gw + 6, top, h)
			end
		end
	end
	-- Dalles entre étages : bandeau + balustrade (garde-corps bas)
	for floorIndex = 2, floors do
		local y = floorY[floorIndex] + cellH
		part(front, bodyX - 4, y + S - 16, bodyW + 8, 18, TRIM, { R = 5, Z = 8, Th = 2.5 })
		box(front, bodyX + 4, y + S - 9, bodyW - 8, 3, P.Gold, 0, 9)
		for c = 1, cols do
			local rx = colX[c] - 2
			local rw = cellW + 4
			part(front, rx, y - 14, rw, 8, TRIM, { R = -1, Z = 11, Th = 2 })
			local count = math.floor(rw / 31)
			for index = 1, count - 1 do
				local bx = rx + index * rw / count
				part(front, bx - 4.5, y - 8, 9, S - 6, TRIM, { R = -1, Z = 10, Th = 1.5, Shade = 0.15 })
			end
		end
		-- Petit balcon arrondi de la travée centrale
		part(front, bayCx - BAY / 2 - 6, y - 12, BAY + 12, 10, TRIM, { R = -1, Z = 12, Th = 2 })
	end
	-- Soubassement (bossages) + perron
	part(front, bodyX - 4, cellBottom - 6, bodyW + 8, plinthH + 6, P.Stone, { R = 6, Z = 8, Line = P.StoneDark:Lerp(INK, 0.3) })
	part(front, bodyX - 8, cellBottom - 8, bodyW + 16, 12, TRIM, { R = -1, Z = 9, Th = 2 })
	for row = 0, 1 do
		local y = cellBottom + 20 + row * 26
		box(front, bodyX + 4, y, bodyW - 8, 2, P.StoneDark, 0.2, 9)
		local count = math.floor(bodyW / 130)
		for index = 0, count do
			box(front, bodyX + 40 + index * 130 + (row % 2) * 65, y + 2, 2, 24, P.StoneDark, 0.3, 9)
		end
	end

	-- ░ Grand escalier double (deux volées qui descendent du perron) ░
	local landW = 176
	local landY = cellBottom
	part(front, bayCx - landW / 2, landY - 4, landW, 18, TRIM, { R = 4, Z = 20, Th = 2.5 })
	box(front, bayCx - landW / 2 + 6, landY + 6, landW - 12, 3, P.Gold, 0, 21)
	local steps = 6
	local run = 30
	local rise = (groundY - landY + 6) / steps
	local flightEnd = landW / 2 + steps * run
	for _, side in ipairs({ -1, 1 }) do
		local startX = bayCx + side * landW / 2
		for step = 1, steps do
			local sx = startX + side * (step - 1) * run
			local sy = landY + 12 + (step - 1) * rise
			local w = run + 18
			part(front, if side < 0 then sx - w else sx, sy, w, rise + 5, P.Stone, { R = 4, Z = 18 + step, Line = P.StoneDark:Lerp(INK, 0.3), Shade = 0.22 })
		end
		-- Rampe à balustres
		local x1, y1 = startX, landY - 2
		local x2, y2 = bayCx + side * (flightEnd + 6), groundY + 2
		for k = 1, 5 do
			local t = k / 6
			local bx = x1 + (x2 - x1) * t
			local by = y1 + (y2 - y1) * t
			part(front, bx - 5, by - 28, 10, 26, TRIM, { R = -1, Z = 29, Th = 1.5, Shade = 0.15 })
		end
		local rail = line(front, x1, y1 - 30, x2, y2 - 36, 10, TRIM, 0, 30)
		stroke(rail, TRIM:Lerp(INK, 0.45), 2)
		-- Piliers (haut et bas de la rampe) + lanternes
		part(front, x1 - 11, y1 - 42, 22, 46, TRIM, { R = 5, Z = 31, Th = 2.5 })
		part(front, x2 - 14, y2 - 48, 28, 58, TRIM, { R = 5, Z = 31, Th = 2.5 })
		postLantern(ctx, front, x2, y2 - 46, 16, 32)
		circle(front, x1, y1 - 46, 14, 14, P.Gold, 0, 32)
	end

	-- ░ Jardin : haies, topiaires, parterres, fontaine, grille ░
	local hedgeY = groundY + 8
	for _, side in ipairs({ -1, 1 }) do
		local x1 = if side < 0 then bodyX - towerOut + 14 else bayCx + flightEnd + 40
		local x2 = if side < 0 then bayCx - flightEnd - 40 else bodyX + bodyW + towerOut - 14
		part(front, x1, hedgeY - 38, x2 - x1, 46, P.Leaf, { R = 18, Z = 14, Line = P.LeafDark:Lerp(INK, 0.3), Shade = 0.22 })
		local bumps = math.floor((x2 - x1) / 70)
		for index = 0, bumps - 1 do
			circle(front, x1 + 34 + index * (x2 - x1 - 68) / math.max(1, bumps - 1), hedgeY - 36, 58, 24, P.Leaf, 0, 15)
		end
		for index = 0, 6 do
			local fx = x1 + 30 + index * (x2 - x1 - 60) / 6
			flower(front, fx, hedgeY - 14 + (index % 2) * 10, 13, if index % 2 == 0 then C.Pink else WHITE, 16)
		end
		-- Topiaire à étages (près de la tour)
		local tcx = if side < 0 then bodyX - towerOut / 2 + 10 else bodyX + bodyW + towerOut / 2 - 10
		local tb = groundY + 104
		part(front, tcx - 20, tb - 30, 40, 30, C.Pink, { R = 6, Z = 22, Th = 2 })
		part(front, tcx - 24, tb - 34, 48, 9, C.Pink:Lerp(WHITE, 0.3), { R = 3, Z = 23, Th = 2, Shade = false })
		box(front, tcx - 3, tb - 150, 6, 120, P.Trunk, 0, 17)
		for k = 0, 2 do
			blob(front, tcx, tb - 56 - k * 38, 70 - k * 18, 44 - k * 9, P.Leaf, { Z = 18 + k, Line = P.LeafDark:Lerp(INK, 0.3), Shade = 0.18 })
		end
		heart(front, tcx, tb - 150, 20, C.Heart, 0, 21)
		-- Parterre rond fleuri
		local bx, by = bayCx + side * 360, groundY + 150
		blob(front, bx, by, 190, 58, P.LeafDark:Lerp(P.Leaf, 0.4), { Z = 24, Line = P.LeafDark:Lerp(INK, 0.3), Shade = 0.2 })
		for index = 0, 6 do
			local a = index / 7 * math.pi * 2
			flower(front, bx + math.cos(a) * 62, by + math.sin(a) * 15, 17, ({ C.Pink, C.Butter, WHITE, C.Lilac })[index % 4 + 1], 25)
		end
		flower(front, bx, by - 2, 20, C.Heart, 25)
		-- Petit topiaire boule dans un pot près de l'escalier
		pottedBall(front, bayCx + side * (flightEnd + 70), groundY + 44, 1.2, C.Lilac, 26)
	end
	-- Fontaine à deux vasques (jets d'eau animés)
	local fy = groundY + 138
	blob(front, bayCx, fy, 300, 64, P.Stone, { Z = 34, Line = P.StoneDark:Lerp(INK, 0.3), Shade = 0.25 })
	local water = circle(front, bayCx, fy - 6, 260, 38, P.Water, 0, 35)
	shade(water, 0.2)
	round(box(front, bayCx - 90, fy - 16, 50, 5, WHITE, 0.4, 36))
	part(front, bayCx - 13, fy - 84, 26, 80, TRIM, { R = 5, Z = 36, Th = 2 })
	blob(front, bayCx, fy - 84, 130, 26, TRIM, { Z = 37, Th = 2 })
	circle(front, bayCx, fy - 89, 108, 12, P.Water, 0, 38)
	part(front, bayCx - 7, fy - 126, 14, 40, TRIM, { R = 4, Z = 37, Th = 1.5 })
	blob(front, bayCx, fy - 126, 60, 16, TRIM, { Z = 38, Th = 2 })
	heart(front, bayCx, fy - 140, 22, C.Pink, 0, 39)
	local drops = {}
	for index = 1, 12 do
		local drop = circle(front, bayCx, fy - 100, 7, 9, P.Water:Lerp(WHITE, 0.35), 0.1, 40)
		stroke(drop, P.Water:Lerp(INK, 0.35), 1)
		table.insert(drops, { Frame = drop, Side = if index % 2 == 0 then 1 else -1, Phase = (index - 1) / 12, High = index % 4 < 2 })
	end
	table.insert(ctx.Anims, function(clock)
		for _, drop in ipairs(drops) do
			local t = (clock * 0.6 + drop.Phase) % 1
			local reach = if drop.High then 44 else 90
			local lift = if drop.High then 30 else 16
			local baseY = if drop.High then fy - 128 else fy - 90
			local fall = if drop.High then 38 else 72
			local dx = drop.Side * (10 + t * reach)
			local dy = -math.sin(t * math.pi) * lift + t * t * fall
			drop.Frame.Position = UDim2.fromOffset(bayCx + dx - 3.5, baseY + dy - 4.5)
			drop.Frame.BackgroundTransparency = 0.05 + t * 0.55
		end
	end)
	-- Grille en fer forgé (premier plan) + piliers à lanternes
	local fenceTop = height - 64
	local gateGap = 330
	local iron = INK:Lerp(C.Lilac, 0.25)
	for _, side in ipairs({ -1, 1 }) do
		local x1 = if side < 0 then 24 else bayCx + gateGap / 2 + 18
		local x2 = if side < 0 then bayCx - gateGap / 2 - 18 else width - 24
		part(front, x1, fenceTop + 12, x2 - x1, 5, iron, { R = 2, Z = 40, Line = false, Shade = false })
		part(front, x1, fenceTop + 42, x2 - x1, 5, iron, { R = 2, Z = 40, Line = false, Shade = false })
		local count = math.floor((x2 - x1) / 30)
		for index = 0, count do
			local bx = x1 + index * (x2 - x1) / count
			local bar = box(front, bx - 2, fenceTop - 4, 4, 58, iron, 0, 41)
			round(bar, 2)
			if index % 3 == 1 then
				heart(front, bx, fenceTop + 28, 12, P.Gold, 0, 42)
			end
		end
		-- Pilier du portail + lanterne
		local px = bayCx + side * (gateGap / 2 + 2)
		part(front, px - 18, fenceTop - 24, 36, 84, P.Stone, { R = 5, Z = 43, Line = P.StoneDark:Lerp(INK, 0.3) })
		part(front, px - 22, fenceTop - 30, 44, 11, TRIM, { R = 4, Z = 44, Th = 2 })
		postLantern(ctx, front, px, fenceTop - 30, 12, 45)
		-- Battant ouvert (vu de biais)
		local gx = bayCx + side * (gateGap / 2 - 26)
		local leaf = part(front, gx - 16, fenceTop, 32, 54, WHITE, { R = 8, Z = 42, Line = iron, Th = 3, T = 1, Shade = false })
		box(leaf, 14.5, 4, 3, 46, iron, 0, 1)
		heart(front, gx, fenceTop + 18, 14, P.Gold, 0, 43)
	end

	fireflies(ctx, ctx.Fx, 60, groundY - 30, width - 120, 250, 10, 1)
	return { Width = width, Height = height, Cells = cells }
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local STYLE_BY_SIZE = { Studio = "Cottage", Apartment = "Townhouse", Loft = "Loft", Mansion = "Mansion" }

local function layer(parent: Instance, name: string, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

function HouseExterior.Build(parent: Instance, size: SizeDef): Exterior
	local root = Instance.new("Frame")
	root.Name = "HouseExterior"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	-- La façade gère elle-même son mode nuit
	root:SetAttribute("DarkSkinIgnore", true)

	local ctx: Ctx = {
		Back = layer(root, "Back", 1),
		Front = nil :: any,
		Fx = nil :: any,
		Lit = {},
		Glows = {},
		Anims = {},
		NightOnly = {},
		DayOnly = {},
	}
	local cellLayer = layer(root, "Cells", 2)
	ctx.Front = layer(root, "Front", 3)
	ctx.Fx = layer(root, "Fx", 4)

	local styleName = size.Exterior or STYLE_BY_SIZE[size.Id] or "Cottage"
	local painter = STYLES[styleName] or STYLES.Cottage
	local cellW = HouseExterior.CellWidth(size)
	local ok, built = pcall(painter, ctx, size, cellW)
	if not ok then
		warn("[HouseExterior] " .. tostring(styleName) .. " : " .. tostring(built))
		-- Repli : simple bâtiment arrondi avec la grille
		for _, child in ipairs(ctx.Back:GetChildren()) do
			child:Destroy()
		end
		for _, child in ipairs(ctx.Front:GetChildren()) do
			child:Destroy()
		end
		table.clear(ctx.Lit)
		table.clear(ctx.Glows)
		table.clear(ctx.Anims)
		local gap, pad = 16, 30
		local cols, floors = size.Columns, size.Floors
		local w = cols * cellW + (cols - 1) * gap + pad * 2
		local h = floors * HouseExterior.CELL_H + (floors - 1) * gap + pad * 2
		part(ctx.Back, 0, 0, w, h, C.PinkSoft, { R = 18, Th = 3 })
		local gaps = {}
		for index = 1, cols - 1 do
			gaps[index] = gap
		end
		local cells = makeGrid(size, cellW, pad, pad, gaps, gap)
		cellBacks(ctx.Back, cells, P.Interior, 2)
		built = { Width = w, Height = h, Cells = cells }
	end
	root.Size = UDim2.fromOffset(built.Width, built.Height)
	root.Parent = parent

	-- Mode nuit : couleurs du jour mémorisées une fois
	type Record = { Object: Instance, Day: Color3 }
	local records: { Record }? = nil
	local function collect(): { Record }
		local list: { Record } = {}
		for _, container in ipairs({ ctx.Back, ctx.Front, ctx.Fx }) do
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("Frame") then
					table.insert(list, { Object = d, Day = d.BackgroundColor3 })
				elseif d:IsA("UIStroke") then
					table.insert(list, { Object = d, Day = d.Color })
				end
			end
		end
		return list
	end

	local dark = false
	local clock = 0

	local exterior = {} :: Exterior
	exterior.Frame = root
	exterior.Width = built.Width
	exterior.Height = built.Height
	exterior.Cells = built.Cells
	exterior.CellLayer = cellLayer

	function exterior.SetDark(value: boolean)
		dark = value == true
		if not records then
			records = collect()
		end
		for _, rec in ipairs(records :: { Record }) do
			local object = rec.Object
			local color = rec.Day
			if dark then
				color = ctx.Lit[object] or color:Lerp(NIGHT_TINT, NIGHT_AMOUNT)
			end
			if object:IsA("UIStroke") then
				object.Color = color
			else
				(object :: Frame).BackgroundColor3 = color
			end
		end
		for _, g in ipairs(ctx.Glows) do
			g.Frame.Visible = dark
			g.Frame.BackgroundTransparency = g.Night
		end
		for _, object in ipairs(ctx.NightOnly) do
			object.Visible = dark
		end
		for _, object in ipairs(ctx.DayOnly) do
			object.Visible = not dark
		end
		for _, anim in ipairs(ctx.Anims) do
			anim(clock, dark)
		end
	end

	function exterior.Update(dt: number)
		clock += dt
		for _, anim in ipairs(ctx.Anims) do
			anim(clock, dark)
		end
	end

	function exterior.Destroy()
		table.clear(ctx.Anims)
		records = nil
		root:Destroy()
	end

	exterior.Update(0)
	return exterior
end

----------------------------------------------------------------------
-- Ciel (facultatif) : remplit `parent`
----------------------------------------------------------------------

local SKY_DAY = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(196, 228, 255)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 226, 240)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 226)),
})
local SKY_NIGHT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 32, 88)),
	ColorSequenceKeypoint.new(0.65, Color3.fromRGB(86, 64, 150)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 96, 170)),
})

function HouseExterior.BuildBackdrop(parent: Instance, _size: SizeDef?): Backdrop
	local root = Instance.new("Frame")
	root.Name = "HouseBackdrop"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = WHITE
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.ZIndex = 1
	root:SetAttribute("DarkSkinIgnore", true)
	local sky = grad(root, WHITE, WHITE, 90)
	sky.Color = SKY_DAY

	local function scaled(x: number, y: number, w: number, h: number, z: number): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(x, y)
		frame.Size = UDim2.fromOffset(w, h)
		frame.ZIndex = z
		frame.Parent = root
		return frame
	end

	-- Soleil / lune
	local sun = scaled(0.86, 0.16, 90, 90, 2)
	circle(sun, 45, 45, 90, 90, Color3.fromRGB(255, 240, 180), 0.6, 1)
	circle(sun, 45, 45, 58, 58, Color3.fromRGB(255, 226, 130), 0, 2)
	local moon = scaled(0.86, 0.16, 90, 90, 2)
	circle(moon, 45, 45, 90, 90, Color3.fromRGB(255, 244, 200), 0.82, 1)
	circle(moon, 45, 45, 54, 54, Color3.fromRGB(255, 244, 200), 0, 2)
	circle(moon, 58, 36, 44, 44, Color3.fromRGB(52, 44, 110), 0, 3)

	-- Collines lointaines
	local hills = {}
	for index, h in ipairs({ { 0.12, 0.34, 0.2 }, { 0.42, 0.5, 0.16 }, { 0.75, 0.42, 0.22 }, { 1.0, 0.3, 0.18 } }) do
		local hill = Instance.new("Frame")
		hill.BorderSizePixel = 0
		hill.AnchorPoint = Vector2.new(0.5, 0)
		hill.Position = UDim2.fromScale(h[1], 1 - h[3])
		hill.Size = UDim2.fromScale(h[2], h[3] * 2)
		hill.BackgroundColor3 = if index % 2 == 0 then Color3.fromRGB(196, 236, 200) else Color3.fromRGB(214, 242, 212)
		hill.ZIndex = 3
		round(hill)
		hill.Parent = root
		table.insert(hills, hill)
	end

	-- Nuages
	type Cloud = { Frame: Frame, X: number, Y: number, Speed: number }
	local clouds: { Cloud } = {}
	for index = 1, 6 do
		local holder = scaled(0, 0, 140, 80, 2)
		local w = 80 + noise(index, 1) * 70
		local base = box(holder, 70 - w / 2, 80 - w * 0.34, w, w * 0.34, WHITE, 0.2, 1)
		round(base)
		circle(holder, 70 - w * 0.14, 80 - w * 0.34, w * 0.5, w * 0.5, WHITE, 0.2, 1)
		circle(holder, 70 + w * 0.2, 80 - w * 0.31, w * 0.36, w * 0.36, WHITE, 0.2, 1)
		table.insert(clouds, { Frame = holder, X = noise(index, 5), Y = 0.1 + noise(index, 4) * 0.5, Speed = 0.005 + noise(index, 3) * 0.008 })
	end

	-- Étoiles / étincelles
	type Star = { Parts: { Instance }, Phase: number }
	local stars: { Star } = {}
	for index = 1, 22 do
		local s = 6 + noise(index, 7) * 8
		local holder = scaled(0.03 + noise(index, 8) * 0.94, 0.03 + noise(index, 9) * 0.62, s, s, 2)
		local shape = sparkle(holder, s / 2, s / 2, s, WHITE, 0.2, 1)
		table.insert(stars, { Parts = shape:GetChildren(), Phase = noise(index, 10) * 6 })
	end

	local dark = false
	local clock = 0
	local backdrop = {} :: Backdrop
	backdrop.Frame = root

	local function paintAll(frame: Instance, color: Color3)
		for _, d in ipairs(frame:GetDescendants()) do
			if d:IsA("Frame") and d.BackgroundTransparency < 1 then
				d.BackgroundColor3 = color
			end
		end
	end

	function backdrop.SetDark(value: boolean)
		dark = value == true
		sky.Color = if dark then SKY_NIGHT else SKY_DAY
		sun.Visible = not dark
		moon.Visible = dark
		for index, hill in ipairs(hills) do
			local day = if index % 2 == 0 then Color3.fromRGB(196, 236, 200) else Color3.fromRGB(214, 242, 212)
			hill.BackgroundColor3 = if dark then day:Lerp(NIGHT_TINT, 0.55) else day
		end
		for _, cloud in ipairs(clouds) do
			paintAll(cloud.Frame, if dark then Color3.fromRGB(120, 110, 180) else WHITE)
		end
		for _, star in ipairs(stars) do
			for _, child in ipairs(star.Parts) do
				(child :: Frame).BackgroundColor3 = if dark then Color3.fromRGB(255, 244, 190) else WHITE
			end
		end
	end

	function backdrop.Update(dt: number)
		clock += dt
		for _, cloud in ipairs(clouds) do
			cloud.X = (cloud.X + cloud.Speed * dt) % 1.3
			cloud.Frame.Position = UDim2.fromScale(cloud.X - 0.15, cloud.Y)
		end
		for _, star in ipairs(stars) do
			local wave = 0.5 + 0.5 * math.sin(clock * 2 + star.Phase)
			local base = if dark then 0.05 else 0.5
			for _, child in ipairs(star.Parts) do
				(child :: Frame).BackgroundTransparency = base + wave * 0.45
			end
		end
	end

	function backdrop.Destroy()
		root:Destroy()
	end

	root.Parent = parent
	backdrop.SetDark(false)
	backdrop.Update(0)
	return backdrop
end

return HouseExterior
