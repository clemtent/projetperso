--[[
	EventService (ModuleScript)
	Emplacement : ServerScriptService > Services > EventService

	Événements aléatoires :
	  - "Dopamine Rush" : x2 sur tous les gains pendant 30 s, pour TOUT le serveur ;
	  - Objet doré : apparaît chez un joueur, disparaît vite, donne un bonus.
	Le serveur décide quand ils arrivent et valide les clics.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local EventService = {}

local services
local random = Random.new()

-- Dans Studio, les événements arrivent plus vite pour pouvoir les tester
local speedup = RunService:IsStudio() and Config.Events.StudioSpeedup or 1

local rush = {
	Active = false,
	EndsAt = 0, -- heure serveur (workspace:GetServerTimeNow())
}

-- Objet doré actuellement affiché pour chaque joueur : [Player] = { Id, ExpiresAt }
local goldenByPlayer = {}

function EventService:Init(allServices)
	services = allServices
end

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

-- Lance un Dopamine Rush (peut aussi être appelé depuis la console pour tester)
function EventService:StartRush()
	if rush.Active then
		return
	end
	local settings = Config.Events.Rush
	rush.Active = true
	rush.EndsAt = workspace:GetServerTimeNow() + settings.Duration
	Net.Event("EventUpdate"):FireAllClients(rushPayload())
	services.GameService:MarkAllDirty()

	task.delay(settings.Duration, function()
		rush.Active = false
		Net.Event("EventUpdate"):FireAllClients(rushPayload())
		services.GameService:MarkAllDirty()
	end)
end

-- Fait apparaître un objet doré chez un joueur
function EventService:SpawnGolden(player: Player)
	local settings = Config.Events.Golden
	local golden = {
		Id = HttpService:GenerateGUID(false),
		ExpiresAt = os.clock() + settings.Lifetime,
	}
	goldenByPlayer[player] = golden
	Net.Event("GoldenSpawn"):FireClient(player, {
		Id = golden.Id,
		X = random:NextNumber(0.1, 0.6), -- évite la boutique à droite
		Y = random:NextNumber(0.2, 0.8),
		Lifetime = settings.Lifetime,
	})
end

local function onGoldenClick(player: Player, id: any)
	if not RateLimiter.Check(player, "Golden", 0.2) then
		return
	end
	local golden = goldenByPlayer[player]
	-- 0.5 s de marge pour la latence réseau
	if type(id) ~= "string" or not golden or golden.Id ~= id or os.clock() > golden.ExpiresAt + 0.5 then
		return
	end
	goldenByPlayer[player] = nil

	local data = services.DataService:GetData(player)
	if not data then
		return
	end
	local settings = Config.Events.Golden
	local reward = Formulas.ScaledReward(services.GameService:GetStats(player), settings.RewardSeconds, settings.MinReward)
	data.Stats.GoldenClicks += 1
	services.GameService:AddDopamine(player, reward, true)
	services.QuestService:Progress(player, "Golden", 1)
	services.GameService:Notify(player, {
		Type = "Bonus",
		Source = "Golden",
		Amount = reward,
		Text = "🌟 OBJET DORÉ : +" .. NumberFormatter.Format(reward) .. " !",
	})
end

function EventService:PlayerReady(player: Player)
	-- Boucle d'objets dorés propre à ce joueur
	task.spawn(function()
		local settings = Config.Events.Golden
		while player.Parent do
			task.wait(random:NextNumber(settings.MinInterval, settings.MaxInterval) / speedup)
			if player.Parent and services.GameService:IsReady(player) then
				self:SpawnGolden(player)
			end
		end
	end)
end

function EventService:PlayerRemoving(player: Player)
	goldenByPlayer[player] = nil
end

function EventService:Start()
	Net.Event("GoldenClick").OnServerEvent:Connect(onGoldenClick)

	-- Boucle des Dopamine Rush (globaux)
	task.spawn(function()
		local settings = Config.Events.Rush
		while true do
			task.wait(random:NextNumber(settings.MinInterval, settings.MaxInterval) / speedup)
			self:StartRush()
			services.GameService:NotifyAll({
				Type = "Rush",
				Text = "⚡ " .. settings.Name .. " : x" .. settings.Multiplier .. " pendant " .. settings.Duration .. " s !",
			})
			task.wait(settings.Duration)
		end
	end)
end

return EventService
