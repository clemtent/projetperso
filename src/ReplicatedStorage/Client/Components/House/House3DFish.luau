--[[
	House3DFish (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DFish

	🐠 (v11, ITEMS11) Les POISSONS des aquariums, vrais et VIVANTS.
	v10 : un ovale + un coin + un œil, figés au milieu de l'eau. Ici :
	  - de vrais poissons (repère House3DKit.Builder, en unités) : corps en
	    2 parties (avant / arrière), tête plus claire, yeux (blanc + pupille),
	    nageoire caudale en V, dorsale, pectorales, anale, et les marques de
	    chaque espèce : 🐟 poisson rouge (rond, double queue voilée), 🤡
	    poisson-clown (bandes blanches liserées de noir), 🔵 néon (bande bleu
	    vif + rouge, en BANC), 👼 scalaire (haut, rayé, longues nageoires),
	    💙 chirurgien bleu (queue jaune), 🎏 combattant (voiles pourpres), 🌈
	    guppy (queue colorée), 🦈 requin (gris, ventre blanc, aileron) ;
	  - l'ANIMATION (un seul Heartbeat pour tous les aquariums, branché tant
	    qu'il en existe, rien au-delà de FAR studs de la caméra, 30 i/s près,
	    15 plus loin) : trajectoires douces différentes pour chacun (courbes
	    de Lissajous, vitesse qui varie : il nage, ralentit, fait du
	    sur-place), demi-tours en arc (cap lissé, tangage limité), queue qui
	    bat (plus vite quand il accélère), ONDULATION du corps (l'arrière suit
	    la queue, la tête contre-balance un peu), pectorales qui battent au
	    sur-place, BANCS (les néons suivent un meneur, chacun à sa place), et
	    les BULLES qui montent du bulleur en zigzag ;
	  - toujours DANS l'eau : le volume de la pièce d'eau de la recette
	    (boîte, bocal sphérique, ou arche du tunnel), moins la taille du
	    poisson, au-dessus du décor du fond.
	Le mouvement se calcule dans le repère de la pièce d'eau : il suit
	l'objet déplacé (mode édition), mis à l'échelle, en miroir, dans le monde
	comme dans la vue 3D de l'interface. Aucune lumière, aucun son.

	API (recettes) :
	  House3DFish.Fish(b, species, x, y, z, length, dir?) -> Fish
	      species : "Goldfish" | "Clown" | "Neon" | "Angel" | "Tang" | "Betta" | "Guppy" | "Shark"
	  House3DFish.Tank(b, water, fishes, opts?)
	      water = la pièce d'eau (boîte ou bocal) ; opts :
	        Kind = "Box" (défaut) | "Bowl" | "Arch"
	        Floor = part du bas réservée au décor (0,3 ; 0..1 de la hauteur)
	        Bubbles = { BasePart }, Bubbler = Vector3 (unités, recette)
	        Arch = { Center = Vector3, Radius = r, Band = e, Depth = d } (unités)
	        RefCenter / RefSize (unités) : la boîte de `water` (Arch, Bubbler)
	  House3DFish.Species -> { string }   House3DFish.Count() -> nombre de poissons vivants
	  House3DFish.Path(seed, t, kind) (pur : position normalisée, testée hors jeu)
]]

local RunService = game:GetService("RunService")

local House3DFish = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = rgb(24, 22, 28)
local FAR = 80 -- (studs) au-delà : immobiles
local NEAR = 40 -- en deçà : 30 i/s, sinon 15
local TAU = math.pi * 2

----------------------------------------------------------------------
-- Espèces (unités : longueur L ; corps vers +X)
----------------------------------------------------------------------

