#!/usr/bin/env python3
"""
Tests logiques de Dopamine Clicker (hors Roblox).

Assemble les modules Shared (Config, NumberFormatter, Formulas, DVDMath) en un
seul script Luau avec de petits "faux" objets Roblox (Vector2, Color3, script,
require), puis l'exécute avec le Luau CLI.

Vérifie aussi que chaque chemin "Config.X.Y" utilisé dans src/ existe bien
dans Shared/Config.luau.

Usage : python3 tests/run_tests.py [--luau /tmp/luau/luau]
Affiche PASS / FAIL pour chaque test ; code de sortie 1 si un test échoue.
"""

import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHARED = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared")
SRC = os.path.join(ROOT, "src")
LUAU = "/tmp/luau/luau"
if "--luau" in sys.argv:
    LUAU = sys.argv[sys.argv.index("--luau") + 1]

MODULES = ["Config", "NumberFormatter", "Formulas", "DVDMath", "ChatTopics"]

HEADER = r"""
-- Faux objets Roblox (juste ce qu'il faut pour les modules Shared)
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
Color3 = {
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
	new = function(r, g, b) return { R = r, G = g, B = b } end,
}
local modules, loaders = {}, {}
local function req(name)
	if modules[name] == nil then modules[name] = loaders[name]() end
	return modules[name]
end
local script = { Parent = { Config = "Config", NumberFormatter = "NumberFormatter", Formulas = "Formulas", DVDMath = "DVDMath" } }
"""

