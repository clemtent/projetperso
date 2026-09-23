--[[
	Formulas (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Formulas

	Toutes les formules de calcul du jeu (coûts, gains, combo, rebirth...).
	Partagé entre serveur et client pour que l'affichage corresponde
	exactement aux calculs du serveur. Le serveur reste l'autorité.
]]

local Config = require(script.Parent.Config)

local Formulas = {}

----------------------------------------------------------------------
-- Coûts des améliorations
----------------------------------------------------------------------

-- Coût d'UN niveau quand on est au niveau `level`
function Formulas.GetUpgradeCost(upgrade, level: number): number
	return math.floor(upgrade.BaseCost * (upgrade.CostGrowth ^ level) + 0.5)
end

-- Nombre de niveaux restants avant le maximum (math.huge si illimité)
function Formulas.GetRemainingLevels(upgrade, level: number): number
	if upgrade.MaxLevel then
		return math.max(0, upgrade.MaxLevel - level)
	end
	return math.huge
end

-- Coût total pour acheter `amount` niveaux à partir de `level`
function Formulas.GetBulkCost(upgrade, level: number, amount: number): number
	local total = 0
	for i = 0, amount - 1 do
		total += Formulas.GetUpgradeCost(upgrade, level + i)
	end
	return total
end

-- Combien de niveaux peut-on acheter avec `money` ? -> (nombre, coût total)
function Formulas.GetMaxAffordable(upgrade, level: number, money: number): (number, number)
	local remaining = math.min(Formulas.GetRemainingLevels(upgrade, level), Config.MaxBulkBuy)
	local amount, total = 0, 0
	while amount < remaining do
		local nextCost = Formulas.GetUpgradeCost(upgrade, level + amount)
		if total + nextCost > money then
			break
		end
		total += nextCost
		amount += 1
	end
	return amount, total
end

-- Selon le mode d'achat ("x1", "x10", "max") -> (nombre de niveaux, coût)
-- Pour "max" sans assez d'argent, renvoie 1 niveau (pour afficher le prix).
function Formulas.GetPurchase(upgrade, level: number, mode: string, money: number): (number, number)
	local remaining = Formulas.GetRemainingLevels(upgrade, level)
	if remaining <= 0 then
		return 0, 0
	end

	if mode == "max" then
		local amount, total = Formulas.GetMaxAffordable(upgrade, level, money)
		if amount > 0 then
			return amount, total
		end
		return 1, Formulas.GetUpgradeCost(upgrade, level)
	end

	local amount = (mode == "x10") and 10 or 1
	amount = math.min(amount, remaining)
	return amount, Formulas.GetBulkCost(upgrade, level, amount)
end

-- Texte du bénéfice d'une amélioration (ex. "+5 / clic")
function Formulas.DescribeUpgrade(upgrade, format: (number) -> string): string
	if upgrade.Category == "Click" then
		return "+" .. format(upgrade.Value) .. " / clic"
	elseif upgrade.Category == "Passive" then
		return "+" .. format(upgrade.Value) .. " / seconde"
	end
	return "x" .. format(upgrade.Value) .. " sur TOUS les gains"
end

----------------------------------------------------------------------
-- Rebirth
----------------------------------------------------------------------

function Formulas.GetRebirthCost(rebirths: number): number
	return Config.Rebirth.BaseCost * (Config.Rebirth.CostGrowth ^ rebirths)
end

function Formulas.GetRebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.MultiplierPerRebirth
end

----------------------------------------------------------------------
-- Combo
----------------------------------------------------------------------

-- Jauge 0-100 -> multiplicateur 1 à MaxMultiplier
function Formulas.GetComboMultiplier(meter: number): number
	local ratio = math.clamp(meter / 100, 0, 1)
	return 1 + ratio * (Config.Combo.MaxMultiplier - 1)
end

-- Met à jour la jauge : on retire la perte depuis le dernier clic puis on ajoute un clic
function Formulas.StepCombo(meter: number, elapsed: number): number
	meter = math.max(0, meter - Config.Combo.DecayPerSecond * elapsed)
	return math.min(100, meter + Config.Combo.GainPerClick)
end

----------------------------------------------------------------------
-- Statistiques d'un joueur (gain par clic, par seconde, multiplicateurs)
----------------------------------------------------------------------

function Formulas.CountAchievements(data): number
	local count = 0
	for id in pairs(data.Achievements) do
		if Config.AchievementsById[id] then
			count += 1
		end
	end
	return count
end

-- `data` = données sauvegardées du joueur, `eventMultiplier` = Rush en cours (ou 1)
function Formulas.ComputeStats(data, eventMultiplier: number?)
	local baseClick = 1
	local basePerSecond = 0
	local upgradeMultiplier = 1

	for _, upgrade in ipairs(Config.Upgrades) do
		local level = data.Upgrades[upgrade.Id] or 0
		if level > 0 then
			if upgrade.Category == "Click" then
				baseClick += upgrade.Value * level
			elseif upgrade.Category == "Passive" then
				basePerSecond += upgrade.Value * level
			elseif upgrade.Category == "Multiplier" then
				upgradeMultiplier *= upgrade.Value ^ level
			end
		end
	end

	local rebirthMultiplier = Formulas.GetRebirthMultiplier(data.Rebirths)
	local achievementMultiplier = 1 + Formulas.CountAchievements(data) * Config.AchievementBonus
	local eventMult = eventMultiplier or 1
	local globalMultiplier = upgradeMultiplier * rebirthMultiplier * achievementMultiplier * eventMult

	return {
		BaseClick = baseClick,
		BasePerSecond = basePerSecond,
		UpgradeMultiplier = upgradeMultiplier,
		RebirthMultiplier = rebirthMultiplier,
		AchievementMultiplier = achievementMultiplier,
		EventMultiplier = eventMult,
		GlobalMultiplier = globalMultiplier,
		ClickValue = baseClick * globalMultiplier,
		PerSecond = basePerSecond * globalMultiplier,
	}
end

-- Récompense qui vaut `seconds` secondes de production (au moins `minimum`)
function Formulas.ScaledReward(stats, seconds: number, minimum: number): number
	local production = stats.PerSecond + stats.ClickValue * Config.Rewards.EstimatedClicksPerSecond
	return math.floor(math.max(minimum, production * seconds))
end

return Formulas
