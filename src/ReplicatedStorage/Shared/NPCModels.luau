--[[
	NPCModels (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > NPCModels

	🧍 Personnages non joueurs de Dopamine Town, partagés par le serveur ET le
	client (v9.8 CITY98 ; v9.9 NPC99 : "20x plus réalistes").
	Styles : caissier·ère, boulanger·ère, client·e, vendeur·se, passant·e,
	joggeur·se, enfant, personne âgée, ouvrier·ère.

	v9.9 (NPC99) — un vrai corps humain, "mignon-réaliste" :
	  - PROPORTIONS d'adulte (≈ 6,3 têtes : tête 0,84 pour 5,3 studs), épaules
	    à 4,16, coudes à 3,32, hanches à 2,6, genoux à 1,5, chevilles à 0,34 ;
	    torse arrondi (buste + cage thoracique ovale + ventre + bassin +
	    fessiers), cou, membres CYLINDRIQUES avec rotules (épaule, coude,
	    genou) : ils plient sans trou ;
	  - VISAGE : crâne + mâchoire, yeux dessinés (SurfaceGui, que des Frame :
	    blanc en amande, iris coloré, pupille, reflet, ligne de cils),
	    paupières qui CLIGNENT, sourcils, nez, lèvres (SurfaceGui), oreilles ;
	    barbe / moustache pour certains hommes, lunettes, maquillage léger ;
	  - CHEVEUX en volume (calotte + nuque + mèches, 10 coiffures : courte,
	    raie, longue, carré, chignon, queue de cheval, bouclée, afro, rasée,
	    chauve) ;
	  - VÊTEMENTS : col (rond, polo, chemise, V), coutures (ourlet, patte de
	    boutonnage, poche), ceinture + boucle, ourlets de pantalon, manches
	    courtes (ourlet) ou longues (poignets), jupe évasée, chaussures avec
	    SEMELLE contrastée, bout arrondi et lacets ;
	  - MAINS : paume, doigts légèrement repliés, POUCE ;
	  - accessoires de métier (visière + badge, toque + tablier, costume +
	    cravate + pochette + tablette, gilet fluo + casque, bandeau, cartable)
	    et objets tenus (sac, téléphone, café, canne, tablette).
	  ~55 à 75 pièces, ANCRÉES, sans collision / requête / contact (sauf la
	  capsule de collision, voir SetSolid), sans ombre pour les petites.
	  Aucune lumière, aucun son, aucun script.

	ANIMATION (v9.9) : marche avec attaque du talon, genou qui plie pendant
	l'oscillation, déroulé du pied, bassin qui se balance et tourne, buste en
	contre-rotation, bras en opposition, rebond vertical ; respiration et
	transfert du poids au repos, clignements des yeux ; la tête se TOURNE
	doucement vers le joueur proche (automatique côté client, ou `look`).

	COLLISION (v9.9) : chaque PNJ reçoit une capsule invisible, ancrée,
	CanCollide (cylindre debout ; boîte quand il est assis) qui suit le
	personnage : le joueur ne le traverse plus. Jamais piégé : si l'avatar
	local se retrouve DANS la capsule (PNJ apparu sur lui), la capsule
	devient traversable jusqu'à ce qu'il en sorte.

	Repère : le PIVOT du modèle est entre les pieds, au sol ; le personnage
	regarde vers -Z (LookVector du pivot). On le place avec
	`m:PivotTo(solCF)`.

	API (compatible v9.8) :
	  NPCModels.Build(style, opts?) -> Model   (non parenté)
	    opts : { Seed, Skin, Shirt, Pants, Hair, Scale, Prop, Name,
	             SitHeight?, Solid? (défaut true), Look? (défaut true) }
	    (même Seed -> même personne sur tous les clients)
	  NPCModels.Place(model, cf)       LA façon de DÉPLACER un PNJ qui bouge
	    (à chaque image) : ne pose que la pièce racine ; Animate repose le reste
	  NPCModels.Animate(model, anim, t, look?)   (CLIENT, à chaque image, léger)
	    anim : "idle" | "walk" | "talk" | "wave" | "scan" | "push" | "sit" |
	           "type" | "clap" | "cheer"
	    t : temps en secondes (+ décalage propre au PNJ) ; `look` (facultatif) :
	    point du monde à regarder (sinon : l'avatar local s'il est proche).
	    La pose est relative au pivot ACTUEL (Place / PivotTo d'abord).
	  NPCModels.SetSolid(model, on)    capsule de collision (défaut : on)
	  NPCModels.SetSitHeight(model, h) dessus du siège (studs au-dessus du
	    pivot) pour "sit" et pour un PNJ ASSIS qui fait autre chose ;
	  NPCModels.SetSeated(model, h?)   h = nombre : assis (les jambes restent
	    assises quelle que soit l'anim : caissier·ère sur un tabouret qui
	    "scan", client qui "talk" en terrasse) ; nil : debout
	  NPCModels.Height (5,3), NPCModels.SitHeight (1,45 : dessus d'un banc /
	    d'une chaise v9.9), NPCModels.Styles, NPCModels.Anims,
	  NPCModels.PartCount(model)
]]

local NPCModels = {}

local M = Enum.Material
local rgb = Color3.fromRGB
-- (v11) tissus lisses : le matériau "Fabric" de Roblox donne un grain
-- pailleté sur les couleurs sombres (capture 32) ; tricot seulement pour
-- l'écharpe et les cheveux crépus
local CLOTH = M.SmoothPlastic
local KNIT = M.Fabric

NPCModels.Height = 5.3
-- (v9.9) dessus d'un siège "standard" (banc de la ville, chaise) : le bassin
-- s'y pose (articulation de la hanche ≈ 0,24 au-dessus, fessiers dessus)
-- (v11 SCALE11) bancs / chaises "à l'échelle Roblox" : dessus à 1,85
NPCModels.SitHeight = 1.85
NPCModels.Styles = { "cashier", "baker", "shopper", "salesperson", "pedestrian", "jogger", "kid", "elder", "worker" }
NPCModels.Anims = { "idle", "walk", "talk", "wave", "scan", "push", "sit", "type", "clap", "cheer" }

-- Groupes articulés (attribut "NpcG" de chaque pièce)
local G_CHEST, G_HEAD = 1, 2
local G_LUP, G_LLO, G_RUP, G_RLO = 3, 4, 5, 6
local G_LTH, G_LSH, G_RTH, G_RSH = 7, 8, 9, 10
local G_PELVIS, G_LFT, G_RFT = 11, 12, 13
local G_LID, G_COL = 14, 15
-- (v11) mains articulées : poignet (la main tourne au bout de l'avant-bras)
local G_LHAND, G_RHAND = 16, 17
local NGROUPS = 17

-- Articulations au repos (repère du pivot, échelle 1)
local J = {
	Pelvis = Vector3.new(0, 2.66, 0),
	Waist = Vector3.new(0, 3.05, 0),
	Neck = Vector3.new(0, 4.42, 0.02),
	ShoulderL = Vector3.new(-0.68, 4.14, 0),
	ShoulderR = Vector3.new(0.68, 4.14, 0),
	ElbowL = Vector3.new(-0.73, 3.32, 0.02),
	ElbowR = Vector3.new(0.73, 3.32, 0.02),
	HipL = Vector3.new(-0.27, 2.6, 0),
	HipR = Vector3.new(0.27, 2.6, 0),
	KneeL = Vector3.new(-0.27, 1.5, 0),
	KneeR = Vector3.new(0.27, 1.5, 0),
	AnkleL = Vector3.new(-0.27, 0.34, 0.03),
	AnkleR = Vector3.new(0.27, 0.34, 0.03),
}
local THIGH_LEN = 1.1 -- (hanche -> genou)
local KNEE_Y = 1.5 -- (genou -> sol, pied à plat)
local HIP_OVER_SEAT = 0.24 -- (articulation de la hanche au-dessus du siège : rayon de la cuisse)
NPCModels.Joints = J

-- Tête (centre du crâne) et visage
local HY = 4.84
local HEAD = Vector3.new(0.68, 0.84, 0.76) -- crâne (ovale)

----------------------------------------------------------------------
-- Palettes réalistes
----------------------------------------------------------------------

local SKINS = {
	rgb(255, 226, 204),
	rgb(246, 212, 184),
	rgb(236, 192, 156),
	rgb(222, 172, 132),
	rgb(200, 146, 106),
	rgb(170, 116, 82),
	rgb(134, 90, 64),
	rgb(100, 66, 48),
}
local HAIRS = {
	rgb(34, 26, 24), -- noir
	rgb(64, 44, 32), -- brun foncé
	rgb(104, 70, 46), -- châtain
	rgb(150, 104, 62), -- châtain clair
	rgb(214, 176, 116), -- blond
	rgb(168, 80, 46), -- roux
	rgb(52, 36, 30),
	rgb(230, 200, 146), -- blond clair
}
local GREYS = { rgb(208, 208, 208), rgb(180, 180, 184), rgb(236, 234, 230), rgb(150, 148, 150) }
local IRIS = { rgb(92, 60, 38), rgb(62, 40, 28), rgb(120, 96, 52), rgb(70, 116, 160), rgb(84, 120, 84), rgb(110, 124, 136) }
local SHIRTS = {
	rgb(66, 110, 170), -- bleu jean
	rgb(236, 236, 232), -- blanc cassé
	rgb(186, 60, 70), -- rouge
	rgb(84, 140, 110), -- vert sauge
	rgb(238, 190, 88), -- moutarde
	rgb(146, 110, 176), -- lilas
	rgb(52, 58, 72), -- anthracite
	rgb(246, 170, 188), -- rose
	rgb(120, 176, 216), -- ciel
	rgb(206, 116, 72), -- terracotta
	rgb(230, 220, 196), -- beige
	rgb(40, 106, 118), -- canard
	rgb(96, 74, 64), -- chocolat
	rgb(210, 214, 222), -- gris perle
}
local PANTS = {
	rgb(50, 68, 106), -- jean
	rgb(38, 42, 52), -- noir
	rgb(128, 108, 84), -- chino
	rgb(82, 88, 98), -- gris
	rgb(72, 94, 140), -- jean clair
	rgb(196, 178, 142), -- beige
	rgb(70, 78, 60), -- kaki
}
local SHOES = { rgb(38, 36, 38), rgb(240, 240, 238), rgb(108, 68, 42), rgb(58, 68, 108), rgb(186, 56, 64), rgb(150, 130, 110) }
local INK = rgb(30, 24, 26)
local WHITE = rgb(250, 250, 248)

local HAIR_F = { "long", "bob", "bun", "pony", "curly", "long", "afro", "part" }
local HAIR_M = { "short", "part", "buzz", "curly", "short", "afro", "part", "short" }

----------------------------------------------------------------------
-- Hasard déterministe (ENTIERS : identique sur tous les processeurs)
----------------------------------------------------------------------

local MODP = 2147483647
local function hash(a: number, b: number): number
	-- (Park-Miller : produits < 2^53, exacts en double partout)
	local x = (math.floor(a) * 7919 + math.floor(b) * 104729 + 12345) % MODP
	x = (x * 48271) % MODP
	x = (x * 48271) % MODP
	x = (x * 48271) % MODP
	return x / MODP
end
NPCModels.Hash = hash

local function pick<T>(list: { T }, seed: number, salt: number): T
	return list[math.floor(hash(seed, salt) * #list) % #list + 1]
end

-- légère variation d'une couleur (tissus : jamais deux fois exactement la même)
local function vary(c: Color3, seed: number, salt: number, amount: number?): Color3
	local k = ((hash(seed, salt) - 0.5) * 2) * (amount or 0.06)
	if k > 0 then
		return c:Lerp(WHITE, k)
	end
	return c:Lerp(INK, -k)
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
	SitHeight: number?,
	Solid: boolean?,
	Look: boolean?,
}

type Ctx = {
	Model: Model,
	S: number, -- échelle du corps
	HS: number, -- échelle en plus pour la tête (enfants : tête plus grosse)
	Count: number,
}

-- Pièce dans le groupe `g` : `cf` et `size` dans le repère de repos (échelle
-- 1). Les pièces de la tête sont agrandies autour du cou (HS).
local function add(ctx: Ctx, g: number, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local s = ctx.S
	local pos = cf.Position
	local sz = size
	if (g == G_HEAD or g == G_LID) and ctx.HS ~= 1 then
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
	p.CastShadow = (name == "Chest" or name == "Pelvis" or name == "Thigh" or name == "Skull")
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
-- cylindre debout centré en (x, y, z)
local function cylY(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z) * UPRIGHT
end

-- Point de la surface du crâne (ovale) vu depuis l'avant, à (x, y) :
-- position + repère tourné pour suivre la courbure (plaques du visage)
local function onEgg(center: Vector3, size: Vector3, x: number, y: number, out: number): CFrame
	local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
	local dx, dy = x - center.X, y - center.Y
	local k = 1 - (dx / a) ^ 2 - (dy / b) ^ 2
	local z = -c * math.sqrt(math.max(k, 0.02))
	-- normale (gradient de l'ovale)
	local n = Vector3.new(dx / (a * a), dy / (b * b), z / (c * c)).Unit
	local p = Vector3.new(x, y, center.Z + z) + n * out
	return CFrame.lookAt(p, p + n)
end
local function onSkull(x: number, y: number, out: number): CFrame
	return onEgg(Vector3.new(0, HY, 0), HEAD, x, y, out)
end

----------------------------------------------------------------------
-- Visage dessiné (SurfaceGui, uniquement des Frame arrondies)
----------------------------------------------------------------------

local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, round: number?, yy: boolean?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	if yy then
		f.SizeConstraint = Enum.SizeConstraint.RelativeYY
	end
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function faceGui(part: BasePart, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 400
	gui.LightInfluence = 1
	gui.MaxDistance = 140
	gui.ClipsDescendants = true
	gui.Parent = part
	return gui
end

-- Œil : blanc en amande, iris, pupille, reflet, ligne de cils (côté `sx`)
local function eyeGui(part: BasePart, iris: Color3, lash: Color3, female: boolean, sx: number)
	local gui = faceGui(part, "EyeGui")
	local white = frame(gui, "White", UDim2.fromScale(0.94, 0.74), UDim2.fromScale(0.5, 0.55), rgb(246, 242, 238), 0.5)
	local ir = frame(white, "Iris", UDim2.fromScale(0.98, 0.98), UDim2.fromScale(0.5 - sx * 0.02, 0.48), iris, 1, true)
	frame(ir, "Ring", UDim2.fromScale(0.72, 0.72), UDim2.fromScale(0.5, 0.5), iris:Lerp(WHITE, 0.18), 1)
	frame(ir, "Pupil", UDim2.fromScale(0.44, 0.44), UDim2.fromScale(0.5, 0.5), rgb(16, 12, 14), 1)
	frame(ir, "Glint", UDim2.fromScale(0.24, 0.24), UDim2.fromScale(0.66, 0.32), WHITE, 1)
	frame(ir, "Glint2", UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.34, 0.68), WHITE, 1)
	-- paupière supérieure (ligne de cils), plus marquée chez les femmes
	frame(gui, "Lash", UDim2.fromScale(1, female and 0.26 or 0.16), UDim2.fromScale(0.5, female and 0.2 or 0.2), lash, 0.5)
	if female then
		-- petite aile de cils vers l'extérieur
		local wing = frame(gui, "Wing", UDim2.fromScale(0.22, 0.14), UDim2.fromScale(sx > 0 and 0.95 or 0.05, 0.16), lash, 0.5)
		wing.Rotation = sx * -22
	end
end

-- Lèvres : lèvre supérieure, lèvre inférieure, commissure, petit sourire
local function mouthGui(part: BasePart, lip: Color3, smile: number)
	local gui = faceGui(part, "MouthGui")
	frame(gui, "LowerLip", UDim2.fromScale(0.62, 0.5), UDim2.fromScale(0.5, 0.62), lip:Lerp(WHITE, 0.08), 0.5)
	frame(gui, "UpperLip", UDim2.fromScale(0.72, 0.36), UDim2.fromScale(0.5, 0.36), lip, 0.5)
	frame(gui, "Line", UDim2.fromScale(0.74, 0.1), UDim2.fromScale(0.5, 0.5), lip:Lerp(INK, 0.55), 0.5)
	for _, sx in ipairs({ -1, 1 }) do
		local c = frame(gui, "Corner", UDim2.fromScale(0.14, 0.09), UDim2.fromScale(0.5 + sx * 0.4, 0.45 - smile * 0.06), lip:Lerp(INK, 0.5), 0.5)
		c.Rotation = sx * -(18 + smile * 20)
	end
end

----------------------------------------------------------------------
-- Tête
----------------------------------------------------------------------

type Look = {
	Skin: Color3,
	Hair: Color3,
	HairStyle: string,
	Shirt: Color3,
	Pants: Color3,
	Shoe: Color3,
	Sole: Color3,
	Female: boolean,
	LongSleeve: boolean,
	Shorts: boolean,
	Skirt: boolean,
	Belt: boolean,
	Collar: string, -- "crew" | "polo" | "shirt" | "v" | "none"
	Beard: string, -- "none" | "stubble" | "beard" | "mustache"
	Glasses: boolean,
	Iris: Color3,
}

local function head(ctx: Ctx, look: Look, seed: number)
	local skin, hair = look.Skin, look.Hair
	local female = look.Female
	add(ctx, G_HEAD, "Skull", HEAD, at(0, HY, 0), skin, M.SmoothPlastic, "Egg")
	-- mâchoire / menton (plus carrée chez les hommes)
	local jawC, jawS = Vector3.new(0, HY - 0.21, -0.06), Vector3.new(female and 0.5 or 0.56, 0.46, 0.6)
	local function onJaw(x: number, y: number, out: number): CFrame
		return onEgg(jawC, jawS, x, y, out)
	end
	add(ctx, G_HEAD, "Jaw", jawS, CFrame.new(jawC), skin, M.SmoothPlastic, "Egg")
	-- oreilles
	for _, sx in ipairs({ -1, 1 }) do
		add(ctx, G_HEAD, "Ear", Vector3.new(0.08, 0.2, 0.15), at(sx * 0.33, HY - 0.02, 0.03) * CFrame.Angles(0, sx * -0.3, 0), skin:Lerp(rgb(200, 120, 110), 0.08), M.SmoothPlastic, "Egg")
	end
	-- nez (arête + bout)
	add(ctx, G_HEAD, "Nose", Vector3.new(0.095, 0.19, 0.115), onSkull(0, HY - 0.08, 0.0) * CFrame.Angles(math.rad(-10), 0, 0), skin:Lerp(rgb(210, 130, 110), 0.1), M.SmoothPlastic, "Egg")
	-- yeux (plaques dessinées) + paupières (clignent) + sourcils
	local lash = look.HairStyle == "bald" and INK or hair:Lerp(INK, 0.6)
	for _, sx in ipairs({ -1, 1 }) do
		local e = add(ctx, G_HEAD, "Eye", Vector3.new(0.16, 0.11, 0.01), onSkull(sx * 0.127, HY + 0.01, 0.006), WHITE, M.SmoothPlastic)
		e.Transparency = 1
		eyeGui(e, look.Iris, lash, female, sx)
		-- paupière : cachée DANS le crâne ; au clignement elle avance devant l'œil
		add(ctx, G_LID, "Lid", Vector3.new(0.17, 0.12, 0.03), onSkull(sx * 0.125, HY + 0.015, -0.045), skin:Lerp(INK, 0.04), M.SmoothPlastic, "Egg")
		local browColor = look.HairStyle == "bald" and GREYS[1]:Lerp(INK, 0.3) or hair:Lerp(INK, 0.25)
		-- (v11) sourcil arrondi, plus fin (arqué chez les femmes)
		add(ctx, G_HEAD, "Brow", Vector3.new(0.17, female and 0.026 or 0.036, 0.04), onSkull(sx * 0.13, HY + 0.115, 0.0) * CFrame.Angles(0, 0, sx * (female and -0.16 or -0.07)), browColor, M.SmoothPlastic, "Egg")
	end
	-- bouche
	local lip = skin:Lerp(rgb(176, 84, 88), female and 0.45 or 0.28)
	if female and hash(seed, 70) < 0.35 then
		lip = pick({ rgb(190, 60, 80), rgb(200, 100, 110), rgb(160, 70, 70) }, seed, 71)
	end
	local mouth = add(ctx, G_HEAD, "Mouth", Vector3.new(0.2, 0.08, 0.01), onJaw(0, HY - 0.25, 0.008), WHITE, M.SmoothPlastic)
	mouth.Transparency = 1
	mouthGui(mouth, lip, hash(seed, 72))
	-- barbe / moustache
	local bc = hair:Lerp(INK, 0.1)
	if look.Beard == "beard" then
		-- (barbe du menton et des joues : derrière la bouche, devant le menton)
		add(ctx, G_HEAD, "Beard", Vector3.new(0.62, 0.34, 0.66), at(0, HY - 0.34, -0.04), bc, M.SmoothPlastic, "Egg")
		add(ctx, G_HEAD, "Mustache", Vector3.new(0.22, 0.05, 0.05), onJaw(0, HY - 0.195, 0.01), bc, M.SmoothPlastic)
	elseif look.Beard == "mustache" then
		add(ctx, G_HEAD, "Mustache", Vector3.new(0.24, 0.06, 0.05), onJaw(0, HY - 0.195, 0.01), bc, M.SmoothPlastic)
	end
	if look.Glasses then
		local frameC = pick({ rgb(40, 34, 34), rgb(120, 80, 50), rgb(180, 170, 160) }, seed, 73)
		for _, sx in ipairs({ -1, 1 }) do
			local lens = add(ctx, G_HEAD, "Glasses", Vector3.new(0.02, 0.15, 0.2), onSkull(sx * 0.125, HY + 0.005, 0.05) * CFrame.Angles(0, math.rad(90), 0), rgb(210, 226, 236), M.Glass, "Cyl")
			lens.Transparency = 0.55
			add(ctx, G_HEAD, "GlassesArm", Vector3.new(0.025, 0.025, 0.36), at(sx * 0.34, HY + 0.03, -0.13), frameC, M.SmoothPlastic)
		end
		add(ctx, G_HEAD, "GlassesBridge", Vector3.new(0.07, 0.025, 0.025), onSkull(0, HY + 0.03, 0.06), frameC, M.SmoothPlastic)
	end
	-- coiffure (volumes superposés, chacun à >= 0,03 des autres faces)
	local hs = look.HairStyle
	if hs == "none" then
		return
	end
	local hairM = M.SmoothPlastic
	if hs == "bald" then
		add(ctx, G_HEAD, "HairSide", Vector3.new(0.74, 0.3, 0.7), at(0, HY + 0.04, 0.1), hair, hairM, "Egg")
		return
	end
	local dark = hair:Lerp(INK, 0.12)
	if hs == "buzz" then
		add(ctx, G_HEAD, "Hair", Vector3.new(HEAD.X * 1.09, HEAD.Y * 0.9, HEAD.Z * 1.06), at(0, HY + 0.14, 0.07) * CFrame.Angles(math.rad(-15), 0, 0), hair, hairM, "Egg")
		return
	end
	-- calotte (inclinée : dégage le front) + nuque
	-- (ovale 1,04 x 0,9 x 1,1 du crâne, remonté de 0,14, reculé de 0,08, incliné
	-- de 15° : naissance des cheveux à ~0,23 au-dessus des yeux, tempes
	-- dégagées au-dessus des sourcils ; cherché numériquement)
	add(ctx, G_HEAD, "Hair", Vector3.new(HEAD.X * 1.09, HEAD.Y * 0.9, HEAD.Z * 1.1), at(0, HY + 0.14, 0.08) * CFrame.Angles(math.rad(-15), 0, 0), hair, hairM, "Egg")
	add(ctx, G_HEAD, "HairBack", Vector3.new(0.62, 0.62, 0.42), at(0, HY - 0.02, 0.2), dark, hairM, "Egg")
	if hs == "short" then
		add(ctx, G_HEAD, "Quiff", Vector3.new(0.5, 0.15, 0.3), at(0.03, HY + 0.37, -0.15) * CFrame.Angles(math.rad(-22), 0, 0), hair:Lerp(WHITE, 0.05), hairM, "Egg")
	elseif hs == "part" then
		-- raie sur le côté : mèche qui retombe
		add(ctx, G_HEAD, "Fringe", Vector3.new(0.56, 0.16, 0.34), at(0.07, HY + 0.32, -0.19) * CFrame.Angles(math.rad(-20), 0, -0.18), hair:Lerp(WHITE, 0.05), hairM, "Egg")
	elseif hs == "long" or hs == "bob" or hs == "pony" or hs == "bun" then
		for _, sx in ipairs({ -1, 1 }) do
			local len = hs == "long" and 0.95 or (hs == "bob" and 0.56 or 0.34)
			add(ctx, G_HEAD, "HairSideLock", Vector3.new(0.14, len, 0.36), at(sx * 0.34, HY + 0.2 - len / 2, 0.06) * CFrame.Angles(0, 0, sx * 0.05), hair, hairM, "Egg")
		end
		add(ctx, G_HEAD, "Fringe", Vector3.new(0.66, 0.22, 0.36), at(-0.05, HY + 0.32, -0.23) * CFrame.Angles(math.rad(-24), 0, 0.14), hair:Lerp(WHITE, 0.06), hairM, "Egg")
		if hs == "long" then
			add(ctx, G_HEAD, "HairLong", Vector3.new(0.72, 1.08, 0.3), at(0, HY - 0.34, 0.27) * CFrame.Angles(math.rad(8), 0, 0), dark, hairM, "Egg")
		elseif hs == "bob" then
			add(ctx, G_HEAD, "HairBob", Vector3.new(0.8, 0.46, 0.5), at(0, HY - 0.12, 0.16), dark, hairM, "Egg")
		elseif hs == "bun" then
			add(ctx, G_HEAD, "Bun", Vector3.new(0.32, 0.32, 0.32), at(0, HY + 0.34, 0.36), hair, hairM, "Ball")
		else
			add(ctx, G_HEAD, "Pony", Vector3.new(0.22, 0.72, 0.24), at(0, HY - 0.12, 0.5) * CFrame.Angles(math.rad(-16), 0, 0), dark, hairM, "Egg")
			add(ctx, G_HEAD, "Tie", Vector3.new(0.14, 0.09, 0.14), at(0, HY + 0.22, 0.43), pick({ rgb(236, 72, 140), rgb(90, 140, 230), rgb(250, 250, 250), rgb(40, 40, 44) }, seed, 22), M.SmoothPlastic, "Egg")
		end
	elseif hs == "curly" then
		for i = 0, 5 do
			local a = (i / 5 - 0.5) * 2.6
			add(ctx, G_HEAD, "Curl", Vector3.new(0.3, 0.3, 0.3), at(math.sin(a) * 0.3, HY + 0.3 + math.cos(a) * 0.1, 0.04 + math.abs(math.sin(a)) * 0.08 - (i % 2) * 0.1), i % 2 == 0 and hair or dark, hairM, "Ball")
		end
	elseif hs == "afro" then
		add(ctx, G_HEAD, "Afro", Vector3.new(0.98, 0.86, 0.96), at(0, HY + 0.24, 0.16), dark, KNIT, "Egg")
	end
end

----------------------------------------------------------------------
-- (v11) MAINS articulées : paume, rangée des jointures, 4 doigts à deux
-- phalanges (ovales qui se chevauchent : doigts arrondis, articulations
-- plus fines), pouce à deux phalanges. Poses : "relax", "flat", "grip",
-- "fist", "point", "phone", "cup". La main tourne au POIGNET (groupe
-- G_LHAND / G_RHAND) ; les doigts se replient (repos recalculé à la volée).
----------------------------------------------------------------------

-- Repère de la main au repos (bras le long du corps), échelle 1 :
--   origine = poignet ; U = vers le bout des doigts (bas) ; B = côté du
--   pouce (avant) ; N = normale de la paume (vers la cuisse).
local function wrist0(sx: number): Vector3
	return Vector3.new(sx * 0.745, 2.62, 0.02)
end
local U0 = Vector3.new(0, -1, 0)
local B0 = Vector3.new(0, 0, -1)
local function n0(sx: number): Vector3
	return Vector3.new(-sx, 0, 0)
end
local function handPt(sx: number, a: number, b: number, c: number): Vector3
	return wrist0(sx) + U0 * a + B0 * b + n0(sx) * c
end
NPCModels.Wrist = wrist0

-- doigts : index, majeur, annulaire, auriculaire
local FING_B = { 0.093, 0.031, -0.031, -0.09 } -- (écart le long de B)
local FING_A = { 0.3, 0.305, 0.3, 0.285 } -- (jointure le long de U)
local FING_W = { 0.08, 0.084, 0.079, 0.07 }
local FING_L1 = { 0.135, 0.15, 0.14, 0.11 }
local FING_L2 = { 0.125, 0.135, 0.125, 0.1 }
local FING_SPREAD = { 0.1, 0.02, -0.06, -0.14 }
local THUMB_BASE = Vector3.new(0.07, 0.115, 0.03) -- (a, b, c)
local THUMB_L = { 0.13, 0.12 }
local THUMB_W = { 0.094, 0.084 }

-- Poses : 4 doigts {repli de la jointure, repli des phalanges}, écartement,
-- direction du pouce (U, B, N) et repli du pouce
export type HandPose = { C: { { number } }, S: number, T: { number }, TC: number }
local HANDS: { [string]: HandPose } = {
	relax = { C = { { 0.25, 0.45 }, { 0.3, 0.5 }, { 0.36, 0.56 }, { 0.42, 0.62 } }, S = 0.35, T = { 0.78, 0.42, 0.42 }, TC = 0.25 },
	flat = { C = { { 0.06, 0.1 }, { 0.06, 0.1 }, { 0.08, 0.12 }, { 0.1, 0.14 } }, S = 0.4, T = { 0.7, 0.6, 0.1 }, TC = 0.05 },
	grip = { C = { { 1.25, 1.35 }, { 1.3, 1.35 }, { 1.3, 1.4 }, { 1.3, 1.45 } }, S = 0, T = { 0.5, 0.25, 0.85 }, TC = 0.45 },
	fist = { C = { { 1.55, 1.75 }, { 1.55, 1.75 }, { 1.55, 1.75 }, { 1.55, 1.8 } }, S = 0, T = { 0.45, 0.05, 0.9 }, TC = 0.6 },
	point = { C = { { 0.04, 0.06 }, { 1.5, 1.7 }, { 1.55, 1.75 }, { 1.55, 1.8 } }, S = 0.1, T = { 0.5, 0.0, 0.9 }, TC = 0.6 },
	phone = { C = { { 0.62, 0.9 }, { 0.58, 0.95 }, { 0.62, 0.95 }, { 0.7, 1.0 } }, S = 0.15, T = { 0.15, 0.95, 0.3 }, TC = 0.15 },
	cup = { C = { { 0.95, 0.7 }, { 0.95, 0.7 }, { 1.0, 0.75 }, { 1.05, 0.8 } }, S = 0.1, T = { 0.35, 0.55, 0.8 }, TC = 0.2 },
}
NPCModels.HandPoses = HANDS

-- Pose -> 13 nombres (fondu d'une pose à l'autre)
local function handVec(name: string?): { number }
	local h = HANDS[name or "relax"] or HANDS.relax
	local v = table.create(13, 0)
	for f = 1, 4 do
		v[f * 2 - 1] = h.C[f][1]
		v[f * 2] = h.C[f][2]
	end
	v[9] = h.S
	v[10], v[11], v[12] = h.T[1], h.T[2], h.T[3]
	v[13] = h.TC
	return v
end

-- repère d'un segment (axe Y = direction) au point p
local function segCF(p: Vector3, d: Vector3): CFrame
	local x = B0 - d * d:Dot(B0)
	if x.Magnitude < 1e-3 then
		x = Vector3.new(1, 0, 0)
	end
	return CFrame.fromMatrix(p, x.Unit, d)
end

-- Repos (échelle 1, repère du pivot) d'une phalange : doigt f (1..4,
-- 5 = pouce), segment g (1, 2), pose v (handVec)
local function fingerRest(sx: number, f: number, g: number, v: { number }): CFrame
	local N = n0(sx)
	if f == 5 then
		local base = handPt(sx, THUMB_BASE.X, THUMB_BASE.Y, THUMB_BASE.Z)
		local d1 = (U0 * v[10] + B0 * v[11] + N * v[12])
		d1 = d1.Magnitude > 1e-3 and d1.Unit or U0
		if g == 1 then
			return segCF(base + d1 * THUMB_L[1] / 2, d1)
		end
		local perp = N - d1 * d1:Dot(N)
		perp = perp.Magnitude > 1e-3 and perp.Unit or N
		local c = v[13] + 0.15
		local d2 = d1 * math.cos(c) + perp * math.sin(c)
		return segCF(base + d1 * THUMB_L[1] + d2 * THUMB_L[2] / 2, d2)
	end
	local sg = FING_SPREAD[f] * v[9]
	local u = U0 * math.cos(sg) + B0 * math.sin(sg)
	local k = handPt(sx, FING_A[f], FING_B[f], 0)
	local t1 = v[f * 2 - 1]
	local d1 = u * math.cos(t1) + N * math.sin(t1)
	if g == 1 then
		return segCF(k + d1 * FING_L1[f] / 2, d1)
	end
	local t2 = t1 + v[f * 2]
	local d2 = u * math.cos(t2) + N * math.sin(t2)
	return segCF(k + d1 * FING_L1[f] + d2 * FING_L2[f] / 2, d2)
end

-- Taille d'une phalange (ovale : un peu plus longue que l'os, chevauchement)
local function fingerSize(f: number, g: number): Vector3
	if f == 5 then
		local w = THUMB_W[g]
		return Vector3.new(w, THUMB_L[g] + w * 0.9, w * 0.92)
	end
	local w = FING_W[f] * (g == 1 and 1 or 0.92)
	local l = g == 1 and FING_L1[f] or FING_L2[f]
	return Vector3.new(w, l + w * 0.9, w * 0.9)
end

-- Repère de la main (U, B) -> CFrame (X = U, Y = B, Z = U x B)
local function handFrame(u: Vector3, b: Vector3): CFrame
	local bb = b - u * u:Dot(b)
	if bb.Magnitude < 1e-3 then
		bb = Vector3.new(0, 1, 0) - u * u.Y
		if bb.Magnitude < 1e-3 then
			bb = Vector3.new(1, 0, 0)
		end
	end
	return CFrame.fromMatrix(Vector3.zero, u, bb.Unit)
end
local HAND_M0 = handFrame(U0, B0)
local HAND_M0_INV = HAND_M0:Inverse()

-- Main complète (12 pièces) dans le groupe de l'avant-bras (attribut NpcG,
-- compatible avec les modules qui lisent les groupes) + attributs de la
-- main (NpcHand = côté, NpcFinger, NpcSeg) pour l'animation des doigts
local function hand(ctx: Ctx, sx: number, skin: Color3, poseName: string?)
	local lo = sx < 0 and G_LLO or G_RLO
	local v = handVec(poseName)
	local knuckle = skin:Lerp(rgb(200, 120, 110), 0.06)
	-- paume (X = B, Y = U : épaisseur selon N)
	local palm = add(ctx, lo, "Palm", Vector3.new(0.26, 0.27, 0.1), CFrame.fromMatrix(handPt(sx, 0.15, 0, 0), B0, U0), skin, M.SmoothPlastic)
	palm:SetAttribute("NpcHand", sx)
	palm:SetAttribute("NpcFinger", 0)
	-- talon de la main (arrondi côté poignet) + rangée des jointures
	local heel = add(ctx, lo, "PalmHeel", Vector3.new(0.25, 0.1, 0.1), CFrame.fromMatrix(handPt(sx, 0.03, 0, 0), B0, U0), skin, M.SmoothPlastic, "Cyl")
	heel:SetAttribute("NpcHand", sx)
	heel:SetAttribute("NpcFinger", -1)
	local kn = add(ctx, lo, "Knuckles", Vector3.new(0.26, 0.104, 0.104), CFrame.fromMatrix(handPt(sx, 0.285, 0, 0), B0, U0), knuckle, M.SmoothPlastic, "Cyl")
	kn:SetAttribute("NpcHand", sx)
	kn:SetAttribute("NpcFinger", -1)
	for f = 1, 5 do
		for g = 1, 2 do
			local part = add(ctx, lo, f == 5 and "Thumb" or "Finger", fingerSize(f, g), fingerRest(sx, f, g, v), skin, M.SmoothPlastic, "Egg")
			part.CastShadow = false
			part:SetAttribute("NpcHand", sx)
			part:SetAttribute("NpcFinger", f)
			part:SetAttribute("NpcSeg", g)
		end
	end
end


----------------------------------------------------------------------
-- Corps
----------------------------------------------------------------------

-- Bras : épaule (deltoïde), bras, coude, avant-bras, main (paume, doigts,
-- POUCE) ; manches courtes (ourlet) ou longues (poignet)
local function arm(ctx: Ctx, sx: number, sleeve: Color3, skin: Color3, longSleeve: boolean, cuff: Color3?, handPoseName: string?, bare: boolean?)
	local up = sx < 0 and G_LUP or G_RUP
	local lo = sx < 0 and G_LLO or G_RLO
	local x = sx * 0.73
	add(ctx, up, "Deltoid", Vector3.new(0.42, 0.42, 0.42), at(sx * 0.65, 4.1, 0), bare and skin or sleeve, bare and M.SmoothPlastic or CLOTH, "Ball")
	add(ctx, up, "UpperArm", Vector3.new(0.84, 0.34, 0.34), cylY(sx * 0.72, 3.72, 0.01), (longSleeve and not bare) and sleeve or skin, (longSleeve and not bare) and CLOTH or M.SmoothPlastic, "Cyl")
	if not longSleeve and not bare then
		-- manche courte : ourlet un peu plus large
		add(ctx, up, "Sleeve", Vector3.new(0.4, 0.42, 0.42), cylY(sx * 0.72, 3.9, 0.01), sleeve, CLOTH, "Cyl")
		add(ctx, up, "SleeveHem", Vector3.new(0.05, 0.43, 0.43), cylY(sx * 0.72, 3.72, 0.01), sleeve:Lerp(INK, 0.12), CLOTH, "Cyl")
	end
	add(ctx, lo, "Elbow", Vector3.new(0.33, 0.33, 0.33), at(x, 3.32, 0.02), longSleeve and sleeve or skin, longSleeve and CLOTH or M.SmoothPlastic, "Ball")
	add(ctx, lo, "Forearm", Vector3.new(0.72, 0.3, 0.3), cylY(x, 2.97, 0.02), longSleeve and sleeve or skin, longSleeve and CLOTH or M.SmoothPlastic, "Cyl")
	if longSleeve then
		add(ctx, lo, "Cuff", Vector3.new(0.12, 0.33, 0.33), cylY(x, 2.63, 0.02), cuff or sleeve:Lerp(INK, 0.1), CLOTH, "Cyl")
	end
	-- (v11) main articulée : paume, jointures, doigts, pouce
	hand(ctx, sx, skin, handPoseName)
end

-- Jambes : cuisse, genou, tibia, mollet, ourlet ; pied : chaussure, bout
-- arrondi, semelle, lacets
local function legs(ctx: Ctx, look: Look, pants: Color3, shorts: boolean, bareThigh: boolean?)
	local skin = look.Skin
	for _, sx in ipairs({ -1, 1 }) do
		local th = sx < 0 and G_LTH or G_RTH
		local sh = sx < 0 and G_LSH or G_RSH
		local ft = sx < 0 and G_LFT or G_RFT
		local x = sx * 0.27
		local thighC = bareThigh and skin or pants
		local thighM = bareThigh and M.SmoothPlastic or CLOTH
		add(ctx, th, "Thigh", Vector3.new(1.2, 0.5, 0.5), cylY(x, 2.02, 0), thighC, thighM, "Cyl")
		if shorts and not bareThigh then
			add(ctx, th, "ShortsHem", Vector3.new(0.1, 0.54, 0.54), cylY(x, 1.66, 0), pants:Lerp(INK, 0.12), CLOTH, "Cyl")
		end
		local legC = shorts and skin or pants
		local legM = shorts and M.SmoothPlastic or CLOTH
		add(ctx, sh, "Knee", Vector3.new(0.42, 0.42, 0.42), at(x, 1.5, 0), (shorts or bareThigh) and skin or pants, (shorts or bareThigh) and M.SmoothPlastic or CLOTH, "Ball")
		add(ctx, sh, "Shin", Vector3.new(1.1, 0.38, 0.38), cylY(x, 0.93, 0.02), legC, legM, "Cyl")
		add(ctx, sh, "Calf", Vector3.new(0.32, 0.6, 0.34), at(x, 1.14, 0.08), legC, legM, "Egg")
		if not shorts then
			add(ctx, sh, "Hem", Vector3.new(0.09, 0.43, 0.43), cylY(x, 0.395, 0.02), pants:Lerp(INK, 0.1), CLOTH, "Cyl")
		else
			add(ctx, sh, "Sock", Vector3.new(0.14, 0.4, 0.4), cylY(x, 0.41, 0.02), WHITE, CLOTH, "Cyl")
		end
		-- pied (tourne à la cheville)
		-- (v11) chaussure ARRONDIE (fini les "pavés" de la capture 32) : tige
		-- ovale, bout rond, semelle en "stade" (bloc + bout + talon ronds)
		add(ctx, ft, "Shoe", Vector3.new(0.36, 0.3, 0.76), at(x, 0.21, -0.15), look.Shoe, M.SmoothPlastic, "Egg")
		add(ctx, ft, "ToeCap", Vector3.new(0.33, 0.21, 0.36), at(x, 0.165, -0.43), look.Shoe:Lerp(INK, 0.06), M.SmoothPlastic, "Egg")
		add(ctx, ft, "Heel", Vector3.new(0.3, 0.26, 0.3), at(x, 0.21, 0.08), look.Shoe:Lerp(INK, 0.08), M.SmoothPlastic, "Egg")
		add(ctx, ft, "Sole", Vector3.new(0.37, 0.075, 0.5), at(x, 0.045, -0.17), look.Sole, M.Rubber)
		add(ctx, ft, "SoleToe", Vector3.new(0.075, 0.37, 0.37), cylY(x, 0.045, -0.42), look.Sole, M.Rubber, "Cyl")
		add(ctx, ft, "SoleHeel", Vector3.new(0.075, 0.34, 0.34), cylY(x, 0.045, 0.08), look.Sole, M.Rubber, "Cyl")
		add(ctx, ft, "Laces", Vector3.new(0.14, 0.035, 0.26), at(x, 0.345, -0.27) * CFrame.Angles(math.rad(-16), 0, 0), look.Shoe:Lerp(WHITE, 0.55), CLOTH)
	end
end

-- Buste + bassin + cou + col / coutures
local function torso(ctx: Ctx, look: Look, shirt: Color3, pants: Color3, skirt: boolean, style: string, seed: number)
	local skin = look.Skin
	local female = look.Female
	-- sections en "stade" (bloc + 2 cylindres debout) : torse arrondi, sans
	-- arêtes vives ni bosses ovales qui dépassent
	local function stadium(g: number, name: string, width: number, depth: number, y0: number, y1: number, color: Color3, z: number?)
		local h = y1 - y0
		local y = (y0 + y1) / 2
		local zz = z or 0
		add(ctx, g, name, Vector3.new(width - depth, h, depth), at(0, y, zz), color, CLOTH)
		for _, sx in ipairs({ -1, 1 }) do
			add(ctx, g, name .. "Side", Vector3.new(h, depth, depth), cylY(sx * (width - depth) / 2, y, zz), color, CLOTH, "Cyl")
		end
	end
	stadium(G_CHEST, "Chest", female and 1.06 or 1.16, female and 0.5 or 0.52, 3.36, 4.2, shirt)
	-- ligne des épaules (arrondie)
	add(ctx, G_CHEST, "Shoulders", Vector3.new(1.0, 0.44, 0.44), at(0, 4.14, 0.0), shirt, CLOTH, "Cyl")
	if female then
		add(ctx, G_CHEST, "Bust", Vector3.new(0.5, 0.32, 0.32), at(0, 3.9, -0.12), shirt, CLOTH, "Cyl")
	end
	stadium(G_CHEST, "Belly", female and 0.9 or 1.02, female and 0.46 or 0.48, 2.9, 3.4, shirt)
	add(ctx, G_CHEST, "Neck", Vector3.new(0.36, 0.3, 0.3), cylY(0, 4.44, 0.03), skin, M.SmoothPlastic, "Cyl")
	-- col
	local col = look.Collar
	if col == "crew" then
		add(ctx, G_CHEST, "Collar", Vector3.new(0.07, 0.4, 0.4), cylY(0, 4.36, 0.03), shirt:Lerp(INK, 0.1), CLOTH, "Cyl")
	elseif col == "v" then
		for _, sx in ipairs({ -1, 1 }) do
			add(ctx, G_CHEST, "Collar", Vector3.new(0.05, 0.2, 0.04), at(sx * 0.06, 4.24, -0.29) * CFrame.Angles(0, 0, sx * 0.55), shirt:Lerp(INK, 0.14), CLOTH)
		end
	elseif col == "polo" or col == "shirt" then
		local cc = col == "polo" and shirt:Lerp(WHITE, 0.12) or shirt
		for _, sx in ipairs({ -1, 1 }) do
			add(ctx, G_CHEST, "Collar", Vector3.new(0.2, 0.06, 0.24), at(sx * 0.13, 4.35, -0.14) * CFrame.Angles(math.rad(-22), sx * 0.4, sx * -0.3), cc, CLOTH)
		end
		add(ctx, G_CHEST, "Placket", Vector3.new(0.1, col == "polo" and 0.36 or 1.0, 0.03), at(0, col == "polo" and 4.1 or 3.62, -0.3), shirt:Lerp(INK, 0.08), CLOTH)
		for i = 0, (col == "polo" and 1 or 3) do
			add(ctx, G_CHEST, "Button", Vector3.new(0.05, 0.05, 0.03), at(0, 4.18 - i * 0.24, -0.325), shirt:Lerp(WHITE, 0.5), M.SmoothPlastic, "Ball")
		end
		if col == "shirt" and hash(seed, 80) < 0.6 then
			add(ctx, G_CHEST, "Pocket", Vector3.new(0.22, 0.24, 0.03), at(-0.26, 3.86, -0.3), shirt:Lerp(INK, 0.06), CLOTH)
		end
	end
	-- bassin + fessiers (ou jupe)
	local hipW = female and 1.08 or 1.0
	local hipD = female and 0.54 or 0.52
	stadium(G_PELVIS, "Pelvis", hipW, hipD, 2.46, 2.94, pants)
	if skirt then
		-- jupe en corolle (s'arrête au-dessus du genou)
		add(ctx, G_PELVIS, "Skirt", Vector3.new(1.18, 1.1, 0.82), at(0, 2.32, 0.01), pants, CLOTH, "Egg")
	else
		add(ctx, G_PELVIS, "Glutes", Vector3.new(hipW - 0.4, 0.42, 0.42), at(0, 2.6, 0.09), pants, CLOTH, "Cyl")
		add(ctx, G_PELVIS, "Crotch", Vector3.new(0.4, 0.3, 0.44), at(0, 2.42, 0), pants, CLOTH, "Egg")
	end
	if look.Belt and style ~= "baker" and not skirt then
		-- ceinture tout autour (même "stade", un peu plus large) + boucle
		local belt = rgb(56, 38, 28)
		add(ctx, G_PELVIS, "Belt", Vector3.new(hipW - hipD, 0.1, hipD + 0.06), at(0, 2.86, 0), belt, M.Leather)
		for _, sx in ipairs({ -1, 1 }) do
			add(ctx, G_PELVIS, "BeltSide", Vector3.new(0.1, hipD + 0.06, hipD + 0.06), cylY(sx * (hipW - hipD) / 2, 2.86, 0), belt, M.Leather, "Cyl")
		end
		add(ctx, G_PELVIS, "Buckle", Vector3.new(0.14, 0.1, 0.03), at(0, 2.86, -hipD / 2 - 0.045), rgb(196, 182, 150), M.Metal)
	end
	return skin
end

----------------------------------------------------------------------
-- Tenues par style
----------------------------------------------------------------------

local function baseLook(style: string, seed: number, opts: Opts): Look
	local female = hash(seed, 1) < 0.5
	local hairStyle = female and pick(HAIR_F, seed, 2) or pick(HAIR_M, seed, 2)
	local hair = pick(HAIRS, seed, 4)
	local skin = opts.Skin or pick(SKINS, seed, 7)
	-- (cheveux crépus / afro plus fréquents avec les peaux foncées, jamais imposés)
	if hairStyle == "afro" and hash(seed, 3) < 0.5 then
		hairStyle = female and "curly" or "short"
	end
	local beard = "none"
	if not female and style ~= "kid" then
		local b = hash(seed, 14)
		beard = b < 0.12 and "beard" or (b < 0.2 and "mustache" or "none")
	end
	local glasses = style ~= "kid" and hash(seed, 15) < 0.18
	if style == "elder" then
		hair = pick(GREYS, seed, 5)
		if not female and hash(seed, 6) < 0.45 then
			hairStyle = "bald"
		elseif female then
			hairStyle = hash(seed, 6) < 0.5 and "bun" or "bob"
		end
		glasses = hash(seed, 57) < 0.6
	end
	local collars = { "crew", "crew", "v", "shirt", "polo", "crew" }
	local sole = pick({ rgb(236, 232, 224), rgb(40, 36, 36), rgb(170, 120, 70) }, seed, 16)
	return {
		Skin = skin,
		Hair = opts.Hair or hair,
		HairStyle = hairStyle,
		Shirt = opts.Shirt or vary(pick(SHIRTS, seed, 8), seed, 17),
		Pants = opts.Pants or vary(pick(PANTS, seed, 9), seed, 18),
		Shoe = pick(SHOES, seed, 10),
		Sole = sole,
		Female = female,
		LongSleeve = hash(seed, 11) < 0.45,
		Shorts = false,
		Skirt = female and hash(seed, 12) < 0.3,
		Belt = hash(seed, 13) < 0.55,
		Collar = pick(collars, seed, 19),
		Beard = beard,
		Glasses = glasses,
		Iris = pick(IRIS, seed, 21),
	}
end

-- (v11) Objets tenus : posés DANS la main (repère de la main : U, B, N),
-- ils suivent le poignet ; la main prend la pose qui va avec
-- ("phone", "cup", "grip", "flat")
local PROP_HAND: { [string]: { number | string } } = {
	phone = { 1, "phone" },
	coffee = { 1, "cup" },
	bag = { 1, "grip" },
	cane = { 1, "grip" },
	tablet = { -1, "flat" },
	leash = { -1, "grip" },
}
NPCModels.PropHands = PROP_HAND

-- pièce rigide de la main `sx` : centre (a, b, c), axes X / Y donnés dans le
-- repère de repos
local function handProp(ctx: Ctx, sx: number, name: string, size: Vector3, a: number, b: number, c: number, ax: Vector3, ay: Vector3, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local lo = sx < 0 and G_LLO or G_RLO
	local p = add(ctx, lo, name, size, CFrame.fromMatrix(handPt(sx, a, b, c), ax, ay), color, material, shape)
	p:SetAttribute("NpcHand", sx)
	p:SetAttribute("NpcFinger", -1)
	return p
end

-- Écran de téléphone : appli de messages / vidéo / carte (que des Frame),
-- lumineux (LightInfluence 0 : il "éclaire" dans la pénombre)
local function phoneScreen(part: BasePart, face: Enum.NormalId, seed: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 260
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.MaxDistance = 70
	gui.ClipsDescendants = true
	gui.Parent = part
	local app = math.floor(hash(seed, 90) * 3)
	local bg = app == 0 and rgb(236, 240, 246) or (app == 1 and rgb(18, 18, 24) or rgb(214, 230, 206))
	local root = frame(gui, "Bg", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), bg, 0.12)
	frame(root, "Status", UDim2.fromScale(1, 0.07), UDim2.fromScale(0.5, 0.035), app == 1 and rgb(10, 10, 14) or rgb(60, 110, 210))
	frame(root, "Notch", UDim2.fromScale(0.3, 0.025), UDim2.fromScale(0.5, 0.02), rgb(8, 8, 10), 1)
	if app == 0 then
		-- messages : bulles grises / bleues
		for i = 0, 3 do
			local mine = (i + seed) % 2 == 0
			local w = 0.45 + hash(seed, 91 + i) * 0.3
			frame(root, "Bubble", UDim2.fromScale(w, 0.1), UDim2.fromScale(mine and (1 - w / 2 - 0.05) or (w / 2 + 0.05), 0.18 + i * 0.16), mine and rgb(52, 132, 250) or rgb(206, 210, 218), 0.4)
		end
		frame(root, "Input", UDim2.fromScale(0.9, 0.07), UDim2.fromScale(0.5, 0.92), WHITE, 0.5)
	elseif app == 1 then
		-- vidéo : image + barre de lecture + commentaires
		local vid = frame(root, "Video", UDim2.fromScale(1, 0.34), UDim2.fromScale(0.5, 0.26), pick({ rgb(230, 120, 70), rgb(80, 170, 220), rgb(120, 200, 120) }, seed, 92))
		frame(vid, "Sun", UDim2.fromScale(0.22, 0.3), UDim2.fromScale(0.7, 0.35), rgb(255, 230, 140), 1)
		frame(vid, "Hill", UDim2.fromScale(1.2, 0.5), UDim2.fromScale(0.4, 0.95), rgb(40, 110, 70), 1)
		frame(root, "Bar", UDim2.fromScale(0.9, 0.012), UDim2.fromScale(0.5, 0.45), rgb(90, 90, 96))
		frame(root, "BarDone", UDim2.fromScale(0.4, 0.012), UDim2.fromScale(0.25, 0.45), rgb(240, 60, 60))
		for i = 0, 2 do
			frame(root, "Line", UDim2.fromScale(0.8 - i * 0.12, 0.035), UDim2.fromScale(0.45, 0.56 + i * 0.09), rgb(70, 70, 78), 0.5)
		end
	else
		-- carte : rues + itinéraire + point bleu
		for i = 0, 3 do
			frame(root, "Street", UDim2.fromScale(1, 0.025), UDim2.fromScale(0.5, 0.2 + i * 0.2), WHITE)
			frame(root, "Avenue", UDim2.fromScale(0.035, 1), UDim2.fromScale(0.15 + i * 0.25, 0.5), WHITE)
		end
		frame(root, "Route", UDim2.fromScale(0.04, 0.42), UDim2.fromScale(0.4, 0.6), rgb(60, 130, 250))
		frame(root, "Me", UDim2.fromScale(0.09, 0.09), UDim2.fromScale(0.4, 0.8), rgb(40, 110, 250), 1, true)
	end
end

local function prop(ctx: Ctx, kind: string, seed: number)
	local sx = 1
	if kind == "bag" then
		-- sac de courses : anse dans le poing, sac qui pend (à l'extérieur de la jambe)
		local c = pick({ rgb(236, 72, 140), rgb(250, 250, 248), rgb(120, 190, 90), rgb(90, 140, 230), rgb(206, 166, 118) }, seed, 30)
		local N = n0(sx)
		handProp(ctx, sx, "Bag", Vector3.new(0.78, 0.84, 0.3), 0.98, 0, -0.1, B0, U0, c, M.SmoothPlastic)
		handProp(ctx, sx, "BagFold", Vector3.new(0.82, 0.1, 0.34), 0.62, 0, -0.1, B0, U0, c:Lerp(INK, 0.15), M.SmoothPlastic)
		for _, bb in ipairs({ -1, 1 }) do
			local top = handPt(sx, 0.57, bb * 0.22, -0.1)
			local g = handPt(sx, 0.31, bb * 0.03, 0.06)
			local mid = (top + g) / 2
			local dir = (g - top).Unit
			local p = add(ctx, G_RLO, "BagHandle", Vector3.new(0.05, (g - top).Magnitude + 0.04, 0.05), CFrame.fromMatrix(mid, N:Cross(dir).Unit, dir), c:Lerp(INK, 0.35), M.SmoothPlastic)
			p:SetAttribute("NpcHand", sx)
			p:SetAttribute("NpcFinger", -1)
		end
	elseif kind == "phone" then
		-- smartphone (×1,3) : coque, écran lumineux bord à bord, objectifs ;
		-- couché dans la paume, écran vers le visage (N), haut vers le pouce
		local case = pick({ rgb(28, 28, 34), rgb(220, 220, 226), rgb(236, 120, 150), rgb(60, 90, 160), rgb(200, 170, 120) }, seed, 31)
		local body = handProp(ctx, sx, "Phone", Vector3.new(0.27, 0.54, 0.05), 0.2, 0.03, 0.084, U0, B0, case, M.SmoothPlastic)
		body.CastShadow = false
		-- (Z du repère = U x B = +X : l'écran (côté N = -X, main droite) est la face Front)
		local scr = handProp(ctx, sx, "PhoneScreen", Vector3.new(0.245, 0.51, 0.01), 0.2, 0.03, 0.113, U0, B0, rgb(10, 10, 14), M.SmoothPlastic)
		phoneScreen(scr, sx > 0 and Enum.NormalId.Front or Enum.NormalId.Back, seed)
	elseif kind == "coffee" then
		-- gobelet tenu à pleine main (axe vers le pouce = vertical quand l'avant-bras est à plat)
		handProp(ctx, sx, "Cup", Vector3.new(0.42, 0.26, 0.26), 0.2, 0.02, 0.19, B0, U0, WHITE, M.SmoothPlastic, "Cyl")
		handProp(ctx, sx, "CupSleeve", Vector3.new(0.17, 0.28, 0.28), 0.2, 0.0, 0.19, B0, U0, rgb(170, 120, 80), M.Cardboard, "Cyl")
		handProp(ctx, sx, "CupLid", Vector3.new(0.05, 0.28, 0.28), 0.2, 0.235, 0.19, B0, U0, rgb(60, 50, 50), M.SmoothPlastic, "Cyl")
	elseif kind == "cane" then
		-- canne : poignée en crosse dans le poing, fût vers le sol
		local wood = rgb(104, 66, 40)
		handProp(ctx, sx, "Cane", Vector3.new(0.1, 2.2, 0.1), 0.31 + 1.06, 0, 0.075, B0, U0, wood, M.Wood)
		handProp(ctx, sx, "CaneGrip", Vector3.new(0.36, 0.1, 0.1), 0.27, 0.12, 0.075, B0, U0, wood, M.Wood, "Cyl")
		handProp(ctx, sx, "CaneTip", Vector3.new(0.12, 0.13, 0.13), 2.43, 0, 0.075, U0, B0, rgb(30, 28, 28), M.Rubber, "Cyl")
	elseif kind == "tablet" then
		-- (main GAUCHE, paume vers le haut : la tablette repose dessus, écran vers le haut)
		local l = -1
		local N = n0(l)
		handProp(ctx, l, "Tablet", Vector3.new(0.86, 0.66, 0.06), 0.24, 0.0, 0.085, B0, U0, rgb(40, 40, 46), M.SmoothPlastic)
		local scr = handProp(ctx, l, "TabletScreen", Vector3.new(0.78, 0.58, 0.01), 0.24, 0.0, 0.12, B0, U0, rgb(150, 210, 255), M.SmoothPlastic)
		-- (X = B, Y = U -> Z = B x U = -X : N = +X pour la main gauche = face Front)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "ScreenGui"
		gui.Face = N.X > 0 and Enum.NormalId.Front or Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 120
		gui.LightInfluence = 0
		gui.Brightness = 1.4
		gui.MaxDistance = 60
		gui.Parent = scr
		local root = frame(gui, "Bg", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), rgb(236, 242, 250), 0.04)
		frame(root, "Head", UDim2.fromScale(1, 0.14), UDim2.fromScale(0.5, 0.07), rgb(60, 110, 210))
		for i = 0, 2 do
			frame(root, "Card", UDim2.fromScale(0.27, 0.5), UDim2.fromScale(0.18 + i * 0.32, 0.5), WHITE, 0.08)
			frame(root, "Pic", UDim2.fromScale(0.22, 0.25), UDim2.fromScale(0.18 + i * 0.32, 0.42), pick({ rgb(240, 160, 90), rgb(120, 190, 240), rgb(140, 210, 140) }, seed + i, 93), 0.1)
		end
		frame(root, "Btn", UDim2.fromScale(0.4, 0.1), UDim2.fromScale(0.5, 0.86), rgb(240, 90, 80), 0.5)
	elseif kind == "leash" then
		-- poignée de la laisse dans le poing gauche (la laisse elle-même est
		-- tracée par l'appelant : NPCModels.HandPoint)
		handProp(ctx, -1, "LeashLoop", Vector3.new(0.05, 0.3, 0.3), 0.31, 0, 0.075, B0, U0, rgb(220, 50, 70), M.SmoothPlastic, "Cyl")
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
	local scale = o.Scale or 1
	local hs = 1.06 -- (tête un peu plus grande : "mignon-réaliste")
	if style == "kid" and o.Scale == nil then
		scale = 0.6 + hash(seed, 40) * 0.1
		hs = 1.28
	elseif o.Scale == nil then
		-- tailles variées : 0,94 à 1,05
		scale = 0.94 + hash(seed, 41) * 0.11
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
		pants = o.Pants or rgb(44, 48, 60)
		look.Collar = "polo"
		look.Belt = true
		table.insert(extras, function()
			-- badge + cordon + visière
			add(ctx, G_CHEST, "Badge", Vector3.new(0.26, 0.16, 0.03), at(0.27, 3.86, -0.3), WHITE, M.SmoothPlastic)
			add(ctx, G_CHEST, "BadgeStripe", Vector3.new(0.26, 0.04, 0.03), at(0.27, 3.92, -0.315), shirt, M.SmoothPlastic)
			add(ctx, G_HEAD, "Visor", Vector3.new(0.8, 0.12, 0.88), at(0, HY + 0.25, 0.02), shirt, M.SmoothPlastic, "Egg")
			add(ctx, G_HEAD, "VisorBrim", Vector3.new(0.56, 0.04, 0.34), at(0, HY + 0.24, -0.46) * CFrame.Angles(math.rad(10), 0, 0), shirt:Lerp(INK, 0.15), M.SmoothPlastic)
		end)
	elseif style == "baker" then
		shirt = WHITE
		sleeve, longSleeve, skirt = WHITE, true, false
		pants = o.Pants or rgb(58, 58, 68)
		cuff = rgb(228, 228, 224)
		look.Collar = "none"
		-- (v11) cheveux ras sous la toque (plus de mèche qui dépasse)
		if look.HairStyle ~= "bald" then
			look.HairStyle = "buzz"
		end
		table.insert(extras, function()
			-- veste croisée (2 rangées de boutons), col officier, tablier, toque plissée
			add(ctx, G_CHEST, "Collar", Vector3.new(0.12, 0.42, 0.42), cylY(0, 4.34, 0.03), rgb(236, 236, 232), CLOTH, "Cyl")
			for i = 0, 2 do
				for _, bx in ipairs({ -0.2, 0.2 }) do
					add(ctx, G_CHEST, "Button", Vector3.new(0.06, 0.06, 0.04), at(bx, 4.02 - i * 0.26, -0.3), rgb(200, 200, 196), M.SmoothPlastic, "Ball")
				end
			end
			add(ctx, G_CHEST, "Apron", Vector3.new(0.9, 0.62, 0.04), at(0, 3.08, -0.28), rgb(232, 188, 128), CLOTH)
			add(ctx, G_PELVIS, "ApronSkirt", Vector3.new(1.0, 1.1, 0.04), at(0, 2.3, -0.3), rgb(232, 188, 128), CLOTH)
			add(ctx, G_PELVIS, "ApronTie", Vector3.new(1.02, 0.07, 0.68), at(0, 2.86, 0), rgb(214, 170, 112), CLOTH)
			add(ctx, G_HEAD, "Toque", Vector3.new(0.5, 0.74, 0.74), cylY(0, HY + 0.52, 0.03), WHITE, CLOTH, "Cyl")
			add(ctx, G_HEAD, "ToquePuff", Vector3.new(0.92, 0.46, 0.92), at(0, HY + 0.82, 0.03), WHITE, CLOTH, "Egg")
			add(ctx, G_HEAD, "ToqueBand", Vector3.new(0.14, 0.77, 0.77), cylY(0, HY + 0.33, 0.03), rgb(236, 236, 232), CLOTH, "Cyl")
		end)
	elseif style == "salesperson" then
		local jacket = o.Shirt or pick({ rgb(36, 44, 70), rgb(40, 40, 44), rgb(90, 90, 100), rgb(64, 50, 44) }, seed, 51)
		shirt, sleeve, longSleeve, skirt = jacket, jacket, true, false
		pants = o.Pants or jacket
		cuff = WHITE
		look.Collar = "none"
		look.Belt = false
		propKind = propKind or "tablet"
		table.insert(extras, function()
			-- chemise en V + cravate + revers + pochette + boutons
			local tieC = pick({ rgb(180, 36, 56), rgb(220, 70, 130), rgb(50, 96, 180), rgb(30, 30, 34) }, seed, 52)
			add(ctx, G_CHEST, "ShirtFront", Vector3.new(0.3, 0.5, 0.04), at(0, 4.04, -0.285), WHITE, CLOTH)
			add(ctx, G_CHEST, "Tie", Vector3.new(0.1, 0.52, 0.03), at(0, 3.98, -0.31), tieC, CLOTH)
			add(ctx, G_CHEST, "TieKnot", Vector3.new(0.12, 0.09, 0.05), at(0, 4.25, -0.3), tieC:Lerp(INK, 0.2), CLOTH)
			for _, sx in ipairs({ -1, 1 }) do
				add(ctx, G_CHEST, "Lapel", Vector3.new(0.12, 0.62, 0.04), at(sx * 0.19, 4.0, -0.305) * CFrame.Angles(0, 0, sx * 0.34), jacket:Lerp(INK, 0.25), CLOTH)
				add(ctx, G_CHEST, "ShirtCollar", Vector3.new(0.14, 0.06, 0.2), at(sx * 0.1, 4.33, -0.15) * CFrame.Angles(math.rad(-22), sx * 0.4, sx * -0.3), WHITE, CLOTH)
			end
			add(ctx, G_CHEST, "Pocket", Vector3.new(0.18, 0.08, 0.04), at(-0.33, 3.95, -0.285), WHITE, M.SmoothPlastic)
			add(ctx, G_CHEST, "JacketButton", Vector3.new(0.06, 0.06, 0.04), at(0, 3.3, -0.26), rgb(30, 30, 30), M.SmoothPlastic, "Ball")
		end)
		look.Shoe = rgb(36, 26, 24)
		look.Sole = rgb(26, 22, 22)
	elseif style == "shopper" then
		propKind = propKind or "bag"
	elseif style == "jogger" then
		shirt = o.Shirt or pick({ rgb(255, 120, 60), rgb(80, 200, 160), rgb(236, 72, 140), rgb(90, 150, 240) }, seed, 53)
		sleeve, longSleeve, skirt, shorts = shirt, false, false, true
		pants = o.Pants or rgb(38, 42, 52)
		look.Shoe = pick({ rgb(250, 250, 250), rgb(255, 90, 90), rgb(90, 200, 255) }, seed, 54)
		look.Sole = WHITE
		look.Belt = false
		look.Collar = "crew"
		table.insert(extras, function()
			add(ctx, G_HEAD, "Headband", Vector3.new(0.12, 0.74, 0.8), cylY(0, HY + 0.17, 0.03) * CFrame.Angles(0, 0, math.rad(-14)), WHITE, CLOTH, "Cyl")
			add(ctx, G_LLO, "Watch", Vector3.new(0.1, 0.32, 0.32), cylY(-0.73, 2.7, 0.02), rgb(40, 40, 46), M.SmoothPlastic, "Cyl")
		end)
	elseif style == "elder" then
		shirt = o.Shirt or pick({ rgb(150, 120, 100), rgb(120, 130, 150), rgb(160, 90, 90), rgb(110, 130, 100), rgb(200, 190, 170) }, seed, 55)
		sleeve, longSleeve = shirt, true
		look.Collar = "v"
		propKind = propKind or (hash(seed, 56) < 0.5 and "cane" or nil)
		table.insert(extras, function()
			-- gilet boutonné (cardigan)
			add(ctx, G_CHEST, "Placket", Vector3.new(0.1, 1.05, 0.03), at(0, 3.55, -0.3), shirt:Lerp(INK, 0.12), CLOTH)
			for i = 0, 3 do
				add(ctx, G_CHEST, "Button", Vector3.new(0.06, 0.06, 0.04), at(0, 3.95 - i * 0.28, -0.32), rgb(226, 216, 196), M.SmoothPlastic, "Ball")
			end
			if not look.Female and hash(seed, 58) < 0.5 then
				-- casquette plate
				local cap = pick({ rgb(90, 80, 70), rgb(70, 76, 90), rgb(120, 100, 76) }, seed, 59)
				add(ctx, G_HEAD, "FlatCap", Vector3.new(0.8, 0.26, 0.9), at(0, HY + 0.34, 0.0) * CFrame.Angles(math.rad(-8), 0, 0), cap, CLOTH, "Egg")
				add(ctx, G_HEAD, "CapBrim", Vector3.new(0.6, 0.06, 0.3), at(0, HY + 0.29, -0.4) * CFrame.Angles(math.rad(12), 0, 0), cap:Lerp(INK, 0.1), CLOTH)
			end
		end)
	elseif style == "worker" then
		shirt = o.Shirt or rgb(70, 90, 130)
		sleeve, longSleeve, skirt = shirt, true, false
		pants = o.Pants or rgb(58, 68, 90)
		look.Shoe = rgb(96, 70, 44)
		look.Sole = rgb(40, 34, 30)
		look.HairStyle = "none" -- (le casque couvre les cheveux)
		look.Collar = "crew"
		look.Belt = true
		table.insert(extras, function()
			local vest = rgb(255, 146, 36)
			add(ctx, G_CHEST, "Vest", Vector3.new(1.14, 1.14, 0.64), at(0, 3.59, 0), vest, CLOTH)
			for _, y in ipairs({ 3.3, 3.62 }) do
				add(ctx, G_CHEST, "VestStripe", Vector3.new(1.2, 0.09, 0.7), at(0, y, 0), rgb(226, 230, 222), M.Glass)
			end
			add(ctx, G_HEAD, "Helmet", Vector3.new(0.84, 0.54, 0.9), at(0, HY + 0.26, 0.02), rgb(255, 206, 36), M.SmoothPlastic, "Egg")
			add(ctx, G_HEAD, "HelmetBrim", Vector3.new(0.05, 0.94, 1.02), cylY(0, HY + 0.1, 0.0), rgb(250, 200, 30), M.SmoothPlastic, "Cyl")
			add(ctx, G_HEAD, "HelmetRidge", Vector3.new(0.12, 0.08, 0.8), at(0, HY + 0.52, 0.02), rgb(240, 192, 30), M.SmoothPlastic, "Egg")
			add(ctx, G_PELVIS, "ToolPouch", Vector3.new(0.14, 0.4, 0.34), at(0.56, 2.64, 0.02), rgb(110, 76, 44), M.Leather)
		end)
	elseif style == "kid" then
		shorts = hash(seed, 58) < 0.5 and not skirt
		longSleeve = false
		look.Belt = false
		look.Beard = "none"
		look.Collar = "crew"
		table.insert(extras, function()
			if hash(seed, 59) < 0.55 then
				-- cartable
				local c = pick({ rgb(255, 120, 160), rgb(90, 160, 240), rgb(255, 200, 60), rgb(120, 200, 120) }, seed, 60)
				add(ctx, G_CHEST, "Backpack", Vector3.new(0.86, 0.96, 0.36), at(0, 3.6, 0.47), c, CLOTH)
				add(ctx, G_CHEST, "BackpackPocket", Vector3.new(0.6, 0.4, 0.12), at(0, 3.32, 0.7), c:Lerp(WHITE, 0.3), CLOTH)
				for _, sx in ipairs({ -1, 1 }) do
					add(ctx, G_CHEST, "Strap", Vector3.new(0.12, 0.9, 0.05), at(sx * 0.3, 3.8, -0.305), c:Lerp(INK, 0.2), CLOTH)
				end
			end
		end)
	elseif style == "pedestrian" then
		if hash(seed, 61) < 0.35 then
			-- veste ouverte par-dessus le t-shirt (le buste prend la couleur de
			-- la veste ; le t-shirt se voit devant)
			local jacket = pick({ rgb(60, 70, 90), rgb(120, 80, 60), rgb(180, 160, 130), rgb(70, 110, 90), rgb(150, 40, 60), rgb(40, 40, 44) }, seed, 62)
			local tee = shirt
			shirt = jacket
			sleeve, longSleeve = jacket, true
			look.Collar = "none"
			table.insert(extras, function()
				add(ctx, G_CHEST, "Tee", Vector3.new(0.34, 1.26, 0.04), at(0, 3.62, -0.265), tee, CLOTH)
				add(ctx, G_CHEST, "TeeCollar", Vector3.new(0.07, 0.4, 0.4), cylY(0, 4.36, 0.03), tee:Lerp(INK, 0.1), CLOTH, "Cyl")
				for _, sx in ipairs({ -1, 1 }) do
					add(ctx, G_CHEST, "JacketLapel", Vector3.new(0.1, 0.56, 0.04), at(sx * 0.21, 3.98, -0.285) * CFrame.Angles(0, 0, sx * 0.28), jacket:Lerp(INK, 0.18), CLOTH)
					add(ctx, G_CHEST, "JacketEdge", Vector3.new(0.05, 0.8, 0.04), at(sx * 0.19, 3.25, -0.265), jacket:Lerp(INK, 0.12), CLOTH)
					add(ctx, G_CHEST, "JacketPocket", Vector3.new(0.2, 0.04, 0.04), at(sx * 0.36, 3.12, -0.255), jacket:Lerp(INK, 0.22), CLOTH)
				end
			end)
		elseif look.Female and hash(seed, 63) < 0.4 then
			-- écharpe
			local sc = pick({ rgb(200, 60, 80), rgb(236, 200, 120), rgb(120, 160, 210) }, seed, 64)
			table.insert(extras, function()
				add(ctx, G_CHEST, "Scarf", Vector3.new(0.16, 0.5, 0.5), cylY(0, 4.34, 0.03), sc, KNIT, "Cyl")
				add(ctx, G_CHEST, "ScarfEnd", Vector3.new(0.16, 0.56, 0.05), at(0.14, 3.98, -0.31), sc:Lerp(INK, 0.1), KNIT)
			end)
		end
	end
	if propKind == "none" then
		propKind = nil
	end

	torso(ctx, look, shirt, pants, skirt, style, seed)
	head(ctx, look, seed)
	-- (v11) pose des doigts au repos selon l'objet tenu
	local lPose, rPose = "relax", "relax"
	local ph = propKind and PROP_HAND[propKind]
	if ph then
		if ph[1] == 1 then
			rPose = ph[2] :: string
		else
			lPose = ph[2] :: string
		end
	end
	model:SetAttribute("NpcHandL", lPose)
	model:SetAttribute("NpcHandR", rPose)
	arm(ctx, -1, sleeve, look.Skin, longSleeve, cuff, lPose)
	arm(ctx, 1, sleeve, look.Skin, longSleeve, cuff, rPose)
	legs(ctx, look, pants, shorts, skirt)
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
	model:SetAttribute("NpcSeed", seed)
	if o.SitHeight then
		model:SetAttribute("NpcSitHeight", o.SitHeight)
	end
	if o.Look == false then
		model:SetAttribute("NpcNoLook", true)
	end
	model:SetAttribute("PartCount", ctx.Count + 1)
	if o.Solid ~= false then
		NPCModels.SetSolid(model, true)
	end
	return model
end

----------------------------------------------------------------------
-- Collision (capsule invisible)
----------------------------------------------------------------------

local COL_RADIUS = 0.78 -- (studs, échelle 1)
local COL_HEIGHT = 5.0

-- Repos de la capsule : debout (cylindre vertical) ou assis (boîte)
local function colliderRest(s: number, sitting: boolean, seatTop: number?): (Vector3, CFrame)
	if sitting then
		local top = seatTop or NPCModels.SitHeight
		local y0 = math.max(0.3, top - 1.2 * s)
		local y1 = top + 2.95 * s
		-- (buste au-dessus du siège + jambes vers l'avant)
		return Vector3.new(1.3 * s, y1 - y0, 1.9 * s), CFrame.new(0, (y0 + y1) / 2, -0.45 * s)
	end
	return Vector3.new(COL_HEIGHT * s, 2 * COL_RADIUS * s, 2 * COL_RADIUS * s), CFrame.new(0, 0.2 * s + COL_HEIGHT * s / 2, 0) * UPRIGHT
end

local rigs: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any

function NPCModels.SetSolid(model: Model, on: boolean)
	local old = model:FindFirstChild("NpcCollider")
	if not on then
		if old then
			old:Destroy()
		end
		model:SetAttribute("NpcSolid", false)
		rigs[model] = nil
		return
	end
	if old then
		return
	end
	local s = tonumber(model:GetAttribute("NpcScale")) or 1
	local size, rest = colliderRest(s, false, nil)
	local root = model.PrimaryPart
	local base = root and root.CFrame or CFrame.new()
	local c = Instance.new("Part")
	c.Name = "NpcCollider"
	c.Shape = Enum.PartType.Cylinder
	c.Anchored = true
	c.CanCollide = true
	c.CanTouch = false
	c.CastShadow = false
	c.Transparency = 1
	c.Size = size
	c.CFrame = base * rest
	c.Material = M.SmoothPlastic
	c:SetAttribute("NpcG", G_COL)
	c:SetAttribute("NpcRest", rest)
	c.Parent = model
	model:SetAttribute("NpcSolid", true)
	rigs[model] = nil
end

function NPCModels.SetSitHeight(model: Model, h: number)
	model:SetAttribute("NpcSitHeight", h)
end

-- h (nombre) : le PNJ est ASSIS sur un siège dont le dessus est à h ; nil : debout
function NPCModels.SetSeated(model: Model, h: number?)
	if h then
		model:SetAttribute("NpcSitHeight", h)
		model:SetAttribute("NpcSeated", true)
	else
		model:SetAttribute("NpcSeated", nil)
	end
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
	HS: number,
	Prop: string?,
	Seed: number,
	Collider: BasePart?,
	ColIndex: number,
	ColSitting: boolean,
	ColSolid: boolean,
	LookYaw: number,
	LookPitch: number,
	LookW: number,
	Clock: number,
	NoLook: boolean,
	SitTop: number?,
	Anim: string?,
	From: any?, -- (pose au changement d'anim : fondu)
	FadeAt: number,
	Last: any?,
	-- (v11) doigts : pièces (index dans Parts), côté, doigt, phalange
	HandIdx: { number },
	HandSide: { number },
	HandF: { number },
	HandG: { number },
	HandCur: { [number]: { number } }, -- (côté -> pose courante, 13 nombres)
	PalmIdx: { [number]: number },
	RevW: number, -- (conduite : poids du regard en arrière, lissé)
	Animated: boolean?,
}

local function rigOf(model: Model): Rig?
	local rig = rigs[model]
	if rig and rig.Root.Parent == model then
		return rig
	end
	local root = model.PrimaryPart or model:FindFirstChild("NpcRoot")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local p = model:GetAttribute("NpcProp")
	local r: Rig = {
		Root = root,
		Parts = {},
		Rests = {},
		Groups = {},
		Frames = {},
		S = tonumber(model:GetAttribute("NpcScale")) or 1,
		HS = tonumber(model:GetAttribute("NpcHeadScale")) or 1,
		Prop = type(p) == "string" and p or nil,
		Seed = tonumber(model:GetAttribute("NpcSeed")) or 1,
		Collider = nil,
		ColIndex = 0,
		ColSitting = false,
		ColSolid = true,
		LookYaw = 0,
		LookPitch = 0,
		LookW = 0,
		Clock = os.clock(),
		NoLook = model:GetAttribute("NpcNoLook") == true,
		SitTop = nil,
		Anim = nil,
		From = nil,
		FadeAt = 0,
		Last = nil,
		HandIdx = {},
		HandSide = {},
		HandF = {},
		HandG = {},
		HandCur = {},
		PalmIdx = {},
		RevW = 0,
	}
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			local g = d:GetAttribute("NpcG")
			local rest = d:GetAttribute("NpcRest")
			if type(g) == "number" and typeof(rest) == "CFrame" then
				-- (v11) pièces de la main : groupe du poignet (NpcG garde
				-- l'avant-bras pour les modules qui lisent les groupes)
				local side = d:GetAttribute("NpcHand")
				if type(side) == "number" then
					g = side < 0 and G_LHAND or G_RHAND
				end
				table.insert(r.Parts, d)
				table.insert(r.Rests, rest)
				table.insert(r.Groups, g)
				table.insert(r.Frames, rest)
				if g == G_COL then
					r.Collider = d
					r.ColIndex = #r.Parts
				end
				if type(side) == "number" then
					local f = tonumber(d:GetAttribute("NpcFinger")) or -1
					if f >= 1 then
						table.insert(r.HandIdx, #r.Parts)
						table.insert(r.HandSide, side)
						table.insert(r.HandF, f)
						table.insert(r.HandG, tonumber(d:GetAttribute("NpcSeg")) or 1)
					elseif f == 0 then
						r.PalmIdx[side] = #r.Parts
					end
				end
			end
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local name = model:GetAttribute(side < 0 and "NpcHandL" or "NpcHandR")
		r.HandCur[side] = handVec(type(name) == "string" and name or "relax")
	end
	rigs[model] = r
	return r
end

-- rotation `rot` autour du point `p` (repère du pivot, échelle appliquée)
local function about(p: Vector3, rot: CFrame): CFrame
	return CFrame.new(p) * rot * CFrame.new(-p)
end

local ANG = CFrame.Angles
local T: { CFrame } = table.create(NGROUPS, CFrame.new())
local sin, cos, max, min, abs = math.sin, math.cos, math.max, math.min, math.abs

-- Pose. Conventions (toutes en radians) :
--   membres : x > 0 = vers l'AVANT (bras levé devant, cuisse levée) ;
--   Knee / Elbow : flexion (> 0 : le tibia part vers l'arrière, l'avant-bras vers l'avant) ;
--   Foot : > 0 = pointe vers le HAUT ;
--   Lean > 0 = buste penché EN AVANT ; HeadPitch > 0 = regarde en BAS ;
--   Yaw > 0 = tourne vers la GAUCHE du personnage (-X local).
type Pose = {
	Bob: number,
	SwayX: number,
	PelvisYaw: number,
	PelvisRoll: number,
	Lean: number,
	Twist: number,
	Side: number,
	HeadYaw: number,
	HeadPitch: number,
	HeadRoll: number,
	LUp: CFrame,
	LLo: number,
	RUp: CFrame,
	RLo: number,
	LLoRot: CFrame?,
	RLoRot: CFrame?,
	LTh: number,
	LThRoll: number,
	LKnee: number,
	LFoot: number,
	RTh: number,
	RThRoll: number,
	RKnee: number,
	RFoot: number,
	Sit: boolean,
	Blink: number,
	LookW: number, -- (0..1) poids du regard vers le joueur
	-- (v11) mains : pose des doigts ("relax" | "flat" | "grip" | "fist" |
	-- "point" | "phone" | "cup") et rotation du poignet (repère de repos :
	-- ANG(0, a, 0) = rotation autour de l'avant-bras ; facultatif)
	LHand: string?,
	RHand: string?,
	LWrist: CFrame?,
	RWrist: CFrame?,
	-- (v11) main placée en cinématique inverse : { Frame = "chest" | "thigh" |
	-- "pivot", Pos (point de la main `Off` = (a, b, c), défaut centre de la
	-- paume), N (normale de la paume), B (direction du pouce), Pole (coude) }
	-- — dans le repère de REPOS du groupe (échelle 1)
	LIK: any?,
	RIK: any?,
}

local function newPose(): Pose
	return {
		Bob = 0,
		SwayX = 0,
		PelvisYaw = 0,
		PelvisRoll = 0,
		Lean = 0,
		Twist = 0,
		Side = 0,
		HeadYaw = 0,
		HeadPitch = 0,
		HeadRoll = 0,
		LUp = CFrame.identity,
		LLo = 0.12,
		RUp = CFrame.identity,
		RLo = 0.12,
		LTh = 0,
		LThRoll = 0,
		LKnee = 0,
		LFoot = 0,
		RTh = 0,
		RThRoll = 0,
		RKnee = 0,
		RFoot = 0,
		Sit = false,
		Blink = 0,
		LookW = 1,
		LHand = "relax",
		RHand = "relax",
	}
end

local function smoothPulse(x: number): number
	-- 0 -> 1 -> 0 sur [0, 1] (cloche douce)
	if x <= 0 or x >= 1 then
		return 0
	end
	return sin(x * math.pi) ^ 2
end

-- Jambes assises (v11, sièges "Roblox" à 1,85) :
--  - siège bas (genou plus haut que la hanche ou presque) : cuisses qui
--    remontent, tibias verticaux, pieds À PLAT ;
--  - siège normal / haut : cuisses posées sur l'assise (légère pente vers le
--    bord), tibias qui pendent un peu vers l'avant, pieds détendus dont la
--    pointe va chercher le sol (s'il est à portée) ; de temps en temps un
--    pied bouge, les enfants balancent les jambes.
local FOOT_TOE, FOOT_HEEL, ANKLE_H = 0.66, 0.24, 0.34
local function footPitchToFloor(ankleY: number): number
	-- pointe (repère du pied : + = vers le haut) qui touche le sol si possible
	local best, bestErr = -0.42, math.huge
	for k = 0, 24 do
		local phi = -k * 0.04 -- (0 .. -0,96)
		local toe = ankleY - ANKLE_H * math.cos(phi) + FOOT_TOE * math.sin(phi)
		local heel = ankleY - ANKLE_H * math.cos(phi) - FOOT_HEEL * math.sin(phi)
		local low = math.min(toe, heel)
		local err = math.abs(low - 0.04)
		if low >= 0.0 and err < bestErr then
			best, bestErr = phi, err
		end
	end
	return math.max(best, -0.75)
end

local function sitLegs(P: Pose, t: number, seatTop: number, s: number, kid: boolean?)
	local yh = (seatTop + HIP_OVER_SEAT * s) / s -- (hauteur de la hanche, échelle 1)
	local c = (yh - KNEE_Y) / THIGH_LEN
	P.Sit = true
	if c <= 0.22 then
		-- siège bas : pieds à plat (tibias verticaux)
		local th = math.acos(math.clamp(c, -0.55, 0.22))
		P.LTh, P.RTh = th + 0.02, th - 0.02
		P.LThRoll, P.RThRoll = 0.06, -0.06
		P.LKnee = th + 0.02 - 0.05
		P.RKnee = th - 0.02 - 0.05
		P.LFoot = -((th + 0.02) - P.LKnee)
		P.RFoot = -((th - 0.02) - P.RKnee)
		P.RFoot += max(0, sin(t * 0.7)) ^ 8 * 0.35
		return
	end
	-- cuisses sur l'assise : pente de 4 à 6° vers le bord
	local th = math.pi / 2 - 0.08
	local swingL, swingR = 0, 0
	if kid then
		swingL = sin(t * 2.2) * 0.32
		swingR = sin(t * 2.2 + 2.4) * 0.32
	else
		-- un pied qui se balance doucement de temps en temps
		swingR = max(0, sin(t * 0.37)) ^ 4 * sin(t * 2.6) * 0.16
	end
	for side = -1, 1, 2 do
		local thS = th + (side < 0 and 0.015 or -0.015)
		local shin = 0.16 + (side < 0 and swingL or swingR) + (side < 0 and 0.03 or 0)
		local kneeY = yh - THIGH_LEN * math.cos(thS)
		local ankleY = kneeY - 1.16 * math.cos(shin)
		local phi = footPitchToFloor(ankleY)
		if side < 0 then
			P.LTh, P.LKnee, P.LFoot, P.LThRoll = thS, thS - shin, phi - shin, 0.07
		else
			P.RTh, P.RKnee, P.RFoot, P.RThRoll = thS, thS - shin, phi - shin, -0.07
		end
	end
end

-- Point le plus bas d'une jambe sous la hanche (échelle 1) : cuisse (1,1),
-- tibia (1,16), pied (cheville à 0,34 du sol ; talon 0,24 derrière, pointe
-- 0,66 devant)
local HIP_Y = 2.6
local function legLow(th: number, knee: number, foot: number): number
	local phi = th - knee + foot
	local c, s2 = cos(phi), sin(phi)
	local heel = -0.34 * c - 0.24 * s2
	local toe = -0.34 * c + 0.66 * s2
	return -(1.1 * cos(th) + 1.16 * cos(th - knee)) + min(heel, toe)
end
local function groundBob(lth: number, lk: number, lf: number, rth: number, rk: number, rf: number): number
	return -min(legLow(lth, lk, lf), legLow(rth, rk, rf)) - HIP_Y
end

-- (v11) mains posées à plat sur le dessus des cuisses (repère de la cuisse au
-- repos : devant de la cuisse = -Z, doigts vers le genou = -Y)
local THIGH_IK = {
	[-1] = { Frame = "thigh", Pos = Vector3.new(-0.3, 1.86, -0.31), N = Vector3.new(0, 0, 1), B = Vector3.new(1, 0, 0), Pole = Vector3.new(-0.8, -0.3, 0.7) },
	[1] = { Frame = "thigh", Pos = Vector3.new(0.3, 1.86, -0.31), N = Vector3.new(0, 0, 1), B = Vector3.new(-1, 0, 0), Pole = Vector3.new(0.8, -0.3, 0.7) },
}
-- téléphone (main droite) devant la poitrine : écran tourné vers les yeux,
-- haut du téléphone vers l'avant (repère du buste au repos)
local PHONE_IK = (function()
	local pc = Vector3.new(0.17, 3.86, -0.95)
	local eye = Vector3.new(0, 4.86, -0.33)
	local n = (eye - pc).Unit
	local f = Vector3.new(0, 0, -1)
	local b = (f - n * f:Dot(n)).Unit
	return { Frame = "chest", Pos = pc, N = n, B = b, Off = Vector3.new(0.2, 0.03, 0.084), Pole = Vector3.new(0.9, -1, 0.25) }
end)()

-- (v11) animations ajoutées par d'autres modules (NPCModels.AddAnim)
local CUSTOM: { [string]: (any, number, number) -> () } = {}

local function pose(anim: string, t: number, propKind: string?, seed: number, seated: boolean, seatTop: number, s: number, kid: boolean?): Pose
	local P = newPose()
	local breathe = sin(t * 1.55) -- (~15 respirations / min)
	-- clignement : toutes les 2,8 à 5 s, 0,14 s
	local period = 2.8 + (seed % 7) * 0.31
	P.Blink = smoothPulse(((t + seed * 0.37) % period) / 0.14)
	-- transfert du poids (repos) : lent, propre à chacun
	local shift = sin(t * 0.42 + seed)
	if anim == "walk" or anim == "push" then
		local w = t * math.pi * 2 * 0.95 -- (0,95 cycle / s à t normal : ~1,9 pas / s)
		local sl, sr = sin(w), sin(w + math.pi)
		local cl, cr = cos(w), cos(w + math.pi)
		local amp = anim == "push" and 0.34 or 0.42
		-- cuisses : avant / arrière
		P.LTh = sl * amp + 0.04
		P.RTh = sr * amp + 0.04
		-- genoux : grande flexion pendant l'oscillation (jambe qui revient),
		-- petite flexion à l'attaque du talon (amorti)
		P.LKnee = max(0, cl) ^ 1.6 * 1.05 + max(0, sin(w - 2.2)) * 0.16 + 0.05
		P.RKnee = max(0, cr) ^ 1.6 * 1.05 + max(0, sin(w + math.pi - 2.2)) * 0.16 + 0.05
		-- pieds : pointe relevée à l'attaque, poussée sur les orteils au départ
		P.LFoot = -0.15 * max(0, sl) + 0.14 * max(0, -cl) + 0.3 * max(0, cl)
		P.RFoot = -0.15 * max(0, sr) + 0.14 * max(0, -cr) + 0.3 * max(0, cr)
		-- bassin : rebond (2 par cycle), balancement latéral vers la jambe d'appui,
		-- rotation avec la jambe avant, léger roulis
		P.SwayX = cl * 0.045
		P.PelvisYaw = -sl * 0.1
		P.PelvisRoll = -cl * 0.045
		-- buste en contre-rotation, tête stable
		P.Twist = sl * 0.08
		P.Lean = anim == "push" and 0.2 or 0.05
		P.HeadYaw = -sl * 0.02
		P.HeadPitch = -0.03
		if anim == "push" then
			-- mains sur la poignée du chariot
			P.LUp = ANG(0.95, 0, 0.1)
			P.RUp = ANG(0.95, 0, -0.1)
			P.LLo, P.RLo = 0.6, 0.6
			P.LHand, P.RHand = "grip", "grip"
			P.LookW = 0.5
		else
			-- bras en opposition des jambes, coude qui plie en avant
			P.LUp = ANG(-sl * 0.4, 0, -0.07)
			P.RUp = ANG(-sr * 0.4, 0, 0.07)
			P.LLo = 0.22 + max(0, -sl) * 0.35
			P.RLo = 0.22 + max(0, -sr) * 0.35
		end
	else
		-- debout (ou assis) : respiration, poids d'une jambe sur l'autre
		P.Bob = breathe * 0.008
		P.SwayX = shift * 0.035
		P.PelvisRoll = shift * 0.035
		P.Side = -shift * 0.03
		local relaxL = max(0, -shift) -- (la jambe qui ne porte pas se plie un peu)
		local relaxR = max(0, shift)
		P.LKnee = relaxL * 0.18
		P.RKnee = relaxR * 0.18
		P.LTh = relaxL * 0.09
		P.RTh = relaxR * 0.09
		P.LFoot = -relaxL * 0.05
		P.RFoot = -relaxR * 0.05
		P.LThRoll = -shift * 0.03
		P.RThRoll = -shift * 0.03
		P.LUp = ANG(0.02 - breathe * 0.01, 0, -0.07)
		P.RUp = ANG(0.02 - breathe * 0.01, 0, 0.07)
		P.LLo, P.RLo = 0.14, 0.14
		P.HeadYaw = sin(t * 0.29 + seed) * 0.3 + sin(t * 0.83) * 0.08
		P.HeadPitch = sin(t * 0.41) * 0.05
		P.HeadRoll = sin(t * 0.23) * 0.03

		if anim == "sit" then
			-- adossé, mains posées à plat sur les cuisses (paumes vers le bas)
			P.Lean = -0.15
			P.LUp = ANG(0.28, 0, 0.1)
			P.RUp = ANG(0.28, 0, -0.1)
			P.LLo, P.RLo = 0.78, 0.78
			P.LHand, P.RHand = "flat", "flat"
			P.LIK = THIGH_IK[-1]
			P.RIK = THIGH_IK[1]
			P.HeadYaw = sin(t * 0.31 + seed) * 0.4
		elseif anim == "wave" then
			P.RUp = ANG(0.25, 0, 2.5)
			P.RLo = 0.4
			P.RLoRot = ANG(0, 0, sin(t * 7) * 0.45)
			P.RHand = "flat"
			P.RWrist = ANG(0, 1.5, 0) -- (paume vers l'avant)
			P.HeadPitch = -0.06
			P.HeadYaw = 0.1
			P.HeadRoll = 0.08
		elseif anim == "scan" then
			-- caisse : les mains passent les articles devant le scanner (droite -> gauche)
			local cyc = (t * 0.8) % 1
			local sweep = sin(cyc * math.pi * 2)
			local lift = max(0, sin(cyc * math.pi * 2 + 1)) * 0.12
			P.Lean = 0.12
			P.Twist = -sweep * 0.14
			P.LUp = ANG(0.6 + lift, -sweep * 0.2, -0.05)
			P.RUp = ANG(0.7 + lift, -sweep * 0.3, 0.05)
			P.LLo, P.RLo = 1.1, 1.05
			P.LHand, P.RHand = "grip", "grip"
			P.HeadPitch = 0.32
			P.HeadYaw = -sweep * 0.18
			P.LookW = 0.45
		elseif anim == "type" then
			P.LUp = ANG(0.4, 0, 0.12)
			P.LLo = 1.25
			P.RUp = ANG(0.5, 0.2, -0.05)
			P.RLo = 1.1 + sin(t * 9) * 0.08
			P.RLoRot = ANG(0, 0, sin(t * 11) * 0.06)
			P.LHand, P.RHand = "flat", "point"
			P.LWrist = ANG(0, -1.5, 0)
			P.HeadPitch = 0.34
			P.Lean = 0.05
			P.LookW = 0.4
		elseif anim == "talk" then
			local g = sin(t * 2.2)
			P.HeadPitch = sin(t * 3.1) * 0.07
			P.HeadYaw = sin(t * 0.6) * 0.2
			P.HeadRoll = sin(t * 1.3) * 0.05
			P.RUp = ANG(0.35 + g * 0.12, 0.1, 0.1)
			P.RLo = 0.95 + sin(t * 3.3) * 0.25
			P.RLoRot = ANG(0, sin(t * 2.7) * 0.3, 0)
			P.LUp = ANG(0.08 + max(0, sin(t * 1.1)) * 0.3, 0, -0.08)
			P.LLo = 0.25 + max(0, sin(t * 1.1)) * 0.7
			P.RHand = "flat" -- (main ouverte qui accompagne la parole)
			P.RWrist = ANG(0, 1.0 + sin(t * 2.1) * 0.3, 0)
			P.Twist = g * 0.05
		elseif anim == "clap" then
			local c = abs(sin(t * 6))
			P.LUp = ANG(0.8, 0, 0.3 - c * 0.22)
			P.RUp = ANG(0.8, 0, -0.3 + c * 0.22)
			P.LLo, P.RLo = 1.2, 1.2
			P.LHand, P.RHand = "flat", "flat"
			P.HeadPitch = -0.08
			P.Bob += c * 0.01
		elseif anim == "cheer" then
			local c = sin(t * 5)
			P.LUp = ANG(0.2, 0, -2.5 - c * 0.15)
			P.RUp = ANG(0.2, 0, 2.5 + c * 0.15)
			P.LLo, P.RLo = 0.3, 0.3
			P.LHand, P.RHand = "flat", "flat"
			P.HeadPitch = -0.15
			P.Bob += max(0, c) * 0.06
		elseif CUSTOM[anim] then
			-- (v11) animation d'un autre module (sport, etc.)
			local okC, errC = pcall(CUSTOM[anim], P, t, seed)
			if not okC then
				warn("[NPCModels] anim " .. anim .. " : " .. tostring(errC))
				CUSTOM[anim] = nil
			end
		end
	end
	-- debout : le bassin se place pour que le pied le plus bas touche le sol
	-- (talon ou pointe selon l'inclinaison du pied) : aucun pied qui flotte
	-- ni qui s'enfonce, rebond naturel de la marche
	if anim ~= "sit" and not seated then
		P.Bob += groundBob(P.LTh, P.LKnee, P.LFoot, P.RTh, P.RKnee, P.RFoot)
	end
	-- assis (anim "sit" ou PNJ assis qui fait autre chose)
	if anim == "sit" or seated then
		P.Bob, P.SwayX, P.PelvisRoll, P.PelvisYaw = breathe * 0.006, 0, 0, 0
		P.Side = 0
		sitLegs(P, t + seed, seatTop, s, kid)
	end
	-- objets tenus : le téléphone se regarde, le café se porte
	local handsBusy = (anim == "wave" or anim == "push" or anim == "scan" or anim == "clap" or anim == "cheer")
	local typing = (anim == "type")
	local casual = (anim == "walk" or anim == "idle" or anim == "sit")
	if propKind == "phone" and not handsBusy then
		-- (v11) téléphone tenu devant la poitrine, écran tourné vers le visage
		-- (cinématique inverse dans le repère du buste), regard dessus
		P.RHand = "phone"
		P.RIK = PHONE_IK
		P.RLoRot = nil
		P.HeadPitch = P.Sit and 0.52 or 0.45
		P.HeadYaw = 0.1
		P.LookW = 0.3
	elseif propKind == "coffee" and not handsBusy then
		P.RHand = "cup"
		P.RIK = nil
		-- (une gorgée de temps en temps)
		local sip = smoothPulse(((t + seed * 0.7) % 9) / 1.6)
		P.RUp = ANG(0.22 + sip * 0.55, 0.25 * sip, 0.1)
		P.RLo = 1.3 + sip * 0.75
		P.HeadPitch = P.HeadPitch * (1 - sip) - sip * 0.12
	elseif propKind == "tablet" and not typing then
		P.LIK = nil
		P.LUp = ANG(0.35, 0, 0.1)
		P.LLo = 1.25
		P.LHand = "flat"
		P.LWrist = ANG(0, 1.5, 0) -- (paume vers le haut : la tablette repose dessus)
	elseif propKind == "tablet" then
		P.LHand = "flat"
		P.LWrist = ANG(0, 1.5, 0)
	elseif propKind == "bag" and not handsBusy then
		P.RHand = "grip"
		P.RIK = nil
		if casual and not P.Sit then
			P.RUp = ANG(0.02, 0, 0.14)
			P.RLo = 0.08
		end
	elseif propKind == "cane" and not handsBusy then
		P.RHand = "grip"
		P.RIK = nil
		if not P.Sit then
			P.RUp = ANG(0.18, 0, 0.1)
			P.RLo = 0.35
		end
	elseif propKind == "leash" and not handsBusy then
		-- (laisse dans la main gauche : avant-bras en avant, peu de balancement)
		P.LHand = "grip"
		P.LIK = nil
		if not P.Sit then
			P.LUp = ANG(0.18 + sin(t * 1.3) * 0.04, 0, -0.12)
			P.LLo = 0.62
		end
	end
	return P
end

-- Fondu entre deux poses (changement d'anim : marche -> arrêt, etc.)
local FADE = 0.35
local function lerpPose(a: any, b: any, k: number): any
	local out = {}
	for key, vb in pairs(b) do
		local va = a[key]
		if type(vb) == "number" and type(va) == "number" then
			out[key] = va + (vb - va) * k
		elseif typeof(vb) == "CFrame" then
			out[key] = (typeof(va) == "CFrame" and va or CFrame.identity):Lerp(vb, k)
		else
			out[key] = vb
		end
	end
	for key, va in pairs(a) do
		if b[key] == nil and typeof(va) == "CFrame" then
			out[key] = va:Lerp(CFrame.identity, k)
		end
	end
	return out
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

----------------------------------------------------------------------
-- Joueur local (regard + anti-piège de la capsule), mis en cache
----------------------------------------------------------------------

local focusAt = -1
local focusHead: Vector3? = nil
local focusRoot: Vector3? = nil
local function localFocus(): (Vector3?, Vector3?)
	local now = os.clock()
	if now - focusAt < 0.05 then
		return focusHead, focusRoot
	end
	focusAt = now
	focusHead, focusRoot = nil, nil
	local ok = pcall(function()
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer
		local character = player and player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			local headPart = character:FindFirstChild("Head")
			if hrp and hrp:IsA("BasePart") then
				focusRoot = hrp.Position
				focusHead = (headPart and headPart:IsA("BasePart")) and headPart.Position or hrp.Position + Vector3.new(0, 1.5, 0)
			end
		end
	end)
	if not ok then
		focusHead, focusRoot = nil, nil
	end
	return focusHead, focusRoot
end

-- Dessus du siège sous le PNJ assis : attribut, sinon rayon vers le bas (une fois)
local function seatTopOf(model: Model, rig: Rig): number
	local attr = tonumber(model:GetAttribute("NpcSitHeight"))
	if attr then
		return attr
	end
	if rig.SitTop then
		return rig.SitTop
	end
	local top = NPCModels.SitHeight
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local pivot = rig.Root.CFrame
		local from = (pivot * CFrame.new(0, 3.2 * rig.S, 0.1 * rig.S)).Position
		local hit = workspace:Raycast(from, pivot.UpVector * -3.1 * rig.S, params)
		if hit then
			local h = pivot:PointToObjectSpace(hit.Position).Y
			if h > 0.6 * rig.S and h < 3.2 * rig.S then
				top = h
				return
			end
		end
		-- (sièges décoratifs sans CanQuery : on cherche, une seule fois, la pièce
		-- voisine sous le bassin dont le dessus est à hauteur d'assise)
		local parent = model.Parent
		if not parent then
			return
		end
		local hip = pivot * CFrame.new(0, 0, 0.1 * rig.S)
		local best = -1
		for _, d in ipairs(parent:GetDescendants()) do
			if d:IsA("BasePart") and not d:IsDescendantOf(model) then
				local rel = d.CFrame:PointToObjectSpace(hip.Position)
				local half = d.Size / 2
				if math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z then
					local topW = (d.CFrame * CFrame.new(0, half.Y, 0)).Position
					local h = pivot:PointToObjectSpace(topW).Y
					if h > 0.6 * rig.S and h < 2.8 * rig.S and h > best and d.CFrame.UpVector.Y > 0.9 then
						best = h
					end
				end
			end
		end
		if best > 0 then
			top = best
		end
	end)
	rig.SitTop = top
	return top
end

----------------------------------------------------------------------
-- (v11) Cinématique inverse (bras), doigts, conduite
----------------------------------------------------------------------

-- repère (axe Y = a, Z = ref orthogonalisé)
local function frameOf(a: Vector3, ref: Vector3): CFrame
	local z = ref - a * ref:Dot(a)
	if z.Magnitude < 1e-4 then
		z = Vector3.new(0, 0, -1) - a * (-a.Z)
		if z.Magnitude < 1e-4 then
			z = Vector3.new(1, 0, 0) - a * a.X
		end
	end
	z = z.Unit
	return CFrame.fromMatrix(Vector3.zero, a:Cross(z), a, z)
end

-- plus petite rotation qui amène a sur b (vecteurs unitaires)
local function rotMin(a: Vector3, b: Vector3): CFrame
	local ax = a:Cross(b)
	local m = ax.Magnitude
	if m < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(ax / m, math.atan2(m, a:Dot(b)))
end

-- Cible d'une main (repère du pivot, posé) : position du POIGNET, repère de
-- la main (handFrame(U, B)) facultatif, direction vers laquelle part le coude
type IKTarget = { Pos: Vector3, Rot: CFrame?, Pole: Vector3 }

-- Bras à deux segments (épaule -> coude -> poignet) : transformations des
-- groupes bras / avant-bras / main
local function solveArm(sx: number, s: number, chest: CFrame, tg: IKTarget): (CFrame, CFrame, CFrame)
	local S0 = (sx < 0 and J.ShoulderL or J.ShoulderR) * s
	local E0 = (sx < 0 and J.ElbowL or J.ElbowR) * s
	local W0 = wrist0(sx) * s
	local S = chest * S0
	local L1 = (E0 - S0).Magnitude
	local L2 = (W0 - E0).Magnitude
	local v = tg.Pos - S
	local dir = v.Magnitude > 1e-4 and v.Unit or Vector3.new(0, -1, 0)
	local D = math.clamp(v.Magnitude, math.abs(L1 - L2) + 0.02 * s, (L1 + L2) * 0.999)
	local W = S + dir * D
	local ca = math.clamp((L1 * L1 + D * D - L2 * L2) / (2 * L1 * D), -1, 1)
	local along = L1 * ca
	local h = math.sqrt(math.max(0, L1 * L1 - along * along))
	local pole = tg.Pole - dir * tg.Pole:Dot(dir)
	if pole.Magnitude < 1e-4 then
		pole = Vector3.new(0, -1, 0) - dir * (-dir.Y)
		if pole.Magnitude < 1e-4 then
			pole = Vector3.new(sx, 0, 0)
		end
	end
	pole = pole.Unit
	local E = S + dir * along + pole * h
	local upA = (E - S).Unit
	local foA = (W - E).Unit
	-- (le coude plie vers l'avant au repos : -Z)
	local bend = foA - upA * foA:Dot(upA)
	if bend.Magnitude < 1e-3 then
		bend = -pole
	end
	local Rup = frameOf(upA, bend) * frameOf((E0 - S0).Unit, Vector3.new(0, 0, -1)):Inverse()
	local Tup = CFrame.new(S) * Rup * CFrame.new(-S0)
	local Rlo = rotMin(Rup * (W0 - E0).Unit, foA) * Rup
	local Tlo = CFrame.new(E) * Rlo * CFrame.new(-E0)
	local Th = Tlo
	if tg.Rot then
		Th = CFrame.new(W) * (tg.Rot * HAND_M0_INV) * CFrame.new(-W0)
	end
	return Tup, Tlo, Th
end

-- repère d'une main dont on connaît la normale de la paume `n` et la
-- direction du pouce `b` (côté `sx`) : U = sx (n x b)
local function handBasis(sx: number, n: Vector3, b: Vector3): (CFrame, Vector3, Vector3)
	local bb = b.Unit
	local nn = n - bb * n:Dot(bb)
	nn = nn.Magnitude > 1e-4 and nn.Unit or Vector3.new(0, 1, 0)
	local u = (nn:Cross(bb) * sx).Unit
	return handFrame(u, bb), u, nn
end

-- Cible "poing sur la jante" (repère du pivot) : volant `wheel` (centre,
-- LookVector = vers le tableau de bord, UpVector = midi), rayon R, angle phi
-- (0 = midi, + = vers la gauche du conducteur)
local function rimTarget(sx: number, s: number, wheel: CFrame, R: number, phi: number): IKTarget
	local up, right, ax = wheel.UpVector, wheel.RightVector, wheel.LookVector
	local rr = up * math.cos(phi) - right * math.sin(phi)
	local g = wheel.Position + rr * R
	local dr = -up * math.sin(phi) - right * math.cos(phi)
	local rot, u, n = handBasis(sx, ax * 0.75 - rr * 0.65, dr * sx)
	return { Pos = g - u * 0.31 * s - n * 0.075 * s, Rot = rot, Pole = Vector3.new(sx * 0.8, -1, 0.35) }
end

-- Jambes de conduite : pieds sur les pédales (deux segments, plan sagittal)
local function driveLegs(P: Pose, seatTop: number, s: number, t: number)
	local yh = (seatTop + HIP_OVER_SEAT * s) / s
	for side = -1, 1, 2 do
		local ankleY = side > 0 and 0.42 or 0.38
		local reach = side > 0 and 2.04 or 1.96
		local dy = yh - ankleY
		local dz = math.sqrt(math.max(0.3, reach * reach - dy * dy))
		local D = math.sqrt(dy * dy + dz * dz)
		local L1, L2 = THIGH_LEN, 1.16
		D = math.clamp(D, 0.3, L1 + L2 - 0.01)
		local alpha = math.atan2(dz, dy)
		local beta = math.acos(math.clamp((L1 * L1 + D * D - L2 * L2) / (2 * L1 * D), -1, 1))
		local gamma = math.acos(math.clamp((L2 * L2 + D * D - L1 * L1) / (2 * L2 * D), -1, 1))
		local th = alpha + beta
		local shin = alpha - gamma
		-- (pied droit sur l'accélérateur : il appuie un peu, par moments)
		local press = side > 0 and (0.45 + sin(t * 0.5) * 0.08) or 0.62
		if side < 0 then
			P.LTh, P.LKnee, P.LFoot, P.LThRoll = th, th - shin, press - shin, 0.1
		else
			P.RTh, P.RKnee, P.RFoot, P.RThRoll = th, th - shin, press - shin, -0.06
		end
	end
	P.Sit = true
end

-- Pose de conduite (le reste : bras en IK dans animateRig)
local function drivePose(t: number, seed: number, s: number, seatTop: number, drive: any, rw: number): Pose
	local P = newPose()
	local breathe = sin(t * 1.55)
	local period = 2.8 + (seed % 7) * 0.31
	P.Blink = smoothPulse(((t + seed * 0.37) % period) / 0.14)
	driveLegs(P, seatTop, s, t)
	local steer = tonumber(drive.Steer) or 0
	P.Lean = -(tonumber(drive.Recline) or 0.18) + breathe * 0.008
	P.Bob = breathe * 0.004
	-- regard : devant, vers l'intérieur du virage, petits coups d'œil
	local glance = max(0, sin(t * 0.23 + seed)) ^ 12 * 0.45 * (seed % 2 == 0 and 1 or -1)
	P.HeadYaw = math.clamp(steer * 0.2, -0.45, 0.45) + glance
	P.HeadPitch = -0.03 + sin(t * 0.4) * 0.02
	P.HeadRoll = -steer * 0.04
	P.Side = -steer * 0.03
	-- marche arrière : buste qui pivote, regard par-dessus l'épaule droite
	P.Twist = -0.55 * rw
	P.HeadYaw = P.HeadYaw * (1 - rw) - 1.15 * rw
	P.HeadPitch = P.HeadPitch * (1 - rw) + 0.05 * rw
	P.LookW = 0
	P.LHand, P.RHand = "grip", rw > 0.5 and "flat" or "grip"
	return P
end

-- Doigts : la pose courante rejoint la pose voulue (fondu ~0,15 s) ; repos
-- des phalanges recalculés seulement quand ils changent
local HAND_VECS: { [string]: { number } } = {}
for name in pairs(HANDS) do
	HAND_VECS[name] = handVec(name)
end
local function updateHands(rig: Rig, P: Pose, dt: number, snap: boolean)
	if #rig.HandIdx == 0 then
		return
	end
	for side = -1, 1, 2 do
		local want = HAND_VECS[(side < 0 and P.LHand or P.RHand) or "relax"] or HAND_VECS.relax
		local cur = rig.HandCur[side]
		local k = snap and 1 or min(1, dt * 9)
		local diff = 0
		for i = 1, 13 do
			local d = want[i] - cur[i]
			if abs(d) > diff then
				diff = abs(d)
			end
			cur[i] += d * k
		end
		if diff > 0.002 then
			local s = rig.S
			for j, idx in ipairs(rig.HandIdx) do
				if rig.HandSide[j] == side then
					local fr = fingerRest(side, rig.HandF[j], rig.HandG[j], cur)
					rig.Rests[idx] = CFrame.new(fr.Position * s) * fr.Rotation
				end
			end
		end
	end
end

local function animateRig(model: Model, rig: Rig, anim: string, t: number, look: Vector3?, drive: any?)
	-- (v10, PHYS10) réaction à une voiture : saut de côté / bousculade (décalage du corps entier)
	local react: CFrame? = nil
	local reactSolid = true
	if not drive and model:GetAttribute("NpcReactT") ~= nil then
		local okR, IR = pcall(require, script.Parent:FindFirstChild("ImpactRules") :: any)
		if okR and type(IR) == "table" then
			local okN, off, solidR, animR = pcall(IR.NpcReact, model, rig.Root.CFrame, os.clock())
			if okN and off then
				react = off
				reactSolid = solidR ~= false
				anim = animR or anim
			end
		end
	end
	local s = rig.S
	local clock = os.clock()
	local dt = math.clamp(clock - rig.Clock, 0, 0.25)
	rig.Clock = clock
	local seated = drive ~= nil or model:GetAttribute("NpcSeated") == true
	local sitting = anim == "sit" or seated
	local seatTop = if drive then drive.Floor else (sitting and seatTopOf(model, rig) or NPCModels.SitHeight)
	local kid = model:GetAttribute("NpcStyle") == "kid"
	local P
	if drive and anim == "drive" then
		local want = drive.Reverse and 1 or 0
		rig.RevW += (want - rig.RevW) * min(1, dt * 2.6)
		P = drivePose(t, rig.Seed, s, seatTop, drive, rig.RevW * rig.RevW * (3 - 2 * rig.RevW))
	else
		P = pose(anim, t, rig.Prop, rig.Seed, seated, seatTop, s, kid)
	end
	local pivot = if react then rig.Root.CFrame * react else rig.Root.CFrame
	-- fondu doux quand l'anim change (pas de saut de pose)
	if rig.Anim ~= anim then
		if rig.Anim ~= nil and rig.Last then
			rig.From = rig.Last
			rig.FadeAt = clock
		end
		rig.Anim = anim
	end
	if rig.From then
		local k = (clock - rig.FadeAt) / FADE
		if k >= 1 then
			rig.From = nil
		else
			k = k * k * (3 - 2 * k)
			P = lerpPose(rig.From, P, k) :: Pose
		end
	end
	rig.Last = P

	-- regard : vers `look`, sinon vers l'avatar local proche (≤ 14 studs, devant)
	local wantYaw, wantPitch, wantW = 0, 0, 0
	local headPos, rootPos = localFocus()
	local target = look
	if not target and not rig.NoLook and headPos then
		target = headPos
	end
	if target and P.LookW > 0 then
		local neckW = pivot * (J.Neck * s + Vector3.new(0, sitting and (seatTop + HIP_OVER_SEAT * s - J.HipL.Y * s) or 0, 0))
		local rel = pivot:VectorToObjectSpace(target - neckW)
		local flat = Vector3.new(rel.X, 0, rel.Z).Magnitude
		if flat < 14 * max(s, 0.8) and flat > 0.5 then
			local yaw = math.atan2(-rel.X, -rel.Z)
			if abs(yaw) < 2.0 then
				wantYaw = math.clamp(yaw, -1.2, 1.2)
				wantPitch = math.clamp(-math.atan2(rel.Y, flat), -0.45, 0.5)
				-- (poids : plein à moins de 9 studs, s'efface jusqu'à 14)
				wantW = math.clamp((14 * s - flat) / (5 * s), 0, 1) * P.LookW
			end
		end
	end
	local k = min(1, dt * 3.2) -- (lissage : ~0,3 s)
	rig.LookYaw += (wantYaw - rig.LookYaw) * k
	rig.LookPitch += (wantPitch - rig.LookPitch) * k
	rig.LookW += (wantW - rig.LookW) * k
	local lw = rig.LookW
	local headYaw = P.HeadYaw * (1 - lw) + rig.LookYaw * lw
	local headPitch = P.HeadPitch * (1 - lw) + rig.LookPitch * lw
	-- (au-delà de ~0,8 rad, le buste suit un peu)
	local chestFollow = math.clamp(rig.LookYaw - 0.8 * math.sign(rig.LookYaw), -0.35, 0.35)
	if abs(rig.LookYaw) < 0.8 then
		chestFollow = 0
	end
	local twist = P.Twist + chestFollow * lw
	headYaw -= chestFollow * lw

	-- assis : le bassin descend sur le siège (articulation de la hanche au-dessus)
	local drop = 0
	if sitting or drive then
		drop = (seatTop + HIP_OVER_SEAT * s) - J.HipL.Y * s
	end
	local body = CFrame.new(P.SwayX * s, P.Bob * s + drop, 0)
	local pel = body * about(J.Pelvis * s, ANG(0, P.PelvisYaw, P.PelvisRoll))
	T[G_PELVIS] = pel
	local chest = pel * about(J.Waist * s, ANG(-P.Lean, twist - P.PelvisYaw * 0.4, P.Side - P.PelvisRoll * 0.6))
	T[G_CHEST] = chest
	local hd = chest * about(J.Neck * s, ANG(-headPitch, headYaw, P.HeadRoll))
	T[G_HEAD] = hd
	T[G_LID] = hd * CFrame.new(0, 0, -P.Blink * 0.06 * s * rig.HS)
	local lu = chest * about(J.ShoulderL * s, P.LUp)
	T[G_LUP] = lu
	T[G_LLO] = lu * about(J.ElbowL * s, ANG(P.LLo, 0, 0) * (P.LLoRot or CFrame.identity))
	local ru = chest * about(J.ShoulderR * s, P.RUp)
	T[G_RUP] = ru
	T[G_RLO] = ru * about(J.ElbowR * s, ANG(P.RLo, 0, 0) * (P.RLoRot or CFrame.identity))
	T[G_LHAND] = T[G_LLO] * about(wrist0(-1) * s, P.LWrist or CFrame.identity)
	T[G_RHAND] = T[G_RLO] * about(wrist0(1) * s, P.RWrist or CFrame.identity)
	-- (v11) conduite : les mains tiennent la jante (cinématique inverse)
	if drive and anim == "drive" then
		local wheel: CFrame = drive.Wheel
		local R = drive.Radius
		local steer = tonumber(drive.Steer) or 0
		local rw = rig.RevW
		for side = -1, 1, 2 do
			local phi = -side * 1.05 + steer
			if side < 0 then
				phi = math.clamp(phi, -0.5, 2.4)
			else
				phi = math.clamp(phi, -2.4, 0.5)
			end
			local tg = rimTarget(side, s, wheel, R, phi)
			if rw > 0.01 then
				local back: IKTarget
				if side < 0 then
					back = rimTarget(side, s, wheel, R, 0.15)
				else
					-- main droite posée sur le dossier du passager
					local rot = handBasis(1, Vector3.new(0, -1, 0), Vector3.new(0, 0, -1))
					back = { Pos = Vector3.new(1.7 * s, seatTop + 2.45 * s, 0.75 * s), Rot = rot, Pole = Vector3.new(0.3, -1, 0.6) }
				end
				local e = rw * rw * (3 - 2 * rw)
				tg = {
					Pos = tg.Pos:Lerp(back.Pos, e),
					Rot = (tg.Rot :: CFrame):Lerp(back.Rot :: CFrame, e),
					Pole = tg.Pole:Lerp(back.Pole, e),
				}
			end
			local tu, tl, th = solveArm(side, s, chest, tg)
			if side < 0 then
				T[G_LUP], T[G_LLO], T[G_LHAND] = tu, tl, th
			else
				T[G_RUP], T[G_RLO], T[G_RHAND] = tu, tl, th
			end
		end
	end
	local lt = pel * about(J.HipL * s, ANG(P.LTh, 0, P.LThRoll))
	T[G_LTH] = lt
	local ls = lt * about(J.KneeL * s, ANG(-P.LKnee, 0, 0))
	T[G_LSH] = ls
	T[G_LFT] = ls * about(J.AnkleL * s, ANG(P.LFoot, 0, 0))
	local rt = pel * about(J.HipR * s, ANG(P.RTh, 0, P.RThRoll))
	T[G_RTH] = rt
	local rs = rt * about(J.KneeR * s, ANG(-P.RKnee, 0, 0))
	T[G_RSH] = rs
	T[G_RFT] = rs * about(J.AnkleR * s, ANG(P.RFoot, 0, 0))
	T[G_COL] = CFrame.identity
	-- (v11) mains en cinématique inverse (posées sur les cuisses, téléphone
	-- devant le visage…) : repère de repos du groupe choisi
	if not drive then
		for side = -1, 1, 2 do
			local ik = if side < 0 then P.LIK else P.RIK
			if type(ik) == "table" and typeof(ik.Pos) == "Vector3" then
				local G = chest
				if ik.Frame == "thigh" then
					G = side < 0 and lt or rt
				elseif ik.Frame == "pivot" then
					G = CFrame.identity
				end
				local rot, u, n = handBasis(side, G:VectorToWorldSpace(ik.N), G:VectorToWorldSpace(ik.B))
				local off: Vector3 = if typeof(ik.Off) == "Vector3" then ik.Off else Vector3.new(0.15, 0, 0)
				local pos = G * (ik.Pos * s) - (u * off.X + rot.UpVector * off.Y + n * off.Z) * s
				local tu, tl, th = solveArm(side, s, chest, { Pos = pos, Rot = rot, Pole = ik.Pole or Vector3.new(side * 0.8, -1, 0.3) })
				if side < 0 then
					T[G_LUP], T[G_LLO], T[G_LHAND] = tu, tl, th
				else
					T[G_RUP], T[G_RLO], T[G_RHAND] = tu, tl, th
				end
			end
		end
	end
	updateHands(rig, P, dt, not rig.Animated)
	rig.Animated = true

	-- capsule : forme (debout / assis) + anti-piège (avatar local dedans)
	local col = rig.Collider
	if col and rig.ColIndex > 0 then
		if rig.ColSitting ~= sitting then
			rig.ColSitting = sitting
			local size, rest = colliderRest(s, sitting, seatTop)
			col.Shape = sitting and Enum.PartType.Block or Enum.PartType.Cylinder
			col.Size = size
			rig.Rests[rig.ColIndex] = rest
		end
		if rootPos then
			local rel = pivot:PointToObjectSpace(rootPos)
			local inside
			if sitting then
				local size = col.Size
				local c = rig.Rests[rig.ColIndex].Position
				inside = abs(rel.X - c.X) < size.X / 2 + 0.3 and abs(rel.Z - c.Z) < size.Z / 2 + 0.3 and rel.Y > -1 and rel.Y < size.Y + 3
			else
				local d = Vector3.new(rel.X, 0, rel.Z).Magnitude
				local r = COL_RADIUS * s
				-- (hystérésis : on redevient solide une fois bien sorti)
				inside = d < r + (rig.ColSolid and 0.35 or 1.1) and rel.Y > -3 and rel.Y < COL_HEIGHT * s + 3
			end
			local solid = not inside and reactSolid
			if solid ~= rig.ColSolid then
				rig.ColSolid = solid
				col.CanCollide = solid
			end
		end
	end

	local frames = rig.Frames
	local groups = rig.Groups
	local rests = rig.Rests
	for i = 1, #rig.Parts do
		frames[i] = pivot * T[groups[i]] * rests[i]
	end
	workspace:BulkMoveTo(rig.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

function NPCModels.Animate(model: Model, anim: string, t: number, look: Vector3?)
	local rig = rigOf(model)
	if not rig then
		return
	end
	if anim == "drive" then
		anim = "sit"
	end
	animateRig(model, rig, anim, t, look, nil)
end

-- (v11) Animation ajoutée par un autre module : fn(P, t, seed) écrit les
-- champs de la pose (mêmes noms / conventions que les anims intégrées :
-- LUp / RUp (CFrame), LLo / RLo, LLoRot / RLoRot, LTh / RTh, LKnee / RKnee,
-- LFoot / RFoot, Lean, Twist, Side, SwayX, PelvisYaw, PelvisRoll, HeadYaw /
-- HeadPitch / HeadRoll, Bob, LookW ; + LHand / RHand (pose des doigts),
-- LWrist / RWrist). Appelée pour un PNJ DEBOUT, après la pose de repos et
-- avant le recalage des pieds au sol. Nom inconnu -> "idle".
function NPCModels.AddAnim(name: string, fn: (any, number, number) -> ())
	if type(name) == "string" and type(fn) == "function" then
		CUSTOM[name] = fn
		if not table.find(NPCModels.Anims, name) then
			table.insert(NPCModels.Anims, name)
		end
	end
end

-- Réglages par défaut du poste de conduite (repère : dessus du coussin du
-- siège, avant = -Z) : volant, rayon, plancher
function NPCModels.DriverRest(scale: number?): { WheelOffset: CFrame, WheelRadius: number, Floor: number }
	local s = scale or 1
	return {
		WheelOffset = CFrame.new(0, 1.5 * s, -1.15 * s) * CFrame.Angles(-0.35, 0, 0),
		WheelRadius = 0.62 * s,
		Floor = 1.0 * s,
	}
end

-- Pivot du PNJ assis (au "plancher", hanches 0,15 en arrière du centre du coussin)
local function seatPivot(seatCF: CFrame, floor: number, s: number): CFrame
	return seatCF * CFrame.new(0, -floor, 0.15 * s)
end

-- 🚗 CONDUCTEUR : assis, pieds sur les pédales, mains sur le volant qui
-- tournent avec lui (steer + = vers la gauche), regard dans le virage ;
-- marche arrière : regard par-dessus l'épaule droite (fondu ~0,4 s).
-- opts : { Wheel: CFrame?, WheelRadius: number?, Floor: number?,
--          Recline: number?, Reverse: boolean?, Look: Vector3?, T: number? }
function NPCModels.Driver(model: Model, seatCF: CFrame, steerAngle: number?, opts: { [string]: any }?)
	local rig = rigOf(model)
	if not rig then
		return
	end
	local o = opts or {}
	local s = rig.S
	local rest = NPCModels.DriverRest(s)
	local floor = tonumber(o.Floor) or rest.Floor
	local pivot = seatPivot(seatCF, floor, s)
	NPCModels.Place(model, pivot)
	local wheel: CFrame = if typeof(o.Wheel) == "CFrame" then o.Wheel else seatCF * rest.WheelOffset
	local drive = {
		Wheel = pivot:ToObjectSpace(wheel),
		Radius = tonumber(o.WheelRadius) or rest.WheelRadius,
		Steer = math.clamp(tonumber(steerAngle) or 0, -2.6, 2.6),
		Reverse = o.Reverse == true,
		Recline = tonumber(o.Recline) or 0.18,
		Floor = floor,
	}
	animateRig(model, rig, "drive", tonumber(o.T) or os.clock() + rig.Seed, if typeof(o.Look) == "Vector3" then o.Look else nil, drive)
end

-- 🚗 PASSAGER : même repère de siège, assis détendu (mains sur les cuisses)
function NPCModels.Passenger(model: Model, seatCF: CFrame, t: number?, opts: { [string]: any }?)
	local rig = rigOf(model)
	if not rig then
		return
	end
	local o = opts or {}
	local s = rig.S
	local floor = tonumber(o.Floor) or NPCModels.DriverRest(s).Floor
	NPCModels.Place(model, seatPivot(seatCF, floor, s))
	animateRig(model, rig, "sit", t or (os.clock() + rig.Seed), if typeof(o.Look) == "Vector3" then o.Look else nil, { Floor = floor })
end

-- Point de prise au creux de la main (MONDE) : la laisse, une poignée…
-- side : -1 = gauche, 1 = droite (après Animate)
function NPCModels.HandPoint(model: Model, side: number): Vector3?
	local rig = rigOf(model)
	if not rig then
		return nil
	end
	local sx = side < 0 and -1 or 1
	local idx = rig.PalmIdx[sx]
	if not idx then
		return nil
	end
	-- (paume : X = B, Y = U, Z = -X du repos ; N = -sx X -> +sx Z)
	local palm = rig.Parts[idx]
	local s = rig.S
	return (palm.CFrame * CFrame.new(0, 0.16 * s, sx * 0.075 * s)).Position
end

----------------------------------------------------------------------
-- (v11) 🐕 CHIENS réalistes : races (labrador, beagle, dalmatien, corgi,
-- husky, caniche, teckel, border collie), corps en trois volumes (poitrail,
-- tronc, croupe), cou, tête (crâne, museau, truffe, mâchoire, langue,
-- yeux, oreilles selon la race), pattes à DEUX segments + coussinet (coude /
-- jarret qui plient), queue en deux segments (loutre, fouet, en trompette,
-- moignon, pompon, panache), collier + médaille. ~30 pièces, ancrées, sans
-- collision. Allure : TROT (diagonales), rebond, tête qui suit, queue qui
-- remue ; à l'arrêt : il renifle, regarde autour, halète.
--   NPCModels.BuildDog(seed, breed?) -> Model (non parenté ; pivot au sol,
--     sous le ventre, regard -Z)
--   NPCModels.AnimateDog(model, cf, t, speed)  (speed en studs / s)
--   NPCModels.DogCollar(model) -> Vector3 (point d'attache de la laisse)
--   NPCModels.DogBreeds = { ... }
----------------------------------------------------------------------

type Breed = {
	Name: string,
	Size: number,
	Leg: number,
	Len: number,
	Ears: string,
	Tail: string,
	Coats: { { Color3 } }, -- { base, dessous, dos? }
	Spots: boolean?,
	Fluffy: boolean?,
}

local BREEDS: { Breed } = {
	{ Name = "labrador", Size = 1.0, Leg = 1.0, Len = 1.0, Ears = "flop", Tail = "otter", Coats = { { rgb(224, 186, 124), rgb(236, 206, 156) }, { rgb(40, 36, 36), rgb(52, 46, 44) }, { rgb(102, 66, 44), rgb(118, 78, 52) } } },
	{ Name = "beagle", Size = 0.74, Leg = 0.85, Len = 1.0, Ears = "long", Tail = "whip", Coats = { { rgb(176, 112, 58), rgb(244, 240, 232), rgb(40, 34, 32) } } },
	{ Name = "dalmatien", Size = 1.0, Leg = 1.1, Len = 1.0, Ears = "flop", Tail = "whip", Coats = { { rgb(246, 244, 240), rgb(250, 250, 248) } }, Spots = true },
	{ Name = "corgi", Size = 0.78, Leg = 0.5, Len = 1.15, Ears = "erect", Tail = "stub", Coats = { { rgb(214, 140, 70), rgb(246, 240, 230) } } },
	{ Name = "husky", Size = 1.0, Leg = 1.0, Len = 1.0, Ears = "erect", Tail = "curl", Coats = { { rgb(236, 236, 236), rgb(248, 248, 248), rgb(104, 108, 116) }, { rgb(236, 230, 222), rgb(248, 246, 242), rgb(150, 100, 60) } } },
	{ Name = "caniche", Size = 0.82, Leg = 1.12, Len = 0.9, Ears = "fluffy", Tail = "pom", Coats = { { rgb(250, 248, 244), rgb(250, 248, 244) }, { rgb(214, 160, 112), rgb(224, 176, 130) }, { rgb(36, 34, 36), rgb(46, 44, 46) } }, Fluffy = true },
	{ Name = "teckel", Size = 0.72, Leg = 0.42, Len = 1.55, Ears = "long", Tail = "whip", Coats = { { rgb(140, 70, 36), rgb(156, 84, 46) }, { rgb(36, 30, 28), rgb(160, 96, 50) } } },
	{ Name = "border collie", Size = 0.92, Leg = 1.0, Len = 1.0, Ears = "semi", Tail = "plume", Coats = { { rgb(30, 28, 30), rgb(246, 244, 240) } } },
}
NPCModels.DogBreeds = BREEDS

-- groupes : 0 corps, 1 tête, 2 queue, 3..6 haut des pattes (AvG, AvD, ArG,
-- ArD), 7..10 bas des pattes (+ coussinet)
local DG_BODY, DG_HEAD, DG_TAIL = 0, 1, 2

function NPCModels.BuildDog(seed: number, breedName: string?): Model
	local breed = BREEDS[math.floor(hash(seed, 300) * #BREEDS) % #BREEDS + 1]
	if breedName then
		for _, b in ipairs(BREEDS) do
			if b.Name == breedName then
				breed = b
			end
		end
	end
	local coat = breed.Coats[math.floor(hash(seed, 301) * #breed.Coats) % #breed.Coats + 1]
	local base, under = coat[1], coat[2]
	local back = coat[3]
	local S = breed.Size * (0.94 + hash(seed, 302) * 0.12)
	local m = Instance.new("Model")
	m.Name = "Dog"
	local count = 0
	local fluffy = breed.Fluffy == true
	local furM = fluffy and KNIT or M.SmoothPlastic
	local function part(g: number, name: string, size: Vector3, cf: CFrame, color: Color3, shape: string?, material: Enum.Material?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = name == "DogBarrel" or name == "DogChest"
		p.Size = size * S
		local rest = CFrame.new(cf.Position * S) * cf.Rotation
		p.CFrame = rest
		p.Color = color
		p.Material = material or M.SmoothPlastic
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cyl" then
			p.Shape = Enum.PartType.Cylinder
		elseif shape == "Egg" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p:SetAttribute("DogG", g)
		p:SetAttribute("DogRest", rest)
		p.Parent = m
		count += 1
		return p
	end
	local legH = 1.05 * breed.Leg
	local jy = legH + 0.1
	local L = 1.5 * breed.Len
	local zF, zH = -L * 0.36, L * 0.38
	-- corps
	local bodyShape = fluffy and "Ball" or "Egg"
	part(DG_BODY, "DogChest", fluffy and Vector3.new(0.9, 0.9, 0.9) or Vector3.new(0.78, 0.84, 0.86), CFrame.new(0, jy + 0.28, zF), base, bodyShape, furM)
	part(DG_BODY, "DogBarrel", Vector3.new(0.68, 0.66, L * 0.95), CFrame.new(0, jy + 0.32, 0), base, "Egg")
	part(DG_BODY, "DogRump", fluffy and Vector3.new(0.8, 0.8, 0.8) or Vector3.new(0.72, 0.74, 0.74), CFrame.new(0, jy + 0.34, zH), base, bodyShape, furM)
	part(DG_BODY, "DogBelly", Vector3.new(0.5, 0.3, L * 0.7), CFrame.new(0, jy + 0.1, -0.05), under, "Egg")
	part(DG_BODY, "DogBib", Vector3.new(0.5, 0.56, 0.3), CFrame.new(0, jy + 0.24, zF - 0.33), under, "Egg")
	if back then
		part(DG_BODY, "DogSaddle", Vector3.new(0.7, 0.4, L * 0.78), CFrame.new(0, jy + 0.5, 0.05), back, "Egg")
	end
	if breed.Spots then
		for i = 1, 7 do
			local a = hash(seed, 310 + i)
			local zz = (hash(seed, 320 + i) - 0.5) * L * 0.9
			local sx = (i % 2 == 0) and 1 or -1
			local ang = (a - 0.5) * 1.8
			local r = 0.35
			local p = Vector3.new(sx * math.cos(ang) * r, jy + 0.32 + math.sin(ang) * r * 0.95, zz)
			part(DG_BODY, "DogSpot", Vector3.new(0.03, 0.15, 0.15), CFrame.lookAt(p, p + Vector3.new(sx * math.cos(ang), math.sin(ang), 0)) * CFrame.Angles(0, math.pi / 2, 0), rgb(26, 24, 26), "Cyl")
		end
	end
	-- cou + collier (dans le groupe du corps)
	local neckP = Vector3.new(0, jy + 0.6, zF - 0.3)
	part(DG_BODY, "DogNeck", Vector3.new(0.42, 0.64, 0.48), CFrame.new(neckP) * CFrame.Angles(-0.7, 0, 0), base, "Egg", furM)
	local collarC = pick({ rgb(220, 50, 70), rgb(50, 110, 220), rgb(60, 170, 90), rgb(240, 170, 40), rgb(40, 40, 44) }, seed, 303)
	local collarCF = CFrame.new(neckP + Vector3.new(0, 0.02, -0.04)) * CFrame.Angles(-0.6, 0, 0)
	part(DG_BODY, "DogCollar", Vector3.new(0.08, 0.47, 0.53), collarCF * CFrame.Angles(0, 0, math.pi / 2), collarC, "Cyl")
	part(DG_BODY, "DogTag", Vector3.new(0.09, 0.09, 0.09), collarCF * CFrame.new(0, -0.06, -0.27), rgb(236, 196, 80), "Ball", M.Metal)
	-- tête
	local sk = Vector3.new(0, jy + 0.96, zF - 0.56)
	local muz = breed.Name == "teckel" and 0.56 or (breed.Name == "corgi" and 0.4 or 0.46)
	part(DG_HEAD, "DogSkull", Vector3.new(0.56, 0.52, 0.6), CFrame.new(sk), base, fluffy and "Ball" or "Egg", furM)
	local muzC = (breed.Name == "beagle" or breed.Name == "border collie" or breed.Name == "husky" or breed.Name == "corgi") and under or base
	part(DG_HEAD, "DogMuzzle", Vector3.new(0.32, 0.27, muz), CFrame.new(sk + Vector3.new(0, -0.1, -0.3 - muz * 0.15)), muzC, "Egg")
	part(DG_HEAD, "DogNose", Vector3.new(0.13, 0.11, 0.1), CFrame.new(sk + Vector3.new(0, -0.03, -0.32 - muz * 0.55)), rgb(26, 22, 24), "Egg")
	part(DG_HEAD, "DogJaw", Vector3.new(0.24, 0.09, muz * 0.7), CFrame.new(sk + Vector3.new(0, -0.22, -0.26 - muz * 0.12)), muzC:Lerp(INK, 0.15), "Egg")
	part(DG_HEAD, "DogTongue", Vector3.new(0.11, 0.035, 0.18), CFrame.new(sk + Vector3.new(0, -0.26, -0.3 - muz * 0.3)) * CFrame.Angles(0.5, 0, 0), rgb(226, 110, 130), "Egg")
	local eyeC = breed.Name == "husky" and rgb(120, 170, 230) or rgb(40, 26, 18)
	for _, sx in ipairs({ -1, 1 }) do
		part(DG_HEAD, "DogEye", Vector3.new(0.1, 0.1, 0.07), CFrame.new(sk + Vector3.new(sx * 0.15, 0.06, -0.26)), eyeC, "Egg")
		part(DG_HEAD, "DogPupil", Vector3.new(0.05, 0.05, 0.03), CFrame.new(sk + Vector3.new(sx * 0.152, 0.06, -0.295)), rgb(10, 8, 8), "Egg")
		local earC = back or base:Lerp(INK, 0.12)
		if breed.Name == "dalmatien" then
			earC = rgb(30, 28, 30)
		elseif breed.Name == "border collie" then
			earC = base
		end
		if breed.Ears == "flop" then
			part(DG_HEAD, "DogEar", Vector3.new(0.1, 0.4, 0.28), CFrame.new(sk + Vector3.new(sx * 0.28, -0.07, 0.02)) * CFrame.Angles(0, 0, sx * 0.2), earC, "Egg")
		elseif breed.Ears == "long" then
			part(DG_HEAD, "DogEar", Vector3.new(0.09, 0.6, 0.3), CFrame.new(sk + Vector3.new(sx * 0.28, -0.2, 0.02)) * CFrame.Angles(0, 0, sx * 0.12), earC, "Egg")
		elseif breed.Ears == "fluffy" then
			part(DG_HEAD, "DogEar", Vector3.new(0.3, 0.46, 0.3), CFrame.new(sk + Vector3.new(sx * 0.3, -0.16, 0.04)), base, "Egg", KNIT)
		elseif breed.Ears == "semi" then
			part(DG_HEAD, "DogEar", Vector3.new(0.08, 0.3, 0.22), CFrame.new(sk + Vector3.new(sx * 0.2, 0.28, 0.04)) * CFrame.Angles(-0.5, 0, sx * -0.3), earC, "Egg")
		else -- erect
			part(DG_HEAD, "DogEar", Vector3.new(0.08, 0.4, 0.24), CFrame.new(sk + Vector3.new(sx * 0.18, 0.33, 0.06)) * CFrame.Angles(-0.1, 0, sx * -0.28), earC, "Egg")
		end
	end
	if fluffy then
		part(DG_HEAD, "DogTopknot", Vector3.new(0.42, 0.42, 0.42), CFrame.new(sk + Vector3.new(0, 0.26, 0.04)), base, "Ball", KNIT)
	end
	-- pattes : haut (épaule / hanche) + bas (coude / jarret) + coussinet
	local legs = { { -0.2, zF, 3, 7, true }, { 0.2, zF, 4, 8, true }, { -0.2, zH, 5, 9, false }, { 0.2, zH, 6, 10, false } }
	local paw = under
	if breed.Name == "labrador" or breed.Name == "dalmatien" or breed.Name == "teckel" or breed.Name == "caniche" then
		paw = base
	end
	for _, l in ipairs(legs) do
		local x, z, gu, gl, front = l[1] :: number, l[2] :: number, l[3] :: number, l[4] :: number, l[5] :: boolean
		local upC = base
		if front then
			part(gu, "DogLegUp", Vector3.new(0.22, legH * 0.62, 0.27), CFrame.new(x, jy - legH * 0.27, z), upC, "Egg", furM)
			part(gl, "DogLegLo", Vector3.new(0.16, legH * 0.62, 0.17), CFrame.new(x, jy - legH * 0.72, z - 0.01), paw, "Egg")
		else
			part(gu, "DogThigh", Vector3.new(0.28, legH * 0.62, 0.42), CFrame.new(x, jy - legH * 0.24, z + 0.05), upC, "Egg", furM)
			part(gl, "DogLegLo", Vector3.new(0.15, legH * 0.64, 0.17), CFrame.new(x, jy - legH * 0.7, z + 0.11) * CFrame.Angles(-0.12, 0, 0), paw, "Egg")
		end
		part(gl, "DogPaw", Vector3.new(0.2, 0.12, 0.27), CFrame.new(x, 0.06, z - 0.06 + (front and 0 or 0.1)), paw, "Egg")
	end
	-- queue
	local tb = Vector3.new(0, jy + 0.55, zH + 0.32)
	local function seg(name: string, from: Vector3, dir: Vector3, len: number, w: number, color: Color3, shape: string?, material: Enum.Material?)
		local d = dir.Unit
		local c = from + d * len / 2
		local x = Vector3.new(1, 0, 0)
		part(DG_TAIL, name, Vector3.new(w, len + w * 0.6, w), CFrame.fromMatrix(c, x, d), color, shape or "Egg", material)
		return from + d * len
	end
	local tip = base
	if breed.Name == "beagle" or breed.Name == "border collie" then
		tip = under
	end
	if breed.Tail == "otter" then
		local e = seg("DogTail", tb, Vector3.new(0, -0.55, 1), 0.5, 0.17, base)
		seg("DogTail", e, Vector3.new(0, -1, 0.45), 0.42, 0.12, base)
	elseif breed.Tail == "whip" then
		local e = seg("DogTail", tb, Vector3.new(0, 0.9, 1), 0.42, 0.12, base)
		seg("DogTail", e, Vector3.new(0, 1, 0.3), 0.38, 0.09, tip)
	elseif breed.Tail == "curl" then
		local e = seg("DogTail", tb, Vector3.new(0, 1.2, 0.4), 0.42, 0.2, base, "Egg", KNIT)
		seg("DogTail", e, Vector3.new(0, 0.2, -1), 0.42, 0.18, back or base, "Egg", KNIT)
	elseif breed.Tail == "stub" then
		part(DG_TAIL, "DogTail", Vector3.new(0.18, 0.18, 0.18), CFrame.new(tb + Vector3.new(0, 0, 0.04)), base, "Ball")
	elseif breed.Tail == "pom" then
		local e = seg("DogTail", tb, Vector3.new(0, 1, 0.5), 0.36, 0.08, base)
		part(DG_TAIL, "DogTailPom", Vector3.new(0.3, 0.3, 0.3), CFrame.new(e), base, "Ball", KNIT)
	else -- panache
		local e = seg("DogTail", tb, Vector3.new(0, -0.3, 1), 0.46, 0.2, base, "Egg", KNIT)
		seg("DogTail", e, Vector3.new(0, 0.5, 1), 0.42, 0.18, tip, "Egg", KNIT)
	end
	m:SetAttribute("DogBreed", breed.Name)
	m:SetAttribute("DogScale", S)
	m:SetAttribute("DogLegH", legH)
	m:SetAttribute("DogLen", L)
	m:SetAttribute("PartCount", count)
	return m
end

type DogRig = { Parts: { BasePart }, Rests: { CFrame }, Groups: { number }, Frames: { CFrame }, S: number, Joints: { [number]: Vector3 }, Neck: Vector3, TailBase: Vector3, Tag: BasePart?, Phase: number, LastT: number }
local dogRigs: { [Model]: DogRig } = setmetatable({}, { __mode = "k" }) :: any

local function dogRigOf(model: Model): DogRig?
	local r = dogRigs[model]
	if r then
		return r
	end
	local S = tonumber(model:GetAttribute("DogScale")) or 1
	local legH = tonumber(model:GetAttribute("DogLegH")) or 1.05
	local L = tonumber(model:GetAttribute("DogLen")) or 1.5
	local jy = legH + 0.1
	local zF, zH = -L * 0.36, L * 0.38
	local rig: DogRig = {
		Parts = {},
		Rests = {},
		Groups = {},
		Frames = {},
		S = S,
		Joints = {},
		Neck = Vector3.new(0, jy + 0.72, zF - 0.36) * S,
		TailBase = Vector3.new(0, jy + 0.55, zH + 0.32) * S,
		Tag = nil,
		Phase = 0,
		LastT = 0,
	}
	local xs = { -0.2, 0.2, -0.2, 0.2 }
	local zs = { zF, zF, zH, zH }
	for i = 1, 4 do
		rig.Joints[2 + i] = Vector3.new(xs[i], jy, zs[i]) * S
		rig.Joints[6 + i] = Vector3.new(xs[i], jy - legH * 0.5, zs[i] + (i > 2 and 0.08 or 0)) * S
	end
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			local g = d:GetAttribute("DogG")
			local rest = d:GetAttribute("DogRest")
			if type(g) == "number" and typeof(rest) == "CFrame" then
				table.insert(rig.Parts, d)
				table.insert(rig.Rests, rest)
				table.insert(rig.Groups, g)
				table.insert(rig.Frames, rest)
				if d.Name == "DogTag" then
					rig.Tag = d
				end
			end
		end
	end
	dogRigs[model] = rig
	return rig
end

local DT: { CFrame } = table.create(11, CFrame.new())

-- cf : pivot au sol (regard -Z) ; speed : studs / s (0 = arrêté)
function NPCModels.AnimateDog(model: Model, cf: CFrame, t: number, speed: number?)
	local rig = dogRigOf(model)
	if not rig then
		return
	end
	local S = rig.S
	local v = math.max(0, speed or 0)
	local moving = v > 0.3
	-- phase de l'allure intégrée (la cadence suit la vitesse sans à-coups)
	local dt = math.clamp(t - rig.LastT, 0, 0.25)
	rig.LastT = t
	local freq = math.clamp(v / (1.7 * S), 1.2, 3.6)
	rig.Phase += dt * freq * math.pi * 2
	local w = rig.Phase
	local amp = moving and math.clamp(v / 4, 0.35, 1) or 0
	local bob = moving and abs(sin(w)) * 0.05 * S or sin(t * 7) * 0.006 * S -- (halète à l'arrêt)
	local root = cf * CFrame.new(0, bob, 0) * CFrame.Angles(moving and sin(w * 2) * 0.015 or 0, 0, moving and sin(w) * 0.02 or 0)
	DT[DG_BODY + 1] = root
	-- tête : suit le trot ; à l'arrêt elle regarde autour et renifle le sol
	local sniff = moving and 0 or max(0, sin(t * 0.45 + S * 5)) ^ 3 * 0.6
	local hyaw = moving and sin(t * 0.8) * 0.12 or sin(t * 0.5) * 0.45
	local hp = rig.Neck
	DT[DG_HEAD + 1] = root * CFrame.new(hp) * CFrame.Angles(sniff + (moving and -sin(w * 2) * 0.04 or 0), hyaw, 0) * CFrame.new(-hp)
	local wag = sin(t * (moving and 9 or 12)) * (moving and 0.45 or 0.6)
	local tp = rig.TailBase
	DT[DG_TAIL + 1] = root * CFrame.new(tp) * CFrame.Angles(0, wag, 0) * CFrame.new(-tp)
	for i = 1, 4 do
		local front = i <= 2
		-- trot : diagonales (AvG + ArD, AvD + ArG)
		local ph = (i == 1 or i == 4) and 0 or math.pi
		local a = sin(w + ph) * 0.5 * amp
		local lift = max(0, cos(w + ph)) * amp
		local hip = rig.Joints[2 + i]
		local up = root * CFrame.new(hip) * CFrame.Angles(a, 0, 0) * CFrame.new(-hip)
		DT[3 + i] = up
		local knee = rig.Joints[6 + i]
		local flex = front and -lift * 1.1 or lift * 0.8
		DT[7 + i] = up * CFrame.new(knee) * CFrame.Angles(flex, 0, 0) * CFrame.new(-knee)
	end
	for i = 1, #rig.Parts do
		rig.Frames[i] = DT[rig.Groups[i] + 1] * rig.Rests[i]
	end
	workspace:BulkMoveTo(rig.Parts, rig.Frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Anneau du collier (MONDE), après AnimateDog
function NPCModels.DogCollar(model: Model): Vector3?
	local rig = dogRigOf(model)
	if rig and rig.Tag then
		return rig.Tag.Position
	end
	return nil
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
