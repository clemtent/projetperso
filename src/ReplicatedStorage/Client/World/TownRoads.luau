--[[
	TownRoads (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownRoads

	🛣️ Dopamine Town (v9.9, CITY99) : les ROUTES "100x plus réalistes",
	construites côté CLIENT, en flux autour de l'avatar (0 pièce serveur).
	Le serveur (TownStreets / TownEntrance, TownKit.LifeSpot) publie des
	emplacements par tronçons de 40 studs au plus ; TownStreetLife les
	construit avec ces fabriques (TownRoads.BUILDERS) :
	  - "RoadSurface" : l'asphalte vit : ornières plus sombres dans les
	    traces des roues, rustines de réparation (neuves plus foncées,
	    anciennes plus grises), fissures colmatées au goudron ;
	  - "CurbLine"    : caniveau en béton le long de chaque bordure +
	    bordure à nez ARRONDI (chanfrein) ;
	  - "Pavers"      : trottoirs en dalles avec leurs JOINTS et quelques
	    dalles d'une autre teinte ;
	  - "Arrow"       : flèches directionnelles peintes (tout droit, gauche,
	    droite, tout droit + droite / gauche) ;
	  - "GiveWay"     : dents de requin "cédez le passage" ;
	  - "RoadWord"    : mots peints ("STOP", "BUS", "ZONE 30", "LENT") ;
	  - "Roundabout"  : rond-point détaillé (anneau franchissable pavé,
	    bordure, balises de chevrons, lignes de cédez-le-passage, panneaux) ;
	  - "Direction"   : poteaux indicateurs à lames (flèches vraiment
	    orientées vers chaque lieu : place, fête foraine, lac, MégaDopa,
	    concession, coin gourmand, skatepark, jardins, tram...) ; les lieux
	    sont les repères "Dest" publiés par le serveur ;
	  - "Walkway"     : allée piétonne pavée (bordures, dalles, joints)
	    qui relie un lieu au réseau (pas de pelouse à traverser).
	Hauteurs au-dessus de l'asphalte (jamais deux faces à moins de 0,02) :
	ornières / caniveau 0,02 ; rustines 0,04 ; fissures 0,055 ; peinture
	(TownStreetLife, relevée en v9.9) 0,08 ; passages piétons 0,09.
	Tout est ancré, sans collision (sauf poteaux), CanQuery / CanTouch false,
	aucune lumière, aucun son.

	API (TownStreetLife) :
	  TownRoads.BUILDERS : { [kind]: (m, F, seed, spot) -> any }
	  TownRoads.BIG      : types vus de loin (rayon "gros objets")
	  TownRoads.SetDestinations(spots)   repères "Dest" (poteaux indicateurs)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local TownRoads = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)

-- Palette (mêmes tons que TownKit : asphalte 78,80,92)
local ASPHALT = rgb(78, 80, 92)
local WORN = rgb(66, 68, 78) -- traces des roues (plus sombres, lustrées)
local PATCH_NEW = rgb(56, 58, 66)
local PATCH_OLD = rgb(98, 100, 108)
local TAR = rgb(30, 30, 34)
local GUTTER = rgb(190, 188, 184)
local CURB = rgb(238, 236, 232)
local JOINT = rgb(168, 162, 156)
local WALK = rgb(216, 210, 204)
local PAINT = rgb(250, 250, 246) -- (= TownKit.C.Line : mêmes lignes que les places de stationnement)
local STEEL = rgb(170, 174, 182)
local GRAPHITE = rgb(52, 54, 60)
local WHITE = rgb(250, 250, 248)

-- Hauteurs des dessus au-dessus de l'asphalte / du trottoir : 0,03 au moins
-- entre deux niveaux qui peuvent se recouvrir (détecteur : < 0,02 = conflit)
local H_WEAR = 0.03 -- ornières, caniveau
local H_PATCH = 0.06 -- rustines
local H_CRACK = 0.09 -- fissures, joints de rustine
local H_PAINT = 0.12 -- peinture (= TownStreetLife.PAINT_TOP)
local H_SLAB = 0.03 -- dalles d'une autre teinte (trottoir)
local H_JOINT = 0.075 -- joints des dalles (trottoir)
TownRoads.H_PAINT = H_PAINT

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?, solid: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = solid == true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Parent = parent
	return p
end

-- Plaque peinte / posée : dessus à `top` au-dessus du repère, 0,2 d'épaisseur
-- (le dessous est caché dans la chaussée : jamais de face presque confondue)
-- (épaisseur 0,3 + 3 x `top` : les dessous, cachés dans la chaussée, sont
-- eux aussi tous à des hauteurs différentes)
local function flat(parent: Instance, name: string, F: CFrame, x: number, z: number, lx: number, lz: number, top: number, color: Color3, material: Enum.Material?, yaw: number?): BasePart
	local thick = 0.3 + 3 * top
	local cf = F * CFrame.new(x, top - thick / 2, z)
	if yaw then
		cf = cf * CFrame.Angles(0, yaw, 0)
	end
	return newPart(parent, name, Vector3.new(lx, thick, lz), cf, color, material)
end

-- Triangle rectangle à plat (WedgePart) : angle droit en `p0`, un côté le
-- long de `u` (longueur l1), l'autre le long de `v` (l2) ; u, v horizontaux ;
-- épaisseur `t` centrée sur le plan de p0
local function tri(parent: Instance, name: string, p0: Vector3, u: Vector3, v: Vector3, l1: number, l2: number, t: number, color: Color3): BasePart
	local Y = u
	local Z = -v
	local X = Y:Cross(Z)
	local center = p0 + u * (l1 / 2) + v * (l2 / 2)
	return wedge(parent, name, Vector3.new(t, l1, l2), CFrame.fromMatrix(center, X, Y, Z), color)
end

local function surfaceText(host: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, maxDistance: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.LightInfluence = 0.7
	gui.MaxDistance = maxDistance or 90
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = bg and 0 or 1
	label.BackgroundColor3 = bg or WHITE
	label.BorderSizePixel = 0
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBold
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	return label
end

----------------------------------------------------------------------
-- Asphalte : ornières, rustines, fissures
----------------------------------------------------------------------

-- `F` au dessus de la chaussée, X le long ; size = (longueur, voies, largeur)
local function buildRoadSurface(m: Model, F: CFrame, seed: number, spot: any)
	local size = spot and spot.Size or Vector3.new(30, 2, 16)
	local len, lanes, width = size.X, math.max(1, math.floor(size.Y + 0.5)), size.Z
	local laneW = width / lanes
	-- (zone sans rustine ni fissure le long des bordures : stationnement, caniveau)
	local keep = math.max(0.5, width / 2 - 3.5)
	-- traces des roues : deux bandes sombres par voie
	for i = 1, lanes do
		local zc = -width / 2 + laneW * (i - 0.5)
		for _, dz in ipairs({ -2.1, 2.1 }) do
			local z = zc + dz
			if math.abs(z) + 0.65 < width / 2 - 1 then
				flat(m, "Wear", F, 0, z, len, 1.3, H_WEAR, WORN, M.Asphalt)
			end
		end
	end
	-- rustines (1 tous les ~20 studs) : rectangles alignés sur la route
	local nPatch = math.floor(len / 20 + hash(seed, 1))
	local placed = {}
	for i = 1, nPatch do
		local lx = 3 + hash(seed, 10 + i) * 5
		local lz = 1.8 + hash(seed, 20 + i) * 1.8
		local x = (hash(seed, 30 + i) - 0.5) * math.max(0, len - lx - 1)
		local zr = math.max(0, keep - lz / 2)
		local z = (hash(seed, 40 + i) - 0.5) * 2 * zr
		local fresh = hash(seed, 50 + i) < 0.5
		-- (jamais deux rustines l'une sur l'autre)
		local over = false
		for _, q in ipairs(placed) do
			if math.abs(q[1] - x) < (q[3] + lx) / 2 + 0.3 and math.abs(q[2] - z) < (q[4] + lz) / 2 + 0.3 then
				over = true
			end
		end
		if over then
			continue
		end
		table.insert(placed, { x, z, lx, lz })
		flat(m, "Patch", F, x, z, lx, lz, H_PATCH, fresh and PATCH_NEW or PATCH_OLD, M.Asphalt)
		-- joint de la rustine (liseré de goudron sur deux côtés)
		if hash(seed, 55 + i) < 0.6 then
			flat(m, "PatchSeal", F, x, z - lz / 2, lx + 0.1, 0.12, H_CRACK, TAR, M.SmoothPlastic)
		end
	end
	-- fissures colmatées (lignes brisées de goudron)
	local nCrack = math.floor(len / 13 + hash(seed, 2))
	for i = 1, nCrack do
		local x = (hash(seed, 60 + i) - 0.5) * (len - 4)
		local z = (hash(seed, 70 + i) - 0.5) * 2 * math.max(0, keep - 1)
		local yaw = (hash(seed, 80 + i) - 0.5) * 1.4
		local segs = 2 + math.floor(hash(seed, 90 + i) * 2)
		for k = 1, segs do
			local l = 1.2 + hash(seed * 3 + k, 100 + i) * 2
			local dir = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
			local mid = Vector3.new(x, 0, z) + dir * (l / 2)
			if math.abs(mid.Z) < keep and math.abs(mid.X) < len / 2 - 1 then
				flat(m, "Crack", F, mid.X, mid.Z, l, 0.1, H_CRACK, TAR, M.SmoothPlastic, yaw)
			end
			x, z = x + dir.X * l, z + dir.Z * l
			yaw += (hash(seed * 7 + k, 110 + i) - 0.5) * 1.6
		end
	end
end

----------------------------------------------------------------------
-- Bordure (nez arrondi) + caniveau
----------------------------------------------------------------------

-- `F` : pied de la face de bordure, au niveau de l'asphalte ; X le long,
-- -Z vers la chaussée ; size = (longueur, hauteur de la bordure, 0)
local function buildCurbLine(m: Model, F: CFrame, _seed: number, spot: any)
	local size = spot and spot.Size or Vector3.new(30, 0.53, 0)
	local len, h = size.X, size.Y
	-- caniveau : bande de béton devant la bordure
	flat(m, "Gutter", F, 0, -0.45, len, 0.9, H_WEAR, GUTTER, M.Concrete)
	-- nez arrondi de la bordure (cylindre couché, à moitié dans la bordure)
	local nose = newPart(m, "CurbNose", Vector3.new(len, 0.26, 0.26), F * CFrame.new(0, h - 0.11, 0.03), CURB, M.Concrete, "Cyl")
	nose.CastShadow = false
end

----------------------------------------------------------------------
-- Trottoirs en dalles
----------------------------------------------------------------------

-- (défini plus bas, avec la liste du mobilier : pas de joints dessous)
local underObstacle: (p: Vector3, pad: number) -> boolean

-- `F` : dessus du trottoir, X le long ; size = (longueur, 0, largeur)
local function buildPavers(m: Model, F: CFrame, seed: number, spot: any)
	local size = spot and spot.Size or Vector3.new(30, 0, 5)
	local len, width = size.X, size.Z
	local step = 4.5
	local n = math.floor(len / step)
	local x0 = -len / 2 + (len - n * step) / 2
	for i = 0, n do
		local x = x0 + i * step
		if not underObstacle((F * CFrame.new(x, 0, 0)).Position, width / 2) then
			flat(m, "Joint", F, x, 0, 0.09, width, H_JOINT, JOINT, M.Concrete)
		end
	end
	-- joint longitudinal (dalles de 1,5 m sur 2 rangées), par morceaux libres
	if width > 4 then
		for i = 0, n - 1 do
			local x = x0 + (i + 0.5) * step
			if not underObstacle((F * CFrame.new(x, 0, 0)).Position, step / 2) then
				flat(m, "Joint", F, x, 0, step - 0.12, 0.09, H_JOINT, JOINT, M.Concrete)
			end
		end
	end
	-- quelques dalles d'une autre teinte (remplacées, plus neuves, tachées)
	for i = 0, n - 1 do
		local h = hash(seed, i)
		if h < 0.2 and not underObstacle((F * CFrame.new(x0 + (i + 0.5) * step, 0, 0)).Position, step / 2 + width / 2) then
			local tone = h < 0.1 and WALK:Lerp(WHITE, 0.35) or WALK:Lerp(GRAPHITE, 0.12)
			local half = width > 4 and (hash(seed, i + 50) < 0.5 and -1 or 1) or 0
			local lz = width > 4 and width / 2 - 0.1 or width - 0.1
			flat(m, "Slab", F, x0 + (i + 0.5) * step, half * width / 4, step - 0.1, lz, H_SLAB, tone, M.Pavement)
		end
	end
end

----------------------------------------------------------------------
-- Marquages : flèches, cédez-le-passage, mots peints
----------------------------------------------------------------------

-- Flèche peinte : `F` sur la chaussée, la flèche pointe vers -Z (sens de
-- circulation). seed : 1 tout droit, 2 gauche, 3 droite, 4 tout droit +
-- droite, 5 tout droit + gauche, 6 gauche + droite
local ARROW_TOP = H_PAINT
local PAINT_T = 0.3 -- (dessous à -0,07 : dans la chaussée)
-- pointe de flèche : triangle isocèle, base au point (x, z), pointe vers
-- la direction `yaw` (0 = -Z du repère)
local function head(m: Model, F: CFrame, x: number, z: number, yaw: number)
	local R = F * CFrame.Angles(0, 0, 0)
	local base = (R * CFrame.new(x, ARROW_TOP - PAINT_T / 2, z)).Position
	local dir = (F * CFrame.Angles(0, yaw, 0)).LookVector
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	-- (côtés dans cet ordre : l'épaisseur du coin pointe vers le bas, comme
	-- la rose des vents de la place)
	tri(m, "ArrowHead", base, side, dir, 0.75, 1.5, PAINT_T, PAINT)
	tri(m, "ArrowHead", base, -side, dir, 0.75, 1.5, PAINT_T, PAINT)
end
local function buildArrow(m: Model, F: CFrame, seed: number)
	local kind = seed % 10
	local straight = kind == 1 or kind == 4 or kind == 5
	-- fût (de +3 à -0,2), puis tout droit jusqu'à la pointe
	flat(m, "ArrowShaft", F, 0, 1.4, 0.4, 3.2, ARROW_TOP, PAINT)
	if straight then
		flat(m, "ArrowShaft", F, 0, -1.1, 0.4, 1.8, ARROW_TOP, PAINT)
		head(m, F, 0, -2.0, 0)
	end
	for _, side in ipairs({ -1, 1 }) do
		local turn = (side < 0 and (kind == 2 or kind == 5 or kind == 6)) or (side > 0 and (kind == 3 or kind == 4 or kind == 6))
		if turn then
			-- branche à 45° qui part du haut du fût, pointe dans son axe
			local bd = Vector3.new(side * 0.7071, 0, -0.7071)
			local b0 = Vector3.new(0, 0, -0.1)
			local mid = b0 + bd * 0.75
			local b1 = b0 + bd * 1.5
			local yaw = -side * math.rad(45)
			flat(m, "ArrowBranch", F, mid.X, mid.Z, 0.4, 1.7, ARROW_TOP, PAINT, nil, yaw)
			head(m, F, b1.X, b1.Z, yaw)
		end
	end
end

-- Dents de requin : `F` au milieu de la voie, les pointes vers +Z (vers
-- les voitures qui arrivent) ; seed = nombre de dents
local function buildGiveWay(m: Model, F: CFrame, seed: number)
	local n = math.max(2, seed)
	local pitch = 1.3
	local dir = F:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local side = F:VectorToWorldSpace(Vector3.new(1, 0, 0))
	for i = 0, n - 1 do
		local x = (i - (n - 1) / 2) * pitch
		local base = (F * CFrame.new(x, ARROW_TOP - PAINT_T / 2, -0.45)).Position
		tri(m, "Tooth", base, side, dir, 0.5, 0.9, PAINT_T, PAINT)
		tri(m, "Tooth", base, -side, dir, 0.5, 0.9, PAINT_T, PAINT)
	end
end

-- Mot peint (lu par le conducteur qui arrive de +Z) : 1 STOP, 2 BUS, 3 ZONE 30, 4 LENT
local WORDS = { "STOP", "BUS", "ZONE 30", "SLOW" }
local function buildRoadWord(m: Model, F: CFrame, seed: number)
	local word = WORDS[seed] or WORDS[1]
	-- (face Top : le haut du texte est vers +Z du support, donc vers le
	-- conducteur qui arrive de +Z ... qui le lit à l'endroit en avançant)
	local host = newPart(m, "RoadWord", Vector3.new(4.6, 0.05, 2.4), F * CFrame.new(0, ARROW_TOP + 0.005, 0), PAINT, M.SmoothPlastic)
	host.Transparency = 1
	local label = surfaceText(host, Enum.NormalId.Top, Locale.T(word), PAINT, nil, Enum.Font.GothamBlack, 120)
	label.TextStrokeTransparency = 1
end

----------------------------------------------------------------------
-- Rond-point
----------------------------------------------------------------------

-- `F` au centre, au niveau de l'asphalte de l'anneau ; size.X = rayon de
-- l'îlot (bordure comprise), size.Z = rayon extérieur de la chaussée ;
-- les branches entrent par +Z et -Z (route d'arrivée) : lignes de cédez
local function buildRoundabout(m: Model, F: CFrame, seed: number, spot: any)
	local size = spot and spot.Size or Vector3.new(8, 0, 20)
	local island, outer = size.X, size.Z
	-- anneau franchissable pavé (pour les camions / bus) autour de l'îlot
	local apron = island + 2.2
	local n = 24
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local mid = d * ((island + apron) / 2)
		local chord = 2 * apron * math.sin(math.pi / n) + 0.05
		local cf = F * CFrame.new(mid) * CFrame.Angles(0, a, 0)
		-- (un pavé sur deux 0,03 plus haut : les recouvrements ne scintillent pas)
		newPart(m, "Apron", Vector3.new(chord, 0.3, apron - island), cf * CFrame.new(0, 0.12 + (i % 2) * 0.03, 0), i % 2 == 0 and rgb(176, 150, 136) or rgb(160, 136, 124), M.Cobblestone)
	end
	-- balises de chevrons sur l'îlot, face aux entrées
	for _, a in ipairs({ 0, math.pi, math.pi / 2, -math.pi / 2 }) do
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local base = F * CFrame.new(d * (island - 1.4) + Vector3.new(0, 0.44, 0)) * CFrame.Angles(0, a + math.pi, 0)
		newPart(m, "ChevronPost", Vector3.new(2.2, 0.2, 0.2), base * CFrame.new(0, 1.1, 0) * UPRIGHT, GRAPHITE, M.Metal, "Cyl", true)
		local board = newPart(m, "Chevron", Vector3.new(2.4, 1.2, 0.12), base * CFrame.new(0, 2.6, -0.16), rgb(30, 60, 140), M.SmoothPlastic)
		surfaceText(board, Enum.NormalId.Back, "❯❯❯", WHITE, rgb(30, 60, 140), Enum.Font.GothamBlack, 120)
	end
	-- ligne de cédez-le-passage (pointillés) + dents de requin à l'entrée
	-- (la route d'arrivée entre par -Z)
	for i = -3, 3 do
		flat(m, "YieldDash", F, i * 1.2, -(outer - 0.6), 0.7, 0.35, ARROW_TOP, PAINT)
	end
	-- panneau "sens giratoire" à l'entrée (disque bleu), à droite en arrivant
	for _, sz in ipairs({ -1 }) do
		local base = F * CFrame.new(-9.5, -0.16, sz * (outer + 2.2)) * CFrame.Angles(0, math.pi, 0) -- (pied sur le pré)
		newPart(m, "SignPole", Vector3.new(6.6, 0.24, 0.24), base * CFrame.new(0, 3.3, 0) * UPRIGHT, STEEL, M.Metal, "Cyl", true)
		local disc = newPart(m, "SignDisc", Vector3.new(0.12, 1.9, 1.9), base * CFrame.new(0, 6.2, 0.16) * CFrame.Angles(0, math.rad(90), 0), rgb(34, 90, 190), M.SmoothPlastic, "Cyl")
		surfaceText(disc, Enum.NormalId.Right, "⟳", WHITE, nil, Enum.Font.GothamBlack, 90)
		surfaceText(disc, Enum.NormalId.Left, "⟳", WHITE, nil, Enum.Font.GothamBlack, 90)
	end
	local _ = seed
end

----------------------------------------------------------------------
-- Poteaux indicateurs vers les lieux de la ville
----------------------------------------------------------------------

type Dest = { Id: number, Pos: Vector3 }
local destinations: { Dest } = {}
-- (dalles : pas de joints sous le mobilier ni sur les bandes podotactiles des passages piétons)
local obstacles: { { any } } = {}
local OBSTACLE_R = {
	Zebra = -1, -- (rayon : demi-largeur de la route + 3)
	BusShelter = 5.5,
	Kiosk = 5,
	Terrace = 7,
	Morris = 2.4,
	PhoneBooth = 2.4,
	Vending = 2,
	Bench = 3.4,
	Planter = 3.4,
	Recycle = 2.4,
	TrafficLight = 1.6,
	Beacon = 1.2,
	StreetName = 1.2,
	Direction = 1.2,
	Bin = 1.3,
	Mailbox = 1.2,
	NewsBox = 1.2,
	Bollards = 2.2,
	ParkMeter = 1,
	SpeedSign = 1,
	DogStation = 1.2,
	DrinkFountain = 1.4,
	Lamppost = 1.2,
	PlanterSmall = 1.4,
	FlowerStall = 4,
	BookStall = 4,
}

-- Lieux (seed du repère "Dest") : emoji + nom anglais (Locale -> français)
TownRoads.PLACES = {
	[1] = { "⛲", "Main square" },
	[2] = { "🎡", "Fun fair" },
	[3] = { "🎪", "Circus" },
	[4] = { "🦆", "Lake" },
	[5] = { "🛝", "Playground" },
	[6] = { "🛒", "MégaDopa" },
	[7] = { "🚗", "Car dealer" },
	[8] = { "🍦", "Food corner" },
	[9] = { "🛹", "Skate park" },
	[10] = { "🥕", "Community gardens" },
	[11] = { "🚋", "Tram" },
	[12] = { "⚽", "Sports ground" },
	[13] = { "🏠", "Houses" },
	[14] = { "🌷", "Flower garden" },
	[15] = { "🏰", "Town gate" },
	[16] = { "🧺", "Market" },
	[17] = { "🏓", "Sports corner" },
}

function TownRoads.SetDestinations(spots: { any })
	table.clear(destinations)
	table.clear(obstacles)
	for _, s in ipairs(spots) do
		if s.Kind == "Dest" then
			table.insert(destinations, { Id = s.Seed, Pos = s.Pos })
		end
		local r = OBSTACLE_R[s.Kind]
		if r then
			if r < 0 then
				r = (s.Seed or 100) / 20 + 3
			end
			table.insert(obstacles, { s.Pos, r })
		end
	end
end

underObstacle = function(p: Vector3, pad: number): boolean
	for _, o in ipairs(obstacles) do
		local q: Vector3 = o[1]
		if Vector3.new(p.X - q.X, 0, p.Z - q.Z).Magnitude < o[2] + pad then
			return true
		end
	end
	return false
end

-- (v11, CITY11) obstacles hauts autour d'un poteau : lampadaires du serveur
-- (modèles "Lamp" de TownKit, lus une fois) + mobilier publié (obstacles)
local serverLamps: { Vector3 }? = nil
local function lampsNear(here: Vector3, r: number): { { any } }
	if not serverLamps then
		local list = {}
		local town = workspace:FindFirstChild("DopamineTown")
		if town then
			for _, d in ipairs(town:GetDescendants()) do
				if d:IsA("Model") and (d.Name == "Lamp" or d.Name == "Lamppost") then
					local pole = d:FindFirstChild("Pole") or d:FindFirstChild("Foot")
					if pole and pole:IsA("BasePart") then
						table.insert(list, pole.Position)
					end
				end
			end
		end
		serverLamps = list
	end
	local out = {}
	for _, q in ipairs(serverLamps :: { Vector3 }) do
		if Vector3.new(q.X - here.X, 0, q.Z - here.Z).Magnitude < r then
			table.insert(out, { q, 0.45 })
		end
	end
	for _, o in ipairs(obstacles) do
		local q: Vector3 = o[1]
		local d = Vector3.new(q.X - here.X, 0, q.Z - here.Z).Magnitude
		if d > 0.3 and d < r and o[2] > 0 then
			table.insert(out, { q, math.min(o[2], 1.2) })
		end
	end
	return out
end

TownRoads.LampsNear = lampsNear -- (v11) TownStreetLife : trottoirs jamais pincés

-- distance (plan) d'un point au segment [a, b]
local function segDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local l2 = ab:Dot(ab)
	local t = l2 > 0 and math.clamp(ap:Dot(ab) / l2, 0, 1) or 0
	return (ap - ab * t).Magnitude
end

-- Poteau indicateur (v11, CITY11, refait — capture 33 : flèches qui
-- "flottaient" à côté du poteau, pointes à l'envers, lames dans les
-- lampadaires voisins). Maintenant :
--   - socle en fonte + collerette, fût Ø 0,42, bagues, épi de faîtage ;
--   - chaque lame est ENFILÉE dans un collier serré sur le fût (elle part
--     de l'axe : aucun jour entre le poteau et la lame), bordure claire,
--     vraie POINTE de flèche (deux coins, même épaisseur que la lame,
--     collés au bout : un seul contour) ;
--   - lames espacées de 1,25 (hauteur 0,95 : jamais l'une sur l'autre) ;
--   - une lame qui passerait dans un lampadaire / un abribus voisin est
--     remplacée par le lieu suivant (jamais de chevauchement) ;
--   - texte des deux côtés (nom à gauche, distance dans une pastille).
-- `F` au pied (dessus du sol) ; jusqu'à 4 lames vers les lieux les plus
-- proches (au-delà de 25 studs), un par type de lieu
local BLADE_LEN = 4.1 -- (depuis l'axe du poteau)
local BLADE_TIP = 0.7
local BLADE_H = 0.95
local BLADE_T = 0.14
local BLADE_GAP = 1.25
local function buildDirection(m: Model, F: CFrame, seed: number)
	local here = F.Position
	local cand = {}
	local seen = {}
	for _, d in ipairs(destinations) do
		local dist = Vector3.new(d.Pos.X - here.X, 0, d.Pos.Z - here.Z).Magnitude
		if dist > 25 and TownRoads.PLACES[d.Id] then
			local prev = seen[d.Id]
			if not prev or prev.Dist > dist then
				seen[d.Id] = { Dest = d, Dist = dist }
			end
		end
	end
	for _, v in pairs(seen) do
		table.insert(cand, v)
	end
	table.sort(cand, function(a, b)
		-- (les grands lieux d'abord, puis les plus proches ; ordre stable)
		local pa = (a.Dest.Id <= 8) and 0 or 1
		local pb = (b.Dest.Id <= 8) and 0 or 1
		if pa ~= pb then
			return pa < pb
		end
		if math.abs(a.Dist - b.Dist) > 1e-3 then
			return a.Dist < b.Dist
		end
		return a.Dest.Id < b.Dest.Id
	end)
	local pole = rgb(34, 40, 50)
	local gold = rgb(200, 168, 92)
	local up = CFrame.new(here)
	-- socle, collerette, fût, bagues, épi
	newPart(m, "DirBase", Vector3.new(0.5, 1.15, 1.15), up * CFrame.new(0, 0.2, 0) * UPRIGHT, pole, M.Metal, "Cyl", true)
	newPart(m, "DirCollar", Vector3.new(0.8, 0.7, 0.7), up * CFrame.new(0, 0.8, 0) * UPRIGHT, pole, M.Metal, "Cyl")
	newPart(m, "DirPole", Vector3.new(10.6, 0.42, 0.42), up * CFrame.new(0, 5.5, 0) * UPRIGHT, pole, M.Metal, "Cyl", true)
	newPart(m, "DirRing", Vector3.new(0.18, 0.54, 0.54), up * CFrame.new(0, 2.6, 0) * UPRIGHT, gold, M.Metal, "Cyl")
	newPart(m, "DirCapRing", Vector3.new(0.22, 0.56, 0.56), up * CFrame.new(0, 10.75, 0) * UPRIGHT, gold, M.Metal, "Cyl")
	newPart(m, "DirCap", Vector3.new(0.62, 0.62, 0.62), up * CFrame.new(0, 11.1, 0), pole, M.Metal, "Ball")
	newPart(m, "DirFinial", Vector3.new(0.34, 0.34, 0.34), up * CFrame.new(0, 11.55, 0), gold, M.Metal, "Ball")
	-- lames : on garde les lieux dont la lame passe libre
	local near = lampsNear(here, BLADE_LEN + BLADE_TIP + 2)
	local colors = { rgb(26, 74, 140), rgb(28, 104, 78), rgb(146, 44, 74), rgb(110, 64, 146) }
	local placed = 0
	for _, c in ipairs(cand) do
		if placed >= 4 then
			break
		end
		local rel = c.Dest.Pos - here
		local dir = Vector3.new(rel.X, 0, rel.Z).Unit
		local tip = here + dir * (BLADE_LEN + BLADE_TIP)
		local clear = true
		for _, o in ipairs(near) do
			if segDist(o[1], here, tip) < o[2] + 0.55 then
				clear = false
				break
			end
		end
		if clear then
			placed += 1
			local yaw = math.atan2(-rel.X, -rel.Z) -- (lame vers -Z du repère tourné)
			local y = 9.95 - (placed - 1) * BLADE_GAP
			local R = up * CFrame.Angles(0, yaw, 0) * CFrame.new(0, y, 0)
			local color = colors[(placed + seed) % #colors + 1]
			-- collier serré sur le fût (la lame y entre)
			newPart(m, "DirClamp", Vector3.new(BLADE_H + 0.12, 0.6, 0.6), R * UPRIGHT, pole, M.Metal, "Cyl")
			-- lame : de l'axe du poteau (z = 0) jusqu'à -BLADE_LEN
			local blade = newPart(m, "DirBlade", Vector3.new(BLADE_T, BLADE_H, BLADE_LEN), R * CFrame.new(0, 0, -BLADE_LEN / 2), color, M.SmoothPlastic)
			-- pointe : moitié haute + moitié basse, collées au bout de la lame
			local zt = -BLADE_LEN - BLADE_TIP / 2
			wedge(m, "DirTip", Vector3.new(BLADE_T, BLADE_H / 2, BLADE_TIP), R * CFrame.new(0, BLADE_H / 4, zt), color, M.SmoothPlastic)
			wedge(m, "DirTip", Vector3.new(BLADE_T, BLADE_H / 2, BLADE_TIP), R * CFrame.new(0, -BLADE_H / 4, zt) * CFrame.Angles(0, 0, math.pi), color, M.SmoothPlastic)
			local place = TownRoads.PLACES[c.Dest.Id]
			local meters = math.max(10, math.floor(c.Dist * 0.33 / 10 + 0.5) * 10)
			-- texte : des deux côtés, à l'écart du collier (0,45) ; nom + pastille
			for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
				local gui = Instance.new("SurfaceGui")
				gui.Name = "Text"
				gui.Face = face
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 48
				gui.LightInfluence = 0.65
				gui.MaxDistance = 90
				gui.Parent = blade
				-- bordure claire (liseré dessiné : aucune pièce en plus)
				local edge = Instance.new("Frame")
				edge.Name = "Edge"
				edge.BackgroundTransparency = 1
				edge.Position = UDim2.fromScale(face == Enum.NormalId.Right and 0.45 / BLADE_LEN or 0.01, 0.06)
				edge.Size = UDim2.fromScale(1 - 0.45 / BLADE_LEN - 0.01, 0.88)
				edge.Parent = gui
				local stroke = Instance.new("UIStroke")
				stroke.Color = rgb(246, 244, 236)
				stroke.Thickness = 3
				stroke.Parent = edge
				-- (face Right : on lit vers la pointe ; face Left : vers le poteau)
				local towardTip = face == Enum.NormalId.Right
				local pad = 0.45 / BLADE_LEN
				local name = Instance.new("TextLabel")
				name.Name = "Name"
				name.BackgroundTransparency = 1
				name.Position = UDim2.fromScale(towardTip and pad + 0.02 or 0.3, 0.12)
				name.Size = UDim2.fromScale(0.68 - pad, 0.76)
				name.TextScaled = true
				name.Font = Enum.Font.GothamBold
				name.TextColor3 = WHITE
				name.TextXAlignment = towardTip and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
				name.Text = place[1] .. " " .. Locale.T(place[2])
				name.Parent = gui
				local pill = Instance.new("TextLabel")
				pill.Name = "Distance"
				pill.BackgroundColor3 = rgb(250, 248, 240)
				pill.BorderSizePixel = 0
				pill.Position = UDim2.fromScale(towardTip and 0.72 or 0.02, 0.2)
				pill.Size = UDim2.fromScale(0.25, 0.6)
				pill.TextScaled = true
				pill.Font = Enum.Font.GothamBlack
				pill.TextColor3 = color
				pill.Text = meters .. " m"
				pill.Parent = gui
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.4, 0)
				corner.Parent = pill
			end
		end
	end
end

----------------------------------------------------------------------
-- Allée piétonne pavée
----------------------------------------------------------------------

-- `F` au milieu de l'allée, sur le sol (dessus du pré) ; X le long ;
-- size = (longueur, style, largeur) ; style 1 = dalles grises, 2 = pavés
-- ocre (parc), 3 = caillebotis bois, 4 = bitume (accès de parking)
local function buildWalkway(m: Model, F: CFrame, seed: number, spot: any)
	local size = spot and spot.Size or Vector3.new(20, 1, 5)
	local len, style, width = size.X, math.floor(size.Y + 0.5), size.Z
	local top = 0.14
	local body = style == 2 and rgb(222, 204, 176) or (style == 3 and rgb(170, 124, 84) or (style == 4 and ASPHALT or rgb(206, 202, 196)))
	local mat = style == 2 and M.Cobblestone or (style == 3 and M.WoodPlanks or (style == 4 and M.Asphalt or M.Pavement))
	newPart(m, "WalkBed", Vector3.new(len, 0.4, width), F * CFrame.new(0, top - 0.2, 0), body, mat)
	-- bordures (0,06 plus hautes)
	for _, sz in ipairs({ -1, 1 }) do
		-- (bordure un peu plus courte que le lit et qui dépasse de 0,05 sur le
		-- côté : aucune face confondue avec lui)
		newPart(m, "WalkEdge", Vector3.new(len - 0.1, 0.4, 0.3), F * CFrame.new(0, top + 0.06 - 0.2, sz * (width / 2 - 0.1)), style == 3 and rgb(120, 86, 58) or rgb(150, 146, 140), style == 3 and M.Wood or M.Concrete)
	end
	if style ~= 3 and style ~= 4 then
		-- joints tous les 3 studs
		local n = math.floor(len / 3)
		for i = 1, n - 1 do
			flat(m, "WalkJoint", F, -len / 2 + i * len / n, 0, 0.08, width - 0.62, top + 0.025, rgb(150, 144, 136), M.Concrete)
		end
	end
	local _ = seed
end

TownRoads.BUILDERS = {
	RoadSurface = buildRoadSurface,
	CurbLine = buildCurbLine,
	Pavers = buildPavers,
	Arrow = buildArrow,
	GiveWay = buildGiveWay,
	RoadWord = buildRoadWord,
	Roundabout = buildRoundabout,
	Direction = buildDirection,
	Walkway = buildWalkway,
}

-- (vus de plus loin : grandes surfaces, poteaux indicateurs)
TownRoads.BIG = { RoadSurface = true, Walkway = true, Roundabout = true, Direction = true }

return TownRoads
