--[[
	Stocks (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Stocks

	Carte "bourse" (slot R1, 288x190) : cours en direct de l'action DOPA
	(commun à tout le serveur, voir StockService) avec un graphique en
	ligne qui défile en douceur, le prix, la variation en %, une petite
	humeur ("🚀 Vers la lune !", "🐻 Aïe aïe aïe"...), le portefeuille du
	joueur (valeur, plus/moins-value, prix moyen d'achat sur le graphique)
	et les boutons Acheter 10 % / 50 % / 100 % et Vendre tout.

	Les achats / ventes passent par la RemoteFunction "StockTrade" : le
	serveur valide tout, on affiche juste son message.
]]

local Stocks = {}
Stocks.Slot = "R1"

-- Dimensions (pixels "design") : la carte est rentrée de 2 px pour que le
-- contour ne soit pas coupé par le slot (ClipsDescendants)
local CARD_W = 284
local CHART_X, CHART_Y = 10, 34
local CHART_W, CHART_H = CARD_W - 20, 78
local PLOT_LEFT, PLOT_TOP = 6, 9
local PLOT_W = CHART_W - PLOT_LEFT - 46 -- place à droite pour les étiquettes min / max
local PLOT_H = CHART_H - 18
local LINE_THICKNESS = 2.5
local SLIDE_TIME = 0.35 -- durée du glissement quand un nouveau point arrive

local UP_COLOR = Color3.fromRGB(22, 170, 80)
local DOWN_COLOR = Color3.fromRGB(225, 45, 55)
local FLAT_COLOR = Color3.fromRGB(120, 120, 130)
local BUY_COLOR = Color3.fromRGB(28, 160, 78)
local AVG_COLOR = Color3.fromRGB(30, 136, 229)

-- Humeur du marché selon la variation sur le graphique
local function getMood(change: number): string
	if change >= 0.05 then
		return "🚀 Vers la lune !"
	elseif change >= 0.015 then
		return "🐂 Ça monte !"
	elseif change <= -0.05 then
		return "💀 C'est la chute..."
	elseif change <= -0.015 then
		return "🐻 Aïe aïe aïe"
	end
	return "😐 Ça stagne..."
end

-- Petites phrases après une transaction réussie
local BUY_JOKES = { "📈 Investi !", "🤑 Pari osé !", "💼 Trader pro", "🙏 Pourvu que ça monte" }
local SELL_JOKES = { "💰 Vendu !", "💸 Encaissé !", "😎 Bien joué", "🏃 On se retire" }

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
	local maxPoints = math.max(2, stockConfig.HistoryLength or 60)
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

	------------------------------------------------------------------
	-- Carte
	------------------------------------------------------------------
	local card = UI.Create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = Theme.Colors.Card,
		BorderSizePixel = 0,
		Parent = ctx.Container,
	})
	UI.Corner(card, 14)
	UI.Stroke(card, Theme.Colors.CardBorder, 2)

	-- En-tête : titre, prix, variation
	UI.Label({
		Name = "Title",
		Text = "📈 " .. tostring(stockConfig.Symbol or "DOPA"),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.fromOffset(92, 22),
		MaxTextSize = 19,
		Parent = card,
	})

	local priceLabel = UI.Label({
		Name = "Price",
		Text = "--",
		Font = Theme.Fonts.Number,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -78, 0, 5),
		Size = UDim2.fromOffset(104, 24),
		MaxTextSize = 21,
		Parent = card,
	})
	local priceScale = UI.Create("UIScale", { Parent = priceLabel })

	local changePill = UI.Create("Frame", {
		Name = "Change",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 7),
		Size = UDim2.fromOffset(62, 20),
		BackgroundColor3 = FLAT_COLOR,
		BorderSizePixel = 0,
		Parent = card,
	})
	UI.Corner(changePill, UDim.new(1, 0))
	local changeLabel = UI.Label({
		Text = "0.0 %",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextLight,
		Size = UDim2.new(1, -8, 1, -4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 13,
		Parent = changePill,
	})

	------------------------------------------------------------------
	-- Graphique
	------------------------------------------------------------------
	local chart = UI.Create("Frame", {
		Name = "Chart",
		Position = UDim2.fromOffset(CHART_X, CHART_Y),
		Size = UDim2.fromOffset(CHART_W, CHART_H),
		BackgroundColor3 = Color3.fromRGB(246, 248, 250),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Corner(chart, 8)
	UI.Stroke(chart, Color3.fromRGB(210, 214, 220), 1)

	-- Lignes de repère
	for i = 0, 2 do
		UI.Create("Frame", {
			Name = "Grid",
			Position = UDim2.fromOffset(PLOT_LEFT, PLOT_TOP + math.floor(PLOT_H * i / 2)),
			Size = UDim2.fromOffset(PLOT_W, 1),
			BackgroundColor3 = Color3.fromRGB(222, 226, 232),
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = chart,
		})
	end

	local function axisLabel(y: number): TextLabel
		return UI.Label({
			Text = "",
			Font = Theme.Fonts.Mono,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0, y),
			Size = UDim2.fromOffset(42, 12),
			MaxTextSize = 10,
			ZIndex = 2,
			Parent = chart,
		})
	end
	local maxLabel = axisLabel(PLOT_TOP)
	local minLabel = axisLabel(PLOT_TOP + PLOT_H)

	-- Prix moyen d'achat du joueur (ligne bleue)
	local avgLine = UI.Create("Frame", {
		Name = "AvgLine",
		Position = UDim2.fromOffset(PLOT_LEFT, 0),
		Size = UDim2.fromOffset(PLOT_W, 1),
		BackgroundColor3 = AVG_COLOR,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = chart,
	})
	UI.Label({
		Text = "ton prix moyen",
		Font = Theme.Fonts.Body,
		TextColor3 = AVG_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(2, -1),
		Size = UDim2.fromOffset(80, 10),
		MaxTextSize = 9,
		ZIndex = 2,
		Parent = avgLine,
	})

	-- Réserve de segments (réutilisés à chaque mise à jour)
	local segments: { Frame } = {}
	local function getSegment(index: number): Frame
		local segment = segments[index]
		if not segment then
			segment = UI.Create("Frame", {
				Name = "Segment",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				BackgroundColor3 = FLAT_COLOR,
				ZIndex = 3,
				Parent = chart,
			})
			UI.Corner(segment, UDim.new(1, 0))
			segments[index] = segment
		end
		return segment
	end

	-- Point "en direct" au bout de la courbe (+ anneau qui pulse)
	local dotRing = UI.Create("Frame", {
		Name = "DotRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = FLAT_COLOR,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
		Parent = chart,
	})
	UI.Corner(dotRing, UDim.new(1, 0))
	local dotRingScale = UI.Create("UIScale", { Parent = dotRing })
	local dot = UI.Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = FLAT_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = chart,
	})
	UI.Corner(dot, UDim.new(1, 0))
	UI.Stroke(dot, Color3.new(1, 1, 1), 1.5)

	-- Humeur du marché (petite étiquette en haut à gauche)
	local moodLabel = UI.Create("TextLabel", {
		Name = "Mood",
		Text = "⏳ Ouverture...",
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextColor3 = Theme.Colors.Text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 16),
		Position = UDim2.fromOffset(5, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = chart,
	})
	UI.Corner(moodLabel, 6)
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		Parent = moodLabel,
	})

	local loadingLabel = UI.Label({
		Text = "Chargement du cours... ⏳",
		TextColor3 = Theme.Colors.TextDim,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.fromOffset(200, 18),
		MaxTextSize = 13,
		ZIndex = 6,
		Parent = chart,
	})

	------------------------------------------------------------------
	-- Portefeuille
	------------------------------------------------------------------
	local holdings = UI.Create("Frame", {
		Name = "Holdings",
		Position = UDim2.fromOffset(10, 116),
		Size = UDim2.fromOffset(CHART_W, 28),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		Parent = card,
	})
	UI.Corner(holdings, 8)
	local valueLabel = UI.Label({
		Name = "Value",
		Text = "",
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(0.55, -8, 1, -8),
		MaxTextSize = 14,
		Parent = holdings,
	})
	local profitLabel = UI.Label({
		Name = "Profit",
		Text = "",
		Font = Theme.Fonts.Number,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 4),
		Size = UDim2.new(0.45, -8, 1, -8),
		MaxTextSize = 13,
		Parent = holdings,
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

	local buttonRow = UI.Create("Frame", {
		Name = "Buttons",
		Position = UDim2.fromOffset(10, 150),
		Size = UDim2.fromOffset(CHART_W, 30),
		BackgroundTransparency = 1,
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

	local sellWidth = 72
	local buyWidth = math.floor((CHART_W - sellWidth - 4 * #buyFractions) / math.max(1, #buyFractions))

	local function makeButton(text: string, color: Color3, width: number, order: number): TextButton
		local button = UI.NeonButton({
			Name = "Trade",
			Text = text,
			Color = color,
			Size = UDim2.fromOffset(width, 30),
			CornerRadius = 9,
			StrokeThickness = 1.5,
			MaxTextSize = 14,
			LayoutOrder = order,
			Parent = buttonRow,
		})
		local padding = button:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new(0, 3)
			padding.PaddingRight = UDim.new(0, 3)
		end
		return button
	end

	local buyButtons: { TextButton } = {}
	for i, fraction in ipairs(buyFractions) do
		local text = "📈 " .. tostring(math.floor(fraction * 100 + 0.5)) .. "%"
		local button = makeButton(text, BUY_COLOR, buyWidth, i)
		button:SetAttribute("Fraction", fraction)
		table.insert(buyButtons, button)
	end
	local sellButton = makeButton("💸 Vendre", Theme.Colors.Red, sellWidth, 10)

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
			dot.Visible = false
			dotRing.Visible = false
			avgLine.Visible = false
			loadingLabel.Visible = true
			return
		end
		loadingLabel.Visible = false

		local spacing = PLOT_W / (maxPoints - 1)
		local span = math.max(rangeMax - rangeMin, 1e-6)
		local offset = (1 - alpha) * spacing
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
			end
			prevX, prevY = x, y
		end
		for j = count, #segments do
			segments[j].Visible = false
		end

		dot.Position = UDim2.fromOffset(prevX, prevY)
		dot.BackgroundColor3 = lineColor
		dot.Visible = true
		dotRing.Position = dot.Position
		dotRing.BackgroundColor3 = lineColor
		dotRing.Visible = true

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

	-- Texte du portefeuille (valeur + plus/moins-value)
	local function refreshHoldings()
		local shares, costBasis = getHoldings()
		local price = targetPrice
		if shares <= 1e-9 then
			valueLabel.Text = '💼 <font color="#777777">Aucune action</font>'
			profitLabel.Text = "Achète bas, vends haut 😏"
			profitLabel.TextColor3 = Theme.Colors.TextDim
			profitLabel.Font = Theme.Fonts.Body
		else
			local value = shares * price
			local sharesText = shares < 100 and string.format("%.2f", shares) or Format.Format(shares)
			valueLabel.Text = "💼 <b>" .. formatAmount(value) .. '</b> <font color="#777777">· ' .. sharesText .. " act.</font>"
			local profit = value - costBasis
			local ratio = costBasis > 0 and profit / costBasis or 0
			local sign = profit >= 0 and "+" or "-"
			profitLabel.Text = formatPercent(ratio) .. " (" .. sign .. formatAmount(math.abs(profit)) .. ")"
			profitLabel.TextColor3 = profit >= 0 and UP_COLOR or DOWN_COLOR
			profitLabel.Font = Theme.Fonts.Number
		end

		-- Boutons : grisés si impossible
		local data = ctx.State.Data
		local dopamine = data and tonumber(data.Dopamine) or 0
		for _, button in ipairs(buyButtons) do
			UI.SetButtonEnabled(button, dopamine >= 1)
		end
		UI.SetButtonEnabled(sellButton, shares > 1e-9)
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
		changeLabel.Text = formatPercent(change)
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
			UI.Tween(priceLabel, 0.7, { TextColor3 = Theme.Colors.Text })
			priceScale.Scale = 1.12
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

	-- Rendu : glissement, plage lissée, prix qui "compte", anneau qui pulse
	local clock = 0
	ctx.OnRender(function(dt: number)
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

		if math.abs(displayPrice - targetPrice) > 0.004 then
			displayPrice += (targetPrice - displayPrice) * math.min(1, dt * 8)
			if math.abs(displayPrice - targetPrice) <= 0.004 then
				displayPrice = targetPrice
			end
			priceLabel.Text = formatPrice(displayPrice)
		elseif priceLabel.Text == "--" and targetPrice > 0 then
			priceLabel.Text = formatPrice(targetPrice)
		end

		local pulse = (clock % 1.2) / 1.2
		dotRingScale.Scale = 1 + pulse * 1.6
		dotRing.BackgroundTransparency = 0.45 + pulse * 0.55
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
		ctx.FloatText(card, UDim2.fromOffset(x, 136), text, color, 22)
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
				ctx.Notify("Tu n'as aucune action à vendre 🤷", Theme.Colors.Red)
			else
				ctx.Notify("Pas assez de Dopamine pour investir 😅", Theme.Colors.Red)
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
				local jokes = action == "sell" and SELL_JOKES or BUY_JOKES
				local text = jokes[random:NextInteger(1, #jokes)]
				feedback(button, text, action == "sell" and Theme.Colors.Gold or UP_COLOR)
				ctx.Notify(type(message) == "string" and message or text, action == "sell" and Theme.Colors.Gold or UP_COLOR)
			else
				ctx.Sound.Play("Error")
				UI.Shake(button)
				local text = ok and type(message) == "string" and message or "La bourse ne répond pas... 😵"
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
