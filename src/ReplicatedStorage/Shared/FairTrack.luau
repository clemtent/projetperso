--[[
	FairTrack (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > FairTrack

	🎢 Manèges SUR RAILS de la fête (v9.9, FAIR99) : grand huit familial et
	train fantôme. Module PUR (CFrame / Vector3 seulement, aucun service) :
	le serveur (TownFair : sièges) et chaque client (FairFx : wagons, rails)
	calculent la MÊME pose à partir de l'heure du serveur.

	  - FairTrack.Build(points, opts) -> Track : spline de Catmull-Rom
	    CENTRIPÈTE fermée (jamais de boucle parasite), rééchantillonnée tous
	    les STEP studs (longueur d'arc), avec tangente, inclinaison dans les
	    virages (dévers) et repère lissé ;
	  - FairTrack.Frame(track, s) -> CFrame : repère du rail à l'abscisse s
	    (-Z = sens de la marche, +Y = dessus du rail, dévers compris) ;
	  - FairTrack.Profile(track, spec) : profil de vitesse PHYSIQUE (montée
	    à la chaîne, puis énergie : v² = v0² + 2 g (h0 - h) - frottement,
	    freins avant la gare) -> table temps(s), durée d'un tour ;
	  - FairTrack.Distance(profile, u) -> s : où est le train u secondes
	    après le départ (recherche dichotomique, interpolée : continue).
	s = 0 : l'arrêt en gare (avant du train). Le train s'y arrête pendant
	l'embarquement puis fait exactement UN tour.
]]

local FairTrack = {}

FairTrack.STEP = 0.25 -- (studs) pas du rééchantillonnage

export type Track = {
	Length: number,
	Step: number,
	N: number,
	Pos: { Vector3 },
	Look: { Vector3 },
	Up: { Vector3 },
	Height: { number },
}

export type Profile = {
	Track: Track,
	Times: { number }, -- temps (s) pour atteindre l'échantillon i (1 = gare)
	Speeds: { number }, -- vitesse (studs/s) à l'échantillon i
	Lap: number,
	MaxSpeed: number,
}

-- Catmull-Rom centripète (alpha = 0,5) entre p1 et p2
local function knot(t: number, a: Vector3, b: Vector3): number
	return t + math.max(1e-4, (b - a).Magnitude ^ 0.5)
end

local function crPoint(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: number): Vector3
	local t0 = 0
	local t1 = knot(t0, p0, p1)
	local t2 = knot(t1, p1, p2)
	local t3 = knot(t2, p2, p3)
	local t = t1 + (t2 - t1) * u
	local a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	local a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	local a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	local b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	local b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
end

-- opts : { MaxBank (rad), BankGain, Sub (sous-pas par segment) }
function FairTrack.Build(points: { Vector3 }, opts: any?): Track
	local o = opts or {}
	local maxBank = o.MaxBank or math.rad(24)
	local gain = o.BankGain or 9
	local sub = o.Sub or 40
	local n = #points
	-- 1) polyligne fine
	local dense: { Vector3 } = {}
	for i = 1, n do
		local p0 = points[(i - 2) % n + 1]
		local p1 = points[i]
		local p2 = points[i % n + 1]
		local p3 = points[(i + 1) % n + 1]
		for k = 0, sub - 1 do
			table.insert(dense, crPoint(p0, p1, p2, p3, k / sub))
		end
	end
	table.insert(dense, dense[1])
	local cum = { 0 }
	for i = 2, #dense do
		cum[i] = cum[i - 1] + (dense[i] - dense[i - 1]).Magnitude
	end
	local length = cum[#dense]
	-- 2) rééchantillonnage à pas constant (longueur d'arc)
	local step = FairTrack.STEP
	local count = math.max(8, math.floor(length / step + 0.5))
	step = length / count
	local pos: { Vector3 } = {}
	local j = 1
	for i = 0, count - 1 do
		local s = i * step
		while j < #dense - 1 and cum[j + 1] < s do
			j += 1
		end
		local seg = cum[j + 1] - cum[j]
		local u = if seg > 1e-6 then (s - cum[j]) / seg else 0
		pos[i + 1] = dense[j]:Lerp(dense[j + 1], u)
	end
	-- 3) tangentes (différences centrées) et courbure horizontale -> dévers
	local look: { Vector3 } = {}
	local height: { number } = {}
	for i = 1, count do
		local a = pos[(i - 2) % count + 1]
		local b = pos[i % count + 1]
		look[i] = (b - a).Unit
		height[i] = pos[i].Y
	end
	local rawBank: { number } = {}
	local W = math.max(2, math.floor(1.5 / step))
	for i = 1, count do
		local a = look[(i - 1 - W) % count + 1]
		local b = look[(i - 1 + W) % count + 1]
		local ha = math.atan2(a.X, a.Z)
		local hb = math.atan2(b.X, b.Z)
		local d = (hb - ha + math.pi) % (2 * math.pi) - math.pi
		local curvature = d / (2 * W * step) -- rad / stud (signe : sens du virage)
		rawBank[i] = math.clamp(curvature * gain, -maxBank, maxBank)
	end
	-- lissage du dévers (moyenne glissante, fenêtre ~6 studs) : aucune secousse
	local up: { Vector3 } = {}
	local Wb = math.max(3, math.floor(3 / step))
	for i = 1, count do
		local sum = 0
		for k = -Wb, Wb do
			sum += rawBank[(i - 1 + k) % count + 1]
		end
		local bank = sum / (2 * Wb + 1)
		local fwd = look[i]
		local right = fwd:Cross(Vector3.new(0, 1, 0))
		if right.Magnitude < 1e-3 then
			right = Vector3.new(1, 0, 0)
		end
		right = right.Unit
		local flatUp = right:Cross(fwd).Unit
		-- (virage à gauche : bank > 0 -> le wagon penche vers l'intérieur,
		-- c.-à-d. vers -right)
		up[i] = (flatUp * math.cos(bank) - right * math.sin(bank)).Unit
	end
	return { Length = length, Step = step, N = count, Pos = pos, Look = look, Up = up, Height = height }
end

local function wrapIndex(track: Track, s: number): (number, number, number)
	local L = track.Length
	s = s % L
	local f = s / track.Step
	local i = math.floor(f)
	local u = f - i
	local a = i % track.N + 1
	local b = (i + 1) % track.N + 1
	return a, b, u
end

-- Repère du rail à l'abscisse s (interpolé : continu d'une image à l'autre)
function FairTrack.Frame(track: Track, s: number): CFrame
	local a, b, u = wrapIndex(track, s)
	local p = track.Pos[a]:Lerp(track.Pos[b], u)
	local fwd = track.Look[a]:Lerp(track.Look[b], u).Unit
	local up = track.Up[a]:Lerp(track.Up[b], u)
	local right = fwd:Cross(up).Unit
	up = right:Cross(fwd).Unit
	-- (-Z = avant : LookVector = fwd)
	return CFrame.fromMatrix(p, right, up, -fwd)
end

function FairTrack.Height(track: Track, s: number): number
	local a, b, u = wrapIndex(track, s)
	return track.Height[a] + (track.Height[b] - track.Height[a]) * u
end

-- spec : { Launch = accélération au départ (studs/s²), Lift = { A, B, V } (montée à
-- vitesse constante entre les abscisses A et B), G (gravité, studs/s²),
-- Friction (0..), MinV, MaxV, Decel (freinage avant la gare), StartV, Cruise = vitesse constante (train fantôme, sans gravité) }
function FairTrack.Profile(track: Track, spec: any): Profile
	local N, step, L = track.N, track.Step, track.Length
	local speeds = table.create(N + 1, 0)
	local g = spec.G or 35
	local mu = spec.Friction or 0.012
	local minV = spec.MinV or 2.2
	local maxV = spec.MaxV or 30
	local launch = spec.Launch or 3
	local lift = spec.Lift
	local cruise = spec.Cruise
	local decel = spec.Decel or 3.2
	local startV = spec.StartV or 0
	local topH, topV = 0, 0
	if lift then
		topH = FairTrack.Height(track, lift.B)
		topV = lift.V
	end
	local maxSeen = 0
	for i = 0, N do
		local s = i * step
		local v
		if cruise then
			v = cruise
		elseif lift and s <= lift.B then
			v = if s >= lift.A then lift.V else math.min(lift.V, math.sqrt(startV * startV + 2 * launch * s))
		else
			local h = FairTrack.Height(track, s)
			local e = topV * topV + 2 * g * (topH - h) - 2 * mu * g * (s - (lift and lift.B or 0))
			v = math.clamp(math.sqrt(math.max(0, e)), minV, maxV)
		end
		-- départ en douceur (train fantôme aussi)
		v = math.min(v, math.sqrt(startV * startV + 2 * launch * s))
		-- freins avant la gare : on arrive à l'arrêt en douceur
		v = math.min(v, math.sqrt(startV * startV + 2 * decel * math.max(0, L - s)))
		speeds[i + 1] = v
		maxSeen = math.max(maxSeen, v)
	end
	local times = table.create(N + 1, 0)
	times[1] = 0
	for i = 2, N + 1 do
		local vm = (speeds[i - 1] + speeds[i]) / 2
		times[i] = times[i - 1] + step / math.max(0.2, vm)
	end
	return { Track = track, Times = times, Speeds = speeds, Lap = times[N + 1], MaxSpeed = maxSeen }
end

-- u secondes après le départ -> abscisse s (0 <= s <= Length)
function FairTrack.Distance(profile: Profile, u: number): number
	local times = profile.Times
	local n = #times
	if u <= 0 then
		return 0
	end
	if u >= times[n] then
		return profile.Track.Length
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= u then
			lo = mid
		else
			hi = mid
		end
	end
	-- accélération CONSTANTE dans l'intervalle (vitesse continue : aucune
	-- secousse d'une image à l'autre, même au départ de la gare)
	local span = times[hi] - times[lo]
	local step = profile.Track.Step
	if span <= 1e-9 then
		return (lo - 1) * step
	end
	local va, vb = profile.Speeds[lo], profile.Speeds[hi]
	local tau = u - times[lo]
	local ds = va * tau + 0.5 * (vb - va) / span * tau * tau
	-- (la vitesse moyenne de l'intervalle est bornée à 0,2 : on reste dedans)
	return (lo - 1) * step + math.clamp(ds * step / math.max(1e-6, (va + vb) / 2 * span), 0, step)
end

return FairTrack
