--[[
	House (ModuleScript) — "🏠 Ma maison"
	Emplacement : ReplicatedStorage > Client > Components > Panels > House

	Grande fenêtre (presque plein écran, s'adapte au téléphone / à la
	tablette) avec deux vues :
	  - VUE D'ENSEMBLE (à l'ouverture, House/HouseOverview) : l'immeuble
	    (studio, appart, loft, manoir) en coupe, chaque pièce dessinée en
	    petit ; clic = zoom dans la pièce ; case vide = "➕ Nouvelle pièce"
	    (choix du type, House/HousePicker) ; "↔ Ranger" = glisser les
	    pièces pour les échanger, "⋯" = ouvrir / changer de type ;
	  - VUE PIÈCE : la pièce kawaii (House/HouseRoom) de la pièce choisie,
	    bouton "⬅ Maison" + onglets des pièces dans le bandeau, type de la
	    pièce (cliquable = changer de type), confort de la pièce ✨ ;
	    mode édition (House/HouseEditor) : glisser, barre d'outils,
	    annuler / rétablir, aimant 🧲, envoyer dans une autre pièce,
	    dupliquer ; inventaire en bas (toucher un objet rangé = le poser ;
	    ✨ = préféré de cette pièce).
	Bandeau : immeuble et nombre de pièces, confort ❤️ + bonus "+X % de
	Dopamine" (en direct pendant l'édition), boutons "↔ Ranger" /
	"✏️ Modifier" et "🛍️ Boutique" (badge) : rien ne se chevauche sur
	téléphone, tablette ou PC. Tiroir de la boutique (House/HouseShop) à
	droite : la maison se décale pour rester visible.
	Textes en anglais (Locale.T), français dans Lang/FR_HouseUI et
	Lang/FR_HouseRooms.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local NeedDopamine = require(script.Parent.Parent.NeedDopamine)
local HouseFolder = script.Parent.Parent:WaitForChild("House")
local HouseCommon = require(HouseFolder:WaitForChild("HouseCommon"))
local HouseRoom = require(HouseFolder:WaitForChild("HouseRoom"))
local HouseEditor = require(HouseFolder:WaitForChild("HouseEditor"))
local HouseShop = require(HouseFolder:WaitForChild("HouseShop"))
local HouseArt = require(HouseFolder:WaitForChild("HouseArt"))
local HouseOverview = require(HouseFolder:WaitForChild("HouseOverview"))
local HousePicker = require(HouseFolder:WaitForChild("HousePicker"))
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

type HouseData = HouseCommon.HouseData
type Placed = HouseCommon.Placed

-- Title / Subtitle en anglais : traduits par PanelManager
local House = {
	Title = "🏠 My House",
	Subtitle = "Decorate your cozy room: comfort boosts ALL your gains",
	Color = HouseCommon.Colors.Pink,
	Size = Vector2.new(1180, 690),
}

local C = HouseCommon.Colors
local WHITE = Color3.new(1, 1, 1)
local TOP_BAR = 46
local PENDING_PLACE_TIME = 6 -- (s) un objet acheté attend l'état du serveur pour être posé
local FADE_TIME = 0.28

local content: Frame
local main: Frame
local left: Frame
local overviewHolder: Frame
local stage: Frame
local stageFade: Frame
local tray: Frame
local trayList: ScrollingFrame
local trayEmpty: TextLabel
local emptyHint: Frame
local editHint: Frame
local leftGroup: Frame
local rightGroup: Frame
local backButton: TextButton
local tabsScroller: ScrollingFrame
local houseChip: Frame
local comfortPill: Frame
local comfortLabel: TextLabel
local bonusLabel: TextLabel
local savedChip: Frame
local roomBar: Frame
local typeButton: TextButton
local statsChip: Frame
local dock: Frame
local undoButton: TextButton
local redoButton: TextButton
local snapButton: TextButton
local arrangeButton: TextButton
local editButton: TextButton
local shopButton: TextButton
local shopBadge: TextLabel
local previewChip: Frame

local room: HouseRoom.Room? = nil
local editor: HouseEditor.Editor? = nil
local shop: HouseShop.Shop? = nil
local overview: HouseOverview.Overview? = nil
local picker: HousePicker.Picker? = nil

local latestHouse: HouseData = HouseCommon.GetHouse(nil)
local isOpen = false
local view = "overview" -- "overview" | "room"
local currentRoomId: string? = nil
local lastRoomId: string? = nil
local forceSync = false
local renderConnection: RBXScriptConnection? = nil
local previewWallpaper: string? = nil
local previewFloor: string? = nil
local pendingPlace: { { Id: string, Until: number } } = {}
local pendingPulse: { [string]: number } = {} -- pièces à faire "rebondir" dès qu'elles existent
local pendingSlotPulse: { [number]: number } = {}
local lastComfort: number? = nil
local traySignature = ""
local tabsSignature = ""
local tabsContentWidth = 300
local savedToken = 0
local refreshClock = 0
local closeWatcher = 0
local hasSelection = false
local transitioning = false

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function notify(text: string, color: Color3?, title: string?)
	Notifications.Toast(text, color or C.Pink, 3.2, title)
end

local function setChip(chip: Frame, text: string)
	local label = chip:FindFirstChild("Label") :: TextLabel?
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function isPhone(): boolean
	return Interface.IsPhone()
end

local function isEditing(): boolean
	return editor ~= nil and (editor :: HouseEditor.Editor).IsEditing()
end

local function isShopOpen(): boolean
	return shop ~= nil and (shop :: HouseShop.Shop).IsOpen()
end

local function isArranging(): boolean
	return overview ~= nil and (overview :: HouseOverview.Overview).IsArranging()
end

-- Largeur de la zone de contenu (px de maquette)
local function contentWidth(): number
	local size = House.GetSize()
	return size.X - 40
end

local function drawerWidth(): number
	local width = contentWidth()
	if isPhone() then
		return math.floor(math.clamp(width * 0.56, 300, 460))
	end
	return math.floor(math.clamp(width * 0.36, 360, 430))
end

local function overrides(): HouseCommon.Overrides?
	local currentEditor = editor
	return currentEditor and currentEditor.Overrides() or nil
end

local function sortedRooms(): { HouseCommon.Room }
	local rooms = table.clone(latestHouse.Rooms)
	table.sort(rooms, function(a, b)
		return a.Slot < b.Slot
	end)
	return rooms
end

local function currentRoom(): HouseCommon.Room?
	return HouseCommon.GetRoom(latestHouse, currentRoomId)
end

local function roomLabel(roomData: HouseCommon.Room): string
	local roomType = HouseCommon.GetRoomType(roomData)
	return roomType.Icon .. " " .. HouseCommon.Name(roomType)
end

local function currentLayout(): { Placed }
	local currentEditor = editor
	if currentEditor and currentRoomId then
		return currentEditor.GetLayout()
	end
	local roomData = currentRoom()
	return roomData and roomData.Placed or {}
end

----------------------------------------------------------------------
-- Bandeau du haut
----------------------------------------------------------------------

local function refreshHeader()
	local size = HouseCommon.GetSize(latestHouse)
	local roomCount = #latestHouse.Rooms
	if isPhone() then
		setChip(houseChip, string.format("%s %d/%d", size.Icon, roomCount, size.MaxRooms))
	else
		setChip(houseChip, string.format("%s %s  •  %s", size.Icon, HouseCommon.Name(size), Locale.T("%d/%d rooms", roomCount, size.MaxRooms)))
	end
	local comfort = HouseCommon.Comfort(latestHouse, overrides())
	local percent = HouseCommon.BonusPercent(comfort)
	if Interface.Device == "Desktop" then
		comfortLabel.Text = Locale.T("❤️ %d comfort", comfort)
		bonusLabel.Text = Locale.T("+%s%% Dopamine", HouseCommon.FormatPercent(percent))
	else
		comfortLabel.Text = string.format("❤️ %d", comfort)
		bonusLabel.Text = Locale.T("+%s%%", HouseCommon.FormatPercent(percent))
	end
	if lastComfort ~= nil and comfort ~= lastComfort then
		UIUtil.Pop(comfortPill, comfort > (lastComfort :: number) and 1.15 or 0.9, 0.4)
	end
	lastComfort = comfort

	-- Pièce ouverte : type (cliquable), confort de la pièce, harmonie, place
	local roomData = currentRoom()
	if roomData then
		local layout = currentLayout()
		local roomComfort = HouseCommon.RoomComfort(latestHouse, roomData, layout)
		local favorites = 0
		for _, entry in ipairs(layout) do
			local item = HouseCommon.ItemsById[entry.I]
			if item and HouseCommon.IsFavorite(roomData, item) then
				favorites += 1
			end
		end
		local typeText = roomLabel(roomData) .. "  ▾"
		if typeButton.Text ~= typeText then
			typeButton.Text = typeText
		end
		local stats = string.format("❤️ %s", HouseCommon.FormatPercent(roomComfort))
		if favorites > 0 then
			stats ..= string.format("   ✨ %d", favorites)
		end
		stats ..= string.format("   📦 %d/%d", #layout, size.RoomItems)
		setChip(statsChip, stats)
	end
end

local function refreshShopBadge()
	local data = ClientState.Data
	local count = #HouseCommon.AffordableNew(data, HouseCommon.Dopamine())
	UIUtil.SetBadge(shopBadge, count)
end

local function showSaved(status: string)
	savedToken += 1
	local token = savedToken
	local label = savedChip:FindFirstChild("Label") :: TextLabel?
	if status == "idle" then
		savedChip.Visible = false
		return
	end
	savedChip.Visible = view == "room"
	if status == "dirty" then
		setChip(savedChip, Locale.T("✏️ Changes…"))
		savedChip.BackgroundColor3 = C.Cream
	elseif status == "saving" then
		setChip(savedChip, Locale.T("💾 Saving…"))
		savedChip.BackgroundColor3 = C.LilacSoft
	elseif status == "saved" then
		setChip(savedChip, Locale.T("Saved ✓"))
		savedChip.BackgroundColor3 = C.MintSoft
		UIUtil.Pop(savedChip, 1.2, 0.35)
		task.delay(2.2, function()
			if token == savedToken then
				savedChip.Visible = false
			end
		end)
	elseif status == "error" then
		setChip(savedChip, Locale.T("⚠️ Not saved"))
		savedChip.BackgroundColor3 = Color3.fromRGB(255, 214, 214)
	end
	if label then
		label.TextColor3 = C.Ink
	end
end

-- Largeur d'un texte (px de maquette)
local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(2000, 100))
	end)
	if ok and typeof(bounds) == "Vector2" then
		return bounds.X
	end
	return #text * size * 0.55
