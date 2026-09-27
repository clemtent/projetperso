--[[
	GardenSnapshot (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > GardenSnapshot

	🌻 Résumé du Jardin de Dopamine d'un joueur, pour l'instantané de la
	ville (WorldService -> clients -> GardenBuilder). Fonction PURE :
	  - accepte les données du serveur (data) OU l'état du client
	    (ClientState.Data : mêmes champs Upgrades / Garden) ;
	  - ne lève jamais d'erreur (sauvegarde abîmée : valeurs ignorées) ;
	  - sûr pour le JSON et les RemoteEvents : clés texte, tableaux denses,
	    nombres entiers finis, aucune Instance / aucun Color3 ;
	  - PETIT (≤ 24 parterres de 3 champs) et STABLE : pas d'heure "Now"
	    dedans (sinon la signature JSON de WorldService changerait à chaque
	    vérification) ; le client prend l'heure du serveur avec
	    workspace:GetServerTimeNow().

	GardenSnapshot.From(data) -> {
		Unlocked = bool,         -- Feature "Garden" possédée
		Count = n,               -- parterres possédés (BasePlots + "Flower Beds")
		Max = n,                 -- parterres possibles au maximum
		Windmill = bool,         -- moulin (Feature "Pinwheel") : déco du jardin
		Plots = { { Flower = "Daisy", PlantedAt = t, ReadyAt = t }, ... },
	}
	GardenSnapshot.Sanitize(snapshot) -> même forme, validée (côté client :
	un instantané venu du réseau n'est jamais cru sur parole).
	GardenSnapshot.Progress(plot, now) -> (progress 0..1, prêt ?, secondes restantes)
	GardenSnapshot.Stage(plot, now) -> "Seed" | "Sprout" | "Bud" | "Bloom" | "Ready"
]]

local Config = require(script.Parent.Config)

local GardenSnapshot = {}

GardenSnapshot.MAX_PLOTS = 24 -- même garde-fou que GardenService
GardenSnapshot.STAGES = { "Seed", "Sprout", "Bud", "Bloom", "Ready" }

local settings = Config.Garden or {}
local flowersById: { [string]: any } = {}
for _, flower in ipairs(settings.Flowers or {}) do
	flowersById[flower.Id] = flower
end
GardenSnapshot.FlowersById = flowersById

local function finite(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

-- Niveau d'une amélioration (données éventuellement incomplètes)
local function levelOf(data: any, upgradeId: string?): number
	if not upgradeId or type(data) ~= "table" or type(data.Upgrades) ~= "table" then
		return 0
	end
	return math.max(0, math.floor(finite(data.Upgrades[upgradeId]) or 0))
end

-- Amélioration qui porte une Feature (Config.FeatureToUpgrade, sinon on cherche)
local function upgradeFor(feature: string): string?
	local map = Config.FeatureToUpgrade
	if type(map) == "table" and type(map[feature]) == "string" then
		return map[feature]
	end
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		if upgrade.Feature == feature then
			return upgrade.Id
		end
	end
	return nil
end

-- Nombre maximum de parterres (tous les niveaux de "Flower Beds" achetés)
function GardenSnapshot.MaxPlots(): number
	local count = settings.BasePlots or 3
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		if upgrade.Feature == "GardenPlots" then
			count += math.max(0, math.floor(finite(upgrade.MaxLevel) or 0))
		end
	end
	return math.clamp(count, 1, GardenSnapshot.MAX_PLOTS)
end

-- Nombre de parterres possédés (même règle que Formulas.GetGardenPlotCount)
function GardenSnapshot.PlotCount(data: any): number
	local count = settings.BasePlots or 3
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		if upgrade.Feature == "GardenPlots" then
			count += levelOf(data, upgrade.Id)
		end
	end
	return math.clamp(math.floor(count), 1, GardenSnapshot.MAX_PLOTS)
end

-- Un parterre valide (copie propre) ou nil (parterre vide / abîmé)
local function cleanPlot(plot: any): { Flower: string, PlantedAt: number, ReadyAt: number }?
	if type(plot) ~= "table" or type(plot.Flower) ~= "string" or not flowersById[plot.Flower] then
		return nil
	end
	local plantedAt, readyAt = finite(plot.PlantedAt), finite(plot.ReadyAt)
	if not plantedAt or not readyAt then
		return nil
	end
	plantedAt, readyAt = math.floor(plantedAt), math.floor(readyAt)
	if readyAt < plantedAt then
		readyAt = plantedAt
	end
	return { Flower = plot.Flower, PlantedAt = plantedAt, ReadyAt = readyAt }
end

local function emptyPlot(): any
	-- (JSON : un tableau dense ne peut pas contenir nil -> "vide" = Flower "")
	return { Flower = "", PlantedAt = 0, ReadyAt = 0 }
end

function GardenSnapshot.From(data: any): { [string]: any }
	local count = GardenSnapshot.PlotCount(data)
	local unlocked = levelOf(data, upgradeFor(settings.Feature or "Garden")) > 0
	local plots = {}
	local garden = type(data) == "table" and data.Garden
	local source = type(garden) == "table" and type(garden.Plots) == "table" and garden.Plots or nil
	if unlocked then
		for index = 1, count do
			plots[index] = (source and cleanPlot(source[index])) or emptyPlot()
		end
	end
	return {
		Unlocked = unlocked,
		Count = count,
		Max = math.max(count, GardenSnapshot.MaxPlots()),
		Windmill = levelOf(data, upgradeFor("Pinwheel")) > 0,
		Plots = plots,
	}
end

-- Instantané reçu du réseau -> forme garantie (nil / n'importe quoi accepté)
function GardenSnapshot.Sanitize(snapshot: any): { [string]: any }
	if type(snapshot) ~= "table" then
		return { Unlocked = false, Count = settings.BasePlots or 3, Max = GardenSnapshot.MaxPlots(), Windmill = false, Plots = {} }
	end
	local count = math.clamp(math.floor(finite(snapshot.Count) or (settings.BasePlots or 3)), 1, GardenSnapshot.MAX_PLOTS)
	local maxPlots = math.clamp(math.floor(finite(snapshot.Max) or count), count, GardenSnapshot.MAX_PLOTS)
	local unlocked = snapshot.Unlocked == true
	local plots = {}
	if unlocked then
		local source = type(snapshot.Plots) == "table" and snapshot.Plots or {}
		for index = 1, count do
			plots[index] = cleanPlot(source[index]) or emptyPlot()
		end
	end
	return { Unlocked = unlocked, Count = count, Max = maxPlots, Windmill = snapshot.Windmill == true, Plots = plots }
end

-- Avancement d'un parterre à l'heure `now` (heure du serveur)
function GardenSnapshot.Progress(plot: any, now: number): (number, boolean, number)
	if type(plot) ~= "table" or not flowersById[plot.Flower] then
		return 0, false, 0
	end
	local plantedAt = finite(plot.PlantedAt) or now
	local readyAt = finite(plot.ReadyAt) or now
	local total = math.max(1, readyAt - plantedAt)
	local remaining = math.max(0, readyAt - now)
	local ready = now >= readyAt
	return ready and 1 or math.clamp(1 - remaining / total, 0, 1), ready, remaining
end

-- Stade visible : graine -> pousse -> bouton -> fleur -> prête (scintille)
function GardenSnapshot.Stage(plot: any, now: number): string
	if type(plot) ~= "table" or not flowersById[plot.Flower] then
		return "Empty"
	end
	local progress, ready = GardenSnapshot.Progress(plot, now)
	if ready then
		return "Ready"
	elseif progress < 0.12 then
		return "Seed"
	elseif progress < 0.45 then
		return "Sprout"
	elseif progress < 0.8 then
		return "Bud"
	end
	return "Bloom"
end

return GardenSnapshot
