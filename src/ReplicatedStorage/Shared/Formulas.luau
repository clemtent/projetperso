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

-- Texte de l'infobulle ("%s" remplacé par la valeur formatée).
-- `translate` (optionnel, ex. Locale.T) traduit la description AVANT de
-- remplacer "%s" : Formulas.DescribeUpgrade(upgrade, NumberFormatter.Format, rebirths, Locale.T)
function Formulas.DescribeUpgrade(
	upgrade,
	format: (number) -> string,
	rebirths: number?,
	translate: ((string) -> string)?
): string
	local text = upgrade.Description or ""
	if translate then
		local ok, translated = pcall(translate, text)
		if ok and type(translated) == "string" then
			text = translated
		end
	end
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

----------------------------------------------------------------------
-- 🏠 Maison
----------------------------------------------------------------------

-- Prix du PROCHAIN exemplaire d'un objet (ownedCount = exemplaires déjà possédés)
function Formulas.GetHouseItemPrice(item, ownedCount: number?): number
	local owned = tonumber(ownedCount) or 0
	if owned ~= owned or owned < 0 then
		owned = 0
	end
	return math.floor(item.Cost * ((item.CostGrowth or 1) ^ math.floor(owned)))
end

-- Taille de maison actuelle (config) : la 1re si la sauvegarde est invalide
function Formulas.GetHouseSize(data)
	local house = type(data) == "table" and data.House or nil
	local sizeId = type(house) == "table" and house.Size or nil
	return (type(sizeId) == "string" and Config.HouseSizesById[sizeId]) or Config.House.Sizes[1]
end

-- Type de pièce (config) : le 1er (salon) si l'id est inconnu
function Formulas.GetRoomType(typeId: any)
	return (type(typeId) == "string" and Config.HouseRoomTypesById[typeId]) or Config.House.RoomTypes[1]
end

-- Vrai si l'objet est un "préféré" de ce type de pièce (bonus d'harmonie)
function Formulas.IsRoomFavorite(roomType, item): boolean
	if type(roomType) ~= "table" or type(item) ~= "table" then
		return false
	end
	return roomType.FavoriteItems[item.Id] == true or roomType.FavoriteCategories[item.Category] == true
end

-- Confort d'un objet posé dans une pièce (harmonie comprise)
function Formulas.GetPlacedComfort(roomType, item): number
	local comfort = item.Comfort
	if Formulas.IsRoomFavorite(roomType, item) then
		comfort *= 1 + Config.House.HarmonyBonus
	end
	return comfort
end

-- Pièces de la maison (format sauvegardé). Une ancienne sauvegarde (une seule
-- pièce : house.Placed) est vue comme un salon unique.
function Formulas.GetHouseRooms(house): { any }
	if type(house) ~= "table" then
		return {}
	end
	if type(house.Rooms) == "table" and #house.Rooms > 0 then
		return house.Rooms
	end
	if type(house.Placed) == "table" then
		return { { Id = "R1", Type = "Living", Slot = 1, Placed = house.Placed } }
	end
	return {}
end

-- Prix de la PROCHAINE pièce quand on en a déjà `roomCount`
function Formulas.GetRoomCost(roomCount: number?): number
	local count = math.max(1, math.floor(tonumber(roomCount) or 1))
	local house = Config.House
	return math.floor(house.RoomCost * (house.RoomCostGrowth ^ (count - 1)))
end

-- Confort total = somme des Comfort des objets POSÉS dans toutes les pièces
-- (x (1 + HarmonyBonus) pour les objets préférés de leur pièce). On ne compte
-- que les objets connus, jamais plus d'exemplaires que possédés (toutes
-- pièces confondues), au plus RoomItems objets par pièce et MaxRooms pièces :
-- une sauvegarde abîmée ne donne rien de plus.
function Formulas.GetHouseComfort(data): number
	local house = type(data) == "table" and data.House or nil
	if type(house) ~= "table" then
		return 0
	end
	local owned = type(house.Items) == "table" and house.Items or {}
	local size = Formulas.GetHouseSize(data)
	local perRoom = size.RoomItems
	local used = {}
	local total = 0
	for roomIndex, room in ipairs(Formulas.GetHouseRooms(house)) do
		if roomIndex > size.MaxRooms then
			break
		end
		if type(room) == "table" and type(room.Placed) == "table" then
			local roomType = Formulas.GetRoomType(room.Type)
			local count = 0
			for _, entry in ipairs(room.Placed) do
				if count >= perRoom then
					break
				end
				local id = type(entry) == "table" and entry.I or nil
				local item = type(id) == "string" and Config.HouseItemsById[id] or nil
				if item then
					local n = (used[id] or 0) + 1
					local have = tonumber(owned[id]) or 0
					if n <= have then
						used[id] = n
						count += 1
						total += Formulas.GetPlacedComfort(roomType, item)
					end
				end
			end
		end
	end
	return total
end

-- Multiplicateur de gains du confort : 1 + min(Max, confort x bonus par point)
function Formulas.GetHouseBonus(comfort: number?): number
	local points = tonumber(comfort) or 0
	if points ~= points or points < 0 then
		points = 0
	end
	local house = Config.House
	return 1 + math.min(house.MaxComfortBonus, points * house.ComfortBonusPerPoint)
end

return Formulas
