--[[
	DebugTools (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > DebugTools

	Outils de TEST, actifs UNIQUEMENT dans Roblox Studio :
	  - DebugTools.Run(commande, argument) : appelle la RemoteFunction
	    "DebugCommand" (le serveur refuse tout hors de Studio) et renvoie
	    (succès, message). Utilisé par le panneau "🛠️ Test".
	  - DebugTools.RegisterChatCommands() : déclare des TextChatCommand
	    CÔTÉ CLIENT (/give, /unlockall, /spawn...) : leur événement Triggered
	    se déclenche de façon fiable côté client, puis appelle la même
	    RemoteFunction. Le résultat s'affiche dans le chat (message système)
	    et en bandeau. Les commandes identiques déclarées par le serveur sont
	    désactivées localement (pas de doublon ; le serveur ignore de toute
	    façon une commande reçue deux fois dans la même seconde).
	  - /test ouvre le panneau de test ; /aide liste les commandes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Notifications = require(script.Parent.Notifications)

local DebugTools = {}

DebugTools.Enabled = RunService:IsStudio()
DebugTools.Ran = Signal.new() -- (commande, argument, succès, message) après chaque commande

-- Appelé par /test (branché par ClientMain : ouvre le panneau de test)
DebugTools.OpenPanel = nil :: (() -> ())?

local REMOTE_TIMEOUT = 5
local FOLDER_NAME = "DopamineClientCommands"

-- Commandes de chat : alias -> commande envoyée au serveur
-- ("/help" est déjà pris par Roblox : on utilise "/aide")
local CHAT_COMMANDS = {
	{ Alias = "give", Command = "give", Help = "/give 1e6" },
	{ Alias = "rush", Command = "rush", Help = "/rush" },
	{ Alias = "daily", Command = "daily", Help = "/daily" },
	{ Alias = "save", Command = "save", Help = "/save" },
	{ Alias = "corner", Command = "corner", Help = "/corner" },
	{ Alias = "unlockall", Command = "unlockall", Help = "/unlockall" },
	{ Alias = "spawn", Command = "spawn", Help = "/spawn golden" },
	{ Alias = "golden", Command = "golden", Help = "/golden" },
	{ Alias = "detox", Command = "detox", Help = "/detox" },
	{ Alias = "chest", Command = "chest", Help = "/chest 3" },
	{ Alias = "reset", Command = "reset", Help = "/reset" },
	{ Alias = "pass", Command = "pass", Help = "/pass vip" },
	{ Alias = "boost", Command = "boost", Help = "/boost 5 60" },
	{ Alias = "theme", Command = "theme", Help = "/theme kawaii" },
	{ Alias = "offline", Command = "offline", Help = "/offline 7200" },
	{ Alias = "aide", Command = "help", Help = "/aide" },
}

local registered = false
local lastDuplicate = false -- la dernière commande était un doublon (déjà exécutée)
local myCommands: { [TextChatCommand]: boolean } = {}
local myAliases: { [string]: boolean } = {} -- "/give" -> true

-- Texte d'aide (liste des commandes de chat)
function DebugTools.HelpText(): string
	local list = {}
	for _, entry in ipairs(CHAT_COMMANDS) do
		table.insert(list, entry.Help)
	end
	table.insert(list, "/test")
	return table.concat(list, "  ")
end

-- RemoteFunction "DebugCommand" (sans attente infinie si le serveur ne l'a pas)
local function getRemote(): RemoteFunction?
	local folder = ReplicatedStorage:WaitForChild("Remotes", REMOTE_TIMEOUT)
	if not folder then
		return nil
	end
	local remote = folder:WaitForChild("DebugCommand", REMOTE_TIMEOUT)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end
	return nil
end

-- Lance une commande de test sur le serveur (bloque le thread appelant).
-- Renvoie (succès, message).
function DebugTools.Run(command: string, argument: string?): (boolean, string)
	if not DebugTools.Enabled then
		return false, Locale.T("Test commands are only available in Studio")
	end
	local remote = getRemote()
	if not remote then
		return false, Locale.T("DebugCommand RemoteFunction not found (server out of date?)")
	end
	local ok, success, message, duplicate = pcall(function()
		return remote:InvokeServer(command, argument or "")
	end)
	local result: boolean
	local text: string
	if not ok then
		result, text = false, Locale.T("Network error: %s", tostring(success))
	else
		result = success == true
		text = message ~= nil and tostring(message) or (result and "OK" or Locale.T("Refused"))
		-- 3e valeur du serveur : commande déjà exécutée (doublon du chat)
		if duplicate == true then
			lastDuplicate = true
		end
	end
	DebugTools.Ran:Fire(command, argument or "", result, text)
	return result, text
end

----------------------------------------------------------------------
-- Commandes de chat (client)
----------------------------------------------------------------------

-- Affiche un message système dans la fenêtre de chat (si possible)
local function systemMessage(text: string)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local channel = channels and channels:FindFirstChild("RBXSystem")
		if channel and channel:IsA("TextChannel") then
			channel:DisplaySystemMessage(text)
		end
	end)
end

-- Désactive (localement) une commande déclarée ailleurs avec un de nos alias
local function disableDuplicate(instance: Instance)
	if not instance:IsA("TextChatCommand") or myCommands[instance] then
		return
	end
	local primary = string.lower(instance.PrimaryAlias)
	local secondary = string.lower(instance.SecondaryAlias)
	if myAliases[primary] or myAliases[secondary] then
		pcall(function()
			instance.Enabled = false
		end)
	end
end

local function onTriggered(entry, text: string)
	-- "/give 1e6" -> argument "1e6" ; "/boost 5 60" -> "5 60"
	local argument = string.match(text, "^%s*/%S+%s*(.-)%s*$") or ""
	task.spawn(function()
		lastDuplicate = false
		local ok, message = DebugTools.Run(entry.Command, argument)
		if lastDuplicate or message == "(already run)" or message == "(déjà exécutée)" then
			return
		end
		systemMessage((ok and "🛠️ " or "❌ ") .. message)
		if not ok then
			Notifications.Toast(message, Theme.Colors.Red, 4, Locale.T("Command /%s", entry.Alias), false, "🛠️")
		end
	end)
end

function DebugTools.RegisterChatCommands()
	if not DebugTools.Enabled or registered then
		return
	end
	registered = true
	-- Les TextChatCommand ne marchent qu'avec le nouveau chat (TextChatService)
	local okVersion, isNewChat = pcall(function()
		return TextChatService.ChatVersion == Enum.ChatVersion.TextChatService
	end)
	if not okVersion or not isNewChat then
		return
	end

	local ok, err = pcall(function()
		local old = TextChatService:FindFirstChild(FOLDER_NAME)
		if old then
			old:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME

		local function add(alias: string, callback: (text: string) -> ())
			local command = Instance.new("TextChatCommand")
			command.Name = "ClientDebug_" .. alias
			command.PrimaryAlias = "/" .. alias
			myCommands[command] = true
			myAliases["/" .. alias] = true
			command.Triggered:Connect(function(_source: TextSource, text: string)
				callback(text)
			end)
			command.Parent = folder
		end

		for _, entry in ipairs(CHAT_COMMANDS) do
			add(entry.Alias, function(text: string)
				onTriggered(entry, text)
			end)
		end
		add("test", function()
			local open = DebugTools.OpenPanel
			if open then
				open()
			end
		end)
		folder.Parent = TextChatService
	end)
	if not ok then
		warn("[DebugTools] Impossible de déclarer les commandes de chat : " .. tostring(err))
		return
	end

	-- Commandes du serveur avec le même alias : désactivées ici (une seule exécution)
	for _, descendant in ipairs(TextChatService:GetDescendants()) do
		disableDuplicate(descendant)
	end
	TextChatService.DescendantAdded:Connect(disableDuplicate)
end

return DebugTools
