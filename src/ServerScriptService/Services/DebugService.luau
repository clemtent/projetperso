--[[
	DebugService (ModuleScript)
	Emplacement : ServerScriptService > Services > DebugService

	Commandes de TEST, actives UNIQUEMENT dans Roblox Studio (jamais dans le
	jeu publié). Trois façons de les lancer, qui passent toutes par le MÊME
	exécuteur (runCommand) :
	  - le chat (TextChatCommand côté serveur + Player.Chatted pour l'ancien chat) ;
	  - la RemoteFunction DebugCommand (commande, argument) -> (succès, message),
	    utilisée par le panneau "🛠️ Test" et les commandes de chat du client.
	    Hors Studio, elle répond toujours (false, message) sans rien faire.
	Commandes :
	  /give 1e6         -> donne de la Dopamine (ici 1 million)
	  /rush             -> lance un Dopamine Rush
	  /daily            -> rend la récompense quotidienne à nouveau disponible
	  /save             -> force une sauvegarde
	  /corner           -> le 1er logo DVD touchera un coin dans ~2 secondes
	  /unlockall        -> toutes les améliorations au max (sauf l'océan)
	  /spawn golden     -> fait apparaître un objet (golden, lightning, notif, email, donation)
	  /golden           -> raccourci de /spawn golden
	  /detox            -> va à l'océan gratuitement
	  /chest 3          -> ajoute des coffres mystère
	  /reset            -> remet toutes les données à zéro (sauf les réglages)
	  /pass vip         -> active / désactive un Game Pass pour tester (x10, x2, autoclick, vip)
	  /boost 5 60       -> boost x5 pendant 60 secondes
	  /theme kawaii     -> donne et équipe un thème
	  /offline 7200     -> simule un retour après 7200 s d'absence (gain hors-ligne)
	  /help             -> liste des commandes
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local DebugService = {}

local services

local IS_STUDIO = RunService:IsStudio()
local MAX_OFFLINE_SECONDS = 30 * 86400 -- /offline : 30 jours au maximum
-- Même commande reçue par deux chemins différents (chat serveur + RF du
-- client) en moins de DUPLICATE_WINDOW secondes : exécutée une seule fois
local DUPLICATE_WINDOW = 1

-- "golden" -> "Golden" (le chat est mis en minuscules)
local spawnKinds = {}
for kind in pairs(Config.Spawners) do
	spawnKinds[string.lower(kind)] = kind
end

-- "vip" -> "VIP", "kawaii" -> "Kawaii" (le chat est mis en minuscules)
local passIds = {}
for _, pass in ipairs(Config.Monetization.GamePasses) do
	passIds[string.lower(pass.Id)] = pass.Id
end
local themeIds = {}
for _, theme in ipairs(Config.Themes) do
	themeIds[string.lower(theme.Id)] = theme.Id
end

local function listIds(map): string
	local list = {}
	for lower in pairs(map) do
		table.insert(list, lower)
	end
	table.sort(list)
	return table.concat(list, ", ")
end

-- Noms des commandes (déclarées comme TextChatCommand dans Studio)
local COMMAND_NAMES = {
	"give", "rush", "daily", "save", "corner", "unlockall", "spawn", "golden", "detox", "chest", "reset",
	"pass", "boost", "theme", "offline", "aide",
}

local HELP = "/give /rush /daily /save /corner /unlockall /spawn <" .. listIds(spawnKinds) .. "> /detox /chest /reset"
	.. " /pass <id> /boost <mult> <secondes> /theme <id> /offline <secondes>"

function DebugService:Init(allServices)
	services = allServices
end

local function info(player: Player, text: string)
	services.GameService:Notify(player, { Type = "Info", Text = "🛠️ " .. text })
end

----------------------------------------------------------------------
-- Exécuteur commun : renvoie (succès, message)
----------------------------------------------------------------------

local function runCommand(player: Player, command: string, argument: string, second: string): (boolean, string)
	local gameService = services.GameService
	local data = services.DataService:GetData(player)
	if not data or not gameService:IsReady(player) then
		return false, "Chargement en cours..."
	end

	if command == "give" then
		local amount = tonumber(argument) or 1e6
		if amount ~= amount or amount <= 0 or amount == math.huge then
			return false, "Montant invalide"
		end
		gameService:AddDopamine(player, amount, false)
		return true, "+" .. NumberFormatter.Format(amount) .. " " .. Config.Game.CurrencyName
	elseif command == "rush" then
		if services.EventService:StartRush() then
			return true, "Dopamine Rush lancé !"
		end
		return false, "Un Rush est déjà en cours"
	elseif command == "daily" then
		data.Daily.LastDay = 0
		gameService:MarkDirty(player)
		return true, "Cadeau quotidien disponible"
	elseif command == "save" then
		local ok = services.DataService:SaveAsync(player, true)
		return ok, ok and "💾 Sauvegardé !" or "💾 Sauvegarde impossible (voir la sortie)"
	elseif command == "corner" then
		if services.DVDService:DebugCorner(player) then
			return true, "Coin dans ~2 secondes..."
		end
		return false, "Il faut au moins un logo DVD"
	elseif command == "unlockall" then
		for _, upgrade in ipairs(Config.Upgrades) do
			if upgrade.Effect ~= "Detox" then
				local level = data.Upgrades[upgrade.Id] or 0
				data.Upgrades[upgrade.Id] = upgrade.MaxLevel or math.max(level, 1)
			end
		end
		services.QuestService:Regenerate(player)
		gameService:RefreshAfterUpgradeChange(player)
		return true, "Tout est débloqué !"
	elseif command == "spawn" or command == "golden" then
		local kind = (command == "golden") and "Golden" or spawnKinds[argument]
		if not kind then
			return false, "Type inconnu : " .. listIds(spawnKinds)
		end
		if not services.EventService:Spawn(player, kind) then
			return false, "Trop d'objets " .. kind .. " à l'écran"
		end
		return true, "Objet " .. kind .. " envoyé"
	elseif command == "detox" then
		gameService:Detox(player)
		return true, "🌊 Détox gratuite"
	elseif command == "chest" then
		local count = math.floor(tonumber(argument) or 1)
		if count ~= count or count < 1 or count == math.huge then
			count = 1
		end
		services.LootService:AddChests(player, count)
		return true, "Coffres ajoutés"
	elseif command == "reset" then
		services.DataService:ResetData(player)
		gameService:ResetCombo(player)
		services.EventService:ClearSpawns(player)
		services.DVDService:Reset(player)
		services.QuestService:PlayerReady(player, data)
		gameService:SendFullSync(player)
		return true, "Données remises à zéro"
	elseif command == "pass" then
		local passId = passIds[argument]
		if not passId then
			return false, "Pass inconnu : " .. listIds(passIds)
		end
		local owned = services.MonetizationService:DebugTogglePass(player, passId)
		if owned == nil then
			return false, "Impossible de changer ce pass"
		end
		gameService:SendState(player)
		return true, "Pass " .. passId .. (owned and " activé" or " désactivé")
	elseif command == "boost" then
		local multiplier = tonumber(argument) or 2
		local seconds = tonumber(second) or 60
		if multiplier ~= multiplier or multiplier < 1 or multiplier > 1000
			or seconds ~= seconds or seconds < 0 or seconds > 7 * 86400 then
			return false, "Usage : /boost <mult 1-1000> <secondes>"
		end
		data.Boost = { Multiplier = multiplier, EndsAt = os.time() + math.floor(seconds) }
		gameService:SendState(player)
		return true, string.format("Boost x%s pendant %d s", tostring(multiplier), math.floor(seconds))
	elseif command == "theme" then
		local themeId = themeIds[argument]
		if not themeId or not services.ThemeService:DebugGrant(player, themeId) then
			return false, "Thème inconnu : " .. listIds(themeIds)
		end
		gameService:SendState(player)
		return true, "Thème " .. themeId .. " donné et équipé"
	elseif command == "offline" then
		local seconds = tonumber(argument) or 7200
		if seconds ~= seconds or seconds <= 0 or seconds > MAX_OFFLINE_SECONDS then
			return false, "Usage : /offline <secondes 1-" .. MAX_OFFLINE_SECONDS .. ">"
		end
		local amount = gameService:GrantOffline(player, math.floor(seconds), true)
		if amount <= 0 then
			return false, "Rien gagné (production nulle ou absence < " .. Config.Offline.MinSeconds .. " s)"
		end
		return true, "Hors-ligne simulé : +" .. NumberFormatter.Format(amount) .. " " .. Config.Game.CurrencyName
	elseif command == "help" or command == "aide" then
		return true, HELP
	end
	return false, "Commande inconnue. " .. HELP
end

----------------------------------------------------------------------
-- Entrée commune (chat et RemoteFunction)
----------------------------------------------------------------------

-- Dernière commande exécutée par joueur (anti-doublon entre les chemins)
local lastRun: { [Player]: { Line: string, Clock: number, Source: string } } = {}

-- Découpe "/give 1e6" ou "boost 5 60" en (commande, argument, second)
local function parse(line: string): (string?, string, string)
	local command, argument, second = string.match(string.lower(line), "^%s*/?(%a+)%s*(%S*)%s*(%S*)")
	return command, argument or "", second or ""
end

-- `source` = "chat" ou "remote". Doublon ignoré si la même ligne arrive dans
-- la seconde par un autre chemin (ou deux fois par le chat) ; deux clics
-- rapides sur le même bouton du panneau de test restent exécutés.
local function execute(player: Player, line: string, source: string): (boolean, string)
	local command, argument, second = parse(line)
	if not command then
		return false, "Commande invalide"
	end
	local normalized = command .. " " .. argument .. " " .. second
	local clock = os.clock()
	local last = lastRun[player]
	if last and last.Line == normalized and clock - last.Clock < DUPLICATE_WINDOW
		and (last.Source ~= source or source == "chat") then
		return true, "(déjà exécutée)"
	end
	lastRun[player] = { Line = normalized, Clock = clock, Source = source }

	local ok, success, message = pcall(runCommand, player, command, argument, second)
	if not ok then
		warn("[DebugService] Erreur de la commande /" .. command .. " :", success)
		return false, "Erreur : " .. tostring(success)
	end
	return success, message
end

-- Message de chat : exécuté s'il ressemble à une commande "/xxx", résultat en notification
local function handleChat(player: Player, message: string)
	if not string.match(message, "^%s*/%a") then
		return
	end
	local ok, text = execute(player, message, "chat")
	if text ~= "(déjà exécutée)" then
		info(player, (ok and "" or "❌ ") .. text)
	end
end

-- RemoteFunction DebugCommand (command: string, arg: string?) -> (ok, message)
local function onDebugCommand(player: Player, command: any, argument: any): (boolean, string)
	if not IS_STUDIO then
		return false, "Commandes de test disponibles uniquement dans Studio"
	end
	if type(command) ~= "string" or #command == 0 or #command > 64 then
		return false, "Commande invalide"
	end
	if argument ~= nil and (type(argument) ~= "string" or #argument > 64) then
		return false, "Argument invalide"
	end
	return execute(player, command .. " " .. (argument or ""), "remote")
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function DebugService:Start()
	-- Toujours branchée (sinon l'appel du client resterait bloqué), mais ne
	-- fait rien hors de Studio
	Net.Function("DebugCommand").OnServerInvoke = onDebugCommand

	if not IS_STUDIO then
		return
	end
	-- Avec le nouveau chat (TextChatService), un message "/xxx" inconnu peut ne
	-- jamais arriver à Player.Chatted : on déclare donc de vraies commandes.
	local ok, err = pcall(function()
		local folder = Instance.new("Folder")
		folder.Name = "DopamineDebugCommands"
		for _, name in ipairs(COMMAND_NAMES) do
			local command = Instance.new("TextChatCommand")
			command.Name = "Debug_" .. name
			command.PrimaryAlias = "/" .. name
			command.Triggered:Connect(function(textSource: TextSource, text: string)
				local player = Players:GetPlayerByUserId(textSource.UserId)
				if player and services.DataService:GetData(player) then
					handleChat(player, text)
				end
			end)
			command.Parent = folder
		end
		folder.Parent = TextChatService
	end)
	if not ok then
		warn("[DebugService] Impossible de déclarer les commandes de chat :", err)
	end
end

function DebugService:PlayerReady(player: Player)
	if not IS_STUDIO then
		return
	end
	-- Ancien chat (LegacyChatService) : Player.Chatted suffit
	player.Chatted:Connect(function(message: string)
		handleChat(player, message)
	end)
end

function DebugService:PlayerRemoving(player: Player)
	lastRun[player] = nil
end

return DebugService
