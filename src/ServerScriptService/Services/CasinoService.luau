--[[
	CasinoService (ModuleScript)
	Emplacement : ServerScriptService > Services > CasinoService

	🎰 Machine chanceuse (débloquée par l'amélioration "Lucky Machine").
	Tours GRATUITS : on ne mise JAMAIS rien (la Dopamine s'achète en Robux,
	donc aucun pari avec elle : règles Roblox sur les jeux d'argent).
	  - Jetons : 1 toutes les Config.Casino.TokenInterval secondes de jeu
	    (au plus MaxTokens). StartTokens offerts une seule fois quand la
	    machine est débloquée (data.Casino.Tokens = -1 : jamais initialisé).
	  - Un tour coûte 1 jeton. Le SERVEUR tire les 3 symboles (selon leur
	    poids) ; le gain vaut des SECONDES de production
	    (Formulas.GetCasinoRewardSeconds -> Formulas.ScaledReward) : paire,
	    triple, ou petit lot de consolation (MissRewardSeconds).
	  - Fermée seulement si Config.Casino.Enabled = false (ou si
	    Config.Monetization.DisableCasinoWhenSelling est forcé à true).
	Le client ne fait qu'afficher l'animation puis le résultat reçu.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local CasinoService = {}

local services
local random = Random.new()
local settings = Config.Casino

local CHARGE_RATE = 1 -- (s) fréquence de la recharge des jetons
local BIG_WIN_SECONDS = 240 -- à partir de ce gain (en secondes), tout le serveur est prévenu

function CasinoService:Init(allServices)
	services = allServices
end

local function isValidNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Répare data.Casino (sauvegarde abîmée) et donne les jetons de départ
-- la première fois que la machine est possédée. Renvoie true si ça a changé.
local function ensure(data): boolean
	local casino = data.Casino
	if type(casino) ~= "table" then
		casino = { Tokens = -1, Progress = 0 }
		data.Casino = casino
	end
	local changed = false
	if not isValidNumber(casino.Tokens) then
		casino.Tokens = -1
	end
	if not isValidNumber(casino.Progress) then
		casino.Progress = 0
	end
	casino.Progress = math.clamp(casino.Progress, 0, 1)
	if casino.Tokens < 0 then
		casino.Tokens = -1
		if Formulas.HasFeature(data, settings.Feature) then
			casino.Tokens = math.clamp(math.floor(settings.StartTokens or 0), 0, settings.MaxTokens)
			casino.Progress = 0
			changed = true
		end
	else
		casino.Tokens = math.clamp(math.floor(casino.Tokens), 0, settings.MaxTokens)
	end
	if casino.Tokens >= settings.MaxTokens then
		casino.Progress = 0
	end
	return changed
end

-- Recharge : `elapsed` secondes de jeu. Renvoie true si un jeton a été gagné.
local function charge(data, elapsed: number): boolean
	local changed = ensure(data)
	local casino = data.Casino
	if casino.Tokens < 0 or not Formulas.HasFeature(data, settings.Feature) then
		return changed
	end
	if casino.Tokens >= settings.MaxTokens then
		casino.Progress = 0
		return changed
	end
	casino.Progress += elapsed / math.max(1, settings.TokenInterval)
	while casino.Progress >= 1 and casino.Tokens < settings.MaxTokens do
		casino.Progress -= 1
		casino.Tokens += 1
		changed = true
	end
	if casino.Tokens >= settings.MaxTokens then
		casino.Progress = 0
	end
	return changed
end

-- Ajoute des jetons (commandes de test, récompenses éventuelles)
function CasinoService:AddTokens(player: Player, count: number)
	local data = services.DataService:GetData(player)
	if not data or not isValidNumber(count) then
		return
	end
	ensure(data)
	data.Casino.Tokens = math.clamp(math.max(0, data.Casino.Tokens) + math.floor(count), 0, settings.MaxTokens)
	services.GameService:SendState(player)
end

-- Champs ajoutés à l'état envoyé au client (voir GameService:BuildState)
function CasinoService:GetClientState(_player: Player, data)
	ensure(data)
	local casino = data.Casino
	return {
		Casino = {
			Tokens = math.max(0, casino.Tokens),
			Progress = casino.Progress,
			Max = settings.MaxTokens,
			Interval = settings.TokenInterval,
		},
	}
end

-- Tire un symbole au hasard selon son poids
local function pickSymbol(): string
	local total = 0
	for _, symbol in ipairs(settings.Symbols) do
		total += symbol.Weight
	end
	local roll = random:NextNumber(0, total)
	for _, symbol in ipairs(settings.Symbols) do
		roll -= symbol.Weight
		if roll <= 0 then
			return symbol.Id
		end
	end
	return settings.Symbols[#settings.Symbols].Id
end

-- Texte dans la langue du joueur
local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

local function formatWait(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function onSpin(player: Player, _ignored: any)
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, T(player, "Loading...")
	end
	if not services.MonetizationService:IsCasinoEnabled() then
		return false, T(player, "The lucky machine is closed")
	end
	if not Formulas.HasFeature(data, settings.Feature) then
		return false, T(player, "The lucky machine isn't unlocked yet")
	end
	-- Petite marge pour la latence réseau
	if not RateLimiter.Check(player, "CasinoSpin", math.max(0, settings.Cooldown - 0.1)) then
		return false, T(player, "The machine is still spinning...")
	end
	ensure(data)
	local casino = data.Casino
	if casino.Tokens < 1 then
		local wait = (1 - casino.Progress) * settings.TokenInterval
		return false, T(player, "No tokens left! Next one in %s", formatWait(wait))
	end

	local reels = { pickSymbol(), pickSymbol(), pickSymbol() }
	local matched = Formulas.GetCasinoMultiplier(reels)
	local seconds = Formulas.GetCasinoRewardSeconds(reels)
	local missSeconds = math.max(1, settings.MissRewardSeconds or 1)
	local minimum = (settings.MinReward or 0) * math.max(1, seconds / missSeconds)
	local reward = Formulas.ScaledReward(services.GameService:GetStats(player), seconds, minimum)

	casino.Tokens -= 1
	data.Stats.SlotSpins += 1
	if matched > 0 then
		data.Stats.SlotWins += 1
	end
	services.GameService:AddDopamine(player, reward, true)
	services.QuestService:Progress(player, "Casino", 1)
	services.GameService:SendState(player)

	if matched >= BIG_WIN_SECONDS then
		local displayName, formatted = player.DisplayName, NumberFormatter.Format(reward)
		services.GameService:NotifyAll(function(lang)
			return {
				Type = "Info",
				Text = Locale.TFor(lang, "🎰 %s hit the jackpot on the lucky machine (+%s)!", displayName, formatted),
			}
		end, player)
	end

	return true, {
		Symbols = reels,
		Reels = reels, -- (ancien nom)
		Reward = reward,
		Seconds = seconds,
		Win = matched > 0,
		Big = matched >= BIG_WIN_SECONDS,
		Tokens = casino.Tokens,
		Progress = casino.Progress,
		Max = settings.MaxTokens,
		Interval = settings.TokenInterval,
	}
end

function CasinoService:Start()
	Net.Function("CasinoSpin").OnServerInvoke = onSpin

	-- Recharge des jetons avec le temps de jeu (indépendante du tick passif)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(CHARGE_RATE)
			local now = os.clock()
			local elapsed = math.min(now - last, 5) -- pas d'énorme rattrapage après un gel
			last = now
			for _, player in ipairs(Players:GetPlayers()) do
				local data = services.DataService:GetData(player)
				if data and services.GameService:IsReady(player) then
					local ok, changed = pcall(charge, data, elapsed)
					if not ok then
						warn("[CasinoService] Recharge des jetons de " .. player.Name .. " :", changed)
					elseif changed then
						-- Nouveau jeton : état complet (au plus 1 fois / TokenInterval)
						services.GameService:SendState(player)
					end
				end
			end
		end
	end)
end

return CasinoService
