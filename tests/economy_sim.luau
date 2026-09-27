--[[
	economy_sim.luau — simulateur d'économie de Dopamine Clicker

	Simule un joueur réaliste avec les VRAIS modules Shared (Config, Formulas,
	NumberFormatter) : mêmes prix, mêmes formules de gains, même barre
	d'améliorations (Formulas.GetVisibleUpgrades : l'océan n'apparaît que
	quand presque tout est acheté), mêmes verrous de renaissance.

	Lancement (le script est assemblé avec les modules par tests/run_tests.py,
	comme les tests) :
	    python3 tests/run_tests.py --sim                 # joueur actif sans Robux
	    python3 tests/run_tests.py --sim --robux         # + Game Passes x2 / VIP / auto-clic
	    python3 tests/run_tests.py --sim --whale         # + tous les Game Passes (x10 compris)
	    python3 tests/run_tests.py --sim --sessions      # 3 h de jeu par jour + gains hors-ligne
	    python3 tests/run_tests.py --sim --all           # les 4 profils l'un après l'autre
	Le test "Économie : rythme des renaissances" de run_tests.py lance le profil
	"Active" et vérifie les objectifs (Sim.Targets).

	Modèle du joueur (Sim.Behaviour, par seconde de jeu actif) :
	  - clique à 6 clics/s pendant 75 % du temps (45 s de clics, 15 s pour le
	    reste : boutiques, maison, bonus...) ; combo moyen calculé sur ce cycle ;
	    le beurre croustillant (x3 par croquée) sert de combo avant "Combo" ;
	  - production passive (Dopamine/s + rebonds du DVD) ;
	  - attrape la plupart des bonus (étoile dorée, éclairs, notifications,
	    mails, dons du live), clique de temps en temps sur le DVD, le fil
	    d'actu, le moulin, la presse turbo, éclate des bulles ; tourne la
	    machine chanceuse dès qu'il a un jeton, cueille le jardin toutes les
	    2 min, ouvre les coffres, finit une quête toutes les ~75 s, gagne
	    2 parties d'arcade par heure ; Dopamine Rush x2 30 s toutes les ~225 s ;
	  - achète ce qui se rembourse le plus vite (améliorations visibles,
	    objets de maison, cosmétiques), les NOUVELLES cartes dès qu'elles ne
	    coûtent pas trop cher (on veut voir ce qu'elles font), agrandit sa
	    maison quand elle est pleine, s'offre de temps en temps un style
	    (papier peint, sol, ambiance, thème...) ;
	  - va à l'océan dès que la carte est visible et payable ; avant, il
	    arrête d'acheter ce qui ne serait pas remboursé à temps.
	Les récompenses "secondes de production" utilisent Formulas.ScaledReward
	(même production de référence que le serveur).
]]

local Config = require("Config")
local Formulas = require("Formulas")
local N = require("NumberFormatter")

local Sim = {}

----------------------------------------------------------------------
-- Objectifs de rythme (joueur actif SANS Robux), en minutes de jeu
----------------------------------------------------------------------
Sim.Targets = {
	-- [n] = { min, max } : durée de la n-ième partie (de la visite n-1 à la visite n)
	RunMinutes = {
		[1] = { 45, 60 },
		[2] = { 60, 75 },
		[3] = { 75, 90 },
		[5] = { 90, 120 },
		[8] = { 150, 400 },
	},
	FirstPurchaseSeconds = 30, -- 1re amélioration achetée en moins de 30 s
	PurchasesIn5Min = 8, -- au moins 8 achats pendant les 5 premières minutes
	MinTotalHours = 16, -- R10 jamais avant 16 h de jeu actif (des jours de jeu)
	RobuxMinRatio = 0.25, -- avec x2 + VIP + auto-clic, une partie dure au moins 25 % de la partie sans Robux
}

