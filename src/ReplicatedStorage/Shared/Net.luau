--[[
	Net (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Net

	Centralise les RemoteEvents / RemoteFunctions.
	- Le SERVEUR appelle Net.Setup() au démarrage : il crée automatiquement le
	  dossier ReplicatedStorage > Remotes et tous les remotes listés ci-dessous.
	  => Tu n'as RIEN à créer à la main.
	- Le CLIENT utilise Net.Event("Nom") / Net.Function("Nom") qui attendent
	  que le remote existe.

	Sens de communication :
	  C -> S : le client demande, le serveur valide TOUT.
	  S -> C : le serveur informe le client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	"ClientReady", -- C -> S : le client est prêt à recevoir les données
	"Click", -- C -> S : un clic sur le gros bouton
	"StateUpdate", -- S -> C : état complet du joueur (Dopamine, niveaux...)
	"Notify", -- S -> C : notifications (succès, bonus, jackpot, erreurs...)
	"DVDSetup", -- S -> C : paramètres du mouvement du logo DVD
	"DVDResize", -- C -> S : taille du logo à l'écran (en fraction de l'écran)
	"DVDClick", -- C -> S : clic sur le logo DVD
	"DVDCorner", -- C -> S : le client pense que le logo a touché un coin
	"GoldenSpawn", -- S -> C : un objet doré apparaît
	"GoldenClick", -- C -> S : le joueur a cliqué l'objet doré
	"EventUpdate", -- S -> C : début / fin d'un Dopamine Rush
	"LeaderboardUpdate", -- S -> C : top du classement
}

Net.Functions = {
	"BuyUpgrade", -- C -> S : (upgradeId, mode) -> (succès, message)
	"Rebirth", -- C -> S : () -> (succès, message)
	"ClaimDaily", -- C -> S : () -> (succès, message)
	"SetSetting", -- C -> S : (nom, valeur) -> succès
}

local FOLDER_NAME = "Remotes"

-- Serveur uniquement : crée tous les remotes
function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup() doit être appelé par le serveur")

	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	for _, name in ipairs(Net.Events) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end

	for _, name in ipairs(Net.Functions) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

local function getFolder(): Instance
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Net.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Net
