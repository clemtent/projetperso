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

	v10 (CARS10) "10x plus réalistes et personnalisables" :
	  - SILHOUETTES : proportions réelles (plus basses, roues plus grandes,
	    jour de roue serré), nez et poupe ARRONDIS de profil (le capot plonge
	    en quart de cercle, le coffre retombe), coins arrondis vus de dessus,
	    capot / toit / vitres BOMBÉS (deux pans qui se rejoignent au milieu),
	    épaules arrondies, ceinture qui monte vers l'arrière ; phares modernes
	    fins et étirés dans l'angle (sourcil de feu de jour, projecteurs, sans
	    chrome), calandre entre les phares, bouclier avec grande prise d'air,
	    feux arrière fins étirés dans l'angle (même soin devant / derrière).
	  - ATELIER (opts.Mods = { [Kind] = Id } de Config.Cars.Mods) : finition
	    (brillant / métallisé / mat / nacré), toit bicolore (dont carbone),
	    8 jantes (Mesh, Split, Turbine, Deep dish, Retro, Star, Sport...),
	    couleur des jantes, pneus (taille basse, flanc blanc, liseré rouge,
	    tout-terrain), lame avant, bas de caisse, ailerons (lèvre, canard,
	    aileron, GT), vitres teintées, néon sous caisse (Neon doux, aucune
	    lumière), sellerie. Mid garde les ailerons, bas de caisse, néon,
	    couleurs ; Low la peinture.
	  - Budgets mesurés : Full 390..500 pièces (options comprises), Mid
	    140..170, Low ~37.
	API v10 (en plus) :
	  CarModels.Stats(carIdOrKind, tuning?) -> Stats (TopSpeed studs/s, Accel,
	    Brake, Coast, Grip, DriftGrip, TurnRate, Stability, Comfort, ZeroToTop,
	    Rating 100..999, Class "D".."S", Stars) : conduite (CarClient) et
	    courses (RACE10). tuning = { Engine, Tyres, Suspension } (0..3).
	  CarModels.CleanTuning(t) / TuningOf(data, carId)
	  CarModels.PriceFor(carId, factor) -> prix en Dopamine (Config.Cars.MinPrice)
	  CarModels.CleanMods(mods) / ModOf(mods, kind) / EncodeMods(mods) -> "K=Id;..."
	    / DecodeMods(text)
	  CarModels.LightRig(model) -> rig ; CarModels.SetLights(rig, { Brake, Reverse,
	    Blink = -1|0|1, Hazard, Head }) : feux stop / recul / clignotants /
	    phares en Neon (côté client, local ; Blink / Hazard = état allumé du
	    moment, l'appelant fait la cadence).
	  Attributs en plus : Finish, Mods (texte encodé).
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
	BubbleCar = { L = 9.2, W = 5.2, WheelD = 2.0, TyreW = 0.78, Clear = 0.45, Low = 2.35, Belt = 2.95, Roof = 4.6, AxleF = -2.75, AxleR = 2.8, Ws = -2.55, R0 = -0.6, R1 = 2.65, Rw = 4.15, Inset = 0.8, HoodF = 2.3, HoodR = 2.75, Deck = 3.0, BeltRise = 0, Tumble = 0.34, NoseR = 1.1, TailR = 1.0, NoseLow = 1.95, Doors = 2, Style = "Bubble" },
	CityCar = { L = 10.6, W = 5.1, WheelD = 2.05, TyreW = 0.82, Clear = 0.42, Low = 2.4, Belt = 2.95, Roof = 4.55, AxleF = -3.2, AxleR = 3.45, Ws = -2.75, R0 = -0.55, R1 = 3.3, Rw = 4.85, Inset = 0.78, HoodF = 2.3, HoodR = 2.8, Deck = 3.05, BeltRise = 0.08, Tumble = 0.32, NoseR = 0.95, TailR = 0.85, NoseLow = 1.95, Doors = 2, Style = "City" },
	Hatchback = { L = 12.2, W = 5.4, WheelD = 2.2, TyreW = 0.9, Clear = 0.42, Low = 2.45, Belt = 3.0, Roof = 4.5, AxleF = -3.8, AxleR = 3.85, Ws = -3.25, R0 = -0.6, R1 = 3.95, Rw = 5.7, Inset = 0.8, HoodF = 2.35, HoodR = 2.85, Deck = 3.1, BeltRise = 0.12, Tumble = 0.34, NoseR = 0.9, TailR = 0.95, NoseLow = 2.0, Doors = 4, Style = "Hatch" },
	Pickup = { L = 13, W = 6.0, WheelD = 2.6, TyreW = 1.05, Clear = 0.75, Low = 3.1, Belt = 3.7, Roof = 5.5, AxleF = -4.1, AxleR = 3.95, Ws = -2.9, R0 = -1.1, R1 = 1.5, Rw = 1.5, Inset = 0.55, HoodF = 3.3, HoodR = 3.6, Deck = 3.75, BeltRise = 0, Tumble = 0.28, NoseR = 0.7, TailR = 0.5, NoseLow = 2.95, Doors = 2, Style = "Pickup" },
	SUV = { L = 12.8, W = 5.8, WheelD = 2.45, TyreW = 1.0, Clear = 0.62, Low = 2.85, Belt = 3.45, Roof = 5.3, AxleF = -3.9, AxleR = 4.0, Ws = -3.2, R0 = -0.8, R1 = 4.7, Rw = 5.85, Inset = 0.72, HoodF = 3.0, HoodR = 3.35, Deck = 3.6, BeltRise = 0.1, Tumble = 0.32, NoseR = 0.85, TailR = 0.9, NoseLow = 2.65, Doors = 4, Style = "SUV" },
	Van = { L = 13, W = 5.8, WheelD = 2.2, TyreW = 0.88, Clear = 0.52, Low = 2.55, Belt = 3.35, Roof = 6.0, AxleF = -4.3, AxleR = 4.15, Ws = -5.4, R0 = -4.0, R1 = 6.1, Rw = 6.42, Inset = 0.5, HoodF = 2.75, HoodR = 3.2, Deck = 3.5, BeltRise = 0, Tumble = 0.3, NoseR = 1.0, TailR = 0.85, NoseLow = 2.4, Doors = 2, Style = "Van" },
	SportsCar = { L = 12.8, W = 5.9, WheelD = 2.15, TyreW = 1.1, Clear = 0.32, Low = 2.35, Belt = 2.7, Roof = 3.65, AxleF = -3.9, AxleR = 3.75, Ws = -1.35, R0 = -0.25, R1 = 1.8, Rw = 2.3, Inset = 0.5, HoodF = 1.95, HoodR = 2.45, Deck = 2.65, BeltRise = 0.1, Tumble = 0.3, NoseR = 1.2, TailR = 1.2, NoseLow = 1.65, Doors = 2, Style = "Sports" },
	Limo = { L = 15.2, W = 5.7, WheelD = 2.25, TyreW = 0.92, Clear = 0.45, Low = 2.5, Belt = 3.05, Roof = 4.6, AxleF = -4.95, AxleR = 4.85, Ws = -3.5, R0 = -1.0, R1 = 3.5, Rw = 5.0, Inset = 0.78, HoodF = 2.5, HoodR = 2.9, Deck = 3.15, BeltRise = 0, Tumble = 0.32, NoseR = 0.9, TailR = 1.0, NoseLow = 2.2, Doors = 4, Style = "Limo" },
}
CarModels.Specs = SPECS
CarModels.Kinds = { "BubbleCar", "CityCar", "Hatchback", "Pickup", "SUV", "Van", "SportsCar", "Limo" }

-- Couleurs fixes
local GLASS = Color3.fromRGB(84, 104, 126) -- verre teinté (transparence automatique)
local GLASS_T = 0.45
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

