--[[
	Lofi (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Lofi

	Petite chambre "lofi" la nuit (slot R3, 384x268), entièrement illustrée
	en code (Frames, UICorner, UIGradient, UIStroke — aucun emoji pour le
	personnage) :
	  - une fenêtre avec ciel étoilé, lune, ville au loin (fenêtres qui
	    s'allument), pluie qui tombe et gouttes sur la vitre, une guirlande
	    lumineuse qui scintille, un chat qui dort (et respire) sur le rebord ;
	  - le personnage : cheveux (frange, mèches, épi), visage aux yeux
	    fermés, joues roses, sweat à capuche, GROS casque rose lumineux
	    (halo qui pulse sur le rythme), la tête qui hoche en rythme, les
	    bras posés sur le bureau : il écrit dans son cahier (le crayon
	    avance, les lignes se remplissent) ;
	  - des notes de musique ♪ ♫ qui s'échappent du casque sur les temps ;
	  - une tasse fumante, des livres, une lampe dont la lueur respire,
	    une horloge (heure réelle) et un post-it ;
	  - en bas, la barre "lecteur" :
	      · un vinyle qui tourne, le morceau en cours (vraie musique de
	        Config.Music, jouée par SoundManager) ou "lofi beats pour
	        réviser", le nombre de personnes qui "révisent" ;
	      · un bouton ⏭ (morceau suivant : SoundManager.NextTrack) ;
	      · un égaliseur piloté par le volume réel du morceau
	        (Sound.PlaybackLoudness), ou animé tout seul sans musique.
	Si la playlist est vide : dans Studio, un rappel "Ajoute une musique
	dans Config.Music" ; en jeu, simplement la petite chambre.
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
local ITEM_BASE = 158 -- les objets "posés" sur le plateau
local WINDOW_X, WINDOW_Y, WINDOW_W, WINDOW_H = 12, 12, 164, 108
local GLASS_W, GLASS_H = WINDOW_W - 12, WINDOW_H - 12
local SILL_Y = WINDOW_Y + WINDOW_H - 2
local LAMP_X = 338
local PX = 258 -- centre du personnage
local HEAD_Y = 84 -- centre de la tête
local EQ_BARS = 8
local BEAT = 60 / 78 -- une pulsation (78 BPM, tranquille)
local NOTE_POOL = 4
local NOTE_LIFE = 2.4

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
	UI.Stroke(card, Theme.Colors.CardBorder, 2)

	local scene = frame({
		Name = "Scene",
		Position = UDim2.fromOffset(SCENE_X, SCENE_Y),
		Size = UDim2.fromOffset(SCENE_W, SCENE_H),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Corner(scene, 10)
	gradient(scene, Color3.fromRGB(84, 62, 130), Color3.fromRGB(46, 34, 80))

	------------------------------------------------------------------
	-- Lueur de la lampe (derrière tout le reste du mur)
	------------------------------------------------------------------
	local glows: { Frame } = {}
	local GLOW_SIZES = { 200, 120 }
	local GLOW_ALPHA = { 0.88, 0.8 }
	for i, size in ipairs(GLOW_SIZES) do
		glows[i] = circle(at({
			Name = "LampGlow",
			BackgroundColor3 = Color3.fromRGB(255, 196, 120),
			BackgroundTransparency = GLOW_ALPHA[i],
			ZIndex = 1,
			Parent = scene,
		}, LAMP_X - 6, 112, size, size))
	end

	------------------------------------------------------------------
	-- Fenêtre : ciel, lune, étoiles, ville, pluie
	------------------------------------------------------------------
	local WOOD_LIGHT = Color3.fromRGB(236, 214, 182)
	local windowFrame = frame({
		Name = "Window",
		Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundColor3 = WOOD_LIGHT,
		ZIndex = 2,
		Parent = scene,
	})
	UI.Corner(windowFrame, 6)
	UI.Stroke(windowFrame, Color3.fromRGB(150, 118, 96), 1.5, 0.3)

	local glass = frame({
		Name = "Glass",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(GLASS_W, GLASS_H),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = windowFrame,
	})
	gradient(glass, Color3.fromRGB(16, 20, 62), Color3.fromRGB(96, 66, 146))

	-- Lune
	local moonGlow = circle(at({
		Name = "MoonGlow",
		BackgroundColor3 = Color3.fromRGB(255, 244, 200),
		BackgroundTransparency = 0.82,
		ZIndex = 2,
		Parent = glass,
	}, GLASS_W - 30, 24, 46, 46))
	local moon = circle(at({
		Name = "Moon",
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = glass,
	}, GLASS_W - 30, 24, 24, 24))
	gradient(moon, Color3.fromRGB(255, 250, 222), Color3.fromRGB(236, 224, 180), 45)
	for i, spec in ipairs({ { 8, 9, 6 }, { 15, 15, 4 } }) do
		circle(at({
			Name = "Crater" .. i,
			BackgroundColor3 = Color3.fromRGB(222, 210, 170),
			ZIndex = 3,
			Parent = moon,
		}, spec[1], spec[2], spec[3], spec[3]))
	end

	-- Étoiles qui scintillent
	local stars: { { Frame: Frame, Phase: number, Speed: number } } = {}
	for _ = 1, 5 do
		local size = random:NextInteger(2, 3)
		local star = circle({
			Name = "Star",
			Position = UDim2.fromOffset(random:NextInteger(6, GLASS_W - 60), random:NextInteger(4, 42)),
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
	UI.Create("UIGradient", {
		Transparency = NumberSequence.new(1, 0),
		Parent = shootingStar,
	})

	-- Ville au loin (immeubles + quelques fenêtres allumées)
	local litWindows: { Frame } = {}
	local buildingX = 0
	local BUILDINGS = { { 22, 34 }, { 18, 50 }, { 28, 28 }, { 20, 44 }, { 26, 36 }, { 22, 54 }, { 30, 30 } }
	local LIGHT_COLORS = { Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 170, 210), Color3.fromRGB(150, 230, 255) }
	for _, spec in ipairs(BUILDINGS) do
		local w, h = spec[1], spec[2]
		local building = frame({
			Name = "Building",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset(buildingX, GLASS_H),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = WHITE,
			ZIndex = 3,
			Parent = glass,
		})
		gradient(building, Color3.fromRGB(44, 38, 84), Color3.fromRGB(22, 18, 46))
		if #litWindows < 7 and h >= 34 then
			for _ = 1, 2 do
				local lit = frame({
					Name = "Lit",
					Position = UDim2.fromOffset(random:NextInteger(3, w - 7), random:NextInteger(5, h - 12)),
					Size = UDim2.fromOffset(3, 4),
					BackgroundColor3 = LIGHT_COLORS[random:NextInteger(1, #LIGHT_COLORS)],
					ZIndex = 3,
					Parent = building,
				})
				table.insert(litWindows, lit)
			end
		end
		buildingX += w + 1
		if buildingX >= GLASS_W then
			break
		end
	end

	-- Pluie : réserve de traits recyclés (aucune création par image)
	local RAIN_ANGLE = math.rad(12)
	local RAIN_SPEED = 230
	local rainCount = effectsOn() and 16 or 8
	local drops: { { Frame: Frame, X: number, Y: number, Speed: number } } = {}
	for _ = 1, rainCount do
		local length = random:NextInteger(8, 14)
		local drop = frame({
			Name = "Rain",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(1.5, length),
			BackgroundColor3 = RAIN_COLOR,
			BackgroundTransparency = random:NextNumber(0.25, 0.55),
			Rotation = 12,
			ZIndex = 4,
			Parent = glass,
		})
		table.insert(drops, {
			Frame = drop,
			X = random:NextNumber(0, GLASS_W + 30),
			Y = random:NextNumber(-20, GLASS_H),
			Speed = RAIN_SPEED * random:NextNumber(0.8, 1.2),
		})
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
			ZIndex = 5,
			Parent = glass,
		})
		table.insert(beads, {
			Frame = bead,
			X = random:NextNumber(8, GLASS_W - 8),
			Y = random:NextNumber(0, GLASS_H),
			Speed = random:NextNumber(6, 16),
		})
	end

	-- Croisillons de la fenêtre (au-dessus de la vitre)
	frame({
		Name = "MullionV",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 5, 1, 0),
		BackgroundColor3 = WOOD_LIGHT,
		ZIndex = 6,
		Parent = windowFrame,
	})
	frame({
		Name = "MullionH",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = WOOD_LIGHT,
		ZIndex = 6,
		Parent = windowFrame,
	})

	-- Rebord
	local sill = frame({
		Name = "Sill",
		Position = UDim2.fromOffset(WINDOW_X - 6, SILL_Y),
		Size = UDim2.fromOffset(WINDOW_W + 12, 8),
		BackgroundColor3 = WHITE,
		ZIndex = 7,
		Parent = scene,
	})
	UI.Corner(sill, 3)
	gradient(sill, Color3.fromRGB(226, 198, 160), Color3.fromRGB(176, 144, 110))

	------------------------------------------------------------------
	-- Guirlande lumineuse au-dessus de la fenêtre
	------------------------------------------------------------------
	frame({
		Name = "Wire",
		Position = UDim2.fromOffset(WINDOW_X - 2, WINDOW_Y + 2),
		Size = UDim2.fromOffset(WINDOW_W + 4, 1.5),
		BackgroundColor3 = Color3.fromRGB(40, 30, 50),
		BackgroundTransparency = 0.2,
		ZIndex = 8,
		Parent = scene,
	})
	local FAIRY_COLORS = {
		Color3.fromRGB(255, 220, 110),
		Color3.fromRGB(255, 140, 200),
		Color3.fromRGB(120, 230, 255),
		Color3.fromRGB(255, 170, 90),
		Color3.fromRGB(190, 160, 255),
		Color3.fromRGB(140, 240, 170),
	}
	local fairy: { { Frame: Frame, Glow: UIStroke, Phase: number } } = {}
	for i, color in ipairs(FAIRY_COLORS) do
		local u = (i - 0.5) / #FAIRY_COLORS
		local bulbFrame = circle(at({
			Name = "Fairy" .. i,
			BackgroundColor3 = color,
			ZIndex = 8,
			Parent = scene,
		}, WINDOW_X + u * WINDOW_W, WINDOW_Y + 6 + math.sin(u * math.pi * 3) * 2, 5, 6))
		local glowStroke = UI.Stroke(bulbFrame, color, 2.5, 0.55)
		table.insert(fairy, { Frame = bulbFrame, Glow = glowStroke, Phase = random:NextNumber(0, math.pi * 2) })
	end

	------------------------------------------------------------------
	-- Chat endormi sur le rebord
	------------------------------------------------------------------
	local CAT_COLOR = Color3.fromRGB(248, 182, 104)
	local CAT_DARK = Color3.fromRGB(214, 136, 64)
	local catX, catBottom = WINDOW_X + 16, SILL_Y + 1

	local tail = frame({
		Name = "CatTail",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(catX + 6, catBottom - 6),
		Size = UDim2.fromOffset(28, 7),
		BackgroundColor3 = CAT_DARK,
		ZIndex = 8,
		Parent = scene,
	})
	UI.Corner(tail, UDim.new(1, 0))

	local body = circle({
		Name = "CatBody",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(catX + 30, catBottom),
		Size = UDim2.fromOffset(60, 24),
		BackgroundColor3 = WHITE,
		ZIndex = 9,
		Parent = scene,
	})
	gradient(body, Color3.fromRGB(255, 206, 140), CAT_COLOR)
	local bodyScale = UI.Create("UIScale", { Parent = body })
	for i = 1, 2 do
		frame({
			Name = "Stripe",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(20 + i * 10, 1),
			Size = UDim2.fromOffset(3, 10),
			Rotation = 12,
			BackgroundColor3 = CAT_DARK,
			ZIndex = 9,
			Parent = body,
		})
	end

	local headX, headY = catX + 58, catBottom - 14
	for side = -1, 1, 2 do
		frame(at({
			Name = "CatEar",
			BackgroundColor3 = CAT_DARK,
			Rotation = 45,
			ZIndex = 9,
			Parent = scene,
		}, headX + side * 7, headY - 9, 9, 9))
	end
	local head = circle(at({
		Name = "CatHead",
		BackgroundColor3 = WHITE,
		ZIndex = 10,
		Parent = scene,
	}, headX, headY, 26, 22))
	gradient(head, Color3.fromRGB(255, 206, 140), CAT_COLOR)
	for side = -1, 1, 2 do
		arc(at({ Name = "Eye", ZIndex = 10, Parent = head }, 13 + side * 5, 9, 5, 5), Color3.fromRGB(70, 40, 30), 1.2, LOWER_ARC)
	end
	frame(at({
		Name = "Nose",
		BackgroundColor3 = Color3.fromRGB(255, 130, 150),
		ZIndex = 10,
		Parent = head,
	}, 13, 15, 4, 3))

	-- "z z z" qui montent de la tête du chat (3 lettres recyclées)
	local zLabels: { TextLabel } = {}
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

	------------------------------------------------------------------
	-- Mur : horloge + post-it
	------------------------------------------------------------------
	local clockFrame = frame({
		Name = "Clock",
		Position = UDim2.fromOffset(186, 12),
		Size = UDim2.fromOffset(58, 24),
		BackgroundColor3 = Color3.fromRGB(22, 18, 36),
		ZIndex = 3,
		Parent = scene,
	})
	UI.Corner(clockFrame, 6)
	UI.Stroke(clockFrame, Color3.fromRGB(110, 90, 160), 1.5)
	local clockLabel = UI.Label({
		Text = "--:--",
		Font = Theme.Fonts.Mono,
		TextColor3 = Color3.fromRGB(120, 255, 200),
		Size = UDim2.new(1, -8, 1, -6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = clockFrame,
	})

	local note = frame({
		Name = "PostIt",
		Position = UDim2.fromOffset(302, 10),
		Size = UDim2.fromOffset(56, 40),
		Rotation = 5,
		BackgroundColor3 = WHITE,
		ZIndex = 4,
		Parent = scene,
	})
	gradient(note, Color3.fromRGB(255, 240, 140), Color3.fromRGB(250, 214, 96))
	UI.Stroke(note, Color3.fromRGB(0, 0, 0), 1, 0.8)
	UI.Label({
		Text = Locale.T("<s>study</s>\nclick ✅"),
		RichText = true,
		TextColor3 = Color3.fromRGB(50, 40, 40),
		TextWrapped = true,
		Size = UDim2.new(1, -6, 1, -6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 12,
		ZIndex = 4,
		Parent = note,
	})

	------------------------------------------------------------------
	-- Lampe de bureau (le cône de lumière éclaire le plateau)
	------------------------------------------------------------------
	local cone = frame({
		Name = "LightCone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(LAMP_X - 4, 106),
		Size = UDim2.fromOffset(78, DESK_FRONT - 106),
		BackgroundColor3 = Color3.fromRGB(255, 214, 140),
		ZIndex = 11,
		Parent = scene,
	})
	UI.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.6, 0.92),
		Parent = cone,
	})
	local lampArm = limb({ Name = "LampArm", BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene }, LAMP_X + 14, ITEM_BASE, LAMP_X + 2, 104, 4)
	gradient(lampArm, Color3.fromRGB(96, 96, 116), Color3.fromRGB(52, 52, 64), 0)
	local lampBase = frame(at({
		Name = "LampBase",
		BackgroundColor3 = WHITE,
		ZIndex = 12,
		Parent = scene,
	}, LAMP_X + 14, ITEM_BASE, 28, 6))
	UI.Corner(lampBase, 3)
	gradient(lampBase, Color3.fromRGB(110, 110, 130), Color3.fromRGB(52, 52, 64))
	local shade = frame(at({
		Name = "LampShade",
		BackgroundColor3 = WHITE,
		Rotation = -14,
		ZIndex = 12,
		Parent = scene,
	}, LAMP_X - 2, 102, 40, 18))
	UI.Corner(shade, UDim.new(0.5, 0))
	gradient(shade, Color3.fromRGB(255, 206, 100), Color3.fromRGB(228, 116, 60))
	local bulb = circle({
		Name = "Bulb",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(12, 8),
		BackgroundColor3 = Color3.fromRGB(255, 250, 210),
		ZIndex = 12,
		Parent = shade,
	})

	------------------------------------------------------------------
	-- Le personnage (corps + tête) derrière le bureau
	------------------------------------------------------------------
	local person = frame({
		Name = "Person",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = scene,
	})

	-- Sweat à capuche
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
		local cord = frame(at({
			Name = "String",
			BackgroundColor3 = Color3.fromRGB(245, 245, 255),
			BackgroundTransparency = 0.1,
			ZIndex = 3,
			Parent = torso,
		}, 40 + side * 7, 16, 2, 14))
		UI.Corner(cord, 1)
	end

	-- Tête (support qui hoche : tout ce qui est dedans bouge avec)
	local headHolder = frame(at({
		Name = "Head",
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = person,
	}, PX, HEAD_Y, 80, 80))

	-- Pièce de la tête, centrée sur (x, y) par rapport au centre de la tête
	local function headPart(props: { [string]: any }, x: number, y: number, w: number, h: number): Frame
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.new(0.5, x, 0.5, y)
		props.Size = UDim2.fromOffset(w, h)
		props.Parent = headHolder
		return frame(props)
	end

	-- Halo lumineux des écouteurs (derrière tout)
	local phoneGlows: { Frame } = {}
	for side = -1, 1, 2 do
		local glow = headPart({ Name = "PhoneGlow", BackgroundColor3 = PHONES_GLOW, BackgroundTransparency = 0.78, ZIndex = 1 }, side * 33, 6, 40, 40)
		UI.Corner(glow, UDim.new(1, 0))
		table.insert(phoneGlows, glow)
	end

	-- Cheveux (arrière) + mèches sur les côtés
	local backHair = headPart({ Name = "BackHair", BackgroundColor3 = WHITE, ZIndex = 2 }, 0, -2, 58, 56)
	UI.Corner(backHair, UDim.new(1, 0))
	gradient(backHair, HAIR_LIGHT, HAIR)
	for side = -1, 1, 2 do
		local lock = headPart({ Name = "Lock", BackgroundColor3 = HAIR, ZIndex = 4 }, side * 23, 11, 13, 30)
		UI.Corner(lock, 7)
	end

	-- Visage
	local face = headPart({ Name = "Face", BackgroundColor3 = WHITE, ZIndex = 3 }, 0, 5, 46, 43)
	UI.Corner(face, UDim.new(0.48, 0))
	gradient(face, SKIN, SKIN_SHADE)
	for side = -1, 1, 2 do
		-- Yeux fermés (arc) + petit cil
		local eye = headPart({ Name = "Eye", ZIndex = 5 }, side * 10, 4, 10, 10)
		eye.BackgroundTransparency = 1
		UI.Corner(eye, UDim.new(1, 0))
		local eyeStroke = UI.Stroke(eye, LINE_INK, 2, 0)
		UI.Create("UIGradient", { Rotation = 90, Transparency = LOWER_ARC, Parent = eyeStroke })
		local lash = headPart({ Name = "Lash", BackgroundColor3 = LINE_INK, Rotation = side * 30, ZIndex = 5 }, side * 16.5, 5.5, 4, 1.6)
		UI.Corner(lash, 1)
		-- Joues roses
		local blush = headPart({ Name = "Blush", BackgroundColor3 = Color3.fromRGB(255, 136, 160), BackgroundTransparency = 0.45, ZIndex = 5 }, side * 13, 13, 9, 5)
		UI.Corner(blush, UDim.new(1, 0))
	end
	local nose = headPart({ Name = "Nose", BackgroundColor3 = SKIN_SHADE:Lerp(Color3.fromRGB(200, 120, 110), 0.4), ZIndex = 5 }, 0, 11, 2.5, 2)
	UI.Corner(nose, 1)
	local mouth = headPart({ Name = "Mouth", ZIndex = 5 }, 0, 14, 6, 6)
	mouth.BackgroundTransparency = 1
	UI.Corner(mouth, UDim.new(1, 0))
	local mouthStroke = UI.Stroke(mouth, LINE_INK, 1.5, 0.1)
	UI.Create("UIGradient", { Rotation = 90, Transparency = LOWER_ARC, Parent = mouthStroke })

	-- Frange, reflet, épi
	for _, spec in ipairs({ { -11, -13, 28, 17, -20 }, { 12, -13, 28, 17, 22 }, { 0, -16, 30, 14, 0 } }) do
		local bang = headPart({ Name = "Bang", BackgroundColor3 = WHITE, Rotation = spec[5], ZIndex = 6 }, spec[1], spec[2], spec[3], spec[4])
		UI.Corner(bang, UDim.new(1, 0))
		gradient(bang, HAIR_LIGHT:Lerp(HAIR, 0.45), HAIR)
	end
	local shine = headPart({ Name = "HairShine", BackgroundColor3 = HAIR_LIGHT:Lerp(WHITE, 0.3), BackgroundTransparency = 0.25, Rotation = -18, ZIndex = 7 }, -9, -21, 14, 3.5)
	UI.Corner(shine, UDim.new(1, 0))
	local ahoge = headPart({ Name = "Ahoge", BackgroundColor3 = HAIR, Rotation = 30, ZIndex = 6 }, 5, -31, 3.5, 12)
	UI.Corner(ahoge, UDim.new(1, 0))

	-- GROS casque : arceau (haut d'un cercle) + deux écouteurs vernis
	local band = headPart({ Name = "Band", BackgroundTransparency = 1, ZIndex = 7 }, 0, 4, 64, 64)
	UI.Corner(band, UDim.new(1, 0))
	local bandStroke = UI.Stroke(band, WHITE, 6, 0)
	UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(PHONES:Lerp(WHITE, 0.3), PHONES_DARK),
		Transparency = UPPER_ARC,
		Parent = bandStroke,
	})

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
	end

	------------------------------------------------------------------
	-- Bureau
	------------------------------------------------------------------
	local deskTop = frame({
		Name = "DeskTop",
		Position = UDim2.fromOffset(0, DESK_Y),
		Size = UDim2.new(1, 0, 0, DESK_FRONT - DESK_Y),
		BackgroundColor3 = WHITE,
		ZIndex = 10,
		Parent = scene,
	})
	UI.Gradient(deskTop, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 104, 76)),
		ColorSequenceKeypoint.new(0.85, Color3.fromRGB(186, 134, 96)),
		ColorSequenceKeypoint.new(0.9, Color3.fromRGB(214, 164, 118)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 164, 118)),
	}), 90)
	local deskFront = frame({
		Name = "DeskFront",
		Position = UDim2.fromOffset(0, DESK_FRONT),
		Size = UDim2.new(1, 0, 0, SCENE_H - DESK_FRONT),
		BackgroundColor3 = WHITE,
		ZIndex = 10,
		Parent = scene,
	})
	gradient(deskFront, Color3.fromRGB(116, 76, 56), Color3.fromRGB(78, 50, 40))

	-- Pile de livres
	for i, spec in ipairs({
		{ 40, 42, 7, Color3.fromRGB(96, 150, 230) },
		{ 42, 36, 6, Color3.fromRGB(240, 110, 120) },
		{ 39, 40, 7, Color3.fromRGB(250, 200, 90) },
	}) do
		local book = frame(at({
			Name = "Book" .. i,
			BackgroundColor3 = WHITE,
			ZIndex = 12,
			Parent = scene,
		}, spec[1], ITEM_BASE - 3 - (i - 1) * 6.5, spec[2], spec[3]))
		UI.Corner(book, 2)
		gradient(book, spec[4]:Lerp(WHITE, 0.2), spec[4]:Lerp(Color3.new(0, 0, 0), 0.2))
		UI.Stroke(book, Color3.fromRGB(40, 24, 30), 1, 0.5)
	end

	-- Tasse fumante
	local mugX = 178
	local mug = frame(at({ Name = "Mug", BackgroundColor3 = WHITE, ZIndex = 12, Parent = scene }, mugX, ITEM_BASE - 9, 16, 18))
	UI.Corner(mug, 4)
	gradient(mug, Color3.fromRGB(255, 250, 240), Color3.fromRGB(214, 206, 196), 0)
	frame(at({ Name = "Stripe", BackgroundColor3 = PHONES, ZIndex = 12, Parent = mug }, 8, 10, 16, 3))
	local handle = circle(at({ Name = "Handle", BackgroundTransparency = 1, ZIndex = 11, Parent = scene }, mugX + 9, ITEM_BASE - 9, 9, 9))
	UI.Stroke(handle, Color3.fromRGB(226, 218, 208), 2.5, 0)
	circle(at({ Name = "Coffee", BackgroundColor3 = Color3.fromRGB(110, 66, 44), ZIndex = 13, Parent = scene }, mugX, ITEM_BASE - 17, 13, 4))
	local steam: { Frame } = {}
	for i = 1, 3 do
		steam[i] = circle({
			Name = "Steam",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(5, 5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			ZIndex = 12,
			Parent = scene,
		})
	end

	------------------------------------------------------------------
	-- Mains sur le bureau : cahier, bras, crayon (devant le bureau)
	------------------------------------------------------------------
	local hands = frame({
		Name = "Hands",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 12,
		Parent = scene,
	})

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
		frame({
			Name = "Written" .. i,
			Position = UDim2.fromOffset(5, 3 + (i - 1) * 4.5),
			Size = UDim2.fromOffset(i == 1 and 24 or 17, 1.5),
			BackgroundColor3 = LINE_INK,
			BackgroundTransparency = 0.45,
			ZIndex = 2,
			Parent = notebook,
		})
	end
	local WRITE_X, WRITE_W = 37, 24 -- zone d'écriture (page de droite)
	local writeLines: { Frame } = {}
	for i = 1, 2 do
		writeLines[i] = frame({
			Name = "Writing" .. i,
			Position = UDim2.fromOffset(WRITE_X, 3 + (i - 1) * 4.5),
			Size = UDim2.fromOffset(0, 1.5),
			BackgroundColor3 = LINE_INK,
			BackgroundTransparency = 0.2,
			ZIndex = 2,
			Parent = notebook,
		})
	end

	-- Manches du sweat (dégradé le long du bras, poignet plus foncé)
	local SLEEVE = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOODIE),
		ColorSequenceKeypoint.new(0.8, HOODIE:Lerp(HOODIE_DARK, 0.3)),
		ColorSequenceKeypoint.new(0.82, HOODIE_DARK),
		ColorSequenceKeypoint.new(1, HOODIE_DARK),
	})
	local UPPER = ColorSequence.new(HOODIE:Lerp(WHITE, 0.12), HOODIE_DARK)

	local L_SHOULDER, L_ELBOW, L_WRIST = Vector2.new(PX - 32, 118), Vector2.new(PX - 48, 150), Vector2.new(PX - 20, 157)
	local R_SHOULDER, R_ELBOW = Vector2.new(PX + 32, 118), Vector2.new(PX + 50, 150)

	local leftUpper = limb({ Name = "LeftUpperArm", BackgroundColor3 = WHITE, ZIndex = 3, Parent = hands }, L_SHOULDER.X, L_SHOULDER.Y, L_ELBOW.X, L_ELBOW.Y, 17)
	UI.Gradient(leftUpper, UPPER, 0)
	local leftFore = limb({ Name = "LeftForearm", BackgroundColor3 = WHITE, ZIndex = 3, Parent = hands }, L_ELBOW.X, L_ELBOW.Y, L_WRIST.X, L_WRIST.Y, 15)
	UI.Gradient(leftFore, SLEEVE, 90)
	local leftHand = circle(at({ Name = "LeftHand", BackgroundColor3 = WHITE, ZIndex = 5, Parent = hands }, L_WRIST.X + 5, L_WRIST.Y, 11, 10))
	gradient(leftHand, SKIN, SKIN_SHADE)

	local rightUpper = limb({ Name = "RightUpperArm", BackgroundColor3 = WHITE, ZIndex = 3, Parent = hands }, R_SHOULDER.X, R_SHOULDER.Y, R_ELBOW.X, R_ELBOW.Y, 17)
	UI.Gradient(rightUpper, UPPER, 180)
	local rightFore = limb({ Name = "RightForearm", BackgroundColor3 = WHITE, ZIndex = 3, Parent = hands }, R_ELBOW.X, R_ELBOW.Y, PX + 20, 152, 15)
	UI.Gradient(rightFore, SLEEVE, 90)
	local pencil = limb({ Name = "Pencil", BackgroundColor3 = WHITE, ZIndex = 4, Parent = hands }, PX + 10, 155, PX + 19, 139, 3.5)
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
	local rightHand = circle(at({ Name = "RightHand", BackgroundColor3 = WHITE, ZIndex = 5, Parent = hands }, PX + 14, 150, 11, 10))
	gradient(rightHand, SKIN, SKIN_SHADE)

	------------------------------------------------------------------
	-- Notes de musique qui s'échappent du casque (recyclées)
	------------------------------------------------------------------
	local notes: { { Label: TextLabel, Active: boolean, Age: number, X: number, Y: number, Dir: number } } = {}
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
		table.insert(notes, { Label = label, Active = false, Age = 0, X = 0, Y = 0, Dir = 1 })
	end
	local nextNoteSide = 1
	local noteColorIndex = 0

	local function spawnNote(centerX: number, headYNow: number)
		for _, n in ipairs(notes) do
			if not n.Active then
				n.Active = true
				n.Age = 0
				n.Dir = nextNoteSide
				n.X = centerX + nextNoteSide * 36
				n.Y = headYNow + 2
				nextNoteSide = -nextNoteSide
				noteColorIndex = noteColorIndex % #NOTE_COLORS + 1
				n.Label.TextColor3 = NOTE_COLORS[noteColorIndex]
				n.Label.Text = random:NextNumber() < 0.5 and "♪" or "♫"
				n.Label.Visible = true
				return
			end
		end
	end

	------------------------------------------------------------------
	-- Barre du bas : lecteur (vinyle, morceau, spectateurs, ⏭, égaliseur)
	------------------------------------------------------------------
	local Sound = ctx.Sound
	local isStudio = RunService:IsStudio()

	local bar = frame({
		Name = "Bar",
		Position = UDim2.fromOffset(SCENE_X, BAR_Y),
		Size = UDim2.fromOffset(SCENE_W, BAR_H),
		BackgroundColor3 = WHITE,
		Parent = card,
	})
	UI.Corner(bar, 10)
	gradient(bar, Color3.fromRGB(40, 32, 70), Color3.fromRGB(18, 14, 32))
	UI.Stroke(bar, Color3.fromRGB(110, 86, 170), 1, 0.45)

	-- Vinyle qui tourne pendant la musique
	local disc = circle({
		Name = "Vinyl",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(22, BAR_H / 2),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Color3.fromRGB(28, 26, 34),
		Parent = bar,
	})
	UI.Stroke(disc, Color3.fromRGB(70, 64, 90), 1.5)
	local groove = circle({
		Name = "Groove",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(21, 21),
		BackgroundTransparency = 1,
		Parent = disc,
	})
	UI.Stroke(groove, Color3.fromRGB(64, 60, 82), 1)
	local labelDisc = circle({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(11, 11),
		BackgroundColor3 = WHITE,
		Parent = disc,
	})
	UI.Gradient(labelDisc, ColorSequence.new(EQ_LOW, EQ_HIGH), 0)
	frame({
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -6),
		Size = UDim2.fromOffset(2, 7),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		Parent = disc,
	})

	local title = UI.Create("TextLabel", {
		Name = "Title",
		Text = Locale.T("lofi beats 🎧 to study to"),
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(44, 4),
		Size = UDim2.fromOffset(190, 18),
		Parent = bar,
	})
	local subtitle = UI.Create("TextLabel", {
		Name = "Subtitle",
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(200, 186, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(44, 22),
		Size = UDim2.fromOffset(190, 15),
		Parent = bar,
	})

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

	-- Égaliseur
	local eqWidth = 70
	local eq = frame({
		Name = "Equalizer",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(eqWidth, 28),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	local barWidth = 6
	local barGap = (eqWidth - EQ_BARS * barWidth) / (EQ_BARS - 1)
	local eqBars: { Frame } = {}
	local eqHeights: { number } = {}
	local eqTargets: { number } = {}
	for i = 1, EQ_BARS do
		local t = (i - 1) / (EQ_BARS - 1)
		local eqBar = frame({
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, (i - 1) * (barWidth + barGap), 1, 0),
			Size = UDim2.fromOffset(barWidth, 4),
			BackgroundColor3 = EQ_LOW:Lerp(EQ_HIGH, t),
			Parent = eq,
		})
		UI.Corner(eqBar, 2)
		eqBars[i] = eqBar
		eqHeights[i] = 0.2
		eqTargets[i] = 0.2
	end

	------------------------------------------------------------------
	-- État du lecteur : vraie musique, musique coupée, ou pas de musique
	------------------------------------------------------------------
	local viewers = random:NextInteger(8000, 14000)
	local tracks = Locale.Pick(TRACKS)
	local trackIndex = random:NextInteger(1, #tracks)
	local showAlt = false -- alterne les deux textes du sous-titre
	local discSpin = 0 -- vitesse de rotation du vinyle (lissée)

	local function hasPlaylist(): boolean
		return type(Sound.HasPlaylist) == "function" and Sound.HasPlaylist()
	end

	-- (nom du morceau, Sound) si de la vraie musique joue, sinon nil
	local function currentMusic(): (string?, Sound?)
		if type(Sound.GetCurrentTrack) ~= "function" or type(Sound.IsMusicPlaying) ~= "function" then
			return nil, nil
		end
		if not Sound.IsMusicPlaying() then
			return nil, nil
		end
		return Sound.GetCurrentTrack()
	end

	local function viewersText(): string
		local text = viewers >= 1e6 and Format.Format(viewers) or Format.WithSpaces(viewers)
		return "🔴 " .. Locale.T("%s people studying (or not)", text)
	end

	local function refreshSubtitle()
		local name = currentMusic()
		local playlist = hasPlaylist()
		skip.Visible = name ~= nil
		eq.Position = name and UDim2.new(1, -44, 0.5, 0) or UDim2.new(1, -10, 0.5, 0)
		-- Textes : toute la place jusqu'à l'égaliseur
		local textWidth = name and 204 or 238
		title.Size = UDim2.fromOffset(textWidth, 18)
		subtitle.Size = UDim2.fromOffset(textWidth, 15)
		subtitle.TextColor3 = Color3.fromRGB(200, 186, 240)

		if name then
			-- Vraie musique
			title.Text = "♫ " .. Locale.T(name)
			subtitle.Text = showAlt and Locale.T("lofi beats 🎧 to study to") or viewersText()
		elseif playlist then
			-- Musique disponible mais coupée (réglage) ou en chargement
			title.Text = Locale.T("lofi beats 🎧 to study to")
			local musicOn = type(Sound.IsMusicEnabled) ~= "function" or Sound.IsMusicEnabled()
			if showAlt then
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
			subtitle.Text = showAlt and ("♫ " .. tracks[trackIndex]) or viewersText()
		end
	end
	refreshSubtitle()

	-- Réagit tout de suite aux changements de morceau / de réglage
	if Sound.TrackChanged then
		ctx.Connect(Sound.TrackChanged, function()
			if not ctx.IsAlive() then
				return
			end
			refreshSubtitle()
			title.TextTransparency = 1
			UI.Tween(title, 0.4, { TextTransparency = 0 })
		end)
	end
	if Sound.MusicStateChanged then
		ctx.Connect(Sound.MusicStateChanged, function()
			if ctx.IsAlive() then
				refreshSubtitle()
			end
		end)
	end

	ctx.Connect(skip.Activated, function()
		if not ctx.IsAlive() then
			return
		end
		if type(Sound.NextTrack) == "function" and Sound.NextTrack() then
			discSpin = 12 -- petit coup de vinyle
		end
	end)

	local function refreshClock()
		-- Roblox : os.date ne gère que "*t" / "!*t" (heure locale du joueur)
		local now = os.date("*t")
		if type(now) == "table" and now.hour and now.min then
			clockLabel.Text = string.format("%02d:%02d", now.hour, now.min)
		end
	end
	refreshClock()

	task.spawn(function()
		local tick = 0
		while ctx.IsAlive() do
			task.wait(1)
			if not ctx.IsAlive() then
				break
			end
			tick += 1
			-- Spectateurs : petite marche aléatoire
			viewers = math.clamp(viewers + random:NextInteger(-40, 55), 3000, 99999)
			if tick % 6 == 0 then
				showAlt = not showAlt
				if showAlt and random:NextNumber() < 0.5 then
					trackIndex = trackIndex % #tracks + 1
				end
				subtitle.TextTransparency = 1
				UI.Tween(subtitle, 0.4, { TextTransparency = 0 })
			end
			refreshSubtitle()
			if tick % 10 == 0 then
				refreshClock()
			end
			-- Une fenêtre de la ville s'allume / s'éteint de temps en temps
			if #litWindows > 0 and random:NextNumber() < 0.25 then
				local lit = litWindows[random:NextInteger(1, #litWindows)]
				lit.BackgroundTransparency = lit.BackgroundTransparency < 0.5 and 1 or 0
			end
		end
	end)

	-- Étoile filante de temps en temps
	task.spawn(function()
		while ctx.IsAlive() do
			task.wait(random:NextNumber(10, 22))
			if not ctx.IsAlive() then
				break
			end
			if effectsOn() then
				local startX = random:NextNumber(10, GLASS_W * 0.5)
				shootingStar.Position = UDim2.fromOffset(startX, random:NextNumber(4, 20))
				shootingStar.BackgroundTransparency = 0
				shootingStar.Visible = true
				local travel = random:NextNumber(60, 90)
				UI.Tween(shootingStar, 0.7, {
					Position = UDim2.fromOffset(startX + travel, 4 + travel * math.tan(math.rad(18))),
					BackgroundTransparency = 1,
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.wait(0.75)
				shootingStar.Visible = false
			end
		end
	end)

	------------------------------------------------------------------
	-- Animation (une seule boucle de rendu)
	------------------------------------------------------------------
	local clock = 0
	local eqTimer = 0
	local beatCount = 0
	local lastBeat = 0
	local loudPeak = 40 -- pic de volume récent (PlaybackLoudness)
	local lastLevel = 0
	local grooveLevel = 0 -- intensité "musicale" lissée (0..1) : hochement + halo
	local writeTime = 0
	local rainDX = math.tan(RAIN_ANGLE)
	local LINE_TIME, PAUSE_TIME = 2.2, 0.9
	local CYCLE = LINE_TIME * 2 + PAUSE_TIME

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt
		local fx = effectsOn()

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

		-- Étoiles, lune, guirlande
		for _, star in ipairs(stars) do
			star.Frame.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(clock * star.Speed + star.Phase))
		end
		moonGlow.BackgroundTransparency = 0.8 + 0.06 * math.sin(clock * 0.8)
		for _, light in ipairs(fairy) do
			local twinkle = 0.5 + 0.5 * math.sin(clock * 2.2 + light.Phase)
			light.Frame.BackgroundTransparency = 0.05 + (1 - twinkle) * 0.35
			light.Glow.Transparency = 0.45 + (1 - twinkle) * 0.5
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
			z.Position = UDim2.fromOffset(headX + 8 + p * 22 + math.sin(p * 6) * 3, headY - 12 - p * 44)
			z.TextSize = 9 + p * 9
			z.TextTransparency = p < 0.12 and (1 - p / 0.12) or (p * p)
		end

		-- Musique : volume réel (si elle joue) → égaliseur + intensité du hochement
		local _, music = currentMusic()
		local playing = music ~= nil and music.Parent ~= nil and music.IsPlaying
		local level = 0
		if playing and music then
			-- Pic adaptatif : l'égaliseur reste expressif quel que soit le volume
			local loudness = music.PlaybackLoudness
			loudPeak = math.max(loudness, loudPeak * (1 - math.min(1, dt * 0.35)), 40)
			level = math.clamp(loudness / loudPeak, 0, 1)
		end
		grooveLevel += ((playing and (0.55 + level * 0.45) or 0.45) - grooveLevel) * math.min(1, dt * 4)

		-- Temps (78 BPM) : pulsation qui retombe après chaque temps
		local beatPhase = (clock % BEAT) / BEAT
		local pulse = math.exp(-beatPhase * 5)
		if playing then
			pulse = math.max(pulse * 0.6, level)
		end
		local beatNow = math.floor(clock / BEAT)
		local onBeat = beatNow ~= lastBeat
		lastBeat = beatNow

		-- Personnage : la tête hoche en rythme et se balance doucement
		local nod = math.sin(beatPhase * math.pi)
		local headOffset = nod * (1.5 + grooveLevel * 2.5)
		local headNowY = HEAD_Y + headOffset
		headHolder.Position = UDim2.fromOffset(PX, headNowY)
		headHolder.Rotation = math.sin(clock * math.pi / BEAT) * (2 + grooveLevel * 2.5)
		local breathe = math.sin(clock * 1.4)
		torso.Position = UDim2.fromOffset(PX, 140 + nod * 0.8 + breathe * 0.4)
		collar.Position = UDim2.fromOffset(PX, 110 + headOffset * 0.5)
		neck.Position = UDim2.fromOffset(PX, 104 + headOffset * 0.5)

		-- Casque lumineux : halo + reflet qui pulsent sur la musique
		for _, glow in ipairs(phoneGlows) do
			glow.BackgroundTransparency = 0.82 - pulse * 0.3
			glow.Size = UDim2.fromOffset(38 + pulse * 8, 38 + pulse * 8)
		end

		-- Écriture : le crayon avance sur la ligne, 2 lignes puis nouvelle page
		writeTime = (writeTime + dt) % CYCLE
		local lineIndex, progress, lifted
		if writeTime < LINE_TIME then
			lineIndex, progress, lifted = 1, writeTime / LINE_TIME, false
		elseif writeTime < LINE_TIME * 2 then
			lineIndex, progress, lifted = 2, (writeTime - LINE_TIME) / LINE_TIME, false
		else
			lineIndex, progress, lifted = 1, 0, true
		end
		if lifted then
			-- Pause : on relit ses notes (lignes pleines), crayon levé
			writeLines[1].Size = UDim2.fromOffset(WRITE_W, 1.5)
			writeLines[2].Size = UDim2.fromOffset(WRITE_W, 1.5)
		else
			writeLines[1].Size = UDim2.fromOffset(lineIndex == 1 and WRITE_W * progress or WRITE_W, 1.5)
			writeLines[2].Size = UDim2.fromOffset(lineIndex == 2 and WRITE_W * progress or 0, 1.5)
		end
		local scribble = lifted and 0 or 1
		local tipX = noteLeft + WRITE_X + (lifted and WRITE_W * 0.5 or WRITE_W * progress) + math.sin(clock * 14) * 0.8 * scribble
		local tipY = noteTop + 3.75 + (lineIndex - 1) * 4.5 + math.sin(clock * 26) * 0.9 * scribble - (lifted and 4 or 0)
		setLimb(pencil, tipX, tipY, tipX + 9, tipY - 16, 3.5)
		local handX, handY = tipX + 4, tipY - 6
		rightHand.Position = UDim2.fromOffset(handX, handY)
		setLimb(rightFore, R_ELBOW.X, R_ELBOW.Y, handX + 3, handY, 15)

		-- Notes de musique : une nouvelle sur certains temps, qui s'envole
		if onBeat and fx and (playing or beatNow % 2 == 0) then
			spawnNote(PX, headNowY)
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
					local x = n.X + n.Dir * p * 30 + math.sin(p * 9) * 4
					local y = n.Y - p * 58
					label.Position = UDim2.fromOffset(x, y)
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
			else
				puff.BackgroundTransparency = 1
			end
		end

		-- Égaliseur : piloté par le volume réel de la musique si elle joue,
		-- sinon animé tout seul (basses sur le temps)
		if playing then
			local rising = level > lastLevel + 0.12
			lastLevel = level
			eqTimer -= dt
			if eqTimer <= 0 or rising then
				eqTimer = 0.07
				for i = 1, EQ_BARS do
					local low = 1 - (i - 1) / (EQ_BARS - 1)
					local base = level * (0.35 + random:NextNumber() * 0.5) + level * low * 0.3
					if rising then
						base += low * 0.25
					end
					eqTargets[i] = math.clamp(base, 0.06, 1)
				end
			end
			discSpin += (4 - discSpin) * math.min(1, dt * 3)
		else
			lastLevel = 0
			eqTimer -= dt
			if eqTimer <= 0 then
				eqTimer = 0.11
				local newBeat = math.floor(clock / BEAT)
				local eqBeat = newBeat ~= beatCount
				beatCount = newBeat
				for i = 1, EQ_BARS do
					local low = 1 - (i - 1) / (EQ_BARS - 1)
					local base = 0.15 + random:NextNumber() * 0.55
					if eqBeat then
						base += low * 0.45
					end
					eqTargets[i] = math.clamp(base, 0.1, 1)
				end
			end
			discSpin += (0.6 - discSpin) * math.min(1, dt * 2)
		end
		local k = math.min(1, dt * 16)
		for i, eqBar in ipairs(eqBars) do
			eqHeights[i] += (eqTargets[i] - eqHeights[i]) * k
			eqBar.Size = UDim2.fromOffset(barWidth, math.floor(3 + eqHeights[i] * 25))
		end

		-- Vinyle
		disc.Rotation = (disc.Rotation + discSpin * 60 * dt) % 360
	end)
end

return Lofi