end

-- Largeur d'une pastille-bouton du bandeau
local function pillWidth(button: TextButton): number
	local padding = button:FindFirstChildOfClass("UIPadding")
	local pads = padding and (padding.PaddingLeft.Offset + padding.PaddingRight.Offset) or 32
	return textWidth(button.Text, button.TextSize, button.Font) + pads + 4
end

-- Largeurs du bandeau (px de maquette) : rien ne se chevauche
local function layoutHeader()
	local inRoom = view == "room"
	arrangeButton.Visible = not inRoom
	editButton.Visible = inRoom
	backButton.Visible = inRoom
	tabsScroller.Visible = inRoom
	houseChip.Visible = not inRoom
	local buttonsWidth = 0
	local gap = 8
	for _, button in ipairs({ arrangeButton, editButton, shopButton }) do
		if button.Visible then
			buttonsWidth += pillWidth(button) + gap
		end
	end
	buttonsWidth = math.max(buttonsWidth + 4, 200)
	rightGroup.Size = UDim2.new(0, buttonsWidth, 1, 0)
	local leftWidth = contentWidth() - buttonsWidth - 10
	leftGroup.Size = UDim2.new(0, leftWidth, 1, 0)
	local backText = isPhone() and "⬅" or Locale.T("⬅ House")
	if backButton.Text ~= backText then
		backButton.Text = backText
	end
	if inRoom then
		local backWidth = pillWidth(backButton)
		local comfortWidth = 28 + 10 + textWidth(comfortLabel.Text, comfortLabel.TextSize, comfortLabel.Font)
			+ textWidth(bonusLabel.Text, bonusLabel.TextSize, bonusLabel.Font)
		local tabsWidth = leftWidth - backWidth - comfortWidth - gap * 2 - 8
		comfortPill.Visible = tabsWidth >= 140
		if not comfortPill.Visible then
			tabsWidth = leftWidth - backWidth - gap - 4
		end
		tabsScroller.Size = UDim2.new(0, math.clamp(tabsContentWidth, 80, math.max(80, tabsWidth)), 1, 0)
	else
		comfortPill.Visible = true
	end
end

-- Dock d'édition : à droite de la barre de la pièce, ou dessous si la
-- place manque (téléphone, boutique ouverte)
local function layoutStageChips()
	local factor = Interface.Scale > 0 and Interface.Scale or 1
	local stageWidth = stage.AbsoluteSize.X / factor
	if stageWidth <= 0 then
		return
	end
	local statsLabel = statsChip:FindFirstChild("Label") :: TextLabel?
	local barWidth = pillWidth(typeButton) + 6 + (statsLabel and textWidth(statsLabel.Text, statsLabel.TextSize, statsLabel.Font) + 26 or 120)
	if savedChip.Visible then
		barWidth += 130
	end
	local dockWidth = 12
	for _, button in ipairs({ undoButton, redoButton, snapButton }) do
		dockWidth += pillWidth(button) + 5
	end
	local rowHeight = (Interface.IsTouch() and Theme.TouchTarget or 34) + 8
	local below = 20 + barWidth + 10 + dockWidth > stageWidth
	dock.Position = UDim2.new(1, -10, 0, below and 8 + rowHeight or 8)
