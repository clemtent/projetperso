--[[
	CarWorkshop (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > CarWorkshop

	🔧 (v10, CARS10) Atelier de "🏎️ Mes voitures" : deux onglets dans la
	fiche de droite, à côté de l'aperçu 3D (CarClient) :
	  - 🎨 STYLE : rubriques (finition, toit bicolore, jantes, couleur des
	    jantes, pneus, lame avant, bas de caisse, aileron, vitres, néon,
	    sellerie, plaque) ; toucher une option la montre TOUT DE SUITE sur
	    l'aperçu 3D (essai gratuit), puis "Appliquer" (déjà achetée /
	    gratuite) ou "Acheter 🧠 prix" (payé une fois par voiture, vérifié
	    par CarService "setMod") ; verrous "visites à l'océan" ; plaque :
	    texte libre (A-Z, 0-9, filtré par le serveur, "plate").
	  - 🏁 PERF : moteur / pneus / suspensions (3 niveaux, "tune"), fiche
	    chiffrée (vitesse max, 0-100 %, indice et classe D..S de
	    CarModels.Stats) avec l'effet du prochain niveau.
	Ordinateur + téléphone (Layout). Aucun son.

	API (CarClient) :
	  local ws = CarWorkshop.new(parent: GuiObject, api)
	    api = { Invoke(action, a, b) -> (ok, message, extra), Toast(text),
	            Owns(carId) -> boolean, Data() -> données client,
	            Changed(carId) (aperçu à reconstruire), NeedDopamine(missing) }
	  ws:SetCar(carId) ; ws:SetTab("Style" | "Perf") ; ws:Refresh()
	  ws:PreviewMods(carId) -> { [Kind] = Id } (enregistrées + essais)
	  ws:PreviewPlate(carId) -> string? (essai de plaque)
	  ws:Reset() (oublie les essais) ; ws:Layout(phone) ; ws.Frame
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local CarModels = require(ReplicatedStorage.Shared.CarModels)

local CarWorkshop = {}
CarWorkshop.__index = CarWorkshop

local PINK = Color3.fromRGB(255, 110, 170)
local PINK_DEEP = Color3.fromRGB(236, 72, 140)
local SKY = Color3.fromRGB(96, 170, 245)
local MINT = Color3.fromRGB(80, 200, 160)
local LILAC = Color3.fromRGB(170, 140, 245)
local INK = Color3.fromRGB(92, 58, 96)
local WHITE = Color3.new(1, 1, 1)
local SOFT = Color3.fromRGB(246, 238, 246)
local LINE = Color3.fromRGB(236, 220, 232)
local ORANGE = Color3.fromRGB(255, 160, 60)

-- Rubriques (ordre de Config.Cars.ModKinds + la plaque)
local KIND_TEXT: { [string]: string } = {
	Finish = "✨ Finish",
	Roof = "🎩 Roof",
	Rims = "🛞 Rims",
	RimColor = "🎨 Rim colour",
	Tyre = "⚫ Tyres",
	Splitter = "🔻 Splitter",
	Skirts = "➖ Skirts",
	Spoiler = "🪽 Spoiler",
	Tint = "🕶️ Windows",
	Glow = "💡 Underglow",
	Interior = "💺 Interior",
	Plate = "🔖 Plate",
}

local CLASS_COLORS: { [string]: Color3 } = {
	D = Color3.fromRGB(150, 150, 170),
	C = Color3.fromRGB(90, 190, 140),
	B = Color3.fromRGB(96, 150, 245),
	A = Color3.fromRGB(170, 110, 245),
	S = Color3.fromRGB(255, 150, 40),
}

local function label(props: { [string]: any }): TextLabel
	return UIUtil.Create("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Title,
		TextColor3 = props.Color or INK,
		TextSize = props.TextSize or 16,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = props.Wrap == true,
		TextTruncate = if props.Wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		Text = props.Text or "",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 25,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
end

local function frame(props: { [string]: any }): Frame
	props.BorderSizePixel = 0
	props.ZIndex = props.ZIndex or 24
	return UIUtil.Create("Frame", props)
end

local function setButton(button: TextButton, text: string, color: Color3, enabled: boolean)
	button.Text = text
	button.BackgroundColor3 = if enabled then color else Color3.fromRGB(200, 190, 204)
	button:SetAttribute("BaseColor", button.BackgroundColor3)
	button.Active = enabled
	button.AutoButtonColor = false
end

-- Couleur d'aperçu d'une option (pastille) ou nil
local function swatchOf(kind: string, entry: any): Color3?
	if typeof(entry.Color) == "Color3" then
		return entry.Color
	end
	if kind == "Roof" then
		if entry.Id == "Carbon" then
			return Color3.fromRGB(30, 31, 36)
		end
		local paint = Config.CarColorsById[entry.Id]
		return paint and paint.Color or nil
	elseif kind == "Tint" then
		local tints = { Clear = Color3.fromRGB(150, 176, 204), Light = Color3.fromRGB(96, 116, 140), Dark = Color3.fromRGB(52, 60, 74), Limo = Color3.fromRGB(20, 22, 28) }
		return tints[entry.Id]
	end
	return nil
end

function CarWorkshop.new(parent: GuiObject, api: any)
	local self = setmetatable({}, CarWorkshop)
	self.Api = api
	self.CarId = ""
	self.Tab = "Style"
	self.Kind = "Finish"
	self.Pending = {} -- [carId] = { [Kind] = Id } (essais pas encore payés)
	self.PlateTry = {} -- [carId] = texte essayé
	self.Busy = false
	self.Phone = false

	local root = frame({ Name = "Workshop", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = parent })
	self.Frame = root

	------------------------------------------------------------------ STYLE
	local style = frame({ Name = "Style", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	self.StyleFrame = style
	local chips = UIUtil.Create("ScrollingFrame", {
		Name = "Kinds",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 36),
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ZIndex = 25,
		Parent = style,
	})
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center, Parent = chips })
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), Parent = chips })
	self.Chips = {}
	local kinds = table.clone(Config.Cars.ModKinds)
	table.insert(kinds, "Plate")
	for order, kind in ipairs(kinds) do
		local chip = UIUtil.Create("TextButton", {
			Name = "Kind_" .. kind,
			AutoButtonColor = false,
			BackgroundColor3 = SOFT,
			Font = Theme.Fonts.Title,
			Text = Locale.T(KIND_TEXT[kind] or kind),
			TextColor3 = INK,
			TextSize = 14,
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = order,
			ZIndex = 26,
			Parent = chips,
		})
		UIUtil.Corner(chip, UDim.new(1, 0))
		UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = chip })
		chip.Activated:Connect(function()
			self.Kind = kind
			self:Refresh()
		end)
		self.Chips[kind] = chip
	end
	local options = UIUtil.Create("ScrollingFrame", {
		Name = "Options",
		BackgroundColor3 = SOFT,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -104),
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 25,
		Parent = style,
	})
	UIUtil.Corner(options, 12)
	local grid = UIUtil.Create("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 40), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = options })
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), Parent = options })
	self.Options = options
	self.Grid = grid
	self.OptionButtons = {}
	-- plaque : champ de texte
	local plateBox = UIUtil.Create("TextBox", {
		Name = "PlateBox",
		BackgroundColor3 = WHITE,
		Font = Theme.Fonts.Number,
		PlaceholderText = Locale.T("YOUR TEXT"),
		PlaceholderColor3 = Color3.fromRGB(180, 170, 186),
		Text = "",
		TextColor3 = Color3.fromRGB(30, 30, 40),
		TextSize = 24,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -20, 0, 46),
		Position = UDim2.fromOffset(10, 52),
		Visible = false,
		ZIndex = 26,
		Parent = style,
	})
	UIUtil.Corner(plateBox, 10)
	UIUtil.Stroke(plateBox, Color3.fromRGB(40, 80, 190), 2)
	local plateHint = label({ Name = "PlateHint", Text = "", TextSize = 13, Font = Theme.Fonts.Body, Wrap = true, Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 104), Visible = false, Parent = style })
	plateBox:GetPropertyChangedSignal("Text"):Connect(function()
		local maxLength = tonumber(Config.Cars.PlateMaxLength) or 8
		local text = string.upper(plateBox.Text)
		text = string.gsub(text, "[^A-Z0-9 ]", "")
		text = string.sub(text, 1, maxLength)
		if text ~= plateBox.Text then
			plateBox.Text = text
			return
		end
		if self.CarId ~= "" then
			self.PlateTry[self.CarId] = text
			self.Api.Changed(self.CarId)
			self:RefreshFooter()
		end
	end)
	self.PlateBox = plateBox
	self.PlateHint = plateHint
	-- pied : option choisie + bouton
	local footer = frame({ Name = "Footer", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -56), Size = UDim2.new(1, 0, 0, 56), Parent = style })
	local picked = label({ Name = "Picked", Text = "", TextSize = 14, Font = Theme.Fonts.Body, Wrap = true, Size = UDim2.new(0.5, -4, 1, 0), Parent = footer })
	local action = UIUtil.PillButton({ Name = "ApplyMod", Text = "", Color = PINK_DEEP, Height = 42, TextSize = 16, ZIndex = 26, Parent = footer })
	action.AutomaticSize = Enum.AutomaticSize.None
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, 0, 0.5, 0)
	action.Size = UDim2.new(0.5, -4, 0, 42)
	action.Activated:Connect(function()
		self:ApplyStyle()
	end)
	self.Picked = picked
	self.Action = action

	------------------------------------------------------------------ PERF
	local perf = frame({ Name = "Perf", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })
	self.PerfFrame = perf
	local head = frame({ Name = "Head", BackgroundColor3 = SOFT, Size = UDim2.new(1, 0, 0, 96), Parent = perf })
	UIUtil.Corner(head, 12)
	local classBadge = label({ Name = "Class", Text = "B", TextSize = 30, Color = WHITE, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(54, 54),
		Position = UDim2.fromOffset(8, 8), ZIndex = 26, Parent = head })
	classBadge.BackgroundTransparency = 0
	classBadge.BackgroundColor3 = CLASS_COLORS.B
	UIUtil.Corner(classBadge, 12)
	local rating = label({ Name = "Rating", Text = "", TextSize = 13, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(62, 20), Position = UDim2.fromOffset(4, 66), Parent = head })
	local readout = frame({ Name = "Readout", BackgroundTransparency = 1, Position = UDim2.fromOffset(72, 6), Size = UDim2.new(1, -80, 1, -12), Parent = head })
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = readout })
	self.Class = classBadge
	self.Rating = rating
	self.Readout = {}
	for order, key in ipairs({ "TopSpeed", "ZeroToTop", "Grip", "TurnRate" }) do
		self.Readout[key] = label({ Name = key, Text = "", TextSize = 14, Font = Theme.Fonts.Body, Size = UDim2.new(1, 0, 0, 19), LayoutOrder = order, Parent = readout })
	end
	local rows = frame({ Name = "Rows", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 1, -104), Parent = perf })
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = rows })
	self.PerfRows = {}
	for order, part in ipairs(Config.Cars.Tuning.Parts) do
		local row = frame({ Name = "Tune_" .. part.Id, BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = order, Parent = rows })
		UIUtil.Corner(row, 12)
		UIUtil.Stroke(row, LINE, 1.5)
		label({ Name = "Name", Text = part.Icon .. " " .. Locale.T(part.Name), TextSize = 16, Size = UDim2.new(0.55, -10, 0, 24), Position = UDim2.fromOffset(10, 4), Parent = row })
		label({ Name = "Desc", Text = Locale.T(part.Desc), TextSize = 12, Font = Theme.Fonts.Body, Size = UDim2.new(0.55, -10, 0, 16), Position = UDim2.fromOffset(10, 28), Parent = row })
		local pips = frame({ Name = "Pips", BackgroundTransparency = 1, Size = UDim2.fromOffset(84, 8), Position = UDim2.fromOffset(10, 46), Parent = row })
		UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pips })
		for k = 1, Config.Cars.Tuning.MaxLevel do
			local pip = frame({ Name = "Pip" .. k, BackgroundColor3 = LINE, Size = UDim2.fromOffset(24, 7), LayoutOrder = k, ZIndex = 26, Parent = pips })
			UIUtil.Corner(pip, UDim.new(1, 0))
		end
		local button = UIUtil.PillButton({ Name = "Upgrade", Text = "", Color = ORANGE, Height = 38, TextSize = 14, ZIndex = 26, Parent = row })
		button.AutomaticSize = Enum.AutomaticSize.None
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.new(0.45, -8, 0, 38)
		button.Activated:Connect(function()
			self:Upgrade(part.Id)
		end)
		self.PerfRows[part.Id] = { Row = row, Pips = pips, Button = button }
	end
	return self
