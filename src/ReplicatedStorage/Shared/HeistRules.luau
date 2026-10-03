--[[
	HeistRules (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > HeistRules

	🕶️ Règles PURES des casses (v11, BANK11) : récompenses, plafonds, part du
	butin, codes des mini-jeux, vérification de vitesse. Utilisé par le
	serveur (HeistKit / BankService / TrainService, qui décident), le client
	(HeistClient : afficher la récompense prévue) et les tests (sans Roblox).
	Casses CARTOON : pied-de-biche, perceuse, ordinateur ; jamais d'armes.
]]

local Config = require(script.Parent.Config)

local HeistRules = {}

-- Symboles du piratage (le client dessine les mêmes, dans le même ordre)
HeistRules.SYMBOLS = { "💎", "⭐", "🔑", "💰", "🔔", "🍀" }

local function finite(v: any, default: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

local function H(): any
	return (Config.Bank and Config.Bank.Heist) or {}
end

-- Règles d'un genre de casse ("Bank" | "Train") ; inconnu -> nil
function HeistRules.Kind(kind: any): any?
	if type(kind) ~= "string" then
		return nil
	end
	return H().Kinds and H().Kinds[kind] or nil
end

-- Bonus d'équipe (x)
function HeistRules.CrewFactor(crewSize: number): number
	local n = math.max(1, math.floor(finite(crewSize, 1)))
	return 1 + math.min(H().MaxCrewBonus or 0.3, (H().CrewBonus or 0.1) * (n - 1))
end

-- Part du butin livrée (0..1) : piles livrées / piles possibles (sacs de
-- l'équipe, au plus le nombre de piles du casse)
function HeistRules.Fill(delivered: number, crewSize: number, totalPiles: number?): number
	local cap = math.max(1, math.floor(finite(crewSize, 1))) * (H().BagCapacity or 3)
	local total = math.floor(finite(totalPiles, cap))
	if total > 0 then
		cap = math.min(cap, total)
	end
	return math.clamp(finite(delivered, 0) / math.max(1, cap), 0, 1)
end

-- Récompense d'un membre de l'équipe -> (Dopamine, 💎, plafonné ?)
-- stats = GameService:GetStats ; fill = part livrée (0..1) ;
-- rewardedToday = casses de CE genre déjà payés aujourd'hui.
function HeistRules.Reward(kind: string, stats: any, fill: number, crewSize: number, rewardedToday: number?): (number, number, boolean)
	local k = HeistRules.Kind(kind)
	if not k then
		return 0, 0, false
	end
	local f = math.clamp(finite(fill, 0), 0, 1)
	if f < (H().MinFill or 0.2) then
		return 0, 0, false
	end
	if finite(rewardedToday, 0) >= (k.Daily or 3) then
		return 0, 0, true
	end
	local perSecond = finite(stats and stats.PerSecond, 0)
	local click = finite(stats and stats.ClickValue, 0)
	local cps = (Config.Rewards and Config.Rewards.EstimatedClicksPerSecond) or 3
	local production = math.max(0, perSecond + click * cps)
	local seconds = (k.Seconds or 90) * f * HeistRules.CrewFactor(crewSize)
	local dopamine = math.floor(math.max(500, production * seconds))
	local range = k.Diamonds or { 5, 10 }
	local diamonds = math.floor((range[1] or 5) + ((range[2] or 10) - (range[1] or 5)) * f + 0.5)
	return dopamine, diamonds, false
end

-- Gain net maximal (multiplicateur moyen de la production) pour un joueur
-- qui réussit TOUS ses casses payés d'une journée de `sessionHours` h de jeu
-- (+ le change 💎 -> Dopamine au maximum) : borne du test d'économie.
function HeistRules.MaxNetMultiplier(sessionHours: number?): number
	local seconds = 0
	for _, k in pairs(H().Kinds or {}) do
		seconds += (k.Seconds or 0) * (1 + (H().MaxCrewBonus or 0.3)) * (k.Daily or 0)
	end
	local E = (Config.Bank and Config.Bank.Exchange) or {}
	seconds += (E.SecondsPerDiamond or 30) * (E.DailyMax or 15)
	local hours = math.max(1, finite(sessionHours, 2))
	return 1 + seconds / (hours * 3600)
end

-- 💎 max par jour (casses à fond, avant le plafond DailyCap)
function HeistRules.MaxDiamondsPerDay(): number
	local total = 0
	for _, k in pairs(H().Kinds or {}) do
		total += ((k.Diamonds or { 0, 0 })[2] or 0) * (k.Daily or 0)
	end
	local cap = (Config.Bank and Config.Bank.Diamonds and Config.Bank.Diamonds.DailyCap) or total
	return math.min(total, cap)
end

-- Code de piratage : `length` symboles (indices 1..#SYMBOLS) tirés avec
-- `rand(1, n)` (Random:NextInteger côté serveur) ; jamais 3 fois le même de suite
function HeistRules.HackCode(rand: (number, number) -> number, length: number?): { number }
	local n = math.clamp(math.floor(finite(length, H().HackLength or 5)), 3, 8)
	local code = {}
	for i = 1, n do
		local s = rand(1, #HeistRules.SYMBOLS)
		if i >= 3 and code[i - 1] == s and code[i - 2] == s then
			s = s % #HeistRules.SYMBOLS + 1
		end
		code[i] = s
	end
	return code
end

-- Réponse du client == code ? (liste d'entiers de même longueur)
function HeistRules.CheckCode(code: { number }, answer: any): boolean
	if type(answer) ~= "table" or #answer ~= #code or #answer > 8 then
		return false
	end
	for i, s in ipairs(code) do
		if answer[i] ~= s then
			return false
		end
	end
	return true
end

-- Déplacement plausible ? (distance en studs pendant dt secondes)
function HeistRules.SpeedOk(distance: number, dt: number): boolean
	local maxSpeed = H().MaxSpeed or 150
	return finite(distance, math.huge) <= maxSpeed * math.max(0.05, finite(dt, 0)) + 6
end

-- "m:ss"
function HeistRules.Clock(seconds: number): string
	local s = math.max(0, math.ceil(finite(seconds, 0)))
	return string.format("%d:%02d", s // 60, s % 60)
end

return HeistRules
