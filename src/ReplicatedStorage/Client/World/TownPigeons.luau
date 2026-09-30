--[[
	TownPigeons (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownPigeons

	🐦 Les pigeons de la place centrale, côté CLIENT (appelé par
	TownPlazaFx : construit avec la place, animé à chaque image de près, à
	30 Hz plus loin, en pause au loin).
	v9.9 (CITY99) : "100x plus réalistes" (v9.8 : "c'est dég") :
	  - ANATOMIE d'un vrai pigeon biset à l'échelle de l'avatar (~32 cm =
	    1 stud de long, ~0,8 stud debout) : corps fuselé en ellipsoïdes qui
	    se fondent (dos, ventre, poitrail rosé, croupion clair, sous-caudales),
	    cou IRISÉ vert + violet (reflets), tête ronde qui prolonge le cou,
	    bec fin avec sa CIRE blanche, yeux orange à pupille noire ;
	  - PLUMAGE en couches : ailes repliées le long du dos avec leurs deux
	    BARRES noires posées sur la couverture (plus de blocs qui dépassent),
	    rémiges sombres qui se croisent sur la queue, queue en deux moitiés
	    qui s'ÉVENTAIL à l'atterrissage, bande terminale sombre ;
	  - pattes fines corail, 3 doigts (2 devant, 1 derrière) ;
	  - 6 plumages : biset, écaillé, argenté, rouge cendré, sombre, pie ;
	  - MARCHE : un pas = un hochement de tête ; la tête reste IMMOBILE dans
	    l'espace pendant que le corps avance, puis se projette en avant (le
	    vrai mouvement du pigeon), pattes alternées, léger roulis ;
	    virages progressifs (plus de rotation instantanée) ;
	  - picore (le corps bascule, 2 à 3 coups de bec), tourne la tête par
	    à-coups, fait sa toilette, roucoule (courbettes, queue étalée qui
	    traîne, petit tour sur lui-même), s'ébroue ;
	  - ENVOL en groupe (quelqu'un arrive trop près, ou de temps en temps) :
	    accroupi, bond, battements rapides, montée, un TOUR de la place en
	    formation (ailes en V, inclinés dans le virage, battements par
	    rafales), puis descente en plané et ATTERRISSAGE freiné (ailes hautes,
	    queue en éventail, pattes en avant) et ailes repliées ; trajectoires
	    en courbes d'Hermite : position et vitesse continues, sans à-coup ;
	  - quelqu'un approche doucement : on s'écarte en marchant ;
	  - JAMAIS deux pigeons l'un dans l'autre : places d'atterrissage
	    choisies libres, pas bloqué par un voisin, séparation au sol
	    (distance mini 2 x BIRD_R), formation de vol décalée, un pigeon par
	    perchoir (lanternes, margelle de la fontaine).
	Tout est ancré, sans collision, animé par CFrame (BulkMoveTo). Aucune
	création d'instance par image. Aucun son.

	API (TownPlazaFx) :
	  TownPigeons.Build(folder, plaza) -> état   (plaza : dossier Plaza, attributs Fx…)
	  TownPigeons.Step(état, dt, avatar: Vector3?)
	  TownPigeons.Count(état) -> number
	  TownPigeons.Near(état, point, radius) -> boolean  (animer à chaque image ?)
	  TownPigeons.Debug(état) -> table  (écart mini au sol, modes…)
]]

local TownPigeons = {}

local M = Enum.Material
local rgb = Color3.fromRGB

local capsuleGap: (a: any, b: any) -> (number, Vector3, Vector3)
local bodyClear: (P: any, me: any, pos: Vector3, yaw: number) -> number

local PER_FLOCK = 5
local BIRD_R = 0.46 -- (studs) demi-distance mini entre deux pigeons au sol
local BODY_HALF = 0.21 -- demi-largeur d'un corps (vu du dessus)
local CAPSULE_MARGIN = 0.06 -- espace gardé entre deux corps
local LAND_GAP = 1.32 -- place d'atterrissage : libre quel que soit le cap (bec 0,5 + queue 0,72 + marge)
local WALK_SPEED = 1.05
local STEP_T = 0.3 -- (s) un pas (= un hochement de tête)
local SCARE_R = 3.6 -- quelqu'un plus près : le groupe s'envole
local WARY_R = 6.5 -- plus près : on s'écarte en marchant
local HOME_R = 4 -- rayon où picore un groupe
local FLY_SPEED = 13
local PERCH_MIN, PERCH_MAX = 8, 18
local RELOCATE_MIN, RELOCATE_MAX = 50, 120 -- (s) un groupe fait un tour de temps en temps

-- Groupes de pièces (chacun a son pivot)
local G_BODY, G_HEAD, G_WING_L, G_WING_R, G_LEG_L, G_LEG_R, G_TAIL_L, G_TAIL_R = 0, 1, 2, 3, 4, 5, 6, 7

-- Pivots (repère du pigeon : pieds au sol, bec vers -Z, +X à droite)
local NECK_P = CFrame.new(0, 0.5, -0.24)
local NECK_INV = NECK_P:Inverse()
local SHOULDER = { CFrame.new(-0.15, 0.5, -0.1), CFrame.new(0.15, 0.5, -0.1) }
local SHOULDER_INV = { SHOULDER[1]:Inverse(), SHOULDER[2]:Inverse() }
local WRIST = { CFrame.new(-0.62, 0.5, -0.06), CFrame.new(0.62, 0.5, -0.06) }
local WRIST_INV = { WRIST[1]:Inverse(), WRIST[2]:Inverse() }
local HIP = { CFrame.new(-0.065, 0.22, 0.02), CFrame.new(0.065, 0.22, 0.02) }
local HIP_INV = { HIP[1]:Inverse(), HIP[2]:Inverse() }
local TAIL_P = CFrame.new(0, 0.4, 0.3)
local TAIL_INV = TAIL_P:Inverse()

