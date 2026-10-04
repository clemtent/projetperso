--[[
	ParkSports (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ParkSports

	🏀🎾⚽🏓 Dopamine Town (v11, PARK11) : des terrains où les PNJ JOUENT
	VRAIMENT ("le basket / le tennis joués avec des animations").
	Chaque terrain est construit côté CLIENT (en flux) avec son jeu animé à
	chaque image près de la caméra (ParkKit.Actor, ≤ 150 studs) :
	  - 🏀 BASKET (shoot-around à 3) : un joueur DRIBBLE (le ballon rebondit
	    entre la main et le sol, au rythme du bras), s'arrête, saute et TIRE
	    (ballon en cloche jusqu'au cercle : panier qui fait trembler le filet,
	    ou rebond sur l'arceau) ; un autre COURT au rebond, attrape le ballon
	    et devient le tireur suivant ; le troisième attend en position, prêt ;
	  - 🎾 TENNIS : vrai échange, la balle passe le filet en cloche, REBONDIT
	    dans le camp adverse, le joueur se DÉPLACE (pas chassés) et frappe en
	    coup droit ou en revers selon le côté, raquette dans la main ; service
	    (lancer de balle + smash) à chaque point ;
	  - ⚽ FOOT : passes à ras de terre en triangle (contrôle, passe du
	    plat du pied), puis TIR au but : le gardien PLONGE, but (le filet se
	    gonfle) ou arrêt, et il relance à la main ;
	  - 🏓 PING-PONG : échanges rapides, rebond de chaque côté de la table,
	    raquettes.
	Balles et ballons suivent des trajectoires physiques calculées (cloches,
	rebonds amortis, roulés) : rien n'est simulé par le moteur, tout dépend
	de l'heure, donc aucun accroc. Les poses des joueurs sont des anims
	"maison" (NPCModels.AddAnim, NPC11) ; sans elles, repli sur les anims de
	base (marche, bras levés...).
	Aucune lumière, aucun son, aucune pièce serveur.

	API :
	  ParkSports.Basketball(m, F, seed, opts?)   F = centre du terrain au sol, X = longueur
	  ParkSports.Tennis(m, F, seed, opts?)
	  ParkSports.Football(m, F, seed, opts?)
	  ParkSports.PingPong(m, F, seed, opts?)     (une table et 2 joueurs)
	  ParkSports.Step(game, t)                   (appelé par l'acteur créé)
	  ParkSports.FOOT = { Basketball = Vector2, ... } emprises
	  ParkSports.Debug(game) -> table             (tests)
]]

local ParkKit = require(script.Parent.ParkKit)

local ParkSports = {}

local M = ParkKit.M
local rgb = ParkKit.rgb
local TAU = ParkKit.TAU
local Part, Box, Column, Rod = ParkKit.Part, ParkKit.Box, ParkKit.Column, ParkKit.Rod
local hash, pick = ParkKit.Hash, ParkKit.Pick
local ANG = CFrame.Angles
local sin, cos, abs, max, min = math.sin, math.cos, math.abs, math.max, math.min

local WHITE = rgb(250, 250, 248)
local STEEL = rgb(150, 156, 164)
local IRON = rgb(44, 48, 56)
local GREEN_D = rgb(46, 92, 66)

ParkSports.FOOT = {
	Basketball = Vector2.new(34, 22),
	Tennis = Vector2.new(46, 40),
	Football = Vector2.new(50, 32),
	PingPong = Vector2.new(16, 12),
}

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function clamp01(u: number): number
	return math.clamp(u, 0, 1)
end

-- cloche douce 0 -> 1 -> 0 sur [a, b]
local function bell(u: number, a: number, b: number): number
	if u <= a or u >= b then
		return 0
	end
	return sin((u - a) / (b - a) * math.pi)
end

----------------------------------------------------------------------
-- Anims "maison" (NPCModels.AddAnim) : t = phase 0..1 (gestes) ou temps
-- (cycles : course, dribble). Conventions des poses (NPCModels) : membre
-- x > 0 vers l'AVANT, bras droit écarté = z > 0, gauche = z < 0 ;
-- coude / genou > 0 = flexion ; Lean > 0 = penché en avant ;
-- Twist > 0 = buste vers la gauche ; HeadPitch > 0 = regarde en bas.
----------------------------------------------------------------------

local function runLegs(P: any, w: number, amp: number)
	local sl, sr = sin(w), sin(w + math.pi)
	local cl, cr = cos(w), cos(w + math.pi)
	P.LTh = sl * amp + 0.1
	P.RTh = sr * amp + 0.1
	P.LKnee = max(0, cl) ^ 1.3 * 1.6 + 0.25
	P.RKnee = max(0, cr) ^ 1.3 * 1.6 + 0.25
	P.LFoot = 0.2 * max(0, cl) - 0.15 * max(0, sl)
	P.RFoot = 0.2 * max(0, cr) - 0.15 * max(0, sr)
	P.PelvisYaw = -sl * 0.12
	P.Twist = sl * 0.14
	P.SwayX = cl * 0.03
	return sl, sr
end

local ANIMS = {}

-- course (t = temps) : grandes foulées, bras pliés à 90° qui balancent
ANIMS.p11_run = {
	Fallback = "walk",
	Fn = function(P: any, t: number, _seed: number)
		local w = t * TAU * 1.45
		local sl, sr = runLegs(P, w, 0.62)
		P.Lean = 0.16
		P.LUp = ANG(-sl * 0.75, 0, -0.12)
		P.RUp = ANG(-sr * 0.75, 0, 0.12)
		P.LLo, P.RLo = 1.45, 1.45
		P.HeadPitch = -0.05
		P.Bob = abs(sin(w)) * 0.12
		P.LookW = 0.2
	end,
}

-- petite foulée (jogging, repli défensif)
ANIMS.p11_jog = {
	Fallback = "walk",
	Fn = function(P: any, t: number, _seed: number)
		local w = t * TAU * 1.25
		local sl, sr = runLegs(P, w, 0.4)
		P.Lean = 0.1
		P.LUp = ANG(-sl * 0.5, 0, -0.1)
		P.RUp = ANG(-sr * 0.5, 0, 0.1)
		P.LLo, P.RLo = 1.35, 1.35
		P.Bob = abs(sin(w)) * 0.06
		P.LookW = 0.3
	end,
}

-- position "prêt" (genoux fléchis, poids sur l'avant, bras devant), petit
-- sautillement sur place
ANIMS.p11_ready = {
	Fallback = "idle",
	Fn = function(P: any, t: number, _seed: number)
		local hop = abs(sin(t * TAU * 1.1))
		P.LTh, P.RTh = 0.42, 0.42
		P.LKnee, P.RKnee = 0.75 + hop * 0.12, 0.75 + hop * 0.12
		P.LFoot, P.RFoot = -0.3, -0.3
		P.LThRoll, P.RThRoll = 0.12, -0.12
		P.Lean = 0.32
		P.LUp = ANG(0.55, 0, -0.25)
		P.RUp = ANG(0.55, 0, 0.25)
		P.LLo, P.RLo = 0.9, 0.9
		P.HeadPitch = -0.28
		P.LookW = 0.2
	end,
}

-- dribble main droite (t = temps : 2 rebonds / s) en marchant
ANIMS.p11_dribble = {
	Fallback = "walk",
	Fn = function(P: any, t: number, _seed: number)
		local w = t * TAU * 1.1
		runLegs(P, w, 0.3)
		local b = abs(sin(t * math.pi * 2)) -- (1 = ballon dans la main)
		P.Lean = 0.22
		P.RUp = ANG(0.35 + b * 0.15, 0, 0.32)
		P.RLo = 0.35 + b * 0.55
		P.RLoRot = ANG(0, 0, -0.2)
		P.LUp = ANG(0.5, 0, -0.35) -- (bras gauche qui protège)
		P.LLo = 0.9
		P.HeadPitch = -0.1
		P.LookW = 0.2
	end,
}

-- tir en suspension (t = phase 0..1 : flexion, saut, lâcher à 0,55, réception)
ANIMS.p11_shoot = {
	Fallback = "cheer",
	Fn = function(P: any, t: number, _seed: number)
		local u = clamp01(t)
		local crouch = bell(u, 0, 0.32) + bell(u, 0.82, 1) * 0.6
		local up = smooth((u - 0.15) / 0.3) -- bras qui montent
		local flick = smooth((u - 0.5) / 0.12) -- poignet / extension
		P.LTh, P.RTh = 0.5 * crouch + 0.05, 0.5 * crouch + 0.05
		P.LKnee, P.RKnee = 1.0 * crouch, 1.0 * crouch
		P.LFoot, P.RFoot = -0.45 * crouch + 0.35 * bell(u, 0.3, 0.8), -0.45 * crouch + 0.35 * bell(u, 0.3, 0.8)
		P.Lean = 0.18 * crouch - 0.06 * up
		-- bras : ballon devant le visage puis au-dessus de la tête, bras droit tendu
		P.RUp = ANG(0.6 + up * 2.2, 0, 0.1)
		P.RLo = 1.5 - up * 0.5 - flick * 0.95
		P.LUp = ANG(0.6 + up * 2.0, 0, -0.3 + flick * 0.1)
		P.LLo = 1.5 - up * 0.4
		P.HeadPitch = -0.35 * up
		P.LookW = 0
	end,
}

-- ballon tenu à deux mains contre la poitrine
ANIMS.p11_hold = {
	Fallback = "idle",
	Fn = function(P: any, t: number, _seed: number)
		P.LUp = ANG(0.45, 0, -0.32)
		P.RUp = ANG(0.45, 0, 0.32)
		P.LLo, P.RLo = 1.55, 1.55
		P.LTh, P.RTh = 0.12, 0.12
		P.LKnee, P.RKnee = 0.25, 0.25
		P.Lean = 0.08
		P.HeadPitch = -0.1 + sin(t * 1.3) * 0.05
	end,
}

-- passe / réception à deux mains (t = phase : bras qui se tendent vers l'avant)
ANIMS.p11_pass = {
	Fallback = "wave",
	Fn = function(P: any, t: number, _seed: number)
		local u = clamp01(t)
		local ext = bell(u, 0.2, 1)
		P.LUp = ANG(0.6 + ext * 0.7, 0, -0.25 + ext * 0.15)
		P.RUp = ANG(0.6 + ext * 0.7, 0, 0.25 - ext * 0.15)
		P.LLo, P.RLo = 1.5 - ext * 1.2, 1.5 - ext * 1.2
		P.LTh, P.RTh = 0.3 * ext, -0.05
		P.LKnee, P.RKnee = 0.3, 0.35
		P.Lean = 0.15 + ext * 0.1
	end,
}

-- défense : bras écartés, genoux fléchis, pas glissés
ANIMS.p11_defend = {
	Fallback = "idle",
	Fn = function(P: any, t: number, _seed: number)
		local s = sin(t * TAU * 1.6)
		P.LTh, P.RTh = 0.45 + s * 0.08, 0.45 - s * 0.08
		P.LKnee, P.RKnee = 0.9, 0.9
		P.LFoot, P.RFoot = -0.35, -0.35
		P.LThRoll, P.RThRoll = 0.22, -0.22
		P.Lean = 0.3
		P.LUp = ANG(0.4, 0, -0.9 - s * 0.1)
		P.RUp = ANG(0.4, 0, 0.9 - s * 0.1)
		P.LLo, P.RLo = 0.4, 0.4
		P.HeadPitch = -0.3
		P.LookW = 0
	end,
}

-- tennis : coup droit (t = phase, impact à 0,5) : rotation des épaules,
-- bras droit qui balaie d'arrière en avant, accompagnement par-dessus l'épaule
ANIMS.p11_forehand = {
	Fallback = "wave",
	Fn = function(P: any, t: number, _seed: number)
		local u = clamp01(t)
		local back = bell(u, 0, 0.45)
		local swing = smooth((u - 0.3) / 0.35)
		P.Twist = 0.75 * back - 0.6 * swing + 0.3 * smooth((u - 0.7) / 0.3)
		P.RUp = ANG(-0.6 * back + 1.3 * swing, 0.3 * swing, 0.9 - 0.5 * swing)
		P.RLo = 0.5 + 0.9 * smooth((u - 0.6) / 0.3)
		P.LUp = ANG(0.8 * back + 0.2, 0, -0.4)
		P.LLo = 0.9
		P.LTh, P.RTh = 0.35, 0.15
		P.LKnee, P.RKnee = 0.6, 0.6
		P.LThRoll, P.RThRoll = 0.15, -0.15
		P.Lean = 0.22
		P.HeadPitch = -0.15
		P.LookW = 0
	end,
}

-- revers à deux mains (t = phase)
ANIMS.p11_backhand = {
	Fallback = "wave",
	Fn = function(P: any, t: number, _seed: number)
		local u = clamp01(t)
		local back = bell(u, 0, 0.45)
		local swing = smooth((u - 0.3) / 0.35)
		P.Twist = -0.8 * back + 0.65 * swing
		P.RUp = ANG(0.4 + 0.9 * swing, 0, -0.5 + 0.5 * swing)
		P.RLo = 0.9 - 0.4 * swing
		P.LUp = ANG(0.3 + 0.9 * swing, 0, 0.1 + 0.3 * swing)
		P.LLo = 1.1 - 0.3 * swing
		P.LTh, P.RTh = 0.15, 0.35
		P.LKnee, P.RKnee = 0.6, 0.6
		P.LThRoll, P.RThRoll = 0.15, -0.15
		P.Lean = 0.22
		P.HeadPitch = -0.15
		P.LookW = 0
	end,
}

-- service / smash (t = phase : lancer de la main gauche, armé, frappe haute à 0,55)
ANIMS.p11_serve = {
	Fallback = "cheer",
	Fn = function(P: any, t: number, _seed: number)
		local u = clamp01(t)
		local toss = smooth(u / 0.3)
		local arm = smooth((u - 0.2) / 0.3)
		local hit = smooth((u - 0.5) / 0.15)
		P.LUp = ANG(0.4 + toss * 2.3 - hit * 2.0, 0, -0.1)
		P.LLo = 0.2
		P.RUp = ANG(0.2 + arm * 2.6 - hit * 1.4, 0, 0.6 - arm * 0.3)
		P.RLo = 1.6 * arm * (1 - hit) + 0.3
		P.Lean = -0.15 * arm + 0.45 * hit
		P.LTh, P.RTh = 0.1 + 0.3 * hit, -0.1
		P.LKnee, P.RKnee = 0.5 * (1 - hit) + 0.2, 0.6 * (1 - hit) + 0.3
		P.HeadPitch = -0.6 * arm * (1 - hit) + 0.2 * hit
		P.LookW = 0
	end,
}

-- foot : frappe du pied droit (t = phase, contact à 0,5)
ANIMS.p11_kick = {
	Fallback = "walk",
	Fn = function(P: any, t: number, _seed: number)
		local u = clamp01(t)
		local back = bell(u, 0, 0.5)
		local fwd = smooth((u - 0.38) / 0.25) * (1 - smooth((u - 0.8) / 0.2))
		P.RTh = -0.7 * back + 1.25 * fwd
		P.RKnee = 1.5 * back + 0.15
		P.RFoot = 0.35 * fwd
		P.LTh, P.LKnee = 0.25, 0.45
		P.LUp = ANG(0.3, 0, -0.9) -- (bras d'équilibre)
		P.RUp = ANG(-0.3 * fwd, 0, 0.5)
		P.LLo, P.RLo = 0.5, 0.5
		P.Lean = 0.12 - 0.15 * fwd
		P.HeadPitch = 0.35
		P.LookW = 0
	end,
}

-- gardien : plongeon latéral (t = phase ; le corps entier est basculé par
-- le placement, ici les bras tendus et les jambes)
ANIMS.p11_dive = {
	Fallback = "cheer",
	Fn = function(P: any, t: number, _seed: number)
		local u = clamp01(t)
		local s = bell(u, 0, 1)
		P.LUp = ANG(0.3, 0, -2.6 * s)
		P.RUp = ANG(0.3, 0, 2.6 * s)
		P.LLo, P.RLo = 0.2, 0.2
		P.LTh, P.RTh = 0.2 * s, -0.1
		P.LKnee, P.RKnee = 0.3 + 0.4 * s, 0.5
		P.HeadPitch = -0.2 * s
		P.LookW = 0
	end,
}

-- ping-pong : petit coup de raquette (t = phase, impact à 0,5)
ANIMS.p11_paddle = {
	Fallback = "wave",
	Fn = function(P: any, t: number, _seed: number)
		local u = clamp01(t)
		local back = bell(u, 0, 0.5)
		local swing = smooth((u - 0.35) / 0.3)
		P.Twist = 0.4 * back - 0.35 * swing
		P.RUp = ANG(0.55 + 0.6 * swing, 0.2, 0.6 - 0.3 * swing)
		P.RLo = 1.2 - 0.3 * swing
		P.LUp = ANG(0.4, 0, -0.35)
		P.LLo = 1.0
		P.LTh, P.RTh = 0.35, 0.35
		P.LKnee, P.RKnee = 0.55, 0.55
		P.Lean = 0.3
		P.HeadPitch = -0.2
		P.LookW = 0
	end,
}

ParkSports.ANIMS = ANIMS
local animsReady = false
local function ensureAnims()
	if not animsReady then
		animsReady = true
		ParkKit.RegisterAnims(ANIMS)
	end
end

----------------------------------------------------------------------
-- Petit moteur : joueurs placés dans le repère du terrain
----------------------------------------------------------------------

-- yaw pour regarder la direction (dx, dz) du repère (le PNJ regarde -Z)
local function yawOf(dx: number, dz: number, fallback: number): number
	if dx * dx + dz * dz < 1e-6 then
		return fallback
	end
	return math.atan2(-dx, -dz)
end

local function lerpAngle(a: number, b: number, k: number): number
	local d = (b - a + math.pi) % TAU - math.pi
	return a + d * k
end

type Item = { Part: BasePart, Off: CFrame }
type Player = { Model: Model?, Yaw: number, X: number, Z: number, Y: number, Seed: number, Items: { Item }, Tilt: CFrame? }

-- (F : repère posé SUR la surface de jeu)
local function newPlayer(m: Instance, F: CFrame, style: string, seed: number, x: number, z: number, yaw: number): Player
	local model = ParkKit.Person(m, style, seed, F * CFrame.new(x, 0, z) * ANG(0, yaw, 0), "none", true)
	return { Model = model, Yaw = yaw, X = x, Z = z, Y = 0, Seed = seed, Items = {}, Tilt = nil }
end

-- raquette (manche + tamis + cordage) tenue dans la main droite ; le tamis
-- pend sous la main, face vers l'avant (repère de la main = avant-bras)
local function giveRacket(m: Instance, p: Player, color: Color3, handle: number, d: number, strings: boolean)
	local grip = Part(m, "RacketGrip", Vector3.new(handle, 0.17, 0.17), CFrame.new(), rgb(40, 34, 30), M.Fabric, "Cyl")
	grip.CastShadow = false
	table.insert(p.Items, { Part = grip, Off = CFrame.new(0, -handle / 2 + 0.1, -0.05) * ANG(0, 0, math.rad(90)) })
	local head = Part(m, "RacketHead", Vector3.new(0.1, d, d), CFrame.new(), color, M.SmoothPlastic, "Cyl")
	head.CastShadow = false
	table.insert(p.Items, { Part = head, Off = CFrame.new(0, -handle - d / 2 + 0.15, -0.05) * ANG(0, math.rad(90), 0) })
	if strings then
		local mesh = Part(m, "RacketStrings", Vector3.new(0.11, d - 0.16, d - 0.16), CFrame.new(), WHITE, M.Fabric, "Cyl")
		mesh.Transparency = 0.45
		mesh.CastShadow = false
		table.insert(p.Items, { Part = mesh, Off = CFrame.new(0, -handle - d / 2 + 0.15, -0.05) * ANG(0, math.rad(90), 0) })
	end
end

-- place le joueur (x, z, y : saut) tourné vers `yaw` (lissé), puis l'anime
local function pose(F: CFrame, p: Player, x: number, z: number, yaw: number, anim: string, at: number, dt: number, y: number?)
	local model = p.Model
	if not model then
		return
	end
	p.Yaw = lerpAngle(p.Yaw, yaw, min(1, dt * 10))
	p.X, p.Z, p.Y = x, z, y or 0
	local cf = F * CFrame.new(x, p.Y, z) * ANG(0, p.Yaw, 0)
	if p.Tilt then
		cf *= p.Tilt
	end
	local NPC = ParkKit.NPC()
	if NPC and NPC.Place then
		NPC.Place(model, cf)
	else
		model:PivotTo(cf)
	end
	ParkKit.Animate(model, anim, at)
	-- objets tenus (raquette...) : suivent la main droite
	if #p.Items > 0 then
		local hand = ParkKit.Hand(model, "R")
		if hand then
			for _, it in ipairs(p.Items) do
				it.Part.CFrame = hand * it.Off
			end
		end
	end
end

-- position de la main droite (monde), sinon devant le joueur
local function handPos(F: CFrame, p: Player, fallback: Vector3): Vector3
	local hand = p.Model and ParkKit.Hand(p.Model, "R")
	if hand then
		return hand.Position
	end
	return F * fallback
end

local function register(m: Instance, F: CFrame, fn: (t: number, dt: number) -> (), seed: number)
	ParkKit.Actor(m, F.Position, fn, hash(seed, 9) * 40)
end

-- point d'une cloche de a à b (flèche h au-dessus de la corde)
local function arc(a: Vector3, b: Vector3, h: number, u: number): Vector3
	return a:Lerp(b, u) + Vector3.new(0, 4 * h * u * (1 - u), 0)
end

-- grillage (panneaux maillés + poteaux) autour d'un rectangle w x d
local function fence(m: Instance, F: CFrame, w: number, d: number, h: number, color: Color3?)
	local c = color or GREEN_D
	for _, sz in ipairs({ -1, 1 }) do
		local mesh = Box(m, "Mesh", F, -w / 2, w / 2, 0.2, h, sz * d / 2 - 0.03, sz * d / 2 + 0.03, STEEL, M.DiamondPlate, true)
		mesh.Transparency = 0.72
		Box(m, "FenceTop", F, -w / 2, w / 2, h, h + 0.14, sz * d / 2 - 0.08, sz * d / 2 + 0.08, c, M.Metal)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local mesh = Box(m, "Mesh", F, sx * w / 2 - 0.03, sx * w / 2 + 0.03, 0.2, h, -d / 2 + 0.1, d / 2 - 0.1, STEEL, M.DiamondPlate, true)
		mesh.Transparency = 0.72
		Box(m, "FenceTop", F, sx * w / 2 - 0.08, sx * w / 2 + 0.08, h, h + 0.14, -d / 2 + 0.1, d / 2 - 0.1, c, M.Metal)
	end
	local nx = math.max(1, math.floor(w / 8))
	local nz = math.max(1, math.floor(d / 8))
	for i = 0, nx do
		for _, sz in ipairs({ -1, 1 }) do
			Column(m, "FencePost", F, -w / 2 + i * w / nx, sz * d / 2, 0, h + 0.3, 0.3, c, M.Metal, true)
		end
	end
	for i = 1, nz - 1 do
		for _, sx in ipairs({ -1, 1 }) do
			Column(m, "FencePost", F, sx * w / 2, -d / 2 + i * d / nz, 0, h + 0.3, 0.3, c, M.Metal, true)
		end
	end
end

-- ligne peinte (dans le repère F, à la hauteur y)
local function line(m: Instance, F: CFrame, x0: number, x1: number, z0: number, z1: number, y: number, color: Color3?)
	local p = Box(m, "Line", F, x0, x1, y, y + 0.03, z0, z1, color or WHITE, M.SmoothPlastic)
	p.CastShadow = false
	return p
end

-- arc de cercle peint (n tronçons) : centre (cx, cz), rayon r, de a0 à a1
local function paintArc(m: Instance, F: CFrame, cx: number, cz: number, r: number, a0: number, a1: number, y: number, n: number, color: Color3?)
	for i = 0, n - 1 do
		local u0 = a0 + (a1 - a0) * i / n
		local u1 = a0 + (a1 - a0) * (i + 1) / n
		local p0 = Vector3.new(cx + cos(u0) * r, y + 0.015, cz + sin(u0) * r)
		local p1 = Vector3.new(cx + cos(u1) * r, y + 0.015, cz + sin(u1) * r)
		local mid = (p0 + p1) / 2
		local seg = Part(m, "LineArc", Vector3.new(0.22, 0.03, (p1 - p0).Magnitude + 0.04), F * CFrame.lookAt(mid, p1), color or WHITE, M.SmoothPlastic)
		seg.CastShadow = false
	end
end

----------------------------------------------------------------------
-- 🏀 BASKET
----------------------------------------------------------------------

local RIM_Y = 10
local RIM_R = 0.78
local BALL_D = 0.78

-- panier sur poteau (repère H : pied du poteau, -Z = vers le terrain) ;
-- renvoie le centre du cercle (repère H) et le filet (pour le faire trembler)
local function hoop(m: Instance, H: CFrame, color: Color3): (Vector3, { BasePart })
	Box(m, "HoopFoot", H, -1.1, 1.1, 0, 0.3, -1.1, 1.1, rgb(180, 180, 184), M.Concrete, true)
	Column(m, "HoopPole", H, 0, 0, 0.3, 11.6, 0.7, color, M.Metal, true)
	ParkKit.Beam(m, "HoopArm", (H * CFrame.new(0, 11.2, 0)).Position, (H * CFrame.new(0, 11.2, -2.4)).Position, 0.45, 0.45, color, M.Metal)
	ParkKit.Beam(m, "HoopBrace", (H * CFrame.new(0, 9.4, 0)).Position, (H * CFrame.new(0, 10.6, -2.3)).Position, 0.25, 0.25, color, M.Metal)
	local board = Box(m, "Backboard", H, -2.9, 2.9, 9.3, 12.6, -2.75, -2.55, WHITE, M.Glass)
	board.Transparency = 0.3
	Box(m, "BoardFrame", H, -2.95, 2.95, 12.6, 12.75, -2.78, -2.52, IRON, M.Metal)
	Box(m, "BoardFrame", H, -2.95, 2.95, 9.15, 9.3, -2.78, -2.52, IRON, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "BoardFrame", H, sx * 2.95 - 0.15, sx * 2.95, 9.3, 12.6, -2.78, -2.52, IRON, M.Metal)
	end
	-- carré de visée (4 bandes)
	Box(m, "Target", H, -1.0, 1.0, 10.05, 10.17, -2.8, -2.76, rgb(214, 60, 40), M.SmoothPlastic)
	Box(m, "Target", H, -1.0, 1.0, 11.3, 11.42, -2.8, -2.76, rgb(214, 60, 40), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "Target", H, sx * 1.0 - sx * 0.12, sx * 1.0, 10.17, 11.3, -2.8, -2.76, rgb(214, 60, 40), M.SmoothPlastic)
	end
	-- cercle (anneau de 12 tiges) + attache
	local rimC = Vector3.new(0, RIM_Y, -2.8 - RIM_R - 0.05)
	for k = 0, 11 do
		local a0, a1 = k / 12 * TAU, (k + 1) / 12 * TAU
		Rod(m, "Rim", (H * CFrame.new(rimC + Vector3.new(cos(a0) * RIM_R, 0, sin(a0) * RIM_R))).Position, (H * CFrame.new(rimC + Vector3.new(cos(a1) * RIM_R, 0, sin(a1) * RIM_R))).Position, 0.09, rgb(236, 100, 30), M.Metal)
	end
	Box(m, "RimMount", H, -0.2, 0.2, RIM_Y - 0.25, RIM_Y + 0.05, -2.84, -2.55, rgb(236, 100, 30), M.Metal)
	-- filet : 8 cordons en cône (ils tremblent quand le ballon passe)
	local net = {}
	for k = 0, 7 do
		local a = k / 8 * TAU
		local top = rimC + Vector3.new(cos(a) * RIM_R, -0.05, sin(a) * RIM_R)
		local bottom = rimC + Vector3.new(cos(a + 0.4) * RIM_R * 0.55, -1.45, sin(a + 0.4) * RIM_R * 0.55)
		local cord = Rod(m, "NetCord", (H * CFrame.new(top)).Position, (H * CFrame.new(bottom)).Position, 0.05, WHITE, M.Fabric)
		cord:SetAttribute("Top", top)
		cord:SetAttribute("Bottom", bottom)
		table.insert(net, cord)
	end
	return rimC, net
end

local function shakeNet(H: CFrame, net: { BasePart }, k: number, t: number)
	for i, cord in ipairs(net) do
		local top = cord:GetAttribute("Top") :: Vector3
		local bottom = cord:GetAttribute("Bottom") :: Vector3
		if top and bottom then
			local sway = k * 0.35 * sin(t * 30 + i)
			local b = bottom + Vector3.new(sway, k * 0.3, sway * 0.6)
			cord.CFrame = ParkKit.RodCF((H * CFrame.new(top)).Position, (H * CFrame.new(b)).Position)
		end
	end
end

-- Choréographie (repère du terrain, panier à +X) : 3 tirs par cycle,
-- tireur k = rebondeur du tir k-1 (voir PARK11 : la boucle se referme)
local SHOT_T = 6.4
local function basketPlan(seed: number, HX: number)
	-- places : départ / tir / attente ; rebonds L1..L3 ; L3 = départ de A
	local function spot(i: number, r0: number, r1: number, a0: number, a1: number): Vector2
		local r = r0 + hash(seed, i) * (r1 - r0)
		local a = a0 + hash(seed, i + 50) * (a1 - a0)
		return Vector2.new(HX - cos(a) * r, sin(a) * r)
	end
	local L1 = spot(1, 3.5, 6, -1.2, 1.2)
	local L2 = spot(2, 3.5, 6, -1.2, 1.2)
	local L3 = spot(3, 9, 12, -0.9, 0.9)
	local W1 = spot(4, 11, 13, 0.6, 1.2)
	local W2 = spot(5, 11, 13, -1.2, -0.6)
	local W3 = spot(6, 13, 15, -0.4, 0.4)
	local Q = { spot(7, 7.5, 10, -1.0, 1.0), spot(8, 7.5, 10, -1.0, 1.0), spot(9, 6.5, 9, -1.0, 1.0) }
	local makes = { hash(seed, 10) < 0.75, hash(seed, 11) < 0.6, hash(seed, 12) < 0.8 }
	-- tir k : tireur, rebondeur, spectateur, départ, tir, attente, rebond
	return {
		{ S = 1, R = 2, I = 3, From = L3, Q = Q[1], To = W1, L = L1, Make = makes[1], RFrom = W2, IAt = W3 },
		{ S = 2, R = 3, I = 1, From = L1, Q = Q[2], To = W2, L = L2, Make = makes[2], RFrom = W3, IAt = W1 },
		{ S = 3, R = 1, I = 2, From = L2, Q = Q[3], To = W3, L = L3, Make = makes[3], RFrom = W1, IAt = W2 },
	}
end

function ParkSports.Basketball(m: Instance, F: CFrame, seed: number, opts: any?): any
	ensureAnims()
	local o = opts or {}
	local W, D = o.W or 30, o.D or 18
	local floor = o.Floor or rgb(196, 92, 60)
	local outer = o.Outer or rgb(60, 104, 150)
	local Y = 0.24 -- dessus du sol de jeu
	Box(m, "CourtBase", F, -W / 2 - 2, W / 2 + 2, -0.1, Y - 0.04, -D / 2 - 2, D / 2 + 2, outer, M.Concrete, true)
	Box(m, "CourtPlay", F, -W / 2, W / 2, Y - 0.04, Y, -D / 2, D / 2, floor, M.Concrete)
	-- lignes : contour, médiane, rond central, raquettes, lignes à 3 points
	local ly = Y
	line(m, F, -W / 2, W / 2, -D / 2, -D / 2 + 0.2, ly)
	line(m, F, -W / 2, W / 2, D / 2 - 0.2, D / 2, ly)
	line(m, F, -W / 2, -W / 2 + 0.2, -D / 2 + 0.2, D / 2 - 0.2, ly)
	line(m, F, W / 2 - 0.2, W / 2, -D / 2 + 0.2, D / 2 - 0.2, ly)
	line(m, F, -0.1, 0.1, -D / 2 + 0.2, D / 2 - 0.2, ly)
	paintArc(m, F, 0, 0, 3.6, 0, TAU, ly, 16)
	local HX = W / 2 - 1.2 -- pied du poteau ... cercle à HX - 3,6
	for _, sx in ipairs({ -1, 1 }) do
		local key = Box(m, "Key", F, sx * (W / 2 - 0.2), sx * (W / 2 - 9), ly, ly + 0.02, -2.9, 2.9, outer, M.SmoothPlastic)
		key.CastShadow = false
		line(m, F, sx * (W / 2 - 9) - 0.1, sx * (W / 2 - 9) + 0.1, -2.9, 2.9, ly + 0.01)
		paintArc(m, F, sx * (W / 2 - 9), 0, 2.9, sx > 0 and math.pi / 2 or -math.pi / 2, sx > 0 and math.pi * 1.5 or math.pi / 2, ly + 0.01, 8)
		-- ligne à 3 points : arc autour du cercle + 2 droites jusqu'à la ligne de fond
		local rx, r3 = sx * (W / 2 - 3.8), math.min(8.5, D / 2 - 0.6)
		local half = math.asin(math.min(0.999, (D / 2 - 0.6) / r3))
		local a0 = sx > 0 and math.pi - half or -half
		local a1 = sx > 0 and math.pi + half or half
		if sx > 0 then
			a0, a1 = math.pi / 2 + (math.pi / 2 - half), math.pi * 1.5 - (math.pi / 2 - half)
		end
		paintArc(m, F, rx, 0, r3, a0, a1, ly, 14)
		local ex = rx + cos(a0) * r3
		for _, sz in ipairs({ -1, 1 }) do
			local ez = sz * abs(sin(a0) * r3)
			line(m, F, math.min(ex, sx * (W / 2 - 0.2)), math.max(ex, sx * (W / 2 - 0.2)), ez - 0.1, ez + 0.1, ly)
		end
	end
	local hoopColor = o.Hoop or rgb(36, 64, 120)
	local Hp = F * CFrame.new(W / 2 + 1.2, Y, 0) * ANG(0, -math.pi / 2, 0)
	local rimL, netP = hoop(m, Hp, hoopColor)
	local Hm = F * CFrame.new(-W / 2 - 1.2, Y, 0) * ANG(0, math.pi / 2, 0)
	hoop(m, Hm, hoopColor)
	if o.Fence ~= false then
		fence(m, F * CFrame.new(0, Y - 0.2, 0), W + 6, D + 3, 9)
	end
	-- banc de touche
	ParkKit.Bench(m, F * CFrame.new(0, Y, D / 2 + 0.6) * ANG(0, 0, 0), 5.6)
	local rim = (Hp * CFrame.new(rimL)).Position
	local rimLocal = F:PointToObjectSpace(rim)
	HX = rimLocal.X
	-- joueurs + ballon
	local styles = { "jogger", "kid", "pedestrian" }
	local plan = basketPlan(seed, HX)
	local players: { Player } = {}
	local FP = F * CFrame.new(0, Y, 0)
	for i = 1, 3 do
		local start = i == 1 and plan[1].From or (i == 2 and plan[1].RFrom or plan[1].IAt)
		table.insert(players, newPlayer(m, FP, styles[i], seed * 7 + i, start.X, start.Y, 0))
	end
	local ball = Part(m, "Basketball", Vector3.new(BALL_D, BALL_D, BALL_D), F * CFrame.new(0, 1, 0), rgb(222, 104, 36), M.Rubber, "Ball")
	for k = 0, 1 do
		local seam = Part(m, "BallSeam", Vector3.new(0.03, BALL_D + 0.01, BALL_D + 0.01), F, rgb(40, 24, 18), M.SmoothPlastic, "Cyl")
		seam:SetAttribute("Seam", k)
	end
	local game = { Kind = "Basketball", F = F, FP = FP, Players = players, Ball = ball, Plan = plan, Rim = rimLocal, Y = Y, Hoop = Hp, Net = netP, Last = 0, Model = m }
	register(m, F, function(t: number, dt: number)
		ParkSports.Step(game, t, dt)
	end, seed)
	return game
end

-- Ordres de placement d'une image, puis SÉPARATION : deux joueurs ne se
-- rentrent jamais dedans (écart mini MIN_GAP, poussés l'un de l'autre)
local MIN_GAP = 1.7
type Order = { P: Player, X: number, Z: number, Yaw: number, Anim: string, At: number, Y: number? }

local function separate(orders: { Order })
	for _ = 1, 3 do
		for i = 1, #orders do
			for j = i + 1, #orders do
				local a, b = orders[i], orders[j]
				local dx, dz = b.X - a.X, b.Z - a.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < MIN_GAP then
					if d < 1e-3 then
						dx, dz, d = 1, 0, 1
					end
					local push = (MIN_GAP - d) / 2 + 0.01
					a.X -= dx / d * push
					a.Z -= dz / d * push
					b.X += dx / d * push
					b.Z += dz / d * push
				end
			end
		end
	end
end

local function apply(FP: CFrame, orders: { Order }, dt: number)
	separate(orders)
	for _, o in ipairs(orders) do
		pose(FP, o.P, o.X, o.Z, o.Yaw, o.Anim, o.At, dt, o.Y)
	end
end

local function stepBasket(G: any, t: number, dt: number)
	local F, Y, FP = G.F, G.Y, G.FP
	local cycle = SHOT_T * 3
	local tc = t % cycle
	local k = math.floor(tc / SHOT_T) + 1
	local u = tc - (k - 1) * SHOT_T
	local s = G.Plan[k]
	local P = G.Players
	local rim = G.Rim
	local shooter, reb, idle = P[s.S], P[s.R], P[s.I]
	local ballPos: Vector3? = nil
	local ballMode = "free"
	local netShake = 0
	local orders: { Order } = {}
	local function order(p: Player, x: number, z: number, yaw: number, anim: string, at: number, y: number?)
		table.insert(orders, { P = p, X = x, Z = z, Yaw = yaw, Anim = anim, At = at, Y = y })
	end
	local function toward(a: Vector2, b: Vector2, v: number): (number, number, number)
		local p = a:Lerp(b, smooth(v))
		local d = b - a
		return p.X, p.Y, yawOf(d.X, d.Y, 0)
	end
	local faceRim = function(x: number, z: number): number
		return yawOf(rim.X - x, rim.Z - z, 0)
	end
	-- TIREUR : dribble jusqu'au point de tir (0 -> 2,4), tir (2,4 -> 3,4),
	-- puis trottine vers sa place d'attente
	if u < 2.4 then
		local x, z, yw = toward(s.From, s.Q, u / 2.4)
		if u > 2.0 then
			yw = faceRim(x, z)
		end
		order(shooter, x, z, yw, "p11_dribble", t)
		ballMode = "dribble"
	elseif u < 3.4 then
		local ph = (u - 2.4) / 1.0
		local jump = bell(ph, 0.25, 0.85) * 1.6
		order(shooter, s.Q.X, s.Q.Y, faceRim(s.Q.X, s.Q.Y), "p11_shoot", ph, jump)
		if ph < 0.55 then
			ballMode = "shoot"
		end
	else
		local v = clamp01((u - 3.4) / 2.2)
		local x, z, yw = toward(s.Q, s.To, v)
		if v >= 1 then
			yw = faceRim(x, z)
		end
		order(shooter, x, z, yw, v < 1 and "p11_jog" or "p11_ready", t)
	end
	-- vol du ballon (lâcher à 2,95 -> cercle à 4,15)
	local release = 2.4 + 0.55
	local arrive = 4.15
	local relPos = G.Release or F * Vector3.new(s.Q.X, Y + 1.6 * bell(0.55, 0.25, 0.85) + 6.9, s.Q.Y)
	if u < 2.4 then
		G.Release = nil
	end
	local rimW = F * Vector3.new(rim.X, rim.Y + BALL_D / 2 + 0.05, rim.Z)
	local landW = F * Vector3.new(s.L.X, Y + BALL_D / 2, s.L.Y)
	local catchT = 5.15
	if u >= release and u < arrive then
		local v = (u - release) / (arrive - release)
		ballPos = arc(relPos, rimW, 3.6, v)
	elseif u >= arrive and u < catchT then
		local v = (u - arrive) / (catchT - arrive)
		if s.Make then
			-- dans le filet puis rebonds amortis vers le rebondeur
			if v < 0.22 then
				local w = v / 0.22
				ballPos = rimW:Lerp(rimW - Vector3.new(0, 2.2, 0), w * w)
				netShake = 1 - w * 0.5
			else
				local w = (v - 0.22) / 0.78
				local from = rimW - Vector3.new(0, 2.2, 0)
				local hb = 2.4 * (1 - w) ^ 2
				local flat = from:Lerp(landW, w)
				local bounceY = abs(sin(w * math.pi * 2)) * hb
				ballPos = Vector3.new(flat.X, max(landW.Y, from.Y * (1 - smooth(w * 3)) + landW.Y * smooth(w * 3)) + bounceY, flat.Z)
				netShake = max(0, 0.5 - w)
			end
		else
			-- sur l'arceau : rebond haut vers le rebondeur
			ballPos = arc(rimW, landW + Vector3.new(0, 2.2, 0), 2.6, min(1, v * 1.15))
			netShake = max(0, 0.4 - v)
		end
	end
	-- REBONDEUR : de sa place d'attente au point de rebond, attrape, garde
	-- le ballon, se tourne vers le panier
	local runStart = 3.1
	if u < runStart then
		order(reb, s.RFrom.X, s.RFrom.Y, faceRim(s.RFrom.X, s.RFrom.Y), "p11_ready", t)
	elseif u < catchT then
		local v = (u - runStart) / (catchT - runStart)
		local x, z, yw = toward(s.RFrom, s.L, v)
		order(reb, x, z, yw, v < 0.85 and "p11_run" or "p11_pass", v < 0.85 and t or (v - 0.85) / 0.15 * 0.5)
	else
		order(reb, s.L.X, s.L.Y, faceRim(s.L.X, s.L.Y), "p11_hold", t)
		ballMode = "hold"
	end
	-- SPECTATEUR : prêt, suit le jeu
	order(idle, s.IAt.X, s.IAt.Y, faceRim(s.IAt.X, s.IAt.Y), "p11_ready", t + idle.Seed)
	apply(FP, orders, dt)
	-- ballon tenu : d'après la main (après la pose)
	if ballMode == "dribble" then
		-- entre la main et le sol, 2 rebonds / s (|sin| : rebond net au sol)
		local h = abs(sin(t * math.pi * 2))
		local side = FP * CFrame.new(shooter.X, 0, shooter.Z) * ANG(0, shooter.Yaw, 0)
		local top = 2.55
		ballPos = (side * CFrame.new(0.85, 0, -0.85)).Position + Vector3.new(0, BALL_D / 2 + (top - BALL_D / 2) * h, 0)
	elseif ballMode == "shoot" then
		local hp = handPos(F, shooter, Vector3.new(shooter.X, Y + 6.5, shooter.Z))
		ballPos = hp + Vector3.new(0, 0.35, 0)
		G.Release = ballPos
	elseif ballMode == "hold" then
		local hp = handPos(F, reb, Vector3.new(reb.X, Y + 3.6, reb.Z - 0.6))
		local root = reb.Model and reb.Model.PrimaryPart
		local fwd = root and root.CFrame.LookVector or Vector3.zero
		ballPos = hp + fwd * 0.25 + Vector3.new(0, 0.2, 0)
	end
	if ballPos then
		local spin = ANG(t * 9, t * 2, 0)
		G.Ball.CFrame = CFrame.new(ballPos) * spin
		local i = 0
		for _, c in ipairs(G.Model:GetChildren()) do
			if c.Name == "BallSeam" and c:IsA("BasePart") then
				c.CFrame = CFrame.new(ballPos) * spin * ANG(0, i * math.pi / 2, 0)
				i += 1
			end
		end
		G.BallAt = ballPos
	end
	if netShake > 0 or G.NetShaking then
		shakeNet(G.Hoop, G.Net, netShake, t)
		G.NetShaking = netShake > 0
	end
end

----------------------------------------------------------------------
-- 🎾 TENNIS (un court ; 2 joueurs en fond de court)
----------------------------------------------------------------------

local RALLY_T = 1.15 -- (s) d'une frappe à la suivante

function ParkSports.Tennis(m: Instance, F: CFrame, seed: number, opts: any?): any
	ensureAnims()
	local o = opts or {}
	local L, Wd = o.L or 36, o.W or 16 -- longueur (X) / largeur (Z) du court
	local surface = o.Surface or pick({ "clay", "hard", "grass" }, seed, 4)
	local col = surface == "clay" and rgb(196, 108, 68) or (surface == "grass" and rgb(92, 160, 80) or rgb(56, 104, 168))
	local outer = surface == "clay" and rgb(180, 98, 62) or (surface == "grass" and rgb(80, 146, 72) or rgb(70, 130, 96))
	local mat = surface == "clay" and M.Sand or (surface == "grass" and M.Grass or M.Concrete)
	local Y = 0.2
	Box(m, "TennisBase", F, -L / 2 - 4, L / 2 + 4, -0.1, Y - 0.04, -Wd / 2 - 3, Wd / 2 + 3, outer, mat, true)
	Box(m, "TennisCourt", F, -L / 2, L / 2, Y - 0.04, Y, -Wd / 2, Wd / 2, col, mat)
	-- lignes : fond, côtés (double + simple), service, médiane
	local sw = Wd / 2 - 1.8 -- couloir du simple
	line(m, F, -L / 2, -L / 2 + 0.2, -Wd / 2, Wd / 2, Y)
	line(m, F, L / 2 - 0.2, L / 2, -Wd / 2, Wd / 2, Y)
	for _, z in ipairs({ -Wd / 2, Wd / 2 - 0.2, -sw, sw - 0.2 }) do
		line(m, F, -L / 2, L / 2, z, z + 0.2, Y)
	end
	local sv = L / 2 * 0.53
	line(m, F, -sv - 0.1, -sv + 0.1, -sw, sw, Y)
	line(m, F, sv - 0.1, sv + 0.1, -sw, sw, Y)
	line(m, F, -sv, sv, -0.1, 0.1, Y)
	-- filet : poteaux, maille, bande blanche (un peu plus haut aux poteaux)
	for _, sz in ipairs({ -1, 1 }) do
		Column(m, "NetPost", F, 0, sz * (Wd / 2 + 0.6), Y, Y + 3.5, 0.3, IRON, M.Metal, true)
	end
	local net = Box(m, "TennisNet", F, -0.03, 0.03, Y + 0.25, Y + 3.0, -Wd / 2 - 0.5, Wd / 2 + 0.5, rgb(24, 26, 30), M.Fabric)
	net.Transparency = 0.55
	Box(m, "NetTape", F, -0.07, 0.07, Y + 3.0, Y + 3.25, -Wd / 2 - 0.5, Wd / 2 + 0.5, WHITE, M.Fabric)
	Box(m, "NetStrap", F, -0.06, 0.06, Y + 0.25, Y + 3.0, -0.12, 0.12, WHITE, M.Fabric)
	-- chaise d'arbitre
	local U = F * CFrame.new(0, Y, Wd / 2 + 2.2)
	for _, sx in ipairs({ -0.8, 0.8 }) do
		for _, sz in ipairs({ -0.6, 0.6 }) do
			Column(m, "UmpireLeg", U, sx, sz, 0, 6.2, 0.18, WHITE, M.Metal)
		end
	end
	Box(m, "UmpireSeat", U, -1, 1, 6.2, 6.4, -0.8, 0.8, rgb(30, 90, 60), M.Wood)
	Box(m, "UmpireBack", U, -1, 1, 6.4, 8, 0.7, 0.8, rgb(30, 90, 60), M.Wood)
	for i = 1, 3 do
		Box(m, "UmpireRung", U, -0.85, 0.85, i * 1.5, i * 1.5 + 0.12, -0.66, -0.54, WHITE, M.Metal)
	end
	if o.Fence ~= false then
		fence(m, F * CFrame.new(0, Y - 0.2, 0), L + 8, Wd + 6, 10, rgb(30, 80, 60))
	end
	-- joueurs : A en -X (regarde +X), B en +X
	local FP = F * CFrame.new(0, Y, 0)
	local players = {
		newPlayer(m, FP, "jogger", seed * 5 + 1, -L / 2 - 1, 0, -math.pi / 2),
		newPlayer(m, FP, pick({ "pedestrian", "jogger" }, seed, 6), seed * 5 + 2, L / 2 + 1, 0, math.pi / 2),
	}
	for i, p in ipairs(players) do
		giveRacket(m, p, i == 1 and rgb(40, 40, 46) or rgb(200, 40, 50), 0.8, 1.05, true)
	end
	local ball = Part(m, "TennisBall", Vector3.new(0.3, 0.3, 0.3), F, rgb(214, 236, 60), M.Fabric, "Ball")
	ball.CastShadow = false
	local game = { Kind = "Tennis", F = F, FP = FP, Players = players, Ball = ball, L = L, Wd = Wd, Y = Y, Seed = seed, Model = m }
	register(m, F, function(t: number, dt: number)
		ParkSports.Step(game, t, dt)
	end, seed)
	return game
end

-- Un POINT : service (frappe 0 à SERVE_T) puis N frappes alternées, la
-- dernière finit dans le filet. Frappe k au temps H(k) = SERVE_T + k x RALLY_T,
-- par A si k est pair. Le joueur se place pour que la balle passe à sa
-- droite (coup droit) ou à sa gauche (revers), y va en pas chassés après la
-- frappe adverse, frappe, puis se recentre.
local SHOTS = 7
local SERVE_T = 1.6

local function tennisPoint(G: any, pt: number)
	local cache = G.Points or {}
	G.Points = cache
	local P = cache[pt % 8]
	if P and P.Id == pt then
		return P
	end
	local seed = G.Seed * 31 + pt * 13
	local half = G.Wd / 2 - 2.8
	local hitX = G.L / 2 - 1.6
	local hits = {}
	for k = 0, SHOTS do
		local who = k % 2 == 0 and -1 or 1
		local z = k == 0 and 1.0 or (hash(seed, k * 3 + 1) * 2 - 1) * half
		local fore = k == 0 or hash(seed, k * 3 + 2) < 0.68
		-- côté droit du joueur : +Z pour A (regarde +X), -Z pour B
		local right = who < 0 and 1 or -1
		local body = z - right * (fore and 0.95 or -0.95)
		table.insert(hits, { X = who * hitX, Y = G.Y + (k == 0 and 6.4 or 2.6), Z = z, Fore = fore, Body = body, Who = who })
	end
	P = { Id = pt, Hits = hits, HitX = hitX }
	cache[pt % 8] = P
	return P
end

local function stepTennis(G: any, t: number, dt: number)
	local F, Y, FP = G.F, G.Y, G.FP
	local period = SERVE_T + SHOTS * RALLY_T + 1.8
	local pt = math.floor(t / period)
	local u = t - pt * period
	local P = tennisPoint(G, pt)
	local hits = P.Hits
	local function H(k: number): number
		return SERVE_T + k * RALLY_T
	end
	local ballPos: Vector3
	if u < SERVE_T then
		-- lancer de balle (main gauche) : monte puis redescend au point d'impact
		local ph = u / SERVE_T
		local h0, top = Y + 3.6, Y + 7.6
		local y
		if ph < 0.5 then
			y = h0 + (top - h0) * (1 - (1 - 2 * ph) ^ 2)
		else
			y = top - (top - hits[1].Y) * ((ph - 0.5) / 0.5) ^ 2
		end
		ballPos = F * Vector3.new(hits[1].X + 0.2, y, hits[1].Z)
	elseif u < H(SHOTS) then
		local k = math.floor((u - SERVE_T) / RALLY_T)
		local v = (u - H(k)) / RALLY_T
		local a, b = hits[k + 1], hits[k + 2]
		local from = Vector3.new(a.X, a.Y, a.Z)
		local to = Vector3.new(b.X, b.Y, b.Z)
		-- rebond dans le camp adverse (à 70 % du trajet), cloche au-dessus du filet
		local bounce = Vector3.new(from.X + (to.X - from.X) * 0.7, Y + 0.15, from.Z + (to.Z - from.Z) * 0.7)
		if v < 0.62 then
			ballPos = F * arc(from, bounce, k == 0 and 0.4 or 2.3, v / 0.62)
		else
			ballPos = F * arc(bounce, to, 1.25, (v - 0.62) / 0.38)
		end
	else
		-- dernière frappe : dans le filet, puis la balle retombe et roule
		local v = clamp01((u - H(SHOTS)) / 1.4)
		local a = hits[SHOTS + 1]
		local from = Vector3.new(a.X, a.Y, a.Z)
		local into = Vector3.new(0.4 * -a.Who * -1, Y + 1.6, a.Z * 0.6)
		if v < 0.4 then
			ballPos = F * arc(from, into, 0.7, v / 0.4)
		else
			local w = (v - 0.4) / 0.6
			ballPos = F * Vector3.new(into.X + a.Who * 1.5 * w, Y + 0.15 + abs(sin(w * math.pi * 3)) * 1.4 * (1 - w) ^ 2, into.Z)
		end
	end
	G.Ball.CFrame = CFrame.new(ballPos)
	G.BallAt = ballPos
	for side, p in ipairs(G.Players) do
		local who = side == 1 and -1 or 1
		local face = side == 1 and -math.pi / 2 or math.pi / 2
		-- mes frappes : k de même parité que moi
		local first = side == 1 and 0 or 1
		local prevK, nextK = nil, nil
		for k = first, SHOTS, 2 do
			if H(k) <= u then
				prevK = k
			elseif not nextK then
				nextK = k
			end
		end
		local x = who * (P.HitX + 0.4)
		local z, anim, at = 0, "p11_ready", t + side
		local zPrev = prevK and hits[prevK + 1].Body or (side == 1 and hits[1].Body or 0)
		if nextK then
			local zNext = hits[nextK + 1].Body
			-- départ quand l'adversaire frappe, arrivée 0,2 s avant ma frappe
			local go = nextK > 0 and H(nextK - 1) or 0
			local arrive = H(nextK) - 0.22
			local w = clamp01((u - go) / max(0.1, arrive - go))
			z = zPrev + (zNext - zPrev) * smooth(w)
			if w > 0 and w < 1 and abs(zNext - zPrev) > 0.8 then
				anim, at = "p11_defend", t
			end
		else
			-- point fini : se recentre
			local w = clamp01((u - H(SHOTS)) / 1.4)
			z = zPrev * (1 - smooth(w))
			if w > 0 and w < 1 then
				anim, at = "p11_jog", t
			end
		end
		-- geste autour de chaque frappe
		for _, k in ipairs({ prevK, nextK }) do
			if k and abs(u - H(k)) < 0.42 then
				if k == 0 then
					anim, at = "p11_serve", 0.55 + (u - H(0)) / 0.42 * 0.45
				else
					anim = hits[k + 1].Fore and "p11_forehand" or "p11_backhand"
					at = 0.5 + (u - H(k)) / 0.84
				end
			end
		end
		if side == 1 and u < SERVE_T then
			anim, at = "p11_serve", 0.55 * u / SERVE_T
			z = hits[1].Body
		end
		pose(FP, p, x, z, face, anim, at, dt)
	end
end

----------------------------------------------------------------------
-- ⚽ FOOT (terrain à 5 : passes en triangle, tir, gardien)
----------------------------------------------------------------------

local PASS_T = 1.7

local function goal(m: Instance, G: CFrame)
	-- (G : milieu de la ligne de but, -Z vers le terrain)
	for _, sx in ipairs({ -3.6, 3.6 }) do
		Column(m, "GoalPost", G, sx, 0, 0, 6.6, 0.32, WHITE, M.Metal, true)
		Rod(m, "GoalStay", (G * CFrame.new(sx, 6.4, 0)).Position, (G * CFrame.new(sx, 0.1, 3)).Position, 0.12, WHITE, M.Metal)
	end
	Box(m, "GoalBar", G, -3.76, 3.76, 6.45, 6.77, -0.16, 0.16, WHITE, M.Metal)
	local back = Box(m, "GoalNet", G, -3.6, 3.6, 0, 6.4, 2.96, 3.02, WHITE, M.Fabric)
	back.Transparency = 0.6
	for _, sx in ipairs({ -3.6, 3.6 }) do
		local side = Part(m, "GoalNetSide", Vector3.new(0.05, 6.4, 3), G * CFrame.new(sx, 3.2, 1.5), WHITE, M.Fabric)
		side.Transparency = 0.6
	end
	local top = Box(m, "GoalNetTop", G, -3.6, 3.6, 6.38, 6.44, 0.16, 2.96, WHITE, M.Fabric)
	top.Transparency = 0.6
	return back
end

function ParkSports.Football(m: Instance, F: CFrame, seed: number, opts: any?): any
	ensureAnims()
	local o = opts or {}
	local W, D = o.W or 46, o.D or 28
	local Y = 0.16
	local green = rgb(72, 152, 72)
	Box(m, "Turf", F, -W / 2 - 1, W / 2 + 1, -0.1, Y, -D / 2 - 1, D / 2 + 1, green, M.Grass, true)
	for i = 0, 7 do
		if i % 2 == 0 then
			local x0 = -W / 2 + i * W / 8
			local s = Box(m, "TurfStripe", F, x0, x0 + W / 8, Y, Y + 0.02, -D / 2, D / 2, rgb(86, 168, 82), M.Grass)
			s.CastShadow = false
		end
	end
	local ly = Y + 0.02
	line(m, F, -W / 2 + 1, W / 2 - 1, -D / 2 + 1, -D / 2 + 1.2, ly)
	line(m, F, -W / 2 + 1, W / 2 - 1, D / 2 - 1.2, D / 2 - 1, ly)
	line(m, F, -W / 2 + 1, -W / 2 + 1.2, -D / 2 + 1.2, D / 2 - 1.2, ly)
	line(m, F, W / 2 - 1.2, W / 2 - 1, -D / 2 + 1.2, D / 2 - 1.2, ly)
	line(m, F, -0.1, 0.1, -D / 2 + 1.2, D / 2 - 1.2, ly)
	paintArc(m, F, 0, 0, 4.6, 0, TAU, ly, 18)
	for _, sx in ipairs({ -1, 1 }) do
		-- surface de réparation
		line(m, F, sx * (W / 2 - 1.2) - (sx > 0 and 7 or 0), sx * (W / 2 - 1.2) + (sx < 0 and 7 or 0), -7, -6.8, ly)
		line(m, F, sx * (W / 2 - 1.2) - (sx > 0 and 7 or 0), sx * (W / 2 - 1.2) + (sx < 0 and 7 or 0), 6.8, 7, ly)
		line(m, F, sx * (W / 2 - 8.2) - 0.1, sx * (W / 2 - 8.2) + 0.1, -7, 7, ly)
	end
	local GP = F * CFrame.new(W / 2 - 1.1, Y, 0) * ANG(0, -math.pi / 2, 0)
	local netBack = goal(m, GP)
	goal(m, F * CFrame.new(-W / 2 + 1.1, Y, 0) * ANG(0, math.pi / 2, 0))
	if o.Fence ~= false then
		fence(m, F * CFrame.new(0, Y - 0.2, 0), W + 4, D + 4, 8, rgb(40, 90, 60))
	end
	-- 3 joueurs en triangle (attaque vers +X) + gardien
	local tri = {
		Vector2.new(W / 2 - 18 + hash(seed, 1) * 3, -6 - hash(seed, 2) * 3),
		Vector2.new(W / 2 - 24 + hash(seed, 3) * 3, 3 + hash(seed, 4) * 3),
		Vector2.new(W / 2 - 13 + hash(seed, 5) * 2, 6 + hash(seed, 6) * 2),
	}
	local players: { Player } = {}
	local FP = F * CFrame.new(0, Y, 0)
	for i = 1, 3 do
		table.insert(players, newPlayer(m, FP, i == 2 and "jogger" or "kid", seed * 9 + i, tri[i].X, tri[i].Y, 0))
	end
	local keeper = newPlayer(m, FP, "kid", seed * 9 + 7, W / 2 - 2.6, 0, math.pi / 2)
	-- maillot du gardien (gants) : rien de plus, sa pose suffit
	local ball = Part(m, "Football", Vector3.new(0.85, 0.85, 0.85), F, WHITE, M.SmoothPlastic, "Ball")
	for k = 0, 2 do
		local patch = Part(m, "BallPatch", Vector3.new(0.3, 0.3, 0.3), F, rgb(30, 30, 34), M.SmoothPlastic, "Ball")
		patch:SetAttribute("Patch", k)
	end
	local game = { Kind = "Football", F = F, FP = FP, Players = players, Keeper = keeper, Ball = ball, Tri = tri, W = W, Y = Y, Seed = seed, Net = netBack, Model = m }
	register(m, F, function(t: number, dt: number)
		ParkSports.Step(game, t, dt)
	end, seed)
	return game
end

local function stepFootball(G: any, t: number, dt: number)
	local F, W, Y, FP = G.F, G.W, G.Y, G.FP
	local tri = G.Tri
	local passes = 4
	local period = passes * PASS_T + 3.6
	local cyc = math.floor(t / period)
	local u = t - cyc * period
	local R = 0.425
	local ballPos: Vector3
	local P = G.Players
	-- passe k : du joueur ((k-1) % 3)+1 au suivant
	local function at(i: number): Vector2
		return tri[((i - 1) % 3) + 1]
	end
	local goalX = W / 2 - 1.1
	local shooterI = ((passes) % 3) + 1
	local shotStart = passes * PASS_T
	local keeper = G.Keeper
	local saveSide = hash(G.Seed, cyc) < 0.5 and -1 or 1
	local scored = hash(G.Seed + 3, cyc) < 0.55
	local aimZ = saveSide * (scored and 2.6 or 1.4)
	if u < shotStart then
		local k = math.floor(u / PASS_T)
		local v = (u - k * PASS_T) / PASS_T
		local from, to = at(k + 1), at(k + 2)
		-- frappe à 0,15 ; roule (décélère) ; contrôlé à 0,85
		local w = clamp01((v - 0.15) / 0.7)
		local e = 1 - (1 - w) ^ 1.6
		local p = from:Lerp(to, e)
		local lead = (to - from).Unit
		local fp = from + lead * 0.9
		local tp = to - lead * 0.9
		p = fp:Lerp(tp, e)
		ballPos = F * Vector3.new(p.X, Y + R + abs(sin(w * math.pi * 2)) * 0.15 * (1 - w), p.Y)
		for i = 1, 3 do
			local me = P[i]
			local pos = at(i)
			local kicker = ((k) % 3) + 1 == i
			local receiver = ((k + 1) % 3) + 1 == i
			local look = kicker and to or (receiver and from or Vector2.new(p.X, p.Y))
			local yaw = yawOf(look.X - pos.X, look.Y - pos.Y, 0)
			if kicker and v < 0.4 then
				pose(FP, me, pos.X, pos.Y, yaw, "p11_kick", v / 0.3, dt)
			elseif receiver and v > 0.75 then
				pose(FP, me, pos.X, pos.Y, yaw, "p11_ready", t, dt)
			else
				pose(FP, me, pos.X + sin(t * 0.7 + i) * 0.4, pos.Y + cos(t * 0.5 + i) * 0.4, yaw, i == 2 and "p11_jog" or "p11_ready", t + i, dt)
			end
		end
		pose(FP, keeper, goalX - 1.6, sin(t * 1.1) * 0.8, math.pi / 2, "p11_ready", t, dt)
		keeper.Tilt = nil
	else
		local v = u - shotStart
		local from = at(shooterI)
		local shot = Vector3.new(goalX + 1.2, Y + 2.2 + (scored and 1.2 or 0.6), aimZ)
		local start = Vector3.new(from.X + 0.9, Y + R, from.Y)
		if v < 0.35 then
			ballPos = F * start
		elseif v < 1.05 then
			local w = (v - 0.35) / 0.7
			local stop = scored and shot or Vector3.new(goalX - 2.2, shot.Y, aimZ)
			ballPos = F * arc(start, stop, 1.2, w)
		elseif scored then
			-- au fond du filet, puis tombe et roule
			local w = clamp01((v - 1.05) / 0.6)
			ballPos = F * Vector3.new(goalX + 2.2, max(Y + R, shot.Y - w * w * shot.Y), aimZ * (1 - 0.2 * w))
		else
			-- arrêté : le gardien le bloque, puis le relance à la main vers le joueur 1
			local hold = F * Vector3.new(goalX - 2.2, Y + 1.4, aimZ * 0.7)
			local w = clamp01((v - 2.2) / 1.2)
			local dest = at(1)
			ballPos = w > 0 and F * arc(Vector3.new(goalX - 2.4, Y + 3, aimZ * 0.5), Vector3.new(dest.X + 0.9, Y + R, dest.Y), 2.2, w) or hold
		end
		-- tireur
		for i = 1, 3 do
			local me = P[i]
			local pos = at(i)
			local yaw = yawOf(goalX - pos.X, 0 - pos.Y, 0)
			if i == shooterI and v < 0.6 then
				pose(FP, me, pos.X, pos.Y, yaw, "p11_kick", v / 0.55 * 0.7 + 0.15, dt)
			elseif v > 1.1 and v < 2.6 and scored then
				pose(FP, me, pos.X, pos.Y, yaw, "p11_shoot", 0.45, dt) -- (bras au ciel)
			else
				pose(FP, me, pos.X, pos.Y, yaw, "p11_ready", t + i, dt)
			end
		end
		-- gardien : plonge du bon côté (raté si but)
		local dive = clamp01((v - 0.45) / 0.55)
		local diveSide = scored and -saveSide or saveSide
		local kz = diveSide * 2.2 * smooth(dive)
		if dive > 0 and v < 2.4 then
			keeper.Tilt = CFrame.new(0, 0.6 * bell(dive, 0, 1), 0) * ANG(0, 0, diveSide * 1.25 * smooth(dive))
			pose(FP, keeper, goalX - 1.6, kz, math.pi / 2, "p11_dive", dive, dt)
		else
			keeper.Tilt = nil
			pose(FP, keeper, goalX - 1.6, v >= 2.4 and 0 or kz, math.pi / 2, v > 2.2 and not scored and "p11_pass" or "p11_ready", v > 2.2 and clamp01((v - 2.2) / 1.0) or t, dt)
		end
		if scored then
			local bulge = bell(clamp01((v - 0.95) / 0.8), 0, 1)
			G.Net.Size = Vector3.new(7.2, 6.4, 0.06 + bulge * 0.02)
			G.Net.Transparency = 0.6 - bulge * 0.15
		end
	end
	G.Ball.CFrame = CFrame.new(ballPos) * ANG(t * 6, 0, t * 3)
	local k = 0
	for _, c in ipairs(G.Model:GetChildren()) do
		if c.Name == "BallPatch" and c:IsA("BasePart") then
			local a = k / 3 * TAU + t * 6
			c.CFrame = CFrame.new(ballPos) * ANG(a, a * 0.5, 0) * CFrame.new(0, 0.3, 0)
			k += 1
		end
	end
	G.BallAt = ballPos
end

----------------------------------------------------------------------
-- 🏓 PING-PONG
----------------------------------------------------------------------

local PP_T = 0.62

function ParkSports.PingPong(m: Instance, F: CFrame, seed: number, opts: any?): any
	ensureAnims()
	local o = opts or {}
	local TL, TW = 8.4, 4.7 -- table (X : longueur)
	local TY = ParkKit.TABLE
	local blue = o.Color or pick({ rgb(36, 92, 160), rgb(40, 120, 80), rgb(40, 60, 120) }, seed, 2)
	-- table d'extérieur en béton / acier : plateau, bord blanc, pieds, filet acier
	Box(m, "PPTop", F, -TL / 2, TL / 2, TY - 0.25, TY, -TW / 2, TW / 2, blue, M.SmoothPlastic, true)
	line(m, F, -TL / 2, TL / 2, -TW / 2, -TW / 2 + 0.12, TY)
	line(m, F, -TL / 2, TL / 2, TW / 2 - 0.12, TW / 2, TY)
	line(m, F, -TL / 2, -TL / 2 + 0.12, -TW / 2 + 0.12, TW / 2 - 0.12, TY)
	line(m, F, TL / 2 - 0.12, TL / 2, -TW / 2 + 0.12, TW / 2 - 0.12, TY)
	line(m, F, -TL / 2 + 0.12, TL / 2 - 0.12, -0.03, 0.03, TY)
	for _, sx in ipairs({ -1, 1 }) do
		Box(m, "PPLeg", F, sx * 2.6 - 0.3, sx * 2.6 + 0.3, 0, TY - 0.25, -TW / 2 + 0.5, TW / 2 - 0.5, rgb(150, 150, 156), M.Concrete, true)
	end
	Box(m, "PPNet", F, -0.05, 0.05, TY, TY + 0.55, -TW / 2 - 0.2, TW / 2 + 0.2, rgb(160, 164, 170), M.DiamondPlate)
	Box(m, "PPNetTop", F, -0.07, 0.07, TY + 0.55, TY + 0.62, -TW / 2 - 0.2, TW / 2 + 0.2, rgb(110, 114, 120), M.Metal)
	Box(m, "PPPad", F, -TL / 2 - 4, TL / 2 + 4, -0.1, 0.08, -TW / 2 - 2.5, TW / 2 + 2.5, rgb(170, 168, 160), M.Concrete, true)
	local Y = 0.08
	local FP = F * CFrame.new(0, Y, 0)
	local players = {
		newPlayer(m, FP, pick({ "kid", "jogger", "pedestrian" }, seed, 1), seed * 3 + 1, -TL / 2 - 1.6, 0, -math.pi / 2),
		newPlayer(m, FP, pick({ "pedestrian", "kid", "elder" }, seed, 2), seed * 3 + 2, TL / 2 + 1.6, 0, math.pi / 2),
	}
	for i, p in ipairs(players) do
		giveRacket(m, p, i == 1 and rgb(200, 40, 40) or rgb(30, 30, 34), 0.45, 0.85, false)
	end
	local ball = Part(m, "PPBall", Vector3.new(0.2, 0.2, 0.2), F, rgb(255, 250, 240), M.SmoothPlastic, "Ball")
	ball.CastShadow = false
	local game = { Kind = "PingPong", F = F, FP = FP, Players = players, Ball = ball, TL = TL, TY = TY, Y = Y, Seed = seed, Model = m }
	register(m, F, function(t: number, dt: number)
		ParkSports.Step(game, t, dt)
	end, seed)
	return game
end

local function stepPingPong(G: any, t: number, dt: number)
	local F, TL, TY, Y = G.F, G.TL, G.TY, G.Y
	local shots = 9
	local period = shots * PP_T + 1.4
	local cyc = math.floor(t / period)
	local u = t - cyc * period
	local seed = G.Seed + cyc * 7
	local hx = TL / 2 + 0.7
	local function hitZ(k: number): number
		return (hash(seed, k) * 2 - 1) * 1.5
	end
	local ballPos: Vector3
	local k = math.floor(u / PP_T)
	if k < shots then
		local v = (u - k * PP_T) / PP_T
		local who = k % 2 == 0 and -1 or 1
		local from = Vector3.new(who * hx, TY + 0.9, hitZ(k))
		local to = Vector3.new(-who * hx, TY + 0.9, hitZ(k + 1))
		local bounce = Vector3.new(-who * TL * 0.25, TY + 0.1, from.Z + (to.Z - from.Z) * 0.6)
		if v < 0.55 then
			ballPos = F * arc(from, bounce, 0.5, v / 0.55)
		else
			ballPos = F * arc(bounce, to, 0.55, (v - 0.55) / 0.45)
		end
	else
		-- point perdu : la balle tombe derrière la table et rebondit
		local v = clamp01((u - shots * PP_T) / 1.4)
		local who = shots % 2 == 0 and -1 or 1
		local from = Vector3.new(who * hx, TY + 0.9, hitZ(shots))
		ballPos = F * Vector3.new(from.X + who * v * 3, Y + 0.1 + abs(sin(v * math.pi * 3)) * (TY + 0.8) * (1 - v), from.Z)
	end
	G.Ball.CFrame = CFrame.new(ballPos)
	G.BallAt = ballPos
	for side, p in ipairs(G.Players) do
		local who = side == 1 and -1 or 1
		local face = side == 1 and -math.pi / 2 or math.pi / 2
		-- frappes de ce joueur : k pair (côté -1) ou impair
		local best, bestDt = nil, math.huge
		for kk = 0, shots - 1 do
			if (kk % 2 == 0) == (side == 1) then
				local d = u - kk * PP_T
				if abs(d) < abs(bestDt) then
					best, bestDt = kk, d
				end
			end
		end
		local z = p.Z
		local anim, at = "p11_ready", t
		if best then
			local target = hitZ(best) + 0.7 * -who
			z += (target - z) * min(1, dt * 8)
			if abs(bestDt) < 0.25 then
				anim, at = "p11_paddle", 0.5 + bestDt / 0.5
			end
		end
		pose(G.FP, p, who * (TL / 2 + 1.6), z, face, anim, at, dt)
	end
end

----------------------------------------------------------------------

function ParkSports.Step(G: any, t: number, dt: number?)
	local d = dt or 1 / 30
	if not G or not G.Model or not G.Model.Parent then
		return
	end
	if G.Kind == "Basketball" then
		stepBasket(G, t, d)
	elseif G.Kind == "Tennis" then
		stepTennis(G, t, d)
	elseif G.Kind == "Football" then
		stepFootball(G, t, d)
	elseif G.Kind == "PingPong" then
		stepPingPong(G, t, d)
	end
end

function ParkSports.Debug(G: any): any
	local players = {}
	for _, p in ipairs(G.Players or {}) do
		table.insert(players, { X = p.X, Z = p.Z, Y = p.Y, Yaw = p.Yaw })
	end
	return { Kind = G.Kind, Ball = G.BallAt, Players = players, Custom = ParkKit.HasCustomAnims() }
end

return ParkSports
