--[[
	ClientState (ModuleScript)
	Emplacement : ReplicatedStorage > Client > ClientState

	Mémorise le dernier état envoyé par le serveur et prévient l'interface
	(signaux). Gère aussi la "prédiction" des clics : on affiche le gain
	tout de suite, sans attendre le serveur, pour une sensation instantanée.
	Le serveur reste l'autorité : dès que sa réponse arrive, l'affichage se
	recale sur la vraie valeur.

	Garde aussi en mémoire : les "Features" débloquées, la bourse, les
	trajectoires des logos DVD, le mode sombre (néon), et relaie les
	événements "Spawn" et "Notify" aux modules qui les écoutent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)

local ClientState = {}

ClientState.Data = nil :: any -- dernier état serveur (nil tant que pas chargé)
ClientState.Changed = Signal.new() -- (data)
ClientState.Rush = { Active = false, EndsAt = 0, Name = "", Multiplier = 1 }
ClientState.RushChanged = Signal.new() -- (rush)
ClientState.Leaderboard = {}
ClientState.LeaderboardChanged = Signal.new() -- (top)

-- Ajouts v2
ClientState.FeaturesChanged = Signal.new() -- (features) : l'ensemble des Features a changé
ClientState.SpawnReceived = Signal.new() -- (info) : chaque événement "Spawn"
ClientState.Stock = { Symbol = Config.Stocks.Symbol, Price = Config.Stocks.StartPrice, History = {} }
ClientState.StockChanged = Signal.new() -- (stock)
ClientState.DVDSetup = { Logos = {} }
ClientState.DVDSetupChanged = Signal.new() -- (setup)
ClientState.DarkMode = false
ClientState.DarkModeChanged = Signal.new() -- (enabled)
ClientState.NotifyReceived = Signal.new() -- (payload) : chaque "Notify" (après le traitement intégré)

-- Prédiction des clics
local clickSeq = 0
local pending = {} -- { { Seq = number, Amount = number } }
local lastUpdateClock = os.clock()
local displayDopamine = 0

-- Combo local (même formule que le serveur, juste pour l'affichage)
local comboMeter = 0
local lastComboClick = 0
local lastLocalClick = 0

-- Features connues (pour détecter les changements)
local knownFeatures: { [string]: boolean }? = nil

-- Traitement "intégré" des Notify (branché par ClientMain)
local notifyHandler: ((payload: any) -> ())? = nil

local function sameSet(a: { [string]: boolean }, b: { [string]: boolean }): boolean
	for key, value in pairs(a) do
		if value and not b[key] then
			return false
		end
	end
	for key, value in pairs(b) do
		if value and not a[key] then
			return false
		end
	end
	return true
end

local function onState(data)
	if type(data) ~= "table" then
		return
	end
	-- Valeurs par défaut (au cas où le serveur n'envoie pas encore un champ)
	data.Features = data.Features or {}
	data.Upgrades = data.Upgrades or {}
	data.Settings = data.Settings or { Sound = true, Music = true, Effects = true }
	data.Stats = data.Stats or {}
	data.Achievements = data.Achievements or {}
	data.Quests = data.Quests or {}
	data.ClickSeq = data.ClickSeq or 0

	ClientState.Data = data
	lastUpdateClock = os.clock()
	-- On oublie les prédictions que le serveur a déjà traitées
	while pending[1] and pending[1].Seq <= data.ClickSeq do
		table.remove(pending, 1)
	end
	if not data.ComboEnabled then
		comboMeter = 0
	end

	local features = data.Features
	local changed = knownFeatures == nil or not sameSet(knownFeatures :: { [string]: boolean }, features)
	knownFeatures = table.clone(features)

	ClientState.Changed:Fire(data)
	if changed then
		ClientState.FeaturesChanged:Fire(features)
	end
end

function ClientState.Init()
	Net.Event("StateUpdate").OnClientEvent:Connect(onState)

	Net.Event("EventUpdate").OnClientEvent:Connect(function(rush)
		ClientState.Rush = rush
		ClientState.RushChanged:Fire(rush)
	end)

	Net.Event("LeaderboardUpdate").OnClientEvent:Connect(function(top)
		ClientState.Leaderboard = top or {}
		ClientState.LeaderboardChanged:Fire(ClientState.Leaderboard)
	end)

	Net.Event("StockUpdate").OnClientEvent:Connect(function(stock)
		if type(stock) ~= "table" then
			return
		end
		stock.History = stock.History or {}
		ClientState.Stock = stock
		ClientState.StockChanged:Fire(stock)
	end)

	Net.Event("DVDSetup").OnClientEvent:Connect(function(setup)
		if type(setup) ~= "table" then
			return
		end
		setup.Logos = setup.Logos or {}
		ClientState.DVDSetup = setup
		ClientState.DVDSetupChanged:Fire(setup)
	end)

	Net.Event("Spawn").OnClientEvent:Connect(function(info)
		if type(info) == "table" then
			ClientState.SpawnReceived:Fire(info)
		end
	end)

	Net.Event("Notify").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local handler = notifyHandler
		if handler then
			local ok, err = pcall(handler, payload)
			if not ok then
				warn("[ClientState] Erreur dans le traitement d'une notification :", err)
			end
		end
		ClientState.NotifyReceived:Fire(payload)
	end)
end

-- Branche le traitement "intégré" des notifications (toasts, stimuli...)
function ClientState.SetNotifyHandler(handler: (payload: any) -> ())
	notifyHandler = handler
end

-- Vrai si la Feature est débloquée (faux avant le premier état)
function ClientState.HasFeature(name: string): boolean
	local data = ClientState.Data
	return data ~= nil and data.Features ~= nil and data.Features[name] == true
end

-- Niveau d'une amélioration (0 avant le premier état)
function ClientState.GetLevel(upgradeId: string): number
	local data = ClientState.Data
	if not data or not data.Upgrades then
		return 0
	end
	return data.Upgrades[upgradeId] or 0
end

-- Mode sombre (activé par le mode néon)
function ClientState.SetDarkMode(enabled: boolean)
	enabled = enabled == true
	if ClientState.DarkMode == enabled then
		return
	end
	ClientState.DarkMode = enabled
	ClientState.DarkModeChanged:Fire(enabled)
end

-- Jauge de combo actuelle (avec la perte depuis le dernier clic)
function ClientState.GetComboMeter(): number
	local data = ClientState.Data
	if not data or not data.ComboEnabled then
		return 0
	end
	local elapsed = os.clock() - lastComboClick
	return math.max(0, comboMeter - Config.Combo.DecayPerSecond * elapsed)
end

function ClientState.GetComboMultiplier(): number
	return Formulas.GetComboMultiplier(ClientState.GetComboMeter())
end

-- Appelé à chaque clic sur le gros bouton. Renvoie le gain prédit (ou nil si
-- le clic est trop rapide, comme le serveur le refuserait).
function ClientState.Click(): number?
	local data = ClientState.Data
	if not data then
		return nil
	end
	local now = os.clock()
	-- Même limite que le serveur : inutile d'envoyer des clics qui seront refusés
	if now - lastLocalClick < 1 / Config.Game.MaxClicksPerSecond then
		return nil
	end
	lastLocalClick = now

	local gain = data.ClickValue or 0
	if data.ComboEnabled then
		comboMeter = Formulas.StepCombo(comboMeter, now - lastComboClick)
		lastComboClick = now
		gain *= Formulas.GetComboMultiplier(comboMeter)
	else
		comboMeter = 0
	end

	clickSeq += 1
	table.insert(pending, { Seq = clickSeq, Amount = gain })
	Net.Event("Click"):FireServer()
	return gain
end

-- Valeur "cible" : état serveur + clics prédits + gains passifs depuis la dernière mise à jour
function ClientState.GetTargetDopamine(): number
	local data = ClientState.Data
	if not data then
		return 0
	end
	local total = data.Dopamine or 0
	for _, prediction in ipairs(pending) do
		total += prediction.Amount
	end
	local elapsed = math.min(os.clock() - lastUpdateClock, 0.5)
	return total + (data.PerSecond or 0) * elapsed
end

-- Valeur affichée, lissée à chaque image (appelé UNE fois par image par la colonne centrale)
function ClientState.UpdateDisplay(dt: number): number
	local target = ClientState.GetTargetDopamine()
	if target < displayDopamine then
		displayDopamine = target -- achat : on descend immédiatement
	else
		displayDopamine += (target - displayDopamine) * (1 - math.exp(-14 * dt))
		if target - displayDopamine < 0.01 then
			displayDopamine = target
		end
	end
	return displayDopamine
end

function ClientState.GetDisplayDopamine(): number
	return displayDopamine
end

return ClientState
