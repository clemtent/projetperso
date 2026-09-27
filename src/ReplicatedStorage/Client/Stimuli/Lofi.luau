--[[
	Lofi (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Lofi

	La petite chambre "lofi" (slot R3, 384x268), entièrement dessinée en
	code (Frames, UICorner, UIGradient, UIStroke — aucun emoji pour le décor
	ni les personnages). v9.1 : la carte fait ≈ 350x245 px à l'écran, donc
	une composition CLAIRE avec peu d'éléments, GROS et contrastés (contours
	sombres), et des animations bien visibles :
	  - à gauche, une grande fenêtre : ciel qui suit l'heure LOCALE du joueur
	    (nuit, aube, jour, crépuscule), grosse lune ou soleil, étoiles qui
	    scintillent, étoile filante, ville avec fenêtres allumées, averses
	    qui vont et viennent (éclairs la nuit), guirlande lumineuse ;
	  - le chat roux dort sur le rebord (respire, gros "Z z z"), se réveille,
	    regarde la pluie puis la chambre, remue la queue, bâille ;
	  - au centre, la fille (plus grande) : hoche franchement la tête en
	    rythme, casque qui pulse, écrit dans son cahier (les lignes
	    apparaissent, la page se tourne), boit une gorgée de sa tasse
	    fumante, et de temps en temps lève les yeux et sourit (petit cœur) ;
	  - à droite, la lampe : grand halo chaud sur le mur, cône et flaque de
	    lumière sur le bureau (contraste chaud / nuit bleue = ambiance cosy) ;
	  - collection de vinyles (amélioration "Vinyl", ctx.GetLevel) : une
	    étagère murale à 10 emplacements, CHAQUE niveau y ajoute un disque
	    (emplacements vides en pointillé : on voit la progression) ; paliers
	    sur la platine : pochette (1), vinyle rose (3), enceinte qui pulse
	    (5), vinyle marbré (6), néon sous le bureau (7), arc-en-ciel (9),
	    disque et bras dorés + étagère dorée (10) ;
	  - le lecteur en bas : pochette + vinyle qui tourne, titre du morceau
	    (SoundManager.GetMusicInfo si disponible, sinon GetCurrentTrack),
	    progression + temps, visualiseur piloté par le volume réel du morceau
	    (PlaybackLoudness) ou animé tout seul, bouton ⏭ (NextTrack).
	Si la playlist est vide : dans Studio, un rappel "Ajoute une musique
	dans Config.Music" ; en jeu, simplement la petite chambre.
	Performance : ≈ 520 instances (contre ≈ 1045 en v9), UNE boucle
	ctx.OnRender limitée à 30 images/s ; objets recyclés (pluie, notes),
	aucune création par image ; pause complète quand la carte est cachée.
]]

local RunService = game:GetService("RunService")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Lofi = {}
Lofi.Slot = "R3"

-- Dimensions (pixels "design")
local SCENE_X, SCENE_Y = 6, 6
local SCENE_W, SCENE_H = 368, 204
local BAR_Y, BAR_H = 214, 42
local DESK_Y = 146 -- dessus du bureau (plateau vu en perspective)
local DESK_FRONT = 160 -- face avant du bureau
local SCENE_RADIUS = 10 -- coins arrondis de la scène (repris par la face avant du bureau)
local ITEM_BASE = 154 -- les objets "posés" sur le plateau
local WINDOW_X, WINDOW_Y, WINDOW_W, WINDOW_H = 18, 28, 156, 86
local FRAME_T = 6 -- épaisseur du cadre de la fenêtre
local GLASS_W, GLASS_H = WINDOW_W - FRAME_T * 2, WINDOW_H - FRAME_T * 2
local SILL_Y = WINDOW_Y + WINDOW_H - 2
local RACK_X, RACK_Y, RACK_W = 198, 24, 164 -- étagère à vinyles (bas de l'étagère)
local LAMP_X = 336
local PX = 256 -- centre de la fille
local HEAD_Y = 80 -- centre de la tête
local TURNTABLE_X = 60 -- centre de la platine
local TT_W = 88 -- largeur de la platine
local MUG_X, MUG_Y = 166, ITEM_BASE - 10 -- tasse posée (centre)
local SHAFT_X1, SHAFT_Y1, SHAFT_X2, SHAFT_Y2 = 96, 110, 170, 204 -- rayon de la fenêtre
local EQ_BARS = 12
local BEAT = 60 / 78 -- une pulsation (78 BPM, tranquille)
local STEP = 1 / 30 -- la scène est animée à 30 images/s au maximum
local NOTE_POOL = 7
local NOTE_LIFE = 2.4
local RAIN_DROPS = 10
local MAX_RECORDS = 10

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local RAIN_COLOR = Color3.fromRGB(196, 214, 255)
local EQ_LOW = Color3.fromRGB(255, 120, 190)
local EQ_HIGH = Color3.fromRGB(100, 220, 255)
local WARM = Color3.fromRGB(255, 176, 96)
local WARM_LIGHT = Color3.fromRGB(255, 226, 170)
local OUTLINE = Color3.fromRGB(40, 22, 52) -- contours "dessin animé"

-- Palette du personnage (original : cheveux indigo, sweat menthe, casque rose)
local SKIN = Color3.fromRGB(255, 224, 204)
local SKIN_SHADE = Color3.fromRGB(244, 190, 170)
local HAIR = Color3.fromRGB(58, 44, 96)
local HAIR_LIGHT = Color3.fromRGB(116, 96, 170)
local HOODIE = Color3.fromRGB(112, 212, 196)
local HOODIE_DARK = Color3.fromRGB(62, 150, 150)
local PHONES = Color3.fromRGB(255, 118, 176)
local PHONES_DARK = Color3.fromRGB(196, 58, 124)
local PHONES_GLOW = Color3.fromRGB(255, 150, 210)
local LINE_INK = Color3.fromRGB(72, 44, 78)
local EYE_INK = Color3.fromRGB(50, 30, 66)
local CAT_COLOR = Color3.fromRGB(250, 170, 88)
local CAT_LIGHT = Color3.fromRGB(255, 214, 150)
local CAT_DARK = Color3.fromRGB(214, 124, 52)
local CAT_CREAM = Color3.fromRGB(255, 238, 210)
local CAT_LINE = Color3.fromRGB(120, 62, 30)
local LEAF_LIGHT = Color3.fromRGB(150, 226, 150)
local LEAF_DARK = Color3.fromRGB(56, 146, 98)
local NOTE_COLORS = { PHONES_GLOW, EQ_HIGH, Color3.fromRGB(255, 226, 120), Color3.fromRGB(196, 170, 255) }
local HEART_COLOR = Color3.fromRGB(255, 110, 160)
local RECORD_COLORS = {
	Color3.fromRGB(255, 120, 150),
	Color3.fromRGB(110, 190, 255),
	Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(160, 120, 240),
	Color3.fromRGB(110, 220, 170),
	Color3.fromRGB(255, 160, 90),
	Color3.fromRGB(240, 240, 250),
	Color3.fromRGB(255, 110, 210),
	Color3.fromRGB(80, 210, 230),
	Color3.fromRGB(255, 120, 150),
}
local GOLD = Color3.fromRGB(255, 206, 80)
local GOLD_DARK = Color3.fromRGB(196, 136, 30)

local TRACKS = {
	en = {
		"midnight_rain.mp3",
		"purring_cat.wav",
		"cold_coffee_at_3am.mp3",
		"endless_revision.mp3",
		"clouds_in_pajamas.mp3",
		"the_test_is_tomorrow.mp3",
		"soft_laziness.wav",
		"5_more_minutes.mp3",
	},
	fr = {
		"pluie_de_minuit.mp3",
		"chat_qui_ronronne.wav",
		"cafe_froid_a_3h.mp3",
		"revisions_infinies.mp3",
		"nuages_en_pyjama.mp3",
		"le_controle_c_est_demain.mp3",
		"flemme_douce.wav",
		"encore_5_minutes.mp3",
	},
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Ambiances selon l'heure : ciel (haut / milieu / horizon), lueur de
-- l'horizon, mur, nuages, ville (loin / près), "nuit" (étoiles, fenêtres
-- allumées), puissance de la lampe, couleur et force du rayon de la fenêtre
local PALETTES = {
	Night = {
		SkyTop = rgb(18, 20, 66), SkyMid = rgb(58, 44, 120), SkyLow = rgb(150, 82, 150),
		Glow = rgb(255, 128, 186), GlowPower = 0.45,
		WallTop = rgb(44, 36, 86), WallLow = rgb(84, 58, 124),
		Cloud = rgb(118, 98, 170), CloudAlpha = 0.45,
		Far = rgb(84, 64, 132), NearTop = rgb(40, 32, 80), NearLow = rgb(20, 16, 42),
		Night = 1, Lamp = 1, Shaft = rgb(150, 172, 255), ShaftPower = 0.6,
	},
	Dawn = {
		SkyTop = rgb(66, 76, 158), SkyMid = rgb(232, 146, 176), SkyLow = rgb(255, 206, 150),
		Glow = rgb(255, 214, 160), GlowPower = 0.5,
		WallTop = rgb(74, 56, 112), WallLow = rgb(120, 86, 146),
		Cloud = rgb(255, 186, 200), CloudAlpha = 0.25,
		Far = rgb(150, 116, 170), NearTop = rgb(76, 60, 116), NearLow = rgb(44, 34, 76),
		Night = 0.35, Lamp = 0.85, Shaft = rgb(255, 196, 170), ShaftPower = 0.75,
	},
	Day = {
		SkyTop = rgb(80, 156, 236), SkyMid = rgb(138, 200, 250), SkyLow = rgb(210, 238, 255),
		Glow = rgb(255, 255, 255), GlowPower = 0.4,
		WallTop = rgb(100, 84, 150), WallLow = rgb(146, 118, 186),
		Cloud = rgb(255, 255, 255), CloudAlpha = 0.05,
		Far = rgb(150, 178, 216), NearTop = rgb(98, 118, 170), NearLow = rgb(66, 82, 132),
		Night = 0, Lamp = 0.6, Shaft = rgb(255, 238, 190), ShaftPower = 1,
	},
	Dusk = {
		SkyTop = rgb(56, 46, 126), SkyMid = rgb(224, 102, 140), SkyLow = rgb(255, 178, 96),
		Glow = rgb(255, 170, 110), GlowPower = 0.55,
		WallTop = rgb(72, 48, 104), WallLow = rgb(122, 76, 132),
		Cloud = rgb(255, 156, 168), CloudAlpha = 0.2,
		Far = rgb(122, 78, 132), NearTop = rgb(62, 44, 96), NearLow = rgb(34, 24, 58),
		Night = 0.65, Lamp = 0.95, Shaft = rgb(255, 170, 120), ShaftPower = 0.8,
	},
}
-- Heures clés (heure locale) : entre deux clés, les ambiances se mélangent
local TIME_KEYS = {
	{ 0, "Night" },
	{ 5, "Night" },
	{ 6.5, "Dawn" },
	{ 8.5, "Day" },
	{ 17, "Day" },
	{ 18.8, "Dusk" },
	{ 20.6, "Night" },
	{ 24, "Night" },
}
local RAIN_SKY = rgb(90, 94, 128) -- ciel voilé quand il pleut

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

local function blendPalette(a: { [string]: any }, b: { [string]: any }, t: number): { [string]: any }
	local out = {}
	for key, value in pairs(a) do
		local other = b[key]
		if typeof(value) == "Color3" then
			out[key] = value:Lerp(other, t)
		else
			out[key] = value + (other - value) * t
		end
	end
	return out
end

-- Ambiance à une heure donnée (0..24)
local function paletteAt(hour: number): { [string]: any }
	for i = 1, #TIME_KEYS - 1 do
		local k0, k1 = TIME_KEYS[i], TIME_KEYS[i + 1]
		if hour >= k0[1] and hour < k1[1] then
			return blendPalette(PALETTES[k0[2]], PALETTES[k1[2]], smooth((hour - k0[1]) / (k1[1] - k0[1])))
		end
	end
	return PALETTES.Night
end

-- Arc "bas de cercle" (yeux fermés, sourire) : on cache la moitié haute
-- du contour avec un dégradé de transparence
local LOWER_ARC = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(0.56, 0),
	NumberSequenceKeypoint.new(1, 0),
})
-- Arc "haut de cercle" (arceau du casque)
local UPPER_ARC = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.54, 1),
	NumberSequenceKeypoint.new(1, 1),
})
-- "Mots" écrits dans le cahier (traits séparés par des espaces) : 10 points
local WORDS = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 0),
	NumberSequenceKeypoint.new(0.31, 1),
	NumberSequenceKeypoint.new(0.38, 1),
	NumberSequenceKeypoint.new(0.39, 0),
	NumberSequenceKeypoint.new(0.68, 0),
	NumberSequenceKeypoint.new(0.69, 1),
	NumberSequenceKeypoint.new(0.76, 1),
	NumberSequenceKeypoint.new(0.77, 0),
	NumberSequenceKeypoint.new(1, 0),
})

-- Vinyle sur la platine selon le niveau de la collection : { base, reflet }
local function vinylLook(level: number): ColorSequence
	local base, shine
	if level >= 10 then
		base, shine = rgb(214, 160, 40), rgb(255, 244, 170)
	elseif level >= 9 then
		-- disque "picture" arc-en-ciel
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 110, 150)),
			ColorSequenceKeypoint.new(0.2, rgb(255, 200, 90)),
			ColorSequenceKeypoint.new(0.4, rgb(120, 230, 150)),
			ColorSequenceKeypoint.new(0.5, rgb(255, 255, 255)),
			ColorSequenceKeypoint.new(0.6, rgb(100, 200, 255)),
			ColorSequenceKeypoint.new(0.8, rgb(170, 120, 255)),
			ColorSequenceKeypoint.new(1, rgb(255, 110, 150)),
		})
	elseif level >= 6 then
		base, shine = rgb(92, 104, 230), rgb(210, 170, 255)
	elseif level >= 3 then
		base, shine = rgb(236, 92, 156), rgb(255, 200, 226)
	else
		base, shine = rgb(34, 32, 44), rgb(112, 106, 142)
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, base),
		ColorSequenceKeypoint.new(0.4, base),
		ColorSequenceKeypoint.new(0.5, shine),
		ColorSequenceKeypoint.new(0.6, base),
		ColorSequenceKeypoint.new(1, base),
	})
end

