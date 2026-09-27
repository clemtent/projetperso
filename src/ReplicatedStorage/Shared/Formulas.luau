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

-- Nombre de visites à l'océan lisible (nil, NaN, négatif -> 0)
local function cleanRebirths(rebirths: any): number
	local value = tonumber(rebirths) or 0
	if value ~= value or value < 0 then
		return 0
	end
	return math.min(math.floor(value), 1000)
end

-- Rebirth ("Aller à l'océan") : prix de la PROCHAINE visite quand on en a
-- déjà fait `rebirths`. BaseCost x CostGrowth^r x (1 + r)^CostPower : la
-- partie polynomiale rend chaque visite nettement plus longue que la
-- précédente (le multiplicateur gagné ne suffit jamais à la rattraper).
function Formulas.GetRebirthCost(rebirths: number): number
	local settings = Config.Rebirth
	local r = cleanRebirths(rebirths)
	return settings.BaseCost * (settings.CostGrowth ^ r) * ((1 + r) ^ (settings.CostPower or 0))
end

-- Multiplicateur permanent des visites : +MultiplierPerRebirth par visite,
-- de moins en moins (x MultiplierDecay à chaque visite suivante)
function Formulas.GetRebirthMultiplier(rebirths: number): number
	local settings = Config.Rebirth
	local r = cleanRebirths(rebirths)
	local decay = settings.MultiplierDecay or 1
	local bonus = 0
	local step = settings.MultiplierPerRebirth
	for _ = 1, r do
		bonus += step
		step *= decay
	end
	return 1 + bonus
end

-- Les améliorations (non permanentes) coûtent PriceGrowth^r x (1 + r)^PricePower
-- fois plus après r visites à l'océan : chaque partie coûte plus cher que la
-- précédente (surtout au début, puis de moins en moins vite)
function Formulas.GetUpgradePriceScale(rebirths: number?): number
	local settings = Config.Rebirth
	local r = cleanRebirths(rebirths)
	return (settings.PriceGrowth or 1) ^ r * (1 + r) ^ (settings.PricePower or 0)
end

-- Prix du PROCHAIN niveau (level = niveau actuel)
function Formulas.GetUpgradeCost(upgrade, level: number, rebirths: number?): number
	if upgrade.Effect == "Detox" then
		return Formulas.GetRebirthCost(rebirths or 0)
	end
	local scale = upgrade.Permanent and 1 or Formulas.GetUpgradePriceScale(rebirths)
	return math.floor(upgrade.Cost * (upgrade.CostGrowth ^ level) * scale + 0.5)
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
-- Vrai si l'amélioration peut être achetée : assez de visites à l'océan
-- (RequiresRebirths) et amélioration requise déjà possédée (Requires)
function Formulas.IsUpgradeUnlocked(data, upgrade): boolean
	local rebirths = type(data) == "table" and tonumber(data.Rebirths) or 0
	if (upgrade.RequiresRebirths or 0) > (rebirths or 0) then
		return false
	end
	if upgrade.Requires and Formulas.GetLevel(data, upgrade.Requires) <= 0 then
		return false
	end
	return true
end

-- Prochaine nouveauté verrouillée par les renaissances (pour l'annoncer :
-- "🌊 x nouveautés après ta prochaine visite à l'océan"), nil s'il n'y en a plus
function Formulas.GetNextRebirthUnlocks(data): (number?, number)
	local rebirths = type(data) == "table" and tonumber(data.Rebirths) or 0
	local nextGate: number? = nil
	for _, upgrade in ipairs(Config.Upgrades) do
		local gate = upgrade.RequiresRebirths or 0
		if gate > (rebirths or 0) and (nextGate == nil or gate < nextGate) then
			nextGate = gate
		end
	end
	local count = 0
	if nextGate then
		for _, upgrade in ipairs(Config.Upgrades) do
			if (upgrade.RequiresRebirths or 0) == nextGate then
				count += 1
			end
		end
	end
	return nextGate, count
