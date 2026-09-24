--[[
	ClientState (ModuleScript)
	Emplacement : ReplicatedStorage > Client > ClientState

	Mémorise le dernier état envoyé par le serveur et prévient l'interface
	(signaux). Gère aussi la "prédiction" des clics : on affiche le gain
	tout de suite, sans attendre le serveur, pour une sensation instantanée.
	Le serveur reste l'autorité : dès que sa réponse arrive, l'affichage se
	recale sur la vraie valeur.

	Garde aussi en mémoire : les "Features" débloquées, la bourse, les
	trajectoires des logos DVD, le mode sombre (néon / thème sombre), et
	relaie les événements "Spawn" et "Notify" aux modules qui les écoutent.

	v3 : Game Passes possédés (Data.Passes), boost temporaire (Data.Boost,
	compte à rebours prédit localement), VIP, signal "Loaded" (premier état).
	v4 : classement en deux parties (ClientState.Leaderboard = top mondial,
	ClientState.ServerLeaderboard = joueurs du serveur en direct), son de
	clic choisi (Data.Settings.ClickSound), Dopamine hors-ligne (Data.Offline).
	Classement complet : ClientState.RebirthLeaderboard = top mondial des
	renaissances (payload.GlobalRebirths). Les anciens formats restent acceptés.
	Le mode sombre est la combinaison (OU) de plusieurs "sources" : le thème
	équipé (SetDarkMode), les stimuli comme le mode néon (SetDarkSource).
]]

local Players = game:GetService("Players")
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
ClientState.Leaderboard = {} -- top mondial : { { Rank, UserId, Name, Value } }
ClientState.LeaderboardChanged = Signal.new() -- (topMondial, classementServeur, topRenaissances)
-- Ajout v4 : classement du serveur en direct { { UserId, Name, Dopamine, Lifetime, Rebirths } } (trié)
ClientState.ServerLeaderboard = {}
-- Top mondial des renaissances : { { Rank, UserId, Name, Value (renaissances), Dopamine? } }
ClientState.RebirthLeaderboard = {}

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

-- Ajouts v3
ClientState.Loaded = Signal.new() -- () : premier état reçu (écran de chargement)
ClientState.IsLoaded = false

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

-- Sources du mode sombre ([nom] = true) : le mode est actif si l'une l'est
local darkSources: { [string]: boolean } = {}

-- Boost temporaire : fin prévue (horloge locale os.clock)
local boostMultiplier = 1
local boostEndsClock = 0

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
	if type(data.Settings.ClickSound) ~= "string" then
		data.Settings.ClickSound = "Default"
	end
	data.Stats = data.Stats or {}
	data.Achievements = data.Achievements or {}
	data.Quests = data.Quests or {}
	data.ClickSeq = data.ClickSeq or 0
	data.Passes = data.Passes or {}
	data.Themes = data.Themes or { Owned = { Classic = true }, Equipped = "Classic" }
	data.Themes.Owned = data.Themes.Owned or { Classic = true }
	data.Boost = data.Boost or { Multiplier = 1, Remaining = 0 }

	ClientState.Data = data
	lastUpdateClock = os.clock()
	-- Boost : on mémorise sa fin pour un compte à rebours fluide entre deux états
	local boost = data.Boost
	local remaining = tonumber(boost.Remaining) or 0
	boostMultiplier = tonumber(boost.Multiplier) or 1
	if boostMultiplier > 1 and remaining > 0 then
		local newEnd = os.clock() + remaining
		-- Petit filtre : on ignore les écarts < 1 s (arrondi du serveur)
		if math.abs(newEnd - boostEndsClock) > 1 then
			boostEndsClock = newEnd
		end
	else
		boostEndsClock = 0
	end
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
	if not ClientState.IsLoaded then
		ClientState.IsLoaded = true
		ClientState.Loaded:Fire()
	end
end

