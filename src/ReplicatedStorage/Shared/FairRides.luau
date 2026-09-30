--[[
	FairRides (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > FairRides

	🎡 Fête foraine de Dopamine Town (v9.8, FAIR98) : la GÉOMÉTRIE et le
	MOUVEMENT des manèges, partagés par le serveur (TownFair : sièges
	ancrés qui bougent) et le client (FairFx : le décor, et les mêmes
	sièges lissés à chaque image ; TownPlazaFx pour le manège de la place).

	Tout mouvement est une fonction PURE de l'heure du serveur
	(workspace:GetServerTimeNow()) : le serveur et tous les clients
	calculent exactement la même pose, sans rien s'envoyer. Un manège
	tourne par CYCLES : arrêt (embarquement), accélération douce, marche,
	ralentissement ; on peut monter à tout moment (invite "Monter").

	Repères :
	  - la fête : WorldLayout.FairCFrame() (centre du sol, -Z local vers la
	    place / l'entrée), coordonnées locales x ∈ [-55, 55], z ∈ [-36, 36] ;
	  - chaque manège a son repère (Base, au sol) ; Pose() remplit des
	    "groupes" (CFrame relatifs à la Base) : plateau, nacelles,
	    chevaux… ; un siège = Base * groupe * Local.
	Pas de service Roblox ici (CFrame seulement) : testable hors jeu.
]]

local FairTrack = require(script.Parent.FairTrack)

local FairRides = {}

local TAU = math.pi * 2

----------------------------------------------------------------------
-- Cycles
----------------------------------------------------------------------

export type Cycle = { Load: number, Ramp: number, Run: number }

-- Période d'un cycle (s)
function FairRides.Period(c: Cycle): number
	return c.Load + 2 * c.Ramp + c.Run
end

-- Heure t (s) -> (avance en "secondes à pleine vitesse", vitesse 0..1,
-- phase "load" | "run", secondes avant la fin de la phase)
function FairRides.Cycle(c: Cycle, t: number): (number, number, string, number)
	local P = FairRides.Period(c)
	local tm = t % P
	local n = (t - tm) / P
	local A, H, L = c.Ramp, c.Run, c.Load
	local per = A + H -- avance d'un cycle complet
	local base = (n % 100000) * per
	if tm < L then
		return base, 0, "load", L - tm
	end
	local u = tm - L
	if u < A then
		return base + u * u / (2 * A), u / A, "run", P - tm
	end
	u -= A
	if u < H then
		return base + A / 2 + u, 1, "run", P - tm
	end
	u -= H
	local left = A - u
	return base + A / 2 + H + (A / 2 - left * left / (2 * A)), left / A, "run", P - tm
end

----------------------------------------------------------------------
-- Manège à chevaux (celui de la place ET celui de la fête) : mêmes
-- emplacements (= TownPlazaFx) : 8 au bord (r 6,6, 2 carrosses) + 4 dedans
----------------------------------------------------------------------

FairRides.CAROUSEL_BOB_SPEED = TAU / 2.6 -- une montée-descente en 2,6 s
FairRides.CAROUSEL_BOB_AMP = 0.5
FairRides.PLAZA_SPIN = TAU / 16 -- manège de la place : un tour en 16 s, sans arrêt

export type Spot = { Pos: Vector3, Fwd: Vector3, Base: CFrame, Carriage: boolean, Horse: number?, Phase: number }

local spots: { Spot }? = nil
function FairRides.CarouselSpots(): { Spot }
	if spots then
		return spots
	end
	local list = {}
	local raw = {}
	for k = 0, 7 do
		table.insert(raw, { A = k / 8 * TAU, R = 6.6, Carriage = k == 0 or k == 4 })
	end
	for k = 0, 3 do
		table.insert(raw, { A = (k + 0.25) / 4 * TAU, R = 4, Carriage = false })
	end
	local horse = 0
	for _, s in ipairs(raw) do
		local pos = Vector3.new(math.sin(s.A) * s.R, 0, math.cos(s.A) * s.R)
		local fwd = Vector3.new(math.cos(s.A), 0, -math.sin(s.A)) -- sens de la rotation
		local entry: Spot = { Pos = pos, Fwd = fwd, Base = CFrame.lookAt(pos, pos + fwd), Carriage = s.Carriage, Horse = nil, Phase = 0 }
		if not s.Carriage then
			horse += 1
			entry.Horse = horse
			entry.Phase = (horse % 2) * math.pi + horse * 0.35
		end
		table.insert(list, entry)
	end
	spots = list
	return list
end
FairRides.CAROUSEL_HORSES = 10
FairRides.HORSE_Y = 2.75 -- centre du corps d'un cheval au-dessus du plateau

-- Groupes : [1] = plateau qui tourne, [1 + k] = cheval k (qui monte et descend)
local function carouselPose(theta: number, bobClock: number, amp: number, out: { CFrame }): number
	local rot = CFrame.Angles(0, theta, 0)
	out[1] = rot
	for _, s in ipairs(FairRides.CarouselSpots()) do
		local k = s.Horse
		if k then
			local bob = amp * math.sin(bobClock * FairRides.CAROUSEL_BOB_SPEED + s.Phase)
			out[1 + k] = rot * s.Base * CFrame.new(0, FairRides.HORSE_Y + bob, 0)
		end
	end
	return 1 + FairRides.CAROUSEL_HORSES
end

-- Manège de la place (tourne sans arrêt, comme en v9.7)
function FairRides.PlazaTheta(now: number): number
	return (now * FairRides.PLAZA_SPIN) % TAU
end

----------------------------------------------------------------------
-- Définition des manèges de la fête (repère de la fête, y = 0 au sol)
----------------------------------------------------------------------

FairRides.FAIR_HALF_W = 55
FairRides.FAIR_HALF_D = 36
FairRides.GROUND = 0.15 -- dessus du sol de la fête au-dessus du pré

-- Grande roue
FairRides.FERRIS_R = 16 -- rayon des axes des nacelles
FairRides.FERRIS_HUB = 21.5 -- hauteur du moyeu
FairRides.FERRIS_N = 10
FairRides.FERRIS_DROP = 4.4 -- de l'axe d'une nacelle à son plancher
-- Tasses
FairRides.CUPS_N = 5
FairRides.CUPS_R = 6 -- rayon des tasses sur le plateau
FairRides.CUPS_DECK = 0.8 -- dessus du plateau tournant
-- Chaises volantes
FairRides.SWING_N = 12
FairRides.SWING_TOP = 12 -- hauteur de l'anneau des chaînes
FairRides.SWING_R0 = 7.5 -- rayon de l'anneau des chaînes
FairRides.SWING_L = 9.2 -- longueur des chaînes
FairRides.SWING_MAX = math.rad(38) -- inclinaison à pleine vitesse
-- Tour de chute (douce)
FairRides.TOWER_N = 8
FairRides.TOWER_R = 3.1 -- rayon des sièges (tournés vers l'extérieur)
FairRides.TOWER_LOW = 1.3 -- plancher de la nacelle en bas
FairRides.TOWER_HIGH = 29 -- ... en haut
FairRides.TOWER_H = 36 -- hauteur du mât
-- Autos tamponneuses
FairRides.BUMPER_W = 30
FairRides.BUMPER_D = 22
FairRides.BUMPER_CARS = 6

export type RideDef = {
	Id: string,
	Kind: string, -- "Carousel" | "Ferris" | "Cups" | "Swings" | "Tower" | "Bumper"
	Name: string, -- texte anglais (Locale.T)
	Icon: string,
	Pos: Vector3, -- repère de la fête
	Yaw: number, -- degrés (autour de Y)
	Cycle: Cycle,
	Speed: number, -- rad/s à pleine vitesse (ou tours)
	Gate: Vector3, -- borne "Monter" (repère de la fête)
	Exit: Vector3, -- où l'on descend (repère de la fête)
}

FairRides.Rides = {
	{ Id = "Ferris", Kind = "Ferris", Name = "Big wheel", Icon = "🎡", Pos = Vector3.new(0, 0, 24), Yaw = 0,
		Cycle = { Load = 10, Ramp = 4, Run = 60 }, Speed = TAU / 36, Gate = Vector3.new(6.5, 0, 14.5), Exit = Vector3.new(-6.5, 0, 13) },
	{ Id = "Carousel", Kind = "Carousel", Name = "Carousel", Icon = "🎠", Pos = Vector3.new(-33, 1.2, -18), Yaw = 0, -- (repère = dessus du socle, comme celui de la place)
		Cycle = { Load = 8, Ramp = 3, Run = 40 }, Speed = TAU / 14, Gate = Vector3.new(-19.8, 0, -12), Exit = Vector3.new(-19.8, 0, -23) },
	{ Id = "Cups", Kind = "Cups", Name = "Teacups", Icon = "☕", Pos = Vector3.new(33, 0, -18), Yaw = 0,
		Cycle = { Load = 8, Ramp = 3, Run = 32 }, Speed = TAU / 14, Gate = Vector3.new(19.6, 0, -12), Exit = Vector3.new(19.6, 0, -23) },
	{ Id = "Swings", Kind = "Swings", Name = "Swing ride", Icon = "🎢", Pos = Vector3.new(-36, 0, 20), Yaw = 0,
		Cycle = { Load = 8, Ramp = 4, Run = 36 }, Speed = TAU / 6.5, Gate = Vector3.new(-20.5, 0, 8.5), Exit = Vector3.new(-21, 0, 32) },
	{ Id = "Tower", Kind = "Tower", Name = "Drop tower", Icon = "🗼", Pos = Vector3.new(-17, 0, 3), Yaw = 0,
		Cycle = { Load = 10, Ramp = 0, Run = 22.2 }, Speed = 0, Gate = Vector3.new(-9.4, 0, 0), Exit = Vector3.new(-9.4, 0, 6.5) },
	{ Id = "Bumper", Kind = "Bumper", Name = "Bumper cars", Icon = "🚗", Pos = Vector3.new(35, 0, 22), Yaw = 0,
		Cycle = { Load = 8, Ramp = 0, Run = 60 }, Speed = 0, Gate = Vector3.new(19, 0, 8.5), Exit = Vector3.new(17, 0, 14) },
} :: { RideDef }

FairRides.ById = {} :: { [string]: RideDef }
for _, r in ipairs(FairRides.Rides) do
	FairRides.ById[r.Id] = r
end

-- Repère (au sol) d'un manège de la fête
function FairRides.RideBase(fairCF: CFrame, def: RideDef): CFrame
	return fairCF * CFrame.new(def.Pos) * CFrame.Angles(0, math.rad(def.Yaw), 0)
end

----------------------------------------------------------------------
-- Tour de chute : hauteur (plancher de la nacelle) et rotation
----------------------------------------------------------------------

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Run = 22,2 s : montée 14 s, pause 3 s, chute douce 2,2 s, remontée +
-- rebond 3 s. Renvoie (hauteur, rotation, phase, secondes avant la fin)
function FairRides.TowerState(c: Cycle, t: number): (number, number, string, number)
	local P = FairRides.Period(c)
	local tm = t % P
	local low, high = FairRides.TOWER_LOW, FairRides.TOWER_HIGH
	if tm < c.Load then
		return low, 0, "load", c.Load - tm
	end
	local u = tm - c.Load
	local left = P - tm
	if u < 14 then
		local k = smooth(u / 14)
		return low + (high - low) * k, math.pi * k, "run", left
	end
	u -= 14
	if u < 3 then
		return high, math.pi, "run", left
	end
	u -= 3
	local bottom = low + 2.4
	if u < 2.2 then
		-- chute : accélère puis freine (jamais brutale)
		local k = u / 2.2
		local e = if k < 0.6 then (k / 0.6) ^ 2 * 0.75 else 0.75 + 0.25 * smooth((k - 0.6) / 0.4)
		return high + (bottom - high) * e, math.pi, "run", left
	end
	u -= 2.2
	-- petit rebond puis on redescend doucement au quai
	local k = math.clamp(u / 3, 0, 1)
	local bounce = math.sin(k * math.pi) * 1.2 * (1 - k)
	return bottom + (low - bottom) * smooth(k) + bounce, math.pi * (1 + smooth(k)), "run", left
end

----------------------------------------------------------------------
-- Poses : remplit `out` (CFrame relatifs à la Base) ; renvoie le nombre
-- de groupes. `t` = heure du serveur.
----------------------------------------------------------------------

function FairRides.Pose(def: RideDef, t: number, out: { CFrame }): number
	local kind = def.Kind
	if kind == "PlazaCarousel" then
		return carouselPose(FairRides.PlazaTheta(t), t, FairRides.CAROUSEL_BOB_AMP, out)
	end
	if kind == "Tower" then
		local y, rot = FairRides.TowerState(def.Cycle, t)
		out[1] = CFrame.new(0, y, 0) * CFrame.Angles(0, rot, 0)
		return 1
	end
	if kind == "Pirate" or kind == "Coaster" or kind == "Ghost" or kind == "Circus" then
		return FairRides.PoseAnnex(def, t, out)
	end
	local progress, speed = FairRides.Cycle(def.Cycle, t)
	local theta = (progress * def.Speed) % TAU
	if kind == "Carousel" then
		-- (les chevaux ne montent et descendent que quand ça tourne)
		return carouselPose(theta, progress, FairRides.CAROUSEL_BOB_AMP * math.min(1, speed * 1.5 + 0.0), out)
	elseif kind == "Ferris" then
		local hub = FairRides.FERRIS_HUB
		out[1] = CFrame.new(0, hub, 0) * CFrame.Angles(0, 0, theta)
		local R, N = FairRides.FERRIS_R, FairRides.FERRIS_N
		-- petit balancement des nacelles (plus fort quand la roue accélère)
		local sway = math.rad(2.2) * speed * math.sin(progress * 1.3)
		for k = 1, N do
			local a = theta + (k - 1) / N * TAU
			-- (= moyeu * Angles(0, 0, a) appliqué au point (0, -R) : suit les rayons)
			out[1 + k] = CFrame.new(math.sin(a) * R, hub - math.cos(a) * R, 0) * CFrame.Angles(0, 0, sway)
		end
		return 1 + N
	elseif kind == "Cups" then
		local deck = CFrame.new(0, FairRides.CUPS_DECK, 0) * CFrame.Angles(0, theta, 0)
		out[1] = deck
		local spin = -progress * TAU / 4.5
		for k = 1, FairRides.CUPS_N do
			local a = (k - 1) / FairRides.CUPS_N * TAU
			out[1 + k] = deck * CFrame.new(math.sin(a) * FairRides.CUPS_R, 0, math.cos(a) * FairRides.CUPS_R) * CFrame.Angles(0, spin + a * 3, 0)
		end
		return 1 + FairRides.CUPS_N
	elseif kind == "Swings" then
		local rot = CFrame.Angles(0, theta, 0)
		out[1] = rot
		local alpha = FairRides.SWING_MAX * speed * speed
		for k = 1, FairRides.SWING_N do
			local a = (k - 1) / FairRides.SWING_N * TAU
			local pivot = rot * CFrame.Angles(0, a, 0) * CFrame.new(FairRides.SWING_R0, FairRides.SWING_TOP, 0)
			out[1 + k] = pivot * CFrame.Angles(0, 0, alpha) * CFrame.new(0, -FairRides.SWING_L, 0)
		end
		return 1 + FairRides.SWING_N
	end
	return 0
end

-- Inclinaison actuelle des chaises volantes (pour les chaînes, côté client)
function FairRides.SwingAlpha(def: RideDef, t: number): number
	local _, speed = FairRides.Cycle(def.Cycle, t)
	return FairRides.SWING_MAX * speed * speed
end

----------------------------------------------------------------------
-- Sièges : { Group, Local } (le devant du siège = -Z = regard de l'avatar)
----------------------------------------------------------------------

export type SeatSpec = { Group: number, Local: CFrame, Size: Vector3 }

local seatCache: { [string]: { SeatSpec } } = {}
function FairRides.Seats(kind: string): { SeatSpec }
	local cached = seatCache[kind]
	if cached then
		return cached
	end
	local list: { SeatSpec } = {}
	if kind == "Carousel" or kind == "PlazaCarousel" then
		for _, s in ipairs(FairRides.CarouselSpots()) do
			if s.Horse then
				-- sur la selle (dessus de la selle à +0,875 du centre du cheval)
				table.insert(list, { Group = 1 + s.Horse, Local = CFrame.new(0, 0.8, -0.05), Size = Vector3.new(1.1, 0.16, 1.2) })
			else
				-- banquette du carrosse (dos au dossier)
				table.insert(list, { Group = 1, Local = s.Base * CFrame.new(0, 0.98, 0.8), Size = Vector3.new(1.5, 0.16, 0.9) })
			end
		end
	elseif kind == "Ferris" then
		for k = 1, FairRides.FERRIS_N do
			local y = -FairRides.FERRIS_DROP + 1.45
			table.insert(list, { Group = 1 + k, Local = CFrame.new(-1.45, y, 0) * CFrame.Angles(0, math.rad(-90), 0), Size = Vector3.new(1.6, 0.16, 1.1) })
			table.insert(list, { Group = 1 + k, Local = CFrame.new(1.45, y, 0) * CFrame.Angles(0, math.rad(90), 0), Size = Vector3.new(1.6, 0.16, 1.1) })
		end
	elseif kind == "Cups" then
		for k = 1, FairRides.CUPS_N do
			table.insert(list, { Group = 1 + k, Local = CFrame.new(-1.05, 1.25, 0) * CFrame.Angles(0, math.rad(-90), 0), Size = Vector3.new(1.4, 0.16, 1) })
			table.insert(list, { Group = 1 + k, Local = CFrame.new(1.05, 1.25, 0) * CFrame.Angles(0, math.rad(90), 0), Size = Vector3.new(1.4, 0.16, 1) })
		end
	elseif kind == "Swings" then
		for k = 1, FairRides.SWING_N do
			table.insert(list, { Group = 1 + k, Local = CFrame.new(0, -0.35, 0), Size = Vector3.new(1.4, 0.16, 1.2) })
		end
	elseif kind == "Pirate" or kind == "Coaster" or kind == "Ghost" or kind == "Circus" then
		list = FairRides.AnnexSeats(kind)
	elseif kind == "Tower" then
		for k = 1, FairRides.TOWER_N do
			local a = (k - 1) / FairRides.TOWER_N * TAU
			table.insert(list, { Group = 1, Local = CFrame.Angles(0, a, 0) * CFrame.new(0, 1.35, -FairRides.TOWER_R) , Size = Vector3.new(1.5, 0.16, 1.1) })
		end
	end
	seatCache[kind] = list
	return list
end

-- CFrame (repère de la Base) du siège `index` d'après les groupes déjà calculés
function FairRides.SeatLocal(kind: string, index: number, groups: { CFrame }): CFrame
	local spec = FairRides.Seats(kind)[index]
	return groups[spec.Group] * spec.Local
end

-- Phase affichée (panneaux) : ("load" | "run", secondes restantes)
function FairRides.Phase(def: RideDef, t: number): (string, number)
	if def.Kind == "Tower" then
		local _, _, phase, left = FairRides.TowerState(def.Cycle, t)
		return phase, left
	end
	if def.Kind == "Coaster" or def.Kind == "Ghost" or def.Kind == "Pirate" then
		local P = FairRides.Period(def.Cycle)
		local tm = t % P
		if tm < def.Cycle.Load then
			return "load", def.Cycle.Load - tm
		end
		return "run", P - tm
	end
	local _, _, phase, left = FairRides.Cycle(def.Cycle, t)
	return phase, left
end

----------------------------------------------------------------------
-- Autos tamponneuses : places de départ (repère de l'arène, au sol)
----------------------------------------------------------------------

function FairRides.BumperHome(index: number): CFrame
	local col = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	return CFrame.new(-8 + col * 8, 0, -4 + row * 8) * CFrame.Angles(0, if row == 0 then 0 else math.pi, 0)
end

----------------------------------------------------------------------
-- Stands de nourriture de la fête (repère de la fête) : devant (-Z du
-- stand) tourné vers l'allée ; Foods = ids de Config.Food.Items
----------------------------------------------------------------------

FairRides.Stalls = {
	{ Id = "FairChurros", Pos = Vector3.new(-11.5, 0, -28), Yaw = -90, Foods = { "Churros", "Crepe" }, Style = "Churros" },
	{ Id = "FairDonut", Pos = Vector3.new(-11.5, 0, -14), Yaw = -90, Foods = { "Donut", "Milkshake" }, Style = "Donut" },
	{ Id = "FairPopcorn", Pos = Vector3.new(11.5, 0, -28), Yaw = 90, Foods = { "Popcorn", "CandyFloss" }, Style = "Popcorn" },
	{ Id = "FairHotDog", Pos = Vector3.new(11.5, 0, -14), Yaw = 90, Foods = { "HotDog", "CandyApple" }, Style = "HotDog" },
}

-- Coin gourmand près de l'arrivée (repère : WorldLayout.FoodCornerCFrame)
FairRides.CornerStalls = {
	{ Id = "CornerTruck", Pos = Vector3.new(-6, 0, 10), Yaw = 0, Foods = { "Taco", "PizzaSlice", "HotDog" }, Style = "Truck" },
	{ Id = "CornerCrepe", Pos = Vector3.new(10, 0, -4), Yaw = 90, Foods = { "Crepe", "Churros" }, Style = "Churros" },
	{ Id = "CornerIce", Pos = Vector3.new(-10, 0, -8), Yaw = -90, Foods = { "IceCream", "Milkshake", "Donut" }, Style = "IceCream" },
}

----------------------------------------------------------------------
-- (v9.9, FAIR99) 🎪 L'ANNEXE : cirque, grand huit, bateau pirate, train
-- fantôme. Leur place dépend de la taille de la ville (4 à 12 parcelles) :
-- le serveur (TownFair) la calcule avec FairRides.SolveAnnex et l'écrit
-- dans l'attribut "BaseCF" de chaque dossier (le client le relit).
-- Repère de chaque attraction : au sol, -Z = l'entrée (côté visiteurs).
-- + trampolines et palais des glaces DANS la fête (places fixes).
----------------------------------------------------------------------

-- 🏴‍☠️ Bateau pirate : coque (axe X) pendue à 2 bras sous l'axe
FairRides.PIRATE_PIVOT = 14.5 -- hauteur de l'axe
FairRides.PIRATE_ARM = 9.2 -- de l'axe au pont de la coque
FairRides.PIRATE_MAX = math.rad(58) -- balancement maximal
FairRides.PIRATE_PERIOD = 5.6 -- (s) aller-retour

-- 🎢 Grand huit familial (x -27..27, z -8..8 ; gare devant, z -5,5)
FairRides.COASTER_POINTS = {
	Vector3.new(-5, 1.6, -5.5), -- arrêt en gare (avant du train)
	Vector3.new(2, 1.6, -5.5),
	Vector3.new(7, 2.0, -5.5), -- pied de la montée (chaîne)
	Vector3.new(17, 9.6, -5.5), -- sommet
	Vector3.new(21.5, 10.2, -4.5),
	Vector3.new(25, 9.2, -0.5),
	Vector3.new(22.5, 7.4, 3.8),
	Vector3.new(15, 2.6, 5.5), -- grande descente
	Vector3.new(8, 2.1, 5.6),
	Vector3.new(2.5, 5.0, 5.6), -- bosse (on décolle un peu !)
	Vector3.new(-3.5, 2.3, 5.6),
	Vector3.new(-11, 4.4, 5.4),
	Vector3.new(-18, 5.9, 4.4),
	Vector3.new(-24, 5.0, 1),
	Vector3.new(-25.5, 3.7, -3),
	Vector3.new(-21.5, 2.5, -5.7),
	Vector3.new(-15, 1.75, -5.55),
	Vector3.new(-10, 1.6, -5.5),
}
FairRides.COASTER_CARS = 4
FairRides.COASTER_GAP = 3.3 -- (studs) d'un wagon à l'autre
FairRides.COASTER_LIFT = { From = Vector3.new(6.5, 2, -5.5), To = Vector3.new(17, 9.6, -5.5), V = 3.6 }

-- 👻 Train fantôme : maison x -12..12, z -8..8 ; gare dehors (z -12)
FairRides.GHOST_POINTS = {
	Vector3.new(-3, 0.45, -12),
	Vector3.new(4, 0.45, -12),
	Vector3.new(7.6, 0.45, -10.4),
	Vector3.new(8.3, 0.45, -5),
	Vector3.new(7.2, 0.45, 2.6),
	Vector3.new(2.2, 0.45, 5.6),
	Vector3.new(-0.8, 0.45, -0.8),
	Vector3.new(-5, 0.45, 5.2),
	Vector3.new(-8.6, 0.45, 1.4),
	Vector3.new(-8.3, 0.45, -5),
	Vector3.new(-8.6, 0.45, -10.4),
	Vector3.new(-6.2, 0.45, -12),
}
FairRides.GHOST_CARS = 3
FairRides.GHOST_GAP = 3.1
FairRides.GHOST_SPEED = 4.2

-- 🎪 Cirque : chapiteau r 18, piste r 6,5, gradins (3 rangs) en 2 tribunes
FairRides.CIRCUS_R = 18
FairRides.CIRCUS_RING = 6.5
FairRides.CIRCUS_TIERS = 3
FairRides.CIRCUS_TIER_R0 = 10.4 -- rayon du 1er rang de sièges
FairRides.CIRCUS_TIER_DR = 1.9
FairRides.CIRCUS_TIER_DY = 1.25
FairRides.CIRCUS_SEAT_Y0 = 1.35 -- dessus du 1er rang
FairRides.CIRCUS_ARCS = { { 32, 140 }, { -140, -32 } } -- (degrés, 0 = fond +Z)
FairRides.CIRCUS_PER_ARC = 4
FairRides.CIRCUS_SHOW = 64 -- (s) le spectacle tourne en boucle

-- Emprise de chaque attraction (repère de l'attraction) : Body = le
-- bâtiment / le manège, Apron = le parvis devant l'entrée (doit rester libre)
export type Rect = { X0: number, X1: number, Z0: number, Z1: number }
export type AnnexDef = {
	Id: string,
	Kind: string,
	Name: string,
	Icon: string,
	Cycle: Cycle,
	Speed: number,
	Gate: Vector3, -- borne (repère de l'attraction)
	Exit: Vector3,
	Body: Rect,
	Apron: Rect,
	Pos: Vector3, -- place "idéale" (grande ville) ; SolveAnnex décide
	Yaw: number,
}

FairRides.Annex = {
	{ Id = "Circus", Kind = "Circus", Name = "Circus", Icon = "🎪", Cycle = { Load = 0, Ramp = 0, Run = 1 }, Speed = 0,
		Gate = Vector3.new(4.2, 0, -20.6), Exit = Vector3.new(-4.5, 0, -23.5),
		Body = { X0 = -20, X1 = 20, Z0 = -21, Z1 = 20 }, Apron = { X0 = -9, X1 = 9, Z0 = -28, Z1 = -21 },
		Pos = Vector3.new(94, 0, -8), Yaw = 90 },
	{ Id = "Coaster", Kind = "Coaster", Name = "Roller coaster", Icon = "🎢", Cycle = { Load = 14, Ramp = 0, Run = 30 }, Speed = 0,
		Gate = Vector3.new(-14.6, 0, -11.2), Exit = Vector3.new(-5, 0, -12.8),
		Body = { X0 = -27.5, X1 = 27.5, Z0 = -9.5, Z1 = 8 }, Apron = { X0 = -20, X1 = -2, Z0 = -15, Z1 = -9.5 },
		Pos = Vector3.new(84, 0, 26), Yaw = 180 },
	{ Id = "Ghost", Kind = "Ghost", Name = "Ghost train", Icon = "👻", Cycle = { Load = 9, Ramp = 0, Run = 30 }, Speed = 0,
		Gate = Vector3.new(5, 0, -16.6), Exit = Vector3.new(-5, 0, -17.5),
		Body = { X0 = -12.5, X1 = 12.5, Z0 = -14.5, Z1 = 9 }, Apron = { X0 = -9, X1 = 7, Z0 = -19.5, Z1 = -14.5 },
		Pos = Vector3.new(68, 0, -24), Yaw = 180 },
	{ Id = "Pirate", Kind = "Pirate", Name = "Pirate ship", Icon = "🏴‍☠️", Cycle = { Load = 10, Ramp = 0, Run = 44 }, Speed = 0,
		Gate = Vector3.new(5.6, 0, -10.8), Exit = Vector3.new(-5, 0, -11.5),
		Body = { X0 = -14.5, X1 = 14.5, Z0 = -7.5, Z1 = 7.5 }, Apron = { X0 = -7, X1 = 8, Z0 = -14, Z1 = -7.5 },
		Pos = Vector3.new(116, 0, 24), Yaw = 180 },
} :: { AnnexDef }

-- (petites attractions SANS siège, dans l'annexe elles aussi)
table.insert(FairRides.Annex, { Id = "Trampolines", Kind = "Trampolines", Name = "Trampolines", Icon = "🤸", Cycle = { Load = 0, Ramp = 0, Run = 1 }, Speed = 0,
	Gate = Vector3.new(0, 0, -7.5), Exit = Vector3.new(0, 0, -9),
	Body = { X0 = -8.5, X1 = 8.5, Z0 = -6.5, Z1 = 6.5 }, Apron = { X0 = -4, X1 = 4, Z0 = -10.5, Z1 = -6.5 },
	Pos = Vector3.new(122, 0, -26), Yaw = 90 })
table.insert(FairRides.Annex, { Id = "Mirrors", Kind = "Mirrors", Name = "Hall of mirrors", Icon = "🪞", Cycle = { Load = 0, Ramp = 0, Run = 1 }, Speed = 0,
	Gate = Vector3.new(0, 0, -7.5), Exit = Vector3.new(0, 0, -9),
	Body = { X0 = -8, X1 = 8, Z0 = -6.5, Z1 = 6.5 }, Apron = { X0 = -4, X1 = 4, Z0 = -10.5, Z1 = -6.5 },
	Pos = Vector3.new(122, 0, 8), Yaw = 90 })

-- Trampolines : 4 toiles 2 x 2 (repère de l'attraction)
FairRides.TRAMPOLINE_BED = 4.6 -- côté d'une toile
FairRides.TRAMPOLINE_TOP = 1.15 -- dessus de la toile (au repos)
FairRides.TRAMPOLINE_BEDS = { Vector3.new(-3.6, 0, -2.8), Vector3.new(3.6, 0, -2.8), Vector3.new(-3.6, 0, 2.8), Vector3.new(3.6, 0, 2.8) }
FairRides.TRAMPOLINE_BOUNCE = 46 -- (studs/s) rebond de base (~5,4 studs de haut)
FairRides.TRAMPOLINE_BOOST = 64 -- rebond si l'on saute au bon moment (~10 studs)

for _, def in ipairs(FairRides.Annex) do
	FairRides.ById[def.Id] = def :: any
end

----------------------------------------------------------------------
-- Rails (grand huit, train fantôme) : construits une fois (module pur)
----------------------------------------------------------------------

local tracks: { [string]: any } = {}

local function nearestS(track: any, p: Vector3): number
	local best, bestS = math.huge, 0
	for i = 1, track.N do
		local d = (track.Pos[i] - p).Magnitude
		if d < best then
			best = d
			bestS = (i - 1) * track.Step
		end
	end
	return bestS
end

-- kind -> { Track, Profile, Cars, Gap } (profil de vitesse compris)
function FairRides.Track(kind: string): any
	local cached = tracks[kind]
	if cached then
		return cached
	end
	local entry
	if kind == "Coaster" then
		local track = FairTrack.Build(FairRides.COASTER_POINTS, { MaxBank = math.rad(26), BankGain = 10 })
		-- (s = 0 : l'arrêt en gare, le premier point)
		local lift = FairRides.COASTER_LIFT
		local profile = FairTrack.Profile(track, {
			Lift = { A = nearestS(track, lift.From), B = nearestS(track, lift.To), V = lift.V },
			G = 35, -- (1 stud ≈ 0,28 m : 9,8 m/s² ≈ 35 studs/s²)
			Friction = 0.018,
			MinV = 3,
			MaxV = 26,
			Launch = 2.6,
			Decel = 3.4,
			StartV = 0,
		})
		entry = { Track = track, Profile = profile, Cars = FairRides.COASTER_CARS, Gap = FairRides.COASTER_GAP }
	elseif kind == "Ghost" then
		local track = FairTrack.Build(FairRides.GHOST_POINTS, { MaxBank = math.rad(6), BankGain = 2 })
		local profile = FairTrack.Profile(track, { Cruise = FairRides.GHOST_SPEED, Launch = 1.6, Decel = 1.8, StartV = 0 })
		entry = { Track = track, Profile = profile, Cars = FairRides.GHOST_CARS, Gap = FairRides.GHOST_GAP }
	end
	tracks[kind] = entry
	return entry
end

-- Durée d'un tour -> cycle (embarquement + un tour)
for _, def in ipairs(FairRides.Annex) do
	if def.Kind == "Coaster" or def.Kind == "Ghost" then
		local entry = FairRides.Track(def.Kind)
		def.Cycle = { Load = def.Cycle.Load, Ramp = 0, Run = entry.Profile.Lap }
	end
end

-- Abscisse de l'avant du train à l'heure t (0 = en gare)
function FairRides.TrainS(def: any, t: number): number
	local entry = FairRides.Track(def.Kind)
	local P = FairRides.Period(def.Cycle)
	local tm = t % P
	if tm < def.Cycle.Load then
		return 0
	end
	return FairTrack.Distance(entry.Profile, tm - def.Cycle.Load)
end

-- Angle du bateau pirate : amplitude qui monte, tient, puis s'éteint
function FairRides.PirateAngle(def: any, t: number): number
	local c = def.Cycle
	local P = FairRides.Period(c)
	local tm = t % P
	if tm < c.Load then
		return 0
	end
	local u = tm - c.Load
	local run = c.Run
	local up, down = 13, 13
	local env
	if u < up then
		env = smooth(u / up)
	elseif u > run - down then
		env = smooth((run - u) / down)
	else
		env = 1
	end
	-- (période entière : l'angle revient à 0 pile à la fin)
	local cycles = math.max(1, math.floor(run / FairRides.PIRATE_PERIOD + 0.5))
	return FairRides.PIRATE_MAX * env * math.sin(u / run * cycles * TAU)
end

-- Poses de l'annexe (groupes relatifs à la Base)
function FairRides.PoseAnnex(def: any, t: number, out: { CFrame }): number
	local kind = def.Kind
	if kind == "Pirate" then
		local a = FairRides.PirateAngle(def, t)
		out[1] = CFrame.new(0, FairRides.PIRATE_PIVOT, 0) * CFrame.Angles(0, 0, a) * CFrame.new(0, -FairRides.PIRATE_ARM, 0)
		return 1
	elseif kind == "Coaster" or kind == "Ghost" then
		local entry = FairRides.Track(kind)
		local s = FairRides.TrainS(def, t)
		for k = 1, entry.Cars do
			out[k] = FairTrack.Frame(entry.Track, s - (k - 1) * entry.Gap)
		end
		return entry.Cars
	elseif kind == "Circus" then
		out[1] = CFrame.identity
		return 1
	end
	return 0
end

-- Sièges de l'annexe (Group, Local, Size ; -Z du siège = regard)
function FairRides.AnnexSeats(kind: string): { SeatSpec }
	local list: { SeatSpec } = {}
	if kind == "Pirate" then
		-- 4 rangées face au milieu, 3 places ; les bouts sont plus hauts
		for _, x in ipairs({ -7.2, -4.4, 4.4, 7.2 }) do
			local yaw = if x < 0 then math.rad(-90) else math.rad(90)
			local y = 1.25 + (math.abs(x) - 4.4) * 0.3
			for _, z in ipairs({ -1.35, 0, 1.35 }) do
				table.insert(list, { Group = 1, Local = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), Size = Vector3.new(1.2, 0.16, 1) })
			end
		end
	elseif kind == "Coaster" then
		for k = 1, FairRides.COASTER_CARS do
			for _, x in ipairs({ -0.7, 0.7 }) do
				table.insert(list, { Group = k, Local = CFrame.new(x, 0.95, 0.35), Size = Vector3.new(1.1, 0.16, 1) })
			end
		end
	elseif kind == "Ghost" then
		for k = 1, FairRides.GHOST_CARS do
			for _, x in ipairs({ -0.66, 0.66 }) do
				table.insert(list, { Group = k, Local = CFrame.new(x, 1.05, 0.3), Size = Vector3.new(1.1, 0.16, 1) })
			end
		end
	elseif kind == "Circus" then
		for tier = 0, FairRides.CIRCUS_TIERS - 1 do
			local r = FairRides.CIRCUS_TIER_R0 + tier * FairRides.CIRCUS_TIER_DR
			local y = FairRides.CIRCUS_SEAT_Y0 + tier * FairRides.CIRCUS_TIER_DY
			for _, arc in ipairs(FairRides.CIRCUS_ARCS) do
				local n = FairRides.CIRCUS_PER_ARC
				for i = 0, n - 1 do
					local a = math.rad(arc[1] + (arc[2] - arc[1]) * (i + 0.5) / n)
					local p = Vector3.new(math.sin(a) * r, y, math.cos(a) * r)
					table.insert(list, { Group = 1, Local = CFrame.lookAt(p, Vector3.new(0, y, 0)), Size = Vector3.new(1.3, 0.16, 1.1) })
				end
			end
		end
	end
	return list
end

----------------------------------------------------------------------
-- Placement de l'annexe (pur) : pour chaque attraction, de la plus grande
-- à la plus petite, on essaie d'abord sa place "idéale", puis toutes les
-- places d'une grille autour de la fête (4 orientations) ; on garde la
-- place libre la plus proche d'une porte de la fête. `isFree(x, z)` (repère
-- de la fête) dit si un point du sol est libre (rues, boulevard, lac…).
----------------------------------------------------------------------

-- Portes de la fête (repère de la fête) : arche, côtés (clôture ouverte)
FairRides.GATES = { Vector3.new(0, 0, -FairRides.FAIR_HALF_D - 6), Vector3.new(FairRides.FAIR_HALF_W + 2, 0, -1), Vector3.new(-FairRides.FAIR_HALF_W - 2, 0, -1) }

local function rectPoints(r: Rect, step: number, margin: number): { Vector3 }
	local pts = {}
	local x0, x1, z0, z1 = r.X0 - margin, r.X1 + margin, r.Z0 - margin, r.Z1 + margin
	local nx = math.max(1, math.ceil((x1 - x0) / step))
	local nz = math.max(1, math.ceil((z1 - z0) / step))
	for i = 0, nx do
		for k = 0, nz do
			table.insert(pts, Vector3.new(x0 + (x1 - x0) * i / nx, 0, z0 + (z1 - z0) * k / nz))
		end
	end
	return pts
end

local function corners(r: Rect, margin: number): { Vector3 }
	return {
		Vector3.new(r.X0 - margin, 0, r.Z0 - margin), Vector3.new(r.X1 + margin, 0, r.Z0 - margin),
		Vector3.new(r.X0 - margin, 0, r.Z1 + margin), Vector3.new(r.X1 + margin, 0, r.Z1 + margin),
		Vector3.new((r.X0 + r.X1) / 2, 0, (r.Z0 + r.Z1) / 2),
	}
end

-- Rectangle (repère de l'attraction) -> rectangle englobant dans la fête
local function worldBox(r: Rect, cf: CFrame, margin: number): Rect
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(corners(r, margin)) do
		local w = cf * p
		x0, x1 = math.min(x0, w.X), math.max(x1, w.X)
		z0, z1 = math.min(z0, w.Z), math.max(z1, w.Z)
	end
	return { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 }
end

local function overlap(a: Rect, b: Rect): boolean
	return a.X0 < b.X1 and b.X0 < a.X1 and a.Z0 < b.Z1 and b.Z0 < a.Z1
end

export type Placement = { Pos: Vector3, Yaw: number, CF: CFrame, Box: Rect }

-- isFree(x, z) : repère de la fête ; renvoie { [Id] = Placement }.
-- `looseFree` (facultatif) : 2e passe, plus permissive (ex. : sans les
-- sites de la nature qui sont posés APRÈS la fête et doivent l'éviter),
-- pour une attraction qui n'a trouvé aucune place à la 1re passe.
function FairRides.SolveAnnex(strictFree: (number, number) -> boolean, looseFree: ((number, number) -> boolean)?): { [string]: Placement }
	local isFree = strictFree
	local hw, hd = FairRides.FAIR_HALF_W, FairRides.FAIR_HALF_D
	-- la fête elle-même + le couloir derrière la mairie (on y passe)
	local taken: { Rect } = {
		{ X0 = -hw - 1.5, X1 = hw + 1.5, Z0 = -hd - 1.5, Z1 = hd + 1.5 },
		{ X0 = -60, X1 = 60, Z0 = -hd - 16, Z1 = -hd },
	}
	-- les portes de côté gardent un passage
	for _, gx in ipairs({ -1, 1 }) do
		table.insert(taken, { X0 = if gx > 0 then hw else -hw - 7, X1 = if gx > 0 then hw + 7 else -hw, Z0 = -6, Z1 = 5 })
	end
	local result: { [string]: Placement } = {}
	local function fits(def: AnnexDef, cf: CFrame): (boolean, Rect?)
		local body = worldBox(def.Body, cf, 1.5)
		local apron = worldBox(def.Apron, cf, 0.5)
		for _, r in ipairs(taken) do
			if overlap(body, r) or overlap(apron, r) then
				return false, nil
			end
		end
		-- test rapide (coins), puis complet (grille de 3 studs)
		for _, rect in ipairs({ def.Body, def.Apron }) do
			for _, p in ipairs(corners(rect, 1.5)) do
				local w = cf * p
				if not isFree(w.X, w.Z) then
					return false, nil
				end
			end
		end
		for _, rect in ipairs({ def.Body, def.Apron }) do
			for _, p in ipairs(rectPoints(rect, 3, 1.5)) do
				local w = cf * p
				if not isFree(w.X, w.Z) then
					return false, nil
				end
			end
		end
		return true, body
	end
	local function cost(def: AnnexDef, cf: CFrame): number
		local door = cf * Vector3.new((def.Apron.X0 + def.Apron.X1) / 2, 0, def.Apron.Z0)
		local best = math.huge
		for _, g in ipairs(FairRides.GATES) do
			best = math.min(best, (door - g).Magnitude)
		end
		-- (entrée tournée vers la fête : un peu préférée)
		local toFair = -Vector3.new(door.X, 0, door.Z)
		local look = cf.LookVector
		local facing = if toFair.Magnitude > 1 then look:Dot(toFair.Unit) else 0
		return best - facing * 6
	end
	-- candidats (grille de 4 studs, 4 orientations) triés par coût : on
	-- s'arrête au PREMIER qui tient (rapide, ~10 000 candidats au plus)
	local function search(def: AnnexDef): (CFrame?, Rect?)
		local ideal = CFrame.new(def.Pos) * CFrame.Angles(0, math.rad(def.Yaw), 0)
		local ok, box = fits(def, ideal)
		if ok then
			return ideal, box
		end
		local cands = {}
		for gx = -150, 150, 4 do
			for gz = -84, 44, 4 do
				if math.abs(gx) > hw + 4 or gz < -hd - 4 then
					for yaw = 0, 270, 90 do
						local cf = CFrame.new(gx, 0, gz) * CFrame.Angles(0, math.rad(yaw), 0)
						table.insert(cands, { CF = cf, Cost = cost(def, cf) })
					end
				end
			end
		end
		table.sort(cands, function(a, b)
			return a.Cost < b.Cost
		end)
		for _, c in ipairs(cands) do
			local fit, b = fits(def, c.CF)
			if fit then
				return c.CF, b
			end
		end
		return nil, nil
	end
	for _, def in ipairs(FairRides.Annex) do
		isFree = strictFree
		local bestCF, bestBox = search(def)
		if not bestCF and looseFree then
			isFree = looseFree
			bestCF, bestBox = search(def)
		end
		if bestCF and bestBox then
			local yaw = math.deg(select(2, bestCF:ToOrientation()))
			result[def.Id] = { Pos = bestCF.Position, Yaw = yaw, CF = bestCF, Box = bestBox }
			table.insert(taken, bestBox)
			table.insert(taken, worldBox(def.Apron, bestCF, 0.5))
		end
	end
	return result
end

-- Boîte (repère de la fête) du corps d'une attraction placée en `cf`
function FairRides.AnnexBox(def: AnnexDef, cf: CFrame): Rect
	return worldBox(def.Body, cf, 1.5)
end

local function segmentHits(a: Vector3, b: Vector3, boxes: { Rect }, skip: Rect?): boolean
	local len = (b - a).Magnitude
	local n = math.max(1, math.ceil(len / 1.5))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		for _, r in ipairs(boxes) do
			if r ~= skip and p.X > r.X0 and p.X < r.X1 and p.Z > r.Z0 and p.Z < r.Z1 then
				return true
			end
		end
	end
	return false
end

-- Allée (repère de la fête, au sol) de la porte de la fête la plus proche
-- jusqu'au parvis de l'attraction : points { porte, coude, parvis, entrée }.
-- `boxes` = corps des autres attractions (+ la fête) à contourner.
function FairRides.AnnexPath(def: AnnexDef, cf: CFrame, boxes: { Rect }): { Vector3 }
	local door = cf * Vector3.new((def.Apron.X0 + def.Apron.X1) / 2, 0, def.Apron.Z0 + 0.5)
	local inner = cf * Vector3.new((def.Apron.X0 + def.Apron.X1) / 2, 0, (def.Apron.Z0 + def.Apron.Z1) / 2)
	local best: { Vector3 }? = nil
	local bestScore = math.huge
	for _, g in ipairs(FairRides.GATES) do
		for order = 1, 2 do
			local corner = if order == 1 then Vector3.new(door.X, 0, g.Z) else Vector3.new(g.X, 0, door.Z)
			local hits = (if segmentHits(g, corner, boxes) then 1 else 0) + (if segmentHits(corner, door, boxes) then 1 else 0)
			local score = (corner - g).Magnitude + (door - corner).Magnitude + hits * 400
			if score < bestScore then
				bestScore = score
				best = { g, corner, door, inner }
			end
		end
	end
	return best or { door, door, door, inner }
end

return FairRides
