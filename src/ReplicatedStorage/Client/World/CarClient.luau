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

	v9.8 (CARS98) :
	  - "🏎️ Mes voitures" REFAITE : grand aperçu 3D (ViewportFrame) de la
	    voiture qui tourne lentement sur un podium (on la fait tourner au
	    doigt / à la souris), nuancier INSTANTANÉ (on repeint le modèle, un
	    seul envoi au serveur 0,6 s après le dernier clic), fiche avec étoiles
	    (vitesse, accélération, maniabilité, confort), "🚗 Conduire" (choisit
	    puis sort la voiture), "Choisir", "Acheter" pour les autres voitures,
	    carrousel de miniatures 3D, infos du garage ; ordinateur + téléphone.
	    Plus de reconstruction de la fenêtre 4 fois par seconde (le lag).
	  - Conduite : caractère par modèle (CarModels.Handling), accélération
	    qui s'essouffle, volant lissé, glisse / drift avec fumée douce aux
	    roues arrière, champ de vision lissé.
	  - Garages : changement de couleur = on repeint (pas de reconstruction).

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
	ShapeKey: string?,
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
local refreshPrompts: () -> () = function() end -- (v9.7) invites "Conduire"

-- ░░ (v9.8, CARS98) fenêtre "🏎️ Mes voitures" refaite ░░
-- Grand APERÇU 3D (ViewportFrame) de la voiture choisie qui tourne
-- lentement sur un podium, lumière douce (on peut la faire tourner au doigt
-- / à la souris) ; nuancier : la couleur change TOUT DE SUITE (on repeint les
-- pièces du modèle, jamais de reconstruction), puis elle est enregistrée au
-- serveur une seule fois, 0,6 s après le dernier clic ; fiche (étoiles,
-- prix), boutons "🚗 Conduire" / "Choisir" / "Acheter" ; carrousel de
-- TOUTES les voitures (miniatures 3D, possédées d'abord) ; infos du garage.
-- Plus aucune reconstruction de la fenêtre 4 fois par seconde (c'était le
-- "lag" de la v9.7) : mise à jour légère quand les données changent.

local COLOR_DEBOUNCE = 0.6
local PREVIEW_SPIN = 0.32 -- rad/s

type Thumb = { Card: TextButton, View: ViewportFrame, Model: Model?, Badge: TextLabel, Name: TextLabel, CarId: string }
local picker: any = {
	Viewing = "", -- voiture affichée dans l'aperçu
	Models = {}, -- [carId] = Model (aperçu, construit une fois)
	Thumbs = {}, -- [carId] = Thumb
	Pending = {}, -- [carId] = colorId (pas encore envoyé)
	PendingClock = 0,
	Local = {}, -- [carId] = colorId (affiché tout de suite, en attendant le serveur)
	Yaw = math.rad(-35),
	Dragging = false,
	DragX = 0,
	LastDrag = -math.huge,
	OwnedKey = "",
	Sending = false,
}
local requestSpawn: () -> () = function() end

local STAT_ROWS = {
	{ "Speed", "⚡ Speed" },
	{ "Accel", "🏁 Acceleration" },
	{ "Grip", "🌀 Handling" },
	{ "Comfort", "🛋️ Comfort" },
}

local function colorIdOf(carId: string): string
	local pending = picker.Pending[carId] or picker.Local[carId]
	if pending then
		return pending
	end
	local cars = carsData()
	local id = cars.Colors and cars.Colors[carId]
	if type(id) == "string" and Config.CarColorsById[id] then
		return id
	end
	local def = Config.CarsById[carId]
	return def and def.DefaultColor or "Bubblegum"
end

local function owns(carId: string): boolean
	local cars = carsData()
	return cars.Owned ~= nil and cars.Owned[carId] == true
end

-- Liste affichée : voitures possédées d'abord, puis les autres (ordre du catalogue)
local function pickerList(): { any }
	local list = {}
	for _, car in ipairs(Config.Cars.List) do
		if owns(car.Id) then
			table.insert(list, car)
		end
	end
	for _, car in ipairs(Config.Cars.List) do
		if not owns(car.Id) then
			table.insert(list, car)
		end
	end
	return list
end

local function lockOf(carId: string): string?
	local ok, reason = pcall(CarModels.LockReason, ClientState.Data, carId)
	if ok then
		return reason
	end
	return nil
end

local function frame(props: { [string]: any }): Frame
	props.BorderSizePixel = 0
	return UIUtil.Create("Frame", props)
end

local function setButton(button: TextButton, text: string, color: Color3, visible: boolean)
	button.Visible = visible
	button.Text = text
	button.BackgroundColor3 = color
	button:SetAttribute("BaseColor", color)
end

-- ░ aperçu 3D ░
local function previewModel(carId: string): Model?
	local model = picker.Models[carId]
	if model then
		return model
	end
	local ok, built = pcall(CarModels.Build, carId, colorIdOf(carId), { Detail = "Full", Plate = "DOPA " .. tostring(LocalPlayer.UserId % 1000) })
	if not ok or typeof(built) ~= "Instance" or not built:IsA("Model") then
		return nil
	end
	local car = built :: Model
	car:PivotTo(CFrame.new())
	picker.Models[carId] = car
	return car
end

local function showPreview(carId: string)
	local view: ViewportFrame? = parts.Preview
	if not view then
		return
	end
	picker.Viewing = carId
	for id, model in pairs(picker.Models) do
		if id ~= carId then
			model.Parent = nil
		end
	end
	local model = previewModel(carId)
	if model then
		CarModels.Repaint(model, carId, colorIdOf(carId))
		model.Parent = view
	end
end

local function updateCamera()
	local camera: Camera? = parts.PreviewCamera
	local model = picker.Models[picker.Viewing]
	if not camera then
		return
	end
	local length = model and tonumber(model:GetAttribute("Length")) or 12
	local height = model and tonumber(model:GetAttribute("Height")) or 5
	local dist = 4 + length * 0.86
	local target = Vector3.new(0, height * 0.42, 0)
	local eye = (CFrame.Angles(0, picker.Yaw, 0) * CFrame.new(0, height * 0.55 + 2.6, dist)).Position
	camera.CFrame = CFrame.lookAt(eye, target)
end

local function stepPreview(dt: number)
	if not pickerOpen then
		return
	end
	if not picker.Dragging and os.clock() - picker.LastDrag > 1.6 then
		picker.Yaw = (picker.Yaw + PREVIEW_SPIN * dt) % (math.pi * 2)
	end
	updateCamera()
	-- couleur : un seul envoi au serveur, après le dernier clic
	if next(picker.Pending) ~= nil and not picker.Sending and os.clock() - picker.PendingClock >= COLOR_DEBOUNCE then
		local batch = picker.Pending
		picker.Pending = {}
		picker.Sending = true
		task.spawn(function()
			for carId, colorId in pairs(batch) do
				local ok, message = invoke("setColor", carId, colorId)
				if not ok then
					picker.Local[carId] = nil
					toast(message)
				end
			end
			picker.Sending = false
		end)
	end
end

-- ░ miniatures ░
local function thumbModel(thumb: Thumb)
	if thumb.Model then
		return
	end
	local ok, built = pcall(CarModels.Build, thumb.CarId, colorIdOf(thumb.CarId), { Detail = "Mid" })
	if ok and typeof(built) == "Instance" and built:IsA("Model") then
		local model = built :: Model
		model:PivotTo(CFrame.Angles(0, math.rad(-35), 0))
		model.Parent = thumb.View
		thumb.Model = model
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		local length = tonumber(model:GetAttribute("Length")) or 12
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 4.5, 3 + length * 1.25), Vector3.new(0, 1.9, 0))
		camera.Parent = thumb.View
		thumb.View.CurrentCamera = camera
	end
