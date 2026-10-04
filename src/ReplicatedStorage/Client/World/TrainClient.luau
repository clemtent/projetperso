--[[
	TrainClient (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TrainClient

	🚂 Le TRAIN de Dopamine Town (v11, TRAIN11), côté CLIENT. Rien n'est
	répliqué : la ligne (Shared/TrainLine) et l'horaire sont une fonction de
	l'heure du serveur, chaque client construit et pose LA MÊME CHOSE.
	  - EN FLUX autour de l'avatar (TrainModels) : voie en morceaux de
	    CHUNK studs (rails + ballast jusqu'à ~1100 studs, traverses près),
	    4 gares (complètes près, bloc de loin), 4 passages à niveau, 4
	    planques, et les 2 TRAINS (complets à moins de FULL_R studs,
	    imposteurs jusqu'à FAR_R) ;
	  - MOUVEMENT : une fonction liée au rendu AVANT la caméra
	    (BindToRenderStep, priorité Camera - 1), horloge lissée : chaque
	    image, les voitures proches + TOUS les sièges du serveur des trains
	    proches sont posés (l'avatar assis suit son siège sans à-coup ; même
	    correctif que les manèges FAIR99) ;
	  - PORTES côté quai : s'ouvrent ~1 s après l'arrêt, se ferment ~2 s
	    avant le départ ; colliders solides seulement à l'arrêt ; un avatar
	    resté DEBOUT dans une voiture qui démarre est reposé sur le quai ;
	  - INVITES : "Monter" (E) aux portes, "S'asseoir" (E) sur chaque siège
	    libre (sauf ceux des PNJ) -> remote "TrainEvent" (le serveur valide) ;
	  - PASSAGES À NIVEAU : barrières qui s'abaissent, feux rouges qui
	    clignotent (TrainLine.CrossingState : la circulation de CARS11 lit la
	    même fonction) ;
	  - CONVOI DE DIAMANTS : état du wagon blindé lu dans les attributs de
	    Workspace > DopamineTrain (volet, boîtier, coffre, sacs, gyrophare),
	    repère 💎 au-dessus du quai pendant l'annonce et le long arrêt ;
	  - PNJ : conducteur dans chaque cabine, quelques voyageurs assis
	    (NPCModels, s'il existe), seulement près de l'avatar ;
	  - HUD (TrainHud) : carte de gare, voyage, bandeau du convoi ;
	    écrans des voitures et tableaux des départs des gares en direct.
	Aucune vraie lumière, aucun son.

	API (TownClient, via optionalModule) :
	  TrainClient.Start(options?)  options.Toast = fn(texte, couleur?)
	  TrainClient.Step(dt)         à chaque image (flux, HUD, tableaux)
	  TrainClient.Stop()           à la sortie (tout est détruit)
	  TrainClient.Debug() -> table
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TrainLine = require(ReplicatedStorage.Shared.TrainLine)
local TrainModels = require(script.Parent.TrainModels)
local TrainHud = require(script.Parent.TrainHud)

local okGQ, GraphicsQuality = pcall(function()
	return require(ReplicatedStorage.Shared.GraphicsQuality)
end)
local okClock, ClockKit = pcall(function()
	return require(script.Parent.ClockKit)
end)

local TrainClient = {}

local LocalPlayer = Players.LocalPlayer

TrainClient.CHUNK = 150 -- (studs d'abscisse) un morceau de voie
TrainClient.DETAIL_R = 260 -- traverses
TrainClient.TRACK_R = 1100 -- rails + ballast
TrainClient.FULL_R = 380 -- train complet
TrainClient.FAR_R = 1500 -- imposteur
TrainClient.STATION_R = 650
TrainClient.STATION_FAR_R = 2200
TrainClient.CROSS_R = 450
TrainClient.HIDE_R = 520
TrainClient.NPC_R = 170
TrainClient.STREAM_EVERY = 0.2
TrainClient.HUD_EVERY = 0.25
TrainClient.RENDER_NAME = "DopamineTrain"

type TrainVis = { Level: number, Cars: { any }, Npcs: { any }, Prompts: { ProximityPrompt }, Seats: { [number]: { [number]: BasePart } } }

local s: any = {
	Started = false,
	Folder = nil,
	Count = 8,
	Chunks = {},
	Stations = {},
	Crossings = {},
	Hideouts = {},
	Trains = {},
	Rider = nil,
	Heist = nil,
	Toast = nil,
	Conns = {},
	Acc = 0,
	HudAcc = 0,
	ScreenAcc = 0,
	Marker = nil,
	ServerFolder = nil,
	Ejected = 0,
}

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

-- Horloge du serveur lissée (pas de petits sauts : voir FairKit.Now)
local clockOffset: number? = nil
local lastClock = 0
local function now(): number
	local c = os.clock()
	local ok, server = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if not ok or type(server) ~= "number" then
		return c
	end
	local target = server - c
	local off = clockOffset
	if off == nil or math.abs(target - off) > 1 then
		off = target
	else
		local dt = math.clamp(c - lastClock, 0, 0.25)
		local maxStep = dt * 0.05
		off += math.clamp(target - off, -maxStep, maxStep)
	end
	clockOffset = off
	lastClock = c
	return c + (off :: number)
end

local function T(text: string, ...): string
	local out = Locale.T(text)
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, out, ...)
		return ok and res or out
	end
	return out
end

local function detailScale(): number
	if okGQ and type(GraphicsQuality) == "table" and type(GraphicsQuality.DetailScale) == "function" then
		local ok, v = pcall(GraphicsQuality.DetailScale)
		if ok and type(v) == "number" and v > 0 then
			return math.clamp(v, 0.4, 1.5)
		end
	end
	return 1
end

local function mmss(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function fire(kind: string, ...)
	local args = table.pack(...)
	pcall(function()
		Net.Event("TrainEvent"):FireServer(kind, table.unpack(args, 1, args.n))
	end)
end

local function character(): (Model?, Humanoid?, BasePart?)
	local ch = LocalPlayer and LocalPlayer.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if ch and hum and root and root:IsA("BasePart") then
		return ch, hum, root
	end
	return nil, nil, nil
end

-- Point de vue (repère ville)
local function focus(): Vector3?
	local _, _, root = character()
	local p: Vector3? = if root then root.Position else nil
	if not p then
		local cam = workspace.CurrentCamera
		p = cam and cam.CFrame.Position or nil
	end
	if not p then
		return nil
	end
	return p - WorldLayout.Origin()
end

local function trainName(ti: number): string
	local def = TrainLine.Trains[ti]
	return T(def and def.Name or "Train")
end

local function stationName(k: number): string
	local def = TrainLine.STATION_DEFS[k]
	return T(def and def.Name or "Station")
end

local function serverFolder(): Instance?
	local f = s.ServerFolder
	if f and f.Parent then
		return f
	end
	local town = workspace:FindFirstChild("DopamineTown")
	f = (town and town:FindFirstChild("DopamineTrain")) or workspace:FindFirstChild("DopamineTrain")
	s.ServerFolder = f
	return f
end

----------------------------------------------------------------------
-- Voie, gares, passages, planques (flux)
----------------------------------------------------------------------

local function streamTrack(p: Vector3)
	local L = TrainLine.Length(s.Count)
	local n = math.ceil(L / TrainClient.CHUNK)
	local ds = detailScale()
	local trackR = TrainClient.TRACK_R * ds
	local wants = {}
	for i = 1, n do
		local s0 = (i - 1) * TrainClient.CHUNK
		local s1 = math.min(L, i * TrainClient.CHUNK)
		local x, z = TrainLine.PointAt(s.Count, (s0 + s1) / 2)
		local d = math.sqrt((x - p.X) ^ 2 + (z - p.Z) ^ 2) - TrainClient.CHUNK / 2
		local cur = s.Chunks[i]
		local level = 0
		local slack = if cur and cur.Level > 0 then 40 else 0
		if d < TrainClient.DETAIL_R + slack then
			level = 2
		elseif d < trackR + slack then
			level = 1
		end
		if (cur and cur.Level or 0) ~= level then
			table.insert(wants, { I = i, Level = level, D = d, S0 = s0, S1 = s1 })
		end
	end
	table.sort(wants, function(a, b)
		return a.D < b.D
	end)
	local budget = 2
	for _, w in ipairs(wants) do
		if budget <= 0 then
			break
		end
		local cur = s.Chunks[w.I]
		if cur and cur.Model then
			cur.Model:Destroy()
		end
		if w.Level > 0 then
			local ok, model = pcall(TrainModels.TrackChunk, s.Folder, s.Count, w.S0, w.S1, w.Level)
			s.Chunks[w.I] = { Level = w.Level, Model = if ok then model else nil }
			if not ok then
				warn("[TrainClient] voie : " .. tostring(model))
			end
			budget -= 1
		else
			s.Chunks[w.I] = nil
		end
	end
end

local function streamPlaces(p: Vector3)
	local ds = detailScale()
	for k, st in ipairs(TrainLine.Stations(s.Count)) do
		local d = math.sqrt((st.X - p.X) ^ 2 + (st.Z - p.Z) ^ 2)
		local cur = s.Stations[k] or { Level = 0 }
		local level = 0
		local slack = if cur.Level > 0 then 60 else 0
		if d < TrainClient.STATION_R * math.max(0.7, ds) + slack then
			level = 2
		elseif d < TrainClient.STATION_FAR_R + slack then
			level = 1
		end
		if level ~= cur.Level then
			if cur.Rec then
				cur.Rec.Model:Destroy()
			end
			if cur.Far then
				cur.Far:Destroy()
			end
			local nrec: any = { Level = level }
			if level == 2 then
				local ok, rec = pcall(TrainModels.Station, s.Folder, s.Count, st, ds >= 0.7, if okClock then ClockKit else nil)
				if ok then
					nrec.Rec = rec
				else
					warn("[TrainClient] gare : " .. tostring(rec))
				end
			elseif level == 1 then
				local ok, far = pcall(TrainModels.StationImpostor, s.Folder, s.Count, st)
				if ok then
					nrec.Far = far
				end
			end
			s.Stations[k] = nrec
			return -- (une construction lourde par passage)
		end
	end
	for i, c in ipairs(TrainLine.Crossings(s.Count)) do
		local d = math.sqrt((c.X - p.X) ^ 2 + (c.Z - p.Z) ^ 2)
		local cur = s.Crossings[i]
		if not cur and d < TrainClient.CROSS_R then
			local ok, rec = pcall(TrainModels.Crossing, s.Folder, c)
			if ok then
				s.Crossings[i] = rec
			else
				warn("[TrainClient] passage : " .. tostring(rec))
				s.Crossings[i] = false
			end
		elseif cur and d > TrainClient.CROSS_R + 70 then
			cur.Model:Destroy()
			s.Crossings[i] = nil
		end
	end
	for k, h in ipairs(TrainLine.Hideouts(s.Count)) do
		local d = math.sqrt((h.X - p.X) ^ 2 + (h.Z - p.Z) ^ 2)
		local cur = s.Hideouts[k]
		if not cur and d < TrainClient.HIDE_R then
			local ok, model = pcall(TrainModels.Hideout, s.Folder, h)
			s.Hideouts[k] = if ok then model else false
		elseif cur and d > TrainClient.HIDE_R + 70 then
			cur:Destroy()
			s.Hideouts[k] = nil
		end
	end
end

----------------------------------------------------------------------
-- Trains (complets / imposteurs)
----------------------------------------------------------------------

local NPCModels: any = nil
local npcTried = false
local function npcModels(): any
	if not npcTried then
		npcTried = true
		local ok, mod = pcall(function()
			return require(ReplicatedStorage.Shared.NPCModels)
		end)
		NPCModels = if ok and type(mod) == "table" then mod else nil
	end
	return NPCModels
end

local function destroyTrain(ti: number)
	local tv = s.Trains[ti]
	if not tv then
		return
	end
	for _, rec in ipairs(tv.Cars) do
		rec.Model:Destroy()
	end
	for _, npc in ipairs(tv.Npcs) do
		if npc.Model then
			npc.Model:Destroy()
		end
	end
	s.Trains[ti] = nil
end

-- Sièges du serveur de ce train : [car][seat] = Seat
local function serverSeats(ti: number): { [number]: { [number]: BasePart } }
	local out = {}
	local f = serverFolder()
	if not f then
		return out
	end
	for _, seat in ipairs(f:GetChildren()) do
		if seat:IsA("BasePart") and seat:GetAttribute("TrainIndex") == ti then
			local ci, si = seat:GetAttribute("CarIndex"), seat:GetAttribute("SeatIndex")
			if type(ci) == "number" and type(si) == "number" then
				out[ci] = out[ci] or {}
				out[ci][si] = seat
			end
		end
	end
	return out
end

local function addPrompts(tv: TrainVis, ti: number, ci: number, rec: any)
	if rec.Kind ~= "Coach" then
		return
	end
	-- monter : un vantail par porte côté quai
	for _, leaf in ipairs(rec.DoorParts) do
		local p = Instance.new("ProximityPrompt")
		p.Name = "TrainBoardPrompt"
		p.ActionText = T("Board")
		p.ObjectText = "🚂 " .. trainName(ti)
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.MaxActivationDistance = 11
		p.RequiresLineOfSight = false
		p.HoldDuration = 0
		p.Enabled = false
		p.Parent = leaf
		p.Triggered:Connect(function()
			fire("board", ti, ci)
		end)
		table.insert(tv.Prompts, p)
	end
	-- s'asseoir : chaque siège libre (pas ceux des PNJ)
	local npc = TrainLine.NpcSeats(ti, ci)
	for si, cushion in pairs(rec.Seats) do
		if not npc[si] then
			local p = Instance.new("ProximityPrompt")
			p.Name = "TrainSeatPrompt"
			p.ActionText = T("Sit")
			p.ObjectText = "💺"
			p.KeyboardKeyCode = Enum.KeyCode.E
			p.MaxActivationDistance = 5
			p.RequiresLineOfSight = false
			p.HoldDuration = 0
			p.Enabled = false
			p:SetAttribute("SeatPrompt", true)
			p.Parent = cushion
			p.Triggered:Connect(function()
				fire("sit", ti, ci, si)
			end)
			table.insert(tv.Prompts, p)
		end
	end
end

local function addNpcs(tv: TrainVis, ti: number, ci: number, rec: any)
	local NM = npcModels()
	if not NM or type(NM.Build) ~= "function" then
		return
	end
	local list = {}
	if rec.Kind == "Loco" then
		for _, cf in ipairs(rec.Npc) do
			table.insert(list, { Style = "worker", Local = cf, Seed = 900 + ti * 10 + ci })
		end
	elseif rec.Kind == "Coach" then
		local seats = TrainLine.SeatsLocal("Coach")
		for si in pairs(TrainLine.NpcSeats(ti, ci)) do
			local seat = seats[si]
			if seat then
				local styles = { "pedestrian", "shopper", "elder", "kid", "pedestrian" }
				local seed = ti * 100 + ci * 17 + si
				table.insert(list, {
					Style = styles[(seed % #styles) + 1],
					Local = CFrame.new(seat.X, TrainLine.FLOOR_L, seat.Z) * CFrame.Angles(0, seat.Yaw, 0),
					Seed = seed,
					Prop = if seed % 3 == 0 then "phone" else nil,
				})
			end
		end
	end
	for _, def in ipairs(list) do
		local ok, model = pcall(NM.Build, def.Style, { Seed = def.Seed, Prop = def.Prop, Name = "TrainNpc" })
		if ok and model then
			pcall(function()
				if type(NM.SetSitHeight) == "function" then
					NM.SetSitHeight(model, TrainLine.SEAT_TOP)
				end
			end)
			model.Parent = rec.Model
			table.insert(tv.Npcs, { Model = model, Car = ci, Local = def.Local, Posed = false, Seed = def.Seed })
		end
	end
end

local function buildTrain(ti: number, level: number)
	destroyTrain(ti)
	if level == 0 then
		return
	end
	local def = TrainLine.Trains[ti]
	local tv: TrainVis = { Level = level, Cars = {}, Npcs = {}, Prompts = {}, Seats = {} }
	for ci, kind in ipairs(def.Cars) do
		local ok, rec = pcall(if level == 2 then TrainModels.BuildCar else TrainModels.BuildImpostor, kind, def.Livery)
		if ok and rec then
			rec.Model.Name = string.format("Train%d_%d_%s", ti, ci, kind)
			rec.Model.Parent = s.Folder
			tv.Cars[ci] = rec
			if level == 2 then
				addPrompts(tv, ti, ci, rec)
				addNpcs(tv, ti, ci, rec)
			end
		else
			warn("[TrainClient] voiture : " .. tostring(rec))
		end
	end
	tv.Seats = serverSeats(ti)
	s.Trains[ti] = tv
end

local function streamTrains(p: Vector3)
	local t = now()
	local ds = detailScale()
	for ti in ipairs(TrainLine.Trains) do
		local st = TrainLine.State(s.Count, t, ti)
		local _, len = TrainLine.Consist(ti)
		local x, z = TrainLine.PointAt(s.Count, st.S - len / 2)
		local d = math.sqrt((x - p.X) ^ 2 + (z - p.Z) ^ 2) - len / 2
		local cur = s.Trains[ti]
		local curLevel = cur and cur.Level or 0
		local slack = if curLevel > 0 then 40 else 0
		local level = 0
		-- (passager : toujours complet)
		if s.Rider and s.Rider.Train == ti then
			level = 2
		elseif d < TrainClient.FULL_R * math.max(0.7, ds) + slack then
			level = 2
		elseif d < TrainClient.FAR_R + slack then
			level = 1
		end
		if level ~= curLevel then
			buildTrain(ti, level)
			return -- (un train par passage)
		end
	end
end

----------------------------------------------------------------------
-- Pose à chaque image (avant la caméra)
----------------------------------------------------------------------

local seatParts: { BasePart } = {}
local seatFrames: { CFrame } = {}

local function doorOpenness(st: any, t: number): number
	if st.Phase == "Run" or not st.StopAt or not st.DepartAt then
		return 0
	end
	local a = math.clamp((t - st.StopAt - 1.0) / 1.6, 0, 1)
	local b = math.clamp((st.DepartAt - 2.0 - t) / 1.6, 0, 1)
	return math.min(a, b)
end

local function vaultAttrs(): (string, boolean, number?)
	local f = serverFolder()
	if not f then
		return "", false, nil
	end
	local step = f:GetAttribute("VaultStep")
	local alarm = f:GetAttribute("Alarm")
	local cycle = f:GetAttribute("HeistCycle")
	return if type(step) == "string" then step else "", alarm == true, if type(cycle) == "number" then cycle else nil
end

local frameCount = 0
local function frameStep(dt: number)
	if not s.Started then
		return
	end
	frameCount += 1
	local t = now()
	local p = focus()
	table.clear(seatParts)
	table.clear(seatFrames)
	for ti, tv in pairs(s.Trains) do
		local frames, st = TrainLine.CarFrames(s.Count, t, ti)
		local riding = s.Rider and s.Rider.Train == ti
		local doors = doorOpenness(st, t)
		local stopped = st.Phase ~= "Run"
		for ci, rec in pairs(tv.Cars) do
			local cf = frames[ci]
			if cf then
				local d = if p then (cf.Position - WorldLayout.Origin() - p).Magnitude else 0
				-- près : chaque image ; plus loin : 1 sur 2 ; imposteurs : 1 sur 3
				local every = if tv.Level == 1 then 3 elseif d < 220 or riding then 1 else 2
				if (frameCount + ci) % every == 0 or rec.LastCF == nil then
					if tv.Level == 2 then
						if rec.Kind == "Coach" then
							TrainModels.SetDoors(rec, doors)
						elseif rec.Kind == "Vault" then
							local step, alarm, cycle = vaultAttrs()
							-- (l'état du casse ne vaut que pour le cycle en cours du convoi :
							-- l'annonce du suivant remet le wagon à neuf)
							if cycle ~= st.Cycle then
								step, alarm = "", false
							end
							TrainModels.SetVault(rec, step, alarm, t, dt * every)
						end
						TrainModels.SetSolid(rec, stopped)
					end
					TrainModels.Pose(rec, cf)
				end
			end
		end
		-- PNJ (près seulement)
		for _, npc in ipairs(tv.Npcs) do
			local cf = frames[npc.Car]
			if cf and npc.Model then
				local near = p ~= nil and (cf.Position - WorldLayout.Origin() - p).Magnitude < TrainClient.NPC_R
				-- (loin : retiré, jamais laissé en arrière d'un train qui roule)
				local holder = tv.Cars[npc.Car] and tv.Cars[npc.Car].Model
				local want = if near then holder else nil
				if npc.Model.Parent ~= want then
					npc.Model.Parent = want
				end
				if near then
					local target = cf * npc.Local
					pcall(function()
						npc.Model:PivotTo(target)
						if not npc.Posed and NPCModels and type(NPCModels.Animate) == "function" then
							NPCModels.Animate(npc.Model, "sit", npc.Seed)
							npc.Posed = true
						end
					end)
				end
			end
		end
		-- sièges du serveur : TOUS ceux de ce train (avatars assis sans à-coup)
		if tv.Level == 2 then
			for ci, list in pairs(tv.Seats) do
				local cf = frames[ci]
				if cf then
					for si, seat in pairs(list) do
						if seat.Parent then
							table.insert(seatParts, seat)
							table.insert(seatFrames, cf * TrainLine.SeatCFrame(si) * CFrame.new(0, -0.1, 0))
						end
					end
				end
			end
		end
	end
	if #seatParts > 0 then
		workspace:BulkMoveTo(seatParts, seatFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- passages à niveau
	for i, rec in pairs(s.Crossings) do
		if rec then
			local on, k = TrainLine.CrossingState(s.Count, i, t)
			TrainModels.SetCrossing(rec, on, k, t)
		end
	end
end

----------------------------------------------------------------------
-- Invites, éjection, HUD, écrans
----------------------------------------------------------------------

local function seated(): boolean
	local _, hum = character()
	return hum ~= nil and hum.SeatPart ~= nil
end

local function updatePrompts(t: number)
	local sit = seated()
	for ti, tv in pairs(s.Trains) do
		if tv.Level == 2 then
			local st = TrainLine.State(s.Count, t, ti)
			local open = doorOpenness(st, t) > 0.6
			for _, p in ipairs(tv.Prompts) do
				p.Enabled = open and not sit
			end
		end
	end
end

-- Avatar DEBOUT dans une voiture qui roule : reposé à côté (jamais traîné ni traversé)
local function ejectStanding(t: number)
	local _, hum, root = character()
	if not hum or not root or hum.SeatPart ~= nil then
		return
	end
	for ti, tv in pairs(s.Trains) do
		if tv.Level == 2 then
			local frames, st = TrainLine.CarFrames(s.Count, t, ti)
			if st.Phase == "Run" then
				for ci, cf in ipairs(frames) do
					local rel = cf:PointToObjectSpace(root.Position)
					local len = TrainLine.Consist(ti)[ci].Len
					if math.abs(rel.X) < TrainLine.CAR_W / 2 and rel.Y > TrainLine.FLOOR_L - 1 and rel.Y < 13 and math.abs(rel.Z) < len / 2 then
						local out = cf * CFrame.new(-(TrainLine.CAR_W / 2 + 4), TrainLine.FLOOR_L + 3, rel.Z)
						root.CFrame = CFrame.new(out.Position) * (cf - cf.Position)
						s.Ejected += 1
						return
					end
				end
			end
		end
	end
end

local function mapPoint(x: number, z: number, R: number): any
	local m = R + TrainLine.OFF_OUT + 40
	return { X = x / m, Y = z / m }
end

local function updateHud(t: number, p: Vector3?)
	-- en voyage
	if s.Rider and seated() then
		local ti = s.Rider.Train
		local st = TrainLine.State(s.Count, t, ti)
		local info: any = { Line = "🚂 " .. trainName(ti) }
		if st.Phase == "Run" then
			local total = math.max(1, (st.ArriveAt or t) - (st.DepartAt or t))
			info.Next = T("Next stop: %s", stationName(st.Next)) .. " · " .. mmss((st.ArriveAt or t) - t)
			info.Progress = 1 - ((st.ArriveAt or t) - t) / total
		else
			info.Next = "🚉 " .. stationName(st.Station) .. " · " .. T("departs in %s", mmss((st.DepartAt or t) - t))
			info.Progress = 0
		end
		TrainHud.SetRide(info)
	else
		TrainHud.SetRide(nil)
		if s.Rider and not seated() then
			s.Rider = nil
		end
	end
	-- carte de gare
	local near: any = nil
	if p and not s.Rider then
		for k, st in ipairs(TrainLine.Stations(s.Count)) do
			local d = math.sqrt((st.X + st.InX * 30 - p.X) ^ 2 + (st.Z + st.InZ * 30 - p.Z) ^ 2)
			if d < 110 then
				near = { K = k, St = st }
				break
			end
		end
	end
	if near then
		local k = near.K
		local rows = {}
		for ti in ipairs(TrainLine.Trains) do
			local arrive, depart = TrainLine.NextStop(s.Count, t, ti, k)
			local st = TrainLine.State(s.Count, t, ti)
			local nowAt = arrive <= t
			local when = if nowAt then T("At platform") .. " · " .. mmss(depart - t) else mmss(arrive - t)
			local icon = if ti == 1 then "🚂" else "🚆"
			if ti == 1 and nowAt and st.Heist then
				icon = "💎"
			end
			table.insert(rows, { Icon = icon, Line = trainName(ti), Dir = "→ " .. stationName(k % 4 + 1), When = when, Now = nowAt })
		end
		local R = TrainLine.Path(s.Count).R
		local stations = {}
		for kk, st in ipairs(TrainLine.Stations(s.Count)) do
			stations[kk] = mapPoint(st.X, st.Z, R)
		end
		local trains = {}
		for ti in ipairs(TrainLine.Trains) do
			local st = TrainLine.State(s.Count, t, ti)
			local x, z = TrainLine.PointAt(s.Count, st.S)
			trains[ti] = mapPoint(x, z, R)
		end
		TrainHud.SetStation({ Name = stationName(k), Rows = rows, Map = { Stations = stations, Trains = trains, Here = k, Legend = T("Belt line · 4 stations") } })
	else
		TrainHud.SetStation(nil)
	end
	-- bandeau du convoi
	local h = TrainLine.Heist(s.Count, t)
	local hasKit = (serverFolder() ~= nil)
	if hasKit and t >= h.AnnounceAt and t < h.End then
		local st = TrainLine.Stations(s.Count)[h.Station]
		local dist = if p then math.floor(math.sqrt((st.X - p.X) ^ 2 + (st.Z - p.Z) ^ 2)) else 0
		if t < h.Start then
			TrainHud.SetHeist({ Title = "💎 " .. T("The diamond convoy stops at %s in %s", stationName(h.Station), mmss(h.Start - t)), Sub = "📍 " .. T("%d studs away · gather on the platform", dist), Hot = false })
		else
			local sf = serverFolder()
			local phase = if sf then sf:GetAttribute("HeistPhase") else nil
			local hot = phase == "Running" or phase == "Escape"
			TrainHud.SetHeist({ Title = "💎 " .. T("The convoy is at %s: %s left to crack the vault!", stationName(h.Station), mmss(h.End - t)), Sub = "📍 " .. T("%d studs away", dist), Hot = hot })
		end
	else
		TrainHud.SetHeist(nil)
	end
	-- repère 💎 au-dessus du quai du convoi
	local marker = s.Marker
	if marker then
		local show = hasKit and t >= h.AnnounceAt and t < h.End
		local gui = marker:FindFirstChildOfClass("BillboardGui")
		if gui then
			gui.Enabled = show
		end
		if show then
			local st = TrainLine.Stations(s.Count)[h.Station]
			marker.CFrame = CFrame.new(WorldLayout.CityPoint(st.X + st.InX * 13, TrainLine.PLATFORM_Y + 26, st.Z + st.InZ * 13))
		end
	end
end

local function updateScreens(t: number)
	-- écrans des voitures
	for ti, tv in pairs(s.Trains) do
		if tv.Level == 2 then
			local st = TrainLine.State(s.Count, t, ti)
			local text
			if st.Phase == "Run" then
				text = T("Next stop: %s", stationName(st.Next))
			else
				text = "🚉 " .. stationName(st.Station)
			end
			for _, rec in pairs(tv.Cars) do
				if rec.Kind == "Coach" then
					TrainModels.SetScreens(rec, text)
				end
			end
		end
	end
	-- tableaux des départs
	for k, cur in pairs(s.Stations) do
		local rec = cur.Rec
		if rec and #rec.Boards > 0 then
			local lines = {}
			for ti in ipairs(TrainLine.Trains) do
				local arrive, depart = TrainLine.NextStop(s.Count, t, ti, k)
				local when = if arrive <= t then T("AT PLATFORM") .. " " .. mmss(depart - t) else mmss(arrive - t)
				local name = string.upper(trainName(ti))
				table.insert(lines, string.format("%-18s %s", string.sub(name, 1, 18), when))
				table.insert(lines, "  → " .. stationName(k % 4 + 1))
			end
			local text = table.concat(lines, "\n")
			for _, l in ipairs(rec.Boards) do
				if l.Text ~= text then
					l.Text = text
				end
			end
		end
		if rec and rec.Clock and okClock and type(ClockKit.Update) == "function" then
			pcall(ClockKit.Update, rec.Clock, t)
		end
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

local function onEvent(kind: any, payload: any)
	if kind == "Toast" and type(payload) == "string" then
		if s.Toast then
			pcall(s.Toast, payload)
		end
	elseif kind == "Rider" then
		if type(payload) == "table" then
			s.Rider = { Train = tonumber(payload.Train) or 1, Car = tonumber(payload.Car) or 1, Seat = tonumber(payload.Seat) or 1 }
		else
			s.Rider = nil
		end
	elseif kind == "Heist" and type(payload) == "table" then
		local first = s.Heist == nil or s.Heist.Cycle ~= payload.Cycle or s.Heist.Phase ~= payload.Phase
		s.Heist = payload
		if first and s.Toast and type(payload.Station) == "number" then
			if payload.Phase == "Announce" then
				pcall(s.Toast, "💎 " .. T("The diamond convoy stops at %s in 2 min!", stationName(payload.Station)))
			elseif payload.Phase == "Hold" then
				pcall(s.Toast, "💎 " .. T("The diamond convoy is at %s!", stationName(payload.Station)))
			end
		end
	end
end

function TrainClient.Start(options: any?)
	if s.Started then
		return
	end
	local town = workspace:FindFirstChild("DopamineTown")
	if not town then
		return
	end
	local o = options or {}
	s.Toast = o.Toast
	local sf = serverFolder()
	local count = (sf and sf:GetAttribute("PlotCount")) or town:GetAttribute("PlotCount")
	s.Count = WorldLayout.PlotCount(if type(count) == "number" then count else 8)
	local folder = Instance.new("Folder")
	folder.Name = "TrainWorld"
	-- (sous DopamineTown : TownAtmosphere suit les verres "NightGlow")
	folder.Parent = town
	s.Folder = folder
	-- repère du convoi (BillboardGui visible de loin)
	local marker = TrainModels.Part(folder, "HeistMarker", Vector3.new(1, 1, 1), CFrame.new(WorldLayout.Origin() + Vector3.new(0, -500, 0)), Color3.new(1, 1, 1))
	marker.Transparency = 1
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(150, 64)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 4000
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = marker
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = "💎\n" .. T("Diamond convoy")
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.fromRGB(160, 240, 255)
	l.TextStrokeTransparency = 0.3
	l.Parent = bb
	s.Marker = marker
	pcall(TrainHud.Build, {
		Leave = function()
			fire("leave")
			local _, hum = character()
			if hum then
				hum.Sit = false
				hum.Jump = true
			end
		end,
	})
	table.insert(s.Conns, Net.Event("TrainEvent").OnClientEvent:Connect(function(kind, payload)
		pcall(onEvent, kind, payload)
	end))
	-- avatar assis dans un train (après un respawn / une reconnexion)
	local _, hum = character()
	if hum and hum.SeatPart and hum.SeatPart:GetAttribute("TrainIndex") then
		local seat = hum.SeatPart
		s.Rider = { Train = seat:GetAttribute("TrainIndex"), Car = seat:GetAttribute("CarIndex"), Seat = seat:GetAttribute("SeatIndex") }
	end
	s.Started = true
	pcall(function()
		RunService:UnbindFromRenderStep(TrainClient.RENDER_NAME)
	end)
	RunService:BindToRenderStep(TrainClient.RENDER_NAME, Enum.RenderPriority.Camera.Value - 1, function(dt)
		local ok, err = pcall(frameStep, dt)
		if not ok and not s.Warned then
			s.Warned = true
			warn("[TrainClient] " .. tostring(err))
		end
	end)
	fire("sync")
end

function TrainClient.Step(dt: number)
	if not s.Started then
		return
	end
	s.Acc += dt
	s.HudAcc += dt
	s.ScreenAcc += dt
	local t = now()
	if s.Acc >= TrainClient.STREAM_EVERY then
		s.Acc = 0
		local p = focus()
		if p then
			streamTrack(p)
			streamPlaces(p)
			streamTrains(p)
		end
		updatePrompts(t)
		ejectStanding(t)
		-- (sièges du serveur arrivés après la construction)
		for ti, tv in pairs(s.Trains) do
			if tv.Level == 2 and next(tv.Seats) == nil then
				tv.Seats = serverSeats(ti)
			end
		end
	end
	if s.HudAcc >= TrainClient.HUD_EVERY then
		s.HudAcc = 0
		updateHud(t, focus())
	end
	if s.ScreenAcc >= 1 then
		s.ScreenAcc = 0
		updateScreens(t)
	end
end

function TrainClient.Stop()
	if not s.Started then
		return
	end
	s.Started = false
	pcall(function()
		RunService:UnbindFromRenderStep(TrainClient.RENDER_NAME)
	end)
	for _, c in ipairs(s.Conns) do
		c:Disconnect()
	end
	table.clear(s.Conns)
	if s.Folder then
		s.Folder:Destroy()
		s.Folder = nil
	end
	s.Chunks = {}
	s.Stations = {}
	s.Crossings = {}
	s.Hideouts = {}
	s.Trains = {}
	s.Rider = nil
	s.Marker = nil
	s.ServerFolder = nil
	pcall(TrainHud.Destroy)
end

-- (tests) état interne + nombre de pièces construites
function TrainClient.Debug(): any
	local parts = 0
	if s.Folder then
		for _, d in ipairs(s.Folder:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
	end
	local chunks, levels = 0, { 0, 0 }
	for _, c in pairs(s.Chunks) do
		chunks += 1
		levels[c.Level] = (levels[c.Level] or 0) + 1
	end
	local trains = {}
	for ti, tv in pairs(s.Trains) do
		trains[ti] = { Level = tv.Level, Cars = #tv.Cars, Npcs = #tv.Npcs, Prompts = #tv.Prompts }
	end
	local stations = {}
	for k, st in pairs(s.Stations) do
		stations[k] = st.Level
	end
	local crossings = 0
	for _, c in pairs(s.Crossings) do
		if c then
			crossings += 1
		end
	end
	return {
		Started = s.Started,
		Count = s.Count,
		Parts = parts,
		Chunks = chunks,
		Levels = levels,
		Trains = trains,
		Stations = stations,
		Crossings = crossings,
		Rider = s.Rider,
		Ejected = s.Ejected,
		Hud = TrainHud.Debug(),
	}
end

-- (tests) force la pose immédiate (sans rendu)
function TrainClient.ForceFrame(dt: number?)
	frameStep(dt or 1 / 60)
end

return TrainClient
