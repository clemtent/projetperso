--[[
	UpgradeBar (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > UpgradeBar

	La rangée de cartes d'amélioration sous le compteur (Formulas.GetVisibleUpgrades).
	v8 — cartes "boutique" lisibles d'un coup d'œil :
	  - plaque d'icône colorée (couleur de l'amélioration) avec reflet ;
	  - pastille de niveau sur la plaque + fine barre de progression
	    niveau / niveau max ;
	  - pastille de PRIX en bas : verte quand on peut payer, sinon grise avec
	    une jauge qui se remplit à mesure que la Dopamine monte (on voit
	    combien il reste avant de pouvoir acheter) ;
	  - achat : la carte s'écrase puis rebondit, reflet qui balaie la carte,
	    plaque qui saute, "Nv 4" qui s'envole, étincelles de sa couleur ;
	  - carte "🔒 teaser" en bout de rangée quand de nouvelles améliorations
	    arrivent après la prochaine visite à l'océan
	    (Formulas.GetNextRebirthUnlocks) ;
	  - infobulle : nom, niveau, description, amélioration requise
	    (Requires), prix + ce qu'il manque ;
	  - PC : survol = infobulle, clic = achat ; tactile : 1er appui =
	    infobulle avec "Acheter", 2e appui = achat ; "Aller à l'océan"
	    demande toujours une confirmation ;
	  - carte trop chère : NeedDopamine.Offer (fenêtre "Pas assez de Dopamine").
	L'état "abordable" suit ClientState.Changed ET ClientState.DopamineChanged
	(s'il existe), limité à 4 mises à jour par seconde (+ filet de sécurité
	lent pour les clics prédits).
	Les cartes sont dessinées en 100 x 100 puis mises à l'échelle (UIScale) :
	plus petites sur téléphone, rangée limitée à la place entre les slots.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Notifications)
local NeedDopamine = require(script.Parent.NeedDopamine)
local PanelManager = require(script.Parent.PanelManager)
local Slots = require(Client.Slots)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)

local UpgradeBar = {}

local DESIGN = 100 -- taille "design" d'une carte (mise à l'échelle ensuite)
local TEASER_WIDTH = 212 -- largeur "design" de la carte teaser
local MAX_WIDTH = 660 -- largeur max de la rangée (au-delà : défilement horizontal)
local GAP = 12
local CARD_SIZE = 100
local MIN_CARD_SIZE = 80
local PHONE_CARD_SIZE = 84 -- téléphone : cartes un peu plus petites (la toile est déjà agrandie)
local PHONE_MIN_CARD_SIZE = 72
local PAD_TOP = 8
local PAD_SIDE = 8
local REFRESH_INTERVAL = 0.25 -- (s) au plus 4 mises à jour "abordable" par seconde
local SAFETY_INTERVAL = 1 -- (s) filet de sécurité (clics prédits sans nouvel état)
UpgradeBar.Height = CARD_SIZE + PAD_TOP + 8

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PRICE_OK = Color3.fromRGB(70, 222, 110)
local PRICE_TRACK = Color3.fromRGB(236, 236, 240)
local PRICE_FILL = Color3.fromRGB(150, 225, 170)
local OCEAN = Color3.fromRGB(0, 140, 200)

-- Mesures selon l'appareil : (taille de carte, taille min, largeur max de la rangée)
local function metrics(): (number, number, number)
	if Interface.IsPhone() then
		local clear = Slots.GetCenterClearWidth() - PAD_SIDE * 2
		return PHONE_CARD_SIZE, PHONE_MIN_CARD_SIZE, math.clamp(clear, 340, MAX_WIDTH)
	end
	return CARD_SIZE, MIN_CARD_SIZE, MAX_WIDTH
end

-- Traduction des textes de Config (anglais -> langue du joueur)
local function translate(text: string): string
	return Locale.T(text)
end

type Card = {
	Upgrade: any,
	Holder: Frame,
	Fit: UIScale,
	Button: TextButton,
	Stroke: UIStroke,
	Gradient: UIGradient,
	Plate: Frame,
	PlateScale: UIScale,
	Icon: TextLabel,
	LevelChip: Frame,
	LevelText: TextLabel,
	LevelTrack: Frame,
	LevelFill: Frame,
	Price: Frame,
	PriceFill: Frame,
	PriceText: TextLabel,
	PriceStroke: UIStroke,
	Shine: UIGradient,
	PopScale: UIScale,
	HD: Frame,
	Rays: Frame,
	Level: number,
	Affordable: boolean?,
	Removing: boolean,
}

local bar: Frame
local scroll: ScrollingFrame
local cards: { [string]: Card } = {}
local random = Random.new()

-- Carte "teaser" (améliorations verrouillées jusqu'à la prochaine visite à l'océan)
local teaser: Frame
local teaserFit: UIScale
local teaserButton: TextButton
local teaserTitle: TextLabel
local teaserText: TextLabel
local teaserIcons: TextLabel
local teaserGate: number? = nil
local teaserCount = 0

-- Infobulle
local tooltip: TextButton
local tipName: TextLabel
local tipLevel: TextLabel
local tipDesc: TextLabel
local tipNeeds: TextLabel
local tipCost: TextLabel
local tipMissing: TextLabel
local tipButton: TextButton
local tipUpgradeId: string? = nil -- Id de la carte, ou "__teaser"
local tipPinned = false -- vrai si ouverte par appui (tactile) ou confirmation
local TEASER_ID = "__teaser"

-- Entrées
local lastInputTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local lastUiTapClock = 0
local hdEnabled = false
local darkMode = false

