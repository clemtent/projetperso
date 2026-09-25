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
	  /lang fr          -> langue du jeu : auto, en ou fr (appliquée au prochain lancement)
	  /help             -> liste des commandes
	Les messages sont écrits en anglais puis traduits dans la langue du
	joueur (Locale.TFor, traductions dans Shared > Lang > FR_Server).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
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
	"pass", "boost", "theme", "offline", "lang", "help", "aide",
}

-- Aide : "%s" = types d'objets de /spawn
local HELP = "/give /rush /daily /save /corner /unlockall /spawn <%s> /detox /chest /reset"
	.. " /pass <id> /boost <mult> <seconds> /theme <id> /offline <seconds> /lang <auto|en|fr>"

-- /lang : argument (minuscules) -> valeur de Settings.Language
local LANGUAGE_ARGS = { auto = "Auto", en = "en", fr = "fr" }

function DebugService:Init(allServices)
	services = allServices
end

-- Texte dans la langue du joueur
local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

local function helpText(player: Player): string
	return T(player, HELP, listIds(spawnKinds))
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
		return false, T(player, "Loading...")
	end

	if command == "give" then
		local amount = tonumber(argument) or 1e6
		if amount ~= amount or amount <= 0 or amount == math.huge then
			return false, T(player, "Invalid amount")
		end
		gameService:AddDopamine(player, amount, false)
		return true, "+" .. NumberFormatter.Format(amount) .. " " .. Config.Game.CurrencyName
	elseif command == "rush" then
		if services.EventService:StartRush() then
			return true, T(player, "Dopamine Rush started!")
		end
		return false, T(player, "A Rush is already running")
	elseif command == "daily" then
		data.Daily.LastDay = 0
		gameService:MarkDirty(player)
		return true, T(player, "Daily gift available")
	elseif command == "save" then
		local ok = services.DataService:SaveAsync(player, true)
		return ok, ok and T(player, "💾 Saved!") or T(player, "💾 Couldn't save (see the Output)")
	elseif command == "corner" then
		if services.DVDService:DebugCorner(player) then
			return true, T(player, "Corner in ~2 seconds...")
		end
		return false, T(player, "You need at least one DVD logo")
	elseif command == "unlockall" then
		for _, upgrade in ipairs(Config.Upgrades) do
			if upgrade.Effect ~= "Detox" then
				local level = data.Upgrades[upgrade.Id] or 0
				data.Upgrades[upgrade.Id] = upgrade.MaxLevel or math.max(level, 1)
			end
		end
		services.QuestService:Regenerate(player)
		gameService:RefreshAfterUpgradeChange(player)
		return true, T(player, "Everything unlocked!")
	elseif command == "spawn" or command == "golden" then
		local kind = (command == "golden") and "Golden" or spawnKinds[argument]
		if not kind then
			return false, T(player, "Unknown type: %s", listIds(spawnKinds))
		end
		if not services.EventService:Spawn(player, kind) then
			return false, T(player, "Too many %s objects on screen", kind)
		end
		return true, T(player, "%s object sent", kind)
	elseif command == "detox" then
		gameService:Detox(player)
		return true, T(player, "🌊 Free detox")
	elseif command == "chest" then
		local count = math.floor(tonumber(argument) or 1)
		if count ~= count or count < 1 or count == math.huge then
			count = 1
		end
		services.LootService:AddChests(player, count)
		return true, T(player, "Chests added")
	elseif command == "reset" then
		services.DataService:ResetData(player)
		gameService:ResetCombo(player)
		services.EventService:ClearSpawns(player)
		services.DVDService:Reset(player)
		services.QuestService:PlayerReady(player, data)
		gameService:SendFullSync(player)
		return true, T(player, "Data reset")
	elseif command == "pass" then
		local passId = passIds[argument]
		if not passId then
			return false, T(player, "Unknown pass: %s", listIds(passIds))
		end
		local owned = services.MonetizationService:DebugTogglePass(player, passId)
		if owned == nil then
			return false, T(player, "Couldn't toggle this pass")
		end
		gameService:SendState(player)
		return true, owned and T(player, "Pass %s enabled", passId) or T(player, "Pass %s disabled", passId)
	elseif command == "boost" then
		local multiplier = tonumber(argument) or 2
		local seconds = tonumber(second) or 60
		if multiplier ~= multiplier or multiplier < 1 or multiplier > 1000
			or seconds ~= seconds or seconds < 0 or seconds > 7 * 86400 then
			return false, T(player, "Usage: /boost <mult 1-1000> <seconds>")
		end
		data.Boost = { Multiplier = multiplier, EndsAt = os.time() + math.floor(seconds) }
		gameService:SendState(player)
		return true, T(player, "Boost x%s for %d s", tostring(multiplier), math.floor(seconds))
	elseif command == "theme" then
		local themeId = themeIds[argument]
		if not themeId or not services.ThemeService:DebugGrant(player, themeId) then
			return false, T(player, "Unknown theme: %s", listIds(themeIds))
		end
		gameService:SendState(player)
		return true, T(player, "Theme %s given and equipped", themeId)
	elseif command == "offline" then
		local seconds = tonumber(argument) or 7200
		if seconds ~= seconds or seconds <= 0 or seconds > MAX_OFFLINE_SECONDS then
			return false, T(player, "Usage: /offline <seconds 1-%s>", tostring(MAX_OFFLINE_SECONDS))
		end
		local amount = gameService:GrantOffline(player, math.floor(seconds), true)
		if amount <= 0 then
			return false, T(player, "Nothing earned (no production or away < %s s)", tostring(Config.Offline.MinSeconds))
		end
		return true, T(player, "Offline simulated: +%s %s", NumberFormatter.Format(amount), Config.Game.CurrencyName)
	elseif command == "lang" then
		local language = LANGUAGE_ARGS[argument]
		if not language then
			return false, T(player, "Usage: /lang <auto|en|fr>")
		end
		data.Settings.Language = language
		gameService:MarkDirty(player)
		-- Message dans la NOUVELLE langue (celle du prochain lancement)
		return true, Locale.TFor(Locale.ForPlayer(player, language),
			"🌐 Language: %s (takes effect after rejoining)", language)
	elseif command == "help" or command == "aide" then
		return true, helpText(player)
	end
	return false, T(player, "Unknown command. %s", helpText(player))
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
-- 3e valeur renvoyée : true si c'était un doublon (rien n'a été exécuté).
local function execute(player: Player, line: string, source: string): (boolean, string, boolean)
	local command, argument, second = parse(line)
	if not command then
		return false, T(player, "Invalid command"), false
	end
	local normalized = command .. " " .. argument .. " " .. second
	local clock = os.clock()
	local last = lastRun[player]
	if last and last.Line == normalized and clock - last.Clock < DUPLICATE_WINDOW
		and (last.Source ~= source or source == "chat") then
		return true, T(player, "(already run)"), true
	end
	lastRun[player] = { Line = normalized, Clock = clock, Source = source }

	local ok, success, message = pcall(runCommand, player, command, argument, second)
	if not ok then
		warn("[DebugService] Erreur de la commande /" .. command .. " :", success)
		return false, T(player, "Error: %s", tostring(success)), false
	end
	return success, message, false
end

-- Message de chat : exécuté s'il ressemble à une commande "/xxx", résultat en notification
local function handleChat(player: Player, message: string)
	if not string.match(message, "^%s*/%a") then
		return
	end
	local ok, text, duplicate = execute(player, message, "chat")
	if not duplicate then
		info(player, (ok and "" or "❌ ") .. text)
	end
end

-- RemoteFunction DebugCommand (command: string, arg: string?) -> (ok, message)
local function onDebugCommand(player: Player, command: any, argument: any): (boolean, string)
	if not IS_STUDIO then
		return false, T(player, "Test commands are only available in Studio")
	end
	if type(command) ~= "string" or #command == 0 or #command > 64 then
		return false, T(player, "Invalid command")
	end
	if argument ~= nil and (type(argument) ~= "string" or #argument > 64) then
		return false, T(player, "Invalid argument")
	end
	local ok, message = execute(player, command .. " " .. (argument or ""), "remote")
	return ok, message
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
