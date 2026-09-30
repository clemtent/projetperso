--[[
	ImpactService (ModuleScript)
	Emplacement : ServerScriptService > Services > ImpactService

	💥 v10 (PHYS10) : collisions réalistes + "se faire renverser" (façon
	dessin animé : on tombe, étoiles, on se relève ; jamais de mort, jamais de
	perte de vie). Règles et chiffres : Shared/ImpactRules.

	  - GROUPES DE COLLISION : enregistre "Riders" et "Ragdoll" et applique la
	    matrice complète (ImpactRules.MATRIX) ; CarService règle déjà
	    avatars <-> voitures et voitures <-> voitures (collision : OUI).
	  - VOITURES DES JOUEURS (et tout modèle étiqueté "DopamineMover" par
	    CollectionService : voitures IA des courses…) : le SERVEUR détecte le
	    choc (20 fois / s) avec la vitesse de la voiture ; >= 12 studs/s ->
	    RENVERSÉ, >= 4,5 -> titube. Le propriétaire n'est jamais renversé par
	    sa propre voiture ; un avatar assis (conducteur, manège) non plus.
	  - RAGDOLL CÔTÉ SERVEUR (répliqué : tout le monde voit le corps tomber) :
	    Motor6D coupés + BallSocket / charnières (ImpactRules.Ragdoll), puis le
	    client du joueur (propriétaire réseau) passe l'Humanoid en "Physics"
	    et donne l'élan. Le client relève le personnage ("up") ; le serveur
	    restaure EXACTEMENT les articulations (et d'office après 6 s).
	  - CIRCULATION (voitures d'ambiance : côté client) : le client détecte et
	    tombe tout de suite, puis PRÉVIENT le serveur ("traffic") qui vérifie
	    (vitesse plausible, recharge, zone sûre, en ville, pas assis) et fait
	    le ragdoll répliqué + les étoiles pour les autres.
	  - ANTI-ABUS : pas de nouveau renversement moins de 3 s après s'être
	    relevé, jamais dans une zone sûre (scène de la place, intérieurs des
	    boutiques, attribut SafeZone), remote limité en fréquence.

	Attributs du PERSONNAGE (répliqués ; chaque client anime les autres) :
	  DopaKnockAt = heure serveur du renversement (étoiles)
	  DopaUpAt    = heure serveur où il se relève ; DopaUpFace = sur le dos ?
	  DopaStumbleAt / DopaStumbleDir = titubement (heure, direction monde)

	RemoteEvent "Impact" :
	  S -> C ("knock", élan: Vector3, rotation: Vector3, vitesse)   renversé
	         ("stumble", poussée: Vector3, direction: Vector3)       titube
	  C -> S ("traffic", "knock" | "stumble", vitesseVoiture: Vector3, dir: Vector3)
	         ("up", surLeDos: boolean)                               relevé
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage.Shared.Net)
local ImpactRules = require(ReplicatedStorage.Shared.ImpactRules)
local RateLimiter = require(script.Parent.RateLimiter)

local ImpactService = {}

ImpactService.CHECK_INTERVAL = 0.05 -- (s) détection des chocs (20 Hz)
ImpactService.ZONE_REFRESH = 5 -- (s) zones sûres relues
ImpactService.MOVER_TAG = "DopamineMover"
ImpactService.LATENCY_AHEAD = 0.08 -- (s) anticipation (positions répliquées en retard)

type Victim = {
	Down: boolean,
	KnockAt: number?,
	UpAt: number?,
	StumbleAt: number?,
	Ragdoll: any,
	Character: Model?,
}

local services: any = nil
local victims: { [Player]: Victim } = {}
local zones: { ImpactRules.Zone } = {}
local zonesAt = -math.huge
local movers: { [Instance]: { Pos: Vector3, T: number, Vel: Vector3 } } = setmetatable({} :: any, { __mode = "k" })
local remote: RemoteEvent? = nil

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
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

local function toast(player: Player, text: string)
	pcall(function()
		Net.Event("WorldEvent"):FireClient(player, "Toast", text)
	end)
end

local function victimOf(player: Player): Victim
	local v = victims[player]
	if not v then
		v = { Down = false }
		victims[player] = v
	end
	return v
end

local function isFinite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

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

local function inTown(player: Player): boolean
	local world = services and services.WorldService
	if world and world.IsInTown then
		return world:IsInTown(player)
	end
	return true
end

local function refreshZones()
	local t = os.clock()
	if t - zonesAt < ImpactService.ZONE_REFRESH then
		return
	end
	zonesAt = t
	local ok, list = pcall(ImpactRules.CollectSafeZones, workspace:FindFirstChild("DopamineTown"))
	if ok then
		zones = list
	end
end

----------------------------------------------------------------------
-- Renverser / relever
----------------------------------------------------------------------

local function standUp(player: Player, faceUp: boolean?)
	local v = victims[player]
	if not v or not v.Down then
		return
	end
	v.Down = false
	v.UpAt = now()
	pcall(ImpactRules.Restore, v.Ragdoll)
	v.Ragdoll = nil
	local character = v.Character
	if character and character.Parent then
		pcall(function()
			character:SetAttribute("DopaUpFace", faceUp == true)
			character:SetAttribute("DopaUpAt", v.UpAt)
		end)
	end
end
ImpactService.StandUp = standUp

-- Peut-on toucher ce joueur (en ville, debout, hors zone sûre) ?
local function eligible(player: Player): (boolean, Model?, Humanoid?, BasePart?)
	local character, humanoid, root = characterOf(player)
	if not character or not humanoid or not root then
		return false, nil, nil, nil
	end
	if not inTown(player) then
		return false, nil, nil, nil
	end
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		return false, nil, nil, nil
	end
	refreshZones()
	if ImpactRules.InSafeZone(root.Position, zones) then
		return false, nil, nil, nil
	end
	return true, character, humanoid, root
end

-- Renverse `player` (ragdoll répliqué). notify : prévenir son client (choc
-- détecté par le serveur ; pour la circulation, le client est déjà tombé).
function ImpactService.Knock(player: Player, dir: Vector3, speed: number, notify: boolean, driver: Player?): boolean
	local ok, character, _humanoid, root = eligible(player)
	if not ok or not character or not root then
		return false
	end
	local v = victimOf(player)
	local t = now()
	if not ImpactRules.CanKnock(v, t) then
		return false
	end
	local state = ImpactRules.Ragdoll(character, { Local = false })
	v.Down = true
	v.KnockAt = t
	v.UpAt = nil
	v.Ragdoll = state
	v.Character = character
	pcall(function()
		character:SetAttribute("DopaUpAt", nil)
		character:SetAttribute("DopaKnockAt", t)
	end)
	if notify and remote then
		local linear, spin = ImpactRules.Impulse(dir, speed, root.AssemblyLinearVelocity)
		pcall(function()
			(remote :: RemoteEvent):FireClient(player, "knock", linear, spin, speed)
		end)
	end
	if driver and driver ~= player then
		toast(driver, T(driver, "⚠️ Careful! You knocked %s over", player.DisplayName))
	end
	-- filet : relevé d'office si le client ne répond pas
	local gen = t
	task.delay(ImpactRules.FAILSAFE, function()
		local cur = victims[player]
		if cur and cur.Down and cur.KnockAt == gen then
			standUp(player, true)
		end
	end)
	return true
end

function ImpactService.Stumble(player: Player, dir: Vector3, speed: number, notify: boolean): boolean
	local ok, character = eligible(player)
	if not ok or not character then
		return false
	end
	local v = victimOf(player)
	local t = now()
	if not ImpactRules.CanStumble(v, t) then
		return false
	end
	v.StumbleAt = t
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local unit = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	pcall(function()
		character:SetAttribute("DopaStumbleDir", unit)
		character:SetAttribute("DopaStumbleAt", t)
	end)
	if notify and remote then
		pcall(function()
			(remote :: RemoteEvent):FireClient(player, "stumble", ImpactRules.StumblePush(unit, speed), unit)
		end)
	end
	return true
end

----------------------------------------------------------------------
-- Détection (voitures des joueurs + modèles "DopamineMover")
----------------------------------------------------------------------

-- Boîte de collision + vitesse d'un mobile ; `owner` = son conducteur légitime
local function moverInfo(model: Instance): (CFrame?, Vector3?, Vector3?)
	local root: BasePart? = nil
	if model:IsA("BasePart") then
		root = model
	elseif model:IsA("Model") then
		root = model.PrimaryPart
	end
	if not root or not root.Parent then
		return nil, nil, nil
	end
	local cf, size = root.CFrame, root.Size
	local vel = root.AssemblyLinearVelocity
	if root.Anchored then
		-- (mobile déplacé par CFrame : vitesse = dérivée de la position)
		local t = os.clock()
		local rec = movers[root]
		if rec then
			local dt = t - rec.T
			if dt > 1e-3 then
				local raw = (cf.Position - rec.Pos) / dt
				if raw.Magnitude > 150 then
					raw = Vector3.zero -- (téléporté)
				end
				rec.Vel = rec.Vel:Lerp(raw, 0.6)
				rec.Pos = cf.Position
				rec.T = t
			end
			vel = rec.Vel
		else
			movers[root] = { Pos = cf.Position, T = t, Vel = Vector3.zero }
			vel = Vector3.zero
		end
	end
	if model:IsA("Model") then
		-- (boîte : celle de la pièce racine, au moins la taille annoncée)
		local w = tonumber(model:GetAttribute("Width"))
		local l = tonumber(model:GetAttribute("Length"))
		if w and l and (w > size.X + 0.5 or l > size.Z + 0.5) then
			size = Vector3.new(math.max(size.X, w - 0.2), size.Y, math.max(size.Z, l - 0.2))
		end
	end
	return cf, size, vel
end

local function checkMover(model: Instance, owner: Player?)
	local cf, size, vel = moverInfo(model)
	if not cf or not size or not vel or not isFinite(vel) then
		return
	end
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if speed < ImpactRules.STUMBLE_SPEED then
		return
	end
	local ahead = speed * ImpactService.LATENCY_AHEAD
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= owner then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - cf.Position).Magnitude < size.Magnitude / 2 + ahead + 6 then
				local impact, dir = ImpactRules.Contact(cf, size, vel, root.Position, root.AssemblyLinearVelocity, ahead)
				if impact and dir then
					local kind = ImpactRules.Classify(impact)
					if kind == "knock" then
						ImpactService.Knock(player, dir, impact, true, owner)
					elseif kind == "stumble" then
						ImpactService.Stumble(player, dir, impact, true)
					end
				end
			end
		end
	end
end

local function detect()
	local carService = services and services.CarService
	if carService and carService.GetCar then
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, model = pcall(carService.GetCar, carService, player)
			if ok and model and model.Parent then
				checkMover(model, player)
			end
		end
	end
	local okTag, tagged = pcall(function()
		return CollectionService:GetTagged(ImpactService.MOVER_TAG)
	end)
	if okTag and type(tagged) == "table" then
		for _, model in ipairs(tagged) do
			if model:IsDescendantOf(workspace) then
				local ownerId = tonumber(model:GetAttribute("OwnerId"))
				local owner = ownerId and Players:GetPlayerByUserId(ownerId) or nil
				checkMover(model, owner)
			end
		end
	end
end

----------------------------------------------------------------------
-- Remote
----------------------------------------------------------------------

local function onImpact(player: Player, action: any, a: any, b: any, c: any)
	if type(action) ~= "string" then
		return
	end
	if action == "up" then
		if not RateLimiter.Check(player, "Impact_up", 0.3) then
			return
		end
		local v = victims[player]
		-- (au moins une seconde au sol : pas de relevé instantané)
		if v and v.Down and v.KnockAt and now() - v.KnockAt >= 1 then
			standUp(player, a == true)
		end
		return
	end
	if action ~= "traffic" then
		return
	end
	if not RateLimiter.Check(player, "Impact_traffic", 0.5) then
		return
	end
	if type(a) ~= "string" or typeof(b) ~= "Vector3" or typeof(c) ~= "Vector3" then
		return
	end
	if not isFinite(b) or not isFinite(c) then
		return
	end
	local speed = Vector3.new(b.X, 0, b.Z).Magnitude
	if speed > ImpactRules.MAX_SPEED then
		return
	end
	-- (le type annoncé doit correspondre à la vitesse)
	local kind = ImpactRules.Classify(speed)
	if a == "knock" and kind == "knock" then
		ImpactService.Knock(player, c, speed, false, nil)
	elseif a == "stumble" and (kind == "knock" or kind == "stumble") then
		ImpactService.Stumble(player, c, speed, false)
	end
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function ImpactService:Init(allServices)
	services = allServices
end

function ImpactService:Start()
	ImpactRules.SetupGroups(PhysicsService)
	local ok, event = pcall(Net.Event, "Impact")
	if ok and event then
		remote = event
		event.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any, c: any)
			local okCall, err = pcall(onImpact, player, action, a, b, c)
			if not okCall then
				warn("[ImpactService] " .. tostring(err))
			end
		end)
	else
		warn("[ImpactService] remote \"Impact\" absent (Net.Events)")
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			-- nouveau personnage : on oublie l'ancien ragdoll (détruit avec lui)
			local v = victims[player]
			if v then
				v.Down = false
				v.Ragdoll = nil
				v.Character = character
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock >= ImpactService.CHECK_INTERVAL then
			clock = 0
			local okDetect, err = pcall(detect)
			if not okDetect then
				warn("[ImpactService] détection : " .. tostring(err))
			end
		end
	end)
end

function ImpactService:PlayerRemoving(player: Player)
	local v = victims[player]
	if v then
		pcall(ImpactRules.Restore, v.Ragdoll)
	end
	victims[player] = nil
end

-- (tests)
function ImpactService.Debug(): any
	return {
		Victims = victims,
		Zones = function()
			return zones
		end,
		Detect = detect,
		OnImpact = onImpact,
		RefreshZones = function()
			zonesAt = -math.huge
			refreshZones()
		end,
	}
end

return ImpactService
