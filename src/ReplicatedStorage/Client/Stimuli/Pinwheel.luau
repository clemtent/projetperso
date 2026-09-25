--[[
	Pinwheel (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Pinwheel

	Un moulin à vent en papier illustré, planté dans un petit pot "kawaii"
	sur une colline, devant un ciel pastel (soleil, nuages qui passent).
	  - 4 pales vernies : grand triangle ombré (dégradé) + rabat plus clair
	    (le "pli" de la feuille), ligne de pliure brillante, petits pois ;
	    moyeu en perle avec reflet.
	  - Bâton en bois (dégradé + veines), pot en terre cuite avec un
	    visage, terre, deux feuilles et une petite fleur.
	  - Tourne en continu, avec des coups de vent de temps en temps. Plus
	    ça tourne vite, plus un disque "flou" coloré apparaît et des
	    lignes de vent traversent la carte (réserve recyclée, aucune
	    création d'instance par image).
	  - Clic / toucher = on souffle dessus : grosse accélération qui retombe
	    doucement, étincelles autour du moyeu... et à très haute vitesse, il
	    essaie de décoller. Chaque souffle envoie Interact("Spin") (limité
	    côté client à la recharge du serveur) ; le bonus arrive par
	    OnBonus("Spin").
	  - Pastille "compteur" en haut à gauche : petit cadran dont l'aiguille
	    et la couleur suivent la vitesse, et les tours / minute.
]]

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Pinwheel = {}
Pinwheel.Slot = "CL"

local BLADE = 42 -- côté du carré d'une pale (portée = BLADE * √2)
local BASE_SPEED = 70 -- degrés / seconde au repos
local BOOST = 540 -- ajout de vitesse par souffle
local MAX_SPEED = 2600
local DECAY = 0.9 -- vitesse de retour au calme
local WIND_POOL = 6 -- lignes de vent recyclées
local SPARKLE_POOL = 6 -- étincelles recyclées

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local BLADE_COLORS = {
	Color3.fromRGB(255, 84, 112), -- framboise
	Color3.fromRGB(255, 196, 46), -- miel
	Color3.fromRGB(64, 156, 255), -- ciel
	Color3.fromRGB(70, 206, 140), -- menthe
}

local LIFT_TEXTS = {
	en = { "It's gonna take off! 🚁", "Hold on tight!", "Too much wind!!", "WHOOOOSH" },
	fr = { "Il va décoller ! 🚁", "Accroche-toi !", "Trop de vent !!", "WOUUUSH" },
}

-- Transparence "demi-carré" : une moitié opaque, l'autre invisible (bord net)
local function halfTransparency(opaqueFirst: boolean): NumberSequence
	local a, b = 0, 1
	if not opaqueFirst then
		a, b = 1, 0
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, a),
		NumberSequenceKeypoint.new(0.495, a),
		NumberSequenceKeypoint.new(0.505, b),
		NumberSequenceKeypoint.new(1, b),
	})
end

-- Trait qui s'estompe aux deux bouts (lignes de vent, pliures)
local FADE_ENDS = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.3, 0.1),
	NumberSequenceKeypoint.new(0.7, 0.1),
	NumberSequenceKeypoint.new(1, 1),
})

