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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local DebugService = {}

local services

-- "golden" -> "Golden" (le chat est mis en minuscules)
local spawnKinds = {}
for kind in pairs(Config.Spawners) do
	spawnKinds[string.lower(kind)] = kind
end

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

function DebugService:PlayerReady(player: Player)
	if not RunService:IsStudio() then
		return
	end

	player.Chatted:Connect(function(message: string)
		local command, argument = string.match(string.lower(message), "^/(%a+)%s*(%S*)")
		if not command then
			return
		end
		local ok, err = pcall(runCommand, player, command, argument or "")
		if not ok then
			warn("[DebugService] Erreur de la commande /" .. command .. " :", err)
		end
	end)
end

return DebugService
