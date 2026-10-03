--[[
	RaceRoutes (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > RaceRoutes

	🏁 Parcours des courses de rue (v10, RACE10), construits sur le GRAPHE
	DES RUES de la ville (WorldLayout.RoadGraph de LAYOUT10) : partagé par le
	serveur (RaceService) et les clients (RaceClient) -> exactement les mêmes
	parcours partout. Calcul pur (nombres), mis en cache par nombre de
	parcelles ; les CFrame ne sont faits qu'à la demande (jeu).

	Parcours (Config.Race.Routes) :
	  City      🏙️ circuit du centre-ville (2 tours) ;
	  Highway   🛣️ sprint sur l'autoroute (bretelle -> sortie) ;
	  Districts 🏘️ boucle par les quartiers résidentiels ;
	  Night     🌙 grand tour (ville + autoroute), course de nuit.
	Chaque parcours = points de passage (coins du centre, centres des
	quartiers, extrémités de la ville...) reliés par le plus court chemin
	dans le graphe (rues déjà prises pénalisées : pas de demi-tour), puis
	virages arrondis (trajectoire de course), rééchantillonné tous les 4
	studs. Ligne de départ sur une LIGNE DROITE (grille de 8 places
	derrière), portes tous les ~170 studs, arrivée (boucle : la ligne de
	départ ; sprint : le dernier point).
	Sans graphe (avant LAYOUT10), un graphe de secours est tiré de l'ancien
	boulevard circulaire + avenue : les courses marchent quand même.
	(v11, RACE11) 3 parcours en plus :
	  Belt      🏎️ Grand Prix de la ceinture (le grand carré de l'avenue de ceinture) ;
	  Loft      🏭 circuit des entrepôts (3 tours serrés : rue des lofts + ceinture) ;
	  Endurance 🌀 la boucle complète de l'autoroute.
	Les lignes de départ de deux parcours sont écartées d'au moins 90 studs
	(portiques jamais superposés). Grille à l'échelle des voitures v11
	(Config.Race.Grid). Chaque parcours a un temps de référence (Par) et ses
	MÉDAILLES (or / argent / bronze), et la liste de ses VIRAGES (panneaux
	à chevrons côté client).

	API :
	  RaceRoutes.Get(routeId, count) -> Route?     (cache)
	  RaceRoutes.All(count) -> { Route }
	  RaceRoutes.Graph(count) -> graphe normalisé (Nodes, Edges, Adj)
	  RaceRoutes.MeetPoint(count) -> (x, z, heading) (repère du centre)
	  RaceRoutes.MeetCFrame(count) -> CFrame (monde, au sol, regard = heading)
	  RaceRoutes.GridCFrame(route, slot) -> CFrame (monde, pivot au sol, avant = -Z)
	  RaceRoutes.ToWorld(x, z, y?) -> Vector3
	  RaceRoutes.BlockedEdgeKeys(count) -> { ["a|b"] = true } (courses en cours)
	  RaceRoutes.IsNearActiveRoute(position: Vector3, margin?) -> boolean
	Route = { Id, Def, Closed, Laps, Line (trajectoire, pas de 4), Total (un
	  tour / la ligne), StartS (sprint : ligne de départ), RaceDistance,
	  Width, Checkpoints = { { D, S, X, Z, TX, TZ, W, Finish? } } (D = distance
	  de course), Grid = { { X, Z, TX, TZ } }, EdgeKeys = { ["a|b"] = true },
	  Nodes = { id }, (v11) Par, Medals = { Gold, Silver, Bronze },
	  Corners = { { S, Turn, Angle } }, PerLap (portes par tour) }
]]

local Config = require(script.Parent.Config)
local WorldLayout = require(script.Parent.WorldLayout)
local RaceRules = require(script.Parent.RaceRules)

local RaceRoutes = {}

RaceRoutes.ACTIVE_ATTRIBUTE = "DopamineRaceRoutes" -- (Workspace) ids des parcours en course, séparés par des virgules
RaceRoutes.STEP = 4 -- pas de la trajectoire (studs)
RaceRoutes.GRID_SLOTS = 8
-- (v11) grille à l'échelle des voitures (Config.Race.Grid)
local gridCfg = (Config.Race and (Config.Race :: any).Grid) or {}
RaceRoutes.GRID_ROW = gridCfg.Row or 21 -- studs entre deux voitures d'une même colonne
RaceRoutes.GRID_FIRST = gridCfg.First or 11 -- 1re place derrière la ligne
RaceRoutes.GRID_SIDE = gridCfg.Side or 5.2 -- décalage latéral des deux colonnes
RaceRoutes.STRAIGHT_BEFORE = 140 -- ligne droite demandée avant le départ
RaceRoutes.SPRINT_GRID = 95 -- sprint : la grille occupe les 95 premiers studs
RaceRoutes.START_GAP = 90 -- (v11) écart minimal entre deux lignes de départ

export type Node = { Id: string, X: number, Z: number, Y: number }
export type Edge = { A: string, B: string, Len: number, Points: { { number } }, Highway: boolean, Ramp: boolean, Width: number, Speed: number, Off: number, EffWidth: number }
export type Graph = { Nodes: { [string]: Node }, Edges: { Edge }, Adj: { [string]: { { To: string, Edge: Edge, Fwd: boolean } } }, Fallback: boolean }

local cache: { [number]: { Graph: Graph?, Routes: { [string]: any } } } = {}
local despike: (points: { { number } }, closed: boolean) -> { { number } }
local otherStarts: (routeId: string, count: number) -> { { number } }
local withMedals: (route: any) -> ()
local withCorners: (route: any) -> ()

local function finite(v: any, d: number): number
	return RaceRules.Finite(v, d)
end

local function origin(): (number, number, number)
	local ok, o = pcall(WorldLayout.Origin)
	if ok and o then
		return o.X, o.Y, o.Z
	end
	return WorldLayout.ORIGIN_X or 0, WorldLayout.ORIGIN_Y or 0, WorldLayout.ORIGIN_Z or 0
end

local function cacheFor(count: number)
	local c = cache[count]
	if not c then
		c = { Graph = nil, Routes = {} }
		cache[count] = c
	end
	return c
end

-- (tests / LAYOUT10 : le graphe a changé) oublie les parcours calculés
function RaceRoutes.ClearCache()
	table.clear(cache)
end

----------------------------------------------------------------------
-- Graphe des rues : normalisation (formes souples) + secours
----------------------------------------------------------------------

-- Position d'un nœud ou d'un point : Vector3 (monde) ou nombres (repère du centre)
local function readPoint(p: any): (number?, number?, number?)
	if p == nil then
		return nil
	end
	local ox, oy, oz = origin()
	local t = typeof(p)
	if t == "Vector3" then
		return p.X - ox, p.Z - oz, p.Y - oy
	elseif t == "CFrame" then
		local q = p.Position
		return q.X - ox, q.Z - oz, q.Y - oy
	elseif t == "table" then
		if p.Position ~= nil then
			return readPoint(p.Position)
		elseif p.P ~= nil then
			return readPoint(p.P)
		elseif p.Pos ~= nil then
			return readPoint(p.Pos)
		elseif type(p.X) == "number" and type(p.Z) == "number" then
			return p.X, p.Z, finite(p.Y, 0)
		elseif type(p.x) == "number" and type(p.z) == "number" then
			return p.x, p.z, finite(p.y, 0)
		elseif type(p[1]) == "number" and type(p[2]) == "number" then
			if type(p[3]) == "number" then
				-- { x, y, z } (3 nombres)
				return p[1], p[3], p[2]
			end
			return p[1], p[2], 0
		end
	end
	return nil
end
RaceRoutes.ReadPoint = readPoint

local function edgeKey(a: string, b: string): string
	if a < b then
		return a .. "|" .. b
	end
	return b .. "|" .. a
end
RaceRoutes.EdgeKey = edgeKey

local function addEdge(g: Graph, a: string, b: string, pts: { { number } }?, info: any)
	local na, nb = g.Nodes[a], g.Nodes[b]
	if not na or not nb or a == b then
		return
	end
	local points: { { number } } = { { na.X, na.Z, na.Y } }
	for _, p in ipairs(pts or {}) do
		local x, z, y = readPoint(p)
		if x and z then
			table.insert(points, { x, z, y or 0 })
		end
	end
	table.insert(points, { nb.X, nb.Z, nb.Y })
	local len = 0
	for i = 2, #points do
		len += math.sqrt((points[i][1] - points[i - 1][1]) ^ 2 + (points[i][2] - points[i - 1][2]) ^ 2)
	end
	local lanes = finite(info and info.Lanes, 1)
	local width = finite(info and (info.Width or info.RoadWidth), math.max(12, lanes * 8))
	-- (autoroute : axe = terre-plein central) on court sur SA chaussée, à
	-- droite de l'axe : décalage = milieu des voies, largeur = les voies
	local off, effW = 0, width
	local offsets = info and info.LaneOffsets
	if lanes >= 2 and type(offsets) == "table" and #offsets >= 2 then
		local lo, hi = math.huge, -math.huge
		for _, o in ipairs(offsets) do
			local v = finite(o, 0)
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
		off = (lo + hi) / 2
		effW = (hi - lo) + 11
	end
	local edge: Edge = {
		A = a,
		B = b,
		Len = math.max(len, 0.1),
		Points = points,
		Highway = info ~= nil and (info.Highway == true or info.Kind == "Highway"),
		Ramp = info ~= nil and (info.Ramp == true or info.Kind == "Ramp"),
		Width = width,
		Speed = finite(info and (info.Speed or info.SpeedLimit), 40),
		Off = off,
		EffWidth = effW,
	}
	table.insert(g.Edges, edge)
	g.Adj[a] = g.Adj[a] or {}
	g.Adj[b] = g.Adj[b] or {}
	table.insert(g.Adj[a], { To = b, Edge = edge, Fwd = true })
	-- sens unique ? (OneWay) : pas d'arête retour
	if not (info and info.OneWay == true) then
		table.insert(g.Adj[b], { To = a, Edge = edge, Fwd = false })
	end
end

-- Graphe brut de LAYOUT10 -> graphe normalisé (nil si inutilisable)
function RaceRoutes.Normalize(raw: any): Graph?
	if type(raw) ~= "table" then
		return nil
	end
	local g: Graph = { Nodes = {}, Edges = {}, Adj = {}, Fallback = false }
	local nodes = raw.Nodes or raw.nodes
	if type(nodes) ~= "table" then
		return nil
	end
	local count = 0
	local function addNode(key: any, node: any)
		local id = if type(node) == "table" and node.Id ~= nil then tostring(node.Id) else tostring(key)
		local x, z, y = readPoint(node)
		if x and z then
			g.Nodes[id] = { Id = id, X = x, Z = z, Y = y or 0 }
			count += 1
		end
	end
	if #nodes > 0 then
		for i, node in ipairs(nodes) do
			addNode(i, node)
		end
	else
		for key, node in pairs(nodes) do
			addNode(key, node)
		end
	end
	local edges = raw.Edges or raw.edges
	if count < 3 or type(edges) ~= "table" then
		return nil
	end
	for _, e in ipairs(edges) do
		if type(e) == "table" then
			local a = e.A or e.From or e.a or e[1]
			local b = e.B or e.To or e.b or e[2]
			if a ~= nil and b ~= nil then
				addEdge(g, tostring(a), tostring(b), e.Points or e.Path, e)
			end
		end
	end
	if #g.Edges < 3 then
		return nil
	end
	return g
end

-- Secours (pas de RoadGraph) : boulevard polygonal devant les parcelles +
-- avenue d'entrée (repère du centre de la ville)
local function fallbackGraph(count: number): Graph
	local g: Graph = { Nodes = {}, Edges = {}, Adj = {}, Fallback = true }
	local m = WorldLayout.PlotSlots(count)
	local ringR = WorldLayout.RingRoadRadius(count)
	local corner = ringR / math.cos(math.pi / m)
	local info = { Width = WorldLayout.ROAD_W, Lanes = 2, Speed = 40 }
	for k = 0, m - 1 do
		local a = (k + 0.5) / m * math.pi * 2
		g.Nodes["R" .. k] = { Id = "R" .. k, X = math.sin(a) * corner, Z = math.cos(a) * corner, Y = WorldLayout.ROAD_Y }
		local mid = k / m * math.pi * 2
		g.Nodes["M" .. k] = { Id = "M" .. k, X = math.sin(mid) * ringR, Z = math.cos(mid) * ringR, Y = WorldLayout.ROAD_Y }
	end
	for k = 0, m - 1 do
		local prev = (k - 1) % m
		addEdge(g, "R" .. prev, "M" .. k, nil, info)
		addEdge(g, "M" .. k, "R" .. k, nil, info)
	end
	-- avenue : de la place jusqu'au boulevard (emplacement 0 = entrée)
	local plazaZ = WorldLayout.PLAZA_R + WorldLayout.WALK_W + 10
	g.Nodes.P0 = { Id = "P0", X = 0, Z = plazaZ, Y = WorldLayout.ROAD_Y }
	addEdge(g, "P0", "M0", nil, { Width = WorldLayout.AVENUE_W, Lanes = 2, Speed = 30 })
	return g
end

-- Graphe de la ville (LAYOUT10 si possible, sinon secours), en cache
function RaceRoutes.Graph(count: number): Graph
	local c = cacheFor(count)
	if c.Graph then
		return c.Graph :: Graph
	end
	local g: Graph? = nil
	local fn = (WorldLayout :: any).RoadGraph
	if type(fn) == "function" then
		local ok, raw = pcall(fn, count)
		if ok then
			g = RaceRoutes.Normalize(raw)
		end
	end
	local graph = g or fallbackGraph(count)
	c.Graph = graph
	return graph
end

----------------------------------------------------------------------
-- Plus court chemin (Dijkstra, tas binaire)
----------------------------------------------------------------------

type CostFn = (edge: Edge) -> number

local function dijkstra(g: Graph, from: string, to: string, cost: CostFn): { { To: string, Edge: Edge, Fwd: boolean } }?
	if from == to then
		return {}
	end
	local dist: { [string]: number } = { [from] = 0 }
	local prev: { [string]: { From: string, Step: any } } = {}
	local heap: { { number | string } } = { { 0, from } }
	local function push(item)
		table.insert(heap, item)
		local i = #heap
		while i > 1 do
			local p = i // 2
			if (heap[p][1] :: number) <= (heap[i][1] :: number) then
				break
			end
			heap[p], heap[i] = heap[i], heap[p]
			i = p
		end
	end
	local function pop()
		local top = heap[1]
		local last = table.remove(heap)
		if #heap > 0 and last then
			heap[1] = last
			local i = 1
			while true do
				local l, r = i * 2, i * 2 + 1
				local s = i
				if l <= #heap and (heap[l][1] :: number) < (heap[s][1] :: number) then
					s = l
				end
				if r <= #heap and (heap[r][1] :: number) < (heap[s][1] :: number) then
					s = r
				end
				if s == i then
					break
				end
				heap[s], heap[i] = heap[i], heap[s]
				i = s
			end
		end
		return top
	end
	while #heap > 0 do
		local item = pop()
		local d, u = item[1] :: number, item[2] :: string
		if d > (dist[u] or math.huge) then
			continue
		end
		if u == to then
			break
		end
		for _, step in ipairs(g.Adj[u] or {}) do
			local c = cost(step.Edge)
			if c < math.huge then
				local nd = d + c
				if nd < (dist[step.To] or math.huge) then
					dist[step.To] = nd
					prev[step.To] = { From = u, Step = step }
					push({ nd, step.To })
				end
			end
		end
	end
	if not prev[to] then
		return nil
	end
	local path = {}
	local cur = to
	while cur ~= from do
		local p = prev[cur]
		table.insert(path, 1, p.Step)
		cur = p.From
	end
	return path
end

-- Nœud le plus proche de (x, z) (filtre facultatif)
local function nearestNode(g: Graph, x: number, z: number, filter: ((Node) -> boolean)?): string?
	local best, bestD = nil, math.huge
	for id, node in pairs(g.Nodes) do
		if (filter == nil or filter(node)) and g.Adj[id] and #g.Adj[id] > 0 then
			local d = (node.X - x) ^ 2 + (node.Z - z) ^ 2
			if d < bestD then
				best, bestD = id, d
			end
		end
	end
	return best
end

-- Nœuds touchés par des arêtes d'un type
local function nodeTypes(g: Graph): ({ [string]: boolean }, { [string]: boolean })
	local city, highway = {}, {}
	for _, e in ipairs(g.Edges) do
		if e.Highway or e.Ramp then
			highway[e.A] = true
			highway[e.B] = true
		else
			city[e.A] = true
			city[e.B] = true
		end
	end
	return city, highway
end

----------------------------------------------------------------------
-- Construction d'un parcours
----------------------------------------------------------------------

-- Boucle / chemin par les points de passage (ids de nœuds)
local function chain(g: Graph, via: { string }, closed: boolean, baseCost: CostFn): ({ { number } }?, { [string]: boolean }, number)
	local used: { [string]: number } = {}
	local keys: { [string]: boolean } = {}
	local points: { { number } } = {}
	local minWidth = math.huge
	local function cost(edge: Edge): number
		local c = baseCost(edge)
		local n = used[edgeKey(edge.A, edge.B)]
		if n then
			c *= 6 + n * 4 -- déjà prise : fortement pénalisée (pas de demi-tour)
		end
		return c
	end
	local legs = if closed then #via else #via - 1
	for k = 1, legs do
		local a = via[k]
		local b = via[(k % #via) + 1]
		local path = dijkstra(g, a, b, cost)
		if not path then
			return nil, keys, minWidth
		end
		for _, step in ipairs(path) do
			local e = step.Edge
			local key = edgeKey(e.A, e.B)
			used[key] = (used[key] or 0) + 1
			keys[key] = true
			minWidth = math.min(minWidth, e.EffWidth)
			local pts = e.Points
			local seq = {}
			if step.Fwd then
				for i = 1, #pts do
					table.insert(seq, pts[i])
				end
			else
				for i = #pts, 1, -1 do
					table.insert(seq, pts[i])
				end
			end
			if e.Off ~= 0 then
				-- décalage à droite du sens de marche (droite = (-tz, tx))
				local shifted = {}
				for i, p in ipairs(seq) do
					local pa = seq[math.max(1, i - 1)]
					local pb = seq[math.min(#seq, i + 1)]
					local dx, dz = pb[1] - pa[1], pb[2] - pa[2]
					local len = math.sqrt(dx * dx + dz * dz)
					if len > 1e-6 then
						dx, dz = dx / len, dz / len
					end
					table.insert(shifted, { p[1] - dz * e.Off, p[2] + dx * e.Off, p[3] })
				end
				seq = shifted
			end
			for _, p in ipairs(seq) do
				table.insert(points, p)
			end
		end
	end
	-- points en double + demi-tours (A -> B -> A) retirés
	local clean: { { number } } = {}
	for _, p in ipairs(points) do
		local n = #clean
		if n == 0 or (p[1] - clean[n][1]) ^ 2 + (p[2] - clean[n][2]) ^ 2 > 0.25 then
			if n >= 2 and (p[1] - clean[n - 1][1]) ^ 2 + (p[2] - clean[n - 1][2]) ^ 2 < 0.25 then
				table.remove(clean)
			else
				table.insert(clean, p)
			end
		end
	end
	return clean, keys, minWidth
end

-- Retire les "pointes" : un point où la ligne repart presque en arrière sur
-- un segment court (raccord bretelle -> chaussée décalée de l'autoroute)
despike = function(points: { { number } }, closed: boolean): { { number } }
	local pts = table.clone(points)
	for _ = 1, 40 do
		local changed = false
		local n = #pts
		local i = if closed then 1 else 2
		local last = if closed then n else n - 1
		while i <= last and #pts >= 4 do
			n = #pts
			local a = pts[if i == 1 then n else i - 1]
			local p = pts[i]
			local c = pts[if i == n then 1 else i + 1]
			local ux, uz = p[1] - a[1], p[2] - a[2]
			local vx, vz = c[1] - p[1], c[2] - p[2]
			local lu, lv = math.sqrt(ux * ux + uz * uz), math.sqrt(vx * vx + vz * vz)
			if lu > 1e-6 and lv > 1e-6 then
				local cosT = (ux * vx + uz * vz) / (lu * lv)
				if cosT < math.cos(math.rad(115)) and math.min(lu, lv) < 30 then
					table.remove(pts, i)
					changed = true
					last -= 1
					continue
				end
			end
			i += 1
		end
		if not changed then
			break
		end
	end
	return pts
end

-- Angle (radians) entre les caps à s0 et s1 (le long de la ligne)
local function headingChange(line: RaceRules.Line, s0: number, s1: number): number
	local worst = 0
	local _, _, tx0, tz0 = RaceRules.PointAt(line, s0)
	local s = s0
	while s <= s1 do
		local _, _, tx, tz = RaceRules.PointAt(line, s)
		local c = math.clamp(tx * tx0 + tz * tz0, -1, 1)
		worst = math.max(worst, math.acos(c))
		s += 8
	end
	return worst
end

-- Tourne une boucle pour qu'elle commence à s0
local function rotateLoop(line: RaceRules.Line, s0: number): RaceRules.Line
	local pts = {}
	local n = line.N
	local step = line.Total / n
	for k = 0, n - 1 do
		local x, z, _, _, y = RaceRules.PointAt(line, s0 + k * step)
		table.insert(pts, { x, z, y })
	end
	return RaceRules.Line(pts, true)
end

local function withCheckpoints(route: any)
	local line: RaceRules.Line = route.Line
	local spacing = (Config.Race and Config.Race.CheckpointSpacing) or 170
	local gateW = math.max(route.Width, 20) + 8
	local cps = {}
	local function gateAt(s: number, d: number, finish: boolean?)
		local x, z, tx, tz = RaceRules.PointAt(line, s)
		table.insert(cps, { D = d, S = s, X = x, Z = z, TX = tx, TZ = tz, W = gateW, Finish = finish == true })
	end
	if route.Closed then
		local per = math.max(2, math.floor(line.Total / spacing + 0.5))
		route.PerLap = per
		for lap = 0, route.Laps - 1 do
			for k = 1, per do
				local s = line.Total * k / per
				local d = lap * line.Total + s
				local isLast = k == per and lap == route.Laps - 1
				gateAt(s % line.Total, d, isLast)
			end
		end
	else
		local length = line.Total - route.StartS
		local per = math.max(2, math.floor(length / spacing + 0.5))
		route.PerLap = per
		for k = 1, per do
			local d = length * k / per
			gateAt(route.StartS + d, d, k == per)
		end
	end
	route.Checkpoints = cps
end

local function withGrid(route: any)
	local line: RaceRules.Line = route.Line
	local grid = {}
	for slot = 1, RaceRoutes.GRID_SLOTS do
		local row = (slot - 1) // 2
		local col = (slot - 1) % 2
		local back = RaceRoutes.GRID_FIRST + row * RaceRoutes.GRID_ROW + col * RaceRoutes.GRID_ROW * 0.5
		local s = route.StartS - back
		local x, z, tx, tz = RaceRules.PointAt(line, s)
		local side = if col == 0 then -RaceRoutes.GRID_SIDE else RaceRoutes.GRID_SIDE
		-- droite = (-tz, tx)
		table.insert(grid, { X = x - tz * side, Z = z + tx * side, TX = tx, TZ = tz, Back = back })
	end
	route.Grid = grid
end

-- Points de passage de chaque parcours
local function districtList(count: number): { any }
	local fn = (WorldLayout :: any).Districts
	if type(fn) ~= "function" then
		return {}
	end
	local ok, list = pcall(fn, count)
	if ok and type(list) == "table" then
		return list
	end
	return {}
end

local function boundsCenter(b: any): (number?, number?, number?, number?)
	-- Bounds : { Min, Max } | { X0, Z0, X1, Z1 } | { Center, Size }
	if type(b) ~= "table" then
		return nil
	end
	if b.Min ~= nil and b.Max ~= nil then
		local x0, z0 = readPoint(b.Min)
		local x1, z1 = readPoint(b.Max)
		if x0 and x1 and z0 and z1 then
			return (x0 + x1) / 2, (z0 + z1) / 2, math.abs(x1 - x0), math.abs(z1 - z0)
		end
	end
	if type(b.X) == "number" and type(b.Z) == "number" and type(b.W) == "number" and type(b.D) == "number" then
		return b.X, b.Z, b.W, b.D
	end
	if type(b.X0) == "number" and type(b.X1) == "number" and type(b.Z0) == "number" and type(b.Z1) == "number" then
		return (b.X0 + b.X1) / 2, (b.Z0 + b.Z1) / 2, math.abs(b.X1 - b.X0), math.abs(b.Z1 - b.Z0)
	end
	if b.Center ~= nil then
		local cx, cz = readPoint(b.Center)
		local sx, sz = 200, 200
		if typeof(b.Size) == "Vector3" then
			sx, sz = b.Size.X, b.Size.Z
		elseif type(b.Size) == "table" then
			sx, sz = finite(b.Size.X or b.Size[1], 200), finite(b.Size.Z or b.Size[2], 200)
		end
		if cx and cz then
			return cx, cz, sx, sz
		end
	end
	return nil
end

local function isResidential(d: any): boolean
	local id = string.lower(tostring(d.Id or d.Name or ""))
	return not (string.find(id, "down") or string.find(id, "center") or string.find(id, "centre") or string.find(id, "plaza"))
end

local function viaPoints(routeId: string, g: Graph, count: number): ({ string }, CostFn, boolean)
	local city, highway = nodeTypes(g)
	local function cityOnly(e: Edge): number
		if e.Highway or e.Ramp then
			return math.huge
		end
		return e.Len
	end
	local function mixed(e: Edge): number
		if e.Highway then
			return e.Len * 0.6
		end
		return e.Len
	end
	local function highwayFirst(e: Edge): number
		if e.Highway then
			return e.Len * 0.25
		elseif e.Ramp then
			return e.Len * 0.6
		end
		return e.Len * 3
	end
	local isCity = function(n: Node): boolean
		return city[n.Id] == true
	end
	local isHighway = function(n: Node): boolean
		return highway[n.Id] == true
	end
	local hasHighway = next(highway) ~= nil
	-- étendue des rues de la ville
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for id, n in pairs(g.Nodes) do
		if city[id] then
			minX, maxX = math.min(minX, n.X), math.max(maxX, n.X)
			minZ, maxZ = math.min(minZ, n.Z), math.max(maxZ, n.Z)
		end
	end
	local via: { string } = {}
	-- (v10, LAYOUT10) repères nommés des courses : WorldLayout.RaceAnchors
	local anchors: { [string]: string } = {}
	local fnA = (WorldLayout :: any).RaceAnchors
	if type(fnA) == "function" and not g.Fallback then
		local ok, list = pcall(fnA, count)
		if ok and type(list) == "table" then
			for name, id in pairs(list) do
				if g.Nodes[tostring(id)] then
					anchors[name] = tostring(id)
				end
			end
		end
	end
	local function fromAnchors(names: { string }): { string }?
		local out = {}
		for _, name in ipairs(names) do
			local id = anchors[name]
			if not id then
				return nil
			end
			table.insert(out, id)
		end
		return out
	end
	if routeId == "City" then
		local list = fromAnchors({ "DowntownSE", "DowntownSW", "DowntownNW", "DowntownNE" })
		if list then
			return list, cityOnly, true
		end
	elseif routeId == "Highway" then
		-- rond-point de l'entrée -> avenue -> bretelle sud -> autoroute (ouest puis nord)
		local list = fromAnchors({ "EntranceLoop", "RampSCity", "HighwayW", "HighwayN" })
			or fromAnchors({ "EntranceBoulevard", "RampSCity", "HighwayW", "HighwayN" })
		if list then
			return list, highwayFirst, false
		end
	elseif routeId == "Night" then
		-- grand tour : rue du marché -> avenue d'entrée -> autoroute sud-ouest
		-- -> sortie ouest -> ceinture -> rue des chalets -> rue du marché
		local list = fromAnchors({ "MarketStreetW", "RampSCity", "HighwayW", "RampWCity", "BeltW" })
			or fromAnchors({ "EntranceBoulevard", "RampSCity", "HighwayW", "RampWCity", "BeltW", "DowntownSW" })
		if list then
			return list, mixed, true
		end
	elseif routeId == "Belt" then
		-- (v11) Grand Prix de la ceinture : les 4 coins de l'avenue de ceinture
		local list = fromAnchors({ "BeltSE", "BeltSW", "BeltNW", "BeltNE" })
		if list then
			return list, cityOnly, true
		end
	elseif routeId == "Endurance" then
		-- (v11) la boucle complète de l'autoroute (rien d'autre)
		local list = fromAnchors({ "HighwayS", "HighwayE", "HighwayN", "HighwayW" })
		if list then
			return list, function(e: Edge): number
				if e.Highway then
					return e.Len
				end
				return math.huge
			end, true
		end
	elseif routeId == "Loft" then
		-- (v11) circuit des entrepôts : la 1re rue du quartier des lofts, la
		-- ceinture, puis l'avenue qui longe le centre
		local corner = anchors.BeltSE
		for _, d in ipairs(districtList(count)) do
			local st = type(d.Streets) == "table" and d.Streets[1] or nil
			if string.lower(tostring(d.Id)) == "loft" and type(st) == "table" and type(st.X0) == "number" and corner then
				local a = nearestNode(g, st.X0, st.Z0, isCity)
				local b = nearestNode(g, st.X1, st.Z1, isCity)
				if a and b and a ~= b then
					local na, nb = g.Nodes[a], g.Nodes[b]
					if na.X ^ 2 + na.Z ^ 2 > nb.X ^ 2 + nb.Z ^ 2 then
						a, b, na, nb = b, a, nb, na
					end
					local nc = g.Nodes[corner]
					local dId = nearestNode(g, na.X, nc.Z, isCity)
					if dId and dId ~= a and dId ~= corner and corner ~= b then
						return { a, b, corner, dId }, cityOnly, true
					end
				end
			end
		end
	elseif routeId == "Districts" then
		-- la rue principale de chaque quartier (sauf les quartiers fermés),
		-- dans l'ordre des angles, chaque rue prise d'un bout à l'autre
		local ds = {}
		for _, d in ipairs(districtList(count)) do
			local st = type(d.Streets) == "table" and d.Streets[1] or nil
			if isResidential(d) and d.Gated ~= true and type(st) == "table" and type(st.X0) == "number" then
				local cx, cz = boundsCenter(d.Bounds)
				if cx and cz then
					table.insert(ds, { St = st, A = math.atan2(cx, cz) })
				end
			end
		end
		table.sort(ds, function(a, b)
			return a.A < b.A
		end)
		if #ds >= 3 then
			local lastX, lastZ = 0, 0
			for i, d in ipairs(ds) do
				local st = d.St
				local a = nearestNode(g, st.X0, st.Z0, isCity)
				local b = nearestNode(g, st.X1, st.Z1, isCity)
				if a and b and a ~= b then
					local na, nb = g.Nodes[a], g.Nodes[b]
					local da = (na.X - lastX) ^ 2 + (na.Z - lastZ) ^ 2
					local db = (nb.X - lastX) ^ 2 + (nb.Z - lastZ) ^ 2
					if i == 1 then
						-- 1re rue : du bout le plus proche du centre vers l'extérieur
						da, db = na.X ^ 2 + na.Z ^ 2, nb.X ^ 2 + nb.Z ^ 2
					end
					if db < da then
						a, b, na, nb = b, a, nb, na
					end
					if via[#via] ~= a then
						table.insert(via, a)
					end
					table.insert(via, b)
					lastX, lastZ = nb.X, nb.Z
				end
			end
			if #via >= 4 then
				if via[#via] == via[1] then
					table.remove(via)
				end
				return via, cityOnly, true
			end
			via = {}
		end
	end
	local function addVia(x: number, z: number, filter: ((Node) -> boolean)?)
		local id = nearestNode(g, x, z, filter)
		if id and via[#via] ~= id and via[1] ~= id then
			table.insert(via, id)
		end
	end
	if routeId == "City" then
		-- coins du centre-ville (quartier "Downtown") ; sinon 55 % de l'étendue
		local cx, cz, sx, sz = 0, 0, (maxX - minX) * 0.55, (maxZ - minZ) * 0.55
		for _, d in ipairs(districtList(count)) do
			if not isResidential(d) then
				local x, z, w, h = boundsCenter(d.Bounds)
				if x and z and w and h then
					cx, cz, sx, sz = x, z, w, h
				end
			end
		end
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			addVia(cx + c[1] * sx / 2, cz + c[2] * sz / 2, isCity)
		end
		return via, cityOnly, true
	elseif routeId == "Districts" then
		local centers = {}
		for _, d in ipairs(districtList(count)) do
			if isResidential(d) then
				local x, z = boundsCenter(d.Bounds)
				if x and z then
					table.insert(centers, { x, z, math.atan2(x, z) })
				end
			end
		end
		if #centers < 3 then
			-- secours : 6 directions à 80 % de l'étendue
			centers = {}
			for k = 0, 5 do
				local a = k / 6 * math.pi * 2 + 0.3
				table.insert(centers, { math.sin(a) * (maxX - minX) * 0.4, math.cos(a) * (maxZ - minZ) * 0.4, a })
			end
		end
		table.sort(centers, function(a, b)
			return a[3] < b[3]
		end)
		for _, c in ipairs(centers) do
			addVia(c[1], c[2], isCity)
		end
		return via, cityOnly, true
	elseif routeId == "Highway" then
		-- sprint : de l'extrémité "nord-ouest" à l'extrémité "sud-est" de l'autoroute
		local hp = (WorldLayout :: any).HighwayPath
		if hasHighway then
			local pts = nil
			if type(hp) == "function" then
				local ok, list = pcall(hp, count)
				if ok and type(list) == "table" and #list >= 2 then
					pts = list
				end
			end
			if pts then
				local n = #pts
				local ax, az = readPoint(pts[1])
				local bx, bz = readPoint(pts[math.max(2, math.floor(n * 0.62))])
				if ax and az and bx and bz then
					addVia(ax, az, isHighway)
					addVia(bx, bz, isHighway)
				end
			end
			if #via < 2 then
				via = {}
				addVia(minX - 1e4, minZ - 1e4, isHighway)
				addVia(maxX + 1e4, maxZ + 1e4, isHighway)
			end
			return via, highwayFirst, false
		end
		-- pas d'autoroute (secours) : les 2/3 du boulevard
		addVia(maxX, 0, isCity)
		addVia(0, maxZ, isCity)
		addVia(minX, 0, isCity)
		return via, cityOnly, false
	elseif routeId == "Belt" or routeId == "Loft" then
		-- secours : grand carré de la ville (80 % / 45 % de l'étendue)
		local f = if routeId == "Belt" then 0.4 else 0.22
		for _, c in ipairs({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
			addVia(c[1] * (maxX - minX) * f, c[2] * (maxZ - minZ) * f, isCity)
		end
		return via, cityOnly, true
	else -- Night / Endurance : grand tour (autoroute permise)
		addVia(0, minZ - 1e4)
		addVia(maxX + 1e4, 0)
		addVia(0, maxZ + 1e4)
		addVia(minX - 1e4, 0)
		return via, if hasHighway then mixed else cityOnly, true
	end
end

-- (v11) lignes de départ / d'arrivée des parcours qui précèdent `routeId`
-- (ordre de Config.Race.Routes) : { { x, z } }
otherStarts = function(routeId: string, count: number): { { number } }
	local out = {}
	for _, def in ipairs((Config.Race and Config.Race.Routes) or {}) do
		if def.Id == routeId then
			break
		end
		local r = RaceRoutes.Get(def.Id, count)
		if r then
			local x, z = RaceRules.PointAt(r.Line, r.StartS)
			table.insert(out, { x, z })
			if not r.Closed then
				local fx, fz = RaceRules.PointAt(r.Line, r.Line.Total)
				table.insert(out, { fx, fz })
			end
		end
	end
	return out
end

-- (v11) temps de référence (pilote parfait) et médailles
withMedals = function(route: any)
	local par = (Config.Race and (Config.Race :: any).Par) or {}
	local top = par.TopSpeed or 66
	local profile = RaceRules.SpeedProfile(route.Line, top)
	local function sOf(d: number): number
		if route.Closed then
			return d % route.Total
		end
		return route.StartS + d
	end
	local t = RaceRules.SimTime(route.Line, profile, sOf, -route.Grid[1].Back, route.RaceDistance, top, par.Accel or 30, 1)
	route.Par = math.floor(t * 10 + 0.5) / 10
	route.Medals = RaceRules.Medals(route.Par)
end

-- (v11) virages marqués (panneaux à chevrons) : { { S, Turn (+1 gauche, -1
-- droite), Angle (rad) } } aux sommets des virages de plus de 35° sur 50 studs
withCorners = function(route: any)
	local line: RaceRules.Line = route.Line
	local samples = {}
	local s = 0
	while s < line.Total do
		local _, _, tx0, tz0 = RaceRules.PointAt(line, s - 25)
		local _, _, tx1, tz1 = RaceRules.PointAt(line, s + 25)
		local cross = tx0 * tz1 - tz0 * tx1
		local ang = math.acos(math.clamp(tx0 * tx1 + tz0 * tz1, -1, 1))
		table.insert(samples, { s, ang, cross })
		s += 6
	end
	local corners = {}
	local n = #samples
	for i = 1, n do
		local a = samples[i]
		local prev = samples[if i > 1 then i - 1 else n]
		local nxt = samples[if i < n then i + 1 else 1]
		if a[2] >= math.rad(35) and a[2] >= prev[2] and a[2] > nxt[2] then
			local last = corners[#corners]
			if not last or a[1] - last.S > 60 then
				if route.Closed or (a[1] > route.StartS + 30 and a[1] < line.Total - 20) then
					-- (droite = (-tz, tx) ; cross > 0 = virage vers la droite)
					table.insert(corners, { S = a[1], Turn = if a[3] > 0 then -1 else 1, Angle = a[2] })
				end
			end
		end
	end
	route.Corners = corners
end

local function buildRoute(routeId: string, count: number): any?
	local def = Config.RaceRoutesById and Config.RaceRoutesById[routeId]
	if not def then
		return nil
	end
	local g = RaceRoutes.Graph(count)
	local via, cost, closed = viaPoints(routeId, g, count)
	if #via < 2 or (closed and #via < 3) then
		return nil
	end
	local points, keys, minWidth = chain(g, via, closed, cost)
	if not points or #points < 3 then
		return nil
	end
	if closed then
		-- le dernier point rejoint le premier : retiré
		local n = #points
		if n > 1 and (points[n][1] - points[1][1]) ^ 2 + (points[n][2] - points[1][2]) ^ 2 < 0.25 then
			table.remove(points)
		end
	end
	local width = if minWidth < math.huge then minWidth else 16
	points = despike(points, closed)
	-- (les virages de l'autoroute sont déjà des arcs dans le graphe)
	local radius = math.clamp(width * 0.9, 12, 22)
	local filleted = RaceRules.Fillet(points, closed, radius, 3)
	local line = RaceRules.Resample(RaceRules.Line(filleted, closed), RaceRoutes.STEP)
	if line.Total < 300 then
		return nil
	end
	local route: any = {
		Id = routeId,
		Def = def,
		Closed = closed,
		Laps = if closed then math.max(1, def.Laps or 1) else 1,
		Width = width,
		EdgeKeys = keys,
		Nodes = via,
		Fallback = g.Fallback,
	}
	if closed then
		-- départ : sur une ligne droite, le plus près du point de rendez-vous
		local mx, mz = RaceRoutes.MeetPoint(count)
		-- (v11) lignes des parcours précédents (portiques jamais superposés)
		local taken = otherStarts(routeId, count)
		local bestS, bestScore = 0, math.huge
		local s = 0
		while s < line.Total do
			local change = headingChange(line, s - RaceRoutes.STRAIGHT_BEFORE, s + 30)
			if change < math.rad(7) then
				local x, z = RaceRules.PointAt(line, s)
				local score = (x - mx) ^ 2 + (z - mz) ^ 2
				for _, q in ipairs(taken) do
					if (x - q[1]) ^ 2 + (z - q[2]) ^ 2 < RaceRoutes.START_GAP ^ 2 then
						score = math.huge
					end
				end
				if score < bestScore then
					bestS, bestScore = s, score
				end
			end
			s += 8
		end
		line = rotateLoop(line, bestS)
		route.Line = line
		route.StartS = 0
		route.Total = line.Total
		route.RaceDistance = line.Total * route.Laps
	else
		route.Line = line
		route.StartS = math.min(RaceRoutes.SPRINT_GRID + 20, line.Total * 0.2)
		route.Total = line.Total
		route.RaceDistance = line.Total - route.StartS
	end
	withCheckpoints(route)
	withGrid(route)
	withMedals(route)
	withCorners(route)
	return route
end

function RaceRoutes.Get(routeId: string, count: number): any?
	local c = cacheFor(count)
	local r = c.Routes[routeId]
	if r == nil then
		local ok, built = pcall(buildRoute, routeId, count)
		if not ok then
			warn("[RaceRoutes] " .. routeId .. " : " .. tostring(built))
			built = nil
		end
		r = built or false
		c.Routes[routeId] = r
	end
	return if r then r else nil
end

function RaceRoutes.All(count: number): { any }
	local list = {}
	for _, def in ipairs((Config.Race and Config.Race.Routes) or {}) do
		local r = RaceRoutes.Get(def.Id, count)
		if r then
			table.insert(list, r)
		end
	end
	return list
end

----------------------------------------------------------------------
-- Point de rendez-vous (QG des courses)
----------------------------------------------------------------------

-- Zone "RaceMeet" réservée par LAYOUT10 (WorldLayout.Facilities / Facility),
-- sinon à côté de la porte de la ville. -> x, z (repère du centre), cap (radians,
-- 0 = regard vers -Z)
function RaceRoutes.MeetPoint(count: number): (number, number, number)
	local W: any = WorldLayout
	local zone = nil
	if type(W.Facility) == "function" then
		-- (v10, LAYOUT10) WorldLayout.Facility(count, id) -> Zone { X, Z, W, D, Yaw, Y }
		local ok, z = pcall(W.Facility, count, "RaceMeet")
		if ok and type(z) == "table" then
			zone = z
		end
	end
	if zone == nil then
		for _, name in ipairs({ "Facilities", "FacilityZones", "Reserved", "Zones" }) do
			if zone == nil and type(W[name]) == "function" then
				local ok, list = pcall(W[name], count)
				if ok and type(list) == "table" then
					for key, z in pairs(list) do
						if type(z) == "table" and (z.Id == "RaceMeet" or key == "RaceMeet") then
							zone = z
						end
					end
				end
			end
		end
	end
	if type(zone) == "table" or typeof(zone) == "CFrame" then
		local cf = if typeof(zone) == "CFrame" then zone else zone.CFrame
		if typeof(cf) == "CFrame" then
			local ox, _, oz = origin()
			local look = cf.LookVector
			return cf.Position.X - ox, cf.Position.Z - oz, math.atan2(-look.X, -look.Z)
		end
		local x, z = readPoint(zone.Center or zone.Position or zone)
		if x and z then
			return x, z, finite(zone.Yaw or zone.Heading or zone.Angle, 0)
		end
	end
	-- secours : devant la porte, côté gauche de l'avenue (regard vers l'avenue)
	local gate = WorldLayout.GateDistance(count)
	return -44, gate - 40, -math.pi / 2
end

----------------------------------------------------------------------
-- Repères du monde (jeu)
----------------------------------------------------------------------

function RaceRoutes.ToWorld(x: number, z: number, y: number?): Vector3
	local ox, oy, oz = origin()
	return Vector3.new(ox + x, oy + (y or WorldLayout.ROAD_Y), oz + z)
end

function RaceRoutes.MeetCFrame(count: number): CFrame
	local x, z, heading = RaceRoutes.MeetPoint(count)
	local p = RaceRoutes.ToWorld(x, z, WorldLayout.WALK_Y)
	return CFrame.new(p) * CFrame.Angles(0, heading, 0)
end

-- Place `slot` de la grille (pivot au sol, avant = -Z du CFrame = sens de la course)
function RaceRoutes.GridCFrame(route: any, slot: number): CFrame
	local g = route.Grid[math.clamp(slot, 1, #route.Grid)]
	local _, _, _, _, y = RaceRules.PointAt(route.Line, route.StartS - g.Back)
	local p = RaceRoutes.ToWorld(g.X, g.Z, y ~= 0 and y or nil)
	return CFrame.lookAt(p, p + Vector3.new(g.TX, 0, g.TZ))
end

-- CFrame (monde) d'une distance de course d (porte, remise sur la route) ;
-- lateral = décalage à droite
function RaceRoutes.CFrameAtD(route: any, d: number, lateral: number?): CFrame
	local s = if route.Closed then d else route.StartS + d
	local x, z, tx, tz, y = RaceRules.PointAt(route.Line, s)
	local side = lateral or 0
	local p = RaceRoutes.ToWorld(x - tz * side, z + tx * side, y ~= 0 and y or nil)
	return CFrame.lookAt(p, p + Vector3.new(tx, 0, tz))
end

----------------------------------------------------------------------
-- Circulation pendant une course (TownTraffic)
----------------------------------------------------------------------

local function activeIds(): { string }
	local ids = {}
	local ok, value = pcall(function()
		return workspace:GetAttribute(RaceRoutes.ACTIVE_ATTRIBUTE)
	end)
	if ok and type(value) == "string" and value ~= "" then
		for id in string.gmatch(value, "[^,]+") do
			if Config.RaceRoutesById[id] then
				table.insert(ids, id)
			end
		end
	end
	return ids
end
RaceRoutes.ActiveIds = activeIds

-- Arêtes du graphe prises par les courses en cours ("a|b", les deux sens)
function RaceRoutes.BlockedEdgeKeys(count: number): { [string]: boolean }
	local out = {}
	for _, id in ipairs(activeIds()) do
		local r = RaceRoutes.Get(id, count)
		if r then
			for key in pairs(r.EdgeKeys) do
				out[key] = true
				local a, b = string.match(key, "^(.-)|(.*)$")
				if a and b then
					out[b .. "|" .. a] = true
				end
			end
		end
	end
	return out
end

-- Position (monde) à moins de `margin` studs d'un parcours en course ?
function RaceRoutes.IsNearActiveRoute(position: Vector3, margin: number?, count: number?): boolean
	local ids = activeIds()
	if #ids == 0 then
		return false
	end
	local n = count or WorldLayout.PlotCount(game:GetService("Players").MaxPlayers)
	local ox, _, oz = origin()
	for _, id in ipairs(ids) do
		local r = RaceRoutes.Get(id, n)
		if r then
			local _, lat, dist = RaceRules.Project(r.Line, position.X - ox, position.Z - oz)
			local _ = lat
			if dist <= r.Width / 2 + (margin or 6) then
				return true
			end
		end
	end
	return false
end

return RaceRoutes
