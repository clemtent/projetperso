--[[
	RaceRules (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > RaceRules

	🏁 Règles PURES des courses de rue (v10, RACE10) : aucune Instance,
	aucun service, seulement Config. Partagé par le serveur (RaceService),
	le client (RaceClient) et les tests (tests/run_tests.py).
	  - lignes brisées en nombres (X / Z / S cumulée) : point à une
	    distance, projection d'une position, rééchantillonnage, virages
	    arrondis (congés) ;
	  - profil de vitesse de la trajectoire (virages -> vitesse max,
	    freinage anticipé) et pas de simulation d'un pilote IA, élastique
	    "juste" (léger, jamais au-delà de la vitesse de pointe, coupé dans le
	    final) ;
	  - classement, récompenses (secondes de production selon la place,
	    adversaires humains, plafond quotidien), données sauvegardées ;
	  - contrôles anti-triche (vitesse plausible, saut, temps minimal d'un
	    tronçon).

	Ligne : { X = { number }, Z = { number }, Y = { number }?, S = { number },
	          N = number, Total = number, Closed = boolean }
	  S[i] = distance cumulée au point i ; boucle (Closed) : le segment N -> 1
	  compte dans Total.
]]

local Config = require(script.Parent.Config)

local RaceRules = {}

export type Line = {
	X: { number },
	Z: { number },
	Y: { number }?,
	S: { number },
	N: number,
	Total: number,
	Closed: boolean,
}

local function finite(value: any, default: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return default
end
RaceRules.Finite = finite

local function cfg(): any
	return Config.Race or {}
end

----------------------------------------------------------------------
-- Lignes brisées
----------------------------------------------------------------------

-- points = { { x, z, y? } } (tableaux) -> Ligne. Les points en double sont retirés.
function RaceRules.Line(points: { { number } }, closed: boolean?): Line
	local X, Z, Y, S = {}, {}, {}, {}
	local total = 0
	for _, p in ipairs(points) do
		local x, z = finite(p[1], 0), finite(p[2], 0)
		local n = #X
		if n == 0 or (x - X[n]) ^ 2 + (z - Z[n]) ^ 2 > 1e-6 then
			if n > 0 then
				total += math.sqrt((x - X[n]) ^ 2 + (z - Z[n]) ^ 2)
			end
			table.insert(X, x)
			table.insert(Z, z)
			table.insert(Y, finite(p[3], 0))
			table.insert(S, total)
		end
	end
	local n = #X
	local isClosed = closed == true and n >= 3
	if isClosed and (X[1] - X[n]) ^ 2 + (Z[1] - Z[n]) ^ 2 < 1e-6 then
		-- dernier point = premier : retiré (la boucle se ferme toute seule)
		table.remove(X)
		table.remove(Z)
		table.remove(Y)
		table.remove(S)
		n -= 1
	end
	if isClosed then
		total = S[n] + math.sqrt((X[1] - X[n]) ^ 2 + (Z[1] - Z[n]) ^ 2)
	else
		total = S[n] or 0
	end
	return { X = X, Z = Z, Y = Y, S = S, N = n, Total = total, Closed = isClosed }
end

-- Distance ramenée dans la ligne (boucle : modulo ; sinon bornée)
function RaceRules.Wrap(line: Line, s: number): number
	if line.Total <= 0 then
		return 0
	end
	if line.Closed then
		return s % line.Total
	end
	return math.clamp(s, 0, line.Total)
end

-- Index i du segment [i, i+1] qui contient s (déjà ramené)
local function segmentAt(line: Line, s: number): number
	local S = line.S
	local lo, hi = 1, line.N
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if S[mid] <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	if not line.Closed and lo >= line.N then
		lo = math.max(1, line.N - 1)
	end
	return lo
end

local function nextIndex(line: Line, i: number): number
	if i >= line.N then
		return if line.Closed then 1 else line.N
	end
	return i + 1
end

local function segEnd(line: Line, i: number): number
	if i >= line.N then
		return line.Total
	end
	return line.S[i + 1]
end

-- Point à la distance s : x, z, tangente (tx, tz unitaire), y
function RaceRules.PointAt(line: Line, s: number): (number, number, number, number, number)
	local n = line.N
	if n == 0 then
		return 0, 0, 0, -1, 0
	end
	if n == 1 then
		return line.X[1], line.Z[1], 0, -1, (line.Y and line.Y[1]) or 0
	end
	local w = RaceRules.Wrap(line, s)
	local i = segmentAt(line, w)
	local j = nextIndex(line, i)
	local s0, s1 = line.S[i], segEnd(line, i)
	local len = math.max(1e-6, s1 - s0)
	local t = math.clamp((w - s0) / len, 0, 1)
	local dx, dz = line.X[j] - line.X[i], line.Z[j] - line.Z[i]
	local d = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
	local Y = line.Y
	local y = if Y then Y[i] + (Y[j] - Y[i]) * t else 0
	return line.X[i] + dx * t, line.Z[i] + dz * t, dx / d, dz / d, y
end

-- Projection de (x, z) sur la ligne. hint (distance attendue) + window :
-- on ne cherche que dans [hint - window, hint + window] (boucle : modulo).
-- -> s, décalage latéral (positif = à DROITE du sens de la course), distance
function RaceRules.Project(line: Line, x: number, z: number, hint: number?, window: number?): (number, number, number)
	local n = line.N
	if n < 2 then
		return 0, 0, if n == 1 then math.sqrt((x - line.X[1]) ^ 2 + (z - line.Z[1]) ^ 2) else 0
	end
	local segCount = if line.Closed then n else n - 1
	local first, count = 1, segCount
	if hint ~= nil and window ~= nil and window * 2 < line.Total then
		local from = RaceRules.Wrap(line, hint - window)
		if not line.Closed then
			from = math.max(0, hint - window)
		end
		first = segmentAt(line, from)
		-- nombre de segments couverts par la fenêtre (au moins 2)
		local k, covered, i = 0, 0, first
		while covered < window * 2 + (segEnd(line, first) - line.S[first]) and k < segCount do
			covered += segEnd(line, i) - line.S[i]
			k += 1
			i = if i >= segCount then 1 else i + 1
			if not line.Closed and i == 1 then
				break
			end
		end
		count = math.max(2, k)
	end
	local bestD2, bestS, bestLat = math.huge, 0, 0
	local i = first
	for _ = 1, count do
		local j = nextIndex(line, i)
		local ax, az = line.X[i], line.Z[i]
		local dx, dz = line.X[j] - ax, line.Z[j] - az
		local len2 = dx * dx + dz * dz
		local t = if len2 > 1e-9 then math.clamp(((x - ax) * dx + (z - az) * dz) / len2, 0, 1) else 0
		local qx, qz = ax + dx * t, az + dz * t
		local d2 = (x - qx) ^ 2 + (z - qz) ^ 2
		if d2 < bestD2 then
			bestD2 = d2
			local len = math.sqrt(math.max(len2, 1e-12))
			bestS = line.S[i] + t * len
			-- droite = (-tz, tx)
			bestLat = ((x - qx) * (-dz) + (z - qz) * dx) / len
		end
		i = if i >= segCount then 1 else i + 1
		if not line.Closed and i > segCount then
			break
		end
	end
	return bestS, bestLat, math.sqrt(bestD2)
end

-- Rééchantillonne à pas constant (~step studs), y compris le segment de fermeture
function RaceRules.Resample(line: Line, step: number): Line
	local total = line.Total
	if total <= 0 or line.N < 2 then
		return line
	end
	local count = math.max(2, math.floor(total / math.max(0.5, step) + 0.5))
	local pts = {}
	local last = if line.Closed then count - 1 else count
	for k = 0, last do
		local s = total * k / count
		local x, z, _, _, y = RaceRules.PointAt(line, s)
		table.insert(pts, { x, z, y })
	end
	return RaceRules.Line(pts, line.Closed)
end

-- Virages arrondis : chaque angle devient un arc de rayon `radius` (réduit si
-- les segments voisins sont trop courts). points = { { x, z, y? } }
function RaceRules.Fillet(points: { { number } }, closed: boolean, radius: number, arcStep: number?): { { number } }
	local n = #points
	if n < 3 then
		return points
	end
	local stepLen = arcStep or 4
	local out = {}
	local function at(i: number): { number }
		if closed then
			return points[((i - 1) % n) + 1]
		end
		return points[math.clamp(i, 1, n)]
	end
	for i = 1, n do
		local p = at(i)
		if not closed and (i == 1 or i == n) then
			table.insert(out, p)
			continue
		end
		local a, c = at(i - 1), at(i + 1)
		local ux, uz = p[1] - a[1], p[2] - a[2]
		local vx, vz = c[1] - p[1], c[2] - p[2]
		local lu, lv = math.sqrt(ux * ux + uz * uz), math.sqrt(vx * vx + vz * vz)
		if lu < 1e-6 or lv < 1e-6 then
			table.insert(out, p)
			continue
		end
		ux, uz, vx, vz = ux / lu, uz / lu, vx / lv, vz / lv
		local cosT = math.clamp(ux * vx + uz * vz, -1, 1)
		local theta = math.acos(cosT) -- angle de braquage (0 = tout droit)
		if theta < math.rad(4) then
			table.insert(out, p)
			continue
		end
		-- longueur des tangentes : r tan(θ/2), au plus 45 % des segments voisins
		local r = radius
		local tanHalf = math.tan(theta / 2)
		local t = r * tanHalf
		local limit = 0.45 * math.min(lu, lv)
		if t > limit then
			t = limit
			r = t / math.max(tanHalf, 1e-6)
		end
		local p0x, p0z = p[1] - ux * t, p[2] - uz * t
		local py = p[3] or 0
		local cross = ux * vz - uz * vx -- signe du virage
		-- centre de l'arc : perpendiculaire à u, côté intérieur
		local nx, nz = -uz, ux
		if cross < 0 then
			nx, nz = uz, -ux
		end
		local cx, cz = p0x + nx * r, p0z + nz * r
		local a0 = math.atan2(p0z - cz, p0x - cx)
		local sweep = if cross >= 0 then theta else -theta
		local steps = math.max(2, math.ceil(math.abs(sweep) * r / stepLen))
		for k = 0, steps do
			local ang = a0 + sweep * k / steps
			table.insert(out, { cx + math.cos(ang) * r, cz + math.sin(ang) * r, py })
		end
	end
	return out
end

-- Rayon de courbure au point i (points i-k, i, i+k ; ligne rééchantillonnée)
local function radiusAt(line: Line, i: number, k: number): number
	local n = line.N
	local function idx(j: number): number
		if line.Closed then
			return ((j - 1) % n) + 1
		end
		return math.clamp(j, 1, n)
	end
	local a, b, c = idx(i - k), idx(i), idx(i + k)
	if a == b or b == c then
		return math.huge
	end
	local ax, az = line.X[a], line.Z[a]
	local bx, bz = line.X[b], line.Z[b]
	local cx, cz = line.X[c], line.Z[c]
	local ab = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local bc = math.sqrt((cx - bx) ^ 2 + (cz - bz) ^ 2)
	local ca = math.sqrt((ax - cx) ^ 2 + (az - cz) ^ 2)
	local area2 = math.abs((bx - ax) * (cz - az) - (bz - az) * (cx - ax))
	if area2 < 1e-6 then
		return math.huge
	end
	return ab * bc * ca / (2 * area2)
end
RaceRules.RadiusAt = radiusAt

-- Profil de vitesse (studs/s) à chaque point d'une ligne RÉÉCHANTILLONNÉE :
-- min(vmax, √(latAcc × R)), puis freinage anticipé (décélération `brake`).
function RaceRules.SpeedProfile(line: Line, vmax: number, latAcc: number?, brake: number?): { number }
	local ai = cfg().AI or {}
	local lat = latAcc or ai.LatAccel or 30
	local dec = brake or ai.Brake or 38
	local n = line.N
	local v = table.create(n, vmax)
	local step = if n > 1 then line.Total / (if line.Closed then n else n - 1) else 4
	local k = math.max(1, math.floor(10 / math.max(step, 0.5) + 0.5))
	for i = 1, n do
		local r = radiusAt(line, i, k)
		v[i] = math.min(vmax, math.sqrt(lat * r))
	end
	-- freinage : on parcourt la ligne à l'envers (2 tours pour une boucle)
	local passes = if line.Closed then 2 else 1
	for _ = 1, passes do
		for i = n - 1, 1, -1 do
			local ds = line.S[i + 1] - line.S[i]
			v[i] = math.min(v[i], math.sqrt(v[i + 1] ^ 2 + 2 * dec * ds))
		end
		if line.Closed and n > 1 then
			local ds = line.Total - line.S[n]
			v[n] = math.min(v[n], math.sqrt(v[1] ^ 2 + 2 * dec * ds))
		end
	end
	return v
end

-- Vitesse du profil à la distance s (interpolée)
function RaceRules.ProfileAt(line: Line, profile: { number }, s: number): number
	if line.N == 0 then
		return 0
	end
	local w = RaceRules.Wrap(line, s)
	local i = segmentAt(line, w)
	local j = nextIndex(line, i)
	local s0, s1 = line.S[i], segEnd(line, i)
	local t = math.clamp((w - s0) / math.max(1e-6, s1 - s0), 0, 1)
	return (profile[i] or 0) + ((profile[j] or 0) - (profile[i] or 0)) * t
end

----------------------------------------------------------------------
-- Pilotes IA
----------------------------------------------------------------------

-- Multiplicateur "élastique" de la vitesse visée d'une IA (juste : léger,
-- coupé dans le final). aiD = distance parcourue par l'IA, leadD = distance
-- du 1er HUMAIN, total = distance de la course.
function RaceRules.RubberBand(aiD: number, leadD: number?, total: number): number
	local ai = cfg().AI or {}
	if leadD == nil or total <= 0 then
		return 1
	end
	if aiD >= total * (1 - (ai.FairFinish or 0.12)) then
		return 1
	end
	local range = ai.RubberRange or 500
	local gap = leadD - aiD
	if gap > 0 then
		return 1 + (ai.RubberBoost or 0.06) * math.clamp(gap / range, 0, 1)
	end
	return 1 - (ai.RubberSlow or 0.1) * math.clamp(-gap / range, 0, 1)
end

-- Un pas de pilote IA : state = { D, V } ; target = vitesse visée (profil x
-- habileté x élastique), top = vitesse de pointe de SA voiture, accel =
-- accélération au départ (modèle de CarClient : a × (1 − 0,55 (v / top)²)).
function RaceRules.AIStep(state: { D: number, V: number }, dt: number, target: number, top: number, accel: number, brake: number?)
	local goal = math.clamp(target, 0, top)
	local v = state.V
	if v < goal then
		local a = accel * (1 - 0.55 * math.clamp(v / math.max(top, 1), 0, 1) ^ 2)
		v = math.min(goal, v + a * dt)
	else
		v = math.max(goal, v - (brake or 40) * dt)
	end
	state.V = v
	state.D += v * dt
end

----------------------------------------------------------------------
-- Classement
----------------------------------------------------------------------

-- racers = { { Finished, FinishTime, Progress, Dnf } } -> nouvelle liste triée
-- (arrivés par temps, puis en course par distance, abandons à la fin)
function RaceRules.Standings(racers: { any }): { any }
	local list = table.clone(racers)
	table.sort(list, function(a, b)
		local ra = if a.Dnf then 3 elseif a.Finished then 1 else 2
		local rb = if b.Dnf then 3 elseif b.Finished then 1 else 2
		if ra ~= rb then
			return ra < rb
		end
		if ra == 1 then
			local ta, tb = finite(a.FinishTime, math.huge), finite(b.FinishTime, math.huge)
			if ta ~= tb then
				return ta < tb
			end
		end
		local pa, pb = finite(a.Progress, 0), finite(b.Progress, 0)
		if pa ~= pb then
			return pa > pb
		end
		return tostring(a.Key or a.Name or "") < tostring(b.Key or b.Name or "")
	end)
	return list
end

-- Temps lisible : 1:02.35
function RaceRules.FormatTime(seconds: number?): string
	local s = finite(seconds, 0)
	if s < 0 then
		s = 0
	end
	local m = math.floor(s / 60)
	local rest = s - m * 60
	return string.format("%d:%05.2f", m, math.floor(rest * 100) / 100)
end

----------------------------------------------------------------------
-- Récompenses
----------------------------------------------------------------------

-- Secondes de production gagnées : place (1..), arrivé ?, nombre
-- d'adversaires HUMAINS. 0 si pas arrivé.
function RaceRules.RewardSeconds(place: number, finished: boolean, humanOpponents: number): number
	local r = cfg().Rewards or {}
	if not finished then
		return 0
	end
	local list = r.Seconds or { 120, 80, 55 }
	local base = list[place] or r.FinishSeconds or 35
	local opp = math.max(0, math.floor(finite(humanOpponents, 0)))
	local factor
	if opp == 0 then
		factor = r.SoloFactor or 0.75
	else
		factor = 1 + math.min(r.MaxHumanBonus or 0.3, (r.HumanBonus or 0.1) * opp)
	end
	return base * factor
end

-- Récompense en Dopamine (stats = Formulas.ComputeStats / GameService:GetStats).
-- rewardedToday = courses déjà payées aujourd'hui. -> (montant, secondes, plafonné?)
function RaceRules.Reward(stats: any, place: number, finished: boolean, humanOpponents: number, rewardedToday: number?): (number, number, boolean)
	local r = cfg().Rewards or {}
	local seconds = RaceRules.RewardSeconds(place, finished, humanOpponents)
	if seconds <= 0 then
		return 0, 0, false
	end
	if finite(rewardedToday, 0) >= (r.DailyRewarded or 8) then
		return 0, 0, true
	end
	local perSecond = finite(stats and stats.PerSecond, 0)
	local click = finite(stats and stats.ClickValue, 0)
	local cps = (Config.Rewards and Config.Rewards.EstimatedClicksPerSecond) or 3
	local production = math.max(0, perSecond + click * cps)
	local amount = math.floor(math.max(r.MinReward or 250, production * seconds))
	return amount, seconds, false
end

-- Gain net maximal (multiplicateur moyen de la production) pour un joueur
-- qui gagne toutes ses courses payées d'une journée de `sessionHours` h de
-- jeu (défaut 2 h) : borne utilisée par le test d'économie.
function RaceRules.MaxNetMultiplier(sessionHours: number?): number
	local r = cfg().Rewards or {}
	local best = ((r.Seconds or { 120 })[1] or 120) * (1 + (r.MaxHumanBonus or 0.3))
	local perDay = best * (r.DailyRewarded or 8)
	local hours = math.max(1, finite(sessionHours, 2))
	return 1 + perDay / (hours * 3600)
end

-- Jour (UTC) pour le plafond quotidien
function RaceRules.Today(now: number): number
	return math.floor(finite(now, 0) / 86400)
end

-- data.Race propre : { Day, Rewarded, Races, Wins, Podiums, Best = { [routeId] = s } }
function RaceRules.SanitizeData(raw: any, today: number): any
	local src = if type(raw) == "table" then raw else {}
	local function count(v: any): number
		return math.max(0, math.floor(finite(v, 0)))
	end
	local best = {}
	if type(src.Best) == "table" then
		for id, value in pairs(src.Best) do
			local t = finite(value, -1)
			if type(id) == "string" and Config.RaceRoutesById and Config.RaceRoutesById[id] and t >= 3 and t < 3600 then
				best[id] = t
			end
		end
	end
	local day = count(src.Day)
	local rewarded = count(src.Rewarded)
	if day ~= today then
		day = today
		rewarded = 0
	end
	return {
		Day = day,
		Rewarded = rewarded,
		Races = count(src.Races),
		Wins = count(src.Wins),
		Podiums = count(src.Podiums),
		Best = best,
	}
end

----------------------------------------------------------------------
-- Anti-triche
----------------------------------------------------------------------

-- Vitesse mesurée plausible ? dist (studs) parcourue en dt (s, fenêtre ~1 s),
-- top = vitesse de pointe de la voiture. -> "ok" | "fast" | "teleport"
function RaceRules.CheckMove(dist: number, dt: number, top: number): string
	local anti = cfg().Anti or {}
	local limit = finite(top, 60) * (anti.SpeedMargin or 1.3) + (anti.AbsSlack or 8)
	local d = finite(dist, 0)
	local t = math.max(finite(dt, 0), 0.05)
	if d > math.max(anti.TeleportStuds or 70, limit * t * 2.5) then
		return "teleport"
	end
	if t >= 0.5 and d / t > limit then
		return "fast"
	end
	return "ok"
end

-- Temps minimal (s) pour un tronçon de `length` studs
function RaceRules.MinSegmentTime(length: number, top: number): number
	local anti = cfg().Anti or {}
	return math.max(0, finite(length, 0)) / math.max(1, finite(top, 60) * (anti.SegmentFactor or 1.15))
end

return RaceRules
