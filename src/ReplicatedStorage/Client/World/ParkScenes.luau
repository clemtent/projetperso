--[[
	ParkScenes (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ParkScenes

	🌳 Dopamine Town (v11, PARK11) : les SCÈNES VIVANTES des parcs, côté
	CLIENT (en flux, animées près de la caméra par ParkKit.Actor) :
	  - 🪑 PNJ sur les BANCS, posés naturellement (assis pour de vrai : pieds
	    au sol, mains...) et qui FONT quelque chose : lire le journal (pages
	    qui tournent), téléphone, nourrir les pigeons (miettes lancées), deux
	    amis qui discutent, somnoler, manger un sandwich ;
	  - 🏃 JOGGEURS qui font le tour d'une boucle (vraie foulée) ;
	  - 🧺 PIQUE-NIQUES : nappe à carreaux, panier, assiettes, famille assise
	    dans l'herbe ; TABLES de pique-nique (dessus 3,1, bancs 1,85) ;
	  - 🐕 PARC À CHIENS : enclos à double portillon, agility (haies, cerceau,
	    rampe, tunnel), bols d'eau, maîtres qui LANCENT la balle, chiens qui
	    courent la chercher et la rapportent (NPCModels.BuildDog, NPC11) ;
	  - 🎺 KIOSQUE À MUSIQUE : octogone sur socle de pierre, colonnes de fonte,
	    toit en pavillon à lambrequins, garde-corps, petit orchestre (trompette,
	    tuba, tambour) qui joue en silence ;
	  - 🌹 ROSERAIE à la française : parterres de buis, rosiers, arches
	    fleuries, fontaine au centre (FountainKit), bancs occupés ;
	  - 🏋️ AGRÈS (barres, banc à abdos) avec un sportif.
	Échelle SCALE11 (bancs 1,85 ; tables 3,1 ; garde-corps 3,6). Aucune
	lumière, aucun son, aucune pièce serveur.

	API : ParkScenes.BUILDERS[kind](m, F, seed, data?) -> état
	      kinds : "RoseGarden", "DogPark", "Bandstand", "Picnic",
	              "PicnicTables", "BenchRow", "Fitness"
	      ParkScenes.Sitter(m, seatCF, groundY, seed, activity?) -> PNJ animé
	      ParkScenes.JogLoop(m, points: {Vector3}, seed, count)
	      ParkScenes.FOOT[kind] = Vector2 (emprise)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParkKit = require(script.Parent.ParkKit)
local FountainKit = require(script.Parent.FountainKit)
local ParkLayout = require(ReplicatedStorage.Shared.ParkLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)

local ParkScenes = {}

local M = ParkKit.M
local rgb = ParkKit.rgb
local TAU = ParkKit.TAU
local Part, Box, Column, Rod, Egg, Ring = ParkKit.Part, ParkKit.Box, ParkKit.Column, ParkKit.Rod, ParkKit.Egg, ParkKit.Ring
local hash, pick = ParkKit.Hash, ParkKit.Pick
local ANG = CFrame.Angles
local sin, cos, abs, max = math.sin, math.cos, math.abs, math.max

local WHITE = rgb(250, 250, 248)
local GRAVEL = rgb(222, 208, 182)
local BOX_GREEN = rgb(54, 104, 52)
local IRON = rgb(34, 46, 42)
local STONE = rgb(214, 206, 192)
local ROSES = { rgb(214, 40, 70), rgb(250, 140, 170), rgb(255, 236, 220), rgb(250, 200, 70), rgb(236, 96, 60), rgb(180, 40, 110) }

ParkScenes.FOOT = {
	RoseGarden = Vector2.new(40, 40),
	DogPark = Vector2.new(36, 30),
	Bandstand = Vector2.new(24, 24),
	Picnic = Vector2.new(26, 18),
	PicnicTables = Vector2.new(28, 16),
	BenchRow = Vector2.new(20, 6),
	FountainSquare = Vector2.new(48, 48),
	Fitness = Vector2.new(20, 14),
}

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function actor(m: Instance, pos: Vector3, fn: (t: number, dt: number) -> (), seed: number)
	ParkKit.Actor(m, pos, fn, hash(seed, 17) * 30)
end

----------------------------------------------------------------------
-- Anims "maison" assises / de parc (NPCModels.AddAnim)
----------------------------------------------------------------------

local ANIMS = {}

-- lire le journal (assis) : deux mains tiennent le journal devant la
-- poitrine, la tête balaie les lignes, page qui se tourne de temps en temps
ANIMS.p11_read = {
	Fallback = "sit",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "grip"
		local turn = max(0, sin(t * 0.35)) ^ 12
		P.LUp = ANG(0.75, 0, -0.18 - turn * 0.2)
		P.RUp = ANG(0.75, 0, 0.18 + turn * 0.3)
		P.LLo, P.RLo = 1.45, 1.45 - turn * 0.4
		P.HeadPitch = 0.38 + sin(t * 0.9) * 0.04
		P.HeadYaw = sin(t * 1.7) * 0.12
		P.LookW = 0.1
	end,
}

-- nourrir les pigeons : la main droite plonge dans le sachet (main gauche)
-- puis lance des miettes devant
ANIMS.p11_feed = {
	Fallback = "sit",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "cup"
		local c = (t * 0.45) % 1
		local toss = smooth((c - 0.55) / 0.15) * (1 - smooth((c - 0.8) / 0.2))
		P.LUp = ANG(0.55, 0, -0.1)
		P.LLo = 1.3
		P.RUp = ANG(0.5 + toss * 0.7, 0, 0.15 - toss * 0.05)
		P.RLo = 1.3 - toss * 1.0
		P.Lean = 0.12 + toss * 0.08
		P.HeadPitch = 0.3
		P.LookW = 0.2
	end,
}

-- somnoler : tête qui tombe doucement, se relève d'un coup de temps en temps
ANIMS.p11_doze = {
	Fallback = "sit",
	Fn = function(P: any, t: number, _seed: number)
		local nod = (t * 0.12) % 1
		P.HeadPitch = 0.15 + smooth(nod / 0.9) * 0.4 - (nod > 0.9 and 0.4 or 0)
		P.HeadRoll = 0.08
		P.LUp = ANG(0.25, 0, 0.25)
		P.RUp = ANG(0.25, 0, -0.25)
		P.LLo, P.RLo = 1.0, 1.0
		P.Lean = -0.12
		P.LookW = 0
	end,
}

-- manger un sandwich : la main droite monte à la bouche, mâche
ANIMS.p11_eat = {
	Fallback = "sit",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "relax"
		local c = (t * 0.3) % 1
		local bite = smooth(c / 0.2) * (1 - smooth((c - 0.35) / 0.25))
		P.RUp = ANG(0.35 + bite * 0.55, 0.25, 0.1)
		P.RLo = 1.2 + bite * 0.75
		P.LUp = ANG(0.3, 0, -0.15)
		P.LLo = 1.2
		P.HeadPitch = 0.05 - bite * 0.12 + sin(t * 9) * 0.02 * (1 - bite)
		P.LookW = 0.3
	end,
}

-- lancer une balle (debout) : bras droit armé derrière, puis lancer
ANIMS.p11_throw = {
	Fallback = "wave",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "relax"
		local u = math.clamp(t, 0, 1)
		local cock = smooth(u / 0.4)
		local fling = smooth((u - 0.4) / 0.2)
		P.RUp = ANG(-0.9 * cock + 2.6 * fling, 0, 0.5 - 0.3 * fling)
		P.RLo = 1.4 * cock * (1 - fling) + 0.2
		P.LUp = ANG(0.6 * cock, 0, -0.3)
		P.LLo = 0.5
		P.Twist = 0.45 * cock - 0.6 * fling
		P.Lean = -0.05 * cock + 0.25 * fling
		P.LTh, P.RTh = 0.3 * fling, -0.2 * cock
		P.LKnee, P.RKnee = 0.25, 0.35
		P.LookW = 0
	end,
}

-- musiciens : trompette (deux mains à la bouche), tambour (baguettes)
ANIMS.p11_trumpet = {
	Fallback = "idle",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "grip"
		local b = sin(t * 4) * 0.04
		P.RUp = ANG(1.25 + b, 0, 0.15)
		P.RLo = 1.85
		P.LUp = ANG(1.2 + b, 0, -0.2)
		P.LLo = 1.9
		P.HeadPitch = -0.15 + b
		P.Lean = -0.05 + b * 0.5
		P.Bob = abs(sin(t * 2.1)) * 0.02
		P.LookW = 0
	end,
}
ANIMS.p11_drum = {
	Fallback = "clap",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "grip"
		local l = abs(sin(t * 6))
		local r = abs(sin(t * 6 + 1.6))
		P.LUp = ANG(0.55 + l * 0.25, 0, -0.25)
		P.LLo = 1.25 - l * 0.35
		P.RUp = ANG(0.55 + r * 0.25, 0, 0.25)
		P.RLo = 1.25 - r * 0.35
		P.HeadPitch = 0.25
		P.LookW = 0
	end,
}
-- tractions / abdos (agrès)
ANIMS.p11_pullup = {
	Fallback = "cheer",
	Fn = function(P: any, t: number, _seed: number)
		P.RHand, P.LHand = "grip", "grip"
		local c = (sin(t * 2.2) + 1) / 2
		P.LUp = ANG(0.2, 0, -2.75 + c * 0.6)
		P.RUp = ANG(0.2, 0, 2.75 - c * 0.6)
		P.LLo, P.RLo = 0.2 + c * 1.6, 0.2 + c * 1.6
		P.LTh, P.RTh = 0.2, 0.2
		P.LKnee, P.RKnee = 0.9, 0.9
		P.HeadPitch = -0.2
		P.LookW = 0
	end,
}
-- étirements (debout) : bras en l'air, flexion latérale
ANIMS.p11_stretch = {
	Fallback = "cheer",
	Fn = function(P: any, t: number, _seed: number)
		local s = sin(t * 0.9)
		P.LUp = ANG(0.1, 0, -2.8)
		P.RUp = ANG(0.1, 0, 2.8)
		P.LLo, P.RLo = 0.15, 0.15
		P.Side = s * 0.28
		P.HeadRoll = s * 0.15
		P.LookW = 0
	end,
}

-- pétanque : accroupi, lancer de la boule par en dessous (t = phase 0..1)
ANIMS.p11_boules = {
	Fallback = "wave",
	Fn = function(P: any, t: number, _seed: number)
		local u = math.clamp(t, 0, 1)
		local crouch = math.sin(math.min(1, u * 1.2) * math.pi) * 0.8 + 0.2
		local swing = smooth((u - 0.3) / 0.35)
		P.LTh, P.RTh = 0.6 * crouch, 0.15 * crouch
		P.LKnee, P.RKnee = 1.1 * crouch, 0.6 * crouch
		P.LFoot = -0.4 * crouch
		P.Lean = 0.45 * crouch
		P.RUp = ANG(-0.7 + swing * 1.6, 0, 0.1)
		P.RLo = 0.25
		P.RHand = swing > 0.6 and "flat" or "grip"
		P.LUp = ANG(0.3, 0, -0.35)
		P.LLo = 0.6
		P.HeadPitch = -0.15
		P.LookW = 0
	end,
}
-- réfléchir (assis, main au menton), puis avancer une pièce
ANIMS.p11_ponder = {
	Fallback = "sit",
	Fn = function(P: any, t: number, _seed: number)
		local c = (t * 0.12) % 1
		local move = math.sin(math.clamp((c - 0.85) / 0.15, 0, 1) * math.pi)
		P.LUp = ANG(0.6, 0, -0.1)
		P.LLo = 2.1 - move * 0.3
		P.LHand = "fist"
		P.RUp = ANG(0.35 + move * 0.5, 0, 0.15)
		P.RLo = 1.1 - move * 0.4
		P.RHand = move > 0.2 and "grip" or "relax"
		P.Lean = 0.25
		P.HeadPitch = 0.35
		P.LookW = 0
	end,
}

ParkScenes.ANIMS = ANIMS
local ready = false
local function ensureAnims(): ()
	if not ready then
		ready = true
		ParkKit.RegisterAnims(ANIMS)
		-- (les anims de jeu, course comprise : ParkSports)
		local okS, ParkSports = pcall(require, script.Parent:FindFirstChild("ParkSports") :: any)
		if okS and type(ParkSports) == "table" and ParkSports.ANIMS then
			ParkKit.RegisterAnims(ParkSports.ANIMS)
		end
	end
end

----------------------------------------------------------------------
-- 🪑 PNJ assis sur un banc, qui fait quelque chose
----------------------------------------------------------------------

local ACTIVITIES = { "read", "phone", "feed", "chat", "doze", "eat", "read", "phone" }

-- seatCF : DESSUS de l'assise (regard -Z) ; groundY : sol
function ParkScenes.Sitter(m: Instance, seatCF: CFrame, groundY: number, seed: number, activity: string?): Model?
	ensureAnims()
	local act = activity or pick(ACTIVITIES, seed, 5)
	local style = pick({ "elder", "pedestrian", "shopper", "elder", "pedestrian", "kid" }, seed, 6)
	local prop = act == "phone" and "phone" or (act == "chat" and pick({ "coffee", "none" }, seed, 8) or "none")
	local npc = ParkKit.Sitter(m, style, seed, seatCF, groundY, prop)
	if not npc then
		return nil
	end
	local anim = ({ read = "p11_read", phone = "sit", feed = "p11_feed", chat = "talk", doze = "p11_doze", eat = "p11_eat" })[act] or "sit"
	-- accessoires : journal (2 pages entre les mains), sandwich, sachet de graines
	local paper: { BasePart } = {}
	local bite: BasePart? = nil
	local crumbs: { BasePart } = {}
	if act == "read" then
		for k = 1, 2 do
			local page = Part(m, "Newspaper", Vector3.new(1.05, 1.5, 0.03), seatCF, k == 1 and rgb(236, 232, 220) or rgb(228, 224, 212), M.SmoothPlastic)
			page.CastShadow = false
			table.insert(paper, page)
		end
	elseif act == "eat" then
		bite = Part(m, "Sandwich", Vector3.new(0.75, 0.3, 0.45), seatCF, rgb(226, 190, 130), M.SmoothPlastic)
	elseif act == "feed" then
		for k = 1, 6 do
			local c = Part(m, "Crumb", Vector3.new(0.12, 0.12, 0.12), seatCF, rgb(214, 186, 130), M.SmoothPlastic, "Ball")
			c.CastShadow = false
			table.insert(crumbs, c)
		end
	end
	local ground = seatCF * CFrame.new(0, -(seatCF.Position.Y - groundY), -2.6)
	actor(m, seatCF.Position, function(t: number)
		ParkKit.Animate(npc, anim, t)
		if #paper > 0 then
			local l, r = ParkKit.Hand(npc, "L"), ParkKit.Hand(npc, "R")
			if l and r then
				local mid = (l.Position + r.Position) / 2
				local root = npc.PrimaryPart
				local fwd = root and root.CFrame.LookVector or seatCF.LookVector
				local cf = CFrame.lookAt(mid + fwd * 0.05 + Vector3.new(0, 0.35, 0), mid + fwd * 2 + Vector3.new(0, 0.9, 0))
				local turn = max(0, sin(t * 0.35)) ^ 12
				paper[1].CFrame = cf * CFrame.new(-0.52, 0, 0) * ANG(0, -0.25, 0)
				paper[2].CFrame = cf * CFrame.new(0.52 - turn * 0.5, 0, -turn * 0.3) * ANG(0, 0.25 + turn * 1.6, 0)
			end
		elseif bite then
			local r = ParkKit.Hand(npc, "R")
			if r then
				bite.CFrame = r * CFrame.new(0, 0.05, -0.2)
			end
		elseif #crumbs > 0 then
			-- miettes lancées : une poignée part en cloche à chaque lancer
			local c = (t * 0.45) % 1
			local r = ParkKit.Hand(npc, "R")
			for k, crumb in ipairs(crumbs) do
				local u = math.clamp((c - 0.62) / 0.3, 0, 1)
				local spread = (k - 3.5) * 0.45
				local land = ground * CFrame.new(spread, 0.06, -hash(seed, k) * 2)
				if u <= 0 and r then
					crumb.CFrame = r
				else
					local from = r and r.Position or seatCF.Position
					local p = from:Lerp(land.Position, u) + Vector3.new(0, 4 * 0.8 * u * (1 - u), 0)
					crumb.CFrame = CFrame.new(p)
				end
			end
		end
	end, seed)
	return npc
end

-- Bancs d'une scène (plan partagé ParkLayout : le serveur a posé un Seat
-- sur chaque place libre) + PNJ sur les places marquées
local function benchesFor(m: Instance, F: CFrame, kind: string, seed: number)
	for _, b in ipairs(ParkLayout.Benches(kind, seed)) do
		ParkKit.Bench(m, F * b.CF, b.Len)
	end
	for i, st in ipairs(ParkLayout.Seats(kind, seed)) do
		if st.Npc and st.Bench < 100 then
			ParkScenes.Sitter(m, F * st.CF, F.Position.Y, seed * 13 + i, st.Activity)
		end
	end
end
ParkScenes.BenchesFor = benchesFor

----------------------------------------------------------------------
-- 🏃 Joggeurs sur une boucle (points au sol, fermée)
----------------------------------------------------------------------

function ParkScenes.JogLoop(m: Instance, points: { Vector3 }, seed: number, count: number)
	ensureAnims()
	local n = #points
	if n < 3 then
		return
	end
	local cum = { 0 }
	for i = 1, n do
		local a, b = points[i], points[i % n + 1]
		table.insert(cum, cum[#cum] + (b - a).Magnitude)
	end
	local total = cum[#cum]
	local function at(s: number): (Vector3, Vector3)
		s = s % total
		for i = 1, n do
			if s <= cum[i + 1] then
				local a, b = points[i], points[i % n + 1]
				local u = (s - cum[i]) / max(0.01, cum[i + 1] - cum[i])
				return a:Lerp(b, u), (b - a).Unit
			end
		end
		return points[1], (points[2] - points[1]).Unit
	end
	for k = 1, count do
		local speed = 8.5 + hash(seed, k) * 3
		local offset = hash(seed, k + 10) * total
		local dir = hash(seed, k + 20) < 0.5 and 1 or -1
		local style = pick({ "jogger", "jogger", "pedestrian", "kid" }, seed, k)
		local p0 = at(offset)
		local npc = ParkKit.Person(m, style, seed * 13 + k, CFrame.new(p0), "none", true)
		if npc then
			local side = (k % 2 == 0) and 0.9 or -0.9
			actor(m, p0, function(t: number)
				local s = offset + dir * t * speed
				local p, d = at(s)
				d *= dir
				local right = Vector3.new(-d.Z, 0, d.X)
				local pos = p + right * side
				local NPC = ParkKit.NPC()
				local cf = CFrame.lookAt(pos, pos + d)
				if NPC and NPC.Place then
					NPC.Place(npc, cf)
				else
					npc:PivotTo(cf)
				end
				ParkKit.Animate(npc, "p11_run", t * speed / 9)
			end, seed + k)
		end
	end
end

----------------------------------------------------------------------
-- Mobilier de parc
----------------------------------------------------------------------

local function gravel(m: Instance, F: CFrame, x0: number, x1: number, z0: number, z1: number, y: number?)
	local p = Box(m, "Gravel", F, x0, x1, (y or 0) - 0.12, (y or 0) + 0.06, z0, z1, GRAVEL, M.Pebble)
	p.CastShadow = false
	return p
end

-- Rosier : touffe de feuillage + fleurs
local function roseBush(m: Instance, F: CFrame, x: number, z: number, seed: number, h: number?)
	local H = h or 2.4
	Egg(m, "RoseLeaves", F * CFrame.new(x, H * 0.5, z), Vector3.new(2.2, H, 2.2), rgb(58, 112, 54), M.Grass)
	local c = pick(ROSES, seed, 1)
	for k = 0, 6 do
		local a = k / 7 * TAU + hash(seed, k)
		local r = 0.7 + hash(seed, k + 9) * 0.25
		ParkKit.Ball(m, "Rose", (F * CFrame.new(x + cos(a) * r, H * (0.55 + hash(seed, k + 3) * 0.4), z + sin(a) * r)).Position, 0.42, c:Lerp(WHITE, hash(seed, k + 5) * 0.15), M.SmoothPlastic)
	end
end

-- Haie de buis taillée (bordure basse), le long de x
local function boxHedge(m: Instance, F: CFrame, x0: number, x1: number, z: number, h: number?)
	local H = h or 1.4
	Box(m, "BoxHedge", F, x0, x1, 0, H, z - 0.55, z + 0.55, BOX_GREEN, M.Grass, true)
	Box(m, "BoxHedgeTop", F, x0 + 0.08, x1 - 0.08, H, H + 0.12, z - 0.45, z + 0.45, BOX_GREEN:Lerp(rgb(90, 150, 70), 0.3), M.Grass)
end

-- Arche fleurie (fer forgé + rosiers grimpants) au-dessus d'une allée
local function roseArch(m: Instance, F: CFrame, w: number, seed: number)
	local H = 9
	for _, sx in ipairs({ -1, 1 }) do
		Column(m, "ArchPost", F, sx * w / 2, 0, 0, H - 1.2, 0.3, IRON, M.Metal, true)
	end
	for k = 0, 8 do
		local a0, a1 = k / 9 * math.pi, (k + 1) / 9 * math.pi
		local p0 = F * Vector3.new(-cos(a0) * w / 2, H - 1.2 + sin(a0) * 1.6, 0)
		local p1 = F * Vector3.new(-cos(a1) * w / 2, H - 1.2 + sin(a1) * 1.6, 0)
		Rod(m, "ArchBow", p0, p1, 0.24, IRON, M.Metal)
		local mid = (p0 + p1) / 2
		Egg(m, "ArchLeaves", CFrame.new(mid) * ANG(hash(seed, k) * 3, k, 0), Vector3.new(1.1, 0.8, 1.0), rgb(58, 112, 54):Lerp(rgb(86, 140, 64), hash(seed, k + 2)), M.Grass)
		for j = 0, 1 do
			local c = pick(ROSES, seed, k * 2 + j)
			local off = Vector3.new(hash(seed, k * 3 + j) - 0.5, 0.35 - j * 0.6, (j - 0.5) * 0.9)
			ParkKit.Ball(m, "ArchRose", mid + off, 0.4, c, M.SmoothPlastic)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 4 do
			local p = F * CFrame.new(sx * w / 2 + (hash(seed, k + sx) - 0.5) * 0.3, 0.8 + k * 1.55, (hash(seed, k + 7) - 0.5) * 0.4)
			Egg(m, "ArchClimb", p, Vector3.new(0.9, 1.3, 0.9), rgb(58, 112, 54):Lerp(rgb(86, 140, 64), hash(seed, k + 9)), M.Grass)
			if k % 2 == 1 then
				ParkKit.Ball(m, "ArchRose", (p * CFrame.new(0.35 * sx, 0.2, -0.35)).Position, 0.38, pick(ROSES, seed, k + 5), M.SmoothPlastic)
			end
		end
	end
end

----------------------------------------------------------------------
-- 🌹 ROSERAIE (40 x 40) : croix d'allées, 4 parterres, fontaine au centre
----------------------------------------------------------------------

local function buildRoseGarden(m: Model, F: CFrame, seed: number): any
	ensureAnims()
	local S = 19
	-- allées en croix + tour
	gravel(m, F, -S, S, -2.5, 2.5)
	gravel(m, F, -2.5, 2.5, -S, -2.5)
	gravel(m, F, -2.5, 2.5, 2.5, S)
	Ring(m, "GardenRing", F, 8.2, 2.6, -0.14, 0.1, 24, GRAVEL, M.Pebble)
	-- 4 parterres (quarts) : bordure de buis, rosiers, motif central
	for qx = -1, 1, 2 do
		for qz = -1, 1, 2 do
			local Q = F * CFrame.new(qx * 12.8, 0, qz * 12.8)
			local half = 5.4
			boxHedge(m, Q, -half, half, -half)
			boxHedge(m, Q, -half, half, half)
			boxHedge(m, Q * ANG(0, math.pi / 2, 0), -half + 1.1, half - 1.1, -half)
			boxHedge(m, Q * ANG(0, math.pi / 2, 0), -half + 1.1, half - 1.1, half)
			local soil = Box(m, "BedSoil", Q, -half + 0.55, half - 0.55, -0.1, 0.18, -half + 0.55, half - 0.55, rgb(98, 70, 50), M.Ground)
			soil.CastShadow = false
			local k = 0
			for ix = -1, 1 do
				for iz = -1, 1 do
					if not (ix == 0 and iz == 0) then
						k += 1
						roseBush(m, Q, ix * 2.9, iz * 2.9, seed * 11 + qx * 7 + qz * 3 + k, 2.2 + hash(seed, k) * 0.6)
					end
				end
			end
			-- if central : topiaire en boule sur tige
			Column(m, "TopiaryStem", Q, 0, 0, 0, 3.2, 0.3, rgb(100, 72, 50), M.Wood)
			ParkKit.Ball(m, "Topiary", (Q * CFrame.new(0, 4.2, 0)).Position, 2.6, BOX_GREEN, M.Grass)
		end
	end
	-- fontaine au centre
	local fx = FountainKit.Build(m, F, "Basin", seed)
	-- arches fleuries aux 4 entrées
	for k = 0, 3 do
		roseArch(m, F * ANG(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -S + 1), 6, seed + k)
	end
	-- 4 bancs face à la fontaine (sur le tour), PNJ ou places libres
	benchesFor(m, F, "RoseGarden", seed)
	actor(m, F.Position, function(t: number)
		FountainKit.Step(fx, t)
	end, seed)
	return { Fountain = fx }
end

----------------------------------------------------------------------
-- 🐕 PARC À CHIENS (36 x 30) : enclos, agility, lancers de balle
----------------------------------------------------------------------

local function buildDogPark(m: Model, F: CFrame, seed: number): any
	ensureAnims()
	local W, D = 34, 28
	local ground = Box(m, "DogTurf", F, -W / 2, W / 2, -0.1, 0.1, -D / 2, D / 2, rgb(120, 156, 84), M.Grass)
	ground.CastShadow = false
	local wood = rgb(142, 102, 66)
	-- clôture bois (lisses + poteaux), double portillon côté -Z
	local H = 3.8
	local function fenceSide(a: Vector3, b: Vector3, gap: boolean)
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local n = math.max(1, math.floor(len / 4))
		for i = 0, n do
			local p = a + dir * (len * i / n)
			if not (gap and abs((i / n) - 0.5) < 0.12) then
				Column(m, "DogPost", CFrame.new(F * p), 0, 0, 0, H, 0.45, wood:Lerp(rgb(0, 0, 0), 0.15), M.Wood, true)
			end
		end
		for _, y in ipairs({ 1.2, 2.4, H - 0.3 }) do
			if gap then
				local mid = (a + b) / 2
				ParkKit.Beam(m, "DogRail", F * (a + Vector3.new(0, y, 0)), F * (mid - dir * 2.2 + Vector3.new(0, y, 0)), 0.18, 0.4, wood, M.Wood, true)
				ParkKit.Beam(m, "DogRail", F * (mid + dir * 2.2 + Vector3.new(0, y, 0)), F * (b + Vector3.new(0, y, 0)), 0.18, 0.4, wood, M.Wood, true)
			else
				ParkKit.Beam(m, "DogRail", F * (a + Vector3.new(0, y, 0)), F * (b + Vector3.new(0, y, 0)), 0.18, 0.4, wood, M.Wood, true)
			end
		end
	end
	fenceSide(Vector3.new(-W / 2, 0, -D / 2), Vector3.new(W / 2, 0, -D / 2), true)
	fenceSide(Vector3.new(W / 2, 0, -D / 2), Vector3.new(W / 2, 0, D / 2), false)
	fenceSide(Vector3.new(W / 2, 0, D / 2), Vector3.new(-W / 2, 0, D / 2), false)
	fenceSide(Vector3.new(-W / 2, 0, D / 2), Vector3.new(-W / 2, 0, -D / 2), false)
	-- sas d'entrée (2e portillon) + panneau
	local sign = Box(m, "DogSign", F, -2, 2, 4.2, 5.6, -D / 2 - 0.25, -D / 2 - 0.1, rgb(250, 244, 230), M.SmoothPlastic)
	ParkKit.Text(sign, Enum.NormalId.Front, "🐕 " .. Locale.T("Dog park"), rgb(60, 40, 30), nil, Enum.Font.FredokaOne)
	for _, sx in ipairs({ -1, 1 }) do
		Column(m, "SignPost", F, sx * 1.8, -D / 2 - 0.18, 0, 5.6, 0.25, wood, M.Wood)
	end
	-- agility : haies, cerceau, rampe en A, tunnel, slalom
	local A = F * CFrame.new(6, 0, 4)
	for i = 0, 2 do
		local hx = -5 + i * 5
		for _, sz in ipairs({ -1.6, 1.6 }) do
			Column(m, "HurdlePost", A, hx, sz, 0, 2.6, 0.22, WHITE, M.Plastic)
		end
		Rod(m, "HurdleBar", (A * CFrame.new(hx, 1.4, -1.6)).Position, (A * CFrame.new(hx, 1.4, 1.6)).Position, 0.16, i % 2 == 0 and rgb(230, 60, 50) or rgb(250, 200, 40), M.Plastic)
	end
	local tunnel = A * CFrame.new(0, 0, 7)
	for k = 0, 5 do
		local ring = Part(m, "TunnelRing", Vector3.new(1.0, 2.4, 2.4), tunnel * CFrame.new(-3 + k * 1.2, 1.2, 0), k % 2 == 0 and rgb(60, 120, 220) or rgb(240, 220, 60), M.Fabric, "Cyl")
		ring.Transparency = 0
	end
	local ramp = A * CFrame.new(-4, 0, -7)
	ParkKit.Wedge(m, "ARamp", Vector3.new(2.6, 2.4, 4.2), ramp * CFrame.new(0, 1.2, -2.1) * ANG(0, math.pi, 0), rgb(214, 160, 70), M.WoodPlanks)
	ParkKit.Wedge(m, "ARamp", Vector3.new(2.6, 2.4, 4.2), ramp * CFrame.new(0, 1.2, 2.1), rgb(214, 160, 70), M.WoodPlanks)
	for k = 0, 5 do
		Column(m, "SlalomPole", F, -12 + k * 1.8, -6, 0, 3.2, 0.2, k % 2 == 0 and rgb(230, 60, 50) or WHITE, M.Plastic)
	end
	-- bols d'eau + fontaine pour chiens, bancs des maîtres
	Column(m, "DogFountain", F, -14, 10, 0, 3.2, 0.8, rgb(50, 90, 70), M.Metal, true)
	Column(m, "DogBowl", F, -14, 11.2, 0.1, 0.5, 1.4, rgb(180, 184, 190), M.Metal)
	local water = Column(m, "DogBowlWater", F, -14, 11.2, 0.3, 0.45, 1.15, rgb(150, 206, 232), M.Glass)
	water.Transparency = 0.3
	benchesFor(m, F, "DogPark", seed)
	-- maîtres qui lancent la balle + chiens
	local NPC = ParkKit.NPC()
	local owners = {}
	local spots = { Vector3.new(-8, 0, -4), Vector3.new(10, 0, -9) }
	for i, sp in ipairs(spots) do
		local owner = ParkKit.Person(m, pick({ "pedestrian", "jogger", "elder", "shopper" }, seed, i + 30), seed * 17 + i, F * CFrame.new(sp), "none", true)
		local dog = nil
		if NPC and type(NPC.BuildDog) == "function" then
			local ok, d = pcall(NPC.BuildDog, seed * 19 + i)
			if ok and d then
				dog = d
				d.Parent = m
				d:PivotTo(F * CFrame.new(sp + Vector3.new(1.5, 0, 0)))
			end
		end
		local ball = Part(m, "DogBall", Vector3.new(0.45, 0.45, 0.45), F, i == 1 and rgb(214, 236, 60) or rgb(240, 80, 60), M.Rubber, "Ball")
		table.insert(owners, { Owner = owner, Dog = dog, Ball = ball, Spot = sp, Seed = seed * 3 + i })
	end
	-- un 3e chien qui fait le tour de l'agility tout seul (trot)
	local roamer = nil
	if NPC and type(NPC.BuildDog) == "function" then
		local ok, d = pcall(NPC.BuildDog, seed * 23 + 5)
		if ok and d then
			roamer = d
			d.Parent = m
		end
	end
	local THROW = 6.0
	actor(m, F.Position, function(t: number, dt: number)
		for _, o in ipairs(owners) do
			local c = (t + hash(o.Seed, 1) * THROW) % THROW
			local ang = hash(o.Seed, math.floor((t + hash(o.Seed, 1) * THROW) / THROW)) * 1.6 - 0.8
			local dir = Vector3.new(sin(ang), 0, -cos(ang))
			if o.Spot.Z < -2 then
				dir = Vector3.new(sin(ang), 0, cos(ang))
			end
			local land = o.Spot + dir * 11
			-- PNJ : armé / lance (0 -> 0,8), attend, reçoit la balle
			local face = CFrame.lookAt(F * o.Spot, F * (o.Spot + dir))
			if o.Owner then
				if NPC and NPC.Place then
					NPC.Place(o.Owner, face)
				end
				if c < 0.9 then
					ParkKit.Animate(o.Owner, "p11_throw", c / 0.9)
				else
					ParkKit.Animate(o.Owner, c > THROW - 0.8 and "p11_pass" or "idle", c > THROW - 0.8 and (c - (THROW - 0.8)) / 0.8 or t)
				end
			end
			-- balle : main -> cloche -> rebonds -> gueule du chien -> retour
			local ballP: Vector3
			local hand = o.Owner and ParkKit.Hand(o.Owner, "R")
			local handP = hand and hand.Position or (F * (o.Spot + Vector3.new(0, 3.5, 0)))
			local fetchT, backT = 2.6, THROW - 0.8
			if c < 0.55 then
				ballP = handP
			elseif c < 1.7 then
				local u = (c - 0.55) / 1.15
				local a = handP
				local b = F * (land + Vector3.new(0, 0.22, 0))
				ballP = a:Lerp(b, u) + Vector3.new(0, 4 * 3.5 * u * (1 - u), 0)
			elseif c < fetchT then
				local u = (c - 1.7) / (fetchT - 1.7)
				ballP = F * (land + dir * u * 2 + Vector3.new(0, 0.22 + abs(sin(u * math.pi * 2)) * (1 - u) * 1.2, 0))
			else
				ballP = nil :: any
			end
			-- chien : attend, s'élance quand la balle part, la rattrape, la rapporte
			local dogPos: Vector3
			local dogLook: Vector3
			local speed = 0
			local sit = o.Spot + Vector3.new(1.6, 0, 0)
			local grab = land + dir * 2
			if c < 0.7 then
				dogPos, dogLook = sit, sit + dir
			elseif c < fetchT then
				local u = smooth((c - 0.7) / (fetchT - 0.7))
				dogPos = sit:Lerp(grab, u)
				dogLook = grab
				speed = (grab - sit).Magnitude / (fetchT - 0.7) * 1.4
			elseif c < backT then
				local u = smooth((c - fetchT) / (backT - fetchT))
				dogPos = grab:Lerp(sit, u)
				dogLook = sit
				speed = (grab - sit).Magnitude / (backT - fetchT) * 1.4
			else
				dogPos, dogLook = sit, o.Spot
			end
			local dcf = CFrame.lookAt(F * dogPos, F * Vector3.new(dogLook.X, dogPos.Y, dogLook.Z))
			if (dogLook - dogPos).Magnitude < 0.05 then
				dcf = F * CFrame.new(dogPos)
			end
			if o.Dog and NPC and NPC.AnimateDog then
				pcall(NPC.AnimateDog, o.Dog, dcf, t, speed)
			end
			if not ballP then
				-- dans la gueule
				local head = o.Dog and NPC and NPC.DogCollar and NPC.DogCollar(o.Dog)
				ballP = head and (head + dcf.LookVector * 0.7 + Vector3.new(0, 0.1, 0)) or (dcf * CFrame.new(0, 1.2, -1.2)).Position
				if c >= backT then
					ballP = handP:Lerp(ballP, 1 - smooth((c - backT) / 0.5))
				end
			end
			o.Ball.CFrame = CFrame.new(ballP)
		end
		-- chien du tour d'agility
		if roamer and NPC and NPC.AnimateDog then
			local r = 9
			local a = t * 0.55
			local center = Vector3.new(4, 0, 4)
			local p = center + Vector3.new(cos(a) * r, 0, sin(a) * r * 0.75)
			local nx = center + Vector3.new(cos(a + 0.1) * r, 0, sin(a + 0.1) * r * 0.75)
			pcall(NPC.AnimateDog, roamer, CFrame.lookAt(F * p, F * nx), t, 5)
		end
		local _ = dt
	end, seed)
	return { Owners = owners }
end

----------------------------------------------------------------------
-- 🎺 KIOSQUE À MUSIQUE (octogone, Ø 18)
----------------------------------------------------------------------

local function buildBandstand(m: Model, F: CFrame, seed: number): any
	ensureAnims()
	local R = 8.5
	local floorY = 3.0
	local green = rgb(40, 84, 66)
	local cream = rgb(246, 238, 220)
	local roofC = pick({ rgb(70, 110, 96), rgb(150, 70, 60), rgb(60, 80, 120) }, seed, 2)
	-- socle de pierre octogonal + marches côté -Z
	Ring(m, "BandBase", F, R - 0.6, 1.2, 0, floorY - 0.3, 8, STONE, M.Limestone, true)
	Column(m, "BandFill", F, 0, 0, 0, floorY - 0.3, (R - 1) * 2, STONE, M.Limestone, true)
	Ring(m, "BandCornice", F, R - 0.4, 1.6, floorY - 0.3, floorY, 8, rgb(236, 230, 218), M.Limestone, true)
	local floor = Column(m, "BandFloor", F, 0, 0, floorY - 0.32, floorY + 0.06, (R - 0.5) * 2, rgb(170, 120, 80), M.WoodPlanks, true)
	floor.CastShadow = true
	for i = 0, 3 do
		local y = (i + 1) * (floorY - 0.06) / 4
		Box(m, "BandStep", F, -2.6, 2.6, 0, y, -R - 3.2 + i * 0.85, -R + 0.4, STONE, M.Limestone, true)
	end
	-- colonnes de fonte (8), lambrequins, garde-corps
	local postR = R - 1.0
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * TAU
		local x, z = cos(a) * postR, sin(a) * postR
		Column(m, "BandColumn", F, x, z, floorY, floorY + 8.4, 0.42, green, M.Metal, true)
		Column(m, "BandCapital", F, x, z, floorY + 8.1, floorY + 8.5, 0.8, green, M.Metal)
		Column(m, "BandColBase", F, x, z, floorY, floorY + 0.5, 0.7, green, M.Metal)
		-- garde-corps (sauf à l'entrée)
		local b = (k + 1.5) / 8 * TAU
		local p0 = F * Vector3.new(cos(a) * postR, floorY, sin(a) * postR)
		local p1 = F * Vector3.new(cos(b) * postR, floorY, sin(b) * postR)
		local mid = (p0 + p1) / 2
		local isEntry = abs(((((k + 1) / 8 * TAU) - (math.pi * 1.5)) + math.pi) % TAU - math.pi) < 0.3
		if not isEntry then
			ParkKit.Beam(m, "BandRail", p0 + Vector3.new(0, ParkKit.RAIL, 0), p1 + Vector3.new(0, ParkKit.RAIL, 0), 0.25, 0.25, green, M.Metal, true)
			ParkKit.Beam(m, "BandRailLow", p0 + Vector3.new(0, 0.4, 0), p1 + Vector3.new(0, 0.4, 0), 0.18, 0.18, green, M.Metal)
			for j = 1, 5 do
				local q = p0:Lerp(p1, j / 6)
				Rod(m, "BandBaluster", q + Vector3.new(0, 0.4, 0), q + Vector3.new(0, ParkKit.RAIL, 0), 0.12, green, M.Metal)
			end
		end
		-- lambrequin (frise festonnée) entre les colonnes
		ParkKit.Beam(m, "BandFrieze", p0 + Vector3.new(0, 8.0, 0), p1 + Vector3.new(0, 8.0, 0), 0.15, 0.8, cream, M.Wood)
		for j = 0, 3 do
			local q = p0:Lerp(p1, (j + 0.5) / 4) + Vector3.new(0, 7.45, 0)
			Egg(m, "BandScallop", CFrame.lookAt(q, q + (mid - F.Position) * Vector3.new(1, 0, 1)), Vector3.new(0.9, 0.55, 0.15), cream, M.Wood)
		end
	end
	-- toit en pavillon (8 pans) + lanternon + épi
	local top = floorY + 8.5
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * TAU
		local b = (k + 1.5) / 8 * TAU
		local e0 = F * Vector3.new(cos(a) * (R + 0.6), top, sin(a) * (R + 0.6))
		local e1 = F * Vector3.new(cos(b) * (R + 0.6), top, sin(b) * (R + 0.6))
		local apex = F * Vector3.new(0, top + 4.6, 0)
		for _, w in ipairs(ParkKit.Triangle(m, "BandRoof", e0, e1, apex, 0.2, roofC, M.Metal)) do
			w.CastShadow = true
		end
		ParkKit.Beam(m, "BandRoofRib", e0 + Vector3.new(0, 0.12, 0), apex + Vector3.new(0, 0.12, 0), 0.22, 0.22, cream, M.Metal)
		ParkKit.Beam(m, "BandEave", e0, e1, 0.3, 0.3, cream, M.Wood)
	end
	Column(m, "BandLantern", F, 0, 0, top + 4.2, top + 5.6, 1.6, cream, M.Wood)
	Egg(m, "BandDome", F * CFrame.new(0, top + 5.8, 0), Vector3.new(2, 1.2, 2), roofC, M.Metal)
	Column(m, "BandSpire", F, 0, 0, top + 6.1, top + 7.6, 0.18, rgb(214, 172, 80), M.Metal)
	ParkKit.Ball(m, "BandFinial", (F * CFrame.new(0, top + 7.7, 0)).Position, 0.45, rgb(214, 172, 80), M.Metal)
	-- petit orchestre : trompette, tuba, tambour (pupitres)
	local band = {}
	local FY = F * CFrame.new(0, floorY, 0)
	local roles = { { "trumpet", -2.6, 1.0 }, { "drum", 0, 2.4 }, { "trumpet", 2.6, 1.0 } }
	for i, r in ipairs(roles) do
		local cf = FY * CFrame.new(r[2], 0, r[3])
		local look = CFrame.lookAt(cf.Position, (FY * CFrame.new(0, 0, -R)).Position)
		local npc = ParkKit.Person(m, pick({ "pedestrian", "elder", "worker" }, seed, i), seed * 29 + i, look, "none", false)
		local inst: BasePart? = nil
		if r[1] == "trumpet" then
			inst = Part(m, "Trumpet", Vector3.new(1.3, 0.22, 0.22), look, rgb(222, 180, 70), M.Metal, "Cyl")
		else
			local drum = Column(m, "Drum", look * CFrame.new(0, 0, -1.1), 0, 0, 2.2, 3.4, 1.6, rgb(200, 40, 50), M.SmoothPlastic)
			Column(m, "DrumSkin", look * CFrame.new(0, 0, -1.1), 0, 0, 3.4, 3.45, 1.5, WHITE, M.Fabric)
			local _ = drum
		end
		-- pupitre
		Column(m, "MusicStand", look * CFrame.new(0, 0, -2.0), 0, 0, 0, 3.6, 0.1, IRON, M.Metal)
		Part(m, "MusicSheet", Vector3.new(1.2, 0.9, 0.06), look * CFrame.new(0, 3.9, -2.0) * ANG(math.rad(-25), 0, 0), WHITE, M.SmoothPlastic)
		table.insert(band, { Npc = npc, Role = r[1], Inst = inst })
	end
	-- bancs du public devant
	benchesFor(m, F, "Bandstand", seed)
	actor(m, F.Position, function(t: number)
		for i, b in ipairs(band) do
			if b.Npc then
				ParkKit.Animate(b.Npc, b.Role == "trumpet" and "p11_trumpet" or "p11_drum", t + i)
				if b.Inst then
					local l, r = ParkKit.Hand(b.Npc, "L"), ParkKit.Hand(b.Npc, "R")
					local root = b.Npc.PrimaryPart
					if l and r and root then
						local mid = (l.Position + r.Position) / 2
						b.Inst.CFrame = CFrame.lookAt(mid, mid + root.CFrame.LookVector) * ANG(0, math.rad(90), 0) * CFrame.new(-0.3, 0, 0)
					end
				end
			end
		end
	end, seed)
	return { Band = band }
end

----------------------------------------------------------------------
-- 🧺 PIQUE-NIQUE dans l'herbe (2 nappes, familles) et TABLES
----------------------------------------------------------------------

local function blanket(m: Instance, B: CFrame, seed: number)
	local colors = pick({ { rgb(214, 50, 60), WHITE }, { rgb(60, 110, 200), WHITE }, { rgb(80, 160, 90), rgb(250, 240, 210) } }, seed, 1)
	Box(m, "Blanket", B, -2.8, 2.8, 0.02, 0.08, -2.2, 2.2, colors[2], M.Fabric)
	for i = 0, 3 do
		local x = -2.8 + i * 1.4 + 0.35
		local stripe = Box(m, "BlanketCheck", B, x, x + 0.7, 0.08, 0.11, -2.18, 2.18, colors[1], M.Fabric)
		stripe.Transparency = 0.15
		local z = -2.2 + i * 1.1 + 0.27
		local s2 = Box(m, "BlanketCheck", B, -2.78, 2.78, 0.14, 0.16, z, z + 0.55, colors[1], M.Fabric)
		s2.Transparency = 0.35
	end
	-- panier en osier, assiettes, bouteille, fruits
	Box(m, "Basket", B, 1.2, 2.5, 0.12, 1.1, -1.9, -1.1, rgb(176, 130, 70), M.Wood)
	Rod(m, "BasketHandle", (B * CFrame.new(1.25, 1.1, -1.5)).Position, (B * CFrame.new(2.45, 1.1, -1.5)).Position, 0.1, rgb(140, 100, 56), M.Wood)
	for k = 0, 2 do
		Column(m, "Plate", B, -1.4 + k * 1.3, 0.3 + (k % 2) * 0.4, 0.12, 0.18, 0.95, WHITE, M.SmoothPlastic)
		ParkKit.Ball(m, "Fruit", (B * CFrame.new(-1.4 + k * 1.3, 0.32, 0.3 + (k % 2) * 0.4)).Position, 0.38, pick({ rgb(220, 40, 40), rgb(250, 180, 40), rgb(120, 190, 60) }, seed, k), M.SmoothPlastic)
	end
	Column(m, "Bottle", B, 0.2, -1.4, 0.12, 1.3, 0.36, rgb(60, 140, 90), M.Glass)
end

local function buildPicnic(m: Model, F: CFrame, seed: number): any
	ensureAnims()
	local people = {}
	for k = 0, 1 do
		local B = F * CFrame.new(-6 + k * 12, 0.05, hash(seed, k) * 3 - 1.5) * ANG(0, hash(seed, k + 4) * 1.2 - 0.6, 0)
		blanket(m, B, seed + k)
		-- 2 ou 3 personnes assises dans l'herbe autour (assise à 0,35 : genoux relevés)
		local n = 2 + (hash(seed, k + 8) < 0.5 and 1 or 0)
		for i = 1, n do
			local a = (i / n) * TAU + hash(seed, i + k * 5)
			local seat = B * CFrame.new(cos(a) * 3.4, 0.35, sin(a) * 2.7)
			local look = CFrame.lookAt(seat.Position, (B * CFrame.new(0, 0.35, 0)).Position)
			local npc = ParkScenes.Sitter(m, look, F.Position.Y, seed * 41 + k * 5 + i, pick({ "chat", "eat", "chat", "phone" }, seed, i + k * 3))
			table.insert(people, npc)
		end
	end
	-- un enfant qui joue au cerf-volant ? (ballon qui roule entre deux enfants)
	return { People = people }
end

-- Table de pique-nique (dessus 3,1 ; bancs 1,85), repère au sol, X = longueur
function ParkScenes.PicnicTable(m: Instance, T: CFrame, seed: number, sitters: number?)
	local wood = rgb(166, 120, 78)
	local L = 7
	Box(m, "PTTop", T, -L / 2, L / 2, ParkKit.TABLE - 0.25, ParkKit.TABLE, -1.4, 1.4, wood, M.WoodPlanks, true)
	for _, sz in ipairs({ -1, 1 }) do
		Box(m, "PTBench", T, -L / 2, L / 2, ParkKit.SEAT - 0.22, ParkKit.SEAT, sz * 2.4 - 0.6, sz * 2.4 + 0.6, wood, M.WoodPlanks, true)
	end
	for _, sx in ipairs({ -L / 2 + 0.8, L / 2 - 0.8 }) do
		-- pieds en A (2 planches croisées)
		for _, sz in ipairs({ -1, 1 }) do
			ParkKit.Beam(m, "PTLeg", (T * CFrame.new(sx, 0, sz * 2.6)).Position, (T * CFrame.new(sx, ParkKit.TABLE - 0.25, sz * 0.5)).Position, 0.3, 0.5, wood:Lerp(rgb(0, 0, 0), 0.1), M.Wood, true)
		end
		Box(m, "PTBrace", T, sx - 0.15, sx + 0.15, ParkKit.SEAT - 0.5, ParkKit.SEAT - 0.22, -3.0, 3.0, wood:Lerp(rgb(0, 0, 0), 0.1), M.Wood)
	end
	-- nappe + panier
	local cloth = Box(m, "PTCloth", T, -1.5, 1.5, ParkKit.TABLE, ParkKit.TABLE + 0.03, -1.45, 1.45, pick({ rgb(214, 60, 70), rgb(70, 120, 210) }, seed, 1), M.Fabric)
	cloth.CastShadow = false
	for k = 1, (sitters or 0) do
		local sz = k % 2 == 0 and 1 or -1
		local x = (k <= 2) and -1.4 or 1.4
		local seat = T * CFrame.new(x, ParkKit.SEAT, sz * 2.4) * ANG(0, sz > 0 and 0 or math.pi, 0)
		ParkScenes.Sitter(m, seat, T.Position.Y, seed * 7 + k, pick({ "eat", "chat", "eat", "phone" }, seed, k))
	end
end

local function buildPicnicTables(m: Model, F: CFrame, seed: number): any
	ensureAnims()
	for k, T in ipairs(ParkLayout.Tables("PicnicTables", seed)) do
		ParkScenes.PicnicTable(m, F * T, seed + k, 0)
	end
	for i, st in ipairs(ParkLayout.Seats("PicnicTables", seed)) do
		if st.Npc then
			ParkScenes.Sitter(m, F * st.CF, F.Position.Y, seed * 17 + i, st.Activity)
		end
	end
	return {}
end

-- Rangée de bancs le long d'une allée (2 bancs, poubelle, lampadaire)
local function buildBenchRow(m: Model, F: CFrame, seed: number): any
	ensureAnims()
	benchesFor(m, F, "BenchRow", seed)
	ParkKit.Bin(m, F * CFrame.new(0, 0, 0.6))
	ParkKit.Lamp(m, F * CFrame.new(8.5, 0, 0.8))
	return {}
end

-- ⛲ PLACE DE LA FONTAINE (Ø 44) : grande fontaine à vasques, dallage en
-- cercles, 8 bancs tournés vers l'eau, lampadaires, joggeurs autour
local function buildFountainSquare(m: Model, F: CFrame, seed: number): any
	ensureAnims()
	local paving = rgb(214, 204, 188)
	Column(m, "SquarePaving", F, 0, 0, -0.1, 0.06, 40, paving, M.Pavement)
	Ring(m, "SquareBand", F, 15.2, 1.2, 0.06, 0.09, 32, rgb(150, 140, 130), M.Granite)
	Ring(m, "SquareEdge", F, 19.6, 0.8, 0.06, 0.2, 40, rgb(170, 160, 150), M.Granite)
	local fx = FountainKit.Build(m, F, "Tiered", seed)
	benchesFor(m, F, "FountainSquare", seed)
	for k = 0, 3 do
		local a = k / 4 * TAU
		ParkKit.Lamp(m, F * CFrame.new(math.cos(a) * 18.4, 0.06, math.sin(a) * 18.4))
	end
	-- joggeurs sur l'anneau extérieur
	local loop = {}
	for k = 0, 15 do
		local a = k / 16 * TAU
		table.insert(loop, (F * CFrame.new(math.cos(a) * 22.5, 0, math.sin(a) * 22.5)).Position)
	end
	ParkScenes.JogLoop(m, loop, seed, 2)
	actor(m, F.Position, function(t: number)
		FountainKit.Step(fx, t)
	end, seed)
	return { Fountain = fx }
end

-- 🏋️ Agrès (barre de traction, barres parallèles, banc incliné) + sportifs
local function buildFitness(m: Model, F: CFrame, seed: number): any
	ensureAnims()
	local pad = Box(m, "FitPad", F, -9, 9, -0.1, 0.12, -6, 6, rgb(70, 120, 90), M.Rubber, true)
	pad.CastShadow = false
	local steel = rgb(60, 70, 84)
	-- barre de traction (haute)
	for _, sx in ipairs({ -1.6, 1.6 }) do
		Column(m, "PullPost", F, -5 + sx, -2, 0, 8.8, 0.4, steel, M.Metal, true)
	end
	Rod(m, "PullBar", (F * CFrame.new(-6.6, 8.4, -2)).Position, (F * CFrame.new(-3.4, 8.4, -2)).Position, 0.2, rgb(200, 200, 206), M.Metal)
	-- barres parallèles
	for _, sz in ipairs({ -0.9, 0.9 }) do
		for _, x in ipairs({ 2, 6 }) do
			Column(m, "DipPost", F, x, 2 + sz, 0, 4.2, 0.3, steel, M.Metal, true)
		end
		Rod(m, "DipBar", (F * CFrame.new(2, 4.1, 2 + sz)).Position, (F * CFrame.new(6, 4.1, 2 + sz)).Position, 0.2, rgb(200, 200, 206), M.Metal)
	end
	-- banc incliné
	ParkKit.Wedge(m, "SitupBench", Vector3.new(1.6, 1.6, 5), F * CFrame.new(4, 0.8, -3.5) * ANG(0, math.pi / 2, 0), rgb(40, 40, 46), M.Rubber, true)
	-- sportif à la barre (pendu : pieds au-dessus du sol) + un qui s'étire
	local hang = ParkKit.Person(m, "jogger", seed * 3 + 1, F * CFrame.new(-5, 2.1, -2) * ANG(0, math.pi, 0), "none", false)
	local str = ParkKit.Person(m, pick({ "jogger", "pedestrian" }, seed, 2), seed * 3 + 2, F * CFrame.new(5, 0.12, -0.5) * ANG(0, 2.5, 0), "none", true)
	actor(m, F.Position, function(t: number)
		if hang then
			local c = (sin(t * 2.2) + 1) / 2
			local NPC = ParkKit.NPC()
			-- (bras tendus : mains à ~7 au-dessus du pivot ; fléchis : ~5,6)
			local cf = F * CFrame.new(-5, 1.4 + c * 1.4, -2) * ANG(0, math.pi, 0)
			if NPC and NPC.Place then
				NPC.Place(hang, cf)
			end
			ParkKit.Animate(hang, "p11_pullup", t)
		end
		if str then
			ParkKit.Animate(str, "p11_stretch", t + 2)
		end
	end, seed)
	return {}
end

ParkScenes.EnsureAnims = ensureAnims

ParkScenes.BUILDERS = {
	RoseGarden = buildRoseGarden,
	DogPark = buildDogPark,
	Bandstand = buildBandstand,
	Picnic = buildPicnic,
	PicnicTables = buildPicnicTables,
	BenchRow = buildBenchRow,
	FountainSquare = buildFountainSquare,
	Fitness = buildFitness,
}

return ParkScenes
