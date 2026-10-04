--[[
	TownPeople (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownPeople

	🚶 Dopamine Town (v9.8, CITY98) : des PASSANTS dans les rues, côté CLIENT.
	  - des marcheurs sur les chemins publiés par le serveur (DopamineTown >
	    StreetLife, Configuration "Path" : l'anneau du trottoir intérieur du
	    boulevard, le tour de la place, la promenade de l'avenue jusqu'à la
	    porte, les trottoirs de l'avenue et des rues) : ils tiennent leur
	    droite, certains marchent à deux en discutant, d'autres promènent
	    leur CHIEN (laisse), joggent, regardent leur téléphone, portent un
	    café ou un sac de courses ;
	  - des gens ASSIS sur les bancs (place, avenue, arrivée, abribus), aux
	    terrasses de café, aux tables d'échecs ; des gens qui DISCUTENT à
	    deux ; quelqu'un qui attend le bus ; les marchands du petit marché,
	    du kiosque et des étals (emplacements de TownStreetLife).
	DÉTERMINISTE : la position de chacun ne dépend que de l'heure du serveur
	(workspace:GetServerTimeNow) et de sa graine -> tous les joueurs voient
	les mêmes passants aux mêmes endroits. Les personnages (NPCModels) ne
	sont construits que près de l'avatar : 18 au plus (les plus proches, à
	moins de 150 studs), 2 constructions par passe ; ancrés, animés par
	CFrame (BulkMoveTo) : 30 Hz près de l'avatar, 10 Hz plus loin. Aucune
	lumière, aucun son.

	v9.9 (NPC99) : chacun tient sa droite, évitement local, capsule de
	collision, places exactes sur les bancs (NPCSeats), regard vers le joueur.

	v11 (NPC11) — "ils se cognent, ils traversent les objets, la laisse flotte" :
	  - COULOIRS LIBRES : au chargement, tout ce qui gêne le long des chemins
	    est relevé UNE fois : mobilier publié (poubelles, bancs, bornes,
	    horodateurs, feux, cabines, jardinières, kiosques, abribus…),
	    pièces SOLIDES du serveur (lampadaires, bancs, bouches à incendie,
	    murs, fontaines…), bordures de trottoir, scène et public du concert
	    (WorldLayout.Facilities "MusicStage" / "MusicCrowd"). Pour chaque
	    stud de chemin on garde les intervalles latéraux BLOQUÉS (calcul
	    paresseux, par tronçons de 32 studs, seulement là où quelqu'un marche
	    près de l'avatar) ;
	  - ÉVITEMENT : chaque marcheur cherche, sur ~1 s devant lui, le point
	    latéral LIBRE le plus proche de sa droite (obstacles fixes + autres
	    passants + chiens + avatars) et s'y décale en douceur (≤ 1,8 stud/s) ;
	    derrière quelqu'un de plus lent sans place pour doubler, il RALENTIT
	    à sa vitesse (au lieu de s'arrêter net) ; face à face sans place, le
	    plus "jeune" (Id) laisse passer l'autre (jamais de blocage mutuel) ;
	  - les compagnons de marche passent en FILE INDIENNE quand c'est étroit ;
	  - le tour de la place contourne la scène et le public du concert ;
	  - CHIENS NPCModels (8 races, trot articulé) ; la laisse part du POING
	    (NPCModels.HandPoint) jusqu'au collier (NPCModels.DogCollar), en
	    chaînette souple (8 segments, flèche selon le mou) : elle ne flotte
	    plus jamais ; le chien trotte du côté libre, renifle à l'arrêt.

	API (TownClient, via optionalModule) :
	  TownPeople.Start()                  à l'entrée en ville
	  TownPeople.Step(position: Vector3)  flux (4 fois / s)
	  TownPeople.Stop()                   à la sortie
	  TownPeople.Positions() -> { Vector3 } passants construits (TownTraffic :
	                                      les voitures s'arrêtent devant eux)
	  TownPeople.Debug() -> table
	  (tests) TownPeople.Frame(dt?, position?, at?), TownPeople.Agents(),
	          TownPeople.Lanes() -> statistiques des couloirs
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local NPCModels = require(ReplicatedStorage.Shared.NPCModels)
local NPCSeats = require(ReplicatedStorage.Shared.NPCSeats)
local okWL, WorldLayout = pcall(require, ReplicatedStorage.Shared.WorldLayout)
-- (v9.8, REALISM98) réglage "Graphismes > Détail" : distance x 0,65 / 1 / 1,35 ;
-- "Low" : moitié moins de passants construits
local okGQ, GraphicsQuality = pcall(require, ReplicatedStorage.Shared.GraphicsQuality)
local function quality(): (number, boolean)
	if okGQ and type(GraphicsQuality) == "table" and GraphicsQuality.Get then
		local ok, q = pcall(GraphicsQuality.Get)
		if ok and type(q) == "table" then
			return tonumber(q.DetailScale) or 1, q.Detail == "Low"
		end
	end
	return 1, false
end

local TownPeople = {}

TownPeople.FOLDER_NAME = "TownPeople"
TownPeople.MAX_BUILT = 18
local NEAR_IN, NEAR_OUT = 150, 175
local BUILDS_PER_STEP = 2
local FAST_RANGE = 90 -- (studs) animés à 30 Hz en deçà, 10 Hz au-delà
local FAST_STEP, SLOW_STEP = 1 / 30, 1 / 10

local rgb = Color3.fromRGB

type Path = {
	Name: string,
	Points: { Vector3 },
	Cum: { number },
	Length: number,
	Loop: boolean,
	-- (v11) couloir : intervalles latéraux bloqués par échantillon (1 stud)
	Blk: { [number]: { number } },
	Done: { [number]: boolean },
	Y: number,
}
type Agent = {
	Id: number,
	Kind: string, -- "walk" | "static"
	Style: string,
	Seed: number,
	Prop: string?,
	Path: Path?,
	Speed: number,
	Dir: number,
	Offset: number,
	Lateral: number,
	Along: number, -- (compagnon / chien : décalage le long du chemin)
	Anim: string,
	CF: CFrame?, -- (statiques)
	Phase: number,
	Dog: boolean,
	Model: Model?,
	DogModel: Model?,
	Leash: { BasePart }?,
	Pos: Vector3,
	Clock: number,
	SitTop: number?, -- (assis) dessus du siège au-dessus du pivot
	Avoid: number, -- (marcheurs) écart latéral d'évitement (lissé)
	Delay: number, -- (s) retard accumulé en attendant / en ralentissant
	Waiting: boolean,
	LastNow: number,
	Heading: Vector3?,
	Mate: any?, -- (compagnon de marche)
	Lead: boolean?, -- (le compagnon "devant" d'un couple)
	Behind: number, -- (0..1) compagnon passé derrière (file indienne)
	Slow: number, -- (0..1) vitesse relative courante (ralenti derrière quelqu'un)
	WaitT: number, -- (s) depuis quand il attend
	DogLat: number, -- (chien) écart latéral lissé
	DogPos: Vector3?,
	Clock2: number?, -- (dernière image de la cadence de marche)
}

local state: any = nil

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and type(t) == "number" and t or os.clock()
end

local function parsePoints(text: string): { Vector3 }
	local pts = {}
	for _, chunk in ipairs(string.split(text, ";")) do
		local c = string.split(chunk, ",")
		local x, y, z = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
		if x and y and z then
			table.insert(pts, Vector3.new(x, y, z))
		end
	end
	return pts
end

local function makePath(name: string, pts: { Vector3 }, loop: boolean): Path?
	if #pts < 2 then
		return nil
	end
	local list = table.clone(pts)
	if loop then
		table.insert(list, pts[1])
	end
	local cum = { 0 }
	local y = 0
	for i = 2, #list do
		cum[i] = cum[i - 1] + (list[i] - list[i - 1]).Magnitude
	end
	for _, p in ipairs(pts) do
		y += p.Y
	end
	return { Name = name, Points = list, Cum = cum, Length = cum[#cum], Loop = loop, Blk = {}, Done = {}, Y = y / #pts }
end

-- Point du chemin à l'abscisse `s` (bouclé)
local function sample(path: Path, s: number): Vector3
	local L = path.Length
	s = s % L
	local cum, pts = path.Cum, path.Points
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = cum[hi] - cum[lo]
	local t = seg > 0 and (s - cum[lo]) / seg or 0
	return pts[lo]:Lerp(pts[hi], t)
end

local UP = Vector3.new(0, 1, 0)

-- abscisse courante d'un marcheur (moins son retard `Delay`)
local function walkerS(a: Agent, now: number): number
	return a.Offset + a.Dir * a.Speed * (now - (a.Delay or 0)) + a.Along + a.Dir * (a.Behind or 0) * -1.6
end

-- Point du chemin + avant / droite (sol) d'un marcheur au temps `now`
local function walkerFrame(a: Agent, now: number): (Vector3, Vector3, Vector3, number)
	local path = a.Path :: Path
	local s = walkerS(a, now)
	local p = sample(path, s)
	local ahead = sample(path, s + a.Dir * 1.2)
	local behind = sample(path, s - a.Dir * 1.2)
	local fwd = ahead - behind
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	if fwd.Magnitude < 0.01 then
		fwd = Vector3.new(0, 0, -1)
	end
	fwd = fwd.Unit
	return p, fwd, fwd:Cross(UP), s
end

local function walkerCF(a: Agent, now: number): CFrame
	local p, fwd, right = walkerFrame(a, now)
	local pos = p + right * (a.Lateral + (a.Avoid or 0))
	local heading = a.Heading or fwd
	return CFrame.lookAt(pos, pos + heading)
end

----------------------------------------------------------------------
-- (v11) Obstacles fixes et couloirs libres
----------------------------------------------------------------------

-- Rectangle au sol (repère : axe X = (AX, AZ), axe Z = (-AZ, AX)) ;
-- Kind : 1 = solide, 2 = bordure (souple), 3 = lieu réservé (concert)
type Rect = { CX: number, CZ: number, AX: number, AZ: number, HX: number, HZ: number, Kind: number }

local BAND = 2.6 -- (studs) écart latéral max. de part et d'autre du chemin
local BODY_PAD = 0.72 -- (studs) demi-largeur d'épaules + marge
local SAMPLE = 1.0 -- (studs) pas des échantillons du couloir
local BLOCK = 32 -- (échantillons) calculés par tronçons
local CELL = 16

-- Emprises (largeur X, profondeur Z, en studs) du mobilier publié
-- (StreetLife) ; un peu généreuses (mobilier agrandi en v11)
local FOOT: { [string]: { number } } = {
	Bin = { 1.2, 1.2 },
	Recycle = { 3.0, 1.3 },
	Mailbox = { 1.1, 1.1 },
	NewsBox = { 1.2, 1.2 },
	ParkMeter = { 0.6, 0.6 },
	TrafficLight = { 0.8, 0.8 },
	PhoneBooth = { 3.0, 3.0 },
	Planter = { 3.4, 1.7 },
	PlanterSmall = { 1.6, 1.6 },
	Vending = { 2.2, 1.5 },
	DogStation = { 1.0, 1.0 },
	SpeedSign = { 0.6, 0.6 },
	Direction = { 0.8, 0.8 },
	StreetName = { 0.5, 0.5 },
	Banner = { 0.5, 0.5 },
	Beacon = { 0.8, 0.8 },
	Bollards = { 3.0, 0.6 },
	Morris = { 2.6, 2.6 },
	Kiosk = { 7, 5 },
	BusShelter = { 8, 3.2 },
	DrinkFountain = { 1.2, 1.2 },
	FlowerStall = { 5, 3 },
	BookStall = { 5, 3 },
	Statue = { 3.6, 3.6 },
	Lamppost = { 0.8, 0.8 },
	ChessTables = { 9, 7 },
	Terrace = { 10, 6 },
	Bench = { 6.2, 2.4 },
	SitBench = { 6.2, 2.4 },
	Hydrant = { 0.8, 0.8 },
	Signpost = { 0.8, 0.8 },
}

local function addRect(s: any, r: Rect)
	table.insert(s.Rects, r)
	local idx = #s.Rects
	local rad = math.sqrt(r.HX * r.HX + r.HZ * r.HZ) + BAND + BODY_PAD
	for cx = math.floor((r.CX - rad) / CELL), math.floor((r.CX + rad) / CELL) do
		for cz = math.floor((r.CZ - rad) / CELL), math.floor((r.CZ + rad) / CELL) do
			local key = cx * 100003 + cz
			local list = s.Grid[key]
			if not list then
				list = {}
				s.Grid[key] = list
			end
			table.insert(list, idx)
		end
	end
end

local function rectFromCF(cf: CFrame, w: number, d: number, kind: number): Rect
	local rv = cf.RightVector
	local flat = Vector3.new(rv.X, 0, rv.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(1, 0, 0)
	end
	flat = flat.Unit
	local p = cf.Position
	return { CX = p.X, CZ = p.Z, AX = flat.X, AZ = flat.Z, HX = w / 2, HZ = d / 2, Kind = kind }
end

-- intervalle de t tel que (px, pz) + (dx, dz) t soit dans le rectangle
-- agrandi de `pad`
local function rayRect(px: number, pz: number, dx: number, dz: number, r: Rect, pad: number): (number?, number?)
	local rx, rz = px - r.CX, pz - r.CZ
	local lx = rx * r.AX + rz * r.AZ
	local lz = -rx * r.AZ + rz * r.AX
	local ux = dx * r.AX + dz * r.AZ
	local uz = -dx * r.AZ + dz * r.AX
	local t0, t1 = -math.huge, math.huge
	local hx, hz = r.HX + pad, r.HZ + pad
	if math.abs(ux) < 1e-6 then
		if math.abs(lx) > hx then
			return nil, nil
		end
	else
		local a, b = (-hx - lx) / ux, (hx - lx) / ux
		if a > b then
			a, b = b, a
		end
		t0, t1 = math.max(t0, a), math.min(t1, b)
	end
	if math.abs(uz) < 1e-6 then
		if math.abs(lz) > hz then
			return nil, nil
		end
	else
		local a, b = (-hz - lz) / uz, (hz - lz) / uz
		if a > b then
			a, b = b, a
		end
		t0, t1 = math.max(t0, a), math.min(t1, b)
	end
	if t0 > t1 then
		return nil, nil
	end
	return t0, t1
end

-- fusion d'intervalles (liste plate lo, hi, lo, hi…) bornée à [-BAND, BAND]
local function merge(list: { number }): { number }
	local n = #list // 2
	if n == 0 then
		return {}
	end
	local pairs_ = table.create(n)
	for i = 1, n do
		pairs_[i] = { list[i * 2 - 1], list[i * 2] }
	end
	table.sort(pairs_, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local lo, hi = pairs_[1][1], pairs_[1][2]
	for i = 2, n do
		local p = pairs_[i]
		if p[1] <= hi + 0.05 then
			hi = math.max(hi, p[2])
		else
			table.insert(out, lo)
			table.insert(out, hi)
			lo, hi = p[1], p[2]
		end
	end
	table.insert(out, lo)
	table.insert(out, hi)
	return out
end

-- le couloir est-il entièrement bloqué ?
local function fullyBlocked(m: { number }): boolean
	for i = 1, #m, 2 do
		if m[i] <= -BAND + 0.3 and m[i + 1] >= BAND - 0.3 then
			return true
		end
	end
	return false
end

-- Intervalles bloqués à l'échantillon i d'un chemin (repère du chemin :
-- droite = sens croissant x UP)
local function computeSample(s: any, path: Path, i: number): { number }
	local sPos = (i - 1) * SAMPLE
	local p = sample(path, sPos)
	local f = sample(path, sPos + 0.6) - sample(path, sPos - 0.6)
	f = Vector3.new(f.X, 0, f.Z)
	if f.Magnitude < 1e-3 then
		return {}
	end
	f = f.Unit
	local r = f:Cross(UP)
	local key = math.floor(p.X / CELL) * 100003 + math.floor(p.Z / CELL)
	local cands = s.Grid[key]
	if not cands then
		return {}
	end
	local function collect(maxKind: number): { number }
		local list = {}
		for _, idx in ipairs(cands) do
			local rect: Rect = s.Rects[idx]
			if rect.Kind <= maxKind or rect.Kind == 3 then
				for _, o in ipairs({ -0.45, 0, 0.45 }) do
					local q = p + f * o
					local t0, t1 = rayRect(q.X, q.Z, r.X, r.Z, rect, BODY_PAD)
					if t0 and t1 and t1 > -BAND and t0 < BAND then
						table.insert(list, math.max(t0, -BAND - 0.5))
						table.insert(list, math.min(t1, BAND + 0.5))
					end
				end
			end
		end
		return merge(list)
	end
	local m = collect(2)
	if fullyBlocked(m) then
		-- (passage piéton : la bordure coupe le chemin) sans les bordures
		m = collect(1)
		if fullyBlocked(m) then
			-- (rien ne passe : on ignore tout pour ne jamais rester planté)
			s.Stuck += 1
			m = {}
		end
	end
	return m
end

local function blockedAt(s: any, path: Path, sPos: number): { number }
	local n = math.max(1, math.floor(path.Length / SAMPLE))
	local i = math.floor((sPos % path.Length) / SAMPLE + 0.5) % n + 1
	local b = (i - 1) // BLOCK
	if not path.Done[b] then
		path.Done[b] = true
		for j = b * BLOCK + 1, math.min(n, (b + 1) * BLOCK) do
			path.Blk[j] = computeSample(s, path, j)
		end
		s.Computed += 1
	end
	return path.Blk[i] or {}
end

-- Relevé des obstacles fixes (une fois, au chargement)
local function collectObstacles(s: any, town: Instance, data: Instance, count: number)
	s.Rects, s.Grid, s.Stuck, s.Computed = {}, {}, 0, 0
	local ny = 0
	-- 1) mobilier publié (+ bordures de trottoir)
	for _, cell in ipairs(data:GetChildren()) do
		local text = cell:GetAttribute("Data")
		if cell.Name ~= "NpcBenches" and type(text) == "string" then
			for _, line in ipairs(string.split(text, "\n")) do
				local f = string.split(line, ";")
				local kind = f[1]
				local x, y, z, yaw = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
				if kind and x and y and z and yaw then
					local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
					local foot = FOOT[kind]
					if foot then
						addRect(s, rectFromCF(cf, foot[1], foot[2], 1))
					elseif kind == "CurbLine" and f[7] then
						local c = string.split(f[7], ",")
						local len = tonumber(c[1])
						if len then
							addRect(s, rectFromCF(cf, len, 0.3, 2))
						end
					end
				end
			end
		end
	end
	-- 2) pièces SOLIDES du serveur près des chemins (lampadaires, bancs,
	-- bouches à incendie, murs, fontaine…)
	local function nearPaths(p: Vector3, ext: number): boolean
		for _, path: Path in ipairs(s.Paths) do
			if math.abs(p.Y - path.Y) < 12 then
				local pts = path.Points
				for i = 2, #pts do
					local a, b = pts[i - 1], pts[i]
					local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
					local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
					local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
					if (ap - ab * t).Magnitude < BAND + BODY_PAD + ext + 1 then
						return true
					end
				end
			end
		end
		return false
	end
	for _, d in ipairs(town:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and not d:IsA("Terrain") then
			local cf, size = d.CFrame, d.Size
			local up = cf.UpVector
			local half
			if math.abs(up.Y) > 0.95 then
				half = Vector3.new(size.X / 2, size.Y / 2, size.Z / 2)
			else
				-- (pièce penchée : boîte englobante)
				local corners = size / 2
				local ex = math.abs(cf.RightVector.X) * corners.X + math.abs(cf.UpVector.X) * corners.Y + math.abs(cf.LookVector.X) * corners.Z
				local ey = math.abs(cf.RightVector.Y) * corners.X + math.abs(cf.UpVector.Y) * corners.Y + math.abs(cf.LookVector.Y) * corners.Z
				local ez = math.abs(cf.RightVector.Z) * corners.X + math.abs(cf.UpVector.Z) * corners.Y + math.abs(cf.LookVector.Z) * corners.Z
				half = Vector3.new(ex, ey, ez)
				cf = CFrame.new(cf.Position)
			end
			local p = cf.Position
			local top, bottom = p.Y + half.Y, p.Y - half.Y
			local ext = math.sqrt(half.X * half.X + half.Z * half.Z)
			if ext < 120 and nearPaths(p, ext) then
				-- (hauteur : entre les genoux et la tête au-dessus du chemin le plus proche)
				local pathY = s.Paths[1] and s.Paths[1].Y or p.Y
				for _, path: Path in ipairs(s.Paths) do
					if math.abs(path.Y - p.Y) < math.abs(pathY - p.Y) then
						pathY = path.Y
					end
				end
				if top > pathY + 0.45 and bottom < pathY + 4.5 then
					addRect(s, rectFromCF(cf, half.X * 2, half.Z * 2, 1))
					ny += 1
				end
			end
		end
	end
	-- 3) scène et public du concert (lieux réservés de la place)
	if okWL and type(WorldLayout) == "table" and WorldLayout.Facilities then
		local okF, zones = pcall(WorldLayout.Facilities, count)
		if okF and type(zones) == "table" then
			local o = WorldLayout.Origin()
			for _, z in ipairs(zones) do
				if z.Id == "MusicStage" or z.Id == "MusicCrowd" then
					local c, sn = math.cos(z.Yaw), math.sin(z.Yaw)
					addRect(s, { CX = o.X + z.X, CZ = o.Z + z.Z, AX = c, AZ = -sn, HX = z.W / 2 + 1, HZ = z.D / 2 + 1, Kind = 3 })
					table.insert(s.Zones, z)
				end
			end
		end
	end
	s.SolidParts = ny
end

----------------------------------------------------------------------
-- Évitement : couloir libre, ralentir, céder le passage
----------------------------------------------------------------------

type Obstacle = { Pos: Vector3, Agent: Agent?, Player: boolean, Dog: boolean? }

local CLEAR_NPC = 1.7 -- (studs) distance latérale pour croiser un passant
local CLEAR_PLAYER = 2.2 -- … un joueur
local CLEAR_DOG = 1.2
local CATCH_UP = 0.2 -- (x vitesse) en plus pour rattraper le retard
local LAT_SPEED = 1.8 -- (studs / s) vitesse latérale max.

-- intervalles libres de [-BAND, BAND] (liste plate) privés de `blocked` (fusionné)
local function freeOf(blocked: { number }): { number }
	local out = {}
	local cur = -BAND
	for i = 1, #blocked, 2 do
		local lo, hi = blocked[i], blocked[i + 1]
		if hi > cur then
			if lo > cur then
				table.insert(out, cur)
				table.insert(out, math.min(lo, BAND))
			end
			cur = math.max(cur, hi)
		end
		if cur >= BAND then
			break
		end
	end
	if cur < BAND then
		table.insert(out, cur)
		table.insert(out, BAND)
	end
	return out
end

local function steer(s: any, a: Agent, now: number, dt: number, obstacles: { Obstacle })
	local path = a.Path :: Path
	local p, fwd, right, sNow = walkerFrame(a, now)
	local lat = a.Lateral + a.Avoid
	local pos = p + right * lat
	local look = 1.4 + a.Speed * 0.9
	local blocked = {}
	-- obstacles fixes sur ~1 s devant (repère du chemin -> repère du marcheur)
	local step = 0
	while step <= look + 0.01 do
		local m = blockedAt(s, path, sNow + a.Dir * (step - 0.6))
		for i = 1, #m, 2 do
			if a.Dir > 0 then
				table.insert(blocked, m[i])
				table.insert(blocked, m[i + 1])
			else
				table.insert(blocked, -m[i + 1])
				table.insert(blocked, -m[i])
			end
		end
		step += SAMPLE
	end
	local staticFree = freeOf(merge(blocked))
	-- obstacles mobiles
	local near = {} -- (bloquent tout de suite : devant, tout près)
	local blocker: Obstacle? = nil
	local blockerFd = math.huge
	local mate = a.Mate
	for _, o in ipairs(obstacles) do
		local ag = o.Agent
		if ag ~= a and (ag == nil or ag ~= mate) and not (o.Dog and ag == a) then
			local rel = o.Pos - pos
			rel = Vector3.new(rel.X, 0, rel.Z)
			local fd = rel:Dot(fwd)
			local ld = rel:Dot(right)
			local clear = o.Player and CLEAR_PLAYER or (o.Dog and CLEAR_DOG or CLEAR_NPC)
			-- (vitesse de rapprochement : un passant d'en face compte plus loin)
			local closing = 0
			if ag and ag.Kind == "walk" and ag.Heading then
				closing = math.max(0, -(ag.Heading :: Vector3):Dot(fwd)) * ag.Speed
			end
			local far = look + closing * 0.9
			if fd > -1.2 and fd < far and math.abs(ld) < BAND + clear + 1 then
				-- céder le passage : face à face, le plus petit Id attend, l'autre passe au plus juste
				local squeeze = 1
				if ag and ag.Waiting and ag.Id < a.Id then
					squeeze = 0.8
				end
				local lo, hi = lat + ld - clear * squeeze, lat + ld + clear * squeeze
				table.insert(blocked, lo)
				table.insert(blocked, hi)
				if fd > 0 and fd < (o.Player and 2.6 or 2.0) and math.abs(ld) < clear * squeeze then
					local yields = not (ag and ag.Waiting and ag.Id < a.Id)
					if yields and fd < blockerFd then
						blocker, blockerFd = o, fd
					end
					table.insert(near, lo)
					table.insert(near, hi)
				end
			end
		end
	end
	local free = freeOf(merge(blocked))
	if #free == 0 then
		free = staticFree -- (au pire : seulement les obstacles fixes)
	end
	-- point visé : le plus proche de sa droite dans l'intervalle où l'on est,
	-- sinon l'intervalle libre le plus proche
	local pref = a.Lateral
	if mate and not a.Lead and mate.Model then
		pref = mate.Lateral + mate.Avoid + (a.Lateral - mate.Lateral)
	end
	local target = lat
	local bestCost = math.huge
	local inside = false
	for i = 1, #free, 2 do
		local lo, hi = free[i], free[i + 1]
		if lat >= lo - 0.05 and lat <= hi + 0.05 then
			inside = true
			target = math.clamp(pref, lo, hi)
			break
		end
	end
	if not inside then
		for i = 1, #free, 2 do
			local lo, hi = free[i], free[i + 1]
			local q = math.clamp(lat, lo, hi)
			local cost = math.abs(q - lat) + 0.3 * math.abs(math.clamp(pref, lo, hi) - pref)
			if cost < bestCost then
				bestCost = cost
				target = math.clamp(q + (math.clamp(pref, lo, hi) - q) * 0.3, lo, hi)
			end
		end
	end
	-- compagnon : file indienne s'il n'y a pas la place à côté
	if mate and not a.Lead and mate.Model then
		local single = math.abs(target - pref) > 0.8
		local want = single and 1 or 0
		a.Behind += (want - a.Behind) * math.min(1, dt * 1.5)
		if a.Behind > 0.5 then
			target = mate.Lateral + mate.Avoid
		end
	end
	local before = a.Avoid
	local want = target - a.Lateral
	local d = want - a.Avoid
	local maxStep = LAT_SPEED * dt
	a.Avoid += math.clamp(d * math.min(1, dt * 3), -maxStep, maxStep)
	-- bloqué (quelqu'un juste devant, pas encore de place sur le côté) :
	-- derrière un marcheur dans le même sens on prend SA vitesse, sinon on attend
	local slow = 1
	if blocker then
		local ag = blocker.Agent
		if ag and ag.Kind == "walk" and ag.Heading and (ag.Heading :: Vector3):Dot(fwd) > 0.5 then
			slow = math.clamp((ag.Speed * (ag.Slow or 1)) / math.max(a.Speed, 0.1), 0, 1) * math.clamp((blockerFd - 1.1) / 0.9, 0, 1)
		else
			slow = 0
		end
	end
	if mate and mate.Model and mate.Waiting then
		slow = 0
	end
	a.Slow = slow
	a.Waiting = slow < 0.05
	if a.Waiting then
		a.WaitT += dt
	else
		a.WaitT = 0
	end
	-- retard : ce qu'on n'a pas avancé ; rattrapé ensuite en marchant un peu plus vite
	if slow < 1 then
		a.Delay += dt * (1 - slow)
	elseif a.Delay > 0 then
		a.Delay = math.max(0, a.Delay - dt * CATCH_UP)
	end
	if mate and mate.Model then
		local dd = math.max(a.Delay, mate.Delay)
		a.Delay, mate.Delay = dd, dd
	end
	-- direction du regard : vers où l'on va vraiment (écart latéral compris)
	local side = dt > 0 and (a.Avoid - before) / dt or 0
	local speed = a.Waiting and 0.01 or a.Speed * math.max(slow, 0.2)
	local dir = fwd * speed + right * math.clamp(side, -2, 2)
	if dir.Magnitude > 0.05 then
		local h = a.Heading or fwd
		local tgt = dir.Unit
		local blend = h:Lerp(tgt, math.min(1, dt * 5))
		a.Heading = blend.Magnitude > 0.01 and blend.Unit or tgt
	end
	-- chien : du côté libre (gauche, sinon droite, sinon devant)
	if a.Dog then
		local dogS = sNow + a.Dir * 2.4
		local m = blockedAt(s, path, dogS)
		local function freeAt(l: number): boolean
			local lp = a.Dir > 0 and l or -l
			for i = 1, #m, 2 do
				if lp > m[i] + 0.25 and lp < m[i + 1] - 0.25 then
					return false
				end
			end
			return math.abs(l) < BAND
		end
		local here = a.Lateral + a.Avoid
		local dl = 0
		if freeAt(here - 1.0) then
			dl = -1.0
		elseif freeAt(here + 1.0) then
			dl = 1.0
		end
		a.DogLat += (dl - a.DogLat) * math.min(1, dt * 1.6)
	end
end

----------------------------------------------------------------------
-- Population
----------------------------------------------------------------------

-- Nombre de marcheurs par chemin (selon sa longueur) + styles tirés au sort
local WALK_STYLES = { "pedestrian", "pedestrian", "shopper", "pedestrian", "elder", "kid", "jogger", "worker", "shopper", "pedestrian" }
local PROPS = { "none", "phone", "coffee", "none", "bag", "none" }

-- dessus des sièges du mobilier client (TownStreetLife.SEAT_TOPS s'il existe)
local function seatTops(): { Terrace: number, Chess: number }
	local tops = { Terrace = 1.85, Chess = 1.85 }
	local module = script.Parent:FindFirstChild("TownStreetLife")
	if module and module:IsA("ModuleScript") then
		local ok, tsl = pcall(require, module)
		local t = if ok and type(tsl) == "table" then (tsl :: any).SEAT_TOPS else nil
		if type(t) == "table" then
			tops.Terrace = tonumber(t.Terrace) or tops.Terrace
			tops.Chess = tonumber(t.Chess) or tops.Chess
		end
	end
	return tops
end

-- Dessus du banc à `pos` (publié par le serveur : NpcBenches) ; nil = détecté
local function benchTop(s: any, pos: Vector3): number?
	for _, b in ipairs(s.Benches or {}) do
		if (b.Pos - pos).Magnitude < 0.6 then
			return b.Top
		end
	end
	return nil
end

local function addAgent(s: any, a: any)
	a.Id = #s.Agents + 1
	a.Pos = Vector3.zero
	a.Clock = 0
	a.Avoid = 0
	a.Delay = 0
	a.Waiting = false
	a.LastNow = 0
	a.Behind = 0
	a.Slow = 1
	a.WaitT = 0
	a.DogLat = -1
	a.Phase = a.Phase or hash(a.Seed, 5) * 10
	table.insert(s.Agents, a)
end

local function populate(s: any)
	local seedBase = 0
	-- marcheurs
	for _, path: Path in ipairs(s.Paths) do
		local n = math.clamp(math.floor(path.Length / 120 + 0.5), 1, 12)
		if path.Name == "PlazaRing" then
			n = 4
		end
		for i = 1, n do
			seedBase += 1
			local seed = seedBase * 13 + 7
			local style = WALK_STYLES[math.floor(hash(seed, 1) * #WALK_STYLES) + 1]
			local dir = hash(seed, 2) < 0.5 and 1 or -1
			local speed = style == "jogger" and 8.5 or (style == "elder" and 2.8 or (3.6 + hash(seed, 3) * 1.0))
			local prop = style == "shopper" and "bag" or PROPS[math.floor(hash(seed, 4) * #PROPS) + 1]
			if style == "jogger" or style == "worker" or style == "kid" then
				prop = "none"
			end
			local offset = (i - 1 + hash(seed, 6) * 0.6) / n * path.Length
			-- tenir SA droite : `right` suit déjà le sens de marche
			local lateral = 0.55 + hash(seed, 7) * 0.35
			local dog = (style == "pedestrian" or style == "elder") and hash(seed, 8) < 0.22
			addAgent(s, {
				Kind = "walk",
				Style = style,
				Seed = seed,
				Prop = dog and "leash" or prop,
				Path = path,
				Speed = speed,
				Dir = dir,
				Offset = offset,
				Lateral = lateral,
				Along = 0,
				Anim = "walk",
				Dog = dog,
				Lead = true,
			})
			-- (parfois un compagnon qui marche à côté : on discute en marchant)
			if not dog and style ~= "jogger" and hash(seed, 9) < 0.25 then
				addAgent(s, {
					Kind = "walk",
					Style = hash(seed, 10) < 0.3 and "kid" or "pedestrian",
					Seed = seed + 1000,
					Prop = "none",
					Path = path,
					Speed = speed,
					Dir = dir,
					Offset = offset,
					Lateral = lateral - 1.35,
					Along = -0.3 * dir,
					Anim = "walk",
					Dog = false,
					Lead = false,
				})
				-- (les deux compagnons ne s'évitent pas et s'attendent)
				local mate = s.Agents[#s.Agents]
				local lead = s.Agents[#s.Agents - 1]
				mate.Mate, lead.Mate = lead, mate
			end
		end
	end
	-- assis sur les bancs : places de NPCSeats (le serveur assoit le joueur
	-- sur une place LIBRE, à côté)
	for _, spot in ipairs(s.Anchors.SitBench or {}) do
		local plan = NPCSeats.BenchPlan(spot.Seed)
		for _, n in ipairs(plan.Npcs) do
			addAgent(s, {
				Kind = "static",
				Style = n.Style,
				Seed = n.Seed,
				Prop = n.Prop,
				CF = spot.CF * CFrame.new(NPCSeats.BENCH_SLOTS[n.Slot], 0, NPCSeats.SLOT_Z),
				Anim = "sit",
				SitTop = benchTop(s, spot.CF.Position),
			})
		end
	end
	-- terrasses : 3 clients assis (hauteur des chaises : TownStreetLife)
	local tops = seatTops()
	for _, spot in ipairs(s.Anchors.Terrace or {}) do
		for k, c in ipairs({ { -3.2, -1 }, { 0, 1 }, { 3.2, -1 }, { 3.2, 1 } }) do
			if k <= 3 or hash(spot.Seed, 30) < 0.5 then
				local chair = spot.CF * CFrame.new(c[1], 0, c[2] * 1.25) * CFrame.Angles(0, c[2] < 0 and math.pi or 0, 0)
				addAgent(s, {
					Kind = "static",
					Style = k % 2 == 0 and "shopper" or "pedestrian",
					Seed = spot.Seed * 11 + k,
					Prop = k == 2 and "coffee" or (k == 3 and "phone" or "none"),
					CF = chair * CFrame.new(0, 0, 0.15),
					Anim = "sit",
					SitTop = tops.Terrace,
				})
			end
		end
	end
	-- échecs : 2 joueurs face à face à la première table
	for _, spot in ipairs(s.Anchors.ChessTables or {}) do
		for _, sz in ipairs({ -1, 1 }) do
			local stool = spot.CF * CFrame.new(-3, 0, sz * 2.3) * CFrame.Angles(0, sz < 0 and math.pi or 0, 0)
			addAgent(s, { Kind = "static", Style = "elder", Seed = spot.Seed * 5 + sz, Prop = "none", CF = stool * CFrame.new(0, 0, 0.1), Anim = "sit", SitTop = tops.Chess })
		end
	end
	-- discussions à deux
	for _, spot in ipairs(s.Anchors.Chat or {}) do
		for _, sx in ipairs({ -1, 1 }) do
			local p = spot.CF * CFrame.new(sx * 1.15, 0, 0)
			addAgent(s, {
				Kind = "static",
				Style = hash(spot.Seed, 40 + sx) < 0.4 and "shopper" or "pedestrian",
				Seed = spot.Seed * 17 + sx,
				Prop = hash(spot.Seed, 42 + sx) < 0.3 and "coffee" or "none",
				CF = CFrame.lookAt(p.Position, (spot.CF * CFrame.new(-sx * 1.15, 0, 0)).Position),
				Anim = sx < 0 and "talk" or "idle",
			})
		end
	end
	-- on attend le bus
	for _, spot in ipairs(s.Anchors.Wait or {}) do
		addAgent(s, { Kind = "static", Style = "pedestrian", Seed = spot.Seed * 3 + 1, Prop = "phone", CF = spot.CF, Anim = "idle" })
	end
	-- marchands : kiosque, étals, petit marché
	for _, spot in ipairs(s.Anchors.Kiosk or {}) do
		addAgent(s, { Kind = "static", Style = "pedestrian", Seed = spot.Seed * 19, Prop = "none", CF = spot.CF * CFrame.new(0, 0, 0.2), Anim = "talk" })
	end
	for _, kind in ipairs({ "FlowerStall", "BookStall" }) do
		for _, spot in ipairs(s.Anchors[kind] or {}) do
			addAgent(s, { Kind = "static", Style = kind == "FlowerStall" and "shopper" or "elder", Seed = spot.Seed * 23, Prop = "none", CF = spot.CF * CFrame.new(0.6, 0, 2.0), Anim = "talk" })
		end
	end
	for _, spot in ipairs(s.Anchors.MarketSquare or {}) do
		local stalls = { { -7, -4, 0 }, { 7, -4, 0 }, { -7, 5, math.pi }, { 7, 5, math.pi } }
		for i, st in ipairs(stalls) do
			local S = spot.CF * CFrame.new(st[1], 0.12, st[2]) * CFrame.Angles(0, st[3], 0)
			addAgent(s, { Kind = "static", Style = i % 2 == 0 and "baker" or "worker", Seed = spot.Seed * 29 + i, Prop = "none", CF = S * CFrame.new(0, 0, 2.0), Anim = i % 2 == 0 and "talk" or "scan" })
			if i <= 2 then
				-- un client devant l'étal
				addAgent(s, { Kind = "static", Style = "shopper", Seed = spot.Seed * 31 + i, Prop = "bag", CF = S * CFrame.new(0.8, 0, -2.6) * CFrame.Angles(0, math.pi, 0), Anim = "idle" })
			end
		end
	end
end

----------------------------------------------------------------------
-- Construction / animation
----------------------------------------------------------------------

local function agentCF(a: Agent, now: number): CFrame
	if a.Kind == "walk" then
		return walkerCF(a, now)
	end
	return a.CF :: CFrame
end

-- chien : un peu devant, du côté libre (DogLat), qui flâne un peu
local function dogCF(a: Agent, now: number): CFrame
	local wander = math.sin(now * 0.31 + a.Seed) * 0.35
	local fake = {
		Path = a.Path,
		Offset = a.Offset,
		Dir = a.Dir,
		Speed = a.Speed,
		Along = a.Dir * (2.3 + math.sin(now * 0.23 + a.Seed) * 0.3),
		Lateral = a.Lateral + a.Avoid + a.DogLat + wander * 0.4,
		Delay = a.Delay,
		Behind = 0,
		Avoid = 0,
		Heading = a.Heading,
	}
	return walkerCF(fake :: any, now)
end

local LEASH_SEGS = 8
local LEASH_LEN = 3.9

local function buildAgent(s: any, a: Agent)
	local style = a.Style
	local m = NPCModels.Build(style, { Seed = a.Seed, Prop = a.Prop or "none", SitHeight = a.SitTop })
	m.Name = "Person"
	NPCModels.Place(m, agentCF(a, s.Now))
	m.Parent = s.Folder
	a.Model = m
	if a.Dog then
		local d = NPCModels.BuildDog(a.Seed)
		d.Parent = s.Folder
		a.DogModel = d
		local leash = {}
		local color = rgb(220, 50, 70)
		for i = 1, LEASH_SEGS do
			local seg = Instance.new("Part")
			seg.Name = "Leash"
			seg.Anchored = true
			seg.CanCollide = false
			seg.CanQuery = false
			seg.CanTouch = false
			seg.CastShadow = false
			seg.Shape = Enum.PartType.Cylinder
			seg.Size = Vector3.new(0.5, 0.07, 0.07)
			seg.Color = color
			seg.Material = Enum.Material.SmoothPlastic
			seg.Parent = s.Folder
			leash[i] = seg
		end
		a.Leash = leash
	end
end

local function destroyAgent(a: Agent)
	if a.Model then
		a.Model:Destroy()
	end
	if a.DogModel then
		a.DogModel:Destroy()
	end
	if a.Leash then
		for _, p in ipairs(a.Leash) do
			p:Destroy()
		end
	end
	a.Model, a.DogModel, a.Leash = nil, nil, nil
end

-- Laisse : chaînette souple du poing au collier (parabole : flèche selon le
-- mou, jamais sous le sol)
local leashFrames: { CFrame } = {}
local function drawLeash(a: Agent, hand: Vector3, collar: Vector3)
	local leash = a.Leash
	if not leash then
		return
	end
	local D = (collar - hand).Magnitude
	local sag = 0
	if D < LEASH_LEN then
		sag = math.sqrt(3 * D * (LEASH_LEN - D) / 8)
	end
	local lowest = math.min(hand.Y, collar.Y) - 0.15
	local floorY = a.Pos.Y + 0.15
	sag = math.min(sag, 1.6, math.max(0, lowest - floorY + 0.5))
	local prev = hand
	for i = 1, LEASH_SEGS do
		local t = i / LEASH_SEGS
		local q = hand:Lerp(collar, t) - Vector3.new(0, 4 * sag * t * (1 - t), 0)
		local mid = (prev + q) / 2
		local len = (q - prev).Magnitude
		local seg = leash[i]
		seg.Size = Vector3.new(len + 0.03, 0.07, 0.07)
		if len > 1e-3 then
			leashFrames[i] = CFrame.lookAt(mid, q) * CFrame.Angles(0, math.pi / 2, 0)
		else
			leashFrames[i] = CFrame.new(mid)
		end
		prev = q
	end
	workspace:BulkMoveTo(leash, leashFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function animateAgent(s: any, a: Agent, now: number, obstacles: { Obstacle }?)
	local m = a.Model
	if not m then
		return
	end
	if a.Kind == "walk" then
		local dt = a.LastNow > 0 and math.clamp(now - a.LastNow, 0, 0.25) or 0
		a.LastNow = now
		if obstacles then
			steer(s, a, now, dt, obstacles)
		end
	end
	local cf = agentCF(a, now)
	a.Pos = cf.Position
	-- (NPCModels.Place : seule la racine bouge, Animate repose le reste)
	NPCModels.Place(m, cf)
	local t = now + a.Phase
	if a.Kind == "walk" then
		-- (cadence proportionnelle à la vitesse : ~4 studs / s = pas normal ;
		-- plus rapide quand on rattrape son retard ; ralenti ; arrêté = au repos)
		local sc = tonumber(m:GetAttribute("NpcScale")) or 1
		local slow = a.Slow or 1
		local rate = a.Speed * slow / (4 * sc) * (a.Delay > 0 and slow >= 1 and (1 + CATCH_UP) or 1)
		if a.Waiting then
			NPCModels.Animate(m, "idle", t)
		else
			a.Clock += rate * math.clamp(now - (a.Clock2 or now), 0, 0.25)
			NPCModels.Animate(m, "walk", a.Clock + a.Phase)
		end
		a.Clock2 = now
		local dog = a.DogModel
		if dog then
			local dcf = dogCF(a, now)
			a.DogPos = dcf.Position
			NPCModels.AnimateDog(dog, dcf, t, a.Waiting and 0 or a.Speed * slow)
			local hand = NPCModels.HandPoint(m, -1)
			local collar = NPCModels.DogCollar(dog)
			if hand and collar then
				drawLeash(a, hand, collar)
			end
		end
	else
		NPCModels.Animate(m, a.Anim, t)
	end
end

----------------------------------------------------------------------
-- Chargement
----------------------------------------------------------------------

-- obstacles : les personnes construites (+ leurs chiens) + les avatars de TOUS les joueurs
local function obstaclesOf(s: any): { Obstacle }
	local obstacles: { Obstacle } = {}
	for _, a: Agent in ipairs(s.Built or {}) do
		local pos = a.Pos
		if a.Kind == "static" and a.Anim == "sit" and a.CF then
			-- (assis : les jambes avancent)
			pos = ((a.CF :: CFrame) * CFrame.new(0, 0, -0.6)).Position
		end
		table.insert(obstacles, { Pos = pos, Agent = a, Player = false })
		if a.DogPos then
			table.insert(obstacles, { Pos = a.DogPos, Agent = a, Player = false, Dog = true })
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(obstacles, { Pos = root.Position, Agent = nil, Player = true })
		end
	end
	s.Obstacles = obstacles
	return obstacles
end

local ANCHOR_KINDS = { "SitBench", "Terrace", "ChessTables", "Chat", "Wait", "Kiosk", "FlowerStall", "BookStall", "MarketSquare" }

-- (v11) tour de la place : contourne la scène et le public du concert
local function plazaRing(s: any, plaza: CFrame, count: number): { Vector3 }
	local zones = {}
	if okWL and type(WorldLayout) == "table" and WorldLayout.Facilities then
		local okF, list = pcall(WorldLayout.Facilities, count)
		if okF and type(list) == "table" then
			for _, z in ipairs(list) do
				if z.Id == "MusicStage" or z.Id == "MusicCrowd" then
					table.insert(zones, z)
				end
			end
		end
	end
	local origin = (okWL and WorldLayout.Origin) and WorldLayout.Origin() or Vector3.zero
	local N = 48
	local radii = table.create(N, 26)
	for i = 1, N do
		local ang = (i - 1) / N * math.pi * 2
		for r = 26, 60, 1 do
			local p = plaza.Position + Vector3.new(math.sin(ang) * r, 0, math.cos(ang) * r)
			local inside = false
			for _, z in ipairs(zones) do
				if WorldLayout.InZone(z, p.X - origin.X, p.Z - origin.Z, 3.5) then
					inside = true
				end
			end
			radii[i] = r
			if not inside then
				break
			end
		end
	end
	-- (lissage : on s'écarte progressivement autour du détour)
	local smooth = table.create(N, 26)
	for i = 1, N do
		local best = radii[i]
		for k = -3, 3 do
			local j = (i - 1 + k) % N + 1
			best = math.max(best, radii[j] - math.abs(k) * 4)
		end
		smooth[i] = best
	end
	local ring = {}
	for i = 1, N do
		local ang = (i - 1) / N * math.pi * 2
		table.insert(ring, plaza.Position + Vector3.new(math.sin(ang) * smooth[i], 0.08, math.cos(ang) * smooth[i]))
	end
	s.PlazaDetour = math.max(table.unpack(smooth)) - 26
	return ring
end

local function load(s: any): boolean
	local town = workspace:FindFirstChild("DopamineTown")
	local data = town and town:FindFirstChild("StreetLife")
	if not town or not data then
		return false
	end
	local count = town:GetAttribute("PlotCount")
	if type(count) ~= "number" then
		count = (okWL and WorldLayout.PlotCount) and WorldLayout.PlotCount(Players.MaxPlayers) or 8
	end
	local paths: { Path } = {}
	local anchors: { [string]: { { CF: CFrame, Seed: number } } } = {}
	for _, kind in ipairs(ANCHOR_KINDS) do
		anchors[kind] = {}
	end
	local benches = {}
	for _, child in ipairs(data:GetChildren()) do
		if child.Name == "NpcBenches" then
			local text = child:GetAttribute("Data")
			if type(text) == "string" then
				for _, line in ipairs(string.split(text, "\n")) do
					local f = string.split(line, ";")
					local x, y, z, top = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
					if x and y and z and top then
						table.insert(benches, { Pos = Vector3.new(x, y, z), Top = top })
					end
				end
			end
		elseif child.Name == "Path" then
			local pts = child:GetAttribute("Points")
			local name = child:GetAttribute("Name")
			if type(pts) == "string" and type(name) == "string" then
				local path = makePath(name, parsePoints(pts), child:GetAttribute("Loop") == true)
				if path then
					table.insert(paths, path)
				end
			end
		else
			local text = child:GetAttribute("Data")
			if type(text) == "string" then
				for _, line in ipairs(string.split(text, "\n")) do
					local f = string.split(line, ";")
					local list = anchors[f[1]]
					local x, y, z, yaw = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
					if list and x and y and z and yaw then
						table.insert(list, { CF = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), Seed = tonumber(f[6]) or 0 })
					end
				end
			end
		end
	end
	-- (ordre stable : même population sur tous les clients)
	table.sort(paths, function(a, b)
		return a.Name < b.Name
	end)
	for _, list in pairs(anchors) do
		table.sort(list, function(a, b)
			local pa, pb = a.CF.Position, b.CF.Position
			if pa.X ~= pb.X then
				return pa.X < pb.X
			end
			return pa.Z < pb.Z
		end)
	end
	s.Zones = {}
	-- le petit tour de la place (autour de la fontaine, en évitant le concert)
	local plaza = town:GetAttribute("PlazaCF")
	if typeof(plaza) == "CFrame" then
		local ok, ring = pcall(plazaRing, s, plaza, count)
		if ok then
			local path = makePath("PlazaRing", ring, true)
			if path then
				table.insert(paths, path)
			end
		end
	end
	s.Paths = paths
	s.Anchors = anchors
	s.Benches = benches
	s.Agents = {}
	local okO, errO = pcall(collectObstacles, s, town, data, count)
	if not okO then
		warn("[TownPeople] obstacles : " .. tostring(errO))
		s.Rects, s.Grid, s.Stuck, s.Computed = {}, {}, 0, 0
	end
	populate(s)
	local folder = Instance.new("Folder")
	folder.Name = TownPeople.FOLDER_NAME
	folder.Parent = workspace
	s.Folder = folder
	s.Loaded = true
	return true
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function TownPeople.Start()
	if state then
		return
	end
	state = { Agents = {}, Paths = {}, Anchors = {}, Loaded = false, Retry = 0, Now = serverNow(), AccFast = 0, AccSlow = 0, Focus = nil, Rects = {}, Grid = {}, Stuck = 0, Computed = 0, Zones = {} }
	pcall(load, state)
	state.Conn = RunService.Heartbeat:Connect(function(dt: number)
		local s = state
		if not s or not s.Loaded then
			return
		end
		s.AccFast += dt
		s.AccSlow += dt
		local fast = s.AccFast >= FAST_STEP
		local slow = s.AccSlow >= SLOW_STEP
		if not fast then
			return
		end
		s.AccFast = 0
		if slow then
			s.AccSlow = 0
		end
		local now = serverNow()
		s.Now = now
		local focus = s.Focus
		local ok, err = pcall(function()
			local obstacles = obstaclesOf(s)
			for _, a: Agent in ipairs(s.Built) do
				local near = focus == nil or (a.Pos - focus).Magnitude < FAST_RANGE
				if near or slow then
					animateAgent(s, a, now, obstacles)
				end
			end
		end)
		if not ok and not s.Warned then
			s.Warned = true
			warn("[TownPeople] " .. tostring(err))
		end
	end)
	state.Built = {}
end

function TownPeople.Step(position: Vector3)
	local s = state
	if not s then
		return
	end
	if not s.Loaded then
		s.Retry -= 1
		if s.Retry <= 0 then
			s.Retry = 4
			pcall(load, s)
		end
		return
	end
	s.Focus = position
	local now = serverNow()
	s.Now = now
	local scale, low = quality()
	local nearIn, nearOut = NEAR_IN * scale, NEAR_OUT * scale
	local maxBuilt = low and math.floor(TownPeople.MAX_BUILT / 2) or TownPeople.MAX_BUILT
	-- distances (tous les passants "existent" ; on ne construit que les plus proches)
	local cands = {}
	for _, a: Agent in ipairs(s.Agents) do
		local p = a.Model and a.Pos or agentCF(a, now).Position
		if not a.Model then
			a.Pos = p
		end
		local d = (Vector3.new(p.X - position.X, 0, p.Z - position.Z)).Magnitude
		if d < nearOut then
			table.insert(cands, { A = a, D = d })
		end
	end
	table.sort(cands, function(x, y)
		return x.D < y.D
	end)
	local wanted: { [Agent]: boolean } = {}
	for i, c in ipairs(cands) do
		if i > maxBuilt then
			break
		end
		-- (hystérésis : un passant déjà construit reste jusqu'à NEAR_OUT)
		if c.D < nearIn or c.A.Model then
			wanted[c.A] = true
		end
	end
	-- (un couple se construit / se détruit ensemble)
	for a in pairs(table.clone(wanted)) do
		if a.Mate then
			wanted[a.Mate] = true
		end
	end
	local built = {}
	for _, a: Agent in ipairs(s.Built) do
		if wanted[a] then
			table.insert(built, a)
		else
			destroyAgent(a)
			a.Avoid, a.Behind, a.Slow, a.DogPos = 0, 0, 1, nil
		end
	end
	local builds = 0
	for _, c in ipairs(cands) do
		local a = c.A
		if wanted[a] and not a.Model and builds < BUILDS_PER_STEP then
			builds += 1
			local ok, err = pcall(buildAgent, s, a)
			if ok then
				table.insert(built, a)
				a.LastNow = 0
				animateAgent(s, a, now, obstaclesOf(s))
			else
				warn("[TownPeople] " .. tostring(err))
				destroyAgent(a)
			end
		end
	end
	s.Built = built
end

-- (rendus / tests) une image d'animation tout de suite ; `at` : heure imposée
function TownPeople.Frame(_dt: number?, position: Vector3?, at: number?)
	local s = state
	if not s or not s.Loaded then
		return
	end
	if position then
		s.Focus = position
	end
	local now = at or serverNow()
	s.Now = now
	local obstacles = obstaclesOf(s)
	for _, a: Agent in ipairs(s.Built) do
		animateAgent(s, a, now, obstacles)
	end
end

function TownPeople.Positions(): { Vector3 }
	local out = {}
	local s = state
	if s and s.Built then
		for _, a: Agent in ipairs(s.Built) do
			if a.Kind == "walk" then
				table.insert(out, a.Pos)
				if a.DogPos then
					table.insert(out, a.DogPos)
				end
			end
		end
	end
	return out
end

function TownPeople.Stop()
	local s = state
	state = nil
	if not s then
		return
	end
	if s.Conn then
		s.Conn:Disconnect()
	end
	for _, a in ipairs(s.Agents) do
		destroyAgent(a)
	end
	if s.Folder then
		s.Folder:Destroy()
	end
end

-- (tests / rendus) les personnes construites : position, état d'attente
function TownPeople.Agents(): { any }
	local out = {}
	local s = state
	for _, a: Agent in ipairs(s and s.Built or {}) do
		table.insert(out, {
			Id = a.Id,
			Kind = a.Kind,
			Pos = a.Pos,
			Waiting = a.Waiting,
			Delay = a.Delay,
			Avoid = a.Avoid,
			Lateral = a.Lateral,
			Model = a.Model,
			Anim = a.Anim,
			Style = a.Style,
			Seed = a.Seed,
			Dog = a.DogModel,
			DogPos = a.DogPos,
			Leash = a.Leash,
			Path = a.Path and (a.Path :: Path).Name or nil,
			Slow = a.Slow,
			Mate = a.Mate and a.Mate.Id or nil,
		})
	end
	return out
end

-- (tests) couloir : intervalles bloqués d'un chemin à l'abscisse s (repère du chemin)
function TownPeople.Lanes(pathName: string?, sPos: number?): any
	local s = state
	if not s then
		return nil
	end
	if pathName then
		for _, p: Path in ipairs(s.Paths) do
			if p.Name == pathName then
				return blockedAt(s, p, sPos or 0)
			end
		end
		return nil
	end
	return { Rects = #s.Rects, SolidParts = s.SolidParts, Computed = s.Computed, Stuck = s.Stuck, Zones = #s.Zones, PlazaDetour = s.PlazaDetour }
end

-- (tests) distance (XZ) de `pos` au plus proche obstacle fixe solide ou réservé
-- (négative = dedans), et sa sorte
function TownPeople.Probe(pos: Vector3): (number, number)
	local s = state
	if not s or not s.Grid then
		return math.huge, 0
	end
	local key = math.floor(pos.X / CELL) * 100003 + math.floor(pos.Z / CELL)
	local best, kind = math.huge, 0
	for _, idx in ipairs(s.Grid[key] or {}) do
		local r: Rect = s.Rects[idx]
		if r.Kind ~= 2 then
			local rx, rz = pos.X - r.CX, pos.Z - r.CZ
			local lx = math.abs(rx * r.AX + rz * r.AZ) - r.HX
			local lz = math.abs(-rx * r.AZ + rz * r.AX) - r.HZ
			local d
			if lx > 0 or lz > 0 then
				d = math.sqrt(math.max(lx, 0) ^ 2 + math.max(lz, 0) ^ 2)
			else
				d = math.max(lx, lz)
			end
			if d < best then
				best, kind = d, r.Kind
			end
		end
	end
	return best, kind
end

function TownPeople.Debug(): any
	local s = state
	if not s then
		return { Started = false }
	end
	local walkers, statics, parts = 0, 0, 0
	for _, a: Agent in ipairs(s.Agents) do
		if a.Kind == "walk" then
			walkers += 1
		else
			statics += 1
		end
	end
	for _, a: Agent in ipairs(s.Built or {}) do
		if a.Model then
			parts += NPCModels.PartCount(a.Model)
		end
		if a.DogModel then
			parts += NPCModels.PartCount(a.DogModel)
		end
		if a.Leash then
			parts += #a.Leash
		end
	end
	local names = {}
	for _, p: Path in ipairs(s.Paths) do
		table.insert(names, p.Name .. "=" .. math.floor(p.Length))
	end
	return { Agents = #s.Agents, Walkers = walkers, Statics = statics, Built = s.Built and #s.Built or 0, Parts = parts, Paths = table.concat(names, " "), Rects = #(s.Rects or {}), Stuck = s.Stuck }
end

return TownPeople
