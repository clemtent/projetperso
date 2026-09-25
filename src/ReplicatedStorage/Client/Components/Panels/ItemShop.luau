--[[
	ItemShop (ModuleScript) — boutique d'objets cosmétiques
	Emplacement : ReplicatedStorage > Client > Components > Panels > ItemShop

	Chapeaux (posés sur le bouton "Clique-moi") et couleurs du bouton.
	Présentation "premium" :
	  - bannière avec un aperçu EN DIRECT de ton bouton (survole une carte
	    pour l'essayer), ta collection et ton bonus ;
	  - onglets Tout / Chapeaux / Couleurs ;
	  - grandes cartes illustrées : vitrine au dégradé de la rareté avec
	    rayons lumineux, pastille de rareté, ruban "ÉQUIPÉ" / "POSSÉDÉ",
	    soulèvement au survol, prix en Dopamine, confettis à l'achat.
	Achat / équipement / retrait via la RemoteFunction "ItemShop".
	Chaque objet possédé donne un petit bonus permanent (Config.CosmeticBonus).
	Débloqué par l'amélioration "Boutique d'objets" (Feature "ItemShop").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local NeedDopamine = require(script.Parent.Parent.NeedDopamine)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)

-- Title / Subtitle en anglais : traduits par PanelManager
local ItemShop = {
	Title = "🛒 Shop",
	Subtitle = "Hats and colors for your button",
	Color = Theme.Colors.Green,
	Size = Vector2.new(780, 600),
}

-- Noms des emplacements (anglais, traduits à l'affichage)
local SLOT_NAMES = { Hat = "Hat", Skin = "Button color" }

local function slotName(slot: string?): string
	local name = slot and SLOT_NAMES[slot]
	return name and Locale.T(name) or ""
end
local HERO_TOP = Color3.fromRGB(40, 190, 120)
local HERO_BOTTOM = Color3.fromRGB(0, 160, 190)
local WHITE = Color3.new(1, 1, 1)

-- Rareté (d'après le prix)
local RARITIES = {
	{ Max = 1e5, Name = "Common", Color = Color3.fromRGB(120, 200, 140) },
	{ Max = 1e6, Name = "Rare", Color = Color3.fromRGB(60, 150, 255) },
	{ Max = 1e7, Name = "Epic", Color = Color3.fromRGB(170, 90, 240) },
	{ Max = 1e8, Name = "Legendary", Color = Color3.fromRGB(255, 170, 20) },
	{ Max = math.huge, Name = "Mythic", Color = Color3.fromRGB(255, 70, 150) },
}

type Rarity = { Max: number, Name: string, Color: Color3 }

type Card = {
	Cosmetic: any,
	Rarity: Rarity,
	Cell: Frame,
	Card: Frame,
	Stroke: UIStroke,
	Button: TextButton,
	Status: TextLabel,
	Ribbon: Frame,
	Rays: Frame,
	Hovered: boolean,
}

local cards: { [string]: Card } = {}
local cardList: { Card } = {}
local busy = false
local filter = "All"
local visible = false
local animation: RBXScriptConnection? = nil
local hoverId: string? = nil

-- Bannière
local previewButton: Frame
local previewGradient: UIGradient
local previewLabel: TextLabel
local previewHat: TextLabel
local previewCaption: TextLabel
local collectionChip: Frame
local bonusChip: Frame
local walletChip: Frame
local collectionBar: Frame

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function getCosmetics(data)
	local cosmetics = data and data.Cosmetics
	local owned = (cosmetics and cosmetics.Owned) or {}
	local equipped = (cosmetics and cosmetics.Equipped) or {}
	return owned, equipped
end

local function rarityOf(cost: number): Rarity
	for _, rarity in ipairs(RARITIES) do
		if cost < rarity.Max then
			return rarity
		end
	end
	return RARITIES[#RARITIES]
end

local function setChipText(chip: Frame, text: string)
	local label = chip:FindFirstChild("Label") :: TextLabel?
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function getDopamine(): number
	local ok, value = pcall(ClientState.GetConfirmedDopamine)
	if ok and type(value) == "number" then
		return value
	end
	local data = ClientState.Data
	return (data and data.Dopamine) or 0
end

----------------------------------------------------------------------
-- Aperçu du bouton (bannière)
----------------------------------------------------------------------

-- Montre le bouton avec la couleur `skinId` et le chapeau `hatId`
local function showPreview(skinId: string, hatId: string, caption: string)
	local skin = Config.CosmeticsById[skinId]
	if skin and skin.Top and skin.Bottom then
		previewGradient.Color = ColorSequence.new(skin.Top, skin.Bottom)
		previewLabel.TextColor3 = Theme.ContrastText(skin.Top:Lerp(skin.Bottom, 0.5))
	else
		previewGradient.Color = ColorSequence.new(Theme.Colors.Button, Theme.Colors.ButtonBottom)
		previewLabel.TextColor3 = Theme.Colors.Text
	end
	local hat = Config.CosmeticsById[hatId]
	local hatText = hat and hat.Icon or ""
	if previewHat.Text ~= hatText then
		previewHat.Text = hatText
		if hatText ~= "" then
			UIUtil.Pop(previewHat, 0.4, 0.35)
		end
	end
	previewCaption.Text = caption
end

-- Aperçu : l'objet survolé par-dessus ce que tu portes
local function refreshPreview()
	if not previewButton then
		return
	end
	local _, equipped = getCosmetics(ClientState.Data)
	local skinId = equipped.Skin or ""
	local hatId = equipped.Hat or ""
	local caption = Locale.T("Your button")
	local hovered = hoverId and Config.CosmeticsById[hoverId]
	if hovered then
		if hovered.Slot == "Skin" then
			skinId = hovered.Id
		else
			hatId = hovered.Id
		end
		caption = Locale.T("Trying: %s", Locale.T(tostring(hovered.Name)))
	end
	showPreview(skinId, hatId, caption)
end

----------------------------------------------------------------------
-- Achat / équipement
----------------------------------------------------------------------

local function celebrate(ui: Card)
	Effects.Confetti(70)
	local layer = Effects.GetLayer()
	if layer then
		local center = Interface.GetCanvasCenter(ui.Card)
		Effects.Burst(layer, UDim2.fromOffset(center.X, center.Y), ui.Rarity.Color, 18)
	end
end

-- Envoie une action au serveur ("buy" | "equip" | "unequip")
local function request(action: string, cosmetic)
	if busy then
		return
	end
	busy = true
	local ui = cards[cosmetic.Id]
	if ui and action == "buy" then
		ui.Button.Text = "…"
	end
	local ok, success, message = pcall(function()
		return Net.Function("ItemShop"):InvokeServer(action, cosmetic.Id)
	end)
	busy = false

	if ok and success then
		if action == "buy" then
			SoundManager.Play("Buy", 1.1)
			task.delay(0.1, SoundManager.Play, "Achievement", 1.4)
			if ui then
				celebrate(ui)
			end
			Notifications.Show({
				Title = Locale.T("%s: it's yours!", Locale.T(cosmetic.Name)),
				Text = Locale.T("+%s%% gains forever • equipped automatically", tostring(math.floor(Config.CosmeticBonus * 100 + 0.5))),
				Icon = cosmetic.Icon,
				Color = Theme.Colors.Green,
				Duration = 4,
			})
		else
			SoundManager.Play("Open", action == "equip" and 1.2 or 0.9)
		end
		if ui then
			UIUtil.Pop(ui.Card, action == "buy" and 1.12 or 1.06, 0.35)
		end
	else
		SoundManager.Play("Error", 0.7)
		if ui then
			UIUtil.Shake(ui.Button)
		end
		local text = ok and tostring(message or Locale.T("Not possible right now.")) or Locale.T("Network error, try again.")
		Notifications.Toast(text, Theme.Colors.Red)
	end
	if ClientState.Data then
		ItemShop.Update(ClientState.Data)
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildHero(content: Frame)
	local hero = UIUtil.Create("Frame", {
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, 106),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		Parent = content,
	})
	UIUtil.Corner(hero, Theme.Radius.L)
	UIUtil.Stroke(hero, HERO_BOTTOM:Lerp(Color3.new(0, 0, 0), 0.3), 1.5, 0.4)
	UIUtil.Gradient(hero, ColorSequence.new(HERO_TOP, HERO_BOTTOM), 20)

	-- Décor : grosses bulles translucides
	for index, info in ipairs({ { 0.92, 0.1, 120 }, { 0.78, 1.05, 90 }, { 0.62, -0.2, 60 }, { 0.99, 0.95, 50 } }) do
		local bubble = UIUtil.Create("Frame", {
			Name = "Bubble" .. index,
			Size = UDim2.fromOffset(info[3], info[3]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(info[1], info[2]),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.86,
			ZIndex = 2,
			Parent = hero,
		})
		UIUtil.Corner(bubble, UDim.new(1, 0))
	end
	for index, info in ipairs({ { "🎩", 0.9, 0.3, 30 }, { "👑", 0.76, 0.72, 26 }, { "🍬", 0.97, 0.78, 22 } }) do
		UIUtil.Label({
			Name = "Deco" .. index,
			Text = info[1],
			Size = UDim2.fromOffset(info[4] + 6, info[4] + 6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(info[2], info[3]),
			Rotation = (index % 2 == 0) and 12 or -14,
			TextTransparency = 0.25,
			MaxTextSize = info[4],
			ZIndex = 2,
			Parent = hero,
		})
	end

	-- Scène d'aperçu (à gauche)
	local stage = UIUtil.Create("Frame", {
		Name = "Stage",
		Size = UDim2.fromOffset(170, 86),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.1,
		ZIndex = 3,
		Parent = hero,
	})
	UIUtil.Corner(stage, Theme.Radius.M)
	UIUtil.Stroke(stage, WHITE, 2, 0.2)
	UIUtil.Gradient(stage, ColorSequence.new(WHITE, Color3.fromRGB(226, 236, 232)), 90)

	previewButton = UIUtil.Create("Frame", {
		Name = "PreviewButton",
		Size = UDim2.fromOffset(112, 38),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 48),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
		Parent = stage,
	})
	UIUtil.Corner(previewButton, 10)
	UIUtil.Stroke(previewButton, Theme.Colors.Border, 1.5)
	previewGradient = UIUtil.Gradient(previewButton, ColorSequence.new(Theme.Colors.Button, Theme.Colors.ButtonBottom), 90)
	previewLabel = UIUtil.Label({
		Text = Locale.T("Click me"),
		Size = UDim2.new(1, -12, 1, -10),
		Position = UDim2.fromOffset(6, 5),
		MaxTextSize = 17,
		ZIndex = 5,
		Parent = previewButton,
	})
	previewHat = UIUtil.Label({
		Name = "Hat",
		Text = "",
		Size = UDim2.fromOffset(34, 34),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 10),
		Rotation = -8,
		MaxTextSize = 30,
		ZIndex = 6,
		Parent = previewButton,
	})
	previewCaption = UIUtil.Label({
		Name = "Caption",
		Text = Locale.T("Your button"),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -12, 0, 14),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		MaxTextSize = 12,
		ZIndex = 4,
		Parent = stage,
	})

	-- Titre, sous-titre et statistiques (à droite)
	local title = UIUtil.Label({
		Name = "HeroTitle",
		Text = Locale.T("Item Shop"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -210, 0, 28),
		Position = UDim2.fromOffset(196, 10),
		MaxTextSize = 24,
		ZIndex = 3,
		Parent = hero,
	})
	local titleStroke = UIUtil.Stroke(title, Color3.fromRGB(0, 90, 80), 1.5, 0.5)
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	UIUtil.Label({
		Name = "HeroSubtitle",
		Text = Locale.T("Each item owned: +%d%% gains forever", math.floor(Config.CosmeticBonus * 100 + 0.5)),
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -210, 0, 16),
		Position = UDim2.fromOffset(196, 38),
		MaxTextSize = 14,
		ZIndex = 3,
		Parent = hero,
	})

	local chips = UIUtil.Create("Frame", {
		Name = "Chips",
		Size = UDim2.new(1, -210, 0, 26),
		Position = UDim2.fromOffset(196, 60),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = hero,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = chips,
	})
	local function heroChip(order: number): Frame
		return UIUtil.Chip({
			Text = "",
			Color = WHITE,
			TextColor3 = Theme.Colors.TextDark,
			Height = 24,
			TextSize = 13,
			LayoutOrder = order,
			ZIndex = 4,
			StrokeColor = WHITE,
			Parent = chips,
		})
	end
	collectionChip = heroChip(1)
	bonusChip = heroChip(2)
	walletChip = heroChip(3)

	-- Barre de collection (bas de la bannière)
	local track = UIUtil.Create("Frame", {
		Name = "Collection",
		Size = UDim2.new(1, -210, 0, 6),
		Position = UDim2.fromOffset(196, 92),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = hero,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	collectionBar = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = track,
	})
	UIUtil.Corner(collectionBar, UDim.new(1, 0))
end

local function buildCard(grid: ScrollingFrame, cosmetic)
	local rarity = rarityOf(tonumber(cosmetic.Cost) or 0)
	local cell = UIUtil.Create("Frame", {
		Name = cosmetic.Id,
		BackgroundTransparency = 1,
		LayoutOrder = cosmetic.Order or 0,
		Parent = grid,
	})
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 1, -6),
		Position = UDim2.fromOffset(0, 5),
		BackgroundColor3 = Theme.Colors.Card,
		ZIndex = 2,
		Parent = cell,
	})
	UIUtil.Corner(card, Theme.Radius.L)
	local stroke = UIUtil.Stroke(card, rarity.Color:Lerp(Color3.new(0, 0, 0), 0.2), 1.5, 0.35)
	UIUtil.Shadow(card, 3, 0.86, 2)

	-- Vitrine : dégradé de la rareté + rayons + objet
	local showcase = UIUtil.Create("Frame", {
		Name = "Showcase",
		Size = UDim2.new(1, -10, 0, 100),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(showcase, Theme.Radius.M)
	UIUtil.SoftGradient(showcase, rarity.Color, 90)
	local rays = UIUtil.Rays(showcase, WHITE, 6, 170, UDim2.fromScale(0.5, 0.55), 3)
	local glow = UIUtil.Create("Frame", {
		Name = "Glow",
		Size = UDim2.fromOffset(70, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		ZIndex = 3,
		Parent = showcase,
	})
	UIUtil.Corner(glow, UDim.new(1, 0))

	if cosmetic.Slot == "Skin" and cosmetic.Top and cosmetic.Bottom then
		local swatch = UIUtil.Create("Frame", {
			Name = "Swatch",
			Size = UDim2.fromOffset(96, 36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.58),
			BackgroundColor3 = WHITE,
			ZIndex = 4,
			Parent = showcase,
		})
		UIUtil.Corner(swatch, 9)
		UIUtil.Stroke(swatch, Theme.Colors.Border, 1.5)
		UIUtil.Gradient(swatch, ColorSequence.new(cosmetic.Top, cosmetic.Bottom), 90)
		UIUtil.Label({
			Text = Locale.T("Click me"),
			TextColor3 = Theme.ContrastText(cosmetic.Top:Lerp(cosmetic.Bottom, 0.5)),
			Size = UDim2.new(1, -8, 1, -8),
			Position = UDim2.fromOffset(4, 4),
			MaxTextSize = 15,
			ZIndex = 5,
			Parent = swatch,
		})
	else
		UIUtil.Label({
			Name = "Icon",
			Text = cosmetic.Icon,
			Size = UDim2.fromOffset(64, 64),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			MaxTextSize = 54,
			ZIndex = 4,
			Parent = showcase,
		})
	end

	-- Pastille de rareté
	local rarityChip = UIUtil.Chip({
		Name = "Rarity",
		Text = Locale.T(rarity.Name),
		Color = rarity.Color:Lerp(Color3.new(0, 0, 0), 0.1),
		TextColor3 = WHITE,
		Height = 18,
		TextSize = 11,
		ZIndex = 5,
		StrokeColor = WHITE,
		Parent = showcase,
	})
	rarityChip.Position = UDim2.fromOffset(6, 6)

	-- Ruban "ÉQUIPÉ" / "POSSÉDÉ"
	local ribbon = UIUtil.Chip({
		Name = "Ribbon",
		Text = Locale.T("EQUIPPED"),
		Color = Theme.Colors.Green,
		TextColor3 = Theme.Colors.TextDark,
		Height = 18,
		TextSize = 11,
		ZIndex = 5,
		Visible = false,
		Parent = showcase,
	})
	ribbon.AnchorPoint = Vector2.new(1, 0)
	ribbon.Position = UDim2.new(1, -6, 0, 6)

	UIUtil.Label({
		Name = "ItemName",
		Text = Locale.T(cosmetic.Name),
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -14, 0, 20),
		Position = UDim2.fromOffset(7, 110),
		MaxTextSize = 16,
		ZIndex = 3,
		Parent = card,
	})
	local status = UIUtil.Label({
		Name = "Status",
		Text = SLOT_NAMES[cosmetic.Slot] or "",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -14, 0, 15),
		Position = UDim2.fromOffset(7, 131),
		MaxTextSize = 13,
		ZIndex = 3,
		Parent = card,
	})

	local button = UIUtil.NeonButton({
		Name = "Action",
		Text = "",
		Size = UDim2.new(1, -18, 0, 34),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		Color = Theme.Colors.Green,
		CornerRadius = 17,
		MaxTextSize = 16,
		ZIndex = 4,
		Parent = card,
	})

	local ui: Card = {
		Cosmetic = cosmetic,
		Rarity = rarity,
		Cell = cell,
		Card = card,
		Stroke = stroke,
		Button = button,
		Status = status,
		Ribbon = ribbon,
		Rays = rays,
		Hovered = false,
	}

	button.Activated:Connect(function()
		local data = ClientState.Data
		if not data or busy then
			return
		end
		local owned, equipped = getCosmetics(data)
		if not owned[cosmetic.Id] then
			if not button:GetAttribute("Enabled") then
				SoundManager.Play("Error", 0.7)
				UIUtil.Shake(button)
				NeedDopamine.Offer((tonumber(cosmetic.Cost) or 0) - getDopamine())
				return
			end
			task.spawn(request, "buy", cosmetic)
		elseif equipped[cosmetic.Slot] == cosmetic.Id then
			task.spawn(request, "unequip", cosmetic)
		else
			task.spawn(request, "equip", cosmetic)
		end
	end)

	-- Survol : la carte se soulève et l'objet s'essaie sur l'aperçu
	local function hover(on: boolean)
		ui.Hovered = on
		UIUtil.Tween(card, 0.18, { Position = UDim2.fromOffset(0, on and 0 or 5) }, Enum.EasingStyle.Quad)
		stroke.Transparency = on and 0 or 0.35
		if on then
			hoverId = cosmetic.Id
		elseif hoverId == cosmetic.Id then
			hoverId = nil
		end
		refreshPreview()
	end
	card.MouseEnter:Connect(function()
		hover(true)
	end)
	card.MouseLeave:Connect(function()
		hover(false)
	end)

	cards[cosmetic.Id] = ui
	table.insert(cardList, ui)
end

local function applyFilter()
	for _, ui in ipairs(cardList) do
		ui.Cell.Visible = filter == "All" or ui.Cosmetic.Slot == filter
	end
end

function ItemShop.Build(content: Frame)
	buildHero(content)

	UIUtil.Tabs({
		Parent = content,
		Tabs = {
			{ Id = "All", Text = Locale.T("✨ All") },
			{ Id = "Hat", Text = Locale.T("🎩 Hats") },
			{ Id = "Skin", Text = Locale.T("🎨 Colors") },
		},
		Color = Theme.Colors.Green,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 116),
		Selected = filter,
		OnSelect = function(id: string)
			filter = id
			applyFilter()
			SoundManager.Play("Click", 1.3)
		end,
	})

	local grid = UIUtil.Create("ScrollingFrame", {
		Name = "Items",
		Size = UDim2.new(1, 0, 1, -160),
		Position = UDim2.fromOffset(0, 160),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.Green,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 10),
		Parent = grid,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.25, -9, 0, 202),
		CellPadding = UDim2.fromOffset(9, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	for _, cosmetic in ipairs(Config.Cosmetics) do
		buildCard(grid, cosmetic)
	end
	applyFilter()
	refreshPreview()
end

function ItemShop.Update(data)
	local owned, equipped = getCosmetics(data)
	local dopamine = getDopamine()
	local ownedCount = 0

	for id, ui in pairs(cards) do
		local cosmetic = ui.Cosmetic
		local isOwned = owned[id] == true
		local isEquipped = isOwned and equipped[cosmetic.Slot] == id
		if isOwned then
			ownedCount += 1
		end

		local ribbonLabel = ui.Ribbon:FindFirstChild("Label") :: TextLabel?
		if isEquipped then
			ui.Button.Text = Locale.T("Remove")
			ui.Button:SetAttribute("BaseColor", Theme.Colors.ButtonBottom)
			UIUtil.SetButtonEnabled(ui.Button, true)
			ui.Button.TextColor3 = Theme.Colors.Text
			ui.Status.Text = Locale.T("✔ On your button")
			ui.Status.TextColor3 = Theme.Colors.Green:Lerp(Color3.new(0, 0, 0), 0.35)
			ui.Ribbon.Visible = true
			ui.Ribbon.BackgroundColor3 = Theme.Colors.Green
			if ribbonLabel then
				ribbonLabel.Text = Locale.T("EQUIPPED")
			end
		elseif isOwned then
			ui.Button.Text = Locale.T("Equip")
			ui.Button:SetAttribute("BaseColor", Theme.Colors.Blue)
			UIUtil.SetButtonEnabled(ui.Button, true)
			ui.Button.TextColor3 = Theme.Colors.TextLight
			ui.Status.Text = Locale.T("Owned • %s", slotName(cosmetic.Slot))
			ui.Status.TextColor3 = Theme.Colors.TextDim
			ui.Ribbon.Visible = true
			ui.Ribbon.BackgroundColor3 = WHITE
			if ribbonLabel then
				ribbonLabel.Text = Locale.T("✔ OWNED")
			end
		else
			local cost = tonumber(cosmetic.Cost) or 0
			local affordable = dopamine >= cost
			ui.Button.Text = "💧 " .. NumberFormatter.Format(cost)
			ui.Button:SetAttribute("BaseColor", Theme.Colors.Green)
			UIUtil.SetButtonEnabled(ui.Button, affordable)
			ui.Button.TextColor3 = Theme.Colors.TextDark
			if affordable then
				ui.Status.Text = slotName(cosmetic.Slot)
				ui.Status.TextColor3 = Theme.Colors.TextDim
			else
				ui.Status.Text = Locale.T("%s short", NumberFormatter.Format(cost - dopamine))
				ui.Status.TextColor3 = Theme.Colors.Red
			end
			ui.Ribbon.Visible = false
		end
	end

	-- Bannière
	if collectionChip then
		local total = #Config.Cosmetics
		setChipText(collectionChip, string.format("🎒 %d / %d", ownedCount, total))
		setChipText(bonusChip, Locale.T("📈 +%d%%", math.floor(ownedCount * Config.CosmeticBonus * 100 + 0.5)))
		setChipText(walletChip, "💧 " .. NumberFormatter.Format(dopamine))
		collectionBar.Size = UDim2.fromScale(total > 0 and ownedCount / total or 0, 1)
		refreshPreview()
	end
end

function ItemShop.OnOpen()
	visible = true
	hoverId = nil
	refreshPreview()
	-- Rayons des vitrines qui tournent doucement (seulement fenêtre ouverte)
	if animation then
		animation:Disconnect()
	end
	animation = RunService.RenderStepped:Connect(function(dt: number)
		for _, ui in ipairs(cardList) do
			if ui.Cell.Visible then
				ui.Rays.Rotation = (ui.Rays.Rotation + dt * (ui.Hovered and 60 or 12)) % 360
			end
		end
	end)
end

function ItemShop.OnClose()
	visible = false
	hoverId = nil
	local connection = animation
	if connection then
		connection:Disconnect()
		animation = nil
	end
end

-- Vrai si la boutique est ouverte
function ItemShop.IsOpen(): boolean
	return visible
end

return ItemShop
