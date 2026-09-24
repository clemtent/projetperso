--[[
	Lofi (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Lofi

	Petite chambre "lofi" la nuit (slot R3, 384x268), entièrement dessinée
	en code : fenêtre avec ciel étoilé, lune, ville au loin et pluie qui
	tombe, un chat qui dort sur le rebord (avec ses "z z z"), une plante,
	un étudiant avec son casque 🎧 qui hoche la tête en rythme, une tasse
	fumante, une lampe de bureau dont la lueur respire, des post-it, une
	horloge (heure réelle), et en bas une barre "lecteur" :
	  - un vinyle qui tourne, le morceau en cours (vraie musique de
	    Config.Music, jouée par SoundManager) ou "lofi beats 🎧 pour
	    réviser", le nombre de personnes qui "révisent" ;
	  - un bouton ⏭ (morceau suivant : SoundManager.NextTrack) ;
	  - un égaliseur piloté par le volume réel du morceau
	    (Sound.PlaybackLoudness), ou animé tout seul sans musique.
	Si la playlist est vide : dans Studio, un rappel "Ajoute une musique
	dans Config.Music" ; en jeu, simplement la petite chambre.
]]

local RunService = game:GetService("RunService")

local Lofi = {}
Lofi.Slot = "R3"

-- Dimensions (pixels "design")
local SCENE_X, SCENE_Y = 6, 6
local SCENE_W, SCENE_H = 368, 204
local BAR_Y, BAR_H = 214, 42
local DESK_Y = 150 -- dessus du bureau (dans la scène)
local WINDOW_X, WINDOW_Y, WINDOW_W, WINDOW_H = 14, 10, 172, 114
local GLASS_W, GLASS_H = WINDOW_W - 12, WINDOW_H - 12
local SILL_Y = WINDOW_Y + WINDOW_H - 2
local LAMP_X = 330
local PERSON_X = 262
local EQ_BARS = 10
local BEAT = 60 / 78 -- une pulsation (78 BPM, tranquille)

local RAIN_COLOR = Color3.fromRGB(190, 210, 255)
local EQ_LOW = Color3.fromRGB(255, 120, 190)
local EQ_HIGH = Color3.fromRGB(100, 220, 255)

local TRACKS = {
	"pluie_de_minuit.mp3",
	"chat_qui_ronronne.wav",
	"cafe_froid_a_3h.mp3",
	"revisions_infinies.mp3",
	"nuages_en_pyjama.mp3",
	"le_controle_c_est_demain.mp3",
	"flemme_douce.wav",
	"encore_5_minutes.mp3",
}

function Lofi.Start(ctx)
	local UI = ctx.UIUtil
	local Theme = ctx.Theme
	local Format = ctx.Format
	local random = Random.new()

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function frame(props): Frame
		local finalProps = { BorderSizePixel = 0 }
		for key, value in pairs(props) do
			finalProps[key] = value
		end
		return UI.Create("Frame", finalProps)
	end

	local function circle(props): Frame
		local f = frame(props)
		UI.Corner(f, UDim.new(1, 0))
		return f
	end

	local function emoji(text: string, size: number, props): TextLabel
		local finalProps = {
			Text = text,
			TextSize = size,
			Font = Theme.Fonts.Body,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size + 6, size + 6),
		}
		for key, value in pairs(props) do
			finalProps[key] = value
		end
		return UI.Create("TextLabel", finalProps)
	end

	------------------------------------------------------------------
	-- Carte + scène
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
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Corner(scene, 10)
	UI.Gradient(scene, ColorSequence.new(Color3.fromRGB(78, 58, 122), Color3.fromRGB(44, 34, 76)), 90)

	------------------------------------------------------------------
	-- Lueur de la lampe (derrière tout le reste du mur)
	------------------------------------------------------------------
	local glows: { Frame } = {}
	local GLOW_SIZES = { 190, 130, 80 }
	local GLOW_ALPHA = { 0.9, 0.84, 0.76 }
	for i, size in ipairs(GLOW_SIZES) do
		glows[i] = circle({
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(LAMP_X - 6, 112),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(255, 196, 120),
			BackgroundTransparency = GLOW_ALPHA[i],
			ZIndex = 1,
			Parent = scene,
		})
	end

	------------------------------------------------------------------
	-- Fenêtre : ciel, lune, étoiles, ville, pluie
	------------------------------------------------------------------
	local windowFrame = frame({
		Name = "Window",
		Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundColor3 = Color3.fromRGB(236, 214, 182),
		ZIndex = 2,
		Parent = scene,
	})
	UI.Corner(windowFrame, 6)

	local glass = frame({
		Name = "Glass",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(GLASS_W, GLASS_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = windowFrame,
	})
	UI.Gradient(glass, ColorSequence.new(Color3.fromRGB(16, 20, 62), Color3.fromRGB(86, 62, 138)), 90)

	-- Lune
	local moonGlow = circle({
		Name = "MoonGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(GLASS_W - 32, 24),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = Color3.fromRGB(255, 244, 200),
		BackgroundTransparency = 0.82,
		ZIndex = 2,
		Parent = glass,
	})
	local moon = circle({
		Name = "Moon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = moonGlow.Position,
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.fromRGB(252, 244, 206),
		ZIndex = 3,
		Parent = glass,
	})
	circle({
		Name = "Crater",
		Position = UDim2.fromOffset(5, 6),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.fromRGB(226, 216, 176),
		ZIndex = 3,
		Parent = moon,
	})
	circle({
		Name = "Crater",
		Position = UDim2.fromOffset(13, 13),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.fromRGB(226, 216, 176),
		ZIndex = 3,
		Parent = moon,
	})

	-- Étoiles qui scintillent
	local stars: { { Frame: Frame, Phase: number, Speed: number } } = {}
	for _ = 1, 7 do
		local size = random:NextInteger(2, 3)
		local star = circle({
			Name = "Star",
			Position = UDim2.fromOffset(random:NextInteger(6, GLASS_W - 60), random:NextInteger(4, 46)),
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
		BackgroundColor3 = Color3.new(1, 1, 1),
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
	for _, spec in ipairs(BUILDINGS) do
		local w, h = spec[1], spec[2]
		local building = frame({
			Name = "Building",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset(buildingX, GLASS_H),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = Color3.fromRGB(28, 24, 58),
			ZIndex = 3,
			Parent = glass,
		})
		if #litWindows < 9 and h >= 34 then
			for _ = 1, 2 do
				local lit = frame({
					Name = "Lit",
					Position = UDim2.fromOffset(random:NextInteger(3, w - 7), random:NextInteger(5, h - 12)),
					Size = UDim2.fromOffset(3, 4),
					BackgroundColor3 = Color3.fromRGB(255, 214, 110),
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
	local rainCount = effectsOn() and 24 or 10
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
	for _ = 1, 3 do
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
		BackgroundColor3 = Color3.fromRGB(236, 214, 182),
		ZIndex = 6,
		Parent = windowFrame,
	})
	frame({
		Name = "MullionH",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = Color3.fromRGB(236, 214, 182),
		ZIndex = 6,
		Parent = windowFrame,
	})

	-- Rebord
	local sill = frame({
		Name = "Sill",
		Position = UDim2.fromOffset(WINDOW_X - 6, SILL_Y),
		Size = UDim2.fromOffset(WINDOW_W + 12, 8),
		BackgroundColor3 = Color3.fromRGB(206, 178, 140),
		ZIndex = 7,
		Parent = scene,
	})
	UI.Corner(sill, 3)

	-- Plante sur le rebord
	emoji("🌵", 22, {
		Name = "Plant",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(WINDOW_X + WINDOW_W - 20, SILL_Y + 3),
		ZIndex = 8,
		Parent = scene,
	})

	------------------------------------------------------------------
	-- Chat endormi sur le rebord
	------------------------------------------------------------------
	local CAT_COLOR = Color3.fromRGB(245, 176, 98)
	local CAT_DARK = Color3.fromRGB(214, 136, 64)
	local catX, catBottom = WINDOW_X + 18, SILL_Y + 1

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
		BackgroundColor3 = CAT_COLOR,
		ZIndex = 9,
		Parent = scene,
	})
	local bodyScale = UI.Create("UIScale", { Parent = body })
	for i = 1, 3 do
		frame({
			Name = "Stripe",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(14 + i * 9, 1),
			Size = UDim2.fromOffset(3, 10),
			Rotation = 12,
			BackgroundColor3 = CAT_DARK,
			ZIndex = 9,
			Parent = body,
		})
	end

	local headX, headY = catX + 58, catBottom - 14
	for side = -1, 1, 2 do
		frame({
			Name = "CatEar",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(headX + side * 7, headY - 9),
			Size = UDim2.fromOffset(9, 9),
			Rotation = 45,
			BackgroundColor3 = CAT_DARK,
			ZIndex = 9,
			Parent = scene,
		})
	end
	local head = circle({
		Name = "CatHead",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(headX, headY),
		Size = UDim2.fromOffset(26, 22),
		BackgroundColor3 = CAT_COLOR,
		ZIndex = 10,
		Parent = scene,
	})
	for side = -1, 1, 2 do
		frame({
			Name = "Eye",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * 5, 0, 10),
			Size = UDim2.fromOffset(6, 2),
			Rotation = side * -12,
			BackgroundColor3 = Color3.fromRGB(70, 40, 30),
			ZIndex = 10,
			Parent = head,
		})
	end
	frame({
		Name = "Nose",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(4, 3),
		BackgroundColor3 = Color3.fromRGB(255, 130, 150),
		ZIndex = 10,
		Parent = head,
	})

	-- "z z z" qui montent de la tête du chat (3 lettres recyclées)
	local zLabels: { TextLabel } = {}
	for i = 1, 3 do
		zLabels[i] = UI.Create("TextLabel", {
			Name = "Z",
			Text = i == 3 and "Z" or "z",
			Font = Theme.Fonts.Title,
			TextSize = 12,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			ZIndex = 11,
			Parent = scene,
		})
	end

	------------------------------------------------------------------
	-- Mur de droite : horloge + post-it
	------------------------------------------------------------------
	local clockFrame = frame({
		Name = "Clock",
		Position = UDim2.fromOffset(204, 12),
		Size = UDim2.fromOffset(70, 26),
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
		MaxTextSize = 16,
		ZIndex = 3,
		Parent = clockFrame,
	})

	local function postIt(text: string, color: Color3, x: number, y: number, w: number, h: number, rotation: number)
		frame({
			Name = "PostItShadow",
			Position = UDim2.fromOffset(x + 2, y + 3),
			Size = UDim2.fromOffset(w, h),
			Rotation = rotation,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.7,
			ZIndex = 3,
			Parent = scene,
		})
		local note = frame({
			Name = "PostIt",
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			Rotation = rotation,
			BackgroundColor3 = color,
			ZIndex = 4,
			Parent = scene,
		})
		UI.Label({
			Text = text,
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
	end
	postIt("<s>réviser</s>\ncliquer ✅", Color3.fromRGB(255, 236, 120), 288, 10, 60, 44, 5)
	postIt("dormir ?\nplus tard 😴", Color3.fromRGB(255, 170, 200), 212, 48, 58, 40, -6)

	------------------------------------------------------------------
	-- Lampe de bureau
	------------------------------------------------------------------
	local cone = frame({
		Name = "LightCone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(LAMP_X - 6, 108),
		Size = UDim2.fromOffset(74, DESK_Y - 108),
		BackgroundColor3 = Color3.fromRGB(255, 214, 140),
		ZIndex = 4,
		Parent = scene,
	})
	UI.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.55, 1),
		Parent = cone,
	})
	frame({
		Name = "LampArm",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(LAMP_X + 14, DESK_Y),
		Size = UDim2.fromOffset(4, 46),
		BackgroundColor3 = Color3.fromRGB(60, 60, 72),
		Rotation = -12,
		ZIndex = 5,
		Parent = scene,
	})
	local lampBase = frame({
		Name = "LampBase",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(LAMP_X + 16, DESK_Y + 1),
		Size = UDim2.fromOffset(28, 6),
		BackgroundColor3 = Color3.fromRGB(60, 60, 72),
		ZIndex = 5,
		Parent = scene,
	})
	UI.Corner(lampBase, 3)
	local shade = frame({
		Name = "LampShade",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(LAMP_X - 2, 104),
		Size = UDim2.fromOffset(40, 18),
		Rotation = -14,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
		Parent = scene,
	})
	UI.Corner(shade, UDim.new(0.5, 0))
	UI.Gradient(shade, ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(230, 120, 60)), 90)
	local bulb = circle({
		Name = "Bulb",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(12, 8),
		BackgroundColor3 = Color3.fromRGB(255, 250, 210),
		ZIndex = 6,
		Parent = shade,
	})

	------------------------------------------------------------------
	-- L'étudiant (avec son casque) derrière le bureau
	------------------------------------------------------------------
	local person = frame({
		Name = "Person",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(PERSON_X, DESK_Y + 12),
		Size = UDim2.fromOffset(70, 70),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = scene,
	})
	emoji("🧑", 58, {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		ZIndex = 7,
		Parent = person,
	})
	local headphones = emoji("🎧", 50, {
		Name = "Headphones",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -40),
		ZIndex = 8,
		Parent = person,
	})

	-- Notes de musique qui s'échappent du casque (recyclées)
	local notes: { TextLabel } = {}
	for i = 1, 2 do
		notes[i] = UI.Create("TextLabel", {
			Name = "Note",
			Text = i == 1 and "♪" or "♫",
			Font = Theme.Fonts.Title,
			TextSize = 15,
			TextColor3 = i == 1 and EQ_LOW or EQ_HIGH,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			ZIndex = 9,
			Parent = scene,
		})
	end

	------------------------------------------------------------------
	-- Bureau
	------------------------------------------------------------------
	local desk = frame({
		Name = "Desk",
		Position = UDim2.fromOffset(0, DESK_Y),
		Size = UDim2.new(1, 0, 0, SCENE_H - DESK_Y),
		BackgroundColor3 = Color3.fromRGB(96, 62, 46),
		ZIndex = 10,
		Parent = scene,
	})
	UI.Corner(desk, 10)
	frame({
		Name = "DeskTop",
		Position = UDim2.fromOffset(0, DESK_Y),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Color3.fromRGB(140, 96, 70),
		ZIndex = 11,
		Parent = scene,
	})
	-- Tiroir
	local drawer = frame({
		Name = "Drawer",
		Position = UDim2.fromOffset(150, 22),
		Size = UDim2.fromOffset(90, 16),
		BackgroundColor3 = Color3.fromRGB(116, 78, 58),
		ZIndex = 10,
		Parent = desk,
	})
	UI.Corner(drawer, 4)
	circle({
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.fromRGB(230, 200, 140),
		ZIndex = 10,
		Parent = drawer,
	})

	-- Objets sur le bureau
	emoji("📚", 22, {
		Name = "Books",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(36, DESK_Y + 4),
		ZIndex = 12,
		Parent = scene,
	})
	emoji("📖", 22, {
		Name = "Book",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(PERSON_X - 30, DESK_Y + 4),
		ZIndex = 12,
		Parent = scene,
	})
	local mugX = 196
	emoji("☕", 22, {
		Name = "Mug",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(mugX, DESK_Y + 4),
		ZIndex = 12,
		Parent = scene,
	})
	local steam: { Frame } = {}
	for i = 1, 3 do
		steam[i] = circle({
			Name = "Steam",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(5, 5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			ZIndex = 12,
			Parent = scene,
		})
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
		BackgroundColor3 = Color3.fromRGB(18, 14, 32),
		Parent = card,
	})
	UI.Corner(bar, 10)
	UI.Stroke(bar, Color3.fromRGB(90, 70, 140), 1, 0.5)

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
		BackgroundColor3 = EQ_LOW,
		Parent = disc,
	})
	UI.Gradient(labelDisc, ColorSequence.new(EQ_LOW, EQ_HIGH), 0)
	frame({
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -6),
		Size = UDim2.fromOffset(2, 7),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		Parent = disc,
	})

	local title = UI.Create("TextLabel", {
		Name = "Title",
		Text = "lofi beats 🎧 pour réviser",
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
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
		BackgroundColor3 = Color3.fromRGB(46, 38, 72),
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "⏭",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		Visible = false,
		Parent = bar,
	})
	UI.Corner(skip, UDim.new(1, 0))
	UI.Stroke(skip, EQ_HIGH, 1.5, 0.4)
	UI.AnimateButton(skip, 1.1, 0.88)

	-- Égaliseur
	local eqWidth = 78
	local eq = frame({
		Name = "Equalizer",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(eqWidth, 28),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	local barWidth = 5
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
	local trackIndex = random:NextInteger(1, #TRACKS)
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
		return "🔴 " .. text .. " personnes révisent (ou pas)"
	end

	local function refreshSubtitle()
		local name = currentMusic()
		local playlist = hasPlaylist()
		skip.Visible = name ~= nil
		eq.Position = name and UDim2.new(1, -44, 0.5, 0) or UDim2.new(1, -10, 0.5, 0)
		-- Textes : toute la place jusqu'à l'égaliseur
		local textWidth = name and 196 or 230
		title.Size = UDim2.fromOffset(textWidth, 18)
		subtitle.Size = UDim2.fromOffset(textWidth, 15)
		subtitle.TextColor3 = Color3.fromRGB(200, 186, 240)

		if name then
			-- Vraie musique
			title.Text = "♫ " .. name
			subtitle.Text = showAlt and "lofi beats 🎧 pour réviser" or viewersText()
		elseif playlist then
			-- Musique disponible mais coupée (réglage) ou en chargement
			title.Text = "lofi beats 🎧 pour réviser"
			local musicOn = type(Sound.IsMusicEnabled) ~= "function" or Sound.IsMusicEnabled()
			if showAlt then
				subtitle.Text = musicOn and "♫ Chargement de la musique..." or "🔇 Musique coupée (⚙️ Paramètres)"
			else
				subtitle.Text = viewersText()
			end
		elseif isStudio then
			-- Rappel pour le créateur du jeu (seulement dans Studio)
			title.Text = "lofi beats 🎧 pour réviser"
			subtitle.Text = "⚠️ Ajoute une musique dans Config.Music"
			subtitle.TextColor3 = Color3.fromRGB(255, 200, 90)
		else
			-- Pas de musique : juste l'ambiance
			title.Text = "lofi beats 🎧 pour réviser"
			subtitle.Text = showAlt and ("♫ " .. TRACKS[trackIndex]) or viewersText()
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

	skip.Activated:Connect(function()
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
					trackIndex = trackIndex % #TRACKS + 1
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
	local loudPeak = 40 -- pic de volume récent (PlaybackLoudness)
	local lastLevel = 0
	local rainDX = math.tan(RAIN_ANGLE)
	ctx.OnRender(function(dt: number)
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

		-- Étoiles
		for _, star in ipairs(stars) do
			star.Frame.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(clock * star.Speed + star.Phase))
		end
		moonGlow.BackgroundTransparency = 0.8 + 0.06 * math.sin(clock * 0.8)

		-- Lueur de la lampe qui "respire" (+ petit grésillement rare)
		local breath = 0.5 + 0.5 * math.sin(clock * 1.2)
		local flicker = (math.sin(clock * 37) > 0.985) and 0.06 or 0
		for i, glow in ipairs(glows) do
			glow.BackgroundTransparency = math.min(1, GLOW_ALPHA[i] + (1 - breath) * 0.05 + flicker)
		end
		bulb.BackgroundTransparency = flicker * 4

		-- Chat : respiration, queue qui ondule, "z z z"
		bodyScale.Scale = 1 + 0.035 * (0.5 + 0.5 * math.sin(clock * 1.6))
		tail.Rotation = -18 + math.sin(clock * 0.9) * 10
		for i, z in ipairs(zLabels) do
			local p = ((clock / 3.3) + (i - 1) / 3) % 1
			z.Position = UDim2.fromOffset(headX + 8 + p * 22 + math.sin(p * 6) * 3, headY - 12 - p * 44)
			z.TextSize = 9 + p * 9
			z.TextTransparency = p < 0.12 and (1 - p / 0.12) or (p * p)
		end

		-- Étudiant qui hoche la tête en rythme
		local beatPhase = (clock % BEAT) / BEAT
		local nod = math.sin(beatPhase * math.pi)
		person.Position = UDim2.fromOffset(PERSON_X, DESK_Y + 12 + nod * 3)
		person.Rotation = math.sin(clock * math.pi / BEAT) * 3
		headphones.Rotation = -person.Rotation * 0.3

		-- Notes de musique
		for i, note in ipairs(notes) do
			if fx then
				local p = ((clock / 2.6) + (i - 1) * 0.5) % 1
				note.Visible = true
				note.Position = UDim2.fromOffset(PERSON_X + 20 + p * 26, 96 - p * 50)
				note.Rotation = math.sin(p * 8) * 20
				note.TextTransparency = p < 0.15 and (1 - p / 0.15) or p
			else
				note.Visible = false
			end
		end

		-- Vapeur du café
		for i, puff in ipairs(steam) do
			if fx then
				local p = ((clock / 2.2) + (i - 1) / 3) % 1
				puff.Position = UDim2.fromOffset(mugX + math.sin(p * 7 + i) * 4, DESK_Y - 18 - p * 26)
				puff.Size = UDim2.fromOffset(4 + p * 6, 4 + p * 6)
				puff.BackgroundTransparency = 0.45 + p * 0.55
			else
				puff.BackgroundTransparency = 1
			end
		end

		-- Égaliseur : piloté par le volume réel de la musique si elle joue,
		-- sinon animé tout seul (basses sur le temps)
		local _, music = currentMusic()
		local loudness = 0
		if music and music.Parent and music.IsPlaying then
			loudness = music.PlaybackLoudness
		end
		if music and music.IsPlaying then
			-- Pic adaptatif : l'égaliseur reste expressif quel que soit le volume
			loudPeak = math.max(loudness, loudPeak * (1 - math.min(1, dt * 0.35)), 40)
			local level = math.clamp(loudness / loudPeak, 0, 1)
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
				local onBeat = newBeat ~= beatCount
				beatCount = newBeat
				for i = 1, EQ_BARS do
					local low = 1 - (i - 1) / (EQ_BARS - 1)
					local base = 0.15 + random:NextNumber() * 0.55
					if onBeat then
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