end

local refreshPicker: () -> () = function() end

local function selectInPicker(carId: string)
	if picker.Viewing ~= carId then
		showPreview(carId)
	end
	refreshPicker()
end

local function buildThumbs()
	local list = parts.Carousel
	if not list then
		return
	end
	for _, car in ipairs(Config.Cars.List) do
		if not picker.Thumbs[car.Id] then
			local card = UIUtil.Create("TextButton", {
				Name = "Thumb_" .. car.Id,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = WHITE,
				Size = UDim2.fromOffset(128, 98),
				ZIndex = 23,
				Parent = list,
			})
			UIUtil.Corner(card, 14)
			UIUtil.Stroke(card, Color3.fromRGB(236, 220, 232), 2)
			local view = UIUtil.Create("ViewportFrame", {
				Name = "View",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -8, 1, -26),
				Position = UDim2.fromOffset(4, 2),
				Ambient = Color3.fromRGB(170, 166, 180),
				LightColor = Color3.fromRGB(255, 250, 244),
				LightDirection = Vector3.new(-0.5, -1, -0.6),
				ZIndex = 24,
				Parent = card,
			})
			local name = label({ Name = "Name", Text = car.Icon .. " " .. Locale.T(car.Name), TextSize = 13, Size = UDim2.new(1, -8, 0, 20),
				Position = UDim2.new(0, 4, 1, -22), ZIndex = 25, Parent = card })
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local badge = label({ Name = "Badge", Text = "", Color = WHITE, TextSize = 12, Size = UDim2.fromOffset(0, 20), Position = UDim2.fromOffset(6, 6), ZIndex = 26, Parent = card })
			badge.AutomaticSize = Enum.AutomaticSize.X
			badge.BackgroundTransparency = 0
			badge.BackgroundColor3 = MINT
			UIUtil.Corner(badge, UDim.new(1, 0))
			UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = badge })
			local thumb: Thumb = { Card = card, View = view, Model = nil, Badge = badge, Name = name, CarId = car.Id }
			picker.Thumbs[car.Id] = thumb
			card.Activated:Connect(function()
				selectInPicker(car.Id)
			end)
		end
	end
end

local function statBar(parent: Instance, order: number, key: string, text: string): Frame
	local row = frame({ Name = "Stat_" .. key, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order, ZIndex = 23, Parent = parent })
	label({ Name = "Label", Text = Locale.T(text), TextSize = 15, Font = Theme.Fonts.Body, Size = UDim2.new(0.46, 0, 1, 0), XAlign = Enum.TextXAlignment.Left, ZIndex = 24, Parent = row })
	local bar = frame({ Name = "Bar", BackgroundTransparency = 1, Size = UDim2.new(0.54, 0, 0, 12), Position = UDim2.new(0.46, 0, 0.5, -6), ZIndex = 24, Parent = row })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
	for k = 1, 5 do
		local seg = frame({ Name = "Seg" .. k, BackgroundColor3 = Color3.fromRGB(236, 224, 236), Size = UDim2.new(0.2, -4, 1, 0), LayoutOrder = k, ZIndex = 25, Parent = bar })
		UIUtil.Corner(seg, UDim.new(1, 0))
	end
	return row
end