TESTS = r"""
local Config = req("Config")
local Formulas = req("Formulas")
local N = req("NumberFormatter")
local DVD = req("DVDMath")

local results = { pass = 0, fail = 0 }
local function test(name, fn)
	local failures = {}
	local function check(cond, msg)
		if not cond then table.insert(failures, msg or "?") end
	end
	local ok, err = pcall(fn, check)
	if not ok then table.insert(failures, "erreur : " .. tostring(err)) end
	if #failures == 0 then
		results.pass += 1
		print("PASS " .. name)
	else
		results.fail += 1
		print("FAIL " .. name)
		for i, f in ipairs(failures) do
			if i > 12 then print("    ... (" .. (#failures - 12) .. " de plus)") break end
			print("    - " .. f)
		end
	end
end
local function eq(check, a, b, msg)
	check(a == b, (msg or "") .. " : " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) * math.max(1, math.abs(b)) end

------------------------------------------------------------------ NumberFormatter
test("NumberFormatter.Format", function(check)
	eq(check, N.Format(0), "0", "0")
	eq(check, N.Format(999), "999", "999")
	eq(check, N.Format(2.5), "2.5", "2.5")
	eq(check, N.Format(1000), "1K", "1K")
	eq(check, N.Format(1234), "1.23K", "1.23K")
	eq(check, N.Format(999999), "999.99K", "troncature")
	eq(check, N.Format(1e6), "1M", "1M")
	eq(check, N.Format(1.5e9), "1.5B", "1.5B")
	eq(check, N.Format(1e12), "1T", "1T")
	eq(check, N.Format(1e15), "1Qa", "1Qa")
	eq(check, N.Format(-1500), "-1.5K", "négatif")
	eq(check, N.Format(0 / 0), "0", "NaN")
	eq(check, N.Format(math.huge), "∞", "inf")
	for e = 3, 65 do
		local s = N.Format(10 ^ e)
		check(s:match("^10*%a+$") ~= nil, "10^" .. e .. " -> " .. s)
	end
	local s = N.Format(1e300)
	check(s:find("e") ~= nil, "1e300 notation scientifique : " .. s)
end)

test("NumberFormatter.WithSpaces / Time / Multiplier", function(check)
	eq(check, N.WithSpaces(0), "0")
	eq(check, N.WithSpaces(123), "123")
	eq(check, N.WithSpaces(1234), "1 234")
	eq(check, N.WithSpaces(123456), "123 456")
	eq(check, N.WithSpaces(1234567), "1 234 567")
	eq(check, N.WithSpaces(999.9), "999", "floor")
	eq(check, N.Time(9), "9s")
	eq(check, N.Time(252), "4m 12s")
	eq(check, N.Time(3725), "1h 02m")
	eq(check, N.Time(-5), "0s")
	eq(check, N.Multiplier(2), "x2")
	eq(check, N.Multiplier(1.5), "x1.5")
	eq(check, N.Multiplier(2500), "x2.5K")
end)

------------------------------------------------------------------ Config
test("Config : cohérence des améliorations", function(check)
	local ids = {}
	for i, u in ipairs(Config.Upgrades) do
		check(not ids[u.Id], "Id en double " .. tostring(u.Id))
		ids[u.Id] = true
		eq(check, u.Order, i, "Order " .. u.Id)
		check(type(u.Name) == "string" and type(u.Icon) == "string", "Name/Icon " .. u.Id)
		check(type(u.Cost) == "number" and u.Cost >= 0, "Cost " .. u.Id)
		check(type(u.CostGrowth) == "number" and u.CostGrowth >= 1, "CostGrowth " .. u.Id)
		local okEffect = ({ Click = 1, PerSecond = 1, DVD = 1, BounceMultiplier = 1, ClickMultiplier = 1, Multiplier = 1, Feature = 1, Detox = 1, Offline = 1 })[u.Effect]
		check(okEffect ~= nil, "Effect inconnu " .. u.Id .. " " .. tostring(u.Effect))
		if u.Effect ~= "Feature" and u.Effect ~= "Detox" and u.Effect ~= "DVD" then
			check(type(u.Value) == "number", "Value manquante " .. u.Id)
		end
		if u.Feature then
			eq(check, Config.FeatureToUpgrade[u.Feature], u.Id, "Feature unique " .. u.Feature)
		end
	end
	eq(check, Config.Upgrades[#Config.Upgrades].Effect, "Detox", "Ocean est la dernière")
	-- Toutes les Features utilisées ailleurs existent
	for kind, s in pairs(Config.Spawners) do
		check(Config.FeatureToUpgrade[s.Feature] ~= nil, "Spawner " .. kind .. " Feature " .. tostring(s.Feature))
	end
	for kind, s in pairs(Config.Interactions) do
		check(Config.FeatureToUpgrade[s.Feature] ~= nil, "Interaction " .. kind .. " Feature " .. tostring(s.Feature))
	end
	for _, q in ipairs(Config.Quests.Pool) do
		if q.Feature then check(Config.FeatureToUpgrade[q.Feature] ~= nil, "Quête " .. q.Type .. " Feature " .. q.Feature) end
		check(q.Text:find("%s", 1, true) ~= nil, "Quête " .. q.Type .. " sans %s")
	end
	check(Config.FeatureToUpgrade[Config.Garden.Feature] ~= nil, "Garden.Feature")
	for _, u in ipairs(Config.Upgrades) do
		if u.Requires then check(Config.UpgradesById[u.Requires] ~= nil, "Requires inconnu : " .. u.Id) end
		check(u.RequiresRebirths == nil or u.RequiresRebirths >= 1, "RequiresRebirths " .. u.Id)
	end
	check(Config.FeatureToUpgrade[Config.Casino.Feature] ~= nil, "Casino.Feature")
	check(Config.FeatureToUpgrade[Config.LootBox.Feature] ~= nil, "LootBox.Feature")
	for _, c in ipairs(Config.Cosmetics) do
		check(c.Slot == "Hat" or c.Slot == "Skin", "Slot cosmétique " .. c.Id)
		if c.Slot == "Skin" then check(c.Top ~= nil and c.Bottom ~= nil, "Skin sans couleurs " .. c.Id) end
	end
end)

------------------------------------------------------------------ Formulas
local function emptyData()
	return { Upgrades = {}, Rebirths = 0, Achievements = {}, Cosmetics = { Owned = {}, Equipped = { Hat = "", Skin = "" } }, Stats = {} }
end

test("Formulas.ComputeStats", function(check)
	local s = Formulas.ComputeStats(emptyData(), nil)
	eq(check, s.ClickValue, 1, "clic de base")
	eq(check, s.PerSecond, 0, "ps de base")
	eq(check, s.DVDCount, 0, "dvd de base")
	eq(check, s.BounceValue, Config.DVD.BaseBounceValue, "rebond de base")
	eq(check, s.GlobalMultiplier, 1, "global de base")

	local U = Config.UpgradesById
	local d = emptyData()
	d.Upgrades = { Finger = 3, DVD = 2, DVDSound = 1, Megaphone = 1, NewsTicker = 1, Press = 2, Boost = 1 }
	d.Rebirths = 2
	d.Achievements = { Clicks100 = true, Bogus = true }
	d.Cosmetics.Owned = { Cap = true, NotACosmetic = true }
	local st = Formulas.ComputeStats(d, 2)
	local global = U.Boost.Value * Formulas.GetRebirthMultiplier(2) * (1 + Config.AchievementBonus) * (1 + Config.CosmeticBonus) * 2
	check(near(st.GlobalMultiplier, global), "global " .. st.GlobalMultiplier .. " vs " .. global)
	check(near(st.ClickValue, (1 + 3 * U.Finger.Value) * U.Megaphone.Value * global), "ClickValue " .. st.ClickValue)
	check(near(st.PerSecond, (U.NewsTicker.Value + 2 * U.Press.Value) * global), "PerSecond " .. st.PerSecond)
	eq(check, st.DVDCount, 2, "DVDCount")
	check(near(st.BounceValue, Config.DVD.BaseBounceValue * U.DVDSound.Value * global), "BounceValue")
	eq(check, st.EventMultiplier, 2, "EventMultiplier")

	-- Features / HasFeature
	local f = Formulas.GetFeatures(d)
	check(f.DVD and f.DVDSound and f.Megaphone and f.NewsTicker and f.Press and f.Boost, "GetFeatures")
	check(not f.Combo, "Combo non possédé")
	check(Formulas.HasFeature(d, "Press") and not Formulas.HasFeature(d, "Casino"), "HasFeature")
	check(not Formulas.HasFeature(d, "Inexistant"), "HasFeature inconnu")
	-- Toutes les améliorations : pas de NaN / infini
	local all = emptyData()
	for _, u in ipairs(Config.Upgrades) do all.Upgrades[u.Id] = u.MaxLevel or 1 end
	local sa = Formulas.ComputeStats(all, 2)
	for k, v in pairs(sa) do check(v == v and v ~= math.huge, "stat " .. k .. " = " .. tostring(v)) end
	-- ScaledReward
	local r = Formulas.ScaledReward(st, 10, 5)
	check(near(r, math.floor((st.PerSecond + st.ClickValue * Config.Rewards.EstimatedClicksPerSecond) * 10)), "ScaledReward")
	eq(check, Formulas.ScaledReward(s, 0, 42), 42, "ScaledReward minimum")
end)

test("Formulas.GetUpgradeCost (Detox compris)", function(check)
	local U = Config.UpgradesById
	eq(check, Formulas.GetUpgradeCost(U.Finger, 0, 0), U.Finger.Cost, "niveau 0")
	eq(check, Formulas.GetUpgradeCost(U.Finger, 1, 0), math.floor(U.Finger.Cost * U.Finger.CostGrowth + 0.5), "niveau 1")
	-- (v9.3) Après r visites, les améliorations non permanentes coûtent GetUpgradePriceScale(r) fois plus
	local R = Config.Rebirth
	eq(check, Formulas.GetUpgradePriceScale(0), 1, "échelle des prix 0")
	check(near(Formulas.GetUpgradePriceScale(3), (R.PriceGrowth or 1) ^ 3 * 4 ^ (R.PricePower or 0)), "échelle des prix 3")
	eq(check, Formulas.GetUpgradeCost(U.Finger, 3, 5), math.floor(U.Finger.Cost * U.Finger.CostGrowth ^ 3 * Formulas.GetUpgradePriceScale(5) + 0.5), "prix x échelle")
	eq(check, Formulas.GetUpgradeCost(U.SleepMode, 1, 5), Formulas.GetUpgradeCost(U.SleepMode, 1, 0), "permanente : même prix")
	local lastScale = 0
	for r = 0, 30 do
		local scale = Formulas.GetUpgradePriceScale(r)
		check(scale > lastScale, "échelle croissante " .. r)
		lastScale = scale
	end
	eq(check, Formulas.GetUpgradeCost(U.Ocean, 0, 0), R.BaseCost, "océan 0")
	check(near(Formulas.GetUpgradeCost(U.Ocean, 0, 2), R.BaseCost * R.CostGrowth ^ 2 * 3 ^ (R.CostPower or 0)), "océan 2")
	eq(check, Formulas.GetRebirthCost(0 / 0), R.BaseCost, "océan NaN")
	eq(check, Formulas.GetRebirthCost(-3), R.BaseCost, "océan négatif")
	eq(check, Formulas.GetUpgradeCost(U.Ocean, 0, nil), Config.Rebirth.BaseCost, "océan nil")
	check(not Formulas.IsMaxed(U.Ocean, 1000), "océan jamais au max")
	check(Formulas.IsMaxed(U.NewsTicker, 1) and not Formulas.IsMaxed(U.NewsTicker, 0), "IsMaxed")
	for _, u in ipairs(Config.Upgrades) do
		local last = -1
		for level = 0, (u.MaxLevel or 3) - 1 do
			local c = Formulas.GetUpgradeCost(u, level, 0)
			check(c == c and c >= last, "coût croissant " .. u.Id .. " niv " .. level)
			last = c
		end
	end
	eq(check, Formulas.GetRebirthMultiplier(0), 1, "mult 0")
	eq(check, Formulas.GetRebirthMultiplier(1), 1 + R.MultiplierPerRebirth, "mult 1")
	check(near(Formulas.GetRebirthMultiplier(2), 1 + R.MultiplierPerRebirth * (1 + (R.MultiplierDecay or 1))), "mult 2")
	local lastMult, lastGain = 1, math.huge
	for r = 1, 30 do
		local m = Formulas.GetRebirthMultiplier(r)
		check(m > lastMult, "multiplicateur croissant " .. r)
		check(m - lastMult <= lastGain + 1e-9, "gain par visite décroissant " .. r)
		lastGain = m - lastMult
		lastMult = m
		-- Chaque visite coûte bien plus que la précédente, plus vite que le multiplicateur ne grandit
		check(Formulas.GetRebirthCost(r) / Formulas.GetRebirthCost(r - 1) > m / Formulas.GetRebirthMultiplier(r - 1), "océan plus cher que le gain " .. r)
	end
end)

test("Formulas.GetVisibleUpgrades : progression", function(check)
	local d = emptyData()
	local first = Formulas.GetVisibleUpgrades(d)
	eq(check, #first, Config.UpgradeBar.RevealAhead, "au début")
	for i, u in ipairs(first) do eq(check, u, Config.Upgrades[i], "ordre au début " .. i) end
	-- Nouveautés des renaissances : cachées au début, visibles avec assez de visites
	for _, u in ipairs(Config.Upgrades) do
		if u.RequiresRebirths then check(not Formulas.IsUpgradeUnlocked(d, u), "verrouillée au début : " .. u.Id) end
	end
	local gate, gateCount = Formulas.GetNextRebirthUnlocks(d)
	check(gate == 1 and gateCount >= 1, "prochaine nouveauté à la 1re visite")
	d.Rebirths = 10
	-- Achète toujours la moins chère visible (hors océan) jusqu'à tout avoir
	local seen = {}
	local steps = 0
	while steps < 1000 do
		steps += 1
		local visible = Formulas.GetVisibleUpgrades(d)
		local notOwned = 0
		for _, u in ipairs(visible) do
			seen[u.Id] = true
			check(not Formulas.IsMaxed(u, d.Upgrades[u.Id] or 0), "visible mais au max : " .. u.Id)
			if (d.Upgrades[u.Id] or 0) == 0 then notOwned += 1 end
		end
		check(notOwned <= Config.UpgradeBar.RevealAhead, "trop de nouvelles visibles : " .. notOwned)
		local best, bestCost
		for _, u in ipairs(visible) do
			if u.Effect ~= "Detox" then
				local c = Formulas.GetUpgradeCost(u, d.Upgrades[u.Id] or 0, d.Rebirths)
				if not bestCost or c < bestCost then best, bestCost = u, c end
			end
		end
		if not best then break end
		d.Upgrades[best.Id] = (d.Upgrades[best.Id] or 0) + 1
	end
	for _, u in ipairs(Config.Upgrades) do check(seen[u.Id], "jamais visible : " .. u.Id) end
	local final = Formulas.GetVisibleUpgrades(d)
	eq(check, #final, 1, "à la fin il ne reste que l'océan")
	eq(check, final[1] and final[1].Id, "Ocean", "dernière carte")
	-- Après la détox : seules les permanentes restent
	local kept = {}
	for id, level in pairs(d.Upgrades) do
		if Config.UpgradesById[id].Permanent then kept[id] = level end
	end
	d.Upgrades = kept
	d.Rebirths = 1
	local after = Formulas.GetVisibleUpgrades(d)
	check(#after >= Config.UpgradeBar.RevealAhead, "après détox : " .. #after)
	eq(check, after[1].Id, "Finger", "après détox, Doigt en premier")
	local features = Formulas.GetFeatures(d)
	for f in pairs(features) do
		check(Config.UpgradesById[Config.FeatureToUpgrade[f]].Permanent, "feature non permanente gardée : " .. f)
	end
end)

test("Formulas.DescribeUpgrade (aucun %s restant)", function(check)
	for _, u in ipairs(Config.Upgrades) do
		for _, fmt in ipairs({ N.Format, N.Multiplier }) do
			local text = Formulas.DescribeUpgrade(u, fmt, 0)
			check(type(text) == "string" and #text > 0, "vide : " .. u.Id)
			check(not text:find("%s", 1, true), "%s restant : " .. u.Id .. " -> " .. text)
			check(not text:find("nan", 1, true), "nan : " .. u.Id)
		end
	end
	local ocean = Formulas.DescribeUpgrade(Config.UpgradesById.Ocean, N.Multiplier, 1)
	check(ocean:find(N.Multiplier(Formulas.GetRebirthMultiplier(2)), 1, true) ~= nil, "océan montre le prochain mult : " .. ocean)
	-- Traduction (optionnelle) appliquée AVANT de remplacer %s
	local fake = { Description = "+%s per click", Value = 3, Effect = "Click" }
	local translated = Formulas.DescribeUpgrade(fake, N.Format, 0, function(text)
		return text == "+%s per click" and "+%s par clic" or text
	end)
	eq(check, translated, "+3 par clic", "traduction")
	eq(check, Formulas.DescribeUpgrade(fake, N.Format, 0), "+3 per click", "sans traduction")
	eq(check, Formulas.DescribeUpgrade(fake, N.Format, 0, function() error("x") end), "+3 per click", "traduction en erreur")
end)

test("Formulas machine chanceuse (tours gratuits, gains en secondes)", function(check)
	local rtp = Formulas.GetCasinoRTP()
	print(string.format("    gain moyen par tour = %.1f s de production", rtp))
	check(rtp >= 5 and rtp <= 60, "gain moyen hors 5-60 s : " .. rtp)
	check(Config.Casino.TokenInterval > 0 and Config.Casino.MaxTokens >= Config.Casino.StartTokens, "jetons")
	local S = Config.Casino.Symbols
	eq(check, Formulas.GetCasinoMultiplier({ S[1].Id, S[1].Id, S[1].Id }), S[1].Triple, "triple")
	eq(check, Formulas.GetCasinoMultiplier({ S[2].Id, S[2].Id, S[1].Id }), S[2].Pair, "paire")
	eq(check, Formulas.GetCasinoMultiplier({ S[1].Id, S[2].Id, S[3].Id }), 0, "perdu")
	eq(check, Formulas.GetCasinoMultiplier({ "x", "x", "x" }), 0, "inconnu")
	for _, s in ipairs(S) do check(Config.CasinoSymbolsById[s.Id] == s, "index " .. s.Id) end

end)

test("Formulas combo", function(check)
	eq(check, Formulas.GetComboMultiplier(0), 1, "min")
	eq(check, Formulas.GetComboMultiplier(100), Config.Combo.MaxMultiplier, "max")
	eq(check, Formulas.GetComboMultiplier(500), Config.Combo.MaxMultiplier, "borné")
	local m = 0
	for _ = 1, 200 do m = Formulas.StepCombo(m, 0.1) end
	eq(check, m, 100, "10 clics/s remplit la jauge")
	m = 0
	for _ = 1, 200 do m = Formulas.StepCombo(m, 1) end
	eq(check, m, Config.Combo.GainPerClick, "1 clic/s")
end)

------------------------------------------------------------------ DVDMath
test("DVDMath : positions dans l'écran et comptage des rebonds", function(check)
	math.randomseed(1234)
	local totalCounted, totalExpected = 0, 0
	for trial = 1, 200 do
		local w, h = 0.05 + math.random() * 0.2, 0.05 + math.random() * 0.2
		local speed = Config.DVD.Speed * (1 + (math.random() * 2 - 1) * Config.DVD.SpeedVariation)
		local ang = math.rad(20 + math.random() * 50)
		local p = {
			X0 = math.random() * (1 - w), Y0 = math.random() * (1 - h),
			VX = math.cos(ang) * speed * (math.random() < 0.5 and -1 or 1),
			VY = math.sin(ang) * speed * (math.random() < 0.5 and -1 or 1),
			T0 = 1.7e9 + math.random() * 1000, W = w, H = h,
		}
		local rangeX, rangeY = DVD.Ranges(p)
		-- 1) "client" : 60 images/s pendant 90 s, compte les changements de BounceIndex
		local t = p.T0
		local lastX, lastY = DVD.BounceIndex(p, t)
		local clientCount = 0
		for _ = 1, 60 * 90 do
			t += 1 / 60
			local x, y = DVD.Position(p, t)
			if not (x >= -1e-9 and x <= rangeX + 1e-9 and y >= -1e-9 and y <= rangeY + 1e-9) then
				check(false, "hors écran essai " .. trial)
				break
			end
			local ix, iy = DVD.BounceIndex(p, t)
			if ix ~= lastX then
				clientCount += math.abs(ix - lastX)
				-- l'heure exacte du rebond est bien dans cette image
				local k = math.max(ix, lastX)
				local tb = DVD.BounceTimeX(p, k)
				check(tb <= t + 1e-6 and tb >= t - 1 / 60 - 1e-6, "BounceTimeX essai " .. trial)
				local bx = DVD.Position(p, tb)
				check(math.abs(bx) < 1e-6 or math.abs(bx - rangeX) < 1e-6, "rebond X au bord essai " .. trial)
			end
			clientCount += math.abs(iy - lastY)
			lastX, lastY = ix, iy
		end
		-- 2) "serveur" : tick de 0.25 s (comme GameService), même intervalle
		local ts = p.T0
		local sx, sy = DVD.BounceIndex(p, ts)
		local serverCount = 0
		for _ = 1, 90 * 4 do
			ts += 0.25
			local ix, iy = DVD.BounceIndex(p, ts)
			serverCount += math.abs(ix - sx) + math.abs(iy - sy)
			sx, sy = ix, iy
		end
		eq(check, clientCount, serverCount, "client vs serveur essai " .. trial)
		-- 3) taux théorique : |VX|/rangeX + |VY|/rangeY rebonds par seconde
		local expected = 90 * (math.abs(p.VX) / rangeX + math.abs(p.VY) / rangeY)
		check(math.abs(serverCount - expected) <= 2.01, string.format("taux essai %d : %d vs %.2f", trial, serverCount, expected))
		totalCounted += serverCount
		totalExpected += expected
	end
	print(string.format("    rebonds comptés %d / attendus %.1f", totalCounted, totalExpected))
	check(math.abs(totalCounted - totalExpected) / totalExpected < 0.01, "écart global > 1 %")
end)

test("DVDMath : coins et directions", function(check)
	-- Logo carré qui part d'un coin en diagonale : coin à chaque rebond X
	local p = { X0 = 0, Y0 = 0, VX = 0.1, VY = 0.1, T0 = 0, W = 0.2, H = 0.2 }
	for k = 1, 5 do
		check(DVD.IsCornerAtBounceX(p, k, Config.DVD.CornerTolerance), "coin k=" .. k)
	end
	local q = { X0 = 0, Y0 = 0.3, VX = 0.1, VY = 0.137, T0 = 0, W = 0.2, H = 0.1 }
	check(not DVD.IsCornerAtBounceX(q, 1, Config.DVD.CornerTolerance), "pas de coin")
	local dx, dy = DVD.Directions(p, 1)
	eq(check, dx, 1, "dir x") eq(check, dy, 1, "dir y")
	dx = DVD.Directions(p, 9)
	eq(check, dx, -1, "dir x après rebond")
	eq(check, DVD.Triangle(1.3, 1), 0.7, "triangle")
	check(near(DVD.Triangle(-0.25, 1), 0.25), "triangle négatif")
end)

------------------------------------------------------------------ ChatTopics (LIVE v9)
test("ChatTopics.Detect : sujets FR/EN, argot, emojis, négations", function(check)
	local CT = req("ChatTopics")
	local function has(text, topic)
		for _, t in ipairs(CT.Detect(text)) do
			if t == topic then return true end
		end
		return false
	end
	local function first(text) return CT.Detect(text)[1] end
	eq(check, first("salut tout le monde !"), "Greeting", "salut")
	eq(check, first("helloooo"), "Greeting", "lettres répétées")
	eq(check, first("coucouuu 👋"), "Greeting", "coucou + emoji")
	eq(check, first("bonne nuit les amis"), "Bye", "bonne nuit")
	eq(check, first("je t'aime trop"), "Love", "je t'aime")
	eq(check, first("t'es nulle"), "Mean", "nulle")
	check(not has("pas mal ce live", "Mean") and has("pas mal ce live", "Compliment"), "négation : pas mal = compliment")
	check(has("tu manges quoi ?", "Question") and has("tu manges quoi ?", "Food"), "question + nourriture")
	eq(check, first("mdrrrr"), "Laugh", "mdr répété")
	eq(check, first("hahahaha"), "Laugh", "haha*")
	eq(check, first("😂😂"), "Laugh", "emoji")
	check(#CT.Detect("le chat va trop vite") == 0, "« chat » (le chat du live) n'est pas un animal")
	eq(check, first("my cat is here"), "Pet", "cat")
	check(has("how old are you", "Age") and has("tu as quel âge ?", "Age"), "âge EN / FR (accents)")
	eq(check, first("j'ai un contrôle demain"), "School", "contrôle (accent)")
	check(#CT.Detect("test") == 0, "« test » n'est pas l'école")
	check(#CT.Detect("") == 0 and #CT.Detect(nil) == 0, "vide / nil")
	check(#CT.Detect(string.rep("hello love pizza lol sleep cat rain ", 20)) <= 4, "4 sujets au plus")
	for _, topic in ipairs(CT.Order) do
		check(type(CT.Keywords[topic]) == "table" and #CT.Keywords[topic] > 0, "mots-clés " .. topic)
	end
end)

------------------------------------------------------------------ Maison 🏠
-- Un seul emoji : pas de ZWJ (U+200D) ni de couleur de peau (U+1F3FB..1F3FF),
-- au plus 2 points de code (le 2e ne peut être que le sélecteur U+FE0F)
local function isSingleEmoji(text)
	if type(text) ~= "string" or #text == 0 or not utf8.len(text) then return false end
	local codes = {}
	for _, code in utf8.codes(text) do table.insert(codes, code) end
	if #codes == 0 or #codes > 2 then return false end
	if codes[1] < 0x2000 then return false end
	if #codes == 2 and codes[2] ~= 0xFE0F then return false end
	for _, code in ipairs(codes) do
		if code == 0x200D or (code >= 0x1F3FB and code <= 0x1F3FF) then return false end
	end
	return true
end

test("Config.House : catalogue (ids, catégories, zones, motifs, prix)", function(check)
	local H = Config.House
	check(type(H) == "table", "Config.House manquant")
	check(H.ComfortBonusPerPoint > 0 and H.ComfortBonusPerPoint <= 0.005 and H.MaxComfortBonus > 0 and H.MaxComfortBonus <= 2
		and H.WallRatio > 0.3 and H.WallRatio < 0.6, "réglages")

	-- Tailles : dans l'ordre, de plus en plus grandes
	local sizeIds = { "Studio", "Apartment", "Loft", "Mansion" }
	eq(check, #H.Sizes, 4, "nombre de tailles")
	for i, size in ipairs(H.Sizes) do
		eq(check, size.Id, sizeIds[i], "taille " .. i)
		check(type(size.Name) == "string" and isSingleEmoji(size.Icon), "Name/Icon taille " .. tostring(size.Id))
		eq(check, Config.HouseSizesById[size.Id], size, "index taille " .. size.Id)
		eq(check, size.Order, i, "Order taille " .. size.Id)
		if i > 1 then
			local prev = H.Sizes[i - 1]
			check(size.Cost > prev.Cost and size.Width >= prev.Width and size.RoomItems >= prev.RoomItems
				and size.MaxRooms > prev.MaxRooms, "taille croissante " .. size.Id)
		end
		check(size.Floors >= 1 and size.Columns >= 1 and size.MaxRooms == size.Floors * size.Columns, "grille " .. size.Id)
		check(({ Cottage = true, Townhouse = true, Loft = true, Mansion = true })[size.Exterior] == true, "Exterior " .. size.Id)
	end
	eq(check, H.Sizes[1].Cost, 0, "studio gratuit")
	eq(check, H.Sizes[1].MaxRooms, 2, "studio 2 pièces")
	eq(check, H.Sizes[4].MaxRooms, 12, "manoir 12 pièces")

	-- Types de pièces : styles et objets préférés existants
	check(#H.RoomTypes >= 10, "au moins 10 types de pièces")
	eq(check, H.RoomTypes[1].Id, "Living", "1er type = salon")
	for _, roomType in ipairs(H.RoomTypes) do
		local id = tostring(roomType.Id)
		eq(check, Config.HouseRoomTypesById[roomType.Id], roomType, "index type " .. id)
		check(type(roomType.Name) == "string" and isSingleEmoji(roomType.Icon), "Name/Icon type " .. id)
		check(Config.HouseWallpapersById[roomType.Wallpaper] ~= nil, "papier peint du type " .. id)
		check(Config.HouseFloorsById[roomType.Floor] ~= nil, "sol du type " .. id)
		for _, categoryId in ipairs(roomType.Categories) do
			check(Config.HouseCategoriesById[categoryId] ~= nil, "catégorie préférée " .. id .. " " .. tostring(categoryId))
		end
		for _, itemId in ipairs(roomType.Items) do
			check(Config.HouseItemsById[itemId] ~= nil, "objet préféré " .. id .. " " .. tostring(itemId))
		end
		check(#roomType.Categories + #roomType.Items > 0, "type sans préférés " .. id)
	end
	check(H.RoomCost > 0 and H.RoomCostGrowth > 1 and H.HarmonyBonus > 0, "prix des pièces / harmonie")

	-- Papiers peints et sols
	local function checkSkins(list, lookup, patterns, minCount, label)
		check(#list >= minCount, label .. " : " .. #list .. " < " .. minCount)
		eq(check, list[1].Cost, 0, label .. " : le 1er est gratuit")
		local ids = {}
		for i, skin in ipairs(list) do
			check(type(skin.Id) == "string" and not ids[skin.Id], label .. " Id en double " .. tostring(skin.Id))
			ids[skin.Id] = true
			eq(check, lookup[skin.Id], skin, label .. " index " .. skin.Id)
			check(type(skin.Name) == "string" and #skin.Name > 0, label .. " Name " .. skin.Id)
			check(skin.Icon == nil or isSingleEmoji(skin.Icon), label .. " Icon " .. skin.Id)
			check(patterns[skin.Pattern] == true, label .. " Pattern invalide " .. skin.Id .. " " .. tostring(skin.Pattern))
			check(type(skin.A) == "table" and type(skin.B) == "table", label .. " couleurs " .. skin.Id)
			check(type(skin.Cost) == "number" and skin.Cost >= 0 and skin.Cost == math.floor(skin.Cost), label .. " Cost " .. skin.Id)
			if i > 1 then check(skin.Cost > 0, label .. " seul le 1er est gratuit : " .. skin.Id) end
		end
	end
	checkSkins(H.Wallpapers, Config.HouseWallpapersById, { Plain = true, Stripes = true, Checker = true, Dots = true, Hearts = true,
		Stars = true, Clouds = true, Bricks = true, Wood = true, Waves = true,
		Plaid = true, Flowers = true, Diamonds = true, Chevron = true, Moons = true,
		-- v9.2
		Flag = true, Bolts = true, Camo = true, Racing = true, Carbon = true, Graffiti = true, Planets = true, NeonGrid = true }, 39, "Papier peint")
	checkSkins(H.Floors, Config.HouseFloorsById, { Plain = true, Checker = true, Wood = true, Tiles = true, Carpet = true,
		Marble = true, Herringbone = true, Terrazzo = true, Mosaic = true, Grass = true, Clouds = true, Starry = true,
		-- v9.2
		Concrete = true, Court = true, Turf = true, TreadPlate = true, Road = true, Lava = true }, 30, "Sol")
	eq(check, H.Wallpapers[1].Pattern, "Stripes", "1er papier peint : rayures roses")
	eq(check, H.Floors[1].Pattern, "Checker", "1er sol : damier prune")

	-- Catégories
	local categoryIds = { "Furniture", "Decor", "Toys", "Plants", "Electronics", "Kitchen", "Doors", "Windows", "Lights", "Pets",
		"Gaming", "Sports", "Adventure", "Setup" } -- (v9.2, v9.5 : Dopamine Setup)
	eq(check, #H.Categories, #categoryIds, "nombre de catégories")
	for i, category in ipairs(H.Categories) do
		eq(check, category.Id, categoryIds[i], "catégorie " .. i)
		check(type(category.Name) == "string" and isSingleEmoji(category.Icon), "Name/Icon catégorie " .. tostring(category.Id))
		eq(check, Config.HouseCategoriesById[category.Id], category, "index catégorie " .. category.Id)
	end

	-- Objets
	check(#H.Items >= 90, "au moins 90 objets : " .. #H.Items)
	local ids, perCategory, placements = {}, {}, { Floor = 0, Wall = 0 }
	local minCost, maxCost = math.huge, 0
	for i, item in ipairs(H.Items) do
		local id = tostring(item.Id)
		check(type(item.Id) == "string" and #item.Id > 0 and #item.Id <= 64 and not ids[item.Id], "Id objet invalide/en double " .. id)
		ids[id] = true
		eq(check, item.Order, i, "Order " .. id)
		eq(check, Config.HouseItemsById[id], item, "index " .. id)
		check(type(item.Name) == "string" and #item.Name > 0, "Name " .. id)
		check(isSingleEmoji(item.Icon), "Icon (un seul emoji) " .. id .. " " .. tostring(item.Icon))
		check(Config.HouseCategoriesById[item.Category] ~= nil, "Category " .. id .. " " .. tostring(item.Category))
		perCategory[item.Category] = (perCategory[item.Category] or 0) + 1
		check(item.Placement == "Floor" or item.Placement == "Wall", "Placement " .. id)
		placements[item.Placement] = (placements[item.Placement] or 0) + 1
		if item.Category == "Windows" then eq(check, item.Placement, "Wall", "fenêtre au mur " .. id) end
		if item.Category == "Doors" then eq(check, item.Placement, "Floor", "porte au sol " .. id) end
		check(type(item.Size) == "number" and item.Size >= 40 and item.Size <= 160, "Size 40..160 " .. id)
		-- (v9.3) Cost = prix réel (palier compris), BaseCost = prix d'origine de la config
		check(type(item.BaseCost) == "number" and item.BaseCost >= 100 and item.BaseCost <= 2e9 and item.BaseCost == math.floor(item.BaseCost), "BaseCost " .. id)
		check(type(item.Cost) == "number" and item.Cost >= item.BaseCost and item.Cost <= 1e11 and item.Cost == math.floor(item.Cost), "Cost " .. id)
		check(type(item.RequiresRebirths) == "number", "palier calculé " .. id)
		check(type(item.CostGrowth) == "number" and item.CostGrowth >= 1.1 and item.CostGrowth <= 2, "CostGrowth " .. id)
		check(type(item.Comfort) == "number" and item.Comfort >= 1 and item.Comfort <= 25 and item.Comfort == math.floor(item.Comfort), "Comfort 1..25 " .. id)
		check(item.MaxOwned == nil or (type(item.MaxOwned) == "number" and item.MaxOwned >= 1 and item.MaxOwned == math.floor(item.MaxOwned)), "MaxOwned " .. id)
		minCost = math.min(minCost, item.Cost)
		maxCost = math.max(maxCost, item.Cost)
	end
	for _, category in ipairs(H.Categories) do
		check((perCategory[category.Id] or 0) >= 5, "catégorie trop vide : " .. category.Id .. " (" .. tostring(perCategory[category.Id] or 0) .. ")")
		eq(check, #Config.HouseItemsByCategory[category.Id], perCategory[category.Id] or 0, "HouseItemsByCategory " .. category.Id)
	end
	check(placements.Wall >= 15 and placements.Floor >= 40, "zones : mur " .. placements.Wall .. ", sol " .. placements.Floor)
	check(minCost <= 1000, "objet le moins cher : " .. minCost)
	check(maxCost >= 5e8, "objet le plus cher : " .. maxCost)
	check(Config.HouseItemsById.LoftBed ~= nil, "LoftBed existe")
	print(string.format("    %d objets, prix %s .. %s", #H.Items, N.Format(minCost), N.Format(maxCost)))
end)

test("Formulas maison (prix, confort, bonus)", function(check)
	local H = Config.House
	local bed = Config.HouseItemsById.LoftBed
	eq(check, Formulas.GetHouseItemPrice(bed, 0), bed.Cost, "prix 0")
	eq(check, Formulas.GetHouseItemPrice(bed, 1), math.floor(bed.Cost * bed.CostGrowth), "prix 1")
	eq(check, Formulas.GetHouseItemPrice(bed, 3), math.floor(bed.Cost * bed.CostGrowth ^ 3), "prix 3")
	eq(check, Formulas.GetHouseItemPrice(bed, nil), bed.Cost, "prix nil")
	eq(check, Formulas.GetHouseItemPrice(bed, -4), bed.Cost, "prix négatif")
	eq(check, Formulas.GetHouseItemPrice(bed, 0 / 0), bed.Cost, "prix NaN")
	for _, item in ipairs(H.Items) do
		local last = 0
		for owned = 0, (item.MaxOwned or 10) - 1 do
			local price = Formulas.GetHouseItemPrice(item, owned)
			check(price == price and price >= last and price < 1e300, "prix croissant " .. item.Id .. " x" .. owned)
			last = price
		end
	end

	-- Confort : objets connus, possédés (toutes pièces), au plus RoomItems par pièce
	eq(check, Formulas.GetHouseComfort(nil), 0, "sans données")
	eq(check, Formulas.GetHouseComfort({}), 0, "sans maison")
	eq(check, Formulas.GetHouseComfort({ House = { Placed = "x" } }), 0, "Placed invalide")
	local sofa, rug = Config.HouseItemsById.Sofa, Config.HouseItemsById.KnittedRug
	local living, bedroom = Config.HouseRoomTypesById.Living, Config.HouseRoomTypesById.Bedroom
	local harmony = 1 + H.HarmonyBonus
	check(Formulas.IsRoomFavorite(living, sofa) and not Formulas.IsRoomFavorite(living, bed), "préférés du salon")
	check(Formulas.IsRoomFavorite(bedroom, bed) and Formulas.IsRoomFavorite(living, rug), "préférés (objet / catégorie)")
	-- Ancienne sauvegarde (une seule pièce) : vue comme un salon
	local data = { House = { Size = "Studio", Items = { LoftBed = 1, Sofa = 2 }, Placed = {
		{ I = "LoftBed", X = 0.5, Y = 0.8, S = 1, Z = 0 },
		{ I = "Sofa", X = 0.2, Y = 0.8, S = 1, Z = 1 },
		{ I = "Sofa", X = 0.3, Y = 0.8, S = 1, Z = 2 },
		{ I = "Sofa", X = 0.4, Y = 0.8, S = 1, Z = 3 }, -- 3e canapé : seulement 2 possédés
		{ I = "KnittedRug", X = 0.4, Y = 0.8, S = 1, Z = 3 }, -- pas possédé
		{ I = "Bogus", X = 0.4, Y = 0.8 }, -- inconnu
		"pas une table",
	} } }
	check(near(Formulas.GetHouseComfort(data), bed.Comfort + 2 * sofa.Comfort * harmony), "confort compté (ancienne maison)")
	data.House.Items.KnittedRug = 1
	check(near(Formulas.GetHouseComfort(data), bed.Comfort + 2 * sofa.Comfort * harmony + rug.Comfort * harmony), "confort + tapis")
	-- Plusieurs pièces : les exemplaires sont comptés toutes pièces confondues
	local rooms = { House = { Size = "Apartment", Items = { LoftBed = 1, Sofa = 1 }, Rooms = {
		{ Id = "R1", Type = "Living", Slot = 1, Placed = { { I = "Sofa" }, { I = "LoftBed" } } },
		{ Id = "R2", Type = "Bedroom", Slot = 2, Placed = { { I = "LoftBed" }, { I = "Sofa" } } }, -- déjà posés au salon
	} } }
	check(near(Formulas.GetHouseComfort(rooms), sofa.Comfort * harmony + bed.Comfort), "exemplaires partagés entre pièces")
	rooms.House.Items.LoftBed = 2
	check(near(Formulas.GetHouseComfort(rooms), sofa.Comfort * harmony + bed.Comfort + bed.Comfort * harmony), "lit harmonieux dans la chambre")
	-- Plafonds : RoomItems par pièce, MaxRooms pièces
	local many = { House = { Size = "Studio", Items = { KnittedRug = 1000 }, Rooms = {} } }
	for r = 1, 3 do
		local placed = {}
		for i = 1, 100 do placed[i] = { I = "KnittedRug", X = 0.5, Y = 0.9, S = 1, Z = i } end
		many.House.Rooms[r] = { Id = "R" .. r, Type = "Kitchen", Slot = r, Placed = placed }
	end
	eq(check, Formulas.GetHouseComfort(many), H.Sizes[1].MaxRooms * H.Sizes[1].RoomItems * rug.Comfort, "studio plafonné")
	many.House.Size = "Mansion"
	eq(check, Formulas.GetHouseComfort(many), 3 * H.Sizes[4].RoomItems * rug.Comfort, "manoir plafonné")
	many.House.Size = "Inconnu"
	eq(check, Formulas.GetHouseSize(many), H.Sizes[1], "taille inconnue -> studio")
	-- Prix des pièces
	eq(check, Formulas.GetRoomCost(1), H.RoomCost, "2e pièce")
	eq(check, Formulas.GetRoomCost(3), math.floor(H.RoomCost * H.RoomCostGrowth ^ 2), "4e pièce")
	eq(check, Formulas.GetRoomCost(nil), H.RoomCost, "prix pièce nil")
	eq(check, Formulas.GetRoomType("Inconnu"), H.RoomTypes[1], "type inconnu -> salon")

	-- Bonus (v9.3, rendements décroissants) : 1 + Max x c / (c + Max / ParPoint)
	local half = H.MaxComfortBonus / H.ComfortBonusPerPoint
	eq(check, Formulas.GetHouseBonus(0), 1, "bonus 0")
	check(near(Formulas.GetHouseBonus(10), 1 + H.MaxComfortBonus * 10 / (10 + half)), "bonus 10")
	check(Formulas.GetHouseBonus(10) <= 1 + 10 * H.ComfortBonusPerPoint, "les premiers points valent au plus ParPoint")
	check(near(Formulas.GetHouseBonus(half), 1 + H.MaxComfortBonus / 2), "moitié du max à Max / ParPoint points")
	check(Formulas.GetHouseBonus(1e9) < 1 + H.MaxComfortBonus and Formulas.GetHouseBonus(1e9) > 1 + H.MaxComfortBonus * 0.99, "bonus plafonné")
	local last = 1
	for c = 0, 5000, 50 do
		local b = Formulas.GetHouseBonus(c)
		check(b >= last, "bonus croissant " .. c)
		check(c == 0 or b - last <= 50 * H.ComfortBonusPerPoint + 1e-9, "rendements décroissants " .. c)
		last = b
	end
	eq(check, Formulas.GetHouseBonus(-5), 1, "bonus négatif")
	eq(check, Formulas.GetHouseBonus(nil), 1, "bonus nil")
	eq(check, Formulas.GetHouseBonus(0 / 0), 1, "bonus NaN")
	-- Le bonus multiplie bien tous les gains
	local d = emptyData()
	local base = Formulas.ComputeStats(d, 1, 1)
	local boosted = Formulas.ComputeStats(d, 1, Formulas.GetHouseBonus(40))
	check(near(boosted.ClickValue, base.ClickValue * Formulas.GetHouseBonus(40)), "bonus appliqué au clic")
end)

test("Maison v9 : tables vides, chaises, objets posés SUR les meubles", function(check)
	local H = Config.House
	local I = Config.HouseItemsById
	check(#H.Items >= 250, "au moins 250 objets (v9 : +40) : " .. #H.Items)
	-- Nouveaux meubles / objets attendus
	for _, id in ipairs({ "DiningTable", "CafeTable", "CoffeeTable", "SideTable", "KitchenIsland", "PicnicTable", "BarTable",
		"BigDesk", "DiningChair", "MushroomStool", "BarStool", "Armchair", "GardenBench", "FloorCushion", "RockingChair",
		"DoubleBed", "FruitBowl", "TeaSet", "DeskLamp", "BoardGame", "PhotoFrame", "HeartPillow", "SnowGlobe", "MiniAquarium",
		"Kitten", "Hedgehog", "FloatingShelf" }) do
		check(I[id] ~= nil, "objet v9 manquant : " .. id)
	end
	eq(check, I.DiningTable and I.DiningTable.Category, "Furniture", "table = meuble")
	eq(check, I.FloatingShelf and I.FloatingShelf.Placement, "Wall", "étagère flottante au mur")
	-- Règle "posable sur un meuble" (même règle client / serveur)
	local can = Formulas.CanGoOnFurniture
	for _, id in ipairs({ "CocoaMug", "HeartPillow", "Kitten", "SleepyCat", "TeaSet", "Laptop", "TulipPot", "ScentedCandle",
		"TeddyBear", "Suitcase", "StorageBox", "BigBear", "RetroTV", "DesktopPC", "FruitBowl", "DeskLamp" }) do
		check(I[id] ~= nil and can(I[id]) == true, "devrait pouvoir aller sur un meuble : " .. id)
	end
	for _, id in ipairs({ "WoodenChair", "DiningTable", "Nightstand", "Sofa", "MouseHole", "WoodenDoor", "CurtainWindow",
		"HangingBulb", "GrandPiano", "KnittedRug", "RobotVacuum", "PetBowl", "FloorLamp", "Dragon" }) do
		check(I[id] ~= nil and can(I[id]) == false, "ne va PAS sur un meuble : " .. id)
	end
	check(can(nil) == false and can({}) == false, "entrée invalide")
	-- Limites du serveur (Y des pieds) : objets posables, anciennes sauvegardes, meubles
	eq(check, Formulas.GetHouseFloorMinY(I.CocoaMug), H.TabletopMinY, "tasse : peut monter sur un meuble")
	eq(check, Formulas.GetHouseFloorMinY(I.Nightstand), H.TabletopMinY, "ancienne sauvegarde (Size <= 70) acceptée")
	eq(check, Formulas.GetHouseFloorMinY(I.DiningTable), H.WallRatio * 0.85, "table : reste au sol")
	check(H.TabletopMinY < H.WallRatio * 0.85 and H.TabletopMinY >= 0.05, "TabletopMinY")
	check(H.TabletopMaxSize >= 70 and H.LegacyTabletopSize <= H.TabletopMaxSize, "tailles posables")
	-- Plus on avance, plus c'est cher : les objets chers sont verrouillés par les visites à l'océan
	check(Formulas.GetHouseRequiredRebirths(I.EggChair) >= 1, "fauteuil œuf : après l'océan")
	check(Formulas.GetHouseRequiredRebirths(I.Candelabra) >= 2, "chandelier : 2 visites")
	check(Formulas.GetHouseRequiredRebirths(I.JewelryBox) >= 3, "coffret royal : 3 visites")
	eq(check, Formulas.GetHouseRequiredRebirths(I.SideTable), 0, "petite table : tout de suite")
	-- Objet retourné (F) : même confort, sauvegardes d'avant (sans F) inchangées
	local plain = { House = { Size = "Studio", Items = { DiningChair = 2 }, Rooms = {
		{ Id = "R1", Type = "Kitchen", Slot = 1, Placed = { { I = "DiningChair", X = 0.3, Y = 0.8, S = 1, Z = 1 },
			{ I = "DiningChair", X = 0.6, Y = 0.8, S = 1, Z = 1, F = true } } } } } }
	check(near(Formulas.GetHouseComfort(plain), 2 * I.DiningChair.Comfort * (1 + H.HarmonyBonus)), "confort avec chaises retournées")
end)

test("Maison v9.1 : 48 nouveaux objets et personnalisation (couleurs, boiseries, ambiances, vues, extérieur, jardin)", function(check)
	-- (faux Color3 des tests : une table { R, G, B })
	local function typeOf(value)
		if type(value) == "table" and type(value.R) == "number" and type(value.G) == "number" and type(value.B) == "number" then
			return "Color3"
		end
		return type(value)
	end
	local H = Config.House
	local I = Config.HouseItemsById
	check(#H.Items >= 295, "au moins 295 objets (v9.1 : +40) : " .. #H.Items)
	local newIds = { "ToyChest", "Pouf", "LadderShelf", "KotatsuTable", "HeartArmchair", "Hammock", "CatSofa", "CrystalThrone",
		"HeartRug", "StarGarland", "KittyClock", "Tapestry", "ButterflyFrame", "CloudRug", "Mannequin", "Harp", "SwanStatue",
		"CrownCushion", "ToyBlocks", "Xylophone", "JackInTheBox", "ToyCar", "PlushPile", "SucculentTrio", "LavenderPot",
		"HangingTerrarium", "LotusBowl", "RainbowTree", "RetroComputer", "Jukebox", "PinballMachine", "Hologram", "Popsicles",
		"WaffleMaker", "DumplingSteamer", "KitchenSink", "GingerbreadHouse", "TulipLamp", "JellyfishLamp", "NeonStar",
		"ArchWindow", "StainedGlass", "DutchDoor", "CastleGate", "Duckling", "Penguin", "Axolotl", "Owl" }
	check(#newIds >= 40, "au moins 40 nouveaux objets")
	local gated = 0
	for _, id in ipairs(newIds) do
		check(I[id] ~= nil, "objet v9.1 manquant : " .. id)
		if I[id] and Formulas.GetHouseRequiredRebirths(I[id]) > 0 then
			gated += 1
		end
	end
	check(gated >= 8, "objets chers verrouillés par l'océan : " .. gated)
	check(Formulas.GetHouseRequiredRebirths(I.CrystalThrone) >= 3, "trône de cristal : 3 visites")
	check(Formulas.GetHouseRequiredRebirths(I.RainbowTree) >= 2, "arbre arc-en-ciel : 2 visites")
	eq(check, Formulas.GetHouseRequiredRebirths(I.ToyChest), 0, "coffre à jouets : tout de suite")
	eq(check, Formulas.CanGoOnFurniture(I.HeartRug), false, "tapis : pas sur un meuble")
	eq(check, Formulas.CanGoOnFurniture(I.Popsicles), true, "glaces : sur la table")
	-- Genres de personnalisation
	local kinds = { Trim = "Room", Mood = "Room", View = "Room", Facade = "House", Roof = "House", RoofStyle = "House", Garden = "Garden" }
	for kind, scope in pairs(kinds) do
		local def = Config.HouseLookKinds[kind]
		check(def ~= nil and def.Scope == scope, "genre " .. kind)
		if def then
			check(#def.List >= 8, kind .. " : au moins 8 choix (" .. #def.List .. ")")
			if scope ~= "Garden" then
				eq(check, def.List[1].Cost, 0, kind .. " : le 1er est gratuit")
			end
			local ids = {}
			for index, entry in ipairs(def.List) do
				check(type(entry.Id) == "string" and not ids[entry.Id], kind .. " : Id " .. tostring(entry.Id))
				ids[entry.Id] = true
				eq(check, def.ById[entry.Id], entry, kind .. " index " .. entry.Id)
				check(type(entry.Name) == "string" and #entry.Name > 0 and isSingleEmoji(entry.Icon), kind .. " Name/Icon " .. entry.Id)
				check(type(entry.Cost) == "number" and entry.Cost >= 0 and entry.Cost == math.floor(entry.Cost), kind .. " Cost " .. entry.Id)
				if index > 1 or scope == "Garden" then
					check(entry.Cost > 0, kind .. " : payant " .. entry.Id)
				end
			end
		end
	end
	for _, trim in ipairs(H.Trims) do
		check(typeOf(trim.Color) == "Color3", "boiseries : couleur " .. trim.Id)
	end
	for _, mood in ipairs(H.Moods) do
		check(typeOf(mood.Tint) == "Color3" and typeOf(mood.Light) == "Color3" and type(mood.Amount) == "number"
			and mood.Amount >= 0 and mood.Amount < 1 and type(mood.Brightness) == "number" and type(mood.Effect) == "string",
			"ambiance " .. mood.Id)
	end
	local viewKinds = { Garden = true, Sunset = true, City = true, Beach = true, Snow = true, Sakura = true, Mountains = true,
		Underwater = true, Candy = true, Space = true, Rainbow = true,
		SkatePark = true, Stadium = true, Racetrack = true, Launch = true, Dino = true, Volcano = true } -- (v9.2)
	for _, view in ipairs(H.Views) do
		check(viewKinds[view.Kind] == true and typeOf(view.Sky) == "Color3", "vue " .. view.Id)
	end
	local roofPatterns = { None = true, Hearts = true, Dots = true, Stripes = true, Stars = true, Flowers = true, Snow = true, Scales = true,
		Checkered = true, Bolts = true, Camo = true, Flames = true } -- (v9.2)
	-- (v9.2) effets d'ambiance connus de HouseMoods
	local moodEffects = { None = true, Rays = true, Sparkles = true, Hearts = true, Leaves = true, Bubbles = true, Disco = true,
		Aurora = true, Rainbow = true, Neon = true, Floodlights = true, RGB = true, Storm = true, Embers = true }
	for _, mood in ipairs(H.Moods) do
		check(moodEffects[mood.Effect] == true, "effet d'ambiance inconnu " .. mood.Id .. " " .. tostring(mood.Effect))
	end
	for _, style in ipairs(H.RoofStyles) do
		check(roofPatterns[style.Pattern] == true, "motif de toit " .. style.Id)
	end
	check(H.GardenSlots >= 4 and H.GardenSlots <= 8, "places du jardin")
	-- Couleurs des objets
	check(#H.Tints >= 8, "au moins 8 couleurs d'objet")
	for _, tint in ipairs(H.Tints) do
		eq(check, Config.HouseTintsById[tint.Id], tint, "couleur index " .. tint.Id)
		check(typeOf(tint.Color) == "Color3" and isSingleEmoji(tint.Icon), "couleur " .. tint.Id)
		check(I[tint.Id] == nil, "id de couleur différent d'un objet : " .. tint.Id)
	end
	check(Formulas.GetHouseRequiredRebirths(Config.HouseTintsById.Gold) >= 1, "couleur or : après l'océan")
	-- Les nouveaux styles chers sont verrouillés
	check(Formulas.GetHouseRequiredRebirths(Config.HouseLooksById.Mood.RainbowGlow) >= 3, "lueur arc-en-ciel : 3 visites")
	check(Formulas.GetHouseRequiredRebirths(Config.HouseLooksById.Garden.UnicornStatue) >= 3, "statue de licorne : 3 visites")
end)
"""


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def build_bundle(extra):
    parts = [HEADER]
    for name in MODULES:
        body = read(os.path.join(SHARED, name + ".luau"))
        parts.append('loaders["%s"] = function()\nlocal require = req\n%s\nend\n' % (name, body))
    parts.append(TESTS)
    parts.append(extra)
    parts.append(
        '\nprint(string.format("\\n%d PASS, %d FAIL", results.pass, results.fail))\n'
        'if results.fail > 0 then error("TESTS EN ÉCHEC", 0) end\n'
    )
    return "\n".join(parts)


