--[[
	TownTraffic (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownTraffic

	🚦 Circulation d'ambiance + véhicules du décor, CÔTÉ CLIENT (v9.7,
	VEHICLES97). Rien ne part au serveur, rien ne touche les joueurs.
	  1. CIRCULATION : ≤ 6 véhicules (1 bus de ville + voitures variées) qui
	     roulent sur la voie extérieure du boulevard circulaire (conduite à
	     droite, sens des angles croissants ; la voie intérieure sert au
	     stationnement ; l'avenue et les rues sont des impasses piétonnes
	     côté place). Modèles ANCRÉS, sans collision (CanCollide / CanQuery /
	     CanTouch false), déplacés par CFrame (BulkMoveTo) à 30 Hz au plus ;
	     trajectoire arrondie aux angles du polygone ; ils :
	       - s'arrêtent avant le passage piéton de l'entrée si quelqu'un est
	         dessus ou tout près ;
	       - freinent / s'arrêtent si un personnage (ou une voiture de
	         joueur : son conducteur) est devant eux dans la voie ;
	       - gardent leurs distances (et s'espacent peu à peu) ;
	       - le bus marque l'arrêt devant l'entrée (5 s).
	     Loin de la caméra (> 420 studs) : on ne déplace plus leurs pièces
	     (ils avancent "en pensée", sans coût).
	  2. DÉCOR EN FLUX : les "places" posées par le serveur
	     (DopamineTown/VehicleSpots, TownKit.VehicleSpot) sont construites
	     quand on s'approche (< 170 studs) et détruites en s'éloignant
	     (> 230) : bus complet (vitres, sièges, barres), vélos à rayons,
	     trottinettes, scooters, camion de livraison, voitures garées en plus.
	     Au plus 2 constructions par passe (0,5 s).
	Aucune lumière, aucun son.

	Crochet TownClient (envoyé à main) :
	  - à l'entrée en ville  : TownTraffic.Start({ Toast = toast })
	  - flux (4 fois / s)    : TownTraffic.Step(root.Position)   (facultatif)
	  - à la sortie          : TownTraffic.Stop()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local CarModels = require(ReplicatedStorage.Shared.CarModels)
local VehicleModels = require(ReplicatedStorage.Shared.VehicleModels)
local Locale = require(ReplicatedStorage.Shared.Locale)

local TownTraffic = {}

TownTraffic.FOLDER_NAME = "TownTraffic"
TownTraffic.MAX_MOVING = 6
TownTraffic.RATE = 1 / 30 -- 30 Hz au plus
TownTraffic.MOVE_RANGE = 420 -- au-delà : pièces non déplacées
TownTraffic.SPOT_IN = 170
TownTraffic.SPOT_OUT = 230
TownTraffic.SPEED = 20 -- studs / s (voitures)
TownTraffic.BUS_SPEED = 21 -- (un peu plus vite : compense ses arrêts)
TownTraffic.BUS_STOP_TIME = 5

local LocalPlayer = Players.LocalPlayer

-- Couleurs de la circulation (réalistes + quelques pastels de la ville)
local TRAFFIC = {
	{ "CityCar", Color3.fromRGB(246, 244, 240) },
	{ "Hatchback", Color3.fromRGB(56, 90, 170) },
	{ "SUV", Color3.fromRGB(176, 182, 192) },
	{ "BubbleCar", Color3.fromRGB(255, 150, 196) },
	{ "Pickup", Color3.fromRGB(220, 44, 64) },
	{ "Van", Color3.fromRGB(186, 156, 246) },
}

type Path = { Points: { Vector3 }, Cum: { number }, Length: number }
type Vehicle = {
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame },
	Frames: { CFrame },
	S: number,
	Speed: number,
	Cruise: number,
	HalfLen: number,
	HalfWidth: number,
	IsBus: boolean,
	StopClock: number,
	LastStopLap: number,
	Placed: boolean,
}
type Spot = { Config: Instance, Kind: string, CF: CFrame, Model: Model? }

local started = false
local folder: Folder? = nil
local connections: { RBXScriptConnection } = {}
local path: Path? = nil
local vehicles: { Vehicle } = {}
local spots: { Spot } = {}
local focus: Vector3? = nil
local zebra: { CF: CFrame, S: number }? = nil
local busStopS: number? = nil
local accum = 0
local sensorClock = 0
local spotClock = 0
local blockers: { Vector3 } = {} -- positions des personnages (10 fois / s)

----------------------------------------------------------------------
-- Trajectoire : voie extérieure du boulevard (polygone arrondi aux angles)
----------------------------------------------------------------------

local function townFolder(): Instance?
	return workspace:FindFirstChild("DopamineTown")
end

local function plotCount(town: Instance?): number
	local count = town and town:GetAttribute("PlotCount")
	return type(count) == "number" and count or WorldLayout.PlotCount(Players.MaxPlayers)
end

local function buildPath(count: number): Path
	local m = WorldLayout.PlotSlots(count)
	local A = WorldLayout.RingRoadRadius(count)
	local O = WorldLayout.Origin()
	local lane = WorldLayout.ROAD_W / 4 -- milieu de la voie extérieure
	local y = O.Y + WorldLayout.ROAD_Y
	local R = (A + lane) / math.cos(math.pi / m)
	local corners = {}
	for k = 0, m - 1 do
		local a = (k + 0.5) / m * math.pi * 2
		corners[k + 1] = Vector3.new(O.X + math.sin(a) * R, y, O.Z + math.cos(a) * R)
	end
	local pts: { Vector3 } = {}
	local radius = 12
	for i = 1, m do
		local prev = corners[(i - 2) % m + 1]
		local c = corners[i]
		local nxt = corners[i % m + 1]
		local dIn = (c - prev).Unit
		local dOut = (nxt - c).Unit
		local pIn = c - dIn * radius
		local pOut = c + dOut * radius
		-- ligne droite depuis la sortie du virage précédent
		local startP = prev + dIn * radius
		local len = (pIn - startP).Magnitude
		local n = math.max(1, math.floor(len / 4))
		for j = 0, n - 1 do
			table.insert(pts, startP:Lerp(pIn, j / n))
		end
		-- virage (courbe de Bézier)
		for j = 0, 7 do
			local t = j / 8
			local u = 1 - t
			table.insert(pts, pIn * (u * u) + c * (2 * u * t) + pOut * (t * t))
		end
	end
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	local total = cum[#pts] + (pts[1] - pts[#pts]).Magnitude
	return { Points = pts, Cum = cum, Length = total }
end

-- Point de la trajectoire à l'abscisse curviligne s (boucle)
local function pointAt(p: Path, s: number): Vector3
	s = s % p.Length
	local cum = p.Cum
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	if s >= cum[#cum] then
		lo = #cum
	end
	local a = p.Points[lo]
	local b = p.Points[lo % #p.Points + 1]
	local segEnd = if lo == #cum then p.Length else cum[lo + 1]
	local t = (s - cum[lo]) / math.max(1e-6, segEnd - cum[lo])
	return a:Lerp(b, math.clamp(t, 0, 1))
end

local function frameAt(p: Path, s: number): CFrame
	local pos = pointAt(p, s)
	local ahead = pointAt(p, s + 3)
	local back = pointAt(p, s - 3)
	local dir = ahead - back
	if dir.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

-- Abscisse du point de la trajectoire le plus proche de `p`
local function nearestS(pa: Path, p: Vector3): number
	local best, bestS = math.huge, 0
	for i, q in ipairs(pa.Points) do
		local d = (q - p).Magnitude
		if d < best then
			best, bestS = d, pa.Cum[i]
		end
	end
	return bestS
end

----------------------------------------------------------------------
-- Véhicules qui roulent
----------------------------------------------------------------------

local function ghost(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

local function addVehicle(model: Model, s: number, isBus: boolean)
	ghost(model)
	local pivot = model:GetPivot()
	local parts, offsets, frames = {}, {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
			table.insert(frames, d.CFrame)
		end
	end
	local length = tonumber(model:GetAttribute("Length")) or 12
	local width = tonumber(model:GetAttribute("Width")) or 5.5
	local v: Vehicle = {
		Model = model,
		Parts = parts,
		Offsets = offsets,
		Frames = frames,
		S = s,
		Speed = 0,
		Cruise = if isBus then TownTraffic.BUS_SPEED else TownTraffic.SPEED,
		HalfLen = length / 2,
		HalfWidth = width / 2,
		IsBus = isBus,
		StopClock = 0,
		LastStopLap = -1,
		Placed = false,
	}
	model.Parent = folder
	table.insert(vehicles, v)
end

local function spawnTraffic()
	local p = path
	if not p then
		return
	end
	local n = TownTraffic.MAX_MOVING
	local step = p.Length / n
	-- le bus
	local bus = VehicleModels.Bus({ Detail = "Light", T = Locale.T })
	bus.Name = "TrafficBus"
	addVehicle(bus, step * 0.35, true)
	for i = 1, n - 1 do
		local entry = TRAFFIC[(i - 1) % #TRAFFIC + 1]
		local car = CarModels.Build(entry[1], entry[2], { Detail = "Parked", Stripe = i % 3 == 0 })
		car.Name = "TrafficCar"
		addVehicle(car, step * (i + 0.35), false)
	end
end

-- Positions des personnages (piétons ET conducteurs des voitures de joueurs)
local function refreshBlockers()
	table.clear(blockers)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(blockers, root.Position)
		end
	end
end

-- Quelqu'un sur le passage piéton de l'entrée (ou tout près) ?
local function zebraBusy(): boolean
	local z = zebra
	if not z then
		return false
	end
	for _, pos in ipairs(blockers) do
		local rel = z.CF:PointToObjectSpace(pos)
		if math.abs(rel.X) < 9 and math.abs(rel.Z) < 13 and math.abs(rel.Y) < 10 then
			return true
		end
	end
	return false
end

-- Distance libre devant un véhicule (personnages dans sa voie)
local function clearAhead(v: Vehicle, cf: CFrame): number
	local best = math.huge
	for _, pos in ipairs(blockers) do
		local rel = cf:PointToObjectSpace(pos)
		local along = -rel.Z - v.HalfLen
		if along > -v.HalfLen and along < 28 and math.abs(rel.X) < v.HalfWidth + 2.5 and math.abs(rel.Y) < 10 then
			best = math.min(best, math.max(0, along))
		end
	end
	return best
end

local function stepTraffic(dt: number, camPos: Vector3?)
	local p = path
	if not p or #vehicles == 0 then
		return
	end
	local L = p.Length
	local ideal = L / #vehicles
	-- tri circulaire : véhicule suivant = plus petite avance positive
	for _, v in ipairs(vehicles) do
		local ahead = math.huge
		local aheadHalf = 0
		for _, o in ipairs(vehicles) do
			if o ~= v then
				local gap = (o.S - v.S) % L
				if gap < ahead then
					ahead = gap
					aheadHalf = o.HalfLen
				end
			end
		end
		local gap = ahead - v.HalfLen - aheadHalf
		-- vitesse voulue : s'espacer peu à peu (plus vite si le trou devant est grand)
		local target = v.Cruise * (0.85 + 0.3 * math.clamp(gap / ideal, 0, 1))
		if gap < 18 then
			target = math.min(target, math.max(0, (gap - 5) / 13) * v.Cruise)
		end
		local cf = frameAt(p, v.S)
		-- personne devant ?
		local free = clearAhead(v, cf)
		local urgent = false
		if free < 26 then
			target = math.min(target, math.max(0, (free - 4) / 20) * v.Cruise)
			urgent = free < 12
		end
		-- passage piéton de l'entrée
		local z = zebra
		if z then
			local toZebra = (z.S - v.S) % L - v.HalfLen - 9
			if toZebra > -2 and toZebra < 22 and zebraBusy() then
				target = math.min(target, math.max(0, toZebra - 1) / 21 * v.Cruise)
			end
		end
		-- arrêt de bus (une fois par tour)
		if v.IsBus and busStopS then
			-- (n° de passage : constant de l'approche à la fin de l'arrêt)
			local lap = math.floor((v.S + 25 - busStopS) / L)
			local toStop = (busStopS - v.S) % L
			if v.StopClock > 0 then
				v.StopClock -= dt
				target = 0
				if v.StopClock <= 0 then
					v.LastStopLap = lap
				end
			elseif toStop < 25 and v.LastStopLap ~= lap then
				target = math.min(target, (toStop + 2) / 25 * v.Cruise)
				if toStop < 1.5 then
					v.StopClock = TownTraffic.BUS_STOP_TIME
				end
			end
		end
		-- accélération / freinage doux
		local accel = if target > v.Speed then 6 elseif urgent then 30 else 16
		v.Speed = v.Speed + math.clamp(target - v.Speed, -accel * dt, accel * dt)
		v.S += v.Speed * dt
		-- déplacement des pièces (seulement près de la caméra)
		local near = camPos == nil or (cf.Position - camPos).Magnitude < TownTraffic.MOVE_RANGE
		if near and (v.Speed > 0.01 or not v.Placed) then
			local pivot = frameAt(p, v.S)
			local frames = v.Frames
			for i, off in ipairs(v.Offsets) do
				frames[i] = pivot * off
			end
			workspace:BulkMoveTo(v.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			v.Placed = true
		end
	end
end

----------------------------------------------------------------------
-- Décor en flux (places du serveur)
----------------------------------------------------------------------

local function buildSpot(spot: Spot): Model?
	local c = spot.Config
	local kind = spot.Kind
	local color = c:GetAttribute("Color")
	local variant = c:GetAttribute("Variant")
	local model: Model? = nil
	if kind == "Car" then
		local roof = c:GetAttribute("RoofColor")
		model = CarModels.Build(tostring(c:GetAttribute("CarId") or "CityCar"), color, {
			Detail = "Parked",
			Stripe = c:GetAttribute("Stripe") == true,
			RoofColor = if typeof(roof) == "Color3" then roof else nil,
		})
	elseif kind == "Bus" then
		model = VehicleModels.Bus({ Detail = if variant == "Light" then "Light" else "Full", T = Locale.T })
	elseif kind == "DeliveryVan" then
		model = VehicleModels.DeliveryVan({ T = Locale.T })
	elseif kind == "Bike" then
		model = VehicleModels.Bike({ Kind = variant, Color = color })
	elseif kind == "KickScooter" then
		model = VehicleModels.KickScooter({ Color = color })
	elseif kind == "Scooter" then
		model = VehicleModels.Scooter({ Color = color })
	end
	if model then
		model:PivotTo(spot.CF)
		model.Parent = folder
	end
	return model
end

local function readSpots()
	table.clear(spots)
	local town = townFolder()
	local list = town and town:FindFirstChild("VehicleSpots")
	if not list then
		return
	end
	for _, c in ipairs(list:GetChildren()) do
		local cf = c:GetAttribute("CF")
		local kind = c:GetAttribute("Kind")
		if typeof(cf) == "CFrame" and type(kind) == "string" then
			table.insert(spots, { Config = c, Kind = kind, CF = cf, Model = nil })
		end
	end
end

local function stepSpots(center: Vector3)
	local builds = 0
	for _, spot in ipairs(spots) do
		local d = (spot.CF.Position - center).Magnitude
		if spot.Model then
			if d > TownTraffic.SPOT_OUT or not spot.Model.Parent then
				spot.Model:Destroy()
				spot.Model = nil
			end
		elseif d < TownTraffic.SPOT_IN and builds < 2 then
			local ok, model = pcall(buildSpot, spot)
			if ok then
				spot.Model = model
			else
				warn("[TownTraffic] " .. tostring(model))
			end
			builds += 1
		end
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

local function cameraPos(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

local function focusPos(): Vector3?
	if focus then
		return focus
	end
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return cameraPos()
end

function TownTraffic.Start(_options: any?)
	if started then
		return
	end
	started = true
	local old = workspace:FindFirstChild(TownTraffic.FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = TownTraffic.FOLDER_NAME
	f.Parent = workspace
	folder = f
	local town = townFolder()
	local count = plotCount(town)
	local p = buildPath(count)
	path = p
	-- passage piéton de l'entrée (côté 0, au milieu de la chaussée) + arrêt de bus
	local A = WorldLayout.RingRoadRadius(count)
	local O = WorldLayout.Origin()
	local side0 = CFrame.lookAt(O + Vector3.new(0, WorldLayout.ROAD_Y, A), O + Vector3.new(0, WorldLayout.ROAD_Y, A - 1))
	zebra = { CF = side0, S = nearestS(p, (side0 * CFrame.new(0, 0, WorldLayout.ROAD_W / 4)).Position) }
	busStopS = nearestS(p, (side0 * CFrame.new(26, 0, WorldLayout.ROAD_W / 4)).Position)
	spawnTraffic()
	readSpots()
	local list = town and town:FindFirstChild("VehicleSpots")
	if list then
		table.insert(connections, list.ChildAdded:Connect(function()
			task.defer(function()
				if started then
					for _, s in ipairs(spots) do
						if s.Model then
							s.Model:Destroy()
						end
					end
					readSpots()
				end
			end)
		end))
	end
	refreshBlockers()
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		sensorClock += dt
		spotClock += dt
		if sensorClock >= 0.1 then
			sensorClock = 0
			refreshBlockers()
		end
		if accum >= TownTraffic.RATE then
			local step = math.min(accum, 0.25)
			accum = 0
			local ok, err = pcall(stepTraffic, step, cameraPos())
			if not ok then
				warn("[TownTraffic] " .. tostring(err))
			end
		end
		if spotClock >= 0.5 then
			spotClock = 0
			local center = focusPos()
			if center then
				local ok, err = pcall(stepSpots, center)
				if not ok then
					warn("[TownTraffic] " .. tostring(err))
				end
			end
		end
	end))
end

-- (crochet TownClient, 4 fois / s) : position de l'avatar pour le flux
function TownTraffic.Step(rootPosition: Vector3?)
	if typeof(rootPosition) == "Vector3" then
		focus = rootPosition
	end
end

function TownTraffic.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	table.clear(vehicles)
	table.clear(spots)
	table.clear(blockers)
	path = nil
	zebra = nil
	busStopS = nil
	focus = nil
	accum, sensorClock, spotClock = 0, 0, 0
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function TownTraffic.IsRunning(): boolean
	return started
end

-- (tests / émulateur)
function TownTraffic.Debug(): any
	return {
		Vehicles = vehicles,
		Spots = spots,
		Path = function()
			return path
		end,
		Zebra = function()
			return zebra
		end,
		BusStop = function()
			return busStopS
		end,
		StepTraffic = stepTraffic,
		StepSpots = stepSpots,
		Blockers = blockers,
		RefreshBlockers = refreshBlockers,
		FrameAt = function(s: number): CFrame?
			return path and frameAt(path, s) or nil
		end,
	}
end

return TownTraffic
