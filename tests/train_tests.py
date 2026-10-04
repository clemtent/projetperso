"""Tests TRAIN11 (v11) : la ligne de ceinture (Shared/TrainLine, sur WorldLayout).

Tracé pour 1..50 parcelles (jamais sur une route hors des 4 passages à niveau,
gares et planques hors routes / parcelles, banque et centre-ville libres),
horaire (continu, 2 trains jamais proches, long arrêt du convoi de diamants
toutes les 20 min, tour à tour dans les 4 gares), passages à niveau fermés
avant le train, sièges et quai aux cibles SCALE11. Appelé par run_tests.py.
"""
import os

TRAIN_TESTS = r"""
do
	local TL = req("TrainLine")
	local WL = req("WorldLayout")
	local function roadGap(count, x, z)
		local best = math.huge
		for _, e in ipairs(WL.RoadGraph(count).Edges) do
			local pts = e.Points
			for i = 2, #pts do
				local a, b = pts[i - 1], pts[i]
				local dx, dz = b.X - a.X, b.Z - a.Z
				local l2 = dx * dx + dz * dz
				local u = if l2 > 0 then math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / l2, 0, 1) else 0
				local d = math.sqrt((a.X + dx * u - x) ^ 2 + (a.Z + dz * u - z) ^ 2) - e.Width / 2 - (e.Sidewalk or 0)
				if d < best then best = d end
			end
		end
		return best
	end

	test("Train v11 : la voie, les gares et les planques ne touchent ni route ni parcelle (1..50 parcelles)", function(check)
		for _, count in ipairs({ 1, 4, 8, 12, 20, 30, 40, 50 }) do
			local L = TL.Length(count)
			local crossings = TL.Crossings(count)
			check(#crossings == 4, count .. " : 4 passages à niveau")
			local minGap = math.huge
			local s = 0
			while s < L do
				local x, z = TL.PointAt(count, s)
				local near = false
				for _, c in ipairs(crossings) do
					if (x - c.X) ^ 2 + (z - c.Z) ^ 2 < 30 * 30 then near = true end
				end
				if not near then minGap = math.min(minGap, roadGap(count, x, z)) end
				s += 6
			end
			check(minGap >= TL.CAR_W / 2 + 3, count .. " : voie trop près d'une route " .. minGap)
			for _, st in ipairs(TL.Stations(count)) do
				local r = st.Rect
				for _, p in ipairs({ { r.X, r.Z }, { r.X - r.W / 2 + 1, r.Z - r.D / 2 + 1 }, { r.X + r.W / 2 - 1, r.Z + r.D / 2 - 1 },
					{ r.X - r.W / 2 + 1, r.Z + r.D / 2 - 1 }, { r.X + r.W / 2 - 1, r.Z - r.D / 2 + 1 } }) do
					check(not WL.OnRoad(count, p[1], p[2], 0) and not WL.OnPlot(count, p[1], p[2], 0), count .. " : gare " .. st.Id .. " sur une route / parcelle")
				end
				check(TL.Near(count, st.Building.X, st.Building.Z, 0), count .. " : le bâtiment de la gare est dans l'emprise")
			end
			for _, h in ipairs(TL.Hideouts(count)) do
				check(WL.IsFreeAt(count, h.X, h.Z, 18), count .. " : planque " .. h.Index .. " pas libre")
			end
			check(not TL.Near(count, 120, 540, 40), count .. " : la banque (BANK11) reste libre")
			check(not TL.Near(count, 0, 0, 200), count .. " : le centre-ville reste libre")
		end
	end)

	test("Train v11 : horaire continu, 2 trains jamais proches, convoi de diamants toutes les 20 min", function(check)
		for _, count in ipairs({ 8, 50 }) do
			local L = TL.Length(count)
			local _, l1 = TL.Consist(1)
			local _, l2 = TL.Consist(2)
			local t0 = 1.75e9
			local prev = nil
			local maxJump, minGap = 0, math.huge
			for t = t0, t0 + 2 * TL.CYCLE, 0.5 do
				local a, b = TL.State(count, t, 1), TL.State(count, t, 2)
				if prev then maxJump = math.max(maxJump, (a.S - prev) % L) end
				prev = a.S
				minGap = math.min(minGap, (b.S - l2 - a.S) % L, (a.S - l1 - b.S) % L)
				check(a.V <= TL.SPEED + 1e-6, "vitesse bornée")
			end
			check(maxJump <= TL.SPEED * 0.5 + 0.5, count .. " : saut de position " .. maxJump)
			check(minGap > 1000, count .. " : trains trop proches " .. minGap)
			local seen = {}
			for c = 10, 13 do
				local st = TL.State(count, c * TL.CYCLE + 5, 1)
				check(st.Phase == "Hold" and st.Heist, count .. " : long arrêt au début du cycle " .. c)
				seen[st.Station] = true
				local h = TL.Heist(count, c * TL.CYCLE - 30)
				check(h.Start == c * TL.CYCLE and h.Station == st.Station and not h.Active, "annonce du convoi")
				-- arrêt suivant : NextStop d'accord avec l'état
				local a, d = TL.NextStop(count, c * TL.CYCLE + 5, 1, st.Station)
				check(a <= c * TL.CYCLE + 5 and math.abs(d - st.DepartAt) < 1e-6, "NextStop en gare")
			end
			local n = 0
			for _ in pairs(seen) do n += 1 end
			check(n == 4, count .. " : le convoi passe tour à tour par les 4 gares")
			local plan = TL.Plan(count, 1)
			check(plan.Dwell >= TL.DWELL_MIN and plan.Dwell <= 60, count .. " : arrêts en gare " .. plan.Dwell)
		end
	end)

	test("Train v11 : passages à niveau fermés avant le train, rouverts après ; sièges SCALE11", function(check)
		local count = 8
		local L = TL.Length(count)
		local t0 = 1.75e9
		for i, c in ipairs(TL.Crossings(count)) do
			for t = t0, t0 + TL.CYCLE, 0.5 do
				for ti = 1, 2 do
					local st = TL.State(count, t, ti)
					local _, len = TL.Consist(ti)
					local ahead = (c.S - st.S) % L
					local passed = (st.S - c.S) % L
					local on, k = TL.CrossingState(count, i, t)
					if ahead < 300 or passed <= len then
						check(on and k > 0.99, "passage " .. i .. " fermé quand un train arrive / passe")
					end
				end
			end
		end
		for _, s in ipairs(TL.SeatsLocal("Coach")) do
			check(math.abs(s.Y - TL.FLOOR_L - 1.85) < 1e-6, "dessus du coussin à 1,85 du plancher")
		end
		check(math.abs(TL.PLATFORM_Y - TL.FLOOR_Y) < 1e-6, "quai de plain-pied avec le plancher")
		check(TL.PLATFORM_OUT + TL.CAR_W / 2 + 0.4 <= TL.OFF_OUT, "lacune quai / voiture")
	end)
end
"""


def train_test(read, shared):
    parts = []
    for name in ("WorldLayout", "TrainLine"):
        body = read(os.path.join(shared, name + ".luau"))
        parts.append('loaders["%s"] = function()\nlocal require = req\nlocal game = { GetService = function() return { Shared = { WorldLayout = "WorldLayout" } } end }\nlocal warn = function(...) print("WARN", ...) end\n%s\nend\n' % (name, body))
    return "\n".join(parts) + TRAIN_TESTS