----------------------------------------------------------------------
-- Comportement du joueur
----------------------------------------------------------------------
Sim.Behaviour = {
	ClickCycle = 60, -- (s) un cycle : on clique ClickDuty x ClickCycle secondes, puis on fait autre chose
	Catch = { Golden = 0.8, Lightning = 0.6, Notif = 0.7, Donation = 0.7, Email = 0.7 },
	-- Temps moyen (s) entre deux clics "volontaires" sur ces interactions
	Attention = { DVD = 30, Headline = 30, Spin = 10, Press = 10 },
	BubblesPerSecond = 1, -- bulles éclatées par seconde (en moyenne)
	BounceRate = 0.25, -- rebonds par seconde et par logo DVD (vitesse 0,16 écran/s)
	GardenCheck = 120, -- (s) passage au jardin
	QuestEvery = 75, -- (s) une quête finie en moyenne
	ArcadeWinsPerHour = 2, -- parties d'arcade gagnées par heure (Arcade possédée)
	ArcadeRewardSeconds = 35,
	ArcadeMinReward = 200,
	RushEvery = 225, -- (s) Dopamine Rush moyen (150..300)
	DecisionEvery = 2, -- (s) le joueur regarde les boutiques
	NewCardFactor = 3, -- une nouvelle carte "vaut" 3x le temps pour se la payer
	UtilityMaxSeconds = 120, -- menus sans gain (calendrier, succès...) : achetés s'ils coûtent < 2 min de gains
	PermanentFactor = 2, -- maison / cosmétiques gardés à l'océan : 2x plus intéressants
	HouseExpandSeconds = 300, -- pièce / maison achetée si elle coûte < 5 min de gains (maison pleine)
	StyleSinkSeconds = 20, -- style / thème acheté s'il coûte < 20 s de gains
	HarmonyShare = 1, -- les objets "préférés" d'une pièce possédée ont le bonus d'harmonie
}

----------------------------------------------------------------------
-- Profils
----------------------------------------------------------------------
local function passMultiplier(ids)
	local m = 1
	for _, id in ipairs(ids) do
		local pass = Config.GamePassesById[id]
		if pass and pass.Multiplier then
			m *= pass.Multiplier
		end
	end
	return m
end

Sim.Profiles = {
	Active = { Name = "Actif, sans Robux", ClicksPerSecond = 6, ClickDuty = 0.75, Passes = {}, AutoClicks = 0 },
	Robux = { Name = "Actif + Game Passes x2, VIP, auto-clic", ClicksPerSecond = 6, ClickDuty = 0.75,
		Passes = { "X2", "VIP" }, AutoClicks = 5 },
	Whale = { Name = "Actif + TOUS les Game Passes (x10, x2, VIP, auto-clic)", ClicksPerSecond = 6, ClickDuty = 0.75,
		Passes = { "X10", "X2", "VIP" }, AutoClicks = 5 },
	Sessions = { Name = "3 h de jeu par jour + hors-ligne, sans Robux", ClicksPerSecond = 6, ClickDuty = 0.75,
		Passes = {}, AutoClicks = 0, SessionHours = 3 },
}
Sim.ProfileOrder = { "Active", "Robux", "Whale", "Sessions" }

----------------------------------------------------------------------
-- Valeurs moyennes tirées de la config
----------------------------------------------------------------------
local function weightedAverage(list, valueFn)
	local total, sum = 0, 0
	for _, entry in ipairs(list) do
		total += entry.Weight
		sum += entry.Weight * valueFn(entry)
	end
	return total > 0 and sum / total or 0
end

-- Combo moyen sur un cycle "ClickDuty x ClickCycle s de clics puis pause"
local function averageCombo(cps: number, duty: number): number
	local B = Sim.Behaviour
	local meter, sum, n = 0, 0, 0
	local clickTime = B.ClickCycle * duty
	for _ = 1, 3 do -- 3 cycles : régime établi
		meter = 0 -- la pause vide la jauge (DecayPerSecond x pause)
		local t = 0
		sum, n = 0, 0
		while t < clickTime do
			meter = Formulas.StepCombo(meter, 1 / cps)
			sum += Formulas.GetComboMultiplier(meter)
			n += 1
			t += 1 / cps
		end
	end
	return n > 0 and sum / n or 1
end

local function casinoWinChance(): number
	local symbols = Config.Casino.Symbols
	local total = 0
	for _, s in ipairs(symbols) do
		total += s.Weight
	end
	local win = 0
	for _, a in ipairs(symbols) do
		for _, b in ipairs(symbols) do
			for _, c in ipairs(symbols) do
				if Formulas.GetCasinoMultiplier({ a.Id, b.Id, c.Id }) > 0 then
					win += (a.Weight / total) * (b.Weight / total) * (c.Weight / total)
				end
			end
		end
	end
	return win
end

----------------------------------------------------------------------
-- État simulé
----------------------------------------------------------------------
local function newData()
	local house = Config.House
	return {
		Dopamine = 0,
		Rebirths = 0,
		Upgrades = {},
		Achievements = {},
		Cosmetics = { Owned = {}, Equipped = { Hat = "", Skin = "" } },
		Themes = { Owned = { Classic = true } },
		LiveFollowed = false,
		House = {
			Size = house.Sizes[1].Id,
			Items = {},
			Rooms = { { Id = "R1", Type = "Living", Slot = 1, Placed = {} } },
		},
		Stats = {
			TotalClicks = 0, LifetimeDopamine = 0, UpgradesBought = 0, CombosMaxed = 0, Bounces = 0,
			DVDCorners = 0, GoldenClicks = 0, LightningClicks = 0, NotifsOpened = 0, EmailsRead = 0,
			BubblesPopped = 0, PressCrushes = 0, SlotSpins = 0, SlotWins = 0, GardenHarvests = 0,
			MinigamesWon = 0, ChestsOpened = 0, CosmeticsBought = 0, QuestsCompleted = 0, DailyClaims = 0,
			PlaySeconds = 0,
		},
	}
