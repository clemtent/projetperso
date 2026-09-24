--[[
	DailyRewardService (ModuleScript)
	Emplacement : ServerScriptService > Services > DailyRewardService

	Récompense quotidienne : 1 fois par jour (jour UTC). Revenir le jour
	suivant augmente la série (streak) et donc la récompense.
	L'heure utilisée est celle du SERVEUR (impossible à tricher en changeant
	l'heure de son PC). Nécessite la Feature "Daily" (amélioration "Calendrier").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local DailyRewardService = {}

local services
local SECONDS_PER_DAY = 86400

function DailyRewardService:Init(allServices)
	services = allServices
end

local function today(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

-- Série qu'aurait le joueur s'il réclamait maintenant
local function nextStreak(data): number
	if data.Daily.LastDay == today() - 1 then
		return data.Daily.Streak + 1
	end
	return 1
end

local function computeReward(stats, streak: number): number
	local bonusDays = math.min(streak, Config.Daily.MaxStreakBonus) - 1
	local seconds = Config.Daily.BaseRewardSeconds + bonusDays * Config.Daily.StreakBonusSeconds
	return Formulas.ScaledReward(stats, seconds, Config.Daily.MinReward * math.min(streak, Config.Daily.MaxStreakBonus))
end

-- Infos affichées par le client
function DailyRewardService:GetInfo(player: Player, stats)
	local data = services.DataService:GetData(player)
	local available = data.Daily.LastDay < today()
	local streak = available and nextStreak(data) or data.Daily.Streak
	return {
		Available = available,
		Streak = streak,
		Reward = computeReward(stats, streak),
		-- secondes avant le prochain jour UTC
		NextIn = (today() + 1) * SECONDS_PER_DAY - os.time(),
	}
end

local function onClaim(player: Player)
	if not RateLimiter.Check(player, "Daily", 1) then
		return false, "Doucement !"
	end
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, "Chargement en cours..."
	end
	if not Formulas.HasFeature(data, "Daily") then
		return false, "Le calendrier n'est pas encore débloqué"
	end
	if data.Daily.LastDay >= today() then
		return false, "Déjà récupéré aujourd'hui, reviens demain !"
	end

	local streak = nextStreak(data)
	local reward = computeReward(services.GameService:GetStats(player), streak)

	data.Daily.LastDay = today()
	data.Daily.Streak = streak
	data.Stats.DailyClaims += 1
	services.GameService:AddDopamine(player, reward, false)
	services.GameService:SendState(player)

	return true, string.format("Jour %d : +%s %s !", streak, NumberFormatter.Format(reward), Config.Game.CurrencyName)
end

function DailyRewardService:Start()
	Net.Function("ClaimDaily").OnServerInvoke = onClaim
end

return DailyRewardService
