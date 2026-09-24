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
	  C -> S : le client DEMANDE, le serveur valide TOUT.
	  S -> C : le serveur informe le client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	"ClientReady", -- C -> S () : l'interface est prête, envoie-moi tout
	"Click", -- C -> S () : un clic sur le bouton
	"StateUpdate", -- S -> C (state) : état complet du joueur
	"Notify", -- S -> C (payload) : succès, quêtes, bonus, jackpot, détox...
	"DVDSetup", -- S -> C ({ Logos = { params... } }) : trajectoires des logos DVD
	"DVDResize", -- C -> S (w, h) : taille d'un logo à l'écran (fraction de l'écran)
	"DVDClick", -- C -> S (index) : clic sur le logo numéro `index`
	"DVDCorner", -- C -> S (index, k) : le logo `index` a touché un coin au rebond k
	"Spawn", -- S -> C (info) : un objet à cliquer apparaît (étoile, éclair, notif, mail)
	"SpawnClick", -- C -> S (id) : le joueur a cliqué cet objet
	"Interact", -- C -> S (kind, arg) : papier bulle, moulin, titre du fil d'actu, presse
	"EventUpdate", -- S -> C (rush) : début / fin d'un Dopamine Rush
	"LeaderboardUpdate", -- S -> C (top) : top du classement
	"StockUpdate", -- S -> C ({ Symbol, Price, History }) : cours de la bourse
}

Net.Functions = {
	"BuyUpgrade", -- C -> S (upgradeId) -> (succès, message)
	"ClaimDaily", -- C -> S () -> (succès, message)
	"SetSetting", -- C -> S (nom, valeur) -> succès
	"StockTrade", -- C -> S ("buy" | "sell", fraction) -> (succès, message)
	"CasinoSpin", -- C -> S (fraction) -> (succès, résultat | message)
	"OpenChest", -- C -> S () -> (succès, résultat | message)
	"ItemShop", -- C -> S ("buy" | "equip" | "unequip", cosmeticId) -> (succès, message)
	"ThemeShop", -- C -> S ("buy" | "equip", themeId) -> (succès, message)
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
