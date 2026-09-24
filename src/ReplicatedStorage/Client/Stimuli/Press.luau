--[[
	Press (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Press

	Une presse hydraulique qui écrase des trucs, en boucle, et c'est très
	satisfaisant :
	  - un objet arrive par le tapis roulant (piles de macarons colorés,
	    pastèque, canard en plastique, gâteau, éponge...) ;
	  - le piston descend lentement, l'objet se tasse, la machine tremble,
	    le manomètre grimpe dans le rouge... puis CRUNCH ! (miettes,
	    vapeur, secousse, onomatopée) ;
	  - la galette obtenue part sur le tas à gauche, qui finit à la poubelle,
	    et la file d'attente à droite se remplit toute seule.
	La vitesse augmente avec le niveau de l'amélioration "Presse hydraulique".
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

-- Durées de base (niveau 1), divisées par le facteur de vitesse
local DURATIONS = {
	Load = 0.55,
	Descend = 1.25,
	Squeeze = 0.5,
	Crunch = 0.09,
	Hold = 0.4,
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

-- Petite fonction utilitaire : mélange de deux couleurs
local function mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
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

local function easeInOut(t: number): number
	return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
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

	local function speedFactor(): number
		local level = math.max(1, ctx.GetLevel("Press"))
		return 1 + (level - 1) * 0.2
	end

	------------------------------------------------------------------
	-- Carte + "rig" (tout ce qui tremble)
	------------------------------------------------------------------
	local card = Create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Card,
		BorderSizePixel = 0,
		Parent = container,
	})
	UIUtil.Corner(card, 18)
	UIUtil.Stroke(card, Theme.Colors.CardBorder, 2)
	UIUtil.Gradient(card, ColorSequence.new(Color3.fromRGB(250, 251, 253), Color3.fromRGB(214, 221, 232)), 90)

	local rig = Create("Frame", {
		Name = "Rig",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})

	local function box(props: { [string]: any }, radius: number?): Frame
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

	-- En-tête
	UIUtil.Label({
		Text = "🗜️ PRESSE HYDRAULIQUE",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.fromOffset(200, 20),
		MaxTextSize = 16,
		ZIndex = 12,
		Parent = card,
	})
	local speedPill = UIUtil.Label({
		Text = "⚡ x1",
		Font = Theme.Fonts.Number,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Colors.Orange,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(216, 8),
		Size = UDim2.fromOffset(58, 18),
		MaxTextSize = 13,
		ZIndex = 12,
		Parent = card,
	})
	UIUtil.Corner(speedPill, UDim.new(1, 0))
	local counterLabel = UIUtil.Label({
		Text = "💥 0",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 6),
		Size = UDim2.fromOffset(96, 22),
		MaxTextSize = 18,
		ZIndex = 12,
		Parent = card,
	})
	local counterScale = Create("UIScale", { Parent = counterLabel })

	------------------------------------------------------------------
	-- La machine
	------------------------------------------------------------------
	local steel = Color3.fromRGB(96, 104, 120)
	local steelDark = Color3.fromRGB(58, 62, 74)
	local hazardYellow = Color3.fromRGB(255, 200, 30)
	local hazardBlack = Color3.fromRGB(34, 34, 40)
	local metalShine = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 176, 190)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 156, 170)),
	})

	-- Colonnes
	for _, x in ipairs({ MX - 110, MX + 94 }) do
		local column = box({ Position = UDim2.fromOffset(x, 40), Size = UDim2.fromOffset(16, ANVIL_Y - 40), BackgroundColor3 = steel, ZIndex = 2 }, 3)
		UIUtil.Gradient(column, metalShine, 0)
	end

	-- Traverse du haut (rayures de sécurité)
	local beam = box({ Position = UDim2.fromOffset(MX - 120, 34), Size = UDim2.fromOffset(240, 26), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 7 }, 6)
	UIUtil.Gradient(beam, stripes(10, hazardYellow, hazardBlack), 35)
	UIUtil.Stroke(beam, hazardBlack, 2)

	-- Vérin (boîtier + tige)
	local housing = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, 56), Size = UDim2.fromOffset(46, 16), BackgroundColor3 = steelDark, ZIndex = 8 }, 4)
	UIUtil.Gradient(housing, metalShine, 0)
	local rod = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, 66), Size = UDim2.fromOffset(18, 10), BackgroundColor3 = Color3.fromRGB(215, 220, 230), ZIndex = 5 })
	UIUtil.Gradient(rod, metalShine, 0)

	-- Plateau
	local plate = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, PLATE_TOP), Size = UDim2.fromOffset(PLATE_W, PLATE_H), BackgroundColor3 = steelDark, ZIndex = 6 }, 5)
	UIUtil.Gradient(plate, ColorSequence.new(Color3.fromRGB(150, 158, 175), Color3.fromRGB(70, 74, 88)), 90)
	local plateStripe = box({ Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 0, 6), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 7, Parent = plate }, 2)
	UIUtil.Gradient(plateStripe, stripes(10, hazardYellow, hazardBlack), 35)

	-- Manomètre (aiguille qui monte dans le rouge)
	local gauge = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX + 84, 47), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 9 }, 11)
	UIUtil.Stroke(gauge, hazardBlack, 2)
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
	local base = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, ANVIL_Y), Size = UDim2.fromOffset(250, 28), BackgroundColor3 = steelDark, ZIndex = 3 }, 5)
	UIUtil.Gradient(base, ColorSequence.new(Color3.fromRGB(130, 136, 150), Color3.fromRGB(50, 54, 64)), 90)
	local baseStripe = box({ Position = UDim2.fromOffset(4, 0), Size = UDim2.new(1, -8, 0, 5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4, Parent = base })
	UIUtil.Gradient(baseStripe, stripes(10, hazardYellow, hazardBlack), 35)
	local led = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -14, 0.6, 0), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Theme.Colors.Green, ZIndex = 5, Parent = base }, 4)

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
	local belt = box({ Position = UDim2.fromOffset(296, QUEUE_Y), Size = UDim2.fromOffset(84, 10), BackgroundColor3 = hazardBlack, ClipsDescendants = true, ZIndex = 3 })
	local beltStripes = box({ Size = UDim2.fromOffset(BELT_STRIPES_W, 10), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3, Parent = belt })
	UIUtil.Gradient(beltStripes, stripes(10, Color3.fromRGB(78, 82, 96), Color3.fromRGB(40, 42, 50)), 0)
	for _, x in ipairs({ 302, 374 }) do
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, QUEUE_Y + 5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = steel, ZIndex = 4 }, 6)
	end
	box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(338, QUEUE_Y + 10), Size = UDim2.fromOffset(8, 256 - QUEUE_Y - 10), BackgroundColor3 = steel, ZIndex = 2 })

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
	-- Objets à écraser
	------------------------------------------------------------------
	local function randomDef()
		if random:NextNumber() < 0.45 then
			local colors = {}
			for i = 1, 3 do
				colors[i] = MACARON_COLORS[random:NextInteger(1, #MACARON_COLORS)]
			end
			return { Kind = "Macaron", Colors = colors, Color = colors[2], Words = MACARON_WORDS, W = 80, H = 78 }
		end
		local item = EMOJI_ITEMS[random:NextInteger(1, #EMOJI_ITEMS)]
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
			Position = UDim2.fromOffset(QUEUE_X[slot], dropIn and QUEUE_Y - 90 or QUEUE_Y),
			Size = UDim2.fromOffset(def.W * scale, def.H * scale),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = rig,
		})
		local parts = buildVisual(def, holder)
		table.insert(queue, { Def = def, Holder = holder, Parts = parts })
		if dropIn then
			UIUtil.Tween(holder, 0.5, { Position = UDim2.fromOffset(QUEUE_X[slot], QUEUE_Y) }, Enum.EasingStyle.Bounce)
		end
	end
	for _ = 1, #QUEUE_X do
		addToQueue(false)
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

	local function steam()
		for _, dir in ipairs({ -1, 1 }) do
			local puff = UIUtil.Label({
				Text = "💨",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(MX + dir * 70, ANVIL_Y - 14),
				Size = UDim2.fromOffset(30, 30),
				Rotation = dir < 0 and 180 or 0,
				MaxTextSize = 28,
				ZIndex = 11,
				Parent = rig,
			})
			UIUtil.Tween(puff, 0.6, { Position = UDim2.fromOffset(MX + dir * 118, ANVIL_Y - 30), TextTransparency = 1 })
			Debris:AddItem(puff, 0.65)
		end
	end

	local function shout(text: string, turbo: boolean)
		local long = #text > 12
		local label = UIUtil.Label({
			Text = text,
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = turbo and Color3.fromRGB(255, 90, 60) or Color3.fromRGB(255, 220, 50),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(MX, 124),
			Size = UDim2.fromOffset(230, long and 30 or 46),
			Rotation = random:NextNumber(-10, 10),
			MaxTextSize = long and 24 or 42,
			ZIndex = 13,
			Parent = rig,
		})
		local stroke = UIUtil.Stroke(label, hazardBlack, 3)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		local scale = Create("UIScale", { Scale = 0.3, Parent = label })
		UIUtil.Tween(scale, 0.22, { Scale = 1.1 }, Enum.EasingStyle.Back)
		task.delay(0.45, function()
			if label.Parent then
				UIUtil.Tween(label, 0.4, { Position = UDim2.fromOffset(MX, 96), TextTransparency = 1 })
				UIUtil.Tween(stroke, 0.4, { Transparency = 1 })
			end
		end)
		Debris:AddItem(label, 0.9)
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
		speedPill.Text = "⚡ x" .. (math.floor(factor * 10 + 0.5) / 10)
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
			UIUtil.Tween(other.Holder, 0.35, { Position = UDim2.fromOffset(QUEUE_X[i], QUEUE_Y) }, Enum.EasingStyle.Quad)
		end
		addToQueue(true)
	end

	-- Le moment CRUNCH
	local function onCrunch()
		if not current then
			return
		end
		local def = current.Def
		local parts = current.Parts
		local effects = effectsOn()
		crushed += 1
		counterLabel.Text = "💥 " .. crushed
		counterScale.Scale = 1.3
		UIUtil.Tween(counterScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Crush", random:NextNumber(0.85, 1.15))
		shakeTime = turbo and 0.35 or 0.22

		local words = def.Words
		local text = words[random:NextInteger(1, #words)]
		if turbo then
			text = "TURBO " .. text
		end
		shout(text, turbo)

		local origin = Vector2.new(MX, ANVIL_Y - 10)
		crumbs(def.Colors, effects and (turbo and 16 or 11) or 4, origin)
		if effects then
			steam()
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
			shout("...elle est revenue", false)
			task.delay(0.75, function()
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
	-- Boucle
	------------------------------------------------------------------
	loadNext()

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
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
				local height = def.H - squeezeDepth * (t * t)
				current.Holder.Size = UDim2.fromOffset(def.W * (1 + 0.1 * t), height)
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
			if current then
				local def = current.Def
				local startH = def.H - squeezeDepth
				local height = startH + (FLAT_H - startH) * t
				current.Holder.Size = UDim2.fromOffset(def.W * (1.1 + 0.5 * t), height)
				if current.Parts.Label then
					current.Parts.Label.Rotation = 0
				end
				plateY = ANVIL_Y - height - PLATE_H
			else
				plateY = ANVIL_Y - FLAT_H - PLATE_H
			end
			targetPressure = 1
			if t >= 1 then
				setPhase("Hold")
			end
		elseif phase == "Hold" then
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
		led.BackgroundColor3 = (phase == "Squeeze" or phase == "Crunch" or phase == "Hold") and Theme.Colors.Red or Theme.Colors.Green

		-- Tapis roulant
		beltOffset = (beltOffset + dt * 30) % (BELT_STRIPES_W / 5)
		beltStripes.Position = UDim2.fromOffset(-beltOffset, 0)

		-- Secousse
		if shakeTime > 0 then
			shakeTime -= dt
			local strength = math.clamp(shakeTime * 18, 0.6, 4)
			rig.Position = UDim2.fromOffset(random:NextNumber(-strength, strength), random:NextNumber(-strength, strength))
		elseif rig.Position ~= UDim2.new() then
			rig.Position = UDim2.new()
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