function ClientState.Init()
	Net.Event("StateUpdate").OnClientEvent:Connect(onState)

	Net.Event("EventUpdate").OnClientEvent:Connect(function(rush)
		ClientState.Rush = rush
		ClientState.RushChanged:Fire(rush)
	end)

	Net.Event("LeaderboardUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.Global ~= nil or payload.Server ~= nil or payload.GlobalRebirths ~= nil then
			-- Format v4 : { Global = {...}, GlobalRebirths = {...}, Server = {...} }
			-- (une partie absente = inchangée)
			if type(payload.Global) == "table" then
				ClientState.Leaderboard = payload.Global
			end
			if type(payload.GlobalRebirths) == "table" then
				ClientState.RebirthLeaderboard = payload.GlobalRebirths
			end
			if type(payload.Server) == "table" then
				ClientState.ServerLeaderboard = payload.Server
			end
		else
			-- Ancien format : un simple tableau (top mondial)
			ClientState.Leaderboard = payload
		end
		ClientState.LeaderboardChanged:Fire(
			ClientState.Leaderboard,
			ClientState.ServerLeaderboard,
			ClientState.RebirthLeaderboard
		)
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

-- Recalcule le mode sombre effectif (OU de toutes les sources)
local function applyDarkSources()
	local enabled = false
	for _, value in pairs(darkSources) do
		if value then
			enabled = true
			break
		end
	end
	if ClientState.DarkMode == enabled then
		return
	end
	ClientState.DarkMode = enabled
	ClientState.DarkModeChanged:Fire(enabled)
end

-- Active / coupe une source du mode sombre (ex. "Stimuli" pour le mode néon)
function ClientState.SetDarkSource(source: string, enabled: boolean)
	if enabled == true then
		darkSources[source] = true
	else
		darkSources[source] = nil
	end
	applyDarkSources()
end

-- Mode sombre "principal" (thème équipé, fond...). Les stimuli (mode néon)
-- passent par une autre source : un thème sombre reste sombre même quand le
-- mode néon s'arrête, et inversement.
function ClientState.SetDarkMode(enabled: boolean)
	ClientState.SetDarkSource("Main", enabled)
end

----------------------------------------------------------------------
-- Robux : passes, boost, VIP
----------------------------------------------------------------------

-- Vrai si le joueur possède le Game Pass `passId` (Id de Config.Monetization.GamePasses)
function ClientState.HasPass(passId: string): boolean
	local data = ClientState.Data
	return data ~= nil and type(data.Passes) == "table" and data.Passes[passId] == true
end

-- Vrai si le joueur est VIP
function ClientState.IsVIP(): boolean
	local data = ClientState.Data
	return data ~= nil and (data.IsVIP == true or ClientState.HasPass("VIP"))
end

-- Multiplicateur permanent des Game Passes possédés (x10, x2, VIP...)
function ClientState.GetPassMultiplier(): number
	local multiplier = 1
	for _, pass in ipairs(Config.Monetization.GamePasses) do
		if pass.Multiplier and ClientState.HasPass(pass.Id) then
			multiplier *= pass.Multiplier
		end
	end
	return multiplier
end

-- Boost temporaire actif : (multiplicateur, secondes restantes) ; (1, 0) sinon
function ClientState.GetBoost(): (number, number)
	if boostMultiplier <= 1 or boostEndsClock <= 0 then
		return 1, 0
	end
	local remaining = boostEndsClock - os.clock()
	if remaining <= 0 then
		return 1, 0
	end
	return boostMultiplier, remaining
end

----------------------------------------------------------------------
-- Classement du serveur (v4)
----------------------------------------------------------------------

-- Place du joueur local dans le classement du serveur : (rang ou nil, nombre de joueurs)
function ClientState.GetServerRank(): (number?, number)
	local list = ClientState.ServerLeaderboard
	if type(list) ~= "table" then
		return nil, 0
	end
	local localId = Players.LocalPlayer and Players.LocalPlayer.UserId
	for index, entry in ipairs(list) do
		if type(entry) == "table" and entry.UserId == localId then
			return index, #list
		end
	end
	return nil, #list
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

-- Valeur "confirmée" : état serveur + clics prédits, SANS l'extrapolation des
-- gains passifs (pour savoir si un achat sera accepté par le serveur)
function ClientState.GetConfirmedDopamine(): number
	local data = ClientState.Data
	if not data then
		return 0
	end
	local total = data.Dopamine or 0
	for _, prediction in ipairs(pending) do
		total += prediction.Amount
	end
	return total
end

-- Valeur affichée, lissée à chaque image (appelé UNE fois par image par la colonne centrale)
function ClientState.UpdateDisplay(dt: number): number
	local target = ClientState.GetTargetDopamine()
	local perSecond = (ClientState.Data and ClientState.Data.PerSecond) or 0
	if target < displayDopamine - perSecond * 0.6 - 1e-6 then
		displayDopamine = target -- vraie baisse (achat, détox) : on descend immédiatement
	elseif target <= displayDopamine then
		-- Petite baisse due au décalage entre ticks passifs et envois d'état :
		-- on garde la valeur affichée jusqu'à ce que la cible la rattrape
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
