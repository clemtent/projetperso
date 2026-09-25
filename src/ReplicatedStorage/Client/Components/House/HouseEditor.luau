--[[
	HouseEditor (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseEditor

	Disposition des objets d'UNE pièce de la maison (côté client) :
	  - copie locale de room.Placed + un "autocollant" par objet
	    (HouseRoom.CreateSticker), triés en profondeur : objets muraux
	    derrière, tapis à plat, puis objets au sol (couche Z, puis Y : plus
	    bas = devant) ; SetRoom change de pièce (la précédente est
	    sauvegardée tout de suite) ;
	  - MODE ÉDITION : glisser-déposer fluide à la souris ET au doigt,
	    l'objet reste dans sa zone (mur / sol), zone valide mise en valeur,
	    AIMANTATION à la grille (option 🧲, lignes visibles pendant le
	    glissement), petit "plop" à la pose ;
	  - sélection + barre d'outils flottante : ➖ plus petit, ➕ plus grand,
	    ⏬ derrière, ⏫ devant, 📑 dupliquer, 🚪 envoyer dans une autre pièce,
	    📦 ranger ; le survol d'un bouton affiche son nom et son raccourci ;
	  - ANNULER / RÉTABLIR (30 étapes par pièce ; Ctrl+Z / Ctrl+Y) ;
	  - clavier : flèches = petit déplacement (Maj = plus grand), + / - =
	    taille, Page préc. / suiv. = couche, Suppr = ranger, Ctrl+D =
	    dupliquer, Échap = désélectionner, G = aimant ;
	  - pose depuis l'inventaire (Place) à un endroit libre ;
	  - sauvegarde automatique "saveLayout" { Rooms = { [pièce] = ... } }
	    ~1,5 s après la dernière modification (les 2 pièces d'un envoi
	    partent dans le même appel) ; nouvel essai si le serveur refuse,
	    puis resynchro ;
	  - hors édition : toucher un objet le fait rebondir (petits cœurs).
	Les exemplaires sont comptés dans TOUTES les pièces (HouseCommon.Available
	avec la disposition locale). Le serveur revérifie tout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Locale = require(ReplicatedStorage.Shared.Locale)
local HouseCommon = require(script.Parent.HouseCommon)
local HouseRoom = require(script.Parent.HouseRoom)

type Placed = HouseCommon.Placed
type HouseData = HouseCommon.HouseData
type Item = HouseCommon.Item
type Room = HouseRoom.Room
type Sticker = HouseRoom.Sticker

local HouseEditor = {}

local SAVE_DELAY = 1.5 -- (s) après la dernière modification
local RETRY_DELAY = 1.2 -- (s) nouvel essai si le serveur refuse
local SYNC_BLOCK = 2.5 -- (s) après une sauvegarde : on ignore les anciens états du serveur
local DRAG_THRESHOLD = 6 -- (px écran) en dessous : c'est un simple toucher
local DRAG_SMOOTHING = 24 -- vitesse de rattrapage du doigt (plus = plus collé)
local LIFT_SCALE = 1.1
local HISTORY_STEPS = 30
local GRID = 20 -- (px de maquette) pas de l'aimant
local NUDGE_SMALL = 4 -- (px de maquette) flèche
local NUDGE_BIG = 24 -- (px de maquette) Maj + flèche
local NUDGE_MERGE = 0.8 -- (s) flèches enchaînées = une seule étape d'annulation

local C = HouseCommon.Colors
local WHITE = Color3.new(1, 1, 1)

export type SaveStatus = "idle" | "dirty" | "saving" | "saved" | "error"

export type Editor = {
	Changed: any, -- Signal () : disposition modifiée (confort, inventaire)
	SaveStatusChanged: any, -- Signal (status: SaveStatus)
	SelectionChanged: any, -- Signal (entry: Placed?)
	HistoryChanged: any, -- Signal () : annuler / rétablir / aimant
	SetEditing: (editing: boolean) -> (),
	IsEditing: () -> boolean,
	SetActive: (active: boolean) -> (),
	SetRoom: (roomId: string) -> (),
	GetRoomId: () -> string?,
	Sync: (house: HouseData, force: boolean?) -> (),
	GetLayout: () -> { Placed },
	Overrides: () -> HouseCommon.Overrides,
	Available: (itemId: string) -> number,
	CanPlace: (itemId: string) -> (boolean, string?),
	Place: (itemId: string) -> boolean,
	Select: (index: number) -> (),
	Deselect: () -> (),
	GetSelected: () -> Placed?,
	Duplicate: () -> boolean,
	SendTo: (roomId: string) -> boolean,
	SetSendHandler: (handler: (entry: Placed) -> ()) -> (),
	Undo: () -> boolean,
	Redo: () -> boolean,
	CanUndo: () -> boolean,
	CanRedo: () -> boolean,
	SetSnap: (on: boolean) -> (),
	GetSnap: () -> boolean,
	Flush: () -> (),
	IsBusy: () -> boolean,
	Update: (dt: number) -> (),
}

type Drag = {
	Entry: Placed,
	Input: InputObject,
	Offset: Vector2,
	Target: Vector2,
	Start: Vector2,
	Moved: boolean,
	Before: { Placed },
}

-- Envoi vers une autre pièce (pour l'annuler / le rétablir)
type Cross = { Room: string, Before: { Placed }, After: { Placed } }
type Step = { Layout: { Placed }, Cross: Cross? }
type History = { Undo: { Step }, Redo: { Step } }

-- Rang de la zone : muraux derrière, objets à plat (tapis), puis le sol
local function zoneRank(sticker: Sticker): number
	if sticker.Item.Placement == "Wall" then
		return 0
	elseif sticker.Flat then
		return 1
	end
	return 2
end

local function roundTo(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

local function signature(list: { Placed }): string
	local parts = table.create(#list)
	for index, entry in ipairs(list) do
		parts[index] = string.format("%s:%.4f:%.4f:%.3f:%d", entry.I, entry.X, entry.Y, entry.S, math.floor(entry.Z))
	end
	return table.concat(parts, ";")
end

local function copyList(list: { Placed }): { Placed }
	local result = table.create(#list)
	for index, entry in ipairs(list) do
		result[index] = { I = entry.I, X = entry.X, Y = entry.Y, S = entry.S, Z = entry.Z }
	end
	return result
end

-- Disposition envoyée au serveur (mêmes arrondis que lui)
local function payloadOf(list: { Placed }): { Placed }
	local payload = table.create(#list)
	for index, entry in ipairs(list) do
		payload[index] = {
			I = entry.I,
			X = roundTo(entry.X, 0.0001),
			Y = roundTo(entry.Y, 0.0001),
			S = roundTo(entry.S, 0.001),
			Z = math.clamp(math.floor(entry.Z), 0, HouseCommon.MAX_Z),
		}
	end
	return payload
end

-- Aimant : partagé par toutes les pièces (et gardé entre deux ouvertures)
local snapEnabled = false

function HouseEditor.new(room: Room, notify: (text: string, color: Color3?) -> ()): Editor
	local editor: Editor
	local house: HouseData = HouseCommon.GetHouse(nil)
	local roomId: string? = nil
	local layout: { Placed } = {}
	local stickers: { [Placed]: Sticker } = {}
	local selected: Placed? = nil
	local drag: Drag? = nil
	local editing = false
	local active = false
	local dirty = false
	local saving = false
	local saveAt = 0
	local failures = 0
	local blockUntil = 0
	local lastSignature = ""
	local clock = 0
	local extras: HouseCommon.Overrides = {} -- autres pièces à sauvegarder avec la prochaine sauvegarde
	local histories: { [string]: History } = {}
	local lastNudge = 0
	local lastNudgeEntry: Placed? = nil
	local sendHandler: ((entry: Placed) -> ())? = nil

	local changed = Signal.new()
	local saveStatusChanged = Signal.new()
	local selectionChanged = Signal.new()
	local historyChanged = Signal.new()

	----------------------------------------------------------------------
	-- Barre d'outils de sélection
	----------------------------------------------------------------------

	local toolbar = UIUtil.Create("Frame", {
		Name = "Toolbar",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = room.Overlay,
	})
	local toolbarScale = UIUtil.Create("UIScale", { Parent = toolbar })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = toolbar,
	})
	local nameChip = UIUtil.Chip({
		Name = "NameChip",
		Text = "",
		Color = C.PinkDeep,
		TextColor3 = WHITE,
		Height = 26,
		TextSize = 14,
		LayoutOrder = 1,
		ZIndex = 21,
		Parent = toolbar,
	})
	local nameLabel = nameChip:FindFirstChild("Label") :: TextLabel
	local bar = UIUtil.Create("Frame", {
		Name = "Bar",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = WHITE,
		LayoutOrder = 2,
		ZIndex = 21,
		Parent = toolbar,
	})
	UIUtil.Corner(bar, 22)
	UIUtil.Stroke(bar, C.Pink, 2, 0.1)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		Parent = bar,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = bar,
	})

	local nameText = ""
	local hoverTip: string? = nil
	local function refreshNameChip()
		local value = hoverTip or nameText
		if nameLabel.Text ~= value then
			nameLabel.Text = value
		end
		nameChip.BackgroundColor3 = hoverTip and C.Ink or C.PinkDeep
	end

	local toolButtons: { TextButton } = {}
	local function toolButton(order: number, icon: string, caption: string, tip: string, color: Color3): TextButton
		local size = Interface.IsTouch() and Theme.TouchTarget or 40
		local button = UIUtil.Create("TextButton", {
			Name = caption,
			Size = UDim2.fromOffset(size + 6, size + 12),
			BackgroundColor3 = color,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = order,
			ZIndex = 22,
			Parent = bar,
		})
		UIUtil.Corner(button, 14)
		UIUtil.Gradient(button, ColorSequence.new(WHITE, Color3.fromRGB(228, 228, 228)), 90)
		UIUtil.Create("TextLabel", {
			Name = "Icon",
			Size = UDim2.new(1, 0, 1, -14),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = icon,
			TextColor3 = C.Ink,
			TextSize = math.floor(size * 0.5),
			ZIndex = 23,
			Parent = button,
		})
		UIUtil.Create("TextLabel", {
			Name = "Caption",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 1, 1, -2),
			Size = UDim2.new(1, -2, 0, 12),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = Locale.T(caption),
			TextColor3 = C.Ink,
			TextScaled = true,
			ZIndex = 23,
			Parent = button,
		})
		UIUtil.AnimateButton(button, 1.08, 0.9)
		-- Infobulle (souris) : nom + raccourci à la place du nom de l'objet
		button.MouseEnter:Connect(function()
			if not Interface.IsTouch() then
				hoverTip = icon .. " " .. Locale.T(tip)
				refreshNameChip()
			end
		end)
		button.MouseLeave:Connect(function()
			hoverTip = nil
			refreshNameChip()
		end)
		table.insert(toolButtons, button)
		return button
	end
	local smallerButton = toolButton(1, "➖", "Smaller", "Smaller  ( - )", C.LilacSoft)
	local biggerButton = toolButton(2, "➕", "Bigger", "Bigger  ( + )", C.LilacSoft)
	local backButton = toolButton(3, "⏬", "Back", "Send backward  ( Page Down )", C.MintSoft)
	local frontButton = toolButton(4, "⏫", "Front", "Bring forward  ( Page Up )", C.MintSoft)
	local copyButton = toolButton(5, "📑", "Copy", "Duplicate  ( Ctrl+D )", Color3.fromRGB(255, 240, 200))
	local sendButton = toolButton(6, "🚪", "Send", "Send to another room", Color3.fromRGB(214, 236, 255))
	local storeButton = toolButton(7, "📦", "Store", "Store in inventory  ( Delete )", C.PinkSoft)

	-- Pastille "+2 ❤️" etc. au-dessus d'un objet (calque des effets)
	local function floatAt(sticker: Sticker, text: string, color: Color3)
		local layer = Effects.GetLayer()
		if not layer or not sticker.Frame.Parent then
			return
		end
		local center = Interface.GetCanvasCenter(sticker.Body)
		Effects.FloatingText(layer, UDim2.fromOffset(center.X, center.Y - 20), text, color, 26)
	end

	local function burstAt(sticker: Sticker, color: Color3?, count: number?)
		local layer = Effects.GetLayer()
		if not layer or not sticker.Frame.Parent then
			return
		end
		local center = Interface.GetCanvasCenter(sticker.Body)
		Effects.Burst(layer, UDim2.fromOffset(center.X, center.Y), color, count or 8)
	end

	----------------------------------------------------------------------
	-- Pièce, exemplaires
	----------------------------------------------------------------------

	local function currentRoomData(): HouseCommon.Room?
		return HouseCommon.GetRoom(house, roomId)
	end

	local function roomItems(): number
		return HouseCommon.GetSize(house).RoomItems
	end

	-- Dispositions locales (pièce ouverte + envois en attente)
	local function overrides(): HouseCommon.Overrides
		local result: HouseCommon.Overrides = {}
		for id, list in pairs(extras) do
			result[id] = list
		end
		if roomId then
			result[roomId :: string] = layout
		end
		return result
	end

	local function available(itemId: string): number
		return HouseCommon.Available(house, itemId, overrides())
	end

	-- Disposition actuelle d'une autre pièce (envoi en attente, sinon serveur)
	local function layoutOfRoom(id: string): { Placed }
		if id == roomId then
			return layout
		end
		local pendingList = extras[id]
		if pendingList then
			return pendingList
		end
		local other = HouseCommon.GetRoom(house, id)
		return other and other.Placed or {}
	end

	----------------------------------------------------------------------
	-- Profondeur et barre d'outils
	----------------------------------------------------------------------

	-- Clé de tri : (zone, couche Z, Y, X)
	local function sortedEntries(): { Placed }
		local list = table.clone(layout)
		table.sort(list, function(a, b)
			local sa, sb = stickers[a], stickers[b]
			local ra = sa and zoneRank(sa) or 2
			local rb = sb and zoneRank(sb) or 2
			if ra ~= rb then
				return ra < rb
			end
			if a.Z ~= b.Z then
				return a.Z < b.Z
			end
			if a.Y ~= b.Y then
				return a.Y < b.Y
			end
			return a.X < b.X
		end)
		return list
	end

	local function resort()
		for index, entry in ipairs(sortedEntries()) do
			local sticker = stickers[entry]
			if sticker then
				local dragged = drag ~= nil and (drag :: Drag).Entry == entry and (drag :: Drag).Moved
				sticker.Frame.ZIndex = dragged and 5000 or index + 10
			end
		end
	end

	-- Rectangle d'un objet dans la pièce (px de maquette) : (gauche, haut, droite, bas)
	local function rectOf(entry: Placed): (number, number, number, number)
		local sticker = stickers[entry]
		local item = sticker and sticker.Item or HouseCommon.ItemsById[entry.I]
		local size = (item and item.Size or 80) * entry.S
		local cx = entry.X * room.Width
		local flat = sticker ~= nil and sticker.Flat
		local halfW = size * (flat and 0.7 or 0.4)
		if item and item.Placement == "Wall" then
			local cy = entry.Y * room.Height
			return cx - halfW, cy - size * 0.42, cx + halfW, cy + size * 0.42
		end
		local bottom = entry.Y * room.Height
		local top = bottom - size * (flat and 0.4 or 0.9)
		return cx - halfW, top, cx + halfW, bottom
	end

	local function overlaps(a: Placed, b: Placed): boolean
		local al, at, ar, ab = rectOf(a)
		local bl, bt, br, bb = rectOf(b)
		return al < br and bl < ar and at < bb and bt < ab
	end

	local function positionToolbar()
		local entry = selected
		if not entry or not editing or (drag ~= nil and (drag :: Drag).Moved) then
			toolbar.Visible = false
			return
		end
		local sticker = stickers[entry]
		if not sticker then
			toolbar.Visible = false
			return
		end
		local scale = math.max(0.2, room.Scale)
		toolbarScale.Scale = 1 / scale
		local _, top, _, bottom = rectOf(entry)
		local toolbarSize = toolbar.AbsoluteSize
		local pixelRatio = room.Frame.AbsoluteSize.X / math.max(1, room.Width)
		local heightInRoom = pixelRatio > 0 and toolbarSize.Y / pixelRatio or 110 / scale
		local widthInRoom = pixelRatio > 0 and toolbarSize.X / pixelRatio or 400 / scale
		local x = math.clamp(entry.X * room.Width, widthInRoom / 2 - 10, room.Width - widthInRoom / 2 + 10)
		if top - heightInRoom - 8 >= -14 then
			toolbar.AnchorPoint = Vector2.new(0.5, 1)
			toolbar.Position = UDim2.fromOffset(x, top - 6)
		else
			toolbar.AnchorPoint = Vector2.new(0.5, 0)
			toolbar.Position = UDim2.fromOffset(x, math.min(bottom + 6, room.Height - heightInRoom + 10))
		end
		toolbar.Visible = true
	end

	local function setDisabled(button: TextButton, disabled: boolean)
		button.BackgroundTransparency = disabled and 0.55 or 0
		local icon = button:FindFirstChild("Icon") :: TextLabel?
		if icon then
			icon.TextTransparency = disabled and 0.5 or 0
		end
	end

	local function refreshToolbarText()
		local entry = selected
		local item = entry and HouseCommon.ItemsById[entry.I]
		if not item then
			return
		end
		local roomData = currentRoomData()
		local comfort = HouseCommon.PlacedComfort(roomData, item)
		local favorite = HouseCommon.IsFavorite(roomData, item)
		nameText = string.format("%s %s  ❤️+%s%s", item.Icon, HouseCommon.Name(item), HouseCommon.FormatPercent(comfort), favorite and "  ✨" or "")
		refreshNameChip()
		local s = (entry :: Placed).S
		setDisabled(smallerButton, s <= HouseCommon.MIN_SCALE + 1e-3)
		setDisabled(biggerButton, s >= HouseCommon.MAX_SCALE - 1e-3)
		setDisabled(copyButton, available(item.Id) <= 0 or #layout >= roomItems())
		setDisabled(sendButton, #house.Rooms < 2)
	end

	local function setSelected(entry: Placed?)
		if selected == entry then
			positionToolbar()
			return
		end
		local previous = selected
		if previous and stickers[previous] then
			room.ShowRing(stickers[previous], false)
		end
		selected = entry
		hoverTip = nil
		if entry and stickers[entry] then
			local sticker = stickers[entry]
			room.ShowRing(sticker, editing)
			refreshToolbarText()
			if editing then
				UIUtil.Pop(bar, 0.6, 0.3)
			end
		end
		positionToolbar()
		-- (taille réelle de la barre connue à l'image suivante)
		task.defer(positionToolbar)
		selectionChanged:Fire(entry)
	end

	----------------------------------------------------------------------
	-- Sauvegarde automatique
	----------------------------------------------------------------------

	local doSave: () -> ()

	local function markDirty(now: boolean?)
		dirty = true
		saveAt = now and os.clock() or os.clock() + SAVE_DELAY
		saveStatusChanged:Fire("dirty")
		changed:Fire()
		if selected then
			refreshToolbarText()
		end
	end

	doSave = function()
		if saving or not dirty then
			return
		end
		local savedRoom = roomId
		if not savedRoom then
			dirty = false
			return
		end
		saving = true
		dirty = false
		-- Mêmes arrondis que le serveur : la disposition renvoyée sera identique
		for _, entry in ipairs(layout) do
			if not (drag ~= nil and (drag :: Drag).Entry == entry) then
				entry.X = roundTo(entry.X, 0.0001)
				entry.Y = roundTo(entry.Y, 0.0001)
				entry.S = roundTo(entry.S, 0.001)
				entry.Z = math.clamp(math.floor(entry.Z), 0, HouseCommon.MAX_Z)
			end
		end
		local rooms: { [string]: { Placed } } = {}
		for id, list in pairs(extras) do
			if HouseCommon.GetRoom(house, id) then
				rooms[id] = payloadOf(list)
			end
		end
		rooms[savedRoom :: string] = payloadOf(layout)
		local savedSignature = signature(layout)
		saveStatusChanged:Fire("saving")
		task.spawn(function()
			local ok, message = HouseCommon.Invoke("saveLayout", { Rooms = rooms })
			saving = false
			if ok then
				failures = 0
				blockUntil = os.clock() + SYNC_BLOCK
				if savedRoom == roomId then
					lastSignature = savedSignature
				end
				if dirty then
					saveAt = math.max(saveAt, os.clock() + 0.6)
					saveStatusChanged:Fire("dirty")
				else
					saveStatusChanged:Fire("saved")
				end
				return
			end
			failures += 1
			if failures <= 2 then
				-- Refus passager (trop rapide, réseau) : on réessaie un peu plus tard
				dirty = true
				saveAt = os.clock() + RETRY_DELAY * failures
				saveStatusChanged:Fire("dirty")
				return
			end
			failures = 0
			table.clear(extras)
			saveStatusChanged:Fire("error")
			notify(message or Locale.T("Couldn't save your room, try again."), Theme.Colors.Red)
			-- On revient à la dernière disposition connue du serveur
			blockUntil = 0
			editor.Sync(house, true)
		end)
	end

	----------------------------------------------------------------------
	-- Historique (annuler / rétablir), par pièce
	----------------------------------------------------------------------

	local function historyOf(id: string?): History?
		if not id then
			return nil
		end
		local history = histories[id :: string]
		if not history then
			history = { Undo = {}, Redo = {} }
			histories[id :: string] = history
		end
		return history
	end

	-- À appeler AVANT une modification (before = disposition avant, si déjà copiée)
	local function pushUndo(before: { Placed }?, cross: Cross?)
		local history = historyOf(roomId)
		if not history then
			return
		end
		table.insert(history.Undo, { Layout = before or copyList(layout), Cross = cross })
		while #history.Undo > HISTORY_STEPS do
			table.remove(history.Undo, 1)
		end
		table.clear(history.Redo)
		lastNudgeEntry = nil
		historyChanged:Fire()
	end

	----------------------------------------------------------------------
	-- Autocollants
	----------------------------------------------------------------------

	local endDrag: () -> ()

	local function wiggle(sticker: Sticker)
		local body = sticker.Body
		body.Rotation = -10
		UIUtil.Tween(body, 0.5, { Rotation = 0 }, Enum.EasingStyle.Elastic)
		sticker.Pop.Scale = 1.15
		UIUtil.Tween(sticker.Pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	local function beginDrag(entry: Placed, input: InputObject)
		local pointer = room.ScreenToRoom(Vector2.new(input.Position.X, input.Position.Y))
		drag = {
			Entry = entry,
			Input = input,
			Offset = Vector2.new(entry.X, entry.Y) - pointer,
			Target = Vector2.new(entry.X, entry.Y),
			Start = Vector2.new(input.Position.X, input.Position.Y),
			Moved = false,
			Before = copyList(layout),
		}
	end

	local function attachSticker(entry: Placed): Sticker?
		local item = HouseCommon.ItemsById[entry.I]
		if not item then
			return nil
		end
		local sticker = room.CreateSticker(item, entry)
		stickers[entry] = sticker
		sticker.Hit.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
				return
			end
			if not editing then
				wiggle(sticker)
				burstAt(sticker, C.Pink, 6)
				SoundManager.Play("Pop", 0.9 + math.random() * 0.3)
				return
			end
			local current = drag
			if current then
				-- Ancien glissement dont la fin a été perdue (bouton relâché hors de la fenêtre)
				if current.Input.UserInputState == Enum.UserInputState.End or current.Input.UserInputState == Enum.UserInputState.Cancel then
					endDrag()
				else
					return
				end
			end
			setSelected(entry)
			beginDrag(entry, input)
		end)
		sticker.Hit.MouseEnter:Connect(function()
			if editing and not drag then
				UIUtil.Tween(sticker.Pop, 0.12, { Scale = 1.05 }, Enum.EasingStyle.Back)
			end
		end)
		sticker.Hit.MouseLeave:Connect(function()
			if not drag or (drag :: Drag).Entry ~= entry then
				UIUtil.Tween(sticker.Pop, 0.12, { Scale = 1 })
			end
		end)
		return sticker
	end

	local function clearStickers()
		for _, sticker in pairs(stickers) do
			room.DestroySticker(sticker)
		end
		table.clear(stickers)
	end

	local function rebuildFrom(list: { Placed }, keepSelection: boolean?)
		local keepIndex: number? = nil
		if selected and keepSelection ~= false then
			keepIndex = table.find(layout, selected :: Placed)
		end
		drag = nil
		room.SetZoneHint(nil)
		room.SetGrid(false)
		clearStickers()
		layout = {}
		for _, entry in ipairs(list) do
			local copy = { I = entry.I, X = entry.X, Y = entry.Y, S = entry.S, Z = entry.Z }
			if attachSticker(copy) then
				table.insert(layout, copy)
			end
		end
		selected = nil
		-- Même objet toujours là (même place dans la liste) : il reste sélectionné
		if keepIndex and layout[keepIndex] then
			setSelected(layout[keepIndex])
		else
			setSelected(nil)
		end
		resort()
		changed:Fire()
	end

	-- Garde seulement les exemplaires possédés (hors autres pièces)
	local function trimToOwned(list: { Placed }): ({ Placed }, number)
		local others = overrides()
		if roomId then
			others[roomId :: string] = {}
		end
		local kept: { Placed } = {}
		local counts: { [string]: number } = {}
		local dropped = 0
		for _, entry in ipairs(list) do
			local free = HouseCommon.Available(house, entry.I, others)
			local used = counts[entry.I] or 0
			if used < free and #kept < roomItems() then
				counts[entry.I] = used + 1
				table.insert(kept, entry)
			else
				dropped += 1
			end
		end
		return kept, dropped
	end

	----------------------------------------------------------------------
	-- Actions de la barre d'outils
	----------------------------------------------------------------------

	local function refuse(button: GuiObject, text: string?)
		SoundManager.Play("Error", 0.8)
		UIUtil.Shake(button)
		if text then
			notify(text, Theme.Colors.Orange)
		end
	end

	local function applyEntry(entry: Placed)
		local sticker = stickers[entry]
		if sticker then
			sticker.Frame.Position = UDim2.fromScale(entry.X, entry.Y)
		end
	end

	local function snapPoint(item: Item, x: number, y: number, s: number): (number, number)
		if snapEnabled then
			local stepX = GRID / math.max(1, room.Width)
			local stepY = GRID / math.max(1, room.Height)
			x = roundTo(x, stepX)
			y = roundTo(y, stepY)
		end
		return HouseCommon.ClampPosition(item, x, y, s, room.Width, room.Height)
	end

	local function resize(delta: number, button: GuiObject)
		local entry = selected
		local sticker = entry and stickers[entry]
		if not entry or not sticker then
			return
		end
		local newScale = math.clamp(roundTo(entry.S + delta, 0.01), HouseCommon.MIN_SCALE, HouseCommon.MAX_SCALE)
		if math.abs(newScale - entry.S) < 1e-3 then
			refuse(button)
			return
		end
		pushUndo()
		entry.S = newScale
		-- Plus grand : l'objet doit rester dans sa zone
		entry.X, entry.Y = HouseCommon.ClampPosition(sticker.Item, entry.X, entry.Y, entry.S, room.Width, room.Height)
		sticker.Frame.Position = UDim2.fromScale(entry.X, entry.Y)
		UIUtil.Tween(sticker.Scale, 0.2, { Scale = sticker.Item.Size * newScale / 100 }, Enum.EasingStyle.Back)
		local ringStroke = sticker.RingStroke
		if ringStroke then
			ringStroke.Thickness = 3 / math.max(0.2, sticker.Item.Size * newScale / 100)
		end
		SoundManager.Play("Click", delta > 0 and 1.2 or 0.85)
		task.delay(0.21, positionToolbar)
		markDirty()
	end

	-- Devant / derrière : passe devant (ou derrière) TOUS les objets qui le chevauchent
	local function restack(forward: boolean, button: GuiObject)
		local entry = selected
		local sticker = entry and stickers[entry]
		if not entry or not sticker then
			return
		end
		local order = sortedEntries()
		local myIndex = table.find(order, entry) or 0
		local rank = zoneRank(sticker)
		local targetZ: number? = nil
		for index, other in ipairs(order) do
			local otherSticker = stickers[other]
			if other ~= entry and otherSticker and zoneRank(otherSticker) == rank and overlaps(entry, other) then
				if forward and index > myIndex then
					targetZ = math.max(targetZ or -math.huge, other.Z + 1)
				elseif not forward and index < myIndex then
					targetZ = math.min(targetZ or math.huge, other.Z - 1)
				end
			end
		end
		if targetZ == nil then
			refuse(button, forward and Locale.T("Already in front!") or Locale.T("Already at the back!"))
			return
		end
		pushUndo()
		entry.Z = math.clamp(targetZ :: number, 0, HouseCommon.MAX_Z)
		resort()
		wiggle(sticker)
		SoundManager.Play("Click", forward and 1.15 or 0.9)
		markDirty()
	end

	local function removeEntry(entry: Placed, color: Color3)
		local sticker = stickers[entry]
		local index = table.find(layout, entry)
		if not index then
			return
		end
		table.remove(layout, index)
		stickers[entry] = nil
		setSelected(nil)
		if sticker then
			burstAt(sticker, color, 8)
			UIUtil.Tween(sticker.Pop, 0.18, { Scale = 0.1 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.delay(0.19, function()
				room.DestroySticker(sticker)
			end)
		end
		resort()
	end

	local function store(entry: Placed)
		if not table.find(layout, entry) then
			return
		end
		pushUndo()
		removeEntry(entry, C.Lilac)
		SoundManager.Play("Pop", 0.7)
		markDirty()
	end

	-- Petit déplacement au clavier (dx, dy en px de maquette)
	local function nudge(dx: number, dy: number)
		local entry = selected
		local sticker = entry and stickers[entry]
		if not entry or not sticker or drag then
			return
		end
		local now = os.clock()
		if lastNudgeEntry ~= entry or now - lastNudge > NUDGE_MERGE then
			pushUndo()
			lastNudgeEntry = entry
		end
		lastNudge = now
		local x = entry.X + dx / math.max(1, room.Width)
		local y = entry.Y + dy / math.max(1, room.Height)
		entry.X, entry.Y = snapPoint(sticker.Item, x, y, entry.S)
		applyEntry(entry)
		resort()
		positionToolbar()
		markDirty()
	end

	-- Endroit libre (peu de chevauchements) dans la zone de l'objet
	local function freeSpot(item: Item, list: { Placed }): (number, number)
		local minY, maxY = HouseCommon.ZoneBounds(item.Placement)
		local best: Vector2? = nil
		local bestScore = math.huge
		local probe: Placed = { I = item.Id, X = 0.5, Y = (minY + maxY) / 2, S = 1, Z = HouseCommon.DEFAULT_Z }
		for attempt = 1, 16 do
			local x = 0.14 + math.random() * 0.72
			local y
			if item.Placement == "Wall" then
				y = minY + (maxY - minY) * (0.25 + math.random() * 0.5)
			else
				y = minY + (maxY - minY) * (0.35 + math.random() * 0.55)
			end
			probe.X, probe.Y = HouseCommon.ClampPosition(item, x, y, 1, room.Width, room.Height)
			local score = 0
			for _, other in ipairs(list) do
				if overlaps(probe, other) then
					score += 1
				end
			end
			-- Un peu de préférence pour le centre (on voit l'objet arriver)
			score += math.abs(probe.X - 0.5) * 0.4 + attempt * 0.001
			if score < bestScore then
				bestScore = score
				best = Vector2.new(probe.X, probe.Y)
			end
		end
		local spot = best or Vector2.new(0.5, (minY + maxY) / 2)
		return spot.X, spot.Y
	end

	local function canPlace(itemId: string): (boolean, string?)
		local item = HouseCommon.ItemsById[itemId]
		if not item or not roomId then
			return false, nil
		end
		if available(itemId) <= 0 then
			return false, Locale.T("Buy one in the shop first!")
		end
		local maxItems = roomItems()
		if #layout >= maxItems then
			return false, Locale.T("This room is full (%d items)! Decorate another room 🏡", maxItems)
		end
		return true, nil
	end

	-- Nouvelle entrée dans la pièce (arrivée animée), déjà validée
	local function addEntry(entry: Placed, fromAbove: boolean)
		local item = HouseCommon.ItemsById[entry.I]
		table.insert(layout, entry)
		local sticker = attachSticker(entry)
		if sticker then
			sticker.Pop.Scale = 0.2
			UIUtil.Tween(sticker.Pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			if fromAbove then
				sticker.Body.Position = UDim2.fromOffset(0, -40)
				UIUtil.Tween(sticker.Body, 0.45, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Bounce)
			end
			local comfort = HouseCommon.PlacedComfort(currentRoomData(), item)
			task.delay(0.3, function()
				burstAt(sticker, C.Pink, 10)
				floatAt(sticker, string.format("+%s ❤️", HouseCommon.FormatPercent(comfort)), C.PinkDeep)
			end)
		end
		SoundManager.Play("Pop", 1.1)
		resort()
	end

	local function place(itemId: string): boolean
		local ok, reason = canPlace(itemId)
		if not ok then
			if reason then
				notify(reason, Theme.Colors.Orange)
			end
			SoundManager.Play("Error", 0.8)
			return false
		end
		local item = HouseCommon.ItemsById[itemId]
		pushUndo()
		local x, y = freeSpot(item, layout)
		x, y = snapPoint(item, x, y, 1)
		-- Nouvelle couche au-dessus des objets qu'il chevauche
		local entry: Placed = { I = itemId, X = x, Y = y, S = 1, Z = HouseCommon.DEFAULT_Z }
		for _, other in ipairs(layout) do
			if overlaps(entry, other) then
				entry.Z = math.max(entry.Z, other.Z)
			end
		end
		addEntry(entry, true)
		if editing then
			setSelected(entry)
		end
		markDirty()
		return true
	end

	local function duplicate(): boolean
		local entry = selected
		local sticker = entry and stickers[entry]
		if not entry or not sticker then
			return false
		end
		local ok, reason = canPlace(entry.I)
		if not ok then
			refuse(copyButton, available(entry.I) <= 0 and Locale.T("No other copy in your inventory: buy one in the shop!") or reason)
			return false
		end
		pushUndo()
		local offset = math.max(GRID, sticker.Item.Size * entry.S * 0.35)
		local x = entry.X + offset / math.max(1, room.Width)
		if x > 0.9 then
			x = entry.X - offset / math.max(1, room.Width)
		end
		local copy: Placed = { I = entry.I, X = x, Y = entry.Y, S = entry.S, Z = math.min(HouseCommon.MAX_Z, entry.Z + 1) }
		copy.X, copy.Y = snapPoint(sticker.Item, copy.X, copy.Y, copy.S)
		addEntry(copy, false)
		setSelected(copy)
		markDirty()
		return true
	end

	-- Envoie l'objet sélectionné dans une autre pièce (sauvegarde des 2 pièces)
	local function sendTo(targetId: string): boolean
		local entry = selected
		local sticker = entry and stickers[entry]
		local target = HouseCommon.GetRoom(house, targetId)
		if not entry or not sticker or not target or targetId == roomId then
			return false
		end
		local targetList = copyList(layoutOfRoom(targetId))
		if #targetList >= roomItems() then
			refuse(sendButton, Locale.T("This room is full (%d items)! Decorate another room 🏡", roomItems()))
			return false
		end
		local item = sticker.Item
		local before = copyList(targetList)
		local x, y = freeSpot(item, targetList)
		local z = HouseCommon.DEFAULT_Z
		for _, other in ipairs(targetList) do
			z = math.max(z, other.Z)
		end
		table.insert(targetList, { I = entry.I, X = x, Y = y, S = entry.S, Z = z })
		pushUndo(nil, { Room = targetId, Before = before, After = copyList(targetList) })
		extras[targetId] = targetList
		floatAt(sticker, "🚪 → " .. HouseCommon.GetRoomType(target).Icon, C.Lilac)
		removeEntry(entry, C.Sky)
		SoundManager.Play("Open", 1.3)
		local roomType = HouseCommon.GetRoomType(target)
		notify(Locale.T("%s sent to %s", item.Icon .. " " .. HouseCommon.Name(item), roomType.Icon .. " " .. HouseCommon.Name(roomType)), C.Lilac)
		markDirty(true)
		return true
	end

	-- Applique une étape d'historique ; renvoie l'étape inverse
	local function applyStep(step: Step): Step
		local inverse: Step = { Layout = copyList(layout), Cross = nil }
		local cross = step.Cross
		if cross then
			local current = layoutOfRoom(cross.Room)
			-- (l'autre pièce a changé depuis : on ne touche plus à elle)
			if HouseCommon.GetRoom(house, cross.Room) and signature(current) == signature(cross.After) then
				extras[cross.Room] = copyList(cross.Before)
				inverse.Cross = { Room = cross.Room, Before = copyList(cross.After), After = copyList(cross.Before) }
			end
		end
		local list, dropped = trimToOwned(copyList(step.Layout))
		rebuildFrom(list, false)
		if dropped > 0 then
			notify(Locale.T("Some items are already used in another room"), Theme.Colors.Orange)
		end
		return inverse
	end

	local function undo(): boolean
		local history = historyOf(roomId)
		if not history or #history.Undo == 0 or drag then
			SoundManager.Play("Error", 0.7)
			return false
		end
		local step = table.remove(history.Undo) :: Step
		table.insert(history.Redo, applyStep(step))
		lastNudgeEntry = nil
		SoundManager.Play("Click", 0.8)
		markDirty(true)
		historyChanged:Fire()
		return true
	end

	local function redo(): boolean
		local history = historyOf(roomId)
		if not history or #history.Redo == 0 or drag then
			SoundManager.Play("Error", 0.7)
			return false
		end
		local step = table.remove(history.Redo) :: Step
		table.insert(history.Undo, applyStep(step))
		lastNudgeEntry = nil
		SoundManager.Play("Click", 1.1)
		markDirty(true)
		historyChanged:Fire()
		return true
	end

	smallerButton.Activated:Connect(function()
		resize(-HouseCommon.SCALE_STEP, smallerButton)
	end)
	biggerButton.Activated:Connect(function()
		resize(HouseCommon.SCALE_STEP, biggerButton)
	end)
	frontButton.Activated:Connect(function()
		restack(true, frontButton)
	end)
	backButton.Activated:Connect(function()
		restack(false, backButton)
	end)
	copyButton.Activated:Connect(function()
		duplicate()
	end)
	sendButton.Activated:Connect(function()
		local entry = selected
		if not entry then
			return
		end
		if #house.Rooms < 2 then
			refuse(sendButton, Locale.T("Buy another room first! 🏡"))
			return
		end
		local handler = sendHandler
		if handler then
			handler(entry)
		end
	end)
	storeButton.Activated:Connect(function()
		local entry = selected
		if entry then
			store(entry)
		end
	end)

	room.BackgroundHit.Activated:Connect(function()
		if not drag then
			setSelected(nil)
		end
	end)
	room.Changed:Connect(positionToolbar)

	----------------------------------------------------------------------
	-- Glisser-déposer (souris + tactile)
	----------------------------------------------------------------------

	endDrag = function()
		local current = drag
		if not current then
			return
		end
		drag = nil
		local entry = current.Entry
		local sticker = stickers[entry]
		room.SetZoneHint(nil)
		room.SetGrid(false)
		if not sticker then
			return
		end
		if current.Moved then
			pushUndo(current.Before)
			entry.X, entry.Y = current.Target.X, current.Target.Y
			sticker.Frame.Position = UDim2.fromScale(entry.X, entry.Y)
			-- "Plop" : l'objet se pose avec un petit rebond
			UIUtil.Tween(sticker.Body, 0.16, { Position = UDim2.fromOffset(0, 0), Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			sticker.Pop.Scale = 0.92
			UIUtil.Tween(sticker.Pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			SoundManager.Play("Pop", 1.05 + math.random() * 0.15)
			resort()
			markDirty()
		else
			UIUtil.Tween(sticker.Pop, 0.12, { Scale = 1 })
			sticker.Body.Rotation = 0
		end
		positionToolbar()
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local current = drag
		if not current or not active then
			return
		end
		local kind = input.UserInputType
		local startedWithMouse = current.Input.UserInputType == Enum.UserInputType.MouseButton1
		local matches = (kind == Enum.UserInputType.MouseMovement and startedWithMouse)
			or (kind == Enum.UserInputType.Touch and input == current.Input)
		if not matches then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if not current.Moved then
			if (position - current.Start).Magnitude < DRAG_THRESHOLD then
				return
			end
			current.Moved = true
			local sticker = stickers[current.Entry]
			if sticker then
				UIUtil.Tween(sticker.Pop, 0.15, { Scale = LIFT_SCALE }, Enum.EasingStyle.Back)
				UIUtil.Tween(sticker.Body, 0.15, { Position = UDim2.fromOffset(0, -8) })
				room.SetZoneHint(sticker.Item.Placement)
				room.SetGrid(snapEnabled, GRID)
				SoundManager.Play("Click", 1.3)
			end
			resort()
			toolbar.Visible = false
		end
		local sticker = stickers[current.Entry]
		if not sticker then
			return
		end
		local pointer = room.ScreenToRoom(position) + current.Offset
		local x, y = snapPoint(sticker.Item, pointer.X, pointer.Y, current.Entry.S)
		current.Target = Vector2.new(x, y)
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local current = drag
		if not current then
			return
		end
		local kind = input.UserInputType
		local startedWithMouse = current.Input.UserInputType == Enum.UserInputType.MouseButton1
		if (kind == Enum.UserInputType.MouseButton1 and startedWithMouse) or (kind == Enum.UserInputType.Touch and input == current.Input) then
			endDrag()
		end
	end)

	-- Raccourcis clavier (PC)
	local function isDown(a: Enum.KeyCode, b: Enum.KeyCode): boolean
		return UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b)
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not active or not editing or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local key = input.KeyCode
		local ctrl = isDown(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)
			or isDown(Enum.KeyCode.LeftMeta, Enum.KeyCode.RightMeta)
		local shift = isDown(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
		if ctrl and key == Enum.KeyCode.Z then
			if shift then
				redo()
			else
				undo()
			end
			return
		elseif ctrl and key == Enum.KeyCode.Y then
			redo()
			return
		elseif key == Enum.KeyCode.G and not ctrl then
			editor.SetSnap(not snapEnabled)
			return
		end
		local entry = selected
		if not entry then
			return
		end
		local step = snapEnabled and GRID or (shift and NUDGE_BIG or NUDGE_SMALL)
		if ctrl and key == Enum.KeyCode.D then
			duplicate()
		elseif key == Enum.KeyCode.Delete or key == Enum.KeyCode.Backspace then
			store(entry)
		elseif key == Enum.KeyCode.Equals or key == Enum.KeyCode.KeypadPlus then
			resize(HouseCommon.SCALE_STEP, biggerButton)
		elseif key == Enum.KeyCode.Minus or key == Enum.KeyCode.KeypadMinus then
			resize(-HouseCommon.SCALE_STEP, smallerButton)
		elseif key == Enum.KeyCode.PageUp then
			restack(true, frontButton)
		elseif key == Enum.KeyCode.PageDown then
			restack(false, backButton)
		elseif key == Enum.KeyCode.Left then
			nudge(-step, 0)
		elseif key == Enum.KeyCode.Right then
			nudge(step, 0)
		elseif key == Enum.KeyCode.Up then
			nudge(0, -step)
		elseif key == Enum.KeyCode.Down then
			nudge(0, step)
		elseif key == Enum.KeyCode.Escape then
			setSelected(nil)
		end
	end)

	-- Taille des boutons (tactile : zones de 44 px)
	Interface.DeviceChanged:Connect(function()
		local size = Interface.IsTouch() and Theme.TouchTarget or 40
		for _, button in ipairs(toolButtons) do
			button.Size = UDim2.fromOffset(size + 6, size + 12)
			local icon = button:FindFirstChild("Icon") :: TextLabel?
			if icon then
				icon.TextSize = math.floor(size * 0.5)
			end
		end
	end)

	----------------------------------------------------------------------
	-- API
	----------------------------------------------------------------------

	editor = {
		Changed = changed,
		SaveStatusChanged = saveStatusChanged,
		SelectionChanged = selectionChanged,
		HistoryChanged = historyChanged,
		SetEditing = function(value: boolean)
			if editing == value then
				return
			end
			editing = value
			if not value then
				if drag then
					endDrag()
				end
				setSelected(nil)
			end
			local current = selected
			if current and stickers[current] then
				room.ShowRing(stickers[current], value)
			end
			positionToolbar()
		end,
		IsEditing = function(): boolean
			return editing
		end,
		SetActive = function(value: boolean)
			active = value
			if not value and drag then
				endDrag()
			end
		end,
		SetRoom = function(newRoomId: string)
			if newRoomId == roomId then
				return
			end
			if drag then
				endDrag()
			end
			-- La pièce quittée part tout de suite (avec les envois en attente)
			if dirty and not saving then
				doSave()
			elseif dirty then
				-- (sauvegarde en cours : la pièce quittée garde sa disposition locale)
				if roomId then
					extras[roomId :: string] = copyList(layout)
				end
				saveAt = os.clock()
			end
			setSelected(nil)
			roomId = newRoomId
			local pendingList = extras[newRoomId]
			local target = HouseCommon.GetRoom(house, newRoomId)
			local list = pendingList or (target and target.Placed) or {}
			extras[newRoomId] = nil
			rebuildFrom(list, false)
			lastSignature = target and signature(target.Placed) or ""
			historyChanged:Fire()
		end,
		GetRoomId = function(): string?
			return roomId
		end,
		Sync = function(newHouse: HouseData, force: boolean?)
			house = newHouse
			if force ~= true and (dirty or saving or drag ~= nil or os.clock() < blockUntil) then
				return
			end
			if not dirty and not saving then
				table.clear(extras)
			end
			local target = HouseCommon.GetRoom(newHouse, roomId)
			if not target then
				return
			end
			local serverSignature = signature(target.Placed)
			if serverSignature == lastSignature and force ~= true then
				return
			end
			if force == true then
				dirty = false
			end
			lastSignature = serverSignature
			rebuildFrom(target.Placed)
		end,
		GetLayout = function(): { Placed }
			return layout
		end,
		Overrides = overrides,
		Available = available,
		CanPlace = canPlace,
		Place = place,
		Select = function(index: number)
			local entry = layout[index]
			if entry then
				setSelected(entry)
			end
		end,
		Deselect = function()
			setSelected(nil)
		end,
		GetSelected = function(): Placed?
			return selected
		end,
		Duplicate = duplicate,
		SendTo = sendTo,
		SetSendHandler = function(handler: (entry: Placed) -> ())
			sendHandler = handler
		end,
		Undo = undo,
		Redo = redo,
		CanUndo = function(): boolean
			local history = roomId and histories[roomId :: string]
			return history ~= nil and #history.Undo > 0
		end,
		CanRedo = function(): boolean
			local history = roomId and histories[roomId :: string]
			return history ~= nil and #history.Redo > 0
		end,
		SetSnap = function(on: boolean)
			snapEnabled = on
			SoundManager.Play("Click", on and 1.3 or 0.9)
			historyChanged:Fire()
		end,
		GetSnap = function(): boolean
			return snapEnabled
		end,
		Flush = function()
			if drag then
				endDrag()
			end
			if dirty then
				doSave()
			end
		end,
		IsBusy = function(): boolean
			return dirty or saving
		end,
		Update = function(dt: number)
			clock += dt
			local current = drag
			if current and current.Moved then
				local entry = current.Entry
				local sticker = stickers[entry]
				if sticker then
					local alpha = 1 - math.exp(-DRAG_SMOOTHING * dt)
					entry.X += (current.Target.X - entry.X) * alpha
					entry.Y += (current.Target.Y - entry.Y) * alpha
					sticker.Frame.Position = UDim2.fromScale(entry.X, entry.Y)
					-- Petit rebond pendant le transport (pas de rotation : certains
					-- dessins découpent leurs formes, ce qui ne marche pas si on les tourne)
					sticker.Body.Position = UDim2.fromOffset(0, -8 + math.sin(clock * 9) * 2.5)
				end
			end
			-- Contour de sélection qui "respire"
			local entry = selected
			if entry and editing and stickers[entry] then
				local ring = stickers[entry].Ring
				local ringStroke = stickers[entry].RingStroke
				if ring and ringStroke then
					ring.BackgroundTransparency = 0.84 + 0.08 * math.sin(clock * 4)
					ringStroke.Transparency = 0.1 + 0.25 * (0.5 + 0.5 * math.sin(clock * 4))
				end
			end
			-- Sauvegarde automatique
			if dirty and not saving and os.clock() >= saveAt then
				doSave()
			end
		end,
	}

	return editor
end

return HouseEditor
