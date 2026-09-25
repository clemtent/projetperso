--[[
	CasinoService (ModuleScript)
	Emplacement : ServerScriptService > Services > CasinoService

	Machine à sous (débloquée par l'amélioration "Machine à sous").
	UNIQUEMENT avec la Dopamine du jeu (jamais de Robux). Fermée si
	Config.Casino.Enabled = false, ou automatiquement dès qu'une offre Robux
	est configurée (Config.Monetization.DisableCasinoWhenSelling).
	Le SERVEUR tire les 3 symboles (selon leur poids dans Config.Casino) et
	calcule le gain avec Formulas.GetCasinoMultiplier : le client ne fait
	qu'afficher l'animation puis le résultat reçu.
]]

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

local BIG_WIN_MULTIPLIER = 25 -- à partir de ce multiplicateur, tout le serveur est prévenu

-- Gain net cumulé au casino (pertes comprises) et son record, par joueur (session).
-- Seul ce qui dépasse le record compte dans LifetimeDopamine : sinon jouer
-- en boucle gonflerait le classement (les gains comptent, pas les pertes).
local casinoNet = {}
local casinoPeak = {}

function CasinoService:Init(allServices)
	services = allServices
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

local function isAllowedFraction(fraction: any): boolean
	if type(fraction) ~= "number" or fraction ~= fraction then
		return false
	end
	for _, allowed in ipairs(settings.BetFractions) do
		if math.abs(allowed - fraction) < 1e-9 then
			return true
		end
	end
	return false
end

-- Texte dans la langue du joueur
local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

local function onSpin(player: Player, fraction: any)
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, T(player, "Loading...")
	end
	if not services.MonetizationService:IsCasinoEnabled() then
		return false, T(player, "The casino is closed")
	end
	if not Formulas.HasFeature(data, settings.Feature) then
		return false, T(player, "The slot machine isn't unlocked yet")
	end
	if not isAllowedFraction(fraction) then
		return false, T(player, "Invalid bet")
	end
	-- Petite marge pour la latence réseau
	if not RateLimiter.Check(player, "CasinoSpin", math.max(0, settings.Cooldown - 0.1)) then
		return false, T(player, "The machine is still spinning...")
	end

	local bet = math.max(settings.MinBet, math.floor(data.Dopamine * fraction))
	if bet > data.Dopamine then
		return false, T(player, "You need at least %s %s", NumberFormatter.Format(settings.MinBet), Config.Game.CurrencyName)
	end

	local reels = { pickSymbol(), pickSymbol(), pickSymbol() }
	local multiplier = Formulas.GetCasinoMultiplier(reels)
	local payout = math.floor(bet * multiplier)

	local maxValue = Config.Game.MaxDopamine
	data.Dopamine = math.min(maxValue, data.Dopamine - bet + payout)
	data.Stats.SlotSpins += 1
	if payout > bet then
		data.Stats.SlotWins += 1
	end
	local net = (casinoNet[player] or 0) + (payout - bet)
	casinoNet[player] = net
	local peak = casinoPeak[player] or 0
	if net > peak then
		data.Stats.LifetimeDopamine = math.min(maxValue, data.Stats.LifetimeDopamine + (net - peak))
		casinoPeak[player] = net
	end
	services.QuestService:Progress(player, "Casino", 1)
	services.GameService:SendState(player)

	if multiplier >= BIG_WIN_MULTIPLIER then
		local displayName = player.DisplayName
		services.GameService:NotifyAll(function(lang)
			return {
				Type = "Info",
				Text = Locale.TFor(lang, "🎰 %s won x%s on the slot machine!", displayName, tostring(multiplier)),
			}
		end, player)
	end

	return true, {
		Reels = reels,
		Bet = bet,
		Payout = payout,
		Multiplier = multiplier,
	}
end

function CasinoService:PlayerRemoving(player: Player)
	casinoNet[player] = nil
	casinoPeak[player] = nil
end

function CasinoService:Start()
	Net.Function("CasinoSpin").OnServerInvoke = onSpin
end

return CasinoService
