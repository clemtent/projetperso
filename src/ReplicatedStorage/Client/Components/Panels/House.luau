--[[
	House (ModuleScript) — "🏠 Ma maison"
	Emplacement : ReplicatedStorage > Client > Components > Panels > House

	Grande fenêtre (presque plein écran, s'adapte au téléphone / à la
	tablette) :
	  - bandeau du haut : nom de la maison et place utilisée, confort ❤️ et
	    bonus "+X % de Dopamine" (calculés en direct pendant l'édition),
	    pastille "Enregistré ✓" de la sauvegarde automatique, boutons
	    "✏️ Modifier" / "✅ Terminé" et "🛍️ Boutique" (badge : nouveaux
	    objets abordables) ;
	  - la pièce kawaii en coupe (House/HouseRoom) avec ses objets ;
	  - mode édition (House/HouseEditor) : glisser, barre d'outils,
	    inventaire en bas (toucher un objet rangé = le poser) ;
	  - tiroir de la boutique (House/HouseShop) : la pièce se décale à
	    gauche pour rester visible (aperçus en direct des murs / sols).
	Un objet acheté est posé tout de suite dans la pièce (si la place le
	permet) et sélectionné. La pièce se construit à la première ouverture.
	Textes en anglais (Locale.T), français dans Lang/FR_HouseUI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local HouseFolder = script.Parent.Parent:WaitForChild("House")
local HouseCommon = require(HouseFolder:WaitForChild("HouseCommon"))
local HouseRoom = require(HouseFolder:WaitForChild("HouseRoom"))
local HouseEditor = require(HouseFolder:WaitForChild("HouseEditor"))
local HouseShop = require(HouseFolder:WaitForChild("HouseShop"))
local HouseArt = require(HouseFolder:WaitForChild("HouseArt"))
local Locale = require(ReplicatedStorage.Shared.Locale)

type HouseData = HouseCommon.HouseData

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

local content: Frame
local main: Frame
local left: Frame
local stage: Frame
local tray: Frame
local trayList: ScrollingFrame
local trayEmpty: TextLabel
local emptyHint: Frame
local editHint: Frame
local houseChip: Frame
local comfortPill: Frame
local comfortLabel: TextLabel
local bonusLabel: TextLabel
local savedChip: Frame
local editButton: TextButton
local shopButton: TextButton
local shopBadge: TextLabel
local previewChip: Frame

local room: HouseRoom.Room? = nil
local editor: HouseEditor.Editor? = nil
local shop: HouseShop.Shop? = nil

local latestHouse: HouseData = HouseCommon.GetHouse(nil)
local isOpen = false
local forceSync = false
local renderConnection: RBXScriptConnection? = nil
local previewWallpaper: string? = nil
local previewFloor: string? = nil
local pendingPlace: { { Id: string, Until: number } } = {}
local lastComfort: number? = nil
local traySignature = ""
local savedToken = 0
local refreshClock = 0
local closeWatcher = 0
local hasSelection = false

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

----------------------------------------------------------------------
-- Bandeau du haut
----------------------------------------------------------------------

local function refreshHeader()
	local layout = editor and editor.GetLayout() or latestHouse.Placed
	local size = HouseCommon.GetSize(latestHouse)
	setChip(houseChip, string.format("%s %s  •  %s", size.Icon, HouseCommon.Name(size), Locale.T("%d/%d items", #layout, size.MaxItems)))
	local comfort = HouseCommon.Comfort(latestHouse, layout)
	local percent = HouseCommon.BonusPercent(comfort)
	comfortLabel.Text = Locale.T("❤️ %d comfort", comfort)
	bonusLabel.Text = Locale.T("+%s%% Dopamine", HouseCommon.FormatPercent(percent))
	if lastComfort ~= nil and comfort ~= lastComfort then
		UIUtil.Pop(comfortPill, comfort > (lastComfort :: number) and 1.15 or 0.9, 0.4)
	end
	lastComfort = comfort
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
	savedChip.Visible = true
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

----------------------------------------------------------------------
-- Pièce : style (taille, papier peint, sol, aperçus)
----------------------------------------------------------------------

local function applyRoomStyle()
	local currentRoom = room
	if not currentRoom then
		return
	end
	local size = HouseCommon.GetSize(latestHouse)
	local wallpaper = (previewWallpaper and HouseCommon.WallpapersById[previewWallpaper]) or HouseCommon.GetWallpaper(latestHouse)
	local floor = (previewFloor and HouseCommon.FloorsById[previewFloor]) or HouseCommon.GetFloor(latestHouse)
	currentRoom.SetStyle(size, wallpaper, floor)
	previewChip.Visible = previewWallpaper ~= nil or previewFloor ~= nil
end

----------------------------------------------------------------------
-- Inventaire (objets possédés pas encore posés)
----------------------------------------------------------------------

local function refreshTray()
	local currentEditor = editor
	if not currentEditor then
		return
	end
	local entries = {}
	local parts = {}
	for _, item in ipairs(HouseCommon.Config.Items) do
		local free = currentEditor.Available(item.Id)
		if free > 0 then
			table.insert(entries, { Item = item, Free = free })
			table.insert(parts, item.Id .. "=" .. free)
		end
	end
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
		UIUtil.Stroke(tile, C.Pink, 1.5, 0.3)
		UIUtil.AnimateButton(tile, 1.08, 0.9)
		local badge = UIUtil.Badge(tile, 20)
		badge.BackgroundColor3 = C.PinkDeep
		badge.Position = UDim2.new(1, -3, 0, 3)
		badge.Text = "x" .. entry.Free
		badge.ZIndex = 20
		badge.Visible = true
		tile.Activated:Connect(function()
			local current = editor
			if current then
				current.Place(item.Id)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Mode édition, tiroir de la boutique
----------------------------------------------------------------------

local function layoutLeft(animate: boolean)
	local shopOpen = shop ~= nil and (shop :: HouseShop.Shop).IsOpen()
	local editing = editor ~= nil and (editor :: HouseEditor.Editor).IsEditing()
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
end

local function refreshEditUi()
	local editing = editor ~= nil and (editor :: HouseEditor.Editor).IsEditing()
	editButton.Text = editing and Locale.T("✅ Done") or Locale.T("✏️ Edit")
	editButton:SetAttribute("BaseColor", editing and Theme.Colors.Green or C.Lilac)
	editButton.BackgroundColor3 = editing and Theme.Colors.Green or C.Lilac
	local empty = #(editor and (editor :: HouseEditor.Editor).GetLayout() or latestHouse.Placed) == 0
	local shopOpen = shop ~= nil and (shop :: HouseShop.Shop).IsOpen()
	emptyHint.Visible = empty and not editing and not shopOpen
	editHint.Visible = editing and not hasSelection and not shopOpen
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
	if not currentEditor or #pendingPlace == 0 then
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
				notify(Locale.T("Your house is full! The new item waits in your inventory 📦"), C.Lilac)
			end
		end
	end
end

----------------------------------------------------------------------
-- Construction de la pièce (à la première ouverture)
----------------------------------------------------------------------

local function ensureRoom()
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

	shop = HouseShop.new(main, {
		Notify = notify,
		OnItemBought = function(itemId: string)
			table.insert(pendingPlace, { Id = itemId, Until = os.clock() + PENDING_PLACE_TIME })
			tryPendingPlacements()
		end,
		OnPlaceRequest = function(itemId: string)
			if not newEditor.IsEditing() then
				setEditing(true)
			end
			newEditor.Place(itemId)
		end,
		OnPreview = function(kind: string, id: string?)
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
	})
	local drawerFrame = (shop :: HouseShop.Shop).Frame
	drawerFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not drawerFrame.Visible then
			layoutLeft(true)
			refreshEditUi()
		end
	end)

	applyRoomStyle()
	newEditor.Sync(latestHouse, true)
	layoutLeft(false)
	refreshHeader()
	refreshEditUi()
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
	local leftGroup = UIUtil.Create("Frame", {
		Name = "Info",
		Size = UDim2.new(1, -300, 1, 0),
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
	houseChip = UIUtil.Chip({
		Name = "HouseChip",
		Text = "🏠",
		Color = C.PinkMist,
		TextColor3 = C.Ink,
		Height = 32,
		TextSize = 15,
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = leftGroup,
	})

	-- Confort + bonus (pilule rose)
	comfortPill = UIUtil.Create("Frame", {
		Name = "Comfort",
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Pink,
		LayoutOrder = 2,
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
	savedChip = UIUtil.Chip({
		Name = "Saved",
		Text = "",
		Color = C.MintSoft,
		TextColor3 = C.Ink,
		Height = 26,
		TextSize = 13,
		LayoutOrder = 3,
		ZIndex = 6,
		Visible = false,
		Parent = leftGroup,
	})

	-- Boutons (à droite)
	local rightGroup = UIUtil.Create("Frame", {
		Name = "Buttons",
		Size = UDim2.new(0, 300, 1, 0),
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
	editButton = barButton("Edit", Locale.T("✏️ Edit"), C.Lilac, 1)
	editButton.Parent = rightGroup
	shopButton = barButton("Shop", Locale.T("🛍️ Shop"), C.PinkDeep, 2)
	shopButton.Parent = rightGroup
	shopBadge = UIUtil.Badge(shopButton, 22)

	-- Zone principale : pièce (+ inventaire) à gauche, tiroir de la boutique à droite
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
	stage = UIUtil.Create("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.PinkMist,
		ZIndex = 5,
		Parent = left,
	})
	UIUtil.Corner(stage, 20)
	UIUtil.Gradient(stage, ColorSequence.new(WHITE, Color3.fromRGB(236, 236, 240)), 90)

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
	previewChip.AnchorPoint = Vector2.new(0.5, 0)
	previewChip.Position = UDim2.new(0.5, 0, 0, 6)

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
		Position = UDim2.fromScale(0.5, 0.52),
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
		Text = Locale.T("Your room is empty! 🥺\nBuy cute furniture to make it cozy."),
		TextColor3 = C.Ink,
		TextWrapped = true,
		MaxTextSize = 17,
		ZIndex = 21,
		Parent = emptyHint,
	})
	local emptyButton = UIUtil.NeonButton({
		Name = "OpenShop",
		Text = Locale.T("🛍️ Open the shop"),
		Size = UDim2.new(1, -60, 0, 40),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Color = C.PinkDeep,
		TextColor3 = WHITE,
		CornerRadius = 20,
		MaxTextSize = 18,
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
		ensureRoom()
		local currentEditor = editor
		if currentEditor then
			setEditing(not currentEditor.IsEditing())
		end
	end)
	shopButton.Activated:Connect(function()
		ensureRoom()
		local currentShop = shop
		if currentShop and currentShop.IsOpen() then
			currentShop.Close()
		else
			openShop(nil)
		end
	end)
	emptyButton.Activated:Connect(function()
		ensureRoom()
		openShop("Items")
	end)

	-- Mode sombre : la pièce passe en mode nuit
	ClientState.DarkModeChanged:Connect(function(dark: boolean)
		local currentRoom = room
		if currentRoom then
			currentRoom.SetDark(dark)
		end
	end)
	-- Écran qui change : tiroir, inventaire
	Interface.DeviceChanged:Connect(function()
		local currentShop = shop
		if currentShop then
			currentShop.SetWidth(drawerWidth())
		end
		traySignature = ""
		refreshTray()
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
	local currentEditor = editor
	if currentEditor then
		local force = forceSync
		forceSync = false
		currentEditor.Sync(latestHouse, force)
		applyRoomStyle()
		tryPendingPlacements()
		refreshTray()
		refreshEditUi()
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
	ensureRoom()
	local currentEditor = editor :: HouseEditor.Editor
	local currentRoom = room :: HouseRoom.Room
	currentEditor.SetActive(true)
	if not currentEditor.IsBusy() then
		currentEditor.Sync(latestHouse, false)
	end
	applyRoomStyle()
	currentRoom.SetDark(ClientState.DarkMode)
	layoutLeft(false)
	refreshHeader()
	refreshEditUi()
	refreshShopBadge()
	task.defer(currentRoom.Refit)

	if renderConnection then
		renderConnection:Disconnect()
	end
	renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		local step = math.min(dt, 0.1)
		currentEditor.Update(step)
		currentRoom.Update(step)
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
