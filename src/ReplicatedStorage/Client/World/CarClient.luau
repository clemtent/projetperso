--[[
	CarClient (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > CarClient

	🚗 Voitures de Dopamine Town, côté client (v9.6, GARAGE96) :
	  - CONDUITE de SA voiture (le serveur, CarService, la fait apparaître et
	    donne au conducteur la propriété réseau) : chaque image, on lit
	    VehicleSeat.ThrottleFloat / SteerFloat (clavier ZQSD / WASD /
	    flèches, joystick mobile, manette : les contrôles de Roblox les
	    remplissent) et on règle la LinearVelocity (vitesse dans le plan
	    horizontal, accélération / freinage doux, marche arrière) et
	    l'AlignOrientation (cap, toujours à plat). Vitesse max
	    Config.Cars.MaxSpeed. Contre un mur, la vitesse retombe toute seule
	    (on part de la vitesse RÉELLE). Pas d'entrée dans les boutiques
	    (sauf la concession, AllowCars) : on est remis en arrière.
	  - CAMÉRA : suit la voiture (sujet = siège, caméra de Roblox, douce),
	    champ de vision qui s'élargit un peu avec la vitesse ; tout est
	    rendu à la sortie.
	  - HUD (ScreenGui "CarGui") : bouton rond "🚗 Ma voiture" (à gauche,
	    avec délai), "▾" = mes voitures (choisir, couleur, garage) ; au
	    volant : compteur de vitesse, 💨 klaxon VISUEL (aucun son), 🔄 remettre
	    sur ses roues, 🚪 sortir (saut = sortir aussi).
	  - Phares : 2 petites SpotLight (luminosité 0,8) sur SA voiture, la nuit
	    seulement, côté client (jamais d'éblouissement).
	  - GARAGES des manoirs (aile construite par HouseFacade, étiquette
	    "DopamineGarage") : voitures possédées garées dedans (attributs
	    répliqués du propriétaire : DopamineCars / DopamineCar /
	    DopamineCarOut), porte basculante qui s'ouvre quand la voiture du
	    propriétaire (ou le propriétaire à pied) arrive, lumière intérieure
	    douce allumée porte ouverte.
	  - Invites "Conduire" : traduites, visibles seulement sur SA voiture.

	API (TownClient) :
	  CarClient.Start({ Toast = function(text) end? })  -- en entrant en ville
	  CarClient.Stop()                                     -- en sortant (avant de rendre la caméra)
	  CarClient.IsDriving() -> boolean
	  CarClient.Debug() -> table (tests)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local CarModels = require(ReplicatedStorage.Shared.CarModels)
local GarageLayout = require(ReplicatedStorage.Shared.GarageLayout)

local LocalPlayer = Players.LocalPlayer

local CarClient = {}

CarClient.GARAGE_TAG = "DopamineGarage"
CarClient.GUI_NAME = "CarGui"

local PINK = Color3.fromRGB(255, 110, 170)
local PINK_DEEP = Color3.fromRGB(236, 72, 140)
local SKY = Color3.fromRGB(96, 170, 245)
local MINT = Color3.fromRGB(80, 200, 160)
local LILAC = Color3.fromRGB(170, 140, 245)
local INK = Color3.fromRGB(92, 58, 96)
local CARD = Color3.fromRGB(255, 250, 253)
local WHITE = Color3.new(1, 1, 1)

-- Réglages de conduite
local ACCEL = 24 -- studs/s² en accélérant
local BRAKE = 60 -- studs/s² en freinant (touche contraire)
local COAST = 14 -- studs/s² sans rien toucher
local TURN_RATE = 1.9 -- rad/s au maximum (à vitesse moyenne)
local DOOR_TIME = 1.1 -- s pour ouvrir / fermer une porte de garage
local BASE_FOV = 70

type Door = { Panel: BasePart, Parts: { { Part: BasePart, Offset: CFrame } }, Closed: CFrame, Open: CFrame, T: number, Target: number }
type Garage = {
	Model: Model,
	OwnerId: number,
	HouseCF: CFrame,
	Doors: { Door },
	Cars: Instance,
	Light: Light?,
	Key: string,
}

local started = false
local connections: { RBXScriptConnection } = {}
local charConnections: { RBXScriptConnection } = {}
local options: any = {}
local gui: ScreenGui? = nil
local parts: { [string]: any } = {}
local garages: { [Model]: Garage } = {}
local driving: any = nil -- { Seat, Model, Root, Drive, Align, Heading, Speed, LastSafe, SafeClock, Lights }
local lastSpawn = -math.huge
local phone = false
local pickerOpen = false
local shopZones: { { CF: CFrame, Size: Vector3 } } = {}
local lastZoneToast = -math.huge
local controls: any = nil

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function track(connection: RBXScriptConnection)
	table.insert(connections, connection)
end

local function toast(text: string?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local fn = options and options.Toast
	if type(fn) == "function" then
		pcall(fn, text)
		return
	end
	pcall(function()
		local Notifications = require(Client.Components:WaitForChild("Notifications", 2) :: any) :: any
		Notifications.Toast(text)
	end)
end

local function invoke(action: string, a: any?, b: any?): (boolean, any, any)
	local ok, success, message, extra = pcall(function()
		return Net.Function("Car"):InvokeServer(action, a, b)
	end)
	if not ok then
		return false, Locale.T("Network error, try again."), nil
	end
	return success == true, message, extra
end

local function carsData(): any
	local data = ClientState.Data
	local cars = data and data.Cars
	if type(cars) ~= "table" then
		return { Owned = {}, Colors = {}, Selected = "", Garage = false }
	end
	return cars
end

local function isNight(): boolean
	local clock = Lighting.ClockTime
	return clock >= 18.2 or clock < 6.3
end

local function label(props: { [string]: any }): TextLabel
	return UIUtil.Create("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Title,
		TextColor3 = props.Color or INK,
		TextSize = props.TextSize or 18,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = props.Wrap == true,
		Text = props.Text or "",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 2,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
end

local function roundButton(parent: Instance, name: string, icon: string, color: Color3, diameter: number, order: number, tagText: string?): TextButton
	local button = UIUtil.PillButton({
		Name = name,
		Text = icon,
		Color = color,
		Height = diameter,
		Round = true,
		TextSize = math.floor(diameter * 0.46),
		LayoutOrder = order,
		Parent = parent,
	})
	if tagText then
		local tag = label({ Name = "Tag", Text = Locale.T(tagText), Color = WHITE, TextSize = 13, Size = UDim2.fromOffset(110, 16),
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1), ZIndex = 5, Parent = button })
		UIUtil.Create("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.2, Parent = tag })
	end
	return button
end

----------------------------------------------------------------------
-- Zones interdites (boutiques sans AllowCars)
----------------------------------------------------------------------

local function collectZones()
	table.clear(shopZones)
	local town = workspace:FindFirstChild("DopamineTown")
	local shops = town and town:FindFirstChild("Shops")
	if not shops then
		return
	end
	for _, shop in ipairs(shops:GetChildren()) do
		local cf = shop:GetAttribute("InteriorCF")
		local size = shop:GetAttribute("InteriorSize")
		if typeof(cf) == "CFrame" and typeof(size) == "Vector3" and shop:GetAttribute("AllowCars") ~= true then
			table.insert(shopZones, { CF = cf, Size = size })
		end
	end
end

local function inZone(position: Vector3): boolean
	for _, zone in ipairs(shopZones) do
		local p = zone.CF:PointToObjectSpace(position)
		if math.abs(p.X) <= zone.Size.X / 2 + 0.5 and math.abs(p.Z) <= zone.Size.Z / 2 + 0.5 and p.Y >= -2 and p.Y <= zone.Size.Y + 1 then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------

local refreshHud: () -> () = function() end
local setPicker: (open: boolean) -> () = function() end

local function buildPicker(root: Frame)
	local dimmer = UIUtil.Create("TextButton", {
		Name = "PickerDimmer",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.new(1, 400, 1, 400),
		Position = UDim2.fromOffset(-200, -200),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	dimmer.Activated:Connect(function()
		setPicker(false)
	end)
	local card = UIUtil.Create("Frame", {
		Name = "CarPicker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(560, 400),
		BackgroundColor3 = CARD,
		Visible = false,
		ZIndex = 21,
		Parent = root,
	})
	UIUtil.Corner(card, 22)
	UIUtil.Stroke(card, PINK, 3)
	UIUtil.SinkClicks(card)
	label({ Name = "Title", Text = Locale.T("🏎️ My cars"), Color = PINK_DEEP, TextSize = 26, Size = UDim2.new(1, -80, 0, 40),
		Position = UDim2.fromOffset(20, 12), XAlign = Enum.TextXAlignment.Left, ZIndex = 22, Parent = card })
	local close = UIUtil.CloseButton({ Name = "ClosePicker", Size = 40, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), ZIndex = 23 })
	close.Parent = card
	close.Activated:Connect(function()
		setPicker(false)
	end)
	local list = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(14, 60),
		Size = UDim2.new(1, -28, 1, -136),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 22,
		Parent = card,
	})
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local garageRow = UIUtil.Create("Frame", {
		Name = "GarageRow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -28, 0, 60),
		BackgroundColor3 = Color3.fromRGB(255, 236, 246),
		ZIndex = 22,
		Parent = card,
	})
	UIUtil.Corner(garageRow, 16)
	local garageText = label({ Name = "Text", Text = "", Color = INK, TextSize = 16, Font = Theme.Fonts.Body, Size = UDim2.new(1, -220, 1, 0),
		Position = UDim2.fromOffset(14, 0), XAlign = Enum.TextXAlignment.Left, Wrap = true, ZIndex = 23, Parent = garageRow })
	local garageButton = UIUtil.PillButton({ Name = "BuyGarage", Text = "", Color = PINK, Height = 42, TextSize = 16, ZIndex = 23, Parent = garageRow })
	garageButton.AnchorPoint = Vector2.new(1, 0.5)
	garageButton.Position = UDim2.new(1, -10, 0.5, 0)
	garageButton.Activated:Connect(function()
		task.spawn(function()
			local ok, message, missing = invoke("buyGarage")
			toast(message)
			if not ok and type(missing) == "number" and missing > 0 then
				pcall(function()
					local NeedDopamine = require(Client.Components:WaitForChild("NeedDopamine", 2) :: any) :: any
					NeedDopamine.Offer(missing)
				end)
			end
		end)
	end)
	parts.Dimmer = dimmer
	parts.Picker = card
	parts.PickerList = list
	parts.GarageText = garageText
	parts.GarageButton = garageButton
end

local function fillPicker()
	local list = parts.PickerList
	if not list then
		return
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local cars = carsData()
	local any = false
	for index, car in ipairs(Config.Cars.List) do
		if cars.Owned and cars.Owned[car.Id] then
			any = true
			local row = UIUtil.Create("Frame", {
				Name = "Car_" .. car.Id,
				Size = UDim2.new(1, -8, 0, 86),
				BackgroundColor3 = if cars.Selected == car.Id then Color3.fromRGB(255, 226, 240) else WHITE,
				LayoutOrder = index,
				ZIndex = 23,
				Parent = list,
			})
			UIUtil.Corner(row, 14)
			UIUtil.Stroke(row, if cars.Selected == car.Id then PINK else Color3.fromRGB(236, 220, 232), 2)
			label({ Name = "Name", Text = car.Icon .. " " .. Locale.T(car.Name), TextSize = 19, Size = UDim2.new(0.5, 0, 0, 30), Position = UDim2.fromOffset(12, 6),
				XAlign = Enum.TextXAlignment.Left, ZIndex = 24, Parent = row })
			local selected = cars.Selected == car.Id
			local choose = UIUtil.PillButton({ Name = "Select", Text = if selected then Locale.T("✅ Selected") else Locale.T("Drive this one"),
				Color = if selected then MINT else SKY, Height = 32, TextSize = 15, ZIndex = 24, Parent = row })
			choose.AnchorPoint = Vector2.new(1, 0)
			choose.Position = UDim2.new(1, -10, 0, 8)
			choose.Activated:Connect(function()
				if not selected then
					task.spawn(function()
						local _, message = invoke("select", car.Id)
						toast(message)
					end)
				end
			end)
			-- nuancier (12 peintures)
			local swatches = UIUtil.Create("Frame", { Name = "Swatches", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 34),
				Position = UDim2.fromOffset(12, 44), ZIndex = 24, Parent = row })
			UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = swatches })
			local current = cars.Colors and cars.Colors[car.Id] or car.DefaultColor
			for k, paint in ipairs(Config.Cars.Colors) do
				local dot = UIUtil.Create("TextButton", { Name = "Paint_" .. paint.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = paint.Color,
					Size = UDim2.fromOffset(30, 30), LayoutOrder = k, ZIndex = 25, Parent = swatches })
				UIUtil.Corner(dot, UDim.new(1, 0))
				UIUtil.Stroke(dot, if paint.Id == current then PINK_DEEP else Color3.fromRGB(210, 200, 214), if paint.Id == current then 3 else 1.5)
				dot.Activated:Connect(function()
					task.spawn(function()
						local _, message = invoke("setColor", car.Id, paint.Id)
						toast(message)
					end)
				end)
			end
		end
	end
	if not any then
		local empty = UIUtil.Create("Frame", { Name = "Empty", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 90), ZIndex = 23, Parent = list })
		label({ Text = Locale.T("No car yet: visit the 🚗 car dealership next to the welcome square!"), TextSize = 18, Font = Theme.Fonts.Body, Wrap = true,
			ZIndex = 24, Parent = empty })
	end
	-- garage
	local garage = Config.House.Garage
	local data = ClientState.Data
	local house = data and data.House
	local mansion = house and house.OwnedSizes and house.OwnedSizes[garage.RequiresSize]
	local button: TextButton = parts.GarageButton
	if cars.Garage then
		parts.GarageText.Text = Locale.T("🏎️ Your garage is built: your cars are parked in front of your mansion")
		button.Visible = false
	else
		button.Visible = true
		button.Text = garage.Icon .. " " .. NumberFormatter.Format(garage.Cost)
		if not mansion then
			local size = Config.HouseSizesById[garage.RequiresSize]
			parts.GarageText.Text = Locale.T("🏎️ Garage: only for the %s", Locale.T(size and size.Name or "Mansion"))
		else
			parts.GarageText.Text = Locale.T("🏎️ Build a 3-car garage next to your mansion")
		end
	end
end

setPicker = function(open: boolean)
	pickerOpen = open
	if parts.Picker then
		parts.Picker.Visible = open
		parts.Dimmer.Visible = open
	end
	if open then
		fillPicker()
	end
end

local function spawnCar()
	if driving then
		return
	end
	local now = os.clock()
	if now - lastSpawn < Config.Cars.SpawnCooldown then
		return
	end
	lastSpawn = now
	refreshHud()
	task.spawn(function()
		local ok, message = invoke("spawn")
		if not ok then
			lastSpawn = -math.huge
			toast(message)
		end
		refreshHud()
	end)
end

local function exitCar()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
		humanoid.Jump = true
	end
	task.spawn(invoke, "exit")
end

local function buildGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild(CarClient.GUI_NAME)
	if old then
		old:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = CarClient.GUI_NAME
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 21
	screen.Parent = playerGui
	gui = screen
	local root = UIUtil.Create("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromOffset(1100, 620), Parent = screen })
	local scale = UIUtil.Create("UIScale", { Parent = root })
	parts.Root = root
	parts.Scale = scale

	-- colonne de gauche : 🚗 Ma voiture / ▾ mes voitures ; au volant : 💨 🔄 🚪
	local column = UIUtil.Create("Frame", {
		Name = "CarColumn",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(76, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder, Parent = column })
	local myCar = roundButton(column, "MyCar", "🚗", PINK_DEEP, 62, 1, "My car")
	myCar.Activated:Connect(spawnCar)
	local cooldown = label({ Name = "Cooldown", Text = "", Color = WHITE, TextSize = 22, ZIndex = 6, Parent = myCar })
	cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldown.BackgroundTransparency = 1
	UIUtil.Corner(cooldown, UDim.new(1, 0))
	local mine = roundButton(column, "MyCars", "🏎️", LILAC, 46, 2, "My cars")
	mine.Activated:Connect(function()
		setPicker(not pickerOpen)
	end)
	local honk = roundButton(column, "Honk", "💨", Color3.fromRGB(255, 196, 70), 56, 3, "Honk")
	honk.Activated:Connect(function()
		task.spawn(invoke, "honk")
	end)
	local flip = roundButton(column, "ResetCar", "🔄", SKY, 50, 4, "Reset car")
	flip.Activated:Connect(function()
		task.spawn(function()
			local _, message = invoke("reset")
			toast(message)
		end)
	end)
	local out = roundButton(column, "ExitCar", "🚪", PINK, 50, 5, "Get out")
	out.Activated:Connect(exitCar)
	parts.Column = column
	parts.MyCar = myCar
	parts.Cooldown = cooldown
	parts.MyCars = mine
	parts.Honk = honk
	parts.Reset = flip
	parts.Exit = out

	-- compteur de vitesse (en bas au milieu, au-dessus de "Se lever")
	local gauge = UIUtil.Create("Frame", {
		Name = "Speedometer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84),
		Size = UDim2.fromOffset(250, 64),
		BackgroundColor3 = Color3.fromRGB(60, 40, 76),
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = root,
	})
	UIUtil.Corner(gauge, UDim.new(1, 0))
	UIUtil.Stroke(gauge, PINK, 2.5)
	local speed = label({ Name = "Speed", Text = "0", Color = WHITE, TextSize = 30, Font = Theme.Fonts.Number, Size = UDim2.fromOffset(90, 40),
		Position = UDim2.fromOffset(18, 4), XAlign = Enum.TextXAlignment.Right, ZIndex = 3, Parent = gauge })
	label({ Name = "Unit", Text = "km/h", Color = Color3.fromRGB(255, 200, 226), TextSize = 15, Font = Theme.Fonts.Body, Size = UDim2.fromOffset(44, 40),
		Position = UDim2.fromOffset(112, 6), XAlign = Enum.TextXAlignment.Left, ZIndex = 3, Parent = gauge })
	local carName = label({ Name = "CarName", Text = "", Color = WHITE, TextSize = 15, Size = UDim2.fromOffset(96, 40), Position = UDim2.fromOffset(150, 4),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 3, Parent = gauge })
	local track_ = UIUtil.Create("Frame", { Name = "Track", Position = UDim2.new(0, 22, 1, -16), Size = UDim2.new(1, -44, 0, 7),
		BackgroundColor3 = Color3.fromRGB(110, 86, 126), ZIndex = 3, Parent = gauge })
	UIUtil.Corner(track_, UDim.new(1, 0))
	local fill = UIUtil.Create("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = PINK, ZIndex = 4, Parent = track_ })
	UIUtil.Corner(fill, UDim.new(1, 0))
	UIUtil.Gradient(fill, ColorSequence.new(MINT, PINK_DEEP), 0)
	local hint = label({ Name = "Hint", Text = "", Color = WHITE, TextSize = 14, Font = Theme.Fonts.Body, Size = UDim2.fromOffset(420, 20),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4), ZIndex = 3, Parent = gauge })
	UIUtil.Create("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.2, Parent = hint })
	parts.Gauge = gauge
	parts.Speed = speed
	parts.Fill = fill
	parts.CarName = carName
	parts.Hint = hint
	buildPicker(root)
end

local function layout()
	local screen = gui
	if not screen then
		return
	end
	local size = screen.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	phone = touch and math.min(size.X, size.Y) < 500
	local designW, designH = phone and 820 or 1100, phone and 430 or 620
	local scale = math.clamp(math.min(size.X / designW, size.Y / designH), 0.45, 1.35)
	parts.Scale.Scale = scale
	parts.Root.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
	-- téléphone : colonne plus haute (le joystick est en bas à gauche)
	parts.Column.AnchorPoint = if phone then Vector2.new(0, 0) else Vector2.new(0, 0.5)
	parts.Column.Position = if phone then UDim2.fromOffset(10, 118) else UDim2.new(0, 14, 0.5, 0)
	local layoutObj = parts.Column:FindFirstChildOfClass("UIListLayout")
	if layoutObj then
		layoutObj.Padding = UDim.new(0, phone and 16 or 22)
	end
	for _, button in ipairs({ parts.MyCar, parts.MyCars, parts.Honk, parts.Reset, parts.Exit }) do
		local tag = button:FindFirstChild("Tag")
		if tag then
			tag.Visible = not phone
		end
	end
	parts.Gauge.Position = if phone then UDim2.new(0.5, 0, 1, -76) else UDim2.new(0.5, 0, 1, -84)
	parts.Hint.Visible = not phone
	parts.Picker.Size = if phone then UDim2.fromOffset(560, 360) else UDim2.fromOffset(560, 400)
end

refreshHud = function()
	if not gui then
		return
	end
	local isDriving = driving ~= nil
	parts.MyCar.Visible = not isDriving
	parts.MyCars.Visible = not isDriving
	parts.Honk.Visible = isDriving
	parts.Reset.Visible = isDriving
	parts.Exit.Visible = isDriving
	parts.Gauge.Visible = isDriving
	local wait = Config.Cars.SpawnCooldown - (os.clock() - lastSpawn)
	parts.Cooldown.Text = if wait > 0.05 then tostring(math.ceil(wait)) else ""
	parts.Cooldown.BackgroundTransparency = if wait > 0.05 then 0.45 else 1
	if isDriving then
		local def = Config.CarsById[driving.CarId]
		parts.CarName.Text = def and def.Icon or "🚗"
		parts.Hint.Text = Locale.T("WASD / arrows to drive · Space to get out")
	end
	if pickerOpen then
		fillPicker()
	end
end

----------------------------------------------------------------------
-- Conduite
----------------------------------------------------------------------

local function moveVector(): Vector3
	if controls == nil then
		controls = false
		pcall(function()
			local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
			local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
			if module and module:IsA("ModuleScript") then
				controls = (require(module) :: any):GetControls()
			end
		end)
	end
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end
	return Vector3.zero
end

local function headingOf(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function setLights(on: boolean)
	if not driving then
		return
	end
	for _, light in ipairs(driving.Lights) do
		if light:IsA("Light") then
			light.Enabled = on
		end
	end
end

local function stopDriving()
	local d = driving
	if not d then
		return
	end
	driving = nil
	-- (plus de commande : la voiture s'arrête, à plat, avant que le serveur l'ancre)
	pcall(function()
		if d.Drive then
			d.Drive.PlaneVelocity = Vector2.new(0, 0)
		end
		if d.Align then
			d.Align.CFrame = CFrame.Angles(0, d.Heading, 0)
		end
	end)
	for _, light in ipairs(d.Lights) do
		pcall(light.Destroy, light)
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = BASE_FOV
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and camera.CameraSubject == d.Seat then
			camera.CameraSubject = humanoid
		end
	end
	refreshHud()
end

local function startDriving(seat: VehicleSeat)
	local model = seat.Parent
	if not model or not model:IsA("Model") then
		return
	end
	local root = model.PrimaryPart
	if not root then
		return
	end
	stopDriving()
	collectZones()
	-- 2 petits phares (attaches à l'avant de la boîte, tournées vers l'avant)
	local lights = {}
	local length = tonumber(model:GetAttribute("Length")) or root.Size.Z
	local width = tonumber(model:GetAttribute("Width")) or root.Size.X
	for _, sx in ipairs({ -1, 1 }) do
		local attachment = Instance.new("Attachment")
		attachment.Name = "CarHeadlight"
		attachment.Position = Vector3.new(sx * width * 0.3, 0, -length / 2 + 0.2)
		attachment.Parent = root
		local spot = Instance.new("SpotLight")
		spot.Name = "CarHeadlight"
		spot.Brightness = 0.8
		spot.Range = 26
		spot.Angle = 55
		spot.Face = Enum.NormalId.Front
		spot.Color = Color3.fromRGB(255, 244, 220)
		spot.Shadows = false
		spot.Enabled = isNight()
		spot.Parent = attachment
		table.insert(lights, attachment)
		table.insert(lights, spot)
	end
	driving = {
		Seat = seat,
		Model = model,
		Root = root,
		Drive = root:FindFirstChild("DriveVelocity"),
		Align = root:FindFirstChild("DriveAlign"),
		Heading = headingOf(root.CFrame),
		Speed = 0,
		LastSafe = root.CFrame,
		SafeClock = 0,
		LightClock = 0,
		Lights = lights,
		CarId = tostring(model:GetAttribute("CarId") or ""),
	}
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = seat
	end
	refreshHud()
end

-- Un pas de conduite (dt en s) : exporté pour les tests (CarClient.Debug().Step)
local function step(dt: number)
	local d = driving
	if not d then
		return
	end
	local seat: VehicleSeat = d.Seat
	local root: BasePart = d.Root
	if not seat.Parent or not root.Parent then
		stopDriving()
		return
	end
	local throttle = seat.ThrottleFloat
	local steer = seat.SteerFloat
	if math.abs(throttle) < 0.01 and math.abs(steer) < 0.01 then
		local move = moveVector()
		throttle = -move.Z
		steer = move.X
	end
	throttle = math.clamp(throttle, -1, 1)
	steer = math.clamp(steer, -1, 1)
	local maxSpeed = Config.Cars.MaxSpeed
	local look = Vector3.new(-math.sin(d.Heading), 0, -math.cos(d.Heading))
	local actual = root.AssemblyLinearVelocity:Dot(look)
	-- vitesse visée
	local target = 0
	local rate = COAST
	if throttle > 0.05 then
		target = throttle * maxSpeed
		rate = if actual < -1 then BRAKE else ACCEL
	elseif throttle < -0.05 then
		if actual > 1 then
			target = 0
			rate = BRAKE
		else
			target = throttle * Config.Cars.ReverseSpeed
			rate = ACCEL * 0.7
		end
	end
	-- on part de la vitesse RÉELLE (contre un mur, elle retombe)
	local base = if math.abs(actual - d.Speed) > 6 then actual else d.Speed
	local delta = math.clamp(target - base, -rate * dt, rate * dt)
	local speed = math.clamp(base + delta, -Config.Cars.ReverseSpeed, maxSpeed)
	if math.abs(speed) < 0.05 and target == 0 then
		speed = 0
	end
	d.Speed = speed
	-- virage : proportionnel à la vitesse (pas de rotation à l'arrêt), plus doux à fond
	local factor = math.clamp(math.abs(speed) / 12, 0, 1) * (1 - 0.4 * math.clamp(math.abs(speed) / maxSpeed, 0, 1))
	local direction = if speed >= 0 then 1 else -1
	d.Heading -= steer * TURN_RATE * factor * direction * dt
	look = Vector3.new(-math.sin(d.Heading), 0, -math.cos(d.Heading))
	local velocity = look * speed
	-- pas d'entrée dans les boutiques (sauf la concession) : remise en arrière
	local ahead = root.Position + velocity * 0.2
	if #shopZones > 0 and inZone(ahead) then
		velocity = Vector3.zero
		d.Speed = 0
		if inZone(root.Position) then
			root.CFrame = d.LastSafe
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if os.clock() - lastZoneToast > 3 then
			lastZoneToast = os.clock()
			toast(Locale.T("🚫 No cars inside!"))
		end
	else
		d.SafeClock += dt
		if d.SafeClock > 0.3 then
			d.SafeClock = 0
			d.LastSafe = root.CFrame
		end
	end
	local drive = d.Drive
	if drive then
		drive.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	end
	local align = d.Align
	if align then
		align.CFrame = CFrame.Angles(0, d.Heading, 0)
	end
	-- caméra : champ de vision un peu plus large en allant vite
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = BASE_FOV + 10 * math.clamp(math.abs(actual) / maxSpeed, 0, 1)
	end
	-- HUD (compteur : 1 stud/s ≈ 1 km/h, arrondi)
	if gui then
		local shown = math.floor(math.abs(actual) + 0.5)
		parts.Speed.Text = tostring(shown)
		parts.Fill.Size = UDim2.fromScale(math.clamp(math.abs(actual) / maxSpeed, 0, 1), 1)
	end
	d.LightClock += dt
	if d.LightClock > 1 then
		d.LightClock = 0
		setLights(isNight())
	end
end

local function onSeated(active: boolean, seatPart: BasePart?)
	if active and seatPart and seatPart:IsA("VehicleSeat") and seatPart.Name == "DriverSeat" then
		local model = seatPart.Parent
		if model and model:GetAttribute("OwnerId") == LocalPlayer.UserId then
			startDriving(seatPart)
			return
		end
	end
	if not active then
		stopDriving()
	end
end

local function watchCharacter(character: Model?)
	for _, c in ipairs(charConnections) do
		c:Disconnect()
	end
	table.clear(charConnections)
	stopDriving()
	if not character then
		return
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") and started then
			table.insert(charConnections, humanoid.Seated:Connect(onSeated))
			local seat = humanoid.SeatPart
			if seat then
				onSeated(true, seat)
			end
		end
	end)
end

----------------------------------------------------------------------
-- Invites "Conduire" (SA voiture seulement, traduites)
----------------------------------------------------------------------

local function fixPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompt.Name ~= "DrivePrompt" then
		return
	end
	local model = prompt:FindFirstAncestorWhichIsA("Model")
	local mine = model ~= nil and model:GetAttribute("OwnerId") == LocalPlayer.UserId
	prompt.Enabled = mine
	if mine then
		prompt.ActionText = Locale.T("Drive")
		local def = model and Config.CarsById[tostring(model:GetAttribute("CarId"))]
		if def then
			prompt.ObjectText = def.Icon .. " " .. Locale.T(def.Name)
		end
	end
end

local function watchCarsFolder(folder: Instance)
	for _, d in ipairs(folder:GetDescendants()) do
		fixPrompt(d)
	end
	track(folder.DescendantAdded:Connect(fixPrompt))
end

----------------------------------------------------------------------
-- Garages des manoirs
----------------------------------------------------------------------

local function ownerOf(model: Instance): (number, Instance?)
	local node: Instance? = model
	while node do
		local id = node:GetAttribute("OwnerId")
		if type(id) == "number" then
			return id, node
		end
		node = node.Parent
	end
	return 0, nil
end

local function parseCars(text: any): { { Id: string, Color: string } }
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	for entry in string.gmatch(text, "[^,]+") do
		local id, color = string.match(entry, "^([%w_]+):([%w_]+)$")
		if id and Config.CarsById[id] then
			table.insert(out, { Id = id, Color = color or "" })
		end
	end
	return out
end

local function refreshGarage(g: Garage)
	local owner = Players:GetPlayerByUserId(g.OwnerId)
	local text = owner and owner:GetAttribute("DopamineCars") or ""
	local selected = owner and owner:GetAttribute("DopamineCar") or ""
	local out = owner and owner:GetAttribute("DopamineCarOut") == true
	local key = tostring(text) .. "|" .. tostring(selected) .. "|" .. tostring(out)
	if key == g.Key then
		return
	end
	g.Key = key
	g.Cars:ClearAllChildren()
	local list = parseCars(text)
	local ids = {}
	for _, entry in ipairs(list) do
		table.insert(ids, entry.Id)
	end
	local bays = GarageLayout.Assign(ids, type(selected) == "string" and selected or nil)
	for _, entry in ipairs(list) do
		local bay = bays[entry.Id]
		if bay and not (out and entry.Id == selected) then
			local ok, model = pcall(CarModels.Build, entry.Id, entry.Color, { Detail = "Parked" })
			if ok and model then
				model.Name = "Parked_" .. entry.Id
				model:PivotTo(GarageLayout.BayCFrame(g.HouseCF, bay))
				model.Parent = g.Cars
			end
		end
	end
end

local function registerGarage(model: Instance)
	if not model:IsA("Model") or garages[model] then
		return
	end
	local houseCF = model:GetAttribute("HouseCF")
	if typeof(houseCF) ~= "CFrame" then
		return
	end
	local doors: { Door } = {}
	for bay = 1, GarageLayout.BAYS do
		local doorModel = model:FindFirstChild("Door_" .. bay)
		local panel = doorModel and doorModel:FindFirstChild("Panel")
		if doorModel and panel and panel:IsA("BasePart") then
			local closed = panel.CFrame
			local open = doorModel:GetAttribute("OpenCF")
			local list = {}
			for _, p in ipairs(doorModel:GetChildren()) do
				if p:IsA("BasePart") then
					table.insert(list, { Part = p, Offset = closed:ToObjectSpace(p.CFrame) })
				end
			end
			table.insert(doors, { Panel = panel, Parts = list, Closed = closed, Open = typeof(open) == "CFrame" and open or closed, T = 0, Target = 0 })
		end
	end
	-- voitures garées : HORS de l'extérieur de la maison (budget de pièces de
	-- la façade), dans la maison ("GarageCars"), vidé quand le garage disparaît
	local ownerId, house = ownerOf(model)
	local cars = house and house:FindFirstChild("GarageCars") or nil
	if not cars then
		cars = Instance.new("Folder")
		cars.Name = "GarageCars"
		cars.Parent = house or model
	end
	local lamp = model:FindFirstChild("CeilingLamp", true)
	local g: Garage = {
		Model = model,
		OwnerId = ownerId,
		HouseCF = houseCF,
		Doors = doors,
		Cars = cars :: Instance,
		Light = lamp and lamp:FindFirstChildWhichIsA("Light") or nil,
		Key = "",
	}
	garages[model] = g
	refreshGarage(g)
end

local function unregisterGarage(model: Instance)
	local g = garages[model :: Model]
	garages[model :: Model] = nil
	if g then
		g.Cars:ClearAllChildren()
	end
end

-- Portes : cibles (10 Hz) puis animation (chaque image)
local function garageTargets()
	local carsFolder = workspace:FindFirstChild("DopamineCars")
	for model, g in pairs(garages) do
		if not model.Parent then
			unregisterGarage(model)
			continue
		end
		refreshGarage(g)
		-- la voiture du propriétaire, ou le propriétaire à pied
		local points: { Vector3 } = {}
		if carsFolder then
			for _, car in ipairs(carsFolder:GetChildren()) do
				if car:IsA("Model") and car:GetAttribute("OwnerId") == g.OwnerId and car.PrimaryPart then
					table.insert(points, car.PrimaryPart.Position)
				end
			end
		end
		local owner = Players:GetPlayerByUserId(g.OwnerId)
		local character = owner and owner.Character
		local charRoot = character and character:FindFirstChild("HumanoidRootPart")
		local walker = charRoot and charRoot:IsA("BasePart") and charRoot.Position or nil
		for bay, door in ipairs(g.Doors) do
			local doorPoint = GarageLayout.DoorPoint(g.HouseCF, bay)
			local want = 0
			for _, p in ipairs(points) do
				-- porte la plus proche de la voiture seulement
				local best, bestDist = 1, math.huge
				for k = 1, #g.Doors do
					local dist = (GarageLayout.DoorPoint(g.HouseCF, k) - p).Magnitude
					if dist < bestDist then
						best, bestDist = k, dist
					end
				end
				if best == bay and bestDist < GarageLayout.OPEN_RANGE then
					want = 1
				end
			end
			if walker and (walker - doorPoint).Magnitude < 9 then
				want = 1
			end
			door.Target = want
		end
		local anyOpen = false
		for _, door in ipairs(g.Doors) do
			if door.Target > 0 or door.T > 0.02 then
				anyOpen = true
			end
		end
		if g.Light then
			g.Light.Enabled = anyOpen
		end
	end
end

local function animateDoors(dt: number)
	for _, g in pairs(garages) do
		for _, door in ipairs(g.Doors) do
			if door.T ~= door.Target then
				local speed = dt / DOOR_TIME
				door.T = if door.Target > door.T then math.min(door.Target, door.T + speed) else math.max(door.Target, door.T - speed)
				local t = door.T
				local eased = t * t * (3 - 2 * t)
				local cf = door.Closed:Lerp(door.Open, eased)
				for _, entry in ipairs(door.Parts) do
					entry.Part.CFrame = cf * entry.Offset
					entry.Part.CanCollide = t < 0.05 and entry.Part == door.Panel
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function CarClient.Start(startOptions: any?)
	if started then
		return
	end
	started = true
	options = type(startOptions) == "table" and startOptions or {}
	buildGui()
	layout()
	refreshHud()
	if gui then
		track(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	end
	track(ClientState.Changed:Connect(function()
		if pickerOpen then
			fillPicker()
		end
	end))
	track(LocalPlayer.CharacterAdded:Connect(watchCharacter))
	watchCharacter(LocalPlayer.Character)
	-- garages (HouseFacade les étiquette côté client)
	for _, model in ipairs(CollectionService:GetTagged(CarClient.GARAGE_TAG)) do
		registerGarage(model)
	end
	track(CollectionService:GetInstanceAddedSignal(CarClient.GARAGE_TAG):Connect(registerGarage))
	track(CollectionService:GetInstanceRemovedSignal(CarClient.GARAGE_TAG):Connect(unregisterGarage))
	-- invites des voitures
	local folder = workspace:FindFirstChild("DopamineCars")
	if folder then
		watchCarsFolder(folder)
	end
	track(workspace.ChildAdded:Connect(function(child)
		if child.Name == "DopamineCars" then
			watchCarsFolder(child)
		end
	end))
	local targetClock, hudClock = 0, 0
	track(RunService.Heartbeat:Connect(function(dt: number)
		if driving then
			local ok, err = pcall(step, dt)
			if not ok then
				warn("[CarClient] Conduite : " .. tostring(err))
				stopDriving()
			end
		end
		animateDoors(dt)
		targetClock += dt
		if targetClock >= 0.1 then
			targetClock = 0
			local ok, err = pcall(garageTargets)
			if not ok then
				warn("[CarClient] Garages : " .. tostring(err))
			end
		end
		hudClock += dt
		if hudClock >= 0.25 then
			hudClock = 0
			if not driving and gui then
				refreshHud()
			end
		end
	end))
end

function CarClient.Stop()
	if not started then
		return
	end
	started = false
	stopDriving()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	for _, c in ipairs(charConnections) do
		c:Disconnect()
	end
	table.clear(charConnections)
	table.clear(garages)
	pickerOpen = false
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(parts)
end

function CarClient.IsDriving(): boolean
	return driving ~= nil
end

function CarClient.Debug(): any
	return {
		Step = step,
		Driving = function()
			return driving
		end,
		Garages = garages,
		GarageTargets = garageTargets,
		AnimateDoors = animateDoors,
		Spawn = spawnCar,
		Exit = exitCar,
		SetPicker = setPicker,
		Seated = onSeated,
		Zones = shopZones,
	}
end

return CarClient
