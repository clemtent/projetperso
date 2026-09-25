--[[
	HouseArt (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseArt

	Dessins "autocollants kawaii" des objets de la maison, faits UNIQUEMENT
	avec des Frames (aucune image à importer) :
	  - une boîte à outils (Kit) : formes arrondies avec contour et ombrage,
	    ovales, traits, triangles, cœurs, étincelles, nuages, petits visages
	    kawaii, reflets, pivots de rotation et petites animations ;
	  - les dessins eux-mêmes, rangés par catégorie dans le dossier Art
	    (un ModuleScript par catégorie : { [Id d'objet] = peintre }).

	Contrat d'un peintre : function(body, kit, item) -> Result?
	  - `body` est une boîte de 100 x 100 px ("maquette") ; les objets posés
	    au sol ont leurs pieds en bas (y = 100), les objets muraux sont
	    centrés. On peut déborder un peu (fil d'une ampoule...).
	  - ZIndex relatifs (ZIndexBehavior = Sibling) : 1..9 entre frères.
	  - Result (tout est facultatif) :
	      Glow       = Color3 : halo de lumière (plus fort la nuit)
	      Flat       = true : objet posé à plat (tapis) -> pas d'ombre ovale
	      WallShadow = Vector2 : taille de l'ombre d'un objet mural (0 = aucune)
	      Bulbs      = { ampoule, halo, ampoule, halo... } : scintillement
	      ShowEmoji  = true : garde l'emoji de l'objet par-dessus (rare)
	      EmojiScale, EmojiY : taille / hauteur de cet emoji

	API :
	  HouseArt.Has(itemId) -> boolean
	  HouseArt.Paint(body, item, static?) -> (Result?, { Anim })
	      dessine l'objet dans `body` ; `static` = pas d'animation (vignettes)
	  HouseArt.Thumbnail(parent, item, size, zIndex?) -> Frame
	      vignette carrée de `size` px (dessin, ou emoji si pas de dessin)
	  HouseArt.Step(anims, clock) : fait vivre les animations
]]

local HouseArt = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local SQRT2 = math.sqrt(2)
local FONT = Enum.Font.FredokaOne

-- Palette kawaii (mêmes teintes que HouseCommon.Colors + quelques couleurs)
local C = {
	White = WHITE,
	Black = BLACK,
	Ink = Color3.fromRGB(92, 58, 96), -- contours / yeux "chocolat-prune"
	Pink = Color3.fromRGB(255, 126, 182),
	PinkDeep = Color3.fromRGB(236, 72, 140),
	PinkSoft = Color3.fromRGB(255, 214, 232),
	PinkMist = Color3.fromRGB(255, 240, 247),
	Blush = Color3.fromRGB(255, 150, 170),
	Lilac = Color3.fromRGB(183, 148, 246),
	LilacSoft = Color3.fromRGB(236, 224, 255),
	Purple = Color3.fromRGB(150, 100, 220),
	Mint = Color3.fromRGB(110, 214, 176),
	MintSoft = Color3.fromRGB(214, 247, 234),
	Green = Color3.fromRGB(110, 190, 110),
	Leaf = Color3.fromRGB(120, 200, 120),
	LeafDark = Color3.fromRGB(70, 150, 90),
	Cream = Color3.fromRGB(255, 247, 236),
	Peach = Color3.fromRGB(255, 190, 160),
	Orange = Color3.fromRGB(255, 160, 90),
	Sky = Color3.fromRGB(150, 205, 255),
	Blue = Color3.fromRGB(100, 160, 240),
	Navy = Color3.fromRGB(60, 70, 130),
	Butter = Color3.fromRGB(255, 226, 130),
	Yellow = Color3.fromRGB(255, 210, 80),
	Gold = Color3.fromRGB(245, 190, 60),
	Red = Color3.fromRGB(240, 90, 100),
	Heart = Color3.fromRGB(255, 79, 139),
	Wood = Color3.fromRGB(214, 164, 120),
	WoodLight = Color3.fromRGB(236, 196, 150),
	WoodDark = Color3.fromRGB(160, 110, 78),
	Brown = Color3.fromRGB(150, 100, 80),
	Grey = Color3.fromRGB(200, 196, 210),
	GreyDark = Color3.fromRGB(120, 116, 136),
	Glass = Color3.fromRGB(200, 235, 255),
}
HouseArt.Colors = C

export type Result = {
	Glow: Color3?,
	Flat: boolean?,
	WallShadow: Vector2?,
	Bulbs: { Frame }?,
	ShowEmoji: boolean?,
	EmojiScale: number?,
	EmojiY: number?,
}

export type Anim = {
	Object: GuiObject,
	Kind: string,
	Amp: number,
	Speed: number,
	Phase: number,
	BaseRotation: number,
	BasePosition: UDim2,
	BaseTransparency: number,
	Scale: UIScale?,
}

type PartOptions = {
	Radius: number?, -- rayon des coins en px (défaut : 6) ; -1 = pilule / ovale
	Z: number?,
	T: number?, -- transparence du fond
	Outline: any?, -- false = sans contour ; Color3 = couleur ; défaut = teinte foncée
	Thickness: number?, -- épaisseur du contour (défaut 1.6)
	Shade: any?, -- false = sans ombrage ; nombre = force (défaut 0.12)
	Shine: boolean?, -- petit reflet blanc en haut à gauche
	Rotation: number?,
}

----------------------------------------------------------------------
-- Couleurs
----------------------------------------------------------------------

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(BLACK, amount)
end

-- Contour "kawaii" : la couleur tirée vers l'encre prune
local function outlineOf(color: Color3): Color3
	return color:Lerp(C.Ink, 0.55)
end

----------------------------------------------------------------------
-- Formes de base
----------------------------------------------------------------------

local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, transparency: number?, z: number?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.ZIndex = z or 2
	frame.Parent = parent
	return frame
end

local function round(frame: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	if radius == nil or radius < 0 then
		corner.CornerRadius = UDim.new(1, 0)
	else
		corner.CornerRadius = UDim.new(0, radius)
	end
	corner.Parent = frame
	return corner
end

local function stroke(frame: GuiObject, color: Color3, thickness: number?, transparency: number?): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness or 1.6
	line.Transparency = transparency or 0
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.LineJoinMode = Enum.LineJoinMode.Round
	line.Parent = frame
	return line
end

-- Dégradé de couleur (multiplie la couleur du fond) ; rotation 90 = haut -> bas
local function gradient(frame: GuiObject, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(top, bottom)
	grad.Rotation = rotation or 90
	grad.Parent = frame
	return grad
end

-- Dégradé de transparence (fondu) ; rotation 90 = haut -> bas
local function fade(frame: GuiObject, from: number, to: number, rotation: number?): UIGradient
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new(from, to)
	grad.Rotation = rotation or 90
	grad.Parent = frame
	return grad
end

local function circle(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, transparency: number?, z: number?): Frame
	local frame = box(parent, cx - w / 2, cy - h / 2, w, h, color, transparency, z)
	round(frame)
	return frame
end

-- Forme "kawaii" : fond + contour foncé + ombrage vertical (+ reflet)
local function part(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, options: PartOptions?): Frame
	local opts: PartOptions = options or {}
	local frame = box(parent, x, y, w, h, color, opts.T, opts.Z)
	local radius = opts.Radius
	if radius == nil then
		radius = 6
	end
	if radius ~= 0 then
		round(frame, radius)
	end
	if opts.Rotation then
		frame.Rotation = opts.Rotation
	end
	local outline = opts.Outline
	if outline ~= false then
		local lineColor = if typeof(outline) == "Color3" then outline else outlineOf(color)
		stroke(frame, lineColor, opts.Thickness or 1.6, 0)
	end
	local shade = opts.Shade
	if shade ~= false then
		local amount = if type(shade) == "number" then shade else 0.12
		gradient(frame, WHITE, Color3.new(1 - amount, 1 - amount, 1 - amount), 90)
	end
	if opts.Shine then
		local shine = box(frame, math.max(2, w * 0.14), math.max(2, h * 0.12), math.max(3, w * 0.26), math.max(2, math.min(6, h * 0.14)), WHITE, 0.35, 3)
		round(shine)
	end
	return frame
end

-- Ovale "kawaii" (même style que part)
local function blob(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, options: PartOptions?): Frame
	local opts: PartOptions = options or {}
	local copy: PartOptions = {
		Radius = -1,
		Z = opts.Z,
		T = opts.T,
		Outline = opts.Outline,
		Thickness = opts.Thickness,
		Shade = opts.Shade,
		Shine = opts.Shine,
		Rotation = opts.Rotation,
	}
	return part(parent, cx - w / 2, cy - h / 2, w, h, color, copy)
end

-- Trait (segment arrondi) entre deux points
local function line(parent: Instance, x1: number, y1: number, x2: number, y2: number, thickness: number, color: Color3, transparency: number?, z: number?): Frame
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	local frame = box(parent, 0, 0, length + thickness, thickness, color, transparency, z)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	frame.Rotation = math.deg(math.atan2(dy, dx))
	round(frame)
	return frame
end

-- Triangle pointe en haut (tranches horizontales) ; `top` = y de la pointe
local function triangle(parent: Instance, cx: number, top: number, w: number, h: number, color: Color3, z: number?, transparency: number?, slices: number?): Frame
	local holder = box(parent, cx - w / 2, top, w, h, color, 1, z)
	local count = slices or math.clamp(math.floor(h / 2), 4, 24)
	for index = 1, count do
		local k = index / count
		local sliceW = w * k
		box(holder, (w - sliceW) / 2, (index - 1) * h / count, sliceW, h / count + 0.6, color, transparency, 1)
	end
	return holder
end

-- Triangle pointe en bas ; `top` = y de la base
local function triangleDown(parent: Instance, cx: number, top: number, w: number, h: number, color: Color3, z: number?, transparency: number?, slices: number?): Frame
	local holder = box(parent, cx - w / 2, top, w, h, color, 1, z)
	local count = slices or math.clamp(math.floor(h / 2), 4, 24)
	for index = 1, count do
		local k = 1 - (index - 1) / count
		local sliceW = w * k
		box(holder, (w - sliceW) / 2, (index - 1) * h / count, sliceW, h / count + 0.6, color, transparency, 1)
	end
	return holder
end

local function diamond(parent: Instance, cx: number, cy: number, side: number, color: Color3, transparency: number?, z: number?): Frame
	local frame = box(parent, 0, 0, side, side, color, transparency, z)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(cx, cy)
	frame.Rotation = 45
	return frame
end

-- Cœur (2 cercles + un losange) centré, de largeur `width` ; renvoie son conteneur
local function heart(parent: Instance, cx: number, cy: number, width: number, color: Color3, transparency: number?, z: number?): Frame
	local holder = box(parent, cx - width / 2, cy - width / 2, width, width, color, 1, z)
	local a = width / (1 + 1 / SQRT2)
	local centerY = width / 2 + a * 0.073
	local offset = a / (2 * SQRT2)
	diamond(holder, width / 2, centerY, a, color, transparency, 1)
	circle(holder, width / 2 - offset, centerY - offset, a, a, color, transparency, 1)
	circle(holder, width / 2 + offset, centerY - offset, a, a, color, transparency, 1)
	return holder
end

-- Étincelle à 4 branches ; renvoie son conteneur
local function sparkle(parent: Instance, cx: number, cy: number, size: number, color: Color3, transparency: number?, z: number?): Frame
	local holder = box(parent, cx - size / 2, cy - size / 2, size, size, color, 1, z)
	diamond(holder, size / 2, size / 2, size * 0.36, color, transparency, 1)
	local thin = math.max(1, size * 0.14)
	local vertical = box(holder, size / 2 - thin / 2, 0, thin, size, color, transparency, 1)
	round(vertical)
	local horizontal = box(holder, 0, size / 2 - thin / 2, size, thin, color, transparency, 1)
	round(horizontal)
	return holder
end

-- Nuage (base arrondie + 2 bosses), `cy` = bas du nuage ; renvoie son conteneur
local function cloud(parent: Instance, cx: number, cy: number, width: number, color: Color3, transparency: number?, z: number?): Frame
	local height = width * 0.62
	local holder = box(parent, cx - width / 2, cy - height, width, height, color, 1, z)
	local baseH = width * 0.34
	local base = box(holder, 0, height - baseH, width, baseH, color, transparency, 1)
	round(base)
	circle(holder, width * 0.36, height - baseH, width * 0.5, width * 0.5, color, transparency, 1)
	circle(holder, width * 0.7, height - baseH * 0.9, width * 0.36, width * 0.36, color, transparency, 1)
	return holder
end

-- Reflet blanc (pilule semi-transparente)
local function shine(parent: Instance, x: number, y: number, w: number, h: number, z: number?, transparency: number?): Frame
	local frame = box(parent, x, y, w, h, WHITE, transparency or 0.35, z or 5)
	round(frame)
	return frame
end

-- Texte / petit emoji d'accent (centré)
local function text(parent: Instance, value: string, cx: number, cy: number, size: number, color: Color3?, z: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(cx, cy)
	label.Size = UDim2.fromOffset(size * 3, size * 1.3)
	label.Font = FONT
	label.Text = value
	label.TextSize = size
	label.TextColor3 = color or C.Ink
	label.ZIndex = z or 6
	label.Parent = parent
	return label
end

-- Conteneur transparent (pour grouper, découper avec clip = true)
local function group(parent: Instance, x: number, y: number, w: number, h: number, z: number?, clip: boolean?): Frame
	local frame = box(parent, x, y, w, h, WHITE, 1, z)
	frame.ClipsDescendants = clip == true
	return frame
end

-- Pivot : conteneur de taille nulle placé en (px, py). Ses enfants se placent
-- par rapport à ce point et tournent autour de lui (balancier, hélice...)
local function pivot(parent: Instance, px: number, py: number, z: number?): Frame
	local frame = box(parent, px, py, 0, 0, WHITE, 1, z)
	return frame
end

----------------------------------------------------------------------
-- Visage kawaii
----------------------------------------------------------------------

type FaceOptions = {
	Eyes: string?, -- "dot" (défaut) | "happy" (^ ^) | "closed" (endormi) | "big" (yeux brillants)
	Mouth: string?, -- "smile" (défaut) | "cat" (ω) | "o" | "none"
	Blush: boolean?, -- défaut true
	Color: Color3?, -- couleur des yeux / de la bouche
	Z: number?,
	Spacing: number?, -- écart entre les yeux (fraction de size, défaut 0.62)
}

-- Visage centré en (cx, cy), `size` ≈ largeur du visage ; renvoie son conteneur
-- (les yeux "dot" / "big" clignent tout seuls si le kit est animé)
local function makeFace(kit: any, parent: Instance, cx: number, cy: number, size: number, options: FaceOptions?): Frame
	local opts: FaceOptions = options or {}
	local ink = opts.Color or C.Ink
	local holder = group(parent, cx - size / 2, cy - size / 2, size, size, opts.Z or 6)
	local half = size / 2
	local gap = size * (opts.Spacing or 0.62) / 2
	local eyeY = half - size * 0.08
	local eyes = opts.Eyes or "dot"
	local eyeSize = math.max(2, size * 0.16)
	local eyeFrames = {}
	for _, side in ipairs({ -1, 1 }) do
		local ex = half + side * gap
		if eyes == "happy" then
			line(holder, ex - eyeSize * 0.55, eyeY + eyeSize * 0.25, ex, eyeY - eyeSize * 0.3, math.max(1, size * 0.06), ink, 0, 2)
			line(holder, ex, eyeY - eyeSize * 0.3, ex + eyeSize * 0.55, eyeY + eyeSize * 0.25, math.max(1, size * 0.06), ink, 0, 2)
		elseif eyes == "closed" then
			line(holder, ex - eyeSize * 0.6, eyeY, ex + eyeSize * 0.6, eyeY, math.max(1, size * 0.06), ink, 0, 2)
		else
			local big = eyes == "big"
			local w = big and eyeSize * 1.35 or eyeSize
			local h = big and eyeSize * 1.6 or eyeSize * 1.15
			local eye = circle(holder, ex, eyeY, w, h, ink, 0, 2)
			local dot = circle(eye, w * 0.32, h * 0.3, w * 0.42, w * 0.42, WHITE, 0, 2)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromOffset(w * 0.34, h * 0.3)
			table.insert(eyeFrames, eye)
		end
		if opts.Blush ~= false then
			circle(holder, ex + side * size * 0.1, eyeY + size * 0.16, size * 0.2, size * 0.11, C.Blush, 0.35, 1)
		end
	end
	local mouth = opts.Mouth or "smile"
	local my = eyeY + size * 0.12
	local mw = size * 0.12
	local thick = math.max(1, size * 0.055)
	if mouth == "smile" then
		line(holder, half - mw / 2, my - mw * 0.2, half, my + mw * 0.25, thick, ink, 0, 2)
		line(holder, half, my + mw * 0.25, half + mw / 2, my - mw * 0.2, thick, ink, 0, 2)
	elseif mouth == "cat" then
		for _, side in ipairs({ -1, 1 }) do
			local ox = half + side * mw * 0.45
			line(holder, ox - mw * 0.45, my - mw * 0.15, ox, my + mw * 0.25, thick, ink, 0, 2)
			line(holder, ox, my + mw * 0.25, ox + mw * 0.45, my - mw * 0.15, thick, ink, 0, 2)
		end
	elseif mouth == "o" then
		local o = circle(holder, half, my + mw * 0.2, mw * 1.1, mw * 1.3, ink, 0, 2)
		circle(o, mw * 0.55, mw * 0.95, mw * 0.7, mw * 0.5, C.Blush, 0, 2)
	end
	for index, eye in ipairs(eyeFrames) do
		kit.Animate(eye, "Blink", 1, 1, index * 0.001 + (cx + cy) * 0.37)
	end
	return holder
end

----------------------------------------------------------------------
-- Kit (une instance par dessin : elle collecte les animations)
----------------------------------------------------------------------

local function newKit(static: boolean)
	local anims: { Anim } = {}
	local kit: any = {
		C = C,
		Static = static,
		Lighten = lighten,
		Darken = darken,
		OutlineOf = outlineOf,
		Box = box,
		Round = round,
		Stroke = stroke,
		Gradient = gradient,
		Fade = fade,
		Circle = circle,
		Part = part,
		Blob = blob,
		Line = line,
		Triangle = triangle,
		TriangleDown = triangleDown,
		Diamond = diamond,
		Heart = heart,
		Sparkle = sparkle,
		Cloud = cloud,
		Shine = shine,
		Text = text,
		Group = group,
		Pivot = pivot,
	}

	-- Animation d'un objet :
	--   "Sway"    : balancement, Amp = degrés
	--   "Spin"    : rotation continue, Speed = tours par seconde (Amp ignoré)
	--   "Bob"     : monte et descend, Amp = px
	--   "Drift"   : glisse de gauche à droite, Amp = px
	--   "Pulse"   : la transparence du fond varie de Amp (lueur, écran)
	--   "Flicker" : petite flamme qui vacille (transparence irrégulière, Amp)
	--   "Breathe" : grossit / rétrécit un peu, Amp = fraction (0.04 = 4 %)
	--   "Blink"   : les yeux clignent de temps en temps (Amp ignoré)
	function kit.Animate(object: GuiObject, kind: string, amp: number?, speed: number?, phase: number?)
		if static then
			return
		end
		local anim: Anim = {
			Object = object,
			Kind = kind,
			Amp = amp or 1,
			Speed = speed or 1,
			Phase = phase or 0,
			BaseRotation = object.Rotation,
			BasePosition = object.Position,
			BaseTransparency = object.BackgroundTransparency,
			Scale = nil,
		}
		if kind == "Breathe" or kind == "Flicker" then
			local existing = object:FindFirstChildOfClass("UIScale")
			anim.Scale = existing or Instance.new("UIScale")
			if not existing then
				(anim.Scale :: UIScale).Parent = object
			end
		end
		table.insert(anims, anim)
	end

	function kit.Face(parent: Instance, cx: number, cy: number, size: number, options: FaceOptions?): Frame
		return makeFace(kit, parent, cx, cy, size, options)
	end

	return kit, anims
end

----------------------------------------------------------------------
-- Registre des dessins (dossier Art)
----------------------------------------------------------------------

type Painter = (Frame, any, any) -> Result?

local painters: { [string]: Painter } = {}

local artFolder = script.Parent:FindFirstChild("Art")
if artFolder then
	for _, moduleScript in ipairs(artFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local ok, result = pcall(require, moduleScript)
			if ok and type(result) == "table" then
				for id, painter in pairs(result) do
					if type(id) == "string" and type(painter) == "function" then
						painters[id] = painter
					end
				end
			else
				warn("[HouseArt] Dessins " .. moduleScript.Name .. " : " .. tostring(result))
			end
		end
	end
end

function HouseArt.Has(itemId: string): boolean
	return painters[itemId] ~= nil
end

-- Dessine l'objet dans `body` (100 x 100) ; nil si l'objet n'a pas de dessin
function HouseArt.Paint(body: Frame, item: any, static: boolean?): (Result?, { Anim })
	local painter = painters[item.Id]
	if not painter then
		return nil, {}
	end
	local kit, anims = newKit(static == true)
	local ok, result = pcall(painter, body, kit, item)
	if not ok then
		warn("[HouseArt] Dessin " .. tostring(item.Id) .. " : " .. tostring(result))
		for _, child in ipairs(body:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		return nil, {}
	end
	return (type(result) == "table" and result or {}) :: Result, anims
end

-- Vignette carrée (boutique, inventaire) : le dessin réduit, sinon l'emoji
function HouseArt.Thumbnail(parent: Instance, item: any, size: number, zIndex: number?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Art"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.ZIndex = zIndex or 1
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(100, 100)
	body.ZIndex = 1
	local scale = Instance.new("UIScale")
	-- Un peu de marge : certains dessins débordent de leur boîte
	scale.Scale = size / 100 * 0.84
	scale.Parent = body
	body.Parent = holder
	local result = HouseArt.Paint(body, item, true)
	if not result then
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.BuilderSansMedium
		label.Text = tostring(item.Icon)
		label.TextSize = math.floor(size * 0.72)
		label.TextColor3 = WHITE
		label.ZIndex = 2
		label.Parent = body
		scale.Scale = size / 100
	end
	holder.Parent = parent
	return holder
end

-- Fait vivre les animations (clock = temps en secondes)
function HouseArt.Step(anims: { Anim }, clock: number)
	for _, anim in ipairs(anims) do
		local object = anim.Object
		local t = clock * anim.Speed + anim.Phase
		local kind = anim.Kind
		if kind == "Sway" then
			object.Rotation = anim.BaseRotation + math.sin(t * 2) * anim.Amp
		elseif kind == "Spin" then
			object.Rotation = anim.BaseRotation + (clock * anim.Speed * 360 + anim.Phase * 57) % 360
		elseif kind == "Bob" then
			local base = anim.BasePosition
			object.Position = base + UDim2.fromOffset(0, math.sin(t * 2.2) * anim.Amp)
		elseif kind == "Drift" then
			local base = anim.BasePosition
			object.Position = base + UDim2.fromOffset(math.sin(t * 1.3) * anim.Amp, 0)
		elseif kind == "Pulse" then
			object.BackgroundTransparency = math.clamp(anim.BaseTransparency + (0.5 + 0.5 * math.sin(t * 2.4)) * anim.Amp, 0, 1)
		elseif kind == "Flicker" then
			local wave = math.sin(t * 9) * 0.5 + math.sin(t * 13.7 + 1.3) * 0.3 + math.sin(t * 23.1) * 0.2
			object.BackgroundTransparency = math.clamp(anim.BaseTransparency + (0.5 + 0.5 * wave) * anim.Amp, 0, 1)
			local scale = anim.Scale
			if scale then
				scale.Scale = 1 + wave * 0.05
			end
		elseif kind == "Breathe" then
			local scale = anim.Scale
			if scale then
				scale.Scale = 1 + math.sin(t * 1.8) * anim.Amp
			end
		elseif kind == "Blink" then
			-- Un clignement rapide toutes les ~4 s (décalé par objet)
			local cycle = (clock + anim.Phase) % 4.2
			object.Visible = cycle < 4.05
		end
	end
end

return HouseArt
