--[[
	HeistKit (ModuleScript) — PAS un service (pas dans ORDER)
	Emplacement : ServerScriptService > Services > HeistKit

	🕶️ Moteur GÉNÉRIQUE des casses de Dopamine Town (v11, BANK11), utilisé
	par BankService (casse de la banque) et TrainService (convoi de diamants,
	TRAIN11). Casses CARTOON : pied-de-biche, perceuse, ordinateur, sacs de
	butin ; aucune arme, aucune violence (la "police" n'est qu'un chrono).
	Tout est décidé ICI : le client n'annonce jamais ni progrès ni butin,
	il DEMANDE (RemoteFunction "Heist") et le serveur vérifie :
	  - équipe : en ville, pas déjà dans un autre casse, à portée du point de
	    rendez-vous (Lobby), MaxCrew au plus ; le 1er inscrit est le chef ;
	  - étapes dans l'ordre, chacune à portée de SA position (Vector3 |
	    BasePart | fonction -> Vector3 : un wagon qui bouge marche aussi) :
	      Crowbar : coups de pied-de-biche (cadence minimale, nombre requis) ;
	      Hack    : code de symboles tiré par le serveur, temps minimal ;
	      Drill   : perçage chronométré par le SERVEUR, blocages à débloquer ;
	      Grab    : maintenir E sur une pile (durée vérifiée), sac limité ;
	      Escape  : porter les sacs jusqu'à la planque (livraison constatée
	                par le serveur d'après la position du personnage) ;
	  - ANTI-TRICHE : distances (marge Config.Bank.Heist.Range), durées
	    minimales, cadence (RateLimiter), saut instantané d'un porteur de sac
	    (HeistRules.SpeedOk) -> le sac tombe à sa dernière position valide ;
	  - sac sur le dos : attribut "HeistBag" (= piles) du personnage, dessiné
	    par chaque client (HeistClient) ; marche ralentie (CarrySlow) ; le sac
	    tombe si le porteur part / tombe / quitte la ville (un coéquipier le
	    ramasse : "pickup") ;
	  - fin : chrono écoulé ou tout livré -> RÉCOMPENSE de chaque membre
	    encore là (HeistRules.Reward : secondes de production x part livrée
	    x bonus d'équipe, plafond par jour et par genre) en Dopamine
	    (GameService:AddDopamine) + 💎 (BankService:GrantDiamonds).

	API (serveur) :
	  HeistKit.Init(services)             (BankService:Init)
	  HeistKit.Start()                    (BankService:Start : remote + boucle 4 Hz)
	  HeistKit.Create(def) -> heist       def = {
	      Kind = "Bank" | "Train",  Name = "...", Icon = "🏦",
	      Lobby = { Position = pos, Radius = 16 },  MaxCrew = 4,
	      LobbySeconds = 30, AutoStart = true, Duration = 240,
	      Steps = { { Id, Kind = "Crowbar"|"Hack"|"Drill"|"Grab"|"Escape", Label,
	                  Position = pos, Radius = 9, Alarm = true?, Taps?, Seconds?,
	                  Spots = { pos, ... } (Grab), Drops = { pos, ... } (Escape) } },
	      OnEvent = function(heist, kind, payload) end }   -- "Opened","Started","Step","Alarm","Bag","Delivered","Finished"
	  heist:Open(text?) / heist:Start() / heist:Cancel(reason?) / heist:Destroy()
	  heist.State : "Idle" | "Lobby" | "Running" | "Done" ; heist.Crew : { [Player] = Member }
	  HeistKit.IsBusy(player) -> boolean ; HeistKit.Get(id) ; HeistKit.All()
	  HeistKit.PlayerRemoving(player)     (BankService:PlayerRemoving)

	Remotes : RemoteFunction "Heist" (C -> S : action, heistId, arg -> ok, message, extra)
	  actions : "sync" | "join" | "leave" | "start" | "tap" (n) | "hackBegin" |
	            "hackAnswer" ({ symboles }) | "unjam" | "grabBegin" (pile) |
	            "grabEnd" (pile) | "escape" | "pickup" (index)
	RemoteEvent "HeistEvent" (S -> C) :
	  ("List", { résumés })      tous les joueurs en ville, à chaque changement
	  ("State", état détaillé)   l'équipe, 4 fois / s
	  ("Toast", texte) | ("Announce", { Text, Icon }) | ("Result", { ... })
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeistRules = require(ReplicatedStorage.Shared.HeistRules)
local Diamonds = require(ReplicatedStorage.Shared.Diamonds)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local RateLimiter = require(script.Parent.RateLimiter)

local HeistKit = {}

local TICK = 0.25
local STATE_EVERY = 0.25
local DONE_HOLD = 12 -- s pendant lesquels un casse fini reste listé (résultats)

export type Member = {
	Player: Player,
	Joined: number,
	Bag: number,
	LastPos: Vector3?,
	LastT: number,
	Code: { number }?,
	CodeAt: number,
	GrabPile: number?,
	GrabAt: number,
	LastTap: number,
	WalkBase: number?,
}

local services: any = nil
local heists: { [string]: any } = {}
local order: { string } = {}
local counter = 0
local started = false
local listDirty = true
local stateClock = 0

local Heist = {}
Heist.__index = Heist

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function H(): any
	return (Config.Bank and Config.Bank.Heist) or {}
end

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

-- Remote (créé ici s'il manque : marche même avant l'ajout dans Net)
local function remote(name: string, className: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		return nil
	end
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
	end
	return r
end

local function fire(player: Player, kind: string, payload: any)
	local r = remote("HeistEvent", "RemoteEvent")
	if r then
		pcall(function()
			(r :: RemoteEvent):FireClient(player, kind, payload)
		end)
	end
end

local function inTown(player: Player): boolean
	local world = services and services.WorldService
	if world and type(world.IsInTown) == "function" then
		local ok, result = pcall(world.IsInTown, world, player)
		return ok and result == true
	end
	return false
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

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") then
		return root, humanoid
	end
	return nil, humanoid
end

-- Position (Vector3 | BasePart | fonction) -> Vector3?
local function resolve(spec: any): Vector3?
	local t = typeof(spec)
	if t == "Vector3" then
		return spec
	elseif t == "Instance" and spec:IsA("BasePart") then
		return spec.Position
	elseif t == "function" then
		local ok, v = pcall(spec)
		if ok and typeof(v) == "Vector3" then
			return v
		end
	end
	return nil
end

-- À portée (à plat, + petite tolérance en hauteur)
local function near(player: Player, pos: Vector3?, radius: number): boolean
	if not pos then
		return false
	end
	local root = rootOf(player)
	if not root then
		return false
	end
	local d = root.Position - pos
	local flat = Vector3.new(d.X, 0, d.Z).Magnitude
	return flat <= radius + (H().Range or 5) and math.abs(d.Y) <= 14
end

local function dataOf(player: Player): any
	return services and services.DataService and services.DataService:GetData(player) or nil
end

local function heistData(player: Player): any?
	local data = dataOf(player)
	if type(data) ~= "table" then
		return nil
	end
	data.Heist = Diamonds.SanitizeHeist(data.Heist, Diamonds.Today(os.time()))
	return data.Heist
end

----------------------------------------------------------------------
-- Sac sur le dos
----------------------------------------------------------------------

local function setBag(heist: any, member: Member, value: number)
	member.Bag = math.max(0, math.floor(value))
	local character = member.Player.Character
	if character then
		pcall(function()
			character:SetAttribute("HeistBag", if member.Bag > 0 then member.Bag else nil)
			character:SetAttribute("HeistKind", if member.Bag > 0 then heist.Kind else nil)
		end)
	end
	-- marche ralentie avec un sac (rendue ensuite)
	local _, humanoid = rootOf(member.Player)
	if humanoid then
		pcall(function()
			if member.Bag > 0 and not member.WalkBase then
				member.WalkBase = humanoid.WalkSpeed
				humanoid.WalkSpeed = humanoid.WalkSpeed * (H().CarrySlow or 0.85)
			elseif member.Bag <= 0 and member.WalkBase then
				humanoid.WalkSpeed = member.WalkBase
				member.WalkBase = nil
			end
		end)
	end
	listDirty = true
end

-- Le sac tombe par terre (porteur parti / téléporté) : un coéquipier peut le ramasser
local function dropBag(heist: any, member: Member, at: Vector3?)
	if member.Bag <= 0 then
		return
	end
	local pos = at or member.LastPos
	if pos and heist.State == "Running" then
		table.insert(heist.Dropped, { Pos = pos, Value = member.Bag })
	end
	setBag(heist, member, 0)
end

----------------------------------------------------------------------
-- Résumés envoyés aux clients
----------------------------------------------------------------------

local function stepOf(heist: any): any?
	return heist.Def.Steps[heist.StepIndex]
end

local function crewList(heist: any): { any }
	local list = {}
	for _, p in ipairs(heist.Order) do
		local m = heist.Crew[p]
		if m then
			table.insert(list, { UserId = p.UserId, Name = p.DisplayName, Bag = m.Bag, Leader = heist.Leader == p })
		end
	end
	return list
end

local function summary(heist: any): any
	local lobby = heist.Def.Lobby or {}
	local step = stepOf(heist)
	local done = {}
	for id in pairs(heist.DoneSteps) do
		table.insert(done, id)
	end
	local taken = {}
	for i in pairs(heist.Taken) do
		table.insert(taken, i)
	end
	return {
		Id = heist.Id,
		Kind = heist.Kind,
		Name = heist.Def.Name or heist.Kind,
		Icon = heist.Def.Icon or "🕶️",
		State = heist.State,
		Lobby = resolve(lobby.Position),
		Radius = lobby.Radius or 16,
		Crew = heist.CrewCount,
		MaxCrew = heist.MaxCrew,
		LobbyEndsAt = heist.LobbyEndsAt,
		EndsAt = heist.EndsAt,
		Alarm = heist.Alarm,
		Step = step and step.Id or nil,
		Done = done,
		Taken = taken,
		Jammed = heist.Jammed,
		Success = heist.Success,
	}
end

local function stateFor(heist: any): any
	local step = stepOf(heist)
	local targets = {}
	if step then
		if step.Kind == "Grab" then
			for i, spot in ipairs(heist.Spots) do
				table.insert(targets, { I = i, Pos = resolve(spot), Taken = heist.Taken[i] == true })
			end
		elseif step.Kind == "Escape" then
			table.insert(targets, { I = 1, Pos = heist.Drop })
		else
			table.insert(targets, { I = 1, Pos = resolve(step.Position) })
		end
	end
	local dropped = {}
	for i, b in ipairs(heist.Dropped) do
		table.insert(dropped, { I = i, Pos = b.Pos, Value = b.Value })
	end
	return {
		Id = heist.Id,
		Kind = heist.Kind,
		Name = heist.Def.Name or heist.Kind,
		Icon = heist.Def.Icon or "🕶️",
		State = heist.State,
		StepIndex = heist.StepIndex,
		Steps = #heist.Def.Steps,
		Step = step and { Id = step.Id, Kind = step.Kind, Label = step.Label, Radius = step.Radius or 9 } or nil,
		Progress = heist.Progress,
		Jammed = heist.Jammed,
		Targets = targets,
		Dropped = dropped,
		Crew = crewList(heist),
		MaxCrew = heist.MaxCrew,
		Leader = heist.Leader and heist.Leader.UserId or 0,
		LobbyEndsAt = heist.LobbyEndsAt,
		EndsAt = heist.EndsAt,
		Alarm = heist.Alarm,
		Delivered = heist.Delivered,
		Total = heist.TotalLoot,
		Capacity = H().BagCapacity or 3,
	}
end

local function pushList()
	local list = {}
	for _, id in ipairs(order) do
		local h = heists[id]
		if h and h.State ~= "Idle" then
			table.insert(list, summary(h))
		end
	end
	for _, p in ipairs(townPlayers()) do
		fire(p, "List", list)
	end
	listDirty = false
end

local function pushState(heist: any)
	local st = stateFor(heist)
	for p in pairs(heist.Crew) do
		fire(p, "State", st)
	end
end

local function emit(heist: any, kind: string, payload: any?)
	listDirty = true
	local cb = heist.Def.OnEvent
	if type(cb) == "function" then
		local ok, err = pcall(cb, heist, kind, payload)
		if not ok then
			warn("[HeistKit] OnEvent " .. kind .. " : " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------
-- Création / cycle de vie
----------------------------------------------------------------------

function HeistKit.Create(def: any): any
	assert(type(def) == "table" and type(def.Steps) == "table" and #def.Steps > 0, "HeistKit.Create : def.Steps requis")
	counter += 1
	local kind = type(def.Kind) == "string" and def.Kind or "Bank"
	local self = setmetatable({}, Heist)
	self.Id = kind .. "#" .. counter
	self.Kind = kind
	self.Def = def
	self.State = "Idle"
	self.MaxCrew = math.clamp(math.floor(tonumber(def.MaxCrew) or H().MaxCrew or 4), 1, 8)
	self.Crew = {} :: { [Player]: Member }
	self.Order = {} :: { Player }
	self.CrewCount = 0
	self.Leader = nil :: Player?
	self.StepIndex = 0
	self.Progress = 0
	self.Jammed = false
	self.Alarm = false
	self.DoneSteps = {}
	self.Spots = {}
	self.Taken = {}
	self.TotalLoot = 0
	self.Delivered = 0
	self.Dropped = {}
	self.Drop = nil :: Vector3?
	self.LobbyEndsAt = nil :: number?
	self.EndsAt = nil :: number?
	self.Success = nil :: boolean?
	self.Rng = Random.new()
	heists[self.Id] = self
	table.insert(order, self.Id)
	return self
end

function HeistKit.Get(id: any): any?
	return type(id) == "string" and heists[id] or nil
end

function HeistKit.All(): { any }
	local list = {}
	for _, id in ipairs(order) do
		table.insert(list, heists[id])
	end
	return list
end

-- Déjà dans un casse (en préparation ou en cours) ?
function HeistKit.IsBusy(player: Player): boolean
	for _, h in pairs(heists) do
		if (h.State == "Lobby" or h.State == "Running") and h.Crew[player] then
			return true
		end
	end
	return false
end

function Heist:Open(text: string?)
	if self.State ~= "Idle" then
		return
	end
	self.State = "Lobby"
	self.LobbyEndsAt = nil
	for _, p in ipairs(townPlayers()) do
		fire(p, "Announce", { Text = text or "", Icon = self.Def.Icon or "🕶️", Kind = self.Kind, Name = self.Def.Name })
	end
	emit(self, "Opened", nil)
end

local function removeMember(heist: any, player: Player, reason: string?)
	local m = heist.Crew[player]
	if not m then
		return
	end
	dropBag(heist, m, nil)
	heist.Crew[player] = nil
	local i = table.find(heist.Order, player)
	if i then
		table.remove(heist.Order, i)
	end
	heist.CrewCount = #heist.Order
	if heist.Leader == player then
		heist.Leader = heist.Order[1]
	end
	fire(player, "Left", { Id = heist.Id, Reason = reason })
	listDirty = true
end

local function beginStep(heist: any, index: number)
	heist.StepIndex = index
	heist.Progress = 0
	heist.Jammed = false
	local step = stepOf(heist)
	if not step then
		return
	end
	local t = now()
	heist.StepAt = t
	if step.Kind == "Drill" then
		heist.DrillLast = t
		heist.Jams = {}
		local n = math.max(0, math.floor(tonumber(step.Jams) or H().DrillJams or 2))
		for j = 1, n do
			-- blocages répartis entre 20 % et 85 %
			table.insert(heist.Jams, 0.2 + (j - 1 + heist.Rng:NextNumber(0.15, 0.85)) * (0.65 / n))
		end
	elseif step.Kind == "Grab" then
		heist.Spots = step.Spots or {}
		heist.Taken = {}
		heist.TotalLoot = #heist.Spots
	elseif step.Kind == "Escape" then
		local drops = step.Drops or {}
		local list = {}
		for _, d in ipairs(drops) do
			local p = resolve(d)
			if p then
				table.insert(list, p)
			end
		end
		heist.Drop = list[heist.Rng:NextInteger(1, math.max(1, #list))] or resolve(step.Position)
		-- ceux qui ont un sac le gardent ; le butin non pris est perdu
	end
	for _, m in pairs(heist.Crew) do
		m.Code = nil
		m.GrabPile = nil
	end
	if step.Alarm and not heist.Alarm then
		heist.Alarm = true
		emit(heist, "Alarm", { Step = step.Id })
	end
	emit(heist, "Step", { Index = index, Id = step.Id })
	pushState(heist)
end

local finish: (heist: any, reason: string) -> ()

local function completeStep(heist: any)
	local step = stepOf(heist)
	if step then
		heist.DoneSteps[step.Id] = true
	end
	if heist.StepIndex >= #heist.Def.Steps then
		finish(heist, "done")
	else
		beginStep(heist, heist.StepIndex + 1)
	end
	listDirty = true
end

function Heist:Start(): boolean
	if self.State ~= "Lobby" or self.CrewCount < 1 then
		return false
	end
	self.State = "Running"
	local t = now()
	self.StartedAt = t
	self.EndsAt = t + (tonumber(self.Def.Duration) or 240)
	self.CrewAtStart = self.CrewCount
	for p in pairs(self.Crew) do
		local hd = heistData(p)
		if hd then
			hd.Done += 1
		end
	end
	emit(self, "Started", { Crew = self.CrewCount })
	beginStep(self, 1)
	return true
end

-- Récompenses + fin. reason : "done" (tout fait) | "time" | "empty" | "cancel"
finish = function(heist: any, reason: string)
	if heist.State == "Done" then
		return
	end
	-- les sacs encore portés à la fin ne comptent pas (pas livrés)
	for _, m in pairs(heist.Crew) do
		setBag(heist, m, 0)
	end
	heist.State = "Done"
	heist.DoneAt = now()
	local crew = heist.CrewCount
	local fill = HeistRules.Fill(heist.Delivered, math.max(1, heist.CrewAtStart or crew), heist.TotalLoot)
	local paid = reason ~= "cancel" and heist.Delivered > 0 and fill >= (H().MinFill or 0.2)
	-- (casse sans butin à porter : aucune étape Grab) réussi = tout fait
	if reason == "done" and heist.TotalLoot == 0 and heist.Delivered == 0 then
		fill, paid = 1, true
	end
	heist.Success = paid
	local results = {}
	for _, p in ipairs(heist.Order) do
		local dop, dia, capped = 0, 0, false
		local hd = heistData(p)
		if paid and hd then
			local stats = nil
			if services and services.GameService then
				local ok, s = pcall(services.GameService.GetStats, services.GameService, p)
				stats = ok and s or nil
			end
			dop, dia, capped = HeistRules.Reward(heist.Kind, stats, fill, crew, hd[heist.Kind])
			if dop > 0 then
				if services and services.GameService then
					services.GameService:AddDopamine(p, dop)
				end
				if hd[heist.Kind] ~= nil then
					hd[heist.Kind] += 1
				end
			end
			if dia > 0 and services and services.BankService then
				local ok, granted = pcall(services.BankService.GrantDiamonds, services.BankService, p, dia, heist.Kind, true)
				dia = ok and tonumber(granted) or 0
			end
			hd.Success += 1
			hd.Best = math.max(hd.Best, math.floor(fill * 100 + 0.5))
			if services and services.GameService then
				services.GameService:MarkDirty(p)
			end
		end
		local row = {
			Id = heist.Id,
			Kind = heist.Kind,
			Name = heist.Def.Name,
			Icon = heist.Def.Icon,
			Success = paid,
			Reason = reason,
			Fill = fill,
			Delivered = heist.Delivered,
			-- (butin possible : sacs de l'équipe, au plus les piles du casse)
			Total = math.min(heist.TotalLoot, math.max(1, heist.CrewAtStart or crew) * (H().BagCapacity or 3)),
			Crew = crew,
			Dopamine = dop,
			Diamonds = dia,
			Capped = capped,
			Text = if paid
				then T(p, "%s Heist done! +%s Dopamine · +%d 💎", heist.Def.Icon or "🕶️", NumberFormatter.Format(dop), dia)
				else T(p, "🚨 Heist failed: the loot is lost"),
		}
		results[p] = row
		fire(p, "Result", row)
	end
	emit(heist, "Finished", { Success = paid, Reason = reason, Fill = fill, Results = results })
	listDirty = true
end

function Heist:Cancel(reason: string?)
	if self.State == "Lobby" or self.State == "Running" then
		finish(self, "cancel")
		for p in pairs(self.Crew) do
			fire(p, "Toast", reason or "")
		end
	end
	self.State = "Done"
	self.DoneAt = now()
	listDirty = true
end

function Heist:Destroy()
	for p in pairs(self.Crew) do
		local m = self.Crew[p]
		if m then
			setBag(self, m, 0)
		end
	end
	heists[self.Id] = nil
	local i = table.find(order, self.Id)
	if i then
		table.remove(order, i)
	end
	listDirty = true
end

----------------------------------------------------------------------
-- Actions des joueurs
----------------------------------------------------------------------

local INTERVALS = {
	sync = 1,
	join = 0.5,
	leave = 0.5,
	start = 0.5,
	tap = 0.05,
	hackBegin = 0.5,
	hackAnswer = 0.4,
	unjam = 0.3,
	grabBegin = 0.2,
	grabEnd = 0.2,
	escape = 0.5,
	pickup = 0.3,
}

local function memberOf(heist: any, player: Player): Member?
	return heist.Crew[player]
end

local function act(player: Player, action: string, heist: any?, arg: any): (boolean, any, any)
	if action == "sync" then
		local list = {}
		for _, id in ipairs(order) do
			local h = heists[id]
			if h and h.State ~= "Idle" then
				table.insert(list, summary(h))
			end
		end
		local mine = nil
		for _, h in pairs(heists) do
			if h.Crew[player] and (h.State == "Lobby" or h.State == "Running") then
				mine = stateFor(h)
			end
		end
		return true, list, mine
	end
	if not heist then
		return false, T(player, "This heist is over")
	end
	if not inTown(player) then
		return false, T(player, "Invalid request")
	end
	local member = memberOf(heist, player)
	local step = stepOf(heist)
	local t = now()

	if action == "join" then
		if heist.State ~= "Lobby" then
			return false, T(player, "This heist has already started")
		end
		if member then
			return true, nil
		end
		if HeistKit.IsBusy(player) then
			return false, T(player, "You are already in a heist")
		end
		if heist.CrewCount >= heist.MaxCrew then
			return false, T(player, "The crew is full")
		end
		local lobby = heist.Def.Lobby or {}
		if not near(player, resolve(lobby.Position), lobby.Radius or 16) then
			return false, T(player, "Get closer to the meeting point")
		end
		local root = rootOf(player)
		heist.Crew[player] = {
			Player = player,
			Joined = t,
			Bag = 0,
			LastPos = root and root.Position or nil,
			LastT = t,
			Code = nil,
			CodeAt = 0,
			GrabPile = nil,
			GrabAt = 0,
			LastTap = 0,
			WalkBase = nil,
		}
		table.insert(heist.Order, player)
		heist.CrewCount = #heist.Order
		if not heist.Leader then
			heist.Leader = player
		end
		if not heist.LobbyEndsAt then
			heist.LobbyEndsAt = t + (tonumber(heist.Def.LobbySeconds) or H().LobbySeconds or 30)
		end
		listDirty = true
		pushState(heist)
		return true, T(player, "🕶️ You joined the crew!")
	elseif action == "leave" then
		if not member then
			return false, T(player, "Invalid request")
		end
		removeMember(heist, player, "left")
		if heist.State == "Lobby" and heist.CrewCount == 0 then
			heist.LobbyEndsAt = nil
		end
		pushState(heist)
		return true, T(player, "You left the crew")
	end

	if not member then
		return false, T(player, "Join the crew first")
	end
	if action == "start" then
		if heist.State ~= "Lobby" then
			return false, T(player, "Invalid request")
		end
		if heist.Leader ~= player then
			return false, T(player, "Only the crew leader can start")
		end
		if heist.Def.ManualStart == false then
			return false, T(player, "The heist starts by itself")
		end
		heist:Start()
		return true, nil
	end
	if heist.State ~= "Running" or not step then
		return false, T(player, "Invalid request")
	end
	local radius = step.Radius or 9

	if action == "tap" then
		if step.Kind ~= "Crowbar" or not near(player, resolve(step.Position), radius) then
			return false, T(player, "Get closer")
		end
		local n = math.clamp(math.floor(tonumber(arg) or 1), 1, 6)
		-- cadence : au plus 1 coup par CrowbarMinInterval depuis le dernier envoi
		local minI = H().CrowbarMinInterval or 0.08
		local allowed = math.max(1, math.floor((t - member.LastTap) / minI))
		member.LastTap = t
		local taps = math.min(n, allowed)
		local need = math.max(1, math.floor(tonumber(step.Taps) or H().CrowbarTaps or 12))
		heist.Progress = math.min(1, heist.Progress + taps / need)
		if heist.Progress >= 1 then
			completeStep(heist)
		else
			pushState(heist)
		end
		return true, nil
	elseif action == "hackBegin" then
		if step.Kind ~= "Hack" or not near(player, resolve(step.Position), radius) then
			return false, T(player, "Get closer")
		end
		member.Code = HeistRules.HackCode(function(a, b)
			return heist.Rng:NextInteger(a, b)
		end, step.Length or H().HackLength)
		member.CodeAt = t
		return true, nil, { Code = member.Code, Show = 2.6 }
	elseif action == "hackAnswer" then
		if step.Kind ~= "Hack" or not member.Code or not near(player, resolve(step.Position), radius) then
			return false, T(player, "Invalid request")
		end
		if t - member.CodeAt < (H().HackMinSeconds or 3) then
			return false, T(player, "Too fast!")
		end
		if HeistRules.CheckCode(member.Code, arg) then
			member.Code = nil
			completeStep(heist)
			return true, T(player, "✅ Hacked!")
		end
		-- mauvais code : nouveau code
		member.Code = HeistRules.HackCode(function(a, b)
			return heist.Rng:NextInteger(a, b)
		end, step.Length or H().HackLength)
		member.CodeAt = t
		return false, T(player, "❌ Wrong code: try again"), { Code = member.Code, Show = 2.6 }
	elseif action == "unjam" then
		if step.Kind ~= "Drill" or not heist.Jammed or not near(player, resolve(step.Position), radius) then
			return false, T(player, "Invalid request")
		end
		heist.Jammed = false
		heist.DrillLast = t
		listDirty = true
		pushState(heist)
		return true, T(player, "🔧 Unjammed!")
	elseif action == "grabBegin" or action == "grabEnd" then
		local i = math.floor(tonumber(arg) or 0)
		local spot = step.Kind == "Grab" and heist.Spots[i] or nil
		if not spot or heist.Taken[i] or not near(player, resolve(spot), step.Radius or 6) then
			return false, T(player, "Get closer")
		end
		if member.Bag >= (H().BagCapacity or 3) then
			return false, T(player, "Your bag is full!")
		end
		if action == "grabBegin" then
			member.GrabPile = i
			member.GrabAt = t
			return true, nil
		end
		local need = (tonumber(step.Seconds) or H().GrabSeconds or 1.5) - 0.3
		if member.GrabPile ~= i or t - member.GrabAt < need then
			return false, T(player, "Too fast!")
		end
		member.GrabPile = nil
		heist.Taken[i] = true
		setBag(heist, member, member.Bag + 1)
		emit(heist, "Bag", { Player = player, Bag = member.Bag })
		local left = 0
		for j = 1, #heist.Spots do
			if not heist.Taken[j] then
				left += 1
			end
		end
		if left == 0 then
			completeStep(heist)
		else
			pushState(heist)
		end
		return true, T(player, "💰 Loot +1 (%d/%d)", member.Bag, H().BagCapacity or 3)
	elseif action == "escape" then
		if step.Kind ~= "Grab" then
			return false, T(player, "Invalid request")
		end
		if member.Bag <= 0 then
			return false, T(player, "Fill your bag first!")
		end
		completeStep(heist)
		return true, nil
	elseif action == "pickup" then
		local i = math.floor(tonumber(arg) or 0)
		local bag = heist.Dropped[i]
		if not bag then
			return false, T(player, "Invalid request")
		end
		local root = rootOf(player)
		if not root or (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(bag.Pos.X, 0, bag.Pos.Z)).Magnitude > 8 + (H().Range or 5) then
			return false, T(player, "Get closer")
		end
		local cap = (H().BagCapacity or 3) * 2
		if member.Bag + bag.Value > cap then
			return false, T(player, "Your bag is full!")
		end
		table.remove(heist.Dropped, i)
		setBag(heist, member, member.Bag + bag.Value)
		pushState(heist)
		return true, T(player, "💰 Bag picked up!")
	end
	return false, T(player, "Invalid request")
end

local function onInvoke(player: Player, action: any, heistId: any, arg: any): (boolean, any, any)
	if type(action) ~= "string" or #action > 16 or INTERVALS[action] == nil then
		return false, T(player, "Invalid request")
	end
	if not RateLimiter.Check(player, "heist:" .. action, INTERVALS[action]) then
		return false, T(player, "Slow down!")
	end
	local heist = HeistKit.Get(heistId)
	local ok, a, b, c = pcall(act, player, action, heist, arg)
	if not ok then
		warn("[HeistKit] " .. action .. " : " .. tostring(a))
		return false, T(player, "Invalid request")
	end
	return a, b, c
end

----------------------------------------------------------------------
-- Boucle (4 Hz)
----------------------------------------------------------------------

local function tickHeist(heist: any, dt: number)
	local t = now()
	if heist.State == "Lobby" then
		-- membres partis / sortis de la ville
		for _, p in ipairs(table.clone(heist.Order)) do
			if not p.Parent or not inTown(p) then
				removeMember(heist, p, "gone")
			end
		end
		if heist.CrewCount == 0 then
			heist.LobbyEndsAt = nil
		elseif heist.LobbyEndsAt and t >= heist.LobbyEndsAt and heist.Def.AutoStart ~= false then
			heist:Start()
		end
		return
	end
	if heist.State == "Done" then
		return
	end
	-- en cours
	for _, p in ipairs(table.clone(heist.Order)) do
		local m = heist.Crew[p]
		if m then
			local root, humanoid = rootOf(p)
			if not p.Parent or not inTown(p) or not root or (humanoid and humanoid.Health <= 0) then
				removeMember(heist, p, "gone")
			else
				-- anti-téléportation des porteurs de sac
				local pos = root.Position
				if m.LastPos and m.Bag > 0 then
					local dist = (pos - m.LastPos).Magnitude
					if not HeistRules.SpeedOk(dist, t - m.LastT) then
						dropBag(heist, m, m.LastPos)
						fire(p, "Toast", T(p, "💨 Too fast! Your bag fell"))
					end
				end
				m.LastPos, m.LastT = pos, t
			end
		end
	end
	if heist.CrewCount == 0 then
		finish(heist, "empty")
		return
	end
	local step = stepOf(heist)
	if step and step.Kind == "Drill" then
		if not heist.Jammed then
			local seconds = tonumber(step.Seconds) or H().DrillSeconds or 22
			heist.Progress = math.min(1, heist.Progress + (t - (heist.DrillLast or t)) / seconds)
			heist.DrillLast = t
			local nextJam = heist.Jams and heist.Jams[1]
			if nextJam and heist.Progress >= nextJam then
				table.remove(heist.Jams, 1)
				heist.Jammed = true
				listDirty = true
				for p in pairs(heist.Crew) do
					fire(p, "Toast", T(p, "⚠️ The drill is jammed! Press E to unjam it"))
				end
			end
			if heist.Progress >= 1 then
				completeStep(heist)
			end
		else
			heist.DrillLast = t
		end
	elseif step and step.Kind == "Escape" and heist.Drop then
		local radius = step.Radius or 14
		for p, m in pairs(heist.Crew) do
			if m.Bag > 0 and near(p, heist.Drop, radius) then
				heist.Delivered += m.Bag
				local n = m.Bag
				setBag(heist, m, 0)
				emit(heist, "Delivered", { Player = p, Value = n })
				for q in pairs(heist.Crew) do
					fire(q, "Toast", T(q, "💰 %s delivered %d loot!", p.DisplayName, n))
				end
			end
		end
		local carried = 0
		for _, m in pairs(heist.Crew) do
			carried += m.Bag
		end
		if carried == 0 and #heist.Dropped == 0 then
			finish(heist, "done")
			return
		end
	end
	if heist.EndsAt and t >= heist.EndsAt then
		finish(heist, "time")
	end
end

local function loop()
	while started do
		local dt = task.wait(TICK)
		local t = now()
		stateClock += dt
		local sendState = stateClock >= STATE_EVERY
		if sendState then
			stateClock = 0
		end
		for _, id in ipairs(table.clone(order)) do
			local heist = heists[id]
			if heist then
				local ok, err = pcall(tickHeist, heist, dt)
				if not ok then
					warn("[HeistKit] " .. id .. " : " .. tostring(err))
				end
				if sendState and (heist.State == "Lobby" or heist.State == "Running") then
					pushState(heist)
				end
				-- un casse fini disparaît de la liste après DONE_HOLD s (son
				-- propriétaire peut le détruire / en recréer un autre)
				if heist.State == "Done" and heist.DoneAt and t - heist.DoneAt > DONE_HOLD and not heist.Hidden then
					heist.Hidden = true
					heist.State = "Idle"
					listDirty = true
				end
			end
		end
		if listDirty then
			pcall(pushList)
		end
	end
end

----------------------------------------------------------------------
-- Branchement
----------------------------------------------------------------------

function HeistKit.Init(allServices: any)
	services = allServices
end

function HeistKit.Start()
	if started then
		return
	end
	started = true
	remote("HeistEvent", "RemoteEvent")
	local rf = remote("Heist", "RemoteFunction")
	if rf then
		(rf :: RemoteFunction).OnServerInvoke = onInvoke
	end
	task.spawn(loop)
end

function HeistKit.PlayerRemoving(player: Player)
	for _, h in pairs(heists) do
		if h.Crew[player] then
			removeMember(h, player, "gone")
		end
	end
end

-- (tests / débogage) pas de la boucle à la main
function HeistKit.Tick(dt: number)
	for _, id in ipairs(table.clone(order)) do
		local heist = heists[id]
		if heist then
			tickHeist(heist, dt)
		end
	end
	if listDirty then
		pushList()
	end
end

HeistKit.Act = act -- (tests)
HeistKit.Summary = summary
HeistKit.StateFor = stateFor

return HeistKit