CONFIG_PATH_RE = re.compile(r"(?<![A-Za-z0-9_.])Config((?:\.[A-Za-z_][A-Za-z0-9_]*)+)")


def config_key_test():
    """Génère un test Luau : chaque chemin Config.X.Y trouvé dans src/ existe."""
    paths = {}
    for base, _, files in os.walk(SRC):
        for fname in files:
            if not fname.endswith(".luau") or fname == "Config.luau":
                continue
            full = os.path.join(base, fname)
            for lineno, line in enumerate(read(full).splitlines(), 1):
                code = line.split("--", 1)[0]
                for m in CONFIG_PATH_RE.finditer(code):
                    path = m.group(1)[1:]
                    # un appel de méthode (Config.X:Y) ou un champ de type n'est pas une clé
                    paths.setdefault(path, "%s:%d" % (os.path.relpath(full, ROOT), lineno))
    lines = ['test("Config : toutes les clés utilisées dans src/ existent (%d chemins)", function(check)' % len(paths)]
    for path, where in sorted(paths.items()):
        keys = path.split(".")
        lua_keys = ", ".join('"%s"' % k for k in keys)
        lines.append(
            '\tdo local v = Config for _, k in ipairs({%s}) do if type(v) ~= "table" then v = nil break end v = v[k] end '
            'check(v ~= nil, "Config.%s (%s)") end' % (lua_keys, path, where)
        )
    lines.append("end)")
    return "\n".join(lines)


def lang_test():
    """Génère un test Luau : dictionnaires de Shared/Lang (mêmes %s/%d des deux
    côtés ; chaque clé de FR_Config est un vrai texte de Config)."""
    lang_dir = os.path.join(SHARED, "Lang")
    lines = ["local LANG = {}"]
    if os.path.isdir(lang_dir):
        for fname in sorted(os.listdir(lang_dir)):
            if fname.endswith(".luau"):
                body = read(os.path.join(lang_dir, fname))
                lines.append('do local ok, r = pcall(function()\n%s\nend) LANG["%s"] = ok and r or { erreur = tostring(r) } end'
                             % (body, fname[:-5]))
    lines.append(r'''
test("Lang : dictionnaires (placeholders, clés de FR_Config)", function(check)
	local configTexts, seen = {}, {}
	local function collect(t)
		if seen[t] then return end
		seen[t] = true
		for k, v in pairs(t) do
			if type(v) == "string" and (k == "Name" or k == "Description" or k == "Text") then
				configTexts[v] = true
			elseif type(v) == "table" then
				collect(v)
			end
		end
	end
	collect(Config)
	local function count(s, p) local n = 0 for _ in s:gmatch(p) do n += 1 end return n end
	for name, dict in pairs(LANG) do
		check(type(dict) == "table" and type(dict.fr) == "table", name .. " : { fr = {...} } attendu " .. tostring(dict.erreur or ""))
		for en, fr in pairs(dict.fr or {}) do
			check(type(en) == "string" and type(fr) == "string", name .. " : entrée non texte")
			if type(en) == "string" and type(fr) == "string" then
				eq(check, count(fr, "%%s"), count(en, "%%s"), name .. " %s : " .. en)
				eq(check, count(fr, "%%d"), count(en, "%%d"), name .. " %d : " .. en)
				if name == "FR_Config" then
					check(configTexts[en] == true, "FR_Config : clé absente de Config : " .. en)
				end
			end
		end
	end
end)

test("Lang : tous les textes de Config.House ont une traduction française", function(check)
	check(LANG.FR_House ~= nil, "FR_House.luau manquant")
	local fr = {}
	for _, dict in pairs(LANG) do
		if type(dict) == "table" and type(dict.fr) == "table" then
			for en, text in pairs(dict.fr) do fr[en] = text end
		end
	end
	local H = Config.House
	for _, list in ipairs({ H.Sizes, H.Wallpapers, H.Floors, H.Categories, H.Items, H.RoomTypes,
		H.Tints, H.Trims, H.Moods, H.Views, H.Facades, H.Roofs, H.RoofStyles, H.GardenDecor }) do
		for _, entry in ipairs(list) do
			check(type(fr[entry.Name]) == "string", "pas de traduction : " .. tostring(entry.Name))
		end
	end
end)''')
    return "\n".join(lines)


def house_art_test():
    """Génère un test Luau : chaque objet de Config.House.Items a un dessin
    (Art.<Id> = function ... dans Client/Components/House/Art/*.luau), et
    aucun dessin ne vise un objet inconnu."""
    art_dir = os.path.join(SRC, "ReplicatedStorage", "Client", "Components", "House", "Art")
    drawn = {}
    if os.path.isdir(art_dir):
        for fname in sorted(os.listdir(art_dir)):
            if fname.endswith(".luau"):
                for m in re.finditer(r"^Art\.(\w+)\s*=\s*function", read(os.path.join(art_dir, fname)), re.M):
                    drawn[m.group(1)] = fname
    ids = ", ".join('["%s"] = "%s"' % (k, v) for k, v in sorted(drawn.items()))
    return "\n".join([
        'test("Maison : chaque objet a son dessin kawaii (%d dessins)", function(check)' % len(drawn),
        "\tlocal drawn = { %s }" % ids,
        "\tfor _, item in ipairs(Config.House.Items) do",
        '\t\tcheck(drawn[item.Id] ~= nil, "pas de dessin pour " .. item.Id)',
        "\tend",
        "\tfor id, file in pairs(drawn) do",
        '\t\tcheck(Config.HouseItemsById[id] ~= nil, "dessin sans objet : " .. id .. " (" .. file .. ")")',
        "\tend",
        "end)",
    ]) + "\n" + house_garden_art_test() + "\n" + house_surfaces_test() + "\n" + house_service_test() + "\n" + cool92_test() + "\n" + setup95_test()


# (v9.5) SETUPDATA95 : "🖥️ Dopamine Setup" (Config.House, Art/Setup95,
# HouseSurfaces) : ids exacts du contrat, dessins, verrous (amélioration +
# visites à l'océan), prix croissants par palier, dessus des bureaux
SETUP95_IDS = [
    "SetupDeskSolo", "SetupDeskDuo", "SetupDeskTrio", "SetupDeskUltra", "SetupKeyboard", "SetupMouse",
    "SetupTVStand", "SetupTVSmall", "SetupTVMedium", "SetupTVLarge", "SetupTVGiant",
    "SetupTVWallMedium", "SetupTVWallLarge", "SetupTVWallGiant", "SetupNewsTV",
    "SetupHiFiBoombox", "SetupHiFiCD", "SetupHiFiVinyl", "SetupHiFiStudio",
    "SetupWindmill", "SetupPress", "SetupBubbleWrap", "SetupLiveStudio",
    "SetupPlantDaisy", "SetupPlantTulip", "SetupPlantRose", "SetupPlantSunflower", "SetupPlantLotus",
]


def setup95_test():
    comp = os.path.join(SRC, "ReplicatedStorage", "Client", "Components", "House")
    art_path = os.path.join(comp, "Art", "Setup95.luau")
    drawn = re.findall(r"^Art\.(\w+)\s*=\s*function", read(art_path), re.M) if os.path.exists(art_path) else []
    surf = read(os.path.join(comp, "HouseSurfaces.luau"))
    surfaced = re.findall(r"^\t(Setup\w+) = \{ \{", surf, re.M)
    lua = lambda names: "{ " + ", ".join('"%s"' % n for n in names) + " }"
    return r'''
test("Maison v9.5 : Dopamine Setup (%d objets, %d dessins Setup95)", function(check)
	local ids, drawnList, surfaced = %s, %s, %s
	local drawn, onSurface = {}, {}
	for _, id in ipairs(drawnList) do drawn[id] = true end
	for _, id in ipairs(surfaced) do onSurface[id] = true end
	local category = Config.HouseCategoriesById.Setup
	check(category ~= nil and category.Name == "Dopamine Setup" and category.Icon == "🖥️" and category.Tint ~= nil, "catégorie Setup")
	local kinds = { Desk = true, Keyboard = true, Mouse = true, TV = true, TVStand = true, HiFi = true, Windmill = true, Press = true,
		BubbleWrap = true, LiveStudio = true, NewsTV = true, Plant = true }
	local feeds = { Runner = true, Live = true, DVD = true, News = true }
	local seen = {}
	for _, id in ipairs(ids) do
		local item = Config.HouseItemsById[id]
		check(item ~= nil, "objet manquant " .. id)
		if item then
			seen[id] = true
			eq(check, item.Category, "Setup", "catégorie " .. id)
			check(drawn[id] == true, "dessin Setup95 " .. id)
			check(type(item.Setup) == "table" and kinds[item.Setup.Kind] == true, "Setup.Kind " .. id)
			check(type(item.Setup.Tier) == "number" and item.Setup.Tier >= 1, "Setup.Tier " .. id)
			check(({ S = true, M = true, L = true, XL = true })[item.Setup.Size] == true, "Setup.Size " .. id)
			check(({ Floor = true, Surface = true, Stand = true, Wall = true })[item.Setup.Mount] == true, "Setup.Mount " .. id)
			if item.Setup.Mount == "Wall" then eq(check, item.Placement, "Wall", "au mur " .. id) else eq(check, item.Placement, "Floor", "au sol " .. id) end
			if item.Setup.Mount == "Surface" then check(Formulas.CanGoOnFurniture(item), "se pose sur un meuble " .. id) end
			if item.Setup.Feeds then
				eq(check, #item.Setup.Feeds, item.Setup.Screens, "un flux par écran " .. id)
				for _, f in ipairs(item.Setup.Feeds) do check(feeds[f] == true, "flux inconnu " .. tostring(f) .. " " .. id) end
			end
			if item.Setup.Kind == "Desk" then
				check(item.Setup.Seat == true and onSurface[id] == true and not Formulas.CanGoOnFurniture(item), "bureau : chaise + dessus " .. id)
			end
			if item.Setup.Kind == "Plant" then check(Config.Garden and type(item.Setup.Flower) == "string", "fleur " .. id) end
			check(type(item.RequiresRebirths) == "number", "RequiresRebirths écrit " .. id)
			if item.RequiresUpgrade ~= nil then
				check(Config.UpgradesById[item.RequiresUpgrade] ~= nil, "amélioration inconnue " .. tostring(item.RequiresUpgrade) .. " " .. id)
			end
		end
	end
	-- aucun autre objet dans la catégorie, aucun autre dessin dans Setup95
	for _, item in ipairs(Config.HouseItemsByCategory.Setup or {}) do check(seen[item.Id] == true, "objet Setup hors contrat " .. item.Id) end
	for id in pairs(drawn) do check(seen[id] == true, "dessin Setup95 sans objet " .. id) end
	for _, id in ipairs({ "SetupTVStand", "SetupBubbleWrap" }) do check(onSurface[id] == true, "dessus " .. id) end
	for _, id in ipairs({ "SetupKeyboard", "SetupMouse", "SetupTVSmall", "SetupPlantDaisy", "SetupPlantTulip", "SetupPlantRose",
		"SetupPlantSunflower", "SetupPlantLotus" }) do
		check(Formulas.CanGoOnFurniture(Config.HouseItemsById[id]), "sur un bureau / meuble : " .. id)
	end
	-- verrous du contrat : amélioration + visites
	local I = Config.HouseItemsById
	local gates = {
		SetupDeskSolo = { "Runner", 0 }, SetupDeskDuo = { "Runner", 1 }, SetupDeskTrio = { "Runner", 2 }, SetupDeskUltra = { "Runner", 4 },
		SetupKeyboard = { "Keyboard", 0 }, SetupMouse = { "Mouse", 0 },
		SetupTVSmall = { "DVD", 0 }, SetupTVMedium = { "DVD", 1 }, SetupTVLarge = { "DVD", 2 }, SetupTVGiant = { "DVD", 4 },
		SetupTVWallMedium = { "DVD", 1 }, SetupTVWallLarge = { "DVD", 2 }, SetupTVWallGiant = { "DVD", 4 },
		SetupHiFiBoombox = { "Lofi", 0 }, SetupHiFiCD = { "Lofi", 1 }, SetupHiFiVinyl = { "Lofi", 2 }, SetupHiFiStudio = { "Lofi", 4 },
		SetupWindmill = { "Pinwheel", 0 }, SetupPress = { "Press", 0 }, SetupBubbleWrap = { "BubbleWrap", 0 }, SetupLiveStudio = { "LiveStream", 0 },
		SetupNewsTV = { "NewsTicker", 0 },
		SetupPlantDaisy = { "Garden", 0 }, SetupPlantTulip = { "Garden", 0 }, SetupPlantRose = { "Garden", 1 }, SetupPlantSunflower = { "Garden", 2 },
		SetupPlantLotus = { "Garden", 3 },
	}
	for id, gate in pairs(gates) do
		local item = I[id]
		if item then
			eq(check, item.RequiresUpgrade, gate[1], "amélioration de " .. id)
			eq(check, Formulas.GetHouseRequiredRebirths(item), gate[2], "visites de " .. id)
		end
	end
	eq(check, I.SetupTVStand and I.SetupTVStand.RequiresUpgrade, nil, "meuble télé libre")
	eq(check, Config.UpgradesById.Runner.Feature, "Runner", "bureaux : amélioration du coureur")
	-- prix strictement croissants avec le palier dans chaque famille
	for _, family in ipairs({
		{ "SetupDeskSolo", "SetupDeskDuo", "SetupDeskTrio", "SetupDeskUltra" },
		{ "SetupTVSmall", "SetupTVMedium", "SetupTVLarge", "SetupTVGiant" },
		{ "SetupTVWallMedium", "SetupTVWallLarge", "SetupTVWallGiant" },
		{ "SetupHiFiBoombox", "SetupHiFiCD", "SetupHiFiVinyl", "SetupHiFiStudio" },
		{ "SetupPlantDaisy", "SetupPlantTulip", "SetupPlantRose", "SetupPlantSunflower", "SetupPlantLotus" },
	}) do
		for k = 2, #family do
			local a, b = I[family[k - 1]], I[family[k]]
			if a and b then
				check(b.Cost > a.Cost and b.Setup.Tier > a.Setup.Tier and b.Comfort >= a.Comfort, "prix / palier croissants " .. a.Id .. " < " .. b.Id)
				check(Formulas.GetHouseRequiredRebirths(b) >= Formulas.GetHouseRequiredRebirths(a), "visites croissantes " .. b.Id)
			end
		end
	end
	-- le support mural coûte un peu plus que la télé sur pied
	for _, pair in ipairs({ { "SetupTVMedium", "SetupTVWallMedium" }, { "SetupTVLarge", "SetupTVWallLarge" }, { "SetupTVGiant", "SetupTVWallGiant" } }) do
		check(I[pair[2]].Cost >= I[pair[1]].Cost, "télé murale >= sur pied " .. pair[2])
	end
	-- prix raisonnables : au moins le prix de l'amélioration à 0 visite, confort
	-- jamais plus rentable que les petits objets du début (<= 1 point / 2 K)
	for _, id in ipairs(ids) do
		local item = I[id]
		if item and item.RequiresUpgrade and Formulas.GetHouseRequiredRebirths(item) == 0 then
			local upgrade = Config.UpgradesById[item.RequiresUpgrade]
			check(item.Cost >= math.min(upgrade.Cost, 5e6) * 0.5, "objet moins cher que son amélioration : " .. id)
		end
		if item then check(item.Cost / item.Comfort >= 2000, "confort trop rentable : " .. id) end
	end
end)''' % (len(SETUP95_IDS), len(drawn), lua(SETUP95_IDS), lua(drawn), lua(surfaced))


