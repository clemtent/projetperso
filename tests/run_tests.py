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

MODULES = ["Config", "NumberFormatter", "Formulas", "DVDMath"]

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
	check(Config.FeatureToUpgrade[Config.Stocks.Feature] ~= nil, "Stocks.Feature")
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
	local global = U.Boost.Value * (1 + 2 * Config.Rebirth.MultiplierPerRebirth) * (1 + Config.AchievementBonus) * (1 + Config.CosmeticBonus) * 2
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
	eq(check, Formulas.GetUpgradeCost(U.Finger, 3, 5), Formulas.GetUpgradeCost(U.Finger, 3, 0), "rebirths sans effet")
	eq(check, Formulas.GetUpgradeCost(U.Ocean, 0, 0), Config.Rebirth.BaseCost, "océan 0")
	eq(check, Formulas.GetUpgradeCost(U.Ocean, 0, 2), Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ 2, "océan 2")
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
	eq(check, Formulas.GetRebirthMultiplier(2), 1 + 2 * Config.Rebirth.MultiplierPerRebirth, "mult 2")
end)

test("Formulas.GetVisibleUpgrades : progression", function(check)
	local d = emptyData()
	local first = Formulas.GetVisibleUpgrades(d)
	eq(check, #first, Config.UpgradeBar.RevealAhead, "au début")
	for i, u in ipairs(first) do eq(check, u, Config.Upgrades[i], "ordre au début " .. i) end
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

test("Formulas casino (RTP 0.90-0.95, multiplicateurs)", function(check)
	local rtp = Formulas.GetCasinoRTP()
	print(string.format("    RTP = %.4f", rtp))
	check(rtp >= 0.90 and rtp <= 0.95, "RTP hors 0.90-0.95 : " .. rtp)
	local S = Config.Casino.Symbols
	eq(check, Formulas.GetCasinoMultiplier({ S[1].Id, S[1].Id, S[1].Id }), S[1].Triple, "triple")
	eq(check, Formulas.GetCasinoMultiplier({ S[2].Id, S[2].Id, S[1].Id }), S[2].Pair, "paire")
	eq(check, Formulas.GetCasinoMultiplier({ S[1].Id, S[2].Id, S[3].Id }), 0, "perdu")
	eq(check, Formulas.GetCasinoMultiplier({ "x", "x", "x" }), 0, "inconnu")
	for _, s in ipairs(S) do check(Config.CasinoSymbolsById[s.Id] == s, "index " .. s.Id) end
	for _, f in ipairs(Config.Casino.BetFractions) do check(f > 0 and f <= 1, "BetFraction " .. f) end
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
	check(near(H.ComfortBonusPerPoint, 0.005) and H.MaxComfortBonus == 1 and H.WallRatio > 0.3 and H.WallRatio < 0.6, "réglages")

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
			check(size.Cost > prev.Cost and size.Width > prev.Width and size.MaxItems > prev.MaxItems, "taille croissante " .. size.Id)
		end
	end
	eq(check, H.Sizes[1].Cost, 0, "studio gratuit")
	eq(check, H.Sizes[1].MaxItems, 25, "studio 25 objets")
	eq(check, H.Sizes[4].MaxItems, 90, "manoir 90 objets")

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
		Stars = true, Clouds = true, Bricks = true, Wood = true, Waves = true }, 12, "Papier peint")
	checkSkins(H.Floors, Config.HouseFloorsById, { Plain = true, Checker = true, Wood = true, Tiles = true, Carpet = true,
		Marble = true, Herringbone = true }, 10, "Sol")
	eq(check, H.Wallpapers[1].Pattern, "Stripes", "1er papier peint : rayures roses")
	eq(check, H.Floors[1].Pattern, "Checker", "1er sol : damier prune")

	-- Catégories
	local categoryIds = { "Furniture", "Decor", "Toys", "Plants", "Electronics", "Kitchen", "Doors", "Windows", "Lights", "Pets" }
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
		check(type(item.Cost) == "number" and item.Cost >= 100 and item.Cost <= 2e9 and item.Cost == math.floor(item.Cost), "Cost " .. id)
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

	-- Confort : objets connus, possédés, au plus MaxItems
	eq(check, Formulas.GetHouseComfort(nil), 0, "sans données")
	eq(check, Formulas.GetHouseComfort({}), 0, "sans maison")
	eq(check, Formulas.GetHouseComfort({ House = { Placed = "x" } }), 0, "Placed invalide")
	local sofa, rug = Config.HouseItemsById.Sofa, Config.HouseItemsById.KnittedRug
	local data = { House = { Size = "Studio", Items = { LoftBed = 1, Sofa = 2 }, Placed = {
		{ I = "LoftBed", X = 0.5, Y = 0.8, S = 1, Z = 0 },
		{ I = "Sofa", X = 0.2, Y = 0.8, S = 1, Z = 1 },
		{ I = "Sofa", X = 0.3, Y = 0.8, S = 1, Z = 2 },
		{ I = "Sofa", X = 0.4, Y = 0.8, S = 1, Z = 3 }, -- 3e canapé : seulement 2 possédés
		{ I = "KnittedRug", X = 0.4, Y = 0.8, S = 1, Z = 3 }, -- pas possédé
		{ I = "Bogus", X = 0.4, Y = 0.8 }, -- inconnu
		"pas une table",
	} } }
	eq(check, Formulas.GetHouseComfort(data), bed.Comfort + 2 * sofa.Comfort, "confort compté")
	data.House.Items.KnittedRug = 1
	eq(check, Formulas.GetHouseComfort(data), bed.Comfort + 2 * sofa.Comfort + rug.Comfort, "confort + tapis")
	-- Plafond MaxItems de la taille actuelle
	local many = { House = { Size = "Studio", Items = { KnittedRug = 1000 }, Placed = {} } }
	for i = 1, 100 do many.House.Placed[i] = { I = "KnittedRug", X = 0.5, Y = 0.9, S = 1, Z = i } end
	eq(check, Formulas.GetHouseComfort(many), H.Sizes[1].MaxItems * rug.Comfort, "studio plafonné")
	many.House.Size = "Mansion"
	eq(check, Formulas.GetHouseComfort(many), H.Sizes[4].MaxItems * rug.Comfort, "manoir plafonné")
	many.House.Size = "Inconnu"
	eq(check, Formulas.GetHouseSize(many), H.Sizes[1], "taille inconnue -> studio")

	-- Bonus : 1 + min(Max, confort x par point)
	eq(check, Formulas.GetHouseBonus(0), 1, "bonus 0")
	check(near(Formulas.GetHouseBonus(10), 1 + 10 * H.ComfortBonusPerPoint), "bonus 10")
	eq(check, Formulas.GetHouseBonus(1e9), 1 + H.MaxComfortBonus, "bonus plafonné")
	eq(check, Formulas.GetHouseBonus(-5), 1, "bonus négatif")
	eq(check, Formulas.GetHouseBonus(nil), 1, "bonus nil")
	eq(check, Formulas.GetHouseBonus(0 / 0), 1, "bonus NaN")
	-- Le bonus multiplie bien tous les gains
	local d = emptyData()
	local base = Formulas.ComputeStats(d, 1, 1)
	local boosted = Formulas.ComputeStats(d, 1, Formulas.GetHouseBonus(40))
	check(near(boosted.ClickValue, base.ClickValue * (1 + 40 * H.ComfortBonusPerPoint)), "bonus appliqué au clic")
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
	for _, list in ipairs({ H.Sizes, H.Wallpapers, H.Floors, H.Categories, H.Items }) do
		for _, entry in ipairs(list) do
			check(type(fr[entry.Name]) == "string", "pas de traduction : " .. tostring(entry.Name))
		end
	end
end)''')
    return "\n".join(lines)


def main():
    if not os.path.exists(LUAU):
        print("FAIL : Luau CLI introuvable (%s)" % LUAU)
        return 1
    bundle = build_bundle(config_key_test() + "\n" + lang_test())
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