-- Mises à jour "abordable" (limitées)
local lastAffordRefresh = 0
local affordScheduled = false

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function formatAmount(value: number): string
	if value >= 1e6 then
		return NumberFormatter.Format(value)
	elseif value < 10 and value % 1 ~= 0 then
		return NumberFormatter.Format(value)
	end
	return NumberFormatter.WithSpaces(value)
end

local function getRebirths(): number
	local data = ClientState.Data
	return (data and data.Rebirths) or 0
end

local function getCost(upgrade): number
	return Formulas.GetUpgradeCost(upgrade, ClientState.GetLevel(upgrade.Id), getRebirths())
end

local function getDopamine(): number
	return ClientState.GetConfirmedDopamine()
end

local function canAfford(upgrade): boolean
	return getDopamine() >= getCost(upgrade) - 1e-6
end

local function isRepeatable(upgrade): boolean
	return upgrade.MaxLevel ~= 1
end

local function upgradeColor(upgrade): Color3
	if upgrade.Effect == "Detox" then
		return OCEAN
	end
	return upgrade.Color or Theme.Colors.Blue
end

----------------------------------------------------------------------
-- Infobulle
----------------------------------------------------------------------

local function hideTooltip()
	tipUpgradeId = nil
	tipPinned = false
	if tooltip then
		tooltip.Visible = false
	end
end

-- Place l'infobulle sous `target` (en coordonnées de la toile)
local function placeTooltip(target: GuiObject)
	local topLeft = Interface.ScreenToCanvas(target.AbsolutePosition)
	local size = target.AbsoluteSize / Interface.Scale
	local canvas = Interface.CanvasSize
	local halfWidth = tooltip.AbsoluteSize.X / Interface.Scale / 2
	if halfWidth <= 0 then
		halfWidth = 150
	end
	local x = math.clamp(topLeft.X + size.X / 2, halfWidth + 8, canvas.X - halfWidth - 8)
	tooltip.Position = UDim2.fromOffset(x, topLeft.Y + size.Y + 10)
end

local function refreshTeaserTooltip()
	if not teaserGate or not teaser.Visible then
		hideTooltip()
		return
	end
	local names = {}
	for _, upgrade in ipairs(Config.Upgrades) do
		if (upgrade.RequiresRebirths or 0) == teaserGate then
			table.insert(names, upgrade.Icon .. " " .. Locale.T(upgrade.Name))
		end
	end
	tipName.Text = Locale.T("🔒 Coming after the ocean")
	tipLevel.Visible = true
	tipLevel.Text = Locale.T("Unlocks at %d ocean visits (you: %d)", teaserGate, getRebirths())
	tipDesc.Text = table.concat(names, "\n")
	tipNeeds.Visible = false
	tipCost.Text = Locale.T("🌊 Go to the ocean to unlock them")
	tipCost.TextColor3 = OCEAN
	tipMissing.Visible = false
	tipButton.Visible = false
	placeTooltip(teaserButton)
end

local function refreshTooltip()
	local id = tipUpgradeId
	if not id then
		return
	end
	if id == TEASER_ID then
		refreshTeaserTooltip()
		return
	end
	local card = cards[id]
	if not card or card.Removing or not card.Holder.Parent then
		hideTooltip()
		return
	end
	local upgrade = card.Upgrade
	local level = ClientState.GetLevel(upgrade.Id)
	local cost = getCost(upgrade)
	local dopamine = getDopamine()
	local affordable = dopamine >= cost - 1e-6

	tipName.Text = upgrade.Icon .. "  " .. Locale.T(upgrade.Name)
	tipDesc.Text = Formulas.DescribeUpgrade(upgrade, NumberFormatter.Format, getRebirths(), translate)
	if upgrade.Effect == "Detox" then
		local rebirths = getRebirths()
		tipLevel.Visible = rebirths > 0
		tipLevel.Text = Locale.T("Ocean visits: %s", tostring(rebirths))
	elseif isRepeatable(upgrade) then
		tipLevel.Visible = true
		tipLevel.Text = upgrade.MaxLevel and Locale.T("Level %d / %d", level, upgrade.MaxLevel) or Locale.T("Level %d", level)
	else
		tipLevel.Visible = true
		tipLevel.Text = Locale.T("One-time purchase")
	end
	-- Amélioration "d'un carré" (Requires) : on rappelle ce qu'elle améliore
	local required = upgrade.Requires and Config.UpgradesById and Config.UpgradesById[upgrade.Requires]
	if not required and upgrade.Requires then
		for _, other in ipairs(Config.Upgrades) do
			if other.Id == upgrade.Requires then
				required = other
				break
			end
		end
	end
	tipNeeds.Visible = required ~= nil
	if required then
		tipNeeds.Text = Locale.T("Upgrades: %s", required.Icon .. " " .. Locale.T(required.Name))
	end
	tipCost.Text = Locale.T("Cost: %s Dopamine", formatAmount(cost))
	tipCost.TextColor3 = affordable and Theme.Colors.RobuxDark or Theme.Colors.Red
	tipMissing.Visible = not affordable
	if not affordable then
		local percent = cost > 0 and math.floor(math.clamp(dopamine / cost, 0, 0.99) * 100) or 0
		tipMissing.Text = Locale.T("%d%% there • %s missing", percent, NumberFormatter.Format(cost - dopamine))
	end

	local needsButton = tipPinned
	tipButton.Visible = needsButton
	if needsButton then
		if upgrade.Effect == "Detox" then
			tipButton.Text = Locale.T("🌊 Let's go")
		elseif affordable then
			tipButton.Text = Locale.T("Buy")
		else
			tipButton.Text = Locale.T("💎 Get Dopamine")
		end
		-- (trop cher : le bouton reste actif et propose la boutique Dopamine)
		tipButton:SetAttribute("BaseColor", affordable and Theme.Colors.Green or Theme.Colors.Robux)
		UIUtil.SetButtonEnabled(tipButton, true)
		tipButton.TextColor3 = affordable and Theme.Colors.TextDark or Theme.Colors.TextLight
	end
	placeTooltip(card.Button)
