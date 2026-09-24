--[[
	Main (Script)
	Emplacement : ServerScriptService > Main

	Point d'entrée du serveur :
	  1. crée les RemoteEvents / RemoteFunctions (Net.Setup) ;
	  2. initialise puis démarre tous les services ;
	  3. gère l'arrivée et le départ des joueurs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
Net.Setup() -- AVANT tout le reste : les clients attendent ces remotes

-- Jeu 100 % interface 2D : pas de personnage (sinon il bouge en fond avec ZQSD / espace)
Players.CharacterAutoLoads = false

local ServicesFolder = script.Parent:WaitForChild("Services")

-- Ordre important : les données d'abord, puis le jeu, puis le reste
-- (PlayerReady est appelé dans cet ordre : QuestService a besoin des stats,
-- DVDService crée les logos avant la synchro complète)
-- (MonetizationService vérifie les Game Passes, ThemeService en a besoin)
local ORDER = {
	"DataService",
	"GameService",
	"MonetizationService",
	"ThemeService",
	"EventService",
	"DVDService",
	"InteractService",
	"StockService",
	"CasinoService",
	"LootService",
	"CosmeticService",
	"QuestService",
	"AchievementService",
	"DailyRewardService",
	"LeaderboardService",
	"DebugService",
}

local services = {}
for _, name in ipairs(ORDER) do
	services[name] = require(ServicesFolder:WaitForChild(name))
end

-- Init : chaque service reçoit la liste des autres (évite les require circulaires)
for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.Init then
		service:Init(services)
	end
end

for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.Start then
		service:Start()
	end
end

----------------------------------------------------------------------
-- Joueurs
----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local data = services.DataService:LoadAsync(player)
	if not data or not player.Parent then
		return
	end

	for _, name in ipairs(ORDER) do
		local service = services[name]
		if service.PlayerReady then
			local ok, err = pcall(service.PlayerReady, service, player, data)
			if not ok then
				warn("[Main] Erreur PlayerReady dans " .. name .. " :", err)
			end
		end
	end

	services.GameService:SendFullSync(player)
end

local function onPlayerRemoving(player: Player)
	for _, name in ipairs(ORDER) do
		local service = services[name]
		if service.PlayerRemoving then
			local ok, err = pcall(service.PlayerRemoving, service, player)
			if not ok then
				warn("[Main] Erreur PlayerRemoving dans " .. name .. " :", err)
			end
		end
	end
	services.DataService:ReleaseAsync(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Joueurs déjà présents (arrive parfois dans Studio)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
