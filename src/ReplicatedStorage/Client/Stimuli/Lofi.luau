--[[
	Lofi (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Lofi

	Petite chambre "lofi" la nuit (slot R3, 384x268), entièrement illustrée
	en code (Frames, UICorner, UIGradient, UIStroke — aucun emoji pour le
	décor ni le personnage). v8 :
	  - la fenêtre : ciel de nuit dégradé, lune et son halo, étoiles qui
	    scintillent, nuages qui passent, ville en deux plans (immeubles au
	    loin, immeubles proches aux fenêtres qui s'allument, antenne au
	    voyant rouge, enseigne néon), pluie, gouttes qui glissent sur la
	    vitre, reflet sur le verre, éclair lointain de temps en temps ;
	    rideaux, tringle et guirlande lumineuse, rebord avec le chat qui
	    dort (respire, remue la queue, "z z z") et deux plantes ;
	  - le mur : horloge à aiguilles (heure réelle), étagère de vinyles
	    (plus de disques avec l'amélioration "Vinyl", disque d'or au
	    niveau 10), guirlande de photos, post-it ;
	  - la fille au casque : cheveux, visage aux yeux baissés, casque rose
	    lumineux qui pulse sur le rythme, la tête hoche, elle écrit dans son
	    cahier (le crayon avance, les lignes se remplissent, la page se
	    tourne) ; des notes ♪ ♫ s'envolent du casque et de la platine ;
	  - le bureau : platine vinyle (disque qui tourne, bras de lecture,
	    voyant), livres, tasse fumante, lampe articulée dont la lumière
	    respire ;
	  - en bas, le lecteur : pochette + vinyle, titre du morceau ("♫ Nom"
	    via SoundManager.GetMusicInfo si disponible, mis à jour sur
	    SoundManager.MusicChanged), barre de progression, visualiseur
	    audio piloté par le volume réel du morceau (PlaybackLoudness), ou
	    animé tout seul sans musique, bouton ⏭ (SoundManager.NextTrack).
	Si la playlist est vide : dans Studio, un rappel "Ajoute une musique
	dans Config.Music" ; en jeu, simplement la petite chambre.
	Performance : une seule boucle de rendu, objets recyclés (pluie, notes,
	fenêtres), pause complète quand la carte n'est pas visible.
]]

local RunService = game:GetService("RunService")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Lofi = {}
Lofi.Slot = "R3"

-- Dimensions (pixels "design")
local SCENE_X, SCENE_Y = 6, 6
local SCENE_W, SCENE_H = 368, 204
local BAR_Y, BAR_H = 214, 42
local DESK_Y = 148 -- dessus du bureau (plateau vu en perspective)
local DESK_FRONT = 164 -- face avant du bureau
local SCENE_RADIUS = 10 -- coins arrondis de la scène (repris par la face avant du bureau)
local ITEM_BASE = 158 -- les objets "posés" sur le plateau
local WINDOW_X, WINDOW_Y, WINDOW_W, WINDOW_H = 20, 16, 146, 96
local GLASS_W, GLASS_H = WINDOW_W - 10, WINDOW_H - 10
local SILL_Y = WINDOW_Y + WINDOW_H - 2
local LAMP_X = 338
local PX = 258 -- centre du personnage
local HEAD_Y = 84 -- centre de la tête
local TURNTABLE_X = 58 -- centre de la platine
local EQ_BARS = 12
local BEAT = 60 / 78 -- une pulsation (78 BPM, tranquille)
local NOTE_POOL = 6
local NOTE_LIFE = 2.4
local RAIN_DROPS = 14
local MAX_RECORDS = 12

local WHITE = Color3.new(1, 1, 1)
local RAIN_COLOR = Color3.fromRGB(190, 210, 255)
local EQ_LOW = Color3.fromRGB(255, 120, 190)
local EQ_HIGH = Color3.fromRGB(100, 220, 255)

-- Palette du personnage (original : cheveux indigo, sweat menthe, casque rose)
local SKIN = Color3.fromRGB(255, 222, 200)
local SKIN_SHADE = Color3.fromRGB(242, 186, 166)
local HAIR = Color3.fromRGB(58, 44, 96)
local HAIR_LIGHT = Color3.fromRGB(112, 92, 164)
local HOODIE = Color3.fromRGB(112, 212, 196)
local HOODIE_DARK = Color3.fromRGB(62, 150, 150)
local PHONES = Color3.fromRGB(255, 118, 176)
local PHONES_DARK = Color3.fromRGB(196, 58, 124)
local PHONES_GLOW = Color3.fromRGB(255, 150, 210)
local LINE_INK = Color3.fromRGB(72, 44, 78)
local NOTE_COLORS = { PHONES_GLOW, EQ_HIGH, Color3.fromRGB(255, 226, 120), Color3.fromRGB(196, 170, 255) }
local RECORD_COLORS = {
	Color3.fromRGB(255, 120, 150),
	Color3.fromRGB(110, 190, 255),
	Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(160, 120, 240),
	Color3.fromRGB(110, 220, 170),
	Color3.fromRGB(255, 160, 90),
	Color3.fromRGB(240, 240, 250),
	Color3.fromRGB(60, 56, 80),
}

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

-- Séquence de couleurs "à bords nets" : { {position, couleur}, ... }
local function bands(list: { { any } }): ColorSequence
	local keypoints = {}
	for _, entry in ipairs(list) do
		table.insert(keypoints, ColorSequenceKeypoint.new(entry[1], entry[2]))
	end
	return ColorSequence.new(keypoints)
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

	-- Contour circulaire dont on ne garde que le haut ou le bas
	local function arc(props: { [string]: any }, color: Color3, thickness: number, sequence: NumberSequence): (Frame, UIStroke)
		props.BackgroundTransparency = 1
		local f = circle(props)
		local stroke = UI.Stroke(f, color, thickness, 0)
		UI.Create("UIGradient", { Rotation = 90, Transparency = sequence, Parent = stroke })
		return f, stroke
	end

	-- Membre (bras, crayon...) : capsule tournée qui va de (x1, y1) à (x2, y2).
	-- Le haut du cadre est du côté (x1, y1) : un dégradé Rotation 90 va du
	-- début vers la fin du membre.
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

	-- État animé (une seule table : peu de variables locales dans Start)
	local S = {
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
		writeTime = 0,
		pageFlip = -1, -- progression du tournage de page (-1 : aucun)
		linesWritten = 0,
		discSpin = 0, -- vitesse de rotation des vinyles (lissée)
		discAngle = 0,
		fakeProgress = 0,
		nextStar = 14, -- étoile filante
		starAge = -1,
		nextFlash = 25, -- éclair lointain
		flash = 0,
		viewers = 0,
		showAlt = false, -- alterne les deux textes du sous-titre
		trackIndex = 1,
		nextNoteSide = 1,
		noteColorIndex = 0,
		shownRecords = -1,
		silentTime = 0, -- depuis quand la musique "joue" sans aucun volume
		armLift = 0, -- bras de la platine levé (0) ou posé sur le disque (1)
	}

	------------------------------------------------------------------
	-- Carte + scène (mur violet du soir)
	------------------------------------------------------------------
	local card = frame({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = Color3.fromRGB(28, 22, 44),
		Parent = ctx.Container,
	})
	UI.Corner(card, 16)
	gradient(card, Color3.fromRGB(40, 30, 64), Color3.fromRGB(20, 16, 32))
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
	UI.Gradient(scene, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 52, 116)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(88, 64, 132)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 44, 96)),
	}), 90)

	------------------------------------------------------------------
	-- Lueur de la lampe (derrière tout le reste du mur)
	------------------------------------------------------------------
	local glows: { Frame } = {}
	local GLOW_SIZES = { 220, 130 }
	local GLOW_ALPHA = { 0.88, 0.8 }
	for i, size in ipairs(GLOW_SIZES) do
		glows[i] = circle(at({
			Name = "LampGlow",
			BackgroundColor3 = Color3.fromRGB(255, 196, 120),
			BackgroundTransparency = GLOW_ALPHA[i],
			ZIndex = 1,
			Parent = scene,
		}, LAMP_X - 10, 116, size, size))
	end

	------------------------------------------------------------------
	-- Fenêtre : ciel, lune, étoiles, nuages, ville en deux plans, pluie
	------------------------------------------------------------------
	local WOOD_LIGHT = Color3.fromRGB(236, 214, 182)
	local windowFrame = frame({
		Name = "Window",
		Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = scene,
	})
	UI.Corner(windowFrame, 5)
	gradient(windowFrame, WOOD_LIGHT, Color3.fromRGB(206, 176, 140))
	UI.Stroke(windowFrame, Color3.fromRGB(120, 92, 76), 1.5, 0.3)

	local glass = frame({
		Name = "Glass",
		Position = UDim2.fromOffset(5, 5),
		Size = UDim2.fromOffset(GLASS_W, GLASS_H),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = windowFrame,
	})
	UI.Gradient(glass, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 18, 58)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(60, 42, 116)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 86, 140)),
	}), 90)

	-- Lune + halo
	local moonGlow = circle(at({ Name = "MoonGlow", BackgroundColor3 = Color3.fromRGB(255, 244, 200), BackgroundTransparency = 0.84, ZIndex = 2, Parent = glass }, GLASS_W - 28, 22, 46, 46))
	do
		local moon = circle(at({ Name = "Moon", BackgroundColor3 = WHITE, ZIndex = 3, Parent = glass }, GLASS_W - 28, 22, 22, 22))
		gradient(moon, Color3.fromRGB(255, 250, 222), Color3.fromRGB(236, 224, 180), 45)
		for i, spec in ipairs({ { 7, 8, 6 }, { 14, 14, 4 }, { 15, 6, 3 } }) do
			circle(at({ Name = "Crater" .. i, BackgroundColor3 = Color3.fromRGB(226, 212, 170), ZIndex = 3, Parent = moon }, spec[1], spec[2], spec[3], spec[3]))
		end
	end

	-- Étoiles qui scintillent
	local stars: { { Frame: Frame, Phase: number, Speed: number } } = {}
	for _ = 1, 7 do
		local size = random:NextInteger(2, 3)
		local star = frame({
			Name = "Star",
			Position = UDim2.fromOffset(random:NextInteger(4, GLASS_W - 56), random:NextInteger(3, 36)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(255, 255, 230),
			ZIndex = 2,
			Parent = glass,
		})
		table.insert(stars, { Frame = star, Phase = random:NextNumber(0, math.pi * 2), Speed = random:NextNumber(1.5, 3.5) })
	end

	-- Étoile filante (une seule, réutilisée)
	local shootingStar = frame({
		Name = "ShootingStar",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(26, 2),
		BackgroundColor3 = WHITE,
		Rotation = 18,
		Visible = false,
		ZIndex = 2,
		Parent = glass,
	})
	UI.Create("UIGradient", { Transparency = NumberSequence.new(1, 0), Parent = shootingStar })

	-- Nuages qui passent lentement (2 nuages de 3 bosses)
	local clouds: { { Frame: Frame, X: number, Speed: number } } = {}
	for i = 1, 2 do
		local cloud = frame({ Name = "Cloud", Size = UDim2.fromOffset(44, 16), BackgroundTransparency = 1, ZIndex = 3, Parent = glass })
		for _, spec in ipairs({ { 12, 10, 18 }, { 24, 7, 22 }, { 34, 11, 16 } }) do
			circle(at({ BackgroundColor3 = Color3.fromRGB(128, 104, 176), BackgroundTransparency = 0.45, ZIndex = 3, Parent = cloud }, spec[1], spec[2], spec[3], spec[3] * 0.8))
		end
		local x = i == 1 and 10 or 80
		cloud.Position = UDim2.fromOffset(x, i == 1 and 30 or 12)
		table.insert(clouds, { Frame = cloud, X = x, Speed = i == 1 and 3 or 2 })
	end

	-- Ville au loin (silhouettes claires) puis ville proche (fenêtres allumées)
	local litWindows: { Frame } = {}
	local towerLight: Frame
	do
		local x = -2
		for _, h in ipairs({ 30, 46, 26, 52, 36, 42, 30, 48 }) do
			local w = random:NextInteger(14, 20)
			frame({ Name = "FarBuilding", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(x, GLASS_H), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Color3.fromRGB(84, 64, 132), BackgroundTransparency = 0.25, ZIndex = 3, Parent = glass })
			x += w + 1
			if x > GLASS_W then
				break
			end
		end
		local LIGHT_COLORS = { Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 170, 210), Color3.fromRGB(150, 230, 255) }
		x = 0
		for index, spec in ipairs({ { 22, 34 }, { 18, 48 }, { 26, 28 }, { 20, 58 }, { 24, 36 }, { 28, 44 } }) do
			local w, h = spec[1], spec[2]
			local building = frame({ Name = "Building", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(x, GLASS_H), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, ZIndex = 4, Parent = glass })
			gradient(building, Color3.fromRGB(42, 34, 80), Color3.fromRGB(20, 16, 42))
			-- Grille de fenêtres (quelques-unes allumées, qui changent)
			for row = 0, math.floor((h - 10) / 8) - 1 do
				for col = 0, math.floor((w - 4) / 6) - 1 do
					if #litWindows < 14 and random:NextNumber() < 0.4 then
						local lit = frame({
							Name = "Lit",
							Position = UDim2.fromOffset(3 + col * 6, 6 + row * 8),
							Size = UDim2.fromOffset(3, 4),
							BackgroundColor3 = LIGHT_COLORS[random:NextInteger(1, #LIGHT_COLORS)],
							BackgroundTransparency = random:NextNumber() < 0.6 and 0.1 or 1,
							ZIndex = 4,
							Parent = building,
						})
						table.insert(litWindows, lit)
					end
				end
			end
			if index == 4 then
				-- La tour : antenne + voyant rouge qui clignote
				frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(1.5, 12), BackgroundColor3 = Color3.fromRGB(30, 24, 50), ZIndex = 4, Parent = building })
				towerLight = circle(at({ BackgroundColor3 = Color3.fromRGB(255, 60, 70), ZIndex = 5, Parent = building }, w / 2, -12, 3, 3))
			elseif index == 2 then
				-- Enseigne néon sur le toit
				local sign = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -1), Size = UDim2.fromOffset(14, 5), BackgroundColor3 = Color3.fromRGB(255, 110, 200), ZIndex = 5, Parent = building })
				UI.Corner(sign, 2)
				UI.Stroke(sign, Color3.fromRGB(255, 150, 220), 1.5, 0.5)
			end
			x += w + 2
			if x > GLASS_W then
				break
			end
		end
	end

	-- Pluie : réserve de traits recyclés (aucune création par image)
	local RAIN_ANGLE = math.rad(12)
	local RAIN_SPEED = 230
	local drops: { { Frame: Frame, X: number, Y: number, Speed: number } } = {}
	for _ = 1, (effectsOn() and RAIN_DROPS or 8) do
		local drop = frame({
			Name = "Rain",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(1.5, random:NextInteger(8, 14)),
			BackgroundColor3 = RAIN_COLOR,
			BackgroundTransparency = random:NextNumber(0.3, 0.6),
			Rotation = 12,
			ZIndex = 5,
			Parent = glass,
		})
		table.insert(drops, { Frame = drop, X = random:NextNumber(0, GLASS_W + 30), Y = random:NextNumber(-20, GLASS_H), Speed = RAIN_SPEED * random:NextNumber(0.8, 1.2) })
	end

	-- Gouttes qui glissent sur la vitre
	local beads: { { Frame: Frame, X: number, Y: number, Speed: number } } = {}
	for _ = 1, 2 do
		local bead = circle({
			Name = "Bead",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(4, 5),
			BackgroundColor3 = Color3.fromRGB(220, 235, 255),
			BackgroundTransparency = 0.35,
			ZIndex = 6,
			Parent = glass,
		})
		table.insert(beads, { Frame = bead, X = random:NextNumber(8, GLASS_W - 8), Y = random:NextNumber(0, GLASS_H), Speed = random:NextNumber(6, 16) })
	end

	-- Reflet sur la vitre + éclair (voile blanc)
	local lightning = frame({ Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(230, 225, 255), BackgroundTransparency = 1, ZIndex = 6, Parent = glass })
	do
		local reflection = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(34, 30), Size = UDim2.fromOffset(12, 110), Rotation = 35, BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, ZIndex = 7, Parent = glass })
		UI.Create("UIGradient", { Transparency = NumberSequence.new(1, 0.3), Rotation = 0, Parent = reflection })

		-- Croisillons de la fenêtre (au-dessus de la vitre)
		frame({ Name = "MullionV", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = WOOD_LIGHT, ZIndex = 8, Parent = windowFrame })
		frame({ Name = "MullionH", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = WOOD_LIGHT, ZIndex = 8, Parent = windowFrame })

		-- Rebord
		local sill = frame({ Name = "Sill", Position = UDim2.fromOffset(WINDOW_X - 8, SILL_Y), Size = UDim2.fromOffset(WINDOW_W + 16, 8), BackgroundColor3 = WHITE, ZIndex = 7, Parent = scene })
		UI.Corner(sill, 3)
		gradient(sill, Color3.fromRGB(236, 208, 170), Color3.fromRGB(176, 144, 110))

		-- Rideaux (plis dans le dégradé) + tringle
		local FOLDS = bands({
			{ 0, Color3.fromRGB(214, 128, 158) },
			{ 0.25, Color3.fromRGB(176, 92, 128) },
			{ 0.5, Color3.fromRGB(222, 140, 168) },
			{ 0.75, Color3.fromRGB(176, 92, 128) },
			{ 1, Color3.fromRGB(206, 120, 150) },
		})
		for side = -1, 1, 2 do
			local x = side < 0 and WINDOW_X - 12 or WINDOW_X + WINDOW_W - 12
			local curtain = frame({ Name = "Curtain", Position = UDim2.fromOffset(x, WINDOW_Y - 8), Size = UDim2.fromOffset(24, WINDOW_H + 10), BackgroundColor3 = WHITE, ZIndex = 9, Parent = scene })
			UI.Corner(curtain, 6)
			UI.Gradient(curtain, FOLDS, 0)
			-- Embrasse (lien qui retient le rideau)
			frame(at({ BackgroundColor3 = Color3.fromRGB(255, 214, 120), ZIndex = 9, Parent = curtain }, 12, WINDOW_H - 20, 26, 3))
		end
		local rod = frame({ Name = "Rod", Position = UDim2.fromOffset(WINDOW_X - 16, WINDOW_Y - 10), Size = UDim2.fromOffset(WINDOW_W + 32, 4), BackgroundColor3 = Color3.fromRGB(110, 76, 60), ZIndex = 10, Parent = scene })
		UI.Corner(rod, 2)
		for side = 0, 1 do
			circle(at({ BackgroundColor3 = Color3.fromRGB(150, 106, 80), ZIndex = 10, Parent = rod }, side * (WINDOW_W + 32), 2, 7, 7))
		end
	end

	------------------------------------------------------------------
	-- Guirlande lumineuse le long de la tringle
	------------------------------------------------------------------
	local FAIRY_COLORS = {
		Color3.fromRGB(255, 220, 110),
		Color3.fromRGB(255, 140, 200),
		Color3.fromRGB(120, 230, 255),
		Color3.fromRGB(255, 170, 90),
		Color3.fromRGB(190, 160, 255),
		Color3.fromRGB(140, 240, 170),
		Color3.fromRGB(255, 220, 110),
	}
	local fairy: { { Frame: Frame, Glow: UIStroke, Phase: number } } = {}
	for i, color in ipairs(FAIRY_COLORS) do
		local u = (i - 0.5) / #FAIRY_COLORS
		local bulbFrame = circle(at({ Name = "Fairy" .. i, BackgroundColor3 = color, ZIndex = 11, Parent = scene }, WINDOW_X - 6 + u * (WINDOW_W + 12), WINDOW_Y - 3 + math.sin(u * math.pi) * 5, 5, 6))
		table.insert(fairy, { Frame = bulbFrame, Glow = UI.Stroke(bulbFrame, color, 2.5, 0.55), Phase = random:NextNumber(0, math.pi * 2) })
	end

	------------------------------------------------------------------
	-- Rebord : chat endormi + plantes
	------------------------------------------------------------------
	local CAT_COLOR = Color3.fromRGB(248, 182, 104)
	local CAT_DARK = Color3.fromRGB(214, 136, 64)
	local catX, catBottom = WINDOW_X + 6, SILL_Y + 1
	local headX, headY = catX + 56, catBottom - 14

	local tail = frame({ Name = "CatTail", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(catX + 6, catBottom - 6), Size = UDim2.fromOffset(26, 7), BackgroundColor3 = CAT_DARK, ZIndex = 8, Parent = scene })
	UI.Corner(tail, UDim.new(1, 0))
	local catBody = circle({ Name = "CatBody", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(catX + 28, catBottom), Size = UDim2.fromOffset(58, 24), BackgroundColor3 = WHITE, ZIndex = 9, Parent = scene })
	gradient(catBody, Color3.fromRGB(255, 210, 146), CAT_COLOR)
	local bodyScale = UI.Create("UIScale", { Parent = catBody })
	local zLabels: { TextLabel } = {}
	do
		for i = 1, 3 do
			frame({ Name = "Stripe", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(16 + i * 9, 1), Size = UDim2.fromOffset(3, 9), Rotation = 12, BackgroundColor3 = CAT_DARK, ZIndex = 9, Parent = catBody })
		end
		-- Pattes repliées
		for i = 0, 1 do
			local paw = circle(at({ BackgroundColor3 = Color3.fromRGB(255, 226, 180), ZIndex = 10, Parent = scene }, catX + 42 + i * 7, catBottom - 2, 8, 5))
			paw.Name = "Paw"
		end
		for side = -1, 1, 2 do
			local ear = frame(at({ Name = "CatEar", BackgroundColor3 = CAT_DARK, Rotation = 45, ZIndex = 9, Parent = scene }, headX + side * 7, headY - 9, 9, 9))
			frame(at({ BackgroundColor3 = Color3.fromRGB(255, 160, 170), ZIndex = 9, Parent = ear }, 5, 5, 4, 4))
		end
		local head = circle(at({ Name = "CatHead", BackgroundColor3 = WHITE, ZIndex = 10, Parent = scene }, headX, headY, 26, 22))
		gradient(head, Color3.fromRGB(255, 210, 146), CAT_COLOR)
		for side = -1, 1, 2 do
			arc(at({ Name = "Eye", ZIndex = 10, Parent = head }, 13 + side * 5, 9, 5, 5), Color3.fromRGB(70, 40, 30), 1.2, LOWER_ARC)
			-- Moustaches
			frame(at({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, Rotation = side * 8, ZIndex = 11, Parent = head }, 13 + side * 13, 15, 9, 1))
		end
		frame(at({ Name = "Nose", BackgroundColor3 = Color3.fromRGB(255, 130, 150), ZIndex = 10, Parent = head }, 13, 14, 4, 3))

		-- "z z z" qui montent de la tête du chat (3 lettres recyclées)
		for i = 1, 3 do
			zLabels[i] = UI.Create("TextLabel", {
				Name = "Z",
				Text = i == 3 and "Z" or "z",
				Font = Theme.Fonts.Title,
				TextSize = 12,
				TextColor3 = WHITE,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(20, 20),
				ZIndex = 11,
				Parent = scene,
			})
		end

		-- Plantes sur le rebord : succulente + petit cactus
		local potX = WINDOW_X + WINDOW_W - 18
		local pot = frame({ Name = "Pot", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(potX, SILL_Y + 1), Size = UDim2.fromOffset(16, 12), BackgroundColor3 = WHITE, ZIndex = 9, Parent = scene })
		UI.Corner(pot, 3)
		gradient(pot, Color3.fromRGB(240, 150, 110), Color3.fromRGB(196, 100, 76))
		for i, rotation in ipairs({ -60, -28, 0, 28, 60 }) do
			local leaf = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(potX, SILL_Y - 9), Size = UDim2.fromOffset(6, 12 + (i % 2) * 3), Rotation = rotation, BackgroundColor3 = WHITE, ZIndex = 8, Parent = scene })
			UI.Corner(leaf, UDim.new(1, 0))
			gradient(leaf, Color3.fromRGB(150, 230, 170), Color3.fromRGB(60, 150, 110))
		end
		local cactusPot = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(potX - 22, SILL_Y + 1), Size = UDim2.fromOffset(11, 8), BackgroundColor3 = Color3.fromRGB(120, 180, 255), ZIndex = 9, Parent = scene })
		UI.Corner(cactusPot, 2)
		local cactus = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(potX - 22, SILL_Y - 6), Size = UDim2.fromOffset(7, 14), BackgroundColor3 = Color3.fromRGB(90, 190, 120), ZIndex = 8, Parent = scene })
		UI.Corner(cactus, UDim.new(1, 0))
		circle(at({ BackgroundColor3 = Color3.fromRGB(255, 140, 180), ZIndex = 9, Parent = cactus }, 3.5, 0, 4, 4))
	end

	------------------------------------------------------------------
	-- Mur : horloge à aiguilles, étagère de vinyles, photos, post-it
	------------------------------------------------------------------
	local CLOCK_X, CLOCK_Y = 208, 30
	local hourHand, minuteHand
	do
		local clockFace = circle(at({ Name = "Clock", BackgroundColor3 = WHITE, ZIndex = 3, Parent = scene }, CLOCK_X, CLOCK_Y, 30, 30))
		gradient(clockFace, Color3.fromRGB(255, 250, 238), Color3.fromRGB(236, 224, 206))
		UI.Stroke(clockFace, Color3.fromRGB(150, 100, 76), 2.5)
		for i = 0, 3 do
			local angle = i * math.pi / 2
			frame(at({ BackgroundColor3 = Color3.fromRGB(110, 80, 70), Rotation = i * 90, ZIndex = 3, Parent = clockFace }, 15 + math.sin(angle) * 11, 15 - math.cos(angle) * 11, 1.5, 4))
		end
		hourHand = frame({ Name = "Hour", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(15, 15), Size = UDim2.fromOffset(2.5, 8), BackgroundColor3 = Color3.fromRGB(60, 40, 50), ZIndex = 4, Parent = clockFace })
		minuteHand = frame({ Name = "Minute", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(15, 15), Size = UDim2.fromOffset(1.5, 11), BackgroundColor3 = Color3.fromRGB(60, 40, 50), ZIndex = 4, Parent = clockFace })
		circle(at({ BackgroundColor3 = PHONES, ZIndex = 5, Parent = clockFace }, 15, 15, 4, 4))
	end

	-- Étagère de vinyles (amélioration "Vinyl" : de plus en plus de disques)
	local SHELF_X, SHELF_Y, SHELF_W = 180, 78, 62
	local records: { Frame } = {}
	local extraSleeve: Frame
	local goldRecord: Frame
	do
		local shelf = frame({ Name = "RecordShelf", Position = UDim2.fromOffset(SHELF_X, SHELF_Y), Size = UDim2.fromOffset(SHELF_W, 4), BackgroundColor3 = WHITE, ZIndex = 4, Parent = scene })
		UI.Corner(shelf, 1)
		gradient(shelf, Color3.fromRGB(220, 170, 124), Color3.fromRGB(140, 94, 66))
		for side = 0, 1 do
			frame({ Position = UDim2.fromOffset(6 + side * (SHELF_W - 16), 4), Size = UDim2.fromOffset(4, 6), BackgroundColor3 = Color3.fromRGB(120, 84, 60), ZIndex = 4, Parent = shelf })
		end
		-- Pochette de face (appuyée contre le mur)
		local sleeve = frame({ Name = "Sleeve", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromOffset(SHELF_X + SHELF_W - 1, SHELF_Y), Size = UDim2.fromOffset(19, 19), Rotation = 4, BackgroundColor3 = WHITE, ZIndex = 5, Parent = scene })
		gradient(sleeve, Color3.fromRGB(255, 140, 180), Color3.fromRGB(120, 90, 220), 45)
		circle(at({ BackgroundColor3 = Color3.fromRGB(255, 236, 170), ZIndex = 5, Parent = sleeve }, 12, 7, 6, 6))
		frame({ Position = UDim2.fromOffset(0, 13), Size = UDim2.fromOffset(19, 6), BackgroundColor3 = Color3.fromRGB(40, 30, 70), BackgroundTransparency = 0.3, ZIndex = 5, Parent = sleeve })
		-- Deuxième pochette (Vinyl niveau 5)
		extraSleeve = frame({ Name = "Sleeve2", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromOffset(SHELF_X + SHELF_W - 14, SHELF_Y), Size = UDim2.fromOffset(18, 18), Rotation = -6, BackgroundColor3 = WHITE, Visible = false, ZIndex = 4, Parent = scene })
		gradient(extraSleeve, Color3.fromRGB(120, 220, 255), Color3.fromRGB(40, 90, 180), 45)
		circle(at({ BackgroundColor3 = Color3.fromRGB(20, 20, 30), ZIndex = 4, Parent = extraSleeve }, 9, 9, 12, 12))
		-- Tranches des disques rangés (affichées selon le niveau)
		for i = 1, MAX_RECORDS do
			local color = RECORD_COLORS[(i * 5) % #RECORD_COLORS + 1]
			records[i] = frame({
				Name = "Record" .. i,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromOffset(SHELF_X + 2 + (i - 1) * 3.4, SHELF_Y),
				Size = UDim2.fromOffset(3, 15 + (i * 7) % 5),
				BackgroundColor3 = color,
				Visible = false,
				ZIndex = 5,
				Parent = scene,
			})
		end
		-- Disque d'or encadré (Vinyl niveau 10)
		goldRecord = frame({ Name = "GoldRecord", Position = UDim2.fromOffset(SHELF_X + 2, SHELF_Y + 14), Size = UDim2.fromOffset(24, 28), BackgroundColor3 = Color3.fromRGB(40, 30, 50), Visible = false, ZIndex = 3, Parent = scene })
		UI.Corner(goldRecord, 2)
		UI.Stroke(goldRecord, Color3.fromRGB(230, 200, 150), 1.5)
		local disc = circle(at({ BackgroundColor3 = WHITE, ZIndex = 3, Parent = goldRecord }, 12, 12, 18, 18))
		gradient(disc, Color3.fromRGB(255, 236, 140), Color3.fromRGB(210, 150, 40), 45)
		circle(at({ BackgroundColor3 = Color3.fromRGB(255, 120, 150), ZIndex = 3, Parent = disc }, 9, 9, 5, 5))
		frame({ Position = UDim2.fromOffset(4, 23), Size = UDim2.fromOffset(16, 2), BackgroundColor3 = Color3.fromRGB(230, 200, 150), ZIndex = 3, Parent = goldRecord })
	end

	-- Guirlande de photos (polaroïds sur une ficelle) + post-it
	do
		frame({ Name = "String", Position = UDim2.fromOffset(240, 14), Size = UDim2.fromOffset(52, 1), Rotation = 3, BackgroundColor3 = Color3.fromRGB(230, 210, 190), BackgroundTransparency = 0.3, ZIndex = 3, Parent = scene })
		for i, spec in ipairs({ { 248, -6, Color3.fromRGB(120, 180, 255), Color3.fromRGB(255, 190, 150) }, { 268, 5, Color3.fromRGB(255, 150, 190), Color3.fromRGB(150, 110, 220) }, { 287, -3, Color3.fromRGB(130, 220, 170), Color3.fromRGB(60, 120, 150) } }) do
			local photo = frame({ Name = "Photo" .. i, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(spec[1], 13 + i * 0.6), Size = UDim2.fromOffset(15, 18), Rotation = spec[2], BackgroundColor3 = Color3.fromRGB(252, 250, 244), ZIndex = 4, Parent = scene })
			local picture = frame({ Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(11, 10), BackgroundColor3 = WHITE, ZIndex = 4, Parent = photo })
			gradient(picture, spec[3], spec[4])
			frame(at({ BackgroundColor3 = Color3.fromRGB(200, 170, 120), ZIndex = 5, Parent = photo }, 7.5, 0, 3, 4))
		end
		local note = frame({ Name = "PostIt", Position = UDim2.fromOffset(304, 14), Size = UDim2.fromOffset(54, 38), Rotation = 5, BackgroundColor3 = WHITE, ZIndex = 4, Parent = scene })
		gradient(note, Color3.fromRGB(255, 240, 140), Color3.fromRGB(250, 214, 96))
		UI.Stroke(note, Color3.fromRGB(0, 0, 0), 1, 0.8)
		frame(at({ BackgroundColor3 = Color3.fromRGB(255, 120, 150), ZIndex = 5, Parent = note }, 27, 1, 14, 4))
		UI.Create("TextLabel", {
			Text = Locale.T("<s>study</s>\nclick ✅"),
			RichText = true,
			Font = Theme.Fonts.Body,
			TextSize = 11,
			TextColor3 = Color3.fromRGB(50, 40, 40),
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -6, 1, -6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			ZIndex = 4,
			Parent = note,
		})
		local heartNote = frame({ Name = "PostIt2", Position = UDim2.fromOffset(330, 54), Size = UDim2.fromOffset(22, 20), Rotation = -8, BackgroundColor3 = Color3.fromRGB(255, 170, 200), ZIndex = 4, Parent = scene })
		UI.Create("TextLabel", { Text = "♥", Font = Theme.Fonts.Title, TextSize = 13, TextColor3 = Color3.fromRGB(220, 60, 110), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = heartNote })
	end

	------------------------------------------------------------------
	-- Lampe de bureau articulée (le cône de lumière éclaire le plateau)
	------------------------------------------------------------------
	local bulb: Frame
	do
		local cone = frame({ Name = "LightCone", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(LAMP_X - 8, 106), Size = UDim2.fromOffset(84, DESK_FRONT - 106), BackgroundColor3 = Color3.fromRGB(255, 214, 140), ZIndex = 11, Parent = scene })
		UI.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.62, 0.93), Parent = cone })
		local ARM_GRAD = ColorSequence.new(Color3.fromRGB(120, 120, 140), Color3.fromRGB(60, 60, 74))
		local lower = limb({ Name = "LampArm", BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene }, LAMP_X + 16, ITEM_BASE - 2, LAMP_X + 22, 120, 4)
		UI.Gradient(lower, ARM_GRAD, 0)
		local upper = limb({ Name = "LampArm2", BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene }, LAMP_X + 22, 120, LAMP_X + 4, 100, 4)
		UI.Gradient(upper, ARM_GRAD, 0)
		-- Ressort + articulation
		limb({ BackgroundColor3 = Color3.fromRGB(200, 200, 214), BackgroundTransparency = 0.3, ZIndex = 12, Parent = scene }, LAMP_X + 20, 148, LAMP_X + 24, 126, 1.5)
		circle(at({ BackgroundColor3 = Color3.fromRGB(150, 150, 170), ZIndex = 13, Parent = scene }, LAMP_X + 22, 120, 7, 7))
		local base = frame(at({ Name = "LampBase", BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene }, LAMP_X + 16, ITEM_BASE, 28, 7))
		UI.Corner(base, 3)
		gradient(base, Color3.fromRGB(120, 120, 140), Color3.fromRGB(52, 52, 64))
		local shade = frame(at({ Name = "LampShade", BackgroundColor3 = WHITE, Rotation = -18, ZIndex = 12, Parent = scene }, LAMP_X - 2, 100, 40, 18))
		UI.Corner(shade, UDim.new(0.5, 0))
		gradient(shade, Color3.fromRGB(255, 206, 100), Color3.fromRGB(228, 116, 60))
		frame(at({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, ZIndex = 12, Parent = shade }, 14, 5, 12, 2))
		bulb = circle({ Name = "Bulb", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(13, 8), BackgroundColor3 = Color3.fromRGB(255, 250, 210), ZIndex = 12, Parent = shade })
	end

	------------------------------------------------------------------
	-- Le personnage (corps + tête) derrière le bureau
	------------------------------------------------------------------
	local person = frame({ Name = "Person", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7, Parent = scene })

	-- Cheveux longs derrière le dos, sweat à capuche
	local backLong = frame(at({ Name = "LongHair", BackgroundColor3 = WHITE, ZIndex = 1, Parent = person }, PX, 116, 66, 50))
	UI.Corner(backLong, 20)
	gradient(backLong, HAIR, HAIR:Lerp(Color3.new(0, 0, 0), 0.25))
	local torso = frame(at({ Name = "Torso", BackgroundColor3 = WHITE, ZIndex = 1, Parent = person }, PX, 140, 80, 64))
	UI.Corner(torso, 28)
	UI.Gradient(torso, ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOODIE:Lerp(WHITE, 0.15)),
		ColorSequenceKeypoint.new(0.6, HOODIE),
		ColorSequenceKeypoint.new(1, HOODIE_DARK),
	}), 90)
	local neck = frame(at({ Name = "Neck", BackgroundColor3 = SKIN_SHADE, ZIndex = 2, Parent = person }, PX, 104, 13, 12))
	UI.Corner(neck, 4)
	local collar = frame(at({ Name = "Hood", BackgroundColor3 = WHITE, ZIndex = 3, Parent = person }, PX, 110, 58, 16))
	UI.Corner(collar, 8)
	gradient(collar, HOODIE_DARK:Lerp(WHITE, 0.1), HOODIE_DARK)
	for side = -1, 1, 2 do
		local cord = frame(at({ Name = "String", BackgroundColor3 = Color3.fromRGB(245, 245, 255), BackgroundTransparency = 0.1, ZIndex = 3, Parent = torso }, 40 + side * 7, 16, 2, 14))
		UI.Corner(cord, 1)
	end

	-- Tête (support qui hoche : tout ce qui est dedans bouge avec)
	local headHolder = frame(at({ Name = "Head", BackgroundTransparency = 1, ZIndex = 4, Parent = person }, PX, HEAD_Y, 80, 80))

	-- Pièce de la tête, centrée sur (x, y) par rapport au centre de la tête
	local function headPart(props: { [string]: any }, x: number, y: number, w: number, h: number): Frame
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.new(0.5, x, 0.5, y)
		props.Size = UDim2.fromOffset(w, h)
		props.Parent = props.Parent or headHolder
		return frame(props)
	end

	-- Halo lumineux des écouteurs (derrière tout)
	local phoneGlows: { Frame } = {}
	for side = -1, 1, 2 do
		local glow = headPart({ Name = "PhoneGlow", BackgroundColor3 = PHONES_GLOW, BackgroundTransparency = 0.78, ZIndex = 1 }, side * 33, 6, 40, 40)
		UI.Corner(glow, UDim.new(1, 0))
		table.insert(phoneGlows, glow)
	end

	do
		-- Cheveux (arrière) + mèches sur les côtés
		local backHair = headPart({ Name = "BackHair", BackgroundColor3 = WHITE, ZIndex = 2 }, 0, -2, 58, 56)
		UI.Corner(backHair, UDim.new(1, 0))
		gradient(backHair, HAIR_LIGHT, HAIR)
		for side = -1, 1, 2 do
			local lock = headPart({ Name = "Lock", BackgroundColor3 = HAIR, ZIndex = 4 }, side * 23, 12, 13, 32)
			UI.Corner(lock, 7)
		end

		-- Visage : yeux baissés (arcs), cils, joues, taches de rousseur
		local face = headPart({ Name = "Face", BackgroundColor3 = WHITE, ZIndex = 3 }, 0, 5, 46, 43)
		UI.Corner(face, UDim.new(0.48, 0))
		gradient(face, SKIN, SKIN_SHADE)
		for side = -1, 1, 2 do
			local eye = headPart({ Name = "Eye", ZIndex = 5 }, side * 10, 4, 10, 10)
			eye.BackgroundTransparency = 1
			UI.Corner(eye, UDim.new(1, 0))
			local eyeStroke = UI.Stroke(eye, LINE_INK, 2, 0)
			UI.Create("UIGradient", { Rotation = 90, Transparency = LOWER_ARC, Parent = eyeStroke })
			local lash = headPart({ Name = "Lash", BackgroundColor3 = LINE_INK, Rotation = side * 30, ZIndex = 5 }, side * 16.5, 5.5, 4, 1.6)
			UI.Corner(lash, 1)
			local brow = headPart({ Name = "Brow", BackgroundColor3 = HAIR, Rotation = side * -6, ZIndex = 5 }, side * 10, -4, 8, 1.6)
			UI.Corner(brow, 1)
			local blush = headPart({ Name = "Blush", BackgroundColor3 = Color3.fromRGB(255, 136, 160), BackgroundTransparency = 0.45, ZIndex = 5 }, side * 13, 13, 9, 5)
			UI.Corner(blush, UDim.new(1, 0))
			for k = 0, 1 do
				headPart({ BackgroundColor3 = Color3.fromRGB(214, 140, 120), BackgroundTransparency = 0.3, ZIndex = 5 }, side * (12 + k * 3), 10 + k, 1.3, 1.3)
			end
		end
		local nose = headPart({ Name = "Nose", BackgroundColor3 = SKIN_SHADE:Lerp(Color3.fromRGB(200, 120, 110), 0.4), ZIndex = 5 }, 0, 11, 2.5, 2)
		UI.Corner(nose, 1)
		local mouth = headPart({ Name = "Mouth", ZIndex = 5 }, 0, 14, 6, 6)
		mouth.BackgroundTransparency = 1
		UI.Corner(mouth, UDim.new(1, 0))
		local mouthStroke = UI.Stroke(mouth, LINE_INK, 1.5, 0.1)
		UI.Create("UIGradient", { Rotation = 90, Transparency = LOWER_ARC, Parent = mouthStroke })

		-- Frange, reflet, épi, barrette
		for _, spec in ipairs({ { -11, -13, 28, 17, -20 }, { 12, -13, 28, 17, 22 }, { 0, -16, 30, 14, 0 } }) do
			local bang = headPart({ Name = "Bang", BackgroundColor3 = WHITE, Rotation = spec[5], ZIndex = 6 }, spec[1], spec[2], spec[3], spec[4])
			UI.Corner(bang, UDim.new(1, 0))
			gradient(bang, HAIR_LIGHT:Lerp(HAIR, 0.45), HAIR)
		end
		local shine = headPart({ Name = "HairShine", BackgroundColor3 = HAIR_LIGHT:Lerp(WHITE, 0.3), BackgroundTransparency = 0.25, Rotation = -18, ZIndex = 7 }, -9, -21, 14, 3.5)
		UI.Corner(shine, UDim.new(1, 0))
		local ahoge = headPart({ Name = "Ahoge", BackgroundColor3 = HAIR, Rotation = 30, ZIndex = 6 }, 5, -31, 3.5, 12)
		UI.Corner(ahoge, UDim.new(1, 0))
		local clip = headPart({ Name = "Clip", BackgroundColor3 = Color3.fromRGB(255, 226, 110), Rotation = -20, ZIndex = 7 }, -17, -14, 9, 3.5)
		UI.Corner(clip, 2)

		-- GROS casque : arceau (haut d'un cercle) + deux écouteurs vernis
		local band = headPart({ Name = "Band", BackgroundTransparency = 1, ZIndex = 7 }, 0, 4, 64, 64)
		UI.Corner(band, UDim.new(1, 0))
		local bandStroke = UI.Stroke(band, WHITE, 6, 0)
		UI.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(PHONES:Lerp(WHITE, 0.3), PHONES_DARK), Transparency = UPPER_ARC, Parent = bandStroke })
		for side = -1, 1, 2 do
			local cushion = headPart({ Name = "Cushion", BackgroundColor3 = Color3.fromRGB(70, 44, 90), ZIndex = 7 }, side * 26, 6, 7, 20)
			UI.Corner(cushion, 3)
			local cup = headPart({ Name = "Cup", BackgroundColor3 = WHITE, ZIndex = 8 }, side * 33, 6, 16, 26)
			UI.Corner(cup, 7)
			UI.Gradient(cup, ColorSequence.new({
				ColorSequenceKeypoint.new(0, PHONES:Lerp(WHITE, 0.35)),
				ColorSequenceKeypoint.new(0.45, PHONES),
				ColorSequenceKeypoint.new(1, PHONES_DARK),
			}), 90)
			UI.Stroke(cup, PHONES_DARK, 1.5, 0.2)
			local cupShine = headPart({ Name = "CupShine", BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, ZIndex = 9 }, side * 33 - 3, -1, 3, 8)
			UI.Corner(cupShine, UDim.new(1, 0))
			-- Petit cœur sur l'écouteur
			local heart = headPart({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, Rotation = 45, ZIndex = 9 }, side * 33 + 1, 9, 4, 4)
			UI.Corner(heart, 1)
		end
	end

	------------------------------------------------------------------
	-- Bureau
	------------------------------------------------------------------
	do
		-- Face avant créée AVANT le plateau (même ZIndex : le plateau passe devant) :
		-- elle remonte derrière lui et ses coins du bas sont arrondis comme la scène
		-- (ClipsDescendants découpe en rectangle : sinon coins carrés qui dépassent)
		local deskFront = frame({ Name = "DeskFront", Position = UDim2.fromOffset(0, DESK_FRONT - SCENE_RADIUS), Size = UDim2.new(1, 0, 0, SCENE_H - DESK_FRONT + SCENE_RADIUS), BackgroundColor3 = WHITE, ZIndex = 10, Parent = scene })
		UI.Corner(deskFront, SCENE_RADIUS)
		gradient(deskFront, Color3.fromRGB(122, 80, 58), Color3.fromRGB(78, 50, 40))
		-- Tiroir + poignée, veines du bois
		local drawer = frame({ Name = "Drawer", Position = UDim2.fromOffset(120, SCENE_RADIUS + 8), Size = UDim2.fromOffset(92, 22), BackgroundColor3 = Color3.fromRGB(138, 92, 66), ZIndex = 10, Parent = deskFront })
		UI.Corner(drawer, 3)
		UI.Stroke(drawer, Color3.fromRGB(70, 44, 34), 1, 0.4)
		frame(at({ BackgroundColor3 = Color3.fromRGB(230, 200, 150), ZIndex = 10, Parent = drawer }, 46, 11, 18, 3))
		for i, y in ipairs({ 18, 32 }) do
			frame({ Position = UDim2.fromOffset(8 + i * 20, y), Size = UDim2.fromOffset(80, 1), BackgroundColor3 = Color3.fromRGB(60, 36, 28), BackgroundTransparency = 0.6, ZIndex = 10, Parent = deskFront })
			frame({ Position = UDim2.fromOffset(236 + i * 14, y + 4), Size = UDim2.fromOffset(90, 1), BackgroundColor3 = Color3.fromRGB(60, 36, 28), BackgroundTransparency = 0.6, ZIndex = 10, Parent = deskFront })
		end
		local deskTop = frame({ Name = "DeskTop", Position = UDim2.fromOffset(0, DESK_Y), Size = UDim2.new(1, 0, 0, DESK_FRONT - DESK_Y), BackgroundColor3 = WHITE, ZIndex = 10, Parent = scene })
		UI.Gradient(deskTop, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 104, 76)),
			ColorSequenceKeypoint.new(0.85, Color3.fromRGB(186, 134, 96)),
			ColorSequenceKeypoint.new(0.9, Color3.fromRGB(214, 164, 118)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 164, 118)),
		}), 90)

		-- Pile de livres + pot à crayons
		for i, spec in ipairs({
			{ 134, 40, 7, Color3.fromRGB(96, 150, 230) },
			{ 136, 34, 6, Color3.fromRGB(240, 110, 120) },
			{ 133, 38, 7, Color3.fromRGB(250, 200, 90) },
		}) do
			local book = frame(at({ Name = "Book" .. i, BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene }, spec[1], ITEM_BASE - 3 - (i - 1) * 6.5, spec[2], spec[3]))
			UI.Corner(book, 2)
			gradient(book, spec[4]:Lerp(WHITE, 0.2), spec[4]:Lerp(Color3.new(0, 0, 0), 0.2))
			UI.Stroke(book, Color3.fromRGB(40, 24, 30), 1, 0.5)
			frame(at({ BackgroundColor3 = Color3.fromRGB(255, 250, 235), ZIndex = 12, Parent = book }, spec[2] - 3, spec[3] / 2, 3, spec[3] - 2))
		end
		local pens = frame({ Name = "PenCup", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(104, ITEM_BASE + 1), Size = UDim2.fromOffset(12, 15), BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene })
		UI.Corner(pens, 3)
		gradient(pens, Color3.fromRGB(190, 170, 255), Color3.fromRGB(120, 100, 200))
		for i, spec in ipairs({ { -3, -10, Color3.fromRGB(255, 200, 60) }, { 1, 6, Color3.fromRGB(255, 120, 150) }, { 3, 14, Color3.fromRGB(100, 200, 255) } }) do
			frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(104 + spec[1], ITEM_BASE - 12), Size = UDim2.fromOffset(2.5, 12 + i), Rotation = spec[2], BackgroundColor3 = spec[3], ZIndex = 11, Parent = scene })
		end
	end

	-- Tasse fumante
	local mugX = 176
	local steam: { Frame } = {}
	do
		local mug = frame(at({ Name = "Mug", BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene }, mugX, ITEM_BASE - 9, 16, 18))
		UI.Corner(mug, 4)
		gradient(mug, Color3.fromRGB(255, 250, 240), Color3.fromRGB(214, 206, 196), 0)
		frame(at({ Name = "Stripe", BackgroundColor3 = PHONES, ZIndex = 12, Parent = mug }, 8, 10, 16, 3))
		local handle = circle(at({ Name = "Handle", BackgroundTransparency = 1, ZIndex = 11, Parent = scene }, mugX + 9, ITEM_BASE - 9, 9, 9))
		UI.Stroke(handle, Color3.fromRGB(226, 218, 208), 2.5, 0)
		circle(at({ Name = "Coffee", BackgroundColor3 = Color3.fromRGB(110, 66, 44), ZIndex = 13, Parent = scene }, mugX, ITEM_BASE - 17, 13, 4))
		for i = 1, 3 do
			steam[i] = circle({ Name = "Steam", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 5), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 12, Parent = scene })
		end
	end

	------------------------------------------------------------------
	-- Platine vinyle sur le bureau (disque qui tourne, bras de lecture)
	------------------------------------------------------------------
	local TT_W = 76
	local platterSpin: UIGradient
	local recordLabel: Frame
	local ttLed: Frame
	local tonearm: Frame
	local tonearmRest = 0
	do
		local body = frame({ Name = "Turntable", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(TURNTABLE_X, ITEM_BASE + 3), Size = UDim2.fromOffset(TT_W, 13), BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene })
		UI.Corner(body, 3)
		gradient(body, Color3.fromRGB(250, 236, 214), Color3.fromRGB(206, 178, 146))
		UI.Stroke(body, Color3.fromRGB(110, 80, 60), 1, 0.4)
		-- Boutons + voyant
		for i = 0, 1 do
			circle(at({ BackgroundColor3 = Color3.fromRGB(90, 80, 90), ZIndex = 12, Parent = body }, 8 + i * 8, 7, 5, 5))
		end
		ttLed = circle(at({ BackgroundColor3 = Color3.fromRGB(90, 255, 150), ZIndex = 12, Parent = body }, TT_W - 8, 7, 4, 4))
		-- Plateau vu du dessus (ellipse) + disque noir, sillons, étiquette
		local top = frame({ Name = "Deck", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(TURNTABLE_X, ITEM_BASE - 9), Size = UDim2.fromOffset(TT_W, 12), BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene })
		UI.Corner(top, 4)
		gradient(top, Color3.fromRGB(236, 218, 196), Color3.fromRGB(222, 200, 172))
		local platter = circle(at({ Name = "Vinyl", BackgroundColor3 = Color3.fromRGB(26, 24, 32), ZIndex = 13, Parent = top }, 30, 5.5, 52, 12))
		platterSpin = UI.Gradient(platter, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 32, 44)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(34, 32, 44)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 104, 140)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(34, 32, 44)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 32, 44)),
		}), 0)
		local groove = circle(at({ BackgroundTransparency = 1, ZIndex = 13, Parent = platter }, 26, 6, 36, 8))
		UI.Stroke(groove, Color3.fromRGB(70, 66, 90), 1, 0.3)
		recordLabel = circle(at({ Name = "Label", BackgroundColor3 = WHITE, ZIndex = 14, Parent = platter }, 26, 6, 11, 4))
		UI.Gradient(recordLabel, ColorSequence.new(EQ_LOW, EQ_HIGH), 0)
		-- Bras de lecture (pivot à droite, pointe sur le disque)
		circle(at({ Name = "Pivot", BackgroundColor3 = Color3.fromRGB(180, 180, 196), ZIndex = 13, Parent = top }, TT_W - 10, 4, 7, 7))
		tonearm = limb({ Name = "Tonearm", BackgroundColor3 = Color3.fromRGB(200, 200, 214), ZIndex = 14, Parent = scene }, TURNTABLE_X + TT_W / 2 - 10, ITEM_BASE - 17, TURNTABLE_X + 14, ITEM_BASE - 13, 2)
		tonearmRest = tonearm.Rotation
	end

	------------------------------------------------------------------
	-- Mains sur le bureau : cahier, bras, crayon (devant le bureau)
	------------------------------------------------------------------
	local hands = frame({ Name = "Hands", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 12, Parent = scene })

	-- Cahier ouvert (page de gauche déjà écrite, page de droite en cours)
	local NOTE_W, NOTE_H = 66, 13
	local noteLeft, noteTop = PX - NOTE_W / 2, 157 - NOTE_H / 2
	local notebook = frame(at({ Name = "Notebook", BackgroundColor3 = WHITE, ZIndex = 1, Parent = hands }, PX, 157, NOTE_W, NOTE_H))
	UI.Corner(notebook, 2)
	UI.Gradient(notebook, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(236, 228, 212)),
		ColorSequenceKeypoint.new(0.46, WHITE),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(196, 186, 170)),
		ColorSequenceKeypoint.new(0.54, WHITE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 228, 212)),
	}), 0)
	UI.Stroke(notebook, Color3.fromRGB(120, 100, 90), 1, 0.4)
	for i = 1, 2 do
		frame({ Name = "Written" .. i, Position = UDim2.fromOffset(5, 3 + (i - 1) * 4.5), Size = UDim2.fromOffset(i == 1 and 24 or 17, 1.5), BackgroundColor3 = LINE_INK, BackgroundTransparency = 0.45, ZIndex = 2, Parent = notebook })
	end
	local WRITE_X, WRITE_W = 37, 24 -- zone d'écriture (page de droite)
	local writeLines: { Frame } = {}
	for i = 1, 2 do
		writeLines[i] = frame({ Name = "Writing" .. i, Position = UDim2.fromOffset(WRITE_X, 3 + (i - 1) * 4.5), Size = UDim2.fromOffset(0, 1.5), BackgroundColor3 = LINE_INK, BackgroundTransparency = 0.2, ZIndex = 2, Parent = notebook })
	end
	-- Page qui se tourne (feuille qui passe de droite à gauche)
	local turningPage = frame({ Name = "TurningPage", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(NOTE_W / 2, NOTE_H / 2), Size = UDim2.fromOffset(0, NOTE_H + 2), BackgroundColor3 = Color3.fromRGB(255, 252, 244), Visible = false, ZIndex = 3, Parent = notebook })
	UI.Corner(turningPage, 2)
	UI.Stroke(turningPage, Color3.fromRGB(150, 130, 120), 1, 0.5)

	-- Manches du sweat (dégradé le long du bras, poignet plus foncé)
	local SLEEVE = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOODIE),
		ColorSequenceKeypoint.new(0.8, HOODIE:Lerp(HOODIE_DARK, 0.3)),
		ColorSequenceKeypoint.new(0.82, HOODIE_DARK),
		ColorSequenceKeypoint.new(1, HOODIE_DARK),
	})
	local R_ELBOW = Vector2.new(PX + 50, 150)
	local rightFore, pencil, rightHand
	do
		local UPPER = ColorSequence.new(HOODIE:Lerp(WHITE, 0.12), HOODIE_DARK)
		local L_SHOULDER, L_ELBOW, L_WRIST = Vector2.new(PX - 32, 118), Vector2.new(PX - 48, 150), Vector2.new(PX - 20, 157)
		local R_SHOULDER = Vector2.new(PX + 32, 118)
		local leftUpper = limb({ Name = "LeftUpperArm", BackgroundColor3 = WHITE, ZIndex = 3, Parent = hands }, L_SHOULDER.X, L_SHOULDER.Y, L_ELBOW.X, L_ELBOW.Y, 17)
		UI.Gradient(leftUpper, UPPER, 0)
		local leftFore = limb({ Name = "LeftForearm", BackgroundColor3 = WHITE, ZIndex = 3, Parent = hands }, L_ELBOW.X, L_ELBOW.Y, L_WRIST.X, L_WRIST.Y, 15)
		UI.Gradient(leftFore, SLEEVE, 90)
		local leftHand = circle(at({ Name = "LeftHand", BackgroundColor3 = WHITE, ZIndex = 5, Parent = hands }, L_WRIST.X + 5, L_WRIST.Y, 11, 10))
		gradient(leftHand, SKIN, SKIN_SHADE)
		local rightUpper = limb({ Name = "RightUpperArm", BackgroundColor3 = WHITE, ZIndex = 3, Parent = hands }, R_SHOULDER.X, R_SHOULDER.Y, R_ELBOW.X, R_ELBOW.Y, 17)
		UI.Gradient(rightUpper, UPPER, 180)
		rightFore = limb({ Name = "RightForearm", BackgroundColor3 = WHITE, ZIndex = 3, Parent = hands }, R_ELBOW.X, R_ELBOW.Y, PX + 20, 152, 15)
		UI.Gradient(rightFore, SLEEVE, 90)
		pencil = limb({ Name = "Pencil", BackgroundColor3 = WHITE, ZIndex = 4, Parent = hands }, PX + 10, 155, PX + 19, 139, 3.5)
		UI.Gradient(pencil, bands({
			{ 0, Color3.fromRGB(60, 56, 70) },
			{ 0.1, Color3.fromRGB(60, 56, 70) },
			{ 0.11, Color3.fromRGB(242, 206, 158) },
			{ 0.24, Color3.fromRGB(242, 206, 158) },
			{ 0.25, Color3.fromRGB(255, 204, 60) },
			{ 0.83, Color3.fromRGB(255, 190, 40) },
			{ 0.84, Color3.fromRGB(200, 200, 214) },
			{ 0.9, Color3.fromRGB(200, 200, 214) },
			{ 0.91, Color3.fromRGB(255, 140, 164) },
			{ 1, Color3.fromRGB(255, 140, 164) },
		}), 90)
		rightHand = circle(at({ Name = "RightHand", BackgroundColor3 = WHITE, ZIndex = 5, Parent = hands }, PX + 14, 150, 11, 10))
		gradient(rightHand, SKIN, SKIN_SHADE)
	end

	------------------------------------------------------------------
	-- Notes de musique (casque et platine) : réserve recyclée
	------------------------------------------------------------------
	local notes: { { Label: TextLabel, Active: boolean, Age: number, X: number, Y: number, Dir: number, Rise: number } } = {}
	for i = 1, NOTE_POOL do
		local label = UI.Create("TextLabel", {
			Name = "Note",
			Text = i % 2 == 1 and "♪" or "♫",
			Font = Theme.Fonts.Title,
			TextSize = 16,
			TextColor3 = NOTE_COLORS[(i - 1) % #NOTE_COLORS + 1],
			TextStrokeColor3 = Color3.fromRGB(40, 20, 60),
			TextStrokeTransparency = 0.5,
			TextTransparency = 1,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			Visible = false,
			ZIndex = 14,
			Parent = scene,
		})
		table.insert(notes, { Label = label, Active = false, Age = 0, X = 0, Y = 0, Dir = 1, Rise = 58 })
	end

	local function spawnNote(x: number, y: number, dir: number, rise: number)
		for _, n in ipairs(notes) do
			if not n.Active then
				n.Active = true
				n.Age = 0
				n.Dir = dir
				n.X, n.Y = x, y
				n.Rise = rise
				S.noteColorIndex = S.noteColorIndex % #NOTE_COLORS + 1
				n.Label.TextColor3 = NOTE_COLORS[S.noteColorIndex]
				n.Label.Text = random:NextNumber() < 0.5 and "♪" or "♫"
				n.Label.Visible = true
				return
			end
		end
	end

	------------------------------------------------------------------
	-- Barre du bas : lecteur (pochette + vinyle, morceau, progression,
	-- visualiseur, ⏭)
	------------------------------------------------------------------
	local isStudio = RunService:IsStudio()
	local bar = frame({ Name = "Bar", Position = UDim2.fromOffset(SCENE_X, BAR_Y), Size = UDim2.fromOffset(SCENE_W, BAR_H), BackgroundColor3 = WHITE, Parent = card })
	UI.Corner(bar, 10)
	gradient(bar, Color3.fromRGB(44, 34, 76), Color3.fromRGB(20, 16, 36))
	UI.Stroke(bar, Color3.fromRGB(120, 96, 186), 1, 0.4)

	-- Vinyle qui sort de sa pochette (tourne pendant la musique)
	local disc = circle({ Name = "Vinyl", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(34, BAR_H / 2), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Color3.fromRGB(28, 26, 34), ZIndex = 1, Parent = bar })
	do
		UI.Stroke(disc, Color3.fromRGB(70, 64, 90), 1)
		local groove = circle(at({ Name = "Groove", BackgroundTransparency = 1, ZIndex = 1, Parent = disc }, 16, 16, 22, 22))
		UI.Stroke(groove, Color3.fromRGB(64, 60, 82), 1)
		local labelDisc = circle(at({ Name = "Label", BackgroundColor3 = WHITE, ZIndex = 1, Parent = disc }, 16, 16, 11, 11))
		UI.Gradient(labelDisc, ColorSequence.new(EQ_LOW, EQ_HIGH), 0)
		frame({ Name = "Shine", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -6), Size = UDim2.fromOffset(2, 7), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, ZIndex = 1, Parent = disc })
		-- Pochette (ciel de nuit + lune), par-dessus le disque
		local art = frame(at({ Name = "Cover", BackgroundColor3 = WHITE, ZIndex = 2, Parent = bar }, 21, BAR_H / 2, 32, 32))
		UI.Corner(art, 6)
		UI.Gradient(art, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 30, 100)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(150, 80, 160)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 150)),
		}), 90)
		UI.Stroke(art, WHITE, 1, 0.6)
		circle(at({ BackgroundColor3 = Color3.fromRGB(255, 244, 200), ZIndex = 2, Parent = art }, 22, 9, 8, 8))
		for i, h in ipairs({ 8, 13, 6, 10 }) do
			frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(2 + (i - 1) * 7, 32), Size = UDim2.fromOffset(6, h), BackgroundColor3 = Color3.fromRGB(30, 22, 60), ZIndex = 2, Parent = art })
		end
	end

	local TEXT_X = 60
	local title = UI.Create("TextLabel", {
		Name = "Title",
		Text = Locale.T("lofi beats 🎧 to study to"),
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(TEXT_X, 3),
		Size = UDim2.fromOffset(190, 17),
		Parent = bar,
	})
	local subtitle = UI.Create("TextLabel", {
		Name = "Subtitle",
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(200, 186, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(TEXT_X, 19),
		Size = UDim2.fromOffset(190, 13),
		Parent = bar,
	})
	-- Barre de progression du morceau
	local progress = frame({ Name = "Progress", Position = UDim2.fromOffset(TEXT_X, 34), Size = UDim2.fromOffset(190, 3), BackgroundColor3 = Color3.fromRGB(80, 66, 130), Parent = bar })
	UI.Corner(progress, UDim.new(1, 0))
	local progressFill = frame({ Name = "Fill", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = WHITE, Parent = progress })
	UI.Corner(progressFill, UDim.new(1, 0))
	UI.Gradient(progressFill, ColorSequence.new(EQ_LOW, EQ_HIGH), 0)
	local knob = circle({ Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3, 0.5), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = WHITE, Parent = progress })

	-- Bouton "morceau suivant"
	local skip = UI.Create("TextButton", {
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
	UI.Corner(skip, UDim.new(1, 0))
	UI.Stroke(skip, EQ_HIGH, 1.5, 0.4)
	UI.AnimateButton(skip, 1.1, 0.88)

	-- Visualiseur audio (barres + petits "pics" qui retombent)
	local EQ_W, EQ_H = 74, 28
	local eq = frame({ Name = "Equalizer", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(EQ_W, EQ_H), BackgroundTransparency = 1, Parent = bar })
	local barWidth = 4
	local barGap = (EQ_W - EQ_BARS * barWidth) / (EQ_BARS - 1)
	local eqBars: { Frame } = {}
	local eqPeaks: { Frame } = {}
	local eqHeights: { number } = {}
	local eqTargets: { number } = {}
	local peakHeights: { number } = {}
	for i = 1, EQ_BARS do
		local t = (i - 1) / (EQ_BARS - 1)
		local color = EQ_LOW:Lerp(EQ_HIGH, t)
		local eqBar = frame({ Name = "Bar" .. i, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, (i - 1) * (barWidth + barGap), 1, 0), Size = UDim2.fromOffset(barWidth, 4), BackgroundColor3 = WHITE, Parent = eq })
		UI.Gradient(eqBar, ColorSequence.new(color:Lerp(WHITE, 0.35), color), 90)
		eqPeaks[i] = frame({ Name = "Peak" .. i, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, (i - 1) * (barWidth + barGap), 1, -6), Size = UDim2.fromOffset(barWidth, 1.5), BackgroundColor3 = color:Lerp(WHITE, 0.5), Parent = eq })
		eqBars[i] = eqBar
		eqHeights[i] = 0.2
		eqTargets[i] = 0.2
		peakHeights[i] = 0.2
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

	-- (nom du morceau, Sound) si de la vraie musique joue, sinon nil.
	-- v8 : SoundManager.GetMusicInfo() -> { Key, Name, Index, Count, Playing }
	-- (si présent), sinon l'ancienne API GetCurrentTrack / IsMusicPlaying.
	local function currentMusic(): (string?, Sound?)
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
		return name, sound
	end

	local function viewersText(): string
		local count = S.viewers >= 1e6 and Format.Format(S.viewers) or Format.WithSpaces(S.viewers)
		return "🔴 " .. Locale.T("%s people studying (or not)", count)
	end

	local function refreshSubtitle()
		local name = currentMusic()
		local playlist = hasPlaylist()
		skip.Visible = name ~= nil and type(Sound.NextTrack) == "function"
		eq.Position = skip.Visible and UDim2.new(1, -44, 0.5, 0) or UDim2.new(1, -10, 0.5, 0)
		-- Textes : toute la place jusqu'au visualiseur
		local textWidth = SCENE_W - TEXT_X - EQ_W - (skip.Visible and 52 or 20)
		title.Size = UDim2.fromOffset(textWidth, 17)
		subtitle.Size = UDim2.fromOffset(textWidth, 13)
		progress.Size = UDim2.fromOffset(textWidth, 3)
		subtitle.TextColor3 = Color3.fromRGB(200, 186, 240)

		if name then
			-- Vraie musique
			title.Text = "♫ " .. Locale.T(name)
			subtitle.Text = S.showAlt and Locale.T("lofi beats 🎧 to study to") or viewersText()
		elseif playlist then
			-- Musique disponible mais coupée (réglage) ou en chargement
			title.Text = Locale.T("lofi beats 🎧 to study to")
			local musicOn = true
			if type(Sound.IsMusicEnabled) == "function" then
				local ok, value = pcall(Sound.IsMusicEnabled)
				musicOn = not ok or value ~= false
			end
			if S.showAlt then
				subtitle.Text = musicOn and Locale.T("♫ Loading music...") or Locale.T("🔇 Music off (⚙️ Settings)")
			else
				subtitle.Text = viewersText()
			end
		elseif isStudio then
			-- Rappel pour le créateur du jeu (seulement dans Studio)
			title.Text = Locale.T("lofi beats 🎧 to study to")
			subtitle.Text = Locale.T("⚠️ Add some music in Config.Music")
			subtitle.TextColor3 = Color3.fromRGB(255, 200, 90)
		else
			-- Pas de musique : juste l'ambiance
			title.Text = Locale.T("lofi beats 🎧 to study to")
			subtitle.Text = S.showAlt and ("♫ " .. tracks[S.trackIndex]) or viewersText()
		end
	end
	refreshSubtitle()

	-- Petit écran (slot réduit) : textes du lecteur un peu plus gros
	local function applyCompact()
		local scale = 1
		if type(ctx.GetSlotScale) == "function" then
			local ok, value = pcall(ctx.GetSlotScale)
			scale = ok and tonumber(value) or 1
		end
		local compact = scale < 0.62
		title.TextSize = compact and 17 or 14
		subtitle.TextSize = compact and 13 or 11
	end
	applyCompact()

	-- Réagit tout de suite aux changements de morceau / de réglage
	local function onTrackChanged()
		if not ctx.IsAlive() then
			return
		end
		refreshSubtitle()
		title.TextTransparency = 1
		UI.Tween(title, 0.4, { TextTransparency = 0 })
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

	ctx.Connect(skip.Activated, function()
		if not ctx.IsAlive() or type(Sound.NextTrack) ~= "function" then
			return
		end
		local ok, changed = pcall(Sound.NextTrack)
		if ok and changed then
			S.discSpin = 12 -- petit coup de vinyle
		end
	end)

	-- Horloge à aiguilles : heure locale du joueur
	local function refreshClock()
		-- Roblox : os.date ne gère que "*t" / "!*t" (heure locale du joueur)
		local now = os.date("*t")
		if type(now) == "table" and now.hour and now.min then
			minuteHand.Rotation = now.min * 6
			hourHand.Rotation = (now.hour % 12) * 30 + now.min * 0.5
		end
	end
	refreshClock()

	-- Disques sur l'étagère (amélioration "Vinyl")
	local function refreshRecords()
		local level = tonumber(ctx.GetLevel("Vinyl")) or 0
		if level == S.shownRecords then
			return
		end
		S.shownRecords = level
		local count = math.clamp(2 + level, 2, MAX_RECORDS)
		for i, record in ipairs(records) do
			record.Visible = i <= count
		end
		extraSleeve.Visible = level >= 5
		goldRecord.Visible = level >= 10
	end
	refreshRecords()
	ctx.Connect(ctx.State.Changed, refreshRecords)

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

	------------------------------------------------------------------
	-- Animation (une seule boucle de rendu)
	------------------------------------------------------------------
	local rainDX = math.tan(RAIN_ANGLE)
	local LINE_TIME, PAUSE_TIME = 2.2, 0.9
	local CYCLE = LINE_TIME * 2 + PAUSE_TIME

	-- Chaque seconde : spectateurs, sous-titre, horloge, fenêtres de la ville
	local function everySecond()
		S.tick += 1
		S.viewers = math.clamp(S.viewers + random:NextInteger(-40, 55), 3000, 99999)
		if S.tick % 6 == 0 then
			S.showAlt = not S.showAlt
			if S.showAlt and random:NextNumber() < 0.5 then
				S.trackIndex = S.trackIndex % #tracks + 1
			end
			subtitle.TextTransparency = 1
			UI.Tween(subtitle, 0.4, { TextTransparency = 0 })
		end
		refreshSubtitle()
		if S.tick % 10 == 0 then
			refreshClock()
			applyCompact()
		end
		-- Une fenêtre de la ville s'allume / s'éteint de temps en temps
		if #litWindows > 0 and random:NextNumber() < 0.4 then
			local lit = litWindows[random:NextInteger(1, #litWindows)]
			lit.BackgroundTransparency = lit.BackgroundTransparency < 0.5 and 1 or 0.1
		end
	end

	ctx.OnRender(function(rawDt: number)
		local dt = math.min(rawDt, 0.1)
		S.visibilityTimer -= dt
		if S.visibilityTimer <= 0 then
			S.visibilityTimer = 0.5
			S.shown = computeShown()
		end
		if not S.shown then
			return
		end
		S.clock += dt
		local clock = S.clock
		local fx = effectsOn()

		S.secondTimer -= dt
		if S.secondTimer <= 0 then
			S.secondTimer = 1
			everySecond()
		end

		-- Pluie (traits recyclés)
		for _, drop in ipairs(drops) do
			drop.Y += drop.Speed * dt
			drop.X -= drop.Speed * rainDX * dt
			if drop.Y > GLASS_H + 10 or drop.X < -10 then
				drop.Y = random:NextNumber(-24, -6)
				drop.X = random:NextNumber(0, GLASS_W + 30)
			end
			drop.Frame.Position = UDim2.fromOffset(drop.X, drop.Y)
		end

		-- Gouttes sur la vitre (glissent lentement, par à-coups)
		for _, bead in ipairs(beads) do
			local jerk = (math.sin(clock * 2 + bead.X) > 0.6) and 3 or 0.4
			bead.Y += bead.Speed * jerk * dt
			if bead.Y > GLASS_H + 6 then
				bead.Y = -6
				bead.X = random:NextNumber(8, GLASS_W - 8)
			end
			bead.Frame.Position = UDim2.fromOffset(bead.X, bead.Y)
		end

		-- Nuages qui dérivent
		for _, cloud in ipairs(clouds) do
			cloud.X += cloud.Speed * dt
			if cloud.X > GLASS_W + 4 then
				cloud.X = -48
			end
			cloud.Frame.Position = UDim2.new(0, cloud.X, 0, cloud.Frame.Position.Y.Offset)
		end

		-- Étoiles, lune, guirlande, voyant de la tour
		for _, star in ipairs(stars) do
			star.Frame.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(clock * star.Speed + star.Phase))
		end
		moonGlow.BackgroundTransparency = 0.82 + 0.06 * math.sin(clock * 0.8)
		towerLight.BackgroundTransparency = (clock % 1.6) < 0.5 and 0 or 0.85
		for _, light in ipairs(fairy) do
			local twinkle = 0.5 + 0.5 * math.sin(clock * 2.2 + light.Phase)
			light.Frame.BackgroundTransparency = 0.05 + (1 - twinkle) * 0.35
			light.Glow.Transparency = 0.45 + (1 - twinkle) * 0.5
		end

		-- Étoile filante et éclair lointain, de temps en temps
		S.nextStar -= dt
		if S.nextStar <= 0 then
			S.nextStar = random:NextNumber(10, 22)
			if fx then
				S.starAge = 0
				shootingStar.Visible = true
				shootingStar.Position = UDim2.fromOffset(random:NextNumber(10, GLASS_W * 0.5), random:NextNumber(4, 20))
			end
		end
		if S.starAge >= 0 then
			S.starAge += dt
			local p = S.starAge / 0.7
			if p >= 1 then
				S.starAge = -1
				shootingStar.Visible = false
			else
				local position = shootingStar.Position
				shootingStar.Position = UDim2.fromOffset(position.X.Offset + 110 * dt, position.Y.Offset + 110 * dt * math.tan(math.rad(18)))
				shootingStar.BackgroundTransparency = p * p
			end
		end
		S.nextFlash -= dt
		if S.nextFlash <= 0 then
			S.nextFlash = random:NextNumber(20, 45)
			if fx then
				S.flash = 1
			end
		end
		if S.flash > 0 then
			S.flash = math.max(0, S.flash - dt * 3)
			local flicker = (S.flash > 0.6 and S.flash < 0.8) and 0.2 or S.flash
			lightning.BackgroundTransparency = 1 - flicker * 0.55
		end

		-- Lueur de la lampe qui "respire" (+ petit grésillement rare)
		local breath = 0.5 + 0.5 * math.sin(clock * 1.2)
		local flicker = (math.sin(clock * 37) > 0.985) and 0.06 or 0
		for i, glow in ipairs(glows) do
			glow.BackgroundTransparency = math.min(1, GLOW_ALPHA[i] + (1 - breath) * 0.05 + flicker)
		end
		bulb.BackgroundTransparency = flicker * 4

		-- Chat : respiration, queue qui ondule, "z z z"
		bodyScale.Scale = 1 + 0.04 * (0.5 + 0.5 * math.sin(clock * 1.6))
		tail.Rotation = -18 + math.sin(clock * 0.9) * 10
		for i, z in ipairs(zLabels) do
			local p = ((clock / 3.3) + (i - 1) / 3) % 1
			z.Position = UDim2.fromOffset(headX + 8 + p * 22 + math.sin(p * 6) * 3, headY - 12 - p * 40)
			z.TextSize = 9 + p * 9
			z.TextTransparency = p < 0.12 and (1 - p / 0.12) or (p * p)
		end

		-- Musique : volume réel (si elle joue) → visualiseur + intensité du hochement
		local _, music = currentMusic()
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

		-- Personnage : la tête hoche en rythme et se balance doucement
		local nod = math.sin(beatPhase * math.pi)
		local headOffset = nod * (1.5 + S.grooveLevel * 2.5)
		local headNowY = HEAD_Y + headOffset
		headHolder.Position = UDim2.fromOffset(PX, headNowY)
		headHolder.Rotation = math.sin(clock * math.pi / BEAT) * (2 + S.grooveLevel * 2.5)
		local breathe = math.sin(clock * 1.4)
		torso.Position = UDim2.fromOffset(PX, 140 + nod * 0.8 + breathe * 0.4)
		collar.Position = UDim2.fromOffset(PX, 110 + headOffset * 0.5)
		neck.Position = UDim2.fromOffset(PX, 104 + headOffset * 0.5)

		-- Casque lumineux : halo qui pulse sur la musique
		for _, glow in ipairs(phoneGlows) do
			glow.BackgroundTransparency = 0.82 - pulse * 0.3
			glow.Size = UDim2.fromOffset(38 + pulse * 8, 38 + pulse * 8)
		end

		-- Écriture : le crayon avance sur la ligne, 2 lignes, pause, et
		-- toutes les 3 pages la feuille se tourne
		local previous = S.writeTime
		S.writeTime = (S.writeTime + dt) % CYCLE
		if S.writeTime < previous then
			S.linesWritten += 1
			if S.linesWritten % 3 == 0 then
				S.pageFlip = 0
			end
		end
		local lineIndex, progressLine, lifted
		if S.writeTime < LINE_TIME then
			lineIndex, progressLine, lifted = 1, S.writeTime / LINE_TIME, false
		elseif S.writeTime < LINE_TIME * 2 then
			lineIndex, progressLine, lifted = 2, (S.writeTime - LINE_TIME) / LINE_TIME, false
		else
			lineIndex, progressLine, lifted = 1, 0, true
		end
		if S.pageFlip >= 0 then
			-- La feuille passe de la page de droite à la page de gauche
			S.pageFlip += dt / 0.6
			local p = S.pageFlip
			if p >= 1 then
				S.pageFlip = -1
				turningPage.Visible = false
			else
				turningPage.Visible = true
				local width = math.abs(math.cos(p * math.pi)) * (NOTE_W / 2)
				turningPage.AnchorPoint = Vector2.new(p < 0.5 and 0 or 1, 0.5)
				turningPage.Size = UDim2.fromOffset(width, NOTE_H + 2 - math.sin(p * math.pi) * 3)
				turningPage.Position = UDim2.fromOffset(NOTE_W / 2, NOTE_H / 2 - math.sin(p * math.pi) * 2)
			end
			lifted = true
		end
		if lifted then
			-- Pause : on relit ses notes (lignes pleines), crayon levé
			local full = S.pageFlip < 0 or S.pageFlip < 0.5
			writeLines[1].Size = UDim2.fromOffset(full and WRITE_W or 0, 1.5)
			writeLines[2].Size = UDim2.fromOffset(full and WRITE_W or 0, 1.5)
		else
			writeLines[1].Size = UDim2.fromOffset(lineIndex == 1 and WRITE_W * progressLine or WRITE_W, 1.5)
			writeLines[2].Size = UDim2.fromOffset(lineIndex == 2 and WRITE_W * progressLine or 0, 1.5)
		end
		local scribble = lifted and 0 or 1
		local tipX = noteLeft + WRITE_X + (lifted and WRITE_W * 0.5 or WRITE_W * progressLine) + math.sin(clock * 14) * 0.8 * scribble
		local tipY = noteTop + 3.75 + (lineIndex - 1) * 4.5 + math.sin(clock * 26) * 0.9 * scribble - (lifted and 4 or 0)
		setLimb(pencil, tipX, tipY, tipX + 9, tipY - 16, 3.5)
		local handX, handY = tipX + 4, tipY - 6
		rightHand.Position = UDim2.fromOffset(handX, handY)
		setLimb(rightFore, R_ELBOW.X, R_ELBOW.Y, handX + 3, handY, 15)

		-- Notes de musique : du casque sur certains temps, de la platine parfois
		if onBeat and fx then
			if playing or beatNow % 2 == 0 then
				spawnNote(PX + S.nextNoteSide * 36, headNowY + 2, S.nextNoteSide, 58)
				S.nextNoteSide = -S.nextNoteSide
			end
			if beatNow % 4 == 1 then
				spawnNote(TURNTABLE_X + 6, ITEM_BASE - 22, 1, 44)
			end
		end
		for _, n in ipairs(notes) do
			if n.Active then
				n.Age += dt
				local p = n.Age / NOTE_LIFE
				if p >= 1 or not fx then
					n.Active = false
					n.Label.Visible = false
				else
					local label = n.Label
					label.Position = UDim2.fromOffset(n.X + n.Dir * p * 30 + math.sin(p * 9) * 4, n.Y - p * n.Rise)
					label.Rotation = math.sin(p * 8) * 18
					label.TextSize = 12 + math.min(1, p * 5) * 6
					local alpha = p < 0.12 and (1 - p / 0.12) or math.max(0, (p - 0.55) / 0.45)
					label.TextTransparency = alpha
					label.TextStrokeTransparency = 0.5 + alpha * 0.5
				end
			end
		end

		-- Vapeur du café
		for i, puff in ipairs(steam) do
			if fx then
				local p = ((clock / 2.2) + (i - 1) / 3) % 1
				puff.Position = UDim2.fromOffset(mugX + math.sin(p * 7 + i) * 4, ITEM_BASE - 24 - p * 26)
				puff.Size = UDim2.fromOffset(4 + p * 7, 4 + p * 7)
				puff.BackgroundTransparency = 0.45 + p * 0.55
			elseif puff.BackgroundTransparency < 1 then
				puff.BackgroundTransparency = 1
			end
		end

		-- Visualiseur : piloté par le volume réel de la musique si elle
		-- joue, sinon animé tout seul (basses sur le temps)
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
			S.discSpin += (0.8 - S.discSpin) * math.min(1, dt * 2)
		end
		local k = math.min(1, dt * 16)
		for i, eqBar in ipairs(eqBars) do
			eqHeights[i] += (eqTargets[i] - eqHeights[i]) * k
			local h = 3 + eqHeights[i] * (EQ_H - 5)
			eqBar.Size = UDim2.fromOffset(barWidth, math.floor(h))
			-- Pic : monte avec la barre, retombe doucement
			peakHeights[i] = math.max(h + 2, peakHeights[i] - dt * 14)
			eqPeaks[i].Position = UDim2.new(0, (i - 1) * (barWidth + barGap), 1, -math.floor(peakHeights[i]))
		end

		-- Vinyles (barre + platine) et progression du morceau
		S.discAngle = (S.discAngle + S.discSpin * 60 * dt) % 360
		disc.Rotation = S.discAngle
		platterSpin.Offset = Vector2.new(math.sin(math.rad(S.discAngle)) * 0.35, 0)
		recordLabel.Position = UDim2.fromOffset(26 + math.sin(math.rad(S.discAngle)) * 0.8, 6)
		ttLed.BackgroundTransparency = playing and 0 or (0.3 + 0.3 * math.sin(clock * 2))
		-- Bras de lecture : posé sur le disque quand la musique joue, sinon relevé
		S.armLift += ((playing and 1 or 0) - S.armLift) * math.min(1, dt * 3)
		tonearm.Rotation = tonearmRest - (1 - S.armLift) * 16
		local ratio: number
		local length = playing and music and tonumber(music.TimeLength) or 0
		if playing and music and length and length > 0 then
			ratio = math.clamp((tonumber(music.TimePosition) or 0) / length, 0, 1)
		else
			S.fakeProgress = (S.fakeProgress + dt / 150) % 1
			ratio = S.fakeProgress
		end
		progressFill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.fromScale(ratio, 0.5)
	end)
end

return Lofi
