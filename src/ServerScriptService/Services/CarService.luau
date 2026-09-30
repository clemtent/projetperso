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
	  - Sécurité : groupes de collision (v10, PHYS10 : voitures <-> avatars
	    et voitures <-> voitures = collision ; renversé façon dessin animé,
	    jamais de mort : ImpactService) ; ronde 4 fois / s : voiture tombée, retournée, trop rapide,
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
	colorId }, Selected = carId | "", Garage = bool,
	(v10, CARS10) Tuning = { [carId] = { Engine, Tyres, Suspension } (0..3) },
	Mods = { [carId] = { [Kind] = Id } } (Config.Cars.Mods, sans l'origine),
	Unlocked = { [carId] = { ["Kind:Id"] = true } } (options achetées),
	Plates = { [carId] = "TEXTE" } (filtré par TextService) }.
	RemoteFunction "Car" (action, a, b) -> (succès, message, extra?) :
	  "buy" carId -> extra = Dopamine manquante (nombre) si trop cher
	  "setColor" carId, colorId | "select" carId | "buyGarage"
	  (v10) "setMod" carId, "Kind:Id" | "tune" carId, partId | "plate" carId, texte
	    (achat vérifié : prix = CarModels.PriceFor, verrous, extra = manque)
	  "spawn" | "exit" | "despawn" | "honk" | "reset"
	Attribut (v10) DopamineCarMods = "carId>Kind=Id;Kind=Id/carId2>..." (garages).
	Courses (v10, RACE10) : CarService:RaceSpawn / RaceRelease / SetFrozen /
	GetStats (voir en bas).
	Tout est dans des pcall, chaque action a sa limite de fréquence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local TextService = game:GetService("TextService")

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
	Frozen: boolean, -- (v10) départ de course : ancrée pendant le compte à rebours
	Loaner: boolean, -- (v10) voiture de prêt des courses (pas possédée)
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
	-- (v10, CARS10) atelier : préparation, options, achats, plaques (par voiture possédée)
	local tuning, mods, unlocked, plates = {}, {}, {}, {}
	local maxPlate = tonumber(Config.Cars.PlateMaxLength) or 8
	for id in pairs(owned) do
		local t = type(raw.Tuning) == "table" and raw.Tuning[id]
		if type(t) == "table" then
			local clean = CarModels.CleanTuning(t)
			if clean.Engine + clean.Tyres + clean.Suspension > 0 then
				tuning[id] = clean
			end
		end
		local m = type(raw.Mods) == "table" and raw.Mods[id]
		if type(m) == "table" then
			local clean = CarModels.CleanMods(m)
			if next(clean) ~= nil then
				mods[id] = clean
			end
		end
		local u = type(raw.Unlocked) == "table" and raw.Unlocked[id]
		if type(u) == "table" then
			local set = {}
			for key, value in pairs(u) do
				local kind, entryId = nil, nil
				if type(key) == "string" then
					kind, entryId = string.match(key, "^(%w+):(%w+)$")
				end
				if value == true and kind and entryId and Config.CarModsById[kind] and Config.CarModsById[kind][entryId] then
					set[key] = true
				end
			end
			if next(set) ~= nil then
				unlocked[id] = set
			end
		end
		local plate = type(raw.Plates) == "table" and raw.Plates[id]
		if type(plate) == "string" and plate ~= "" and #plate <= maxPlate * 4 then
			plates[id] = plate
		end
	end
	data.Cars = { Owned = owned, Colors = colors, Selected = selected, Garage = raw.Garage == true, Tuning = tuning, Mods = mods, Unlocked = unlocked, Plates = plates }
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
	local modParts = {}
	for _, id in ipairs(ownedList(data)) do
		table.insert(parts, id .. ":" .. colorOf(data, id))
		-- (v10) options de chaque voiture (garages vus par les autres clients)
		local encoded = CarModels.EncodeMods(data.Cars.Mods and data.Cars.Mods[id])
		if encoded ~= "" then
			table.insert(modParts, id .. ">" .. encoded)
		end
	end
	pcall(function()
		player:SetAttribute("DopamineCarMods", table.concat(modParts, "/"))
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
-- Groupes de collision (v10, PHYS10) : voitures <-> avatars = OUI, voitures
-- <-> voitures = OUI (on ne traverse plus rien ; se faire renverser :
-- ImpactService). Matrice complète : Shared/ImpactRules.MATRIX.
----------------------------------------------------------------------

local function setupGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CarService.CAR_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CarService.WALKER_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(CarService.CAR_GROUP, CarService.WALKER_GROUP, true)
		PhysicsService:CollisionGroupSetCollidable(CarService.CAR_GROUP, CarService.CAR_GROUP, true)
	end)