end

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

function CarWorkshop:CarsData(): any
	local data = self.Api.Data()
	local cars = data and data.Cars
	return if type(cars) == "table" then cars else {}
end

function CarWorkshop:SavedMods(carId: string): { [string]: string }
	local mods = self:CarsData().Mods
	return CarModels.CleanMods(type(mods) == "table" and mods[carId] or nil)
end

function CarWorkshop:PreviewMods(carId: string): { [string]: string }
	local out = self:SavedMods(carId)
	local pending = self.Pending[carId]
	if pending then
		for kind, id in pairs(pending) do
			out[kind] = id
		end
	end
	return CarModels.CleanMods(out)
end

function CarWorkshop:PreviewPlate(carId: string): string?
	local text = self.PlateTry[carId]
	if type(text) == "string" and text ~= "" then
		return text
	end
	local plates = self:CarsData().Plates
	local saved = type(plates) == "table" and plates[carId]
	return if type(saved) == "string" and saved ~= "" then saved else nil
end

function CarWorkshop:Unlocked(carId: string, kind: string, entry: any): boolean
	local list = Config.Cars.Mods[kind]
	if (list and list[1] == entry) or (tonumber(entry.Price) or 0) <= 0 then
		return true
	end
	local all = self:CarsData().Unlocked
	local set = type(all) == "table" and all[carId]
	return type(set) == "table" and set[kind .. ":" .. entry.Id] == true
