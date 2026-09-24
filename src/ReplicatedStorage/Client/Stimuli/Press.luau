--[[
	Press (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Press

	Une presse hydraulique qui écrase des trucs, en boucle, et c'est très
	satisfaisant :
	  - un objet arrive par le tapis roulant (piles de macarons colorés,
	    pastèque, canard en plastique, gâteau, éponge... et des objets
	    propres à chaque palier de la presse) ;
	  - le piston descend, l'objet se tasse, la machine tremble, le
	    manomètre grimpe dans le rouge... puis CRUNCH ! (écrasement avec
	    rebond, onde de choc, éclats, vapeur, secousse de toute la carte,
	    son "Crush", onomatopée) ;
	  - la galette part sur le tas à gauche, qui finit à la poubelle.

	Paliers visuels selon le niveau de l'amélioration "Presse hydraulique"
	(ctx.GetLevel("Press")) :
	  1-2 bois & corde, 3-4 acier, 5-6 industrielle (manomètres, tuyaux,
	  vapeur, gyrophare), 7-8 or (reflets, étincelles dorées),
	  9-10 diamant néon (contours lumineux, gerbes d'étincelles).
	Une pastille "Niv. X" affiche le niveau et le nom du palier ; changer
	de palier joue une petite animation. La vitesse augmente aussi avec le
	niveau.

	Avec "Presse turbo" (Feature PressStart), un gros bouton START rouge
	permet d'écraser soi-même : Interact("Press") (recharge côté serveur,
	compte à rebours affiché) et le bonus s'affiche via OnBonus("Press").
]]

local Debris = game:GetService("Debris")

local Press = {}
Press.Slot = "C3"

----------------------------------------------------------------------
-- Géométrie (pixels "design" dans un slot de 384 x 268)
----------------------------------------------------------------------
local MX = 170 -- centre de la machine
local ANVIL_Y = 228 -- dessus de l'enclume (bas des objets)
local PLATE_TOP = 64 -- position haute du plateau
local PLATE_H = 22
local PLATE_W = 176
local FLAT_H = 12 -- hauteur d'un objet écrasé
local BIN_X = 32 -- centre de la poubelle
local BIN_TOP = 196
local PILE_MAX = 8
local QUEUE_X = { 322, 360 } -- places dans la file d'attente
local QUEUE_Y = 222 -- dessus du tapis roulant
local QUEUE_SIZE = 34
local BELT_STRIPES_W = 110 -- bande de rayures du tapis (10 rayures, période = 1/5)
local COLUMN_X = { MX - 110, MX + 94 }

-- Durées de base (niveau 1), divisées par le facteur de vitesse
local DURATIONS = {
	Load = 0.55,
	Descend = 1.25,
	Squeeze = 0.5,
	Crunch = 0.08,
	Hold = 0.45,
	Rise = 0.85,
}

local MACARON_COLORS = {
	Color3.fromRGB(255, 160, 192), -- framboise
	Color3.fromRGB(172, 222, 140), -- pistache
	Color3.fromRGB(192, 162, 240), -- violette
	Color3.fromRGB(255, 228, 120), -- citron
	Color3.fromRGB(156, 100, 74), -- chocolat
	Color3.fromRGB(255, 190, 132), -- fleur d'oranger
	Color3.fromRGB(150, 206, 255), -- myrtille... bleue
	Color3.fromRGB(236, 86, 124), -- fraise
}

local MACARON_WORDS = { "CRUNCH !", "SCRONCH !", "CRAC !", "Macaron à plat !", "CROUNCH !" }

local EMOJI_ITEMS = {
	{ Icon = "🍉", Color = Color3.fromRGB(235, 70, 80), Words = { "SPLOTCH !", "SCHPLOUF !" } },
	{ Icon = "🥫", Color = Color3.fromRGB(205, 60, 45), Words = { "CRONCH !", "CLONK !" } },
	{ Icon = "🧸", Color = Color3.fromRGB(190, 130, 70), Words = { "POUF !", "Pardon nounours..." } },
	{ Icon = "🎂", Color = Color3.fromRGB(255, 190, 215), Words = { "SPLAF !", "Joyeux écrasement !" } },
	{ Icon = "🥚", Color = Color3.fromRGB(255, 214, 60), Words = { "CRAC !", "Omelette !" } },
	{ Icon = "🍩", Color = Color3.fromRGB(255, 140, 190), Words = { "SCRONCH !", "Donut plat !" } },
	{ Icon = "🧊", Color = Color3.fromRGB(170, 225, 255), Words = { "CRIIIC !", "Glace pilée !" } },
	{ Icon = "🎈", Color = Color3.fromRGB(240, 60, 80), Words = { "POP !!!", "BANG !" }, Special = "Pop" },
	{ Icon = "🦆", Color = Color3.fromRGB(255, 212, 40), Words = { "POUIC !", "COIN !" } },
	{ Icon = "🍅", Color = Color3.fromRGB(230, 40, 30), Words = { "SPLOTCH !", "Ketchup maison !" } },
	{ Icon = "🧽", Color = Color3.fromRGB(250, 220, 70), Words = { "SCHLURP !" }, Special = "Sponge" },
	{ Icon = "🍔", Color = Color3.fromRGB(200, 120, 50), Words = { "SMASH !", "Smash burger !" } },
	{ Icon = "📦", Color = Color3.fromRGB(190, 140, 80), Words = { "CRAC !", "Colis livré (à plat)" } },
	{ Icon = "🍋", Color = Color3.fromRGB(255, 230, 60), Words = { "PSCHIT !", "Limonade !" } },
}

----------------------------------------------------------------------
-- Paliers visuels
----------------------------------------------------------------------
local function seq(...: Color3): ColorSequence
	local colors = { ... }
	local keypoints = {}
	for i, color in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), color))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end
	return ColorSequence.new(keypoints)
end