end

----------------------------------------------------------------------
-- Onglets des pièces (vue pièce)
----------------------------------------------------------------------

local openRoom: (roomId: string, instant: boolean?, after: (() -> ())?) -> ()

local function refreshTabs()
	local rooms = sortedRooms()
	local parts = { currentRoomId or "", isPhone() and "p" or "d" }
	for _, roomData in ipairs(rooms) do
		table.insert(parts, roomData.Id .. ":" .. roomData.Type)
	end
	local signatureText = table.concat(parts, ",")
	if signatureText == tabsSignature then
		return
	end
	tabsSignature = signatureText
	for _, child in ipairs(tabsScroller:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local height = Interface.IsTouch() and 40 or 34
	local currentButton: TextButton? = nil
	local total = 6
	for index, roomData in ipairs(rooms) do
		local roomType = HouseCommon.GetRoomType(roomData)
		local isCurrent = roomData.Id == currentRoomId
		local named = isCurrent and Interface.Device == "Desktop"
		local tab = UIUtil.Create("TextButton", {
			Name = "Tab_" .. roomData.Id,
			Size = UDim2.fromOffset(named and 0 or height + 4, height),
			AutomaticSize = named and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
			BackgroundColor3 = isCurrent and C.PinkDeep or WHITE,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = (isCurrent and Interface.Device == "Desktop") and roomLabel(roomData) or roomType.Icon,
			TextColor3 = isCurrent and WHITE or C.Ink,
			TextSize = named and 15 or 20,
			LayoutOrder = index,
			ZIndex = 7,
			Parent = tabsScroller,
		})
		UIUtil.Corner(tab, UDim.new(1, 0))
		UIUtil.Stroke(tab, isCurrent and WHITE or C.Pink, isCurrent and 2 or 1.5, isCurrent and 0.1 or 0.35)
		if named then
			UIUtil.Create("UIPadding", {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				Parent = tab,
			})
		end
		if isCurrent then
			UIUtil.Gradient(tab, ColorSequence.new(WHITE, Color3.fromRGB(226, 226, 226)), 90)
			currentButton = tab
		end
		UIUtil.AnimateButton(tab, 1.08, 0.92)
		total += (named and textWidth(tab.Text, tab.TextSize, tab.Font) + 28 or height + 4) + 5
		tab.Activated:Connect(function()
			if roomData.Id ~= currentRoomId then
				SoundManager.Play("Click", 1.2)
				openRoom(roomData.Id, true)
			end
		end)
	end
	tabsContentWidth = total
	task.defer(layoutHeader)
	-- L'onglet courant reste visible
	local current = currentButton
	if current then
		task.defer(function()
			local offset = current.AbsolutePosition.X - tabsScroller.AbsolutePosition.X + tabsScroller.CanvasPosition.X
			local visible = tabsScroller.AbsoluteSize.X
			if offset + current.AbsoluteSize.X > tabsScroller.CanvasPosition.X + visible or offset < tabsScroller.CanvasPosition.X then
				tabsScroller.CanvasPosition = Vector2.new(math.max(0, offset - visible / 2), 0)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Pièce : style (taille, papier peint, sol, aperçus)
----------------------------------------------------------------------

local function applyRoomStyle()
	local currentRoomView = room
	local roomData = currentRoom()
	if not currentRoomView or not roomData then
		return
	end
	local size = HouseCommon.GetSize(latestHouse)
	local wallpaper = (previewWallpaper and HouseCommon.WallpapersById[previewWallpaper]) or HouseCommon.GetRoomWallpaper(roomData)
	local floor = (previewFloor and HouseCommon.FloorsById[previewFloor]) or HouseCommon.GetRoomFloor(roomData)
	currentRoomView.SetStyle(size, wallpaper, floor)
	currentRoomView.SetExterior(size.Exterior)
	previewChip.Visible = view == "room" and (previewWallpaper ~= nil or previewFloor ~= nil)
end

----------------------------------------------------------------------
-- Inventaire (objets possédés pas encore posés)
----------------------------------------------------------------------

local function refreshTray()
	local currentEditor = editor
	if not currentEditor then
		return
	end
	local roomData = currentRoom()
	local entries = {}
	local parts = { currentRoomId or "" }
	for _, item in ipairs(HouseCommon.Config.Items) do
		local free = currentEditor.Available(item.Id)
		if free > 0 then
			local favorite = HouseCommon.IsFavorite(roomData, item)
			table.insert(entries, { Item = item, Free = free, Favorite = favorite, Order = #entries })
			table.insert(parts, item.Id .. "=" .. free)
		end
	end
	-- Les préférés de la pièce d'abord (bonus d'harmonie ✨)
	table.sort(entries, function(a, b)
		if a.Favorite ~= b.Favorite then
			return a.Favorite
		end
		return a.Order < b.Order
	end)
	local signatureText = table.concat(parts, ",") .. (isPhone() and "|p" or "")
	if signatureText == traySignature then
		return
	end
	traySignature = signatureText
	for _, child in ipairs(trayList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	trayEmpty.Visible = #entries == 0
	local tileSize = isPhone() and 52 or 58
	for index, entry in ipairs(entries) do
		local item = entry.Item
		local holder = UIUtil.Create("Frame", {
			Name = item.Id,
			Size = UDim2.fromOffset(tileSize + 6, tileSize + 8),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			ZIndex = 12,
			Parent = trayList,
		})
		local tile = UIUtil.Create("TextButton", {
			Name = "Tile",
			Size = UDim2.fromOffset(tileSize, tileSize),
			Position = UDim2.fromOffset(0, 6),
			BackgroundColor3 = HouseCommon.CategoryTint(item.Category),
			AutoButtonColor = false,
			Font = Theme.Fonts.Body,
			Text = HouseArt.Has(item.Id) and "" or item.Icon,
			TextSize = math.floor(tileSize * 0.6),
			ZIndex = 13,
			Parent = holder,
		})
		UIUtil.Corner(tile, 14)
		if HouseArt.Has(item.Id) then
			HouseArt.Thumbnail(tile, item, tileSize - 2, 1)
		end
		UIUtil.Stroke(tile, entry.Favorite and C.Butter:Lerp(C.Peach, 0.5) or C.Pink, entry.Favorite and 2.5 or 1.5, 0.2)
		UIUtil.AnimateButton(tile, 1.08, 0.9)
		local badge = UIUtil.Badge(tile, 20)
		badge.BackgroundColor3 = C.PinkDeep
		-- (un peu rentré : le badge et son contour restent dans la rangée qui découpe)
		badge.Position = UDim2.new(1, -5, 0, 6)
		badge.Text = "x" .. entry.Free
		badge.ZIndex = 20
		badge.Visible = true
		if entry.Favorite then
			UIUtil.Create("TextLabel", {
				Name = "Favorite",
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.fromOffset(2, 2),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Text = "✨",
				TextSize = 15,
				ZIndex = 20,
				Parent = tile,
			})
		end
		tile.Activated:Connect(function()
			local current = editor
			if current then
				current.Place(item.Id)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Mode édition, tiroir de la boutique, dock (annuler / aimant)
----------------------------------------------------------------------

local function refreshDock()
	local currentEditor = editor
	if not currentEditor then
		return
	end
	local canUndo, canRedo = currentEditor.CanUndo(), currentEditor.CanRedo()
	undoButton.BackgroundColor3 = canUndo and WHITE or Color3.fromRGB(236, 232, 238)
	undoButton.TextTransparency = canUndo and 0 or 0.55
	redoButton.BackgroundColor3 = canRedo and WHITE or Color3.fromRGB(236, 232, 238)
	redoButton.TextTransparency = canRedo and 0 or 0.55
	local snap = currentEditor.GetSnap()
	snapButton.BackgroundColor3 = snap and C.Mint or WHITE
	snapButton.TextColor3 = snap and WHITE or C.Ink
	local phone = isPhone()
	undoButton.Text = phone and "↩️" or Locale.T("↩️ Undo")
	redoButton.Text = phone and "↪️" or Locale.T("↪️ Redo")
	snapButton.Text = phone and "🧲" or (snap and Locale.T("🧲 Snap: on") or Locale.T("🧲 Snap: off"))
end

local function layoutLeft(animate: boolean)
	local shopOpen = isShopOpen()
	local editing = isEditing() and view == "room"
	local rightGap = shopOpen and (drawerWidth() + 10) or 0
	local target = UDim2.new(1, -rightGap, 1, 0)
	if animate then
		UIUtil.Tween(left, 0.3, { Size = target }, Enum.EasingStyle.Quint)
	else
		left.Size = target
	end
	local trayHeight = isPhone() and 70 or 82
	tray.Size = UDim2.new(1, 0, 0, trayHeight)
	tray.Visible = editing
	local stageTarget = UDim2.new(1, 0, 1, editing and -(trayHeight + 8) or 0)
	if animate then
		UIUtil.Tween(stage, 0.3, { Size = stageTarget }, Enum.EasingStyle.Quint)
	else
		stage.Size = stageTarget
	end
	task.defer(layoutStageChips)
	task.delay(0.32, layoutStageChips)
end

local function refreshEditUi()
	local inRoom = view == "room"
	local editing = isEditing()
	editButton.Text = editing and Locale.T("✅ Done") or Locale.T("✏️ Edit")
	editButton:SetAttribute("BaseColor", editing and Theme.Colors.Green or C.Lilac)
	editButton.BackgroundColor3 = editing and Theme.Colors.Green or C.Lilac
	local arranging = isArranging()
	arrangeButton.Text = arranging and Locale.T("✅ Done") or Locale.T("↔️ Arrange")
	arrangeButton:SetAttribute("BaseColor", arranging and Theme.Colors.Green or C.Lilac)
	arrangeButton.BackgroundColor3 = arranging and Theme.Colors.Green or C.Lilac
	local empty = #currentLayout() == 0
	local shopOpen = isShopOpen()
	emptyHint.Visible = inRoom and empty and not editing and not shopOpen
	editHint.Visible = inRoom and editing and not hasSelection and not shopOpen
	dock.Visible = inRoom and editing
	refreshDock()
	task.defer(layoutHeader)
	task.defer(layoutStageChips)
end

local function setEditing(value: boolean)
	local currentEditor = editor
	if not currentEditor or currentEditor.IsEditing() == value then
		return
	end
	currentEditor.SetEditing(value)
	if value then
		traySignature = ""
		refreshTray()
		SoundManager.Play("Open", 1.3)
	else
		currentEditor.Flush()
		SoundManager.Play("Click", 0.9)
	end
	layoutLeft(true)
	refreshEditUi()
end

local function openShop(section: string?)
	local currentShop = shop
	if not currentShop then
		return
	end
	currentShop.SetWidth(drawerWidth())
	currentShop.Open(section)
	layoutLeft(true)
	refreshEditUi()
end

local function tryPendingPlacements()
	local currentEditor = editor
	if not currentEditor or #pendingPlace == 0 or view ~= "room" then
		return
	end
	local now = os.clock()
	for index = #pendingPlace, 1, -1 do
		local pending = pendingPlace[index]
		if now > pending.Until then
			table.remove(pendingPlace, index)
		elseif currentEditor.Available(pending.Id) > 0 then
			table.remove(pendingPlace, index)
			local ok = currentEditor.CanPlace(pending.Id)
			if ok then
				if not currentEditor.IsEditing() then
					setEditing(true)
				end
				currentEditor.Place(pending.Id)
			else
				notify(Locale.T("This room is full! The new item waits in your inventory 📦"), C.Lilac)
			end
		end
	end
end

----------------------------------------------------------------------
-- Vues : vue d'ensemble <-> pièce
----------------------------------------------------------------------

local function refreshOverview()
	local currentOverview = overview
	if currentOverview and view == "overview" then
		currentOverview.SetHouse(latestHouse, overrides())
		for roomId, untilTime in pairs(pendingPulse) do
			if os.clock() > untilTime then
				pendingPulse[roomId] = nil
			elseif HouseCommon.GetRoom(latestHouse, roomId) then
				pendingPulse[roomId] = nil
				currentOverview.Pulse(roomId)
			end
		end
		for slot, untilTime in pairs(pendingSlotPulse) do
			local roomAt = HouseCommon.RoomAtSlot(latestHouse, slot)
			if os.clock() > untilTime then
				pendingSlotPulse[slot] = nil
			elseif roomAt then
				pendingSlotPulse[slot] = nil
				currentOverview.Pulse(roomAt.Id)
			end
		end
	end
end

local function setView(newView: string)
	view = newView
	local inRoom = newView == "room"
	overviewHolder.Visible = not inRoom
	stage.Visible = inRoom
	roomBar.Visible = inRoom
	if not inRoom then
		savedChip.Visible = false
		previewChip.Visible = false
		local currentOverview = overview
		if currentOverview then
			currentOverview.SetArranging(false)
		end
	end
	layoutLeft(false)
	refreshHeader()
	refreshEditUi()
	layoutHeader()
end

local function showRoomNow(roomId: string)
	local currentEditor = editor :: HouseEditor.Editor
	local currentRoomView = room :: HouseRoom.Room
	currentRoomId = roomId
	lastRoomId = roomId
	previewWallpaper, previewFloor = nil, nil
	currentEditor.SetRoom(roomId)
	setView("room")
	applyRoomStyle()
	refreshTabs()
	traySignature = ""
	refreshTray()
	refreshHeader()
	refreshEditUi()
	task.defer(currentRoomView.Refit)
	local currentShop = shop
	if currentShop and currentShop.IsOpen() then
		currentShop.Refresh()
	end
end

openRoom = function(roomId: string, instant: boolean?, after: (() -> ())?)
	if transitioning or not HouseCommon.GetRoom(latestHouse, roomId) then
		return
	end
	local currentOverview = overview
	local function finish()
		transitioning = false
		showRoomNow(roomId)
		-- Fondu d'arrivée dans la pièce
		stageFade.Visible = true
		stageFade.BackgroundTransparency = 0
		UIUtil.Tween(stageFade, FADE_TIME, { BackgroundTransparency = 1 })
		task.delay(FADE_TIME, function()
			stageFade.Visible = false
		end)
		tryPendingPlacements()
		if after then
			after()
		end
	end
	if view == "overview" and not instant and currentOverview then
		transitioning = true
		currentOverview.ZoomIn(roomId, finish)
	else
		finish()
	end
end

local function backToOverview()
	if view ~= "room" or transitioning then
		return
	end
	local currentEditor = editor
	if currentEditor then
		if currentEditor.IsEditing() then
			setEditing(false)
		end
		currentEditor.Flush()
	end
	previewWallpaper, previewFloor = nil, nil
	local leaving = currentRoomId
	currentRoomId = nil
	setView("overview")
	refreshOverview()
	local currentOverview = overview
	if currentOverview then
		currentOverview.ZoomOut(leaving)
	end
	local currentShop = shop
	if currentShop and currentShop.IsOpen() then
		currentShop.Refresh()
	end
	SoundManager.Play("Click", 0.9)
end

----------------------------------------------------------------------
-- Pièces : achat, type, rangement, envoi d'objets
----------------------------------------------------------------------

local function invoke(action: string, argument: any, onDone: ((ok: boolean, message: string?) -> ())?)
	task.spawn(function()
		local ok, message = HouseCommon.Invoke(action, argument)
		if onDone then
			onDone(ok, message)
		end
	end)
end

local function harmonyText(): string
	return HouseCommon.FormatPercent((HouseCommon.Config.HarmonyBonus or 0) * 100)
end

local function buyRoomAt(slot: number)
	local currentPicker = picker
	if not currentPicker then
		return
	end
	local size = HouseCommon.GetSize(latestHouse)
	local cost = HouseCommon.RoomCost(latestHouse)
	currentPicker.ShowRoomTypes({
		Title = Locale.T("🏗️ New room  •  💧 %s", NumberFormatter.Format(cost)),
		Subtitle = Locale.T("Room %d/%d — its favourite items give ✨ +%s%% comfort", #latestHouse.Rooms + 1, size.MaxRooms, harmonyText()),
		OnPick = function(typeId: string)
			local price = HouseCommon.RoomCost(latestHouse)
			local dopamine = HouseCommon.Dopamine()
			if dopamine < price then
				local missing = price - dopamine
				NeedDopamine.Offer(missing, function()
					notify(Locale.T("You need %s more Dopamine", NumberFormatter.Format(missing)), Theme.Colors.Red)
				end)
				return
			end
			invoke("buyRoom", { Type = typeId, Slot = slot }, function(ok: boolean, message: string?)
				if ok then
					SoundManager.Play("Buy", 1.1)
					notify(message or Locale.T("New room!"), Theme.Colors.Green, Locale.T("🏠 New room"))
					pendingSlotPulse[slot] = os.clock() + PENDING_PLACE_TIME
					refreshOverview()
				else
					SoundManager.Play("Error", 0.8)
					notify(message or Locale.T("Network error, try again."), Theme.Colors.Red)
				end
			end)
		end,
	})
end

local function changeRoomType(roomId: string)
	local currentPicker = picker
	local roomData = HouseCommon.GetRoom(latestHouse, roomId)
	if not currentPicker or not roomData then
		return
	end
	currentPicker.ShowRoomTypes({
		Title = Locale.T("🔄 Change room type"),
		Subtitle = Locale.T("Free! Items stay where they are  •  favourites give ✨ +%s%% comfort", harmonyText()),
		Current = roomData.Type,
		OnPick = function(typeId: string)
			invoke("setRoomType", { Room = roomId, Type = typeId }, function(ok: boolean, message: string?)
				notify(message or "", ok and Theme.Colors.Green or Theme.Colors.Red)
				if ok then
					pendingPulse[roomId] = os.clock() + PENDING_PLACE_TIME
				end
			end)
		end,
	})
end

local function roomMenu(roomId: string)
	local currentPicker = picker
	local roomData = HouseCommon.GetRoom(latestHouse, roomId)
	if not currentPicker or not roomData then
		return
	end
	currentPicker.ShowMenu({
		Title = roomLabel(roomData),
		Subtitle = Locale.T("Drag the room onto another spot to move it"),
		Buttons = {
			{ Text = Locale.T("🚪 Go inside"), Color = C.MintSoft, OnClick = function()
				local currentOverview = overview
				if currentOverview then
					currentOverview.SetArranging(false)
				end
				refreshEditUi()
				openRoom(roomId)
			end },
			{ Text = Locale.T("🔄 Change type"), Color = C.LilacSoft, OnClick = function()
				task.delay(0.16, function()
					changeRoomType(roomId)
				end)
			end },
		},
	})
end

local function moveRoom(roomId: string, slot: number)
	invoke("moveRoom", { Room = roomId, Slot = slot }, function(ok: boolean, message: string?)
		if not ok then
			local currentOverview = overview
			if currentOverview then
				currentOverview.CancelMoves()
			end
			SoundManager.Play("Error", 0.8)
			notify(message or Locale.T("Network error, try again."), Theme.Colors.Red)
		end
	end)
end

local function askSendTarget(entry: Placed)
	local currentPicker = picker
	local currentEditor = editor
	local item = HouseCommon.ItemsById[entry.I]
	if not currentPicker or not currentEditor or not item then
		return
	end
	local counts: { [string]: number } = {}
	local current = currentEditor.Overrides()
	for _, roomData in ipairs(latestHouse.Rooms) do
		counts[roomData.Id] = #(current[roomData.Id] or roomData.Placed)
	end
	currentPicker.ShowRooms({
		Title = Locale.T("🚪 Send %s to…", item.Icon .. " " .. HouseCommon.Name(item)),
		Subtitle = Locale.T("It lands on a free spot of that room"),
		House = latestHouse,
		ExcludeId = currentRoomId,
		Item = item,
		Counts = counts,
		OnPick = function(targetId: string)
			local active = editor
			if active then
				active.SendTo(targetId)
			end
		end,
	})
end

----------------------------------------------------------------------
-- Construction (à la première ouverture)
----------------------------------------------------------------------

local function ensureBuilt()
	if room then
		return
	end
	local newRoom = HouseRoom.new(stage)
	room = newRoom
	newRoom.SetDark(ClientState.DarkMode)

	local newEditor = HouseEditor.new(newRoom, function(text: string, color: Color3?)
		notify(text, color)
	end)
	editor = newEditor
	newEditor.Changed:Connect(function()
		refreshHeader()
		refreshTray()
		refreshEditUi()
		local currentShop = shop
		if currentShop then
			currentShop.Refresh()
		end
	end)
	newEditor.SaveStatusChanged:Connect(showSaved)
	newEditor.SelectionChanged:Connect(function(entry)
		hasSelection = entry ~= nil
		refreshEditUi()
	end)
	newEditor.HistoryChanged:Connect(refreshDock)
	newEditor.SetSendHandler(askSendTarget)

	picker = HousePicker.new(content)

	local newOverview = HouseOverview.new(overviewHolder, {
		OnOpenRoom = function(roomId: string)
			openRoom(roomId)
		end,
		OnEmptySlot = buyRoomAt,
		OnMoveRoom = moveRoom,
		OnRoomMenu = roomMenu,
	})
	overview = newOverview
	newOverview.SetDark(ClientState.DarkMode)

	-- Contrat B (HouseShop) : handlers passés tels quels (champs ajoutés en parallèle)
	local handlers = {
		Notify = notify,
		OnItemBought = function(itemId: string)
			if view == "room" then
				table.insert(pendingPlace, { Id = itemId, Until = os.clock() + PENDING_PLACE_TIME })
				tryPendingPlacements()
			end
		end,
		OnPlaceRequest = function(itemId: string)
			local function place()
				local current = editor
				if not current then
					return
				end
				if not current.IsEditing() then
					setEditing(true)
				end
				current.Place(itemId)
			end
			if view == "room" then
				place()
			else
				local target = lastRoomId and HouseCommon.GetRoom(latestHouse, lastRoomId) or sortedRooms()[1]
				if target then
					openRoom(target.Id, false, place)
				end
			end
		end,
		OnPreview = function(kind: string, id: string?)
			if view ~= "room" then
				return
			end
			if kind == "Wallpaper" then
				previewWallpaper = id
			else
				previewFloor = id
			end
			applyRoomStyle()
		end,
		OnHouseChanged = function()
			forceSync = not newEditor.IsBusy()
		end,
		BeforeHouseChange = function()
			newEditor.Flush()
		end,
		GetAvailable = function(itemId: string): number
			return newEditor.Available(itemId)
		end,
		GetCurrentRoom = function(): string?
			return view == "room" and currentRoomId or nil
		end,
		OnRoomBought = function(roomId: string)
			pendingPulse[roomId] = os.clock() + PENDING_PLACE_TIME
			refreshOverview()
		end,
		OnSizeChanged = function()
			forceSync = true
			refreshOverview()
			refreshHeader()
		end,
	}
	shop = HouseShop.new(main, handlers :: any)
	local drawerFrame = (shop :: HouseShop.Shop).Frame
	drawerFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not drawerFrame.Visible then
			previewWallpaper, previewFloor = nil, nil
			applyRoomStyle()
			layoutLeft(true)
			refreshEditUi()
		end
	end)

	newEditor.Sync(latestHouse, true)
	setView("overview")
end

----------------------------------------------------------------------
-- Construction de la fenêtre
----------------------------------------------------------------------

-- Pastille-bouton du bandeau
local function barButton(name: string, text: string, color: Color3, order: number): TextButton
	local height = Interface.IsTouch() and Theme.TouchTarget or 36
	local button = UIUtil.PillButton({
		Name = name,
		Text = text,
		Color = color,
		TextColor3 = WHITE,
		Height = height,
		TextSize = 16,
		LayoutOrder = order,
		ZIndex = 6,
	})
	local stroke = UIUtil.Create("UIStroke", {
		Color = Theme.Colors.TextDark,
		Thickness = 1,
		Transparency = 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
	stroke.Parent = button
	return button
end

-- Petit bouton blanc du dock / de la barre de la pièce
local function smallButton(name: string, text: string, order: number, parent: Instance): TextButton
	local height = Interface.IsTouch() and Theme.TouchTarget or 34
	local button = UIUtil.PillButton({
		Name = name,
		Text = text,
		Color = WHITE,
		TextColor3 = C.Ink,
		Height = height,
		TextSize = 15,
		LayoutOrder = order,
		ZIndex = 21,
		StrokeColor = C.Pink,
		StrokeTransparency = 0.3,
	})
	button.Parent = parent
	return button
end

function House.GetSize(): Vector2
	local canvas = Interface.CanvasSize
	local width = math.clamp(canvas.X * 0.94, 640, 1240)
	local height = math.clamp(canvas.Y * 0.94, 420, 720)
	return Vector2.new(math.floor(width), math.floor(height))
end

function House.Build(frame: Frame)
	content = frame

	-- Bandeau du haut
	local topBar = UIUtil.Create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, TOP_BAR),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = content,
	})
	leftGroup = UIUtil.Create("Frame", {
		Name = "Info",
		Size = UDim2.new(1, -360, 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 5,
		Parent = topBar,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = leftGroup,
	})
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 2), Parent = leftGroup })

	-- Vue pièce : retour + onglets des pièces
	backButton = barButton("Back", Locale.T("⬅ House"), C.PinkDeep, 1)
	backButton.Parent = leftGroup
	backButton.Visible = false
	tabsScroller = UIUtil.Create("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(0, 300, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 0,
		LayoutOrder = 2,
		Visible = false,
		ZIndex = 6,
		Parent = leftGroup,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 5),
		Parent = tabsScroller,
	})
	-- (marges : les contours des onglets ne sont pas coupés)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), Parent = tabsScroller })

	houseChip = UIUtil.Chip({
		Name = "HouseChip",
		Text = "🏠",
		Color = C.PinkMist,
		TextColor3 = C.Ink,
		Height = 32,
		TextSize = 15,
		LayoutOrder = 3,
		ZIndex = 6,
		Parent = leftGroup,
	})

	-- Confort + bonus (pilule rose)
	comfortPill = UIUtil.Create("Frame", {
		Name = "Comfort",
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Pink,
		LayoutOrder = 4,
		ZIndex = 6,
		Parent = leftGroup,
	})
	UIUtil.Corner(comfortPill, UDim.new(1, 0))
	UIUtil.Stroke(comfortPill, WHITE, 2, 0.2)
	UIUtil.Gradient(comfortPill, ColorSequence.new(C.Pink:Lerp(WHITE, 0.15), C.PinkDeep), 0)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = comfortPill,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = comfortPill,
	})
	comfortLabel = UIUtil.Create("TextLabel", {
		Name = "Comfort",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = WHITE,
		TextSize = 17,
		LayoutOrder = 1,
		ZIndex = 7,
		Parent = comfortPill,
	})
	bonusLabel = UIUtil.Create("TextLabel", {
		Name = "Bonus",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextColor3 = C.PinkMist,
		TextSize = 15,
		LayoutOrder = 2,
		ZIndex = 7,
		Parent = comfortPill,
	})
	for _, label in ipairs({ comfortLabel, bonusLabel }) do
		UIUtil.Create("UIStroke", {
			Color = C.PinkDeep:Lerp(Color3.new(0, 0, 0), 0.4),
			Thickness = 1,
			Transparency = 0.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = label,
		})
	end

	-- Boutons (à droite)
	rightGroup = UIUtil.Create("Frame", {
		Name = "Buttons",
		Size = UDim2.new(0, 350, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = topBar,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = rightGroup,
	})
	arrangeButton = barButton("Arrange", Locale.T("↔️ Arrange"), C.Lilac, 1)
	arrangeButton.Parent = rightGroup
	editButton = barButton("Edit", Locale.T("✏️ Edit"), C.Lilac, 2)
	editButton.Parent = rightGroup
	editButton.Visible = false
	shopButton = barButton("Shop", Locale.T("🛍️ Shop"), C.PinkDeep, 3)
	shopButton.Parent = rightGroup
	-- Badge DANS la pastille, à droite du texte (ne cache plus "Boutique" et ne
	-- déborde pas du bord de la fenêtre) : la pastille s'élargit quand il est là
	shopBadge = UIUtil.Badge(shopButton, 20)
	shopBadge.AnchorPoint = Vector2.new(1, 0.5)
	do
		local padding = shopButton:FindFirstChildOfClass("UIPadding")
		local basePad = padding and padding.PaddingRight.Offset or 16
		local function placeBadge()
			local right = shopBadge.Visible and basePad + 30 or basePad
			if padding then
				padding.PaddingRight = UDim.new(0, right)
			end
			shopBadge.Position = UDim2.new(1, right - 6, 0.5, 0)
			task.defer(layoutHeader)
		end
		shopBadge:GetPropertyChangedSignal("Visible"):Connect(placeBadge)
		placeBadge()
	end

	-- Zone principale : maison / pièce (+ inventaire) à gauche, tiroir de la boutique à droite
	main = UIUtil.Create("Frame", {
		Name = "Main",
		Size = UDim2.new(1, 0, 1, -(TOP_BAR + 6)),
		Position = UDim2.fromOffset(0, TOP_BAR + 6),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = content,
	})
	left = UIUtil.Create("Frame", {
		Name = "Left",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = main,
	})
	overviewHolder = UIUtil.Create("Frame", {
		Name = "OverviewHolder",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = left,
	})
	stage = UIUtil.Create("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.PinkMist,
		Visible = false,
		ZIndex = 5,
		Parent = left,
	})
	UIUtil.Corner(stage, 20)
	UIUtil.Gradient(stage, ColorSequence.new(WHITE, Color3.fromRGB(236, 236, 240)), 90)
	stage:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layoutStageChips()
	end)
	stageFade = UIUtil.Create("Frame", {
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
		Parent = stage,
	})
	UIUtil.Corner(stageFade, 20)

	-- Barre de la pièce (en haut à gauche) : type (cliquable), confort, sauvegarde
	roomBar = UIUtil.Create("Frame", {
		Name = "RoomBar",
		Size = UDim2.new(1, -20, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = stage,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = roomBar,
	})
	typeButton = smallButton("RoomType", "", 1, roomBar)
	typeButton.BackgroundColor3 = WHITE
	statsChip = UIUtil.Chip({
		Name = "RoomStats",
		Text = "",
		Color = WHITE,
		TextColor3 = C.Ink,
		Height = 28,
		TextSize = 14,
		LayoutOrder = 2,
		ZIndex = 21,
		Parent = roomBar,
	})
	statsChip.BackgroundTransparency = 0.1
	savedChip = UIUtil.Chip({
		Name = "Saved",
		Text = "",
		Color = C.MintSoft,
		TextColor3 = C.Ink,
		Height = 26,
		TextSize = 13,
		LayoutOrder = 3,
		ZIndex = 21,
		Visible = false,
		Parent = roomBar,
	})

	-- Dock d'édition (en haut à droite) : annuler / rétablir / aimant
	dock = UIUtil.Create("Frame", {
		Name = "Dock",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 22,
		Parent = stage,
	})
	UIUtil.Corner(dock, UDim.new(1, 0))
	UIUtil.Stroke(dock, C.Pink, 1.5, 0.3)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = dock,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 5),
		Parent = dock,
	})
	undoButton = smallButton("Undo", "↩️", 1, dock)
	redoButton = smallButton("Redo", "↪️", 2, dock)
	snapButton = smallButton("Snap", "🧲", 3, dock)

	-- "Aperçu" (essai d'un papier peint / sol)
	previewChip = UIUtil.Chip({
		Name = "PreviewChip",
		Text = Locale.T("👀 Preview"),
		Color = C.Butter,
		TextColor3 = C.Ink,
		Height = 26,
		TextSize = 14,
		ZIndex = 20,
		Visible = false,
		Parent = stage,
	})
	previewChip.AnchorPoint = Vector2.new(0.5, 1)
	previewChip.Position = UDim2.new(0.5, 0, 1, -38)

	-- Astuce en mode édition
	editHint = UIUtil.Chip({
		Name = "EditHint",
		Text = Locale.T("✋ Drag to move  •  tap for options"),
		Color = WHITE,
		TextColor3 = C.Ink,
		Height = 24,
		TextSize = 13,
		ZIndex = 20,
		Visible = false,
		Parent = stage,
	})
	editHint.AnchorPoint = Vector2.new(0.5, 1)
	editHint.Position = UDim2.new(0.5, 0, 1, -6)

	-- Pièce vide : invitation à ouvrir la boutique
	emptyHint = UIUtil.Create("Frame", {
		Name = "EmptyHint",
		Size = UDim2.fromOffset(340, 132),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 20,
		Parent = stage,
	})
	UIUtil.Corner(emptyHint, 20)
	UIUtil.Stroke(emptyHint, C.Pink, 2, 0.2)
	UIUtil.Label({
		Name = "Text",
		Size = UDim2.new(1, -24, 0, 62),
		Position = UDim2.fromOffset(12, 10),
		Font = Theme.Fonts.Title,
		Text = Locale.T("This room is empty! 🥺\nPlace cute furniture to make it cozy."),
		TextColor3 = C.Ink,
		TextWrapped = true,
		MaxTextSize = 17,
		ZIndex = 21,
		Parent = emptyHint,
	})
	local emptyButton = UIUtil.NeonButton({
		Name = "Decorate",
		Text = Locale.T("✏️ Decorate"),
		Size = UDim2.new(0.5, -18, 0, 40),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Color = C.Lilac,
		TextColor3 = WHITE,
		CornerRadius = 20,
		MaxTextSize = 17,
		ZIndex = 21,
		Parent = emptyHint,
	})
	local emptyShopButton = UIUtil.NeonButton({
		Name = "OpenShop",
		Text = Locale.T("🛍️ Shop"),
		Size = UDim2.new(0.5, -18, 0, 40),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Color = C.PinkDeep,
		TextColor3 = WHITE,
		CornerRadius = 20,
		MaxTextSize = 17,
		ZIndex = 21,
		Parent = emptyHint,
	})

	-- Inventaire (mode édition)
	tray = UIUtil.Create("Frame", {
		Name = "Inventory",
		Size = UDim2.new(1, 0, 0, 82),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 10,
		Parent = left,
	})
	UIUtil.Corner(tray, 18)
	UIUtil.Stroke(tray, C.Pink, 1.5, 0.3)
	UIUtil.Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(0, 104, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = Locale.T("📦 Inventory\ntap to place"),
		TextColor3 = C.Ink,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = tray,
	})
	trayList = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, -128, 1, -4),
		Position = UDim2.fromOffset(120, 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Pink,
		ZIndex = 11,
		Parent = tray,
	})
	-- Marge à gauche : le contour de la première tuile n'est pas coupé
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), Parent = trayList })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = trayList,
	})
	trayEmpty = UIUtil.Create("TextLabel", {
		Name = "Empty",
		Size = UDim2.new(1, -140, 1, 0),
		Position = UDim2.fromOffset(124, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = Locale.T("Everything is placed! Buy more cute stuff in the 🛍️ Shop."),
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = tray,
	})

	-- Boutons
	editButton.Activated:Connect(function()
		ensureBuilt()
		local currentEditor = editor
		if currentEditor and view == "room" then
			setEditing(not currentEditor.IsEditing())
		end
	end)
	arrangeButton.Activated:Connect(function()
		ensureBuilt()
		local currentOverview = overview
		if currentOverview and view == "overview" then
			currentOverview.SetArranging(not currentOverview.IsArranging())
			SoundManager.Play(currentOverview.IsArranging() and "Open" or "Click", 1.2)
			refreshEditUi()
		end
	end)
	shopButton.Activated:Connect(function()
		ensureBuilt()
		local currentShop = shop
		if currentShop and currentShop.IsOpen() then
			currentShop.Close()
		else
			openShop(nil)
		end
	end)
	backButton.Activated:Connect(backToOverview)
	typeButton.Activated:Connect(function()
		if currentRoomId then
			changeRoomType(currentRoomId :: string)
		end
	end)
	undoButton.Activated:Connect(function()
		local currentEditor = editor
		if currentEditor then
			currentEditor.Undo()
		end
	end)
	redoButton.Activated:Connect(function()
		local currentEditor = editor
		if currentEditor then
			currentEditor.Redo()
		end
	end)
	snapButton.Activated:Connect(function()
		local currentEditor = editor
		if currentEditor then
			currentEditor.SetSnap(not currentEditor.GetSnap())
			notify(currentEditor.GetSnap() and Locale.T("🧲 Items now snap to the grid") or Locale.T("🧲 Free placement"), C.Lilac)
		end
	end)
	emptyButton.Activated:Connect(function()
		setEditing(true)
	end)
	emptyShopButton.Activated:Connect(function()
		ensureBuilt()
		openShop("Items")
	end)

	-- Mode sombre : la maison et la pièce passent en mode nuit
	ClientState.DarkModeChanged:Connect(function(dark: boolean)
		local currentRoomView = room
		if currentRoomView then
			currentRoomView.SetDark(dark)
		end
		local currentOverview = overview
		if currentOverview then
			currentOverview.SetDark(dark)
		end
	end)
	-- Écran qui change : tiroir, inventaire, bandeau
	Interface.DeviceChanged:Connect(function()
		local currentShop = shop
		if currentShop then
			currentShop.SetWidth(drawerWidth())
		end
		traySignature = ""
		tabsSignature = ""
		refreshTray()
		refreshTabs()
		refreshHeader()
		refreshEditUi()
		if room then
			layoutLeft(false)
		end
	end)

	refreshHeader()
	refreshEditUi()
end

function House.Update(data)
	local previousSize = latestHouse.Size
	latestHouse = HouseCommon.GetHouse(data)
	-- Nouvelle taille de maison : le serveur a recalé les objets, on reprend
	-- sa disposition telle quelle
	if previousSize ~= latestHouse.Size then
		forceSync = true
	end
	-- La pièce ouverte n'existe plus (ne devrait pas arriver) : retour à la maison
	if view == "room" and not currentRoom() then
		backToOverview()
	end
	local currentEditor = editor
	if currentEditor then
		local force = forceSync
		forceSync = false
		currentEditor.Sync(latestHouse, force)
		applyRoomStyle()
		tryPendingPlacements()
		refreshTray()
		if view == "room" then
			refreshTabs()
		end
		refreshEditUi()
	end
	if isOpen then
		refreshOverview()
	end
	refreshHeader()
	refreshShopBadge()
	if isOpen and shop then
		(shop :: HouseShop.Shop).Refresh()
	end
end

function House.OnOpen()
	isOpen = true
	closeWatcher += 1
	ensureBuilt()
	local currentEditor = editor :: HouseEditor.Editor
	local currentRoomView = room :: HouseRoom.Room
	local currentOverview = overview :: HouseOverview.Overview
	currentEditor.SetActive(true)
	if not currentEditor.IsBusy() then
		currentEditor.Sync(latestHouse, false)
	end
	-- "🏠 Ma maison" s'ouvre sur la vue d'ensemble
	currentRoomId = nil
	setView("overview")
	currentRoomView.SetDark(ClientState.DarkMode)
	currentOverview.SetDark(ClientState.DarkMode)
	refreshOverview()
	currentOverview.ZoomOut(nil)
	refreshShopBadge()
	task.defer(function()
		currentOverview.Refit()
		layoutHeader()
	end)

	if renderConnection then
		renderConnection:Disconnect()
	end
	renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		local step = math.min(dt, 0.1)
		currentEditor.Update(step)
		if view == "room" then
			currentRoomView.Update(step)
		else
			currentOverview.Update(step)
		end
		refreshClock += step
		if refreshClock >= 0.5 then
			refreshClock = 0
			refreshShopBadge()
			local currentShop = shop
			if currentShop and currentShop.IsOpen() then
				currentShop.Refresh()
			end
		end
	end)
end

function House.OnClose()
	isOpen = false
	local connection = renderConnection
	if connection then
		connection:Disconnect()
		renderConnection = nil
	end
	local currentShop = shop
	if currentShop then
		currentShop.Close()
	end
	local currentPicker = picker
	if currentPicker then
		currentPicker.Close()
	end
	local currentOverview = overview
	if currentOverview then
		currentOverview.SetArranging(false)
	end
	local currentEditor = editor
	if not currentEditor then
		return
	end
	currentEditor.SetActive(false)
	if currentEditor.IsEditing() then
		currentEditor.SetEditing(false)
		if tray then
			layoutLeft(false)
		end
		refreshEditUi()
	end
	currentEditor.Flush()
	-- Sauvegarde encore en attente (nouvel essai) : on continue en arrière-plan
	closeWatcher += 1
	local token = closeWatcher
	task.spawn(function()
		local started = os.clock()
		while token == closeWatcher and currentEditor.IsBusy() and os.clock() - started < 12 do
			task.wait(0.25)
			currentEditor.Update(0.25)
		end
	end)
end

return House