-- "1:05" (secondes entières uniquement : %d n'accepte pas les décimales)
local function clockText(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function Lofi.Start(ctx)
	local UI = ctx.UIUtil
	local Theme = ctx.Theme
	local Format = ctx.Format
	local Sound = ctx.Sound
	local random = Random.new()

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function frame(props: { [string]: any }): Frame
		props.BorderSizePixel = 0
		return UI.Create("Frame", props)
	end

	local function circle(props: { [string]: any }): Frame
		local f = frame(props)
		UI.Corner(f, UDim.new(1, 0))
		return f
	end

	-- Cadre centré sur (x, y) (pixels du parent)
	local function at(props: { [string]: any }, x: number, y: number, w: number, h: number): { [string]: any }
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.fromOffset(x, y)
		props.Size = UDim2.fromOffset(w, h)
		return props
	end

	local function gradient(guiObject: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
		return UI.Gradient(guiObject, ColorSequence.new(top, bottom), rotation or 90)
	end

	-- Dégradé de transparence seul
	local function fade(guiObject: Instance, sequence: NumberSequence, rotation: number?): UIGradient
		return UI.Create("UIGradient", { Transparency = sequence, Rotation = rotation or 90, Parent = guiObject })
	end

	-- Contour sombre (lisible en petit)
	local function outline(guiObject: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
		return UI.Stroke(guiObject, color or OUTLINE, thickness or 1.5, transparency or 0.25)
	end

	-- Contour circulaire dont on ne garde que le haut ou le bas
	local function arc(props: { [string]: any }, color: Color3, thickness: number, sequence: NumberSequence): (Frame, UIStroke)
		props.BackgroundTransparency = 1
		local f = circle(props)
		local stroke = UI.Stroke(f, color, thickness, 0)
		UI.Create("UIGradient", { Rotation = 90, Transparency = sequence, Parent = stroke })
		return f, stroke
	end

	-- Membre (bras, crayon, queue...) : capsule tournée qui va de (x1, y1) à
	-- (x2, y2). Le haut du cadre est du côté (x1, y1) : un dégradé Rotation 90
	-- va du début vers la fin du membre. (Rotation = autour du CENTRE.)
	local function setLimb(limb: GuiObject, x1: number, y1: number, x2: number, y2: number, thickness: number)
		local dx, dy = x2 - x1, y2 - y1
		local length = math.sqrt(dx * dx + dy * dy)
		limb.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
		limb.Size = UDim2.fromOffset(thickness, length + thickness * 0.6)
		limb.Rotation = math.deg(math.atan2(-dx, dy))
	end

	local function limb(props: { [string]: any }, x1: number, y1: number, x2: number, y2: number, thickness: number): Frame
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		local f = frame(props)
		UI.Corner(f, UDim.new(1, 0))
		setLimb(f, x1, y1, x2, y2, thickness)
		return f
	end

	-- Halo doux : ellipses superposées, plus opaque au centre
	local function halo(props: { [string]: any }, x: number, y: number, w: number, h: number, layers: number): { Frame }
		local list = {}
		for i = 1, layers do
			local k = 1 - (i - 1) / layers * 0.66
			table.insert(list, circle(at(table.clone(props), x, y, w * k, h * k)))
		end
		return list
	end

	local function label(props: { [string]: any }): TextLabel
		props.BackgroundTransparency = 1
		return UI.Create("TextLabel", props)
	end

	-- État animé (une seule table : peu de variables locales dans Start)
	local S = {
		acc = 0, -- temps accumulé (boucle à 30 images/s)
		frame = 0, -- numéro de l'image (le décor lent est animé une image sur deux)
		timeStamp = -1, -- dernier temps affiché dans le lecteur
		clock = 0,
		shown = true,
		visibilityTimer = 0,
		secondTimer = 0,
		tick = 0,
		eqTimer = 0,
		beatCount = 0,
		lastBeat = 0,
		loudPeak = 40, -- pic de volume récent (PlaybackLoudness)
		lastLevel = 0,
		grooveLevel = 0, -- intensité "musicale" lissée (0..1) : hochement + halo
		silentTime = 0, -- depuis quand la musique "joue" sans aucun volume
		musicName = nil :: string?,
		musicSound = nil :: Sound?,
		writeTime = 0,
		pageFlip = -1, -- progression du tournage de page (-1 : aucun)
		linesWritten = 0,
		discSpin = 0, -- vitesse de rotation des vinyles (lissée)
		discAngle = 0,
		fakeProgress = random:NextNumber(0.1, 0.6),
		fakeLength = random:NextInteger(140, 220),
		nextStar = 8, -- étoile filante
		starAge = -1,
		nextFlash = 20, -- éclair lointain
		flash = 0,
		viewers = 0,
		showAlt = false, -- alterne les deux textes du sous-titre
		trackIndex = 1,
		nextNoteSide = 1,
		noteColorIndex = 0,
		vinylLevel = -1,
		armLift = 0, -- bras de la platine levé (0) ou posé sur le disque (1)
		popDisc = 0, -- disque qui vient d'arriver sur l'étagère (animation)
		popT = -1,
		-- Heure et météo
		hour = 22,
		night = 1,
		lampPower = 1,
		rain = 1, -- intensité de la pluie (0..1), lissée
		rainTarget = 1,
		weatherTimer = random:NextNumber(60, 100),
		skyRain = -1, -- pluie utilisée pour le dernier calcul du ciel
		palette = PALETTES.Night,
		nextFlyer = random:NextNumber(6, 12),
		flyerAge = -1,
		flyerY = 20,
		flyerSpeed = 30,
		-- La fille
		blinkTimer = random:NextNumber(1.5, 3),
		blinkAge = -1,
		sipTimer = random:NextNumber(9, 14),
		sipT = -1,
		happyTimer = random:NextNumber(5, 9), -- elle lève les yeux et sourit
		happyT = -1,
		happy = 0, -- 0..1 lissé
		-- Le chat
		catMode = "sleep",
		catTimer = random:NextNumber(10, 16),
		catT = 0,
		catAwake = 9,
		catBlink = -1,
		catLook = 0,
	}

	------------------------------------------------------------------
	-- Carte + scène (mur dont la couleur suit l'heure)
	------------------------------------------------------------------
	local card = frame({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = WHITE,
		Parent = ctx.Container,
	})
	UI.Corner(card, 16)
	gradient(card, Color3.fromRGB(44, 32, 72), Color3.fromRGB(18, 14, 30))
	local cardStroke = UI.Stroke(card, WHITE, 2)
	UI.Gradient(cardStroke, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 200)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 130, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 220, 255)),
	}), 30)

	local scene = frame({
		Name = "Scene",
		Position = UDim2.fromOffset(SCENE_X, SCENE_Y),
		Size = UDim2.fromOffset(SCENE_W, SCENE_H),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Corner(scene, SCENE_RADIUS)
	local wallGradient = gradient(scene, PALETTES.Night.WallTop, PALETTES.Night.WallLow)

	-- Grand halo chaud de la lampe sur le mur (3 couches : dégradé radial)
	local LAMP_HALO_ALPHA = 0.76
	local lampHalo = halo({ Name = "LampGlow", BackgroundColor3 = WARM, BackgroundTransparency = LAMP_HALO_ALPHA, ZIndex = 1, Parent = scene }, LAMP_X - 14, 104, 250, 230, 3)

	------------------------------------------------------------------
	-- Fenêtre : ciel (heure locale), soleil / lune, étoiles, nuages,
	-- ville en deux plans, pluie, reflets
	------------------------------------------------------------------
	local WIN = {
		Stars = {} :: { { Parts: { Frame }, Phase: number, Speed: number } },
		Clouds = {} :: { { Frame: Frame, X: number, Y: number, Speed: number } },
		Puffs = {} :: { Frame },
		Far = {} :: { Frame },
		Near = {} :: { UIGradient },
		Lit = {} :: { { Frame: Frame, On: boolean } },
		Drops = {} :: { { Frame: Frame, X: number, Y: number, Speed: number } },
		Fairy = {} :: { { Frame: Frame, Glow: UIStroke, Phase: number } },
		Roof = {} :: { Frame }, -- antenne (couleur de la ville)
	}
	do
		local WOOD_LIGHT = Color3.fromRGB(240, 220, 190)
		local windowFrame = frame({
			Name = "Window",
			Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y),
			Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
			BackgroundColor3 = WHITE,
			ZIndex = 2,
			Parent = scene,
		})
		UI.Corner(windowFrame, 6)
		gradient(windowFrame, WOOD_LIGHT, Color3.fromRGB(210, 180, 146))
		outline(windowFrame, Color3.fromRGB(90, 60, 70), 2, 0.2)

		local glass = frame({
			Name = "Glass",
			Position = UDim2.fromOffset(FRAME_T, FRAME_T),
			Size = UDim2.fromOffset(GLASS_W, GLASS_H),
			BackgroundColor3 = WHITE,
			ClipsDescendants = true,
			ZIndex = 2,
			Parent = windowFrame,
		})
		WIN.Sky = UI.Gradient(glass, ColorSequence.new(PALETTES.Night.SkyTop, PALETTES.Night.SkyLow), 90)

		-- Lueur de l'horizon (ville la nuit, soleil couchant...)
		WIN.Horizon = frame({ Name = "Horizon", Position = UDim2.fromOffset(0, GLASS_H - 40), Size = UDim2.fromOffset(GLASS_W, 40), BackgroundColor3 = PALETTES.Night.Glow, BackgroundTransparency = 0.6, ZIndex = 1, Parent = glass })
		fade(WIN.Horizon, NumberSequence.new(1, 0))

		-- Étoiles qui scintillent (les plus grosses en forme de croix)
		for i, spec in ipairs({ { 62, 10 }, { 110, 20 }, { 132, 7 }, { 20, 30 }, { 84, 5 }, { 124, 34 }, { 44, 20 } }) do
			local x, y = spec[1], spec[2]
			local parts = {}
			if i <= 2 then
				local sparkle = frame(at({ Name = "Sparkle", BackgroundTransparency = 1, ZIndex = 1, Parent = glass }, x, y, 9, 9))
				table.insert(parts, frame(at({ BackgroundColor3 = Color3.fromRGB(255, 255, 235), ZIndex = 1, Parent = sparkle }, 4.5, 4.5, 9, 1.5)))
				table.insert(parts, frame(at({ BackgroundColor3 = Color3.fromRGB(255, 255, 235), ZIndex = 1, Parent = sparkle }, 4.5, 4.5, 1.5, 9)))
			else
				table.insert(parts, frame(at({ Name = "Star", BackgroundColor3 = Color3.fromRGB(255, 255, 230), Rotation = 45, ZIndex = 1, Parent = glass }, x, y, 3, 3)))
			end
			table.insert(WIN.Stars, { Parts = parts, Phase = random:NextNumber(0, math.pi * 2), Speed = random:NextNumber(1.5, 3.5) })
		end

		-- Soleil (disque + halo) et grosse lune (disque, cratères, halo)
		WIN.Sun = frame(at({ Name = "Sun", BackgroundTransparency = 1, ZIndex = 2, Parent = glass }, 0, 0, 48, 48))
		halo({ BackgroundColor3 = Color3.fromRGB(255, 236, 170), BackgroundTransparency = 0.7, ZIndex = 2, Parent = WIN.Sun }, 24, 24, 48, 48, 1)
		local sunDisc = circle(at({ Name = "Disc", BackgroundColor3 = WHITE, ZIndex = 2, Parent = WIN.Sun }, 24, 24, 22, 22))
		gradient(sunDisc, Color3.fromRGB(255, 250, 214), Color3.fromRGB(255, 200, 100), 45)
		WIN.Moon = frame(at({ Name = "Moon", BackgroundTransparency = 1, ZIndex = 2, Parent = glass }, 0, 0, 56, 56))
		WIN.MoonGlow = halo({ BackgroundColor3 = Color3.fromRGB(255, 244, 200), BackgroundTransparency = 0.84, ZIndex = 2, Parent = WIN.Moon }, 28, 28, 56, 56, 2)
		local moonDisc = circle(at({ Name = "Disc", BackgroundColor3 = WHITE, ZIndex = 2, Parent = WIN.Moon }, 28, 28, 26, 26))
		gradient(moonDisc, Color3.fromRGB(255, 252, 226), Color3.fromRGB(236, 222, 176), 45)
		for i, spec in ipairs({ { 9, 10, 7 }, { 17, 17, 5 } }) do
			circle(at({ Name = "Crater" .. i, BackgroundColor3 = Color3.fromRGB(226, 210, 166), ZIndex = 2, Parent = moonDisc }, spec[1], spec[2], spec[3], spec[3]))
		end

		-- Étoile filante (une seule, réutilisée)
		WIN.Shooting = frame({ Name = "ShootingStar", AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(34, 2.5), BackgroundColor3 = WHITE, Rotation = 18, Visible = false, ZIndex = 2, Parent = glass })
		UI.Corner(WIN.Shooting, UDim.new(1, 0))
		fade(WIN.Shooting, NumberSequence.new(1, 0), 0)

		-- Oiseau (le jour) ou avion (la nuit) qui traverse le ciel
		WIN.Flyer = frame({ Name = "Flyer", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 7), BackgroundTransparency = 1, Visible = false, ZIndex = 3, Parent = glass })
		WIN.WingL = frame({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(7.5, 3.5), Size = UDim2.fromOffset(7, 2), BackgroundColor3 = Color3.fromRGB(60, 54, 90), ZIndex = 3, Parent = WIN.Flyer })
		WIN.WingR = frame({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(6.5, 3.5), Size = UDim2.fromOffset(7, 2), BackgroundColor3 = Color3.fromRGB(60, 54, 90), ZIndex = 3, Parent = WIN.Flyer })
		WIN.PlaneLight = circle(at({ BackgroundColor3 = Color3.fromRGB(255, 80, 90), ZIndex = 3, Parent = WIN.Flyer }, 7, 3.5, 3, 3))

		-- Nuages qui passent lentement
		for _, spec in ipairs({ { 10, 26, 3 }, { 90, 12, 2 } }) do
			local cloud = frame({ Name = "Cloud", Size = UDim2.fromOffset(46, 18), BackgroundTransparency = 1, ZIndex = 3, Parent = glass })
			for _, puff in ipairs({ { 15, 11, 24, 14 }, { 29, 9, 26, 18 } }) do
				table.insert(WIN.Puffs, circle(at({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, ZIndex = 3, Parent = cloud }, puff[1], puff[2], puff[3], puff[4])))
			end
			cloud.Position = UDim2.fromOffset(spec[1], spec[2])
			table.insert(WIN.Clouds, { Frame = cloud, X = spec[1], Y = spec[2], Speed = spec[3] })
		end

		-- Ville au loin (silhouettes) puis ville proche (fenêtres allumées)
		local x = -2
		for _, spec in ipairs({ { 24, 20 }, { 22, 30 }, { 26, 18 }, { 22, 34 }, { 28, 24 }, { 26, 28 } }) do
			table.insert(WIN.Far, frame({ Name = "FarBuilding", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(x, GLASS_H), Size = UDim2.fromOffset(spec[1], spec[2]), BackgroundColor3 = PALETTES.Night.Far, ZIndex = 4, Parent = glass }))
			x += spec[1] + 1
		end
		local LIGHT_COLORS = { Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 170, 210), Color3.fromRGB(150, 230, 255) }
		x = 2
		local LIT_SPOTS = {
			-- { bâtiment, colonne, rangée } : fenêtres allumées (grosses, lisibles)
			{ 1, 0, 0 }, { 1, 1, 1 }, { 2, 0, 1 }, { 2, 1, 0 }, { 2, 1, 2 },
			{ 3, 1, 0 }, { 4, 0, 0 }, { 4, 1, 1 }, { 5, 1, 0 }, { 5, 0, 1 },
		}
		local buildings = {}
		for index, spec in ipairs({ { 26, 24 }, { 22, 30 }, { 30, 18 }, { 24, 36 }, { 30, 26 } }) do
			local w, h = spec[1], spec[2]
			local building = frame({ Name = "Building", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(x, GLASS_H), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, ZIndex = 5, Parent = glass })
			table.insert(WIN.Near, gradient(building, PALETTES.Night.NearTop, PALETTES.Night.NearLow))
			buildings[index] = building
			if index == 4 then
				-- La tour : antenne + voyant rouge qui clignote
				table.insert(WIN.Roof, frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(2, 9), BackgroundColor3 = PALETTES.Night.NearTop, ZIndex = 5, Parent = building }))
				WIN.TowerLight = circle(at({ BackgroundColor3 = Color3.fromRGB(255, 60, 70), ZIndex = 6, Parent = building }, w / 2, -9, 4, 4))
			elseif index == 5 then
				-- Enseigne néon sur le toit
				local sign = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -1), Size = UDim2.fromOffset(18, 6), BackgroundColor3 = Color3.fromRGB(255, 110, 200), ZIndex = 6, Parent = building })
				UI.Corner(sign, 2)
				WIN.Neon = UI.Stroke(sign, Color3.fromRGB(255, 150, 220), 2, 0.5)
				WIN.NeonSign = sign
			end
			x += w + 3
		end
		for _, spot in ipairs(LIT_SPOTS) do
			local building = buildings[spot[1]]
			local lit = frame({
				Name = "Lit",
				Position = UDim2.fromOffset(4 + spot[2] * 10, 5 + spot[3] * 9),
				Size = UDim2.fromOffset(5, 5),
				BackgroundColor3 = LIGHT_COLORS[random:NextInteger(1, #LIGHT_COLORS)],
				BackgroundTransparency = 1,
				ZIndex = 5,
				Parent = building,
			})
			table.insert(WIN.Lit, { Frame = lit, On = random:NextNumber() < 0.75 })
		end

		-- Pluie : réserve de traits recyclés (aucune création par image)
		for _ = 1, RAIN_DROPS do
			local drop = frame({
				Name = "Rain",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(2, random:NextInteger(12, 18)),
				BackgroundColor3 = RAIN_COLOR,
				BackgroundTransparency = random:NextNumber(0.25, 0.5),
				Rotation = 12,
				ZIndex = 6,
				Parent = glass,
			})
			table.insert(WIN.Drops, { Frame = drop, X = random:NextNumber(0, GLASS_W + 30), Y = random:NextNumber(-20, GLASS_H), Speed = 200 * random:NextNumber(0.85, 1.15) })
		end

		-- Éclair (voile blanc) + reflets sur la vitre
		WIN.Flash = frame({ Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(230, 225, 255), BackgroundTransparency = 1, ZIndex = 8, Parent = glass })
		for _, spec in ipairs({ { 34, 30, 16, 0.86 } }) do
			local reflection = frame(at({ Name = "Reflection", Rotation = 35, BackgroundColor3 = WHITE, BackgroundTransparency = spec[4], ZIndex = 9, Parent = glass }, spec[1], spec[2], spec[3], 120))
			fade(reflection, NumberSequence.new(1, 0.2), 0)
		end

		-- Croisillons de la fenêtre (au-dessus de la vitre)
		frame({ Name = "MullionV", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = WOOD_LIGHT, ZIndex = 10, Parent = windowFrame })
		frame({ Name = "MullionH", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = WOOD_LIGHT, ZIndex = 10, Parent = windowFrame })

		-- Rebord
		local sill = frame({ Name = "Sill", Position = UDim2.fromOffset(WINDOW_X - 10, SILL_Y), Size = UDim2.fromOffset(WINDOW_W + 20, 9), BackgroundColor3 = WHITE, ZIndex = 6, Parent = scene })
		UI.Corner(sill, 3)
		gradient(sill, Color3.fromRGB(246, 222, 186), Color3.fromRGB(180, 146, 112))
		outline(sill, Color3.fromRGB(90, 60, 70), 1.5, 0.3)

		-- Rideaux (plis dans le dégradé) + embrasse, tringle
		local FOLDS = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(226, 128, 160)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(176, 84, 124)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(230, 140, 170)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 80, 120)),
		})
		for side = -1, 1, 2 do
			local cx = side < 0 and WINDOW_X - 14 or WINDOW_X + WINDOW_W - 12
			local curtain = frame({ Name = "Curtain", Position = UDim2.fromOffset(cx, WINDOW_Y - 8), Size = UDim2.fromOffset(26, WINDOW_H + 8), BackgroundColor3 = WHITE, ZIndex = 9, Parent = scene })
			UI.Corner(curtain, 8)
			UI.Gradient(curtain, FOLDS, 0)
			outline(curtain, Color3.fromRGB(96, 36, 70), 1.5, 0.35)
			frame(at({ Name = "Tie", BackgroundColor3 = Color3.fromRGB(255, 214, 120), ZIndex = 9, Parent = curtain }, 13, WINDOW_H - 22, 28, 4))
		end
		local rod = frame({ Name = "Rod", Position = UDim2.fromOffset(WINDOW_X - 18, WINDOW_Y - 11), Size = UDim2.fromOffset(WINDOW_W + 36, 5), BackgroundColor3 = Color3.fromRGB(120, 80, 62), ZIndex = 10, Parent = scene })
		UI.Corner(rod, 2)

		-- Guirlande lumineuse (grosses ampoules) le long de la tringle
		local FAIRY_COLORS = {
			Color3.fromRGB(255, 220, 110),
			Color3.fromRGB(255, 140, 200),
			Color3.fromRGB(120, 230, 255),
			Color3.fromRGB(255, 170, 90),
			Color3.fromRGB(190, 160, 255),
			Color3.fromRGB(140, 240, 170),
		}
		for i = 0, 1 do
			local u0, u1 = i / 2, (i + 1) / 2
			local x0, x1 = WINDOW_X - 4 + u0 * (WINDOW_W + 8), WINDOW_X - 4 + u1 * (WINDOW_W + 8)
			limb({ BackgroundColor3 = Color3.fromRGB(60, 80, 60), BackgroundTransparency = 0.2, ZIndex = 10, Parent = scene }, x0, WINDOW_Y - 6 + math.sin(u0 * math.pi) * 7, x1, WINDOW_Y - 6 + math.sin(u1 * math.pi) * 7, 1.2)
		end
		for i, color in ipairs(FAIRY_COLORS) do
			local u = (i - 0.5) / #FAIRY_COLORS
			local bulbFrame = circle(at({ Name = "Fairy" .. i, BackgroundColor3 = color, ZIndex = 10, Parent = scene }, WINDOW_X - 4 + u * (WINDOW_W + 8), WINDOW_Y - 2 + math.sin(u * math.pi) * 7, 7, 8))
			table.insert(WIN.Fairy, { Frame = bulbFrame, Glow = UI.Stroke(bulbFrame, color, 3, 0.55), Phase = random:NextNumber(0, math.pi * 2) })
		end
	end

	------------------------------------------------------------------
	-- Le chat sur le rebord (dort, se réveille, regarde, bâille)
	------------------------------------------------------------------
	local CAT = {} -- parties animées
	local catX, catBottom = WINDOW_X + 8, SILL_Y + 1
	local CAT_HEAD_X, CAT_HEAD_Y = catX + 80, catBottom - 15
	do
		local cat = frame({ Name = "Cat", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7, Parent = scene })
		-- Queue en deux segments (courbe) : enroulée devant le corps quand il
		-- dort, dressée derrière lui quand il est réveillé (ZIndex changé)
		CAT.Tail1 = limb({ Name = "Tail1", BackgroundColor3 = CAT_DARK, ZIndex = 5, Parent = cat }, catX + 6, catBottom - 6, catX + 20, catBottom - 6, 9)
		outline(CAT.Tail1, CAT_LINE, 1.2, 0.35)
		CAT.Tail2 = limb({ Name = "Tail2", BackgroundColor3 = WHITE, ZIndex = 5, Parent = cat }, catX + 20, catBottom - 6, catX + 32, catBottom - 12, 8)
		UI.Gradient(CAT.Tail2, ColorSequence.new({
			ColorSequenceKeypoint.new(0, CAT_DARK),
			ColorSequenceKeypoint.new(0.6, CAT_DARK),
			ColorSequenceKeypoint.new(0.62, CAT_CREAM),
			ColorSequenceKeypoint.new(1, CAT_CREAM),
		}), 90)
		outline(CAT.Tail2, CAT_LINE, 1.2, 0.35)
		-- Corps (respire), rayures, cuisse
		local body = circle({ Name = "CatBody", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(catX + 36, catBottom), Size = UDim2.fromOffset(74, 30), BackgroundColor3 = WHITE, ZIndex = 2, Parent = cat })
		gradient(body, CAT_LIGHT, CAT_COLOR)
		outline(body, CAT_LINE, 1.5, 0.3)
		CAT.BodyScale = UI.Create("UIScale", { Parent = body })
		for i = 1, 3 do
			frame({ Name = "Stripe", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(22 + i * 11, 1), Size = UDim2.fromOffset(4, 11), Rotation = 12, BackgroundColor3 = CAT_DARK, ZIndex = 2, Parent = body })
		end
		circle(at({ Name = "Thigh", BackgroundColor3 = CAT_DARK, ZIndex = 2, Parent = body }, 16, 18, 24, 20))
		-- Pattes avant repliées
		for i = 0, 1 do
			circle(at({ Name = "Paw", BackgroundColor3 = CAT_CREAM, ZIndex = 4, Parent = cat }, catX + 64 + i * 10, catBottom - 3, 11, 6))
		end
		-- Tête (support qui bouge : levée, penchée)
		local head = frame(at({ Name = "CatHead", BackgroundTransparency = 1, ZIndex = 3, Parent = cat }, CAT_HEAD_X, CAT_HEAD_Y, 44, 38))
		CAT.Head = head
		CAT.Ears = {}
		for side = -1, 1, 2 do
			local ear = frame(at({ Name = "CatEar", BackgroundColor3 = CAT_DARK, Rotation = 45, ZIndex = 1, Parent = head }, 22 + side * 9, 9, 13, 13))
			UI.Corner(ear, 3)
			outline(ear, CAT_LINE, 1.2, 0.35)
			frame(at({ BackgroundColor3 = Color3.fromRGB(255, 160, 170), ZIndex = 1, Parent = ear }, 7.5, 7.5, 6, 6))
			table.insert(CAT.Ears, ear)
		end
		local skull = circle(at({ Name = "Face", BackgroundColor3 = WHITE, ZIndex = 2, Parent = head }, 22, 21, 36, 29))
		gradient(skull, CAT_LIGHT, CAT_COLOR)
		outline(skull, CAT_LINE, 1.5, 0.3)
		-- Joues duveteuses + rayures du front
		circle(at({ Name = "Muzzle", BackgroundColor3 = CAT_CREAM, ZIndex = 2, Parent = head }, 22, 27, 28, 12))
		for i = -1, 1 do
			frame(at({ BackgroundColor3 = CAT_DARK, ZIndex = 3, Parent = head }, 22 + i * 4, 10.5, 2.4, 5 - math.abs(i)))
		end
		-- Yeux fermés (arcs) / ouverts (ovales + reflet)
		CAT.Closed = {}
		CAT.Open = {}
		for side = -1, 1, 2 do
			local closed = arc(at({ Name = "EyeClosed", ZIndex = 3, Parent = head }, 22 + side * 8, 18, 8, 8), Color3.fromRGB(70, 40, 30), 1.8, LOWER_ARC)
			table.insert(CAT.Closed, closed)
			local open = circle(at({ Name = "EyeOpen", BackgroundColor3 = Color3.fromRGB(56, 44, 30), Visible = false, ZIndex = 3, Parent = head }, 22 + side * 8, 20, 6, 7))
			circle(at({ BackgroundColor3 = WHITE, ZIndex = 3, Parent = open }, 4, 2, 2.2, 2.2))
			table.insert(CAT.Open, open)
		end
		frame(at({ Name = "Nose", BackgroundColor3 = Color3.fromRGB(255, 120, 144), ZIndex = 3, Parent = head }, 22, 24, 5, 3.5))
		CAT.Mouth = circle(at({ Name = "Yawn", BackgroundColor3 = Color3.fromRGB(200, 70, 100), Visible = false, ZIndex = 3, Parent = head }, 22, 29, 6, 0))
		-- "Z z z" qui montent quand il dort (3 lettres recyclées)
		CAT.Z = {}
		for i = 1, 3 do
			CAT.Z[i] = label({
				Name = "Z",
				Text = "Z",
				Font = Theme.Fonts.Title,
				TextSize = 14,
				TextColor3 = WHITE,
				TextStrokeColor3 = Color3.fromRGB(60, 40, 110),
				TextStrokeTransparency = 0.3,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(24, 24),
				ZIndex = 19,
				Parent = scene,
			})
		end

		-- Petite plante sur le rebord
		local potX = WINDOW_X + WINDOW_W - 22
		local pot = frame({ Name = "Pot", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(potX, SILL_Y + 1), Size = UDim2.fromOffset(16, 13), BackgroundColor3 = WHITE, ZIndex = 8, Parent = scene })
		UI.Corner(pot, 3)
		gradient(pot, Color3.fromRGB(246, 150, 110), Color3.fromRGB(196, 100, 76))
		for i, rotation in ipairs({ -50, 0, 50 }) do
			local leaf = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(potX, SILL_Y - 10), Size = UDim2.fromOffset(8, 14 + (i % 2) * 4), Rotation = rotation, BackgroundColor3 = i == 2 and LEAF_LIGHT or LEAF_DARK, ZIndex = 8, Parent = scene })
			UI.Corner(leaf, UDim.new(1, 0))
		end
	end

	------------------------------------------------------------------
	-- Étagère à vinyles (amélioration "Vinyl") : 10 emplacements
	------------------------------------------------------------------
	local RACK = { Discs = {} :: { { Disc: Frame, Ring: UIStroke, Label: Frame, X: number } } }
	do
		RACK.Shelf = frame({ Name = "VinylShelf", Position = UDim2.fromOffset(RACK_X - 4, RACK_Y), Size = UDim2.fromOffset(RACK_W + 8, 5), BackgroundColor3 = WHITE, ZIndex = 3, Parent = scene })
		UI.Corner(RACK.Shelf, 2)
		RACK.ShelfGradient = gradient(RACK.Shelf, Color3.fromRGB(226, 174, 126), Color3.fromRGB(140, 94, 66))
		outline(RACK.Shelf, OUTLINE, 1, 0.45)
		local step = RACK_W / MAX_RECORDS
		for i = 1, MAX_RECORDS do
			local x = RACK_X + step * (i - 0.5)
			local disc = circle({
				Name = "RackDisc" .. i,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromOffset(x, RACK_Y),
				Size = UDim2.fromOffset(15, 15),
				BackgroundColor3 = Color3.fromRGB(28, 26, 38),
				ZIndex = 3,
				Parent = scene,
			})
			local ring = UI.Stroke(disc, WHITE, 1.2, 0.7)
			local center = circle(at({ Name = "Label", BackgroundColor3 = RECORD_COLORS[i], ZIndex = 3, Parent = disc }, 7.5, 7.5, 6, 6))
			table.insert(RACK.Discs, { Disc = disc, Ring = ring, Label = center, X = x })
		end
	end

	------------------------------------------------------------------
	-- Ombre de la fille sur le mur (la lampe est à droite)
	------------------------------------------------------------------
	local shadowHead = circle(at({ Name = "ShadowHead", BackgroundColor3 = Color3.fromRGB(16, 8, 34), BackgroundTransparency = 0.8, ZIndex = 4, Parent = scene }, PX - 26, HEAD_Y + 4, 92, 86))

	------------------------------------------------------------------
	-- La fille (corps + tête) derrière le bureau
	------------------------------------------------------------------
	local person = frame({ Name = "Person", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5, Parent = scene })
	local G = {} -- parties animées de la fille

	-- Cheveux longs derrière le dos, capuche, buste
	do
		local backLong = frame(at({ Name = "LongHair", BackgroundColor3 = WHITE, ZIndex = 1, Parent = person }, PX, 126, 84, 56))
		UI.Corner(backLong, 24)
		gradient(backLong, HAIR, HAIR:Lerp(BLACK, 0.3))
		G.Hood = frame(at({ Name = "HoodBack", BackgroundColor3 = WHITE, ZIndex = 2, Parent = person }, PX, 120, 84, 24))
		UI.Corner(G.Hood, 12)
		gradient(G.Hood, HOODIE_DARK:Lerp(WHITE, 0.1), HOODIE_DARK:Lerp(BLACK, 0.12))
	end
	G.Torso = frame(at({ Name = "Torso", BackgroundColor3 = WHITE, ZIndex = 3, Parent = person }, PX, 158, 108, 80))
	UI.Corner(G.Torso, 34)
	UI.Gradient(G.Torso, ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOODIE:Lerp(WHITE, 0.15)),
		ColorSequenceKeypoint.new(0.6, HOODIE),
		ColorSequenceKeypoint.new(1, HOODIE_DARK),
	}), 90)
	outline(G.Torso, Color3.fromRGB(30, 80, 86), 1.5, 0.3)
	-- Lumière chaude de la lampe sur l'épaule droite
	G.Rim = frame({ Name = "RimLight", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WARM_LIGHT, BackgroundTransparency = 0.25, ZIndex = 3, Parent = G.Torso })
	UI.Corner(G.Rim, 34)
	fade(G.Rim, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 0.35) }), 0)
	for side = -1, 1, 2 do
		frame(at({ Name = "String", BackgroundColor3 = Color3.fromRGB(245, 245, 255), ZIndex = 3, Parent = G.Torso }, 54 + side * 9, 20, 3, 18))
	end
	G.Neck = frame(at({ Name = "Neck", BackgroundColor3 = SKIN_SHADE, ZIndex = 4, Parent = person }, PX, 114, 16, 12))
	UI.Corner(G.Neck, 4)
	G.Collar = frame(at({ Name = "Collar", BackgroundColor3 = WHITE, ZIndex = 5, Parent = person }, PX, 123, 58, 15))
	UI.Corner(G.Collar, 8)
	gradient(G.Collar, HOODIE_DARK:Lerp(WHITE, 0.15), HOODIE_DARK)

	-- Tête (support qui hoche : tout ce qui est dedans bouge avec)
	local headHolder = frame(at({ Name = "Head", BackgroundTransparency = 1, ZIndex = 6, Parent = person }, PX, HEAD_Y, 100, 100))
	G.Head = headHolder

	-- Pièce de la tête, centrée sur (x, y) par rapport au centre de la tête
	local function headPart(props: { [string]: any }, x: number, y: number, w: number, h: number): Frame
		props.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
		props.Position = UDim2.new(0.5, x, 0.5, y)
		props.Size = UDim2.fromOffset(w, h)
		props.Parent = props.Parent or headHolder
		return frame(props)
	end

	G.Eyes = {}
	G.Cups = {}
	do
		-- Cheveux (arrière) + mèches sur les côtés
		local backHair = headPart({ Name = "BackHair", BackgroundColor3 = WHITE, ZIndex = 2 }, 0, -2, 74, 70)
		UI.Corner(backHair, UDim.new(1, 0))
		gradient(backHair, HAIR_LIGHT, HAIR)
		outline(backHair, OUTLINE, 1.5, 0.2)
		for side = -1, 1, 2 do
			local lock = headPart({ Name = "Lock", BackgroundColor3 = WHITE, Rotation = side * -5, ZIndex = 4 }, side * 29, 20, 15, 44)
			UI.Corner(lock, 8)
			gradient(lock, HAIR, HAIR:Lerp(BLACK, 0.15))
		end

		-- Visage : yeux baissés (ovales + cils, clignent), joues
		local face = headPart({ Name = "Face", BackgroundColor3 = WHITE, ZIndex = 3 }, 0, 6, 58, 54)
		UI.Corner(face, UDim.new(0.48, 0))
		gradient(face, SKIN, SKIN_SHADE)
		for side = -1, 1, 2 do
			local eye = headPart({ Name = "Eye", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = EYE_INK, ZIndex = 5 }, side * 12, 13, 10, 6)
			UI.Corner(eye, UDim.new(1, 0))
			local shine = circle({ Name = "Shine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(side < 0 and 0.68 or 0.32, 0.36), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = WHITE, ZIndex = 5, Parent = eye })
			local lash = headPart({ Name = "Lash", BackgroundColor3 = LINE_INK, Rotation = side * 9, ZIndex = 6 }, side * 12, 7, 14, 2.6)
			table.insert(G.Eyes, { Eye = eye, Lash = lash, Shine = shine, Side = side })
			headPart({ Name = "Brow", BackgroundColor3 = HAIR, Rotation = side * -6, ZIndex = 5 }, side * 12, -3, 10, 2.2)
			local blush = headPart({ Name = "Blush", BackgroundColor3 = Color3.fromRGB(255, 130, 158), BackgroundTransparency = 0.4, ZIndex = 5 }, side * 18, 18, 12, 6)
			UI.Corner(blush, UDim.new(1, 0))
		end
		-- Bouche : petit arc (sourire), plus grand quand elle lève les yeux
		G.Mouth, G.MouthStroke = arc({ Name = "Mouth", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 19), Size = UDim2.fromOffset(8, 8), ZIndex = 5, Parent = headHolder }, LINE_INK, 1.8, LOWER_ARC)

		-- Frange + reflet
		for _, spec in ipairs({ { -14, -16, 34, 21, -20 }, { 15, -16, 34, 21, 22 }, { 0, -21, 38, 17, 0 } }) do
			local bang = headPart({ Name = "Bang", BackgroundColor3 = WHITE, Rotation = spec[5], ZIndex = 6 }, spec[1], spec[2], spec[3], spec[4])
			UI.Corner(bang, UDim.new(1, 0))
			gradient(bang, HAIR_LIGHT:Lerp(HAIR, 0.45), HAIR)
		end
		local shine = headPart({ Name = "HairShine", BackgroundColor3 = HAIR_LIGHT:Lerp(WHITE, 0.35), BackgroundTransparency = 0.2, Rotation = -18, ZIndex = 7 }, -12, -26, 17, 4)
		UI.Corner(shine, UDim.new(1, 0))

		-- GROS casque : arceau (haut d'un cercle) + deux écouteurs vernis
		local band = headPart({ Name = "Band", BackgroundTransparency = 1, ZIndex = 7 }, 0, 4, 84, 84)
		UI.Corner(band, UDim.new(1, 0))
		local bandStroke = UI.Stroke(band, WHITE, 7, 0)
		UI.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(PHONES:Lerp(WHITE, 0.3), PHONES_DARK), Transparency = UPPER_ARC, Parent = bandStroke })
		G.Leds = {}
		for side = -1, 1, 2 do
			local cushion = headPart({ Name = "Cushion", BackgroundColor3 = Color3.fromRGB(70, 44, 90), ZIndex = 7 }, side * 33, 8, 8, 24)
			UI.Corner(cushion, 3)
			local cup = headPart({ Name = "Cup", BackgroundColor3 = WHITE, ZIndex = 8 }, side * 42, 8, 20, 32)
			UI.Corner(cup, 8)
			UI.Gradient(cup, ColorSequence.new({
				ColorSequenceKeypoint.new(0, PHONES:Lerp(WHITE, 0.35)),
				ColorSequenceKeypoint.new(0.45, PHONES),
				ColorSequenceKeypoint.new(1, PHONES_DARK),
			}), 90)
			outline(cup, Color3.fromRGB(110, 24, 70), 1.5, 0.15)
			table.insert(G.Cups, cup)
			local cupShine = frame({ Name = "CupShine", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(4, 10), BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, ZIndex = 9, Parent = cup })
			UI.Corner(cupShine, UDim.new(1, 0))
			-- Anneau lumineux (pulse sur la musique)
			local led = circle({ Name = "Led", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromOffset(11, 11), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, ZIndex = 9, Parent = cup })
			table.insert(G.Leds, UI.Stroke(led, Color3.fromRGB(255, 230, 245), 2, 0.3))
		end
	end

	------------------------------------------------------------------
	-- Bureau (face avant, plateau, flaque de lumière, objets)
	------------------------------------------------------------------
	local D = {} -- éléments du bureau animés
	do
		-- Face avant créée AVANT le plateau (ZIndex plus bas) : elle remonte
		-- derrière lui et ses coins du bas sont arrondis comme la scène
		-- (ClipsDescendants découpe en rectangle : sinon coins carrés qui dépassent)
		local deskFront = frame({ Name = "DeskFront", Position = UDim2.fromOffset(0, DESK_FRONT - SCENE_RADIUS), Size = UDim2.new(1, 0, 0, SCENE_H - DESK_FRONT + SCENE_RADIUS), BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene })
		UI.Corner(deskFront, SCENE_RADIUS)
		gradient(deskFront, Color3.fromRGB(120, 78, 58), Color3.fromRGB(64, 40, 34))
		-- Deux tiroirs + poignées
		for _, dx in ipairs({ 40, 200 }) do
			local drawer = frame({ Name = "Drawer", Position = UDim2.fromOffset(dx, SCENE_RADIUS + 9), Size = UDim2.fromOffset(128, 24), BackgroundColor3 = Color3.fromRGB(138, 92, 66), ZIndex = 12, Parent = deskFront })
			UI.Corner(drawer, 4)
			outline(drawer, Color3.fromRGB(60, 36, 30), 1.2, 0.35)
			local handle = frame(at({ BackgroundColor3 = Color3.fromRGB(240, 208, 150), ZIndex = 12, Parent = drawer }, 64, 12, 26, 5))
			UI.Corner(handle, 2)
		end
		local deskTop = frame({ Name = "DeskTop", Position = UDim2.fromOffset(0, DESK_Y), Size = UDim2.new(1, 0, 0, DESK_FRONT - DESK_Y), BackgroundColor3 = WHITE, ZIndex = 13, Parent = scene })
		UI.Gradient(deskTop, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 104, 76)),
			ColorSequenceKeypoint.new(0.82, Color3.fromRGB(192, 140, 100)),
			ColorSequenceKeypoint.new(0.86, Color3.fromRGB(226, 176, 128)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(226, 176, 128)),
		}), 90)
		-- La lumière de la lampe déborde sur la face avant du bureau
		D.Spill = frame({ Name = "LightSpill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(316, DESK_FRONT), Size = UDim2.fromOffset(150, 40), BackgroundColor3 = WARM_LIGHT, BackgroundTransparency = 0.78, ZIndex = 13, Parent = scene })
		UI.Corner(D.Spill, 20)
		fade(D.Spill, NumberSequence.new(0, 1))
		-- Ombre portée du plateau sur la face avant
		local lip = frame({ Name = "DeskLip", Position = UDim2.fromOffset(0, DESK_FRONT), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = BLACK, BackgroundTransparency = 0.55, ZIndex = 13, Parent = scene })
		fade(lip, NumberSequence.new(0, 1))
		-- Néon sous le plateau (Vinyl niveau 7) : bande qui change de couleur
		D.Neon = frame({ Name = "DeskNeon", Position = UDim2.fromOffset(4, DESK_FRONT - 1), Size = UDim2.new(1, -8, 0, 3), BackgroundColor3 = Color3.fromRGB(255, 120, 220), Visible = false, ZIndex = 14, Parent = scene })
		UI.Corner(D.Neon, UDim.new(1, 0))
		D.NeonGlow = UI.Stroke(D.Neon, Color3.fromRGB(255, 120, 220), 3, 0.5)
		D.NeonWash = frame({ Name = "NeonWash", Position = UDim2.fromOffset(0, DESK_FRONT + 1), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Color3.fromRGB(255, 120, 220), BackgroundTransparency = 0.6, Visible = false, ZIndex = 13, Parent = scene })
		fade(D.NeonWash, NumberSequence.new(0, 1))

		-- Flaque de lumière chaude sous la lampe
		D.Pool = halo({ Name = "LightPool", BackgroundColor3 = WARM_LIGHT, BackgroundTransparency = 0.7, ZIndex = 14, Parent = scene }, 314, 153, 160, 18, 2)
		-- Ombres douces sous les objets
		for _, spec in ipairs({ { TURNTABLE_X, 92 }, { 350, 34 } }) do
			circle(at({ Name = "ItemShadow", BackgroundColor3 = Color3.fromRGB(40, 20, 16), BackgroundTransparency = 0.7, ZIndex = 14, Parent = scene }, spec[1], ITEM_BASE + 3, spec[2], 6))
		end
		D.MugShadow = circle(at({ Name = "MugShadow", BackgroundColor3 = Color3.fromRGB(40, 20, 16), BackgroundTransparency = 0.7, ZIndex = 14, Parent = scene }, MUG_X + 1, ITEM_BASE + 2, 26, 6))
	end

	------------------------------------------------------------------
	-- Platine vinyle (disque vu de 3/4 qui tourne) + paliers "Vinyl"
	------------------------------------------------------------------
	local TT = {} -- platine
	do
		-- Pochette posée contre le mur derrière la platine (niveau 1)
		TT.Sleeve = frame({ Name = "NowPlaying", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(TURNTABLE_X + 34, DESK_Y + 2), Size = UDim2.fromOffset(30, 30), Rotation = 8, BackgroundColor3 = WHITE, Visible = false, ZIndex = 15, Parent = scene })
		UI.Corner(TT.Sleeve, 3)
		gradient(TT.Sleeve, Color3.fromRGB(255, 150, 190), Color3.fromRGB(110, 90, 220), 45)
		circle(at({ BackgroundColor3 = Color3.fromRGB(255, 240, 180), ZIndex = 15, Parent = TT.Sleeve }, 20, 10, 9, 9))

		-- Enceinte (niveau 5) : la membrane pulse sur le temps
		TT.Speaker = frame({ Name = "Speaker", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(TURNTABLE_X + 60, ITEM_BASE + 3), Size = UDim2.fromOffset(20, 32), BackgroundColor3 = WHITE, Visible = false, ZIndex = 16, Parent = scene })
		UI.Corner(TT.Speaker, 4)
		gradient(TT.Speaker, Color3.fromRGB(156, 108, 78), Color3.fromRGB(96, 62, 46))
		outline(TT.Speaker, OUTLINE, 1.2, 0.3)
		TT.Woofer = circle(at({ Name = "Woofer", BackgroundColor3 = Color3.fromRGB(40, 34, 44), ZIndex = 16, Parent = TT.Speaker }, 10, 18, 14, 14))
		UI.Stroke(TT.Woofer, Color3.fromRGB(150, 140, 160), 1.2, 0.2)

		-- Corps de la platine (bois clair) : boutons + voyant
		local body = frame({ Name = "Turntable", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(TURNTABLE_X, ITEM_BASE + 3), Size = UDim2.fromOffset(TT_W, 13), BackgroundColor3 = WHITE, ZIndex = 16, Parent = scene })
		UI.Corner(body, 3)
		gradient(body, Color3.fromRGB(250, 236, 214), Color3.fromRGB(200, 170, 138))
		outline(body, OUTLINE, 1.2, 0.3)
		circle(at({ BackgroundColor3 = Color3.fromRGB(90, 80, 90), ZIndex = 16, Parent = body }, 10, 6.5, 7, 7))
		TT.LedLight = circle(at({ BackgroundColor3 = Color3.fromRGB(90, 255, 150), ZIndex = 16, Parent = body }, TT_W - 9, 6.5, 5, 5))
		-- Plateau vu de 3/4 + vinyle (dégradé qui tourne), étiquette, reflet
		-- qui tourne autour du disque (la rotation se voit bien)
		local top = frame({ Name = "Deck", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(TURNTABLE_X, ITEM_BASE - 9), Size = UDim2.fromOffset(TT_W, 22), BackgroundColor3 = WHITE, ZIndex = 16, Parent = scene })
		UI.Corner(top, 6)
		gradient(top, Color3.fromRGB(240, 222, 200), Color3.fromRGB(222, 198, 170))
		outline(top, OUTLINE, 1.2, 0.3)
		local platter = circle(at({ Name = "Vinyl", BackgroundColor3 = WHITE, ZIndex = 16, Parent = top }, 36, 11, 64, 18))
		TT.Spin = UI.Gradient(platter, vinylLook(0), 0)
		TT.Label = circle(at({ Name = "Label", BackgroundColor3 = WHITE, ZIndex = 16, Parent = platter }, 32, 9, 18, 6))
		UI.Gradient(TT.Label, ColorSequence.new(EQ_LOW, EQ_HIGH), 0)
		TT.Glint = circle(at({ Name = "Glint", BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, ZIndex = 16, Parent = platter }, 32, 3, 8, 3))
		-- Bras de lecture (pivot à droite, pointe sur le disque)
		TT.Pivot = circle(at({ Name = "Pivot", BackgroundColor3 = Color3.fromRGB(180, 180, 196), ZIndex = 16, Parent = top }, TT_W - 9, 7, 9, 9))
		outline(TT.Pivot, OUTLINE, 1, 0.4)
		TT.Arm = limb({ Name = "Tonearm", BackgroundColor3 = Color3.fromRGB(210, 210, 224), ZIndex = 16, Parent = scene }, TURNTABLE_X + TT_W / 2 - 9, ITEM_BASE - 24, TURNTABLE_X + 16, ITEM_BASE - 17, 3)
		TT.ArmRest = TT.Arm.Rotation
	end

	------------------------------------------------------------------
	-- Lampe de bureau articulée
	------------------------------------------------------------------
	local LAMP = {}
	do
		local ARM = Color3.fromRGB(96, 96, 116)
		limb({ Name = "LampArm", BackgroundColor3 = ARM, ZIndex = 16, Parent = scene }, LAMP_X + 16, ITEM_BASE - 2, LAMP_X + 24, 122, 5)
		limb({ Name = "LampArm2", BackgroundColor3 = ARM, ZIndex = 16, Parent = scene }, LAMP_X + 24, 122, LAMP_X + 4, 102, 5)
		local base = frame(at({ Name = "LampBase", BackgroundColor3 = WHITE, ZIndex = 16, Parent = scene }, LAMP_X + 16, ITEM_BASE, 32, 8))
		UI.Corner(base, 3)
		gradient(base, Color3.fromRGB(124, 124, 146), Color3.fromRGB(52, 52, 64))
		-- Cône de lumière (plus lumineux près de l'ampoule)
		LAMP.Rays = {}
		for i, spec in ipairs({ { -8, 0.7 } }) do
			local ray = limb({ Name = "LightRay" .. i, BackgroundColor3 = WARM_LIGHT, BackgroundTransparency = spec[2], ZIndex = 15, Parent = scene }, LAMP_X - 8, 110, LAMP_X - 8 + spec[1], DESK_FRONT + 2, 64)
			fade(ray, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1) }))
			table.insert(LAMP.Rays, { Frame = ray, Alpha = spec[2] })
		end
		local shade = frame(at({ Name = "LampShade", BackgroundColor3 = WHITE, Rotation = -20, ZIndex = 16, Parent = scene }, LAMP_X - 2, 101, 46, 20))
		UI.Corner(shade, UDim.new(0.5, 0))
		gradient(shade, Color3.fromRGB(255, 210, 100), Color3.fromRGB(232, 112, 60))
		outline(shade, Color3.fromRGB(120, 50, 30), 1.5, 0.25)
		LAMP.Bulb = circle({ Name = "Bulb", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(15, 9), BackgroundColor3 = Color3.fromRGB(255, 250, 210), ZIndex = 16, Parent = shade })
		LAMP.BulbGlow = circle(at({ Name = "BulbGlow", BackgroundColor3 = Color3.fromRGB(255, 240, 190), BackgroundTransparency = 0.55, ZIndex = 16, Parent = scene }, LAMP_X - 6, 110, 30, 18))
	end

	------------------------------------------------------------------
	-- Rayon de lumière de la fenêtre (lune la nuit, soleil le jour)
	------------------------------------------------------------------
	local shaft = limb({ Name = "WindowLight", BackgroundColor3 = PALETTES.Night.Shaft, BackgroundTransparency = 0.8, ZIndex = 14, Parent = scene }, SHAFT_X1, SHAFT_Y1, SHAFT_X2, SHAFT_Y2, 70)
	fade(shaft, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.55, 0.65), NumberSequenceKeypoint.new(1, 1) }))

	------------------------------------------------------------------
	-- Mains sur le bureau : cahier, bras, crayon, tasse (devant le bureau)
	------------------------------------------------------------------
	local hands = frame({ Name = "Hands", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 17, Parent = scene })
	local H = {} -- parties animées des mains

	-- Cahier ouvert (page de gauche déjà écrite, page de droite en cours)
	local NOTE_W, NOTE_H = 80, 17
	local NOTE_Y = 155
	local noteLeft, noteTop = PX - NOTE_W / 2, NOTE_Y - NOTE_H / 2
	local WRITE_X, WRITE_W = 45, 30 -- zone d'écriture (page de droite)
	do
		local notebook = frame(at({ Name = "Notebook", BackgroundColor3 = WHITE, ZIndex = 1, Parent = hands }, PX, NOTE_Y, NOTE_W, NOTE_H))
		UI.Corner(notebook, 3)
		UI.Gradient(notebook, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(236, 228, 212)),
			ColorSequenceKeypoint.new(0.46, WHITE),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(196, 186, 170)),
			ColorSequenceKeypoint.new(0.54, WHITE),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 228, 212)),
		}), 0)
		outline(notebook, OUTLINE, 1.2, 0.35)
		-- Page de gauche : déjà écrite (mots)
		for i = 1, 2 do
			local written = frame({ Name = "Written" .. i, Position = UDim2.fromOffset(6, 4 + (i - 1) * 6), Size = UDim2.fromOffset(i == 1 and 30 or 22, 2), BackgroundColor3 = LINE_INK, BackgroundTransparency = 0.3, ZIndex = 2, Parent = notebook })
			fade(written, WORDS, 0)
		end
		-- Page de droite : les mots apparaissent au passage du crayon
		-- (fenêtre qui s'élargit et découpe la ligne complète)
		H.Lines = {}
		for i = 1, 2 do
			local reveal = frame({ Name = "Reveal" .. i, Position = UDim2.fromOffset(WRITE_X, 3.5 + (i - 1) * 6), Size = UDim2.fromOffset(0, 3), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2, Parent = notebook })
			local ink = frame({ Name = "Ink", Position = UDim2.fromOffset(0, 0.5), Size = UDim2.fromOffset(WRITE_W, 2), BackgroundColor3 = LINE_INK, BackgroundTransparency = 0.05, ZIndex = 2, Parent = reveal })
			fade(ink, WORDS, 0)
			H.Lines[i] = reveal
		end
		-- Page qui se tourne (feuille qui passe de droite à gauche)
		H.Page = frame({ Name = "TurningPage", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(NOTE_W / 2, NOTE_H / 2), Size = UDim2.fromOffset(0, NOTE_H + 2), BackgroundColor3 = Color3.fromRGB(255, 252, 244), Visible = false, ZIndex = 3, Parent = notebook })
		UI.Corner(H.Page, 2)
		UI.Stroke(H.Page, Color3.fromRGB(150, 130, 120), 1, 0.4)
	end

	-- Tasse fumante (posée à gauche ; elle la boit de temps en temps)
	H.Mug = frame(at({ Name = "Mug", BackgroundTransparency = 1, ZIndex = 2, Parent = hands }, MUG_X, MUG_Y, 34, 34))
	do
		local handleRing = circle(at({ Name = "Handle", BackgroundTransparency = 1, ZIndex = 2, Parent = H.Mug }, 6, 17, 11, 11))
		UI.Stroke(handleRing, Color3.fromRGB(236, 228, 218), 3, 0)
		local cup = frame(at({ Name = "Cup", BackgroundColor3 = WHITE, ZIndex = 2, Parent = H.Mug }, 17, 17, 20, 22))
		UI.Corner(cup, 5)
		gradient(cup, Color3.fromRGB(255, 250, 240), Color3.fromRGB(214, 206, 196), 0)
		outline(cup, OUTLINE, 1.2, 0.3)
		frame(at({ Name = "Stripe", BackgroundColor3 = PHONES, ZIndex = 2, Parent = cup }, 10, 13, 20, 4))
		circle(at({ Name = "Coffee", BackgroundColor3 = Color3.fromRGB(110, 66, 44), ZIndex = 2, Parent = H.Mug }, 17, 8, 16, 5))
	end
	H.Steam = {}
	for i = 1, 3 do
		H.Steam[i] = circle({ Name = "Steam", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 3, Parent = hands })
	end

	-- Manches du sweat (dégradé le long du bras, poignet plus foncé)
	local SLEEVE = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOODIE),
		ColorSequenceKeypoint.new(0.8, HOODIE:Lerp(HOODIE_DARK, 0.3)),
		ColorSequenceKeypoint.new(0.82, HOODIE_DARK),
		ColorSequenceKeypoint.new(1, HOODIE_DARK),
	})
	local UPPER_SLEEVE = ColorSequence.new(HOODIE:Lerp(WHITE, 0.12), HOODIE_DARK)
	local SLEEVE_LINE = Color3.fromRGB(30, 80, 86)
	local L_SHOULDER = Vector2.new(PX - 38, 130)
	local L_REST_ELBOW, L_REST_HAND = Vector2.new(PX - 56, 152), Vector2.new(PX - 18, 156)
	local R_SHOULDER = Vector2.new(PX + 38, 130)
	local R_ELBOW = Vector2.new(PX + 58, 152)
	do
		H.LeftUpper = limb({ Name = "LeftUpperArm", BackgroundColor3 = WHITE, ZIndex = 4, Parent = hands }, L_SHOULDER.X, L_SHOULDER.Y, L_REST_ELBOW.X, L_REST_ELBOW.Y, 20)
		UI.Gradient(H.LeftUpper, UPPER_SLEEVE, 0)
		outline(H.LeftUpper, SLEEVE_LINE, 1.2, 0.35)
		H.LeftFore = limb({ Name = "LeftForearm", BackgroundColor3 = WHITE, ZIndex = 4, Parent = hands }, L_REST_ELBOW.X, L_REST_ELBOW.Y, L_REST_HAND.X - 5, L_REST_HAND.Y, 17)
		UI.Gradient(H.LeftFore, SLEEVE, 90)
		outline(H.LeftFore, SLEEVE_LINE, 1.2, 0.35)
		H.LeftHand = circle(at({ Name = "LeftHand", BackgroundColor3 = WHITE, ZIndex = 6, Parent = hands }, L_REST_HAND.X, L_REST_HAND.Y, 13, 12))
		gradient(H.LeftHand, SKIN, SKIN_SHADE)
		local rightUpper = limb({ Name = "RightUpperArm", BackgroundColor3 = WHITE, ZIndex = 4, Parent = hands }, R_SHOULDER.X, R_SHOULDER.Y, R_ELBOW.X, R_ELBOW.Y, 20)
		UI.Gradient(rightUpper, UPPER_SLEEVE, 180)
		outline(rightUpper, SLEEVE_LINE, 1.2, 0.35)
		H.RightFore = limb({ Name = "RightForearm", BackgroundColor3 = WHITE, ZIndex = 4, Parent = hands }, R_ELBOW.X, R_ELBOW.Y, PX + 20, 152, 17)
		UI.Gradient(H.RightFore, SLEEVE, 90)
		outline(H.RightFore, SLEEVE_LINE, 1.2, 0.35)
		H.Pencil = limb({ Name = "Pencil", BackgroundColor3 = WHITE, ZIndex = 5, Parent = hands }, PX + 10, 155, PX + 20, 136, 4)
		UI.Gradient(H.Pencil, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 56, 70)),
			ColorSequenceKeypoint.new(0.12, Color3.fromRGB(60, 56, 70)),
			ColorSequenceKeypoint.new(0.13, Color3.fromRGB(242, 206, 158)),
			ColorSequenceKeypoint.new(0.26, Color3.fromRGB(242, 206, 158)),
			ColorSequenceKeypoint.new(0.27, Color3.fromRGB(255, 204, 60)),
			ColorSequenceKeypoint.new(0.86, Color3.fromRGB(255, 190, 40)),
			ColorSequenceKeypoint.new(0.87, Color3.fromRGB(255, 140, 164)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 164)),
		}), 90)
		H.RightHand = circle(at({ Name = "RightHand", BackgroundColor3 = WHITE, ZIndex = 6, Parent = hands }, PX + 14, 150, 13, 12))
		gradient(H.RightHand, SKIN, SKIN_SHADE)
	end

	------------------------------------------------------------------
	-- Particules : notes de musique (et petits cœurs)
	------------------------------------------------------------------
	local notes: { { Label: TextLabel, Active: boolean, Age: number, X: number, Y: number, Dir: number, Rise: number } } = {}
	for i = 1, NOTE_POOL do
		local noteLabel = label({
			Name = "Note",
			Text = i % 2 == 1 and "♪" or "♫",
			Font = Theme.Fonts.Title,
			TextSize = 18,
			TextColor3 = NOTE_COLORS[(i - 1) % #NOTE_COLORS + 1],
			TextStrokeColor3 = Color3.fromRGB(40, 20, 60),
			TextStrokeTransparency = 0.35,
			TextTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(24, 24),
			Visible = false,
			ZIndex = 19,
			Parent = scene,
		})
		table.insert(notes, { Label = noteLabel, Active = false, Age = 0, X = 0, Y = 0, Dir = 1, Rise = 58 })
	end

	local function spawnNote(x: number, y: number, dir: number, rise: number, heart: boolean?)
		for _, n in ipairs(notes) do
			if not n.Active then
				n.Active = true
				n.Age = 0
				n.Dir = dir
				n.X, n.Y = x, y
				n.Rise = rise
				if heart then
					n.Label.TextColor3 = HEART_COLOR
					n.Label.Text = "♥"
				else
					S.noteColorIndex = S.noteColorIndex % #NOTE_COLORS + 1
					n.Label.TextColor3 = NOTE_COLORS[S.noteColorIndex]
					n.Label.Text = random:NextNumber() < 0.5 and "♪" or "♫"
				end
				n.Label.Visible = true
				return
			end
		end
	end

	------------------------------------------------------------------
	-- Vignettage (bords plus sombres : profondeur, regard vers le centre)
	------------------------------------------------------------------
	do
		local vertical = frame({ Name = "VignetteY", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 4, 24), ZIndex = 20, Parent = scene })
		UI.Corner(vertical, SCENE_RADIUS)
		fade(vertical, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.1, 1),
			NumberSequenceKeypoint.new(0.82, 1),
			NumberSequenceKeypoint.new(1, 0.5),
		}), 90)
	end

	------------------------------------------------------------------
	-- Barre du bas : lecteur (pochette + vinyle, morceau, progression,
	-- temps, visualiseur, ⏭)
	------------------------------------------------------------------
	local isStudio = RunService:IsStudio()
	local B = { LayoutKey = "" } -- éléments du lecteur
	local bar = frame({ Name = "Bar", Position = UDim2.fromOffset(SCENE_X, BAR_Y), Size = UDim2.fromOffset(SCENE_W, BAR_H), BackgroundColor3 = WHITE, Parent = card })
	UI.Corner(bar, 10)
	gradient(bar, Color3.fromRGB(46, 36, 80), Color3.fromRGB(20, 16, 36))
	UI.Stroke(bar, Color3.fromRGB(130, 104, 196), 1, 0.4)

	-- Vinyle qui sort de sa pochette (tourne pendant la musique)
	B.Disc = circle({ Name = "Vinyl", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(35, BAR_H / 2), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Color3.fromRGB(28, 26, 34), ZIndex = 1, Parent = bar })
	do
		UI.Stroke(B.Disc, Color3.fromRGB(70, 64, 90), 1)
		local labelDisc = circle(at({ Name = "Label", BackgroundColor3 = WHITE, ZIndex = 1, Parent = B.Disc }, 16, 16, 11, 11))
		UI.Gradient(labelDisc, ColorSequence.new(EQ_LOW, EQ_HIGH), 0)
		frame({ Name = "Shine", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -6), Size = UDim2.fromOffset(2, 7), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, ZIndex = 1, Parent = B.Disc })
		-- Pochette (ciel de nuit, lune, ville), par-dessus le disque
		local art = frame(at({ Name = "Cover", BackgroundColor3 = WHITE, ZIndex = 2, Parent = bar }, 22, BAR_H / 2, 32, 32))
		UI.Corner(art, 6)
		UI.Gradient(art, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 30, 100)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(150, 80, 160)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 150)),
		}), 90)
		UI.Stroke(art, WHITE, 1, 0.6)
		circle(at({ BackgroundColor3 = Color3.fromRGB(255, 244, 200), ZIndex = 2, Parent = art }, 22, 9, 8, 8))
		for i, h in ipairs({ 9, 14, 11 }) do
			frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(3 + (i - 1) * 9, 32), Size = UDim2.fromOffset(8, h), BackgroundColor3 = Color3.fromRGB(30, 22, 60), ZIndex = 2, Parent = art })
		end
	end

	local TEXT_X = 62
	B.Title = label({
		Name = "Title",
		Text = Locale.T("lofi beats 🎧 to study to"),
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(TEXT_X, 3),
		Size = UDim2.fromOffset(190, 17),
		Parent = bar,
	})
	B.Subtitle = label({
		Name = "Subtitle",
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(200, 186, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(TEXT_X, 19),
		Size = UDim2.fromOffset(150, 13),
		Parent = bar,
	})
	B.Time = label({
		Name = "Time",
		Text = "0:00 / 0:00",
		Font = Theme.Fonts.Body,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(170, 156, 214),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(TEXT_X + 190, 36),
		Size = UDim2.fromOffset(58, 12),
		Parent = bar,
	})
	-- Barre de progression du morceau
	B.Progress = frame({ Name = "Progress", Position = UDim2.fromOffset(TEXT_X, 35), Size = UDim2.fromOffset(128, 3), BackgroundColor3 = Color3.fromRGB(80, 66, 130), Parent = bar })
	UI.Corner(B.Progress, UDim.new(1, 0))
	B.Fill = frame({ Name = "Fill", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = WHITE, Parent = B.Progress })
	UI.Corner(B.Fill, UDim.new(1, 0))
	UI.Gradient(B.Fill, ColorSequence.new(EQ_LOW, EQ_HIGH), 0)
	B.Knob = circle({ Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3, 0.5), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = WHITE, Parent = B.Progress })

	-- Bouton "morceau suivant"
	B.Skip = UI.Create("TextButton", {
		Name = "Next",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Color3.fromRGB(56, 44, 90),
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "⏭",
		TextColor3 = WHITE,
		TextSize = 15,
		Visible = false,
		Parent = bar,
	})
	UI.Corner(B.Skip, UDim.new(1, 0))
	UI.Stroke(B.Skip, EQ_HIGH, 1.5, 0.4)
	UI.AnimateButton(B.Skip, 1.1, 0.88)

	-- Visualiseur audio (barres arrondies, du rose au bleu)
	local EQ_W, EQ_H = 74, 28
	B.Eq = frame({ Name = "Equalizer", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(EQ_W, EQ_H), BackgroundTransparency = 1, Parent = bar })
	local barWidth = 4
	local barGap = (EQ_W - EQ_BARS * barWidth) / (EQ_BARS - 1)
	local eqBars: { Frame } = {}
	local eqHeights: { number } = {}
	local eqTargets: { number } = {}
	for i = 1, EQ_BARS do
		local t = (i - 1) / (EQ_BARS - 1)
		local eqBar = frame({ Name = "Bar" .. i, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, (i - 1) * (barWidth + barGap), 1, 0), Size = UDim2.fromOffset(barWidth, 4), BackgroundColor3 = EQ_LOW:Lerp(EQ_HIGH, t), Parent = B.Eq })
		eqBars[i] = eqBar
		eqHeights[i] = 0.2
		eqTargets[i] = 0.2
	end

	------------------------------------------------------------------
	-- État du lecteur : vraie musique, musique coupée, ou pas de musique
	------------------------------------------------------------------
	S.viewers = random:NextInteger(8000, 14000)
	local tracks = Locale.Pick(TRACKS)
	S.trackIndex = random:NextInteger(1, #tracks)

	local function hasPlaylist(): boolean
		if type(Sound.HasPlaylist) ~= "function" then
			return false
		end
		local ok, value = pcall(Sound.HasPlaylist)
		return ok and value == true
	end

	-- Relit le morceau en cours : S.musicName (si de la vraie musique joue)
	-- et S.musicSound (le Sound, pour le volume réel et la progression).
	-- v8 : SoundManager.GetMusicInfo() -> { Key, Name, Index, Count, Playing }
	-- (si présent), sinon l'ancienne API GetCurrentTrack / IsMusicPlaying.
	local function refreshMusic()
		local name: string? = nil
		local sound: Sound? = nil
		local infoKnown = false
		if type(Sound.GetMusicInfo) == "function" then
			local ok, info = pcall(Sound.GetMusicInfo)
			if ok and type(info) == "table" then
				infoKnown = true
				if info.Playing ~= false and type(info.Name) == "string" and info.Name ~= "" then
					name = info.Name
				end
			end
		end
		if type(Sound.GetCurrentTrack) == "function" and type(Sound.IsMusicPlaying) == "function" then
			local okPlaying, playing = pcall(Sound.IsMusicPlaying)
			if okPlaying and playing == true then
				local okTrack, trackName, trackSound = pcall(Sound.GetCurrentTrack)
				if okTrack then
					if not infoKnown and type(trackName) == "string" then
						name = trackName
					end
					if typeof(trackSound) == "Instance" and trackSound:IsA("Sound") then
						sound = trackSound
					end
				end
			end
		end
		S.musicName = name
		S.musicSound = sound
	end

	local function viewersText(): string
		local count = S.viewers >= 1e6 and Format.Format(S.viewers) or Format.WithSpaces(S.viewers)
		return "🔴 " .. Locale.T("%s people studying (or not)", count)
	end

	local function isCompact(): boolean
		local scale = 1
		if type(ctx.GetSlotScale) == "function" then
			local ok, value = pcall(ctx.GetSlotScale)
			scale = ok and tonumber(value) or 1
		end
		return scale < 0.62
	end

	-- Mise en page du lecteur (textes plus gros sur petit écran)
	local function layoutBar()
		local compact = isCompact()
		local skipVisible = S.musicName ~= nil and type(Sound.NextTrack) == "function"
		local key = (compact and "C" or "N") .. (skipVisible and "S" or "")
		if key == B.LayoutKey then
			return
		end
		B.LayoutKey = key
		B.Skip.Visible = skipVisible
		local eqW = compact and 50 or EQ_W
		B.Eq.Size = UDim2.fromOffset(eqW, EQ_H)
		B.Eq.Position = B.Skip.Visible and UDim2.new(1, -44, 0.5, 0) or UDim2.new(1, -10, 0.5, 0)
		local w = compact and 3 or barWidth
		local gap = (eqW - EQ_BARS * w) / (EQ_BARS - 1)
		for i, eqBar in ipairs(eqBars) do
			eqBar.Size = UDim2.fromOffset(w, eqBar.Size.Y.Offset)
			eqBar.Position = UDim2.new(0, (i - 1) * (w + gap), 1, 0)
		end
		-- Textes : toute la place jusqu'au visualiseur
		local textWidth = SCENE_W - TEXT_X - eqW - (B.Skip.Visible and 52 or 20)
		if compact then
			B.Title.TextSize = 21
			B.Title.Position = UDim2.fromOffset(TEXT_X, 1)
			B.Title.Size = UDim2.fromOffset(textWidth, 26)
			B.Subtitle.Visible = false
			B.Time.Visible = false
			B.Progress.Position = UDim2.fromOffset(TEXT_X, 32)
			B.Progress.Size = UDim2.fromOffset(textWidth, 5)
		else
			B.Title.TextSize = 14
			B.Title.Position = UDim2.fromOffset(TEXT_X, 3)
			B.Title.Size = UDim2.fromOffset(textWidth, 17)
			B.Subtitle.Visible = true
			B.Time.Visible = true
			B.Subtitle.Size = UDim2.fromOffset(textWidth, 13)
			B.Time.Position = UDim2.fromOffset(TEXT_X + textWidth, 36)
			B.Progress.Position = UDim2.fromOffset(TEXT_X, 35)
			B.Progress.Size = UDim2.fromOffset(textWidth - 62, 3)
		end
	end

	local function refreshSubtitle()
		refreshMusic()
		local name = S.musicName
		local playlist = hasPlaylist()
		layoutBar()
		B.Subtitle.TextColor3 = Color3.fromRGB(200, 186, 240)
		if name then
			-- Vraie musique
			B.Title.Text = "♫ " .. Locale.T(name)
			B.Subtitle.Text = S.showAlt and Locale.T("lofi beats 🎧 to study to") or viewersText()
		elseif playlist then
			-- Musique disponible mais coupée (réglage) ou en chargement
			B.Title.Text = Locale.T("lofi beats 🎧 to study to")
			local musicOn = true
			if type(Sound.IsMusicEnabled) == "function" then
				local ok, value = pcall(Sound.IsMusicEnabled)
				musicOn = not ok or value ~= false
			end
			if S.showAlt then
				B.Subtitle.Text = musicOn and Locale.T("♫ Loading music...") or Locale.T("🔇 Music off (⚙️ Settings)")
			else
				B.Subtitle.Text = viewersText()
			end
		elseif isStudio then
			-- Rappel pour le créateur du jeu (seulement dans Studio)
			B.Title.Text = Locale.T("lofi beats 🎧 to study to")
			B.Subtitle.Text = Locale.T("⚠️ Add some music in Config.Music")
			B.Subtitle.TextColor3 = Color3.fromRGB(255, 200, 90)
		else
			-- Pas de musique : juste l'ambiance
			B.Title.Text = Locale.T("lofi beats 🎧 to study to")
			B.Subtitle.Text = S.showAlt and ("♫ " .. tracks[S.trackIndex]) or viewersText()
		end
	end
	refreshSubtitle()

	-- Réagit tout de suite aux changements de morceau / de réglage
	local function onTrackChanged()
		if not ctx.IsAlive() then
			return
		end
		refreshSubtitle()
		B.Title.TextTransparency = 1
		UI.Tween(B.Title, 0.4, { TextTransparency = 0 })
		S.discSpin = math.max(S.discSpin, 8)
	end
	local function connectSignal(signal: any, callback: (...any) -> ())
		if type(signal) == "table" and type(signal.Connect) == "function" then
			ctx.Connect(signal, callback)
		elseif typeof(signal) == "RBXScriptSignal" then
			ctx.Connect(signal, callback)
		end
	end
	connectSignal(Sound.MusicChanged, onTrackChanged)
	connectSignal(Sound.TrackChanged, onTrackChanged)
	connectSignal(Sound.MusicStateChanged, function()
		if ctx.IsAlive() then
			refreshSubtitle()
		end
	end)

	ctx.Connect(B.Skip.Activated, function()
		if not ctx.IsAlive() or type(Sound.NextTrack) ~= "function" then
			return
		end
		local ok, changed = pcall(Sound.NextTrack)
		if ok and changed then
			S.discSpin = 12 -- petit coup de vinyle
		end
	end)

	------------------------------------------------------------------
	-- Heure locale : ciel, lumières
	------------------------------------------------------------------
	local function localHour(): number
		-- Roblox : os.date ne gère que "*t" / "!*t" (heure locale du joueur)
		local now = os.date("*t")
		if type(now) == "table" and now.hour and now.min then
			return (now.hour + now.min / 60) % 24
		end
		return 22
	end

	-- Soleil (6 h → 20 h) ou lune (20 h → 6 h) : arc de gauche à droite
	local function placeSky(hour: number)
		local isSun = hour >= 6 and hour < 20
		local t = isSun and (hour - 6) / 14 or ((hour - 20) % 24) / 10
		local x = 22 + t * (GLASS_W - 44)
		local y = 44 - math.sqrt(math.sin(t * math.pi)) * 30
		WIN.Sun.Visible = isSun
		WIN.Moon.Visible = not isSun
		local body = isSun and WIN.Sun or WIN.Moon
		body.Position = UDim2.fromOffset(x, y)
	end

	-- Fenêtres allumées de la ville (la nuit seulement)
	local function refreshCityLights()
		for _, lit in ipairs(WIN.Lit) do
			lit.Frame.BackgroundTransparency = lit.On and (0.05 + (1 - S.night) * 0.95) or 1
		end
	end

	-- Applique l'ambiance (heure + pluie) : appelé rarement (toutes les
	-- 10 s, ou quand l'intensité de la pluie a changé)
	local function applyPalette()
		local P = paletteAt(S.hour)
		S.palette = P
		S.night = P.Night
		S.lampPower = P.Lamp
		S.skyRain = S.rain
		local wet = S.rain * 0.3
		WIN.Sky.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, P.SkyTop:Lerp(RAIN_SKY, wet)),
			ColorSequenceKeypoint.new(0.55, P.SkyMid:Lerp(RAIN_SKY, wet)),
			ColorSequenceKeypoint.new(1, P.SkyLow:Lerp(RAIN_SKY, wet * 0.7)),
		})
		WIN.Horizon.BackgroundColor3 = P.Glow
		WIN.Horizon.BackgroundTransparency = 1 - P.GlowPower * (1 - S.rain * 0.3)
		wallGradient.Color = ColorSequence.new(P.WallTop, P.WallLow)
		local cloudColor = P.Cloud:Lerp(Color3.fromRGB(150, 150, 176), S.rain * 0.35)
		local cloudAlpha = math.clamp(P.CloudAlpha - S.rain * 0.12, 0, 1)
		for _, puff in ipairs(WIN.Puffs) do
			puff.BackgroundColor3 = cloudColor
			puff.BackgroundTransparency = cloudAlpha
		end
		for _, far in ipairs(WIN.Far) do
			far.BackgroundColor3 = P.Far
		end
		local near = ColorSequence.new(P.NearTop, P.NearLow)
		for _, g in ipairs(WIN.Near) do
			g.Color = near
		end
		for _, part in ipairs(WIN.Roof) do
			part.BackgroundColor3 = P.NearTop
		end
		refreshCityLights()
		shaft.BackgroundColor3 = P.Shaft
		shaft.BackgroundTransparency = 1 - 0.3 * P.ShaftPower * (1 - S.rain * 0.45)
		placeSky(S.hour)
	end

	-- Collection de vinyles (amélioration "Vinyl") : un disque par niveau
	-- sur l'étagère + paliers visibles sur la platine
	local function refreshVinyl()
		local level = math.clamp(math.floor(tonumber(ctx.GetLevel("Vinyl")) or 0), 0, MAX_RECORDS)
		if level == S.vinylLevel then
			return
		end
		local grew = S.vinylLevel >= 0 and level > S.vinylLevel
		S.vinylLevel = level
		for i, slot in ipairs(RACK.Discs) do
			local owned = i <= level
			local gold = owned and i == MAX_RECORDS
			-- Emplacement vide : cercle en pointillé ; disque : noir (or au niveau 10)
			slot.Disc.BackgroundTransparency = owned and 0 or 1
			slot.Disc.BackgroundColor3 = gold and GOLD or Color3.fromRGB(28, 26, 38)
			slot.Ring.Color = gold and Color3.fromRGB(255, 244, 190) or (owned and Color3.fromRGB(110, 100, 140) or WHITE)
			slot.Ring.Transparency = owned and 0.1 or 0.72
			slot.Label.Visible = owned
		end
		RACK.ShelfGradient.Color = level >= 10 and ColorSequence.new(Color3.fromRGB(255, 232, 140), GOLD_DARK) or ColorSequence.new(Color3.fromRGB(226, 174, 126), Color3.fromRGB(140, 94, 66))
		TT.Sleeve.Visible = level >= 1
		TT.Speaker.Visible = level >= 5
		D.Neon.Visible = level >= 7
		D.NeonWash.Visible = level >= 7
		TT.Spin.Color = vinylLook(level)
		TT.Arm.BackgroundColor3 = level >= 10 and Color3.fromRGB(255, 214, 90) or Color3.fromRGB(210, 210, 224)
		TT.Pivot.BackgroundColor3 = level >= 10 and Color3.fromRGB(255, 200, 70) or Color3.fromRGB(180, 180, 196)
		-- Disque qui était en train de "sauter" : remis à sa place
		local previous = RACK.Discs[S.popDisc]
		if previous then
			previous.Disc.Size = UDim2.fromOffset(15, 15)
			previous.Disc.Position = UDim2.fromOffset(previous.X, RACK_Y)
		end
		S.popT = -1
		if grew then
			-- Nouveau disque : il "saute" sur l'étagère + petite pluie de notes
			S.popDisc = level
			S.popT = 0
			S.discSpin = 12
			if effectsOn() then
				local slot = RACK.Discs[level]
				if slot then
					spawnNote(slot.X, RACK_Y + 6, -1, 40)
				end
				spawnNote(TURNTABLE_X, ITEM_BASE - 26, 1, 56)
			end
		end
	end
	refreshVinyl()
	ctx.Connect(ctx.State.Changed, refreshVinyl)

	S.hour = localHour()
	applyPalette()
	layoutBar()

	-- Visibilité : la boucle se met en pause quand la carte est cachée
	local function computeShown(): boolean
		if type(ctx.IsVisible) == "function" then
			local ok, visible = pcall(ctx.IsVisible)
			if ok then
				return visible ~= false
			end
		end
		return ctx.Container.Visible
	end
	if type(ctx.OnVisibilityChanged) == "function" then
		ctx.OnVisibilityChanged(function(visibility: string)
			S.shown = visibility ~= "Hidden"
		end)
	end

	------------------------------------------------------------------
	-- Animation
	------------------------------------------------------------------
	local RAIN_DX = math.tan(math.rad(12))
	local LINE_TIME, PAUSE_TIME = 2.2, 0.9
	local CYCLE = LINE_TIME * 2 + PAUSE_TIME
	local HAPPY_TIME = 3.2

	-- Chaque seconde : spectateurs, sous-titre, heure, fenêtres de la ville, météo
	local function everySecond()
		S.tick += 1
		S.viewers = math.clamp(S.viewers + random:NextInteger(-40, 55), 3000, 99999)
		if S.tick % 6 == 0 then
			S.showAlt = not S.showAlt
			if S.showAlt and random:NextNumber() < 0.5 then
				S.trackIndex = S.trackIndex % #tracks + 1
			end
			B.Subtitle.TextTransparency = 1
			UI.Tween(B.Subtitle, 0.4, { TextTransparency = 0 })
		end
		refreshSubtitle()
		if S.tick % 10 == 0 then
			S.hour = localHour()
			applyPalette()
		end
		-- Une fenêtre de la ville s'allume / s'éteint de temps en temps
		if #WIN.Lit > 0 and random:NextNumber() < 0.4 then
			local lit = WIN.Lit[random:NextInteger(1, #WIN.Lit)]
			lit.On = not lit.On
			lit.Frame.BackgroundTransparency = lit.On and (0.05 + (1 - S.night) * 0.95) or 1
		end
		-- Météo : les averses vont et viennent
		S.weatherTimer -= 1
		if S.weatherTimer <= 0 then
			if S.rainTarget > 0.5 then
				S.rainTarget = random:NextNumber() < 0.3 and 0.4 or 0
				S.weatherTimer = random:NextNumber(40, 80)
			else
				S.rainTarget = 1
				S.weatherTimer = random:NextNumber(70, 120)
			end
		end
	end

	-- Écriture, clignements, gorgée de café, sourire : la fille
	local SIP_KEYS = {
		-- { temps, main X, main Y, coude X, coude Y, tasse X, tasse Y, tasse rotation, tête }
		{ 0, L_REST_HAND.X, L_REST_HAND.Y, L_REST_ELBOW.X, L_REST_ELBOW.Y, MUG_X, MUG_Y, 0, 0 },
		{ 0.9, MUG_X - 12, MUG_Y + 1, PX - 70, 140, MUG_X, MUG_Y, 0, 0 },
		{ 1.8, PX - 22, 106, PX - 52, 140, PX - 8, 104, -8, 1 },
		{ 3.1, PX - 21, 103, PX - 51, 138, PX - 7, 101, -20, 1 },
		{ 3.9, MUG_X - 12, MUG_Y + 1, PX - 70, 140, MUG_X, MUG_Y, 0, 0 },
		{ 4.7, L_REST_HAND.X, L_REST_HAND.Y, L_REST_ELBOW.X, L_REST_ELBOW.Y, MUG_X, MUG_Y, 0, 0 },
	}
	local SIP_TIME = SIP_KEYS[#SIP_KEYS][1]
	local sipPose = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	local function sampleSip(t: number)
		for i = 1, #SIP_KEYS - 1 do
			local a, b = SIP_KEYS[i], SIP_KEYS[i + 1]
			if t <= b[1] then
				local k = smooth((t - a[1]) / (b[1] - a[1]))
				for j = 2, 9 do
					sipPose[j] = a[j] + (b[j] - a[j]) * k
				end
				return
			end
		end
		local last = SIP_KEYS[#SIP_KEYS]
		for j = 2, 9 do
			sipPose[j] = last[j]
		end
	end

	local function updateGirl(dt: number, clock: number, beatPhase: number, onBeat: boolean, beatNow: number, pulse: number, fx: boolean)
		-- Gorgée de café de temps en temps
		S.sipTimer -= dt
		if S.sipT < 0 and S.happyT < 0 and S.sipTimer <= 0 and S.pageFlip < 0 then
			S.sipT = 0
		end
		local sipping = S.sipT >= 0
		local sipHead = 0
		if sipping then
			S.sipT += dt
			if S.sipT >= SIP_TIME then
				S.sipT = -1
				S.sipTimer = random:NextNumber(22, 36)
				sipping = false
			end
		end
		if sipping then
			sampleSip(S.sipT)
			sipHead = sipPose[9]
		else
			sampleSip(0)
		end
		-- De temps en temps, elle lève les yeux vers la fenêtre et sourit
		S.happyTimer -= dt
		if S.happyT < 0 and not sipping and S.happyTimer <= 0 then
			S.happyT = 0
			if fx then
				spawnNote(PX - 30, HEAD_Y - 30, -1, 40, true)
			end
		end
		if S.happyT >= 0 then
			S.happyT += dt
			if S.happyT >= HAPPY_TIME then
				S.happyT = -1
				S.happyTimer = random:NextNumber(14, 22)
			end
		end
		local happyTarget = S.happyT >= 0 and 1 or 0
		S.happy += (happyTarget - S.happy) * math.min(1, dt * 6)
		local happy = S.happy

		local handX, handY, elbowX, elbowY = sipPose[2], sipPose[3], sipPose[4], sipPose[5]
		H.Mug.Position = UDim2.fromOffset(sipPose[6], sipPose[7])
		H.Mug.Rotation = sipPose[8]
		local lifted = math.clamp((MUG_Y - sipPose[7]) / 40, 0, 1)
		D.MugShadow.BackgroundTransparency = 0.7 + lifted * 0.3
		setLimb(H.LeftUpper, L_SHOULDER.X, L_SHOULDER.Y, elbowX, elbowY, 20)
		setLimb(H.LeftFore, elbowX, elbowY, handX - 4, handY, 17)
		H.LeftHand.Position = UDim2.fromOffset(handX, handY)

		-- Tête : hoche franchement en rythme, se balance ; penchée en arrière
		-- pendant la gorgée, relevée (vers la fenêtre) quand elle sourit
		local calm = (1 - sipHead) * (1 - happy * 0.6)
		local nod = math.sin(beatPhase * math.pi)
		local headOffset = nod * (2.5 + S.grooveLevel * 3) * calm
		local headNowY = HEAD_Y + headOffset - sipHead * 2 - happy * 4
		local lean = calm * (math.sin(clock * math.pi / BEAT) * (3 + S.grooveLevel * 3)) - happy * 7
		headHolder.Position = UDim2.fromOffset(PX + (S.writeTime < LINE_TIME * 2 and (S.writeTime % LINE_TIME) / LINE_TIME - 0.5 or 0) * 2 * calm - happy * 2, headNowY)
		headHolder.Rotation = lean - sipHead * 6
		local breathe = math.sin(clock * 1.4)
		G.Torso.Position = UDim2.fromOffset(PX, 158 + nod * 1.2 * calm + breathe * 0.6)
		G.Collar.Position = UDim2.fromOffset(PX, 123 + headOffset * 0.5)
		G.Neck.Position = UDim2.fromOffset(PX, 114 + headOffset * 0.5)
		G.Hood.Position = UDim2.fromOffset(PX, 120 + headOffset * 0.4)
		shadowHead.Position = UDim2.fromOffset(PX - 26, headNowY + 4)
		shadowHead.Rotation = lean

		-- Clignements (et yeux fermés pendant la gorgée)
		S.blinkTimer -= dt
		if S.blinkTimer <= 0 then
			S.blinkTimer = random:NextNumber(2.2, 5)
			S.blinkAge = 0
			if random:NextNumber() < 0.2 then
				S.blinkTimer = 0.32 -- double clignement
			end
		end
		local openness = 1
		if S.blinkAge >= 0 then
			S.blinkAge += dt
			local p = S.blinkAge / 0.16
			if p >= 1 then
				S.blinkAge = -1
			else
				openness = math.abs(p * 2 - 1)
			end
		end
		if sipping and S.sipT > 1.5 and S.sipT < 3.3 then
			openness = 0
		end
		-- Yeux baissés (6 px) ou grands ouverts quand elle sourit (9 px)
		local eyeH = 1.5 + openness * (4.5 + happy * 4)
		for _, e in ipairs(G.Eyes) do
			e.Eye.Size = UDim2.fromOffset(10 - happy, eyeH)
			e.Shine.Visible = openness > 0.6
			e.Lash.Position = UDim2.new(0.5, e.Side * 12, 0.5, 13 - eyeH - 1)
		end
		local mouthW = 8 + happy * 5
		G.Mouth.Size = UDim2.fromOffset(mouthW, mouthW)
		G.Mouth.Position = UDim2.new(0.5, 0, 0.5, 19 - happy * 1.5)
		G.MouthStroke.Thickness = 1.8 + happy * 0.6

		-- Casque lumineux : halo + écouteurs qui pulsent sur la musique
		for _, cup in ipairs(G.Cups) do
			cup.Size = UDim2.fromOffset(20 + pulse * 2, 32 + pulse * 2)
		end
		for _, led in ipairs(G.Leds) do
			led.Transparency = 0.6 - pulse * 0.55
		end

		-- Écriture : le crayon avance sur la ligne, 2 lignes, pause, et
		-- toutes les 3 pages la feuille se tourne (en pause pendant la gorgée
		-- et quand elle lève les yeux)
		local paused = sipping or S.happyT >= 0
		if not paused then
			local previous = S.writeTime
			S.writeTime = (S.writeTime + dt) % CYCLE
			if S.writeTime < previous then
				S.linesWritten += 1
				if S.linesWritten % 3 == 0 then
					S.pageFlip = 0
				end
			end
		end
		local lineIndex, progressLine, pencilUp
		if S.writeTime < LINE_TIME then
			lineIndex, progressLine, pencilUp = 1, S.writeTime / LINE_TIME, false
		elseif S.writeTime < LINE_TIME * 2 then
			lineIndex, progressLine, pencilUp = 2, (S.writeTime - LINE_TIME) / LINE_TIME, false
		else
			lineIndex, progressLine, pencilUp = 1, 0, true
		end
		if paused then
			pencilUp = true
		end
		local flipping = false
		if S.pageFlip >= 0 then
			-- La feuille passe de la page de droite à la page de gauche
			S.pageFlip += dt / 0.6
			local p = S.pageFlip
			if p >= 1 then
				S.pageFlip = -1
				H.Page.Visible = false
			else
				flipping = true
				H.Page.Visible = true
				local width = math.abs(math.cos(p * math.pi)) * (NOTE_W / 2)
				H.Page.AnchorPoint = Vector2.new(p < 0.5 and 0 or 1, 0.5)
				H.Page.Size = UDim2.fromOffset(width, NOTE_H + 2 - math.sin(p * math.pi) * 3)
				H.Page.Position = UDim2.fromOffset(NOTE_W / 2, NOTE_H / 2 - math.sin(p * math.pi) * 3)
			end
			pencilUp = true
		end
		if flipping then
			-- Page pleine qui part, puis page blanche une fois tournée
			local full = S.pageFlip < 0.5
			H.Lines[1].Size = UDim2.fromOffset(full and WRITE_W or 0, 3)
			H.Lines[2].Size = UDim2.fromOffset(full and WRITE_W or 0, 3)
		elseif paused then
			-- (lignes figées pendant la gorgée / le sourire)
		elseif pencilUp and S.writeTime >= LINE_TIME * 2 then
			-- Pause en fin de cycle : les deux lignes sont écrites
			H.Lines[1].Size = UDim2.fromOffset(WRITE_W, 3)
			H.Lines[2].Size = UDim2.fromOffset(WRITE_W, 3)
		else
			H.Lines[1].Size = UDim2.fromOffset(lineIndex == 1 and WRITE_W * progressLine or WRITE_W, 3)
			H.Lines[2].Size = UDim2.fromOffset(lineIndex == 2 and WRITE_W * progressLine or 0, 3)
		end
		local scribble = pencilUp and 0 or 1
		local tipX = noteLeft + WRITE_X + (pencilUp and WRITE_W * 0.5 or WRITE_W * progressLine) + math.sin(clock * 14) * 1.2 * scribble
		local tipY = noteTop + 5 + (lineIndex - 1) * 6 + math.sin(clock * 26) * 1.2 * scribble - (pencilUp and 5 or 0)
		setLimb(H.Pencil, tipX, tipY, tipX + 10, tipY - 18, 4)
		local rhX, rhY = tipX + 5, tipY - 7
		H.RightHand.Position = UDim2.fromOffset(rhX, rhY)
		setLimb(H.RightFore, R_ELBOW.X, R_ELBOW.Y, rhX + 3, rhY, 17)

		-- Notes de musique : du casque sur certains temps, de la platine
		-- (plus souvent avec une grande collection de vinyles)
		if onBeat and fx then
			if S.musicSound or beatNow % 2 == 0 then
				spawnNote(PX + S.nextNoteSide * 46, headNowY + 2, S.nextNoteSide, 62)
				S.nextNoteSide = -S.nextNoteSide
			end
			local every = S.vinylLevel >= 6 and 2 or 4
			if beatNow % every == 1 then
				spawnNote(TURNTABLE_X + 8, ITEM_BASE - 30, 1, 48)
			end
		end

		-- Vapeur du café (suit la tasse)
		local mugTopX, mugTopY = sipPose[6] + 1, sipPose[7] - 14
		for i, puff in ipairs(H.Steam) do
			if fx then
				local p = ((clock / 2.2) + (i - 1) / 3) % 1
				puff.Position = UDim2.fromOffset(mugTopX + math.sin(p * 7 + i) * 5, mugTopY - p * 28)
				puff.Size = UDim2.fromOffset(6 + p * 11, 6 + p * 11)
				puff.BackgroundTransparency = 0.5 + p * 0.5
			elseif puff.BackgroundTransparency < 1 then
				puff.BackgroundTransparency = 1
			end
		end
	end

	-- Le chat : dort, se réveille, regarde la pluie puis la chambre, bâille
	local function updateCat(dt: number, clock: number)
		S.catTimer -= dt
		local awake = S.catMode == "awake"
		if not awake and S.catTimer <= 0 then
			S.catMode = "awake"
			S.catT = 0
			S.catAwake = random:NextNumber(8, 11)
			awake = true
		elseif awake then
			S.catT += dt
			if S.catT >= S.catAwake then
				S.catMode = "sleep"
				S.catTimer = random:NextNumber(16, 26)
				awake = false
			end
		end
		local t = S.catT
		local lift, look, yawn, eyesOpen = 0, 0, false, false
		if awake then
			lift = math.min(smooth(t / 0.7), smooth((S.catAwake - t) / 0.9))
			if t > 0.9 and t < 3.8 then
				look = -1 -- regarde la pluie
			elseif t > 4.1 and t < 6.4 then
				look = 1 -- regarde la chambre
			end
			yawn = t > S.catAwake - 2.3 and t < S.catAwake - 1.3
			eyesOpen = t > 0.35 and t < S.catAwake - 0.6 and not yawn
			-- Clignement
			if S.catBlink < 0 and random:NextNumber() < dt * 0.5 then
				S.catBlink = 0
			end
			if S.catBlink >= 0 then
				S.catBlink += dt
				if S.catBlink > 0.15 then
					S.catBlink = -1
				else
					eyesOpen = false
				end
			end
		end
		S.catLook += (look - S.catLook) * math.min(1, dt * 4)
		CAT.Head.Position = UDim2.fromOffset(CAT_HEAD_X + S.catLook * 2, CAT_HEAD_Y - lift * 7)
		CAT.Head.Rotation = S.catLook * 10 + (yawn and -8 or 0)
		for i, eye in ipairs(CAT.Open) do
			eye.Visible = eyesOpen
			eye.Position = UDim2.fromOffset(22 + (i == 1 and -8 or 8) + S.catLook * 1.8, 19)
		end
		for _, eye in ipairs(CAT.Closed) do
			eye.Visible = not eyesOpen
		end
		CAT.Mouth.Visible = yawn
		if yawn then
			local p = (t - (S.catAwake - 2.3)) / 1
			CAT.Mouth.Size = UDim2.fromOffset(6, 1 + math.sin(p * math.pi) * 7)
		end
		-- Oreilles : petit frémissement quand il est réveillé
		local twitch = (awake and math.sin(clock * 9) > 0.97) and 14 or 0
		CAT.Ears[1].Rotation = 45 - twitch
		CAT.Ears[2].Rotation = 45 + (awake and (math.sin(clock * 7 + 2) > 0.985 and 14 or 0) or 0)
		-- Respiration + queue (lente quand il dort, qui fouette réveillé)
		CAT.BodyScale.Scale = 1 + (awake and 0.02 or 0.05) * (0.5 + 0.5 * math.sin(clock * (awake and 2.4 or 1.6)))
		local baseX, baseY, a1, a2
		local tailZ = awake and 1 or 5
		if CAT.Tail1.ZIndex ~= tailZ then
			CAT.Tail1.ZIndex = tailZ
			CAT.Tail2.ZIndex = tailZ
		end
		if awake then
			-- dressée derrière le corps, le bout fouette
			baseX, baseY = catX + 6, catBottom - 14
			a1 = math.rad(252 + math.sin(clock * 3) * 10)
			a2 = a1 + math.rad(38 + math.sin(clock * 4.2) * 34)
		else
			-- enroulée devant le corps, le bout remue doucement
			baseX, baseY = catX + 5, catBottom - 5
			a1 = math.rad(-6)
			a2 = a1 - math.rad(28 + math.sin(clock * 0.9) * 18)
		end
		local midX, midY = baseX + math.cos(a1) * 15, baseY + math.sin(a1) * 15
		setLimb(CAT.Tail1, baseX, baseY, midX, midY, 9)
		setLimb(CAT.Tail2, midX, midY, midX + math.cos(a2) * 13, midY + math.sin(a2) * 13, 8)
		-- "Z z z" seulement quand il dort (gros, lisibles)
		for i, z in ipairs(CAT.Z) do
			if awake then
				if z.TextTransparency < 1 then
					z.TextTransparency = 1
					z.TextStrokeTransparency = 1
				end
			else
				local p = ((clock / 3.3) + (i - 1) / 3) % 1
				z.Position = UDim2.fromOffset(CAT_HEAD_X + 12 + p * 26 + math.sin(p * 6) * 4, CAT_HEAD_Y - 16 - p * 46)
				z.TextSize = math.floor(11 + p * 12)
				local alpha = p < 0.12 and (1 - p / 0.12) or (p * p)
				z.TextTransparency = alpha
				z.TextStrokeTransparency = 0.3 + alpha * 0.7
			end
		end
	end

	-- Ciel : pluie, nuages, étoiles, soleil / lune, oiseau / avion
	local function updateWindow(dt: number, clock: number, fx: boolean, slow: boolean)
		-- Intensité de la pluie (lissée) ; le ciel est recalculé si elle a changé
		if S.rain ~= S.rainTarget then
			local step = dt * 0.12
			S.rain = S.rain < S.rainTarget and math.min(S.rainTarget, S.rain + step) or math.max(S.rainTarget, S.rain - step)
			if math.abs(S.rain - S.skyRain) > 0.05 then
				applyPalette()
			end
		end
		local rain = S.rain
		local visibleDrops = math.floor(rain * #WIN.Drops + 0.5)
		for i, drop in ipairs(WIN.Drops) do
			local show = i <= visibleDrops
			if drop.Frame.Visible ~= show then
				drop.Frame.Visible = show
			end
			if show then
				drop.Y += drop.Speed * dt
				drop.X -= drop.Speed * RAIN_DX * dt
				if drop.Y > GLASS_H + 10 or drop.X < -10 then
					drop.Y = random:NextNumber(-24, -6)
					drop.X = random:NextNumber(0, GLASS_W + 30)
				end
				drop.Frame.Position = UDim2.fromOffset(drop.X, drop.Y)
			end
		end

		-- Nuages qui dérivent
		for _, cloud in ipairs(WIN.Clouds) do
			cloud.X += cloud.Speed * dt * (1 + rain)
			if cloud.X > GLASS_W + 4 then
				cloud.X = -50
			end
			cloud.Frame.Position = UDim2.fromOffset(cloud.X, cloud.Y)
		end

		-- Étoiles (la nuit), lune, voyant de la tour, néon, guirlande
		-- (décor lent : une image sur deux)
		local night = S.night
		if slow then
			for _, star in ipairs(WIN.Stars) do
				local twinkle = 0.5 + 0.5 * math.sin(clock * star.Speed + star.Phase)
				local alpha = 1 - night * (1 - rain * 0.5) * (0.2 + 0.8 * twinkle)
				for _, part in ipairs(star.Parts) do
					part.BackgroundTransparency = alpha
				end
			end
			for i, glow in ipairs(WIN.MoonGlow) do
				glow.BackgroundTransparency = 0.82 + 0.06 * math.sin(clock * 0.8 + i)
			end
			for _, light in ipairs(WIN.Fairy) do
				local twinkle = 0.5 + 0.5 * math.sin(clock * 2.2 + light.Phase)
				light.Frame.BackgroundTransparency = (1 - twinkle) * 0.35
				light.Glow.Transparency = 0.35 + (1 - twinkle) * 0.55
			end
		end
		if WIN.TowerLight then
			WIN.TowerLight.BackgroundTransparency = (clock % 1.6) < 0.5 and (1 - night) * 0.8 or 0.85
		end
		if WIN.Neon and slow then
			WIN.Neon.Transparency = math.min(1, 0.3 + (1 - night) * 0.6 + ((math.sin(clock * 23) > 0.93) and 0.3 or 0))
			WIN.NeonSign.BackgroundTransparency = (1 - night) * 0.5
		end

		-- Étoile filante (nuit claire) et éclair lointain (nuit d'orage)
		S.nextStar -= dt
		if S.nextStar <= 0 then
			S.nextStar = random:NextNumber(9, 18)
			if fx and night > 0.6 and rain < 0.5 then
				S.starAge = 0
				WIN.Shooting.Visible = true
				WIN.Shooting.Position = UDim2.fromOffset(random:NextNumber(30, GLASS_W * 0.6), random:NextNumber(4, 18))
			end
		end
		if S.starAge >= 0 then
			S.starAge += dt
			local p = S.starAge / 0.8
			if p >= 1 then
				S.starAge = -1
				WIN.Shooting.Visible = false
			else
				local position = WIN.Shooting.Position
				WIN.Shooting.Position = UDim2.fromOffset(position.X.Offset + 110 * dt, position.Y.Offset + 110 * dt * math.tan(math.rad(18)))
				WIN.Shooting.BackgroundTransparency = p * p
			end
		end
		S.nextFlash -= dt
		if S.nextFlash <= 0 then
			S.nextFlash = random:NextNumber(18, 40)
			if fx and rain > 0.6 and night > 0.5 then
				S.flash = 1
			end
		end
		if S.flash > 0 then
			S.flash = math.max(0, S.flash - dt * 3)
			local flicker = (S.flash > 0.6 and S.flash < 0.8) and 0.2 or S.flash
			WIN.Flash.BackgroundTransparency = 1 - flicker * 0.6
		end

		-- Oiseau (le jour) ou avion (la nuit) qui traverse de temps en temps
		S.nextFlyer -= dt
		if S.nextFlyer <= 0 and S.flyerAge < 0 then
			S.nextFlyer = random:NextNumber(14, 28)
			if fx then
				S.flyerAge = 0
				local bird = night < 0.5
				WIN.WingL.Visible = bird
				WIN.WingR.Visible = bird
				WIN.PlaneLight.Visible = not bird
				WIN.Flyer.Visible = true
				S.flyerY = random:NextNumber(8, 28)
				S.flyerSpeed = bird and random:NextNumber(24, 34) or random:NextNumber(9, 13)
			end
		end
		if S.flyerAge >= 0 then
			S.flyerAge += dt
			local x = -10 + S.flyerAge * S.flyerSpeed
			if x > GLASS_W + 12 then
				S.flyerAge = -1
				WIN.Flyer.Visible = false
			else
				local bird = WIN.WingL.Visible
				local flap = bird and math.sin(S.flyerAge * 14) * 22 or 0
				WIN.WingL.Rotation = 18 + flap
				WIN.WingR.Rotation = -18 - flap
				WIN.Flyer.Position = UDim2.fromOffset(x, S.flyerY + (bird and math.sin(S.flyerAge * 3) * 2 or -S.flyerAge * 0.4))
				if not bird then
					WIN.PlaneLight.BackgroundColor3 = (S.flyerAge % 1) < 0.5 and Color3.fromRGB(255, 80, 90) or WHITE
					WIN.PlaneLight.BackgroundTransparency = (S.flyerAge % 0.5) < 0.15 and 0 or 0.6
				end
			end
		end
	end

	-- Lumières (lampe qui respire, halo, flaque), étagère, platine
	local function updateRoom(dt: number, clock: number, pulse: number, slow: boolean)
		-- Collection de vinyles : enceinte qui pulse, néon qui change de couleur
		if S.vinylLevel >= 5 then
			local size = 14 + pulse * 3
			TT.Woofer.Size = UDim2.fromOffset(size, size)
		end
		if S.vinylLevel >= 7 then
			local color = Color3.fromHSV((clock * 0.06) % 1, 0.6, 1)
			D.Neon.BackgroundColor3 = color
			D.NeonGlow.Color = color
			D.NeonGlow.Transparency = 0.55 - pulse * 0.3
			D.NeonWash.BackgroundColor3 = color
			D.NeonWash.BackgroundTransparency = 0.72 - pulse * 0.12
		end
		-- Nouveau disque sur l'étagère : il saute et grossit un instant
		if S.popT >= 0 then
			S.popT += dt
			local slot = RACK.Discs[S.popDisc]
			if S.popT >= 0.8 or not slot then
				S.popT = -1
				if slot then
					slot.Disc.Size = UDim2.fromOffset(15, 15)
					slot.Disc.Position = UDim2.fromOffset(slot.X, RACK_Y)
				end
			else
				local p = S.popT / 0.8
				local bump = math.sin(p * math.pi)
				local size = 15 + bump * 6
				slot.Disc.Size = UDim2.fromOffset(size, size)
				slot.Disc.Position = UDim2.fromOffset(slot.X, RACK_Y - bump * 2)
			end
		end
		if not slow then
			return -- (lumières : une image sur deux)
		end
		local power = S.lampPower
		local breath = 0.5 + 0.5 * math.sin(clock * 1.2)
		local flicker = (math.sin(clock * 37) > 0.985) and 0.05 or 0
		for _, glow in ipairs(lampHalo) do
			glow.BackgroundTransparency = math.min(1, 1 - (1 - LAMP_HALO_ALPHA) * power * (0.85 + 0.15 * breath) + flicker)
		end
		for _, glow in ipairs(D.Pool) do
			glow.BackgroundTransparency = math.min(1, 1 - 0.36 * power * (0.9 + 0.1 * breath) + flicker)
		end
		D.Spill.BackgroundTransparency = math.min(1, 1 - 0.24 * power * (0.9 + 0.1 * breath) + flicker)
		for _, ray in ipairs(LAMP.Rays) do
			ray.Frame.BackgroundTransparency = math.min(1, 1 - (1 - ray.Alpha) * power + flicker)
		end
		LAMP.Bulb.BackgroundTransparency = flicker * 4
		LAMP.BulbGlow.BackgroundTransparency = 0.5 + (1 - power) * 0.3 + flicker * 3
		shadowHead.BackgroundTransparency = 1 - 0.22 * power
	end

	-- Visualiseur, vinyles, progression et temps
	local function updatePlayer(dt: number, clock: number, playing: boolean, level: number, reactive: boolean)
		local music = S.musicSound
		if reactive then
			local rising = level > S.lastLevel + 0.12
			S.lastLevel = level
			S.eqTimer -= dt
			if S.eqTimer <= 0 or rising then
				S.eqTimer = 0.07
				for i = 1, EQ_BARS do
					local low = 1 - (i - 1) / (EQ_BARS - 1)
					local base = level * (0.35 + random:NextNumber() * 0.5) + level * low * 0.3
					if rising then
						base += low * 0.25
					end
					eqTargets[i] = math.clamp(base, 0.06, 1)
				end
			end
			S.discSpin += (4 - S.discSpin) * math.min(1, dt * 3)
		else
			S.lastLevel = 0
			S.eqTimer -= dt
			if S.eqTimer <= 0 then
				S.eqTimer = 0.11
				local newBeat = math.floor(clock / BEAT)
				local eqBeat = newBeat ~= S.beatCount
				S.beatCount = newBeat
				for i = 1, EQ_BARS do
					local low = 1 - (i - 1) / (EQ_BARS - 1)
					local base = 0.15 + random:NextNumber() * 0.5
					if eqBeat then
						base += low * 0.45
					end
					eqTargets[i] = math.clamp(base, 0.1, 1)
				end
			end
			S.discSpin += (1.2 - S.discSpin) * math.min(1, dt * 2)
		end
		local k = math.min(1, dt * 16)
		for i, eqBar in ipairs(eqBars) do
			eqHeights[i] += (eqTargets[i] - eqHeights[i]) * k
			local h = 3 + eqHeights[i] * (EQ_H - 5)
			eqBar.Size = UDim2.fromOffset(eqBar.Size.X.Offset, math.floor(h))
		end

		-- Vinyles (barre + platine) et progression du morceau
		S.discAngle = (S.discAngle + S.discSpin * 60 * dt) % 360
		B.Disc.Rotation = S.discAngle
		local angle = math.rad(S.discAngle)
		TT.Spin.Offset = Vector2.new(math.sin(angle) * 0.35, 0)
		-- Reflet qui fait le tour du disque (ellipse vue de 3/4)
		TT.Glint.Position = UDim2.fromOffset(32 + math.cos(angle) * 22, 9 + math.sin(angle) * 5.5)
		TT.Glint.Rotation = math.deg(math.atan2(math.sin(angle) * 5.5, math.cos(angle) * 22)) + 90
		TT.LedLight.BackgroundTransparency = playing and 0 or (0.3 + 0.3 * math.sin(clock * 2))
		-- Bras de lecture : posé sur le disque quand la musique joue, sinon relevé
		S.armLift += ((playing and 1 or 0) - S.armLift) * math.min(1, dt * 3)
		TT.Arm.Rotation = TT.ArmRest - (1 - S.armLift) * 16
		local position, length = 0, 0
		if playing and music then
			length = tonumber(music.TimeLength) or 0
			position = tonumber(music.TimePosition) or 0
		end
		if length <= 0 then
			S.fakeProgress = (S.fakeProgress + dt / S.fakeLength) % 1
			length = S.fakeLength
			position = S.fakeProgress * length
		end
		local ratio = math.clamp(position / length, 0, 1)
		B.Fill.Size = UDim2.fromScale(ratio, 1)
		B.Knob.Position = UDim2.fromScale(ratio, 0.5)
		-- Temps : le texte n'est refait que quand la seconde change
		local stamp = math.floor(position) * 10000 + math.floor(length)
		if B.Time.Visible and stamp ~= S.timeStamp then
			S.timeStamp = stamp
			B.Time.Text = clockText(position) .. " / " .. clockText(length)
		end
	end

	ctx.OnRender(function(rawDt: number)
		S.visibilityTimer -= rawDt
		if S.visibilityTimer <= 0 then
			S.visibilityTimer = 0.5
			S.shown = computeShown()
		end
		if not S.shown then
			S.acc = 0
			return
		end
		-- 30 images/s maximum : la scène est calme, inutile d'en faire plus
		S.acc += rawDt
		if S.acc < STEP then
			return
		end
		local dt = math.min(S.acc, 0.1)
		S.acc = 0
		S.frame += 1
		local slow = S.frame % 2 == 0
		S.clock += dt
		local clock = S.clock
		local fx = effectsOn()

		S.secondTimer -= dt
		if S.secondTimer <= 0 then
			S.secondTimer = 1
			everySecond()
		end

		-- Musique : volume réel (si elle joue) → visualiseur + intensité du hochement
		local music = S.musicSound
		local playing = music ~= nil and music.Parent ~= nil and music.IsPlaying == true
		local level = 0
		if playing and music then
			-- Pic adaptatif : le visualiseur reste expressif quel que soit le volume
			local loudness = tonumber(music.PlaybackLoudness) or 0
			S.loudPeak = math.max(loudness, S.loudPeak * (1 - math.min(1, dt * 0.35)), 40)
			level = math.clamp(loudness / S.loudPeak, 0, 1)
			-- Volume nul (musique à 0, chargement) : le visualiseur s'anime seul
			if loudness < 0.5 then
				S.silentTime += dt
			else
				S.silentTime = 0
			end
		end
		local reactive = playing and S.silentTime < 1.5
		S.grooveLevel += ((playing and (0.55 + level * 0.45) or 0.45) - S.grooveLevel) * math.min(1, dt * 4)

		-- Temps (78 BPM) : pulsation qui retombe après chaque temps
		local beatPhase = (clock % BEAT) / BEAT
		local pulse = math.exp(-beatPhase * 5)
		if playing then
			pulse = math.max(pulse * 0.6, level)
		end
		local beatNow = math.floor(clock / BEAT)
		local onBeat = beatNow ~= S.lastBeat
		S.lastBeat = beatNow

		updateWindow(dt, clock, fx, slow)
		updateCat(dt, clock)
		updateGirl(dt, clock, beatPhase, onBeat, beatNow, pulse, fx)
		updateRoom(dt, clock, pulse, slow)

		-- Notes de musique (et cœurs) qui s'envolent
		for _, n in ipairs(notes) do
			if n.Active then
				n.Age += dt
				local p = n.Age / NOTE_LIFE
				if p >= 1 or not fx then
					n.Active = false
					n.Label.Visible = false
				else
					local noteLabel = n.Label
					noteLabel.Position = UDim2.fromOffset(n.X + n.Dir * p * 32 + math.sin(p * 9) * 5, n.Y - p * n.Rise)
					noteLabel.Rotation = math.sin(p * 8) * 18
					noteLabel.TextSize = math.floor(14 + math.min(1, p * 5) * 8)
					local alpha = p < 0.12 and (1 - p / 0.12) or math.max(0, (p - 0.55) / 0.45)
					noteLabel.TextTransparency = alpha
					noteLabel.TextStrokeTransparency = 0.35 + alpha * 0.65
				end
			end
		end

		updatePlayer(dt, clock, playing, level, reactive)
	end)
end

return Lofi