end

-- Liste des styles (sans effet sur les gains) : dépenses "plaisir"
local function buildStyleList()
	local list = {}
	local function add(entries, kind)
		for _, e in ipairs(entries) do
			if type(e.Cost) == "number" and e.Cost > 0 then
				table.insert(list, { Kind = kind, Entry = e, Cost = e.Cost })
			end
		end
	end
	local H = Config.House
	add(H.Wallpapers, "Wallpaper")
	add(H.Floors, "Floor")
	for kind, def in pairs(Config.HouseLookKinds) do
		add(def.List, kind)
	end
	for _, theme in ipairs(Config.Themes) do
		if type(theme.Cost) == "number" and theme.Cost > 0 then
			table.insert(list, { Kind = "Theme", Entry = theme, Cost = theme.Cost })
		end
	end
	table.sort(list, function(a, b)
		return a.Cost < b.Cost
	end)
	return list
end

-- Verrou d'un thème (RequiresRebirths, même règle que les cosmétiques)
local function themeUnlocked(data, theme): boolean
	if Formulas.IsThemeUnlocked then
		return Formulas.IsThemeUnlocked(data, theme)
	end
	return (tonumber(theme.RequiresRebirths) or 0) <= data.Rebirths
end

local function styleUnlocked(data, style): boolean
	if style.Kind == "Theme" then
		return themeUnlocked(data, style.Entry)
	end
	return Formulas.IsHouseEntryUnlocked(data, style.Entry)
end

local function cosmeticUnlocked(data, cosmetic): boolean
	if Formulas.IsCosmeticUnlocked then
		return Formulas.IsCosmeticUnlocked(data, cosmetic)
	end
	return (tonumber(cosmetic.RequiresRebirths) or 0) <= data.Rebirths
end

local function roomTypeUnlocked(data, roomType): boolean
	return Formulas.IsHouseEntryUnlocked(data, roomType)
end

