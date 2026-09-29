--[[
	CarModels (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > CarModels

	🚗 Les voitures de Dopamine Town (v9.6), construites en pièces (blocs,
	coins, cylindres) : utilisé par le SERVEUR (voitures garées de la ville,
	TownKit.Car ; voiture qu'on conduit, CarService) ET par le CLIENT
	(concession, garage du manoir). Pur : que des Instances, aucun service.

	8 modèles "réalistes stylisés" : vraie silhouette (capot, habitacle,
	coffre / hayon / benne), toit arrondi, vitres (Glass transparent) avec
	montants, phares et feux, calandre, pare-chocs, 4 roues (pneu, jante,
	moyeu) dans leurs passages de roue, rétroviseurs, plaques, poignées,
	sièges et volant visibles derrière les vitres.
	  BubbleCar : petite voiture ronde kawaii (phares ronds, toit blanc,
	              roue de secours) ;
	  CityCar   : citadine 3 portes ;
	  Hatchback : compacte 5 portes, becquet ;
	  Pickup    : pick-up (cabine + benne, grosses roues) ;
	  SUV       : grand SUV (barres de toit, roue de secours) ;
	  Van       : combi / camping-car bicolore ;
	  SportsCar : roadster décapotable (aileron, doubles échappements) ;
	  Limo      : limousine (3 vitres par côté, chromes).
	Pas de lumière, pas de Neon, pas de son (le client ajoute de petits
	phares la nuit à SA voiture seulement).

	v9.7 (VEHICLES97) "10x mieux" : capot bombé en 2 pans + nez arrondi,
	ailes évasées autour des roues (arches en 3 segments ; bossages d'ailes
	sur le roadster), bas de caisse noirs, toit aux bords arrondis, montants
	noirs ("toit flottant"), vraies JANTES (lèvre, disque de frein, étrier,
	5 / 6 / 10 rayons, cache-moyeu), blocs optiques (boîtier, glace,
	projecteur, feu de jour ; feux arrière rouge + bande + recul), calandres
	différentes par modèle, antibrouillards, rétroviseurs sur pied, sièges
	avec appuie-tête, banquette arrière, écran, colonne de direction.
	Peinture légèrement brillante (Reflectance), option bicolore :
	  opts.Stripe = true | Color3 (bandes de course / filet latéral),
	  opts.RoofColor = Color3 (toit bicolore).
	"Full" ≈ 110-160 pièces (voiture qu'on conduit, concession) ;
	"Parked" ≈ 40-48 pièces (voitures garées de la ville, garages).

	API :
	  CarModels.Build(carId, color?, opts?) -> Model
	    color : Color3 | Id de Config.Cars.Colors | nil (couleur par défaut)
	    opts  : { Detail = "Full" | "Parked", Plate = "TEXTE"?,
	              Scale = number | Vector3 (x = largeur, y = hauteur, z = longueur),
	              Stripe = true | Color3 ?, RoofColor = Color3 ? }
	    Repère : pivot = centre du DESSOUS (au sol), avant vers -Z. Tout est
	    ANCRÉ ; PrimaryPart "Root" = boîte de collision invisible (seule pièce
	    CanCollide), les autres pièces sont du décor (CanCollide / CanQuery /
	    CanTouch false). Attributs : CarId, Length, Width, Height, SeatCF
	    (CFrame du siège du conducteur, repère du pivot), WheelRadius.
	  CarModels.Dimensions(carId) -> Vector3 (largeur, hauteur, longueur)
	  CarModels.WheelPositions(carId) -> { Vector3 } (centres des roues, repère du pivot)
	  CarModels.ColorOf(carId, color?) -> Color3
	  CarModels.LockReason(data, carId) -> string? (nil = débloquée ; texte traduit)
	  CarModels.Kinds : ids des modèles
]]

local Config = require(script.Parent.Config)

local CarModels = {}

local M = Enum.Material
local PI = math.pi

export type Spec = {
	L: number, -- longueur
	W: number, -- largeur (carrosserie)
	WheelD: number, -- diamètre des roues
	TyreW: number, -- largeur des pneus
	Clear: number, -- dessous de la carrosserie
	Low: number, -- dessus du bas de caisse (départ du capot)
	Belt: number, -- ligne de ceinture (bas des vitres)
	Roof: number, -- dessus du toit
	AxleF: number, -- z de l'essieu avant
	AxleR: number, -- z de l'essieu arrière
	Ws: number, -- pied du pare-brise
	R0: number, -- avant du toit
	R1: number, -- arrière du toit
	Rw: number, -- pied de la lunette arrière
	Inset: number, -- rentré de l'habitacle (de chaque côté)
	HoodFront: number, -- 0..1 : hauteur du nez du capot (0 = en coin, 1 = plat)
	TrunkDrop: number, -- coffre plus bas que la ceinture de...
	Doors: number, -- 2 ou 4 (joints / poignées)
	Style: string,
}

local SPECS: { [string]: Spec } = {
	BubbleCar = { L = 9.2, W = 5.2, WheelD = 2.0, TyreW = 0.75, Clear = 0.72, Low = 1.85, Belt = 2.75, Roof = 5.0,
		AxleF = -2.85, AxleR = 2.85, Ws = -2.5, R0 = -1.05, R1 = 1.85, Rw = 3.2, Inset = 0.45, HoodFront = 0.55, TrunkDrop = 0.15, Doors = 2, Style = "Bubble" },
	CityCar = { L = 10.6, W = 5.2, WheelD = 2.1, TyreW = 0.8, Clear = 0.72, Low = 1.8, Belt = 2.85, Roof = 5.0,
		AxleF = -3.45, AxleR = 3.35, Ws = -2.35, R0 = -0.85, R1 = 2.75, Rw = 4.25, Inset = 0.4, HoodFront = 0.45, TrunkDrop = 0.05, Doors = 2, Style = "City" },
	Hatchback = { L = 11.6, W = 5.4, WheelD = 2.2, TyreW = 0.85, Clear = 0.72, Low = 1.8, Belt = 2.95, Roof = 5.0,
		AxleF = -3.8, AxleR = 3.7, Ws = -2.45, R0 = -0.7, R1 = 3.55, Rw = 5.0, Inset = 0.4, HoodFront = 0.4, TrunkDrop = 0, Doors = 4, Style = "Hatch" },
	Pickup = { L = 13, W = 6.0, WheelD = 2.7, TyreW = 1.0, Clear = 1.15, Low = 2.45, Belt = 3.6, Roof = 6.0,
		AxleF = -4.1, AxleR = 4.0, Ws = -2.7, R0 = -1.55, R1 = 1.35, Rw = 1.45, Inset = 0.35, HoodFront = 0.75, TrunkDrop = 0, Doors = 4, Style = "Pickup" },
	SUV = { L = 12.6, W = 6.0, WheelD = 2.6, TyreW = 0.95, Clear = 1.0, Low = 2.35, Belt = 3.55, Roof = 6.1,
		AxleF = -4.0, AxleR = 3.9, Ws = -2.75, R0 = -1.35, R1 = 5.3, Rw = 5.75, Inset = 0.35, HoodFront = 0.7, TrunkDrop = 0, Doors = 4, Style = "SUV" },
	Van = { L = 13, W = 6.0, WheelD = 2.4, TyreW = 0.9, Clear = 0.9, Low = 2.2, Belt = 3.35, Roof = 6.7,
		AxleF = -4.4, AxleR = 4.2, Ws = -5.15, R0 = -3.85, R1 = 6.15, Rw = 6.2, Inset = 0.3, HoodFront = 0.6, TrunkDrop = 0, Doors = 2, Style = "Van" },
	SportsCar = { L = 12.6, W = 5.8, WheelD = 2.3, TyreW = 1.05, Clear = 0.55, Low = 1.45, Belt = 2.55, Roof = 2.55,
		AxleF = -4.05, AxleR = 3.85, Ws = -1.2, R0 = -0.2, R1 = 1.9, Rw = 2.9, Inset = 0.45, HoodFront = 0, TrunkDrop = 0.15, Doors = 2, Style = "Sports" },
	Limo = { L = 15.2, W = 5.8, WheelD = 2.2, TyreW = 0.85, Clear = 0.7, Low = 1.8, Belt = 2.95, Roof = 5.0,
		AxleF = -5.2, AxleR = 5.1, Ws = -3.4, R0 = -2.0, R1 = 5.0, Rw = 6.1, Inset = 0.4, HoodFront = 0.5, TrunkDrop = 0.1, Doors = 4, Style = "Limo" },
}
CarModels.Specs = SPECS
CarModels.Kinds = { "BubbleCar", "CityCar", "Hatchback", "Pickup", "SUV", "Van", "SportsCar", "Limo" }

-- Couleurs fixes
local GLASS = Color3.fromRGB(46, 60, 78) -- (v9.8) verre teinté
local TRIM = Color3.fromRGB(44, 44, 54)
local TYRE = Color3.fromRGB(32, 32, 38)
local CHROME = Color3.fromRGB(214, 218, 226)
local LAMP = Color3.fromRGB(255, 250, 228)
local TAIL = Color3.fromRGB(214, 36, 56)
local AMBER = Color3.fromRGB(255, 170, 60)
local PLATE = Color3.fromRGB(248, 248, 244)
local PLATE_BAND = Color3.fromRGB(40, 80, 190)
local SEAT = Color3.fromRGB(70, 56, 66)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
-- (v9.7) détails
local DISC = Color3.fromRGB(118, 120, 128) -- disque de frein
local CAL_RED = Color3.fromRGB(212, 40, 52)
local CAL_DARK = Color3.fromRGB(78, 78, 88)
local HOUSING = Color3.fromRGB(28, 28, 34) -- boîtiers des optiques
local DRL = Color3.fromRGB(255, 252, 240) -- feu de jour (pas de Neon)
local TAIL_IN = Color3.fromRGB(255, 96, 104)
local REVERSE = Color3.fromRGB(236, 236, 240)
local SEAT2 = Color3.fromRGB(88, 72, 82)
local SCREEN = Color3.fromRGB(44, 70, 104)
local GRAPHITE = Color3.fromRGB(52, 54, 62)
-- (v9.8, CARS98) détails "10x plus réalistes"
local SIDEWALL = Color3.fromRGB(50, 50, 56) -- flanc du pneu (un peu plus clair que la bande)
local GAP = Color3.fromRGB(22, 22, 28) -- joints de carrosserie
local HEADLINER = Color3.fromRGB(206, 202, 196) -- ciel de toit (intérieur)
local CONSOLE = Color3.fromRGB(36, 36, 42)
local GLASS_T = 0.38 -- transparence des vitres teintées

local function kindOf(carId: string?): string
	if type(carId) == "string" then
		if SPECS[carId] then
			return carId
		end
		local car = Config.CarsById and Config.CarsById[carId]
		if car and type(car.Kind) == "string" and SPECS[car.Kind] then
			return car.Kind
		end
	end
	return "CityCar"
end

function CarModels.Dimensions(carId: string?): Vector3
	local s = SPECS[kindOf(carId)]
	local height = s.Roof
	if s.Style == "Sports" then
		height = s.Belt + 1.3
	end
	return Vector3.new(s.W, height, s.L)
end

function CarModels.WheelPositions(carId: string?): { Vector3 }
	local s = SPECS[kindOf(carId)]
	local x = s.W / 2 - s.TyreW / 2 + 0.12
	local out = {}
	for _, z in ipairs({ s.AxleF, s.AxleR }) do
		for _, sx in ipairs({ -1, 1 }) do
			table.insert(out, Vector3.new(sx * x, s.WheelD / 2, z))
		end
	end
	return out
end

function CarModels.ColorOf(carId: string?, color: any?): Color3
	if typeof(color) == "Color3" then
		return color
	end
	local byId = Config.CarColorsById or {}
	if type(color) == "string" and byId[color] then
		return byId[color].Color
	end
	local car = type(carId) == "string" and Config.CarsById and Config.CarsById[carId] or nil
	local default = car and byId[car.DefaultColor]
	if default then
		return default.Color
	end
	return Color3.fromRGB(255, 150, 196)
end

-- 🔒 Raison du verrou (nil = débloquée) : visites à l'océan
function CarModels.LockReason(data: any, carId: string): string?
	local car = Config.CarsById and Config.CarsById[carId]
	if not car then
		return "?"
	end
	local need = tonumber(car.RequiresRebirths) or 0
	local have = type(data) == "table" and tonumber(data.Rebirths) or 0
	if (have or 0) >= need then
		return nil
	end
	local text = "🔒 Unlocked after %d visits to the ocean"
	local okLocale, Locale = pcall(require, script.Parent:FindFirstChild("Locale") :: any)
	if okLocale and type(Locale) == "table" and type(Locale.T) == "function" then
		return Locale.T(text, need)
	end
	return string.format(text, need)
end

----------------------------------------------------------------------
-- Constructeur (repère local : sol au centre, avant vers -Z)
----------------------------------------------------------------------

type B = {
	Model: Model,
	S: Vector3, -- échelle
	Count: number,
	Paint: Color3?, -- couleur de carrosserie (pièces marquées "Paint" : repeinture sans reconstruire)
	Gloss: number?, -- (v9.7) Reflectance de la peinture (vernis léger)
}

local function newPart(b: B, className: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shadow: boolean?): BasePart
	local p = Instance.new(className :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if b.Paint and color == b.Paint then
		p:SetAttribute("Paint", true)
		if b.Gloss and (material == M.SmoothPlastic or material == M.Plastic) then
			p.Reflectance = b.Gloss
		end
	end
	p.Parent = b.Model
	b.Count += 1
	return p
end

local function P(b: B, x: number, y: number, z: number): Vector3
	return Vector3.new(x * b.S.X, y * b.S.Y, z * b.S.Z)
end

-- Bloc aligné : bornes x0..x1, y0..y1, z0..z1
local function box(b: B, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local s = b.S
	return newPart(b, "Part", name, Vector3.new(math.abs(x1 - x0) * s.X, math.abs(y1 - y0) * s.Y, math.abs(z1 - z0) * s.Z),
		CFrame.new(P(b, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)), color, material or M.SmoothPlastic, shadow)
end

-- Coin (WedgePart) : haut du côté +Z (dos) si `highBack`, sinon côté -Z
local function wedge(b: B, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, highBack: boolean, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local s = b.S
	local cf = CFrame.new(P(b, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
	if not highBack then
		cf *= CFrame.Angles(0, PI, 0)
	end
	return newPart(b, "WedgePart", name, Vector3.new(math.abs(x1 - x0) * s.X, math.abs(y1 - y0) * s.Y, math.abs(z1 - z0) * s.Z), cf, color, material or M.SmoothPlastic, shadow)
end

-- Plaque inclinée entre deux points (y, z) du plan de côté, à l'abscisse x
local function slab(b: B, name: string, x: number, width: number, y0: number, z0: number, y1: number, z1: number, thick: number, color: Color3, material: Enum.Material?): BasePart
	local a = P(b, x, y0, z0)
	local c = P(b, x, y1, z1)
	local len = (c - a).Magnitude
	local cf = CFrame.lookAt((a + c) / 2, c)
	return newPart(b, "Part", name, Vector3.new(width * b.S.X, thick * b.S.Y, len), cf, color, material or M.SmoothPlastic)
end

-- Cylindre couché le long de X (roues, nez arrondi)
local function cylX(b: B, name: string, x: number, y: number, z: number, length: number, diameter: number, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local m = math.min(b.S.Y, b.S.Z)
	local p = newPart(b, "Part", name, Vector3.new(length * b.S.X, diameter * m, diameter * m), CFrame.new(P(b, x, y, z)), color, material or M.SmoothPlastic, shadow)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Cylindre le long de Z (arêtes du toit, échappements, phares ronds)
local function cylZ(b: B, name: string, x: number, y: number, z: number, length: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local m = math.min(b.S.X, b.S.Y)
	local p = newPart(b, "Part", name, Vector3.new(length * b.S.Z, diameter * m, diameter * m), CFrame.new(P(b, x, y, z)) * CFrame.Angles(0, PI / 2, 0), color, material or M.SmoothPlastic)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

----------------------------------------------------------------------
-- Éléments
----------------------------------------------------------------------

-- Bloc tourné autour de X (arches, rayons, étriers) : centre, taille, angle (rad)
local function boxRotX(b: B, name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number, angle: number, color: Color3, material: Enum.Material?): BasePart
	local m = math.min(b.S.Y, b.S.Z)
	return newPart(b, "Part", name, Vector3.new(sx * b.S.X, sy * m, sz * m), CFrame.new(P(b, x, y, z)) * CFrame.Angles(angle, 0, 0), color, material or M.SmoothPlastic)
end

-- Cylindre debout (axe Y) : disques posés à plat
local function cylY(b: B, name: string, x: number, y: number, z: number, height: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local m = math.min(b.S.X, b.S.Z)
	local p = newPart(b, "Part", name, Vector3.new(height * b.S.Y, diameter * m, diameter * m), CFrame.new(P(b, x, y, z)) * CFrame.Angles(0, 0, PI / 2), color, material or M.SmoothPlastic)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- (v9.8) Ellipsoïde (SpecialMesh "Sphere" qui remplit la pièce) : formes
-- arrondies (nez, toit en dôme, rétroviseurs, optiques). Taille = extents.
local function ell(b: B, name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number, color: Color3, material: Enum.Material?, rot: CFrame?, shadow: boolean?): BasePart
	local cf = CFrame.new(P(b, x, y, z))
	if rot then
		cf *= rot
	end
	local p = newPart(b, "Part", name, Vector3.new(sx * b.S.X, sy * b.S.Y, sz * b.S.Z), cf, color, material or M.SmoothPlastic, shadow)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- (v9.8) Tige (cylindre) entre deux points du repère local (arêtes arrondies)
local function rod(b: B, name: string, a: Vector3, c: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local pa, pc = P(b, a.X, a.Y, a.Z), P(b, c.X, c.Y, c.Z)
	local len = (pc - pa).Magnitude
	local m = math.min(b.S.X, b.S.Y)
	local cf = CFrame.lookAt((pa + pc) / 2, pc) * CFrame.Angles(0, PI / 2, 0)
	local p = newPart(b, "Part", name, Vector3.new(len, diameter * m, diameter * m), cf, color, material or M.SmoothPlastic)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

type WheelLook = { Rim: Color3, Cap: Color3, Caliper: Color3, Spokes: number }

-- Roue (v9.8) : passage sombre, pneu (bande de roulement) + FLANC plus clair,
-- fond de jante, disque de frein, étrier, rayons, cache-moyeu. Couches depuis
-- la face extérieure du pneu (vers l'extérieur), toutes espacées de ≥ 0,025
-- (aucune face confondue : pas de z-fighting) :
-- pneu 0 | flanc +0,025 | fond de jante +0,05 | disque +0,075 |
-- étrier +0,0625..+0,10 | rayons +0,125..+0,16 | cache-moyeu +0,10..+0,195
local function wheel(b: B, s: Spec, x: number, z: number, full: boolean, look: WheelLook)
	local D = s.WheelD
	local r = D / 2
	local side = x > 0 and 1 or -1
	cylX(b, "WheelArch", side * (s.W / 2 - 0.01), r + 0.1, z, 0.1, D + 0.55, TRIM, M.SmoothPlastic)
	cylX(b, "Tyre", x, r, z, s.TyreW, D, TYRE, M.Rubber, true)
	local face = x + side * s.TyreW / 2
	local function layer(name: string, outer: number, thick: number, diameter: number, color: Color3, material: Enum.Material)
		cylX(b, name, face + side * (outer - thick / 2), r, z, thick, diameter, color, material)
	end
	if not full then
		layer("Rim", 0.05, 0.3, D * 0.66, look.Rim, M.Metal)
		layer("Hub", 0.1, 0.1, D * 0.24, look.Cap, M.Metal)
		return
	end
	layer("Sidewall", 0.025, 0.08, D - 0.14, SIDEWALL, M.Rubber)
	if look.Spokes <= 0 then
		-- jante tôle (kawaii) : grande jante + enjoliveur + bouton central
		layer("Rim", 0.05, 0.3, D * 0.66, look.Rim, M.SmoothPlastic)
		layer("HubCap", 0.075, 0.1, D * 0.46, look.Cap, M.Metal)
		layer("HubCenter", 0.1, 0.1, D * 0.16, look.Rim, M.SmoothPlastic)
		return
	end
	layer("Rim", 0.05, 0.3, D * 0.68, GRAPHITE:Lerp(look.Rim, 0.35), M.Metal)
	layer("BrakeDisc", 0.075, 0.12, D * 0.5, DISC, M.Metal)
	local ca = math.rad(40)
	boxRotX(b, "Caliper", face + side * 0.08125, r + math.cos(ca) * D * 0.19, z + math.sin(ca) * D * 0.19, 0.0375, D * 0.1, D * 0.2, ca, look.Caliper)
	local len = D * 0.62
	local sw = D * 0.075
	local sx = face + side * 0.1425
	if look.Spokes == 5 then
		for k = 0, 4 do
			local a = k / 5 * 2 * PI
			boxRotX(b, "Spoke", sx, r + math.cos(a) * len / 4, z + math.sin(a) * len / 4, 0.035, sw, len / 2, a - PI / 2, look.Rim, M.Metal)
		end
	else
		local bars = if look.Spokes >= 10 then 5 else 3
		for k = 0, bars - 1 do
			boxRotX(b, "Spoke", sx, r, z, 0.035, sw, len, k / bars * PI - PI / 2, look.Rim, M.Metal)
		end
	end
	-- lèvre de jante (anneau chromé : 8 segments fins, couche +0,085..+0,115)
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * 2 * PI
		local rr = D * 0.33
		boxRotX(b, "RimLip", face + side * 0.1, r + math.cos(a) * rr, z + math.sin(a) * rr, 0.03, 0.06, 2 * rr * math.tan(PI / 8) + 0.02, a, CHROME, M.Metal)
	end
	layer("Hub", 0.195, 0.095, D * 0.17, look.Cap, M.Metal)
end

-- Arche d'aile évasée au-dessus d'une roue : 5 segments tangents (±60°),
-- du flanc (W/2 - 0,02) à W/2 + 0,11. `topAt(z)` = dessus local de la caisse :
-- un segment qui dépasserait est remplacé par un bossage d'aile (roadster).
local function archFlare(b: B, s: Spec, z: number, side: number, topAt: (number) -> number, color: Color3, material: Enum.Material, paint: Color3)
	local r = s.WheelD / 2
	local ra = r + 0.32
	local thick = 0.24
	local half = ra * math.sin(math.rad(15)) + 0.04 -- (v9.8) 5 segments de 30° : arche lisse
	local x = side * (s.W / 2 + 0.045)
	local hump = false
	for k = -2, 2 do
		local a = k * math.rad(30)
		local y = r + math.cos(a) * ra
		local zc = z + math.sin(a) * ra
		local maxY = y + math.abs(math.sin(a)) * half + math.abs(math.cos(a)) * thick / 2
		local ext = math.abs(math.cos(a)) * half + math.abs(math.sin(a)) * thick / 2
		local localTop = math.min(topAt(zc - ext), topAt(zc), topAt(zc + ext))
		if maxY <= localTop - 0.04 then
			boxRotX(b, "Arch", x, y, zc, 0.13, thick, half * 2, a, color, material)
		elseif k == 0 then
			hump = true
		end
	end
	if hump then
		-- bossage d'aile par-dessus la caisse (bloc + deux pentes)
		local h1 = r + ra + thick / 2 + 0.05
		local base = math.min(topAt(z - ra * 1.15), topAt(z), topAt(z + ra * 1.15)) - 0.05
		local x0, x1 = side * (s.W / 2 - 1.0), side * s.W / 2
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		box(b, "Fender", lo, hi, base, h1, z - ra * 0.55, z + ra * 0.55, paint, M.SmoothPlastic, true)
		wedge(b, "FenderSlope", lo, hi, base, h1, z - ra * 1.15, z - ra * 0.55, true, paint, M.SmoothPlastic)
		wedge(b, "FenderSlope", lo, hi, base, h1, z + ra * 0.55, z + ra * 1.15, false, paint, M.SmoothPlastic)
	end
end

local function plate(b: B, name: string, z: number, y: number, facing: number, full: boolean, text: string?)
	local p = box(b, name, -0.9, 0.9, y - 0.24, y + 0.24, z - 0.03, z + 0.03, PLATE, M.SmoothPlastic)
	if full then
		-- (bande bleue 0,04 en avant de la plaque : jamais coplanaire avec le pare-chocs)
		box(b, name .. "Band", -0.9, -0.66, y - 0.24, y + 0.24, z + 0.06 * facing - 0.025, z + 0.06 * facing + 0.025, PLATE_BAND, M.SmoothPlastic)
	end
	if text and text ~= "" then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlateText"
		gui.Face = facing > 0 and Enum.NormalId.Back or Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		gui.MaxDistance = 60
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(0.8, 0, 1, 0)
		label.Position = UDim2.fromScale(0.16, 0)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(30, 30, 40)
		label.Text = string.upper(string.sub(text, 1, 8))
		label.Parent = gui
		gui.Parent = p
	end
end

-- Habitacle : sièges avant (assise, dossier, appuie-tête), banquette arrière,
-- tableau de bord + écran, volant sur sa colonne
local function interior(b: B, s: Spec, seatZ: number, seatTop: number, style: string)
	local wc = s.W - 2 * s.Inset
	local seatX = wc * 0.22
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * seatX
		box(b, "SeatCushion", x - 0.72, x + 0.72, seatTop - 0.35, seatTop, seatZ - 0.7, seatZ + 0.75, SEAT, M.Fabric)
		slab(b, "SeatBack", x, 1.4, seatTop, seatZ + 0.85, seatTop + 1.65, seatZ + 1.15, 0.35, SEAT, M.Fabric)
		box(b, "Headrest", x - 0.4, x + 0.4, seatTop + 1.7, seatTop + 2.1, seatZ + 1.03, seatZ + 1.33, SEAT2, M.Fabric)
	end
	-- banquette arrière (s'il y a la place avant la lunette)
	local rearZ = seatZ + 2.25
	if style == "Limo" then
		-- salon : banquette du fond + banquette latérale + petit bar
		local backZ = s.R1 - 0.9
		box(b, "RearBench", -wc / 2 + 0.2, wc / 2 - 0.2, seatTop - 0.35, seatTop, backZ - 1.2, backZ, SEAT2, M.Fabric)
		slab(b, "RearBack", 0, wc - 0.4, seatTop, backZ + 0.1, seatTop + 1.6, backZ + 0.4, 0.35, SEAT2, M.Fabric)
		box(b, "SideBench", -wc / 2 + 0.2, -wc / 2 + 1.3, seatTop - 0.35, seatTop, rearZ, backZ - 1.3, SEAT2, M.Fabric)
		box(b, "MiniBar", wc / 2 - 1.1, wc / 2 - 0.2, seatTop - 0.3, seatTop + 0.5, rearZ + 0.2, backZ - 1.35, Color3.fromRGB(96, 64, 48), M.Wood)
	elseif style ~= "Sports" and style ~= "Van" and rearZ + 1.1 < s.Rw then
		box(b, "RearBench", -wc / 2 + 0.2, wc / 2 - 0.2, seatTop - 0.35, seatTop, rearZ - 0.65, rearZ + 0.6, SEAT, M.Fabric)
		-- (dossier sous la lunette inclinée : jamais à travers la vitre)
		local backZ = rearZ + 1.0
		local glassY = s.Roof - 0.34
		if backZ > s.R1 and s.Rw - s.R1 > 0.1 then
			glassY -= (s.Roof - 0.34 - s.Belt) * (backZ - s.R1) / (s.Rw - s.R1)
		end
		local h = math.min(1.55, glassY - seatTop - 0.15)
		if h > 0.6 then
			slab(b, "RearBack", 0, wc - 0.4, seatTop, rearZ + 0.7, seatTop + h, backZ, 0.35, SEAT, M.Fabric)
		end
	end
	-- tableau de bord, écran, volant + colonne (devant le conducteur, à gauche)
	box(b, "Dashboard", -wc / 2 + 0.1, wc / 2 - 0.1, s.Belt - 0.5, s.Belt + 0.05, s.Ws + 0.05, s.Ws + 0.85, TRIM, M.SmoothPlastic)
	box(b, "Screen", -0.42, 0.42, s.Belt + 0.05, s.Belt + 0.42, s.Ws + 0.72, s.Ws + 0.8, SCREEN, M.Glass)
	local wheelZ = math.min(seatZ - 1.4, s.Ws + 1.2)
	local sw = cylZ(b, "SteeringWheel", -seatX, s.Belt + 0.25, wheelZ, 0.14, 1.05, TRIM, M.SmoothPlastic)
	sw.CFrame = sw.CFrame * CFrame.Angles(0, 0, math.rad(-25))
	slab(b, "SteeringColumn", -seatX, 0.16, s.Belt - 0.25, s.Ws + 0.8, s.Belt + 0.2, wheelZ - 0.1, 0.16, GRAPHITE, M.SmoothPlastic)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function CarModels.Build(carId: string?, color: any?, opts: any?): Model
	local options = type(opts) == "table" and opts or {}
	local kind = kindOf(carId)
	local s = SPECS[kind]
	local paint = CarModels.ColorOf(type(carId) == "string" and carId or kind, color)
	local full = options.Detail ~= "Parked"
	local scale = Vector3.new(1, 1, 1)
	if typeof(options.Scale) == "Vector3" then
		scale = options.Scale
	elseif type(options.Scale) == "number" and options.Scale > 0 then
		scale = Vector3.new(options.Scale, options.Scale, options.Scale)
	end
	local model = Instance.new("Model")
	model.Name = "Car_" .. kind
	local b: B = { Model = model, S = scale, Count = 0, Paint = paint, Gloss = if full then 0.1 else 0.07 }

	local zF, zB = -s.L / 2, s.L / 2
	local wc = s.W - 2 * s.Inset
	local roofT = 0.34
	local style = s.Style
	local convertible = style == "Sports"
	local offroad = style == "SUV" or style == "Pickup"
	local r = s.WheelD / 2
	local ra = r + 0.32 -- rayon des arches
	-- teinte de contraste (bandes, toit bicolore) : sombre sur une peinture claire
	local lum = paint.R * 0.3 + paint.G * 0.59 + paint.B * 0.11
	local contrast = if lum > 0.62 then GRAPHITE else Color3.fromRGB(250, 248, 244)
	local stripe: Color3? = nil
	if typeof(options.Stripe) == "Color3" then
		stripe = options.Stripe
	elseif options.Stripe == true or (full and options.Stripe == nil and (style == "Sports" or style == "Hatch")) then
		stripe = contrast
	end
	local roofColor = paint
	if typeof(options.RoofColor) == "Color3" then
		roofColor = options.RoofColor
	elseif style == "Bubble" or style == "Van" then
		roofColor = WHITE:Lerp(paint, 0.08)
	end
	-- jantes par modèle
	local look: WheelLook = { Rim = CHROME, Cap = CHROME, Caliper = CAL_DARK, Spokes = 5 }
	if style == "Bubble" then
		look = { Rim = WHITE, Cap = CHROME, Caliper = CAL_DARK, Spokes = 0 }
	elseif style == "Sports" then
		look = { Rim = GRAPHITE, Cap = CHROME, Caliper = CAL_RED, Spokes = 10 }
	elseif style == "Limo" then
		look = { Rim = CHROME, Cap = GRAPHITE, Caliper = CAL_DARK, Spokes = 10 }
	elseif offroad then
		look = { Rim = Color3.fromRGB(190, 194, 202), Cap = GRAPHITE, Caliper = CAL_DARK, Spokes = 6 }
	elseif style == "Van" then
		look = { Rim = WHITE, Cap = CHROME, Caliper = CAL_DARK, Spokes = 0 }
	elseif style == "Hatch" then
		look = { Rim = CHROME, Cap = GRAPHITE, Caliper = CAL_RED, Spokes = 6 }
	end

	-- boîte de collision (surélevée : les bordures passent dessous)
	local rootBottom = math.max(s.Clear, 0.95)
	local rootTop = math.max(s.Belt, rootBottom + 1.2)
	local root = box(b, "Root", -s.W / 2 + 0.1, s.W / 2 - 0.1, rootBottom, rootTop, zF + 0.2, zB - 0.2, paint, M.SmoothPlastic)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	model.PrimaryPart = root
	root.PivotOffset = CFrame.new(0, -((rootBottom + rootTop) / 2) * scale.Y, 0)

	-- ░ profil du dessus de caisse (capot bombé en 2 pans) ░
	local upH = s.Belt - s.Low
	local hoodZ0 = zF + 0.35
	local hf = upH * s.HoodFront
	local hoodY0 = s.Low + hf
	local curved = full and (s.Ws - hoodZ0) > 1.2 and (s.Belt - hoodY0) > 0.3
	local zm = hoodZ0 + (s.Ws - hoodZ0) * 0.45
	local ym = hoodY0 + (s.Belt - hoodY0) * (if curved then 0.7 else 0.45)
	local trunkEnd = zB - 0.35
	local function topAt(z: number): number
		if z <= hoodZ0 then
			return s.Low
		elseif z < s.Ws then
			if z < zm then
				return hoodY0 + (ym - hoodY0) * (z - hoodZ0) / (zm - hoodZ0)
			end
			return ym + (s.Belt - ym) * (z - zm) / math.max(0.01, s.Ws - zm)
		elseif style == "Pickup" or z <= s.Rw then
			return s.Belt
		end
		return s.Belt - s.TrunkDrop
	end

	-- ░ bas de caisse : bloc + nez / arrière arrondis ░
	local lowH = s.Low - s.Clear
	local rn = lowH / 2
	box(b, "Body", -s.W / 2, s.W / 2, s.Clear, s.Low, zF + rn, zB - rn, paint, M.SmoothPlastic, true)
	-- (v9.8) nez / arrière en ELLIPSOÏDE : arrondis de face ET vus de dessus
	ell(b, "NoseRound", 0, s.Clear + rn, zF + rn, s.W - 0.02, lowH, rn * 2, paint, M.SmoothPlastic, nil, true)
	ell(b, "TailRound", 0, s.Clear + rn, zB - rn, s.W - 0.02, lowH, rn * 2, paint, M.SmoothPlastic, nil, true)
	-- pare-chocs : lèvre basse sombre + prise d'air + antibrouillards
	-- (v9.8) lèvres de pare-chocs arrondies (ellipsoïdes : coins ronds vus de dessus)
	ell(b, "BumperF", 0, s.Clear + 0.105, zF + 0.43, s.W + 0.08, 0.36, 0.94, TRIM, M.SmoothPlastic)
	ell(b, "BumperR", 0, s.Clear + 0.105, zB - 0.43, s.W + 0.08, 0.36, 0.94, TRIM, M.SmoothPlastic)
	local intakeTop = s.Clear + math.min(0.44, lowH * 0.4 - 0.02)
	if full and style ~= "Bubble" then
		box(b, "Intake", -s.W * 0.34, s.W * 0.34, s.Clear + 0.28, intakeTop, zF - 0.03, zF + 0.5, HOUSING, M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			cylZ(b, "FogLight", sx * s.W * 0.41, (s.Clear + 0.28 + intakeTop) / 2, zF + 0.01, 0.16, math.max(0.14, intakeTop - s.Clear - 0.3), LAMP, M.Glass)
		end
	end
	-- bas de caisse noirs (marchepieds pour le SUV / pick-up)
	if full then
		for _, sx in ipairs({ -1, 1 }) do
			if offroad then
				local x0, x1 = sx * (s.W / 2 - 0.3), sx * (s.W / 2 + 0.28)
				box(b, "SideStep", math.min(x0, x1), math.max(x0, x1), s.Clear - 0.12, s.Clear + 0.04, s.AxleF + ra + 0.15, s.AxleR - ra - 0.15, GRAPHITE, M.DiamondPlate)
			else
				local x0, x1 = sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.06)
				box(b, "SideSkirt", math.min(x0, x1), math.max(x0, x1), s.Clear - 0.05, s.Clear + 0.3, s.AxleF + ra + 0.05, s.AxleR - ra - 0.05, TRIM, M.SmoothPlastic)
			end
		end
	end

	-- ░ haut de caisse : capot (2 pans), bas de l'habitacle, coffre ░
	if hf > 0.05 then
		box(b, "HoodBase", -s.W / 2, s.W / 2, s.Low, hoodY0, hoodZ0, s.Ws, paint, M.SmoothPlastic, true)
	end
	if s.Belt - hoodY0 > 0.05 then
		if curved then
			box(b, "HoodMid", -s.W / 2, s.W / 2, hoodY0, ym, zm, s.Ws, paint, M.SmoothPlastic, true)
			wedge(b, "Hood", -s.W / 2, s.W / 2, hoodY0, ym, hoodZ0, zm, true, paint, M.SmoothPlastic, true)
			wedge(b, "Hood", -s.W / 2, s.W / 2, ym, s.Belt, zm, s.Ws, true, paint, M.SmoothPlastic, true)
		else
			wedge(b, "Hood", -s.W / 2, s.W / 2, hoodY0, s.Belt, hoodZ0, s.Ws, true, paint, M.SmoothPlastic, true)
		end
	end
	if full and not convertible then
		-- grille d'auvent (essuie-glaces) au pied du pare-brise
		box(b, "Cowl", -wc / 2, wc / 2, s.Belt - 0.04, s.Belt + 0.05, s.Ws - 0.3, s.Ws + 0.02, HOUSING, M.SmoothPlastic)
	end
	if convertible then
		-- baquet ouvert : plancher + flancs + tablier + capot arrière
		box(b, "CockpitFloor", -wc / 2, wc / 2, s.Low - 0.3, s.Low - 0.1, s.Ws, s.Rw, TRIM, M.Fabric)
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "Flank", sx * wc / 2, sx * s.W / 2, s.Low, s.Belt, s.Ws, s.Rw, paint, M.SmoothPlastic, true)
		end
		box(b, "Cowl", -wc / 2, wc / 2, s.Low, s.Belt, s.Ws, s.Ws + 0.5, paint, M.SmoothPlastic)
		box(b, "Bulkhead", -wc / 2, wc / 2, s.Low, s.Belt - 0.05, s.Rw - 0.4, s.Rw, paint, M.SmoothPlastic)
		box(b, "RearDeck", -s.W / 2, s.W / 2, s.Low, s.Belt - s.TrunkDrop, s.Rw, trunkEnd, paint, M.SmoothPlastic, true)
		-- carénages derrière les appuie-tête
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * wc * 0.22
			wedge(b, "Fairing", x - 0.55, x + 0.55, s.Belt - s.TrunkDrop, s.Belt + 0.75, s.Rw, s.Rw + 1.6, false, paint, M.SmoothPlastic)
		end
	elseif style == "Pickup" then
		box(b, "CabLower", -s.W / 2, s.W / 2, s.Low, s.Belt, s.Ws, s.Rw + 0.1, paint, M.SmoothPlastic, true)
		-- benne : plancher strié, ridelles, hayon
		box(b, "BedFloor", -s.W / 2 + 0.35, s.W / 2 - 0.35, s.Low - 0.25, s.Low + 0.06, s.Rw + 0.1, trunkEnd - 0.25, TRIM, M.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "BedSide", sx * (s.W / 2 - 0.3), sx * s.W / 2, s.Low, s.Belt, s.Rw + 0.1, trunkEnd, paint, M.SmoothPlastic, true)
			box(b, "BedRail", sx * (s.W / 2 - 0.34), sx * (s.W / 2 + 0.02), s.Belt, s.Belt + 0.12, s.Rw + 0.1, trunkEnd, TRIM, M.SmoothPlastic)
			if full then
				box(b, "BedRib", sx * 0.9 - 0.12, sx * 0.9 + 0.12, s.Low + 0.06, s.Low + 0.13, s.Rw + 0.45, trunkEnd - 0.6, GRAPHITE, M.Metal)
			end
		end
		box(b, "BedFront", -s.W / 2 + 0.33, s.W / 2 - 0.33, s.Low, s.Belt - 0.04, s.Rw + 0.1, s.Rw + 0.4, paint, M.SmoothPlastic)
		box(b, "Tailgate", -s.W / 2 + 0.33, s.W / 2 - 0.33, s.Low - 0.3, s.Belt - 0.04, trunkEnd - 0.3, trunkEnd, paint, M.SmoothPlastic, true)
		if full then
			box(b, "TailgateHandle", -0.45, 0.45, s.Belt - 0.42, s.Belt - 0.27, trunkEnd - 0.02, trunkEnd + 0.06, GRAPHITE, M.Metal)
		end
	else
		box(b, "CabinLower", -s.W / 2, s.W / 2, s.Low, s.Belt, s.Ws, s.Rw, paint, M.SmoothPlastic, true)
		if trunkEnd - s.Rw > 0.1 then
			box(b, "Trunk", -s.W / 2, s.W / 2, s.Low, s.Belt - s.TrunkDrop, s.Rw, trunkEnd, paint, M.SmoothPlastic, true)
		end
	end

	-- ░ ailes évasées + roues ░
	local archColor = if offroad then GRAPHITE else paint
	for _, pos in ipairs(CarModels.WheelPositions(kind)) do
		if full then
			archFlare(b, s, pos.Z, pos.X > 0 and 1 or -1, topAt, archColor, M.SmoothPlastic, paint)
		end
		wheel(b, s, pos.X, pos.Z, full, look)
	end

	-- ░ habitacle : vitres (pare-brise, côtés, lunette), montants, toit ░
	local seatTop = math.min(s.Low + 0.35, s.Roof - 3.05)
	local seatZ = s.R0 + (s.R1 - s.R0) * 0.42
	if style == "Van" then
		seatZ = s.R0 + 1.15
	elseif style == "Pickup" then
		seatZ = s.R0 + 1.05
	elseif convertible then
		seatZ = s.Rw - 1.6
		seatTop = s.Low + 0.15
	elseif style == "Limo" then
		seatZ = s.R0 + 1.2
	end
	local gTop = s.Roof - roofT
	if convertible then
		-- pare-brise court et incliné, cadre
		slab(b, "Windshield", 0, wc - 0.2, s.Belt, s.Ws + 0.1, s.Belt + 1.35, s.Ws + 1.05, 0.12, GLASS, M.Glass).Transparency = 0.35
		for _, sx in ipairs({ -1, 1 }) do
			slab(b, "WindshieldFrame", sx * (wc / 2 - 0.05), 0.14, s.Belt, s.Ws + 0.05, s.Belt + 1.42, s.Ws + 1.05, 0.2, TRIM, M.SmoothPlastic)
		end
		slab(b, "WindshieldTop", 0, wc - 0.1, s.Belt + 1.35, s.Ws + 1.02, s.Belt + 1.42, s.Ws + 1.1, 0.14, TRIM, M.SmoothPlastic)
	else
		local front = wedge(b, "GlassFront", -wc / 2, wc / 2, s.Belt, gTop, s.Ws, s.R0, true, GLASS, M.Glass)
		front.Transparency = GLASS_T
		front.Reflectance = 0.12
		local midEnd = s.R1
		if style == "Van" then
			midEnd = s.R0 + 2.7
			box(b, "CargoBox", -wc / 2, wc / 2, s.Belt, gTop, midEnd, s.R1, WHITE:Lerp(paint, 0.3), M.SmoothPlastic, true)
			-- petites vitres arrière du combi
			box(b, "CamperWindow", -wc / 2 - 0.03, wc / 2 + 0.03, s.Belt + 0.5, gTop - 0.6, midEnd + 3.2, midEnd + 5.4, GLASS, M.Glass).Transparency = GLASS_T
			box(b, "RearWindow", -wc / 2 + 0.5, wc / 2 - 0.5, s.Belt + 0.6, gTop - 0.5, s.R1 - 0.02, s.R1 + 0.03, GLASS, M.Glass).Transparency = GLASS_T
		end
		box(b, "GlassSide", -wc / 2, wc / 2, s.Belt, gTop, s.R0, midEnd, GLASS, M.Glass).Transparency = GLASS_T
		if s.Rw - s.R1 > 0.1 then
			wedge(b, "GlassRear", -wc / 2, wc / 2, s.Belt, gTop, s.R1, s.Rw, false, GLASS, M.Glass).Transparency = GLASS_T
		elseif style ~= "Van" then
			box(b, "RearWindow", -wc / 2 + 0.2, wc / 2 - 0.2, s.Belt + 0.2, gTop - 0.1, s.R1 - 0.07, s.R1 + 0.02, GLASS, M.Glass).Transparency = GLASS_T
			box(b, "RearPanel", -wc / 2, wc / 2, s.Belt, gTop, s.R1, s.R1 + 0.1, paint, M.SmoothPlastic)
		end
		-- (v9.8) toit en DÔME : un ellipsoïde (bords et bouts arrondis, reflet
		-- continu) qui déborde un peu des vitres comme une vraie gouttière
		local roofL = s.R1 - s.R0 + 0.3
		local roofZ = (s.R0 + s.R1) / 2
		ell(b, "Roof", 0, gTop, roofZ, wc + 0.14, roofT * 2, roofL, roofColor, M.SmoothPlastic, nil, true)
		if full then
			-- ciel de toit clair (vu de l'intérieur) sous le dôme
			box(b, "Headliner", -wc / 2 + 0.3, wc / 2 - 0.3, gTop - roofT - 0.09, gTop - roofT - 0.03, s.R0 + 0.35, s.R1 - 0.35, HEADLINER, M.Fabric)
			if style == "Hatch" or style == "SUV" or style == "Limo" or style == "City" then
				-- toit panoramique : un dôme de verre fumé un peu plus haut au centre
				ell(b, "Sunroof", 0, gTop, roofZ - roofL * 0.1, (wc + 0.14) * 0.62, roofT * 2 + 0.05, roofL * 0.5, GLASS, M.Glass)
			end
			-- gouttières chromées le long du toit
			for _, sx in ipairs({ -1, 1 }) do
				rod(b, "DripRail", Vector3.new(sx * (wc / 2 + 0.05), gTop - 0.02, s.R0 + 0.15), Vector3.new(sx * (wc / 2 + 0.05), gTop - 0.02, s.R1 - 0.05), 0.07, CHROME, M.Metal)
			end
		end
		-- montants : A et B noirs (toit "flottant"), C couleur carrosserie
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * (wc / 2 + 0.03)
			slab(b, "PillarA", x, 0.12, s.Belt, s.Ws, gTop, s.R0, 0.3, HOUSING, M.SmoothPlastic)
			if s.Rw - s.R1 > 0.1 then
				slab(b, "PillarC", x, 0.12, gTop, s.R1, s.Belt, s.Rw, 0.5, paint, M.SmoothPlastic)
			else
				box(b, "PillarC", x - 0.06, x + 0.06, s.Belt, gTop, s.R1 - 0.45, s.R1 + 0.07, paint, M.SmoothPlastic)
			end
			if not full then
				-- (version garée : pas de montant B)
			elseif style ~= "Van" then
				local bz = if s.Doors == 4 then s.R0 + (s.R1 - s.R0) * 0.46 else s.R0 + (s.R1 - s.R0) * 0.62
				box(b, "PillarB", x - 0.06, x + 0.06, s.Belt, gTop, bz - 0.18, bz + 0.18, HOUSING, M.SmoothPlastic)
				if style == "Limo" then
					box(b, "PillarB", x - 0.06, x + 0.06, s.Belt, gTop, bz + 1.9, bz + 2.3, HOUSING, M.SmoothPlastic)
				end
			else
				box(b, "PillarB", x - 0.06, x + 0.06, s.Belt, gTop, midEnd - 0.1, midEnd + 0.2, HOUSING, M.SmoothPlastic)
			end
		end
	end
	-- rétroviseurs (sur pied, coque couleur carrosserie, miroir)
	for _, sx in ipairs({ -1, 1 }) do
		local mz = s.Ws + (if convertible then 0.3 else 0.25)
		local x0, x1 = sx * (s.W / 2 + (if full then 0.12 else -0.05)), sx * (s.W / 2 + 0.52)
		-- (v9.8) coque arrondie (ellipsoïde) + clignotant + miroir
		ell(b, "Mirror", (x0 + x1) / 2, s.Belt + 0.27, mz + 0.2, math.abs(x1 - x0), 0.42, 0.44, paint, M.SmoothPlastic)
		if full then
			local sx0, sx1 = sx * (s.W / 2 - 0.05), sx * (s.W / 2 + 0.2)
			box(b, "MirrorArm", math.min(sx0, sx1), math.max(sx0, sx1), s.Belt + 0.03, s.Belt + 0.15, mz + 0.12, mz + 0.26, HOUSING, M.SmoothPlastic)
			local gx0, gx1 = sx * (s.W / 2 + 0.2), sx * (s.W / 2 + 0.46)
			box(b, "MirrorGlass", math.min(gx0, gx1), math.max(gx0, gx1), s.Belt + 0.13, s.Belt + 0.39, mz + 0.36, mz + 0.4, CHROME, M.Glass)
			ell(b, "MirrorBlinker", sx * (s.W / 2 + 0.47), s.Belt + 0.25, mz + 0.16, 0.08, 0.1, 0.2, AMBER, M.SmoothPlastic)
		end
	end

	-- ░ ligne de ceinture chromée ░
	for _, sx in ipairs(if full then { -1, 1 } else {}) do
		-- (v9.8) jonc chromé au pied des vitres (posé sur le rebord de caisse)
		local tx0, tx1 = sx * (wc / 2 + 0.02), sx * (wc / 2 + 0.12)
		box(b, "BeltTrim", math.min(tx0, tx1), math.max(tx0, tx1), s.Belt - 0.02, s.Belt + 0.05, s.Ws + 0.05, if style == "Pickup" then s.Rw else s.Rw - 0.05, CHROME, M.Metal)
	end

	-- ░ optiques avant ░
	local lampY = s.Low + math.min(0.32, math.max(0.2, hf * 0.5))
	-- (haut du phare jamais au ras du dessus du capot)
	local lampTop = lampY + 0.24
	if math.abs(lampTop - hoodY0) < 0.05 then
		lampTop = hoodY0 - 0.06
	end
	if style == "Bubble" or style == "Van" then
		-- phares ronds rétro (cerclage)
		local van = style == "Van"
		local ly = if van then hoodY0 - 0.5 else s.Low + 0.42
		local d = if van then 0.95 else 1.15
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * s.W * 0.3
			cylZ(b, "HeadlightRim", x, ly, hoodZ0 + 0.02, 0.2, d, if van then CHROME else WHITE, M.SmoothPlastic)
			cylZ(b, "Headlight", x, ly, hoodZ0 - 0.06, 0.1, d - 0.3, LAMP, M.Glass)
			if full then
				cylZ(b, "HeadlightDot", x, ly, hoodZ0 - 0.11, 0.08, d * 0.26, DRL, M.SmoothPlastic)
			end
		end
	elseif hf < 0.1 then
		-- nez en coin (roadster) : phares couchés dans la pente du capot + feu de jour
		local function onHood(t: number, lift: number): (number, number)
			local z = hoodZ0 + t * (s.Ws - hoodZ0)
			return topAt(z) + lift, z
		end
		local ya, za = onHood(0.04, 0.03)
		local yb, zb = onHood(0.16, 0.03)
		for _, sx in ipairs({ -1, 1 }) do
			slab(b, "Headlight", sx * s.W * 0.2, s.W * 0.2, ya, za, yb, zb, 0.1, LAMP, M.Glass)
			if full then
				local yc, zc = onHood(0.06, 0.1)
				local yd, zd = onHood(0.09, 0.1)
				slab(b, "HeadlightDRL", sx * s.W * 0.2, s.W * 0.16, yc, zc, yd, zd, 0.04, DRL, M.SmoothPlastic)
			end
		end
	else
		for _, sx in ipairs({ -1, 1 }) do
			local x0, x1 = sx * s.W * 0.18, sx * s.W * 0.45
			if full then
				-- boîtier sombre, glace, projecteur rond, feu de jour
				box(b, "HeadlightHousing", math.min(x0, x1), math.max(x0, x1), lampY - 0.22, lampTop, hoodZ0 - 0.07, hoodZ0 + 0.1, HOUSING, M.SmoothPlastic)
				local l0, l1 = sx * (s.W * 0.18 + 0.05), sx * (s.W * 0.45 - 0.05)
				box(b, "Headlight", math.min(l0, l1), math.max(l0, l1), lampY - 0.18, lampTop - 0.04, hoodZ0 - 0.1, hoodZ0 + 0.05, LAMP, M.Glass)
				local d0, d1 = sx * (s.W * 0.18 + 0.08), sx * (s.W * 0.45 - 0.08)
				box(b, "HeadlightDRL", math.min(d0, d1), math.max(d0, d1), lampY - 0.14, lampY - 0.08, hoodZ0 - 0.13, hoodZ0 - 0.02, DRL, M.SmoothPlastic)
				cylZ(b, "Projector", sx * s.W * 0.37, (lampY - 0.08 + lampTop - 0.04) / 2, hoodZ0 - 0.11, 0.08, math.min(0.3, lampTop - lampY - 0.02), CHROME, M.Metal)
				box(b, "Indicator", math.min(sx * s.W * 0.45, sx * s.W * 0.49), math.max(sx * s.W * 0.45, sx * s.W * 0.49), lampY - 0.2, lampY + 0.12, hoodZ0 - 0.08, hoodZ0 + 0.1, AMBER, M.SmoothPlastic)
			else
				box(b, "Headlight", math.min(x0, x1), math.max(x0, x1), lampY - 0.2, lampTop, hoodZ0 - 0.08, hoodZ0 + 0.1, LAMP, M.Glass)
			end
		end
	end

	-- ░ feux arrière (bloc rouge + bande claire + feu de recul) ░
	local tailY = math.min(s.Belt - s.TrunkDrop - 0.35, s.Low + 0.45)
	local tailZ = if style == "Pickup" or convertible then trunkEnd + 0.02 else math.max(trunkEnd, s.Rw)
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * s.W * 0.28, sx * s.W * 0.48
		box(b, "Taillight", math.min(x0, x1), math.max(x0, x1), tailY - 0.26, tailY + 0.24, tailZ - 0.1, tailZ + 0.08, TAIL, M.Glass)
		if full then
			local i0, i1 = sx * s.W * 0.3, sx * s.W * 0.46
			box(b, "TailBar", math.min(i0, i1), math.max(i0, i1), tailY + 0.04, tailY + 0.14, tailZ - 0.05, tailZ + 0.11, TAIL_IN, M.SmoothPlastic)
			local r0, r1 = sx * s.W * 0.3, sx * s.W * 0.36
			box(b, "ReverseLight", math.min(r0, r1), math.max(r0, r1), tailY - 0.21, tailY - 0.05, tailZ - 0.05, tailZ + 0.11, REVERSE, M.Glass)
		end
	end

	-- ░ calandre (par modèle) + logo ░
	local grilleY = s.Clear + lowH * 0.66
	local gh = lowH * 0.22
	if style == "Bubble" then
		box(b, "Grille", -s.W * 0.14, s.W * 0.14, grilleY - gh * 0.6, grilleY + gh * 0.6, zF - 0.04, zF + 0.3, TRIM, M.Metal)
		box(b, "Smile", -0.8, 0.8, s.Clear + 0.36, s.Clear + 0.44, zF - 0.08, zF + 0.1, CHROME, M.Metal)
	elseif style == "Sports" then
		-- grande bouche noire (pas de chrome)
		box(b, "Grille", -s.W * 0.3, s.W * 0.3, grilleY - gh, grilleY + gh * 0.6, zF - 0.04, zF + 0.3, HOUSING, M.SmoothPlastic)
	else
		local gw = if offroad or style == "Limo" then 0.3 else 0.22
		local frame = if offroad or style == "Limo" then CHROME else TRIM
		box(b, "Grille", -s.W * gw, s.W * gw, grilleY - gh, grilleY + gh, zF - 0.04, zF + 0.3, frame, M.Metal)
		if full then
			box(b, "GrilleMesh", -s.W * gw + 0.12, s.W * gw - 0.12, grilleY - gh + 0.08, grilleY + gh - 0.08, zF - 0.07, zF + 0.1, HOUSING, M.DiamondPlate)
			if style == "Limo" then
				for k = -2, 2 do
					box(b, "GrilleBar", k * s.W * 0.1 - 0.05, k * s.W * 0.1 + 0.05, grilleY - gh + 0.08, grilleY + gh - 0.08, zF - 0.1, zF + 0.05, CHROME, M.Metal)
				end
			else
				for k = -1, 1, 2 do
					box(b, "GrilleBar", -s.W * gw + 0.1, s.W * gw - 0.1, grilleY + k * gh * 0.35 - 0.04, grilleY + k * gh * 0.35 + 0.04, zF - 0.1, zF + 0.05, if offroad then CHROME else GRAPHITE, M.Metal)
				end
			end
		end
	end
	if full then
		cylZ(b, "Badge", 0, grilleY, zF - 0.13, 0.08, 0.34, if style == "Limo" or style == "Sports" then CHROME else Color3.fromRGB(255, 120, 170), M.Metal)
	end

	-- ░ plaques ░
	if full then
		plate(b, "PlateFront", zF - 0.06, s.Clear + 0.14, -1, full, nil)
	end
	plate(b, "PlateRear", zB + 0.06, s.Clear + lowH * 0.55, 1, full, options.Plate)

	-- ░ bande bicolore (option) ░
	if stripe then
		if convertible then
			-- deux bandes de course : capot (suivent les 2 pans) + capot arrière
			for _, sx in ipairs({ -1, 1 }) do
				local x = sx * 0.32
				local ya, za = topAt(hoodZ0 + 0.05) + 0.03, hoodZ0 + 0.05
				local yb, zb = topAt(zm) + 0.03, zm
				local yc, zc = topAt(s.Ws - 0.05) + 0.03, s.Ws - 0.05
				slab(b, "Stripe", x, 0.36, ya, za, yb, zb, 0.04, stripe, M.SmoothPlastic)
				slab(b, "Stripe", x, 0.36, yb, zb, yc, zc, 0.04, stripe, M.SmoothPlastic)
				box(b, "Stripe", x - 0.18, x + 0.18, s.Belt - s.TrunkDrop, s.Belt - s.TrunkDrop + 0.04, s.Rw + 0.05, trunkEnd - 0.05, stripe, M.SmoothPlastic)
			end
		elseif style ~= "Van" and style ~= "Bubble" then
			-- filet latéral (coachline) sur toute la longueur
			local yS = s.Low + (s.Belt - s.Low) * 0.36
			local z0 = hoodZ0 + (s.Ws - hoodZ0) * 0.35
			if topAt(z0) < yS + 0.12 then
				z0 = s.Ws
			end
			local z1 = trunkEnd - 0.25
			for _, sx in ipairs({ -1, 1 }) do
				local x0, x1 = sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.07)
				box(b, "Stripe", math.min(x0, x1), math.max(x0, x1), yS - 0.07, yS + 0.07, z0, z1, stripe, M.SmoothPlastic)
			end
		end
	end

	-- ░ détails (joints de portes, poignées, échappement, intérieur) ░
	if full then
		local bz = if s.Doors == 4 then s.R0 + (s.R1 - s.R0) * 0.46 else s.R0 + (s.R1 - s.R0) * 0.62
		if style == "Van" then
			bz = s.R0 + 2.7
		elseif convertible then
			bz = s.Rw - 0.3
		end
		local doorFront = if convertible then s.Ws + 0.6 else s.Ws + 0.12
		for _, sx in ipairs({ -1, 1 }) do
			local x0, x1 = sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.08)
			local lo, hi = math.min(x0, x1), math.max(x0, x1)
			box(b, "DoorSeam", lo, hi, s.Clear + 0.35, s.Belt - 0.15, doorFront - 0.03, doorFront + 0.03, HOUSING, M.SmoothPlastic)
			box(b, "DoorSeam", lo, hi, s.Clear + 0.35, s.Belt - 0.15, bz - 0.03, bz + 0.03, HOUSING, M.SmoothPlastic)
			local hx0, hx1 = sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.2)
			box(b, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), s.Belt - 0.5, s.Belt - 0.36, bz - 0.75, bz - 0.25, CHROME, M.Metal)
			if s.Doors == 4 and style ~= "Pickup" then
				local rz = if style == "Limo" then bz + 2.3 else s.Rw - 0.2
				box(b, "DoorSeam", lo, hi, s.Clear + 0.35, s.Belt - 0.15, rz - 0.03, rz + 0.03, HOUSING, M.SmoothPlastic)
				box(b, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), s.Belt - 0.5, s.Belt - 0.36, rz - 0.75, rz - 0.25, CHROME, M.Metal)
			elseif style == "Pickup" then
				local rz = s.Rw
				box(b, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), s.Belt - 0.5, s.Belt - 0.36, rz - 0.75, rz - 0.25, CHROME, M.Metal)
			end
		end
		cylZ(b, "Exhaust", s.W * 0.28, s.Clear + 0.12, zB + 0.05, 0.7, 0.34, CHROME, M.Metal)
		interior(b, s, seatZ, seatTop, style)
		-- ░ (v9.8) épaules arrondies le long de la ligne de caisse ░
		if not convertible then
			local pts = { Vector3.new(0, topAt(hoodZ0 + 0.25), hoodZ0 + 0.25) }
			if curved then
				table.insert(pts, Vector3.new(0, ym, zm))
			end
			table.insert(pts, Vector3.new(0, s.Belt, s.Ws))
			local endZ = if style == "Pickup" then trunkEnd - 0.15 else s.Rw
			table.insert(pts, Vector3.new(0, s.Belt, endZ))
			if style ~= "Pickup" and trunkEnd - s.Rw > 0.4 then
				table.insert(pts, Vector3.new(0, s.Belt - s.TrunkDrop, s.Rw + 0.05))
				table.insert(pts, Vector3.new(0, s.Belt - s.TrunkDrop, trunkEnd - 0.2))
			end
			for _, sx in ipairs({ -1, 1 }) do
				for k = 1, #pts - 1 do
					local a, c = pts[k], pts[k + 1]
					if (c - a).Magnitude > 0.2 then
						rod(b, "Shoulder", Vector3.new(sx * (s.W / 2 - 0.1), a.Y - 0.1, a.Z), Vector3.new(sx * (s.W / 2 - 0.1), c.Y - 0.1, c.Z), 0.3, paint, M.SmoothPlastic)
					end
				end
			end
		end
		-- ░ (v9.8) joints du capot, trappe à carburant, répétiteurs, nervure ░
		for _, sx in ipairs({ -1, 1 }) do
			local gx = sx * (s.W / 2 - 0.42)
			local z1 = hoodZ0 + 0.35
			local segs = if curved then { { z1, zm }, { zm, s.Ws - 0.3 } } else { { z1, s.Ws - 0.3 } }
			for _, seg in ipairs(segs) do
				slab(b, "HoodSeam", gx, 0.05, topAt(seg[1]), seg[1], topAt(seg[2]), seg[2], 0.07, GAP, M.SmoothPlastic)
			end
			local fx0, fx1 = sx * (s.W / 2 - 0.03), sx * (s.W / 2 + 0.035)
			box(b, "Crease", math.min(fx0, fx1), math.max(fx0, fx1), s.Low - 0.32, s.Low - 0.26, s.AxleF + ra + 0.3, s.AxleR - ra - 0.3, paint, M.SmoothPlastic)
			ell(b, "Repeater", sx * (s.W / 2 + 0.01), s.Low + 0.05, s.AxleF + ra + 0.2, 0.08, 0.14, 0.34, AMBER, M.SmoothPlastic)
		end
		cylX(b, "FuelCap", -(s.W / 2 + 0.01), s.Belt - 0.5, math.min(s.AxleR - ra - 0.4, s.Rw - 0.5), 0.1, 0.45, paint:Lerp(GAP, 0.12), M.SmoothPlastic)
		-- essuie-glaces posés sur le pare-brise
		if not convertible then
			local dy, dz = gTop - s.Belt, s.R0 - s.Ws
			local n = Vector3.new(0, dz, -dy).Unit * 0.06
			local function onGlass(x: number, y: number): Vector3
				return Vector3.new(x, y, s.Ws + (y - s.Belt) / dy * dz) + n
			end
			for _, x in ipairs({ -wc * 0.42, wc * 0.02 }) do
				rod(b, "Wiper", onGlass(x, s.Belt + 0.1), onGlass(x + wc * 0.36, s.Belt + 0.24), 0.07, GAP, M.SmoothPlastic)
			end
		end
	end

	-- ░ particularités de chaque modèle ░
	if style == "Bubble" then
		-- roue de secours ronde à l'arrière
		cylZ(b, "SpareWheel", 0, s.Low + 0.55, trunkEnd + 0.25, 0.5, 1.5, TYRE, M.Rubber)
		cylZ(b, "SpareRim", 0, s.Low + 0.55, trunkEnd + 0.3, 0.52, 0.9, WHITE, M.SmoothPlastic)
		if full then
			-- cils kawaii au-dessus des phares ronds
			for _, sx in ipairs({ -1, 1 }) do
				for k = -1, 1 do
					local x = sx * s.W * 0.3 + k * 0.28
					boxRotX(b, "Lash", x, s.Low + 1.08, hoodZ0 - 0.04, 0.07, 0.07, 0.3, math.rad(55), BLACK, M.SmoothPlastic)
				end
			end
		end
	elseif style == "Hatch" then
		box(b, "Spoiler", -wc / 2 + 0.2, wc / 2 - 0.2, gTop + 0.02, s.Roof - 0.12, s.R1 - 0.05, s.R1 + 0.6, GRAPHITE, M.SmoothPlastic)
		if full then
			box(b, "BrakeLight3", -0.5, 0.5, gTop + 0.06, s.Roof - 0.16, s.R1 + 0.6, s.R1 + 0.64, TAIL, M.Glass)
		end
	elseif style == "SUV" then
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "RoofRail", sx * (wc / 2 - 0.45), sx * (wc / 2 - 0.25), s.Roof - 0.2, s.Roof + 0.22, s.R0 + 0.4, s.R1 - 0.4, TRIM, M.Metal)
		end
		if full then
			for _, z in ipairs({ s.R0 + 1.2, s.R1 - 1.2 }) do
				box(b, "CrossBar", -wc / 2 + 0.45, wc / 2 - 0.45, s.Roof + 0.04, s.Roof + 0.17, z - 0.1, z + 0.1, TRIM, M.Metal)
			end
		end
		cylZ(b, "SpareWheel", 0, s.Belt + 0.5, trunkEnd + 0.4, 0.7, 2.2, TYRE, M.Rubber)
		cylZ(b, "SpareCover", 0, s.Belt + 0.5, trunkEnd + 0.5, 0.6, 1.7, paint, M.SmoothPlastic)
		box(b, "SkidPlate", -s.W * 0.3, s.W * 0.3, s.Clear - 0.12, s.Clear + 0.2, zF + 0.1, zF + 1.2, CHROME, M.Metal)
	elseif style == "Pickup" then
		box(b, "RollBar", -wc / 2 + 0.3, wc / 2 - 0.3, s.Belt + 0.9, s.Belt + 1.15, s.Rw + 0.55, s.Rw + 0.8, TRIM, M.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "RollBarPost", sx * (wc / 2 - 0.3) - 0.12, sx * (wc / 2 - 0.3) + 0.12, s.Belt, s.Belt + 1.15, s.Rw + 0.55, s.Rw + 0.8, TRIM, M.Metal)
		end
		if full then
			-- rampe de 4 phares ronds sur l'arceau (sans lumière)
			for k = -3, 3, 2 do
				cylZ(b, "BarLamp", k * 0.45, s.Belt + 1.33, s.Rw + 0.67, 0.28, 0.36, LAMP, M.Glass)
			end
			box(b, "TowHitch", -0.25, 0.25, s.Clear - 0.02, s.Clear + 0.2, zB + 0.04, zB + 0.5, GRAPHITE, M.Metal)
		end
		box(b, "SkidPlate", -s.W * 0.3, s.W * 0.3, s.Clear - 0.12, s.Clear + 0.2, zF + 0.1, zF + 1.2, CHROME, M.Metal)
	elseif style == "Van" then
		-- bande couleur carrosserie sur la cellule claire (bicolore) + porte
		-- coulissante + galerie avec planche de surf + store banne roulé
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "VanStripe", sx * (wc / 2 - 0.02), sx * (wc / 2 + 0.05), s.Belt + 0.1, s.Belt + 0.45, s.R0 + 2.75, s.R1 - 0.2, paint, M.SmoothPlastic)
		end
		if full then
			box(b, "SlideRail", wc / 2 - 0.02, wc / 2 + 0.06, s.Roof - roofT - 0.75, s.Roof - roofT - 0.65, s.R0 + 2.8, s.R0 + 7, TRIM, M.Metal)
			for _, z in ipairs({ s.R0 + 1.4, s.R1 - 1.2 }) do
				box(b, "RackBar", -wc / 2 + 0.3, wc / 2 - 0.3, s.Roof - 0.14, s.Roof + 0.2, z - 0.12, z + 0.12, TRIM, M.Metal)
			end
			local boardL = math.min(s.R1 - s.R0 - 0.6, 7.2)
			local bc = (s.R0 + s.R1) / 2
			local surf = Color3.fromRGB(120, 220, 230)
			box(b, "Surfboard", -0.75, 0.75, s.Roof + 0.2, s.Roof + 0.36, bc - boardL / 2 + 0.75, bc + boardL / 2 - 0.4, surf, M.SmoothPlastic)
			cylY(b, "SurfboardNose", 0, s.Roof + 0.28, bc - boardL / 2 + 0.75, 0.16, 1.5, surf)
			box(b, "SurfboardStripe", -0.1, 0.1, s.Roof + 0.36, s.Roof + 0.4, bc - boardL / 2 + 0.9, bc + boardL / 2 - 0.55, Color3.fromRGB(255, 150, 196), M.SmoothPlastic)
			cylZ(b, "Awning", -(wc / 2 + 0.1), gTop - 0.1, s.R0 + 4.9, 4.2, 0.36, Color3.fromRGB(255, 214, 120), M.Fabric)
		end
	elseif style == "Sports" then
		-- aileron, prises d'air, doubles échappements, diffuseur
		box(b, "Wing", -s.W / 2 + 0.3, s.W / 2 - 0.3, s.Belt + 0.75, s.Belt + 0.9, trunkEnd - 1.1, trunkEnd - 0.2, GRAPHITE, M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "WingPost", sx * s.W * 0.3 - 0.08, sx * s.W * 0.3 + 0.08, s.Belt - s.TrunkDrop, s.Belt + 0.76, trunkEnd - 0.75, trunkEnd - 0.5, GRAPHITE, M.SmoothPlastic)
			-- (prise d'air devant l'arche arrière, jamais devant la roue)
			box(b, "SideIntake", sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.19), s.Clear + 0.45, s.Low - 0.1, s.AxleR - ra - 1.2, s.AxleR - ra - 0.15, TRIM, M.Metal)
		end
		cylZ(b, "Exhaust2", -s.W * 0.28, s.Clear + 0.12, zB + 0.05, 0.7, 0.34, CHROME, M.Metal)
		if full then
			for k = -1, 1 do
				box(b, "DiffuserFin", k * 0.6 - 0.05, k * 0.6 + 0.05, s.Clear - 0.02, s.Clear + 0.24, zB - 0.5, zB + 0.12, GRAPHITE, M.SmoothPlastic)
			end
		end
	elseif style == "Limo" then
		for _, sx in ipairs({ -1, 1 }) do
			-- (entre les deux arches : jamais devant les roues)
			box(b, "ChromeSill", sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.19), s.Clear + 0.1, s.Clear + 0.22, s.AxleF + ra + 0.1, s.AxleR - ra - 0.1, CHROME, M.Metal)
		end
		cylZ(b, "Ornament", 0, s.Belt - 0.02, hoodZ0 + 0.6, 0.3, 0.3, CHROME, M.Metal)
	end

	-- attributs (siège du conducteur : repère du pivot)
	local seatX = -(s.W - 2 * s.Inset) * 0.22
	model:SetAttribute("CarId", type(carId) == "string" and carId or kind)
	model:SetAttribute("CarKind", kind)
	model:SetAttribute("Length", s.L * scale.Z)
	model:SetAttribute("Width", s.W * scale.X)
	model:SetAttribute("Height", CarModels.Dimensions(kind).Y * scale.Y)
	model:SetAttribute("WheelRadius", s.WheelD / 2 * math.min(scale.Y, scale.Z))
	model:SetAttribute("SeatCF", CFrame.new(P(b, seatX, seatTop, seatZ)))
	model:SetAttribute("PartCount", b.Count)
	return model
end

return CarModels