end

local function tagWalker(part: Instance)
	-- (v10) KeepGroup : boîtes du ragdoll (groupe "Ragdoll", ImpactRules)
	if part:IsA("BasePart") and part:GetAttribute("KeepGroup") ~= true then
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
	-- (v9.9, CARS99) roues animables : pivots "WheelSteer" (braquage) et
	-- "WheelSpin" (rotation) reliés par des Motor6D ; chaque client règle
	-- leur Transform (CarClient). Les autres pièces des roues sont soudées à
	-- leur pivot, le reste de la carrosserie à la boîte Root.
	local steers: { [number]: BasePart } = {}
	local spins: { [number]: BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and type(d:GetAttribute("Wheel")) == "number" then
			if d.Name == "WheelSteer" then
				steers[d:GetAttribute("Wheel") :: number] = d
			elseif d.Name == "WheelSpin" then
				spins[d:GetAttribute("Wheel") :: number] = d
			end
		end
	end
	for index, steer in pairs(steers) do
		local spin = spins[index]
		if spin then
			local m1 = Instance.new("Motor6D")
			m1.Name = "WheelSteer"
			m1.Part0 = root
			m1.Part1 = steer
			m1.C0 = root.CFrame:ToObjectSpace(steer.CFrame)
			m1.Parent = steer
			local m2 = Instance.new("Motor6D")
			m2.Name = "WheelSpin"
			m2.Part0 = steer
			m2.Part1 = spin
			m2.C0 = steer.CFrame:ToObjectSpace(spin.CFrame)
			m2.Parent = spin
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			d.Massless = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			local wheelIndex = d:GetAttribute("Wheel")
			local hub: BasePart? = nil
			if type(wheelIndex) == "number" and steers[wheelIndex] and spins[wheelIndex] then
				hub = if d:GetAttribute("Spin") then spins[wheelIndex] else steers[wheelIndex]
			end
			if d.Name == "WheelSteer" or d.Name == "WheelSpin" then
				if not (hub and spins[wheelIndex :: number]) then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = d
					weld.Parent = d
				end
			elseif hub and hub ~= d then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hub
				weld.Part1 = d
				weld.Parent = d
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = d
				weld.Parent = d
			end
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
		-- (v9.7) le client cache l'invite "Conduire" tant que quelqu'un est au volant
		car.Model:SetAttribute("Occupied", true)
		-- (v10) départ de course : reste ancrée tant que RACE10 la bloque
		if not car.Frozen then
			car.Root.Anchored = false
			pcall(function()
				car.Root:SetNetworkOwner(car.Player)
			end)
		end
	else
		car.Driving = false
		car.LastUsed = os.clock()
		car.Model:SetAttribute("Occupied", false)
		pcall(function()
			local drive = car.Root:FindFirstChild("DriveVelocity") :: LinearVelocity?
			if drive then
				drive.PlaneVelocity = Vector2.new(0, 0)
			end
			local align = car.Root:FindFirstChild("DriveAlign") :: AlignOrientation?
			if align then
				align.CFrame = flatten(car.Root.CFrame).Rotation
			end
		end)
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

-- (v10, CARS10) plaque personnalisée (déjà filtrée à l'enregistrement) ou "DC 123"
local function plateOf(player: Player, data: any, carId: string): string
	local plates = data and data.Cars and data.Cars.Plates
	local text = type(plates) == "table" and plates[carId]
	if type(text) == "string" and text ~= "" then
		return text
	end
	return plateText(player)
end

-- Options de CarModels.Build pour la voiture d'un joueur (peinture, options, plaque)
local function buildOptions(player: Player, data: any, carId: string): any
	local mods = data and data.Cars and data.Cars.Mods
	return { Detail = "Full", Plate = plateOf(player, data, carId), Mods = type(mods) == "table" and mods[carId] or nil }
end

-- Construit, équipe et enregistre la voiture d'un joueur à `target`
-- (commun à "🚗 Ma voiture" et aux courses de RACE10)
local function makeCar(player: Player, data: any, carId: string, target: CFrame, loaner: boolean, fromGarage: boolean): Car
	despawn(player, true)
	local opts = if loaner then { Detail = "Full", Plate = "LOAN " .. tostring(player.UserId % 100) } else buildOptions(player, data, carId)
	local model = CarModels.Build(carId, if loaner then nil else colorOf(data, carId), opts)
	model.Name = "Car_" .. player.UserId
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	if fromGarage then
		model:SetAttribute("FromGarage", true)
	end
	if loaner then
		model:SetAttribute("Loaner", true)
	end
	-- (v10) performances (RACE10 : plausibilité de la vitesse, affichage)
	local stats = CarModels.Stats(carId, if loaner then nil else CarModels.TuningOf(data, carId))
	model:SetAttribute("TopSpeed", stats.TopSpeed)
	model:SetAttribute("Rating", stats.Rating)
	model:SetAttribute("Class", stats.Class)
	model:SetAttribute("Tuning", string.format("%d%d%d", stats.Tuning.Engine, stats.Tuning.Tyres, stats.Tuning.Suspension))
	model:PivotTo(target)
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
		Frozen = false,
		Loaner = loaner,
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
	return car
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
	-- où ? dans son garage si on est devant, sinon à côté de soi
	local target: CFrame? = nil
	local fromGarage = false
	local houseCF = houseOf(player)
	if houseCF and hasGarage(data) and (GarageLayout.Center(houseCF) - charRoot.Position).Magnitude < SPAWN_RANGE_GARAGE then
		local bays = GarageLayout.Assign(ownedList(data), carId)
		target = GarageLayout.BayCFrame(houseCF, bays[carId] or 2)
		fromGarage = true
	end
	if not target then
		local size = CarModels.Dimensions(carId)
		-- (v10, PHYS10) les autres voitures et les autres joueurs COMPTENT
		-- (on s'y cogne maintenant) : jamais d'apparition dans quelqu'un
		local ignore: { Instance } = { character }
		target = findSpot(charRoot.CFrame, size, ignore)
	end
	local car = makeCar(player, data, carId, target :: CFrame, false, fromGarage)
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
	-- voiture sortie : repeinte tout de suite, même au volant (v9.8 : on ne
	-- change que la couleur des pièces "Paint", rien ne bouge)
	local car = cars[player]
	if car and car.CarId == carId then
		CarModels.Repaint(car.Model, carId, colorId)
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
-- 🔧 (v10, CARS10) Atelier : options visuelles, préparation, plaque
----------------------------------------------------------------------

local function isUnlocked(data: any, carId: string, kind: string, id: string): boolean
	local list = Config.Cars.Mods[kind]
	if list and list[1] and list[1].Id == id then
		return true -- (l'origine est toujours gratuite)
	end
	local entry = Config.CarModsById[kind] and Config.CarModsById[kind][id]
	if entry and (tonumber(entry.Price) or 0) <= 0 then
		return true
	end
	local set = data.Cars.Unlocked[carId]
	return type(set) == "table" and set[kind .. ":" .. id] == true
end

-- Paiement (Dopamine) -> (ok, message?, manque?)
local function pay(player: Player, data: any, cost: number): (boolean, string?, number?)
	if not isValidNumber(cost) or cost < 0 then
		return false, T(player, "Invalid request"), nil
	end
	if cost <= 0 then
		return true, nil, nil
	end
	if not isValidNumber(data.Dopamine) or data.Dopamine < cost then
		local missing = math.max(0, cost - (isValidNumber(data.Dopamine) and data.Dopamine or 0))
		return false, T(player, "Not enough %s", Config.Game.CurrencyName), missing
	end
	data.Dopamine -= cost
	return true, nil, nil
end

-- Voiture sortie et garée : reconstruite sur place avec ses nouvelles options
local function refreshOut(player: Player, data: any, carId: string)
	local car = cars[player]
	if car and car.CarId == carId and not car.Loaner and not car.Driving and car.Seat.Occupant == nil and car.Root.Parent then
		local cf = flatten(car.Model:GetPivot())
		pcall(makeCar, player, data, carId, cf, false, car.Model:GetAttribute("FromGarage") == true)
	end
end

-- "setMod" carId, "Kind:Id" : applique une option (achetée une fois par voiture)
local function setMod(player: Player, data: any, carId: any, pair: any): (boolean, string, number?)
	if type(carId) ~= "string" or not data.Cars.Owned[carId] or type(pair) ~= "string" or #pair > 40 then
		return false, T(player, "Invalid request")
	end
	local kind, id = string.match(pair, "^(%w+):(%w+)$")
	local entry = kind and id and Config.CarModsById[kind] and Config.CarModsById[kind][id]
	if not entry then
		return false, T(player, "Invalid request")
	end
	local need = tonumber(entry.RequiresRebirths) or 0
	if (tonumber(data.Rebirths) or 0) < need then
		return false, T(player, "🔒 Unlocked after %d visits to the ocean", need)
	end
	local owned = isUnlocked(data, carId, kind :: string, id :: string)
	if not owned then
		local cost = CarModels.PriceFor(carId, entry.Price)
		local ok, message, missing = pay(player, data, cost)
		if not ok then
			return false, message or "", missing
		end
		data.Cars.Unlocked[carId] = data.Cars.Unlocked[carId] or {}
		data.Cars.Unlocked[carId][kind .. ":" .. id] = true
	end
	local mods = data.Cars.Mods[carId] or {}
	mods[kind] = id
	data.Cars.Mods[carId] = CarModels.CleanMods(mods)
	sendState(player)
	publish(player)
	refreshOut(player, data, carId)
	return true, T(player, "🔧 %s applied", T(player, entry.Name))
end

-- "tune" carId, "Engine" | "Tyres" | "Suspension" : niveau suivant
local function tune(player: Player, data: any, carId: any, partId: any): (boolean, string, number?)
	local part = type(partId) == "string" and Config.CarTuningById[partId] or nil
	if type(carId) ~= "string" or not data.Cars.Owned[carId] or not part then
		return false, T(player, "Invalid request")
	end
	local tuning = CarModels.TuningOf(data, carId)
	local level = (tuning :: any)[part.Id] + 1
	local maxLevel = tonumber(Config.Cars.Tuning.MaxLevel) or 3
	if level > maxLevel then
		return false, T(player, "Already at the max level")
	end
	local need = type(part.RequiresRebirths) == "table" and tonumber(part.RequiresRebirths[level]) or 0
	if (tonumber(data.Rebirths) or 0) < need then
		return false, T(player, "🔒 Unlocked after %d visits to the ocean", need)
	end
	local cost = CarModels.PriceFor(carId, type(part.Price) == "table" and part.Price[level] or 0)
	local ok, message, missing = pay(player, data, cost)
	if not ok then
		return false, message or "", missing
	end
	;(tuning :: any)[part.Id] = level
	data.Cars.Tuning[carId] = tuning
	sendState(player)
	-- voiture sortie : ses performances changent tout de suite (CarClient lit l'attribut)
	local car = cars[player]
	if car and car.CarId == carId and not car.Loaner then
		local stats = CarModels.Stats(carId, tuning)
		pcall(function()
			car.Model:SetAttribute("TopSpeed", stats.TopSpeed)
			car.Model:SetAttribute("Rating", stats.Rating)
			car.Model:SetAttribute("Class", stats.Class)
			car.Model:SetAttribute("Tuning", string.format("%d%d%d", tuning.Engine, tuning.Tyres, tuning.Suspension))
		end)
	end
	return true, T(player, "%s %s level %d!", part.Icon, T(player, part.Name), level)
end

-- "plate" carId, texte : plaque personnalisée (A-Z, 0-9, espace ; filtrée)
local function setPlate(player: Player, data: any, carId: any, text: any): (boolean, string, number?)
	if type(carId) ~= "string" or not data.Cars.Owned[carId] or type(text) ~= "string" then
		return false, T(player, "Invalid request")
	end
	local maxLength = tonumber(Config.Cars.PlateMaxLength) or 8
	local clean = string.upper(text)
	clean = string.gsub(clean, "[^A-Z0-9 ]", "")
	clean = string.gsub(clean, "^%s+", "")
	clean = string.gsub(clean, "%s+$", "")
	clean = string.gsub(clean, "%s+", " ")
	if #clean == 0 then
		-- plaque d'origine (gratuit)
		data.Cars.Plates[carId] = nil
		sendState(player)
		refreshOut(player, data, carId)
		return true, T(player, "🔖 Original plate")
	end
	if #clean > maxLength then
		return false, T(player, "%d characters max", maxLength)
	end
	local okFilter, filtered = pcall(function()
		local result = TextService:FilterStringAsync(clean, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not okFilter or type(filtered) ~= "string" then
		return false, T(player, "Network error, try again.")
	end
	if filtered ~= clean or string.find(filtered, "#", 1, true) then
		return false, T(player, "🚫 This plate is not allowed")
	end
	if data.Cars.Plates[carId] == clean then
		return true, ""
	end
	local cost = CarModels.PriceFor(carId, Config.Cars.PlatePrice)
	local ok, message, missing = pay(player, data, cost)
	if not ok then
		return false, message or "", missing
	end
	data.Cars.Plates[carId] = clean
	sendState(player)
	refreshOut(player, data, carId)
	return true, T(player, "🔖 Plate %s applied", clean)
end

----------------------------------------------------------------------
-- Remote
----------------------------------------------------------------------

local INTERVALS = { buy = 0.4, buyGarage = 0.4, setColor = 0.25, select = 0.25, exit = 0.3, despawn = 0.5, reset = 2, setMod = 0.2, tune = 0.4, plate = 2 }

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
	elseif action == "setMod" then
		return setMod(player, data, a, b)
	elseif action == "tune" then
		return tune(player, data, a, b)
	elseif action == "plate" then
		return setPlate(player, data, a, b)
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

-- (v10, CARS10 -> RACE10) performances d'une voiture du joueur avec SA
-- préparation (carId nil = voiture choisie ; nil si pas possédée)
function CarService:GetStats(player: Player, carId: string?): any
	local data = dataOf(player)
	if type(data) ~= "table" then
		return nil
	end
	CarService.Sanitize(data)
	local id = if type(carId) == "string" then carId else data.Cars.Selected
	if type(id) ~= "string" or not data.Cars.Owned[id] then
		return nil
	end
	return CarModels.Stats(id, CarModels.TuningOf(data, id))
end

----------------------------------------------------------------------
-- 🏁 (v10, CARS10 -> RACE10) courses : placer / bloquer / rendre
----------------------------------------------------------------------

-- Met la voiture CHOISIE du joueur sur la grille (`cf` = pivot au sol, avant
-- vers -Z), la fait apparaître si elle n'est pas sortie, et l'assoit au
-- volant. Sans voiture : une "CityCar" de prêt (attribut "Loaner"), rendue
-- par RaceRelease. -> (ok, message?)
function CarService:RaceSpawn(player: Player, cf: CFrame): (boolean, string?)
	if typeof(cf) ~= "CFrame" then
		return false, "bad cframe"
	end
	local data = dataOf(player)
	if type(data) ~= "table" then
		return false, T(player, "Loading...")
	end
	local _, humanoid = characterOf(player)
	if not humanoid then
		return false, T(player, "Walk around the town first")
	end
	CarService.Sanitize(data)
	local target = flatten(cf)
	local selected = data.Cars.Selected
	local owned = type(selected) == "string" and selected ~= "" and data.Cars.Owned[selected] == true
	local carId = if owned then selected else "CityCar"
	local car = cars[player]
	local ok, err = pcall(function()
		if car and car.Root.Parent and car.CarId == carId and car.Loaner == not owned then
			-- déjà sortie : on la pose sur la grille (tout l'assemblage suit la Root)
			local root = car.Root
			local wasAnchored = root.Anchored
			root.Anchored = true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			car.Model:PivotTo(target)
			car.LastSafe = root.CFrame
			car.LastUsed = os.clock()
			if not wasAnchored and not car.Frozen and car.Seat.Occupant ~= nil then
				root.Anchored = false
				pcall(function()
					root:SetNetworkOwner(player)
				end)
			end
		else
			car = makeCar(player, data, carId, target, not owned, false)
		end
	end)
	if not ok or not car then
		warn("[CarService] RaceSpawn : " .. tostring(err))
		return false, T(player, "Invalid request")
	end
	sit(player, car :: Car)
	return true, nil
end

-- Fin de course : rend la voiture de prêt (la vraie voiture reste sortie)
function CarService:RaceRelease(player: Player)
	local car = cars[player]
	if not car then
		return
	end
	if car.Frozen then
		CarService:SetFrozen(player, false)
	end
	if car.Loaner then
		despawn(player, true)
	end
end

-- Compte à rebours : voiture ancrée sur place (frozen = true), puis libérée
-- (désancrée, propriété réseau rendue au conducteur)
function CarService:SetFrozen(player: Player, frozen: boolean)
	local car = cars[player]
	if not car or not car.Root.Parent then
		return
	end
	car.Frozen = frozen == true
	pcall(function()
		local root = car.Root
		if car.Frozen then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = true
			car.Model:SetAttribute("Frozen", true)
		else
			car.Model:SetAttribute("Frozen", nil)
			car.LastSafe = root.CFrame
			if car.Seat.Occupant ~= nil then
				root.Anchored = false
				root:SetNetworkOwner(player)
			end
		end
	end)
end

return CarService
