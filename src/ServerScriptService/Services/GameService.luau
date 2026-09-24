--[[
	GameService (ModuleScript)
	Emplacement : ServerScriptService > Services > GameService

	Cœur du jeu, 100 % côté serveur :
	  - clics (limite de clics/seconde, combo calculé par le serveur si la
	    Feature "Combo" est débloquée) ;
	  - achats d'améliorations (le serveur vérifie le prix et l'argent) et
	    "Aller à l'océan" (détox = rebirth) ;
	  - gains passifs (voir le pipeline ci-dessous) ;
	  - temps d'écran (par session, par jour UTC, total) ;
	  - envoi régulier de l'état au client (StateUpdate) ;
	  - leaderstats (liste des joueurs en haut à droite).

	Pipeline du tick passif (toutes les Config.Game.PassiveTickRate secondes,
	pour chaque joueur chargé) :
	  1. Dopamine/s : PerSecond x temps écoulé -> AddDopamine ;
	  2. Rebonds DVD : DVDService:CollectBounces renvoie le nombre de rebonds
	     depuis le dernier tick (tous les logos, 2 axes, plafonné) ;
	     gain = rebonds x BounceValue, Stats.Bounces, quête "Bounces" ;
	  3. Temps de jeu : Stats.PlaySeconds, temps de la session et
	     ScreenTime["jour UTC"] (on ne garde que Config.ScreenTime.DaysKept jours) ;
	  4. Coffres : LootService:Charge remplit la jauge du coffre mystère ;
	  5. Auto-clic (Game Pass) : AutoClicksPerSecond clics/s, même gain qu'un
	     clic sans combo, comptés dans Stats.TotalClicks.
	Les stats (Rush et bonus Robux compris) sont recalculées une seule fois par
	joueur et par tick. Bonus Robux = produit des multiplicateurs des Game Passes
	possédés x boost actif (MonetizationService).
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
local SECONDS_PER_DAY = 86400

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function currentDay(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

local function createLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
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

-- Temps d'écran : supprime les jours trop anciens (et les clés invalides)
local function pruneScreenTime(data)
	local screenTime = data.ScreenTime
	local oldest = currentDay() - Config.ScreenTime.DaysKept + 1
	for key, value in pairs(screenTime) do
		local day = tonumber(key)
		if type(key) ~= "string" or not day or day < oldest or not isValidNumber(value) then
			screenTime[key] = nil
		end
	end
end

-- Corrige une sauvegarde abîmée ou devenue incohérente avec la config
-- (niveau max baissé, objet cosmétique supprimé...)
local function sanitizeData(data)
	for upgradeId, level in pairs(data.Upgrades) do
		local upgrade = Config.UpgradesById[upgradeId]
		if not upgrade or not isValidNumber(level) or level <= 0 or upgrade.Effect == "Detox" then
			data.Upgrades[upgradeId] = nil
		elseif upgrade.MaxLevel and level > upgrade.MaxLevel then
			data.Upgrades[upgradeId] = upgrade.MaxLevel
		else
			data.Upgrades[upgradeId] = math.floor(level)
		end
	end

	local cosmetics = data.Cosmetics
	for _, slot in ipairs({ "Hat", "Skin" }) do
		local id = cosmetics.Equipped[slot]
		local cosmetic = type(id) == "string" and Config.CosmeticsById[id]
		if not cosmetic or cosmetic.Slot ~= slot or not cosmetics.Owned[id] then
			cosmetics.Equipped[slot] = ""
		end
	end

	local chests = data.Chests
	chests.Stored = math.clamp(math.floor(chests.Stored), 0, Config.LootBox.MaxStored)
	chests.Progress = math.clamp(chests.Progress, 0, 1)

	if not isValidNumber(data.Dopamine) or data.Dopamine < 0 then
		data.Dopamine = 0
	end
	if not isValidNumber(data.Stock.Shares) or data.Stock.Shares < 0 then
		data.Stock.Shares = 0
		data.Stock.CostBasis = 0
	end

	pruneScreenTime(data)
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

-- Le joueur possède-t-il cette Feature (débloquée par une amélioration) ?
function GameService:HasFeature(player: Player, feature: string): boolean
	local data = services.DataService:GetData(player)
	return data ~= nil and Formulas.HasFeature(data, feature)
end

-- Calcule les statistiques actuelles du joueur (gain/clic, gain/s...)
function GameService:GetStats(player: Player)
	local data = services.DataService:GetData(player)
	return Formulas.ComputeStats(
		data,
		services.EventService:GetMultiplier(),
		services.MonetizationService:GetBonusMultiplier(player)
	)
end

-- Ajoute de la Dopamine (façon normale de gagner de l'argent dans le jeu)
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
-- payload = { Type = "Info" | "Error" | "Achievement" | "Quest" | "Bonus" | "Jackpot" | "Rush" | "Unlock" | "Detox" | "Purchase", ... }
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

-- Temps d'écran envoyé au client
function GameService:GetScreenTime(player: Player)
	local data = services.DataService:GetData(player)
	local session = sessions[player]
	local today = currentDay()
	local days = {}
	for offset = Config.ScreenTime.DaysKept - 1, 0, -1 do
		table.insert(days, data.ScreenTime[tostring(today - offset)] or 0)
	end
	return {
		Session = session and session.SessionSeconds or 0,
		Today = data.ScreenTime[tostring(today)] or 0,
		Total = data.Stats.PlaySeconds,
		Days = days, -- du plus ancien à aujourd'hui
	}
end

-- Construit l'état envoyé au client (tout ce que l'interface doit afficher)
function GameService:BuildState(player: Player)
	local data = services.DataService:GetData(player)
	local session = sessions[player]
	local stats = self:GetStats(player)
	local monetization = services.MonetizationService
	local boostMultiplier, boostRemaining = monetization:GetBoost(data)

	return {
		Dopamine = data.Dopamine,
		Rebirths = data.Rebirths,
		Upgrades = data.Upgrades,
		Features = Formulas.GetFeatures(data),
		Achievements = data.Achievements,
		Quests = data.Quests,
		Stats = data.Stats,
		Settings = data.Settings,

		ClickValue = stats.ClickValue,
		PerSecond = stats.PerSecond,
		BounceValue = stats.BounceValue,
		DVDCount = stats.DVDCount,
		GlobalMultiplier = stats.GlobalMultiplier,
		ClickMultiplier = stats.ClickMultiplier,
		UpgradeMultiplier = stats.UpgradeMultiplier,
		RebirthMultiplier = stats.RebirthMultiplier,
		AchievementMultiplier = stats.AchievementMultiplier,
		CosmeticMultiplier = stats.CosmeticMultiplier,
		EventMultiplier = stats.EventMultiplier,
		BonusMultiplier = stats.BonusMultiplier, -- Game Passes x boost actif
		ComboEnabled = Formulas.HasFeature(data, "Combo"),

		RebirthCost = Formulas.GetRebirthCost(data.Rebirths),
		NextRebirthMultiplier = Formulas.GetRebirthMultiplier(data.Rebirths + 1),

		Daily = services.DailyRewardService:GetInfo(player, stats),
		Stock = { Shares = data.Stock.Shares, CostBasis = data.Stock.CostBasis },
		Chests = {
			Stored = data.Chests.Stored,
			Progress = data.Chests.Progress,
			Max = Config.LootBox.MaxStored,
		},
		Cosmetics = data.Cosmetics,
		ScreenTime = self:GetScreenTime(player),

		-- Thèmes et boutique Robux
		Themes = services.ThemeService:GetState(player), -- { Owned = { [id] = true }, Equipped = id }
		Passes = monetization:GetOwnedPasses(player), -- { [passId] = true }
		Boost = { Multiplier = boostMultiplier, Remaining = math.max(0, math.floor(boostRemaining)) },
		CasinoEnabled = monetization:IsCasinoEnabled(),
		IsVIP = monetization:IsVIP(player),

		-- Nombre de clics reçus par le serveur (sert au client pour sa prédiction)
		ClickSeq = session and session.ClickSeq or 0,
	}
end

function GameService:SendState(player: Player)
	local session = sessions[player]
	local data = services.DataService:GetData(player)
	if not session or not data then
		return
	end
	session.Dirty = false
	Net.Event("StateUpdate"):FireClient(player, self:BuildState(player))
	updateLeaderstats(player, data)
end

-- Envoie tout ce dont le client a besoin (état, logos DVD, Rush, classement, bourse)
function GameService:SendFullSync(player: Player)
	if not sessions[player] then
		return
	end
	self:SendState(player)
	services.DVDService:SendSetup(player)
	services.EventService:SendState(player)
	services.LeaderboardService:SendTo(player)
	services.StockService:SendTo(player)
end

-- Remet le combo à zéro (détox, reset...)
function GameService:ResetCombo(player: Player)
	local session = sessions[player]
	if session then
		session.Combo = 0
		session.ComboMaxed = false
	end
end

-- "Aller à l'océan" : remet la progression à zéro contre un multiplicateur
-- permanent. On garde : succès, stats, cosmétiques, cadeau, réglages,
-- coffres, temps d'écran, quêtes et les améliorations "Permanent".
function GameService:Detox(player: Player)
	local data = services.DataService:GetData(player)
	if not data or not sessions[player] then
		return
	end

	local kept = {}
	for upgradeId, level in pairs(data.Upgrades) do
		local upgrade = Config.UpgradesById[upgradeId]
		if upgrade and upgrade.Permanent then
			kept[upgradeId] = level
		end
	end

	data.Dopamine = 0
	data.Upgrades = kept
	data.Stock.Shares = 0
	data.Stock.CostBasis = 0
	data.Rebirths += 1
	self:ResetCombo(player)

	services.DVDService:Reset(player)
	services.EventService:ClearSpawns(player)
	-- Nouvelles quêtes adaptées à la production (redevenue petite) après la détox
	services.QuestService:Regenerate(player)

	local multiplier = Formulas.GetRebirthMultiplier(data.Rebirths)
	self:Notify(player, {
		Type = "Detox",
		Rebirths = data.Rebirths,
		Multiplier = multiplier,
	})
	self:NotifyAll({
		Type = "Info",
		Text = "🌊 " .. player.DisplayName .. " est allé(e) à l'océan (x" .. data.Rebirths .. ")",
	}, player)
	self:SendState(player)
end

-- Appelé après un changement d'améliorations fait "à la main" (commandes de test)
function GameService:RefreshAfterUpgradeChange(player: Player)
	services.DVDService:SyncLogos(player)
	self:SendState(player)
end

----------------------------------------------------------------------
-- Cycle de vie du joueur (appelé par Main)
----------------------------------------------------------------------

function GameService:PlayerReady(player: Player, data)
	local now = os.clock()
	sessions[player] = {
		ClickSeq = 0,
		Combo = 0, -- jauge de combo (0-100)
		ComboMaxed = false, -- déjà compté comme "combo max" ?
		LastClick = now,
		Tokens = Config.Game.MaxClicksPerSecond, -- anti-autoclick (seau de jetons)
		LastRefill = now,
		SessionSeconds = 0, -- temps de jeu de cette session
		Dirty = true,
	}
	sanitizeData(data)
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

	-- Combo calculé par le serveur (le client ne fait que l'afficher),
	-- seulement si l'amélioration "Combo" est achetée
	local comboMultiplier = 1
	if Formulas.HasFeature(data, "Combo") then
		session.Combo = Formulas.StepCombo(session.Combo, now - session.LastClick)
		if session.Combo >= 100 and not session.ComboMaxed then
			session.ComboMaxed = true
			data.Stats.CombosMaxed += 1
			services.QuestService:Progress(player, "Combo", 1)
		elseif session.Combo < 50 then
			session.ComboMaxed = false
		end
		comboMultiplier = Formulas.GetComboMultiplier(session.Combo)
	else
		session.Combo = 0
		session.ComboMaxed = false
	end
	session.LastClick = now

	local stats = GameService:GetStats(player)
	GameService:AddDopamine(player, stats.ClickValue * comboMultiplier, true)
	services.QuestService:Progress(player, "Clicks", 1)
end

local function onBuyUpgrade(player: Player, upgradeId: any)
	if not RateLimiter.Check(player, "Buy", 0.05) then
		return false, "Doucement !"
	end
	local data = services.DataService:GetData(player)
	if not data or not sessions[player] then
		return false, "Chargement en cours..."
	end
	if type(upgradeId) ~= "string" or #upgradeId > 64 then
		return false, "Requête invalide"
	end
	local upgrade = Config.UpgradesById[upgradeId]
	if not upgrade then
		return false, "Amélioration inconnue"
	end

	local level = data.Upgrades[upgradeId] or 0
	if Formulas.IsMaxed(upgrade, level) then
		return false, "Niveau maximum atteint"
	end
	local cost = Formulas.GetUpgradeCost(upgrade, level, data.Rebirths)
	if not isValidNumber(cost) or data.Dopamine < cost then
		return false, "Pas assez de " .. Config.Game.CurrencyName
	end

	-- "Aller à l'océan" : la détox
	if upgrade.Effect == "Detox" then
		if not RateLimiter.Check(player, "Detox", 2) then
			return false, "Doucement !"
		end
		GameService:Detox(player)
		local multiplier = NumberFormatter.Multiplier(Formulas.GetRebirthMultiplier(data.Rebirths))
		return true, "🌊 Respire... Gains permanents " .. multiplier
	end

	data.Dopamine -= cost
	data.Upgrades[upgradeId] = level + 1
	data.Stats.UpgradesBought += 1
	services.QuestService:Progress(player, "Buy", 1)

	if upgrade.Feature and level == 0 then
		GameService:Notify(player, {
			Type = "Unlock",
			Feature = upgrade.Feature,
			UpgradeId = upgrade.Id,
			Text = "✨ Nouveau : " .. upgrade.Icon .. " " .. upgrade.Name .. " !",
		})
		if upgrade.Feature == "Quests" then
			-- Les quêtes deviennent visibles : on en propose des toutes neuves, à l'échelle
			services.QuestService:Regenerate(player)
		end
	end

	services.DVDService:SyncLogos(player)
	GameService:SendState(player)
	return true, string.format("%s %s niveau %d", upgrade.Icon, upgrade.Name, level + 1)
end

local function onSetSetting(player: Player, name: any, value: any)
	if type(name) ~= "string" or not VALID_SETTINGS[name] or type(value) ~= "boolean" then
		return false
	end
	-- Une limite par réglage : couper le son puis les effets rapidement reste possible
	if not RateLimiter.Check(player, "Setting" .. name, 0.2) then
		return false
	end
	local data = services.DataService:GetData(player)
	if not data then
		return false
	end
	data.Settings[name] = value
	GameService:MarkDirty(player)
	return true
end

----------------------------------------------------------------------
-- Tick passif (voir le pipeline en haut du fichier)
----------------------------------------------------------------------

local function passiveTick(player: Player, session, elapsed: number)
	local data = services.DataService:GetData(player)
	if not data then
		return
	end
	local stats = GameService:GetStats(player)

	-- 1. Dopamine par seconde
	if stats.PerSecond > 0 then
		GameService:AddDopamine(player, stats.PerSecond * elapsed, true)
	end

	-- 2. Rebonds des logos DVD
	local bounces = services.DVDService:CollectBounces(player, workspace:GetServerTimeNow())
	if bounces > 0 then
		data.Stats.Bounces += bounces
		GameService:AddDopamine(player, stats.BounceValue * bounces, true)
		services.QuestService:Progress(player, "Bounces", bounces)
	end

	-- 3. Temps de jeu / temps d'écran
	local before = math.floor(session.SessionSeconds)
	session.SessionSeconds += elapsed
	data.Stats.PlaySeconds += elapsed
	local key = tostring(currentDay())
	local screenTime = data.ScreenTime
	if screenTime[key] == nil then
		screenTime[key] = 0
		pruneScreenTime(data) -- nouveau jour : on oublie le plus ancien
	end
	screenTime[key] += elapsed
	if math.floor(session.SessionSeconds) ~= before then
		session.Dirty = true -- au moins 1 envoi par seconde pour le temps d'écran
	end

	-- 4. Coffre mystère
	services.LootService:Charge(player, data, elapsed)

	-- 5. Auto-clic (Game Pass) : comme un clic normal, sans combo
	local autoClicks = services.MonetizationService:TakeAutoClicks(player, elapsed)
	if autoClicks > 0 then
		data.Stats.TotalClicks += autoClicks
		GameService:AddDopamine(player, stats.ClickValue * autoClicks, true)
	end
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
	Net.Function("SetSetting").OnServerInvoke = onSetSetting

	-- Gains passifs
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Game.PassiveTickRate)
			local now = os.clock()
			-- plafond : évite un énorme rattrapage après un gel du serveur
			local elapsed = math.min(now - last, 5)
			last = now
			for player, session in pairs(sessions) do
				local ok, err = pcall(passiveTick, player, session, elapsed)
				if not ok then
					warn("[GameService] Erreur du tick passif pour " .. player.Name .. " :", err)
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
					local ok, err = pcall(function()
						services.AchievementService:Check(player)
						self:SendState(player)
					end)
					if not ok then
						session.Dirty = false
						warn("[GameService] Erreur d'envoi de l'état pour " .. player.Name .. " :", err)
					end
				end
			end
		end
	end)

	-- Petit rappel dans la console du serveur
	print(string.format("[Dopamine Clicker] Serveur prêt (%d joueur(s))", #Players:GetPlayers()))
end

return GameService
