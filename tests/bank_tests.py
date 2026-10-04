"""
Tests BANK11 (v11) : 💎 Diamants, Banque Dopamine, casses (Shared/Diamonds,
Shared/HeistRules, Shared/BankLayout, Config.Bank).

Branché dans tests/run_tests.py (main) : bank_test() renvoie le code Luau
(chargeurs WorldLayout + Diamonds + HeistRules + BankLayout, puis les tests).
Vérifie :
  - Config.Bank (plafonds, change, casses, boutique de luxe cohérente) ;
  - données propres (valeurs folles, objets inconnus, jour suivant, même table) ;
  - plafond du jour des 💎 (sources hors plafond : Ocean, Interest), solde max ;
  - intérêts du coffre, change 💎 -> Dopamine (secondes de production) ;
  - règles des casses (part du butin, bonus d'équipe, plafond du jour, codes
    de piratage, vitesse plausible) ;
  - la banque dans le terrain réservé par CITY11, planques libres et loin ;
  - le RYTHME des parties : réussir tous ses casses payés + changer le
    maximum de 💎 chaque jour ne raccourcit pas les parties de plus de 25 %.
"""

import os

BANK_TESTS = r"""
-- (BANK11) petits Vector3 / CFrame (rotation autour de Y seulement) pour
-- WorldLayout.CityCFrame / BankLayout, si le banc de test n'en a pas
if Vector3 == nil then
	local V = {}
	V.__index = function(v, k)
		if k == "Magnitude" then
			return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		end
		return nil
	end
	local function new(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
	end
	V.__add = function(a, b) return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	V.__sub = function(a, b) return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	V.__mul = function(a, b)
		if type(a) == "number" then return new(a * b.X, a * b.Y, a * b.Z) end
		if type(b) == "number" then return new(a.X * b, a.Y * b, a.Z * b) end
		return new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	Vector3 = { new = new }
	local C = {}
	local function rot(cf, x, y, z)
		return new(x * cf.c + z * cf.s, y, -x * cf.s + z * cf.c)
	end
	C.__index = function(cf, k)
		if k == "Position" then return new(cf.x, cf.y, cf.z) end
		if k == "LookVector" then return rot(cf, 0, 0, -1) end
		if k == "PointToObjectSpace" then
			return function(self, p)
				local dx, dy, dz = p.X - self.x, p.Y - self.y, p.Z - self.z
				return new(dx * self.c - dz * self.s, dy, dx * self.s + dz * self.c)
			end
		end
		return nil
	end
	local function cfnew(x, y, z, c, s)
		return setmetatable({ x = x, y = y, z = z, c = c or 1, s = s or 0 }, C)
	end
	C.__mul = function(a, b)
		if getmetatable(b) == C then
			local p = rot(a, b.x, b.y, b.z)
			-- (rotations autour de Y : les angles s'ajoutent)
			return cfnew(a.x + p.X, a.y + p.Y, a.z + p.Z, a.c * b.c - a.s * b.s, a.s * b.c + a.c * b.s)
		end
		local p = rot(a, b.X, b.Y, b.Z)
		return new(a.x + p.X, a.y + p.Y, a.z + p.Z)
	end
	CFrame = {
		new = function(x, y, z)
			if type(x) == "table" then return cfnew(x.X, x.Y, x.Z) end
			return cfnew(x or 0, y or 0, z or 0)
		end,
		Angles = function(rx, ry, rz)
			assert((rx or 0) == 0 and (rz or 0) == 0, "test : rotation Y seulement")
			return cfnew(0, 0, 0, math.cos(ry or 0), math.sin(ry or 0))
		end,
	}
end
do
	script.Parent.WorldLayout = "WorldLayout"
	script.Parent.Diamonds = "Diamonds"
	script.Parent.HeistRules = "HeistRules"
	script.Parent.BankLayout = "BankLayout"
	local D = req("Diamonds")
	local HR = req("HeistRules")
	local BL = req("BankLayout")
	local WL = req("WorldLayout")
	local Sim = req("EconomySim")

	test("Banque v11 : Config.Bank (plafonds, change, casses, boutique de luxe)", function(check)
		local B = Config.Bank
		check(type(B) == "table", "Config.Bank")
		check(B.Diamonds.DailyCap > 0 and B.Diamonds.DailyCap <= 200, "plafond du jour raisonnable")
		check(B.Vault.InterestRate > 0 and B.Vault.InterestRate <= 0.05 and B.Vault.InterestMax <= 20, "intérêts modestes")
		check(B.Exchange.SecondsPerDiamond > 0 and B.Exchange.SecondsPerDiamond <= 60 and B.Exchange.DailyMax <= 30, "change borné")
		check(B.Heist.MaxCrew >= 2 and B.Heist.MaxCrew <= 4, "équipe de 2 à 4")
		for _, kind in ipairs({ "Bank", "Train" }) do
			local k = B.Heist.Kinds[kind]
			check(k and k.Seconds > 0 and k.Seconds <= 180 and k.Daily >= 1 and k.Daily <= 6, kind .. " : récompense / jour")
			check(k.Diamonds[1] >= 1 and k.Diamonds[2] >= k.Diamonds[1], kind .. " : 💎 min / max")
			check(k.Cooldown >= 120 and k.FailCooldown >= 60 and k.Duration >= 120, kind .. " : temps")
		end
		local slots = {}
		for _, s in ipairs(D.SLOTS) do slots[s] = true end
		local ids, kinds = {}, { Wear = 0, Title = 0, Paint = 0 }
		for i, item in ipairs(B.Luxury) do
			check(type(item.Id) == "string" and not ids[item.Id], "id unique " .. tostring(item.Id))
			ids[item.Id] = true
			check(Config.BankLuxuryById[item.Id] == item and item.Order == i, "index " .. item.Id)
			check(kinds[item.Kind] ~= nil, "genre connu " .. item.Id)
			kinds[item.Kind] = (kinds[item.Kind] or 0) + 1
			check(type(item.Price) == "number" and item.Price >= 10 and item.Price == math.floor(item.Price), "prix entier " .. item.Id)
			check(type(item.Name) == "string" and type(item.Icon) == "string" and type(item.Desc) == "string", "textes " .. item.Id)
			if item.Kind == "Wear" or item.Kind == "Title" then
				check(slots[item.Slot] == true and slots[item.Slot] ~= nil, "emplacement " .. item.Id)
			end
			if item.Kind == "Title" then
				check(type(item.Title) == "string" and #item.Title > 0, "texte du titre " .. item.Id)
			end
			if item.Kind == "Paint" then
				check(type(item.Color) == "table" and item.Color.R ~= nil, "couleur " .. item.Id)
			end
		end
		check(kinds.Wear >= 8 and kinds.Title >= 3 and kinds.Paint >= 3, "boutique variée")
		-- objectif à long terme : la boutique complète vaut des semaines de casses
		check(D.CatalogueTotal() >= HR.MaxDiamondsPerDay() * 15, "boutique = au moins 15 jours de 💎 " .. D.CatalogueTotal())
	end)

	test("Banque v11 : données propres (valeurs folles, objets inconnus, jour suivant, même table)", function(check)
		local d = D.Sanitize(nil, 100)
		check(d.Wallet == 0 and d.Vault == 0 and d.Day == 100 and #d.History == 0 and next(d.Owned) == nil, "neuf")
		local raw = { Wallet = 0 / 0, Vault = -5, Earned = math.huge, Day = 99, DayEarned = 70, Exchanged = 9, InterestDay = 99,
			Owned = { DiamondCrown = true, Nope = true, GoldChain = "yes" }, Equipped = { Head = "DiamondCrown", Neck = "GoldChain", Back = "Nope", Face = "DiamondCrown" },
			History = { { T = 5, K = "Bank", A = 12, N = "" }, { K = 5 }, "x" } }
		local same = raw
		local c = D.Sanitize(raw, 100)
		check(c == same, "même table (références des services valides)")
		check(c.Wallet == 0 and c.Vault == 0 and c.Earned == 0, "valeurs folles -> 0")
		check(c.DayEarned == 0 and c.Exchanged == 0 and c.Day == 100, "nouveau jour : compteurs remis")
		check(c.Owned.DiamondCrown == true and c.Owned.Nope == nil and c.Owned.GoldChain == nil, "objets inconnus / invalides retirés")
		check(c.Equipped.Head == "DiamondCrown" and c.Equipped.Neck == nil and c.Equipped.Back == nil and c.Equipped.Face == nil, "porté seulement si possédé et bon emplacement")
		check(#c.History == 1 and c.History[1].A == 12, "historique propre")
		local big = { Wallet = 5e9 }
		check(D.Sanitize(big, 1).Wallet == Config.Bank.Diamonds.MaxBalance, "solde plafonné")
		local h = D.SanitizeHeist({ Day = 3, Bank = 2, Train = 9, Done = 4.7, Success = -1, Best = 80 }, 4)
		check(h.Bank == 0 and h.Train == 0 and h.Done == 4 and h.Success == 0 and h.Best == 80, "casses : nouveau jour")
		for _ = 1, 50 do D.Log(c, 1, "Deposit", 1, "") end
		eq(check, #c.History, Config.Bank.Diamonds.HistorySize, "historique borné")
		check(D.Amount(3) == 3 and D.Amount(2.5) == nil and D.Amount(0) == nil and D.Amount(-1) == nil and D.Amount(0 / 0) == nil and D.Amount(math.huge) == nil and D.Amount("5") == nil, "montants valides")
		check(D.Amount(10, 5) == nil, "montant au-dessus du max")
	end)

	test("Banque v11 : plafond des 💎, intérêts, change en secondes de production, boutique", function(check)
		local d = D.Sanitize(nil, 1)
		local cap = Config.Bank.Diamonds.DailyCap
		eq(check, D.Grantable(d, 500, true), cap, "plafond du jour")
		eq(check, D.Grantable(d, 500, false), 500, "hors plafond (océan, intérêts)")
		d.DayEarned = cap - 3
		eq(check, D.Grantable(d, 10, true), 3, "reste du jour")
		d.Wallet = Config.Bank.Diamonds.MaxBalance - 2
		eq(check, D.Grantable(d, 10, false), 2, "solde max")
		check(D.Grantable(d, 0 / 0, false) == 0 and D.Grantable(d, -4, false) == 0, "valeurs folles")
		-- intérêts
		eq(check, D.Interest(9), 0, "trop peu au coffre")
		eq(check, D.Interest(10), 1, "au moins 1 💎")
		eq(check, D.Interest(100), 2, "2 %")
		eq(check, D.Interest(1e6), Config.Bank.Vault.InterestMax, "plafond des intérêts")
		local v = D.Sanitize({ Vault = 100, InterestDay = 0 }, 7)
		eq(check, D.InterestDue(v, 7), 2, "intérêts dus")
		v.InterestDay = 7
		eq(check, D.InterestDue(v, 7), 0, "une fois par jour")
		eq(check, D.InterestDue(v, 8), 2, "le lendemain")
		-- change : secondes de production (plancher 500)
		local stats = { PerSecond = 1000, ClickValue = 100 }
		local prod = 1000 + 100 * Config.Rewards.EstimatedClicksPerSecond
		eq(check, D.ExchangeValue(stats, 3), math.floor(prod * Config.Bank.Exchange.SecondsPerDiamond) * 3, "3 💎")
		eq(check, D.ExchangeValue({ PerSecond = 0 }, 2), Config.Bank.Exchange.MinPerDiamond * 2, "plancher en début de partie")
		eq(check, D.ExchangeValue({ PerSecond = 0 / 0 }, 1), Config.Bank.Exchange.MinPerDiamond, "stats folles")
		local e = D.Sanitize({ Exchanged = 10, Day = 1 }, 1)
		eq(check, D.ExchangeLeft(e), Config.Bank.Exchange.DailyMax - 10, "reste à changer")
		-- boutique
		local w = D.Sanitize({ Wallet = 100 }, 1)
		local crown = Config.BankLuxuryById.DiamondCrown
		local chain = Config.BankLuxuryById.GoldChain
		local mm = Config.BankLuxuryById.TitleMastermind
		check(not D.CanBuy(w, { Success = 0 }, crown), "trop cher")
		check(D.CanBuy(w, { Success = 0 }, chain), "assez de 💎")
		check(not D.CanBuy(w, { Success = 0 }, mm) and D.CanBuy(w, { Success = 3 }, mm), "titre après 3 casses réussis")
		w.Owned.GoldChain = true
		local okOwned, why = D.CanBuy(w, { Success = 0 }, chain)
		check(not okOwned and why == "Already owned", "déjà possédé")
	end)

	test("Banque v11 : règles des casses (part du butin, équipe, plafond, codes, vitesse)", function(check)
		eq(check, HR.Fill(3, 1, 8), 1, "seul, sac plein")
		eq(check, HR.Fill(4, 2, 8), 4 / 6, "à deux")
		eq(check, HR.Fill(8, 4, 8), 1, "à quatre : toutes les piles")
		eq(check, HR.Fill(0 / 0, 1, 8), 0, "valeur folle")
		check(HR.CrewFactor(1) == 1 and HR.CrewFactor(4) == 1 + Config.Bank.Heist.MaxCrewBonus and HR.CrewFactor(99) == 1 + Config.Bank.Heist.MaxCrewBonus, "bonus d'équipe borné")
		local stats = { PerSecond = 1e6, ClickValue = 0 }
		local d1, g1 = HR.Reward("Bank", stats, 1, 1, 0)
		local d2, g2 = HR.Reward("Bank", stats, 0.5, 1, 0)
		local d4, g4 = HR.Reward("Bank", stats, 1, 4, 0)
		eq(check, d1, math.floor(1e6 * Config.Bank.Heist.Kinds.Bank.Seconds), "Dopamine = secondes de production")
		check(d2 < d1 and g2 < g1 and d4 > d1 and g4 == g1, "part du butin / bonus d'équipe")
		eq(check, g1, Config.Bank.Heist.Kinds.Bank.Diamonds[2], "💎 max sac plein")
		local d0, g0 = HR.Reward("Bank", stats, 0.1, 1, 0)
		check(d0 == 0 and g0 == 0, "trop peu de butin : rien")
		local dc, gc, capped = HR.Reward("Bank", stats, 1, 1, Config.Bank.Heist.Kinds.Bank.Daily)
		check(dc == 0 and gc == 0 and capped, "plafond du jour")
		check(HR.Reward("Nope", stats, 1, 1, 0) == 0, "genre inconnu")
		local dt, gt = HR.Reward("Train", { PerSecond = 0 }, 1, 1, 0)
		check(dt == 500 and gt == Config.Bank.Heist.Kinds.Train.Diamonds[2], "début de partie : plancher")
		check(HR.MaxDiamondsPerDay() <= Config.Bank.Diamonds.DailyCap, "💎 / jour ≤ plafond")
		-- codes de piratage
		local seed = 7
		local function rand(a, b)
			seed = (seed * 1103515245 + 12345) % 2147483648
			return a + seed % (b - a + 1)
		end
		for _ = 1, 200 do
			local code = HR.HackCode(rand, 5)
			check(#code == 5, "5 symboles")
			for i, s in ipairs(code) do
				check(s >= 1 and s <= #HR.SYMBOLS and s == math.floor(s), "symbole valide")
				if i >= 3 then check(not (code[i] == code[i - 1] and code[i] == code[i - 2]), "jamais 3 fois le même") end
			end
			check(HR.CheckCode(code, table.clone(code)), "bonne réponse")
		end
		check(not HR.CheckCode({ 1, 2, 3 }, { 1, 2 }) and not HR.CheckCode({ 1, 2, 3 }, "123") and not HR.CheckCode({ 1, 2, 3 }, { 1, 2, 4 }), "mauvaises réponses")
		check(HR.SpeedOk(20, 0.25) and HR.SpeedOk(30, 0.25) and not HR.SpeedOk(300, 0.25) and not HR.SpeedOk(0 / 0, 0.25), "vitesse plausible (voiture OK, téléportation non)")
		eq(check, HR.Clock(75.2), "1:16", "chrono")
	end)

	test("Banque v11 : dans le terrain réservé (CITY11), planques libres et loin (1..50 parcelles)", function(check)
		for _, count in ipairs({ 1, 8, 20, 50 }) do
			local o = WL.Origin()
			local cf = BL.CFrame(count)
			local c = cf.Position - o
			check(math.abs(c.X - 120) < 1e-6 and math.abs(c.Z - 540) < 1e-6, count .. " : centre (120, 540)")
			check(cf.LookVector.Z < -0.99, count .. " : façade vers la rue du marché (-Z)")
			-- emprise : x 84..156, z 502..568
			for _, p in ipairs({ { -BL.ALLEY, -BL.STEPS_END - 2 }, { BL.ALLEY, BL.BACK + 2 } }) do
				local w = cf * Vector3.new(p[1], 0, p[2]) - o
				check(w.X >= 84 - 1e-6 and w.X <= 156 + 1e-6 and w.Z >= 502 - 1e-6 and w.Z <= 568 + 1e-6, count .. " : coin dans le terrain " .. w.X .. "," .. w.Z)
			end
			local pts = BL.Points(count)
			check(#pts.Counters == 4 and #pts.ATMs == 4 and #pts.Piles == 8, count .. " : points")
			for _, p in ipairs({ pts.Lobby, pts.Hack, pts.Drill, pts.Luxury, pts.Deposit }) do
				check(BL.Inside(count, p, 0), count .. " : point dans la banque")
			end
			local drops = BL.Drops(count)
			check(#drops >= 2, count .. " : au moins 2 planques " .. #drops)
			for _, d in ipairs(drops) do
				local x, z = d.X - o.X, d.Z - o.Z
				check(WL.IsFreeAt(count, x, z, 7), count .. " : planque libre " .. x .. "," .. z)
				check(math.sqrt((x - 120) ^ 2 + (z - 540) ^ 2) >= 150, count .. " : planque assez loin")
				check(not BL.Inside(count, d, 20), count .. " : planque hors de la banque")
			end
		end
	end)

	test("Banque v11 : réussir tous ses casses + changer le max de 💎 ne casse pas le rythme des parties", function(check)
		local mult = HR.MaxNetMultiplier(2)
		check(mult <= 1.25, "gain net max (2 h de jeu par jour) " .. mult)
		local active = Sim.RunMinutes(Sim.Run("Active", { MaxHours = 40, MaxRebirths = 5 }))
		Config.GamePassesById.__BankTest = { Id = "__BankTest", Multiplier = mult }
		local ok, result = pcall(Sim.Run, { Name = "Actif + casses", ClicksPerSecond = 6, ClickDuty = 0.75, Passes = { "__BankTest" }, AutoClicks = 0 },
			{ MaxHours = 40, MaxRebirths = 5 })
		Config.GamePassesById.__BankTest = nil
		check(ok, tostring(result))
		if not ok then return end
		local runs = Sim.RunMinutes(result)
		local parts = {}
		for n = 1, 5 do table.insert(parts, "R" .. n .. "=" .. (runs[n] and tostring(math.floor(runs[n] + 0.5)) or "-")) end
		print("    casses + change (x" .. string.format("%.3f", mult) .. " net), parties (min) : " .. table.concat(parts, " "))
		for n = 1, 5 do
			check(runs[n] ~= nil and active[n] ~= nil and runs[n] >= active[n] * 0.75, "R" .. n .. " : partie trop courte avec les casses")
		end
		check(runs[5] ~= nil and runs[1] ~= nil and runs[5] >= runs[1] * 1.3, "la courbe reste croissante")
	end)
end
"""


def bank_test(read, shared):
    """Code Luau des tests BANK11 (chargeurs WorldLayout + Diamonds + HeistRules + BankLayout + tests)."""
    parts = []
    for name in ("WorldLayout", "Diamonds", "HeistRules", "BankLayout"):
        body = read(os.path.join(shared, name + ".luau"))
        parts.append('loaders["%s"] = function()\nlocal require = req\nlocal warn = function(...) print("WARN", ...) end\n%s\nend\n' % (name, body))
    return "\n".join(parts) + BANK_TESTS
