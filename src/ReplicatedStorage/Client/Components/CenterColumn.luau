--[[
	CenterColumn (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > CenterColumn

	La colonne centrale, volontairement toute simple (comme au début d'un
	certain "clicker de stimulation") :
	  - le chapeau équipé (emoji) posé sur le bouton ;
	  - le bouton gris "Clique-moi" (couleurs selon le cosmétique "Skin") ;
	  - "12 345 Dopamine" (gros chiffre + unité plus discrète) puis
	    "123 Dopamine par seconde" ;
	  - la bannière du Dopamine Rush (quand il est actif) ;
	  - les indicateurs Robux : 👑 VIP, 💎 bonus des passes, ⏱️ boost avec
	    compte à rebours, 🤖 auto-clic (+ petit robot qui tape le bouton) ;
	  - les pastilles des menus (Temps d'écran, Boutique, Succès, Quêtes,
	    Classement (toujours visible), Cadeau, 🎨 Thèmes, 💎 Robux, ⚙️, et
	    🛠️ Test UNIQUEMENT dans Studio) avec badges rouges ;
	  - la jauge de combo (si la Feature "Combo" est débloquée) ;
	  - la barre d'améliorations (UpgradeBar).
	Occupe x ∈ [centre-330, centre+330], y ∈ [28, ~430] de la toile.
	v5 : textes traduits (Locale) ; sur téléphone les pastilles des menus
	tiennent sur UNE ligne qui défile horizontalement (zones tactiles de
	44 px), la largeur est limitée par les slots de côté (Slots) et tout se
	réajuste si l'écran change (Interface.DeviceChanged).
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
local Slots = require(Client.Slots)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Locale = require(ReplicatedStorage.Shared.Locale)

local CenterColumn = {}

-- Le bouton "💎 Robux" n'apparaît que si une offre est configurée (ou dans Studio)
local function robuxShopVisible(): boolean
	return Config.IsSellingForRobux == true or RunService:IsStudio()
end

-- La pastille "🛠️ Test" (panneau de test) n'existe que dans Studio
local function debugVisible(): boolean
	return RunService:IsStudio()
end

-- Pastilles des menus (Feature = nil : toujours visible ; Visible = fonction optionnelle).
-- Text : anglais, traduit à la construction (Locale.T)
local PILLS = {
	{ Id = "ScreenTime", Text = "⏱️ Screen Time", Color = Theme.Colors.Dark, Feature = "ScreenTime", Panel = "ScreenTime" },
	{ Id = "ItemShop", Text = "🛒 Shop", Color = Theme.Colors.Green, Feature = "ItemShop", Panel = "ItemShop" },
	{ Id = "Achievements", Text = "🏆 Achievements", Color = Theme.Colors.Purple, Feature = "Achievements", Panel = "Achievements" },
	{ Id = "Quests", Text = "📜 Quests", Color = Theme.Colors.Orange, Feature = "Quests", Panel = "Quests" },
	{ Id = "Leaderboard", Text = "🥇 Leaderboard", Color = Theme.Colors.Blue, Feature = nil, Panel = "Leaderboard" },
	{ Id = "Daily", Text = "🎁 Gift", Color = Theme.Colors.Pink, Feature = "Daily", Panel = "Daily" },
	{ Id = "Themes", Text = "🎨 Themes", Color = Theme.Colors.Cyan, Feature = nil, Panel = "Themes" },
	{ Id = "RobuxShop", Text = "💎 Robux", Color = Theme.Colors.Robux, Feature = nil, Panel = "RobuxShop", Visible = robuxShopVisible },
	{ Id = "Settings", Text = "⚙️", Color = Theme.Colors.ButtonBottom, Feature = nil, Panel = "Settings", Round = true },
	{ Id = "Debug", Text = "🛠️ Test", Color = Theme.Colors.Red, Feature = nil, Panel = "Debug", Visible = debugVisible },
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
local robotLabel: TextLabel
local counterRow: Frame
local counterLabel: TextLabel -- le nombre
local unitLabel: TextLabel -- "Dopamine"
local counterScale: UIScale
local perSecondLabel: TextLabel
local statusLeft: Frame
local vipChip: Frame
local bonusChip: Frame
local boostCard: Frame
local boostTitle: TextLabel
local boostTimer: TextLabel
local rushBanner: Frame
local rushLabel: TextLabel
local comboBar: Frame
local comboFill: Frame
local comboLabel: TextLabel
local pills = {} -- [Id] = { Button, Holder, Badge, Def }
local pillsStack: Frame -- pile verticale qui contient la rangée des pastilles
local pillsRow: GuiObject? = nil
local pillsDevice = "" -- profil pour lequel la rangée a été construite

local seenAchievements: number? = nil -- succès déjà vus (badge "Succès")
local counterFlashUntil = 0 -- le compteur brille en doré (gros gain) jusqu'à cette heure
local counterFlashing = false
local robotClock = 0
local robotFloatClock = 0
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

	-- Son de clic choisi dans les paramètres ; il monte dans les aigus avec le combo
	SoundManager.PlayClick(0.95 + ratio * 0.6 + random:NextNumber(0, 0.08))

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
	UIUtil.Shadow(clickButton, 4, 0.8, 3)

	clickLabel = UIUtil.Label({
		Text = Locale.T("Click me"),
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

	-- Petit robot (Game Pass "Auto-clic") posé sur le coin haut-gauche du bouton
	robotLabel = UIUtil.Label({
		Name = "Robot",
		Text = "🤖",
		Size = UDim2.fromOffset(34, 34),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 10, 0, 4),
		Rotation = 0,
		ZIndex = 5,
		MaxTextSize = 30,
		Visible = false,
		Parent = buttonHolder,
	})

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

-- Largeur max de la rangée des pastilles (téléphone : entre les slots de côté)
local function pillsRowWidth(): number
	if Interface.IsPhone() then
		return math.clamp(Slots.GetCenterClearWidth(), 360, 664)
	end
	return 664
end

-- (Re)construit la rangée des pastilles selon l'appareil :
--   PC / tablette : lignes qui passent à la ligne (Wraps) ;
--   téléphone : UNE ligne qui défile horizontalement.
local function buildPills(parent: Frame, order: number)
	if pillsRow then
		pillsRow:Destroy()
		pillsRow = nil
	end
	table.clear(pills)
	local phone = Interface.IsPhone()
	local height = Interface.IsTouch() and Theme.TouchTarget or PILL_HEIGHT
	-- Marge verticale du support (place pour le badge rouge sur téléphone)
	local holderPad = phone and 12 or 6
	local buttonY = phone and 7 or 3
	pillsDevice = Interface.Device

	local row: GuiObject
	if phone then
		row = UIUtil.Create("ScrollingFrame", {
			Name = "Pills",
			Size = UDim2.fromOffset(pillsRowWidth(), height + holderPad),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 0,
			ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
			LayoutOrder = order,
			Parent = parent,
		})
		UIUtil.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			Parent = row,
		})
	else
		row = UIUtil.Create("Frame", {
			Name = "Pills",
			Size = UDim2.fromOffset(664, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = parent,
		})
	end
	pillsRow = row
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Wraps = not phone,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})

	for index, def in ipairs(PILLS) do
		-- Support (6 px de marge verticale entre deux lignes de pastilles)
		local holder = UIUtil.Create("Frame", {
			Name = def.Id,
			Size = UDim2.fromOffset(def.Round and height or 0, height + holderPad),
			AutomaticSize = def.Round and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Visible = def.Feature == nil and (def.Visible == nil or def.Visible()),
			Parent = row,
		})
		local button = UIUtil.PillButton({
			Name = "Button",
			Text = Locale.T(def.Text),
			Color = def.Color,
			TextColor3 = def.Round and Theme.Colors.Text or Theme.Colors.TextLight,
			Height = height,
			TextSize = def.Round and math.floor(height * 0.56) or math.floor(height * 0.45),
			Round = def.Round,
			Position = UDim2.fromOffset(0, buttonY),
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
		UIUtil.Shadow(button, 2, 0.86, 2)
		local badge = UIUtil.Badge(button, 22)
		badge.Position = UDim2.new(1, -2, 0, phone and 6 or 2)
		UIUtil.Create("UIScale", { Name = "PopScale", Parent = holder })

		button.Activated:Connect(function()
			if not PanelManager.IsRegistered(def.Panel) then
				SoundManager.Play("Error", 0.8)
				UIUtil.Shake(button)
				return
			end
			PanelManager.Toggle(def.Panel)
		end)
		pills[def.Id] = { Button = button, Holder = holder, Badge = badge, Def = def }
	end
	return row
end

-- Le bandeau Rush se superpose à la ligne "par seconde" (hors de la pile) :
-- il ne pousse pas la barre d'améliorations sur les emplacements du bas
local function buildRush(parent: GuiObject)
	rushBanner = UIUtil.Create("Frame", {
		Name = "RushBanner",
		Size = UDim2.fromOffset(330, 28),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.Yellow,
		ZIndex = 2,
		Visible = false,
		Parent = parent,
	})
	UIUtil.Corner(rushBanner, UDim.new(1, 0))
	UIUtil.Stroke(rushBanner, Theme.Colors.Border, 1.5)
	UIUtil.Shadow(rushBanner, 3, 0.84, 2)
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
		Text = Locale.T("COMBO %s", "x1"),
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -10, 1, -4),
		Position = UDim2.fromOffset(5, 2),
		ZIndex = 2,
		MaxTextSize = 14,
		Parent = comboBar,
	})
end

-- Indicateurs Robux, de chaque côté du bouton (hors de la pile : ils ne
-- poussent jamais la barre d'améliorations sur les emplacements du bas).
--   gauche : 👑 VIP, 💎 bonus des Game Passes ; droite : ⏱️ boost + minuteur.
-- `buttonCenterX` / `buttonCenterY` : centre du bouton dans la colonne.
local function buildStatus(column: Frame, buttonCenterX: number, buttonCenterY: number)
	statusLeft = UIUtil.Create("Frame", {
		Name = "StatusLeft",
		Size = UDim2.fromOffset(70, 56),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(buttonCenterX - BUTTON_SIZE.X / 2 - 8, buttonCenterY),
		BackgroundTransparency = 1,
		Parent = column,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = statusLeft,
	})
	local function chip(name: string, text: string, color: Color3, textColor: Color3, chipOrder: number): Frame
		local frame = UIUtil.Chip({
			Name = name,
			Text = text,
			Color = color,
			TextColor3 = textColor,
			Height = 22,
			TextSize = 13,
			LayoutOrder = chipOrder,
			Visible = false,
			Parent = statusLeft,
		})
		UIUtil.Gradient(frame, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(225, 225, 225)), 90)
		UIUtil.Create("UIScale", { Name = "PopScale", Parent = frame })
		return frame
	end
	vipChip = chip("VIP", "👑 VIP", Theme.Colors.Premium, Theme.Colors.TextDark, 1)
	bonusChip = chip("Bonus", "💎 x1", Theme.Colors.Purple, Theme.Colors.TextLight, 2)

	-- Carte du boost : "⏱️ x2" + minuteur
	boostCard = UIUtil.Create("Frame", {
		Name = "Boost",
		Size = UDim2.fromOffset(62, 50),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(buttonCenterX + BUTTON_SIZE.X / 2 + 8, buttonCenterY),
		BackgroundColor3 = Theme.Colors.Boost,
		Visible = false,
		Parent = column,
	})
	UIUtil.Corner(boostCard, Theme.Radius.M)
	UIUtil.Stroke(boostCard, Theme.Colors.Border, 1.5, 0.3)
	UIUtil.Gradient(boostCard, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)), 90)
	UIUtil.Create("UIScale", { Name = "PopScale", Parent = boostCard })
	UIUtil.Shadow(boostCard, 3, 0.85, 2)
	boostTitle = UIUtil.Label({
		Text = "⏱️ x2",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextLight,
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.fromOffset(4, 5),
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = boostCard,
	})
	boostTimer = UIUtil.Label({
		Text = "0:00",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextLight,
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.fromOffset(4, 26),
		MaxTextSize = 15,
		ZIndex = 2,
		Parent = boostCard,
	})
	for _, label in ipairs({ boostTitle, boostTimer }) do
		local stroke = UIUtil.Stroke(label, Color3.fromRGB(120, 40, 0), 1, 0.5)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end