function Pinwheel.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()
	local spinConfig = ctx.Config.Interactions.Spin
	local cooldown = (spinConfig and spinConfig.Cooldown) or 2

	local width = container.Size.X.Offset > 0 and container.Size.X.Offset or 170
	local height = container.Size.Y.Offset > 0 and container.Size.Y.Offset or 170
	local hubX, hubY = width / 2, math.floor(height * 0.41)
	local reach = math.ceil(BLADE * math.sqrt(2))

	-- Texte flottant dessiné dans le calque Overlay : il monte de 100 px et
	-- serait coupé par le slot (ClipsDescendants). `point` = position en
	-- pixels "design" dans `guiObject` (qui fait `designW` de large).
	local function floatOnOverlay(guiObject: GuiObject, designW: number, point: Vector2, text: string, color: Color3?, size: number?)
		local ratio = guiObject.AbsoluteSize.X / math.max(1, designW)
		local canvas = ctx.Interface.ScreenToCanvas(guiObject.AbsolutePosition + point * ratio)
		ctx.FloatText(ctx.Overlay, UDim2.fromOffset(canvas.X, canvas.Y), text, color, size)
	end

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Petit cadre sans bordure
	local function frame(props: { [string]: any }): Frame
		props.BorderSizePixel = 0
		return Create("Frame", props)
	end

	-- Cadre centré sur (x, y)
	local function centered(props: { [string]: any }, x: number, y: number, w: number, h: number): Frame
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.fromOffset(x, y)
		props.Size = UDim2.fromOffset(w, h)
		return frame(props)
	end

	local function round(guiObject: GuiObject)
		UIUtil.Corner(guiObject, UDim.new(1, 0))
	end

	------------------------------------------------------------------
	-- Carte : ciel pastel, soleil, nuages, collines
	------------------------------------------------------------------
	local card = frame({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		Parent = container,
	})
	UIUtil.Corner(card, 18)
	UIUtil.Stroke(card, Theme.Colors.CardBorder, 2)
	UIUtil.Gradient(card, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(148, 204, 255)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(214, 232, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 226, 234)),
	}), 90)
	local cardScale = Create("UIScale", { Parent = card })

	-- Soleil (halo qui respire)
	local sunGlow = centered({ Name = "SunGlow", BackgroundColor3 = Color3.fromRGB(255, 240, 170), BackgroundTransparency = 0.6, ZIndex = 1, Parent = card }, width - 24, 24, 46, 46)
	round(sunGlow)
	local sun = centered({ Name = "Sun", BackgroundColor3 = Color3.fromRGB(255, 214, 90), ZIndex = 1, Parent = card }, width - 24, 24, 22, 22)
	round(sun)
	UIUtil.Gradient(sun, ColorSequence.new(Color3.fromRGB(255, 246, 190), Color3.fromRGB(255, 200, 80)), 45)

	-- Nuages (3 boules chacun) qui passent lentement
	local clouds = {}
	for i = 1, 2 do
		local cloud = centered({
			Name = "Cloud",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.05,
			ZIndex = 1,
			Parent = card,
		}, 0, 0, i == 1 and 40 or 32, i == 1 and 13 or 11)
		round(cloud)
		for p = 1, 2 do
			local puff = frame({
				Name = "Puff",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(p == 1 and 0.36 or 0.64, 0.55),
				Size = UDim2.fromScale(p == 1 and 0.46 or 0.36, p == 1 and 1.35 or 1.05),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.05,
				ZIndex = 1,
				Parent = cloud,
			})
			round(puff)
		end
		table.insert(clouds, {
			Frame = cloud,
			X = width * (i == 1 and 0.22 or 0.7),
			Y = i == 1 and 22 or 50,
			Speed = random:NextNumber(3, 6),
		})
	end

	-- Collines (une claire au fond, une plus foncée devant)
	local farHill = centered({ Name = "FarHill", BackgroundColor3 = Color3.fromRGB(150, 222, 150), ZIndex = 2, Parent = card }, width * 0.18, height + 14, 170, 70)
	round(farHill)
	local hill = centered({ Name = "Hill", BackgroundColor3 = WHITE, ZIndex = 2, Parent = card }, width * 0.62, height + 22, 240, 80)
	round(hill)
	UIUtil.Gradient(hill, ColorSequence.new(Color3.fromRGB(120, 214, 120), Color3.fromRGB(62, 160, 90)), 90)

	------------------------------------------------------------------
	-- Pot, terre, plante et bâton en bois
	------------------------------------------------------------------
	local potTop = height - 38
	local stick = frame({
		Name = "Stick",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(hubX, hubY),
		Size = UDim2.fromOffset(7, potTop - hubY + 6),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(stick, 3)
	UIUtil.Gradient(stick, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(246, 214, 160)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(226, 176, 110)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(158, 104, 58)),
	}), 0)
	-- Veines du bois
	for i, spec in ipairs({ { 2, 0.15, 0.55 }, { 4.5, 0.4, 0.5 } }) do
		frame({
			Name = "Grain" .. i,
			Position = UDim2.new(0, spec[1], spec[2], 0),
			Size = UDim2.new(0, 1, spec[3], 0),
			BackgroundColor3 = Color3.fromRGB(130, 82, 40),
			BackgroundTransparency = 0.55,
			ZIndex = 3,
			Parent = stick,
		})
	end

	-- Plante : deux feuilles + une petite fleur sur sa tige
	local LEAF = ColorSequence.new(Color3.fromRGB(150, 230, 120), Color3.fromRGB(56, 160, 80))
	for side = -1, 1, 2 do
		local leaf = frame({
			Name = "Leaf",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(hubX + side * 12, potTop + 3),
			Size = UDim2.fromOffset(10, 22),
			Rotation = side * 38,
			BackgroundColor3 = WHITE,
			ZIndex = 4,
			Parent = card,
		})
		round(leaf)
		UIUtil.Gradient(leaf, LEAF, 90)
	end
	local flowerX, flowerY = hubX - 22, potTop - 24
	frame({
		Name = "Stem",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(flowerX + 2, flowerY),
		Size = UDim2.fromOffset(2, potTop - flowerY + 2),
		Rotation = -10,
		BackgroundColor3 = Color3.fromRGB(70, 170, 90),
		ZIndex = 4,
		Parent = card,
	})
	local flower = centered({ Name = "Flower", BackgroundTransparency = 1, ZIndex = 5, Parent = card }, flowerX, flowerY, 16, 16)
	for p = 0, 3 do
		local a = math.rad(p * 90 + 45)
		local petal = centered({
			Name = "Petal",
			BackgroundColor3 = Color3.fromRGB(255, 150, 196),
			ZIndex = 5,
			Parent = flower,
		}, 8 + math.cos(a) * 4, 8 + math.sin(a) * 4, 8, 8)
		round(petal)
	end
	local flowerHeart = centered({ Name = "Heart", BackgroundColor3 = Color3.fromRGB(255, 220, 80), ZIndex = 6, Parent = flower }, 8, 8, 6, 6)
	round(flowerHeart)

	-- Pot en terre cuite (rebord + corps + terre + petit visage)
	local TERRACOTTA = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(246, 160, 116)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(222, 118, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 82, 56)),
	})
	local potBody = frame({
		Name = "Pot",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(hubX, potTop + 6),
		Size = UDim2.fromOffset(40, 26),
		BackgroundColor3 = WHITE,
		ZIndex = 5,
		Parent = card,
	})
	UIUtil.Corner(potBody, 9)
	UIUtil.Gradient(potBody, TERRACOTTA, 0)
	UIUtil.Stroke(potBody, Color3.fromRGB(120, 60, 40), 1.5, 0.35)
	-- Visage "kawaii" peint sur le pot
	for side = -1, 1, 2 do
		local eye = centered({ Name = "Eye", BackgroundColor3 = Color3.fromRGB(80, 40, 36), ZIndex = 6, Parent = potBody }, 20 + side * 7, 12, 3.5, 4)
		round(eye)
	end
	local smile = centered({ Name = "Smile", BackgroundTransparency = 1, ZIndex = 6, Parent = potBody }, 20, 14, 7, 7)
	round(smile)
	local smileStroke = UIUtil.Stroke(smile, Color3.fromRGB(80, 40, 36), 1.5, 0)
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.55, 1),
			NumberSequenceKeypoint.new(0.62, 0),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = smileStroke,
	})

	local rim = frame({
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(hubX, potTop),
		Size = UDim2.fromOffset(48, 10),
		BackgroundColor3 = WHITE,
		ZIndex = 6,
		Parent = card,
	})
	UIUtil.Corner(rim, 4)
	UIUtil.Gradient(rim, ColorSequence.new(Color3.fromRGB(250, 170, 126), Color3.fromRGB(196, 96, 64)), 90)
	UIUtil.Stroke(rim, Color3.fromRGB(120, 60, 40), 1.5, 0.35)
	local soil = centered({ Name = "Soil", BackgroundColor3 = Color3.fromRGB(92, 58, 42), ZIndex = 6, Parent = rim }, 24, 2, 38, 5)
	round(soil)

	------------------------------------------------------------------
	-- Rotor : 4 pales (triangle ombré + rabat clair + pliure + pois)
	------------------------------------------------------------------
	local rotorHolder = frame({
		Name = "RotorHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(hubX, hubY),
		Size = UDim2.fromOffset(reach * 2, reach * 2),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = card,
	})
	-- Ombre douce de la roue sur le ciel
	local rotorShadow = centered({
		Name = "Shadow",
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.93,
		ZIndex = 1,
		Parent = rotorHolder,
	}, reach + 3, reach + 5, reach * 1.7, reach * 1.7)
	round(rotorShadow)

	local rotor = frame({
		Name = "Rotor",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = rotorHolder,
	})
	local foldSize = math.floor(BLADE * 0.8)
	for index, color in ipairs(BLADE_COLORS) do
		local bladeHolder = frame({
			Name = "Blade" .. index,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Rotation = (index - 1) * 90,
			ZIndex = 2,
			Parent = rotor,
		})
		-- Triangle principal (moitié bas-gauche du carré, sommet au moyeu) :
		-- sombre dans le creux de la courbure, vif près de la pliure
		local main = frame({
			Name = "Main",
			Position = UDim2.fromOffset(reach, reach),
			Size = UDim2.fromOffset(BLADE, BLADE),
			BackgroundColor3 = WHITE,
			ZIndex = 2,
			Parent = bladeHolder,
		})
		local mainGradient = UIUtil.Gradient(main, ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(BLACK, 0.3)),
			ColorSequenceKeypoint.new(0.3, color),
			ColorSequenceKeypoint.new(0.5, color:Lerp(WHITE, 0.25)),
			ColorSequenceKeypoint.new(1, color),
		}), -45)
		mainGradient.Transparency = halfTransparency(true)
		-- Petits pois blancs (dans le triangle : y > x)
		for d, spec in ipairs({ { 0.24, 0.7, 6 }, { 0.5, 0.86, 4 } }) do
			local dot = centered({
				Name = "Dot" .. d,
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.3,
				ZIndex = 3,
				Parent = main,
			}, BLADE * spec[1], BLADE * spec[2], spec[3], spec[3])
			round(dot)
		end
		-- Rabat (moitié haut-droite d'un carré plus petit) : papier plié, plus clair
		local fold = frame({
			Name = "Fold",
			Position = UDim2.fromOffset(reach, reach),
			Size = UDim2.fromOffset(foldSize, foldSize),
			BackgroundColor3 = WHITE,
			ZIndex = 4,
			Parent = bladeHolder,
		})
		local foldGradient = UIUtil.Gradient(fold, ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.7)),
			ColorSequenceKeypoint.new(0.5, color:Lerp(WHITE, 0.62)),
			ColorSequenceKeypoint.new(1, color:Lerp(WHITE, 0.18)),
		}), -45)
		foldGradient.Transparency = halfTransparency(false)
		-- Pliure brillante (diagonale du moyeu vers la pointe)
		local creaseLength = foldSize * math.sqrt(2)
		local crease = frame({
			Name = "Crease",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(reach + foldSize / 2 - creaseLength / 2, reach + foldSize / 2),
			Size = UDim2.fromOffset(creaseLength, 2),
			Rotation = 45,
			BackgroundColor3 = WHITE,
			ZIndex = 5,
			Parent = bladeHolder,
		})
		UIUtil.Create("UIGradient", { Transparency = FADE_ENDS, Parent = crease })
	end

	-- Disque "flou" coloré (apparaît quand ça tourne vite)
	local blur = centered({
		Name = "Blur",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = rotorHolder,
	}, reach, reach, reach * 1.85, reach * 1.85)
	round(blur)
	local blurColors = {}
	for i, color in ipairs(BLADE_COLORS) do
		table.insert(blurColors, ColorSequenceKeypoint.new((i - 1) / #BLADE_COLORS, color:Lerp(WHITE, 0.35)))
	end
	table.insert(blurColors, ColorSequenceKeypoint.new(1, BLADE_COLORS[1]:Lerp(WHITE, 0.35)))
	local blurGradient = UIUtil.Gradient(blur, ColorSequence.new(blurColors), 0)
	local blurStroke = UIUtil.Stroke(blur, WHITE, 3, 1)

	-- Moyeu : rosace + perle vernie + reflet
	local rosette = centered({ Name = "Rosette", BackgroundColor3 = WHITE, BackgroundTransparency = 0.15, ZIndex = 7, Parent = rotorHolder }, reach, reach, 24, 24)
	round(rosette)
	local hub = centered({ Name = "Hub", BackgroundColor3 = WHITE, ZIndex = 8, Parent = rotorHolder }, reach, reach, 16, 16)
	round(hub)
	UIUtil.Gradient(hub, ColorSequence.new(Color3.fromRGB(255, 236, 244), Color3.fromRGB(236, 90, 130)), 45)
	UIUtil.Stroke(hub, Color3.fromRGB(120, 30, 60), 1.5, 0.2)
	local hubShine = centered({ Name = "Shine", BackgroundColor3 = WHITE, BackgroundTransparency = 0.1, ZIndex = 9, Parent = hub }, 5.5, 5.5, 5, 4)
	round(hubShine)

	------------------------------------------------------------------
	-- Lignes de vent + étincelles (réserves recyclées)
	------------------------------------------------------------------
	local winds = {}
	for i = 1, WIND_POOL do
		local line = frame({
			Name = "Wind" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(30, 2),
			BackgroundColor3 = Color3.fromRGB(246, 252, 255),
			Visible = false,
			ZIndex = 11,
			Parent = card,
		})
		round(line)
		UIUtil.Create("UIGradient", { Transparency = FADE_ENDS, Parent = line })
		winds[i] = { Frame = line, Active = false, X = 0, Y = 0, Speed = 0, Life = 0, MaxLife = 1, Phase = 0 }
	end

	local function spawnWind()
		for _, wind in ipairs(winds) do
			if not wind.Active then
				wind.Active = true
				wind.X = -20
				wind.Y = random:NextNumber(12, height - 50)
				wind.Speed = random:NextNumber(220, 320)
				wind.MaxLife = (width + 40) / wind.Speed
				wind.Life = 0
				wind.Phase = random:NextNumber(0, math.pi * 2)
				wind.Frame.Size = UDim2.fromOffset(random:NextNumber(22, 40), 2)
				wind.Frame.Visible = true
				return
			end
		end
	end

	local sparkles: { TextLabel } = {}
	local SPARKLE_COLORS = { Color3.fromRGB(255, 214, 60), WHITE, Color3.fromRGB(255, 150, 196) }
	for i = 1, SPARKLE_POOL do
		local sparkle = UIUtil.Create("TextLabel", {
			Name = "Sparkle" .. i,
			Text = "✦",
			Font = Theme.Fonts.Title,
			TextSize = 16,
			TextColor3 = SPARKLE_COLORS[(i - 1) % #SPARKLE_COLORS + 1],
			TextStrokeColor3 = Color3.fromRGB(200, 120, 40),
			TextStrokeTransparency = 0.6,
			TextTransparency = 1,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(hubX, hubY),
			Size = UDim2.fromOffset(20, 20),
			ZIndex = 13,
			Parent = card,
		})
		sparkles[i] = sparkle
	end
	local nextSparkle = 1

	local function sparkleBurst(count: number)
		for _ = 1, count do
			local sparkle = sparkles[nextSparkle]
			nextSparkle = nextSparkle % #sparkles + 1
			local a = random:NextNumber(0, math.pi * 2)
			local distance = random:NextNumber(34, 56)
			sparkle.Position = UDim2.fromOffset(hubX, hubY)
			sparkle.TextTransparency = 0
			sparkle.TextStrokeTransparency = 0.6
			sparkle.TextSize = random:NextInteger(12, 18)
			sparkle.Rotation = 0
			UIUtil.Tween(sparkle, random:NextNumber(0.45, 0.65), {
				Position = UDim2.fromOffset(hubX + math.cos(a) * distance, hubY + math.sin(a) * distance),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				Rotation = random:NextNumber(-120, 120),
				TextSize = 6,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end

	------------------------------------------------------------------
	-- Pastilles : compteur (cadran + tr/min), indice, décollage
	------------------------------------------------------------------
	local chip = frame({
		Name = "RpmChip",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(72, 18),
		BackgroundColor3 = Color3.fromRGB(34, 28, 58),
		BackgroundTransparency = 0.08,
		ZIndex = 12,
		Parent = card,
	})
	round(chip)
	UIUtil.Gradient(chip, ColorSequence.new(WHITE, Color3.fromRGB(170, 170, 190)), 90)
	UIUtil.Stroke(chip, WHITE, 1, 0.55)
	local dial = centered({ Name = "Dial", BackgroundColor3 = Color3.fromRGB(18, 14, 34), ZIndex = 12, Parent = chip }, 10, 9, 12, 12)
	round(dial)
	local dialStroke = UIUtil.Stroke(dial, Theme.Colors.Green, 1.5, 0)
	local needle = frame({
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1.5, 5),
		BackgroundColor3 = WHITE,
		ZIndex = 13,
		Parent = dial,
	})
	local rpmFormat = Locale.T("%d rpm")
	local rpmLabel = UIUtil.Label({
		Name = "Rpm",
		Text = Locale.T("%d rpm", 12),
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 2),
		Size = UDim2.new(1, -24, 1, -4),
		MaxTextSize = 11,
		ZIndex = 13,
		Parent = chip,
	})

	local hint = UIUtil.Label({
		Name = "Hint",
		Text = Locale.T("Blow! 🌬️"),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(width - 6, height - 24),
		Size = UDim2.fromOffset(54, 18),
		MaxTextSize = 11,
		ZIndex = 12,
		Parent = card,
	})
	round(hint)
	local hintStroke = UIUtil.Stroke(hint, Theme.Colors.Border, 1, 0.5)

	local liftLabel = UIUtil.Label({
		Name = "Lift",
		Text = "",
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Theme.Colors.Yellow,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(hubX, 28),
		Size = UDim2.fromOffset(width - 16, 18),
		MaxTextSize = 15,
		ZIndex = 14,
		Parent = card,
	})
	local liftStroke = UIUtil.Stroke(liftLabel, Theme.Colors.TextDark, 2, 1)
	liftStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	------------------------------------------------------------------
	-- Interaction (toute la carte est cliquable)
	------------------------------------------------------------------
	local button = Create("TextButton", {
		Name = "Blow",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 20,
		Parent = card,
	})

	local speed = BASE_SPEED
	local angle = random:NextNumber(0, 90)
	local lastInteract = -math.huge
	local gustTimer = random:NextNumber(5, 10)
	local rpmTimer = 0
	local windTimer = 0
	local lifting = false
	local blown = false
	local clock = 0

	local function blow()
		speed = math.min(MAX_SPEED, speed + BOOST)
		cardScale.Scale = 0.94
		UIUtil.Tween(cardScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Open", random:NextNumber(1.1, 1.4))
		local fx = effectsOn()
		for _ = 1, fx and 3 or 1 do
			spawnWind()
		end
		sparkleBurst(fx and 4 or 2)
		-- Petit "pop" du moyeu
		hub.Size = UDim2.fromOffset(21, 21)
		UIUtil.Tween(hub, 0.3, { Size = UDim2.fromOffset(16, 16) }, Enum.EasingStyle.Back)
		if not blown then
			blown = true
			UIUtil.Tween(hint, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
			UIUtil.Tween(hintStroke, 0.3, { Transparency = 1 })
		end
		local now = os.clock()
		if now - lastInteract >= cooldown then
			lastInteract = now
			ctx.Interact("Spin")
		end
	end
	ctx.Connect(button.Activated, blow)

	ctx.OnBonus("Spin", function(payload)
		local amount = tonumber(payload.Amount)
		if amount then
			floatOnOverlay(container, width, Vector2.new(hubX, hubY - 30), "+" .. ctx.Format.Format(amount), Theme.Colors.Gold, 26)
		end
	end)

	------------------------------------------------------------------
	-- Animation
	------------------------------------------------------------------
	local restPosition = UDim2.fromOffset(hubX, hubY)
	local SLOW_COLOR = Theme.Colors.Green
	local MID_COLOR = Theme.Colors.Yellow
	local FAST_COLOR = Theme.Colors.Red

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt
		local fx = effectsOn()

		-- Coups de vent naturels
		gustTimer -= dt
		if gustTimer <= 0 then
			gustTimer = random:NextNumber(6, 12)
			speed = math.min(MAX_SPEED, speed + random:NextNumber(150, 300))
			if fx then
				spawnWind()
				spawnWind()
			end
		end

		-- Retour progressif au calme
		speed = BASE_SPEED + (speed - BASE_SPEED) * math.exp(-dt * DECAY)
		angle = (angle + speed * dt) % 360
		rotor.Rotation = angle

		-- Disque flou coloré (tourne avec la roue)
		local fast = math.clamp((speed - 450) / 1500, 0, 1)
		blur.BackgroundTransparency = 1 - fast * 0.5
		blurStroke.Transparency = 1 - fast * 0.6
		blurGradient.Rotation = angle

		-- Lignes de vent continues quand ça tourne vite
		if fx and speed > 700 then
			windTimer -= dt * (speed / 900)
			if windTimer <= 0 then
				windTimer = random:NextNumber(0.16, 0.3)
				spawnWind()
			end
		end
		for _, wind in ipairs(winds) do
			if wind.Active then
				wind.Life += dt
				wind.X += wind.Speed * dt
				local life = wind.Life / wind.MaxLife
				if life >= 1 then
					wind.Active = false
					wind.Frame.Visible = false
				else
					local wave = math.sin(wind.Phase + wind.Life * 9) * 4
					wind.Frame.Position = UDim2.fromOffset(wind.X, wind.Y + wave)
					wind.Frame.Rotation = math.cos(wind.Phase + wind.Life * 9) * 8
					wind.Frame.BackgroundTransparency = 0.15 + 0.85 * life * life
				end
			end
		end

		-- Décollage (tremble et monte un peu quand c'est très rapide)
		local liftAmount = math.clamp((speed - 1500) / 1000, 0, 1)
		if liftAmount > 0 then
			rotorHolder.Position = UDim2.fromOffset(
				hubX + random:NextNumber(-1.5, 1.5) * liftAmount,
				hubY - liftAmount * 6 + random:NextNumber(-1.5, 1.5) * liftAmount
			)
			stick.Rotation = math.sin(clock * 40) * 2 * liftAmount
		elseif rotorHolder.Position ~= restPosition then
			rotorHolder.Position = restPosition
			stick.Rotation = 0
		end
		if liftAmount > 0.3 and not lifting then
			lifting = true
			local liftTexts = Locale.Pick(LIFT_TEXTS)
			liftLabel.Text = liftTexts[random:NextInteger(1, #liftTexts)]
			UIUtil.Tween(liftLabel, 0.2, { TextTransparency = 0 })
			UIUtil.Tween(liftStroke, 0.2, { Transparency = 0 })
		elseif liftAmount < 0.1 and lifting then
			lifting = false
			UIUtil.Tween(liftLabel, 0.4, { TextTransparency = 1 })
			UIUtil.Tween(liftStroke, 0.4, { Transparency = 1 })
		end

		-- Nuages, soleil, fleur qui se balance dans le vent
		for _, cloud in ipairs(clouds) do
			cloud.X += cloud.Speed * dt
			if cloud.X > width + 30 then
				cloud.X = -30
			end
			cloud.Frame.Position = UDim2.fromOffset(cloud.X, cloud.Y)
		end
		sunGlow.BackgroundTransparency = 0.6 + 0.12 * math.sin(clock * 1.3)
		flower.Rotation = math.sin(clock * (1.5 + fast * 6)) * (6 + fast * 14)

		-- Compteur : aiguille, couleur du cadran, tours / minute (degrés/s ÷ 6)
		local ratio = math.clamp((speed - BASE_SPEED) / (MAX_SPEED - BASE_SPEED), 0, 1)
		needle.Rotation = -120 + ratio * 240
		rpmTimer -= dt
		if rpmTimer <= 0 then
			rpmTimer = 0.12
			rpmLabel.Text = string.format(rpmFormat, math.floor(speed / 6 + 0.5))
			dialStroke.Color = ratio < 0.5 and SLOW_COLOR:Lerp(MID_COLOR, ratio * 2) or MID_COLOR:Lerp(FAST_COLOR, (ratio - 0.5) * 2)
		end

		-- L'indice "Souffle !" se dandine tant qu'on n'a pas soufflé
		if not blown then
			hint.Rotation = math.sin(clock * 3) * 4
		end
	end)
end

function Pinwheel.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Pinwheel
