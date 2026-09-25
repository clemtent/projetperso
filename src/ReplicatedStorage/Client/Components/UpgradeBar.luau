--[[
	UpgradeBar (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > UpgradeBar

	La rangée de cartes carrées sous le compteur (Formulas.GetVisibleUpgrades) :
	  - carte blanche à bord noir, gros emoji, pastille rouge = niveau
	    (améliorations à plusieurs niveaux) ;
	  - carte "fanée" si on ne peut pas se la payer ;
	  - infobulle : nom, description, coût (rouge si trop cher) ;
	  - PC : survol = infobulle, clic = achat ;
	  - tactile : 1er appui = infobulle avec un bouton "Acheter", 2e appui
	    (ou "Acheter") = achat ;
	  - "Aller à l'océan" demande toujours une confirmation ;
	  - style "Icônes HD" (Feature HDIcons) : cartes brillantes colorées ;
	  - mode sombre : cartes sombres translucides, texte blanc ;
	  - finitions : ombre douce sous les cartes et l'infobulle, petit "pop"
	    quand une carte devient abordable.
	v5 : noms / descriptions traduits (Locale.T sur les textes anglais de
	Config) ; sur téléphone : cartes plus petites (84), rangée limitée à la
	place entre les slots de côté, infobulle plus large avec de plus gros
	textes ; tout se réajuste quand l'écran change.
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
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)

local UpgradeBar = {}

local MAX_WIDTH = 660 -- largeur max de la rangée (au-delà : défilement horizontal)
local GAP = 14
local CARD_SIZE = 100
local MIN_CARD_SIZE = 78
local PHONE_CARD_SIZE = 84 -- téléphone : cartes un peu plus petites (la toile est déjà agrandie)
local PHONE_MIN_CARD_SIZE = 70
local PAD_TOP = 10 -- place pour les pastilles qui dépassent
local PAD_SIDE = 10
UpgradeBar.Height = CARD_SIZE + PAD_TOP + 6

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
	Button: TextButton,
	Stroke: UIStroke,
	Gradient: UIGradient,
	Icon: TextLabel,
	Badge: TextLabel,
	PopScale: UIScale,
	HD: Frame,
	Level: number,
	Affordable: boolean,
	Removing: boolean,
}

local bar: Frame
local scroll: ScrollingFrame
local cards: { [string]: Card } = {}
local random = Random.new()

-- Infobulle
local tooltip: TextButton
local tipName: TextLabel
local tipDesc: TextLabel
local tipLevel: TextLabel
local tipCost: TextLabel
local tipButton: TextButton
local tipUpgradeId: string? = nil
local tipPinned = false -- vrai si ouverte par appui (tactile) ou confirmation

-- Entrées
local lastInputTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local lastUiTapClock = 0
local hdEnabled = false
local darkMode = false

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

local function canAfford(upgrade): boolean
	return ClientState.GetConfirmedDopamine() >= getCost(upgrade) - 1e-6
end

local function isRepeatable(upgrade): boolean
	return upgrade.MaxLevel ~= 1
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

local function refreshTooltip()
	local id = tipUpgradeId
	if not id then
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
	local affordable = canAfford(upgrade)

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
		tipLevel.Visible = false
	end
	tipCost.Text = Locale.T("Cost: %s Dopamine", formatAmount(cost))
	tipCost.TextColor3 = affordable and Theme.Colors.Text or Theme.Colors.Red

	local needsButton = tipPinned
	tipButton.Visible = needsButton
	if needsButton then
		tipButton.Text = upgrade.Effect == "Detox" and Locale.T("🌊 Let's go") or Locale.T("Buy")
		UIUtil.SetButtonEnabled(tipButton, affordable)
	end

	-- Placement sous la carte (en coordonnées de la toile)
	local topLeft = Interface.ScreenToCanvas(card.Button.AbsolutePosition)
	local size = card.Button.AbsoluteSize / Interface.Scale
	local canvas = Interface.CanvasSize
	local halfWidth = tooltip.AbsoluteSize.X / Interface.Scale / 2
	if halfWidth <= 0 then
		halfWidth = 140
	end
	local x = math.clamp(topLeft.X + size.X / 2, halfWidth + 8, canvas.X - halfWidth - 8)
	tooltip.Position = UDim2.fromOffset(x, topLeft.Y + size.Y + 10)
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
		Size = UDim2.fromOffset(280, 0),
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

	local function textLine(order: number, font: Enum.Font, textSize: number, color: Color3): TextLabel
		return UIUtil.Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = font,
			TextSize = textSize,
			TextColor3 = color,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			LayoutOrder = order,
			ZIndex = 6,
			Parent = tooltip,
		})
	end

	tipName = textLine(1, Theme.Fonts.Title, 21, Theme.Colors.Text)
	tipDesc = textLine(2, Theme.Fonts.Body, 16, Theme.Colors.TextDim)
	tipLevel = textLine(3, Theme.Fonts.Body, 15, Theme.Colors.TextDim)
	tipName:SetAttribute("BaseTextSize", 21)
	tipDesc:SetAttribute("BaseTextSize", 16)
	tipLevel:SetAttribute("BaseTextSize", 15)
	-- Fine ligne de séparation avant le prix
	UIUtil.Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Colors.Divider,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		ZIndex = 6,
		Parent = tooltip,
	})
	tipCost = textLine(4, Theme.Fonts.Title, 17, Theme.Colors.Text)
	tipCost:SetAttribute("BaseTextSize", 17)

	tipButton = UIUtil.PillButton({
		Name = "Buy",
		Text = Locale.T("Buy"),
		Color = Theme.Colors.Green,
		TextColor3 = Theme.Colors.TextDark,
		Height = 38,
		TextSize = 18,
		LayoutOrder = 5,
		ZIndex = 6,
		Parent = tooltip,
	})
	tipButton.Visible = false
