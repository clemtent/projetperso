"""
Tests REALISM11 (v11) : 🌈 arc-en-ciel + 🍀 pot d'or (Shared/RainbowGold).

Branché dans tests/run_tests.py (main) : rainbow_test() renvoie le code Luau
(chargeurs WorldLayout + RainbowGold, puis les tests). Vérifie :
  - l'horloge de la météo (épisodes, pas deux orages, ~3 arcs-en-ciel / h,
    fenêtres assez longues pour atteindre le pot) ;
  - les places du pot (dans la ville, hors routes / parcelles / lieux bâtis,
    ordre d'essai déterministe et distinct) ;
  - la récompense (ordre d'arrivée, minimum, plafond du jour, valeurs folles,
    anti-saut) ;
  - le RYTHME des parties (simulateur d'économie) : arriver premier à tous
    les pots payés ne raccourcit pas les parties de plus de 25 %.
"""

import os

RAINBOW_TESTS = r"""
do
	script.Parent.WorldLayout = "WorldLayout"
	script.Parent.RainbowGold = "RainbowGold"
	local RG = req("RainbowGold")
	local WL = req("WorldLayout")
	local Sim = req("EconomySim")

	test("Arc-en-ciel v11 : horloge de la météo et fenêtres de l'arc", function(check)
		local E = RG.EPISODE
		check(E == 600, "épisodes de 10 min")
		local counts, storms, prevStorm = {}, 0, false
		local events, open, shortest, longest = 0, 0, math.huge, 0
		for index = 0, 4000 do
			local kind = RG.KindOf(index)
			counts[kind] = (counts[kind] or 0) + 1
			check(not (prevStorm and kind == "Storm"), "deux orages de suite " .. index)
			prevStorm = kind == "Storm"
			local w = RG.WINDOWS[kind]
			if w then
				events += 1
				check(w[1] < w[2] and w[2] < w[3] and w[3] < w[4] and w[4] < 1, "fenêtre " .. kind)
				-- durée pendant laquelle le pot peut être atteint
				local t0, t1 = nil, nil
				for k = 0, 600 do
					local t = index * E + k
					local e = RG.Event(t)
					if e and e.Open then
						t0 = t0 or t
						t1 = t
						check(e.Id == index, "Id = n° de l'épisode")
					end
				end
				if t0 and t1 then
					open += 1
					shortest = math.min(shortest, t1 - t0)
					longest = math.max(longest, t1 - t0)
				end
				-- rien au tout début ni à la toute fin de l'épisode (fondus raccordés)
				check(RG.Amount(kind, 0) == 0 and RG.Amount(kind, 1) == 0 and RG.Amount(kind, 0.995) == 0, "bords à 0 " .. kind)
			else
				check(RG.Event(index * E + 300) == nil, "pas d'arc par beau temps")
			end
		end
		local perHour = events / 4001 * 6
		print(string.format("    arcs-en-ciel : %.2f / h ; pot ouvert de %d à %d s", perHour, shortest, longest))
		check(perHour > 2 and perHour < 4, "2 à 4 arcs-en-ciel par heure : " .. perHour)
		check(open == events, "chaque arc-en-ciel ouvre son pot")
		check(shortest >= 100 and longest <= 260, "le pot reste ouvert ~2 à 4 min")
		check(RG.Event(0 / 0) == nil, "valeurs folles")
		local nxt = RG.NextEvent(12345)
		check(nxt ~= nil and nxt.StartAt > 12345 and nxt.StartAt - 12345 < 6 * 3600, "prochain arc-en-ciel")
		check(RG.Hash(5) >= 0 and RG.Hash(5) < 1 and RG.Hash(5) == RG.Hash(5), "hachage stable")
	end)

	test("Arc-en-ciel v11 : places du pot (sur les trottoirs, hors chaussée / parcelles / lieux bâtis)", function(check)
		for _, count in ipairs({ 1, 8, 20, 50 }) do
			local spots = RG.Candidates(count)
			check(#spots >= 80, count .. " parcelles : au moins 80 places (" .. #spots .. ")")
			local kinds = {}
			local R = WL.TownRadius(count)
			local graph = WL.RoadGraph(count)
			for _, s in ipairs(spots) do
				kinds[s.Zone] = true
				check(math.max(math.abs(s.X), math.abs(s.Z)) < R - 20, "dans la ville " .. s.Zone)
				-- sur un trottoir : hors de toute chaussée, à moins d'un trottoir d'une route
				local onWalk, onLane = false, false
				for _, e in ipairs(graph.Edges) do
					local d = WL.EdgeDistance(e, s.X, s.Z)
					if d < e.Width / 2 + 0.5 then onLane = true end
					if not e.Highway and (e.Sidewalk or 0) > 0 and d >= e.Width / 2 and d <= e.Width / 2 + e.Sidewalk then onWalk = true end
				end
				check(onWalk and not onLane, "sur un trottoir, pas sur la chaussée " .. s.Zone .. " " .. math.floor(s.X) .. "," .. math.floor(s.Z))
				check(not WL.OnPlot(count, s.X, s.Z, 0), "pas sur une parcelle " .. s.Zone)
				for _, id in ipairs({ "TownHall", "MusicStage", "Fair", "Gate", "Market", "FoodCorner", "Dealership", "RaceMeet" }) do
					local z = WL.Facility(count, id)
					check(not z or not WL.InZone(z, s.X, s.Z, 0), "pas dans " .. id)
				end
				check(math.sqrt(s.X * s.X + s.Z * s.Z) > WL.PLAZA_R, "pas au milieu de la place")
				check(type(s.Y) == "number" and s.Y == s.Y and math.abs(s.Y) < 20, "hauteur")
			end
			check(kinds.Street and (kinds.Avenue or kinds.Belt) and kinds.Downtown, count .. " parcelles : rues, avenues, centre")
			check(RG.Candidates(count) == spots, "cache")
			-- ordre d'essai : déterministe, distinct, dans la liste
			for id = 1, 200 do
				local order = RG.Order(id, #spots)
				local seen = {}
				check(#order == math.min(#spots, RG.CONFIG.Tries), "nombre d'essais")
				for _, i in ipairs(order) do
					check(i >= 1 and i <= #spots and not seen[i], "indice " .. i)
					seen[i] = true
				end
				check(RG.Order(id, #spots)[1] == order[1], "déterministe")
				check(RG.Side(id) == 1 or RG.Side(id) == -1, "côté")
			end
		end
		check(#RG.Order(3, 0) == 0 and #RG.Order(3, 2) == 2, "petites listes")
		-- les arcs-en-ciel successifs ne tombent pas toujours au même endroit
		local spots = RG.Candidates(8)
		local firsts = {}
		local distinct = 0
		for id = 1, 100 do
			local i = RG.Order(id, #spots)[1]
			if not firsts[i] then firsts[i] = true distinct += 1 end
		end
		check(distinct >= 40, "places variées : " .. distinct .. " / 100")
	end)

	test("Arc-en-ciel v11 : récompense du pot d'or (ordre d'arrivée, plafond, anti-saut)", function(check)
		local stats = { PerSecond = 1000, ClickValue = 100 } -- production 1300/s
		local r1, s1 = RG.Reward(stats, 1, 0)
		local r2 = RG.Reward(stats, 2, 0)
		local r3 = RG.Reward(stats, 3, 0)
		local r4 = RG.Reward(stats, 4, 0)
		eq(check, r1, 1300 * 240, "1er : 240 s de production")
		check(s1 == 240 and r1 > r2 and r2 > r3 and r3 > 0 and r4 == 0, "1er > 2e > 3e > 4e (rien)")
		local capped, _, isCapped = RG.Reward(stats, 1, RG.CONFIG.DailyRewarded)
		check(capped == 0 and isCapped, "plafond quotidien")
		eq(check, (RG.Reward({ PerSecond = 0, ClickValue = 0 }, 2, 0)), RG.CONFIG.MinReward, "minimum")
		check(RG.Reward({ PerSecond = 0 / 0, ClickValue = 1 / 0 }, 1, 0) == RG.CONFIG.MinReward, "valeurs folles")
		check(RG.Reward(nil, 1, nil) == RG.CONFIG.MinReward and RG.Reward(stats, 0 / 0, 0) == 0, "entrées absentes")
		-- atteindre le pot
		check(RG.InReach(3, 1, 4) and not RG.InReach(10, 0, 10) and not RG.InReach(0, 40, 0) and not RG.InReach(0 / 0, 0, 0), "rayon du pot")
		check(not RG.IsJump(9, 0.1) and not RG.IsJump(30, 0.25), "voiture rapide (120 studs/s) : pas un saut")
		check(RG.IsJump(400, 0.25) and RG.IsJump(1 / 0, 1) and RG.IsJump(5000, 2), "téléportation")
		-- données
		local today = RG.Today(86400 * 20000 + 5)
		local d = RG.SanitizeData({ Day = today - 1, Rewarded = 4, Pots = 9.6, Firsts = -3 }, today)
		check(d.Day == today and d.Rewarded == 0 and d.Pots == 9 and d.Firsts == 0 and d.LastId == -1, "nouveau jour, valeurs propres")
		local e = RG.SanitizeData({ Day = today, Rewarded = 99 }, today)
		check(e.Rewarded == RG.CONFIG.DailyRewarded, "compteur borné")
		check(RG.SanitizeData(nil, today).Pots == 0, "vieille sauvegarde")
	end)

	test("Arc-en-ciel v11 : arriver 1er à tous les pots ne casse pas le rythme des parties", function(check)
		local mult = RG.MaxNetMultiplier(2)
		check(mult <= 1.25, "gain net max (2 h de jeu par jour) " .. mult)
		local active = Sim.RunMinutes(Sim.Run("Active", { MaxHours = 40, MaxRebirths = 5 }))
		Config.GamePassesById.__RainbowTest = { Id = "__RainbowTest", Multiplier = mult }
		local ok, result = pcall(Sim.Run, { Name = "Actif + pots d'or", ClicksPerSecond = 6, ClickDuty = 0.75, Passes = { "__RainbowTest" }, AutoClicks = 0 },
			{ MaxHours = 40, MaxRebirths = 5 })
		Config.GamePassesById.__RainbowTest = nil
		check(ok, tostring(result))
		if not ok then return end
		local runs = Sim.RunMinutes(result)
		local parts = {}
		for n = 1, 5 do table.insert(parts, "R" .. n .. "=" .. (runs[n] and tostring(math.floor(runs[n] + 0.5)) or "-")) end
		print("    pots d'or (x" .. string.format("%.3f", mult) .. " net), parties (min) : " .. table.concat(parts, " "))
		for n = 1, 5 do
			check(runs[n] ~= nil and active[n] ~= nil and runs[n] >= active[n] * 0.75, "R" .. n .. " : partie trop courte avec les pots d'or")
		end
		check(runs[5] ~= nil and runs[1] ~= nil and runs[5] >= runs[1] * 1.3, "la courbe reste croissante")
	end)
end
"""


def rainbow_test(read, shared):
    """Code Luau des tests REALISM11 (chargeurs WorldLayout + RainbowGold + tests)."""
    parts = []
    for name in ("WorldLayout", "RainbowGold"):
        body = read(os.path.join(shared, name + ".luau"))
        parts.append('loaders["%s"] = function()\nlocal require = req\nlocal warn = function(...) print("WARN", ...) end\n%s\nend\n' % (name, body))
    return "\n".join(parts) + RAINBOW_TESTS
