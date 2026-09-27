--[[
	NeedDopamine (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > NeedDopamine

	Fenêtre "Pas assez de Dopamine !" quand un achat est trop cher
	(améliorations, "Aller à l'océan", maison 🏠, thèmes, boutique d'objets) :
	  - bandeau coloré avec une grosse goutte 💧 (et un "!" qui sautille) ;
	  - ce qu'on essayait d'acheter (optionnel : icône + nom) ;
	  - combien il manque + jauge "tu as / il faut" qui se remplit EN DIRECT
	    (la production continue pendant que la fenêtre est ouverte) ;
	  - conseil honnête : le plus petit pack de Dopamine qui suffit (selon ta
	    production actuelle), ou "attends ~X" si ta production y arrive
	    vite toute seule ;
	  - bouton "💎 Get Dopamine" : ouvre la boutique Robux directement sur
	    l'onglet "💧 Dopamine" (packs de Dopamine) ;
	  - "Later", ✕ ou clic À CÔTÉ de la carte : ferme. Un clic DANS la carte
	    (zone vide) ne ferme rien (UIUtil.SinkClicks).
	Elle s'affiche À CHAQUE achat refusé faute de Dopamine (plus de pause
	après "Later"), refus du serveur compris (NeedDopamine.OfferRefusal).
	Une seule fenêtre à la fois (jamais empilée, ni sur la fenêtre "Bon
	retour !"). S'il n'y a aucun pack de Dopamine à vendre (IDs à 0 hors
	Studio), on affiche juste la bulle (fallback).
	La fenêtre vit dans le calque Toasts (au-dessus des panneaux).
	Signaux (v8, utilisés par OfferPopup / UpgradeBar) : Shown (fenêtre
	ouverte), Refused(manque) ("Later", ✕ ou clic à côté).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local SoundManager = require(Client.SoundManager)
local ClientState = require(Client.ClientState)
local Interface = require(Client.Interface)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Locale = require(ReplicatedStorage.Shared.Locale)

local NeedDopamine = {}

NeedDopamine.Shown = Signal.new() -- () : la fenêtre vient de s'ouvrir
NeedDopamine.Refused = Signal.new() -- (manque) : "Later", ✕ ou clic à côté

-- Ce qu'on essayait d'acheter (tout est optionnel)
export type Context = {
	Icon: string?, -- emoji
	Name: string?, -- nom DÉJÀ traduit
	Color: Color3?, -- couleur de l'objet (pastille)
	Have: number?, -- Dopamine "vue par le serveur" (refus du serveur)
}

local CARD_WIDTH = 440
local HEADER_HEIGHT = 92
local WAIT_HINT = 45 -- (s) si la production comble le manque avant : on le dit
local LIVE_REFRESH = 0.25 -- (s) jauge en direct : 4 mises à jour par seconde au plus

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(34, 22, 64)
local VIOLET = Color3.fromRGB(124, 58, 237)
local PINK = Color3.fromRGB(236, 72, 153)
local BUY = Theme.Colors.Robux

local layer: Frame? = nil
local current: Frame? = nil
local liveConnection: any = nil
local loopTweens: { Tween } = {}

function NeedDopamine.Build(parent: Frame)
	layer = parent
end

-- Pack de Dopamine achetable ?
local function packOnSale(product): boolean
	return product.Kind == "Dopamine" and ((tonumber(product.ProductId) or 0) ~= 0 or RunService:IsStudio())
end

-- Au moins un pack de Dopamine achetable ?
local function hasDopaminePacks(): boolean
	for _, product in ipairs(Config.Monetization.Products) do
		if packOnSale(product) then
			return true
		end
	end
	return false
end

-- Production actuelle (pour estimer les packs et le temps d'attente)
local function currentStats(): { PerSecond: number, ClickValue: number }
	local data = ClientState.Data
	return {
		PerSecond = tonumber(data and data.PerSecond) or 0,
		ClickValue = tonumber(data and data.ClickValue) or 0,
	}
end

-- Le plus petit pack qui couvre `missing` : (pack, montant) ; sinon le plus gros
local function suggestPack(missing: number): (any?, number)
	local stats = currentStats()
	local best, bestAmount, biggest, biggestAmount = nil, 0, nil, 0
	for _, product in ipairs(Config.Monetization.Products) do
		if packOnSale(product) then
			local amount = Formulas.ScaledReward(stats, tonumber(product.Seconds) or 0, tonumber(product.Minimum) or 0)
			if amount >= missing and (best == nil or amount < bestAmount) then
				best, bestAmount = product, amount
			end
			if amount > biggestAmount then
				biggest, biggestAmount = product, amount
			end
		end
	end
	if best then
		return best, bestAmount
	end
	return biggest, biggestAmount
end

-- Module chargé à la demande (évite les require circulaires au démarrage)
local function lazy(name: string, sub: string?): any
	local folder: Instance? = script.Parent
	if sub and folder then
		folder = folder:FindFirstChild(sub)
	end
	local module = folder and folder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local function stopLoops()
	for _, tween in ipairs(loopTweens) do
		tween:Cancel()
	end
	table.clear(loopTweens)
	if liveConnection then
		liveConnection:Disconnect()
		liveConnection = nil
	end
end

-- Petite animation en boucle (aller-retour), arrêtée à la fermeture
local function loop(instance: Instance, duration: number, props: { [string]: any }, delay: number?, reverses: boolean?)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, reverses ~= false, delay or 0),
		props
	)
	tween:Play()
	table.insert(loopTweens, tween)
end

local function close()
	local window = current
	if not window then
		return
	end
	current = nil
	stopLoops()
	local card = window:FindFirstChild("Card") :: Frame?
	local dimmer = window:FindFirstChild("Dimmer") :: GuiObject?
	if dimmer then
		UIUtil.Tween(dimmer, 0.2, { BackgroundTransparency = 1 })
	end
	if card then
		local scale = card:FindFirstChild("PopScale") :: UIScale?
		if scale then
			UIUtil.Tween(scale, 0.2, { Scale = 0.85 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
	end
	task.delay(0.22, function()
		window:Destroy()
	end)
end

local function refuse(missing: number)
	if not current then
		return
	end
	close()
	NeedDopamine.Refused:Fire(missing)
end

local function openShop()
	close()
	local PanelManager = lazy("PanelManager")
	if not PanelManager or not PanelManager.IsRegistered("RobuxShop") then
		return
	end
	PanelManager.Open("RobuxShop")
	local shop = lazy("RobuxShop", "Panels")
	if type(shop) == "table" and type(shop.ShowTab) == "function" then
		pcall(shop.ShowTab, "Dopamine")
	end
end

-- Texte qui garde sa taille (réduit si traduit plus long)
local function text(parent: Instance, props: { [string]: any }): TextLabel
	local maxSize = props.MaxTextSize or props.TextSize or 16
	local label = UIUtil.Create("TextLabel", {
		Name = props.Name,
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0),
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Body,
		Text = props.Text or "",
		TextColor3 = props.TextColor3 or Theme.Colors.Text,
		TextSize = maxSize,
		TextScaled = true,
		TextWrapped = props.TextWrapped == true,
		RichText = props.RichText == true,
		ZIndex = props.ZIndex or 4,
		Parent = parent,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = props.MinTextSize or 10, Parent = label })
	return label
end

-- Bandeau du haut : dégradé violet -> rose, bulles, grosse goutte + "!"
local function buildHeader(card: Frame)
	local header = UIUtil.Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, -12, 0, HEADER_HEIGHT),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(header, 18)
	UIUtil.Gradient(header, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(139, 92, 246)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(192, 88, 220)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(244, 114, 182)),
	}), 20)
	header:SetAttribute("DarkSkinIgnore", true)

	-- Bulles décoratives (quelques cercles blancs translucides)
	local bubbles = {
		{ 0.08, 0.3, 26, 0.8 },
		{ 0.18, 0.78, 14, 0.75 },
		{ 0.83, 0.22, 20, 0.8 },
		{ 0.93, 0.7, 30, 0.84 },
		{ 0.7, 0.85, 10, 0.7 },
		{ 0.3, 0.12, 9, 0.7 },
	}
	for index, spec in ipairs(bubbles) do
		local bubble = UIUtil.Create("Frame", {
			Name = "Bubble" .. index,
			Size = UDim2.fromOffset(spec[3], spec[3]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = spec[4],
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = header,
		})
		UIUtil.Corner(bubble, UDim.new(1, 0))
		loop(bubble, 1.6 + index * 0.35, { Position = UDim2.new(spec[1], 0, spec[2], -6) }, index * 0.2)
	end
	-- Étincelles
	for index, spec in ipairs({ { 0.24, 0.42, 16 }, { 0.76, 0.5, 18 }, { 0.62, 0.18, 12 } }) do
		local sparkle = UIUtil.Create("TextLabel", {
			Name = "Sparkle" .. index,
			Size = UDim2.fromOffset(spec[3] + 6, spec[3] + 6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = "✨",
			TextSize = spec[3],
			TextTransparency = 0.2,
			ZIndex = 4,
			Parent = header,
		})
		loop(sparkle, 0.9 + index * 0.25, { TextTransparency = 0.85 }, index * 0.3)
	end

	-- Grosse goutte dans un médaillon blanc (qui flotte doucement)
	local medal = UIUtil.Create("Frame", {
		Name = "Medal",
		Size = UDim2.fromOffset(70, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 6 + HEADER_HEIGHT / 2),
		BackgroundColor3 = WHITE,
		ZIndex = 5,
		Parent = card,
	})
	medal:SetAttribute("DarkSkinIgnore", true)
	UIUtil.Corner(medal, UDim.new(1, 0))
	UIUtil.Stroke(medal, WHITE, 3, 0.35)
	UIUtil.Gradient(medal, ColorSequence.new(WHITE, Color3.fromRGB(233, 222, 255)), 90)
	local drop = UIUtil.Create("TextLabel", {
		Name = "Drop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "💧",
		TextSize = 40,
		ZIndex = 6,
		Parent = medal,
	})
	-- "!" rouge qui sautille
	local alert = UIUtil.Create("TextLabel", {
		Name = "Alert",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 8),
		BackgroundColor3 = Theme.Colors.Red,
		Font = Theme.Fonts.Title,
		Text = "!",
		TextColor3 = WHITE,
		TextSize = 18,
		ZIndex = 7,
		Parent = medal,
	})
	UIUtil.Corner(alert, UDim.new(1, 0))
	UIUtil.Stroke(alert, WHITE, 2, 0)
	loop(medal, 1.3, { Position = UDim2.new(0.5, 0, 0, 2 + HEADER_HEIGHT / 2) })
	loop(alert, 0.45, { Rotation = 14 })
	-- Petite secousse "il en manque !" à l'ouverture
	task.spawn(function()
		for index = 1, 6 do
			if not drop.Parent then
				return
			end
			drop.Rotation = index % 2 == 0 and -12 or 12
			task.wait(0.06)
		end
		drop.Rotation = 0
	end)
end

-- Jauge "tu as / il faut" (brillante), renvoie une fonction de mise à jour
local function buildGauge(card: Frame, y: number): (have: number, need: number, animate: boolean) -> ()
	local track = UIUtil.Create("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, -56, 0, 26),
		BackgroundColor3 = Color3.fromRGB(236, 232, 248),
		ClipsDescendants = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	UIUtil.Stroke(track, Color3.fromRGB(196, 181, 253), 1.5, 0)
	UIUtil.Gradient(track, ColorSequence.new(Color3.fromRGB(222, 222, 222), WHITE), 90)
	local fill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = track,
	})
	fill:SetAttribute("DarkSkinIgnore", true)
	UIUtil.Corner(fill, UDim.new(1, 0))
	UIUtil.Gradient(fill, ColorSequence.new(VIOLET, PINK), 0)
	-- Reflet sur le haut du remplissage
	UIUtil.Create("Frame", {
		Name = "Shine",
		Size = UDim2.new(1, -8, 0.42, 0),
		Position = UDim2.fromOffset(4, 2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = fill,
	}, { UIUtil.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	-- (texte blanc bordé de foncé : lisible sur le remplissage comme sur le rail,
	-- en mode clair comme en mode sombre)
	local amounts = UIUtil.Create("TextLabel", {
		Name = "Amounts",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = "",
		TextColor3 = WHITE,
		TextSize = 14,
		ZIndex = 7,
		Parent = track,
	})
	local amountsStroke = UIUtil.Stroke(amounts, INK, 1.5, 0.3)
	amountsStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	amounts:SetAttribute("DarkSkinIgnore", true)

	return function(have: number, need: number, animate: boolean)
		local ratio = need > 0 and math.clamp(have / need, 0, 1) or 0
		local target = UDim2.fromScale(math.max(ratio, 0.04), 1)
		if animate then
			UIUtil.Tween(fill, 0.6, { Size = target }, Enum.EasingStyle.Quint)
		else
			fill.Size = target
		end
		amounts.Text = string.format(
			"💧 %s / %s  •  %s%%",
			NumberFormatter.Format(math.max(0, have)),
			NumberFormatter.Format(need),
			tostring(math.floor(ratio * 100))
		)
	end
end

-- Conseil honnête : attendre un peu, ou le plus petit pack qui suffit
local function hintFor(missing: number): string
	if missing <= 0 then
		return Locale.T("✨ You have enough now: try again!")
	end
	local production = currentStats().PerSecond
	local seconds = production > 0 and missing / production or math.huge
	if seconds <= WAIT_HINT then
		return Locale.T("⏳ Or just wait ~%s: your production gets there.", NumberFormatter.Time(math.ceil(seconds)))
	end
	local pack, amount = suggestPack(missing)
	if pack then
		return Locale.T("💡 %s gives ≈ %s Dopamine", pack.Icon .. " " .. Locale.T(tostring(pack.Name)), NumberFormatter.Format(amount))
	end
	return ""
end

local function build(missing: number, context: Context?)
	local parent = layer
	if not parent then
		return
	end
	if current then
		stopLoops()
		current:Destroy()
		current = nil
	end
	-- Dopamine de départ : celle vue par le serveur (refus) ou la confirmée
	local serverView = context ~= nil and context.Have ~= nil
	local function readHave(): number
		if serverView then
			local data = ClientState.Data
			return math.max(0, tonumber(data and data.Dopamine) or 0)
		end
		return math.max(0, ClientState.GetConfirmedDopamine())
	end
	local have = (context and tonumber(context.Have)) or readHave()
	local need = have + missing

	local window = UIUtil.Create("Frame", {
		Name = "NeedDopamine",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 45,
		Parent = parent,
	})
	current = window

	-- Fond assombri : un clic À CÔTÉ de la carte ferme (= "Later").
	-- (plus léger si une fenêtre est déjà ouverte dessous : pas de double voile)
	local PanelManager = lazy("PanelManager")
	local panelOpen = PanelManager ~= nil and PanelManager.IsOpen()
	local dimmer = UIUtil.Create("TextButton", {
		Name = "Dimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 10, 30),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = window,
	})
	UIUtil.Tween(dimmer, 0.25, { BackgroundTransparency = panelOpen and 0.72 or 0.45 })
	dimmer.Activated:Connect(function()
		refuse(missing)
	end)

	local hasContext = context ~= nil and type(context.Name) == "string" and context.Name ~= ""
	local cardHeight = HEADER_HEIGHT + (hasContext and 262 or 232)
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(CARD_WIDTH, cardHeight),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		Active = true,
		ZIndex = 2,
		Parent = window,
	})
	UIUtil.Corner(card, Theme.Radius.XL)
	UIUtil.SinkClicks(card) -- clic dans la carte (zone vide) : ne ferme pas
	UIUtil.Stroke(card, Color3.fromRGB(167, 139, 250), 2, 0.1)
	UIUtil.Gradient(card, ColorSequence.new(WHITE, Color3.fromRGB(246, 241, 255)), 90)
	UIUtil.Shadow(card, 8, 0.7, 5)
	-- Tient toujours à l'écran (téléphone) + petit "pop" d'entrée
	local canvas = Interface.CanvasSize
	local fit = math.min(1, (canvas.X - 24) / CARD_WIDTH, (canvas.Y - 24) / cardHeight)
	local scale = UIUtil.Create("UIScale", { Name = "PopScale", Scale = 0.8 * fit, Parent = card })
	UIUtil.Tween(scale, 0.32, { Scale = fit }, Enum.EasingStyle.Back)

	buildHeader(card)

	-- ✕ (même effet que "Later" ou un clic à côté)
	UIUtil.CloseButton({
		Name = "Close",
		Size = 34,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		ZIndex = 8,
		Hitbox = Interface.IsTouch() and 48 or 0,
		Shadow = false,
		Parent = card,
		OnClose = function()
			SoundManager.Play("Click", 1.1)
			refuse(missing)
		end,
	})

	local y = HEADER_HEIGHT + 16
	text(card, {
		Name = "Title",
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, -40, 0, 32),
		Font = Theme.Fonts.Title,
		Text = Locale.T("Not enough Dopamine!"),
		TextColor3 = Theme.Colors.Text,
		TextSize = 27,
		ZIndex = 4,
	})
	y += 36

	-- Ce qu'on voulait acheter (pastille)
	if hasContext and context then
		local color = context.Color or VIOLET
		local chip = UIUtil.Chip({
			Name = "Target",
			Text = Locale.T("To buy: %s", ((context.Icon and context.Icon .. " ") or "") .. tostring(context.Name)),
			Color = color:Lerp(WHITE, 0.84),
			TextColor3 = color:Lerp(INK, 0.55),
			StrokeColor = color,
			Height = 26,
			TextSize = 14,
			ZIndex = 4,
			Parent = card,
		})
		chip.AnchorPoint = Vector2.new(0.5, 0)
		chip.Position = UDim2.new(0.5, 0, 0, y)
		y += 32
	end

	local needLabel = text(card, {
		Name = "Text",
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, -48, 0, 22),
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 17,
		RichText = true,
		ZIndex = 4,
	})
	y += 30

	local setGauge = buildGauge(card, y)
	y += 36

	local hintLabel = text(card, {
		Name = "Hint",
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, -48, 0, 34),
		Text = "",
		TextColor3 = Color3.fromRGB(95, 60, 150),
		TextSize = 15,
		TextWrapped = true,
		ZIndex = 4,
	})

	local function paint(currentHave: number, animate: boolean)
		local left = math.max(0, need - currentHave)
		if left > 0 then
			needLabel.Text = Locale.T("You need <b>%s</b> more Dopamine.", NumberFormatter.Format(left))
		else
			needLabel.Text = Locale.T("<b>You can afford it now!</b>")
		end
		setGauge(currentHave, need, animate)
		hintLabel.Text = hintFor(left)
	end
	paint(have, true)

	-- Deux boutons côte à côte : "Later" (neutre) + "💎 Get Dopamine" (achat)
	local margin, gap = 24, 12
	local laterWidth = math.floor((CARD_WIDTH - margin * 2 - gap) * 0.36)
	local getWidth = CARD_WIDTH - margin * 2 - gap - laterWidth
	local later = UIUtil.BasicButton({
		Name = "Later",
		Text = Locale.T("Later"),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 19,
		Size = UDim2.fromOffset(laterWidth, 50),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, margin, 1, -20),
		CornerRadius = UDim.new(1, 0),
		ZIndex = 5,
		Parent = card,
	})
	local get = UIUtil.NeonButton({
		Name = "GetDopamine",
		Text = Locale.T("💎 Get Dopamine"),
		Color = BUY,
		TextColor3 = WHITE,
		Size = UDim2.fromOffset(getWidth, 50),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -margin, 1, -20),
		CornerRadius = UDim.new(1, 0),
		MaxTextSize = 20,
		ZIndex = 5,
		Parent = card,
	})
	-- Reflet qui traverse le bouton d'achat (boucle douce, pas de code par image)
	get.ClipsDescendants = true
	local shine = UIUtil.Create("Frame", {
		Name = "Shine",
		Size = UDim2.new(0, 34, 1, 24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.3, 0, 0.5, 0),
		Rotation = 18,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = get,
	})
	shine:SetAttribute("DarkSkinIgnore", true)
	loop(shine, 1.1, { Position = UDim2.new(1.3, 0, 0.5, 0) }, 1.4, false)

	later.Activated:Connect(function()
		SoundManager.Play("Click", 1.1)
		refuse(missing)
	end)
	get.Activated:Connect(function()
		SoundManager.Play("Click", 1.3)
		openShop()
	end)

	-- Jauge en direct (la production continue pendant que la fenêtre est ouverte)
	local lastPaint = os.clock()
	local dopamineChanged = (ClientState :: any).DopamineChanged
	if type(dopamineChanged) == "table" and type(dopamineChanged.Connect) == "function" then
		liveConnection = dopamineChanged:Connect(function()
			if current ~= window or os.clock() - lastPaint < LIVE_REFRESH then
				return
			end
			lastPaint = os.clock()
			paint(readHave(), true)
		end)
	end
	NeedDopamine.Shown:Fire()
