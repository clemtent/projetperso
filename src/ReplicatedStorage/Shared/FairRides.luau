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
	    place / l'entrée), coordonnées locales x ∈ [-55, 55], z ∈ [-38, 38] ;
	  - chaque manège a son repère (Base, au sol) ; Pose() remplit des
	    "groupes" (CFrame relatifs à la Base) : plateau, nacelles,
	    chevaux… ; un siège = Base * groupe * Local.
	Pas de service Roblox ici (CFrame seulement) : testable hors jeu.
]]

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
FairRides.FAIR_HALF_D = 38
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
	{ Id = "Swings", Kind = "Swings", Name = "Swing ride", Icon = "🎢", Pos = Vector3.new(-36, 0, 21), Yaw = 0,
		Cycle = { Load = 8, Ramp = 4, Run = 36 }, Speed = TAU / 6.5, Gate = Vector3.new(-20.5, 0, 9.5), Exit = Vector3.new(-21, 0, 34) },
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
	{ Id = "CornerTruck", Pos = Vector3.new(-6, 0, 10), Yaw = 180, Foods = { "Taco", "PizzaSlice", "HotDog" }, Style = "Truck" },
	{ Id = "CornerCrepe", Pos = Vector3.new(10, 0, -4), Yaw = 90, Foods = { "Crepe", "Churros" }, Style = "Churros" },
	{ Id = "CornerIce", Pos = Vector3.new(-10, 0, -8), Yaw = -90, Foods = { "IceCream", "Milkshake", "Donut" }, Style = "IceCream" },
}

return FairRides
