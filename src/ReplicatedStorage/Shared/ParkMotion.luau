--[[
	ParkMotion (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > ParkMotion

	🛝 Aire de jeux de Dopamine Town (v9.9, PARK99) : plan ET mouvements,
	partagés par le serveur (TownPark : sièges, invites) et le client
	(ParkPlay : décor réaliste, animation, poses de l'avatar).

	Tout le mouvement est une FONCTION DE L'HEURE DU SERVEUR
	(workspace:GetServerTimeNow()) et de 4 attributs posés par le serveur sur
	chaque jeu quand quelqu'un monte ou descend :
	  On (bool) : au moins un enfant dessus ; T0 : heure du dernier changement ;
	  A0 : enveloppe (0..1) ou angle au moment T0 ; W0 : vitesse (tourniquet).
	Chaque client calcule donc EXACTEMENT la même pose, sans remote ni flux
	réseau : tout le monde voit la balançoire du voisin se balancer.

	Physique (à l'échelle réelle : ~3,06 studs par mètre, SCALE99) :
	  - balançoire : pendule simple, ω = √(g / L), g = 9,81 m/s² × 3,06 ;
	    l'amplitude monte quand on "pompe" (enveloppe 1 − e^(−t/τ)) puis
	    s'amortit quand on descend ;
	  - tape-cul : bascule à plateau (on reste un instant en bas : tanh) ;
	  - tourniquet : vitesse angulaire qui monte / retombe (intégrale exacte :
	    aucun à-coup de l'angle aux changements) ;
	  - jeux à ressort : tangage + roulis + petit rebond.

	Repère de l'aire (g) : centre au sol (dessus du pré), -Z vers la place
	(portillon), comme TownNature.
]]

local ParkMotion = {}

local rad = math.rad
local exp = math.exp
local sin = math.sin
local TAU = math.pi * 2

----------------------------------------------------------------------
-- Échelle et physique
----------------------------------------------------------------------

ParkMotion.STUDS_PER_METER = 3.06
ParkMotion.G = 9.81 * ParkMotion.STUDS_PER_METER -- (studs/s²) ≈ 30

----------------------------------------------------------------------
-- Plan (repère de l'aire)
----------------------------------------------------------------------

ParkMotion.W, ParkMotion.D = 38, 30 -- (aire) largeur x profondeur
ParkMotion.FLOOR_TOP = 0.2 -- dessus du sol souple (serveur)
ParkMotion.GATE = 2.4 -- demi-largeur du portillon (côté -Z)

-- Balançoires : portique le long de X, on se balance le long de Z
ParkMotion.SWING = {
	Center = Vector3.new(11, 0, -7),
	PivotY = 8.6, -- axe des crochets (sous la poutre) (v11 SCALE11 : portique plus haut)
	SeatTop = 1.85, -- dessus de l'assise au repos (v11 SCALE11 : 1,85)
	Xs = { -2.7, 0, 2.7 }, -- 3 places (2 sangles + 1 siège bébé)
	Amax = rad(34),
	Rise = 3.2, -- (s) on prend de l'élan…
	Fall = 5.0, -- …et on s'arrête doucement
}
ParkMotion.SWING.L = ParkMotion.SWING.PivotY - ParkMotion.SWING.SeatTop
ParkMotion.SWING.Omega = math.sqrt(ParkMotion.G / ParkMotion.SWING.L) -- (rad/s) période ≈ 2,9 s

-- Tape-cul : planche le long de X, pivot au centre
ParkMotion.SEESAW = {
	Center = Vector3.new(11.5, 0, 7),
	PivotY = 1.55,
	Half = 4.3, -- demi-longueur de la planche
	SeatX = 3.85, -- sièges à ±SeatX
	SeatUp = 0.52, -- dessus du siège au-dessus de l'axe
	Tilt = rad(13),
	Period = 2.6,
	Rise = 0.9,
	Fall = 1.6,
}

-- Tourniquet
ParkMotion.MERRY = {
	Center = Vector3.new(2, 0, 0.5),
	DeckTop = 0.9,
	Radius = 3.3,
	SeatR = 2.4,
	SeatTop = 1.45,
	Seats = 4,
	Wmax = 1.1, -- (rad/s) un tour en ~5,7 s
	Rise = 2.4,
	Fall = 5.5,
}

-- Jeux à ressort (cheval, canard)
ParkMotion.SPRINGS = {
	{ Pos = Vector3.new(-6, 0, -11.4), Yaw = rad(20), Kind = "Horse" },
	{ Pos = Vector3.new(-6.6, 0, -6.4), Yaw = rad(-25), Kind = "Duck" },
}
ParkMotion.SPRING = {
	PivotY = 0.45, -- haut du socle (le ressort part de là)
	SeatUp = 1.45, -- dessus de la selle au-dessus du pivot (selle à ~1,9)
	Pitch = rad(15),
	Roll = rad(4),
	Freq = 1.25,
	Rise = 0.8,
	Fall = 1.3,
}

-- Toboggan : tour, échelle (-Z), glissière (+Z), mur d'escalade (-X)
ParkMotion.SLIDE = {
	Tower = Vector3.new(-12, 0, 1.8),
	DeckTop = 4.6,
	Deck = 3.4,
	-- profil de la glissière (repère de la tour) : { z, dessus de la surface }
	Profile = { { 1.7, 4.62 }, { 2.3, 4.58 }, { 3.0, 4.25 }, { 7.8, 1.2 }, { 8.7, 0.78 }, { 10.2, 0.72 } },
	LadderZ = -2.05, -- plan des barreaux (devant la tour)
	LadderLean = rad(14),
}

-- Cage à grimper + échelle horizontale (barres de singe)
ParkMotion.MONKEY = {
	Z = 10.5,
	X0 = -5.2, -- échelle de départ (bout -X)
	X1 = 4.2, -- échelle d'arrivée (bout +X)
	BarY = 7.0, -- barreaux (centre)
	Rungs = 9,
	Width = 1.8,
}

-- Bac à sable
ParkMotion.SAND = { Center = Vector3.new(-13.5, 0, -10.5), Inner = 6.4 }

-- Bancs des parents (2 places chacun)
ParkMotion.BENCHES = {
	{ Pos = Vector3.new(15.9, 0, -1), Face = Vector3.new(-1, 0, 0) },
	{ Pos = Vector3.new(-17.4, 0, -3.8), Face = Vector3.new(1, 0, 0) },
}
ParkMotion.BENCH = { SeatTop = 1.85, Length = 5.6, Places = { -1.4, 1.4 } } -- (v11 SCALE11)

----------------------------------------------------------------------
-- Enveloppe (0 -> 1 en montant, 1 -> 0 en descendant), continue
----------------------------------------------------------------------

function ParkMotion.Env(on: boolean, t0: number, a0: number, t: number, rise: number, fall: number): number
	local dt = math.max(0, t - t0)
	if on then
		return 1 - (1 - math.clamp(a0, 0, 1)) * exp(-dt / rise)
	end
	return math.clamp(a0, 0, 1) * exp(-dt / fall)
end

-- État d'un jeu (attributs du serveur) ; valeurs sûres si absents
export type State = { On: boolean, T0: number, A0: number, W0: number }

function ParkMotion.StateOf(holder: Instance?): State
	local on, t0, a0, w0 = false, 0, 0, 0
	if holder then
		on = holder:GetAttribute("On") == true
		t0 = tonumber(holder:GetAttribute("T0")) or 0
		a0 = tonumber(holder:GetAttribute("A0")) or 0
		w0 = tonumber(holder:GetAttribute("W0")) or 0
	end
	if t0 ~= t0 then
		t0 = 0
	end
	if a0 ~= a0 then
		a0 = 0
	end
	if w0 ~= w0 then
		w0 = 0
	end
	return { On = on, T0 = t0, A0 = a0, W0 = w0 }
end

-- Réglages (montée / descente) par sorte de jeu
local RATES = {
	Swing = ParkMotion.SWING,
	Seesaw = ParkMotion.SEESAW,
	Spring = ParkMotion.SPRING,
}

-- Tourniquet : (angle, vitesse) à l'instant t
function ParkMotion.Merry(s: State, t: number): (number, number)
	local m = ParkMotion.MERRY
	local dt = math.max(0, t - s.T0)
	if s.On then
		local k = exp(-dt / m.Rise)
		local w = m.Wmax - (m.Wmax - s.W0) * k
		local a = s.A0 + m.Wmax * dt - (m.Wmax - s.W0) * m.Rise * (1 - k)
		return a, w
	end
	local k = exp(-dt / m.Fall)
	return s.A0 + s.W0 * m.Fall * (1 - k), s.W0 * k
end

-- Nouvel état quand le nombre d'enfants passe de 0 à 1 (on = true) ou de
-- 1 à 0 (on = false) : l'enveloppe / l'angle repartent de leur valeur
-- ACTUELLE (aucun saut)
function ParkMotion.Transition(kind: string, s: State, t: number, on: boolean): State
	if kind == "Merry" then
		local a, w = ParkMotion.Merry(s, t)
		return { On = on, T0 = t, A0 = a % TAU, W0 = w }
	end
	local r = RATES[kind] or ParkMotion.SWING
	local env = ParkMotion.Env(s.On, s.T0, s.A0, t, r.Rise, r.Fall)
	return { On = on, T0 = t, A0 = env, W0 = 0 }
end

function ParkMotion.EnvOf(kind: string, s: State, t: number): number
	local r = RATES[kind] or ParkMotion.SWING
	return ParkMotion.Env(s.On, s.T0, s.A0, t, r.Rise, r.Fall)
end

----------------------------------------------------------------------
-- Poses (repère de l'aire)
----------------------------------------------------------------------

-- Balançoire `i` : angle (rad, + = vers -Z) et phase (pour les jambes)
function ParkMotion.SwingAngle(env: number, t: number, i: number): (number, number)
	local S = ParkMotion.SWING
	local phase = S.Omega * t + i * 1.9
	return S.Amax * env * sin(phase), phase
end

-- Repère du pivot de la balançoire i (x le long de la poutre)
function ParkMotion.SwingPivot(i: number): CFrame
	local S = ParkMotion.SWING
	return CFrame.new(S.Center + Vector3.new(S.Xs[i] or 0, S.PivotY, 0))
end

-- Repère de l'assise (dessus, face -Z) pour un angle donné
function ParkMotion.SwingSeat(i: number, angle: number): CFrame
	local S = ParkMotion.SWING
	return ParkMotion.SwingPivot(i) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -S.L, 0)
end

-- Tape-cul : angle (+ = le bout +X monte)
function ParkMotion.SeesawAngle(env: number, t: number): number
	local S = ParkMotion.SEESAW
	-- au repos : le bout +X posé au sol ; en jeu : bascule "à plateau"
	local wave = math.tanh(2.4 * sin(TAU * t / S.Period)) / math.tanh(2.4)
	return -S.Tilt * (1 - env) + S.Tilt * env * wave
end

function ParkMotion.SeesawPivot(angle: number): CFrame
	local S = ParkMotion.SEESAW
	return CFrame.new(S.Center + Vector3.new(0, S.PivotY, 0)) * CFrame.Angles(0, 0, angle)
end

-- Siège k (1 = bout -X, face +X ; 2 = bout +X, face -X), dessus du siège
function ParkMotion.SeesawSeat(k: number, angle: number): CFrame
	local S = ParkMotion.SEESAW
	local x = k == 1 and -S.SeatX or S.SeatX
	local p = ParkMotion.SeesawPivot(angle) * CFrame.new(x, S.SeatUp, 0)
	-- (le siège reste dans le plan de la planche ; l'avatar regarde le pivot)
	local yaw = k == 1 and -math.pi / 2 or math.pi / 2
	return p * CFrame.Angles(0, yaw, 0)
end

function ParkMotion.MerryFrame(angle: number): CFrame
	local m = ParkMotion.MERRY
	return CFrame.new(m.Center) * CFrame.Angles(0, angle, 0)
end

-- Siège k du tourniquet (dessus, face au centre)
function ParkMotion.MerrySeat(k: number, angle: number): CFrame
	local m = ParkMotion.MERRY
	local a = (k - 0.5) / m.Seats * TAU
	return ParkMotion.MerryFrame(angle) * CFrame.Angles(0, a, 0) * CFrame.new(0, m.SeatTop, m.SeatR)
end

-- Jeu à ressort i : repère du socle, puis repère du corps (tangage / roulis)
function ParkMotion.SpringBase(i: number): CFrame
	local s = ParkMotion.SPRINGS[i] or ParkMotion.SPRINGS[1]
	return CFrame.new(s.Pos) * CFrame.Angles(0, s.Yaw, 0)
end

function ParkMotion.SpringBody(i: number, env: number, t: number): CFrame
	local S = ParkMotion.SPRING
	local w = TAU * S.Freq * t + i * 2.3
	local pitch = S.Pitch * env * sin(w)
	local roll = S.Roll * env * sin(w * 0.5 + 0.7)
	local bounce = 0.12 * env * math.abs(sin(w))
	return ParkMotion.SpringBase(i) * CFrame.new(0, S.PivotY + bounce, 0) * CFrame.Angles(pitch, 0, roll)
end

function ParkMotion.SpringSeat(i: number, env: number, t: number): CFrame
	return ParkMotion.SpringBody(i, env, t) * CFrame.new(0, ParkMotion.SPRING.SeatUp, 0.15)
end

-- Bancs : place k du banc b (dessus de l'assise, face `Face`)
function ParkMotion.BenchFrame(b: number): CFrame
	local B = ParkMotion.BENCHES[b] or ParkMotion.BENCHES[1]
	return CFrame.lookAt(B.Pos, B.Pos + B.Face)
end

function ParkMotion.BenchSeat(b: number, k: number): CFrame
	-- (v11 SCALE11 : dessus des lattes, centré sur la profondeur : z -0,15)
	return ParkMotion.BenchFrame(b) * CFrame.new(ParkMotion.BENCH.Places[k] or 0, ParkMotion.BENCH.SeatTop, -0.15)
end

----------------------------------------------------------------------
-- Toboggan : point de la surface à l'abscisse z (repère de la tour)
----------------------------------------------------------------------

function ParkMotion.SlideTower(): CFrame
	return CFrame.new(ParkMotion.SLIDE.Tower)
end

-- (y, pente dy/dz) de la surface de glisse à l'abscisse z (profil lissé)
function ParkMotion.SlideSurface(z: number): (number, number)
	local P = ParkMotion.SLIDE.Profile
	if z <= P[1][1] then
		return P[1][2], 0
	end
	for i = 1, #P - 1 do
		local a, b = P[i], P[i + 1]
		if z <= b[1] then
			local u = (z - a[1]) / (b[1] - a[1])
			local slope = (b[2] - a[2]) / (b[1] - a[1])
			-- raccord doux avec les pentes voisines (Hermite)
			local s0 = i > 1 and (b[2] - P[i - 1][2]) / (b[1] - P[i - 1][1]) or slope
			local s1 = i < #P - 1 and (P[i + 2][2] - a[2]) / (P[i + 2][1] - a[1]) or slope
			local h = b[1] - a[1]
			local u2, u3 = u * u, u * u * u
			local y = (2 * u3 - 3 * u2 + 1) * a[2] + (u3 - 2 * u2 + u) * h * s0 + (-2 * u3 + 3 * u2) * b[2] + (u3 - u2) * h * s1
			local dy = ((6 * u2 - 6 * u) * a[2] + (3 * u2 - 4 * u + 1) * h * s0 + (-6 * u2 + 6 * u) * b[2] + (3 * u2 - 2 * u) * h * s1) / h
			return y, dy
		end
	end
	local last = P[#P]
	return last[2], 0
end

ParkMotion.SLIDE_END = ParkMotion.SLIDE.Profile[#ParkMotion.SLIDE.Profile][1]

return ParkMotion
