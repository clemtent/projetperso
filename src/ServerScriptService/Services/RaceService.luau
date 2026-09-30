--[[
	RaceService (ModuleScript)
	Emplacement : ServerScriptService > Services > RaceService

	🏁 Courses de rue de Dopamine Town (v10, RACE10). Tout est décidé ICI
	(le client n'annonce jamais ni porte, ni temps, ni place) :
	  - 4 parcours (Config.Race.Routes, géométrie : Shared/RaceRoutes, sur le
	    graphe des rues de LAYOUT10) ; une course à la fois par parcours ;
	  - INSCRIPTION ("join") au QG des courses (à pied, touche E, à moins de
	    Config.Race.JoinRange studs) ou au volant de sa voiture (bouton 🏁
	    du HUD) ; salle d'attente de LobbySeconds (une inscription tardive
	    laisse au moins LateJoinSeconds), 1 à 8 humains, des pilotes IA
	    complètent la grille jusqu'à MinGrid voitures ;
	  - GRILLE : chaque humain est posé à sa place au volant de SA voiture
	    choisie (CarService:RaceSpawn ; sans voiture : une citadine prêtée),
	    voitures GELÉES (CarService:SetFrozen) pendant le 3-2-1 (heure du
	    serveur : les feux sont synchronisés chez tout le monde), puis GO ;
	  - COURSE (10 fois / s) : position de chaque voiture projetée sur la
	    trajectoire -> distance parcourue, portes dans l'ORDRE (largeur de la
	    porte vérifiée), tours, meilleur tour ; ANTI-TRICHE : vitesse
	    plausible sur ~1 s (vitesse de pointe de SA voiture x 1,3), saut
	    instantané -> remis à la dernière porte (3e fois : disqualifié),
	    tronçon plus rapide que possible -> disqualifié (pas de récompense),
	    hors de sa voiture plus de OffCarGrace s -> abandon ;
	  - PILOTES IA simulés ici (profil de vitesse de la trajectoire,
	    habileté 0,90..0,97, voitures d'un niveau proche de celui des
	    humains, élastique léger et JAMAIS au-delà de leur vitesse de pointe,
	    coupé dans les 12 % finaux ; ils changent de file pour doubler un
	    humain au lieu de le traverser). Les clients les dessinent (RaceClient)
	    d'après les instantanés (5 fois / s) ;
	  - ARRIVÉE / RÉSULTATS : classement, RÉCOMPENSE en Dopamine (secondes
	    de production selon la place, adversaires humains, plafond
	    quotidien : RaceRules.Reward), records par parcours (data.Race.Best
	    + tableau du serveur, affiché au QG), voiture prêtée rendue.
	  - Circulation : l'attribut "DopamineRaceRoutes" de Workspace liste les
	    parcours en course (TownTraffic évite leurs rues : RaceRoutes.BlockedEdgeKeys).
	Tout est dans des pcall ; chaque demande a sa limite de fréquence.

	Données : data.Race = { Day, Rewarded, Races, Wins, Podiums, Best = { [routeId] = s } }.
	RemoteEvent "RaceEvent" :
	  C -> S : ("join", routeId) | ("leave") | ("reset") | ("sync")
	  S -> C : ("Lobbies", { [routeId] = { Phase, Count, Names, EndsAt } })
	           ("Board", { [routeId] = { { Name, UserId, Time, CarId } } })
	           ("Joined", { Route, RaceId }) | ("Left", { Route })
	           ("State", instantané) (5 fois / s aux joueurs en ville près d'une course)
	           ("Result", { Route, RaceId, Rows, Mine }) | ("Toast", texte) | ("Reset", { D })
	           ("Grid", { Route, RaceId, GoAt, Slot }) | ("Finished", { Route, Time })
	           ("Me", { Rewarded, Daily, Best, Wins, Races, Podiums })
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local CarModels = require(ReplicatedStorage.Shared.CarModels)
local RaceRules = require(ReplicatedStorage.Shared.RaceRules)
local RaceRoutes = require(ReplicatedStorage.Shared.RaceRoutes)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local RateLimiter = require(script.Parent.RateLimiter)

local RaceService = {}

local TICK = 0.1
local SNAPSHOT_EVERY = 0.2
local RESULTS_HOLD = 9 -- s d'affichage des résultats avant de rouvrir le parcours
local PROJECT_WINDOW = 220
local BOARD_SIZE = 8

type Racer = {
	Key: string,
	Player: Player?,
	UserId: number,
	Name: string,
	IsAI: boolean,
	CarId: string,
	Color: string,
	Top: number,
	Accel: number,
	Rating: number,
	Slot: number,
	D: number,
	S: number,
	Lat: number,
	V: number,
	Next: number,
	LastCpD: number,
	Finished: boolean,
	FinishTime: number?,
	Dnf: boolean,
	DnfReason: string?,
	Strikes: number,
	Suspicious: boolean,
	Samples: { { number } }, -- { t, x, z }
	SegStart: number,
	LapStart: number,
	BestLap: number?,
	OffCarSince: number?,
	IgnoreUntil: number,
	LastReset: number,
	-- IA
	Skill: number,
	Lane: number,
	LaneGoal: number,
	Profile: { number }?,
	Place: number,
}

type Race = {
	Id: number,
	RouteId: string,
	Route: any,
	Phase: string, -- "Lobby" | "Grid" | "Countdown" | "Racing" | "Results"
	Racers: { Racer },
	ByPlayer: { [Player]: Racer },
	LobbyEnds: number,
	GoAt: number,
	FirstFinish: number?,
	EndsAt: number,
	PhaseAt: number,
	Results: any?,
}

local services: any = nil
local races: { [string]: Race } = {}
local playerRace: { [Player]: Race } = {}
local board: { [string]: { { Name: string, UserId: number, Time: number, CarId: string } } } = {}
local raceCounter = 0
local lobbiesDirty = true
local boardDirty = true
local profiles: { [string]: { number } } = {}

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.clock()
end

local function T(player: Player, text: string, ...): string
	if services and services.GameService then
		return services.GameService:T(player, text, ...)
	end
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
end

local function dataOf(player: Player): any
	return services and services.DataService and services.DataService:GetData(player) or nil
end

local function plotCount(): number
	return WorldLayout.PlotCount(Players.MaxPlayers)
end

local function inTown(player: Player): boolean
	local world = services and services.WorldService
	if world and type(world.IsInTown) == "function" then
		local ok, result = pcall(world.IsInTown, world, player)
		return ok and result == true
	end
	return false
end

local function fire(player: Player, kind: string, payload: any)
	pcall(function()
		Net.Event("RaceEvent"):FireClient(player, kind, payload)
	end)
end

local function townPlayers(): { Player }
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if inTown(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function toast(player: Player, text: string)
	fire(player, "Toast", text)
end

local raceData: (player: Player) -> any

-- Ses chiffres (menu : courses payées aujourd'hui, records, victoires)
local function pushMe(player: Player)
	local rd = raceData(player)
	if rd then
		local daily = (Config.Race and Config.Race.Rewards and Config.Race.Rewards.DailyRewarded) or 8
		fire(player, "Me", { Rewarded = rd.Rewarded, Daily = daily, Best = rd.Best, Wins = rd.Wins, Races = rd.Races, Podiums = rd.Podiums })
	end
end

raceData = function(player: Player): any?
	local data = dataOf(player)
	if type(data) ~= "table" then
		return nil
	end
	data.Race = RaceRules.SanitizeData(data.Race, RaceRules.Today(os.time()))
	return data.Race
end

-- Voiture pilotée : (modèle, racine, au volant ?)
local function carOf(player: Player): (Model?, BasePart?, boolean)
	local cs = services and services.CarService
	if not cs or type(cs.GetCar) ~= "function" then
		return nil, nil, false
	end
	local ok, model = pcall(cs.GetCar, cs, player)
	if not ok or not model or not model.Parent then
		return nil, nil, false
	end
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	local seat = model:FindFirstChild("DriverSeat", true)
	local driving = false
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if seat and seat:IsA("VehicleSeat") and humanoid then
		driving = seat.Occupant == humanoid
	end
	if root and not root:IsA("BasePart") then
		root = nil
	end
	return model, root :: BasePart?, driving
end

-- Performances de la voiture d'un humain (celle qu'il conduit, avec sa préparation)
local function statsOf(player: Player): any
	local model = carOf(player)
	local carId = model and model:GetAttribute("CarId")
	local cs = services and services.CarService
	local stats = nil
	if cs and type(cs.GetStats) == "function" then
		local ok, s = pcall(cs.GetStats, cs, player, if type(carId) == "string" then carId else nil)
		if ok and type(s) == "table" then
			stats = s
		end
	end
	if not stats then
		stats = CarModels.Stats(if type(carId) == "string" then carId else "CityCar", nil)
	end
	return stats
end

local function profileFor(race: Race, top: number): { number }
	local key = race.RouteId .. ":" .. tostring(math.floor(top + 0.5))
	local p = profiles[key]
	if not p then
		p = RaceRules.SpeedProfile(race.Route.Line, math.floor(top + 0.5))
		profiles[key] = p
	end
	return p
end

local function lineS(race: Race, d: number): number
	local route = race.Route
	if route.Closed then
		return d % route.Total
	end
	return route.StartS + d
end

----------------------------------------------------------------------
-- Tableau des records (serveur) + salles d'attente
----------------------------------------------------------------------

local function recordBest(routeId: string, player: Player, time: number, carId: string)
	local list = board[routeId] or {}
	board[routeId] = list
	for i, row in ipairs(list) do
		if row.UserId == player.UserId then
			if time >= row.Time then
				return
			end
			table.remove(list, i)
			break
		end
	end
	table.insert(list, { Name = player.DisplayName, UserId = player.UserId, Time = time, CarId = carId })
	table.sort(list, function(a, b)
		return a.Time < b.Time
	end)
	while #list > BOARD_SIZE do
		table.remove(list)
	end
	boardDirty = true
end

local function lobbiesPayload(): any
	local out = {}
	for id, race in pairs(races) do
		local names = {}
		for _, r in ipairs(race.Racers) do
			if not r.IsAI then
				table.insert(names, r.Name)
			end
		end
		out[id] = { Phase = race.Phase, Count = #names, Names = names, EndsAt = race.LobbyEnds, RaceId = race.Id }
	end
	return out
end

local function pushLobbies(target: Player?)
	local payload = lobbiesPayload()
	if target then
		fire(target, "Lobbies", payload)
		return
	end
	for _, p in ipairs(townPlayers()) do
		fire(p, "Lobbies", payload)
	end
end

local function pushBoard(target: Player?)
	if target then
		fire(target, "Board", board)
		return
	end
	for _, p in ipairs(townPlayers()) do
		fire(p, "Board", board)
	end
end

local function setActiveAttribute()
	local ids = {}
	for id, race in pairs(races) do
		if race.Phase == "Grid" or race.Phase == "Countdown" or race.Phase == "Racing" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	pcall(function()
		workspace:SetAttribute(RaceRoutes.ACTIVE_ATTRIBUTE, table.concat(ids, ","))
	end)
end

----------------------------------------------------------------------
-- Instantané (clients)
----------------------------------------------------------------------

local function snapshot(race: Race): any
	local rows = {}
	for _, r in ipairs(race.Racers) do
		table.insert(rows, {
			K = r.Key,
			N = r.Name,
			U = r.UserId,
			AI = r.IsAI,
			C = r.CarId,
			Col = r.Color,
			D = math.floor(r.D * 10) / 10,
			V = math.floor(r.V * 10) / 10,
			L = math.floor((if r.IsAI then r.Lane else r.Lat) * 10) / 10,
			Nx = r.Next,
			Pl = r.Place,
			F = r.Finished,
			T = r.FinishTime,
			X = r.Dnf,
			B = r.BestLap,
		})
	end
	return {
		Id = race.Id,
		Route = race.RouteId,
		Phase = race.Phase,
		GoAt = race.GoAt,
		Now = now(),
		EndsAt = race.EndsAt,
		Racers = rows,
	}
end

----------------------------------------------------------------------
-- Inscription / départ
----------------------------------------------------------------------

local function newRace(routeId: string): Race?
	local route = RaceRoutes.Get(routeId, plotCount())
	if not route then
		return nil
	end
	raceCounter += 1
	local race: Race = {
		Id = raceCounter,
		RouteId = routeId,
		Route = route,
		Phase = "Lobby",
		Racers = {},
		ByPlayer = {},
		LobbyEnds = now() + ((Config.Race and Config.Race.LobbySeconds) or 20),
		GoAt = 0,
		FirstFinish = nil,
		EndsAt = 0,
		PhaseAt = now(),
		Results = nil,
	}
	races[routeId] = race
	return race
end

local function newRacer(player: Player?, index: number): Racer
	return {
		Key = if player then "P" .. player.UserId else "AI" .. index,
		Player = player,
		UserId = if player then player.UserId else 0,
		Name = if player then player.DisplayName else "",
		IsAI = player == nil,
		CarId = "CityCar",
		Color = "",
		Top = 50,
		Accel = 24,
		Rating = 300,
		Slot = index,
		D = 0,
		S = 0,
		Lat = 0,
		V = 0,
		Next = 1,
		LastCpD = 0,
		Finished = false,
		FinishTime = nil,
		Dnf = false,
		DnfReason = nil,
		Strikes = 0,
		Suspicious = false,
		Samples = {},
		SegStart = 0,
		LapStart = 0,
		BestLap = nil,
		OffCarSince = nil,
		IgnoreUntil = 0,
		LastReset = 0,
		Skill = 1,
		Lane = 0,
		LaneGoal = 0,
		Profile = nil,
		Place = index,
	}
end

local function removeRacer(race: Race, player: Player)
	local racer = race.ByPlayer[player]
	race.ByPlayer[player] = nil
	playerRace[player] = nil
	if racer then
		local i = table.find(race.Racers, racer)
		if i then
			table.remove(race.Racers, i)
		end
	end
	lobbiesDirty = true
end

local function join(player: Player, routeId: any): (boolean, string?)
	if type(routeId) ~= "string" or not Config.RaceRoutesById[routeId] then
		return false, T(player, "Invalid request")
	end
	if not inTown(player) then
		return false, T(player, "Walk around the town first")
	end
	if raceData(player) == nil then
		return false, T(player, "Loading...")
	end
	local current = playerRace[player]
	if current then
		if current.RouteId == routeId then
			return true, nil
		end
		if current.Phase ~= "Lobby" then
			return false, T(player, "Finish your race first!")
		end
		removeRacer(current, player)
	end
	-- au QG (à pied) ou au volant de sa voiture
	local _, root, driving = carOf(player)
	local near = false
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local meet = RaceRoutes.MeetCFrame(plotCount()).Position
		local flat = Vector3.new(hrp.Position.X - meet.X, 0, hrp.Position.Z - meet.Z)
		near = flat.Magnitude <= ((Config.Race and Config.Race.JoinRange) or 45)
	end
	if not near and not (driving and root) then
		return false, T(player, "Join at the race meeting point, or from your car 🏁")
	end
	local race = races[routeId]
	if race and race.Phase ~= "Lobby" then
		return false, T(player, "A race is running on this route: try another one!")
	end
	if not race then
		race = newRace(routeId)
		if not race then
			return false, T(player, "This route is not available")
		end
	end
	local humans = 0
	for _, r in ipairs(race.Racers) do
		if not r.IsAI then
			humans += 1
		end
	end
	if humans >= ((Config.Race and Config.Race.MaxRacers) or 8) then
		return false, T(player, "This race is full")
	end
	local racer = newRacer(player, humans + 1)
	table.insert(race.Racers, racer)
	race.ByPlayer[player] = racer
	playerRace[player] = race
	local late = now() + ((Config.Race and Config.Race.LateJoinSeconds) or 8)
	if race.LobbyEnds < late then
		race.LobbyEnds = late
	end
	lobbiesDirty = true
	fire(player, "Joined", { Route = routeId, RaceId = race.Id, EndsAt = race.LobbyEnds })
	return true, nil
end

-- Pilotes IA : voitures d'un niveau proche de celui des humains
local function addAI(race: Race)
	local cfgRace = Config.Race or {}
	local ai = cfgRace.AI or {}
	local want = (cfgRace.MinGrid or 4) - #race.Racers
	if want <= 0 then
		return
	end
	local ratings = {}
	for _, r in ipairs(race.Racers) do
		table.insert(ratings, r.Rating)
	end
	table.sort(ratings)
	local target = ratings[math.max(1, math.ceil(#ratings / 2))] or 300
	local kinds = {}
	for _, kind in ipairs(CarModels.Kinds or {}) do
		local s = CarModels.Stats(kind, nil)
		table.insert(kinds, { Kind = kind, Rating = s.Rating })
	end
	table.sort(kinds, function(a, b)
		return math.abs(a.Rating - target) < math.abs(b.Rating - target)
	end)
	local colors = (Config.Cars and Config.Cars.Colors) or {}
	local names = ai.Names or { "Nina" }
	local skills = ai.Skill or { 0.93 }
	local seed = race.Id * 7 + #race.Route.Line.X
	for k = 1, want do
		local index = #race.Racers + 1
		local racer = newRacer(nil, index)
		local pick = kinds[((k - 1) % math.max(1, math.min(3, #kinds))) + 1]
		local kind = pick and pick.Kind or "CityCar"
		local stats = CarModels.Stats(kind, nil)
		racer.CarId = kind
		racer.Color = colors[((seed + k * 5) % math.max(1, #colors)) + 1] and colors[((seed + k * 5) % math.max(1, #colors)) + 1].Id or ""
		racer.Name = "🤖 " .. names[((seed + k) % #names) + 1]
		racer.Top = stats.TopSpeed
		racer.Accel = stats.Accel
		racer.Rating = stats.Rating
		racer.Skill = skills[((seed + k * 3) % #skills) + 1]
		table.insert(race.Racers, racer)
	end
end

local function startGrid(race: Race)
	race.Phase = "Grid"
	race.PhaseAt = now()
	lobbiesDirty = true
	local cs = services and services.CarService
	-- humains : à leur place au volant, voitures gelées
	local slot = 0
	for _, racer in ipairs(table.clone(race.Racers)) do
		local player = racer.Player
		if player then
			local ok, message = false, nil
			if player.Parent and inTown(player) and cs and type(cs.RaceSpawn) == "function" then
				slot += 1
				racer.Slot = slot
				local okCall, a, b = pcall(cs.RaceSpawn, cs, player, RaceRoutes.GridCFrame(race.Route, slot))
				ok, message = okCall and a == true, if okCall then b else tostring(a)
			end
			if not ok then
				slot -= 1
				removeRacer(race, player)
				fire(player, "Left", { Route = race.RouteId })
				if player.Parent then
					toast(player, T(player, "Could not start the race: %s", tostring(message or "?")))
				end
			else
				pcall(cs.SetFrozen, cs, player, true)
				local stats = statsOf(player)
				local model = carOf(player)
				racer.CarId = model and tostring(model:GetAttribute("CarId") or stats.CarId) or stats.CarId
				racer.Top = RaceRules.Finite(stats.TopSpeed, 50)
				racer.Accel = RaceRules.Finite(stats.Accel, 24)
				racer.Rating = RaceRules.Finite(stats.Rating, 300)
			end
		end
	end
	if next(race.ByPlayer) == nil then
		races[race.RouteId] = nil
		lobbiesDirty = true
		setActiveAttribute()
		return
	end
	addAI(race)
	-- IA : places restantes de la grille
	for _, racer in ipairs(race.Racers) do
		if racer.IsAI then
			slot += 1
			racer.Slot = slot
			local g = race.Route.Grid[math.clamp(slot, 1, #race.Route.Grid)]
			racer.D = -g.Back
			local side = if (slot - 1) % 2 == 0 then -RaceRoutes.GRID_SIDE else RaceRoutes.GRID_SIDE
			racer.Lane = side
			racer.LaneGoal = side
			racer.Profile = profileFor(race, racer.Top)
		end
	end
	-- humains : distance de départ (derrière la ligne)
	for _, racer in ipairs(race.Racers) do
		if not racer.IsAI then
			local g = race.Route.Grid[math.clamp(racer.Slot, 1, #race.Route.Grid)]
			racer.D = -g.Back
			racer.S = lineS(race, racer.D)
		end
	end
	setActiveAttribute()
	local cfgRace = Config.Race or {}
	race.GoAt = now() + (cfgRace.GridSeconds or 3) + (cfgRace.CountdownSeconds or 3)
	race.EndsAt = race.GoAt + (cfgRace.MaxSeconds or 480)
	for player in pairs(race.ByPlayer) do
		fire(player, "Grid", { Route = race.RouteId, RaceId = race.Id, GoAt = race.GoAt, Slot = race.ByPlayer[player].Slot })
	end
end

local function go(race: Race)
	race.Phase = "Racing"
	race.PhaseAt = now()
	local cs = services and services.CarService
	for player, racer in pairs(race.ByPlayer) do
		racer.SegStart = race.GoAt
		racer.LapStart = race.GoAt
		racer.IgnoreUntil = race.GoAt + 0.5
		table.clear(racer.Samples)
		if cs and type(cs.SetFrozen) == "function" then
			pcall(cs.SetFrozen, cs, player, false)
		end
	end
	for _, racer in ipairs(race.Racers) do
		racer.SegStart = race.GoAt
		racer.LapStart = race.GoAt
	end
	lobbiesDirty = true
end

----------------------------------------------------------------------
-- Pendant la course
----------------------------------------------------------------------

local function dnf(race: Race, racer: Racer, reason: string)
	if racer.Finished or racer.Dnf then
		return
	end
	racer.Dnf = true
	racer.DnfReason = reason
	local player = racer.Player
	if player and player.Parent then
		toast(player, T(player, reason))
	end
end

-- Porte franchie (dans l'ordre) : temps minimal du tronçon, tour, arrivée
local function passCheckpoints(race: Race, racer: Racer, t: number)
	local cps = race.Route.Checkpoints
	while racer.Next <= #cps do
		local cp = cps[racer.Next]
		if racer.D < cp.D - 1 then
			break
		end
		if math.abs(racer.Lat) > cp.W / 2 + 6 then
			-- à côté de la porte : il faut revenir la prendre
			break
		end
		local seg = cp.D - racer.LastCpD
		if not racer.IsAI and t - racer.SegStart < RaceRules.MinSegmentTime(seg, racer.Top) then
			racer.Suspicious = true
		end
		racer.LastCpD = cp.D
		racer.SegStart = t
		racer.Next += 1
		-- tour bouclé (boucle : la porte de la ligne de départ)
		if race.Route.Closed and (cp.S < 1 or cp.Finish) then
			local lap = t - racer.LapStart
			racer.LapStart = t
			if lap > 3 and (racer.BestLap == nil or lap < (racer.BestLap :: number)) then
				racer.BestLap = lap
			end
		end
		if cp.Finish then
			racer.Finished = true
			racer.FinishTime = t - race.GoAt
			if not race.Route.Closed then
				racer.BestLap = racer.FinishTime
			end
			if not racer.IsAI and race.FirstFinish == nil then
				race.FirstFinish = t
			end
			local player = racer.Player
			if player then
				fire(player, "Finished", { Route = race.RouteId, Time = racer.FinishTime })
			end
			break
		end
	end
end

local function updateHuman(race: Race, racer: Racer, t: number)
	local player = racer.Player :: Player
	if not player.Parent or not inTown(player) then
		dnf(race, racer, "You left the race")
		return
	end
	local _, root, driving = carOf(player)
	if not driving or not root then
		racer.OffCarSince = racer.OffCarSince or t
		if t - (racer.OffCarSince :: number) > ((Config.Race and Config.Race.OffCarGrace) or 5) then
			dnf(race, racer, "You left your car: race over")
		end
		racer.V = 0
		return
	end
	racer.OffCarSince = nil
	local origin = WorldLayout.Origin()
	local x, z = root.Position.X - origin.X, root.Position.Z - origin.Z
	local anti = (Config.Race and Config.Race.Anti) or {}
	-- saut / vitesse (fenêtre d'~1 s)
	local samples = racer.Samples
	local last = samples[#samples]
	if t >= racer.IgnoreUntil and last then
		local jump = math.sqrt((x - last[2]) ^ 2 + (z - last[3]) ^ 2)
		if RaceRules.CheckMove(jump, t - last[1], racer.Top) == "teleport" then
			warn(string.format("[RaceService] %s : saut de %.0f studs en %.2f s (%.0f, %.0f) -> (%.0f, %.0f)", player.Name, jump, t - last[1], last[2], last[3], x, z))
			racer.Strikes += 1
			table.clear(samples)
			if racer.Strikes >= (anti.MaxStrikes or 3) then
				racer.Suspicious = true
				dnf(race, racer, "Disqualified: impossible moves")
				return
			end
			-- remis à la dernière porte
			local cs = services and services.CarService
			if cs and type(cs.RaceSpawn) == "function" then
				pcall(cs.RaceSpawn, cs, player, RaceRoutes.CFrameAtD(race.Route, racer.LastCpD - 6))
			end
			racer.D = racer.LastCpD - 6
			racer.S = lineS(race, racer.D)
			racer.IgnoreUntil = t + 1
			toast(player, T(player, "Back to the last checkpoint"))
			return
		end
	end
	table.insert(samples, { t, x, z })
	while #samples > 2 and t - samples[1][1] > 1.2 do
		table.remove(samples, 1)
	end
	local first = samples[1]
	local span = t - first[1]
	if span >= 0.5 and t >= racer.IgnoreUntil then
		local dist = math.sqrt((x - first[2]) ^ 2 + (z - first[3]) ^ 2)
		racer.V = dist / span
		if RaceRules.CheckMove(dist, span, racer.Top) == "fast" then
			racer.Suspicious = true
		end
	end
	-- progression sur la trajectoire
	local route = race.Route
	local s, lat, off = RaceRules.Project(route.Line, x, z, racer.S, PROJECT_WINDOW)
	if off > route.Width / 2 + 60 then
		return -- perdu loin de la route : la progression attend
	end
	racer.Lat = lat
	if route.Closed then
		local delta = s - racer.S
		local half = route.Total / 2
		if delta > half then
			delta -= route.Total
		elseif delta < -half then
			delta += route.Total
		end
		racer.D += delta
	else
		racer.D = s - route.StartS
	end
	racer.S = s
	passCheckpoints(race, racer, t)
end

local function updateAI(race: Race, racer: Racer, t: number, dt: number, leadD: number?)
	local route = race.Route
	local profile = racer.Profile or profileFor(race, racer.Top)
	racer.Profile = profile
	local s = lineS(race, racer.D)
	local target = RaceRules.ProfileAt(route.Line, profile, s) * racer.Skill * RaceRules.RubberBand(racer.D, leadD, route.RaceDistance)
	-- un humain juste devant dans la même file : on change de file (ou on suit)
	local halfRoad = math.max(4, route.Width / 2 - 3)
	local blocked = false
	for _, other in ipairs(race.Racers) do
		if other ~= racer and not other.Dnf and not other.Finished then
			local gap = other.D - racer.D
			if gap > 0 and gap < 24 and math.abs((if other.IsAI then other.Lane else other.Lat) - racer.Lane) < 4.6 then
				blocked = true
				local otherLat = if other.IsAI then other.Lane else other.Lat
				racer.LaneGoal = math.clamp(if otherLat > 0 then otherLat - 6 else otherLat + 6, -halfRoad, halfRoad)
				if gap < 12 then
					target = math.min(target, other.V)
				end
			end
		end
	end
	if not blocked and math.abs(racer.LaneGoal) > 0.1 and t - race.GoAt > 4 then
		-- retour doux vers la trajectoire
		racer.LaneGoal *= 0.98
	end
	racer.Lane += math.clamp(racer.LaneGoal - racer.Lane, -3 * dt, 3 * dt)
	local before = racer.D
	RaceRules.AIStep(racer :: any, dt, target, racer.Top, racer.Accel, (Config.Race and Config.Race.AI and Config.Race.AI.Brake) or 38)
	racer.Lat = racer.Lane
	racer.S = lineS(race, racer.D)
	-- portes (l'IA reste sur sa trajectoire : largeur toujours bonne)
	if racer.D > before then
		local cps = route.Checkpoints
		while racer.Next <= #cps and racer.D >= cps[racer.Next].D do
			local cp = cps[racer.Next]
			racer.Next += 1
			racer.LastCpD = cp.D
			if cp.Finish then
				racer.Finished = true
				-- instant exact du franchissement (interpolé)
				local frac = if racer.D > before then (cp.D - before) / (racer.D - before) else 1
				racer.FinishTime = (t - dt + dt * math.clamp(frac, 0, 1)) - race.GoAt
				break
			end
		end
	end
end

local function rank(race: Race)
	local rows = {}
	for _, r in ipairs(race.Racers) do
		local cps = race.Route.Checkpoints
		local cap = if r.Next <= #cps then cps[r.Next].D else race.Route.RaceDistance
		table.insert(rows, { Key = r.Key, Racer = r, Finished = r.Finished, FinishTime = r.FinishTime, Progress = math.min(r.D, cap + 0.5), Dnf = r.Dnf })
	end
	for place, row in ipairs(RaceRules.Standings(rows)) do
		row.Racer.Place = place
	end
end

----------------------------------------------------------------------
-- Fin de course : classement, récompenses, records
----------------------------------------------------------------------

local function finish(race: Race)
	race.Phase = "Results"
	race.PhaseAt = now()
	rank(race)
	local humans = 0
	for _, r in ipairs(race.Racers) do
		if not r.IsAI then
			humans += 1
		end
	end
	local rows = {}
	local ordered = table.clone(race.Racers)
	table.sort(ordered, function(a, b)
		return a.Place < b.Place
	end)
	local cs = services and services.CarService
	local mine: { [Player]: any } = {}
	for _, r in ipairs(ordered) do
		local reward, seconds, capped = 0, 0, false
		local player = r.Player
		if player and player.Parent then
			local rd = raceData(player)
			if rd then
				if not r.Suspicious then
					local stats = services and services.GameService and services.GameService:GetStats(player)
					reward, seconds, capped = RaceRules.Reward(stats, r.Place, r.Finished, humans - 1, rd.Rewarded)
				end
				if reward > 0 and services and services.GameService then
					services.GameService:AddDopamine(player, reward)
					rd.Rewarded += 1
				end
				rd.Races += 1
				if r.Finished and not r.Suspicious then
					if r.Place == 1 then
						rd.Wins += 1
					end
					if r.Place <= 3 then
						rd.Podiums += 1
					end
					local best = r.BestLap
					if best and best > 3 then
						local old = rd.Best[race.RouteId]
						if old == nil or best < old then
							rd.Best[race.RouteId] = best
						end
						recordBest(race.RouteId, player, best, r.CarId)
					end
				end
				if services and services.GameService then
					services.GameService:MarkDirty(player)
				end
			end
			mine[player] = { Place = r.Place, Reward = reward, Seconds = seconds, Capped = capped, Suspicious = r.Suspicious,
				Left = math.max(0, ((Config.Race and Config.Race.Rewards and Config.Race.Rewards.DailyRewarded) or 8) - (rd and rd.Rewarded or 0)) }
		end
		table.insert(rows, {
			Place = r.Place,
			Name = r.Name,
			UserId = r.UserId,
			AI = r.IsAI,
			CarId = r.CarId,
			Color = r.Color,
			Time = r.FinishTime,
			BestLap = r.BestLap,
			Finished = r.Finished,
			Dnf = r.Dnf,
			Reward = if player then (mine[player] and mine[player].Reward or 0) else 0,
		})
	end
	race.Results = rows
	for player, racer in pairs(race.ByPlayer) do
		if cs and type(cs.RaceRelease) == "function" then
			pcall(cs.RaceRelease, cs, player)
		end
		local m = mine[player] or { Place = racer.Place, Reward = 0 }
		if player.Parent then
			fire(player, "Result", { Route = race.RouteId, RaceId = race.Id, Rows = rows, Mine = m, Humans = humans })
			pushMe(player)
			if m.Reward and m.Reward > 0 then
				toast(player, T(player, "🏁 +%s Dopamine!", NumberFormatter.Format(m.Reward)))
			elseif m.Capped then
				toast(player, T(player, "Daily race rewards reached: records still count!"))
			end
		end
		playerRace[player] = nil
	end
	table.clear(race.ByPlayer)
	lobbiesDirty = true
	setActiveAttribute()
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function stepRace(race: Race, dt: number)
	local t = now()
	local cfgRace = Config.Race or {}
	if race.Phase == "Lobby" then
		-- humains partis
		for _, r in ipairs(table.clone(race.Racers)) do
			local p = r.Player
			if p and (not p.Parent or not inTown(p)) then
				removeRacer(race, p)
			end
		end
		if #race.Racers == 0 then
			races[race.RouteId] = nil
			lobbiesDirty = true
			return
		end
		if t >= race.LobbyEnds or #race.Racers >= (cfgRace.MaxRacers or 8) then
			startGrid(race)
		end
	elseif race.Phase == "Grid" then
		if t >= race.GoAt - (cfgRace.CountdownSeconds or 3) then
			race.Phase = "Countdown"
			race.PhaseAt = t
		end
	elseif race.Phase == "Countdown" then
		if t >= race.GoAt then
			go(race)
		end
	elseif race.Phase == "Racing" then
		local leadD: number? = nil
		for _, r in ipairs(race.Racers) do
			if not r.IsAI and not r.Dnf and not r.Finished then
				updateHuman(race, r, t)
			end
		end
		for _, r in ipairs(race.Racers) do
			if not r.IsAI and not r.Dnf then
				local d = if r.Finished then race.Route.RaceDistance else r.D
				if leadD == nil or d > (leadD :: number) then
					leadD = d
				end
			end
		end
		for _, r in ipairs(race.Racers) do
			if r.IsAI and not r.Finished then
				updateAI(race, r, t, dt, leadD)
			end
		end
		rank(race)
		-- fin : tous les humains arrivés / abandonnés, délai après le 1er, durée max
		local running = false
		for _, r in ipairs(race.Racers) do
			if not r.IsAI and not r.Finished and not r.Dnf then
				running = true
			end
		end
		local graceOver = race.FirstFinish ~= nil and t - (race.FirstFinish :: number) > (cfgRace.FinishGrace or 35)
		if not running or graceOver or t >= race.EndsAt then
			for _, r in ipairs(race.Racers) do
				if not r.Finished and not r.Dnf and not r.IsAI then
					dnf(race, r, "Time's up!")
				end
			end
			finish(race)
		end
	elseif race.Phase == "Results" then
		if t - race.PhaseAt > RESULTS_HOLD then
			races[race.RouteId] = nil
			lobbiesDirty = true
		end
	end
end

local snapClock = 0
local function tick(dt: number)
	for _, race in pairs(races) do
		local ok, err = pcall(stepRace, race, dt)
		if not ok then
			warn("[RaceService] " .. tostring(err))
		end
	end
	snapClock += dt
	if snapClock >= SNAPSHOT_EVERY then
		snapClock = 0
		local active = {}
		for _, race in pairs(races) do
			if race.Phase ~= "Lobby" then
				table.insert(active, snapshot(race))
			end
		end
		if #active > 0 then
			for _, p in ipairs(townPlayers()) do
				fire(p, "State", active)
			end
		end
		if lobbiesDirty then
			lobbiesDirty = false
			pushLobbies()
		end
		if boardDirty then
			boardDirty = false
			pushBoard()
		end
	end
end

----------------------------------------------------------------------
-- Demandes des clients
----------------------------------------------------------------------

local function leave(player: Player)
	local race = playerRace[player]
	if not race then
		return
	end
	if race.Phase == "Lobby" then
		removeRacer(race, player)
		fire(player, "Left", { Route = race.RouteId })
		return
	end
	local racer = race.ByPlayer[player]
	if racer and (race.Phase == "Racing" or race.Phase == "Grid" or race.Phase == "Countdown") then
		dnf(race, racer, "You left the race")
		local cs = services and services.CarService
		if cs and type(cs.RaceRelease) == "function" then
			pcall(cs.RaceRelease, cs, player)
		end
		race.ByPlayer[player] = nil
		playerRace[player] = nil
		fire(player, "Left", { Route = race.RouteId })
	end
end

local function resetToCheckpoint(player: Player)
	local race = playerRace[player]
	local racer = race and race.ByPlayer[player]
	if not race or not racer or race.Phase ~= "Racing" or racer.Finished or racer.Dnf then
		return
	end
	local t = now()
	if t - racer.LastReset < ((Config.Race and Config.Race.ResetCooldown) or 3) then
		return
	end
	racer.LastReset = t
	local cs = services and services.CarService
	if cs and type(cs.RaceSpawn) == "function" then
		local d = math.max(racer.LastCpD - 6, -RaceRoutes.GRID_FIRST)
		local ok = pcall(cs.RaceSpawn, cs, player, RaceRoutes.CFrameAtD(race.Route, d))
		if ok then
			racer.D = d
			racer.S = lineS(race, d)
			racer.Lat = 0
			racer.IgnoreUntil = t + 1
			table.clear(racer.Samples)
			fire(player, "Reset", { D = d })
		end
	end
end

local function onEvent(player: Player, kind: any, arg: any)
	if type(kind) ~= "string" then
		return
	end
	if not RateLimiter.Check(player, "Race_" .. kind, if kind == "sync" then 1 else 0.4) then
		return
	end
	if kind == "join" then
		local ok, message = join(player, arg)
		if not ok and message then
			toast(player, message)
		end
	elseif kind == "leave" then
		leave(player)
	elseif kind == "reset" then
		resetToCheckpoint(player)
	elseif kind == "sync" then
		pushLobbies(player)
		pushBoard(player)
		pushMe(player)
		local race = playerRace[player]
		if race then
			fire(player, "Joined", { Route = race.RouteId, RaceId = race.Id, EndsAt = race.LobbyEnds })
		end
	end
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function RaceService:Init(allServices)
	services = allServices
end

function RaceService:Start()
	pcall(function()
		workspace:SetAttribute(RaceRoutes.ACTIVE_ATTRIBUTE, "")
	end)
	-- parcours calculés d'avance (le 1er joueur n'attend pas)
	task.spawn(function()
		local ok, err = pcall(RaceRoutes.All, plotCount())
		if not ok then
			warn("[RaceService] Parcours : " .. tostring(err))
		end
	end)
	Net.Event("RaceEvent").OnServerEvent:Connect(function(player: Player, kind: any, arg: any)
		local ok, err = pcall(onEvent, player, kind, arg)
		if not ok then
			warn("[RaceService] Erreur pour " .. player.Name .. " : " .. tostring(err))
		end
	end)
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock >= TICK then
			local step = math.min(clock, 0.5)
			clock = 0
			tick(step)
		end
	end)
end

function RaceService:PlayerReady(player: Player, data)
	data.Race = RaceRules.SanitizeData(data.Race, RaceRules.Today(os.time()))
	-- ses records (sauvegardés) rejoignent le tableau du serveur
	for routeId, best in pairs(data.Race.Best) do
		recordBest(routeId, player, best, "")
	end
end

function RaceService:PlayerRemoving(player: Player)
	local race = playerRace[player]
	if race then
		pcall(leave, player)
		removeRacer(race, player)
	end
	playerRace[player] = nil
end

-- (tests / autres services) la course d'un joueur (id du parcours) ou nil
function RaceService:RaceOf(player: Player): string?
	local race = playerRace[player]
	return race and race.RouteId or nil
end

-- (tests) accès interne
function RaceService:Debug(): any
	return {
		Races = races,
		Board = board,
		Tick = tick,
		Join = join,
		Leave = leave,
		Reset = resetToCheckpoint,
		Now = now,
	}
end

return RaceService
