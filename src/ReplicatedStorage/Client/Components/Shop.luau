--[[
	Shop (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Shop

	Boutique d'améliorations (panneau de droite) :
	  - onglets CLIC / PASSIF / MULTI ;
	  - mode d'achat x1 / x10 / MAX ;
	  - chaque carte affiche : icône, nom, niveau, bénéfice, total, coût ;
	  - bouton grisé si pas assez de Dopamine.
	Les cartes sont générées automatiquement depuis Config.Upgrades.
	L'achat est une DEMANDE au serveur, qui vérifie tout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Notifications)

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)

local Shop = {}

local BUY_MODES = { "x1", "x10", "max" }
local BUY_MODE_LABELS = { x1 = "x1", x10 = "x10", max = "MAX" }
local CATEGORY_COLORS = {
	Click = Theme.Colors.Pink,
	Passive = Theme.Colors.Cyan,
	Multiplier = Theme.Colors.Yellow,
}

local currentCategory = "Click"
local buyMode = "x1"
local cards = {} -- [upgradeId] = { Frame, Button, Level, Total }
local tabButtons = {} -- [categoryId] = bouton

-- Texte "total" : ce que rapporte actuellement l'amélioration
local function totalText(upgrade, level: number): string
	if upgrade.Category == "Click" then
		return "Total : +" .. NumberFormatter.Format(upgrade.Value * level) .. " / clic"
	elseif upgrade.Category == "Passive" then
		return "Total : +" .. NumberFormatter.Format(upgrade.Value * level) .. " / s"
	end
	return level > 0 and "✔ Actif" or "Pas encore acheté"
end

local function requestBuy(upgradeId: string, card)
	local ok, success, message = pcall(function()
		return Net.Function("BuyUpgrade"):InvokeServer(upgradeId, buyMode)
	end)
	if ok and success then
		SoundManager.Play("Buy", 1 + math.random() * 0.2)
		Effects.Burst(card.Frame, UDim2.fromScale(0.85, 0.5), CATEGORY_COLORS[Config.UpgradesById[upgradeId].Category], 12)
		card.Frame.BackgroundColor3 = Theme.Colors.PanelLight
		UIUtil.Tween(card.Frame, 0.4, { BackgroundColor3 = Theme.Colors.Card })
	else
		SoundManager.Play("Error", 0.7)
		UIUtil.Shake(card.Button)
		if ok and message then
			Notifications.Toast(message, Theme.Colors.Red)
		end
	end
end

local function createCard(list: ScrollingFrame, upgrade)
	local color = CATEGORY_COLORS[upgrade.Category]

	local frame = UIUtil.Create("Frame", {
		Name = upgrade.Id,
		Size = UDim2.new(1, -8, 0, 92),
		BackgroundColor3 = Theme.Colors.Card,
		LayoutOrder = upgrade.Order,
		Parent = list,
	})
	UIUtil.Corner(frame, 14)
	UIUtil.Stroke(frame, color, 2, 0.5)

	-- Icône
	local iconBack = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(60, 60),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundColor3 = Theme.Colors.PanelLight,
		Parent = frame,
	})
	UIUtil.Corner(iconBack, UDim.new(1, 0))
	UIUtil.Stroke(iconBack, color, 2)
	UIUtil.Label({
		Text = upgrade.Icon,
		Size = UDim2.fromScale(0.75, 0.75),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 40,
		Parent = iconBack,
	})

	-- Textes
	UIUtil.Label({
		Text = upgrade.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 0, 22),
		Position = UDim2.fromOffset(78, 8),
		MaxTextSize = 18,
		Parent = frame,
	})
	local levelLabel = UIUtil.Label({
		Text = "Niv. 0",
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 0, 18),
		Position = UDim2.fromOffset(78, 30),
		MaxTextSize = 15,
		Parent = frame,
	})
	UIUtil.Label({
		Text = Formulas.DescribeUpgrade(upgrade, NumberFormatter.Format),
		TextColor3 = Theme.Colors.Text,
		Font = Theme.Fonts.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 0, 18),
		Position = UDim2.fromOffset(78, 50),
		MaxTextSize = 14,
		Parent = frame,
	})
	local totalLabel = UIUtil.Label({
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 0, 16),
		Position = UDim2.fromOffset(78, 70),
		MaxTextSize = 13,
		Parent = frame,
	})

	-- Bouton d'achat
	local button = UIUtil.NeonButton({
		Size = UDim2.fromOffset(100, 64),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Color = color,
		TextColor3 = Theme.Colors.TextDark,
		MaxTextSize = 18,
		Parent = frame,
	})

	local card = { Frame = frame, Button = button, Level = levelLabel, Total = totalLabel }
	button.Activated:Connect(function()
		if button:GetAttribute("Enabled") then
			requestBuy(upgrade.Id, card)
		else
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(button)
		end
	end)
	cards[upgrade.Id] = card
