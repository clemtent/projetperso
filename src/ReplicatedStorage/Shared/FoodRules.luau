--[[
	FoodRules (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > FoodRules

	🍦 Règles PURES de la nourriture de Dopamine Town (v9.8, FAIR98) :
	prix et cumul des boosts. Utilisé par le serveur (FoodService, qui
	décide) et par le client (FairFx : afficher le prix avant d'acheter),
	testé par tests/run_tests.py (sans Roblox).
]]

local Config = require(script.Parent.Config)

local FoodRules = {}

local function finite(v: any, default: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

-- Valeur d'un aliment : secondes de production "offertes" par son boost
function FoodRules.BoostSeconds(food: any): number
	return math.max(0, (finite(food.Multiplier, 1) - 1) * finite(food.Duration, 0))
end

-- Arrondi "joli" vers le haut (2 chiffres significatifs)
local function nice(x: number): number
	if x < 100 then
		return math.ceil(x)
	end
	local p = 10 ^ (math.floor(math.log10(x)) - 1)
	return math.ceil(x / p) * p
end

-- Prix en Dopamine. `perSecond` / `clickValue` = production actuelle du
-- joueur (stats du serveur) ; `foodMultiplier` = boost nourriture déjà
-- actif (on l'enlève : manger ne rend pas la suivante plus chère).
function FoodRules.Price(food: any, perSecond: any, clickValue: any, foodMultiplier: any): number
	local F = Config.Food
	local m = math.max(1, finite(foodMultiplier, 1))
	local production = (math.max(0, finite(perSecond, 0)) + math.max(0, finite(clickValue, 0)) * Config.Rewards.EstimatedClicksPerSecond) / m
	local price = F.PriceFactor * FoodRules.BoostSeconds(food) * production
	return nice(math.max(F.MinPrice, price))
end

-- Cumul : boost actuel (multiplicateur, secondes restantes) + aliment ->
-- nouveau (multiplicateur, secondes restantes). La "valeur" déjà gagnée
-- ((m - 1) x secondes) est conservée en changeant de multiplicateur.
function FoodRules.Stack(multiplier: any, remaining: any, food: any): (number, number)
	local F = Config.Food
	local cur = math.max(1, finite(multiplier, 1))
	local left = math.max(0, finite(remaining, 0))
	local m = math.clamp(finite(food.Multiplier, 1), 1, F.MaxMultiplier)
	local d = math.max(0, finite(food.Duration, 0))
	if m <= 1 or d <= 0 then
		return cur, math.min(left, F.MaxSeconds)
	end
	if left <= 0 or cur <= 1 then
		return m, math.min(d, F.MaxSeconds)
	end
	if m > cur then
		local converted = left * (cur - 1) / (m - 1)
		return m, math.min(d + converted, F.MaxSeconds)
	end
	local added = d * (m - 1) / (cur - 1)
	return cur, math.min(left + added, F.MaxSeconds)
end

-- Multiplicateur MOYEN au mieux (en mangeant sans arrêt le meilleur
-- rapport), prix déduit : 1 + (Mmax - 1) x (1 - PriceFactor). Sert aux
-- tests d'économie (il ne doit pas casser le rythme des parties).
function FoodRules.MaxNetMultiplier(): number
	local F = Config.Food
	return 1 + (F.MaxMultiplier - 1) * (1 - F.PriceFactor)
end

return FoodRules
