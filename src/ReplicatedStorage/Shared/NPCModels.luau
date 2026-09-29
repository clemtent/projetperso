--[[
	NPCModels (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > NPCModels

	🧍 Personnages non joueurs de Dopamine Town (v9.8, CITY98), partagés par
	le serveur ET le client (construction pure d'Instances, aucun service) :
	caissier·ère, boulanger·ère, client·e, vendeur·se, passant·e, joggeur·se,
	enfant, personne âgée, ouvrier·ère. Style "réaliste stylisé" :
	  - tête ovale (peau de 8 teintes réalistes), yeux avec reflet, sourcils,
	    nez, bouche, oreilles, 7 coiffures (courte, longue, chignon, queue de
	    cheval, bouclée, rasée, chauve) ;
	  - cou, buste (chemise / polo / veste), épaules arrondies, bras en deux
	    segments (coude) + mains, bassin, cuisses + tibias (genou), chaussures ;
	  - jupe, short, manches courtes ou longues selon la tenue ;
	  - accessoires de métier : visière + badge (caisse), toque + tablier
	    (boulangerie), veste + cravate + tablette (vente), gilet fluo +
	    casque (chantier), sac de courses, téléphone, café, canne.
	~26 à 36 pièces, toutes ANCRÉES, sans collision / requête / contact,
	sans ombre pour les petites. Aucune lumière, aucun son, aucun script.

	Repère : le PIVOT du modèle est entre les pieds, au sol ; le personnage
	regarde vers -Z (LookVector du pivot). On le place avec
	`m:PivotTo(solCF)`.

	API :
	  NPCModels.Build(style, opts?) -> Model   (non parenté)
	    opts : { Seed, Skin, Shirt, Pants, Hair, Scale, Prop, Name }
	    (même Seed -> même personne sur tous les clients)
	  NPCModels.Place(model, cf)               LA façon de DÉPLACER un PNJ qui
	    bouge (à chaque image) : ne pose que la pièce racine (pas de
	    Model:PivotTo répété, dont les erreurs d'arrondi s'accumulent
	    jusqu'à des CFrame NaN) ; Animate repose ensuite tout le reste
	  NPCModels.Animate(model, anim, t)        (CLIENT, à chaque image, léger)
	    anim : "idle" | "walk" | "talk" | "wave" | "scan" | "push" | "sit" | "type"
	    t : temps en secondes. La pose est relative au pivot ACTUEL du modèle
	    (Place / PivotTo d'abord, puis Animate). Chaque pièce est recalculée
	    à partir de la racine et de sa pose de repos (rien ne s'accumule).
	    Marche aussi sur un PNJ construit par le serveur : la pose de repos
	    est rangée en attributs.
	  NPCModels.Height, NPCModels.SitHeight, NPCModels.Styles
]]

local NPCModels = {}

local M = Enum.Material
local rgb = Color3.fromRGB

-- (échelle de base : un adulte mesure ~5,3 studs, cheveux compris)
local BASE = 0.95
NPCModels.Height = 5.3
NPCModels.SitHeight = 1.9 -- dessus d'un banc (TownKit.BENCH) : bassin posé dessus
NPCModels.Styles = { "cashier", "baker", "shopper", "salesperson", "pedestrian", "jogger", "kid", "elder", "worker" }
NPCModels.Anims = { "idle", "walk", "talk", "wave", "scan", "push", "sit", "type" }

-- Groupes articulés (attribut "NpcG" de chaque pièce)
local G_BODY, G_HEAD = 1, 2
local G_LUP, G_LLO, G_RUP, G_RLO = 3, 4, 5, 6
local G_LTH, G_LSH, G_RTH, G_RSH = 7, 8, 9, 10

-- Articulations au repos (repère du pivot, avant échelle)
local J = {
	Waist = Vector3.new(0, 2.6, 0),
	Neck = Vector3.new(0, 4.35, 0),
	ShoulderL = Vector3.new(-0.86, 4.12, 0),
	ShoulderR = Vector3.new(0.86, 4.12, 0),
	ElbowL = Vector3.new(-0.93, 3.2, 0),
	ElbowR = Vector3.new(0.93, 3.2, 0),
	HipL = Vector3.new(-0.29, 2.42, 0),
	HipR = Vector3.new(0.29, 2.42, 0),
	KneeL = Vector3.new(-0.29, 1.32, 0),
	KneeR = Vector3.new(0.29, 1.32, 0),
}

----------------------------------------------------------------------
-- Palettes réalistes
----------------------------------------------------------------------

local SKINS = {
	rgb(255, 224, 196),
	rgb(247, 210, 178),
	rgb(236, 190, 150),
	rgb(222, 170, 126),
	rgb(198, 142, 102),
	rgb(168, 112, 78),
	rgb(130, 86, 60),
	rgb(98, 64, 46),
}
local HAIRS = {
	rgb(36, 28, 26), -- noir
	rgb(70, 48, 36), -- brun foncé
	rgb(110, 74, 48), -- châtain
	rgb(160, 110, 64), -- châtain clair
	rgb(222, 184, 120), -- blond
	rgb(176, 84, 48), -- roux
	rgb(58, 40, 34),
	rgb(236, 206, 150), -- blond clair
}
local GREYS = { rgb(214, 214, 214), rgb(186, 186, 190), rgb(240, 238, 234) }
local SHIRTS = {
	rgb(66, 110, 170), -- bleu jean
	rgb(236, 236, 232), -- blanc cassé
	rgb(196, 64, 72), -- rouge
	rgb(84, 140, 110), -- vert sauge
	rgb(246, 196, 92), -- moutarde
	rgb(150, 110, 180), -- lilas
	rgb(52, 58, 72), -- anthracite
	rgb(255, 170, 190), -- rose
	rgb(120, 180, 220), -- ciel
	rgb(214, 120, 70), -- terracotta
	rgb(236, 226, 200), -- beige
	rgb(40, 110, 120), -- canard
}
local PANTS = {
	rgb(52, 70, 110), -- jean
	rgb(40, 44, 54), -- noir
	rgb(120, 104, 84), -- chino
	rgb(82, 90, 100), -- gris
	rgb(70, 90, 140), -- jean clair
	rgb(196, 176, 140), -- beige
}
local SHOES = { rgb(40, 38, 40), rgb(240, 240, 240), rgb(110, 70, 44), rgb(60, 70, 110), rgb(200, 60, 70) }
local INK = rgb(34, 28, 30)
local WHITE = rgb(250, 250, 250)

local HAIR_STYLES = { "short", "long", "bun", "pony", "curly", "buzz", "short", "long" }

----------------------------------------------------------------------
-- Hasard déterministe
----------------------------------------------------------------------

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function pick<T>(list: { T }, seed: number, salt: number): T
	return list[math.floor(hash(seed, salt) * #list) % #list + 1]
end

----------------------------------------------------------------------
-- Fabrique
----------------------------------------------------------------------

export type Opts = {
	Seed: number?,
	Skin: Color3?,
	Shirt: Color3?,
	Pants: Color3?,
	Hair: Color3?,
	Scale: number?,
	Prop: string?,
	Name: string?,
}

type Ctx = {
	Model: Model,
	S: number, -- échelle du corps
	HS: number, -- échelle en plus pour la tête (enfants : tête plus grosse)
	Count: number,
}

-- Pièce dans le groupe `g` : `cf` et `size` dans le repère de repos (avant
-- échelle). Les pièces de la tête sont agrandies autour du cou (HS).
local function add(ctx: Ctx, g: number, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local s = ctx.S
	local pos = cf.Position
	local sz = size
	if g == G_HEAD and ctx.HS ~= 1 then
		pos = J.Neck + (pos - J.Neck) * ctx.HS
		sz = size * ctx.HS
	end
	local rest = CFrame.new(pos * s) * cf.Rotation
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = (g == G_BODY and name == "Torso")
	p.Size = sz * s
	p.CFrame = rest
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Ball" then
		(p :: Part).Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		(p :: Part).Shape = Enum.PartType.Cylinder
	elseif shape == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p:SetAttribute("NpcG", g)
	p:SetAttribute("NpcRest", rest)
	p.Parent = ctx.Model
	ctx.Count += 1
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Tête : ovale, visage, oreilles, coiffure (groupe G_HEAD, centre ~ (0, 4.95))
local HEAD_Y = 4.95
local function head(ctx: Ctx, skin: Color3, hair: Color3, hairStyle: string, seed: number, female: boolean)
	local hy = HEAD_Y
	add(ctx, G_HEAD, "Head", Vector3.new(0.92, 1.1, 1), at(0, hy, 0), skin, M.SmoothPlastic, "Egg")
	-- oreilles
	for _, sx in ipairs({ -1, 1 }) do
		add(ctx, G_HEAD, "Ear", Vector3.new(0.12, 0.26, 0.2), at(sx * 0.475, hy - 0.02, 0.04), skin, M.SmoothPlastic, "Egg")
	end
	-- yeux (blanc + iris foncé devant), sourcils
	local eye = pick({ rgb(60, 40, 30), rgb(70, 110, 150), rgb(80, 110, 70), rgb(40, 30, 28) }, seed, 21)
	for _, sx in ipairs({ -1, 1 }) do
		add(ctx, G_HEAD, "EyeWhite", Vector3.new(0.19, 0.13, 0.08), at(sx * 0.19, hy + 0.04, -0.43), WHITE, M.SmoothPlastic, "Egg")
		add(ctx, G_HEAD, "Eye", Vector3.new(0.1, 0.12, 0.06), at(sx * 0.19, hy + 0.04, -0.5), eye, M.SmoothPlastic, "Egg")
		add(ctx, G_HEAD, "Brow", Vector3.new(0.22, 0.05, 0.06), at(sx * 0.2, hy + 0.2, -0.4) * CFrame.Angles(0, 0, sx * -0.12), hair, M.SmoothPlastic)
	end
	add(ctx, G_HEAD, "Nose", Vector3.new(0.13, 0.2, 0.14), at(0, hy - 0.09, -0.5), skin:Lerp(rgb(200, 120, 100), 0.12), M.SmoothPlastic, "Egg")
	add(ctx, G_HEAD, "Mouth", Vector3.new(0.22, 0.05, 0.05), at(0, hy - 0.3, -0.425), female and rgb(196, 86, 100) or rgb(150, 80, 76), M.SmoothPlastic)
	-- coiffure : chaque coque garde >= 0,03 stud d'écart avec le crâne et
	-- les autres coques, sur chaque face de sa boîte (aucun z-fighting,
	-- même avec un détecteur qui prend les ovales pour des boîtes)
	if hairStyle == "none" then
		return
	end
	if hairStyle == "bald" then
		add(ctx, G_HEAD, "HairSide", Vector3.new(1.0, 0.34, 0.9), at(0, hy - 0.02, 0.1), hair, M.SmoothPlastic, "Egg")
		return
	end
	local capH = hairStyle == "buzz" and 0.6 or 0.74
	add(ctx, G_HEAD, "Hair", Vector3.new(0.98, capH, 1.06), at(0, hy + (hairStyle == "buzz" and 0.35 or 0.3), 0.06), hair, M.SmoothPlastic, "Egg")
	if hairStyle ~= "buzz" then
		add(ctx, G_HEAD, "HairBack", Vector3.new(0.76, 0.8, 0.5), at(0, hy + 0.02, 0.39), hair, M.SmoothPlastic, "Egg")
	end
	if hairStyle == "long" then
		add(ctx, G_HEAD, "HairLong", Vector3.new(0.7, 1.15, 0.34), at(0, hy - 0.5, 0.3), hair, M.SmoothPlastic, "Egg")
		add(ctx, G_HEAD, "Fringe", Vector3.new(0.78, 0.24, 0.3), at(0.08, hy + 0.36, -0.38) * CFrame.Angles(math.rad(-20), 0, -0.15), hair, M.SmoothPlastic, "Egg")
	elseif hairStyle == "bun" then
		add(ctx, G_HEAD, "Bun", Vector3.new(0.44, 0.44, 0.44), at(0, hy + 0.58, 0.28), hair, M.SmoothPlastic, "Ball")
	elseif hairStyle == "pony" then
		add(ctx, G_HEAD, "Pony", Vector3.new(0.26, 0.9, 0.3), at(0, hy - 0.05, 0.58) * CFrame.Angles(math.rad(-18), 0, 0), hair, M.SmoothPlastic, "Egg")
		add(ctx, G_HEAD, "Tie", Vector3.new(0.2, 0.12, 0.2), at(0, hy + 0.36, 0.7), pick({ rgb(236, 72, 140), rgb(90, 140, 230), rgb(250, 250, 250) }, seed, 22), M.SmoothPlastic, "Egg")
	elseif hairStyle == "curly" then
		for i = 0, 4 do
			local a = (i / 4 - 0.5) * 2.4
			add(ctx, G_HEAD, "Curl", Vector3.new(0.42, 0.42, 0.42), at(math.sin(a) * 0.4, hy + 0.34 + math.cos(a) * 0.12, 0.12 + math.abs(math.sin(a)) * 0.05), hair, M.SmoothPlastic, "Ball")
		end
	elseif hairStyle == "short" and not female then
		add(ctx, G_HEAD, "Quiff", Vector3.new(0.7, 0.26, 0.4), at(0.05, hy + 0.5, -0.28) * CFrame.Angles(math.rad(-15), 0, 0), hair, M.SmoothPlastic, "Egg")
	end
end

-- Bras (épaule arrondie, bras, avant-bras, main) ; `longSleeve` : avant-bras vêtu
local function arm(ctx: Ctx, sx: number, sleeve: Color3, skin: Color3, longSleeve: boolean, cuff: Color3?)
	local up = sx < 0 and G_LUP or G_RUP
	local lo = sx < 0 and G_LLO or G_RLO
	local x = sx * 0.93
	add(ctx, up, "Shoulder", Vector3.new(0.56, 0.56, 0.56), at(sx * 0.84, 4.1, 0), sleeve, M.Fabric, "Ball")
	add(ctx, up, "UpperArm", Vector3.new(0.42, 1.02, 0.44), at(x, 3.66, 0), sleeve, M.Fabric)
	add(ctx, lo, "Forearm", Vector3.new(0.36, 0.98, 0.38), at(x, 2.72, 0), longSleeve and sleeve or skin, longSleeve and M.Fabric or M.SmoothPlastic)
	if cuff then
		add(ctx, lo, "Cuff", Vector3.new(0.4, 0.1, 0.42), at(x, 2.31, 0), cuff, M.SmoothPlastic)
	end
	add(ctx, lo, "Hand", Vector3.new(0.34, 0.4, 0.3), at(x, 2.06, -0.02), skin, M.SmoothPlastic, "Egg")
end

-- Jambes (cuisse, tibia, chaussure) ; `shorts` : tibia nu
local function legs(ctx: Ctx, pants: Color3, skin: Color3, shoe: Color3, shorts: boolean, bareThigh: boolean?)
	for _, sx in ipairs({ -1, 1 }) do
		local th = sx < 0 and G_LTH or G_RTH
		local sh = sx < 0 and G_LSH or G_RSH
		local x = sx * 0.29
		add(ctx, th, "Thigh", Vector3.new(0.52, 1.24, 0.58), at(x, 1.92, 0), bareThigh and skin or pants, bareThigh and M.SmoothPlastic or M.Fabric)
		add(ctx, sh, "Shin", Vector3.new(0.44, 1.06, 0.48), at(x, 0.84, 0.01), shorts and skin or pants, shorts and M.SmoothPlastic or M.Fabric)
		add(ctx, sh, "Shoe", Vector3.new(0.5, 0.3, 0.92), at(x, 0.15, -0.15), shoe, M.SmoothPlastic)
	end
end

----------------------------------------------------------------------
-- Tenues par style
----------------------------------------------------------------------

type Look = {
	Skin: Color3,
	Hair: Color3,
	HairStyle: string,
	Shirt: Color3,
	Pants: Color3,
	Shoe: Color3,
	Female: boolean,
	LongSleeve: boolean,
	Shorts: boolean,
	Skirt: boolean,
	Belt: boolean,
}

local function baseLook(style: string, seed: number, opts: Opts): Look
	local female = hash(seed, 1) < 0.5
	local hairStyle = pick(HAIR_STYLES, seed, 2)
	if not female and (hairStyle == "long" or hairStyle == "bun" or hairStyle == "pony") then
		hairStyle = hash(seed, 3) < 0.5 and "short" or "buzz"
	end
	if female and hairStyle == "buzz" then
		hairStyle = "long"
	end
	local hair = pick(HAIRS, seed, 4)
	if style == "elder" then
		hair = pick(GREYS, seed, 5)
		if not female and hash(seed, 6) < 0.5 then
			hairStyle = "bald"
		end
	end
	return {
		Skin = opts.Skin or pick(SKINS, seed, 7),
		Hair = opts.Hair or hair,
		HairStyle = hairStyle,
		Shirt = opts.Shirt or pick(SHIRTS, seed, 8),
		Pants = opts.Pants or pick(PANTS, seed, 9),
		Shoe = pick(SHOES, seed, 10),
		Female = female,
		LongSleeve = hash(seed, 11) < 0.45,
		Shorts = false,
		Skirt = female and hash(seed, 12) < 0.3,
		Belt = hash(seed, 13) < 0.5,
	}
end

-- Accessoire tenu dans la main droite (groupe avant-bras droit)
local function prop(ctx: Ctx, kind: string, seed: number)
	local hand = Vector3.new(0.93, 2.06, -0.02)
	if kind == "bag" then
		local c = pick({ rgb(236, 72, 140), rgb(255, 255, 255), rgb(120, 180, 90), rgb(90, 140, 230), rgb(214, 170, 120) }, seed, 30)
		add(ctx, G_RLO, "Bag", Vector3.new(0.34, 0.9, 0.8), at(hand.X + 0.08, hand.Y - 0.72, 0), c, M.SmoothPlastic)
		add(ctx, G_RLO, "BagHandle", Vector3.new(0.06, 0.34, 0.5), at(hand.X + 0.08, hand.Y - 0.12, 0), c:Lerp(INK, 0.3), M.SmoothPlastic)
	elseif kind == "phone" then
		add(ctx, G_RLO, "Phone", Vector3.new(0.2, 0.06, 0.36), at(hand.X - 0.02, hand.Y + 0.02, -0.26), rgb(30, 30, 36), M.SmoothPlastic)
		add(ctx, G_RLO, "PhoneScreen", Vector3.new(0.16, 0.02, 0.3), at(hand.X - 0.02, hand.Y + 0.06, -0.26), rgb(120, 190, 255), M.Glass)
	elseif kind == "coffee" then
		add(ctx, G_RLO, "Cup", Vector3.new(0.5, 0.26, 0.26), at(hand.X, hand.Y + 0.14, -0.2) * UPRIGHT, WHITE, M.SmoothPlastic, "Cyl")
		add(ctx, G_RLO, "CupSleeve", Vector3.new(0.2, 0.28, 0.28), at(hand.X, hand.Y + 0.1, -0.2) * UPRIGHT, rgb(170, 120, 80), M.Cardboard, "Cyl")
		add(ctx, G_RLO, "CupLid", Vector3.new(0.06, 0.3, 0.3), at(hand.X, hand.Y + 0.41, -0.2) * UPRIGHT, rgb(60, 50, 50), M.SmoothPlastic, "Cyl")
	elseif kind == "cane" then
		add(ctx, G_RLO, "Cane", Vector3.new(0.12, 2.1, 0.12), at(hand.X + 0.02, hand.Y - 1.02, -0.05), rgb(110, 70, 44), M.Wood)
		add(ctx, G_RLO, "CaneGrip", Vector3.new(0.12, 0.12, 0.44), at(hand.X + 0.02, hand.Y + 0.04, -0.14), rgb(110, 70, 44), M.Wood)
	elseif kind == "tablet" then
		-- (main GAUCHE : la droite tape dessus)
		add(ctx, G_LLO, "Tablet", Vector3.new(0.7, 0.06, 0.95), at(-0.72, 2.12, -0.38) * CFrame.Angles(0, 0, math.rad(-12)), rgb(40, 40, 46), M.SmoothPlastic)
		add(ctx, G_LLO, "TabletScreen", Vector3.new(0.6, 0.04, 0.82), at(-0.715, 2.17, -0.38) * CFrame.Angles(0, 0, math.rad(-12)), rgb(150, 210, 255), M.Glass)
	end
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

function NPCModels.Build(style: string, opts: Opts?): Model
	local o: Opts = opts or {}
	if not table.find(NPCModels.Styles, style) then
		style = "pedestrian"
	end
	local seed = o.Seed or 1
	local model = Instance.new("Model")
	model.Name = o.Name or ("NPC_" .. style)
	local scale = (o.Scale or 1) * BASE
	local hs = 1
	if style == "kid" and o.Scale == nil then
		scale = BASE * (0.6 + hash(seed, 40) * 0.08)
		hs = 1.22
	end
	local ctx: Ctx = { Model = model, S = scale, HS = hs, Count = 0 }
	local look = baseLook(style, seed, o)
	local shirt, pants = look.Shirt, look.Pants
	local sleeve = shirt
	local longSleeve = look.LongSleeve
	local skirt = look.Skirt
	local shorts = false
	local cuff: Color3? = nil
	local propKind = o.Prop
	local extras: { () -> () } = {}

	if style == "cashier" then
		shirt = o.Shirt or pick({ rgb(40, 150, 150), rgb(214, 60, 90), rgb(60, 110, 200) }, seed, 50)
		sleeve, longSleeve, skirt = shirt, false, false
		pants = o.Pants or rgb(46, 50, 62)
		table.insert(extras, function()
			-- polo : col + badge + visière
			add(ctx, G_BODY, "Collar", Vector3.new(0.18, 0.78, 0.78), at(0, 4.3, 0) * UPRIGHT, shirt:Lerp(WHITE, 0.25), M.Fabric, "Cyl")
			add(ctx, G_BODY, "Badge", Vector3.new(0.36, 0.2, 0.06), at(0.32, 3.9, -0.35), WHITE, M.SmoothPlastic)
			add(ctx, G_BODY, "BadgeDot", Vector3.new(0.08, 0.08, 0.05), at(0.2, 3.9, -0.385), shirt, M.SmoothPlastic)
			add(ctx, G_HEAD, "Visor", Vector3.new(1.06, 0.16, 1.08), at(0, HEAD_Y + 0.3, 0), shirt, M.SmoothPlastic, "Egg")
			add(ctx, G_HEAD, "VisorBrim", Vector3.new(0.72, 0.06, 0.44), at(0, HEAD_Y + 0.3, -0.62) * CFrame.Angles(math.rad(8), 0, 0), shirt, M.SmoothPlastic)
		end)
	elseif style == "baker" then
		shirt = WHITE
		sleeve, longSleeve, skirt = WHITE, true, false
		pants = o.Pants or rgb(60, 60, 70)
		cuff = rgb(230, 230, 226)
		table.insert(extras, function()
			add(ctx, G_BODY, "Apron", Vector3.new(1.08, 2.1, 0.08), at(0, 2.65, -0.36), rgb(236, 190, 130), M.Fabric)
			for i = 0, 1 do
				add(ctx, G_BODY, "Button", Vector3.new(0.1, 0.1, 0.1), at(0.3, 4.12 - i * 0.24, -0.34), rgb(200, 200, 200), M.SmoothPlastic, "Ball")
			end
			add(ctx, G_HEAD, "Toque", Vector3.new(0.7, 1.04, 1.04), at(0, HEAD_Y + 0.72, 0.02) * UPRIGHT, WHITE, M.Fabric, "Cyl")
			add(ctx, G_HEAD, "ToquePuff", Vector3.new(1.18, 0.62, 1.18), at(0, HEAD_Y + 1.1, 0.02), WHITE, M.Fabric, "Egg")
		end)
	elseif style == "salesperson" then
		local jacket = o.Shirt or pick({ rgb(36, 44, 70), rgb(40, 40, 44), rgb(90, 90, 100) }, seed, 51)
		shirt, sleeve, longSleeve, skirt = jacket, jacket, true, false
		pants = o.Pants or jacket
		cuff = WHITE
		propKind = propKind or "tablet"
		table.insert(extras, function()
			-- plastron de chemise en V + cravate + revers
			add(ctx, G_BODY, "ShirtFront", Vector3.new(0.5, 0.9, 0.06), at(0, 3.85, -0.35), WHITE, M.Fabric)
			add(ctx, G_BODY, "Tie", Vector3.new(0.14, 0.78, 0.06), at(0, 3.82, -0.38), pick({ rgb(200, 40, 60), rgb(236, 72, 140), rgb(60, 110, 200) }, seed, 52), M.Fabric)
			for _, sx in ipairs({ -1, 1 }) do
				add(ctx, G_BODY, "Lapel", Vector3.new(0.2, 0.95, 0.09), at(sx * 0.3, 3.85, -0.37) * CFrame.Angles(0, 0, sx * 0.3), jacket:Lerp(INK, 0.25), M.Fabric)
			end
			add(ctx, G_BODY, "Pocket", Vector3.new(0.2, 0.06, 0.06), at(-0.44, 3.95, -0.35), WHITE, M.SmoothPlastic)
		end)
		look.Shoe = rgb(40, 30, 28)
	elseif style == "shopper" then
		propKind = propKind or "bag"
	elseif style == "jogger" then
		shirt = o.Shirt or pick({ rgb(255, 120, 60), rgb(80, 200, 160), rgb(236, 72, 140), rgb(90, 150, 240) }, seed, 53)
		sleeve, longSleeve, skirt, shorts = shirt, false, false, true
		pants = o.Pants or rgb(40, 44, 54)
		look.Shoe = pick({ rgb(250, 250, 250), rgb(255, 90, 90), rgb(90, 200, 255) }, seed, 54)
		look.Belt = false
		table.insert(extras, function()
			add(ctx, G_HEAD, "Headband", Vector3.new(0.12, 1.06, 1.1), at(0, HEAD_Y + 0.2, 0) * UPRIGHT, WHITE, M.Fabric, "Cyl")
		end)
	elseif style == "elder" then
		shirt = o.Shirt or pick({ rgb(150, 120, 100), rgb(120, 130, 150), rgb(170, 90, 90), rgb(110, 130, 100) }, seed, 55)
		sleeve, longSleeve = shirt, true
		propKind = propKind or (hash(seed, 56) < 0.5 and "cane" or nil)
		table.insert(extras, function()
			-- gilet : boutons
			for i = 0, 3 do
				add(ctx, G_BODY, "Button", Vector3.new(0.09, 0.09, 0.09), at(0, 4.05 - i * 0.36, -0.34), rgb(230, 220, 200), M.SmoothPlastic, "Ball")
			end
			if hash(seed, 57) < 0.6 then
				-- lunettes
				for _, sx in ipairs({ -1, 1 }) do
					local lens = add(ctx, G_HEAD, "Glasses", Vector3.new(0.04, 0.24, 0.28), at(sx * 0.19, HEAD_Y + 0.04, -0.57) * CFrame.Angles(0, math.rad(90), 0), rgb(200, 226, 240), M.Glass, "Cyl")
					lens.Transparency = 0.45
				end
			end
		end)
	elseif style == "worker" then
		shirt = o.Shirt or rgb(70, 90, 130)
		sleeve, longSleeve, skirt = shirt, true, false
		pants = o.Pants or rgb(60, 70, 90)
		look.Shoe = rgb(96, 70, 44)
		look.HairStyle = "none" -- (le casque couvre les cheveux)
		table.insert(extras, function()
			local vest = rgb(255, 150, 40)
			add(ctx, G_BODY, "Vest", Vector3.new(1.38, 1.3, 0.76), at(0, 3.6, 0), vest, M.Fabric)
			add(ctx, G_BODY, "VestStripe", Vector3.new(1.2, 0.14, 0.06), at(0, 3.35, -0.38), rgb(230, 230, 220), M.Glass)
			add(ctx, G_HEAD, "Helmet", Vector3.new(1.12, 0.74, 1.12), at(0, HEAD_Y + 0.33, 0.02), rgb(255, 210, 40), M.SmoothPlastic, "Egg")
			add(ctx, G_HEAD, "HelmetBrim", Vector3.new(0.08, 1.2, 1.26), at(0, HEAD_Y + 0.14, 0.02) * UPRIGHT, rgb(255, 210, 40), M.SmoothPlastic, "Cyl")
		end)
	elseif style == "kid" then
		shorts = hash(seed, 58) < 0.5 and not skirt
		longSleeve = false
		look.Belt = false
		table.insert(extras, function()
			if hash(seed, 59) < 0.5 then
				-- sac à dos
				local c = pick({ rgb(255, 120, 160), rgb(90, 160, 240), rgb(255, 200, 60), rgb(120, 200, 120) }, seed, 60)
				add(ctx, G_BODY, "Backpack", Vector3.new(0.98, 1.1, 0.42), at(0, 3.45, 0.53), c, M.Fabric)
				add(ctx, G_BODY, "BackpackPocket", Vector3.new(0.7, 0.44, 0.12), at(0, 3.12, 0.78), c:Lerp(WHITE, 0.3), M.Fabric)
			end
		end)
	elseif style == "pedestrian" then
		if hash(seed, 61) < 0.35 then
			-- veste ouverte par-dessus le t-shirt
			local jacket = pick({ rgb(60, 70, 90), rgb(120, 80, 60), rgb(180, 160, 130), rgb(70, 110, 90), rgb(150, 40, 60) }, seed, 62)
			sleeve, longSleeve = jacket, true
			table.insert(extras, function()
				for _, sx in ipairs({ -1, 1 }) do
					add(ctx, G_BODY, "Jacket", Vector3.new(0.44, 1.66, 0.74), at(sx * 0.47, 3.44, 0), jacket, M.Fabric)
				end
				add(ctx, G_BODY, "JacketBack", Vector3.new(1.18, 1.62, 0.1), at(0, 3.43, 0.35), jacket, M.Fabric)
			end)
		end
	end
	if propKind == "none" then
		propKind = nil
	end

	-- buste, bassin, ceinture, cou
	local skin, hair = look.Skin, look.Hair
	add(ctx, G_BODY, "Torso", Vector3.new(1.3, 1.62, 0.68), at(0, 3.5, 0), shirt, M.Fabric)
	add(ctx, G_BODY, "Chest", Vector3.new(1.16, 0.5, 0.6), at(0, 4.3, 0.02), shirt, M.Fabric, "Egg")
	add(ctx, G_BODY, "Neck", Vector3.new(0.34, 0.38, 0.38), at(0, 4.45, 0.02) * UPRIGHT, skin, M.SmoothPlastic, "Cyl")
	if skirt then
		add(ctx, G_BODY, "Skirt", Vector3.new(1.24, 1.0, 0.8), at(0, 2.3, 0), pants:Lerp(rgb(200, 90, 120), 0.4), M.Fabric)
	else
		add(ctx, G_BODY, "Hips", Vector3.new(1.14, 0.6, 0.62), at(0, 2.45, 0), pants, M.Fabric)
	end
	if look.Belt and not skirt and style ~= "baker" then
		add(ctx, G_BODY, "Belt", Vector3.new(1.2, 0.12, 0.68), at(0, 2.62, 0), rgb(60, 40, 30), M.Leather)
	end
	head(ctx, skin, hair, look.HairStyle, seed, look.Female)
	arm(ctx, -1, sleeve, skin, longSleeve, cuff)
	arm(ctx, 1, sleeve, skin, longSleeve, cuff)
	legs(ctx, pants, skin, look.Shoe, shorts, skirt)
	for _, fn in ipairs(extras) do
		fn()
	end
	if propKind then
		prop(ctx, propKind, seed)
		model:SetAttribute("NpcProp", propKind)
	end
	-- pivot au sol (pièce racine invisible entre les pieds)
	local root = Instance.new("Part")
	root.Name = "NpcRoot"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Transparency = 1
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("NpcStyle", style)
	model:SetAttribute("NpcScale", scale)
	model:SetAttribute("NpcHeadScale", hs)
	model:SetAttribute("PartCount", ctx.Count + 1)
	return model
end

----------------------------------------------------------------------
-- Animation procédurale (client)
----------------------------------------------------------------------

type Rig = {
	Root: BasePart,
	Parts: { BasePart },
	Rests: { CFrame },
	Groups: { number },
	Frames: { CFrame },
	S: number,
	Prop: string?,
}

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function rigOf(model: Model): Rig?
	local rig = rigs[model]
	if rig and rig.Root.Parent == model then
		return rig
	end
	local root = model.PrimaryPart or model:FindFirstChild("NpcRoot")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local r: Rig = { Root = root, Parts = {}, Rests = {}, Groups = {}, Frames = {}, S = tonumber(model:GetAttribute("NpcScale")) or BASE, Prop = nil }
	local p = model:GetAttribute("NpcProp")
	r.Prop = type(p) == "string" and p or nil
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			local g = d:GetAttribute("NpcG")
			local rest = d:GetAttribute("NpcRest")
			if type(g) == "number" and typeof(rest) == "CFrame" then
				table.insert(r.Parts, d)
				table.insert(r.Rests, rest)
				table.insert(r.Groups, g)
				table.insert(r.Frames, rest)
			end
		end
	end
	rigs[model] = r
	return r
end

-- rotation `rot` autour du point `p` (repère du pivot, échelle appliquée)
local function about(p: Vector3, rot: CFrame): CFrame
	return CFrame.new(p) * rot * CFrame.new(-p)
end

local ANG = CFrame.Angles
local T: { CFrame } = table.create(10, CFrame.new())

-- Pose : angles (radians). x > 0 = membre vers l'avant.
type Pose = {
	Bob: number,
	Lean: number,
	Twist: number,
	HeadYaw: number,
	HeadPitch: number,
	LUp: CFrame,
	LLo: number,
	RUp: CFrame,
	RLo: number,
	LTh: number,
	LSh: number,
	RTh: number,
	RSh: number,
	Drop: number,
	LLoRot: CFrame?,
	RLoRot: CFrame?,
}

local function pose(anim: string, t: number, propKind: string?): Pose
	local P: Pose = {
		Bob = 0,
		Lean = 0,
		Twist = 0,
		HeadYaw = 0,
		HeadPitch = 0,
		LUp = CFrame.identity,
		LLo = 0,
		RUp = CFrame.identity,
		RLo = 0,
		LTh = 0,
		LSh = 0,
		RTh = 0,
		RSh = 0,
		Drop = 0,
	}
	local breathe = math.sin(t * 1.7) * 0.012
	if anim == "walk" or anim == "push" then
		local w = t * math.pi * 2 * 0.9 -- ~1,8 pas / s
		local sw = math.sin(w)
		P.LTh = sw * 0.5
		P.RTh = -sw * 0.5
		-- genou : plié pendant que la jambe revient vers l'avant
		P.LSh = -math.max(0, math.sin(w + 1.3)) * 0.75 - 0.05
		P.RSh = -math.max(0, math.sin(w + 1.3 + math.pi)) * 0.75 - 0.05
		P.Bob = math.abs(math.cos(w)) * 0.07 - 0.05
		P.Twist = sw * 0.06
		P.HeadYaw = -sw * 0.04 + math.sin(t * 0.37) * 0.25
		if anim == "push" then
			P.Lean = 0.12
			P.LUp = ANG(0.95, 0, 0.08)
			P.RUp = ANG(0.95, 0, -0.08)
			P.LLo, P.RLo = 0.55, 0.55
		else
			P.LUp = ANG(-sw * 0.42, 0, -0.06)
			P.RUp = ANG(sw * 0.42, 0, 0.06)
			P.LLo = 0.2 + math.max(0, -sw) * 0.3
			P.RLo = 0.2 + math.max(0, sw) * 0.3
		end
	elseif anim == "sit" then
		P.Drop = 0
		P.LTh, P.RTh = 1.5, 1.45
		P.LSh, P.RSh = -1.45 + math.sin(t * 1.3) * 0.12, -1.4 - math.sin(t * 1.3 + 1) * 0.12
		P.Lean = -0.08
		P.LUp = ANG(0.35, 0, -0.05)
		P.RUp = ANG(0.35, 0, 0.05)
		P.LLo, P.RLo = 0.9, 0.9
		P.HeadYaw = math.sin(t * 0.31) * 0.45
		P.HeadPitch = math.sin(t * 0.5) * 0.05
		P.Bob = breathe
	elseif anim == "wave" then
		P.Bob = breathe
		P.RUp = ANG(0, 0, 2.55)
		P.RLo = 0.35
		P.RLoRot = ANG(0, 0, math.sin(t * 7) * 0.45)
		P.LUp = ANG(0.05, 0, -0.06)
		P.LLo = 0.15
		P.HeadPitch = -0.08
		P.HeadYaw = 0.1
	elseif anim == "scan" then
		-- caisse : les mains passent les articles devant le scanner (droite -> gauche)
		local cyc = (t * 0.9) % 1
		local sweep = math.sin(cyc * math.pi * 2)
		P.Bob = breathe
		P.Lean = 0.12
		P.Twist = sweep * 0.12
		P.LUp = ANG(0.55, sweep * 0.25, 0)
		P.RUp = ANG(0.6, sweep * 0.3, 0)
		P.LLo, P.RLo = 1.15, 1.1
		P.HeadPitch = 0.3
		P.HeadYaw = sweep * 0.15
	elseif anim == "type" then
		P.Bob = breathe
		P.LUp = ANG(0.35, 0, 0.12)
		P.LLo = 1.25
		P.RUp = ANG(0.45, 0.2, -0.05)
		P.RLo = 1.05 + math.sin(t * 9) * 0.08
		P.HeadPitch = 0.35
		P.Lean = 0.04
	elseif anim == "talk" then
		local g = math.sin(t * 2.2)
		P.Bob = breathe
		P.HeadPitch = math.sin(t * 3.1) * 0.08
		P.HeadYaw = math.sin(t * 0.6) * 0.2
		P.RUp = ANG(0.35 + g * 0.12, 0, 0.12)
		P.RLo = 0.95 + math.sin(t * 3.3) * 0.25
		P.LUp = ANG(0.08, 0, -0.08)
		P.LLo = 0.25 + math.max(0, math.sin(t * 1.1)) * 0.6
		P.Twist = g * 0.05
	else -- idle
		P.Bob = breathe
		P.HeadYaw = math.sin(t * 0.33) * 0.35 + math.sin(t * 0.91) * 0.1
		P.HeadPitch = math.sin(t * 0.47) * 0.05
		P.LUp = ANG(0.02, 0, -0.05 - breathe)
		P.RUp = ANG(0.02, 0, 0.05 + breathe)
		P.LLo, P.RLo = 0.12, 0.12
		P.LTh, P.RTh = 0.02, -0.02
	end
	-- accessoires tenus : le téléphone se regarde, le café se porte
	local handsBusy = (anim == "wave" or anim == "push" or anim == "scan")
	local typing = (anim == "type")
	local casual = (anim == "walk" or anim == "idle")
	if propKind == "phone" and not handsBusy then
		P.RUp = ANG(0.35, 0.25, 0.05)
		P.RLo = 1.35
		P.HeadPitch = 0.45
		P.HeadYaw = 0.1
	elseif propKind == "coffee" and not handsBusy then
		P.RUp = ANG(0.25, 0, 0.05)
		P.RLo = 1.2
	elseif propKind == "tablet" and not typing then
		P.LUp = ANG(0.3, 0, 0.1)
		P.LLo = 1.2
	elseif propKind == "bag" and casual then
		P.RUp = ANG(0.03, 0, 0.12)
		P.RLo = 0.05
	end
	return P
end

-- Déplace un PNJ (pièce racine seulement ; Animate repose les autres)
function NPCModels.Place(model: Model, cf: CFrame)
	local root = model.PrimaryPart
	if root then
		root.CFrame = cf
	else
		model:PivotTo(cf)
	end
end

function NPCModels.Animate(model: Model, anim: string, t: number)
	local rig = rigOf(model)
	if not rig then
		return
	end
	local s = rig.S
	local P = pose(anim, t, rig.Prop)
	local pivot = rig.Root.CFrame
	-- (assis : le bassin se pose sur le banc -> descend de ~0,4 ; SitHeight 1,9)
	local sitDrop = anim == "sit" and (J.HipL.Y * s - (NPCModels.SitHeight + 0.2)) or 0
	local body = CFrame.new(0, P.Bob * s - sitDrop, 0)
	local waist = J.Waist * s
	local torso = body * about(waist, ANG(P.Lean, P.Twist, 0))
	T[G_BODY] = torso
	T[G_HEAD] = torso * about(J.Neck * s, ANG(P.HeadPitch, P.HeadYaw, 0))
	local lu = torso * about(J.ShoulderL * s, P.LUp)
	T[G_LUP] = lu
	T[G_LLO] = lu * about(J.ElbowL * s, ANG(P.LLo, 0, 0) * (P.LLoRot or CFrame.identity))
	local ru = torso * about(J.ShoulderR * s, P.RUp)
	T[G_RUP] = ru
	T[G_RLO] = ru * about(J.ElbowR * s, ANG(P.RLo, 0, 0) * (P.RLoRot or CFrame.identity))
	local lt = body * about(J.HipL * s, ANG(P.LTh, 0, 0))
	T[G_LTH] = lt
	T[G_LSH] = lt * about(J.KneeL * s, ANG(P.LSh, 0, 0))
	local rt = body * about(J.HipR * s, ANG(P.RTh, 0, 0))
	T[G_RTH] = rt
	T[G_RSH] = rt * about(J.KneeR * s, ANG(P.RSh, 0, 0))
	local frames = rig.Frames
	local groups = rig.Groups
	local rests = rig.Rests
	for i = 1, #rig.Parts do
		frames[i] = pivot * T[groups[i]] * rests[i]
	end
	workspace:BulkMoveTo(rig.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- (tests / rendus) pièces d'un modèle
function NPCModels.PartCount(model: Model): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return NPCModels