end

function CarWorkshop:LockOf(entry: any, level: number?): number?
	local need = tonumber(entry.RequiresRebirths) or 0
	if type(entry.RequiresRebirths) == "table" then
		need = tonumber(entry.RequiresRebirths[level or 1]) or 0
	end
	local data = self.Api.Data()
	local have = data and tonumber(data.Rebirths) or 0
	return if have >= need then nil else need
end

function CarWorkshop:Reset()
	table.clear(self.Pending)
	table.clear(self.PlateTry)
end

----------------------------------------------------------------------
-- Affichage
----------------------------------------------------------------------

function CarWorkshop:SetCar(carId: string)
	if self.CarId ~= carId then
		self.CarId = carId
		local saved = self:CarsData().Plates
		self.PlateBox.Text = if type(saved) == "table" and type(saved[carId]) == "string" then saved[carId] else ""
	end
	self:Refresh()
end

function CarWorkshop:SetTab(tab: string)
	self.Tab = tab
	self:Refresh()
end

function CarWorkshop:SetVisible(visible: boolean)
	self.Frame.Visible = visible
end

-- (re)crée les boutons d'options de la rubrique affichée
function CarWorkshop:BuildOptions()
	local kind = self.Kind
	if self.OptionsKind == kind then
		return
	end
	self.OptionsKind = kind
	for _, b in pairs(self.OptionButtons) do
		b.Button:Destroy()
	end
	table.clear(self.OptionButtons)
	local list = Config.Cars.Mods[kind]
	if not list then
		return
	end
	for order, entry in ipairs(list) do
		local button = UIUtil.Create("TextButton", {
			Name = "Opt_" .. entry.Id,
			AutoButtonColor = false,
			BackgroundColor3 = WHITE,
			Text = "",
			LayoutOrder = order,
			ZIndex = 26,
			Parent = self.Options,
		})
		UIUtil.Corner(button, 10)
		local stroke = UIUtil.Stroke(button, LINE, 1.5)
		local sw = swatchOf(kind, entry)
		local x = 8
		if sw then
			local dot = frame({ Name = "Swatch", BackgroundColor3 = sw, Size = UDim2.fromOffset(20, 20), Position = UDim2.new(0, 8, 0.5, -10), ZIndex = 27, Parent = button })
			UIUtil.Corner(dot, UDim.new(1, 0))
			UIUtil.Stroke(dot, Color3.fromRGB(210, 200, 214), 1)
			x = 34
		end
		local name = label({ Name = "Name", Text = Locale.T(entry.Name), TextSize = 13, Size = UDim2.new(1, -x - 4, 0, 18), Position = UDim2.fromOffset(x, 3), ZIndex = 27, Parent = button })
		local price = label({ Name = "Price", Text = "", TextSize = 12, Font = Theme.Fonts.Body, Size = UDim2.new(1, -x - 4, 0, 15), Position = UDim2.fromOffset(x, 21), ZIndex = 27, Parent = button })
		button.Activated:Connect(function()
			local carId = self.CarId
			if carId == "" then
				return
			end
			-- essai tout de suite sur l'aperçu 3D (gratuit)
			self.Pending[carId] = self.Pending[carId] or {}
			self.Pending[carId][kind] = entry.Id
			self.Api.Changed(carId)
			self:Refresh()
		end)
		self.OptionButtons[entry.Id] = { Button = button, Stroke = stroke, Name = name, Price = price, Entry = entry }
	end
