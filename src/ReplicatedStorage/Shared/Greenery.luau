--[[
	Greenery (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Greenery

	🌳 Les arbres de Dopamine Town (v9.7, NATURE97), "réalistes stylisés",
	construits en pièces : utilisé par le SERVEUR (TownKit.Tree : les arbres
	de la ville) ET par le CLIENT (TownGreenery : détails "de près").
	Pur : que des Instances, aucun service.

	Chaque arbre = tronc (évasé au pied), 2 à 4 branches, feuillage en
	plusieurs grappes qui se chevauchent (boules / ovales = Part + SpecialMesh
	"Sphere") en 2-3 verts : silhouette irrégulière. Espèces :
	  Oak     : chêne rond, large ;
	  Maple   : érable d'automne (orange, rouge, jaune) ;
	  Cherry  : cerisier en fleurs (roses), en parasol, pétales au sol ;
	  Birch   : bouleau (tronc blanc à marques noires), feuillage clair ;
	  Fir     : sapin (étages de plus en plus petits + pointe) ;
	  Palm    : palmier (tronc courbé en anneaux, palmes, noix de coco) ;
	  Poplar  : peuplier (haut et fin) ;
	  Fruit   : pommier (petit, rond, pommes rouges / oranges) ;
	  Willow  : saule pleureur (dôme + rideaux qui tombent) ;
	  Round   : boule taillée (jardinières de la place).
	La taille, la rotation, les teintes et les grappes varient avec la
	graine (`seed`) : même arbre pour tout le monde, à chaque démarrage.

	NIVEAUX DE DÉTAIL (budget de pièces de la ville) :
	  0 : silhouette (tronc + 2-4 grappes) — ce qu'on voit de loin ;
	  1 : + branches, grappe du sommet, palmes... (arbres "vedettes") ;
	  2 : + évasement du pied, branche et petites grappes en plus, fruits,
	      marques du bouleau, noix de coco, pétales : ajouté par le CLIENT
	      (TownGreenery) seulement pour les arbres proches de l'avatar.
	Les pièces des niveaux 1-2 ne touchent jamais une face plane d'une
	pièce d'un autre niveau (pas de z-fighting) : grappes rondes, tiges
	cylindriques, anneaux aux hauteurs distinctes.

	API :
	  Greenery.SPECIES : { string } (ordre de la galerie)
	  Greenery.Species(kind, seed) -> string
	      kind : nom d'espèce, ou ancien numéro v9.4 (1 feuillu, 2 cerisier,
	      3 sapin, 4 boule taillée)
	  Greenery.Tree(parent, base, height, seed, species, maxTier, minTier?, opts?) -> (Model, number)
	      base = pied du tronc (sol) ; construit les niveaux minTier..maxTier ;
	      opts = { Lawn = bool (pétales / feuilles au sol permis), Name = string? }
	      Renvoie le modèle et son nombre de pièces. Attributs du modèle :
	      TreeSpecies, TreeHeight, TreeSeed, TreeTier (niveau max construit),
	      TreeBase (Vector3), TreeLawn.
	  Greenery.Hash(a, b?) -> 0..1 (même formule que TownKit.Hash)
]]

local Greenery = {}

local M = Enum.Material
local V = Vector3.new
local TAU = math.pi * 2

Greenery.NEAR_TIER = 2

-- Plan du LAC du parc (v9.7), partagé serveur (TownNature) / client
-- (TownGreenery : nénuphars, canards, cygnes, roseaux de près). Repère du
-- lac (attribut "DetailCF" du modèle Lake) : origine = centre au niveau du
-- pré, X = le long de la rive, Z = en s'éloignant de la place ; les
-- valeurs sont des fractions du rayon R (attribut "DetailR").
Greenery.LAKE = {
	BridgeX = -0.22, -- (pont : de z = -(R+5) à z = R+5)
	BridgeHalfW = 3.2,
	Island = { 0.36, 0.14, 0.2 }, -- x, z, rayon
	Jet = { 0.18, -0.42 },
	DockZ = -0.34, -- (ponton : le long de x, depuis la rive +X)
	WaterTop = 0.4, -- (au-dessus du pré)
}

