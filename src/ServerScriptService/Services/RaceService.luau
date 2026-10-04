--[[
	RaceService (ModuleScript)
	Emplacement : ServerScriptService > Services > RaceService

	🏁 Courses de rue de Dopamine Town (v10 RACE10, v11 RACE11). Tout est
	décidé ICI (le client n'annonce jamais ni porte, ni temps, ni place) :
	  - 7 parcours (Config.Race.Routes, géométrie : Shared/RaceRoutes, sur le
	    graphe des rues de LAYOUT10) ; une course à la fois par parcours ;
	  - INSCRIPTION ("join") au QG des courses (à pied, touche E, à moins de
	    Config.Race.JoinRange studs) ou au volant de sa voiture (bouton 🏁
	    du HUD) ; salle d'attente de LobbySeconds (une inscription tardive
	    laisse au moins LateJoinSeconds), 1 à 8 humains, des pilotes IA
	    complètent la grille jusqu'à MinGrid voitures ;
	  - GRILLE : chaque humain est posé à sa place au volant de SA voiture
	    choisie (CarService:RaceSpawn ; sans voiture : une citadine prêtée),
	    voitures GELÉES (CarService:SetFrozen) pendant la présentation et le
	    3-2-1 (heure du serveur : feux et caméra synchronisés), puis GO ;
	  - COURSE (10 fois / s) : position de chaque voiture projetée sur la
	    trajectoire -> distance parcourue, portes dans l'ORDRE (largeur de la
	    porte vérifiée), tours, meilleur tour, TEMPS DE PASSAGE (écart avec le
	    fantôme de ton meilleur tour, envoyé à chaque porte) ; ANTI-TRICHE :
	    vitesse plausible sur ~1 s (vitesse de pointe de SA voiture x 1,3,
	    nitro comprise pendant un boost), saut instantané -> remis à la
	    dernière porte (3e fois : disqualifié), tronçon plus rapide que
	    possible -> disqualifié (pas de récompense), hors de sa voiture plus
	    de OffCarGrace s -> abandon ;
	  - (v11) NITRO : charges données par le serveur (Config.Race.Nitro.Start
	    au départ) ; la jauge se remplit en DÉRAPANT (angle de glisse mesuré
	    ici d'après la position et le cap de la voiture) et dans l'ASPIRATION
	    d'une autre voiture ; "nitro" -> boost de BoostFactor pendant Seconds
	    (le client règle l'attribut local RaceBoost lu par CarClient) ;
	  - PILOTES IA simulés ici (profil de vitesse de la trajectoire,
	    habileté 0,90..0,97, voitures d'un niveau proche de celui des
	    humains, élastique léger et JAMAIS au-delà de leur vitesse de pointe,
	    coupé dans les 12 % finaux). (v11) Temps de réaction au départ,
	    aspiration, DÉPASSEMENTS (choix du côté le plus libre, file tenue
	    pendant le dépassement, retour sur la trajectoire ensuite), nitro
	    dans les lignes droites. Les clients les dessinent (RaceClient, avec
	    un pilote NPCModels.Driver) d'après les instantanés (5 fois / s) ;
	  - ARRIVÉE / RÉSULTATS : classement, RÉCOMPENSE en Dopamine (secondes
	    de production selon la place, adversaires humains, plafond
	    quotidien : RaceRules.Reward, inchangé), (v11) XP + rang, MÉDAILLE
	    du parcours (1re médaille d'or d'un parcours : 💎 1 diamant si la
	    banque existe, BankService:GrantDiamonds), records personnels, stats
	    par parcours, HISTORIQUE, FANTÔME du meilleur tour (temps de passage),
	    records du serveur (tableau du QG) et classement des pilotes (XP).
	  - SPECTATEURS ("watch") : instantanés 5 fois / s.
	  - Circulation : l'attribut "DopamineRaceRoutes" de Workspace liste les
	    parcours en course (TownTraffic évite leurs rues : RaceRoutes.BlockedEdgeKeys).
	Tout est dans des pcall ; chaque demande a sa limite de fréquence.

	Données : data.Race (RaceRules.SanitizeData) = { Day, Rewarded, Races,
	  Wins, Podiums, Best, Xp, History, Routes, Ghost, DriftBest, Overtakes, Distance }.
	RemoteEvent "RaceEvent" :
	  C -> S : ("join", routeId) | ("leave") | ("reset") | ("sync") | ("nitro")
	           | ("watch", routeId | nil)
	  S -> C : ("Lobbies", { [routeId] = { Phase, Count, Names, EndsAt } })
	           ("Board", { [routeId] = { { Name, UserId, Time, CarId } } })
	           ("Pilots", { { Name, UserId, Xp, Wins, Races } })
	           ("Joined", { Route, RaceId }) | ("Left", { Route })
	           ("State", instantanés) (5 fois / s aux coureurs / spectateurs, 2,5 aux autres)
	           ("Result", { Route, RaceId, Rows, Mine, Humans }) | ("Toast", texte) | ("Reset", { D })
	           ("Grid", { Route, RaceId, GoAt, Slot }) | ("Finished", { Route, Time })
	           ("Split", { Index, Time, Delta? }) | ("Lap", { Lap, Time, Best, Delta? })
	           ("Nitro", { Until, Charges })
	           ("Me", { Rewarded, Daily, Best, Wins, Races, Podiums, Xp, History, Routes, Ghost, ... })
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
local RESULTS_HOLD = 12 -- s d'affichage des résultats avant de rouvrir le parcours
local PROJECT_WINDOW = 220
local BOARD_SIZE = 8
local PILOTS_SIZE = 10

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
	LapStartD: number,
	LapSplits: { T: { number }, D: { number } },
	LastLap: number?,
	BestLap: number?,
	BestLapSplits: any?,
	OffCarSince: number?,
	IgnoreUntil: number,
	LastReset: number,
	-- (v11) nitro, dérapage, aspiration, dépassements
	Nitro: number,
	Gauge: number,
	BoostUntil: number,
	SegBoost: boolean,
	Drift: number,
	DriftCombo: number,
	DraftT: number,
	Overtakes: number,
	PrevPlace: number,
	PlaceSince: number,
	-- IA
	Skill: number,
	Lane: number,
	LaneGoal: number,
	PassTimer: number,
	Launch: number,
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
local watchers: { [Player]: string } = {}
local board: { [string]: { { Name: string, UserId: number, Time: number, CarId: string } } } = {}
local raceCounter = 0
local lobbiesDirty = true
local boardDirty = true
local pilotsDirty = true
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

local function cfgRace(): any
	return Config.Race or {}
end

local raceData: (player: Player) -> any

-- Ses chiffres (menu, page de stats, fantômes)
local function pushMe(player: Player)
	local rd = raceData(player)
	if rd then
		local daily = (cfgRace().Rewards or {}).DailyRewarded or 8
		fire(player, "Me", {
			Rewarded = rd.Rewarded,
			Daily = daily,
			Best = rd.Best,
			Wins = rd.Wins,
			Races = rd.Races,
			Podiums = rd.Podiums,
			Xp = rd.Xp,
			History = rd.History,
			Routes = rd.Routes,
			Ghost = rd.Ghost,
			DriftBest = rd.DriftBest,
			Overtakes = rd.Overtakes,
			Distance = rd.Distance,
		})
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

-- (v11) vitesse de pointe tolérée à l'instant t (boost de nitro compris, +1 s de marge)
local function topAt(racer: Racer, t: number): number
	if t < racer.BoostUntil + 1 then
		return racer.Top * RaceRules.BoostFactor()
	end
	return racer.Top
end

----------------------------------------------------------------------
-- Tableau des records (serveur), pilotes, salles d'attente
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

-- Pilotes présents classés par XP (tableau du QG, page "Classement")
local function pilotsPayload(): any
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local data = dataOf(p)
		local rd = type(data) == "table" and type(data.Race) == "table" and data.Race or nil
		if rd and ((rd.Xp or 0) > 0 or (rd.Races or 0) > 0) then
			table.insert(list, { Name = p.DisplayName, UserId = p.UserId, Xp = rd.Xp or 0, Wins = rd.Wins or 0, Races = rd.Races or 0 })
		end
	end
	table.sort(list, function(a, b)
		if a.Xp ~= b.Xp then
			return a.Xp > b.Xp
		end
		return a.UserId < b.UserId
	end)
	while #list > PILOTS_SIZE do
		table.remove(list)
	end
	return list
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
		out[id] = { Phase = race.Phase, Count = #names, Names = names, EndsAt = race.LobbyEnds, RaceId = race.Id, GoAt = race.GoAt }
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

local function pushPilots(target: Player?)
	local payload = pilotsPayload()
	if target then
		fire(target, "Pilots", payload)
		return
	end
	for _, p in ipairs(townPlayers()) do
		fire(p, "Pilots", payload)
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

local function round1(v: number): number
	return math.floor(v * 10 + 0.5) / 10
end

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
			D = round1(r.D),
			V = round1(r.V),
			L = round1(if r.IsAI then r.Lane else r.Lat),
			Nx = r.Next,
			Pl = r.Place,
			F = r.Finished,
			T = r.FinishTime,
			X = r.Dnf,
			B = r.BestLap,
			-- (v11)
			LL = r.LastLap,
			LS = r.LapStart,
			LD = round1(r.LapStartD),
			Ni = r.Nitro,
			Ga = math.floor(r.Gauge * 100) / 100,
			Bo = if r.BoostUntil > race.GoAt then r.BoostUntil else nil,
			Dr = math.floor(r.Drift),
			Ov = r.Overtakes,
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
		LobbyEnds = now() + (cfgRace().LobbySeconds or 20),
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
		LapStartD = 0,
		LapSplits = { T = {}, D = {} },
		LastLap = nil,
		BestLap = nil,
		BestLapSplits = nil,
		OffCarSince = nil,
		IgnoreUntil = 0,
		LastReset = 0,
		Nitro = (cfgRace().Nitro or {}).Start or 1,
		Gauge = 0,
		BoostUntil = 0,
		SegBoost = false,
		Drift = 0,
		DriftCombo = 0,
		DraftT = 0,
		Overtakes = 0,
		PrevPlace = index,
		PlaceSince = 0,
		Skill = 1,
		Lane = 0,
		LaneGoal = 0,
		PassTimer = 0,
		Launch = 0,
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
		near = flat.Magnitude <= (cfgRace().JoinRange or 45)
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
	if humans >= (cfgRace().MaxRacers or 8) then
		return false, T(player, "This race is full")
	end
	local racer = newRacer(player, humans + 1)
	table.insert(race.Racers, racer)
	race.ByPlayer[player] = racer
	playerRace[player] = race
	watchers[player] = nil
	local late = now() + (cfgRace().LateJoinSeconds or 8)
	if race.LobbyEnds < late then
		race.LobbyEnds = late
	end
	lobbiesDirty = true
	fire(player, "Joined", { Route = routeId, RaceId = race.Id, EndsAt = race.LobbyEnds })
	return true, nil
end

-- Pilotes IA : voitures d'un niveau proche de celui des humains
local function addAI(race: Race)
	local cfg = cfgRace()
	local ai = cfg.AI or {}
	local want = (cfg.MinGrid or 4) - #race.Racers
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
	local launch = ai.Launch or { 0.15, 0.45 }
	local seed = race.Id * 7 + #race.Route.Line.X
	for k = 1, want do
		local index = #race.Racers + 1
		local racer = newRacer(nil, index)
		local pick = kinds[((k - 1) % math.max(1, math.min(3, #kinds))) + 1]
		local kind = pick and pick.Kind or "CityCar"
		local stats = CarModels.Stats(kind, nil)
		racer.CarId = kind
		local color = colors[((seed + k * 5) % math.max(1, #colors)) + 1]
		racer.Color = color and color.Id or ""
		racer.Name = "🤖 " .. names[((seed + k) % #names) + 1]
		racer.Top = stats.TopSpeed
		racer.Accel = stats.Accel
		racer.Rating = stats.Rating
		racer.Skill = skills[((seed + k * 3) % #skills) + 1]
		-- temps de réaction au départ (déterministe)
		racer.Launch = launch[1] + (launch[2] - launch[1]) * (((seed * 13 + k * 29) % 100) / 100)
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
		racer.PrevPlace = racer.Slot
		racer.Place = racer.Slot
	end
	setActiveAttribute()
	local cfg = cfgRace()
	race.GoAt = now() + (cfg.GridSeconds or 3) + (cfg.CountdownSeconds or 3)
	race.EndsAt = race.GoAt + (cfg.MaxSeconds or 480)
	for player in pairs(race.ByPlayer) do
		fire(player, "Grid", { Route = race.RouteId, RaceId = race.Id, GoAt = race.GoAt, Slot = race.ByPlayer[player].Slot })
	end
end

local function go(race: Race)
	race.Phase = "Racing"
	race.PhaseAt = now()
	local cs = services and services.CarService
	for player, racer in pairs(race.ByPlayer) do
		racer.IgnoreUntil = race.GoAt + 0.5
		table.clear(racer.Samples)
		if cs and type(cs.SetFrozen) == "function" then
			pcall(cs.SetFrozen, cs, player, false)
		end
	end
	for _, racer in ipairs(race.Racers) do
		racer.SegStart = race.GoAt
		racer.LapStart = race.GoAt
		racer.LapStartD = 0
		racer.PlaceSince = race.GoAt
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

local function ghostOf(player: Player?, routeId: string): any?
	if not player then
		return nil
	end
	local data = dataOf(player)
	local rd = type(data) == "table" and type(data.Race) == "table" and data.Race or nil
	local g = rd and type(rd.Ghost) == "table" and rd.Ghost[routeId] or nil
	return if type(g) == "table" then g else nil
end

-- Porte franchie (dans l'ordre) : temps minimal du tronçon, temps de
-- passage (fantôme), tour, arrivée
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
		if not racer.IsAI then
			-- (v11) le boost de nitro est permis : tronçon jugé à la vitesse boostée
			local top = if racer.SegBoost or t < racer.BoostUntil + 1 then racer.Top * RaceRules.BoostFactor() else racer.Top
			if t - racer.SegStart < RaceRules.MinSegmentTime(seg, top) then
				racer.Suspicious = true
			end
		end
		racer.LastCpD = cp.D
		racer.SegStart = t
		racer.SegBoost = t < racer.BoostUntil
		local index = racer.Next
		racer.Next += 1
		-- temps de passage dans le tour (fantôme)
		local lapT = t - racer.LapStart
		local lapD = cp.D - racer.LapStartD
		table.insert(racer.LapSplits.T, lapT)
		table.insert(racer.LapSplits.D, lapD)
		local player = racer.Player
		local lapEnd = cp.LapEnd == true or cp.Finish == true
		if player and not lapEnd then
			local ghost = ghostOf(player, race.RouteId)
			local gt = ghost and RaceRules.GhostTimeAt(ghost, lapD)
			fire(player, "Split", { Index = index, Time = t - race.GoAt, Lap = lapT, Delta = if gt then lapT - gt else nil })
		end
		if lapEnd then
			local lap = t - racer.LapStart
			local valid = lap > 3
			local ghost = player and ghostOf(player, race.RouteId)
			if valid then
				racer.LastLap = lap
				if racer.BestLap == nil or lap < (racer.BestLap :: number) then
					racer.BestLap = lap
					racer.BestLapSplits = { T = table.clone(racer.LapSplits.T), D = table.clone(racer.LapSplits.D) }
				end
			end
			if player then
				fire(player, "Lap", {
					Lap = math.floor(cp.D / race.Route.Total + 0.5),
					Time = lap,
					Best = racer.BestLap,
					Delta = if ghost and ghost.Time then lap - ghost.Time else nil,
				})
			end
			racer.LapStart = t
			racer.LapStartD = cp.D
			racer.LapSplits = { T = {}, D = {} }
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
			if player then
				fire(player, "Finished", { Route = race.RouteId, Time = racer.FinishTime })
			end
			break
		end
	end
end

-- (v11) aspiration : y a-t-il une voiture 8..30 studs devant, dans la même file ?
local function drafting(race: Race, racer: Racer): boolean
	local myLat = if racer.IsAI then racer.Lane else racer.Lat
	for _, other in ipairs(race.Racers) do
		if other ~= racer and not other.Dnf and not other.Finished then
			local lat = if other.IsAI then other.Lane else other.Lat
			if RaceRules.InDraft(other.D - racer.D, lat - myLat) then
				return true
			end
		end
	end
	return false
end

local function gainNitro(racer: Racer, driftPoints: number, draftSeconds: number)
	racer.Nitro, racer.Gauge = RaceRules.NitroGain(racer.Nitro, racer.Gauge, driftPoints, draftSeconds)
end

local function updateHuman(race: Race, racer: Racer, t: number, dt: number)
	local player = racer.Player :: Player
	if not player.Parent or not inTown(player) then
		dnf(race, racer, "You left the race")
		return
	end
	local _, root, driving = carOf(player)
	if not driving or not root then
		racer.OffCarSince = racer.OffCarSince or t
		if t - (racer.OffCarSince :: number) > (cfgRace().OffCarGrace or 5) then
			dnf(race, racer, "You left your car: race over")
		end
		racer.V = 0
		return
	end
	racer.OffCarSince = nil
	local origin = WorldLayout.Origin()
	local x, z = root.Position.X - origin.X, root.Position.Z - origin.Z
	local anti = cfgRace().Anti or {}
	local top = topAt(racer, t)
	-- saut / vitesse (fenêtre d'~1 s)
	local samples = racer.Samples
	local last = samples[#samples]
	if t >= racer.IgnoreUntil and last then
		local jump = math.sqrt((x - last[2]) ^ 2 + (z - last[3]) ^ 2)
		if RaceRules.CheckMove(jump, t - last[1], top) == "teleport" then
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
			racer.DriftCombo = 0
			toast(player, T(player, "Back to the last checkpoint"))
			return
		end
	end
	-- (v11) dérapage : angle entre le cap de la voiture et son déplacement récent
	if last and t >= racer.IgnoreUntil then
		local sdt = t - last[1]
		if sdt > 0.05 and sdt < 0.5 then
			local vx, vz = (x - last[2]) / sdt, (z - last[3]) / sdt
			local speed = math.sqrt(vx * vx + vz * vz)
			local look = root.CFrame.LookVector
			local angle = RaceRules.SlipAngle(look.X, look.Z, vx, vz)
			local rate = RaceRules.DriftRate(angle, speed)
			if rate > 0 then
				racer.DriftCombo += rate * sdt
				racer.Drift += rate * sdt
				gainNitro(racer, rate * sdt, 0)
			else
				racer.DriftCombo = 0
			end
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
		if RaceRules.CheckMove(dist, span, top) == "fast" then
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
	-- (v11) aspiration
	if racer.V > 20 and drafting(race, racer) then
		racer.DraftT += dt
		gainNitro(racer, 0, dt)
	end
	passCheckpoints(race, racer, t)
end

local function updateAI(race: Race, racer: Racer, t: number, dt: number, leadD: number?)
	local route = race.Route
	local ai = cfgRace().AI or {}
	if t < race.GoAt + racer.Launch then
		return -- temps de réaction au départ
	end
	local profile = racer.Profile or profileFor(race, racer.Top)
	racer.Profile = profile
	local s = lineS(race, racer.D)
	local profV = RaceRules.ProfileAt(route.Line, profile, s)
	local target = profV * racer.Skill * RaceRules.RubberBand(racer.D, leadD, route.RaceDistance)
	local top = racer.Top
	-- (v11) nitro de l'IA : dans une ligne droite, derrière le 1er humain
	if racer.Nitro > 0 and t >= racer.BoostUntil and profV >= racer.Top * 0.97 and leadD ~= nil and racer.D < (leadD :: number)
		and racer.D > route.RaceDistance * 0.15 and racer.D < route.RaceDistance * (1 - (ai.FairFinish or 0.12)) then
		racer.Nitro -= 1
		racer.BoostUntil = t + ((cfgRace().Nitro or {}).Seconds or 2.6)
	end
	if t < racer.BoostUntil then
		top = racer.Top * RaceRules.BoostFactor()
		if profV >= racer.Top * 0.97 then
			-- (le boost ne sert qu'en ligne droite : les virages gardent leur vitesse)
			target = math.max(target, top)
		end
	end
	-- (v11) aspiration : petit gain de vitesse
	local inDraft = drafting(race, racer)
	if inDraft then
		target *= 1 + (ai.Draft or 0.04)
		racer.DraftT += dt
		gainNitro(racer, 0, dt)
	end
	-- (v11) DÉPASSEMENTS : une voiture plus lente devant dans ma file -> je
	-- choisis le côté le plus libre et je tiens ma file le temps de passer
	local halfRoad = math.max(4, route.Width / 2 - 3.2)
	local blocker: Racer? = nil
	local blockGap = math.huge
	for _, other in ipairs(race.Racers) do
		if other ~= racer and not other.Dnf and not other.Finished then
			local gap = other.D - racer.D
			local otherLat = if other.IsAI then other.Lane else other.Lat
			if gap > 0 and gap < 30 and math.abs(otherLat - racer.Lane) < 5.6 and gap < blockGap then
				blocker, blockGap = other, gap
			end
		end
	end
	if blocker then
		local b = blocker :: Racer
		local otherLat = if b.IsAI then b.Lane else b.Lat
		-- place à gauche / à droite de la voiture devant (bornée à la chaussée)
		local roomLeft = (otherLat + halfRoad)
		local roomRight = (halfRoad - otherLat)
		local wantSide = if roomRight >= roomLeft then 1 else -1
		if racer.PassTimer > 0 and racer.LaneGoal ~= 0 then
			wantSide = if racer.LaneGoal > otherLat then 1 else -1
		end
		racer.LaneGoal = math.clamp(otherLat + wantSide * 6.4, -halfRoad, halfRoad)
		racer.PassTimer = 2.5
		if math.abs(racer.LaneGoal - otherLat) < 5.6 or blockGap < 12 and math.abs(racer.Lane - otherLat) < 4.6 then
			-- pas la place (ou pas encore décalé) : on suit
			target = math.min(target, b.V + (if blockGap > 16 then 2 else -1))
		end
	else
		racer.PassTimer = math.max(0, racer.PassTimer - dt)
		if racer.PassTimer <= 0 and math.abs(racer.LaneGoal) > 0.1 and t - race.GoAt > 4 then
			-- retour doux vers la trajectoire
			racer.LaneGoal *= 0.97
		end
	end
	racer.Lane += math.clamp(racer.LaneGoal - racer.Lane, -3.6 * dt, 3.6 * dt)
	local before = racer.D
	RaceRules.AIStep(racer :: any, dt, target, top, racer.Accel, ai.Brake or 38)
	racer.Lat = racer.Lane
	racer.S = lineS(race, racer.D)
	-- portes (l'IA reste sur sa trajectoire : largeur toujours bonne)
	if racer.D > before then
		local cps = route.Checkpoints
		while racer.Next <= #cps and racer.D >= cps[racer.Next].D do
			local cp = cps[racer.Next]
			racer.Next += 1
			racer.LastCpD = cp.D
			local frac = if racer.D > before then (cp.D - before) / (racer.D - before) else 1
			local at = t - dt + dt * math.clamp(frac, 0, 1)
			if route.Closed and (cp.LapEnd or cp.Finish) then
				local lap = at - racer.LapStart
				if lap > 3 then
					racer.LastLap = lap
					if racer.BestLap == nil or lap < (racer.BestLap :: number) then
						racer.BestLap = lap
					end
				end
				racer.LapStart = at
				racer.LapStartD = cp.D
			end
			if cp.Finish then
				racer.Finished = true
				-- instant exact du franchissement (interpolé)
				racer.FinishTime = at - race.GoAt
				if not route.Closed then
					racer.BestLap = racer.FinishTime
				end
				break
			end
		end
	end
end

local function rank(race: Race, t: number)
	local rows = {}
	for _, r in ipairs(race.Racers) do
		local cps = race.Route.Checkpoints
		local cap = if r.Next <= #cps then cps[r.Next].D else race.Route.RaceDistance
		table.insert(rows, { Key = r.Key, Racer = r, Finished = r.Finished, FinishTime = r.FinishTime, Progress = math.min(r.D, cap + 0.5), Dnf = r.Dnf })
	end
	for place, row in ipairs(RaceRules.Standings(rows)) do
		local r = row.Racer
		r.Place = place
		-- (v11) dépassements (humains) : place gagnée et gardée 1,5 s, après les 3 premières s
		if race.Phase == "Racing" and place ~= r.PrevPlace then
			if place < r.PrevPlace and t - race.GoAt > 3 and not r.Finished then
				if t - r.PlaceSince > 0.3 then
					r.Overtakes += r.PrevPlace - place
				end
			end
			r.PrevPlace = place
			r.PlaceSince = t
		end
	end
end

----------------------------------------------------------------------
-- Fin de course : classement, récompenses, XP, records, fantômes
----------------------------------------------------------------------

local function grantGoldDiamond(player: Player, rd: any, routeId: string): boolean
	local stat = rd.Routes[routeId]
	if not stat or stat.G then
		return false
	end
	local bank = services and services.BankService
	if not bank or type(bank.GrantDiamonds) ~= "function" then
		return false
	end
	-- (BANK11) BankService:GrantDiamonds(player, amount, source, quiet) -> diamants donnés (0 : plafond du jour)
	local ok, granted = pcall(bank.GrantDiamonds, bank, player, 1, "Race", true)
	if ok and (tonumber(granted) or 0) > 0 then
		stat.G = true
		return true
	end
	return false
end

local function finish(race: Race)
	race.Phase = "Results"
	race.PhaseAt = now()
	-- IA encore en route : temps estimé (distance restante à leur vitesse moyenne)
	local t = now()
	for _, r in ipairs(race.Racers) do
		if r.IsAI and not r.Finished then
			local elapsed = math.max(1, t - race.GoAt)
			local avg = math.max(8, (r.D + 1) / elapsed)
			r.Finished = true
			r.FinishTime = elapsed + math.max(0, race.Route.RaceDistance - r.D) / avg
		end
	end
	rank(race, t)
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
	local winnerTime = ordered[1] and ordered[1].FinishTime
	local cs = services and services.CarService
	local mine: { [Player]: any } = {}
	local medals = race.Route.Medals
	for _, r in ipairs(ordered) do
		local reward, seconds, capped = 0, 0, false
		local player = r.Player
		if player and player.Parent then
			local rd = raceData(player)
			local m: any = { Place = r.Place, Reward = 0 }
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
				local valid = r.Finished and not r.Suspicious
				local stat = rd.Routes[race.RouteId] or { R = 0, W = 0, P = 0, M = 0 }
				rd.Routes[race.RouteId] = stat
				stat.R += 1
				local medal = if valid then RaceRules.MedalFor(r.FinishTime, medals) else 0
				local prevBestRace = stat.T
				local newPB = false
				local newBestLap = false
				local oldLap = rd.Best[race.RouteId]
				if valid then
					if r.Place == 1 then
						rd.Wins += 1
						stat.W += 1
					end
					if r.Place <= 3 then
						rd.Podiums += 1
						stat.P += 1
					end
					if r.FinishTime and (stat.T == nil or r.FinishTime < stat.T) then
						stat.T = r.FinishTime
						stat.C = r.CarId
						newPB = prevBestRace ~= nil
					end
					if medal > 0 and (stat.M == 0 or medal < stat.M) then
						stat.M = medal
					end
					local best = r.BestLap
					if best and best > 3 then
						if oldLap == nil or best < oldLap then
							rd.Best[race.RouteId] = best
							newBestLap = oldLap ~= nil
							-- fantôme : temps de passage du meilleur tour
							local splits = r.BestLapSplits
							if splits then
								local ghost = RaceRules.CleanGhost({ T = splits.T, D = splits.D, Car = r.CarId })
								if ghost then
									rd.Ghost[race.RouteId] = ghost
								end
							end
						end
						recordBest(race.RouteId, player, best, r.CarId)
					end
				end
				-- XP (cosmétique)
				local xpBefore = rd.Xp
				local xp = RaceRules.XpFor({
					Place = r.Place,
					Finished = valid,
					Dnf = r.Dnf or (r.Finished and r.Suspicious),
					Humans = humans - 1,
					Medal = medal,
					Record = newPB or newBestLap,
					Overtakes = r.Overtakes,
				})
				rd.Xp += xp
				rd.DriftBest = math.max(rd.DriftBest, math.floor(r.Drift))
				rd.Overtakes += r.Overtakes
				rd.Distance += math.floor(math.clamp(r.D, 0, race.Route.RaceDistance))
				RaceRules.PushHistory(rd, {
					R = race.RouteId,
					P = if valid then r.Place else 0,
					N = #race.Racers,
					T = if valid then r.FinishTime else nil,
					L = r.BestLap,
					C = r.CarId,
					X = xp,
					M = medal,
					At = os.time(),
				})
				local diamond = medal == 1 and grantGoldDiamond(player, rd, race.RouteId)
				if services and services.GameService then
					services.GameService:MarkDirty(player)
				end
				pilotsDirty = true
				m = {
					Place = r.Place,
					Reward = reward,
					Seconds = seconds,
					Capped = capped,
					Suspicious = r.Suspicious,
					Left = math.max(0, ((cfgRace().Rewards or {}).DailyRewarded or 8) - rd.Rewarded),
					Time = r.FinishTime,
					Finished = valid,
					BestLap = r.BestLap,
					Medal = medal,
					Medals = medals,
					Par = race.Route.Par,
					Xp = xp,
					XpBefore = xpBefore,
					XpAfter = rd.Xp,
					PB = newPB,
					PrevBest = prevBestRace,
					BestLapPB = newBestLap,
					Drift = math.floor(r.Drift),
					Overtakes = r.Overtakes,
					Diamond = diamond == true,
				}
			end
			mine[player] = m
		end
		table.insert(rows, {
			Place = r.Place,
			Name = r.Name,
			UserId = r.UserId,
			AI = r.IsAI,
			CarId = r.CarId,
			Color = r.Color,
			Time = r.FinishTime,
			Gap = if r.Finished and r.FinishTime and winnerTime and r.Place > 1 then r.FinishTime - winnerTime else nil,
			BestLap = r.BestLap,
			Finished = r.Finished,
			Dnf = r.Dnf,
			Drift = math.floor(r.Drift),
			Reward = if player then (mine[player] and mine[player].Reward or 0) else 0,
			Xp = if player and mine[player] then mine[player].Xp else nil,
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
			if m.Diamond then
				toast(player, T(player, "💎 First gold medal on this route: +1 diamond!"))
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
	local cfg = cfgRace()
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
		if t >= race.LobbyEnds or #race.Racers >= (cfg.MaxRacers or 8) then
			startGrid(race)
		end
	elseif race.Phase == "Grid" then
		if t >= race.GoAt - (cfg.CountdownSeconds or 3) then
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
				updateHuman(race, r, t, dt)
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
		rank(race, t)
		-- fin : tous les humains arrivés / abandonnés, délai après le 1er, durée max
		local running = false
		for _, r in ipairs(race.Racers) do
			if not r.IsAI and not r.Finished and not r.Dnf then
				running = true
			end
		end
		local graceOver = race.FirstFinish ~= nil and t - (race.FirstFinish :: number) > (cfg.FinishGrace or 35)
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
local snapRound = 0
local pilotsClock = 0
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
		-- coureurs + spectateurs : 5 fois / s ; autres joueurs en ville : 2,5 fois / s (50 joueurs)
		snapRound += 1
		if #active > 0 then
			for _, p in ipairs(townPlayers()) do
				if playerRace[p] ~= nil or watchers[p] ~= nil or snapRound % 2 == 0 then
					fire(p, "State", active)
				end
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
	pilotsClock += dt
	if pilotsDirty and pilotsClock >= 2 then
		pilotsClock = 0
		pilotsDirty = false
		pushPilots()
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
	if t - racer.LastReset < (cfgRace().ResetCooldown or 3) then
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
			racer.DriftCombo = 0
			table.clear(racer.Samples)
			fire(player, "Reset", { D = d })
		end
	end
end

-- (v11) nitro : une charge -> boost (validé ici)
local function useNitro(player: Player)
	local race = playerRace[player]
	local racer = race and race.ByPlayer[player]
	if not race or not racer or race.Phase ~= "Racing" or racer.Finished or racer.Dnf then
		return
	end
	local t = now()
	if racer.Nitro <= 0 or t < racer.BoostUntil or t < race.GoAt + 0.5 then
		return
	end
	racer.Nitro -= 1
	racer.BoostUntil = t + ((cfgRace().Nitro or {}).Seconds or 2.6)
	racer.SegBoost = true
	fire(player, "Nitro", { Until = racer.BoostUntil, Charges = racer.Nitro })
end

local function onEvent(player: Player, kind: any, arg: any)
	if type(kind) ~= "string" then
		return
	end
	if not RateLimiter.Check(player, "Race_" .. kind, if kind == "sync" then 1 elseif kind == "nitro" then 0.25 else 0.4) then
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
	elseif kind == "nitro" then
		useNitro(player)
	elseif kind == "watch" then
		if type(arg) == "string" and Config.RaceRoutesById[arg] and playerRace[player] == nil then
			watchers[player] = arg
		else
			watchers[player] = nil
		end
	elseif kind == "sync" then
		pushLobbies(player)
		pushBoard(player)
		pushPilots(player)
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
		local stat = data.Race.Routes[routeId]
		recordBest(routeId, player, best, stat and stat.C or "")
	end
	pilotsDirty = true
end

function RaceService:PlayerRemoving(player: Player)
	local race = playerRace[player]
	if race then
		pcall(leave, player)
		removeRacer(race, player)
	end
	playerRace[player] = nil
	watchers[player] = nil
	pilotsDirty = true
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
		Nitro = useNitro,
		Watchers = watchers,
		Pilots = pilotsPayload,
		Now = now,
	}
end

return RaceService
