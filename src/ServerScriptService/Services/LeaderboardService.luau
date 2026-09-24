--[[
	LeaderboardService (ModuleScript)
	Emplacement : ServerScriptService > Services > LeaderboardService

	Classement disponible pour tout le monde dès le début (pas d'amélioration) :
	  - "Global" : top de tous les serveurs sur la Dopamine totale gagnée,
	    avec un OrderedDataStore (lu toutes les Config.Leaderboard.UpdateInterval s) ;
	  - "Server" : classement EN DIRECT des joueurs de ce serveur (Dopamine
	    actuelle), envoyé à tout le monde toutes les 2 secondes.
	Événement LeaderboardUpdate : { Global = { entrées }, Server = { entrées } }
	  Global : { Rank, UserId, Name, Value }
	  Server : { Rank, UserId, Name, Dopamine, Lifetime, Rebirths } (Dopamine décroissante)

	Astuce : un OrderedDataStore n'accepte que des entiers (max ~9.2e18),
	alors que la Dopamine peut dépasser 1e30. On stocke donc
	log10(valeur) * 1 000 000 (un entier), puis on refait l'inverse à la lecture.
	L'ordre du classement reste exactement le même.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local LeaderboardService = {}

local services
local orderedStore: OrderedDataStore? = nil
local cachedTop = {} -- dernier classement global connu
local nameCache = {} -- [userId] = nom

local SERVER_RANKING_INTERVAL = 2 -- secondes entre deux envois du classement du serveur

do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Leaderboard.StoreName)
	end)
	if ok then
		orderedStore = result
	else
		warn("[LeaderboardService] Classement indisponible :", result)
	end
end

local function encode(value: number): number
	return math.floor(math.log10(math.max(0, value) + 1) * 1e6)
end

local function decode(stored: number): number
	return 10 ^ (stored / 1e6) - 1
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
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Joueur " .. userId
end

function LeaderboardService:Init(allServices)
	services = allServices
end

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeNumber(value): number
	return isValidNumber(value) and value or 0
end

-- Classement en direct des joueurs chargés de ce serveur
local function buildServerRanking()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local data = services.DataService:GetData(player)
		if data then
			table.insert(list, {
				UserId = player.UserId,
				Name = player.DisplayName,
				Dopamine = safeNumber(data.Dopamine),
				Lifetime = safeNumber(data.Stats and data.Stats.LifetimeDopamine),
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
		Server = buildServerRanking(),
	}
end

function LeaderboardService:SendTo(player: Player)
	Net.Event("LeaderboardUpdate"):FireClient(player, buildPayload())
end

-- Envoie le classement (global en cache + serveur en direct) à tout le monde
function LeaderboardService:Broadcast()
	if #Players:GetPlayers() == 0 then
		return
	end
	Net.Event("LeaderboardUpdate"):FireAllClients(buildPayload())
end

-- Écrit le score d'un joueur dans le classement
function LeaderboardService:SubmitAsync(player: Player)
	local data = services.DataService:GetData(player)
	if not orderedStore or not data then
		return
	end
	local store = orderedStore :: OrderedDataStore
	local ok, err = pcall(function()
		store:SetAsync("P_" .. player.UserId, encode(data.Stats.LifetimeDopamine))
	end)
	if not ok then
		warn("[LeaderboardService] Échec d'envoi du score :", err)
	end
end

-- Lit le top et l'envoie à tout le monde
function LeaderboardService:RefreshAsync()
	if not orderedStore then
		return
	end
	local store = orderedStore :: OrderedDataStore
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.Leaderboard.Size)
	end)
	if not ok then
		warn("[LeaderboardService] Échec de lecture du classement :", pages)
		return
	end

	local top = {}
	for rank, entry in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(string.sub(entry.key, 3))
		if userId then
			table.insert(top, {
				Rank = rank,
				UserId = userId,
				Name = getName(userId),
				Value = decode(entry.value),
			})
		end
	end
	cachedTop = top
	self:Broadcast()
end

function LeaderboardService:PlayerRemoving(player: Player)
	task.spawn(function()
		self:SubmitAsync(player)
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

	-- Classement global (OrderedDataStore)
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
				warn("[LeaderboardService] Erreur du classement global :", err)
			end
			task.wait(Config.Leaderboard.UpdateInterval)
		end
	end)
end

return LeaderboardService