Greenery.SPECIES = { "Oak", "Maple", "Cherry", "Birch", "Fir", "Palm", "Poplar", "Fruit", "Willow", "Round" }

local function hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end
Greenery.Hash = hash

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Palettes (2-3 teintes par arbre : ombre, milieu, lumière)
local PAL = {
	Oak = { { rgb(84, 148, 72), rgb(104, 168, 82), rgb(132, 190, 96) }, { rgb(72, 136, 76), rgb(94, 158, 80), rgb(122, 182, 92) }, { rgb(92, 150, 64), rgb(116, 170, 74), rgb(146, 196, 94) } },
	Maple = { { rgb(206, 78, 58), rgb(236, 124, 62), rgb(248, 178, 76) }, { rgb(190, 64, 70), rgb(226, 98, 64), rgb(244, 150, 70) }, { rgb(214, 120, 52), rgb(240, 166, 66), rgb(250, 208, 102) } },
	Cherry = { { rgb(240, 150, 186), rgb(255, 180, 208), rgb(255, 216, 230) }, { rgb(232, 138, 180), rgb(250, 168, 202), rgb(255, 206, 226) } },
	Birch = { { rgb(128, 178, 84), rgb(152, 198, 96), rgb(184, 216, 110) }, { rgb(140, 186, 76), rgb(166, 204, 92), rgb(198, 222, 116) } },
	Fir = { { rgb(40, 96, 72), rgb(52, 114, 82), rgb(70, 134, 92) }, { rgb(46, 104, 80), rgb(60, 124, 88), rgb(82, 146, 98) } },
	Palm = { { rgb(80, 150, 64), rgb(104, 172, 72), rgb(136, 194, 86) } },
	Poplar = { { rgb(84, 144, 64), rgb(108, 166, 74), rgb(136, 186, 86) }, { rgb(96, 152, 70), rgb(120, 172, 80), rgb(154, 196, 92) } },
	Fruit = { { rgb(80, 146, 70), rgb(102, 166, 80), rgb(130, 188, 92) } },
	Willow = { { rgb(116, 170, 88), rgb(140, 190, 100), rgb(170, 208, 112) } },
	Round = { { rgb(78, 146, 78), rgb(98, 164, 86), rgb(124, 184, 96) } },
}
local BARK = rgb(116, 84, 62)
local BARK_DARK = rgb(92, 66, 52)
local BARK_CHERRY = rgb(104, 70, 68)
local BIRCH_BARK = rgb(238, 234, 226)
local BIRCH_MARK = rgb(58, 54, 60)
local PALM_BARK = rgb(168, 130, 92)
local PALM_RING = rgb(140, 104, 74)
local FRUITS = { rgb(222, 52, 62), rgb(236, 72, 58), rgb(246, 150, 52) }

