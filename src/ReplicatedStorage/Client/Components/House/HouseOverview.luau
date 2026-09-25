--[[
	HouseOverview (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseOverview

	Vue d'ensemble de la maison ("🏠 Ma maison" s'ouvre ici) :
	  - ciel (jour / nuit) avec nuages qui passent, soleil ou lune, étoiles,
	    collines ; l'immeuble (House/HouseExterior, dessiné en coupe comme
	    une maison de poupée) centré et mis à l'échelle ;
	  - dans chaque case : la pièce en petit (House/HouseMiniRoom) + une
	    pastille "🛏️ Chambre ❤️ 24 ✨2" ; survol = contour lumineux, clic =
	    zoom fluide vers la pièce (OnOpenRoom) ;
	  - cases vides : "➕ Nouvelle pièce" en pointillés avec le prix
	    (OnEmptySlot -> choix du type de pièce) ;
	  - MODE RANGEMENT : on glisse une pièce (souris ou doigt) sur une autre
	    case (échange) ou une case vide ; case visée en surbrillance,
	    animations ; toucher une pièce = menu "⋯" (OnRoomMenu).
	HouseExterior est écrit en parallèle : chargé avec pcall, sinon un
	immeuble simple (façade arrondie + grille de cases) le remplace.

	API :
	  HouseOverview.new(parent, handlers) -> Overview
	    .Frame, .SetHouse(house, overrides?), .SetDark(dark),
	    .SetArranging(on), .IsArranging(), .Update(dt), .Refit(),
	    .ZoomIn(roomId, done), .ZoomOut(roomId?), .Pulse(roomId),
	    .CancelMoves(), .CellScreenCenter(slot) -> Vector2?,
	    .BeginDrag(roomId, screenPos), .DragTo(screenPos), .EndDrag(),
	    .IsDragging()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local SoundManager = require(Client.SoundManager)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local HouseCommon = require(script.Parent.HouseCommon)
local HousePatterns = require(script.Parent.HousePatterns)
local HouseMiniRoom = require(script.Parent.HouseMiniRoom)

type HouseData = HouseCommon.HouseData
type Room = HouseCommon.Room
type SizeDef = HouseCommon.SizeDef
type Placed = HouseCommon.Placed
type Mini = HouseMiniRoom.Mini

local HouseOverview = {}

local CELL_H = 190
local DRAG_THRESHOLD = 8 -- (px écran)
local DRAG_SMOOTHING = 26
local ZOOM_TIME = 0.38

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local C = HouseCommon.Colors
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle
local Round = HousePatterns.Round

local SKY_DAY = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(176, 220, 255)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(226, 232, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 226, 238)),
})
local SKY_NIGHT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 24, 74)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 52, 132)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 88, 160)),
})

export type Handlers = {
	OnOpenRoom: (roomId: string) -> (),
	OnEmptySlot: (slot: number) -> (),
	OnMoveRoom: (roomId: string, slot: number) -> (),
	OnRoomMenu: (roomId: string) -> (),
}

export type Overview = {
	Frame: Frame,
	SetHouse: (house: HouseData, overrides: HouseCommon.Overrides?) -> (),
	SetDark: (dark: boolean) -> (),
	SetArranging: (on: boolean) -> (),
	IsArranging: () -> boolean,
	Update: (dt: number) -> (),
	Refit: () -> (),
	ZoomIn: (roomId: string, done: () -> ()) -> (),
	ZoomOut: (roomId: string?) -> (),
	Pulse: (roomId: string) -> (),
	CancelMoves: () -> (),
	CellScreenCenter: (slot: number) -> Vector2?,
	BeginDrag: (roomId: string, screenPos: Vector2) -> (),
	DragTo: (screenPos: Vector2) -> (),
	EndDrag: () -> (),
	IsDragging: () -> boolean,
}

type Rect = { X: number, Y: number, W: number, H: number }

type Exterior = {
	Frame: Frame,
	Width: number,
	Height: number,
	Cells: { [number]: Rect },
	CellLayer: Frame,
	SetDark: (dark: boolean) -> (),
	Update: (dt: number) -> (),
	Destroy: () -> (),
}

type Card = {
	RoomId: string,
	Frame: Frame,
	Scale: UIScale,
	Mini: Mini,
	Hover: Frame,
	HoverStroke: UIStroke,
	Chip: Frame,
	ChipLabel: TextLabel,
	ChipScale: UIScale,
	Menu: TextButton,
	MenuScale: UIScale,
	Shadow: Frame,
	Hit: TextButton,
	Slot: number,
	Hovered: boolean,
}

type EmptySlot = {
	Slot: number,
	Frame: Frame,
	Content: Frame,
	ContentScale: UIScale,
	Price: TextLabel,
	Plus: Frame,
	Hit: TextButton,
}

type Drag = {
	Card: Card,
	FromSlot: number,
	Offset: Vector2, -- (px de maquette) coin de la carte - pointeur
	Target: Vector2, -- coin visé de la carte
	Current: Vector2,
	Over: number?,
}

type Pending = { RoomId: string, Input: InputObject, Start: Vector2 }

