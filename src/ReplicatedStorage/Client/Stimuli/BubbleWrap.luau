--[[
	BubbleWrap (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > BubbleWrap

	v9 : un VRAI papier bulle.
	  - Feuille de plastique translucide (reflets en biais) posée sur un
	    fond de carton ; 8 x 5 bulles en quinconce, centrées.
	  - Chaque bulle est un dôme brillant : ombre douce portée sur la
	    feuille, dôme translucide (bords plus opaques et bleutés = la
	    réfraction du plastique), gros reflet en haut à gauche, petit reflet
	    en bas à droite, liseré clair.
	  - POP : la bulle gonfle sous le doigt puis se dégonfle en rebondissant
	    et se froisse (plus d'ombre, plastique laiteux, deux plis qui se
	    creusent), bouffée d'air, anneau qui s'élargit et petits traits "pop"
	    qui partent en étoile. Les bulles éclatées restent aplaties jusqu'à
	    la feuille suivante.
	  - clic / toucher sur une bulle = POP ; sur PC, maintenir le clic et
	    "glisser" sur les bulles ; au survol, la bulle se soulève un peu ;
	  - chaque bulle éclatée envoie Interact("Bubble"). Le serveur ne renvoie
	    pas de notification : le "+X" affiché est prédit côté client
	    (gain par clic x Config.Interactions.Bubble.ClickFraction) ;
	  - limite côté client (seau de jetons) pour ne jamais dépasser
	    MaxPerSecond : au-delà, la bulle résiste (petit tremblement) ;
	  - quand tout est éclaté : la feuille part, un message apparaît sur le
	    carton, une feuille neuve arrive en glissant, ses bulles se gonflent
	    en vague et un reflet balaie la feuille.
	  - Pastille compteur (en-tête) : bulles éclatées pendant la session ;
	    son remplissage bleu = avancement de la feuille en cours.
	Sons inchangés : "Pop" à chaque bulle éclatée, "Open" à chaque feuille.
	Les bulles et les effets sont créés une seule fois puis réutilisés ;
	UNE boucle OnRender (animations des bulles, effets, vague) qui ne fait
	rien au repos.
]]

local UserInputService = game:GetService("UserInputService")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local BubbleWrap = {}
BubbleWrap.Slot = "L2"

local COLUMNS = 8
local ROWS = 5
local DIAMETER = 26
local PITCH_X = 31 -- quinconce : les rangées impaires sont décalées de PITCH_X / 2
local PITCH_Y = 27
local WINDOW_X = 8 -- fenêtre (feuille) dans la carte
local WINDOW_Y = 30
local FX_POOL = 6 -- effets de "pop" recyclés
local BURST_LINES = 6 -- traits "pop" par effet
local POP_TIME = 0.34 -- rebond d'une bulle qui éclate
local INFLATE_TIME = 0.34 -- gonflage d'une bulle neuve
local FX_TIME = 0.42 -- durée d'un effet de pop
local HOVER_SCALE = 1.07
local FLAT_SCALE = 0.88 -- bulle éclatée (aplatie)
local SHEET_PAD = 1 -- la feuille déborde d'1 px de la fenêtre (pas de liseré de carton)

local WHITE = Color3.new(1, 1, 1)

-- Dôme intact : bord haut-gauche blanc, milieu transparent, bord bas-droite bleuté
local DOME_COLOR = Color3.fromRGB(238, 247, 255)
local DOME_TRANSPARENCY = 0.2
local DOME_GRADIENT_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(226, 240, 253)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(146, 188, 228)),
})
local DOME_GRADIENT_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.02),
	NumberSequenceKeypoint.new(0.35, 0.34),
	NumberSequenceKeypoint.new(0.68, 0.4),
	NumberSequenceKeypoint.new(1, 0),
})
local DOME_STROKE = Color3.fromRGB(160, 200, 236)
local SHADOW_REST = 0.76

