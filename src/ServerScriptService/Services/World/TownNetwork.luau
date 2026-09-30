--[[
	TownNetwork (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownNetwork

	🛣️ (v10, LAYOUT10) Le RÉSEAU ROUTIER de la grande ville, côté SERVEUR :
	uniquement les coques PHYSIQUES (on roule / on marche dessus), en peu de
	pièces, construites une fois depuis WorldLayout.RoadGraph :
	  - avenues, ceinture, rues des quartiers, route de l'entrée, rue du
	    marché : chaussée (Asphalt) + trottoirs surélevés (dessus WALK_Y) ;
	    un carré d'asphalte à chaque carrefour, des coins de trottoir, et le
	    trottoir continue devant les carrefours en T ;
	  - AUTOROUTE (anneau, 2 x 2 voies, HIGHWAY_W) : dalles le long de l'axe
	    (virages en cordes qui se chevauchent, hauteurs alternées de 0,03
	    pour éviter tout z-fight) ;
	  - bretelles (1 voie, 0,06 au-dessus : raccord sans marche sensible) ;
	  - 4 PONTS des échangeurs : tablier qui suit WorldLayout.BridgeProfile
	    (mêmes stations que le graphe : les voitures de la circulation roulent
	    dessus), garde-corps sur la partie haute, culées + pile centrale ;
	  - ronds-points au bout des routes extérieures (aire de repos / belvédères) ;
	  - PLATEAU de la colline des manoirs (WorldLayout District.Plateau).
	Les rues du centre-ville (avenue "rambla", rues latérales) restent celles
	de TownStreets (arêtes "Downtown" : sautées ici).
	Tout le détail visuel est CÔTÉ CLIENT : ici on publie seulement les
	emplacements TownKit.LifeSpot "RoadSurface" / "CurbLine" / "Pavers"
	(tronçons de 40 studs, format de TownRoads, CITY) et "Zebra" (passages
	piétons de WorldLayout.RoadGraph.Crossings). Marquages, glissières,
	lampadaires, portiques, murs antibruit, piles décorées : CITY10.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)

local TownNetwork = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part

local ROAD_Y = WorldLayout.ROAD_Y
local WALK_Y = WorldLayout.WALK_Y
local GROUND_Y = WorldLayout.GROUND_Y
local ROAD_T = 0.7 -- épaisseur de la chaussée (comme TownStreets)
local WALK_T = 1.3 -- épaisseur des trottoirs
local CHUNK = 40
local CURB_H = WALK_Y + 0.03 - ROAD_Y

-- Demi-largeurs RÉELLES des rues du centre-ville (TownStreets) : avenue
-- "rambla" (voies jusqu'à 15) et rues latérales (8)
local DOWNTOWN_HALF_AVENUE = 15
local DOWNTOWN_HALF_STREET = 8

type Node = WorldLayout.RoadNode
type Edge = WorldLayout.RoadEdge

-- Bras d'un carrefour : direction (unité, à plat) depuis le nœud, demi-largeur, trottoir
type Arm = { Edge: Edge, DX: number, DZ: number, Half: number, Walk: number, Special: boolean }

local function flatDir(a: WorldLayout.RoadPoint, b: WorldLayout.RoadPoint): (number, number, number)
	local dx, dz = b.X - a.X, b.Z - a.Z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return 0, -1, 0
	end
	return dx / len, dz / len, len
end

local function isDowntown(e: Edge): boolean
	return e.Kind == "Downtown"
end

-- Demi-largeur physique d'une arête (rues du centre-ville : TownStreets)
local function halfOf(e: Edge): number
	if e.Kind == "Downtown" then
		local p1, p2 = e.Points[1], e.Points[#e.Points]
		-- (avenue d'entrée sur l'axe x = 0 ; rues latérales sur z = 0)
		if math.abs(p1.X) < 1 and math.abs(p2.X) < 1 then
			return DOWNTOWN_HALF_AVENUE
		end
		return DOWNTOWN_HALF_STREET
	end
	return e.Width / 2
end

-- Repère au sol au point `p` (repère ville), X le long de (dx, dz)
local function alongFrame(p: WorldLayout.RoadPoint, dx: number, dz: number, y: number?): CFrame
	local base = WorldLayout.CityPoint(p.X, y or 0, p.Z)
	return CFrame.lookAt(base, base + Vector3.new(dz, 0, -dx))
end

-- Tronçons client (TownRoads) : un emplacement `kind` tous les <= 40 studs
local function chunks(kind: string, F: CFrame, x0: number, x1: number, y: number, z: number, sy: number, sz: number, seed: number, turn: boolean?)
	local len = x1 - x0
	if len <= 1 then
		return
	end
	local n = math.max(1, math.ceil(len / CHUNK))
	for i = 0, n - 1 do
		local a = x0 + i * len / n
		local cf = F * CFrame.new(a + len / n / 2, y, z)
		if turn then
			cf = cf * CFrame.Angles(0, math.pi, 0)
		end
		TownKit.LifeSpot(kind, cf, seed + i * 7, Vector3.new(len / n, sy, sz))
	end
end

-- Dalle entre deux points (repère ville), dessus à la hauteur des points
-- + `lift`, largeur `w`, épaisseur `t` ; `ext0` / `ext1` : allongement aux bouts
local function slab(parent: Instance, name: string, a: WorldLayout.RoadPoint, b: WorldLayout.RoadPoint, w: number, t: number, lift: number, color: Color3, material: Enum.Material, profile: string, ext0: number?, ext1: number?): BasePart?
	local pa = WorldLayout.CityPoint(a.X, a.Y + lift, a.Z)
	local pb = WorldLayout.CityPoint(b.X, b.Y + lift, b.Z)
	local d = pb - pa
	local len = d.Magnitude
	if len < 0.2 then
		return nil
	end
	local u = d / len
	local e0, e1 = ext0 or 0, ext1 or 0
	pa -= u * e0
	pb += u * e1
	local mid = (pa + pb) / 2
	-- repère : -Z le long de la route, Y ~ vers le haut (perpendiculaire à la pente)
	local look = CFrame.lookAt(mid, pb)
	local up = look.UpVector
	local center = mid - up * (t / 2)
	return part(parent, name, Vector3.new(w, t, len + e0 + e1), CFrame.lookAt(center, center + look.LookVector, up), color, material, profile)
end

-- Point décalé latéralement (à droite du sens a -> b) de `off`
local function offsetPoint(p: WorldLayout.RoadPoint, dx: number, dz: number, off: number): WorldLayout.RoadPoint
	-- droite de (dx, dz) = (-dz, dx)
	return { X = p.X - dz * off, Y = p.Y, Z = p.Z + dx * off }
end

-- Polyligne coupée : garde la partie entre les abscisses s0 et s1 (à plat)
local function trimPolyline(points: { WorldLayout.RoadPoint }, s0: number, s1: number): { WorldLayout.RoadPoint }
	local out: { WorldLayout.RoadPoint } = {}
	local acc = 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local _, _, len = flatDir(a, b)
		local segA, segB = acc, acc + len
		if segB > s0 and segA < s1 and len > 1e-6 then
			local t0 = math.clamp((s0 - segA) / len, 0, 1)
			local t1 = math.clamp((s1 - segA) / len, 0, 1)
			local function lerp(t: number): WorldLayout.RoadPoint
				return { X = a.X + (b.X - a.X) * t, Y = a.Y + (b.Y - a.Y) * t, Z = a.Z + (b.Z - a.Z) * t }
			end
			if #out == 0 then
				table.insert(out, lerp(t0))
			end
			table.insert(out, lerp(t1))
		end
		acc = segB
	end
	return out
end

local function flatLength(points: { WorldLayout.RoadPoint }): number
	local len = 0
	for i = 2, #points do
		local _, _, l = flatDir(points[i - 1], points[i])
		len += l
	end
	return len
end

----------------------------------------------------------------------
-- Carrefours
----------------------------------------------------------------------

type Box = { HX: number, HZ: number, Walk: number, Arms: { Arm }, NoWalk: boolean, Build: boolean }

local function armsOf(graph: WorldLayout.RoadGraph): { [string]: { Arm } }
	local arms: { [string]: { Arm } } = {}
	for _, e in ipairs(graph.Edges) do
		if not e.Highway and e.Kind ~= "Roundabout" then
			for _, endId in ipairs({ e.A, e.B }) do
				local pts = WorldLayout.EdgePoints(e, endId)
				local dx, dz = flatDir(pts[1], pts[2])
				arms[endId] = arms[endId] or {}
				table.insert(arms[endId], {
					Edge = e,
					DX = dx,
					DZ = dz,
					Half = halfOf(e),
					Walk = e.Sidewalk,
					Special = e.Ramp or e.Bridge,
				})
			end
		end
	end
	return arms
end

local function boxOf(node: Node, arms: { Arm }): Box
	local hx, hz, walk = 0, 0, 0
	local noWalk = false
	local build = false
	for _, arm in ipairs(arms) do
		-- (nœuds de l'autoroute : seulement des bretelles -> pas de carré)
		if arm.Edge.Kind ~= "Downtown" and not arm.Special then
			build = true
		end
		if arm.Special then
			noWalk = true
		elseif math.abs(arm.DZ) >= math.abs(arm.DX) then
			hx = math.max(hx, arm.Half) -- (bras nord-sud : largeur en x)
		else
			hz = math.max(hz, arm.Half)
		end
		walk = math.max(walk, arm.Walk)
	end
	if hx == 0 then
		hx = hz
	end
	if hz == 0 then
		hz = hx
	end
	return { HX = hx, HZ = hz, Walk = walk, Arms = arms, NoWalk = noWalk, Build = build and #arms >= 2 }
end

-- Longueur à retirer au bout d'une arête qui arrive dans le carré du carrefour
local function trimFor(box: Box?, arm: Arm): number
	if not box or not box.Build then
		return 0
	end
	if math.abs(arm.DZ) >= math.abs(arm.DX) then
		return box.HZ
	end
	return box.HX
end

local function buildJunction(parent: Instance, node: Node, box: Box)
	local cx, cz = node.X, node.Z
	local y = node.Y
	-- carré d'asphalte
	local p = WorldLayout.CityPoint(cx, y - ROAD_T / 2, cz)
	part(parent, "Junction", Vector3.new(2 * box.HX, ROAD_T, 2 * box.HZ), CFrame.new(p), C.Asphalt, M.Asphalt, "solid")
	if box.NoWalk or box.Walk <= 0 then
		return
	end
	local w = box.Walk
	local wy = y - ROAD_Y + WALK_Y
	-- coins de trottoir
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local q = WorldLayout.CityPoint(cx + sx * (box.HX + w / 2), wy - WALK_T / 2, cz + sz * (box.HZ + w / 2))
			part(parent, "WalkCorner", Vector3.new(w, WALK_T, w), CFrame.new(q), C.Walk, M.Pavement, "solid")
		end
	end
	-- côtés sans bras : le trottoir continue devant le carrefour
	local has = { N = false, S = false, E = false, W = false }
	for _, arm in ipairs(box.Arms) do
		if math.abs(arm.DZ) >= math.abs(arm.DX) then
			if arm.DZ > 0 then
				has.S = true
			else
				has.N = true
			end
		else
			if arm.DX > 0 then
				has.E = true
			else
				has.W = true
			end
		end
	end
	if not has.S then
		part(parent, "WalkSide", Vector3.new(2 * box.HX, WALK_T, w), CFrame.new(WorldLayout.CityPoint(cx, wy - WALK_T / 2, cz + box.HZ + w / 2)), C.Walk, M.Pavement, "solid")
	end
	if not has.N then
		part(parent, "WalkSide", Vector3.new(2 * box.HX, WALK_T, w), CFrame.new(WorldLayout.CityPoint(cx, wy - WALK_T / 2, cz - box.HZ - w / 2)), C.Walk, M.Pavement, "solid")
	end
	if not has.E then
		part(parent, "WalkSide", Vector3.new(w, WALK_T, 2 * box.HZ), CFrame.new(WorldLayout.CityPoint(cx + box.HX + w / 2, wy - WALK_T / 2, cz)), C.Walk, M.Pavement, "solid")
	end
	if not has.W then
		part(parent, "WalkSide", Vector3.new(w, WALK_T, 2 * box.HZ), CFrame.new(WorldLayout.CityPoint(cx - box.HX - w / 2, wy - WALK_T / 2, cz)), C.Walk, M.Pavement, "solid")
	end
end

----------------------------------------------------------------------
-- Routes de la ville
----------------------------------------------------------------------

local graphNodes: { [string]: Node } = {}

local function buildCityEdge(parent: Instance, e: Edge, boxes: { [string]: Box }, arms: { [string]: { Arm } }, seed: number)
	local pts = e.Points
	local total = flatLength(pts)
	local armA, armB
	for _, arm in ipairs(arms[e.A] or {}) do
		if arm.Edge == e then
			armA = arm
		end
	end
	for _, arm in ipairs(arms[e.B] or {}) do
		if arm.Edge == e then
			armB = arm
		end
	end
	local s0 = armA and trimFor(boxes[e.A], armA) or 0
	local s1 = total - (armB and trimFor(boxes[e.B], armB) or 0)
	if s1 - s0 < 0.5 then
		return
	end
	local road = trimPolyline(pts, s0, s1)
	local half = e.Width / 2
	for i = 2, #road do
		slab(parent, "Asphalt", road[i - 1], road[i], e.Width, ROAD_T, 0, C.Asphalt, M.Asphalt, "solid")
	end
	-- trottoirs (raccourcis près des échangeurs : les bretelles arrivent au carrefour)
	local w = e.Sidewalk
	if w > 0 and not e.Bridge then
		-- (bretelles au carrefour, anneau d'un rond-point : trottoir arrêté avant)
		local function stop(id: string): number
			local node = graphNodes[id]
			if (boxes[id] and boxes[id].NoWalk) or (node and node.Kind == "Roundabout") then
				return 40
			end
			return 0
		end
		-- (coins de trottoir du carrefour : w x w au-delà du carré)
		local function corner(id: string): number
			local b = boxes[id]
			return (b and b.Build and not b.NoWalk and b.Walk > 0) and b.Walk or 0
		end
		local k0 = s0 + math.max(stop(e.A), corner(e.A))
		local k1 = s1 - math.max(stop(e.B), corner(e.B))
		if k1 - k0 > 1 then
			local walkPts = trimPolyline(pts, k0, k1)
			for i = 2, #walkPts do
				local a, b = walkPts[i - 1], walkPts[i]
				local dx, dz = flatDir(a, b)
				for _, side in ipairs({ -1, 1 }) do
					local off = side * (half + w / 2)
					slab(parent, "Sidewalk", offsetPoint(a, dx, dz, off), offsetPoint(b, dx, dz, off), w, WALK_T, WALK_Y - ROAD_Y, C.Walk, M.Pavement, "solid")
				end
			end
		end
	end
	-- détails client (seulement les tronçons à plat : les emplacements ne
	-- portent que le cap) ; rien sur l'anneau d'un rond-point (il a ses propres
	-- détails : pas de face confondue avec son asphalte)
	local function ring(id: string): number
		local node = graphNodes[id]
		return (node and node.Kind == "Roundabout") and 22 or 0
	end
	local detail = road
	if ring(e.A) > 0 or ring(e.B) > 0 then
		detail = trimPolyline(pts, s0 + ring(e.A), s1 - ring(e.B))
	end
	for i = 2, #detail do
		local a, b = detail[i - 1], detail[i]
		if math.abs(a.Y - b.Y) < 0.01 then
			local dx, dz, len = flatDir(a, b)
			local F = alongFrame(a, dx, dz, a.Y - ROAD_Y)
			chunks("RoadSurface", F, 1, len - 1, ROAD_Y, 0, 2, e.Width, seed * 100 + i)
			if w > 0 then
				-- (F : +Z = à DROITE du sens ; bordure de gauche retournée)
				chunks("CurbLine", F, 0, len, ROAD_Y, half - 0.05, CURB_H, 0, seed * 100 + 20 + i)
				chunks("CurbLine", F, 0, len, ROAD_Y, -half + 0.05, CURB_H, 0, seed * 100 + 40 + i, true)
				local wIn = w - 0.85
				chunks("Pavers", F, 1, len - 1, WALK_Y, half + 0.85 + wIn / 2, 0, wIn, seed * 100 + 60 + i)
				chunks("Pavers", F, 1, len - 1, WALK_Y, -half - 0.85 - wIn / 2, 0, wIn, seed * 100 + 80 + i)
			end
		end
	end
end

----------------------------------------------------------------------
-- Autoroute, bretelles, ponts
----------------------------------------------------------------------

-- Polyligne en dalles : chaque bout de dalle dépasse de w/2·tan(angle/2)
-- dans les virages (pas de trou au bord extérieur) ; hauteurs alternées
-- (0 / +0,03) pour que deux dalles qui se chevauchent ne soient jamais au
-- même niveau
local function polylineSlabs(parent: Instance, name: string, pts: { WorldLayout.RoadPoint }, w: number, t: number, lift: number, color: Color3, material: Enum.Material, parity0: number): number
	local n = #pts
	local count = 0
	local function turnAt(i: number): number
		if i <= 1 or i >= n then
			return 0
		end
		local ax, az = flatDir(pts[i - 1], pts[i])
		local bx, bz = flatDir(pts[i], pts[i + 1])
		local dot = math.clamp(ax * bx + az * bz, -1, 1)
		return math.acos(dot)
	end
	for i = 2, n do
		local e0 = w / 2 * math.tan(turnAt(i - 1) / 2) + (turnAt(i - 1) > 1e-3 and 0.2 or 0)
		local e1 = w / 2 * math.tan(turnAt(i) / 2) + (turnAt(i) > 1e-3 and 0.2 or 0)
		local parity = (parity0 + i) % 2
		if slab(parent, name, pts[i - 1], pts[i], w, t, lift + parity * 0.03, color, material, "solid", e0, e1) then
			count += 1
		end
	end
	return count
end

local function buildHighway(parent: Instance, graph: WorldLayout.RoadGraph, count: number)
	local model = TownKit.Model(parent, "Highway")
	-- l'anneau complet (une seule polyligne fermée, parité continue)
	local hw = WorldLayout.HighwayPath(count)
	-- (départ au milieu du côté sud, dans une ligne droite : aucun virage au raccord)
	local startP = { X = 0, Y = ROAD_Y, Z = WorldLayout.HighwayR(count) }
	local ordered: { WorldLayout.RoadPoint } = { startP }
	for i = 1, #hw do
		table.insert(ordered, hw[i])
	end
	table.insert(ordered, startP)
	polylineSlabs(model, "Carriageway", ordered, WorldLayout.HIGHWAY_W, 1, 0, C.Asphalt, M.Asphalt, 0)
	-- bretelles (0,06 au-dessus : jamais au niveau de l'autoroute ni du carrefour)
	for _, e in ipairs(graph.Edges) do
		if e.Ramp then
			polylineSlabs(model, "Ramp", e.Points, WorldLayout.RAMP_W, 1, 0.06, C.Asphalt, M.Asphalt, 0)
		end
	end
end

local function buildBridges(parent: Instance, graph: WorldLayout.RoadGraph)
	for _, e in ipairs(graph.Edges) do
		if e.Bridge then
			local model = TownKit.Model(parent, "Bridge")
			-- (les 10 premiers / derniers studs sont dans le carré des carrefours)
			local pts = trimPolyline(e.Points, 10, flatLength(e.Points) - 10)
			local deckW = e.Width + 2 * e.Sidewalk
			for i = 2, #pts do
				local a, b = pts[i - 1], pts[i]
				slab(model, "Deck", a, b, deckW, 1.2, 0, C.Asphalt, M.Asphalt, "solid")
				-- garde-corps là où le tablier est haut (plus de 1,5 stud)
				if math.min(a.Y, b.Y) > ROAD_Y + 1.5 then
					local dx, dz = flatDir(a, b)
					for _, side in ipairs({ -1, 1 }) do
						-- (0,05 en retrait : aucune face confondue avec le chant du tablier)
						local off = side * (deckW / 2 - 0.45)
						-- (raccourci de 0,06 aux bouts : deux tronçons voisins ne partagent jamais une face)
						slab(model, "Parapet", offsetPoint(a, dx, dz, off), offsetPoint(b, dx, dz, off), 0.8, 2.6, 2.6, C.Stone, M.Concrete, "solid", -0.06, -0.06)
					end
				end
			end
			-- culées (aux bouts du tablier plat) + pile sur le terre-plein central
			local mid = pts[math.floor(#pts / 2) + 1]
			local first, last = pts[1], pts[#pts]
			local dx, dz = flatDir(first, last)
			local half = WorldLayout.BRIDGE_HALF
			local top = ROAD_Y + WorldLayout.BRIDGE_Y - 1.2
			local cx, cz = (first.X + last.X) / 2, (first.Z + last.Z) / 2
			for _, n in ipairs({ -half + 1.6, 0, half - 1.6 }) do
				local h = top - GROUND_Y
				local q = WorldLayout.CityPoint(cx + dx * n, GROUND_Y + h / 2, cz + dz * n)
				local thick = n == 0 and 3 or 3.2
				part(model, n == 0 and "Pier" or "Abutment", Vector3.new(n == 0 and deckW - 6 or deckW, h - 0.02, thick), CFrame.lookAt(q, q + Vector3.new(dx, 0, dz)), C.StoneDark, M.Concrete, "solid")
			end
			local _ = mid
		end
	end
end

-- Ronds-points au bout des routes extérieures (asphalte + îlot)
local function buildRoundabouts(parent: Instance, count: number)
	for _, ix in ipairs(WorldLayout.INTERCHANGES) do
		local H = WorldLayout.HighwayR(count) + WorldLayout.OUTSIDE_END
		local p = WorldLayout.CityPoint(ix.NX * H, 0, ix.NZ * H)
		local model = TownKit.Model(parent, "Roundabout")
		-- (Disc : `center` = milieu du DESSUS)
		TownKit.Disc(model, "Ring", p + Vector3.new(0, ROAD_Y + 0.06, 0), 29, ROAD_T, C.Asphalt, M.Asphalt, "solid")
		TownKit.Disc(model, "Island", p + Vector3.new(0, WALK_Y + 0.06, 0), 14, WALK_T, C.Curb, M.Concrete, "solid")
		TownKit.Disc(model, "IslandGrass", p + Vector3.new(0, WALK_Y + 0.12, 0), 13, 0.2, C.Lawn, M.Grass, "deco")
		TownKit.LifeSpot("Roundabout", CFrame.new(p + Vector3.new(0, ROAD_Y + 0.06, 0)), 8100 + (ix.NX + 2) * 10 + ix.NZ, Vector3.new(14, 0, 29))
		TownKit.Tree(model, p + Vector3.new(0, WALK_Y + 0.2, 0), 15, 8200 + ix.NX * 3 + ix.NZ, "Cherry", { Tier = 1, Lawn = true })
	end
end

-- Plateau de la colline des manoirs (sol surélevé, sous les parcelles et les rues)
local function buildPlateaus(parent: Instance, count: number)
	for _, d in ipairs(WorldLayout.Districts(count)) do
		local p = d.Plateau
		if p and d.Rise > 0 then
			local model = TownKit.Model(parent, "Plateau_" .. d.Id)
			local top = GROUND_Y + d.Rise
			local h = top + 2 -- (enterré de 2 studs sous le pré)
			local q = WorldLayout.CityPoint(p.X, top - h / 2, p.Z)
			local ground = part(model, "Hill", Vector3.new(p.W, h, p.D), CFrame.new(q), C.Grass, M.Grass, "solid")
			ground:SetAttribute("District", d.Id)
			-- talus : 4 bords en pente douce (coins de roche)
			local slope = 6
			for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local sx, sz = side[1], side[2]
				local len = sx ~= 0 and p.D or p.W
				local cx = p.X + sx * (p.W / 2 + slope / 2)
				local cz = p.Z + sz * (p.D / 2 + slope / 2)
				local base = WorldLayout.CityPoint(cx, GROUND_Y + d.Rise / 2 - 0.05, cz)
				-- WedgePart : pente vers -Z local ; on tourne -Z vers l'extérieur
				local out = Vector3.new(sx, 0, sz)
				TownKit.Wedge(model, "Bank", Vector3.new(len, d.Rise - 0.1, slope), CFrame.lookAt(base, base + out), C.GrassDark, M.Grass, "solid")
			end
		end
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TownNetwork.Build(folder: Instance, geo: TownKit.Geo): Folder
	local count = geo.Count
	local graph = WorldLayout.RoadGraph(count)
	graphNodes = graph.Nodes
	local root = Instance.new("Folder")
	root.Name = "Network"
	root.Parent = folder
	local before = TownKit.Stats.Parts
	buildPlateaus(root, count)
	local roads = TownKit.Model(root, "Roads")
	local arms = armsOf(graph)
	local boxes: { [string]: Box } = {}
	for id, list in pairs(arms) do
		local node = graph.Nodes[id]
		if node and node.Kind ~= "Roundabout" then
			local box = boxOf(node, list)
			boxes[id] = box
			if box.Build then
				buildJunction(roads, node, box)
			end
		end
	end
	for i, e in ipairs(graph.Edges) do
		if not e.Highway and not e.Ramp and not e.Bridge and e.Kind ~= "Roundabout" and not isDowntown(e) then
			buildCityEdge(roads, e, boxes, arms, 9000 + i)
		end
	end
	buildHighway(root, graph, count)
	buildBridges(root, graph)
	buildRoundabouts(root, count)
	-- passages piétons (client)
	for i, cr in ipairs(graph.Crossings) do
		local c, s = math.cos(cr.Yaw), math.sin(cr.Yaw)
		-- sens de la route = LookVector de Yaw ; la bande traverse la chaussée
		local ux, uz = -s, -c
		local p = WorldLayout.CityPoint(cr.X, cr.Y, cr.Z)
		TownKit.LifeSpot("Zebra", CFrame.lookAt(p, p + Vector3.new(-uz, 0, ux)), math.floor(cr.Length * 10 + 0.5) + 0 * i)
	end
	root:SetAttribute("Parts", TownKit.Stats.Parts - before)
	root:SetAttribute("Edges", #graph.Edges)
	return root
end

return TownNetwork
