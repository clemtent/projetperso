--[[
	ClientMain (LocalScript)
	Emplacement : StarterPlayer > StarterPlayerScripts > ClientMain

	Point d'entrée du client : construit toute l'interface en code et
	branche les RemoteEvents. Aucune logique de gain ici : le client
	affiche et envoie des DEMANDES, le serveur décide.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Client = ReplicatedStorage:WaitForChild("Client")
local Components = Client:WaitForChild("Components")
local Panels = Components:WaitForChild("Panels")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Interface = require(Client:WaitForChild("Interface"))
local ClientState = require(Client:WaitForChild("ClientState"))
local SoundManager = require(Client:WaitForChild("SoundManager"))
local Effects = require(Client:WaitForChild("Effects"))

local Background = require(Components:WaitForChild("Background"))
local HUD = require(Components:WaitForChild("HUD"))
local Clicker = require(Components:WaitForChild("Clicker"))
local Shop = require(Components:WaitForChild("Shop"))
local SideMenu = require(Components:WaitForChild("SideMenu"))
local Notifications = require(Components:WaitForChild("Notifications"))
local DVDLogo = require(Components:WaitForChild("DVDLogo"))
local GoldenObject = require(Components:WaitForChild("GoldenObject"))
local PanelManager = require(Components:WaitForChild("PanelManager"))

-- Le sac à dos (outils) ne sert à rien ici
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- 1. Services de base
SoundManager.Init()
ClientState.Init()

-- 2. Écran et calques
local screenGui = Interface.Build()
Background.Build(screenGui)
local layers = Interface.Layers
Effects.Init(layers.Effects)

-- 3. Composants
HUD.Build(layers.Main)
Clicker.Build(layers.Main)
Shop.Build(layers.Main)
SideMenu.Build(layers.Main)
Notifications.Build(layers.Toasts)
DVDLogo.Build(layers.DVD)
GoldenObject.Build(layers.Golden)

-- 4. Fenêtres
PanelManager.Build(layers.Panels)
PanelManager.Register("Quests", require(Panels:WaitForChild("Quests")))
PanelManager.Register("Achievements", require(Panels:WaitForChild("Achievements")))
PanelManager.Register("Rebirth", require(Panels:WaitForChild("Rebirth")))
PanelManager.Register("Daily", require(Panels:WaitForChild("Daily")))
PanelManager.Register("Leaderboard", require(Panels:WaitForChild("Leaderboard")))
PanelManager.Register("Settings", require(Panels:WaitForChild("Settings")))

-- 5. Événements serveur
Net.Event("Notify").OnClientEvent:Connect(Notifications.Handle)
ClientState.RushChanged:Connect(function(rush)
	Background.SetRush(rush.Active)
end)

-- Au premier état reçu : on ouvre le cadeau du jour s'il est disponible
local firstState
firstState = ClientState.Changed:Connect(function(data)
	firstState:Disconnect()
	if data.Daily.Available then
		task.delay(1.5, PanelManager.Open, "Daily")
	end
end)

-- 6. On prévient le serveur que l'interface est prête
Net.Event("ClientReady"):FireServer()