def cool92_test():
    """(v9.2) Contenu "cool" des boutiques : objets de la maison (≥ 35, verrous
    d'océan des objets chers), chapeaux / motifs de boutons dessinés par
    Client/Components/CosmeticArt.luau, décors des thèmes (Background.luau)."""
    comp = os.path.join(SRC, "ReplicatedStorage", "Client", "Components")
    cosm = read(os.path.join(comp, "CosmeticArt.luau")) if os.path.exists(os.path.join(comp, "CosmeticArt.luau")) else ""
    hats = sorted(set(re.findall(r"^HATS\.(\w+)\s*=\s*function", cosm, re.M)))
    skins = sorted(set(re.findall(r"^SKINS\.(\w+)\s*=\s*function", cosm, re.M)))
    decors = sorted(set(re.findall(r"^Decors\.(\w+)\s*=\s*function", read(os.path.join(comp, "Background.luau")), re.M)))
    art_dir = os.path.join(comp, "House", "Art")
    cool = []
    for fname in sorted(os.listdir(art_dir)):
        if fname.startswith("Cool92") and fname.endswith(".luau"):
            cool += re.findall(r"^Art\.(\w+)\s*=\s*function", read(os.path.join(art_dir, fname)), re.M)
    lua = lambda names: "{ " + ", ".join('["%s"] = true' % n for n in names) + " }"
    return "\n".join([
        'test("Boutiques v9.2 : contenu cool (%d objets, %d chapeaux, %d motifs, %d décors)", function(check)' % (len(cool), len(hats), len(skins), len(decors)),
        "\tlocal cool, hats, skins, decors = %s, %s, %s, %s" % (lua(cool), lua(hats), lua(skins), lua(decors)),
        "\tlocal count = 0",
        "\tfor id in pairs(cool) do",
        "\t\tlocal item = Config.HouseItemsById[id]",
        '\t\tcheck(item ~= nil, "objet cool inconnu " .. id)',
        "\t\tif item then",
        "\t\t\tcount += 1",
        '\t\t\tif item.Cost >= 3e6 then check(Formulas.GetHouseRequiredRebirths(item) >= 1, "objet cher sans visite à l\'océan : " .. id) end',
        "\t\tend",
        "\tend",
        '\tcheck(count >= 35, "au moins 35 objets cool : " .. count)',
        "\tfor _, c in ipairs(Config.Cosmetics) do",
        '\t\tif c.Pattern ~= nil then check(skins[c.Pattern] == true, "motif de bouton sans dessin : " .. c.Id) end',
        "\tend",
        "\tfor id in pairs(hats) do",
        '\t\tlocal c = Config.CosmeticsById[id]',
        '\t\tcheck(c ~= nil and c.Slot == "Hat", "chapeau dessiné inconnu : " .. id)',
        "\tend",
        "\tfor _, theme in ipairs(Config.Themes) do",
        '\t\tcheck(decors[theme.Decor] == true, "décor de thème inconnu : " .. tostring(theme.Id) .. " " .. tostring(theme.Decor))',
        "\tend",
        '\tfor _, id in ipairs({ "Street", "Gamer", "SpaceStation" }) do check(Config.ThemesById[id] ~= nil, "thème " .. id) end',
        "end)",
    ])


def house_garden_art_test():
    """(v9.1) Chaque déco du jardin (Config.House.GardenDecor) a son dessin
    (Garden.<Id> = function ... dans Client/Components/House/GardenArt/*.luau)."""
    garden_dir = os.path.join(SRC, "ReplicatedStorage", "Client", "Components", "House", "GardenArt")
    drawn = {}
    if os.path.isdir(garden_dir):
        for fname in sorted(os.listdir(garden_dir)):
            if fname.endswith(".luau"):
                for m in re.finditer(r"^Garden\.(\w+)\s*=\s*function", read(os.path.join(garden_dir, fname)), re.M):
                    drawn[m.group(1)] = fname
    ids = ", ".join('["%s"] = "%s"' % (k, v) for k, v in sorted(drawn.items()))
    return "\n".join([
        'test("Maison v9.1 : chaque déco du jardin a son dessin (%d dessins)", function(check)' % len(drawn),
        "\tlocal drawn = { %s }" % ids,
        "\tfor _, decor in ipairs(Config.House.GardenDecor) do",
        '\t\tcheck(drawn[decor.Id] ~= nil, "pas de dessin pour la déco " .. decor.Id)',
        "\tend",
        "\tfor id, file in pairs(drawn) do",
        '\t\tcheck(Config.HouseLooksById.Garden[id] ~= nil, "dessin sans déco : " .. id .. " (" .. file .. ")")',
        "\tend",
        "end)",
    ])


# 🏠 Simulation SERVEUR de HouseService (source injectée telle quelle, faux
# services) : la disposition envoyée par l'éditeur (objets posés SUR les
# meubles, chaises retournées F, anciennes sauvegardes) est acceptée telle
# quelle ; ce qui sort des zones est recalé.
HOUSE_SERVICE_TESTS = r"""
do
	local fakeFunctions = {}
	local fakeNet = { Function = function(name)
		fakeFunctions[name] = fakeFunctions[name] or {}
		return fakeFunctions[name]
	end }
	-- (v9.6 PLACE96) zone valide partagée : WorldLayout (source telle quelle)
	local wlFn, wlErr = loadstring(HS_WORLD_LAYOUT_SRC, "=WorldLayout")
	assert(wlFn, wlErr)
	local WL = wlFn()
	local fakeModules = { Config = Config, Formulas = Formulas, NumberFormatter = N, Net = fakeNet, WorldLayout = WL,
		RateLimiter = { Check = function() return true end } }
	local shared = { Config = "Config", Formulas = "Formulas", NumberFormatter = "NumberFormatter", Net = "Net", WorldLayout = "WorldLayout" }
	local env = {
		game = { GetService = function() return { Shared = shared } end },
		script = { Parent = { RateLimiter = "RateLimiter" } },
		require = function(key) return fakeModules[key] end,
		warn = function() end,
	}
	local fn, err = loadstring(HOUSE_SERVICE_SRC, "=HouseService")
	assert(fn, err)
	setfenv(fn, setmetatable(env, { __index = getfenv(0) }))
	local HouseService = fn()
	local data
	local player = { Name = "Test" }
	HouseService:Init({
		DataService = { GetData = function() return data end },
		GameService = {
			T = function(_, _, text, ...) if select("#", ...) > 0 then return string.format(text, ...) end return text end,
			SendState = function() end,
			IsReady = function() return true end,
		},
	})
	HouseService:Start()

	test("HouseService (simulation) : objets sur les meubles, chaises retournées, anciennes sauvegardes", function(check)
		local H = Config.House
		data = { Dopamine = 0, Rebirths = 0, Stats = {}, House = { Size = "Studio",
			Items = { DiningTable = 1, DiningChair = 3, CocoaMug = 1, Nightstand = 1, WoodenChair = 1, HeartPillow = 1 },
			-- ancienne maison à une seule pièce : table de chevet posée en hauteur (ancienne règle Size <= 70)
			Placed = { { I = "Nightstand", X = 0.5, Y = 0.3, S = 1, Z = 1 } } } }
		HouseService:PlayerReady(player, data)
		local room = data.House.Rooms[1]
		check(room ~= nil and room.Id == "R1", "ancienne sauvegarde -> une pièce")
		eq(check, room and room.Placed[1] and room.Placed[1].Y, 0.3, "ancienne table de chevet en hauteur gardée")
		local invoke = fakeFunctions.House and fakeFunctions.House.OnServerInvoke
		check(type(invoke) == "function", "RemoteFunction House branchée")
		if type(invoke) ~= "function" then return end
		local ok, message = invoke(player, "saveLayout", { Rooms = { R1 = {
			{ I = "DiningTable", X = 0.4, Y = 0.74, S = 1, Z = 100 },
			{ I = "CocoaMug", X = 0.4, Y = 0.5337, S = 1, Z = 100 }, -- sur la table
			{ I = "DiningChair", X = 0.3, Y = 0.734, S = 1, Z = 100 }, -- à gauche de la table
			{ I = "DiningChair", X = 0.5, Y = 0.734, S = 1, Z = 100, F = true }, -- à droite, retournée
			{ I = "HeartPillow", X = 0.7, Y = 0.18, S = 1, Z = 100, F = "oui" }, -- (F invalide ignoré)
			{ I = "DiningChair", X = 0.2, Y = 0.3, S = 1, Z = 100 }, -- une chaise ne monte pas sur un meuble
		} } })
		check(ok == true, "disposition acceptée : " .. tostring(message))
		local placed = data.House.Rooms[1].Placed
		eq(check, #placed, 6, "6 objets")
		check(near(placed[2].Y, 0.5337, 1e-6), "tasse sur la table : Y gardé " .. tostring(placed[2].Y))
		eq(check, placed[3].F, nil, "chaise de gauche : pas retournée")
		eq(check, placed[4].F, true, "chaise de droite : retournée (F gardé)")
		eq(check, placed[5].F, nil, "F invalide ignoré")
		check(near(placed[5].Y, 0.18, 1e-6), "coussin posé en hauteur (étagère murale...) " .. tostring(placed[5].Y))
		-- (v9.6) même zone que l'éditeur 2D : bande du sol (WorldLayout.PlacementArea)
		local _, _, chairY0 = WL.PlacementArea("Floor", Config.HouseItemsById.DiningChair.Size, WL.RoomWidthPx(Config.HouseSizesById.Studio), 440, H.WallRatio)
		check(placed[6].Y >= H.WallRatio + 0.03 and near(placed[6].Y, chairY0, 2e-4), "chaise recalée au sol : " .. tostring(placed[6].Y))
		-- Trop haut même pour un petit objet : recalé à TabletopMinY
		ok = invoke(player, "saveLayout", { Rooms = { R1 = { { I = "CocoaMug", X = 0.5, Y = 0.01, S = 1, Z = 1 } } } })
		check(ok == true and near(data.House.Rooms[1].Placed[1].Y, H.TabletopMinY, 1e-6), "tasse trop haute recalée")
		-- Comfort identique avec ou sans F
		eq(check, Formulas.GetHouseComfort(data), Config.HouseItemsById.CocoaMug.Comfort * (1 + (Formulas.IsRoomFavorite(Formulas.GetRoomType("Living"), Config.HouseItemsById.CocoaMug) and H.HarmonyBonus or 0)), "confort")
	end)

	test("HouseService (simulation) v9.1 : personnalisation sauvegardée et vérifiée (styles, jardin, couleurs d'objets)", function(check)
		local H = Config.House
		-- Sauvegarde d'avant la v9.1 (sans aucun champ nouveau) + champs abîmés
		data = { Dopamine = 1e6, Rebirths = 0, Stats = {}, House = { Size = "Studio", Items = { Sofa = 2, TeddyBear = 1 },
			OwnedMoods = { Moonlight = true, Nope = true, [5] = true }, Facade = "Nope", Garden = { "PinkFlamingo", 12 },
			Rooms = { { Id = "R1", Type = "Living", Slot = 1, Mood = "Moonlight", View = "Nope",
				Placed = { { I = "Sofa", X = 0.5, Y = 0.8, S = 1, Z = 1, C = "Mint" }, { I = "Sofa", X = 0.3, Y = 0.8, S = 1, Z = 1, C = "Gold" },
					{ I = "TeddyBear", X = 0.6, Y = 0.8, S = 1, Z = 1, C = "Nope" } } } } } }
		HouseService:PlayerReady(player, data)
		local house = data.House
		local room = house.Rooms[1]
		eq(check, room.Trim, H.Trims[1].Id, "boiseries par défaut")
		eq(check, room.Mood, "Moonlight", "ambiance possédée gardée")
		eq(check, room.View, H.Views[1].Id, "vue inconnue -> par défaut")
		eq(check, house.Facade, H.Facades[1].Id, "façade inconnue -> d'origine")
		eq(check, house.Roof, H.Roofs[1].Id, "toit par défaut")
		eq(check, house.RoofStyle, H.RoofStyles[1].Id, "motif par défaut")
		eq(check, #house.Garden, 0, "déco du jardin non possédée retirée")
		eq(check, house.OwnedMoods.Nope, nil, "ambiance inconnue retirée")
		eq(check, house.OwnedMoods[H.Moods[1].Id], true, "1re ambiance gratuite possédée")
		eq(check, room.Placed[1].C, "Mint", "couleur d'objet gardée")
		eq(check, room.Placed[2].C, nil, "couleur or verrouillée (0 visite) retirée")
		eq(check, room.Placed[3].C, nil, "couleur inconnue retirée")
		local invoke = fakeFunctions.House.OnServerInvoke
		-- Achat d'une ambiance pour la pièce R1
		local ok, message = invoke(player, "buyLook", { Kind = "Mood", Id = "CozyLamp", Room = "R1" })
		check(ok == true, "achat ambiance : " .. tostring(message))
		eq(check, room.Mood, "CozyLamp", "ambiance appliquée")
		eq(check, data.Dopamine, 1e6 - Config.HouseMoodsById.CozyLamp.Cost, "prix payé")
		ok = invoke(player, "buyLook", { Kind = "Mood", Id = "CozyLamp", Room = "R1" })
		check(ok == false, "déjà possédée")
		ok = invoke(player, "setLook", { Kind = "Mood", Id = "Moonlight", Room = "R1" })
		check(ok == true and room.Mood == "Moonlight", "ambiance possédée réappliquée")
		ok = invoke(player, "setLook", { Kind = "View", Id = "BeachView", Room = "R1" })
		check(ok == false and room.View == H.Views[1].Id, "vue pas achetée : refusée")
		ok = invoke(player, "buyLook", { Kind = "Mood", Id = "RainbowGlow", Room = "R1" })
		check(ok == false and room.Mood == "Moonlight", "ambiance verrouillée par l'océan : refusée")
		ok = invoke(player, "buyLook", { Kind = "Nope", Id = "X" })
		check(ok == false, "genre inconnu refusé")
		ok = invoke(player, "buyLook", { Kind = "Trim", Id = "MintTrim", Room = "R99" })
		check(ok == false, "pièce inconnue refusée")
		-- Extérieur
		ok = invoke(player, "buyLook", { Kind = "Facade", Id = "StrawberryFacade" })
		check(ok == true and house.Facade == "StrawberryFacade", "façade achetée et appliquée")
		ok = invoke(player, "buyLook", { Kind = "RoofStyle", Id = "HeartRoof" })
		check(ok == true and house.RoofStyle == "HeartRoof", "motif du toit acheté")
		-- Jardin : achat = posé, rangé / ressorti, plein au-delà de GardenSlots
		data.Dopamine = 1e12
		data.Rebirths = 8 -- (v9.3) toute la déco du jardin débloquée (paliers jusqu'à 8 visites)
		local bought = 0
		for _, decor in ipairs(H.GardenDecor) do
			if invoke(player, "buyLook", { Kind = "Garden", Id = decor.Id }) then
				bought += 1
			end
		end
		eq(check, bought, #H.GardenDecor, "toute la déco achetée")
		eq(check, #house.Garden, H.GardenSlots, "jardin rempli (places max)")
		local extra = H.GardenDecor[#H.GardenDecor].Id
		check(table.find(house.Garden, extra) == nil, "déco en trop achetée mais rangée")
		ok = invoke(player, "setLook", { Kind = "Garden", Id = extra, On = true })
		check(ok == false, "jardin plein : refusé")
		ok = invoke(player, "setLook", { Kind = "Garden", Id = house.Garden[1], On = false })
		check(ok == true and #house.Garden == H.GardenSlots - 1, "déco rangée")
		ok = invoke(player, "setLook", { Kind = "Garden", Id = extra, On = true })
		check(ok == true and table.find(house.Garden, extra) ~= nil, "déco sortie")
		-- Couleurs des objets posés : envoyées avec la disposition
		ok = invoke(player, "saveLayout", { Rooms = { R1 = { { I = "Sofa", X = 0.5, Y = 0.8, S = 1, Z = 1, C = "Gold" },
			{ I = "TeddyBear", X = 0.6, Y = 0.8, S = 1, Z = 1, C = string.rep("x", 200) } } } })
		check(ok == true, "disposition avec couleurs acceptée")
		eq(check, room.Placed[1].C, "Gold", "couleur or après 5 visites")
		eq(check, room.Placed[2].C, nil, "couleur trop longue ignorée")
		-- Nouvelle pièce : styles par défaut
		house.OwnedSizes.Apartment = true
		house.Size = "Apartment"
		ok = invoke(player, "buyRoom", "Kitchen")
		local newRoom = house.Rooms[#house.Rooms]
		-- (v9.6) le look du type (boiseries / ambiance), sinon les styles par défaut
		local kitchenType = Config.HouseRoomTypesById.Kitchen
		check(ok == true and newRoom.Trim == (kitchenType.Trim or H.Trims[1].Id) and newRoom.Mood == (kitchenType.Mood or H.Moods[1].Id)
			and newRoom.View == H.Views[1].Id, "nouvelle pièce : styles par défaut")
	end)

	-- (v9.5) SETUPDATA95 : "Dopamine Setup", le serveur vérifie RequiresUpgrade
	test("HouseService (simulation) v9.5 : objets Dopamine Setup verrouillés par leur amélioration", function(check)
		local invoke = fakeFunctions.House and fakeFunctions.House.OnServerInvoke
		if type(invoke) ~= "function" then check(false, "RemoteFunction House") return end
		data = { Dopamine = 1e12, Rebirths = 5, Upgrades = {}, Stats = {}, House = { Size = "Studio", Items = {} } }
		HouseService:PlayerReady(player, data)
		local items = data.House.Items
		local ok, message = invoke(player, "buyItem", "SetupDeskSolo")
		check(ok == false and (items.SetupDeskSolo or 0) == 0, "bureau sans Coureur infini : refusé")
		check(type(message) == "string" and message:find("Endless Runner", 1, true) ~= nil and message:find("first", 1, true) ~= nil,
			"message : débloque l'amélioration d'abord : " .. tostring(message))
		eq(check, data.Dopamine, 1e12, "rien de payé")
		data.Upgrades.Runner = 0
		ok = invoke(player, "buyItem", "SetupDeskSolo")
		check(ok == false, "niveau 0 : refusé")
		data.Upgrades.Runner = 0 / 0
		ok = invoke(player, "buyItem", "SetupDeskSolo")
		check(ok == false, "niveau NaN : refusé")
		data.Upgrades.Runner = 1
		ok = invoke(player, "buyItem", "SetupDeskSolo")
		check(ok == true and items.SetupDeskSolo == 1, "bureau avec Coureur infini : acheté")
		eq(check, data.Dopamine, 1e12 - Config.HouseItemsById.SetupDeskSolo.Cost, "prix payé")
		-- l'objet acheté reste à soi même si l'amélioration disparaît (océan)
		data.Upgrades.Runner = nil
		check(items.SetupDeskSolo == 1, "objet gardé")
		-- meuble télé : aucune amélioration exigée
		ok = invoke(player, "buyItem", "SetupTVStand")
		check(ok == true, "meuble télé : pas d'amélioration exigée")
		-- visites à l'océan d'abord, puis amélioration
		data.Rebirths = 3
		data.Upgrades.DVD = 1
		ok, message = invoke(player, "buyItem", "SetupTVGiant")
		check(ok == false and tostring(message):find("ocean", 1, true) ~= nil, "télé géante : 4 visites : " .. tostring(message))
		data.Rebirths = 4
		ok = invoke(player, "buyItem", "SetupTVGiant")
		check(ok == true, "télé géante : 4 visites + DVD")
		-- chaque objet Setup est refusé sans son amélioration, accepté avec
		data.Rebirths = 10
		data.Dopamine = 1e15
		for _, item in ipairs(Config.House.Items) do
			if item.RequiresUpgrade then
				data.Upgrades = {}
				local before = items[item.Id] or 0
				local refused = invoke(player, "buyItem", item.Id)
				check(refused == false and (items[item.Id] or 0) == before, "refusé sans " .. item.RequiresUpgrade .. " : " .. item.Id)
				data.Upgrades[item.RequiresUpgrade] = 1
				local accepted, why = invoke(player, "buyItem", item.Id)
				check(accepted == true and items[item.Id] == before + 1, "accepté avec " .. item.RequiresUpgrade .. " : " .. item.Id .. " " .. tostring(why))
			end
		end
	end)
	-- (v9.6) PLACE96 : zone valide partagée (2D / 3D / serveur) + réparation
	-- des anciennes dispositions + look des types de pièces
	test("HouseService (simulation) v9.6 : dispositions hors de la pièce réparées au chargement et à la sauvegarde", function(check)
		local invoke = fakeFunctions.House and fakeFunctions.House.OnServerInvoke
		if type(invoke) ~= "function" then check(false, "RemoteFunction House") return end
		local H = Config.House
		local mansion = Config.HouseSizesById.Mansion
		local wpx = WL.RoomWidthPx(mansion)
		-- sauvegarde "cassée" par l'ancienne édition 3D : objets hors des bords, sofa dans le mur, tableau au plafond
		data = { Dopamine = 0, Rebirths = 5, Stats = {}, House = { Size = "Mansion", OwnedSizes = { Studio = true, Mansion = true },
			Items = { Sofa = 1, FramedPicture = 1, CocoaMug = 1, Bookshelf = 1 },
			Rooms = { { Id = "R1", Type = "Living", Slot = 1, Placed = {
				{ I = "Sofa", X = 0.001, Y = H.WallRatio + 0.001, S = 1.4, Z = 100 },
				{ I = "FramedPicture", X = 0.999, Y = 0, S = 1, Z = 100 },
				{ I = "CocoaMug", X = 1, Y = 0.999, S = 1, Z = 100 },
				{ I = "Bookshelf", X = 0.5, Y = 0.9999, S = 1.6, Z = 100 },
			} } } } }
		HouseService:PlayerReady(player, data)
		local placed = data.House.Rooms[1].Placed
		eq(check, #placed, 4, "4 objets gardés")
		for _, e in ipairs(placed) do
			local item = Config.HouseItemsById[e.I]
			local raised = item.Placement ~= "Wall" and Formulas.GetHouseFloorMinY(item) < H.WallRatio * 0.85 and Formulas.GetHouseFloorMinY(item) or nil
			local x0, x1, y0, y1 = WL.PlacementArea(item.Placement, item.Size * e.S, wpx, 440, H.WallRatio, raised)
			check(e.X >= x0 - 1e-9 and e.X <= x1 + 1e-9 and e.Y >= y0 - 1e-9 and e.Y <= y1 + 1e-9,
				string.format("%s réparé dans la zone : %.4f %.4f (x %.4f..%.4f y %.4f..%.4f)", e.I, e.X, e.Y, x0, x1, y0, y1))
		end
		check(placed[1].Y >= H.WallRatio + 0.035 - 1e-9, "sofa : pieds dans la bande du sol (plus dans le mur)")
		-- idempotent : recharger ne bouge plus rien
		local before = {}
		for i, e in ipairs(placed) do before[i] = { e.X, e.Y } end
		HouseService:PlayerReady(player, data)
		for i, e in ipairs(data.House.Rooms[1].Placed) do
			check(e.X == before[i][1] and e.Y == before[i][2], "réparation stable " .. e.I)
		end
		-- sauvegarde hors zone : bornée pareil
		local ok = invoke(player, "saveLayout", { Rooms = { R1 = { { I = "Sofa", X = -3, Y = 0.2, S = 1, Z = 100 } } } })
		local sofa = data.House.Rooms[1].Placed[1]
		local x0, _, y0 = WL.PlacementArea("Floor", Config.HouseItemsById.Sofa.Size, wpx, 440, H.WallRatio)
		check(ok == true and near(sofa.X, x0, 2e-4) and near(sofa.Y, y0, 2e-4), "sauvegarde bornée : " .. tostring(sofa.X) .. " / " .. tostring(sofa.Y))
	end)

	test("HouseService (simulation) v9.6 : look automatique des types de pièces (achat, changement de type, choix gardé)", function(check)
		local invoke = fakeFunctions.House and fakeFunctions.House.OnServerInvoke
		if type(invoke) ~= "function" then check(false, "RemoteFunction House") return end
		local H = Config.House
		local types = Config.HouseRoomTypesById
		data = { Dopamine = 1e12, Rebirths = 5, Stats = {}, House = { Size = "Mansion", OwnedSizes = { Studio = true, Mansion = true }, Items = {} } }
		HouseService:PlayerReady(player, data)
		local house = data.House
		-- chaque type a un look connu
		for _, roomType in ipairs(H.RoomTypes) do
			check(Config.HouseWallpapersById[roomType.Wallpaper] ~= nil and Config.HouseFloorsById[roomType.Floor] ~= nil, "look connu : " .. roomType.Id)
			check(roomType.Trim == nil or Config.HouseTrimsById[roomType.Trim] ~= nil, "boiserie connue : " .. roomType.Id)
			check(roomType.Mood == nil or Config.HouseMoodsById[roomType.Mood] ~= nil, "ambiance connue : " .. roomType.Id)
		end
		-- nouvelle salle de bain : murs + sol du type, GRATUITS (pas achetés)
		local ok, message = invoke(player, "buyRoom", "Bathroom")
		check(ok == true, "salle de bain achetée : " .. tostring(message))
		local bath = house.Rooms[#house.Rooms]
		eq(check, bath.Wallpaper, types.Bathroom.Wallpaper, "salle de bain : papier peint du type")
		eq(check, bath.Floor, types.Bathroom.Floor, "salle de bain : sol du type")
		eq(check, bath.Trim, types.Bathroom.Trim, "salle de bain : boiseries du type")
		check(house.OwnedWallpapers[types.Bathroom.Wallpaper] == nil, "le style du type n'est PAS offert pour toute la maison")
		-- salle de jeux : néon sombre + ambiance
		ok = invoke(player, "buyRoom", "GameRoom")
		local game = house.Rooms[#house.Rooms]
		check(ok == true and game.Wallpaper == types.GameRoom.Wallpaper and game.Floor == types.GameRoom.Floor and game.Mood == types.GameRoom.Mood,
			"salle de jeux : look du type " .. tostring(game.Wallpaper) .. " / " .. tostring(game.Floor) .. " / " .. tostring(game.Mood))
		-- rechargement : le look gratuit reste (pas remis au 1er style)
		HouseService:PlayerReady(player, data)
		bath = house.Rooms[#house.Rooms - 1]
		eq(check, bath.Wallpaper, types.Bathroom.Wallpaper, "rechargement : look du type gardé")
		eq(check, bath.Floor, types.Bathroom.Floor, "rechargement : sol du type gardé")
		-- changer le type : le look suit
		ok = invoke(player, "setRoomType", { Room = bath.Id, Type = "Kitchen" })
		check(ok == true and bath.Wallpaper == types.Kitchen.Wallpaper and bath.Floor == types.Kitchen.Floor, "cuisine : look du type appliqué")
		-- un style choisi à la main n'est plus remplacé
		ok = invoke(player, "buyFloor", { Room = bath.Id, Id = "CherryWood" })
		check(ok == true and bath.Floor == "CherryWood", "sol choisi à la main")
		ok = invoke(player, "setRoomType", { Room = bath.Id, Type = "Bathroom" })
		check(ok == true and bath.Floor == "CherryWood", "type changé : le sol choisi reste " .. tostring(bath.Floor))
		eq(check, bath.Wallpaper, types.Bathroom.Wallpaper, "type changé : les murs (pas choisis) suivent")
		-- le look du type se remet gratuitement (même non acheté), un autre style non
		ok = invoke(player, "setFloor", { Room = bath.Id, Id = types.Bathroom.Floor })
		check(ok == true and bath.Floor == types.Bathroom.Floor, "sol du type remis gratuitement")
		local dopamine = data.Dopamine
		ok = invoke(player, "buyFloor", { Room = bath.Id, Id = types.Bathroom.Floor })
		check(ok == true and data.Dopamine == dopamine, "\"acheter\" le sol du type : gratuit")
		ok = invoke(player, "setFloor", { Room = bath.Id, Id = "GoldenMarble" })
		check(ok == false and bath.Floor == types.Bathroom.Floor, "autre sol pas acheté : refusé")
		ok = invoke(player, "setRoomType", { Room = bath.Id, Type = "Library" })
		check(ok == true and bath.Floor == types.Library.Floor, "sol du type (plus choisi à la main) : suit le nouveau type")
		-- un style d'un AUTRE type n'est pas gratuit ici
		ok = invoke(player, "setWallpaper", { Room = bath.Id, Id = types.GameRoom.Wallpaper })
		check(ok == false, "papier peint d'un autre type : refusé")
	end)
end
"""