end

function Formulas.GetVisibleUpgrades(data): { any }
	local list = {}
	local revealed = 0
	for _, upgrade in ipairs(Config.Upgrades) do
		local level = Formulas.GetLevel(data, upgrade.Id)
		if not Formulas.IsMaxed(upgrade, level) and Formulas.IsUpgradeUnlocked(data, upgrade) then
			if level > 0 then
				table.insert(list, upgrade)
			elseif revealed < Config.UpgradeBar.RevealAhead then
				-- (les améliorations verrouillées ne comptent pas : elles ne
				-- bloquent jamais l'océan)
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

-- Bonus permanents : +Config.CosmeticBonus par objet cosmétique possédé,
-- +Config.AchievementBonus par succès (linéaires, petits : jamais une boule
-- de neige, même avec tout le catalogue)
function Formulas.GetCosmeticMultiplier(count: number?): number
	return 1 + math.max(0, tonumber(count) or 0) * Config.CosmeticBonus
end

function Formulas.GetAchievementMultiplier(count: number?): number
	return 1 + math.max(0, tonumber(count) or 0) * Config.AchievementBonus
end

-- Verrous des renaissances (visites à l'océan) des cosmétiques et des thèmes
function Formulas.GetRequiredRebirths(entry): number
	return type(entry) == "table" and tonumber(entry.RequiresRebirths) or 0
end

function Formulas.IsCosmeticUnlocked(data, cosmetic): boolean
	local rebirths = type(data) == "table" and tonumber(data.Rebirths) or 0
	return Formulas.GetRequiredRebirths(cosmetic) <= (rebirths or 0)
end

function Formulas.IsThemeUnlocked(data, theme): boolean
	return Formulas.IsCosmeticUnlocked(data, theme)
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
	local achievementMultiplier = Formulas.GetAchievementMultiplier(Formulas.CountAchievements(data))
	local cosmeticMultiplier = Formulas.GetCosmeticMultiplier(Formulas.CountCosmetics(data))
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
-- 🎰 Machine chanceuse (tours GRATUITS : aucune mise)
-- Les gains sont en SECONDES de production (voir Formulas.ScaledReward)
----------------------------------------------------------------------

-- Secondes de production gagnées pour 3 symboles (ids). 0 = rien d'aligné.
-- Paire = 2 symboles identiques, Triple = 3 (on garde la meilleure combinaison)
function Formulas.GetCasinoMultiplier(reels: { string }): number
	local counts = {}
	for _, id in ipairs(reels) do
		counts[id] = (counts[id] or 0) + 1
	end
	local best = 0
	for id, count in pairs(counts) do
		local symbol = Config.CasinoSymbolsById[id]
		if symbol then
			if count >= 3 then
				best = math.max(best, symbol.Triple or 0)
			elseif count == 2 then
				best = math.max(best, symbol.Pair or 0)
			end
		end
	end
	return best
end

-- Secondes réellement données pour ce tirage (lot de consolation si rien ne sort)
function Formulas.GetCasinoRewardSeconds(reels: { string }): number
	local seconds = Formulas.GetCasinoMultiplier(reels)
	if seconds <= 0 then
		return Config.Casino.MissRewardSeconds or 0
	end
	return seconds
end

-- Gain moyen d'un tour, en secondes de production (consolation comprise)
function Formulas.GetCasinoRTP(): number
	local symbols = Config.Casino.Symbols
	local totalWeight = 0
	for _, symbol in ipairs(symbols) do
		totalWeight += symbol.Weight
	end
	if totalWeight <= 0 then
		return 0
	end
	local expected = 0
	for _, a in ipairs(symbols) do
		for _, b in ipairs(symbols) do
			for _, c in ipairs(symbols) do
				local probability = (a.Weight / totalWeight) * (b.Weight / totalWeight) * (c.Weight / totalWeight)
				expected += probability * Formulas.GetCasinoRewardSeconds({ a.Id, b.Id, c.Id })
			end
		end
	end
	return expected
end

----------------------------------------------------------------------
-- 🌻 Jardin de Dopamine
----------------------------------------------------------------------

-- Nombre de parterres (BasePlots + niveau de "Flower Beds")
function Formulas.GetGardenPlotCount(data): number
	local settings = Config.Garden
	local count = settings.BasePlots or 3
	for _, upgrade in ipairs(Config.Upgrades) do
		if upgrade.Feature == "GardenPlots" then
			count += Formulas.GetLevel(data, upgrade.Id)
		end
	end
	return count
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

-- Catégories dont les objets ne se posent jamais SUR un meuble (sauf
-- Tabletop = true dans la config : valise, carton...)
local NOT_ON_FURNITURE = { Furniture = true, Doors = true, Windows = true }

-- Vrai si l'objet peut être posé SUR un meuble (table, étagère, lit,
-- canapé...) : petit objet au sol, pas un meuble ni une porte. Même règle
-- côté client (éditeur) et serveur (limites de la disposition).
function Formulas.CanGoOnFurniture(item): boolean
	if type(item) ~= "table" or item.Placement ~= "Floor" then
		return false
	end
	if item.Tabletop == true then
		return true
	elseif item.Tabletop == false or NOT_ON_FURNITURE[item.Category] then
		return false
	end
	local house = Config.House
	return (tonumber(item.Size) or math.huge) <= (tonumber(house.TabletopMaxSize) or 0)
end

-- Plus petit Y (pieds) permis pour un objet au sol : celui des objets posés
-- sur les meubles s'il peut y aller (ou petit objet d'une ancienne
-- sauvegarde), sinon le haut de la zone du sol
function Formulas.GetHouseFloorMinY(item): number
	local house = Config.House
	local legacy = tonumber(house.LegacyTabletopSize) or 0
	if Formulas.CanGoOnFurniture(item) or (type(item) == "table" and (tonumber(item.Size) or math.huge) <= legacy) then
		return tonumber(house.TabletopMinY) or 0.22
	end
	return house.WallRatio * 0.85
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