local function buildPicker(root: Frame)
	local dimmer = UIUtil.Create("TextButton", {
		Name = "PickerDimmer",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Size = UDim2.new(1, 400, 1, 400),
		Position = UDim2.fromOffset(-200, -200),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	dimmer.Activated:Connect(function()
		setPicker(false)
	end)
	local card = frame({
		Name = "CarPicker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(960, 570),
		BackgroundColor3 = CARD,
		Visible = false,
		ZIndex = 21,
		Parent = root,
	})
	UIUtil.Corner(card, 24)
	UIUtil.Stroke(card, PINK, 3)
	UIUtil.SinkClicks(card)
	label({ Name = "Title", Text = Locale.T("🏎️ My cars"), Color = PINK_DEEP, TextSize = 26, Size = UDim2.new(0, 300, 0, 40),
		Position = UDim2.fromOffset(22, 10), XAlign = Enum.TextXAlignment.Left, ZIndex = 22, Parent = card })
	local close = UIUtil.CloseButton({ Name = "ClosePicker", Size = 40, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), ZIndex = 23 })
	close.Parent = card
	close.Activated:Connect(function()
		setPicker(false)
	end)
	-- ░ scène 3D : fond dégradé + ViewportFrame ░
	local stage = frame({ Name = "Stage", BackgroundColor3 = WHITE, Position = UDim2.fromOffset(16, 56), Size = UDim2.fromOffset(580, 330), ZIndex = 22, Parent = card })
	UIUtil.Corner(stage, 18)
	UIUtil.Gradient(stage, ColorSequence.new(Color3.fromRGB(255, 236, 246), Color3.fromRGB(206, 196, 246)), 90)
	local view = UIUtil.Create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 146, 162),
		LightColor = Color3.fromRGB(255, 248, 238),
		LightDirection = Vector3.new(-0.55, -1, -0.45),
		ZIndex = 23,
		Parent = stage,
	})
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = 34
	camera.Parent = view
	view.CurrentCamera = camera
	-- podium : disque clair + anneau rose (dans la scène)
	local podium = Instance.new("Part")
	podium.Name = "Podium"
	podium.Anchored = true
	podium.Shape = Enum.PartType.Cylinder
	podium.Size = Vector3.new(0.4, 21, 21)
	podium.CFrame = CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	podium.Color = Color3.fromRGB(250, 246, 252)
	podium.Material = Enum.Material.SmoothPlastic
	podium.Parent = view
	local rim = podium:Clone()
	rim.Name = "PodiumRim"
	rim.Size = Vector3.new(0.3, 22, 22)
	rim.CFrame = CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
	rim.Color = PINK
	rim.Parent = view
	local carTitle = label({ Name = "CarTitle", Text = "", Color = INK, TextSize = 24, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(14, 8),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 25, Parent = stage })
	local carDesc = label({ Name = "CarDesc", Text = "", Color = INK, TextSize = 15, Font = Theme.Fonts.Body, Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(14, 38), XAlign = Enum.TextXAlignment.Left, ZIndex = 25, Parent = stage })
	carDesc.TextTransparency = 0.2
	local dragHint = label({ Name = "DragHint", Text = Locale.T("⟲ Drag to turn"), Color = INK, TextSize = 13, Font = Theme.Fonts.Body, Size = UDim2.fromOffset(160, 18),
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -8), XAlign = Enum.TextXAlignment.Right, ZIndex = 25, Parent = stage })
	dragHint.TextTransparency = 0.35
	-- rotation au doigt / à la souris
	view.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			picker.Dragging = true
			picker.DragX = input.Position.X
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input: InputObject)
		if picker.Dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local dx = input.Position.X - picker.DragX
			picker.DragX = input.Position.X
			picker.Yaw -= dx * 0.012
			picker.LastDrag = os.clock()
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if picker.Dragging then
				picker.LastDrag = os.clock()
			end
			picker.Dragging = false
		end
	end))
	-- ░ nuancier (sous l'aperçu) ░
	local paintRow = frame({ Name = "PaintRow", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 394), Size = UDim2.fromOffset(580, 44), ZIndex = 22, Parent = card })
	local swatches = frame({ Name = "Swatches", BackgroundTransparency = 1, Size = UDim2.new(1, -150, 1, 0), ZIndex = 23, Parent = paintRow })
	local swatchLayout = UIUtil.Create("UIGridLayout", { CellSize = UDim2.fromOffset(30, 30), CellPadding = UDim2.fromOffset(5, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = swatches })
	local paintName = label({ Name = "PaintName", Text = "", Color = INK, TextSize = 15, Font = Theme.Fonts.Body, Size = UDim2.new(0, 146, 1, 0), AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0), XAlign = Enum.TextXAlignment.Right, Wrap = true, ZIndex = 23, Parent = paintRow })
	local swatchButtons = {}
	for k, paint in ipairs(Config.Cars.Colors) do
		local dot = UIUtil.Create("TextButton", { Name = "Paint_" .. paint.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = paint.Color,
			LayoutOrder = k, ZIndex = 24, Parent = swatches })
		UIUtil.Corner(dot, UDim.new(1, 0))
		local stroke = UIUtil.Stroke(dot, Color3.fromRGB(210, 200, 214), 1.5)
		-- reflet (petit point clair) : la pastille a l'air vernie
		local shine = frame({ Name = "Shine", BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, Size = UDim2.fromScale(0.3, 0.3), Position = UDim2.fromScale(0.2, 0.16), ZIndex = 25, Parent = dot })
		UIUtil.Corner(shine, UDim.new(1, 0))
		swatchButtons[paint.Id] = { Button = dot, Stroke = stroke }
		dot.Activated:Connect(function()
			local carId = picker.Viewing
			if carId == "" then
				return
			end
			-- tout de suite à l'écran (aperçu + miniature), serveur plus tard
			picker.Local[carId] = paint.Id
			local model = picker.Models[carId]
			if model then
				CarModels.Repaint(model, carId, paint.Id)
			end
			local thumb = picker.Thumbs[carId]
			if thumb and thumb.Model then
				CarModels.Repaint(thumb.Model, carId, paint.Id)
			end
			if owns(carId) then
				picker.Pending[carId] = paint.Id
				picker.PendingClock = os.clock()
			end
			refreshPicker()
		end)
	end
	-- ░ fiche (à droite) ░
	local info = frame({ Name = "Info", BackgroundColor3 = WHITE, Position = UDim2.fromOffset(612, 56), Size = UDim2.fromOffset(332, 382), ZIndex = 22, Parent = card })
	UIUtil.Corner(info, 18)
	UIUtil.Stroke(info, Color3.fromRGB(244, 222, 236), 2)
	local infoTitle = label({ Name = "InfoTitle", Text = "", Color = PINK_DEEP, TextSize = 22, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(14, 10),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 23, Parent = info })
	infoTitle.TextTruncate = Enum.TextTruncate.AtEnd
	local status = label({ Name = "Status", Text = "", Color = INK, TextSize = 15, Font = Theme.Fonts.Body, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(14, 40),
		XAlign = Enum.TextXAlignment.Left, Wrap = true, ZIndex = 23, Parent = info })
	local stats = frame({ Name = "Stats", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 72), Size = UDim2.new(1, -28, 0, 110), ZIndex = 23, Parent = info })
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = stats })
	local statRows = {}
	for k, row in ipairs(STAT_ROWS) do
		statRows[row[1]] = statBar(stats, k, row[1], row[2])
	end
	local drive = UIUtil.PillButton({ Name = "DriveCar", Text = "", Color = PINK_DEEP, Height = 46, TextSize = 19, ZIndex = 24, Parent = info })
	drive.AutomaticSize = Enum.AutomaticSize.None
	drive.Size = UDim2.new(1, -28, 0, 46)
	drive.Position = UDim2.fromOffset(14, 196)
	local choose = UIUtil.PillButton({ Name = "Select", Text = "", Color = SKY, Height = 38, TextSize = 16, ZIndex = 24, Parent = info })
	choose.AutomaticSize = Enum.AutomaticSize.None
	choose.Size = UDim2.new(1, -28, 0, 38)
	choose.Position = UDim2.fromOffset(14, 250)
	-- garage
	local garageRow = frame({ Name = "GarageRow", BackgroundColor3 = Color3.fromRGB(255, 236, 246), Position = UDim2.new(0, 10, 1, -86), Size = UDim2.new(1, -20, 0, 76), ZIndex = 23, Parent = info })
	UIUtil.Corner(garageRow, 14)
	local garageText = label({ Name = "Text", Text = "", Color = INK, TextSize = 14, Font = Theme.Fonts.Body, Size = UDim2.new(1, -16, 0, 36),
		Position = UDim2.fromOffset(8, 2), XAlign = Enum.TextXAlignment.Left, Wrap = true, ZIndex = 24, Parent = garageRow })
	local garageButton = UIUtil.PillButton({ Name = "BuyGarage", Text = "", Color = PINK, Height = 32, TextSize = 15, ZIndex = 24, Parent = garageRow })
	garageButton.AnchorPoint = Vector2.new(1, 1)
	garageButton.Position = UDim2.new(1, -8, 1, -6)
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
	drive.Activated:Connect(function()
		local carId = picker.Viewing
		if carId == "" then
			return
		end
		task.spawn(function()
			if not owns(carId) then
				-- acheter (le serveur vérifie tout : prix, verrou)
				local ok, message, missing = invoke("buy", carId)
				toast(message)
				if not ok and type(missing) == "number" and missing > 0 then
					pcall(function()
						local NeedDopamine = require(Client.Components:WaitForChild("NeedDopamine", 2) :: any) :: any
						NeedDopamine.Offer(missing)
					end)
				end
				return
			end
			-- conduire : la couleur choisie part d'abord, puis on sort la voiture
			local pending = picker.Pending[carId]
			if pending then
				picker.Pending[carId] = nil
				invoke("setColor", carId, pending)
			end
			if carsData().Selected ~= carId then
				local ok, message = invoke("select", carId)
				if not ok then
					toast(message)
					return
				end
			end
			setPicker(false)
			requestSpawn()
		end)
	end)
	choose.Activated:Connect(function()
		local carId = picker.Viewing
		if carId ~= "" and owns(carId) and carsData().Selected ~= carId then
			task.spawn(function()
				local _, message = invoke("select", carId)
				toast(message)
			end)
		end
	end)
	-- ░ carrousel (toutes les voitures) ░
	local carousel = UIUtil.Create("ScrollingFrame", {
		Name = "Carousel",
		Position = UDim2.fromOffset(16, 446),
		Size = UDim2.new(1, -32, 0, 112),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ZIndex = 22,
		Parent = card,
	})
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center, Parent = carousel })
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), Parent = carousel })
	parts.Dimmer = dimmer
	parts.Picker = card
	parts.Stage = stage
	parts.Preview = view
	parts.PreviewCamera = camera
	parts.CarTitle = carTitle
	parts.CarDesc = carDesc
	parts.PaintRow = paintRow
	parts.Swatches = swatches
	parts.SwatchLayout = swatchLayout
	parts.SwatchButtons = swatchButtons
	parts.PaintName = paintName
	parts.Info = info
	parts.InfoTitle = infoTitle
	parts.Status = status
	parts.StatRows = statRows
	parts.Drive = drive
	parts.Choose = choose
	parts.Carousel = carousel
	parts.GarageText = garageText
	parts.GarageButton = garageButton
