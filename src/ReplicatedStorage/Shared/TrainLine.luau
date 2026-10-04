--[[
	TrainLine (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > TrainLine

	🚂 La LIGNE DE CEINTURE de Dopamine Town (v11, TRAIN11) : calcul PUR
	(nombres seulement, aucun Instance), partagé par le serveur
	(TrainService : sièges, montée, braquage) et les clients (TrainClient :
	rails, gares, trains, passages à niveau) -> tout le monde voit le même
	train au même endroit, sans réseau : la position est une fonction de
	l'heure du serveur (workspace:GetServerTimeNow()).

	TRACÉ (repère "ville" de WorldLayout : x, z depuis le centre de la place,
	+Z = sud) : une boucle dans la ceinture verte, entre l'avenue de ceinture
	(axe à R = WorldLayout.BeltR(count)) et l'autoroute, pour TOUS les
	nombres de parcelles (la boucle grandit avec R) :
	  - décalage de l'axe de la voie depuis l'axe de l'avenue de ceinture :
	    OFF_MID (29) au milieu de chaque côté (|le long| <= MID_HALF), où la
	    voie coupe À NIVEAU la route qui part vers l'échangeur (4 PASSAGES À
	    NIVEAU : barrières + feux clignotants), puis s'écarte en douceur
	    (cosinus) jusqu'à OFF_OUT (70) pour |le long| >= TRANS_END : la voie
	    passe ainsi SOUS les bretelles de l'échangeur sans jamais les toucher ;
	  - coins : arcs de rayon CORNER_R (120) centrés en (±(R-50), ±(R-50)) ;
	  - sens de circulation : côté sud vers +X, est vers -Z, nord vers -X,
	    ouest vers +Z ;
	  - 4 GARES, toutes du côté INTÉRIEUR (entre le trottoir de l'avenue de
	    ceinture et la voie), STATION_ALONG (260) après chaque passage à
	    niveau, en face du carrefour de l'avenue ±250 : Gare des Lofts (sud),
	    Gare du Parc des Sports (est), Gare des Collines (nord), Gare des
	    Cottages (ouest) ;
	  - 4 PLANQUES (braquage) dans les coins, à l'extérieur de la voie.

	HORAIRE (fonction pure de l'heure du serveur) : deux trains sur la même
	boucle, à une demi-boucle l'un de l'autre (jamais de collision) :
	  1. "Dopamine Express" : locomotive + 2 voitures + WAGON BLINDÉ 💎 ;
	  2. "Navette de la ceinture" : locomotive + 3 voitures.
	Cycles de CYCLE (1200 s = 20 min) : au début de chaque cycle, le convoi
	de diamants fait un LONG ARRÊT (HOLD = 210 s) à une gare (tour à tour :
	sud, est, nord, ouest) -> fenêtre du BRAQUAGE (TrainService + HeistKit).
	Ensuite il roule de gare en gare (vitesse SPEED, accélération ACCEL,
	arrêts d'au moins DWELL_MIN s, répartis pour retomber pile à l'heure)
	jusqu'à la gare du braquage suivant. La navette fait la même chose, une
	demi-boucle plus loin (elle attend à la gare d'en face pendant le long
	arrêt : régulation).

	API (count = nombre de parcelles, t = heure du serveur) :
	  TrainLine.Path(count) -> { Points = { {X, Z, S, A, Side} }, Length, R }
	  TrainLine.PointAt(count, s) -> (x, z, dx, dz)   (s modulo la longueur)
	  TrainLine.Near(count, x, z, r) -> boolean   voie (±CORRIDOR), gares,
	      planques, matériel des passages à niveau : À LAISSER LIBRE
	  TrainLine.Stations(count) -> { Station }  Station = { Index, Id, Name,
	      Emoji, X, Z, Yaw (LookVector = sens de marche), S, Side, Rect,
	      Platform, Building, InX, InZ (vers le centre) }
	  TrainLine.Crossings(count) -> { Crossing }  Crossing = { Index, Id, X,
	      Z, S, Yaw (sens de marche), RoadYaw, EdgeKey?, StopDist, Width }
	  TrainLine.CrossingState(count, i, t) -> (feux allumés, barrière 0..1)
	  TrainLine.CrossingClosed(count, i, t) -> boolean (voitures : STOP à
	      StopDist du centre, des deux côtés)
	  TrainLine.Hideouts(count) -> { {Index, X, Z, Yaw, W, D} }
	  TrainLine.Trains -> définitions (voitures, longueurs)
	  TrainLine.State(count, t, trainIndex?) -> TrainState
	      { Train, S (tête), V, Phase "Hold"|"Dwell"|"Run", Station (gare
	      d'arrêt ou de départ), Next (gare suivante), DepartAt, ArriveAt,
	      Cycle, Heist (long arrêt du convoi en cours) }
	  TrainLine.CarPoses(count, t, trainIndex) -> { {Kind, X, Z, DX, DZ, Len,
	      Offset} } (centre de chaque voiture, direction de marche)
	  TrainLine.CarPoseAt(count, headS, offset, len) -> (x, z, dx, dz)
	  TrainLine.Heist(count, t) -> { Active, Start, End, Station, Cycle,
	      AnnounceAt } (long arrêt en cours, sinon le prochain)
	  TrainLine.SeatsLocal(kind) -> { {X, Y, Z, Yaw} } (repère de la voiture :
	      origine sur le dessus du rail au centre, -Z = avant, +X = droite =
	      EXTÉRIEUR de la boucle, -X = côté quai ; Y = dessus du coussin)
	  TrainLine.NextStop(count, t, trainIndex, station) -> (arrivée, départ)
	      prochain passage du train à cette gare (en gare : arrivée <= t)
	  TrainLine.VaultLocal() -> positions locales du braquage (porte,
	      boîtier, coffre, sacs)
	  TrainLine.ToWorld(count, t, trainIndex, carIndex, lx, ly, lz) -> (x, y, z)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)

local TrainLine = {}

----------------------------------------------------------------------
-- Constantes (studs, secondes)
----------------------------------------------------------------------

TrainLine.OFF_MID = 29 -- axe de la voie au passage à niveau (depuis l'axe de l'avenue de ceinture) ; v11 : 26 -> 29 (lignes d'arrêt hors du carrefour de la ceinture : CARS11)
TrainLine.OFF_OUT = 70 -- axe de la voie ailleurs
TrainLine.MID_HALF = 40 -- |le long| <= ça : décalage OFF_MID
TrainLine.TRANS_END = 140 -- |le long| >= ça : décalage OFF_OUT
TrainLine.CORNER_R = 120 -- rayon des coins
TrainLine.CORRIDOR = 12 -- demi-largeur de l'emprise à laisser libre
TrainLine.GAUGE = 5 -- entre les axes des deux rails
TrainLine.RAIL_Y = 1.15 -- dessus du rail (repère : Origin().Y)
TrainLine.FLOOR_Y = 4.15 -- plancher des voitures
TrainLine.FLOOR_L = TrainLine.FLOOR_Y - TrainLine.RAIL_Y -- (3) plancher dans le repère local des voitures
TrainLine.PLATFORM_Y = 4.15 -- dessus du quai = plancher des voitures (de plain-pied, SCALE11)
TrainLine.CAR_W = 11 -- largeur des voitures
TrainLine.CAR_H = 13 -- hauteur (au-dessus du rail)
TrainLine.GAP = 2 -- entre deux voitures (soufflets)

TrainLine.STATION_ALONG = 260 -- centre des gares : après le passage à niveau
TrainLine.PLATFORM_LEN = 190
TrainLine.PLATFORM_IN = 50 -- quai : du décalage 50...
TrainLine.PLATFORM_OUT = 64 -- ... à 64 (bord du quai : axe - CAR_W / 2 - 0,5)
TrainLine.BUILDING_IN = 18 -- bâtiment voyageurs : décalage 18..44 (au niveau du trottoir), longueur 90
TrainLine.BUILDING_OUT = 44 -- (44..50 : marches jusqu'au quai)
TrainLine.BUILDING_LEN = 90
TrainLine.STATION_IN = 16 -- emprise d'une gare : du bord du trottoir (16) au bord du quai

TrainLine.SPEED = 48 -- vitesse de croisière
TrainLine.ACCEL = 6 -- accélération / freinage
TrainLine.DWELL_MIN = 18 -- arrêt minimal en gare
TrainLine.CYCLE = 1200 -- un convoi de diamants toutes les 20 min
TrainLine.HOLD = 210 -- long arrêt du convoi (fenêtre du braquage)
TrainLine.ANNOUNCE = 120 -- annonce avant l'arrivée du convoi

-- Passages à niveau : distances de la TÊTE du train au centre du passage
TrainLine.WARN_DIST = 560 -- les feux clignotent
TrainLine.CLOSED_DIST = 420 -- barrières baissées (abaissement entre les deux)
TrainLine.CLEAR_AFTER = 30 -- après la queue : barrières encore baissées
TrainLine.RAISE_LEN = 60 -- puis remontée sur ces studs de marche
TrainLine.STOP_DIST = 10 -- ligne d'arrêt des voitures (depuis l'axe de la voie : juste derrière les barrières, à ±9)

TrainLine.CARS = {
	Loco = { Len = 48, Seats = 0 },
	Coach = { Len = 42, Seats = 16 },
	Vault = { Len = 38, Seats = 0 },
}

TrainLine.Trains = {
	{ Index = 1, Id = "Express", Name = "Dopamine Express", Cars = { "Loco", "Coach", "Coach", "Vault" }, Livery = "Express" },
	{ Index = 2, Id = "Shuttle", Name = "Belt shuttle", Cars = { "Loco", "Coach", "Coach", "Coach" }, Livery = "Shuttle" },
}

TrainLine.STATION_DEFS = {
	{ Id = "Lofts", Name = "Lofts station", Emoji = "🏭" },
	{ Id = "Sports", Name = "Sports park station", Emoji = "🏟️" },
	{ Id = "Hills", Name = "Hills station", Emoji = "🌲" },
	{ Id = "Cottages", Name = "Cottages station", Emoji = "🏡" },
}

-- côtés dans le sens de marche : direction d (le long), normale n (vers l'extérieur)
local SIDES = {
	{ DX = 1, DZ = 0, NX = 0, NZ = 1 }, -- sud : vers +X
	{ DX = 0, DZ = -1, NX = 1, NZ = 0 }, -- est : vers -Z
	{ DX = -1, DZ = 0, NX = 0, NZ = -1 }, -- nord : vers -X
	{ DX = 0, DZ = 1, NX = -1, NZ = 0 }, -- ouest : vers +Z
}
TrainLine.SIDES = SIDES

local function finite(v: any, default: number): number
	if type(v) == "number" and v == v and v > -math.huge and v < math.huge then
		return v
	end
	return default
end

local function yawOf(lx: number, lz: number): number
	-- CFrame.Angles(0, yaw, 0).LookVector = (lx, 0, lz)
	return math.atan2(-lx, -lz)
end

-- Décalage de la voie en fonction de la position le long du côté
function TrainLine.Offset(a: number): number
	local d = math.abs(a)
	if d <= TrainLine.MID_HALF then
		return TrainLine.OFF_MID
	elseif d >= TrainLine.TRANS_END then
		return TrainLine.OFF_OUT
	end
	local u = (d - TrainLine.MID_HALF) / (TrainLine.TRANS_END - TrainLine.MID_HALF)
	return TrainLine.OFF_MID + (TrainLine.OFF_OUT - TrainLine.OFF_MID) * (1 - math.cos(math.pi * u)) / 2
end

----------------------------------------------------------------------
-- Tracé (mis en cache par nombre de parcelles)
----------------------------------------------------------------------

type Point = { X: number, Z: number, S: number, A: number, Side: number }
type Path = {
	Points: { Point },
	Length: number,
	R: number,
	Count: number,
	CrossS: { number },
	StationS: { number },
	Grid: { [number]: { number } },
}

local GRID = 50
local pathCache: { [number]: Path } = {}

local function cellKey(cx: number, cz: number): number
	return (cx + 1000) * 4000 + (cz + 1000)
end

local function countOf(count: number?): number
	return WorldLayout.PlotCount(finite(count, 8))
end

local function buildPath(count: number): Path
	local R = WorldLayout.BeltR(count)
	local A = R - 50 -- bout de la partie droite d'un côté (début de l'arc du coin)
	local Rc = TrainLine.CORNER_R
	local pts: { Point } = {}
	local crossIdx, stationIdx = {}, {}
	for k, side in ipairs(SIDES) do
		-- valeurs de "a" le long du côté (fin : près des passages, large : ailleurs)
		local list = {}
		local a = -A
		while a < A - 1e-6 do
			table.insert(list, a)
			local d = math.abs(a)
			local step = if d < TrainLine.TRANS_END + 10 then 5 else 20
			local nextA = a + step
			-- points clés exacts : passage (0), gare (STATION_ALONG), bords de la transition
			for _, key in ipairs({ -TrainLine.TRANS_END, -TrainLine.MID_HALF, 0, TrainLine.MID_HALF, TrainLine.TRANS_END, TrainLine.STATION_ALONG }) do
				if key > a + 1e-6 and key < nextA - 1e-6 then
					nextA = key
				end
			end
			a = math.min(nextA, A)
		end
		for _, av in ipairs(list) do
			local off = R + TrainLine.Offset(av)
			table.insert(pts, { X = side.DX * av + side.NX * off, Z = side.DZ * av + side.NZ * off, S = 0, A = av, Side = k })
			if math.abs(av) < 1e-6 then
				crossIdx[k] = #pts
			elseif math.abs(av - TrainLine.STATION_ALONG) < 1e-6 then
				stationIdx[k] = #pts
			end
		end
		-- coin : de la normale de ce côté vers la direction (le côté suivant)
		local cx = side.DX * A + side.NX * A
		local cz = side.DZ * A + side.NZ * A
		local steps = 30
		for i = 0, steps - 1 do
			local th = (i / steps) * math.pi / 2
			local c, s = math.cos(th), math.sin(th)
			table.insert(pts, {
				X = cx + Rc * (side.NX * c + side.DX * s),
				Z = cz + Rc * (side.NZ * c + side.DZ * s),
				S = 0,
				A = A + Rc * th, -- (indicatif)
				Side = k,
			})
		end
	end
	-- abscisses curvilignes
	local acc = 0
	for i, p in ipairs(pts) do
		if i > 1 then
			local q = pts[i - 1]
			acc += math.sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2)
		end
		p.S = acc
	end
	local last, first = pts[#pts], pts[1]
	local length = acc + math.sqrt((first.X - last.X) ^ 2 + (first.Z - last.Z) ^ 2)
	-- grille des segments (Near)
	local grid: { [number]: { number } } = {}
	for i = 1, #pts do
		local p, q = pts[i], pts[i % #pts + 1]
		local x0, x1 = math.min(p.X, q.X), math.max(p.X, q.X)
		local z0, z1 = math.min(p.Z, q.Z), math.max(p.Z, q.Z)
		for gx = math.floor(x0 / GRID), math.floor(x1 / GRID) do
			for gz = math.floor(z0 / GRID), math.floor(z1 / GRID) do
				local key = cellKey(gx, gz)
				local cell = grid[key]
				if not cell then
					cell = {}
					grid[key] = cell
				end
				table.insert(cell, i)
			end
		end
	end
	local crossS, stationS = {}, {}
	for k = 1, 4 do
		crossS[k] = pts[crossIdx[k]].S
		stationS[k] = pts[stationIdx[k]].S
	end
	return { Points = pts, Length = length, R = R, Count = count, CrossS = crossS, StationS = stationS, Grid = grid }
end

local function getPath(count: number?): Path
	local n = countOf(count)
	local cached = pathCache[n]
	if not cached then
		cached = buildPath(n)
		pathCache[n] = cached
	end
	return cached
end

function TrainLine.Path(count: number?): any
	return getPath(count)
end

function TrainLine.Length(count: number?): number
	return getPath(count).Length
end

-- Point de la voie à l'abscisse s (modulo la longueur) -> x, z, direction unitaire
function TrainLine.PointAt(count: number?, s: number): (number, number, number, number)
	local path = getPath(count)
	local L = path.Length
	s = finite(s, 0) % L
	local pts = path.Points
	local n = #pts
	-- recherche dichotomique du segment [i, i+1]
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if pts[mid].S <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local i = lo
	if pts[n].S <= s then
		i = n
	end
	local p = pts[i]
	local q = pts[i % n + 1]
	local segLen = if i == n then L - p.S else q.S - p.S
	local dx, dz = q.X - p.X, q.Z - p.Z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-9 then
		return p.X, p.Z, 1, 0
	end
	local u = if segLen > 1e-9 then (s - p.S) / segLen else 0
	return p.X + dx * u, p.Z + dz * u, dx / len, dz / len
end

----------------------------------------------------------------------
-- Gares, passages à niveau, planques
----------------------------------------------------------------------

local stationCache: { [number]: { any } } = {}
local crossingCache: { [number]: { any } } = {}
local hideoutCache: { [number]: { any } } = {}

-- rectangle aligné (repère ville) d'un côté : le long [a0, a1], décalage [o0, o1]
local function sideRect(side: any, R: number, a0: number, a1: number, o0: number, o1: number): { X: number, Z: number, W: number, D: number }
	local ac, oc = (a0 + a1) / 2, R + (o0 + o1) / 2
	local la, lo = math.abs(a1 - a0), math.abs(o1 - o0)
	local x = side.DX * ac + side.NX * oc
	local z = side.DZ * ac + side.NZ * oc
	if side.DX ~= 0 then
		return { X = x, Z = z, W = la, D = lo }
	end
	return { X = x, Z = z, W = lo, D = la }
end
TrainLine.SideRect = sideRect

function TrainLine.Stations(count: number?): { any }
	local path = getPath(count)
	local cached = stationCache[path.Count]
	if cached then
		return cached
	end
	local list = {}
	local R = path.R
	local half = TrainLine.PLATFORM_LEN / 2
	for k, side in ipairs(SIDES) do
		local def = TrainLine.STATION_DEFS[k]
		local a = TrainLine.STATION_ALONG
		local off = R + TrainLine.OFF_OUT
		table.insert(list, {
			Index = k,
			Id = def.Id,
			Name = def.Name,
			Emoji = def.Emoji,
			Side = k,
			X = side.DX * a + side.NX * off,
			Z = side.DZ * a + side.NZ * off,
			Yaw = yawOf(side.DX, side.DZ),
			S = path.StationS[k],
			InX = -side.NX,
			InZ = -side.NZ,
			-- emprise complète (à laisser libre) : du trottoir de la ceinture au bord du quai
			Rect = sideRect(side, R, a - half - 2, a + half + 2, TrainLine.STATION_IN, TrainLine.PLATFORM_OUT),
			Platform = sideRect(side, R, a - half, a + half, TrainLine.PLATFORM_IN, TrainLine.PLATFORM_OUT),
			Building = sideRect(side, R, a - TrainLine.BUILDING_LEN / 2, a + TrainLine.BUILDING_LEN / 2, TrainLine.BUILDING_IN, TrainLine.BUILDING_OUT),
		})
	end
	stationCache[path.Count] = list
	return list
end

function TrainLine.Crossings(count: number?): { any }
	local path = getPath(count)
	local cached = crossingCache[path.Count]
	if cached then
		return cached
	end
	local list = {}
	local R = path.R
	for k, side in ipairs(SIDES) do
		local off = R + TrainLine.OFF_MID
		local x, z = side.NX * off, side.NZ * off
		-- arête de la route coupée (la plus proche du centre du passage)
		local edgeKey: string? = nil
		local width = 20
		local edge: any = (WorldLayout.NearestRoad(path.Count, x, z))
		if type(edge) == "table" then
			edgeKey = tostring(edge.A) .. "|" .. tostring(edge.B)
			width = finite(edge.Width, 20)
		end
		table.insert(list, {
			Index = k,
			Id = "X" .. k,
			X = x,
			Z = z,
			S = path.CrossS[k],
			Yaw = yawOf(side.DX, side.DZ),
			RoadYaw = yawOf(side.NX, side.NZ),
			EdgeKey = edgeKey,
			StopDist = TrainLine.STOP_DIST,
			Width = width,
			NX = side.NX,
			NZ = side.NZ,
		})
	end
	crossingCache[path.Count] = list
	return list
end

-- Planques (fin du braquage) : dans les coins, à l'extérieur de la voie.
-- Planque k = coin APRÈS la gare k (le plus proche dans le sens de marche).
TrainLine.HIDEOUT_OUT = 95 -- centre : (R + 95) sur les deux axes
TrainLine.HIDEOUT_W = 30
TrainLine.HIDEOUT_D = 22
function TrainLine.Hideouts(count: number?): { any }
	local path = getPath(count)
	local cached = hideoutCache[path.Count]
	if cached then
		return cached
	end
	local list = {}
	local R = path.R
	for k, side in ipairs(SIDES) do
		local c = R + TrainLine.HIDEOUT_OUT
		local x = side.DX * c + side.NX * c
		local z = side.DZ * c + side.NZ * c
		-- façade tournée vers le centre de la ville (vers la voie)
		table.insert(list, { Index = k, X = x, Z = z, Yaw = yawOf(-x, -z), W = TrainLine.HIDEOUT_W, D = TrainLine.HIDEOUT_D })
	end
	hideoutCache[path.Count] = list
	return list
end

local function inRect(rect: any, x: number, z: number, r: number): boolean
	return math.abs(x - rect.X) <= rect.W / 2 + r and math.abs(z - rect.Z) <= rect.D / 2 + r
end

-- Vrai si (x, z) (rayon r) touche l'emprise du train : voie (±CORRIDOR),
-- gares (bâtiment + quai), planques, feux et barrières des passages.
function TrainLine.Near(count: number?, x: number, z: number, r: number?): boolean
	local path = getPath(count)
	local rr = math.max(0, finite(r, 0))
	x, z = finite(x, 0), finite(z, 0)
	local R = path.R
	local m = math.max(math.abs(x), math.abs(z))
	-- (rejet rapide : tout est dans l'anneau carré [R + 14, R + 125])
	if m < R + TrainLine.STATION_IN - 2 - rr or m > R + TrainLine.HIDEOUT_OUT + 30 + rr then
		return false
	end
	for _, st in ipairs(TrainLine.Stations(count)) do
		if inRect(st.Rect, x, z, rr) then
			return true
		end
	end
	for _, h in ipairs(TrainLine.Hideouts(count)) do
		if (x - h.X) ^ 2 + (z - h.Z) ^ 2 <= (h.W / 2 + 8 + rr) ^ 2 then
			return true
		end
	end
	-- voie : segments de la grille autour du point
	local reach = TrainLine.CORRIDOR + rr
	local pts = path.Points
	local n = #pts
	local seen = {}
	for gx = math.floor((x - reach) / GRID), math.floor((x + reach) / GRID) do
		for gz = math.floor((z - reach) / GRID), math.floor((z + reach) / GRID) do
			local cell = path.Grid[cellKey(gx, gz)]
			if cell then
				for _, i in ipairs(cell) do
					if not seen[i] then
						seen[i] = true
						local p, q = pts[i], pts[i % n + 1]
						local dx, dz = q.X - p.X, q.Z - p.Z
						local l2 = dx * dx + dz * dz
						local u = if l2 > 0 then math.clamp(((x - p.X) * dx + (z - p.Z) * dz) / l2, 0, 1) else 0
						local ex, ez = p.X + dx * u - x, p.Z + dz * u - z
						if ex * ex + ez * ez <= reach * reach then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

-- Distance (au carré) de (x, z) à l'axe de la voie -> (d², s du point le plus proche)
function TrainLine.Project(count: number?, x: number, z: number, maxDist: number?): (number, number)
	local path = getPath(count)
	local reach = finite(maxDist, 40)
	local pts = path.Points
	local n = #pts
	local best, bestS = math.huge, 0
	local seen = {}
	for gx = math.floor((x - reach) / GRID), math.floor((x + reach) / GRID) do
		for gz = math.floor((z - reach) / GRID), math.floor((z + reach) / GRID) do
			local cell = path.Grid[cellKey(gx, gz)]
			if cell then
				for _, i in ipairs(cell) do
					if not seen[i] then
						seen[i] = true
						local p, q = pts[i], pts[i % n + 1]
						local dx, dz = q.X - p.X, q.Z - p.Z
						local l2 = dx * dx + dz * dz
						local u = if l2 > 0 then math.clamp(((x - p.X) * dx + (z - p.Z) * dz) / l2, 0, 1) else 0
						local ex, ez = p.X + dx * u - x, p.Z + dz * u - z
						local d2 = ex * ex + ez * ez
						if d2 < best then
							best = d2
							local segLen = if i == n then path.Length - p.S else q.S - p.S
							bestS = p.S + segLen * u
						end
					end
				end
			end
		end
	end
	return best, bestS
end

----------------------------------------------------------------------
-- Trains : longueurs, poses des voitures
----------------------------------------------------------------------

-- Longueur totale d'un train + décalage (depuis la tête) de chaque voiture
function TrainLine.Consist(trainIndex: number): ({ { Kind: string, Len: number, Offset: number } }, number)
	local def = TrainLine.Trains[trainIndex] or TrainLine.Trains[1]
	local list = {}
	local off = 0
	for i, kind in ipairs(def.Cars) do
		local len = TrainLine.CARS[kind].Len
		table.insert(list, { Kind = kind, Len = len, Offset = off })
		off += len
		if i < #def.Cars then
			off += TrainLine.GAP
		end
	end
	return list, off
end

-- Centre et direction d'une voiture : posée sur ses deux bogies (corde)
function TrainLine.CarPoseAt(count: number?, headS: number, offset: number, len: number): (number, number, number, number)
	local sf = headS - offset - len * 0.18
	local sr = headS - offset - len * 0.82
	local fx, fz = TrainLine.PointAt(count, sf)
	local rx, rz = TrainLine.PointAt(count, sr)
	local dx, dz = fx - rx, fz - rz
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1e-6 then
		local _, _, tx, tz = TrainLine.PointAt(count, headS - offset - len / 2)
		dx, dz, l = tx, tz, 1
	end
	return (fx + rx) / 2, (fz + rz) / 2, dx / l, dz / l
end

----------------------------------------------------------------------
-- Horaire
----------------------------------------------------------------------

type Plan = { Legs: number, Run: { number }, Start: { number }, Dwell: number }
local planCache: { [string]: Plan } = {}

-- Temps de parcours d'une distance D (départ et arrivée à l'arrêt)
function TrainLine.RunTime(D: number): number
	local V, A = TrainLine.SPEED, TrainLine.ACCEL
	if D >= V * V / A then
		return D / V + V / A
	end
	return 2 * math.sqrt(D / A)
end

-- Distance parcourue après tau s d'un trajet de longueur D
function TrainLine.RunDistance(D: number, tau: number): (number, number)
	local V, A = TrainLine.SPEED, TrainLine.ACCEL
	local T = TrainLine.RunTime(D)
	tau = math.clamp(tau, 0, T)
	local vmax = math.min(V, math.sqrt(D * A))
	local ta = vmax / A
	if tau <= ta then
		return 0.5 * A * tau * tau, A * tau
	elseif tau >= T - ta then
		local r = T - tau
		return D - 0.5 * A * r * r, A * r
	end
	return 0.5 * A * ta * ta + vmax * (tau - ta), vmax
end

-- Tête du train 1 à l'arrêt en gare k
local function stopS(path: Path, k: number): number
	local _, total = TrainLine.Consist(1)
	return (path.StationS[(k - 1) % 4 + 1] + total / 2) % path.Length
end

local function legDistance(path: Path, from: number, to: number): number
	local d = (stopS(path, to) - stopS(path, from)) % path.Length
	if d < 1 then
		d += path.Length
	end
	return d
end

-- Gare du long arrêt du cycle c (1..4)
function TrainLine.HeistStation(cycle: number): number
	return (math.floor(finite(cycle, 0)) % 4) + 1
end

-- Plan d'un cycle commençant à la gare H : n trajets (n = 1 mod 4), arrêts égaux
local function getPlan(path: Path, H: number): Plan
	local key = path.Count .. ":" .. H
	local cached = planCache[key]
	if cached then
		return cached
	end
	local budget = TrainLine.CYCLE - TrainLine.HOLD
	local function runs(n: number): ({ number }, number)
		local list, sum = {}, 0
		for k = 1, n do
			local from = (H - 1 + k - 1) % 4 + 1
			local to = from % 4 + 1
			local t = TrainLine.RunTime(legDistance(path, from, to))
			list[k] = t
			sum += t
		end
		return list, sum
	end
	local bestN, bestRuns, bestDwell = 1, nil :: { number }?, 0
	local n = 1
	while n <= 4 * 60 + 1 do
		local list, sum = runs(n)
		if n == 1 then
			if sum <= budget then
				bestN, bestRuns, bestDwell = 1, list, 0
			end
		else
			local dwell = (budget - sum) / (n - 1)
			if dwell >= TrainLine.DWELL_MIN then
				bestN, bestRuns, bestDwell = n, list, dwell
			else
				break
			end
		end
		n += 4
	end
	if not bestRuns then
		-- (boucle immense : un seul trajet, plus court que le cycle par construction ici)
		bestRuns = runs(1)
	end
	local starts = {}
	local acc = 0
	for k = 1, bestN do
		starts[k] = acc
		acc += (bestRuns :: { number })[k] + bestDwell
	end
	local plan = { Legs = bestN, Run = bestRuns :: { number }, Start = starts, Dwell = bestDwell }
	planCache[key] = plan
	return plan
end

function TrainLine.Plan(count: number?, H: number): any
	return getPlan(getPath(count), H)
end

export type TrainState = {
	Train: number,
	S: number,
	V: number,
	Phase: string,
	Station: number,
	Next: number,
	DepartAt: number?,
	ArriveAt: number?,
	StopAt: number?,
	Cycle: number,
	Heist: boolean,
}

-- État du train 1 (convoi) à l'instant t
local function expressState(path: Path, t: number): TrainState
	local C = TrainLine.CYCLE
	local cycle = math.floor(t / C)
	local t0 = cycle * C
	local H = TrainLine.HeistStation(cycle)
	local tau = t - t0
	if tau < TrainLine.HOLD then
		return { Train = 1, S = stopS(path, H), V = 0, Phase = "Hold", Station = H, Next = H % 4 + 1,
			DepartAt = t0 + TrainLine.HOLD, ArriveAt = nil, StopAt = t0, Cycle = cycle, Heist = true }
	end
	local plan = getPlan(path, H)
	local rel = tau - TrainLine.HOLD
	-- trajet en cours : le dernier dont le départ est passé
	local k = 1
	for i = plan.Legs, 1, -1 do
		if rel >= plan.Start[i] then
			k = i
			break
		end
	end
	local from = (H - 1 + k - 1) % 4 + 1
	local to = from % 4 + 1
	local within = rel - plan.Start[k]
	local run = plan.Run[k]
	if within < run then
		local D = legDistance(path, from, to)
		local d, v = TrainLine.RunDistance(D, within)
		return { Train = 1, S = (stopS(path, from) + d) % path.Length, V = v, Phase = "Run", Station = from, Next = to,
			DepartAt = t0 + TrainLine.HOLD + plan.Start[k], ArriveAt = t0 + TrainLine.HOLD + plan.Start[k] + run, StopAt = nil, Cycle = cycle, Heist = false }
	end
	-- arrêt en gare "to" (le dernier arrêt du cycle mène au long arrêt suivant)
	local departAt = if k < plan.Legs then t0 + TrainLine.HOLD + plan.Start[k + 1] else t0 + C + TrainLine.HOLD
	return { Train = 1, S = stopS(path, to), V = 0, Phase = "Dwell", Station = to, Next = to % 4 + 1,
		DepartAt = departAt, ArriveAt = nil, StopAt = t0 + TrainLine.HOLD + plan.Start[k] + run, Cycle = cycle, Heist = false }
end

-- État d'un train (1 = convoi, 2 = navette : une demi-boucle plus loin)
function TrainLine.State(count: number?, t: number, trainIndex: number?): TrainState
	local path = getPath(count)
	local st = expressState(path, finite(t, 0))
	if (trainIndex or 1) == 2 then
		local _, len1 = TrainLine.Consist(1)
		local _, len2 = TrainLine.Consist(2)
		local s2 = (st.S - len1 / 2 + path.Length / 2 + len2 / 2) % path.Length
		return {
			Train = 2,
			S = s2,
			V = st.V,
			Phase = if st.Phase == "Hold" then "Dwell" else st.Phase,
			Station = (st.Station + 1) % 4 + 1,
			Next = (st.Next + 1) % 4 + 1,
			DepartAt = st.DepartAt,
			ArriveAt = st.ArriveAt,
			StopAt = st.StopAt,
			Cycle = st.Cycle,
			Heist = false,
		}
	end
	return st
end

-- Arrêts du convoi pendant le cycle c : { {Station, Arrive, Depart} }
local function cycleStops(path: Path, c: number): { any }
	local C = TrainLine.CYCLE
	local t0 = c * C
	local H = TrainLine.HeistStation(c)
	local plan = getPlan(path, H)
	local list = { { Station = H, Arrive = t0, Depart = t0 + TrainLine.HOLD } }
	for k = 1, plan.Legs - 1 do
		local from = (H - 1 + k - 1) % 4 + 1
		local to = from % 4 + 1
		-- (le dernier trajet arrive au long arrêt du cycle suivant)
		table.insert(list, { Station = to, Arrive = t0 + TrainLine.HOLD + plan.Start[k] + plan.Run[k], Depart = t0 + TrainLine.HOLD + plan.Start[k + 1] })
	end
	return list
end

-- Prochain passage d'un train à une gare : (arrivée, départ). En gare : arrivée <= t.
function TrainLine.NextStop(count: number?, t: number, trainIndex: number, station: number): (number, number)
	local path = getPath(count)
	t = finite(t, 0)
	local shift = if (trainIndex or 1) == 2 then 2 else 0
	local c = math.floor(t / TrainLine.CYCLE)
	for cc = c, c + 2 do
		for _, stop in ipairs(cycleStops(path, cc)) do
			local st = (stop.Station - 1 + shift) % 4 + 1
			if st == station and stop.Depart > t then
				return stop.Arrive, stop.Depart
			end
		end
	end
	return t + TrainLine.CYCLE, t + TrainLine.CYCLE + TrainLine.DWELL_MIN
end

-- Poses de toutes les voitures d'un train
function TrainLine.CarPoses(count: number?, t: number, trainIndex: number): { any }
	local st = TrainLine.State(count, t, trainIndex)
	local list = {}
	local consist = TrainLine.Consist(trainIndex)
	for i, car in ipairs(consist) do
		local x, z, dx, dz = TrainLine.CarPoseAt(count, st.S, car.Offset, car.Len)
		list[i] = { Kind = car.Kind, X = x, Z = z, DX = dx, DZ = dz, Len = car.Len, Offset = car.Offset }
	end
	return list
end

-- Long arrêt du convoi : en cours, sinon le prochain
function TrainLine.Heist(count: number?, t: number): any
	local C = TrainLine.CYCLE
	t = finite(t, 0)
	local cycle = math.floor(t / C)
	local t0 = cycle * C
	if t - t0 >= TrainLine.HOLD then
		cycle += 1
		t0 += C
	end
	return {
		Active = t >= t0 and t < t0 + TrainLine.HOLD,
		Start = t0,
		End = t0 + TrainLine.HOLD,
		AnnounceAt = t0 - TrainLine.ANNOUNCE,
		Station = TrainLine.HeistStation(cycle),
		Cycle = cycle,
	}
end

----------------------------------------------------------------------
-- Passages à niveau
----------------------------------------------------------------------

-- (feux allumés, barrière 0 = levée .. 1 = baissée) pour le passage i
function TrainLine.CrossingState(count: number?, i: number, t: number): (boolean, number)
	local path = getPath(count)
	local L = path.Length
	local cs = path.CrossS[i]
	if not cs then
		return false, 0
	end
	local lights, k = false, 0
	for ti = 1, #TrainLine.Trains do
		local st = TrainLine.State(count, t, ti)
		local _, len = TrainLine.Consist(ti)
		local ahead = (cs - st.S) % L -- la tête arrive
		local passed = (st.S - cs) % L -- la tête est passée
		local kk = 0
		local on = false
		if passed <= len + TrainLine.CLEAR_AFTER then
			on, kk = true, 1
		elseif passed <= len + TrainLine.CLEAR_AFTER + TrainLine.RAISE_LEN then
			on = true
			kk = 1 - (passed - len - TrainLine.CLEAR_AFTER) / TrainLine.RAISE_LEN
		elseif ahead <= TrainLine.WARN_DIST then
			on = true
			kk = math.clamp((TrainLine.WARN_DIST - ahead) / (TrainLine.WARN_DIST - TrainLine.CLOSED_DIST), 0, 1)
		end
		if on then
			lights = true
			k = math.max(k, kk)
		end
	end
	return lights, k
end

function TrainLine.CrossingClosed(count: number?, i: number, t: number): boolean
	local on = TrainLine.CrossingState(count, i, t)
	return on
end

----------------------------------------------------------------------
-- Repère local des voitures (origine : dessus du rail, au centre ;
-- -Z = avant, +X = droite = extérieur de la boucle, -X = côté quai)
----------------------------------------------------------------------

local seatCache: { [string]: { any } } = {}

-- Sièges d'une voiture : 4 rangées de 2 + 2 en vis-à-vis (carrés), allée au milieu
TrainLine.SEAT_ROWS = { -11, -5.5, 5.5, 11 }
TrainLine.SEAT_X = { -3.6, -1.6, 1.6, 3.6 }
TrainLine.SEAT_TOP = 1.85 -- dessus de l'assise au-dessus du plancher (cibles SCALE11 : 1,8..1,9)
function TrainLine.SeatsLocal(kind: string): { any }
	local cached = seatCache[kind]
	if cached then
		return cached
	end
	local list = {}
	if kind == "Coach" then
		for r, z in ipairs(TrainLine.SEAT_ROWS) do
			-- rangées 1 et 3 regardent vers l'arrière (+Z), 2 et 4 vers l'avant (-Z) : vis-à-vis
			local yaw = if r % 2 == 1 then math.pi else 0
			for _, x in ipairs(TrainLine.SEAT_X) do
				table.insert(list, { X = x, Y = TrainLine.FLOOR_L + TrainLine.SEAT_TOP, Z = z, Yaw = yaw })
			end
		end
	end
	seatCache[kind] = list
	return list
end

-- Places du braquage dans le wagon blindé (repère local : Y depuis le dessus du rail)
function TrainLine.VaultLocal(): any
	local half = TrainLine.CAR_W / 2
	local F = TrainLine.FLOOR_L
	return {
		Door = { X = -half - 0.6, Y = F + 4, Z = 0 }, -- porte blindée, côté quai
		Panel = { X = -half - 0.6, Y = F + 4.5, Z = -11 }, -- boîtier électronique
		Safe = { X = -2.6, Y = F + 4, Z = 0 }, -- coffre au fond (porte ouverte)
		Bags = { { X = -1.5, Y = F + 1, Z = -6 }, { X = -1.5, Y = F + 1, Z = 6 }, { X = 1.8, Y = F + 1, Z = -9 }, { X = 1.8, Y = F + 1, Z = 9 } },
		DoorW = 8,
	}
end

-- Point local -> monde (repère ville, y depuis Origin().Y) d'une voiture
function TrainLine.ToWorld(count: number?, t: number, trainIndex: number, carIndex: number, lx: number, ly: number, lz: number): (number, number, number)
	local st = TrainLine.State(count, t, trainIndex)
	local consist = TrainLine.Consist(trainIndex)
	local car = consist[carIndex] or consist[1]
	local x, z, dx, dz = TrainLine.CarPoseAt(count, st.S, car.Offset, car.Len)
	-- droite = look x up = (-dz, 0, dx)
	local rx, rz = -dz, dx
	return x + rx * lx - dx * lz, TrainLine.RAIL_Y + ly, z + rz * lx - dz * lz
end

-- Index de la voiture blindée du convoi
function TrainLine.VaultCarIndex(): number
	for i, kind in ipairs(TrainLine.Trains[1].Cars) do
		if kind == "Vault" then
			return i
		end
	end
	return #TrainLine.Trains[1].Cars
end

-- Sièges occupés par des PNJ (mêmes chez tout le monde ; jamais proposés aux joueurs)
function TrainLine.NpcSeats(trainIndex: number, carIndex: number): { [number]: boolean }
	local set = {}
	local n = #TrainLine.SeatsLocal("Coach")
	local seed = trainIndex * 7 + carIndex * 13
	for k = 1, 3 do
		set[((seed * (k + 3) + k * 5) % n) + 1] = true
	end
	return set
end

----------------------------------------------------------------------
-- CFrame (jeu seulement : serveur / client)
----------------------------------------------------------------------

-- Repère d'une voiture : origine sur le dessus du rail au centre, LookVector = sens de marche
function TrainLine.CarFrame(count: number?, headS: number, offset: number, len: number): CFrame
	local x, z, dx, dz = TrainLine.CarPoseAt(count, headS, offset, len)
	local p = WorldLayout.CityPoint(x, TrainLine.RAIL_Y, z)
	return CFrame.lookAt(p, p + Vector3.new(dx, 0, dz))
end

-- Repères de toutes les voitures d'un train à l'instant t
function TrainLine.CarFrames(count: number?, t: number, trainIndex: number): ({ CFrame }, any)
	local st = TrainLine.State(count, t, trainIndex)
	local list = {}
	for i, car in ipairs((TrainLine.Consist(trainIndex))) do
		list[i] = TrainLine.CarFrame(count, st.S, car.Offset, car.Len)
	end
	return list, st
end

-- Repère local d'un siège (dessus de l'assise, regard = sens du siège)
function TrainLine.SeatCFrame(index: number): CFrame
	local seat = TrainLine.SeatsLocal("Coach")[index]
	if not seat then
		return CFrame.new()
	end
	return CFrame.new(seat.X, seat.Y, seat.Z) * CFrame.Angles(0, seat.Yaw, 0)
end

TrainLine.YawOf = yawOf

return TrainLine
