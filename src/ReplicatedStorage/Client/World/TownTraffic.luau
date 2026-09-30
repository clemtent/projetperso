--[[
	TownTraffic (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownTraffic

	🚦 Circulation d'ambiance + véhicules du décor, CÔTÉ CLIENT (v9.7,
	VEHICLES97). Rien ne part au serveur, rien ne touche les joueurs.
	  1. CIRCULATION : 1 bus de ville + voitures variées qui roulent sur la
	     voie extérieure du boulevard circulaire (conduite à droite). Modèles
	     ANCRÉS, sans collision, déplacés par CFrame (BulkMoveTo) ; ils
	     s'arrêtent avant le passage piéton de l'entrée si quelqu'un est
	     dessus, freinent devant un personnage ou un passant (TownPeople),
	     gardent leurs distances, le bus marque ses arrêts.
	  2. DÉCOR EN FLUX : les "places" posées par le serveur
	     (DopamineTown/VehicleSpots, TownKit.VehicleSpot) sont construites
	     quand on s'approche et détruites en s'éloignant.
	v9.8 (CARS98) : feux stop, clignotants, arrêts aux carrefours.

	v9.9 (CARS99) "100x plus réaliste, sans à-coups" :
	  - MOUVEMENT À CHAQUE IMAGE (Heartbeat) près de la caméra (< 140 studs ;
	    ~20 Hz plus loin) : plus de saccades à 30 Hz ; démarrages et freinages
	    en douceur (accélération limitée + à-coup limité), jamais de saut ;
	  - ROUES qui TOURNENT (vitesse / rayon) et BRAQUENT dans les virages
	    (braquage = atan(empattement × courbure)), SUSPENSION : la caisse
	    plonge au freinage, s'assoit à l'accélération, prend du roulis dans
	    les virages, légère vibration de la route ;
	  - BUS : il s'AGENOUILLE à l'arrêt (caisse abaissée + penchée côté
	    trottoir), ses PORTES s'ouvrent (les battants sortent puis glissent),
	    se referment, puis il se relève et repart ;
	  - NIVEAUX DE DÉTAIL : voitures "Mid" (~150 pièces) près de la caméra,
	    "Low" (~37) plus loin (échange avec hystérésis, 1 reconstruction par
	    image au plus) ; places de stationnement idem ;
	  - les voitures garées CONSTRUITES PAR LE SERVEUR (version "Low" pour le
	    budget de la ville) sont remplacées localement par la version "Mid"
	    quand on s'en approche (le modèle serveur est rendu invisible pour ce
	    client : LocalTransparencyModifier ; sa boîte de collision reste).
	Aucune lumière, aucun son.

	Crochet TownClient (inchangé) :
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

-- (v9.8) réglage "Graphismes > Détail" (REALISM98) : portée d'animation et
-- nombre de véhicules réduits en détail bas
local okGQ, GraphicsQuality = pcall(require, ReplicatedStorage.Shared:FindFirstChild("GraphicsQuality") :: any)
local function detailScale(): number
	if okGQ and type(GraphicsQuality) == "table" and type(GraphicsQuality.DetailScale) == "function" then
		local ok, value = pcall(GraphicsQuality.DetailScale)
		if ok and type(value) == "number" then
			return value
		end
	end
	return 1
end
local function lowDetail(): boolean
	if okGQ and type(GraphicsQuality) == "table" and type(GraphicsQuality.Get) == "function" then
		local ok, q = pcall(GraphicsQuality.Get)
		return ok and type(q) == "table" and q.Detail == "Low"
	end
	return false
end

TownTraffic.FOLDER_NAME = "TownTraffic"
TownTraffic.MAX_MOVING = 10 -- 1 bus + 9 voitures
TownTraffic.MOVE_RANGE = 420 -- au-delà : pièces non déplacées
TownTraffic.SMOOTH_RANGE = 140 -- (v9.9) en deçà : pose à chaque image
TownTraffic.MID_IN = 85 -- (v9.9) voitures "Mid" plus près que ça
TownTraffic.MID_OUT = 105
TownTraffic.SPOT_IN = 170
TownTraffic.SPOT_OUT = 230
TownTraffic.PARKED_IN = 90 -- (v9.9) voitures du serveur remplacées par "Mid"
TownTraffic.PARKED_OUT = 110
TownTraffic.SPEED = 20 -- studs / s (voitures)
TownTraffic.BUS_SPEED = 21 -- (un peu plus vite : compense ses arrêts)
TownTraffic.BUS_STOP_TIME = 6
TownTraffic.SIDE_STOP_TIME = 4.5 -- arrêts aux carrefours des rues latérales
TownTraffic.BLINK_AHEAD = 34 -- clignotant allumé à moins de 34 studs d'un virage
TownTraffic.MAX_STEER = math.rad(32)

local LocalPlayer = Players.LocalPlayer

-- Couleurs de la circulation (réalistes + quelques pastels de la ville)
local TRAFFIC = {
	{ "CityCar", Color3.fromRGB(246, 244, 240) },
	{ "Hatchback", Color3.fromRGB(56, 90, 170) },
	{ "SUV", Color3.fromRGB(176, 182, 192) },
	{ "BubbleCar", Color3.fromRGB(255, 150, 196) },
	{ "Pickup", Color3.fromRGB(220, 44, 64) },
	{ "Van", Color3.fromRGB(186, 156, 246) },
	{ "SportsCar", Color3.fromRGB(255, 212, 80) },
	{ "Limo", Color3.fromRGB(38, 38, 48) },
	{ "Hatchback", Color3.fromRGB(34, 110, 76) },
}
local AMBER = Color3.fromRGB(255, 170, 60)
local BRAKE_ON = Color3.fromRGB(255, 58, 70)

type Path = { Points: { Vector3 }, Cum: { number }, Length: number, Corners: { { S: number, Turn: number } } }
type DoorLeaf = { Index: number, Leaf: number, Door: number }
type Vehicle = {
	Model: Model,
	Rig: any, -- CarModels.Rig
	Kind: string,
	Color: Color3,
	Stripe: boolean,
	Lod: number, -- 2 Mid, 1 Low, 0 bus
	S: number,
	Speed: number,
	Accel: number,
	Cruise: number,
	HalfLen: number,
	HalfWidth: number,
	Base: number, -- empattement
	IsBus: boolean,
	StopClock: number,
	LastStopLap: number,
	Placed: boolean,
	Skip: number,
	Blinkers: { [number]: { BasePart } }, -- [-1] gauche / [1] droite
	Brakes: { BasePart },
	BlinkSide: number,
	Braking: boolean,
	StopLaps: { [number]: number },
	Spin: number,
	Steer: number,
	Heading: number?,
	Pitch: number,
	Roll: number,
	Kneel: number,
	DoorOpen: number,
	Doors: { DoorLeaf },
	DoorOffs: { [number]: CFrame },
}
type Spot = { Config: Instance, Kind: string, CF: CFrame, Model: Model?, Lod: number }
type Parked = { Server: Model, Local: Model?, Kind: string, Color: Color3, Scale: Vector3 }

local started = false
local folder: Folder? = nil
local connections: { RBXScriptConnection } = {}
local path: Path? = nil
local vehicles: { Vehicle } = {}
local spots: { Spot } = {}
local parked: { Parked } = {}
local focus: Vector3? = nil
local zebra: { CF: CFrame, S: number }? = nil
local busStopS: number? = nil
local sideStops: { number } = {} -- arrêts de bus aux carrefours des rues latérales
local sensorClock = 0
local spotClock = 0
local blockers: { Vector3 } = {} -- positions des personnages et passants (10 fois / s)
local rebuiltThisFrame = false

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
	local radius = 14
	local cornerIdx: { { I: number, Turn: number } } = {}
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
		-- virage (courbe de Bézier, 16 points : courbure douce) ; sens (+1 gauche / -1 droite)
		table.insert(cornerIdx, { I = #pts + 8, Turn = if dIn:Cross(dOut).Y > 0 then -1 else 1 })
		for j = 0, 15 do
			local t = j / 16
			local u = 1 - t
			table.insert(pts, pIn * (u * u) + c * (2 * u * t) + pOut * (t * t))
		end
	end
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	local total = cum[#pts] + (pts[1] - pts[#pts]).Magnitude
	local cornerList = {}
	for _, c in ipairs(cornerIdx) do
		table.insert(cornerList, { S = cum[c.I] or 0, Turn = c.Turn })
	end
	return { Points = pts, Cum = cum, Length = total, Corners = cornerList }
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

-- Repère au sol (avant = -Z = sens de marche) ; la direction vient d'une base
-- de ±`look` studs (virages lissés)
local function frameAt(p: Path, s: number, look: number?): CFrame
	local d = look or 3
	-- (v9.9) position filtrée sur ±2 studs : plus d'angles vifs entre les
	-- points de la polyligne (trajectoire C1, sans à-coups de direction)
	local pos = (pointAt(p, s - 2) + pointAt(p, s) * 2 + pointAt(p, s + 2)) / 4
	local ahead = pointAt(p, s + d)
	local back = pointAt(p, s - d)
	local dir = ahead - back
	if dir.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

local function headingOf(cf: CFrame): number
	local l = cf.LookVector
	return math.atan2(-l.X, -l.Z)
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

-- clignotants (4 petits feux orange, éteints = invisibles) + feux stop
local function addLights(model: Model): ({ [number]: { BasePart } }, { BasePart })
	local pivot = model:GetPivot()
	local length = tonumber(model:GetAttribute("Length")) or 12
	local width = tonumber(model:GetAttribute("Width")) or 5.5
	local height = tonumber(model:GetAttribute("Height")) or 5
	local y = math.clamp(height * 0.42, 1.8, 3.4)
	local blinkers: { [number]: { BasePart } } = { [-1] = {}, [1] = {} }
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = Instance.new("Part")
			p.Name = "Blinker"
			p.Size = Vector3.new(0.16, 0.24, 0.5)
			p.CFrame = pivot * CFrame.new(sx * (width / 2 + 0.03), y, sz * (length / 2 - 0.6))
			p.Color = AMBER
			p.Material = Enum.Material.Neon
			p.Transparency = 1
			p.CastShadow = false
			p.Parent = model
			table.insert(blinkers[sx], p)
		end
	end
	local brakes = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Taillight" then
			d:SetAttribute("OffColor", d.Color)
			d:SetAttribute("OffMaterial", d.Material.Name)
			table.insert(brakes, d)
		end
	end
	return blinkers, brakes
end

-- (Re)construit le modèle d'un véhicule au niveau de détail voulu
local function buildVehicleModel(v: Vehicle, lod: number)
	local old = v.Model
	local model: Model
	if v.IsBus then
		model = VehicleModels.Bus({ Detail = "Light", T = Locale.T })
		model.Name = "TrafficBus"
	else
		model = CarModels.Build(v.Kind, v.Color, { Detail = if lod >= 2 then "Mid" else "Low", Stripe = v.Stripe })
		model.Name = "TrafficCar"
	end
	local pivot = if old and old.Parent then old:GetPivot() else CFrame.new()
	model:PivotTo(CFrame.new())
	local blinkers, brakes = addLights(model)
	ghost(model)
	local rig = CarModels.WheelRig(model)
	v.Rig = rig
	v.Blinkers = blinkers
	v.Brakes = brakes
	v.BlinkSide = 0
	v.Braking = false
	v.Lod = lod
	-- battants de portes (bus)
	local doors: { DoorLeaf } = {}
	for index, part in ipairs(rig.Body) do
		local door = part:GetAttribute("Door")
		if type(door) == "number" then
			table.insert(doors, { Index = index, Leaf = tonumber(part:GetAttribute("Leaf")) or 1, Door = door })
		end
	end
	v.Doors = doors
	v.DoorOffs = {}
	local length = tonumber(model:GetAttribute("Length")) or 12
	v.HalfLen = length / 2
	v.HalfWidth = (tonumber(model:GetAttribute("Width")) or 5.5) / 2
	local front, back = math.huge, -math.huge
	for _, w in ipairs(rig.Wheels) do
		front = math.min(front, w.Center.Position.Z)
		back = math.max(back, w.Center.Position.Z)
	end
	v.Base = if back > front then back - front else length * 0.6
	model:PivotTo(pivot)
	for i, part in ipairs(rig.Parts) do
		rig.Frames[i] = part.CFrame
	end
	model.Parent = folder
	v.Model = model
	v.Placed = false
	if old and old ~= model then
		old:Destroy()
	end
end

local function addVehicle(kind: string, color: Color3, stripe: boolean, s: number, isBus: boolean)
	local v: Vehicle = {
		Model = nil :: any,
		Rig = nil,
		Kind = kind,
		Color = color,
		Stripe = stripe,
		Lod = 1,
		S = s,
		Speed = 0,
		Accel = 0,
		Cruise = if isBus then TownTraffic.BUS_SPEED else TownTraffic.SPEED,
		HalfLen = 6,
		HalfWidth = 2.8,
		Base = 7,
		IsBus = isBus,
		StopClock = 0,
		LastStopLap = -1,
		Placed = false,
		Skip = 0,
		Blinkers = { [-1] = {}, [1] = {} },
		Brakes = {},
		BlinkSide = 0,
		Braking = false,
		StopLaps = {},
		Spin = 0,
		Steer = 0,
		Heading = nil,
		Pitch = 0,
		Roll = 0,
		Kneel = 0,
		DoorOpen = 0,
		Doors = {},
		DoorOffs = {},
	}
	buildVehicleModel(v, if isBus then 0 else 1)
	table.insert(vehicles, v)
end

local function spawnTraffic()
	local p = path
	if not p then
		return
	end
	local n = if lowDetail() then math.min(6, TownTraffic.MAX_MOVING) else TownTraffic.MAX_MOVING
	local step = p.Length / n
	addVehicle("Bus", Color3.new(1, 1, 1), false, step * 0.35, true)
	for i = 1, n - 1 do
		local entry = TRAFFIC[(i - 1) % #TRAFFIC + 1]
		addVehicle(entry[1], entry[2], i % 3 == 0, step * (i + 0.35), false)
	end
end

-- Passants de TownPeople (s'ils existent) : les voitures s'arrêtent devant eux
local peopleModule: any = nil
local function peoplePositions(): { Vector3 }
	if peopleModule == nil then
		peopleModule = false
		local module = script.Parent:FindFirstChild("TownPeople")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				peopleModule = result
			end
		end
	end
	if peopleModule and type(peopleModule.Positions) == "function" then
		local ok, list = pcall(peopleModule.Positions)
		if ok and type(list) == "table" then
			return list
		end
	end
	return {}
end

-- Positions des personnages (piétons ET conducteurs) + passants
local function refreshBlockers()
	table.clear(blockers)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(blockers, root.Position)
		end
	end
	for _, pos in ipairs(peoplePositions()) do
		if typeof(pos) == "Vector3" then
			table.insert(blockers, pos)
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

-- Pose complète : caisse (suspension, génuflexion du bus, portes) + roues
local function poseVehicle(v: Vehicle, pivot: CFrame)
	local rig = v.Rig
	if not rig then
		return
	end
	local frames = rig.Frames
	local lift = 1.0
	local heave = -0.38 * v.Kneel
	local roll = v.Roll - 0.028 * v.Kneel -- (bus : penché côté trottoir, +X)
	local bob = CFrame.new(0, lift + heave, 0) * CFrame.Angles(v.Pitch, 0, roll) * CFrame.new(0, -lift, 0)
	local body = pivot * bob
	local offs = v.DoorOffs
	local i = 0
	for k, off in ipairs(rig.BodyOff) do
		i += 1
		local door = offs[k]
		frames[i] = if door then body * door * off else body * off
	end
	local spinCF = CFrame.Angles(-v.Spin, 0, 0)
	local steerCF = CFrame.Angles(0, v.Steer, 0)
	for _, set in ipairs(rig.Wheels) do
		local c = pivot * set.Center
		local steered = if set.Front then c * steerCF else c
		local spun = steered * spinCF
		for _, off in ipairs(set.SpinOff) do
			i += 1
			frames[i] = spun * off
		end
		for _, off in ipairs(set.SteerOff) do
			i += 1
			frames[i] = steered * off
		end
	end
	workspace:BulkMoveTo(rig.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Portes du bus : 0 fermées -> 0,35 battants sortis -> 1 glissés
local function updateDoors(v: Vehicle)
	table.clear(v.DoorOffs)
	if #v.Doors == 0 or v.DoorOpen <= 0.001 then
		return
	end
	local o = v.DoorOpen
	local out = 0.2 * math.clamp(o / 0.35, 0, 1)
	local slide = 1.2 * math.clamp((o - 0.35) / 0.65, 0, 1)
	for _, leaf in ipairs(v.Doors) do
		v.DoorOffs[leaf.Index] = CFrame.new(out, 0, leaf.Leaf * slide)
	end
end

local function stepTraffic(dt: number, camPos: Vector3?)
	local p = path
	if not p or #vehicles == 0 then
		return
	end
	rebuiltThisFrame = false
	local L = p.Length
	local ideal = L / #vehicles
	local range = TownTraffic.MOVE_RANGE * detailScale()
	for _, v in ipairs(vehicles) do
		-- véhicule suivant = plus petite avance positive
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
		-- ralentir dans les virages (la courbure se lit sur ±8 studs)
		local h0 = headingOf(frameAt(p, v.S - 4, 4))
		local h1 = headingOf(frameAt(p, v.S + 4, 4))
		local dh = (h1 - h0 + math.pi) % (2 * math.pi) - math.pi
		local curvature = dh / 8
		target = math.min(target, v.Cruise * (1 - math.clamp(math.abs(curvature) * 6, 0, 0.35)))
		-- arrêts de bus (une fois par tour à chaque arrêt : entrée + carrefours)
		if v.IsBus then
			if v.StopClock > 0 then
				v.StopClock -= dt
				target = 0
			else
				local stops = { busStopS }
				for _, st in ipairs(sideStops) do
					table.insert(stops, st)
				end
				for k, stopS in ipairs(stops) do
					if stopS then
						local lap = math.floor((v.S + 30 - stopS) / L)
						local toStop = (stopS - v.S) % L
						if toStop > L - 3 then
							toStop -= L -- (arrêt dépassé de peu : on s'arrête quand même)
						end
						if toStop < 30 and v.StopLaps[k] ~= lap then
							-- freinage régulier (≈ 2,4 studs/s²) jusqu'au point d'arrêt
							target = math.min(target, math.sqrt(math.max(0, toStop) * 2 * 2.4))
							if toStop < 0.6 and v.Speed < 1.5 then
								v.StopClock = if k == 1 then TownTraffic.BUS_STOP_TIME else TownTraffic.SIDE_STOP_TIME
								v.StopLaps[k] = lap
								v.LastStopLap = lap
							end
						end
					end
				end
			end
			-- génuflexion + portes : s'agenouiller, ouvrir, fermer, se relever
			local stopped = v.StopClock > 0 and v.Speed < 0.3
			local wantKneel = if stopped then 1 else 0
			local wantDoors = if stopped and v.StopClock > 1.4 and v.Kneel > 0.7 then 1 else 0
			if wantDoors == 0 and v.DoorOpen > 0.01 then
				wantKneel = 1 -- (on ne se relève qu'une fois les portes fermées)
			end
			v.DoorOpen += math.clamp(wantDoors - v.DoorOpen, -dt / 1.1, dt / 1.1)
			v.Kneel += math.clamp(wantKneel - v.Kneel, -dt / 1.2, dt / 1.2)
			if v.DoorOpen > 0.01 or v.Kneel > 0.05 then
				target = 0
			end
			updateDoors(v)
		end
		-- clignotant avant les virages du boulevard
		local blink = 0
		for _, c in ipairs(p.Corners) do
			local toCorner = (c.S - v.S) % L
			local past = (v.S - c.S) % L
			if toCorner < TownTraffic.BLINK_AHEAD + v.HalfLen or past < 6 then
				blink = c.Turn
			end
		end
		-- accélération / freinage doux : accélération voulue, puis à-coup limité
		local wantAccel
		if target > v.Speed then
			wantAccel = math.min((target - v.Speed) * 1.2, 2.5 + 3 * math.clamp(v.Speed / v.Cruise, 0, 1))
		else
			wantAccel = math.max((target - v.Speed) * 1.8, if urgent then -26 else -9)
		end
		local jerk = if urgent then 80 else 14
		v.Accel += math.clamp(wantAccel - v.Accel, -jerk * dt, jerk * dt)
		local before = v.Speed
		v.Speed = math.max(0, v.Speed + v.Accel * dt)
		if v.Speed <= 0 and v.Accel < 0 then
			v.Accel = 0
		end
		if v.Speed > target and target <= 0.01 and v.Speed < 0.15 then
			v.Speed = 0
		end
		v.S += v.Speed * dt -- (non bouclé : sert à compter les tours des arrêts de bus)
		-- feux stop quand on freine (ou à l'arrêt), clignotants (2 Hz)
		local braking = v.Speed < before - 0.02 or (v.Speed < 0.3 and target < 0.5)
		if braking ~= v.Braking then
			v.Braking = braking
			for _, b in ipairs(v.Brakes) do
				b.Color = if braking then BRAKE_ON else (b:GetAttribute("OffColor") or b.Color)
				local off = b:GetAttribute("OffMaterial")
				local ok, mat = pcall(function()
					return (Enum.Material :: any)[off]
				end)
				b.Material = if braking then Enum.Material.Neon elseif ok and mat then mat else Enum.Material.SmoothPlastic
			end
		end
		local on = blink ~= 0 and (os.clock() * 2) % 1 < 0.55
		local side = if on then blink else 0
		if side ~= v.BlinkSide then
			v.BlinkSide = side
			for _, sx in ipairs({ -1, 1 }) do
				for _, b in ipairs(v.Blinkers[sx]) do
					b.Transparency = if sx == side then 0 else 1
				end
			end
		end
		-- roues : rotation + braquage ; caisse : tangage / roulis
		local pivot = frameAt(p, v.S)
		local heading = headingOf(pivot)
		local yawRate = 0
		if v.Heading then
			yawRate = ((heading - v.Heading + math.pi) % (2 * math.pi) - math.pi) / math.max(dt, 1e-3)
		end
		v.Heading = heading
		local radius = if v.Rig and v.Rig.Wheels[1] then v.Rig.Wheels[1].Radius else 1
		v.Spin = (v.Spin + v.Speed / math.max(0.3, radius) * dt) % (math.pi * 2)
		local steerTarget = math.clamp(math.atan(v.Base * curvature), -TownTraffic.MAX_STEER, TownTraffic.MAX_STEER)
		v.Steer += (steerTarget - v.Steer) * math.clamp(dt * 6, 0, 1)
		local pitchTarget = math.clamp(v.Accel * 0.0028, -0.032, 0.022)
		local rollTarget = math.clamp(-v.Speed * yawRate * 0.0035, -0.035, 0.035)
		local k = math.clamp(dt * 5, 0, 1)
		v.Pitch += (pitchTarget - v.Pitch) * k
		v.Roll += (rollTarget - v.Roll) * k
		-- niveau de détail (voitures) : "Mid" près de la caméra
		local dist = if camPos then (pivot.Position - camPos).Magnitude else 0
		if not v.IsBus and not rebuiltThisFrame then
			local want = v.Lod
			if dist < TownTraffic.MID_IN * detailScale() then
				want = 2
			elseif dist > TownTraffic.MID_OUT * detailScale() then
				want = 1
			end
			if want ~= v.Lod then
				rebuiltThisFrame = true
				buildVehicleModel(v, want)
			end
		end
		-- déplacement des pièces : chaque image près de la caméra, ~20 Hz plus loin
		local near = camPos == nil or dist < range
		if near then
			local smooth = camPos == nil or dist < TownTraffic.SMOOTH_RANGE
			v.Skip += 1
			if smooth or v.Skip >= 3 or not v.Placed then
				v.Skip = 0
				-- (petite vibration de la route, proportionnelle à la vitesse)
				local noise = math.sin(os.clock() * 11 + v.S) * 0.012 * math.clamp(v.Speed / 20, 0, 1)
				poseVehicle(v, pivot * CFrame.new(0, noise, 0))
				v.Placed = true
			end
		end
	end
end

----------------------------------------------------------------------
-- Décor en flux (places du serveur) + voitures garées du serveur
----------------------------------------------------------------------

local function buildSpot(spot: Spot, lod: number): Model?
	local c = spot.Config
	local kind = spot.Kind
	local color = c:GetAttribute("Color")
	local variant = c:GetAttribute("Variant")
	local model: Model? = nil
	if kind == "Car" then
		local roof = c:GetAttribute("RoofColor")
		model = CarModels.Build(tostring(c:GetAttribute("CarId") or "CityCar"), color, {
			Detail = if lod >= 2 then "Mid" else "Low",
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
			table.insert(spots, { Config = c, Kind = kind, CF = cf, Model = nil, Lod = 0 })
		end
	end
end

local function setLocalHidden(model: Instance, hidden: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		elseif d:IsA("SurfaceGui") then
			d.Enabled = not hidden
		end
	end
end

-- voitures garées construites par le serveur (TownKit.Car : version "Low")
local function readParked()
	for _, pk in ipairs(parked) do
		if pk.Local then
			pk.Local:Destroy()
		end
		if pk.Server.Parent then
			setLocalHidden(pk.Server, false)
		end
	end
	table.clear(parked)
	local town = townFolder()
	if not town then
		return
	end
	for _, d in ipairs(town:GetDescendants()) do
		if d:IsA("Model") and type(d:GetAttribute("CarKind")) == "string" then
			local kind = d:GetAttribute("CarKind") :: string
			local spec = CarModels.Specs[kind]
			if spec then
				local color = Color3.new(1, 1, 1)
				for _, q in ipairs(d:GetDescendants()) do
					if q:IsA("BasePart") and q:GetAttribute("Paint") then
						color = q.Color
						break
					end
				end
				local scale = Vector3.new(
					(tonumber(d:GetAttribute("Width")) or spec.W) / spec.W,
					(tonumber(d:GetAttribute("Height")) or spec.Roof) / spec.Roof,
					(tonumber(d:GetAttribute("Length")) or spec.L) / spec.L
				)
				table.insert(parked, { Server = d, Local = nil, Kind = kind, Color = color, Scale = scale })
			end
		end
	end
end

local function stepSpots(center: Vector3)
	local builds = 0
	local mid = TownTraffic.PARKED_IN * detailScale()
	local midOut = TownTraffic.PARKED_OUT * detailScale()
	for _, spot in ipairs(spots) do
		local d = (spot.CF.Position - center).Magnitude
		if spot.Model then
			if d > TownTraffic.SPOT_OUT or not spot.Model.Parent then
				spot.Model:Destroy()
				spot.Model = nil
				spot.Lod = 0
			elseif spot.Kind == "Car" and builds < 2 and ((spot.Lod < 2 and d < mid) or (spot.Lod >= 2 and d > midOut)) then
				-- (v9.9) changement de niveau de détail
				local lod = if d < mid then 2 else 1
				local ok, model = pcall(buildSpot, spot, lod)
				if ok and model then
					spot.Model:Destroy()
					spot.Model = model
					spot.Lod = lod
				end
				builds += 1
			end
		elseif d < TownTraffic.SPOT_IN and builds < 2 then
			local lod = if d < mid then 2 else 1
			local ok, model = pcall(buildSpot, spot, lod)
			if ok then
				spot.Model = model
				spot.Lod = lod
			else
				warn("[TownTraffic] " .. tostring(model))
			end
			builds += 1
		end
	end
	-- voitures garées du serveur : version "Mid" locale quand on s'approche
	for _, pk in ipairs(parked) do
		local server = pk.Server
		if not server.Parent then
			if pk.Local then
				pk.Local:Destroy()
				pk.Local = nil
			end
		else
			local d = (server:GetPivot().Position - center).Magnitude
			if pk.Local and d > midOut then
				pk.Local:Destroy()
				pk.Local = nil
				setLocalHidden(server, false)
			elseif not pk.Local and d < mid and builds < 2 then
				builds += 1
				local ok, model = pcall(CarModels.Build, pk.Kind, pk.Color, { Detail = "Mid", Scale = pk.Scale })
				if ok and model then
					ghost(model)
					model:PivotTo(server:GetPivot())
					model.Name = "ParkedCar"
					model.Parent = folder
					pk.Local = model
					setLocalHidden(server, true)
				end
			end
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
	-- 2 autres arrêts : aux carrefours des rues latérales (1/4 et 3/4 du tour)
	table.clear(sideStops)
	local m = WorldLayout.PlotSlots(count)
	local sideR = math.max(1, math.floor(m / 4 + 0.5))
	for _, slot in ipairs({ sideR, m - sideR }) do
		local a = slot / m * math.pi * 2
		local dirv = Vector3.new(math.sin(a), 0, math.cos(a))
		local at = O + dirv * (A + WorldLayout.ROAD_W / 4)
		local tangent = Vector3.new(dirv.Z, 0, -dirv.X)
		table.insert(sideStops, nearestS(p, at + tangent * 22))
	end
	spawnTraffic()
	readSpots()
	readParked()
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
	local parkedClock = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		sensorClock += dt
		spotClock += dt
		parkedClock += dt
		if sensorClock >= 0.1 then
			sensorClock = 0
			refreshBlockers()
		end
		-- (v9.9) à chaque image : mouvement lisse (dt borné)
		local ok, err = pcall(stepTraffic, math.min(dt, 0.1), cameraPos())
		if not ok then
			warn("[TownTraffic] " .. tostring(err))
		end
		if parkedClock >= 5 then
			-- (les voitures du serveur peuvent arriver après nous)
			parkedClock = 0
			local count0 = #parked
			local n = 0
			local t = townFolder()
			if t then
				for _, d in ipairs(t:GetDescendants()) do
					if d:IsA("Model") and d:GetAttribute("CarKind") then
						n += 1
					end
				end
			end
			if n ~= count0 then
				readParked()
			end
		end
		if spotClock >= 0.5 then
			spotClock = 0
			local center = focusPos()
			if center then
				local okS, errS = pcall(stepSpots, center)
				if not okS then
					warn("[TownTraffic] " .. tostring(errS))
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
	for _, pk in ipairs(parked) do
		if pk.Server.Parent then
			setLocalHidden(pk.Server, false)
		end
	end
	table.clear(parked)
	table.clear(vehicles)
	table.clear(spots)
	table.clear(blockers)
	path = nil
	zebra = nil
	busStopS = nil
	table.clear(sideStops)
	focus = nil
	sensorClock, spotClock = 0, 0
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
		Parked = parked,
		Path = function()
			return path
		end,
		Zebra = function()
			return zebra
		end,
		SideStops = sideStops,
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
