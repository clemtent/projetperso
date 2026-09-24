--[[
	DataService (ModuleScript)
	Emplacement : ServerScriptService > Services > DataService

	Chargement / sauvegarde des données des joueurs avec DataStoreService
	(format "version 2", magasin Config.DataStore.Name) :
	  - pcall + plusieurs tentatives (retry) avec attente croissante ;
	  - sauvegarde à la sortie du joueur, toutes les X secondes, et à la
	    fermeture du serveur (BindToClose) ;
	  - si le chargement échoue, on NE sauvegarde PAS (pour ne jamais écraser
	    une vraie sauvegarde avec des données vides).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

-- Profils chargés : [Player] = { Data = table, CanSave = bool, Saving = bool }
local profiles = {}

-- Données d'un nouveau joueur (version 2). Toute nouvelle clé ajoutée ici
-- sera automatiquement ajoutée aux anciennes sauvegardes (voir reconcile).
local TEMPLATE = {
	Version = 2,
	Dopamine = 0,
	Rebirths = 0,
	Upgrades = {}, -- [upgradeId] = niveau
	Achievements = {}, -- [achievementId] = true
	Quests = {}, -- liste des quêtes actives
	Daily = { LastDay = 0, Streak = 0 },
	Settings = { Sound = true, Music = true, Effects = true },
	Cosmetics = {
		Owned = {}, -- [cosmeticId] = true
		Equipped = { Hat = "", Skin = "" }, -- "" = rien d'équipé
	},
	Stock = { Shares = 0, CostBasis = 0 }, -- actions de la bourse
	Chests = { Stored = 0, Progress = 0 }, -- coffres mystère
	ScreenTime = {}, -- ["numéro du jour UTC"] = secondes jouées ce jour-là
	Stats = {
		TotalClicks = 0,
		LifetimeDopamine = 0, -- Dopamine gagnée depuis toujours (classement)
		UpgradesBought = 0,
		CombosMaxed = 0,
		DVDClicks = 0,
		DVDCorners = 0,
		Bounces = 0,
		GoldenClicks = 0,
		LightningClicks = 0,
		NotifsOpened = 0,
		EmailsRead = 0,
		BubblesPopped = 0,
		Spins = 0,
		HeadlinesClicked = 0,
		PressCrushes = 0,
		SlotSpins = 0,
		SlotWins = 0,
		StockTrades = 0,
		ChestsOpened = 0,
		CosmeticsBought = 0,
		QuestsCompleted = 0,
		DailyClaims = 0,
		PlaySeconds = 0,
	},
}

local services -- rempli par Init

local dataStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStore.Name)
	end)
	if ok then
		dataStore = result
	else
		warn("[DataService] DataStore indisponible (place non publiée ?) :", result)
	end
end

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Ajoute les clés manquantes (nouvelle version du jeu) sans toucher aux
-- existantes. Une valeur du mauvais type (sauvegarde corrompue) est remplacée.
local function reconcile(data, template)
	for key, value in pairs(template) do
		local current = data[key]
		if current == nil or type(current) ~= type(value) or (type(value) == "number" and current ~= current) then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and next(value) ~= nil then
			reconcile(current, value)
		end
	end
	return data
end

-- Erreurs pour lesquelles réessayer ne sert à rien (ex. Studio sans accès aux API)
local function isFatalError(message: string): boolean
	return string.find(message, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(message, "publish", 1, true) ~= nil
		or string.find(message, "403", 1, true) ~= nil
end

-- Exécute `callback` avec pcall et réessaie en cas d'échec
local function retry(description: string, callback: () -> any): (boolean, any)
	local lastError
	for attempt = 1, Config.DataStore.MaxRetries do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		warn(string.format("[DataService] %s : échec (tentative %d) : %s", description, attempt, tostring(result)))
		if isFatalError(tostring(result)) then
			warn("[DataService] Active 'Enable Studio Access to API Services' (Game Settings > Security) et publie le jeu.")
			break
		end
		if attempt < Config.DataStore.MaxRetries then
			task.wait(2 ^ attempt) -- 2s, 4s, 8s...
		end
	end
	return false, lastError
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function DataService:Init(allServices)
	services = allServices
end

-- Charge les données d'un joueur (bloquant). Renvoie la table de données.
function DataService:LoadAsync(player: Player)
	local canSave = dataStore ~= nil
	local data

	if dataStore then
		local store = dataStore :: DataStore
		local ok, result = retry("Chargement de " .. player.Name, function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			data = (type(result) == "table") and result or nil
		else
			-- Échec total : on joue avec des données vides mais sans sauvegarder
			canSave = false
		end
	end

	data = reconcile(data or deepCopy(TEMPLATE), TEMPLATE)
	data.Version = TEMPLATE.Version

	-- Le joueur a pu partir pendant le chargement
	if not player.Parent then
		return nil
	end

	profiles[player] = { Data = data, CanSave = canSave, Saving = false }

	if not canSave then
		task.defer(function()
			services.GameService:Notify(player, {
				Type = "Error",
				Text = "⚠️ Sauvegarde indisponible : ta progression ne sera pas enregistrée.",
			})
		end)
	end

	return data
end

function DataService:GetData(player: Player)
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService:GetLoadedPlayers(): { Player }
	local list = {}
	for player in pairs(profiles) do
		table.insert(list, player)
	end
	return list
end

-- Remet les données d'un joueur à zéro (commande de test /reset), SAUF les
-- réglages. La table est vidée "sur place" : les autres services qui ont
-- gardé une référence vers elle restent valides.
function DataService:ResetData(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	local settings = deepCopy(data.Settings)
	for key in pairs(data) do
		data[key] = nil
	end
	for key, value in pairs(TEMPLATE) do
		data[key] = deepCopy(value)
	end
	if type(settings) == "table" then
		data.Settings = reconcile(settings, TEMPLATE.Settings)
	end
	return true
end

-- Sauvegarde les données d'un joueur (bloquant)
function DataService:SaveAsync(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.CanSave or not dataStore then
		return false
	end
	if profile.Saving then
		return false -- une sauvegarde est déjà en cours
	end

	profile.Saving = true
	local data = profile.Data
	local store = dataStore :: DataStore
	local ok = retry("Sauvegarde de " .. player.Name, function()
		store:UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
	profile.Saving = false
	return ok
end

-- Sauvegarde puis oublie le joueur (à la sortie)
function DataService:ReleaseAsync(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	-- Si une sauvegarde automatique est en cours, on attend qu'elle finisse
	local waited = 0
	while profile.Saving and waited < 10 do
		waited += task.wait(0.1)
	end
	self:SaveAsync(player)
	profiles[player] = nil
end

function DataService:Start()
	-- Sauvegarde périodique
	task.spawn(function()
		while true do
			task.wait(Config.DataStore.AutoSaveInterval)
			for player in pairs(profiles) do
				task.spawn(function()
					self:SaveAsync(player)
				end)
			end
		end
	end)

	-- Fermeture du serveur : on sauvegarde tout le monde en parallèle
	game:BindToClose(function()
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			if profiles[player] then
				pending += 1
				task.spawn(function()
					self:ReleaseAsync(player)
					pending -= 1
				end)
			end
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