end

-- Met à jour toutes les cartes de l'onglet affiché
function Shop.Refresh()
	local data = ClientState.Data
	if not data then
		return
	end
	local money = ClientState.GetDisplayDopamine()

	for _, upgrade in ipairs(Config.Upgrades) do
		local card = cards[upgrade.Id]
		local visible = upgrade.Category == currentCategory
		card.Frame.Visible = visible
		if visible then
			local level = data.Upgrades[upgrade.Id] or 0
			local amount, cost = Formulas.GetPurchase(upgrade, level, buyMode, money)
			local maxed = Formulas.GetRemainingLevels(upgrade, level) <= 0

			card.Level.Text = upgrade.MaxLevel and upgrade.MaxLevel == 1 and "" or ("Niv. " .. level)
			card.Total.Text = totalText(upgrade, level)

			if maxed then
				card.Button.Text = (upgrade.MaxLevel == 1) and "ACHETÉ ✔" or "MAX"
				UIUtil.SetButtonEnabled(card.Button, false)
			else
				local prefix = amount > 1 and ("+" .. amount .. "\n") or ""
				card.Button.Text = prefix .. "💧 " .. NumberFormatter.Format(cost)
				UIUtil.SetButtonEnabled(card.Button, money >= cost)
			end
		end
	end

	for categoryId, tab in pairs(tabButtons) do
		local selected = categoryId == currentCategory
		tab.BackgroundColor3 = selected and CATEGORY_COLORS[categoryId] or Theme.Colors.PanelLight
		tab.TextColor3 = selected and Theme.Colors.TextDark or Theme.Colors.Text
	end
end

function Shop.Build(parent: Frame)
	local panel = UIUtil.Create("Frame", {
		Name = "Shop",
		Size = UDim2.new(0, 340, 1, -86),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 72),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		Parent = parent,
	})
	UIUtil.Corner(panel, 20)
	local stroke = UIUtil.Stroke(panel, Color3.new(1, 1, 1), 3)
	UIUtil.Gradient(stroke, nil, 90)

	UIUtil.Label({
		Text = "🛒 BOUTIQUE",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Pink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -120, 0, 34),
		Position = UDim2.fromOffset(14, 10),
		MaxTextSize = 22,
		Parent = panel,
	})

	-- Mode d'achat (x1 -> x10 -> MAX)
	local modeButton = UIUtil.NeonButton({
		Text = "x1",
		Size = UDim2.fromOffset(84, 34),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Color = Theme.Colors.Purple,
		MaxTextSize = 18,
		Parent = panel,
	})
	modeButton.Activated:Connect(function()
		local index = table.find(BUY_MODES, buyMode) or 1
		buyMode = BUY_MODES[index % #BUY_MODES + 1]
		modeButton.Text = BUY_MODE_LABELS[buyMode]
		SoundManager.Play("Open", 1.3)
		Shop.Refresh()
	end)

	-- Onglets
	local tabs = UIUtil.Create("Frame", {
		Size = UDim2.new(1, -24, 0, 36),
		Position = UDim2.fromOffset(12, 52),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		Parent = tabs,
	})
	local tabCount = #Config.ShopCategories
	for index, category in ipairs(Config.ShopCategories) do
		local tab = UIUtil.NeonButton({
			Text = category.Name,
			Font = Theme.Fonts.Title,
			Size = UDim2.new(1 / tabCount, -6 * (tabCount - 1) / tabCount, 1, 0),
			Color = Theme.Colors.PanelLight,
			LayoutOrder = index,
			MaxTextSize = 14,
			Parent = tabs,
		})
		tab.Activated:Connect(function()
			currentCategory = category.Id
			SoundManager.Play("Open", 1.1)
			Shop.Refresh()
		end)
		tabButtons[category.Id] = tab
	end

	-- Liste défilante des cartes
	local list = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, -16, 1, -104),
		Position = UDim2.fromOffset(10, 96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Cyan,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = list,
	})
	UIUtil.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = list })

	for _, upgrade in ipairs(Config.Upgrades) do
		createCard(list, upgrade)
	end

	ClientState.Changed:Connect(Shop.Refresh)
	-- Rafraîchit aussi régulièrement (l'argent affiché augmente en continu)
	task.spawn(function()
		while panel.Parent do
			Shop.Refresh()
			task.wait(0.2)
		end
	end)

	return panel
end

return Shop