----------------------------------------------------------------------
-- 🏁 (v10, CARS10) PERFORMANCES + PRÉPARATION (lu par CarClient pour la
-- conduite et par RACE10 pour les courses : IA, validation serveur)
----------------------------------------------------------------------
export type Tuning = { Engine: number, Tyres: number, Suspension: number }
export type Stats = {
	CarId: string,
	Kind: string,
	Tuning: Tuning,
	TopSpeed: number, -- studs/s (marche avant, à fond, sur le plat)
	Reverse: number, -- studs/s
	Accel: number, -- studs/s² au démarrage (s'essouffle vers TopSpeed)
	Brake: number, -- studs/s² en freinant
	Coast: number, -- studs/s² sans rien toucher
	Grip: number, -- adhérence latérale (1/s : vitesse de résorption de la glisse)
	DriftGrip: number, -- adhérence en dérapage (1/s)
	TurnRate: number, -- rad/s max (à vitesse moyenne)
	Stability: number, -- 0..1 : part du virage gardée à pleine vitesse
	Comfort: number, -- 1..5
	ZeroToTop: number, -- s de 0 à 95 % de TopSpeed (simulation du même modèle que CarClient)
	Rating: number, -- indice de performance 100..999 (appariement, IA)
	Class: string, -- "D" | "C" | "B" | "A" | "S"
	Stars: { Speed: number, Accel: number, Grip: number, Comfort: number },
}

local BASE_ACCEL, BASE_BRAKE, BASE_COAST, BASE_TURN = 24, 60, 14, 1.9

local function kindOfPublic(carId: string?): string
	return kindOf(carId)
end

-- Préparation propre (niveaux entiers 0..MaxLevel)
function CarModels.CleanTuning(tuning: any): Tuning
	local maxLevel = (Config.Cars.Tuning and Config.Cars.Tuning.MaxLevel) or 3
	local out = { Engine = 0, Tyres = 0, Suspension = 0 }
	if type(tuning) == "table" then
		for key in pairs(out) do
			local v = tonumber(tuning[key])
			if v and v == v then
				out[key] = math.clamp(math.floor(v), 0, maxLevel)
			end
		end
	end
	return out :: Tuning
end

-- Préparation d'une voiture dans les données d'un joueur (data.Cars.Tuning)
function CarModels.TuningOf(data: any, carId: string): Tuning
	local cars = type(data) == "table" and data.Cars
	local all = type(cars) == "table" and cars.Tuning
	return CarModels.CleanTuning(type(all) == "table" and all[carId] or nil)
end

-- Temps de 0 à 95 % de la vitesse max avec le modèle d'accélération de
-- CarClient (accélération x (1 - 0,55 (v / vmax)²))
local function zeroToTop(top: number, accel: number): number
	local v, t = 0, 0
	local dt = 1 / 30
	while v < top * 0.95 and t < 60 do
		v += accel * (1 - 0.55 * (v / top) ^ 2) * dt
		t += dt
	end
	return t
end

-- Performances d'une voiture (carId ou Kind) avec sa préparation.
-- Déterministe, pur, identique serveur / client.
function CarModels.Stats(carId: string?, tuning: any?): Stats
	local kind = kindOfPublic(carId)
	local h = HANDLING[kind] or HANDLING.CityCar
	local t = CarModels.CleanTuning(tuning)
	local maxSpeed = tonumber(Config.Cars.MaxSpeed) or 50
	local top = maxSpeed * h[1] * (1 + 0.1 * t.Engine)
	local accel = BASE_ACCEL * h[2] * (1 + 0.12 * t.Engine)
	local brake = BASE_BRAKE * (0.9 + 0.1 * h[3]) * (1 + 0.1 * t.Tyres)
	local grip = 10 * h[3] * (1 + 0.08 * t.Tyres + 0.03 * t.Suspension)
	local driftGrip = 3 * h[3] * (1 + 0.1 * t.Suspension + 0.04 * t.Tyres)
	local turn = BASE_TURN * (0.92 + 0.08 * h[3]) * (1 + 0.05 * t.Suspension)
	local stability = math.clamp(0.6 + 0.05 * t.Suspension + 0.03 * t.Tyres, 0, 0.9)
	local z = zeroToTop(top, accel)
	-- indice : vitesse 45 %, accélération 30 %, tenue 25 % (100..999)
	local speedN = top / (maxSpeed * 1.35)
	local accelN = accel / (BASE_ACCEL * 1.9)
	local gripN = (grip / 10 + turn / BASE_TURN) / 2 / 1.5
	local rating = math.clamp(math.floor(100 + 900 * (0.45 * speedN + 0.3 * accelN + 0.25 * gripN) ^ 1.6 + 0.5), 100, 999)
	local class = if rating >= 750 then "S" elseif rating >= 600 then "A" elseif rating >= 490 then "B" elseif rating >= 400 then "C" else "D"
	local function stars(v: number): number
		return math.clamp(math.floor(v + 0.5), 1, 5)
	end
	return {
		CarId = type(carId) == "string" and carId or kind,
		Kind = kind,
		Tuning = t,
		TopSpeed = top,
		Reverse = tonumber(Config.Cars.ReverseSpeed) or 18,
		Accel = accel,
		Brake = brake,
		Coast = BASE_COAST,
		Grip = grip,
		DriftGrip = driftGrip,
		TurnRate = turn,
		Stability = stability,
		Comfort = h[4],
		ZeroToTop = z,
		Rating = rating,
		Class = class,
		Stars = {
			Speed = stars((top / maxSpeed - 0.7) / 0.1),
			Accel = stars((accel / BASE_ACCEL - 0.7) / 0.13),
			Grip = stars((grip / 10 - 0.7) / 0.1),
			Comfort = stars(h[4]),
		},
	} :: Stats
end

-- Prix d'une option / d'un niveau pour une voiture (Price x prix de la
-- voiture, au moins MinPrice, arrondi à 2 chiffres significatifs ; 0 = gratuit)
function CarModels.PriceFor(carId: string, factor: number?): number
	local f = tonumber(factor) or 0
	if f <= 0 then
		return 0
	end
	local car = Config.CarsById and Config.CarsById[carId]
	local base = car and tonumber(car.Cost) or 1e6
	local price = math.max(tonumber(Config.Cars.MinPrice) or 0, base * f)
	local unit = 10 ^ math.max(0, math.floor(math.log10(price)) - 1)
	return math.floor(price / unit + 0.5) * unit
end

-- 🎨 (v10) Options visuelles d'une voiture (data.Cars.Mods[carId]) : on ne
-- garde que les clés connues de Config.Cars.Mods avec un Id connu, et pas
-- les valeurs d'origine (1re entrée). Tables compactes, sûres.
function CarModels.CleanMods(mods: any): { [string]: string }
	local out = {}
	if type(mods) ~= "table" then
		return out
	end
	local byKind = Config.CarModsById or {}
	for kind, list in pairs(Config.Cars.Mods or {}) do
		local id = mods[kind]
		if type(id) == "string" and byKind[kind] and byKind[kind][id] and list[1] and list[1].Id ~= id then
			out[kind] = id
		end
	end
	return out
end

-- Valeur d'une option (Id ; l'origine si absente)
function CarModels.ModOf(mods: any, kind: string): string
	local id = type(mods) == "table" and mods[kind]
	local byKind = Config.CarModsById and Config.CarModsById[kind]
	if type(id) == "string" and byKind and byKind[id] then
		return id
	end
	local list = Config.Cars.Mods and Config.Cars.Mods[kind]
	return list and list[1] and list[1].Id or ""
end

-- Texte compact pour un attribut répliqué : "Rims=Mesh;Tint=Dark" (et retour)
function CarModels.EncodeMods(mods: any): string
	local clean = CarModels.CleanMods(mods)
	local keys = {}
	for kind in pairs(clean) do
		table.insert(keys, kind)
	end
	table.sort(keys)
	local parts = {}
	for _, kind in ipairs(keys) do
		table.insert(parts, kind .. "=" .. clean[kind])
	end
	return table.concat(parts, ";")
end
function CarModels.DecodeMods(text: any): { [string]: string }
	local raw = {}
	if type(text) == "string" then
		for kind, id in string.gmatch(text, "(%w+)=(%w+)") do
			raw[kind] = id
		end
	end
	return CarModels.CleanMods(raw)
end

-- (v10) finitions : teinte (nacré, mat) et brillance (Reflectance) par niveau de détail
local FINISH_GLOSS: { [string]: { number } } = {
	Gloss = { 0.03, 0.08, 0.15 },
	Metallic = { 0.05, 0.16, 0.3 },
	Pearl = { 0.04, 0.12, 0.24 },
	Matte = { 0, 0, 0 },
}
local function finishColor(c: Color3, finish: any): Color3
	if finish == "Pearl" then
		return c:Lerp(Color3.fromRGB(255, 244, 252), 0.1)
	elseif finish == "Matte" then
		return c:Lerp(Color3.fromRGB(120, 120, 124), 0.08)
	elseif finish == "Metallic" then
		return c:Lerp(Color3.fromRGB(20, 20, 26), 0.06)
	end
	return c
end
-- vitres teintées : couleur, transparence
local TINTS: { [string]: { any } } = {
	Clear = { GLASS, GLASS_T },
	Light = { Color3.fromRGB(66, 82, 100), 0.36 },
	Dark = { Color3.fromRGB(40, 48, 60), 0.26 },
	Limo = { Color3.fromRGB(20, 22, 28), 0.12 },
}

-- Repeint un modèle déjà construit (pièces marquées "Paint") : pour changer
-- de couleur SANS reconstruire (fenêtre "Mes voitures", concession)
function CarModels.Repaint(model: Instance, carId: string?, color: any?)
	local paint = finishColor(CarModels.ColorOf(carId, color), model:GetAttribute("Finish"))
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
	PaintMat: Enum.Material?, -- (v10) finition mate : matériau de la peinture
	GlassColor: Color3, -- (v10) teinte des vitres
	GlassT: number, -- (v10) transparence des vitres
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
			if b.PaintMat then
				p.Material = b.PaintMat
			end
		end
	elseif color == GLASS then
		p.Color = b.GlassColor
		p.Transparency = b.GlassT
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
	if w.Unit:Dot(ud) < 0.99966 then -- (v10 : ~1,5° de tolérance)
		return false
	end
	local s4 = (p4 - p1):Dot(ud)
	local s3 = (p3 - p1):Dot(ud)
	local hv = (p4 - p1) - ud * s4
	if hv.Magnitude < 0.02 then
		return false
	end
	-- (v10) éclats de triangle minuscules (< SLIVER) : le bloc déborde un
	-- peu à la place (invisible, 2 à 4 pièces de moins par quadrilatère)
	local SLIVER = 0.08
	local a0 = if s4 > SLIVER then s4 elseif s4 < -SLIVER then 0 else math.min(0, s4)
	local a1 = if s3 < len - SLIVER then s3 elseif s3 > len + SLIVER then len else math.max(len, s3)
	if a1 - a0 < 0.02 then
		return false
	end
	local q1, q2 = p1 + ud * a0, p1 + ud * a1
	rect(b, name, q1, q2, q1 + hv, color, material, thick, ref)
	if s4 > SLIVER then
		tri(b, name, p1, q1, p4, color, material, thick, ref)
	elseif s4 < -SLIVER then
		tri(b, name, p1, p4, p1 + hv, color, material, thick, ref)
	end
	if s3 < len - SLIVER then
		tri(b, name, p2, q2, p3, color, material, thick, ref)
	elseif s3 > len + SLIVER then
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
	noseRoll: number,
	tailRoll: number,
	planX: (number) -> number,
	flankTop: (number) -> number,
	topY: (number) -> number,
	topE: (number) -> number,
	crown: (number) -> number,
	p2: (number) -> (number, number),
	ref: (number) -> Vector3,
}

