--[[
	Pinwheel (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Pinwheel

	Un moulin à vent en papier planté dans un petit pot : 4 pales colorées
	(triangles obtenus avec des dégradés à bord net) qui tournent en continu,
	avec des coups de vent de temps en temps.
	Clic / toucher = on souffle dessus : grosse accélération qui retombe
	doucement, traits de vent, halo de vitesse... et à très haute vitesse,
	il essaie de décoller. Chaque souffle envoie Interact("Spin") (limité
	côté client à la recharge du serveur) ; le bonus arrive par OnBonus("Spin").
]]

local Debris = game:GetService("Debris")

local Pinwheel = {}
Pinwheel.Slot = "CL"

local BLADE = 44 -- côté du carré d'une pale (portée = BLADE * √2)
local BASE_SPEED = 70 -- degrés / seconde au repos
local BOOST = 540 -- ajout de vitesse par souffle
local MAX_SPEED = 2600
local DECAY = 0.9 -- vitesse de retour au calme

local BLADE_COLORS = {
	Color3.fromRGB(240, 60, 72),
	Color3.fromRGB(255, 205, 40),
	Color3.fromRGB(40, 150, 240),
	Color3.fromRGB(60, 200, 110),
}

local LIFT_TEXTS = { "Il va décoller ! 🚁", "Accroche-toi !", "Trop de vent !!", "WOUUUSH" }

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
	local hubX, hubY = width / 2, math.floor(height * 0.435)
	-- Texte flottant dessiné dans le calque Overlay : il monte de 100 px et
	-- serait coupé par le slot (ClipsDescendants). `point` = position en
	-- pixels "design" dans `guiObject` (qui fait `designW` de large).
	local function floatOnOverlay(guiObject: GuiObject, designW: number, point: Vector2, text: string, color: Color3?, size: number?)
		local ratio = guiObject.AbsoluteSize.X / math.max(1, designW)
		local canvas = ctx.Interface.ScreenToCanvas(guiObject.AbsolutePosition + point * ratio)
		ctx.FloatText(ctx.Overlay, UDim2.fromOffset(canvas.X, canvas.Y), text, color, size)
	end

	local reach = math.ceil(BLADE * math.sqrt(2))

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	------------------------------------------------------------------
	-- Carte (ciel clair)
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
	UIUtil.Gradient(card, ColorSequence.new(Color3.fromRGB(196, 230, 255), Color3.fromRGB(255, 255, 255)), 90)
	local cardScale = Create("UIScale", { Parent = card })

	-- Deux petits nuages qui passent
	local clouds = {}
	for i = 1, 2 do
		local cloud = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(width * (i == 1 and 0.25 or 0.8), i == 1 and 26 or 58),
			Size = UDim2.fromOffset(38, 14),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = card,
		})
		UIUtil.Corner(cloud, UDim.new(1, 0))
		local puff = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.45, 0.6),
			Size = UDim2.fromOffset(20, 16),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = cloud,
		})
		UIUtil.Corner(puff, UDim.new(1, 0))
		table.insert(clouds, { Frame = cloud, X = cloud.Position.X.Offset, Y = cloud.Position.Y.Offset, Speed = random:NextNumber(3, 7) })
	end

	------------------------------------------------------------------
	-- Pot + bâton
	------------------------------------------------------------------
	local potTop = height - 26
	local stick = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(hubX, hubY),
		Size = UDim2.fromOffset(6, potTop - hubY + 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Gradient(stick, ColorSequence.new(Color3.fromRGB(236, 196, 136), Color3.fromRGB(168, 116, 64)), 0)
	local pot = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(hubX, potTop + 4),
		Size = UDim2.fromOffset(38, 20),
		BackgroundColor3 = Color3.fromRGB(208, 112, 72),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(pot, 5)
	UIUtil.Gradient(pot, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)), 0)
	local rim = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(hubX, potTop),
		Size = UDim2.fromOffset(46, 8),
		BackgroundColor3 = Color3.fromRGB(186, 94, 58),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Corner(rim, 3)
	-- Petite pousse (parce que pourquoi pas)
	UIUtil.Label({
		Text = "🌱",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(hubX + 13, potTop + 2),
		Size = UDim2.fromOffset(16, 16),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = card,
	})

	------------------------------------------------------------------
	-- Rotor : 4 pales (triangle principal + petit triangle "pli" plus clair)
	------------------------------------------------------------------
	local rotorHolder = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(hubX, hubY),
		Size = UDim2.fromOffset(reach * 2, reach * 2),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = card,
	})
	local rotor = Create("Frame", {
		Name = "Rotor",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = rotorHolder,
	})
	for index, color in ipairs(BLADE_COLORS) do
		local bladeHolder = Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Rotation = (index - 1) * 90,
			ZIndex = 5,
			Parent = rotor,
		})
		-- Triangle principal (moitié bas-gauche du carré, sommet au moyeu)
		local main = Create("Frame", {
			Position = UDim2.fromOffset(reach, reach),
			Size = UDim2.fromOffset(BLADE, BLADE),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = bladeHolder,
		})
		local mainGradient = UIUtil.Gradient(main, ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.18)), -45)
		mainGradient.Transparency = halfTransparency(true)
		-- Pli (moitié haut-droite d'un carré plus petit, plus clair)
		local foldSize = math.floor(BLADE * 0.72)
		local fold = Create("Frame", {
			Position = UDim2.fromOffset(reach, reach),
			Size = UDim2.fromOffset(foldSize, foldSize),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = bladeHolder,
		})
		local foldGradient = UIUtil.Gradient(fold, ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.55), color:Lerp(Color3.new(1, 1, 1), 0.25)), -45)
		foldGradient.Transparency = halfTransparency(false)
	end

	-- Halo de vitesse (apparaît quand ça tourne vite)
	local blur = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = rotorHolder,
	})
	UIUtil.Corner(blur, UDim.new(1, 0))
	local blurStroke = UIUtil.Stroke(blur, Color3.fromRGB(255, 255, 255), 3, 1)

	-- Moyeu (épingle)
	local hub = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = rotorHolder,
	})
	UIUtil.Corner(hub, UDim.new(1, 0))
	UIUtil.Stroke(hub, Theme.Colors.Border, 2)
	local pin = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Theme.Colors.Red,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = hub,
	})
	UIUtil.Corner(pin, UDim.new(1, 0))

	------------------------------------------------------------------
	-- Textes : vitesse, indice, décollage
	------------------------------------------------------------------
	local rpmLabel = UIUtil.Label({
		Text = "12 tr/min",
		Font = Theme.Fonts.Number,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Colors.Dark,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromOffset(6, height - 22),
		Size = UDim2.fromOffset(54, 16),
		MaxTextSize = 11,
		ZIndex = 12,
		Parent = card,
	})
	UIUtil.Corner(rpmLabel, UDim.new(1, 0))

	local hint = UIUtil.Label({
		Text = "Souffle ! 🌬️",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(width - 6, height - 22),
		Size = UDim2.fromOffset(54, 16),
		MaxTextSize = 11,
		ZIndex = 12,
		Parent = card,
	})
	UIUtil.Corner(hint, UDim.new(1, 0))
	UIUtil.Stroke(hint, Theme.Colors.Border, 1, 0.5)

	local liftLabel = UIUtil.Label({
		Text = "",
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Theme.Colors.Yellow,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(hubX, 3),
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
	local lifting = false
	local blown = false
	local clock = 0

	-- Traits de vent qui traversent la carte
	local function windStreaks(count: number)
		for _ = 1, count do
			local y = hubY + random:NextNumber(-reach * 0.8, reach * 0.8)
			local streak = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(-10, y),
				Size = UDim2.fromOffset(random:NextNumber(18, 34), 3),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				ZIndex = 11,
				Parent = card,
			})
			UIUtil.Corner(streak, UDim.new(1, 0))
			UIUtil.Stroke(streak, Color3.fromRGB(140, 190, 230), 1, 0.3)
			UIUtil.Tween(streak, random:NextNumber(0.35, 0.55), {
				Position = UDim2.fromOffset(width + 20, y + random:NextNumber(-10, 10)),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(streak, 0.6)
		end
	end

	local function blow()
		speed = math.min(MAX_SPEED, speed + BOOST)
		cardScale.Scale = 0.94
		UIUtil.Tween(cardScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Open", random:NextNumber(1.1, 1.4))
		windStreaks(effectsOn() and 3 or 1)
		if not blown then
			blown = true
			UIUtil.Tween(hint, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
			local stroke = hint:FindFirstChildOfClass("UIStroke")
			if stroke then
				UIUtil.Tween(stroke, 0.3, { Transparency = 1 })
			end
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
	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt

		-- Coups de vent naturels
		gustTimer -= dt
		if gustTimer <= 0 then
			gustTimer = random:NextNumber(6, 12)
			speed = math.min(MAX_SPEED, speed + random:NextNumber(150, 300))
			if effectsOn() then
				windStreaks(2)
			end
		end

		-- Retour progressif au calme
		speed = BASE_SPEED + (speed - BASE_SPEED) * math.exp(-dt * DECAY)
		angle = (angle + speed * dt) % 360
		rotor.Rotation = angle

		-- Halo de vitesse
		local fast = math.clamp((speed - 500) / 1600, 0, 1)
		blur.BackgroundTransparency = 1 - fast * 0.35
		blurStroke.Transparency = 1 - fast * 0.7

		-- Décollage (tremble et monte un peu quand c'est très rapide)
		local liftAmount = math.clamp((speed - 1500) / 1000, 0, 1)
		if liftAmount > 0 then
			rotorHolder.Position = UDim2.fromOffset(
				hubX + random:NextNumber(-1.5, 1.5) * liftAmount,
				hubY - liftAmount * 6 + random:NextNumber(-1.5, 1.5) * liftAmount
			)
			stick.Rotation = math.sin(clock * 40) * 2 * liftAmount
		elseif rotorHolder.Position ~= UDim2.fromOffset(hubX, hubY) then
			rotorHolder.Position = UDim2.fromOffset(hubX, hubY)
			stick.Rotation = 0
		end
		if liftAmount > 0.3 and not lifting then
			lifting = true
			liftLabel.Text = LIFT_TEXTS[random:NextInteger(1, #LIFT_TEXTS)]
			UIUtil.Tween(liftLabel, 0.2, { TextTransparency = 0 })
			UIUtil.Tween(liftStroke, 0.2, { Transparency = 0 })
		elseif liftAmount < 0.1 and lifting then
			lifting = false
			UIUtil.Tween(liftLabel, 0.4, { TextTransparency = 1 })
			UIUtil.Tween(liftStroke, 0.4, { Transparency = 1 })
		end

		-- Nuages
		for _, cloud in ipairs(clouds) do
			cloud.X += cloud.Speed * dt
			if cloud.X > width + 30 then
				cloud.X = -30
			end
			cloud.Frame.Position = UDim2.fromOffset(cloud.X, cloud.Y)
		end

		-- Compteur de tours / minute (degrés/s ÷ 6)
		rpmTimer -= dt
		if rpmTimer <= 0 then
			rpmTimer = 0.12
			rpmLabel.Text = math.floor(speed / 6 + 0.5) .. " tr/min"
		end

		-- L'indice "Souffle !" respire tant qu'on n'a pas soufflé
		if not blown then
			hint.Rotation = math.sin(clock * 3) * 4
		end
	end)
end

function Pinwheel.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Pinwheel
