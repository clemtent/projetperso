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
	  - sélection + BARRE D'OUTILS "bonbons" (House/HouseButtons) près de
	    l'objet (ou en bas de la scène sur téléphone) : vignette + nom +
	    confort + "📍 sur la table", taille ➖ 100 % ➕, ⏬ derrière /
	    ⏫ devant, ↔️ retourner (miroir), 📑 copier, 🚪 envoyer dans une
	    autre pièce, 📦 ranger (rouge) ; bulle au survol (nom + raccourci) ;
	    les clics dans la barre ne désélectionnent jamais l'objet ;
	  - ANNULER / RÉTABLIR (30 étapes par pièce ; Ctrl+Z / Ctrl+Y) ;
	  - clavier : flèches = petit déplacement (Maj = plus grand), + / - =
	    taille, Page préc. / suiv. = couche, F = retourner, Suppr = ranger,
	    Ctrl+D = dupliquer, Échap = désélectionner, G = aimant ;
	  - pose depuis l'inventaire (Place) à un endroit libre : petite déco
	    directement SUR un meuble (nourriture sur une table, coussin sur le
	    lit...), chaise directement À UNE TABLE ;
	  - sauvegarde automatique "saveLayout" { Rooms = { [pièce] = ... } }
	    ~1,5 s après la dernière modification (les 2 pièces d'un envoi
	    partent dans le même appel) ; nouvel essai si le serveur refuse,
	    puis resynchro ;
	  - hors édition : toucher un objet le fait rebondir (petits cœurs) ;
	  - SUR LES MEUBLES (House/HouseSurfaces) : un petit objet glissé
	    au-dessus d'une table, d'un bureau, d'une étagère, d'un lit, d'un
	    canapé, d'une chaise... s'y pose : pendant le glissement, toutes les
	    places possibles s'allument, le dessus visé brille avec une étiquette
	    "✨ Poser sur : Table à manger" et le meuble est entouré ;
	  - CHAISES À TABLE : une chaise / un tabouret glissé près d'une table
	    se range à gauche ou à droite (tournée vers elle), derrière (le
	    dossier dépasse) ou devant ; déplacer / agrandir la table emporte ses
	    chaises et ce qui est posé dessus ; ranger la table fait tomber ce
	    qui était posé dessus (les chaises restent) ;
	  - ANIMAUX : hors édition, les animaux de la pièce se promènent et
	    utilisent leurs affaires (House/HousePets, visuel seulement).
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
local HouseSurfaces = require(script.Parent.HouseSurfaces)
local HousePets = require(script.Parent.HousePets)
local HouseArt = require(script.Parent.HouseArt)
local HouseButtons = require(script.Parent.HouseButtons)

type Placed = HouseCommon.Placed
type HouseData = HouseCommon.HouseData
type Item = HouseCommon.Item
type Room = HouseRoom.Room
type Sticker = HouseRoom.Sticker
type Candy = HouseButtons.Candy

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
local DOCK_BELOW = 760 -- (px de maquette) scène plus étroite : barre d'outils en bas de la scène

local C = HouseCommon.Colors
local P = HouseButtons.Palette
local WHITE = Color3.new(1, 1, 1)
local SEAT_TINT = Color3.fromRGB(56, 176, 140) -- étiquette "chaise à table"

export type SaveStatus = "idle" | "dirty" | "saving" | "saved" | "error"