-- Bulle éclatée : plastique laiteux, plat, liseré froissé
local FLAT_COLOR = Color3.fromRGB(240, 244, 250)
local FLAT_TRANSPARENCY = 0.42
local FLAT_GRADIENT_COLOR = ColorSequence.new(WHITE, Color3.fromRGB(206, 216, 232))
local FLAT_GRADIENT_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.45),
	NumberSequenceKeypoint.new(1, 0.2),
})
local FLAT_STROKE = Color3.fromRGB(176, 192, 214)
local WRINKLE_DARK = Color3.fromRGB(138, 160, 192) -- pli (creux)
local WRINKLE_LIGHT = WHITE -- pli (arête qui brille)

-- Trait qui s'estompe aux deux bouts (reflets en biais de la feuille)
local SHEEN = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})

local CAPTIONS = {
	en = {
		"Again! 🔁",
		"Fresh sheet 📦",
		"Bubble delivery!",
		"Want some more?",
		"Pop pop pop!",
		"That sheet was innocent.",
		"Zero bubble survivors.",
		"It's therapeutic.",
	},
	fr = {
		"Encore ! 🔁",
		"Nouvelle feuille 📦",
		"Livraison de bulles !",
		"Tu en veux encore ?",
		"Pop pop pop !",
		"La feuille était innocente.",
		"Zéro bulle survivante.",
		"C'est thérapeutique.",
	},
}

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeOutBack(t: number): number
	local c = 1.9
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

