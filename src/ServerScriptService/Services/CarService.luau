--[[
	CarService (ModuleScript)
	Emplacement : ServerScriptService > Services > CarService

	🚗 Voitures de Dopamine Town (v9.6, GARAGE96).
	  - Catalogue : Config.Cars (8 modèles de Shared/CarModels, prix étalés
	    sur la progression, verrous "visites à l'océan"). Achat à la
	    concession (TownShops / ShopUI de SHOPS96) ou n'importe où par le
	    remote "Car". Voitures gardées pour toujours (même après l'océan).
	  - 🏎️ Garage du manoir (Config.House.Garage) : aile de 3 places devant
	    le manoir (GarageLayout), construite par chaque client (HouseFacade),
	    voitures possédées garées dedans (CarClient). On peut acheter des
	    voitures SANS garage : elles y seront rangées le jour où on l'a.
	  - Conduite (en ville seulement) : "🚗 Ma voiture" fait apparaître SA
	    voiture choisie (côté SERVEUR : tout le monde la voit) à côté de soi,
	    ou dans son garage si on est devant, et nous assoit au volant.
	    Contrôle "physique légère" : boîte de collision surélevée (les
	    bordures passent dessous) + 4 boules invisibles aux roues (elles
	    montent les trottoirs), tout le reste soudé et sans masse ;
	    LinearVelocity (plan horizontal) + AlignOrientation (toujours à
	    plat, cap voulu) pilotés par le CLIENT du conducteur, propriétaire
	    réseau de la voiture (CarClient lit VehicleSeat.ThrottleFloat /
	    SteerFloat : clavier ZQSD / WASD / flèches, joystick mobile, manette).
	    Garée (personne au volant) = ancrée : elle ne bouge jamais.
	  - Sécurité : groupes de collision (voitures <-> avatars : AUCUNE
	    collision, donc ni mort ni projection ; voitures <-> voitures non
	    plus) ; ronde 4 fois / s : voiture tombée, retournée, trop rapide,
	    entrée dans une maison (WorldLayout.InsideHouse) ou une boutique
	    (attributs InteriorCF / InteriorSize, sauf AllowCars) -> remise à sa
	    dernière position sûre ; rangée au bout de Config.Cars.IdleDespawn s
	    sans conducteur, ou si son propriétaire quitte la ville / le jeu.
	  - Klaxon VISUEL "💨" (bulle au-dessus de la voiture) : aucun son.
	  - Attributs du Player (répliqués, lus par CarClient pour les garages) :
	    DopamineCars = "id:couleur,..." (voitures possédées), DopamineCar =
	    voiture choisie, DopamineGarage = garage (et manoir), DopamineCarOut =
	    voiture sortie.

	Données : data.Cars = { Owned = { [carId] = true }, Colors = { [carId] =
	colorId }, Selected = carId | "", Garage = bool }.
	RemoteFunction "Car" (action, a, b) -> (succès, message, extra?) :
	  "buy" carId -> extra = Dopamine manquante (nombre) si trop cher
	  "setColor" carId, colorId | "select" carId | "buyGarage"
	  "spawn" | "exit" | "despawn" | "honk" | "reset"
	Tout est dans des pcall, chaque action a sa limite de fréquence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local CarModels = require(ReplicatedStorage.Shared.CarModels)
local GarageLayout = require(ReplicatedStorage.Shared.GarageLayout)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local RateLimiter = require(script.Parent.RateLimiter)

local CarService = {}

CarService.CAR_GROUP = "DopamineCars"
CarService.WALKER_GROUP = "DopamineWalkers"
CarService.FOLDER_NAME = "DopamineCars"

local PATROL_INTERVAL = 0.25
local MAX_SPEED_CLAMP = 110 -- studs/s : au-delà, c'est un bug physique -> on arrête tout
local SPAWN_RANGE_GARAGE = 45 -- studs : "🚗 Ma voiture" près de son garage -> sortie du garage

type Car = {
	Player: Player,
	Model: Model,
	Root: BasePart,
	Seat: VehicleSeat,
	CarId: string,
	Driving: boolean,
	LastUsed: number,
	LastSafe: CFrame,
	Generation: number,
}

local services: any = nil
local cars: { [Player]: Car } = {}
local folder: Folder? = nil
local generation = 0

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function T(player: Player, text: string, ...): string
	if services and services.GameService then
		return services.GameService:T(player, text, ...)
	end
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
end

local function isValidNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function dataOf(player: Player): any
	return services and services.DataService and services.DataService:GetData(player) or nil
end

-- data.Cars propre (sauvegarde abîmée corrigée, ids inconnus retirés)
function CarService.Sanitize(data: any)
	if type(data) ~= "table" then
		return
	end
	local raw = type(data.Cars) == "table" and data.Cars or {}
	local owned, colors = {}, {}
	if type(raw.Owned) == "table" then
		for id, value in pairs(raw.Owned) do
			if value == true and type(id) == "string" and Config.CarsById[id] then
				owned[id] = true
			end
		end
	end
	if type(raw.Colors) == "table" then
		for id, colorId in pairs(raw.Colors) do
			if owned[id] and type(colorId) == "string" and Config.CarColorsById[colorId] then
				colors[id] = colorId
			end
		end
	end
	local selected = type(raw.Selected) == "string" and owned[raw.Selected] and raw.Selected or ""
	if selected == "" then
		for _, car in ipairs(Config.Cars.List) do
			if owned[car.Id] then
				selected = car.Id
			end
		end
	end
	data.Cars = { Owned = owned, Colors = colors, Selected = selected, Garage = raw.Garage == true }
end

local function ownedList(data: any): { string }
	local list = {}
	local cars_ = data and data.Cars
	for _, car in ipairs(Config.Cars.List) do
		if cars_ and cars_.Owned and cars_.Owned[car.Id] then
			table.insert(list, car.Id)
		end
	end
	return list
end

local function colorOf(data: any, carId: string): string
	local colors = data and data.Cars and data.Cars.Colors
	local colorId = colors and colors[carId]
	if type(colorId) == "string" and Config.CarColorsById[colorId] then
		return colorId
	end
	local car = Config.CarsById[carId]
	return car and car.DefaultColor or "Bubblegum"
end

-- Le garage est visible : acheté ET on habite le manoir
local function hasGarage(data: any): boolean
	if type(data) ~= "table" or type(data.Cars) ~= "table" or data.Cars.Garage ~= true then
		return false
	end
	local house = data.House
	local size = house and Config.HouseSizesById[house.Size]
	return GarageLayout.Supports(size)
end

-- Attributs répliqués du Player (garages des autres clients)
local function publish(player: Player)
	local data = dataOf(player)
	if not data then
		return
	end
	local parts = {}
	for _, id in ipairs(ownedList(data)) do
		table.insert(parts, id .. ":" .. colorOf(data, id))
	end
	pcall(function()
		player:SetAttribute("DopamineCars", table.concat(parts, ","))
		player:SetAttribute("DopamineCar", data.Cars and data.Cars.Selected or "")
		player:SetAttribute("DopamineGarage", hasGarage(data))
		player:SetAttribute("DopamineCarOut", cars[player] ~= nil)
	end)
end

local function toast(player: Player, text: string)
	pcall(function()
		Net.Event("WorldEvent"):FireClient(player, "Toast", text)
	end)
end

local function sendState(player: Player)
	if services and services.GameService then
		services.GameService:SendState(player)
	end
end

----------------------------------------------------------------------
-- Ville : maisons, boutiques, parcelles (zones interdites aux voitures)
----------------------------------------------------------------------

local function townFolder(): Instance?
	return workspace:FindFirstChild("DopamineTown")
end

-- { { HouseCF, Size, OwnerId } } des parcelles habitées
local function houses(): { { HouseCF: CFrame, Size: any, OwnerId: number } }
	local out = {}
	local town = townFolder()
	local plots = town and town:FindFirstChild("Plots")
	if not plots then
		return out
	end
	local list = plots:GetChildren()
	local count = #list
	for _, plot in ipairs(list) do
		local index = tonumber(plot:GetAttribute("Index"))
		local ownerId = tonumber(plot:GetAttribute("OwnerId")) or 0
		if index and ownerId ~= 0 then
			local owner = Players:GetPlayerByUserId(ownerId)
			local data = owner and dataOf(owner)
			local size = data and data.House and Config.HouseSizesById[data.House.Size] or Config.House.Sizes[1]
			table.insert(out, { HouseCF = WorldLayout.HouseCFrame(WorldLayout.PlotCFrame(index, count)), Size = size, OwnerId = ownerId })
		end
	end
	return out
end

local function houseOf(player: Player): (CFrame?, any)
	for _, h in ipairs(houses()) do
		if h.OwnerId == player.UserId then
			return h.HouseCF, h.Size
		end
	end
	return nil, nil
end

-- Point dans une zone interdite (maison, boutique fermée aux voitures) ?
local function forbidden(position: Vector3, zones: { { HouseCF: CFrame, Size: any, OwnerId: number } }?): boolean
	for _, h in ipairs(zones or houses()) do
		local x, y, d = WorldLayout.ToLocal(h.HouseCF, position)
		if WorldLayout.InsideHouse(h.Size, x, y, d, 0.3) then
			return true
		end
	end
	local town = townFolder()
	local shops = town and town:FindFirstChild("Shops")
	if shops then
		for _, shop in ipairs(shops:GetChildren()) do
			local cf = shop:GetAttribute("InteriorCF")
			local size = shop:GetAttribute("InteriorSize")
			if typeof(cf) == "CFrame" and typeof(size) == "Vector3" and shop:GetAttribute("AllowCars") ~= true then
				local p = cf:PointToObjectSpace(position)
				if math.abs(p.X) <= size.X / 2 + 0.5 and math.abs(p.Z) <= size.Z / 2 + 0.5 and p.Y >= -2 and p.Y <= size.Y + 1 then
					return true
				end
			end
		end
	end
	return false
end
CarService.IsForbidden = forbidden

----------------------------------------------------------------------
-- Groupes de collision : voitures <-> avatars = jamais
----------------------------------------------------------------------

local function setupGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CarService.CAR_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CarService.WALKER_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(CarService.CAR_GROUP, CarService.WALKER_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(CarService.CAR_GROUP, CarService.CAR_GROUP, false)
	end)
end

local function tagWalker(part: Instance)
	if part:IsA("BasePart") then
		pcall(function()
			part.CollisionGroup = CarService.WALKER_GROUP
		end)
	end
end

local function watchCharacter(character: Model)
	for _, d in ipairs(character:GetDescendants()) do
		tagWalker(d)
	end
	character.DescendantAdded:Connect(tagWalker)
end

----------------------------------------------------------------------
-- La voiture qu'on conduit
----------------------------------------------------------------------

local function characterOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function flatten(cf: CFrame): CFrame
	local look = cf.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(cf.Position, cf.Position + look.Unit)
end

local function despawn(player: Player, silent: boolean?)
	local car = cars[player]
	if not car then
		return
	end
	cars[player] = nil
	pcall(function()
		local weld = car.Seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end)
	pcall(car.Model.Destroy, car.Model)
	if not silent and player.Parent then
		toast(player, T(player, "🚗 Your car went back to the garage"))
	end
	publish(player)
end

-- Transforme le modèle ancré de CarModels en voiture qu'on conduit
local function rig(model: Model, carId: string): (BasePart, VehicleSeat)
	local root = model.PrimaryPart :: BasePart
	local pivot = model:GetPivot()
	local noFriction = PhysicalProperties.new(0.7, 0, 0, 100, 100)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			d.Massless = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
			d.Anchored = false
		end
	end
	root.CanCollide = true
	root.CanTouch = false
	root.CustomPhysicalProperties = noFriction
	root.CollisionGroup = CarService.CAR_GROUP
	-- boules de contact aux roues (invisibles) : montent les bordures
	local wheelRadius = tonumber(model:GetAttribute("WheelRadius")) or 1
	for index, position in ipairs(CarModels.WheelPositions(carId)) do
		local ball = Instance.new("Part")
		ball.Name = "Contact" .. index
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(wheelRadius * 2, wheelRadius * 2, wheelRadius * 2)
		ball.CFrame = pivot * CFrame.new(position.X * 0.8, wheelRadius, position.Z)
		ball.Transparency = 1
		ball.CanCollide = true
		ball.CanTouch = false
		ball.CanQuery = false
		ball.CastShadow = false
		ball.CustomPhysicalProperties = noFriction
		ball.CollisionGroup = CarService.CAR_GROUP
		ball.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = ball
		weld.Parent = ball
		ball.Parent = model
	end
	-- siège du conducteur (invisible ; on s'y assoit par l'invite ou le bouton)
	local seatCF = model:GetAttribute("SeatCF")
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(1.6, 0.3, 1.6)
	seat.CFrame = pivot * (typeof(seatCF) == "CFrame" and seatCF or CFrame.new(0, 2, 0)) * CFrame.new(0, -0.15, 0)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat.Massless = true
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.HeadsUpDisplay = false
	seat.Anchored = false
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = root
	seatWeld.Part1 = seat
	seatWeld.Parent = seat
	seat.Parent = model
	-- contrôleurs (réglés chaque image par le client du conducteur)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Drive"
	attachment.Parent = root
	local mass = root:GetMass()
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name:sub(1, 7) == "Contact" then
			mass += d:GetMass()
		end
	end
	local drive = Instance.new("LinearVelocity")
	drive.Name = "DriveVelocity"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	drive.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	drive.PlaneVelocity = Vector2.new(0, 0)
	drive.MaxForce = math.max(1000, mass * 140)
	drive.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "DriveAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.MaxTorque = math.max(1e5, mass * 4000)
	align.MaxAngularVelocity = 8
	align.Responsiveness = 30
	align.CFrame = flatten(pivot).Rotation
	align.Parent = root
	model:SetAttribute("Mass", mass)
	root.Anchored = true
	return root, seat
end

-- Une place libre au sol près de `origin` (sinon `origin` lui-même)
local function findSpot(origin: CFrame, size: Vector3, ignore: { Instance }): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local look = flatten(origin)
	local candidates = { look * CFrame.new(size.X / 2 + 4, 0, 0), look * CFrame.new(-size.X / 2 - 4, 0, 0), look * CFrame.new(0, 0, size.Z / 2 + 4), look }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	overlap.RespectCanCollide = true
	local zones = houses()
	for index, cf in ipairs(candidates) do
		local from = cf.Position + Vector3.new(0, 6, 0)
		local hit = workspace:Raycast(from, Vector3.new(0, -20, 0), params)
		if hit then
			local ground = CFrame.new(Vector3.new(cf.X, hit.Position.Y + 0.05, cf.Z)) * look.Rotation
			local free = true
			if index < #candidates then
				local okBox, parts = pcall(function()
					return workspace:GetPartBoundsInBox(ground * CFrame.new(0, size.Y / 2 + 0.7, 0), size - Vector3.new(0.4, 1.2, 0.4), overlap)
				end)
				free = okBox and #parts == 0 and not forbidden(ground.Position + Vector3.new(0, 1, 0), zones)
			end
			if free then
				return ground
			end
		end
	end
	return look * CFrame.new(0, -3, 0)
end

local function sit(player: Player, car: Car): boolean
	local _, humanoid = characterOf(player)
	if not humanoid then
		return false
	end
	if car.Seat.Occupant ~= nil then
		return car.Seat.Occupant == humanoid
	end
	local ok = pcall(function()
		car.Seat:Sit(humanoid)
	end)
	return ok
end

local function onOccupant(car: Car)
	local occupant = car.Seat.Occupant
	if occupant then
		local who = Players:GetPlayerFromCharacter(occupant.Parent)
		if who ~= car.Player then
			-- (seul le propriétaire conduit)
			pcall(function()
				local weld = car.Seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
			end)
			return
		end
		car.Driving = true
		car.LastUsed = os.clock()
		car.Root.Anchored = false
		pcall(function()
			car.Root:SetNetworkOwner(car.Player)
		end)
	else
		car.Driving = false
		car.LastUsed = os.clock()
		local gen = car.Generation
		task.delay(0.8, function()
			if cars[car.Player] == car and car.Generation == gen and car.Seat.Occupant == nil and car.Root.Parent then
				pcall(function()
					car.Root.AssemblyLinearVelocity = Vector3.zero
					car.Root.AssemblyAngularVelocity = Vector3.zero
					car.Root.CFrame = flatten(car.Root.CFrame)
					car.Root.Anchored = true
				end)
			end
		end)
	end
end

local function plateText(player: Player): string
	return string.format("DC %03d", player.UserId % 1000)
end

local function spawnCar(player: Player, data: any): (boolean, string)
	local character, _, charRoot = characterOf(player)
	if not character or not charRoot then
		return false, T(player, "Walk around the town first")
	end
	local carId = data.Cars.Selected
	if carId == "" or not data.Cars.Owned[carId] then
		return false, T(player, "🚗 Buy a car at the car dealership first!")
	end
	local zones = houses()
	if forbidden(charRoot.Position, zones) then
		return false, T(player, "🚫 Go outside to take your car")
	end
	despawn(player, true)
	local model = CarModels.Build(carId, colorOf(data, carId), { Detail = "Full", Plate = plateText(player) })
	model.Name = "Car_" .. player.UserId
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	-- où ? dans son garage si on est devant, sinon à côté de soi
	local target: CFrame? = nil
	local houseCF = houseOf(player)
	if houseCF and hasGarage(data) and (GarageLayout.Center(houseCF) - charRoot.Position).Magnitude < SPAWN_RANGE_GARAGE then
		local bays = GarageLayout.Assign(ownedList(data), carId)
		target = GarageLayout.BayCFrame(houseCF, bays[carId] or 2)
		model:SetAttribute("FromGarage", true)
	end
	if not target then
		local size = CarModels.Dimensions(carId)
		local ignore: { Instance } = { character }
		for _, other in pairs(cars) do
			table.insert(ignore, other.Model)
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		target = findSpot(charRoot.CFrame, size, ignore)
	end
	model:PivotTo(target :: CFrame)
	local root, seat = rig(model, carId)
	generation += 1
	local car: Car = {
		Player = player,
		Model = model,
		Root = root,
		Seat = seat,
		CarId = carId,
		Driving = false,
		LastUsed = os.clock(),
		LastSafe = root.CFrame,
		Generation = generation,
	}
	cars[player] = car
	-- invite "Conduire" (le client la traduit et la cache aux autres joueurs)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = tostring((Config.CarsById[carId] or {}).Name or carId)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(who: Player)
		if who == player and cars[player] == car then
			sit(player, car)
		elseif who ~= player then
			toast(who, T(who, "🔒 This is %s's car", player.DisplayName))
		end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupant(car)
	end)
	local f = folder
	if not f or not f.Parent then
		local newFolder = Instance.new("Folder")
		newFolder.Name = CarService.FOLDER_NAME
		newFolder.Parent = workspace
		folder = newFolder
		f = newFolder
	end
	model.Parent = f
	publish(player)
	sit(player, car)
	local def = Config.CarsById[carId]
	return true, T(player, "%s Let's drive! WASD / arrows, jump to get out", def and def.Icon or "🚗")
end

local function honk(player: Player): (boolean, string)
	local car = cars[player]
	if not car then
		return false, T(player, "Invalid request")
	end
	local old = car.Root:FindFirstChild("Honk")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Honk"
	gui.Size = UDim2.fromOffset(150, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (tonumber(car.Model:GetAttribute("Height")) or 5) + 1.5, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(236, 72, 140)
	label.Text = "💨 Tut-tut !"
	label.Parent = gui
	gui.Parent = car.Root
	task.delay(1.6, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
	return true, ""
end

local function reset(player: Player): (boolean, string)
	local car = cars[player]
	if not car then
		return false, T(player, "Invalid request")
	end
	pcall(function()
		car.Root.AssemblyLinearVelocity = Vector3.zero
		car.Root.AssemblyAngularVelocity = Vector3.zero
		car.Root.CFrame = flatten(car.LastSafe) + Vector3.new(0, 2, 0)
	end)
	return true, T(player, "🔄 Back on its wheels!")
end

----------------------------------------------------------------------
-- Achats
----------------------------------------------------------------------

local function buy(player: Player, data: any, carId: any): (boolean, string, number?)
	local car = type(carId) == "string" and Config.CarsById[carId] or nil
	if not car then
		return false, T(player, "Invalid request")
	end
	if data.Cars.Owned[car.Id] then
		return false, T(player, "You already own this car")
	end
	local lock = (tonumber(car.RequiresRebirths) or 0) > (tonumber(data.Rebirths) or 0)
	if lock then
		return false, T(player, "🔒 Unlocked after %d visits to the ocean", tonumber(car.RequiresRebirths) or 0)
	end
	local cost = car.Cost
	if not isValidNumber(cost) or cost < 0 then
		return false, T(player, "Invalid request")
	end
	if not isValidNumber(data.Dopamine) or data.Dopamine < cost then
		local missing = math.max(0, cost - (isValidNumber(data.Dopamine) and data.Dopamine or 0))
		return false, T(player, "Not enough %s", Config.Game.CurrencyName), missing
	end
	data.Dopamine -= cost
	data.Cars.Owned[car.Id] = true
	data.Cars.Colors[car.Id] = data.Cars.Colors[car.Id] or car.DefaultColor
	data.Cars.Selected = car.Id
	sendState(player)
	publish(player)
	return true, T(player, "%s %s is yours! Drive it in Dopamine Town (%s)", car.Icon, T(player, car.Name), NumberFormatter.Format(cost))
end

local function buyGarage(player: Player, data: any): (boolean, string, number?)
	local garage = Config.House.Garage
	if data.Cars.Garage then
		return false, T(player, "You already have a garage")
	end
	if (tonumber(data.Rebirths) or 0) < (tonumber(garage.RequiresRebirths) or 0) then
		return false, T(player, "🔒 Unlocked after %d visits to the ocean", tonumber(garage.RequiresRebirths) or 0)
	end
	local house = data.House
	if not (house and house.OwnedSizes and house.OwnedSizes[garage.RequiresSize]) then
		local size = Config.HouseSizesById[garage.RequiresSize]
		return false, T(player, "🏰 You need the %s first", T(player, size and size.Name or tostring(garage.RequiresSize)))
	end
	local cost = garage.Cost
	if not isValidNumber(data.Dopamine) or data.Dopamine < cost then
		local missing = math.max(0, cost - (isValidNumber(data.Dopamine) and data.Dopamine or 0))
		return false, T(player, "Not enough %s", Config.Game.CurrencyName), missing
	end
	data.Dopamine -= cost
	data.Cars.Garage = true
	sendState(player)
	publish(player)
	return true, T(player, "%s Your garage is built! Your cars are parked inside", garage.Icon)
end

local function setColor(player: Player, data: any, carId: any, colorId: any): (boolean, string)
	if type(carId) ~= "string" or not data.Cars.Owned[carId] or type(colorId) ~= "string" or not Config.CarColorsById[colorId] then
		return false, T(player, "Invalid request")
	end
	data.Cars.Colors[carId] = colorId
	sendState(player)
	publish(player)
	-- voiture sortie et libre : repeinte tout de suite (on la refait au même endroit)
	local car = cars[player]
	if car and car.CarId == carId and not car.Driving then
		local cf = car.Root.CFrame
		local paint = Config.CarColorsById[colorId].Color
		for _, d in ipairs(car.Model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("Paint") then
				d.Color = paint
			end
		end
		car.Root.CFrame = cf
	end
	local paint = Config.CarColorsById[colorId]
	return true, T(player, "🎨 %s applied", T(player, paint.Name))
end

local function select_(player: Player, data: any, carId: any): (boolean, string)
	if type(carId) ~= "string" or not data.Cars.Owned[carId] then
		return false, T(player, "Invalid request")
	end
	data.Cars.Selected = carId
	sendState(player)
	publish(player)
	local car = Config.CarsById[carId]
	return true, T(player, "%s %s selected", car.Icon, T(player, car.Name))
end

----------------------------------------------------------------------
-- Remote
----------------------------------------------------------------------

local INTERVALS = { buy = 0.4, buyGarage = 0.4, setColor = 0.25, select = 0.25, exit = 0.3, despawn = 0.5, reset = 2 }

local function onCar(player: Player, action: any, a: any, b: any): (boolean, string, any?)
	if type(action) ~= "string" or #action > 24 then
		return false, T(player, "Invalid request")
	end
	local interval = INTERVALS[action]
	if action == "spawn" then
		interval = Config.Cars.SpawnCooldown
	elseif action == "honk" then
		interval = Config.Cars.HonkCooldown
	end
	if not interval then
		return false, T(player, "Invalid request")
	end
	if not RateLimiter.Check(player, "Car_" .. action, interval) then
		if action == "honk" then
			return false, ""
		end
		return false, T(player, "Slow down!")
	end
	local data = dataOf(player)
	if not data or (services.GameService.IsReady and not services.GameService:IsReady(player)) then
		return false, T(player, "Loading...")
	end
	CarService.Sanitize(data)
	if action == "buy" then
		return buy(player, data, a)
	elseif action == "buyGarage" then
		return buyGarage(player, data)
	elseif action == "setColor" then
		return setColor(player, data, a, b)
	elseif action == "select" then
		return select_(player, data, a)
	end
	-- en ville seulement
	local world = services.WorldService
	if world and world.IsInTown and not world:IsInTown(player) then
		return false, T(player, "Walk around the town first")
	end
	if action == "spawn" then
		return spawnCar(player, data)
	elseif action == "exit" then
		local car = cars[player]
		if car then
			pcall(function()
				local weld = car.Seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
			end)
		end
		return true, ""
	elseif action == "despawn" then
		despawn(player, true)
		return true, ""
	elseif action == "honk" then
		return honk(player)
	elseif action == "reset" then
		return reset(player)
	end
	return false, T(player, "Invalid request")
end

----------------------------------------------------------------------
-- Ronde : sécurité, rangement
----------------------------------------------------------------------

local function patrol()
	if next(cars) == nil then
		return
	end
	local zones = houses()
	local floorY = WorldLayout.Origin().Y - 30
	local world = services and services.WorldService
	for player, car in pairs(cars) do
		local root = car.Root
		if not root.Parent or not player.Parent then
			despawn(player, true)
		elseif world and world.IsInTown and not world:IsInTown(player) then
			despawn(player, true)
		elseif not car.Driving and os.clock() - car.LastUsed > Config.Cars.IdleDespawn then
			despawn(player, false)
		elseif car.Driving then
			local cf = root.CFrame
			local bad = cf.Position.Y < floorY or cf.UpVector.Y < 0.3 or forbidden(cf.Position, zones)
			local speed = root.AssemblyLinearVelocity.Magnitude
			if bad or speed > MAX_SPEED_CLAMP then
				pcall(function()
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					if bad then
						root.CFrame = flatten(car.LastSafe)
					end
				end)
				if bad and cf.Position.Y >= floorY and cf.UpVector.Y >= 0.3 then
					toast(player, T(player, "🚫 No cars inside!"))
				end
			else
				car.LastSafe = cf
				car.LastUsed = os.clock()
			end
		end
	end
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function CarService:Init(allServices)
	services = allServices
end

function CarService:Start()
	setupGroups()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Net.Function("Car").OnServerInvoke = function(player: Player, action: any, a: any, b: any)
		local ok, success, message, extra = pcall(onCar, player, action, a, b)
		if not ok then
			warn("[CarService] Erreur pour " .. player.Name .. " :", success)
			return false, T(player, "Invalid request")
		end
		return success, message, extra
	end
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock >= PATROL_INTERVAL then
			clock = 0
			local ok, err = pcall(patrol)
			if not ok then
				warn("[CarService] Ronde : " .. tostring(err))
			end
		end
	end)
end

function CarService:PlayerReady(player: Player, data)
	CarService.Sanitize(data)
	publish(player)
end

function CarService:PlayerRemoving(player: Player)
	despawn(player, true)
end

-- État client (GameService.BuildState) : ClientState.Data.Cars
function CarService:GetClientState(_player: Player, data)
	if type(data) ~= "table" then
		return nil
	end
	if type(data.Cars) ~= "table" then
		CarService.Sanitize(data)
	end
	return { Cars = data.Cars }
end

-- (WorldService, instantané de la maison) garage visible ? (aile du manoir)
function CarService:GarageSnapshot(player: Player): boolean
	return hasGarage(dataOf(player))
end

-- (tests / autres services) la voiture sortie d'un joueur
function CarService:GetCar(player: Player): Model?
	local car = cars[player]
	return car and car.Model or nil
end

return CarService
