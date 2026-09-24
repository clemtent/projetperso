--[[
	CenterColumn (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > CenterColumn

	La colonne centrale, volontairement toute simple (comme au début d'un
	certain "clicker de stimulation") :
	  - le chapeau équipé (emoji) posé sur le bouton ;
	  - le bouton gris "Clique-moi" (couleurs selon le cosmétique "Skin") ;
	  - "12 345 Dopamine" puis "123 Dopamine par seconde" ;
	  - la bannière du Dopamine Rush (quand il est actif) ;
	  - les pastilles des menus (Temps d'écran, Boutique, Succès, Quêtes,
	    Classement, Cadeau, ⚙️) avec badges rouges ;
	  - la jauge de combo (si la Feature "Combo" est débloquée) ;
	  - la barre d'améliorations (UpgradeBar).
	Occupe x ∈ [centre-330, centre+330], y ∈ [28, ~430] de la toile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local PanelManager = require(script.Parent.PanelManager)
local UpgradeBar = require(script.Parent.UpgradeBar)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local CenterColumn = {}

-- Pastilles des menus (Feature = nil : toujours visible)
local PILLS = {
	{ Id = "ScreenTime", Text = "⏱️ Temps d'écran", Color = Theme.Colors.Dark, Feature = "ScreenTime", Panel = "ScreenTime" },
	{ Id = "ItemShop", Text = "🛒 Boutique", Color = Theme.Colors.Green, Feature = "ItemShop", Panel = "ItemShop" },
	{ Id = "Achievements", Text = "🏆 Succès", Color = Theme.Colors.Purple, Feature = "Achievements", Panel = "Achievements" },
	{ Id = "Quests", Text = "📜 Quêtes", Color = Theme.Colors.Orange, Feature = "Quests", Panel = "Quests" },
	{ Id = "Leaderboard", Text = "🥇 Classement", Color = Theme.Colors.Blue, Feature = "Leaderboard", Panel = "Leaderboard" },
	{ Id = "Daily", Text = "🎁 Cadeau", Color = Theme.Colors.Pink, Feature = "Daily", Panel = "Daily" },
	{ Id = "Settings", Text = "⚙️", Color = Theme.Colors.ButtonBottom, Feature = nil, Panel = "Settings", Round = true },
}

local BUTTON_SIZE = Vector2.new(184, 62)
local PILL_HEIGHT = 36

local random = Random.new()
local effectsLayer: Frame

local buttonHolder: Frame
local clickButton: TextButton
local clickLabel: TextLabel
local buttonGradient: UIGradient
local hatLabel: TextLabel
local counterLabel: TextLabel
local counterScale: UIScale
local perSecondLabel: TextLabel
local rushBanner: Frame
local rushLabel: TextLabel
local comboBar: Frame
local comboFill: Frame
local comboLabel: TextLabel
local pills = {} -- [Id] = { Button, Holder, Badge, Def }

local seenAchievements: number? = nil -- succès déjà vus (badge "Succès")
local currentSkin = ""
local currentHat = ""

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

-- "12 345" sous le million, "1.23M" au-delà, "2.5" pour les petites décimales
local function formatAmount(value: number): string
	if value >= 1e6 then
		return NumberFormatter.Format(value)
	elseif value < 10 and value % 1 ~= 0 then
		return NumberFormatter.Format(value)
	end
	return NumberFormatter.WithSpaces(value)
end

local function countTrue(map): number
	local count = 0
	if type(map) == "table" then
		for _, value in pairs(map) do
			if value then
				count += 1
			end
		end
	end
	return count
end

----------------------------------------------------------------------
-- Cosmétiques (chapeau + couleur du bouton)
----------------------------------------------------------------------

local function applySkin(skinId: string)
	if skinId == currentSkin then
		return
	end
	currentSkin = skinId
	local skin = Config.CosmeticsById[skinId]
	if skin and skin.Top and skin.Bottom then
		buttonGradient.Color = ColorSequence.new(skin.Top, skin.Bottom)
		clickLabel.TextColor3 = Theme.ContrastText(skin.Top:Lerp(skin.Bottom, 0.5))
	else
		buttonGradient.Color = ColorSequence.new(Theme.Colors.Button, Theme.Colors.ButtonBottom)
		clickLabel.TextColor3 = Theme.Colors.Text
	end
end

local function applyHat(hatId: string)
	if hatId == currentHat then
		return
	end
	currentHat = hatId
	local hat = Config.CosmeticsById[hatId]
	if hat then
		hatLabel.Text = hat.Icon
		hatLabel.Visible = true
		local scale = hatLabel:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.2
			UIUtil.Tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	else
		hatLabel.Visible = false
	end
end

----------------------------------------------------------------------
-- Clic sur le gros bouton
----------------------------------------------------------------------

local function onClick()
	local gain = ClientState.Click()
	if not gain then
		return
	end
	UpgradeBar.HideTooltip()

	-- Squish : on écrase le bouton puis il rebondit
	clickButton.Size = UDim2.fromScale(1.08, 0.84)
	UIUtil.Tween(clickButton, 0.4, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Elastic)

	-- Le chapeau saute un peu
	if hatLabel.Visible then
		hatLabel.Position = UDim2.new(0.5, 0, 0, 6)
		UIUtil.Tween(hatLabel, 0.35, { Position = UDim2.new(0.5, 0, 0, 18) }, Enum.EasingStyle.Bounce)
	end

	-- "+X" qui s'envole près du bouton (couleur selon le combo)
	local ratio = ClientState.GetComboMeter() / 100
	local color = ClientState.DarkMode and Theme.Colors.TextLight or Theme.Colors.Text
	if ratio > 0.75 then
		color = Theme.Colors.Red
	elseif ratio > 0.35 then
		color = Theme.Colors.Orange
	end
	local center = Interface.GetCanvasCenter(clickButton)
	local position = UDim2.fromOffset(center.X + random:NextNumber(-80, 80), center.Y - 30 + random:NextNumber(-14, 8))
	Effects.FloatingText(effectsLayer, position, "+" .. formatAmount(gain), color, 28 + ratio * 12)
	Effects.Burst(effectsLayer, UDim2.fromOffset(center.X + random:NextNumber(-40, 40), center.Y), nil, 4)

	-- Le son monte dans les aigus avec le combo
	SoundManager.Play("Click", 0.95 + ratio * 0.6 + random:NextNumber(0, 0.08))

	counterScale.Scale = 1.08
	UIUtil.Tween(counterScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildButton(column: Frame)
	buttonHolder = UIUtil.Create("Frame", {
		Name = "ClickerHolder",
		Size = UDim2.fromOffset(BUTTON_SIZE.X, BUTTON_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = column,
	})

	clickButton = UIUtil.Create("TextButton", {
		Name = "ClickButton",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), -- couleurs données par le dégradé
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
		Parent = buttonHolder,
	})
	UIUtil.Corner(clickButton, 12)
	UIUtil.Stroke(clickButton, Theme.Colors.Border, 1.5)
	buttonGradient = UIUtil.Gradient(clickButton, ColorSequence.new(Theme.Colors.Button, Theme.Colors.ButtonBottom), 90)

	clickLabel = UIUtil.Label({
		Text = "Clique-moi",
		Font = Theme.Fonts.Body,
		Size = UDim2.new(1, -20, 1, -16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
		MaxTextSize = 28,
		Parent = clickButton,
	})

	-- Chapeau posé sur le bouton
	hatLabel = UIUtil.Label({
		Name = "Hat",
		Text = "",
		Size = UDim2.fromOffset(60, 60),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 18),
		Rotation = -8,
		ZIndex = 4,
		MaxTextSize = 56,
		Visible = false,
		Parent = buttonHolder,
	})
	UIUtil.Create("UIScale", { Parent = hatLabel })

	-- Souris ET tactile (multi-touch compris)
	clickButton.InputBegan:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			onClick()
		end
	end)
	-- Survol : léger grossissement
	local hoverScale = UIUtil.Create("UIScale", { Parent = buttonHolder })
	clickButton.MouseEnter:Connect(function()
		UIUtil.Tween(hoverScale, 0.15, { Scale = 1.04 }, Enum.EasingStyle.Back)
	end)
	clickButton.MouseLeave:Connect(function()
		UIUtil.Tween(hoverScale, 0.15, { Scale = 1 })
	end)
end

local function buildPills(parent: Frame, order: number)
	local row = UIUtil.Create("Frame", {
		Name = "Pills",
		Size = UDim2.fromOffset(640, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Wraps = true,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})

	for index, def in ipairs(PILLS) do
		-- Support (6 px de marge verticale entre deux lignes de pastilles)
		local holder = UIUtil.Create("Frame", {
			Name = def.Id,
			Size = UDim2.fromOffset(def.Round and PILL_HEIGHT or 0, PILL_HEIGHT + 6),
			AutomaticSize = def.Round and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Visible = def.Feature == nil,
			Parent = row,
		})
		local button = UIUtil.PillButton({
			Name = "Button",
			Text = def.Text,
			Color = def.Color,
			TextColor3 = def.Round and Theme.Colors.Text or Theme.Colors.TextLight,
			Height = PILL_HEIGHT,
			TextSize = def.Round and 20 or 17,
			Round = def.Round,
			Position = UDim2.fromOffset(0, 3),
			Parent = holder,
		})
		if not def.Round then
			-- Contour du texte pour rester lisible sur les couleurs claires
			local stroke = UIUtil.Create("UIStroke", {
				Color = Theme.Colors.TextDark,
				Thickness = 1,
				Transparency = 0.55,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				Parent = button,
			})
			stroke.Name = "TextStroke"
		end
		local badge = UIUtil.Badge(button, 22)
		badge.Position = UDim2.new(1, -2, 0, 2)
		UIUtil.Create("UIScale", { Name = "PopScale", Parent = holder })

		button.Activated:Connect(function()
			PanelManager.Toggle(def.Panel)
		end)
		pills[def.Id] = { Button = button, Holder = holder, Badge = badge, Def = def }
	end
	return row
end

local function buildRush(parent: Frame, order: number)
	rushBanner = UIUtil.Create("Frame", {
		Name = "RushBanner",
		Size = UDim2.fromOffset(330, 28),
		BackgroundColor3 = Theme.Colors.Yellow,
		LayoutOrder = order,
		Visible = false,
		Parent = parent,
	})
	UIUtil.Corner(rushBanner, UDim.new(1, 0))
	UIUtil.Stroke(rushBanner, Theme.Colors.Border, 1.5)
	rushLabel = UIUtil.Label({
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		Size = UDim2.new(1, -16, 1, -6),
		Position = UDim2.fromOffset(8, 3),
		MaxTextSize = 18,
		Parent = rushBanner,
	})
end

local function buildCombo(parent: Frame, order: number)
	comboBar = UIUtil.Create("Frame", {
		Name = "ComboBar",
		Size = UDim2.fromOffset(300, 20),
		BackgroundColor3 = Theme.Colors.PanelLight,
		LayoutOrder = order,
		ClipsDescendants = true,
		Visible = false,
		Parent = parent,
	})
	UIUtil.Corner(comboBar, UDim.new(1, 0))
	UIUtil.Stroke(comboBar, Theme.Colors.Border, 1.5)
	comboFill = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = comboBar,
	})
	UIUtil.Corner(comboFill, UDim.new(1, 0))
	UIUtil.Gradient(comboFill, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Colors.Yellow),
		ColorSequenceKeypoint.new(0.5, Theme.Colors.Orange),
		ColorSequenceKeypoint.new(1, Theme.Colors.Red),
	}), 0)
	comboLabel = UIUtil.Label({
		Text = "COMBO x1",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -10, 1, -4),
		Position = UDim2.fromOffset(5, 2),
		ZIndex = 2,
		MaxTextSize = 14,
		Parent = comboBar,
	})