-- Rayures nettes (dégradé à bords francs)
local function stripes(n: number, c1: Color3, c2: Color3): ColorSequence
	local keypoints = {}
	for i = 0, n - 1 do
		local color = (i % 2 == 0) and c1 or c2
		table.insert(keypoints, ColorSequenceKeypoint.new(i / n, color))
		table.insert(keypoints, ColorSequenceKeypoint.new((i + 1) / n - 0.002, color))
	end
	keypoints[#keypoints] = ColorSequenceKeypoint.new(1, keypoints[#keypoints].Value)
	return ColorSequence.new(keypoints)
end

local rgb = Color3.fromRGB

type TierStyle = {
	Name: string,
	Icon: string,
	Shout: string,
	Chip: Color3,
	ChipText: Color3,
	CardTop: Color3,
	CardBottom: Color3,
	CardStroke: Color3,
	Title: Color3,
	Column: ColorSequence,
	Outline: Color3,
	Beam: ColorSequence,
	BeamRotation: number,
	Housing: ColorSequence,
	Rod: ColorSequence,
	RodRotation: number,
	Plate: ColorSequence,
	Stripe: ColorSequence,
	Base: ColorSequence,
	Debris: { Color3 },
	Items: { any },
}

local TIERS: { TierStyle } = {
	{
		Name = "Bois & corde",
		Shout = "PRESSE EN BOIS !",
		Icon = "🪵",
		Chip = rgb(170, 112, 64),
		ChipText = rgb(255, 255, 255),
		CardTop = rgb(255, 249, 238),
		CardBottom = rgb(236, 218, 190),
		CardStroke = rgb(96, 62, 34),
		Title = rgb(80, 50, 26),
		Column = seq(rgb(140, 92, 54), rgb(200, 146, 96), rgb(122, 78, 44)),
		Outline = rgb(92, 58, 32),
		Beam = stripes(8, rgb(186, 128, 78), rgb(168, 112, 66)),
		BeamRotation = 90,
		Housing = seq(rgb(150, 98, 58), rgb(110, 70, 40)),
		Rod = stripes(8, rgb(226, 196, 138), rgb(186, 150, 92)),
		RodRotation = 60,
		Plate = seq(rgb(206, 150, 98), rgb(130, 84, 48)),
		Stripe = stripes(6, rgb(226, 196, 138), rgb(186, 150, 92)),
		Base = seq(rgb(170, 116, 70), rgb(96, 60, 34)),
		Debris = { rgb(170, 112, 64), rgb(226, 196, 138) },
		Items = {
			{ Icon = "🥥", Color = rgb(130, 86, 52), Words = { "CRAC !", "Noix de coco ouverte !" } },
			{ Icon = "🥖", Color = rgb(222, 170, 92), Words = { "CROUSTI !", "Baguette à plat !" } },
			{ Icon = "🌰", Color = rgb(150, 90, 50), Words = { "CRIC !", "Châtaigne pilée !" } },
		},
	},
	{
		Name = "Acier",
		Shout = "PRESSE EN ACIER !",
		Icon = "⚙️",
		Chip = rgb(96, 104, 120),
		ChipText = rgb(255, 255, 255),
		CardTop = rgb(250, 251, 253),
		CardBottom = rgb(214, 221, 232),
		CardStroke = rgb(30, 30, 36),
		Title = rgb(24, 24, 30),
		Column = seq(rgb(150, 156, 170), rgb(250, 252, 255), rgb(120, 126, 140)),
		Outline = rgb(58, 62, 74),
		Beam = stripes(10, rgb(255, 200, 30), rgb(34, 34, 40)),
		BeamRotation = 35,
		Housing = seq(rgb(170, 176, 190), rgb(70, 74, 88)),
		Rod = seq(rgb(190, 196, 206), rgb(255, 255, 255), rgb(170, 176, 188)),
		RodRotation = 0,
		Plate = seq(rgb(160, 168, 185), rgb(70, 74, 88)),
		Stripe = stripes(10, rgb(255, 200, 30), rgb(34, 34, 40)),
		Base = seq(rgb(140, 146, 160), rgb(50, 54, 64)),
		Debris = { rgb(200, 205, 215) },
		Items = {
			{ Icon = "🔩", Color = rgb(150, 150, 165), Words = { "CLONK !", "Boulon aplati !" } },
			{ Icon = "🥫", Color = rgb(205, 60, 45), Words = { "CRONCH !", "Conserve compacte !" } },
		},
	},
	{
		Name = "Industrielle",
		Shout = "PRESSE INDUSTRIELLE !",
		Icon = "🏭",
		Chip = rgb(232, 110, 30),
		ChipText = rgb(255, 255, 255),
		CardTop = rgb(236, 240, 244),
		CardBottom = rgb(176, 186, 198),
		CardStroke = rgb(40, 44, 52),
		Title = rgb(30, 34, 40),
		Column = seq(rgb(88, 96, 110), rgb(160, 168, 182), rgb(66, 72, 84)),
		Outline = rgb(36, 40, 48),
		Beam = stripes(10, rgb(255, 130, 30), rgb(30, 32, 38)),
		BeamRotation = 35,
		Housing = seq(rgb(110, 118, 132), rgb(44, 48, 58)),
		Rod = seq(rgb(170, 176, 188), rgb(240, 244, 250), rgb(140, 146, 158)),
		RodRotation = 0,
		Plate = seq(rgb(120, 128, 144), rgb(44, 48, 58)),
		Stripe = stripes(10, rgb(255, 130, 30), rgb(30, 32, 38)),
		Base = seq(rgb(100, 106, 120), rgb(34, 38, 46)),
		Debris = { rgb(120, 126, 140), rgb(255, 150, 60) },
		Items = {
			{ Icon = "🚗", Color = rgb(220, 50, 50), Words = { "CRUNCH !", "Compression auto !" } },
			{ Icon = "📺", Color = rgb(90, 90, 104), Words = { "KRZZT !", "Écran plat !" } },
			{ Icon = "🧯", Color = rgb(220, 40, 40), Words = { "PSCHHHT !", "Extincteur éteint !" } },
		},
	},
	{
		Name = "Or massif",
		Shout = "PRESSE EN OR !",
		Icon = "👑",
		Chip = rgb(255, 194, 26),
		ChipText = rgb(70, 44, 0),
		CardTop = rgb(255, 252, 236),
		CardBottom = rgb(255, 226, 150),
		CardStroke = rgb(150, 100, 10),
		Title = rgb(100, 64, 0),
		Column = seq(rgb(214, 150, 20), rgb(255, 244, 170), rgb(196, 130, 10)),
		Outline = rgb(150, 100, 10),
		Beam = stripes(10, rgb(255, 214, 70), rgb(255, 246, 200)),
		BeamRotation = 35,
		Housing = seq(rgb(255, 230, 130), rgb(200, 140, 20)),
		Rod = seq(rgb(230, 180, 60), rgb(255, 250, 210), rgb(210, 150, 30)),
		RodRotation = 0,
		Plate = seq(rgb(255, 236, 140), rgb(190, 126, 10)),
		Stripe = stripes(10, rgb(255, 250, 220), rgb(230, 170, 30)),
		Base = seq(rgb(250, 210, 90), rgb(160, 100, 10)),
		Debris = { rgb(255, 214, 70), rgb(255, 246, 200) },
		Items = {
			{ Icon = "🏆", Color = rgb(255, 196, 40), Words = { "CLANG !", "Trophée à plat !" } },
			{ Icon = "💰", Color = rgb(230, 190, 60), Words = { "KA-CHING !", "Pluie de pièces !" } },
			{ Icon = "👑", Color = rgb(255, 204, 40), Words = { "CRONCH !", "Couronne aplatie !" } },
		},
	},
	{
		Name = "Diamant néon",
		Shout = "PRESSE DIAMANT !",
		Icon = "💎",
		Chip = rgb(0, 214, 255),
		ChipText = rgb(10, 20, 40),
		CardTop = rgb(40, 26, 70),
		CardBottom = rgb(12, 10, 26),
		CardStroke = rgb(0, 230, 255),
		Title = rgb(255, 255, 255),
		Column = seq(rgb(150, 240, 255), rgb(255, 255, 255), rgb(190, 150, 255)),
		Outline = rgb(0, 230, 255),
		Beam = stripes(10, rgb(0, 230, 255), rgb(255, 60, 200)),
		BeamRotation = 35,
		Housing = seq(rgb(200, 250, 255), rgb(120, 90, 220)),
		Rod = seq(rgb(190, 250, 255), rgb(255, 255, 255), rgb(170, 140, 255)),
		RodRotation = 0,
		Plate = seq(rgb(190, 250, 255), rgb(110, 80, 210)),
		Stripe = stripes(10, rgb(0, 230, 255), rgb(255, 60, 200)),
		Base = seq(rgb(80, 60, 150), rgb(20, 14, 40)),
		Debris = { rgb(0, 230, 255), rgb(255, 60, 200), rgb(255, 255, 255) },
		Items = {
			{ Icon = "💎", Color = rgb(120, 220, 255), Words = { "CRIIING !", "Diamant ?? Non, du verre." } },
			{ Icon = "🔮", Color = rgb(190, 120, 255), Words = { "PSHIIIT !", "Avenir écrasé !" } },
			{ Icon = "🌟", Color = rgb(255, 230, 90), Words = { "SHIIING !", "Étoile filante... à plat" } },
		},
	},
}

local function tierForLevel(level: number): number
	return math.clamp(math.floor((math.max(1, level) - 1) / 2) + 1, 1, #TIERS)
end

local function mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

local function easeInOut(t: number): number
	return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- Rebond façon "Back" (dépasse puis revient) : 0 -> 1
local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function Press.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()
	local cooldown = (ctx.Config.Interactions.Press and ctx.Config.Interactions.Press.Cooldown) or 3

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function currentLevel(): number
		return math.max(1, ctx.GetLevel("Press") or 1)
	end

	local function speedFactor(): number
		return 1 + (currentLevel() - 1) * 0.2
	end

	------------------------------------------------------------------
	-- Carte (secouée en entier au CRUNCH) + "rig" (la machine)
	------------------------------------------------------------------
	local card = Create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = container,
	})
	UIUtil.Corner(card, 18)
	local cardStroke = UIUtil.Stroke(card, Theme.Colors.CardBorder, 2)
	local cardGradient = UIUtil.Gradient(card, ColorSequence.new(Color3.fromRGB(250, 251, 253), Color3.fromRGB(214, 221, 232)), 90)

	local rig = Create("Frame", {
		Name = "Rig",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})

	local function box(props: { [string]: any }, radius: (number | UDim)?): Frame
		props.BorderSizePixel = 0
		if props.Parent == nil then
			props.Parent = rig
		end
		local frame = Create("Frame", props)
		if radius then
			UIUtil.Corner(frame, radius)
		end
		return frame
	end

	-- En-tête : titre, pastille de palier "Niv. X", compteur, vitesse
	local titleLabel = UIUtil.Label({
		Text = "🗜️ PRESSE",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.fromOffset(96, 20),
		MaxTextSize = 16,
		ZIndex = 12,
		Parent = card,
	})
	local tierChip = UIUtil.Chip({
		Name = "TierChip",
		Text = "",
		Color = TIERS[1].Chip,
		TextColor3 = TIERS[1].ChipText,
		Height = 19,
		TextSize = 11,
		ZIndex = 12,
		Parent = card,
	})
	tierChip.Position = UDim2.fromOffset(110, 8)
	local tierChipLabel = tierChip:FindFirstChild("Label") :: TextLabel?
	local tierChipScale = Create("UIScale", { Parent = tierChip })
	local counterLabel = UIUtil.Label({
		Text = "💥 0",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 5),
		Size = UDim2.fromOffset(80, 20),
		MaxTextSize = 17,
		ZIndex = 12,
		Parent = card,
	})
	local counterScale = Create("UIScale", { Parent = counterLabel })
	local speedLabel = UIUtil.Label({
		Text = "⚡ x1",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.Orange,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 24),
		Size = UDim2.fromOffset(60, 12),
		MaxTextSize = 11,
		ZIndex = 12,
		Parent = card,
	})

	------------------------------------------------------------------
	-- La machine (couleurs appliquées par applyTier)
	------------------------------------------------------------------
	local white = Color3.new(1, 1, 1)
	local hazardBlack = Color3.fromRGB(34, 34, 40)

	-- Colonnes
	local columns: { { Frame: Frame, Gradient: UIGradient, Stroke: UIStroke } } = {}
	for _, x in ipairs(COLUMN_X) do
		local column = box({ Position = UDim2.fromOffset(x, 40), Size = UDim2.fromOffset(16, ANVIL_Y - 40), BackgroundColor3 = white, ZIndex = 2 }, 3)
		local gradient = UIUtil.Gradient(column, TIERS[2].Column, 0)
		local stroke = UIUtil.Stroke(column, TIERS[2].Outline, 1, 0.4)
		table.insert(columns, { Frame = column, Gradient = gradient, Stroke = stroke })
	end

	-- Traverse du haut (coupe ses reflets)
	local beam = box({ Position = UDim2.fromOffset(MX - 120, 34), Size = UDim2.fromOffset(240, 26), BackgroundColor3 = white, ClipsDescendants = true, ZIndex = 7 }, 6)
	local beamGradient = UIUtil.Gradient(beam, TIERS[2].Beam, 35)
	local beamStroke = UIUtil.Stroke(beam, hazardBlack, 2)

	-- Vérin (boîtier + tige)
	local housing = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, 56), Size = UDim2.fromOffset(46, 16), BackgroundColor3 = white, ZIndex = 8 }, 4)
	local housingGradient = UIUtil.Gradient(housing, TIERS[2].Housing, 90)
	local rod = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, 66), Size = UDim2.fromOffset(18, 10), BackgroundColor3 = white, ZIndex = 5 })
	local rodGradient = UIUtil.Gradient(rod, TIERS[2].Rod, 0)

	-- Plateau (+ éclair blanc au moment du choc)
	local plate = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, PLATE_TOP), Size = UDim2.fromOffset(PLATE_W, PLATE_H), BackgroundColor3 = white, ZIndex = 6 }, 5)
	local plateGradient = UIUtil.Gradient(plate, TIERS[2].Plate, 90)
	local plateStroke = UIUtil.Stroke(plate, TIERS[2].Outline, 1, 0.4)
	local plateStripe = box({ Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 0, 6), BackgroundColor3 = white, ZIndex = 7, Parent = plate }, 2)
	local plateStripeGradient = UIUtil.Gradient(plateStripe, TIERS[2].Stripe, 35)
	local plateFlash = box({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = white, BackgroundTransparency = 1, ZIndex = 8, Parent = plate }, 5)

	-- Manomètre (aiguille qui monte dans le rouge)
	local gauge = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX + 84, 47), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = white, ZIndex = 9 }, 11)
	local gaugeStroke = UIUtil.Stroke(gauge, hazardBlack, 2)
	box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.72, 0.28), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Theme.Colors.Red, ZIndex = 10, Parent = gauge }, 3)
	local needlePivot = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = gauge,
	})
	box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 0.42, 0), BackgroundColor3 = Theme.Colors.Red, ZIndex = 11, Parent = needlePivot })

	-- Socle + enclume
	local base = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, ANVIL_Y), Size = UDim2.fromOffset(250, 28), BackgroundColor3 = white, ZIndex = 3 }, 5)
	local baseGradient = UIUtil.Gradient(base, TIERS[2].Base, 90)
	local baseStripe = box({ Position = UDim2.fromOffset(4, 0), Size = UDim2.new(1, -8, 0, 5), BackgroundColor3 = white, ZIndex = 4, Parent = base })
	local baseStripeGradient = UIUtil.Gradient(baseStripe, TIERS[2].Stripe, 35)
	local led = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -14, 0.6, 0), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Theme.Colors.Green, ZIndex = 5, Parent = base }, 4)

	-- Onde de choc (ellipse réutilisée)
	local shockRing = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX, ANVIL_Y), Size = UDim2.fromOffset(20, 6), BackgroundTransparency = 1, ZIndex = 9 }, UDim.new(1, 0))
	local shockStroke = UIUtil.Stroke(shockRing, white, 3, 1)

	-- Poubelle (à gauche)
	local bin = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(BIN_X, BIN_TOP), Size = UDim2.fromOffset(48, 256 - BIN_TOP), BackgroundColor3 = Color3.fromRGB(120, 170, 130), ZIndex = 5 }, 5)
	UIUtil.Gradient(bin, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)), 0)
	box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -3), Size = UDim2.new(1, 6, 0, 7), BackgroundColor3 = Color3.fromRGB(80, 130, 92), ZIndex = 6, Parent = bin }, 3)
	UIUtil.Label({
		Text = "♻️",
		Position = UDim2.fromScale(0.15, 0.3),
		Size = UDim2.fromScale(0.7, 0.45),
		MaxTextSize = 26,
		ZIndex = 6,
		Parent = bin,
	})

	-- Tapis roulant (à droite) : rayures qui défilent
	local steel = Color3.fromRGB(96, 104, 120)
	local belt = box({ Position = UDim2.fromOffset(296, QUEUE_Y), Size = UDim2.fromOffset(84, 10), BackgroundColor3 = hazardBlack, ClipsDescendants = true, ZIndex = 3 })
	local beltStripes = box({ Size = UDim2.fromOffset(BELT_STRIPES_W, 10), BackgroundColor3 = white, ZIndex = 3, Parent = belt })
	UIUtil.Gradient(beltStripes, stripes(10, Color3.fromRGB(78, 82, 96), Color3.fromRGB(40, 42, 50)), 0)
	for _, x in ipairs({ 302, 374 }) do
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, QUEUE_Y + 5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = steel, ZIndex = 4 }, 6)
	end
	box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(338, QUEUE_Y + 10), Size = UDim2.fromOffset(8, 256 - QUEUE_Y - 10), BackgroundColor3 = steel, ZIndex = 2 })

	-- Décors propres au palier (reconstruits à chaque changement de palier)
	local decorBack = Create("Frame", { Name = "DecorBack", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = rig })
	local decorFront = Create("Frame", { Name = "DecorFront", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9, Parent = rig })

	------------------------------------------------------------------
	-- Bouton START (Presse turbo) ou panneau d'avertissement
	------------------------------------------------------------------
	local warning = Create("Frame", {
		Name = "Warning",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(338, 44),
		Size = UDim2.fromOffset(78, 76),
		BackgroundColor3 = Theme.Colors.Yellow,
		BorderSizePixel = 0,
		ZIndex = 12,
		Parent = rig,
	})
	UIUtil.Corner(warning, 8)
	UIUtil.Stroke(warning, hazardBlack, 2)
	UIUtil.Label({
		Text = "⚠️",
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 30),
		MaxTextSize = 28,
		ZIndex = 13,
		Parent = warning,
	})
	UIUtil.Label({
		Text = "NE PAS METTRE LES DOIGTS",
		Font = Theme.Fonts.Title,
		TextColor3 = hazardBlack,
		Position = UDim2.fromOffset(4, 36),
		Size = UDim2.new(1, -8, 0, 34),
		MaxTextSize = 12,
		TextWrapped = true,
		ZIndex = 13,
		Parent = warning,
	})

	local startGroup = Create("Frame", {
		Name = "StartGroup",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(338, 38),
		Size = UDim2.fromOffset(80, 96),
		BackgroundTransparency = 1,
		ZIndex = 12,
		Visible = false,
		Parent = rig,
	})
	box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(40, 70), Size = UDim2.fromOffset(76, 16), BackgroundColor3 = hazardBlack, ZIndex = 1, Parent = startGroup }, 6)
	local buttonSide = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(40, 12), Size = UDim2.fromOffset(62, 62), BackgroundColor3 = Color3.fromRGB(150, 16, 24), ZIndex = 2, Parent = startGroup }, 31)
	local startButton = Create("TextButton", {
		Name = "Start",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(40, 4),
		Size = UDim2.fromOffset(62, 62),
		BackgroundColor3 = Theme.Colors.Red,
		AutoButtonColor = false,
		Font = Enum.Font.LuckiestGuy,
		Text = "START",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 17,
		ZIndex = 3,
		Parent = startGroup,
	})
	UIUtil.Corner(startButton, UDim.new(1, 0))
	UIUtil.Stroke(startButton, Color3.fromRGB(120, 10, 18), 2)
	UIUtil.Gradient(startButton, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)), 90)
	local startTextStroke = UIUtil.Stroke(startButton, Color3.fromRGB(110, 0, 10), 1.5)
	startTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	-- Reflet
	box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.08), Size = UDim2.fromScale(0.55, 0.22), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, ZIndex = 4, Parent = startButton }, 8)

	local function refreshStartVisibility()
		local owned = ctx.HasFeature("PressStart")
		startGroup.Visible = owned
		warning.Visible = not owned
	end
	refreshStartVisibility()
	if ctx.State.FeaturesChanged then
		ctx.Connect(ctx.State.FeaturesChanged, refreshStartVisibility)
	end

	------------------------------------------------------------------
	-- Paliers : couleurs + décors
	------------------------------------------------------------------
	local tierIndex = 0
	local shownLevel = 0
	-- Éléments animés du palier courant (voir OnRender)
	local tierAnim = {
		Needles = {} :: { Frame },
		Twinkles = {} :: { TextLabel },
		Beacon = nil :: Frame?,
		Shine = nil :: Frame?,
		Glow = nil :: Frame?,
		SteamX = 0,
		SteamTimer = 1,
	}

	local function dot(parent: Instance, x: number, y: number, size: number, color: Color3, z: number): Frame
		return box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size, size), BackgroundColor3 = color, ZIndex = z, Parent = parent }, UDim.new(1, 0))
	end

	local function buildDecor(index: number)
		decorBack:ClearAllChildren()
		decorFront:ClearAllChildren()
		if tierAnim.Shine then
			tierAnim.Shine:Destroy()
		end
		tierAnim.Needles = {}
		tierAnim.Twinkles = {}
		tierAnim.Beacon = nil
		tierAnim.Shine = nil
		tierAnim.Glow = nil

		if index == 1 then
			-- Bois & corde : cordes enroulées sur les colonnes, clous sur la traverse
			for _, x in ipairs(COLUMN_X) do
				for _, y in ipairs({ 78, 132, 186 }) do
					local rope = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + 8, y), Size = UDim2.fromOffset(22, 8), BackgroundColor3 = white, ZIndex = 1, Parent = decorBack }, 3)
					UIUtil.Gradient(rope, stripes(6, Color3.fromRGB(230, 200, 140), Color3.fromRGB(180, 142, 86)), 60)
				end
			end
			for _, x in ipairs({ MX - 108, MX - 60, MX + 60, MX + 108 }) do
				dot(decorFront, x, 47, 4, Color3.fromRGB(70, 60, 56), 1)
			end
		elseif index == 2 then
			-- Acier : rivets
			for i = 0, 5 do
				dot(decorFront, MX - 110 + i * 44, 38, 4, Color3.fromRGB(230, 232, 240), 1)
			end
		elseif index == 3 then
			-- Industrielle : tuyau + vanne (derrière), manomètres + gyrophare (devant)
			box({ Position = UDim2.fromOffset(36, 70), Size = UDim2.fromOffset(8, 118), BackgroundColor3 = Color3.fromRGB(110, 118, 132), ZIndex = 1, Parent = decorBack }, 3)
			box({ Position = UDim2.fromOffset(36, 70), Size = UDim2.fromOffset(28, 8), BackgroundColor3 = Color3.fromRGB(110, 118, 132), ZIndex = 1, Parent = decorBack }, 3)
			local valve = dot(decorBack, 40, 128, 16, Color3.fromRGB(220, 50, 40), 2)
			valve.BackgroundTransparency = 1
			UIUtil.Stroke(valve, Color3.fromRGB(220, 50, 40), 3)
			box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 3), BackgroundColor3 = Color3.fromRGB(220, 50, 40), ZIndex = 2, Parent = valve })
			tierAnim.SteamX = 40
			for _, x in ipairs({ MX - 92, MX - 66 }) do
				local small = dot(decorFront, x, 47, 16, white, 1)
				UIUtil.Stroke(small, hazardBlack, 2)
				local pivot = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = small })
				box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 0.4, 0), BackgroundColor3 = hazardBlack, ZIndex = 2, Parent = pivot })
				table.insert(tierAnim.Needles, pivot)
			end
			local beacon = box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(MX + 40, 35), Size = UDim2.fromOffset(12, 8), BackgroundColor3 = Color3.fromRGB(255, 140, 20), ZIndex = 1, Parent = decorFront }, 4)
			tierAnim.Beacon = beacon
		elseif index == 4 then
			-- Or : reflet qui passe sur la traverse + étoiles scintillantes
			local shine = box({ Position = UDim2.fromOffset(-40, 0), Size = UDim2.new(0, 34, 1, 0), BackgroundColor3 = white, ZIndex = 8, Parent = beam })
			local shineGradient = UIUtil.Gradient(shine, ColorSequence.new(white), 0)
			shineGradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			tierAnim.Shine = shine
			for _, pos in ipairs({ Vector2.new(MX - 118, 84), Vector2.new(MX + 118, 120), Vector2.new(MX - 100, 170), Vector2.new(MX + 104, 196), Vector2.new(MX, 30) }) do
				local star = UIUtil.Label({
					Text = "✦",
					Font = Theme.Fonts.Title,
					TextColor3 = Color3.fromRGB(255, 220, 90),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(pos.X, pos.Y),
					Size = UDim2.fromOffset(14, 14),
					MaxTextSize = 14,
					ZIndex = 2,
					Parent = decorFront,
				})
				table.insert(tierAnim.Twinkles, star)
			end
		elseif index == 5 then
			-- Diamant néon : reflet, gemmes sur la traverse, lueur sous l'enclume
			local shine = box({ Position = UDim2.fromOffset(-40, 0), Size = UDim2.new(0, 28, 1, 0), BackgroundColor3 = white, ZIndex = 8, Parent = beam })
			local shineGradient = UIUtil.Gradient(shine, ColorSequence.new(white), 0)
			shineGradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			tierAnim.Shine = shine
			for _, x in ipairs({ MX - 100, MX + 100 }) do
				local gem = UIUtil.Label({
					Text = "💎",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(x, 47),
					Size = UDim2.fromOffset(18, 18),
					MaxTextSize = 16,
					ZIndex = 2,
					Parent = decorFront,
				})
				table.insert(tierAnim.Twinkles, gem)
			end
			local glow = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX, ANVIL_Y + 2), Size = UDim2.fromOffset(230, 10), BackgroundColor3 = Color3.fromRGB(0, 230, 255), BackgroundTransparency = 0.5, ZIndex = 1, Parent = decorBack }, UDim.new(1, 0))
			tierAnim.Glow = glow
		end
	end

	local function applyTier(index: number)
		local style = TIERS[index]
		cardGradient.Color = ColorSequence.new(style.CardTop, style.CardBottom)
		cardStroke.Color = style.CardStroke
		titleLabel.TextColor3 = style.Title
		counterLabel.TextColor3 = style.Title
		for _, column in ipairs(columns) do
			column.Gradient.Color = style.Column
			column.Stroke.Color = style.Outline
			column.Stroke.Thickness = index == 5 and 2 or 1
			column.Stroke.Transparency = index == 5 and 0 or 0.4
		end
		beamGradient.Color = style.Beam
		beamGradient.Rotation = style.BeamRotation
		beamStroke.Color = index == 5 and style.Outline or mix(style.Outline, hazardBlack, 0.4)
		housingGradient.Color = style.Housing
		rodGradient.Color = style.Rod
		rodGradient.Rotation = style.RodRotation
		plateGradient.Color = style.Plate
		plateStroke.Color = style.Outline
		plateStroke.Transparency = index == 5 and 0 or 0.4
		plateStroke.Thickness = index == 5 and 2 or 1
		plateStripeGradient.Color = style.Stripe
		baseGradient.Color = style.Base
		baseStripeGradient.Color = style.Stripe
		gaugeStroke.Color = index == 5 and style.Outline or hazardBlack
		tierChip.BackgroundColor3 = style.Chip
		buildDecor(index)
	end

	-- Petit flash blanc sur toute la carte (changement de palier)
	local function flashCard()
		local flash = Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = white,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ZIndex = 20,
			Parent = card,
		})
		UIUtil.Corner(flash, 18)
		UIUtil.Tween(flash, 0.6, { BackgroundTransparency = 1 })
		Debris:AddItem(flash, 0.65)
	end

	local shout: (text: string, color: Color3?, y: number?) -> ()

	local function refreshLevel(celebrate: boolean)
		local level = currentLevel()
		if level == shownLevel then
			return
		end
		local newTier = tierForLevel(level)
		local tierChanged = newTier ~= tierIndex
		shownLevel = level
		tierIndex = newTier
		local style = TIERS[newTier]
		if tierChipLabel then
			tierChipLabel.Text = style.Icon .. " Niv. " .. level .. " · " .. style.Name
			tierChipLabel.TextColor3 = style.ChipText
		end
		if tierChanged then
			applyTier(newTier)
		end
		if celebrate then
			tierChipScale.Scale = 1.35
			UIUtil.Tween(tierChipScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			if tierChanged then
				flashCard()
				ctx.Sound.Play("Buy", 1.1)
				ctx.Effects.Burst(card, UDim2.fromOffset(MX, 120), style.Chip, 14)
				shout(style.Icon .. " " .. style.Shout, style.Chip, 150)
			end
		end
	end

	------------------------------------------------------------------
	-- Objets à écraser
	------------------------------------------------------------------
	local function randomDef()
		if random:NextNumber() < 0.4 then
			local colors = {}
			for i = 1, 3 do
				colors[i] = MACARON_COLORS[random:NextInteger(1, #MACARON_COLORS)]
			end
			return { Kind = "Macaron", Colors = colors, Color = colors[2], Words = MACARON_WORDS, W = 80, H = 78 }
		end
		local item
		local tierItems = TIERS[math.max(1, tierIndex)].Items
		if random:NextNumber() < 0.4 and #tierItems > 0 then
			item = tierItems[random:NextInteger(1, #tierItems)]
		else
			item = EMOJI_ITEMS[random:NextInteger(1, #EMOJI_ITEMS)]
		end
		return { Kind = "Emoji", Icon = item.Icon, Color = item.Color, Colors = { item.Color }, Words = item.Words, Special = item.Special, W = 72, H = 72 }
	end

	-- Construit le visuel d'un objet dans `holder` (tailles en Scale : il se déforme avec lui)
	local function buildVisual(def, holder: Frame)
		local parts = { Fillings = {} }
		if def.Kind == "Macaron" then
			for i = 1, 3 do
				local color = def.Colors[i]
				local unit = Create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5 + random:NextNumber(-0.03, 0.03), (i - 1) / 3),
					Size = UDim2.fromScale(random:NextNumber(0.9, 1), 1 / 3),
					BackgroundTransparency = 1,
					ZIndex = 1,
					Parent = holder,
				})
				local top = box({ Position = UDim2.fromScale(0, 0.04), Size = UDim2.fromScale(1, 0.42), BackgroundColor3 = color, ZIndex = 2, Parent = unit })
				UIUtil.Corner(top, UDim.new(0.5, 0))
				UIUtil.Gradient(top, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)), 90)
				local fillingColor = (color.R < 0.7 and color.G < 0.5) and Color3.fromRGB(96, 56, 40) or Color3.fromRGB(255, 246, 228)
				local filling = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.86, 0.17), BackgroundColor3 = fillingColor, ZIndex = 3, Parent = unit })
				UIUtil.Corner(filling, UDim.new(0.5, 0))
				local bottom = box({ Position = UDim2.fromScale(0, 0.56), Size = UDim2.fromScale(1, 0.4), BackgroundColor3 = mix(color, Color3.new(0, 0, 0), 0.08), ZIndex = 2, Parent = unit })
				UIUtil.Corner(bottom, UDim.new(0.5, 0))
				table.insert(parts.Fillings, filling)
			end
		else
			parts.Label = UIUtil.Label({
				Text = def.Icon,
				Size = UDim2.fromScale(1, 1),
				MaxTextSize = 72,
				ZIndex = 2,
				Parent = holder,
			})
			local splat = box({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = def.Color, Visible = false, ZIndex = 1, Parent = holder })
			UIUtil.Corner(splat, UDim.new(0.5, 0))
			UIUtil.Stroke(splat, mix(def.Color, Color3.new(0, 0, 0), 0.35), 1.5)
			UIUtil.Gradient(splat, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)), 90)
			parts.Splat = splat
		end
		return parts
	end

	-- File d'attente (tapis roulant)
	local queue = {} -- { { Def, Holder, Parts } }

	local function addToQueue(dropIn: boolean)
		local def = randomDef()
		local slot = #queue + 1
		local scale = QUEUE_SIZE / math.max(def.W, def.H)
		local holder = Create("Frame", {
			Name = "Item",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(QUEUE_X[slot] or QUEUE_X[#QUEUE_X], dropIn and QUEUE_Y - 90 or QUEUE_Y),
			Size = UDim2.fromOffset(def.W * scale, def.H * scale),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = rig,
		})
		local parts = buildVisual(def, holder)
		table.insert(queue, { Def = def, Holder = holder, Parts = parts })
		if dropIn then
			UIUtil.Tween(holder, 0.5, { Position = UDim2.fromOffset(QUEUE_X[slot] or QUEUE_X[#QUEUE_X], QUEUE_Y) }, Enum.EasingStyle.Bounce)
		end
	end

	-- Tas de galettes (au-dessus de la poubelle)
	local pile = {}

	local function addToPile(color: Color3)
		if not ctx.IsAlive() then
			return
		end
		local disc = box({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(BIN_X + random:NextNumber(-3, 3), BIN_TOP - #pile * 7),
			Size = UDim2.fromOffset(44, 8),
			BackgroundColor3 = color,
			Rotation = random:NextNumber(-5, 5),
			ZIndex = 4,
		}, 4)
		table.insert(pile, disc)
		if #pile >= PILE_MAX then
			-- La poubelle avale tout le tas
			local old = pile
			pile = {}
			task.delay(0.3, function()
				for i, item in ipairs(old) do
					if item.Parent then
						UIUtil.Tween(item, 0.35 + i * 0.03, { Position = UDim2.fromOffset(BIN_X, BIN_TOP + 30), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
						Debris:AddItem(item, 0.7)
					end
				end
			end)
		end
	end

	------------------------------------------------------------------
	-- Effets du CRUNCH
	------------------------------------------------------------------
	local shakeTime = 0
	local shakePower = 1

	local function crumbs(colors: { Color3 }, count: number, origin: Vector2)
		for _ = 1, count do
			local size = random:NextInteger(4, 9)
			local color = colors[random:NextInteger(1, #colors)]
			if random:NextNumber() < 0.2 then
				color = Color3.new(1, 1, 1)
			end
			local crumb = box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(origin.X + random:NextNumber(-30, 30), origin.Y),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = color,
				Rotation = random:NextNumber(0, 90),
				ZIndex = 10,
			}, 2)
			local dir = random:NextNumber() < 0.5 and -1 or 1
			local peak = UDim2.fromOffset(origin.X + dir * random:NextNumber(40, 110), origin.Y - random:NextNumber(20, 70))
			local land = UDim2.fromOffset(peak.X.Offset + dir * random:NextNumber(10, 40), ANVIL_Y + random:NextNumber(4, 24))
			UIUtil.Tween(crumb, 0.2, { Position = peak, Rotation = crumb.Rotation + 120 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.2, function()
				if crumb.Parent then
					UIUtil.Tween(crumb, 0.4, { Position = land, BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
			Debris:AddItem(crumb, 0.7)
		end
	end

	-- Bouffée de vapeur (disque blanc qui gonfle, monte et s'efface)
	local function puff(x: number, y: number, size: number, dx: number, dy: number)
		local cloud = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = white,
			BackgroundTransparency = 0.25,
			ZIndex = 11,
		}, UDim.new(1, 0))
		UIUtil.Tween(cloud, 0.7, {
			Position = UDim2.fromOffset(x + dx, y + dy),
			Size = UDim2.fromOffset(size * 2.2, size * 2.2),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Debris:AddItem(cloud, 0.75)
	end

	local function steam(big: boolean)
		for _, dir in ipairs({ -1, 1 }) do
			puff(MX + dir * 70, ANVIL_Y - 10, big and 16 or 12, dir * 48, -22)
			if big then
				puff(MX + dir * 90, ANVIL_Y - 6, 12, dir * 60, -34)
			end
		end
	end

	-- Gerbe d'étincelles (traits lumineux qui partent en étoile)
	local function sparks(colors: { Color3 }, count: number)
		for _ = 1, count do
			local angle = random:NextNumber(-math.pi, 0)
			local distance = random:NextNumber(50, 120)
			local spark = box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(MX, ANVIL_Y - 6),
				Size = UDim2.fromOffset(12, 2),
				BackgroundColor3 = colors[random:NextInteger(1, #colors)],
				Rotation = math.deg(angle),
				ZIndex = 12,
			}, 1)
			UIUtil.Tween(spark, 0.4, {
				Position = UDim2.fromOffset(MX + math.cos(angle) * distance, ANVIL_Y - 6 + math.sin(angle) * distance),
				Size = UDim2.fromOffset(4, 2),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			Debris:AddItem(spark, 0.45)
		end
	end

	-- Onde de choc au ras de l'enclume
	local function shockwave(color: Color3)
		shockRing.Size = UDim2.fromOffset(40, 8)
		shockStroke.Color = color
		shockStroke.Transparency = 0
		UIUtil.Tween(shockRing, 0.35, { Size = UDim2.fromOffset(280, 36) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		UIUtil.Tween(shockStroke, 0.35, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end

	shout = function(text: string, color: Color3?, y: number?)
		local long = utf8.len(text) or #text
		local isLong = long > 12
		local startY = y or 124
		local label = UIUtil.Label({
			Text = text,
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = color or Color3.fromRGB(255, 220, 50),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(MX, startY),
			Size = UDim2.fromOffset(240, isLong and 30 or 46),
			Rotation = random:NextNumber(-10, 10),
			MaxTextSize = isLong and 24 or 42,
			ZIndex = 13,
			Parent = rig,
		})
		local stroke = UIUtil.Stroke(label, hazardBlack, 3)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		local scale = Create("UIScale", { Scale = 0.3, Parent = label })
		UIUtil.Tween(scale, 0.22, { Scale = 1.1 }, Enum.EasingStyle.Back)
		task.delay(0.5, function()
			if label.Parent then
				UIUtil.Tween(label, 0.4, { Position = UDim2.fromOffset(MX, startY - 28), TextTransparency = 1 })
				UIUtil.Tween(stroke, 0.4, { Transparency = 1 })
			end
		end)
		Debris:AddItem(label, 1)
	end

	------------------------------------------------------------------
	-- Cycle de la presse (machine à états, pilotée par OnRender)
	------------------------------------------------------------------
	local phase = "Idle"
	local phaseTime = 0
	local phaseDuration = 0
	local current = nil -- objet sur l'enclume : { Def, Holder, Parts }
	local plateY = PLATE_TOP
	local phaseStartPlate = PLATE_TOP
	local squeezeDepth = 0
	local turbo = false
	local pendingTurbo = false
	local crushed = 0
	local pressure = 0
	local cooldownEnd = 0
	local shownCooldown = ""
	local beltOffset = 0
	local factor = 1

	local function setPhase(name: string)
		phase = name
		phaseTime = 0
		phaseStartPlate = plateY
		local speedMul = factor
		if turbo and (name == "Descend" or name == "Squeeze") then
			speedMul *= 4
		end
		phaseDuration = (DURATIONS[name] or 0.5) / speedMul
	end

	local function itemHeight(): number
		if current then
			return current.Holder.Size.Y.Offset
		end
		return 0
	end

	-- Charge le prochain objet de la file sur l'enclume
	local function loadNext()
		factor = speedFactor()
		speedLabel.Text = "⚡ x" .. (math.floor(factor * 10 + 0.5) / 10)
		local entry = table.remove(queue, 1)
		if not entry then
			addToQueue(false)
			entry = table.remove(queue, 1)
		end
		current = entry
		local def = entry.Def
		entry.Holder.ZIndex = 4
		setPhase("Load")
		UIUtil.Tween(entry.Holder, phaseDuration, { Position = UDim2.fromOffset(MX, ANVIL_Y), Size = UDim2.fromOffset(def.W, def.H) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		-- Le reste de la file avance, et on remplit
		for i, other in ipairs(queue) do
			UIUtil.Tween(other.Holder, 0.35, { Position = UDim2.fromOffset(QUEUE_X[i] or QUEUE_X[#QUEUE_X], QUEUE_Y) }, Enum.EasingStyle.Quad)
		end
		while #queue < #QUEUE_X do
			addToQueue(true)
		end
	end

	-- Le moment CRUNCH
	local function onCrunch()
		if not current then
			return
		end
		local def = current.Def
		local parts = current.Parts
		local effects = effectsOn()
		local style = TIERS[math.max(1, tierIndex)]
		crushed += 1
		counterLabel.Text = "💥 " .. crushed
		counterScale.Scale = 1.35
		UIUtil.Tween(counterScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Crush", random:NextNumber(0.85, 1.15) * (turbo and 0.85 or 1))

		-- Secousse de toute la carte (plus forte aux paliers élevés et en turbo)
		shakeTime = turbo and 0.38 or 0.26
		shakePower = 1 + (tierIndex - 1) * 0.15 + (turbo and 0.4 or 0)

		local words = def.Words
		local word = words[random:NextInteger(1, #words)]
		if turbo then
			word = "TURBO " .. word
		end
		shout(word, turbo and Color3.fromRGB(255, 90, 60) or nil, nil)

		-- Éclair sur le plateau + onde de choc
		plateFlash.BackgroundTransparency = 0.15
		UIUtil.Tween(plateFlash, 0.3, { BackgroundTransparency = 1 })
		shockwave(tierIndex == 5 and Color3.fromRGB(0, 230, 255) or white)

		local origin = Vector2.new(MX, ANVIL_Y - 10)
		local debrisColors = table.clone(def.Colors)
		for _, color in ipairs(style.Debris) do
			table.insert(debrisColors, color)
		end
		crumbs(debrisColors, effects and (turbo and 16 or 11) or 4, origin)
		if effects then
			steam(tierIndex >= 3)
			if tierIndex == 4 then
				sparks({ Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 250, 210) }, 8)
			elseif tierIndex == 5 then
				sparks(style.Debris, 14)
			elseif turbo then
				sparks({ Color3.fromRGB(255, 200, 60) }, 6)
			end
		end

		if parts.Label then
			parts.Label.Visible = false
			if def.Special == "Pop" then
				current.Holder.Visible = false
				current.NoPile = true
			elseif parts.Splat then
				parts.Splat.Visible = true
			end
			-- Morceaux de l'objet qui s'envolent
			if effects and def.Special ~= "Sponge" then
				for _ = 1, 3 do
					local bit = UIUtil.Label({
						Text = def.Icon,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(MX, ANVIL_Y - 12),
						Size = UDim2.fromOffset(22, 22),
						MaxTextSize = 22,
						ZIndex = 10,
						Parent = rig,
					})
					local dx = random:NextNumber(-120, 120)
					UIUtil.Tween(bit, 0.55, {
						Position = UDim2.fromOffset(MX + dx, ANVIL_Y - random:NextNumber(40, 90)),
						Rotation = random:NextNumber(-360, 360),
						TextTransparency = 1,
					}, Enum.EasingStyle.Quad)
					Debris:AddItem(bit, 0.6)
				end
			end
		else
			-- Macarons : la crème déborde
			for _, filling in ipairs(parts.Fillings) do
				UIUtil.Tween(filling, 0.15, { Size = UDim2.fromScale(1.12, 0.3) }, Enum.EasingStyle.Back)
			end
		end
	end

	-- Envoie la galette sur le tas
	local function sendToPile(entry)
		local holder = entry.Holder
		if entry.NoPile or not holder.Parent then
			holder:Destroy()
			return
		end
		local color = entry.Def.Color
		UIUtil.Tween(holder, 0.45, {
			Position = UDim2.fromOffset(BIN_X, BIN_TOP - #pile * 7),
			Size = UDim2.fromOffset(44, 8),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		task.delay(0.46, function()
			holder:Destroy()
			addToPile(color)
		end)
	end

	local function onRise()
		local entry = current
		current = nil
		if not entry then
			return
		end
		if entry.Def.Special == "Sponge" and entry.Parts.Label then
			-- L'éponge reprend sa forme... puis part quand même
			local holder = entry.Holder
			UIUtil.Tween(holder, 0.4, { Size = UDim2.fromOffset(entry.Def.W, entry.Def.H) }, Enum.EasingStyle.Back)
			entry.Parts.Label.Visible = true
			if entry.Parts.Splat then
				entry.Parts.Splat.Visible = false
			end
			shout("...elle est revenue", nil, nil)
			-- Part avant la fin de la remontée (phaseDuration = durée de "Rise") :
			-- sinon, à haute vitesse, l'objet suivant arrive sur l'éponge
			task.delay(math.min(0.75, phaseDuration * 0.8), function()
				if ctx.IsAlive() and holder.Parent then
					sendToPile(entry)
				end
			end)
		else
			sendToPile(entry)
		end
	end

	------------------------------------------------------------------
	-- Bouton START : écrasement manuel
	------------------------------------------------------------------
	ctx.Connect(startButton.MouseButton1Down, function()
		startButton.Position = UDim2.fromOffset(40, 9)
	end)
	ctx.Connect(startButton.MouseButton1Up, function()
		startButton.Position = UDim2.fromOffset(40, 4)
	end)
	ctx.Connect(startButton.MouseLeave, function()
		startButton.Position = UDim2.fromOffset(40, 4)
	end)
	ctx.Connect(startButton.Activated, function()
		if not ctx.HasFeature("PressStart") then
			return
		end
		local now = os.clock()
		if now < cooldownEnd then
			ctx.Sound.Play("Error", 1)
			UIUtil.Shake(startGroup)
			return
		end
		cooldownEnd = now + cooldown
		ctx.Interact("Press")
		ctx.Sound.Play("Click", 0.7)
		if phase == "Descend" or phase == "Squeeze" then
			turbo = true
			-- Accélère la phase en cours (en gardant la progression)
			local progress = phaseDuration > 0 and phaseTime / phaseDuration or 1
			phaseDuration /= 4
			phaseTime = progress * phaseDuration
		else
			pendingTurbo = true
		end
	end)

	ctx.OnBonus("Press", function(payload)
		local amount = tonumber(payload.Amount)
		if amount then
			ctx.FloatText(container, UDim2.fromOffset(MX, 110), "+" .. ctx.Format.Format(amount), Theme.Colors.Gold, 30)
		end
	end)

	------------------------------------------------------------------
	-- Palier initial + suivi du niveau
	------------------------------------------------------------------
	refreshLevel(false)
	ctx.Connect(ctx.State.Changed, function()
		refreshLevel(true)
	end)

	for _ = 1, #QUEUE_X do
		addToQueue(false)
	end

	------------------------------------------------------------------
	-- Boucle
	------------------------------------------------------------------
	loadNext()

	local clock = 0
	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt
		phaseTime += dt
		local t = phaseDuration > 0 and math.clamp(phaseTime / phaseDuration, 0, 1) or 1
		local targetPressure = 0

		if phase == "Load" then
			plateY = PLATE_TOP
			if t >= 1 then
				turbo = pendingTurbo
				pendingTurbo = false
				squeezeDepth = current and current.Def.H * 0.24 or 0
				setPhase("Descend")
			end
		elseif phase == "Descend" then
			local contact = ANVIL_Y - itemHeight() - PLATE_H
			plateY = phaseStartPlate + (contact - phaseStartPlate) * easeInOut(t)
			targetPressure = 0.15 + 0.2 * t
			if t >= 1 then
				setPhase("Squeeze")
			end
		elseif phase == "Squeeze" then
			if current then
				local def = current.Def
				-- Se tasse en tremblant, s'élargit un peu
				local height = def.H - squeezeDepth * (t * t)
				local wobble = math.sin(clock * 60) * 2 * t
				current.Holder.Size = UDim2.fromOffset(def.W * (1 + 0.1 * t) + wobble, height)
				if current.Parts.Label then
					current.Parts.Label.Rotation = random:NextNumber(-6, 6) * t
				end
			end
			plateY = ANVIL_Y - itemHeight() - PLATE_H
			targetPressure = 0.4 + 0.5 * t
			shakeTime = math.max(shakeTime, 0.03 * t)
			if t >= 1 then
				setPhase("Crunch")
				onCrunch()
			end
		elseif phase == "Crunch" then
			-- Écrasé d'un coup, un peu plus bas que la galette finale
			local squashed = FLAT_H * 0.6
			if current then
				local def = current.Def
				local startH = def.H - squeezeDepth
				local height = startH + (squashed - startH) * t
				current.Holder.Size = UDim2.fromOffset(def.W * (1.1 + 0.6 * t), height)
				if current.Parts.Label then
					current.Parts.Label.Rotation = 0
				end
				plateY = ANVIL_Y - height - PLATE_H
			else
				plateY = ANVIL_Y - squashed - PLATE_H
			end
			targetPressure = 1
			if t >= 1 then
				setPhase("Hold")
			end
		elseif phase == "Hold" then
			-- Petit rebond de la galette (et du plateau) : "boing"
			local squashed = FLAT_H * 0.6
			local height = squashed + (FLAT_H - squashed) * easeOutBack(t)
			if current then
				local def = current.Def
				current.Holder.Size = UDim2.fromOffset(def.W * (1.7 - 0.2 * easeOut(t)), height)
			end
			plateY = ANVIL_Y - height - PLATE_H
			targetPressure = 0.9
			if t >= 1 then
				setPhase("Rise")
				onRise()
				turbo = false
			end
		elseif phase == "Rise" then
			plateY = phaseStartPlate + (PLATE_TOP - phaseStartPlate) * easeOut(t)
			targetPressure = 0.1
			if t >= 1 then
				plateY = PLATE_TOP
				loadNext()
			end
		end

		-- Plateau + tige
		plate.Position = UDim2.fromOffset(MX, plateY)
		rod.Size = UDim2.fromOffset(18, math.max(4, plateY - 66 + 4))

		-- Manomètre
		pressure += (targetPressure - pressure) * math.min(1, dt * 8)
		needlePivot.Rotation = -120 + pressure * 240
		local pressing = phase == "Squeeze" or phase == "Crunch" or phase == "Hold"
		led.BackgroundColor3 = pressing and Theme.Colors.Red or Theme.Colors.Green

		-- Tapis roulant
		beltOffset = (beltOffset + dt * 30) % (BELT_STRIPES_W / 5)
		beltStripes.Position = UDim2.fromOffset(-beltOffset, 0)

		-- Animations du palier
		for i, needle in ipairs(tierAnim.Needles) do
			needle.Rotation = -100 + pressure * 200 + math.sin(clock * (7 + i * 3)) * 8
		end
		for i, star in ipairs(tierAnim.Twinkles) do
			local wave = 0.5 + 0.5 * math.sin(clock * 3 + i * 1.9)
			star.TextTransparency = 0.1 + (1 - wave) * 0.8
			star.Rotation = math.sin(clock + i) * 15
		end
		local beacon = tierAnim.Beacon
		if beacon then
			beacon.BackgroundTransparency = (math.sin(clock * 8) > 0) and 0 or 0.6
		end
		local shineFrame = tierAnim.Shine
		if shineFrame then
			local sweep = (clock * 0.45) % 1.6 -- passe puis marque une pause
			shineFrame.Position = UDim2.fromOffset(-40 + sweep * 200, 0)
		end
		local glow = tierAnim.Glow
		if glow then
			glow.BackgroundTransparency = 0.45 + 0.3 * math.sin(clock * 4)
		end
		if tierIndex == 5 then
			-- Contours néon qui changent de couleur
			local hue = (clock * 0.12) % 1
			local neon = Color3.fromHSV(hue, 0.75, 1)
			for _, column in ipairs(columns) do
				column.Stroke.Color = neon
			end
			plateStroke.Color = neon
			beamStroke.Color = neon
			cardStroke.Color = Color3.fromHSV((hue + 0.5) % 1, 0.7, 1)
		elseif tierIndex == 3 and effectsOn() then
			-- Vapeur qui s'échappe du tuyau de temps en temps
			tierAnim.SteamTimer -= dt
			if tierAnim.SteamTimer <= 0 then
				tierAnim.SteamTimer = random:NextNumber(1.2, 2.6)
				puff(tierAnim.SteamX, 66, 8, random:NextNumber(-6, 6), -26)
			end
		end

		-- Secousse de toute la carte
		if shakeTime > 0 then
			shakeTime -= dt
			local strength = math.clamp(shakeTime * 18, 0.6, 4) * shakePower
			card.Position = UDim2.fromOffset(random:NextNumber(-strength, strength), random:NextNumber(-strength, strength))
		elseif card.Position ~= UDim2.new() then
			card.Position = UDim2.new()
		end

		-- Compte à rebours du bouton START
		if startGroup.Visible then
			local remaining = cooldownEnd - os.clock()
			local text = remaining > 0 and string.format("%.1f", remaining) or "START"
			if text ~= shownCooldown then
				shownCooldown = text
				startButton.Text = text
				startButton.BackgroundColor3 = remaining > 0 and Color3.fromRGB(150, 110, 112) or Theme.Colors.Red
				buttonSide.BackgroundColor3 = remaining > 0 and Color3.fromRGB(96, 70, 72) or Color3.fromRGB(150, 16, 24)
			end
		end
	end)
end

function Press.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Press