end

local function showTooltip(upgradeId: string, pinned: boolean)
	local changed = tipUpgradeId ~= upgradeId
	tipUpgradeId = upgradeId
	tipPinned = pinned
	tooltip.Visible = true
	refreshTooltip()
	if changed then
		local scale = tooltip:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.85
			UIUtil.Tween(scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

local function buildTooltip(layer: Frame)
	-- TextButton (sans texte) : un appui DANS l'infobulle ne traverse pas vers les
	-- stimuli en dessous et ne la ferme pas
	tooltip = UIUtil.Create("TextButton", {
		Name = "UpgradeTooltip",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(290, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Colors.Card,
		Visible = false,
		ZIndex = 5,
		Parent = layer,
	})
	UIUtil.Corner(tooltip, 14)
	UIUtil.Stroke(tooltip, Theme.Colors.CardBorder, 1.5, 0.05)
	UIUtil.Create("UIScale", { Parent = tooltip })
	UIUtil.Shadow(tooltip, 5, 0.8, 3)
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = tooltip,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = tooltip,
	})

	local function textLine(name: string, lineOrder: number, font: Enum.Font, textSize: number, color: Color3): TextLabel
		local line = UIUtil.Create("TextLabel", {
			Name = name,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = font,
			TextSize = textSize,
			TextColor3 = color,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			LayoutOrder = lineOrder,
			ZIndex = 6,
			Parent = tooltip,
		})
		line:SetAttribute("BaseTextSize", textSize)
		return line
	end

	tipName = textLine("Name", 1, Theme.Fonts.Title, 21, Theme.Colors.Text)
	tipLevel = textLine("Level", 2, Theme.Fonts.Title, 14, Theme.Colors.Purple)
	tipDesc = textLine("Description", 3, Theme.Fonts.Body, 16, Theme.Colors.TextDim)
	tipNeeds = textLine("Needs", 4, Theme.Fonts.Body, 14, Theme.Colors.TextDim)
	-- Fine ligne de séparation avant le prix
	UIUtil.Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Colors.Divider,
		BorderSizePixel = 0,
		LayoutOrder = 5,
		ZIndex = 6,
		Parent = tooltip,
	})
	tipCost = textLine("Cost", 6, Theme.Fonts.Title, 17, Theme.Colors.Text)
	tipMissing = textLine("Missing", 7, Theme.Fonts.Body, 14, Theme.Colors.TextDim)

	tipButton = UIUtil.PillButton({
		Name = "Buy",
		Text = Locale.T("Buy"),
		Color = Theme.Colors.Green,
		TextColor3 = Theme.Colors.TextDark,
		Height = 38,
		TextSize = 18,
		LayoutOrder = 8,
		ZIndex = 6,
		Parent = tooltip,
	})
	tipButton.Visible = false
end

----------------------------------------------------------------------
-- Style des cartes
----------------------------------------------------------------------

-- Reflet qui balaie la carte (0,5 s), caché le reste du temps
local function sweep(card: Card)
	local frame = card.Shine.Parent :: Frame
	frame.Visible = true
	card.Shine.Offset = Vector2.new(-1, 0)
	UIUtil.Tween(card.Shine, 0.45, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad)
	local token = (frame:GetAttribute("Sweep") or 0) + 1
	frame:SetAttribute("Sweep", token)
	task.delay(0.5, function()
		if frame:GetAttribute("Sweep") == token then
			frame.Visible = false
		end
	end)
end