end

----------------------------------------------------------------------
-- Mises à jour
----------------------------------------------------------------------

local function applyDarkMode(dark: boolean)
	local textColor = dark and Theme.DarkColors.Text or Theme.Colors.Text
	local dimColor = dark and Theme.DarkColors.TextDim or Theme.Colors.TextDim
	counterLabel.TextColor3 = textColor
	perSecondLabel.TextColor3 = dimColor
	local counterStroke = counterLabel:FindFirstChild("DarkStroke") :: UIStroke?
	if counterStroke then
		counterStroke.Enabled = dark
	end
	local perSecondStroke = perSecondLabel:FindFirstChild("DarkStroke") :: UIStroke?
	if perSecondStroke then
		perSecondStroke.Enabled = dark
	end
end

local function refreshPills()
	for _, pill in pairs(pills) do
		local feature = pill.Def.Feature
		local shouldShow = feature == nil or ClientState.HasFeature(feature)
		if shouldShow and not pill.Holder.Visible then
			pill.Holder.Visible = true
			local scale = pill.Holder:FindFirstChild("PopScale") :: UIScale?
			if scale then
				scale.Scale = 0.2
				UIUtil.Tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		elseif not shouldShow and pill.Holder.Visible then
			pill.Holder.Visible = false
			if PanelManager.IsOpen(pill.Def.Panel) then
				PanelManager.Close()
			end
		end
	end