def house_service_test():
    """Injecte Services/HouseService.luau (source telle quelle) puis HOUSE_SERVICE_TESTS."""
    path = os.path.join(SRC, "ServerScriptService", "Services", "HouseService.luau")
    body = read(path)
    if "]=====]" in body:
        raise ValueError("délimiteur ]=====] interdit dans " + path)
    wl = read(os.path.join(SHARED, "WorldLayout.luau"))
    if "]=====]" in wl:
        raise ValueError("délimiteur ]=====] interdit dans WorldLayout.luau")
    return "local HOUSE_SERVICE_SRC = [=====[%s]=====]\nlocal HS_WORLD_LAYOUT_SRC = [=====[%s]=====]\n%s" % (body, wl, HOUSE_SERVICE_TESTS)


def house_surfaces_test():
    """Génère un test Luau : les dessus de meubles, sièges et tables de
    Client/Components/House/HouseSurfaces.luau visent des objets connus
    (coordonnées 0..100, x0 < x1), chaque table a un dessus, chaque siège est
    un meuble au sol."""
    path = os.path.join(SRC, "ReplicatedStorage", "Client", "Components", "House", "HouseSurfaces.luau")
    src = read(path) if os.path.exists(path) else ""

    def block(name):
        m = re.search(r"^local %s[^\n]*=\s*\{\n(.*?)^\}" % name, src, re.M | re.S)
        return m.group(1) if m else ""

    surfaces = []
    for m in re.finditer(r"^\t(\w+) = \{ (.*?) \},?\s*(?:--.*)?$", block("SURFACES"), re.M):
        for s in re.finditer(r"\{ ([\d.]+), ([\d.]+), ([\d.]+)(?:, (-?[\d.]+))?(?:, ([\d.]+))? \}", m.group(2)):
            surfaces.append('{ "%s", %s, %s, %s, %s, %s }' % (m.group(1), s.group(1), s.group(2), s.group(3), s.group(4) or "nil", s.group(5) or "nil"))
    seats = re.findall(r"^\t(\w+) = \{ View = \"(\w+)\"", block("SEATS"), re.M)
    tables = re.findall(r"^\t(\w+) = true", block("TABLES"), re.M)
    beds = re.findall(r"^\t(\w+) = true", block("BEDS"), re.M)
    return "\n".join([
        'test("Maison : dessus des meubles, sièges et tables (%d dessus, %d sièges, %d tables)", function(check)'
        % (len(surfaces), len(seats), len(tables)),
        "\tlocal surfaces = { %s }" % ", ".join(surfaces),
        "\tlocal seats = { %s }" % ", ".join('{ "%s", "%s" }' % s for s in seats),
        "\tlocal tables = { %s }" % ", ".join('"%s"' % t for t in tables),
        "\tlocal beds = { %s }" % ", ".join('"%s"' % b for b in beds),
        '\tcheck(#surfaces >= 30 and #seats >= 6 and #tables >= 6, "données de HouseSurfaces lues")',
        "\tlocal hasSurface = {}",
        "\tlocal levels = {}",
        "\tfor _, s in ipairs(surfaces) do",
        "\t\tlocal item = Config.HouseItemsById[s[1]]",
        '\t\tcheck(item ~= nil, "dessus d\'un objet inconnu : " .. s[1])',
        '\t\tcheck(s[2] >= 0 and s[3] <= 100 and s[2] < s[3] and s[4] >= 0 and s[4] <= 100, "coordonnées du dessus " .. s[1])',
        '\t\tcheck(s[5] == nil or (s[5] >= -0.5 and s[5] <= 0.5), "profondeur 3D du dessus (v9.6) " .. s[1])',
        '\t\tcheck(s[6] == nil or (s[6] > 0 and s[6] < 100), "place libre du rayon (v9.6) " .. s[1])',
        "\t\tlevels[s[1]] = (levels[s[1]] or 0) + 1",
        "\t\thasSurface[s[1]] = true",
        "\tend",
        '\tcheck((levels.Bookshelf or 0) >= 4 and levels.WallShelf == 1 and levels.TrophyShelf == 1 and (levels.FloatingShelf or 0) >= 2, "(v9.6) étagères à plusieurs niveaux")',
        "\tfor _, t in ipairs(tables) do",
        '\t\tcheck(Config.HouseItemsById[t] ~= nil and hasSurface[t] == true, "table sans dessus : " .. t)',
        "\tend",
        "\tfor _, b in ipairs(beds) do",
        '\t\tcheck(Config.HouseItemsById[b] ~= nil and hasSurface[b] == true, "lit sans dessus : " .. b)',
        "\tend",
        "\tfor _, s in ipairs(seats) do",
        "\t\tlocal item = Config.HouseItemsById[s[1]]",
        '\t\tcheck(item ~= nil and item.Placement == "Floor" and item.Category == "Furniture", "siège = meuble au sol : " .. s[1])',
        '\t\tcheck(s[2] == "Side" or s[2] == "Front" or s[2] == "Round", "vue du siège " .. s[1])',
        "\tend",
        "end)",
    ])


