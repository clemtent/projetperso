--[[
	Stocks (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Stocks

	Widget de trading "pro" (slot R1, 288x190), cours en direct de l'action
	DOPA (commun à tout le serveur, voir StockService) :
	  - en-tête : logo, symbole, "EN DIRECT" qui clignote, prix qui "compte"
	    et pastille de variation colorée (▲ vert / ▼ rouge) ;
	  - graphique en aire : grille, courbe lissée qui glisse à chaque point,
	    remplissage en dégradé sous la courbe, point lumineux qui pulse,
	    étiquette de prix qui suit la courbe sur l'axe de droite, ligne de
	    ton prix moyen d'achat, humeur du marché ("🚀 Vers la lune !"...) ;
	  - carte portefeuille : valeur nette des frais, nombre d'actions,
	    plus/moins-value colorée, rappel des frais (Config.Stocks.Fee) ;
	  - boutons Acheter 10 % / 50 % / 100 % et Vendre (survol animé) ;
	  - bandeau de fausses actus boursières qui défile en bas.

	Les achats / ventes passent par la RemoteFunction "StockTrade" : le
	serveur valide tout, on affiche juste son message.
]]

local TextService = game:GetService("TextService")

local Stocks = {}
Stocks.Slot = "R1"

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

-- Dimensions (pixels "design") : la carte est rentrée de 2 px pour que le
-- contour ne soit pas coupé par le slot (ClipsDescendants)
local CARD_W, CARD_H = 284, 186
local CHART_X, CHART_Y = 8, 38
local CHART_W, CHART_H = CARD_W - 16, 68
local PLOT_LEFT, PLOT_TOP = 4, 8
local AXIS_W = 44 -- place à droite pour l'étiquette de prix et les min / max
local PLOT_W = CHART_W - PLOT_LEFT - AXIS_W
local PLOT_H = CHART_H - 16
local DISPLAY_POINTS = 40 -- points dessinés au maximum (limite d'instances)
local LINE_THICKNESS = 2.2
local SLIDE_TIME = 0.35 -- durée du glissement quand un nouveau point arrive
local TAPE_SPEED = 32 -- pixels "design" / seconde du bandeau d'actus

local CARD_TOP = Color3.fromRGB(24, 31, 50)
local CARD_BOTTOM = Color3.fromRGB(11, 15, 26)
local PANEL = Color3.fromRGB(30, 38, 60)
local GRID = Color3.fromRGB(120, 140, 190)
local TEXT = Color3.fromRGB(240, 244, 255)
local TEXT_DIM = Color3.fromRGB(140, 152, 180)
local UP_COLOR = Color3.fromRGB(34, 211, 122)
local DOWN_COLOR = Color3.fromRGB(255, 77, 94)
local FLAT_COLOR = Color3.fromRGB(150, 160, 185)
local AVG_COLOR = Color3.fromRGB(80, 170, 255)
local WHITE = Color3.new(1, 1, 1)

-- Humeur du marché selon la variation sur le graphique
local function getMood(change: number): string
	if change >= 0.05 then
		return Locale.T("🚀 To the moon!")
	elseif change >= 0.015 then
		return Locale.T("🐂 Going up!")
	elseif change <= -0.05 then
		return Locale.T("💀 It's crashing...")
	elseif change <= -0.015 then
		return Locale.T("🐻 Oof, oof, oof")
	end
	return Locale.T("😐 Going nowhere...")
end

-- Petites phrases après une transaction réussie
local BUY_JOKES = {
	en = { "📈 Invested!", "🤑 Bold bet!", "💼 Pro trader", "🙏 Please go up" },
	fr = { "📈 Investi !", "🤑 Pari osé !", "💼 Trader pro", "🙏 Pourvu que ça monte" },
}
local SELL_JOKES = {
	en = { "💰 Sold!", "💸 Cashed out!", "😎 Nicely done", "🏃 Getting out" },
	fr = { "💰 Vendu !", "💸 Encaissé !", "😎 Bien joué", "🏃 On se retire" },
}

-- Fausses actus du bandeau (%s = symbole)
local TAPE_NEWS = {
	en = {
		"%s: analyst mistakes the chart for a heart monitor",
		"Rumor: %s's CEO may be a cat. Stock jumps",
		"%s unveils an even more clickable button, markets go wild",
		"Trader buys %s \"because the line looks pretty\"",
		"Experts predict %s will go up, go down, or stay the same",
		"%s: shareholder meeting postponed due to nap time",
		"A hamster now manages the %s investment fund",
		"%s opens an office on the Moon, rent is astronomical",
		"Scandal: intern clicked \"sell\" 3 times at %s",
		"%s: \"our results are excellent, we think\"",
		"%s stock closely tracks the price of pizza",
		"A pigeon bets it all on %s, markets hold their breath",
		"%s promises a dividend paid in hugs next quarter",
		"Alert: %s charts now look like a roller coaster",
		"%s buys a bubble-wrap factory, a \"pop\" strategy",
		"Buy low, sell high: the secret tip finally revealed",
	},
	fr = {
		"%s : un analyste confond le graphique avec un électrocardiogramme",
		"Rumeur : le PDG de %s serait un chat. Le cours bondit",
		"%s annonce un bouton encore plus cliquable, les marchés s'emballent",
		"Un trader achète %s « parce que la courbe est jolie »",
		"Les experts prédisent que %s va monter, descendre, ou rester pareil",
		"%s : la réunion des actionnaires reportée pour cause de sieste",
		"Un hamster gère désormais le fonds d'investissement %s",
		"%s ouvre un bureau sur la Lune, le loyer est astronomique",
		"Scandale : un stagiaire a cliqué 3 fois sur « vendre » chez %s",
		"%s : « nos résultats sont excellents, enfin on croit »",
		"Le cours de %s suit de près celui de la baguette tradition",
		"Un pigeon mise tout sur %s, les marchés retiennent leur souffle",
		"%s promet un dividende en câlins pour le prochain trimestre",
		"Alerte : les graphiques de %s ressemblent à des montagnes russes",
		"%s rachète une usine de papier bulle, stratégie « pop »",
		"Achète bas, vends haut : le conseil secret enfin révélé",
	},
}

local function formatPrice(price: number): string
	if price >= 1000 then
		return string.format("%.0f", price)
	end
	return string.format("%.2f", price)
end

local function formatPercent(ratio: number): string
	return string.format("%+.1f %%", ratio * 100)
end

function Stocks.Start(ctx)
	local UI = ctx.UIUtil
	local Theme = ctx.Theme
	local Format = ctx.Format
	local stockConfig = ctx.Config.Stocks
	local symbolName = tostring(stockConfig.Symbol or "DOPA")
	local maxPoints = math.clamp(math.floor(tonumber(stockConfig.HistoryLength) or 60), 2, DISPLAY_POINTS)
	local random = Random.new()

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function formatAmount(value: number): string
		if value < 1e6 then
			return Format.WithSpaces(value)
		end
		return Format.Format(value)
	end

	local function frame(props: { [string]: any }): Frame
		props.BorderSizePixel = 0
		if props.BackgroundTransparency == nil and props.BackgroundColor3 == nil then
			props.BackgroundTransparency = 1
		end
		return UI.Create("Frame", props)
	end

	local function fade(parent: Instance, top: number, bottom: number, rotation: number?): UIGradient
		return UI.Create("UIGradient", {
			Rotation = rotation or 90,
			Transparency = NumberSequence.new(top, bottom),
			Parent = parent,
		})
	end

	------------------------------------------------------------------
	-- Carte (bleu nuit, style terminal de trading)
	------------------------------------------------------------------
	local card = frame({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = WHITE,
		Parent = ctx.Container,
	})
	UI.Corner(card, 14)
	UI.Gradient(card, ColorSequence.new(CARD_TOP, CARD_BOTTOM), 90)
	local cardStroke = UI.Stroke(card, WHITE, 1.5, 0)
	UI.Gradient(cardStroke, ColorSequence.new(Color3.fromRGB(90, 110, 170), Color3.fromRGB(30, 38, 60)), 90)

	-- Logo (carré arrondi dégradé)
	local logo = frame({
		Name = "Logo",
		Position = UDim2.fromOffset(8, 7),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = WHITE,
		Parent = card,
	})
	UI.Corner(logo, 8)
	UI.Gradient(logo, ColorSequence.new(Color3.fromRGB(60, 230, 150), Color3.fromRGB(20, 140, 200)), 45)
	UI.Label({
		Text = "🧠",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		MaxTextSize = 18,
		ZIndex = 2,
		Parent = logo,
	})

	UI.Label({
		Name = "Symbol",
		Text = symbolName,
		Font = Theme.Fonts.Title,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(40, 5),
		Size = UDim2.fromOffset(70, 17),
		MaxTextSize = 17,
		Parent = card,
	})
	local liveDot = frame({
		Name = "LiveDot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(40, 28),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = DOWN_COLOR,
		Parent = card,
	})
	UI.Corner(liveDot, UDim.new(1, 0))
	local feePercent = tostring(math.floor(math.clamp(tonumber(stockConfig.Fee) or 0, 0, 1) * 100 + 0.5)) .. " %"
	UI.Label({
		Text = Locale.T("LIVE · %s fee", feePercent),
		Font = Theme.Fonts.Body,
		TextColor3 = TEXT_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(49, 22),
		Size = UDim2.fromOffset(110, 12),
		MaxTextSize = 10,
		Parent = card,
	})

	local priceLabel = UI.Label({
		Name = "Price",
		Text = "--",
		Font = Theme.Fonts.Number,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -76, 0, 6),
		Size = UDim2.fromOffset(96, 24),
		MaxTextSize = 22,
		Parent = card,
	})
	local priceScale = UI.Create("UIScale", { Parent = priceLabel })

	local changePill = frame({
		Name = "Change",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 9),
		Size = UDim2.fromOffset(64, 20),
		BackgroundColor3 = FLAT_COLOR,
		Parent = card,
	})
	UI.Corner(changePill, UDim.new(1, 0))
	UI.Gradient(changePill, ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200)), 90)
	local changeLabel = UI.Label({
		Text = "0.0 %",
		Font = Theme.Fonts.Number,
		TextColor3 = Color3.fromRGB(10, 20, 20),
		Size = UDim2.new(1, -8, 1, -4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 13,
		ZIndex = 2,
		Parent = changePill,
	})

	------------------------------------------------------------------
	-- Graphique
	------------------------------------------------------------------
	local chart = frame({
		Name = "Chart",
		Position = UDim2.fromOffset(CHART_X, CHART_Y),
		Size = UDim2.fromOffset(CHART_W, CHART_H),
		BackgroundColor3 = Color3.fromRGB(8, 12, 22),
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Corner(chart, 8)
	UI.Stroke(chart, Color3.fromRGB(50, 62, 95), 1, 0.2)

	-- Grille : 4 lignes horizontales, 5 verticales (très discrètes)
	for i = 0, 3 do
		frame({
			Name = "GridH",
			Position = UDim2.fromOffset(PLOT_LEFT, PLOT_TOP + math.floor(PLOT_H * i / 3)),
			Size = UDim2.fromOffset(PLOT_W, 1),
			BackgroundColor3 = GRID,
			BackgroundTransparency = 0.86,
			ZIndex = 1,
			Parent = chart,
		})
	end
	for i = 1, 5 do
		frame({
			Name = "GridV",
			Position = UDim2.fromOffset(PLOT_LEFT + math.floor(PLOT_W * i / 6), PLOT_TOP),
			Size = UDim2.fromOffset(1, PLOT_H),
			BackgroundColor3 = GRID,
			BackgroundTransparency = 0.92,
			ZIndex = 1,
			Parent = chart,
		})
	end

	local function axisLabel(y: number): TextLabel
		return UI.Label({
			Text = "",
			Font = Theme.Fonts.Mono,
			TextColor3 = TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0, y),
			Size = UDim2.fromOffset(AXIS_W - 6, 11),
			MaxTextSize = 9,
			ZIndex = 2,
			Parent = chart,
		})
	end
	local maxLabel = axisLabel(PLOT_TOP)
	local minLabel = axisLabel(PLOT_TOP + PLOT_H)

	-- Prix moyen d'achat du joueur (ligne bleue)
	local avgLine = frame({
		Name = "AvgLine",
		Position = UDim2.fromOffset(PLOT_LEFT, 0),
		Size = UDim2.fromOffset(PLOT_W, 1),
		BackgroundColor3 = AVG_COLOR,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = 4,
		Parent = chart,
	})
	UI.Label({
		Text = Locale.T("your avg price"),
		Font = Theme.Fonts.Body,
		TextColor3 = AVG_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(2, -1),
		Size = UDim2.fromOffset(80, 10),
		MaxTextSize = 9,
		ZIndex = 4,
		Parent = avgLine,
	})

	-- Réserves de segments (courbe) et de tranches (aire), réutilisés
	local segments: { Frame } = {}
	local slices: { Frame } = {}
	local function getSegment(index: number): Frame
		local segment = segments[index]
		if not segment then
			segment = frame({
				Name = "Segment",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = FLAT_COLOR,
				ZIndex = 5,
				Parent = chart,
			})
			UI.Corner(segment, UDim.new(1, 0))
			segments[index] = segment
		end
		return segment
	end
	local function getSlice(index: number): Frame
		local slice = slices[index]
		if not slice then
			slice = frame({
				Name = "Fill",
				BackgroundColor3 = FLAT_COLOR,
				ZIndex = 2,
				Parent = chart,
			})
			fade(slice, 0.55, 1)
			slices[index] = slice
		end
		return slice
	end

	-- Ligne pointillée du prix actuel + étiquette de prix sur l'axe
	local priceLine = frame({
		Name = "PriceLine",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(PLOT_W, 1),
		BackgroundColor3 = FLAT_COLOR,
		BackgroundTransparency = 0.5,
		Visible = false,
		ZIndex = 3,
		Parent = chart,
	})
	fade(priceLine, 1, 0.2, 0)
	local priceTag = frame({
		Name = "PriceTag",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(AXIS_W - 2, 14),
		BackgroundColor3 = FLAT_COLOR,
		Visible = false,
		ZIndex = 7,
		Parent = chart,
	})
	UI.Corner(priceTag, 4)
	local priceTagLabel = UI.Label({
		Text = "",
		Font = Theme.Fonts.Mono,
		TextColor3 = Color3.fromRGB(8, 12, 22),
		Size = UDim2.new(1, -4, 1, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 10,
		ZIndex = 8,
		Parent = priceTag,
	})

	-- Point "en direct" au bout de la courbe (+ halo qui pulse)
	local dotRing = frame({
		Name = "DotRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = FLAT_COLOR,
		BackgroundTransparency = 0.6,
		Visible = false,
		ZIndex = 6,
		Parent = chart,
	})
	UI.Corner(dotRing, UDim.new(1, 0))
	local dotRingScale = UI.Create("UIScale", { Parent = dotRing })
	local dot = frame({
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = FLAT_COLOR,
		Visible = false,
		ZIndex = 7,
		Parent = chart,
	})
	UI.Corner(dot, UDim.new(1, 0))
	UI.Stroke(dot, WHITE, 1.5)

	-- Humeur du marché (petite étiquette en haut à gauche)
	local moodLabel = UI.Create("TextLabel", {
		Name = "Mood",
		Text = Locale.T("⏳ Opening..."),
		Font = Theme.Fonts.Title,
		TextSize = 10,
		TextColor3 = TEXT,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 14),
		Position = UDim2.fromOffset(5, 3),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = chart,
	})
	UI.Corner(moodLabel, 5)
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		Parent = moodLabel,
	})

	local loadingLabel = UI.Label({
		Text = Locale.T("Loading price... ⏳"),
		TextColor3 = TEXT_DIM,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.fromOffset(200, 18),
		MaxTextSize = 13,
		ZIndex = 9,
		Parent = chart,
	})

	------------------------------------------------------------------
	-- Carte portefeuille
	------------------------------------------------------------------
	local holdings = frame({
		Name = "Holdings",
		Position = UDim2.fromOffset(8, 110),
		Size = UDim2.fromOffset(CHART_W, 26),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1,
		Parent = card,
	})
	UI.Corner(holdings, 8)
	UI.Stroke(holdings, Color3.fromRGB(60, 74, 110), 1, 0.3)
	local valueLabel = UI.Label({
		Name = "Value",
		Text = "",
		RichText = true,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(0.56, -8, 1, -8),
		MaxTextSize = 13,
		Parent = holdings,
	})
	local profitPill = frame({
		Name = "Profit",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.new(0.44, -6, 1, -8),
		BackgroundColor3 = FLAT_COLOR,
		BackgroundTransparency = 0.8,
		Parent = holdings,
	})
	UI.Corner(profitPill, UDim.new(1, 0))
	local profitLabel = UI.Label({
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = TEXT_DIM,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 1, -2),
		MaxTextSize = 12,
		ZIndex = 2,
		Parent = profitPill,
	})

	------------------------------------------------------------------
	-- Boutons
	------------------------------------------------------------------
	local function hasFraction(value: number): boolean
		for _, fraction in ipairs(stockConfig.Fractions or {}) do
			if math.abs(fraction - value) < 1e-6 then
				return true
			end
		end
		return false
	end

	-- Fractions d'achat affichées : 10 %, 50 %, 100 % (si le serveur les accepte)
	local buyFractions = {}
	for _, fraction in ipairs({ 0.1, 0.5, 1 }) do
		if hasFraction(fraction) then
			table.insert(buyFractions, fraction)
		end
	end
	if #buyFractions == 0 then
		for i, fraction in ipairs(stockConfig.Fractions or {}) do
			if i > 3 then
				break
			end
			table.insert(buyFractions, fraction)
		end
	end

	local buttonRow = frame({
		Name = "Buttons",
		Position = UDim2.fromOffset(8, 140),
		Size = UDim2.fromOffset(CHART_W, 26),
		Parent = card,
	})
	UI.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = buttonRow,
	})

	local sellWidth = 74
	local buyWidth = math.floor((CHART_W - sellWidth - 4 * #buyFractions) / math.max(1, #buyFractions))
	local DISABLED_COLOR = Color3.fromRGB(62, 70, 92)

	local function makeButton(text: string, color: Color3, width: number, order: number): TextButton
		-- Support transparent placé par le UIListLayout : le bouton, lui, reste
		-- libre de bouger (sinon UI.Shake, qui change Position, ne fait rien)
		local holder = frame({
			Name = "TradeHolder",
			Size = UDim2.fromOffset(width, 26),
			LayoutOrder = order,
			Parent = buttonRow,
		})
		local button = UI.Create("TextButton", {
			Name = "Trade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = text,
			TextColor3 = WHITE,
			TextSize = 13,
			Parent = holder,
		})
		UI.Corner(button, 8)
		UI.Gradient(button, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(175, 175, 175)), 90)
		local stroke = UI.Stroke(button, color:Lerp(WHITE, 0.35), 1, 0.3)
		local textStroke = UI.Stroke(button, Color3.new(0, 0, 0), 1, 0.7)
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		-- Reflet en haut
		local shine = frame({
			Position = UDim2.fromOffset(3, 2),
			Size = UDim2.new(1, -6, 0.42, 0),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.8,
			ZIndex = 2,
			Parent = button,
		})
		UI.Corner(shine, 6)
		button:SetAttribute("BaseColor", color)
		button:SetAttribute("Enabled", true)
		UI.AnimateButton(button, 1.06, 0.92)

		-- Survol : un peu plus lumineux
		ctx.Connect(button.MouseEnter, function()
			if button:GetAttribute("Enabled") ~= false then
				UI.Tween(button, 0.15, { BackgroundColor3 = color:Lerp(WHITE, 0.2) })
				UI.Tween(stroke, 0.15, { Transparency = 0 })
			end
		end)
		ctx.Connect(button.MouseLeave, function()
			if button:GetAttribute("Enabled") ~= false then
				UI.Tween(button, 0.15, { BackgroundColor3 = color })
			end
			UI.Tween(stroke, 0.15, { Transparency = 0.3 })
		end)
		return button
	end

	local function setEnabled(button: TextButton, value: boolean)
		if button:GetAttribute("Enabled") == value then
			return
		end
		button:SetAttribute("Enabled", value)
		local base = button:GetAttribute("BaseColor")
		button.BackgroundColor3 = value and (typeof(base) == "Color3" and base or FLAT_COLOR) or DISABLED_COLOR
		button.TextTransparency = value and 0 or 0.45
	end

	local buyButtons: { TextButton } = {}
	for i, fraction in ipairs(buyFractions) do
		local text = "▲ " .. tostring(math.floor(fraction * 100 + 0.5)) .. "%"
		local button = makeButton(text, Color3.fromRGB(22, 170, 96), buyWidth, i)
		button:SetAttribute("Fraction", fraction)
		table.insert(buyButtons, button)
	end
	local sellButton = makeButton(Locale.T("▼ Sell"), Color3.fromRGB(220, 50, 70), sellWidth, 10)

	------------------------------------------------------------------
	-- Bandeau de fausses actus (défile en bas de la carte)
	------------------------------------------------------------------
	local tape = frame({
		Name = "Tape",
		Position = UDim2.fromOffset(8, 170),
		Size = UDim2.fromOffset(CHART_W, 12),
		BackgroundColor3 = Color3.fromRGB(6, 9, 16),
		BackgroundTransparency = 0.2,
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Corner(tape, 4)
	local tapeItems = {}
	local newsDeck: { string } = {}
	local function nextNews(): string
		if #newsDeck == 0 then
			for _, text in ipairs(Locale.Pick(TAPE_NEWS)) do
				table.insert(newsDeck, text)
			end
			for i = #newsDeck, 2, -1 do
				local j = random:NextInteger(1, i)
				newsDeck[i], newsDeck[j] = newsDeck[j], newsDeck[i]
			end
		end
		local text = table.remove(newsDeck) or Locale.Pick(TAPE_NEWS)[1]
		return "📰 " .. string.format(text, symbolName) .. "   •"
	end
	local function measure(text: string): number
		local ok, size = pcall(function()
			return TextService:GetTextSize(text, 10, Enum.Font.BuilderSansMedium, Vector2.new(4000, 12))
		end)
		if ok and size then
			return size.X + 14
		end
		return #text * 5
	end
	for i = 1, 2 do
		local label = UI.Create("TextLabel", {
			Name = "News",
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = "",
			TextColor3 = Color3.fromRGB(255, 205, 110),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(10, 12),
			ZIndex = 2,
			Parent = tape,
		})
		tapeItems[i] = { Label = label, X = 0, Width = 10 }
	end
	local function loadTape(item, x: number)
		local text = nextNews()
		item.Label.Text = text
		item.Width = measure(text)
		item.Label.Size = UDim2.fromOffset(item.Width, 12)
		item.X = x
	end
	loadTape(tapeItems[1], CHART_W * 0.3)
	loadTape(tapeItems[2], tapeItems[1].X + tapeItems[1].Width)

	------------------------------------------------------------------
	-- Données et rendu
	------------------------------------------------------------------
	local values: { number } = {}
	local prevLast = 0 -- dernier prix AVANT la mise à jour (pour animer la fin de courbe)
	local slideStart = -math.huge
	local rangeMin, rangeMax = 0, 1
	local targetMin, targetMax = 0, 1
	local lineColor = FLAT_COLOR
	local displayPrice = 0
	local targetPrice = 0
	local dirty = true
	local tagY = -1

	local function getHoldings(): (number, number)
		local data = ctx.State.Data
		local stock = data and data.Stock
		if type(stock) ~= "table" then
			return 0, 0
		end
		return tonumber(stock.Shares) or 0, tonumber(stock.CostBasis) or 0
	end

	-- Recalcule la plage verticale visée (avec une petite marge)
	local function computeRange()
		local lo, hi = math.huge, -math.huge
		for _, value in ipairs(values) do
			lo = math.min(lo, value)
			hi = math.max(hi, value)
		end
		if lo == math.huge then
			lo, hi = 0, 1
		end
		local span = hi - lo
		local minSpan = math.max(hi * 0.02, 0.5)
		if span < minSpan then
			local mid = (hi + lo) / 2
			lo, hi = mid - minSpan / 2, mid + minSpan / 2
			span = minSpan
		end
		targetMin = lo - span * 0.12
		targetMax = hi + span * 0.12
	end

	local function redraw(alpha: number)
		local count = #values
		if count < 2 then
			for _, segment in ipairs(segments) do
				segment.Visible = false
			end
			for _, slice in ipairs(slices) do
				slice.Visible = false
			end
			dot.Visible = false
			dotRing.Visible = false
			avgLine.Visible = false
			priceLine.Visible = false
			priceTag.Visible = false
			loadingLabel.Visible = true
			return
		end
		loadingLabel.Visible = false

		local spacing = PLOT_W / (maxPoints - 1)
		local span = math.max(rangeMax - rangeMin, 1e-6)
		local offset = (1 - alpha) * spacing
		local bottom = PLOT_TOP + PLOT_H
		local prevX, prevY = 0, 0
		for i = 1, count do
			local value = values[i]
			if i == count then
				value = prevLast + (value - prevLast) * alpha
			end
			local x = PLOT_LEFT + PLOT_W - (count - i) * spacing + offset
			local y = PLOT_TOP + PLOT_H * (1 - (value - rangeMin) / span)
			if i > 1 then
				local segment = getSegment(i - 1)
				local dx, dy = x - prevX, y - prevY
				local length = math.sqrt(dx * dx + dy * dy)
				segment.Position = UDim2.fromOffset((x + prevX) / 2, (y + prevY) / 2)
				segment.Size = UDim2.fromOffset(length + LINE_THICKNESS * 0.6, LINE_THICKNESS)
				segment.Rotation = math.deg(math.atan2(dy, dx))
				segment.BackgroundColor3 = lineColor
				segment.Visible = true

				-- Tranche d'aire sous le segment (dégradé vers le bas)
				local slice = getSlice(i - 1)
				local top = math.min(y, prevY) + math.abs(dy) * 0.5
				slice.Position = UDim2.fromOffset(prevX, top)
				slice.Size = UDim2.fromOffset(dx + 1, math.max(0, bottom - top))
				slice.BackgroundColor3 = lineColor
				slice.Visible = true
			end
			prevX, prevY = x, y
		end
		for j = count, #segments do
			segments[j].Visible = false
		end
		for j = count, #slices do
			slices[j].Visible = false
		end

		dot.Position = UDim2.fromOffset(prevX, prevY)
		dot.BackgroundColor3 = lineColor
		dot.Visible = true
		dotRing.Position = dot.Position
		dotRing.BackgroundColor3 = lineColor
		dotRing.Visible = true

		-- Étiquette de prix : suit la fin de courbe (lissée dans OnRender)
		local clampedY = math.clamp(prevY, 7, CHART_H - 7)
		if tagY < 0 then
			tagY = clampedY
		end
		priceLine.Position = UDim2.fromOffset(PLOT_LEFT, prevY)
		priceLine.BackgroundColor3 = lineColor
		priceLine.Visible = true
		priceTag.BackgroundColor3 = lineColor
		priceTag.Visible = true

		-- Prix moyen d'achat (seulement s'il est dans le cadre)
		local shares, costBasis = getHoldings()
		if shares > 1e-9 and costBasis > 0 then
			local average = costBasis / shares
			local y = PLOT_TOP + PLOT_H * (1 - (average - rangeMin) / span)
			avgLine.Position = UDim2.fromOffset(PLOT_LEFT, math.floor(y))
			avgLine.Visible = y >= 2 and y <= CHART_H - 2
		else
			avgLine.Visible = false
		end

		maxLabel.Text = formatPrice(rangeMax)
		minLabel.Text = formatPrice(math.max(0, rangeMin))
	end

	-- Portefeuille (valeur + plus/moins-value + frais)
	local FEE = math.clamp(tonumber(stockConfig.Fee) or 0, 0, 1)
	local feeText = tostring(math.floor(FEE * 100 + 0.5)) .. " %"
	local function refreshHoldings()
		local shares, costBasis = getHoldings()
		local price = targetPrice
		if shares <= 1e-9 then
			valueLabel.Text = Locale.T('💼 <font color="#8C98B4">No shares · %s fee</font>', feeText)
			profitLabel.Text = Locale.T("Buy low, sell high 😏")
			profitLabel.TextColor3 = TEXT_DIM
			profitPill.BackgroundColor3 = FLAT_COLOR
		else
			-- Valeur NETTE des frais de vente : c'est ce que "Vendre" rapporte vraiment
			local value = shares * price * (1 - FEE)
			local sharesText = shares < 100 and string.format("%.2f", shares) or Format.Format(shares)
			valueLabel.Text = Locale.T('💼 <b>%s</b> <font color="#8C98B4">· %s shares</font>', formatAmount(value), sharesText)
			local profit = value - costBasis
			local ratio = costBasis > 0 and profit / costBasis or 0
			local sign = profit >= 0 and "+" or "-"
			profitLabel.Text = (profit >= 0 and "▲ " or "▼ ") .. formatPercent(ratio) .. " (" .. sign .. formatAmount(math.abs(profit)) .. ")"
			local color = profit >= 0 and UP_COLOR or DOWN_COLOR
			profitLabel.TextColor3 = color
			profitPill.BackgroundColor3 = color
		end

		-- Boutons : grisés si impossible
		local data = ctx.State.Data
		local dopamine = data and tonumber(data.Dopamine) or 0
		for _, button in ipairs(buyButtons) do
			setEnabled(button, dopamine >= 1)
		end
		setEnabled(sellButton, shares > 1e-9)
	end

	local function applyStock(stock)
		if type(stock) ~= "table" then
			return
		end
		local history = type(stock.History) == "table" and stock.History or {}
		local previousLast = values[#values]
		local newValues = {}
		local first = math.max(1, #history - maxPoints + 1)
		for i = first, #history do
			local value = tonumber(history[i])
			if value then
				table.insert(newValues, value)
			end
		end
		local price = tonumber(stock.Price)
		if #newValues == 0 and price then
			newValues = { price }
		end
		values = newValues

		local last = values[#values] or price or 0
		prevLast = previousLast or last
		targetPrice = price or last
		if displayPrice == 0 then
			displayPrice = targetPrice
		end

		-- Animation : la courbe glisse d'un cran vers la gauche
		if previousLast ~= nil then
			slideStart = os.clock()
		else
			slideStart = -math.huge
		end

		-- Variation sur la fenêtre affichée
		local firstValue = values[1] or last
		local change = firstValue > 0 and (last - firstValue) / firstValue or 0
		if change > 0.0005 then
			lineColor = UP_COLOR
		elseif change < -0.0005 then
			lineColor = DOWN_COLOR
		else
			lineColor = FLAT_COLOR
		end
		changePill.BackgroundColor3 = lineColor
		changeLabel.Text = (change > 0.0005 and "▲ " or (change < -0.0005 and "▼ " or "")) .. formatPercent(change)
		if #values >= 2 then
			local mood = getMood(change)
			if moodLabel.Text ~= mood then
				moodLabel.Text = mood
				moodLabel.Rotation = random:NextNumber(-6, 6)
				UI.Tween(moodLabel, 0.4, { Rotation = 0 }, Enum.EasingStyle.Back)
			end
		end

		-- Petit "flash" du prix
		if previousLast ~= nil and last ~= previousLast then
			priceLabel.TextColor3 = last > previousLast and UP_COLOR or DOWN_COLOR
			UI.Tween(priceLabel, 0.7, { TextColor3 = TEXT })
			priceScale.Scale = 1.1
			UI.Tween(priceScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end

		computeRange()
		if previousLast == nil then
			rangeMin, rangeMax = targetMin, targetMax
		end
		dirty = true
		refreshHoldings()
	end

	applyStock(ctx.State.Stock)
	ctx.Connect(ctx.State.StockChanged, applyStock)
	ctx.Connect(ctx.State.Changed, function()
		refreshHoldings()
		dirty = true
	end)
	refreshHoldings()

	-- Rendu : glissement, plage lissée, prix qui "compte", halo, bandeau
	local clock = 0
	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt
		local elapsed = os.clock() - slideStart
		local alpha = 1
		if elapsed < SLIDE_TIME then
			local t = math.clamp(elapsed / SLIDE_TIME, 0, 1)
			alpha = 1 - (1 - t) * (1 - t) -- ease out
			dirty = true
		end

		local k = math.min(1, dt * 6)
		if math.abs(rangeMin - targetMin) > 1e-4 or math.abs(rangeMax - targetMax) > 1e-4 then
			rangeMin += (targetMin - rangeMin) * k
			rangeMax += (targetMax - rangeMax) * k
			dirty = true
		end

		if dirty then
			dirty = false
			redraw(alpha)
		end

		-- Étiquette de prix : glisse vers la fin de courbe
		if priceTag.Visible then
			local wanted = math.clamp(dot.Position.Y.Offset, 7, CHART_H - 7)
			tagY += (wanted - tagY) * math.min(1, dt * 10)
			priceTag.Position = UDim2.fromOffset(PLOT_LEFT + PLOT_W + 1, tagY)
		end

		if math.abs(displayPrice - targetPrice) > 0.004 then
			displayPrice += (targetPrice - displayPrice) * math.min(1, dt * 8)
			if math.abs(displayPrice - targetPrice) <= 0.004 then
				displayPrice = targetPrice
			end
			priceLabel.Text = formatPrice(displayPrice)
			priceTagLabel.Text = formatPrice(displayPrice)
		elseif priceLabel.Text == "--" and targetPrice > 0 then
			priceLabel.Text = formatPrice(targetPrice)
			priceTagLabel.Text = formatPrice(targetPrice)
		end

		local pulse = (clock % 1.2) / 1.2
		dotRingScale.Scale = 1 + pulse * 1.6
		dotRing.BackgroundTransparency = 0.45 + pulse * 0.55
		liveDot.BackgroundTransparency = (math.floor(clock * 1.6) % 2 == 0) and 0 or 0.7

		-- Bandeau d'actus : défilement continu, le texte sorti repasse derrière
		for _, item in ipairs(tapeItems) do
			item.X -= TAPE_SPEED * dt
		end
		for index, item in ipairs(tapeItems) do
			if item.X + item.Width < 0 then
				local other = tapeItems[3 - index]
				loadTape(item, math.max(CHART_W, other.X + other.Width))
			end
			item.Label.Position = UDim2.fromOffset(math.floor(item.X), 0)
		end
	end)

	------------------------------------------------------------------
	-- Transactions
	------------------------------------------------------------------
	local busy = false
	local lastTrade = 0
	local cooldown = tonumber(stockConfig.TradeCooldown) or 0.5

	-- Texte flottant + pièces au-dessus du bouton cliqué
	local function feedback(button: TextButton, text: string, color: Color3)
		-- Conversion pixels écran -> pixels "design" de la carte (UIScale)
		local scale = card.AbsoluteSize.X / CARD_W
		local x = CARD_W / 2
		if scale > 0 then
			x = (button.AbsolutePosition.X + button.AbsoluteSize.X / 2 - card.AbsolutePosition.X) / scale
		end
		x = math.clamp(x, 60, CARD_W - 60)
		ctx.FloatText(card, UDim2.fromOffset(x, 126), text, color, 22)
		if effectsOn() then
			ctx.Effects.Burst(card, UDim2.fromOffset(x, 150), Theme.Colors.Gold, 8)
		end
	end

	local function trade(action: string, fraction: number, button: TextButton)
		if busy or os.clock() - lastTrade < cooldown then
			UI.Shake(button)
			return
		end
		if button:GetAttribute("Enabled") == false then
			ctx.Sound.Play("Error")
			UI.Shake(button)
			if action == "sell" then
				ctx.Notify(Locale.T("You don't have any shares to sell 🤷"), Theme.Colors.Red)
			else
				ctx.Notify(Locale.T("Not enough Dopamine to invest 😅"), Theme.Colors.Red)
			end
			return
		end
		busy = true
		lastTrade = os.clock()
		task.spawn(function()
			local ok, success, message = pcall(function()
				return ctx.Net.Function("StockTrade"):InvokeServer(action, fraction)
			end)
			busy = false
			if not ctx.IsAlive() then
				return
			end
			if ok and success then
				ctx.Sound.Play("Cash", action == "sell" and 1.15 or 1)
				local jokes = Locale.Pick(action == "sell" and SELL_JOKES or BUY_JOKES)
				local text = jokes[random:NextInteger(1, #jokes)]
				feedback(button, text, action == "sell" and Theme.Colors.Gold or UP_COLOR)
				ctx.Notify(type(message) == "string" and message or text, action == "sell" and Theme.Colors.Gold or UP_COLOR)
			else
				ctx.Sound.Play("Error")
				UI.Shake(button)
				local text = ok and type(message) == "string" and message or Locale.T("The market isn't responding... 😵")
				ctx.Notify(text, Theme.Colors.Red)
			end
		end)
	end

	for _, button in ipairs(buyButtons) do
		local fraction = button:GetAttribute("Fraction") :: number
		ctx.Connect(button.Activated, function()
			trade("buy", fraction, button)
		end)
	end
	ctx.Connect(sellButton.Activated, function()
		trade("sell", 1, sellButton)
	end)
end

return Stocks
