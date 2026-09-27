--[[
	CosmeticArt (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > CosmeticArt

	(v9.2) Dessins des chapeaux et des motifs de boutons "cool" de la
	boutique d'objets (Config.Cosmetics) — uniquement des Frames, même style
	"autocollant" que la maison (boîte à outils de HouseArt) :
	  - chapeaux : casquette à l'envers, bandeau de ninja, casque gamer,
	    chapeau de pirate, casque de course, casque de viking, capuche de
	    dino, visière de robot (les autres chapeaux gardent leur emoji) ;
	  - motifs de boutons (cosmetic.Pattern) posés par-dessus le dégradé
	    Top -> Bottom : Carbon, Camo, Basketball, Controller, Flames, Lava,
	    Galaxy, Circuit. Positions en fractions : le motif s'adapte à la
	    taille du bouton (gros bouton, aperçu, pastille de la boutique).
	Rien n'est animé (aucune boucle) : quelques dizaines de Frames au plus.

	API :
	  CosmeticArt.HasHat(id) -> boolean
	  CosmeticArt.ApplyHat(label, cosmetic?) -> boolean
	      dessine le chapeau dans `label` (TextLabel carré du chapeau) et
	      vide son texte ; sinon remet l'emoji (cosmetic.Icon, "" si nil)
	  CosmeticArt.ApplySkin(button, cosmetic?, radius?, zIndex?)
	      pose (ou retire) le motif du bouton (enfant "SkinArt" découpé aux
	      coins arrondis du bouton, sous son texte)
]]

local Components = script.Parent
local HouseArt = require(Components:WaitForChild("House"):WaitForChild("HouseArt"))

local CosmeticArt = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local DARK = rgb(44, 46, 64)
local DARKER = rgb(30, 32, 46)
local CYAN = rgb(60, 222, 255)
local MAGENTA = rgb(255, 84, 196)
local LIME = rgb(140, 240, 110)
local RED = rgb(236, 66, 76)
local ORANGE = rgb(255, 152, 56)
local YELLOW = rgb(255, 214, 80)
local STEEL = rgb(176, 186, 206)
local GOLD = rgb(245, 190, 60)

----------------------------------------------------------------------
-- Chapeaux (boîte 100 x 100, le bas du chapeau vers y = 92)
----------------------------------------------------------------------

local HATS: { [string]: (body: Frame, kit: any) -> () } = {}

-- Casquette portée à l'envers (visière vers l'arrière, fermeture devant)
HATS.Snapback = function(body, kit)
	local navy = rgb(60, 80, 150)
	kit.Part(body, 60, 70, 36, 12, RED, { Radius = 6, Z = 1, Rotation = 10, Shine = true }) -- visière (derrière)
	local dome = kit.Part(body, 14, 36, 70, 54, navy, { Radius = 28, Z = 2, Shine = true })
	kit.Box(dome, 34, 4, 2, 48, kit.Lighten(navy, 0.25), 0.3, 2) -- couture
	kit.Circle(dome, 35, 3, 8, 6, RED, 0, 3) -- bouton
	-- ouverture réglable à l'avant
	local gap = kit.Part(body, 22, 72, 22, 14, rgb(255, 220, 196), { Radius = 7, Z = 3 })
	kit.Box(gap, 3, 2, 16, 3, WHITE, 0, 2)
	kit.Part(body, 10, 84, 80, 8, kit.Darken(navy, 0.2), { Radius = 4, Z = 3 })
	kit.Sparkle(dome, 50, 22, 12, YELLOW, 0, 3)
end

