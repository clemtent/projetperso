--[[
	LeaderboardService (ModuleScript)
	Emplacement : ServerScriptService > Services > LeaderboardService

	Classement global (tous serveurs confondus) sur la Dopamine totale gagnée,
	avec un OrderedDataStore.

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
local cachedTop = {} -- dernier classement connu
local nameCache = {} -- [userId] = nom

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

function LeaderboardService:SendTo(player: Player)
	Net.Event("LeaderboardUpdate"):FireClient(player, cachedTop)
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
	Net.Event("LeaderboardUpdate"):FireAllClients(cachedTop)
end

function LeaderboardService:PlayerRemoving(player: Player)
	task.spawn(function()
		self:SubmitAsync(player)
	end)
end

function LeaderboardService:Start()
	task.spawn(function()
		task.wait(5) -- laisse le temps aux premiers joueurs de charger
		while true do
			for _, player in ipairs(services.DataService:GetLoadedPlayers()) do
				self:SubmitAsync(player)
			end
			self:RefreshAsync()
			task.wait(Config.Leaderboard.UpdateInterval)
		end
	end)
end

return LeaderboardService