end

function CarWorkshop:RefreshFooter()
	local carId = self.CarId
	local def = Config.CarsById[carId]
	if not def then
		return
	end
	local owned = self.Api.Owns(carId)
	if self.Kind == "Plate" then
		local try = self.PlateTry[carId] or ""
		local plates = self:CarsData().Plates
		local saved = type(plates) == "table" and plates[carId] or ""
		local cost = CarModels.PriceFor(carId, Config.Cars.PlatePrice)
		self.Picked.Text = Locale.T("🔖 %d characters max: letters, numbers, spaces", tonumber(Config.Cars.PlateMaxLength) or 8)
		if not owned then
			setButton(self.Action, Locale.T("Buy the car first"), LILAC, false)
		elseif try == saved then
			setButton(self.Action, Locale.T("✅ Applied"), MINT, false)
		elseif try == "" then
			setButton(self.Action, Locale.T("Original plate"), SKY, true)
		else
			setButton(self.Action, Locale.T("Apply — 🧠 %s", NumberFormatter.Format(cost)), PINK_DEEP, true)
		end
		return
	end
	local list = Config.Cars.Mods[self.Kind]
	local byId = Config.CarModsById[self.Kind]
	local current = self:PreviewMods(carId)[self.Kind] or (list and list[1].Id)
	local entry = byId and byId[current]
	if not entry then
		return
	end
	local saved = self:SavedMods(carId)[self.Kind] or list[1].Id
	local unlocked = self:Unlocked(carId, self.Kind, entry)
	local lock = self:LockOf(entry)
	local cost = CarModels.PriceFor(carId, entry.Price)
	self.Picked.Text = Locale.T(entry.Name) .. (if current ~= saved then "\n" .. Locale.T("(preview)") else "")
	if current == saved then
		setButton(self.Action, Locale.T("✅ Applied"), MINT, false)
	elseif not owned then
		setButton(self.Action, Locale.T("Buy the car first"), LILAC, false)
	elseif lock then
		setButton(self.Action, "🔒 " .. Locale.T("%d visits to the ocean", lock), LILAC, false)
	elseif unlocked then
		setButton(self.Action, Locale.T("Apply"), SKY, true)
	else
		setButton(self.Action, Locale.T("Buy — 🧠 %s", NumberFormatter.Format(cost)), PINK_DEEP, true)
	end