-- Bandeau de ninja (plaque en métal + rubans qui flottent)
HATS.NinjaBand = function(body, kit)
	for index, spec in ipairs({ { 70, 66, 28, -24 }, { 72, 76, 24, 16 } }) do
		kit.Part(body, spec[1], spec[2], spec[3], 9, RED, { Radius = 4, Z = 1, Rotation = spec[4] })
		local _ = index
	end
	local band = kit.Part(body, 6, 64, 88, 22, RED, { Radius = 11, Z = 2, Shine = true })
	kit.Box(band, 6, 16, 76, 2, kit.Darken(RED, 0.25), 0.2, 2)
	local plate = kit.Part(body, 30, 60, 40, 30, STEEL, { Radius = 6, Z = 3, Shine = true })
	-- étoile de ninja gravée
	kit.Diamond(plate, 20, 15, 10, DARK, 0, 2)
	kit.Box(plate, 11, 13.5, 18, 3, DARK, 0, 2)
	kit.Box(plate, 18.5, 6, 3, 18, DARK, 0, 2)
	kit.Circle(plate, 20, 15, 4, 4, STEEL, 0, 3)
	for _, x in ipairs({ 4, 36 }) do
		kit.Circle(plate, x, 5, 3, 3, DARK, 0.2, 2)
		kit.Circle(plate, x, 25, 3, 3, DARK, 0.2, 2)
	end
end

-- Casque gamer (arceau, oreillettes RGB, micro)
HATS.GamerHeadset = function(body, kit)
	local clip = kit.Group(body, 8, 20, 84, 50, 1, true)
	-- arceau clair (lisible sur les boutons sombres) + coussinet
	kit.Part(clip, 4, 4, 76, 90, WHITE, { Radius = -1, T = 1, Outline = rgb(230, 236, 250), Thickness = 9, Shade = false })
	local pad = kit.Part(body, 30, 20, 40, 12, MAGENTA, { Radius = 6, Z = 2, Shine = true })
	kit.Box(pad, 8, 4, 24, 3, CYAN, 0.1, 2)
	for index, side in ipairs({ -1, 1 }) do
		local cx = 50 + side * 38
		local color = index == 1 and CYAN or MAGENTA
		kit.Blob(body, cx, 70, 30, 38, color, { Z = 2, Outline = false, Shade = false, T = 0.55 })
		local cup = kit.Blob(body, cx, 70, 24, 32, rgb(236, 240, 250), { Z = 3, Shine = true })
		kit.Blob(cup, 12, 16, 14, 20, DARKER, { Z = 2, Outline = color, Thickness = 2.5, Shade = false })
	end
	kit.Line(body, 16, 80, 34, 92, 3, DARK, 0, 4)
	kit.Blob(body, 36, 92, 9, 7, DARKER, { Z = 5 })
	kit.Circle(body, 36, 92, 4, 4, LIME, 0, 6)
end

-- Chapeau de pirate (tricorne noir, galon doré, tête de mort mignonne, plume)
HATS.PirateHat = function(body, kit)
	local black = rgb(46, 42, 58)
	kit.Part(body, 60, 18, 12, 40, rgb(240, 90, 110), { Radius = 6, Z = 1, Rotation = 30 }) -- plume
	local crown = kit.Part(body, 22, 30, 56, 44, black, { Radius = 20, Z = 2, Shine = true })
	local _ = crown
	local brim = kit.Part(body, 2, 62, 96, 26, black, { Radius = 13, Z = 3, Shine = true })
	kit.Stroke(brim, GOLD, 3, 0)
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(body, 50 + side * 38 - 9, 50, 18, 26, black, { Radius = 9, Z = 3, Rotation = side * 30 })
	end
	local skull = kit.Blob(body, 50, 56, 22, 20, WHITE, { Z = 4 })
	kit.Circle(skull, 7, 9, 5, 5, black, 0, 2)
	kit.Circle(skull, 15, 9, 5, 5, black, 0, 2)
	kit.Box(skull, 8, 15, 6, 2, black, 0, 2)
	kit.Line(body, 38, 70, 62, 78, 3, WHITE, 0, 4)
	kit.Line(body, 62, 70, 38, 78, 3, WHITE, 0, 4)
end

-- Casque de course (intégral rouge, bandes blanches, visière fumée)
HATS.RacingHelmet = function(body, kit)
	local helmet = kit.Part(body, 10, 18, 80, 74, RED, { Radius = 36, Z = 1, Shine = true })
	kit.Box(helmet, 34, 2, 5, 70, WHITE, 0, 2)
	kit.Box(helmet, 42, 2, 5, 70, WHITE, 0, 2)
	local visor = kit.Part(body, 36, 42, 54, 26, DARKER, { Radius = 12, Z = 2 })
	kit.Gradient(visor, rgb(90, 110, 180), rgb(20, 20, 40), 90)
	kit.Shine(visor, 8, 5, 20, 5, 3, 0.35)
	kit.Part(body, 14, 80, 72, 12, DARKER, { Radius = 6, Z = 3 })
	local plate = kit.Blob(body, 26, 50, 22, 18, WHITE, { Z = 3 })
	kit.Text(plate, "7", 11, 9, 14, RED, 2)
