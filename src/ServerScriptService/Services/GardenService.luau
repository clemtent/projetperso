--[[
	GardenService (ModuleScript)
	Emplacement : ServerScriptService > Services > GardenService

	🌻 Jardin de Dopamine (Config.Garden, Feature "Garden" ; remplace la bourse).
	  - Parterres : Config.Garden.BasePlots + niveau de l'amélioration
	    "Flower Beds" (Feature "GardenPlots") : Formulas.GetGardenPlotCount.
	  - Chaque parterre fait pousser une fleur tirée au hasard (Weight) ;
	    elle est prête GrowSeconds après avoir été plantée. Les dates sont
	    celles du SERVEUR (os.time) et sont gardées dans data.Garden.Plots :
	    le jardin pousse même quand on n'est pas là.
	  - RemoteFunction "Garden" :
	      "harvest", index  -> cueille UNE fleur (seulement si elle est prête)
	      "harvestAll"      -> cueille toutes les fleurs prêtes
	    Gain = RewardSeconds de production (Formulas.ScaledReward, au moins
	    MinReward), puis un nouveau bulbe est planté automatiquement.
	  - Envoyé au client par GetClientState :
	      Garden = { Plots = { { Flower, PlantedAt, ReadyAt } }, Now = os.time() }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local GardenService = {}

local services
local random = Random.new()
local settings = Config.Garden

local MAX_PLOTS = 24 -- garde-fou (sauvegarde abîmée, configuration extrême)
local RARE_BROADCAST_WEIGHT = 3 -- fleurs au plus aussi rares que ça : annoncées au serveur

local flowersById = {}
for _, flower in ipairs(settings.Flowers) do
	flowersById[flower.Id] = flower
end

function GardenService:Init(allServices)
	services = allServices
end

local function isValidNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Tire une fleur au hasard selon son poids
local function pickFlower()
	local total = 0
	for _, flower in ipairs(settings.Flowers) do
		total += flower.Weight
	end
	local roll = random:NextNumber(0, total)
	for _, flower in ipairs(settings.Flowers) do
		roll -= flower.Weight
		if roll <= 0 then
			return flower
		end
	end
	return settings.Flowers[1]
end

local function plant(now: number)
	local flower = pickFlower()
	return { Flower = flower.Id, PlantedAt = now, ReadyAt = now + flower.GrowSeconds }
end

-- Nombre de parterres du joueur
local function plotCount(data): number
	return math.clamp(math.floor(Formulas.GetGardenPlotCount(data)), 1, MAX_PLOTS)
end

-- Répare data.Garden (types, fleurs retirées de la config, dates impossibles)
-- et ajuste le nombre de parterres. Ne fait rien sans la Feature.
local function sanitize(data)
	if type(data.Garden) ~= "table" then
		data.Garden = {}
	end
	local garden = data.Garden
	if type(garden.Plots) ~= "table" then
		garden.Plots = {}
	end
	if not Formulas.HasFeature(data, settings.Feature) then
		return
	end
	local now = os.time()
	local count = plotCount(data)
	local plots = garden.Plots
	-- Appelé à chaque état envoyé : on ne recrée un parterre que s'il est abîmé
	for index = 1, count do
		local plot = plots[index]
		local flower = type(plot) == "table" and flowersById[plot.Flower]
		if not flower or not isValidNumber(plot.PlantedAt) then
			plots[index] = plant(now)
		elseif plot.PlantedAt > now or plot.PlantedAt ~= math.floor(plot.PlantedAt) or plot.ReadyAt ~= plot.PlantedAt + flower.GrowSeconds then
			-- Date dans le futur (horloge d'un autre serveur) ou incohérente : recalculée
			local plantedAt = math.min(math.floor(plot.PlantedAt), now)
			plots[index] = { Flower = flower.Id, PlantedAt = plantedAt, ReadyAt = plantedAt + flower.GrowSeconds }
		end
	end
	-- Parterres en trop (après l'océan, "Flower Beds" repart de zéro) ou clés parasites
	for key in pairs(plots) do
		if type(key) ~= "number" or key < 1 or key > count or key ~= math.floor(key) then
			plots[key] = nil
		end
	end
end

-- Champs ajoutés à l'état envoyé au client (voir GameService:BuildState)
function GardenService:GetClientState(_player: Player, data)
	sanitize(data)
	-- (la table est copiée par le RemoteEvent : on peut l'envoyer telle quelle)
	local owned = Formulas.HasFeature(data, settings.Feature)
	return {
		Garden = { Plots = owned and data.Garden.Plots or {}, Now = os.time() },
	}
end

-- Texte dans la langue du joueur
local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

local function formatWait(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Cueille la fleur du parterre `index` (déjà vérifiée prête). Renvoie le gain.
local function harvestPlot(player: Player, data, index: number, stats, now: number)
	local plot = data.Garden.Plots[index]
	local flower = flowersById[plot.Flower]
	local minimum = (settings.MinReward or 0) * math.max(1, flower.RewardSeconds / 10)
	local amount = Formulas.ScaledReward(stats, flower.RewardSeconds, minimum)
	data.Garden.Plots[index] = plant(now)
	data.Stats.GardenHarvests = (tonumber(data.Stats.GardenHarvests) or 0) + 1
	services.GameService:AddDopamine(player, amount, true)
	return flower, amount
end

local function announceRare(player: Player, flower, amount: number)
	if flower.Weight > RARE_BROADCAST_WEIGHT then
		return
	end
	local displayName, formatted = player.DisplayName, NumberFormatter.Format(amount)
	services.GameService:NotifyAll(function(lang)
		return {
			Type = "Info",
			Text = Locale.TFor(lang, "🌸 %s picked a %s in their garden (+%s)!", displayName, Locale.TFor(lang, flower.Name), formatted),
		}
	end, player)
end

local function onGarden(player: Player, action: any, arg: any)
	if action ~= "harvest" and action ~= "harvestAll" then
		return false, T(player, "Invalid request")
	end
	local interval = action == "harvestAll" and 1 or math.max(0.05, (settings.HarvestCooldown or 0.3) - 0.1)
	if not RateLimiter.Check(player, "Garden_" .. action, interval) then
		return false, T(player, "Slow down!")
	end
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, T(player, "Loading...")
	end
	if not Formulas.HasFeature(data, settings.Feature) then
		return false, T(player, "The garden isn't unlocked yet")
	end
	sanitize(data)

	local now = os.time()
	local plots = data.Garden.Plots
	local stats = services.GameService:GetStats(player)

	if action == "harvest" then
		local index = tonumber(arg)
		if not index or index ~= math.floor(index) or index < 1 or index > #plots then
			return false, T(player, "Invalid request")
		end
		local plot = plots[index]
		if now < plot.ReadyAt then
			return false, T(player, "Still growing... ready in %s", formatWait(plot.ReadyAt - now))
		end
		local flower, amount = harvestPlot(player, data, index, stats, now)
		services.QuestService:Progress(player, "Harvest", 1)
		services.GameService:SendState(player)
		announceRare(player, flower, amount)
		return true, {
			Plot = index,
			Flower = flower.Id,
			Reward = amount,
			Harvested = { { Plot = index, Flower = flower.Id, Reward = amount } },
			Plots = data.Garden.Plots,
			Now = now,
		}
	end

	-- "harvestAll"
	local harvested = {}
	local total = 0
	for index, plot in ipairs(plots) do
		if now >= plot.ReadyAt then
			local flower, amount = harvestPlot(player, data, index, stats, now)
			total += amount
			table.insert(harvested, { Plot = index, Flower = flower.Id, Reward = amount })
			announceRare(player, flower, amount)
		end
	end
	if #harvested == 0 then
		return false, T(player, "Nothing is ready yet 🌱")
	end
	services.QuestService:Progress(player, "Harvest", #harvested)
	services.GameService:SendState(player)
	return true, {
		Reward = total,
		Harvested = harvested,
		Plots = data.Garden.Plots,
		Now = now,
	}
end

function GardenService:PlayerReady(_player: Player, data)
	sanitize(data)
end

function GardenService:Start()
	Net.Function("Garden").OnServerInvoke = onGarden
end

return GardenService