-- Prix + jauge "presque abordable" + contour (appelé au plus 4 fois / s)
local function styleAffordability(card: Card, animate: boolean)
	local upgrade = card.Upgrade
	local cost = getCost(upgrade)
	local dopamine = getDopamine()
	local affordable = dopamine >= cost - 1e-6
	local progress = cost > 0 and math.clamp(dopamine / cost, 0, 1) or 1

	local priceText = "💧 " .. NumberFormatter.Format(cost)
	if card.PriceText.Text ~= priceText then
		card.PriceText.Text = priceText
	end
	if affordable then
		card.Price.BackgroundColor3 = PRICE_OK
		card.PriceFill.Visible = false
		card.PriceText.TextColor3 = Theme.Colors.TextDark
		card.PriceStroke.Color = Color3.fromRGB(20, 120, 50)
		card.PriceStroke.Transparency = 0.2
	else
		card.Price.BackgroundColor3 = darkMode and Color3.fromRGB(60, 60, 72) or PRICE_TRACK
		card.PriceFill.Visible = progress > 0.02
		local target = UDim2.fromScale(progress, 1)
		if animate and card.PriceFill.Size ~= target then
			UIUtil.Tween(card.PriceFill, REFRESH_INTERVAL, { Size = target }, Enum.EasingStyle.Linear)
		else
			card.PriceFill.Size = target
		end
		card.PriceText.TextColor3 = darkMode and Theme.DarkColors.TextDim or Theme.Colors.TextDim
		card.PriceStroke.Color = Theme.Colors.CardBorder
		card.PriceStroke.Transparency = 0.75
	end

	card.Stroke.Thickness = affordable and 2 or 1.5
	card.Stroke.Transparency = affordable and 0 or 0.5
	card.Icon.TextTransparency = affordable and 0 or 0.2
	card.Plate.BackgroundTransparency = affordable and 0 or 0.25

	-- Devient abordable : petit "pop" pour attirer l'œil
	if card.Affordable == false and affordable and animate and tipUpgradeId ~= upgrade.Id then
		card.PopScale.Scale = 1.1
		UIUtil.Tween(card.PopScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		sweep(card)
	end
	card.Affordable = affordable
end

local function styleCard(card: Card)
	local upgrade = card.Upgrade
	local button = card.Button
	local color = upgradeColor(upgrade)

	if hdEnabled then
		button.BackgroundColor3 = WHITE
		button.BackgroundTransparency = darkMode and 0.1 or 0
		card.Gradient.Enabled = true
		card.Gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.55), color:Lerp(WHITE, 0.15))
		card.HD.Visible = true
	else
		card.HD.Visible = false
		card.Gradient.Enabled = true
		-- Carte blanche avec un très léger voile de sa couleur en bas
		card.Gradient.Color = ColorSequence.new(WHITE, color:Lerp(WHITE, 0.86))
		if darkMode then
			button.BackgroundColor3 = Theme.DarkColors.Card
			button.BackgroundTransparency = Theme.DarkColors.CardTransparency
			card.Gradient.Enabled = false
		else
			button.BackgroundColor3 = Theme.Colors.Card
			button.BackgroundTransparency = 0
		end
	end
	card.Stroke.Color = darkMode and Theme.DarkColors.CardBorder or Theme.Colors.CardBorder
	styleAffordability(card, false)
end

local function styleAll()
	for _, card in pairs(cards) do
		if not card.Removing then
			styleCard(card)
		end
	end
end

-- Niveau : pastille sur la plaque + barre de progression
local function styleLevel(card: Card, data)
	local upgrade = card.Upgrade
	local level = Formulas.GetLevel(data, upgrade.Id)
	if upgrade.Effect == "Detox" then
		local rebirths = data.Rebirths or 0
		card.LevelChip.Visible = rebirths > 0
		card.LevelText.Text = "🌊" .. tostring(rebirths)
		card.LevelTrack.Visible = false
	elseif isRepeatable(upgrade) then
		card.LevelChip.Visible = level > 0
		card.LevelText.Text = tostring(level)
		card.LevelTrack.Visible = upgrade.MaxLevel ~= nil
		if upgrade.MaxLevel then
			card.LevelFill.Size = UDim2.fromScale(math.clamp(level / upgrade.MaxLevel, 0, 1), 1)
		end
	else
		card.LevelChip.Visible = false
		card.LevelTrack.Visible = false
	end
end

----------------------------------------------------------------------
-- Achat
----------------------------------------------------------------------

local function burstAt(card: Card, color: Color3?)
	local layer = Effects.GetLayer()
	if layer and card.Button.Parent then
		Effects.Burst(layer, Interface.CanvasPosition(card.Button), color, 14)
	end
end

local function failFeedback(card: Card?)
	SoundManager.Play("Error", 0.7)
	if card then
		UIUtil.Shake(card.Button)
	end
end

-- Animation d'achat : écrasement + rebond, reflet qui balaie, plaque qui saute
local function buyAnimation(card: Card, newLevel: number?)
	card.PopScale.Scale = 0.86
	UIUtil.Tween(card.PopScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Elastic)
	card.PlateScale.Scale = 1.35
	UIUtil.Tween(card.PlateScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)
	sweep(card)
	local layer = Effects.GetLayer()
	if layer and card.Button.Parent and newLevel and isRepeatable(card.Upgrade) and card.Upgrade.Effect ~= "Detox" then
		Effects.Pop(layer, Interface.CanvasPosition(card.Button, Vector2.new(0, -46)), Locale.T("Lv %d", newLevel), {
			Color = Theme.Colors.Green,
			Size = 22,
			Style = "Bonus",
			Rise = 50,
		})
	end
end

local function buy(upgradeId: string)
	lastUiTapClock = os.clock()
	local card = cards[upgradeId]
	if not card or card.Removing then
		return
	end
	local upgrade = card.Upgrade
	if not canAfford(upgrade) then
		failFeedback(card)
		NeedDopamine.Offer(getCost(upgrade) - getDopamine())
		return
	end
	local previousLevel = ClientState.GetLevel(upgrade.Id)
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Net.Function("BuyUpgrade"):InvokeServer(upgradeId)
		end)
		if ok and success then
			SoundManager.Play("Buy", 0.95 + random:NextNumber(0, 0.15))
			burstAt(card, upgradeColor(upgrade))
			buyAnimation(card, previousLevel + 1)
			if upgrade.Effect == "Detox" then
				hideTooltip()
			end
		else
			failFeedback(card)
			if not ok then
				Notifications.Toast(Locale.T("Network error, try again."), Theme.Colors.Red)
			elseif type(message) == "string" and message ~= "" then
				local layer = Effects.GetLayer()
				if layer and card.Button.Parent then
					Effects.Pop(layer, Interface.CanvasPosition(card.Button, Vector2.new(0, -40)), message, { Color = Theme.Colors.Red, Size = 20, Style = "Text" })
				end
			end
		end
	end)
end

----------------------------------------------------------------------
-- Création / suppression des cartes
----------------------------------------------------------------------

