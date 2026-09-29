--[[
	TownFair (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownFair

	🎡 FÊTE FORAINE de Dopamine Town (v9.8, FAIR98), côté SERVEUR :
	derrière la mairie (WorldLayout.FairCFrame), 110 x 76 studs, avec de
	VRAIS manèges où l'on s'assoit :
	  🎡 grande roue (10 nacelles qui restent droites), 🎠 manège à chevaux,
	  ☕ tasses qui tournent, 🎢 chaises volantes, 🗼 tour de chute douce,
	  🚗 autos tamponneuses (on conduit !) ; + le manège de la PLACE
	  (TownPlaza) devient lui aussi un vrai manège.
	Ici, SEULEMENT ce qui doit être partagé : le sol, les SIÈGES (Seat
	ancrés, invisibles), les bornes "Monter" (ProximityPrompt), l'arène et
	les 6 autos tamponneuses (physique), les bornes des stands de
	nourriture (FoodService). Tout le décor (structures, chevaux, nacelles,
	guirlandes, stands, clôtures…) est construit par chaque client
	(Client/World/FairFx) et suit la MÊME pose (Shared/FairRides : fonction
	pure de l'heure du serveur).

	Pourquoi des sièges ANCRÉS déplacés par CFrame : un avatar assis est
	soudé (SeatWeld) à son siège ; siège ancré = tout l'assemblage ancré :
	aucune physique, donc jamais de projection ni de chute, quel que soit
	le poids des passagers. Le serveur ne déplace QUE les sièges occupés
	(10 fois / s, peu de réseau) ; chaque client déplace localement tous
	les sièges proches à chaque image (FairFx : même pose -> fluide).
	Monter : invite "Monter" à l'entrée du manège -> Seat:Sit sur une place
	libre (sièges CanTouch = false : on ne s'y assoit jamais par accident).
	Descendre : sauter / bouton "Se lever" -> le serveur repose l'avatar à
	la sortie du manège (jamais en l'air).
	Autos tamponneuses : caisse NON ancrée (groupe de collision
	"DopamineBumper" : se cognent entre elles et contre la bordure, jamais
	contre les piétons), VehicleSeat, LinearVelocity + AlignOrientation
	réglés par le client du conducteur (propriétaire réseau), comme
	CarService ; rangée (ancrée) à sa place dès qu'elle est libre.
	Budget : ~110 pièces serveur, 0 lumière (les lueurs sont côté client).

	API (TownMap / TownPlaza) :
	  TownFair.Build(decor, geo) -> Folder "Fair" (réserve la place AVANT la
	    nature / les rues : appeler avant elles)
	  TownFair.BuildFoodCorner(decor, geo) -> Folder "FoodCorner"
	  TownFair.AddPlazaCarousel(model, baseCF, booth) : sièges + invite du
	    manège de la place (appelé par TownPlaza, avant Build)
	  TownFair.StallAnchor(parent, cf, stallId, foods, label) : borne de stand
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local FairRides = require(ReplicatedStorage.Shared.FairRides)
local Config = require(ReplicatedStorage.Shared.Config)
local TownKit = require(script.Parent.TownKit)

local TownFair = {}

TownFair.FOLDER_NAME = "Fair"
TownFair.BUMPER_GROUP = "DopamineBumper"
TownFair.WALKER_GROUP = "DopamineWalkers" -- (= CarService.WALKER_GROUP)

local M = TownKit.M
local part = TownKit.Part

local SERVER_RATE = 0.1 -- (s) sièges occupés déplacés 10 fois / s
local GATE_RANGE = 14 -- (studs) distance max à la borne pour monter
local BUMPER_SPEED_CLAMP = 60

local function foodService(): any
	local services = script.Parent.Parent
	local module = services:FindFirstChild("FoodService")
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return ok and result or nil
end

----------------------------------------------------------------------
-- État (un seul jeu de manèges : TownMap.Build peut reconstruire)
----------------------------------------------------------------------

type Ride = {
	Def: any,
	Base: CFrame,
	Seats: { Seat },
	Riders: { [Seat]: Humanoid },
	Groups: { CFrame },
	Exit: CFrame,
	Gate: BasePart?,
	Cars: { any }?,
}

local rides: { Ride } = {}
local pendingPlaza: Ride? = nil
local connections: { RBXScriptConnection } = {}
local generation = 0

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

----------------------------------------------------------------------
-- Pièces serveur
----------------------------------------------------------------------

local function invisible(p: BasePart): BasePart
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

local function newSeat(parent: Instance, name: string, size: Vector3, cf: CFrame): Seat
	local seat = part(parent, name, size, cf, Color3.fromRGB(255, 255, 255), M.SmoothPlastic, "deco", "Seat") :: Seat
	invisible(seat)
	return seat
end

-- Invite (textes anglais ; FairFx les traduit : attributs LocAction / LocObject)
local function prompt(host: BasePart, action: string, object: string, distance: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "FairPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	p:SetAttribute("LocAction", action)
	p:SetAttribute("LocObject", object)
	p.Parent = host
	return p
end

----------------------------------------------------------------------
-- Monter / descendre
----------------------------------------------------------------------

local function characterOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function poseRide(ride: Ride, t: number)
	if ride.Def.Kind ~= "Bumper" then
		FairRides.Pose(ride.Def, t, ride.Groups)
	end
end

local function seatWorld(ride: Ride, index: number): CFrame
	return ride.Base * FairRides.SeatLocal(ride.Def.Kind, index, ride.Groups)
end

-- Place libre : grande roue = la nacelle la plus basse ; sinon au hasard
local function pickSeat(ride: Ride): (Seat?, number?)
	local free = {}
	for i, seat in ipairs(ride.Seats) do
		if seat.Occupant == nil and ride.Riders[seat] == nil then
			table.insert(free, i)
		end
	end
	if #free == 0 then
		return nil, nil
	end
	local best = free[math.random(1, #free)]
	if ride.Def.Kind == "Ferris" then
		local lowest = math.huge
		for _, i in ipairs(free) do
			local y = seatWorld(ride, i).Position.Y
			if y < lowest - 0.01 then
				lowest = y
				best = i
			end
		end
	end
	return ride.Seats[best], best
end

local function exitCharacter(ride: Ride, humanoid: Humanoid, index: number)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") or not character.Parent then
		return
	end
	if humanoid.SeatPart ~= nil then
		return -- (déjà assis ailleurs)
	end
	local off = ((index % 5) - 2) * 1.6
	local cf = ride.Exit * CFrame.new(off, 3.2, 0)
	pcall(function()
		character:PivotTo(cf)
	end)
end

local releaseCar: (ride: Ride, car: any) -> ()

local function watchSeat(ride: Ride, seat: Seat, index: number)
	table.insert(connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		local previous = ride.Riders[seat]
		if occupant then
			ride.Riders[seat] = occupant
			return
		end
		ride.Riders[seat] = nil
		if previous then
			-- (après la destruction de la soudure : on repose l'avatar au sol)
			task.defer(exitCharacter, ride, previous, index)
		end
		if ride.Cars then
			for _, car in ipairs(ride.Cars) do
				if car.Seat == seat then
					task.delay(1.2, function()
						if seat.Occupant == nil then
							releaseCar(ride, car)
						end
					end)
				end
			end
		end
	end))
end

local function board(ride: Ride, player: Player)
	local _, humanoid, root = characterOf(player)
	if not humanoid or not root then
		return
	end
	if humanoid.SeatPart ~= nil then
		return -- déjà assis (voiture, banc, autre manège)
	end
	local gate = ride.Gate
	if gate and (root.Position - gate.Position).Magnitude > GATE_RANGE then
		return
	end
	if ride.Def.Kind == "Bumper" then
		local cars = ride.Cars or {}
		for _, car in ipairs(cars) do
			if car.Seat.Occupant == nil and not car.Busy then
				car.Busy = true
				local body: BasePart = car.Body
				body.Anchored = false
				pcall(function()
					body:SetNetworkOwner(player)
				end)
				car.Seat:Sit(humanoid)
				task.delay(0.5, function()
					car.Busy = false
				end)
				return
			end
		end
		return
	end
	local seat, index = pickSeat(ride)
	if not seat or not index then
		return
	end
	-- siège mis à la pose EXACTE du moment, puis on s'assoit
	poseRide(ride, serverNow())
	seat.CFrame = seatWorld(ride, index)
	ride.Riders[seat] = humanoid
	seat:Sit(humanoid)
	task.delay(1, function()
		if seat.Occupant == nil and ride.Riders[seat] == humanoid then
			ride.Riders[seat] = nil
		end
	end)
end

local function addGate(ride: Ride, parent: Instance, gateCF: CFrame)
	local gate = invisible(part(parent, "RideGate", Vector3.new(1.2, 5, 1.2), gateCF * CFrame.new(0, 2.5, 0), Color3.fromRGB(255, 255, 255), M.SmoothPlastic, "deco"))
	gate:SetAttribute("RideId", ride.Def.Id)
	local def = ride.Def
	local p = prompt(gate, "Ride", def.Icon .. " " .. def.Name, 10)
	p:SetAttribute("RideId", def.Id)
	table.insert(connections, p.Triggered:Connect(function(player)
		local ok, err = pcall(board, ride, player)
		if not ok then
			warn("[TownFair] monter : " .. tostring(err))
		end
	end))
	ride.Gate = gate
end

local function makeRide(parent: Instance, def: any, base: CFrame, exitCF: CFrame): Ride
	local ride: Ride = { Def = def, Base = base, Seats = {}, Riders = {}, Groups = {}, Exit = exitCF }
	local model = Instance.new("Folder")
	model.Name = def.Id
	model.Parent = parent
	if def.Kind ~= "Bumper" then
		poseRide(ride, serverNow())
		for i, spec in ipairs(FairRides.Seats(def.Kind)) do
			local seat = newSeat(model, "RideSeat", spec.Size, seatWorld(ride, i))
			seat:SetAttribute("RideId", def.Id)
			seat:SetAttribute("SeatIndex", i)
			ride.Seats[i] = seat
			watchSeat(ride, seat, i)
		end
	end
	return ride
end

----------------------------------------------------------------------
-- Autos tamponneuses
----------------------------------------------------------------------

local BUMPER_COLORS = {
	Color3.fromRGB(236, 72, 120),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(110, 210, 150),
	Color3.fromRGB(176, 120, 240),
	Color3.fromRGB(255, 130, 70),
}

local function setupGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(TownFair.BUMPER_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(TownFair.WALKER_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(TownFair.BUMPER_GROUP, TownFair.WALKER_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(TownFair.BUMPER_GROUP, TownFair.BUMPER_GROUP, true)
	end)
end

local function carHome(ride: Ride, index: number): CFrame
	return ride.Base * CFrame.new(0, 0.3, 0) * FairRides.BumperHome(index)
end

releaseCar = function(ride: Ride, car: any)
	local body: BasePart = car.Body
	if not body.Parent then
		return
	end
	pcall(function()
		if not body.Anchored then
			body:SetNetworkOwner(nil)
		end
	end)
	body.AssemblyLinearVelocity = Vector3.zero
	body.AssemblyAngularVelocity = Vector3.zero
	body.Anchored = true
	body.CFrame = carHome(ride, car.Index) * CFrame.new(0, 0.6, 0)
	local velocity = body:FindFirstChild("BumperVelocity") :: LinearVelocity?
	if velocity then
		velocity.PlaneVelocity = Vector2.zero
	end
	local align = body:FindFirstChild("BumperAlign") :: AlignOrientation?
	if align then
		align.CFrame = body.CFrame.Rotation
	end
end

local function buildBumper(parent: Instance, ride: Ride)
	setupGroups()
	local model = parent:FindFirstChild(ride.Def.Id) or parent
	local W, D = FairRides.BUMPER_W, FairRides.BUMPER_D
	local base = ride.Base
	-- piste (légèrement surélevée) + bordure en caoutchouc
	local floor = part(model, "BumperFloor", Vector3.new(W, 0.3, D), base * CFrame.new(0, 0.15, 0), Color3.fromRGB(70, 74, 92), M.SmoothPlastic, "solid")
	floor.CastShadow = false
	local rubber = Color3.fromRGB(250, 214, 80)
	for _, s in ipairs({ { 0, -D / 2 - 0.4, W + 1.6, 0.8 }, { 0, D / 2 + 0.4, W + 1.6, 0.8 }, { -W / 2 - 0.4, 0, 0.8, D }, { W / 2 + 0.4, 0, 0.8, D } }) do
		local wall = part(model, "BumperRail", Vector3.new(s[3], 1.9, s[4]), base * CFrame.new(s[1], 0.95, s[2]), rubber, M.Rubber, "solid")
		wall.CustomPhysicalProperties = PhysicalProperties.new(1, 0.2, 0.7, 1, 100)
	end
	local cars: { any } = {}
	ride.Cars = cars
	for i = 1, FairRides.BUMPER_CARS do
		local home = carHome(ride, i)
		local body = part(model, "BumperBody", Vector3.new(3.4, 1.1, 4.6), home * CFrame.new(0, 0.6, 0), BUMPER_COLORS[(i - 1) % #BUMPER_COLORS + 1], M.SmoothPlastic, "solid")
		body.CanQuery = false
		body.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0, 0.55, 100, 100)
		pcall(function()
			body.CollisionGroup = TownFair.BUMPER_GROUP
		end)
		body:SetAttribute("BumperIndex", i)
		local seat = Instance.new("VehicleSeat")
		seat.Name = "BumperSeat"
		seat.Size = Vector3.new(1.6, 0.3, 1.6)
		seat.CFrame = body.CFrame * CFrame.new(0, 0.7, 0.55)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanTouch = false
		seat.CanQuery = false
		seat.CastShadow = false
		seat.Massless = true
		seat.MaxSpeed = 0
		seat.Torque = 0
		seat.TurnSpeed = 0
		seat.HeadsUpDisplay = false
		seat.Anchored = false
		seat:SetAttribute("RideId", ride.Def.Id)
		seat:SetAttribute("SeatIndex", i)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = seat
		weld.Parent = seat
		seat.Parent = body
		TownKit.Stats.Parts += 1
		local attachment = Instance.new("Attachment")
		attachment.Name = "Drive"
		attachment.Parent = body
		local mass = 3.4 * 1.1 * 4.6 * 1.2 -- (volume x densité de la caisse)
		local velocity = Instance.new("LinearVelocity")
		velocity.Name = "BumperVelocity"
		velocity.Attachment0 = attachment
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		velocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
		velocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
		velocity.PlaneVelocity = Vector2.zero
		velocity.MaxForce = math.max(800, (mass + 20) * 90)
		velocity.Parent = body
		local align = Instance.new("AlignOrientation")
		align.Name = "BumperAlign"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.RigidityEnabled = false
		align.MaxTorque = math.max(1e5, mass * 4000)
		align.MaxAngularVelocity = 10
		align.Responsiveness = 25
		align.CFrame = body.CFrame.Rotation
		align.Parent = body
		local car = { Body = body, Seat = seat, Index = i, Busy = false }
		table.insert(cars, car)
		ride.Seats[i] = seat :: any
		watchSeat(ride, seat :: any, i)
	end
end

-- Ronde (2 fois / s) : auto sortie de l'arène, tombée ou trop rapide -> rangée
local function patrolBumper(ride: Ride)
	local cars = ride.Cars
	if not cars then
		return
	end
	for _, car in ipairs(cars) do
		local body: BasePart = car.Body
		if body.Parent and not body.Anchored then
			local rel = ride.Base:PointToObjectSpace(body.Position)
			local out = math.abs(rel.X) > FairRides.BUMPER_W / 2 + 2 or math.abs(rel.Z) > FairRides.BUMPER_D / 2 + 2 or rel.Y < -3 or rel.Y > 6
			if out or body.AssemblyLinearVelocity.Magnitude > BUMPER_SPEED_CLAMP then
				local occupant = car.Seat.Occupant
				if occupant then
					occupant.Sit = false
				end
				releaseCar(ride, car)
			elseif car.Seat.Occupant == nil and not car.Busy then
				releaseCar(ride, car)
			end
		end
	end
end

----------------------------------------------------------------------
-- Boucle serveur : seuls les sièges OCCUPÉS bougent (10 fois / s)
----------------------------------------------------------------------

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function stepRides()
	local t = serverNow()
	table.clear(moveParts)
	table.clear(moveFrames)
	for _, ride in ipairs(rides) do
		if ride.Def.Kind ~= "Bumper" and next(ride.Riders) ~= nil then
			poseRide(ride, t)
			for i, seat in ipairs(ride.Seats) do
				if seat.Occupant ~= nil then
					table.insert(moveParts, seat)
					table.insert(moveFrames, seatWorld(ride, i))
				end
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Nouvelle construction de la ville : on oublie l'ancienne (connexions,
-- boucle, manèges) ; appelé par le premier de AddPlazaCarousel / Build
local function beginEpoch()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	table.clear(rides)
	generation += 1
end

local function startLoop()
	local myGen = generation
	local acc, patrol = 0, 0
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		if myGen ~= generation then
			return
		end
		acc += dt
		patrol += dt
		if acc >= SERVER_RATE then
			acc = 0
			local ok, err = pcall(stepRides)
			if not ok then
				warn("[TownFair] " .. tostring(err))
			end
		end
		if patrol >= 0.5 then
			patrol = 0
			for _, ride in ipairs(rides) do
				if ride.Cars then
					pcall(patrolBumper, ride)
				end
			end
		end
	end))
end

----------------------------------------------------------------------
-- Stands de nourriture (borne invisible + invite, enregistrée par FoodService)
----------------------------------------------------------------------

-- `cf` = devant du comptoir (au sol), -Z vers les clients
function TownFair.StallAnchor(parent: Instance, cf: CFrame, stallId: string, foods: { string }, label: string): BasePart
	local anchor = invisible(part(parent, "StallAnchor", Vector3.new(2, 4, 1), cf * CFrame.new(0, 2.6, 0), Color3.fromRGB(255, 255, 255), M.SmoothPlastic, "deco"))
	anchor:SetAttribute("FoodStall", stallId)
	local p = prompt(anchor, "Order", label, 9)
	p:SetAttribute("FoodStall", stallId)
	p:SetAttribute("Foods", table.concat(foods, ","))
	local service = foodService()
	if service and type(service.RegisterStall) == "function" then
		service.RegisterStall(stallId, anchor, foods)
	end
	return anchor
end

local function stallLabel(foods: { string }): string
	local icons = {}
	for _, id in ipairs(foods) do
		local food = Config.FoodById[id]
		if food then
			table.insert(icons, food.Icon)
		end
	end
	return table.concat(icons, " ") .. " Snacks"
end

----------------------------------------------------------------------
-- Manège de la place (TownPlaza) : 12 places sur les chevaux / carrosses
----------------------------------------------------------------------

function TownFair.AddPlazaCarousel(model: Instance, baseCF: CFrame, booth: BasePart?)
	beginEpoch()
	local def = {
		Id = "PlazaCarousel",
		Kind = "PlazaCarousel",
		Name = "Carousel",
		Icon = "🎠",
		Cycle = { Load = 0, Ramp = 0, Run = 1 },
		Speed = 0,
	}
	local exitCF = if booth then CFrame.new(booth.Position + (baseCF.Position - booth.Position) * Vector3.new(1, 0, 1) * -0.35) else baseCF * CFrame.new(0, 0, -13)
	local folder = Instance.new("Folder")
	folder.Name = "RideSeats"
	folder.Parent = model
	local ride = makeRide(folder, def, baseCF, CFrame.new(exitCF.Position.X, baseCF.Position.Y - 1.2, exitCF.Position.Z))
	if booth then
		addGate(ride, folder, CFrame.new(booth.Position.X, baseCF.Position.Y - 1.2, booth.Position.Z))
	end
	pendingPlaza = ride
end

----------------------------------------------------------------------
-- La fête
----------------------------------------------------------------------

-- Réserve le rectangle de la fête (arbres / terrains n'y poussent pas)
local function reserve(geo: TownKit.Geo, F: CFrame)
	for _, x in ipairs({ -40, 0, 40 }) do
		for _, z in ipairs({ -20, 20 }) do
			geo.Reserve(F * Vector3.new(x, 0, z), 25)
		end
	end
	for _, x in ipairs({ -20, 20 }) do
		geo.Reserve(F * Vector3.new(x, 0, 0), 25)
	end
	geo.Reserve(F * Vector3.new(0, 0, -44), 10) -- allée devant l'arche
end

function TownFair.Build(decor: Instance, geo: TownKit.Geo): Folder
	-- (reconstruction : l'ancienne boucle s'arrête, les sièges partent avec la ville)
	local plaza = pendingPlaza
	pendingPlaza = nil
	if not plaza then
		beginEpoch()
	end
	table.clear(rides)
	local F = WorldLayout.FairCFrame()
	reserve(geo, F)
	local folder = Instance.new("Folder")
	folder.Name = TownFair.FOLDER_NAME
	folder:SetAttribute("FxVersion", 1)
	folder:SetAttribute("FairCF", F)
	folder.Parent = decor
	-- sol de la fête (terre battue claire ; allées et décor : client)
	local ground = part(folder, "FairGround", Vector3.new(WorldLayout.FAIR_W, 0.3, WorldLayout.FAIR_D), F * CFrame.new(0, -0.15, 0), Color3.fromRGB(226, 206, 170), M.Ground, "solid")
	ground.CastShadow = false
	local ridesFolder = Instance.new("Folder")
	ridesFolder.Name = "Rides"
	ridesFolder.Parent = folder
	for _, def in ipairs(FairRides.Rides) do
		local base = FairRides.RideBase(F, def)
		local exitCF = F * CFrame.new(def.Exit)
		local ride = makeRide(ridesFolder, def, base, exitCF)
		addGate(ride, ridesFolder, F * CFrame.new(def.Gate))
		if def.Kind == "Bumper" then
			buildBumper(ridesFolder, ride)
		end
		table.insert(rides, ride)
	end
	if plaza then
		table.insert(rides, plaza) -- (sièges et invite créés juste avant par TownPlaza)
	end
	-- stands de nourriture de la fête
	local stallsFolder = Instance.new("Folder")
	stallsFolder.Name = "Stalls"
	stallsFolder.Parent = folder
	for _, s in ipairs(FairRides.Stalls) do
		local cf = F * CFrame.new(s.Pos) * CFrame.Angles(0, math.rad(s.Yaw), 0)
		TownFair.StallAnchor(stallsFolder, cf * CFrame.new(0, 0, -2.2), s.Id, s.Foods, stallLabel(s.Foods))
	end
	startLoop()
	folder:SetAttribute("Rides", #rides)
	return folder
end

-- 🍦 Coin gourmand près de l'arrivée : sol pavé + 3 bornes de stands
function TownFair.BuildFoodCorner(decor: Instance, geo: TownKit.Geo): Folder
	local cf = WorldLayout.FoodCornerCFrame(geo.Count)
	local folder = Instance.new("Folder")
	folder.Name = "FoodCorner"
	folder:SetAttribute("FxVersion", 1)
	folder:SetAttribute("CornerCF", cf)
	folder.Parent = decor
	-- (juste au-dessus du trottoir : jamais coplanaire avec lui)
	local pad = part(folder, "CornerPad", Vector3.new(WorldLayout.FOOD_W, 1.3, WorldLayout.FOOD_D), cf * CFrame.new(0, -0.65 + 0.04, 0), Color3.fromRGB(236, 222, 208), M.Pavement, "solid")
	pad.CastShadow = false
	for _, s in ipairs(FairRides.CornerStalls) do
		local scf = cf * CFrame.new(s.Pos) * CFrame.Angles(0, math.rad(s.Yaw), 0)
		local front = if s.Style == "Truck" then CFrame.new(0, 0, -3.4) else CFrame.new(0, 0, -2.2)
		TownFair.StallAnchor(folder, scf * front, s.Id, s.Foods, stallLabel(s.Foods))
	end
	geo.Reserve(cf.Position, math.sqrt((WorldLayout.FOOD_W / 2) ^ 2 + (WorldLayout.FOOD_D / 2) ^ 2))
	return folder
end

-- (tests / debug) état des manèges
function TownFair.Debug(): any
	return { Rides = rides }
end

-- Garde l'API privée utilisable par les tests : monter un joueur
function TownFair.Board(rideId: string, player: Player): boolean
	for _, ride in ipairs(rides) do
		if ride.Def.Id == rideId then
			board(ride, player)
			return true
		end
	end
	return false
end

-- (Players.PlayerRemoving : rien à faire, Seat.Occupant repasse à nil tout seul)
local _ = Players

return TownFair