# 🕹️ Arcade + 💎 boutique Robux (agent ARCADESHOP) : packs de tickets, combos
# et objets stylés "bientôt" (Config.Monetization), 🏆 trophées (mises des
# duels, règles pures d'ArcadeConfig.Logic), puis simulations SERVEUR de
# MinigameService et MonetizationService (faux services, faux temps) : leurs
# sources sont injectées telles quelles par arcade_shop_test().
ARCADE_SHOP_TESTS = r"""
do
	local function loadModule(src, name, env)
		local fn, err = loadstring(src, "=" .. name)
		assert(fn, err)
		if env then
			setfenv(fn, setmetatable(env, { __index = getfenv(0) }))
		end
		return fn()
	end
	local ArcadeConfig = loadModule(ARCADE_SRC, "ArcadeConfig")
	local products = Config.Monetization.Products

	test("Config.Monetization : packs de tickets, combos et objets stylés (bientôt)", function(check)
		local expected = { { 5, 3714962647 }, { 10, 3714962696 }, { 25, 3714962739 }, { 50, 3714962804 }, { 100, 3714962854 } }
		local packs = {}
		for _, p in ipairs(products) do
			if p.Kind == "Tickets" then table.insert(packs, p) end
		end
		eq(check, #packs, #expected, "5 packs de tickets")
		for i, want in ipairs(expected) do
			local p = packs[i]
			if p then
				eq(check, p.Tickets, want[1], "tickets du pack " .. i)
				eq(check, p.ProductId, want[2], "ProductId du pack " .. i)
				check(p.ComingSoon ~= true, "pack en vente " .. p.Id)
				eq(check, Config.ProductsByProductId[p.ProductId], p, "index ProductId " .. p.Id)
				check(type(p.Name) == "string" and #p.Name > 0 and type(p.Icon) == "string" and #p.Icon > 0, "nom / icône " .. p.Id)
				check(type(p.PriceHint) == "number" and p.PriceHint > 0, "PriceHint " .. p.Id)
			end
		end
		check(packs[5] and type(packs[5].Tag) == "string" and packs[5].Tag:find("BEST VALUE", 1, true) ~= nil, "ruban BEST VALUE sur le gros pack")
		-- Ids uniques, IDs Roblox uniques
		local ids, productIds = {}, {}
		for _, p in ipairs(products) do
			check(not ids[p.Id], "Id en double " .. tostring(p.Id))
			ids[p.Id] = true
			if p.ProductId ~= 0 then
				check(not productIds[p.ProductId], "ProductId en double " .. tostring(p.ProductId))
				productIds[p.ProductId] = true
			end
		end
		-- Bientôt : combos (déjà accordables) et objets stylés (pas encore codés)
		local combos, styles = 0, 0
		local ready = Config.Monetization.ReadyKinds
		check(type(ready) == "table", "ReadyKinds")
		for _, p in ipairs(products) do
			if p.ComingSoon then
				eq(check, p.ProductId, 0, "bientôt sans ID : " .. p.Id)
				check(Config.ProductsByProductId[0] == nil, "ID 0 jamais indexé")
			end
			if p.Kind == "Combo" then
				combos += 1
				check(p.ComingSoon == true, "combo marqué bientôt " .. p.Id)
				check(type(p.Tickets) == "number" and p.Tickets > 0 and p.Tickets == math.floor(p.Tickets), "tickets du combo " .. p.Id)
				check(type(p.Seconds) == "number" and p.Seconds > 0 and type(p.Minimum) == "number" and p.Minimum > 0, "Dopamine du combo " .. p.Id)
			elseif p.Kind == "Stylish" then
				styles += 1
				check(p.ComingSoon == true, "objet stylé marqué bientôt " .. p.Id)
				check(type(p.Style) == "string", "Style " .. p.Id)
			end
			check(({ Dopamine = 1, Boost = 1, ServerRush = 1, Tickets = 1, Combo = 1, Stylish = 1 })[p.Kind] ~= nil, "Kind inconnu " .. p.Id)
			-- Ce qui est vendu (ID + pas "bientôt") doit être accordable par le serveur
			if p.ProductId ~= 0 and not p.ComingSoon then
				check(ready[p.Kind] == true, "vendu mais pas accordable : " .. p.Id)
			end
		end
		check(combos >= 3 and styles >= 5, "combos " .. combos .. " / stylés " .. styles)
		check(ready.Tickets and ready.Combo and not ready.Stylish, "ReadyKinds : Tickets + Combo oui, Stylish non")
	end)

	test("ArcadeConfig : 🏆 trophées (mises des duels) et règles pures", function(check)
		local stakes = ArcadeConfig.Duels.Stakes
		eq(check, stakes[1], 0, "1re mise = duel amical")
		for i = 2, #stakes do
			check(stakes[i] > stakes[i - 1] and stakes[i] == math.floor(stakes[i]), "mises croissantes entières")
			check(ArcadeConfig.StakesSet[stakes[i]] == true, "StakesSet " .. stakes[i])
		end
		local TR = ArcadeConfig.Trophies
		check(TR.Icon == "🏆" and TR.WelcomeGift > 0 and TR.PerSoloWin >= 1 and TR.DailyCap >= TR.PerSoloWin, "réglages des trophées")
		check(stakes[#stakes] <= TR.WelcomeGift + TR.DailyCap, "la plus grosse mise reste atteignable en un jour")
		check(ArcadeConfig.Tickets.Max >= 1e6, "Tickets.Max assez grand pour les achats")
		local L = ArcadeConfig.Logic
		-- Plafonds du jour
		eq(check, L.CappedGrant(3, 0, 20), 3, "sous le plafond")
		eq(check, L.CappedGrant(3, 19, 20), 1, "reste 1")
		eq(check, L.CappedGrant(3, 20, 20), 0, "plafond atteint")
		eq(check, L.CappedGrant(3, 25, 20), 0, "au-delà du plafond")
		eq(check, L.CappedGrant(2.7, 0, 20), 2, "entier")
		eq(check, L.CappedGrant(-4, 0, 20), 0, "négatif")
		eq(check, L.CappedGrant(0 / 0, 0, 20), 0, "NaN")
		eq(check, L.CappedGrant(math.huge, 0, 20), 0, "infini")
		-- Mises
		local ok, why = L.CheckStake(5, 10, 10)
		check(ok and why == nil, "mise payable")
		ok, why = L.CheckStake(5, 4, 10)
		check(not ok and why == "self", "pas assez de trophées (soi)")
		ok, why = L.CheckStake(5, 10, 4)
		check(not ok and why == "other", "pas assez de trophées (adversaire)")
		ok, why = L.CheckStake(7, 99, 99)
		check(not ok and why == "invalid", "mise hors liste")
		ok, why = L.CheckStake("5", 99, 99)
		check(not ok and why == "invalid", "mise texte")
		ok = L.CheckStake(0, 0, 0)
		check(ok, "duel amical sans trophée")
		-- Pot : gagnant x2, perdant 0, égalité rendue ; jamais créé ni détruit
		for _, stake in ipairs(stakes) do
			local w1, w2, d = L.StakePayouts(stake, 1), L.StakePayouts(stake, 2), L.StakePayouts(stake, 0)
			eq(check, w1[1], stake * 2, "gagnant 1") eq(check, w1[2], 0, "perdant 2")
			eq(check, w2[1], 0, "perdant 1") eq(check, w2[2], stake * 2, "gagnant 2")
			eq(check, d[1], stake, "égalité 1") eq(check, d[2], stake, "égalité 2")
			eq(check, w1[1] + w1[2], stake * 2, "pot conservé")
		end
		-- Pack de tickets conseillé : le plus petit qui suffit, sinon le plus gros
		local packs = {}
		for _, p in ipairs(products) do
			if p.Kind == "Tickets" and not p.ComingSoon then table.insert(packs, p) end
		end
		local function pick(missing)
			local p = L.PickTicketPack(missing, packs)
			return p and p.Tickets
		end
		eq(check, pick(1), 5, "manque 1") eq(check, pick(5), 5, "manque 5") eq(check, pick(6), 10, "manque 6")
		eq(check, pick(26), 50, "manque 26") eq(check, pick(99), 100, "manque 99") eq(check, pick(500), 100, "trop : le plus gros")
		check(L.PickTicketPack(3, {}) == nil, "aucun pack")
	end)

	------------------------------------------------------------------ Simulation serveur
	-- Faux temps / faux task : les délais sont joués par advance()
	local now = 1000
	local queue = {}
	local function schedule(t, fn, ...)
		table.insert(queue, { At = now + (t or 0), Fn = fn, Args = table.pack(...) })
	end
	local function advance(seconds)
		local target = now + seconds
		while true do
			table.sort(queue, function(a, b) return a.At < b.At end)
			local item = queue[1]
			if not item or item.At > target then break end
			table.remove(queue, 1)
			now = math.max(now, item.At)
			item.Fn(table.unpack(item.Args, 1, item.Args.n))
		end
		now = target
	end
	local fakeTask = {
		delay = function(t, fn, ...) schedule(t, fn, ...) end,
		defer = function(fn, ...) schedule(0, fn, ...) end,
		spawn = function(fn, ...) fn(...) end,
		wait = function() return 0 end,
	}
	-- (os.time part d'un début de jour UTC : la simulation ne change jamais de jour)
	local fakeOs = { clock = function() return now end, time = function() return 1699833600 + math.floor(now) end }
	local PlayersService = { list = {} }
	PlayersService.GetPlayers = function() return table.clone(PlayersService.list) end
	PlayersService.GetPlayerByUserId = function(_, id)
		for _, p in ipairs(PlayersService.list) do if p.UserId == id then return p end end
		return nil
	end
	local function newPlayer(id, name)
		local p = { UserId = id, DisplayName = name, Name = name }
		p.GetNetworkPing = function() return 0.04 end
		p.Parent = PlayersService
		table.insert(PlayersService.list, p)
		return p
	end
	local fakeLocale = {
		TFor = function(_, text, ...) if select("#", ...) > 0 then return string.format(text, ...) end return text end,
	}
	local function fakeT(_, _p, text, ...)
		if select("#", ...) > 0 then return string.format(text, ...) end
		return text
	end
	local fakeRandom = { new = function()
		return { NextInteger = function(_, a, b) return math.random(a, b) end, NextNumber = function(_, a, b) return a + math.random() * (b - a) end }
	end }

	test("MinigameService (simulation) : mises en 🏆, tickets jamais misés", function(check)
		math.randomseed(7)
		local events, arcadeFn = {}, nil
		local Net = {
			Event = function(name)
				return { FireClient = function(_, player, kind, payload)
					if name == "ArcadeEvent" then
						events[player] = events[player] or {}
						table.insert(events[player], { kind, payload })
					end
				end }
			end,
			Function = function(name)
				return setmetatable({}, { __newindex = function(t, k, v) if name == "Arcade" then arcadeFn = v end rawset(t, k, v) end })
			end,
		}
		local datas = {}
		local announces = 0
		local services = {
			DataService = { GetData = function(_, p) return datas[p] end },
			GameService = {
				IsReady = function(_, p) return datas[p] ~= nil end,
				T = fakeT,
				GetStats = function() return { PerSecond = 100, ClickValue = 10 } end,
				AddDopamine = function(_, p, amount) datas[p].Dopamine += amount end,
				SendState = function() end,
				Notify = function() end,
				NotifyAll = function(_, fn)
					local ok, msg = pcall(fn, "en")
					check(ok and type(msg.Text) == "string" and msg.Text:find("🏆", 1, true) ~= nil, "annonce en 🏆")
					announces += 1
				end,
			},
			MonetizationService = {
				GetBoost = function() return 1, 0 end,
				AddBoost = function() end,
			},
		}
		local shared = {
			Config = Config,
			Formulas = { HasFeature = function(data, f) return data.Features[f] == true end, ScaledReward = Formulas.ScaledReward },
			Locale = fakeLocale,
			NumberFormatter = N,
			Net = Net,
			ArcadeConfig = ArcadeConfig,
		}
		local ReplicatedStorage = { Shared = {} }
		for k in pairs(shared) do ReplicatedStorage.Shared[k] = k end
		local closers = {}
		local Service = loadModule(MINIGAME_SRC, "MinigameService", {
			require = function(x) if x == "RateLimiter" then return { Check = function() return true end } end return shared[x] end,
			game = {
				GetService = function(_, n) if n == "Players" then return PlayersService end return ReplicatedStorage end,
				BindToClose = function(_, fn) table.insert(closers, fn) end,
			},
			script = { Parent = { RateLimiter = "RateLimiter", FindFirstChild = function() return nil end } },
			task = fakeTask, os = fakeOs, Random = fakeRandom,
			warn = function(...) check(false, "warn : " .. table.concat({ ... }, " ")) end,
		})
		Service:Init(services)
		Service:Start()
		advance(0)
		local function lastEvent(p, kind)
			local list = events[p] or {}
			for i = #list, 1, -1 do if list[i][1] == kind then return list[i][2] end end
			return nil
		end
		local function call(p, action, arg) return arcadeFn(p, action, arg) end
		local function newData(tickets)
			return { Tickets = tickets, Arcade = {}, Dopamine = 0, Features = { Minigames = true },
				Stats = { MinigamesPlayed = 0, MinigamesWon = 0, DuelsWon = 0 } }
		end
		local TR, TK = ArcadeConfig.Trophies, ArcadeConfig.Tickets
		local A, B, C = newPlayer(1, "Ana"), newPlayer(2, "Bob"), newPlayer(3, "Cid")
		for _, p in ipairs({ A, B, C }) do
			datas[p] = newData(500)
			Service:PlayerReady(p, datas[p])
		end
		-- Cadeaux de bienvenue : tickets ET trophées (une seule fois)
		call(A, "lobby") call(B, "lobby") call(C, "lobby") call(A, "lobby")
		eq(check, datas[A].Trophies, TR.WelcomeGift, "trophées de bienvenue")
		eq(check, datas[A].Tickets, 500 + TK.StartTickets, "tickets de bienvenue")
		-- Ancien joueur (déjà "Welcomed" avant les trophées) : reçoit quand même les trophées
		local D = newPlayer(4, "Dan")
		datas[D] = newData(40)
		datas[D].Arcade = { Welcomed = true }
		Service:PlayerReady(D, datas[D])
		call(D, "lobby")
		eq(check, datas[D].Tickets, 40, "pas de 2e cadeau de tickets")
		eq(check, datas[D].Trophies, TR.WelcomeGift, "trophées offerts aux anciens joueurs")
		local ok, lobby = call(A, "lobby")
		check(ok and type(lobby.Players) == "table" and #lobby.Players == 3, "lobby")
		check(type(lobby.Players[1].Trophies) == "number", "le lobby montre les trophées")

		-- 500 tickets mais trop peu de trophées : mise refusée (on ne mise JAMAIS de tickets)
		local big = ArcadeConfig.Duels.Stakes[#ArcadeConfig.Duels.Stakes]
		datas[A].Trophies = big - 1
		advance(3)
		local okBig, msg = call(A, "invite", { Target = 2, Game = "TicTacToe", Stake = big })
		check(not okBig and type(msg) == "string" and msg:find("trophies", 1, true) ~= nil, "mise > trophées refusée malgré les tickets")
		datas[A].Trophies = 30
		datas[B].Trophies = big - 1
		advance(3)
		okBig, msg = call(A, "invite", { Target = 2, Game = "TicTacToe", Stake = big })
		check(not okBig and type(msg) == "string" and msg:find("Bob", 1, true) ~= nil, "adversaire sans assez de trophées")
		check(not call(A, "invite", { Target = 2, Game = "TicTacToe", Stake = 25 }), "ancienne mise en tickets (25) refusée")

		-- Duel à 5 🏆 : séquestre, victoire, pot x2 ; tickets : seulement le bonus fixe
		datas[B].Trophies = 20
		advance(3)
		local ticketsA, ticketsB = datas[A].Tickets, datas[B].Tickets
		local okI, inv = call(A, "invite", { Target = 2, Game = "TicTacToe", Stake = 5 })
		check(okI and inv.Invite and inv.Invite.Stake == 5, "invitation à 5 🏆")
		local okA = call(B, "accept", inv.Invite.Id)
		check(okA, "acceptation")
		eq(check, datas[A].Trophies, 25, "séquestre A") eq(check, datas[B].Trophies, 15, "séquestre B")
		eq(check, datas[A].Tickets, ticketsA, "tickets de A intacts") eq(check, datas[B].Tickets, ticketsB, "tickets de B intacts")
		local duel = lastEvent(A, "duelStart")
		local p1 = duel.You == 1 and A or B
		local p2 = p1 == A and B or A
		for _, move in ipairs({ { p1, 1 }, { p2, 2 }, { p1, 5 }, { p2, 3 }, { p1, 9 } }) do
			check(call(move[1], "move", { Id = duel.Id, Move = move[2] }), "coup " .. move[2])
		end
		local fin = lastEvent(p1, "duelEnd")
		check(fin and fin.Result.Outcome == "Win" and fin.Result.Trophies == 5, "victoire : +5 🏆 net")
		local winnerBefore = p1 == A and 25 or 15
		local loserBefore = p2 == A and 25 or 15
		eq(check, datas[p1].Trophies, winnerBefore + 10 + fin.Result.TrophyBonus, "gagnant : pot x2 + bonus")
		eq(check, fin.Result.TrophyBonus, TR.PerDuelWin, "1 🏆 bonus")
		eq(check, datas[p2].Trophies, loserBefore, "perdant : mise perdue")
		eq(check, lastEvent(p2, "duelEnd").Result.Trophies, -5, "perdant : -5 🏆")
		eq(check, datas[p1].Tickets, (p1 == A and ticketsA or ticketsB) + TK.DuelWinBonus, "gagnant : seulement le bonus de tickets")
		eq(check, datas[p2].Tickets, p2 == A and ticketsA or ticketsB, "perdant : tickets intacts")
		eq(check, datas[p1].Arcade.History[1].K, "T", "historique : mise en trophées")
		eq(check, announces, 1, "annonce du gros duel")

		-- Le prix de la victoire NE dépend PAS de la mise (duel amical = même bonus)
		advance(5)
		local _, inv2 = call(A, "invite", { Target = 3, Game = "TicTacToe", Stake = 0 })
		call(C, "accept", inv2.Invite.Id)
		local d2 = lastEvent(A, "duelStart")
		local q1 = d2.You == 1 and A or C
		local q2 = q1 == A and C or A
		local before = { [A] = { datas[A].Tickets, datas[A].Trophies, datas[A].Dopamine }, [C] = { datas[C].Tickets, datas[C].Trophies, datas[C].Dopamine } }
		for _, move in ipairs({ { q1, 1 }, { q2, 2 }, { q1, 5 }, { q2, 3 }, { q1, 9 } }) do
			call(move[1], "move", { Id = d2.Id, Move = move[2] })
		end
		local fin2 = lastEvent(q1, "duelEnd")
		check(fin2 and fin2.Result.Outcome == "Win" and fin2.Result.Trophies == 0, "duel amical gagné")
		eq(check, datas[q1].Tickets - before[q1][1], TK.DuelWinBonus, "même bonus de tickets sans mise")
		eq(check, datas[q1].Trophies - before[q1][2], TR.PerDuelWin, "même bonus de trophée sans mise")
		check(datas[q1].Dopamine > before[q1][3], "même prix en Dopamine sans mise")

		-- Duel trop long : égalité, mises rendues ; fermeture du serveur : rendues aussi
		advance(5)
		local tA, tB = datas[A].Trophies, datas[B].Trophies
		local _, inv3 = call(A, "invite", { Target = 2, Game = "SpotRace", Stake = 2 })
		call(B, "accept", inv3.Invite.Id)
		eq(check, datas[A].Trophies, tA - 2, "séquestre (égalité)")
		advance(ArcadeConfig.Duels.MaxDuelSeconds + 1)
		eq(check, datas[A].Trophies, tA, "égalité : mise rendue A") eq(check, datas[B].Trophies, tB, "égalité : mise rendue B")
		advance(5)
		local _, inv4 = call(A, "invite", { Target = 2, Game = "Connect4", Stake = 10 })
		call(B, "accept", inv4.Invite.Id)
		eq(check, datas[B].Trophies, tB - 10, "séquestre (fermeture)")
		for _, fn in ipairs(closers) do fn() end
		eq(check, datas[A].Trophies, tA, "fermeture : rendue A") eq(check, datas[B].Trophies, tB, "fermeture : rendue B")

		-- Acceptation revérifiée : l'inviteur a dépensé ses trophées entre-temps
		advance(5)
		local _, inv5 = call(A, "invite", { Target = 3, Game = "TicTacToe", Stake = 5 })
		datas[A].Trophies = 1
		local okAcc, accMsg = call(C, "accept", inv5.Invite.Id)
		check(not okAcc and tostring(accMsg):find("trophies", 1, true) ~= nil, "acceptation refusée : l'inviteur n'a plus assez")
		check(lastEvent(A, "inviteClosed") and lastEvent(A, "inviteClosed").Reason == "trophies", "invitation fermée (trophées)")

		-- Boutique à tickets : refus avec le manque (le client propose d'en acheter)
		datas[C].Tickets = 3
		local okBuy, refusal = call(C, "buy", "Snack")
		check(not okBuy and type(refusal) == "table" and refusal.Missing == 17 and refusal.Currency == "Tickets", "refus : Missing = 17")
		datas[C].Tickets = 20
		check(call(C, "buy", "Snack") and datas[C].Tickets == 0, "achat en tickets")

		-- Tickets achetés en Robux : même solde, sans plafond du jour
		local added, balance = Service:GrantPurchasedTickets(C, 100)
		eq(check, added, 100, "tickets achetés ajoutés") eq(check, balance, 100, "nouveau solde")
		eq(check, datas[C].Arcade.TicketsBought, 100, "stat TicketsBought")
		check(not pcall(Service.GrantPurchasedTickets, Service, C, 2.5), "montant non entier refusé")

		-- Victoires solo : +1 🏆 par victoire récompensée, plafond du jour
		local rewardWin = Service._Internal.RewardWin
		local E = newPlayer(5, "Eve")
		datas[E] = newData(0)
		Service:PlayerReady(E, datas[E])
		call(E, "lobby")
		local start = datas[E].Trophies
		local first = rewardWin(E, "Minesweeper", 42)
		eq(check, first.Trophies, TR.PerSoloWin, "victoire solo : +1 🏆")
		eq(check, datas[E].Trophies, start + TR.PerSoloWin, "solde après victoire")
		local total = first.Trophies
		for _, gameId in ipairs({ "Minesweeper", "Memory", "Simon" }) do
			for _ = 1, 20 do
				local r = rewardWin(E, gameId, nil)
				total += r.Trophies
				if r.Capped then
					eq(check, r.Trophies, 0, "partie non récompensée : pas de trophée")
				end
			end
		end
		eq(check, total, TR.DailyCap, "plafond du jour des trophées")
		eq(check, datas[E].Trophies, start + TR.DailyCap, "solde plafonné")
		eq(check, datas[E].Arcade.DayTrophies, TR.DailyCap, "DayTrophies")
		local st = Service:GetClientState(A, datas[A])
		check(type(st.Trophies) == "number" and st.Arcade.TrophyCap == TR.DailyCap and type(st.Arcade.TrophiesEarned) == "number", "GetClientState : trophées")
		-- Sauvegarde abîmée : trophées nettoyés
		datas[B].Trophies = -5
		call(B, "lobby")
		eq(check, datas[B].Trophies, 0, "trophées négatifs corrigés")
		datas[B].Trophies = 0 / 0
		call(B, "lobby")
		eq(check, datas[B].Trophies, 0, "trophées NaN corrigés")
	end)

	test("MonetizationService (simulation) : ProcessReceipt tickets, combos, bientôt", function(check)
		local Decision = { PurchaseGranted = "Granted", NotProcessedYet = "NotYet" }
		local MPS = { PromptGamePassPurchaseFinished = { Connect = function() end } }
		local datas, notifies, saves = {}, {}, { ok = true, count = 0 }
		local players = { list = {} }
		players.GetPlayerByUserId = function(_, id)
			for _, p in ipairs(players.list) do if p.UserId == id then return p end end
			return nil
		end
		local P = { UserId = 77, Name = "Buyer", DisplayName = "Buyer" }
		table.insert(players.list, P)
		datas[P] = { Tickets = 3, Dopamine = 0, Purchases = {}, Boost = { Multiplier = 1, EndsAt = 0 }, Stats = { RobuxPurchases = 0 } }
		local services = {
			DataService = {
				GetData = function(_, p) return datas[p] end,
				CanSave = function() return true end,
				SaveAsync = function() saves.count += 1 return saves.ok end,
			},
			GameService = {
				IsReady = function(_, p) return datas[p] ~= nil end,
				T = fakeT,
				GetStats = function() return { PerSecond = 1000, ClickValue = 10 } end,
				AddDopamine = function(_, p, amount) datas[p].Dopamine += amount end,
				Notify = function(_, _p, payload) table.insert(notifies, payload) end,
				SendState = function() end,
				MarkDirty = function() end,
				NotifyAll = function() end,
			},
			MinigameService = {
				GrantPurchasedTickets = function(_, p, amount)
					datas[p].Tickets += amount
					return amount, datas[p].Tickets
				end,
			},
			EventService = { StartRush = function() end },
		}
		local shared = { Config = Config, Formulas = Formulas, Locale = fakeLocale, NumberFormatter = N }
		local ReplicatedStorage = { Shared = {} }
		for k in pairs(shared) do ReplicatedStorage.Shared[k] = k end
		local Service = loadModule(MONETIZATION_SRC, "MonetizationService", {
			require = function(x) return shared[x] end,
			game = { GetService = function(_, n)
				if n == "MarketplaceService" then return MPS end
				if n == "Players" then return players end
				if n == "RunService" then return { IsStudio = function() return false end } end
				return ReplicatedStorage
			end },
			Enum = { ProductPurchaseDecision = Decision },
			task = fakeTask,
			warn = function() end,
			print = function() end,
		})
		Service:Init(services)
		Service:Start()
		check(type(MPS.ProcessReceipt) == "function", "ProcessReceipt défini")
		local receipt = 0
		local function buy(productId, purchaseId)
			receipt += 1
			return MPS.ProcessReceipt({ PlayerId = P.UserId, ProductId = productId, PurchaseId = purchaseId or ("P" .. receipt) })
		end
		-- Chaque pack de tickets : accordé, même solde que l'arcade, bandeau "Purchase"
		local expected = 3
		for _, p in ipairs(Config.Monetization.Products) do
			if p.Kind == "Tickets" and p.ProductId ~= 0 then
				local decision = buy(p.ProductId)
				eq(check, decision, Decision.PurchaseGranted, "pack accordé " .. p.Id)
				expected += p.Tickets
				eq(check, datas[P].Tickets, expected, "tickets après " .. p.Id)
				local last = notifies[#notifies]
				check(last and last.Type == "Purchase" and last.Tickets == p.Tickets and type(last.Title) == "string", "bandeau d'achat " .. p.Id)
			end
		end
		eq(check, expected, 3 + 5 + 10 + 25 + 50 + 100, "total des 5 packs")
		-- Même achat renvoyé par Roblox : rien de plus
		local pack5 = Config.ProductsById.Tickets5
		eq(check, buy(pack5.ProductId, "SAME"), Decision.PurchaseGranted, "1er reçu")
		eq(check, buy(pack5.ProductId, "SAME"), Decision.PurchaseGranted, "reçu en double")
		eq(check, datas[P].Tickets, expected + 5, "jamais accordé deux fois")
		-- Sauvegarde ratée : Roblox réessaiera, mais sans redonner
		saves.ok = false
		eq(check, buy(pack5.ProductId, "RETRY"), Decision.NotProcessedYet, "sauvegarde ratée")
		saves.ok = true
		eq(check, buy(pack5.ProductId, "RETRY"), Decision.PurchaseGranted, "nouvel essai")
		eq(check, datas[P].Tickets, expected + 10, "accordé une seule fois malgré l'échec")
		-- Produit inconnu
		eq(check, buy(123456789), Decision.NotProcessedYet, "produit inconnu")
		-- Combo (le jour où l'ID est collé) : tickets + Dopamine
		local combo = Config.ProductsById.ComboStarter
		Config.ProductsByProductId[900001] = combo
		local ticketsBefore, dopamineBefore = datas[P].Tickets, datas[P].Dopamine
		eq(check, buy(900001), Decision.PurchaseGranted, "combo accordé")
		eq(check, datas[P].Tickets, ticketsBefore + combo.Tickets, "tickets du combo")
		eq(check, datas[P].Dopamine - dopamineBefore, Formulas.ScaledReward({ PerSecond = 1000, ClickValue = 10 }, combo.Seconds, combo.Minimum), "Dopamine du combo")
		-- Objet stylé (pas encore codé) : jamais accordé, jamais enregistré
		local style = Config.ProductsById.StyleGoldenTrail
		Config.ProductsByProductId[900002] = style
		local purchases = #datas[P].Purchases
		eq(check, buy(900002, "STYLE"), Decision.NotProcessedYet, "objet stylé refusé")
		eq(check, #datas[P].Purchases, purchases, "achat stylé non enregistré")
		Config.ProductsByProductId[900001] = nil
		Config.ProductsByProductId[900002] = nil
	end)
end
"""


def arcade_shop_test():
    """Tests ARCADESHOP : injecte ArcadeConfig, MinigameService et
    MonetizationService (sources telles quelles) puis ARCADE_SHOP_TESTS."""
    services = os.path.join(SRC, "ServerScriptService", "Services")
    sources = [
        ("ARCADE_SRC", os.path.join(SHARED, "ArcadeConfig.luau")),
        ("MINIGAME_SRC", os.path.join(services, "MinigameService.luau")),
        ("MONETIZATION_SRC", os.path.join(services, "MonetizationService.luau")),
    ]
    lines = []
    for name, path in sources:
        body = read(path)
        if "]=====]" in body:
            raise ValueError("délimiteur ]=====] interdit dans " + path)
        lines.append("local %s = [=====[%s]=====]" % (name, body))
    return "\n".join(lines) + "\n" + ARCADE_SHOP_TESTS


