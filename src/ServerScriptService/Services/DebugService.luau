--[[
	DebugService (ModuleScript)
	Emplacement : ServerScriptService > Services > DebugService

	Commandes de TEST, actives UNIQUEMENT dans Roblox Studio (jamais dans le
	jeu publié). Tape-les dans le chat pendant un test "Play" :
	  /give 1e6       -> donne de la Dopamine (ici 1 million)
	  /rush           -> lance un Dopamine Rush
	  /daily          -> rend la récompense quotidienne à nouveau disponible
	  /save           -> force une sauvegarde
	  /corner         -> le 1er logo DVD touchera un coin dans ~2 secondes
	  /unlockall      -> toutes les améliorations au max (sauf l'océan)
	  /spawn golden   -> fait apparaître un objet (golden, lightning, notif, email)
	  /golden         -> raccourci de /spawn golden
	  /detox          -> va à l'océan gratuitement
	  /chest 3        -> ajoute des coffres mystère
	  /reset          -> remet toutes les données à zéro (sauf les réglages)
	  /help           -> liste des commandes
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)

local DebugService = {}

local services

-- "golden" -> "Golden" (le chat est mis en minuscules)
local spawnKinds = {}
for kind in pairs(Config.Spawners) do
	spawnKinds[string.lower(kind)] = kind
end

-- Noms des commandes (déclarées comme TextChatCommand dans Studio)
local COMMAND_NAMES = { "give", "rush", "daily", "save", "corner", "unlockall", "spawn", "golden", "detox", "chest", "reset", "help" }

local HELP = "/give /rush /daily /save /corner /unlockall /spawn <golden|lightning|notif|email> /detox /chest /reset"

function DebugService:Init(allServices)
	services = allServices
end

local function info(player: Player, text: string)
	services.GameService:Notify(player, { Type = "Info", Text = "🛠️ " .. text })
end

local function runCommand(player: Player, command: string, argument: string)
	local gameService = services.GameService
	local data = services.DataService:GetData(player)
	if not data then
		return
	end

	if command == "give" then
		local amount = tonumber(argument) or 1e6
		if amount ~= amount or amount <= 0 or amount == math.huge then
			info(player, "Montant invalide")
			return
		end
		gameService:AddDopamine(player, amount, false)
		info(player, "Dopamine ajoutée")
	elseif command == "rush" then
		services.EventService:StartRush()
	elseif command == "daily" then
		data.Daily.LastDay = 0
		gameService:MarkDirty(player)
		info(player, "Cadeau quotidien disponible")
	elseif command == "save" then
		local ok = services.DataService:SaveAsync(player)
		info(player, ok and "💾 Sauvegardé !" or "💾 Sauvegarde impossible (voir la sortie)")
	elseif command == "corner" then
		if services.DVDService:DebugCorner(player) then
			info(player, "Coin dans ~2 secondes...")
		else
			info(player, "Il faut au moins un logo DVD")
		end
	elseif command == "unlockall" then
		for _, upgrade in ipairs(Config.Upgrades) do
			if upgrade.Effect ~= "Detox" then
				local level = data.Upgrades[upgrade.Id] or 0
				data.Upgrades[upgrade.Id] = upgrade.MaxLevel or math.max(level, 1)
			end
		end
		services.QuestService:Regenerate(player)
		gameService:RefreshAfterUpgradeChange(player)
		info(player, "Tout est débloqué !")
	elseif command == "spawn" or command == "golden" then
		local kind = (command == "golden") and "Golden" or spawnKinds[argument]
		if not kind then
			info(player, "Type inconnu : golden, lightning, notif ou email")
			return
		end
		if not services.EventService:Spawn(player, kind) then
			info(player, "Trop d'objets " .. kind .. " à l'écran")
		end
	elseif command == "detox" then
		gameService:Detox(player)
	elseif command == "chest" then
		local count = math.floor(tonumber(argument) or 1)
		if count ~= count or count < 1 then
			count = 1
		end
		services.LootService:AddChests(player, count)
		info(player, "Coffres ajoutés")
	elseif command == "reset" then
		services.DataService:ResetData(player)
		gameService:ResetCombo(player)
		services.EventService:ClearSpawns(player)
		services.DVDService:Reset(player)
		services.QuestService:PlayerReady(player, data)
		gameService:SendFullSync(player)
		info(player, "Données remises à zéro")
	elseif command == "help" then
		info(player, HELP)
	end
end

-- Exécute un message de chat s'il ressemble à une commande "/xxx"
-- (anti-doublon : le même message reçu deux fois en 1 s n'est exécuté qu'une fois)
local lastMessage: { [Player]: { Text: string, Clock: number } } = {}
local function handleMessage(player: Player, message: string)
	local command, argument = string.match(string.lower(message), "^/(%a+)%s*(%S*)")
	if not command then
		return
	end
	local last = lastMessage[player]
	if last and last.Text == message and os.clock() - last.Clock < 1 then
		return
	end
	lastMessage[player] = { Text = message, Clock = os.clock() }
	local ok, err = pcall(runCommand, player, command, argument or "")
	if not ok then
		warn("[DebugService] Erreur de la commande /" .. command .. " :", err)
	end
end

function DebugService:Start()
	if not RunService:IsStudio() then
		return
	end
	-- Avec le nouveau chat (TextChatService), un message "/xxx" inconnu peut ne
	-- jamais arriver à Player.Chatted : on déclare donc de vraies commandes.
	local folder = Instance.new("Folder")
	folder.Name = "DopamineDebugCommands"
	for _, name in ipairs(COMMAND_NAMES) do
		local command = Instance.new("TextChatCommand")
		command.Name = "Debug_" .. name
		command.PrimaryAlias = "/" .. name
		command.Triggered:Connect(function(textSource: TextSource, text: string)
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if player and services.DataService:GetData(player) then
				handleMessage(player, text)
			end
		end)
		command.Parent = folder
	end
	folder.Parent = TextChatService
end

function DebugService:PlayerReady(player: Player)
	if not RunService:IsStudio() then
		return
	end
	-- Ancien chat (LegacyChatService) : Player.Chatted suffit
	player.Chatted:Connect(function(message: string)
		handleMessage(player, message)
	end)
end

function DebugService:PlayerRemoving(player: Player)
	lastMessage[player] = nil
end

return DebugService