end

-- Casque de viking (dôme gris, bandeau doré à rivets, cornes)
HATS.VikingHelmet = function(body, kit)
	local horn = rgb(250, 240, 214)
	local hornDark = rgb(226, 206, 170)
	for _, side in ipairs({ -1, 1 }) do
		-- corne qui s'affine en remontant vers l'extérieur
		kit.Blob(body, 50 + side * 34, 62, 22, 18, horn, { Z = 1, Rotation = side * 20 })
		kit.Blob(body, 50 + side * 42, 48, 16, 20, horn, { Z = 1, Rotation = side * 25 })
		kit.Blob(body, 50 + side * 45, 35, 11, 16, horn, { Z = 1, Rotation = side * 15 })
		kit.Triangle(body, 50 + side * 45, 18, 10, 14, horn, 1)
		kit.Box(body, 50 + side * 36 - 6, 56, 12, 3, hornDark, 0.2, 2)
	end
	local dome = kit.Part(body, 14, 30, 72, 60, STEEL, { Radius = 32, Z = 2, Shine = true })
	kit.Box(dome, 33, 4, 6, 54, GOLD, 0, 2)
	local band = kit.Part(body, 10, 76, 80, 14, GOLD, { Radius = 5, Z = 3, Shine = true })
	for index = 0, 5 do
		kit.Circle(band, 8 + index * 12.8, 7, 4, 4, rgb(200, 150, 50), 0, 2)
	end
	kit.Part(body, 45, 76, 10, 20, STEEL, { Radius = 3, Z = 4 }) -- nasal
end

-- Capuche de dino (verte, piques orange, dents, yeux)
HATS.DinoHood = function(body, kit)
	local green = rgb(120, 200, 110)
	for index = 0, 3 do
		kit.Triangle(body, 30 + index * 13, 10 + math.abs(index - 1.5) * 5, 14, 16, ORANGE, 1)
	end
	local hood = kit.Part(body, 12, 22, 76, 66, green, { Radius = 32, Z = 2, Shine = true })
	kit.Face(hood, 38, 26, 30, { Eyes = "big", Mouth = "none", Z = 3 })
	for index = 0, 6 do
		kit.TriangleDown(body, 20 + index * 10, 80, 8, 8, WHITE, 3) -- dents
	end
	kit.Part(body, 12, 78, 76, 6, kit.Darken(green, 0.2), { Radius = 3, Z = 3 })
	for _, x in ipairs({ 24, 76 }) do
		kit.Circle(body, x, 60, 8, 6, kit.Darken(green, 0.15), 0.2, 3) -- écailles
	end
end

-- Visière de robot (bandeau métal, visière lumineuse, antenne)
HATS.RobotVisor = function(body, kit)
	kit.Line(body, 50, 44, 50, 16, 3, STEEL, 0, 1)
	kit.Circle(body, 50, 14, 12, 12, RED, 0.5, 1)
	kit.Circle(body, 50, 14, 8, 8, RED, 0, 2)
	local band = kit.Part(body, 6, 44, 88, 44, STEEL, { Radius = 16, Z = 2, Shine = true })
	local visor = kit.Part(band, 8, 12, 72, 16, DARKER, { Radius = 8, Z = 2 })
	local glow = kit.Box(visor, 6, 5, 60, 6, CYAN, 0, 2)
	kit.Round(glow)
	for _, x in ipairs({ 22, 50 }) do
		kit.Box(visor, x, 4, 8, 8, WHITE, 0.2, 3)
	end
	for _, x in ipairs({ 4, 80 }) do
		kit.Circle(band, x, 22, 6, 6, DARK, 0, 3)
	end
	kit.Box(band, 10, 34, 68, 2, DARK, 0.4, 2)
end

function CosmeticArt.HasHat(id: string): boolean
	return HATS[id] ~= nil
end