end

local function chipText(frame: Frame, text: string)
	local label = frame:FindFirstChild("Label") :: TextLabel?
	if label and label.Text ~= text then
		label.Text = text
	end
end

-- Montre / cache un indicateur (avec un petit "pop" à l'apparition)
local function setChipVisible(frame: GuiObject, visible: boolean)
	if frame.Visible == visible then
		return
	end
	frame.Visible = visible
	if visible then
		UIUtil.Pop(frame, 0.3, 0.4)
	end
end

-- Mise à jour des indicateurs + animation du robot (à chaque image)
local function updateStatus(dt: number)
	local data = ClientState.Data
	if not data then
		return
	end

	setChipVisible(vipChip, ClientState.IsVIP())

	local passMultiplier = ClientState.GetPassMultiplier()
	setChipVisible(bonusChip, passMultiplier > 1.001)
	if bonusChip.Visible then
		chipText(bonusChip, "💎 " .. NumberFormatter.Multiplier(passMultiplier))
	end

	local boostMultiplier, remaining = ClientState.GetBoost()
	setChipVisible(boostCard, remaining > 0)
	if remaining > 0 then
		local title = "⏱️ " .. NumberFormatter.Multiplier(boostMultiplier)
		if boostTitle.Text ~= title then
			boostTitle.Text = title
		end
		local clock = UIUtil.FormatClock(remaining)
		if boostTimer.Text ~= clock then
			boostTimer.Text = clock
		end
		-- Pulsation douce (plus rapide dans la dernière minute)
		local speed = remaining < 60 and 9 or 3
		boostCard.Rotation = math.sin(os.clock() * speed) * 3
	end

	-- Auto-clic (Game Pass) : petit robot qui tape le coin du bouton
	local hasAuto = ClientState.HasPass("AutoClick")
	if robotLabel.Visible ~= hasAuto then
		robotLabel.Visible = hasAuto
		if hasAuto then
			UIUtil.Pop(robotLabel, 0.2, 0.5)
		end
	end
	if hasAuto then
		local autoPass = Config.GamePassesById.AutoClick
		local rate = (autoPass and tonumber(autoPass.AutoClicksPerSecond)) or 1
		robotClock += dt * rate
		-- Petit coup de tête à chaque "clic" du robot
		local phase = robotClock % 1
		robotLabel.Rotation = phase < 0.35 and 18 * math.sin(phase / 0.35 * math.pi) or 0
		-- Toutes les secondes : "+X" discret (gain approximatif des clics auto)
		robotFloatClock += dt
		if robotFloatClock >= 1 then
			robotFloatClock = 0
			local gain = (tonumber(data.ClickValue) or 0) * rate
			if gain > 0 and effectsLayer then
				local center = Interface.GetCanvasCenter(robotLabel)
				Effects.FloatingText(effectsLayer, UDim2.fromOffset(center.X - 6, center.Y - 16), "+" .. formatAmount(gain), Theme.Colors.Cyan, 18)
			end
		end
	end
end

-- Gros gain (bonus, jackpot, achat...) : le compteur grossit et brille
local function counterCelebrate(strength: number)
	counterScale.Scale = 1 + 0.08 * strength
	UIUtil.Tween(counterScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Elastic)
	counterFlashUntil = os.clock() + 0.8
end

----------------------------------------------------------------------
-- Mises à jour
----------------------------------------------------------------------

local function applyDarkMode(dark: boolean)
	local textColor = dark and Theme.DarkColors.Text or Theme.Colors.Text
	local dimColor = dark and Theme.DarkColors.TextDim or Theme.Colors.TextDim
	counterLabel.TextColor3 = textColor
	unitLabel.TextColor3 = dimColor
	perSecondLabel.TextColor3 = dimColor
	for _, label in ipairs({ counterLabel, unitLabel }) do
		local counterStroke = label:FindFirstChild("DarkStroke") :: UIStroke?
		if counterStroke then
			counterStroke.Enabled = dark
		end
	end
	local perSecondStroke = perSecondLabel:FindFirstChild("DarkStroke") :: UIStroke?
	if perSecondStroke then
		perSecondStroke.Enabled = dark
	end
end

local function refreshPills(instant: boolean?)
	local skipPop = instant == true
	for _, pill in pairs(pills) do
		local feature = pill.Def.Feature
		local shouldShow = (feature == nil or ClientState.HasFeature(feature))
			and (pill.Def.Visible == nil or pill.Def.Visible())
		if shouldShow and not pill.Holder.Visible then
			pill.Holder.Visible = true
			local scale = pill.Holder:FindFirstChild("PopScale") :: UIScale?
			if scale and not skipPop then
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
		local dopamine = ClientState.GetConfirmedDopamine()
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

	-- Classement : couronne quand tu es 1er du serveur (au moins 2 joueurs)
	local leaderboard = pills.Leaderboard
	if leaderboard then
		local rank, count = ClientState.GetServerRank()
		UIUtil.SetBadge(leaderboard.Badge, (rank == 1 and count >= 2) and "👑" or "")
	end

	-- Thèmes : thèmes achetables en Dopamine, pas encore possédés, qu'on peut se payer
	local themes = pills.Themes
	if themes then
		local owned = (type(data.Themes) == "table" and data.Themes.Owned) or {}
		local dopamine = ClientState.GetConfirmedDopamine()
		local affordable = 0
		for _, theme in ipairs(Config.Themes) do
			local cost = tonumber(theme.Cost)
			if cost and cost > 0 and not owned[theme.Id] and dopamine >= cost then
				affordable += 1
			end
		end
		UIUtil.SetBadge(themes.Badge, affordable)
	end
end

local function onState(data)
	perSecondLabel.Text = Locale.T("%s Dopamine per second", formatAmount(data.PerSecond or 0))
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
	buildStatus(column, 350, 40 + BUTTON_SIZE.Y / 2)

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
		Padding = UDim.new(0, 3), -- tout doit tenir au-dessus des emplacements du bas (y <= 425)
		Parent = stack,
	})

	-- Compteur : gros nombre + unité plus discrète, alignés sur la même ligne
	counterRow = UIUtil.Create("Frame", {
		Name = "Counter",
		Size = UDim2.fromOffset(620, 46),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = stack,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = counterRow,
	})
	counterScale = UIUtil.Create("UIScale", { Parent = counterRow })
	counterLabel = UIUtil.Create("TextLabel", {
		Name = "Number",
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = "0",
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Display,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = 1,
		Parent = counterRow,
	})
	unitLabel = UIUtil.Create("TextLabel", {
		Name = "Unit",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "Dopamine",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 24,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = 2,
		Parent = counterRow,
	})
	for _, label in ipairs({ counterLabel, unitLabel }) do
		local counterStroke = UIUtil.Stroke(label, Theme.Colors.TextDark, 2, 0.3)
		counterStroke.Name = "DarkStroke"
		counterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		counterStroke.Enabled = false
	end

	perSecondLabel = UIUtil.Label({
		Name = "PerSecond",
		Text = Locale.T("%s Dopamine per second", "0"),
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

	buildRush(perSecondLabel)
	pillsStack = stack
	buildPills(stack, 5)
	buildCombo(stack, 6)
	local upgradeBar = UpgradeBar.Build(stack, floatingLayer)
	upgradeBar.LayoutOrder = 7

	-- Signaux
	ClientState.Changed:Connect(onState)
	ClientState.NotifyReceived:Connect(function(payload)
		local kind = payload.Type
		if kind == "Purchase" or kind == "Jackpot" then
			counterCelebrate(2)
		elseif kind == "Bonus" or kind == "Quest" or kind == "Achievement" then
			counterCelebrate(1)
		end
	end)
	ClientState.FeaturesChanged:Connect(function()
		refreshPills()
	end)
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
		counterLabel.Text = formatAmount(ClientState.UpdateDisplay(dt))
		-- Gros gain : le nombre brille en doré un instant
		local flashing = os.clock() < counterFlashUntil
		if flashing or counterFlashing then
			local base = ClientState.DarkMode and Theme.DarkColors.Text or Theme.Colors.Text
			local t = flashing and math.clamp((counterFlashUntil - os.clock()) / 0.8, 0, 1) or 0
			counterLabel.TextColor3 = base:Lerp(Theme.Colors.Gold, t)
			counterFlashing = flashing
		end

		updateStatus(dt)

		if comboBar.Visible then
			local meter = ClientState.GetComboMeter()
			comboFill.Size = UDim2.fromScale(meter / 100, 1)
			comboLabel.Text = Locale.T("COMBO %s", NumberFormatter.Multiplier(Formulas.GetComboMultiplier(meter)))
			comboBar.Rotation = meter >= 99.5 and math.sin(os.clock() * 30) * 1.5 or 0
		end

		local rush = ClientState.Rush
		local remaining = (rush.EndsAt or 0) - workspace:GetServerTimeNow()
		local active = rush.Active == true and remaining > 0
		if rushBanner.Visible ~= active then
			rushBanner.Visible = active
		end
		if active then
			rushLabel.Text = string.format(
				"⚡ %s x%s — %ds",
				Locale.T(tostring(rush.Name or "RUSH")),
				tostring(rush.Multiplier or 2),
				math.ceil(remaining)
			)
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

	-- Écran qui change (téléphone <-> tablette, rotation) : pastilles et largeurs
	local function relayout()
		if Interface.Device ~= pillsDevice then
			buildPills(pillsStack, 5)
			refreshPills(true)
			refreshBadges()
		elseif pillsRow and pillsRow:IsA("ScrollingFrame") then
			local row = pillsRow :: ScrollingFrame
			row.Size = UDim2.fromOffset(pillsRowWidth(), row.Size.Y.Offset)
		end
	end
	Interface.DeviceChanged:Connect(relayout)
	Slots.Changed:Connect(relayout)

	if ClientState.Data then
		onState(ClientState.Data)
		refreshPills()
	end
	return column
end

return CenterColumn