type SpeciesDef = {
	Body: Color3, Belly: Color3, Fin: Color3, FinAlpha: number,
	H: number, T: number, -- hauteur, épaisseur (x L)
	Tail: number, -- taille de la caudale (x L)
	Dorsal: number, Anal: number,
	Bands: { { number } }?, -- { x, couleur(1 = blanc) }
	Stripe: Color3?, Stripe2: Color3?,
	Bars: number?, -- rayures verticales (scalaire)
	TailColor: Color3?,
	Speed: number, Depth: number, -- vitesse, profondeur préférée (-1 bas .. 1 haut)
	Shark: boolean?,
}

local SPECIES: { [string]: SpeciesDef } = {
	Goldfish = { Body = rgb(255, 136, 34), Belly = rgb(255, 196, 110), Fin = rgb(255, 160, 70), FinAlpha = 0.3, H = 0.56, T = 0.32, Tail = 0.62, Dorsal = 0.24, Anal = 0.1, Speed = 0.7, Depth = 0.1 },
	Clown = { Body = rgb(255, 120, 20), Belly = rgb(255, 160, 70), Fin = rgb(255, 130, 30), FinAlpha = 0, H = 0.48, T = 0.3, Tail = 0.34, Dorsal = 0.18, Anal = 0.1,
		Bands = { { 0.2 }, { -0.02 }, { -0.33 } }, Speed = 0.8, Depth = -0.2 },
	Neon = { Body = rgb(170, 186, 200), Belly = rgb(220, 226, 236), Fin = rgb(220, 230, 240), FinAlpha = 0.5, H = 0.3, T = 0.2, Tail = 0.3, Dorsal = 0.12, Anal = 0.1,
		Stripe = rgb(40, 210, 255), Stripe2 = rgb(236, 40, 60), Speed = 1.2, Depth = 0.25 },
	Angel = { Body = rgb(226, 230, 236), Belly = rgb(246, 246, 250), Fin = rgb(220, 224, 236), FinAlpha = 0.25, H = 0.92, T = 0.16, Tail = 0.4, Dorsal = 0.55, Anal = 0.55,
		Bars = 3, Speed = 0.55, Depth = 0.05 },
	Tang = { Body = rgb(40, 96, 230), Belly = rgb(70, 130, 240), Fin = rgb(30, 60, 160), FinAlpha = 0, H = 0.6, T = 0.2, Tail = 0.36, Dorsal = 0.2, Anal = 0.16,
		TailColor = rgb(255, 214, 40), Stripe = rgb(20, 24, 50), Speed = 1.0, Depth = 0 },
	Betta = { Body = rgb(150, 30, 120), Belly = rgb(190, 60, 150), Fin = rgb(120, 30, 170), FinAlpha = 0.25, H = 0.42, T = 0.24, Tail = 0.85, Dorsal = 0.4, Anal = 0.36, Speed = 0.45, Depth = 0.35 },
	Guppy = { Body = rgb(170, 190, 170), Belly = rgb(220, 230, 210), Fin = rgb(255, 120, 60), FinAlpha = 0.15, H = 0.32, T = 0.2, Tail = 0.5, Dorsal = 0.14, Anal = 0.08,
		TailColor = rgb(60, 150, 255), Speed = 1.1, Depth = 0.3 },
	Shark = { Body = rgb(120, 136, 160), Belly = rgb(232, 236, 244), Fin = rgb(110, 124, 150), FinAlpha = 0, H = 0.26, T = 0.24, Tail = 0.42, Dorsal = 0.3, Anal = 0.06, Speed = 0.9, Depth = 0, Shark = true },
}
House3DFish.Species = { "Goldfish", "Clown", "Neon", "Angel", "Tang", "Betta", "Guppy", "Shark" }

----------------------------------------------------------------------
-- Construction (recettes)
----------------------------------------------------------------------

export type Group = { Parts: { BasePart }, Kind: string, HingeX: number }
export type Fish = {
	Species: string,
	Body: BasePart, -- centre du corps
	Head: BasePart, -- (donne le sens du poisson une fois construit)
	HeadX: number, -- (unités) tête - corps, le long du poisson
	Length: number, -- (unités)
	Groups: { Group },
	School: number?, -- banc (même numéro : même meneur)
	Seed: number,
}

