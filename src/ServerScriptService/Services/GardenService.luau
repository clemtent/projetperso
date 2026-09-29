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
	    v9.8 (GARDEN98) 🌷 jardin de la maison aménagé librement :
	      "saveLayout", { Layout = { [clé] = { X, D, R } }, Decor = { id, ... }? }
	          -> places choisies dans le mode édition du jardin (GardenEdit) ;
	             TOUT est revérifié (GardenSnapshot.CleanLayout : clés connues,
	             objets possédés, zones du niveau, couloirs des portes, nombre
	             d'objets posés) ; Decor = la déco du jardin sortie (possédée,
	             places du niveau) -> data.House.Garden ; limité à 1 / 0,5 s
	      "buyPiece", id    -> achète un objet de jardin (Config.Garden.Pieces :
	             +15 % par exemplaire possédé, Max, RequiresRebirths)
	      "expand"          -> agrandit le jardin d'un niveau (Config.Garden.Expansion)
	  - Envoyé au client par GetClientState :
	      Garden = { Plots = { { Flower, PlantedAt, ReadyAt } }, Now = os.time(),
	                 Level = n, Pieces = { [id] = n }, Layout = { ... } }
	  Données (anciennes sauvegardes : tout ce qui manque = niveau 0, rien) :
	    data.Garden = { Plots, Level, Pieces = { [id] = n }, Layout = { [clé] = { X, D, R } } }
	    (data.Garden n'est jamais remis à zéro par l'océan : seuls les
	    parterres en trop disparaissent)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local GardenSnapshot = require(ReplicatedStorage.Shared.GardenSnapshot)
local RateLimiter = require(script.Parent.RateLimiter)

local GardenService = {}

local services
local random = Random.new()
local settings = Config.Garden

local MAX_PLOTS = 24 -- garde-fou (sauvegarde abîmée, configuration extrême)
local RARE_BROADCAST_WEIGHT = 3 -- fleurs au plus aussi rares que ça : annoncées au serveur
local LAYOUT_INTERVAL = 0.5 -- (s) entre deux sauvegardes du jardin
local BUY_INTERVAL = 0.2 -- (s) entre deux achats du jardin

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

-- (v9.8) Contexte de vérification de la disposition du jardin
local function layoutContext(data): any
	local owned = Formulas.HasFeature(data, settings.Feature)
	local house = type(data.House) == "table" and data.House or {}
	local decor = {}
	if type(house.Garden) == "table" then
		for _, id in ipairs(house.Garden) do
			if type(id) == "string" then
				decor[id] = true
			end
		end
	end
	return {
		Level = GardenSnapshot.Level(data),
		Size = type(house.Size) == "string" and house.Size or nil,
		Beds = owned and plotCount(data) or math.max(1, settings.BasePlots or 3),
		Decor = decor,
		Pieces = GardenSnapshot.OwnedPieces(data),
		Windmill = GardenSnapshot.HasWindmill(data),
	}
end