end

-- Mise à jour LÉGÈRE (textes, boutons, badges, contours) : jamais de reconstruction
refreshPicker = function()
	if not parts.Picker or not pickerOpen then
		return
	end
	local cars = carsData()
	local list = pickerList()
	-- ordre du carrousel (possédées d'abord) + miniatures
	for index, car in ipairs(list) do
		local thumb: Thumb? = picker.Thumbs[car.Id]
		if thumb then
			thumb.Card.LayoutOrder = index
			local owned = owns(car.Id)
			local lock = if owned then nil else lockOf(car.Id)
			local badge = thumb.Badge
			if cars.Selected == car.Id then
				badge.Text = Locale.T("✅ Selected")
				badge.BackgroundColor3 = MINT
			elseif owned then
				badge.Text = Locale.T("In the garage")
				badge.BackgroundColor3 = SKY
			elseif lock then
				badge.Text = "🔒"
				badge.BackgroundColor3 = LILAC
			else
				badge.Text = "🧠 " .. NumberFormatter.Format(car.Cost)
				badge.BackgroundColor3 = PINK
			end
			thumb.View.ImageTransparency = if owned or lock == nil then 0 else 0.45
			local stroke = thumb.Card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if picker.Viewing == car.Id then PINK_DEEP else Color3.fromRGB(236, 220, 232)
				stroke.Thickness = if picker.Viewing == car.Id then 3 else 2
			end
			if thumb.Model then
				CarModels.Repaint(thumb.Model, car.Id, colorIdOf(car.Id))
			end
		end
	end
	-- fiche de la voiture affichée
	local carId = picker.Viewing
	local def = Config.CarsById[carId]
	if def then
		local owned = owns(carId)
		local lock = if owned then nil else lockOf(carId)
		parts.CarTitle.Text = def.Icon .. " " .. Locale.T(def.Name)
		parts.CarDesc.Text = Locale.T(def.Desc)
		parts.InfoTitle.Text = def.Icon .. " " .. Locale.T(def.Name)
		if owned then
			parts.Status.Text = if cars.Selected == carId then Locale.T("✅ Your chosen car") else Locale.T("🔑 Yours — parked in your garage")
		elseif lock then
			parts.Status.Text = lock
		else
			parts.Status.Text = Locale.T("On sale at the 🚗 dealership: 🧠 %s", NumberFormatter.Format(def.Cost))
		end
		local h = CarModels.Handling(carId)
		for key, row in pairs(parts.StatRows) do
			local n = h.Stars[key] or 0
			for k = 1, 5 do
				local seg = row.Bar:FindFirstChild("Seg" .. k)
				if seg then
					seg.BackgroundColor3 = if k <= n then (if key == "Speed" then PINK_DEEP elseif key == "Accel" then Color3.fromRGB(255, 160, 60) elseif key == "Grip" then SKY else MINT) else Color3.fromRGB(236, 224, 236)
				end
			end
		end
		if owned then
			setButton(parts.Drive, Locale.T("🚗 Drive"), PINK_DEEP, true)
			setButton(parts.Choose, if cars.Selected == carId then Locale.T("✅ Selected") else Locale.T("Choose this one"), if cars.Selected == carId then MINT else SKY, true)
		elseif lock then
			setButton(parts.Drive, "🔒 " .. Locale.T("Locked"), LILAC, true)
			setButton(parts.Choose, "", SKY, false)
		else
			setButton(parts.Drive, Locale.T("Buy — 🧠 %s", NumberFormatter.Format(def.Cost)), PINK_DEEP, true)
			setButton(parts.Choose, "", SKY, false)
		end
		-- nuancier : contour sur la couleur affichée
		local current = colorIdOf(carId)
		for id, sw in pairs(parts.SwatchButtons) do
			sw.Stroke.Color = if id == current then PINK_DEEP else Color3.fromRGB(210, 200, 214)
			sw.Stroke.Thickness = if id == current then 3.5 else 1.5
		end
		local paint = Config.CarColorsById[current]
		parts.PaintName.Text = "🎨 " .. Locale.T(paint and paint.Name or current) .. (if owned then "" else "\n" .. Locale.T("(preview)"))
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

-- Mise en page (ordinateur / téléphone) de la fenêtre
local function layoutPicker()
	local card = parts.Picker
	if not card then
		return
	end
	if phone then
		card.Size = UDim2.fromOffset(800, 410)
		parts.Stage.Position = UDim2.fromOffset(12, 52)
		parts.Stage.Size = UDim2.fromOffset(430, 226)
		parts.PaintRow.Position = UDim2.fromOffset(12, 282)
		parts.PaintRow.Size = UDim2.fromOffset(430, 30)
		parts.SwatchLayout.CellSize = UDim2.fromOffset(24, 24)
		parts.SwatchLayout.CellPadding = UDim2.fromOffset(3, 3)
		parts.PaintName.Size = UDim2.new(0, 96, 1, 0)
		parts.Swatches.Size = UDim2.new(1, -98, 1, 0)
		parts.Info.Position = UDim2.fromOffset(454, 52)
		parts.Info.Size = UDim2.fromOffset(334, 262)
		parts.Carousel.Position = UDim2.fromOffset(12, 318)
		parts.Carousel.Size = UDim2.new(1, -24, 0, 86)
		parts.Status.Position = UDim2.fromOffset(14, 36)
		parts.StatRows.Speed.Parent.Position = UDim2.fromOffset(14, 58)
		parts.Drive.Position = UDim2.fromOffset(14, 136)
		parts.Drive.Size = UDim2.new(0.5, -18, 0, 40)
		parts.Choose.Position = UDim2.new(0.5, 4, 0, 138)
		parts.Choose.Size = UDim2.new(0.5, -18, 0, 36)
		parts.GarageText.Parent.Position = UDim2.fromOffset(10, 184)
		parts.GarageText.Parent.Size = UDim2.new(1, -20, 0, 70)
		for _, thumb in pairs(picker.Thumbs) do
			thumb.Card.Size = UDim2.fromOffset(104, 80)
		end
		parts.StatRows.Speed.Parent.Size = UDim2.new(1, -28, 0, 72)
		for _, row in pairs(parts.StatRows) do
			row.Size = UDim2.new(1, 0, 0, 15)
		end
		local statLayout = parts.StatRows.Speed.Parent:FindFirstChildOfClass("UIListLayout")
		if statLayout then
			statLayout.Padding = UDim.new(0, 3)
		end
	else
		card.Size = UDim2.fromOffset(960, 570)
		parts.Stage.Position = UDim2.fromOffset(16, 56)
		parts.Stage.Size = UDim2.fromOffset(580, 330)
		parts.PaintRow.Position = UDim2.fromOffset(16, 394)
		parts.PaintRow.Size = UDim2.fromOffset(580, 44)
		parts.SwatchLayout.CellSize = UDim2.fromOffset(30, 30)
		parts.SwatchLayout.CellPadding = UDim2.fromOffset(5, 5)
		parts.PaintName.Size = UDim2.new(0, 146, 1, 0)
		parts.Swatches.Size = UDim2.new(1, -150, 1, 0)
		parts.Info.Position = UDim2.fromOffset(612, 56)
		parts.Info.Size = UDim2.fromOffset(332, 382)
		parts.Carousel.Position = UDim2.fromOffset(16, 446)
		parts.Carousel.Size = UDim2.new(1, -32, 0, 112)
		parts.Status.Position = UDim2.fromOffset(14, 40)
		parts.StatRows.Speed.Parent.Position = UDim2.fromOffset(14, 72)
		parts.Drive.Position = UDim2.fromOffset(14, 196)
		parts.Drive.Size = UDim2.new(1, -28, 0, 46)
		parts.Choose.Position = UDim2.fromOffset(14, 250)
		parts.Choose.Size = UDim2.new(1, -28, 0, 38)
		parts.GarageText.Parent.Position = UDim2.new(0, 10, 1, -86)
		parts.GarageText.Parent.Size = UDim2.new(1, -20, 0, 76)
		for _, thumb in pairs(picker.Thumbs) do
			thumb.Card.Size = UDim2.fromOffset(128, 98)
		end
		parts.StatRows.Speed.Parent.Size = UDim2.new(1, -28, 0, 110)
		for _, row in pairs(parts.StatRows) do
			row.Size = UDim2.new(1, 0, 0, 22)
		end
		local statLayout = parts.StatRows.Speed.Parent:FindFirstChildOfClass("UIListLayout")
		if statLayout then
			statLayout.Padding = UDim.new(0, 6)
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
		buildThumbs()
		layoutPicker()
		-- miniatures 3D : une par image (jamais de gros à-coup à l'ouverture)
		task.spawn(function()
			for _, car in ipairs(Config.Cars.List) do
				local thumb = picker.Thumbs[car.Id]
				if not pickerOpen then
					break
				end
				if thumb and not thumb.Model then
					thumbModel(thumb)
					task.wait()
				end
			end
		end)
		local cars = carsData()
		local first = if cars.Selected ~= "" and Config.CarsById[cars.Selected] then cars.Selected else (pickerList()[1] and pickerList()[1].Id or "")
		if picker.Viewing == "" or not Config.CarsById[picker.Viewing] then
			picker.Viewing = first
		end
		showPreview(picker.Viewing)
		updateCamera()
		refreshPicker()
	else
		picker.Dragging = false
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

requestSpawn = spawnCar

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
	layoutPicker()
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
	-- (v9.8) plus de reconstruction de "Mes voitures" ici (c'était le lag)
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
	refreshPrompts() -- (v9.7) l'invite "Conduire" revient une fois descendu
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
	-- (v9.8) fumée de dérapage aux roues arrière (particules douces, locales)
	local smoke = {}
	for _, sx in ipairs({ -1, 1 }) do
		local attachment = Instance.new("Attachment")
		attachment.Name = "DriftSmoke"
		attachment.Position = Vector3.new(sx * width * 0.36, -root.Size.Y / 2 + 0.2, length / 2 - 2.2)
		attachment.Parent = root
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "DriftSmoke"
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(236, 236, 240))
		emitter.LightEmission = 0
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.2) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(40, 40)
		emitter.Rate = 22
		emitter.Enabled = false
		emitter.Parent = attachment
		table.insert(lights, attachment) -- (détruit avec les phares à la sortie)
		table.insert(smoke, emitter)
	end
	local carId = tostring(model:GetAttribute("CarId") or "")
	driving = {
		Seat = seat,
		Model = model,
		Root = root,
		Drive = root:FindFirstChild("DriveVelocity"),
		Align = root:FindFirstChild("DriveAlign"),
		Heading = headingOf(root.CFrame),
		Speed = 0,
		Steer = 0,
		Vel = Vector3.zero,
		Slip = 0,
		Smoke = smoke,
		Handling = CarModels.Handling(carId),
		LastSafe = root.CFrame,
		SafeClock = 0,
		LightClock = 0,
		Lights = lights,
		CarId = carId,
	}
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = seat
	end
	-- (v9.7) au volant : plus d'invite "Conduire", fenêtre "Mes voitures" fermée
	if pickerOpen then
		setPicker(false)
	end
	refreshHud()
	refreshPrompts()
end

-- Un pas de conduite (dt en s) : exporté pour les tests (CarClient.Debug().Step)
-- (v9.8, CARS98) conduite plus douce et plus "voiture" :
--  - chaque modèle a son caractère (CarModels.Handling : vitesse max,
--    accélération, adhérence) ; accélération qui s'essouffle près de la
--    vitesse max ; direction lissée (le volant ne claque plus) ;
--  - GLISSE : la vitesse garde une part latérale qui ne se résorbe que
--    progressivement (adhérence) ; à fond en braquant fort, l'adhérence
--    baisse -> la voiture dérape (drift) avec un peu de fumée aux roues
--    arrière (particules locales, douces) ;
--  - caméra : champ de vision qui s'élargit avec la vitesse.
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
	local h = d.Handling
	-- volant lissé (plus vite pour revenir au centre)
	local steerRate = if math.abs(steer) < math.abs(d.Steer) then 7 else 4.5
	d.Steer += math.clamp(steer - d.Steer, -steerRate * dt, steerRate * dt)
	local maxSpeed = Config.Cars.MaxSpeed * h.Speed
	local look = Vector3.new(-math.sin(d.Heading), 0, -math.cos(d.Heading))
	local actual = root.AssemblyLinearVelocity:Dot(look)
	-- vitesse visée
	local target = 0
	local rate = COAST
	if throttle > 0.05 then
		target = throttle * maxSpeed
		local fade = 1 - 0.55 * math.clamp(math.max(actual, 0) / maxSpeed, 0, 1) ^ 2
		rate = if actual < -1 then BRAKE else ACCEL * h.Accel * fade
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
	d.Heading -= d.Steer * TURN_RATE * factor * direction * dt
	look = Vector3.new(-math.sin(d.Heading), 0, -math.cos(d.Heading))
	local right = Vector3.new(-look.Z, 0, look.X)
	-- glisse latérale : ce qui reste de l'ancienne vitesse sur le côté
	local drifting = math.abs(d.Steer) > 0.6 and speed > maxSpeed * 0.62 and throttle > 0.3
	local grip = (if drifting then 3 else 10) * h.Grip
	local lateral = d.Vel:Dot(right) * math.exp(-grip * dt)
	if math.abs(lateral) < 0.05 then
		lateral = 0
	end
	local velocity = look * speed + right * lateral
	d.Vel = velocity
	d.Slip = math.abs(lateral)
	-- pas d'entrée dans les boutiques (sauf la concession) : remise en arrière
	local ahead = root.Position + velocity * 0.2
	if #shopZones > 0 and inZone(ahead) then
		velocity = Vector3.zero
		d.Speed = 0
		d.Vel = Vector3.zero
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
	-- fumée de dérapage (douce, locale)
	for _, smoke in ipairs(d.Smoke) do
		smoke.Enabled = d.Slip > 5
	end
	-- caméra : champ de vision un peu plus large en allant vite
	local camera = workspace.CurrentCamera
	if camera then
		local want = BASE_FOV + 12 * math.clamp(math.abs(actual) / maxSpeed, 0, 1)
		camera.FieldOfView += (want - camera.FieldOfView) * math.clamp(dt * 3, 0, 1)
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

-- (v9.7, VEHICLES97) bug "le bouton Conduire reste affiché quand je conduis" :
-- l'invite n'est active que sur SA voiture ET si personne n'est au volant
-- (siège occupé, attribut serveur "Occupied", ou c'est nous qui conduisons).
-- Le serveur ne touche jamais à Enabled (pas de conflit de réplication) :
-- le client recalcule à chaque changement + 4 fois par seconde (filet).
local drivePrompts: { [ProximityPrompt]: boolean } = setmetatable({} :: any, { __mode = "k" })

local function promptBusy(model: Instance?): boolean
	if not model then
		return false
	end
	if driving and driving.Model == model then
		return true
	end
	if model:GetAttribute("Occupied") == true then
		return true
	end
	local seat = model:FindFirstChild("DriverSeat", true)
	return seat ~= nil and seat:IsA("VehicleSeat") and seat.Occupant ~= nil
end

local function updatePrompt(prompt: ProximityPrompt)
	local model = prompt:FindFirstAncestorWhichIsA("Model")
	local mine = model ~= nil and model:GetAttribute("OwnerId") == LocalPlayer.UserId
	local enabled = mine and not promptBusy(model)
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

local carsFolder: Instance? = nil

local function fixPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompt.Name ~= "DrivePrompt" then
		return
	end
	local model = prompt:FindFirstAncestorWhichIsA("Model")
	local mine = model ~= nil and model:GetAttribute("OwnerId") == LocalPlayer.UserId
	if drivePrompts[prompt :: ProximityPrompt] then
		updatePrompt(prompt :: ProximityPrompt)
		return
	end
	drivePrompts[prompt :: ProximityPrompt] = true
	updatePrompt(prompt :: ProximityPrompt)
	if model and mine then
		track(model:GetAttributeChangedSignal("Occupied"):Connect(function()
			updatePrompt(prompt)
		end))
	end
	if mine then
		prompt.ActionText = Locale.T("Drive")
		local def = model and Config.CarsById[tostring(model:GetAttribute("CarId"))]
		if def then
			prompt.ObjectText = def.Icon .. " " .. Locale.T(def.Name)
		end
	end
end

-- (v9.7) recalcul : invites connues + invites des voitures du dossier (au cas
-- où DescendantAdded serait arrivé avant l'invite : quelques voitures au plus)
refreshPrompts = function()
	for prompt in pairs(drivePrompts) do
		if prompt.Parent then
			updatePrompt(prompt)
		else
			drivePrompts[prompt] = nil
		end
	end
	local folder = carsFolder
	if folder and folder.Parent then
		for _, model in ipairs(folder:GetChildren()) do
			local root = model:IsA("Model") and model.PrimaryPart
			local prompt = root and root:FindFirstChild("DrivePrompt")
			if prompt and not drivePrompts[prompt :: ProximityPrompt] then
				fixPrompt(prompt)
			end
		end
	end
end

local function watchCarsFolder(folder: Instance)
	carsFolder = folder
	for _, d in ipairs(folder:GetDescendants()) do
		fixPrompt(d)
	end
	-- (v9.7 : un modèle entier peut arriver d'un coup : on fouille aussi dedans)
	track(folder.DescendantAdded:Connect(function(d: Instance)
		fixPrompt(d)
		if d:IsA("Model") then
			for _, x in ipairs(d:GetDescendants()) do
				fixPrompt(x)
			end
		end
	end))
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
	local list = parseCars(text)
	-- (v9.8) seules les couleurs ont changé : on repeint, sans reconstruire
	local shape = {}
	for _, entry in ipairs(list) do
		table.insert(shape, entry.Id)
	end
	local shapeKey = table.concat(shape, ",") .. "|" .. tostring(selected) .. "|" .. tostring(out)
	if shapeKey == g.ShapeKey then
		g.Key = key
		for _, entry in ipairs(list) do
			local model = g.Cars:FindFirstChild("Parked_" .. entry.Id)
			if model then
				CarModels.Repaint(model, entry.Id, entry.Color)
			end
		end
		return
	end
	g.Key = key
	g.ShapeKey = shapeKey
	g.Cars:ClearAllChildren()
	local ids = {}
	for _, entry in ipairs(list) do
		table.insert(ids, entry.Id)
	end
	local bays = GarageLayout.Assign(ids, type(selected) == "string" and selected or nil)
	for _, entry in ipairs(list) do
		local bay = bays[entry.Id]
		if bay and not (out and entry.Id == selected) then
			-- (v9.9) mon garage : voitures détaillées ; celui des autres : "Mid"
			local detail = if g.OwnerId == LocalPlayer.UserId then "Full" else "Mid"
			local ok, model = pcall(CarModels.Build, entry.Id, entry.Color, { Detail = detail })
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
-- (v9.9, CARS99) Roues des voitures conduites : elles TOURNENT et BRAQUENT
-- (la mienne et celles des autres joueurs). CarService relie les pivots
-- "WheelSteer" / "WheelSpin" de CarModels par des Motor6D ; ici on règle
-- leur Transform (local à chaque client, jamais répliqué) : rotation =
-- vitesse / rayon, braquage = mon volant (ma voiture) ou déduit de la
-- vitesse de lacet (atan(empattement × lacet / vitesse)) pour les autres.
----------------------------------------------------------------------

type WheelAnim = {
	Root: BasePart,
	Steer: { [number]: Motor6D },
	Spin: { [number]: Motor6D },
	Front: { [number]: boolean },
	Angle: number,
	SteerNow: number,
	Radius: number,
	Base: number,
}
local wheelAnims: { [Model]: WheelAnim | false } = {}
local MAX_STEER = math.rad(30)
local WHEEL_RANGE = 220

local function wheelAnimOf(model: Model): WheelAnim?
	local cached = wheelAnims[model]
	if cached ~= nil then
		return cached or nil
	end
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local steer: { [number]: Motor6D } = {}
	local spin: { [number]: Motor6D } = {}
	local front: { [number]: boolean } = {}
	local found = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and (d.Name == "WheelSteer" or d.Name == "WheelSpin") then
			local p1 = d.Part1
			local index = p1 and p1:GetAttribute("Wheel")
			if type(index) == "number" then
				found = true
				if d.Name == "WheelSteer" then
					steer[index] = d
					front[index] = d.C0.Position.Z < 0
				else
					spin[index] = d
				end
			end
		end
	end
	if not found then
		-- (le modèle arrive peut-être en morceaux : on réessaiera)
		return nil
	end
	local positions = CarModels.WheelPositions(tostring(model:GetAttribute("CarId") or ""))
	local anim: WheelAnim = {
		Root = root,
		Steer = steer,
		Spin = spin,
		Front = front,
		Angle = 0,
		SteerNow = 0,
		Radius = math.max(0.3, tonumber(model:GetAttribute("WheelRadius")) or 1),
		Base = math.abs(positions[#positions].Z - positions[1].Z),
	}
	wheelAnims[model] = anim
	return anim
end

local function animateWheels(dt: number)
	local folder = carsFolder
	if not folder or not folder.Parent then
		return
	end
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local a = wheelAnimOf(model)
			if a and a.Root.Parent and (camPos == nil or (a.Root.Position - camPos).Magnitude < WHEEL_RANGE) then
				local look = a.Root.CFrame.LookVector
				local speed = a.Root.AssemblyLinearVelocity:Dot(look)
				if math.abs(speed) < 0.05 then
					speed = 0
				end
				a.Angle = (a.Angle + speed / a.Radius * dt) % (math.pi * 2)
				local target = a.SteerNow
				if driving and driving.Model == model then
					target = -(tonumber(driving.Steer) or 0) * MAX_STEER
				elseif math.abs(speed) > 1 then
					local yaw = a.Root.AssemblyAngularVelocity.Y
					target = math.clamp(math.atan(a.Base * yaw / speed), -MAX_STEER, MAX_STEER)
				end
				a.SteerNow += (target - a.SteerNow) * math.clamp(dt * 10, 0, 1)
				local steerCF = CFrame.Angles(0, a.SteerNow, 0)
				for index, motor in pairs(a.Steer) do
					motor.Transform = if a.Front[index] then steerCF else CFrame.identity
				end
				local spinCF = CFrame.Angles(-a.Angle, 0, 0)
				for _, motor in pairs(a.Spin) do
					motor.Transform = spinCF
				end
			end
		end
	end
	for model in pairs(wheelAnims) do
		if not model.Parent then
			wheelAnims[model] = nil
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
			refreshPicker()
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
		local okW, errW = pcall(animateWheels, dt)
		if not okW then
			warn("[CarClient] Roues : " .. tostring(errW))
		end
		if pickerOpen then
			local okP, errP = pcall(stepPreview, dt)
			if not okP then
				warn("[CarClient] Mes voitures : " .. tostring(errP))
			end
		end
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
			refreshPrompts() -- (v9.7) filet : siège occupé / libéré
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
	table.clear(drivePrompts)
	table.clear(wheelAnims)
	carsFolder = nil
	pickerOpen = false
	-- (v9.8) aperçus 3D de "Mes voitures"
	for _, model in pairs(picker.Models) do
		pcall(model.Destroy, model)
	end
	table.clear(picker.Models)
	table.clear(picker.Thumbs)
	table.clear(picker.Pending)
	table.clear(picker.Local)
	picker.Viewing = ""
	picker.Dragging = false
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
