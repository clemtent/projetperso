--[[
	Runner (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Runner

	Un "jeu de course infini" façon jeu mobile qui tourne tout seul dans le
	coin en haut à gauche (slot L1, 288x190). v8 :
	  - ciel qui suit un cycle jour / coucher de soleil / nuit / aube (4 min) :
	    soleil qui traverse le ciel puis se couche derrière la ville, lune et
	    étoiles qui scintillent la nuit, nuages teintés selon l'heure ;
	  - ville en parallaxe sur deux plans : silhouettes lointaines dans la
	    brume + immeubles détaillés (façade, flanc ombré, grilles de fenêtres
	    qui s'allument la nuit, antennes, châteaux d'eau) ;
	  - voie en perspective : murs de soutènement (margelle, bordure, piliers,
	    graffitis), arbres derrière les murs, lampadaires (qui éclairent le sol
	    la nuit), trottoirs, ballast, lits de voie sombres, traverses et rails
	    en deux tons qui défilent ;
	  - obstacles : trains détaillés (face avant, flanc et toit en vraie
	    perspective, girouette lumineuse, phares), barrières basses (saut),
	    hautes (glissade), paires de cônes (saut) ;
	  - pièces qui tournent (anneau, reflet, éclat) ; bonus aimant 🧲,
	    pièces x2 et jetpack 🚀, chacun avec son effet visuel ;
	  - HUD : pièces (+ badge x2), distance, record de la session, combo,
	    jauges des bonus ; petits événements ("Beau saut !", "De justesse !")
	    et, de temps en temps, une chute, un écran de fin de course puis une
	    nouvelle partie (le record est gardé pendant la session).
	v9 ("encore mieux") :
	  - coureur plus grand, contours façon dessin animé : bras et jambes
	    articulés (pivots), bras opposés aux jambes, épaules qui tournent,
	    sac à dos à ressort, porte-clés qui se balance, capuche qui rebondit ;
	    figures pendant les sauts (groupé, vrille, étoile) ; il se retourne de
	    temps en temps (visage, clignement des yeux) et réagit : yeux ronds
	    quand un train le frôle, ravi avec un bonus, sonné (yeux en croix,
	    étoiles autour de la tête) après une chute ; bulle d'émoji ;
	  - baskets = amélioration "RunnerShoes" (0 à 10), visibles et mises à
	    jour en direct (ctx.State.Changed) : usées, blanches, sport, lacets de
	    couleur, montantes, semelles néon (halo au sol, traînée lumineuse
	    qui suit les changements de voie), ailes aux talons, bottes à
	    réaction, bottes-fusées en feu ; poussière / étincelles / plumes /
	    braises selon le niveau ; badge "👟 Niv. X" dans le HUD ; un peu plus
	    de vitesse à chaque niveau ; "Nouvelles baskets !" à l'achat ;
	  - décor : grande roue et tour de télévision au loin (lumières la nuit),
	    oiseaux, enseigne "DOPA", pont routier qui passe au-dessus de la voie
	    (ombre sur les rails), vitres des trains allumées la nuit, ombres de
	    contact, vignette ;
	  - pièces ramassées qui filent vers le compteur ; écran de fin avec
	    bandeau "Perdu" et bouton "Rejouer" qui s'enfonce tout seul.
	Tout est dessiné avec des Frames créées une seule fois puis recyclées
	(~800 instances en tout, modificateurs compris ; aucune création pendant
	la partie). Une seule boucle OnRender, en pause quand la carte n'est pas
	visible ; décor d'ambiance à 30 images/s ; couleurs jour / nuit
	recalculées 5 fois par seconde, et seulement pendant les transitions ;
	les propriétés inchangées ne sont pas réécrites (visibilité mémorisée).
	Purement visuel : aucun appel serveur. Tout dérive de la taille du slot.
]]

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Runner = {}
Runner.Slot = "L1"

-- Record de la session (le module reste en mémoire : survit aux redémarrages du stimulus)
local sessionBest = 0

----------------------------------------------------------------------
-- Réglages. Unités "monde" : 1 unité = 1 pixel à la profondeur z = 1
-- pour un écran de 280 px de large (tout est ensuite mis à l'échelle).
----------------------------------------------------------------------
local DESIGN_W = 280
local BEZEL = 4 -- bord du "téléphone"
local CARD_INSET = 2 -- marge dans le slot : le contour n'est pas coupé par le découpage du slot
local Z_NEAR = 0.6 -- en dessous : l'objet est passé derrière la caméra
local Z_FAR = 10 -- apparition au loin
local CHAR_Z = 1.45 -- profondeur du coureur
local LANES = { -80, 0, 80 } -- centre des 3 voies
local RAIL_OFFSET = 22 -- écart des rails autour du centre d'une voie
local WALL_X = 172 -- murs de soutènement
local WALL_H = 70
local COPING_H = 63 -- bas de la margelle
local KERB_H = 10 -- haut de la bordure sombre
-- Bandes au sol (x monde, de gauche à droite) : trottoir, ballast, lit de voie...
local GROUND_EDGES = { -WALL_X, -110, -54, -26, 26, 54, 110, WALL_X }
local TIE_PER_LANE = 6 -- traverses par voie
local TIE_GAP = 0.62
local TIE_START = 0.62
local TIE_DEPTH = 0.1
local TIE_HALF = 31
local POLE_X = 148 -- lampadaires
local POLE_H = 100
local POLE_ARM = 26
local POLE_PER_SIDE = 2
local POLE_GAP = 3
local PILLAR_X = 168 -- piliers des murs
local PILLAR_W = 12
local PILLAR_PER_SIDE = 3
local PILLAR_GAP = 2.2
local TREE_X = 206 -- arbres derrière les murs
local TREE_PER_SIDE = 2
local TREE_GAP = 3.3
local PANEL_LEN = 1.1 -- longueur (en profondeur) d'un graffiti
local TRAIN_W = 66
local TRAIN_H = 86
local TRAIN_LEN = 2.2
local ONCOMING_EXTRA = 2.4 -- vitesse en plus d'un train qui fonce vers nous
local BARRIER_W = 62
local COIN_SIZE = 22
local COIN_H = 24 -- hauteur du centre d'une pièce
local CHAR_W = 46 -- v9 : coureur plus grand (détails et baskets lisibles)
local CHAR_H = 74
-- Proportions du coureur (échelle de son cadre : 0 = haut de la tête, 1 = sol)
local LEG_TOP = 0.61 -- hanches
local LEG_LEN = 0.3
local ARM_LEN = 0.29
local SHOE_W = 0.33
local SHOE_H = 0.15
local JUMP_TIME = 0.58
local JUMP_H = 46
local SLIDE_TIME = 0.62
local JET_H = 100
local JET_TIME = 6.5
local MAGNET_TIME = 8
local DOUBLE_TIME = 10
local BASE_SPEED = 3.3 -- profondeur parcourue par seconde
local MAX_SPEED = 4.9
local SPEED_RAMP = 0.018
local WAVE_GAP = 3.4 -- distance entre deux vagues d'obstacles
local BIG = 900 -- taille des demi-plans
local DAY_LENGTH = 240 -- durée d'un cycle jour / nuit (s)
local COMBO_WINDOW = 0.75 -- délai max entre deux pièces pour garder le combo

local SHOE_SPEED = 0.025 -- vitesse en plus par niveau de "RunnerShoes" (+25 % au niveau 10)
local RIBBON_SEGMENTS = 4 -- traînée lumineuse des baskets : segments par pied
local RIBBON_DZ = 0.2 -- profondeur entre deux points de la traînée
local AMBIENT_STEP = 1 / 30 -- décor d'ambiance (nuages, oiseaux, grande roue) : 30 images/s max
local BRIDGE_LOW = 176 -- dessous du pont (au-dessus de la caméra)
local BRIDGE_TOP = 202
local BRIDGE_DEPTH = 0.42
local BRIDGE_PILLAR_X = WALL_X + 8

local TRAIN_POOL = 2
local BARRIER_POOL = 3
local CONE_POOL = 2
local COIN_POOL = 9
local SPARKLE_POOL = 5
local POP_POOL = 3
local SPEEDLINE_POOL = 5
local DUST_POOL = 7
local SHOE_FX_POOL = 6
local FLYER_POOL = 4
local STAR_COUNT = 6
local BIRD_COUNT = 3

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = rgb(255, 208, 40)
local INK = rgb(22, 20, 36) -- contours des textes

local TRAIN_LIVERIES = {
	{ Body = rgb(226, 62, 78), Accent = rgb(255, 214, 90) },
	{ Body = rgb(40, 124, 226), Accent = rgb(255, 255, 255) },
	{ Body = rgb(250, 176, 36), Accent = rgb(70, 70, 86) },
	{ Body = rgb(30, 172, 118), Accent = rgb(236, 250, 236) },
	{ Body = rgb(138, 84, 222), Accent = rgb(255, 160, 214) },
}

-- Côtés de la voie : murs (couleurs pastel), margelle claire, bordure sombre
local SIDE_DEFS = {
	{ Sign = -1, Wall = rgb(238, 166, 138), Coping = rgb(252, 232, 214), Kerb = rgb(176, 114, 98), Pillar = rgb(216, 142, 116) },
	{ Sign = 1, Wall = rgb(158, 170, 232), Coping = rgb(232, 236, 252), Kerb = rgb(100, 110, 178), Pillar = rgb(134, 146, 214) },
}
-- Couleur des 7 bandes entre les GROUND_EDGES
local GROUND_COLORS = {
	rgb(208, 194, 176), -- trottoir
	rgb(112, 100, 98), -- lit de voie
	rgb(160, 150, 146), -- ballast entre deux voies
	rgb(112, 100, 98),
	rgb(160, 150, 146),
	rgb(112, 100, 98),
	rgb(208, 194, 176),
}
local TIE_COLOR = rgb(126, 88, 62)
local RAIL_BASE = rgb(92, 96, 114)
local RAIL_SHINE = rgb(236, 240, 252)
local BUILDING_COLORS = {
	rgb(244, 188, 168),
	rgb(168, 188, 240),
	rgb(250, 220, 166),
	rgb(190, 168, 230),
	rgb(172, 220, 212),
	rgb(240, 174, 196),
}
local GLASS_DAY = rgb(146, 184, 236)
local WINDOW_NIGHT = rgb(255, 212, 124)
local LAMP_LIGHT = rgb(255, 232, 160)
local TREE_GREEN = rgb(88, 176, 106)
local TRUNK = rgb(126, 88, 62)

local GRAFFITI_WORDS = {
	en = { "DOPA", "WOW", "GG", "LOL", "YOLO", "RUN", "+1", "OMG", "EZ", "POG", "FAST", "GO!" },
	fr = { "DOPA", "WOW", "GG", "LOL", "YOLO", "RUN", "+1", "OMG", "EZ", "POG", "VITE", "GO!" },
}
local GRAFFITI_COLORS = {
	{ rgb(255, 70, 160), rgb(255, 190, 40) },
	{ rgb(40, 210, 230), rgb(150, 80, 240) },
	{ rgb(80, 220, 110), rgb(0, 150, 240) },
	{ rgb(255, 120, 40), rgb(240, 40, 90) },
}

-- Couleurs du coureur
local HOODIE = rgb(255, 98, 62)
local HOODIE_DARK = rgb(206, 62, 42)
local HOODIE_RIB = rgb(232, 76, 50)
local JEANS = rgb(58, 84, 176)
local JEANS_HEM = rgb(92, 124, 214)
local SKIN = rgb(240, 190, 148)
local HAIR = rgb(84, 52, 32)
local CAP = rgb(40, 170, 255)
local CAP_DARK = rgb(18, 112, 206)
local PACK = rgb(255, 204, 44)
local PACK_DARK = rgb(232, 150, 20)
local STRAP = rgb(60, 52, 70)
local JET = rgb(206, 212, 226)
local JET_DARK = rgb(132, 140, 164)
local OUTLINE = rgb(46, 30, 44) -- contours façon dessin animé
local EYE = rgb(40, 28, 36)
local MOUTH = rgb(150, 50, 60)

-- Baskets du coureur (amélioration "RunnerShoes", niveaux 0 à 10) : chaque
-- niveau se voit. Body = tige, Accent = talon, Stripe / Laces = bande et
-- lacets (nil = aucun), Sole = semelle, Glow = lueur néon (semelle qui
-- brille, halo au sol, traînée lumineuse), Wings = ailes aux talons,
-- Flame = propulseurs (1 = bottes à réaction, 2 = bottes-fusées), High =
-- montantes, Trail = style de la traînée (poussière, néon, or, réacteur, feu).
local SHOE_TIERS = {
	[0] = { Body = rgb(178, 172, 164), Accent = rgb(146, 140, 132), Sole = rgb(128, 122, 116), Trail = "Dust" },
	[1] = { Body = rgb(250, 250, 253), Accent = rgb(236, 72, 84), Sole = rgb(236, 72, 84), Trail = "Dust" },
	[2] = { Body = rgb(46, 132, 242), Accent = WHITE, Stripe = WHITE, Sole = rgb(250, 250, 250), Trail = "Dust" },
	[3] = { Body = rgb(232, 52, 64), Accent = WHITE, Stripe = WHITE, Laces = rgb(255, 222, 40), Sole = WHITE, Trail = "Dust" },
	[4] = { Body = rgb(36, 38, 52), Accent = rgb(160, 255, 60), Stripe = rgb(160, 255, 60), Laces = rgb(160, 255, 60), Sole = WHITE, High = true, Trail = "Dust" },
	[5] = { Body = WHITE, Accent = rgb(0, 214, 255), Stripe = rgb(0, 214, 255), Laces = rgb(0, 214, 255), Sole = rgb(60, 244, 255), Glow = rgb(0, 230, 255), Trail = "Neon" },
	[6] = { Body = rgb(140, 60, 236), Accent = rgb(255, 84, 204), Stripe = rgb(60, 240, 255), Laces = rgb(60, 240, 255), Sole = rgb(255, 110, 214), Glow = rgb(255, 70, 200), Trail = "Neon" },
	[7] = { Body = WHITE, Accent = rgb(255, 196, 60), Stripe = rgb(255, 196, 60), Laces = rgb(90, 200, 255), Sole = rgb(140, 226, 255), Glow = rgb(110, 214, 255), Wings = WHITE, Trail = "Neon" },
	[8] = { Body = rgb(255, 200, 48), Accent = WHITE, Stripe = WHITE, Laces = WHITE, Sole = rgb(255, 248, 214), Glow = rgb(255, 214, 80), Wings = rgb(255, 240, 170), Trail = "Gold" },
	[9] = { Body = rgb(206, 214, 230), Accent = rgb(60, 156, 255), Stripe = rgb(60, 156, 255), Laces = rgb(60, 156, 255), Sole = rgb(84, 90, 116), Glow = rgb(80, 176, 255), Flame = 1, Trail = "Jet" },
	[10] = { Body = rgb(228, 40, 54), Accent = rgb(255, 208, 60), Stripe = rgb(255, 208, 60), Laces = rgb(255, 208, 60), Sole = rgb(58, 56, 74), Glow = rgb(255, 150, 40), Flame = 2, Trail = "Fire" },
}
local MAX_SHOE_LEVEL = 10
-- Couleur du badge "👟 Niv. X" et des effets de chaque niveau
local SHOE_BADGE = {
	[0] = rgb(170, 170, 176),
	rgb(255, 96, 108),
	rgb(80, 156, 255),
	rgb(255, 80, 90),
	rgb(160, 255, 60),
	rgb(0, 230, 255),
	rgb(255, 90, 214),
	rgb(140, 222, 255),
	rgb(255, 214, 80),
	rgb(96, 184, 255),
	rgb(255, 176, 40),
}
-- Traînée lumineuse au sol (niveaux 5+) : largeur (unités monde), transparence
-- aux pieds / au bout, couleurs aux pieds / au bout (nil = lueur du niveau)
local SHOE_TRAILS: { [string]: any } = {
	Neon = { Width = 5, Head = 0.15, Tail = 0.92 },
	Gold = { Width = 6, Head = 0.1, Tail = 0.9, TailColor = rgb(255, 150, 40) },
	Jet = { Width = 6, Head = 0.1, Tail = 0.94, HeadColor = rgb(220, 246, 255) },
	Fire = { Width = 8, Head = 0.05, Tail = 0.94, HeadColor = rgb(255, 244, 130), TailColor = rgb(255, 60, 24) },
}

-- Visage (quand il se retourne) : taille de l'œil et de la bouche, hauteur du sourcil
local EXPRESSIONS = {
	Smile = { Eye = Vector2.new(0.16, 0.26), Mouth = Vector2.new(0.32, 0.1), Brow = 0.12 },
	Wow = { Eye = Vector2.new(0.2, 0.32), Mouth = Vector2.new(0.17, 0.22), Brow = 0.02 },
	Happy = { Eye = Vector2.new(0.26, 0.08), Mouth = Vector2.new(0.38, 0.17), Brow = 0.1 },
	Dizzy = { Eye = Vector2.new(0.3, 0.08), Mouth = Vector2.new(0.26, 0.1), Brow = 0.14 },
}

-- Cycle jour / nuit : clés (P = position dans le cycle, 0..1)
local DAWN = {
	Top = rgb(64, 84, 170),
	Mid = rgb(214, 150, 178),
	Low = rgb(255, 202, 164),
	Far = rgb(172, 152, 192),
	Fog = rgb(250, 208, 190),
	Cloud = rgb(255, 222, 216),
	Amb = Color3.new(0.93, 0.85, 0.85),
	Night = 0.3,
}
local DAY = {
	Top = rgb(44, 114, 232),
	Mid = rgb(108, 176, 252),
	Low = rgb(210, 234, 255),
	Far = rgb(168, 188, 232),
	Fog = rgb(228, 238, 255),
	Cloud = WHITE,
	Amb = WHITE,
	Night = 0,
}
local SUNSET = {
	Top = rgb(72, 74, 166),
	Mid = rgb(232, 126, 142),
	Low = rgb(255, 182, 104),
	Far = rgb(196, 134, 158),
	Fog = rgb(255, 188, 148),
	Cloud = rgb(255, 200, 178),
	Amb = Color3.new(1, 0.84, 0.74),
	Night = 0.15,
}
local NIGHT = {
	Top = rgb(10, 14, 46),
	Mid = rgb(30, 40, 100),
	Low = rgb(76, 78, 150),
	Far = rgb(46, 52, 100),
	Fog = rgb(64, 68, 128),
	Cloud = rgb(80, 88, 134),
	Amb = Color3.new(0.52, 0.56, 0.8),
	Night = 1,
}
local SKY_KEYS = {
	{ P = 0, K = DAWN },
	{ P = 0.07, K = DAY },
	{ P = 0.45, K = DAY },
	{ P = 0.54, K = SUNSET },
	{ P = 0.62, K = NIGHT },
	{ P = 0.92, K = NIGHT },
	{ P = 1, K = DAWN },
}

----------------------------------------------------------------------
-- Petits outils (séquences de couleurs : 20 points au maximum)
----------------------------------------------------------------------
local function kp(t: number, color: Color3): ColorSequenceKeypoint
	return ColorSequenceKeypoint.new(t, color)
end

local function nkp(t: number, value: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, value)
end

-- Rayures franches (dégradé à bords nets) : count bandes alternées (count <= 10)
local function stripes(a: Color3, b: Color3, count: number): ColorSequence
	local keypoints = {}
	for i = 0, count - 1 do
		local color = (i % 2 == 0) and a or b
		table.insert(keypoints, kp(i / count, color))
		table.insert(keypoints, kp(math.min(1, (i + 1) / count - 0.002), color))
	end
	keypoints[#keypoints] = kp(1, keypoints[#keypoints].Value)
	return ColorSequence.new(keypoints)
end

-- n "fenêtres" (n <= 4) occupant la part `fill`, séparées par des intervalles
-- égaux : valeur `inside` dans les fenêtres, `outside` ailleurs.
-- Renvoie aussi le début de chaque fenêtre et leur largeur.
local function windowBands(n: number, fill: number, inside: number, outside: number): (NumberSequence, { number }, number)
	local w = fill / n
	local g = (1 - fill) / (n + 1)
	local points = { nkp(0, outside) }
	local starts = {}
	for k = 0, n - 1 do
		local s = g + k * (w + g)
		table.insert(points, nkp(s - 0.002, outside))
		table.insert(points, nkp(s, inside))
		table.insert(points, nkp(s + w, inside))
		table.insert(points, nkp(s + w + 0.002, outside))
		table.insert(starts, s)
	end
	table.insert(points, nkp(1, outside))
	return NumberSequence.new(points), starts, w
end

-- Couleur par colonne de fenêtres (gris = fenêtre éteinte, blanc = allumée)
local function columnMask(starts: { number }, width: number, values: { number }): ColorSequence
	local points = {}
	for k, s in ipairs(starts) do
		local v = values[k] or 1
		local c = Color3.new(v, v, v)
		if k == 1 then
			table.insert(points, kp(0, c))
		end
		table.insert(points, kp(s, c))
		table.insert(points, kp(s + width, c))
		if k == #starts then
			table.insert(points, kp(1, c))
		end
	end
	return ColorSequence.new(points)
end

local function mulColor(c: Color3, a: Color3): Color3
	return Color3.new(c.R * a.R, c.G * a.G, c.B * a.B)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Couleurs du ciel à la position p du cycle (interpolées entre deux clés)
local function sampleSky(p: number)
	for i = 1, #SKY_KEYS - 1 do
		local a, b = SKY_KEYS[i], SKY_KEYS[i + 1]
		if p >= a.P and p <= b.P then
			local t = smooth((p - a.P) / (b.P - a.P))
			local ka, kb = a.K, b.K
			return {
				Top = ka.Top:Lerp(kb.Top, t),
				Mid = ka.Mid:Lerp(kb.Mid, t),
				Low = ka.Low:Lerp(kb.Low, t),
				Far = ka.Far:Lerp(kb.Far, t),
				Fog = ka.Fog:Lerp(kb.Fog, t),
				Cloud = ka.Cloud:Lerp(kb.Cloud, t),
				Amb = ka.Amb:Lerp(kb.Amb, t),
				Night = ka.Night + (kb.Night - ka.Night) * t,
			}
		end
	end
	return DAY
end

function Runner.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()
	local withSpaces = ctx.Format.WithSpaces

	------------------------------------------------------------------
	-- Géométrie de l'écran et projection
	------------------------------------------------------------------
	local slotSize = ctx.GetSlotSize and ctx.GetSlotSize() or Vector2.new(288, 190)
	local slotW = slotSize.X > 0 and slotSize.X or 288
	local slotH = slotSize.Y > 0 and slotSize.Y or 190
	local SW = slotW - CARD_INSET * 2 - BEZEL * 2
	local SH = slotH - CARD_INSET * 2 - BEZEL * 2
	local U = SW / DESIGN_W -- facteur d'échelle
	local CX = SW / 2
	local HY = math.floor(SH * 0.41) -- ligne d'horizon
	local CAM_H = (SH - HY + 8 * U) / U -- hauteur de la caméra (sol à z = 1 : juste sous l'écran)
	local VP = Vector2.new(CX, HY) -- point de fuite
	local BELOW = Vector2.new(CX, SH + 400) -- point toujours "sous" les droites qui passent par le point de fuite

	local camX = 0 -- la caméra suit un peu le coureur

	local function sx(wx: number, z: number): number
		return CX + (wx - camX) * U / z
	end
	local function sy(wy: number, z: number): number
		return HY + (CAM_H - wy) * U / z
	end

	-- Ordre d'affichage selon la profondeur (plus proche = au-dessus)
	local function depthZ(z: number): number
		return 20 + math.clamp(math.floor((Z_FAR + 3 - z) * 8), 0, 110)
	end

	-- 0 avant `from`, 1 à partir de `to`
	local function fade(z: number, from: number, to: number): number
		return math.clamp((z - from) / (to - from), 0, 1)
	end

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function frame(props: { [string]: any }, radius: UDim?): Frame
		props.BorderSizePixel = 0
		local f = Create("Frame", props)
		if radius then
			UIUtil.Corner(f, radius)
		end
		return f
	end

	local ROUND = UDim.new(1, 0)

	-- Visibilité mémorisée côté Lua : la propriété n'est écrite que si elle
	-- change (des centaines de cadres sont mis à jour à chaque image)
	local shown: { [GuiObject]: boolean } = {}
	local function show(f: GuiObject, visible: boolean)
		if shown[f] ~= visible then
			shown[f] = visible
			f.Visible = visible
		end
	end

	-- Place un grand cadre tourné dont un bord suit la droite p1 -> p2, du côté de `toward`
	local function setHalfPlane(f: Frame, origin: Vector2, p1: Vector2, p2: Vector2, toward: Vector2)
		local delta = p2 - p1
		local length = delta.Magnitude
		if length < 1e-3 then
			show(f, false)
			return
		end
		show(f, true)
		local dir = delta / length
		local normal = Vector2.new(-dir.Y, dir.X)
		if (toward - p1):Dot(normal) < 0 then
			normal = -normal
		end
		local center = (p1 + p2) / 2 + normal * (BIG / 2) - origin
		f.Position = UDim2.fromOffset(center.X, center.Y)
		f.Size = UDim2.fromOffset(length + BIG * 2, BIG)
		f.Rotation = math.deg(math.atan2(dir.Y, dir.X))
	end

	-- Place un trait (cadre centré, AnchorPoint 0.5) entre deux points
	local function setLine(f: Frame, p1: Vector2, p2: Vector2, thickness: number)
		local delta = p2 - p1
		local mid = (p1 + p2) / 2
		f.Position = UDim2.fromOffset(mid.X, mid.Y)
		f.Size = UDim2.fromOffset(delta.Magnitude, thickness)
		f.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end

	------------------------------------------------------------------
	-- Lumière ambiante : les cadres "teintés" gardent leur couleur de jour
	-- et sont multipliés par la lumière (jour, coucher de soleil, nuit)
	------------------------------------------------------------------
	local ambient = WHITE
	local tintList: { GuiObject } = {}
	local tintBase: { [GuiObject]: Color3 } = {}
	local tinted: { [GuiObject]: boolean } = {}
	local function tint(inst: any, color: Color3): any
		if not tinted[inst] then
			tinted[inst] = true
			table.insert(tintList, inst)
		end
		tintBase[inst] = color
		inst.BackgroundColor3 = mulColor(color, ambient)
		return inst
	end
	-- Couleur "lumineuse" (néon, flammes) : jamais assombrie par la nuit
	local function glowColor(inst: any, color: Color3): any
		tintBase[inst] = nil
		inst.BackgroundColor3 = color
		return inst
	end

	------------------------------------------------------------------
	-- Cadre "téléphone" + écran (le ciel est le dégradé de l'écran)
	------------------------------------------------------------------
	local device = frame({
		Name = "RunnerDevice",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -CARD_INSET * 2, 1, -CARD_INSET * 2),
		BackgroundColor3 = rgb(26, 26, 36),
		Parent = container,
	}, UDim.new(0, 12))
	UIUtil.Gradient(device, ColorSequence.new(rgb(70, 72, 92), rgb(24, 24, 34)), 90)
	UIUtil.Stroke(device, Theme.Colors.Border, 2)

	local screen = frame({
		Name = "Screen",
		Position = UDim2.fromOffset(BEZEL, BEZEL),
		Size = UDim2.fromOffset(SW, SH),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = device,
	}, UDim.new(0, 8))
	local horizonT = math.clamp(HY / SH, 0.2, 0.8)
	local skyGradient = UIUtil.Gradient(screen, ColorSequence.new(WHITE), 90)
	local function skySequence(top: Color3, mid: Color3, low: Color3): ColorSequence
		return ColorSequence.new({
			kp(0, top),
			kp(horizonT * 0.55, mid),
			kp(horizonT * 0.97, low),
			kp(1, low),
		})
	end

	-- Tout le décor est dans "Scene" (qu'on secoue lors d'une chute)
	local scene = frame({
		Name = "Scene",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = screen,
	})
	local function layer(name: string, zIndex: number, parent: Instance?): Frame
		return frame({
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Parent = parent or scene,
		})
	end
	local skyLayer = layer("Sky", 1)

	------------------------------------------------------------------
	-- Étoiles, soleil, lune
	------------------------------------------------------------------
	local stars = {}
	for i = 1, STAR_COUNT do
		local size = (i % 4 == 0 and 2.6 or 1.6) * U
		table.insert(stars, {
			Frame = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(random:NextNumber(0.03, 0.97) * SW, random:NextNumber(0.04, 0.72) * HY),
				Size = UDim2.fromOffset(size, size),
				Rotation = 45,
				BackgroundColor3 = (i % 3 == 0) and rgb(255, 240, 200) or WHITE,
				BackgroundTransparency = 1,
				ZIndex = 1,
				Parent = skyLayer,
			}),
			Phase = random:NextNumber(0, 6.3),
		})
	end

	local function disc(size: number, color: Color3, transparency: number, zIndex: number, parent: Instance): Frame
		return frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			ZIndex = zIndex,
			Parent = parent,
		}, ROUND)
	end
	local sky = {}
	sky.SunGlowOuter = disc(86 * U, rgb(255, 246, 200), 0.82, 2, skyLayer)
	sky.Sun = disc(26 * U, WHITE, 0, 2, skyLayer)
	sky.SunGradient = UIUtil.Gradient(sky.Sun, ColorSequence.new(rgb(255, 255, 232), rgb(255, 206, 80)), 90)
	sky.MoonGlow = disc(48 * U, rgb(200, 214, 255), 0.85, 2, skyLayer)
	sky.Moon = disc(20 * U, rgb(246, 244, 232), 0, 2, skyLayer)
	UIUtil.Gradient(sky.Moon, ColorSequence.new(WHITE, rgb(214, 210, 196)), 60)
	for _, crater in ipairs({ { 0.36, 0.4, 0.28 } }) do
		frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(crater[1], crater[2]),
			Size = UDim2.fromScale(crater[3], crater[3]),
			BackgroundColor3 = rgb(206, 202, 188),
			ZIndex = 2,
			Parent = sky.Moon,
		}, ROUND)
	end

	------------------------------------------------------------------
	-- Nuages (4, qui dérivent ; parallaxe légère ; couleur selon l'heure)
	------------------------------------------------------------------
	local clouds = {}
	for i = 1, 3 do
		local width = random:NextNumber(44, 66) * U
		local base = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(width, width * 0.32),
			BackgroundColor3 = WHITE,
			ZIndex = 3,
			Parent = skyLayer,
		}, ROUND)
		local puffs = { base }
		table.insert(puffs, frame({
			Position = UDim2.fromScale(0.16, -0.62),
			Size = UDim2.fromScale(0.46, 1.25),
			BackgroundColor3 = WHITE,
			ZIndex = 3,
			Parent = base,
		}, ROUND))
		table.insert(clouds, {
			Frame = base,
			Puffs = puffs,
			X = SW * (i - 0.5) / 3 + random:NextNumber(-16, 16) * U,
			Y = random:NextNumber(0.42, 0.72) * HY,
			Width = width,
			Speed = random:NextNumber(3, 8) * U,
			Parallax = 0.03 + i * 0.012,
		})
	end

	------------------------------------------------------------------
	-- Oiseaux (petits "V" qui battent des ailes, le jour seulement)
	------------------------------------------------------------------
	local birds = {}
	for i = 1, BIRD_COUNT do
		local holder = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(9 * U, 5 * U),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = skyLayer,
		})
		-- (Roblox tourne un cadre autour de son centre : chaque aile est
		-- replacée pour que son bout intérieur reste collé au corps)
		local wings = {}
		for _, sideSign in ipairs({ -1, 1 }) do
			table.insert(wings, {
				Frame = frame({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(4.6 * U, math.max(1, 1.3 * U)),
					BackgroundColor3 = rgb(70, 72, 96),
					ZIndex = 1,
					Parent = holder,
				}, ROUND),
				Sign = sideSign,
			})
		end
		table.insert(birds, {
			Holder = holder,
			Wings = wings,
			X = random:NextNumber(0, SW),
			Y = random:NextNumber(0.25, 0.6) * HY,
			Speed = random:NextNumber(7, 12) * U,
			Phase = random:NextNumber(0, 6),
			Flap = random:NextNumber(9, 12) + i,
		})
	end

	------------------------------------------------------------------
	-- Ville : silhouettes lointaines (brume) + immeubles détaillés.
	-- Les calques sont plus larges que l'écran pour la parallaxe.
	------------------------------------------------------------------
	local SKY_MARGIN = 26 * U
	local city: any = { Far = {}, Mid = {} }
	city.FarHolder = frame({
		Name = "CityFar",
		Position = UDim2.fromOffset(-SKY_MARGIN, 0),
		Size = UDim2.fromOffset(SW + SKY_MARGIN * 2, SH),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = scene,
	})
	do
		local totalW = SW + SKY_MARGIN * 2
		local count = 9
		local step = totalW / count
		for i = 1, count do
			local w = step * random:NextNumber(0.8, 1.25)
			local h = random:NextNumber(16, 44) * U
			if i % 4 == 2 then
				h += 14 * U -- une tour plus haute de temps en temps
			end
			local b = frame({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromOffset((i - 1) * step - step * 0.1, HY + 3 * U),
				Size = UDim2.fromOffset(w, h + 3 * U),
				BackgroundColor3 = WHITE,
				ZIndex = 1,
				Parent = city.FarHolder,
			})
			local entry = { Frame = b, Shade = random:NextNumber(0.9, 1.06), Antenna = nil :: Frame? }
			if i % 4 == 2 then
				entry.Antenna = frame({
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.new(0, math.max(1, 1.5 * U), 0, 12 * U),
					BackgroundColor3 = WHITE,
					ZIndex = 1,
					Parent = b,
				})
			end
			table.insert(city.Far, entry)
		end
	end

	-- Monuments lointains (silhouettes dans la brume) : grande roue qui
	-- tourne (nacelles, lumières roses la nuit) et tour de télévision (feu
	-- rouge qui clignote au sommet la nuit)
	city.Landmarks = {} -- cadres colorés comme les silhouettes lointaines
	do
		local totalW = SW + SKY_MARGIN * 2
		local wheelD = 50 * U
		local cx, cy = totalW * 0.6, HY - 22 * U
		local wheel = {
			Center = Vector2.new(cx, cy),
			Radius = wheelD / 2,
			Angle = 0,
			Spokes = {},
			Gondolas = {},
		}
		for _, sideSign in ipairs({ -1, 1 }) do
			local leg = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				ZIndex = 1,
				Parent = city.FarHolder,
			})
			setLine(leg, Vector2.new(cx, cy), Vector2.new(cx + sideSign * wheelD * 0.34, HY + 3 * U), math.max(1, 1.6 * U))
			table.insert(city.Landmarks, leg)
		end
		wheel.Ring = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(wheelD, wheelD),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = city.FarHolder,
		}, ROUND)
		wheel.RingStroke = UIUtil.Stroke(wheel.Ring, WHITE, math.max(1, 1.5 * U), 0)
		for k = 1, 3 do
			local spoke = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx, cy),
				Size = UDim2.fromOffset(wheelD, math.max(1, 0.8 * U)),
				BackgroundColor3 = WHITE,
				ZIndex = 1,
				Parent = city.FarHolder,
			})
			table.insert(wheel.Spokes, { Frame = spoke, Base = (k - 1) * 60 })
			table.insert(city.Landmarks, spoke)
		end
		for k = 1, 6 do
			table.insert(wheel.Gondolas, {
				Frame = frame({
					AnchorPoint = Vector2.new(0.5, 0.2),
					Size = UDim2.fromOffset(math.max(2, 3.2 * U), math.max(2, 3.4 * U)),
					BackgroundColor3 = WHITE,
					ZIndex = 3,
					Parent = city.FarHolder,
				}, UDim.new(0.3, 0)),
				Base = (k - 1) * math.pi / 3,
			})
		end
		wheel.Hub = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(4 * U, 4 * U),
			BackgroundColor3 = WHITE,
			ZIndex = 3,
			Parent = city.FarHolder,
		}, ROUND)
		table.insert(city.Landmarks, wheel.Hub)
		city.Wheel = wheel

		-- Tour de télévision : fût, cabine, antenne et feu rouge
		local tx = totalW * 0.36
		local shaft = frame({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(tx, HY + 3 * U),
			Size = UDim2.fromOffset(math.max(2, 4.5 * U), 54 * U),
			BackgroundColor3 = WHITE,
			ZIndex = 1,
			Parent = city.FarHolder,
		})
		local pod = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(tx, HY + 3 * U - 42 * U),
			Size = UDim2.fromOffset(15 * U, 8 * U),
			BackgroundColor3 = WHITE,
			ZIndex = 1,
			Parent = city.FarHolder,
		}, ROUND)
		local needle = frame({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(tx, HY + 3 * U - 54 * U),
			Size = UDim2.fromOffset(math.max(1, 1.2 * U), 12 * U),
			BackgroundColor3 = WHITE,
			ZIndex = 1,
			Parent = city.FarHolder,
		})
		table.insert(city.Landmarks, shaft)
		table.insert(city.Landmarks, pod)
		table.insert(city.Landmarks, needle)
		city.TowerLight = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(tx, HY + 3 * U - 66 * U),
			Size = UDim2.fromOffset(math.max(2, 3 * U), math.max(2, 3 * U)),
			BackgroundColor3 = rgb(255, 60, 60),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = city.FarHolder,
		}, ROUND)
	end
	-- Brume devant les silhouettes lointaines
	city.Haze = frame({
		Name = "Haze",
		Position = UDim2.fromOffset(0, HY - 34 * U),
		Size = UDim2.fromOffset(SW, 40 * U),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = scene,
	})
	UIUtil.Gradient(city.Haze, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new({
		nkp(0, 1),
		nkp(0.75, 0.35),
		nkp(1, 0.2),
	})

	city.MidHolder = frame({
		Name = "CityMid",
		Position = UDim2.fromOffset(-SKY_MARGIN, 0),
		Size = UDim2.fromOffset(SW + SKY_MARGIN * 2, SH),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = scene,
	})
	do
		local totalW = SW + SKY_MARGIN * 2
		local count = 5
		local step = totalW / count
		local baseY = HY + 50 * U -- le bas est caché par les murs
		local faceShade = ColorSequence.new({
			kp(0, WHITE),
			kp(0.72, WHITE),
			kp(0.725, rgb(190, 190, 206)),
			kp(1, rgb(170, 170, 190)),
		})
		for i = 1, count do
			local w = step * random:NextNumber(0.84, 1.02)
			local h = random:NextNumber(16, 40) * U + (i % 3 == 1 and 10 * U or 0)
			local x = (i - 1) * step + random:NextNumber(-3, 3) * U
			local total = h + (baseY - HY)
			local body = frame({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromOffset(x, baseY),
				Size = UDim2.fromOffset(w, total),
				BackgroundColor3 = WHITE,
				ZIndex = (i % 2 == 0) and 2 or 1,
				Parent = city.MidHolder,
			})
			UIUtil.Gradient(body, faceShade, 0)
			local building = {
				Body = body,
				Base = BUILDING_COLORS[(i - 1) % #BUILDING_COLORS + 1],
				Blocks = {},
				Extras = {},
			}
			-- 1 ou 2 blocs de fenêtres (4 colonnes x 4 étages au plus par bloc)
			local columns = random:NextInteger(3, 4)
			local blockCount = 1
			local topPad = 5 * U / total
			local usable = math.min(h + 14 * U, 46 * U) / total
			for blockIndex = 1, blockCount do
				local blockH = usable / blockCount
				local windows = frame({
					Position = UDim2.fromScale(0.06, topPad + (blockIndex - 1) * blockH),
					Size = UDim2.fromScale(0.64, blockH - 0.012),
					BackgroundColor3 = GLASS_DAY,
					ZIndex = 2,
					Parent = body,
				})
				local transparency, starts, width = windowBands(columns, 0.66, 0, 1)
				local gradient = UIUtil.Gradient(windows, ColorSequence.new(WHITE), 0)
				gradient.Transparency = transparency
				local dayValues, nightValues = {}, {}
				for c = 1, columns do
					dayValues[c] = random:NextNumber(0.82, 1)
					nightValues[c] = (random:NextNumber() < 0.7) and random:NextNumber(0.85, 1) or 0.28
				end
				-- Étages : bandes de façade devant les fenêtres
				local floors = frame({
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = WHITE,
					ZIndex = 1,
					Parent = windows,
				})
				local rows = random:NextInteger(3, 4)
				local floorGradient = UIUtil.Gradient(floors, ColorSequence.new(WHITE), 90)
				floorGradient.Transparency = (windowBands(rows, 0.6, 1, 0))
				table.insert(building.Blocks, {
					Windows = windows,
					Gradient = gradient,
					Floors = floors,
					DayMask = columnMask(starts, width, dayValues),
					NightMask = columnMask(starts, width, nightValues),
				})
			end
			-- Détail de toit : antenne, château d'eau ou édicule
			local roofKind = i % 4
			if roofKind == 0 then
				table.insert(building.Extras, frame({
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.3, 0),
					Size = UDim2.new(0, math.max(1, 1.5 * U), 0, 11 * U),
					BackgroundColor3 = WHITE,
					ZIndex = 1,
					Parent = body,
				}))
			elseif roofKind == 2 then
				table.insert(building.Extras, frame({
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.62, 0, 0, 0),
					Size = UDim2.fromOffset(9 * U, 8 * U),
					BackgroundColor3 = WHITE,
					ZIndex = 1,
					Parent = body,
				}))
			elseif roofKind == 3 then
				-- Enseigne lumineuse "DOPA" sur la façade (brille aussi la nuit)
				table.insert(building.Extras, frame({
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0.12, 0),
					Size = UDim2.new(0.34, 0, 0, 5 * U),
					BackgroundColor3 = WHITE,
					ZIndex = 1,
					Parent = body,
				}))
				local board = frame({
					Name = "Billboard",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.62, 0, 0, 3 * U),
					Size = UDim2.fromOffset(32 * U, 11 * U),
					BackgroundColor3 = WHITE,
					ZIndex = 3,
					Parent = body,
				}, UDim.new(0, 2 * U))
				UIUtil.Gradient(board, ColorSequence.new(rgb(255, 64, 160), rgb(255, 170, 40)), 0)
				UIUtil.Stroke(board, rgb(40, 30, 60), math.max(1, 1.2 * U), 0.2)
				local label = UIUtil.Label({
					Text = "🧠 DOPA",
					Font = Enum.Font.LuckiestGuy,
					TextColor3 = WHITE,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.55),
					Size = UDim2.fromScale(0.9, 0.8),
					MaxTextSize = math.max(8, math.floor(11 * U)),
					ZIndex = 4,
					Parent = board,
				})
				label.TextStrokeColor3 = rgb(120, 20, 70)
				label.TextStrokeTransparency = 0.2
				city.Billboard = board
			end
			table.insert(city.Mid, building)
		end
	end

	------------------------------------------------------------------
	-- Murs et sol en perspective : demi-plans (grands cadres tournés)
	-- découpés par deux zones (gauche / droite du point de fuite)
	------------------------------------------------------------------
	local sides = {}
	for _, def in ipairs(SIDE_DEFS) do
		local s = def.Sign
		local originX = s < 0 and 0 or CX
		local clip = frame({
			Name = s < 0 and "LeftSide" or "RightSide",
			Position = UDim2.fromOffset(originX, 0),
			Size = UDim2.fromOffset(s < 0 and CX or SW - CX, SH),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 5,
			Parent = scene,
		})
		local function plane(color: Color3, zIndex: number): Frame
			return tint(
				frame({
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = color,
					ZIndex = zIndex,
					Parent = clip,
				}),
				color
			)
		end
		-- (ZIndex 1 : arbres ; 5 : graffitis ; 6 : piliers)
		local side = {
			Sign = s,
			Def = def,
			Origin = Vector2.new(originX, 0),
			Clip = clip,
			Coping = plane(def.Coping, 2),
			Wall = plane(def.Wall, 3),
			Kerb = plane(def.Kerb, 4),
			Cap = plane(WHITE, 7),
			Bands = {},
		}
		side.Cap.BackgroundTransparency = 0.35
		UIUtil.Gradient(side.Wall, ColorSequence.new(WHITE, rgb(222, 222, 232)), 90)
		-- Bandes au sol : à gauche, la bande à droite de chaque limite ;
		-- à droite, la bande à gauche (voir updateStatic)
		for index = 1, #GROUND_EDGES do
			local colorIndex = s < 0 and index or index - 1
			local color = GROUND_COLORS[colorIndex]
			if color then
				local zIndex = 8 + (s < 0 and index or (#GROUND_EDGES + 1 - index))
				side.Bands[index] = plane(color, zIndex)
			end
		end
		table.insert(sides, side)
	end

	------------------------------------------------------------------
	-- Voie : traverses (qui défilent) et rails
	------------------------------------------------------------------
	local track = layer("Track", 6)

	local ties = {}
	for _, laneX in ipairs(LANES) do
		for i = 1, TIE_PER_LANE do
			local tie = frame({
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = TIE_COLOR,
				ZIndex = 1,
				Parent = track,
			})
			tint(tie, TIE_COLOR)
			table.insert(ties, { Frame = tie, X = laneX, Offset = (i - 1) * TIE_GAP, Alpha = -1 })
		end
	end
	local TIE_CYCLE = TIE_PER_LANE * TIE_GAP

	-- Chaque rail : acier + reflet ; le bout lointain s'estompe dans la brume
	local rails = {}
	for _, laneX in ipairs(LANES) do
		for _, offset in ipairs({ -RAIL_OFFSET, RAIL_OFFSET }) do
			do
				local base = tint(
					frame({
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = RAIL_BASE,
						ZIndex = 2,
						Parent = track,
					}),
					RAIL_BASE
				)
				local shine = tint(
					frame({
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = RAIL_SHINE,
						ZIndex = 3,
						Parent = track,
					}),
					RAIL_SHINE
				)
				UIUtil.Gradient(base, ColorSequence.new(WHITE), 0).Transparency = NumberSequence.new({
					nkp(0, 0.85),
					nkp(0.25, 0.1),
					nkp(1, 0),
				})
				table.insert(rails, { Base = base, Shine = shine, X = laneX + offset })
			end
		end
	end

	local function worldPoint(wx: number, wy: number): Vector2
		return Vector2.new(sx(wx, 1), sy(wy, 1))
	end

	-- Recalcule murs, sol et rails (seulement quand la caméra bouge)
	local function updateStatic()
		for _, side in ipairs(sides) do
			local s = side.Sign
			local origin = side.Origin
			local top = worldPoint(s * WALL_X, WALL_H)
			setHalfPlane(side.Coping, origin, VP, top, BELOW)
			setHalfPlane(side.Wall, origin, VP, worldPoint(s * WALL_X, COPING_H), BELOW)
			setHalfPlane(side.Kerb, origin, VP, worldPoint(s * WALL_X, KERB_H), BELOW)
			setLine(side.Cap, VP - origin, top - origin, math.max(1, 1.6 * U))
			for index, band in pairs(side.Bands) do
				local edge = GROUND_EDGES[index]
				local onThisSide = (s < 0 and edge < camX) or (s > 0 and edge > camX)
				if onThisSide then
					setHalfPlane(band, origin, VP, worldPoint(edge, 0), BELOW)
				else
					show(band, false)
				end
			end
		end
		for _, rail in ipairs(rails) do
			local far = Vector2.new(sx(rail.X, Z_FAR), sy(0, Z_FAR))
			local near = Vector2.new(sx(rail.X, 0.72), sy(0, 0.72))
			setLine(rail.Base, far, near, math.max(1.4, 2.6 * U))
			setLine(rail.Shine, far, near, math.max(0.8, 1 * U))
		end
	end

	------------------------------------------------------------------
	-- Décor des murs : arbres derrière, graffitis, piliers
	------------------------------------------------------------------
	local trees = {}
	for sideIndex, side in ipairs(sides) do
		for i = 1, TREE_PER_SIDE do
			local trunk = tint(
				frame({
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundColor3 = TRUNK,
					ZIndex = 1,
					Parent = side.Clip,
				}),
				TRUNK
			)
			local crown = tint(
				frame({
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = TREE_GREEN,
					ZIndex = 1,
					Parent = side.Clip,
				}, ROUND),
				TREE_GREEN
			)
			UIUtil.Gradient(crown, ColorSequence.new({
				kp(0, rgb(255, 255, 230)),
				kp(0.35, WHITE),
				kp(1, rgb(150, 176, 166)),
			}), sideIndex == 1 and 60 or 120)
			table.insert(trees, {
				Trunk = trunk,
				Crown = crown,
				Sign = side.Sign,
				Offset = (i - 1) * TREE_GAP + (side.Sign > 0 and TREE_GAP * 0.45 or 0),
				Size = random:NextNumber(0.9, 1.15),
			})
		end
	end
	local TREE_CYCLE = TREE_PER_SIDE * TREE_GAP

	local pillars = {}
	for _, side in ipairs(sides) do
		for i = 1, PILLAR_PER_SIDE do
			local pillar = tint(
				frame({
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundColor3 = side.Def.Pillar,
					ZIndex = 6,
					Parent = side.Clip,
				}),
				side.Def.Pillar
			)

			table.insert(pillars, {
				Frame = pillar,
				Sign = side.Sign,
				Offset = (i - 1) * PILLAR_GAP + (side.Sign > 0 and PILLAR_GAP * 0.5 or 0),
				Alpha = -1,
			})
		end
	end
	local PILLAR_CYCLE = PILLAR_PER_SIDE * PILLAR_GAP

	-- Graffitis sur les murs (2, recyclés)
	local panels = {}
	local function restylePanel(panel)
		local side = sides[random:NextInteger(1, 2)]
		panel.Side = side
		panel.Frame.Parent = side.Clip
		local colors = GRAFFITI_COLORS[random:NextInteger(1, #GRAFFITI_COLORS)]
		panel.Gradient.Color = ColorSequence.new(colors[1], colors[2])
		panel.Gradient.Rotation = random:NextInteger(0, 1) * 90 + random:NextNumber(-20, 20)
		local graffitiWords = Locale.Pick(GRAFFITI_WORDS)
		panel.Label.Text = graffitiWords[random:NextInteger(1, #graffitiWords)]
		panel.Label.Rotation = random:NextNumber(-10, 10)
	end
	for i = 1, 1 do
		local f = tint(
			frame({
				BackgroundColor3 = WHITE,
				ZIndex = 5,
				Visible = false,
				Parent = sides[1].Clip,
			}, UDim.new(0.16, 0)),
			WHITE
		)
		local label = UIUtil.Label({
			Text = "",
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = WHITE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.54),
			Size = UDim2.fromScale(0.84, 0.7),
			ZIndex = 5,
			MaxTextSize = 60,
			Parent = f,
		})
		local sizeConstraint = label:FindFirstChildOfClass("UITextSizeConstraint")
		if sizeConstraint then
			sizeConstraint.MinTextSize = 1 -- au loin, le graffiti devient minuscule
		end
		label.TextStrokeColor3 = rgb(30, 24, 40)
		label.TextStrokeTransparency = 0
		local panel = {
			Frame = f,
			Gradient = UIUtil.Gradient(f, ColorSequence.new(WHITE), 0),
			Label = label,
			Z = 3 + i * 3.8,
			Side = sides[1],
		}
		restylePanel(panel)
		table.insert(panels, panel)
	end

	------------------------------------------------------------------
	-- Monde (objets triés par profondeur)
	------------------------------------------------------------------
	local world = layer("World", 7)

	-- Brume à l'horizon : les objets lointains en sortent doucement
	local fog = frame({
		Name = "Fog",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(CX, HY - 4 * U),
		Size = UDim2.fromOffset(SW * 0.6, 24 * U),
		BackgroundColor3 = WHITE,
		ZIndex = depthZ(6),
		Parent = world,
	}, ROUND)
	UIUtil.Gradient(fog, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new({
		nkp(0, 1),
		nkp(0.4, 0.3),
		nkp(1, 1),
	})

	-- Lampadaires (2 par côté, recyclés en boucle) + halo au sol la nuit
	local poles = {}
	for _, s in ipairs({ -1, 1 }) do
		for i = 1, POLE_PER_SIDE do
			local metal = rgb(70, 74, 96)
			local pool = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = LAMP_LIGHT,
				BackgroundTransparency = 1,
				Parent = world,
			}, ROUND)
			local pole = tint(
				frame({
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundColor3 = metal,
					Parent = world,
				}),
				metal
			)
			local arm = tint(
				frame({
					AnchorPoint = Vector2.new(s < 0 and 0 or 1, 0.5),
					BackgroundColor3 = metal,
					Parent = world,
				}),
				metal
			)
			-- tête de lampe (verre gris le jour, lumineux la nuit)
			local glow = frame({
				AnchorPoint = Vector2.new(0.5, 0.2),
				Position = UDim2.fromScale(s < 0 and 0.9 or 0.1, 0.5),
				Size = UDim2.fromScale(0.42, 2.6),
				BackgroundColor3 = LAMP_LIGHT,
				Parent = arm,
			}, UDim.new(0.5, 0))
			table.insert(poles, {
				Pole = pole,
				Arm = arm,
				Glow = glow,
				Pool = pool,
				Sign = s,
				Offset = (i - 1) * POLE_GAP + (s > 0 and POLE_GAP / 2 or 0),
				Alpha = -1,
				Depth = -1,
			})
		end
	end
	local POLE_CYCLE = POLE_PER_SIDE * POLE_GAP

	------------------------------------------------------------------
	-- Faces en perspective (flanc et toit des trains) : un trapèze =
	-- un rectangle + 2 triangles (demi-plans dans des cadres qui découpent)
	------------------------------------------------------------------
	local function newQuad(color: Color3)
		local function piece(parent: Instance): Frame
			return tint(
				frame({
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = color,
					Parent = parent,
				}),
				color
			)
		end
		local rect = tint(frame({ BackgroundColor3 = color, Visible = false, Parent = world }), color)
		local clipA = frame({ BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, Parent = world })
		local clipB = frame({ BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, Parent = world })
		return { Rect = rect, ClipA = clipA, HalfA = piece(clipA), ClipB = clipB, HalfB = piece(clipB) }
	end

	local function quadColor(q, color: Color3)
		tint(q.Rect, color)
		tint(q.HalfA, color)
		tint(q.HalfB, color)
	end

	-- Couleur lumineuse (vitres allumées la nuit) : pas assombrie
	local function quadGlow(q, color: Color3)
		glowColor(q.Rect, color)
		glowColor(q.HalfA, color)
		glowColor(q.HalfB, color)
	end

	local function hideQuad(q)
		show(q.Rect, false)
		show(q.ClipA, false)
		show(q.ClipB, false)
	end

	local function placeClip(clip: Frame, x: number, y: number, w: number, h: number, zIndex: number)
		show(clip, true)
		clip.Position = UDim2.fromOffset(x, y)
		clip.Size = UDim2.fromOffset(w, h)
		if clip.ZIndex ~= zIndex then
			clip.ZIndex = zIndex
		end
	end

	-- Trapèze à bords verticaux : x = xa (haut ta, bas ba) et x = xb (tb, bb)
	local function setVQuad(q, xa: number, ta: number, ba: number, xb: number, tb: number, bb: number, zIndex: number)
		if xa > xb then
			xa, xb, ta, tb, ba, bb = xb, xa, tb, ta, bb, ba
		end
		local w = xb - xa
		if w < 0.6 then
			hideQuad(q)
			return
		end
		local tMin, tMax = math.min(ta, tb), math.max(ta, tb)
		local bMin, bMax = math.min(ba, bb), math.max(ba, bb)
		if bMin > tMax then
			show(q.Rect, true)
			q.Rect.Position = UDim2.fromOffset(xa, tMax - 0.5)
			q.Rect.Size = UDim2.fromOffset(w, bMin - tMax + 1)
			q.Rect.ZIndex = zIndex
		else
			show(q.Rect, false)
		end
		if tMax - tMin > 0.4 then
			placeClip(q.ClipA, xa, tMin, w, tMax - tMin + 0.5, zIndex)
			setHalfPlane(q.HalfA, Vector2.new(xa, tMin), Vector2.new(xa, ta), Vector2.new(xb, tb), Vector2.new(xa + w / 2, tMax + 1000))
		else
			show(q.ClipA, false)
		end
		if bMax - bMin > 0.4 then
			placeClip(q.ClipB, xa, bMin - 0.5, w, bMax - bMin + 0.5, zIndex)
			setHalfPlane(q.HalfB, Vector2.new(xa, bMin - 0.5), Vector2.new(xa, ba), Vector2.new(xb, bb), Vector2.new(xa + w / 2, bMin - 1000))
		else
			show(q.ClipB, false)
		end
	end

	-- Trapèze à bords horizontaux : y = ya (gauche la, droite ra) et y = yb (lb, rb)
	local function setHQuad(q, ya: number, la: number, ra: number, yb: number, lb: number, rb: number, zIndex: number)
		if ya > yb then
			ya, yb, la, lb, ra, rb = yb, ya, lb, la, rb, ra
		end
		local h = yb - ya
		if h < 0.6 then
			hideQuad(q)
			return
		end
		local lMin, lMax = math.min(la, lb), math.max(la, lb)
		local rMin, rMax = math.min(ra, rb), math.max(ra, rb)
		if rMin > lMax then
			show(q.Rect, true)
			q.Rect.Position = UDim2.fromOffset(lMax - 0.5, ya)
			q.Rect.Size = UDim2.fromOffset(rMin - lMax + 1, h)
			q.Rect.ZIndex = zIndex
		else
			show(q.Rect, false)
		end
		if lMax - lMin > 0.4 then
			placeClip(q.ClipA, lMin, ya, lMax - lMin + 0.5, h, zIndex)
			setHalfPlane(q.HalfA, Vector2.new(lMin, ya), Vector2.new(la, ya), Vector2.new(lb, yb), Vector2.new(lMax + 1000, ya + h / 2))
		else
			show(q.ClipA, false)
		end
		if rMax - rMin > 0.4 then
			placeClip(q.ClipB, rMin - 0.5, ya, rMax - rMin + 0.5, h, zIndex)
			setHalfPlane(q.HalfB, Vector2.new(rMin - 0.5, ya), Vector2.new(ra, ya), Vector2.new(rb, yb), Vector2.new(rMin - 1000, ya + h / 2))
		else
			show(q.ClipB, false)
		end
	end

	------------------------------------------------------------------
	-- Trains (face avant détaillée, flanc et toit en perspective)
	------------------------------------------------------------------
	local trains = {}
	for _ = 1, TRAIN_POOL do
		local body = frame({
			Name = "Train",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = WHITE,
			Visible = false,
			Parent = world,
		}, UDim.new(0.12, 0))
		UIUtil.Gradient(body, ColorSequence.new({
			kp(0, WHITE),
			kp(0.5, rgb(234, 234, 240)),
			kp(1, rgb(176, 176, 192)),
		}), 90)
		local function part(props: { [string]: any }, radius: UDim?): Frame
			props.Parent = props.Parent or body
			return frame(props, radius)
		end
		-- toit arrondi plus sombre
		local cap = part({
			Size = UDim2.fromScale(1, 0.1),
			BackgroundColor3 = WHITE,
		}, UDim.new(0.5, 0))
		-- girouette (écran lumineux)
		local sign = part({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.115),
			Size = UDim2.fromScale(0.56, 0.075),
			BackgroundColor3 = rgb(24, 22, 30),
		})
		local signLed = part({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.5),
			BackgroundColor3 = rgb(255, 176, 40),
			Parent = sign,
		})
		UIUtil.Gradient(signLed, stripes(WHITE, rgb(120, 70, 20), 9), 0)
		local windshield = part({
			Position = UDim2.fromScale(0.08, 0.215),
			Size = UDim2.fromScale(0.84, 0.29),
			BackgroundColor3 = WHITE,
		}, UDim.new(0.18, 0))
		local glass = UIUtil.Gradient(windshield, ColorSequence.new(rgb(150, 212, 255), rgb(30, 44, 86)), 70)
		part({
			Position = UDim2.fromScale(0.16, -0.15),
			Size = UDim2.fromScale(0.09, 1.3),
			Rotation = 28,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.6,
			Parent = windshield,
		})
		local pillar = part({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.05, 1),
			BackgroundColor3 = WHITE,
			Parent = windshield,
		})
		-- bandes de livrée
		local stripe = part({
			Position = UDim2.fromScale(0, 0.55),
			Size = UDim2.fromScale(1, 0.055),
			BackgroundColor3 = WHITE,
		})
		-- halo des phares (la nuit, ou quand le train fonce vers nous)
		local beam = part({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.73),
			Size = UDim2.fromScale(1.3, 0.34),
			BackgroundColor3 = rgb(255, 250, 214),
			BackgroundTransparency = 1,
		}, ROUND)
		local function headlight(x: number): Frame
			return part({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.73),
				Size = UDim2.fromScale(0.16, 0.1),
				BackgroundColor3 = rgb(255, 248, 200),
			}, ROUND)
		end
		local headL = headlight(0.19)
		local headR = headlight(0.81)
		-- pare-chocs
		part({
			Position = UDim2.fromScale(0.03, 0.84),
			Size = UDim2.fromScale(0.94, 0.1),
			BackgroundColor3 = rgb(62, 64, 78),
		}, UDim.new(0.35, 0))
		-- ombre de contact au pied du train
		part({
			Name = "ContactShadow",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.985),
			Size = UDim2.fromScale(1.12, 0.07),
			BackgroundColor3 = rgb(10, 8, 24),
			BackgroundTransparency = 0.5,
		}, ROUND)
		local train = {
			Active = false,
			Body = body,
			Cap = cap,
			Glass = glass,
			Pillar = pillar,
			HeadL = headL,
			HeadR = headR,
			Beam = beam,
			Stripe = stripe,
			Side = newQuad(WHITE),
			Roof = newQuad(WHITE),
			Windows = newQuad(WHITE), -- bande vitrée du flanc (allumée la nuit)
			Lane = 1,
			Z = Z_FAR,
			Extra = 0,
			Passed = false,
		}
		tint(body, WHITE)
		table.insert(trains, train)
	end

	------------------------------------------------------------------
	-- Pont routier qui passe au-dessus de la voie de temps en temps :
	-- face avant (béton, bande colorée, garde-corps, panneau), dessous
	-- sombre, deux piles posées sur les murs et une ombre sur les rails.
	------------------------------------------------------------------
	local bridge = { Active = false, Z = Z_FAR }
	do
		local concrete = rgb(214, 208, 204)
		bridge.Face = tint(frame({
			Name = "Bridge",
			BackgroundColor3 = concrete,
			Visible = false,
			Parent = world,
		}), concrete)
		UIUtil.Gradient(bridge.Face, ColorSequence.new({
			kp(0, WHITE),
			kp(0.6, rgb(236, 234, 240)),
			kp(1, rgb(170, 166, 178)),
		}), 90)
		bridge.Stripe = frame({
			Position = UDim2.fromScale(0, 0.3),
			Size = UDim2.fromScale(1, 0.2),
			BackgroundColor3 = rgb(255, 120, 60),
			ZIndex = 2,
			Parent = bridge.Face,
		})
		-- garde-corps (bande sombre au-dessus de la face)
		bridge.Rail = tint(frame({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 0.02),
			Size = UDim2.fromScale(1, 0.26),
			BackgroundColor3 = rgb(84, 90, 116),
			ZIndex = 1,
			Parent = bridge.Face,
		}), rgb(84, 90, 116))
		UIUtil.Gradient(bridge.Rail, ColorSequence.new(rgb(200, 206, 230), WHITE), 90)
		bridge.Sign = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			Size = UDim2.fromScale(0.16, 0.62),
			BackgroundColor3 = rgb(20, 130, 80),
			ZIndex = 3,
			Parent = bridge.Face,
		}, UDim.new(0.12, 0))
		UIUtil.Stroke(bridge.Sign, WHITE, math.max(1, 1.2 * U), 0.1)
		bridge.SignLabel = UIUtil.Label({
			Text = "🧠 DOPA CITY",
			Font = Theme.Fonts.Number,
			TextColor3 = WHITE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.88, 0.72),
			MaxTextSize = 40,
			ZIndex = 4,
			Parent = bridge.Sign,
		})
		local labelConstraint = bridge.SignLabel:FindFirstChildOfClass("UITextSizeConstraint")
		if labelConstraint then
			labelConstraint.MinTextSize = 1 -- au loin, le panneau devient minuscule
		end
		bridge.Under = tint(frame({
			Name = "BridgeUnder",
			BackgroundColor3 = rgb(92, 88, 104),
			Visible = false,
			Parent = world,
		}), rgb(92, 88, 104))
		UIUtil.Gradient(bridge.Under, ColorSequence.new(rgb(150, 150, 160), WHITE), 90)
		bridge.Pillars = {}
		for _, sideSign in ipairs({ -1, 1 }) do
			local pillar = tint(frame({
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = concrete,
				Visible = false,
				Parent = world,
			}), concrete)
			UIUtil.Gradient(pillar, ColorSequence.new(sideSign < 0 and rgb(230, 230, 236) or rgb(180, 176, 190), sideSign < 0 and rgb(180, 176, 190) or rgb(230, 230, 236)), 0)
			table.insert(bridge.Pillars, { Frame = pillar, Sign = sideSign })
		end
		bridge.Shadow = frame({
			Name = "BridgeShadow",
			BackgroundColor3 = rgb(20, 16, 40),
			BackgroundTransparency = 0.72,
			Visible = false,
			ZIndex = 2,
			Parent = world,
		})
	end

	------------------------------------------------------------------
	-- Obstacles : barrière basse (saut), haute (glissade), cônes (saut)
	------------------------------------------------------------------
	local obstacles = {}
	local LEG_COLOR = rgb(84, 88, 108)
	local CONE = rgb(255, 112, 36)
	local function newBarrier()
		local board = tint(
			frame({
				Name = "Barrier",
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = WHITE,
				Visible = false,
				Parent = world,
			}, UDim.new(0.2, 0)),
			WHITE
		)
		local legs = {}
		for _, legX in ipairs({ 0.12, 0.88 }) do
			table.insert(
				legs,
				tint(
					frame({
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(legX, 1),
						Size = UDim2.fromScale(0.065, 1),
						BackgroundColor3 = LEG_COLOR,
						ZIndex = 0,
						Parent = board,
					}),
					LEG_COLOR
				)
			)
		end
		local shadow = frame({
			Name = "ContactShadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 2),
			Size = UDim2.fromScale(1.02, 0.22),
			BackgroundColor3 = rgb(10, 8, 24),
			BackgroundTransparency = 0.6,
			ZIndex = 0,
			Parent = board,
		}, ROUND)
		return {
			Type = "Board",
			Visual = board,
			Board = board,
			Shadow = shadow,
			Gradient = UIUtil.Gradient(board, ColorSequence.new(WHITE), 25),
			Legs = legs,
			-- gyrophare (barrières hautes)
			Light = frame({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.04),
				Size = UDim2.fromScale(0.12, 0.42),
				BackgroundColor3 = rgb(255, 70, 60),
				Parent = board,
			}, ROUND),
		}
	end

	-- Deux cônes côte à côte
	local function newCones()
		local cones = frame({
			Name = "Cones",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = world,
		})
		frame({
			Name = "ContactShadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.98),
			Size = UDim2.fromScale(1.02, 0.16),
			BackgroundColor3 = rgb(10, 8, 24),
			BackgroundTransparency = 0.55,
			ZIndex = 0,
			Parent = cones,
		}, ROUND)
		for _, coneX in ipairs({ 0.24, 0.76 }) do
			-- (largeurs relatives au cadre des deux cônes : un cône = 42 %)
			local function conePart(y: number, w: number, h: number, color: Color3, radius: UDim?): Frame
				return tint(
					frame({
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(coneX, y),
						Size = UDim2.fromScale(w * 0.42, h),
						BackgroundColor3 = color,
						Parent = cones,
					}, radius),
					color
				)
			end
			conePart(0.86, 1, 0.14, rgb(206, 80, 30)) -- socle
			conePart(0.48, 0.66, 0.4, CONE, UDim.new(0.2, 0))
			conePart(0.34, 0.5, 0.16, rgb(248, 248, 252)) -- bande réfléchissante
			conePart(0, 0.34, 0.36, CONE, UDim.new(0.45, 0))
		end
		return { Type = "Cone", Visual = cones, Cones = cones }
	end

	for index = 1, BARRIER_POOL + CONE_POOL do
		local ob: any = (index <= BARRIER_POOL) and newBarrier() or newCones()
		ob.Active = false
		ob.Kind = "Low"
		ob.Bottom, ob.Top = 20, 38
		ob.Lane = 1
		ob.Z = Z_FAR
		ob.Handled, ob.Fatal, ob.Passed = false, false, false
		ob.Knock, ob.Phase = 0, 0
		table.insert(obstacles, ob)
	end

	------------------------------------------------------------------
	-- Pièces (tournent sur elles-mêmes, anneau, reflet, éclat)
	------------------------------------------------------------------
	local coinSequence = ColorSequence.new({
		kp(0, rgb(255, 196, 30)),
		kp(0.38, rgb(255, 216, 60)),
		kp(0.5, rgb(255, 255, 222)),
		kp(0.62, rgb(255, 216, 60)),
		kp(1, rgb(226, 142, 16)),
	})
	local coinsPool = {}
	for _ = 1, COIN_POOL do
		local coin = frame({
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			Visible = false,
			Parent = world,
		}, ROUND)
		local gradient = UIUtil.Gradient(coin, coinSequence, 45)
		-- anneau en creux (plus sombre), qui tourne avec la pièce
		frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			BackgroundColor3 = rgb(232, 158, 22),
			Parent = coin,
		}, ROUND)
		table.insert(coinsPool, {
			Active = false,
			Frame = coin,
			Gradient = gradient,
			Lane = 1,
			X = 0,
			H = COIN_H,
			Z = Z_FAR,
			Phase = 0,
			Air = false,
			Pulled = false,
		})
	end

	------------------------------------------------------------------
	-- Bonus à ramasser (aimant, x2, jetpack) : bulle brillante + halo
	------------------------------------------------------------------
	local POWER_STYLE = {
		Magnet = { Icon = "🧲", Color = rgb(255, 110, 170), Text = "" },
		Double = { Icon = "", Color = rgb(255, 196, 40), Text = "x2" },
		Jetpack = { Icon = "🚀", Color = rgb(90, 200, 255), Text = "" },
	}
	local pickup = { Active = false, Kind = "Magnet", Lane = 2, Z = Z_FAR }
	pickup.Root = frame({
		Name = "PowerUp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = world,
	})
	pickup.Halo = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.7, 1.7),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
		Parent = pickup.Root,
	}, ROUND)
	pickup.Bubble = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = pickup.Root,
	}, ROUND)
	UIUtil.Gradient(pickup.Bubble, ColorSequence.new(WHITE, rgb(210, 214, 230)), 90)
	pickup.Stroke = UIUtil.Stroke(pickup.Bubble, WHITE, 2, 0)
	pickup.Icon = UIUtil.Label({
		Text = "🧲",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = 3,
		MaxTextSize = 60,
		Parent = pickup.Bubble,
	})
	pickup.Text = UIUtil.Label({
		Text = "",
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.78, 0.62),
		ZIndex = 3,
		MaxTextSize = 60,
		Parent = pickup.Bubble,
	})
	pickup.Text.TextStrokeColor3 = rgb(150, 80, 0)
	pickup.Text.TextStrokeTransparency = 0
	for _, label in ipairs({ pickup.Icon, pickup.Text }) do
		local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			constraint.MinTextSize = 1 -- au loin, la bulle est toute petite
		end
	end

	------------------------------------------------------------------
	-- Le coureur (vu de dos) : sweat à capuche, casquette à l'envers, sac à
	-- dos qui rebondit (porte-clés qui se balance) et baskets qui changent
	-- avec l'amélioration "RunnerShoes". Contours sombres façon dessin
	-- animé. Quand il se retourne, on voit son visage (yeux qui clignent,
	-- expressions) ; une bulle d'émoji ponctue les moments forts.
	-- Roblox tourne un cadre autour de son CENTRE : bras et jambes sont
	-- dans un "pivot" transparent centré sur l'épaule / la hanche et deux
	-- fois plus long que le membre (qui en occupe la moitié basse).
	------------------------------------------------------------------
	local CW = CHAR_W * U / CHAR_Z
	local CH = CHAR_H * U / CHAR_Z
	local charDepth = depthZ(CHAR_Z)
	local hero: any = {}

	local function outline(inst: GuiObject, transparency: number?): UIStroke
		return UIUtil.Stroke(inst, OUTLINE, 1, transparency or 0.3)
	end

	hero.Shadow = frame({
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.65,
		ZIndex = charDepth - 1,
		Parent = world,
	}, ROUND)
	-- Halo coloré au sol sous les baskets lumineuses (niveau 5 et plus)
	hero.UnderGlow = frame({
		Name = "ShoeGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = charDepth - 1,
		Parent = world,
	}, ROUND)
	UIUtil.Gradient(hero.UnderGlow, ColorSequence.new(WHITE), 0).Transparency = NumberSequence.new({
		nkp(0, 0.85),
		nkp(0.5, 0),
		nkp(1, 0.85),
	})

	hero.Aura = frame({
		Name = "MagnetAura",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = rgb(255, 90, 200),
		BackgroundTransparency = 0.9,
		Visible = false,
		ZIndex = charDepth + 2,
		Parent = world,
	}, ROUND)
	hero.AuraStroke = UIUtil.Stroke(hero.Aura, rgb(255, 90, 200), 2, 0.2)

	-- Anneau qui s'élargit autour des pieds (nouvelles baskets)
	hero.ShoeRing = frame({
		Name = "ShoeRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = charDepth + 2,
		Parent = world,
	}, ROUND)
	hero.ShoeRingStroke = UIUtil.Stroke(hero.ShoeRing, WHITE, math.max(1.5, 2.5 * U), 0)

	hero.Root = frame({
		Name = "Hero",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(CW, CH),
		BackgroundTransparency = 1,
		ZIndex = charDepth,
		Parent = world,
	})

	local function limb(parent: Instance, props: { [string]: any }, color: Color3, radius: UDim?): Frame
		props.Parent = parent
		props.BackgroundColor3 = color
		return tint(frame(props, radius or UDim.new(0.4, 0)), color)
	end

	-- Articulation : cadre transparent centré en (x, y), tourné à chaque image
	local function pivot(x: number, y: number, w: number, zIndex: number): Frame
		return frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, 0.6),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Parent = hero.Root,
		})
	end

	-- Jambes (jean modelé, ourlet plus clair)
	hero.Legs = {}
	for index, x in ipairs({ 0.37, 0.63 }) do
		local hip = pivot(x, LEG_TOP, 0.2, 1)
		local leg = limb(hip, {
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(1, 0.5),
			ZIndex = 1,
		}, JEANS, UDim.new(0.35, 0))
		UIUtil.Gradient(leg, ColorSequence.new({
			kp(0, rgb(192, 198, 222)),
			kp(0.45, WHITE),
			kp(1, rgb(170, 178, 208)),
		}), 0)
		outline(leg)
		limb(leg, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1.08, 0.2),
			ZIndex = 2,
		}, JEANS_HEM, UDim.new(0.3, 0))
		table.insert(hero.Legs, { Pivot = hip, Frame = leg, X = x, Side = index == 1 and -1 or 1 })
	end

	-- Baskets : enfants du coureur, placées au bout des jambes à chaque image
	-- (couleurs et accessoires selon le niveau : voir applyShoes)
	hero.Shoes = {}
	for _, leg in ipairs(hero.Legs) do
		local side = leg.Side
		local root = frame({
			Name = "Shoe",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(SHOE_W, SHOE_H),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = hero.Root,
		})
		local shoe: any = { Root = root, Side = side }
		-- halo néon derrière la chaussure
		shoe.Glow = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.6),
			Size = UDim2.fromScale(1.9, 1.9),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.6,
			Visible = false,
			ZIndex = 1,
			Parent = root,
		}, ROUND)
		-- flammes des propulseurs (sous la semelle)
		shoe.Flame = frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.8),
			Size = UDim2.fromScale(0.7, 1.4),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 1,
			Parent = root,
		}, UDim.new(0.5, 0))
		shoe.FlameGradient = UIUtil.Gradient(shoe.Flame, ColorSequence.new({
			kp(0, rgb(255, 255, 230)),
			kp(0.35, rgb(255, 204, 60)),
			kp(1, rgb(255, 70, 20)),
		}), 90)
		shoe.FlameGradient.Transparency = NumberSequence.new({
			nkp(0, 0),
			nkp(0.55, 0.15),
			nkp(1, 1),
		})
		shoe.Core = frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.84),
			Size = UDim2.fromScale(0.32, 0.7),
			BackgroundColor3 = rgb(214, 246, 255),
			Visible = false,
			ZIndex = 2,
			Parent = root,
		}, UDim.new(0.5, 0))
		UIUtil.Gradient(shoe.Core, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new(0, 1)
		-- aile au talon, côté extérieur (3 plumes) : pivot centré sur l'attache
		shoe.Wing = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side < 0 and 0.12 or 0.88, 0.42),
			Size = UDim2.fromScale(1.6, 1.3),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 2,
			Parent = root,
		})
		shoe.Feathers = {}
		for f = 1, 3 do
			local feather = frame({
				AnchorPoint = Vector2.new(side < 0 and 1 or 0, 0.5),
				Position = UDim2.fromScale(0.5, 0.24 + (f - 1) * 0.2),
				Size = UDim2.fromScale((1.02 - (f - 1) * 0.24) * 0.5, 0.25),
				Rotation = side * (-26 + (f - 1) * 20),
				BackgroundColor3 = WHITE,
				ZIndex = 4 - f,
				Parent = shoe.Wing,
			}, ROUND)
			outline(feather, 0.4)
			table.insert(shoe.Feathers, feather)
		end
		-- tige (dessus clair, bas plus sombre)
		shoe.Upper = frame({
			Size = UDim2.fromScale(1, 0.82),
			BackgroundColor3 = WHITE,
			ZIndex = 4,
			Parent = root,
		}, UDim.new(0.45, 0))
		UIUtil.Gradient(shoe.Upper, ColorSequence.new(WHITE, rgb(190, 192, 208)), 90)
		outline(shoe.Upper, 0.15)
		-- bande latérale
		shoe.Stripe = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.96, 0.12),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 5,
			Parent = root,
		})
		-- lacets (vus d'en haut, ils dépassent derrière le talon)
		shoe.Laces = frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.05),
			Size = UDim2.fromScale(0.56, 0.2),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 5,
			Parent = root,
		}, UDim.new(0.3, 0))
		UIUtil.Gradient(shoe.Laces, stripes(WHITE, rgb(150, 150, 166), 4), 0)
		-- contrefort (talon)
		shoe.Heel = frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, -0.1),
			Size = UDim2.fromScale(0.24, 0.36),
			BackgroundColor3 = WHITE,
			ZIndex = 6,
			Parent = root,
		}, UDim.new(0.35, 0))
		-- semelle (grandit quand le pied part en arrière : on la voit de face)
		shoe.Sole = frame({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1.06, 0.28),
			BackgroundColor3 = WHITE,
			ZIndex = 7,
			Parent = root,
		}, UDim.new(0.4, 0))
		UIUtil.Gradient(shoe.Sole, stripes(WHITE, rgb(206, 206, 220), 4), 90)
		outline(shoe.Sole, 0.15)
		-- tuyère des bottes à réaction
		shoe.Nozzle = frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.86),
			Size = UDim2.fromScale(0.46, 0.24),
			BackgroundColor3 = rgb(70, 74, 92),
			Visible = false,
			ZIndex = 8,
			Parent = root,
		}, UDim.new(0.3, 0))
		table.insert(hero.Shoes, shoe)
	end

	-- Bras (pivot à l'épaule) : manche, bord-côte, poing
	hero.Arms = {}
	for index, x in ipairs({ 0.15, 0.85 }) do
		local shoulder = pivot(x, 0.325, 0.17, 2)
		local sleeve = limb(shoulder, {
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(1, 0.5),
			ZIndex = 1,
		}, HOODIE_DARK)
		outline(sleeve)
		limb(sleeve, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.97),
			Size = UDim2.fromScale(1.04, 0.22),
			ZIndex = 2,
		}, HOODIE_RIB, UDim.new(0.3, 0))
		local hand = limb(sleeve, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1.03),
			Size = UDim2.new(1.12, 0, 0, math.max(2, CW * 0.18)),
			ZIndex = 3,
		}, SKIN, ROUND)
		outline(hand, 0.4)
		table.insert(hero.Arms, { Pivot = shoulder, Sleeve = sleeve, X = x, Side = index == 1 and -1 or 1 })
	end

	-- Buste : sweat modelé, bord-côte, bretelles du sac, capuche
	hero.Torso = limb(hero.Root, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.265),
		Size = UDim2.fromScale(0.66, 0.41),
		ZIndex = 3,
	}, HOODIE, UDim.new(0.32, 0))
	UIUtil.Gradient(hero.Torso, ColorSequence.new({
		kp(0, rgb(196, 196, 196)),
		kp(0.42, WHITE),
		kp(1, rgb(182, 182, 182)),
	}), 0)
	outline(hero.Torso)
	limb(hero.Torso, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.98, 0.15),
		ZIndex = 2,
	}, HOODIE_RIB, UDim.new(0.4, 0))
	for _, strapX in ipairs({ 0.25, 0.75 }) do
		limb(hero.Torso, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(strapX, 0.03),
			Size = UDim2.fromScale(0.13, 0.5),
			ZIndex = 2,
		}, STRAP, UDim.new(0.4, 0))
	end
	hero.Hood = limb(hero.Torso, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, -0.06),
		Size = UDim2.fromScale(0.72, 0.32),
		ZIndex = 3,
	}, HOODIE_DARK, ROUND)
	outline(hero.Hood, 0.45)
	limb(hero.Hood, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.62, 0.4),
		ZIndex = 2,
	}, rgb(150, 42, 32), ROUND)

	-- Tête : cheveux, oreilles, visage (quand il se retourne), casquette
	hero.Head = limb(hero.Root, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.47, 0.295),
		ZIndex = 5,
	}, HAIR, ROUND)
	outline(hero.Head)
	hero.Ears = {}
	for _, earX in ipairs({ 0.03, 0.97 }) do
		local ear = limb(hero.Head, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(earX, 0.64),
			Size = UDim2.fromScale(0.2, 0.28),
			ZIndex = 1,
		}, SKIN, ROUND)
		outline(ear, 0.5)
		table.insert(hero.Ears, ear)
	end
	hero.Face = limb(hero.Head, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromScale(0.6, 0.62),
		Visible = false,
		ZIndex = 2,
	}, SKIN, ROUND)
	hero.Blush = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.3, 0.16),
		BackgroundColor3 = rgb(255, 128, 140),
		BackgroundTransparency = 0.35,
		ZIndex = 1,
		Parent = hero.Face,
	}, ROUND)
	hero.Eye = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.6, 0.36),
		Size = UDim2.fromScale(0.17, 0.26),
		BackgroundColor3 = EYE,
		ZIndex = 2,
		Parent = hero.Face,
	}, ROUND)
	-- (yeux en croix : sonné après une chute)
	hero.EyeX = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.6, 0.36),
		Size = UDim2.fromScale(0.3, 0.08),
		Rotation = -45,
		BackgroundColor3 = EYE,
		Visible = false,
		ZIndex = 2,
		Parent = hero.Face,
	})
	hero.Brow = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.6, 0.12),
		Size = UDim2.fromScale(0.3, 0.08),
		BackgroundColor3 = HAIR,
		ZIndex = 2,
		Parent = hero.Face,
	}, UDim.new(0.5, 0))
	hero.Mouth = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.62, 0.78),
		Size = UDim2.fromScale(0.3, 0.1),
		BackgroundColor3 = MOUTH,
		ZIndex = 2,
		Parent = hero.Face,
	}, ROUND)
	hero.Cap = limb(hero.Head, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, -0.1),
		Size = UDim2.fromScale(1.1, 0.64),
		ZIndex = 3,
	}, CAP, UDim.new(0.5, 0))
	UIUtil.Gradient(hero.Cap, ColorSequence.new(WHITE, rgb(190, 200, 222)), 90)
	outline(hero.Cap, 0.3)
	-- logo sur le devant de la casquette (tournée vers nous) + bouton
	frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.24, 0.3),
		BackgroundColor3 = rgb(255, 226, 80),
		ZIndex = 2,
		Parent = hero.Cap,
	}, ROUND)
	limb(hero.Cap, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.14, 0.14),
		ZIndex = 2,
	}, CAP_DARK, ROUND)
	hero.Visor = limb(hero.Head, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.94, 0.2),
		ZIndex = 4,
	}, CAP_DARK, UDim.new(0.5, 0))
	outline(hero.Visor, 0.4)

	-- Sac à dos (rebondit avec un peu de retard) : rabat, poche, porte-clés
	hero.Pack = limb(hero.Root, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.355),
		Size = UDim2.fromScale(0.5, 0.3),
		ZIndex = 6,
	}, PACK, UDim.new(0.32, 0))
	UIUtil.Gradient(hero.Pack, ColorSequence.new(WHITE, rgb(222, 212, 196)), 90)
	outline(hero.Pack)
	hero.Flap = limb(hero.Pack, {
		Size = UDim2.fromScale(1, 0.32),
		ZIndex = 2,
	}, PACK_DARK, UDim.new(0.45, 0))
	hero.Pocket = limb(hero.Pack, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.72, 0.36),
		ZIndex = 2,
	}, PACK_DARK, UDim.new(0.3, 0))
	hero.Charm = frame({
		Name = "Charm",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.7, 0.6),
		Size = UDim2.fromScale(0.2, 0.7),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = hero.Pack,
	})
	frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, math.max(1, 0.8 * U), 0.34, 0),
		BackgroundColor3 = rgb(70, 60, 84),
		ZIndex = 1,
		Parent = hero.Charm,
	})
	local charmBall = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.88),
		Size = UDim2.new(0, math.max(2, 3.2 * U), 0, math.max(2, 3.2 * U)),
		Rotation = 45,
		BackgroundColor3 = rgb(255, 70, 170),
		ZIndex = 2,
		Parent = hero.Charm,
	}, UDim.new(0.25, 0))
	outline(charmBall, 0.4)
	-- Flammes du jetpack (cachées hors bonus)
	hero.Flames = {}
	for _, x in ipairs({ 0.27, 0.73 }) do
		local flame = frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0.95),
			Size = UDim2.fromScale(0.3, 0.7),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 1,
			Parent = hero.Pack,
		}, UDim.new(0.5, 0))
		local gradient = UIUtil.Gradient(flame, ColorSequence.new(rgb(255, 250, 200), rgb(255, 96, 20)), 90)
		gradient.Transparency = NumberSequence.new(0, 0.85)
		table.insert(hero.Flames, flame)
	end

	------------------------------------------------------------------
	-- Effets (poussière, lignes de vitesse, étincelles, textes)
	------------------------------------------------------------------
	local fxLayer = layer("FX", 8)

	local dusts = {}
	for _ = 1, DUST_POOL do
		table.insert(dusts, {
			Frame = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = rgb(236, 222, 200),
				Visible = false,
				ZIndex = charDepth + 1,
				Parent = world,
			}, ROUND),
			Life = 0,
			MaxLife = 1,
			X = 0,
			Y = 0,
			VX = 0,
			VY = 0,
			Size = 4,
		})
	end
	-- (color : couleur lumineuse, jamais assombrie ; sinon poussière du sol)
	local function spawnDust(x: number, y: number, vx: number, vy: number, size: number, life: number, color: Color3?)
		if not effectsOn() then
			return
		end
		for _, dust in ipairs(dusts) do
			if dust.Life <= 0 then
				dust.Life, dust.MaxLife = life, life
				dust.X, dust.Y, dust.VX, dust.VY, dust.Size = x, y, vx, vy, size
				dust.Frame.BackgroundColor3 = color or mulColor(rgb(236, 222, 200), ambient)
				dust.Frame.Visible = true
				return
			end
		end
	end

	local speedLines = {}
	for _ = 1, SPEEDLINE_POOL do
		table.insert(speedLines, {
			Frame = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 1,
				Visible = false,
				Parent = fxLayer,
			}),
			Angle = 0,
			R = 0,
			Speed = 0,
		})
	end
	local function resetSpeedLine(line)
		local roll = random:NextNumber()
		local degrees
		if roll < 0.3 then
			degrees = random:NextNumber(200, 252) -- ciel (pas derrière le coureur)
		elseif roll < 0.6 then
			degrees = random:NextNumber(288, 340)
		elseif roll < 0.8 then
			degrees = random:NextNumber(-25, 12) -- côté droit
		else
			degrees = random:NextNumber(168, 205) -- côté gauche
		end
		line.Angle = math.rad(degrees)
		line.R = random:NextNumber(14, 50) * U
		line.Speed = random:NextNumber(220, 340) * U
	end
	for _, line in ipairs(speedLines) do
		resetSpeedLine(line)
		line.R = random:NextNumber(14, 200) * U
	end

	local sparkles = {}
	for _ = 1, SPARKLE_POOL do
		table.insert(sparkles, {
			Frame = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = rgb(255, 244, 150),
				Visible = false,
				Parent = fxLayer,
			}),
			Life = 0,
			X = 0,
			Y = 0,
			VX = 0,
			VY = 0,
		})
	end

	local pops = {}
	for _ = 1, POP_POOL do
		local label = UIUtil.Label({
			Text = "+1",
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = GOLD,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			MaxTextSize = 40,
			ZIndex = 2,
			Parent = fxLayer,
		})
		local stroke = UIUtil.Stroke(label, INK, 1.5)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		table.insert(pops, { Label = label, Stroke = stroke, Life = 0, MaxLife = 0.7, X = 0, Y = 0, W = 40, H = 16, Rise = 26 })
	end

	local function spawnSparkles(x: number, y: number, count: number)
		if not effectsOn() then
			return
		end
		for _ = 1, count do
			local chosen: any = nil
			for _, sparkle in ipairs(sparkles) do
				if sparkle.Life <= 0 then
					chosen = sparkle
					break
				end
			end
			if not chosen then
				return
			end
			local angle = random:NextNumber(0, math.pi * 2)
			local velocity = random:NextNumber(40, 90) * U
			chosen.Life = 0.45
			chosen.X, chosen.Y = x, y
			chosen.VX = math.cos(angle) * velocity
			chosen.VY = math.sin(angle) * velocity - 30 * U
			chosen.Frame.BackgroundColor3 = (random:NextNumber() < 0.5) and rgb(255, 244, 150) or WHITE
			chosen.Frame.Visible = true
		end
	end

	-- Texte qui monte (réutilise le plus ancien si tout est pris)
	local function popText(text: string, x: number, y: number, color: Color3, width: number, height: number, big: boolean?)
		local chosen = pops[1]
		for _, pop in ipairs(pops) do
			if pop.Life < chosen.Life then
				chosen = pop
			end
		end
		chosen.MaxLife = big and 1.1 or 0.7
		chosen.Life = chosen.MaxLife
		chosen.Rise = big and 12 or 26
		chosen.X, chosen.Y = x, y
		chosen.W, chosen.H = width, height
		chosen.Label.Text = text
		chosen.Label.TextColor3 = color
		chosen.Label.Visible = true
	end

	------------------------------------------------------------------
	-- Effets des baskets : traînée lumineuse au sol (un ruban par pied,
	-- 4 segments en perspective qui suivent les changements de voie),
	-- étincelles / plumes / braises qui s'échappent des talons
	------------------------------------------------------------------
	local ribbons = {}
	for _ = 1, 2 do
		local ribbon: any = { Points = {}, Segments = {}, Gradients = {} }
		for k = 0, RIBBON_SEGMENTS do
			ribbon.Points[k] = { X = 0, H = 0, Scroll = 0 }
		end
		for k = 1, RIBBON_SEGMENTS do
			local segment = frame({
				Name = "Trail",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				Visible = false,
				ZIndex = charDepth - 1,
				Parent = world,
			}, UDim.new(0.3, 0))
			-- dégradé le long du segment (continu d'un segment à l'autre)
			ribbon.Segments[k] = segment
			ribbon.Gradients[k] = UIUtil.Gradient(segment, ColorSequence.new(WHITE), 0)
		end
		table.insert(ribbons, ribbon)
	end

	local shoeFx = {}
	for _ = 1, SHOE_FX_POOL do
		table.insert(shoeFx, {
			Frame = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				Visible = false,
				ZIndex = 1,
				Parent = fxLayer,
			}, UDim.new(0.3, 0)),
			Life = 0,
			MaxLife = 1,
			X = 0,
			Y = 0,
			VX = 0,
			VY = 0,
			Size = 3,
			Spin = 0,
		})
	end
	local function spawnShoeFx(x: number, y: number, color: Color3, size: number, vx: number, vy: number, life: number)
		for _, fx in ipairs(shoeFx) do
			if fx.Life <= 0 then
				fx.Life, fx.MaxLife = life, life
				fx.X, fx.Y, fx.VX, fx.VY, fx.Size = x, y, vx, vy, size
				fx.Spin = random:NextNumber(-360, 360)
				fx.Frame.BackgroundColor3 = color
				fx.Frame.Rotation = 45
				fx.Frame.Visible = true
				return
			end
		end
	end

	------------------------------------------------------------------
	-- Bulle d'émoji au-dessus du coureur (expressions) et étoiles qui
	-- tournent autour de sa tête quand il est sonné
	------------------------------------------------------------------
	hero.Emote = frame({
		Name = "Emote",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(21 * U, 19 * U),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 3,
		Parent = fxLayer,
	}, UDim.new(0.42, 0))
	UIUtil.Stroke(hero.Emote, OUTLINE, math.max(1, 1.2 * U), 0.25)
	hero.EmoteScale = Create("UIScale", { Parent = hero.Emote })
	-- petite pointe de la bulle
	frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromOffset(6 * U, 6 * U),
		Rotation = 45,
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = hero.Emote,
	})
	hero.EmoteLabel = UIUtil.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		MaxTextSize = 40,
		ZIndex = 2,
		Parent = hero.Emote,
	})
	hero.DizzyStars = {}
	for k = 1, 3 do
		local star = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(4.5 * U, 4.5 * U),
			BackgroundColor3 = rgb(255, 226, 60),
			Visible = false,
			ZIndex = 2,
			Parent = fxLayer,
		}, UDim.new(0.2, 0))
		UIUtil.Stroke(star, rgb(200, 120, 0), 1, 0.3)
		table.insert(hero.DizzyStars, { Frame = star, Phase = (k - 1) * math.pi * 2 / 3 })
	end

	-- Vignette : bas de l'image un peu plus sombre (profondeur, HUD lisible)
	local vignette = frame({
		Name = "Vignette",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.34),
		BackgroundColor3 = rgb(20, 14, 40),
		ZIndex = 5,
		Parent = screen,
	})
	UIUtil.Gradient(vignette, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new({
		nkp(0, 1),
		nkp(0.55, 0.9),
		nkp(1, 0.66),
	})

	------------------------------------------------------------------
	-- HUD (pièces, distance, record, combo, bonus en cours)
	------------------------------------------------------------------
	local hudLayer = layer("HUD", 9, screen)
	local hud: any = {}
	local hudBoost = 1 -- agrandissement des pastilles (téléphone)

	local function pill(position: UDim2, size: UDim2, anchor: Vector2?): Frame
		local p = frame({
			AnchorPoint = anchor or Vector2.zero,
			Position = position,
			Size = size,
			BackgroundColor3 = rgb(16, 18, 32),
			BackgroundTransparency = 0.35,
			ZIndex = 1,
			Parent = hudLayer,
		}, ROUND)
		UIUtil.Stroke(p, WHITE, 1, 0.6)
		return p
	end

	local function coinIcon(parent: Instance, position: UDim2, size: number): Frame
		local icon = frame({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = WHITE,
			ZIndex = 2,
			Parent = parent,
		}, ROUND)
		UIUtil.Gradient(icon, coinSequence, 45)
		frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
			BackgroundColor3 = rgb(232, 158, 22),
			ZIndex = 2,
			Parent = icon,
		}, ROUND)
		return icon
	end

	hud.CoinPill = pill(UDim2.fromOffset(6 * U, 6 * U), UDim2.fromOffset(70 * U, 21 * U))
	hud.CoinScale = Create("UIScale", { Parent = hud.CoinPill })
	coinIcon(hud.CoinPill, UDim2.new(0, 3 * U, 0.5, 0), 15 * U)
	hud.CoinLabel = UIUtil.Label({
		Text = "0",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(22 * U, 2 * U),
		Size = UDim2.new(1, -26 * U, 1, -4 * U),
		MaxTextSize = math.floor(16 * U),
		ZIndex = 2,
		Parent = hud.CoinPill,
	})
	-- badge "x2" collé à la pastille des pièces
	hud.DoubleBadge = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 0, 0, 1 * U),
		Size = UDim2.fromOffset(19 * U, 13 * U),
		BackgroundColor3 = rgb(255, 196, 40),
		Visible = false,
		ZIndex = 3,
		Parent = hud.CoinPill,
	}, ROUND)
	UIUtil.Label({
		Text = "x2",
		Font = Theme.Fonts.Number,
		TextColor3 = rgb(80, 40, 0),
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = math.floor(11 * U),
		ZIndex = 4,
		Parent = hud.DoubleBadge,
	})

	hud.DistPill = pill(UDim2.new(1, -6 * U, 0, 6 * U), UDim2.fromOffset(84 * U, 21 * U), Vector2.new(1, 0))
	hud.DistScale = Create("UIScale", { Parent = hud.DistPill })
	hud.DistStroke = hud.DistPill:FindFirstChildOfClass("UIStroke")
	hud.DistLabel = UIUtil.Label({
		Text = "0 m",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		Position = UDim2.fromOffset(6 * U, 2 * U),
		Size = UDim2.new(1, -12 * U, 1, -4 * U),
		MaxTextSize = math.floor(16 * U),
		ZIndex = 2,
		Parent = hud.DistPill,
	})
	hud.BestLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = rgb(255, 232, 150),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10 * U, 0, 28 * U),
		Size = UDim2.fromOffset(110 * U, 11 * U),
		MaxTextSize = math.floor(11 * U),
		Visible = false,
		ZIndex = 2,
		Parent = hudLayer,
	})
	hud.BestLabel.TextStrokeColor3 = INK
	hud.BestLabel.TextStrokeTransparency = 0.2

	hud.ComboPill = pill(UDim2.new(0.5, 0, 0, 6 * U), UDim2.fromOffset(78 * U, 19 * U), Vector2.new(0.5, 0))
	hud.ComboPill.Visible = false
	hud.ComboScale = Create("UIScale", { Parent = hud.ComboPill })
	hud.ComboLabel = UIUtil.Label({
		Text = "",
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = GOLD,
		Position = UDim2.fromOffset(5 * U, 2 * U),
		Size = UDim2.new(1, -10 * U, 1, -3 * U),
		MaxTextSize = math.floor(15 * U),
		ZIndex = 2,
		Parent = hud.ComboPill,
	})

	-- Jauges des bonus (aimant / jetpack, puis x2)
	local function powerPill(): any
		local p = pill(UDim2.fromOffset(6 * U, 31 * U), UDim2.fromOffset(62 * U, 16 * U))
		p.Visible = false
		local icon = UIUtil.Label({
			Text = "🧲",
			Font = Theme.Fonts.Number,
			TextColor3 = GOLD,
			Position = UDim2.fromOffset(3 * U, 1 * U),
			Size = UDim2.fromOffset(15 * U, 14 * U),
			MaxTextSize = 30,
			ZIndex = 2,
			Parent = p,
		})
		local back = frame({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 21 * U, 0.5, 0),
			Size = UDim2.new(1, -27 * U, 0, math.max(3, 5 * U)),
			BackgroundColor3 = rgb(60, 62, 80),
			ZIndex = 2,
			Parent = p,
		}, ROUND)
		local fill = frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = GOLD,
			ZIndex = 3,
			Parent = back,
		}, ROUND)
		return { Pill = p, Icon = icon, Fill = fill }
	end
	hud.Power = powerPill()

	-- Badge des baskets (amélioration "RunnerShoes") en bas à gauche :
	-- "👟 Niv. X", couleurs du niveau, pulse quand il change
	hud.Shoe = pill(UDim2.new(0, 6 * U, 1, -6 * U), UDim2.fromOffset(64 * U, 20 * U), Vector2.new(0, 1))
	hud.Shoe.Name = "ShoeBadge"
	hud.Shoe.Visible = false
	hud.ShoeStroke = hud.Shoe:FindFirstChildOfClass("UIStroke")
	hud.ShoeScale = Create("UIScale", { Parent = hud.Shoe })
	hud.ShoeIcon = UIUtil.Label({
		Text = "👟",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3 * U, 0.5, 0),
		Size = UDim2.fromOffset(17 * U, 17 * U),
		MaxTextSize = 40,
		ZIndex = 3,
		Parent = hud.Shoe,
	})
	hud.ShoeLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(22 * U, 2 * U),
		Size = UDim2.new(1, -26 * U, 1, -4 * U),
		MaxTextSize = math.floor(14 * U),
		ZIndex = 3,
		Parent = hud.Shoe,
	})
	-- reflet coloré (dégradé selon le niveau)
	hud.ShoeShine = frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = 2,
		Parent = hud.Shoe,
	}, ROUND)
	hud.ShoeShineGradient = UIUtil.Gradient(hud.ShoeShine, ColorSequence.new(WHITE), 0)
	hud.ShoeShineGradient.Transparency = NumberSequence.new({
		nkp(0, 0.2),
		nkp(0.5, 0.75),
		nkp(1, 1),
	})

	-- Pièces ramassées qui filent vers le compteur
	local HUD_COIN = Vector2.new(16.5 * U, 16.5 * U) -- centre de l'icône du compteur
	local flyers = {}
	for _ = 1, FLYER_POOL do
		local f = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 4,
			Parent = hudLayer,
		}, ROUND)
		UIUtil.Gradient(f, coinSequence, 45)
		table.insert(flyers, { Frame = f, T = 1, From = Vector2.zero, Size = 8 })
	end

	-- Écran de fin de course : bandeau "Perdu", distance, pièces, record et
	-- bouton "Rejouer" (décoratif : il s'enfonce tout seul, puis la partie
	-- suivante commence)
	hud.Results = frame({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 7 * U),
		Size = UDim2.fromOffset(156 * U, 116 * U),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.06,
		Visible = false,
		ZIndex = 5,
		Parent = hudLayer,
	}, UDim.new(0, 12 * U))
	UIUtil.Gradient(hud.Results, ColorSequence.new(rgb(64, 70, 118), rgb(22, 22, 40)), 90)
	UIUtil.Stroke(hud.Results, WHITE, 1.5, 0.45)
	hud.ResultsScale = Create("UIScale", { Parent = hud.Results })
	hud.ResultsTitle = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 1 * U),
		Size = UDim2.fromOffset(104 * U, 22 * U),
		BackgroundColor3 = WHITE,
		ZIndex = 7,
		Parent = hud.Results,
	}, ROUND)
	UIUtil.Gradient(hud.ResultsTitle, ColorSequence.new(rgb(255, 84, 112), rgb(255, 156, 56)), 0)
	UIUtil.Stroke(hud.ResultsTitle, WHITE, 1.5, 0.1)
	local titleLabel = UIUtil.Label({
		Text = Locale.T("Game over"),
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.86, 0.72),
		MaxTextSize = math.floor(16 * U),
		ZIndex = 8,
		Parent = hud.ResultsTitle,
	})
	titleLabel.TextStrokeColor3 = rgb(120, 20, 50)
	titleLabel.TextStrokeTransparency = 0.1
	local function resultsLabel(y: number, h: number, font: Enum.Font, color: Color3, maxSize: number): TextLabel
		local label = UIUtil.Label({
			Text = "",
			Font = font,
			TextColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y * U),
			Size = UDim2.fromOffset(136 * U, h * U),
			MaxTextSize = math.floor(maxSize * U),
			ZIndex = 6,
			Parent = hud.Results,
		})
		return label
	end
	hud.ResultsDistance = resultsLabel(15, 28, Theme.Fonts.Number, WHITE, 26)
	hud.ResultsCoins = resultsLabel(44, 16, Theme.Fonts.Number, GOLD, 15)
	hud.ResultsBest = resultsLabel(62, 18, Enum.Font.LuckiestGuy, rgb(255, 220, 90), 15)
	hud.ResultsBest.TextStrokeColor3 = INK
	hud.ResultsBest.TextStrokeTransparency = 0
	hud.Replay = frame({
		Name = "Replay",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 96 * U),
		Size = UDim2.fromOffset(100 * U, 21 * U),
		BackgroundColor3 = WHITE,
		ZIndex = 7,
		Parent = hud.Results,
	}, ROUND)
	UIUtil.Gradient(hud.Replay, ColorSequence.new(rgb(110, 236, 110), rgb(24, 170, 70)), 90)
	UIUtil.Stroke(hud.Replay, rgb(10, 90, 40), math.max(1, 1.5 * U), 0)
	hud.ReplayScale = Create("UIScale", { Parent = hud.Replay })
	local replayLabel = UIUtil.Label({
		Text = "▶ " .. Locale.T("Play again"),
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.86, 0.7),
		MaxTextSize = math.floor(14 * U),
		ZIndex = 8,
		Parent = hud.Replay,
	})
	replayLabel.TextStrokeColor3 = rgb(10, 90, 40)
	replayLabel.TextStrokeTransparency = 0.2

	-- Voile noir (enchaînement entre deux parties)
	hud.Fade = frame({
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(8, 8, 16),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = screen,
	})

	------------------------------------------------------------------
	-- État de la partie
	------------------------------------------------------------------
	local st = {
		Visible = true,
		VisibleCheck = 0,
		Clock = 0,
		DayTime = DAY_LENGTH * random:NextNumber(0.1, 0.3),
		LightTimer = 0,
		LightSig = -99,
		NightMask = false,
		Night = 0,
		Mode = "Run", -- "Run" | "Crash"
		ModeT = 0,
		RunTime = 0,
		RunLength = random:NextNumber(80, 160),
		CrashPending = false,
		Speed = BASE_SPEED,
		Scroll = 0,
		WaveDistance = 0,
		Distance = 0,
		Coins = 0,
		ShownCoins = -1,
		ShownDistance = -1,
		CoinPulse = 0,
		Combo = 0,
		LastCoin = -10,
		ComboPulse = 0,
		BestBeaten = false,
		EventCooldown = 0,
		TargetLane = 2,
		LeftLane = 2,
		LaneChangedAt = -10,
		RunnerX = 0,
		RunnerH = 0,
		Lean = 0,
		RunPhase = 0,
		LastStep = 0,
		JumpT = -1, -- < 0 : pas de saut en cours
		SlideT = -1, -- < 0 : pas de glissade en cours
		LandT = 0,
		WishLane = 2,
		WishTimer = 2,
		JetTime = 0,
		MagnetTime = 0,
		DoubleTime = 0,
		PowerTimer = random:NextNumber(8, 12), -- premier bonus assez tôt
		PendingPower = nil :: string?,
		AirDistance = 0,
		AirLane = 2,
		AirCount = 0,
		LineStrength = 0,
		LinesVisible = false,
		LastStaticCam = math.huge,
		ShakeT = 0,
		FadeT = 0,
		DustTimer = 0,
		JetShown = false,
		LastCoinPop = -10,
		ShownCombo = -1,
		ShownBest = -1,
		NewBest = false,
		-- v9 : baskets ("RunnerShoes")
		ShoeLevel = -1, -- niveau affiché (-1 : pas encore appliqué)
		ShoePulse = 0, -- pulsation du badge
		ShoeFlash = 0, -- anneau autour des pieds (nouvelles baskets)
		PendingCelebrate = false,
		RibbonDrop = 0, -- défilement au dernier point posé de la traînée
		RibbonReset = true, -- traînée à recoller aux pieds (début de partie)
		RibbonsShown = false,
		ShoeFxTimer = 0,
		-- v9 : expressions et mouvements secondaires
		Turn = 0, -- tête tournée (-1 gauche .. 1 droite)
		LookTimer = random:NextNumber(3, 6),
		LookT = -1, -- < 0 : ne se retourne pas
		LookDur = 1,
		LookDir = 1,
		Expression = "Smile",
		BlinkTimer = 2,
		BlinkT = 0,
		EmoteT = 0,
		EmoteDur = 1,
		PackY = 0,
		PackV = 0,
		CharmA = 0,
		CharmV = 0,
		LastVX = 0,
		VX = 0, -- vitesse latérale du coureur
		Trick = 0, -- figure pendant le saut (0 : groupé, 1 : vrille, 2 : étoile)
		TrickDir = 1,
		-- v9 : décor
		AmbientT = 0,
		BridgeNext = random:NextNumber(10, 18), -- défilement auquel le prochain pont apparaît
	}

	local function nearestLane(x: number): number
		local best, bestDistance = 2, math.huge
		for index, laneX in ipairs(LANES) do
			local d = math.abs(x - laneX)
			if d < bestDistance then
				best, bestDistance = index, d
			end
		end
		return best
	end

	-- Vrai si la carte est affichée (le cadre et tous ses parents visibles).
	-- Le StimulusManager met déjà OnRender en pause quand le slot est caché
	-- (ctx.IsVisible / OnVisibilityChanged) : ceci n'est qu'un filet de sécurité.
	local function computeVisible(): boolean
		if type(ctx.IsVisible) == "function" then
			local ok, visible = pcall(ctx.IsVisible)
			if ok and visible == false then
				return false
			end
		end
		local node: Instance? = container
		while node do
			if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
				return false
			end
			if node:IsA("ScreenGui") then
				return (node :: ScreenGui).Enabled
			end
			node = node.Parent
		end
		return false
	end

	if type(ctx.OnVisibilityChanged) == "function" then
		ctx.OnVisibilityChanged(function(visibility: string)
			st.Visible = visibility ~= "Hidden"
			st.VisibleCheck = 0.5
		end)
	end

	------------------------------------------------------------------
	-- Jour / nuit : couleurs recalculées 5 fois par seconde au plus
	------------------------------------------------------------------
	local function placeArc(t: number, disc1: Frame, disc2: Frame?, disc3: Frame?)
		local elevation = math.sin(math.pi * math.clamp(t, 0, 1))
		local x = SW * (0.1 + 0.8 * t)
		local y = HY + 8 * U - elevation * HY * 0.78
		local position = UDim2.fromOffset(x, y)
		disc1.Position = position
		if disc2 then
			disc2.Position = position
		end
		if disc3 then
			disc3.Position = position
		end
		return elevation
	end

	local function updateLighting(force: boolean?)
		local p = (st.DayTime / DAY_LENGTH) % 1
		local key = sampleSky(p)
		st.Night = key.Night

		-- Soleil : se lève à l'aube, se couche derrière la ville
		local sunT = ((p + 0.03) % 1) / 0.61
		local sunUp = sunT <= 1
		for _, f in ipairs({ sky.Sun, sky.SunGlowOuter }) do
			f.Visible = sunUp
		end
		if sunUp then
			local elevation = placeArc(sunT, sky.Sun, sky.SunGlowOuter)
			local warm = 1 - math.clamp(elevation * 1.6, 0, 1)
			sky.Sun.BackgroundColor3 = WHITE:Lerp(rgb(255, 196, 150), warm)
			sky.SunGlowOuter.BackgroundColor3 = rgb(255, 246, 200):Lerp(rgb(255, 140, 110), warm)
		end
		-- Lune la nuit
		local moonT = (p - 0.6) / 0.38
		local moonUp = moonT >= 0 and moonT <= 1
		sky.Moon.Visible = moonUp
		sky.MoonGlow.Visible = moonUp
		if moonUp then
			placeArc(moonT, sky.Moon, sky.MoonGlow)
		end
		-- Étoiles qui scintillent
		for _, star in ipairs(stars) do
			local twinkle = 0.55 + 0.45 * math.sin(st.Clock * 2.2 + star.Phase)
			star.Frame.BackgroundTransparency = 1 - key.Night * twinkle * 0.95
		end

		-- Le reste ne change que pendant les transitions
		local signature
		if p >= 0.07 and p <= 0.45 then
			signature = -1
		elseif p >= 0.62 and p <= 0.92 then
			signature = -2
		else
			signature = math.floor(p * 300)
		end
		if signature == st.LightSig and not force then
			return
		end
		st.LightSig = signature

		ambient = key.Amb
		for _, inst in ipairs(tintList) do
			local base = tintBase[inst]
			if base then
				inst.BackgroundColor3 = mulColor(base, ambient)
			end
		end
		skyGradient.Color = skySequence(key.Top, key.Mid, key.Low)
		fog.BackgroundColor3 = key.Fog
		city.Haze.BackgroundColor3 = key.Fog
		for _, cloud in ipairs(clouds) do
			for _, puff in ipairs(cloud.Puffs) do
				puff.BackgroundColor3 = key.Cloud
				puff.BackgroundTransparency = 0.04 + key.Night * 0.4
			end
		end
		for _, entry in ipairs(city.Far) do
			local color = key.Far:Lerp(WHITE, math.max(0, entry.Shade - 1) * 2):Lerp(BLACK, math.max(0, 1 - entry.Shade))
			entry.Frame.BackgroundColor3 = color
			if entry.Antenna then
				entry.Antenna.BackgroundColor3 = color
			end
		end
		local night = key.Night
		-- Monuments lointains : silhouettes le jour, lumières la nuit
		local landmark = key.Far:Lerp(BLACK, 0.06)
		for _, f in ipairs(city.Landmarks) do
			f.BackgroundColor3 = landmark
		end
		local wheel = city.Wheel
		wheel.RingStroke.Color = landmark:Lerp(rgb(255, 120, 210), smooth(night))
		for index, gondola in ipairs(wheel.Gondolas) do
			local lit = (index % 2 == 0) and rgb(255, 230, 120) or rgb(120, 230, 255)
			gondola.Frame.BackgroundColor3 = landmark:Lerp(lit, smooth(night))
		end
		for _, bird in ipairs(birds) do
			bird.Holder.Visible = night < 0.5
			for _, wing in ipairs(bird.Wings) do
				wing.Frame.BackgroundColor3 = rgb(70, 72, 96):Lerp(key.Far, 0.3)
			end
		end
		-- Pont : bande lumineuse la nuit ; trains : vitres allumées la nuit
		if night > 0.3 then
			glowColor(bridge.Stripe, rgb(255, 150, 90):Lerp(rgb(255, 200, 120), night))
		else
			tint(bridge.Stripe, rgb(255, 120, 60))
		end
		local trainGlass = rgb(52, 72, 116):Lerp(rgb(255, 222, 150), smooth(math.clamp((night - 0.3) / 0.5, 0, 1)))
		for _, train in ipairs(trains) do
			if night > 0.3 then
				quadGlow(train.Windows, trainGlass)
			else
				quadColor(train.Windows, trainGlass)
			end
		end
		local useNightMask = night > 0.5
		local maskChanged = useNightMask ~= st.NightMask
		st.NightMask = useNightMask
		local glass = mulColor(GLASS_DAY, ambient):Lerp(key.Fog, 0.2):Lerp(WINDOW_NIGHT, smooth(night))
		for _, building in ipairs(city.Mid) do
			local face = mulColor(building.Base, ambient):Lerp(key.Fog, 0.28)
			building.Body.BackgroundColor3 = face
			for _, extra in ipairs(building.Extras) do
				extra.BackgroundColor3 = face:Lerp(BLACK, 0.12)
			end
			for _, block in ipairs(building.Blocks) do
				block.Floors.BackgroundColor3 = face
				block.Windows.BackgroundColor3 = glass
				if maskChanged or force then
					block.Gradient.Color = useNightMask and block.NightMask or block.DayMask
				end
			end
		end
		-- Lampadaires et phares : plus forts la nuit
		for _, pole in ipairs(poles) do
			pole.Glow.BackgroundColor3 = rgb(206, 210, 222):Lerp(LAMP_LIGHT, night)
			pole.Pool.BackgroundTransparency = 1 - night * 0.22
		end
		for _, train in ipairs(trains) do
			if train.Extra <= 0 then
				train.Beam.BackgroundTransparency = 1 - night * 0.45
			end
		end
	end

	------------------------------------------------------------------
	-- Apparition des objets
	------------------------------------------------------------------
	local function firstFree(pool)
		for _, object in ipairs(pool) do
			if not object.Active then
				return object
			end
		end
		return nil
	end

	local function hideTrain(train)
		train.Active = false
		train.Body.Visible = false
		hideQuad(train.Side)
		hideQuad(train.Roof)
		hideQuad(train.Windows)
	end

	local function spawnTrain(lane: number, z: number, oncoming: boolean): boolean
		local train = firstFree(trains)
		if not train then
			return false
		end
		local livery = TRAIN_LIVERIES[random:NextInteger(1, #TRAIN_LIVERIES)]
		train.Active = true
		train.Lane = lane
		train.Z = z
		train.Extra = oncoming and ONCOMING_EXTRA or 0
		train.Passed = false
		tint(train.Body, livery.Body)
		tint(train.Cap, livery.Body:Lerp(BLACK, 0.3))
		tint(train.Pillar, livery.Body:Lerp(BLACK, 0.45))
		tint(train.Stripe, livery.Accent)
		quadColor(train.Side, livery.Body:Lerp(BLACK, 0.22))
		quadColor(train.Roof, livery.Body:Lerp(WHITE, 0.45):Lerp(rgb(150, 150, 170), 0.25))
		local lightColor = oncoming and rgb(255, 252, 214) or rgb(255, 222, 150)
		train.HeadL.BackgroundColor3 = lightColor
		train.HeadR.BackgroundColor3 = lightColor
		train.HeadL.BackgroundTransparency = oncoming and 0 or 0.3
		train.HeadR.BackgroundTransparency = oncoming and 0 or 0.3
		train.Beam.BackgroundTransparency = oncoming and 0.6 or (1 - st.Night * 0.45)
		train.Body.Visible = true
		return true
	end

	local function spawnObstacle(lane: number, z: number, kind: string): boolean
		local wanted = kind == "Cone" and "Cone" or "Board"
		local ob: any = nil
		for _, candidate in ipairs(obstacles) do
			if not candidate.Active and candidate.Type == wanted then
				ob = candidate
				break
			end
		end
		if not ob then
			-- plus de cônes libres : une barrière basse à la place
			return kind == "Cone" and spawnObstacle(lane, z, "Low") or false
		end
		ob.Active = true
		ob.Lane = lane
		ob.Z = z
		ob.Kind = kind
		ob.Handled = false
		ob.Fatal = false
		ob.Passed = false
		ob.Knock = 0
		ob.Phase = random:NextNumber(0, 6)
		if kind == "Cone" then
			ob.Bottom, ob.Top = 0, 30
			ob.Cones.Visible = true
			ob.Cones.Rotation = 0
		else
			if kind == "Low" then
				ob.Bottom, ob.Top = 20, 38
				ob.Gradient.Color = stripes(rgb(236, 40, 52), WHITE, 7)
			else
				ob.Bottom, ob.Top = 58, 78
				ob.Gradient.Color = stripes(rgb(255, 200, 20), rgb(34, 34, 44), 7)
			end
			local legScale = ob.Bottom / (ob.Top - ob.Bottom)
			for _, leg in ipairs(ob.Legs) do
				leg.Size = UDim2.fromScale(0.065, legScale)
			end
			ob.Shadow.Position = UDim2.fromScale(0.5, 1 + legScale)
			ob.Shadow.Size = UDim2.fromScale(1.02, 0.22 * (18 / (ob.Top - ob.Bottom)))
			ob.Light.Visible = kind == "High"
			ob.Board.Rotation = 0
			ob.Board.Visible = true
		end
		return true
	end

	local function spawnCoin(lane: number, z: number, height: number, air: boolean)
		local coin = firstFree(coinsPool)
		if not coin then
			return
		end
		coin.Active = true
		coin.Lane = lane
		coin.X = LANES[lane]
		coin.H = height
		coin.Z = z
		coin.Phase = z * 2.2
		coin.Air = air
		coin.Pulled = false
		coin.Frame.Visible = true
	end

	local function laneIsEmpty(lane: number): boolean
		for _, pool in ipairs({ trains, obstacles, coinsPool }) do
			for _, object in ipairs(pool) do
				if object.Active and object.Lane == lane then
					return false
				end
			end
		end
		return not (pickup.Active and pickup.Lane == lane)
	end

	local function anyTrain(): boolean
		for _, train in ipairs(trains) do
			if train.Active then
				return true
			end
		end
		return false
	end

	-- Une vague : une voie toujours libre, le reste trains / barrières / cônes / rien
	local function spawnWave(z: number)
		local trainsAllowed = st.JetTime <= 0 or st.JetTime > 3.5
		local free = random:NextInteger(1, 3)
		local kinds = { "None", "None", "None" }

		-- Parfois un train qui fonce vers nous (seul train à l'écran, voie vide)
		local oncoming: number? = nil
		if trainsAllowed and not anyTrain() and random:NextNumber() < 0.3 then
			local candidate = random:NextInteger(1, 3)
			if laneIsEmpty(candidate) then
				oncoming = candidate
				kinds[candidate] = "Oncoming"
				if free == candidate then
					free = candidate % 3 + 1
				end
			end
		end

		for lane = 1, 3 do
			if lane ~= free and kinds[lane] == "None" then
				local roll = random:NextNumber()
				if trainsAllowed and not oncoming and roll < 0.4 then
					kinds[lane] = "Train"
				elseif roll < 0.82 then
					local pick = random:NextNumber()
					kinds[lane] = (pick < 0.42) and "Low" or (pick < 0.7 and "Cone" or "High")
				end
			end
		end
		-- Jamais deux trains côte à côte : le coureur serait coincé
		if kinds[2] == "Train" and (kinds[1] == "Train" or kinds[3] == "Train") then
			kinds[2] = "Low"
		end

		for lane = 1, 3 do
			local kind = kinds[lane]
			if kind == "Train" or kind == "Oncoming" then
				if not spawnTrain(lane, z, kind == "Oncoming") then
					kinds[lane] = "None"
				end
			elseif kind ~= "None" then
				if not spawnObstacle(lane, z, kind) then
					kinds[lane] = "None"
				end
			end
		end

		-- Bonus sur la voie libre
		if st.PendingPower and not pickup.Active then
			local kind = st.PendingPower :: string
			local style = POWER_STYLE[kind]
			pickup.Active = true
			pickup.Kind = kind
			pickup.Lane = free
			pickup.Z = z + 1.3
			pickup.Icon.Text = style.Icon
			pickup.Text.Text = style.Text
			pickup.Halo.BackgroundColor3 = style.Color
			pickup.Stroke.Color = style.Color
			pickup.Bubble.BackgroundColor3 = WHITE:Lerp(style.Color, 0.25)
			pickup.Root.Visible = true
			st.PendingPower = nil
		end

		-- Pièces : sur la voie libre, ou en arc au-dessus d'un obstacle bas
		local coinLane = free
		if random:NextNumber() < 0.4 then
			local other = random:NextInteger(1, 3)
			local kind = kinds[other]
			if kind == "Low" or kind == "Cone" or kind == "High" or kind == "None" then
				coinLane = other
			end
		end
		local count = random:NextInteger(3, 5)
		local arc = kinds[coinLane] == "Low" or kinds[coinLane] == "Cone"
		for k = 0, count - 1 do
			local dz = (k - (count - 1) / 2) * 0.42
			local height = COIN_H
			if arc then
				height += 38 * math.max(0, 1 - (dz / 0.95) ^ 2)
			end
			spawnCoin(coinLane, z + dz, height, false)
		end
	end

	------------------------------------------------------------------
	-- Ramassage, événements
	------------------------------------------------------------------
	local function eventText(text: string, color: Color3)
		if st.EventCooldown > 0 then
			return
		end
		st.EventCooldown = 2.6
		popText(text, CX, HY - 8 * U, color, 150 * U, 22 * U, true)
	end

	-- Pièce qui file vers le compteur (le compteur pulse à son arrivée)
	local function launchFlyer(x: number, y: number, size: number)
		if not effectsOn() then
			st.CoinPulse = 1
			return
		end
		local chosen = flyers[1]
		for _, flyer in ipairs(flyers) do
			if flyer.T >= 1 then
				chosen = flyer
				break
			end
			if flyer.T > chosen.T then
				chosen = flyer
			end
		end
		if chosen.T < 1 then
			st.CoinPulse = 1 -- pièce remplacée : elle "arrive" tout de suite
		end
		chosen.T = 0
		chosen.From = Vector2.new(x, y)
		chosen.Size = math.max(6 * U, size)
		chosen.Frame.Visible = true
	end

	-- Bulle d'émoji au-dessus de la tête
	local function showEmote(emoji: string, duration: number)
		if not effectsOn() then
			return
		end
		hero.EmoteLabel.Text = emoji
		hero.Emote.Visible = true
		st.EmoteT = 0
		st.EmoteDur = duration
	end

	-- Se retourne (visage visible) : "Smile" | "Wow" | "Happy" | "Dizzy"
	local function lookBack(expression: string, duration: number, direction: number?)
		st.Expression = expression
		st.LookT = 0
		st.LookDur = duration
		st.LookDir = direction or ((random:NextNumber() < 0.5) and -1 or 1)
		st.LookTimer = random:NextNumber(6, 11)
	end

	local function collectCoin(coin, px: number, py: number)
		coin.Active = false
		coin.Frame.Visible = false
		local gain = st.DoubleTime > 0 and 2 or 1
		st.Coins += gain
		launchFlyer(px, py, COIN_SIZE * U / math.max(coin.Z, 0.6))
		if st.Clock - st.LastCoin < COMBO_WINDOW then
			st.Combo += 1
			st.ComboPulse = 1
		else
			st.Combo = 1
		end
		st.LastCoin = st.Clock
		spawnSparkles(px, py, 2)
		local headY = sy(st.RunnerH + CHAR_H + 4, CHAR_Z)
		if st.Clock - st.LastCoinPop < 0.3 then
			return
		end
		st.LastCoinPop = st.Clock
		popText(gain == 2 and "+2" or "+1", px + random:NextNumber(4, 14) * U, math.min(py, headY), gain == 2 and rgb(255, 150, 60) or GOLD, 28 * U, 13 * U)
	end

	local function activatePower(kind: string, px: number, py: number)
		local popY = HY - 14 * U -- au-dessus de la tête (bulle d'émoji)
		st.EventCooldown = math.max(st.EventCooldown, 1.2)
		if kind == "Jetpack" then
			st.JetTime = JET_TIME
			st.MagnetTime = 0
			st.AirLane = st.TargetLane
			st.AirCount = 0
			st.AirDistance = 0
			st.JumpT, st.SlideT = -1, -1
			popText(Locale.T("JETPACK!"), CX, popY, rgb(120, 220, 255), 130 * U, 26 * U, true)
			showEmote("😎", 1.6)
		elseif kind == "Double" then
			st.DoubleTime = DOUBLE_TIME
			popText(Locale.T("COINS x2!"), CX, popY, rgb(255, 196, 40), 140 * U, 26 * U, true)
			showEmote("🤑", 1.4)
		else
			st.MagnetTime = MAGNET_TIME
			st.JetTime = 0
			popText(Locale.T("MAGNET!"), CX, popY, rgb(255, 120, 190), 130 * U, 26 * U, true)
			showEmote("😍", 1.4)
		end
		lookBack("Happy", 0.9)
		spawnSparkles(px, py, 6)
	end

	------------------------------------------------------------------
	-- Baskets : niveau de l'amélioration "RunnerShoes" (0 à 10), visible
	-- sur le coureur, dans sa traînée et dans le badge du HUD ; mis à jour
	-- en direct à chaque achat (ctx.State.Changed)
	------------------------------------------------------------------
	local shoeTier = SHOE_TIERS[0]
	local shoeTrail: any = nil -- style de traînée lumineuse (nil = poussière seulement)

	local function readShoeLevel(): number
		local level = tonumber(ctx.GetLevel("RunnerShoes")) or 0
		return math.clamp(math.floor(level), 0, MAX_SHOE_LEVEL)
	end

	local function applyShoes(level: number)
		local tier = SHOE_TIERS[level] or SHOE_TIERS[0]
		shoeTier = tier
		st.ShoeLevel = level
		local glow = tier.Glow
		local flameLevel = tier.Flame or 0
		for _, shoe in ipairs(hero.Shoes) do
			tint(shoe.Upper, tier.Body)
			tint(shoe.Heel, tier.Accent)
			shoe.Stripe.Visible = tier.Stripe ~= nil
			if tier.Stripe then
				tint(shoe.Stripe, tier.Stripe)
			end
			shoe.Laces.Visible = tier.Laces ~= nil
			if tier.Laces then
				tint(shoe.Laces, tier.Laces)
			end
			-- semelle lumineuse (néon) : jamais assombrie la nuit
			if glow then
				glowColor(shoe.Sole, tier.Sole)
				shoe.Glow.BackgroundColor3 = glow
			else
				tint(shoe.Sole, tier.Sole)
			end
			shoe.Glow.Visible = glow ~= nil
			shoe.Wing.Visible = tier.Wings ~= nil
			if tier.Wings then
				for _, feather in ipairs(shoe.Feathers) do
					tint(feather, tier.Wings)
				end
			end
			shoe.Flame.Visible = flameLevel > 0
			shoe.Core.Visible = flameLevel > 1
			shoe.Nozzle.Visible = flameLevel > 0
			shoe.Root.Size = UDim2.fromScale(SHOE_W * (flameLevel > 1 and 1.06 or 1), SHOE_H * (tier.High and 1.3 or 1))
		end
		hero.UnderGlow.Visible = glow ~= nil
		if glow then
			hero.UnderGlow.BackgroundColor3 = glow
		end
		-- Traînée lumineuse (niveaux 5+) : couleurs de la tête à la queue
		shoeTrail = glow and SHOE_TRAILS[tier.Trail] or nil
		for _, ribbon in ipairs(ribbons) do
			for k, segment in ipairs(ribbon.Segments) do
				if shoeTrail and glow then
					local head = shoeTrail.HeadColor or glow
					local tail = shoeTrail.TailColor or glow
					local t0, t1 = (k - 1) / RIBBON_SEGMENTS, k / RIBBON_SEGMENTS
					local gradient = ribbon.Gradients[k]
					gradient.Color = ColorSequence.new(head:Lerp(tail, t0), head:Lerp(tail, t1))
					gradient.Transparency = NumberSequence.new(
						shoeTrail.Head + (shoeTrail.Tail - shoeTrail.Head) * t0,
						shoeTrail.Head + (shoeTrail.Tail - shoeTrail.Head) * t1
					)
				end
				show(segment, false)
			end
		end
		-- Lignes de vitesse teintées aux hauts niveaux
		for _, line in ipairs(speedLines) do
			line.Frame.BackgroundColor3 = glow and WHITE:Lerp(glow, 0.35) or WHITE
		end
		-- Badge du HUD
		hud.Shoe.Visible = level > 0
		if level > 0 then
			local color = SHOE_BADGE[level] or WHITE
			hud.ShoeLabel.Text = Locale.T("Lv. %s", tostring(level))
			hud.ShoeLabel.TextColor3 = level >= MAX_SHOE_LEVEL and rgb(255, 224, 110) or WHITE
			hud.ShoeShine.BackgroundColor3 = color
			if hud.ShoeStroke then
				hud.ShoeStroke.Color = color
				hud.ShoeStroke.Transparency = 0.05
				hud.ShoeStroke.Thickness = level >= MAX_SHOE_LEVEL and 2 or 1.5
			end
		end
	end

	-- Nouvelles baskets : texte, anneau aux pieds, étincelles, badge qui pulse
	local function celebrateShoes()
		local color = SHOE_BADGE[st.ShoeLevel] or WHITE
		st.ShoeFlash = 1
		st.ShoePulse = 1
		hero.ShoeRingStroke.Color = color
		hero.ShoeRing.Visible = true
		popText(Locale.T("NEW SHOES!"), CX, HY - 14 * U, color, 160 * U, 24 * U, true)
		st.EventCooldown = math.max(st.EventCooldown, 1.6)
		showEmote("🤩", 1.6)
		lookBack("Happy", 1.1)
		spawnSparkles(sx(st.RunnerX, CHAR_Z), sy(6, CHAR_Z), 5)
	end

	local function refreshShoes()
		local level = readShoeLevel()
		if level == st.ShoeLevel then
			return
		end
		local upgraded = st.ShoeLevel >= 0 and level > st.ShoeLevel
		applyShoes(level)
		if upgraded then
			st.PendingCelebrate = true -- joué dès que la carte est visible
		end
	end

	------------------------------------------------------------------
	-- "IA" du coureur : choisit sa voie (évite les trains, vise les pièces)
	------------------------------------------------------------------

	-- Temps (s) avant qu'un train n'arrive sur le coureur dans cette voie
	local function laneDanger(lane: number): number
		local best = math.huge
		for _, train in ipairs(trains) do
			if train.Active and train.Lane == lane then
				local v = st.Speed + train.Extra
				local leave = (train.Z + TRAIN_LEN - CHAR_Z + 0.3) / v
				if leave > 0 then
					best = math.min(best, math.max(0, (train.Z - CHAR_Z - 0.3) / v))
				end
			end
		end
		return best
	end

	local function laneAppeal(lane: number): number
		local score = 0
		for _, coin in ipairs(coinsPool) do
			if coin.Active and coin.Lane == lane and coin.Z > CHAR_Z and coin.Z < CHAR_Z + 3.5 then
				score += 0.5
			end
		end
		for _, ob in ipairs(obstacles) do
			if ob.Active and ob.Lane == lane and ob.Z > CHAR_Z and ob.Z < CHAR_Z + 3 then
				-- fin de course programmée : il fonce (sans le savoir) vers l'obstacle
				score += (st.CrashPending and ob.Kind ~= "High") and 1.5 or -0.2
			end
		end
		if pickup.Active and pickup.Lane == lane and pickup.Z > CHAR_Z then
			score += 4
		end
		if lane == st.WishLane then
			score += 0.9
		end
		return score
	end

	local function setLane(lane: number)
		if lane ~= st.TargetLane then
			st.LeftLane = st.TargetLane
			st.LaneChangedAt = st.Clock
			st.TargetLane = lane
		end
	end

	local function chooseLane()
		local current = st.TargetLane
		local danger = { laneDanger(1), laneDanger(2), laneDanger(3) }
		local bestLane, bestScore = current, -math.huge
		for lane = 1, 3 do
			local score = laneAppeal(lane) - math.abs(lane - current) * 0.8
			if danger[lane] < 1.1 then
				score -= 100 - danger[lane] * 20 -- plus le train est proche, pire c'est
			end
			if math.abs(lane - current) == 2 and danger[2] < 0.9 then
				score -= 80 -- impossible de traverser la voie du milieu
			end
			if lane == current then
				score += 0.3
			end
			if score > bestScore then
				bestLane, bestScore = lane, score
			end
		end
		if bestLane ~= current then
			setLane(current + (bestLane > current and 1 or -1)) -- une voie à la fois
		end
	end

	------------------------------------------------------------------
	-- Début / fin de partie
	------------------------------------------------------------------
	local function resetRun()
		for _, train in ipairs(trains) do
			hideTrain(train)
		end
		for _, ob in ipairs(obstacles) do
			ob.Active = false
			ob.Visual.Visible = false
		end
		for _, coin in ipairs(coinsPool) do
			coin.Active = false
			coin.Frame.Visible = false
		end
		pickup.Active = false
		pickup.Root.Visible = false
		st.Mode, st.ModeT = "Run", 0
		st.ShownCombo = -1
		hud.ResultsBest.Rotation = 0
		st.RunTime = 0
		st.RunLength = random:NextNumber(80, 160)
		st.CrashPending = false
		st.Speed = BASE_SPEED
		st.WaveDistance = 0
		st.Distance = 0
		st.Coins = 0
		st.Combo = 0
		st.BestBeaten = false
		st.TargetLane, st.LeftLane = 2, 2
		st.RunnerX, st.RunnerH = 0, 0
		st.JumpT, st.SlideT, st.LandT = -1, -1, 0
		st.JetTime, st.MagnetTime, st.DoubleTime = 0, 0, 0
		st.PowerTimer = random:NextNumber(8, 12)
		st.PendingPower = nil
		st.LookT, st.Turn = -1, 0
		st.LookTimer = random:NextNumber(3, 6)
		st.Trick = 0
		st.RibbonReset = true
		hero.Root.Rotation = 0
		hud.Results.Visible = false
		hud.ReplayScale.Scale = 1
		spawnWave(Z_FAR - WAVE_GAP * 1.5)
		spawnWave(Z_FAR)
		popText(Locale.T("GO!"), CX, HY + 10 * U, rgb(120, 255, 160), 110 * U, 28 * U, true)
	end

	local function startCrash(ob)
		st.Mode, st.ModeT = "Crash", 0
		st.CrashPending = false
		st.JumpT, st.SlideT = -1, -1
		st.Combo = 0
		st.ShakeT = 0.35
		ob.Knock = 0.001
		local px, py = sx(st.RunnerX, CHAR_Z), sy(20, CHAR_Z)
		spawnSparkles(px, py, 6)
		for k = 1, 5 do
			spawnDust(px + (k - 3) * 5 * U, sy(0, CHAR_Z), (k - 3) * 22 * U, -random:NextNumber(10, 30) * U, 7 * U, 0.6)
		end
		popText(Locale.T("OUCH!"), CX, HY + 4 * U, rgb(255, 110, 100), 120 * U, 28 * U, true)
		-- sonné : il se retourne (yeux en croix), étoiles autour de la tête
		lookBack("Dizzy", 99, (random:NextNumber() < 0.5) and -1 or 1)
		showEmote("😵", 1.3)
		-- Résultats (affichés un peu plus tard)
		local meters = math.floor(st.Distance)
		local newBest = meters > sessionBest
		local previousBest = sessionBest
		if newBest then
			sessionBest = meters
		end
		hud.ResultsDistance.Text = withSpaces(meters) .. " m"
		hud.ResultsCoins.Text = "🪙 " .. withSpaces(st.Coins)
		st.NewBest = newBest and previousBest > 0
		if st.NewBest then
			hud.ResultsBest.Text = Locale.T("NEW BEST!")
			hud.ResultsBest.TextColor3 = rgb(255, 220, 90)
		else
			hud.ResultsBest.Text = Locale.T("Best: %s m", withSpaces(sessionBest))
			hud.ResultsBest.TextColor3 = rgb(200, 210, 240)
		end
	end

	------------------------------------------------------------------
	-- Mise en place : décor placé, deux vagues déjà en route
	------------------------------------------------------------------
	updateStatic()
	st.LastStaticCam = camX
	updateLighting(true)
	spawnWave(Z_FAR - WAVE_GAP * 1.5)
	spawnWave(Z_FAR)
	refreshShoes()
	ctx.Connect(ctx.State.Changed, refreshShoes)

	------------------------------------------------------------------
	-- Décor qui défile
	------------------------------------------------------------------
	-- Décor d'ambiance (30 images/s au plus) : nuages, oiseaux, grande
	-- roue, feu de la tour de télévision
	local function updateAmbient(dt: number)
		for _, cloud in ipairs(clouds) do
			cloud.X -= cloud.Speed * dt
			if cloud.X < -cloud.Width then
				cloud.X += SW + cloud.Width * 2
			end
			cloud.Frame.Position = UDim2.fromOffset(cloud.X - camX * cloud.Parallax * U, cloud.Y)
		end
		for _, bird in ipairs(birds) do
			if bird.Holder.Visible then
				bird.X += bird.Speed * dt
				if bird.X > SW + 14 * U then
					bird.X = -14 * U
					bird.Y = random:NextNumber(0.25, 0.6) * HY
				end
				local y = bird.Y + math.sin(st.Clock * 1.3 + bird.Phase) * 2 * U
				bird.Holder.Position = UDim2.fromOffset(bird.X - camX * 0.05 * U, y)
				-- ailes en "V" qui battent (bout intérieur collé au corps)
				local angle = 14 + math.sin(st.Clock * bird.Flap + bird.Phase) * 26
				local rad = math.rad(angle)
				local half = 2.3 * U
				for _, wing in ipairs(bird.Wings) do
					wing.Frame.Position = UDim2.fromOffset(4.5 * U + wing.Sign * math.cos(rad) * half, 3 * U - math.sin(rad) * half)
					wing.Frame.Rotation = -wing.Sign * angle
				end
			end
		end
		local wheel = city.Wheel
		wheel.Angle += dt * 0.22
		for _, spoke in ipairs(wheel.Spokes) do
			spoke.Frame.Rotation = spoke.Base + math.deg(wheel.Angle)
		end
		for _, gondola in ipairs(wheel.Gondolas) do
			local a = gondola.Base + wheel.Angle
			gondola.Frame.Position = UDim2.fromOffset(wheel.Center.X + math.cos(a) * wheel.Radius, wheel.Center.Y + math.sin(a) * wheel.Radius)
		end
		city.TowerLight.BackgroundTransparency = (st.Night > 0.3 and math.sin(st.Clock * 3.2) > 0.2) and 0 or 1
		-- reflet qui glisse sur le badge des baskets
		if hud.Shoe.Visible then
			hud.ShoeShineGradient.Offset = Vector2.new(math.sin(st.Clock * 1.6) * 0.5, 0)
		end
	end

	-- Pont : apparaît au loin de temps en temps et passe au-dessus du coureur
	local function hideBridge()
		bridge.Active = false
		bridge.Face.Visible = false
		bridge.Under.Visible = false
		bridge.Shadow.Visible = false
		for _, pillar in ipairs(bridge.Pillars) do
			pillar.Frame.Visible = false
		end
	end

	local function updateBridge(move: number)
		if not bridge.Active then
			if st.Mode == "Run" and st.Scroll >= st.BridgeNext then
				st.BridgeNext = st.Scroll + random:NextNumber(40, 64)
				bridge.Active = true
				bridge.Z = Z_FAR + 2.5
				bridge.Face.Visible = true
				bridge.Under.Visible = true
				bridge.Shadow.Visible = true
				for _, pillar in ipairs(bridge.Pillars) do
					pillar.Frame.Visible = true
				end
			else
				return
			end
		end
		bridge.Z -= move
		local z = bridge.Z
		if z + BRIDGE_DEPTH < 0.3 then
			hideBridge()
			return
		end
		local zf = math.max(z, 0.22)
		local zb = math.max(z + BRIDGE_DEPTH, 0.28)
		local zm = (zf + zb) / 2
		local left, right = -14 * U, SW + 14 * U
		local top, low = sy(BRIDGE_TOP, zf), sy(BRIDGE_LOW, zf)
		bridge.Face.Position = UDim2.fromOffset(left, top)
		bridge.Face.Size = UDim2.fromOffset(right - left, math.max(1, low - top))
		bridge.Face.ZIndex = depthZ(zf)
		local lowBack = sy(BRIDGE_LOW, zb)
		bridge.Under.Position = UDim2.fromOffset(left, low)
		bridge.Under.Size = UDim2.fromOffset(right - left, math.max(1, lowBack - low))
		bridge.Under.ZIndex = depthZ(zb)
		for _, pillar in ipairs(bridge.Pillars) do
			local pillarTop = sy(BRIDGE_LOW, zm)
			pillar.Frame.Position = UDim2.fromOffset(sx(pillar.Sign * BRIDGE_PILLAR_X, zm), pillarTop)
			pillar.Frame.Size = UDim2.fromOffset(math.max(1, 18 * U / zm), math.max(1, sy(WALL_H, zm) - pillarTop))
			pillar.Frame.ZIndex = depthZ(zm)
		end
		-- ombre sur la voie (entre les murs)
		local shadowTop, shadowBottom = sy(0, zb), sy(0, zf)
		local halfW = WALL_X * U / zf
		bridge.Shadow.Position = UDim2.fromOffset(sx(0, zf) - halfW, shadowTop)
		bridge.Shadow.Size = UDim2.fromOffset(halfW * 2, math.max(1, shadowBottom - shadowTop))
	end

	local function updateScenery(dt: number, move: number)
		updateBridge(move)
		city.FarHolder.Position = UDim2.fromOffset(-SKY_MARGIN - camX * 0.06 * U, 0)
		city.MidHolder.Position = UDim2.fromOffset(-SKY_MARGIN - camX * 0.15 * U, 0)

		local scroll = st.Scroll
		for _, tie in ipairs(ties) do
			local z = TIE_START + (tie.Offset - scroll) % TIE_CYCLE
			local top = sy(0, z + TIE_DEPTH)
			local f = tie.Frame
			f.Position = UDim2.fromOffset(sx(tie.X, z + TIE_DEPTH * 0.5), top)
			f.Size = UDim2.fromOffset(TIE_HALF * 2 * U / z, math.max(1, sy(0, z) - top))
			local alpha = fade(z, 3, 4.4)
			if alpha ~= tie.Alpha then
				tie.Alpha = alpha
				f.BackgroundTransparency = alpha
			end
		end

		for _, pole in ipairs(poles) do
			local z = 0.55 + (pole.Offset - scroll) % POLE_CYCLE
			local x = sx(pole.Sign * POLE_X, z)
			local topY = sy(POLE_H, z)
			local t = fade(z, 4.6, 5.9)
			local depth = depthZ(z)
			pole.Pole.Position = UDim2.fromOffset(x, sy(0, z))
			pole.Pole.Size = UDim2.fromOffset(math.max(1, 4 * U / z), POLE_H * U / z)
			pole.Arm.Position = UDim2.fromOffset(x, topY)
			pole.Arm.Size = UDim2.fromOffset(POLE_ARM * U / z, math.max(1, 3 * U / z))
			if depth ~= pole.Depth then
				pole.Depth = depth
				pole.Pole.ZIndex = depth
				pole.Arm.ZIndex = depth
				pole.Pool.ZIndex = depth - 1
			end
			if t ~= pole.Alpha then
				pole.Alpha = t
				pole.Pole.BackgroundTransparency = t
				pole.Arm.BackgroundTransparency = t
				pole.Glow.BackgroundTransparency = t
			end
			-- flaque de lumière sous la lampe (la nuit)
			local lampX = pole.Sign * (POLE_X - POLE_ARM)
			pole.Pool.Position = UDim2.fromOffset(sx(lampX, z), sy(0, z))
			pole.Pool.Size = UDim2.fromOffset(56 * U / z, 12 * U / z)
			show(pole.Pool, st.Night > 0.05 and t < 1)
		end

		for _, pillar in ipairs(pillars) do
			local z = 0.7 + (pillar.Offset - scroll) % PILLAR_CYCLE
			local f = pillar.Frame
			local x = sx(pillar.Sign * PILLAR_X, z)
			local originX = pillar.Sign < 0 and 0 or CX
			f.Position = UDim2.fromOffset(x - originX, sy(0, z))
			f.Size = UDim2.fromOffset(math.max(1, PILLAR_W * U / z), (WALL_H + 2) * U / z)
			local alpha = fade(z, 5.2, 6.4)
			if alpha ~= pillar.Alpha then
				pillar.Alpha = alpha
				f.BackgroundTransparency = alpha
			end
		end

		for _, tree in ipairs(trees) do
			local z = 1 + (tree.Offset - scroll) % TREE_CYCLE
			local originX = tree.Sign < 0 and 0 or CX
			local x = sx(tree.Sign * TREE_X, z) - originX
			local k = U / z * tree.Size
			tree.Trunk.Position = UDim2.fromOffset(x, sy(WALL_H - 4, z))
			tree.Trunk.Size = UDim2.fromOffset(math.max(1, 5 * k), 26 * k)
			tree.Crown.Position = UDim2.fromOffset(x, sy(WALL_H - 4, z) - 36 * k)
			tree.Crown.Size = UDim2.fromOffset(40 * k, 36 * k)
		end

		for _, panel in ipairs(panels) do
			panel.Z -= move
			if panel.Z + PANEL_LEN < 1 then
				panel.Z = random:NextNumber(8, 12)
				restylePanel(panel)
			end
			local f = panel.Frame
			if panel.Z > 8 then
				f.Visible = false
			else
				local s = panel.Side.Sign
				local xNear = sx(s * WALL_X, panel.Z)
				local xFar = sx(s * WALL_X, panel.Z + PANEL_LEN)
				local midZ = panel.Z + PANEL_LEN / 2
				local top = sy(54, midZ)
				local t = fade(panel.Z, 6.3, 8)
				f.Visible = true
				f.Position = UDim2.fromOffset(math.min(xNear, xFar) - panel.Side.Origin.X, top)
				f.Size = UDim2.fromOffset(math.abs(xNear - xFar), sy(16, midZ) - top)
				f.BackgroundTransparency = t
				panel.Label.TextTransparency = t
				panel.Label.TextStrokeTransparency = t
			end
		end
	end

	------------------------------------------------------------------
	-- Trains
	------------------------------------------------------------------
	local function updateTrains(dt: number, move: number)
		for _, train in ipairs(trains) do
			if train.Active then
				local previousZ = train.Z
				train.Z -= move + train.Extra * dt * (st.Mode == "Run" and 1 or 0)
				if previousZ >= CHAR_Z and train.Z < CHAR_Z and st.Mode == "Run" and not train.Passed then
					train.Passed = true
					-- Évité de justesse : train qui fonce à côté, ou voie quittée à temps
					local laneX = LANES[train.Lane]
					local dodged = st.Clock - st.LaneChangedAt < 1 and train.Lane == st.LeftLane
					if dodged or (train.Extra > 0 and math.abs(laneX - st.RunnerX) < 100 and st.JetTime <= 0) then
						eventText(Locale.T("CLOSE CALL!"), rgb(255, 150, 90))
						-- il se retourne, les yeux ronds, vers le train qui passe
						lookBack("Wow", 1.1, laneX < st.RunnerX and -1 or 1)
						showEmote("😮", 1.2)
					end
				end
				if train.Z < Z_NEAR then
					hideTrain(train)
				else
					local z = train.Z
					local back = z + TRAIN_LEN
					local laneX = LANES[train.Lane]
					local x = sx(laneX, z)
					local depth = depthZ(z)
					local body = train.Body
					body.Position = UDim2.fromOffset(x, sy(0, z))
					body.Size = UDim2.fromOffset(TRAIN_W * U / z, TRAIN_H * U / z)
					body.ZIndex = depth
					local halfW = TRAIN_W / 2
					-- Toit : trapèze entre l'avant et l'arrière
					setHQuad(
						train.Roof,
						sy(TRAIN_H, back),
						sx(laneX - halfW + 3, back),
						sx(laneX + halfW - 3, back),
						sy(TRAIN_H, z) + 1,
						sx(laneX - halfW + 3, z),
						sx(laneX + halfW - 3, z),
						depth - 1
					)
					-- Flanc tourné vers la caméra
					local offset = laneX - camX
					if math.abs(offset) > halfW then
						local sideX = offset > 0 and laneX - halfW or laneX + halfW
						setVQuad(
							train.Side,
							sx(sideX, z),
							sy(TRAIN_H - 4, z),
							sy(2, z),
							sx(sideX, back),
							sy(TRAIN_H - 4, back),
							sy(2, back),
							depth - 3
						)
						-- bande vitrée (du nez à l'arrière), inutile au loin
						if z < 7 then
							local winFront, winBack = z + 0.14, back - 0.12
							setVQuad(
								train.Windows,
								sx(sideX, winFront),
								sy(TRAIN_H - 17, winFront),
								sy(TRAIN_H - 40, winFront),
								sx(sideX, winBack),
								sy(TRAIN_H - 17, winBack),
								sy(TRAIN_H - 40, winBack),
								depth - 2
							)
						else
							hideQuad(train.Windows)
						end
					else
						hideQuad(train.Side)
						hideQuad(train.Windows)
					end
					if train.Extra > 0 then
						-- Phares qui clignotent : il fonce vers nous !
						local blink = (math.sin(st.Clock * 16) > 0) and 0 or 0.4
						train.HeadL.BackgroundTransparency = blink
						train.HeadR.BackgroundTransparency = 0.4 - blink
					end
				end
			end
		end
	end

	------------------------------------------------------------------
	-- Obstacles
	------------------------------------------------------------------
	local function updateObstacles(dt: number, move: number)
		for _, ob in ipairs(obstacles) do
			if ob.Active then
				local previousZ = ob.Z
				ob.Z -= move
				if ob.Knock > 0 and ob.Knock < 0.5 then
					ob.Z += dt * 2.6 -- percuté : l'obstacle est projeté devant le coureur
				end
				if ob.Fatal and st.Mode == "Run" and ob.Z <= CHAR_Z + 0.1 then
					ob.Fatal = false
					if ob.Lane == nearestLane(st.RunnerX) and st.RunnerH < ob.Top then
						startCrash(ob)
					end
				end
				if previousZ >= CHAR_Z and ob.Z < CHAR_Z and not ob.Passed and st.Mode == "Run" then
					ob.Passed = true
					if ob.Lane == nearestLane(st.RunnerX) and st.JetTime <= 0 then
						if ob.Kind == "High" then
							eventText(Locale.T("SLIDE!"), rgb(140, 220, 255))
						elseif st.RunnerH > 12 and random:NextNumber() < 0.7 then
							eventText(Locale.T("NICE JUMP!"), rgb(130, 255, 150))
						end
					end
				end
				if ob.Z < Z_NEAR then
					ob.Active = false
					ob.Visual.Visible = false
				else
					local z = ob.Z
					local x = sx(LANES[ob.Lane], z)
					local knock = 0
					if ob.Knock > 0 then
						ob.Knock += dt
						knock = math.min(1, ob.Knock * 3)
					end
					if ob.Kind == "Cone" then
						local cones = ob.Cones
						cones.Position = UDim2.fromOffset(x, sy(0, z) - knock * 10 * U)
						cones.Size = UDim2.fromOffset(BARRIER_W * U / z, ob.Top * U / z)
						cones.ZIndex = depthZ(z)
						cones.Rotation = knock * 28
					else
						local board = ob.Board
						board.Position = UDim2.fromOffset(x, sy(ob.Bottom, z) - knock * 8 * U)
						board.Size = UDim2.fromOffset(BARRIER_W * U / z, (ob.Top - ob.Bottom) * U / z)
						board.ZIndex = depthZ(z)
						board.Rotation = knock * 22
						if ob.Kind == "High" then
							local on = math.sin(st.Clock * 7 + ob.Phase) > 0
							ob.Light.BackgroundColor3 = on and rgb(255, 70, 60) or rgb(130, 30, 34)
						end
					end
				end
			end
		end
	end

	------------------------------------------------------------------
	-- Pièces (aimant, ramassage) et bonus
	------------------------------------------------------------------
	local function updateCoins(dt: number, move: number)
		local runnerX, runnerH = st.RunnerX, st.RunnerH
		for _, coin in ipairs(coinsPool) do
			if coin.Active then
				local previousZ = coin.Z
				local collected = false
				if st.MagnetTime > 0 and not coin.Pulled and coin.Z < CHAR_Z + 2.6 and coin.Z > CHAR_Z - 0.2 then
					coin.Pulled = true
				end
				if coin.Pulled then
					-- Aimant : la pièce file vers le coureur (au lieu de défiler)
					local k = math.min(1, dt * 10)
					coin.X += (runnerX - coin.X) * k
					coin.H += (runnerH + 30 - coin.H) * k
					coin.Z += (CHAR_Z - coin.Z) * math.min(1, dt * 8)
					collected = math.abs(coin.Z - CHAR_Z) < 0.15 and math.abs(coin.X - runnerX) < 16
				else
					coin.Z -= move
				end
				if collected then
					-- déjà ramassée par l'aimant
				elseif previousZ >= CHAR_Z and coin.Z < CHAR_Z and st.Mode == "Run" then
					collected = math.abs(coin.X - runnerX) < 30 and coin.H > runnerH - 12 and coin.H < runnerH + CHAR_H + 12
				end
				local z = math.max(coin.Z, 0.3)
				local px, py = sx(coin.X, z), sy(coin.H, z)
				if collected then
					collectCoin(coin, px, py)
				elseif coin.Z < Z_NEAR then
					coin.Active = false
					coin.Frame.Visible = false
				else
					coin.Phase += dt * 6
					local size = COIN_SIZE * U / z
					local spin = math.abs(math.cos(coin.Phase))
					local f = coin.Frame
					f.Position = UDim2.fromOffset(px, py)
					f.Size = UDim2.fromOffset(size * math.max(0.14, spin), size)
					f.ZIndex = depthZ(z)
					coin.Gradient.Offset = Vector2.new(math.sin(st.Clock * 2.4 + coin.Phase * 0.3) * 0.7, 0)
				end
			end
		end

		if pickup.Active then
			local previousZ = pickup.Z
			pickup.Z -= move
			local z = math.max(pickup.Z, 0.3)
			local height = 32 + math.sin(st.Clock * 4) * 5
			local px, py = sx(LANES[pickup.Lane], z), sy(height, z)
			if previousZ >= CHAR_Z and pickup.Z < CHAR_Z and math.abs(LANES[pickup.Lane] - runnerX) < 34 and st.Mode == "Run" then
				pickup.Active = false
				pickup.Root.Visible = false
				activatePower(pickup.Kind, px, py)
			elseif pickup.Z < Z_NEAR then
				pickup.Active = false
				pickup.Root.Visible = false
			else
				local size = 28 * U / z * (1 + math.sin(st.Clock * 6) * 0.05)
				pickup.Root.Position = UDim2.fromOffset(px, py)
				pickup.Root.Size = UDim2.fromOffset(size, size)
				pickup.Root.ZIndex = depthZ(z)
				pickup.Bubble.Rotation = math.sin(st.Clock * 3) * 10
				pickup.Halo.Size = UDim2.fromScale(1.55 + math.sin(st.Clock * 5) * 0.15, 1.55 + math.sin(st.Clock * 5) * 0.15)
				pickup.Stroke.Thickness = math.max(1, size * 0.07)
			end
		end
	end

	------------------------------------------------------------------
	-- Pose et animation du coureur
	------------------------------------------------------------------
	local legAngle = { 0, 0 }
	local armLen = { ARM_LEN, ARM_LEN }
	local armAngle = { 0, 0 }
	-- Position des talons à l'écran (étincelles, poussière) : x1, y1, x2, y2
	local heels = { 0, 0, 0, 0 }

	-- Visage : se retourne de temps en temps, cligne des yeux, expressions
	local function updateFace(dt: number)
		if st.Mode == "Run" and st.LookT < 0 then
			st.LookTimer -= dt
			if st.LookTimer <= 0 and st.JumpT < 0 and st.SlideT < 0 and st.JetTime <= 0 then
				lookBack("Smile", random:NextNumber(0.8, 1.2))
			end
		end
		local turnTarget = 0
		if st.LookT >= 0 then
			st.LookT += dt
			if st.LookT >= st.LookDur then
				st.LookT = -1
			else
				turnTarget = st.LookDir * 0.8
			end
		end
		st.Turn += (turnTarget - st.Turn) * math.min(1, dt * 11)
		st.BlinkTimer -= dt
		if st.BlinkTimer <= 0 then
			st.BlinkTimer = random:NextNumber(1.4, 3.4)
			st.BlinkT = 0.13
		end
		st.BlinkT = math.max(0, st.BlinkT - dt)

		local turn = st.Turn
		local a = math.abs(turn)
		local dir = turn >= 0 and 1 or -1
		local visible = a > 0.08
		show(hero.Face, visible)
		-- l'oreille du côté du visage passe derrière la joue ; la visière tourne
		show(hero.Ears[1], not (dir < 0 and a > 0.35))
		show(hero.Ears[2], not (dir > 0 and a > 0.35))
		hero.Visor.Position = UDim2.fromScale(0.5 - turn * 0.22, 0.53)
		if not visible then
			return
		end
		hero.Face.Position = UDim2.fromScale(0.5 + dir * (0.5 - 0.3 * a), 0.66)
		hero.Face.Size = UDim2.fromScale(0.3 + 0.36 * a, 0.62)
		local expression = st.Expression
		local expr = EXPRESSIONS[expression] or EXPRESSIONS.Smile
		local featureX = 0.5 + dir * 0.2
		local blink = (st.BlinkT > 0 and (expression == "Smile" or expression == "Wow")) and 0.16 or 1
		hero.Eye.Position = UDim2.fromScale(featureX, 0.36)
		hero.Eye.Size = UDim2.fromScale(expr.Eye.X, expr.Eye.Y * blink)
		hero.Eye.Rotation = expression == "Dizzy" and 45 or (expression == "Happy" and -dir * 16 or 0)
		show(hero.EyeX, expression == "Dizzy")
		hero.EyeX.Position = UDim2.fromScale(featureX, 0.36)
		hero.Brow.Position = UDim2.fromScale(featureX - dir * 0.02, expr.Brow)
		hero.Brow.Rotation = expression == "Wow" and -dir * 12 or dir * 8
		hero.Mouth.Position = UDim2.fromScale(0.5 + dir * 0.24, expression == "Wow" and 0.8 or 0.78)
		hero.Mouth.Size = UDim2.fromScale(expr.Mouth.X, expr.Mouth.Y)
		hero.Blush.Position = UDim2.fromScale(0.5 + dir * 0.04, 0.62)
	end

	local function updateHero(dt: number)
		local running = st.Mode == "Run"
		st.RunPhase += dt * (9 + st.Speed * 1.3)
		local sinP = math.sin(st.RunPhase)
		local liftL, liftR = math.max(0, sinP), math.max(0, -sinP)
		-- Bras opposés aux jambes : pied gauche levé derrière = bras gauche en
		-- avant (raccourci) et bras droit en arrière (coude écarté)
		armLen[1] = ARM_LEN * (1 - 0.3 * liftL + 0.04 * liftR)
		armLen[2] = ARM_LEN * (1 - 0.3 * liftR + 0.04 * liftL)
		armAngle[1] = 10 + 24 * liftR - 6 * liftL
		armAngle[2] = 10 + 24 * liftL - 6 * liftR
		legAngle[1], legAngle[2] = 0, 0
		local bob = math.abs(sinP) * 2.2 * U
		local strike = 1 - math.abs(sinP) -- 1 : un pied touche le sol
		local widthMul, heightMul = 1 + 0.03 * strike, 1 - 0.035 * strike
		local rotation = st.Lean + sinP * 2.5
		local torsoShift = sinP * 0.014 -- les épaules tournent un peu
		local jet = st.JetTime > 0
		local flying = jet or st.RunnerH > JUMP_H + 8
		local onGround = st.RunnerH < 2
		local runCycle = running and not flying and st.SlideT < 0 and st.JumpT < 0

		if not running then
			-- Chute : bascule en avant puis reste assis, sonné (il vacille)
			local k = math.min(1, st.ModeT * 3.2)
			liftL, liftR = 0.7 * k, 0.5 * k
			armLen[1], armLen[2] = ARM_LEN * 0.82, ARM_LEN * 0.82
			armAngle[1], armAngle[2] = 70 * k, 70 * k
			legAngle[1], legAngle[2] = 16 * k, 16 * k
			bob = -math.sin(math.min(1, st.ModeT * 2.4) * math.pi) * 12 * U
			heightMul = 1 - 0.3 * k
			widthMul = 1 + 0.08 * k
			rotation = -18 * k + math.sin(st.Clock * 3.4) * 4 * k
			torsoShift = 0
		elseif flying then
			-- Jetpack : jambes qui pendent, bras écartés
			local dangle = math.sin(st.Clock * 4) * 0.15
			liftL, liftR = 0.25 + dangle, 0.25 - dangle
			armLen[1], armLen[2] = ARM_LEN * 0.9, ARM_LEN * 0.9
			armAngle[1], armAngle[2] = 40, 40
			legAngle[1], legAngle[2] = 6 + dangle * 24, 6 - dangle * 24
			bob = math.sin(st.Clock * 5) * 1.5 * U
			rotation = st.Lean
			torsoShift = 0
		elseif st.SlideT >= 0 then
			-- Glissade : accroupi, bras écartés pour l'équilibre
			local k = math.sin(math.pi * math.min(1, st.SlideT * 1.15))
			widthMul, heightMul = 1 + 0.14 * k, 1 - 0.44 * k
			liftL, liftR = 0.75 * k, 0.75 * k
			armLen[1], armLen[2] = ARM_LEN * 0.88, ARM_LEN * 0.88
			armAngle[1], armAngle[2] = 66 * k, 66 * k
			legAngle[1], legAngle[2] = 12 * k, 12 * k
			bob = 0
			rotation = st.Lean * 0.5
			torsoShift = 0
		elseif st.JumpT >= 0 then
			-- Saut : étiré au décollage, puis une figure (groupé, vrille ou étoile)
			local t = st.JumpT
			bob = 0
			torsoShift = 0
			rotation = st.Lean
			if st.Trick == 2 then
				local k = math.sin(math.pi * math.min(1, t * 1.2))
				liftL, liftR = 0.15, 0.15
				armLen[1], armLen[2] = ARM_LEN, ARM_LEN
				armAngle[1], armAngle[2] = 30 + 100 * k, 30 + 100 * k
				legAngle[1], legAngle[2] = 28 * k, 28 * k
			else
				liftL, liftR = 0.55, 0.45
				armLen[1], armLen[2] = ARM_LEN * 0.86, ARM_LEN * 0.86
				armAngle[1], armAngle[2] = st.Trick == 1 and 24 or 128, st.Trick == 1 and 24 or 128
				if st.Trick == 1 then
					rotation = st.Lean + 360 * smooth((t - 0.08) / 0.78) * st.TrickDir
				end
			end
			if t < 0.2 then
				heightMul = 1 + 0.1 * math.sin(t / 0.2 * math.pi)
				widthMul = 1 - 0.06 * math.sin(t / 0.2 * math.pi)
			end
		end
		if st.LandT > 0 and running then
			-- Écrasement à l'atterrissage
			local k = st.LandT / 0.16
			heightMul *= 1 - 0.14 * k
			widthMul *= 1 + 0.1 * k
		end

		local rootW, rootH = CW * widthMul, CH * heightMul
		local tier = shoeTier
		local shoeH = SHOE_H * (tier.High and 1.3 or 1)
		for index, leg in ipairs(hero.Legs) do
			local lift = index == 1 and liftL or liftR
			local len = LEG_LEN * (1 - 0.42 * lift)
			local hipY = LEG_TOP - 0.03 * lift
			local hipX = leg.X + torsoShift * 0.4
			local rot = -leg.Side * legAngle[index]
			leg.Pivot.Position = UDim2.fromScale(hipX, hipY)
			leg.Pivot.Size = UDim2.fromScale(0.2, len * 2)
			leg.Pivot.Rotation = rot
			-- bout de la jambe (rotation en pixels, puis retour à l'échelle du cadre)
			local rad = math.rad(rot)
			local footX = hipX - math.sin(rad) * len * rootH / rootW
			local footY = hipY + math.cos(rad) * len
			local shoe = hero.Shoes[index]
			shoe.Lift = lift
			shoe.Root.Position = UDim2.fromScale(footX, footY + SHOE_H * 0.7 - shoeH * 0.5)
			shoe.Root.Rotation = rot + leg.Side * lift * 12
			-- pied qui part en arrière : on voit la semelle (néon aux niveaux 5+)
			shoe.Sole.Size = UDim2.fromScale(1.06, 0.28 + 0.6 * lift)
			heels[index * 2 - 1] = footX
			heels[index * 2] = footY + SHOE_H * 0.7
		end
		for index, arm in ipairs(hero.Arms) do
			arm.Pivot.Position = UDim2.fromScale(arm.X + torsoShift, 0.325)
			arm.Pivot.Size = UDim2.fromScale(0.17, armLen[index] * 2)
			arm.Pivot.Rotation = -arm.Side * armAngle[index]
		end
		hero.Torso.Position = UDim2.fromScale(0.5 + torsoShift, 0.265)
		hero.Head.Position = UDim2.fromScale(0.5 + torsoShift * 0.5, math.abs(sinP) * 0.008)
		-- la tête reste plus droite que le corps (sauf pendant une vrille)
		hero.Head.Rotation = (st.Trick == 1 and st.JumpT >= 0) and 0 or -(rotation - st.Lean) * 0.5 - st.Lean * 0.3

		-- Sac à dos et capuche : ressort (rebond à l'atterrissage, léger
		-- balancement pendant la course)
		st.PackV += (-260 * st.PackY - 13 * st.PackV) * dt
		st.PackY += st.PackV * dt
		local packOffset = math.clamp(st.PackY, -0.05, 0.05) + (runCycle and math.cos(st.RunPhase * 2 + 0.9) * 0.012 or 0)
		hero.Pack.Position = UDim2.fromScale(0.5 + torsoShift * 1.3, 0.355 + packOffset)
		hero.Hood.Position = UDim2.fromScale(0.5, -0.06 + packOffset * 0.7)
		-- Porte-clés : pendule (virages, foulées)
		local accel = (st.VX - st.LastVX) / dt
		st.LastVX = st.VX
		local drive = math.clamp(accel * 0.0025, -30, 30) + (runCycle and math.cos(st.RunPhase) * 5 or 0)
		st.CharmV += (-80 * st.CharmA - 4 * st.CharmV + drive) * dt
		st.CharmA = math.clamp(st.CharmA + st.CharmV * dt, -1.1, 1.1)
		hero.Charm.Rotation = math.deg(st.CharmA)

		local heroScreenX = sx(st.RunnerX, CHAR_Z)
		local heroY = sy(st.RunnerH, CHAR_Z) - bob
		local root = hero.Root
		root.Position = UDim2.fromOffset(heroScreenX, heroY)
		root.Size = UDim2.fromOffset(rootW, rootH)
		root.Rotation = rotation
		local top = heroY - rootH
		for i = 1, 2 do
			heels[i * 2 - 1] = heroScreenX + (heels[i * 2 - 1] - 0.5) * rootW
			heels[i * 2] = top + heels[i * 2] * rootH
		end

		local groundY = sy(0, CHAR_Z)
		local shadowScale = 1 - math.clamp(st.RunnerH / 150, 0, 0.6)
		hero.Shadow.Position = UDim2.fromOffset(heroScreenX, groundY)
		hero.Shadow.Size = UDim2.fromOffset(32 * U * shadowScale * widthMul, 7 * U * shadowScale)
		hero.Shadow.BackgroundTransparency = 0.6 + math.clamp(st.RunnerH / 100, 0, 1) * 0.25

		-- Baskets : halo, ailes qui battent, flammes qui vacillent
		if tier.Glow then
			local k = 1 - math.clamp(st.RunnerH / 90, 0, 0.75)
			hero.UnderGlow.Position = UDim2.fromOffset(heroScreenX, groundY)
			hero.UnderGlow.Size = UDim2.fromOffset(46 * U * k, 13 * U * k)
			hero.UnderGlow.BackgroundTransparency = 0.35 + 0.12 * math.sin(st.Clock * 5) + (1 - k) * 0.4
		end
		local flameLevel = tier.Flame or 0
		for index, shoe in ipairs(hero.Shoes) do
			if tier.Glow then
				shoe.Glow.BackgroundTransparency = 0.5 + 0.14 * math.sin(st.Clock * 7 + index * 2)
			end
			if tier.Wings then
				local flap = math.sin(st.Clock * (running and 17 or 5) + index * 1.3)
				shoe.Wing.Rotation = -shoe.Side * (6 + flap * 24)
			end
			if flameLevel > 0 then
				local boost = (not onGround or (shoe.Lift or 0) > 0.3) and 1.35 or 0.85
				local len = (flameLevel > 1 and 1.55 or 1.1) * boost * random:NextNumber(0.8, 1.15)
				shoe.Flame.Size = UDim2.fromScale(flameLevel > 1 and 0.8 or 0.62, len)
				if flameLevel > 1 then
					shoe.Core.Size = UDim2.fromScale(0.34, len * 0.55)
				end
			end
		end

		-- Jetpack : le sac devient un réacteur
		if jet ~= st.JetShown then
			st.JetShown = jet
			tint(hero.Pack, jet and JET or PACK)
			tint(hero.Pocket, jet and JET_DARK or PACK_DARK)
			tint(hero.Flap, jet and JET_DARK or PACK_DARK)
			for _, flame in ipairs(hero.Flames) do
				flame.Visible = jet
			end
		end
		if jet then
			for _, flame in ipairs(hero.Flames) do
				flame.Size = UDim2.fromScale(0.3, 0.55 + random:NextNumber() * 0.45)
			end
		end

		-- Aimant : halo qui pulse autour du coureur
		if st.MagnetTime > 0 and running then
			local size = CH * (1.25 + math.sin(st.Clock * 8) * 0.08)
			show(hero.Aura, true)
			hero.Aura.Position = UDim2.fromOffset(heroScreenX, heroY - CH * 0.5)
			hero.Aura.Size = UDim2.fromOffset(size, size)
			hero.AuraStroke.Transparency = st.MagnetTime < 1.5 and ((math.sin(st.Clock * 20) > 0) and 0.2 or 0.8) or 0.2
		else
			show(hero.Aura, false)
		end

		-- Anneau "nouvelles baskets" qui s'élargit autour des pieds
		if st.ShoeFlash > 0 then
			st.ShoeFlash = math.max(0, st.ShoeFlash - dt / 0.8)
			local k = 1 - st.ShoeFlash
			hero.ShoeRing.Visible = st.ShoeFlash > 0
			hero.ShoeRing.Position = UDim2.fromOffset(heroScreenX, groundY)
			hero.ShoeRing.Size = UDim2.fromOffset((18 + 80 * k) * U, (6 + 22 * k) * U)
			hero.ShoeRingStroke.Transparency = k * k
		end

		-- Bulle d'émoji (pop, flotte, disparaît)
		if hero.Emote.Visible then
			st.EmoteT += dt
			local t = st.EmoteT
			if t >= st.EmoteDur then
				hero.Emote.Visible = false
			else
				local scale = 1
				if t < 0.2 then
					scale = 0.3 + 0.7 * math.sin(t / 0.2 * math.pi * 0.5) + 0.25 * math.sin(t / 0.2 * math.pi)
				elseif t > st.EmoteDur - 0.15 then
					scale = (st.EmoteDur - t) / 0.15
				end
				hero.EmoteScale.Scale = math.max(0.05, scale)
				-- à gauche de la tête (les "+1" des pièces montent à droite)
				local sideSign = st.Turn > 0.1 and 1 or -1
				hero.Emote.Position = UDim2.fromOffset(heroScreenX + sideSign * 15 * U, top - 1 * U + math.sin(t * 5) * 1.2 * U)
			end
		end
		-- Étoiles qui tournent autour de la tête quand il est sonné
		local dizzy = not running and st.ModeT > 0.3
		for _, star in ipairs(hero.DizzyStars) do
			if star.Frame.Visible ~= dizzy then
				star.Frame.Visible = dizzy
			end
			if dizzy then
				local angle = st.Clock * 5 + star.Phase
				star.Frame.Position = UDim2.fromOffset(heroScreenX + math.cos(angle) * 12 * U, top + 2 * U + math.sin(angle) * 3.5 * U)
				star.Frame.Rotation = math.deg(angle) * 1.5
			end
		end

		updateFace(dt)

		-- Poussière (et étincelles des baskets) à chaque foulée ; en continu
		-- pendant une glissade
		if running and onGround and not flying then
			local level = math.max(0, st.ShoeLevel)
			if st.SlideT >= 0 then
				st.DustTimer -= dt
				if st.DustTimer <= 0 then
					st.DustTimer = 0.05
					spawnDust(heroScreenX + random:NextNumber(-8, 8) * U, groundY, random:NextNumber(-30, 30) * U, 18 * U, 6 * U, 0.45)
				end
			else
				local step = math.floor(st.RunPhase / math.pi)
				if step ~= st.LastStep then
					st.LastStep = step
					local side = (step % 2 == 0) and -1 or 1
					local size = (4 + level * 0.4) * U
					spawnDust(heroScreenX + side * 6 * U, groundY - 1 * U, side * (12 + level) * U, 14 * U, size, 0.35 + level * 0.012)
					if level >= 3 then
						spawnDust(heroScreenX - side * 3 * U, groundY, -side * 8 * U, 18 * U, size * 0.7, 0.3)
					end
					if tier.Glow then
						spawnDust(heroScreenX + side * 5 * U, groundY, side * 22 * U, 8 * U, size * 0.8, 0.3, tier.Glow)
					end
				end
			end
		end
	end

	------------------------------------------------------------------
	-- Effets (lignes de vitesse, poussière, étincelles, textes)
	------------------------------------------------------------------
	-- Traînée lumineuse des baskets : points posés au sol (ou en l'air) tous
	-- les RIBBON_DZ de défilement, qui se rapprochent de la caméra
	local function updateTrail(fxOn: boolean)
		local on = fxOn and shoeTrail ~= nil and st.Mode == "Run" and st.JetTime <= 0 and st.RunnerH < JUMP_H + 20
		if not on then
			if st.RibbonsShown then
				st.RibbonsShown = false
				for _, ribbon in ipairs(ribbons) do
					for _, segment in ipairs(ribbon.Segments) do
						show(segment, false)
					end
				end
			end
			st.RibbonReset = true
			return
		end
		local trail = shoeTrail
		local reset = st.RibbonReset
		st.RibbonReset = false
		local drop = st.Scroll - st.RibbonDrop >= RIBBON_DZ
		if drop or reset then
			st.RibbonDrop = st.Scroll
		end
		st.RibbonsShown = true
		local footH = math.max(0, st.RunnerH) + 3
		for index, ribbon in ipairs(ribbons) do
			local footX = st.RunnerX + (index == 1 and -7 or 7)
			local points = ribbon.Points
			if reset then
				for k = 0, RIBBON_SEGMENTS do
					local p = points[k]
					p.X, p.H, p.Scroll = footX, footH, st.Scroll
				end
			elseif drop then
				for k = RIBBON_SEGMENTS, 2, -1 do
					local p, q = points[k], points[k - 1]
					p.X, p.H, p.Scroll = q.X, q.H, q.Scroll
				end
				local p1 = points[1]
				p1.X, p1.H, p1.Scroll = footX, footH, st.Scroll
			end
			local p0 = points[0]
			p0.X, p0.H, p0.Scroll = footX, footH, st.Scroll
			for k, segment in ipairs(ribbon.Segments) do
				local a, b = points[k - 1], points[k]
				local za = math.max(0.5, CHAR_Z - (st.Scroll - a.Scroll))
				local zb = math.max(0.5, CHAR_Z - (st.Scroll - b.Scroll))
				local pa = Vector2.new(sx(a.X, za), sy(a.H, za))
				local pb = Vector2.new(sx(b.X, zb), sy(b.H, zb))
				if (pb - pa).Magnitude < 0.8 then
					show(segment, false)
				else
					show(segment, true)
					setLine(segment, pa, pb, math.max(1, trail.Width * U / ((za + zb) / 2)))
				end
			end
		end
	end

	-- Étincelles / plumes / braises qui s'échappent des talons (niveaux 5+)
	local function updateShoeFx(dt: number, fxOn: boolean)
		local tier = shoeTier
		local level = st.ShoeLevel
		if fxOn and st.Mode == "Run" and level >= 5 then
			local rate = level >= 10 and 16 or (level >= 9 and 12 or (level >= 7 and 6 or 3))
			st.ShoeFxTimer -= dt
			if st.ShoeFxTimer <= 0 then
				st.ShoeFxTimer = 1 / rate
				local i = random:NextInteger(1, 2)
				local x, y = heels[i * 2 - 1], heels[i * 2]
				local color, size, vx, vy, life
				if level >= 10 then
					color = (random:NextNumber() < 0.5) and rgb(255, 220, 90) or rgb(255, 110, 30)
					size, vx, vy, life = random:NextNumber(2, 3.5) * U, random:NextNumber(-25, 25) * U, random:NextNumber(20, 60) * U, 0.45
				elseif level >= 9 then
					color = (random:NextNumber() < 0.6) and rgb(170, 226, 255) or WHITE
					size, vx, vy, life = random:NextNumber(2, 3) * U, random:NextNumber(-20, 20) * U, random:NextNumber(30, 60) * U, 0.35
				elseif level >= 7 then
					-- plumes (niveaux 7-8) : tombent en tournoyant
					color = tier.Wings or WHITE
					size, vx, vy, life = random:NextNumber(2.5, 3.5) * U, random:NextNumber(-18, 18) * U, random:NextNumber(10, 26) * U, 0.7
				else
					color = tier.Glow or WHITE
					size, vx, vy, life = random:NextNumber(1.8, 2.8) * U, random:NextNumber(-16, 16) * U, random:NextNumber(12, 30) * U, 0.4
				end
				spawnShoeFx(x, y, color, size, vx, vy, life)
			end
		end
		for _, fx in ipairs(shoeFx) do
			if fx.Life > 0 then
				fx.Life -= dt
				local f = fx.Frame
				if fx.Life <= 0 then
					f.Visible = false
				else
					local t = fx.Life / fx.MaxLife
					fx.X += fx.VX * dt
					fx.Y += fx.VY * dt
					local size = fx.Size * (0.5 + 0.5 * t)
					f.Position = UDim2.fromOffset(fx.X, fx.Y)
					f.Size = UDim2.fromOffset(size, size * (level >= 7 and level <= 8 and 0.55 or 1))
					f.Rotation += fx.Spin * dt
					f.BackgroundTransparency = 1 - t
				end
			end
		end
	end

	-- Pièces qui filent vers le compteur (arc, puis le compteur pulse)
	local function updateFlyers(dt: number)
		for _, flyer in ipairs(flyers) do
			if flyer.T < 1 then
				flyer.T = math.min(1, flyer.T + dt / 0.45)
				local t = flyer.T
				local e = t * t
				local p = flyer.From:Lerp(HUD_COIN, e) - Vector2.new(0, math.sin(t * math.pi) * 16 * U)
				local size = flyer.Size + (13 * U - flyer.Size) * e
				flyer.Frame.Position = UDim2.fromOffset(p.X, p.Y)
				flyer.Frame.Size = UDim2.fromOffset(size, size)
				if t >= 1 then
					flyer.Frame.Visible = false
					st.CoinPulse = 1
				end
			end
		end
	end

	local function updateFx(dt: number, fxOn: boolean)
		local wanted = 0
		if fxOn and st.Mode == "Run" then
			wanted = st.JetTime > 0 and 1 or math.clamp((st.Speed - 4.3) / 0.5, 0, 1) * 0.45
			-- les meilleures baskets donnent une impression de vitesse
			wanted = math.max(wanted, math.max(0, st.ShoeLevel - 4) * 0.055)
		end
		st.LineStrength += (wanted - st.LineStrength) * math.min(1, dt * 3)
		if st.LineStrength > 0.02 then
			st.LinesVisible = true
			for _, line in ipairs(speedLines) do
				line.R += line.Speed * dt * (st.JetTime > 0 and 1.4 or 1)
				if line.R > 210 * U then
					resetSpeedLine(line)
				end
				local length = 8 * U + line.R * 0.3
				local dirX, dirY = math.cos(line.Angle), math.sin(line.Angle)
				local r = line.R + length / 2
				local f = line.Frame
				f.Visible = true
				f.Position = UDim2.fromOffset(CX + dirX * r, HY + dirY * r)
				f.Size = UDim2.fromOffset(length, math.max(1, 1.5 * U))
				f.Rotation = math.deg(line.Angle)
				local appear = math.clamp((line.R - 14 * U) / (30 * U), 0, 1)
				f.BackgroundTransparency = 1 - st.LineStrength * appear * 0.7
			end
		elseif st.LinesVisible then
			st.LinesVisible = false
			for _, line in ipairs(speedLines) do
				line.Frame.Visible = false
			end
		end

		for _, dust in ipairs(dusts) do
			if dust.Life > 0 then
				dust.Life -= dt
				local f = dust.Frame
				if dust.Life <= 0 then
					f.Visible = false
				else
					local t = 1 - dust.Life / dust.MaxLife
					dust.X += dust.VX * dt
					dust.Y += dust.VY * dt
					local size = dust.Size * (0.6 + t * 1.4)
					f.Position = UDim2.fromOffset(dust.X, dust.Y)
					f.Size = UDim2.fromOffset(size, size * 0.8)
					f.BackgroundTransparency = 0.35 + t * 0.65
				end
			end
		end

		for _, sparkle in ipairs(sparkles) do
			if sparkle.Life > 0 then
				sparkle.Life -= dt
				local f = sparkle.Frame
				if sparkle.Life <= 0 then
					f.Visible = false
				else
					sparkle.VY += 140 * U * dt
					sparkle.X += sparkle.VX * dt
					sparkle.Y += sparkle.VY * dt
					local t = sparkle.Life / 0.45
					local size = 6 * U * (0.4 + 0.6 * t)
					f.Position = UDim2.fromOffset(sparkle.X, sparkle.Y)
					f.Size = UDim2.fromOffset(size, size)
					f.Rotation = 45 + (1 - t) * 180
					f.BackgroundTransparency = 1 - t
				end
			end
		end

		for _, pop in ipairs(pops) do
			if pop.Life > 0 then
				pop.Life -= dt
				local label = pop.Label
				if pop.Life <= 0 then
					label.Visible = false
				else
					pop.Y -= pop.Rise * U * dt
					local age = pop.MaxLife - pop.Life
					local grow = 1 + 0.45 * math.clamp(1 - age / 0.15, 0, 1)
					local t = pop.Life < 0.25 and (1 - pop.Life / 0.25) or 0
					label.Position = UDim2.fromOffset(pop.X, pop.Y)
					label.Size = UDim2.fromOffset(pop.W * grow, pop.H * grow)
					label.TextTransparency = t
					pop.Stroke.Transparency = t
				end
			end
		end
	end

	------------------------------------------------------------------
	-- HUD
	------------------------------------------------------------------
	local function setPower(slot, icon: string, color: Color3, ratio: number)
		slot.Pill.Visible = true
		slot.Icon.Text = icon
		slot.Fill.BackgroundColor3 = color
		slot.Fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	end

	local function updateHud(dt: number)
		if st.Coins ~= st.ShownCoins then
			st.ShownCoins = st.Coins
			hud.CoinLabel.Text = withSpaces(st.Coins)
		end
		local meters = math.floor(st.Distance)
		if meters ~= st.ShownDistance then
			st.ShownDistance = meters
			hud.DistLabel.Text = withSpaces(meters) .. " m"
			-- Record : celui de la session, ou la course en cours si elle le bat
			local best = st.BestBeaten and meters or sessionBest
			if best ~= st.ShownBest then
				st.ShownBest = best
				hud.BestLabel.Visible = best > 0
				hud.BestLabel.Text = Locale.T("BEST") .. " " .. withSpaces(best) .. " m"
			end
		end
		-- Nouveau record en pleine course
		if not st.BestBeaten and sessionBest > 0 and meters > sessionBest and st.Mode == "Run" then
			st.BestBeaten = true
			eventText(Locale.T("NEW BEST!"), rgb(255, 220, 90))
			hud.DistLabel.TextColor3 = rgb(255, 224, 110)
			if hud.DistStroke then
				hud.DistStroke.Color = GOLD
				hud.DistStroke.Transparency = 0.1
			end
		elseif not st.BestBeaten and hud.DistLabel.TextColor3 ~= WHITE then
			hud.DistLabel.TextColor3 = WHITE
			if hud.DistStroke then
				hud.DistStroke.Color = WHITE
				hud.DistStroke.Transparency = 0.6
			end
		end
		if st.CoinPulse > 0 then
			st.CoinPulse = math.max(0, st.CoinPulse - dt * 5)
			hud.CoinScale.Scale = hudBoost * (1 + 0.16 * st.CoinPulse)
		end
		hud.DoubleBadge.Visible = st.DoubleTime > 0
		-- Badge des baskets : rebondit quand le niveau change
		if st.ShoePulse > 0 then
			st.ShoePulse = math.max(0, st.ShoePulse - dt / 0.9)
			local k = 1 - st.ShoePulse
			hud.ShoeScale.Scale = hudBoost * (1 + 0.4 * math.sin(k * math.pi) * (1 - k * 0.5))
		end

		-- Combo (à partir de 5 pièces d'affilée)
		local comboOn = st.Combo >= 5 and st.Clock - st.LastCoin < COMBO_WINDOW + 0.4 and st.Mode == "Run"
		if comboOn then
			hud.ComboPill.Visible = true
			if st.Combo ~= st.ShownCombo then
				st.ShownCombo = st.Combo
				hud.ComboLabel.Text = Locale.T("COMBO x%d", st.Combo)
				hud.ComboLabel.TextColor3 = st.Combo >= 10 and rgb(255, 140, 60) or GOLD
			end
			st.ComboPulse = math.max(0, st.ComboPulse - dt * 4)
			hud.ComboScale.Scale = 1 + 0.18 * st.ComboPulse
		elseif hud.ComboPill.Visible then
			hud.ComboPill.Visible = false
		end

		-- Jauge du bonus en cours (jetpack, sinon aimant, sinon x2 ; le x2 a aussi son badge)
		if st.JetTime > 0 then
			setPower(hud.Power, "🚀", rgb(80, 200, 255), st.JetTime / JET_TIME)
		elseif st.MagnetTime > 0 then
			setPower(hud.Power, "🧲", rgb(255, 90, 170), st.MagnetTime / MAGNET_TIME)
		elseif st.DoubleTime > 0 then
			setPower(hud.Power, "x2", rgb(255, 196, 40), st.DoubleTime / DOUBLE_TIME)
		elseif hud.Power.Pill.Visible then
			hud.Power.Pill.Visible = false
		end
	end

	------------------------------------------------------------------
	-- Téléphone : la carte est très réduite (échelle du slot ~0,4) ; les
	-- pastilles principales (pièces, distance, baskets) sont agrandies pour
	-- rester lisibles, la ligne du dessous (bonus, combo, record) descend
	------------------------------------------------------------------
	local function applyHudBoost()
		if container:GetAttribute("SlotAnimating") then
			return -- apparition "pop" en cours : taille pas encore définitive
		end
		-- échelle réelle à l'écran (toile de l'interface x échelle du slot)
		local scale = screen.AbsoluteSize.X / math.max(1, SW)
		if scale <= 0 then
			return
		end
		local boost = math.clamp(0.55 / scale, 1, 1.3)
		if math.abs(boost - hudBoost) < 0.01 then
			return
		end
		hudBoost = boost
		hud.CoinScale.Scale = boost
		hud.DistScale.Scale = boost
		hud.ShoeScale.Scale = boost
		local row = (6 + 21 * boost + 4) * U -- sous les pastilles agrandies
		hud.Power.Pill.Position = UDim2.fromOffset(6 * U, row)
		hud.BestLabel.Position = UDim2.new(1, -10 * U, 0, row - 3 * U)
		hud.ComboPill.Position = boost > 1.05 and UDim2.new(0.5, 0, 0, row) or UDim2.new(0.5, 0, 0, 6 * U)
	end
	applyHudBoost()

	------------------------------------------------------------------
	-- Boucle principale
	------------------------------------------------------------------
	ctx.OnRender(function(rawDt: number)
		-- Pause quand la carte n'est pas visible (vérifié 2 fois par seconde)
		st.VisibleCheck -= rawDt
		if st.VisibleCheck <= 0 then
			st.VisibleCheck = 0.5
			st.Visible = computeVisible()
			applyHudBoost()
		end
		if not st.Visible then
			return
		end

		local dt = math.clamp(rawDt, 1 / 240, 1 / 20)
		st.Clock += dt
		st.DayTime += dt
		st.ModeT += dt
		st.EventCooldown = math.max(0, st.EventCooldown - dt)
		local fxOn = effectsOn()
		local running = st.Mode == "Run"

		st.LightTimer -= dt
		if st.LightTimer <= 0 then
			st.LightTimer = 0.2
			updateLighting()
		end

		-- Décor d'ambiance : 30 images/s au plus
		st.AmbientT += dt
		if st.AmbientT >= AMBIENT_STEP then
			updateAmbient(st.AmbientT)
			st.AmbientT = 0
		end

		-- Nouvelles baskets achetées pendant que la carte était cachée : fête maintenant
		if st.PendingCelebrate and running then
			st.PendingCelebrate = false
			celebrateShoes()
		end

		-- Vitesse (accélère doucement, plus vite en jetpack et avec de
		-- meilleures baskets, s'arrête après une chute)
		if running then
			st.RunTime += dt
			local shoeBoost = 1 + SHOE_SPEED * math.max(0, st.ShoeLevel)
			local baseSpeed = math.min(MAX_SPEED, BASE_SPEED + st.RunTime * SPEED_RAMP) * shoeBoost
			local wantedSpeed = st.JetTime > 0 and baseSpeed * 1.3 or baseSpeed
			st.Speed += (wantedSpeed - st.Speed) * math.min(1, dt * 2)
		else
			st.Speed += (0 - st.Speed) * math.min(1, dt * 7)
		end
		local move = st.Speed * dt
		st.Scroll += move
		if running then
			st.Distance += move * 6
		end

		-- Bonus
		st.JetTime = math.max(0, st.JetTime - dt)
		st.MagnetTime = math.max(0, st.MagnetTime - dt)
		st.DoubleTime = math.max(0, st.DoubleTime - dt)
		if running and st.JetTime <= 0 and st.MagnetTime <= 0 and not st.PendingPower and not pickup.Active then
			st.PowerTimer -= dt
			if st.PowerTimer <= 0 then
				local roll = random:NextNumber()
				st.PendingPower = (roll < 0.38) and "Magnet" or (roll < 0.72 and "Double" or "Jetpack")
				st.PowerTimer = random:NextNumber(14, 22)
			end
		end
		-- Au bout d'un moment, le coureur finira par rater un obstacle
		if running and not st.CrashPending and st.RunTime > st.RunLength and st.JetTime <= 0 then
			st.CrashPending = true
		end

		-- Nouvelles vagues
		if running then
			st.WaveDistance += move
			if st.WaveDistance >= WAVE_GAP then
				st.WaveDistance -= WAVE_GAP
				spawnWave(Z_FAR)
			end
			-- Pièces dans le ciel pendant le jetpack
			if st.JetTime > 1.6 then
				st.AirDistance += move
				if st.AirDistance >= 0.5 then
					st.AirDistance -= 0.5
					st.AirCount += 1
					if st.AirCount % 5 == 0 then
						st.AirLane = math.clamp(st.AirLane + ((random:NextNumber() < 0.5) and -1 or 1), 1, 3)
					end
					spawnCoin(st.AirLane, Z_FAR, JET_H + 28, true)
				end
			end
		end

		--------------------------------------------------------------
		-- Le coureur : voie, sauts, glissades
		--------------------------------------------------------------
		if running then
			st.WishTimer -= dt
			if st.WishTimer <= 0 then
				st.WishLane = random:NextInteger(1, 3)
				st.WishTimer = random:NextNumber(1.5, 3.5)
			end
			if st.JetTime > 0.9 then
				-- En vol : suit la traînée de pièces
				local nearest: any, nearestZ = nil, math.huge
				for _, coin in ipairs(coinsPool) do
					if coin.Active and coin.Air and coin.Z > CHAR_Z and coin.Z < nearestZ then
						nearest, nearestZ = coin, coin.Z
					end
				end
				if nearest then
					setLane(nearest.Lane)
				end
			elseif math.abs(st.RunnerX - LANES[st.TargetLane]) < 10 then
				chooseLane()
			end
		end

		local previousX = st.RunnerX
		st.RunnerX += (LANES[st.TargetLane] - st.RunnerX) * math.min(1, dt * 11)
		local vx = (st.RunnerX - previousX) / dt
		st.VX = vx
		st.Lean += (math.clamp(vx * 0.06, -15, 15) - st.Lean) * math.min(1, dt * 12)

		-- Sauts / glissades automatiques devant les obstacles
		if running and st.JetTime <= 0 and st.RunnerH < 60 then
			local myLane = nearestLane(st.RunnerX)
			for _, ob in ipairs(obstacles) do
				if ob.Active and not ob.Handled and ob.Lane == myLane then
					local timeTo = (ob.Z - CHAR_Z) / st.Speed
					if timeTo > 0 and timeTo < 0.27 then
						ob.Handled = true
						if st.CrashPending and ob.Kind ~= "High" and st.MagnetTime <= 0 then
							ob.Fatal = true -- raté !
						elseif ob.Kind == "High" then
							st.SlideT = 0
							st.JumpT = -1
						elseif st.JumpT < 0 then
							st.JumpT = 0
							st.SlideT = -1
							-- une figure de temps en temps (vrille, étoile)
							local roll = random:NextNumber()
							st.Trick = (roll < 0.55) and 0 or (roll < 0.8 and 1 or 2)
							st.TrickDir = (random:NextNumber() < 0.5) and -1 or 1
							st.PackV += 0.35
						end
					end
				end
			end
		end
		if st.JumpT >= 0 then
			st.JumpT += dt / JUMP_TIME
			if st.JumpT >= 1 then
				st.JumpT = -1
				st.LandT = 0.16
				st.PackV += 0.55 -- le sac retombe et rebondit
				local x, y = sx(st.RunnerX, CHAR_Z), sy(0, CHAR_Z)
				spawnDust(x - 6 * U, y, -26 * U, 6 * U, 6 * U, 0.4)
				spawnDust(x + 6 * U, y, 26 * U, 6 * U, 6 * U, 0.4)
			end
		end
		if st.SlideT >= 0 then
			st.SlideT += dt / SLIDE_TIME
			if st.SlideT >= 1 then
				st.SlideT = -1
			end
		end
		st.LandT = math.max(0, st.LandT - dt)

		local heightTarget = 0
		if st.JetTime > 0 then
			heightTarget = JET_H
		elseif st.JumpT >= 0 then
			heightTarget = 4 * JUMP_H * st.JumpT * (1 - st.JumpT)
		end
		local slow = st.JetTime > 0 or (st.JumpT < 0 and st.RunnerH > JUMP_H + 8)
		st.RunnerH += (heightTarget - st.RunnerH) * math.min(1, dt * (slow and 4 or 30))

		-- Caméra : suit un peu le coureur (parallaxe)
		camX += (st.RunnerX * 0.42 - camX) * math.min(1, dt * 5)
		if math.abs(camX - st.LastStaticCam) > 0.03 then
			st.LastStaticCam = camX
			updateStatic()
		end

		updateScenery(dt, move)
		updateTrains(dt, move)
		updateObstacles(dt, move)
		updateCoins(dt, move)
		updateHero(dt)
		updateTrail(fxOn)
		updateShoeFx(dt, fxOn)
		updateFx(dt, fxOn)
		updateFlyers(dt)
		updateHud(dt)

		-- Secousse lors d'une chute
		if st.ShakeT > 0 then
			st.ShakeT = math.max(0, st.ShakeT - dt)
			local k = st.ShakeT / 0.35 * 3 * U
			scene.Position = UDim2.fromOffset(random:NextNumber(-k, k), random:NextNumber(-k, k))
		elseif scene.Position ~= UDim2.new() then
			scene.Position = UDim2.new()
		end

		-- Fin de course : résultats, fondu, nouvelle partie
		if st.Mode == "Crash" then
			local t = st.ModeT
			if t >= 1.25 then
				hud.Results.Visible = true
				local k = math.clamp((t - 1.25) / 0.25, 0, 1)
				hud.ResultsScale.Scale = 0.6 + 0.4 * (1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2)
				if st.NewBest then
					hud.ResultsBest.Rotation = math.sin(st.Clock * 6) * 4
				end
				-- bouton "Rejouer" : respire, puis s'enfonce tout seul
				if t < 3.6 then
					hud.ReplayScale.Scale = 1 + 0.05 * math.sin(st.Clock * 7)
				elseif t < 3.75 then
					hud.ReplayScale.Scale = 0.86
				else
					hud.ReplayScale.Scale = 1.06
				end
			end
			if t >= 3.95 then
				st.FadeT = math.clamp((t - 3.95) / 0.3, 0, 1)
				if t >= 4.25 then
					resetRun()
					st.FadeT = 1
				end
			end
		elseif st.FadeT > 0 then
			st.FadeT = math.max(0, st.FadeT - dt / 0.35)
		end
		if st.FadeT > 0 then
			hud.Fade.Visible = true
			hud.Fade.BackgroundTransparency = 1 - st.FadeT
		elseif hud.Fade.Visible then
			hud.Fade.Visible = false
		end
	end)
end

function Runner.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Runner