end

----------------------------------------------------------------------
-- Achat
----------------------------------------------------------------------

local function burstAt(card: Card, color: Color3?)
	local layer = Effects.GetLayer()
	if layer and card.Button.Parent then
		Effects.Burst(layer, Interface.CanvasPosition(card.Button), color, 12)
	end
end

local function failFeedback(card: Card?)
	SoundManager.Play("Error", 0.7)
	if card then
		UIUtil.Shake(card.Button)
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
		NeedDopamine.Offer(getCost(upgrade) - ClientState.GetConfirmedDopamine())
		return
	end
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Net.Function("BuyUpgrade"):InvokeServer(upgradeId)
		end)
		if ok and success then
			SoundManager.Play("Buy", 0.95 + random:NextNumber(0, 0.15))
			burstAt(card, upgrade.Color)
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
					Effects.FloatingText(layer, Interface.CanvasPosition(card.Button, Vector2.new(0, -40)), message, Theme.Colors.Red, 20)
				end
			end
		end
	end)
end

----------------------------------------------------------------------
-- Style des cartes
----------------------------------------------------------------------

local function styleCard(card: Card)
	local upgrade = card.Upgrade
	local affordable = canAfford(upgrade)
	local button = card.Button

	if hdEnabled then
		local color: Color3 = upgrade.Color or Theme.Colors.Blue
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.BackgroundTransparency = darkMode and 0.1 or 0
		card.Gradient.Enabled = true
		card.Gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.45), color)
		card.HD.Visible = true
	else
		card.Gradient.Enabled = false
		card.HD.Visible = false
		if darkMode then
			button.BackgroundColor3 = Theme.DarkColors.Card
			button.BackgroundTransparency = Theme.DarkColors.CardTransparency
		else
			button.BackgroundColor3 = Theme.Colors.Card
			button.BackgroundTransparency = 0
		end
	end
	card.Stroke.Color = darkMode and Theme.DarkColors.CardBorder or Theme.Colors.CardBorder
	card.Stroke.Transparency = affordable and 0 or 0.45
	card.Icon.TextTransparency = affordable and 0 or 0.5
end

local function styleAll()
	for _, card in pairs(cards) do
		if not card.Removing then
			styleCard(card)
		end
	end
end

----------------------------------------------------------------------
-- Création / suppression des cartes
----------------------------------------------------------------------