export type Editor = {
	Changed: any, -- Signal () : disposition modifiée (confort, inventaire)
	SaveStatusChanged: any, -- Signal (status: SaveStatus)
	SelectionChanged: any, -- Signal (entry: Placed?)
	HistoryChanged: any, -- Signal () : annuler / rétablir / aimant
	SetEditing: (editing: boolean) -> (),
	IsEditing: () -> boolean,
	SetActive: (active: boolean) -> (),
	SetLive: (visible: boolean) -> (), -- pièce affichée : les animaux vivent
	GetPets: () -> HousePets.Pets,
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
	Flip: () -> boolean,
	SendTo: (roomId: string) -> boolean,
	SetSendHandler: (handler: (entry: Placed) -> ()) -> (),
	SetDockHost: (host: GuiObject?) -> (), -- téléphone : la barre d'outils prend la place de l'inventaire
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

-- Objet posé sur le meuble qu'on déplace (décalage en fractions de la pièce)
type Rider = { Entry: Placed, DX: number, DY: number }

type Drag = {
	Entry: Placed,
	Input: InputObject,
	Offset: Vector2,
	Target: Vector2,
	Start: Vector2,
	Moved: boolean,
	Before: { Placed },
	Riders: { Rider },
	Skip: { [Placed]: boolean },
	Tabletop: boolean, -- peut être posé sur un meuble
	IsSeat: boolean, -- chaise / tabouret : peut se ranger à une table
	Surface: HouseSurfaces.Surface?,
	Seat: HouseSurfaces.SeatSpot?,
	HintKey: string,
	WasOn: boolean, -- posé sur un meuble au début du glissement
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
		parts[index] = string.format("%s:%.4f:%.4f:%.3f:%d%s", entry.I, entry.X, entry.Y, entry.S, math.floor(entry.Z), entry.F and ":F" or "")
	end
	return table.concat(parts, ";")
end

local function copyEntry(entry: Placed): Placed
	return { I = entry.I, X = entry.X, Y = entry.Y, S = entry.S, Z = entry.Z, F = entry.F == true or nil }
end

local function copyList(list: { Placed }): { Placed }
	local result = table.create(#list)
	for index, entry in ipairs(list) do
		result[index] = copyEntry(entry)
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
			F = entry.F == true or nil,
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
	local liveVisible = false
	local pets = HousePets.new(room)

	local changed = Signal.new()
	local saveStatusChanged = Signal.new()
	local selectionChanged = Signal.new()
	local historyChanged = Signal.new()

	----------------------------------------------------------------------
	-- Barre d'outils de sélection ("bonbons")
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
	toolbar:SetAttribute("DarkSkinIgnore", true)
	local toolbarScale = UIUtil.Create("UIScale", { Parent = toolbar })
	local toolbarLayout = UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 5),
		Parent = toolbar,
	})

	-- En-tête : vignette + nom + confort, et où l'objet est posé
	local header = UIUtil.Create("Frame", {
		Name = "Header",
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 21,
		Parent = toolbar,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = header,
	})
	-- (conteneurs = boutons sans action : un clic dans la barre ne traverse
	-- jamais jusqu'à la pièce, qui désélectionnerait l'objet)
	local nameChip = HouseButtons.Container({
		Name = "NameChip",
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.PinkDeep,
		LayoutOrder = 1,
		ZIndex = 21,
		Parent = header,
	})
	UIUtil.Corner(nameChip, UDim.new(1, 0))
	UIUtil.Stroke(nameChip, WHITE, 2, 0)
	UIUtil.Gradient(nameChip, ColorSequence.new(Color3.fromRGB(255, 196, 222), WHITE), 90)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 13), Parent = nameChip })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 7),
		Parent = nameChip,
	})
	local thumb = UIUtil.Create("Frame", {
		Name = "Thumb",
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = WHITE,
		LayoutOrder = 1,
		ZIndex = 22,
		Parent = nameChip,
	})
	UIUtil.Corner(thumb, UDim.new(1, 0))
	UIUtil.Stroke(thumb, C.PinkSoft, 1.5, 0)
	local nameLabel = UIUtil.Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = WHITE,
		TextSize = 15,
		LayoutOrder = 2,
		ZIndex = 22,
		Parent = nameChip,
	})
	UIUtil.Create("UIStroke", {
		Color = C.PinkDeep:Lerp(Color3.new(0, 0, 0), 0.45),
		Thickness = 1,
		Transparency = 0.55,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = nameLabel,
	})
	local placeChip = HouseButtons.Container({
		Name = "PlaceChip",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.MintSoft,
		LayoutOrder = 2,
		ZIndex = 21,
		Visible = false,
		Parent = header,
	})
	UIUtil.Corner(placeChip, UDim.new(1, 0))
	UIUtil.Stroke(placeChip, C.Mint, 1.5, 0.2)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11), Parent = placeChip })
	local placeLabel = UIUtil.Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = C.Ink,
		TextSize = 13,
		ZIndex = 22,
		Parent = placeChip,
	})

	-- Capsule d'outils (les clics entre les boutons ne traversent pas)
	local bar = HouseButtons.Container({
		Name = "Bar",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = WHITE,
		LayoutOrder = 2,
		ZIndex = 21,
		Parent = toolbar,
	})
	UIUtil.Corner(bar, 22)
	UIUtil.Stroke(bar, C.Pink, 2, 0.05)
	UIUtil.Gradient(bar, ColorSequence.new(WHITE, Color3.fromRGB(255, 232, 244)), 90)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 7),
		Parent = bar,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = bar,
	})

	local function separator(order: number): Frame
		local line = UIUtil.Create("Frame", {
			Name = "Sep" .. order,
			Size = UDim2.fromOffset(2, 40),
			BackgroundColor3 = C.Pink,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			LayoutOrder = order,
			ZIndex = 22,
			Parent = bar,
		})
		UIUtil.Corner(line, UDim.new(1, 0))
		return line
	end

	local candies: { Candy } = {}
	local function toolSize(): (number, number)
		if Interface.IsTouch() then
			return 58, 60
		end
		return 56, 56
	end
	local function tool(order: number, name: string, icon: string, caption: string, color: Color3, textColor: Color3?): Candy
		local w, h = toolSize()
		local candy = HouseButtons.Candy({
			Name = name,
			Icon = icon,
			Caption = Locale.T(caption),
			Color = color,
			TextColor = textColor,
			Width = w,
			Height = h,
			IconSize = 22,
			LayoutOrder = order,
			ZIndex = 22,
			Parent = bar,
		})
		table.insert(candies, candy)
		return candy
	end

	-- Taille : ➖ 100 % ➕ (segment)
	local sizeGroup = UIUtil.Create("Frame", {
		Name = "SizeGroup",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(243, 236, 255),
		LayoutOrder = 1,
		ZIndex = 22,
		Parent = bar,
	})
	UIUtil.Corner(sizeGroup, 18)
	UIUtil.Stroke(sizeGroup, C.Lilac, 1.5, 0.45)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = sizeGroup,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = sizeGroup,
	})
	local function sizeButton(order: number, name: string, icon: string): Candy
		local candy = HouseButtons.Candy({
			Name = name,
			Icon = icon,
			Color = P.Lilac,
			Width = Interface.IsTouch() and 46 or 40,
			Height = Interface.IsTouch() and 50 or 46,
			Radius = 16,
			IconSize = 18,
			LayoutOrder = order,
			ZIndex = 23,
			Parent = sizeGroup,
		})
		table.insert(candies, candy)
		return candy
	end
	local smaller = sizeButton(1, "Smaller", "➖")
	local percentHolder = UIUtil.Create("Frame", {
		Name = "Percent",
		Size = UDim2.fromOffset(52, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		ZIndex = 23,
		Parent = sizeGroup,
	})
	local percentLabel = UIUtil.Create("TextLabel", {
		Name = "Value",
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 3),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "100%",
		TextColor3 = C.Ink,
		TextSize = 17,
		ZIndex = 24,
		Parent = percentHolder,
	})
	UIUtil.Create("TextLabel", {
		Name = "Caption",
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 27),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = Locale.T("Size"),
		TextColor3 = C.Lilac:Lerp(C.Ink, 0.45),
		TextSize = 12,
		ZIndex = 24,
		Parent = percentHolder,
	})
	local bigger = sizeButton(3, "Bigger", "➕")
	separator(2)
	local backTool = tool(3, "Back", "⏬", "Back", P.Mint)
	local frontTool = tool(4, "Front", "⏫", "Front", P.Mint)
	separator(5)
	local flipTool = tool(6, "Flip", "↔️", "Flip", P.Sky)
	local copyTool = tool(7, "Copy", "📑", "Copy", P.Butter)
	local sendTool = tool(8, "Send", "🚪", "Send", P.Peach)
	separator(9)
	local storeTool = tool(10, "Store", "📦", "Put away", P.Red, WHITE)
	-- (téléphone : la barre cache l'inventaire -> "OK" pour le retrouver)
	local doneTool = tool(-1, "Deselect", "✔️", "OK", P.Green, WHITE)
	doneTool.Button.Visible = false
	local doneSep = separator(0)
	doneSep.Visible = false

	HouseButtons.Tip(smaller.Button, function()
		return HouseButtons.TipText("Make smaller", "( - )")
	end)
	HouseButtons.Tip(bigger.Button, function()
		return HouseButtons.TipText("Make bigger", "( + )")
	end)
	HouseButtons.Tip(backTool.Button, function()
		return HouseButtons.TipText("Send backward", "( Page Down )")
	end)
	HouseButtons.Tip(frontTool.Button, function()
		return HouseButtons.TipText("Bring forward", "( Page Up )")
	end)
	HouseButtons.Tip(flipTool.Button, function()
		return HouseButtons.TipText("Flip left / right", "( F )")
	end)
	HouseButtons.Tip(copyTool.Button, function()
		return HouseButtons.TipText("Duplicate", "( Ctrl+D )")
	end)
	HouseButtons.Tip(sendTool.Button, function()
		return HouseButtons.TipText("Send to another room")
	end)
	HouseButtons.Tip(storeTool.Button, function()
		return HouseButtons.TipText("Put away in the inventory", "( Delete )")
	end)

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

	-- Clé de tri : (zone, couche Z, Y, X) ; un objet posé sur un meuble
	-- passe juste devant ce meuble, une chaise à table juste derrière /
	-- devant elle (HouseSurfaces.Order)
	local function rankOf(entry: Placed): number
		local sticker = stickers[entry]
		return sticker and zoneRank(sticker) or 2
	end
	local function sortedEntries(): { Placed }
		return HouseSurfaces.Order(layout, room.Width, room.Height, rankOf)
	end

	-- (ZIndex espacés de 2 : les animaux qui se promènent se glissent entre deux objets)
	local function resort()
		local current = drag
		local riding: { [Placed]: number } = {}
		if current and current.Moved then
			for index, rider in ipairs(current.Riders) do
				riding[rider.Entry] = index
			end
		end
		for index, entry in ipairs(sortedEntries()) do
			local sticker = stickers[entry]
			if sticker then
				local dragged = current ~= nil and current.Entry == entry and current.Moved
				local rider = riding[entry]
				sticker.Frame.ZIndex = dragged and 5000 or (rider and 5000 + rider * 2 or index * 2 + 10)
			end
		end
		pets.Refresh(layout, stickers)
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

	-- Barre en bas (téléphone / petite scène : à la place de l'inventaire si
	-- la fenêtre a donné un "hôte", sinon en bas de la scène) ou près de l'objet
	local docked = false
	local dockHost: GuiObject? = nil
	local function wantDocked(): boolean
		if Interface.IsPhone() then
			return true
		end
		local factor = Interface.Scale > 0 and Interface.Scale or 1
		local stageWidth = room.Stage.AbsoluteSize.X / factor
		return stageWidth > 0 and stageWidth < DOCK_BELOW
	end
	local function applyToolbarMode()
		local dock = wantDocked()
		local host = dockHost
		local parent: Instance = dock and (host or room.Stage) or room.Overlay
		if dock == docked and toolbar.Parent == parent then
			return
		end
		docked = dock
		HouseButtons.HideTipOf(toolbar)
		if host and not dock then
			host.Visible = false
		end
		doneTool.Button.Visible = dock and host ~= nil
		doneSep.Visible = doneTool.Button.Visible
		if dock then
			toolbar.Parent = parent
			toolbar.ZIndex = 25
			toolbarScale.Scale = 1
			if host then
				-- (une seule rangée : nom à gauche, outils à droite)
				toolbarLayout.FillDirection = Enum.FillDirection.Horizontal
				toolbar.AnchorPoint = Vector2.new(0.5, 0.5)
				toolbar.Position = UDim2.fromScale(0.5, 0.5)
			else
				toolbarLayout.FillDirection = Enum.FillDirection.Vertical
				toolbar.AnchorPoint = Vector2.new(0.5, 1)
				toolbar.Position = UDim2.new(0.5, 0, 1, -6)
			end
		else
			toolbarLayout.FillDirection = Enum.FillDirection.Vertical
			toolbar.Parent = room.Overlay
			toolbar.ZIndex = 20
		end
	end

	-- Hôte (téléphone) : visible avec la barre ; la barre rétrécit si besoin
	local function fitDockHost(visible: boolean)
		local host = dockHost
		if not host or not docked then
			return
		end
		host.Visible = visible
		if visible then
			local factor = Interface.Scale > 0 and Interface.Scale or 1
			local hostWidth = host.AbsoluteSize.X / factor
			local barWidth = toolbar.AbsoluteSize.X / factor / math.max(0.2, toolbarScale.Scale)
			if hostWidth > 0 and barWidth > 0 then
				toolbarScale.Scale = math.clamp((hostWidth - 12) / barWidth, 0.5, 1)
			end
		end
	end

	local function positionToolbar()
		local entry = selected
		if not entry or not editing or (drag ~= nil and (drag :: Drag).Moved) then
			toolbar.Visible = false
			fitDockHost(false)
			return
		end
		local sticker = stickers[entry]
		if not sticker then
			toolbar.Visible = false
			fitDockHost(false)
			return
		end
		applyToolbarMode()
		if docked then
			toolbar.Visible = true
			fitDockHost(true)
			return
		end
		local scale = math.max(0.2, room.Scale)
		toolbarScale.Scale = 1 / scale
		local _, top, _, bottom = rectOf(entry)
		local toolbarSize = toolbar.AbsoluteSize
		local pixelRatio = room.Frame.AbsoluteSize.X / math.max(1, room.Width)
		local heightInRoom = pixelRatio > 0 and toolbarSize.Y / pixelRatio or 120 / scale
		local widthInRoom = pixelRatio > 0 and toolbarSize.X / pixelRatio or 560 / scale
		-- (barre plus large que la pièce : centrée ; math.clamp exige min <= max)
		local minX = widthInRoom / 2 - 10
		local maxX = room.Width - widthInRoom / 2 + 10
		local x = minX <= maxX and math.clamp(entry.X * room.Width, minX, maxX) or room.Width / 2
		if top - heightInRoom - 8 >= -16 then
			-- au-dessus de l'objet
			toolbar.AnchorPoint = Vector2.new(0.5, 1)
			toolbar.Position = UDim2.fromOffset(x, top - 6)
		elseif bottom + heightInRoom + 6 <= room.Height + 14 then
			-- en dessous
			toolbar.AnchorPoint = Vector2.new(0.5, 0)
			toolbar.Position = UDim2.fromOffset(x, bottom + 6)
		else
			-- objet très haut : en haut de la pièce
			toolbar.AnchorPoint = Vector2.new(0.5, 0)
			toolbar.Position = UDim2.fromOffset(x, -10)
		end
		toolbar.Visible = true
	end

	-- Où est posé l'objet (étiquette "📍") : meuble porteur ou table de la chaise
	local function placeText(entry: Placed): string?
		local support = HouseSurfaces.SupportOf(entry, layout, room.Width, room.Height)
		if support then
			local furniture = HouseCommon.ItemsById[support.Entry.I]
			if furniture then
				return Locale.T("📍 On: %s", HouseCommon.Name(furniture))
			end
		end
		local seat = HouseSurfaces.SeatedAt(entry, layout, room.Width, room.Height)
		if seat then
			local furniture = HouseCommon.ItemsById[seat.Table.I]
			if furniture then
				return Locale.T("🪑 At: %s", HouseCommon.Name(furniture))
			end
		end
		return nil
	end

	local thumbItemId = ""
	local function refreshToolbarText()
		local entry = selected
		local item = entry and HouseCommon.ItemsById[entry.I]
		if not entry or not item then
			return
		end
		applyToolbarMode()
		local roomData = currentRoomData()
		local comfort = HouseCommon.PlacedComfort(roomData, item)
		local favorite = HouseCommon.IsFavorite(roomData, item)
		local text = string.format("%s  ❤️+%s%s", HouseCommon.Name(item), HouseCommon.FormatPercent(comfort), favorite and "  ✨" or "")
		if nameLabel.Text ~= text then
			nameLabel.Text = text
		end
		if thumbItemId ~= item.Id then
			thumbItemId = item.Id
			for _, child in ipairs(thumb:GetChildren()) do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			HouseArt.Thumbnail(thumb, item, 26, 23)
		end
		local place = placeText(entry)
		placeChip.Visible = place ~= nil and not docked
		if place and placeLabel.Text ~= place then
			placeLabel.Text = place
		end
		percentLabel.Text = string.format("%d%%", math.floor(entry.S * 100 + 0.5))
		smaller.SetEnabled(entry.S > HouseCommon.MIN_SCALE + 1e-3)
		bigger.SetEnabled(entry.S < HouseCommon.MAX_SCALE - 1e-3)
		copyTool.SetEnabled(available(item.Id) > 0 and #layout < roomItems())
		sendTool.SetEnabled(#house.Rooms >= 2)
		flipTool.SetIcon(entry.F and "↩️" or "↔️")
	end

	local function setSelected(entry: Placed?)
		if selected == entry then
			if entry then
				refreshToolbarText()
			end
			positionToolbar()
			return
		end
		local previous = selected
		if previous and stickers[previous] then
			room.ShowRing(stickers[previous], false)
		end
		selected = entry
		HouseButtons.HideTipOf(toolbar)
		if entry and stickers[entry] then
			local sticker = stickers[entry]
			room.ShowRing(sticker, editing)
			refreshToolbarText()
			if editing then
				UIUtil.Pop(bar, 0.7, 0.28)
				UIUtil.Pop(nameChip, 0.6, 0.3)
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

	local function applyEntry(entry: Placed)
		local sticker = stickers[entry]
		if sticker then
			sticker.Frame.Position = UDim2.fromScale(entry.X, entry.Y)
		end
	end

	-- Objets posés sur `entry` et chaises rangées à cette table (ils le suivent)
	local function ridersOf(entry: Placed): ({ Rider }, { [Placed]: Placed })
		local riders: { Rider } = {}
		local dependents, parents = HouseSurfaces.Dependents(entry, layout, room.Width, room.Height)
		for _, other in ipairs(dependents) do
			table.insert(riders, { Entry = other, DX = other.X - entry.X, DY = other.Y - entry.Y })
		end
		return riders, parents
	end

	-- Place les objets posés sur un meuble qui bouge (et leurs autocollants)
	local function moveRiders(entry: Placed, riders: { Rider })
		for _, rider in ipairs(riders) do
			local other = rider.Entry
			other.X = entry.X + rider.DX
			other.Y = entry.Y + rider.DY
			local sticker = stickers[other]
			if sticker then
				sticker.Frame.Position = UDim2.fromScale(other.X, other.Y)
			end
		end
	end

	-- Déplace un objet et ce qui le suit d'un décalage (dx, dy)
	local function shiftGroup(entry: Placed, dx: number, dy: number, followers: { Placed })
		entry.X += dx
		entry.Y += dy
		applyEntry(entry)
		for _, other in ipairs(followers) do
			other.X += dx
			other.Y += dy
			applyEntry(other)
		end
	end

	-- Chaise rangée à `tableEntry` : se replace à la même place (après un
	-- changement de taille de la chaise ou de la table)
	local function reseat(seat: Placed, tableEntry: Placed, kind: string, followers: { Placed })
		local seatItem = HouseCommon.ItemsById[seat.I]
		if not seatItem then
			return
		end
		for _, spot in ipairs(HouseSurfaces.SeatSpots(tableEntry, seatItem, seat.S, seat.X, room.Width, room.Height)) do
			if spot.Kind == kind then
				local x, y = HouseCommon.ClampPosition(seatItem, spot.X, spot.Y, seat.S, room.Width, room.Height)
				shiftGroup(seat, x - seat.X, y - seat.Y, followers)
				return
			end
		end
	end

	-- Meuble agrandi / rétréci : ce qui est posé dessus reste sur le dessus,
	-- les chaises restent rangées à leur place autour de la table
	local function rescaleRiders(entry: Placed, item: Item, oldX: number, oldY: number, oldS: number, riders: { Rider }, parents: { [Placed]: Placed }, seats: { [Placed]: string })
		local old: Placed = { I = entry.I, X = oldX, Y = oldY, S = oldS, Z = entry.Z, F = entry.F }
		-- Ce qui est posé sur une chaise suit sa chaise
		local seatOf: { [Placed]: Placed } = {}
		for _, rider in ipairs(riders) do
			local node = rider.Entry
			local depth = 0
			while parents[node] and parents[node] ~= entry and depth < 6 do
				node = parents[node]
				depth += 1
			end
			if seats[node] and node ~= rider.Entry then
				seatOf[rider.Entry] = node
			end
		end
		for seat, kind in pairs(seats) do
			local followers = {}
			for other, owner in pairs(seatOf) do
				if owner == seat then
					table.insert(followers, other)
				end
			end
			reseat(seat, entry, kind, followers)
		end
		for _, rider in ipairs(riders) do
			local other = rider.Entry
			if not seats[other] and not seatOf[other] then
				local bx, by = HouseSurfaces.RoomToBox(old, item, other.X, other.Y, room.Width, room.Height)
				other.X, other.Y = HouseSurfaces.BoxToRoom(entry, item, bx, by, room.Width, room.Height)
				local otherItem = HouseCommon.ItemsById[other.I]
				if otherItem then
					other.X, other.Y = HouseCommon.ClampPosition(otherItem, other.X, other.Y, other.S, room.Width, room.Height, true)
				end
				applyEntry(other)
			end
		end
	end

	-- Chaises rangées à cette table (et leur place)
	local function seatsOf(entry: Placed, riders: { Rider }): { [Placed]: string }
		local seats: { [Placed]: string } = {}
		if not HouseSurfaces.IsTable(entry.I) then
			return seats
		end
		for _, rider in ipairs(riders) do
			local spot = HouseSurfaces.SeatedAt(rider.Entry, layout, room.Width, room.Height)
			if spot and spot.Table == entry then
				seats[rider.Entry] = spot.Kind
			end
		end
		return seats
	end

	-- Meuble rangé / envoyé ailleurs : ce qui était posé dessus tombe par
	-- terre (petit rebond) ; les chaises autour d'une table restent où elles sont
	local function dropRiders(entry: Placed)
		local riders, parents = ridersOf(entry)
		local seats = seatsOf(entry, riders)
		for _, rider in ipairs(riders) do
			local other = rider.Entry
			-- (ce qui est sur une chaise reste sur la chaise)
			local node = other
			local onSeat = seats[other] ~= nil
			local depth = 0
			while not onSeat and parents[node] and parents[node] ~= entry and depth < 6 do
				node = parents[node]
				onSeat = seats[node] ~= nil
				depth += 1
			end
			local item = HouseCommon.ItemsById[other.I]
			local sticker = stickers[other]
			if item and not onSeat then
				local fromY = other.Y
				other.X, other.Y = HouseCommon.ClampPosition(item, other.X, entry.Y + 0.01, other.S, room.Width, room.Height)
				if sticker then
					sticker.Frame.Position = UDim2.fromScale(other.X, other.Y)
					local fall = (other.Y - fromY) * room.Height / math.max(0.2, item.Size * other.S / 100)
					sticker.Body.Position = UDim2.fromOffset(0, -fall)
					UIUtil.Tween(sticker.Body, 0.45, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Bounce)
				end
			end
		end
	end

	local function beginDrag(entry: Placed, input: InputObject)
		local pointer = room.ScreenToRoom(Vector2.new(input.Position.X, input.Position.Y))
		local riders = ridersOf(entry)
		local skip: { [Placed]: boolean } = { [entry] = true }
		for _, rider in ipairs(riders) do
			skip[rider.Entry] = true
		end
		local item = HouseCommon.ItemsById[entry.I]
		drag = {
			Entry = entry,
			Input = input,
			Offset = Vector2.new(entry.X, entry.Y) - pointer,
			Target = Vector2.new(entry.X, entry.Y),
			Start = Vector2.new(input.Position.X, input.Position.Y),
			Moved = false,
			Before = copyList(layout),
			Riders = riders,
			Skip = skip,
			Tabletop = HouseSurfaces.CanStandOn(item),
			IsSeat = HouseSurfaces.IsSeat(entry.I),
			Surface = nil,
			Seat = nil,
			HintKey = "",
			WasOn = HouseSurfaces.SupportOf(entry, layout, room.Width, room.Height) ~= nil,
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
				-- (un animal qui dormait chez lui se réveille et vient jouer)
				pets.Poke(entry)
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

	local function clearHints()
		room.SetZoneHint(nil)
		room.SetGrid(false)
		room.SetSurfaceHint(nil)
		room.ShowSurfaces(nil)
		room.SetTargetGlow(nil)
	end

	local function rebuildFrom(list: { Placed }, keepSelection: boolean?)
		local keepIndex: number? = nil
		if selected and keepSelection ~= false then
			keepIndex = table.find(layout, selected :: Placed)
		end
		drag = nil
		clearHints()
		clearStickers()
		layout = {}
		for _, entry in ipairs(list) do
			local copy = copyEntry(entry)
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
		local riders, parents = ridersOf(entry)
		local seats = seatsOf(entry, riders)
		local support = HouseSurfaces.SupportOf(entry, layout, room.Width, room.Height)
		local seated = HouseSurfaces.SeatedAt(entry, layout, room.Width, room.Height)
		local oldX, oldY, oldS = entry.X, entry.Y, entry.S
		entry.S = newScale
		-- Plus grand : l'objet doit rester dans sa zone
		entry.X, entry.Y = HouseCommon.ClampPosition(sticker.Item, entry.X, entry.Y, entry.S, room.Width, room.Height, support ~= nil)
		sticker.Frame.Position = UDim2.fromScale(entry.X, entry.Y)
		if #riders > 0 then
			rescaleRiders(entry, sticker.Item, oldX, oldY, oldS, riders, parents, seats)
		end
		-- Chaise rangée à une table : elle reste bien rangée (avec ce qui est dessus)
		if seated then
			local followers = {}
			for _, rider in ipairs(riders) do
				table.insert(followers, rider.Entry)
			end
			reseat(entry, seated.Table, seated.Kind, followers)
		end
		resort()
		UIUtil.Tween(sticker.Scale, 0.2, { Scale = sticker.Item.Size * newScale / 100 }, Enum.EasingStyle.Back)
		local ringStroke = sticker.RingStroke
		if ringStroke then
			ringStroke.Thickness = 3 / math.max(0.2, sticker.Item.Size * newScale / 100)
		end
		SoundManager.Play("Click", delta > 0 and 1.2 or 0.85)
		task.delay(0.21, positionToolbar)
		markDirty()
	end

	-- Chaise rangée à une table : "devant" / "derrière" la font changer de place
	local function restackSeat(entry: Placed, forward: boolean, button: GuiObject): boolean
		local seated = HouseSurfaces.SeatedAt(entry, layout, room.Width, room.Height)
		if not seated then
			return false
		end
		local want = forward and "Front" or "Behind"
		if seated.Kind == want then
			refuse(button, forward and Locale.T("Already in front!") or Locale.T("Already at the back!"))
			return true
		end
		local item = HouseCommon.ItemsById[entry.I]
		if not item then
			return true
		end
		for _, spot in ipairs(HouseSurfaces.SeatSpots(seated.Table, item, entry.S, entry.X, room.Width, room.Height)) do
			if spot.Kind == want then
				pushUndo()
				local riders = ridersOf(entry)
				local followers = {}
				for _, rider in ipairs(riders) do
					table.insert(followers, rider.Entry)
				end
				local x, y = HouseCommon.ClampPosition(item, spot.X, spot.Y, entry.S, room.Width, room.Height)
				shiftGroup(entry, x - entry.X, y - entry.Y, followers)
				entry.Z = seated.Table.Z
				local sticker = stickers[entry]
				if sticker then
					wiggle(sticker)
				end
				resort()
				positionToolbar()
				SoundManager.Play("Click", forward and 1.15 or 0.9)
				markDirty()
				return true
			end
		end
		refuse(button, Locale.T("No room for this chair there"))
		return true
	end

	-- Devant / derrière : passe devant (ou derrière) TOUS les objets qui le chevauchent
	local function restack(forward: boolean, button: GuiObject)
		local entry = selected
		local sticker = entry and stickers[entry]
		if not entry or not sticker then
			return
		end
		if HouseSurfaces.IsSeat(entry.I) and restackSeat(entry, forward, button) then
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

	-- Retourne l'objet (miroir) ; un meuble retourné emporte ce qui est
	-- posé dessus et ses chaises (elles restent tournées vers la table)
	local function flip(): boolean
		local entry = selected
		local sticker = entry and stickers[entry]
		if not entry or not sticker then
			return false
		end
		pushUndo()
		local riders = ridersOf(entry)
		local flipped = entry.F ~= true
		entry.F = flipped or nil
		room.SetFlip(sticker, flipped)
		for _, rider in ipairs(riders) do
			local other = rider.Entry
			other.X = entry.X - (other.X - entry.X)
			local info = HouseSurfaces.Seat(other.I)
			local otherSticker = stickers[other]
			if info and info.View == "Side" then
				other.F = (other.F ~= true) or nil
				if otherSticker then
					room.SetFlip(otherSticker, other.F == true)
				end
			end
			local otherItem = HouseCommon.ItemsById[other.I]
			if otherItem then
				other.X = math.clamp(other.X, 0, 1)
			end
			applyEntry(other)
		end
		wiggle(sticker)
		SoundManager.Play("Click", flipped and 1.25 or 1.05)
		resort()
		markDirty()
		return true
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
		dropRiders(entry)
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
		local riders = ridersOf(entry)
		local x = entry.X + dx / math.max(1, room.Width)
		local y = entry.Y + dy / math.max(1, room.Height)
		local support = HouseSurfaces.SupportOf(entry, layout, room.Width, room.Height)
		if support and dy <= 0 then
			-- Posé sur un meuble : glisse le long du dessus (flèche bas = descend)
			local surface = support :: HouseSurfaces.Surface
			entry.X = math.clamp(x, surface.L, surface.R)
			entry.X, entry.Y = HouseCommon.ClampPosition(sticker.Item, entry.X, surface.Y, entry.S, room.Width, room.Height, true)
		elseif support then
			entry.X, entry.Y = snapPoint(sticker.Item, x, support.Base + 0.01, entry.S)
		else
			entry.X, entry.Y = snapPoint(sticker.Item, x, y, entry.S)
		end
		applyEntry(entry)
		moveRiders(entry, riders)
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

	-- Petit objet : une place libre SUR un meuble si possible (la nourriture
	-- sur une table, un coussin ou une peluche sur le lit...)
	local function surfaceSpot(item: Item): (number?, number?)
		if not HouseSurfaces.CanStandOn(item) or item.Category == "Pets" then
			return nil, nil
		end
		local height = item.Size / math.max(1, room.Height)
		local halfW = item.Size * 0.3 / math.max(1, room.Width)
		local candidates: { { Point: Vector2, Pref: number } } = {}
		local bestPref = 0
		for _, entry in ipairs(layout) do
			if HouseSurfaces.Has(entry.I) then
				local pref = HouseSurfaces.Preference(item, entry.I)
				if pref > 0 then
					for _, surface in ipairs(HouseSurfaces.Of(entry, room.Width, room.Height)) do
						if surface.Y >= HouseSurfaces.MinY() and surface.Y - height * 0.92 > -0.02 and surface.R - surface.L > halfW * 2 then
							for _, t in ipairs({ 0.2, 0.5, 0.8 }) do
								local x = surface.L + (surface.R - surface.L) * t
								local free = true
								for _, other in ipairs(layout) do
									if math.abs(other.Y - surface.Y) < 0.01 and math.abs(other.X - x) < halfW * 1.6 then
										free = false
										break
									end
								end
								if free then
									table.insert(candidates, { Point = Vector2.new(x, surface.Y), Pref = pref })
									bestPref = math.max(bestPref, pref)
								end
							end
						end
					end
				end
			end
		end
		local best: { Vector2 } = {}
		for _, candidate in ipairs(candidates) do
			if candidate.Pref == bestPref then
				table.insert(best, candidate.Point)
			end
		end
		-- (hors cuisine et coussins : pas toujours sur un meuble, sinon tout s'y entasse)
		if #best == 0 or (bestPref < 2 and item.Category ~= "Kitchen" and math.random() < 0.35) then
			return nil, nil
		end
		local pick = best[math.random(1, #best)]
		return HouseCommon.ClampPosition(item, pick.X, pick.Y, 1, room.Width, room.Height, true)
	end

	-- Chaise : une place libre à une table (côtés d'abord, puis derrière)
	local function seatSpotFor(item: Item, scale: number, except: Placed?): HouseSurfaces.SeatSpot?
		if not HouseSurfaces.IsSeat(item.Id) then
			return nil
		end
		for _, kindWanted in ipairs({ "Left", "Right", "Behind", "Front" }) do
			for _, tableEntry in ipairs(layout) do
				if HouseSurfaces.IsTable(tableEntry.I) then
					for _, spot in ipairs(HouseSurfaces.SeatSpots(tableEntry, item, scale, tableEntry.X, room.Width, room.Height)) do
						if spot.Kind == kindWanted then
							local taken = false
							for _, other in ipairs(layout) do
								if other ~= except and HouseSurfaces.IsSeat(other.I) then
									local at = HouseSurfaces.SeatedAt(other, layout, room.Width, room.Height)
									if at and at.Table == tableEntry and at.Kind == kindWanted then
										taken = true
										break
									end
								end
							end
							if not taken and spot.X > 0.03 and spot.X < 0.97 then
								return spot
							end
						end
					end
				end
			end
		end
		return nil
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
		local x, y
		local flipped: boolean? = nil
		local z = HouseCommon.DEFAULT_Z
		local seat = seatSpotFor(item, 1, nil)
		local onX, onY = surfaceSpot(item)
		if seat then
			x, y = HouseCommon.ClampPosition(item, seat.X, seat.Y, 1, room.Width, room.Height)
			flipped = seat.F
			z = seat.Table.Z
		elseif onX and onY then
			x, y = onX, onY
		else
			x, y = freeSpot(item, layout)
			x, y = snapPoint(item, x, y, 1)
		end
		local entry: Placed = { I = itemId, X = x, Y = y, S = 1, Z = z, F = flipped }
		if not seat then
			-- Nouvelle couche au-dessus des objets qu'il chevauche
			for _, other in ipairs(layout) do
				if overlaps(entry, other) then
					entry.Z = math.max(entry.Z, other.Z)
				end
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
			refuse(copyTool.Button, available(entry.I) <= 0 and Locale.T("No other copy in your inventory: buy one in the shop!") or reason)
			return false
		end
		pushUndo()
		local item = sticker.Item
		local copy: Placed = { I = entry.I, X = entry.X, Y = entry.Y, S = entry.S, Z = math.min(HouseCommon.MAX_Z, entry.Z + 1), F = entry.F }
		local offset = math.max(GRID, item.Size * entry.S * 0.35) / math.max(1, room.Width)
		local support = HouseSurfaces.SupportOf(entry, layout, room.Width, room.Height)
		local seat: HouseSurfaces.SeatSpot? = nil
		if HouseSurfaces.IsSeat(entry.I) and HouseSurfaces.SeatedAt(entry, layout, room.Width, room.Height) then
			seat = seatSpotFor(item, entry.S, nil)
		end
		if seat then
			-- Chaise à table : la copie prend une autre place autour d'une table
			copy.X, copy.Y = HouseCommon.ClampPosition(item, seat.X, seat.Y, entry.S, room.Width, room.Height)
			copy.F = seat.F
			copy.Z = seat.Table.Z
		elseif support then
			-- Posé sur un meuble : la copie reste sur le même dessus
			local x = entry.X + offset
			if x > support.R then
				x = entry.X - offset
			end
			copy.X, copy.Y = HouseCommon.ClampPosition(item, math.clamp(x, support.L, support.R), support.Y, entry.S, room.Width, room.Height, true)
		else
			local x = entry.X + offset
			if x > 0.9 then
				x = entry.X - offset
			end
			copy.X, copy.Y = snapPoint(item, x, entry.Y, entry.S)
		end
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
			refuse(sendTool.Button, Locale.T("This room is full (%d items)! Decorate another room 🏡", roomItems()))
			return false
		end
		local item = sticker.Item
		local before = copyList(targetList)
		local x, y = freeSpot(item, targetList)
		local z = HouseCommon.DEFAULT_Z
		for _, other in ipairs(targetList) do
			z = math.max(z, other.Z)
		end
		table.insert(targetList, { I = entry.I, X = x, Y = y, S = entry.S, Z = z, F = entry.F })
		pushUndo(nil, { Room = targetId, Before = before, After = copyList(targetList) })
		extras[targetId] = targetList
		floatAt(sticker, "🚪 → " .. HouseCommon.GetRoomType(target).Icon, C.Lilac)
		dropRiders(entry)
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

	smaller.Button.Activated:Connect(function()
		resize(-HouseCommon.SCALE_STEP, smaller.Button)
	end)
	bigger.Button.Activated:Connect(function()
		resize(HouseCommon.SCALE_STEP, bigger.Button)
	end)
	frontTool.Button.Activated:Connect(function()
		restack(true, frontTool.Button)
	end)
	backTool.Button.Activated:Connect(function()
		restack(false, backTool.Button)
	end)
	flipTool.Button.Activated:Connect(function()
		flip()
	end)
	copyTool.Button.Activated:Connect(function()
		duplicate()
	end)
	sendTool.Button.Activated:Connect(function()
		local entry = selected
		if not entry then
			return
		end
		if #house.Rooms < 2 then
			refuse(sendTool.Button, Locale.T("Buy another room first! 🏡"))
			return
		end
		local handler = sendHandler
		if handler then
			handler(entry)
		end
	end)
	storeTool.Button.Activated:Connect(function()
		local entry = selected
		if entry then
			store(entry)
		end
	end)
	doneTool.Button.Activated:Connect(function()
		SoundManager.Play("Click", 1)
		setSelected(nil)
	end)

	room.BackgroundHit.Activated:Connect(function()
		if not drag then
			setSelected(nil)
		end
	end)
	room.Changed:Connect(positionToolbar)
	room.Stage:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if selected and editing then
			positionToolbar()
		end
	end)

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
		clearHints()
		if not sticker then
			return
		end
		if current.Moved then
			pushUndo(current.Before)
			entry.X, entry.Y = current.Target.X, current.Target.Y
			local seat = current.Seat
			if seat then
				-- Chaise rangée à la table : même couche que la table, tournée vers elle
				entry.Z = seat.Table.Z
				local info = HouseSurfaces.Seat(entry.I)
				if info and info.View == "Side" then
					entry.F = seat.F == true or nil
				end
			end
			room.SetFlip(sticker, entry.F == true)
			sticker.Frame.Position = UDim2.fromScale(entry.X, entry.Y)
			-- Ce qui est posé dessus suit (et reste dans la pièce)
			moveRiders(entry, current.Riders)
			for _, rider in ipairs(current.Riders) do
				local other = rider.Entry
				local otherItem = HouseCommon.ItemsById[other.I]
				if otherItem then
					local onFurniture = HouseSurfaces.CanStandOn(otherItem)
					other.X, other.Y = HouseCommon.ClampPosition(otherItem, other.X, other.Y, other.S, room.Width, room.Height, onFurniture)
					applyEntry(other)
				end
				local riderSticker = stickers[other]
				if riderSticker then
					UIUtil.Tween(riderSticker.Body, 0.16, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end
			if current.Surface or seat then
				-- Posé sur un meuble / rangée à table : petites étincelles
				task.delay(0.12, function()
					burstAt(sticker, seat and C.Mint or C.Butter, 7)
				end)
			end
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

	-- Texte de l'étiquette pendant un glissement
	local function hintFor(surface: HouseSurfaces.Surface?, seat: HouseSurfaces.SeatSpot?): string?
		if surface then
			local furniture = HouseCommon.ItemsById[surface.Entry.I]
			return furniture and Locale.T("✨ Put on: %s", HouseCommon.Name(furniture)) or nil
		elseif seat then
			local furniture = HouseCommon.ItemsById[seat.Table.I]
			if not furniture then
				return nil
			end
			local name = HouseCommon.Name(furniture)
			if seat.Kind == "Behind" then
				return Locale.T("🪑 Behind: %s", name)
			elseif seat.Kind == "Front" then
				return Locale.T("🪑 In front of: %s", name)
			end
			return Locale.T("🪑 At the side of: %s", name)
		end
		return nil
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
		local sticker = stickers[current.Entry]
		if not sticker then
			return
		end
		local item = sticker.Item
		if not current.Moved then
			if (position - current.Start).Magnitude < DRAG_THRESHOLD then
				return
			end
			current.Moved = true
			UIUtil.Tween(sticker.Pop, 0.15, { Scale = LIFT_SCALE }, Enum.EasingStyle.Back)
			UIUtil.Tween(sticker.Body, 0.15, { Position = UDim2.fromOffset(0, -8) })
			room.SetZoneHint(item.Placement)
			for _, rider in ipairs(current.Riders) do
				local riderSticker = stickers[rider.Entry]
				if riderSticker then
					UIUtil.Tween(riderSticker.Body, 0.15, { Position = UDim2.fromOffset(0, -8) })
				end
			end
			room.SetGrid(snapEnabled, GRID)
			-- Toutes les places possibles s'allument (petit objet)
			if current.Tabletop then
				local height = item.Size * current.Entry.S / math.max(1, room.Height)
				room.ShowSurfaces(HouseSurfaces.All(layout, height, room.Width, room.Height, current.Skip))
			end
			SoundManager.Play("Click", 1.3)
			resort()
			toolbar.Visible = false
			HouseButtons.HideTipOf(toolbar)
		end
		local pointer = room.ScreenToRoom(position) + current.Offset
		-- Petit objet au-dessus d'un meuble : il se pose SUR le meuble ;
		-- chaise près d'une table : elle se range à la table
		local surface: HouseSurfaces.Surface? = nil
		local seat: HouseSurfaces.SeatSpot? = nil
		if current.Tabletop then
			local height = item.Size * current.Entry.S / math.max(1, room.Height)
			surface = HouseSurfaces.Find(layout, pointer.X, pointer.Y, height, room.Width, room.Height, current.Skip)
		end
		if not surface and current.IsSeat then
			seat = HouseSurfaces.FindSeat(layout, current.Entry, pointer.X, pointer.Y, room.Width, room.Height, current.Skip)
		end
		local x, y
		if surface then
			x = math.clamp(pointer.X, surface.L, surface.R)
			if snapEnabled then
				x = math.clamp(roundTo(x, GRID / math.max(1, room.Width)), surface.L, surface.R)
			end
			x, y = HouseCommon.ClampPosition(item, x, surface.Y, current.Entry.S, room.Width, room.Height, true)
		elseif seat then
			x, y = HouseCommon.ClampPosition(item, seat.X, seat.Y, current.Entry.S, room.Width, room.Height)
		else
			x, y = snapPoint(item, pointer.X, pointer.Y, current.Entry.S)
		end
		-- Indices : dessus visé / place à table, meuble entouré, petit "clic"
		local key = ""
		if surface then
			key = string.format("S%s:%d", tostring(surface.Entry), surface.Index)
		elseif seat then
			key = string.format("C%s:%s", tostring(seat.Table), seat.Kind)
		end
		if key ~= current.HintKey then
			current.HintKey = key
			if key ~= "" then
				SoundManager.Play("Click", 1.45)
			end
		end
		local label = hintFor(surface, seat)
		if surface then
			room.SetSurfaceHint(surface, label, C.PinkDeep)
			room.SetTargetGlow(stickers[surface.Entry])
		elseif seat then
			room.SetSurfaceHint({ L = seat.L, R = seat.R, Y = seat.Top }, label, SEAT_TINT)
			room.SetTargetGlow(stickers[seat.Table])
		else
			room.SetSurfaceHint(nil)
			room.SetTargetGlow(nil)
		end
		-- Chaise de profil : elle se tourne vers la table (aperçu en direct)
		if current.IsSeat then
			local info = HouseSurfaces.Seat(item.Id)
			local wantFlip = current.Entry.F == true
			if seat and info and info.View == "Side" then
				wantFlip = seat.F == true
			end
			room.SetFlip(sticker, wantFlip)
		end
		current.Surface = surface
		current.Seat = seat
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
		elseif key == Enum.KeyCode.F and not ctrl then
			flip()
		elseif key == Enum.KeyCode.Delete or key == Enum.KeyCode.Backspace then
			store(entry)
		elseif key == Enum.KeyCode.Equals or key == Enum.KeyCode.KeypadPlus then
			resize(HouseCommon.SCALE_STEP, bigger.Button)
		elseif key == Enum.KeyCode.Minus or key == Enum.KeyCode.KeypadMinus then
			resize(-HouseCommon.SCALE_STEP, smaller.Button)
		elseif key == Enum.KeyCode.PageUp then
			restack(true, frontTool.Button)
		elseif key == Enum.KeyCode.PageDown then
			restack(false, backTool.Button)
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

	-- Taille des boutons (tactile : zones de 44 px et plus)
	Interface.DeviceChanged:Connect(function()
		local w, h = toolSize()
		for _, candy in ipairs(candies) do
			if candy.Button.Parent == bar then
				candy.SetSize(w, h)
			else
				candy.SetSize(Interface.IsTouch() and 46 or 40, Interface.IsTouch() and 50 or 46)
			end
		end
		positionToolbar()
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
			-- En décoration, les animaux rentrent chez eux (on déplace leur "maison")
			pets.SetLive(liveVisible and active and not editing)
			local current = selected
			if current and stickers[current] then
				room.ShowRing(stickers[current], value)
			end
			positionToolbar()
		end,
		IsEditing = function(): boolean
			return editing
		end,
		SetLive = function(visible: boolean)
			liveVisible = visible
			pets.SetLive(visible and active and not editing)
		end,
		GetPets = function(): HousePets.Pets
			return pets
		end,
		SetActive = function(value: boolean)
			active = value
			if not value and drag then
				endDrag()
			end
			pets.SetLive(liveVisible and active and not editing)
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
		Flip = flip,
		SendTo = sendTo,
		SetSendHandler = function(handler: (entry: Placed) -> ())
			sendHandler = handler
		end,
		SetDockHost = function(host: GuiObject?)
			local old = dockHost
			if old and old ~= host then
				old.Visible = false
			end
			dockHost = host
			docked = false
			positionToolbar()
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
			if liveVisible then
				pets.Update(dt)
			end
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
					local bounce = -8 + math.sin(clock * 9) * 2.5
					sticker.Body.Position = UDim2.fromOffset(0, bounce)
					if #current.Riders > 0 then
						moveRiders(entry, current.Riders)
						for _, rider in ipairs(current.Riders) do
							local riderSticker = stickers[rider.Entry]
							if riderSticker then
								-- (même rebond, en px de maquette : dessins de tailles différentes)
								local k = sticker.Item.Size * entry.S / math.max(1, riderSticker.Item.Size * rider.Entry.S)
								riderSticker.Body.Position = UDim2.fromOffset(0, bounce * k)
							end
						end
					end
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