end

function CarWorkshop:RefreshStyle()
	local carId = self.CarId
	for kind, chip in pairs(self.Chips) do
		local on = kind == self.Kind
		chip.BackgroundColor3 = if on then PINK_DEEP else SOFT
		chip.TextColor3 = if on then WHITE else INK
	end
	local plate = self.Kind == "Plate"
	self.Options.Visible = not plate
	self.PlateBox.Visible = plate
	self.PlateHint.Visible = plate
	if plate then
		self.PlateHint.Text = Locale.T("Shown on your car for everyone: keep it friendly!")
	else
		self:BuildOptions()
		local preview = self:PreviewMods(carId)
		local saved = self:SavedMods(carId)
		local list = Config.Cars.Mods[self.Kind] or {}
		local first = list[1] and list[1].Id
		for id, b in pairs(self.OptionButtons) do
			local entry = b.Entry
			local shown = (preview[self.Kind] or first) == id
			local isSaved = (saved[self.Kind] or first) == id
			b.Stroke.Color = if shown then PINK_DEEP else LINE
			b.Stroke.Thickness = if shown then 3 else 1.5
			b.Button.BackgroundColor3 = if shown then Color3.fromRGB(255, 240, 248) else WHITE
			local lock = self:LockOf(entry)
			if isSaved then
				b.Price.Text = Locale.T("✅ On your car")
			elseif self:Unlocked(carId, self.Kind, entry) then
				b.Price.Text = if (tonumber(entry.Price) or 0) <= 0 then Locale.T("Free") else Locale.T("🔓 Bought")
			elseif lock then
				b.Price.Text = "🔒 " .. Locale.T("%d visits to the ocean", lock)
			else
				b.Price.Text = "🧠 " .. NumberFormatter.Format(CarModels.PriceFor(carId, entry.Price))
			end
		end
	end
	self:RefreshFooter()