local function createCard(upgrade): Card
	local color = upgradeColor(upgrade)
	local holder = UIUtil.Create("Frame", {
		Name = upgrade.Id,
		Size = UDim2.fromOffset(CARD_SIZE, CARD_SIZE),
		BackgroundTransparency = 1,
		Parent = scroll,
	})
	-- Cadre "design" 100 x 100 mis à l'échelle de la carte
	local fitFrame = UIUtil.Create("Frame", {
		Name = "Fit",
		Size = UDim2.fromOffset(DESIGN, DESIGN),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local fit = UIUtil.Create("UIScale", { Name = "FitScale", Parent = fitFrame })

	local button = UIUtil.Create("TextButton", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Card,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = false,
		Parent = fitFrame,
	})
	UIUtil.Corner(button, 18)
	local stroke = UIUtil.Stroke(button, Theme.Colors.CardBorder, 2)
	local gradient = UIUtil.Gradient(button, ColorSequence.new(WHITE, color:Lerp(WHITE, 0.86)), 90)
	local popScale = UIUtil.Create("UIScale", { Name = "PopScale", Parent = button })
	-- (ombre de 2 + 2 px : tient sous la carte, jamais coupée par la barre)
	UIUtil.Shadow(button, 2, 0.84, 1)

	-- Décor "Icônes HD" : rayons qui tournent derrière la plaque
	local hd = UIUtil.Create("Frame", {
		Name = "HD",
		Size = UDim2.new(1, -8, 1, -8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 1,
		Parent = button,
	})
	UIUtil.Corner(hd, 14)
	local rays = UIUtil.Create("Frame", {
		Name = "Rays",
		Size = UDim2.fromScale(1.6, 1.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = hd,
	})
	for i = 0, 5 do
		UIUtil.Create("Frame", {
			Size = UDim2.new(0, 12, 1, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = i * 30,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = rays,
		})
	end

	-- Plaque d'icône (couleur de l'amélioration)
	local plate = UIUtil.Create("Frame", {
		Name = "Plate",
		Size = UDim2.fromOffset(54, 54),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(50, 7),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = button,
	})
	UIUtil.Corner(plate, 16)
	UIUtil.Stroke(plate, color:Lerp(BLACK, 0.35), 1.5, 0.15)
	UIUtil.Gradient(plate, ColorSequence.new(color:Lerp(WHITE, 0.62), color:Lerp(WHITE, 0.18)), 90)
	local plateScale = UIUtil.Create("UIScale", { Name = "PlateScale", Parent = plate })
	local gloss = UIUtil.Create("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -8, 0.42, 0),
		Position = UDim2.fromOffset(4, 3),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = plate,
	})
	UIUtil.Corner(gloss, 12)
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.1, 1),
		Parent = gloss,
	})
	local icon = UIUtil.Create("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = upgrade.Icon,
		TextSize = 34,
		TextColor3 = Theme.Colors.Text,
		ZIndex = 4,
		Parent = plate,
	})

	-- Pastille de niveau (coin de la plaque)
	local levelChip = UIUtil.Create("Frame", {
		Name = "LevelChip",
		Size = UDim2.fromOffset(22, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(71, 3),
		BackgroundColor3 = Theme.Colors.Dark,
		Visible = false,
		ZIndex = 6,
		Parent = button,
	})
	UIUtil.Corner(levelChip, UDim.new(1, 0))
	UIUtil.Stroke(levelChip, WHITE, 1.5, 0)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		Parent = levelChip,
	})
	local levelText = UIUtil.Create("TextLabel", {
		Name = "Level",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = "",
		TextSize = 13,
		TextColor3 = Theme.Colors.TextLight,
		ZIndex = 7,
		Parent = levelChip,
	})

	-- Barre de progression des niveaux
	local levelTrack = UIUtil.Create("Frame", {
		Name = "LevelTrack",
		Size = UDim2.fromOffset(62, 5),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(50, 65),
		BackgroundColor3 = Color3.fromRGB(226, 226, 232),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = button,
	})
	UIUtil.Corner(levelTrack, UDim.new(1, 0))
	local levelFill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color:Lerp(BLACK, 0.1),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = levelTrack,
	})
	UIUtil.Corner(levelFill, UDim.new(1, 0))

	-- Pastille de prix (jauge "presque abordable" dessous)
	local price = UIUtil.Create("Frame", {
		Name = "Price",
		Size = UDim2.fromOffset(88, 23),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(50, 95),
		BackgroundColor3 = PRICE_TRACK,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = button,
	})
	UIUtil.Corner(price, UDim.new(1, 0))
	local priceStroke = UIUtil.Stroke(price, Theme.Colors.CardBorder, 1, 0.75)
	local priceFill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = PRICE_FILL,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = price,
	})
	UIUtil.Corner(priceFill, UDim.new(1, 0))
	local priceText = UIUtil.Create("TextLabel", {
		Name = "PriceText",
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = "",
		TextSize = 15,
		TextScaled = true,
		TextColor3 = Theme.Colors.TextDark,
		ZIndex = 5,
		Parent = price,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 9, Parent = priceText })

	-- Reflet qui balaie la carte (achat / devient abordable)
	local shineFrame = UIUtil.Create("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false, -- montré seulement pendant le balayage
		ZIndex = 8,
		Parent = button,
	})
	UIUtil.Corner(shineFrame, 18)
	local shine = UIUtil.Create("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(1, 0), -- hors de la carte au repos
		Parent = shineFrame,
	})

	local card: Card = {
		Upgrade = upgrade,
		Holder = holder,
		Fit = fit,
		Button = button,
		Stroke = stroke,
		Gradient = gradient,
		Plate = plate,
		PlateScale = plateScale,
		Icon = icon,
		LevelChip = levelChip,
		LevelText = levelText,
		LevelTrack = levelTrack,
		LevelFill = levelFill,
		Price = price,
		PriceFill = priceFill,
		PriceText = priceText,
		PriceStroke = priceStroke,
		Shine = shine,
		PopScale = popScale,
		HD = hd,
		Rays = rays,
		Level = ClientState.GetLevel(upgrade.Id),
		Affordable = nil,
		Removing = false,
	}

	-- Survol (PC)
	button.MouseEnter:Connect(function()
		if lastInputTouch or tipPinned then
			return
		end
		showTooltip(upgrade.Id, false)
		UIUtil.Tween(popScale, 0.12, { Scale = 1.06 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		UIUtil.Tween(popScale, 0.12, { Scale = 1 })
		if tipUpgradeId == upgrade.Id and not tipPinned then
			hideTooltip()
		end
	end)

	-- Clic / appui
	button.Activated:Connect(function()
		lastUiTapClock = os.clock()
		local needsConfirm = upgrade.Effect == "Detox"
		if lastInputTouch or needsConfirm then
			if tipUpgradeId == upgrade.Id and tipPinned and not needsConfirm then
				buy(upgrade.Id)
			else
				showTooltip(upgrade.Id, true)
				SoundManager.Play("Click", 1.3)
			end
		else
			-- Une infobulle épinglée (ex. confirmation de l'océan) sur une AUTRE
			-- carte : on la ferme, sinon elle resterait bloquée à l'écran
			if tipPinned and tipUpgradeId ~= upgrade.Id then
				hideTooltip()
				showTooltip(upgrade.Id, false)
			end
			buy(upgrade.Id)
		end
	end)

	styleCard(card)
	return card
end

local function removeCard(id: string)
	local card = cards[id]
	if not card or card.Removing then
		return
	end
	card.Removing = true
	cards[id] = nil
	if tipUpgradeId == id then
		hideTooltip()
	end
	UIUtil.Tween(card.PopScale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.delay(0.3, function()
		card.Holder:Destroy()
	end)
end

----------------------------------------------------------------------
-- Carte teaser (🔒 nouveautés après la prochaine visite à l'océan)
----------------------------------------------------------------------

local function buildTeaser()
	teaser = UIUtil.Create("Frame", {
		Name = "Teaser",
		Size = UDim2.fromOffset(TEASER_WIDTH, CARD_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = scroll,
	})
	local fitFrame = UIUtil.Create("Frame", {
		Name = "Fit",
		Size = UDim2.fromOffset(TEASER_WIDTH, DESIGN),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		BackgroundTransparency = 1,
		Parent = teaser,
	})
	teaserFit = UIUtil.Create("UIScale", { Name = "FitScale", Parent = fitFrame })
	teaserButton = UIUtil.Create("TextButton", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(232, 244, 252),
		AutoButtonColor = false,
		Text = "",
		Parent = fitFrame,
	})
	UIUtil.Corner(teaserButton, 18)
	local stroke = UIUtil.Stroke(teaserButton, OCEAN:Lerp(BLACK, 0.2), 1.5, 0.35)
	stroke.Name = "TeaserStroke"
	UIUtil.Gradient(teaserButton, ColorSequence.new(Color3.fromRGB(245, 251, 255), Color3.fromRGB(205, 232, 248)), 90)
	UIUtil.Shadow(teaserButton, 2, 0.86, 1)
	local teaserPop = UIUtil.Create("UIScale", { Name = "PopScale", Parent = teaserButton })

	-- Vagues décoratives en bas
	for index = 1, 2 do
		local wave = UIUtil.Create("Frame", {
			Name = "Wave" .. index,
			Size = UDim2.new(1.3, 0, 0, 40),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, index == 1 and -20 or 24, 1, index == 1 and -18 or -10),
			BackgroundColor3 = OCEAN:Lerp(WHITE, index == 1 and 0.55 or 0.3),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = teaserButton,
		})
		UIUtil.Corner(wave, UDim.new(1, 0))
	end
	-- (la carte coupe les vagues)
	teaserButton.ClipsDescendants = true

	local lock = UIUtil.Create("Frame", {
		Name = "OceanPlate",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(9, 10),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = teaserButton,
	})
	UIUtil.Corner(lock, 14)
	UIUtil.Stroke(lock, OCEAN:Lerp(BLACK, 0.3), 1.5, 0.2)
	UIUtil.Gradient(lock, ColorSequence.new(Color3.fromRGB(230, 240, 250), Color3.fromRGB(170, 200, 225)), 90)
	UIUtil.Create("TextLabel", {
		Name = "Wave",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "🌊",
		TextSize = 26,
		ZIndex = 4,
		Parent = lock,
	})

	teaserTitle = UIUtil.Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -66, 0, 22),
		Position = UDim2.fromOffset(60, 9),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = Color3.fromRGB(10, 60, 100),
		TextSize = 17,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Parent = teaserButton,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 10, Parent = teaserTitle })
	teaserText = UIUtil.Create("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, -66, 0, 34),
		Position = UDim2.fromOffset(60, 31),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextColor3 = Color3.fromRGB(40, 80, 110),
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
		Parent = teaserButton,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 9, Parent = teaserText })
	-- Silhouettes des nouveautés (fantômes)
	teaserIcons = UIUtil.Create("TextLabel", {
		Name = "Icons",
		Size = UDim2.new(1, -20, 0, 26),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextSize = 20,
		TextTransparency = 0.45,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
		Parent = teaserButton,
	})

	teaserButton.MouseEnter:Connect(function()
		if lastInputTouch or tipPinned then
			return
		end
		showTooltip(TEASER_ID, false)
		UIUtil.Tween(teaserPop, 0.12, { Scale = 1.04 }, Enum.EasingStyle.Back)
	end)
	teaserButton.MouseLeave:Connect(function()
		UIUtil.Tween(teaserPop, 0.12, { Scale = 1 })
		if tipUpgradeId == TEASER_ID and not tipPinned then
			hideTooltip()
		end
	end)
	teaserButton.Activated:Connect(function()
		lastUiTapClock = os.clock()
		UIUtil.Shake(teaserButton)
		showTooltip(TEASER_ID, lastInputTouch)
	end)