local function named(p: BasePart, name: string, alpha: number?): BasePart
	p.Name = name
	p.CastShadow = false
	if alpha and alpha > 0 then
		p.Transparency = alpha
	end
	return p
end

-- Un poisson (unités), centre (x, y, z), longueur L, tourné vers +X (dir 1) ou -X
function House3DFish.Fish(b: any, species: string, x: number, y: number, z: number, L: number, dir: number?): Fish
	local sp = SPECIES[species] or SPECIES.Goldfish
	local d = if (dir or 1) < 0 then -1 else 1
	local base = CFrame.new(x, y, z) * CFrame.Angles(0, if d < 0 then math.pi else 0, 0)
	local H, T = sp.H * L, sp.T * L
	local body: { BasePart } = {}
	local rear: { BasePart } = {}
	local tail: { BasePart } = {}
	local finL: { BasePart } = {}
	local finR: { BasePart } = {}
	local function egg(list: { BasePart }, name: string, cf: CFrame, w: number, h: number, t: number, color: Color3, alpha: number?, mat: Enum.Material?): BasePart
		local p = named(b.EggR(base * cf, w, h, t, color, mat or M.SmoothPlastic), name, alpha)
		table.insert(list, p)
		return p
	end
	local function wedge(list: { BasePart }, name: string, cf: CFrame, w: number, h: number, t: number, color: Color3, alpha: number?): BasePart
		local p = named(b.Part("WedgePart", base * cf, Vector3.new(t, h, w), color, M.SmoothPlastic, name), name, alpha)
		table.insert(list, p)
		return p
	end
	-- corps : avant (+ tête plus claire, ventre), arrière (pédoncule)
	local front = egg(body, "FishBody", CFrame.new(0.06 * L, 0, 0), 0.62 * L, H, T, sp.Body)
	egg(body, "FishBelly", CFrame.new(0.04 * L, -0.16 * H, 0), 0.5 * L, 0.62 * H, T * 0.94, sp.Belly)
	local headX = if sp.Shark then 0.34 * L else 0.28 * L
	local head = egg(body, "FishHead", CFrame.new(headX, -0.04 * H, 0), (if sp.Shark then 0.36 else 0.3) * L, H * 0.8, T * 0.9, sp.Body:Lerp(WHITE, 0.12))
	egg(rear, "FishRear", CFrame.new(-0.24 * L, 0.01 * H, 0), 0.5 * L, H * 0.62, T * 0.8, sp.Body:Lerp(BLACK, 0.06))
	-- yeux (blanc + pupille) sur les côtés de la tête
	local eyeX = headX + 0.06 * L
	local eye = math.max(0.06 * L, 0.6)
	for _, s in ipairs({ -1, 1 }) do
		egg(body, "FishEye", CFrame.new(eyeX, 0.1 * H, s * T * 0.36), eye, eye, eye * 0.5, WHITE)
		egg(body, "FishPupil", CFrame.new(eyeX + 0.01 * L, 0.1 * H, s * T * 0.42), eye * 0.6, eye * 0.6, eye * 0.32, BLACK)
	end
	-- bouche
	egg(body, "FishMouth", CFrame.new(headX + 0.15 * L, -0.08 * H, 0), 0.05 * L, 0.06 * L, T * 0.3, sp.Body:Lerp(BLACK, 0.35))
	-- nageoire dorsale, anale (sur l'arrière), pectorales (battent)
	if sp.Shark then
		wedge(body, "FishDorsal", CFrame.new(0, 0.5 * H + 0.12 * L, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.24 * L, 0.26 * L, 0.03 * L, sp.Fin)
	else
		egg(body, "FishDorsal", CFrame.new(-0.04 * L, 0.48 * H + sp.Dorsal * L * 0.3, 0) * CFrame.Angles(0, 0, -0.35), 0.36 * L, sp.Dorsal * L, 0.025 * L, sp.Fin, sp.FinAlpha)
	end
	egg(rear, "FishAnal", CFrame.new(-0.18 * L, -0.46 * H - sp.Anal * L * 0.25, 0) * CFrame.Angles(0, 0, 0.35), 0.26 * L, math.max(0.06 * L, sp.Anal * L), 0.025 * L, sp.Fin, sp.FinAlpha)
	for _, s in ipairs({ -1, 1 }) do
		local list = if s < 0 then finL else finR
		egg(list, "FishPectoral", CFrame.new(0.14 * L, -0.18 * H, s * T * 0.5) * CFrame.Angles(s * 0.5, 0, -0.5), (if sp.Shark then 0.26 else 0.16) * L, 0.05 * L, 0.12 * L, sp.Fin, sp.FinAlpha)
	end
	-- caudale en V (2 lobes) ; voiles : 2 lobes de plus, transparents
	local tc = sp.TailColor or sp.Fin
	local tl = sp.Tail * L
	local tailX = -0.46 * L - tl * 0.3
	-- pédoncule : relie l'arrière du corps à la queue (pas de trou)
	egg(rear, "FishPeduncle", CFrame.new(-0.45 * L, 0, 0), 0.16 * L, H * 0.32, T * 0.5, sp.Body:Lerp(BLACK, 0.06))
	local upper = if sp.Shark then 1.25 else 1
	egg(tail, "FishTail", CFrame.new(tailX, tl * 0.28 * upper, 0) * CFrame.Angles(0, 0, 0.62), tl * 0.75, tl * 0.32 * upper, 0.03 * L, tc, sp.FinAlpha)
	egg(tail, "FishTail", CFrame.new(tailX, -tl * 0.28, 0) * CFrame.Angles(0, 0, -0.62), tl * 0.75, tl * 0.32, 0.03 * L, tc, sp.FinAlpha)
	if sp.Tail >= 0.6 then
		egg(tail, "FishVeil", CFrame.new(tailX - tl * 0.2, 0, 0), tl * 0.9, tl * 0.8, 0.02 * L, tc:Lerp(WHITE, 0.15), math.max(0.35, sp.FinAlpha + 0.15))
	end
	-- marques de l'espèce
	if sp.Bands then
		for _, band in ipairs(sp.Bands) do
			local bx = band[1] * L
			local list = if bx < -0.15 * L then rear else body
			local scale = if bx < -0.15 * L then 0.66 else 1
			egg(list, "FishBandEdge", CFrame.new(bx, 0, 0), 0.11 * L, H * 0.96 * scale, T * 1.04 * scale, BLACK)
			egg(list, "FishBand", CFrame.new(bx, 0, 0), 0.08 * L, H * 0.98 * scale, T * 1.08 * scale, WHITE)
		end
	end
	if sp.Stripe then
		egg(body, "FishStripe", CFrame.new(0.02 * L, 0.06 * H, 0), 0.62 * L, 0.12 * H + 0.02 * L, T * 1.04, sp.Stripe)
	end
	if sp.Stripe2 then
		egg(rear, "FishStripe2", CFrame.new(-0.22 * L, -0.12 * H, 0), 0.4 * L, 0.2 * H, T * 0.86, sp.Stripe2)
	end
	if sp.Bars then
		for k = 1, sp.Bars do
			local bx = (0.22 - (k - 1) * 0.22) * L
			egg(if bx < -0.15 * L then rear else body, "FishBar", CFrame.new(bx, 0, 0), 0.05 * L, H * (0.9 - 0.12 * (k - 1)), T * 1.06, rgb(40, 40, 46))
		end
	end
	local fish: Fish = {
		Species = species,
		Body = front,
		Head = head,
		HeadX = headX - 0.06 * L,
		Length = L,
		Groups = {
			{ Parts = body, Kind = "body", HingeX = 0 },
			{ Parts = rear, Kind = "rear", HingeX = -0.06 * L },
			{ Parts = tail, Kind = "tail", HingeX = -0.47 * L },
			{ Parts = finL, Kind = "finL", HingeX = 0.14 * L },
			{ Parts = finR, Kind = "finR", HingeX = 0.14 * L },
		},
		Seed = math.floor((x * 7.13 + y * 3.71 + z * 1.93 + L * 11.1) * 1000) % 100000,
	}
	return fish
end

----------------------------------------------------------------------
-- Trajectoires (pur)
----------------------------------------------------------------------

local function hash(seed: number, k: number): number
	local v = math.sin(seed * 12.9898 + k * 78.233) * 43758.5453
	return v - math.floor(v)
end

-- Temps "nagé" τ(t) et vitesse relative s(t) (0,3..1 : nage, ralentit, sur-place)
local function swimTime(seed: number, t: number, speed: number): (number, number)
	local w = 0.09 + 0.08 * hash(seed, 9)
	local ph = hash(seed, 10) * TAU
	local s = 0.65 + 0.35 * math.sin(w * t + ph)
	local tau = (0.65 * t - (0.35 / w) * math.cos(w * t + ph)) * speed
	return tau, s * speed
end

-- Position normalisée (-1..1 sur chaque axe de la boîte, ou du bocal) au
-- temps nagé τ ; amplitudes A (déjà réduites de la taille du poisson)
function House3DFish.Path(seed: number, tau: number, kind: string, A: Vector3, depth: number): Vector3
	local wx = 0.16 + 0.1 * hash(seed, 1)
	local wz = 0.27 + 0.16 * hash(seed, 2)
	local wy = 0.08 + 0.07 * hash(seed, 3)
	local px, pz, py = hash(seed, 4) * TAU, hash(seed, 5) * TAU, hash(seed, 6) * TAU
	if kind == "Bowl" then
		-- (bocal : un cercle qui tourne lentement, rayon et hauteur qui varient)
		local r = 0.55 + 0.25 * math.sin(wz * tau + pz)
		local a = wx * 1.6 * tau + px
		return Vector3.new(math.cos(a) * r * A.X, math.sin(wy * tau + py) * 0.45 * A.Y + depth * 0.3 * A.Y, math.sin(a) * r * A.Z)
	end
	local yy = math.clamp(depth * 0.5 + math.sin(wy * tau + py) * 0.55, -1, 1)
	return Vector3.new(math.sin(wx * tau + px) * A.X, yy * A.Y, math.sin(wz * tau + pz) * A.Z)
end

----------------------------------------------------------------------
-- Aquariums vivants
----------------------------------------------------------------------

type Live = {
	Fish: Fish,
	Def: SpeciesDef,
	Offsets: { { Part: BasePart, Off: CFrame, Group: string } },
	Hinges: { [string]: Vector3 },
	HalfLen: number, HalfH: number,
	Heading: Vector3?, -- (repère de l'eau)
	Phase: number,
}

type Tank = {
	Water: BasePart,
	Kind: string,
	Floor: number,
	Fishes: { Fish },
	Live: { Live }?,
	Size: Vector3?, -- taille de l'eau à la capture (studs)
	Bubbles: { BasePart },
	BubbleOff: { Vector3 }, -- (repère de l'eau, studs)
	Bubbler: Vector3?, -- (normalisé)
	Arch: any?,
	RefCenter: Vector3?, RefSize: Vector3?,
	Acc: number,
}

local tanks: { [BasePart]: Tank } = {}
local connection: RBXScriptConnection? = nil
local clock = 0

function House3DFish.Count(): number
	local n = 0
	for _, tank in pairs(tanks) do
		n += #tank.Fishes
	end
	return n
end

-- Repères de chaque pièce par rapport au poisson (à la 1re image où l'aquarium est en place)
local function capture(tank: Tank): boolean
	local water = tank.Water
	local live: { Live } = {}
	local wcf = water.CFrame
	for _, fish in ipairs(tank.Fishes) do
		local body, head = fish.Body, fish.Head
		if not body.Parent or not head.Parent then
			continue
		end
		local delta = head.Position - body.Position
		if delta.Magnitude < 1e-4 then
			continue
		end
		local fwd = delta.Unit
		local up = wcf.UpVector
		local side = fwd:Cross(up)
		if side.Magnitude < 1e-4 then
			continue
		end
		side = side.Unit
		up = side:Cross(fwd)
		local frame0 = CFrame.fromMatrix(body.Position, fwd, up, fwd:Cross(up))
		local k = delta.Magnitude / math.max(0.01, fish.HeadX)
		local entry: Live = { Fish = fish, Def = SPECIES[fish.Species] or SPECIES.Goldfish, Offsets = {}, Hinges = {}, HalfLen = 0, HalfH = 0, Heading = nil, Phase = hash(fish.Seed, 20) * TAU }
		for _, g in ipairs(fish.Groups) do
			entry.Hinges[g.Kind] = Vector3.new(g.HingeX * k, 0, 0)
			for _, p in ipairs(g.Parts) do
				local off = frame0:ToObjectSpace(p.CFrame)
				table.insert(entry.Offsets, { Part = p, Off = off, Group = g.Kind })
				local e = p.Size / 2
				entry.HalfLen = math.max(entry.HalfLen, math.abs(off.X) + e.X * 0.6)
				entry.HalfH = math.max(entry.HalfH, math.abs(off.Y) + e.Y * 0.6)
			end
		end
		-- (les pectorales battent autour de leur racine, côté corps)
		for _, o in ipairs(entry.Offsets) do
			if o.Group == "finL" or o.Group == "finR" then
				entry.Hinges[o.Group] = Vector3.new(o.Off.X, o.Off.Y, o.Off.Z * 0.6)
			end
		end
		table.insert(live, entry)
	end
	tank.Live = live
	tank.Size = water.Size
	-- bulles : repère de l'eau
	tank.BubbleOff = {}
	for _, bubble in ipairs(tank.Bubbles) do
		table.insert(tank.BubbleOff, wcf:PointToObjectSpace(bubble.Position))
	end
	return #live > 0
end

-- Unités de la recette -> normalisé dans la boîte de l'eau
local function norm(tank: Tank, p: Vector3): Vector3
	local c, s = tank.RefCenter or Vector3.zero, tank.RefSize or Vector3.one
	return Vector3.new((p.X - c.X) / (s.X / 2), (p.Y - c.Y) / (s.Y / 2), (p.Z - c.Z) / (s.Z / 2))
end

local function poseTank(tank: Tank, t: number, dt: number, parts: { BasePart }, cfs: { CFrame })
	local water = tank.Water
	local wcf = water.CFrame
	local half = water.Size / 2
	local leaders: { [number]: Vector3 } = {}
	for index, f in ipairs(tank.Live or {}) do
		local fish, sp = f.Fish, f.Def
		local seed = if fish.School then fish.School * 131 + 7 else fish.Seed
		local tau, s = swimTime(seed, t, sp.Speed)
		-- marges : la taille du poisson (studs -> normalisé), le décor au fond
		local mx = math.clamp(1 - (f.HalfLen + 0.05) / math.max(0.05, half.X), 0.05, 0.95)
		local mz = math.clamp(1 - (f.HalfLen + 0.05) / math.max(0.05, half.Z), 0.05, 0.95)
		local my = math.clamp(1 - (f.HalfH + 0.05) / math.max(0.05, half.Y), 0.05, 0.95)
		local n: Vector3
		local n2: Vector3
		if tank.Kind == "Arch" and tank.Arch then
			local A = tank.Arch
			local function archAt(tt: number): Vector3
				local th = math.pi / 2 + 0.34 * math.pi * math.sin(0.11 * tt + hash(seed, 11) * TAU)
				local r = A.Radius + A.Band * 0.5 + A.Band * 0.18 * math.sin(0.23 * tt + hash(seed, 12) * TAU)
				local zz = (A.Depth * 0.5 - fish.Length * 0.7) * math.sin(0.19 * tt + hash(seed, 13) * TAU)
				return norm(tank, A.Center + Vector3.new(math.cos(th) * r, math.sin(th) * r, zz))
			end
			n = archAt(tau)
			n2 = archAt(tau + 0.05)
		else
			local floor = if tank.Kind == "Bowl" then 0 else tank.Floor
			-- (le bas réservé au décor : on resserre la hauteur et on remonte le centre)
			local A = Vector3.new(mx, my * (1 - floor), mz)
			local lift = my * floor
			n = House3DFish.Path(seed, tau, tank.Kind, A, sp.Depth) + Vector3.new(0, lift, 0)
			n2 = House3DFish.Path(seed, tau + 0.05, tank.Kind, A, sp.Depth) + Vector3.new(0, lift, 0)
		end
		-- banc : chacun à sa place derrière / à côté du meneur
		if fish.School then
			local lead = leaders[fish.School]
			if not lead then
				leaders[fish.School] = n
			end
			local off = Vector3.new((hash(fish.Seed, 21) - 0.5) * 0.36, (hash(fish.Seed, 22) - 0.5) * 0.3, (hash(fish.Seed, 23) - 0.5) * 0.5)
			local wob = Vector3.new(0, math.sin(t * 1.3 + f.Phase) * 0.03, math.sin(t * 0.9 + f.Phase) * 0.04)
			n += off + wob
			n2 += off + wob
		end
		n = Vector3.new(math.clamp(n.X, -mx, mx), math.clamp(n.Y, -my, my), math.clamp(n.Z, -mz, mz))
		local pos = n * half
		local vel = (n2 - (n - Vector3.zero)) * half
		-- cap lissé (demi-tours en arc), tangage limité à ~25°
		local want = if vel.Magnitude > 1e-4 then vel.Unit else (f.Heading or Vector3.new(1, 0, 0))
		local flat = Vector3.new(want.X, 0, want.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(1, 0, 0)
		end
		want = (flat.Unit * math.cos(math.rad(25)) + Vector3.new(0, math.clamp(want.Y, -0.42, 0.42), 0)).Unit
		local head = f.Heading or want
		local turn = math.min(1, dt * 2.6)
		head = head:Lerp(want, turn)
		if head.Magnitude < 1e-3 then
			head = want
		end
		head = head.Unit
		f.Heading = head
		-- repère du poisson dans le monde (X = avant, Y = haut de l'eau)
		local fwd = wcf:VectorToWorldSpace(head)
		local up = wcf.UpVector
		local side = fwd:Cross(up)
		if side.Magnitude < 1e-4 then
			side = wcf.RightVector
		end
		side = side.Unit
		up = side:Cross(fwd)
		local frame = CFrame.fromMatrix(wcf * pos, fwd, up, fwd:Cross(up))
		-- queue qui bat (plus vite et plus fort quand il nage vite), corps qui ondule
		local speed = math.clamp(s / math.max(0.2, sp.Speed), 0.2, 1)
		local freq = 1.2 + 3.2 * speed
		local tailA = (0.18 + 0.28 * speed) * math.sin(t * freq * TAU / 2 + f.Phase)
		local rearA = tailA * 0.45
		local headA = -tailA * 0.12
		local flap = (0.25 + 0.35 * (1 - speed)) * math.sin(t * 5.5 + f.Phase)
		local hBody, hRear, hTail = f.Hinges.body, f.Hinges.rear, f.Hinges.tail
		local rotBody = CFrame.new(hBody) * CFrame.Angles(0, headA, 0) * CFrame.new(-hBody)
		local rotRear = CFrame.new(hRear) * CFrame.Angles(0, rearA, 0) * CFrame.new(-hRear)
		local rotTail = rotRear * CFrame.new(hTail) * CFrame.Angles(0, tailA, 0) * CFrame.new(-hTail)
		local hL, hR = f.Hinges.finL, f.Hinges.finR
		local rotL = CFrame.new(hL) * CFrame.Angles(flap, 0, 0) * CFrame.new(-hL)
		local rotR = CFrame.new(hR) * CFrame.Angles(-flap, 0, 0) * CFrame.new(-hR)
		for _, o in ipairs(f.Offsets) do
			local g = o.Group
			local r = if g == "rear" then rotRear elseif g == "tail" then rotTail elseif g == "finL" then rotBody * rotL elseif g == "finR" then rotBody * rotR else rotBody
			table.insert(parts, o.Part)
			table.insert(cfs, frame * r * o.Off)
		end
		local _ = index
	end
	-- bulles : montent du bulleur en zigzag, reviennent en bas
	local nb = #tank.Bubbles
	if nb > 0 then
		local src = tank.Bubbler
		local base = if src then src * half else Vector3.new(half.X * 0.7, -half.Y * 0.8, half.Z * 0.2)
		local top = half.Y * 0.92
		for i, bubble in ipairs(tank.Bubbles) do
			local phase = (t * 0.32 + i / nb) % 1
			local y = base.Y + (top - base.Y) * phase
			local wig = math.sin(t * 6 + i * 1.7) * half.X * 0.025 * (0.3 + phase)
			local p = Vector3.new(base.X + wig, y, base.Z + math.cos(t * 5 + i) * half.Z * 0.02)
			table.insert(parts, bubble)
			table.insert(cfs, wcf * CFrame.new(p))
		end
	end
end

local function step(dt: number)
	clock += dt
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	local alive = false
	for water, tank in pairs(tanks) do
		if water.Parent == nil then
			tanks[water] = nil
			continue
		end
		alive = true
		local inWorld = water:IsDescendantOf(workspace)
		local dist = if eye and inWorld then (water.Position - eye).Magnitude else 0
		if dist > FAR then
			continue
		end
		tank.Acc += dt
		local period = if dist <= NEAR then 1 / 30 else 1 / 15
		if tank.Acc < period then
			continue
		end
		local tdt = math.min(tank.Acc, 0.25)
		tank.Acc = 0
		if not tank.Live or not tank.Size or (tank.Size - water.Size).Magnitude > 1e-3 then
			if not capture(tank) then
				continue
			end
		end
		poseTank(tank, clock, tdt, parts, cfs)
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if not alive and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureRunning()
	if connection or not RunService:IsClient() then
		return
	end
	connection = RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(step, math.min(dt, 0.1))
		if not ok then
			warn("[House3DFish] " .. tostring(err))
		end
	end)
end

-- Rend un aquarium vivant. `water` = pièce d'eau (boîte / bocal) de la recette
function House3DFish.Tank(b: any, water: BasePart, fishes: { Fish }, opts: any?)
	local o = opts or {}
	local tank: Tank = {
		Water = water,
		Kind = o.Kind or "Box",
		Floor = math.clamp(tonumber(o.Floor) or 0.3, 0, 0.8),
		Fishes = fishes,
		Live = nil,
		Size = nil,
		Bubbles = o.Bubbles or {},
		BubbleOff = {},
		Bubbler = nil,
		Arch = o.Arch,
		RefCenter = o.RefCenter,
		RefSize = o.RefSize,
		Acc = 1,
	}
	if o.Bubbler and o.RefCenter and o.RefSize then
		tank.Bubbler = norm(tank, o.Bubbler)
	end
	for _, bubble in ipairs(tank.Bubbles) do
		bubble.Name = "Bubble"
		bubble.CastShadow = false
	end
	tanks[water] = tank
	water:SetAttribute("FishTank", #fishes)
	local _ = b
	ensureRunning()
end

-- (tests hors jeu : une image d'animation tout de suite, sans Heartbeat)
function House3DFish.StepNow(dt: number)
	step(dt)
end

return House3DFish
