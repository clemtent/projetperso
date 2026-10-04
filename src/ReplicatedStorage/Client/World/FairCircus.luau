--[[
	FairCircus (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FairCircus

	🎪 LE GRAND CIRQUE de la fête, côté client.
	v11 (PARK11) — "20x mieux et plus grand" (échelle SCALE11 : chapiteau
	de rayon 30 au lieu de 18, piste de 9, gradins de 5 rangs aux assises à
	1,85 au-dessus de leur marchepied) :
	  - DEHORS : grand chapiteau à 32 pans rayés rouge / crème, murs de 11,
	    lambrequin festonné à frange dorée, toit en cône avec coutures, deux
	    mâts royaux, coupole et drapeau, haubans et piquets tendus de
	    guirlandes d'ampoules ; GRAND PORCHE d'entrée (auvent à pignon sur
	    colonnes dorées, fronton "Grand Cirque Dopamine" bordé d'ampoules,
	    rideaux de velours drapés), billetterie ouvragée avec sa caissière et
	    des clients qui font la queue, panneau d'affiches, roulotte de cirque ;
	  - DEDANS : sol de sciure, PISTE de 9 (bordure rembourrée rouge et
	    blanche, tapis à étoile dorée), barrière de velours, gradins sur 5
	    rangs (marchepieds, planches, garde-corps), allée où passe un vendeur
	    de pop-corn, portique des coulisses (rideaux, arche dorée) surmonté du
	    BALCON DE L'ORCHESTRE (trompettes, tambour), mâts royaux à bandes,
	    gréement : treillis, 2 trapèzes, échelles de corde, plates-formes,
	    filet de sécurité, fil de funambule ; couronne de projecteurs (2 vraies
	    lumières douces, faisceaux qui SUIVENT le numéro en cours) ;
	  - LE SPECTACLE (96 s, même heure pour tout le monde) : Monsieur Loyal
	    (chapeau haut-de-forme) présente ; JONGLEUR (cascade de 3 balles) et
	    MONOCYCLISTE ; VOITURE DE CLOWNS (tours de piste, arrêt, les clowns
	    jaillissent) ; CHIENS SAVANTS qui sautent dans le cerceau ; TRAPÈZE
	    VOLANT (pendules physiques, le voltigeur lâche sa barre, vole et est
	    rattrapé par le porteur, puis tombe dans le filet qui rebondit) ;
	    FUNAMBULE avec son balancier ; FINAL (tous saluent, confettis) ;
	    public qui applaudit et se lève aux grands moments.
	Les artistes sont des PNJ (NPCModels) animés avec des anims "maison"
	(ParkKit / NPCModels.AddAnim) quand la caméra est à moins de SHOW_R.
	Aucune pièce serveur ici (sauf les 40 sièges, TownFair), aucun son.

	API (FairFx) :
	  FairCircus.Build(r: RideFx, npcFolder)   r.Extra.Step(t) anime tout
	  FairCircus.SHOW_R
	  FairCircus.Debug(r) -> table   (tests : numéro en cours, positions)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FairRides = require(ReplicatedStorage.Shared.FairRides)
local Locale = require(ReplicatedStorage.Shared.Locale)
local FairKit = require(script.Parent.FairKit)
local ParkKit = require(script.Parent.ParkKit)

local FairCircus = {}

local M = FairKit.M
local C = FairKit.C
local VERTICAL = FairKit.VERTICAL
local BALL, CYL = FairKit.BALL, FairKit.CYL
local TAU = FairKit.TAU
local Part, Solid, Glow = FairKit.Part, FairKit.Solid, FairKit.Glow
local Fixed = FairKit.Fixed
local ANG = CFrame.Angles
local sin, cos, abs, max = math.sin, math.cos, math.abs, math.max

type RideFx = FairKit.RideFx

local SHOW_R = 120 -- (studs) la caméra doit être plus près pour animer le spectacle
local LIGHT_R = 70 -- ... pour allumer les 2 projecteurs

local RED = Color3.fromRGB(198, 34, 48)
local RED_D = Color3.fromRGB(150, 22, 36)
local CANVAS = Color3.fromRGB(250, 242, 224)
local VELVET = Color3.fromRGB(132, 20, 38)
local GOLD = Color3.fromRGB(226, 176, 70)
local SAWDUST = Color3.fromRGB(222, 196, 150)
local BENCH_BLUE = Color3.fromRGB(40, 64, 132)
local PLANK = Color3.fromRGB(186, 138, 92)
local ROPE_C = Color3.fromRGB(232, 222, 196)

-- Géométrie (repère du chapiteau : y = 0 au sol, -Z = entrée du public)
local R = FairRides.CIRCUS_R
local WALL_H = 11
local FLOOR = FairRides.CIRCUS_FLOOR or 0.14
local RING = FairRides.CIRCUS_RING
local APEX = 33
-- 4 mâts autour de la piste (entre la bordure et la barrière, hors du plan
-- des trapèzes z = 0) : treillis du gréement à y 22 entre eux
local POLE_X, POLE_Z, POLE_TOP = 9.8, 6.0, 25.4
local RIG_Y = 22
local TRAP_L = 6
local BAR_A, BAR_B = -4.2, 4.11 -- x des pivots des trapèzes (voltigeur / porteur)
local TRAP_AMP = math.rad(32) -- amplitude du voltigeur
local CATCH_AMP = math.rad(20) -- amplitude du porteur (même fréquence, en opposition)
local TRAP_W = math.sqrt(30 / TRAP_L) -- (rad/s) pendule : g ≈ 30 studs/s²
local REACH = 6.0 -- (pieds -> mains, bras tendus au-dessus de la tête)
local KNEE_REACH = 4.6 -- (genoux -> mains, porteur pendu par les genoux)
local NET_Y = 3.0
local PLATFORM_X, PLATFORM_Y = -10.4, 11.6 -- dessus de la plate-forme du voltigeur
local WIRE_Y, WIRE_Z, WIRE_X = 12, -5, 9.6
local BACKSTAGE = Vector3.new(0, FLOOR, 22)
local SHOW_T = FairRides.CIRCUS_SHOW

local function polar(a: number, r: number, y: number): Vector3
	return Vector3.new(sin(a) * r, y, cos(a) * r)
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function bell(u: number, a: number, b: number): number
	if u <= a or u >= b then
		return 0
	end
	return sin((u - a) / (b - a) * math.pi)
end

-- triangle plein dans le repère du chapiteau
local function tri(r: RideFx, name: string, a: Vector3, b: Vector3, c: Vector3, t: number, color: Color3, material: Enum.Material?): { BasePart }
	return ParkKit.Triangle(r.Model, name, r.Base * a, r.Base * b, r.Base * c, t, color, material or M.Fabric)
end

local function rod(r: RideFx, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?): BasePart
	return FairKit.Rod(r.Model, name, r.Base * a, r.Base * b, d, color, material)
end

----------------------------------------------------------------------
-- Anims "maison" des artistes (NPCModels.AddAnim via ParkKit)
----------------------------------------------------------------------

local ANIMS = {}
-- Monsieur Loyal : bras droit qui présente la piste en un grand geste
ANIMS.c11_present = {
	Fallback = "talk",
	Fn = function(P: any, t: number, _seed: number)
		local s = (sin(t * 0.9) + 1) / 2
		P.RHand, P.LHand = "flat", "relax"
		P.RUp = ANG(0.9 + s * 0.5, 0, 0.9 + s * 0.6)
		P.RLo = 0.25
		P.RWrist = ANG(0, -math.pi / 2, 0)
		P.LUp = ANG(0.35, 0, -0.15)
		P.LLo = 1.6
		P.Lean = -0.06
		P.HeadPitch = -0.12
		P.HeadYaw = (s - 0.5) * 0.6
		P.LookW = 0
	end,
}
-- salut (t = phase 0..1)
ANIMS.c11_bow = {
	Fallback = "wave",
	Fn = function(P: any, t: number, _seed: number)
		local u = math.clamp(t, 0, 1)
		local b = bell(u, 0.05, 0.95)
		P.Lean = 0.85 * b
		P.HeadPitch = 0.3 * b
		P.RUp = ANG(0.5 + 0.6 * b, 0, 0.9 - 0.6 * b)
		P.RLo = 0.9 * b + 0.2
		P.LUp = ANG(-0.2 * b, 0, -0.25)
		P.LLo = 0.3
		P.RHand, P.LHand = "flat", "relax"
		P.LookW = 0
	end,
}
-- jongleur : mains qui montent et descendent en alternance (t = temps)
ANIMS.c11_juggle = {
	Fallback = "talk",
	Fn = function(P: any, t: number, _seed: number)
		local w = t * TAU * 1.6
		P.RHand, P.LHand = "cup", "cup"
		P.RUp = ANG(0.55 + 0.18 * sin(w), 0, 0.22)
		P.LUp = ANG(0.55 + 0.18 * sin(w + math.pi), 0, -0.22)
		P.RLo = 1.25 - 0.25 * sin(w)
		P.LLo = 1.25 - 0.25 * sin(w + math.pi)
		P.HeadPitch = -0.45
		P.LookW = 0
	end,
}
-- trapèze / suspension : bras tendus au-dessus de la tête (voltigeur)
ANIMS.c11_hang = {
	Fallback = "cheer",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "grip"
		P.LUp = ANG(0.15, 0, -2.85)
		P.RUp = ANG(0.15, 0, 2.85)
		P.LLo, P.RLo = 0.1, 0.1
		local k = sin(t * 2.2) * 0.2
		P.LTh, P.RTh = 0.3 + k, 0.3 + k
		P.LKnee, P.RKnee = 0.25, 0.25
		P.LFoot, P.RFoot = -0.6, -0.6
		P.HeadPitch = -0.2
		P.LookW = 0
	end,
}
-- porteur pendu par les genoux (le corps est retourné par le placement) :
-- genoux crochetés à 90°, bras tendus vers le bas (au-dessus de la tête)
ANIMS.c11_catch = {
	Fallback = "cheer",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "grip"
		P.LUp = ANG(0.1, 0, -2.9)
		P.RUp = ANG(0.1, 0, 2.9)
		P.LLo, P.RLo = 0.1, 0.1
		P.LTh, P.RTh = 0.15, 0.15
		P.LKnee, P.RKnee = 1.55, 1.55
		P.LFoot, P.RFoot = 0.3, 0.3
		P.Lean = -0.1
		P.HeadPitch = -0.35
		P.LookW = 0
	end,
}
-- monter à l'échelle de corde (t = temps : mains et pieds alternés)
ANIMS.c11_climb = {
	Fallback = "walk",
	Fn = function(P: any, t: number, _seed: number)
		local w = t * TAU * 1.1
		P.RHand, P.LHand = "grip", "grip"
		P.RUp = ANG(2.4 + 0.35 * sin(w), 0, 0.2)
		P.LUp = ANG(2.4 + 0.35 * sin(w + math.pi), 0, -0.2)
		P.RLo = 0.6 + 0.4 * max(0, -sin(w))
		P.LLo = 0.6 + 0.4 * max(0, sin(w))
		P.LTh = 0.6 + 0.5 * max(0, sin(w + math.pi))
		P.RTh = 0.6 + 0.5 * max(0, sin(w))
		P.LKnee = 1.0 + 0.6 * max(0, sin(w + math.pi))
		P.RKnee = 1.0 + 0.6 * max(0, sin(w))
		P.Lean = 0.15
		P.HeadPitch = -0.3
		P.LookW = 0
	end,
}
-- funambule : bras écartés tenant le balancier, petits pas prudents
ANIMS.c11_wire = {
	Fallback = "walk",
	Fn = function(P: any, t: number, _seed: number)
		local w = t * TAU * 0.6
		P.RHand, P.LHand = "grip", "grip"
		P.LUp = ANG(0.55, 0, -0.55 + sin(t * 1.3) * 0.08)
		P.RUp = ANG(0.55, 0, 0.55 + sin(t * 1.3) * 0.08)
		P.LLo, P.RLo = 0.9, 0.9
		P.LTh = sin(w) * 0.22
		P.RTh = sin(w + math.pi) * 0.22
		P.LKnee = max(0, cos(w)) * 0.5 + 0.1
		P.RKnee = max(0, cos(w + math.pi)) * 0.5 + 0.1
		P.LFoot, P.RFoot = 0.1, 0.1
		P.Side = sin(t * 1.3) * 0.08
		P.HeadPitch = 0.2
		P.LookW = 0
	end,
}
-- dresseur : cerceau tenu bras droit tendu sur le côté
ANIMS.c11_hoop = {
	Fallback = "wave",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "flat"
		P.RUp = ANG(0.25, 0, 1.45)
		P.RLo = 0.1
		P.LUp = ANG(0.7 + sin(t * 2) * 0.2, 0, -0.3)
		P.LLo = 0.5
		P.HeadYaw = -0.5
		P.LookW = 0
	end,
}
-- monocycle : pédalage (cercles), bras écartés pour l'équilibre
ANIMS.c11_ride = {
	Fallback = "walk",
	Fn = function(P: any, t: number, _seed: number)
		local w = t * TAU * 1.0
		P.LUp = ANG(0.2, 0, -1.25 + sin(t * 2.3) * 0.15)
		P.RUp = ANG(0.2, 0, 1.25 - sin(t * 2.3) * 0.15)
		P.LLo, P.RLo = 0.2, 0.2
		P.RHand, P.LHand = "flat", "flat"
		P.LTh = 0.75 + 0.35 * sin(w)
		P.RTh = 0.75 + 0.35 * sin(w + math.pi)
		P.LKnee = 1.0 + 0.45 * cos(w)
		P.RKnee = 1.0 + 0.45 * cos(w + math.pi)
		P.Side = sin(t * 2.3) * 0.06
		P.LookW = 0
	end,
}

local animsReady = false
local function ensureAnims()
	if animsReady then
		return
	end
	animsReady = true
	ParkKit.RegisterAnims(ANIMS)
	-- (orchestre : trompette / tambour, applaudir... : ParkScenes)
	local okS, ParkScenes = pcall(require, script.Parent:FindFirstChild("ParkScenes") :: any)
	if okS and type(ParkScenes) == "table" and ParkScenes.EnsureAnims then
		pcall(ParkScenes.EnsureAnims)
	end
end

----------------------------------------------------------------------
-- Chapiteau
----------------------------------------------------------------------

local N_PANELS = 32
local ENTRY_HALF = math.rad(12.5) -- (demi-ouverture de l'entrée)

local function isEntry(a: number): boolean
	local d = abs(((a - math.pi) + math.pi) % TAU - math.pi)
	return d < ENTRY_HALF
end

local function buildTent(r: RideFx): CFrame
	local N = N_PANELS
	local chord = 2 * R * sin(math.pi / N) + 0.08
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * TAU
		local stripe = if i % 2 == 0 then RED else CANVAS
		if not isEntry(a) then
			local p = polar(a, R, WALL_H / 2)
			local wall = Solid(Fixed(r, "Canvas", Vector3.new(chord, WALL_H, 0.25), CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z)), stripe, M.Fabric))
			wall.CastShadow = true
			Fixed(r, "Hem", Vector3.new(chord + 0.06, 0.5, 0.34), CFrame.lookAt(polar(a, R, 0.29), polar(a, R + 1, 0.29)), RED_D, M.Fabric)
			-- couture verticale entre deux lés
			local seam = polar(a + math.pi / N, R + 0.14, WALL_H / 2)
			Fixed(r, "Seam", Vector3.new(0.12, WALL_H, 0.06), CFrame.lookAt(seam, seam + Vector3.new(seam.X, 0, seam.Z)), CANVAS:Lerp(RED, 0.5), M.Fabric)
		end
		-- lambrequin festonné (2 demi-triangles) + gland doré
		local e = polar(a, R + 0.4, WALL_H + 0.25)
		local half = (R + 0.4) * sin(math.pi / N)
		local size, cf = FairKit.Tri(e, -FairKit.UP, Vector3.new(cos(a), 0, -sin(a)), 1.4, half, 0.1)
		Part(r.Model, "Valance", size, r.Base * cf, if i % 2 == 0 then CANVAS else RED, M.Fabric, nil, "WedgePart")
		local size2, cf2 = FairKit.Tri(e, -FairKit.UP, -Vector3.new(cos(a), 0, -sin(a)), 1.4, half, 0.1)
		Part(r.Model, "Valance", size2, r.Base * cf2, if i % 2 == 0 then CANVAS else RED, M.Fabric, nil, "WedgePart")
		Fixed(r, "Tassel", Vector3.new(0.3, 0.5, 0.3), CFrame.new(polar(a, R + 0.42, WALL_H - 1.35)), GOLD, M.Fabric, BALL)
	end
	-- bourrelet doré à l'égout
	for i = 0, N - 1 do
		local a0, a1 = i / N * TAU, (i + 1) / N * TAU
		rod(r, "Eave", polar(a0, R + 0.45, WALL_H + 0.45), polar(a1, R + 0.45, WALL_H + 0.45), 0.34, GOLD, M.Metal)
	end
	-- toit en cône : 32 pans rayés jusqu'à la coupole, coutures en corde
	local eaveR, eaveY = R + 0.45, WALL_H + 0.5
	local top = Vector3.new(0, APEX, 0)
	for k = 0, N - 1 do
		local a0, a1 = k / N * TAU, (k + 1) / N * TAU
		local p0, p1 = polar(a0, eaveR, eaveY), polar(a1, eaveR, eaveY)
		for _, w in ipairs(tri(r, "Roof", p0, p1, top, 0.22, if k % 2 == 0 then RED else CANVAS)) do
			w.CastShadow = true
		end
		rod(r, "RoofSeam", p0 + Vector3.new(0, 0.18, 0), top + Vector3.new(0, 0.18, 0), 0.12, ROPE_C, M.Fabric)
	end
	-- coupole (tambour, petit toit, épi) + drapeau
	Fixed(r, "Cupola", Vector3.new(2.2, 5.4, 5.4), CFrame.new(0, APEX - 0.4, 0) * VERTICAL, RED, M.Fabric, CYL)
	Fixed(r, "CupolaRim", Vector3.new(0.4, 5.8, 5.8), CFrame.new(0, APEX + 0.75, 0) * VERTICAL, GOLD, M.Metal, CYL)
	Fixed(r, "CupolaCap", Vector3.new(4.8, 2.2, 4.8), CFrame.new(0, APEX + 1.5, 0), CANVAS, M.Fabric, BALL)
	Fixed(r, "FlagPole", Vector3.new(6, 0.25, 0.25), CFrame.new(0, APEX + 5, 0) * VERTICAL, GOLD, M.Metal, CYL)
	Fixed(r, "FlagBall", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, APEX + 8.1, 0), GOLD, M.Metal, BALL)
	local fs, fl = FairKit.Tri(r.Base * Vector3.new(0, APEX + 7.6, 0), r.Base:VectorToWorldSpace(Vector3.new(1, 0, 0)), -FairKit.UP, 3.6, 1.8, 0.06)
	Part(r.Model, "Pennant", fs, fl, RED, M.Fabric, nil, "WedgePart")
	-- haubans, piquets, guirlandes d'ampoules (sauf devant l'entrée)
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * TAU
		if abs(((a - math.pi) + math.pi) % TAU - math.pi) > math.rad(28) then
			local from = polar(a, R + 0.3, WALL_H + 0.3)
			local to = polar(a, R + 4.5, 0.4)
			rod(r, "Guy", from, to, 0.08, ROPE_C, M.Fabric)
			Fixed(r, "Stake", Vector3.new(0.35, 1.0, 0.35), CFrame.new(polar(a, R + 4.55, 0.4)) * ANG(0, 0, math.rad(12)), C.WoodDark, M.Wood)
			if i % 2 == 0 then
				FairKit.Bulbs(r.Model, r.Base * from:Lerp(to, 0.1), r.Base * from:Lerp(to, 0.85), 6, 0.3, { C.Bulb, Color3.fromRGB(255, 180, 120), Color3.fromRGB(255, 120, 160) })
			end
		end
	end
	-- GRAND PORCHE : 2 rangées de colonnes dorées, auvent à pignon rayé,
	-- fronton à ampoules, rideaux drapés
	local pz0, pz1 = -R - 0.2, -R - 8.5
	local pw = 7
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ pz0 - 0.6, (pz0 + pz1) / 2, pz1 }) do
			Solid(Fixed(r, "PorchColumn", Vector3.new(8.3, 0.6, 0.6), CFrame.new(sx * pw, 4.75, z) * VERTICAL, GOLD, M.Metal, CYL))
			Fixed(r, "PorchBase", Vector3.new(0.6, 1.1, 1.1), CFrame.new(sx * pw, 0.3, z) * VERTICAL, RED_D, M.Metal, CYL)
			Fixed(r, "PorchCap", Vector3.new(0.4, 1.0, 1.0), CFrame.new(sx * pw, 8.7, z) * VERTICAL, GOLD, M.Metal, CYL)
		end
		-- pan d'auvent incliné (rayures)
		for k = 0, 5 do
			local z0 = pz0 + (pz1 - pz0) * k / 6
			local z1 = pz0 + (pz1 - pz0) * (k + 1) / 6
			local a = Vector3.new(sx * (pw + 0.6), 8.9, (z0 + z1) / 2)
			local b = Vector3.new(0, 11.6, (z0 + z1) / 2)
			local len = (b - a).Magnitude
			Fixed(r, "PorchRoof", Vector3.new(len + 0.2, 0.2, abs(z1 - z0) + 0.02), CFrame.lookAt((a + b) / 2, b) * ANG(0, math.rad(90), 0) * CFrame.new(0, (k % 2) * 0.04, 0), if k % 2 == 0 then RED else CANVAS, M.Fabric).CastShadow = true
		end
		-- rideaux de velours relevés
		Fixed(r, "Drape", Vector3.new(1.8, 8.2, 0.35), CFrame.new(sx * 5.4, 4.6, pz0 - 0.3) * ANG(0, 0, math.rad(sx * -7)), VELVET, M.Fabric)
		Fixed(r, "TieBack", Vector3.new(0.45, 0.45, 0.6), CFrame.new(sx * 5.0, 3.6, pz0 - 0.55), GOLD, M.Metal, BALL)
		Solid(Fixed(r, "Jamb", Vector3.new(0.6, WALL_H, 0.6), CFrame.new(sx * 6.6, WALL_H / 2, -R + 0.2), GOLD, M.Metal))
	end
	-- fronton (triangle) + enseigne bordée d'ampoules
	tri(r, "Pediment", Vector3.new(-pw - 0.6, 8.9, pz1 - 0.35), Vector3.new(pw + 0.6, 8.9, pz1 - 0.35), Vector3.new(0, 11.7, pz1 - 0.35), 0.3, RED_D, M.SmoothPlastic)
	local board = Fixed(r, "Board", Vector3.new(15, 3.2, 0.35), CFrame.new(0, 10.6, pz1 - 0.6), RED_D, M.SmoothPlastic)
	FairKit.Sign(board, "🎪 " .. Locale.T("Grand Dopamine Circus"), Color3.fromRGB(255, 226, 120), RED_D, Enum.Font.Fondamento)
	FairKit.Bulbs(r.Model, r.Base * Vector3.new(-7.4, 12.35, pz1 - 0.8), r.Base * Vector3.new(7.4, 12.35, pz1 - 0.8), 18, 0.3, { C.Bulb, Color3.fromRGB(255, 190, 120) })
	FairKit.Bulbs(r.Model, r.Base * Vector3.new(-7.4, 8.85, pz1 - 0.8), r.Base * Vector3.new(7.4, 8.85, pz1 - 0.8), 18, 0.3, { C.Bulb })
	-- tapis rouge du porche
	local carpet = Fixed(r, "Carpet", Vector3.new(6, 0.06, abs(pz1 - pz0) + 4), CFrame.new(0, 0.05, (pz0 + pz1) / 2 + 1.5), VELVET, M.Fabric)
	carpet.CastShadow = false
	-- billetterie (cabine rayée à dôme, vitre, comptoir, enseigne)
	local booth = CFrame.new(11.5, 0, -R - 6.5) * ANG(0, math.rad(-25), 0)
	Solid(Fixed(r, "Booth", Vector3.new(4.2, 5.4, 3.4), booth * CFrame.new(0, 2.7, 0.5), CANVAS, M.WoodPlanks))
	for i = 0, 4 do
		Fixed(r, "BoothStripe", Vector3.new(0.4, 5.34, 3.46), booth * CFrame.new(-1.68 + i * 0.84, 2.7, 0.5), RED, M.WoodPlanks)
	end
	local glass = Fixed(r, "BoothGlass", Vector3.new(3, 1.7, 0.08), booth * CFrame.new(0, 3.5, -1.24), Color3.fromRGB(180, 210, 230), M.Glass)
	glass.Transparency = 0.45
	Fixed(r, "BoothCounter", Vector3.new(3.4, 0.25, 0.8), booth * CFrame.new(0, 2.6, -1.55), GOLD, M.Metal)
	Fixed(r, "BoothDome", Vector3.new(4.8, 2.4, 4.0), booth * CFrame.new(0, 5.6, 0.5), RED, M.SmoothPlastic, BALL)
	Fixed(r, "BoothFinial", Vector3.new(0.5, 0.5, 0.5), booth * CFrame.new(0, 6.9, 0.5), GOLD, M.Metal, BALL)
	local tag = Fixed(r, "BoothSign", Vector3.new(3.4, 0.9, 0.12), booth * CFrame.new(0, 4.75, -1.25), CANVAS, M.SmoothPlastic)
	FairKit.Sign(tag, "🎟️ " .. Locale.T("Box office"), RED, CANVAS)
	-- panneau d'affiches (chevalet double)
	local poster = CFrame.new(-11.5, 0, -R - 7) * ANG(0, math.rad(25), 0)
	for _, sz in ipairs({ -1, 1 }) do
		local face = Fixed(r, "PosterBoard", Vector3.new(4, 5.4, 0.2), poster * CFrame.new(0, 3.2, sz * 0.7) * ANG(math.rad(sz * 9), 0, 0), Color3.fromRGB(250, 236, 200), M.SmoothPlastic)
		FairKit.Sign(face, if sz < 0 then "🤹 🐩 🤸\n" .. Locale.T("Show") else "🎪 " .. Locale.T("Tonight"), RED_D, Color3.fromRGB(250, 236, 200), Enum.Font.Fondamento, if sz < 0 then Enum.NormalId.Front else Enum.NormalId.Back)
	end
	-- roulotte de cirque (caisse rouge à moulures dorées, roues à rayons, toit arrondi)
	local wag = CFrame.new(-R - 3, 0, -10) * ANG(0, math.rad(80), 0)
	Solid(Fixed(r, "Wagon", Vector3.new(4.6, 4.6, 9), wag * CFrame.new(0, 3.3, 0), RED, M.WoodPlanks))
	Fixed(r, "WagonRoof", Vector3.new(9.4, 1.6, 5.0), wag * CFrame.new(0, 5.6, 0) * ANG(0, math.rad(90), 0), CANVAS, M.Wood, CYL)
	for _, sx in ipairs({ -1, 1 }) do
		Fixed(r, "WagonTrim", Vector3.new(0.1, 3.4, 8), wag * CFrame.new(sx * 2.33, 3.3, 0), GOLD, M.Metal)
		for _, z in ipairs({ -3, 3 }) do
			Fixed(r, "WagonWheel", Vector3.new(0.3, 2.2, 2.2), wag * CFrame.new(sx * 2.45, 1.1, z) * ANG(0, 0, 0), GOLD, M.Wood, CYL)
			Fixed(r, "WagonHub", Vector3.new(0.45, 0.6, 0.6), wag * CFrame.new(sx * 2.55, 1.1, z), RED_D, M.Wood, CYL)
		end
	end
	return booth
