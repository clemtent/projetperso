--[[
	TrainService (ModuleScript)
	Emplacement : ServerScriptService > Services > TrainService

	🚂 Le TRAIN de Dopamine Town (v11, TRAIN11), côté SERVEUR. Le tracé, les
	gares et l'HORAIRE sont une fonction pure de l'heure du serveur
	(Shared/TrainLine) : chaque client dessine les deux trains au même
	endroit sans aucun réseau. Ici, SEULEMENT ce qui doit être décidé ou
	partagé :
	  - les SIÈGES (Seat ancrés, invisibles, CanTouch = false : jamais
	    d'assise par accident) des voitures voyageurs (2 trains, 5 voitures,
	    16 places chacune moins les places des PNJ). Même principe que les
	    manèges (TownFair) : siège ancré = avatar soudé ancré, aucune
	    physique ; le serveur ne déplace QUE les sièges occupés (10 fois / s),
	    chaque client pose localement tous les sièges proches à chaque image
	    (TrainClient) -> voyage fluide. Dessus du siège = dessus du coussin
	    (cibles SCALE11 : 1,85 au-dessus du plancher) ;
	  - MONTER ("board" : à côté d'une porte, train à l'arrêt) et S'ASSEOIR
	    ("sit" : une place précise, depuis l'intérieur de la voiture) ;
	    DESCENDRE (saut / "leave") : l'avatar est reposé sur le quai si le
	    train est en gare, sinon à côté de la voie (côté intérieur) ;
	  - le TRAIN QUI RENVERSE (façon dessin animé, ImpactService.Knock) un
	    piéton resté sur la voie devant un train qui roule (barrières et
	    feux des passages à niveau : TrainClient) ;
	  - le BRAQUAGE DU CONVOI DE DIAMANTS 💎 toutes les 20 min (TrainLine.Heist)
	    avec le HeistKit de BANK11 (équipe, mini-jeux pied-de-biche /
	    piratage / perceuse, sacs, alarme, planques, récompenses Dopamine +
	    💎 plafonnées : tout est générique et validé là-bas) : annonce
	    TrainLine.ANNOUNCE s avant, salle d'attente sur le quai de la gare du
	    long arrêt, départ du casse quand le convoi s'arrête ; si le convoi
	    repart avant que les sacs soient remplis : casse annulé. L'état du
	    wagon blindé (porte forcée, boîtier piraté, coffre ouvert, alarme)
	    est publié en ATTRIBUTS du dossier Workspace > DopamineTrain (les
	    clients l'animent ; les retardataires le lisent).
	Tout est dans des pcall ; chaque demande a sa limite de fréquence.

	RemoteEvent "TrainEvent" :
	  C -> S : ("board", trainIndex, carIndex) | ("sit", trainIndex, carIndex, seatIndex)
	           ("leave") | ("sync")
	  S -> C : ("Toast", texte) | ("Heist", { Cycle, Station, Start, End, Phase })
	           ("Rider", { Train, Car, Seat } | false)
	Attributs de Workspace > DopamineTrain : PlotCount, HeistKit (bool), HeistCycle,
	  HeistStation, HeistPhase ("Announce" | "Lobby" | "Running" | "Escape" |
	  "Done" | "Cancelled" | ""), VaultStep (dernière étape réussie : "" |
	  "crowbar" | "hack" | "drill" | "grab"), Alarm (bool).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TrainLine = require(ReplicatedStorage.Shared.TrainLine)
local RateLimiter = require(script.Parent.RateLimiter)

local TrainService = {}

TrainService.FOLDER_NAME = "DopamineTrain"
TrainService.SEAT_RATE = 0.1 -- (s) sièges occupés déplacés au serveur
TrainService.HIT_RATE = 0.1 -- (s) piétons sur la voie
TrainService.HEIST_RATE = 0.5 -- (s) horaire du braquage
TrainService.BOARD_RANGE = 14 -- (studs) d'une porte : monter
TrainService.SIT_RANGE = 10 -- (studs) d'une place : s'asseoir (depuis l'intérieur)

type SeatRec = {
	Seat: Seat,
	Train: number,
	Car: number,
	Index: number,
	Rider: Humanoid?,
	Player: Player?,
	Npc: boolean,
}

local services: any = nil
local folder: Folder? = nil
local seats: { SeatRec } = {}
local seatOf: { [Seat]: SeatRec } = {}
local riderOf: { [Player]: SeatRec } = {}
local connections: { RBXScriptConnection } = {}
local plotCount = 8
local heistKit: any = nil
local heist: any = nil -- { Cycle, Handle, Station, Start, End, Started, Grabbed, Phase }
local lastStep = ""

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
	return os.time()
end

local function T(player: Player, text: string, ...): string
	if services and services.GameService and type(services.GameService.T) == "function" then
		local ok, result = pcall(services.GameService.T, services.GameService, player, text, ...)
		if ok and type(result) == "string" then
			return result
		end
	end
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
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
		Net.Event("TrainEvent"):FireClient(player, kind, payload)
	end)
end

local function fireTown(kind: string, payload: any)
	for _, p in ipairs(Players:GetPlayers()) do
		if inTown(p) then
			fire(p, kind, payload)
		end
	end
end

local function characterOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function setAttr(name: string, value: any)
	if folder then
		pcall(function()
			(folder :: Folder):SetAttribute(name, value)
		end)
	end
end

local function heistBusy(player: Player): boolean
	if heistKit and type(heistKit.IsBusy) == "function" then
		local ok, busy = pcall(heistKit.IsBusy, player)
		return ok and busy == true
	end
	return false
end

----------------------------------------------------------------------
-- Sièges
----------------------------------------------------------------------

local function seatWorld(rec: SeatRec, t: number): CFrame
	local frames = TrainLine.CarFrames(plotCount, t, rec.Train)
	local carCF = frames[rec.Car] or CFrame.new()
	-- (le dessus de la pièce = dessus du coussin : centre 0,1 plus bas)
	return carCF * TrainLine.SeatCFrame(rec.Index) * CFrame.new(0, -0.1, 0)
end

-- Où reposer un avatar qui descend : quai (train en gare) ou bord de la voie
local function exitCFrame(rec: SeatRec, t: number): CFrame
	local frames, st = TrainLine.CarFrames(plotCount, t, rec.Train)
	local carCF = frames[rec.Car] or CFrame.new()
	local side = -(TrainLine.CAR_W / 2 + 3) -- côté quai (-X local)
	local along = ((rec.Index - 1) % 4 - 1.5) * 1.4
	if st.Phase ~= "Run" then
		-- quai : au niveau du plancher, + 3 (centre de l'avatar)
		return carCF * CFrame.new(side, TrainLine.FLOOR_Y - TrainLine.RAIL_Y + 3, along) * CFrame.Angles(0, math.pi / 2, 0)
	end
	-- en marche : à côté de la voie, au sol (pelouse), un peu plus loin
	local out = carCF * CFrame.new(side - 3, 0, along)
	local p = out.Position
	local ground = WorldLayout.Origin().Y + WorldLayout.GROUND_Y + 3
	return CFrame.new(p.X, ground, p.Z) * (out - out.Position)
end

local function release(rec: SeatRec, previous: Humanoid?)
	local character = previous and previous.Parent
	if not character or not character:IsA("Model") or not character.Parent then
		return
	end
	if (previous :: Humanoid).SeatPart ~= nil then
		return -- (déjà assis ailleurs)
	end
	local cf = exitCFrame(rec, now())
	pcall(function()
		(character :: Model):PivotTo(cf)
	end)
end

local function watchSeat(rec: SeatRec)
	table.insert(connections, rec.Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = rec.Seat.Occupant
		local previous = rec.Rider
		if occupant then
			rec.Rider = occupant
			local player = Players:GetPlayerFromCharacter(occupant.Parent)
			rec.Player = player
			if player then
				riderOf[player] = rec
				fire(player, "Rider", { Train = rec.Train, Car = rec.Car, Seat = rec.Index })
			end
			pcall(function()
				rec.Seat:SetAttribute("SitAt", now())
			end)
			return
		end
		rec.Rider = nil
		local player = rec.Player
		rec.Player = nil
		if player and riderOf[player] == rec then
			riderOf[player] = nil
			fire(player, "Rider", false)
		end
		if previous then
			task.defer(release, rec, previous)
		end
	end))
end

local function buildSeats()
	local town = workspace:FindFirstChild("DopamineTown")
	local f = Instance.new("Folder")
	f.Name = TrainService.FOLDER_NAME
	f:SetAttribute("PlotCount", plotCount)
	f:SetAttribute("HeistPhase", "")
	f:SetAttribute("VaultStep", "")
	f:SetAttribute("Alarm", false)
	folder = f
	local t = now()
	for ti, def in ipairs(TrainLine.Trains) do
		local frames = TrainLine.CarFrames(plotCount, t, ti)
		for ci, kind in ipairs(def.Cars) do
			if kind == "Coach" then
				local npc = TrainLine.NpcSeats(ti, ci)
				for si in ipairs(TrainLine.SeatsLocal("Coach")) do
					if not npc[si] then
						local seat = Instance.new("Seat")
						seat.Name = string.format("TrainSeat_%d_%d_%d", ti, ci, si)
						seat.Size = Vector3.new(2.4, 0.2, 2.2)
						seat.CFrame = frames[ci] * TrainLine.SeatCFrame(si) * CFrame.new(0, -0.1, 0)
						seat.Anchored = true
						seat.CanCollide = false
						seat.CanTouch = false
						seat.CanQuery = false
						seat.Transparency = 1
						seat.CastShadow = false
						seat:SetAttribute("SitKind", "seat")
						seat:SetAttribute("TrainIndex", ti)
						seat:SetAttribute("CarIndex", ci)
						seat:SetAttribute("SeatIndex", si)
						seat.Parent = f
						local rec: SeatRec = { Seat = seat, Train = ti, Car = ci, Index = si, Rider = nil, Player = nil, Npc = false }
						table.insert(seats, rec)
						seatOf[seat] = rec
						watchSeat(rec)
					end
				end
			end
		end
	end
	-- (hors de DopamineTown s'il n'existe pas encore : le client cherche les deux)
	f.Parent = town or workspace
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local function stepSeats()
	table.clear(moveParts)
	table.clear(moveFrames)
	local t = now()
	local framesCache: { [number]: { CFrame } } = {}
	for _, rec in ipairs(seats) do
		if rec.Seat.Occupant ~= nil then
			local frames = framesCache[rec.Train]
			if not frames then
				frames = TrainLine.CarFrames(plotCount, t, rec.Train)
				framesCache[rec.Train] = frames
			end
			table.insert(moveParts, rec.Seat)
			table.insert(moveFrames, frames[rec.Car] * TrainLine.SeatCFrame(rec.Index) * CFrame.new(0, -0.1, 0))
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- Monter / s'asseoir / descendre
----------------------------------------------------------------------

local function canBoard(player: Player, trainIndex: number): (boolean, string?)
	if not inTown(player) then
		return false, nil
	end
	if heistBusy(player) then
		return false, "Finish the heist first!"
	end
	local st = TrainLine.State(plotCount, now(), trainIndex)
	if st.Phase == "Run" and st.V > 2 then
		return false, "Wait for the train to stop"
	end
	return true, nil
end

local function sitOn(rec: SeatRec, humanoid: Humanoid)
	rec.Seat.CFrame = seatWorld(rec, now())
	rec.Seat:Sit(humanoid)
end

local function board(player: Player, trainIndex: any, carIndex: any)
	local ti, ci = tonumber(trainIndex), tonumber(carIndex)
	if not ti or not ci or not TrainLine.Trains[ti] then
		return
	end
	local _, humanoid, root = characterOf(player)
	if not humanoid or not root or humanoid.SeatPart ~= nil then
		return
	end
	local ok, why = canBoard(player, ti)
	if not ok then
		if why then
			fire(player, "Toast", T(player, why))
		end
		return
	end
	local frames = TrainLine.CarFrames(plotCount, now(), ti)
	local carCF = frames[ci]
	local consist = TrainLine.Consist(ti)
	if not carCF or not consist[ci] or consist[ci].Kind ~= "Coach" then
		return
	end
	local rel = carCF:PointToObjectSpace(root.Position)
	if math.abs(rel.Z) > consist[ci].Len / 2 + 4 or math.abs(rel.X) > TrainLine.CAR_W / 2 + TrainService.BOARD_RANGE or math.abs(rel.Y - 5) > 9 then
		return
	end
	-- place libre la plus proche
	local best, bestD = nil :: SeatRec?, math.huge
	for _, rec in ipairs(seats) do
		if rec.Train == ti and rec.Car == ci and rec.Seat.Occupant == nil then
			local local_ = TrainLine.SeatCFrame(rec.Index).Position
			local d = (local_ - rel).Magnitude
			if d < bestD then
				best, bestD = rec, d
			end
		end
	end
	if not best then
		fire(player, "Toast", T(player, "This carriage is full"))
		return
	end
	sitOn(best, humanoid)
end

local function sit(player: Player, trainIndex: any, carIndex: any, seatIndex: any)
	local ti, ci, si = tonumber(trainIndex), tonumber(carIndex), tonumber(seatIndex)
	if not ti or not ci or not si then
		return
	end
	local _, humanoid, root = characterOf(player)
	if not humanoid or not root or humanoid.SeatPart ~= nil then
		return
	end
	local ok, why = canBoard(player, ti)
	if not ok then
		if why then
			fire(player, "Toast", T(player, why))
		end
		return
	end
	for _, rec in ipairs(seats) do
		if rec.Train == ti and rec.Car == ci and rec.Index == si then
			if rec.Seat.Occupant ~= nil then
				return
			end
			local world = seatWorld(rec, now())
			if (world.Position - root.Position).Magnitude > TrainService.SIT_RANGE then
				return
			end
			sitOn(rec, humanoid)
			return
		end
	end
end

local function leave(player: Player)
	local rec = riderOf[player]
	local _, humanoid = characterOf(player)
	if not rec or not humanoid then
		return
	end
	humanoid.Sit = false
	pcall(function()
		local weld = rec.Seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- Piétons sur la voie : renversés (dessin animé) par un train qui roule
----------------------------------------------------------------------

local function stepHits()
	local impact = services and services.ImpactService
	if not impact or type(impact.Knock) ~= "function" then
		return
	end
	local t = now()
	local origin = WorldLayout.Origin()
	local states = {}
	for ti in ipairs(TrainLine.Trains) do
		states[ti] = TrainLine.State(plotCount, t, ti)
	end
	local L = TrainLine.Length(plotCount)
	for _, player in ipairs(Players:GetPlayers()) do
		local _, humanoid, root = characterOf(player)
		if humanoid and root and humanoid.SeatPart == nil and inTown(player) then
			local p = root.Position - origin
			-- au niveau de la voie (pas sur un quai, pas sur un pont)
			if p.Y < TrainLine.PLATFORM_Y + 2 and TrainLine.Near(plotCount, p.X, p.Z, 0) then
				local d2, s = TrainLine.Project(plotCount, p.X, p.Z, 10)
				if d2 <= (TrainLine.CAR_W / 2 + 0.8) ^ 2 then
					for ti, st in ipairs(states) do
						if st.V > 4 then
							local _, len = TrainLine.Consist(ti)
							local ahead = (s - st.S) % L -- devant la tête
							local behind = (st.S - s) % L -- sous le train
							if ahead <= st.V * 0.25 + 2 or behind <= len then
								local _, _, dx, dz = TrainLine.PointAt(plotCount, s)
								local x0, z0 = TrainLine.PointAt(plotCount, s)
								local side = Vector3.new(p.X - x0, 0, p.Z - z0)
								local push = Vector3.new(dx, 0, dz) * 0.6
								if side.Magnitude > 0.1 then
									push += side.Unit
								else
									push += Vector3.new(-dz, 0, dx)
								end
								pcall(impact.Knock, player, push.Unit, math.max(14, st.V * 0.6), true, nil)
								break
							end
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Braquage du convoi (HeistKit de BANK11)
----------------------------------------------------------------------

local function v3(x: number, y: number, z: number): Vector3
	return WorldLayout.CityPoint(x, y, z)
end

-- Position monde (repère local du wagon blindé) à l'instant t. Le casse se
-- joue pendant le LONG ARRÊT : le wagon est immobile en gare -> positions fixes
-- (calculées à l'heure du début de l'arrêt, même si on les annonce avant)
local function vaultPoint(lx: number, ly: number, lz: number, t: number): Vector3
	local x, y, z = TrainLine.ToWorld(plotCount, t, 1, TrainLine.VaultCarIndex(), lx, ly, lz)
	return v3(x, y, z)
end

local function heistEvent(_h: any, kind: any, payload: any)
	if not heist then
		return
	end
	if kind == "Started" then
		heist.Phase = "Running"
		setAttr("HeistPhase", "Running")
	elseif kind == "Step" then
		local id = type(payload) == "table" and (payload.Id or payload.Step or payload.Done) or payload
		if type(id) == "string" then
			lastStep = id
			setAttr("VaultStep", id)
			if id == "grab" then
				heist.Grabbed = true
			end
		end
	elseif kind == "Alarm" then
		setAttr("Alarm", true)
	elseif kind == "Bag" then
		heist.Grabbed = true
		if lastStep ~= "grab" and lastStep ~= "drill" then
			setAttr("VaultStep", "drill")
		end
	elseif kind == "Delivered" then
		heist.Phase = "Escape"
		setAttr("HeistPhase", "Escape")
	elseif kind == "Finished" then
		heist.Phase = "Done"
		setAttr("HeistPhase", "Done")
		setAttr("Alarm", false)
	end
end

local function destroyHeist()
	if heist and heist.Handle then
		pcall(function()
			heist.Handle:Destroy()
		end)
	end
	heist = nil
end

local function openHeist(info: any)
	destroyHeist()
	local stations = TrainLine.Stations(plotCount)
	local st = stations[info.Station]
	local hideouts = TrainLine.Hideouts(plotCount)
	local hide = hideouts[info.Station]
	local V = TrainLine.VaultLocal()
	local fy = TrainLine.FLOOR_L -- (repère local du wagon : depuis le dessus du rail)
	local lobby = v3(st.X + st.InX * 13, TrainLine.PLATFORM_Y + 3, st.Z + st.InZ * 13)
	local at = info.Start + 1
	local grabSpots = {}
	for _, b in ipairs(V.Bags) do
		table.insert(grabSpots, vaultPoint(b.X, b.Y, b.Z, at))
	end
	local stepsDef = {
		{ Id = "crowbar", Kind = "Crowbar", Label = "Pry open the armoured wagon door", Radius = 9, Taps = 12,
			Position = vaultPoint(V.Door.X - 1.5, fy + 3, V.Door.Z, at) },
		{ Id = "hack", Kind = "Hack", Label = "Hack the security box", Radius = 9,
			Position = vaultPoint(V.Panel.X - 1.5, fy + 3, V.Panel.Z, at) },
		{ Id = "drill", Kind = "Drill", Label = "Drill the safe", Radius = 10, Seconds = 20,
			Position = vaultPoint(V.Safe.X, fy + 3, V.Safe.Z, at) },
		{ Id = "grab", Kind = "Grab", Label = "Fill the bags with diamonds", Radius = 7, Seconds = 1.5, Spots = grabSpots },
		{ Id = "escape", Kind = "Escape", Label = "Bring the loot to the hideout", Radius = 14,
			Drops = { v3(hide.X, WorldLayout.GROUND_Y + 3, hide.Z) } },
	}
	heist = { Cycle = info.Cycle, Station = info.Station, Start = info.Start, End = info.End, Started = false, Grabbed = false, Phase = "Announce", Handle = nil }
	lastStep = ""
	setAttr("HeistCycle", info.Cycle)
	setAttr("HeistStation", info.Station)
	setAttr("HeistPhase", "Announce")
	setAttr("VaultStep", "")
	setAttr("Alarm", false)
	if heistKit and type(heistKit.Create) == "function" then
		local ok, h = pcall(heistKit.Create, {
			Kind = "Train",
			Name = "Diamond convoy",
			Lobby = { Position = lobby, Radius = 22 },
			Duration = TrainLine.HOLD + 150,
			MaxCrew = 4,
			Steps = stepsDef,
			OnEvent = heistEvent,
		})
		if ok and h then
			heist.Handle = h
			pcall(function()
				h:Open("🚂💎 The diamond convoy is coming! Gather on the station platform")
			end)
		else
			warn("[TrainService] HeistKit.Create : " .. tostring(h))
		end
	end
	fireTown("Heist", { Cycle = info.Cycle, Station = info.Station, Start = info.Start, End = info.End, Phase = "Announce" })
end

local function stepHeist()
	local t = now()
	local info = TrainLine.Heist(plotCount, t)
	-- annonce (ou reprise après un redémarrage du serveur pendant la fenêtre)
	if (not heist or heist.Cycle ~= info.Cycle) and t >= info.AnnounceAt and t < info.End then
		if not heist or heist.Phase == "Done" or heist.Phase == "Cancelled" or t > (heist.End or 0) + 150 then
			openHeist(info)
		end
	end
	if not heist then
		return
	end
	local h = heist.Handle
	if not heist.Started and t >= heist.Start then
		heist.Started = true
		heist.Phase = "Lobby"
		if h then
			local ok, err = pcall(function()
				h:Start()
			end)
			if not ok then
				warn("[TrainService] heist:Start : " .. tostring(err))
			end
		end
		fireTown("Heist", { Cycle = heist.Cycle, Station = heist.Station, Start = heist.Start, End = heist.End, Phase = "Hold" })
	end
	-- le convoi repart : sans sacs remplis, le casse est raté
	if heist.Started and t >= heist.End and not heist.Grabbed and heist.Phase ~= "Cancelled" and heist.Phase ~= "Done" then
		heist.Phase = "Cancelled"
		setAttr("HeistPhase", "Cancelled")
		setAttr("Alarm", false)
		if h then
			pcall(function()
				local state = h.State
				if state ~= "Done" and state ~= "Escape" then
					h:Cancel("The convoy left the station!")
				end
			end)
		end
	end
	-- ménage bien après la fin
	if t > heist.End + 200 then
		destroyHeist()
		setAttr("HeistPhase", "")
		setAttr("VaultStep", "")
		setAttr("Alarm", false)
	end
end

----------------------------------------------------------------------
-- Remote
----------------------------------------------------------------------

local function onEvent(player: Player, kind: any, a: any, b: any, c: any)
	if type(kind) ~= "string" then
		return
	end
	if kind == "board" then
		if RateLimiter.Check(player, "Train_board", 0.5) then
			board(player, a, b)
		end
	elseif kind == "sit" then
		if RateLimiter.Check(player, "Train_sit", 0.4) then
			sit(player, a, b, c)
		end
	elseif kind == "leave" then
		if RateLimiter.Check(player, "Train_leave", 0.3) then
			leave(player)
		end
	elseif kind == "sync" then
		if RateLimiter.Check(player, "Train_sync", 2) and heist then
			fire(player, "Heist", { Cycle = heist.Cycle, Station = heist.Station, Start = heist.Start, End = heist.End, Phase = heist.Phase })
		end
	end
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function TrainService:Init(allServices)
	services = allServices
end

function TrainService:Start()
	plotCount = WorldLayout.PlotCount(Players.MaxPlayers)
	local okKit, kit = pcall(function()
		local module = script.Parent:FindFirstChild("HeistKit")
		return module and require(module :: ModuleScript) or nil
	end)
	heistKit = if okKit and type(kit) == "table" then kit else nil
	if not heistKit then
		warn("[TrainService] HeistKit absent : pas de braquage du train")
	end
	local okSeats, errSeats = pcall(buildSeats)
	if not okSeats then
		warn("[TrainService] sièges : " .. tostring(errSeats))
	end
	-- (les clients n'annoncent le convoi que si le braquage existe)
	setAttr("HeistKit", heistKit ~= nil)
	table.insert(connections, Net.Event("TrainEvent").OnServerEvent:Connect(function(player, kind, a, b, c)
		local ok, err = pcall(onEvent, player, kind, a, b, c)
		if not ok then
			warn("[TrainService] " .. tostring(kind) .. " : " .. tostring(err))
		end
	end))
	local accSeat, accHit, accHeist = 0, 0, 0
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		accSeat += dt
		accHit += dt
		accHeist += dt
		if accSeat >= TrainService.SEAT_RATE then
			accSeat = 0
			local ok, err = pcall(stepSeats)
			if not ok then
				warn("[TrainService] sièges : " .. tostring(err))
			end
		end
		if accHit >= TrainService.HIT_RATE then
			accHit = 0
			pcall(stepHits)
		end
		if accHeist >= TrainService.HEIST_RATE then
			accHeist = 0
			local ok, err = pcall(stepHeist)
			if not ok then
				warn("[TrainService] braquage : " .. tostring(err))
			end
		end
	end))
end

function TrainService:PlayerReady(player: Player, _data: any)
	if heist then
		fire(player, "Heist", { Cycle = heist.Cycle, Station = heist.Station, Start = heist.Start, End = heist.End, Phase = heist.Phase })
	end
end

function TrainService:PlayerRemoving(player: Player)
	riderOf[player] = nil
end

-- (tests / débogage)
function TrainService.Debug(): any
	local busy = 0
	for _, rec in ipairs(seats) do
		if rec.Seat.Occupant ~= nil then
			busy += 1
		end
	end
	return {
		Seats = #seats,
		Busy = busy,
		PlotCount = plotCount,
		HeistKit = heistKit ~= nil,
		Heist = heist and { Cycle = heist.Cycle, Station = heist.Station, Phase = heist.Phase, Started = heist.Started } or nil,
		State1 = TrainLine.State(plotCount, now(), 1),
		State2 = TrainLine.State(plotCount, now(), 2),
	}
end

return TrainService