----------------------------------------------------------------------
-- Immeuble de secours (si HouseExterior n'est pas disponible)
----------------------------------------------------------------------

local function buildFallback(parent: Instance, size: SizeDef): Exterior
	local cellW = math.floor(300 * (tonumber(size.Width) or 1))
	local wallT, slab, inner = 22, 20, 14
	local roofH, groundH, margin = 120, 46, 40
	local floors, columns = size.Floors, size.Columns
	local bodyW = columns * cellW + (columns - 1) * inner + wallT * 2
	local bodyH = floors * CELL_H + (floors - 1) * slab + wallT + 26
	local width = bodyW + margin * 2
	local height = roofH + bodyH + groundH

	local frame = UIUtil.Create("Frame", {
		Name = "Exterior",
		Size = UDim2.fromOffset(width, height),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 1,
	})
	local back = UIUtil.Create("Frame", {
		Name = "Back",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = frame,
	})
	local cellLayer = UIUtil.Create("Frame", {
		Name = "CellLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = frame,
	})
	local front = UIUtil.Create("Frame", {
		Name = "Front",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = frame,
	})
	local facadeColor = Color3.fromRGB(255, 236, 244)
	local trim = Color3.fromRGB(236, 150, 190)
	-- Pelouse
	local lawn = Box(back, 0, height - groundH - 6, width, groundH, Color3.fromRGB(150, 222, 150), 0, 1)
	Round(lawn, UDim.new(0, 24))
	UIUtil.Stroke(lawn, Color3.fromRGB(108, 190, 118), 2, 0.2)
	-- Façade
	local facade = Box(back, margin, roofH, bodyW, bodyH, facadeColor, 0, 2)
	Round(facade, UDim.new(0, 18))
	UIUtil.Stroke(facade, trim, 3, 0.1)
	-- Toit (trapèze en tranches) + faîtage
	local slices = 18
	for index = 0, slices - 1 do
		local k = (index + 1) / slices
		local rowW = bodyW * 0.45 + (bodyW + 50 - bodyW * 0.45) * k
		Box(back, width / 2 - rowW / 2, 14 + index * (roofH - 14) / slices, rowW, (roofH - 14) / slices + 0.8,
			Color3.fromRGB(255, 150, 190):Lerp(Color3.fromRGB(226, 104, 156), k * 0.3), 0, 3)
	end
	local ridge = Box(back, width / 2 - bodyW * 0.24, 8, bodyW * 0.48, 12, Color3.fromRGB(226, 104, 156), 0, 4)
	Round(ridge)
	HousePatterns.Heart(back, width / 2, 4, 26, C.Heart, 0, 5)
	local cells: { [number]: Rect } = {}
	for floorIndex = 1, floors do
		for column = 1, columns do
			local slot = (floorIndex - 1) * columns + column
			local x = margin + wallT + (column - 1) * (cellW + inner)
			local y = roofH + wallT + (floors - floorIndex) * (CELL_H + slab)
			cells[slot] = { X = x, Y = y, W = cellW, H = CELL_H }
			-- Fond de case (sous la pièce)
			local hole = Box(back, x - 3, y - 3, cellW + 6, CELL_H + 6, trim:Lerp(BLACK, 0.2), 0.3, 3)
			Round(hole, UDim.new(0, 8))
		end
		-- Dalle de plancher (devant)
		local y = roofH + wallT + (floors - floorIndex) * (CELL_H + slab) + CELL_H
		local slabFrame = Box(front, margin + 8, y, bodyW - 16, 12, C.Cream, 0, 1)
		Round(slabFrame, UDim.new(0, 5))
		UIUtil.Stroke(slabFrame, trim, 1.5, 0.3)
	end
	frame.Parent = parent
	local night = { lawn, facade }
	return {
		Frame = frame,
		Width = width,
		Height = height,
		Cells = cells,
		CellLayer = cellLayer,
		SetDark = function(dark: boolean)
			for _, part in ipairs(night) do
				local day = part:GetAttribute("DayColor")
				if typeof(day) ~= "Color3" then
					day = part.BackgroundColor3
					part:SetAttribute("DayColor", day)
				end
				part.BackgroundColor3 = dark and (day :: Color3):Lerp(Color3.fromRGB(40, 36, 100), 0.4) or day :: Color3
			end
		end,
		Update = function(_dt: number) end,
		Destroy = function()
			frame:Destroy()
		end,
	}
end

-- Immeuble de HouseExterior (Contrat A), sinon celui de secours
local function buildExterior(parent: Instance, size: SizeDef): Exterior
	local folder = script.Parent
	local moduleScript = folder:FindFirstChild("HouseExterior")
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(function()
			local module = (require :: any)(moduleScript)
			local built = module.Build(parent, size)
			assert(type(built) == "table" and typeof(built.Frame) == "Instance" and type(built.Cells) == "table", "bad exterior")
			assert(typeof(built.CellLayer) == "Instance", "no cell layer")
			for slot = 1, size.MaxRooms do
				assert(type(built.Cells[slot]) == "table", "missing cell " .. slot)
			end
			return built
		end)
		if ok then
			local built = result :: any
			built.Width = tonumber(built.Width) or built.Frame.Size.X.Offset
			built.Height = tonumber(built.Height) or built.Frame.Size.Y.Offset
			if type(built.SetDark) ~= "function" then
				built.SetDark = function() end
			end
			if type(built.Update) ~= "function" then
				built.Update = function() end
			end
			if type(built.Destroy) ~= "function" then
				built.Destroy = function()
					built.Frame:Destroy()
				end
			end
			return built :: Exterior
		end
		warn("[HouseOverview] HouseExterior : " .. tostring(result))
		-- Nettoyage d'une construction ratée
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	return buildFallback(parent, size)
end

----------------------------------------------------------------------
-- Vue d'ensemble
----------------------------------------------------------------------

function HouseOverview.new(parent: Frame, handlers: Handlers): Overview
	local overview: Overview
	local house: HouseData? = nil
	local overridesNow: HouseCommon.Overrides? = nil
	local size: SizeDef? = nil
	local exterior: Exterior? = nil
	local cards: { [string]: Card } = {}
	local empties: { [number]: EmptySlot } = {}
	local localSlots: { [string]: number } = {} -- déplacements pas encore confirmés
	local dark = false
	local arranging = false
	local drag: Drag? = nil
	local pending: Pending? = nil
	local fitScale = 1
	local zoomed = false
	local zoomToken = 0
	local clock = 0

	local root = UIUtil.Create("Frame", {
		Name = "Overview",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 5,
		Parent = parent,
	})
	root:SetAttribute("DarkSkinIgnore", true)
	UIUtil.Corner(root, 20)
	local probe = UIUtil.Create("Frame", {
		Name = "Probe",
		Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1,
		Parent = root,
	})

	------------------------------------------------------------------
	-- Ciel
	------------------------------------------------------------------
	local sky = UIUtil.Create("Frame", {
		Name = "Sky",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = root,
	})
	local skyGradient = UIUtil.Gradient(sky, SKY_DAY, 90)
	local sun = UIUtil.Create("Frame", {
		Name = "Sun",
		Size = UDim2.fromOffset(120, 120),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -90, 0, 70),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = sky,
	})
	local sunGlow = Circle(sun, 60, 60, 120, 120, Color3.fromRGB(255, 240, 180), 0.75, 1)
	local sunDisc = Circle(sun, 60, 60, 60, 60, Color3.fromRGB(255, 226, 130), 0, 2)
	local moonBite = Circle(sunDisc, 42, 20, 44, 44, Color3.fromRGB(40, 34, 95), 0, 3)
	moonBite.Visible = false
	local clouds: { { Frame: Frame, X: number, Y: number, Speed: number } } = {}
	for index = 1, 5 do
		local holder = UIUtil.Create("Frame", {
			Name = "Cloud" .. index,
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(140, 90),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = sky,
		})
		local w = 80 + (index * 37 % 60)
		HousePatterns.Cloud(holder, 70, 90, w, WHITE, 0.12 + (index % 3) * 0.1, 1)
		table.insert(clouds, { Frame = holder, X = (index * 0.23) % 1, Y = 0.1 + (index * 0.17) % 0.45, Speed = 0.006 + (index % 4) * 0.003 })
	end
	local stars: { Frame } = {}
	for index = 1, 26 do
		local s = 5 + (index * 7 % 6)
		local holder = UIUtil.Create("Frame", {
			Name = "Star" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale((index * 0.618) % 1, 0.03 + ((index * 0.382) % 1) * 0.62),
			Size = UDim2.fromOffset(s, s),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 2,
			Parent = sky,
		})
		HousePatterns.Sparkle(holder, s / 2, s / 2, s, Color3.fromRGB(255, 244, 196), 0.1, 1)
		holder:SetAttribute("Phase", index * 1.7)
		table.insert(stars, holder)
	end
	-- Collines au loin
	local hills: { Frame } = {}
	for index, info in ipairs({ { 0.12, 0.62, Color3.fromRGB(190, 232, 190) }, { 0.5, 0.9, Color3.fromRGB(176, 226, 180) }, { 0.88, 0.66, Color3.fromRGB(196, 236, 196) } }) do
		local hill = UIUtil.Create("Frame", {
			Name = "Hill" .. index,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(info[1], 0, 0.8, 0),
			Size = UDim2.new(info[2], 0, 0.6, 0),
			BackgroundColor3 = info[3],
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = sky,
		})
		Round(hill)
		hill:SetAttribute("DayColor", info[3])
		table.insert(hills, hill)
	end

	------------------------------------------------------------------
	-- Immeuble (zoom) et calque de glissement
	------------------------------------------------------------------
	local zoom = UIUtil.Create("Frame", {
		Name = "Zoom",
		Size = UDim2.fromOffset(100, 100),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = root,
	})
	local zoomScale = UIUtil.Create("UIScale", { Parent = zoom })
	local dragLayer = UIUtil.Create("Frame", {
		Name = "DragLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = zoom,
	})
	local dropMark = UIUtil.Create("Frame", {
		Name = "Drop",
		BackgroundColor3 = C.Pink,
		BackgroundTransparency = 0.72,
		Visible = false,
		ZIndex = 1,
		Parent = dragLayer,
	})
	UIUtil.Corner(dropMark, 14)
	UIUtil.Stroke(dropMark, WHITE, 5, 0)
	local dropChip = UIUtil.Chip({
		Name = "DropChip",
		Text = "",
		Color = C.PinkDeep,
		TextColor3 = WHITE,
		Height = 28,
		TextSize = 16,
		ZIndex = 2,
		Parent = dropMark,
	})
	dropChip.AnchorPoint = Vector2.new(0.5, 0.5)
	dropChip.Position = UDim2.fromScale(0.5, 0.5)
	local dropChipScale = UIUtil.Create("UIScale", { Parent = dropChip })

	-- Astuce en bas
	local hint = UIUtil.Chip({
		Name = "Hint",
		Text = "",
		Color = WHITE,
		TextColor3 = C.Ink,
		Height = 26,
		TextSize = 14,
		ZIndex = 20,
		Parent = root,
	})
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -8)

	local function refreshHint()
		local label = hint:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = arranging and Locale.T("✋ Drag a room onto another spot  •  tap it for options")
				or Locale.T("👆 Tap a room to decorate it")
		end
		hint.BackgroundColor3 = arranging and C.Butter or WHITE
	end

	------------------------------------------------------------------
	-- Coordonnées
	------------------------------------------------------------------

	-- Position écran -> px de maquette de l'immeuble
	local function screenToBuilding(position: Vector2): Vector2
		local ext = exterior
		if not ext then
			return Vector2.zero
		end
		local absSize = zoom.AbsoluteSize
		if absSize.X <= 0 then
			return Vector2.zero
		end
		local k = absSize.X / ext.Width
		return (position - zoom.AbsolutePosition) / k
	end

	local function slotOf(room: Room): number
		return localSlots[room.Id] or room.Slot
	end

	local function rectOf(slot: number): Rect?
		local ext = exterior
		return ext and ext.Cells[slot] or nil
	end

	-- Taille "constante à l'écran" des pastilles (bornée par la taille des cases)
	local function labelScale(): number
		local wanted = 1 / math.max(0.05, fitScale)
		local limit = Interface.IsPhone() and 2.6 or 2.2
		return math.clamp(wanted * (Interface.IsPhone() and 0.8 or 0.95), 1, limit)
	end

	------------------------------------------------------------------
	-- Cartes (pièces) et cases vides
	------------------------------------------------------------------

	local function roomStats(room: Room): (number, number, number)
		local currentHouse = house :: HouseData
		local placed = (overridesNow and overridesNow[room.Id]) or room.Placed
		local comfort = HouseCommon.RoomComfort(currentHouse, room, placed)
		local favorites = 0
		for _, entry in ipairs(placed) do
			local item = HouseCommon.ItemsById[entry.I]
			if item and HouseCommon.IsFavorite(room, item) then
				favorites += 1
			end
		end
		return comfort, favorites, #placed
	end

	local function chipText(room: Room): string
		local roomType = HouseCommon.GetRoomType(room)
		local comfort, favorites = roomStats(room)
		local comfortText = string.format("❤️ %d", math.floor(comfort + 0.5))
		if Interface.IsPhone() then
			return string.format("%s %s", roomType.Icon, comfortText)
		end
		local text = string.format("%s %s  %s", roomType.Icon, HouseCommon.Name(roomType), comfortText)
		if favorites > 0 then
			text ..= string.format("  ✨%d", favorites)
		end
		return text
	end

	local function paintCard(card: Card)
		local showRing = card.Hovered or arranging or (drag ~= nil and (drag :: Drag).Card == card)
		card.Hover.Visible = showRing
		card.HoverStroke.Color = arranging and C.Lilac or WHITE
		card.Hover.BackgroundTransparency = card.Hovered and not arranging and 0.85 or 1
		card.Menu.Visible = arranging and not (drag ~= nil and (drag :: Drag).Card == card)
	end

	local function placeCard(card: Card, animate: boolean)
		local rect = rectOf(card.Slot)
		if not rect then
			return
		end
		local target = UDim2.fromOffset(rect.X, rect.Y)
		if animate then
			UIUtil.Tween(card.Frame, 0.32, { Position = target }, Enum.EasingStyle.Back)
		else
			card.Frame.Position = target
		end
	end

	local function newCard(room: Room): Card
		local ext = exterior :: Exterior
		local rect = ext.Cells[slotOf(room)] or ext.Cells[1]
		local frame = UIUtil.Create("Frame", {
			Name = "Room_" .. room.Id,
			Size = UDim2.fromOffset(rect.W, rect.H),
			Position = UDim2.fromOffset(rect.X, rect.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = ext.CellLayer,
		})
		local scale = UIUtil.Create("UIScale", { Parent = frame })
		local shadow = Box(frame, 10, 14, rect.W, rect.H, BLACK, 0.7, 0)
		Round(shadow, UDim.new(0, 10))
		shadow.Name = "Shadow"
		shadow.Visible = false
		local mini = HouseMiniRoom.new(frame, rect.W, rect.H)
		mini.Frame.ZIndex = 1
		local hover = UIUtil.Create("Frame", {
			Name = "Hover",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 3,
			Parent = frame,
		})
		UIUtil.Corner(hover, 6)
		local hoverStroke = UIUtil.Stroke(hover, WHITE, 5, 0.05)
		local chip = UIUtil.Chip({
			Name = "Label",
			Text = "",
			Color = WHITE,
			TextColor3 = C.Ink,
			Height = 24,
			TextSize = 14,
			ZIndex = 4,
			Parent = frame,
		})
		chip.AnchorPoint = Vector2.new(0, 0)
		chip.Position = UDim2.fromOffset(8, 8)
		chip.BackgroundTransparency = 0.08
		local chipScale = UIUtil.Create("UIScale", { Parent = chip })
		local hit = UIUtil.Create("TextButton", {
			Name = "Hit",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 5,
			Parent = frame,
		})
		local menu = UIUtil.Create("TextButton", {
			Name = "Menu",
			Size = UDim2.fromOffset(34, 34),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			BackgroundColor3 = C.Lilac,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = "⋯",
			TextColor3 = WHITE,
			TextSize = 24,
			Visible = false,
			ZIndex = 6,
			Parent = frame,
		})
		UIUtil.Corner(menu, UDim.new(1, 0))
		UIUtil.Stroke(menu, WHITE, 2, 0)
		local menuScale = UIUtil.Create("UIScale", { Parent = menu })
		local card: Card = {
			RoomId = room.Id,
			Frame = frame,
			Scale = scale,
			Mini = mini,
			Hover = hover,
			HoverStroke = hoverStroke,
			Chip = chip,
			ChipLabel = chip:FindFirstChild("Label") :: TextLabel,
			ChipScale = chipScale,
			Menu = menu,
			MenuScale = menuScale,
			Shadow = shadow,
			Hit = hit,
			Slot = slotOf(room),
			Hovered = false,
		}
		hit.MouseEnter:Connect(function()
			if drag then
				return
			end
			card.Hovered = true
			paintCard(card)
			UIUtil.Pop(chip, 1.1, 0.25)
		end)
		hit.MouseLeave:Connect(function()
			card.Hovered = false
			paintCard(card)
		end)
		hit.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
				return
			end
			if not arranging or drag or zoomed then
				return
			end
			pending = { RoomId = card.RoomId, Input = input, Start = Vector2.new(input.Position.X, input.Position.Y) }
		end)
		hit.Activated:Connect(function()
			if arranging or drag or zoomed then
				return
			end
			SoundManager.Play("Click", 1.1)
			handlers.OnOpenRoom(card.RoomId)
		end)
		menu.Activated:Connect(function()
			pending = nil
			handlers.OnRoomMenu(card.RoomId)
		end)
		return card
	end

	local function newEmpty(slot: number): EmptySlot
		local ext = exterior :: Exterior
		local rect = ext.Cells[slot]
		local frame = UIUtil.Create("Frame", {
			Name = "Empty_" .. slot,
			Size = UDim2.fromOffset(rect.W, rect.H),
			Position = UDim2.fromOffset(rect.X, rect.Y),
			BackgroundColor3 = Color3.fromRGB(255, 244, 250),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = ext.CellLayer,
		})
		UIUtil.Gradient(frame, ColorSequence.new(WHITE, Color3.fromRGB(236, 226, 246)), 90)
		-- Pointillés
		local dash, gap, inset = 14, 10, 8
		local color = C.Pink
		local x = inset
		while x < rect.W - inset do
			local w = math.min(dash, rect.W - inset - x)
			Box(frame, x, inset, w, 3, color, 0.1, 2)
			Box(frame, x, rect.H - inset - 3, w, 3, color, 0.1, 2)
			x += dash + gap
		end
		local y = inset + dash + gap
		while y < rect.H - inset - dash do
			Box(frame, inset, y, 3, dash, color, 0.1, 2)
			Box(frame, rect.W - inset - 3, y, 3, dash, color, 0.1, 2)
			y += dash + gap
		end
		local content = UIUtil.Create("Frame", {
			Name = "Content",
			Size = UDim2.fromOffset(160, 96),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = frame,
		})
		local contentScale = UIUtil.Create("UIScale", { Parent = content })
		local plus = Circle(content, 80, 22, 40, 40, C.PinkDeep, 0, 1)
		UIUtil.Stroke(plus, WHITE, 3, 0)
		UIUtil.Create("TextLabel", {
			Name = "Icon",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = "+",
			TextColor3 = WHITE,
			TextSize = 30,
			ZIndex = 2,
			Parent = plus,
		})
		UIUtil.Create("TextLabel", {
			Name = "Title",
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 46),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = Locale.T("New room"),
			TextColor3 = C.Ink,
			TextSize = 17,
			ZIndex = 2,
			Parent = content,
		})
		local price = UIUtil.Create("TextLabel", {
			Name = "Price",
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 70),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = "",
			TextColor3 = C.PinkDeep,
			TextSize = 15,
			ZIndex = 2,
			Parent = content,
		})
		local hit = UIUtil.Create("TextButton", {
			Name = "Hit",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			Parent = frame,
		})
		local empty: EmptySlot = {
			Slot = slot,
			Frame = frame,
			Content = content,
			ContentScale = contentScale,
			Price = price,
			Plus = plus,
			Hit = hit,
		}
		hit.MouseEnter:Connect(function()
			if not drag then
				UIUtil.Tween(contentScale, 0.15, { Scale = labelScale() * 1.08 }, Enum.EasingStyle.Back)
				frame.BackgroundTransparency = 0
			end
		end)
		hit.MouseLeave:Connect(function()
			UIUtil.Tween(contentScale, 0.15, { Scale = labelScale() })
			frame.BackgroundTransparency = 0.15
		end)
		hit.Activated:Connect(function()
			if drag or zoomed then
				return
			end
			SoundManager.Play("Click", 1.2)
			UIUtil.Pop(plus, 1.25, 0.3)
			handlers.OnEmptySlot(slot)
		end)
		return empty
	end

	local function clearAll()
		for _, card in pairs(cards) do
			card.Mini.Destroy()
			card.Frame:Destroy()
		end
		table.clear(cards)
		for _, empty in pairs(empties) do
			empty.Frame:Destroy()
		end
		table.clear(empties)
		local ext = exterior
		if ext then
			ext.Destroy()
			exterior = nil
		end
		for _, child in ipairs(zoom:GetChildren()) do
			if child ~= dragLayer and child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local refit: (force: boolean?) -> ()

	local function applyLabelScales()
		local s = labelScale()
		for _, card in pairs(cards) do
			card.ChipScale.Scale = s
			card.MenuScale.Scale = s
			card.Chip.Position = UDim2.fromOffset(6 * s, 6 * s)
			card.Menu.Position = UDim2.new(1, -6 * s, 0, 6 * s)
		end
		for _, empty in pairs(empties) do
			local rect = rectOf(empty.Slot)
			local limit = rect and math.min(rect.W / 170, rect.H / 104) or s
			empty.ContentScale.Scale = math.min(s, limit)
		end
		dropChipScale.Scale = s
	end

	-- Remet chaque pièce / case vide à sa place (sans reconstruire)
	local function layoutCells(animate: boolean)
		local currentHouse = house
		local currentSize = size
		if not currentHouse or not currentSize then
			return
		end
		local used: { [number]: boolean } = {}
		for _, room in ipairs(currentHouse.Rooms) do
			local card = cards[room.Id]
			if card then
				local slot = slotOf(room)
				used[slot] = true
				if card.Slot ~= slot then
					card.Slot = slot
					if not (drag and (drag :: Drag).Card == card) then
						placeCard(card, animate)
					end
				end
			end
		end
		local cost = HouseCommon.RoomCost(currentHouse)
		local affordable = HouseCommon.Dopamine() >= cost
		for slot = 1, currentSize.MaxRooms do
			local isEmpty = not used[slot]
			local empty = empties[slot]
			if isEmpty and not empty and exterior then
				empty = newEmpty(slot)
				empties[slot] = empty
				applyLabelScales()
			end
			if empty then
				empty.Frame.Visible = isEmpty
				empty.Price.Text = "💧 " .. NumberFormatter.Format(cost)
				empty.Price.TextColor3 = affordable and Theme.Colors.Green or C.PinkDeep
			end
		end
	end

	------------------------------------------------------------------
	-- Glisser-déposer (mode rangement)
	------------------------------------------------------------------

	local function slotAt(point: Vector2): number?
		local ext = exterior
		local currentSize = size
		if not ext or not currentSize then
			return nil
		end
		local best, bestDistance = nil, math.huge
		for slot = 1, currentSize.MaxRooms do
			local rect = ext.Cells[slot]
			if rect then
				local cx = math.clamp(point.X, rect.X, rect.X + rect.W)
				local cy = math.clamp(point.Y, rect.Y, rect.Y + rect.H)
				local distance = (Vector2.new(cx, cy) - point).Magnitude
				if distance < bestDistance then
					best, bestDistance = slot, distance
				end
			end
		end
		if bestDistance > 60 then
			return nil
		end
		return best
	end

	local function roomAt(slot: number): Room?
		local currentHouse = house
		if not currentHouse then
			return nil
		end
		for _, room in ipairs(currentHouse.Rooms) do
			if slotOf(room) == slot then
				return room
			end
		end
		return nil
	end

	local function showDrop(slot: number?)
		local current = drag
		if not slot or not current or slot == current.FromSlot then
			dropMark.Visible = false
			return
		end
		local rect = rectOf(slot) :: Rect
		dropMark.Position = UDim2.fromOffset(rect.X - 4, rect.Y - 4)
		dropMark.Size = UDim2.fromOffset(rect.W + 8, rect.H + 8)
		local label = dropChip:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = roomAt(slot) and Locale.T("⇄ Swap") or Locale.T("📍 Move here")
		end
		if not dropMark.Visible then
			dropMark.Visible = true
			UIUtil.Pop(dropChip, 0.6, 0.25)
		end
	end

	local function beginDrag(roomId: string, screenPos: Vector2)
		local card = cards[roomId]
		if not card or drag or not exterior then
			return
		end
		local rect = rectOf(card.Slot) :: Rect
		local point = screenToBuilding(screenPos)
		local corner = Vector2.new(rect.X, rect.Y)
		drag = {
			Card = card,
			FromSlot = card.Slot,
			Offset = corner - point,
			Target = corner,
			Current = corner,
			Over = nil,
		}
		card.Frame.Parent = dragLayer
		card.Frame.ZIndex = 3
		card.Shadow.Visible = true
		UIUtil.Tween(card.Scale, 0.15, { Scale = 1.06 }, Enum.EasingStyle.Back)
		card.Hovered = false
		paintCard(card)
		SoundManager.Play("Click", 1.3)
		-- Case de départ : contour en pointillés (la case vide réapparaît)
		local empty = empties[card.Slot]
		if not empty and exterior then
			empty = newEmpty(card.Slot)
			empties[card.Slot] = empty
			applyLabelScales()
		end
		if empty then
			empty.Frame.Visible = true
			empty.Content.Visible = false
		end
	end

	local function dragTo(screenPos: Vector2)
		local current = drag
		if not current then
			return
		end
		local point = screenToBuilding(screenPos)
		current.Target = point + current.Offset
		local rect = rectOf(current.FromSlot) :: Rect
		local over = slotAt(point)
		if over ~= current.Over then
			current.Over = over
			showDrop(over)
			if over and over ~= current.FromSlot then
				SoundManager.Play("Click", 1.5)
			end
		end
		-- (au premier appel, la carte saute presque sous le doigt)
		if (current.Current - Vector2.new(rect.X, rect.Y)).Magnitude < 1 then
			current.Current = current.Current:Lerp(current.Target, 0.5)
		end
	end

	local function finishDrag()
		local current = drag
		if not current then
			return
		end
		drag = nil
		dropMark.Visible = false
		local card = current.Card
		local ext = exterior
		card.Frame.Parent = ext and ext.CellLayer or dragLayer
		card.Frame.ZIndex = 2
		card.Shadow.Visible = false
		UIUtil.Tween(card.Scale, 0.2, { Scale = 1 })
		local empty = empties[current.FromSlot]
		if empty then
			empty.Content.Visible = true
		end
		local target = current.Over
		if target and target ~= current.FromSlot then
			local other = roomAt(target)
			localSlots[card.RoomId] = target
			if other then
				localSlots[other.Id] = current.FromSlot
			end
			card.Slot = -1 -- repositionné par layoutCells (animé)
			layoutCells(true)
			SoundManager.Play("Pop", 1.1)
			handlers.OnMoveRoom(card.RoomId, target)
		else
			placeCard(card, true)
			layoutCells(false)
		end
		paintCard(card)
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseMovement and kind ~= Enum.UserInputType.Touch then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		local waiting = pending
		if waiting and not drag then
			local matches = (kind == Enum.UserInputType.Touch and input == waiting.Input)
				or (kind == Enum.UserInputType.MouseMovement and waiting.Input.UserInputType == Enum.UserInputType.MouseButton1)
			if matches and (position - waiting.Start).Magnitude >= DRAG_THRESHOLD then
				pending = nil
				beginDrag(waiting.RoomId, waiting.Start)
				dragTo(position)
			end
			return
		end
		if drag then
			dragTo(position)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local waiting = pending
		if waiting then
			pending = nil
			if waiting.Input == input or kind == Enum.UserInputType.MouseButton1 then
				-- Simple toucher en mode rangement : menu de la pièce
				if arranging and not drag then
					handlers.OnRoomMenu(waiting.RoomId)
				end
			end
			return
		end
		if drag then
			finishDrag()
		end
	end)

	------------------------------------------------------------------
	-- Mise à l'échelle et zoom
	------------------------------------------------------------------

	local function available(): Vector2
		local factor = probe.AbsoluteSize.X / 100
		if factor <= 0 then
			return Vector2.new(1000, 560)
		end
		return root.AbsoluteSize / factor
	end

	refit = function(force: boolean?)
		local ext = exterior
		if not ext then
			return
		end
		local space = available()
		local bottom = 34 -- place de l'astuce
		local newScale = math.max(0.05, math.min((space.X - 24) / ext.Width, (space.Y - bottom - 16) / ext.Height))
		local changed = math.abs(newScale - fitScale) > 1e-4
		fitScale = newScale
		if not zoomed then
			zoomScale.Scale = newScale
			zoom.Position = UDim2.new(0.5, 0, 0.5, -bottom / 2 + 4)
		end
		if changed or force == true then
			applyLabelScales()
		end
	end

	-- Position / échelle du zoom qui remplit la zone avec la case
	local function zoomTarget(slot: number): (number, UDim2)
		local ext = exterior :: Exterior
		local rect = ext.Cells[slot]
		local space = available()
		local s = math.min(space.X / rect.W, space.Y / rect.H) * 0.92
		local cx = rect.X + rect.W / 2 - ext.Width / 2
		local cy = rect.Y + rect.H / 2 - ext.Height / 2
		return s, UDim2.new(0.5, -cx * s, 0.5, -cy * s)
	end

	local function rebuild()
		local currentSize = size :: SizeDef
		clearAll()
		exterior = buildExterior(zoom, currentSize)
		local ext = exterior :: Exterior
		zoom.Size = UDim2.fromOffset(ext.Width, ext.Height)
		ext.Frame.Position = UDim2.fromScale(0.5, 0.5)
		ext.Frame.ZIndex = 1
		ext.SetDark(dark)
		refit(true)
	end

	------------------------------------------------------------------
	-- API
	------------------------------------------------------------------

	overview = {
		Frame = root,
		SetHouse = function(newHouse: HouseData, overrides: HouseCommon.Overrides?)
			house = newHouse
			overridesNow = overrides
			local newSize = HouseCommon.GetSize(newHouse)
			if not size or newSize.Id ~= (size :: SizeDef).Id or not exterior then
				size = newSize
				localSlots = {}
				rebuild()
			end
			-- Déplacements confirmés par le serveur : on oublie la version locale
			for roomId, slot in pairs(localSlots) do
				local room = HouseCommon.GetRoom(newHouse, roomId)
				if not room or room.Slot == slot then
					localSlots[roomId] = nil
				end
			end
			local seen: { [string]: boolean } = {}
			for _, room in ipairs(newHouse.Rooms) do
				seen[room.Id] = true
				if slotOf(room) <= newSize.MaxRooms then
					local card = cards[room.Id]
					if not card then
						card = newCard(room)
						cards[room.Id] = card
						applyLabelScales()
						paintCard(card)
					end
					local placed = (overrides and overrides[room.Id]) or room.Placed
					card.Mini.Set(room, newSize, placed)
					card.Mini.SetDark(dark)
					local text = chipText(room)
					if card.ChipLabel.Text ~= text then
						card.ChipLabel.Text = text
					end
				end
			end
			for roomId, card in pairs(cards) do
				if not seen[roomId] then
					card.Mini.Destroy()
					card.Frame:Destroy()
					cards[roomId] = nil
				end
			end
			layoutCells(true)
		end,
		SetDark = function(value: boolean)
			dark = value
			skyGradient.Color = value and SKY_NIGHT or SKY_DAY
			sunDisc.BackgroundColor3 = value and Color3.fromRGB(255, 244, 200) or Color3.fromRGB(255, 226, 130)
			sunGlow.BackgroundColor3 = value and Color3.fromRGB(200, 200, 255) or Color3.fromRGB(255, 240, 180)
			sunGlow.BackgroundTransparency = value and 0.86 or 0.75
			moonBite.BackgroundColor3 = Color3.fromRGB(30, 28, 80)
			moonBite.Visible = value
			for _, star in ipairs(stars) do
				star.Visible = value
			end
			for _, cloud in ipairs(clouds) do
				for _, child in ipairs(cloud.Frame:GetDescendants()) do
					if child:IsA("Frame") then
						child.BackgroundColor3 = value and Color3.fromRGB(110, 100, 170) or WHITE
					end
				end
			end
			for _, hill in ipairs(hills) do
				local day = hill:GetAttribute("DayColor")
				if typeof(day) == "Color3" then
					hill.BackgroundColor3 = value and day:Lerp(Color3.fromRGB(40, 36, 100), 0.55) or day
				end
			end
			local ext = exterior
			if ext then
				ext.SetDark(value)
			end
			for _, card in pairs(cards) do
				card.Mini.SetDark(value)
			end
		end,
		SetArranging = function(on: boolean)
			if arranging == on then
				return
			end
			arranging = on
			pending = nil
			if not on and drag then
				finishDrag()
			end
			for _, card in pairs(cards) do
				paintCard(card)
			end
			refreshHint()
			UIUtil.Pop(hint, 1.1, 0.3)
		end,
		IsArranging = function(): boolean
			return arranging
		end,
		Update = function(dt: number)
			clock += dt
			for _, cloud in ipairs(clouds) do
				cloud.X = (cloud.X + cloud.Speed * dt) % 1.3
				cloud.Frame.Position = UDim2.fromScale(cloud.X - 0.15, cloud.Y)
			end
			if dark then
				for _, star in ipairs(stars) do
					local phase = tonumber(star:GetAttribute("Phase")) or 0
					local wave = 0.5 + 0.5 * math.sin(clock * 2 + phase)
					for _, child in ipairs(star:GetChildren()) do
						if child:IsA("Frame") then
							child.BackgroundTransparency = 0.05 + wave * 0.5
						end
					end
				end
			end
			local ext = exterior
			if ext then
				ext.Update(dt)
			end
			local current = drag
			if current then
				local alpha = 1 - math.exp(-DRAG_SMOOTHING * dt)
				current.Current = current.Current:Lerp(current.Target, alpha)
				current.Card.Frame.Position = UDim2.fromOffset(current.Current.X, current.Current.Y)
			end
			if arranging then
				local wave = 0.5 + 0.5 * math.sin(clock * 4)
				for _, card in pairs(cards) do
					card.HoverStroke.Transparency = 0.05 + wave * 0.45
				end
			end
		end,
		Refit = function()
			refit(true)
		end,
		ZoomIn = function(roomId: string, done: () -> ())
			local card = cards[roomId]
			if not card or not exterior then
				done()
				return
			end
			zoomToken += 1
			local token = zoomToken
			zoomed = true
			local s, position = zoomTarget(card.Slot)
			UIUtil.Tween(zoomScale, ZOOM_TIME, { Scale = s }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			UIUtil.Tween(zoom, ZOOM_TIME, { Position = position }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			SoundManager.Play("Open", 1.2)
			task.delay(ZOOM_TIME, function()
				if token == zoomToken then
					done()
				end
			end)
		end,
		ZoomOut = function(roomId: string?)
			zoomToken += 1
			local card = roomId and cards[roomId :: string]
			if card and exterior then
				local s, position = zoomTarget(card.Slot)
				zoomScale.Scale = s
				zoom.Position = position
			end
			zoomed = false
			local space = available()
			local ext = exterior
			if ext then
				local bottom = 34
				local target = math.max(0.05, math.min((space.X - 24) / ext.Width, (space.Y - bottom - 16) / ext.Height))
				fitScale = target
				UIUtil.Tween(zoomScale, ZOOM_TIME, { Scale = target }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				UIUtil.Tween(zoom, ZOOM_TIME, { Position = UDim2.new(0.5, 0, 0.5, -bottom / 2 + 4) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				applyLabelScales()
			end
		end,
		Pulse = function(roomId: string)
			local card = cards[roomId]
			if card then
				card.Scale.Scale = 0.85
				UIUtil.Tween(card.Scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
				UIUtil.Pop(card.Chip, 1.3, 0.4)
			end
		end,
		CancelMoves = function()
			localSlots = {}
			layoutCells(true)
		end,
		CellScreenCenter = function(slot: number): Vector2?
			local rect = rectOf(slot)
			local ext = exterior
			if not rect or not ext then
				return nil
			end
			local k = zoom.AbsoluteSize.X / ext.Width
			return zoom.AbsolutePosition + Vector2.new(rect.X + rect.W / 2, rect.Y + rect.H / 2) * k
		end,
		BeginDrag = beginDrag,
		DragTo = dragTo,
		EndDrag = finishDrag,
		IsDragging = function(): boolean
			return drag ~= nil
		end,
	}

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		refit()
	end)
	probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		refit()
	end)
	Interface.DeviceChanged:Connect(function()
		refit(true)
		local currentHouse = house
		if currentHouse then
			for _, room in ipairs(currentHouse.Rooms) do
				local card = cards[room.Id]
				if card then
					card.ChipLabel.Text = chipText(room)
				end
			end
		end
	end)
	refreshHint()
	return overview
end

return HouseOverview
