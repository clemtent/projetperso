--[[
	HouseShop (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseShop

	Tiroir "🛍️ Boutique" de la maison (glisse depuis la droite) :
	  - onglets : 🛋️ Objets / 🎨 Murs / 🟫 Sols / 🚪 Pièces / 🏡 Maisons ;
	    l'onglet choisi s'élargit (icône + nom), les autres gardent leur
	    icône : les 5 onglets tiennent même sur téléphone ;
	  - Objets : pastilles de catégories (+ "préférés" de la pièce ouverte)
	    et grille de cartes (dessin sur vignette pastel, nom, ❤️ confort,
	    exemplaires possédés, "✨ Nouveau" si abordable, prix du prochain
	    exemplaire, "MAX" si MaxOwned) ; badge ✨ sur les objets préférés de
	    la pièce ouverte (bonus d'harmonie) ;
	  - Murs / Sols : PAR PIÈCE. Bandeau en haut : la pièce modifiée (la
	    pièce ouverte) ou, depuis la vue de la maison, un choix de pièce ;
	    ✓ = posé dans CETTE pièce ; survol (ou toucher l'aperçu) = essayer ;
	  - Pièces : les 12 types de pièce (aperçu murs / sol, objets préférés,
	    prix de la prochaine pièce, compteur x/y) : "buyRoom" { Type } ;
	    maison pleine -> l'onglet Maisons ;
	  - Maisons : chaque bâtiment avec sa silhouette dessinée (grille des
	    pièces, pièces du joueur dans la maison actuelle), étages x pièces,
	    objets max par pièce, prix / possédé / habité.
	Achats : HouseCommon.Invoke (pcall), sons, confettis et bandeaux ;
	message du serveur affiché en cas de refus. Les cartes sont construites
	au premier affichage d'un onglet, les dessins peints par petits paquets.
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
type Room = HouseCommon.Room
type RoomTypeDef = HouseCommon.RoomTypeDef

local HouseShop = {}

local C = HouseCommon.Colors
local WHITE = Color3.new(1, 1, 1)
local BUY_COLOR = Theme.Colors.Green
local SOFT_STROKE = C.PinkSoft:Lerp(C.Pink, 0.3)
local CARD_HEIGHT = 178
local STYLE_CARD_HEIGHT = 158
local ROOM_CARD_HEIGHT = 128
local SIZE_ROW_HEIGHT = 132
local FAV_TILE = 32 -- vignette d'un objet / d'une catégorie préférée (carte de pièce)
local FAV_GAP = 4
local MAX_FAVS = 10
local TAB_ICON_WIDTH = 44 -- onglet non choisi (icône seule) : cible tactile
local LIST_INSET = 31 -- largeur du tiroir - largeur utile d'une liste (marges)

export type Handlers = {
	Notify: (text: string, color: Color3?, title: string?) -> (),
	OnItemBought: (itemId: string) -> (),
	OnPlaceRequest: (itemId: string) -> (),
	OnPreview: (kind: string, id: string?) -> (),
	OnHouseChanged: () -> (),
	BeforeHouseChange: () -> (),
	GetAvailable: (itemId: string) -> number,
	-- Pièce dont on modifie murs / sol (nil = vue de la maison : choix dans la boutique)
	GetCurrentRoom: (() -> string?)?,
	-- Après un "buyRoom" réussi, quand la pièce est arrivée dans ClientState.Data
	OnRoomBought: ((roomId: string) -> ())?,
	-- Après "buySize" / "setSize" réussi, quand le nouvel état est arrivé
	OnSizeChanged: (() -> ())?,
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
	Fav: Frame,
	Comfort: TextLabel,
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

type FavTile = {
	Frame: Frame,
	Paint: (() -> ())?,
}

type RoomCard = {
	Type: RoomTypeDef,
	Card: Frame,
	Button: TextButton,
	Stroke: UIStroke,
	Count: Frame,
	Favs: { FavTile },
	More: Frame,
}

type MiniCell = { Frame: Frame, Floor: Frame, Label: TextLabel }

type SizeRow = {
	Size: SizeDef,
	Row: Frame,
	Tile: Frame,
	Scale: UIScale,
	Natural: Vector2,
	Texts: { GuiObject },
	Button: TextButton,
	Stroke: UIStroke,
	Status: TextLabel,
	Cells: { [number]: MiniCell },
	CellKey: string,
}

-- Onglets : Id, icône (onglet replié), texte (onglet choisi)
local TAB_DEFS = {
	{ Id = "Items", Icon = "🛋️", Text = "🛋️ Items" },
	{ Id = "Wallpapers", Icon = "🎨", Text = "🎨 Walls" },
	{ Id = "Floors", Icon = "🟫", Text = "🟫 Floors" },
	{ Id = "Rooms", Icon = "🚪", Text = "🚪 Rooms" },
	{ Id = "Sizes", Icon = "🏡", Text = "🏡 Houses" },
}
local SECTION_ALIASES: { [string]: string } = {
	Houses = "Sizes",
	Walls = "Wallpapers",
	Wallpaper = "Wallpapers",
	Floor = "Floors",
	Room = "Rooms",
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

local function setText(label: TextLabel, text: string, color: Color3?)
	if label.Text ~= text then
		label.Text = text
	end
	if color then
		label.TextColor3 = color
	end
end

-- Texte d'une ligne (étiquette simple)
local function textLine(parent: Instance, name: string, props: { [string]: any }): TextLabel
	return UIUtil.Create("TextLabel", {
		Name = name,
		Position = props.Position,
		Size = props.Size,
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Body,
		Text = props.Text or "",
		TextColor3 = props.TextColor3 or Theme.Colors.TextDim,
		TextSize = props.TextSize or 13,
		TextWrapped = props.TextWrapped == true,
		TextTruncate = props.TextWrapped and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		ZIndex = props.ZIndex or 35,
		Parent = parent,
	})
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

-- Petit rectangle arrondi (dessins des maisons)
local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): Frame
	local options = props or {}
	local frame = UIUtil.Create("Frame", {
		Name = options.Name or "Part",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BackgroundTransparency = options.Transparency or 0,
		BorderSizePixel = 0,
		ZIndex = options.ZIndex or 36,
		Parent = parent,
	})
	if options.Radius then
		UIUtil.Corner(frame, options.Radius)
	end
	if options.Stroke then
		UIUtil.Stroke(frame, options.Stroke, options.StrokeThickness or 1.5, 0)
	end
	return frame
end

-- Pièces triées par emplacement (rez-de-chaussée à gauche d'abord)
local function sortedRooms(house: HouseData): { Room }
	local rooms = table.clone(house.Rooms)
	table.sort(rooms, function(a, b)
		return a.Slot < b.Slot
	end)
	return rooms
end

-- Noms affichés des pièces ("🛏️ Chambre", "🛏️ Chambre 2" s'il y en a plusieurs)
local function roomLabels(house: HouseData): { [string]: string }
	local rooms = sortedRooms(house)
	local counts: { [string]: number } = {}
	for _, room in ipairs(rooms) do
		counts[room.Type] = (counts[room.Type] or 0) + 1
	end
	local seen: { [string]: number } = {}
	local labels: { [string]: string } = {}
	for _, room in ipairs(rooms) do
		local roomType = HouseCommon.GetRoomType(room)
		local label = roomType and (roomType.Icon .. " " .. HouseCommon.Name(roomType)) or room.Id
		if (counts[room.Type] or 0) > 1 then
			seen[room.Type] = (seen[room.Type] or 0) + 1
			label ..= " " .. tostring(seen[room.Type])
		end
		labels[room.Id] = label
	end
	return labels
end

-- "50" : bonus d'harmonie en %
local function harmonyPercent(): string
	return HouseCommon.FormatPercent((HouseCommon.Config.HarmonyBonus or 0) * 100)
end

-- "4.5" / "3" : confort lisible
local function formatComfort(value: number): string
	if math.abs(value - math.floor(value)) < 0.05 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%.1f", value)
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
	local roomCards: { RoomCard } = {}
	local sizeRows: { SizeRow } = {}
	local stickyPreview: { Kind: string, Id: string }? = nil
	local hoverPreview: { Kind: string, Id: string }? = nil
	local width = 380
	local openToken = 0
	local chosenRoomId: string? = nil -- pièce choisie dans la boutique (vue de la maison)
	local previewRoomId: string? = nil -- pièce visée par l'essai en cours
	local favRoomKey = "" -- type de la pièce ouverte (filtre / badges ✨)
	local refresh: () -> ()
	local layoutSizeRow: (row: SizeRow) -> ()
	local roomsHeader: Frame
	local roomsHarmony: TextLabel

	----------------------------------------------------------------------
	-- Pièce visée
	----------------------------------------------------------------------

	-- Pièce ouverte dans l'interface (nil = vue de la maison)
	local function currentRoom(house: HouseData): Room?
		local getter = handlers.GetCurrentRoom
		if not getter then
			return nil
		end
		local ok, roomId = pcall(getter)
		if ok and type(roomId) == "string" then
			return HouseCommon.GetRoom(house, roomId)
		end
		return nil
	end

	-- Pièce dont on change murs / sol : (pièce, verrouillée ?)
	-- verrouillée = la pièce ouverte ; sinon celle choisie dans la boutique
	-- (par défaut la première : rez-de-chaussée, à gauche)
	local function targetRoom(house: HouseData): (Room?, boolean)
		local current = currentRoom(house)
		if current then
			return current, true
		end
		local chosen = HouseCommon.GetRoom(house, chosenRoomId)
		if chosen then
			return chosen, false
		end
		return sortedRooms(house)[1], false
	end

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

	-- Onglets : même look que UIUtil.Tabs (fond gris clair, pastille blanche
	-- bordée), mais l'onglet choisi prend la place libre et affiche son nom
	local tabBar = UIUtil.Create("Frame", {
		Name = "Sections",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Theme.Colors.Surface,
		ZIndex = 31,
		Parent = drawer,
	})
	UIUtil.Corner(tabBar, UDim.new(1, 0))
	UIUtil.Stroke(tabBar, Theme.Colors.Divider, 1)
	local tabIndicator = UIUtil.Create("Frame", {
		Name = "Indicator",
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(80, 30),
		BackgroundColor3 = WHITE,
		ZIndex = 32,
		Parent = tabBar,
	})
	UIUtil.Corner(tabIndicator, UDim.new(1, 0))
	UIUtil.Stroke(tabIndicator, C.PinkDeep, 1.5, 0.35)
	local tabSelectedColor = C.PinkDeep:Lerp(Color3.new(0, 0, 0), 0.25)
	local tabButtons: { [string]: TextButton } = {}
	local selectedTab = "Items"

	local function tabGeometry(): { [string]: { X: number, W: number } }
		local inner = math.max(0, width - 24 - 6)
		local iconWidth = math.min(TAB_ICON_WIDTH, math.floor(inner / #TAB_DEFS))
		local selectedWidth = inner - iconWidth * (#TAB_DEFS - 1)
		local geometry = {}
		local x = 3
		for _, def in ipairs(TAB_DEFS) do
			local w = def.Id == selectedTab and selectedWidth or iconWidth
			geometry[def.Id] = { X = x, W = w }
			x += w
		end
		return geometry
	end

	local function layoutTabs(animated: boolean)
		local geometry = tabGeometry()
		for _, def in ipairs(TAB_DEFS) do
			local button = tabButtons[def.Id]
			local spot = geometry[def.Id]
			local selected = def.Id == selectedTab
			local text = selected and Locale.T(def.Text) or def.Icon
			if button.Text ~= text then
				button.Text = text
			end
			button.TextSize = selected and 14 or 17
			button.TextColor3 = selected and tabSelectedColor or Theme.Colors.TextDim
			local position = UDim2.fromOffset(spot.X, -4)
			local size = UDim2.fromOffset(spot.W, 44)
			if animated then
				UIUtil.Tween(button, 0.25, { Position = position, Size = size }, Enum.EasingStyle.Quint)
			else
				button.Position = position
				button.Size = size
			end
			if selected then
				local indicatorPosition = UDim2.fromOffset(spot.X, 3)
				local indicatorSize = UDim2.fromOffset(spot.W, 30)
				if animated then
					UIUtil.Tween(tabIndicator, 0.25, { Position = indicatorPosition, Size = indicatorSize }, Enum.EasingStyle.Quint)
				else
					tabIndicator.Position = indicatorPosition
					tabIndicator.Size = indicatorSize
				end
			end
		end
	end

	for index, def in ipairs(TAB_DEFS) do
		-- Zone cliquable plus haute que la barre (4 px de chaque côté)
		local button = UIUtil.Create("TextButton", {
			Name = def.Id,
			Size = UDim2.fromOffset(TAB_ICON_WIDTH, 44),
			Position = UDim2.fromOffset(3 + (index - 1) * TAB_ICON_WIDTH, -4),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = def.Icon,
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 33,
			Parent = tabBar,
		})
		tabButtons[def.Id] = button
		button.MouseEnter:Connect(function()
			if def.Id ~= selectedTab then
				button.TextColor3 = Theme.Colors.Text
			end
		end)
		button.MouseLeave:Connect(function()
			button.TextColor3 = def.Id == selectedTab and tabSelectedColor or Theme.Colors.TextDim
		end)
		button.Activated:Connect(function()
			if def.Id ~= selectedTab then
				SoundManager.Play("Click", 1.1)
				shop.Open(def.Id)
			end
		end)
	end

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

	local function setListTop(list: ScrollingFrame, top: number)
		list.Position = UDim2.fromOffset(0, top)
		list.Size = UDim2.new(1, 6, 1, -top)
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

	-- Bandeau "pièce" des onglets Murs / Sols
	local roomBar = UIUtil.Create("Frame", {
		Name = "RoomBar",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = C.PinkMist,
		Visible = false,
		ZIndex = 32,
		Parent = body,
	})
	UIUtil.Corner(roomBar, 14)
	UIUtil.Stroke(roomBar, C.PinkSoft, 1.5, 0)
	local roomHint = textLine(roomBar, "Hint", {
		Position = UDim2.fromOffset(10, 5),
		Size = UDim2.new(1, -20, 0, 18),
		TextColor3 = C.Ink,
		TextSize = 13,
		ZIndex = 33,
	})
	local roomChips = UIUtil.Create("ScrollingFrame", {
		Name = "Rooms",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 0,
		ZIndex = 33,
		Parent = roomBar,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = roomChips,
	})
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = roomChips,
	})
	local roomChipsKey = ""

	local wallpapersList = scroller("WallpapersList", 50)
	local wallpapersGrid = UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, STYLE_CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(8, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wallpapersList,
	})
	local floorsList = scroller("FloorsList", 50)
	local floorsGrid = UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, STYLE_CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(8, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = floorsList,
	})
	local roomsList = scroller("RoomsList", 0)
	UIUtil.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = roomsList,
	})
	local sizesList = scroller("SizesList", 0)
	UIUtil.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = sizesList,
	})

	-- Largeur utile de la colonne de texte d'une carte de pièce
	local function roomTextWidth(): number
		return width - LIST_INSET - (8 + 88 + 10) - 8
	end

	-- Vignettes "préférés" visibles selon la largeur ("+N" si ça déborde)
	local function fitFavorites(card: RoomCard)
		local fit = math.max(1, math.floor((roomTextWidth() + FAV_GAP) / (FAV_TILE + FAV_GAP)))
		local total = #card.Favs
		local shown = total <= fit and total or (fit - 1)
		for index, tile in ipairs(card.Favs) do
			local visible = index <= shown
			tile.Frame.Visible = visible
			tile.Frame.Position = UDim2.fromOffset((index - 1) * (FAV_TILE + FAV_GAP), 0)
			if visible and tile.Paint then
				local paint = tile.Paint
				tile.Paint = nil
				task.defer(paint)
			end
		end
		card.More.Visible = shown < total
		if shown < total then
			card.More.Position = UDim2.fromOffset(shown * (FAV_TILE + FAV_GAP), 0)
			local label = card.More:FindFirstChild("Label") :: TextLabel?
			if label then
				label.Text = "+" .. tostring(total - shown)
			end
		end
	end

	-- Nombre de colonnes selon la largeur du tiroir
	local function relayoutGrids()
		local designWidth = width - 40 -- marges du tiroir et de la liste
		local columns = math.clamp(math.floor(designWidth / 118), 2, 5)
		local styleColumns = math.clamp(math.floor(designWidth / 150), 2, 4)
		itemsGrid.CellSize = UDim2.new(1 / columns, -8, 0, CARD_HEIGHT)
		wallpapersGrid.CellSize = UDim2.new(1 / styleColumns, -8, 0, STYLE_CARD_HEIGHT)
		floorsGrid.CellSize = UDim2.new(1 / styleColumns, -8, 0, STYLE_CARD_HEIGHT)
		for _, card in ipairs(roomCards) do
			fitFavorites(card)
		end
		for _, row in ipairs(sizeRows) do
			layoutSizeRow(row)
		end
		-- En-tête des pièces : l'explication tient sur une ligne si c'est large
		local wide = width >= 400
		roomsHeader.Size = UDim2.new(1, 0, 0, wide and 72 or 88)
		roomsHarmony.Size = UDim2.new(1, -24, 0, wide and 16 or 32)
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
	local function request(action: string, argument: any, button: GuiObject): (boolean, string?)
		if busy then
			return false, nil
		end
		busy = true
		local ok, message = HouseCommon.Invoke(action, argument)
		busy = false
		if not ok then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(button)
			handlers.Notify(message or Locale.T("Not possible right now."), Theme.Colors.Red)
		end
		return ok, message
	end

	-- Pas assez de Dopamine : fenêtre "Get Dopamine" (ou bulle)
	local function needDopamine(button: GuiObject, price: number)
		SoundManager.Play("Error", 0.7)
		UIUtil.Shake(button)
		local missing = price - HouseCommon.Dopamine()
		NeedDopamine.Offer(missing, function()
			handlers.Notify(Locale.T("You need %s more Dopamine", NumberFormatter.Format(missing)), Theme.Colors.Red)
		end)
	end

	-- Attend (3 s max) que le nouvel état du serveur soit arrivé
	local function waitForState(check: (house: HouseData) -> boolean): boolean
		for _ = 1, 60 do
			if check(HouseCommon.GetHouse(ClientState.Data)) then
				return true
			end
			task.wait(0.05)
		end
		return check(HouseCommon.GetHouse(ClientState.Data))
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
			needDopamine(card.Button, price)
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
		local room = targetRoom(house)
		if not room then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(card.Button)
			handlers.Notify(Locale.T("Open a room to change its walls and floor"), Theme.Colors.Orange)
			return
		end
		local owned = card.Kind == "Wallpaper" and house.OwnedWallpapers or house.OwnedFloors
		local equipped = card.Kind == "Wallpaper" and room.Wallpaper or room.Floor
		local id = card.Style.Id
		if equipped == id then
			UIUtil.Pop(card.Card, 1.05, 0.3)
			return
		end
		local isOwned = owned[id] == true or card.Style.Cost <= 0
		if not isOwned and HouseCommon.Dopamine() < card.Style.Cost then
			needDopamine(card.Button, card.Style.Cost)
			return
		end
		local action = (isOwned and "set" or "buy") .. card.Kind
		local roomId = room.Id
		task.spawn(function()
			local ok, message = request(action, { Room = roomId, Id = id }, card.Button)
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
				refresh()
			end
		end)
	end

	local function buyRoomType(card: RoomCard)
		local house = HouseCommon.GetHouse(ClientState.Data)
		local size = HouseCommon.GetSize(house)
		if #house.Rooms >= size.MaxRooms then
			-- Maison pleine : direction l'onglet des maisons
			SoundManager.Play("Pop", 1)
			handlers.Notify(Locale.T("Your house is full: move to a bigger house!"), Theme.Colors.Orange)
			shop.Open("Sizes")
			return
		end
		local price = HouseCommon.RoomCost(house)
		if HouseCommon.Dopamine() < price then
			needDopamine(card.Button, price)
			return
		end
		local before: { [string]: boolean } = {}
		for _, room in ipairs(house.Rooms) do
			before[room.Id] = true
		end
		local typeId = card.Type.Id
		task.spawn(function()
			local ok, message = request("buyRoom", { Type = typeId }, card.Button)
			if not ok then
				return
			end
			celebrate(card.Card, true)
			handlers.Notify(message or Locale.T("New room: %s!", card.Type.Icon .. " " .. HouseCommon.Name(card.Type)), Theme.Colors.Green, Locale.T("🚪 New room!"))
			UIUtil.Pop(card.Card, 1.05, 0.35)
			-- La nouvelle pièce = l'Id absent avant l'achat (du bon type)
			local newId: string? = nil
			waitForState(function(latest: HouseData): boolean
				for _, room in ipairs(latest.Rooms) do
					if not before[room.Id] and room.Type == typeId then
						newId = room.Id
						return true
					end
				end
				return false
			end)
			handlers.OnHouseChanged()
			local onBought = handlers.OnRoomBought
			if newId and onBought then
				onBought(newId)
			end
			refresh()
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
			needDopamine(row.Button, size.Cost)
			return
		end
		-- Dispositions en attente envoyées AVANT le déménagement (le serveur
		-- recale ensuite les pièces et les objets pour la nouvelle maison)
		handlers.BeforeHouseChange()
		local sizeId = size.Id
		task.spawn(function()
			local ok, message = request(isOwned and "setSize" or "buySize", sizeId, row.Button)
			if not ok then
				return
			end
			if isOwned then
				SoundManager.Play("Open", 1)
			else
				celebrate(row.Row, true)
			end
			handlers.Notify(message or Locale.T("Welcome home!"), Theme.Colors.Green, if isOwned then nil else Locale.T("🏡 New house!"))
			waitForState(function(latest: HouseData): boolean
				if isOwned then
					return latest.Size == sizeId
				end
				return latest.OwnedSizes[sizeId] == true
			end)
			handlers.OnHouseChanged()
			local onChanged = handlers.OnSizeChanged
			if onChanged then
				onChanged()
			end
			refresh()
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
		local stroke = UIUtil.Stroke(card, SOFT_STROKE, 1.5, 0)
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
			Position = UDim2.new(1, -3, 1, -3),
			Height = 18,
			TextSize = 11,
			ZIndex = 38,
		})
		-- ✨ = objet préféré de la pièce ouverte (confort x1.5 dans cette pièce)
		local favBadge = UIUtil.Create("Frame", {
			Name = "Favorite",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 3, 1, -3),
			Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = C.Lilac,
			Visible = false,
			ZIndex = 38,
			Parent = tile,
		})
		UIUtil.Corner(favBadge, UDim.new(1, 0))
		UIUtil.Stroke(favBadge, WHITE, 1.5, 0)
		UIUtil.Create("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = "✨",
			TextSize = 12,
			ZIndex = 39,
			Parent = favBadge,
		})
		textLine(card, "Name", {
			Position = UDim2.fromOffset(8, 90),
			Size = UDim2.new(1, -16, 0, 18),
			Font = Theme.Fonts.Title,
			Text = HouseCommon.Name(item),
			TextColor3 = Theme.Colors.Text,
			TextSize = 14,
		})
		local comfort = textLine(card, "Comfort", {
			Position = UDim2.fromOffset(8, 108),
			Size = UDim2.new(1, -16, 0, 16),
			Text = Locale.T("❤️ +%d comfort", item.Comfort),
			TextColor3 = C.PinkDeep,
			TextSize = 13,
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
			Fav = favBadge,
			Comfort = comfort,
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
		textLine(card, "Name", {
			Position = UDim2.fromOffset(8, 88),
			Size = UDim2.new(1, -16, 0, 18),
			Font = Theme.Fonts.Title,
			Text = (style.Icon and (style.Icon .. " ") or "") .. HouseCommon.Name(style),
			TextColor3 = Theme.Colors.Text,
			TextSize = 14,
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

	-- Onglet Pièces : carte d'en-tête (compteur, prix, harmonie)
	roomsHeader = UIUtil.Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = C.PinkMist,
		LayoutOrder = 0,
		ZIndex = 34,
		Parent = roomsList,
	})
	UIUtil.Corner(roomsHeader, 16)
	UIUtil.Stroke(roomsHeader, C.PinkSoft:Lerp(C.Pink, 0.4), 1.5, 0)
	local roomsCounter = textLine(roomsHeader, "Counter", {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 20),
		Font = Theme.Fonts.Title,
		TextColor3 = C.Ink,
		TextSize = 15,
	})
	local roomsNext = textLine(roomsHeader, "Next", {
		Position = UDim2.fromOffset(12, 29),
		Size = UDim2.new(1, -24, 0, 18),
		Font = Theme.Fonts.Title,
		TextColor3 = C.PinkDeep,
		TextSize = 13,
	})
	roomsHarmony = textLine(roomsHeader, "Harmony", {
		Position = UDim2.fromOffset(12, 48),
		Size = UDim2.new(1, -24, 0, 30),
		Text = Locale.T("✨ Items a room loves give +%s%% comfort there", harmonyPercent()),
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	-- Petites vignettes à peindre (objets préférés des pièces), par paquets
	local thumbQueue: { () -> () } = {}
	local thumbPainting = false
	local function queueThumb(paint: () -> ())
		table.insert(thumbQueue, paint)
		if thumbPainting then
			return
		end
		thumbPainting = true
		task.spawn(function()
			while #thumbQueue > 0 do
				for _ = 1, 8 do
					local job = table.remove(thumbQueue, 1)
					if not job then
						break
					end
					job()
				end
				task.wait()
			end
			thumbPainting = false
		end)
	end

	-- Vignette "préféré" : catégorie (emoji sur blanc, bord lilas) ou objet (dessin)
	local function favTile(holder: Frame, entry: { Kind: string, Icon: string, Item: Item? }): FavTile
		local frame = UIUtil.Create("Frame", {
			Name = "Fav",
			Size = UDim2.fromOffset(FAV_TILE, FAV_TILE),
			BackgroundColor3 = entry.Item and HouseCommon.CategoryTint(entry.Item.Category) or WHITE,
			ZIndex = 36,
			Parent = holder,
		})
		UIUtil.Corner(frame, 9)
		UIUtil.Stroke(frame, entry.Kind == "Category" and C.Lilac or SOFT_STROKE, entry.Kind == "Category" and 1.5 or 1, 0)
		local emoji = UIUtil.Create("TextLabel", {
			Name = "Emoji",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = entry.Icon,
			TextSize = 18,
			ZIndex = 37,
			Parent = frame,
		})
		local tile: FavTile = { Frame = frame, Paint = nil }
		local item = entry.Item
		if item and HouseArt.Has(item.Id) then
			tile.Paint = function()
				queueThumb(function()
					if frame.Parent then
						HouseArt.Thumbnail(frame, item, FAV_TILE - 6, 38)
						emoji.Visible = false
					end
				end)
			end
		end
		return tile
	end

	-- Préférés d'un type de pièce : catégories, objets cités, puis quelques
	-- objets des catégories préférées (les moins chers d'abord)
	local function favoritesOf(roomType: RoomTypeDef): { { Kind: string, Icon: string, Item: Item? } }
		local list = {}
		local used: { [string]: boolean } = {}
		for _, categoryId in ipairs(roomType.Categories or {}) do
			local entry = HouseCommon.CategoriesById[categoryId]
			if entry then
				table.insert(list, { Kind = "Category", Icon = entry.Icon, Item = nil })
			end
		end
		for _, itemId in ipairs(roomType.Items or {}) do
			local item = HouseCommon.ItemsById[itemId]
			if item and not used[itemId] and #list < MAX_FAVS then
				used[itemId] = true
				table.insert(list, { Kind = "Item", Icon = item.Icon, Item = item })
			end
		end
		if #list < MAX_FAVS and #(roomType.Categories or {}) > 0 then
			local extra = {}
			for _, item in ipairs(HouseCommon.Config.Items) do
				if not used[item.Id] and roomType.FavoriteCategories and roomType.FavoriteCategories[item.Category] then
					table.insert(extra, item)
				end
			end
			table.sort(extra, function(a, b)
				return a.Cost < b.Cost
			end)
			for _, item in ipairs(extra) do
				if #list >= MAX_FAVS then
					break
				end
				table.insert(list, { Kind = "Item", Icon = item.Icon, Item = item })
			end
		end
		return list
	end

	local function buildRoomCard(roomType: RoomTypeDef)
		local card = UIUtil.Create("Frame", {
			Name = roomType.Id,
			Size = UDim2.new(1, 0, 0, ROOM_CARD_HEIGHT),
			BackgroundColor3 = WHITE,
			LayoutOrder = (roomType.Order or 0) + 1,
			ZIndex = 34,
			Parent = roomsList,
		})
		UIUtil.Corner(card, 16)
		local stroke = UIUtil.Stroke(card, SOFT_STROKE, 1.5, 0)
		-- Aperçu : mur + sol par défaut du type, emoji dans une bulle blanche
		local preview = UIUtil.Create("Frame", {
			Name = "Preview",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(0, 88, 1, -16),
			BackgroundColor3 = C.PinkSoft,
			ZIndex = 35,
			Parent = card,
		})
		preview:SetAttribute("DarkSkinIgnore", true)
		UIUtil.Corner(preview, 12)
		UIUtil.Stroke(preview, SOFT_STROKE, 1, 0)
		local canvas = UIUtil.Create("CanvasGroup", {
			Name = "Canvas",
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			ZIndex = 36,
			Parent = preview,
		})
		UIUtil.Corner(canvas, 12)
		local artHeight = (ROOM_CARD_HEIGHT - 16) * 2
		local wallHeight = math.floor(artHeight * 0.52)
		local art = UIUtil.Create("Frame", {
			Name = "Art",
			Size = UDim2.fromOffset(176, artHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 36,
			Parent = canvas,
		})
		UIUtil.Create("UIScale", { Scale = 0.5, Parent = art })
		local wall = UIUtil.Create("Frame", {
			Name = "Wall",
			Size = UDim2.fromOffset(176, wallHeight),
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 36,
			Parent = art,
		})
		local floor = UIUtil.Create("Frame", {
			Name = "Floor",
			Position = UDim2.fromOffset(0, wallHeight),
			Size = UDim2.fromOffset(176, artHeight - wallHeight),
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 36,
			Parent = art,
		})
		local wallStyle = HouseCommon.WallpapersById[roomType.Wallpaper] or HouseCommon.Config.Wallpapers[1]
		local floorStyle = HouseCommon.FloorsById[roomType.Floor] or HouseCommon.Config.Floors[1]
		if wallStyle then
			wall.BackgroundColor3 = wallStyle.A
			HousePatterns.BuildWall(wall, 176, wallHeight, wallStyle, 1)
		end
		if floorStyle then
			floor.BackgroundColor3 = floorStyle.A
			HousePatterns.BuildFloor(floor, 176, artHeight - wallHeight, floorStyle, 1)
		end
		box(art, 0, wallHeight - 3, 176, 7, WHITE, { Name = "Baseboard", ZIndex = 38, Transparency = 0.1 })
		local bubble = UIUtil.Create("Frame", {
			Name = "Bubble",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.08,
			ZIndex = 40,
			Parent = preview,
		})
		UIUtil.Corner(bubble, UDim.new(1, 0))
		UIUtil.Stroke(bubble, C.PinkSoft:Lerp(C.Pink, 0.35), 1.5, 0)
		UIUtil.Create("TextLabel", {
			Name = "Emoji",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = roomType.Icon,
			TextSize = 30,
			ZIndex = 41,
			Parent = bubble,
		})
		-- Nombre de pièces de ce type dans la maison
		local count = tag(preview, "x1", C.Lilac, WHITE, {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Height = 18,
			TextSize = 11,
			ZIndex = 42,
		})
		count.Visible = false

		local textLeft = 8 + 88 + 10
		textLine(card, "Name", {
			Position = UDim2.fromOffset(textLeft, 8),
			Size = UDim2.new(1, -(textLeft + 8), 0, 20),
			Font = Theme.Fonts.Title,
			Text = HouseCommon.Name(roomType),
			TextColor3 = Theme.Colors.Text,
			TextSize = 16,
		})
		textLine(card, "Loves", {
			Position = UDim2.fromOffset(textLeft, 28),
			Size = UDim2.new(1, -(textLeft + 8), 0, 16),
			Text = Locale.T("✨ Loves (+%s%%):", harmonyPercent()),
			TextColor3 = C.Lilac:Lerp(C.Ink, 0.35),
			TextSize = 12,
		})
		local favHolder = UIUtil.Create("Frame", {
			Name = "Favorites",
			Position = UDim2.fromOffset(textLeft, 47),
			Size = UDim2.new(1, -(textLeft + 8), 0, FAV_TILE),
			BackgroundTransparency = 1,
			ZIndex = 35,
			Parent = card,
		})
		local favs: { FavTile } = {}
		for _, entry in ipairs(favoritesOf(roomType)) do
			table.insert(favs, favTile(favHolder, entry))
		end
		local more = UIUtil.Create("Frame", {
			Name = "More",
			Size = UDim2.fromOffset(FAV_TILE, FAV_TILE),
			BackgroundColor3 = C.LilacSoft,
			Visible = false,
			ZIndex = 36,
			Parent = favHolder,
		})
		UIUtil.Corner(more, 9)
		UIUtil.Create("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = "+0",
			TextColor3 = C.Ink,
			TextSize = 13,
			ZIndex = 37,
			Parent = more,
		})
		local button = actionButton(card, {
			Size = UDim2.new(1, -(textLeft + 8), 0, 34),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, textLeft, 1, -8),
			ZIndex = 35,
		})
		local entry: RoomCard = {
			Type = roomType,
			Card = card,
			Button = button,
			Stroke = stroke,
			Count = count,
			Favs = favs,
			More = more,
		}
		table.insert(roomCards, entry)
		fitFavorites(entry)
		button.Activated:Connect(function()
			buyRoomType(entry)
		end)
	end

	-- Silhouette d'un bâtiment (dessinée à taille "naturelle" puis réduite
	-- par un UIScale pour tenir dans la vignette) : cellules = pièces
	local CELL_W, CELL_H, CELL_GAP, FACADE_PAD = 24, 20, 4, 5
	local EXTERIORS: { [string]: { Facade: Color3, Edge: Color3, Roof: Color3, RoofDark: Color3 } } = {
		Cottage = {
			Facade = Color3.fromRGB(255, 244, 230),
			Edge = Color3.fromRGB(226, 186, 160),
			Roof = C.Pink,
			RoofDark = C.PinkDeep,
		},
		Townhouse = {
			Facade = Color3.fromRGB(238, 228, 255),
			Edge = Color3.fromRGB(176, 150, 230),
			Roof = Color3.fromRGB(150, 118, 212),
			RoofDark = Color3.fromRGB(118, 90, 180),
		},
		Loft = {
			Facade = Color3.fromRGB(232, 150, 128),
			Edge = Color3.fromRGB(176, 98, 86),
			Roof = Color3.fromRGB(118, 96, 110),
			RoofDark = Color3.fromRGB(92, 72, 88),
		},
		Mansion = {
			Facade = Color3.fromRGB(255, 248, 238),
			Edge = Color3.fromRGB(230, 196, 170),
			Roof = C.Pink,
			RoofDark = C.PinkDeep,
		},
	}

	local function drawBuilding(tile: Frame, size: SizeDef): ({ [number]: MiniCell }, UIScale, Vector2)
		local style = EXTERIORS[size.Exterior] or EXTERIORS.Cottage
		local cols, floors = math.max(1, size.Columns), math.max(1, size.Floors)
		local bodyW = cols * CELL_W + (cols - 1) * CELL_GAP + 2 * FACADE_PAD
		local bodyH = floors * CELL_H + (floors - 1) * CELL_GAP + 2 * FACADE_PAD
		local isMansion = size.Exterior == "Mansion"
		local towerW = isMansion and 18 or 0
		local roofH = if size.Exterior == "Loft" then 18 elseif isMansion then 26 else 22
		local groundH = 8
		local totalW = bodyW + 2 * towerW + 8
		local totalH = roofH + bodyH + groundH
		local holder = UIUtil.Create("Frame", {
			Name = "Building",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.fromOffset(totalW, totalH),
			BackgroundTransparency = 1,
			ZIndex = 36,
			Parent = tile,
		})
		local scale = UIUtil.Create("UIScale", { Parent = holder })
		local left = towerW + 4
		local top = roofH
		-- Sol / jardin
		box(holder, 0, totalH - groundH, totalW, groundH, C.Mint, { Name = "Ground", Radius = 4, ZIndex = 37 })
		if isMansion then
			-- Haies rondes au pied des tours
			for _, x in ipairs({ 0, 9, totalW - 17, totalW - 8 }) do
				box(holder, x, totalH - groundH - 6, 9, 9, Color3.fromRGB(96, 196, 150), { Name = "Hedge", Radius = 5, ZIndex = 39 })
			end
		end
		-- Tours (manoir) : corps lilas + toit pointu en gradins + drapeau
		if isMansion then
			for _, x in ipairs({ 2, totalW - towerW - 2 }) do
				local towerTop = top - 6
				box(holder, x, towerTop, towerW, totalH - groundH - towerTop, C.LilacSoft, {
					Name = "Tower", Radius = 3, Stroke = style.Edge, StrokeThickness = 1, ZIndex = 37,
				})
				box(holder, x + 5, towerTop + 10, towerW - 10, 10, C.Sky, { Name = "TowerWindow", Radius = 4, ZIndex = 38 })
				box(holder, x - 2, towerTop - 6, towerW + 4, 7, C.Lilac, { Name = "TowerRoof", Radius = 3, ZIndex = 38 })
				box(holder, x + 2, towerTop - 12, towerW - 4, 7, C.Lilac, { Name = "TowerRoof", Radius = 3, ZIndex = 38 })
				box(holder, x + 6, towerTop - 18, towerW - 12, 7, C.Lilac, { Name = "TowerRoof", Radius = 3, ZIndex = 38 })
				box(holder, x + towerW / 2 - 0.5, towerTop - 26, 1.5, 9, style.Edge, { Name = "Pole", ZIndex = 38 })
				box(holder, x + towerW / 2 + 1, towerTop - 26, 7, 5, C.Heart, { Name = "Flag", Radius = 2, ZIndex = 38 })
			end
		end
		-- Toit
		if size.Exterior == "Loft" then
			-- Toit plat, château d'eau et petite plante
			box(holder, left - 3, top - 5, bodyW + 6, 6, style.RoofDark, { Name = "Roof", Radius = 2, ZIndex = 38 })
			box(holder, left + bodyW - 22, top - 17, 13, 9, C.Wood, { Name = "WaterTower", Radius = 3, ZIndex = 38 })
			box(holder, left + bodyW - 21, top - 8, 2, 4, C.WoodDark, { Name = "Leg", ZIndex = 38 })
			box(holder, left + bodyW - 12, top - 8, 2, 4, C.WoodDark, { Name = "Leg", ZIndex = 38 })
			box(holder, left + 6, top - 14, 10, 10, C.Mint, { Name = "Plant", Radius = 5, ZIndex = 38 })
			box(holder, left + 8, top - 7, 6, 4, C.WoodDark, { Name = "Pot", Radius = 1, ZIndex = 38 })
		elseif size.Exterior == "Townhouse" then
			-- Toit mansardé + lucarnes
			box(holder, left - 4, top - 6, bodyW + 8, 7, style.RoofDark, { Name = "Roof", Radius = 3, ZIndex = 38 })
			box(holder, left + 3, top - 16, bodyW - 6, 11, style.Roof, { Name = "Roof", Radius = 4, ZIndex = 38 })
			box(holder, left + bodyW / 2 - 12, top - 14, 8, 7, C.Butter, { Name = "Dormer", Radius = 2, ZIndex = 39 })
			box(holder, left + bodyW / 2 + 4, top - 14, 8, 7, C.Butter, { Name = "Dormer", Radius = 2, ZIndex = 39 })
			box(holder, left + bodyW - 14, top - 22, 6, 9, C.WoodDark, { Name = "Chimney", Radius = 1, ZIndex = 37 })
		else
			-- Toit en gradins arrondis (chaumière, fronton du manoir)
			local steps = isMansion and 4 or 3
			local stepH = math.floor((roofH - 2) / steps)
			for index = 1, steps do
				local inset = (index - 1) * (bodyW / (steps * 2 + 1))
				local color = index == 1 and style.RoofDark or style.Roof
				box(holder, left - 4 + inset, top - index * stepH, bodyW + 8 - inset * 2, stepH + 1, color, {
					Name = "Roof", Radius = 3, ZIndex = 38 + index,
				})
			end
			if isMansion then
				box(holder, left + bodyW / 2 - 4, top - steps * stepH - 7, 8, 7, C.Heart, { Name = "Heart", Radius = 4, ZIndex = 43 })
			else
				box(holder, left + bodyW - 16, top - roofH + 1, 6, 10, Color3.fromRGB(214, 120, 128), {
					Name = "Chimney", Radius = 1, ZIndex = 37,
				})
			end
		end
		-- Façade
		local facade = box(holder, left, top, bodyW, bodyH, style.Facade, {
			Name = "Facade", Radius = 4, Stroke = style.Edge, StrokeThickness = 1, ZIndex = 37,
		})
		-- Cellules = pièces (étage 1 en bas)
		local cells: { [number]: MiniCell } = {}
		for slot = 1, cols * floors do
			local floorIndex, column = HouseCommon.SlotCell(size, slot)
			local x = FACADE_PAD + (column - 1) * (CELL_W + CELL_GAP)
			local y = bodyH - FACADE_PAD - floorIndex * CELL_H - (floorIndex - 1) * CELL_GAP
			local cell = box(facade, x, y, CELL_W, CELL_H, C.Cream, {
				Name = "Cell" .. slot, Radius = 3, Stroke = style.Edge, StrokeThickness = 1, ZIndex = 38,
			})
			local floorStrip = box(cell, 0, CELL_H - 7, CELL_W, 7, C.Wood, { Name = "FloorStrip", Radius = 3, ZIndex = 39 })
			local label = UIUtil.Create("TextLabel", {
				Name = "Icon",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Text = "",
				TextSize = 13,
				ZIndex = 40,
				Parent = cell,
			})
			cells[slot] = { Frame = cell, Floor = floorStrip, Label = label }
		end
		-- Balcons entre les étages (maison de ville) / fleurs (chaumière)
		if size.Exterior == "Townhouse" then
			for floorIndex = 2, floors do
				local y = bodyH - FACADE_PAD - (floorIndex - 1) * (CELL_H + CELL_GAP) - CELL_H - 1
				box(facade, FACADE_PAD - 2, y + CELL_H - 1, bodyW - 2 * FACADE_PAD + 4, 2, style.Edge, { Name = "Balcony", ZIndex = 41 })
			end
		elseif size.Exterior == "Cottage" then
			for column = 1, cols do
				local x = FACADE_PAD + (column - 1) * (CELL_W + CELL_GAP)
				box(facade, x + 3, bodyH - 4, CELL_W - 6, 3, C.Mint, { Name = "FlowerBox", Radius = 1, ZIndex = 41 })
			end
		end
		return cells, scale, Vector2.new(totalW, totalH)
	end

	-- Aspect des cellules : pièces du joueur (maison actuelle) ou fenêtres
	local function paintCells(row: SizeRow, house: HouseData, current: boolean)
		local key = "other"
		if current then
			local parts = {}
			for _, room in ipairs(sortedRooms(house)) do
				table.insert(parts, room.Slot .. ":" .. room.Type .. ":" .. room.Wallpaper .. ":" .. room.Floor)
			end
			key = table.concat(parts, "|")
		end
		if row.CellKey == key then
			return
		end
		row.CellKey = key
		for slot, cell in pairs(row.Cells) do
			local room = current and HouseCommon.RoomAtSlot(house, slot) or nil
			if room then
				local wallpaper = HouseCommon.GetRoomWallpaper(room)
				local floor = HouseCommon.GetRoomFloor(room)
				local roomType = HouseCommon.GetRoomType(room)
				cell.Frame.BackgroundColor3 = wallpaper and wallpaper.A or C.Cream
				cell.Frame.BackgroundTransparency = 0
				cell.Floor.Visible = true
				cell.Floor.BackgroundColor3 = floor and floor.A or C.Wood
				cell.Label.Text = roomType and roomType.Icon or ""
			elseif current then
				-- Emplacement libre de la maison actuelle
				cell.Frame.BackgroundColor3 = WHITE
				cell.Frame.BackgroundTransparency = 0.25
				cell.Floor.Visible = false
				cell.Label.Text = ""
			else
				-- Autre maison : fenêtres éclairées
				cell.Frame.BackgroundColor3 = Color3.fromRGB(255, 244, 206)
				cell.Frame.BackgroundTransparency = 0
				cell.Floor.Visible = false
				cell.Label.Text = ""
			end
		end
	end

	-- Vignette plus large quand le tiroir l'est (le manoir reste lisible)
	layoutSizeRow = function(row: SizeRow)
		local tileW = width >= 400 and 132 or 104
		local tileH = SIZE_ROW_HEIGHT - 16
		row.Tile.Size = UDim2.fromOffset(tileW, tileH)
		row.Scale.Scale = math.min((tileW - 10) / row.Natural.X, (tileH - 8) / row.Natural.Y, 1.5)
		local textLeft = 8 + tileW + 10
		for _, object in ipairs(row.Texts) do
			object.Position = UDim2.new(0, textLeft, object.Position.Y.Scale, object.Position.Y.Offset)
			object.Size = UDim2.new(1, -(textLeft + 8), object.Size.Y.Scale, object.Size.Y.Offset)
		end
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
		local stroke = UIUtil.Stroke(row, SOFT_STROKE, 1.5, 0)
		local tile = UIUtil.Create("Frame", {
			Name = "Preview",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(104, SIZE_ROW_HEIGHT - 16),
			BackgroundColor3 = WHITE,
			ZIndex = 35,
			Parent = row,
		})
		tile:SetAttribute("DarkSkinIgnore", true)
		UIUtil.Corner(tile, 14)
		UIUtil.Stroke(tile, SOFT_STROKE, 1, 0)
		UIUtil.Gradient(tile, ColorSequence.new(Color3.fromRGB(206, 232, 255), Color3.fromRGB(255, 232, 242)), 90)
		local cells, scale, natural = drawBuilding(tile, size)
		local name = textLine(row, "Name", {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 20),
			Font = Theme.Fonts.Title,
			Text = size.Icon .. " " .. HouseCommon.Name(size),
			TextColor3 = Theme.Colors.Text,
			TextSize = 16,
		})
		local grid = textLine(row, "Grid", {
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 16),
			Text = size.Floors == 1 and Locale.T("🏢 1 floor × %d rooms", size.Columns)
				or Locale.T("🏢 %d floors × %d rooms", size.Floors, size.Columns),
			TextSize = 12,
		})
		local items = textLine(row, "Items", {
			Position = UDim2.fromOffset(0, 47),
			Size = UDim2.new(1, 0, 0, 16),
			Text = Locale.T("🛋️ up to %d items / room", size.RoomItems),
			TextSize = 12,
		})
		local status = textLine(row, "Status", {
			Position = UDim2.fromOffset(0, 65),
			Size = UDim2.new(1, 0, 0, 18),
			TextColor3 = C.PinkDeep,
			TextSize = 13,
		})
		local button = actionButton(row, {
			Size = UDim2.new(1, 0, 0, 34),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -8),
			ZIndex = 35,
		})
		local entry: SizeRow = {
			Size = size,
			Row = row,
			Tile = tile,
			Scale = scale,
			Natural = natural,
			Texts = { name, grid, items, status, button },
			Button = button,
			Stroke = stroke,
			Status = status,
			Cells = cells,
			CellKey = "",
		}
		layoutSizeRow(entry)
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
		local house = HouseCommon.GetHouse(ClientState.Data)
		local room = currentRoom(house)
		for _, card in ipairs(itemCards) do
			local visible
			if category == "Favorites" then
				visible = room ~= nil and HouseCommon.IsFavorite(room, card.Item)
			else
				visible = category == "All" or card.Item.Category == category
			end
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
	-- Préférés de la pièce ouverte (cachée dans la vue de la maison)
	categoryPill("Favorites", "", 1)
	local favoritesPill = categoryButtons.Favorites
	favoritesPill.Visible = false
	for index, entry in ipairs(HouseCommon.Config.Categories) do
		categoryPill(entry.Id, entry.Icon .. " " .. HouseCommon.Name(entry), index + 1)
	end
	paintCategories()
	task.defer(refreshMoreHint)

	-- Pastille "préférés" et filtre selon la pièce ouverte
	local function syncFavoriteRoom(house: HouseData)
		local room = currentRoom(house)
		local roomType = room and HouseCommon.GetRoomType(room)
		local key = roomType and roomType.Id or ""
		if key == favRoomKey then
			return
		end
		favRoomKey = key
		favoritesPill.Visible = roomType ~= nil
		if roomType then
			favoritesPill.Text = Locale.T("%s Favourites", roomType.Icon)
		end
		if category == "Favorites" and not roomType then
			category = "All"
			paintCategories()
		end
		if built.Items then
			applyFilter()
		end
		task.defer(refreshMoreHint)
	end

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
		elseif name == "Rooms" then
			task.spawn(function()
				for index, roomType in ipairs(HouseCommon.Config.RoomTypes) do
					buildRoomCard(roomType)
					if index % 4 == 0 then
						refresh()
						task.wait()
					end
				end
				refresh()
			end)
		elseif name == "Sizes" then
			for _, size in ipairs(HouseCommon.Config.Sizes) do
				buildSizeRow(size)
			end
		end
	end

	----------------------------------------------------------------------
	-- Bandeau de la pièce (Murs / Sols)
	----------------------------------------------------------------------

	local function refreshRoomBar(house: HouseData)
		local room, locked = targetRoom(house)
		local kind = section == "Wallpapers" and "Wallpaper" or "Floor"
		-- L'essai en cours visait une autre pièce : on l'arrête
		local roomId = room and room.Id or nil
		if roomId ~= previewRoomId then
			previewRoomId = roomId
			if stickyPreview or hoverPreview then
				endPreviews()
			end
		end
		local labels = roomLabels(house)
		-- Pièce ouverte : une ligne "🎨 Murs de cette pièce : [🛏️ Chambre]" ;
		-- vue de la maison : consigne + choix parmi toutes les pièces
		local barHeight = locked and 42 or 66
		roomHint.Visible = not locked
		roomHint.Text = Locale.T("🏠 Open a room, or pick one here:")
		roomBar.Size = UDim2.new(1, 0, 0, barHeight)
		roomChips.Position = UDim2.fromOffset(0, locked and 3 or 26)
		setListTop(wallpapersList, barHeight + 6)
		setListTop(floorsList, barHeight + 6)
		-- Pastilles des pièces (reconstruites si la liste change)
		local parts = { locked and ("L" .. kind) or "U", roomId or "" }
		for _, entry in ipairs(sortedRooms(house)) do
			table.insert(parts, entry.Id .. "=" .. (labels[entry.Id] or ""))
		end
		local key = table.concat(parts, "|")
		if key == roomChipsKey then
			return
		end
		roomChipsKey = key
		for _, child in ipairs(roomChips:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if locked then
			UIUtil.Create("TextLabel", {
				Name = "Lead",
				Size = UDim2.fromOffset(0, 30),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Text = kind == "Wallpaper" and Locale.T("🎨 Walls of this room:") or Locale.T("🟫 Floor of this room:"),
				TextColor3 = C.Ink,
				TextSize = 13,
				LayoutOrder = 0,
				ZIndex = 34,
				Parent = roomChips,
			})
		end
		local height = Interface.IsTouch() and 32 or 28
		local selectedChip: GuiObject? = nil
		for order, entry in ipairs(sortedRooms(house)) do
			if not locked or entry.Id == roomId then
				local selected = entry.Id == roomId
				local chip = UIUtil.PillButton({
					Name = entry.Id,
					Text = labels[entry.Id] or entry.Id,
					Color = selected and C.PinkDeep or WHITE,
					TextColor3 = selected and WHITE or C.Ink,
					Height = height,
					TextSize = 13,
					LayoutOrder = order,
					ZIndex = 34,
					StrokeColor = C.Pink,
					Parent = roomChips,
				})
				if selected then
					selectedChip = chip
				end
				local chosenId = entry.Id
				chip.Activated:Connect(function()
					if locked or chosenId == chosenRoomId then
						UIUtil.Pop(chip, 1.06, 0.2)
						return
					end
					chosenRoomId = chosenId
					SoundManager.Play("Click", 1.1)
					refresh()
				end)
			end
		end
		-- La pièce choisie reste visible dans la rangée (défilement, une fois
		-- les pastilles placées par le UIListLayout)
		task.delay(0.1, function()
			local chip = selectedChip
			if not chip or not chip.Parent then
				return
			end
			-- (positions absolues = px d'écran : ramenées en px de maquette)
			local k = chip.AbsoluteSize.Y / height
			if k <= 0 then
				return
			end
			local window = roomChips.AbsoluteWindowSize.X / k
			local left = (chip.AbsolutePosition.X - roomChips.AbsolutePosition.X) / k + roomChips.CanvasPosition.X
			local right = left + chip.AbsoluteSize.X / k
			local canvasX = roomChips.CanvasPosition.X
			if right > canvasX + window - 8 then
				canvasX = right - window + 16
			elseif left < canvasX + 8 then
				canvasX = math.max(0, left - 16)
			end
			roomChips.CanvasPosition = Vector2.new(canvasX, 0)
		end)
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
			syncFavoriteRoom(house)
			local room = currentRoom(house)
			for _, card in ipairs(itemCards) do
				if card.Cell.Visible then
					local item = card.Item
					local owned = HouseCommon.Owned(house, item.Id)
					local maxed = HouseCommon.IsMaxed(item, owned)
					local price = HouseCommon.Price(item, owned)
					local affordable = dopamine >= price
					local favorite = room ~= nil and HouseCommon.IsFavorite(room, item)
					card.Owned.Visible = owned > 0
					if owned > 0 then
						local free = handlers.GetAvailable(item.Id)
						setChipText(card.Owned, free > 0 and string.format("x%d • 📦%d", owned, free) or ("x" .. owned))
					end
					card.New.Visible = owned == 0 and affordable
					card.Fav.Visible = favorite
					if favorite then
						setText(card.Comfort, Locale.T("✨ +%s comfort", formatComfort(HouseCommon.PlacedComfort(room, item))), C.Lilac:Lerp(C.Ink, 0.3))
					else
						setText(card.Comfort, Locale.T("❤️ +%d comfort", item.Comfort), C.PinkDeep)
					end
					if maxed then
						paintButton(card.Button, Locale.T("MAX ✓"), Theme.Colors.ButtonBottom, true, Theme.Colors.Text)
					else
						paintButton(card.Button, "💧 " .. NumberFormatter.Format(price), BUY_COLOR, affordable, Theme.Colors.TextDark)
					end
					if owned == 0 and affordable then
						card.Stroke.Color = C.Butter:Lerp(C.PinkDeep, 0.2)
						card.Stroke.Thickness = 2.5
					elseif favorite then
						card.Stroke.Color = C.Lilac
						card.Stroke.Thickness = 2
					else
						card.Stroke.Color = SOFT_STROKE
						card.Stroke.Thickness = 1.5
					end
				end
			end
		elseif section == "Wallpapers" or section == "Floors" then
			refreshRoomBar(house)
			local room = targetRoom(house)
			for _, card in ipairs(styleCards) do
				local isWallpaper = card.Kind == "Wallpaper"
				if (section == "Wallpapers") == isWallpaper then
					local owned = isWallpaper and house.OwnedWallpapers or house.OwnedFloors
					local equippedId = room and (isWallpaper and room.Wallpaper or room.Floor) or nil
					local equipped = equippedId == card.Style.Id
					local isOwned = owned[card.Style.Id] == true or card.Style.Cost <= 0
					card.Check.Visible = equipped
					if equipped then
						paintButton(card.Button, Locale.T("✔ Applied"), Theme.Colors.ButtonBottom, true, Theme.Colors.Text)
						card.Stroke.Color = Theme.Colors.Green
						card.Stroke.Thickness = 3
					elseif isOwned then
						paintButton(card.Button, Locale.T("Apply"), Theme.Colors.Blue, true, WHITE)
						card.Stroke.Color = SOFT_STROKE
						card.Stroke.Thickness = 1.5
					else
						local affordable = dopamine >= card.Style.Cost
						paintButton(card.Button, "💧 " .. NumberFormatter.Format(card.Style.Cost), BUY_COLOR, affordable, Theme.Colors.TextDark)
						card.Stroke.Color = SOFT_STROKE
						card.Stroke.Thickness = 1.5
					end
				end
			end
		elseif section == "Rooms" then
			local size = HouseCommon.GetSize(house)
			local count = #house.Rooms
			local full = count >= size.MaxRooms
			local price = HouseCommon.RoomCost(house)
			local affordable = dopamine >= price
			setText(roomsCounter, Locale.T("%s %s  •  %d/%d rooms", size.Icon, HouseCommon.Name(size), count, size.MaxRooms))
			if full then
				setText(roomsNext, Locale.T("🏠 Full house! Move to a bigger one 🏡"), Theme.Colors.Orange)
			else
				setText(roomsNext, Locale.T("Next room: %s", "💧 " .. NumberFormatter.Format(price)), C.PinkDeep)
			end
			local perType: { [string]: number } = {}
			for _, room in ipairs(house.Rooms) do
				perType[room.Type] = (perType[room.Type] or 0) + 1
			end
			for _, card in ipairs(roomCards) do
				local have = perType[card.Type.Id] or 0
				card.Count.Visible = have > 0
				if have > 0 then
					setChipText(card.Count, "x" .. have)
				end
				if full then
					paintButton(card.Button, Locale.T("🏡 Bigger house"), Theme.Colors.Blue, true, WHITE)
				else
					paintButton(card.Button, "💧 " .. NumberFormatter.Format(price), BUY_COLOR, affordable, Theme.Colors.TextDark)
				end
				card.Stroke.Color = have > 0 and C.Lilac or SOFT_STROKE
				card.Stroke.Thickness = have > 0 and 2 or 1.5
			end
		elseif section == "Sizes" then
			local roomCount = #house.Rooms
			for _, row in ipairs(sizeRows) do
				local size = row.Size
				local current = house.Size == size.Id
				local isOwned = house.OwnedSizes[size.Id] == true or size.Cost <= 0
				paintCells(row, house, current)
				if current then
					paintButton(row.Button, Locale.T("✔ Home"), Theme.Colors.ButtonBottom, true, Theme.Colors.Text)
					setText(row.Status, Locale.T("🏠 Home • %d/%d rooms", roomCount, size.MaxRooms), C.PinkDeep)
					row.Stroke.Color = Theme.Colors.Green
					row.Stroke.Thickness = 3
				elseif isOwned then
					local tooSmall = roomCount > size.MaxRooms
					paintButton(row.Button, Locale.T("Move in"), Theme.Colors.Blue, not tooSmall, WHITE)
					if tooSmall then
						setText(row.Status, Locale.T("⚠️ Too many rooms (max %d)", size.MaxRooms), Theme.Colors.Orange)
					else
						setText(row.Status, Locale.T("✔ Owned"), C.PinkDeep)
					end
					row.Stroke.Color = SOFT_STROKE
					row.Stroke.Thickness = 1.5
				else
					local affordable = dopamine >= size.Cost
					paintButton(row.Button, "💧 " .. NumberFormatter.Format(size.Cost), BUY_COLOR, affordable, Theme.Colors.TextDark)
					setText(row.Status, affordable and Locale.T("You can afford it!") or Locale.T("Not enough Dopamine yet"), C.PinkDeep)
					row.Stroke.Color = SOFT_STROKE
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
		Rooms = roomsList,
		Sizes = sizesList,
	}

	local function showSection(name: string)
		local target = SECTION_ALIASES[name] or name
		if not sections[target] then
			target = "Items"
		end
		local changed = target ~= section
		section = target
		for id, frame in pairs(sections) do
			frame.Visible = id == target
		end
		categoryRow.Visible = target == "Items"
		roomBar.Visible = target == "Wallpapers" or target == "Floors"
		selectedTab = target
		layoutTabs(changed)
		-- Changer d'onglet arrête l'essai en cours
		if stickyPreview or hoverPreview then
			endPreviews()
		end
		buildSection(target)
		relayoutGrids()
		refresh()
	end

	closeButton.Activated:Connect(function()
		shop.Close()
	end)

	layoutTabs(false)

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
			layoutTabs(false)
			relayoutGrids()
		end,
	}
	return shop
end

return HouseShop
