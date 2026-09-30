--[[
	HouseFacadeEditor (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseFacadeEditor

	(v10 HOUSE10) 🏡 Éditeur de l'EXTÉRIEUR de la maison, avec un APERÇU 3D
	en direct (la vraie façade de la ville : HouseFacade, dans un
	ViewportFrame, qu'on fait tourner au doigt / à la souris).
	  - onglets (Shared/HouseOptions.GROUPS) : Style, Façade, Toit, Fenêtres,
	    Entrée, Jardin ; chaque réglage = une rangée de choix (pastilles de
	    couleur ou cartes icône + nom + prix / ✓ / 🔒 visites à l'océan) ;
	  - le projet est essayé sur l'aperçu tout de suite (sans rien payer) ;
	    total des choix pas encore achetés en bas, "✅ Appliquer" achète
	    tout d'un coup et applique (House "saveExterior", validé par le
	    serveur) ; "↺ Annuler" revient à la maison actuelle ;
	  - numéro de la maison (0 = automatique) ;
	  - mise en page ordinateur (aperçu à gauche, réglages à droite) et
	    téléphone (aperçu en haut, réglages en bas) ; suit la taille d'écran.
	Ouvert depuis "🏠 Ma maison" (onglet Extérieur) et, en ville, par la
	boîte aux lettres de SA maison (E).
	ScreenGui "HouseFacadeEditor" (DisplayOrder 60, KEEP_GUIS de la ville).

	API : HouseFacadeEditor.Open(options?) ; .Close() ; .IsOpen()
	  options = { Plot: number? (numéro automatique affiché) }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local UIUtil = require(Client.UIUtil)
local Theme = require(Client.Theme)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local HouseOptions = require(ReplicatedStorage.Shared.HouseOptions)
local HouseCommon = require(script.Parent.HouseCommon)

local World = Client:WaitForChild("World")
local HouseKit = require(World:WaitForChild("HouseKit") :: ModuleScript)
local HouseFacade = require(World:WaitForChild("HouseFacade") :: ModuleScript)

local HouseFacadeEditor = {}

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(62, 44, 72)
local PINK = Color3.fromRGB(255, 126, 182)
local PINK_DEEP = Color3.fromRGB(226, 72, 140)
local CARD = Color3.fromRGB(255, 250, 253)
local SOFT = Color3.fromRGB(246, 238, 246)
local MINT = Color3.fromRGB(70, 190, 140)
local LOCK = Color3.fromRGB(150, 140, 160)
local REBUILD_DELAY = 0.12 -- (s) aperçu refait après le dernier clic

local LocalPlayer = Players.LocalPlayer

type Chip = { Button: TextButton, Stroke: UIStroke, Kind: string, Id: string, Price: TextLabel? }

local state = {
	Gui = nil :: ScreenGui?,
	Open = false,
	Design = {} :: { [string]: any }, -- projet en cours (Kind -> Id, Num)
	Saved = {} :: { [string]: any }, -- extérieur actuel (serveur)
	Group = "Style",
	Chips = {} :: { Chip },
	Headers = {} :: { [string]: TextLabel },
	Dirty = true,
	ChangedAt = 0,
	Yaw = math.rad(28),
	Pitch = math.rad(16),
	Zoom = 1,
	Dragging = false,
	DragX = 0,
	DragY = 0,
	LastDrag = -math.huge,
	Model = nil :: Model?,
	Size = nil :: any,
	Plot = 1,
	Busy = false,
	Connections = {} :: { RBXScriptConnection },
	Parts = {} :: { [string]: any },
}

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

local function houseData(): any
	local data = ClientState.Data
	return type(data) == "table" and type(data.House) == "table" and data.House or {}
end

local function ownedExt(): { [string]: boolean }
	local owned = houseData().OwnedExt
	return type(owned) == "table" and owned or {}
end

local function rebirths(): number
	local data = ClientState.Data
	return type(data) == "table" and tonumber(data.Rebirths) or 0
end

local function currentSize(): any
	local ok, house = pcall(HouseCommon.GetHouse, ClientState.Data)
	if ok and house then
		return HouseCommon.GetSize(house)
	end
	return Config.House.Sizes[1]
end

local function price(value: number): string
	return "💧 " .. NumberFormatter.Format(value)
end

-- Apparence de SA maison (couleurs 2D, jardin, garage) + le projet
local function looksFor(design: { [string]: any }): any
	local house = houseData()
	local function lookColor(kind: string, id: any): Color3?
		local byId = Config.HouseLooksById and Config.HouseLooksById[kind]
		local entry = byId and type(id) == "string" and byId[id] or nil
		return entry and typeof(entry.Color) == "Color3" and entry.Color or nil
	end
	local roofStyle = Config.HouseLooksById and Config.HouseLooksById.RoofStyle and Config.HouseLooksById.RoofStyle[tostring(house.RoofStyle)]
	return {
		Wall = lookColor("Facade", house.Facade),
		Roof = lookColor("Roof", house.Roof),
		Pattern = roofStyle and tostring(roofStyle.Pattern) or "None",
		Garden = type(house.Garden) == "table" and house.Garden or {},
		Rooms = {},
		Name = LocalPlayer and LocalPlayer.DisplayName or "",
		Garage = LocalPlayer ~= nil and LocalPlayer:GetAttribute("DopamineGarage") == true,
		Ext = design,
		Plot = state.Plot,
	}
end

----------------------------------------------------------------------
-- Aperçu 3D
----------------------------------------------------------------------

local function rebuildPreview()
	local view: ViewportFrame? = state.Parts.View
	if not view then
		return
	end
	if state.Model then
		state.Model:Destroy()
		state.Model = nil
	end
	local model = Instance.new("Model")
	model.Name = "PreviewHouse"
	local folder = Instance.new("Folder")
	folder.Name = "Exterior"
	folder.Parent = model
	local size = currentSize()
	state.Size = size
	local kit = HouseKit.new(CFrame.new(), folder, 0)
	local ok, err = pcall(HouseFacade.Build, kit, size, looksFor(state.Design))
	if not ok then
		warn("[HouseFacadeEditor] " .. tostring(err))
	end
	-- (particules et SurfaceGui inutiles dans l'aperçu)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	model.Parent = view
	state.Model = model
	state.Dirty = false
end

local function updateCamera()
	local camera: Camera? = state.Parts.Camera
	if not camera then
		return
	end
	local dims = WorldLayout.Dims(state.Size or currentSize())
	local width = dims.Width + 24
	local height = dims.Height + 12
	local target = Vector3.new(0, height * 0.38, -dims.Depth * 0.35)
	-- toute la largeur de la maison dans le champ (selon le format de l'aperçu)
	local view: ViewportFrame? = state.Parts.View
	local aspect = 1.2
	if view and view.AbsoluteSize.Y > 10 then
		aspect = view.AbsoluteSize.X / view.AbsoluteSize.Y
	end
	local half = math.tan(math.rad(camera.FieldOfView) / 2)
	local fitWidth = (width / 2) / (half * aspect)
	local fitHeight = (height / 2) / half
	local dist = (math.max(fitWidth, fitHeight) * 1.05 + dims.Depth * 0.5) * state.Zoom
	local offset = CFrame.Angles(0, state.Yaw, 0) * CFrame.Angles(-state.Pitch, 0, 0) * Vector3.new(0, 0, dist)
	camera.CFrame = CFrame.lookAt(target + offset, target)
end

local function markDirty()
	state.Dirty = true
	state.ChangedAt = os.clock()
end

----------------------------------------------------------------------
-- Interface
----------------------------------------------------------------------

local function label(props: { [string]: any }): TextLabel
	local l = UIUtil.Create("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Title,
		Text = props.Text or "",
		TextColor3 = props.Color or INK,
		TextSize = props.TextSize or 16,
		TextWrapped = props.Wrap == true,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	return l
end

local function frame(props: { [string]: any }): Frame
	local f = UIUtil.Create("Frame", {
		Name = props.Name or "Frame",
		BackgroundColor3 = props.BackgroundColor3 or WHITE,
		BackgroundTransparency = props.BackgroundTransparency or 0,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	})
	return f
end

-- Choix actuel d'un genre dans le projet
local function chosen(kind: string): string
	local id = state.Design[kind]
	return if type(id) == "string" then id else HouseOptions.Default(kind)
end

local function refreshTotals()
	local owned = ownedExt()
	local total, toBuy, locked = HouseOptions.Quote(state.Design, owned, rebirths())
	local parts = state.Parts
	local totalLabel: TextLabel? = parts.Total
	local apply: TextButton? = parts.Apply
	local dopamine = HouseCommon.Dopamine()
	local changed = HouseOptions.Encode(state.Design) ~= HouseOptions.Encode(state.Saved)
	if totalLabel then
		if not changed then
			totalLabel.Text = Locale.T("Your house as it is now")
		elseif total <= 0 then
			totalLabel.Text = Locale.T("Free: styles you already own")
		else
			totalLabel.Text = Locale.T("Total: %s (%d new)", price(total), #toBuy)
		end
		totalLabel.TextColor3 = if total > dopamine and changed then Theme.Colors.Red else INK
	end
	if apply then
		local ok = changed and locked == nil and total <= dopamine and not state.Busy
		UIUtil.SetButtonEnabled(apply, ok)
		if locked then
			apply.Text = Locale.T("🔒 %d ocean visits", locked.Choice.Rebirths)
		elseif changed and total > 0 then
			apply.Text = Locale.T("✅ Buy & apply")
		else
			apply.Text = Locale.T("✅ Apply")
		end
	end
	-- cartes : sélection, possédé, prix, verrou
	for _, chip in ipairs(state.Chips) do
		local selected = chosen(chip.Kind) == chip.Id
		chip.Stroke.Color = if selected then PINK_DEEP else Color3.fromRGB(226, 214, 228)
		chip.Stroke.Thickness = if selected then 3 else 1.5
		local choice = HouseOptions.Choice(chip.Kind, chip.Id)
		if chip.Price and choice then
			local isOwned = HouseOptions.IsOwned(owned, chip.Kind, chip.Id)
			if isOwned then
				chip.Price.Text = if choice.Cost == 0 then Locale.T("Free") else "✓ " .. Locale.T("Owned")
				chip.Price.TextColor3 = MINT
			elseif choice.Rebirths > rebirths() then
				chip.Price.Text = "🔒 " .. Locale.T("%d visits", choice.Rebirths)
				chip.Price.TextColor3 = LOCK
			else
				chip.Price.Text = price(choice.Cost)
				chip.Price.TextColor3 = if choice.Cost > dopamine then Theme.Colors.Red else INK
			end
		end
	end
	for kind, header in pairs(state.Headers) do
		local def = HouseOptions.ByKind[kind]
		local choice = HouseOptions.Choice(kind, chosen(kind))
		if def and choice then
			header.Text = def.Icon .. " " .. Locale.T(def.Name) .. " · " .. Locale.T(choice.Name)
		end
	end
	local num: TextBox? = parts.Num
	if num and not num:IsFocused() then
		local n = HouseOptions.ValidNumber(state.Design.Num)
		num.Text = if n > 0 then tostring(n) else ""
		num.PlaceholderText = Locale.T("Auto (%d)", state.Plot)
	end
end

local function select(kind: string, id: string)
	local choice = HouseOptions.Choice(kind, id)
	if not choice then
		return
	end
	if id == HouseOptions.Default(kind) then
		state.Design[kind] = nil
	else
		state.Design[kind] = id
	end
	markDirty()
	refreshTotals()
end

-- Une rangée de choix pour un genre
local function kindRow(parent: Instance, def: any, order: number, phone: boolean)
	local row = frame({ Name = "Kind_" .. def.Id, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = order, ZIndex = 24, Parent = parent })
	row.AutomaticSize = Enum.AutomaticSize.Y
	UIUtil.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = row })
	local header = label({ Name = "Header", Text = "", TextSize = if phone then 15 else 16, Size = UDim2.new(1, 0, 0, 22), XAlign = Enum.TextXAlignment.Left, ZIndex = 25,
		LayoutOrder = 1, Parent = row })
	header.TextTruncate = Enum.TextTruncate.AtEnd
	state.Headers[def.Id] = header
	local grid = frame({ Name = "Choices", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, ZIndex = 24, Parent = row })
	grid.AutomaticSize = Enum.AutomaticSize.Y
	if def.Swatch then
		UIUtil.Create("UIGridLayout", { CellSize = UDim2.fromOffset(34, 34), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	else
		UIUtil.Create("UIGridLayout", { CellSize = UDim2.fromOffset(if phone then 96 else 104, 62), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid })
	end
	for index, choice in ipairs(def.Choices) do
		local button = UIUtil.Create("TextButton", {
			Name = "Choice_" .. choice.Id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = if def.Swatch and choice.Color then choice.Color else WHITE,
			LayoutOrder = index,
			ZIndex = 25,
			Parent = grid,
		})
		UIUtil.Corner(button, if def.Swatch then UDim.new(1, 0) else UDim.new(0, 12))
		local stroke = UIUtil.Stroke(button, Color3.fromRGB(226, 214, 228), 1.5)
		local chip: Chip = { Button = button, Stroke = stroke, Kind = def.Id, Id = choice.Id, Price = nil }
		if def.Swatch then
			if not choice.Color then
				-- "Auto" : pastille rayée (couleur du style)
				button.BackgroundColor3 = SOFT
				label({ Name = "Auto", Text = "🏠", TextSize = 16, ZIndex = 26, Parent = button })
			end
			if choice.Rebirths > 0 then
				label({ Name = "Lock", Text = "🔒", TextSize = 11, Size = UDim2.fromOffset(14, 14), Position = UDim2.new(1, -12, 1, -12), ZIndex = 27, Parent = button })
			end
		else
			label({ Name = "Icon", Text = choice.Icon, TextSize = 20, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 3), ZIndex = 26, Parent = button })
			local name = label({ Name = "Name", Text = Locale.T(choice.Name), Font = Theme.Fonts.Body, TextSize = 12, Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 25),
				ZIndex = 26, Parent = button })
			name.TextTruncate = Enum.TextTruncate.AtEnd
			chip.Price = label({ Name = "Price", Text = "", TextSize = 11, Size = UDim2.new(1, -6, 0, 14), Position = UDim2.fromOffset(3, 43), ZIndex = 26, Parent = button })
		end
		button.Activated:Connect(function()
			select(def.Id, choice.Id)
		end)
		table.insert(state.Chips, chip)
	end
end

-- Numéro de la maison (0 = automatique)
local function numberRow(parent: Instance, order: number)
	local row = frame({ Name = "Number", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = order, ZIndex = 24, Parent = parent })
	label({ Name = "Header", Text = "🔢 " .. Locale.T("House number"), TextSize = 16, Size = UDim2.new(1, 0, 0, 22), XAlign = Enum.TextXAlignment.Left, ZIndex = 25, Parent = row })
	local box = UIUtil.Create("TextBox", {
		Name = "NumBox",
		Text = "",
		PlaceholderText = "",
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextColor3 = INK,
		PlaceholderColor3 = LOCK,
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(140, 32),
		Position = UDim2.fromOffset(0, 24),
		ZIndex = 25,
		Parent = row,
	})
	UIUtil.Corner(box, 10)
	UIUtil.Stroke(box, Color3.fromRGB(226, 214, 228), 1.5)
	state.Parts.Num = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = string.gsub(box.Text, "%D", "")
		if #digits > 4 then
			digits = string.sub(digits, 1, 4)
		end
		if digits ~= box.Text then
			box.Text = digits
			return
		end
	end)
	box.FocusLost:Connect(function()
		local n = HouseOptions.ValidNumber(tonumber(box.Text) or 0)
		state.Design.Num = if n > 0 then n else nil
		markDirty()
		refreshTotals()
	end)
end

local function showGroup(group: string)
	state.Group = group
	local parts = state.Parts
	for id, page in pairs(parts.Pages or {}) do
		(page :: GuiObject).Visible = id == group
	end
	for id, tab in pairs(parts.Tabs or {}) do
		local on = id == group
		local button = tab :: TextButton
		button.BackgroundColor3 = if on then PINK else WHITE
		button.TextColor3 = if on then WHITE else INK
	end
end

local function setStatus(text: string, color: Color3?)
	local status: TextLabel? = state.Parts.Status
	if status then
		status.Text = text
		status.TextColor3 = color or INK
	end
end

local function apply()
	if state.Busy then
		return
	end
	local owned = ownedExt()
	local total, _, locked = HouseOptions.Quote(state.Design, owned, rebirths())
	if locked or total > HouseCommon.Dopamine() then
		local button: TextButton? = state.Parts.Apply
		if button then
			UIUtil.Shake(button)
		end
		return
	end
	state.Busy = true
	refreshTotals()
	local design = HouseOptions.Resolve(state.Design)
	-- (on n'envoie que les choix non par défaut + le numéro)
	local payload: { [string]: any } = {}
	for _, def in ipairs(HouseOptions.KINDS) do
		payload[def.Id] = design[def.Id]
	end
	payload.Num = design.Num
	task.spawn(function()
		local ok, message = HouseCommon.Invoke("saveExterior", payload)
		state.Busy = false
		if ok then
			state.Saved = table.clone(state.Design)
			setStatus(message or Locale.T("🏡 New look for your house!"), MINT)
		else
			setStatus(message or Locale.T("Network error, try again."), Theme.Colors.Red)
		end
		refreshTotals()
	end)
end

local function build(phone: boolean)
	local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	if state.Gui then
		state.Gui:Destroy()
	end
	state.Chips = {}
	state.Headers = {}
	state.Parts = {}
	local gui = UIUtil.Create("ScreenGui", {
		Name = "HouseFacadeEditor",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	state.Gui = gui
	local dimmer = UIUtil.Create("TextButton", { Name = "Dimmer", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = gui })
	dimmer.Activated:Connect(function()
		HouseFacadeEditor.Close()
	end)
	local camera = workspace.CurrentCamera
	local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local card = frame({ Name = "Card", BackgroundColor3 = CARD, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 21, Parent = gui })
	if phone then
		card.Size = UDim2.new(1, -12, 1, -12)
	else
		card.Size = UDim2.fromOffset(math.min(1040, screen.X - 40), math.min(620, screen.Y - 40))
	end
	UIUtil.Corner(card, if phone then 16 else 24)
	UIUtil.Stroke(card, PINK, 3)
	UIUtil.SinkClicks(card)
	label({ Name = "Title", Text = Locale.T("🏡 Customise my house"), Color = PINK_DEEP, TextSize = if phone then 20 else 26, Size = UDim2.new(1, -70, 0, 36),
		Position = UDim2.fromOffset(16, 8), XAlign = Enum.TextXAlignment.Left, ZIndex = 22, Parent = card })
	local close = UIUtil.CloseButton({ Name = "Close", Size = if phone then 36 else 40, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), ZIndex = 23 })
	close.Parent = card
	close.Activated:Connect(function()
		HouseFacadeEditor.Close()
	end)
	-- ░ aperçu 3D ░
	local top = 50
	local footerH = if phone then 86 else 64
	local stage = frame({ Name = "Stage", ZIndex = 22, Parent = card })
	if phone then
		stage.Position = UDim2.fromOffset(8, top)
		stage.Size = UDim2.new(1, -16, 0.42, -top)
	else
		stage.Position = UDim2.fromOffset(16, top)
		stage.Size = UDim2.new(0.6, -24, 1, -top - footerH - 8)
	end
	UIUtil.Corner(stage, 16)
	UIUtil.Gradient(stage, ColorSequence.new(Color3.fromRGB(206, 230, 255), Color3.fromRGB(255, 244, 236)), 90)
	local view = UIUtil.Create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 150, 158),
		LightColor = Color3.fromRGB(255, 248, 238),
		LightDirection = Vector3.new(-0.5, -1, -0.7),
		ZIndex = 23,
		Parent = stage,
	})
	UIUtil.Corner(view, 16)
	local previewCamera = Instance.new("Camera")
	previewCamera.Name = "PreviewCamera"
	previewCamera.FieldOfView = 36
	previewCamera.Parent = view
	view.CurrentCamera = previewCamera
	state.Parts.View = view
	state.Parts.Camera = previewCamera
	-- sol : pelouse + trottoir + rue
	local function ground(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Parent = view
	end
	ground("Lawn", Vector3.new(220, 1, 110), CFrame.new(0, HouseKit.LAWN - 0.5, -10), Color3.fromRGB(116, 180, 96), Enum.Material.Grass)
	ground("Street", Vector3.new(220, 1, 18), CFrame.new(0, HouseKit.LAWN - 0.45, 40), Color3.fromRGB(70, 72, 78), Enum.Material.Asphalt)
	local hint = label({ Name = "DragHint", Text = Locale.T("⟲ Drag to turn"), Font = Theme.Fonts.Body, TextSize = 13, Size = UDim2.fromOffset(160, 18), AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -8), XAlign = Enum.TextXAlignment.Right, ZIndex = 25, Parent = stage })
	hint.TextTransparency = 0.3
	-- zoom
	for index, spec in ipairs({ { "ZoomIn", "➕", 0.82 }, { "ZoomOut", "➖", 1.22 } }) do
		local zb = UIUtil.BasicButton({ Name = spec[1], Text = spec[2], TextSize = 16, Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(10, 10 + (index - 1) * 40), ZIndex = 26,
			Shadow = false })
		zb.Parent = stage
		zb.Activated:Connect(function()
			state.Zoom = math.clamp(state.Zoom * spec[3], 0.45, 1.6)
		end)
	end
	view.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			state.Dragging = true
			state.DragX = input.Position.X
			state.DragY = input.Position.Y
		end
	end)
	-- ░ réglages ░
	local panel = frame({ Name = "Options", BackgroundTransparency = 1, ZIndex = 22, Parent = card })
	if phone then
		panel.Position = UDim2.new(0, 8, 0.42, 6)
		panel.Size = UDim2.new(1, -16, 0.58, -footerH - 14)
	else
		panel.Position = UDim2.new(0.6, 0, 0, top)
		panel.Size = UDim2.new(0.4, -16, 1, -top - footerH - 8)
	end
	local tabs = frame({ Name = "Tabs", BackgroundColor3 = SOFT, Size = UDim2.new(1, 0, 0, 40), ZIndex = 23, Parent = panel })
	UIUtil.Corner(tabs, 12)
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = tabs })
	state.Parts.Tabs = {}
	state.Parts.Pages = {}
	local size = currentSize()
	local style = WorldLayout.StyleOf(size)
	local floors = WorldLayout.Dims(size).Floors
	local groups = HouseOptions.GROUPS
	for index, group in ipairs(groups) do
		local tab = UIUtil.Create("TextButton", {
			Name = "Tab_" .. group.Id,
			Text = if phone then group.Icon else group.Icon .. " " .. Locale.T(group.Name),
			Font = Theme.Fonts.Title,
			TextSize = if phone then 18 else 12,
			TextWrapped = true,
			TextColor3 = INK,
			AutoButtonColor = false,
			BackgroundColor3 = WHITE,
			Size = UDim2.new(1 / #groups, -5, 1, -8),
			LayoutOrder = index,
			ZIndex = 24,
			Parent = tabs,
		})
		UIUtil.Corner(tab, 9)
		tab.Activated:Connect(function()
			showGroup(group.Id)
		end)
		state.Parts.Tabs[group.Id] = tab
		local page = UIUtil.Create("ScrollingFrame", {
			Name = "Page_" .. group.Id,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, -48),
			Position = UDim2.fromOffset(0, 48),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 5,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
			ZIndex = 23,
			Parent = panel,
		})
		UIUtil.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = page })
		UIUtil.Create("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), Parent = page })
		state.Parts.Pages[group.Id] = page
		local order = 0
		for _, def in ipairs(HouseOptions.KINDS) do
			if def.Group == group.Id and HouseOptions.Applies(def.Id, style, floors) then
				order += 1
				kindRow(page, def, order, phone)
			end
		end
		if group.Id == "Garden" then
			numberRow(page, order + 1)
		end
	end
	-- ░ bas : total, statut, annuler, appliquer ░
	local footer = frame({ Name = "Footer", BackgroundColor3 = SOFT, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, footerH),
		ZIndex = 22, Parent = card })
	UIUtil.Corner(footer, 14)
	local buttonsW = if phone then 220 else 330
	-- (téléphone : le total sur toute la largeur, les boutons en dessous)
	state.Parts.Total = label({ Name = "Total", Text = "", TextSize = if phone then 14 else 18, Size = if phone then UDim2.new(1, -20, 0, 24) else UDim2.new(1, -buttonsW - 20, 0.55, 0),
		Position = UDim2.fromOffset(12, 2), XAlign = Enum.TextXAlignment.Left, ZIndex = 23, Parent = footer })
	local status = label({ Name = "Status", Text = "", Font = Theme.Fonts.Body, TextSize = if phone then 12 else 14,
		Size = if phone then UDim2.new(1, -buttonsW - 20, 0, 40) else UDim2.new(1, -buttonsW - 20, 0.45, -2),
		Position = if phone then UDim2.new(0, 12, 1, -46) else UDim2.new(0, 12, 0.55, 0), XAlign = Enum.TextXAlignment.Left, Wrap = phone, ZIndex = 23, Parent = footer })
	status.TextTruncate = Enum.TextTruncate.AtEnd
	state.Parts.Status = status
	local buttonH = if phone then 44 else footerH - 16
	local buttonY = if phone then UDim2.new(1, -(if phone then 136 else 210) - 8, 1, -6) else UDim2.new(1, -(if phone then 136 else 210) - 8, 0.5, 0)
	local revert = UIUtil.BasicButton({ Name = "Revert", Text = Locale.T("↺ Undo"), TextSize = if phone then 15 else 18, Size = UDim2.fromOffset(if phone then 80 else 120, buttonH),
		AnchorPoint = if phone then Vector2.new(1, 1) else Vector2.new(1, 0.5), Position = buttonY, ZIndex = 24 })
	revert.Parent = footer
	revert.Activated:Connect(function()
		state.Design = table.clone(state.Saved)
		markDirty()
		refreshTotals()
		setStatus("")
	end)
	local applyButton = UIUtil.NeonButton({ Name = "Apply", Text = Locale.T("✅ Apply"), Color = MINT, Size = UDim2.fromOffset(if phone then 130 else 200, if phone then 46 else footerH - 14),
		AnchorPoint = if phone then Vector2.new(1, 1) else Vector2.new(1, 0.5), Position = if phone then UDim2.new(1, -8, 1, -5) else UDim2.new(1, -8, 0.5, 0), ZIndex = 24,
		MaxTextSize = if phone then 16 else 20 })
	applyButton.Parent = footer
	applyButton.Activated:Connect(function()
		if applyButton:GetAttribute("Enabled") == false then
			UIUtil.Shake(applyButton)
			return
		end
		apply()
	end)
	state.Parts.Apply = applyButton
	showGroup(state.Group)
	refreshTotals()
	markDirty()
	state.ChangedAt = -math.huge
