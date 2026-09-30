--[[
	CarModels (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > CarModels

	🚗 Les voitures de Dopamine Town, construites en pièces : utilisé par le
	SERVEUR (voitures garées de la ville, TownKit.Car ; voiture qu'on conduit,
	CarService) ET par le CLIENT (circulation, concession, garage du manoir,
	fenêtre "Mes voitures"). Pur : que des Instances, aucun service.

	8 modèles :
	  BubbleCar : petite citadine ronde kawaii (phares ronds chromés, toit blanc) ;
	  CityCar   : citadine 3 portes (type 500) ;
	  Hatchback : compacte 5 portes (type Golf), becquet ;
	  Pickup    : pick-up (cabine + benne ouverte, grosses roues) ;
	  SUV       : SUV compact (barres de toit, protections noires) ;
	  Van       : combi bicolore (face en V, galerie + planche de surf) ;
	  SportsCar : roadster décapotable (bossages derrière les sièges) ;
	  Limo      : grande berline 3 volumes (calandre chromée, 3 vitres).

	v9.9 (CARS99) "100x plus réalistes" — la carrosserie est une vraie COQUE :
	  - PROPORTIONS réelles (1 m ≈ 2,97 studs, avatar 5,2) : empattement et
	    porte-à-faux de vraies voitures, garde au sol ~0,45, roues de ~0,65 m
	    DANS leurs passages de roue (plus de roues qui dépassent), ceinture de
	    caisse plus haute, pavillon plus bas, montants inclinés (tumblehome :
	    les vitres rentrent vers le toit) ;
	  - la coque (capot, pare-brise, toit, lunette, coffre, épaules, ailes,
	    coins arrondis vus de dessus) est un MAILLAGE de triangles (2 coins
	    WedgePart par triangle, face extérieure exactement sur la surface :
	    aucun jour, aucun z-fighting) tendu entre des SECTIONS le long de la
	    voiture ; flancs verticaux découpés en arc autour des roues (arches
	    lisses), passages de roue noirs, bas de caisse ;
	  - vitres teintées (Transparency + Reflectance), montants A/B/C, joints
	    de portes, poignées, rétroviseurs (coque, miroir, clignotant),
	    essuie-glaces, gouttières, antenne requin, trappe à carburant ;
	  - blocs optiques (boîtier, réflecteur chromé, 2 projecteurs, feu de
	    jour, glace claire, répétiteur d'angle) ; feux arrière (glace rouge,
	    barre, recul, clignotant, bandeau), 3e feu stop, plaques, logos ;
	  - pneus avec flanc, jantes (lèvre, voile sombre, rayons), disques de
	    frein, étriers ; habitacle (sièges + appuie-tête, banquette, planche
	    de bord, écran, volant sur sa colonne, console, ciel de toit) ;
	  - peinture vernie (Reflectance 0,1 en "Full").
	NIVEAUX DE DÉTAIL (opts.Detail) :
	  "Full" (≤ ~400 pièces : sa voiture, concession, garage, aperçu),
	  "Mid"  (≤ ~120 : circulation, voitures garées près de la caméra),
	  "Low"  (≤ ~45 : loin / serveur),
	  "Parked" = "Low" (ancien nom : voitures garées du serveur, budget de la
	  ville ; TownTraffic les remplace par "Mid" près de la caméra).
	ROUES ANIMABLES : chaque pièce d'une roue porte l'attribut "Wheel" (index
	dans WheelPositions) et "Spin" = true si elle tourne avec la roue (l'étrier
	ne fait que braquer). En "Full", 2 pivots invisibles par roue ("WheelSteer",
	"WheelSpin") : CarService les relie par des Motor6D et CarClient règle
	leur Transform (rotation + braquage) sur TOUS les clients.
	Pas de lumière, pas de Neon, pas de son (le client ajoute de petits phares
	la nuit à SA voiture seulement).

	API (inchangée) :
	  CarModels.Build(carId, color?, opts?) -> Model
	    color : Color3 | Id de Config.Cars.Colors | nil (couleur par défaut)
	    opts  : { Detail = "Full" | "Mid" | "Low" | "Parked", Plate = "TEXTE"?,
	              Scale = number | Vector3 (x = largeur, y = hauteur, z = longueur),
	              Stripe = true | Color3 ?, RoofColor = Color3 ? }
	    Repère : pivot = centre du DESSOUS (au sol), avant vers -Z. Tout est
	    ANCRÉ ; PrimaryPart "Root" = boîte de collision invisible (seule pièce
	    CanCollide), les autres pièces sont du décor (CanCollide / CanQuery /
	    CanTouch false). Attributs : CarId, CarKind, Length, Width, Height,
	    SeatCF (CFrame du siège du conducteur, repère du pivot), WheelRadius,
	    Lod (3 / 2 / 1), PartCount.
	  CarModels.Dimensions(carId) -> Vector3 (largeur, hauteur, longueur)
	  CarModels.WheelPositions(carId) -> { Vector3 } (centres des roues, repère du pivot)
	  CarModels.ColorOf(carId, color?) -> Color3
	  CarModels.LockReason(data, carId) -> string? (nil = débloquée ; texte traduit)
	  CarModels.Kinds : ids des modèles
	  CarModels.Handling(carId) -> { Speed, Accel, Grip, Comfort, Stars }
	  CarModels.Repaint(model, carId, color?) (repeint les pièces "Paint")
	  CarModels.WheelRig(model) -> rig (v9.9) : pour animer un modèle ANCRÉ
	    (circulation, plateau tournant) : { Body = { parts }, BodyOff = { CFrame },
	    Wheels = { { Center: CFrame, Front: boolean, Radius: number,
	    Spin = { parts }, SpinOff = { CFrame }, Steer = { parts }, SteerOff = { CFrame } } } }
	    (décalages dans le repère du pivot / du centre de la roue).
	  CarModels.PoseRig(rig, pivot, spin, steer, bob?) -> (parts, frames) : pose
	    complète (à passer à workspace:BulkMoveTo) ; bob = CFrame de caisse
	    (tangage / roulis / pompage de la suspension).
]]

local Config = require(script.Parent.Config)

local CarModels = {}

local M = Enum.Material
local PI = math.pi
local V3 = Vector3.new

export type Spec = {
	L: number, -- longueur
	W: number, -- largeur (flancs)
	WheelD: number, -- diamètre des roues
	TyreW: number, -- largeur des pneus
	Clear: number, -- dessous de la carrosserie (garde au sol)
	Low: number, -- dessus du flanc vertical (au-dessus des arches)
	Belt: number, -- ligne de ceinture (bas des vitres) au milieu
	Roof: number, -- dessus du toit (sommet du pare-brise pour le roadster)
	AxleF: number, -- z de l'essieu avant
	AxleR: number, -- z de l'essieu arrière
	Ws: number, -- pied du pare-brise
	R0: number, -- avant du toit
	R1: number, -- arrière du toit
	Rw: number, -- pied de la lunette arrière
	Inset: number, -- rentré du bord du toit (de chaque côté)
	HoodF: number, -- hauteur du capot à l'avant
	HoodR: number, -- hauteur du capot au pied du pare-brise
	Deck: number, -- hauteur du coffre / du hayon (benne : dessus des ridelles)
	BeltRise: number, -- montée de la ceinture de l'avant à l'arrière
	Tumble: number, -- rentré du bas des vitres
	NoseR: number, -- rayon des coins avant (vu de dessus)
	TailR: number, -- rayon des coins arrière
	NoseLow: number?, -- dessus du flanc au nez (roadster : nez plongeant)
	Doors: number, -- 2 ou 4
	Style: string,
}

local SPECS: { [string]: Spec } = {
	BubbleCar = { L = 9.2, W = 5.2, WheelD = 1.95, TyreW = 0.75, Clear = 0.5, Low = 2.45, Belt = 3.1, Roof = 4.95, AxleF = -2.7, AxleR = 2.75, Ws = -2.7, R0 = -0.7, R1 = 2.9, Rw = 4.25, Inset = 0.66, HoodF = 2.75, HoodR = 3.0, Deck = 3.2, BeltRise = 0, Tumble = 0.32, NoseR = 1.0, TailR = 0.9, Doors = 2, Style = "Bubble" },
	CityCar = { L = 10.6, W = 5.1, WheelD = 1.95, TyreW = 0.8, Clear = 0.45, Low = 2.45, Belt = 3.2, Roof = 4.95, AxleF = -3.15, AxleR = 3.45, Ws = -2.65, R0 = -0.4, R1 = 3.5, Rw = 4.95, Inset = 0.64, HoodF = 2.75, HoodR = 3.1, Deck = 3.35, BeltRise = 0, Tumble = 0.3, NoseR = 0.9, TailR = 0.8, Doors = 2, Style = "City" },
	Hatchback = { L = 12.2, W = 5.4, WheelD = 2.05, TyreW = 0.85, Clear = 0.45, Low = 2.5, Belt = 3.25, Roof = 4.95, AxleF = -3.75, AxleR = 3.8, Ws = -2.95, R0 = -0.35, R1 = 4.3, Rw = 5.75, Inset = 0.62, HoodF = 2.8, HoodR = 3.15, Deck = 3.4, BeltRise = 0, Tumble = 0.3, NoseR = 1.0, TailR = 0.85, Doors = 4, Style = "Hatch" },
	Pickup = { L = 13, W = 6.0, WheelD = 2.5, TyreW = 1.0, Clear = 0.75, Low = 3.0, Belt = 3.8, Roof = 5.6, AxleF = -4.0, AxleR = 3.9, Ws = -2.7, R0 = -0.95, R1 = 1.55, Rw = 1.55, Inset = 0.5, HoodF = 3.4, HoodR = 3.75, Deck = 3.8, BeltRise = 0, Tumble = 0.25, NoseR = 0.8, TailR = 0.6, Doors = 2, Style = "Pickup" },
	SUV = { L = 12.8, W = 5.8, WheelD = 2.35, TyreW = 0.95, Clear = 0.65, Low = 2.8, Belt = 3.55, Roof = 5.6, AxleF = -3.85, AxleR = 3.95, Ws = -3.05, R0 = -0.6, R1 = 4.9, Rw = 5.95, Inset = 0.55, HoodF = 3.1, HoodR = 3.45, Deck = 3.7, BeltRise = 0, Tumble = 0.28, NoseR = 1.0, TailR = 0.9, Doors = 4, Style = "SUV" },
	Van = { L = 13, W = 5.8, WheelD = 2.15, TyreW = 0.85, Clear = 0.55, Low = 2.55, Belt = 3.45, Roof = 6.3, AxleF = -4.3, AxleR = 4.15, Ws = -5.35, R0 = -3.85, R1 = 6.15, Rw = 6.42, Inset = 0.45, HoodF = 2.85, HoodR = 3.35, Deck = 3.6, BeltRise = 0, Tumble = 0.28, NoseR = 0.85, TailR = 0.75, Doors = 2, Style = "Van" },
	SportsCar = { L = 12.8, W = 5.9, WheelD = 2.05, TyreW = 1.05, Clear = 0.35, Low = 2.4, Belt = 2.8, Roof = 3.75, AxleF = -3.8, AxleR = 3.8, Ws = -1.25, R0 = -0.2, R1 = 1.85, Rw = 2.3, Inset = 0.5, HoodF = 2.1, HoodR = 2.6, Deck = 2.75, BeltRise = 0.1, Tumble = 0.3, NoseR = 1.2, TailR = 1.1, NoseLow = 1.8, Doors = 2, Style = "Sports" },
	Limo = { L = 15.2, W = 5.7, WheelD = 2.1, TyreW = 0.9, Clear = 0.5, Low = 2.55, Belt = 3.3, Roof = 4.95, AxleF = -4.9, AxleR = 4.8, Ws = -3.4, R0 = -0.8, R1 = 3.45, Rw = 4.95, Inset = 0.62, HoodF = 2.85, HoodR = 3.2, Deck = 3.4, BeltRise = 0, Tumble = 0.3, NoseR = 1.1, TailR = 1.0, Doors = 4, Style = "Limo" },
}
CarModels.Specs = SPECS
CarModels.Kinds = { "BubbleCar", "CityCar", "Hatchback", "Pickup", "SUV", "Van", "SportsCar", "Limo" }

-- Couleurs fixes
local GLASS = Color3.fromRGB(58, 74, 92) -- verre teinté (transparence automatique)
local GLASS_T = 0.4
local TRIM = Color3.fromRGB(30, 31, 36) -- plastique noir
local TYRE = Color3.fromRGB(28, 28, 32)
local SIDEWALL = Color3.fromRGB(44, 44, 50)
local CHROME = Color3.fromRGB(214, 218, 226)
local LAMP = Color3.fromRGB(255, 250, 232)
local LENS = Color3.fromRGB(226, 236, 246)
local TAIL = Color3.fromRGB(196, 24, 40)
local TAIL_IN = Color3.fromRGB(255, 90, 100)
local AMBER = Color3.fromRGB(255, 160, 50)
local PLATE = Color3.fromRGB(248, 248, 244)
local PLATE_BAND = Color3.fromRGB(40, 80, 190)
local SEAT = Color3.fromRGB(58, 52, 58)
local SEAT2 = Color3.fromRGB(78, 70, 76)
local WHITE = Color3.new(1, 1, 1)
local DISC = Color3.fromRGB(128, 130, 138)
local CAL_RED = Color3.fromRGB(212, 40, 52)
local CAL_DARK = Color3.fromRGB(70, 70, 80)
local HOUSING = Color3.fromRGB(22, 22, 28)
local DRL = Color3.fromRGB(255, 252, 244)
local REVERSE = Color3.fromRGB(236, 236, 240)
local SCREEN = Color3.fromRGB(30, 60, 96)
local GRAPHITE = Color3.fromRGB(52, 54, 62)
local GAP = Color3.fromRGB(18, 18, 22)
local HEADLINER = Color3.fromRGB(206, 202, 196)
local LINER = Color3.fromRGB(16, 16, 20)
local CARPET = Color3.fromRGB(40, 38, 42)

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
	return Vector3.new(s.W, s.Roof, s.L)
end

-- (v9.9) roues DANS les passages : face extérieure du pneu 0,22 en retrait du
-- flanc (la jante bombée et le cache-moyeu arrivent à l'aplomb de la caisse)
function CarModels.WheelPositions(carId: string?): { Vector3 }
	local s = SPECS[kindOf(carId)]
	local x = s.W / 2 - s.TyreW / 2 - 0.22
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

-- Comportement au volant par modèle (multiplicateurs de la conduite de
-- CarClient : vitesse max, accélération, adhérence) + confort, et notes de 1
-- à 5 étoiles (fenêtre "Mes voitures", pupitres de la concession)
export type Handling = { Speed: number, Accel: number, Grip: number, Comfort: number, Stars: { Speed: number, Accel: number, Grip: number, Comfort: number } }
local HANDLING: { [string]: { number } } = {
	BubbleCar = { 0.8, 0.9, 1.05, 3 },
	CityCar = { 0.88, 1.0, 1.1, 3 },
	Hatchback = { 0.95, 1.05, 1.05, 3 },
	Pickup = { 0.92, 0.9, 0.85, 3 },
	SUV = { 0.95, 0.9, 0.9, 5 },
	Van = { 0.85, 0.8, 0.85, 4 },
	SportsCar = { 1.16, 1.35, 1.2, 2 },
	Limo = { 1.0, 0.85, 0.8, 5 },
}
function CarModels.Handling(carId: string?): Handling
	local h = HANDLING[kindOf(carId)] or HANDLING.CityCar
	local function stars(v: number): number
		return math.clamp(math.floor(v + 0.5), 1, 5)
	end
	return {
		Speed = h[1],
		Accel = h[2],
		Grip = h[3],
		Comfort = h[4],
		Stars = { Speed = stars((h[1] - 0.7) / 0.1), Accel = stars((h[2] - 0.7) / 0.13), Grip = stars((h[3] - 0.7) / 0.1), Comfort = stars(h[4]) },
	}
end

-- Repeint un modèle déjà construit (pièces marquées "Paint") : pour changer
-- de couleur SANS reconstruire (fenêtre "Mes voitures", concession)
function CarModels.Repaint(model: Instance, carId: string?, color: any?)
	local paint = CarModels.ColorOf(carId, color)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Paint") then
			d.Color = paint
		end
	end
	if model:IsA("Model") then
		model:SetAttribute("PaintColor", paint)
	end
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
-- Pièces (repère local : sol au centre, avant vers -Z)
----------------------------------------------------------------------

type B = {
	Model: Model,
	S: Vector3, -- échelle
	Count: number,
	Paint: Color3,
	Gloss: number, -- Reflectance de la peinture
	Lod: number, -- 3 Full, 2 Mid, 1 Low
	WheelTag: number?, -- (roues) index de la roue en cours
	Spin: boolean?, -- (roues) la pièce tourne avec la roue
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
	if color == b.Paint then
		p:SetAttribute("Paint", true)
		if material == M.SmoothPlastic then
			p.Reflectance = b.Gloss
		end
	elseif color == GLASS then
		p.Transparency = GLASS_T
		p.Reflectance = if b.Lod >= 3 then 0.2 else 0.12
	end
	if b.WheelTag then
		p:SetAttribute("Wheel", b.WheelTag)
		if b.Spin then
			p:SetAttribute("Spin", true)
		end
	end
	p.Parent = b.Model
	b.Count += 1
	return p
end

-- point local -> point du modèle (échelle)
local function P(b: B, x: number, y: number, z: number): Vector3
	return Vector3.new(x * b.S.X, y * b.S.Y, z * b.S.Z)
end
local function PV(b: B, v: Vector3): Vector3
	return Vector3.new(v.X * b.S.X, v.Y * b.S.Y, v.Z * b.S.Z)
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

-- Cylindre couché le long de X (roues)
local function cylX(b: B, name: string, x: number, y: number, z: number, length: number, diameter: number, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local m = math.min(b.S.Y, b.S.Z)
	local p = newPart(b, "Part", name, Vector3.new(length * b.S.X, diameter * m, diameter * m), CFrame.new(P(b, x, y, z)), color, material or M.SmoothPlastic, shadow)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Cylindre le long de Z (phares ronds, échappements)
local function cylZ(b: B, name: string, x: number, y: number, z: number, length: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local m = math.min(b.S.X, b.S.Y)
	local p = newPart(b, "Part", name, Vector3.new(length * b.S.Z, diameter * m, diameter * m), CFrame.new(P(b, x, y, z)) * CFrame.Angles(0, PI / 2, 0), color, material or M.SmoothPlastic)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Cylindre debout (axe Y)
local function cylY(b: B, name: string, x: number, y: number, z: number, height: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local m = math.min(b.S.X, b.S.Z)
	local p = newPart(b, "Part", name, Vector3.new(height * b.S.Y, diameter * m, diameter * m), CFrame.new(P(b, x, y, z)) * CFrame.Angles(0, 0, PI / 2), color, material or M.SmoothPlastic)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Bloc tourné autour de X (arches, rayons, étriers) : centre, taille, angle (rad)
local function boxRotX(b: B, name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number, angle: number, color: Color3, material: Enum.Material?): BasePart
	local m = math.min(b.S.Y, b.S.Z)
	return newPart(b, "Part", name, Vector3.new(sx * b.S.X, sy * m, sz * m), CFrame.new(P(b, x, y, z)) * CFrame.Angles(angle, 0, 0), color, material or M.SmoothPlastic)
end

-- Ellipsoïde (SpecialMesh "Sphere" qui remplit la pièce). Taille = extents.
local function ell(b: B, name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number, color: Color3, material: Enum.Material?, rot: CFrame?): BasePart
	local cf = CFrame.new(P(b, x, y, z))
	if rot then
		cf *= rot
	end
	local p = newPart(b, "Part", name, Vector3.new(sx * b.S.X, sy * b.S.Y, sz * b.S.Z), cf, color, material or M.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Tige (cylindre) entre deux points du repère local
local function rod(b: B, name: string, a: Vector3, c: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart?
	local pa, pc = PV(b, a), PV(b, c)
	local len = (pc - pa).Magnitude
	if len < 0.03 then
		return nil
	end
	local m = math.min(b.S.X, b.S.Y)
	local cf = CFrame.lookAt((pa + pc) / 2, pc) * CFrame.Angles(0, PI / 2, 0)
	local p = newPart(b, "Part", name, Vector3.new(len, diameter * m, diameter * m), cf, color, material or M.SmoothPlastic)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Bande plate posée sur une surface (montants, joints) : de `a` à `c`, face
-- vers `n` (normale extérieure), largeur `w`, épaisseur `t` (enfoncée de moitié)
local function strip(b: B, name: string, a: Vector3, c: Vector3, n: Vector3, w: number, t: number, color: Color3, material: Enum.Material?, lift: number?): BasePart?
	local pa, pc = PV(b, a), PV(b, c)
	local d = pc - pa
	if d.Magnitude < 0.03 then
		return nil
	end
	local dir = d.Unit
	local nn = (n - dir * n:Dot(dir))
	if nn.Magnitude < 1e-3 then
		return nil
	end
	nn = nn.Unit
	local x = nn:Cross(dir).Unit
	return newPart(b, "Part", name, Vector3.new(w, t, d.Magnitude), CFrame.fromMatrix((pa + pc) / 2 + nn * (lift or 0), x, nn, -dir), color, material or M.SmoothPlastic)
end

----------------------------------------------------------------------
-- Maillage : triangles en 2 coins (WedgePart), quadrilatères
----------------------------------------------------------------------

-- Triangle a, b, c (repère local) : face extérieure SUR le plan du triangle,
-- épaisseur vers l'intérieur (côté de `ref`). 0, 1 ou 2 coins.
local function tri(b: B, name: string, pa: Vector3, pb: Vector3, pc: Vector3, color: Color3, material: Enum.Material, thick: number, ref: Vector3)
	local a, bb, c = PV(b, pa), PV(b, pb), PV(b, pc)
	local ab, ac, bc = bb - a, c - a, c - bb
	local dab, dac, dbc = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if dab > dac and dab > dbc then
		a, c = c, a
	elseif dac > dbc and dac > dab then
		a, bb = bb, a
	end
	ab, ac, bc = bb - a, c - a, c - bb
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-5 or bc.Magnitude < 1e-3 then
		return
	end
	local right = cross.Unit
	local back = bc.Unit
	local up = bc:Cross(right).Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.02 then
		return
	end
	local n = right
	if ((a + bb + c) / 3 - PV(b, ref)):Dot(n) < 0 then
		n = -n
	end
	local shift = -n * thick / 2
	local l1 = math.abs(ab:Dot(back))
	if l1 > 0.025 then
		newPart(b, "WedgePart", name, Vector3.new(thick, height, l1), CFrame.fromMatrix((a + bb) / 2 + shift, right, up, back), color, material)
	end
	local l2 = math.abs(ac:Dot(back))
	if l2 > 0.025 then
		newPart(b, "WedgePart", name, Vector3.new(thick, height, l2), CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back), color, material)
	end
end

-- Rectangle c1 -> c2 (côté u), c1 -> c4 (côté v, perpendiculaire) : 1 bloc
local function rect(b: B, name: string, c1: Vector3, c2: Vector3, c4: Vector3, color: Color3, material: Enum.Material, thick: number, ref: Vector3)
	local su, sv = PV(b, c2 - c1), PV(b, c4 - c1)
	local n = su:Cross(sv).Unit
	local center = PV(b, (c2 + c4) / 2)
	local sign = if (center - PV(b, ref)):Dot(n) < 0 then -1 else 1
	newPart(b, "Part", name, Vector3.new(su.Magnitude, sv.Magnitude, thick), CFrame.fromMatrix(center - n * sign * thick / 2, su.Unit, sv.Unit), color, material)
end

-- Trapèze (p1p2 parallèle à p4p3) : rectangle + coins rectangles (≤ 3 pièces)
local function trapezoid(b: B, name: string, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, color: Color3, material: Enum.Material, thick: number, ref: Vector3): boolean
	local u = p2 - p1
	local len = u.Magnitude
	local w = p3 - p4
	if len < 0.02 or w.Magnitude < 0.02 then
		return false
	end
	local ud = u / len
	if w.Unit:Dot(ud) < 0.99995 then
		return false
	end
	local s4 = (p4 - p1):Dot(ud)
	local s3 = (p3 - p1):Dot(ud)
	local hv = (p4 - p1) - ud * s4
	if hv.Magnitude < 0.02 then
		return false
	end
	local a0, a1 = math.max(0, s4), math.min(len, s3)
	if a1 - a0 < 0.02 then
		return false
	end
	local q1, q2 = p1 + ud * a0, p1 + ud * a1
	rect(b, name, q1, q2, q1 + hv, color, material, thick, ref)
	if s4 > 0.02 then
		tri(b, name, p1, q1, p4, color, material, thick, ref)
	elseif s4 < -0.02 then
		tri(b, name, p1, p4, p1 + hv, color, material, thick, ref)
	end
	if s3 < len - 0.02 then
		tri(b, name, p2, q2, p3, color, material, thick, ref)
	elseif s3 > len + 0.02 then
		tri(b, name, p2, p3, p2 + hv, color, material, thick, ref)
	end
	return true
end

-- Quadrilatère p1 p2 p3 p4 (dans l'ordre) : 1 bloc si c'est un rectangle,
-- rectangle + coins si deux côtés sont parallèles, sinon 2 triangles
-- (coupés par la plus courte diagonale)
local function quad(b: B, name: string, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, color: Color3, material: Enum.Material, thick: number, ref: Vector3)
	local u, v = p2 - p1, p4 - p1
	if u.Magnitude > 0.02 and v.Magnitude > 0.02 and (p3 - (p2 + v)).Magnitude < 0.004 and math.abs(u.Unit:Dot(v.Unit)) < 0.002 then
		rect(b, name, p1, p2, p4, color, material, thick, ref)
		return
	end
	if trapezoid(b, name, p1, p2, p3, p4, color, material, thick, ref) or trapezoid(b, name, p2, p3, p4, p1, color, material, thick, ref) then
		return
	end
	if (p3 - p1).Magnitude <= (p4 - p2).Magnitude then
		tri(b, name, p1, p2, p3, color, material, thick, ref)
		tri(b, name, p1, p3, p4, color, material, thick, ref)
	else
		tri(b, name, p1, p2, p4, color, material, thick, ref)
		tri(b, name, p2, p3, p4, color, material, thick, ref)
	end
end

-- Coin (WedgePart) dans le plan du flanc (x0..x1) : triangle rectangle entre
-- la corde (za, ya) -> (zb, yb) et l'horizontale y = max(ya, yb) (au-dessus)
local function chordWedge(b: B, name: string, x0: number, x1: number, za: number, ya: number, zb: number, yb: number, color: Color3, material: Enum.Material)
	local ymax, ymin = math.max(ya, yb), math.min(ya, yb)
	if ymax - ymin < 0.02 or math.abs(zb - za) < 0.02 then
		return
	end
	local cf = CFrame.new(P(b, (x0 + x1) / 2, (ya + yb) / 2, (za + zb) / 2))
	if yb > ya then
		cf *= CFrame.Angles(PI, 0, 0)
	else
		cf *= CFrame.Angles(0, 0, PI)
	end
	newPart(b, "WedgePart", name, Vector3.new(math.abs(x1 - x0) * b.S.X, (ymax - ymin) * b.S.Y, math.abs(zb - za) * b.S.Z), cf, color, material)
end

----------------------------------------------------------------------
-- Géométrie d'un modèle : profils le long de z
----------------------------------------------------------------------

type Geo = {
	zF: number,
	zB: number,
	r: number,
	ra: number,
	aF0: number,
	aF1: number,
	aR0: number,
	aR1: number,
	noseR: number,
	tailR: number,
	noseLow: number,
	hoodF: number,
	sill: number,
	cowl: number,
	planX: (number) -> number,
	flankTop: (number) -> number,
	topY: (number) -> number,
	topE: (number) -> number,
	p2: (number) -> (number, number),
	ref: (number) -> Vector3,
}

type St = { z: number, t: number, e: number, bx: number, by: number, fx: number, fy: number }

local function lerp(a: number, c: number, u: number): number
	return a + (c - a) * u
end

local function makeGeo(s: Spec): Geo
	local g = {} :: any
	local hw = s.W / 2
	g.zF, g.zB = -s.L / 2, s.L / 2
	g.r = s.WheelD / 2
	g.ra = g.r + 0.2
	g.aF0, g.aF1 = s.AxleF - g.ra, s.AxleF + g.ra
	g.aR0, g.aR1 = s.AxleR - g.ra, s.AxleR + g.ra
	g.noseR = math.max(0.3, math.min(s.NoseR, g.aF0 - g.zF - 0.08))
	g.tailR = math.max(0.3, math.min(s.TailR, g.zB - g.aR1 - 0.08))
	g.noseLow = s.NoseLow or s.Low
	g.hoodF = math.max(s.HoodF, g.noseLow + 0.26)
	g.sill = s.Clear + 0.1
	g.cowl = 0.35
	local sports = s.Style == "Sports"
	local pickup = s.Style == "Pickup"
	local zF, zB = g.zF, g.zB

	-- demi-largeur vue de dessus (coins arrondis en quart de cercle)
	function g.planX(z: number): number
		if z < zF + g.noseR then
			local u = math.clamp((z - zF) / g.noseR, 0, 1)
			return hw - g.noseR * (1 - math.sin(math.acos(1 - u)))
		elseif z > zB - g.tailR then
			local u = math.clamp((zB - z) / g.tailR, 0, 1)
			return hw - g.tailR * (1 - math.sin(math.acos(1 - u)))
		end
		return hw
	end
	-- dessus du flanc vertical (nez plongeant du roadster)
	function g.flankTop(z: number): number
		local n2 = zF + g.noseR
		if z <= n2 then
			return g.noseLow
		elseif z < g.aF0 then
			return lerp(g.noseLow, s.Low, (z - n2) / math.max(0.01, g.aF0 - n2))
		end
		return s.Low
	end
	-- ceinture (bas des vitres) dans l'habitacle
	local function belt(z: number): number
		local u = math.clamp((z - s.Ws) / math.max(0.01, s.Rw - s.Ws), 0, 1)
		return lerp(s.Belt - s.BeltRise / 2, s.Belt + s.BeltRise / 2, u)
	end
	-- dessus (axe) : capot, auvent, pare-brise, toit bombé, lunette, coffre
	function g.topY(z: number): number
		local wsC = s.Ws - g.cowl
		if z <= wsC then
			local u = math.clamp((z - zF) / math.max(0.01, wsC - zF), 0, 1)
			return g.hoodF + (s.HoodR - 0.03 - g.hoodF) * (1 - (1 - u) ^ 2) - 0.12 * (1 - u) ^ 8
		elseif z <= s.Ws then
			return s.HoodR
		elseif z <= s.R0 then
			return lerp(s.HoodR + 0.06, s.Roof - 0.04, (z - s.Ws) / math.max(0.01, s.R0 - s.Ws))
		elseif sports and z < s.Rw then
			return belt(z) -- cockpit ouvert
		elseif pickup and z > s.R1 + 0.01 then
			return s.Deck -- benne ouverte
		elseif z <= s.R1 then
			return s.Roof - 0.04
		elseif z <= s.Rw then
			local u = (z - s.R1) / math.max(0.01, s.Rw - s.R1)
			return lerp(s.Roof - 0.04, s.Deck, u)
		end
		local u = (z - s.Rw) / math.max(0.01, zB - s.Rw)
		return s.Deck - 0.1 * u * u - 0.1 * u ^ 8
	end
	-- demi-largeur du dessus plat (capot, toit, coffre)
	function g.topE(z: number): number
		-- (même largeur du capot au coffre : les bandes du dessus sont des
		-- rectangles, 1 pièce chacune)
		local e = hw - s.Inset
		if sports and z < s.Ws - g.cowl then
			e = hw - 1.0
		elseif sports and z >= s.R0 and z < s.Rw then
			e = hw - s.Tumble
		elseif pickup and z > s.R1 + 0.01 then
			e = g.planX(z) - 0.1
		end
		return math.min(e, g.planX(z) - 0.1 - (if pickup and z > s.R1 + 0.01 then 0 else 0.42))
	end
	-- épaule / ceinture (x, y) : arête de l'aile, bas des vitres
	function g.p2(z: number): (number, number)
		local px = g.planX(z)
		if z < s.Ws then
			if sports then
				return px - 0.2, g.topY(z) + 0.16 -- ailes plus hautes que le capot
			end
			return px, g.topY(z) - 0.2 -- (aile verticale jusqu'à l'arête)
		elseif pickup and z > s.R1 + 0.01 then
			return px - 0.1, s.Deck
		elseif z <= s.Rw then
			return math.min(hw - s.Tumble, px - 0.13), belt(z)
		end
		return px, g.topY(z) - 0.2
	end
	-- point intérieur (orientation des triangles)
	function g.ref(z: number): Vector3
		return Vector3.new(0, s.Clear + 0.3, math.clamp(z, zF + 2, zB - 2))
	end
	return g :: Geo
end

-- Sections le long de la voiture (plus nombreuses en "Full")
local function stations(s: Spec, g: Geo, lod: number): { St }
	local list: { { z: number, pri: number } } = {}
	local function add(z: number, pri: number)
		table.insert(list, { z = z, pri = pri })
	end
	add(g.zF, 3)
	add(g.zF + g.noseR, 2)
	if lod >= 3 then
		add(g.zF + g.noseR * (1 - math.cos(PI / 4)), 1)
	end
	local wsC = s.Ws - g.cowl
	if lod >= 3 then
		if wsC - (g.zF + g.noseR) > 2.2 then
			add((g.zF + g.noseR + wsC) / 2, 1)
		end
		add(wsC, 1)
	end
	add(s.Ws, 3)
	add(s.R0, 3)
	add(s.R1, 3)
	add(s.Rw, 3)
	local t2 = g.zB - g.tailR
	if lod >= 3 and t2 - s.Rw > 2.2 then
		add((s.Rw + t2) / 2, 1)
	end
	add(t2, 2)
	if lod >= 3 then
		add(g.zB - g.tailR * (1 - math.cos(PI / 4)), 1)
	end
	add(g.zB, 3)
	table.sort(list, function(a, c)
		return a.z < c.z
	end)
	-- sections trop proches : on garde la plus importante
	local i = 1
	while i < #list do
		local a, c = list[i], list[i + 1]
		if c.z - a.z < 0.14 then
			if c.pri > a.pri then
				table.remove(list, i)
			else
				table.remove(list, i + 1)
			end
		else
			i += 1
		end
	end
	local out: { St } = {}
	for _, item in ipairs(list) do
		local z = item.z
		local bx, by = g.p2(z)
		table.insert(out, { z = z, t = g.topY(z), e = g.topE(z), bx = bx, by = by, fx = g.planX(z), fy = g.flankTop(z) })
	end
	return out
end

-- Section interpolée en z (montants, joints)
local function sectionAt(st: { St }, z: number): St
	for i = 1, #st - 1 do
		local a, c = st[i], st[i + 1]
		if z >= a.z and z <= c.z then
			local u = (z - a.z) / math.max(1e-4, c.z - a.z)
			return { z = z, t = lerp(a.t, c.t, u), e = lerp(a.e, c.e, u), bx = lerp(a.bx, c.bx, u), by = lerp(a.by, c.by, u), fx = lerp(a.fx, c.fx, u), fy = lerp(a.fy, c.fy, u) }
		end
	end
	return if z < st[1].z then st[1] else st[#st]
end

----------------------------------------------------------------------
-- Roues
----------------------------------------------------------------------

type WheelLook = { Rim: Color3, Dish: Color3, Cap: Color3, Caliper: Color3, Spokes: number }

-- Roue : pneu + flanc, lèvre de jante, voile sombre, disque, étrier, rayons,
-- cache-moyeu. Couches depuis la face extérieure du pneu, espacées de ≥ 0,02.
local function wheel(b: B, s: Spec, index: number, x: number, z: number, look: WheelLook)
	local D = s.WheelD
	local r = D / 2
	local side = if x > 0 then 1 else -1
	local lod = b.Lod
	b.WheelTag = index
	b.Spin = true
	local tw = s.TyreW
	cylX(b, "Tyre", x, r, z, tw, D, TYRE, M.Rubber, true)
	local face = x + side * tw / 2
	local function layer(name: string, out: number, thick: number, diameter: number, color: Color3, material: Enum.Material): BasePart
		return cylX(b, name, face + side * (out - thick / 2), r, z, thick, diameter, color, material)
	end
	if lod <= 1 then
		layer("Rim", 0.05, 0.1, D * 0.62, look.Rim, M.Metal)
		b.WheelTag = nil
		b.Spin = nil
		return
	end
	if lod == 2 then
		layer("Rim", 0.05, 0.1, D * 0.62, look.Rim, M.Metal)
		-- une barre sombre à travers la jante : on voit la roue tourner
		boxRotX(b, "Spoke", face + side * 0.08, r, z, 0.06, D * 0.12, D * 0.5, 0, look.Dish, M.Metal)
		b.WheelTag = nil
		b.Spin = nil
		return
	end
	layer("Sidewall", 0.04, 0.1, D - 0.12, SIDEWALL, M.Rubber)
	layer("RimLip", 0.08, 0.1, D * 0.66, look.Rim, M.Metal).Reflectance = 0.25
	layer("RimDish", 0.12, 0.1, D * 0.58, look.Dish, M.Metal)
	layer("BrakeDisc", 0.16, 0.1, D * 0.44, DISC, M.Metal)
	-- étrier (braque sans tourner)
	b.Spin = false
	local ca = math.rad(40)
	boxRotX(b, "Caliper", face + side * 0.175, r + math.cos(ca) * D * 0.18, z + math.sin(ca) * D * 0.18, 0.05, D * 0.1, D * 0.2, ca, look.Caliper)
	b.Spin = true
	-- rayons (de 0,08 D à 0,31 D : ils ne se touchent que sous le cache-moyeu)
	local n = look.Spokes
	local r0, r1 = D * 0.08, D * 0.31
	local sw = if n >= 10 then D * 0.045 else D * 0.075
	for k = 0, n - 1 do
		local a = k / n * 2 * PI
		local rc = (r0 + r1) / 2
		boxRotX(b, "Spoke", face + side * 0.215, r + math.cos(a) * rc, z + math.sin(a) * rc, 0.05, sw, r1 - r0, a - PI / 2, look.Rim, M.Metal)
	end
	layer("HubCap", 0.28, 0.08, D * 0.18, look.Cap, M.Metal)
	layer("HubLogo", 0.32, 0.06, D * 0.07, CAL_RED, M.SmoothPlastic)
	-- pivots invisibles (CarService : Motor6D ; CarClient : rotation / braquage)
	b.Spin = false
	local steer = box(b, "WheelSteer", x - 0.1, x + 0.1, r - 0.1, r + 0.1, z - 0.1, z + 0.1, WHITE, M.SmoothPlastic)
	steer.Transparency = 1
	b.Spin = true
	local spin = box(b, "WheelSpin", x - 0.1, x + 0.1, r - 0.1, r + 0.1, z - 0.1, z + 0.1, WHITE, M.SmoothPlastic)
	spin.Transparency = 1
	b.WheelTag = nil
	b.Spin = nil
end

----------------------------------------------------------------------
-- Plaque d'immatriculation
----------------------------------------------------------------------

local function plate(b: B, name: string, z: number, y: number, facing: number, band: boolean, text: string?)
	local p = box(b, name, -0.85, 0.85, y - 0.22, y + 0.22, z - 0.03, z + 0.03, PLATE, M.SmoothPlastic)
	if band then
		-- (bande bleue 0,03 en avant de la plaque : jamais coplanaire)
		box(b, name .. "Band", -0.85, -0.63, y - 0.22, y + 0.22, z + 0.045 * facing - 0.015, z + 0.045 * facing + 0.015, PLATE_BAND, M.SmoothPlastic)
	end
	if text and text ~= "" then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlateText"
		gui.Face = if facing > 0 then Enum.NormalId.Back else Enum.NormalId.Front
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

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function lodOf(detail: any): number
	if detail == "Mid" then
		return 2
	elseif detail == "Low" or detail == "Parked" then
		return 1
	end
	return 3
end

-- Version "Low" (loin / serveur) : volumes simples, ~30-45 pièces
local function buildLow(b: B, s: Spec, g: Geo, paint: Color3, roofColor: Color3, look: WheelLook)
	local hw = s.W / 2
	local style = s.Style
	local archTop = g.r + g.ra
	local low = s.Low
	-- bas de caisse découpé autour des roues (+ coins d'arche abattus)
	box(b, "Body", -hw + 0.15, hw - 0.15, g.sill, g.noseLow, g.zF, g.zF + 0.4, paint)
	box(b, "Body", -hw, hw, g.sill, low, g.zF + 0.4, g.aF0, paint, M.SmoothPlastic, true)
	box(b, "Body", -hw, hw, g.sill, low, g.aF1, g.aR0, paint, M.SmoothPlastic, true)
	box(b, "Body", -hw, hw, g.sill, low, g.aR1, g.zB - 0.4, paint, M.SmoothPlastic, true)
	box(b, "Body", -hw + 0.15, hw - 0.15, g.sill, low, g.zB - 0.4, g.zB, paint)
	for _, a in ipairs({ { g.aF0, g.aF1 }, { g.aR0, g.aR1 } }) do
		box(b, "Body", -hw, hw, archTop, low, a[1], a[2], paint)
		local c = math.min(0.5, low - archTop + 0.4)
		wedge(b, "Body", -hw, hw, archTop - c + 0.25, archTop, a[1], a[1] + c, false, paint)
		wedge(b, "Body", -hw, hw, archTop - c + 0.25, archTop, a[2] - c, a[2], true, paint)
		box(b, "WheelWell", -hw + s.TyreW + 0.25, hw - s.TyreW - 0.25, g.sill + 0.1, archTop, a[1], a[2], LINER)
	end
	-- capot, habitacle, coffre / benne
	local hoodTop = s.HoodR
	wedge(b, "Hood", -hw + 0.1, hw - 0.1, low, hoodTop, g.zF + 0.15, s.Ws, true, paint)
	box(b, "Upper", -hw, hw, low, s.Belt, s.Ws, if style == "Pickup" then s.R1 else s.Rw, paint)
	if style == "Pickup" then
		box(b, "Bed", -hw, hw, low, s.Deck, s.R1, g.zB - 0.1, paint)
		box(b, "BedFloor", -hw + 0.3, hw - 0.3, s.Deck - 0.05, s.Deck + 0.05, s.R1 + 0.3, g.zB - 0.4, TRIM)
	elseif g.zB - 0.1 - s.Rw > 0.1 then
		box(b, "Deck", -hw, hw, low, s.Deck, s.Rw, g.zB - 0.1, paint)
	end
	-- vitres + toit
	local gw = hw - s.Inset
	if style == "Sports" then
		wedge(b, "Windshield", -gw, gw, s.Belt, s.Roof, s.Ws + 0.05, s.R0, true, GLASS, M.Glass)
		box(b, "Cockpit", -hw + 0.4, hw - 0.4, low, s.Belt - 0.02, s.R0, s.R1, TRIM)
	else
		wedge(b, "Windshield", -gw, gw, s.Belt, s.Roof - 0.12, s.Ws + 0.05, s.R0, true, GLASS, M.Glass)
		box(b, "SideGlass", -gw, gw, s.Belt, s.Roof - 0.12, s.R0, s.R1, GLASS, M.Glass)
		box(b, "Roof", -gw + 0.05, gw - 0.05, s.Roof - 0.12, s.Roof, s.R0 - 0.05, s.R1 + 0.05, roofColor)
		if s.Rw - s.R1 > 0.1 then
			wedge(b, "RearGlass", -gw, gw, s.Belt, s.Roof - 0.12, s.R1, s.Rw, false, GLASS, M.Glass)
		else
			box(b, "RearWall", -gw, gw, s.Belt, s.Roof - 0.12, s.R1 - 0.02, s.R1 + 0.1, paint)
		end
	end
	-- phares, feux, calandre, plaque, rétroviseurs
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * hw * 0.42, sx * (hw - 0.35)
		box(b, "Headlight", math.min(x0, x1), math.max(x0, x1), g.noseLow - 0.45, g.noseLow - 0.05, g.zF - 0.04, g.zF + 0.2, LAMP, M.Glass)
		box(b, "Taillight", math.min(x0, x1), math.max(x0, x1), low - 0.45, low - 0.08, g.zB - 0.2, g.zB + 0.04, TAIL, M.Glass)
		ell(b, "Mirror", sx * (hw + 0.2), s.Belt + 0.25, s.Ws + 0.45, 0.55, 0.4, 0.42, paint)
	end
	box(b, "Grille", -hw * 0.36, hw * 0.36, g.sill + 0.25, g.noseLow - 0.15, g.zF - 0.03, g.zF + 0.2, TRIM)
	box(b, "PlateRear", -0.8, 0.8, g.sill + 0.25, g.sill + 0.65, g.zB - 0.1, g.zB + 0.04, PLATE)
end

function CarModels.Build(carId: string?, color: any?, opts: any?): Model
	local options = type(opts) == "table" and opts or {}
	local kind = kindOf(carId)
	local s = SPECS[kind]
	local paint = CarModels.ColorOf(type(carId) == "string" and carId or kind, color)
	local lod = lodOf(options.Detail)
	local full = lod >= 3
	local scale = Vector3.new(1, 1, 1)
	if typeof(options.Scale) == "Vector3" then
		scale = options.Scale
	elseif type(options.Scale) == "number" and options.Scale > 0 then
		scale = Vector3.new(options.Scale, options.Scale, options.Scale)
	end
	local model = Instance.new("Model")
	model.Name = "Car_" .. kind
	local b: B = { Model = model, S = scale, Count = 0, Paint = paint, Gloss = if full then 0.1 elseif lod == 2 then 0.06 else 0.03, Lod = lod }
	local g = makeGeo(s)
	local style = s.Style
	local hw = s.W / 2
	local zF, zB = g.zF, g.zB
	local sports = style == "Sports"
	local pickup = style == "Pickup"
	local offroad = style == "SUV" or style == "Pickup"
	local twoBox = style == "City" or style == "Hatch" or style == "SUV" or style == "Bubble" or style == "Van"
	local r, ra = g.r, g.ra

	-- teinte de contraste (bandes, toit bicolore)
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
		roofColor = WHITE:Lerp(paint, 0.06)
	end
	-- jantes par modèle
	local look: WheelLook = { Rim = CHROME, Dish = GRAPHITE, Cap = CHROME, Caliper = CAL_DARK, Spokes = 5 }
	if style == "Bubble" then
		look = { Rim = WHITE, Dish = Color3.fromRGB(200, 202, 210), Cap = CHROME, Caliper = CAL_DARK, Spokes = 8 }
	elseif sports then
		look = { Rim = GRAPHITE, Dish = HOUSING, Cap = CHROME, Caliper = CAL_RED, Spokes = 10 }
	elseif style == "Limo" then
		look = { Rim = CHROME, Dish = GRAPHITE, Cap = GRAPHITE, Caliper = CAL_DARK, Spokes = 10 }
	elseif offroad then
		look = { Rim = Color3.fromRGB(190, 194, 202), Dish = GRAPHITE, Cap = GRAPHITE, Caliper = CAL_DARK, Spokes = 6 }
	elseif style == "Van" then
		look = { Rim = WHITE, Dish = Color3.fromRGB(190, 192, 200), Cap = CHROME, Caliper = CAL_DARK, Spokes = 5 }
	elseif style == "Hatch" then
		look = { Rim = CHROME, Dish = HOUSING, Cap = GRAPHITE, Caliper = CAL_RED, Spokes = 5 }
	end

	-- boîte de collision (surélevée : les bordures passent dessous)
	local rootBottom = math.max(s.Clear, 0.95)
	local rootTop = math.max(s.Belt, rootBottom + 1.2)
	local root = box(b, "Root", -hw + 0.1, hw - 0.1, rootBottom, rootTop, zF + 0.2, zB - 0.2, WHITE, M.SmoothPlastic)
	root:SetAttribute("Paint", nil)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	model.PrimaryPart = root
	root.PivotOffset = CFrame.new(0, -((rootBottom + rootTop) / 2) * scale.Y, 0)

	-- siège du conducteur
	local seatTop = math.min(s.Roof - 3.65, s.Clear + 1.85)
	local seatZ = s.R0 + (s.R1 - s.R0) * 0.42
	if style == "Van" then
		seatTop = 2.35
		seatZ = s.R0 + 1.35
	elseif pickup then
		seatZ = s.R0 + 1.35
	elseif sports then
		seatTop = s.Clear + 0.6
		seatZ = s.R1 - 0.95
	elseif style == "Limo" then
		seatZ = s.R0 + 1.45
	elseif style == "Bubble" then
		seatZ = s.R0 + 1.35
	end
	local seatX = -s.W * 0.2

	if lod <= 1 then
		buildLow(b, s, g, paint, roofColor, look)
	else
		local st = stations(s, g, lod)
		local thick = 0.14
		local gThick = 0.06
		----------------------------------------------------------------
		-- ░ coque : dessus, arête (vitres), épaule, coins ░
		----------------------------------------------------------------
		local wsC = s.Ws - g.cowl
		for i = 1, #st - 1 do
			local A, C = st[i], st[i + 1]
			local zm = (A.z + C.z) / 2
			local ref = g.ref(zm)
			local topCol, topMat = paint, M.SmoothPlastic
			local b1Col, b1Mat = paint, M.SmoothPlastic
			local skipTop, skipB1 = false, false
			local region
			if zm < wsC then
				region = "hood"
			elseif zm < s.Ws then
				region = "cowl"
				topCol = TRIM
			elseif zm < s.R0 then
				region = "wind"
				topCol, topMat = GLASS, M.Glass
				b1Col, b1Mat = GLASS, M.Glass
				if sports then
					skipB1 = true
				end
			elseif sports and zm < s.Rw then
				region = "cockpit"
				skipTop, skipB1 = true, true
			elseif pickup and zm > s.R1 then
				region = "bed"
				skipTop, skipB1 = true, true
			elseif zm < s.R1 then
				region = "roof"
				topCol = roofColor
				b1Col, b1Mat = GLASS, M.Glass
			elseif zm < s.Rw then
				region = "rear"
				topCol, topMat = GLASS, M.Glass
				if twoBox then
					b1Col, b1Mat = GLASS, M.Glass
				end
			else
				region = "deck"
			end
			local merged = lod == 2 and (region == "hood" or region == "deck" or region == "cowl")
			local th = if topMat == M.Glass then gThick else thick
			-- dessus (trapèze : 1 bloc + 2 coins)
			if not skipTop then
				local e1, e2 = A.e, C.e
				local m = math.min(e1, e2)
				quad(b, "Top", V3(-m, A.t, A.z), V3(m, A.t, A.z), V3(m, C.t, C.z), V3(-m, C.t, C.z), topCol, topMat, th, ref)
				if math.abs(e1 - e2) > 0.02 then
					for _, sx in ipairs({ -1, 1 }) do
						if e1 > e2 then
							tri(b, "Top", V3(sx * m, A.t, A.z), V3(sx * e1, A.t, A.z), V3(sx * m, C.t, C.z), topCol, topMat, th, ref)
						else
							tri(b, "Top", V3(sx * m, A.t, A.z), V3(sx * m, C.t, C.z), V3(sx * e2, C.t, C.z), topCol, topMat, th, ref)
						end
					end
				end
			end
			for _, sx in ipairs({ -1, 1 }) do
				local a1, a2, a3 = V3(sx * A.e, A.t, A.z), V3(sx * A.bx, A.by, A.z), V3(sx * A.fx, A.fy, A.z)
				local c1, c2, c3 = V3(sx * C.e, C.t, C.z), V3(sx * C.bx, C.by, C.z), V3(sx * C.fx, C.fy, C.z)
				if merged then
					quad(b, "Body", a1, a3, c3, c1, paint, M.SmoothPlastic, thick, ref)
				else
					if not skipB1 then
						quad(b, if b1Mat == M.Glass then "Window" else "Pillar", a1, a2, c2, c1, b1Col, b1Mat, if b1Mat == M.Glass then gThick else thick, ref)
					end
					quad(b, "Shoulder", a2, a3, c3, c2, paint, M.SmoothPlastic, thick, ref)
				end
				-- coins arrondis (flanc vertical sous l'épaule)
				if C.z <= zF + g.noseR + 1e-3 or A.z >= zB - g.tailR - 1e-3 then
					quad(b, "Corner", a3, V3(sx * A.fx, g.sill, A.z), V3(sx * C.fx, g.sill, C.z), c3, paint, M.SmoothPlastic, thick, ref)
				end
			end
		end

		----------------------------------------------------------------
		-- ░ flancs verticaux découpés autour des roues ░
		----------------------------------------------------------------
		local fth = 0.16
		local archN = if full then 4 else 2
		for _, sx in ipairs({ -1, 1 }) do
			local x0, x1 = sx * hw, sx * (hw - fth)
			local lo, hi = math.min(x0, x1), math.max(x0, x1)
			local function piece(z0: number, z1: number)
				if z1 - z0 < 0.02 then
					return
				end
				local t0, t1 = g.flankTop(z0), g.flankTop(z1)
				local tl = math.min(t0, t1)
				box(b, "Flank", lo, hi, g.sill, tl, z0, z1, paint, M.SmoothPlastic, true)
				if math.abs(t0 - t1) > 0.02 then
					wedge(b, "Flank", lo, hi, tl, math.max(t0, t1), z0, z1, t1 > t0, paint)
				end
			end
			local function arch(axle: number)
				for k = 0, archN - 1 do
					local a0 = -PI / 2 + k * PI / archN
					local a1 = a0 + PI / archN
					local za, ya = axle + ra * math.sin(a0), r + ra * math.cos(a0)
					local zb, yb = axle + ra * math.sin(a1), r + ra * math.cos(a1)
					local ymax = math.max(ya, yb)
					if s.Low - ymax > 0.02 then
						box(b, "ArchPanel", lo, hi, ymax, s.Low, za, zb, paint)
					end
					chordWedge(b, "ArchPanel", lo, hi, za, ya, zb, yb, paint, M.SmoothPlastic)
				end
				-- lèvre d'aile (ou protection noire des tout-terrain)
				if full then
					local lipT = if offroad then 0.32 else 0.12
					local lipOut = if offroad then 0.1 else 0.045
					local lipCol = if offroad then TRIM else paint
					local lipMat = if offroad then M.Plastic else M.SmoothPlastic
					local rr = ra + lipT / 2
					local n = 4
					for k = 0, n - 1 do
						local a = -PI / 2 + (k + 0.5) * PI / n
						local ex0, ex1 = sx * (hw - 0.1), sx * (hw + lipOut)
						boxRotX(b, "ArchLip", (ex0 + ex1) / 2, r + math.cos(a) * rr, axle + math.sin(a) * rr, math.abs(ex1 - ex0), lipT, 2 * rr * math.tan(PI / (2 * n)) + 0.02, a, lipCol, lipMat)
					end
				end
			end
			piece(zF + g.noseR, g.aF0)
			arch(s.AxleF)
			piece(g.aF1, g.aR0)
			arch(s.AxleR)
			piece(g.aR1, zB - g.tailR)
			-- bas de caisse (noir) entre les roues
			if full then
				local r0x, r1x = sx * (hw - 0.1), sx * (hw + (if offroad then 0.1 else 0.035))
				box(b, "Rocker", math.min(r0x, r1x), math.max(r0x, r1x), g.sill - 0.04, g.sill + (if offroad then 0.45 else 0.3), g.aF1 + 0.05, g.aR0 - 0.05, TRIM, M.Plastic)
			end
		end
		-- passages de roue sombres (on ne voit pas dans la caisse)
		for _, pos in ipairs(CarModels.WheelPositions(kind)) do
			local sx = if pos.X > 0 then 1 else -1
			cylX(b, "WheelWell", sx * (math.abs(pos.X) - s.TyreW / 2 - 0.13), r, pos.Z, 0.08, ra * 2 + 0.1, LINER)
			if full then
				-- toit du passage de roue (vu dans le jour au-dessus du pneu)
				local inner, outer = math.max(math.abs(pos.X) - s.TyreW / 2 - 0.1, g.topE(pos.Z) + 0.12), hw - fth - 0.08
				if outer - inner > 0.1 then
					box(b, "WheelWell", sx * inner, sx * outer, r + ra + 0.05, r + ra + 0.13, pos.Z - ra * 0.75, pos.Z + ra * 0.75, LINER)
				end
			end
		end
		-- plancher (sous la voiture, entre les roues)
		box(b, "Floor", -hw + s.TyreW + 0.5, hw - s.TyreW - 0.5, s.Clear + 0.05, g.sill + 0.02, zF + 0.7, zB - 0.7, LINER)

		----------------------------------------------------------------
		-- ░ faces avant / arrière (bouclier) ░
		----------------------------------------------------------------
		local function endFace(S: St, zf: number, dir: number)
			-- dir = -1 : avant (face vers -Z) ; +1 : arrière
			local zin = zf - dir * 0.24
			local ref = V3(0, (S.fy + S.t) / 2, zf - dir * 1.5)
			box(b, "Fascia", -S.fx, S.fx, g.sill, S.fy, math.min(zf, zin), math.max(zf, zin), paint, M.SmoothPlastic, true)
			if lod < 3 and not pickup then
				-- (Mid : 2 blocs, sous la coque)
				local yb = math.min(S.by, S.t)
				if yb - S.fy > 0.03 then
					box(b, "Fascia", -S.bx, S.bx, S.fy, yb, math.min(zf, zin), math.max(zf, zin), paint)
				end
				if S.t - yb > 0.03 then
					box(b, "Fascia", -S.e, S.e, yb, S.t, math.min(zf, zin), math.max(zf, zin), paint)
				end
				return
			end
			if S.t - S.fy > 0.03 and not (pickup and dir > 0) then
				quad(b, "Fascia", V3(-S.e, S.fy, zf), V3(S.e, S.fy, zf), V3(S.e, S.t, zf), V3(-S.e, S.t, zf), paint, M.SmoothPlastic, 0.2, ref)
			end
			for _, sx in ipairs({ -1, 1 }) do
				if pickup and dir > 0 then
					quad(b, "Fascia", V3(sx * S.fx, S.fy, zf), V3(sx * S.bx, S.by, zf), V3(sx * 0.001, S.by, zf), V3(sx * 0.001, S.fy, zf), paint, M.SmoothPlastic, 0.2, ref)
				else
					quad(b, "Fascia", V3(sx * S.e, S.fy, zf), V3(sx * S.fx, S.fy, zf), V3(sx * S.bx, S.by, zf), V3(sx * S.e, S.t, zf), paint, M.SmoothPlastic, 0.2, ref)
				end
			end
		end
		endFace(st[1], zF, -1)
		endFace(st[#st], zB, 1)
		-- lèvres de pare-chocs (noires, sous les boucliers)
		local nfx, tfx = st[1].fx, st[#st].fx
		box(b, "BumperLip", -nfx + 0.1, nfx - 0.1, s.Clear, g.sill + 0.06, zF + 0.06, zF + 0.6, TRIM, M.Plastic)
		box(b, "BumperLip", -tfx + 0.1, tfx - 0.1, s.Clear, g.sill + 0.06, zB - 0.6, zB - 0.06, TRIM, M.Plastic)

		----------------------------------------------------------------
		-- ░ avant : optiques, calandre, prise d'air, antibrouillards ░
		----------------------------------------------------------------
		local fy = g.noseLow
		local N0 = st[1]
		local round = style == "Bubble" or style == "Van"
		if round then
			-- phares ronds rétro (cerclage chromé)
			local d = if style == "Van" then 0.95 else 1.05
			local ly = fy - 0.2
			for _, sx in ipairs({ -1, 1 }) do
				local x = sx * (nfx - 0.72)
				cylZ(b, "HeadlightRim", x, ly, zF - 0.05, 0.14, d, CHROME, M.Metal)
				cylZ(b, "Headlight", x, ly, zF - 0.1, 0.1, d - 0.2, LAMP, M.Glass)
				if full then
					cylZ(b, "HeadlightDot", x, ly, zF - 0.17, 0.06, d * 0.3, DRL, M.SmoothPlastic)
					cylZ(b, "Indicator", sx * (nfx - 0.2), ly - 0.55, zF - 0.04, 0.1, 0.3, AMBER, M.SmoothPlastic):SetAttribute("Side", sx)
				end
			end
		else
			local ly0 = fy - (if sports then 0.36 else 0.55)
			local ly1 = fy + math.max(0.06, math.min(0.22, (N0.by - fy) * 0.55))
			for _, sx in ipairs({ -1, 1 }) do
				local hx0, hx1 = sx * (s.W * 0.19), sx * (nfx - 0.08)
				local lo, hi = math.min(hx0, hx1), math.max(hx0, hx1)
				box(b, "HeadlightHousing", lo, hi, ly0, ly1, zF - 0.04, zF + 0.1, HOUSING)
				if full then
					box(b, "Reflector", lo + 0.06, hi - 0.06, ly0 + 0.06, ly1 - 0.05, zF - 0.07, zF - 0.02, CHROME, M.Metal)
					local pd = math.min(0.34, ly1 - ly0 - 0.14)
					local py = (ly0 + ly1) / 2 + 0.03
					for _, f in ipairs({ 0.32, 0.68 }) do
						cylZ(b, "Projector", lerp(hx0, hx1, f), py, zF - 0.1, 0.06, pd, LAMP, M.Glass)
					end
					box(b, "HeadlightDRL", lo + 0.05, hi - 0.05, ly0 + 0.07, ly0 + 0.14, zF - 0.12, zF - 0.06, DRL)
					local lens = box(b, "HeadlightLens", lo - 0.02, hi + 0.02, ly0 - 0.02, ly1 + 0.01, zF - 0.16, zF - 0.13, LENS, M.Glass)
					lens.Transparency = 0.65
					lens.Reflectance = 0.25
					-- répétiteur orange sur l'angle
					local ind = box(b, "Indicator", if sx > 0 then hi - 0.3 else lo, if sx > 0 then hi else lo + 0.3, ly0 - 0.14, ly0 - 0.02, zF - 0.08, zF + 0.05, AMBER)
					ind:SetAttribute("Side", sx)
				else
					box(b, "Headlight", lo + 0.05, hi - 0.05, ly0 + 0.05, ly1 - 0.03, zF - 0.08, zF - 0.02, LAMP, M.Glass)
				end
			end
		end
		-- calandre (par modèle) : cadre + grille + barres + logo
		local gw = if offroad or style == "Limo" then s.W * 0.2 else s.W * 0.17
		local gy0, gy1 = fy - 0.5, fy - 0.04
		if style == "Limo" then
			gy0, gy1 = fy - 0.62, fy + 0.1
		elseif pickup then
			gy0, gy1 = fy - 0.7, fy + 0.12
		elseif style == "Bubble" then
			gw, gy0, gy1 = s.W * 0.1, fy - 0.45, fy - 0.2
		elseif sports then
			gw = 0
		elseif style == "Van" then
			gw, gy0, gy1 = s.W * 0.12, fy - 0.9, fy - 0.72
		end
		if gw > 0 then
			local frameCol = if offroad or style == "Limo" then CHROME else TRIM
			box(b, "GrilleFrame", -gw, gw, gy0, gy1, zF - 0.03, zF + 0.1, frameCol, M.Metal)
			box(b, "Grille", -gw + 0.08, gw - 0.08, gy0 + 0.07, gy1 - 0.07, zF - 0.08, zF + 0.05, HOUSING, M.DiamondPlate)
			if full then
				if style == "Limo" then
					for k = -3, 3 do
						local x = k * gw / 4
						box(b, "GrilleBar", x - 0.035, x + 0.035, gy0 + 0.07, gy1 - 0.07, zF - 0.12, zF - 0.02, CHROME, M.Metal)
					end
				else
					for k = -1, 1, 2 do
						local y = (gy0 + gy1) / 2 + k * (gy1 - gy0) * 0.2
						box(b, "GrilleBar", -gw + 0.1, gw - 0.1, y - 0.035, y + 0.035, zF - 0.12, zF - 0.02, if offroad then CHROME else GRAPHITE, M.Metal)
					end
				end
				cylZ(b, "Badge", 0, (gy0 + gy1) / 2, zF - 0.14, 0.05, 0.3, CHROME, M.Metal)
			end
		elseif full then
			cylZ(b, "Badge", 0, fy - 0.05, zF - 0.03, 0.05, 0.28, CHROME, M.Metal)
		end
		-- prise d'air basse + antibrouillards
		local iw = math.min(if sports then s.W * 0.36 else s.W * 0.28, nfx - 0.3)
		local iy1 = g.sill + (if sports then 0.75 else 0.55)
		box(b, "Intake", -iw, iw, g.sill + 0.18, iy1, zF - 0.05, zF + 0.1, TRIM, M.Plastic)
		if full then
			box(b, "IntakeBar", -iw + 0.08, iw - 0.08, (g.sill + 0.18 + iy1) / 2 - 0.03, (g.sill + 0.18 + iy1) / 2 + 0.03, zF - 0.09, zF + 0.02, GRAPHITE, M.Metal)
			if not round then
				for _, sx in ipairs({ -1, 1 }) do
					cylZ(b, "FogLight", sx * math.min(iw + 0.35, nfx - 0.25), g.sill + (if iw + 0.35 > nfx - 0.25 then 0.8 else 0.36), zF - 0.03, 0.08, 0.3, LAMP, M.Glass)
				end
			end
			plate(b, "PlateFront", zF - 0.12, g.sill + 0.42, -1, true, nil)
		end

		----------------------------------------------------------------
		-- ░ arrière : feux, bandeau, pare-chocs, diffuseur, échappement ░
		----------------------------------------------------------------
		local T0 = st[#st]
		local tfy = T0.fy
		local tailTop = math.min(tfy + math.max(0.05, (T0.by - tfy) * 0.6), T0.t - 0.05)
		local tailBot = tfy - 0.58
		if pickup then
			tailBot, tailTop = s.Low - 0.3, s.Deck - 0.35
		elseif style == "Van" then
			tailBot, tailTop = tfy - 0.2, tfy + 0.5
		end
		for _, sx in ipairs({ -1, 1 }) do
			local tx0, tx1 = sx * (if pickup then tfx - 0.55 else s.W * 0.2), sx * (tfx - 0.06)
			local lo, hi = math.min(tx0, tx1), math.max(tx0, tx1)
			box(b, "Taillight", lo, hi, tailBot, tailTop, zB - 0.1, zB + 0.05, TAIL, M.Glass)
			if full then
				box(b, "TailBar", lo + 0.06, hi - 0.06, tailTop - 0.16, tailTop - 0.08, zB + 0.03, zB + 0.08, TAIL_IN, M.SmoothPlastic)
				local rv0, rv1 = if sx > 0 then lo + 0.06 else hi - 0.36, if sx > 0 then lo + 0.36 else hi - 0.06
				box(b, "ReverseLight", rv0, rv1, tailBot + 0.06, tailBot + 0.2, zB + 0.03, zB + 0.08, REVERSE, M.Glass)
				local ind = box(b, "RearIndicator", if sx > 0 then hi - 0.34 else lo + 0.06, if sx > 0 then hi - 0.06 else lo + 0.34, tailBot + 0.06, tailBot + 0.2, zB + 0.03, zB + 0.08, AMBER)
				ind:SetAttribute("Side", sx)
			end
		end
		if full and (style == "City" or style == "Hatch" or style == "SUV" or style == "Limo") then
			local bw = s.W * 0.2 - 0.03
			box(b, "TailLightBar", -bw, bw, tailTop - 0.14, tailTop - 0.08, zB - 0.02, zB + 0.09, TAIL_IN, M.Glass)
			box(b, "TailBlack", -bw, bw, tailTop - 0.2, tailTop, zB - 0.05, zB + 0.045, HOUSING)
		end
		box(b, "Diffuser", -tfx + 0.25, tfx - 0.25, g.sill + 0.06, g.sill + 0.42, zB - 0.02, zB + 0.1, TRIM, M.Plastic)
		plate(b, "PlateRear", zB + 0.13, g.sill + 0.78, 1, full, options.Plate)
		cylZ(b, "Exhaust", s.W * 0.3, g.sill + 0.2, zB + 0.1, 0.36, 0.3, CHROME, M.Metal)
		if sports then
			cylZ(b, "Exhaust", -s.W * 0.3, g.sill + 0.2, zB + 0.1, 0.36, 0.3, CHROME, M.Metal)
		end
		if full then
			cylZ(b, "BadgeRear", 0, math.min(tailTop + 0.1, T0.t - 0.12), zB + 0.03, 0.05, 0.26, CHROME, M.Metal)
		end

		----------------------------------------------------------------
		-- ░ vitrage : montants, gouttières, joncs, essuie-glaces ░
		----------------------------------------------------------------
		if not sports then
			local Aw, Ar = sectionAt(st, s.Ws), sectionAt(st, s.R0)
			local Rr = sectionAt(st, s.R1)
			for _, sx in ipairs({ -1, 1 }) do
				-- montant A (arête pare-brise / vitre latérale)
				rod(b, "PillarA", V3(sx * Aw.e, Aw.t, Aw.z), V3(sx * Ar.e, Ar.t, Ar.z), if full then 0.2 else 0.16, HOUSING)
				-- montant B (et C1 pour la limousine), noirs
				local pillars: { number } = {}
				if s.Doors == 4 or style == "Limo" then
					table.insert(pillars, s.R0 + (s.R1 - s.R0) * (if style == "Limo" then 0.36 else 0.48))
					if style == "Limo" then
						table.insert(pillars, s.R0 + (s.R1 - s.R0) * 0.7)
					end
				elseif style == "Van" then
					table.insert(pillars, s.R0 + 2.4)
					table.insert(pillars, s.R0 + 6.2)
				elseif not pickup then
					table.insert(pillars, s.R0 + (s.R1 - s.R0) * 0.68)
				end
				for _, pz in ipairs(pillars) do
					local S = sectionAt(st, pz)
					local a, c = V3(sx * S.bx, S.by, pz), V3(sx * S.e, S.t, pz)
					-- (combi : larges montants blancs, bicolore)
					local van = style == "Van"
					strip(b, "PillarB", a, c, V3(sx, 0.3, 0), if van then 0.6 else 0.32, 0.08, if van then roofColor else HOUSING, nil, 0.05)
				end
				-- montant C (vitre de custode des SUV / combis)
				if twoBox and s.Rw - s.R1 > 0.2 then
					strip(b, "PillarC", V3(sx * Rr.bx, Rr.by, s.R1 + 0.05), V3(sx * Rr.e, Rr.t, s.R1 + 0.05), V3(sx, 0.3, 0), 0.4, 0.08, HOUSING, nil, 0.05)
				end
				if style == "Van" then
					-- montant de custode blanc à l'arrière du combi
					local Sd = sectionAt(st, s.R1 - 0.45)
					strip(b, "PillarD", V3(sx * Sd.bx, Sd.by, Sd.z), V3(sx * Sd.e, Sd.t, Sd.z), V3(sx, 0.3, 0), 0.8, 0.08, roofColor, nil, 0.05)
				end
				if full then
					-- gouttière (arête du toit) + jonc de ceinture
					rod(b, "DripRail", V3(sx * Ar.e, Ar.t, s.R0), V3(sx * Rr.e, Rr.t, s.R1), 0.1, HOUSING)
					local endZ = if pickup then s.R1 - 0.05 else s.Rw - 0.05
					local Be = sectionAt(st, endZ)
					rod(b, "BeltTrim", V3(sx * Aw.bx, Aw.by, s.Ws + 0.05), V3(sx * Be.bx, Be.by, endZ), 0.09, if style == "Limo" then CHROME else HOUSING, if style == "Limo" then M.Metal else M.SmoothPlastic)
				end
			end
			if full then
				-- essuie-glaces posés sur le pare-brise
				local dy, dz = Ar.t - Aw.t, s.R0 - s.Ws
				local nrm = V3(0, dz, -dy).Unit * 0.05
				local function onGlass(x: number, y: number): Vector3
					return V3(x, y, s.Ws + (y - Aw.t) / dy * dz) + nrm
				end
				local ww = Aw.e * 2
				for _, x in ipairs({ -ww * 0.42, ww * 0.02 }) do
					rod(b, "Wiper", onGlass(x, Aw.t + 0.12), onGlass(x + ww * 0.36, Aw.t + 0.3), 0.06, GAP)
				end
				-- antenne requin
				if not pickup and style ~= "Van" then
					local Sa = sectionAt(st, s.R1 - 0.6)
					wedge(b, "Antenna", -0.1, 0.1, Sa.t - 0.02, Sa.t + 0.2, s.R1 - 1.0, s.R1 - 0.45, true, if roofColor == paint then paint else HOUSING)
				end
				-- 3e feu stop (haut du hayon)
				if twoBox then
					box(b, "BrakeLight3", -0.5, 0.5, Rr.t - 0.12, Rr.t - 0.04, s.R1 + 0.04, s.R1 + 0.14, TAIL, M.Glass)
				end
			end
		else
			-- roadster : cadre du pare-brise, arceaux, bossages, cockpit
			local Aw, Ar = sectionAt(st, s.Ws), sectionAt(st, s.R0)
			for _, sx in ipairs({ -1, 1 }) do
				rod(b, "WindshieldFrame", V3(sx * Aw.e, Aw.t, Aw.z), V3(sx * Ar.e, Ar.t, Ar.z), 0.16, HOUSING)
			end
			rod(b, "WindshieldTop", V3(-Ar.e, Ar.t, Ar.z), V3(Ar.e, Ar.t, Ar.z), 0.16, HOUSING)
			local cx = hw - s.Tumble - 0.02
			box(b, "CockpitTub", -cx, cx, s.Clear + 0.2, s.Belt - 0.1, s.R0 - 0.1, s.Rw, TRIM, M.Fabric)
			box(b, "Bulkhead", -cx, cx, s.Belt - 0.1, s.Deck + 0.02, s.R1, s.Rw + 0.05, paint)
			for _, sx in ipairs({ -1, 1 }) do
				ell(b, "Fairing", sx * s.W * 0.2, s.Deck, s.Rw + 0.9, 1.1, 0.9, 2.4, paint)
				if full then
					-- arceau de sécurité derrière chaque siège
					local hx = sx * s.W * 0.2
					rod(b, "RollHoop", V3(hx - 0.45, s.Deck, s.Rw + 0.1), V3(hx - 0.35, s.Deck + 0.95, s.Rw + 0.1), 0.14, CHROME, M.Metal)
					rod(b, "RollHoop", V3(hx + 0.45, s.Deck, s.Rw + 0.1), V3(hx + 0.35, s.Deck + 0.95, s.Rw + 0.1), 0.14, CHROME, M.Metal)
					rod(b, "RollHoop", V3(hx - 0.35, s.Deck + 0.95, s.Rw + 0.1), V3(hx + 0.35, s.Deck + 0.95, s.Rw + 0.1), 0.14, CHROME, M.Metal)
				end
			end
			if full then
				-- becquet arrière (queue de canard) + prises d'air latérales
				wedge(b, "Ducktail", -hw + 0.8, hw - 0.8, s.Deck - 0.12, s.Deck + 0.08, zB - 1.3, zB - 0.4, true, paint)
				for _, sx in ipairs({ -1, 1 }) do
					local ix0, ix1 = sx * (hw - 0.08), sx * (hw + 0.05)
					box(b, "SideIntake", math.min(ix0, ix1), math.max(ix0, ix1), g.sill + 0.6, s.Low - 0.35, s.R1, g.aR0 - 0.2, HOUSING)
				end
			end
		end

		----------------------------------------------------------------
		-- ░ rétroviseurs ░
		----------------------------------------------------------------
		local Aw = sectionAt(st, s.Ws + 0.45)
		for _, sx in ipairs({ -1, 1 }) do
			local mz = s.Ws + (if sports then 0.55 else 0.45)
			local my = Aw.by + 0.34
			ell(b, "Mirror", sx * (hw + 0.28), my, mz, 0.66, 0.44, 0.48, paint)
			if full then
				local ax0, ax1 = sx * (Aw.bx - 0.05), sx * (hw + 0.05)
				box(b, "MirrorArm", math.min(ax0, ax1), math.max(ax0, ax1), my - 0.2, my - 0.08, mz - 0.08, mz + 0.08, HOUSING)
				local gx0, gx1 = sx * (hw + 0.06), sx * (hw + 0.5)
				box(b, "MirrorGlass", math.min(gx0, gx1), math.max(gx0, gx1), my - 0.15, my + 0.15, mz + 0.2, mz + 0.28, CHROME, M.Glass).Reflectance = 0.5
				local mi = ell(b, "MirrorBlinker", sx * (hw + 0.56), my - 0.06, mz - 0.02, 0.1, 0.1, 0.24, AMBER)
				mi:SetAttribute("Side", sx)
			end
		end

		----------------------------------------------------------------
		-- ░ détails "Full" : joints de portes, poignées, trappe, intérieur ░
		----------------------------------------------------------------
		if full then
			local function archY(z: number): number
				for _, ax in ipairs({ s.AxleF, s.AxleR }) do
					local dz = z - ax
					if math.abs(dz) < ra then
						return r + math.sqrt(ra * ra - dz * dz)
					end
				end
				return g.sill
			end
			local seams: { number } = {}
			local handles: { number } = {}
			if style == "Van" then
				seams = { s.Ws + 0.25, s.R0 + 2.4, s.R0 + 6.2 }
				handles = { s.R0 + 2.2, s.R0 + 6.0 }
			elseif pickup then
				seams = { s.Ws + 0.2, s.R1 - 0.1 }
				handles = { s.R1 - 0.45 }
			elseif s.Doors == 4 then
				local bz = s.R0 + (s.R1 - s.R0) * (if style == "Limo" then 0.36 else 0.48)
				local rz = if style == "Limo" then s.R0 + (s.R1 - s.R0) * 0.7 else math.min(s.R1 - 0.1, g.aR0 + 0.2)
				seams = { s.Ws + 0.2, bz, rz }
				handles = { bz - 0.4, rz - 0.4 }
			else
				local bz = if sports then s.R1 - 0.35 else s.R0 + (s.R1 - s.R0) * 0.68
				seams = { s.Ws + (if sports then 0.5 else 0.2), bz }
				handles = { bz - 0.45 }
			end
			for _, sx in ipairs({ -1, 1 }) do
				for _, z in ipairs(seams) do
					local y0 = math.max(g.sill + 0.25, archY(z) + 0.05)
					local S = sectionAt(st, z)
					local x0, x1 = sx * (hw - 0.02), sx * (hw + 0.012)
					if S.fy - y0 > 0.1 then
						box(b, "DoorSeam", math.min(x0, x1), math.max(x0, x1), y0, S.fy - 0.02, z - 0.022, z + 0.022, GAP)
					end
					-- (sur l'épaule, jusqu'à la ceinture)
					rod(b, "DoorSeam", V3(sx * (S.fx + 0.004), S.fy, z), V3(sx * (S.bx + 0.004), S.by, z), 0.045, GAP)
				end
				for _, z in ipairs(handles) do
					local S = sectionAt(st, z)
					local hx0, hx1 = sx * (hw - 0.03), sx * (hw + 0.07)
					box(b, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), S.fy - 0.3, S.fy - 0.18, z - 0.3, z + 0.1, if style == "Limo" then CHROME else paint, if style == "Limo" then M.Metal else M.SmoothPlastic)
				end
			end
			-- trappe à carburant (côté droit, au-dessus de la roue arrière)
			local fz = math.min(g.aR0 - 0.45, s.Rw - 0.4)
			local fsx = if sports then -1 else 1
			cylX(b, "FuelCap", fsx * (hw + 0.004), s.Low - 0.35, if pickup or sports then g.aR1 + 0.5 else fz, 0.03, 0.42, paint:Lerp(GAP, 0.15))

			-- ░ habitacle ░
			local wc = hw - s.Tumble - 0.12
			local roofIn = s.Roof - 0.3
			box(b, "Carpet", -wc, wc, g.sill + 0.02, g.sill + 0.12, s.Ws + 0.3, if pickup then s.R1 - 0.1 else s.Rw - 0.2, CARPET, M.Fabric)
			local function seat(x: number, z: number, top: number, w: number, tall: boolean)
				box(b, "SeatCushion", x - w, x + w, top - 0.35, top, z - 0.75, z + 0.45, SEAT, M.Fabric)
				local backTop = math.min(top + 2.2, roofIn - 0.35)
				slab(b, "SeatBack", x, w * 2, top - 0.05, z + 0.62, backTop, z + 0.95, 0.34, SEAT, M.Fabric)
				if tall then
					box(b, "Headrest", x - 0.36, x + 0.36, backTop + 0.05, math.min(backTop + 0.5, roofIn - 0.05), z + 0.85, z + 1.15, SEAT2, M.Fabric)
				end
			end
			seat(seatX, seatZ, seatTop, 0.62, true)
			seat(-seatX, seatZ, seatTop, 0.62, true)
			if style ~= "Sports" and not pickup and style ~= "Van" then
				local rz = seatZ + 2.35
				if style == "Limo" then
					rz = seatZ + 3.2
				end
				local lim = if twoBox then s.R1 + 0.4 else s.Rw - 0.3
				if rz + 1.0 < lim then
					seat(0, rz, seatTop + 0.05, wc - 0.1, false)
				end
			end
			if style == "Van" then
				-- coin salon du combi : banquette + petite table
				box(b, "VanBench", -wc + 0.1, wc - 0.1, seatTop - 0.35, seatTop, s.R1 - 2.6, s.R1 - 1.3, SEAT2, M.Fabric)
				slab(b, "VanBenchBack", 0, wc * 2 - 0.2, seatTop, s.R1 - 1.25, seatTop + 1.9, s.R1 - 0.95, 0.3, SEAT2, M.Fabric)
				box(b, "VanTable", -1.0, 1.0, seatTop + 0.6, seatTop + 0.72, s.R1 - 4.4, s.R1 - 3.2, Color3.fromRGB(196, 160, 120), M.Wood)
			end
			-- planche de bord, écran, compteurs, volant, console
			local dashZ0 = s.Ws + 0.12
			local dashZ1 = s.Ws + (if style == "Van" then 0.9 else 1.05)
			local by0 = sectionAt(st, s.Ws + 0.1).by
			box(b, "Dashboard", -wc, wc, by0 - 0.55, by0 + 0.06, dashZ0, dashZ1, TRIM)
			box(b, "DashTop", -wc + 0.1, wc - 0.1, by0 + 0.06, by0 + 0.12, dashZ0 + 0.1, dashZ1 - 0.2, GRAPHITE, M.Fabric)
			box(b, "Screen", -0.5, 0.5, by0 + 0.12, by0 + 0.52, dashZ1 - 0.45, dashZ1 - 0.37, SCREEN, M.Glass)
			local swZ = math.min(seatZ - 1.45, dashZ1 + 0.35)
			local sw = cylZ(b, "SteeringWheel", seatX, by0 + 0.08, swZ, 0.1, 1.0, HOUSING)
			sw.CFrame = sw.CFrame * CFrame.Angles(0, 0, math.rad(-22))
			cylZ(b, "WheelHub", seatX, by0 + 0.08, swZ + 0.08, 0.1, 0.32, GRAPHITE)
			rod(b, "SteeringColumn", V3(seatX, by0 - 0.25, dashZ1 - 0.1), V3(seatX, by0 + 0.02, swZ + 0.1), 0.16, GRAPHITE)
			if style ~= "Van" then
				box(b, "Console", -0.32, 0.32, g.sill + 0.12, seatTop - 0.05, dashZ1 - 0.05, seatZ + 0.3, TRIM)
				ell(b, "GearKnob", 0, seatTop + 0.18, seatZ - 0.8, 0.2, 0.24, 0.2, CHROME, M.Metal)
			end
			if not sports then
				-- ciel de toit clair
				box(b, "Headliner", -(hw - s.Inset - 0.25), hw - s.Inset - 0.25, roofIn - 0.08, roofIn - 0.02, s.R0 + 0.35, s.R1 - 0.35, HEADLINER, M.Fabric)
			end
		end

		----------------------------------------------------------------
		-- ░ bande bicolore (option) ░
		----------------------------------------------------------------
		if stripe then
			if sports then
				-- deux bandes de course sur le capot (suivent la courbe) + le coffre
				for _, sx in ipairs({ -1, 1 }) do
					local x = sx * 0.4
					local prev: St? = nil
					for _, S in ipairs(st) do
						if S.z > s.Ws - g.cowl + 0.01 then
							break
						end
						if prev and S.z - prev.z > 0.05 then
							strip(b, "Stripe", V3(x, prev.t + 0.01, prev.z + 0.02), V3(x, S.t + 0.01, S.z), V3(0, 1, 0), 0.4, 0.04, stripe :: Color3)
						end
						prev = S
					end
					box(b, "Stripe", x - 0.2, x + 0.2, s.Deck - 0.02, s.Deck + 0.02, s.Rw + 2.2, zB - 1.4, stripe :: Color3)
				end
			elseif style ~= "Van" and style ~= "Bubble" then
				-- filet latéral sur le flanc (entre les roues)
				for _, sx in ipairs({ -1, 1 }) do
					local x0, x1 = sx * (hw - 0.02), sx * (hw + 0.018)
					local y = s.Low - 0.55
					box(b, "Stripe", math.min(x0, x1), math.max(x0, x1), y - 0.07, y + 0.07, g.aF1 + 0.2, g.aR0 - 0.2, stripe :: Color3)
				end
			end
		end

		----------------------------------------------------------------
		-- ░ particularités de chaque modèle ░
		----------------------------------------------------------------
		if style == "Bubble" and full then
			-- roue de secours ronde à l'arrière (housse couleur carrosserie)
			cylZ(b, "SpareWheel", 0, s.Low + 0.2, zB + 0.25, 0.42, 1.5, TYRE, M.Rubber)
			cylZ(b, "SpareCover", 0, s.Low + 0.2, zB + 0.48, 0.1, 1.2, WHITE:Lerp(paint, 0.3))
		elseif style == "Hatch" then
			local Rr = sectionAt(st, s.R1)
			box(b, "Spoiler", -Rr.e + 0.1, Rr.e - 0.1, Rr.t - 0.02, Rr.t + 0.1, s.R1 - 0.05, s.R1 + 0.5, GRAPHITE)
		elseif style == "SUV" then
			local R0s, R1s = sectionAt(st, s.R0 + 0.4), sectionAt(st, s.R1 - 0.4)
			for _, sx in ipairs({ -1, 1 }) do
				local x = sx * (R0s.e - 0.25)
				rod(b, "RoofRail", V3(x, R0s.t + 0.12, R0s.z), V3(x, R1s.t + 0.12, R1s.z), 0.16, HOUSING, M.Metal)
				if full then
					for _, zz in ipairs({ R0s.z, R1s.z }) do
						local Sz = sectionAt(st, zz)
						box(b, "RailFoot", x - 0.08, x + 0.08, Sz.t - 0.02, Sz.t + 0.1, zz - 0.15, zz + 0.15, HOUSING)
					end
				end
			end
			if full then
				box(b, "SkidPlate", -s.W * 0.28, s.W * 0.28, s.Clear - 0.06, g.sill + 0.12, zF - 0.05, zF + 0.5, CHROME, M.Metal)
				box(b, "SkidPlateR", -s.W * 0.25, s.W * 0.25, s.Clear - 0.06, g.sill + 0.12, zB - 0.5, zB + 0.05, CHROME, M.Metal)
			end
		elseif pickup then
			-- benne : plancher, parois intérieures, face avant, hayon ; paroi arrière de la cabine
			local bz0, bz1 = s.R1 + 0.02, zB - 0.25
			local bedY = s.Low - 0.3
			local ix = hw - 0.28
			box(b, "BedFloor", -ix, ix, bedY - 0.1, bedY, bz0, bz1, GRAPHITE, M.DiamondPlate)
			for _, sx in ipairs({ -1, 1 }) do
				local x0, x1 = sx * ix, sx * (ix + 0.1)
				box(b, "BedWall", math.min(x0, x1), math.max(x0, x1), bedY, s.Deck - 0.02, bz0, bz1, paint)
				local rx0, rx1 = sx * (ix - 0.04), sx * (hw - 0.06)
				box(b, "BedRail", math.min(rx0, rx1), math.max(rx0, rx1), s.Deck - 0.02, s.Deck + 0.1, bz0, zB - 0.1, HOUSING, M.Plastic)
			end
			box(b, "BedFront", -ix, ix, bedY, s.Deck, bz0, bz0 + 0.12, paint)
			box(b, "Tailgate", -ix, ix, bedY, s.Deck - 0.04, bz1, zB - 0.1, paint)
			local cw = hw - s.Inset
			box(b, "CabBack", -cw, cw, s.Deck, s.Roof - 0.12, s.R1 - 0.02, s.R1 + 0.1, paint)
			box(b, "CabGlass", -cw + 0.45, cw - 0.45, s.Deck + 0.35, s.Roof - 0.45, s.R1 + 0.1, s.R1 + 0.14, GLASS, M.Glass)
			if full then
				for k = -2, 2 do
					box(b, "BedRib", k * 0.9 - 0.08, k * 0.9 + 0.08, bedY, bedY + 0.06, bz0 + 0.3, bz1 - 0.3, CHROME, M.Metal)
				end
				box(b, "TailgateHandle", -0.4, 0.4, s.Deck - 0.45, s.Deck - 0.3, zB - 0.12, zB - 0.04, HOUSING)
				box(b, "TowHitch", -0.22, 0.22, g.sill - 0.02, g.sill + 0.2, zB - 0.1, zB + 0.45, GRAPHITE, M.Metal)
				-- marchepieds
				for _, sx in ipairs({ -1, 1 }) do
					local sx0, sx1 = sx * (hw - 0.2), sx * (hw + 0.3)
					box(b, "SideStep", math.min(sx0, sx1), math.max(sx0, sx1), g.sill - 0.18, g.sill - 0.04, g.aF1 + 0.2, g.aR0 - 0.2, GRAPHITE, M.DiamondPlate)
				end
			end
		elseif style == "Van" then
			-- gros logo rond, galerie + planche de surf
			if full then
				local vy = fy + 0.15
				cylZ(b, "Badge", 0, vy - 0.55, zF - 0.05, 0.06, 0.7, CHROME, M.Metal)
				local Rr = sectionAt(st, s.R0 + 1)
				for _, z in ipairs({ s.R0 + 1.4, s.R1 - 1.4 }) do
					box(b, "RackBar", -Rr.e + 0.2, Rr.e - 0.2, s.Roof + 0.02, s.Roof + 0.2, z - 0.1, z + 0.1, HOUSING, M.Metal)
				end
				local boardL = math.min(s.R1 - s.R0 - 1.2, 7.2)
				local bc = (s.R0 + s.R1) / 2
				local surf = Color3.fromRGB(120, 220, 230)
				box(b, "Surfboard", -0.7, 0.7, s.Roof + 0.2, s.Roof + 0.34, bc - boardL / 2 + 0.7, bc + boardL / 2 - 0.4, surf)
				cylY(b, "SurfboardNose", 0, s.Roof + 0.27, bc - boardL / 2 + 0.7, 0.14, 1.4, surf)
				box(b, "SurfboardStripe", -0.1, 0.1, s.Roof + 0.34, s.Roof + 0.37, bc - boardL / 2 + 0.9, bc + boardL / 2 - 0.55, Color3.fromRGB(255, 150, 196))
				-- rail de porte coulissante
				local rx0, rx1 = hw - s.Inset + 0.02, hw - s.Inset + 0.1
				local Sr = sectionAt(st, s.R0 + 4)
				box(b, "SlideRail", rx0, rx1, Sr.by + 0.95, Sr.by + 1.02, s.R0 + 2.5, s.R0 + 6.1, HOUSING, M.Metal)
			end
		elseif style == "Limo" then
			if full then
				ell(b, "Ornament", 0, sectionAt(st, zF + 0.6).t + 0.12, zF + 0.6, 0.14, 0.3, 0.14, CHROME, M.Metal)
				for _, sx in ipairs({ -1, 1 }) do
					local cx0, cx1 = sx * (hw - 0.02), sx * (hw + 0.05)
					box(b, "ChromeSill", math.min(cx0, cx1), math.max(cx0, cx1), g.sill + 0.32, g.sill + 0.4, g.aF1 + 0.1, g.aR0 - 0.1, CHROME, M.Metal)
				end
			end
		end
	end

	-- ░ roues ░
	for index, pos in ipairs(CarModels.WheelPositions(kind)) do
		wheel(b, s, index, pos.X, pos.Z, look)
	end

	-- attributs (siège du conducteur : repère du pivot)
	model:SetAttribute("CarId", type(carId) == "string" and carId or kind)
	model:SetAttribute("CarKind", kind)
	model:SetAttribute("Length", s.L * scale.Z)
	model:SetAttribute("Width", s.W * scale.X)
	model:SetAttribute("Height", s.Roof * scale.Y)
	model:SetAttribute("WheelRadius", s.WheelD / 2 * math.min(scale.Y, scale.Z))
	model:SetAttribute("SeatCF", CFrame.new(P(b, seatX, seatTop, seatZ)))
	model:SetAttribute("Lod", lod)
	model:SetAttribute("PartCount", b.Count)
	return model
end

----------------------------------------------------------------------
-- Animation des roues d'un modèle ANCRÉ (circulation, vitrines)
----------------------------------------------------------------------

export type WheelSet = {
	Center: CFrame,
	Front: boolean,
	Radius: number,
	Spin: { BasePart },
	SpinOff: { CFrame },
	Steer: { BasePart },
	SteerOff: { CFrame },
}
export type Rig = { Body: { BasePart }, BodyOff: { CFrame }, Wheels: { WheelSet }, Parts: { BasePart }, Frames: { CFrame } }

function CarModels.WheelRig(model: Model): Rig
	-- (générique : toute maquette dont les pièces de roue portent "Wheel" /
	-- "Spin" ; le centre et le rayon de chaque roue = ceux de son pneu "Tyre")
	local pivot = model:GetPivot()
	local groups: { [number]: { BasePart } } = {}
	local tyres: { [number]: BasePart } = {}
	local body: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local w = d:GetAttribute("Wheel")
			if type(w) == "number" then
				groups[w] = groups[w] or {}
				table.insert(groups[w], d)
				if d.Name == "Tyre" and not tyres[w] then
					tyres[w] = d
				end
			else
				table.insert(body, d)
			end
		end
	end
	local rig: Rig = { Body = body, BodyOff = {}, Wheels = {}, Parts = {}, Frames = {} }
	for _, p in ipairs(body) do
		table.insert(rig.BodyOff, pivot:ToObjectSpace(p.CFrame))
		table.insert(rig.Parts, p)
	end
	local indices = {}
	for index in pairs(groups) do
		table.insert(indices, index)
	end
	table.sort(indices)
	for _, index in ipairs(indices) do
		local tyre = tyres[index]
		local list = groups[index]
		if not tyre then
			-- (pas de pneu : pièces fixées au corps)
			for _, p in ipairs(list) do
				table.insert(rig.Body, p)
				table.insert(rig.BodyOff, pivot:ToObjectSpace(p.CFrame))
				table.insert(rig.Parts, p)
			end
		else
			local center = CFrame.new(pivot:PointToObjectSpace(tyre.Position))
			local set: WheelSet = { Center = center, Front = center.Position.Z < 0, Radius = tyre.Size.Y / 2, Spin = {}, SpinOff = {}, Steer = {}, SteerOff = {} }
			local world = pivot * center
			for _, p in ipairs(list) do
				local off = world:ToObjectSpace(p.CFrame)
				if p:GetAttribute("Spin") then
					table.insert(set.Spin, p)
					table.insert(set.SpinOff, off)
				else
					table.insert(set.Steer, p)
					table.insert(set.SteerOff, off)
				end
			end
			table.insert(rig.Wheels, set)
		end
	end
	-- (ordre de rig.Parts = celui de PoseRig : corps, puis chaque roue)
	table.clear(rig.Parts)
	for _, p in ipairs(rig.Body) do
		table.insert(rig.Parts, p)
	end
	for _, set in ipairs(rig.Wheels) do
		for _, p in ipairs(set.Spin) do
			table.insert(rig.Parts, p)
		end
		for _, p in ipairs(set.Steer) do
			table.insert(rig.Parts, p)
		end
	end
	for i = 1, #rig.Parts do
		rig.Frames[i] = rig.Parts[i].CFrame
	end
	return rig
end

-- Pose : pivot (monde), rotation des roues `spin` (rad), braquage `steer`
-- (rad, roues avant), `bob` = CFrame de caisse (suspension). Renvoie les
-- listes à passer à workspace:BulkMoveTo.
function CarModels.PoseRig(rig: Rig, pivot: CFrame, spin: number, steer: number, bob: CFrame?): ({ BasePart }, { CFrame })
	local frames = rig.Frames
	local i = 0
	local body = if bob then pivot * bob else pivot
	for _, off in ipairs(rig.BodyOff) do
		i += 1
		frames[i] = body * off
	end
	local spinCF = CFrame.Angles(-spin, 0, 0)
	for _, set in ipairs(rig.Wheels) do
		local c = pivot * set.Center
		local steered = if set.Front and steer ~= 0 then c * CFrame.Angles(0, steer, 0) else c
		local spun = steered * spinCF
		for _, off in ipairs(set.SpinOff) do
			i += 1
			frames[i] = spun * off
		end
		for _, off in ipairs(set.SteerOff) do
			i += 1
			frames[i] = steered * off
		end
	end
	return rig.Parts, frames
end

return CarModels
