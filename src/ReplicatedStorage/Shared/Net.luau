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
	"StateTick", -- S -> C (tick) : petite mise à jour fréquente (Dopamine, clics...) entre deux états complets
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
	"ArcadeEvent", -- S <-> C (kind, payload) : arcade en temps réel (invitations, coups des duels...)
	"FriendMailEvent", -- S -> C ("New", mail filtré) : un mail d'ami Roblox arrive (FriendMailService)
	"WorldEvent", -- S -> C (kind, payload) : 🚶 Dopamine Town (maisons, "j'aime", messages) (WorldService)
	"MusicEvent", -- C <-> S (kind, ...) : 🎵 scène musicale de la place (notes relayées aux voisins, morceaux, radio) (TownMusic, v9.9)
}

Net.Functions = {
	"BuyUpgrade", -- C -> S (upgradeId) -> (succès, message)
	"ClaimDaily", -- C -> S () -> (succès, message)
	"SetSetting", -- C -> S (nom, valeur) -> succès
	"CasinoSpin", -- C -> S () -> (succès, résultat | message) : tour GRATUIT (1 jeton) de la machine chanceuse
	"OpenChest", -- C -> S () -> (succès, résultat | message)
	"ItemShop", -- C -> S ("buy" | "equip" | "unequip", cosmeticId) -> (succès, message)
	"ThemeShop", -- C -> S ("buy" | "equip", themeId) -> (succès, message)
	"House", -- C -> S (action, argument) -> (succès, message) : maison (achats, papier peint, sol, disposition)
	"Garden", -- C -> S (action, argument) -> (succès, résultat | message) : jardin de Dopamine
	"Arcade", -- C -> S (action, argument) -> (succès, résultat | message) : mini-jeux, tickets, duels
	"FilterText", -- C -> S (purpose "Live" | "Mail", texte) -> (succès, { Text, Topics } | message) : texte tapé, filtré par Roblox
	"FriendMail", -- C -> S (action, argument) -> (succès, résultat | message, état?) : mails entre amis Roblox (FriendMailService)
	"World", -- C -> S (action, argument) -> (succès, résultat | message) : 🚶 Dopamine Town (entrer, visiter, s'asseoir, j'aime) (WorldService)
	"Car", -- C -> S (action, a, b) -> (succès, message, extra?) : 🚗 voitures (acheter, couleur, choisir, garage, conduire, klaxon) (CarService)
	"Food", -- C -> S ("buy", foodId, stallId | "bite") -> (succès, message, manquant?) : 🍦 nourriture de Dopamine Town (FoodService, v9.8)
	"DebugCommand", -- C -> S (commande, argument) -> (succès, message) : UNIQUEMENT dans Studio
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
