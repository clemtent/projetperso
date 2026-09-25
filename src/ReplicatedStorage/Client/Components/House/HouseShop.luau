--[[
	HouseShop (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseShop

	Tiroir "🛍️ Boutique" de la maison (glisse depuis la droite de la pièce) :
	  - onglets : 🛋️ Objets / 🎨 Murs / 🟫 Sols / 🏡 Maisons ;
	  - Objets : pastilles de catégories (Config.House.Categories) + grille
	    de cartes (emoji sur vignette pastel, nom, ❤️ confort, exemplaires
	    possédés, pastille "✨ Nouveau" si abordable, prix du prochain
	    exemplaire via Formulas.GetHouseItemPrice, "MAX" si MaxOwned) ;
	  - Murs / Sols : aperçus EN DIRECT des motifs (HousePatterns) ; survol
	    (ou toucher l'aperçu) = essayer sur la pièce ; acheter / appliquer ;
	  - Maisons : les tailles (largeur, nombre d'objets) : acheter / emménager.
	Achats : Net.Function("House"):InvokeServer(action, id) protégé (pcall),
	avec sons, confettis et bandeaux. Les cartes sont construites au premier
	affichage (par petits paquets pour ne pas figer l'écran).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local Effects = require(Client.Effects)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Locale = require(ReplicatedStorage.Shared.Locale)
local HouseCommon = require(script.Parent.HouseCommon)
local NeedDopamine = require(script.Parent.Parent.NeedDopamine)
local HouseArt = require(script.Parent.HouseArt)
local HousePatterns = require(script.Parent.HousePatterns)

type Item = HouseCommon.Item
type Style = HouseCommon.Style
type SizeDef = HouseCommon.SizeDef
type HouseData = HouseCommon.HouseData

local HouseShop = {}

local C = HouseCommon.Colors
local WHITE = Color3.new(1, 1, 1)
local BUY_COLOR = Theme.Colors.Green
local CARD_HEIGHT = 178
local STYLE_CARD_HEIGHT = 158
local SIZE_ROW_HEIGHT = 86

export type Handlers = {
	Notify: (text: string, color: Color3?, title: string?) -> (),
	OnItemBought: (itemId: string) -> (),
	OnPlaceRequest: (itemId: string) -> (),
	OnPreview: (kind: string, id: string?) -> (),
	OnHouseChanged: () -> (),
	BeforeHouseChange: () -> (),
	GetAvailable: (itemId: string) -> number,
}

export type Shop = {
	Frame: Frame,
	Open: (section: string?) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	Refresh: () -> (),
	SetWidth: (width: number) -> (),
}

type ItemCard = {
	Item: Item,
	Cell: Frame,
	Card: Frame,
	Button: TextButton,
	Owned: Frame,
	New: Frame,
	Stroke: UIStroke,
	Rank: number,
	Tile: GuiObject,
	Emoji: TextLabel,
	Painted: boolean,
}

type StyleCard = {
	Kind: string,
	Style: Style,
	Card: Frame,
	Button: TextButton,
	Stroke: UIStroke,
	Check: Frame,
}

type SizeRow = {
	Size: SizeDef,
	Row: Frame,
	Button: TextButton,
	Stroke: UIStroke,
	Status: TextLabel,
}

-- Petite étiquette arrondie dans une carte
local function tag(parent: Instance, text: string, color: Color3, textColor: Color3, props: { [string]: any }): Frame
	local chip = UIUtil.Chip({
		Name = props.Name or "Tag",
		Text = text,
		Color = color,
		TextColor3 = textColor,
		Height = props.Height or 20,
		TextSize = props.TextSize or 12,
		ZIndex = props.ZIndex or 6,
		Parent = parent,
	})
	chip.AnchorPoint = props.AnchorPoint or Vector2.zero
	chip.Position = props.Position or UDim2.new()
	return chip
end

local function setChipText(chip: Frame, text: string)
	local label = chip:FindFirstChild("Label") :: TextLabel?
	if label and label.Text ~= text then
		label.Text = text
	end
end

-- Bouton d'achat / d'action d'une carte
local function actionButton(parent: Instance, props: { [string]: any }): TextButton
	local button = UIUtil.NeonButton({
		Name = props.Name or "Action",
		Text = "",
		Size = props.Size,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Color = BUY_COLOR,
		CornerRadius = props.CornerRadius or 14,
		MaxTextSize = props.MaxTextSize or 15,
		ZIndex = props.ZIndex or 6,
		Parent = parent,
	})
	return button
end

-- Change l'aspect d'un bouton d'action
local function paintButton(button: TextButton, text: string, color: Color3, enabled: boolean, textColor: Color3?)
	if button.Text ~= text then
		button.Text = text
	end
	button:SetAttribute("BaseColor", color)
	UIUtil.SetButtonEnabled(button, enabled)
	button.TextColor3 = textColor or Theme.ContrastText(color)
end

function HouseShop.new(parent: Frame, handlers: Handlers): Shop
	local shop: Shop
	local isOpen = false
	local section = "Items"
	local category = "All"
	local busy = false
	local built: { [string]: boolean } = {}
	local itemCards: { ItemCard } = {}
	local styleCards: { StyleCard } = {}
	local sizeRows: { SizeRow } = {}
	local stickyPreview: { Kind: string, Id: string }? = nil
	local hoverPreview: { Kind: string, Id: string }? = nil
	local width = 380
	local openToken = 0
	local refresh: () -> ()

	----------------------------------------------------------------------
	-- Cadre du tiroir
	----------------------------------------------------------------------

	local drawer = UIUtil.Create("Frame", {
		Name = "ShopDrawer",
		Size = UDim2.new(0, width, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, width + 40, 0, 0),
		BackgroundColor3 = WHITE,
		Active = true,
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	UIUtil.Corner(drawer, 20)
	UIUtil.Stroke(drawer, C.Pink, 2, 0.25)
	UIUtil.Shadow(drawer, 6, 0.8, 4)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		Parent = drawer,
	})

	-- En-tête : titre, porte-monnaie, ✕
	UIUtil.Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -150, 0, 30),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = Locale.T("🛍️ House shop"),
		TextColor3 = C.Ink,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 31,
		Parent = drawer,
	})
	local wallet = UIUtil.Chip({
		Name = "Wallet",
		Text = "💧 0",
		Color = C.MintSoft,
		TextColor3 = C.Ink,
		Height = 28,
		TextSize = 15,
		ZIndex = 31,
		Parent = drawer,
	})
	wallet.AnchorPoint = Vector2.new(1, 0)
	wallet.Position = UDim2.new(1, -44, 0, 1)
	local closeButton = UIUtil.BasicButton({
		Name = "Close",
		Text = "✕",
		Font = Theme.Fonts.Title,
		TextSize = 17,
		Size = UDim2.fromOffset(34, 34),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		CornerRadius = 17,
		ZIndex = 31,
		Parent = drawer,
	})

	local tabs = UIUtil.Tabs({
		Name = "Sections",
		Parent = drawer,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 36),
		Color = C.PinkDeep,
		TextSize = 14,
		ZIndex = 31,
		Tabs = {
			{ Id = "Items", Text = Locale.T("🛋️ Items") },
			{ Id = "Wallpapers", Text = Locale.T("🎨 Walls") },
			{ Id = "Floors", Text = Locale.T("🟫 Floors") },
			{ Id = "Sizes", Text = Locale.T("🏡 Houses") },
		},
		Selected = "Items",
		OnSelect = function(id: string)
			shop.Open(id)
		end,
	})

	local body = UIUtil.Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -84),
		Position = UDim2.fromOffset(0, 84),
		BackgroundTransparency = 1,
		ZIndex = 31,
		Parent = drawer,
	})

	local function scroller(name: string, top: number): ScrollingFrame
		local list = UIUtil.Create("ScrollingFrame", {
			Name = name,
			Size = UDim2.new(1, 6, 1, -top),
			Position = UDim2.fromOffset(0, top),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = C.Pink,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
			ZIndex = 32,
			Parent = body,
		})
		-- (3 px à gauche / en haut : contour épais de la carte choisie jamais coupé)
		UIUtil.Create("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 3),
			PaddingRight = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 12),
			Parent = list,
		})
		return list
	end

	-- Section Objets : pastilles de catégories + grille
	local categoryRow = UIUtil.Create("ScrollingFrame", {
		Name = "Categories",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 0,
		ZIndex = 32,
		Parent = body,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = categoryRow,
	})
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 40),
		Parent = categoryRow,
	})
	-- La rangée défile : fondu blanc + flèche "›" à droite, pour qu'une
	-- pastille coupée au bord se lise comme "il y en a d'autres" (la flèche
	-- fait défiler ; elle disparaît au bout de la rangée)
	local moreHint = UIUtil.Create("Frame", {
		Name = "MoreCategories",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(56, 38),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 34,
		Parent = body,
	})
	UIUtil.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = moreHint,
	})
	local moreButton = UIUtil.PillButton({
		Name = "More",
		Text = "›",
		Color = C.Pink,
		TextColor3 = WHITE,
		Height = 28,
		TextSize = 20,
		Round = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -3, 0.5, 0),
		ZIndex = 35,
		Parent = moreHint,
	})
	local function refreshMoreHint()
		local window = categoryRow.AbsoluteWindowSize.X
		local canvas = categoryRow.AbsoluteCanvasSize.X
		moreHint.Visible = categoryRow.Visible and canvas > window + categoryRow.CanvasPosition.X + 4
	end
	moreButton.Activated:Connect(function()
		local maxX = math.max(0, categoryRow.AbsoluteCanvasSize.X - categoryRow.AbsoluteWindowSize.X)
		local target = math.min(maxX, categoryRow.CanvasPosition.X + 140)
		UIUtil.Tween(categoryRow, 0.25, { CanvasPosition = Vector2.new(target, 0) })
	end)
	categoryRow:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshMoreHint)
	categoryRow:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(refreshMoreHint)
	categoryRow:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refreshMoreHint)
	categoryRow:GetPropertyChangedSignal("Visible"):Connect(refreshMoreHint)
	local itemsList = scroller("ItemsList", 44)
	local itemsGrid = UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(8, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = itemsList,
	})
	local wallpapersList = scroller("WallpapersList", 0)
	local wallpapersGrid = UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, STYLE_CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(8, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wallpapersList,
	})
	local floorsList = scroller("FloorsList", 0)
	local floorsGrid = UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, STYLE_CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(8, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = floorsList,
	})
	local sizesList = scroller("SizesList", 0)
	UIUtil.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = sizesList,
	})

	-- Nombre de colonnes selon la largeur du tiroir
	local function relayoutGrids()
		local designWidth = width - 40 -- marges du tiroir et de la liste
		local columns = math.clamp(math.floor(designWidth / 118), 2, 5)
		local styleColumns = math.clamp(math.floor(designWidth / 150), 2, 4)
		itemsGrid.CellSize = UDim2.new(1 / columns, -8, 0, CARD_HEIGHT)
		wallpapersGrid.CellSize = UDim2.new(1 / styleColumns, -8, 0, STYLE_CARD_HEIGHT)
		floorsGrid.CellSize = UDim2.new(1 / styleColumns, -8, 0, STYLE_CARD_HEIGHT)
	end

	----------------------------------------------------------------------
	-- Aperçus en direct sur la pièce
	----------------------------------------------------------------------

	local function applyPreview()
		local current = hoverPreview or stickyPreview
		handlers.OnPreview("Wallpaper", current and current.Kind == "Wallpaper" and current.Id or nil)
		handlers.OnPreview("Floor", current and current.Kind == "Floor" and current.Id or nil)
	end

	local function endPreviews()
		hoverPreview = nil
		stickyPreview = nil
		applyPreview()
	end

	----------------------------------------------------------------------
	-- Achats
	----------------------------------------------------------------------

	local function celebrate(guiObject: GuiObject, big: boolean)
		SoundManager.Play("Buy", big and 1 or 1.15)
		Effects.Confetti(big and 70 or 36)
		local layer = Effects.GetLayer()
		if layer and guiObject.Parent then
			local center = Interface.GetCanvasCenter(guiObject)
			Effects.Burst(layer, UDim2.fromOffset(center.X, center.Y), C.Pink, 12)
		end
	end

	-- Appelle le serveur ; (succès) + bandeau et son d'erreur si refus
	local function request(action: string, id: string, button: GuiObject): (boolean, string?)
		if busy then
			return false, nil
		end
		busy = true
		local ok, message = HouseCommon.Invoke(action, id)
		busy = false
		if not ok then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(button)
			handlers.Notify(message or Locale.T("Not possible right now."), Theme.Colors.Red)
		end
		return ok, message
	end

	local function buyItem(card: ItemCard)
		local item = card.Item
		local house = HouseCommon.GetHouse(ClientState.Data)
		local owned = HouseCommon.Owned(house, item.Id)
		if HouseCommon.IsMaxed(item, owned) then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(card.Button)
			handlers.Notify(Locale.T("You already have the maximum of %s", item.Icon .. " " .. HouseCommon.Name(item)), Theme.Colors.Orange)
			return
		end
		local price = HouseCommon.Price(item, owned)
		if HouseCommon.Dopamine() < price then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(card.Button)
			local missing = price - HouseCommon.Dopamine()
			NeedDopamine.Offer(missing, function()
				handlers.Notify(Locale.T("You need %s more Dopamine", NumberFormatter.Format(missing)), Theme.Colors.Red)
			end)
			return
		end
		task.spawn(function()
			local ok, message = request("buyItem", item.Id, card.Button)
			if ok then
				celebrate(card.Card, false)
				handlers.Notify(message or Locale.T("%s is yours!", item.Icon .. " " .. HouseCommon.Name(item)), Theme.Colors.Green, Locale.T("🏠 New item"))
				UIUtil.Pop(card.Card, 1.08, 0.35)
				handlers.OnItemBought(item.Id)
			end
		end)
	end

	local function styleAction(card: StyleCard)
		local house = HouseCommon.GetHouse(ClientState.Data)
		local owned = card.Kind == "Wallpaper" and house.OwnedWallpapers or house.OwnedFloors
		local equipped = card.Kind == "Wallpaper" and house.Wallpaper or house.Floor
		local id = card.Style.Id
		if equipped == id then
			UIUtil.Pop(card.Card, 1.05, 0.3)
			return
		end
		local isOwned = owned[id] == true or card.Style.Cost <= 0
		if not isOwned and HouseCommon.Dopamine() < card.Style.Cost then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(card.Button)
			local missing = card.Style.Cost - HouseCommon.Dopamine()
			NeedDopamine.Offer(missing, function()
				handlers.Notify(Locale.T("You need %s more Dopamine", NumberFormatter.Format(missing)), Theme.Colors.Red)
			end)
			return
		end
		local action = (isOwned and "set" or "buy") .. card.Kind
		task.spawn(function()
			local ok, message = request(action, id, card.Button)
			if ok then
				stickyPreview = nil
				hoverPreview = nil
				applyPreview()
				if isOwned then
					SoundManager.Play("Open", 1.2)
					UIUtil.Pop(card.Card, 1.06, 0.3)
				else
					celebrate(card.Card, false)
					handlers.Notify(message or Locale.T("Applied!"), Theme.Colors.Green)
				end
			end
		end)
	end

	local function sizeAction(row: SizeRow)
		local house = HouseCommon.GetHouse(ClientState.Data)
		local size = row.Size
		if house.Size == size.Id then
			UIUtil.Pop(row.Row, 1.04, 0.3)
			return
		end
		local isOwned = house.OwnedSizes[size.Id] == true or size.Cost <= 0
		if not isOwned and HouseCommon.Dopamine() < size.Cost then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(row.Button)
			local missing = size.Cost - HouseCommon.Dopamine()
			NeedDopamine.Offer(missing, function()
				handlers.Notify(Locale.T("You need %s more Dopamine", NumberFormatter.Format(missing)), Theme.Colors.Red)
			end)
			return
		end
		-- Disposition en attente envoyée AVANT le déménagement (le serveur
		-- recale ensuite les objets pour la nouvelle largeur)
		handlers.BeforeHouseChange()
		task.spawn(function()
			local ok, message = request(isOwned and "setSize" or "buySize", size.Id, row.Button)
			if ok then
				if isOwned then
					SoundManager.Play("Open", 1)
				else
					celebrate(row.Row, true)
				end
				handlers.Notify(message or Locale.T("Welcome home!"), Theme.Colors.Green, if isOwned then nil else Locale.T("🏡 New house!"))
				handlers.OnHouseChanged()
			end
		end)
	end

	----------------------------------------------------------------------
	-- Cartes
	----------------------------------------------------------------------

	local function makeCard(parentList: Instance, name: string, order: number): (Frame, Frame, UIStroke)
		local cell = UIUtil.Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			ZIndex = 33,
			Parent = parentList,
		})
		local card = UIUtil.Create("Frame", {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			ZIndex = 34,
			Parent = cell,
		})
		UIUtil.Corner(card, 16)
		local stroke = UIUtil.Stroke(card, C.PinkSoft:Lerp(C.Pink, 0.3), 1.5, 0)
		pcall(UIUtil.Shadow, card, 3, 0.86, 2)
		card.MouseEnter:Connect(function()
			UIUtil.Tween(card, 0.12, { Position = UDim2.fromOffset(0, -3) })
		end)
		card.MouseLeave:Connect(function()
			UIUtil.Tween(card, 0.12, { Position = UDim2.fromOffset(0, 0) })
		end)
		return cell, card, stroke
	end

	local function buildItemCard(item: Item, rank: number)
		local cell, card, stroke = makeCard(itemsList, item.Id, rank)
		local tile = UIUtil.Create("TextButton", {
			Name = "Tile",
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, 80),
			BackgroundColor3 = HouseCommon.CategoryTint(item.Category),
			AutoButtonColor = false,
			Text = "",
			ZIndex = 35,
			Parent = card,
		})
		UIUtil.Corner(tile, 12)
		UIUtil.Gradient(tile, ColorSequence.new(WHITE, Color3.fromRGB(232, 232, 232)), 90)
		-- Petits points décoratifs sur la vignette
		for index = 1, 3 do
			local dot = UIUtil.Create("Frame", {
				Size = UDim2.fromOffset(6, 6),
				Position = UDim2.new(index / 4, 0, index % 2 == 0 and 0.18 or 0.8, 0),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.35,
				ZIndex = 36,
				Parent = tile,
			})
			UIUtil.Corner(dot, UDim.new(1, 0))
		end
		-- Emoji en attendant le dessin (peint petit à petit, voir paintArt)
		local emoji = UIUtil.Create("TextLabel", {
			Name = "Emoji",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.54),
			Size = UDim2.fromOffset(60, 56),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = item.Icon,
			TextSize = 46,
			ZIndex = 37,
			Parent = tile,
		})
		tag(tile, item.Placement == "Wall" and Locale.T("Wall") or Locale.T("Floor"), WHITE, C.Ink, {
			Name = "Placement",
			Position = UDim2.fromOffset(4, 4),
			Height = 18,
			TextSize = 11,
			ZIndex = 38,
		})
		local ownedTag = tag(tile, "x0", C.Lilac, WHITE, {
			Name = "Owned",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Height = 18,
			TextSize = 11,
			ZIndex = 38,
		})
		local newTag = tag(tile, Locale.T("✨ New"), C.Butter, C.Ink, {
			Name = "New",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -4),
			Height = 18,
			TextSize = 11,
			ZIndex = 38,
		})
		UIUtil.Create("TextLabel", {
			Name = "Name",
			Position = UDim2.fromOffset(8, 90),
			Size = UDim2.new(1, -16, 0, 18),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = HouseCommon.Name(item),
			TextColor3 = Theme.Colors.Text,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 35,
			Parent = card,
		})
		UIUtil.Create("TextLabel", {
			Name = "Comfort",
			Position = UDim2.fromOffset(8, 108),
			Size = UDim2.new(1, -16, 0, 16),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = Locale.T("❤️ +%d comfort", item.Comfort),
			TextColor3 = C.PinkDeep,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 35,
			Parent = card,
		})
		local button = actionButton(card, {
			Size = UDim2.new(1, -12, 0, 34),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 6, 1, -8),
			ZIndex = 35,
		})
		local entry: ItemCard = {
			Item = item,
			Cell = cell,
			Card = card,
			Button = button,
			Owned = ownedTag,
			New = newTag,
			Stroke = stroke,
			Rank = rank,
			Tile = tile,
			Emoji = emoji,
			Painted = false,
		}
		table.insert(itemCards, entry)
		button.Activated:Connect(function()
			buyItem(entry)
		end)
		-- Toucher la vignette d'un objet possédé mais rangé : on le pose
		tile.Activated:Connect(function()
			if handlers.GetAvailable(item.Id) > 0 then
				handlers.OnPlaceRequest(item.Id)
			else
				UIUtil.Pop(tile, 1.08, 0.3)
				SoundManager.Play("Pop", 1.2)
			end
		end)
	end

	local function buildStyleCard(kind: string, style: Style, listFrame: Instance)
		local _, card, stroke = makeCard(listFrame, style.Id, style.Order or 0)
		local preview = UIUtil.Create("TextButton", {
			Name = "Preview",
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, 78),
			BackgroundColor3 = style.A,
			AutoButtonColor = false,
			ClipsDescendants = true,
			Text = "",
			ZIndex = 35,
		})
		preview:SetAttribute("DarkSkinIgnore", true)
		UIUtil.Corner(preview, 12)
		preview.Parent = card
		-- Motif en miniature (dessiné plus large que la carte : le surplus est coupé).
		-- CanvasGroup arrondi : ClipsDescendants seul découpe en rectangle et le
		-- motif dépassait des coins arrondis de l'aperçu
		local canvas = UIUtil.Create("CanvasGroup", {
			Name = "Canvas",
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			ZIndex = 36,
			Parent = preview,
		})
		UIUtil.Corner(canvas, 12)
		-- Dessin à l'échelle de la pièce, réduit de moitié (mêmes proportions, peu de Frames)
		local art = UIUtil.Create("Frame", {
			Name = "Art",
			Size = UDim2.fromOffset(420, 160),
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 36,
			Parent = canvas,
		})
		UIUtil.Create("UIScale", { Scale = 0.5, Parent = art })
		if kind == "Wallpaper" then
			HousePatterns.BuildWall(art, 420, 160, style, 1)
		else
			HousePatterns.BuildFloor(art, 420, 160, style, 1)
		end
		local check = UIUtil.Create("Frame", {
			Name = "Check",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = Theme.Colors.Green,
			Visible = false,
			ZIndex = 40,
			Parent = card,
		})
		UIUtil.Corner(check, UDim.new(1, 0))
		UIUtil.Stroke(check, WHITE, 2)
		UIUtil.Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = "✓",
			TextColor3 = WHITE,
			TextSize = 15,
			ZIndex = 41,
			Parent = check,
		})
		UIUtil.Create("TextLabel", {
			Name = "Name",
			Position = UDim2.fromOffset(8, 88),
			Size = UDim2.new(1, -16, 0, 18),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = (style.Icon and (style.Icon .. " ") or "") .. HouseCommon.Name(style),
			TextColor3 = Theme.Colors.Text,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 35,
			Parent = card,
		})
		local button = actionButton(card, {
			Size = UDim2.new(1, -12, 0, 32),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 6, 1, -8),
			ZIndex = 35,
		})
		local entry: StyleCard = { Kind = kind, Style = style, Card = card, Button = button, Stroke = stroke, Check = check }
		table.insert(styleCards, entry)
		button.Activated:Connect(function()
			styleAction(entry)
		end)
		-- Essayer : survol (PC) ou toucher l'aperçu (mobile : reste affiché)
		preview.MouseEnter:Connect(function()
			if Interface.IsTouch() then
				return
			end
			hoverPreview = { Kind = kind, Id = style.Id }
			applyPreview()
		end)
		preview.MouseLeave:Connect(function()
			local hover = hoverPreview
			if hover and hover.Id == style.Id then
				hoverPreview = nil
				applyPreview()
			end
		end)
		preview.Activated:Connect(function()
			local sticky = stickyPreview
			if sticky and sticky.Id == style.Id and sticky.Kind == kind then
				stickyPreview = nil
			else
				stickyPreview = { Kind = kind, Id = style.Id }
			end
			SoundManager.Play("Pop", 1.15)
			UIUtil.Pop(card, 1.05, 0.25)
			applyPreview()
		end)
	end

	local function buildSizeRow(size: SizeDef)
		local row = UIUtil.Create("Frame", {
			Name = size.Id,
			Size = UDim2.new(1, 0, 0, SIZE_ROW_HEIGHT),
			BackgroundColor3 = WHITE,
			LayoutOrder = size.Order or 0,
			ZIndex = 34,
			Parent = sizesList,
		})
		UIUtil.Corner(row, 16)
		local stroke = UIUtil.Stroke(row, C.PinkSoft:Lerp(C.Pink, 0.3), 1.5, 0)
		local icon = UIUtil.Create("Frame", {
			Name = "Icon",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(SIZE_ROW_HEIGHT - 16, SIZE_ROW_HEIGHT - 16),
			BackgroundColor3 = C.PinkSoft,
			ZIndex = 35,
			Parent = row,
		})
		UIUtil.Corner(icon, 14)
		UIUtil.Gradient(icon, ColorSequence.new(WHITE, Color3.fromRGB(230, 230, 230)), 90)
		UIUtil.Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = size.Icon,
			TextSize = 40,
			ZIndex = 36,
			Parent = icon,
		})
		local textLeft = SIZE_ROW_HEIGHT + 2
		UIUtil.Create("TextLabel", {
			Name = "Name",
			Position = UDim2.fromOffset(textLeft, 10),
			Size = UDim2.new(1, -(textLeft + 8), 0, 20),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = HouseCommon.Name(size),
			TextColor3 = Theme.Colors.Text,
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 35,
			Parent = row,
		})
		UIUtil.Create("TextLabel", {
			Name = "Info",
			Position = UDim2.fromOffset(textLeft, 30),
			Size = UDim2.new(1, -(textLeft + 8), 0, 16),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = Locale.T("↔ x%s wide  •  up to %d items", tostring(size.Width), size.MaxItems),
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 35,
			Parent = row,
		})
		local status = UIUtil.Create("TextLabel", {
			Name = "Status",
			Position = UDim2.fromOffset(textLeft, 54),
			Size = UDim2.new(1, -(textLeft + 132), 0, 22),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = "",
			TextColor3 = C.PinkDeep,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 35,
			Parent = row,
		})
		local button = actionButton(row, {
			Size = UDim2.fromOffset(120, 32),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8, 1, -8),
			ZIndex = 35,
		})
		local entry: SizeRow = { Size = size, Row = row, Button = button, Stroke = stroke, Status = status }
		table.insert(sizeRows, entry)
		button.Activated:Connect(function()
			sizeAction(entry)
		end)
	end

	-- Pastilles de catégories
	local categoryButtons: { [string]: TextButton } = {}
	local function paintCategories()
		for id, button in pairs(categoryButtons) do
			local selected = id == category
			button:SetAttribute("BaseColor", selected and C.PinkDeep or WHITE)
			button.BackgroundColor3 = selected and C.PinkDeep or WHITE
			button.TextColor3 = selected and WHITE or C.Ink
		end
	end
	-- Dessins des vignettes : peints à la demande (cartes visibles), quelques-uns
	-- par image pour ne pas figer l'écran à l'ouverture de la boutique
	local paintQueue: { ItemCard } = {}
	local painting = false
	local function paintArt(card: ItemCard)
		if card.Painted then
			return
		end
		card.Painted = true
		if HouseArt.Has(card.Item.Id) then
			HouseArt.Thumbnail(card.Tile, card.Item, 78, 37)
			card.Emoji.Visible = false
		end
	end
	local function queueArt(card: ItemCard)
		if card.Painted then
			return
		end
		table.insert(paintQueue, card)
		if painting then
			return
		end
		painting = true
		task.spawn(function()
			while #paintQueue > 0 do
				for _ = 1, 6 do
					local next = table.remove(paintQueue, 1)
					if not next then
						break
					end
					if next.Cell.Visible then
						paintArt(next)
					end
				end
				task.wait()
			end
			painting = false
		end)
	end

	local function applyFilter()
		table.clear(paintQueue)
		for _, card in ipairs(itemCards) do
			local visible = category == "All" or card.Item.Category == category
			card.Cell.Visible = visible
		end
		-- Dans l'ordre d'affichage (les premières cartes d'abord)
		local ordered = {}
		for _, card in ipairs(itemCards) do
			if card.Cell.Visible and not card.Painted then
				table.insert(ordered, card)
			end
		end
		table.sort(ordered, function(a, b)
			return a.Cell.LayoutOrder < b.Cell.LayoutOrder
		end)
		for _, card in ipairs(ordered) do
			queueArt(card)
		end
		itemsList.CanvasPosition = Vector2.zero
	end
	local function categoryPill(id: string, text: string, order: number)
		local height = Interface.IsTouch() and 34 or 30
		local button = UIUtil.PillButton({
			Name = id,
			Text = text,
			Color = WHITE,
			TextColor3 = C.Ink,
			Height = height,
			TextSize = 13,
			LayoutOrder = order,
			ZIndex = 33,
			StrokeColor = C.Pink,
			Parent = categoryRow,
		})
		categoryButtons[id] = button
		button.Activated:Connect(function()
			if category == id then
				return
			end
			category = id
			SoundManager.Play("Click", 1.1)
			paintCategories()
			applyFilter()
			refresh()
		end)
	end
	categoryPill("All", Locale.T("✨ All"), 0)
	for index, entry in ipairs(HouseCommon.Config.Categories) do
		categoryPill(entry.Id, entry.Icon .. " " .. HouseCommon.Name(entry), index)
	end
	paintCategories()
	task.defer(refreshMoreHint)

	-- Construction paresseuse d'une section (par paquets)
	local function buildSection(name: string)
		if built[name] then
			return
		end
		built[name] = true
		if name == "Items" then
			local items = table.clone(HouseCommon.Config.Items)
			table.sort(items, function(a, b)
				if a.Cost ~= b.Cost then
					return a.Cost < b.Cost
				end
				return (a.Order or 0) < (b.Order or 0)
			end)
			task.spawn(function()
				for rank, item in ipairs(items) do
					buildItemCard(item, rank)
					if rank % 24 == 0 then
						applyFilter()
						refresh()
						task.wait()
					end
				end
				applyFilter()
				refresh()
			end)
		elseif name == "Wallpapers" then
			for _, style in ipairs(HouseCommon.Config.Wallpapers) do
				buildStyleCard("Wallpaper", style, wallpapersList)
			end
		elseif name == "Floors" then
			for _, style in ipairs(HouseCommon.Config.Floors) do
				buildStyleCard("Floor", style, floorsList)
			end
		elseif name == "Sizes" then
			for _, size in ipairs(HouseCommon.Config.Sizes) do
				buildSizeRow(size)
			end
		end
	end

	----------------------------------------------------------------------
	-- Mise à jour des cartes
	----------------------------------------------------------------------

	refresh = function()
		local data = ClientState.Data
		local house = HouseCommon.GetHouse(data)
		local dopamine = HouseCommon.Dopamine()
		setChipText(wallet, "💧 " .. NumberFormatter.Format(dopamine))
		if not isOpen then
			return
		end

		if section == "Items" then
			for _, card in ipairs(itemCards) do
				if card.Cell.Visible then
					local item = card.Item
					local owned = HouseCommon.Owned(house, item.Id)
					local maxed = HouseCommon.IsMaxed(item, owned)
					local price = HouseCommon.Price(item, owned)
					local affordable = dopamine >= price
					card.Owned.Visible = owned > 0
					if owned > 0 then
						local free = handlers.GetAvailable(item.Id)
						setChipText(card.Owned, free > 0 and string.format("x%d • 📦%d", owned, free) or ("x" .. owned))
					end
					card.New.Visible = owned == 0 and affordable
					if maxed then
						paintButton(card.Button, Locale.T("MAX ✓"), Theme.Colors.ButtonBottom, true, Theme.Colors.Text)
					else
						paintButton(card.Button, "💧 " .. NumberFormatter.Format(price), BUY_COLOR, affordable, Theme.Colors.TextDark)
					end
					card.Stroke.Color = (owned == 0 and affordable) and C.Butter:Lerp(C.PinkDeep, 0.2) or C.PinkSoft:Lerp(C.Pink, 0.3)
					card.Stroke.Thickness = (owned == 0 and affordable) and 2.5 or 1.5
				end
			end
		elseif section == "Wallpapers" or section == "Floors" then
			for _, card in ipairs(styleCards) do
				local isWallpaper = card.Kind == "Wallpaper"
				if (section == "Wallpapers") == isWallpaper then
					local owned = isWallpaper and house.OwnedWallpapers or house.OwnedFloors
					local equipped = (isWallpaper and house.Wallpaper or house.Floor) == card.Style.Id
					local isOwned = owned[card.Style.Id] == true or card.Style.Cost <= 0
					card.Check.Visible = equipped
					if equipped then
						paintButton(card.Button, Locale.T("✔ Applied"), Theme.Colors.ButtonBottom, true, Theme.Colors.Text)
						card.Stroke.Color = Theme.Colors.Green
						card.Stroke.Thickness = 3
					elseif isOwned then
						paintButton(card.Button, Locale.T("Apply"), Theme.Colors.Blue, true, WHITE)
						card.Stroke.Color = C.PinkSoft:Lerp(C.Pink, 0.3)
						card.Stroke.Thickness = 1.5
					else
						local affordable = dopamine >= card.Style.Cost
						paintButton(card.Button, "💧 " .. NumberFormatter.Format(card.Style.Cost), BUY_COLOR, affordable, Theme.Colors.TextDark)
						card.Stroke.Color = C.PinkSoft:Lerp(C.Pink, 0.3)
						card.Stroke.Thickness = 1.5
					end
				end
			end
		elseif section == "Sizes" then
			for _, row in ipairs(sizeRows) do
				local size = row.Size
				local current = house.Size == size.Id
				local isOwned = house.OwnedSizes[size.Id] == true or size.Cost <= 0
				if current then
					paintButton(row.Button, Locale.T("✔ Home"), Theme.Colors.ButtonBottom, true, Theme.Colors.Text)
					row.Status.Text = Locale.T("🏠 You live here")
					row.Stroke.Color = Theme.Colors.Green
					row.Stroke.Thickness = 3
				elseif isOwned then
					paintButton(row.Button, Locale.T("Move in"), Theme.Colors.Blue, true, WHITE)
					row.Status.Text = Locale.T("✔ Owned")
					row.Stroke.Color = C.PinkSoft:Lerp(C.Pink, 0.3)
					row.Stroke.Thickness = 1.5
				else
					local affordable = dopamine >= size.Cost
					paintButton(row.Button, "💧 " .. NumberFormatter.Format(size.Cost), BUY_COLOR, affordable, Theme.Colors.TextDark)
					row.Status.Text = affordable and Locale.T("You can afford it!") or Locale.T("Not enough Dopamine yet")
					row.Stroke.Color = C.PinkSoft:Lerp(C.Pink, 0.3)
					row.Stroke.Thickness = 1.5
				end
			end
		end
	end

	----------------------------------------------------------------------
	-- Ouverture / fermeture
	----------------------------------------------------------------------

	local sections: { [string]: GuiObject } = {
		Items = itemsList,
		Wallpapers = wallpapersList,
		Floors = floorsList,
		Sizes = sizesList,
	}

	local function showSection(name: string)
		section = name
		for id, frame in pairs(sections) do
			frame.Visible = id == name
		end
		categoryRow.Visible = name == "Items"
		tabs.Select(name, true)
		-- Changer d'onglet arrête l'essai en cours
		if stickyPreview or hoverPreview then
			endPreviews()
		end
		buildSection(name)
		relayoutGrids()
		refresh()
	end

	closeButton.Activated:Connect(function()
		shop.Close()
	end)

	shop = {
		Frame = drawer,
		Open = function(newSection: string?)
			local target = newSection or section
			if not isOpen then
				isOpen = true
				openToken += 1
				drawer.Visible = true
				drawer.Position = UDim2.new(1, width + 40, 0, 0)
				UIUtil.Tween(drawer, 0.32, { Position = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quint)
				SoundManager.Play("Open", 1.15)
			end
			showSection(target)
		end,
		Close = function()
			if not isOpen then
				return
			end
			isOpen = false
			openToken += 1
			local token = openToken
			endPreviews()
			UIUtil.Tween(drawer, 0.22, { Position = UDim2.new(1, width + 40, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.23, function()
				if token == openToken then
					drawer.Visible = false
				end
			end)
		end,
		IsOpen = function(): boolean
			return isOpen
		end,
		Refresh = function()
			refresh()
		end,
		SetWidth = function(newWidth: number)
			width = newWidth
			drawer.Size = UDim2.new(0, newWidth, 1, 0)
			if not isOpen then
				drawer.Position = UDim2.new(1, newWidth + 40, 0, 0)
			end
			relayoutGrids()
		end,
	}
	return shop
end

return HouseShop