----------------------------------------------------------------------
-- Simulation
----------------------------------------------------------------------
function Sim.Run(profileOrName, options)
	options = options or {}
	local profile = type(profileOrName) == "string" and Sim.Profiles[profileOrName] or profileOrName or Sim.Profiles.Active
	local B = Sim.Behaviour
	local maxRebirths = options.MaxRebirths or 10
	local maxSeconds = (options.MaxHours or 60) * 3600
	local sampleEvery = options.SampleEvery or 600

	local data = newData()
	local passMult = passMultiplier(profile.Passes or {})
	local cps, duty, autoCps = profile.ClicksPerSecond, profile.ClickDuty, profile.AutoClicks or 0
	local comboAvg = averageCombo(cps, duty)
	local comboMax = Config.Combo.MaxMultiplier
	local casinoRTP = Formulas.GetCasinoRTP()
	local casinoWin = casinoWinChance()
	local estCps = Config.Rewards.EstimatedClicksPerSecond
	local styles = buildStyleList()
	local ownedStyles = {}

	-- Moyennes (en "secondes de production") et minimums des sources
	local gardenTotalWeight = 0
	for _, f in ipairs(Config.Garden.Flowers) do
		gardenTotalWeight += f.Weight
	end
	local gardenCycle = weightedAverage(Config.Garden.Flowers, function(f)
		return f.GrowSeconds
	end) + B.GardenCheck / 2
	local questSeconds, questMin = 0, 0
	for _, q in ipairs(Config.Quests.Pool) do
		questSeconds += q.RewardSeconds
		questMin += q.MinReward
	end
	questSeconds /= #Config.Quests.Pool
	questMin /= #Config.Quests.Pool

	-- Maison (état simplifié : confort des objets posés, trié)
	local sizeIndex = 1
	local roomTypes = { "Living" }
	local favorites = { [Config.HouseRoomTypesById.Living] = true }
	local placed = {} -- confort (harmonie comprise) des objets posés, trié croissant
	local comfort = 0
	local function capacity(): number
		return #roomTypes * Config.House.Sizes[sizeIndex].RoomItems
	end
	local function itemComfort(item): number
		for roomType in pairs(favorites) do
			if Formulas.IsRoomFavorite(roomType, item) then
				return Formulas.GetPlacedComfort(roomType, item)
			end
		end
		return item.Comfort
	end
	local function comfortGain(item): number
		local c = itemComfort(item)
		if #placed < capacity() then
			return c
		end
		local low = placed[1]
		return (low and c > low) and (c - low) or 0
	end
	local function placeItem(item)
		local c = itemComfort(item)
		if #placed >= capacity() then
			if placed[1] and c > placed[1] then
				comfort -= placed[1]
				table.remove(placed, 1)
			else
				return
			end
		end
		comfort += c
		local i = 1
		while placed[i] and placed[i] < c do
			i += 1
		end
		table.insert(placed, i, c)
	end

	-- Taux de gains --------------------------------------------------
	local rates -- cache
	local ratesVersion = 0 -- change à chaque recalcul (état modifié)
	local function computeRates()
		ratesVersion += 1
		local houseBonus = Formulas.GetHouseBonus(comfort)
		local stats = Formulas.ComputeStats(data, 1, passMult * houseBonus)
		local f = Formulas.GetFeatures(data)
		local cv = stats.ClickValue
		local P = stats.PerSecond + cv * estCps
		local manual = math.max(f.Combo and comboAvg or 1, f.Butter and Config.Interactions.Butter.ClickFraction or 1)
		local clicks = cps * duty * cv * manual + autoCps * cv * (f.Combo and comboMax or 1)
		local bubbles = f.BubbleWrap and B.BubblesPerSecond * cv * Config.Interactions.Bubble.ClickFraction or 0
		local passive = stats.PerSecond + stats.DVDCount * B.BounceRate * stats.BounceValue
		local bonus = 0
		local function reward(seconds, minimum)
			return math.max(minimum, P * seconds)
		end
		for kind, s in pairs(Config.Spawners) do
			if f[s.Feature] and (not s.RequiresFollow or data.LiveFollowed) then
				local catch = B.Catch[kind] or 0.5
				bonus += catch * reward(s.RewardSeconds, s.MinReward) / ((s.MinInterval + s.MaxInterval) / 2)
			end
		end
		local I = Config.Interactions
		if f.DVD then
			bonus += reward(Config.DVD.ClickRewardSeconds, Config.DVD.ClickMinReward) / math.max(Config.DVD.ClickCooldown, B.Attention.DVD)
		end
		if f[I.Headline.Feature] then
			bonus += reward(I.Headline.RewardSeconds, I.Headline.MinReward) / math.max(I.Headline.Cooldown, B.Attention.Headline)
		end
		if f[I.Spin.Feature] then
			bonus += reward(I.Spin.RewardSeconds, I.Spin.MinReward) / math.max(I.Spin.Cooldown, B.Attention.Spin)
		end
		if f[I.Press.Feature] then
			bonus += reward(I.Press.RewardSeconds, I.Press.MinReward) / math.max(I.Press.Cooldown, B.Attention.Press)
		end
		if f[Config.Casino.Feature] then
			bonus += reward(casinoRTP, Config.Casino.MinReward) / Config.Casino.TokenInterval
		end
		local plots = 0
		if f[Config.Garden.Feature] then
			plots = Formulas.GetGardenPlotCount(data)
			local perCycle = weightedAverage(Config.Garden.Flowers, function(fl)
				return reward(fl.RewardSeconds, (Config.Garden.MinReward or 0) * math.max(1, fl.RewardSeconds / 10))
			end)
			bonus += plots * perCycle / gardenCycle
		end
		if f[Config.LootBox.Feature] then
			bonus += weightedAverage(Config.LootBox.Tiers, function(t)
				return reward(t.RewardSeconds, 100)
			end) / Config.LootBox.ChargeInterval
		end
		if f.Quests then
			bonus += reward(questSeconds, questMin) / B.QuestEvery
		end
		if f.Minigames then
			bonus += reward(B.ArcadeRewardSeconds, B.ArcadeMinReward) * B.ArcadeWinsPerHour / 3600
		end
		rates = {
			Stats = stats, Features = f, P = P, Plots = plots, HouseBonus = houseBonus,
			Clicks = clicks + bubbles, Passive = passive, Bonus = bonus,
			Total = clicks + bubbles + passive + bonus,
		}
		return rates
	end

	local rushAverage = 1 + (Config.Events.Rush.Multiplier - 1) * Config.Events.Rush.Duration / B.RushEvery

	-- Résultats ------------------------------------------------------
	local result = {
		Profile = profile.Name,
		RebirthAt = {}, -- [n] = secondes de jeu actif à la n-ième visite
		RebirthDay = {}, -- [n] = jour (profil "sessions")
		Samples = {},
		Purchases = {}, -- achats des 10 premières minutes
		Log = {},
		ReachedMax = false,
	}
	local function sample(t)
		local r = rates or computeRates()
		local s = r.Stats
		table.insert(result.Samples, {
			T = t, Rebirths = data.Rebirths, Bank = data.Dopamine, Income = r.Total * rushAverage,
			P = r.P, Clicks = r.Clicks, Passive = r.Passive, Bonus = r.Bonus,
			Rebirth = s.RebirthMultiplier, Upgrade = s.UpgradeMultiplier, ClickMult = s.ClickMultiplier,
			Achievement = s.AchievementMultiplier, Cosmetic = s.CosmeticMultiplier, House = r.HouseBonus,
			Comfort = comfort, Items = #placed, Cosmetics = Formulas.CountCosmetics(data),
			Achievements = Formulas.CountAchievements(data),
		})
	end

	local function earn(amount)
		if amount <= 0 then
			return
		end
		data.Dopamine += amount
		data.Stats.LifetimeDopamine += amount
	end

	local function checkAchievements()
		local changed = false
		for _, a in ipairs(Config.Achievements) do
			if not data.Achievements[a.Id] then
				local value = data.Stats[a.Stat]
				if value == nil then
					value = data[a.Stat]
				end
				if type(value) == "number" and value >= a.Goal then
					data.Achievements[a.Id] = true
					if SIM_DEBUG then print("ACH", t, a.Id, a.Reward) end
					earn(a.Reward)
					changed = true
				end
			end
		end
		if changed then
			rates = nil
		end
	end

	-- Achats ---------------------------------------------------------
	local t = 0
	local function logPurchase(kind, name, cost)
		if SIM_DEBUG then
			print("BUY", t, data.Rebirths, name, cost, data.Dopamine, (rates or computeRates()).Total, SIM_LASTGAIN or 0)
		end
		if t <= 600 then
			table.insert(result.Purchases, { T = t, Kind = kind, Name = name, Cost = cost })
		end
	end

	local function onFeatureBought(upgrade)
		local r = rates or computeRates()
		if upgrade.Feature == "LiveStream" and not data.LiveFollowed then
			data.LiveFollowed = true -- s'abonne tout de suite (bonus unique)
			local I = Config.Interactions.Follow
			earn(math.max(I.MinReward, r.P * I.RewardSeconds))
		end
		if upgrade.Feature == Config.Casino.Feature and not data.CasinoStarted then
			data.CasinoStarted = true -- jetons offerts (une fois dans la vie)
			earn(Config.Casino.StartTokens * math.max(Config.Casino.MinReward, r.P * casinoRTP))
			data.Stats.SlotSpins += Config.Casino.StartTokens
		end
	end

	local nextThreshold = 0 -- (optimisation) rien ne change tant que la Dopamine n'atteint pas ce seuil
	local lastDecisionAt = 0
	local decidedVersion = -1 -- ... ni que l'état (taux de gains) ne change
	local function tryPurchase()
		local r = rates or computeRates()
		local R = r.Total * rushAverage
		if R <= 0 then
			return false
		end
		local bank = data.Dopamine
		local visible = Formulas.GetVisibleUpgrades(data)
		local oceanVisible = false
		for _, u in ipairs(visible) do
			if u.Effect == "Detox" then
				oceanVisible = true
			end
		end
		local oceanCost = Formulas.GetRebirthCost(data.Rebirths)
		-- Temps avant de pouvoir aller à l'océan (si la carte est là)
		local horizon = math.huge
		if oceanVisible then
			horizon = math.max(0, (oceanCost - bank) / R)
		end

		local best, bestScore = nil, math.huge
		nextThreshold = math.huge
		local function consider(candidate)
			local cost = candidate.Cost
			if not (cost == cost) or cost == math.huge then
				return
			end
			local payback = candidate.Gain > 0 and cost / (candidate.Gain * rushAverage) or math.huge
			if candidate.NewCard then
				payback = math.min(payback, cost / R * B.NewCardFactor)
			end
			if candidate.Utility then
				payback = cost <= R * B.UtilityMaxSeconds and cost / R or math.huge
			end
			if candidate.Permanent then
				payback /= B.PermanentFactor
			end
			if payback == math.huge then
				return
			end
			-- Pas rentable avant l'océan : on garde plutôt pour la visite
			local limit = candidate.Permanent and horizon * 2 or horizon
			if oceanVisible and payback > limit then
				return
			end
			if cost > bank and cost < nextThreshold then
				nextThreshold = cost
			end
			local wait = math.max(0, (cost - bank) / R)
			local score = wait + payback
			if score < bestScore then
				best, bestScore = candidate, score
			end
		end

		-- Améliorations visibles
		local baseTotal = r.Total
		for _, u in ipairs(visible) do
			if u.Effect ~= "Detox" then
				local level = data.Upgrades[u.Id] or 0
				local cost = Formulas.GetUpgradeCost(u, level, data.Rebirths)
				data.Upgrades[u.Id] = level + 1
				local after = computeRates().Total
				data.Upgrades[u.Id] = level > 0 and level or nil
				rates = nil
				local gain = after - baseTotal
				local utility = gain <= 0 and (u.Effect == "Feature" or u.Effect == "Offline")
				consider({ Kind = "Upgrade", Upgrade = u, Cost = cost, Gain = gain, NewCard = level == 0,
					Utility = utility, Permanent = u.Permanent == true })
			end
		end
		r = computeRates()

		-- Objets de la maison : le meilleur rapport confort / prix
		local bonusNow = Formulas.GetHouseBonus(comfort)
		local bestItem, bestItemRatio, bestItemCost, bestItemGain = nil, 0, 0, 0
		for _, item in ipairs(Config.House.Items) do
			local owned = data.House.Items[item.Id] or 0
			if (item.MaxOwned == nil or owned < item.MaxOwned) and Formulas.IsHouseEntryUnlocked(data, item) then
				local g = comfortGain(item)
				if g > 0 then
					local price = Formulas.GetHouseItemPrice(item, owned)
					local gain = r.Total * (Formulas.GetHouseBonus(comfort + g) / bonusNow - 1)
					if gain > 0 and gain / price > bestItemRatio then
						bestItem, bestItemRatio, bestItemCost, bestItemGain = item, gain / price, price, gain
					end
				end
			end
		end
		if bestItem then
			consider({ Kind = "Item", Item = bestItem, Cost = bestItemCost, Gain = bestItemGain, Permanent = true })
		end

		-- Cosmétiques (+bonus par objet possédé)
		if r.Features.ItemShop then
			local n = Formulas.CountCosmetics(data)
			local mult = (1 + (n + 1) * Config.CosmeticBonus) / (1 + n * Config.CosmeticBonus)
			if Formulas.GetCosmeticMultiplier then
				mult = Formulas.GetCosmeticMultiplier(n + 1) / Formulas.GetCosmeticMultiplier(n)
			end
			local cheapest
			for _, c in ipairs(Config.Cosmetics) do
				if not data.Cosmetics.Owned[c.Id] and cosmeticUnlocked(data, c) and (cheapest == nil or c.Cost < cheapest.Cost) then
					cheapest = c
				end
			end
			if cheapest then
				consider({ Kind = "Cosmetic", Cosmetic = cheapest, Cost = cheapest.Cost, Gain = r.Total * (mult - 1), Permanent = true })
			end
		end

		-- Agrandir la maison quand elle est pleine
		if #placed >= capacity() then
			local size = Config.House.Sizes[sizeIndex]
			if #roomTypes < size.Floors * size.Columns then
				local cost = Formulas.GetRoomCost(#roomTypes)
				if cost <= R * B.HouseExpandSeconds and cost > bank and cost < nextThreshold then
					nextThreshold = cost
				end
				if cost <= R * B.HouseExpandSeconds and cost <= bank then
					consider({ Kind = "Room", Cost = cost, Gain = 0, Utility = true, Permanent = true })
				end
			else
				local nextSize = Config.House.Sizes[sizeIndex + 1]
				if nextSize and Formulas.IsHouseEntryUnlocked(data, nextSize) and nextSize.Cost <= R * B.HouseExpandSeconds then
					consider({ Kind = "Size", Size = nextSize, Cost = nextSize.Cost, Gain = 0, Utility = true, Permanent = true })
				end
			end
		end

		-- Océan
		if oceanVisible and bank >= oceanCost then
			return "Ocean"
		end
		if oceanVisible and oceanCost < nextThreshold then
			nextThreshold = oceanCost
		end

		if best and best.Cost <= bank then
			SIM_LASTGAIN = best.Gain
			data.Dopamine -= best.Cost
			if best.Kind == "Upgrade" then
				local u = best.Upgrade
				local level = data.Upgrades[u.Id] or 0
				data.Upgrades[u.Id] = level + 1
				data.Stats.UpgradesBought += 1
				logPurchase("Upgrade", u.Id .. " " .. (level + 1), best.Cost)
				if level == 0 then
					onFeatureBought(u)
				end
			elseif best.Kind == "Item" then
				local item = best.Item
				data.House.Items[item.Id] = (data.House.Items[item.Id] or 0) + 1
				placeItem(item)
				logPurchase("Item", item.Id, best.Cost)
			elseif best.Kind == "Cosmetic" then
				data.Cosmetics.Owned[best.Cosmetic.Id] = true
				data.Stats.CosmeticsBought += 1
				logPurchase("Cosmetic", best.Cosmetic.Id, best.Cost)
			elseif best.Kind == "Room" then
				-- Prochain type de pièce débloqué (pour l'harmonie)
				for _, rt in ipairs(Config.House.RoomTypes) do
					if not favorites[rt] and roomTypeUnlocked(data, rt) then
						favorites[rt] = true
						table.insert(roomTypes, rt.Id)
						break
					end
				end
				if #roomTypes < 1 + #placed // Config.House.Sizes[sizeIndex].RoomItems then
					table.insert(roomTypes, "Living")
				end
				logPurchase("Room", "#" .. #roomTypes, best.Cost)
			elseif best.Kind == "Size" then
				sizeIndex += 1
				data.House.Size = best.Size.Id
				logPurchase("Size", best.Size.Id, best.Cost)
			end
			rates = nil
			return true
		end

		-- Petits plaisirs : un style pas cher (aucun effet sur les gains)
		for index, style in ipairs(styles) do
			if not ownedStyles[index] and style.Cost <= bank * 0.5 and style.Cost <= R * B.StyleSinkSeconds and styleUnlocked(data, style) then
				ownedStyles[index] = true
				data.Dopamine -= style.Cost
				return true
			elseif style.Cost > R * B.StyleSinkSeconds then
				break
			elseif not ownedStyles[index] and style.Cost > bank * 0.5 and styleUnlocked(data, style) then
				nextThreshold = math.min(nextThreshold, style.Cost * 2)
				break
			end
		end
		return false
	end

	local function detox()
		local kept = {}
		for id, level in pairs(data.Upgrades) do
			local u = Config.UpgradesById[id]
			if u and u.Permanent then
				kept[id] = level
			end
		end
		data.Upgrades = kept
		data.Dopamine = 0
		data.Rebirths += 1
		data.LiveFollowed = false
		rates = nil
	end

	-- Boucle principale ----------------------------------------------
	local dt = 1
	local nextDecision = 0
	local nextSample = 0
	local lastRebirthAt = 0
	local sessionSeconds = 0
	local day = 1
	local streak = 1
	local function claimDaily()
		if not Formulas.HasFeature(data, "Daily") then
			return
		end
		local r = rates or computeRates()
		local D = Config.Daily
		local bonusDays = math.min(streak, D.MaxStreakBonus) - 1
		local seconds = D.BaseRewardSeconds + bonusDays * D.StreakBonusSeconds
		earn(math.max(D.MinReward * math.min(streak, D.MaxStreakBonus), r.P * seconds))
		data.Stats.DailyClaims += 1
		streak += 1
	end

	while t < maxSeconds and data.Rebirths < maxRebirths do
		local r = rates or computeRates()
		local rush = (t % B.RushEvery) < Config.Events.Rush.Duration and Config.Events.Rush.Multiplier or 1
		earn(r.Total * rush * dt)
		-- Statistiques (pour les succès)
		local S = data.Stats
		local f = r.Features
		S.TotalClicks += (cps * duty + autoCps) * dt
		S.PlaySeconds += dt
		S.Bounces += r.Stats.DVDCount * B.BounceRate * dt
		if f.Combo then
			S.CombosMaxed += dt / B.ClickCycle
		end
		if f.BubbleWrap then
			S.BubblesPopped += B.BubblesPerSecond * dt
		end
		if f.GoldenStar then
			S.GoldenClicks += B.Catch.Golden * dt / 65
		end
		if f.Weather then
			S.LightningClicks += B.Catch.Lightning * dt / 25
		end
		if f.PhoneNotifs then
			S.NotifsOpened += B.Catch.Notif * dt / 14
		end
		if f.Email then
			S.EmailsRead += B.Catch.Email * dt / 32.5
		end
		if f.PressStart then
			S.PressCrushes += dt / B.Attention.Press
		end
		if f[Config.Casino.Feature] then
			S.SlotSpins += dt / Config.Casino.TokenInterval
			S.SlotWins += casinoWin * dt / Config.Casino.TokenInterval
		end
		if f[Config.Garden.Feature] then
			S.GardenHarvests += r.Plots * dt / gardenCycle
		end
		if f[Config.LootBox.Feature] then
			S.ChestsOpened += dt / Config.LootBox.ChargeInterval
		end
		if f.Quests then
			S.QuestsCompleted += dt / B.QuestEvery
		end
		if f.Minigames then
			S.MinigamesWon += B.ArcadeWinsPerHour * dt / 3600
		end
		t += dt
		sessionSeconds += dt

		if t >= nextSample then
			sample(t)
			nextSample += sampleEvery
		end

		if t >= nextDecision then
			nextDecision += B.DecisionEvery
			checkAchievements()
			if ratesVersion ~= decidedVersion or data.Dopamine >= nextThreshold or t >= lastDecisionAt + 30 then
			lastDecisionAt = t
			for _ = 1, 20 do -- plusieurs achats d'un coup si possible
				local bought = tryPurchase()
				if bought == "Ocean" then
					detox()
					result.RebirthAt[data.Rebirths] = t
					result.RebirthDay[data.Rebirths] = day
					table.insert(result.Log, string.format("R%d à %s (partie de %s)", data.Rebirths, N.Time(t), N.Time(t - lastRebirthAt)))
					if SIM_DEBUG then print("DEBUG R", data.Rebirths, t, data.Stats.LifetimeDopamine) end
					lastRebirthAt = t
					checkAchievements()
					break
				elseif not bought then
					break
				end
			end
			rates = rates or computeRates()
			decidedVersion = ratesVersion
			end
		end

		-- Fin de la séance du jour : hors-ligne jusqu'au lendemain
		if profile.SessionHours and sessionSeconds >= profile.SessionHours * 3600 then
			sessionSeconds = 0
			local away = (24 - profile.SessionHours) * 3600
			local stats = Formulas.ComputeStats(data, 1, passMult * Formulas.GetHouseBonus(comfort))
			earn(Formulas.GetOfflineReward(data, stats.PerSecond, away))
			day += 1
			claimDaily()
			rates = nil
		end
	end
	sample(t)
	result.EndT = t
	result.Rebirths = data.Rebirths
	result.ReachedMax = data.Rebirths >= maxRebirths
	result.Data = data
	return result
end

----------------------------------------------------------------------
-- Rapport
----------------------------------------------------------------------
local function minutes(seconds: number?): string
	if not seconds then
		return "-"
	end
	return tostring(math.floor(seconds / 60 + 0.5))
end

-- Durées des parties en minutes : { [n] = minutes de la n-ième partie }
function Sim.RunMinutes(result)
	local list = {}
	local last = 0
	for n = 1, result.Rebirths do
		local at = result.RebirthAt[n]
		if not at then
			break
		end
		list[n] = (at - last) / 60
		last = at
	end
	return list
end

function Sim.Report(result)
	print("==== " .. result.Profile .. " ====")
	local runs = Sim.RunMinutes(result)
	local line1, line2, line3 = { "Rn     " }, { "cumul  " }, { "partie " }
	for n = 1, 10 do
		table.insert(line1, string.format("%6s", "R" .. n))
		table.insert(line2, string.format("%6s", result.RebirthAt[n] and minutes(result.RebirthAt[n]) or "-"))
		table.insert(line3, string.format("%6s", runs[n] and tostring(math.floor(runs[n] + 0.5)) or "-"))
	end
	print(table.concat(line1, ""))
	print(table.concat(line2, "") .. "   (minutes de jeu actif)")
	print(table.concat(line3, ""))
	if next(result.RebirthDay) then
		local days = { "jour   " }
		for n = 1, 10 do
			table.insert(days, string.format("%6s", result.RebirthDay[n] and tostring(result.RebirthDay[n]) or "-"))
		end
		print(table.concat(days, ""))
	end
	print(string.format("fin : %s de jeu, %d visites", N.Time(result.EndT), result.Rebirths))
	print("Achats des 10 premières minutes :")
	local parts = {}
	for _, p in ipairs(result.Purchases) do
		table.insert(parts, string.format("%s %s (%s)", N.Time(p.T), p.Name, N.Format(p.Cost)))
	end
	print("  " .. table.concat(parts, " | "))
	print("  t       R  gains/s     P        clics%  bonus%  xRenais  xAmél  xClic  xSuccès xCosm  xMaison confort")
	for _, s in ipairs(result.Samples) do
		if s.T % 1800 < 600 or s.T <= 1200 then
			print(string.format("  %-7s %-2d %-9s %-9s %5.0f%% %6.0f%%  x%-6s x%-5s x%-5s x%-6s x%-5s x%-6s %d",
				N.Time(s.T), s.Rebirths, N.Format(s.Income), N.Format(s.P),
				100 * s.Clicks / math.max(1e-9, s.Clicks + s.Passive + s.Bonus),
				100 * s.Bonus / math.max(1e-9, s.Clicks + s.Passive + s.Bonus),
				N.Format(s.Rebirth), N.Format(s.Upgrade), N.Format(s.ClickMult), N.Format(s.Achievement),
				N.Format(s.Cosmetic), N.Format(s.House), math.floor(s.Comfort)))
		end
	end
	print("")
end

function Sim.Main(args)
	args = args or {}
	local names = {}
	if args.all then
		names = Sim.ProfileOrder
	else
		table.insert(names, args.profile or "Active")
	end
	for _, name in ipairs(names) do
		local result = Sim.Run(name, { MaxHours = 80 })
		Sim.Report(result)
	end
end

return Sim
