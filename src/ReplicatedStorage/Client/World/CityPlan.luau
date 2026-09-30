--[[
	CityPlan (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > CityPlan

	🗺️ Dopamine Town (v10, CITY10) : le PLAN d'habillage de la grande ville,
	calculé côté CLIENT à partir du contrat de LAYOUT10 (WorldLayout :
	Districts, RoadGraph, HighwayPath, Facilities...). 0 pièce serveur, 0
	réseau : chaque client calcule exactement la même liste (tout est
	déterministe), et TownStreetLife la construit en flux autour de l'avatar.
	  - AUTOROUTE : tronçons (marquages, séparateur central, glissières,
	    balises), candélabres, portiques avant chaque sortie, panneaux
	    "Sortie à 500 m", limitations, musoirs de sortie, murs antibruit le
	    long des lignes droites, bretelles, habillage des ponts (piles,
	    corniche), aire de repos et belvédères ;
	  - QUARTIERS : panneaux d'entrée (ou portails pour les quartiers
	    fermés), décor entre deux parcelles (haie + lanterne au village,
	    arbre + lampadaire en ville, lampadaire industriel aux lofts, mur de
	    pierre + cyprès ou fontaine sur la colline), repères du quartier et
	    lieux de remplissage dans les zones libres ("Free") ;
	  - CASES NATURE : bois des collines (bosquets, cabanes, prairies), parc
	    des sports (stade, tennis, foot, basket), parc du sud (gare routière,
	    parking, square).
	Aucun emplacement ne chevauche une route, une parcelle, une place de
	chantier, un lieu réservé (WorldLayout.IsFreeAt aux coins), ni un gros
	emplacement déjà publié par le serveur (liste `taken`).

	API (TownStreetLife) :
	  CityPlan.Build(count, taken?) -> { Spot }   Spot = { Kind, CF, Seed,
	      Pos, Size?, Data?, Snap? }  (Snap : recalé au sol par rayon)
	  CityPlan.BUILDERS / BIG / IMPOSTORS : fabriques de tous les kits
	  CityPlan.FOOT : emprises (x, z) des lieux
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local CityKit = require(script.Parent.CityKit)
local TownHighway = require(script.Parent.TownHighway)
local DistrictCottage = require(script.Parent.DistrictCottage)
local DistrictTownhouse = require(script.Parent.DistrictTownhouse)
local DistrictLoft = require(script.Parent.DistrictLoft)
local DistrictMansion = require(script.Parent.DistrictMansion)
local DistrictParks = require(script.Parent.DistrictParks)

local CityPlan = {}

local hash = CityKit.Hash
local WL: any = WorldLayout

----------------------------------------------------------------------
-- Fabriques de tous les kits
----------------------------------------------------------------------

CityPlan.BUILDERS = {}
CityPlan.BIG = {}
CityPlan.IMPOSTORS = {}
CityPlan.FOOT = {
	-- lieux existants de TownDistricts (v9.9) réutilisés comme remplissage
	SkatePark = Vector2.new(38, 28),
	CommunityGarden = Vector2.new(32, 26),
	SportsCorner = Vector2.new(30, 24),
	HwyRest = Vector2.new(50, 36),
}
for _, kit in ipairs({ TownHighway, DistrictCottage, DistrictTownhouse, DistrictLoft, DistrictMansion, DistrictParks } :: { any }) do
	for k, f in pairs(kit.BUILDERS) do
		CityPlan.BUILDERS[k] = f
	end
	for k in pairs(kit.BIG or {}) do
		CityPlan.BIG[k] = true
	end
	for k, f in pairs(kit.IMPOSTORS or {}) do
		CityPlan.IMPOSTORS[k] = f
	end
	for k, v in pairs(kit.FOOT or {}) do
		CityPlan.FOOT[k] = v
	end
end

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

type Spot = { Kind: string, CF: CFrame, Seed: number, Pos: Vector3, Size: Vector3?, Data: any?, Snap: boolean? }

local GROUND = 0.4 -- (WorldLayout.GROUND_Y) dessus des pelouses (repère ville)

local function yawOf(lx: number, lz: number): number
	return math.atan2(-lx, -lz)
end

-- repère monde : point ville (x, y, z), regard (lx, lz)
local function cframe(x: number, y: number, z: number, lx: number, lz: number): CFrame
	return WL.CityCFrame(x, z, yawOf(lx, lz), y)
end

local function add(out: { Spot }, kind: string, cf: CFrame, seed: number, size: Vector3?, data: any?, snap: boolean?)
	table.insert(out, { Kind = kind, CF = cf, Seed = seed, Pos = cf.Position, Size = size, Data = data, Snap = snap })
end

-- Emplacements libres : ni route, ni parcelle, ni lieu réservé, ni gros
-- emplacement déjà pris (serveur ou plan) ; test du centre + 4 coins + 4
-- milieux d'un rectangle (repère ville, orienté par `yaw`)
type Ctx = { Count: number, Taken: { { number } } }

local function rectFree(ctx: Ctx, x: number, z: number, w: number, d: number, ax: number, az: number): boolean
	-- a = axe "largeur" (unitaire), n = axe "profondeur"
	local nx, nz = -az, ax
	local pts = { { 0, 0 }, { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 }, { 0, -0.5 }, { 0, 0.5 }, { -0.5, 0 }, { 0.5, 0 } }
	for _, p in ipairs(pts) do
		local px = x + ax * p[1] * w + nx * p[2] * d
		local pz = z + az * p[1] * w + nz * p[2] * d
		local ok, free = pcall(WL.IsFreeAt, ctx.Count, px, pz, 1)
		if ok and not free then
			return false
		end
	end
	-- cercles déjà pris : distance du cercle au rectangle orienté
	for _, t in ipairs(ctx.Taken) do
		local dx, dz = t[1] - x, t[2] - z
		local la = dx * ax + dz * az
		local ln = dx * nx + dz * nz
		local ca = math.clamp(la, -w / 2, w / 2)
		local cn = math.clamp(ln, -d / 2, d / 2)
		if (la - ca) ^ 2 + (ln - cn) ^ 2 < t[3] * t[3] then
			return false
		end
	end
	return true
end

local function take(ctx: Ctx, x: number, z: number, r: number)
	table.insert(ctx.Taken, { x, z, r })
end

----------------------------------------------------------------------
-- Rangement d'un rectangle libre : lieux (en premier) puis remplissage
----------------------------------------------------------------------

-- côté du rectangle le plus proche d'une route : normale sortante (nx, nz)
local function frontSide(ctx: Ctx, R: any): (number, number)
	local best, bx, bz = math.huge, 0, -1
	for _, s in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		local mx = R.X + s[1] * R.W / 2
		local mz = R.Z + s[2] * R.D / 2
		local ok, _e, _x, _y, _z, dist = pcall(WL.NearestRoad, ctx.Count, mx, mz)
		local dd = ok and type(dist) == "number" and dist or math.huge
		if dd < best - 1e-6 then
			best, bx, bz = dd, s[1], s[2]
		end
	end
	return bx, bz
end

type Pack = { Queue: { string }, Fillers: { string }, Style: string, Seed: number, Hedge: string? }

local GAP = 7

local function packRect(ctx: Ctx, out: { Spot }, R: any, pack: Pack, y: number)
	local nx, nz = frontSide(ctx, R)
	-- axe le long du côté avant : a = (-nz, nx) ; longueurs
	local ax, az = -nz, nx
	local alongLen = math.abs(ax) > 0.5 and R.W or R.D
	local depthLen = math.abs(nx) > 0.5 and R.W or R.D
	local fx, fz = R.X + nx * depthLen / 2, R.Z + nz * depthLen / 2 -- milieu du côté avant
	local rowStart, rowDepth = 3, 0
	local cursor = -alongLen / 2 + 3
	local fillIndex = 0
	local guard = 0
	local function fits(kind: string, w: number, d: number): boolean
		return cursor + w <= alongLen / 2 - 3 and rowStart + d <= depthLen - 3
	end
	while guard < 400 do
		guard += 1
		-- prochain type : lieux de la file, puis remplissage (tourne)
		local kind: string?
		local fromQueue = false
		for i, k in ipairs(pack.Queue) do
			local f = CityPlan.FOOT[k]
			if f and fits(k, f.X, f.Y) then
				kind = k
				table.remove(pack.Queue, i)
				fromQueue = true
				break
			end
		end
		if not kind then
			for tries = 0, #pack.Fillers - 1 do
				local k = pack.Fillers[1 + (fillIndex + tries) % #pack.Fillers]
				local f = CityPlan.FOOT[k]
				if f and fits(k, f.X, f.Y) then
					kind = k
					fillIndex += tries + 1
					break
				end
			end
		end
		if not kind then
			-- rangée suivante (plus loin de la rue), ou fin du rectangle
			if rowDepth <= 0 then
				-- rien ne rentre dans cette rangée
				if cursor > -alongLen / 2 + 3 then
					cursor = alongLen -- force la rangée suivante
				else
					break
				end
			end
			rowStart += rowDepth + GAP
			rowDepth = 0
			cursor = -alongLen / 2 + 3
			if rowStart + 12 > depthLen - 3 then
				break
			end
		else
			local foot = CityPlan.FOOT[kind]
			local w, d = foot.X, foot.Y
			-- centre : côté avant - n * (rowStart + d/2) + a * (cursor + w/2)
			local along = cursor + w / 2
			local depth = rowStart + d / 2
			local cx = fx - nx * depth + ax * along
			local cz = fz - nz * depth + az * along
			if rectFree(ctx, cx, cz, w + 2, d + 2, ax, az) then
				local seed = math.floor(hash(pack.Seed, #out) * 100000)
				add(out, kind, cframe(cx, y, cz, nx, nz), seed, nil, { Style = pack.Style }, true)
				-- (pas de "take" : le rangement ne se chevauche jamais lui-même)
				-- haie / mur le long du devant des champs et bosquets (1re rangée)
				if pack.Hedge and rowStart <= 3 and (kind == "Orchard" or kind == "Meadow" or kind == "Grove") then
					local hx, hz = fx - nx * 1.6 + ax * along, fz - nz * 1.6 + az * along
					add(out, pack.Hedge, cframe(hx, y, hz, nx, nz), seed + 1, Vector3.new(w - 4, 3, 2), nil, true)
				end
				rowDepth = math.max(rowDepth, d)
			elseif fromQueue then
				-- (lieu refusé ici : on le garde pour la suite)
				table.insert(pack.Queue, kind)
			end
			cursor += w + GAP
		end
	end
end

----------------------------------------------------------------------
-- 🛣️ Autoroute
----------------------------------------------------------------------

local HWY = {
	Lanes = 2,
	Lane = 11,
	Median = 8,
	ShL = 1,
	ShR = 2,
}

-- rayon de l'autoroute pour le plan en cours (la ville grandit avec le
-- nombre de parcelles : WorldLayout.HighwayR(count))
local HR = 1110

-- repère d'échangeur (même formule que WorldLayout) : t le long, n vers l'extérieur
local function ixLocal(ix: any, x: number, z: number): (number, number)
	local H = HR
	local cx, cz = ix.NX * H, ix.NZ * H
	local tx, tz = ix.NZ, -ix.NX
	local dx, dz = x - cx, z - cz
	return dx * tx + dz * tz, dx * ix.NX + dz * ix.NZ
end

local function ixPoint(ix: any, t: number, n: number): (number, number)
	local H = HR
	return ix.NX * H + ix.NZ * t + ix.NX * n, ix.NZ * H - ix.NX * t + ix.NZ * n
end

local IX_NAMES = {
	S = { "City centre", "Town gate" },
	E = { "Townhouse Streets", "Loft District" },
	N = { "Mansion Hills", "Sports park" },
	W = { "Cottage Village", "Hill woods" },
}

-- découpe une polyligne en tronçons de `maxLen` au plus
-- -> { {A, B (Vector3 ville), S (abscisse du début), Turn (angle aux joints)} }
local function pieces(points: { any }, closed: boolean, maxLen: number): ({ any }, number)
	local list = {}
	local n = #points
	local last = closed and n or n - 1
	local s = 0
	-- angle de virage à chaque sommet
	local function dir(i: number): Vector3
		local a = points[(i - 1) % n + 1]
		local b = points[i % n + 1]
		local v = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		return v.Magnitude > 1e-6 and v.Unit or Vector3.new(1, 0, 0)
	end
	for i = 1, last do
		local a = points[i]
		local b = points[i % n + 1]
		local A = Vector3.new(a.X, a.Y, a.Z)
		local B = Vector3.new(b.X, b.Y, b.Z)
		local len = (B - A).Magnitude
		if len > 0.5 then
			local k = math.max(1, math.ceil(len / maxLen))
			local turnA, turnB = 0, 0
			if closed or i > 1 then
				turnA = math.acos(math.clamp(dir(i - 1):Dot(dir(i)), -1, 1))
			end
			if closed or i < last then
				turnB = math.acos(math.clamp(dir(i):Dot(dir(i + 1)), -1, 1))
			end
			for j = 0, k - 1 do
				local p0 = A:Lerp(B, j / k)
				local p1 = A:Lerp(B, (j + 1) / k)
				table.insert(list, { A = p0, B = p1, S = s + len * j / k, Turn = math.max(j == 0 and turnA or 0, j == k - 1 and turnB or 0) })
			end
			s += len
		end
	end
	return list, s
end

local function segCF(p: any): CFrame
	local A: Vector3, B: Vector3 = p.A, p.B
	local a = WL.CityPoint(A.X, A.Y, A.Z)
	local b = WL.CityPoint(B.X, B.Y, B.Z)
	return CFrame.lookAt((a + b) / 2, b)
end

local function nearestIx(x: number, z: number): (any, number, number)
	local best, bt, bn, bd = nil, 0, 0, math.huge
	for _, ix in ipairs(WL.INTERCHANGES or {}) do
		local t, n = ixLocal(ix, x, z)
		local d = math.abs(t) + math.abs(n)
		if d < bd then
			best, bt, bn, bd = ix, t, n, d
		end
	end
	return best, bt, bn
end

local function planHighway(ctx: Ctx, out: { Spot })
	if type(WL.HighwayPath) ~= "function" then
		return
	end
	local ok, path = pcall(WL.HighwayPath, ctx.Count)
	if not ok or type(path) ~= "table" or #path < 3 then
		return
	end
	local T = WL.RAMP_T or 380
	local W = TownHighway.Width(HWY)
	local list, total = pieces(path, true, 40)
	local half = W / 2
	for i, p in ipairs(list) do
		local cf = segCF(p)
		local mid = (p.A + p.B) / 2
		local ix, t = nearestIx(mid.X, mid.Z)
		local at = math.abs(t)
		local data = table.clone(HWY)
		data.Deck = false
		data.Par = i % 2
		data.S = p.S
		data.Overlap = p.Turn > 0.01 and half * math.tan(p.Turn / 2) + 0.2 or 0
		-- bretelles (divergents / convergents) : pas de glissière extérieure
		if ix and at > T - 200 and at < T + 10 then
			data.NoRail = true
		end
		add(out, "HwySeg", cf, 1000 + i, Vector3.new(W, 0.5, (p.B - p.A).Magnitude), data)
		-- mur antibruit côté ville, sur les lignes droites loin des échangeurs
		if p.Turn < 0.01 and ix and at > T + 60 then
			local right = cf.RightVector
			local wall = cf * CFrame.new(-(half + 7), 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
			local _ = right
			add(out, "HwyWall", CFrame.new(wall.Position.X, WL.Origin().Y + GROUND, wall.Position.Z) * wall.Rotation, 2000 + i, Vector3.new((p.B - p.A).Magnitude + 0.02, 11, 1), nil)
		end
	end
	-- candélabres sur le terre-plein tous les ~80 studs (loin des ponts)
	local s = 20
	while s < total do
		local x, y, z, dx, dz = WL.PointAlong(path, s)
		local ix, t = nearestIx(x, z)
		if not (ix and math.abs(t) < 40) then
			add(out, "HwyLamp", cframe(x, y, z, dx, dz), math.floor(s), nil, { Reach = 9 })
		end
		s += 80
	end
	-- échangeurs : portiques, panneaux "500 m", limitations, musoirs
	for _, ix in ipairs(WL.INTERCHANGES or {}) do
		local names = IX_NAMES[ix.Id] or { "City centre", "Highway" }
		local tx, tz = ix.NZ, -ix.NX -- sens +t
		-- chaussée extérieure : roule vers +t, sort à t = -T ; intérieure : vers -t, sort à +T
		for _, dirT in ipairs({ 1, -1 }) do
			local exitT = -dirT * T
			local vx, vz = tx * dirT, tz * dirT -- sens de circulation
			-- portique 300 studs avant la sortie
			local gt = exitT - dirT * 300
			local gx, gz = ixPoint(ix, gt, 0)
			add(out, "HwyGantry", cframe(gx, WL.ROAD_Y or 0.5, gz, vx, vz), 3000 + gt, nil, {
				W = W,
				Side = "Right",
				Signs = {
					{ Text = Locale.T("Exit") .. " " .. ix.Id .. " · " .. Locale.T(names[1]), Arrow = "Exit", Green = false },
					{ Text = Locale.T("Ring road"), Arrow = "Up", Green = true },
				},
			})
			-- panneau "Sortie à 500 m" (accotement droit)
			local st = exitT - dirT * 520
			local rn = -dirT * (half + 4) -- côté droit de la circulation : n = -dirT * ...
			-- (droite du sens +t = +n (extérieur) ; droite du sens -t = -n)
			rn = dirT * (half + 4)
			local sx, sz = ixPoint(ix, st, rn)
			add(out, "HwySign", cframe(sx, GROUND, sz, vx, vz), 3100 + st, nil, { Kind = "Exit", Text = "↗ " .. Locale.T("Exit") .. " " .. ix.Id .. " · 500 m\n" .. Locale.T(names[1]) .. " · " .. Locale.T(names[2]), W = 14 }, true)
			-- limitation après le convergent (sortie + entrée au même échangeur)
			local lt = -exitT + dirT * 60
			local lx, lz = ixPoint(ix, lt, rn)
			add(out, "HwySign", cframe(lx, GROUND, lz, vx, vz), 3200 + lt, nil, { Kind = "Speed", Limit = 110 }, true)
		end
	end
	-- bretelles : tronçons, musoirs de sortie
	local okG, graph = pcall(WL.RoadGraph, ctx.Count)
	if okG and type(graph) == "table" then
		for ei, e in ipairs(graph.Edges) do
			if e.Ramp and e.Points and #e.Points >= 2 then
				local rl = pieces(e.Points, false, 26)
				for j, p in ipairs(rl) do
					local mid = (p.A + p.B) / 2
					local _ix, _t, n = nearestIx(mid.X, mid.Z)
					-- (dalles des bretelles à +0,06 / +0,09 : peinture 0,06 plus haut
					-- que celle de l'autoroute, jamais confondue au convergent)
					local data = { Oneway = true, Lanes = 1, Lane = 8, ShL = 1, ShR = 3, Deck = false, Par = j % 2, S = p.S, PaintY = 0.06 }
					data.Overlap = p.Turn > 0.01 and 6 * math.tan(p.Turn / 2) + 0.2 or 0
					if math.abs(n) < half + 9 then
						data.NoRail = true
					end
					add(out, "HwyRamp", segCF(p), 4000 + ei * 50 + j, Vector3.new(12, 0.5, (p.B - p.A).Magnitude), data)
				end
				-- musoir : sortie = la bretelle part de l'autoroute (A = nœud "Highway")
				local na = graph.Nodes[e.A]
				if na and na.Kind == "Highway" then
					-- point de la bretelle à ~8 studs du bord de la chaussée
					local sAlong = 0
					for step = 0, 60 do
						local x, _y, z = WL.PointAlong(e.Points, step * 4)
						local _i, _t, n = nearestIx(x, z)
						if math.abs(n) > half + 7 then
							sAlong = step * 4
							break
						end
					end
					if sAlong > 0 then
						local x, y, z, dx, dz = WL.PointAlong(e.Points, sAlong)
						-- nez du musoir : entre la bretelle et la chaussée (vers l'axe)
						local _i, _t, n = nearestIx(x, z)
						local ix = _i
						local px, pz = x, z
						if ix then
							local toward = n > 0 and -1 or 1
							px, pz = x + ix.NX * toward * 6.5, z + ix.NZ * toward * 6.5
						end
						add(out, "HwyExit", cframe(px, y, pz, dx, dz), 4900 + ei, nil, { Number = ix and ix.Id or nil })
					end
				end
			end
		end
		-- ponts : habillage du tablier du serveur (corniche, garde-corps
		-- anti-jets, candélabres) et piles des rampes d'approche (le serveur
		-- pose déjà la pile centrale et les 2 culées à n = ±36,4)
		for ei, e in ipairs(graph.Edges) do
			if e.Bridge and e.Points and #e.Points >= 2 then
				local base = WL.ROAD_Y or 0.5
				local bl = pieces(e.Points, false, 26)
				for j, p in ipairs(bl) do
					local mid = (p.A + p.B) / 2
					if mid.Y - base > 1.5 then
						local _ix, _t, n = nearestIx(mid.X, mid.Z)
						local elev = mid.Y - base
						add(out, "BridgeSeg", segCF(p), 5000 + ei * 60 + j, Vector3.new(26, 1.2, (p.B - p.A).Magnitude), {
							Elev = elev,
							-- piles sous les rampes d'approche (hors culées)
							Pier = math.abs(n) > 40 and elev > 3.5 and j % 2 == 0,
							Lamp = j % 3 == 0,
							Ground = WL.Origin().Y + GROUND,
							Par = j % 2,
						})
					end
				end
			end
		end
	end
	-- aire de repos, belvédères
	for _, zone in ipairs(WL.Facilities(ctx.Count)) do
		if zone.Id == "RestArea" then
			add(out, "HwyRest", WL.ZoneCFrame(zone) * CFrame.new(0, GROUND, 0), 6001, nil, nil, true)
			take(ctx, zone.X, zone.Z, 36)
		elseif string.sub(zone.Id, 1, 8) == "Lookout_" then
			add(out, "Lookout", WL.ZoneCFrame(zone) * CFrame.new(0, GROUND, 0), 6002 + #out, nil, nil, true)
			take(ctx, zone.X, zone.Z, 30)
		end
	end
end

----------------------------------------------------------------------
-- 🏘️ Quartiers
----------------------------------------------------------------------

local THEME = {
	Cottage = {
		Queue = { "CtgChapel", "CtgBakery", "CtgPond", "CtgGreen", "CtgWell", "CommunityGarden" },
		Fillers = { "Orchard", "Meadow", "Grove", "CtgGreen", "Meadow", "Orchard", "PocketPark", "Grove" },
		Hedge = "CtgHedge",
	},
	Townhouse = {
		Queue = { "TwnSquare", "TwnCafe", "TwnCornerShop", "ShopRow", "TwnBikes", "TwnBusStop", "BasketCourt" },
		Fillers = { "PocketPark", "TwnCafe", "ParkingLot", "TwnSquare", "ShopRow", "BasketCourt", "TwnCornerShop", "Grove" },
	},
	Loft = {
		Queue = { "LftWarehouse", "LftFoodTrucks", "LftMural", "SkatePark", "LftContainers", "LftWarehouse" },
		Fillers = { "LftWarehouse", "ParkingLot", "LftContainers", "BasketCourt", "LftMural", "LftWarehouse", "Grove" },
	},
	Mansion = {
		Queue = { "MnsFountain", "MnsViewpoint", "MnsTopiary", "MnsFountain", "MnsTopiary" },
		Fillers = { "Grove", "MnsFountain", "Meadow", "Orchard", "Grove", "PocketPark" },
		Hedge = "MnsWall",
	},
	Mixed = {
		Queue = { "PocketPark", "ShopRow", "SportsCorner", "BasketCourt", "CommunityGarden", "FootPitch" },
		Fillers = { "PocketPark", "Grove", "ParkingLot", "Meadow", "BasketCourt", "ShopRow", "TwnSquare" },
	},
}

-- décor entre deux parcelles voisines d'une rangée (ou au bout de la rangée)
local function gapItems(ctx: Ctx, out: { Spot }, d: any, style: string, px: number, pz: number, lx: number, lz: number, y: number, side: number, idx: number)
	local W, D = WL.PLOT_W, WL.PLOT_D
	local gap = style == "Mansion" and (WL.MANSION_GAP or 64) or (WL.PLOT_GAP or 12)
	-- a = axe de la rangée (perpendiculaire au regard)
	local ax, az = -lz, lx
	local gx = px + ax * side * (W / 2 + gap / 2)
	local gz = pz + az * side * (W / 2 + gap / 2)
	-- avant de la rangée (côté rue)
	local fx, fz = gx + lx * (D / 2 - 3), gz + lz * (D / 2 - 3)
	local seed = idx * 7 + (side > 0 and 1 or 0)
	local function free(x: number, z: number, r: number): boolean
		local ok, f = pcall(WL.IsFreeAt, ctx.Count, x, z, r)
		return not ok or f
	end
	if not free(fx, fz, 1) then
		return
	end
	if style == "Cottage" then
		add(out, "CtgLantern", cframe(fx, y, fz, lx, lz), seed, nil, nil, true)
		-- haie mitoyenne (le long de la profondeur), du devant au fond
		local hx, hz = gx - lx * 3, gz - lz * 3
		if free(hx, hz, 1) then
			add(out, "CtgHedge", cframe(hx, y, hz, ax, az), seed + 1, Vector3.new(D - 16, 3, 2), nil, true)
		end
		add(out, "CtgFlowers", cframe(fx - ax * side * 3, y, fz - az * side * 3, lx, lz), seed + 2, nil, nil, true)
	elseif style == "Townhouse" or style == "Mixed" then
		add(out, "TwnTree", cframe(fx, y, fz, lx, lz), seed, nil, nil, true)
		local bx, bz = gx - lx * 10, gz - lz * 10
		if free(bx, bz, 1) then
			add(out, "TwnLamp", cframe(bx, y, bz, lx, lz), seed + 1, nil, nil, true)
		end
	elseif style == "Loft" then
		add(out, "LftLamp", cframe(fx, y, fz, lx, lz), seed, nil, nil, true)
		local hx, hz = gx - lx * 4, gz - lz * 4
		if free(hx, hz, 1) then
			add(out, "LftFence", cframe(hx, y, hz, ax, az), seed + 1, Vector3.new(D - 12, 7, 1), nil, true)
		end
	elseif style == "Mansion" then
		-- mur de pierre au milieu de l'intervalle, cyprès de part et d'autre
		local wx, wz = gx - lx * 2, gz - lz * 2
		if idx % 2 == 0 then
			add(out, "MnsWall", cframe(wx, y, wz, ax, az), seed, Vector3.new(D - 8, 5, 2), nil, true)
			for _, o in ipairs({ -7, 7 }) do
				add(out, "MnsCypress", cframe(wx + ax * o, y, wz + az * o, ax, az), seed + o, Vector3.new(D - 16, 15, 3), nil, true)
			end
		else
			-- fontaine sur le devant, cyprès au fond
			local cx, cz = gx + lx * (D / 2 - 24), gz + lz * (D / 2 - 24)
			if free(cx, cz, 18) then
				add(out, "MnsFountain", cframe(cx, y, cz, lx, lz), seed, nil, nil, true)
			end
			local bx, bz = gx - lx * (D / 2 - 8), gz - lz * (D / 2 - 8)
			add(out, "MnsCypress", cframe(bx, y, bz, lx, lz), seed + 3, Vector3.new(gap - 16, 15, 3), nil, true)
		end
		add(out, "MnsLantern", cframe(fx, y, fz, lx, lz), seed + 5, nil, nil, true)
	end
end

local function planDistricts(ctx: Ctx, out: { Spot })
	if type(WL.Districts) ~= "function" then
		return
	end
	local ok, districts = pcall(WL.Districts, ctx.Count)
	if not ok or type(districts) ~= "table" then
		return
	end
	local sh = WL.STREET_HALF or 14
	for di, d in ipairs(districts) do
		local style = d.Style
		local y = (d.Rise or 0) + GROUND
		-- panneaux d'entrée / portails
		if d.Gated and d.Gates and #d.Gates > 0 then
			for gi, g in ipairs(d.Gates) do
				local cf = WL.CityCFrame(g.X, g.Z, g.Yaw, y)
				add(out, "MnsGate", cf, di * 100 + gi, nil, nil, true)
				take(ctx, g.X, g.Z, 26)
			end
		else
			for si, st in ipairs(d.Streets or {}) do
				local dx, dz = st.X1 - st.X0, st.Z1 - st.Z0
				local len = math.sqrt(dx * dx + dz * dz)
				if len > 1 then
					local ux, uz = dx / len, dz / len
					for _, e in ipairs({ { st.X0, st.Z0, 1 }, { st.X1, st.Z1, -1 } }) do
						-- juste à l'intérieur de la case, à droite de la rue en entrant
						local inx, inz = ux * e[3], uz * e[3]
						local rx, rz = -inz, inx -- droite en entrant (regard (inx, inz) x haut)
						local sx = e[1] + inx * ((WL.GRID_HALF or 16) + 6) + rx * (sh + 2.5)
						local sz = e[2] + inz * ((WL.GRID_HALF or 16) + 6) + rz * (sh + 2.5)
						local okF, f = pcall(WL.IsFreeAt, ctx.Count, sx, sz, 2)
						if not okF or f then
							-- panneau face aux arrivants (regard vers l'avenue)
							take(ctx, sx, sz, 6)
							add(out, "DistrictSign", cframe(sx, y, sz, -inx, -inz), di * 100 + si * 2 + (e[3] > 0 and 0 or 1), nil, { Style = style, Text = (d.Emoji or "") .. " " .. Locale.T(d.Name or style) }, true)
						end
					end
				end
			end
		end
		-- décor entre les parcelles (parcelles + places vides d'une rangée)
		local members = {}
		for _, idx in ipairs(d.Plots or {}) do
			local okP, p = pcall(WL.PlotPlaceData, idx, ctx.Count)
			if okP and p then
				table.insert(members, { X = p.X, Z = p.Z, Y = p.Y or 0, LookX = p.LookX, LookZ = p.LookZ })
			end
		end
		for _, lot in ipairs(d.Lots or {}) do
			table.insert(members, { X = lot.X, Z = lot.Z, Y = lot.Y or 0, LookX = lot.LookX, LookZ = lot.LookZ })
		end
		local seen = {}
		for mi, p in ipairs(members) do
			for _, side in ipairs({ -1, 1 }) do
				local W = WL.PLOT_W
				local gap = style == "Mansion" and (WL.MANSION_GAP or 64) or (WL.PLOT_GAP or 12)
				local ax, az = -p.LookZ, p.LookX
				local gx = p.X + ax * side * (W / 2 + gap / 2)
				local gz = p.Z + az * side * (W / 2 + gap / 2)
				local key = math.floor(gx + 0.5) .. "_" .. math.floor(gz + 0.5)
				if not seen[key] then
					seen[key] = true
					gapItems(ctx, out, d, style, p.X, p.Z, p.LookX, p.LookZ, (p.Y or 0) + GROUND, side, di * 1000 + mi * 2 + (side > 0 and 1 or 0))
				end
			end
		end
		-- zones libres : repères du quartier, puis remplissage
		local theme = THEME[style] or THEME.Mixed
		local pack: Pack = { Queue = table.clone(theme.Queue), Fillers = theme.Fillers, Style = style, Seed = di * 7919, Hedge = theme.Hedge }
		-- (les plus grands rectangles d'abord : les repères y tiennent)
		local rects = table.clone(d.Free or {})
		table.sort(rects, function(a, b)
			return a.W * a.D > b.W * b.D
		end)
		for _, R in ipairs(rects) do
			packRect(ctx, out, R, pack, (R.Y or 0) + GROUND)
		end
		-- lofts : voie ferrée le long du fond du plus grand rectangle libre
		if style == "Loft" and rects[1] and rects[1].W > 120 then
			local R = rects[1]
			y = (R.Y or 0) + GROUND
			local nx, nz = frontSide(ctx, R)
			local ax, az = -nz, nx
			local alongLen = math.abs(ax) > 0.5 and R.W or R.D
			local depthLen = math.abs(nx) > 0.5 and R.W or R.D
			local bx, bz = R.X - nx * (depthLen / 2 - 5), R.Z - nz * (depthLen / 2 - 5)
			local n = math.max(1, math.floor((alongLen - 10) / 40))
			local L = (alongLen - 10) / n
			local okRail = true
			for k = 0, n - 1 do
				local along = -alongLen / 2 + 5 + (k + 0.5) * L
				local cx, cz = bx + ax * along, bz + az * along
				if rectFree(ctx, cx, cz, L, 8, ax, az) then
					add(out, "LftRail", cframe(cx, y, cz, nx, nz) * CFrame.Angles(0, 0, 0), 7000 + k, Vector3.new(L + 0.02, 1, 8), nil, true)
				else
					okRail = false
				end
			end
			if okRail and n >= 2 then
				local cx, cz = bx + ax * (-alongLen / 2 + 5 + L), bz + az * (-alongLen / 2 + 5 + L)
				add(out, "LftWagon", cframe(cx, y, cz, nx, nz), 7100, nil, nil, true)
			end
		end
	end
end

----------------------------------------------------------------------
-- 🛣️ Marquages des rues (hors autoroute, bretelles et boulevard du centre)
----------------------------------------------------------------------

local function planRoads(ctx: Ctx, out: { Spot })
	local ok, graph = pcall(WL.RoadGraph, ctx.Count)
	if not ok or type(graph) ~= "table" then
		return
	end
	local degree: { [string]: number } = {}
	for _, e in ipairs(graph.Edges) do
		degree[e.A] = (degree[e.A] or 0) + 1
		degree[e.B] = (degree[e.B] or 0) + 1
	end
	local B = (WL.DOWNTOWN_B or 250) + 1
	local function inside(p: any): boolean
		return math.abs(p.X) <= B and math.abs(p.Z) <= B
	end
	local clearJ = (WL.GRID_HALF or 16) + 9 -- au-delà du passage piéton (18,5..23,5)
	for ei, e in ipairs(graph.Edges) do
		if not e.Highway and not e.Ramp and e.Points and #e.Points >= 2 then
			local pa, pb = e.Points[1], e.Points[#e.Points]
			if not (inside(pa) and inside(pb)) then
				local function clear(id: string): number
					local node = graph.Nodes[id]
					if not node then
						return 0
					end
					if node.Kind == "Junction" or (degree[id] or 0) >= 3 then
						return clearJ
					elseif node.Kind == "Roundabout" then
						return 4
					end
					return 0
				end
				local list, len = pieces(e.Points, false, 40)
				local cA, cB = clear(e.A), clear(e.B)
				local fast = e.Kind == "Belt" or e.Kind == "Connector" or e.Kind == "Outside"
				for j, p in ipairs(list) do
					add(out, "RoadMarks", segCF(p), 8000 + ei * 40 + j, Vector3.new(e.Width, 0.2, (p.B - p.A).Magnitude), {
						Width = e.Width,
						S = p.S,
						Len = len,
						ClearA = cA,
						ClearB = cB,
						StopA = cA >= clearJ,
						StopB = cB >= clearJ,
						OneWay = e.OneWay,
						Dash = fast and 9 or 6,
						Gap = fast and 15 or 8,
					})
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- 🌳 Cases nature
----------------------------------------------------------------------

local NATURE = {
	HillWoods = { Queue = { "Cabin", "Meadow", "Cabin", "Meadow" }, Fillers = { "Grove", "Grove", "Grove", "Meadow", "Grove", "Grove" } },
	SportsPark = { Queue = { "Stadium", "Tennis", "FootPitch", "BasketCourt", "ParkingLot", "SkatePark", "SportsCorner", "FootPitch" }, Fillers = { "PocketPark", "Grove", "BasketCourt", "Tennis", "Meadow" } },
	SouthPark = { Queue = { "BusStation", "ParkingLot", "PocketPark", "CommunityGarden" }, Fillers = { "PocketPark", "Grove", "Meadow", "ParkingLot" } },
}

local function planNature(ctx: Ctx, out: { Spot })
	if type(WL.Facilities) ~= "function" then
		return
	end
	local ok, zones = pcall(WL.Facilities, ctx.Count)
	if not ok or type(zones) ~= "table" then
		return
	end
	for zi, zone in ipairs(zones) do
		local theme = NATURE[zone.Id]
		if theme then
			local pack: Pack = { Queue = table.clone(theme.Queue), Fillers = theme.Fillers, Style = "Nature", Seed = zi * 104729 }
			-- (Yaw = 0 pour ces zones : rectangle aligné sur les axes)
			packRect(ctx, out, { X = zone.X, Z = zone.Z, W = zone.W - 8, D = zone.D - 8 }, pack, (zone.Y or 0) + GROUND)
		end
	end
end

----------------------------------------------------------------------
-- Plan complet
----------------------------------------------------------------------

local cache: { [string]: { Spot } } = {}

-- taken : { {x, z, r} } (repère ville) déjà occupés (gros emplacements du serveur)
function CityPlan.Build(count: number, taken: { { number } }?): { Spot }
	local n = count
	if type(WL.PlotCount) == "function" then
		n = WL.PlotCount(count)
	end
	local key = n .. "_" .. (taken and #taken or 0)
	if cache[key] then
		return cache[key]
	end
	local ctx: Ctx = { Count = n, Taken = table.clone(taken or {}) }
	local out: { Spot } = {}
	if type(WL.Districts) ~= "function" or type(WL.CityCFrame) ~= "function" then
		return out -- (ancienne ville en anneau : rien à habiller ici)
	end
	HR = type(WL.HighwayR) == "function" and WL.HighwayR(n) or (WL.HIGHWAY_R or 1110)
	local okH, errH = pcall(planHighway, ctx, out)
	if not okH then
		warn("[CityPlan] autoroute : " .. tostring(errH))
	end
	local okD, errD = pcall(planDistricts, ctx, out)
	if not okD then
		warn("[CityPlan] quartiers : " .. tostring(errD))
	end
	local okN, errN = pcall(planNature, ctx, out)
	if not okN then
		warn("[CityPlan] nature : " .. tostring(errN))
	end
	local okR, errR = pcall(planRoads, ctx, out)
	if not okR then
		warn("[CityPlan] marquages : " .. tostring(errR))
	end
	cache[key] = out
	return out
end

-- Point monde -> repère ville (x, z)
function CityPlan.ToCity(p: Vector3): (number, number)
	local o = WL.Origin()
	return p.X - o.X, p.Z - o.Z
end

return CityPlan
