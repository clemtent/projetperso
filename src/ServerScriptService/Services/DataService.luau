--[[
	DataService (ModuleScript)
	Emplacement : ServerScriptService > Services > DataService

	Chargement / sauvegarde des données des joueurs avec DataStoreService
	(format "version 2", magasin Config.DataStore.Name) :
	  - pcall + plusieurs tentatives (retry) avec attente croissante ;
	  - sauvegarde à la sortie du joueur, toutes les 60 secondes (au plus),
	    après certaines actions importantes (détox, achat Robux) et à la
	    fermeture du serveur (BindToClose) ;
	  - data.LastOnline (os.time) est mis à jour à chaque sauvegarde : au
	    chargement, l'absence (en secondes) sert au gain hors-ligne
	    (GameService, voir TakeOfflineSeconds) ;
	  - si le chargement échoue, on NE sauvegarde PAS (pour ne jamais écraser
	    une vraie sauvegarde avec des données vides).
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)

local DataService = {}

-- Profils chargés : [Player] = { Data = table, CanSave = bool, Saving = bool, Releasing = bool,
--   OfflineSeconds = secondes d'absence depuis la dernière sauvegarde (0 = rien à donner) }
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
	-- ClickSound = Id de Config.ClickSounds ; Language = "Auto" | "en" | "fr"
	-- ("Auto" = langue de Roblox du joueur) ; DarkMode = mode sombre de l'interface
	Settings = { Sound = true, Music = true, Effects = true, ClickSound = "Default", Language = "Auto", DarkMode = false },
	Cosmetics = {
		Owned = {}, -- [cosmeticId] = true
		Equipped = { Hat = "", Skin = "" }, -- "" = rien d'équipé
	},
	Stock = { Shares = 0, CostBasis = 0 }, -- actions de la bourse
	Chests = { Stored = 0, Progress = 0 }, -- coffres mystère
	ScreenTime = {}, -- ["numéro du jour UTC"] = secondes jouées ce jour-là
	Themes = {
		Owned = { Classic = true }, -- [themeId] = true (achetés, gardés pour toujours)
		Equipped = "Classic",
	},
	Boost = { Multiplier = 1, EndsAt = 0 }, -- boost acheté (EndsAt = os.time() de fin)
	-- 🏠 Maison (Config.House), gardée pour toujours (même après l'océan).
	-- Items = { [itemId] = nombre possédé } ;
	-- Placed = { { I = itemId, X = 0..1, Y = 0..1, S = 0.6..1.6, Z = 0..999 }, ... }
	House = {
		Size = Config.House.Sizes[1].Id,
		Wallpaper = Config.House.Wallpapers[1].Id,
		Floor = Config.House.Floors[1].Id,
		OwnedSizes = { [Config.House.Sizes[1].Id] = true },
		OwnedWallpapers = { [Config.House.Wallpapers[1].Id] = true },
		OwnedFloors = { [Config.House.Floors[1].Id] = true },
		Items = {},
		Placed = {},
	},
	Purchases = {}, -- PurchaseId (texte) des 50 derniers achats Robux traités (anti-doublon)
	LastOnline = 0, -- os.time() de la dernière sauvegarde / sortie (0 = jamais)
	LiveFollowed = false, -- abonné au live ASMR pendant cette partie (remis à false à la détox)
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
		RobuxPurchases = 0,
		ThemesBought = 0,
		Donations = 0, -- dons du live cliqués
		Follows = 0, -- abonnements au live
		ButterCrunches = 0, -- croquées de beurre
		OfflineEarned = 0, -- Dopamine gagnée hors-ligne
		HouseItemsBought = 0, -- objets de maison achetés
		HouseComfort = 0, -- meilleur confort de maison atteint
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

-- Plafond de l'absence prise en compte (sécurité contre une date abîmée) : 1 an
local MAX_OFFLINE_SECONDS = 365 * 86400
-- Sauvegarde automatique : au plus toutes les 60 secondes
local AUTOSAVE_INTERVAL = math.min(Config.DataStore.AutoSaveInterval, 60)

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Secondes écoulées depuis `lastOnline` (0 si jamais connecté ou date invalide)
local function offlineSecondsSince(lastOnline): number
	if not isValidNumber(lastOnline) or lastOnline <= 0 then
		return 0
	end
	return math.clamp(os.time() - lastOnline, 0, MAX_OFFLINE_SECONDS)
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

	-- Absence depuis la dernière sauvegarde (gain hors-ligne donné par
	-- GameService quand le client est prêt), puis on repart de maintenant
	local offlineSeconds = offlineSecondsSince(data.LastOnline)
	data.LastOnline = os.time()

	-- Le joueur a pu partir pendant le chargement
	if not player.Parent then
		return nil
	end

	profiles[player] = {
		Data = data,
		CanSave = canSave,
		Saving = false,
		Releasing = false,
		OfflineSeconds = offlineSeconds,
	}

	if not canSave then
		local language = Locale.ForPlayer(player, data.Settings.Language)
		task.defer(function()
			services.GameService:Notify(player, {
				Type = "Error",
				Text = Locale.TFor(language, "⚠️ Saving is unavailable: your progress won't be saved."),
			})
		end)
	end

	return data
end

function DataService:GetData(player: Player)
	local profile = profiles[player]
	return profile and profile.Data
end

-- Renvoie (une seule fois) les secondes d'absence calculées au chargement
function DataService:TakeOfflineSeconds(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local seconds = profile.OfflineSeconds or 0
	profile.OfflineSeconds = 0
	return seconds
end

function DataService:GetLoadedPlayers(): { Player }
	local list = {}
	for player in pairs(profiles) do
		table.insert(list, player)
	end
	return list
end

-- Remet les données d'un joueur à zéro (commande de test /reset), SAUF les
-- réglages et la liste des achats Robux traités (anti-doublon). La table est vidée "sur place" : les autres services qui ont
-- gardé une référence vers elle restent valides.
function DataService:ResetData(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	local settings = deepCopy(data.Settings)
	local purchases = deepCopy(data.Purchases)
	for key in pairs(data) do
		data[key] = nil
	end
	for key, value in pairs(TEMPLATE) do
		data[key] = deepCopy(value)
	end
	if type(settings) == "table" then
		data.Settings = reconcile(settings, TEMPLATE.Settings)
	end
	if type(purchases) == "table" then
		data.Purchases = purchases
	end
	data.LastOnline = os.time()
	profile.OfflineSeconds = 0
	return true
end

-- true si les données de ce joueur peuvent être sauvegardées
-- (DataStore disponible et chargement réussi)
function DataService:CanSave(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.CanSave and dataStore ~= nil
end

-- Sauvegarde les données d'un joueur (bloquant).
-- `waitIfBusy` = true : si une sauvegarde est déjà en cours, on attend qu'elle
-- finisse puis on sauvegarde à nouveau (utilisé après un achat Robux : la
-- sauvegarde en cours ne contient peut-être pas l'achat).
function DataService:SaveAsync(player: Player, waitIfBusy: boolean?): boolean
	local profile = profiles[player]
	if not profile or not profile.CanSave or not dataStore then
		return false
	end
	if profile.Saving and waitIfBusy then
		local waited = 0
		while profile.Saving and waited < 30 do
			waited += task.wait(0.1)
		end
	end
	if profile.Saving then
		return false -- une sauvegarde est déjà en cours
	end

	profile.Saving = true
	local data = profile.Data
	data.LastOnline = os.time() -- dernière présence connue (gain hors-ligne)
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
	-- Déjà en cours de libération (PlayerRemoving puis BindToClose) : rien à refaire
	if profile.Releasing then
		return
	end
	profile.Releasing = true
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
			task.wait(AUTOSAVE_INTERVAL)
			for player in pairs(profiles) do
				task.spawn(function()
					self:SaveAsync(player)
				end)
			end
		end
	end)

	-- Fermeture du serveur : on sauvegarde tout le monde en parallèle
	game:BindToClose(function()
		-- On libère TOUS les profils chargés, y compris ceux des joueurs déjà
		-- sortis de la liste Players (leur sauvegarde de sortie peut être en cours)
		for player, profile in pairs(profiles) do
			if not profile.Releasing then
				task.spawn(function()
					self:ReleaseAsync(player)
				end)
			end
		end
		-- On attend aussi les sauvegardes lancées par PlayerRemoving :
		-- ReleaseAsync retire le profil de la table quand il a fini
		local start = os.clock()
		while next(profiles) ~= nil and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