function BubbleWrap.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()
	local bubbleConfig = ctx.Config.Interactions.Bubble or {}
	local maxPerSecond = bubbleConfig.MaxPerSecond or 12
	local clickFraction = bubbleConfig.ClickFraction or 0.5

	-- Seau de jetons (un peu sous la limite serveur, pour ne jamais être refusé)
	local capacity = math.max(1, math.floor(maxPerSecond * 0.75))
	local refillRate = maxPerSecond * 0.9
	local tokens = capacity
	local lastRefill = os.clock()

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function round(guiObject: GuiObject)
		UIUtil.Corner(guiObject, UDim.new(1, 0))
	end

	-- Taille "design" de la carte et de la fenêtre (slot 288 x 180)
	local slotSize = ctx.GetSlotSize and ctx.GetSlotSize() or Vector2.new(288, 180)
	local cardW = (slotSize.X > 0 and slotSize.X or 288) - 4
	local cardH = (slotSize.Y > 0 and slotSize.Y or 180) - 4
	local windowW = cardW - WINDOW_X * 2
	local windowH = cardH - WINDOW_Y - 6

	------------------------------------------------------------------
	-- Carte + en-tête (petite bulle dessinée, titre, pastille compteur)
	------------------------------------------------------------------
	local card = Create("Frame", {
		Name = "Card",
		-- 2 px de marge : le contour de la carte n'est pas coupé par le slot
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = Theme.Colors.Card,
		BorderSizePixel = 0,
		Parent = container,
	})
	UIUtil.Corner(card, 18)
	UIUtil.Stroke(card, Theme.Colors.CardBorder, 2)
	UIUtil.Gradient(card, ColorSequence.new(WHITE, Color3.fromRGB(236, 242, 250)), 90)

	-- Icône : une bulle brillante
	local icon = Create("Frame", {
		Name = "Icon",
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.fromOffset(17, 17),
		BackgroundColor3 = DOME_COLOR,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = card,
	})
	round(icon)
	Create("UIGradient", { Rotation = 45, Color = DOME_GRADIENT_COLOR, Parent = icon })
	UIUtil.Stroke(icon, Color3.fromRGB(96, 150, 206), 1.5, 0)
	local iconShine = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.34, 0.32),
		Size = UDim2.fromOffset(7, 4),
		Rotation = -40,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = icon,
	})
	round(iconShine)

	UIUtil.Label({
		Name = "Title",
		Text = Locale.T("BUBBLE WRAP"),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(35, 4),
		Size = UDim2.fromOffset(150, 22),
		MaxTextSize = 15,
		ZIndex = 5,
		Parent = card,
	})

	-- Pastille : fond clair, remplissage bleu (= avancement de la feuille), compteur
	local pill = Create("Frame", {
		Name = "Counter",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -9, 0, 5),
		Size = UDim2.fromOffset(74, 20),
		BackgroundColor3 = Color3.fromRGB(232, 243, 255),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = card,
	})
	round(pill)
	UIUtil.Stroke(pill, Color3.fromRGB(96, 150, 206), 1.5, 0)
	local pillScale = Create("UIScale", { Parent = pill })
	local pillFill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = pill,
	})
	round(pillFill)
	UIUtil.Gradient(pillFill, ColorSequence.new(Color3.fromRGB(140, 205, 255), Color3.fromRGB(70, 150, 235)), 0)
	local counterLabel = UIUtil.Label({
		Name = "Count",
		Text = "💥 0",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDark,
		Position = UDim2.fromOffset(4, 1),
		Size = UDim2.new(1, -8, 1, -2),
		MaxTextSize = 14,
		ZIndex = 6,
		Parent = pill,
	})

	------------------------------------------------------------------
	-- Fenêtre : carton (visible quand la feuille part) + feuille de plastique
	------------------------------------------------------------------
	local window = Create("Frame", {
		Name = "Window",
		Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y),
		Size = UDim2.new(1, -WINDOW_X * 2, 1, -(WINDOW_Y + 6)),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Gradient(window, ColorSequence.new(Color3.fromRGB(226, 196, 150), Color3.fromRGB(204, 168, 118)), 90)
	UIUtil.Stroke(window, Color3.fromRGB(150, 176, 206), 1, 0.3)
	-- Lignes du carton ondulé
	for index = 1, 3 do
		Create("Frame", {
			Name = "Groove",
			Position = UDim2.new(0, 0, index / 4, 0),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.fromRGB(176, 136, 90),
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = window,
		})
	end

	-- Message de fin de feuille (sur le carton)
	local caption = UIUtil.Label({
		Name = "Caption",
		Text = "",
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Theme.Colors.Blue,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 0, 34),
		MaxTextSize = 26,
		ZIndex = 1,
		Parent = window,
	})
	local captionStroke = UIUtil.Stroke(caption, WHITE, 2.5, 1)
	captionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local sheetRest = UDim2.fromOffset(-SHEET_PAD, -SHEET_PAD)
	local sheet = Create("Frame", {
		Name = "Sheet",
		Position = sheetRest,
		Size = UDim2.new(1, SHEET_PAD * 2, 1, SHEET_PAD * 2),
		BackgroundColor3 = Color3.fromRGB(222, 238, 252),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = window,
	})
	UIUtil.Gradient(sheet, ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(236, 245, 253)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(206, 224, 242)),
	}), 55)

	-- Reflets en biais du plastique (fixes) + un reflet qui balaie la feuille neuve
	local function sheenBand(name: string, x: number, width: number, transparency: number): Frame
		local band = Create("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, windowH / 2),
			Size = UDim2.fromOffset(width, windowH * 1.5),
			Rotation = 32,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = sheet,
		})
		Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE), Transparency = SHEEN, Parent = band })
		return band
	end
	sheenBand("Sheen", windowW * 0.28, 22, 0.35)
	sheenBand("Sheen", windowW * 0.36, 7, 0.4)
	sheenBand("Sheen", windowW * 0.78, 14, 0.5)
	local sweep = sheenBand("Sweep", -40, 30, 0.1)
	sweep.Visible = false

	------------------------------------------------------------------
	-- Bulles (créées une fois, réutilisées pour chaque feuille)
	------------------------------------------------------------------
	local bubbles = {}
	local poppedCount = 0
	local sessionPops = 0
	local regenerating = false
	local gridW = (COLUMNS - 1) * PITCH_X + PITCH_X / 2 + DIAMETER
	local gridH = (ROWS - 1) * PITCH_Y + DIAMETER
	local originX = SHEET_PAD + (windowW - gridW) / 2 + DIAMETER / 2
	local originY = SHEET_PAD + (windowH - gridH) / 2 + DIAMETER / 2

	local function bubblePosition(row: number, column: number): (number, number)
		local x = originX + column * PITCH_X + ((row % 2 == 1) and PITCH_X / 2 or 0)
		local y = originY + row * PITCH_Y
		return x, y
	end

	-- Animations en cours (bulles qui éclatent / se gonflent)
	local animating = {}

	local function startAnim(bubble, kind: string, delay: number)
		bubble.Anim = kind
		bubble.AnimT = -delay
		if not bubble.Listed then
			bubble.Listed = true
			table.insert(animating, bubble)
		end
	end

	local function restScale(bubble): number
		return bubble.Hover and HOVER_SCALE or 1
	end

	-- Aspect "dôme intact"
	local function setDomeLook(bubble)
		local button = bubble.Button
		button.BackgroundColor3 = DOME_COLOR
		button.BackgroundTransparency = DOME_TRANSPARENCY
		bubble.Gradient.Color = DOME_GRADIENT_COLOR
		bubble.Gradient.Transparency = DOME_GRADIENT_TRANSPARENCY
		bubble.Stroke.Color = DOME_STROKE
		bubble.Stroke.Transparency = 0.1
		local shadow = bubble.Shadow
		shadow.Position = UDim2.fromOffset(bubble.X + 1.5, bubble.Y + 2.5)
		shadow.BackgroundTransparency = SHADOW_REST
		local highlight = bubble.Highlight
		highlight.Position = UDim2.fromScale(0.34, 0.3)
		highlight.Size = UDim2.fromOffset(9, 5)
		highlight.Rotation = -40
		highlight.BackgroundColor3 = WHITE
		highlight.BackgroundTransparency = 0.02
		local reflex = bubble.Reflex
		reflex.Position = UDim2.fromScale(0.7, 0.74)
		reflex.Size = UDim2.fromOffset(5, 2.5)
		reflex.Rotation = -40
		reflex.BackgroundColor3 = WHITE
		reflex.BackgroundTransparency = 0.45
	end

	-- Aspect "éclatée" : plastique laiteux, deux plis (la longueur des plis est animée)
	local function setFlatLook(bubble)
		local button = bubble.Button
		button.BackgroundColor3 = FLAT_COLOR
		button.BackgroundTransparency = FLAT_TRANSPARENCY
		bubble.Gradient.Color = FLAT_GRADIENT_COLOR
		bubble.Gradient.Transparency = FLAT_GRADIENT_TRANSPARENCY
		bubble.Stroke.Color = FLAT_STROKE
		bubble.Stroke.Transparency = 0.3
		bubble.Shadow.Position = UDim2.fromOffset(bubble.X + 0.5, bubble.Y + 1)
		-- Deux plis presque parallèles, décalés de part et d'autre du centre
		-- (une arête claire, un creux plus sombre) : du plastique froissé
		local angle = random:NextNumber(0, 180)
		local normal = math.rad(angle + 90)
		local shift = random:NextNumber(2.5, 4)
		local highlight = bubble.Highlight
		highlight.Position = UDim2.new(0.5, -math.cos(normal) * shift, 0.5, -math.sin(normal) * shift)
		highlight.Rotation = angle
		highlight.BackgroundColor3 = WRINKLE_LIGHT
		highlight.BackgroundTransparency = 0.05
		local reflex = bubble.Reflex
		reflex.Position = UDim2.new(0.5, math.cos(normal) * shift * 0.8, 0.5, math.sin(normal) * shift * 0.8)
		reflex.Rotation = angle + random:NextNumber(-28, 28)
		reflex.BackgroundColor3 = WRINKLE_DARK
		reflex.BackgroundTransparency = 0.35
		bubble.CreaseA = DIAMETER * random:NextNumber(0.5, 0.64)
		bubble.CreaseB = DIAMETER * random:NextNumber(0.42, 0.56)
	end

	local function setCreases(bubble, amount: number)
		bubble.Highlight.Size = UDim2.fromOffset(math.max(1, bubble.CreaseA * amount), 1.6)
		bubble.Reflex.Size = UDim2.fromOffset(math.max(1, bubble.CreaseB * amount), 1.3)
	end

	-- Vrai si un jeton est disponible (et le consomme)
	local function takeToken(): boolean
		local now = os.clock()
		tokens = math.min(capacity, tokens + (now - lastRefill) * refillRate)
		lastRefill = now
		if tokens >= 1 then
			tokens -= 1
			return true
		end
		return false
	end

	------------------------------------------------------------------
	-- Effets de "pop" : réserve recyclée (anneau, bouffée d'air, traits en
	-- étoile), animée par la boucle (aucune création pendant le jeu)
	------------------------------------------------------------------
	local fxPool = {}
	for index = 1, FX_POOL do
		local ring = Create("Frame", {
			Name = "PopRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(DIAMETER, DIAMETER),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 8,
			Parent = sheet,
		})
		round(ring)
		local puff = Create("Frame", {
			Name = "PopPuff",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(DIAMETER, DIAMETER),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 7,
			Parent = sheet,
		})
		round(puff)
		local lines = {}
		for line = 1, BURST_LINES do
			local frame = Create("Frame", {
				Name = "PopLine",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(6, 2),
				BackgroundColor3 = (line % 2 == 0) and WHITE or Color3.fromRGB(120, 186, 246),
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 9,
				Parent = sheet,
			})
			round(frame)
			lines[line] = { Frame = frame, Angle = 0, Reach = 14 }
		end
		fxPool[index] = {
			Ring = ring,
			RingStroke = UIUtil.Stroke(ring, Color3.fromRGB(110, 184, 246), 2, 0.1),
			Puff = puff,
			Lines = lines,
			Full = false,
			Age = 1,
			X = 0,
			Y = 0,
		}
	end
	local nextFx = 1
	local activeFx = 0

	local function popEffects(x: number, y: number)
		local fx = fxPool[nextFx]
		nextFx = nextFx % FX_POOL + 1
		if fx.Age >= 1 then
			activeFx += 1
		end
		fx.Age = 0
		fx.X, fx.Y = x, y
		fx.Full = effectsOn()
		fx.Ring.Position = UDim2.fromOffset(x, y)
		fx.Ring.Size = UDim2.fromOffset(DIAMETER, DIAMETER)
		fx.RingStroke.Transparency = 0.1
		fx.Ring.Visible = true
		fx.Puff.Visible = fx.Full
		local base = random:NextNumber(0, math.pi * 2)
		for index, line in ipairs(fx.Lines) do
			line.Angle = base + (index - 1) * (math.pi * 2 / BURST_LINES) + random:NextNumber(-0.25, 0.25)
			line.Reach = random:NextNumber(11, 17)
			line.Frame.Rotation = math.deg(line.Angle)
			line.Frame.Visible = fx.Full
		end
	end

	local function stepEffects(dt: number)
		if activeFx <= 0 then
			return
		end
		for _, fx in ipairs(fxPool) do
			if fx.Age < 1 then
				fx.Age = math.min(1, fx.Age + dt / FX_TIME)
				local age = fx.Age
				local eased = easeOutCubic(age)
				local size = DIAMETER * (1 + 1.1 * eased)
				fx.Ring.Size = UDim2.fromOffset(size, size)
				fx.RingStroke.Transparency = 0.1 + 0.9 * age
				fx.RingStroke.Thickness = 0.6 + 1.6 * (1 - age)
				if fx.Full then
					local puffAge = math.min(1, age / 0.45)
					local puffSize = DIAMETER * (0.7 + 0.8 * easeOutCubic(puffAge))
					fx.Puff.Size = UDim2.fromOffset(puffSize, puffSize)
					fx.Puff.BackgroundTransparency = 0.3 + 0.7 * puffAge
					for _, line in ipairs(fx.Lines) do
						local reach = DIAMETER * 0.5 + line.Reach * eased
						line.Frame.Position = UDim2.fromOffset(fx.X + math.cos(line.Angle) * reach, fx.Y + math.sin(line.Angle) * reach)
						line.Frame.Size = UDim2.fromOffset(1.5 + 6 * (1 - age), 2)
						line.Frame.BackgroundTransparency = age ^ 1.5
					end
				end
				if fx.Age >= 1 then
					fx.Ring.Visible = false
					fx.Puff.Visible = false
					for _, line in ipairs(fx.Lines) do
						line.Frame.Visible = false
					end
					activeFx -= 1
				end
			end
		end
	end

	------------------------------------------------------------------
	-- Pop !
	------------------------------------------------------------------
	local regenerate -- (déclarée plus bas)

	local function updateCounter()
		counterLabel.Text = "💥 " .. tostring(sessionPops)
		local total = math.max(1, #bubbles)
		UIUtil.Tween(pillFill, 0.18, { Size = UDim2.fromScale(math.clamp(poppedCount / total, 0, 1), 1) }, Enum.EasingStyle.Quad)
	end

	local function pop(bubble)
		if bubble.Popped or regenerating or not ctx.IsAlive() then
			return
		end
		if not takeToken() then
			-- Trop vite : la bulle résiste
			if bubble.Anim == nil then
				bubble.Scale.Scale = 0.9
				UIUtil.Tween(bubble.Scale, 0.2, { Scale = restScale(bubble) }, Enum.EasingStyle.Back)
			end
			return
		end
		bubble.Popped = true
		bubble.Hover = false
		poppedCount += 1
		sessionPops += 1

		ctx.Interact("Bubble")
		ctx.Sound.Play("Pop", random:NextNumber(0.9, 1.35))

		-- Gonfle sous le doigt, éclate, se dégonfle en rebondissant et se froisse
		setFlatLook(bubble)
		setCreases(bubble, 0)
		bubble.Scale.Scale = 1.2
		startAnim(bubble, "Pop", 0)
		popEffects(bubble.X, bubble.Y)

		-- "+X" prédit
		local data = ctx.State.Data
		local value = (data and tonumber(data.ClickValue) or 0) * clickFraction
		if value > 0 then
			local sheetOffset = sheet.Position.X.Offset
			ctx.FloatText(
				container,
				UDim2.fromOffset(2 + WINDOW_X + sheetOffset + bubble.X, 2 + WINDOW_Y - SHEET_PAD + bubble.Y - 12),
				"+" .. ctx.Format.Format(value),
				Theme.Colors.Blue,
				18
			)
		end

		updateCounter()
		pillScale.Scale = 1.14
		UIUtil.Tween(pillScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)

		if poppedCount >= #bubbles then
			regenerate()
		end
	end

	for row = 0, ROWS - 1 do
		for column = 0, COLUMNS - 1 do
			local x, y = bubblePosition(row, column)
			-- Ombre douce portée sur la feuille
			local shadow = Create("Frame", {
				Name = "BubbleShadow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x + 1.5, y + 2.5),
				Size = UDim2.fromOffset(DIAMETER, DIAMETER),
				BackgroundColor3 = Color3.fromRGB(70, 104, 146),
				BackgroundTransparency = SHADOW_REST,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = sheet,
			})
			round(shadow)
			-- Dôme (le bouton)
			local button = Create("TextButton", {
				Name = "Bubble",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(DIAMETER, DIAMETER),
				BackgroundColor3 = DOME_COLOR,
				BackgroundTransparency = DOME_TRANSPARENCY,
				AutoButtonColor = false,
				Text = "",
				ZIndex = 5,
				Parent = sheet,
			})
			round(button)
			local gradient = Create("UIGradient", { Rotation = 45, Color = DOME_GRADIENT_COLOR, Parent = button })
			local stroke = UIUtil.Stroke(button, DOME_STROKE, 1, 0.1)
			local scale = Create("UIScale", { Parent = button })
			local highlight = Create("Frame", {
				Name = "Highlight",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = button,
			})
			round(highlight)
			local reflex = Create("Frame", {
				Name = "Reflex",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = button,
			})
			round(reflex)
			local bubble = {
				Button = button,
				Gradient = gradient,
				Stroke = stroke,
				Scale = scale,
				Shadow = shadow,
				Highlight = highlight,
				Reflex = reflex,
				X = x,
				Y = y,
				Row = row,
				Column = column,
				Popped = false,
				Hover = false,
				Anim = nil :: string?,
				AnimT = 0,
				Listed = false,
				CreaseA = DIAMETER * 0.66,
				CreaseB = DIAMETER * 0.42,
			}
			setDomeLook(bubble)
			table.insert(bubbles, bubble)

			ctx.Connect(button.MouseButton1Down, function()
				pop(bubble)
			end)
			-- Glisser en maintenant le clic (souris) ; sinon la bulle se soulève
			ctx.Connect(button.MouseEnter, function()
				if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					pop(bubble)
				elseif not bubble.Popped then
					bubble.Hover = true
					if bubble.Anim == nil then
						bubble.Scale.Scale = HOVER_SCALE
					end
				end
			end)
			ctx.Connect(button.MouseLeave, function()
				if bubble.Hover then
					bubble.Hover = false
					if bubble.Anim == nil and not bubble.Popped then
						bubble.Scale.Scale = 1
					end
				end
			end)
		end
	end

	-- Avance les animations des bulles (rebond du pop, gonflage)
	local function stepBubbles(dt: number)
		if #animating == 0 then
			return
		end
		local index = 1
		while index <= #animating do
			local bubble = animating[index]
			local finished = false
			bubble.AnimT += dt
			local t = bubble.AnimT
			if bubble.Anim == "Pop" then
				if t >= POP_TIME then
					bubble.Scale.Scale = FLAT_SCALE
					setCreases(bubble, 1)
					bubble.Shadow.BackgroundTransparency = 0.94
					finished = true
				else
					-- Rebond amorti autour de la taille "aplatie"
					bubble.Scale.Scale = FLAT_SCALE + (1.2 - FLAT_SCALE) * math.exp(-t * 13) * math.cos(t * 27)
					setCreases(bubble, math.clamp((t - 0.03) / 0.12, 0, 1))
					bubble.Shadow.BackgroundTransparency = SHADOW_REST + (0.94 - SHADOW_REST) * math.clamp(t / 0.12, 0, 1)
				end
			elseif bubble.Anim == "Inflate" then
				if t >= INFLATE_TIME then
					setDomeLook(bubble)
					bubble.Scale.Scale = restScale(bubble)
					finished = true
				elseif t >= 0 then
					local p = t / INFLATE_TIME
					bubble.Scale.Scale = 0.3 + 0.7 * easeOutBack(p)
					bubble.Highlight.BackgroundTransparency = 1 - 0.98 * p
					bubble.Reflex.BackgroundTransparency = 1 - 0.55 * p
					bubble.Shadow.BackgroundTransparency = 1 - (1 - SHADOW_REST) * p
				end
			else
				finished = true
			end
			if finished then
				bubble.Anim = nil
				bubble.Listed = false
				animating[index] = animating[#animating]
				animating[#animating] = nil
			else
				index += 1
			end
		end
	end

	------------------------------------------------------------------
	-- Nouvelle feuille
	------------------------------------------------------------------
	local sweepAge = -1 -- < 0 : pas de reflet qui balaie

	regenerate = function()
		if regenerating then
			return
		end
		regenerating = true
		task.spawn(function()
			task.wait(0.35)
			if not ctx.IsAlive() then
				return
			end
			-- Message sur le carton, visible pendant que la feuille glisse
			local captions = Locale.Pick(CAPTIONS)
			caption.Text = captions[random:NextInteger(1, #captions)]
			caption.TextTransparency = 0
			captionStroke.Transparency = 0
			UIUtil.Tween(sheet, 0.35, { Position = UDim2.fromOffset(-(windowW + 10), -SHEET_PAD) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			ctx.Sound.Play("Open", 0.9)
			task.wait(0.75)
			if not ctx.IsAlive() then
				return
			end
			-- Feuille neuve : bulles "à plat", elles se gonflent en vague en arrivant
			for _, bubble in ipairs(bubbles) do
				bubble.Popped = false
				bubble.Hover = false
				setDomeLook(bubble)
				bubble.Scale.Scale = 0.3
				bubble.Highlight.BackgroundTransparency = 1
				bubble.Reflex.BackgroundTransparency = 1
				bubble.Shadow.BackgroundTransparency = 1
				startAnim(bubble, "Inflate", 0.16 + bubble.Column * 0.035 + bubble.Row * 0.025)
			end
			poppedCount = 0
			updateCounter()
			sheet.Position = UDim2.fromOffset(windowW + 10, -SHEET_PAD)
			UIUtil.Tween(sheet, 0.45, { Position = sheetRest }, Enum.EasingStyle.Back)
			UIUtil.Tween(caption, 0.3, { TextTransparency = 1 })
			UIUtil.Tween(captionStroke, 0.3, { Transparency = 1 })
			sweepAge = -0.3
			task.wait(0.45)
			regenerating = false
		end)
	end

	------------------------------------------------------------------
	-- Boucle : animations des bulles, effets, reflet qui balaie, et petite
	-- vague de "respiration" des bulles intactes (pour donner envie),
	-- seulement si le papier bulle est visible.
	------------------------------------------------------------------
	local WAVE_STEP = 0.04 -- décalage par colonne
	local WAVE_TIME = 0.3
	local waveAge = -1 -- < 0 : pas de vague en cours
	local nextWave = os.clock() + random:NextNumber(4, 7)

	ctx.OnRender(function(dt: number)
		stepEffects(dt)
		stepBubbles(dt)

		if sweepAge > -0.5 then
			sweepAge += dt
			if sweepAge >= 0.7 then
				sweepAge = -1
				sweep.Visible = false
			elseif sweepAge >= 0 then
				sweep.Visible = true
				sweep.Position = UDim2.fromOffset(-40 + (windowW + 80) * easeOutCubic(sweepAge / 0.7), windowH / 2)
			end
		end

		local now = os.clock()
		if waveAge < 0 then
			if now >= nextWave then
				nextWave = now + random:NextNumber(4, 7)
				if not regenerating and ctx.GetVisibility() == "Visible" then
					waveAge = 0
				end
			end
			return
		end
		waveAge += dt
		local finished = true
		for index, bubble in ipairs(bubbles) do
			if not bubble.Popped and bubble.Anim == nil then
				local t = waveAge - ((index - 1) % COLUMNS) * WAVE_STEP
				local rest = restScale(bubble)
				if t < WAVE_TIME then
					finished = false
					if t >= 0 then
						bubble.Scale.Scale = rest + 0.07 * math.sin(t / WAVE_TIME * math.pi)
					end
				elseif bubble.Scale.Scale ~= rest then
					bubble.Scale.Scale = rest
				end
			end
		end
		if finished then
			waveAge = -1
		end
	end)
end

function BubbleWrap.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return BubbleWrap
