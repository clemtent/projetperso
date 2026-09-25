--[[
	HousePicker (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HousePicker

	Petites fenêtres de choix de la maison (par-dessus la fenêtre "🏠 Ma
	maison", fond assombri, clic à côté = fermer) :
	  - ShowRoomTypes : les 12 types de pièces en cartes (icône, nom,
	    préférés : catégories + vignettes d'objets, "✓ Actuel") -> achat
	    d'une pièce ou changement de type ;
	  - ShowRooms : les pièces de la maison (petite pièce dessinée, nom,
	    place "12/36", ✨ si l'objet y est préféré, "Pleine") -> "Envoyer
	    dans une autre pièce" ;
	  - ShowMenu : quelques gros boutons (menu "⋯" d'une pièce).
	Zones tactiles >= 44 px ; la grille s'adapte au téléphone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local SoundManager = require(Client.SoundManager)
local Locale = require(ReplicatedStorage.Shared.Locale)
local HouseCommon = require(script.Parent.HouseCommon)
local HouseArt = require(script.Parent.HouseArt)
local HouseMiniRoom = require(script.Parent.HouseMiniRoom)

type HouseData = HouseCommon.HouseData
type Item = HouseCommon.Item

local HousePicker = {}

local C = HouseCommon.Colors
local WHITE = Color3.new(1, 1, 1)

export type MenuButton = { Text: string, Color: Color3, OnClick: () -> () }

export type Picker = {
	Frame: Frame,
	ShowRoomTypes: (options: {
		Title: string,
		Subtitle: string,
		Current: string?,
		OnPick: (typeId: string) -> (),
	}) -> (),
	ShowRooms: (options: {
		Title: string,
		Subtitle: string,
		House: HouseData,
		ExcludeId: string?,
		Item: Item?,
		Counts: { [string]: number }?,
		OnPick: (roomId: string) -> (),
	}) -> (),
	ShowMenu: (options: { Title: string, Subtitle: string, Buttons: { MenuButton } }) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
}

function HousePicker.new(parent: Frame): Picker
	local picker: Picker
	local closeToken = 0

	local overlay = UIUtil.Create("Frame", {
		Name = "Picker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 60,
		Parent = parent,
	})
	local dim = UIUtil.Create("TextButton", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 20, 50),
		BackgroundTransparency = 0.55,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 60,
		Parent = overlay,
	})
	UIUtil.Corner(dim, 20)
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, -24, 1, -16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		ZIndex = 61,
		Parent = overlay,
	})
	UIUtil.Corner(card, 22)
	UIUtil.Stroke(card, C.Pink, 2.5, 0.1)
	UIUtil.Gradient(card, ColorSequence.new(WHITE, C.PinkMist), 90)
	local sizeLimit = UIUtil.Create("UISizeConstraint", { MaxSize = Vector2.new(820, 480), Parent = card })
	local cardScale = UIUtil.Create("UIScale", { Parent = card })
	local title = UIUtil.Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -80, 0, 30),
		Position = UDim2.fromOffset(18, 10),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = C.Ink,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 62,
		Parent = card,
	})
	local subtitle = UIUtil.Create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, -80, 0, 20),
		Position = UDim2.fromOffset(18, 40),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 62,
		Parent = card,
	})
	local closeButton = UIUtil.Create("TextButton", {
		Name = "PickerClose",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		BackgroundColor3 = C.PinkSoft,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "✕",
		TextColor3 = C.Ink,
		TextSize = 20,
		ZIndex = 63,
		Parent = card,
	})
	UIUtil.Corner(closeButton, UDim.new(1, 0))
	UIUtil.Stroke(closeButton, C.Pink, 1.5, 0.3)
	UIUtil.AnimateButton(closeButton, 1.08, 0.9)
	local list = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, -24, 1, -78),
		Position = UDim2.fromOffset(12, 68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Pink,
		ZIndex = 62,
		Parent = card,
	})
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 6),
		Parent = list,
	})
	local grid = UIUtil.Create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(10, 10),
		CellSize = UDim2.new(0.25, -10, 0, 120),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = list,
	})

	local function clearList()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function close()
		if not overlay.Visible then
			return
		end
		closeToken += 1
		local token = closeToken
		UIUtil.Tween(cardScale, 0.14, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.14, function()
			if token == closeToken then
				overlay.Visible = false
				clearList()
			end
		end)
	end

	-- rows : nombre de rangées (la fenêtre prend juste la hauteur utile)
	local function open(titleText: string, subtitleText: string, columns: number, cellHeight: number, rows: number, maxWidth: number?)
		closeToken += 1
		local height = 84 + rows * (cellHeight + 10) + 6
		card.Size = UDim2.new(1, -24, 0, height)
		clearList()
		title.Text = titleText
		subtitle.Text = subtitleText
		local phone = Interface.IsPhone()
		sizeLimit.MaxSize = Vector2.new(maxWidth or (phone and 900 or 820), 480)
		-- (plus haute que la place : elle défile, sans dépasser de la fenêtre)
		task.defer(function()
			local factor = Interface.Scale > 0 and Interface.Scale or 1
			local space = overlay.AbsoluteSize.Y / factor
			if space > 0 and height > space - 16 then
				card.Size = UDim2.new(1, -24, 1, -16)
			end
		end)
		grid.CellSize = UDim2.new(1 / columns, -10, 0, cellHeight)
		overlay.Visible = true
		cardScale.Scale = 0.85
		UIUtil.Tween(cardScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		list.CanvasPosition = Vector2.zero
		SoundManager.Play("Open", 1.4)
	end

	-- Carte cliquable de la grille
	local function cell(order: number, color: Color3, enabled: boolean, onClick: () -> ()): TextButton
		local button = UIUtil.Create("TextButton", {
			Name = "Cell" .. order,
			BackgroundColor3 = color,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = order,
			ZIndex = 63,
			Parent = list,
		})
		UIUtil.Corner(button, 16)
		UIUtil.Stroke(button, enabled and C.Pink or Color3.fromRGB(200, 190, 200), 2, enabled and 0.25 or 0.4)
		UIUtil.Gradient(button, ColorSequence.new(WHITE, Color3.fromRGB(232, 232, 236)), 90)
		if enabled then
			UIUtil.AnimateButton(button, 1.04, 0.95)
		else
			button.BackgroundTransparency = 0.35
		end
		button.Activated:Connect(function()
			if not enabled then
				SoundManager.Play("Error", 0.8)
				UIUtil.Shake(button)
				return
			end
			SoundManager.Play("Click", 1.2)
			close()
			onClick()
		end)
		return button
	end

	local function text(parentObject: Instance, value: string, position: UDim2, size: UDim2, fontSize: number, color: Color3?, bold: boolean?): TextLabel
		return UIUtil.Create("TextLabel", {
			Size = size,
			Position = position,
			BackgroundTransparency = 1,
			Font = bold and Theme.Fonts.Title or Theme.Fonts.Body,
			Text = value,
			TextColor3 = color or C.Ink,
			TextSize = fontSize,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 65,
			Parent = parentObject,
		})
	end

	dim.Activated:Connect(close)
	closeButton.Activated:Connect(close)

	picker = {
		Frame = overlay,
		ShowRoomTypes = function(options)
			local phone = Interface.IsPhone()
			local columns = phone and 6 or 4
			local cellHeight = phone and 116 or 124
			local types = HouseCommon.Config.RoomTypes
			open(options.Title, options.Subtitle, columns, cellHeight, math.ceil(#types / columns))
			for index, roomType in ipairs(types) do
				local wallpaper = HouseCommon.WallpapersById[roomType.Wallpaper]
				local tint = C.PinkMist
				if wallpaper then
					-- (papiers peints sombres : fond bien éclairci, le texte reste lisible)
					local a = wallpaper.A
					local luminance = 0.3 * a.R + 0.59 * a.G + 0.11 * a.B
					tint = a:Lerp(WHITE, luminance < 0.6 and 0.72 or 0.35)
				end
				local isCurrent = options.Current == roomType.Id
				local button = cell(index, tint, not isCurrent, function()
					options.OnPick(roomType.Id)
				end)
				text(button, roomType.Icon, UDim2.fromOffset(0, 6), UDim2.new(1, 0, 0, 36), 30)
				text(button, HouseCommon.Name(roomType), UDim2.fromOffset(4, 44), UDim2.new(1, -8, 0, 20), phone and 14 or 16, C.Ink, true)
				-- Préférés : icônes des catégories + vignettes de quelques objets
				local row = UIUtil.Create("Frame", {
					Name = "Favorites",
					Size = UDim2.new(1, -8, 0, 34),
					Position = UDim2.new(0, 4, 1, -44),
					BackgroundTransparency = 1,
					ZIndex = 64,
					Parent = button,
				})
				UIUtil.Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 3),
					Parent = row,
				})
				local maxIcons = phone and 3 or 4
				local count = 0
				local function bubble(order: number): Frame
					local holder = UIUtil.Create("Frame", {
						Name = "Fav" .. order,
						Size = UDim2.fromOffset(30, 30),
						BackgroundColor3 = WHITE,
						LayoutOrder = order,
						ZIndex = 65,
						Parent = row,
					})
					UIUtil.Corner(holder, UDim.new(1, 0))
					UIUtil.Stroke(holder, C.Pink, 1, 0.5)
					return holder
				end
				for _, categoryId in ipairs(roomType.Categories) do
					if count >= maxIcons then
						break
					end
					local category = HouseCommon.CategoriesById[categoryId]
					if category then
						count += 1
						local holder = bubble(count)
						holder.BackgroundColor3 = HouseCommon.CategoryTint(categoryId)
						text(holder, category.Icon, UDim2.new(), UDim2.fromScale(1, 1), 18)
					end
				end
				for _, itemId in ipairs(roomType.Items) do
					if count >= maxIcons then
						break
					end
					local item = HouseCommon.ItemsById[itemId]
					if item then
						count += 1
						local holder = bubble(count)
						holder.BackgroundColor3 = HouseCommon.CategoryTint(item.Category)
						HouseArt.Thumbnail(holder, item, 30, 66)
					end
				end
				if isCurrent then
					local badge = UIUtil.Chip({
						Name = "Current",
						Text = Locale.T("✓ Current"),
						Color = Theme.Colors.Green,
						TextColor3 = WHITE,
						Height = 22,
						TextSize = 13,
						ZIndex = 66,
						Parent = button,
					})
					badge.AnchorPoint = Vector2.new(1, 0)
					badge.Position = UDim2.new(1, -6, 0, 6)
				end
			end
		end,
		ShowRooms = function(options)
			local phone = Interface.IsPhone()
			local columns = phone and 4 or 3
			local cellHeight = phone and 128 or 150
			local house = options.House
			open(options.Title, options.Subtitle, columns, cellHeight, math.max(1, math.ceil((#house.Rooms - 1) / columns)))
			local size = HouseCommon.GetSize(house)
			local rooms = table.clone(house.Rooms)
			table.sort(rooms, function(a, b)
				return a.Slot < b.Slot
			end)
			local order = 0
			for _, room in ipairs(rooms) do
				if room.Id ~= options.ExcludeId then
					order += 1
					local roomType = HouseCommon.GetRoomType(room)
					local used = (options.Counts and options.Counts[room.Id]) or #room.Placed
					local full = used >= size.RoomItems
					local button = cell(order, WHITE, not full, function()
						options.OnPick(room.Id)
					end)
					-- Petite pièce dessinée
					local previewW = phone and 150 or 190
					local previewH = math.floor(previewW * 0.5)
					local holder = UIUtil.Create("Frame", {
						Name = "Preview",
						Size = UDim2.fromOffset(previewW, previewH),
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 6),
						BackgroundTransparency = 1,
						ZIndex = 64,
						Parent = button,
					})
					local previewScale = UIUtil.Create("UIScale", { Parent = holder })
					local mini = HouseMiniRoom.new(holder, previewW, previewH)
					mini.Set(room, size)
					UIUtil.Corner(mini.Frame, 10)
					-- (la case de la grille peut être plus étroite que l'aperçu)
					local function fitPreview()
						local width = button.AbsoluteSize.X
						local ratio = Interface.Scale > 0 and width / Interface.Scale or width
						previewScale.Scale = math.clamp((ratio - 12) / previewW, 0.4, 1)
					end
					button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPreview)
					fitPreview()
					local line = string.format("%s %s", roomType.Icon, HouseCommon.Name(roomType))
					text(button, line, UDim2.new(0, 4, 1, -44), UDim2.new(1, -8, 0, 20), phone and 14 or 16, C.Ink, true)
					local info = full and Locale.T("🚫 Full") or string.format("📦 %d/%d", used, size.RoomItems)
					local item = options.Item
					if not full and item and HouseCommon.IsFavorite(room, item) then
						info ..= "  " .. Locale.T("✨ Favourite")
					end
					text(button, info, UDim2.new(0, 4, 1, -24), UDim2.new(1, -8, 0, 18), 13, full and Theme.Colors.Red or Theme.Colors.TextDim)
				end
			end
		end,
		ShowMenu = function(options)
			local count = #options.Buttons
			local columns = math.max(1, math.min(count, 3))
			local cellHeight = Interface.IsTouch() and 64 or 56
			local rows = math.ceil(count / columns)
			open(options.Title, options.Subtitle, columns, cellHeight, rows, 560)
			for index, info in ipairs(options.Buttons) do
				local button = cell(index, info.Color, true, info.OnClick)
				text(button, info.Text, UDim2.fromOffset(8, 0), UDim2.new(1, -16, 1, 0), 18, C.Ink, true)
			end
		end,
		Close = close,
		IsOpen = function(): boolean
			return overlay.Visible
		end,
	}
	return picker
end

return HousePicker