end

function CarWorkshop:RefreshPerf()
	local carId = self.CarId
	if carId == "" then
		return
	end
	local tuning = CarModels.TuningOf(self.Api.Data(), carId)
	local stats = CarModels.Stats(carId, tuning)
	self.Class.Text = stats.Class
	self.Class.BackgroundColor3 = CLASS_COLORS[stats.Class] or CLASS_COLORS.B
	self.Rating.Text = Locale.T("Rating %d", stats.Rating)
	-- (1 stud/s ≈ 1 km/h au compteur de CarClient)
	self.Readout.TopSpeed.Text = Locale.T("⚡ Top speed: %d km/h", math.floor(stats.TopSpeed + 0.5))
	self.Readout.ZeroToTop.Text = Locale.T("🏁 0 to top speed: %.1f s", stats.ZeroToTop)
	self.Readout.Grip.Text = Locale.T("🌀 Grip: %d%%", math.floor(stats.Grip * 10 + 0.5))
	self.Readout.TurnRate.Text = Locale.T("🛞 Steering: %d%%", math.floor(stats.TurnRate / 1.9 * 100 + 0.5))
	local owned = self.Api.Owns(carId)
	local maxLevel = Config.Cars.Tuning.MaxLevel
	for _, part in ipairs(Config.Cars.Tuning.Parts) do
		local row = self.PerfRows[part.Id]
		local level = (tuning :: any)[part.Id] or 0
		for k = 1, maxLevel do
			local pip = row.Pips:FindFirstChild("Pip" .. k)
			if pip then
				pip.BackgroundColor3 = if k <= level then ORANGE else LINE
			end
		end
		if level >= maxLevel then
			setButton(row.Button, Locale.T("✅ MAX"), MINT, false)
		elseif not owned then
			setButton(row.Button, Locale.T("Buy the car first"), LILAC, false)
		else
			local lock = self:LockOf(part, level + 1)
			if lock then
				setButton(row.Button, "🔒 " .. Locale.T("%d visits to the ocean", lock), LILAC, false)
			else
				local cost = CarModels.PriceFor(carId, part.Price[level + 1])
				setButton(row.Button, Locale.T("⬆️ Lv %d — 🧠 %s", level + 1, NumberFormatter.Format(cost)), ORANGE, true)
			end
		end
	end
end

function CarWorkshop:Refresh()
	if self.CarId == "" then
		return
	end
	self.StyleFrame.Visible = self.Tab == "Style"
	self.PerfFrame.Visible = self.Tab == "Perf"
	if self.Tab == "Style" then
		self:RefreshStyle()
	else
		self:RefreshPerf()
	end
end

----------------------------------------------------------------------
-- Actions (le serveur vérifie tout)
----------------------------------------------------------------------