-- (v9.8) Niveau, objets possédés et disposition : réparés (jamais d'erreur)
local function sanitizeLayout(data)
	local garden = data.Garden
	garden.Level = GardenSnapshot.Level(data)
	garden.Pieces = GardenSnapshot.OwnedPieces(data)
	garden.Layout = GardenSnapshot.CleanLayout(garden.Layout, layoutContext(data))
end

-- Répare data.Garden (types, fleurs retirées de la config, dates impossibles)
-- et ajuste le nombre de parterres. Les parterres ne bougent pas sans la Feature.
local function sanitize(data)
	if type(data.Garden) ~= "table" then
		data.Garden = {}
	end
	local garden = data.Garden
	if type(garden.Plots) ~= "table" then
		garden.Plots = {}
	end
	sanitizeLayout(data)
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
	local garden = data.Garden
	return {
		Garden = {
			Plots = owned and garden.Plots or {},
			Now = os.time(),
			Level = garden.Level,
			Pieces = garden.Pieces,
			Layout = garden.Layout,
		},
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

----------------------------------------------------------------------
-- v9.8 (GARDEN98) : jardin de la maison (disposition, objets, agrandissement)
----------------------------------------------------------------------

local function gardenResult(data): any
	local garden = data.Garden
	return { Level = garden.Level, Pieces = garden.Pieces, Layout = garden.Layout, Decor = (data.House and data.House.Garden) or {} }
end

-- Déco du jardin sortie demandée par le mode édition -> data.House.Garden
local function applyDecor(data, requested: any)
	local house = data.House
	if type(house) ~= "table" or type(requested) ~= "table" then
		return
	end
	local owned = type(house.OwnedGarden) == "table" and house.OwnedGarden or {}
	local looks = Config.HouseLooksById and Config.HouseLooksById.Garden or {}
	local slots = GardenSnapshot.DecorSlots(GardenSnapshot.Level(data))
	local list, seen = {}, {}
	for index, id in ipairs(requested) do
		if index > 64 or #list >= slots then
			break
		end
		if type(id) == "string" and #id <= 64 and owned[id] == true and looks[id] and not seen[id] then
			seen[id] = true
			table.insert(list, id)
		end
	end
	house.Garden = list
end

local function saveLayout(player: Player, data, argument: any)
	if type(argument) ~= "table" or type(argument.Layout) ~= "table" then
		return false, T(player, "Invalid request")
	end
	local requested = 0
	for _ in pairs(argument.Layout) do
		requested += 1
		if requested > GardenSnapshot.MAX_ENTRIES * 2 then
			return false, T(player, "Invalid request")
		end
	end
	if argument.Decor ~= nil then
		applyDecor(data, argument.Decor)
	end
	local clean = GardenSnapshot.CleanLayout(argument.Layout, layoutContext(data))
	local kept = 0
	for _ in pairs(clean) do
		kept += 1
	end
	data.Garden.Layout = clean
	services.GameService:SendState(player)
	local result = gardenResult(data)
	result.Dropped = math.max(0, requested - kept)
	return true, result
end

local function buyPiece(player: Player, data, pieceId: any)
	local piece = type(pieceId) == "string" and GardenSnapshot.PiecesById[pieceId] or nil
	if not piece then
		return false, T(player, "Invalid request")
	end
	local rebirths = isValidNumber(data.Rebirths) and data.Rebirths or 0
	local needed = tonumber(piece.RequiresRebirths) or 0
	if rebirths < needed then
		return false, T(player, "🔒 Unlocked after %d visits to the ocean", needed)
	end
	local pieces = data.Garden.Pieces
	local owned = pieces[piece.Id] or 0
	if owned >= (tonumber(piece.Max) or 10) then
		return false, T(player, "You have the maximum of this item")
	end
	local cost = GardenSnapshot.PieceCost(piece, owned)
	if not isValidNumber(data.Dopamine) or data.Dopamine < cost then
		return false, T(player, "Not enough %s", Config.Game.CurrencyName)
	end
	data.Dopamine -= cost
	pieces[piece.Id] = owned + 1
	services.GameService:SendState(player)
	local result = gardenResult(data)
	result.Piece = piece.Id
	result.Count = owned + 1
	result.Message = T(player, "%s %s is yours! (%s)", piece.Icon or "🪴", T(player, piece.Name), NumberFormatter.Format(cost))
	return true, result
end

local function expand(player: Player, data)
	local level = GardenSnapshot.Level(data)
	local info = GardenSnapshot.LevelInfo(level + 1)
	if not info then
		return false, T(player, "Your garden is already at its biggest!")
	end
	local rebirths = isValidNumber(data.Rebirths) and data.Rebirths or 0
	local needed = tonumber(info.RequiresRebirths) or 0
	if rebirths < needed then
		return false, T(player, "🔒 Unlocked after %d visits to the ocean", needed)
	end
	local cost = tonumber(info.Cost) or math.huge
	if not isValidNumber(data.Dopamine) or data.Dopamine < cost then
		return false, T(player, "Not enough %s", Config.Game.CurrencyName)
	end
	data.Dopamine -= cost
	data.Garden.Level = level + 1
	sanitizeLayout(data)
	services.GameService:SendState(player)
	local result = gardenResult(data)
	result.Message = T(player, "%s %s: your garden is bigger! (%s)", info.Icon or "🌳", T(player, info.Name), NumberFormatter.Format(cost))
	return true, result
end

local HOUSE_ACTIONS = { saveLayout = true, buyPiece = true, expand = true }

local function onGarden(player: Player, action: any, arg: any)
	if HOUSE_ACTIONS[action] then
		local interval = action == "saveLayout" and LAYOUT_INTERVAL or BUY_INTERVAL
		if not RateLimiter.Check(player, "Garden_" .. action, interval) then
			return false, T(player, "Slow down!")
		end
		local data = services.DataService:GetData(player)
		if not data or not services.GameService:IsReady(player) then
			return false, T(player, "Loading...")
		end
		sanitize(data)
		if action == "saveLayout" then
			return saveLayout(player, data, arg)
		elseif action == "buyPiece" then
			return buyPiece(player, data, arg)
		end
		return expand(player, data)
	end
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
	Net.Function("Garden").OnServerInvoke = function(player: Player, action: any, arg: any)
		local ok, success, result = pcall(onGarden, player, action, arg)
		if not ok then
			warn("[GardenService] Erreur pour " .. player.Name .. " :", success)
			return false, T(player, "Invalid request")
		end
		return success, result
	end
end

return GardenService
