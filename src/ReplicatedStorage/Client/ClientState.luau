--[[
	ClientState (ModuleScript)
	Emplacement : ReplicatedStorage > Client > ClientState

	Mémorise le dernier état envoyé par le serveur et prévient l'interface
	(signal Changed). Gère aussi la "prédiction" des clics : on affiche le
	gain tout de suite, sans attendre le serveur, pour une sensation
	instantanée. Le serveur reste l'autorité : dès que sa réponse arrive,
	l'affichage se recale sur la vraie valeur.
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

-- Prédiction des clics
local clickSeq = 0
local pending = {} -- { { Seq = number, Amount = number } }
local lastUpdateClock = os.clock()
local displayDopamine = 0

-- Combo local (même formule que le serveur, juste pour l'affichage)
local comboMeter = 0
local lastComboClick = 0
local lastLocalClick = 0

function ClientState.Init()
	Net.Event("StateUpdate").OnClientEvent:Connect(function(data)
		ClientState.Data = data
		lastUpdateClock = os.clock()
		-- On oublie les prédictions que le serveur a déjà traitées
		while pending[1] and pending[1].Seq <= data.ClickSeq do
			table.remove(pending, 1)
		end
		ClientState.Changed:Fire(data)
	end)

	Net.Event("EventUpdate").OnClientEvent:Connect(function(rush)
		ClientState.Rush = rush
		ClientState.RushChanged:Fire(rush)
	end)

	Net.Event("LeaderboardUpdate").OnClientEvent:Connect(function(top)
		ClientState.Leaderboard = top
		ClientState.LeaderboardChanged:Fire(top)
	end)
end

-- Jauge de combo actuelle (avec la perte depuis le dernier clic)
function ClientState.GetComboMeter(): number
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

	comboMeter = Formulas.StepCombo(comboMeter, now - lastComboClick)
	lastComboClick = now

	local gain = data.ClickValue * Formulas.GetComboMultiplier(comboMeter)
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
	local total = data.Dopamine
	for _, prediction in ipairs(pending) do
		total += prediction.Amount
	end
	local elapsed = math.min(os.clock() - lastUpdateClock, 0.5)
	return total + data.PerSecond * elapsed
end

-- Valeur affichée, lissée à chaque image (appelé par le HUD)
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