end

----------------------------------------------------------------------
-- Intérieur
----------------------------------------------------------------------

local function seatRadius(tier: number): number
	return FairRides.CIRCUS_TIER_R0 + tier * FairRides.CIRCUS_TIER_DR
end
local function seatTop(tier: number): number
	return FairRides.CIRCUS_SEAT_Y0 + tier * FairRides.CIRCUS_TIER_DY
end

local function buildInside(r: RideFx): any
	-- (dessous à -0,03 : aucune face confondue avec les pieds des gradins, posés à 0)
	Solid(Fixed(r, "Sawdust", Vector3.new(FLOOR + 0.03, 2 * R - 0.6, 2 * R - 0.6), CFrame.new(0, (FLOOR - 0.03) / 2, 0) * VERTICAL, SAWDUST, M.Sand, CYL))
	-- PISTE : tapis rouge + étoile dorée + bordure rembourrée (32 segments)
	Fixed(r, "RingMat", Vector3.new(0.06, 2 * RING - 0.8, 2 * RING - 0.8), CFrame.new(0, FLOOR + 0.03, 0) * VERTICAL, Color3.fromRGB(176, 36, 48), M.Fabric, CYL)
	Fixed(r, "RingMatEdge", Vector3.new(0.05, 2 * RING - 2.2, 2 * RING - 2.2), CFrame.new(0, FLOOR + 0.07, 0) * VERTICAL, Color3.fromRGB(196, 46, 58), M.Fabric, CYL)
	for k = 0, 4 do
		local a0 = k / 5 * TAU
		local tip = polar(a0, 4.6, FLOOR + 0.11)
		local l = polar(a0 - math.pi / 5, 1.75, FLOOR + 0.11)
		local rr = polar(a0 + math.pi / 5, 1.75, FLOOR + 0.11)
		tri(r, "RingStar", l, rr, tip, 0.04, GOLD, M.Fabric)
	end
	Fixed(r, "RingStarCore", Vector3.new(0.04, 3.6, 3.6), CFrame.new(0, FLOOR + 0.11, 0) * VERTICAL, GOLD, M.Fabric, CYL)
	for i = 0, 31 do
		local a = (i + 0.5) / 32 * TAU
		local p = polar(a, RING, FLOOR + 0.5)
		local chord = 2 * RING * sin(math.pi / 32) + 0.04
		Solid(Fixed(r, "Curb", Vector3.new(chord, 1.0, 0.8), CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z)), if i % 2 == 0 then RED else C.White, M.SmoothPlastic))
		Fixed(r, "CurbPad", Vector3.new(chord, 0.18, 0.95), CFrame.lookAt(p + Vector3.new(0, 0.58, 0), p + Vector3.new(p.X, 0.58, p.Z)), GOLD, M.Fabric)
	end
	-- barrière de velours devant le 1er rang (r 12,2)
	local rb = FairRides.CIRCUS_TIER_R0 - 1.9 - 0.3
	for _, arc in ipairs(FairRides.CIRCUS_ARCS) do
		local a0, a1 = math.rad(arc[1] - 3), math.rad(arc[2] + 3)
		local n = 14
		for i = 0, n - 1 do
			local u0, u1 = a0 + (a1 - a0) * i / n, a0 + (a1 - a0) * (i + 1) / n
			local pa, pb = polar(u0, rb, FLOOR), polar(u1, rb, FLOOR)
			local mid = (pa + pb) / 2
			Solid(Fixed(r, "Barrier", Vector3.new((pb - pa).Magnitude + 0.04, 1.3, 0.3), CFrame.lookAt(mid + Vector3.new(0, 0.65, 0), mid + Vector3.new(mid.X, 0.65, mid.Z)), RED_D, M.Wood))
			Fixed(r, "BarrierTop", Vector3.new((pb - pa).Magnitude + 0.06, 0.2, 0.42), CFrame.lookAt(mid + Vector3.new(0, 1.4, 0), mid + Vector3.new(mid.X, 1.4, mid.Z)), VELVET, M.Fabric)
		end
	end
	-- GRADINS : rang k = marchepied (bloc plein jusqu'à F_k) + assise
	-- (contremarche bleue + planche, dessus à F_k + 1,85)
	local DR, DY = FairRides.CIRCUS_TIER_DR, FairRides.CIRCUS_TIER_DY
	for tier = 0, FairRides.CIRCUS_TIERS - 1 do
		local rs = seatRadius(tier)
		local rFoot = rs - 1.9 -- début du rang (devant les pieds)
		local footY = FLOOR + tier * DY
		local top = seatTop(tier)
		for _, arc in ipairs(FairRides.CIRCUS_ARCS) do
			local a0, a1 = math.rad(arc[1] - 3), math.rad(arc[2] + 3)
			local n = 16
			for i = 0, n - 1 do
				local a = a0 + (a1 - a0) * (i + 0.5) / n
				local look = CFrame.lookAt(polar(a, 0, 0), polar(a, 1, 0)) -- (+Z local = vers l'extérieur)
				local function block(name: string, r0: number, r1: number, y0: number, y1: number, color: Color3, mat: Enum.Material, solid: boolean)
					local mid = (r0 + r1) / 2
					local chord = 2 * r1 * sin((a1 - a0) / n / 2) + 0.06
					local p = Fixed(r, name, Vector3.new(chord, y1 - y0, r1 - r0), look * CFrame.new(0, (y0 + y1) / 2, -mid), color, mat)
					if solid then
						Solid(p)
					end
					return p
				end
				-- (la face avant du bloc regarde le centre : lookAt vers l'extérieur, z négatif = rayon)
				if tier > 0 then
					block("Step", rFoot, rFoot + DR, 0, footY, BENCH_BLUE:Lerp(C.White, 0.05 * tier), M.SmoothPlastic, true)
				end
				block("Riser", rs - 0.7, rs + 0.7, footY, top - 0.25, BENCH_BLUE:Lerp(Color3.new(0, 0, 0), 0.15), M.SmoothPlastic, true)
				block("Plank", rs - 0.75, rs + 0.75, top - 0.25, top, PLANK, M.WoodPlanks, true)
			end
		end
	end
	-- garde-corps derrière le dernier rang (≥ 3,6 au-dessus du dernier marchepied)
	local rTop = seatRadius(FairRides.CIRCUS_TIERS - 1) + 0.95
	local yTop = FLOOR + FairRides.CIRCUS_TIERS * DY
	for _, arc in ipairs(FairRides.CIRCUS_ARCS) do
		local n = 12
		for i = 0, n - 1 do
			local a0 = math.rad(arc[1] - 3 + (arc[2] - arc[1] + 6) * i / n)
			local a1 = math.rad(arc[1] - 3 + (arc[2] - arc[1] + 6) * (i + 1) / n)
			rod(r, "BackRail", polar(a0, rTop, yTop + 1.7), polar(a1, rTop, yTop + 1.7), 0.16, GOLD, M.Metal)
			Solid(Fixed(r, "RailPost", Vector3.new(0.16, 3.6, 0.16), CFrame.new(polar(a0, rTop, yTop - 0.05)), GOLD, M.Metal))
			Solid(Fixed(r, "BackWall", Vector3.new(2 * rTop * sin((a1 - a0) / 2) + 0.06, yTop - 0.05, 0.4), CFrame.lookAt(polar((a0 + a1) / 2, rTop + 0.2, (yTop - 0.05) / 2), polar((a0 + a1) / 2, rTop + 2, (yTop - 0.05) / 2)), BENCH_BLUE:Lerp(Color3.new(0, 0, 0), 0.25), M.SmoothPlastic))
		end
	end
	-- COULISSES : portique doré, rideaux de velours plissés, balcon de
	-- l'orchestre au-dessus (garde-corps)
	local bz = 24.5
	for i = -6, 6 do
		Fixed(r, "Curtain", Vector3.new(0.95, 9, 0.35), CFrame.new(i * 0.85, 4.6, bz + (i % 2) * 0.14), VELVET, M.Fabric)
	end
	Fixed(r, "Arch", Vector3.new(12.6, 0.8, 0.8), CFrame.new(0, 9.3, bz - 0.4), GOLD, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Solid(Fixed(r, "ArchPost", Vector3.new(0.8, 9.3, 0.8), CFrame.new(sx * 6.0, 4.65, bz - 0.4), GOLD, M.Metal))
		Fixed(r, "ArchStar", Vector3.new(0.2, 1.4, 1.4), CFrame.new(sx * 6.0, 10.2, bz - 0.85) * ANG(0, math.rad(90), 0), GOLD, M.Metal, CYL)
	end
	Solid(Fixed(r, "Balcony", Vector3.new(13, 0.6, 4.4), CFrame.new(0, 9.9, bz + 1.5), PLANK, M.WoodPlanks))
	Fixed(r, "BalconyFront", Vector3.new(13, 1.6, 0.25), CFrame.new(0, 11.0, bz - 0.75), RED, M.Fabric)
	FairKit.Bulbs(r.Model, r.Base * Vector3.new(-6.2, 11.9, bz - 0.95), r.Base * Vector3.new(6.2, 11.9, bz - 0.95), 12, 0.26, { C.Bulb, Color3.fromRGB(255, 190, 120) })
	-- 4 MÂTS (bandes rouges), treillis, plate-forme et échelle du voltigeur,
	-- échelle du porteur, plates-formes du funambule
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = sx * POLE_X, sz * POLE_Z
			Solid(Fixed(r, "KingPole", Vector3.new(POLE_TOP, 0.9, 0.9), CFrame.new(x, POLE_TOP / 2, z) * VERTICAL, C.White, M.Metal, CYL)).CastShadow = true
			for k = 0, 9 do
				Fixed(r, "PoleBand", Vector3.new(0.6, 0.98, 0.98), CFrame.new(x, 1.2 + k * 2.4, z) * VERTICAL, RED, M.Metal, CYL)
			end
			Fixed(r, "PoleFoot", Vector3.new(0.3, 2.2, 2.2), CFrame.new(x, FLOOR + 0.15, z) * VERTICAL, C.Steel, M.Metal, CYL)
			Fixed(r, "PoleTop", Vector3.new(0.8, 0.8, 0.8), CFrame.new(x, POLE_TOP + 0.3, z), GOLD, M.Metal, BALL)
		end
		FairKit.Truss(r.Model, "Rig", r.Base * Vector3.new(-POLE_X, RIG_Y, sx * POLE_Z), r.Base * Vector3.new(POLE_X, RIG_Y, sx * POLE_Z), r.Base:VectorToWorldSpace(Vector3.new(0, 1, 0)), 0.9, 0.18, Color3.fromRGB(60, 60, 70), 12)
		-- plates-formes du funambule (bras du mât avant)
		Solid(Fixed(r, "WirePlatform", Vector3.new(1.8, 0.3, 1.8), CFrame.new(sx * (WIRE_X + 0.7), WIRE_Y - 0.15, WIRE_Z), C.Steel, M.DiamondPlate))
		FairKit.Beam(r.Model, "WireArm", r.Base * Vector3.new(sx * POLE_X, WIRE_Y - 0.45, -POLE_Z), r.Base * Vector3.new(sx * (WIRE_X + 0.7), WIRE_Y - 0.45, WIRE_Z), 0.3, 0.3, C.Steel)
	end
	-- traverses des trapèzes (le long de z) + crochets
	for _, x in ipairs({ BAR_A, BAR_B }) do
		FairKit.Beam(r.Model, "RigCross", r.Base * Vector3.new(x, RIG_Y, -POLE_Z), r.Base * Vector3.new(x, RIG_Y, POLE_Z), 0.5, 0.5, Color3.fromRGB(60, 60, 70))
	end
	-- plate-forme du voltigeur (sur une traverse entre les 2 mâts de gauche) + échelle
	FairKit.Beam(r.Model, "PlatformBeam", r.Base * Vector3.new(-POLE_X, PLATFORM_Y - 0.45, -POLE_Z), r.Base * Vector3.new(-POLE_X, PLATFORM_Y - 0.45, POLE_Z), 0.4, 0.4, C.Steel)
	Solid(Fixed(r, "Platform", Vector3.new(2.0, 0.3, 2.4), CFrame.new(PLATFORM_X, PLATFORM_Y - 0.15, 0), C.Steel, M.DiamondPlate))
	for _, sz in ipairs({ -1.2, 1.2 }) do
		rod(r, "PlatformRail", Vector3.new(PLATFORM_X - 1, PLATFORM_Y + 2.4, sz), Vector3.new(PLATFORM_X + 0.6, PLATFORM_Y + 2.4, sz), 0.1, GOLD, M.Metal)
		rod(r, "PlatformRailPost", Vector3.new(PLATFORM_X - 1, PLATFORM_Y, sz), Vector3.new(PLATFORM_X - 1, PLATFORM_Y + 2.4, sz), 0.1, GOLD, M.Metal)
	end
	local function ladder(x: number, z: number, y1: number)
		for _, dz in ipairs({ -0.45, 0.45 }) do
			rod(r, "LadderRope", Vector3.new(x, FLOOR, z + dz), Vector3.new(x, y1, z + dz), 0.08, ROPE_C, M.Fabric)
		end
		local n = math.floor((y1 - FLOOR) / 1.0)
		for k = 1, n - 1 do
			local y = FLOOR + k * (y1 - FLOOR) / n
			rod(r, "LadderRung", Vector3.new(x, y, z - 0.45), Vector3.new(x, y, z + 0.45), 0.1, PLANK, M.Wood)
		end
	end
	ladder(PLATFORM_X, 1.8, PLATFORM_Y)
	ladder(BAR_B + 1.6, 1.9, RIG_Y - 0.3)
	-- fil de funambule
	rod(r, "HighWire", Vector3.new(-WIRE_X, WIRE_Y, WIRE_Z), Vector3.new(WIRE_X, WIRE_Y, WIRE_Z), 0.08, Color3.fromRGB(200, 200, 210), M.Metal)
	-- treillis du gréement entre les mâts (y 22) + filet de sécurité
	local net = Fixed(r, "Net", Vector3.new(17, 0.08, 7.2), CFrame.new(0, NET_Y, 0), Color3.fromRGB(28, 28, 34), M.Fabric)
	net.Transparency = 0.55
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Fixed(r, "NetPost", Vector3.new(0.16, NET_Y, 0.16), CFrame.new(sx * 8.5, NET_Y / 2 + FLOOR / 2, sz * 3.6), C.Steel, M.Metal)
		end
		rod(r, "NetEdge", Vector3.new(sx * 8.5, NET_Y, -3.6), Vector3.new(sx * 8.5, NET_Y, 3.6), 0.12, C.Steel, M.Metal)
	end
	-- couronne de projecteurs (12 côtés, y 24) + 6 projecteurs ; 2 vraies
	-- lumières (≤ 0,9) qui suivent le numéro
	local ringY, ringR = 24, 12.5
	for k = 0, 11 do
		rod(r, "LightRing", polar(k / 12 * TAU, ringR, ringY), polar((k + 1) / 12 * TAU, ringR, ringY), 0.3, Color3.fromRGB(50, 50, 58), M.Metal)
	end
	local cans = {}
	for k = 0, 5 do
		local a = (k + 0.5) / 6 * TAU
		local from = polar(a, ringR, ringY - 0.6)
		local head = Fixed(r, "Projector", Vector3.new(1.0, 1.0, 1.6), CFrame.lookAt(from, Vector3.new(0, FLOOR, 0)), Color3.fromRGB(36, 36, 42), M.Metal)
		local lens = Glow(Fixed(r, "Lens", Vector3.new(0.1, 0.8, 0.8), CFrame.lookAt(from, Vector3.new(0, FLOOR, 0)) * CFrame.new(0, 0, -0.82) * ANG(0, math.rad(90), 0), C.Bulb, M.SmoothPlastic, CYL))
		local beam = Fixed(r, "LightBeam", Vector3.new(10, 2.6, 2.6), CFrame.new(from), Color3.fromRGB(255, 244, 210), M.SmoothPlastic, CYL)
		beam.Transparency = 0.94
		local spot: SpotLight? = nil
		if k == 1 or k == 4 then
			local sp = Instance.new("SpotLight")
			sp.Name = "CircusSpot"
			sp.Brightness = 0.9
			sp.Range = 32
			sp.Angle = 26
			sp.Color = Color3.fromRGB(255, 240, 214)
			sp.Shadows = false
			sp.Face = Enum.NormalId.Front
			sp.Enabled = false
			sp.Parent = head
			spot = sp
		end
		table.insert(cans, { Head = head, Lens = lens, Beam = beam, From = from, Spot = spot, K = k })
	end
	return { Cans = cans, Net = net }
end

----------------------------------------------------------------------
-- Le spectacle (96 s) : fonction PURE de l'heure du serveur
----------------------------------------------------------------------

-- Programme (s)
local ACT = {
	Intro = { 0, 8 },
	Juggler = { 8, 24 },
	Clowns = { 24, 42 },
	Dogs = { 42, 56 },
	Trapeze = { 56, 74 },
	Wire = { 74, 88 },
	Finale = { 88, 96 },
}
FairCircus.ACT = ACT

local function actAt(u: number): string
	for name, w in pairs(ACT) do
		if u >= w[1] and u < w[2] then
			return name
		end
	end
	return "Intro"
end

-- présence dans [a, b] avec 2 s d'entrée / sortie depuis les coulisses
local function window(t: number, a: number, b: number): (number, boolean)
	if t < a - 2 or t > b + 2 then
		return 0, false
	end
	if t < a then
		return (t - (a - 2)) / 2, true
	end
	if t > b then
		return 1 - (t - b) / 2, true
	end
	return 1, false
end

local function travel(to: Vector3, u: number): Vector3
	return BACKSTAGE:Lerp(to, smooth(u))
end

local function buildShow(r: RideFx, folder: Instance, booth: CFrame): any
	local NPC = ParkKit.NPC()
	local show: any = { Npcs = {}, Parts = {}, Frames = {}, Fans = {}, Band = {}, Queue = {}, HideIndex = {} }
	if not NPC or type(NPC.Build) ~= "function" then
		return show
	end
	ensureAnims()
	local function npc(style: string, seed: number, opts: any): Model?
		local o = opts or {}
		o.Seed = seed
		o.Solid = if o.Solid == nil then false else o.Solid
		o.Look = false
		local ok, m = pcall(NPC.Build, style, o)
		if not ok or not m then
			return nil
		end
		m:PivotTo(r.Base * CFrame.new(BACKSTAGE))
		m.Parent = folder
		return m
	end
	show.Ringmaster = npc("salesperson", 501, { Shirt = Color3.fromRGB(186, 30, 44), Pants = Color3.fromRGB(240, 240, 236), Prop = "none" })
	show.Juggler = npc("pedestrian", 502, { Shirt = Color3.fromRGB(255, 200, 60), Pants = Color3.fromRGB(80, 60, 160), Prop = "none" })
	show.Rider = npc("jogger", 503, { Shirt = Color3.fromRGB(80, 170, 255), Pants = Color3.fromRGB(250, 250, 252), Prop = "none" })
	show.Flyer = npc("jogger", 504, { Shirt = Color3.fromRGB(255, 132, 180), Pants = Color3.fromRGB(255, 132, 180), Prop = "none" })
	show.Catcher = npc("jogger", 505, { Shirt = Color3.fromRGB(252, 244, 228), Pants = Color3.fromRGB(186, 150, 246), Prop = "none" })
	show.Clown1 = npc("pedestrian", 506, { Shirt = Color3.fromRGB(128, 214, 150), Pants = Color3.fromRGB(236, 72, 140), Hair = Color3.fromRGB(255, 120, 40), Prop = "none" })
	show.Clown2 = npc("kid", 507, { Shirt = Color3.fromRGB(255, 176, 60), Pants = Color3.fromRGB(80, 170, 255), Hair = Color3.fromRGB(60, 200, 255), Prop = "none" })
	show.Trainer = npc("pedestrian", 509, { Shirt = Color3.fromRGB(40, 110, 70), Pants = Color3.fromRGB(240, 236, 220), Prop = "none" })
	show.Walker = npc("jogger", 510, { Shirt = Color3.fromRGB(250, 210, 80), Pants = Color3.fromRGB(250, 210, 80), Prop = "none" })
	-- caissière dans la cabine + 2 clients qui font la queue
	show.Cashier = npc("cashier", 508, { Solid = true })
	if show.Cashier then
		show.Cashier:PivotTo(r.Base * booth * CFrame.new(0, 0, 0.7))
	end
	for i = 1, 2 do
		local q = npc(i == 1 and "shopper" or "kid", 530 + i, { Solid = true })
		if q then
			q:PivotTo(r.Base * booth * CFrame.new(0, 0, -2.6 - (i - 1) * 2.2) * ANG(0, math.pi, 0))
			table.insert(show.Queue, q)
		end
	end
	-- détail (GraphicsQuality) : nombre de spectateurs
	local detail = 1
	pcall(function()
		local GQ = require(ReplicatedStorage.Shared.GraphicsQuality) :: any
		detail = GQ.DetailScale()
	end)
	local fanSpots = { { 0, 45 }, { 1, 74 }, { 2, 100 }, { 0, 128 }, { 3, 60 }, { 1, -50 }, { 2, -88 }, { 0, -115 }, { 3, -135 }, { 4, 88 }, { 4, -70 }, { 2, 136 } }
	local fans = if detail < 0.9 then 4 elseif detail > 1.1 then #fanSpots else 9
	local styles = { "shopper", "kid", "elder", "pedestrian", "kid", "shopper", "pedestrian", "elder", "kid", "shopper", "pedestrian", "kid" }
	for i, fs in ipairs(fanSpots) do
		if i > fans then
			break
		end
		local tier, deg = fs[1], fs[2]
		local m = npc(styles[i], 520 + i, { Solid = true })
		if m then
			-- (entre les sièges du serveur : décalage d'une demi-place)
			local a = math.rad(deg)
			local top = seatTop(tier)
			local foot = FLOOR + tier * FairRides.CIRCUS_TIER_DY
			local seatCF = CFrame.lookAt(polar(a, seatRadius(tier), top), Vector3.new(0, top, 0))
			m:PivotTo(r.Base * seatCF * CFrame.new(0, -(top - foot), 0.15))
			pcall(NPC.SetSeated, m, top - foot)
			table.insert(show.Fans, { Model = m, Seed = i * 1.3 })
		end
	end
	-- orchestre sur le balcon des coulisses
	for i, role in ipairs({ "trumpet", "drum", "trumpet" }) do
		local m = npc(i == 2 and "worker" or "pedestrian", 540 + i, { Shirt = RED_D, Pants = Color3.fromRGB(30, 30, 36), Prop = "none" })
		if m then
			local p = Vector3.new(-3.6 + (i - 1) * 3.6, 10.2, 26.2)
			m:PivotTo(r.Base * CFrame.lookAt(p, Vector3.new(0, 10.2, 0)))
			local inst = nil
			if role == "trumpet" then
				inst = Part(r.Model, "Trumpet", Vector3.new(1.3, 0.24, 0.24), r.Base, GOLD, M.Metal, CYL)
			else
				Fixed(r, "BandDrum", Vector3.new(1.3, 1.7, 1.7), CFrame.new(p + Vector3.new(0, 1.9, -1.1)) * VERTICAL, RED, M.SmoothPlastic, CYL)
			end
			table.insert(show.Band, { Model = m, Role = role, Inst = inst })
		end
	end
	-- vendeur de pop-corn (plateau) qui fait le tour de l'allée
	show.Vendor = npc("salesperson", 550, { Shirt = CANVAS, Pants = RED_D, Prop = "none", Solid = true })
	show.Tray = Part(r.Model, "PopcornTray", Vector3.new(1.6, 0.25, 1.0), r.Base, RED, M.SmoothPlastic)
	show.Popcorn = Part(r.Model, "Popcorn", Vector3.new(1.3, 0.5, 0.75), r.Base, Color3.fromRGB(255, 244, 200), M.SmoothPlastic)
	-- accessoires : chapeau de Monsieur Loyal, nez de clowns, balles,
	-- monocycle, voiture, cerceau, trapèzes, balancier, confettis, chiens
	local model = r.Model
	show.Hat = { Part(model, "TopHat", Vector3.new(1.1, 0.9, 0.9), r.Base, Color3.fromRGB(24, 24, 28), M.SmoothPlastic, CYL), Part(model, "TopHatBrim", Vector3.new(0.08, 1.45, 1.45), r.Base, Color3.fromRGB(24, 24, 28), M.SmoothPlastic, CYL), Part(model, "TopHatBand", Vector3.new(0.2, 0.95, 0.95), r.Base, RED, M.Fabric, CYL) }
	show.Noses = { Part(model, "ClownNose", Vector3.new(0.3, 0.3, 0.3), r.Base, Color3.fromRGB(240, 30, 40), M.SmoothPlastic, BALL), Part(model, "ClownNose", Vector3.new(0.3, 0.3, 0.3), r.Base, Color3.fromRGB(240, 30, 40), M.SmoothPlastic, BALL) }
	show.Balls = {}
	for i = 1, 3 do
		table.insert(show.Balls, Part(model, "JuggleBall", Vector3.one * 0.48, r.Base, ({ RED, C.Lemon, C.Sky })[i], M.SmoothPlastic, BALL))
	end
	show.Uni = {
		Wheel = Part(model, "UniWheel", Vector3.new(0.24, 1.9, 1.9), r.Base, Color3.fromRGB(30, 30, 36), M.Rubber, CYL),
		Hub = Part(model, "UniHub", Vector3.new(0.38, 0.55, 0.55), r.Base, C.SteelLight, M.Metal, CYL),
		Post = Part(model, "UniPost", Vector3.new(0.16, 1.6, 0.16), r.Base, C.SteelLight, M.Metal),
		Saddle = Part(model, "UniSaddle", Vector3.new(0.5, 0.22, 0.9), r.Base, RED, M.Leather),
	}
	local car = {}
	local carColor = Color3.fromRGB(255, 196, 60)
	local function carPart(name: string, size: Vector3, loc: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		table.insert(car, { Part = Part(model, name, size * 1.45, r.Base, color, mat or M.SmoothPlastic, shape), Loc = CFrame.new(loc.Position * 1.45) * loc.Rotation })
	end
	carPart("ClownCarBody", Vector3.new(2.4, 1.1, 3.4), CFrame.new(0, 0.95, 0), carColor)
	carPart("ClownCarHood", Vector3.new(2.3, 0.9, 1.4), CFrame.new(0, 1.2, -1.3), carColor, M.SmoothPlastic, BALL)
	carPart("ClownCarCab", Vector3.new(2.1, 1.3, 1.6), CFrame.new(0, 1.95, 0.5), Color3.fromRGB(80, 170, 255), M.SmoothPlastic, BALL)
	carPart("ClownCarDots", Vector3.new(0.05, 0.5, 0.5), CFrame.new(1.22, 1.0, 0.3) * ANG(0, math.rad(90), 0), RED, M.SmoothPlastic, CYL)
	carPart("ClownCarDots", Vector3.new(0.05, 0.5, 0.5), CFrame.new(-1.22, 1.0, 0.3) * ANG(0, math.rad(90), 0), RED, M.SmoothPlastic, CYL)
	for _, wx in ipairs({ -1.1, 1.1 }) do
		for _, wz in ipairs({ -1.1, 1.1 }) do
			carPart("ClownCarWheel", Vector3.new(0.4, 0.9, 0.9), CFrame.new(wx, 0.45, wz), Color3.fromRGB(30, 30, 36), M.Rubber, CYL)
		end
	end
	carPart("ClownCarHorn", Vector3.new(0.3, 0.3, 0.6), CFrame.new(0.8, 1.6, -1.6), GOLD, M.Metal, BALL)
	carPart("ClownCarFlower", Vector3.new(0.5, 0.5, 0.5), CFrame.new(-0.6, 2.8, 0.5), C.Pink, M.SmoothPlastic, BALL)
	show.Car = car
	-- cerceau (anneau de 16 tiges) tenu par le dresseur
	show.Hoop = {}
	for k = 0, 15 do
		table.insert(show.Hoop, Part(model, "Hoop", Vector3.new(0.6, 0.14, 0.14), r.Base, k % 2 == 0 and RED or C.White, M.SmoothPlastic, CYL))
	end
	show.Dogs = {}
	if type(NPC.BuildDog) == "function" then
		for i, breed in ipairs({ "caniche", "border collie", "dalmatien" }) do
			local ok, d = pcall(NPC.BuildDog, 560 + i, breed)
			if ok and d then
				d.Parent = folder
				d:PivotTo(r.Base * CFrame.new(BACKSTAGE))
				table.insert(show.Dogs, d)
			end
		end
	end
	show.Bars = {}
	for i, x in ipairs({ BAR_A, BAR_B }) do
		table.insert(show.Bars, {
			X = x,
			Ropes = { Part(model, "TrapezeRope", Vector3.new(0.07, TRAP_L, 0.07), r.Base, ROPE_C, M.Fabric), Part(model, "TrapezeRope", Vector3.new(0.07, TRAP_L, 0.07), r.Base, ROPE_C, M.Fabric) },
			Bar = Part(model, "TrapezeBar", Vector3.new(1.6, 0.16, 0.16), r.Base, C.SteelLight, M.Metal, CYL),
			Sign = if i == 1 then 1 else -1,
		})
		Fixed(r, "TrapezeHook", Vector3.new(0.5, 0.4, 1.8), CFrame.new(x, RIG_Y - 0.45, 0), C.Steel, M.Metal)
	end
	show.Pole = Part(model, "BalancePole", Vector3.new(8, 0.14, 0.14), r.Base, Color3.fromRGB(230, 230, 236), M.Metal, CYL)
	show.Confetti = {}
	for k = 1, 28 do
		table.insert(show.Confetti, Part(model, "Confetti", Vector3.new(0.28, 0.04, 0.2), r.Base * CFrame.new(0, -20, 0), FairKit.PALETTE[k % #FairKit.PALETTE + 1], M.SmoothPlastic))
	end
	return show
end

local function dir(theta: number): Vector3
	return Vector3.new(sin(theta), -cos(theta), 0)
end

local function stepShow(r: RideFx, show: any, t: number, near: boolean, fx: any)
	local NPC = ParkKit.NPC()
	local u = t % SHOW_T
	local parts, frames = show.Parts, show.Frames
	table.clear(parts)
	table.clear(frames)
	local B = r.Base
	local HIDE = CFrame.new(0, -30, 0)
	local function put(p: BasePart, cf: CFrame)
		table.insert(parts, p)
		table.insert(frames, B * cf)
	end
	local function place(m: Model?, cf: CFrame, anim: string, at: number)
		if not m or not NPC then
			return
		end
		if cf == HIDE then
			-- (chacun sa cachette sous le sol : jamais deux PNJ l'un dans l'autre)
			local k = show.HideIndex[m]
			if not k then
				show.HideCount = (show.HideCount or 0) + 1
				k = show.HideCount
				show.HideIndex[m] = k
			end
			cf = HIDE * CFrame.new(k * 3, 0, 0)
		end
		if NPC.Place then
			NPC.Place(m, B * cf)
		else
			m:PivotTo(B * cf)
		end
		if near then
			ParkKit.Animate(m, anim, at)
		end
	end
	local focus = Vector3.new(0, FLOOR + 3, 0)
	local front = Vector3.new(0, 0, -1)
	-- 🎩 Monsieur Loyal : présente au bord de la piste, au centre pour l'intro et le final
	do
		local center = u < ACT.Intro[2] or u >= ACT.Finale[1]
		local spot = if center then Vector3.new(0, FLOOR, -1.5) else Vector3.new(-6.5, FLOOR, -10.6)
		local look = if center then Vector3.new(0, FLOOR, -20) else Vector3.new(0, FLOOR, 0)
		local anim, at = "c11_present", t + 11
		if u >= ACT.Finale[1] + 4 then
			anim, at = "c11_bow", ((u - ACT.Finale[1] - 4) % 2) / 2
		end
		place(show.Ringmaster, CFrame.lookAt(spot, look), anim, at)
		if u < ACT.Intro[2] then
			focus = spot + Vector3.new(0, 3, 0)
		end
		local head = ParkKit.Head(show.Ringmaster)
		if head and show.Hat then
			local hatCF = B:ToObjectSpace(head) * CFrame.new(0, 0.85, 0)
			put(show.Hat[1], hatCF * VERTICAL)
			put(show.Hat[2], hatCF * CFrame.new(0, -0.42, 0) * VERTICAL)
			put(show.Hat[3], hatCF * CFrame.new(0, -0.3, 0) * VERTICAL)
		end
	end
	-- 🤹 jongleur + 🚲 monocycliste
	do
		local a0, a1 = ACT.Juggler[1], ACT.Juggler[2]
		local k, moving = window(u, a0 + 0.5, a1 - 0.5)
		local target = Vector3.new(0, FLOOR, -0.5)
		local p = travel(target, k)
		local d = if moving then (if u < (a0 + a1) / 2 then target - BACKSTAGE else BACKSTAGE - target) else front
		d = Vector3.new(d.X, 0, d.Z).Unit
		local cf = CFrame.lookAt(p, p + d)
		place(show.Juggler, cf, if moving then "walk" elseif k > 0.5 then "c11_juggle" else "idle", t + 2)
		local juggling = k > 0.99 and not moving
		for i, b in ipairs(show.Balls) do
			local ph = (t * 1.6 + (i - 1) / 3) % 1
			local side = if math.floor(t * 1.6 + (i - 1) / 3) % 2 == 0 then 1 else -1
			local x = side * (0.6 - 1.2 * ph)
			local y = 3.6 + 3.2 * 4 * ph * (1 - ph)
			put(b, if juggling then cf * CFrame.new(x, y, -0.8) elseif k > 0 then cf * CFrame.new(0.55, 2.7 + i * 0.001, -0.3) else HIDE)
		end
		if juggling then
			focus = p + Vector3.new(0, 4, 0)
		end
		-- monocycle : tours de piste autour du jongleur
		local kr = window(u, a0 + 2, a1 - 1)
		local ringR = 6.2
		local pr, fwd
		if u >= a0 + 2 and u <= a1 - 1 then
			local a = (u - a0 - 2) * 0.75
			pr = Vector3.new(sin(a) * ringR, FLOOR, cos(a) * ringR)
			fwd = Vector3.new(cos(a), 0, -sin(a))
		else
			local start = Vector3.new(0, FLOOR, ringR)
			pr = travel(start, kr)
			fwd = if u < (a0 + a1) / 2 then (start - BACKSTAGE) else (BACKSTAGE - start)
			if fwd.Magnitude < 0.01 then
				fwd = front
			end
			fwd = fwd.Unit
		end
		local base = CFrame.lookAt(pr, pr + fwd)
		local wobble = ANG(0, 0, sin(t * 5) * 0.05)
		local on = kr > 0
		place(show.Rider, base * CFrame.new(0, if on then 1.95 else -30, 0) * wobble, "c11_ride", t + 5)
		local uni = show.Uni
		local hidden = if on then CFrame.identity else HIDE
		put(uni.Wheel, hidden * base * CFrame.new(0, 0.95, 0) * ANG(0, math.rad(90), 0) * ANG(t * 6, 0, 0))
		put(uni.Hub, hidden * base * CFrame.new(0, 0.95, 0) * ANG(0, math.rad(90), 0))
		put(uni.Post, hidden * base * CFrame.new(0, 1.75, 0) * wobble)
		put(uni.Saddle, hidden * base * CFrame.new(0, 2.6, 0) * wobble)
	end
	-- 🚗 voiture de clowns : 2 tours, arrêt, les clowns jaillissent
	do
		local a0, a1 = ACT.Clowns[1], ACT.Clowns[2]
		local k = window(u, a0 + 1, a1 - 1)
		local ringR = 4.8
		local carCF
		if u >= a0 + 1 and u < a0 + 11 then
			local a = (u - a0 - 1) / 10 * TAU * 1.5 + math.pi
			local p = Vector3.new(sin(a) * ringR, FLOOR, cos(a) * ringR)
			carCF = CFrame.lookAt(p, p + Vector3.new(cos(a), 0, -sin(a)))
			focus = p + Vector3.new(0, 2, 0)
		elseif u >= a0 + 11 and u <= a1 - 1 then
			local a = 1.5 * TAU + math.pi
			local p = Vector3.new(sin(a) * ringR, FLOOR, cos(a) * ringR)
			carCF = CFrame.lookAt(p, p + Vector3.new(cos(a), 0, -sin(a)))
			focus = p + Vector3.new(0, 2, 0)
		else
			local start = Vector3.new(0, FLOOR, -ringR)
			local p = travel(start, k)
			carCF = CFrame.lookAt(p, p + (if u < (a0 + a1) / 2 then (start - BACKSTAGE) else (BACKSTAGE - start)).Unit)
			if k <= 0 then
				carCF = HIDE
			end
		end
		local bounce = CFrame.new(0, abs(sin(t * 9)) * 0.1, 0)
		for _, c in ipairs(show.Car) do
			put(c.Part, carCF * bounce * c.Loc)
		end
		for i, m in ipairs({ show.Clown1, show.Clown2 }) do
			if m then
				local outT = a0 + 11.3 + i * 0.4
				local out = u >= outT and u < a1 - 1.6 - i * 0.3
				local pop = math.clamp((u - outT) / 0.5, 0, 1)
				local sx = if i == 1 then -1 else 1
				local cf = if out then carCF * CFrame.new(sx * (2.6 + pop * 1.2), 0, -0.6 - (i - 1) * 0.8) * ANG(0, math.rad(sx * -70), 0) else HIDE
				place(m, cf, if out and pop >= 1 then (if (u - outT) % 3 < 1.5 then "cheer" else "c11_bow") else "idle", if (u - outT) % 3 < 1.5 then t + i * 3 else ((u - outT) % 1.5) / 1.5)
				local head = out and ParkKit.Head(m)
				put(show.Noses[i], if head then B:ToObjectSpace(head) * CFrame.new(0, -0.05, -0.42) else HIDE)
			end
		end
	end
	-- 🐩 chiens savants : tours de piste, saut dans le cerceau
	do
		local a0, a1 = ACT.Dogs[1], ACT.Dogs[2]
		local k, moving = window(u, a0 + 0.5, a1 - 0.5)
		local tp = travel(Vector3.new(0, FLOOR, -1.2), k)
		local hoopAngle = math.pi -- (cerceau côté entrée)
		local circleR = 5.2
		local present = k > 0
		local trainerCF = CFrame.lookAt(tp, tp + (if moving then (tp - BACKSTAGE).Unit else Vector3.new(-1, 0, 0)))
		place(show.Trainer, if present then trainerCF else HIDE, if moving then "walk" else "c11_hoop", t + 4)
		-- cerceau dans la main droite (ou au point fixe sur le cercle)
		local hoopC = Vector3.new(sin(hoopAngle) * circleR, FLOOR + 2.3, cos(hoopAngle) * circleR)
		local hoopCF = CFrame.lookAt(hoopC, hoopC + Vector3.new(1, 0, 0))
		for i, seg in ipairs(show.Hoop) do
			local a = (i - 0.5) / #show.Hoop * TAU
			put(seg, if present and not moving then hoopCF * CFrame.new(cos(a) * 1.5, sin(a) * 1.5, 0) * ANG(0, math.rad(90), 0) * ANG(a + math.pi / 2, 0, 0) else HIDE)
		end
		for i, dog in ipairs(show.Dogs) do
			local dk = window(u, a0 + 1 + i * 0.5, a1 - 1 - i * 0.3)
			local cf, speed
			if dk <= 0 then
				cf = HIDE
				speed = 0
			elseif u > a0 + 2 + i * 0.5 and u < a1 - 2 - i * 0.3 then
				local a = (u - a0) * 1.1 - i * 0.9
				local p = Vector3.new(sin(a) * circleR, FLOOR, cos(a) * circleR)
				local tangent = Vector3.new(cos(a), 0, -sin(a))
				-- saut quand il passe au cerceau
				local da = ((a - hoopAngle) + math.pi) % TAU - math.pi
				local jump = bell(da, -0.45, 0.45) * 2.6
				cf = CFrame.lookAt(p + Vector3.new(0, jump, 0), p + Vector3.new(0, jump, 0) + tangent)
				speed = circleR * 1.1
			else
				local p = travel(Vector3.new(sin(i) * circleR, FLOOR, cos(i) * circleR), dk)
				cf = CFrame.lookAt(p, p + Vector3.new(0, 0, -1))
				speed = 5
			end
			if NPC and NPC.AnimateDog then
				pcall(NPC.AnimateDog, dog, B * cf, t, speed)
			end
		end
		if present then
			focus = hoopC
		end
	end
	-- 🤸 TRAPÈZE VOLANT : 2 pendules (même fréquence, en opposition) ; le
	-- voltigeur lâche sa barre au plus haut, vole (salto) jusqu'aux mains du
	-- porteur pendu par les genoux, se balance avec lui, puis tombe dans le
	-- filet qui se creuse et rebondit
	do
		local a0, a1 = ACT.Trapeze[1], ACT.Trapeze[2]
		local swing0 = a0 + 4 -- départ du balancement
		local tt = u - swing0
		local ph = if u >= swing0 then sin(TRAP_W * tt - math.pi / 2) else -1
		local thA = TRAP_AMP * ph
		local thB = -CATCH_AMP * ph
		local T = 2 * math.pi / TRAP_W
		local tRelease = 1.5 * T -- θA au plus haut côté porteur (θB au plus haut côté voltigeur)
		local tFly = 0.53
		local tDrop = tRelease + 2 * T -- de nouveau au plus haut côté voltigeur
		local pivA = Vector3.new(BAR_A, RIG_Y - 0.6, 0)
		local pivB = Vector3.new(BAR_B, RIG_Y - 0.6, 0)
		local active = u >= a0 - 2 and u < a1 + 2
		for i, bar in ipairs(show.Bars) do
			local th = if i == 1 then thA else thB
			if not active then
				th = 0
			end
			local piv = if i == 1 then pivA else pivB
			local pivot = CFrame.new(piv) * ANG(0, 0, th)
			for k, rope in ipairs(bar.Ropes) do
				put(rope, pivot * CFrame.new(0, -TRAP_L / 2, if k == 1 then -0.75 else 0.75))
			end
			put(bar.Bar, pivot * CFrame.new(0, -TRAP_L, 0) * ANG(0, math.rad(90), 0))
		end
		local flyer, catcher = show.Flyer, show.Catcher
		-- repère "debout, face +X" et "tête en bas, face -X"
		local FACE_X = ANG(0, -math.pi / 2, 0)
		local UPSIDE = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, -1, 0))
		if active then
			-- porteur : monte à l'échelle (à côté de sa barre), puis pendu par les genoux
			local climbR = math.clamp((u - (a0 - 1.5)) / 3.5, 0, 1)
			if u < a0 + 2.2 then
				local lad = Vector3.new(BAR_B + 1.6, FLOOR + climbR * (RIG_Y - TRAP_L - 3.5 - FLOOR), 2.6)
				place(catcher, CFrame.lookAt(lad, lad + Vector3.new(0, 0, -1)), "c11_climb", t)
			else
				local knees = pivB + dir(thB) * (TRAP_L + 0.05)
				local hang = CFrame.new(knees) * ANG(0, 0, thB) * UPSIDE * CFrame.new(0, -1.5, 0)
				place(catcher, hang, "c11_catch", t + 7)
			end
			local catcherHands = pivB + dir(thB) * (TRAP_L + KNEE_REACH)
			if u < swing0 - 0.4 then
				-- voltigeur : monte à l'échelle puis attend sur la plate-forme, la barre en main
				local climbF = math.clamp((u - (a0 - 2)) / 3.2, 0, 1)
				if climbF < 1 then
					local lad = Vector3.new(PLATFORM_X, FLOOR + climbF * (PLATFORM_Y - FLOOR), 2.7)
					place(flyer, CFrame.lookAt(lad, lad + Vector3.new(0, 0, -1)), "c11_climb", t)
				else
					local hands = pivA + dir(-TRAP_AMP) * TRAP_L
					place(flyer, CFrame.new(hands) * ANG(0, 0, -TRAP_AMP) * CFrame.new(0, -REACH, 0) * FACE_X, "c11_hang", t)
				end
			elseif tt < tRelease then
				local hands = pivA + dir(thA) * TRAP_L
				place(flyer, CFrame.new(hands) * ANG(0, 0, thA) * CFrame.new(0, -REACH, 0) * FACE_X, "c11_hang", t)
				focus = hands
			elseif tt < tRelease + tFly then
				-- VOL avec salto : des mains (barre A) aux mains du porteur
				local w = (tt - tRelease) / tFly
				local from = pivA + dir(TRAP_AMP) * TRAP_L
				local to = pivB + dir(-CATCH_AMP) * (TRAP_L + KNEE_REACH)
				local hands = from:Lerp(to, w) + Vector3.new(0, 1.4 * 4 * w * (1 - w), 0)
				place(flyer, CFrame.new(hands) * ANG(0, 0, -w * TAU) * CFrame.new(0, -REACH, 0) * FACE_X, "c11_hang", t)
				focus = hands
			elseif tt < tDrop then
				place(flyer, CFrame.new(catcherHands) * ANG(0, 0, thB) * CFrame.new(0, -REACH, 0) * FACE_X, "c11_hang", t)
				focus = catcherHands
			else
				-- lâché : tombe dans le filet, rebondit, saute au sol et salue
				local d = tt - tDrop
				local start = pivB + dir(-CATCH_AMP) * (TRAP_L + KNEE_REACH + REACH)
				local landX = start.X
				local fall = math.sqrt(2 * max(0.1, start.Y - NET_Y) / 30)
				local pos
				local anim, at = "c11_hang", t
				if d < fall then
					pos = Vector3.new(landX, max(NET_Y, start.Y - 30 * d * d / 2), 0)
				elseif d < fall + 1.4 then
					local b = d - fall
					pos = Vector3.new(landX, NET_Y + abs(sin(b * math.pi * 1.4)) * 2.2 * (1 - b / 1.4), 0)
					anim = "cheer"
				elseif d < fall + 3.0 then
					local w = (d - fall - 1.4) / 1.6
					local edge = Vector3.new(-9.0, FLOOR, -1.5)
					pos = Vector3.new(landX, NET_Y, 0):Lerp(edge, smooth(w)) + Vector3.new(0, 1.5 * 4 * w * (1 - w), 0)
					anim = "walk"
				else
					pos = Vector3.new(-9.0, FLOOR, -1.5)
					anim, at = "c11_bow", math.clamp((d - fall - 3.0) / 1.5, 0, 1)
				end
				place(flyer, CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)), anim, at)
				-- le filet se creuse sous le rebond
				if fx and fx.Net and d >= fall and d < fall + 1.6 then
					local sag = bell(d - fall, 0, 0.8) * 0.9
					put(fx.Net, CFrame.new(0, NET_Y - sag, 0))
				elseif fx and fx.Net then
					put(fx.Net, CFrame.new(0, NET_Y, 0))
				end
				focus = pos + Vector3.new(0, 2, 0)
			end
		else
			place(flyer, HIDE, "idle", t)
			place(catcher, HIDE, "idle", t)
		end
	end
	-- 🎪 FUNAMBULE : monte, traverse le fil avec son balancier, redescend
	do
		local a0, a1 = ACT.Wire[1], ACT.Wire[2]
		local walker = show.Walker
		local active = u >= a0 - 1 and u < a1 + 1
		local poleCF = HIDE
		if active then
			local climb = math.clamp((u - (a0 - 1)) / 2.5, 0, 1)
			local cross = math.clamp((u - (a0 + 2)) / 10, 0, 1)
			local down = math.clamp((u - (a1 - 1.8)) / 2.5, 0, 1)
			local p, look, anim
			if cross <= 0 then
				p = Vector3.new(-WIRE_X - 0.6, FLOOR + climb * (WIRE_Y - FLOOR), WIRE_Z - 1)
				look, anim = p + Vector3.new(1, 0, 0), if climb < 1 then "c11_climb" else "idle"
			elseif down <= 0 then
				local x = -WIRE_X + cross * 2 * WIRE_X
				-- (petite hésitation au milieu)
				p = Vector3.new(x, WIRE_Y + 0.05, WIRE_Z)
				look, anim = p + Vector3.new(1, 0, 0), "c11_wire"
				focus = p + Vector3.new(0, 3, 0)
			else
				p = Vector3.new(WIRE_X + 0.6, WIRE_Y - down * (WIRE_Y - FLOOR), WIRE_Z - 1)
				look, anim = p + Vector3.new(1, 0, 0), if down < 1 then "c11_climb" else "c11_bow"
			end
			local sway = if cross > 0 and down <= 0 then ANG(sin(t * 1.3) * 0.06, 0, 0) else CFrame.identity
			place(walker, CFrame.lookAt(p, look) * sway, anim, if anim == "c11_bow" then 0.5 else t)
			if cross > 0 and down <= 0 then
				local l, rh = ParkKit.Hand(walker, "L"), ParkKit.Hand(walker, "R")
				if l and rh then
					local mid = B:PointToObjectSpace((l.Position + rh.Position) / 2)
					poleCF = CFrame.new(mid) * ANG(0, math.rad(90), 0) * ANG(sin(t * 1.3) * 0.08, 0, 0)
				else
					poleCF = CFrame.new(p + Vector3.new(0, 3.3, 0)) * ANG(0, math.rad(90), 0)
				end
			end
		else
			place(walker, HIDE, "idle", t)
		end
		put(show.Pole, poleCF)
	end
	-- 🎉 FINAL : confettis qui tombent en virevoltant
	do
		local a0 = ACT.Finale[1]
		local on = u >= a0 and u < SHOW_T
		for k, c in ipairs(show.Confetti) do
			if on then
				local life = (u - a0 + k * 0.29) % 4
				local a = k * 2.4 + life * 1.5
				local rr = 2 + (k % 7)
				put(c, CFrame.new(sin(a) * rr, 21 - life * 5, cos(a) * rr) * ANG(life * 6 + k, life * 4, k))
			else
				put(c, HIDE)
			end
		end
		if on then
			focus = Vector3.new(0, FLOOR + 3, -1.5)
		end
	end
	-- 🥁 orchestre, public, vendeur, caissière, file d'attente
	if near and NPC then
		for i, b in ipairs(show.Band) do
			ParkKit.Animate(b.Model, if b.Role == "trumpet" then "p11_trumpet" else "p11_drum", t + i)
			if b.Inst then
				local l, rh = ParkKit.Hand(b.Model, "L"), ParkKit.Hand(b.Model, "R")
				local root = b.Model.PrimaryPart
				if l and rh and root then
					local mid = (l.Position + rh.Position) / 2
					put(b.Inst, B:ToObjectSpace(CFrame.lookAt(mid, mid + root.CFrame.LookVector) * ANG(0, math.rad(90), 0) * CFrame.new(-0.3, 0, 0)))
				end
			end
		end
		local climax = (u > ACT.Clowns[1] + 11 and u < ACT.Clowns[1] + 15) or (u > ACT.Trapeze[1] + 7.5 and u < ACT.Trapeze[1] + 9.5) or u >= ACT.Finale[1]
		for _, fan in ipairs(show.Fans) do
			pcall(NPC.Animate, fan.Model, if climax then "cheer" else "clap", t + fan.Seed)
		end
		if show.Cashier then
			pcall(NPC.Animate, show.Cashier, "talk", t + 9)
		end
		for i, q in ipairs(show.Queue) do
			pcall(NPC.Animate, q, i == 1 and "talk" or "idle", t + i)
		end
		-- vendeur : aller-retour dans l'allée, côté entrée (entre la bordure et la barrière)
		if show.Vendor then
			local s0 = (t * 0.09) % 2
			local w = if s0 < 1 then s0 else 2 - s0
			local a = math.rad(-162 + 64 * smooth(w))
			local p = polar(a, 10.6, FLOOR)
			local tangent = Vector3.new(cos(a), 0, -sin(a)) * (if s0 < 1 then 1 else -1)
			place(show.Vendor, CFrame.lookAt(p, p + tangent), "walk", t * 0.8)
			local hand = ParkKit.Hand(show.Vendor, "R")
			local root = show.Vendor.PrimaryPart
			if hand and root then
				local trayCF = B:ToObjectSpace(CFrame.new(hand.Position + root.CFrame.LookVector * 0.5 + Vector3.new(0, 0.4, 0)) * root.CFrame.Rotation)
				put(show.Tray, trayCF)
				put(show.Popcorn, trayCF * CFrame.new(0, 0.35, 0))
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	show.Focus = focus
	show.Act = actAt(u)
	-- projecteurs : faisceaux vers le numéro en cours
	if fx and fx.Cans then
		for _, can in ipairs(fx.Cans) do
			local from = can.From
			local to = focus + Vector3.new(sin(can.K * 1.7) * 1.2, -2.5, cos(can.K * 1.7) * 1.2)
			local look = CFrame.lookAt(from, to)
			can.Head.CFrame = B * look
			can.Lens.CFrame = B * look * CFrame.new(0, 0, -0.82) * ANG(0, math.rad(90), 0)
			local len = (to - from).Magnitude
			can.Beam.Size = Vector3.new(len - 1, 2.8, 2.8)
			can.Beam.CFrame = B * CFrame.lookAt((from + to) / 2, to) * ANG(0, math.rad(90), 0)
		end
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function FairCircus.Build(r: RideFx, npcFolder: Instance)
	local booth = buildTent(r)
	local fx = buildInside(r)
	local show = buildShow(r, npcFolder, booth)
	r.Radius = R + 6
	local lights = {}
	for _, can in ipairs(fx.Cans) do
		if can.Spot then
			table.insert(lights, can.Spot)
		end
	end
	r.Extra = {
		Show = show,
		Fx = fx,
		Lights = lights,
		Step = function(t: number)
			local camera = workspace.CurrentCamera
			local dist = if camera then (camera.CFrame.Position - r.Base.Position).Magnitude else math.huge
			local near = dist < SHOW_R
			for _, l in ipairs(lights) do
				local on = dist < LIGHT_R
				if l.Enabled ~= on then
					l.Enabled = on
				end
			end
			if near or show.Parked ~= true then
				show.Parked = not near
				stepShow(r, show, t, near, fx)
			end
		end,
	}
end

function FairCircus.Debug(r: RideFx): any
	local show = r.Extra and r.Extra.Show
	return { Act = show and show.Act, Focus = show and show.Focus, Fans = show and #show.Fans or 0, Dogs = show and #(show.Dogs or {}) or 0 }
end

FairCircus.SHOW_R = SHOW_R

return FairCircus