end

local function refreshBadges()
	local data = ClientState.Data
	if not data then
		return
	end

	-- Boutique : objets pas encore possédés qu'on peut se payer
	local shop = pills.ItemShop
	if shop then
		local owned = (data.Cosmetics and data.Cosmetics.Owned) or {}
		local dopamine = ClientState.GetTargetDopamine()
		local affordable = 0
		for _, cosmetic in ipairs(Config.Cosmetics) do
			if not owned[cosmetic.Id] and dopamine >= cosmetic.Cost then
				affordable += 1
			end
		end
		UIUtil.SetBadge(shop.Badge, affordable)
	end

	-- Succès : débloqués depuis la dernière ouverture du menu
	local achievements = pills.Achievements
	if achievements then
		local count = countTrue(data.Achievements)
		if seenAchievements == nil or PanelManager.IsOpen("Achievements") then
			seenAchievements = count
		end
		UIUtil.SetBadge(achievements.Badge, math.max(0, count - (seenAchievements or count)))
	end

	-- Cadeau : disponible ?
	local daily = pills.Daily
	if daily then
		UIUtil.SetBadge(daily.Badge, (data.Daily and data.Daily.Available) and "!" or "")
	end
end

local function onState(data)
	perSecondLabel.Text = formatAmount(data.PerSecond or 0) .. " Dopamine par seconde"
	comboBar.Visible = data.ComboEnabled == true
	local equipped = data.Cosmetics and data.Cosmetics.Equipped
	applySkin((equipped and equipped.Skin) or "")
	applyHat((equipped and equipped.Hat) or "")
	refreshBadges()
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- `parent` = calque Main ; `floatingLayer` = calque au-dessus des stimuli
-- (infobulle) ; `fxLayer` = calque des effets
function CenterColumn.Build(parent: Frame, floatingLayer: Frame, fxLayer: Frame)
	effectsLayer = fxLayer

	local column = UIUtil.Create("Frame", {
		Name = "CenterColumn",
		Size = UDim2.fromOffset(700, 410),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 24),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	buildButton(column)

	-- Pile verticale sous le bouton (les éléments cachés ne prennent pas de place)
	local stack = UIUtil.Create("Frame", {
		Name = "Stack",
		Size = UDim2.new(1, 0, 1, -(40 + BUTTON_SIZE.Y + 4)),
		Position = UDim2.fromOffset(0, 40 + BUTTON_SIZE.Y + 4),
		BackgroundTransparency = 1,
		Parent = column,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = stack,
	})

	counterLabel = UIUtil.Label({
		Name = "Counter",
		Text = "0 Dopamine",
		Font = Theme.Fonts.Number,
		Size = UDim2.fromOffset(320, 44),
		LayoutOrder = 1,
		MaxTextSize = 40,
		Parent = stack,
	})
	counterScale = UIUtil.Create("UIScale", { Parent = counterLabel })
	local counterStroke = UIUtil.Stroke(counterLabel, Theme.Colors.TextDark, 2, 0.3)
	counterStroke.Name = "DarkStroke"
	counterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	counterStroke.Enabled = false

	perSecondLabel = UIUtil.Label({
		Name = "PerSecond",
		Text = "0 Dopamine par seconde",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.fromOffset(320, 22),
		LayoutOrder = 2,
		MaxTextSize = 21,
		Parent = stack,
	})
	local perSecondStroke = UIUtil.Stroke(perSecondLabel, Theme.Colors.TextDark, 1.5, 0.4)
	perSecondStroke.Name = "DarkStroke"
	perSecondStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	perSecondStroke.Enabled = false

	buildRush(stack, 3)
	UIUtil.Create("Frame", { Name = "Spacer", Size = UDim2.fromOffset(1, 2), BackgroundTransparency = 1, LayoutOrder = 4, Parent = stack })
	buildPills(stack, 5)
	buildCombo(stack, 6)
	local upgradeBar = UpgradeBar.Build(stack, floatingLayer)
	upgradeBar.LayoutOrder = 7

	-- Signaux
	ClientState.Changed:Connect(onState)
	ClientState.FeaturesChanged:Connect(refreshPills)
	ClientState.DarkModeChanged:Connect(applyDarkMode)
	applyDarkMode(ClientState.DarkMode)
	PanelManager.Opened:Connect(function(name: string)
		if name == "Achievements" and ClientState.Data then
			seenAchievements = countTrue(ClientState.Data.Achievements)
			local pill = pills.Achievements
			if pill then
				UIUtil.SetBadge(pill.Badge, 0)
			end
		end
	end)

	-- Compteur lissé, jauge de combo, Rush : à chaque image
	local badgeClock = 0
	RunService.RenderStepped:Connect(function(dt: number)
		counterLabel.Text = formatAmount(ClientState.UpdateDisplay(dt)) .. " Dopamine"

		if comboBar.Visible then
			local meter = ClientState.GetComboMeter()
			comboFill.Size = UDim2.fromScale(meter / 100, 1)
			comboLabel.Text = "COMBO " .. NumberFormatter.Multiplier(Formulas.GetComboMultiplier(meter))
			comboBar.Rotation = meter >= 99.5 and math.sin(os.clock() * 30) * 1.5 or 0
		end

		local rush = ClientState.Rush
		local remaining = (rush.EndsAt or 0) - workspace:GetServerTimeNow()
		local active = rush.Active == true and remaining > 0
		if rushBanner.Visible ~= active then
			rushBanner.Visible = active
		end
		if active then
			rushLabel.Text = string.format("⚡ %s x%s — %ds", tostring(rush.Name or "RUSH"), tostring(rush.Multiplier or 2), math.ceil(remaining))
			rushBanner.Rotation = math.sin(os.clock() * 8) * 1.5
		end

		-- Badges (4 fois par seconde : la Dopamine monte en continu)
		badgeClock += dt
		if badgeClock >= 0.25 then
			badgeClock = 0
			refreshBadges()
		end
	end)

	-- Petit rappel tant que le joueur n'a jamais cliqué
	task.spawn(function()
		while buttonHolder.Parent do
			local data = ClientState.Data
			if data and data.Stats and (data.Stats.TotalClicks or 0) == 0 then
				UIUtil.Tween(buttonHolder, 0.25, { Rotation = 5 }, Enum.EasingStyle.Sine)
				task.wait(0.25)
				UIUtil.Tween(buttonHolder, 0.25, { Rotation = -5 }, Enum.EasingStyle.Sine)
				task.wait(0.25)
				UIUtil.Tween(buttonHolder, 0.25, { Rotation = 0 }, Enum.EasingStyle.Sine)
			end
			task.wait(2)
		end
	end)

	if ClientState.Data then
		onState(ClientState.Data)
		refreshPills()
	end
	return column
end

return CenterColumn
