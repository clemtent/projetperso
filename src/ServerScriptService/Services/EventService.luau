--[[
	EventService (ModuleScript)
	Emplacement : ServerScriptService > Services > EventService

	Événements aléatoires :
	  - "Dopamine Rush" : x2 sur tous les gains pendant 30 s, pour TOUT le serveur ;
	  - objets à cliquer vite (Config.Spawners) : étoile dorée, éclair,
	    notification de téléphone, e-mail, don du live. Chaque type apparaît
	    chez un joueur seulement s'il possède la Feature correspondante
	    (et, si RequiresFollow, seulement s'il est abonné au live :
	    data.LiveFollowed).
	Le serveur décide quand ils arrivent et valide les clics.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)

local EventService = {}

local services
local random = Random.new()

-- Dans Studio, les événements arrivent plus vite pour pouvoir les tester
local speedup = RunService:IsStudio() and Config.Events.StudioSpeedup or 1

local SPAWN_GRACE = 0.5 -- marge (s) pour la latence réseau
local SCHEDULER_STEP = 0.25 -- intervalle (s) de la boucle des apparitions

local rush = {
	Active = false,
	EndsAt = 0, -- heure serveur (workspace:GetServerTimeNow())
	Token = 0, -- change à chaque (re)programmation de la fin du Rush
}

--[[
	Apparitions par joueur :
	[Player] = {
		Pending = { [id] = { Kind, ExpiresAt } }, -- objets affichés, pas encore cliqués
		NextAt = { [kind] = os.clock() de la prochaine apparition (nil = Feature absente) },
	}
]]
local spawnStates = {}

function EventService:Init(allServices)
	services = allServices
end

----------------------------------------------------------------------
-- Dopamine Rush (global)
----------------------------------------------------------------------

function EventService:GetMultiplier(): number
	return rush.Active and Config.Events.Rush.Multiplier or 1
end

local function rushPayload()
	return {
		Active = rush.Active,
		EndsAt = rush.EndsAt,
		Name = Config.Events.Rush.Name,
		Multiplier = Config.Events.Rush.Multiplier,
	}
end

function EventService:SendState(player: Player)
	Net.Event("EventUpdate"):FireClient(player, rushPayload())
end

-- Programme la fin du Rush en cours (un jeton évite qu'une ancienne fin
-- programmée coupe un Rush prolongé entre-temps)
local function scheduleRushEnd()
	rush.Token += 1
	local token = rush.Token
	local remaining = math.max(0, rush.EndsAt - workspace:GetServerTimeNow())
	task.delay(remaining, function()
		if rush.Token ~= token or not rush.Active then
			return
		end
		rush.Active = false
		Net.Event("EventUpdate"):FireAllClients(rushPayload())
		services.GameService:MarkAllDirty()
	end)
end

-- Lance un Dopamine Rush (aussi utilisé par la commande de test /rush).
-- `extend` = true (Rush acheté avec des Robux) : si un Rush est déjà en
-- cours, il est prolongé de sa durée au lieu d'être ignoré.
-- Renvoie true si un Rush a été lancé ou prolongé.
function EventService:StartRush(extend: boolean?): boolean
	local settings = Config.Events.Rush
	if rush.Active then
		if not extend then
			return false
		end
		rush.EndsAt += settings.Duration
		scheduleRushEnd()
		Net.Event("EventUpdate"):FireAllClients(rushPayload())
		services.GameService:MarkAllDirty()
		services.GameService:NotifyAll(function(lang)
			return {
				Type = "Rush",
				Text = Locale.TFor(lang, "⚡ %s extended by %s s!", Locale.TFor(lang, settings.Name), tostring(settings.Duration)),
			}
		end)
		return true
	end
	rush.Active = true
	rush.EndsAt = workspace:GetServerTimeNow() + settings.Duration
	scheduleRushEnd()
	Net.Event("EventUpdate"):FireAllClients(rushPayload())
	services.GameService:MarkAllDirty()
	services.GameService:NotifyAll(function(lang)
		return {
			Type = "Rush",
			Text = Locale.TFor(lang, "⚡ %s: x%s for %s s!", Locale.TFor(lang, settings.Name),
				tostring(settings.Multiplier), tostring(settings.Duration)),
		}
	end)
	return true
end

----------------------------------------------------------------------
-- Objets à cliquer (Config.Spawners)
----------------------------------------------------------------------

-- Retire les objets expirés et renvoie le nombre d'objets encore en attente pour ce type
local function cleanPending(state, kind: string): number
	local clock = os.clock()
	local count = 0
	for id, spawn in pairs(state.Pending) do
		if clock > spawn.ExpiresAt + SPAWN_GRACE then
			state.Pending[id] = nil
		elseif spawn.Kind == kind then
			count += 1
		end
	end
	return count
end

-- Fait apparaître un objet chez un joueur (ignore la Feature : utilisé aussi par /spawn).
-- Renvoie false si trop d'objets de ce type sont déjà affichés.
function EventService:Spawn(player: Player, kind: string): boolean
	local state = spawnStates[player]
	local settings = Config.Spawners[kind]
	if not state or not settings then
		return false
	end
	if cleanPending(state, kind) >= Config.MaxPendingSpawnsPerKind then
		return false
	end

	local id = HttpService:GenerateGUID(false)
	state.Pending[id] = {
		Kind = kind,
		ExpiresAt = os.clock() + settings.Lifetime,
	}
	Net.Event("Spawn"):FireClient(player, {
		Kind = kind,
		Id = id,
		X = random:NextNumber(0.08, 0.72),
		Y = random:NextNumber(0.15, 0.85),
		Lifetime = settings.Lifetime,
		Variant = random:NextInteger(1, 1000),
	})
	return true
end

-- Ancien nom (v1), gardé pour compatibilité
function EventService:SpawnGolden(player: Player)
	return self:Spawn(player, "Golden")
end

-- Oublie tous les objets en attente (détox, reset)
function EventService:ClearSpawns(player: Player)
	local state = spawnStates[player]
	if state then
		state.Pending = {}
		state.NextAt = {}
	end
end

local function randomDelay(settings): number
	return random:NextNumber(settings.MinInterval, settings.MaxInterval) / speedup
end

-- Le joueur remplit-il les conditions de ce type d'objet ?
local function isSpawnerUnlocked(data, settings): boolean
	if not Formulas.HasFeature(data, settings.Feature) then
		return false
	end
	if settings.RequiresFollow and data.LiveFollowed ~= true then
		return false -- dons du live : seulement après "Suivre"
	end
	return true
end

-- Boucle unique qui planifie les apparitions de chaque type pour chaque joueur
-- (équivaut à une boucle par joueur et par type, sans créer de threads)
local function schedulerStep()
	local clock = os.clock()
	for player, state in pairs(spawnStates) do
		local data = services.DataService:GetData(player)
		if data and services.GameService:IsReady(player) then
			for kind, settings in pairs(Config.Spawners) do
				if not isSpawnerUnlocked(data, settings) then
					state.NextAt[kind] = nil -- pas débloqué : rien ne se prépare
				elseif state.NextAt[kind] == nil then
					-- Tout juste débloqué (ou arrivée du joueur) : le premier arrive plus vite
					state.NextAt[kind] = clock + randomDelay(settings) * 0.5
				elseif clock >= state.NextAt[kind] then
					state.NextAt[kind] = clock + randomDelay(settings)
					EventService:Spawn(player, kind)
				end
			end
		end
	end
end

-- Pas de limite de fréquence ici : chaque id est à usage unique (supprimé de
-- Pending dès le premier clic), donc deux clics rapides légitimes passent
local function onSpawnClick(player: Player, id: any)
	local state = spawnStates[player]
	if not state or type(id) ~= "string" or #id > 64 then
		return
	end
	local spawn = state.Pending[id]
	if not spawn then
		return
	end
	state.Pending[id] = nil
	if os.clock() > spawn.ExpiresAt + SPAWN_GRACE then
		return -- trop tard
	end

	local data = services.DataService:GetData(player)
	local settings = Config.Spawners[spawn.Kind]
	if not data or not settings then
		return
	end
	local reward = Formulas.ScaledReward(services.GameService:GetStats(player), settings.RewardSeconds, settings.MinReward)
	if settings.Stat then
		data.Stats[settings.Stat] = (data.Stats[settings.Stat] or 0) + 1
	end
	services.GameService:AddDopamine(player, reward, true)
	services.QuestService:Progress(player, "Spawns", 1)
	services.GameService:Notify(player, {
		Type = "Bonus",
		Source = spawn.Kind,
		Amount = reward,
		SpawnId = id,
	})
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function EventService:PlayerReady(player: Player)
	spawnStates[player] = { Pending = {}, NextAt = {} }
end

function EventService:PlayerRemoving(player: Player)
	spawnStates[player] = nil
end

function EventService:Start()
	Net.Event("SpawnClick").OnServerEvent:Connect(onSpawnClick)

	-- Boucle des apparitions (par joueur et par type)
	task.spawn(function()
		while true do
			task.wait(SCHEDULER_STEP)
			local ok, err = pcall(schedulerStep)
			if not ok then
				warn("[EventService] Erreur des apparitions :", err)
			end
		end
	end)

	-- Boucle des Dopamine Rush (globaux)
	task.spawn(function()
		local settings = Config.Events.Rush
		while true do
			task.wait(random:NextNumber(settings.MinInterval, settings.MaxInterval) / speedup)
			self:StartRush()
			task.wait(settings.Duration)
		end
	end)
end

return EventService