end

local function refreshTeaser(data)
	local gate, count = Formulas.GetNextRebirthUnlocks(data)
	teaserGate = gate
	teaserCount = count
	local show = gate ~= nil and count > 0
	teaser.Visible = show
	if not show then
		if tipUpgradeId == TEASER_ID then
			hideTooltip()
		end
		return
	end
	local rebirths = tonumber(data.Rebirths) or 0
	local visits = math.max(1, (gate :: number) - rebirths)
	teaserTitle.Text = count == 1 and Locale.T("🔒 1 new upgrade") or Locale.T("🔒 %d new upgrades", count)
	if visits <= 1 then
		teaserText.Text = Locale.T("after your next visit to the ocean")
	else
		teaserText.Text = Locale.T("after %d more visits to the ocean", visits)
	end
	local icons = {}
	for _, upgrade in ipairs(Config.Upgrades) do
		if (upgrade.RequiresRebirths or 0) == gate and #icons < 6 then
			table.insert(icons, upgrade.Icon)
		end
	end
	teaserIcons.Text = table.concat(icons, " ")
end

----------------------------------------------------------------------
-- Mise en page
----------------------------------------------------------------------

-- Place les cartes (centrées ; défilement si trop large).
-- Les cartes de `created` arrivent en glissant depuis le bas.
local function layout(list: { any }, created: { [string]: boolean })
	local count = #list
	local cardSize, minCardSize, maxWidth = metrics()
	local teaserOn = teaser.Visible
	local slots = count + (teaserOn and TEASER_WIDTH / DESIGN or 0)
	local gaps = math.max(0, count + (teaserOn and 1 or 0) - 1)
	local size = cardSize
	if slots > 0 then
		size = math.clamp(math.floor((maxWidth - GAP * gaps) / slots), minCardSize, cardSize)
	end
	local scale = size / DESIGN
	-- Hauteur de la barre selon l'appareil
	local barHeight = cardSize + PAD_TOP + 8
	UpgradeBar.Height = barHeight
	if bar.Size.Y.Offset ~= barHeight then
		bar.Size = UDim2.new(1, 0, 0, barHeight)
	end
	local teaserWidth = teaserOn and math.floor(TEASER_WIDTH * scale) or 0
	local contentWidth = count * size + teaserWidth + gaps * GAP + PAD_SIDE * 2
	local viewWidth = math.min(contentWidth, maxWidth + PAD_SIDE * 2)
	scroll.Size = UDim2.new(0, viewWidth, 1, 0)
	scroll.CanvasSize = UDim2.fromOffset(contentWidth, 0)
	scroll.ScrollBarThickness = contentWidth > viewWidth + 1 and 4 or 0

	local y = PAD_TOP + (cardSize - size)
	for index, upgrade in ipairs(list) do
		local card = cards[upgrade.Id]
		if card then
			local x = PAD_SIDE + (index - 1) * (size + GAP)
			local target = UDim2.fromOffset(x, y)
			local targetSize = UDim2.fromOffset(size, size)
			card.Fit.Scale = scale
			if created[upgrade.Id] then
				card.Holder.Size = targetSize
				card.Holder.Position = target + UDim2.fromOffset(0, 40)
				card.PopScale.Scale = 0.2
				UIUtil.Tween(card.Holder, 0.4, { Position = target }, Enum.EasingStyle.Back)
				UIUtil.Tween(card.PopScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			elseif card.Holder.Position ~= target or card.Holder.Size ~= targetSize then
				UIUtil.Tween(card.Holder, 0.3, { Position = target, Size = targetSize })
			end
		end
	end
	if teaserOn then
		teaserFit.Scale = scale
		teaser.Size = UDim2.fromOffset(teaserWidth, size)
		teaser.Position = UDim2.fromOffset(PAD_SIDE + count * (size + GAP), y)
	end
end

----------------------------------------------------------------------
-- Mises à jour
----------------------------------------------------------------------

-- "Abordable" : prix, jauges, contours (au plus 4 fois par seconde)
local function refreshAffordability()
	lastAffordRefresh = os.clock()
	for _, card in pairs(cards) do
		if not card.Removing then
			styleAffordability(card, true)
		end
	end
	if tipUpgradeId then
		refreshTooltip()
	end
end

-- Demande une mise à jour "abordable" (regroupées : 4 par seconde au plus)
local function requestAffordability()
	if affordScheduled then
		return
	end
	local delay = REFRESH_INTERVAL - (os.clock() - lastAffordRefresh)
	if delay <= 0 then
		refreshAffordability()
		return
	end
	affordScheduled = true
	task.delay(delay, function()
		affordScheduled = false
		refreshAffordability()
	end)
end

local function refresh(data)
	local visible = Formulas.GetVisibleUpgrades(data)
	local wanted = {}
	for _, upgrade in ipairs(visible) do
		wanted[upgrade.Id] = true
	end

	-- Cartes qui disparaissent (achat unique terminé, niveau max, océan...)
	local toRemove = {}
	for id in pairs(cards) do
		if not wanted[id] then
			table.insert(toRemove, id)
		end
	end
	for _, id in ipairs(toRemove) do
		removeCard(id)
	end

	-- Nouvelles cartes
	local created = {}
	for _, upgrade in ipairs(visible) do
		if not cards[upgrade.Id] then
			cards[upgrade.Id] = createCard(upgrade)
			created[upgrade.Id] = true
		end
	end

	refreshTeaser(data)
	layout(visible, created)

	for _, upgrade in ipairs(visible) do
		local card = cards[upgrade.Id]
		if card then
			local level = Formulas.GetLevel(data, upgrade.Id)
			styleLevel(card, data)
			-- "Pop" de la pastille quand le niveau augmente
			if level > card.Level and not created[upgrade.Id] then
				UIUtil.Pop(card.LevelChip, 1.6, 0.4)
			end
			card.Level = level
			styleCard(card)
		end
	end
	lastAffordRefresh = os.clock()

	if tipUpgradeId then
		refreshTooltip()
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

-- `parent` : cadre de la colonne centrale ; `tooltipLayer` : calque plein écran
-- au-dessus des stimuli (pour l'infobulle)
function UpgradeBar.Build(parent: GuiObject, tooltipLayer: Frame): Frame
	bar = UIUtil.Create("Frame", {
		Name = "UpgradeBar",
		Size = UDim2.new(1, 0, 0, UpgradeBar.Height),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	scroll = UIUtil.Create("ScrollingFrame", {
		Name = "Cards",
		Size = UDim2.new(0, MAX_WIDTH, 1, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ScrollBarImageColor3 = Theme.Colors.Dark,
		CanvasSize = UDim2.fromOffset(0, 0),
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Parent = bar,
	})
	buildTeaser()

	buildTooltip(tooltipLayer)
	tooltip.Activated:Connect(function()
		lastUiTapClock = os.clock()
	end)
	tipButton.Activated:Connect(function()
		lastUiTapClock = os.clock()
		local id = tipUpgradeId
		if not id or id == TEASER_ID then
			return
		end
		-- (trop cher : buy propose la boutique Dopamine via NeedDopamine)
		buy(id)
	end)

	-- Type d'entrée (tactile ou souris)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			lastInputTouch = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			lastInputTouch = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement and not UserInputService.TouchEnabled then
			lastInputTouch = false
		end
	end)
	-- Appui ailleurs : on ferme l'infobulle "épinglée"
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.Touch and inputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local stamp = os.clock()
		task.delay(0.15, function()
			if tipPinned and lastUiTapClock < stamp - 0.25 then
				hideTooltip()
			end
		end)
	end)

	PanelManager.Opened:Connect(hideTooltip)

	-- Écran qui change : cartes, largeur et infobulle réajustées
	local function applyDevice()
		local touch = Interface.IsTouch()
		tooltip.Size = UDim2.fromOffset(touch and 330 or 290, 0)
		-- Bouton "Acheter" : zone tactile de 44 px au moins
		tipButton.Size = UDim2.fromOffset(0, touch and Theme.TouchTarget or 38)
		tipButton.TextSize = touch and 20 or 18
		for _, line in ipairs({ tipName, tipLevel, tipDesc, tipNeeds, tipCost, tipMissing }) do
			local base = line:GetAttribute("BaseTextSize") or 16
			line.TextSize = touch and base + 3 or base
		end
		if ClientState.Data then
			refresh(ClientState.Data)
		end
	end
	Interface.DeviceChanged:Connect(applyDevice)
	Slots.Changed:Connect(applyDevice)
	applyDevice()

	-- Mises à jour : état complet (structure) + ticks légers de Dopamine
	ClientState.Changed:Connect(refresh)
	local dopamineChanged = (ClientState :: any).DopamineChanged
	local hasTicks = type(dopamineChanged) == "table" and type(dopamineChanged.Connect) == "function"
	if hasTicks then
		dopamineChanged:Connect(requestAffordability)
	end
	ClientState.FeaturesChanged:Connect(function()
		hdEnabled = ClientState.HasFeature("HDIcons")
		styleAll()
	end)
	ClientState.DarkModeChanged:Connect(function(dark: boolean)
		darkMode = dark
		styleAll()
	end)
	darkMode = ClientState.DarkMode

	-- Rotation des rayons HD (seulement avec les Icônes HD) + filet de sécurité
	-- "abordable" (clics prédits, ou pas encore de ticks légers : 4 fois / s)
	local safety = hasTicks and SAFETY_INTERVAL or REFRESH_INTERVAL
	RunService.RenderStepped:Connect(function()
		if hdEnabled then
			local rotation = (os.clock() * 25) % 360
			for _, card in pairs(cards) do
				card.Rays.Rotation = rotation
			end
		end
		if os.clock() - lastAffordRefresh >= safety then
			requestAffordability()
		end
	end)

	if ClientState.Data then
		refresh(ClientState.Data)
	end
	return bar
end

-- Masque l'infobulle (ex. clic sur le gros bouton)
function UpgradeBar.HideTooltip()
	if not tipPinned then
		hideTooltip()
	end
end

-- Nombre de nouveautés annoncées par la carte teaser (0 si aucune)
function UpgradeBar.GetTeaserCount(): number
	return teaser and teaser.Visible and teaserCount or 0
end

return UpgradeBar