-- c = bombé du dessus (le milieu est à t + c : capot, toit, vitres galbés)
type St = { z: number, t: number, e: number, bx: number, by: number, fx: number, fy: number, c: number }

local function lerp(a: number, c: number, u: number): number
	return a + (c - a) * u
end

local function makeGeo(s: Spec, lod: number?): Geo
	local g = {} :: any
	local hw = s.W / 2
	g.zF, g.zB = -s.L / 2, s.L / 2
	g.r = s.WheelD / 2
	-- (v10) jour de roue plus serré (arches collées au pneu, plus réaliste)
	g.ra = g.r + 0.14
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
	-- (v10) nez et poupe ARRONDIS de profil : le capot plonge en quart de
	-- cercle vers le bouclier, le coffre / hayon retombe vers le pare-chocs
	g.noseRoll = math.clamp(g.hoodF - g.noseLow - 0.16, 0, 0.34)
	g.tailRoll = if pickup then 0 else math.clamp(s.Deck - s.Low - 0.18, 0, 0.3)

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
	-- dessus du flanc vertical (aile qui plonge vers le nez)
	function g.flankTop(z: number): number
		local n2 = zF + g.noseR
		if z <= n2 then
			return g.noseLow
		elseif z < g.aF0 then
			local u = (z - n2) / math.max(0.01, g.aF0 - n2)
			return lerp(g.noseLow, s.Low, 1 - (1 - u) ^ 2)
		end
		return s.Low
	end
	-- ceinture (bas des vitres) dans l'habitacle
	local rise = if (lod or 3) >= 3 then s.BeltRise else 0 -- (Mid : ceinture droite, vitres rectangulaires)
	local function belt(z: number): number
		local u = math.clamp((z - s.Ws) / math.max(0.01, s.Rw - s.Ws), 0, 1)
		return lerp(s.Belt - rise / 2, s.Belt + rise / 2, u)
	end
	-- arrondi (quart de cercle) : 1 au bord, 0 à `len` du bord
	local function roll(d: number, len: number): number
		local u = math.clamp(d / math.max(0.05, len), 0, 1)
		return 1 - math.sin(u * PI / 2)
	end
	-- dessus (axe) : capot, auvent, pare-brise, toit bombé, lunette, coffre
	function g.topY(z: number): number
		local wsC = s.Ws - g.cowl
		if z <= wsC then
			local u = math.clamp((z - zF) / math.max(0.01, wsC - zF), 0, 1)
			return g.hoodF + (s.HoodR - 0.03 - g.hoodF) * (1 - (1 - u) ^ 2) - g.noseRoll * roll(z - zF, g.noseR * 0.9)
		elseif z <= s.Ws then
			return s.HoodR
		elseif z <= s.R0 then
			-- pare-brise légèrement galbé (plus raide en haut)
			local u = (z - s.Ws) / math.max(0.01, s.R0 - s.Ws)
			return lerp(s.HoodR + 0.06, s.Roof - 0.04, u + 0.12 * u * (1 - u))
		elseif sports and z < s.Rw then
			return belt(z) -- cockpit ouvert
		elseif pickup and z > s.R1 + 0.01 then
			return s.Deck -- benne ouverte
		elseif z <= s.R1 then
			return s.Roof - 0.04
		elseif z <= s.Rw then
			local u = (z - s.R1) / math.max(0.01, s.Rw - s.R1)
			return lerp(s.Roof - 0.04, s.Deck, u - 0.1 * u * (1 - u))
		end
		local u = (z - s.Rw) / math.max(0.01, zB - s.Rw)
		return s.Deck - 0.08 * u * u - g.tailRoll * roll(zB - z, g.tailR * 0.9)
	end
	-- demi-largeur du dessus (capot, toit, coffre) : le bord du bombé
	function g.topE(z: number): number
		local e = hw - s.Inset
		if sports and z < s.Ws - g.cowl then
			e = hw - 1.0
		elseif sports and z >= s.R0 and z < s.Rw then
			e = hw - s.Tumble
		elseif pickup and z > s.R1 + 0.01 then
			e = g.planX(z) - 0.1
		elseif z < s.Ws or z > s.Rw then
			-- capot / coffre plus larges que le toit (épaules pleines)
			e = hw - s.Inset * 0.72
		end
		return math.min(e, g.planX(z) - 0.1 - (if pickup and z > s.R1 + 0.01 then 0 else 0.36))
	end
	-- bombé au milieu du dessus
	function g.crown(z: number): number
		if sports and z >= s.R0 and z < s.Rw then
			return 0
		elseif pickup and z > s.R1 + 0.01 then
			return 0
		elseif z < s.Ws - g.cowl then
			return if z - zF < 0.05 then 0.02 else 0.09
		elseif z < s.Ws then
			return 0.05
		elseif z < s.R0 then
			return 0.08
		elseif z <= s.R1 then
			return 0.13
		elseif z <= s.Rw then
			return 0.08
		end
		return if zB - z < 0.05 then 0.02 else 0.07
	end
	-- épaule / ceinture (x, y) : arête de l'aile, bas des vitres
	function g.p2(z: number): (number, number)
		local px = g.planX(z)
		local t = g.topY(z)
		if z < s.Ws then
			if sports then
				return px - 0.2, t + 0.16 -- ailes plus hautes que le capot
			end
			-- (v10) épaule arrondie : l'arête descend moins près du nez
			return px - 0.04, t - math.min(0.24, (t - g.flankTop(z)) * 0.55)
		elseif pickup and z > s.R1 + 0.01 then
			return px - 0.1, s.Deck
		elseif z <= s.Rw then
			return math.min(hw - s.Tumble, px - 0.13), belt(z)
		end
		return px - 0.04, t - math.min(0.24, (t - g.flankTop(z)) * 0.55)
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
	-- coins arrondis : une section intermédiaire (45°) en "Full"
	local angles = if lod >= 3 then { PI / 4 } else {}
	for _, a in ipairs(angles) do
		add(g.zF + g.noseR * (1 - math.cos(a)), 1)
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
	for _, a in ipairs(angles) do
		add(g.zB - g.tailR * (1 - math.cos(a)), 1)
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
		table.insert(out, { z = z, t = g.topY(z), e = g.topE(z), bx = bx, by = by, fx = g.planX(z), fy = g.flankTop(z), c = if lod >= 3 then g.crown(z) else 0 })
	end
	return out
end

