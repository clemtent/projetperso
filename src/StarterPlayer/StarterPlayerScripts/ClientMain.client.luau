--[[
	ClientMain (LocalScript)
	Emplacement : StarterPlayer > StarterPlayerScripts > ClientMain

	Point d'entrée du client : construit toute l'interface en code, lance
	le gestionnaire de stimuli et branche les RemoteEvents. Aucune logique
	de gain ici : le client affiche et envoie des DEMANDES, le serveur décide.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Client = ReplicatedStorage:WaitForChild("Client")
local Components = Client:WaitForChild("Components")
local Panels = Components:WaitForChild("Panels")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Interface = require(Client:WaitForChild("Interface"))
local ClientState = require(Client:WaitForChild("ClientState"))
local SoundManager = require(Client:WaitForChild("SoundManager"))
local Effects = require(Client:WaitForChild("Effects"))
local StimulusManager = require(Client:WaitForChild("StimulusManager"))

local Background = require(Components:WaitForChild("Background"))
local Notifications = require(Components:WaitForChild("Notifications"))
local PanelManager = require(Components:WaitForChild("PanelManager"))
local CenterColumn = require(Components:WaitForChild("CenterColumn"))

-- Le sac à dos (outils) ne sert à rien ici. La liste des joueurs (leaderstats)
-- et la fenêtre de chat recouvriraient les emplacements R1 / L1 et captureraient
-- les clics : le jeu a déjà son propre classement.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)
-- (Dans Studio on garde le chat : il sert à taper les commandes de test /give, /rush...)
if not RunService:IsStudio() then
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	end)
	pcall(function()
		TextChatService.ChatWindowConfiguration.Enabled = false
	end)
end
-- Pas de joystick / bouton de saut tactiles : ils prendraient les appuis
-- destinés aux emplacements du bas (Runner, Lofi...)
pcall(function()
	GuiService.TouchControlsEnabled = false
end)

-- 1. Services de base
SoundManager.Init()
ClientState.Init()

-- 2. Écran et calques
Interface.Build()
local layers = Interface.Layers
Effects.Init(layers.Effects)
Background.Build(layers.Background)

-- 3. Toasts et fenêtres
Notifications.Build(layers.Toasts)
PanelManager.Build(layers.Panels)
PanelManager.Register("ScreenTime", require(Panels:WaitForChild("ScreenTime")))
PanelManager.Register("ItemShop", require(Panels:WaitForChild("ItemShop")))
PanelManager.Register("Achievements", require(Panels:WaitForChild("Achievements")))
PanelManager.Register("Quests", require(Panels:WaitForChild("Quests")))
PanelManager.Register("Leaderboard", require(Panels:WaitForChild("Leaderboard")))
PanelManager.Register("Daily", require(Panels:WaitForChild("Daily")))
PanelManager.Register("Settings", require(Panels:WaitForChild("Settings")))

-- 4. Colonne centrale (bouton, compteur, menus, améliorations).
-- L'infobulle des améliorations va dans le calque Panels (au-dessus des stimuli).
CenterColumn.Build(layers.Main, layers.Panels, layers.Effects)

-- 5. Stimuli (tout ce qui apparaît à l'écran avec les améliorations)
StimulusManager.Init()

-- 6. Notifications du serveur : toasts + stimuli (bonus, océan)
ClientState.SetNotifyHandler(function(payload)
	Notifications.Handle(payload)
	StimulusManager.HandleNotify(payload)
end)
ClientState.RushChanged:Connect(function(rush)
	Background.SetRush(rush.Active == true)
end)

-- 7. Musique : seulement avec "Lofi Beats" (le réglage Musique est géré par le panneau Paramètres)
ClientState.FeaturesChanged:Connect(function()
	SoundManager.SetMusicAllowed(ClientState.HasFeature("Lofi"))
end)

-- 8. Au premier état reçu : on ouvre le cadeau du jour s'il est disponible
local firstState
firstState = ClientState.Changed:Connect(function(data)
	firstState:Disconnect()
	if ClientState.HasFeature("Daily") and data.Daily and data.Daily.Available then
		task.delay(1.5, function()
			if not PanelManager.IsOpen() then
				PanelManager.Open("Daily")
			end
		end)
	end
end)

-- 9. On prévient le serveur que l'interface est prête
Net.Event("ClientReady"):FireServer()