end

local function isPhone(): boolean
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return size.X < 820 or size.Y < 520
end

function HouseFacadeEditor.IsOpen(): boolean
	return state.Open
end

function HouseFacadeEditor.Open(options: { [string]: any }?)
	local o = options or {}
	state.Plot = math.max(1, math.floor(tonumber(o.Plot) or tonumber(LocalPlayer and LocalPlayer:GetAttribute("TownPlot")) or 1))
	local saved = HouseOptions.Sanitize(houseData().Ext, ownedExt())
	state.Saved = saved
	state.Design = table.clone(saved)
	if state.Open then
		refreshTotals()
		markDirty()
		return
	end
	state.Open = true
	local phone = isPhone()
	build(phone)
	local conns = state.Connections
	table.insert(conns, RunService.RenderStepped:Connect(function(dt: number)
		if not state.Open then
			return
		end
		if state.Dirty and os.clock() - state.ChangedAt >= REBUILD_DELAY then
			rebuildPreview()
		end
		if not state.Dragging and os.clock() - state.LastDrag > 2 then
			state.Yaw = (state.Yaw + dt * 0.18) % (math.pi * 2)
		end
		updateCamera()
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input: InputObject)
		if state.Dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local dx, dy = input.Position.X - state.DragX, input.Position.Y - state.DragY
			state.DragX, state.DragY = input.Position.X, input.Position.Y
			state.Yaw -= dx * 0.01
			state.Pitch = math.clamp(state.Pitch + dy * 0.006, math.rad(4), math.rad(55))
			state.LastDrag = os.clock()
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and state.Open then
			state.Zoom = math.clamp(state.Zoom * (1 - input.Position.Z * 0.08), 0.45, 1.6)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if state.Dragging then
				state.LastDrag = os.clock()
			end
			state.Dragging = false
		end
	end))
	table.insert(conns, ClientState.Changed:Connect(function()
		if state.Open then
			refreshTotals()
		end
	end))
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local now = isPhone()
			if state.Open and now ~= phone then
				phone = now
				build(phone)
			end
		end))
	end
	local card = state.Gui and state.Gui:FindFirstChild("Card")
	if card and card:IsA("GuiObject") then
		UIUtil.Pop(card, 0.9, 0.22)
	end
end

function HouseFacadeEditor.Close()
	if not state.Open then
		return
	end
	state.Open = false
	for _, c in ipairs(state.Connections) do
		c:Disconnect()
	end
	state.Connections = {}
	if state.Model then
		state.Model:Destroy()
		state.Model = nil
	end
	if state.Gui then
		state.Gui:Destroy()
		state.Gui = nil
	end
	state.Parts = {}
	state.Chips = {}
	state.Headers = {}
end

return HouseFacadeEditor
