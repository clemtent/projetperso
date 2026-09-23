--[[
	GameService (ModuleScript)
	Emplacement : ServerScriptService > Services > GameService

	Cœur du jeu, 100 % côté serveur :
	  - clics (avec limite de clics/seconde et combo calculé par le serveur) ;
	  - achats d'améliorations (le serveur vérifie le prix et l'argent) ;
	  - gains passifs (Dopamine/s) ;
	  - rebirth ;
	  - envoi régulier de l'état au client (StateUpdate) ;
	  - leaderstats (liste des joueurs en haut à droite).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local NumberFormatter = require(Shared.NumberFormatter)
local Net = require(Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local GameService = {}

local services -- toutes les autres services (rempli par Init)

-- Données "de session" (non sauvegardées) : [Player] = session
local sessions = {}

local VALID_SETTINGS = { Sound = true, Music = true, Effects = true }
local VALID_BUY_MODES = { x1 = true, x10 = true, max = true }

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	-- StringValue pour afficher "1.5M" au lieu d'un nombre illisible
	local dopamine = Instance.new("StringValue")
	dopamine.Name = Config.Game.CurrencyName
	dopamine.Value = "0"
	dopamine.Parent = folder

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = 0
	rebirths.Parent = folder

	folder.Parent = player
end

local function updateLeaderstats(player: Player, data)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local dopamine = folder:FindFirstChild(Config.Game.CurrencyName) :: StringValue?
	local rebirths = folder:FindFirstChild("Rebirths") :: IntValue?
	if dopamine then
		local text = NumberFormatter.Format(data.Dopamine)
		if dopamine.Value ~= text then
			dopamine.Value = text
		end
	end
	if rebirths and rebirths.Value ~= data.Rebirths then
		rebirths.Value = data.Rebirths
	end
end

----------------------------------------------------------------------
-- API utilisée par les autres services
----------------------------------------------------------------------

function GameService:Init(allServices)
	services = allServices
end

function GameService:IsReady(player: Player): boolean
	return sessions[player] ~= nil
end

function GameService:GetSession(player: Player)
	return sessions[player]
end

-- Calcule les statistiques actuelles du joueur (gain/clic, gain/s...)
function GameService:GetStats(player: Player)
	local data = services.DataService:GetData(player)
	return Formulas.ComputeStats(data, services.EventService:GetMultiplier())
end

-- Ajoute de la Dopamine (seule façon de gagner de l'argent dans le jeu)
-- countForQuests = false pour ne pas faire avancer les quêtes "Gagne X"
function GameService:AddDopamine(player: Player, amount: number, countForQuests: boolean?)
	local data = services.DataService:GetData(player)
	if not data or not isValidNumber(amount) or amount <= 0 then
		return
	end
	local maxValue = Config.Game.MaxDopamine
	data.Dopamine = math.min(maxValue, data.Dopamine + amount)
	data.Stats.LifetimeDopamine = math.min(maxValue, data.Stats.LifetimeDopamine + amount)
	if countForQuests ~= false then
		services.QuestService:Progress(player, "Earn", amount)
	end
	self:MarkDirty(player)
end

function GameService:MarkDirty(player: Player)
	local session = sessions[player]
	if session then
		session.Dirty = true
	end
end

function GameService:MarkAllDirty()
	for _, session in pairs(sessions) do
		session.Dirty = true
	end
end

-- Envoie une notification à un joueur
-- payload = { Type = "Info" | "Error" | "Achievement" | "Quest" | "Bonus" | "Jackpot" | ..., Text = "...", ... }
function GameService:Notify(player: Player, payload)
	Net.Event("Notify"):FireClient(player, payload)
end

-- Notifie tous les joueurs (sauf `except`, optionnel)
function GameService:NotifyAll(payload, except: Player?)
	local remote = Net.Event("Notify")
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= except then
			remote:FireClient(other, payload)
		end
	end
end

-- Construit l'état envoyé au client (tout ce que l'interface doit afficher)
function GameService:BuildState(player: Player)
	local data = services.DataService:GetData(player)
	local session = sessions[player]
	local stats = self:GetStats(player)

	return {
		Dopamine = data.Dopamine,
		Rebirths = data.Rebirths,
		Upgrades = data.Upgrades,
		Achievements = data.Achievements,
		Quests = data.Quests,
		Stats = data.Stats,
		Settings = data.Settings,

		ClickValue = stats.ClickValue,
		PerSecond = stats.PerSecond,
		GlobalMultiplier = stats.GlobalMultiplier,
		UpgradeMultiplier = stats.UpgradeMultiplier,
		RebirthMultiplier = stats.RebirthMultiplier,
		AchievementMultiplier = stats.AchievementMultiplier,
		EventMultiplier = stats.EventMultiplier,

		RebirthCost = Formulas.GetRebirthCost(data.Rebirths),
		NextRebirthMultiplier = Formulas.GetRebirthMultiplier(data.Rebirths + 1),

		Daily = services.DailyRewardService:GetInfo(player, stats),

		-- Nombre de clics reçus par le serveur (sert au client pour sa prédiction)
		ClickSeq = session.ClickSeq,
	}
end

function GameService:SendState(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	session.Dirty = false
	Net.Event("StateUpdate"):FireClient(player, self:BuildState(player))
	updateLeaderstats(player, services.DataService:GetData(player))
end

-- Envoie tout ce dont le client a besoin (état, logo DVD, événements, classement)
function GameService:SendFullSync(player: Player)
	if not sessions[player] then
		return
	end
	self:SendState(player)
	services.DVDService:SendSetup(player)
	services.EventService:SendState(player)
	services.LeaderboardService:SendTo(player)
end

----------------------------------------------------------------------
-- Cycle de vie du joueur (appelé par Main)
----------------------------------------------------------------------

function GameService:PlayerReady(player: Player, _data)
	local now = os.clock()
	sessions[player] = {
		ClickSeq = 0,
		Combo = 0, -- jauge de combo (0-100)
		ComboMaxed = false, -- déjà compté comme "combo max" ?
		LastClick = now,
		Tokens = Config.Game.MaxClicksPerSecond, -- anti-autoclick (seau de jetons)
		LastRefill = now,
		Dirty = true,
	}
	createLeaderstats(player)
end

function GameService:PlayerRemoving(player: Player)
	sessions[player] = nil
end

----------------------------------------------------------------------
-- Actions des joueurs (toujours validées ici)
----------------------------------------------------------------------

local function onClick(player: Player)
	local session = sessions[player]
	local data = services.DataService:GetData(player)
	if not session or not data then
		return
	end

	-- Compté même si refusé : le client s'en sert pour corriger sa prédiction
	session.ClickSeq += 1
	session.Dirty = true

	-- Seau de jetons : on regagne MaxClicksPerSecond jetons par seconde
	local now = os.clock()
	local maxClicks = Config.Game.MaxClicksPerSecond
	session.Tokens = math.min(maxClicks, session.Tokens + (now - session.LastRefill) * maxClicks)
	session.LastRefill = now
	if session.Tokens < 1 then
		return -- trop de clics : ignoré (autoclicker / exploit)
	end
	session.Tokens -= 1

	data.Stats.TotalClicks += 1

	-- Combo calculé par le serveur (le client ne fait que l'afficher)
	session.Combo = Formulas.StepCombo(session.Combo, now - session.LastClick)
	session.LastClick = now
	if session.Combo >= 100 and not session.ComboMaxed then
		session.ComboMaxed = true
		data.Stats.CombosMaxed += 1
		services.QuestService:Progress(player, "Combo", 1)
	elseif session.Combo < 50 then
		session.ComboMaxed = false
	end

	local stats = GameService:GetStats(player)
	local gain = stats.ClickValue * Formulas.GetComboMultiplier(session.Combo)
	GameService:AddDopamine(player, gain, true)
	services.QuestService:Progress(player, "Clicks", 1)
end

local function onBuyUpgrade(player: Player, upgradeId: any, mode: any)
	if not RateLimiter.Check(player, "Buy", 0.05) then
		return false, "Doucement !"
	end
	local data = services.DataService:GetData(player)
	if not data or not sessions[player] then
		return false, "Chargement en cours..."
	end
	if type(upgradeId) ~= "string" or type(mode) ~= "string" or not VALID_BUY_MODES[mode] then
		return false, "Requête invalide"
	end
	local upgrade = Config.UpgradesById[upgradeId]
	if not upgrade then
		return false, "Amélioration inconnue"
	end

	local level = data.Upgrades[upgradeId] or 0
	local amount, cost = Formulas.GetPurchase(upgrade, level, mode, data.Dopamine)
	if amount <= 0 then
		return false, "Niveau maximum atteint"
	end
	if data.Dopamine < cost then
		return false, "Pas assez de " .. Config.Game.CurrencyName
	end

	data.Dopamine -= cost
	data.Upgrades[upgradeId] = level + amount
	data.Stats.UpgradesBought += amount
	services.QuestService:Progress(player, "Buy", amount)

	GameService:SendState(player)
	return true, string.format("%s %s niveau %d", upgrade.Icon, upgrade.Name, level + amount)
end

local function onRebirth(player: Player)
	if not RateLimiter.Check(player, "Rebirth", 1) then
		return false, "Doucement !"
	end
	local data = services.DataService:GetData(player)
	local session = sessions[player]
	if not data or not session then
		return false, "Chargement en cours..."
	end

	local cost = Formulas.GetRebirthCost(data.Rebirths)
	if data.Dopamine < cost then
		return false, "Il te faut " .. NumberFormatter.Format(cost) .. " " .. Config.Game.CurrencyName
	end

	-- On remet la progression à zéro... contre un multiplicateur permanent
	data.Dopamine = 0
	data.Upgrades = {}
	data.Rebirths += 1
	session.Combo = 0

	GameService:NotifyAll({
		Type = "Info",
		Text = "♻️ " .. player.DisplayName .. " vient de faire un REBIRTH (x" .. data.Rebirths .. ") !",
	}, player)
	GameService:SendState(player)
	local multiplier = NumberFormatter.Multiplier(Formulas.GetRebirthMultiplier(data.Rebirths))
	return true, "Rebirth réussi ! Gains permanents " .. multiplier
end

local function onSetSetting(player: Player, name: any, value: any)
	if not RateLimiter.Check(player, "Setting", 0.2) then
		return false
	end
	local data = services.DataService:GetData(player)
	if not data or type(name) ~= "string" or not VALID_SETTINGS[name] or type(value) ~= "boolean" then
		return false
	end
	data.Settings[name] = value
	GameService:MarkDirty(player)
	return true
end

----------------------------------------------------------------------
-- Démarrage : branchements des remotes + boucles
----------------------------------------------------------------------

function GameService:Start()
	Net.Event("Click").OnServerEvent:Connect(onClick)
	Net.Event("ClientReady").OnServerEvent:Connect(function(player)
		if RateLimiter.Check(player, "ClientReady", 2) then
			self:SendFullSync(player)
		end
	end)
	Net.Function("BuyUpgrade").OnServerInvoke = onBuyUpgrade
	Net.Function("Rebirth").OnServerInvoke = onRebirth
	Net.Function("SetSetting").OnServerInvoke = onSetSetting

	-- Gains passifs
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Game.PassiveTickRate)
			local now = os.clock()
			local elapsed = now - last
			last = now
			for player in pairs(sessions) do
				local stats = self:GetStats(player)
				if stats.PerSecond > 0 then
					self:AddDopamine(player, stats.PerSecond * elapsed, true)
				end
			end
		end
	end)

	-- Synchronisation vers les clients (seulement si quelque chose a changé)
	task.spawn(function()
		while true do
			task.wait(Config.Game.SyncRate)
			for player, session in pairs(sessions) do
				if session.Dirty then
					services.AchievementService:Check(player)
					self:SendState(player)
				end
			end
		end
	end)

	-- Petit rappel dans la console du serveur
	print(string.format("[Dopamine Clicker] Serveur prêt (%d joueur(s))", #Players:GetPlayers()))
end

return GameService
