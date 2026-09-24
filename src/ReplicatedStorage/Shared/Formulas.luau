--[[
	Formulas (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Formulas

	Toutes les formules de calcul du jeu (coûts, gains, combo, rebirth,
	casino...). Partagé entre serveur et client pour que l'affichage
	corresponde exactement aux calculs du serveur. Le serveur reste l'autorité.
]]

local Config = require(script.Parent.Config)

local Formulas = {}

----------------------------------------------------------------------
-- Améliorations
----------------------------------------------------------------------

-- Niveau actuel d'une amélioration
function Formulas.GetLevel(data, upgradeId: string): number
	return data.Upgrades[upgradeId] or 0
end

-- Rebirth ("Aller à l'océan")
function Formulas.GetRebirthCost(rebirths: number): number
	return Config.Rebirth.BaseCost * (Config.Rebirth.CostGrowth ^ rebirths)
end

function Formulas.GetRebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.MultiplierPerRebirth
end

-- Prix du PROCHAIN niveau (level = niveau actuel)
function Formulas.GetUpgradeCost(upgrade, level: number, rebirths: number?): number
	if upgrade.Effect == "Detox" then
		return Formulas.GetRebirthCost(rebirths or 0)
	end
	return math.floor(upgrade.Cost * (upgrade.CostGrowth ^ level) + 0.5)
end

function Formulas.IsMaxed(upgrade, level: number): boolean
	return upgrade.MaxLevel ~= nil and level >= upgrade.MaxLevel
end

-- Texte de l'infobulle ("%s" remplacé par la valeur formatée)
function Formulas.DescribeUpgrade(upgrade, format: (number) -> string, rebirths: number?): string
	local text = upgrade.Description or ""
	if not string.find(text, "%s", 1, true) then
		return text
	end
	local value = upgrade.Value or 0
	if upgrade.Effect == "Detox" then
		value = Formulas.GetRebirthMultiplier((rebirths or 0) + 1)
	elseif upgrade.Effect == "DVD" then
		value = Config.DVD.BaseBounceValue
	end
	return (string.gsub(text, "%%s", format(value), 1))
end

-- Liste des améliorations visibles dans la barre : celles déjà possédées
-- (et pas au maximum) + les Config.UpgradeBar.RevealAhead suivantes.
function Formulas.GetVisibleUpgrades(data): { any }
	local list = {}
	local revealed = 0
	for _, upgrade in ipairs(Config.Upgrades) do
		local level = Formulas.GetLevel(data, upgrade.Id)
		if not Formulas.IsMaxed(upgrade, level) then
			if level > 0 then
				table.insert(list, upgrade)
			elseif revealed < Config.UpgradeBar.RevealAhead then
				table.insert(list, upgrade)
				revealed += 1
			end
		end
	end
	return list
end

-- Ensemble des "Features" débloquées : { [Feature] = true }
function Formulas.GetFeatures(data): { [string]: boolean }
	local features = {}
	for _, upgrade in ipairs(Config.Upgrades) do
		if upgrade.Feature and Formulas.GetLevel(data, upgrade.Id) > 0 then
			features[upgrade.Feature] = true
		end
	end
	return features
end

function Formulas.HasFeature(data, feature: string): boolean
	local upgradeId = Config.FeatureToUpgrade[feature]
	return upgradeId ~= nil and Formulas.GetLevel(data, upgradeId) > 0
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
-- Statistiques d'un joueur
----------------------------------------------------------------------

local function countKeys(map, lookup): number
	local count = 0
	for id, value in pairs(map) do
		if value and lookup[id] then
			count += 1
		end
	end
	return count
end

function Formulas.CountAchievements(data): number
	return countKeys(data.Achievements, Config.AchievementsById)
end

function Formulas.CountCosmetics(data): number
	local cosmetics = data.Cosmetics
	if not cosmetics or not cosmetics.Owned then
		return 0
	end
	return countKeys(cosmetics.Owned, Config.CosmeticsById)
end

-- `data` = données sauvegardées du joueur, `eventMultiplier` = Rush en cours (ou 1),
-- `bonusMultiplier` = bonus Robux (Game Passes x Boost actif), calculé par le serveur (ou 1)
function Formulas.ComputeStats(data, eventMultiplier: number?, bonusMultiplier: number?)
	local baseClick = 1
	local basePerSecond = 0
	local clickMultiplier = 1
	local bounceMultiplier = 1
	local upgradeMultiplier = 1
	local dvdCount = 0

	for _, upgrade in ipairs(Config.Upgrades) do
		local level = Formulas.GetLevel(data, upgrade.Id)
		if level > 0 then
			local effect = upgrade.Effect
			if effect == "Click" then
				baseClick += upgrade.Value * level
			elseif effect == "PerSecond" then
				basePerSecond += upgrade.Value * level
			elseif effect == "DVD" then
				dvdCount += level
			elseif effect == "BounceMultiplier" then
				bounceMultiplier *= upgrade.Value ^ level
			elseif effect == "ClickMultiplier" then
				clickMultiplier *= upgrade.Value ^ level
			elseif effect == "Multiplier" then
				upgradeMultiplier *= upgrade.Value ^ level
			end
		end
	end

	local rebirthMultiplier = Formulas.GetRebirthMultiplier(data.Rebirths)
	local achievementMultiplier = 1 + Formulas.CountAchievements(data) * Config.AchievementBonus
	local cosmeticMultiplier = 1 + Formulas.CountCosmetics(data) * Config.CosmeticBonus
	local eventMult = eventMultiplier or 1
	local bonusMult = bonusMultiplier or 1
	local globalMultiplier = upgradeMultiplier * rebirthMultiplier * achievementMultiplier * cosmeticMultiplier * eventMult * bonusMult

	return {
		BaseClick = baseClick,
		BasePerSecond = basePerSecond,
		ClickMultiplier = clickMultiplier,
		BounceMultiplier = bounceMultiplier,
		UpgradeMultiplier = upgradeMultiplier,
		RebirthMultiplier = rebirthMultiplier,
		AchievementMultiplier = achievementMultiplier,
		CosmeticMultiplier = cosmeticMultiplier,
		EventMultiplier = eventMult,
		BonusMultiplier = bonusMult,
		GlobalMultiplier = globalMultiplier,
		ClickValue = baseClick * clickMultiplier * globalMultiplier,
		PerSecond = basePerSecond * globalMultiplier,
		BounceValue = Config.DVD.BaseBounceValue * bounceMultiplier * globalMultiplier,
		DVDCount = dvdCount,
	}
end

-- Récompense qui vaut `seconds` secondes de production (au moins `minimum`)
function Formulas.ScaledReward(stats, seconds: number, minimum: number): number
	local production = stats.PerSecond + stats.ClickValue * Config.Rewards.EstimatedClicksPerSecond
	return math.floor(math.max(minimum, production * seconds))
end

----------------------------------------------------------------------
-- Dopamine hors-ligne
----------------------------------------------------------------------

-- Niveau total des améliorations "Offline" (Mode veille)
function Formulas.GetOfflineLevel(data): number
	local level = 0
	for _, upgrade in ipairs(Config.Upgrades) do
		if upgrade.Effect == "Offline" then
			level += Formulas.GetLevel(data, upgrade.Id)
		end
	end
	return level
end

-- (taux 0..1, durée max en secondes)
function Formulas.GetOfflineSettings(data): (number, number)
	local level = Formulas.GetOfflineLevel(data)
	local rate = Config.Offline.BaseRate + Config.Offline.RatePerLevel * level
	local maxSeconds = (Config.Offline.BaseMaxHours + Config.Offline.HoursPerLevel * level) * 3600
	return rate, maxSeconds
end

-- Gain hors-ligne pour `seconds` d'absence avec la production `perSecond`
function Formulas.GetOfflineReward(data, perSecond: number, seconds: number): number
	if seconds < Config.Offline.MinSeconds or perSecond <= 0 then
		return 0
	end
	local rate, maxSeconds = Formulas.GetOfflineSettings(data)
	return math.floor(perSecond * rate * math.min(seconds, maxSeconds))
end

----------------------------------------------------------------------
-- Casino
----------------------------------------------------------------------

-- Multiplicateur de gain pour 3 symboles (ids). 0 = perdu.
function Formulas.GetCasinoMultiplier(reels: { string }): number
	local counts = {}
	for _, id in ipairs(reels) do
		counts[id] = (counts[id] or 0) + 1
	end
	local best = 0
	for id, count in pairs(counts) do
		local symbol = Config.CasinoSymbolsById[id]
		if symbol then
			if count == 3 then
				best = math.max(best, symbol.Triple)
			elseif count == 2 then
				best = math.max(best, symbol.Pair)
			end
		end
	end
	return best
end

-- Taux de retour théorique (ex. 0.93 = on récupère 93 % des mises en moyenne)
function Formulas.GetCasinoRTP(): number
	local symbols = Config.Casino.Symbols
	local totalWeight = 0
	for _, symbol in ipairs(symbols) do
		totalWeight += symbol.Weight
	end
	local expected = 0
	for _, a in ipairs(symbols) do
		for _, b in ipairs(symbols) do
			for _, c in ipairs(symbols) do
				local probability = (a.Weight / totalWeight) * (b.Weight / totalWeight) * (c.Weight / totalWeight)
				expected += probability * Formulas.GetCasinoMultiplier({ a.Id, b.Id, c.Id })
			end
		end
	end
	return expected
end

----------------------------------------------------------------------
-- Bourse
----------------------------------------------------------------------

function Formulas.GetStockValue(stock, price: number): number
	return (stock and stock.Shares or 0) * price
end

return Formulas
