--[[
	LeaderboardService (ModuleScript)
	Emplacement : ServerScriptService > Services > LeaderboardService

	Classement disponible pour tout le monde dès le début (pas d'amélioration) :
	  - "Global" : top de tous les serveurs sur la Dopamine totale gagnée,
	    avec un OrderedDataStore (Config.Leaderboard.StoreName) ;
	  - "GlobalRebirths" : top de tous les serveurs sur le nombre de
	    renaissances (visites à l'océan), second OrderedDataStore
	    (Config.Leaderboard.RebirthStoreName) ;
	  - "Server" : classement EN DIRECT des joueurs de ce serveur (Dopamine
	    actuelle), envoyé à tout le monde toutes les 2 secondes.
	Les deux tops mondiaux sont écrits puis relus toutes les
	Config.Leaderboard.UpdateInterval secondes (et au départ d'un joueur).

	Événement LeaderboardUpdate :
	  {
	    Global         = { { Rank, UserId, Name, Value, Rebirths? } }, -- Value = Dopamine gagnée
	    GlobalRebirths = { { Rank, UserId, Name, Value, Dopamine? } }, -- Value = renaissances
	    Server         = { { Rank, UserId, Name, Dopamine, Lifetime, Rebirths } }, -- Dopamine décroissante
	  }
	Les champs "croisés" (Rebirths d'un top Dopamine, Dopamine d'un top
	renaissances) sont remplis quand on les connaît : joueur présent, présent
	dans l'autre top, ou lu dans l'autre store (avec cache et budget).

	Astuce : un OrderedDataStore n'accepte que des entiers (max ~9.2e18),
	alors que la Dopamine peut dépasser 1e30. On stocke donc
	log10(valeur) * 1 000 000 (un entier), puis on refait l'inverse à la lecture.
	L'ordre du classement reste exactement le même. Les renaissances, elles,
	sont stockées telles quelles (entier).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local LeaderboardService = {}

local services
local dopamineStore: OrderedDataStore? = nil
local rebirthStore: OrderedDataStore? = nil
local cachedTop = {} -- dernier top mondial Dopamine connu
local cachedRebirthTop = {} -- dernier top mondial renaissances connu
local nameCache = {} -- [userId] = nom
local lastSubmitted = {} -- [userId] = { Dopamine = encodé, Rebirths = entier } (évite les écritures inutiles)
local crossCache = {} -- [clé] = { Value = number?, Time = os.clock() } (valeurs lues dans l'autre store)
local lastWarn = {} -- [clé] = os.clock() du dernier avertissement

local SERVER_RANKING_INTERVAL = 2 -- secondes entre deux envois du classement du serveur
local WARN_COOLDOWN = 300 -- un même avertissement au plus toutes les 5 minutes
local MIN_GET_BUDGET = 20 -- on garde de la marge de lecture pour les sauvegardes des joueurs
local MAX_INTEGER = 2 ^ 53 -- au-delà, un entier n'est plus exact

-- Avertissement limité (évite de remplir la console dans Studio sans accès aux API)
local function warnThrottled(key: string, ...)
	local now = os.clock()
	if lastWarn[key] and now - lastWarn[key] < WARN_COOLDOWN then
		return
	end
	lastWarn[key] = now
	warn("[LeaderboardService]", ...)
end

local function openStore(name: any): OrderedDataStore?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		return result
	end
	warn("[LeaderboardService] Classement " .. name .. " indisponible :", result)
	return nil
end

dopamineStore = openStore(Config.Leaderboard.StoreName)
rebirthStore = openStore(Config.Leaderboard.RebirthStoreName)

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeNumber(value): number
	return isValidNumber(value) and value or 0
end

-- Dopamine -> entier du store (log10)
local function encode(value: number): number
	return math.floor(math.log10(math.max(0, safeNumber(value)) + 1) * 1e6)
end

-- Entier du store -> Dopamine
local function decode(stored: any): number
	local number = tonumber(stored)
	if not number or not isValidNumber(number) then
		return 0
	end
	local value = 10 ^ (number / 1e6) - 1
	return isValidNumber(value) and math.max(0, value) or 0
end

-- Renaissances -> entier du store (tel quel, borné)
local function encodeRebirths(value: any): number
	return math.floor(math.clamp(safeNumber(value), 0, MAX_INTEGER))
end

local function getName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return "Player " .. userId -- nom de secours (envoyé à tous : laissé en anglais)
end

-- Valeurs à envoyer pour un joueur (nil si ses données ne sont pas chargées)
local function readScores(player: Player): (number?, number?)
	local data = services and services.DataService:GetData(player)
	if type(data) ~= "table" then
		return nil, nil
	end
	local stats = type(data.Stats) == "table" and data.Stats or {}
	return encode(stats.LifetimeDopamine), encodeRebirths(data.Rebirths)
end

function LeaderboardService:Init(allServices)
	services = allServices
end

----------------------------------------------------------------------
-- Classement du serveur (en direct)
----------------------------------------------------------------------

local function buildServerRanking()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local data = services.DataService:GetData(player)
		if type(data) == "table" then
			local stats = type(data.Stats) == "table" and data.Stats or {}
			table.insert(list, {
				UserId = player.UserId,
				Name = player.DisplayName,
				Dopamine = safeNumber(data.Dopamine),
				Lifetime = safeNumber(stats.LifetimeDopamine),
				Rebirths = safeNumber(data.Rebirths),
			})
		end
	end
	table.sort(list, function(a, b)
		if a.Dopamine ~= b.Dopamine then
			return a.Dopamine > b.Dopamine
		end
		if a.Lifetime ~= b.Lifetime then
			return a.Lifetime > b.Lifetime
		end
		return a.UserId < b.UserId
	end)
	for rank, entry in ipairs(list) do
		entry.Rank = rank
	end
	return list
end

-- Contenu de LeaderboardUpdate
local function buildPayload()
	return {
		Global = cachedTop,
		GlobalRebirths = cachedRebirthTop,
		Server = buildServerRanking(),
	}
end

function LeaderboardService:SendTo(player: Player)
	Net.Event("LeaderboardUpdate"):FireClient(player, buildPayload())
end

-- Envoie le classement (tops mondiaux en cache + serveur en direct) à tout le monde
function LeaderboardService:Broadcast()
	if #Players:GetPlayers() == 0 then
		return
	end
	Net.Event("LeaderboardUpdate"):FireAllClients(buildPayload())
end

----------------------------------------------------------------------
-- Classements mondiaux (OrderedDataStore)
----------------------------------------------------------------------

-- Écrit une valeur dans un store (pcall) ; vrai si réussi
local function writeScore(store: OrderedDataStore?, key: string, value: number, label: string): boolean
	if not store then
		return false
	end
	local target = store :: OrderedDataStore
	local ok, err = pcall(function()
		target:SetAsync(key, value)
	end)
	if not ok then
		warnThrottled("write" .. label, "Échec d'envoi du score (" .. label .. ") :", err)
	end
	return ok
end

-- Écrit les scores déjà lus (Dopamine encodée, renaissances) d'un joueur
local function submitScores(userId: number, dopamine: number, rebirths: number)
	local key = "P_" .. userId
	local previous = lastSubmitted[userId] or {}
	local submitted = { Dopamine = previous.Dopamine, Rebirths = previous.Rebirths }
	lastSubmitted[userId] = submitted
	if dopamine > 0 and previous.Dopamine ~= dopamine then
		if writeScore(dopamineStore, key, dopamine, "Dopamine") then
			submitted.Dopamine = dopamine
		end
	end
	-- Pas de renaissance : inutile d'encombrer le top avec des zéros
	-- (sauf si un score a déjà été écrit, pour le corriger)
	if (rebirths > 0 or previous.Rebirths ~= nil) and previous.Rebirths ~= rebirths then
		if writeScore(rebirthStore, key, rebirths, "Rebirths") then
			submitted.Rebirths = rebirths
		end
	end
end

-- Écrit les scores d'un joueur dans les deux classements
function LeaderboardService:SubmitAsync(player: Player)
	local dopamine, rebirths = readScores(player)
	if dopamine == nil or rebirths == nil then
		return
	end
	submitScores(player.UserId, dopamine, rebirths)
end

-- Lit un top (pcall) : liste { { UserId, Stored } } ou nil si échec
local function readTop(store: OrderedDataStore?, label: string): { { UserId: number, Stored: number } }?
	if not store then
		return nil
	end
	local target = store :: OrderedDataStore
	local ok, result = pcall(function()
		local pages = target:GetSortedAsync(false, Config.Leaderboard.Size)
		return pages:GetCurrentPage()
	end)
	if not ok or type(result) ~= "table" then
		warnThrottled("read" .. label, "Échec de lecture du classement (" .. label .. ") :", result)
		return nil
	end
	local list = {}
	for _, entry in ipairs(result) do
		local key = type(entry) == "table" and entry.key
		local stored = type(entry) == "table" and tonumber(entry.value)
		local userId = type(key) == "string" and tonumber(string.sub(key, 3)) or nil
		if userId and stored and stored > 0 then
			table.insert(list, { UserId = userId, Stored = stored })
		end
	end
	return list
end

-- Valeur d'un joueur dans l'autre store (cache + budget de lecture).
-- Renvoie (valeur brute ou nil, connue) : "connue" = lecture réussie
-- (valeur nil = aucun score écrit), faux = impossible de savoir pour l'instant.
local function lookupStored(store: OrderedDataStore?, label: string, userId: number): (number?, boolean)
	if not store then
		return nil, false
	end
	local cacheKey = label .. "_" .. userId
	local cached = crossCache[cacheKey]
	local cacheTime = tonumber(Config.Leaderboard.CrossLookupCacheTime) or 300
	if cached and os.clock() - cached.Time < cacheTime then
		return cached.Value, true
	end
	local budgetOk, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	if not budgetOk or type(budget) ~= "number" or budget < MIN_GET_BUDGET then
		if cached then
			return cached.Value, true -- valeur un peu ancienne, mieux que rien
		end
		return nil, false
	end
	local target = store :: OrderedDataStore
	local ok, value = pcall(function()
		return target:GetAsync("P_" .. userId)
	end)
	if not ok then
		warnThrottled("lookup" .. label, "Échec de lecture d'un score (" .. label .. ") :", value)
		if cached then
			return cached.Value, true
		end
		return nil, false
	end
	local number = tonumber(value)
	crossCache[cacheKey] = { Value = number, Time = os.clock() }
	return number, true
end

-- Lit les deux tops, complète les valeurs croisées, puis envoie à tout le monde
function LeaderboardService:RefreshAsync()
	local dopamineTop = readTop(dopamineStore, "Dopamine")
	local rebirthTop = readTop(rebirthStore, "Rebirths")

	-- Valeurs connues sans requête : joueurs présents et entrées de l'autre top
	local knownDopamine = {} -- [userId] = Dopamine gagnée (décodée)
	local knownRebirths = {} -- [userId] = renaissances
	for _, player in ipairs(Players:GetPlayers()) do
		local data = services.DataService:GetData(player)
		if type(data) == "table" then
			local stats = type(data.Stats) == "table" and data.Stats or {}
			knownDopamine[player.UserId] = safeNumber(stats.LifetimeDopamine)
			knownRebirths[player.UserId] = encodeRebirths(data.Rebirths)
		end
	end
	for _, entry in ipairs(dopamineTop or {}) do
		if knownDopamine[entry.UserId] == nil then
			knownDopamine[entry.UserId] = decode(entry.Stored)
		end
	end
	for _, entry in ipairs(rebirthTop or {}) do
		if knownRebirths[entry.UserId] == nil then
			knownRebirths[entry.UserId] = entry.Stored
		end
	end

	if dopamineTop then
		local top = {}
		for rank, entry in ipairs(dopamineTop) do
			local rebirths = knownRebirths[entry.UserId]
			if rebirths == nil then
				-- Absent du top renaissances : on lit son score (0 si jamais écrit)
				local stored, known = lookupStored(rebirthStore, "Rebirths", entry.UserId)
				if known then
					rebirths = stored or 0
				end
			end
			table.insert(top, {
				Rank = rank,
				UserId = entry.UserId,
				Name = getName(entry.UserId),
				Value = decode(entry.Stored),
				Rebirths = rebirths,
			})
		end
		cachedTop = top
	end

	if rebirthTop then
		local top = {}
		for rank, entry in ipairs(rebirthTop) do
			local dopamine = knownDopamine[entry.UserId]
			if dopamine == nil then
				local stored, known = lookupStored(dopamineStore, "Dopamine", entry.UserId)
				if known then
					dopamine = stored and decode(stored) or 0
				end
			end
			table.insert(top, {
				Rank = rank,
				UserId = entry.UserId,
				Name = getName(entry.UserId),
				Value = entry.Stored,
				Dopamine = dopamine,
			})
		end
		cachedRebirthTop = top
	end

	self:Broadcast()
end

function LeaderboardService:PlayerRemoving(player: Player)
	-- Scores lus tout de suite (les données sont libérées juste après)
	local userId = player.UserId
	local dopamine, rebirths = readScores(player)
	if dopamine == nil or rebirths == nil then
		lastSubmitted[userId] = nil
		return
	end
	task.spawn(function()
		submitScores(userId, dopamine, rebirths)
		lastSubmitted[userId] = nil
	end)
end

function LeaderboardService:Start()
	-- Classement du serveur en direct
	task.spawn(function()
		while true do
			task.wait(SERVER_RANKING_INTERVAL)
			local ok, err = pcall(self.Broadcast, self)
			if not ok then
				warn("[LeaderboardService] Échec d'envoi du classement du serveur :", err)
			end
		end
	end)

	-- Classements mondiaux (OrderedDataStore)
	task.spawn(function()
		task.wait(5) -- laisse le temps aux premiers joueurs de charger
		while true do
			local ok, err = pcall(function()
				for _, player in ipairs(services.DataService:GetLoadedPlayers()) do
					self:SubmitAsync(player)
				end
				self:RefreshAsync()
			end)
			if not ok then
				warn("[LeaderboardService] Erreur du classement mondial :", err)
			end
			task.wait(Config.Leaderboard.UpdateInterval)
		end
	end)
end

return LeaderboardService