end

--[[
	À appeler quand un achat est refusé faute de Dopamine (à CHAQUE fois).
	missing = combien il manque ; fallback = fonction qui affiche la bulle
	habituelle (utilisée s'il n'y a pas de pack à vendre ou si une autre
	fenêtre bloque) ; context (optionnel) = { Icon, Name (traduit), Color }
	de ce qu'on voulait acheter.
	Renvoie true si la fenêtre est (déjà) ouverte.
]]
function NeedDopamine.Offer(missing: number, fallback: (() -> ())?, context: Context?): boolean
	missing = math.max(0, tonumber(missing) or 0)
	if missing > 0 and missing < 1 then
		missing = 1 -- (jamais "il te manque 0")
	end
	-- La fenêtre "Bon retour !" est à l'écran : on n'empile pas
	local offline = lazy("OfflinePopup")
	local offlineOpen = offline ~= nil and type(offline.IsVisible) == "function" and offline.IsVisible()
	if not layer or not hasDopaminePacks() or offlineOpen then
		if fallback then
			fallback()
		end
		return false
	end
	SoundManager.Play("Error", 0.7)
	-- Déjà ouverte : on la remplace (le manque a pu changer), jamais deux fenêtres
	build(missing, context)
	return true
end

-- Le message de refus du serveur veut-il dire "pas assez de Dopamine" ?
-- (texte traduit côté serveur : on compare avec toutes les langues)
function NeedDopamine.IsRefusal(message: any): boolean
	if type(message) ~= "string" or message == "" then
		return false
	end
	local currency = tostring(Config.Game.CurrencyName or "Dopamine")
	for _, lang in ipairs(Locale.Languages) do
		if message == Locale.TFor(lang, "Not enough %s", currency) then
			return true
		end
	end
	local lower = string.lower(message)
	return (string.find(lower, "not enough", 1, true) ~= nil or string.find(lower, "pas assez", 1, true) ~= nil)
		and string.find(lower, string.lower(currency), 1, true) ~= nil
end

--[[
	Refus du SERVEUR (le client croyait pouvoir payer : clics prédits pas
	encore comptés...) : si `message` veut dire "pas assez de Dopamine",
	ouvre la fenêtre avec le VRAI manque (prix - Dopamine connue du serveur,
	1 au minimum) et renvoie true ; sinon renvoie false (autre refus).
]]
function NeedDopamine.OfferRefusal(message: any, cost: number?, fallback: (() -> ())?, context: Context?): boolean
	if not NeedDopamine.IsRefusal(message) then
		return false
	end
	local data = ClientState.Data
	local serverHave = math.max(0, tonumber(data and data.Dopamine) or ClientState.GetConfirmedDopamine())
	local missing = math.max(1, math.ceil((tonumber(cost) or 0) - serverHave))
	local fullContext: Context = {
		Icon = context and context.Icon,
		Name = context and context.Name,
		Color = context and context.Color,
		Have = serverHave,
	}
	NeedDopamine.Offer(missing, fallback, fullContext)
	return true
end

function NeedDopamine.IsVisible(): boolean
	return current ~= nil
end

-- Ferme la fenêtre (sans compter comme un refus)
function NeedDopamine.Close()
	close()
end

return NeedDopamine
