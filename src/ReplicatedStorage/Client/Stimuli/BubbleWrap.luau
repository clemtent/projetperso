--[[
	BubbleWrap (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > BubbleWrap

	Une feuille de papier bulle (8 x 5 bulles, en quinconce) :
	  - clic / toucher sur une bulle = POP (son à hauteur aléatoire, bulle
	    qui gonfle puis s'aplatit, onde, gouttelettes, "+X") ;
	  - sur PC, on peut aussi maintenir le clic et "glisser" sur les bulles ;
	  - chaque bulle éclatée envoie Interact("Bubble"). Le serveur ne renvoie
	    pas de notification : le "+X" affiché est prédit côté client
	    (gain par clic x Config.Interactions.Bubble.ClickFraction) ;
	  - limite côté client (seau de jetons) pour ne jamais dépasser
	    MaxPerSecond : au-delà, la bulle résiste (petit tremblement) ;
	  - quand tout est éclaté, la feuille part et une neuve arrive en glissant.
	Les 40 bulles sont créées une seule fois puis réutilisées.
]]

local UserInputService = game:GetService("UserInputService")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local BubbleWrap = {}
BubbleWrap.Slot = "L2"

local COLUMNS = 8
local ROWS = 5
local PITCH_X = 32
local PITCH_Y = 28
local DIAMETER = 26

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

	------------------------------------------------------------------
	-- Carte + en-tête
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

	UIUtil.Label({
		Text = Locale.T("🔘 BUBBLE WRAP"),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.fromOffset(160, 20),
		MaxTextSize = 15,
		ZIndex = 5,
		Parent = card,
	})
	local counterLabel = UIUtil.Label({
		Text = "💥 0",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 5),
		Size = UDim2.fromOffset(90, 20),
		MaxTextSize = 15,
		ZIndex = 5,
		Parent = card,
	})
	local counterScale = Create("UIScale", { Parent = counterLabel })

	-- Fenêtre (découpe la feuille quand elle glisse)
	local window = Create("Frame", {
		Name = "Window",
		Position = UDim2.fromOffset(8, 28),
		Size = UDim2.new(1, -16, 1, -34),
		BackgroundColor3 = Color3.fromRGB(236, 240, 246),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = card,
	})

	local sheet = Create("Frame", {
		Name = "Sheet",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(222, 240, 255),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = window,
	})
	UIUtil.Gradient(sheet, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(210, 226, 240)), 60)

	-- Message de fin de feuille
	local caption = UIUtil.Label({
		Text = "",
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Theme.Colors.Blue,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 0, 34),
		MaxTextSize = 28,
		ZIndex = 1,
		Parent = window,
	})
	local captionStroke = UIUtil.Stroke(caption, Color3.new(1, 1, 1), 2.5, 1)
	captionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	------------------------------------------------------------------
	-- Bulles (créées une fois, réutilisées pour chaque feuille)
	------------------------------------------------------------------
	local bubbleFill = Color3.fromRGB(242, 250, 255)
	local bubbleStroke = Color3.fromRGB(140, 190, 228)
	local bubbles = {}
	local poppedCount = 0
	local sessionPops = 0
	local regenerating = false

	local function bubblePosition(row: number, column: number): (number, number)
		local x = 16 + column * PITCH_X + ((row % 2 == 1) and PITCH_X / 2 or 0)
		local y = 16 + row * PITCH_Y
		return x, y
	end

	local function resetBubble(bubble)
		bubble.Popped = false
		local button = bubble.Button
		button.BackgroundTransparency = 0.05
		bubble.Scale.Scale = 1
		bubble.Stroke.Color = bubbleStroke
		bubble.Stroke.Transparency = 0
		local shine = bubble.Shine
		shine.Position = UDim2.fromScale(0.34, 0.3)
		shine.Size = UDim2.fromScale(0.36, 0.22)
		shine.Rotation = -30
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0.05
	end

	local function setPoppedLook(bubble)
		local button = bubble.Button
		button.BackgroundTransparency = 0.6
		bubble.Stroke.Color = Color3.fromRGB(120, 158, 196)
		bubble.Stroke.Transparency = 0.35
		-- Le reflet devient un pli
		local shine = bubble.Shine
		shine.Position = UDim2.fromScale(0.5, 0.5)
		shine.Size = UDim2.fromScale(0.62, 0.08)
		shine.Rotation = random:NextNumber(20, 60)
		shine.BackgroundColor3 = Color3.fromRGB(130, 170, 206)
		shine.BackgroundTransparency = 0.25
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
	-- Effets de "pop" (v8) : réserves recyclées, animées par UNE boucle
	-- (avant : 12 instances + 5 tweens créés à chaque bulle éclatée, jusqu'à
	-- 12 fois par seconde en glissant la souris)
	------------------------------------------------------------------
	local RING_POOL = 6
	local DROP_POOL = 18
	local rings = {}
	for index = 1, RING_POOL do
		local ring = Create("Frame", {
			Name = "PopRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(DIAMETER, DIAMETER),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 6,
			Parent = sheet,
		})
		UIUtil.Corner(ring, UDim.new(1, 0))
		rings[index] = { Frame = ring, Stroke = UIUtil.Stroke(ring, Color3.fromRGB(110, 180, 240), 2, 0.1), Age = 1 }
	end
	local drops = {}
	for index = 1, DROP_POOL do
		local drop = Create("Frame", {
			Name = "PopDrop",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 7,
			Parent = sheet,
		})
		UIUtil.Corner(drop, UDim.new(1, 0))
		drops[index] = {
			Frame = drop,
			Stroke = UIUtil.Stroke(drop, Color3.fromRGB(120, 180, 230), 1),
			Age = 1,
			X = 0,
			Y = 0,
			DX = 0,
			DY = 0,
		}
	end
	local nextRing, nextDrop = 1, 1
	local activeEffects = 0 -- effets en cours (la boucle ne fait rien s'il n'y en a pas)

	local function popEffects(x: number, y: number)
		local ring = rings[nextRing]
		nextRing = nextRing % RING_POOL + 1
		if ring.Age >= 1 then
			activeEffects += 1
		end
		ring.Age = 0
		ring.Frame.Position = UDim2.fromOffset(x, y)
		ring.Frame.Size = UDim2.fromOffset(DIAMETER, DIAMETER)
		ring.Stroke.Transparency = 0.1
		ring.Frame.Visible = true

		if effectsOn() then
			for _ = 1, 3 do
				local drop = drops[nextDrop]
				nextDrop = nextDrop % DROP_POOL + 1
				if drop.Age >= 1 then
					activeEffects += 1
				end
				local angle = random:NextNumber(0, math.pi * 2)
				local distance = random:NextNumber(12, 22)
				drop.Age = 0
				drop.X, drop.Y = x, y
				drop.DX, drop.DY = math.cos(angle) * distance, math.sin(angle) * distance
				drop.Frame.Position = UDim2.fromOffset(x, y)
				drop.Frame.BackgroundTransparency = 0
				drop.Stroke.Transparency = 0
				drop.Frame.Visible = true
			end
		end
	end

	-- Avance les effets de pop (anneau 0.25 s, gouttes 0.3 s)
	local function stepEffects(dt: number)
		if activeEffects <= 0 then
			return
		end
		for _, ring in ipairs(rings) do
			if ring.Age < 1 then
				ring.Age = math.min(1, ring.Age + dt / 0.25)
				local eased = 1 - (1 - ring.Age) ^ 2
				local size = DIAMETER * (1 + 0.8 * eased)
				ring.Frame.Size = UDim2.fromOffset(size, size)
				ring.Stroke.Transparency = 0.1 + 0.9 * ring.Age
				if ring.Age >= 1 then
					ring.Frame.Visible = false
					activeEffects -= 1
				end
			end
		end
		for _, drop in ipairs(drops) do
			if drop.Age < 1 then
				drop.Age = math.min(1, drop.Age + dt / 0.3)
				local eased = 1 - (1 - drop.Age) ^ 2
				drop.Frame.Position = UDim2.fromOffset(drop.X + drop.DX * eased, drop.Y + drop.DY * eased)
				drop.Frame.BackgroundTransparency = drop.Age
				drop.Stroke.Transparency = drop.Age
				if drop.Age >= 1 then
					drop.Frame.Visible = false
					activeEffects -= 1
				end
			end
		end
	end

	local regenerate -- (déclarée plus bas)

	local function pop(bubble)
		if bubble.Popped or regenerating or not ctx.IsAlive() then
			return
		end
		if not takeToken() then
			-- Trop vite : la bulle résiste
			bubble.Scale.Scale = 0.9
			UIUtil.Tween(bubble.Scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			return
		end
		bubble.Popped = true
		poppedCount += 1
		sessionPops += 1

		ctx.Interact("Bubble")
		ctx.Sound.Play("Pop", random:NextNumber(0.9, 1.35))

		-- Gonfle puis s'aplatit
		bubble.Scale.Scale = 1.22
		UIUtil.Tween(bubble.Scale, 0.22, { Scale = 0.84 }, Enum.EasingStyle.Back)
		setPoppedLook(bubble)
		popEffects(bubble.X, bubble.Y)

		-- "+X" prédit
		local data = ctx.State.Data
		local value = (data and tonumber(data.ClickValue) or 0) * clickFraction
		if value > 0 then
			local sheetOffset = sheet.Position.X.Offset
			ctx.FloatText(
				container,
				UDim2.fromOffset(8 + sheetOffset + bubble.X, 28 + bubble.Y - 10),
				"+" .. ctx.Format.Format(value),
				Theme.Colors.Blue,
				18
			)
		end

		counterLabel.Text = "💥 " .. sessionPops
		counterScale.Scale = 1.15
		UIUtil.Tween(counterScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)

		if poppedCount >= #bubbles then
			regenerate()
		end
	end

	for row = 0, ROWS - 1 do
		for column = 0, COLUMNS - 1 do
			local x, y = bubblePosition(row, column)
			local button = Create("TextButton", {
				Name = "Bubble",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(DIAMETER, DIAMETER),
				BackgroundColor3 = bubbleFill,
				BackgroundTransparency = 0.05,
				AutoButtonColor = false,
				Text = "",
				ZIndex = 4,
				Parent = sheet,
			})
			UIUtil.Corner(button, UDim.new(1, 0))
			UIUtil.Gradient(button, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(186, 218, 244)), 90)
			local stroke = UIUtil.Stroke(button, bubbleStroke, 1.5)
			local scale = Create("UIScale", { Parent = button })
			local shine = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = button,
			})
			UIUtil.Corner(shine, UDim.new(1, 0))
			local bubble = { Button = button, Stroke = stroke, Scale = scale, Shine = shine, X = x, Y = y, Popped = false }
			resetBubble(bubble)
			table.insert(bubbles, bubble)

			ctx.Connect(button.MouseButton1Down, function()
				pop(bubble)
			end)
			-- Glisser en maintenant le clic (souris)
			ctx.Connect(button.MouseEnter, function()
				if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					pop(bubble)
				end
			end)
		end
	end

	------------------------------------------------------------------
	-- Nouvelle feuille
	------------------------------------------------------------------
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
			-- Message au milieu, visible pendant que la feuille glisse
			local captions = Locale.Pick(CAPTIONS)
			caption.Text = captions[random:NextInteger(1, #captions)]
			caption.TextTransparency = 0
			captionStroke.Transparency = 0
			local slotWidth = ctx.GetSlotSize and ctx.GetSlotSize().X or 288
			local width = (slotWidth > 0 and slotWidth or 288) - 16
			UIUtil.Tween(sheet, 0.35, { Position = UDim2.fromOffset(-(width + 10), 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			ctx.Sound.Play("Open", 0.9)
			task.wait(0.75)
			if not ctx.IsAlive() then
				return
			end
			for _, bubble in ipairs(bubbles) do
				resetBubble(bubble)
			end
			poppedCount = 0
			sheet.Position = UDim2.fromOffset(width + 10, 0)
			UIUtil.Tween(sheet, 0.45, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
			UIUtil.Tween(caption, 0.3, { TextTransparency = 1 })
			UIUtil.Tween(captionStroke, 0.3, { Transparency = 1 })
			task.wait(0.45)
			regenerating = false
		end)
	end

	-- Petite vague de "respiration" des bulles intactes (pour donner envie).
	-- v8 : animée dans la boucle (avant : ~40 tweens + 40 threads d'un coup
	-- toutes les 4 à 7 s), et seulement si le papier bulle est visible.
	local WAVE_STEP = 0.04 -- décalage par colonne
	local WAVE_TIME = 0.3
	local waveAge = -1 -- < 0 : pas de vague en cours
	local nextWave = os.clock() + random:NextNumber(4, 7)

	ctx.OnRender(function(dt: number)
		stepEffects(dt)
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
			if not bubble.Popped then
				local t = waveAge - (index % COLUMNS) * WAVE_STEP
				if t < WAVE_TIME then
					finished = false
					if t >= 0 then
						bubble.Scale.Scale = 1 + 0.08 * math.cos(t / WAVE_TIME * math.pi / 2)
					end
				elseif bubble.Scale.Scale ~= 1 then
					bubble.Scale.Scale = 1
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