-- Aile dépliée : le X de la pièce (épaisseur) -> vers le haut, son Y
-- (largeur) -> la corde (vers l'arrière), son Z (longueur) -> l'envergure
local function openAt(x: number, y: number, z: number, sweep: number?): CFrame
	local base = CFrame.fromMatrix(Vector3.new(x, y, z), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
	if sweep then
		return CFrame.new(x, y, z) * CFrame.Angles(0, sweep, 0) * (CFrame.new(x, y, z):Inverse() * base)
	end
	return base
end

-- Barre d'aile dépliée : X de la pièce -> haut, Y (longueur) -> envergure, Z -> corde
local function openBar(x: number, y: number, z: number): CFrame
	return CFrame.fromMatrix(Vector3.new(x, y, z), Vector3.new(0, 1, 0), Vector3.new(1, 0, 0))
end

type Spec = {
	Name: string,
	Size: Vector3,
	Shape: string,
	Color: string,
	Group: number,
	Fold: CFrame,
	Open: CFrame?,
	Hand: boolean?, -- rémiges : pliées au poignet en plus
	Shine: number?,
}

-- Pièces d'un pigeon (36) : construites une fois pour toutes
local SPECS: { Spec } = {}
local function spec(name: string, size: Vector3, shape: string, color: string, group: number, fold: CFrame, open: CFrame?, hand: boolean?, shine: number?)
	table.insert(SPECS, { Name = name, Size = size, Shape = shape, Color = color, Group = group, Fold = fold, Open = open, Hand = hand, Shine = shine })
end
do
	local rx = function(d: number): CFrame
		return CFrame.Angles(math.rad(d), 0, 0)
	end
	-- corps : dos (un peu relevé devant), ventre, poitrail, croupion, sous-caudales
	spec("Body", Vector3.new(0.4, 0.37, 0.78), "Egg", "Body", G_BODY, CFrame.new(0, 0.37, 0.04) * rx(8))
	spec("Belly", Vector3.new(0.35, 0.25, 0.5), "Egg", "Belly", G_BODY, CFrame.new(0, 0.29, 0.03))
	spec("Breast", Vector3.new(0.37, 0.4, 0.4), "Egg", "Breast", G_BODY, CFrame.new(0, 0.43, -0.19))
	spec("Rump", Vector3.new(0.28, 0.2, 0.34), "Egg", "Rump", G_BODY, CFrame.new(0, 0.44, 0.29) * rx(-6))
	spec("UnderTail", Vector3.new(0.19, 0.1, 0.3), "Egg", "Belly", G_BODY, CFrame.new(0, 0.33, 0.42) * rx(-12))
	-- tête + cou (pivot : base du cou)
	-- (le cou est gris-bleu devant ; le VERT irisé sur les côtés du haut du
	-- cou, le VIOLET en bas : deux plaques par côté, un peu brillantes)
	spec("Neck", Vector3.new(0.25, 0.36, 0.26), "Egg", "Head", G_HEAD, CFrame.new(0, 0.58, -0.27) * rx(-18))
	spec("NeckSheen", Vector3.new(0.27, 0.2, 0.25), "Egg", "Sheen", G_HEAD, CFrame.new(0, 0.51, -0.25) * rx(-10), nil, nil, 0.16)
	for _, sx in ipairs({ -1, 1 }) do
		spec("NeckGreen", Vector3.new(0.12, 0.24, 0.2), "Egg", "Neck", G_HEAD, CFrame.new(sx * 0.07, 0.6, -0.26) * rx(-18), nil, nil, 0.2)
	end
	spec("Head", Vector3.new(0.22, 0.22, 0.27), "Egg", "Head", G_HEAD, CFrame.new(0, 0.76, -0.37) * rx(-6))
	spec("Beak", Vector3.new(0.045, 0.045, 0.15), "Egg", "Beak", G_HEAD, CFrame.new(0, 0.735, -0.525) * rx(-12))
	spec("Cere", Vector3.new(0.058, 0.04, 0.065), "Egg", "Cere", G_HEAD, CFrame.new(0, 0.766, -0.482))
	for _, sx in ipairs({ -1, 1 }) do
		-- œil à fleur de tête (lentille aplatie), pupille au centre
		spec("Eye", Vector3.new(0.03, 0.062, 0.062), "Egg", "Eye", G_HEAD, CFrame.new(sx * 0.094, 0.787, -0.425))
		spec("Pupil", Vector3.new(0.014, 0.03, 0.03), "Egg", "Pupil", G_HEAD, CFrame.new(sx * 0.106, 0.788, -0.427))
	end
	-- ailes : couverture (+ 2 barres) et rémiges ; pliées le long du dos /
	-- dépliées (envergure totale ~2,2 studs = ~70 cm, comme un vrai)
	for i, sx in ipairs({ -1, 1 }) do
		local g = i == 1 and G_WING_L or G_WING_R
		local s = SHOULDER[i].Position
		spec("Wing", Vector3.new(0.11, 0.28, 0.66), "Egg", "Wing", g, CFrame.new(sx * 0.172, 0.43, 0.1) * rx(6) * CFrame.Angles(0, 0, sx * math.rad(-6)), openAt(s.X + sx * 0.33, s.Y, s.Z + 0.05))
		-- 2 barres noires : bandes obliques sur l'arrière de l'aile repliée,
		-- bandes le long de l'envergure sur l'aile ouverte
		spec("WingBar", Vector3.new(0.03, 0.2, 0.06), "Egg", "Bar", g, CFrame.new(sx * 0.214, 0.43, 0.14) * rx(28), openBar(s.X + sx * 0.36, s.Y + 0.046, s.Z + 0.1))
		spec("WingBar", Vector3.new(0.03, 0.19, 0.06), "Egg", "Bar", g, CFrame.new(sx * 0.206, 0.42, 0.27) * rx(28), openBar(s.X + sx * 0.3, s.Y + 0.046, s.Z + 0.17))
		spec("Primaries", Vector3.new(0.07, 0.16, 0.48), "Egg", "Prim", g, CFrame.new(sx * 0.105, 0.44, 0.46) * rx(-5) * CFrame.Angles(0, sx * math.rad(4), 0), openAt(s.X + sx * 0.84, s.Y, s.Z + 0.12, sx * math.rad(-14)), true)
	end
	-- queue en deux moitiés (éventail) + bande terminale sombre
	for i, sx in ipairs({ -1, 1 }) do
		local g = i == 1 and G_TAIL_L or G_TAIL_R
		local t = TAIL_P * rx(-9)
		spec("Tail", Vector3.new(0.15, 0.045, 0.44), "Egg", "Tail", g, t * CFrame.new(sx * 0.036, 0, 0.24))
		spec("TailBand", Vector3.new(0.158, 0.052, 0.12), "Egg", "Band", g, t * CFrame.new(sx * 0.036, -0.002, 0.4))
	end
	-- pattes (cachées en haut sous le ventre) + 3 doigts
	for i, sx in ipairs({ -1, 1 }) do
		local g = i == 1 and G_LEG_L or G_LEG_R
		local x = sx * 0.065
		spec("Leg", Vector3.new(0.045, 0.21, 0.05), "Egg", "Leg", g, CFrame.new(x, 0.12, 0.02))
		spec("Toe", Vector3.new(0.028, 0.024, 0.13), "Egg", "Leg", g, CFrame.new(x - 0.018, 0.013, -0.035) * CFrame.Angles(0, math.rad(22), 0))
		spec("Toe", Vector3.new(0.028, 0.024, 0.13), "Egg", "Leg", g, CFrame.new(x + 0.018, 0.013, -0.035) * CFrame.Angles(0, math.rad(-22), 0))
		spec("Toe", Vector3.new(0.026, 0.022, 0.08), "Egg", "Leg", g, CFrame.new(x, 0.012, 0.055))
	end
end

-- Plumages (tons réels du pigeon biset et de ses variantes de ville)
local PLUMES = {
	-- biset "barré" classique
	{ Body = rgb(148, 156, 174), Belly = rgb(140, 148, 166), Breast = rgb(152, 140, 160), Rump = rgb(176, 182, 196), Head = rgb(116, 122, 144), Neck = rgb(70, 132, 108), Sheen = rgb(128, 80, 146), Wing = rgb(172, 178, 192), Bar = rgb(34, 34, 42), Prim = rgb(70, 74, 88), Tail = rgb(136, 142, 160), Band = rgb(40, 40, 48) },
	-- écaillé (ailes mouchetées plus sombres)
	{ Body = rgb(118, 122, 138), Belly = rgb(112, 116, 132), Breast = rgb(126, 108, 126), Rump = rgb(140, 144, 158), Head = rgb(92, 96, 116), Neck = rgb(62, 120, 100), Sheen = rgb(112, 70, 132), Wing = rgb(106, 110, 124), Bar = rgb(46, 46, 56), Prim = rgb(56, 58, 70), Tail = rgb(110, 114, 130), Band = rgb(36, 36, 44) },
	-- argenté (clair)
	{ Body = rgb(196, 198, 206), Belly = rgb(188, 190, 198), Breast = rgb(198, 184, 194), Rump = rgb(214, 214, 220), Head = rgb(160, 162, 178), Neck = rgb(104, 158, 134), Sheen = rgb(158, 110, 170), Wing = rgb(212, 212, 218), Bar = rgb(92, 92, 104), Prim = rgb(124, 124, 136), Tail = rgb(186, 188, 196), Band = rgb(96, 96, 106) },
	-- rouge cendré (brun rosé, barres brunes)
	{ Body = rgb(178, 152, 142), Belly = rgb(170, 146, 138), Breast = rgb(184, 140, 136), Rump = rgb(196, 178, 170), Head = rgb(142, 114, 110), Neck = rgb(120, 136, 96), Sheen = rgb(150, 90, 120), Wing = rgb(198, 176, 162), Bar = rgb(120, 70, 64), Prim = rgb(122, 98, 92), Tail = rgb(170, 148, 140), Band = rgb(112, 76, 70) },
	-- sombre (mélanique)
	{ Body = rgb(74, 76, 88), Belly = rgb(70, 72, 84), Breast = rgb(84, 74, 88), Rump = rgb(86, 88, 100), Head = rgb(62, 64, 76), Neck = rgb(52, 108, 90), Sheen = rgb(96, 60, 116), Wing = rgb(84, 86, 98), Bar = rgb(28, 28, 34), Prim = rgb(46, 48, 58), Tail = rgb(70, 72, 84), Band = rgb(30, 30, 36) },
	-- pie (blanc taché de gris)
	{ Body = rgb(234, 232, 230), Belly = rgb(240, 238, 236), Breast = rgb(226, 214, 218), Rump = rgb(244, 242, 240), Head = rgb(150, 154, 170), Neck = rgb(98, 150, 126), Sheen = rgb(150, 104, 164), Wing = rgb(236, 234, 232), Bar = rgb(150, 152, 162), Prim = rgb(120, 122, 134), Tail = rgb(220, 220, 222), Band = rgb(120, 122, 132) },
}
local FIXED = { Beak = rgb(58, 50, 54), Cere = rgb(234, 230, 224), Eye = rgb(232, 112, 36), Pupil = rgb(16, 14, 16), Leg = rgb(212, 92, 102) }

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function newPart(parent: Instance, s: Spec, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = s.Name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = s.Size
	p.Color = color
	p.Material = M.SmoothPlastic
	p.Reflectance = s.Shine or 0
	if s.Shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local function plumeFor(seed: number): { [string]: Color3 }
	if seed % 11 == 0 then
		return PLUMES[6]
	elseif seed % 7 == 0 then
		return PLUMES[4]
	elseif seed % 5 == 0 then
		return PLUMES[5]
	elseif seed % 4 == 0 then
		return PLUMES[3]
	elseif seed % 3 == 0 then
		return PLUMES[2]
	end
	return PLUMES[1]
end

local function vec3Attr(folder: Instance, name: string): Vector3?
	local v = folder:GetAttribute(name)
	return typeof(v) == "Vector3" and v or nil
end

-- Perchoirs : dessus des lanternes des lampadaires de la place, margelle de
-- la fontaine (milieu de chaque pan)
local function perches(plaza: Instance): { Vector3 }
	local list = {}
	local center = vec3Attr(plaza, "FxCenter")
	local lamps = vec3Attr(plaza, "FxLamps")
	if center and lamps then
		local r, top, n = lamps.X, lamps.Y, math.floor(lamps.Z)
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * math.pi * 2
			local d = Vector3.new(math.sin(a), 0, math.cos(a))
			local along = Vector3.new(d.Z, 0, -d.X)
			for _, z in ipairs({ -1.9, 1.9 }) do
				-- (dessus du chapeau de la lanterne)
				table.insert(list, center + d * r + along * z + Vector3.new(0, top + 0.5, 0))
			end
		end
	end
	local base = vec3Attr(plaza, "FxFountainBase")
	if base then
		for i = 0, 11 do
			local a = (i + 0.5) / 12 * math.pi * 2
			table.insert(list, base + Vector3.new(math.sin(a) * 13.5, 3.2, math.cos(a) * 13.5))
		end
	end
	return list
end

function TownPigeons.Build(folder: Instance, plaza: Instance): any
	local model = Instance.new("Model")
	model.Name = "Pigeons"
	model.Parent = folder
	local P = {
		List = {},
		Flocks = {},
		Parts = {},
		Frames = {},
		Homes = {},
		Perches = perches(plaza),
		Taken = {},
		Time = 0,
		Center = vec3Attr(plaza, "FxCenter") or Vector3.new(0, 0, 0),
	}
	for i = 1, 4 do
		local home = vec3Attr(plaza, "FxFlock" .. i)
		if home then
			table.insert(P.Homes, home + Vector3.new(0, 0.12, 0))
		end
	end
	for h, home in ipairs(P.Homes) do
		local flock = { Id = h, Home = home, Air = false, Timer = 20 + h * 17, Birds = {} }
		table.insert(P.Flocks, flock)
		for j = 1, PER_FLOCK do
			local seed = h * 10 + j
			local rng = Random.new(h * 31 + j * 7)
			-- places de départ sur une petite grille décalée (jamais l'un dans l'autre)
			local a = (j / PER_FLOCK) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local r = 1.1 + (j % 2) * 1.2
			local pos = home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local yaw = rng:NextNumber(0, math.pi * 2)
			local bird = {
				Id = #P.List + 1,
				Pos = pos,
				Ground = home.Y,
				Yaw = yaw,
				YawTarget = yaw,
				Flock = flock,
				Slot = j,
				Rng = rng,
				Mode = "idle",
				Timer = rng:NextNumber(0.2, 1.5),
				Clock = 0,
				Target = nil,
				Walked = 0,
				StepPhase = 0,
				HeadYaw = 0,
				HeadYawTarget = 0,
				HeadTimer = rng:NextNumber(0.3, 1.2),
				Spread = 0,
				TailSpread = 0,
				Flap = 0,
				FlapPhase = rng:NextNumber(),
				Burst = 0,
				Pitch = 0,
				Bank = 0,
				Fly = nil,
				Perched = false,
				PerchIndex = nil,
				First = #P.Parts + 1,
			}
			local plume = plumeFor(seed)
			for _, s in ipairs(SPECS) do
				local color = plume[s.Color] or FIXED[s.Color] or rgb(128, 128, 128)
				local p = newPart(model, s, color)
				p.CFrame = CFrame.new(pos) * s.Fold
				table.insert(P.Parts, p)
				table.insert(P.Frames, p.CFrame)
			end
			table.insert(P.List, bird)
			table.insert(flock.Birds, bird)
		end
	end
	return P
end

function TownPigeons.Count(P: any): number
	return P and #P.List or 0
end

-- Un pigeon est-il assez près de `point` pour être animé à chaque image ?
function TownPigeons.Near(P: any, point: Vector3, radius: number): boolean
	if not P then
		return false
	end
	for _, flock in ipairs(P.Flocks) do
		if flock.Air or (flock.Home - point).Magnitude < radius then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Trajectoires de vol : courbes d'Hermite (position ET vitesse continues)
----------------------------------------------------------------------

local function hermite(seg: any, t: number): (Vector3, Vector3)
	local d = seg.Dur
	local u = math.clamp(t / d, 0, 1)
	local u2, u3 = u * u, u * u * u
	local h00 = 2 * u3 - 3 * u2 + 1
	local h10 = u3 - 2 * u2 + u
	local h01 = -2 * u3 + 3 * u2
	local h11 = u3 - u2
	local m0, m1 = seg.V0 * d, seg.V1 * d
	local pos = seg.P0 * h00 + m0 * h10 + seg.P1 * h01 + m1 * h11
	local d00 = 6 * u2 - 6 * u
	local d10 = 3 * u2 - 4 * u + 1
	local d01 = -6 * u2 + 6 * u
	local d11 = 3 * u2 - 2 * u
	local vel = (seg.P0 * d00 + m0 * d10 + seg.P1 * d01 + m1 * d11) / d
	return pos, vel
end

local function seg(kind: string, p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, dur: number): any
	return { Kind = kind, P0 = p0, V0 = v0, P1 = p1, V1 = v1, Dur = math.max(0.2, dur) }
end

local function horizontal(v: Vector3): Vector3
	local h = Vector3.new(v.X, 0, v.Z)
	if h.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return h.Unit
end

-- Vol court (vers un perchoir, ou pour redescendre) : bond, montée, arrivée freinée
local function hopPlan(from: Vector3, to: Vector3, delay: number): any
	local dir = horizontal(to - from)
	local dist = (to - from).Magnitude
	local dur = math.clamp(dist / 8, 1.1, 3.6)
	local climb = math.max(0, to.Y - from.Y)
	local v0 = dir * 2.5 + Vector3.new(0, 6 + climb * 0.8, 0)
	local v1 = dir * 1.6 + Vector3.new(0, -1.2, 0)
	return { Segs = { seg("land", from, v0, to, v1, dur) }, I = 1, T = -delay, From = from }
end

-- Tour de la place en formation puis atterrissage à `to`
local function tourPlan(P: any, bird: any, to: Vector3, delay: number): any
	local C = P.Center
	local from = bird.Pos
	local slot = bird.Slot
	-- décalages de formation (chaque pigeon a son couloir : jamais l'un dans l'autre)
	local lateral = ((slot - 1) % 3 - 1) * 1.7
	local vertical = math.floor((slot - 1) / 3) * 1.3 - 0.6 + (bird.Flock.Id % 2) * 0.7
	local R = 23 + lateral + bird.Flock.Id * 0.9
	local H = C.Y + 10.5 + vertical
	local function orbitPoint(a: number): (Vector3, Vector3)
		local p = Vector3.new(C.X + math.sin(a) * R, H, C.Z + math.cos(a) * R)
		-- (sens horaire vu du dessus : a décroît)
		local t = Vector3.new(-math.cos(a), 0, math.sin(a))
		return p, t * FLY_SPEED
	end
	local rel = from - C
	local a0 = math.atan2(rel.X, rel.Z) - 0.5
	local segs = {}
	local p1, v1 = orbitPoint(a0)
	local out = horizontal(rel)
	table.insert(segs, seg("up", from, out * 2 + Vector3.new(0, 7, 0), p1, v1, 1.5))
	-- 1 tour et quart, par quarts de cercle (tangentes = vitesse de croisière)
	local relTo = to - C
	local aTo = math.atan2(relTo.X, relTo.Z)
	local turns = 4 + math.floor(((a0 - aTo) % (math.pi * 2)) / (math.pi / 2))
	local a = a0
	local quarter = math.pi / 2
	local qDur = R * quarter / FLY_SPEED
	for _ = 1, turns do
		local pa, va = orbitPoint(a)
		local pb, vb = orbitPoint(a - quarter)
		-- (tangentes d'Hermite d'un quart de cercle : R·π/2 ≈ bonne approximation)
		table.insert(segs, seg("cruise", pa, va, pb, vb, qDur))
		a -= quarter
	end
	local pe, ve = orbitPoint(a)
	local dist = (to - pe).Magnitude
	local dir = horizontal(to - pe)
	table.insert(segs, seg("land", pe, ve, to, dir * 1.8 + Vector3.new(0, -1.3, 0), math.clamp(dist / (FLY_SPEED * 0.55), 1.6, 4.2)))
	return { Segs = segs, I = 1, T = -delay, From = from }
end

----------------------------------------------------------------------
-- Places libres (atterrissage, marche)
----------------------------------------------------------------------

-- Distance horizontale de `p` à la place la plus proche prise par un autre
-- pigeon : où il se tient (au sol, ou accroupi avant l'envol), où il va se
-- poser, où il marche
local function nearestTaken(P: any, me: any, p: Vector3): number
	local best = math.huge
	local function consider(q: Vector3?)
		if q and math.abs(q.Y - p.Y) < 1.5 then
			local d = Vector3.new(q.X - p.X, 0, q.Z - p.Z).Magnitude
			if d < best then
				best = d
			end
		end
	end
	for _, other in ipairs(P.List) do
		if other ~= me then
			if other.Fly then
				consider(other.Dest)
				if other.Fly.T < 0 then
					consider(other.Pos)
				end
			else
				consider(other.Pos)
			end
			consider(other.Target)
		end
	end
	return best
end

local function clearOf(P: any, me: any, p: Vector3, gap: number): boolean
	return nearestTaken(P, me, p) >= gap
end

local function freeSpot(P: any, me: any, center: Vector3, radius: number, rng: Random, gap: number?): Vector3?
	for _ = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * radius
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if clearOf(P, me, p, gap or (2 * BIRD_R + 0.15)) then
			return p
		end
	end
	return nil
end

local function freePerch(P: any, near: Vector3, rng: Random): (Vector3?, number?)
	local best, bestI, bestD = nil, nil, math.huge
	for i, p in ipairs(P.Perches) do
		if not P.Taken[i] then
			local d = (p - near).Magnitude + rng:NextNumber(0, 14)
			if d < bestD then
				best, bestI, bestD = p, i, d
			end
		end
	end
	return best, bestI
end

local function releasePerch(P: any, bird: any)
	if bird.PerchIndex then
		P.Taken[bird.PerchIndex] = nil
		bird.PerchIndex = nil
	end
end

local function startFly(bird: any, plan: any, dest: Vector3, perched: boolean)
	bird.Fly = plan
	bird.Dest = dest
	bird.Mode = "fly"
	bird.Target = nil
	bird.Perched = false
	bird.WillPerch = perched
	bird.Clock = 0
	bird.Burst = 1
end

-- Tout le groupe s'envole (loin de `threat` si donné) et fait le tour de la place
local function flockTakeOff(P: any, flock: any, threat: Vector3?)
	if flock.Air then
		return
	end
	-- nouveau coin de la place : le plus loin de la menace (ou un autre au hasard)
	local best, bestScore = flock.Home, -math.huge
	for _, home in ipairs(P.Homes) do
		local score = threat and (home - threat).Magnitude or (home ~= flock.Home and 10 + (home - flock.Home).Magnitude * 0.01 or 0)
		score += (home ~= flock.Home) and 5 or 0
		if score > bestScore then
			best, bestScore = home, score
		end
	end
	flock.Home = best
	flock.Air = true
	flock.Timer = flock.Birds[1] and flock.Birds[1].Rng:NextNumber(RELOCATE_MIN, RELOCATE_MAX) or 60
	for k, bird in ipairs(flock.Birds) do
		if bird.Mode ~= "fly" and not bird.Perched then
			local rng = bird.Rng
			releasePerch(P, bird)
			local dest: Vector3? = nil
			local perched = false
			if rng:NextNumber() < 0.25 then
				local perch, index = freePerch(P, best, rng)
				if perch and index then
					P.Taken[index] = true
					bird.PerchIndex = index
					dest, perched = perch, true
				end
			end
			if not dest then
				dest = freeSpot(P, bird, best, HOME_R - 0.5, rng, LAND_GAP) or (best + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)))
			end
			-- (réaction décalée : ils ne partent pas tous à la même image)
			startFly(bird, tourPlan(P, bird, dest :: Vector3, (k - 1) * 0.16 + rng:NextNumber(0, 0.12)), dest :: Vector3, perched)
		end
	end
end

----------------------------------------------------------------------
-- Comportement
----------------------------------------------------------------------

local function yawTo(from: Vector3, to: Vector3, fallback: number): number
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude < 0.05 then
		return fallback
	end
	return math.atan2(-d.X, -d.Z)
end

local function angleDiff(a: number, b: number): number
	return (a - b + math.pi) % (math.pi * 2) - math.pi
end

local function approach(value: number, target: number, rate: number, dt: number): number
	local k = 1 - math.exp(-rate * dt)
	return value + (target - value) * k
end

local function peopleNear(): { Vector3 }
	local folder = script.Parent
	local mod = folder and folder:FindFirstChild("TownPeople")
	if not mod then
		return {}
	end
	local ok, TownPeople = pcall(require, mod)
	if ok and type(TownPeople) == "table" and type(TownPeople.Positions) == "function" then
		local ok2, list = pcall(TownPeople.Positions)
		if ok2 and type(list) == "table" then
			return list
		end
	end
	return {}
end

-- Nouveau comportement au sol
local function chooseGround(P: any, bird: any)
	local rng = bird.Rng
	local r = rng:NextNumber()
	bird.Clock = 0
	bird.Target = nil
	if r < 0.3 then
		bird.Mode, bird.Timer = "peck", rng:NextNumber(0.9, 1.8)
	elseif r < 0.62 then
		local spot = freeSpot(P, bird, bird.Flock.Home, HOME_R, rng)
		if spot and (spot - bird.Pos).Magnitude > 0.6 then
			bird.Mode, bird.Timer = "walk", 6
			bird.Target = spot
		else
			bird.Mode, bird.Timer = "idle", rng:NextNumber(0.6, 1.4)
		end
	elseif r < 0.74 then
		bird.Mode, bird.Timer = "idle", rng:NextNumber(0.8, 2)
	elseif r < 0.82 then
		bird.Mode, bird.Timer = "coo", rng:NextNumber(1.6, 2.6)
	elseif r < 0.89 then
		bird.Mode, bird.Timer = "preen", rng:NextNumber(1, 2)
	elseif r < 0.93 then
		bird.Mode, bird.Timer = "shake", 0.5
	elseif r < 0.96 then
		-- (parfois un pigeon va se percher tout seul)
		local perch, index = freePerch(P, bird.Pos, rng)
		if perch and index then
			P.Taken[index] = true
			bird.PerchIndex = index
			startFly(bird, hopPlan(bird.Pos, perch, 0.25), perch, true)
		else
			bird.Mode, bird.Timer = "idle", 1
		end
	else
		bird.Mode, bird.Timer = "idle", rng:NextNumber(0.5, 1.5)
	end
end

-- Fin d'un vol : posé
local function land(P: any, bird: any)
	bird.Pos = bird.Dest or bird.Pos
	bird.Fly = nil
	bird.Dest = nil
	bird.Perched = bird.WillPerch == true
	bird.WillPerch = nil
	bird.Ground = bird.Pos.Y
	bird.Mode = bird.Perched and "perch" or "settle"
	bird.Timer = bird.Perched and bird.Rng:NextNumber(PERCH_MIN, PERCH_MAX) or 0.45
	bird.Clock = 0
	if bird.Perched then
		bird.YawTarget = yawTo(bird.Pos, P.Center, bird.Yaw) + math.pi
	end
	-- le groupe est posé quand tous ses pigeons le sont
	local flock = bird.Flock
	if flock.Air then
		local all = true
		for _, b in ipairs(flock.Birds) do
			if b.Fly then
				all = false
				break
			end
		end
		if all then
			flock.Air = false
		end
	end
end

-- Poses : tout est dans le repère du pigeon (pieds au sol, bec vers -Z)
local function pose(P: any, bird: any, dt: number)
	local mode = bird.Mode
	local rng = bird.Rng
	local lift, pitch, roll = 0, 0, 0
	local headFwd, headPitch, headLift = 0, 0, 0
	local legA, legLift = { 0, 0 }, { 0, 0 }
	local tailPitch, tailSpreadTarget = 0, 0
	local spreadTarget = 0
	local flapTarget, flapFreq, flapMean = 0, 0, 0
	local center = false -- (bascule autour du centre du corps : en vol)

	-- tête : petites rotations par à-coups (comme un vrai pigeon)
	bird.HeadTimer -= dt
	if bird.HeadTimer <= 0 then
		bird.HeadTimer = rng:NextNumber(0.35, 1.4)
		bird.HeadYawTarget = (mode == "walk" or mode == "fly") and rng:NextNumber(-0.15, 0.15) or rng:NextNumber(-0.7, 0.7)
	end
	bird.HeadYaw = approach(bird.HeadYaw, bird.HeadYawTarget, 22, dt)

	if mode == "fly" then
		local plan = bird.Fly
		plan.T += dt
		if plan.T < 0 then
			-- accroupi, prêt à bondir
			local k = math.clamp(1 + plan.T / 0.2, 0, 1)
			lift = -0.05 * k
			pitch = -0.12 * k
			spreadTarget = 0.2 * k
			bird.Pos = plan.From
			-- (se tourne déjà vers là où il va s'envoler)
			local first = plan.Segs[1]
			if first then
				local h = Vector3.new(first.V0.X, 0, first.V0.Z)
				if h.Magnitude > 0.1 then
					local d = angleDiff(math.atan2(-h.X, -h.Z), bird.Yaw)
					bird.Yaw += math.clamp(d, -9 * dt, 9 * dt)
				end
			end
		else
			local s = plan.Segs[plan.I]
			while s and plan.T > s.Dur do
				plan.T -= s.Dur
				plan.I += 1
				s = plan.Segs[plan.I]
				-- début de la descente : la place visée est-elle toujours libre ?
				-- (sinon une autre, tout près : jamais posé sur un voisin)
				if s and s.Kind == "land" and not bird.WillPerch and plan.T < 0.05 and not clearOf(P, bird, s.P1, LAND_GAP) then
					local spot = freeSpot(P, bird, s.P1, 2.5, bird.Rng, LAND_GAP)
					if spot then
						s.P1 = spot
						bird.Dest = spot
					end
				end
			end
			if not s then
				land(P, bird)
				pose(P, bird, 0)
				return
			end
			-- pendant la descente, la place visée est surveillée : prise entre-temps
			-- (un voisin s'y est poussé) -> nouvelle trajectoire vers une place
			-- libre, qui part de la position ET de la vitesse actuelles (sans saut)
			if s.Kind == "land" and not bird.WillPerch and plan.T < s.Dur * 0.8 then
				bird.Watch = (bird.Watch or 0) - dt
				if bird.Watch <= 0 then
					bird.Watch = 0.15
					if not clearOf(P, bird, s.P1, LAND_GAP - 0.1) then
						local spot = freeSpot(P, bird, s.P1, 2.5, bird.Rng, LAND_GAP) or freeSpot(P, bird, bird.Flock.Home, HOME_R + 1.5, bird.Rng, LAND_GAP)
						if spot then
							local p0, v0 = hermite(s, plan.T)
							local ns = seg("land", p0, v0, spot, s.V1, math.max(0.9, s.Dur - plan.T))
							plan.Segs[plan.I] = ns
							plan.T = 0
							s = ns
							bird.Dest = spot
						end
					end
				end
			end
			local pos, vel = hermite(s, plan.T)
			bird.Pos = pos
			local speed = vel.Magnitude
			if Vector3.new(vel.X, 0, vel.Z).Magnitude > 0.4 then
				-- cap = direction du vol, tourné progressivement (9 rad/s au plus)
				local newYaw = math.atan2(-vel.X, -vel.Z)
				local turn = math.clamp(angleDiff(newYaw, bird.Yaw), -9 * dt, 9 * dt)
				bird.Yaw += turn
				bird.YawTarget = bird.Yaw
				bird.Bank = approach(bird.Bank, math.clamp(-turn / math.max(dt, 1 / 120) * 0.12, -0.55, 0.55), 5, dt)
			end
			local climbPitch = speed > 0.1 and math.asin(math.clamp(vel.Y / speed, -1, 1)) or 0
			spreadTarget = 1
			center = true
			local u = plan.T / s.Dur
			if s.Kind == "up" then
				pitch = math.clamp(climbPitch, -0.3, 0.9) * 0.8
				flapTarget, flapFreq, flapMean = 0.95, 7, 0.15
				legA = { 1.2, 1.2 }
				tailSpreadTarget = 0.6
			elseif s.Kind == "cruise" then
				pitch = climbPitch * 0.6
				-- rafales de battements, puis plané ailes en V
				bird.Burst -= dt
				if bird.Burst < -1.3 then
					bird.Burst = rng:NextNumber(0.6, 1.1)
				end
				if bird.Burst > 0 then
					flapTarget, flapFreq, flapMean = 0.65, 6, 0.1
				else
					flapTarget, flapFreq, flapMean = 0.04, 2, 0.32
				end
				legA = { 1.3, 1.3 }
			else -- "land"
				if u < 0.55 then
					-- descente en plané
					pitch = climbPitch * 0.5
					flapTarget, flapFreq, flapMean = 0.05, 2, 0.3
					legA = { 1.3, 1.3 }
				else
					-- freinage : corps redressé, ailes hautes qui battent, queue en éventail, pattes en avant
					local k = (u - 0.55) / 0.45
					pitch = 0.2 + 0.45 * k
					flapTarget, flapFreq, flapMean = 0.75, 5.5, 0.35
					legA = { 1.3 - 1.8 * k, 1.3 - 1.8 * k }
					tailSpreadTarget = 1
					tailPitch = 0.35 * k
				end
			end
			roll = bird.Bank
		end
	elseif mode == "walk" then
		local target = bird.Target
		if not target then
			bird.Mode, bird.Timer = "idle", 0.5
		else
			local want = yawTo(bird.Pos, target, bird.Yaw)
			bird.YawTarget = want
			local facing = math.abs(angleDiff(want, bird.Yaw)) < 0.6
			local speed = (bird.Hurry and bird.Hurry > 0) and WALK_SPEED * 1.6 or WALK_SPEED
			if facing then
				local step = Vector3.new(-math.sin(bird.Yaw), 0, -math.cos(bird.Yaw)) * (speed * dt)
				local nextPos = bird.Pos + step
				-- (un voisin devant : on attend / on change de but, jamais l'un dans l'autre)
				local dNext = nearestTaken(P, bird, nextPos)
				local blocked = dNext < 2 * BIRD_R + 0.05 and dNext < nearestTaken(P, bird, bird.Pos)
				if not blocked then
					-- (le corps entier : bec et queue compris)
					local cNext = bodyClear(P, bird, nextPos, bird.Yaw)
					blocked = cNext < CAPSULE_MARGIN and cNext < bodyClear(P, bird, bird.Pos, bird.Yaw)
				end
				if blocked then
					bird.Target = freeSpot(P, bird, bird.Flock.Home, HOME_R, rng)
					if not bird.Target then
						bird.Mode, bird.Timer = "idle", 0.6
					end
				else
					bird.Pos = nextPos
					bird.StepPhase += dt / STEP_T
				end
				if (Vector3.new(target.X - bird.Pos.X, 0, target.Z - bird.Pos.Z)).Magnitude < 0.12 then
					bird.Target = nil
					bird.Mode, bird.Timer = "idle", rng:NextNumber(0.2, 0.8)
				end
			else
				-- on tourne sur place à petits pas
				bird.StepPhase += dt / STEP_T * 0.8
			end
			-- un pas = un hochement : la tête AVANCE vite (35 %), puis reste
			-- immobile dans l'espace pendant que le corps la rattrape (65 %)
			local u = bird.StepPhase % 1
			local amp = speed * STEP_T * 0.65 / 2
			if u < 0.35 then
				headFwd = -amp + (u / 0.35) * 2 * amp
			else
				headFwd = amp - ((u - 0.35) / 0.65) * 2 * amp
			end
			local foot = math.floor(bird.StepPhase) % 2 + 1
			local swing = math.sin(u * math.pi)
			legA[foot] = -0.45 * swing + 0.2
			legLift[foot] = 0.045 * swing
			legA[3 - foot] = 0.15 * (1 - u)
			roll = (foot == 1 and 1 or -1) * 0.05 * swing
			lift = 0.012 * swing
			pitch = -0.04
		end
	elseif mode == "peck" then
		-- 2 à 3 coups de bec : le corps bascule, la tête plonge
		local c = bird.Clock
		local k = math.clamp(c / 0.2, 0, 1)
		pitch = -0.32 * k
		local beat = math.max(0, math.sin(c * 11))
		headPitch = (0.75 + 0.55 * beat) * k
		headFwd = 0.04 * k
		tailPitch = -0.2 * k
	elseif mode == "coo" then
		-- roucoulade : courbettes, queue étalée qui traîne, petit tour sur lui-même
		local c = bird.Clock
		local bow = math.max(0, math.sin(c * 5.5))
		headPitch = -0.3 + 0.65 * bow
		pitch = -0.1 * bow
		tailSpreadTarget = 1
		tailPitch = -0.35
		lift = 0.02 * bow
		bird.YawTarget = bird.Yaw + 1.2
		local foot = math.floor(c * 5) % 2 + 1
		legA[foot] = -0.2
		legLift[foot] = 0.03
	elseif mode == "preen" then
		-- toilette : la tête plonge vers l'aile
		headPitch = 0.9
		bird.HeadYawTarget = 1.9 * (bird.Id % 2 == 0 and 1 or -1)
		spreadTarget = 0.12 + 0.06 * math.sin(bird.Clock * 14)
	elseif mode == "shake" then
		-- s'ébroue : petit frisson des ailes et de la queue
		spreadTarget = 0.25
		roll = math.sin(bird.Clock * 40) * 0.06
		tailSpreadTarget = 0.6
	elseif mode == "settle" then
		-- juste posé : on replie les ailes
		spreadTarget = 0
		tailSpreadTarget = 0.3
	elseif mode == "perch" then
		headPitch = math.sin(bird.Clock * 0.9) * 0.15
	end

	-- lissage des ailes / queue / battements (sans à-coup)
	bird.Spread = approach(bird.Spread, spreadTarget, spreadTarget > bird.Spread and 12 or 7, dt)
	bird.TailSpread = approach(bird.TailSpread, tailSpreadTarget, 8, dt)
	bird.Flap = approach(bird.Flap, flapTarget, 10, dt)
	bird.FlapMean = approach(bird.FlapMean or 0, flapMean, 6, dt)
	bird.FlapPhase = (bird.FlapPhase + dt * math.max(flapFreq, 1)) % 1
	if mode ~= "fly" then
		-- virage progressif vers le cap voulu (3,5 rad/s au plus)
		local d = angleDiff(bird.YawTarget, bird.Yaw)
		local newYaw = bird.Yaw + math.clamp(d, -3.5 * dt, 3.5 * dt)
		-- (on ne tourne pas sa queue dans un voisin)
		if newYaw ~= bird.Yaw and not bird.Perched then
			local cNew = bodyClear(P, bird, bird.Pos, newYaw)
			if cNew >= CAPSULE_MARGIN or cNew >= bodyClear(P, bird, bird.Pos, bird.Yaw) then
				bird.Yaw = newYaw
			end
		else
			bird.Yaw = newYaw
		end
		bird.Bank = approach(bird.Bank, 0, 6, dt)
	end
	bird.Pitch = approach(bird.Pitch, pitch, center and 6 or 14, dt)
	-- toute la pose est LISSÉE (constante de temps ~50 ms) : on passe d'un
	-- geste à l'autre (picorer -> marcher, vol -> sol) sans aucun saut
	local S = bird.Pose
	if not S then
		S = { Lift = 0, Roll = 0, HeadFwd = 0, HeadPitch = 0, HeadLift = 0, LegA = { 0, 0 }, LegLift = { 0, 0 }, TailPitch = 0, PivotY = 0 }
		bird.Pose = S
	end
	local k = 1 - math.exp(-20 * dt)
	local kf = 1 - math.exp(-35 * dt) -- (hochement de tête : plus vif)
	S.Lift += (lift - S.Lift) * k
	S.Roll += (roll - S.Roll) * k
	S.HeadFwd += (headFwd - S.HeadFwd) * kf
	S.HeadPitch += (headPitch - S.HeadPitch) * k
	S.HeadLift += (headLift - S.HeadLift) * k
	for i = 1, 2 do
		S.LegA[i] += (legA[i] - S.LegA[i]) * k
		S.LegLift[i] += (legLift[i] - S.LegLift[i]) * k
	end
	S.TailPitch += (tailPitch - S.TailPitch) * k
	-- pivot de la bascule : pieds au sol, centre du corps en vol (glissé)
	S.PivotY += ((center and 0.37 or 0) - S.PivotY) * (1 - math.exp(-6 * dt))
end

-- Écrit les CFrames des pièces d'un pigeon dans `frames`
local function write(bird: any, frames: { CFrame })
	local ps = bird.Pose
	local pivot = CFrame.new(0, ps.PivotY, 0)
	local root = CFrame.new(bird.Pos + Vector3.new(0, ps.Lift, 0)) * CFrame.Angles(0, bird.Yaw, 0) * pivot * CFrame.Angles(bird.Pitch, 0, ps.Roll) * pivot:Inverse()
	local head = root * CFrame.new(0, ps.HeadLift, -ps.HeadFwd) * NECK_P * CFrame.Angles(0, bird.HeadYaw, 0) * CFrame.Angles(-ps.HeadPitch, 0, 0) * NECK_INV
	local theta = bird.FlapMean + bird.Flap * math.sin(bird.FlapPhase * math.pi * 2)
	local theta2 = bird.Flap * 0.45 * math.sin((bird.FlapPhase - 0.1) * math.pi * 2)
	local spread = bird.Spread
	local wings = {}
	local wrists = {}
	for i, sx in ipairs({ -1, 1 }) do
		wings[i] = root * SHOULDER[i] * CFrame.Angles(0, 0, sx * theta * spread) * SHOULDER_INV[i]
		wrists[i] = WRIST[i] * CFrame.Angles(0, 0, sx * theta2 * spread) * WRIST_INV[i]
	end
	local tails = {}
	for i, sx in ipairs({ -1, 1 }) do
		tails[i] = root * TAIL_P * CFrame.Angles(ps.TailPitch, sx * 0.3 * bird.TailSpread, 0) * TAIL_INV
	end
	local legs = {}
	for i = 1, 2 do
		legs[i] = root * CFrame.new(0, ps.LegLift[i], 0) * HIP[i] * CFrame.Angles(ps.LegA[i], 0, 0) * HIP_INV[i]
	end
	local base = bird.First - 1
	for k, s in ipairs(SPECS) do
		local g = s.Group
		local cf
		if g == G_BODY then
			cf = root * s.Fold
		elseif g == G_HEAD then
			cf = head * s.Fold
		elseif g == G_WING_L or g == G_WING_R then
			local w = g == G_WING_L and 1 or 2
			local open = s.Open :: CFrame
			if s.Hand then
				open = wrists[w] * open
			end
			cf = wings[w] * (spread < 0.01 and s.Fold or (spread > 0.99 and open or s.Fold:Lerp(open, spread)))
		elseif g == G_TAIL_L then
			cf = tails[1] * s.Fold
		elseif g == G_TAIL_R then
			cf = tails[2] * s.Fold
		elseif g == G_LEG_L then
			cf = legs[1] * s.Fold
		else
			cf = legs[2] * s.Fold
		end
		frames[base + k] = cf
	end
end

-- Corps d'un pigeon vu du dessus : segment bec (0,5 devant) -> queue (0,72
-- derrière), demi-largeur 0,21. Renvoie l'espace libre entre deux corps
-- (négatif = ils se touchent) et les deux points les plus proches.
local function segment(pos: Vector3, yaw: number): (Vector3, Vector3)
	local f = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local p = Vector3.new(pos.X, 0, pos.Z)
	return p + f * 0.5, p - f * 0.72
end
local function closestOn(a0: Vector3, a1: Vector3, p: Vector3): Vector3
	local d = a1 - a0
	local t = math.clamp((p - a0):Dot(d) / math.max(d:Dot(d), 1e-6), 0, 1)
	return a0 + d * t
end
local function cross2(o: Vector3, p: Vector3, q: Vector3): number
	return (p.X - o.X) * (q.Z - o.Z) - (p.Z - o.Z) * (q.X - o.X)
end
local function gapAt(apos: Vector3, ayaw: number, bpos: Vector3, byaw: number): (number, Vector3, Vector3)
	local a0, a1 = segment(apos, ayaw)
	local b0, b1 = segment(bpos, byaw)
	-- (corps qui se croisent en X : distance nulle)
	local d1, d2 = cross2(a0, a1, b0), cross2(a0, a1, b1)
	local d3, d4 = cross2(b0, b1, a0), cross2(b0, b1, a1)
	if d1 * d2 < 0 and d3 * d4 < 0 then
		return -2 * BODY_HALF, Vector3.new(apos.X, 0, apos.Z), Vector3.new(bpos.X, 0, bpos.Z)
	end
	-- (distance segment-segment en 2D : minimum des 4 projections d'extrémités)
	local best, pa, pb = math.huge, a0, b0
	for _, c in ipairs({
		{ a0, closestOn(b0, b1, a0) },
		{ a1, closestOn(b0, b1, a1) },
		{ closestOn(a0, a1, b0), b0 },
		{ closestOn(a0, a1, b1), b1 },
	}) do
		local d = (c[1] - c[2]).Magnitude
		if d < best then
			best, pa, pb = d, c[1], c[2]
		end
	end
	return best - 2 * BODY_HALF, pa, pb
end
capsuleGap = function(a: any, b: any): (number, Vector3, Vector3)
	return gapAt(a.Pos, a.Yaw, b.Pos, b.Yaw)
end

-- Espace libre mini entre le corps de `me` (placé en pos, yaw) et les
-- pigeons posés au même niveau (ou accroupis avant l'envol)
bodyClear = function(P: any, me: any, pos: Vector3, yaw: number): number
	local best = math.huge
	for _, other in ipairs(P.List) do
		if other ~= me and not other.Perched and (not other.Fly or other.Fly.T < 0) and math.abs(other.Pos.Y - pos.Y) < 1 then
			local g = gapAt(pos, yaw, other.Pos, other.Yaw)
			if g < best then
				best = g
			end
		end
	end
	return best
end

function TownPigeons.Step(P: any, dt: number, avatar: Vector3?)
	if not P then
		return
	end
	dt = math.clamp(dt, 0, 0.1)
	P.Time += dt
	-- menaces : l'avatar + les passants proches (relus 4 fois / s)
	P.PeopleClock = (P.PeopleClock or 0) - dt
	if P.PeopleClock <= 0 then
		P.PeopleClock = 0.25
		P.People = peopleNear()
	end
	local threats = {}
	if avatar then
		table.insert(threats, { Pos = avatar, Scale = 1 })
	end
	for _, q in ipairs(P.People or {}) do
		table.insert(threats, { Pos = q, Scale = 0.7 })
	end
	-- groupes : envol si quelqu'un arrive trop près, ou de temps en temps
	for _, flock in ipairs(P.Flocks) do
		if not flock.Air then
			flock.Timer -= dt
			local threat: Vector3? = nil
			for _, bird in ipairs(flock.Birds) do
				if not bird.Fly and not bird.Perched then
					for _, t in ipairs(threats) do
						local d = Vector3.new(bird.Pos.X - t.Pos.X, 0, bird.Pos.Z - t.Pos.Z).Magnitude
						if d < SCARE_R * t.Scale and math.abs(t.Pos.Y - bird.Pos.Y) < 8 then
							threat = t.Pos
							break
						elseif d < WARY_R * t.Scale and math.abs(t.Pos.Y - bird.Pos.Y) < 8 and bird.Mode ~= "walk" then
							-- on s'écarte en marchant (vite)
							local away = horizontal(bird.Pos - t.Pos)
							local spot = bird.Pos + away * 1.6
							if clearOf(P, bird, spot, 2 * BIRD_R + 0.1) then
								bird.Mode, bird.Timer, bird.Clock = "walk", 2, 0
								bird.Target = spot
								bird.Hurry = 1.5
							end
						end
					end
				end
				if threat then
					break
				end
			end
			if threat then
				flockTakeOff(P, flock, threat)
			elseif flock.Timer <= 0 then
				flockTakeOff(P, flock, nil)
			end
		end
	end
	-- chaque pigeon
	for _, bird in ipairs(P.List) do
		bird.Timer -= dt
		bird.Clock += dt
		if bird.Hurry then
			bird.Hurry -= dt
			if bird.Hurry <= 0 then
				bird.Hurry = nil
			end
		end
		if bird.Mode == "perch" and bird.Timer <= 0 then
			-- on redescend picorer près de son groupe
			releasePerch(P, bird)
			local spot = freeSpot(P, bird, bird.Flock.Home, HOME_R, bird.Rng, LAND_GAP) or bird.Flock.Home
			startFly(bird, hopPlan(bird.Pos, spot, 0.2), spot, false)
		elseif bird.Mode ~= "fly" and bird.Mode ~= "perch" and bird.Timer <= 0 then
			chooseGround(P, bird)
		end
		pose(P, bird, dt)
	end
	-- séparation au sol : deux pigeons ne se chevauchent JAMAIS
	local list = P.List
	for i = 1, #list do
		local a = list[i]
		if not a.Fly and not a.Perched then
			for j = i + 1, #list do
				local b = list[j]
				if not b.Fly and not b.Perched and math.abs(a.Pos.Y - b.Pos.Y) < 1 then
					local d = Vector3.new(b.Pos.X - a.Pos.X, 0, b.Pos.Z - a.Pos.Z)
					local m = d.Magnitude
					local need = 2 * BIRD_R
					if m < need then
						-- (poussée douce : 3 studs/s au plus, pas de saut visible)
						local n = m > 1e-3 and d / m or Vector3.new(1, 0, 0)
						local push = math.min((need - m) / 2 + 0.002, 3 * dt)
						a.Pos -= n * push
						b.Pos += n * push
					end
					-- corps réels (bec -> bout de la queue, orientés) : jamais sécants
					local clear, pa, pb = capsuleGap(a, b)
					if clear < CAPSULE_MARGIN then
						local sep = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z)
						local n = sep.Magnitude > 1e-3 and sep.Unit or Vector3.new(1, 0, 0)
						local push = math.min((CAPSULE_MARGIN - clear) / 2 + 0.002, 4 * dt)
						a.Pos -= n * push
						b.Pos += n * push
					end
				end
			end
		end
	end
	local frames = P.Frames
	for _, bird in ipairs(list) do
		write(bird, frames)
	end
	workspace:BulkMoveTo(P.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Mesures (émulateur / tests) : écart mini entre deux pigeons au sol (centres
-- et corps réels : MinClear < 0 = deux corps qui se touchent), modes
function TownPigeons.Debug(P: any): any
	if not P then
		return {}
	end
	local minGap = math.huge
	local minClear = math.huge
	local clearInfo = ""
	local info = ""
	local modes = {}
	for i, a in ipairs(P.List) do
		modes[a.Mode] = (modes[a.Mode] or 0) + 1
		for j = i + 1, #P.List do
			local b = P.List[j]
			if not a.Fly and not b.Fly and not a.Perched and not b.Perched and math.abs(a.Pos.Y - b.Pos.Y) < 1 then
				local g = Vector3.new(a.Pos.X - b.Pos.X, 0, a.Pos.Z - b.Pos.Z).Magnitude
				local cg = capsuleGap(a, b)
				if cg < minClear then
					minClear = cg
					clearInfo = a.Mode .. "/" .. b.Mode .. " " .. a.Id .. "," .. b.Id .. string.format(" d=%.2f", g)
				end
				if g < minGap then
					minGap = g
					info = a.Mode .. "/" .. b.Mode .. " " .. a.Id .. "," .. b.Id
				end
			end
		end
	end
	return { Birds = #P.List, Parts = #P.Parts, MinGap = minGap, MinClear = minClear, ClearPair = clearInfo, MinPair = info, Modes = modes }
end

return TownPigeons