-- Visites à l'océan nécessaires pour acheter un objet / un style / une
-- maison / un type de pièce de la maison (0 = disponible tout de suite).
-- RequiresRebirths explicite dans la config, sinon selon le prix
-- (Config.House.RebirthGates : les objets chers arrivent plus tard).
function Formulas.GetHouseRequiredRebirths(entry): number
	if type(entry) ~= "table" then
		return 0
	end
	if type(entry.RequiresRebirths) == "number" then
		return entry.RequiresRebirths
	end
	local cost = tonumber(entry.Cost) or 0
	local required = 0
	for _, gate in ipairs(Config.House.RebirthGates) do
		if cost >= gate.Cost then
			required = math.max(required, gate.Rebirths)
		end
	end
	return required
end

function Formulas.IsHouseEntryUnlocked(data, entry): boolean
	local rebirths = type(data) == "table" and tonumber(data.Rebirths) or 0
	return Formulas.GetHouseRequiredRebirths(entry) <= (rebirths or 0)
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

-- Multiplicateur de gains du confort, à rendements décroissants :
-- 1 + Max x c / (c + Max / ParPoint). Les premiers points valent
-- ComfortBonusPerPoint chacun, puis de moins en moins ; on approche
-- MaxComfortBonus sans jamais l'atteindre (moitié du max à Max / ParPoint
-- points de confort).
function Formulas.GetHouseBonus(comfort: number?): number
	local points = tonumber(comfort) or 0
	if points ~= points or points < 0 then
		points = 0
	end
	points = math.min(points, 1e12)
	local house = Config.House
	local max = house.MaxComfortBonus
	local perPoint = house.ComfortBonusPerPoint
	if max <= 0 or perPoint <= 0 then
		return 1
	end
	local half = max / perPoint
	return 1 + max * points / (points + half)
end

return Formulas