-- Section interpolée en z (montants, joints)
local function sectionAt(st: { St }, z: number): St
	for i = 1, #st - 1 do
		local a, c = st[i], st[i + 1]
		if z >= a.z and z <= c.z then
			local u = (z - a.z) / math.max(1e-4, c.z - a.z)
			return { z = z, t = lerp(a.t, c.t, u), e = lerp(a.e, c.e, u), bx = lerp(a.bx, c.bx, u), by = lerp(a.by, c.by, u), fx = lerp(a.fx, c.fx, u), fy = lerp(a.fy, c.fy, u), c = lerp(a.c, c.c, u) }
		end
	end
	return if z < st[1].z then st[1] else st[#st]
end

-- (v10) hauteur du dessus BOMBÉ à l'abscisse x (Mid / Low : plat)
local function topAt(S: St, x: number): number
	return S.t + S.c * math.max(0, 1 - math.abs(x) / math.max(0.05, S.e))
end

----------------------------------------------------------------------
-- Roues
----------------------------------------------------------------------

-- (v10) Design = dessin de jante (Config.Cars.Mods.Rims), Tyre = style de pneu
type WheelLook = { Rim: Color3, Dish: Color3, Cap: Color3, Caliper: Color3, Spokes: number, Design: string, Tyre: string }

local WHITEWALL = Color3.fromRGB(240, 238, 232)

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
	local tyre = look.Tyre
	local design = look.Design
	-- pneu taille basse : jante plus grande, flanc plus fin
	local rimK = if tyre == "LowProfile" then 0.76 else 0.66
	if lod <= 1 then
		layer("Rim", 0.05, 0.1, D * (rimK - 0.04), look.Rim, M.Metal)
		b.WheelTag = nil
		b.Spin = nil
		return
	end
	if lod == 2 then
		if tyre == "Whitewall" then
			layer("Whitewall", 0.03, 0.06, D * 0.84, WHITEWALL, M.Rubber)
		end
		layer("Rim", 0.07, 0.1, D * (rimK - 0.04), look.Rim, M.Metal)
		-- une barre sombre à travers la jante : on voit la roue tourner
		boxRotX(b, "Spoke", face + side * 0.1, r, z, 0.06, D * 0.12, D * (rimK - 0.16), 0, look.Dish, M.Metal)
		b.WheelTag = nil
		b.Spin = nil
		return
	end
	layer("Sidewall", 0.04, 0.1, D - 0.12, SIDEWALL, M.Rubber)
	-- flanc décoré
	if tyre == "Whitewall" then
		layer("Whitewall", 0.06, 0.04, D * 0.84, WHITEWALL, M.Rubber)
	elseif tyre == "RedLine" then
		layer("RedLine", 0.06, 0.04, D * 0.86, CAL_RED, M.Rubber)
		layer("Sidewall", 0.07, 0.03, D * 0.81, SIDEWALL, M.Rubber)
	elseif tyre == "OffRoad" then
		-- pneu tout-terrain : pavés de la bande de roulement
		for k = 0, 7 do
			local a = (k + 0.5) / 8 * 2 * PI
			boxRotX(b, "Tread", x, r + math.cos(a) * (r - 0.03), z + math.sin(a) * (r - 0.03), tw + 0.06, 0.16, D * 0.2, a, TYRE, M.Rubber)
		end
	end
	local deep = design == "DeepDish"
	-- lèvre (plus large et polie pour la jante "Deep dish"), voile, disque
	-- ("Deep dish" : large lèvre polie, petit voile sombre au centre)
	layer("RimLip", 0.1, 0.1, D * rimK, look.Rim, M.Metal).Reflectance = if deep then 0.4 else 0.25
	layer("RimDish", 0.14, 0.1, D * (rimK - (if deep then 0.2 else 0.08)), look.Dish, M.Metal)
	layer("BrakeDisc", 0.18, 0.1, D * (if deep then rimK - 0.3 else rimK * 0.66), DISC, M.Metal)
	-- étrier (braque sans tourner)
	b.Spin = false
	local ca = math.rad(40)
	local cr = D * (if deep then rimK - 0.3 else rimK * 0.66) * 0.36
	boxRotX(b, "Caliper", face + side * 0.195, r + math.cos(ca) * cr, z + math.sin(ca) * cr, 0.05, D * 0.1, D * 0.2, ca, look.Caliper)
	b.Spin = true
	-- rayons : rayon intérieur r0, extérieur r1 (sous la lèvre), largeur w,
	-- torsion (angle entre le pied et la tête du rayon : jantes "turbine", "mesh")
	local out = 0.235
	local r1 = D * (rimK / 2 - 0.02)
	local function spoke(a: number, r0: number, rEnd: number, w: number, twist: number)
		local y0, z0 = math.cos(a) * r0, math.sin(a) * r0
		local y1, z1 = math.cos(a + twist) * rEnd, math.sin(a + twist) * rEnd
		local dy, dz = y1 - y0, z1 - z0
		local len = math.sqrt(dy * dy + dz * dz)
		if len < 0.05 then
			return
		end
		boxRotX(b, "Spoke", face + side * out, r + (y0 + y1) / 2, z + (z0 + z1) / 2, 0.05, w, len, math.atan2(dz, dy) - PI / 2, look.Rim, M.Metal)
	end
	if design == "Retro" then
		-- enjoliveur plein (rétro) : disque, jonc, moyeu
		layer("Hubcap", 0.2, 0.06, D * (rimK - 0.1), look.Rim, M.Metal).Reflectance = 0.35
		layer("HubcapRing", 0.25, 0.04, D * (rimK - 0.24), look.Dish, M.Metal)
	elseif design == "Mesh" then
		for k = 0, 7 do
			local a = k / 8 * 2 * PI
			spoke(a, D * 0.08, r1, D * 0.032, 0.42)
			spoke(a, D * 0.08, r1, D * 0.032, -0.42)
		end
	elseif design == "Split" then
		for k = 0, 5 do
			local a = k / 6 * 2 * PI
			spoke(a - 0.1, D * 0.08, r1, D * 0.04, 0.05)
			spoke(a + 0.1, D * 0.08, r1, D * 0.04, -0.05)
		end
	elseif design == "Turbine" then
		for k = 0, 9 do
			spoke(k / 10 * 2 * PI, D * 0.08, r1, D * 0.075, 0.55)
		end
	elseif design == "Star" then
		for k = 0, 2 do
			spoke(k / 3 * 2 * PI, D * 0.06, r1, D * 0.17, 0)
		end
	elseif design == "Sport" then
		for k = 0, 4 do
			spoke(k / 5 * 2 * PI, D * 0.08, r1, D * 0.1, 0.12)
		end
	elseif deep then
		for k = 0, 4 do
			spoke(k / 5 * 2 * PI, D * 0.06, D * (rimK / 2 - 0.1), D * 0.08, 0)
		end
	else
		-- jante d'origine du modèle (look.Spokes rayons droits)
		local n = look.Spokes
		for k = 0, n - 1 do
			spoke(k / n * 2 * PI, D * 0.08, r1, if n >= 10 then D * 0.045 else D * 0.075, 0)
		end
	end
	layer("HubCap", 0.3, 0.08, D * 0.18, look.Cap, M.Metal)
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
		box(b, "Cockpit", -hw + 0.4, hw - 0.4, low, s.Belt + 0.04, s.R0, s.R1, TRIM) -- (v9.9) dessus 0,04 au-dessus de la caisse : plus de z-fight
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
	-- (v10, CARS10) options de l'atelier (Config.Cars.Mods ; inconnues ignorées)
	local mods = CarModels.CleanMods(options.Mods)
	local function mod(kindName: string): string
		return CarModels.ModOf(mods, kindName)
	end
	local finish = mod("Finish")
	paint = finishColor(paint, finish)
	local tint = TINTS[mod("Tint")] or TINTS.Clear
	local b: B = {
		Model = model,
		S = scale,
		Count = 0,
		Paint = paint,
		Gloss = (FINISH_GLOSS[finish] or FINISH_GLOSS.Gloss)[lod],
		Lod = lod,
		PaintMat = if finish == "Matte" then M.Plastic else nil,
		GlassColor = tint[1],
		GlassT = tint[2],
	}
	local g = makeGeo(s, lod)
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
	elseif style == "City" then
		-- (v9.9) toit bicolore de citadine (blanc ou graphite selon la teinte)
		roofColor = contrast
	elseif (style == "Hatch" or style == "SUV") and lum > 0.22 then
		roofColor = Color3.fromRGB(34, 35, 42) -- toit noir brillant
	end
	-- (v10) toit bicolore choisi à l'atelier
	local roofMat = M.SmoothPlastic
	local roofMod = mod("Roof")
	if roofMod == "Body" then
		roofColor = paint
	elseif roofMod == "Carbon" then
		roofColor = Color3.fromRGB(30, 31, 36)
		roofMat = M.Fabric -- (tissage : effet fibre de carbone)
	elseif roofMod ~= "Auto" and Config.CarColorsById and Config.CarColorsById[roofMod] then
		roofColor = finishColor(Config.CarColorsById[roofMod].Color, finish)
	end
	-- (v10) sellerie
	local interior = Config.CarModsById and Config.CarModsById.Interior and Config.CarModsById.Interior[mod("Interior")]
	local seatCol = interior and interior.Color or SEAT
	local seatCol2 = seatCol:Lerp(Color3.new(1, 1, 1), 0.12)
	-- jantes par modèle
	local look: WheelLook = { Rim = CHROME, Dish = GRAPHITE, Cap = CHROME, Caliper = CAL_DARK, Spokes = 5, Design = "Stock", Tyre = "Road" }
	if style == "Bubble" then
		look = { Rim = WHITE, Dish = Color3.fromRGB(200, 202, 210), Cap = CHROME, Caliper = CAL_DARK, Spokes = 8, Design = "Stock", Tyre = "Road" }
	elseif sports then
		look = { Rim = GRAPHITE, Dish = HOUSING, Cap = CHROME, Caliper = CAL_RED, Spokes = 10, Design = "Stock", Tyre = "Road" }
	elseif style == "Limo" then
		look = { Rim = CHROME, Dish = GRAPHITE, Cap = GRAPHITE, Caliper = CAL_DARK, Spokes = 10, Design = "Stock", Tyre = "Road" }
	elseif offroad then
		look = { Rim = Color3.fromRGB(190, 194, 202), Dish = GRAPHITE, Cap = GRAPHITE, Caliper = CAL_DARK, Spokes = 6, Design = "Stock", Tyre = "Road" }
	elseif style == "Van" then
		look = { Rim = WHITE, Dish = Color3.fromRGB(190, 192, 200), Cap = CHROME, Caliper = CAL_DARK, Spokes = 5, Design = "Stock", Tyre = "Road" }
	elseif style == "Hatch" then
		look = { Rim = CHROME, Dish = HOUSING, Cap = GRAPHITE, Caliper = CAL_RED, Spokes = 5, Design = "Stock", Tyre = "Road" }
	end
	-- (v10) jantes, couleur des jantes, pneus de l'atelier
	look.Design = mod("Rims")
	look.Tyre = mod("Tyre")
	local rimMod = mod("RimColor")
	if rimMod == "Body" then
		look.Rim = paint
	elseif rimMod ~= "Auto" then
		local entry = Config.CarModsById and Config.CarModsById.RimColor and Config.CarModsById.RimColor[rimMod]
		if entry and typeof(entry.Color) == "Color3" then
			look.Rim = entry.Color
			look.Cap = if rimMod == "Chrome" then GRAPHITE else CHROME
		end
	end
	if look.Design == "Turbine" or look.Design == "Mesh" then
		look.Dish = HOUSING
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
				if style == "Van" then
					topCol = roofColor -- (combi bicolore : capot blanc)
					b1Col = roofColor
				end
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
				topCol, topMat = roofColor, roofMat
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
			if not skipTop and (A.c > 0.005 or C.c > 0.005) then
				-- (v10) dessus BOMBÉ : deux pans qui se rejoignent au milieu
				for _, sx in ipairs({ -1, 1 }) do
					quad(b, "Top", V3(0, A.t + A.c, A.z), V3(sx * A.e, A.t, A.z), V3(sx * C.e, C.t, C.z), V3(0, C.t + C.c, C.z), topCol, topMat, th, ref)
				end
			elseif not skipTop then
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
		local archN = if full then 4 else 3
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
				-- protections noires d'arches des tout-terrain
				if full and offroad then
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
			-- (v9.9) ligne de caractère : arête ombrée entre le flanc et l'épaule
			rod(b, "Crease", V3(sx * hw, s.Low - 0.03, if sports then g.aF0 else zF + g.noseR), V3(sx * hw, s.Low - 0.03, zB - g.tailR), 0.07, paint:Lerp(Color3.new(0, 0, 0), 0.3))
			-- bas de caisse (noir) entre les roues
			if full and mod("Skirts") == "None" then
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
		-- ░ avant (v9.9 passe visuelle) : un VRAI visage, en couches
		-- espacées de ≥ 0,04 (aucun z-fighting) : jupe noire + prise d'air
		-- + antibrouillards cerclés + lame argent, plaque sur le bouclier,
		-- calandre (cadre chromé, grille, barres, logo), blocs optiques
		-- (cerclage chromé, boîtier noir, projecteurs, feu de jour en L,
		-- glace claire, retour sur l'angle, répétiteur) ░
		----------------------------------------------------------------
		local fy = g.noseLow
		local N0 = st[1]
		local N1 = if st[2] and st[2].z < zF + g.noseR - 0.01 then st[2] else nil
		local round = style == "Bubble" or style == "Van"
		-- (v10) bouclier moderne : jupe basse noire + grande prise d'air
		-- (maille), plaque sur le bouclier peint, antibrouillards sans chrome
		local valTop = g.sill + (if sports then 0.4 elseif round then 0.55 else 0.44)
		box(b, "Valance", -nfx + 0.08, nfx - 0.08, g.sill - 0.05, valTop, zF - 0.06, zF + 0.1, TRIM, M.Plastic)
		if full and style ~= "SUV" then
			box(b, "SkidStrip", -nfx + 0.35, nfx - 0.35, g.sill + 0.03, g.sill + 0.1, zF - 0.1, zF - 0.02, GRAPHITE, M.Metal).Reflectance = 0.2
		end
		local iw = math.min(if sports then s.W * 0.32 else s.W * 0.26, nfx - 0.7)
		box(b, "Intake", -iw, iw, g.sill + 0.14, valTop - 0.06, zF - 0.1, zF + 0.05, HOUSING, M.DiamondPlate)
		if full then
			local iy = (g.sill + 0.14 + valTop - 0.06) / 2
			box(b, "IntakeBar", -iw + 0.06, iw - 0.06, iy - 0.025, iy + 0.025, zF - 0.14, zF + 0.02, GRAPHITE, M.Metal)
			for _, sx in ipairs({ -1, 1 }) do
				local fx = sx * math.min(iw + 0.36, nfx - 0.3)
				local fyL = (g.sill + valTop) / 2 + 0.02
				cylZ(b, "FogRing", fx, fyL, zF - 0.07, 0.06, 0.3, if round then CHROME else GRAPHITE, M.Metal)
				cylZ(b, "FogLight", fx, fyL, zF - 0.11, 0.06, 0.2, LAMP, M.SmoothPlastic)
			end
		end
		if round then
			plate(b, "PlateFront", zF - 0.05, math.max(valTop + 0.26, math.min(valTop + 0.3, fy - 0.9)), -1, full, nil)
			-- phares ronds rétro (cerclage chromé, boîtier, lampe, point de feu de jour)
			local d = if style == "Van" then 0.95 else 1.0
			local ly = if style == "Van" then fy - 0.35 else fy - 0.3
			for _, sx in ipairs({ -1, 1 }) do
				local x = sx * (nfx - 0.62)
				cylZ(b, "HeadlightRim", x, ly, zF - 0.05, 0.14, d, CHROME, M.Metal)
				cylZ(b, "Headlight", x, ly, zF - 0.13, 0.06, d - 0.2, LAMP, M.SmoothPlastic).Reflectance = 0.15
				if full then
					cylZ(b, "HeadlightDot", x, ly, zF - 0.18, 0.06, d * 0.32, DRL, M.SmoothPlastic)
					local lens = cylZ(b, "HeadlightLens", x, ly, zF - 0.23, 0.04, d - 0.14, LENS, M.Glass)
					lens.Transparency = 0.7
					lens.Reflectance = 0.3
					cylZ(b, "Indicator", sx * (nfx - 0.12), ly - 0.6, zF - 0.04, 0.1, 0.26, AMBER, M.SmoothPlastic):SetAttribute("Side", sx)
				end
			end
			-- pare-chocs chromé rétro (barre) + calandre "sourire"
			if full then
				cylX(b, "BumperBar", 0, valTop - 0.06, zF - 0.14, nfx * 2 - 0.3, 0.26, CHROME, M.Metal).Reflectance = 0.3
				for _, sx in ipairs({ -1, 1 }) do
					box(b, "BumperGuard", sx * 0.95 - 0.08, sx * 0.95 + 0.08, valTop - 0.2, valTop + 0.35, zF - 0.24, zF - 0.1, CHROME, M.Metal)
				end
			end
			if style == "Van" then
				-- grand logo rond sur la face avant blanche (bicolore)
				local uy0 = ly + 0.45
				if N0.t - 0.05 - uy0 > 0.12 then
					box(b, "FrontUpper", -N0.e, N0.e, uy0, N0.t - 0.05, zF - 0.04, zF + 0.08, roofColor)
				end
				if full then
					cylZ(b, "Badge", 0, ly + 0.3, zF - 0.06, 0.06, 0.62, CHROME, M.Metal)
					cylZ(b, "BadgeCore", 0, ly + 0.3, zF - 0.1, 0.04, 0.4, roofColor, M.SmoothPlastic)
				end
			elseif full then
				-- petite calandre chromée "sourire" + logo
				box(b, "GrilleFrame", -0.7, 0.7, fy - 0.72, fy - 0.44, zF - 0.05, zF + 0.05, CHROME, M.Metal)
				box(b, "Grille", -0.62, 0.62, fy - 0.67, fy - 0.49, zF - 0.09, zF + 0.04, HOUSING, M.DiamondPlate)
				cylZ(b, "Badge", 0, fy - 0.2, zF - 0.05, 0.06, 0.3, CHROME, M.Metal)
			end
		else
			-- (v10) blocs optiques MODERNES : fins, hauts, étirés jusque dans
			-- l'angle arrondi ; boîtier fumé, 2 projecteurs, sourcil de feu de
			-- jour sur toute la largeur, glace claire, répétiteur ; pas de chrome
			local lh = if sports then 0.34 elseif pickup then 0.6 elseif offroad then 0.52 elseif style == "Limo" then 0.46 else 0.42
			local ly1 = fy + math.max(0.04, math.min(0.12, (N0.t - fy) * 0.5))
			local ly0 = ly1 - lh
			local lw = if sports then s.W * 0.22 else s.W * 0.2
			local xi = math.max(nfx - lw, 0.55)
			for _, sx in ipairs({ -1, 1 }) do
				local hx0, hx1 = sx * xi, sx * (nfx - 0.02)
				local lo, hi = math.min(hx0, hx1), math.max(hx0, hx1)
				box(b, "HeadlightHousing", lo, hi, ly0, ly1, zF - 0.07, zF + 0.08, HOUSING)
				if full then
					local width = hi - lo
					local two = width >= 0.9
					local pd = math.min(0.3, lh - 0.14, if two then width * 0.3 else width * 0.5)
					local py = ly0 + (lh - 0.08) / 2
					for _, f in ipairs(if two then { 0.3, 0.68 } else { 0.5 }) do
						local px = lerp(sx * xi, sx * nfx, f)
						cylZ(b, "ProjectorRing", px, py, zF - 0.1, 0.04, pd + 0.08, GRAPHITE, M.Metal)
						cylZ(b, "Projector", px, py, zF - 0.14, 0.04, pd, LAMP, M.SmoothPlastic).Reflectance = 0.2
					end
					-- sourcil de feu de jour (haut du bloc)
					box(b, "HeadlightDRL", lo + 0.04, hi - 0.03, ly1 - 0.1, ly1 - 0.03, zF - 0.13, zF - 0.05, DRL)
					local lens = box(b, "HeadlightLens", lo - 0.01, hi + 0.01, ly0 - 0.01, ly1 + 0.01, zF - 0.2, zF - 0.17, LENS, M.Glass)
					lens.Transparency = 0.8
					lens.Reflectance = 0.3
					local ind = box(b, "Indicator", if sx > 0 then hi - 0.3 else lo + 0.06, if sx > 0 then hi - 0.06 else lo + 0.3, ly0 + 0.05, ly0 + 0.14, zF - 0.13, zF - 0.05, AMBER)
					ind:SetAttribute("Side", sx)
					-- l'optique continue dans l'angle arrondi (boîtier + filet de feu de jour)
					if N1 then
						local dx, dz = N1.fx - N0.fx, N1.z - zF
						local nrm = V3(sx * dz, 0, -dx)
						local ym = (ly0 + ly1) / 2
						local a0 = V3(sx * (N0.fx - 0.01), ym, zF + 0.01)
						local c0 = V3(sx * (N1.fx - 0.03), ym, N1.z - 0.01)
						strip(b, "HeadlightWrap", a0, c0, nrm, lh, 0.08, HOUSING, M.SmoothPlastic, 0.04)
						strip(b, "HeadlightWrapDRL", a0 + V3(0, lh * 0.5 - 0.065, 0), c0 + V3(0, lh * 0.5 - 0.065, 0), nrm, 0.07, 0.06, DRL, M.SmoothPlastic, 0.1)
					end
				else
					box(b, "Headlight", lo + 0.05, hi - 0.05, ly0 + 0.05, ly1 - 0.05, zF - 0.11, zF - 0.03, LAMP, M.SmoothPlastic)
				end
			end
			-- calandre entre les phares : cadre, maille, barres, logo
			local gw = if sports then 0 else xi - 0.12
			local gy0, gy1 = ly0 - 0.06, ly1 - 0.04
			if style == "Limo" then
				gy0 = ly0 - 0.3
			elseif offroad then
				gy0, gy1 = ly0 - 0.34, ly1 + 0.02
			end
			if gw > 0.2 then
				local frameCol = if offroad or style == "Limo" or style == "City" then CHROME else GRAPHITE
				box(b, "GrilleFrame", -gw, gw, gy0, gy1, zF - 0.05, zF + 0.1, frameCol, M.Metal).Reflectance = 0.2
				box(b, "Grille", -gw + 0.07, gw - 0.07, gy0 + 0.06, gy1 - 0.06, zF - 0.09, zF + 0.05, HOUSING, M.DiamondPlate)
				if full then
					if style == "Limo" then
						for k = -4, 4 do
							local x = k * gw / 5
							box(b, "GrilleBar", x - 0.03, x + 0.03, gy0 + 0.06, gy1 - 0.06, zF - 0.13, zF - 0.03, CHROME, M.Metal)
						end
					else
						for k = 1, 2 do
							local y = gy0 + (gy1 - gy0) * k / 3
							box(b, "GrilleBar", -gw + 0.09, gw - 0.09, y - 0.025, y + 0.025, zF - 0.13, zF - 0.03, if offroad or style == "City" then CHROME else GRAPHITE, M.Metal)
						end
					end
					cylZ(b, "Badge", 0, (gy0 + gy1) / 2, zF - 0.16, 0.05, 0.32, CHROME, M.Metal)
					cylZ(b, "BadgeCore", 0, (gy0 + gy1) / 2, zF - 0.2, 0.04, 0.2, Color3.fromRGB(40, 80, 190), M.SmoothPlastic)
				end
			elseif full then
				-- roadster : pas de calandre, logo sur le museau
				cylZ(b, "Badge", 0, ly1 - 0.08, zF - 0.04, 0.05, 0.3, CHROME, M.Metal)
			end
			-- plaque sur le bouclier peint, entre la calandre et la prise d'air
			local py = math.clamp((valTop + gy0) / 2, valTop + 0.25, math.max(valTop + 0.25, gy0 - 0.25))
			plate(b, "PlateFront", zF - 0.05, py, -1, full, nil)
		end
		-- bas de caisse avant : Mid → phares simples déjà posés

		----------------------------------------------------------------
		-- ░ arrière : feux (cerclage, glace, barres intérieures, recul,
		-- clignotant, retour sur l'angle), jupe noire + catadioptres,
		-- échappements, plaque, jonc chromé, logo ░
		----------------------------------------------------------------
		local T0 = st[#st]
		local T1 = if st[#st - 1] and st[#st - 1].z > zB - g.tailR + 0.01 then st[#st - 1] else nil
		local tfy = T0.fy
		local tailTop = math.min(tfy + math.max(0.05, (T0.by - tfy) * 0.6), T0.t - 0.08)
		-- (v10) feux fins et étirés (jusque dans l'angle arrondi)
		local tailBot = tailTop - (if sports then 0.36 elseif style == "Bubble" then 0.52 else 0.44)
		local tailIn = math.max(0.7, tfx - s.W * 0.2)
		if pickup then
			tailBot, tailTop = s.Low - 0.3, s.Deck - 0.35
		elseif style == "Van" then
			tailBot, tailTop = tfy - 0.25, tfy + 0.55
		end
		local rValTop = g.sill + 0.5
		for _, sx in ipairs({ -1, 1 }) do
			local tx0, tx1 = sx * (if pickup then tfx - 0.6 elseif style == "Van" then s.W * 0.2 else tailIn), sx * (tfx - 0.04)
			local lo, hi = math.min(tx0, tx1), math.max(tx0, tx1)
			if full then
				box(b, "TailBezel", lo - 0.05, hi + 0.04, tailBot - 0.05, tailTop + 0.04, zB - 0.1, zB + 0.03, HOUSING)
			end
			box(b, "Taillight", lo, hi, tailBot, tailTop, zB - 0.1, zB + 0.07, TAIL, M.SmoothPlastic)
			if full then
				-- barres lumineuses intérieures (en C) + recul + clignotant
				box(b, "TailBar", lo + 0.07, hi - 0.07, tailTop - 0.17, tailTop - 0.1, zB + 0.03, zB + 0.11, TAIL_IN, M.SmoothPlastic)
				local vx0, vx1 = if sx > 0 then hi - 0.14 else lo + 0.07, if sx > 0 then hi - 0.07 else lo + 0.14
				if tailTop - 0.17 - (tailBot + 0.26) > 0.08 then
					box(b, "TailBar", vx0, vx1, tailBot + 0.26, tailTop - 0.17, zB + 0.03, zB + 0.11, TAIL_IN, M.SmoothPlastic)
				end
				local rv0, rv1 = if sx > 0 then lo + 0.07 else hi - 0.4, if sx > 0 then lo + 0.4 else hi - 0.07
				box(b, "ReverseLight", rv0, rv1, tailBot + 0.06, tailBot + 0.22, zB + 0.03, zB + 0.11, REVERSE, M.SmoothPlastic)
				local ind = box(b, "RearIndicator", if sx > 0 then hi - 0.38 else lo + 0.07, if sx > 0 then hi - 0.07 else lo + 0.38, tailBot + 0.06, tailBot + 0.22, zB + 0.03, zB + 0.11, AMBER)
				ind:SetAttribute("Side", sx)
				local wTop = math.min(tailTop, tfy - 0.04)
				if T1 and not pickup and wTop - tailBot > 0.2 then
					local a0 = V3(sx * (T0.fx - 0.01), (tailBot + wTop) / 2, zB - 0.01)
					local c0 = V3(sx * (T1.fx - 0.03), (tailBot + wTop) / 2, T1.z + 0.01)
					local dx, dz = T1.fx - T0.fx, zB - T1.z
					local nrm = V3(sx * dz, 0, dx)
					strip(b, "TailWrap", a0, c0, nrm, wTop - tailBot, 0.08, TAIL, M.SmoothPlastic, 0.04)
					strip(b, "TailWrapBar", a0 + V3(0, (wTop - tailBot) * 0.5 - 0.1, 0), c0 + V3(0, (wTop - tailBot) * 0.5 - 0.1, 0), nrm, 0.07, 0.06, TAIL_IN, M.SmoothPlastic, 0.1)
				end
				-- catadioptre rouge au coin de la jupe
				local cx0, cx1 = sx * (tfx - 0.45), sx * (tfx - 0.2)
				box(b, "Reflector", math.min(cx0, cx1), math.max(cx0, cx1), g.sill + 0.15, g.sill + 0.27, zB + 0.04, zB + 0.1, TAIL, M.SmoothPlastic)
			end
		end
		if full and (style == "City" or style == "Hatch" or style == "SUV" or style == "Limo") then
			local bw = tailIn - 0.06
			box(b, "TailLightBar", -bw, bw, tailTop - 0.14, tailTop - 0.08, zB - 0.02, zB + 0.1, TAIL_IN, M.SmoothPlastic)
			box(b, "TailBlack", -bw + 0.05, bw - 0.05, tailTop - 0.2, tailTop, zB - 0.05, zB + 0.045, HOUSING)
		end
		-- jupe arrière noire (diffuseur) sur toute la largeur
		box(b, "Diffuser", -tfx + 0.08, tfx - 0.08, g.sill - 0.05, rValTop, zB - 0.06, zB + 0.06, TRIM, M.Plastic)
		plate(b, "PlateRear", zB + 0.05, rValTop + 0.3, 1, full, options.Plate)
		if full and not sports and not pickup then
			-- jonc chromé au-dessus de la plaque
			box(b, "TrunkChrome", -0.95, 0.95, rValTop + 0.6, rValTop + 0.66, zB - 0.02, zB + 0.05, CHROME, M.Metal)
		end
		local twin = sports or style == "Hatch" or style == "Limo"
		for _, sx in ipairs(if twin then { -1, 1 } else { 1 }) do
			cylZ(b, "Exhaust", sx * s.W * 0.3, g.sill + 0.18, zB + 0.12, 0.34, 0.28, CHROME, M.Metal).Reflectance = 0.3
			if full then
				cylZ(b, "ExhaustInner", sx * s.W * 0.3, g.sill + 0.18, zB + 0.26, 0.06, 0.18, HOUSING, M.SmoothPlastic)
			end
		end
		if full then
			cylZ(b, "BadgeRear", 0, math.min(tailTop + 0.12, T0.t - 0.14), zB + 0.03, 0.05, 0.26, CHROME, M.Metal)
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
					rod(b, "DripRail", V3(sx * (Ar.e + 0.06), Ar.t - 0.12, s.R0), V3(sx * (Rr.e + 0.06), Rr.t - 0.12, s.R1), 0.07, if style == "Limo" then CHROME else HOUSING, if style == "Limo" then M.Metal else M.SmoothPlastic)
					local endZ = if pickup then s.R1 - 0.05 else s.Rw - 0.05
					local Be = sectionAt(st, endZ)
					local chromeBelt = not pickup and style ~= "Van"
					rod(b, "BeltTrim", V3(sx * Aw.bx, Aw.by, s.Ws + 0.05), V3(sx * Be.bx, Be.by, endZ), 0.09, if chromeBelt then CHROME else HOUSING, if chromeBelt then M.Metal else M.SmoothPlastic)
					-- arête du toit arrondie (couleur du toit) au-dessus de la gouttière
					rod(b, "RoofEdge", V3(sx * (Ar.e - 0.02), Ar.t - 0.04, s.R0 + 0.05), V3(sx * (Rr.e - 0.02), Rr.t - 0.04, s.R1 - 0.05), 0.16, roofColor)
				end
			end
			if full then
				-- essuie-glaces posés sur le pare-brise
				local dy, dz = Ar.t - Aw.t, s.R0 - s.Ws
				local nrm = V3(0, dz, -dy).Unit * 0.05
				local cw = sectionAt(st, (s.Ws + s.R0) / 2).c
				local function onGlass(x: number, y: number): Vector3
					return V3(x, y, s.Ws + (y - Aw.t) / dy * dz) + nrm + V3(0, cw * math.max(0, 1 - math.abs(x) / math.max(0.1, Aw.e)), 0)
				end
				local ww = Aw.e * 2
				for _, x in ipairs({ -ww * 0.42, ww * 0.02 }) do
					rod(b, "Wiper", onGlass(x, Aw.t + 0.12), onGlass(x + ww * 0.36, Aw.t + 0.3), 0.06, GAP)
				end
				-- antenne requin
				if not pickup and style ~= "Van" then
					local Sa = sectionAt(st, s.R1 - 0.6)
					wedge(b, "Antenna", -0.1, 0.1, topAt(Sa, 0) - 0.02, topAt(Sa, 0) + 0.2, s.R1 - 1.0, s.R1 - 0.45, true, if roofColor == paint then paint else HOUSING)
				end
				-- essuie-glace arrière (hayon)
				if twoBox and s.Rw - s.R1 > 0.15 then
					local Rw2 = sectionAt(st, s.Rw)
					local rdy, rdz = Rr.t - Rw2.t, s.Rw - s.R1
					local rn = V3(0, rdz, rdy).Unit * 0.05
					local function onRear(x: number, u: number): Vector3
						local cr = lerp(Rw2.c, Rr.c, u) * math.max(0, 1 - math.abs(x) / math.max(0.1, Rr.e))
						return V3(x, lerp(Rw2.t, Rr.t, u) + cr, lerp(s.Rw, s.R1, u)) + rn
					end
					cylZ(b, "RearWiperPivot", 0, lerp(Rw2.t, Rr.t, 0.1) + lerp(Rw2.c, Rr.c, 0.1) + 0.05, lerp(s.Rw, s.R1, 0.1) + 0.08, 0.1, 0.16, GAP)
					rod(b, "RearWiper", onRear(0, 0.12), onRear(-Rr.e * 0.55, 0.62), 0.06, GAP)
				end
				-- 3e feu stop (haut du hayon)
				if twoBox then
					box(b, "BrakeLight3", -0.5, 0.5, Rr.t + Rr.c * 0.8 - 0.12, Rr.t + Rr.c * 0.8 - 0.04, s.R1 + 0.04, s.R1 + 0.14, TAIL, M.Glass)
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
				if mod("Spoiler") == "Stock" then
					wedge(b, "Ducktail", -hw + 0.8, hw - 0.8, s.Deck - 0.12, s.Deck + 0.08, zB - 1.3, zB - 0.4, true, paint)
				end
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
			ell(b, "Mirror", sx * (hw + 0.28), my, mz, 0.66, 0.44, 0.48, if style == "Hatch" or style == "SUV" or pickup then TRIM else paint)
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
					box(b, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), S.fy - 0.3, S.fy - 0.18, z - 0.3, z + 0.1, CHROME, M.Metal).Reflectance = 0.3
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
				box(b, "SeatCushion", x - w, x + w, top - 0.35, top, z - 0.75, z + 0.45, seatCol, M.Fabric)
				local backTop = math.min(top + 2.2, roofIn - 0.35)
				slab(b, "SeatBack", x, w * 2, top - 0.05, z + 0.62, backTop, z + 0.95, 0.34, seatCol, M.Fabric)
				if tall then
					box(b, "Headrest", x - 0.36, x + 0.36, backTop + 0.05, math.min(backTop + 0.5, roofIn - 0.05), z + 0.85, z + 1.15, seatCol2, M.Fabric)
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
				box(b, "VanBench", -wc + 0.1, wc - 0.1, seatTop - 0.35, seatTop, s.R1 - 2.6, s.R1 - 1.3, seatCol2, M.Fabric)
				slab(b, "VanBenchBack", 0, wc * 2 - 0.2, seatTop, s.R1 - 1.25, seatTop + 1.9, s.R1 - 0.95, 0.3, seatCol2, M.Fabric)
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
							strip(b, "Stripe", V3(x, topAt(prev, x) + 0.01, prev.z + 0.02), V3(x, topAt(S, x) + 0.01, S.z), V3(0, 1, 0), 0.4, 0.04, stripe :: Color3)
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
		elseif style == "Hatch" and mod("Spoiler") == "Stock" then
			local Rr = sectionAt(st, s.R1)
			box(b, "Spoiler", -Rr.e + 0.1, Rr.e - 0.1, Rr.t + Rr.c - 0.02, Rr.t + Rr.c + 0.1, s.R1 - 0.05, s.R1 + 0.5, GRAPHITE)
		elseif style == "SUV" then
			local R0s, R1s = sectionAt(st, s.R0 + 0.4), sectionAt(st, s.R1 - 0.4)
			for _, sx in ipairs({ -1, 1 }) do
				local x = sx * (R0s.e - 0.25)
				rod(b, "RoofRail", V3(x, topAt(R0s, x) + 0.12, R0s.z), V3(x, topAt(R1s, x) + 0.12, R1s.z), 0.16, HOUSING, M.Metal)
				if full then
					for _, zz in ipairs({ R0s.z, R1s.z }) do
						local Sz = sectionAt(st, zz)
						box(b, "RailFoot", x - 0.08, x + 0.08, topAt(Sz, x) - 0.02, topAt(Sz, x) + 0.1, zz - 0.15, zz + 0.15, HOUSING)
					end
				end
			end
			if full then
				box(b, "SkidPlate", -s.W * 0.28, s.W * 0.28, s.Clear - 0.06, g.sill + 0.12, zF - 0.12, zF + 0.5, CHROME, M.Metal)
				box(b, "SkidPlateR", -s.W * 0.25, s.W * 0.25, s.Clear - 0.06, g.sill + 0.12, zB - 0.5, zB + 0.12, CHROME, M.Metal)
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
			-- paroi arrière de la cabine = cadre autour de la lunette (on voit l'habitacle)
			local gx, cy0, cy1 = cw - 0.45, s.Deck + 0.35, s.Roof - 0.45
			box(b, "CabBack", -cw, cw, s.Deck, cy0, s.R1 - 0.02, s.R1 + 0.1, paint)
			box(b, "CabBack", -cw, cw, cy1, s.Roof - 0.12, s.R1 - 0.02, s.R1 + 0.1, paint)
			for _, sx in ipairs({ -1, 1 }) do
				box(b, "CabBack", math.min(sx * gx, sx * cw), math.max(sx * gx, sx * cw), cy0, cy1, s.R1 - 0.02, s.R1 + 0.1, paint)
			end
			box(b, "CabGlass", -gx - 0.05, gx + 0.05, cy0 - 0.05, cy1 + 0.05, s.R1 + 0.02, s.R1 + 0.06, GLASS, M.Glass)
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
					box(b, "RackBar", -Rr.e + 0.2, Rr.e - 0.2, s.Roof + Rr.c + 0.02, s.Roof + Rr.c + 0.2, z - 0.1, z + 0.1, HOUSING, M.Metal)
				end
				local boardL = math.min(s.R1 - s.R0 - 1.2, 7.2)
				local bc = (s.R0 + s.R1) / 2
				local surf = Color3.fromRGB(120, 220, 230)
				box(b, "Surfboard", -0.7, 0.7, s.Roof + Rr.c + 0.2, s.Roof + Rr.c + 0.34, bc - boardL / 2 + 0.7, bc + boardL / 2 - 0.4, surf)
				cylY(b, "SurfboardNose", 0, s.Roof + Rr.c + 0.27, bc - boardL / 2 + 0.7, 0.14, 1.4, surf)
				box(b, "SurfboardStripe", -0.1, 0.1, s.Roof + Rr.c + 0.34, s.Roof + Rr.c + 0.37, bc - boardL / 2 + 0.9, bc + boardL / 2 - 0.55, Color3.fromRGB(255, 150, 196))
				-- rail de porte coulissante
				local rx0, rx1 = hw - s.Inset + 0.02, hw - s.Inset + 0.1
				local Sr = sectionAt(st, s.R0 + 4)
				box(b, "SlideRail", rx0, rx1, Sr.by + 0.95, Sr.by + 1.02, s.R0 + 2.5, s.R0 + 6.1, HOUSING, M.Metal)
			end
		elseif style == "Limo" then
			if full then
				ell(b, "Ornament", 0, topAt(sectionAt(st, zF + 0.6), 0) + 0.12, zF + 0.6, 0.14, 0.3, 0.14, CHROME, M.Metal)
				for _, sx in ipairs({ -1, 1 }) do
					local cx0, cx1 = sx * (hw - 0.02), sx * (hw + 0.05)
					box(b, "ChromeSill", math.min(cx0, cx1), math.max(cx0, cx1), g.sill + 0.32, g.sill + 0.4, g.aF1 + 0.1, g.aR0 - 0.1, CHROME, M.Metal)
				end
			end
		end

		----------------------------------------------------------------
		-- ░ (v10, CARS10) KIT CARROSSERIE de l'atelier : lame avant, bas de
		-- caisse, aileron, néon sous caisse (Mid : aileron, bas de caisse,
		-- néon ; Full : tout) ░
		----------------------------------------------------------------
		local kitNfx = st[1].fx
		local splitter = mod("Splitter")
		if full and splitter ~= "None" then
			local race = splitter == "Race"
			local y0 = s.Clear - (if race then 0.06 else 0.02)
			local sp = box(b, "Splitter", -kitNfx + (if race then 0.05 else 0.2), kitNfx - (if race then 0.05 else 0.2), y0, s.Clear + 0.04, zF - (if race then 0.42 else 0.22), zF + 0.3, HOUSING, M.SmoothPlastic)
			sp.Reflectance = 0.1
			if race then
				-- dérives aux extrémités + ailettes (canards) sur les coins du bouclier
				for _, sx in ipairs({ -1, 1 }) do
					local x0, x1 = sx * (kitNfx - 0.05), sx * (kitNfx - 0.13)
					box(b, "SplitterFin", math.min(x0, x1), math.max(x0, x1), s.Clear + 0.04, s.Clear + 0.3, zF - 0.4, zF - 0.02, HOUSING)
					local cx0, cx1 = sx * (kitNfx - 0.1), sx * (kitNfx + 0.25)
					wedge(b, "Canard", math.min(cx0, cx1), math.max(cx0, cx1), g.sill + 0.5, g.sill + 0.62, zF - 0.02, zF + 0.5, true, HOUSING)
				end
			end
		end
		local skirts = mod("Skirts") == "Sport"
		if skirts then
			for _, sx in ipairs({ -1, 1 }) do
				local x0, x1 = sx * (hw - 0.06), sx * (hw + 0.1)
				box(b, "SideSkirt", math.min(x0, x1), math.max(x0, x1), g.sill - 0.12, g.sill + 0.34, g.aF1 + 0.06, g.aR0 - 0.06, paint)
				if full then
					local l0, l1 = sx * (hw - 0.02), sx * (hw + 0.14)
					box(b, "SkirtLip", math.min(l0, l1), math.max(l0, l1), g.sill - 0.16, g.sill - 0.08, g.aF1 + 0.1, g.aR0 - 0.1, HOUSING, M.Plastic)
				end
			end
		end
		-- aileron : sur l'arête du toit (2 volumes) ou sur le coffre (3 volumes)
		local spoiler = mod("Spoiler")
		if spoiler ~= "Stock" and spoiler ~= "None" and (full or spoiler == "Wing" or spoiler == "GT") then
			local roofMount = twoBox
			local carbon = Color3.fromRGB(30, 31, 36)
			if roofMount then
				local Rr = sectionAt(st, s.R1)
				local yTop = Rr.t + Rr.c
				local e = Rr.e
				if spoiler == "Lip" then
					wedge(b, "Spoiler", -e + 0.12, e - 0.12, yTop - 0.02, yTop + 0.12, s.R1 - 0.1, s.R1 + 0.5, false, paint)
				elseif spoiler == "Duck" then
					-- grand becquet de pavillon (dessus plat + dessous en biseau)
					box(b, "Spoiler", -e + 0.08, e - 0.08, yTop - 0.02, yTop + 0.08, s.R1 - 0.15, s.R1 + 0.6, paint)
					wedge(b, "Spoiler", -e + 0.08, e - 0.08, yTop - 0.22, yTop - 0.02, s.R1 + 0.2, s.R1 + 0.6, true, paint)
				else
					local gt = spoiler == "GT"
					local lift = if gt then 0.5 else 0.28
					local bladeCol = if gt then carbon else paint
					for _, sx in ipairs({ -1, 1 }) do
						local px = sx * (e - 0.45)
						box(b, "WingPost", px - 0.05, px + 0.05, Rr.t + Rr.c * 0.4 - 0.02, yTop + lift, s.R1 - 0.1, s.R1 + 0.2, HOUSING)
					end
					local blade = box(b, "Wing", -e - (if gt then 0.1 else -0.05), e + (if gt then 0.1 else -0.05), yTop + lift, yTop + lift + 0.1, s.R1 - 0.25, s.R1 + (if gt then 0.75 else 0.55), bladeCol, if gt then M.Fabric else M.SmoothPlastic)
					blade.CFrame = blade.CFrame * CFrame.Angles(math.rad(-6), 0, 0)
					if gt and full then
						for _, sx in ipairs({ -1, 1 }) do
							local ex = sx * (e + 0.14)
							box(b, "WingPlate", ex - 0.04, ex + 0.04, yTop + lift - 0.2, yTop + lift + 0.26, s.R1 - 0.35, s.R1 + 0.8, carbon, M.Fabric)
						end
					end
				end
			else
				local deckZ = zB - 0.75
				local Sd = sectionAt(st, deckZ)
				local deckY = if pickup then s.Deck + 0.1 else topAt(Sd, 0)
				local e = if pickup then hw - 0.3 else Sd.e
				if spoiler == "Lip" then
					wedge(b, "Spoiler", -e + 0.15, e - 0.15, deckY - 0.04, deckY + 0.12, zB - 0.75, zB - 0.25, true, paint)
				elseif spoiler == "Duck" then
					wedge(b, "Spoiler", -e + 0.1, e - 0.1, deckY - 0.08, deckY + 0.22, zB - 1.4, zB - 0.3, true, paint)
				else
					local gt = spoiler == "GT"
					local lift = if gt then 0.95 else 0.6
					local bladeCol = if gt then carbon else paint
					local wz0, wz1 = zB - (if gt then 1.35 else 1.1), zB - 0.3
					for _, sx in ipairs({ -1, 1 }) do
						local px = sx * math.min(e - 0.3, hw * 0.55)
						box(b, "WingPost", px - 0.06, px + 0.06, deckY - 0.06, deckY + lift, wz0 + 0.3, wz0 + 0.62, HOUSING)
					end
					local half = (if gt then hw - 0.15 else hw - 0.5)
					local blade = box(b, "Wing", -half, half, deckY + lift, deckY + lift + 0.1, wz0, wz1, bladeCol, if gt then M.Fabric else M.SmoothPlastic)
					blade.CFrame = blade.CFrame * CFrame.Angles(math.rad(-8), 0, 0)
					if gt and full then
						for _, sx in ipairs({ -1, 1 }) do
							local ex = sx * (half + 0.05)
							box(b, "WingPlate", ex - 0.04, ex + 0.04, deckY + lift - 0.25, deckY + lift + 0.3, wz0 - 0.1, wz1 + 0.05, carbon, M.Fabric)
						end
					end
				end
			end
		end
		-- néon doux sous la caisse (Neon translucide, AUCUNE lumière)
		local glow = Config.CarModsById and Config.CarModsById.Glow and Config.CarModsById.Glow[mod("Glow")]
		if glow and typeof(glow.Color) == "Color3" then
			local gy0, gy1 = math.max(0.12, s.Clear - 0.12), math.max(0.18, s.Clear - 0.05)
			local parts = {}
			for _, sx in ipairs({ -1, 1 }) do
				local x0, x1 = sx * (hw - 0.3), sx * (hw - 0.16)
				table.insert(parts, box(b, "Underglow", math.min(x0, x1), math.max(x0, x1), gy0, gy1, g.aF1 + 0.1, g.aR0 - 0.1, glow.Color, M.Neon))
			end
			if full then
				table.insert(parts, box(b, "Underglow", -kitNfx + 0.5, kitNfx - 0.5, gy0, gy1, zF + 0.5, zF + 0.64, glow.Color, M.Neon))
				table.insert(parts, box(b, "Underglow", -st[#st].fx + 0.5, st[#st].fx - 0.5, gy0, gy1, zB - 0.64, zB - 0.5, glow.Color, M.Neon))
			end
			for _, q in ipairs(parts) do
				q.Transparency = 0.3
				q:SetAttribute("Glow", true)
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
	-- (v10) finition (Repaint la garde) et options de l'atelier
	model:SetAttribute("Finish", finish)
	model:SetAttribute("Mods", CarModels.EncodeMods(mods))
	return model
end

----------------------------------------------------------------------
-- 🚦 (v10) FEUX : stop, recul, clignotants, phares (côté CLIENT, local :
-- CarClient pour les voitures des joueurs ; TownTraffic peut s'en servir).
-- On passe les glaces en Neon (plus clair) quand le feu est allumé :
-- aucune lumière, aucun son.
----------------------------------------------------------------------
export type LightEntry = { Part: BasePart, Color: Color3, Material: Enum.Material, Side: number }
export type LightRig = {
	Brake: { LightEntry },
	Reverse: { LightEntry },
	Blink: { LightEntry },
	Head: { LightEntry },
	State: { [string]: any },
}

local LIGHT_KIND: { [string]: string } = {
	Taillight = "Brake",
	TailWrap = "Brake",
	TailBar = "Brake",
	TailWrapBar = "Brake",
	TailLightBar = "Brake",
	BrakeLight3 = "Brake",
	ReverseLight = "Reverse",
	Indicator = "Blink",
	RearIndicator = "Blink",
	MirrorBlinker = "Blink",
	HeadlightDRL = "Head",
	HeadlightWrapDRL = "Head",
	Projector = "Head",
	Headlight = "Head",
	HeadlightDot = "Head",
	FogLight = "Head",
}
local LIGHT_ON: { [string]: Color3 } = {
	Brake = Color3.fromRGB(255, 46, 64),
	Reverse = Color3.fromRGB(255, 255, 255),
	Blink = Color3.fromRGB(255, 170, 40),
	Head = Color3.fromRGB(255, 250, 236),
}

function CarModels.LightRig(model: Instance): LightRig
	local rig: LightRig = { Brake = {}, Reverse = {}, Blink = {}, Head = {}, State = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local kind = LIGHT_KIND[d.Name]
			if kind then
				local side = tonumber(d:GetAttribute("Side")) or (if d.Position.X > 0 then 1 else -1)
				table.insert((rig :: any)[kind], { Part = d, Color = d.Color, Material = d.Material, Side = side })
			end
		end
	end
	return rig
end

-- state = { Brake = bool, Reverse = bool, Blink = -1 | 0 | 1 (côté, déjà
-- cadencé par l'appelant), Hazard = bool, Head = bool } ; ne touche une pièce
-- que si son état change (bon marché, appelable 10 fois / s)
function CarModels.SetLights(rig: LightRig, state: any)
	local function apply(kind: string, list: { LightEntry }, wantFor: (LightEntry) -> boolean)
		for _, e in ipairs(list) do
			local on = wantFor(e)
			local key = e.Part
			if rig.State[key] ~= on then
				rig.State[key] = on
				if on then
					e.Part.Material = Enum.Material.Neon
					e.Part.Color = LIGHT_ON[kind]:Lerp(e.Color, 0.25)
				else
					e.Part.Material = e.Material
					e.Part.Color = e.Color
				end
			end
		end
	end
	local brake = state.Brake == true
	local reverse = state.Reverse == true
	local blink = tonumber(state.Blink) or 0
	local hazard = state.Hazard == true
	local head = state.Head == true
	apply("Brake", rig.Brake, function()
		return brake
	end)
	apply("Reverse", rig.Reverse, function()
		return reverse
	end)
	apply("Blink", rig.Blink, function(e: LightEntry)
		return hazard or (blink ~= 0 and e.Side == blink)
	end)
	apply("Head", rig.Head, function()
		return head
	end)
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