local function createCard(upgrade): Card
	local holder = UIUtil.Create("Frame", {
		Name = upgrade.Id,
		Size = UDim2.fromOffset(CARD_SIZE, CARD_SIZE),
		BackgroundTransparency = 1,
		Parent = scroll,
	})

	local button = UIUtil.Create("TextButton", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Card,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = false,
		Parent = holder,
	})
	UIUtil.Corner(button, 18)
	local stroke = UIUtil.Stroke(button, Theme.Colors.CardBorder, 2)
	local gradient = UIUtil.Gradient(button, ColorSequence.new(Color3.new(1, 1, 1)), 90)
	gradient.Enabled = false
	local popScale = UIUtil.Create("UIScale", { Name = "PopScale", Parent = button })
	UIUtil.Shadow(button, 3, 0.84, 2)

	-- Décor "Icônes HD" : rayons qui tournent, anneau blanc, reflet brillant
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
		Position = UDim2.fromScale(0.5, 0.5),
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
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = rays,
		})
	end
	local ring = UIUtil.Create("Frame", {
		Name = "Ring",
		Size = UDim2.fromScale(0.7, 0.7),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.65,
		ZIndex = 2,
		Parent = hd,
	})
	UIUtil.Corner(ring, UDim.new(1, 0))
	UIUtil.Stroke(ring, Color3.new(1, 1, 1), 3)
	local gloss = UIUtil.Create("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = hd,
	})
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = gloss,
	})

	local icon = UIUtil.Label({
		Name = "Icon",
		Text = upgrade.Icon,
		Size = UDim2.fromScale(0.62, 0.62),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
		MaxTextSize = 60,
		Parent = button,
	})

	local badge = UIUtil.Badge(holder, 26)
	badge.Position = UDim2.new(1, -6, 0, 4)

	local card: Card = {
		Upgrade = upgrade,
		Holder = holder,
		Button = button,
		Stroke = stroke,
		Gradient = gradient,
		Icon = icon,
		Badge = badge,
		PopScale = popScale,
		HD = hd,
		Level = ClientState.GetLevel(upgrade.Id),
		Affordable = canAfford(upgrade),
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

-- Place les cartes (centrées ; défilement si trop large).
-- Les cartes de `created` arrivent en glissant depuis le bas.
local function layout(order: { any }, created: { [string]: boolean })
	local count = #order
	local cardSize, minCardSize, maxWidth = metrics()
	local size = cardSize
	if count > 0 then
		size = math.clamp(math.floor((maxWidth - GAP * (count - 1)) / count), minCardSize, cardSize)
	end
	-- Hauteur de la barre selon l'appareil
	local barHeight = cardSize + PAD_TOP + 6
	UpgradeBar.Height = barHeight
	if bar.Size.Y.Offset ~= barHeight then
		bar.Size = UDim2.new(1, 0, 0, barHeight)
	end
	local contentWidth = count * size + math.max(0, count - 1) * GAP + PAD_SIDE * 2
	local viewWidth = math.min(contentWidth, maxWidth + PAD_SIDE * 2)
	scroll.Size = UDim2.new(0, viewWidth, 1, 0)
	scroll.CanvasSize = UDim2.fromOffset(contentWidth, 0)
	scroll.ScrollBarThickness = contentWidth > viewWidth + 1 and 4 or 0

	for index, upgrade in ipairs(order) do
		local card = cards[upgrade.Id]
		if card then
			local x = PAD_SIDE + (index - 1) * (size + GAP)
			local y = PAD_TOP + (cardSize - size)
			local target = UDim2.fromOffset(x, y)
			local targetSize = UDim2.fromOffset(size, size)
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

	layout(visible, created)

	for _, upgrade in ipairs(visible) do
		local card = cards[upgrade.Id]
		if card then
			-- Pastille : niveau (améliorations à plusieurs niveaux) ou nombre de visites à l'océan
			local level = Formulas.GetLevel(data, upgrade.Id)
			if upgrade.Effect == "Detox" then
				UIUtil.SetBadge(card.Badge, data.Rebirths or 0)
			elseif isRepeatable(upgrade) then
				UIUtil.SetBadge(card.Badge, level)
			else
				UIUtil.SetBadge(card.Badge, 0)
			end

			-- "Pop" quand le niveau augmente
			if level > card.Level and not created[upgrade.Id] then
				card.PopScale.Scale = 1.25
				UIUtil.Tween(card.PopScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				card.Badge.Size = UDim2.fromOffset(34, 34)
				UIUtil.Tween(card.Badge, 0.3, { Size = UDim2.fromOffset(26, 26) }, Enum.EasingStyle.Back)
			end
			card.Level = level
			styleCard(card)
		end
	end

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

	buildTooltip(tooltipLayer)
	tooltip.Activated:Connect(function()
		lastUiTapClock = os.clock()
	end)
	tipButton.Activated:Connect(function()
		lastUiTapClock = os.clock()
		local id = tipUpgradeId
		if not id then
			return
		end
		local card = cards[id]
		if not tipButton:GetAttribute("Enabled") then
			failFeedback(card)
			return
		end
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
		tooltip.Size = UDim2.fromOffset(touch and 330 or 280, 0)
		-- Bouton "Acheter" : zone tactile de 44 px au moins
		tipButton.Size = UDim2.fromOffset(0, touch and Theme.TouchTarget or 38)
		tipButton.TextSize = touch and 20 or 18
		for _, line in ipairs({ tipName, tipDesc, tipLevel, tipCost }) do
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

	-- Mises à jour
	ClientState.Changed:Connect(refresh)
	ClientState.FeaturesChanged:Connect(function()
		hdEnabled = ClientState.HasFeature("HDIcons")
		styleAll()
	end)
	ClientState.DarkModeChanged:Connect(function(dark: boolean)
		darkMode = dark
		styleAll()
	end)
	darkMode = ClientState.DarkMode

	-- Affordabilité (10 fois par seconde) + rotation des rayons HD
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if hdEnabled then
			local rotation = (os.clock() * 25) % 360
			for _, card in pairs(cards) do
				local rays = card.HD:FindFirstChild("Rays") :: Frame?
				if rays then
					rays.Rotation = rotation
				end
			end
		end
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		for _, card in pairs(cards) do
			if not card.Removing then
				local affordable = canAfford(card.Upgrade)
				card.Icon.TextTransparency = affordable and 0 or 0.5
				card.Stroke.Transparency = affordable and 0 or 0.45
				-- Devient abordable : petit "pop" pour attirer l'œil
				if affordable and not card.Affordable and tipUpgradeId ~= card.Upgrade.Id then
					card.PopScale.Scale = 1.1
					UIUtil.Tween(card.PopScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				end
				card.Affordable = affordable
			end
		end
		if tipUpgradeId then
			refreshTooltip()
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

return UpgradeBar