-- Dessine le chapeau dans `label` (ou remet l'emoji) ; renvoie true si dessiné
function CosmeticArt.ApplyHat(label: GuiObject, cosmetic: any?): boolean
	local old = label:FindFirstChild("HatArt")
	if old then
		old:Destroy()
	end
	local painter = cosmetic and HATS[cosmetic.Id]
	local textLabel = label:IsA("TextLabel") and label or nil
	if not painter then
		if textLabel then
			textLabel.Text = cosmetic and tostring(cosmetic.Icon or "") or ""
		end
		return false
	end
	if textLabel then
		textLabel.Text = ""
	end
	local size = math.min(label.Size.X.Offset, label.Size.Y.Offset)
	if size <= 0 then
		size = math.min(label.AbsoluteSize.X, label.AbsoluteSize.Y)
	end
	if size <= 0 then
		size = 60
	end
	local body = Instance.new("Frame")
	body.Name = "HatArt"
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(100, 100)
	body.ZIndex = label.ZIndex
	local scale = Instance.new("UIScale")
	scale.Scale = size / 100 * 1.2 -- (un peu plus grand qu'un emoji : les dessins ont des marges)
	scale.Parent = body
	local kit = HouseArt.NewKit(true)
	local ok, err = pcall(painter, body, kit)
	if not ok then
		warn("[CosmeticArt] Chapeau " .. tostring(cosmetic.Id) .. " : " .. tostring(err))
		body:Destroy()
		if textLabel then
			textLabel.Text = tostring(cosmetic.Icon or "")
		end
		return false
	end
	body.Parent = label
	return true
end

----------------------------------------------------------------------
-- Motifs des boutons (fractions de la taille du bouton)
----------------------------------------------------------------------

local function frame(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, t: number?, z: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = t or 0
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function roundify(f: GuiObject, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(1, 0)
	corner.Parent = f
end

-- Ovale centré (cx, cy), tourné
local function oval(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, t: number?, rotation: number?, z: number?): Frame
	local f = frame(parent, cx, cy, w, h, color, t, z)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Rotation = rotation or 0
	roundify(f)
	return f
end

-- Petit disque qui reste rond (largeur = hauteur en px)
local function dot(parent: Instance, cx: number, cy: number, h: number, color: Color3, t: number?, z: number?): Frame
	local f = frame(parent, cx, cy, h, h, color, t, z)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.SizeConstraint = Enum.SizeConstraint.RelativeYY
	roundify(f)
	return f
end

local function ringOval(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, thick: number, t: number?): Frame
	local f = oval(parent, cx, cy, w, h, color, 1)
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thick
	line.Transparency = t or 0
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = f
	return f
end

local WEAVE = (function()
	local points = {}
	for index = 0, 18 do
		table.insert(points, NumberSequenceKeypoint.new(index / 18, index % 2 == 0 and 0.35 or 0.9))
	end
	return NumberSequence.new(points)
end)()

local SKINS: { [string]: (holder: Frame) -> () } = {}

SKINS.Carbon = function(holder)
	local rows = 7
	for row = 0, rows - 1 do
		for col = 0, 2 do
			local offset = (row % 2) * 0.03
			local strip = frame(holder, col / 3 - offset, row / rows, 1 / 3 + 0.01, 1 / rows, rgb(150, 156, 176), 0, 1)
			local weave = Instance.new("UIGradient")
			weave.Transparency = WEAVE
			weave.Parent = strip
		end
	end
	local gloss = frame(holder, 0.18, -0.4, 0.14, 1.8, WHITE, 0.82, 2)
	gloss.Rotation = 24
end

SKINS.Camo = function(holder)
	local tones = { rgb(70, 92, 56), rgb(122, 146, 90), rgb(176, 186, 130), rgb(90, 76, 60) }
	local spots = {
		{ 0.08, 0.2, 0.26, 0.5, -20 }, { 0.3, 0.75, 0.3, 0.45, 15 }, { 0.5, 0.2, 0.24, 0.5, 30 },
		{ 0.72, 0.7, 0.3, 0.5, -10 }, { 0.92, 0.25, 0.22, 0.6, 20 }, { 0.2, 0.5, 0.14, 0.4, 50 },
		{ 0.62, 0.45, 0.16, 0.35, -40 }, { 0.84, 0.95, 0.2, 0.4, 0 }, { 0.02, 0.9, 0.18, 0.4, 10 },
		{ 0.42, 1, 0.2, 0.4, 25 }, { 0.4, -0.05, 0.2, 0.35, 0 },
	}
	for index, s in ipairs(spots) do
		oval(holder, s[1], s[2], s[3], s[4], tones[index % #tones + 1], 0, s[5], 1)
	end
end

SKINS.Basketball = function(holder)
	local seam = rgb(90, 40, 20)
	frame(holder, 0.5, 0, 0.012, 1, seam, 0, 2).AnchorPoint = Vector2.new(0.5, 0)
	frame(holder, 0, 0.5, 1, 0.04, seam, 0, 2).AnchorPoint = Vector2.new(0, 0.5)
	ringOval(holder, 0.02, 0.5, 0.5, 1.6, seam, 2.5, 0)
	ringOval(holder, 0.98, 0.5, 0.5, 1.6, seam, 2.5, 0)
	for index = 1, 14 do
		local x = ((index * 0.37) % 1)
		local y = ((index * 0.61) % 1)
		dot(holder, x, y, 0.08, rgb(200, 90, 30), 0.5, 1)
	end
	local shine = oval(holder, 0.3, 0.2, 0.3, 0.18, WHITE, 0.7, -8, 3)
	local _ = shine
end

SKINS.Controller = function(holder)
	-- croix directionnelle à gauche, boutons à droite, sticks aux coins
	frame(holder, 0.06, 0.44, 0.14, 0.12, WHITE, 0.25, 2)
	frame(holder, 0.105, 0.26, 0.05, 0.48, WHITE, 0.25, 2)
	for index, spec in ipairs({ { 0.87, 0.3, YELLOW }, { 0.93, 0.5, RED }, { 0.81, 0.5, CYAN }, { 0.87, 0.7, LIME } }) do
		dot(holder, spec[1], spec[2], 0.2, spec[3], 0, 2)
		local _ = index
	end
	for _, x in ipairs({ 0.26, 0.74 }) do
		dot(holder, x, 0.82, 0.26, DARKER, 0.2, 2)
		dot(holder, x, 0.82, 0.14, rgb(90, 90, 120), 0, 3)
	end
	local led = frame(holder, 0.42, 0.08, 0.16, 0.06, CYAN, 0, 2)
	roundify(led)
end

-- Langue de flamme : base ronde + pointe (ovale étiré tourné)
local function flameTongue(holder: Instance, cx: number, h: number, w: number, color: Color3, z: number)
	oval(holder, cx, 1 - h * 0.18, w, h * 0.5, color, 0, 0, z)
	oval(holder, cx + w * 0.08, 1 - h * 0.55, w * 0.55, h * 0.8, color, 0, 12, z)
end

SKINS.Flames = function(holder)
	for index = 0, 6 do
		local cx = 0.04 + index * 0.155
		local h = 0.7 + ((index * 37) % 5) * 0.08
		flameTongue(holder, cx, h, 0.2, RED, 1)
		flameTongue(holder, cx, h * 0.8, 0.15, ORANGE, 2)
		flameTongue(holder, cx, h * 0.5, 0.09, YELLOW, 3)
	end
end

SKINS.Lava = function(holder)
	local rock = { rgb(70, 50, 54), rgb(96, 66, 66), rgb(60, 40, 46) }
	for index, spec in ipairs({ { 0.12, 0.3, 0.3, 0.7 }, { 0.42, 0.7, 0.34, 0.8 }, { 0.72, 0.28, 0.32, 0.7 }, { 0.95, 0.78, 0.26, 0.8 }, { 0.15, 0.95, 0.26, 0.5 } }) do
		oval(holder, spec[1], spec[2], spec[3], spec[4], rock[index % #rock + 1], 0, (index - 2) * 12, 1)
	end
	-- fissures lumineuses
	for index, spec in ipairs({ { 0.28, 0.5, 0.3, 30 }, { 0.58, 0.45, 0.28, -40 }, { 0.84, 0.55, 0.26, 55 }, { 0.3, 0.1, 0.2, -10 }, { 0.62, 0.95, 0.24, 10 } }) do
		local crack = frame(holder, spec[1], spec[2], spec[3], 0.06, rgb(255, 130, 50), 0, 2)
		crack.AnchorPoint = Vector2.new(0.5, 0.5)
		crack.Rotation = spec[4]
		roundify(crack)
		local glow = oval(holder, spec[1], spec[2], spec[3] * 1.1, 0.3, rgb(255, 170, 60), 0.7, spec[4], 2)
		local _ = glow
		local _i = index
	end
	dot(holder, 0.5, 0.2, 0.14, YELLOW, 0.2, 3)
	dot(holder, 0.1, 0.62, 0.1, YELLOW, 0.3, 3)
end

SKINS.Galaxy = function(holder)
	oval(holder, 0.5, 0.5, 0.9, 0.7, rgb(255, 120, 220), 0.7, -12, 1)
	oval(holder, 0.45, 0.5, 0.6, 0.35, rgb(120, 220, 255), 0.65, -12, 2)
	oval(holder, 0.5, 0.5, 0.25, 0.3, WHITE, 0.55, 0, 3)
	for index = 1, 16 do
		local x = (index * 0.618) % 1
		local y = (index * 0.377 + 0.1) % 1
		dot(holder, x, y, index % 4 == 0 and 0.1 or 0.05, WHITE, index % 3 == 0 and 0 or 0.3, 4)
	end
	local planet = dot(holder, 0.86, 0.3, 0.3, rgb(255, 180, 110), 0, 4)
	local ringBand = frame(planet, 0.5, 0.55, 1.8, 0.14, rgb(255, 230, 170), 0.1, 2)
	ringBand.AnchorPoint = Vector2.new(0.5, 0.5)
	ringBand.Rotation = -18
	roundify(ringBand)
end

SKINS.Circuit = function(holder)
	local traces = {
		{ 0, 0.25, 0.3, 0.035 }, { 0.3, 0.25, 0.012, 0.3 }, { 0.3, 0.55, 0.2, 0.035 },
		{ 0.7, 0.2, 0.3, 0.035 }, { 0.7, 0.2, 0.012, 0.45 }, { 0.62, 0.65, 0.09, 0.035 },
		{ 0, 0.8, 0.18, 0.035 }, { 0.18, 0.8, 0.012, 0.2 }, { 0.85, 0.82, 0.15, 0.035 }, { 0.85, 0.65, 0.012, 0.2 },
	}
	for index, t in ipairs(traces) do
		frame(holder, t[1], t[2], t[3], t[4], index % 2 == 0 and CYAN or LIME, 0.15, 1)
	end
	for _, n in ipairs({ { 0.5, 0.565 }, { 0.3, 0.255 }, { 0.62, 0.665 }, { 0.18, 0.99 }, { 0.855, 0.655 }, { 0.705, 0.215 } }) do
		dot(holder, n[1], n[2], 0.16, CYAN, 0, 2)
		dot(holder, n[1], n[2], 0.07, WHITE, 0, 3)
	end
	local chip = frame(holder, 0.42, 0.08, 0.16, 0.3, DARKER, 0, 2)
	roundify(chip, UDim.new(0, 3))
	local stroke = Instance.new("UIStroke")
	stroke.Color = MAGENTA
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = chip
end

-- Pose (ou retire) le motif du bouton
function CosmeticArt.ApplySkin(button: GuiObject, cosmetic: any?, radius: number?, zIndex: number?)
	local old = button:FindFirstChild("SkinArt")
	if old then
		old:Destroy()
	end
	local pattern = cosmetic and cosmetic.Pattern
	local painter = type(pattern) == "string" and SKINS[pattern] or nil
	if not painter then
		return
	end
	-- CanvasGroup : le motif est découpé aux coins arrondis du bouton
	local holder = Instance.new("CanvasGroup")
	holder.Name = "SkinArt"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = zIndex or button.ZIndex
	holder.GroupTransparency = 0.12
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = holder
	local ok, err = pcall(painter, holder)
	if not ok then
		warn("[CosmeticArt] Motif " .. tostring(pattern) .. " : " .. tostring(err))
		holder:Destroy()
		return
	end
	holder.Parent = button
end

return CosmeticArt