FRIEND_MAIL_TESTS = r"""
do
	local fn, err = loadstring(FRIEND_MAIL_SRC, "=FriendMailRules")
	assert(fn, err)
	local R = fn()
	local NOW = 1760000000

	test("FriendMailRules : anti-spam (10 min / 2 min, horloge abîmée ou en avance)", function(check)
		eq(check, R.NewInterval, 600, "1 mail / 10 min")
		eq(check, R.ReplyInterval, 120, "1 réponse / 2 min")
		local ok, left = R.Check({ LastNew = 0, LastReply = 0 }, NOW, false)
		check(ok and left == 0, "jamais envoyé : autorisé")
		ok, left = R.Check({ LastNew = NOW - 148, LastReply = 0 }, NOW, false)
		check(not ok and left == 452, "envoyé il y a 148 s : encore 452 s (" .. tostring(left) .. ")")
		ok, left = R.Check({ LastNew = NOW - 148, LastReply = 0 }, NOW, true)
		check(ok and left == 0, "la réponse a son propre délai")
		ok, left = R.Check({ LastNew = 0, LastReply = NOW - 30 }, NOW, true)
		check(not ok and left == 90, "réponse il y a 30 s : encore 90 s")
		ok = R.Check({ LastNew = NOW - 600 }, NOW, false)
		check(ok, "pile 10 min : autorisé")
		ok, left = R.Check({ LastNew = NOW + 5000 }, NOW, false)
		check(not ok and left == 600, "date dans le futur = maintenant (pas de blocage éternel)")
		ok = R.Check({ LastNew = 0 / 0 }, NOW, false)
		check(ok, "NaN = jamais envoyé")
		ok = R.Check(nil, NOW, false)
		check(ok, "pas de données : autorisé")
		eq(check, R.Countdown(452), "7:32", "compte à rebours")
		eq(check, R.Countdown(59.2), "1:00", "arrondi au-dessus")
		eq(check, R.Countdown(0), "0:00", "zéro")
		eq(check, R.Countdown(3723), "1:02:03", "heures")
	end)

	test("FriendMailRules : boîte stockée (30 max, 30 jours, doublons, invalides)", function(check)
		local list = {}
		for i = 1, 40 do
			table.insert(list, { Id = "m" .. i, F = 100 + i, S = "s", B = "b", T = NOW - i * 3600 })
		end
		table.insert(list, { Id = "old", F = 5, S = "s", B = "b", T = NOW - 31 * 86400 })
		table.insert(list, { Id = "m3", F = 999, S = "dup", B = "b", T = NOW })
		table.insert(list, { Id = "bad", F = -1, S = "s", B = "b", T = NOW })
		table.insert(list, { Id = "bad2", F = 7, S = 12, B = "b", T = NOW })
		table.insert(list, "garbage")
		local kept = R.TrimInbox(list, NOW)
		eq(check, #kept, 30, "30 mails gardés")
		eq(check, kept[1].Id, "m1", "le plus récent d'abord")
		eq(check, kept[30].Id, "m30", "les plus vieux partent")
		local ids = {}
		for _, r in ipairs(kept) do
			check(not ids[r.Id], "doublon " .. r.Id)
			ids[r.Id] = true
		end
		check(not ids.old and not ids.bad and not ids.bad2, "vieux / invalides retirés")
		eq(check, #R.TrimInbox(nil, NOW), 0, "boîte absente")
		local appended = R.Append(kept, { Id = "new", F = 42, S = "hi", B = "yo", T = NOW }, NOW)
		eq(check, #appended, 30, "ajout : toujours 30")
		eq(check, appended[1].Id, "new", "ajout en tête")
		local ops = { Delete = { m1 = true }, Read = { m2 = true }, Replied = { m4 = true }, Blocked = { ["103"] = true } }
		local applied = R.ApplyOps(kept, ops, NOW)
		local byId = {}
		for _, r in ipairs(applied) do byId[r.Id] = r end
		check(byId.m1 == nil, "supprimé")
		check(byId.m2 and byId.m2.Rd == true, "lu")
		check(byId.m4 and byId.m4.Rp == true, "répondu")
		check(byId.m3 == nil, "expéditeur bloqué (103) retiré")
	end)

	test("FriendMailRules : nettoyage du texte et des données", function(check)
		eq(check, R.Clean("  hello \n\t world  ", 60), "hello world", "espaces")
		eq(check, R.Clean(string.rep("é", 80), 60), string.rep("é", 60), "coupe UTF-8 à 60 caractères")
		eq(check, R.Clean("\255\254", 60), "", "UTF-8 invalide refusé")
		eq(check, R.Clean(42, 60), "", "pas un texte")
		check(#R.Clean(string.rep("a", 100000), 300) == 300, "très long : coupé")
		check(R.ValidUserId(12345) and not R.ValidUserId(0) and not R.ValidUserId(1.5) and not R.ValidUserId("1"), "UserId")
		local clean = R.SanitizeData({ LastNew = NOW + 999, LastReply = -4, Blocked = { ["12"] = true, x = true, ["13"] = "yes", [14] = true } }, NOW)
		eq(check, clean.LastNew, NOW, "futur ramené à maintenant")
		eq(check, clean.LastReply, 0, "négatif = 0")
		check(clean.Blocked["12"] == true and clean.Blocked["14"] == true, "blocages gardés (clés texte)")
		check(clean.Blocked.x == nil and clean.Blocked["13"] == nil, "blocages invalides retirés")
		local fresh = R.SanitizeData(nil, NOW)
		check(fresh.LastNew == 0 and fresh.LastReply == 0 and next(fresh.Blocked) == nil, "données absentes")
	end)

	test("FriendMailRules : secours du filtre (jamais le brut) et lecture prudente des amis", function(check)
		eq(check, R.ShownText("pour toi", "pour tous"), "pour toi", "filtre du destinataire d'abord")
		eq(check, R.ShownText(nil, "pour ######"), "pour ######", "échec : version pour tout le monde")
		eq(check, R.ShownText("", "x"), "", "texte vide filtré = vide")
		check(R.ShownText(nil, nil) == nil, "aucune version filtrée : pas montré")
		check(R.ShownText(nil, 42) == nil, "secours abîmé : pas montré")
		local id, name, display = R.ReadFriend({ Id = 222, Username = "lea_rblx", DisplayName = "Léa" })
		check(id == 222 and name == "lea_rblx" and display == "Léa", "FriendPages (Id, Username, DisplayName)")
		id, name, display = R.ReadFriend({ VisitorId = 333, UserName = "maxou99", IsOnline = true })
		check(id == 333 and name == "maxou99" and display == "maxou99", "GetFriendsOnlineAsync (VisitorId, UserName)")
		id, name, display = R.ReadFriend({ UserId = "444", DisplayName = "Sam" })
		check(id == 444 and name == "Sam" and display == "Sam", "UserId en texte, seulement DisplayName")
		check(R.ReadFriend({ Id = -3 }) == nil and R.ReadFriend({ Id = 1.5 }) == nil and R.ReadFriend("x") == nil, "invalides")
	end)
end
"""


GARDEN_SNAPSHOT_TESTS = r"""
do
	local fn, err = loadstring(GARDEN_SNAPSHOT_SRC, "=GardenSnapshot")
	assert(fn, err)
	setfenv(fn, setmetatable({ require = function(name) return req(name) end, script = { Parent = { Config = "Config" } } }, { __index = getfenv() }))
	local GS = fn()

	-- valeurs sûres pour le JSON / un RemoteEvent (pas de NaN, tableaux denses)
	local function jsonSafe(value, depth)
		depth = depth or 0
		local t = type(value)
		if t == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
		if t == "string" or t == "boolean" then return true end
		if t ~= "table" or depth > 6 then return false end
		local n, count = #value, 0
		for k, v in pairs(value) do
			count += 1
			if type(k) ~= "string" and not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then return false end
			if not jsonSafe(v, depth + 1) then return false end
		end
		return n == 0 or count == n
	end
	local function ser(v)
		if type(v) ~= "table" then return tostring(v) end
		local keys = {}
		for k in pairs(v) do table.insert(keys, tostring(k)) end
		table.sort(keys)
		local out = {}
		for _, k in ipairs(keys) do table.insert(out, k .. "=" .. ser(v[k] ~= nil and v[k] or v[tonumber(k)])) end
		return "{" .. table.concat(out, ",") .. "}"
	end

	test("GardenSnapshot : données absentes ou abîmées -> verrouillé, jamais d'erreur", function(check)
		for _, data in ipairs({ nil, {}, { Upgrades = "x" }, { Upgrades = {}, Garden = 5 }, { Upgrades = { Garden = 0 / 0 } } }) do
			local ok, snap = pcall(GS.From, data)
			check(ok and snap.Unlocked == false and #snap.Plots == 0, "From(" .. ser(data) .. ")")
			check(ok and jsonSafe(snap), "JSON : " .. ser(data))
		end
		local s = GS.Sanitize("n'importe quoi")
		check(s.Unlocked == false and #s.Plots == 0 and s.Count >= 1, "Sanitize(texte)")
	end)

	test("GardenSnapshot : parterres, maximum, moulin, fleurs invalides vidées", function(check)
		local data = { Upgrades = { Garden = 1, GardenPlots = 2, Pinwheel = 1 }, Garden = { Plots = {
			{ Flower = "Rose", PlantedAt = 1000, ReadyAt = 1240 },
			{ Flower = "Cactus", PlantedAt = 1000, ReadyAt = 1060 },
			{ Flower = "Daisy", PlantedAt = 0 / 0, ReadyAt = 5 },
			"vide",
			{ Flower = "Lotus", PlantedAt = 2000.7, ReadyAt = 100 },
		} } }
		local snap = GS.From(data)
		check(snap.Unlocked and snap.Windmill, "débloqué + moulin")
		check(snap.Count == Formulas.GetGardenPlotCount(data), "Count = Formulas.GetGardenPlotCount")
		check(#snap.Plots == snap.Count, "un parterre par parterre possédé")
		local maxPlots = Config.Garden.BasePlots
		for _, u in ipairs(Config.Upgrades) do
			if u.Feature == "GardenPlots" then maxPlots += u.MaxLevel end
		end
		check(snap.Max == maxPlots, "Max = BasePlots + niveaux max (" .. tostring(snap.Max) .. ")")
		check(snap.Plots[1].Flower == "Rose" and snap.Plots[1].ReadyAt == 1240, "rose gardée")
		check(snap.Plots[2].Flower == "" and snap.Plots[3].Flower == "" and snap.Plots[4].Flower == "", "fleur inconnue / NaN / texte -> vide")
		check(snap.Plots[5].PlantedAt == 2000 and snap.Plots[5].ReadyAt >= snap.Plots[5].PlantedAt, "dates entières, jamais prête avant d'être plantée")
		check(jsonSafe(snap), "JSON")
		check(ser(GS.From(data)) == ser(snap), "stable (aucune heure dedans)")
		check(ser(GS.Sanitize(snap)) == ser(snap), "Sanitize(From(x)) == From(x)")
		check(ser(GS.From(data)):len() < 900, "petit")
	end)

	test("GardenSnapshot : stades graine -> pousse -> bouton -> fleur -> prête", function(check)
		local order = { Seed = 0, Sprout = 1, Bud = 2, Bloom = 3, Ready = 4 }
		for _, flower in ipairs(Config.Garden.Flowers) do
			local plot = { Flower = flower.Id, PlantedAt = 0, ReadyAt = flower.GrowSeconds }
			local last = -1
			for step = 0, 20 do
				local stage = GS.Stage(plot, flower.GrowSeconds * step / 20)
				check(order[stage] ~= nil and order[stage] >= last, flower.Id .. " : stade " .. tostring(stage))
				last = order[stage] or last
			end
			check(GS.Stage(plot, 0) == "Seed" and GS.Stage(plot, flower.GrowSeconds) == "Ready", flower.Id .. " : début / fin")
			check(GARDEN_BUILDER_FLOWERS[flower.Id] == true, flower.Id .. " : pas de fleur 3D dans GardenBuilder")
		end
		check(GS.Stage({ Flower = "", PlantedAt = 0, ReadyAt = 0 }, 10) == "Empty", "vide")
	end)
end
"""


def garden_snapshot_test():
    """Tests GARDEN3D95 : Shared/GardenSnapshot (instantané du jardin pour la
    ville) + chaque fleur de Config.Garden a sa fleur 3D dans GardenBuilder."""
    body = read(os.path.join(SHARED, "GardenSnapshot.luau"))
    if "]=====]" in body:
        raise ValueError("délimiteur ]=====] interdit dans GardenSnapshot.luau")
    builder = read(os.path.join(SRC, "ReplicatedStorage", "Client", "World", "GardenBuilder.luau"))
    styles = re.search(r"local FLOWER_STYLE[^\n]*\n(.*?)\n}", builder, re.S)
    ids = re.findall(r"^\t(\w+) = \{", styles.group(1), re.M) if styles else []
    flowers = "local GARDEN_BUILDER_FLOWERS = { %s }\n" % ", ".join("%s = true" % i for i in ids)
    return "local GARDEN_SNAPSHOT_SRC = [=====[%s]=====]\n%s%s" % (body, flowers, GARDEN_SNAPSHOT_TESTS)


def friend_mail_test():
    """Tests MAILFRIENDS : règles pures des mails entre amis (Shared/FriendMailRules)."""
    body = read(os.path.join(SHARED, "FriendMailRules.luau"))
    if "]=====]" in body:
        raise ValueError("délimiteur ]=====] interdit dans FriendMailRules.luau")
    return "local FRIEND_MAIL_SRC = [=====[%s]=====]\n%s" % (body, FRIEND_MAIL_TESTS)


WORLD_LAYOUT_TESTS = r"""
do
	local fn, err = loadstring(WORLD_LAYOUT_SRC, "=WorldLayout")
	assert(fn, err)
	local L = fn()
	local SIZES = { Config.HouseSizesById.Studio, Config.HouseSizesById.Apartment, Config.HouseSizesById.Loft, Config.HouseSizesById.Mansion }
	local ratio = Config.House.WallRatio

	test("WorldLayout : 2D -> 3D -> 2D (sol) retombe sur les mêmes X / Y", function(check)
		for _, size in ipairs(SIZES) do
			local dims = L.RoomDims(size, ratio)
			for _, fd in ipairs({ 0.6, 2.2, 4 }) do
				for X = 0.1, 0.91, 0.1 do
					for Y = ratio + 0.08, 0.99, 0.07 do
						local x, z = L.FloorForward(dims, X, Y, 1, fd)
						-- (hors des bords bornés : l'aller-retour est exact)
						local zFront = z + fd / 2
						if zFront > fd + 0.09 and zFront < dims.D - 0.11 then
							local X2, Y2 = L.FloorInverse(dims, x, z, fd)
							check(math.abs(X2 - X) < 1e-6 and math.abs(Y2 - Y) < 1e-6,
								string.format("%s X %.3f Y %.3f -> %.5f %.5f", size.Id, X, Y, X2, Y2))
						end
					end
				end
			end
		end
	end)

	test("WorldLayout : objets muraux (aller-retour) et bornes", function(check)
		for _, size in ipairs(SIZES) do
			local dims = L.RoomDims(size, ratio)
			for X = 0.15, 0.86, 0.1 do
				for Y = 0.08, ratio - 0.08, 0.05 do
					local k = 0.03
					local x, y = L.WallForward(dims, X, Y, 1, k)
					local X2, Y2 = L.WallInverse(dims, x, y, k)
					check(math.abs(X2 - X) < 1e-6 and math.abs(Y2 - Y) < 1e-6, string.format("%s mur %.2f %.2f -> %.4f %.4f", size.Id, X, Y, X2, Y2))
				end
			end
			-- un pointeur hors de la pièce reste dans la zone du sol / du mur
			local X, Y = L.FloorInverse(dims, 999, -50, 2)
			check(X == 1 and Y >= ratio and Y <= 1, "sol : borné")
			local WX, WY = L.WallInverse(dims, -999, 999, 0.03)
			check(WX == 0 and WY >= 0 and WY <= ratio, "mur : borné")
		end
	end)

	-- (v9.6 PLACE96) UNE zone valide pour l'éditeur 2D, l'édition 3D et le serveur
	test("WorldLayout v9.6 : aller-retour 2D -> 3D -> 2D (positions au hasard dans la zone valide)", function(check)
		-- (petit générateur déterministe : pas de Random dans la CLI Luau)
		local seed = 96
		local rng = {}
		function rng:NextNumber(a: number?, b: number?): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			local t = seed / 2147483648
			if a and b then
				return a + (b - a) * t
			end
			return t
		end
		local bad = 0
		local count = 0
		for _, size in ipairs(SIZES) do
			local dims = L.RoomDims(size, ratio)
			for _ = 1, 400 do
				local sizePx = rng:NextNumber(40, 160) * rng:NextNumber(0.6, 1.6)
				local fw = sizePx * L.PX * rng:NextNumber(0.5, 0.95)
				local fd = rng:NextNumber(0.3, 3)
				local against = rng:NextNumber() < 0.3
				local x0, x1, y0, y1 = L.PlacementArea("Floor", sizePx, dims.RoomWpx, dims.RoomHpx, ratio)
				local X, Y = L.ClampToArea(rng:NextNumber(x0, x1), rng:NextNumber(y0, y1), x0, x1, y0, y1)
				-- 3D (ce que montre le fantôme) puis relâché : la 2D sauvée retombe au même endroit 3D
				local x, z = L.FloorForward(dims, X, Y, fw, fd, against)
				local x2, z2, X2, Y2 = L.FloorClamp(dims, x, z, fw, fd, x0, x1, y0, y1, against)
				local x3, z3 = L.FloorForward(dims, X2, Y2, fw, fd, against)
				count += 1
				-- le fantôme montré = l'image 3D exacte de la 2D sauvée (point fixe)
				if not (math.abs(x3 - x2) < 1e-6 and math.abs(z3 - z2) < 1e-6) then
					bad += 1
				end
				-- hors des bords bornés par la 3D (murs de côté / fond / devant) : la 2D revient à l'identique
				local zFront = z + fd / 2
				local limit = dims.W / 2 - fw / 2 - 0.1
				if not against and math.abs(x) < limit - 1e-6 and zFront > fd + 0.09 and zFront < dims.D - 0.11 then
					if not (math.abs(X2 - X) < 2e-4 and math.abs(Y2 - Y) < 2e-4) then
						bad += 1
					end
				end
				if not (X2 >= x0 - 1e-9 and X2 <= x1 + 1e-9 and Y2 >= y0 - 1e-9 and Y2 <= y1 + 1e-9) then
					bad += 1
				end
				-- mur
				local w0, w1, v0, v1 = L.PlacementArea("Wall", sizePx, dims.RoomWpx, dims.RoomHpx, ratio)
				local WX, WY = L.ClampToArea(rng:NextNumber(w0, w1), rng:NextNumber(v0, v1), w0, w1, v0, v1)
				local k = sizePx * L.PX / 100
				local wx, wy = L.WallForward(dims, WX, WY, fw, k)
				local wx2, wy2, WX2, WY2 = L.WallClamp(dims, wx, wy, fw, k, w0, w1, v0, v1)
				local wx3, wy3 = L.WallForward(dims, WX2, WY2, fw, k)
				if not (math.abs(wx3 - wx2) < 1e-6 and math.abs(wy3 - wy2) < 1e-6) then
					bad += 1
				end
				local wlimit = dims.W / 2 - math.min(fw / 2, dims.W / 2) - 0.1
				if math.abs(wx) < wlimit - 1e-6 and not (math.abs(WX2 - WX) < 2e-4 and math.abs(WY2 - WY) < 2e-4) then
					bad += 1
				end
			end
		end
		check(bad == 0, string.format("%d / %d allers-retours faux", bad, count))
	end)

	test("WorldLayout v9.6 : les extrêmes 3D restent dans la zone 2D (plus aucun débordement)", function(check)
		for _, size in ipairs(SIZES) do
			local dims = L.RoomDims(size, ratio)
			for _, sizePx in ipairs({ 40, 80, 120, 160 * 1.6 }) do
				local fw, fd = sizePx * L.PX * 0.9, 2
				local x0, x1, y0, y1 = L.PlacementArea("Floor", sizePx, dims.RoomWpx, dims.RoomHpx, ratio)
				for _, x in ipairs({ -999, -dims.W / 2, 0, dims.W / 2, 999 }) do
					for _, z in ipairs({ -50, 0, fd / 2, dims.D / 2, dims.D, 500 }) do
						local _, _, X, Y = L.FloorClamp(dims, x, z, fw, fd, x0, x1, y0, y1, false)
						check(X >= x0 - 1e-9 and X <= x1 + 1e-9 and Y >= y0 - 1e-9 and Y <= y1 + 1e-9, string.format("%s sol %d (%.1f, %.1f) -> %.4f %.4f", size.Id, sizePx, x, z, X, Y))
					end
				end
				local w0, w1, v0, v1 = L.PlacementArea("Wall", sizePx, dims.RoomWpx, dims.RoomHpx, ratio)
				for _, x in ipairs({ -999, 0, 999 }) do
					for _, y in ipairs({ -20, 0, 6, L.WALL_H, 40 }) do
						local _, _, X, Y = L.WallClamp(dims, x, y, fw, sizePx * L.PX / 100, w0, w1, v0, v1)
						check(X >= w0 - 1e-9 and X <= w1 + 1e-9 and Y >= v0 - 1e-9 and Y <= v1 + 1e-9, string.format("%s mur %d (%.1f, %.1f) -> %.4f %.4f", size.Id, sizePx, x, y, X, Y))
					end
				end
			end
			-- la zone garde l'objet dans la pièce 2D : bords visibles et tête sous le plafond
			local x0, x1, y0 = L.PlacementArea("Floor", 160, dims.RoomWpx, dims.RoomHpx, ratio)
			check(x0 * dims.RoomWpx >= 160 * 0.38 - 1e-6 and (1 - x1) * dims.RoomWpx >= 160 * 0.38 - 1e-6, size.Id .. " : largeur dans la pièce")
			check(y0 >= ratio + 0.035 - 1e-9, size.Id .. " : pieds sous le mur")
		end
		-- valeurs arrondies à 0,0001 sans ressortir des bornes
		local X, Y = L.ClampToArea(0.123456, 2, 0.12346, 0.9, 0.5, 0.98549)
		check(X >= 0.12346 - 1e-9 and Y <= 0.98549 + 1e-9, "arrondi dans les bornes " .. X .. " " .. Y)
	end)

	test("WorldLayout : maison, pièces, parcelles", function(check)
		for _, size in ipairs(SIZES) do
			local dims = L.Dims(size)
			check(dims.Width <= L.PLOT_W - 16, size.Id .. " : la maison tient sur la parcelle (" .. dims.Width .. ")")
			for slot = 1, size.Floors * size.Columns do
				local floor, column = L.SlotCell(size, slot)
				eq(check, (floor - 1) * size.Columns + column, slot, size.Id .. " emplacement")
				local x, y, d = L.RoomCenter(size, slot)
				eq(check, L.SlotAt(size, x, y + 1, d), slot, size.Id .. " SlotAt(centre)")
				check(L.InsideHouse(size, x, y, d, 0), size.Id .. " centre dans la maison")
				local xMin, xMax = L.RoomInterior(size, slot)
				check(math.abs((xMax - xMin) - L.RoomWidth(size)) < 1e-9, size.Id .. " largeur intérieure = coque")
			end
			-- (v9.4) cage à droite ou au milieu (comme la 2D)
			local h0, h1 = L.HallSpan(size)
			check(L.SlotAt(size, (h0 + h1) / 2, L.FloorY(1) + 2, 10) == nil, size.Id .. " : la cage n'est pas une pièce")
			check(not L.InsideHouse(size, 0, 3, -8, 0), size.Id .. " : le jardin n'est pas dans la maison")
			-- porte d'entrée dans la cage, face à l'escalier
			local door = L.DoorX(size)
			check(door - L.DOOR_W / 2 >= h0 and door + L.DOOR_W / 2 <= h1, size.Id .. " porte")
			local s0, s1 = L.StairSpan(size)
			check(s0 > h0 + 2.5 and s1 < h1 - 2.5, size.Id .. " escalier au milieu de la cage (couloirs de chaque côté)")
			-- colonnes contiguës hors de la cage, sans chevauchement
			for column = 1, size.Columns do
				local c0, c1 = L.ColumnSpan(size, column)
				check(c1 <= h0 + 1e-9 or c0 >= h1 - 1e-9, size.Id .. " colonne " .. column .. " hors de la cage")
				eq(check, L.ColumnAt(size, (c0 + c1) / 2), column, size.Id .. " ColumnAt")
			end
			-- passages : chaque pièce touche la cage ou une voisine
			for column = 1, size.Columns do
				check(#L.RoomDoors(size, column) >= 1, size.Id .. " passages")
			end
		end
		-- (v9.4) escalier : pente <= 40°, hauteur libre >= 7 partout, haut au ras de l'étage
		check(L.StairSlope() <= 40, "pente de l'escalier " .. L.StairSlope())
		eq(check, L.STAIR_STEPS * L.STAIR_RISE, L.STORY, "13 marches = un étage")
		check(math.abs(L.StairHeight(L.STAIR_D1) - L.STORY) < 1e-9, "haut de la rampe au ras de l'étage")
		check(L.StairHeight(L.STAIR_D0) == 0, "bas de la rampe au sol")
		local minHead = math.huge
		for i = 0, 200 do
			local d = L.STAIR_D0 + (L.STAIR_D1 - L.STAIR_D0) * i / 200
			local ceiling = d < L.STAIR_HOLE_D0 and L.WALL_H or (L.STORY + L.WALL_H - 1.2)
			minHead = math.min(minHead, ceiling - L.StairHeight(d))
		end
		check(minHead >= 7, "hauteur libre sur l'escalier " .. minHead)
		check(L.STAIR_D1 <= L.WALL_T + L.DEPTH - 2, "palier du haut")
		for _, n in ipairs({ 4, 8, 12 }) do
			local r = L.PlotRadius(n)
			local x1, z1 = L.PlotPlace(1, n)
			local x2, z2 = L.PlotPlace(2, n)
			local frontR = r - L.PLOT_D / 2
			-- coins avant de deux parcelles voisines : jamais l'un sur l'autre
			local gap = 2 * frontR * math.sin(math.pi / n) - L.PLOT_W * math.cos(math.pi / n)
			check(gap > 0, n .. " parcelles : coins avant séparés (" .. gap .. ")")
			check(math.abs(math.sqrt(x1 * x1 + z1 * z1) - r) < 1e-6 and math.abs(math.sqrt(x2 * x2 + z2 * z2) - r) < 1e-6, "rayon")
			check(L.RingRoadRadius(n) > L.PLAZA_R + 60, "route loin de la place")
		end
		eq(check, L.PlotCount(50), 12, "PlotCount max")
		eq(check, L.PlotCount(1), 4, "PlotCount min")
		eq(check, L.PlotCount(nil), 8, "PlotCount défaut")
	end)

	test("WorldLayout : rotation R (sauvegarde)", function(check)
		eq(check, L.NormalizeRotation(nil), nil, "nil")
		eq(check, L.NormalizeRotation(0), nil, "0 -> nil")
		eq(check, L.NormalizeRotation(360), nil, "360 -> nil")
		eq(check, L.NormalizeRotation(45), 45, "45")
		eq(check, L.NormalizeRotation(44), 45, "arrondi 15")
		eq(check, L.NormalizeRotation(-45), 315, "négatif")
		eq(check, L.NormalizeRotation(0 / 0), nil, "NaN")
		eq(check, L.NormalizeRotation(math.huge), nil, "inf")
		eq(check, L.NormalizeRotation("90"), nil, "texte")
		eq(check, L.Rotate(nil, 45), 45, "tourner")
		eq(check, L.Rotate(315, 45), nil, "tour complet")
		eq(check, L.Rotate(0, -45), 315, "sens inverse")
		eq(check, L.Snap(3.4, 1), 3, "grille")
		eq(check, L.Snap(3.5, 1), 4, "grille (milieu)")
	end)

	test("WorldLayout : ouverture, visites, j'aime (limites par jour)", function(check)
		check(L.CanEnter("Everyone", false, false), "tout le monde")
		check(L.CanEnter("Friends", false, true) and not L.CanEnter("Friends", false, false), "amis")
		check(not L.CanEnter("Nobody", false, true), "personne")
		check(L.CanEnter("Nobody", true, false), "le propriétaire entre toujours")
		eq(check, L.NormalizeOpen("Hack"), "Everyone", "valeur inconnue")
		local now = 1760000000
		local liker = L.SanitizeTown(nil, now)
		local owner = L.SanitizeTown({ Open = "Friends", Likes = 5, Visits = "x", Liked = "bad" }, now)
		eq(check, owner.Open, "Friends", "Open gardé")
		eq(check, owner.Likes, 5, "Likes gardés")
		eq(check, owner.Visits, 0, "Visits réparé")
		local ok, why = L.CanLike(liker, 1, 1)
		check(not ok and why == "Self", "pas sa propre maison")
		ok = L.CanLike(liker, 1, 2)
		check(ok, "premier j'aime")
		check(L.ApplyLike(liker, owner, 2), "récompense du propriétaire")
		eq(check, owner.Likes, 6, "compteur")
		ok, why = L.CanLike(liker, 1, 2)
		check(not ok and why == "Already", "une fois par maison et par jour")
		for id = 3, 11 do
			L.ApplyLike(liker, owner, id)
		end
		ok, why = L.CanLike(liker, 1, 99)
		check(not ok and why == "Limit", "10 par jour")
		-- le lendemain tout repart
		local tomorrow = L.SanitizeTown(liker, now + 86400)
		check(L.CanLike(tomorrow, 1, 2), "nouveau jour")
		eq(check, tomorrow.LikesGiven, 0, "remis à zéro")
		-- récompenses reçues : 30 par jour au plus
		local busy = L.SanitizeTown({ LikedRewards = 30, RewardDay = L.DayNumber(now) }, now)
		check(not L.ApplyLike(L.SanitizeTown(nil, now), busy, 7), "plafond des récompenses")
		eq(check, busy.Likes, 1, "le j'aime compte quand même")
		eq(check, L.RewardAmount(1000, 60), 60000, "60 s de production")
		eq(check, L.RewardAmount(0 / 0, 60), 0, "NaN")
		eq(check, L.RewardAmount(-5, 60), 0, "négatif")
	end)
end
"""