----------------------------------------------------------------------
-- Descriptions de pièces (repère local de l'arbre : pied au sol, 0,0,0)
----------------------------------------------------------------------

type Spec = {
	Tier: number,
	Kind: string, -- "Ball" | "Egg" | "Cyl" | "Block"
	Name: string,
	Size: Vector3,
	CF: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Profile: string, -- "prop" (solide) | "deco" | "decoS" (décor qui garde son ombre)
	Transparency: number?,
}

local function dir(angle: number): Vector3
	return V(math.cos(angle), 0, math.sin(angle))
end

local function add(list: { Spec }, tier: number, kind: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, profile: string)
	table.insert(list, { Tier = tier, Kind = kind, Name = name, Size = size, CF = cf, Color = color, Material = material, Profile = profile })
end

local function ball(list: { Spec }, tier: number, name: string, center: Vector3, d: number, color: Color3, profile: string?)
	add(list, tier, "Ball", name, V(d, d, d), CFrame.new(center), color, M.Grass, profile or "deco")
end

-- (grappes / étages : chaque ovale tourne un peu sur lui-même, d'un angle
-- différent de ses voisins : même un détecteur qui prendrait l'ovale pour
-- sa boîte n'y trouverait aucune face parallèle confondue ; palmes, rideaux
-- et racines gardent leur orientation)
local SPIN = { Crown = true, CrownTop = true, Cluster = true, Tier = true, Tip = true, Bough = true, Petals = true }
local function egg(list: { Spec }, tier: number, name: string, cf: CFrame, size: Vector3, color: Color3, profile: string?, material: Enum.Material?)
	local c = SPIN[name] and cf * CFrame.Angles(0, 0.3 + (#list % 7) * 0.33, 0) or cf
	add(list, tier, "Egg", name, size, c, color, material or M.Grass, profile or "deco")
end

-- cylindre debout (pied `bottom`)
local function column(list: { Spec }, tier: number, name: string, bottom: Vector3, height: number, d: number, color: Color3, material: Enum.Material, profile: string)
	add(list, tier, "Cyl", name, V(height, d, d), CFrame.new(bottom + V(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, material, profile)
end

-- tige cylindrique de a à b (dépasse de `over` aux deux bouts : joints cachés)
local function rod(list: { Spec }, tier: number, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material, profile: string?, over: number?)
	local axis = (b - a).Unit
	local e = over or 0
	local a2, b2 = a - axis * e, b + axis * e
	local mid = (a2 + b2) / 2
	local up = math.abs(axis.Y) > 0.98 and V(1, 0, 0) or V(0, 1, 0)
	local cf = CFrame.lookAt(mid, b2, up) * CFrame.Angles(0, math.pi / 2, 0)
	add(list, tier, "Cyl", name, V((b2 - a2).Magnitude, d, d), cf, color, material, profile or "deco")
end

----------------------------------------------------------------------
-- Espèces
----------------------------------------------------------------------

type Ctx = { H: number, Seed: number, A: number, R: (k: number) -> number, P: { Color3 }, Lawn: boolean }

-- pied évasé (de près) : 3 racines = ovales couchés qui partent du tronc
local function roots(list: { Spec }, c: Ctx, d: number, color: Color3, material: Enum.Material?)
	for k = 0, 2 do
		local b = c.A + 0.6 + k * TAU / 3 + c.R(120 + k) * 0.5
		local cf = CFrame.new(dir(b) * d * 0.52 + V(0, 0.04, 0)) * CFrame.Angles(0, -b, 0) * CFrame.Angles(0, 0, math.rad(-14))
		egg(list, 2, "Root", cf, V(d * 1.5, d * 0.62, d * 0.7), color, "deco", material or M.Wood)
	end
end

-- Feuillus ronds : chêne, érable, pommier
local function broadleaf(list: { Spec }, c: Ctx, species: string)
	local H, A, R, P = c.H, c.A, c.R, c.P
	local fruit = species == "Fruit"
	local tH = H * (fruit and 0.34 or 0.42)
	local d = fruit and (0.4 + H * 0.05) or (0.5 + H * 0.06)
	local s = 0.92 + R(9) * 0.16 -- (grappes un peu plus ou moins fournies)
	local bark = fruit and BARK_DARK or BARK
	column(list, 0, "Trunk", V(0, -0.2, 0), tH + H * 0.2 + 0.2, d, bark, M.Wood, "prop")
	-- branches : de la fourche vers le cœur des grappes
	local fork = V(0, tH * 0.86, 0)
	local p1 = dir(A) * H * 0.26 + V(0, H * 0.64, 0)
	local p2 = dir(A + 2.4 + R(3) * 0.4) * H * 0.24 + V(0, H * 0.6, 0)
	local p3 = dir(A + 4.3 + R(4) * 0.3) * H * 0.2 + V(0, H * 0.56, 0)
	rod(list, 1, "Branch", fork, p1, d * 0.5, bark, M.Wood)
	rod(list, 1, "Branch", fork + V(0, H * 0.03, 0), p2, d * 0.46, bark, M.Wood)
	rod(list, 2, "Branch", fork - V(0, H * 0.04, 0), p3, d * 0.4, bark, M.Wood)
	-- évasement du pied (ovale à moitié enterré)
	roots(list, c, d, bark, M.Wood)
	-- grappes
	local mid, dark, light = P[2], P[1], P[3]
	if species == "Maple" then
		-- (érable : grappes de teintes différentes, comme en automne)
		mid, dark, light = P[2], P[1], P[3]
	end
	ball(list, 0, "Crown", V(0, H * 0.72, 0) + dir(A + 1.2) * H * 0.03, H * 0.54 * s, mid, "decoS")
	ball(list, 0, "Crown", p1 + V(0, H * 0.04, 0), H * 0.42 * s, light, "decoS")
	ball(list, 0, "Crown", p2 + V(0, H * 0.03, 0), H * 0.4 * s, dark, "decoS")
	ball(list, 1, "CrownTop", V(0, H * 0.9, 0) + dir(A + 3.4) * H * 0.07, H * 0.34 * s, light:Lerp(mid, 0.3))
	ball(list, 2, "Cluster", p3 + V(0, H * 0.02, 0), H * 0.3 * s, dark:Lerp(mid, 0.4))
	ball(list, 2, "Cluster", dir(A + 1.1) * H * 0.3 + V(0, H * 0.8, 0), H * 0.24 * s, light)
	ball(list, 2, "Cluster", dir(A + 5.2) * H * 0.2 + V(0, H * 0.96, 0), H * 0.2 * s, mid:Lerp(light, 0.5))
	if fruit then
		-- pommes posées à la surface des grappes (sous l'équateur)
		local centers = { { V(0, H * 0.72, 0), H * 0.27 * s }, { p1 + V(0, H * 0.04, 0), H * 0.21 * s }, { p2 + V(0, H * 0.03, 0), H * 0.2 * s } }
		for i = 1, 7 do
			local ctr = centers[i % 3 + 1]
			local ang = A + i * 1.9 + R(20 + i)
			local rr = ctr[2]
			local p = ctr[1] + dir(ang) * rr * 0.88 - V(0, rr * 0.47, 0)
			ball(list, 2, "Apple", p, 0.7 + H * 0.02, FRUITS[i % #FRUITS + 1], "deco")
		end
	end
end

local function cherry(list: { Spec }, c: Ctx)
	local H, A, R, P = c.H, c.A, c.R, c.P
	local tH = H * 0.4
	local d = 0.4 + H * 0.06
	local s = 0.92 + R(9) * 0.16
	column(list, 0, "Trunk", V(0, -0.2, 0), tH + H * 0.12 + 0.2, d, BARK_CHERRY, M.Wood, "prop")
	local fork = V(0, tH * 0.92, 0)
	local tips = {}
	for k = 0, 2 do
		tips[k + 1] = dir(A + k * 2.1 + R(5 + k) * 0.5) * H * (0.28 + R(8 + k) * 0.06) + V(0, H * (0.57 + k * 0.03), 0)
	end
	rod(list, 1, "Branch", fork, tips[1], d * 0.45, BARK_CHERRY, M.Wood)
	rod(list, 1, "Branch", fork + V(0, H * 0.02, 0), tips[2], d * 0.42, BARK_CHERRY, M.Wood)
	rod(list, 2, "Branch", fork - V(0, H * 0.02, 0), tips[3], d * 0.4, BARK_CHERRY, M.Wood)
	roots(list, c, d, BARK_CHERRY, M.Wood)
	local yaw = CFrame.Angles(0, -A, 0)
	egg(list, 0, "Crown", CFrame.new(0, H * 0.71, 0) * yaw, V(H * 0.64, H * 0.36, H * 0.56) * s, P[2], "decoS")
	egg(list, 0, "Crown", CFrame.new(tips[1] + V(0, H * 0.06, 0)) * yaw, V(H * 0.42, H * 0.27, H * 0.38) * s, P[3], "decoS")
	egg(list, 0, "Crown", CFrame.new(tips[2] + V(0, H * 0.085, 0)) * yaw, V(H * 0.4, H * 0.26, H * 0.36) * s, P[1], "decoS")
	egg(list, 1, "CrownTop", CFrame.new(dir(A + 3.6) * H * 0.06 + V(0, H * 0.89, 0)) * yaw, V(H * 0.36, H * 0.22, H * 0.34) * s, P[3])
	egg(list, 2, "Cluster", CFrame.new(tips[3] + V(0, H * 0.05, 0)) * yaw, V(H * 0.3, H * 0.2, H * 0.3) * s, P[2]:Lerp(P[1], 0.5))
	egg(list, 2, "Cluster", CFrame.new(dir(A + 0.9) * H * 0.3 + V(0, H * 0.835, 0)) * yaw, V(H * 0.24, H * 0.16, H * 0.24) * s, P[3])
	if c.Lawn then
		-- pétales tombés : taches roses à plat sur la pelouse
		for k = 0, 2 do
			local p = dir(A + k * 2.3 + R(30 + k)) * H * (0.2 + R(33 + k) * 0.14) + V(0, 0.06, 0)
			egg(list, 2, "Petals", CFrame.new(p) * CFrame.Angles(0, R(36 + k) * TAU, 0), V(H * 0.22, 0.12, H * 0.16), P[3], "deco", M.SmoothPlastic)
		end
	end
end

local function birch(list: { Spec }, c: Ctx)
	local H, A, R, P = c.H, c.A, c.R, c.P
	local d = 0.3 + H * 0.04
	column(list, 0, "Trunk", V(0, -0.2, 0), H * 0.8 + 0.2, d, BIRCH_BARK, M.SmoothPlastic, "prop")
	-- marques noires : petits traits posés sur l'écorce (tangents au tronc)
	for k = 1, 7 do
		local b = A + k * 2.4 + R(40 + k)
		local y = H * (0.06 + k * 0.07) + R(44 + k) * 0.5
		local cf = CFrame.new(dir(b) * (d / 2 - 0.02) + V(0, y, 0)) * CFrame.Angles(0, math.pi / 2 - b, 0)
		add(list, 2, "Block", "BarkMark", V(d * (0.35 + R(48 + k) * 0.3), 0.1 + R(52 + k) * 0.08, 0.1), cf, BIRCH_MARK, M.SmoothPlastic, "deco")
	end
	local b1 = dir(A) * H * 0.18 + V(0, H * 0.7, 0)
	local b2 = dir(A + 2.6 + R(3) * 0.5) * H * 0.17 + V(0, H * 0.64, 0)
	rod(list, 1, "Branch", V(0, H * 0.5, 0), b1, d * 0.45, BIRCH_BARK, M.SmoothPlastic)
	rod(list, 1, "Branch", V(0, H * 0.46, 0), b2, d * 0.42, BIRCH_BARK, M.SmoothPlastic)
	roots(list, c, d, BIRCH_BARK, M.SmoothPlastic)
	local yaw = CFrame.Angles(0, -A, 0)
	egg(list, 0, "Crown", CFrame.new(0, H * 0.74, 0) * yaw, V(H * 0.34, H * 0.46, H * 0.32), P[2], "decoS")
	egg(list, 0, "Crown", CFrame.new(b1 + V(0, H * 0.04, 0)) * yaw, V(H * 0.28, H * 0.34, H * 0.26), P[3], "decoS")
	egg(list, 0, "Crown", CFrame.new(b2 + V(0, H * 0.02, 0)) * yaw, V(H * 0.26, H * 0.32, H * 0.26), P[1], "decoS")
	egg(list, 1, "CrownTop", CFrame.new(dir(A + 4) * H * 0.04 + V(0, H * 0.95, 0)) * yaw, V(H * 0.2, H * 0.26, H * 0.2), P[3])
	egg(list, 2, "Cluster", CFrame.new(dir(A + 1.5) * H * 0.15 + V(0, H * 0.56, 0)) * yaw, V(H * 0.2, H * 0.22, H * 0.2), P[1]:Lerp(P[2], 0.5))
	egg(list, 2, "Cluster", CFrame.new(dir(A + 4.4) * H * 0.16 + V(0, H * 0.84, 0)) * yaw, V(H * 0.18, H * 0.2, H * 0.18), P[2])
end

local function fir(list: { Spec }, c: Ctx)
	local H, A, R, P = c.H, c.A, c.R, c.P
	local d = 0.35 + H * 0.05
	local w = 0.94 + R(9) * 0.12
	column(list, 0, "Trunk", V(0, -0.2, 0), H * 0.62 + 0.2, d, BARK_DARK, M.Wood, "prop")
	roots(list, c, d, BARK_DARK, M.Wood)
	-- étages : ovales aplatis de plus en plus petits (légèrement tournés)
	local tiers = {
		{ 0.24, 0.66, 0.28, P[1] },
		{ 0.39, 0.54, 0.27, P[2] },
		{ 0.53, 0.42, 0.26, P[1]:Lerp(P[2], 0.5) },
		{ 0.66, 0.3, 0.25, P[2]:Lerp(P[3], 0.4) },
	}
	for i, t in ipairs(tiers) do
		local cf = CFrame.new(dir(A + i * 2) * H * 0.012 + V(0, H * t[1], 0)) * CFrame.Angles(0, -A - i * 0.7, 0)
		egg(list, 0, "Tier", cf, V(H * t[2] * w, H * t[3], H * t[2] * w * 0.94), t[4], i == 1 and "decoS" or "deco")
	end
	egg(list, 1, "Tip", CFrame.new(0, H * 0.82, 0), V(H * 0.17, H * 0.34, H * 0.17), P[3])
	-- (de près) bords d'étages irréguliers
	egg(list, 2, "Bough", CFrame.new(dir(A) * H * 0.24 + V(0, H * 0.24, 0)) * CFrame.Angles(0, -A, 0), V(H * 0.22, H * 0.14, H * 0.18), P[2])
	egg(list, 2, "Bough", CFrame.new(dir(A + 3.3) * H * 0.18 + V(0, H * 0.42, 0)) * CFrame.Angles(0, -A - 3.3, 0), V(H * 0.18, H * 0.13, H * 0.16), P[3]:Lerp(P[2], 0.5))
end

local function palm(list: { Spec }, c: Ctx)
	local H, A, R, P = c.H, c.A, c.R, c.P
	local d = 0.55 + H * 0.03
	-- tronc courbé : 3 segments qui penchent de plus en plus
	local pts = {}
	for i = 0, 3 do
		local t = i / 3
		pts[i + 1] = dir(A) * H * 0.16 * t * t + V(0, H * 0.84 * t, 0)
	end
	for i = 1, 3 do
		rod(list, 0, "Trunk", pts[i] - (i == 1 and V(0, 0.3, 0) or V(0, 0, 0)), pts[i + 1], d * (1.08 - i * 0.1), PALM_BARK, M.Wood, "prop", d * 0.2)
	end
	-- anneaux du tronc (de près) : petites boules aux jointures
	for i = 2, 3 do
		ball(list, 2, "Ring", pts[i], d * (1.1 - i * 0.08), PALM_RING, "deco")
	end
	local top = pts[4]
	ball(list, 1, "Heart", top + V(0, 0.1, 0), d * 1.5, P[1], "deco")
	-- palmes : longs ovales plats qui retombent
	local n = 7
	for k = 0, n - 1 do
		local b = A + k * TAU / n + R(50 + k) * 0.3
		local droop = math.rad(18 + R(60 + k) * 22)
		local L = H * (0.46 + R(70 + k) * 0.08)
		local out = dir(b) * math.cos(droop) - V(0, math.sin(droop), 0)
		local center = top + out * L * 0.46 + V(0, 0.3, 0)
		local cf = CFrame.lookAt(center, center + out)
		egg(list, k < 5 and 0 or 1, "Frond", cf, V(H * 0.13, 0.35, L), P[(k % 3) + 1], k == 0 and "decoS" or "deco")
	end
	for k = 0, 2 do
		ball(list, 2, "Coconut", top + dir(A + 0.8 + k * 2.1) * d * 0.55 - V(0, d * 0.55, 0), 0.8 + H * 0.01, rgb(122, 86, 52), "deco")
	end
end

local function poplar(list: { Spec }, c: Ctx)
	local H, A, P = c.H, c.A, c.P
	local d = 0.35 + H * 0.04
	column(list, 0, "Trunk", V(0, -0.2, 0), H * 0.42 + 0.2, d, BARK, M.Wood, "prop")
	roots(list, c, d, BARK, M.Wood)
	egg(list, 0, "Crown", CFrame.new(0, H * 0.55, 0), V(H * 0.28, H * 0.72, H * 0.28), P[2], "decoS")
	egg(list, 0, "Crown", CFrame.new(dir(A) * H * 0.05 + V(0, H * 0.72, 0)), V(H * 0.22, H * 0.5, H * 0.21), P[3], "deco")
	egg(list, 1, "Crown", CFrame.new(dir(A + 3) * H * 0.06 + V(0, H * 0.42, 0)), V(H * 0.22, H * 0.4, H * 0.22), P[1], "deco")
	egg(list, 2, "CrownTop", CFrame.new(dir(A + 1.4) * H * 0.02 + V(0, H * 0.93, 0)), V(H * 0.12, H * 0.2, H * 0.12), P[3])
	egg(list, 2, "Cluster", CFrame.new(dir(A + 4.6) * H * 0.08 + V(0, H * 0.62, 0)), V(H * 0.16, H * 0.28, H * 0.16), P[1]:Lerp(P[2], 0.5))
end

local function willow(list: { Spec }, c: Ctx)
	local H, A, R, P = c.H, c.A, c.R, c.P
	local d = 0.6 + H * 0.06
	column(list, 0, "Trunk", V(0, -0.2, 0), H * 0.56 + 0.2, d, BARK_DARK, M.Wood, "prop")
	roots(list, c, d, BARK_DARK, M.Wood)
	local b1 = dir(A) * H * 0.26 + V(0, H * 0.7, 0)
	local b2 = dir(A + 3.1) * H * 0.24 + V(0, H * 0.68, 0)
	rod(list, 1, "Branch", V(0, H * 0.42, 0), b1, d * 0.46, BARK_DARK, M.Wood)
	rod(list, 1, "Branch", V(0, H * 0.4, 0), b2, d * 0.42, BARK_DARK, M.Wood)
	egg(list, 0, "Crown", CFrame.new(0, H * 0.74, 0) * CFrame.Angles(0, -A, 0), V(H * 0.72, H * 0.36, H * 0.66), P[2], "decoS")
	-- rideaux qui pendent autour du dôme
	local n = 6
	for k = 0, n - 1 do
		local b = A + k * TAU / n + R(80 + k) * 0.25
		local tier = (k % 2 == 0) and 0 or (k == 5 and 2 or 1)
		local cf = CFrame.new(dir(b) * H * 0.3 + V(0, H * (0.5 + R(90 + k) * 0.06), 0)) * CFrame.Angles(0, -b, 0)
		egg(list, tier, "Drape", cf, V(H * 0.16, H * 0.5, H * 0.24), (k % 3 == 0) and P[1] or P[3], "deco")
	end
	egg(list, 2, "CrownTop", CFrame.new(dir(A + 2) * H * 0.08 + V(0, H * 0.9, 0)), V(H * 0.3, H * 0.16, H * 0.3), P[3])
end

local function round(list: { Spec }, c: Ctx)
	local H, P = c.H, c.P
	local d = 0.4 + H * 0.03
	column(list, 0, "Trunk", V(0, -0.2, 0), H * 0.5 + 0.2, d, BARK, M.Wood, "prop")
	ball(list, 0, "Crown", V(0, H * 0.64, 0), H * 0.56, P[2], "decoS")
	ball(list, 1, "Crown", V(0, H * 0.88, 0) + dir(c.A) * H * 0.05, H * 0.26, P[3])
	roots(list, c, d, BARK, M.Wood)
end

local BUILDERS = {
	Oak = function(list, c)
		broadleaf(list, c, "Oak")
	end,
	Maple = function(list, c)
		broadleaf(list, c, "Maple")
	end,
	Fruit = function(list, c)
		broadleaf(list, c, "Fruit")
	end,
	Cherry = cherry,
	Birch = birch,
	Fir = fir,
	Palm = palm,
	Poplar = poplar,
	Willow = willow,
	Round = round,
}

-- Nom d'espèce (accepte les anciens numéros v9.4)
function Greenery.Species(kind: any, seed: number): string
	if type(kind) == "string" and BUILDERS[kind] then
		return kind
	end
	if kind == 2 then
		return "Cherry"
	elseif kind == 3 then
		return "Fir"
	elseif kind == 4 then
		return "Round"
	end
	-- feuillu "au hasard" : surtout des chênes, quelques érables / bouleaux
	local h = hash(seed, 17)
	if h < 0.5 then
		return "Oak"
	elseif h < 0.68 then
		return "Maple"
	elseif h < 0.84 then
		return "Birch"
	end
	return "Fruit"
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function applyProfile(p: BasePart, profile: string)
	p.CanTouch = false
	if profile == "prop" then
		p.CanQuery = false
		p.CastShadow = true
	else
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = profile == "decoS"
	end
end

local function make(parent: Instance, spec: Spec, root: CFrame): BasePart
	local p = Instance.new("Part")
	p.Name = spec.Name
	p.Anchored = true
	p.Size = spec.Size
	p.CFrame = root * spec.CF
	p.Color = spec.Color
	p.Material = spec.Material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if spec.Kind == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif spec.Kind == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif spec.Kind == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	if spec.Transparency then
		p.Transparency = spec.Transparency
	end
	applyProfile(p, spec.Profile)
	p.Parent = parent
	return p
end

function Greenery.Tree(parent: Instance, base: Vector3, height: number, seed: number, species: string, maxTier: number, minTier: number?, opts: { [string]: any }?): (Model, number)
	local o = opts or {}
	local sp = Greenery.Species(species, seed)
	local pals = PAL[sp] or PAL.Oak
	local R = function(k: number): number
		return hash(seed, k)
	end
	local c: Ctx = {
		H = height,
		Seed = seed,
		A = R(1) * TAU,
		R = R,
		P = pals[1 + math.floor(R(2) * #pals) % #pals],
		Lawn = o.Lawn == true,
	}
	local list: { Spec } = {}
	BUILDERS[sp](list, c)
	local model = Instance.new("Model")
	model.Name = o.Name or "Tree"
	local root = CFrame.new(base) * CFrame.Angles(0, R(6) * TAU, 0)
	local lo = minTier or 0
	local n = 0
	for _, spec in ipairs(list) do
		if spec.Tier >= lo and spec.Tier <= maxTier then
			make(model, spec, root)
			n += 1
		end
	end
	model:SetAttribute("TreeSpecies", sp)
	model:SetAttribute("TreeHeight", height)
	model:SetAttribute("TreeSeed", seed)
	model:SetAttribute("TreeTier", maxTier)
	model:SetAttribute("TreeBase", base)
	model:SetAttribute("TreeLawn", c.Lawn)
	model.Parent = parent
	return model, n
end

return Greenery