function CarWorkshop:Run(action: string, a: any, b: any, done: (() -> ())?)
	if self.Busy then
		return
	end
	self.Busy = true
	task.spawn(function()
		local ok, message, missing = self.Api.Invoke(action, a, b)
		self.Busy = false
		if type(message) == "string" and message ~= "" then
			self.Api.Toast(message)
		end
		if not ok and type(missing) == "number" and missing > 0 then
			self.Api.NeedDopamine(missing)
		end
		if ok and done then
			done()
		end
		self:Refresh()
	end)
end

function CarWorkshop:ApplyStyle()
	local carId = self.CarId
	if carId == "" or not self.Api.Owns(carId) or not self.Action.Active then
		return
	end
	if self.Kind == "Plate" then
		local text = self.PlateTry[carId] or ""
		self:Run("plate", carId, text, function()
			self.PlateTry[carId] = nil
			self.Api.Changed(carId)
		end)
		return
	end
	local kind = self.Kind
	local id = self:PreviewMods(carId)[kind] or Config.Cars.Mods[kind][1].Id
	self:Run("setMod", carId, kind .. ":" .. id, function()
		local pending = self.Pending[carId]
		if pending then
			pending[kind] = nil
		end
		self.Api.Changed(carId)
	end)
end

function CarWorkshop:Upgrade(partId: string)
	local carId = self.CarId
	if carId == "" or not self.Api.Owns(carId) then
		return
	end
	self:Run("tune", carId, partId, nil)
end

----------------------------------------------------------------------
-- Mise en page
----------------------------------------------------------------------

function CarWorkshop:Layout(phone: boolean)
	self.Phone = phone
	self.Grid.CellSize = UDim2.new(0.5, -6, 0, if phone then 34 else 40)
	for _, chip in pairs(self.Chips) do
		chip.TextSize = if phone then 12 else 14
		chip.Size = UDim2.fromOffset(0, if phone then 24 else 28)
	end
	local footerH = if phone then 44 else 56
	local footer = self.Action.Parent :: Frame
	footer.Size = UDim2.new(1, 0, 0, footerH)
	footer.Position = UDim2.new(0, 0, 1, -footerH)
	self.Action.Size = UDim2.new(0.5, -4, 0, if phone then 34 else 42)
	self.Action.TextSize = if phone then 13 else 16
	self.Options.Position = UDim2.fromOffset(0, if phone then 32 else 42)
	self.Options.Size = UDim2.new(1, 0, 1, -(if phone then 32 else 42) - footerH - 4)
	self.PlateBox.Position = UDim2.fromOffset(10, if phone then 38 else 52)
	self.PlateHint.Position = UDim2.fromOffset(10, if phone then 88 else 104)
	-- perf : fiche plus courte sur téléphone
	local head = self.PerfFrame:FindFirstChild("Head") :: Frame?
	local rows = self.PerfFrame:FindFirstChild("Rows") :: Frame?
	if head and rows then
		head.Size = UDim2.new(1, 0, 0, if phone then 70 else 96)
		self.Class.Size = UDim2.fromOffset(if phone then 42 else 54, if phone then 42 else 54)
		self.Rating.Position = UDim2.fromOffset(0, if phone then 50 else 66)
		for _, l in pairs(self.Readout) do
			l.TextSize = if phone then 12 else 14
			l.Size = UDim2.new(1, 0, 0, if phone then 14 else 19)
		end
		rows.Position = UDim2.fromOffset(0, if phone then 76 else 104)
		rows.Size = UDim2.new(1, 0, 1, -(if phone then 76 else 104))
		for _, r in pairs(self.PerfRows) do
			r.Row.Size = UDim2.new(1, 0, 0, if phone then 44 else 58)
			local desc = r.Row:FindFirstChild("Desc")
			if desc then
				(desc :: GuiObject).Visible = not phone
			end
			r.Pips.Position = UDim2.fromOffset(10, if phone then 30 else 46)
			r.Button.Size = UDim2.new(0.5, -8, 0, if phone then 32 else 38)
			r.Button.TextSize = if phone then 12 else 14
		end
	end
end

function CarWorkshop:Destroy()
	self.Frame:Destroy()
end

return CarWorkshop