def world_layout_test():
    """Tests WORLD93 : géométrie de Dopamine Town, 2D <-> 3D, règles (Shared/WorldLayout)."""
    body = read(os.path.join(SHARED, "WorldLayout.luau"))
    if "]=====]" in body:
        raise ValueError("délimiteur ]=====] interdit dans WorldLayout.luau")
    return "local WORLD_LAYOUT_SRC = [=====[%s]=====]\n%s" % (body, WORLD_LAYOUT_TESTS)


GARAGE_TESTS = r"""
do
	local fnW, errW = loadstring(GARAGE_WORLD_SRC, "=WorldLayout")
	assert(fnW, errW)
	local WL = fnW()
	local fnG, errG = loadstring(GARAGE_LAYOUT_SRC, "=GarageLayout")
	assert(fnG, errG)
	local GL = fnG()

	test("Voitures v9.6 : catalogue Config.Cars (ids, modèles, prix, verrous, peintures)", function(check)
		local cars = Config.Cars
		check(type(cars) == "table" and #cars.List >= 6 and #cars.List <= 8, "6 à 8 voitures")
		local ids, colors = {}, {}
		for _, paint in ipairs(cars.Colors) do
			check(not colors[paint.Id], "peinture en double " .. tostring(paint.Id))
			colors[paint.Id] = true
			check(type(paint.Name) == "string" and type(paint.Color) == "table", "peinture " .. tostring(paint.Id))
			check(Config.CarColorsById[paint.Id] == paint, "CarColorsById " .. tostring(paint.Id))
		end
		check(#cars.Colors >= 8, "au moins 8 peintures")
		local lastCost, lastGate = 0, 0
		for index, car in ipairs(cars.List) do
			check(not ids[car.Id], "voiture en double " .. tostring(car.Id))
			ids[car.Id] = true
			check(Config.CarsById[car.Id] == car and car.Order == index, "CarsById / Order " .. car.Id)
			check(CAR_KINDS[car.Kind] == true, "modèle 3D (CarModels) " .. tostring(car.Kind))
			check(colors[car.DefaultColor] == true, "couleur par défaut " .. car.Id)
			check(type(car.Cost) == "number" and car.Cost > lastCost, "prix croissants " .. car.Id)
			check(type(car.RequiresRebirths) == "number" and car.RequiresRebirths >= lastGate, "verrous croissants " .. car.Id)
			check(type(car.Icon) == "string" and #car.Icon > 0 and type(car.Name) == "string" and type(car.Desc) == "string", "textes " .. car.Id)
			lastCost, lastGate = car.Cost, car.RequiresRebirths
		end
		check(cars.List[1].RequiresRebirths == 0, "une voiture dès le début")
		check(cars.MaxSpeed > 20 and cars.MaxSpeed <= 60, "vitesse max raisonnable")
		check(cars.IdleDespawn >= 30 and cars.SpawnCooldown >= 1 and cars.HonkCooldown >= 0.5, "délais")
		-- garage (entrée de Config.House), dans la gamme du manoir
		local garage = Config.House.Garage
		local mansion = Config.HouseSizesById[garage.RequiresSize]
		check(mansion ~= nil and mansion.Exterior == "Mansion", "garage : pour le manoir")
		check(garage.RequiresRebirths >= (mansion.RequiresRebirths or 0), "garage : verrou >= manoir")
		check(garage.Cost >= mansion.Cost * 0.5 and garage.Cost <= mansion.Cost * 20, "garage : prix dans la gamme du manoir")
		eq(check, garage.Bays, GL.BAYS, "places du garage")
	end)

	test("Voitures v9.6 : garage du manoir dans la parcelle (GarageLayout)", function(check)
		local mansion = Config.HouseSizesById.Mansion
		local dims = WL.Dims(mansion)
		local right = dims.Left + dims.Width
		check(GL.Supports(mansion) and not GL.Supports(Config.HouseSizesById.Studio), "manoir seulement")
		-- dans la cour de devant, sans toucher la maison, la tour de droite, les arbres, la boîte aux lettres, le panneau
		check(GL.D1 < 0 and GL.D0 > -WL.GARDEN_D + 4, "entre la rue et la façade")
		check(GL.X1 <= WL.PLOT_W / 2 - 4, "dans la parcelle (largeur)")
		local tx, td, tr = right + WL.WALL_T + 1, 0.5, 7 + 0.4
		local cx = math.clamp(tx, GL.X0, GL.X1)
		local cd = math.clamp(td, GL.D0, GL.D1)
		check(math.sqrt((tx - cx) ^ 2 + (td - cd) ^ 2) > tr, "loin de la tour de droite")
		check(GL.X0 > 7 + 2, "boîte aux lettres / panneau libres")
		check(GL.X1 < 83 - 3, "arbre du coin libre")
		check(GL.X0 > WL.DoorX(mansion) + 12, "allée de la porte libre")
		-- places : chaque voiture tient (largeur par la porte, longueur dedans)
		local bayW = (GL.X1 - GL.X0 - 2 * GL.WALL) / GL.BAYS
		check(GL.DOOR_W <= bayW - 1, "portes plus étroites que les places")
		check(CAR_MAX_W <= GL.DOOR_W - 1.2, "la plus large voiture passe la porte (" .. CAR_MAX_W .. ")")
		check(CAR_MAX_L <= GL.InnerDepth() - 0.4, "la plus longue voiture tient dedans (" .. CAR_MAX_L .. ")")
		check(GL.DOOR_H >= CAR_MAX_H + 0.4, "la plus haute voiture passe sous la porte")
		for bay = 1, GL.BAYS - 1 do
			check(GL.BayX(bay + 1) - GL.BayX(bay) >= CAR_MAX_W + 1, "places séparées")
		end
		check(GL.BayX(1) - GL.DOOR_W / 2 > GL.X0 + GL.WALL and GL.BayX(GL.BAYS) + GL.DOOR_W / 2 < GL.X1 - GL.WALL, "portes dans la façade")
		check(GL.Inside((GL.X0 + GL.X1) / 2, 2, (GL.D0 + GL.D1) / 2) and not GL.Inside(0, 2, 5), "Inside")
		-- attribution des places : la voiture choisie au milieu, 3 au plus
		local a = GL.Assign({ "BubbleCar", "SUV", "SportsCar", "Limo" }, "SportsCar")
		eq(check, a.SportsCar, 2, "choisie au milieu")
		check(a.BubbleCar == 1 and a.SUV == 3 and a.Limo == nil, "autres places, 3 au plus")
		local b = GL.Assign({ "CityCar" }, "")
		eq(check, b.CityCar, 2, "une seule voiture : au milieu")
	end)

	test("Voitures v9.6 : textes traduits (Config.Cars, garage)", function(check)
		for _, text in ipairs(CAR_TEXTS_MISSING) do
			check(false, "traduction française manquante : " .. text)
		end
	end)
end
"""


def garage_test():
    """Tests GARAGE96 : catalogue des voitures, garage du manoir (Shared/GarageLayout), traductions."""
    world = read(os.path.join(SHARED, "WorldLayout.luau"))
    garage = read(os.path.join(SHARED, "GarageLayout.luau"))
    models = read(os.path.join(SHARED, "CarModels.luau"))
    for body in (world, garage):
        if "]=====]" in body:
            raise ValueError("délimiteur ]=====] interdit")
    # modèles 3D (SPECS de CarModels) : largeur / longueur / hauteur max
    kinds, max_w, max_l, max_h = [], 0.0, 0.0, 0.0
    for m in re.finditer(r"^\t(\w+) = \{ L = ([\d.]+), W = ([\d.]+),.*?Belt = ([\d.]+), Roof = ([\d.]+),", models, re.M):
        kinds.append(m.group(1))
        max_l = max(max_l, float(m.group(2)))
        max_w = max(max_w, float(m.group(3)))
        max_h = max(max_h, float(m.group(5)))
    # textes à traduire (Config.Cars + garage) : clés présentes dans Shared/Lang
    config = read(os.path.join(SHARED, "Config.luau"))
    start = config.find("Config.Cars = {")
    block = config[start:config.find("\n}\n", start)] if start >= 0 else ""
    texts = re.findall(r'(?:Name|Desc) = "([^"]+)"', block)
    garage_line = re.search(r'Garage = \{ Id = "Garage", Name = "([^"]+)"', config)
    if garage_line:
        texts.append(garage_line.group(1))
    keys = set()
    lang_dir = os.path.join(SHARED, "Lang")
    for name in os.listdir(lang_dir):
        if name.endswith(".luau"):
            keys.update(re.findall(r'\["((?:[^"\\]|\\.)*)"\]\s*=', read(os.path.join(lang_dir, name))))
    missing = [t for t in texts if t not in keys]
    lua_list = "{ " + ", ".join('"%s"' % t.replace('"', '\\"') for t in missing) + " }"
    kinds_set = "{ " + ", ".join("%s = true" % k for k in kinds) + " }"
    return ("local GARAGE_WORLD_SRC = [=====[%s]=====]\nlocal GARAGE_LAYOUT_SRC = [=====[%s]=====]\n"
            "local CAR_KINDS = %s\nlocal CAR_MAX_W, CAR_MAX_L, CAR_MAX_H = %s, %s, %s\nlocal CAR_TEXTS_MISSING = %s\n%s") % (
        world, garage, kinds_set, max_w, max_l, max_h, lua_list, GARAGE_TESTS)


SIM_PATH = os.path.join(ROOT, "tests", "economy_sim.luau")


def sim_loader():
    """Le simulateur d'économie (tests/economy_sim.luau) comme module "EconomySim"."""
    body = read(SIM_PATH)
    return 'loaders["EconomySim"] = function()\nlocal require = req\n%s\nend\n' % body


ECONOMY_TESTS = r"""
do
	local Sim = req("EconomySim")

	test("Économie (simulateur) : rythme des renaissances, joueur actif sans Robux", function(check)
		local result = Sim.Run("Active", { MaxHours = 40, MaxRebirths = 10 })
		local runs = Sim.RunMinutes(result)
		local parts = {}
		for n = 1, 10 do
			table.insert(parts, "R" .. n .. "=" .. (runs[n] and tostring(math.floor(runs[n] + 0.5)) or "-"))
		end
		print("    parties (min) : " .. table.concat(parts, " "))
		check(result.Rebirths >= 10, "10 visites en moins de 40 h de jeu : " .. result.Rebirths)
		-- Chaque partie dure au moins autant que la précédente (tolérance 2 %)
		for n = 2, 10 do
			if runs[n] and runs[n - 1] then
				check(runs[n] >= runs[n - 1] * 0.98, string.format("partie R%d (%.0f min) plus courte que R%d (%.0f min)", n, runs[n], n - 1, runs[n - 1]))
			end
		end
		-- Objectifs (Sim.Targets.RunMinutes)
		for n, range in pairs(Sim.Targets.RunMinutes) do
			local minutes = runs[n]
			check(minutes ~= nil and minutes >= range[1] and minutes <= range[2],
				string.format("partie R%d : %s min hors [%d, %d]", n, tostring(minutes and math.floor(minutes + 0.5)), range[1], range[2]))
		end
		-- Début de partie : des achats tout de suite
		local first = result.Purchases[1]
		check(first ~= nil and first.T <= Sim.Targets.FirstPurchaseSeconds, "1er achat en moins de " .. Sim.Targets.FirstPurchaseSeconds .. " s")
		local early = 0
		for _, p in ipairs(result.Purchases) do
			if p.T <= 300 then
				early += 1
			end
		end
		check(early >= Sim.Targets.PurchasesIn5Min, "achats pendant les 5 premières minutes : " .. early)
		-- Tout le contenu prend des jours : R10 jamais avant Sim.Targets.MinTotalHours h de jeu actif
		local total = result.RebirthAt[10]
		check(total ~= nil and total >= Sim.Targets.MinTotalHours * 3600, "R10 trop tôt : " .. tostring(total and math.floor(total / 60)) .. " min")
	end)

	test("Économie (simulateur) : les Robux accélèrent sans casser la courbe", function(check)
		local active = Sim.RunMinutes(Sim.Run("Active", { MaxHours = 40, MaxRebirths = 5 }))
		local robux = Sim.RunMinutes(Sim.Run("Robux", { MaxHours = 40, MaxRebirths = 5 }))
		local parts = {}
		for n = 1, 5 do
			table.insert(parts, "R" .. n .. "=" .. (robux[n] and tostring(math.floor(robux[n] + 0.5)) or "-"))
		end
		print("    Game Passes x2 + VIP + auto-clic, parties (min) : " .. table.concat(parts, " "))
		for n = 1, 5 do
			check(robux[n] ~= nil and active[n] ~= nil and robux[n] < active[n], "R" .. n .. " : les Game Passes doivent faire gagner du temps")
			check(robux[n] ~= nil and active[n] ~= nil and robux[n] >= active[n] * Sim.Targets.RobuxMinRatio,
				"R" .. n .. " : partie Robux trop courte (" .. tostring(robux[n] and math.floor(robux[n])) .. " min)")
		end
		-- La courbe reste croissante dans l'ensemble (pas d'effondrement après R1)
		check(robux[5] ~= nil and robux[1] ~= nil and robux[5] >= robux[1] * 1.3, "Robux : R5 doit rester nettement plus longue que R1")
		check(robux[3] ~= nil and robux[2] ~= nil and robux[3] >= robux[2] * 0.95, "Robux : R3 plus courte que R2")
	end)
end
"""


def economy_test():
    """Tests ECONOMY93 : le simulateur tests/economy_sim.luau (vrais modules
    Shared) doit respecter les objectifs de rythme (Sim.Targets)."""
    return sim_loader() + ECONOMY_TESTS


def run_sim():
    """python3 tests/run_tests.py --sim [--robux | --whale | --sessions | --all] :
    lance le simulateur d'économie avec les vrais modules Shared et affiche le rapport."""
    profile = "Active"
    for flag, name in (("--robux", "Robux"), ("--whale", "Whale"), ("--sessions", "Sessions")):
        if flag in sys.argv:
            profile = name
    parts = [HEADER]
    for name in MODULES:
        body = read(os.path.join(SHARED, name + ".luau"))
        parts.append('loaders["%s"] = function()\nlocal require = req\n%s\nend\n' % (name, body))
    parts.append(sim_loader())
    parts.append('req("EconomySim").Main({ profile = "%s", all = %s })\n' % (profile, "true" if "--all" in sys.argv else "false"))
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(parts))
        path = f.name
    try:
        proc = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=900)
    finally:
        os.unlink(path)
    sys.stdout.write(proc.stdout)
    if proc.stderr:
        sys.stdout.write(proc.stderr)
    return proc.returncode


def main():
    if not os.path.exists(LUAU):
        print("FAIL : Luau CLI introuvable (%s)" % LUAU)
        return 1
    if "--sim" in sys.argv:
        return run_sim()
    bundle = build_bundle(config_key_test() + "\n" + lang_test() + "\n" + house_art_test() + "\n" + arcade_shop_test() + "\n" + friend_mail_test()
                          + "\n" + economy_test() + "\n" + world_layout_test() + "\n" + garden_snapshot_test() + "\n" + garage_test())
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(bundle)
        path = f.name
    try:
        proc = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=300)
    finally:
        os.unlink(path)
    sys.stdout.write(proc.stdout)
    if proc.stderr:
        sys.stdout.write(proc.stderr)
    ok = proc.returncode == 0 and not re.search(r"^FAIL ", proc.stdout, re.M)
    print("\nRÉSULTAT GLOBAL : " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
