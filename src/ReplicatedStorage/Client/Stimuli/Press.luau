--[[
	Press (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Press

	Une vraie petite chaîne d'écrasement, en boucle, très satisfaisante :
	  - un tapis roulant (bande qui défile, rouleaux qui tournent, pieds)
	    amène les objets un par un sous la presse ; la file d'attente est
	    variée (macarons, canette, pastèque, gâteau, cadeau, gelée, éponge,
	    Rubik's cube, canard, ballon, pot de peinture... + objets propres au
	    palier), tous DESSINÉS en Frames : ils se déforment vraiment ;
	  - la presse : deux colonnes ombrées façon métal, traverse avec bande
	    d'accent et boulons, vérin (chemise + tige chromée), plateau guidé
	    par les colonnes, enclume ; centrale hydraulique à gauche (moteur,
	    réservoir avec voyant d'huile), deux flexibles jusqu'au vérin,
	    manomètres gradués (aiguille qui grimpe dans le rouge) ;
	  - le cycle : chargement (le tapis avance), descente, compression (l'objet
	    se tasse et s'élargit en tremblant), CRUNCH (écrasement avec rebond,
	    onde de choc, éclats, étincelles, vapeur, poussière, secousse de la
	    MACHINE seulement : la carte et son contour ne bougent pas), remontée,
	    et la galette repart sur le tapis vers le bac à gauche.

	10 paliers visuels, un par niveau de "Presse hydraulique" (ctx.GetLevel("Press")) :
	  1 bois rustique, 2 chêne & fer, 3 acier, 4 acier bleu, 5 industrielle
	  (gyrophare, vapeur), 6 usine (afficheur numérique), 7 or, 8 or royal
	  (rubis), 9 diamant (cristaux), 10 diamant néon (contours arc-en-ciel).
	Pastille "Niv. X · palier" + animation au changement de palier. La
	vitesse augmente avec le niveau.

	"Presse turbo" (Feature PressStart) : pupitre avec un gros bouton START
	(Interact("Press"), recharge côté serveur, jauge de recharge affichée) ;
	le bonus s'affiche via OnBonus("Press"). Sans turbo : panneau "Attention
	aux doigts".

	Performance : une seule boucle OnRender ; particules, bouffées de vapeur
	et cris "CRUNCH!" viennent de réserves réutilisées (aucune création
	d'instance par image) ; rien n'est animé quand la carte est cachée.
	Mise en page : tout reste à l'intérieur de la carte (ClipsDescendants),
	contour jamais coupé (voir Slots.ClipMargin).
]]

local Debris = game:GetService("Debris")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Press = {}
Press.Slot = "C3"

----------------------------------------------------------------------
-- Géométrie (pixels "design" dans la carte de 380 x 264 : slot de 384 x 268
-- moins 2 px de marge de chaque côté pour que le contour ne soit pas coupé)
----------------------------------------------------------------------
local HEADER_H = 32
local MX = 170 -- axe de la presse
local FLOOR_Y = 246 -- sol de l'atelier
local BELT_Y = 206 -- dessus du tapis (bas des objets)
local BELT_H = 8
local BELT_X0, BELT_X1 = 66, 372
local CROWN_Y, CROWN_H = 50, 26 -- traverse du haut
local CYL_Y = 36 -- haut du vérin
local PLATE_TOP = CROWN_Y + CROWN_H + 6 -- plateau en position haute
local PLATE_H = 22
local PLATE_W = 160
local PILLAR_W = 18
local PILLAR_X = { MX - 80 - PILLAR_W, MX + 80 } -- bord gauche de chaque colonne
local SPACING = 84 -- pas du tapis entre deux objets
local SLOT_X = { MX + SPACING, MX + SPACING * 2 } -- file d'attente
local EXIT_X = MX - SPACING -- la galette s'arrête ici avant de tomber dans le bac
local BIN_X, BIN_W, BIN_TOP = 36, 50, 184
local FLAT_H = 11 -- hauteur d'une galette
local CONSOLE_X, CONSOLE_Y, CONSOLE_W, CONSOLE_H = 294, 38, 76, 90
local PARTICLE_MAX = 44
local PUFF_MAX = 10
local SHOUT_COUNT = 2

-- Durées de base (niveau 1), divisées par le facteur de vitesse
local DURATIONS = {
	Load = 0.9,
	Descend = 1.1,
	Squeeze = 0.55,
	Crunch = 0.07,
	Hold = 0.45,
	Rise = 0.8,
}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK = rgb(34, 34, 40)
local RED = rgb(230, 40, 50)
local PILL = UDim.new(0.5, 0)

----------------------------------------------------------------------
-- Petits outils de couleur
----------------------------------------------------------------------
local function seq(...: Color3): ColorSequence
	local colors = { ... }
	local keypoints = {}
	for i, color in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), color))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end
	return ColorSequence.new(keypoints)
end

-- Bandes nettes de couleurs données (dégradé à bords francs)
local function bands(colors: { Color3 }): ColorSequence
	local keypoints = {}
	local n = #colors
	for i, color in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / n, color))
		table.insert(keypoints, ColorSequenceKeypoint.new(math.min(1, i / n - 0.002), color))
	end
	keypoints[#keypoints] = ColorSequenceKeypoint.new(1, colors[n])
	return ColorSequence.new(keypoints)
end

-- Rayures alternées (n bandes)
local function stripes(n: number, c1: Color3, c2: Color3): ColorSequence
	local colors = {}
	for i = 1, n do
		colors[i] = (i % 2 == 1) and c1 or c2
	end
	return bands(colors)
end

local function darker(color: Color3, k: number): Color3
	return color:Lerp(BLACK, k)
end

local function lighter(color: Color3, k: number): Color3
	return color:Lerp(WHITE, k)
end

-- Ombrage d'un cylindre vertical (colonne, tige) : sombre / reflet / base / sombre
local function cylinderSeq(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, darker(color, 0.35)),
		ColorSequenceKeypoint.new(0.22, lighter(color, 0.55)),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(0.85, darker(color, 0.25)),
		ColorSequenceKeypoint.new(1, darker(color, 0.45)),
	})
end

-- Ombrage d'une poutre horizontale (lumière d'en haut)
local function beamSeq(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter(color, 0.4)),
		ColorSequenceKeypoint.new(0.35, color),
		ColorSequenceKeypoint.new(1, darker(color, 0.35)),
	})
end

-- Dégradés "multiplicateurs" (appliqués sur une couleur de fond)
local SHADE_V = seq(WHITE, rgb(205, 205, 205))
local SHADE_CYL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(150, 150, 150)),
	ColorSequenceKeypoint.new(0.25, WHITE),
	ColorSequenceKeypoint.new(0.55, rgb(225, 225, 225)),
	ColorSequenceKeypoint.new(1, rgb(125, 125, 125)),
})

local function easeInOut(t: number): number
	return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- Rebond façon "Back" (dépasse puis revient) : 0 -> 1
local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

----------------------------------------------------------------------
-- Objets à écraser
----------------------------------------------------------------------
-- Texte traduit : { en = {...}, fr = {...} } (choisi avec Locale.Pick)
type Words = { en: { string }, fr: { string } }

local MACARON_COLORS = {
	rgb(255, 160, 192), -- framboise
	rgb(172, 222, 140), -- pistache
	rgb(192, 162, 240), -- violette
	rgb(255, 228, 120), -- citron
	rgb(156, 100, 74), -- chocolat
	rgb(255, 190, 132), -- fleur d'oranger
	rgb(150, 206, 255), -- myrtille... bleue
	rgb(236, 86, 124), -- fraise
}
local CAN_COLORS = { rgb(220, 40, 50), rgb(30, 110, 220), rgb(40, 170, 90), rgb(150, 70, 220), rgb(250, 150, 20) }
local GIFT_COLORS = { rgb(230, 60, 90), rgb(60, 140, 240), rgb(40, 180, 120), rgb(170, 90, 230), rgb(255, 170, 30) }
local RIBBON_COLORS = { rgb(255, 214, 60), WHITE, rgb(255, 120, 170), rgb(90, 220, 255) }
local JELLY_COLORS = { rgb(255, 70, 110), rgb(90, 220, 120), rgb(255, 170, 40), rgb(140, 110, 255), rgb(60, 200, 255) }
local ICING_COLORS = { rgb(255, 160, 200), rgb(120, 70, 50), WHITE, rgb(170, 220, 255) }
local RUBIK_COLORS = { rgb(230, 40, 40), rgb(40, 180, 70), rgb(30, 100, 230), rgb(255, 210, 30), rgb(255, 130, 20), WHITE }
local PAINT_COLORS = { rgb(255, 60, 120), rgb(40, 190, 255), rgb(120, 220, 60), rgb(255, 200, 30), rgb(160, 90, 255) }

local W = {
	Macaron = { en = { "CRUNCH!", "SCRUNCH!", "CRACK!", "Flat macaron!", "CRONCH!" }, fr = { "CRUNCH !", "SCRONCH !", "CRAC !", "Macaron à plat !", "CROUNCH !" } },
	Can = { en = { "CRONCH!", "Soda: flattened!", "PSSHT-CLONK!" }, fr = { "CRONCH !", "Soda aplati !", "PSCHT-CLONK !" } },
	Melon = { en = { "SPLOTCH!", "SPLOOSH!", "Instant juice!" }, fr = { "SPLOTCH !", "SCHPLOUF !", "Jus instantané !" } },
	Cake = { en = { "SPLAT!", "Happy squish-day!", "Flat cake!" }, fr = { "SPLAF !", "Joyeux écrasement !", "Gâteau plat !" } },
	Gift = { en = { "CRUNCH!", "Surprise! It's flat.", "Gift: unwrapped!" }, fr = { "CRUNCH !", "Surprise ! C'est plat.", "Cadeau déballé !" } },
	Jelly = { en = { "SPLORCH!", "Wobble... SPLAT!", "BLOBBB!" }, fr = { "SPLORTCH !", "Tremblote... SPLAF !", "BLOBBB !" } },
	Sponge = { en = { "SCHLURP!", "SQUISH!" }, fr = { "SCHLURP !", "SQUICH !" } },
	Rubik = { en = { "CRACK!", "Solved! (sort of)", "KRRRK!" }, fr = { "CRAC !", "Résolu ! (en quelque sorte)", "KRRRK !" } },
	Duck = { en = { "SQUEAK!", "QUACK!", "SQUEEEE!" }, fr = { "POUIC !", "COIN !", "POUIIIC !" } },
	Ball = { en = { "POP!!!", "BANG!", "Beach's closed!" }, fr = { "POP !!!", "BANG !", "Plage fermée !" } },
	Paint = { en = { "SPLASH!", "Modern art!", "SPLOSH!" }, fr = { "SPLASH !", "Art moderne !", "SPLOSH !" } },
	Log = { en = { "CRACK!", "Firewood, sorted!", "TIMBERRR!" }, fr = { "CRAC !", "Bois de chauffage, prêt !", "ATTENTION, CHUTE !" } },
	Barrel = { en = { "CLANG!", "Barrel pancake!", "BONG!" }, fr = { "CLANG !", "Tonneau-crêpe !", "BONG !" } },
	Drum = { en = { "KA-BLONK!", "Oil change!", "CRUMPLE!" }, fr = { "KA-BLONK !", "Vidange !", "FROISSSS !" } },
	Gold = { en = { "KA-CHING!", "Fresh gold leaf!", "CLINK!" }, fr = { "KA-CHING !", "Feuille d'or fraîche !", "CLING !" } },
	Crystal = { en = { "CRIIING!", "Premium crushed ice!", "SHIIING!" }, fr = { "CRIIING !", "Glace pilée premium !", "SHIIING !" } },
}

-- Boîte à outils passée aux dessins d'objets
type Kit = {
	Part: (parent: Instance, x: number, y: number, w: number, h: number, color: Color3, z: number?, radius: UDim?, transparency: number?) -> Frame,
	Gradient: (frame: Instance, color: ColorSequence, rotation: number?) -> UIGradient,
	Stroke: (frame: Instance, color: Color3, thickness: number?, transparency: number?) -> UIStroke,
	Random: Random,
}

-- Résultat d'un dessin : couleurs des éclats, couleur de la galette, pièces spéciales
type Built = {
	Colors: { Color3 },
	Main: Color3,
	Fillings: { Frame }?,
	Body: Frame?,
	Gradient: UIGradient?,
	Stroke: UIStroke?,
}

type Drawn = {
	Id: string,
	W: number,
	H: number,
	Weight: number,
	Words: Words,
	Special: string?,
	Wobble: number?,
	Build: (k: Kit, holder: Frame) -> Built,
}

local function pickFrom(list: { any }, r: Random): any
	return list[r:NextInteger(1, #list)]
end

-- Reflet commun (bande blanche translucide à gauche)
local function shine(k: Kit, holder: Frame, x: number, y: number, w: number, h: number, z: number?)
	k.Part(holder, x, y, w, h, WHITE, z or 8, PILL, 0.55)
end

local DRAWN: { [string]: Drawn } = {
	Macarons = {
		Id = "Macarons", W = 62, H = 64, Weight = 3, Words = W.Macaron,
		Build = function(k, holder)
			local colors, fillings = {}, {}
			for i = 1, 3 do
				local color = pickFrom(MACARON_COLORS, k.Random)
				colors[i] = color
				local unit = k.Part(holder, 0.5 + k.Random:NextNumber(-0.03, 0.03), (i - 1) / 3, k.Random:NextNumber(0.9, 1), 1 / 3, color, 1, nil, 1)
				unit.AnchorPoint = Vector2.new(0.5, 0)
				k.Gradient(k.Part(unit, 0, 0.04, 1, 0.42, color, 2, PILL), SHADE_V, 90)
				local fillingColor = (color.R < 0.7 and color.G < 0.5) and rgb(96, 56, 40) or rgb(255, 246, 228)
				local filling = k.Part(unit, 0.5, 0.42, 0.86, 0.17, fillingColor, 3, PILL)
				filling.AnchorPoint = Vector2.new(0.5, 0)
				k.Gradient(k.Part(unit, 0, 0.56, 1, 0.4, darker(color, 0.08), 2, PILL), SHADE_V, 90)
				table.insert(fillings, filling)
			end
			return { Colors = colors, Main = colors[2], Fillings = fillings }
		end,
	},
	Can = {
		Id = "Can", W = 40, H = 62, Weight = 2, Words = W.Can,
		Build = function(k, holder)
			local c = pickFrom(CAN_COLORS, k.Random)
			local body = k.Part(holder, 0, 0.07, 1, 0.93, c, 2, UDim.new(0.18, 0))
			k.Gradient(body, SHADE_CYL, 0)
			local band = k.Part(body, 0, 0.34, 1, 0.3, WHITE, 3)
			k.Gradient(band, SHADE_CYL, 0)
			k.Part(band, 0.28, 0.16, 0.44, 0.68, c, 4, PILL)
			local rim = k.Part(holder, 0.04, 0, 0.92, 0.15, rgb(214, 218, 226), 4, PILL)
			k.Gradient(rim, seq(WHITE, rgb(150, 156, 168)), 90)
			k.Part(rim, 0.38, 0.28, 0.24, 0.44, rgb(150, 156, 170), 5, PILL)
			shine(k, holder, 0.14, 0.14, 0.12, 0.78)
			return { Colors = { c, rgb(210, 214, 222), WHITE }, Main = c }
		end,
	},
	Melon = {
		Id = "Melon", W = 70, H = 54, Weight = 2, Words = W.Melon, Special = "Melon",
		Build = function(k, holder)
			local body = k.Part(holder, 0, 0, 1, 1, WHITE, 2, PILL)
			local gradient = k.Gradient(body, stripes(9, rgb(40, 132, 48), rgb(118, 198, 86)), 0)
			local stroke = k.Stroke(body, rgb(26, 90, 34), 1.5)
			k.Part(holder, 0.47, -0.06, 0.06, 0.1, rgb(110, 80, 40), 1)
			shine(k, holder, 0.18, 0.12, 0.3, 0.18)
			return { Colors = { rgb(235, 60, 70), rgb(255, 120, 120), rgb(40, 132, 48) }, Main = rgb(235, 60, 70), Body = body, Gradient = gradient, Stroke = stroke }
		end,
	},
	Cake = {
		Id = "Cake", W = 64, H = 64, Weight = 2, Words = W.Cake,
		Build = function(k, holder)
			local sponge = rgb(246, 206, 140)
			local icing = pickFrom(ICING_COLORS, k.Random)
			k.Part(holder, -0.08, 0.93, 1.16, 0.07, rgb(240, 242, 248), 1, PILL)
			k.Gradient(k.Part(holder, 0, 0.62, 1, 0.32, sponge, 2, UDim.new(0.15, 0)), SHADE_V, 90)
			k.Part(holder, 0, 0.55, 1, 0.08, rgb(255, 250, 240), 3, PILL)
			k.Gradient(k.Part(holder, 0, 0.3, 1, 0.27, sponge, 2, UDim.new(0.15, 0)), SHADE_V, 90)
			k.Part(holder, -0.03, 0.2, 1.06, 0.15, icing, 4, PILL)
			for _, x in ipairs({ 0.12, 0.42, 0.74 }) do
				k.Part(holder, x, 0.28, 0.08, k.Random:NextNumber(0.08, 0.16), icing, 4, PILL)
			end
			local cherry = k.Part(holder, 0.42, 0.02, 0.16, 0.18, rgb(220, 30, 50), 5, PILL)
			k.Part(cherry, 0.2, 0.15, 0.3, 0.3, WHITE, 6, PILL, 0.4)
			return { Colors = { sponge, icing, rgb(255, 250, 240), rgb(220, 30, 50) }, Main = sponge }
		end,
	},
	Gift = {
		Id = "Gift", W = 58, H = 60, Weight = 2, Words = W.Gift,
		Build = function(k, holder)
			local c = pickFrom(GIFT_COLORS, k.Random)
			local ribbon = pickFrom(RIBBON_COLORS, k.Random)
			k.Gradient(k.Part(holder, 0.05, 0.34, 0.9, 0.66, c, 2, UDim.new(0.08, 0)), SHADE_V, 90)
			k.Gradient(k.Part(holder, 0, 0.24, 1, 0.16, lighter(c, 0.12), 3, UDim.new(0.2, 0)), SHADE_V, 90)
			k.Part(holder, 0.42, 0.24, 0.16, 0.76, ribbon, 4)
			local left = k.Part(holder, 0.16, 0.05, 0.32, 0.2, ribbon, 5, PILL)
			left.Rotation = -18
			local right = k.Part(holder, 0.52, 0.05, 0.32, 0.2, ribbon, 5, PILL)
			right.Rotation = 18
			k.Part(holder, 0.43, 0.12, 0.14, 0.14, darker(ribbon, 0.15), 6, PILL)
			return { Colors = { c, ribbon, lighter(c, 0.3) }, Main = c }
		end,
	},
	Jelly = {
		Id = "Jelly", W = 58, H = 52, Weight = 2, Words = W.Jelly, Wobble = 4,
		Build = function(k, holder)
			local c = pickFrom(JELLY_COLORS, k.Random)
			k.Part(holder, -0.1, 0.9, 1.2, 0.1, rgb(240, 242, 248), 1, PILL)
			local body = k.Part(holder, 0, 0.14, 1, 0.8, c, 2, UDim.new(0.3, 0), 0.12)
			k.Gradient(body, seq(lighter(c, 0.35), c, darker(c, 0.2)), 90)
			k.Part(holder, 0.07, 0.16, 0.86, 0.2, lighter(c, 0.45), 3, PILL, 0.2)
			shine(k, holder, 0.14, 0.38, 0.1, 0.38)
			k.Part(holder, 0.4, 0, 0.2, 0.22, rgb(220, 30, 60), 4, PILL)
			return { Colors = { c, lighter(c, 0.4), rgb(220, 30, 60) }, Main = c }
		end,
	},
	Sponge = {
		Id = "Sponge", W = 64, H = 44, Weight = 1, Words = W.Sponge, Special = "Sponge", Wobble = 2,
		Build = function(k, holder)
			local foam = k.Part(holder, 0, 0.3, 1, 0.7, rgb(255, 220, 70), 2, UDim.new(0.12, 0))
			k.Gradient(foam, SHADE_V, 90)
			k.Gradient(k.Part(holder, 0, 0, 1, 0.34, rgb(60, 170, 80), 3, UDim.new(0.14, 0)), SHADE_V, 90)
			for _, hole in ipairs({ { 0.12, 0.5, 0.14, 0.16 }, { 0.42, 0.66, 0.1, 0.12 }, { 0.68, 0.46, 0.16, 0.16 }, { 0.3, 0.8, 0.12, 0.1 }, { 0.82, 0.76, 0.08, 0.1 } }) do
				k.Part(holder, hole[1], hole[2], hole[3], hole[4], rgb(222, 172, 30), 3, PILL)
			end
			return { Colors = { rgb(255, 220, 70), rgb(60, 170, 80), rgb(190, 230, 255) }, Main = rgb(255, 220, 70) }
		end,
	},
	Rubik = {
		Id = "Rubik", W = 52, H = 52, Weight = 1, Words = W.Rubik,
		Build = function(k, holder)
			local base = k.Part(holder, 0, 0, 1, 1, rgb(26, 26, 30), 2, UDim.new(0.12, 0))
			local used = {}
			for i = 0, 2 do
				for j = 0, 2 do
					local color = pickFrom(RUBIK_COLORS, k.Random)
					used[#used + 1] = color
					k.Part(base, 0.05 + i * 0.31, 0.05 + j * 0.31, 0.28, 0.28, color, 3, UDim.new(0.2, 0))
				end
			end
			shine(k, holder, 0.1, 0.08, 0.3, 0.1)
			return { Colors = { used[1], used[5], used[9], rgb(26, 26, 30) }, Main = used[5] }
		end,
	},
	Duck = {
		Id = "Duck", W = 62, H = 58, Weight = 2, Words = W.Duck,
		Build = function(k, holder)
			local yellow = rgb(255, 210, 40)
			k.Part(holder, -0.04, 0.36, 0.24, 0.24, yellow, 1, PILL)
			k.Gradient(k.Part(holder, 0, 0.42, 0.94, 0.56, yellow, 2, PILL), SHADE_V, 90)
			k.Gradient(k.Part(holder, 0.44, 0.02, 0.48, 0.5, yellow, 3, PILL), SHADE_V, 90)
			k.Part(holder, 0.84, 0.25, 0.2, 0.13, rgb(255, 130, 30), 4, PILL)
			local eye = k.Part(holder, 0.66, 0.14, 0.09, 0.1, rgb(30, 30, 40), 4, PILL)
			k.Part(eye, 0.2, 0.1, 0.4, 0.4, WHITE, 5, PILL)
			k.Part(holder, 0.16, 0.56, 0.42, 0.22, rgb(240, 178, 20), 3, PILL)
			shine(k, holder, 0.52, 0.08, 0.14, 0.12)
			return { Colors = { yellow, rgb(255, 130, 30), rgb(255, 240, 150) }, Main = yellow }
		end,
	},
	Ball = {
		Id = "Ball", W = 56, H = 56, Weight = 1, Words = W.Ball, Special = "Pop",
		Build = function(k, holder)
			local ball = k.Part(holder, 0, 0, 1, 1, WHITE, 2, PILL)
			k.Gradient(ball, bands({ rgb(230, 40, 50), WHITE, rgb(30, 110, 230), rgb(255, 210, 30), WHITE, rgb(40, 180, 90) }), 0)
			k.Stroke(ball, rgb(60, 60, 80), 1, 0.5)
			k.Part(holder, 0.42, 0.42, 0.16, 0.16, WHITE, 3, PILL)
			shine(k, holder, 0.2, 0.12, 0.26, 0.16)
			return { Colors = { rgb(230, 40, 50), rgb(30, 110, 230), rgb(255, 210, 30), rgb(40, 180, 90), WHITE }, Main = rgb(230, 40, 50) }
		end,
	},
	Paint = {
		Id = "Paint", W = 48, H = 56, Weight = 1, Words = W.Paint, Special = "Paint",
		Build = function(k, holder)
			local c = pickFrom(PAINT_COLORS, k.Random)
			local body = k.Part(holder, 0, 0.12, 1, 0.88, rgb(200, 204, 212), 2, UDim.new(0.12, 0))
			k.Gradient(body, SHADE_CYL, 0)
			local label = k.Part(body, 0, 0.28, 1, 0.46, c, 3)
			k.Gradient(label, SHADE_CYL, 0)
			k.Part(label, 0.34, 0.2, 0.32, 0.6, WHITE, 4, PILL, 0.25)
			k.Part(holder, 0, 0.05, 1, 0.14, rgb(214, 218, 226), 3, PILL)
			k.Part(holder, 0.08, 0.07, 0.56, 0.11, c, 4, PILL)
			k.Part(holder, 0.18, 0.12, 0.09, 0.24, c, 4, PILL)
			return { Colors = { c, c, lighter(c, 0.4), rgb(200, 204, 212) }, Main = c }
		end,
	},
	-- Objets propres aux paliers
	Log = {
		Id = "Log", W = 76, H = 40, Weight = 0, Words = W.Log,
		Build = function(k, holder)
			local bark = k.Part(holder, 0, 0, 0.84, 1, WHITE, 2, UDim.new(0.3, 0))
			k.Gradient(bark, stripes(6, rgb(140, 92, 52), rgb(100, 64, 34)), 90)
			local ring = k.Part(holder, 0.64, 0, 0.36, 1, rgb(226, 184, 124), 3, PILL)
			k.Stroke(ring, rgb(110, 70, 38), 2)
			local inner = k.Part(ring, 0.25, 0.25, 0.5, 0.5, rgb(206, 158, 96), 4, PILL)
			k.Stroke(inner, rgb(170, 120, 70), 1)
			return { Colors = { rgb(140, 92, 52), rgb(226, 184, 124), rgb(90, 60, 30) }, Main = rgb(206, 158, 96) }
		end,
	},
	Barrel = {
		Id = "Barrel", W = 50, H = 64, Weight = 0, Words = W.Barrel,
		Build = function(k, holder)
			local c = k.Random:NextNumber() < 0.5 and rgb(170, 176, 188) or rgb(50, 110, 200)
			local body = k.Part(holder, 0, 0.06, 1, 0.94, c, 2, UDim.new(0.14, 0))
			k.Gradient(body, SHADE_CYL, 0)
			k.Part(body, 0, 0.26, 1, 0.07, darker(c, 0.35), 3)
			k.Part(body, 0, 0.66, 1, 0.07, darker(c, 0.35), 3)
			k.Part(holder, 0.03, 0, 0.94, 0.13, lighter(c, 0.3), 4, PILL)
			shine(k, holder, 0.16, 0.14, 0.1, 0.76)
			return { Colors = { c, lighter(c, 0.4), darker(c, 0.3) }, Main = c }
		end,
	},
	Drum = {
		Id = "Drum", W = 50, H = 64, Weight = 0, Words = W.Drum,
		Build = function(k, holder)
			local c = rgb(255, 140, 20)
			local body = k.Part(holder, 0, 0.06, 1, 0.94, c, 2, UDim.new(0.14, 0))
			k.Gradient(body, SHADE_CYL, 0)
			local band = k.Part(body, 0, 0.36, 1, 0.3, rgb(30, 30, 36), 3)
			local sign = k.Part(band, 0.5, 0.5, 0.36, 0.6, rgb(255, 214, 40), 4)
			sign.AnchorPoint = Vector2.new(0.5, 0.5)
			sign.Rotation = 45
			k.Part(holder, 0.03, 0, 0.94, 0.13, lighter(c, 0.3), 4, PILL)
			shine(k, holder, 0.16, 0.14, 0.1, 0.76)
			return { Colors = { c, rgb(30, 30, 36), rgb(255, 214, 40), rgb(40, 30, 20) }, Main = c }
		end,
	},
	GoldBars = {
		Id = "GoldBars", W = 72, H = 42, Weight = 0, Words = W.Gold,
		Build = function(k, holder)
			local function bar(x: number, y: number, w: number, h: number)
				local b = k.Part(holder, x, y, w, h, WHITE, 2, UDim.new(0.2, 0))
				k.Gradient(b, seq(rgb(255, 246, 196), rgb(255, 208, 70), rgb(196, 126, 10)), 90)
				k.Stroke(b, rgb(150, 96, 10), 1)
				k.Part(b, 0.12, 0.16, 0.76, 0.2, WHITE, 3, PILL, 0.45)
			end
			bar(0, 0.52, 0.49, 0.48)
			bar(0.51, 0.52, 0.49, 0.48)
			bar(0.22, 0.04, 0.56, 0.48)
			return { Colors = { rgb(255, 214, 70), rgb(255, 246, 196), rgb(200, 130, 10) }, Main = rgb(255, 208, 70) }
		end,
	},
	Crystal = {
		Id = "Crystal", W = 56, H = 56, Weight = 0, Words = W.Crystal,
		Build = function(k, holder)
			local ice = k.Part(holder, 0, 0, 1, 1, rgb(170, 230, 255), 2, UDim.new(0.16, 0), 0.12)
			k.Gradient(ice, seq(WHITE, rgb(200, 240, 255), rgb(110, 180, 240)), 60)
			k.Stroke(ice, WHITE, 1.5, 0.15)
			k.Part(holder, 0.1, 0.08, 0.5, 0.3, WHITE, 3, UDim.new(0.25, 0), 0.5)
			k.Part(holder, 0.52, 0.56, 0.36, 0.3, rgb(120, 200, 255), 3, UDim.new(0.25, 0), 0.35)
			k.Part(holder, 0.18, 0.5, 0.08, 0.34, WHITE, 3, PILL, 0.45)
			return { Colors = { rgb(190, 240, 255), WHITE, rgb(120, 200, 255) }, Main = rgb(170, 230, 255) }
		end,
	},
}

-- Objets "emoji" (remplacés par une galette colorée à l'écrasement)
type EmojiItem = { Icon: string, Color: Color3, Words: Words }
local EMOJI_ITEMS: { EmojiItem } = {
	{ Icon = "🥫", Color = rgb(205, 60, 45), Words = { en = { "CRONCH!", "CLONK!" }, fr = { "CRONCH !", "CLONK !" } } },
	{ Icon = "🧸", Color = rgb(190, 130, 70), Words = { en = { "POOF!", "Sorry, teddy..." }, fr = { "POUF !", "Pardon nounours..." } } },
	{ Icon = "🥚", Color = rgb(255, 214, 60), Words = { en = { "CRACK!", "Omelette!" }, fr = { "CRAC !", "Omelette !" } } },
	{ Icon = "🍩", Color = rgb(255, 140, 190), Words = { en = { "SCRUNCH!", "Flat donut!" }, fr = { "SCRONCH !", "Donut plat !" } } },
	{ Icon = "🧊", Color = rgb(170, 225, 255), Words = { en = { "CRIIICK!", "Crushed ice!" }, fr = { "CRIIIC !", "Glace pilée !" } } },
	{ Icon = "🍅", Color = rgb(230, 40, 30), Words = { en = { "SPLOTCH!", "Homemade ketchup!" }, fr = { "SPLOTCH !", "Ketchup maison !" } } },
	{ Icon = "🍔", Color = rgb(200, 120, 50), Words = { en = { "SMASH!", "Smash burger!" }, fr = { "SMASH !", "Smash burger !" } } },
	{ Icon = "📦", Color = rgb(190, 140, 80), Words = { en = { "CRACK!", "Package delivered (flat)" }, fr = { "CRAC !", "Colis livré (à plat)" } } },
	{ Icon = "🍋", Color = rgb(255, 230, 60), Words = { en = { "PSSHT!", "Lemonade!" }, fr = { "PSCHIT !", "Limonade !" } } },
	{ Icon = "🎃", Color = rgb(255, 140, 20), Words = { en = { "SPLUNK!", "Pumpkin purée!" }, fr = { "SPLOUNK !", "Purée de citrouille !" } } },
	{ Icon = "🍍", Color = rgb(255, 200, 40), Words = { en = { "SQUISH!", "Pineapple juice!" }, fr = { "SQUICH !", "Jus d'ananas !" } } },
	{ Icon = "🧁", Color = rgb(255, 170, 210), Words = { en = { "SPLUT!", "Cupcake pancake!" }, fr = { "SPLOUTCH !", "Cupcake-crêpe !" } } },
}

----------------------------------------------------------------------
-- Paliers visuels (un par niveau)
----------------------------------------------------------------------
type Localized = { en: string, fr: string }

type TierStyle = {
	Name: Localized,
	Shout: Localized,
	Icon: string,
	Chip: Color3,
	ChipText: Color3,
	WallTop: Color3,
	WallBottom: Color3,
	Seam: Color3,
	Floor: Color3,
	CardStroke: Color3,
	Title: Color3,
	Frame: Color3, -- couleur principale de la machine
	AccentA: Color3, -- bandes d'accent (rayures)
	AccentB: Color3,
	Chrome: Color3, -- tige du vérin
	Hose: Color3,
	Fitting: Color3,
	Bolt: Color3,
	Outline: Color3,
	Debris: { Color3 },
	Drawn: { string }, -- objets dessinés propres au palier
	Emoji: { EmojiItem },
	Wood: boolean?,
	Rope: boolean?,
	Bands: boolean?,
	Rivets: boolean?,
	Gauge2: boolean?,
	Beacon: boolean?,
	Steam: boolean?,
	Digital: boolean?,
	Shine: boolean?,
	Sparkle: Color3?,
	Gems: boolean?,
	Crystal: boolean?,
	Neon: boolean?,
	Dark: boolean?, -- carte sombre (texte clair)
}

local TIERS: { TierStyle } = {
	{
		Name = { en = "Rustic wood", fr = "Bois rustique" },
		Shout = { en = "WOODEN PRESS!", fr = "PRESSE EN BOIS !" },
		Icon = "🪵",
		Chip = rgb(170, 112, 64), ChipText = WHITE,
		WallTop = rgb(255, 247, 232), WallBottom = rgb(236, 212, 176), Seam = rgb(200, 162, 112), Floor = rgb(138, 94, 56),
		CardStroke = rgb(96, 62, 34), Title = rgb(80, 50, 26),
		Frame = rgb(186, 128, 74), AccentA = rgb(226, 196, 138), AccentB = rgb(186, 150, 92),
		Chrome = rgb(214, 170, 84), Hose = rgb(122, 76, 42), Fitting = rgb(214, 170, 84), Bolt = rgb(70, 58, 50), Outline = rgb(96, 60, 32),
		Debris = { rgb(186, 128, 74), rgb(226, 196, 138) },
		Drawn = { "Log" },
		Emoji = {
			{ Icon = "🥥", Color = rgb(130, 86, 52), Words = { en = { "CRACK!", "Coconut: opened!" }, fr = { "CRAC !", "Noix de coco ouverte !" } } },
			{ Icon = "🥖", Color = rgb(222, 170, 92), Words = { en = { "CRUNCHY!", "Flat baguette!" }, fr = { "CROUSTI !", "Baguette à plat !" } } },
		},
		Wood = true, Rope = true,
	},
	{
		Name = { en = "Oak & iron", fr = "Chêne & fer" },
		Shout = { en = "IRON-BOUND PRESS!", fr = "PRESSE CERCLÉE DE FER !" },
		Icon = "🪓",
		Chip = rgb(120, 76, 44), ChipText = WHITE,
		WallTop = rgb(248, 238, 222), WallBottom = rgb(216, 192, 158), Seam = rgb(180, 146, 104), Floor = rgb(104, 72, 44),
		CardStroke = rgb(70, 46, 26), Title = rgb(66, 40, 20),
		Frame = rgb(140, 90, 50), AccentA = rgb(92, 94, 104), AccentB = rgb(62, 64, 72),
		Chrome = rgb(160, 164, 172), Hose = rgb(64, 46, 32), Fitting = rgb(150, 154, 162), Bolt = rgb(44, 44, 50), Outline = rgb(66, 42, 22),
		Debris = { rgb(140, 90, 50), rgb(120, 122, 130) },
		Drawn = { "Log", "Barrel" },
		Emoji = {
			{ Icon = "🌰", Color = rgb(150, 90, 50), Words = { en = { "CRICK!", "Mashed chestnut!" }, fr = { "CRIC !", "Châtaigne pilée !" } } },
			{ Icon = "🪣", Color = rgb(150, 156, 170), Words = { en = { "CLONK!", "Flat bucket!" }, fr = { "CLONK !", "Seau à plat !" } } },
		},
		Wood = true, Bands = true, Rivets = true,
	},
	{
		Name = { en = "Steel", fr = "Acier" },
		Shout = { en = "STEEL PRESS!", fr = "PRESSE EN ACIER !" },
		Icon = "⚙️",
		Chip = rgb(96, 104, 120), ChipText = WHITE,
		WallTop = rgb(246, 248, 252), WallBottom = rgb(208, 216, 228), Seam = rgb(180, 190, 206), Floor = rgb(96, 104, 118),
		CardStroke = rgb(30, 30, 36), Title = rgb(24, 24, 30),
		Frame = rgb(160, 168, 182), AccentA = rgb(255, 200, 30), AccentB = INK,
		Chrome = rgb(210, 216, 226), Hose = rgb(40, 40, 46), Fitting = rgb(200, 204, 212), Bolt = rgb(90, 96, 110), Outline = rgb(58, 62, 74),
		Debris = { rgb(200, 205, 215) },
		Drawn = { "Barrel" },
		Emoji = {
			{ Icon = "🔩", Color = rgb(150, 150, 165), Words = { en = { "CLONK!", "Flattened bolt!" }, fr = { "CLONK !", "Boulon aplati !" } } },
		},
		Rivets = true,
	},
	{
		Name = { en = "Blue steel", fr = "Acier bleu" },
		Shout = { en = "HEAVY STEEL PRESS!", fr = "PRESSE LOURDE !" },
		Icon = "🔧",
		Chip = rgb(40, 104, 200), ChipText = WHITE,
		WallTop = rgb(240, 245, 252), WallBottom = rgb(194, 208, 228), Seam = rgb(170, 188, 214), Floor = rgb(70, 82, 104),
		CardStroke = rgb(20, 44, 90), Title = rgb(16, 34, 70),
		Frame = rgb(48, 114, 204), AccentA = rgb(255, 200, 30), AccentB = INK,
		Chrome = rgb(214, 220, 230), Hose = rgb(30, 30, 36), Fitting = rgb(220, 60, 50), Bolt = rgb(220, 226, 236), Outline = rgb(20, 50, 100),
		Debris = { rgb(48, 114, 204), rgb(220, 226, 236) },
		Drawn = { "Barrel" },
		Emoji = {
			{ Icon = "🧲", Color = rgb(220, 40, 40), Words = { en = { "CLANK!", "Demagnetized!" }, fr = { "CLANK !", "Démagnétisé !" } } },
		},
		Rivets = true, Gauge2 = true,
	},
	{
		Name = { en = "Industrial", fr = "Industrielle" },
		Shout = { en = "INDUSTRIAL PRESS!", fr = "PRESSE INDUSTRIELLE !" },
		Icon = "🏭",
		Chip = rgb(236, 120, 20), ChipText = WHITE,
		WallTop = rgb(230, 232, 234), WallBottom = rgb(176, 180, 186), Seam = rgb(150, 154, 162), Floor = rgb(78, 82, 90),
		CardStroke = rgb(40, 44, 52), Title = rgb(30, 34, 40),
		Frame = rgb(244, 140, 30), AccentA = rgb(255, 214, 40), AccentB = INK,
		Chrome = rgb(214, 220, 230), Hose = rgb(28, 28, 32), Fitting = rgb(255, 210, 40), Bolt = rgb(60, 60, 66), Outline = rgb(90, 50, 10),
		Debris = { rgb(244, 140, 30), rgb(120, 126, 140) },
		Drawn = { "Drum" },
		Emoji = {
			{ Icon = "🚗", Color = rgb(220, 50, 50), Words = { en = { "CRUNCH!", "Car compactor!" }, fr = { "CRUNCH !", "Compression auto !" } } },
			{ Icon = "📺", Color = rgb(90, 90, 104), Words = { en = { "KRZZT!", "Flat screen TV!" }, fr = { "KRZZT !", "Écran plat !" } } },
		},
		Rivets = true, Gauge2 = true, Beacon = true, Steam = true,
	},
	{
		Name = { en = "Factory", fr = "Usine" },
		Shout = { en = "FACTORY PRESS!", fr = "PRESSE D'USINE !" },
		Icon = "🏗️",
		Chip = rgb(40, 190, 100), ChipText = rgb(10, 30, 16),
		WallTop = rgb(62, 70, 84), WallBottom = rgb(32, 36, 44), Seam = rgb(84, 94, 110), Floor = rgb(26, 30, 36),
		CardStroke = rgb(60, 210, 110), Title = WHITE,
		Frame = rgb(78, 88, 104), AccentA = rgb(60, 214, 110), AccentB = rgb(26, 30, 36),
		Chrome = rgb(214, 220, 230), Hose = rgb(20, 20, 24), Fitting = rgb(60, 214, 110), Bolt = rgb(150, 160, 176), Outline = rgb(20, 24, 30),
		Debris = { rgb(78, 88, 104), rgb(60, 214, 110) },
		Drawn = { "Drum", "Barrel" },
		Emoji = {
			{ Icon = "🧯", Color = rgb(220, 40, 40), Words = { en = { "PSSHHHT!", "Extinguisher: extinguished!" }, fr = { "PSCHHHT !", "Extincteur éteint !" } } },
			{ Icon = "🖨️", Color = rgb(200, 204, 212), Words = { en = { "PAPER JAM!", "Printer: finally quiet." }, fr = { "BOURRAGE !", "Imprimante enfin calme." } } },
		},
		Rivets = true, Gauge2 = true, Beacon = true, Steam = true, Digital = true, Dark = true,
	},
	{
		Name = { en = "Solid gold", fr = "Or massif" },
		Shout = { en = "GOLDEN PRESS!", fr = "PRESSE EN OR !" },
		Icon = "🥇",
		Chip = rgb(255, 194, 26), ChipText = rgb(70, 44, 0),
		WallTop = rgb(255, 251, 236), WallBottom = rgb(255, 224, 150), Seam = rgb(236, 196, 110), Floor = rgb(150, 100, 20),
		CardStroke = rgb(150, 100, 10), Title = rgb(100, 64, 0),
		Frame = rgb(240, 180, 40), AccentA = rgb(255, 240, 170), AccentB = rgb(214, 150, 20),
		Chrome = rgb(255, 230, 140), Hose = rgb(120, 72, 20), Fitting = rgb(255, 220, 90), Bolt = rgb(150, 100, 10), Outline = rgb(150, 100, 10),
		Debris = { rgb(255, 214, 70), rgb(255, 246, 200) },
		Drawn = { "GoldBars" },
		Emoji = {
			{ Icon = "🏆", Color = rgb(255, 196, 40), Words = { en = { "CLANG!", "Flat trophy!" }, fr = { "CLANG !", "Trophée à plat !" } } },
			{ Icon = "💰", Color = rgb(230, 190, 60), Words = { en = { "KA-CHING!", "It's raining coins!" }, fr = { "KA-CHING !", "Pluie de pièces !" } } },
		},
		Rivets = true, Gauge2 = true, Shine = true, Sparkle = rgb(255, 214, 80),
	},
	{
		Name = { en = "Royal gold", fr = "Or royal" },
		Shout = { en = "ROYAL PRESS!", fr = "PRESSE ROYALE !" },
		Icon = "👑",
		Chip = rgb(196, 30, 70), ChipText = rgb(255, 236, 160),
		WallTop = rgb(96, 34, 96), WallBottom = rgb(46, 12, 52), Seam = rgb(130, 60, 120), Floor = rgb(140, 20, 44),
		CardStroke = rgb(255, 200, 60), Title = rgb(255, 230, 150),
		Frame = rgb(246, 190, 50), AccentA = rgb(196, 24, 56), AccentB = rgb(255, 222, 120),
		Chrome = rgb(255, 236, 160), Hose = rgb(150, 20, 44), Fitting = rgb(255, 214, 80), Bolt = rgb(255, 236, 160), Outline = rgb(150, 96, 10),
		Debris = { rgb(255, 214, 70), rgb(196, 24, 56), rgb(255, 246, 200) },
		Drawn = { "GoldBars" },
		Emoji = {
			{ Icon = "👑", Color = rgb(255, 204, 40), Words = { en = { "CRONCH!", "Crown: flattened!" }, fr = { "CRONCH !", "Couronne aplatie !" } } },
			{ Icon = "🏺", Color = rgb(200, 120, 60), Words = { en = { "CRASH!", "Antique: now modern." }, fr = { "CRASH !", "Antiquité : désormais moderne." } } },
		},
		Rivets = true, Gauge2 = true, Shine = true, Sparkle = rgb(255, 214, 80), Gems = true, Dark = true,
	},
	{
		Name = { en = "Diamond", fr = "Diamant" },
		Shout = { en = "DIAMOND PRESS!", fr = "PRESSE DIAMANT !" },
		Icon = "💎",
		Chip = rgb(90, 200, 255), ChipText = rgb(8, 36, 60),
		WallTop = rgb(238, 250, 255), WallBottom = rgb(186, 224, 248), Seam = rgb(170, 214, 240), Floor = rgb(110, 170, 214),
		CardStroke = rgb(40, 140, 210), Title = rgb(12, 54, 90),
		Frame = rgb(176, 232, 255), AccentA = WHITE, AccentB = rgb(130, 206, 255),
		Chrome = rgb(236, 250, 255), Hose = rgb(80, 164, 230), Fitting = WHITE, Bolt = rgb(90, 170, 230), Outline = rgb(40, 130, 200),
		Debris = { rgb(190, 240, 255), WHITE, rgb(120, 200, 255) },
		Drawn = { "Crystal" },
		Emoji = {
			{ Icon = "💎", Color = rgb(120, 220, 255), Words = { en = { "CRIIING!", "Diamond?? Nope, glass." }, fr = { "CRIIING !", "Diamant ?? Non, du verre." } } },
			{ Icon = "🔮", Color = rgb(190, 120, 255), Words = { en = { "PSHIIIT!", "Future: crushed!" }, fr = { "PSHIIIT !", "Avenir écrasé !" } } },
		},
		Rivets = true, Gauge2 = true, Shine = true, Sparkle = rgb(140, 220, 255), Crystal = true,
	},
	{
		Name = { en = "Neon diamond", fr = "Diamant néon" },
		Shout = { en = "NEON DIAMOND PRESS!", fr = "PRESSE DIAMANT NÉON !" },
		Icon = "🌈",
		Chip = rgb(0, 214, 255), ChipText = rgb(10, 20, 40),
		WallTop = rgb(38, 22, 72), WallBottom = rgb(10, 8, 26), Seam = rgb(70, 40, 130), Floor = rgb(18, 12, 38),
		CardStroke = rgb(0, 230, 255), Title = WHITE,
		Frame = rgb(200, 238, 255), AccentA = rgb(0, 230, 255), AccentB = rgb(255, 60, 200),
		Chrome = rgb(236, 250, 255), Hose = rgb(255, 60, 200), Fitting = rgb(0, 230, 255), Bolt = rgb(0, 230, 255), Outline = rgb(0, 230, 255),
		Debris = { rgb(0, 230, 255), rgb(255, 60, 200), WHITE },
		Drawn = { "Crystal" },
		Emoji = {
			{ Icon = "🌟", Color = rgb(255, 230, 90), Words = { en = { "SHIIING!", "Shooting star... flattened" }, fr = { "SHIIING !", "Étoile filante... à plat" } } },
			{ Icon = "🪩", Color = rgb(200, 200, 230), Words = { en = { "DISCO CRUNCH!", "Party's over." }, fr = { "DISCO CRUNCH !", "La fête est finie." } } },
		},
		Rivets = true, Gauge2 = true, Beacon = true, Shine = true, Sparkle = rgb(255, 120, 230), Crystal = true, Neon = true, Dark = true,
	},
}

local function tierForLevel(level: number): number
	return math.clamp(math.floor(level), 1, #TIERS)
end

-- Tirage pondéré d'un objet dessiné "général" (Weight > 0)
local GENERAL: { Drawn } = {}
local GENERAL_WEIGHT = 0
for _, def in pairs(DRAWN) do
	if def.Weight > 0 then
		table.insert(GENERAL, def)
		GENERAL_WEIGHT += def.Weight
	end
end
table.sort(GENERAL, function(a, b)
	return a.Id < b.Id
end)

function Press.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()
	local cooldown = (ctx.Config.Interactions.Press and ctx.Config.Interactions.Press.Cooldown) or 3

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- La carte est-elle visible ? (si le StimulusManager sait le dire)
	local function visible(): boolean
		local isVisible = ctx.IsVisible
		if type(isVisible) ~= "function" then
			return true
		end
		local ok, result = pcall(isVisible)
		return not ok or result ~= false
	end

	local function currentLevel(): number
		return math.max(1, ctx.GetLevel("Press") or 1)
	end

	local function speedFactor(): number
		return 1 + (currentLevel() - 1) * 0.2
	end

	------------------------------------------------------------------
	-- Carte (fixe, contour toujours net) = mur de l'atelier + sol
	------------------------------------------------------------------
	local card = Create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true, -- rien ne dépasse jamais du cadre
		Parent = container,
	})
	UIUtil.Corner(card, 18)
	local cardStroke = UIUtil.Stroke(card, Theme.Colors.CardBorder, 2)
	-- Le fond de la carte = le sol ; le mur est une plaque arrondie en haut
	-- (ClipsDescendants ne coupe pas les coins arrondis : rien de carré ne
	-- doit toucher les coins de la carte)
	UIUtil.Gradient(card, seq(WHITE, rgb(150, 150, 150)), 90)

	local function box(props: { [string]: any }, radius: (number | UDim)?): Frame
		props.BorderSizePixel = 0
		local frame = Create("Frame", props)
		if radius then
			UIUtil.Corner(frame, radius)
		end
		return frame
	end

	local wall = box({ Name = "Wall", Size = UDim2.new(1, 0, 0, FLOOR_Y), BackgroundColor3 = WHITE, ZIndex = 1, Parent = card }, 18)
	local wallGradient = UIUtil.Gradient(wall, seq(TIERS[1].WallTop, TIERS[1].WallBottom), 90)
	local wallFoot = box({ Position = UDim2.fromOffset(0, FLOOR_Y - 20), Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = WHITE, ZIndex = 1, Parent = card })
	local wallFootGradient = UIUtil.Gradient(wallFoot, seq(TIERS[1].WallBottom, TIERS[1].WallBottom), 90)

	-- Joints de panneaux muraux (recolorés selon le palier)
	local seams: { Frame } = {}
	for i = 1, 5 do
		table.insert(seams, box({ Position = UDim2.fromOffset(i * 64 - 8, HEADER_H + 4), Size = UDim2.fromOffset(1, FLOOR_Y - HEADER_H - 4), BackgroundColor3 = TIERS[1].Seam, BackgroundTransparency = 0.5, ZIndex = 2, Parent = card }))
	end
	table.insert(seams, box({ Position = UDim2.fromOffset(0, 150), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = TIERS[1].Seam, BackgroundTransparency = 0.5, ZIndex = 2, Parent = card }))

	-- Sol (= fond de la carte) + bande de sécurité
	local floor = box({ Name = "Floor", Position = UDim2.fromOffset(0, FLOOR_Y), Size = UDim2.new(1, 0, 1, -FLOOR_Y), BackgroundTransparency = 1, ZIndex = 2, Parent = card })
	local floorTape = box({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = WHITE, ZIndex = 1, Parent = floor })
	local floorTapeGradient = UIUtil.Gradient(floorTape, stripes(40, rgb(255, 200, 30), INK), 0)
	-- Grille néon au sol (palier 10)
	local floorGrid = box({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 1, Parent = floor })
	for i = 1, 10 do
		box({ Position = UDim2.fromOffset(i * 34, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = rgb(255, 60, 200), BackgroundTransparency = 0.45, ZIndex = 1, Parent = floorGrid })
	end
	box({ Position = UDim2.fromOffset(20, 9), Size = UDim2.new(1, -40, 0, 1), BackgroundColor3 = rgb(0, 230, 255), BackgroundTransparency = 0.45, ZIndex = 1, Parent = floorGrid })

	-- La machine ("rig") : seule elle tremble au CRUNCH
	local rig = Create("Frame", {
		Name = "Rig",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = card,
	})

	local function rbox(props: { [string]: any }, radius: (number | UDim)?): Frame
		if props.Parent == nil then
			props.Parent = rig
		end
		return box(props, radius)
	end

	local function dot(parent: Instance, x: number, y: number, size: number, color: Color3, z: number): Frame
		return box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size, size), BackgroundColor3 = color, ZIndex = z, Parent = parent }, UDim.new(1, 0))
	end

	------------------------------------------------------------------
	-- En-tête : titre, pastille de palier, compteur, vitesse
	------------------------------------------------------------------
	local titleLabel = UIUtil.Label({
		Text = Locale.T("🗜️ PRESS"),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.fromOffset(92, 20),
		MaxTextSize = 16,
		ZIndex = 30,
		Parent = card,
	})
	local tierChip = box({
		Name = "TierChip",
		Position = UDim2.fromOffset(108, 7),
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = TIERS[1].Chip,
		ZIndex = 30,
		Parent = card,
	}, UDim.new(1, 0))
	local tierChipStroke = UIUtil.Stroke(tierChip, WHITE, 1.5, 0.35)
	UIUtil.Gradient(tierChip, seq(WHITE, rgb(215, 215, 215)), 90)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 9), Parent = tierChip })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 5),
		Parent = tierChip,
	})
	-- Pastille ronde "niveau" à gauche de la pilule
	local levelBadge = box({ Size = UDim2.fromOffset(15, 15), BackgroundColor3 = WHITE, LayoutOrder = 1, ZIndex = 31, Parent = tierChip }, UDim.new(1, 0))
	local levelBadgeLabel = Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = "",
		TextColor3 = INK,
		TextSize = 10,
		ZIndex = 32,
		Parent = levelBadge,
	})
	local tierChipLabel = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = WHITE,
		TextSize = 12,
		LayoutOrder = 2,
		ZIndex = 32,
		Parent = tierChip,
	})
	local tierChipScale = Create("UIScale", { Parent = tierChip })
	local counterLabel = UIUtil.Label({
		Text = "💥 0",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 4),
		Size = UDim2.fromOffset(70, 18),
		MaxTextSize = 16,
		ZIndex = 30,
		Parent = card,
	})
	local counterScale = Create("UIScale", { Parent = counterLabel })
	local speedLabel = UIUtil.Label({
		Text = "⚡ x1",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.Orange,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 21),
		Size = UDim2.fromOffset(60, 12),
		MaxTextSize = 11,
		ZIndex = 30,
		Parent = card,
	})

	------------------------------------------------------------------
	-- Manomètre gradué (aiguille = cadre pivot à faire tourner)
	------------------------------------------------------------------
	local function makeGauge(parent: Instance, cx: number, cy: number, size: number, z: number): (Frame, Frame, UIStroke)
		local face = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(size, size), BackgroundColor3 = WHITE, ZIndex = z, Parent = parent }, UDim.new(1, 0))
		UIUtil.Gradient(face, seq(WHITE, rgb(214, 218, 228)), 90)
		local bezel = UIUtil.Stroke(face, INK, size >= 20 and 2.5 or 2)
		local ticks = size >= 20 and 7 or 5
		for i = 0, ticks - 1 do
			local pivot = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Rotation = -120 + i * (240 / (ticks - 1)),
				ZIndex = z + 1,
				Parent = face,
			})
			local redZone = i >= ticks - 2
			box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.07), Size = UDim2.new(0, redZone and 2 or 1, 0.17, 0), BackgroundColor3 = redZone and RED or INK, ZIndex = z + 1, Parent = pivot })
		end
		local needle = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Rotation = -120,
			ZIndex = z + 2,
			Parent = face,
		})
		box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.new(0, 2, 0.46, 0), BackgroundColor3 = RED, ZIndex = z + 2, Parent = needle }, 1)
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.22, 0.22), BackgroundColor3 = INK, ZIndex = z + 3, Parent = face }, UDim.new(1, 0))
		-- Reflet de la vitre
		box({ Position = UDim2.fromScale(0.16, 0.1), Size = UDim2.fromScale(0.44, 0.22), BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, Rotation = -25, ZIndex = z + 3, Parent = face }, UDim.new(1, 0))
		return face, needle, bezel
	end

	------------------------------------------------------------------
	-- Flexible hydraulique (courbe de Bézier en petits segments)
	------------------------------------------------------------------
	local hoseSegments: { Frame } = {}
	local fittings: { Frame } = {}
	local function hose(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, thickness: number, z: number)
		local steps = 10
		local previous = p0
		for i = 1, steps do
			local t = i / steps
			local u = 1 - t
			local point = p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
			local delta = point - previous
			local middle = (point + previous) / 2
			local segment = rbox({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(middle.X, middle.Y),
				Size = UDim2.fromOffset(delta.Magnitude + thickness * 0.7, thickness),
				Rotation = math.deg(math.atan2(delta.Y, delta.X)),
				BackgroundColor3 = TIERS[1].Hose,
				ZIndex = z,
			}, UDim.new(1, 0))
			table.insert(hoseSegments, segment)
			previous = point
		end
		for _, p in ipairs({ p0, p3 }) do
			table.insert(fittings, rbox({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.X, p.Y), Size = UDim2.fromOffset(thickness + 4, thickness + 4), BackgroundColor3 = TIERS[1].Fitting, ZIndex = z + 1 }, 2))
		end
	end

	------------------------------------------------------------------
	-- Centrale hydraulique (à gauche) : moteur + réservoir + voyant d'huile
	------------------------------------------------------------------
	local motor = rbox({ Position = UDim2.fromOffset(16, 66), Size = UDim2.fromOffset(40, 26), BackgroundColor3 = WHITE, ZIndex = 3 }, 6)
	local motorGradient = UIUtil.Gradient(motor, stripes(8, rgb(120, 126, 140), rgb(90, 96, 110)), 90)
	local motorStroke = UIUtil.Stroke(motor, INK, 1.5, 0.3)
	rbox({ Position = UDim2.fromOffset(12, 72), Size = UDim2.fromOffset(6, 14), BackgroundColor3 = rgb(70, 74, 86), ZIndex = 3 }, 2)
	local tank = rbox({ Position = UDim2.fromOffset(12, 92), Size = UDim2.fromOffset(48, 62), BackgroundColor3 = WHITE, ZIndex = 3 }, 7)
	local tankGradient = UIUtil.Gradient(tank, cylinderSeq(TIERS[1].Frame), 0)
	local tankStroke = UIUtil.Stroke(tank, TIERS[1].Outline, 1.5, 0.2)
	-- Voyant d'huile (niveau qui bouge avec la pression)
	local sight = rbox({ Position = UDim2.fromOffset(40, 100), Size = UDim2.fromOffset(10, 46), BackgroundColor3 = rgb(30, 34, 44), ClipsDescendants = true, ZIndex = 4 }, 3)
	UIUtil.Stroke(sight, WHITE, 1, 0.5)
	local oil = rbox({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.6), BackgroundColor3 = rgb(255, 180, 40), ZIndex = 5, Parent = sight }, 2)
	UIUtil.Gradient(oil, seq(rgb(255, 230, 140), rgb(230, 130, 20)), 90)
	local _, tankNeedle = makeGauge(rig, 25, 114, 18, 5)
	-- Pieds du réservoir
	for _, x in ipairs({ 16, 50 }) do
		rbox({ Position = UDim2.fromOffset(x, 154), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = rgb(60, 64, 74), ZIndex = 3 }, 1)
	end
	-- Deux flexibles jusqu'au vérin
	hose(Vector2.new(28, 66), Vector2.new(24, 34), Vector2.new(96, 30), Vector2.new(MX - 30, 42), 5, 2)
	hose(Vector2.new(44, 66), Vector2.new(46, 46), Vector2.new(104, 44), Vector2.new(MX - 30, 50), 4, 2)

	------------------------------------------------------------------
	-- La presse
	------------------------------------------------------------------
	-- Colonnes (ombrées comme des cylindres) + pieds
	local pillars: { { Frame: Frame, Gradient: UIGradient, Stroke: UIStroke } } = {}
	for _, x in ipairs(PILLAR_X) do
		local pillar = rbox({ Position = UDim2.fromOffset(x, CROWN_Y + 4), Size = UDim2.fromOffset(PILLAR_W, FLOOR_Y - CROWN_Y - 8), BackgroundColor3 = WHITE, ZIndex = 2 }, 3)
		local gradient = UIUtil.Gradient(pillar, cylinderSeq(TIERS[1].Frame), 0)
		local stroke = UIUtil.Stroke(pillar, TIERS[1].Outline, 1, 0.35)
		table.insert(pillars, { Frame = pillar, Gradient = gradient, Stroke = stroke })
	end
	local feet: { Frame } = {}
	for _, x in ipairs(PILLAR_X) do
		local foot = rbox({ Position = UDim2.fromOffset(x - 6, FLOOR_Y - 7), Size = UDim2.fromOffset(PILLAR_W + 12, 8), BackgroundColor3 = WHITE, ZIndex = 3 }, 2)
		table.insert(feet, foot)
	end
	local feetGradients: { UIGradient } = {}
	for _, foot in ipairs(feet) do
		table.insert(feetGradients, UIUtil.Gradient(foot, beamSeq(TIERS[1].Frame), 90))
	end

	-- Vérin (chemise + fond) au-dessus de la traverse
	local housing = rbox({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, CYL_Y), Size = UDim2.fromOffset(60, CROWN_Y - CYL_Y + 4), BackgroundColor3 = WHITE, ZIndex = 4 }, 5)
	local housingGradient = UIUtil.Gradient(housing, cylinderSeq(TIERS[1].Frame), 0)
	local housingStroke = UIUtil.Stroke(housing, TIERS[1].Outline, 1.5, 0.25)
	local cap = rbox({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(MX, CYL_Y + 3), Size = UDim2.fromOffset(68, 6), BackgroundColor3 = WHITE, ZIndex = 5 }, 2)
	local capGradient = UIUtil.Gradient(cap, beamSeq(TIERS[1].Frame), 90)

	-- Traverse
	local crown = rbox({ Position = UDim2.fromOffset(MX - 114, CROWN_Y), Size = UDim2.fromOffset(228, CROWN_H), BackgroundColor3 = WHITE, ClipsDescendants = true, ZIndex = 6 }, 6)
	local crownGradient = UIUtil.Gradient(crown, beamSeq(TIERS[1].Frame), 90)
	local crownStroke = UIUtil.Stroke(crown, TIERS[1].Outline, 2, 0.1)
	local crownStripe = box({ Position = UDim2.fromOffset(8, 9), Size = UDim2.new(1, -16, 0, 8), BackgroundColor3 = WHITE, ZIndex = 7, Parent = crown }, 2)
	local crownStripeGradient = UIUtil.Gradient(crownStripe, stripes(22, TIERS[1].AccentA, TIERS[1].AccentB), 35)

	-- Tige chromée (derrière la traverse et le plateau)
	local rod = rbox({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, CROWN_Y + CROWN_H - 2), Size = UDim2.fromOffset(20, 10), BackgroundColor3 = WHITE, ZIndex = 3 })
	local rodGradient = UIUtil.Gradient(rod, cylinderSeq(TIERS[1].Chrome), 0)
	-- Joint (bague) sous la traverse
	local gland = rbox({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, CROWN_Y + CROWN_H - 1), Size = UDim2.fromOffset(30, 6), BackgroundColor3 = WHITE, ZIndex = 7 }, 2)
	local glandGradient = UIUtil.Gradient(gland, beamSeq(TIERS[1].Frame), 90)

	-- Plateau (guidé par les colonnes) + éclair blanc au choc
	local plate = rbox({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, PLATE_TOP), Size = UDim2.fromOffset(PLATE_W, PLATE_H), BackgroundColor3 = WHITE, ZIndex = 5 }, 4)
	local plateGradient = UIUtil.Gradient(plate, beamSeq(TIERS[1].Frame), 90)
	local plateStroke = UIUtil.Stroke(plate, TIERS[1].Outline, 1.5, 0.2)
	local plateStripe = box({ Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 6), BackgroundColor3 = WHITE, ZIndex = 6, Parent = plate }, 2)
	local plateStripeGradient = UIUtil.Gradient(plateStripe, stripes(16, TIERS[1].AccentA, TIERS[1].AccentB), 35)
	-- Semelle (plus sombre, en dessous)
	local die = box({ Position = UDim2.new(0, 10, 1, -5), Size = UDim2.new(1, -20, 0, 5), BackgroundColor3 = rgb(60, 64, 76), ZIndex = 6, Parent = plate }, 1)
	local guides: { Frame } = {}
	for _, side in ipairs({ -1, 1 }) do
		local guide = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * (PLATE_W / 2 + 1), 0.5, 0),
			Size = UDim2.fromOffset(PILLAR_W + 10, PLATE_H + 6),
			BackgroundColor3 = WHITE,
			ZIndex = 7,
			Parent = plate,
		}, 4)
		UIUtil.Stroke(guide, INK, 1, 0.5)
		table.insert(guides, guide)
	end
	local guideGradients: { UIGradient } = {}
	for _, guide in ipairs(guides) do
		table.insert(guideGradients, UIUtil.Gradient(guide, beamSeq(TIERS[1].Frame), 90))
	end
	local plateFlash = box({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 9, Parent = plate }, 4)

	-- Manomètre principal (sur la traverse, à droite du vérin)
	local _, mainNeedle, mainBezel = makeGauge(rig, MX + 62, CYL_Y + 9, 24, 8)
	-- Second manomètre (paliers >= 4)
	local gauge2, gauge2Needle = makeGauge(rig, MX + 92, CYL_Y + 11, 18, 8)

	-- Enclume (sous le tapis) avec bande d'accent
	local bolster = rbox({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MX, BELT_Y + BELT_H - 1), Size = UDim2.fromOffset(176, FLOOR_Y - BELT_Y - BELT_H + 1), BackgroundColor3 = WHITE, ZIndex = 4 }, 3)
	local bolsterGradient = UIUtil.Gradient(bolster, beamSeq(TIERS[1].Frame), 90)
	local bolsterStroke = UIUtil.Stroke(bolster, TIERS[1].Outline, 1.5, 0.2)
	local bolsterStripe = box({ Position = UDim2.fromOffset(6, 12), Size = UDim2.new(1, -12, 0, 8), BackgroundColor3 = WHITE, ZIndex = 5, Parent = bolster }, 2)
	local bolsterStripeGradient = UIUtil.Gradient(bolsterStripe, stripes(18, TIERS[1].AccentA, TIERS[1].AccentB), 35)
	local led = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Theme.Colors.Green, ZIndex = 6, Parent = bolster }, UDim.new(1, 0))

	------------------------------------------------------------------
	-- Tapis roulant : bande qui défile, châssis, rouleaux, pieds
	------------------------------------------------------------------
	local belt = rbox({ Position = UDim2.fromOffset(BELT_X0, BELT_Y), Size = UDim2.fromOffset(BELT_X1 - BELT_X0, BELT_H), BackgroundColor3 = rgb(40, 42, 50), ClipsDescendants = true, ZIndex = 6 }, 3)
	local BELT_PERIOD = 12
	local beltStripes = box({ Size = UDim2.new(1, BELT_PERIOD * 2, 1, 0), BackgroundColor3 = WHITE, ZIndex = 6, Parent = belt })
	UIUtil.Gradient(beltStripes, stripes(math.floor((BELT_X1 - BELT_X0 + BELT_PERIOD * 2) / (BELT_PERIOD / 2)), rgb(74, 78, 92), rgb(44, 46, 56)), 0)
	box({ Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, ZIndex = 7, Parent = belt })
	-- Châssis (devant les rouleaux) : à droite de l'enclume et petit bout à gauche
	local steel = rgb(96, 104, 120)
	local frames = {
		rbox({ Position = UDim2.fromOffset(MX + 88, BELT_Y + BELT_H), Size = UDim2.fromOffset(BELT_X1 - MX - 88, 12), BackgroundColor3 = WHITE, ZIndex = 7 }, 3),
		rbox({ Position = UDim2.fromOffset(BELT_X0, BELT_Y + BELT_H), Size = UDim2.fromOffset(MX - 88 - BELT_X0, 12), BackgroundColor3 = WHITE, ZIndex = 7 }, 3),
	}
	for _, f in ipairs(frames) do
		UIUtil.Gradient(f, beamSeq(steel), 90)
	end
	-- Rouleaux (moyeux qui tournent quand la bande avance)
	local rollers: { Frame } = {}
	for _, x in ipairs({ 74, MX + 102, MX + 130, MX + 158, MX + 186 }) do
		local hub = rbox({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, BELT_Y + BELT_H + 6), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = rgb(200, 206, 216), ZIndex = 8 }, UDim.new(1, 0))
		UIUtil.Stroke(hub, rgb(50, 54, 64), 1)
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -2, 0, 2), BackgroundColor3 = rgb(60, 64, 76), ZIndex = 9, Parent = hub })
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, -2), BackgroundColor3 = rgb(60, 64, 76), ZIndex = 9, Parent = hub })
		table.insert(rollers, hub)
	end
	-- Pieds du tapis + entretoise
	for _, x in ipairs({ MX + 110, BELT_X1 - 16 }) do
		rbox({ Position = UDim2.fromOffset(x, BELT_Y + BELT_H + 12), Size = UDim2.fromOffset(7, FLOOR_Y - BELT_Y - BELT_H - 12), BackgroundColor3 = rgb(80, 86, 100), ZIndex = 5 }, 1)
	end
	rbox({ Position = UDim2.fromOffset(MX + 110, FLOOR_Y - 12), Size = UDim2.fromOffset(BELT_X1 - 16 - MX - 110, 4), BackgroundColor3 = rgb(80, 86, 100), ZIndex = 5 }, 1)

	------------------------------------------------------------------
	-- Bac de récupération (à gauche, sous le bout du tapis)
	------------------------------------------------------------------
	rbox({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(BIN_X, BIN_TOP), Size = UDim2.fromOffset(BIN_W, FLOOR_Y - BIN_TOP), BackgroundColor3 = rgb(40, 90, 56), ZIndex = 3 }, 5)
	local binFront = rbox({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(BIN_X, BIN_TOP + 8), Size = UDim2.fromOffset(BIN_W + 4, FLOOR_Y - BIN_TOP - 8), BackgroundColor3 = rgb(70, 150, 96), ZIndex = 9 }, 5)
	UIUtil.Gradient(binFront, cylinderSeq(rgb(70, 150, 96)), 0)
	UIUtil.Stroke(binFront, rgb(30, 80, 46), 1.5)
	UIUtil.Label({
		Text = "♻️",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(26, 26),
		MaxTextSize = 22,
		ZIndex = 10,
		Parent = binFront,
	})
	rbox({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(BIN_X, BIN_TOP + 5), Size = UDim2.fromOffset(BIN_W + 8, 6), BackgroundColor3 = rgb(50, 120, 72), ZIndex = 10 }, 3)
	local binFill = rbox({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(BIN_X, BIN_TOP + 10), Size = UDim2.fromOffset(BIN_W - 12, 0), BackgroundColor3 = rgb(180, 140, 90), ZIndex = 4 }, PILL)
	local binScale = Create("UIScale", { Parent = binFront })

	------------------------------------------------------------------
	-- Onde de choc + éclair d'impact (réutilisés)
	------------------------------------------------------------------
	local shockRing = rbox({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX, BELT_Y), Size = UDim2.fromOffset(20, 6), BackgroundTransparency = 1, ZIndex = 11 }, UDim.new(1, 0))
	local shockStroke = UIUtil.Stroke(shockRing, WHITE, 3, 1)
	local impactFlash = rbox({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX, BELT_Y - 6), Size = UDim2.fromOffset(150, 40), BackgroundColor3 = rgb(255, 250, 220), BackgroundTransparency = 1, ZIndex = 11 }, UDim.new(1, 0))

	-- Décors propres au palier (reconstruits à chaque changement)
	local decorBack = Create("Frame", { Name = "DecorBack", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Parent = rig })
	local decorFront = Create("Frame", { Name = "DecorFront", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10, Parent = rig })

	------------------------------------------------------------------
	-- Pupitre (à droite) : bouton START (Presse turbo) ou panneau d'avertissement
	------------------------------------------------------------------
	local console = rbox({ Name = "Console", Position = UDim2.fromOffset(CONSOLE_X, CONSOLE_Y), Size = UDim2.fromOffset(CONSOLE_W, CONSOLE_H), BackgroundColor3 = WHITE, ZIndex = 12 }, 10)
	UIUtil.Gradient(console, seq(rgb(84, 90, 104), rgb(44, 48, 58)), 90)
	local consoleStroke = UIUtil.Stroke(console, INK, 2)
	for _, pos in ipairs({ Vector2.new(6, 6), Vector2.new(CONSOLE_W - 6, 6), Vector2.new(6, CONSOLE_H - 6), Vector2.new(CONSOLE_W - 6, CONSOLE_H - 6) }) do
		dot(console, pos.X, pos.Y, 4, rgb(170, 176, 190), 13)
	end
	-- Voyant d'état (vert = prêt, rouge = en pression)
	local statusLamp = dot(console, 14, 14, 8, Theme.Colors.Green, 14)
	UIUtil.Stroke(statusLamp, INK, 1)

	-- Sans turbo : panneau "Attention aux doigts"
	local warning = box({ Name = "Warning", Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 1, -32), BackgroundColor3 = rgb(255, 206, 40), ZIndex = 13, Parent = console }, 6)
	UIUtil.Stroke(warning, INK, 1.5)
	UIUtil.Label({
		Text = "⚠️",
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.new(1, 0, 0, 24),
		MaxTextSize = 22,
		ZIndex = 14,
		Parent = warning,
	})
	UIUtil.Label({
		Text = Locale.T("KEEP FINGERS CLEAR"),
		Font = Theme.Fonts.Title,
		TextColor3 = INK,
		Position = UDim2.fromOffset(4, 26),
		Size = UDim2.new(1, -8, 1, -30),
		MaxTextSize = 11,
		TextWrapped = true,
		ZIndex = 14,
		Parent = warning,
	})
	local consoleTitle = UIUtil.Label({
		Text = Locale.T("SAFETY"),
		Font = Theme.Fonts.Title,
		TextColor3 = rgb(220, 226, 236),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(22, 7),
		Size = UDim2.new(1, -30, 0, 14),
		MaxTextSize = 11,
		ZIndex = 14,
		Parent = console,
	})

	-- Avec turbo : bouton champignon rouge + jauge de recharge
	local startGroup = box({ Name = "StartGroup", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 13, Visible = false, Parent = console })
	local buttonBase = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CONSOLE_W / 2, 52), Size = UDim2.fromOffset(58, 58), BackgroundColor3 = rgb(30, 32, 40), ZIndex = 13, Parent = startGroup }, UDim.new(1, 0))
	UIUtil.Stroke(buttonBase, rgb(120, 126, 140), 1.5)
	local buttonSide = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CONSOLE_W / 2, 54), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = rgb(150, 16, 24), ZIndex = 14, Parent = startGroup }, UDim.new(1, 0))
	local startButton = Create("TextButton", {
		Name = "Start",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CONSOLE_W / 2, 49),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = RED,
		AutoButtonColor = false,
		Font = Enum.Font.LuckiestGuy,
		Text = "START",
		TextColor3 = WHITE,
		TextSize = 13,
		ZIndex = 15,
		Parent = startGroup,
	})
	UIUtil.Corner(startButton, UDim.new(1, 0))
	UIUtil.Stroke(startButton, rgb(120, 10, 18), 1.5)
	UIUtil.Gradient(startButton, seq(WHITE, rgb(200, 200, 200)), 90)
	local startTextStroke = UIUtil.Stroke(startButton, rgb(110, 0, 10), 1.2)
	startTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.08), Size = UDim2.fromScale(0.56, 0.22), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, ZIndex = 16, Parent = startButton }, UDim.new(1, 0))
	-- Jauge de recharge
	local chargeBack = box({ Position = UDim2.fromOffset(10, CONSOLE_H - 12), Size = UDim2.new(1, -20, 0, 5), BackgroundColor3 = rgb(24, 26, 32), ZIndex = 14, Parent = startGroup }, UDim.new(1, 0))
	local chargeFill = box({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Colors.Green, ZIndex = 15, Parent = chargeBack }, UDim.new(1, 0))
	local startScale = Create("UIScale", { Parent = startButton })

	local function refreshStartVisibility()
		local owned = ctx.HasFeature("PressStart")
		startGroup.Visible = owned
		warning.Visible = not owned
		consoleTitle.Text = owned and Locale.T("TURBO") or Locale.T("SAFETY")
	end
	refreshStartVisibility()
	if ctx.State.FeaturesChanged then
		ctx.Connect(ctx.State.FeaturesChanged, refreshStartVisibility)
	end

	------------------------------------------------------------------
	-- Réserves réutilisées : particules, bouffées de vapeur, cris
	------------------------------------------------------------------
	local fx = Create("Frame", { Name = "FX", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 13, Parent = rig })

	type Particle = {
		Frame: Frame,
		Corner: UICorner,
		Active: boolean,
		X: number,
		Y: number,
		VX: number,
		VY: number,
		Life: number,
		MaxLife: number,
		Size: number,
		Gravity: number,
		Spin: number,
		Streak: boolean,
	}
	local particles: { Particle } = {}
	local activeParticles = 0

	local function getParticle(): Particle?
		for _, particle in ipairs(particles) do
			if not particle.Active then
				return particle
			end
		end
		if #particles >= PARTICLE_MAX then
			return nil
		end
		local frame = box({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = WHITE, Visible = false, ZIndex = 13, Parent = fx })
		local corner = UIUtil.Corner(frame, 2)
		local particle: Particle = {
			Frame = frame, Corner = corner, Active = false,
			X = 0, Y = 0, VX = 0, VY = 0, Life = 0, MaxLife = 1, Size = 4, Gravity = 0, Spin = 0, Streak = false,
		}
		table.insert(particles, particle)
		return particle
	end

	local function emit(x: number, y: number, vx: number, vy: number, size: number, color: Color3, life: number, gravity: number, round: boolean, streak: boolean?)
		local particle = getParticle()
		if not particle then
			return
		end
		particle.Active = true
		activeParticles += 1
		particle.X, particle.Y, particle.VX, particle.VY = x, y, vx, vy
		particle.Life, particle.MaxLife = life, life
		particle.Size = size
		particle.Gravity = gravity
		particle.Spin = random:NextNumber(-600, 600)
		particle.Streak = streak == true
		local frame = particle.Frame
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0
		frame.Rotation = random:NextNumber(0, 90)
		frame.Size = UDim2.fromOffset(size, size)
		particle.Corner.CornerRadius = round and UDim.new(1, 0) or UDim.new(0, 2)
		frame.Position = UDim2.fromOffset(x, y)
		frame.Visible = true
	end

	local function updateParticles(dt: number)
		if activeParticles <= 0 then
			return
		end
		for _, particle in ipairs(particles) do
			if particle.Active then
				particle.Life -= dt
				if particle.Life <= 0 then
					particle.Active = false
					activeParticles -= 1
					particle.Frame.Visible = false
				else
					particle.VY += particle.Gravity * dt
					particle.X += particle.VX * dt
					particle.Y += particle.VY * dt
					local frame = particle.Frame
					frame.Position = UDim2.fromOffset(particle.X, particle.Y)
					local k = particle.Life / particle.MaxLife
					if particle.Streak then
						frame.Rotation = math.deg(math.atan2(particle.VY, particle.VX))
						frame.Size = UDim2.fromOffset(2 + particle.Size * k * 2.2, 2)
					else
						frame.Rotation += particle.Spin * dt
					end
					if k < 0.35 then
						frame.BackgroundTransparency = 1 - k / 0.35
					end
				end
			end
		end
	end

	type Puff = { Frame: Frame, Active: boolean, X: number, Y: number, DX: number, DY: number, Size: number, Life: number, MaxLife: number }
	local puffs: { Puff } = {}
	for _ = 1, PUFF_MAX do
		local frame = box({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = WHITE, BackgroundTransparency = 1, Visible = false, ZIndex = 12, Parent = fx }, UDim.new(1, 0))
		table.insert(puffs, { Frame = frame, Active = false, X = 0, Y = 0, DX = 0, DY = 0, Size = 10, Life = 0, MaxLife = 1 })
	end
	local activePuffs = 0

	local function puff(x: number, y: number, size: number, dx: number, dy: number, color: Color3?)
		for _, p in ipairs(puffs) do
			if not p.Active then
				p.Active = true
				activePuffs += 1
				p.X, p.Y, p.DX, p.DY, p.Size = x, y, dx, dy, size
				p.Life, p.MaxLife = 0.75, 0.75
				p.Frame.BackgroundColor3 = color or WHITE
				p.Frame.Visible = true
				return
			end
		end
	end

	local function updatePuffs(dt: number)
		if activePuffs <= 0 then
			return
		end
		for _, p in ipairs(puffs) do
			if p.Active then
				p.Life -= dt
				if p.Life <= 0 then
					p.Active = false
					activePuffs -= 1
					p.Frame.Visible = false
				else
					local t = easeOut(1 - p.Life / p.MaxLife)
					local size = p.Size * (1 + 1.3 * t)
					p.Frame.Position = UDim2.fromOffset(p.X + p.DX * t, p.Y + p.DY * t)
					p.Frame.Size = UDim2.fromOffset(size, size)
					p.Frame.BackgroundTransparency = 0.3 + 0.7 * t
				end
			end
		end
	end

	-- Cris "CRUNCH!" (2 étiquettes utilisées à tour de rôle)
	type Shout = { Label: TextLabel, Stroke: UIStroke, Scale: UIScale, Life: number, Y: number }
	local shouts: { Shout } = {}
	for _ = 1, SHOUT_COUNT do
		local label = UIUtil.Label({
			Text = "",
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = rgb(255, 220, 50),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(MX, 130),
			Size = UDim2.fromOffset(230, 40),
			MaxTextSize = 36,
			Visible = false,
			ZIndex = 20,
			Parent = card,
		})
		local stroke = UIUtil.Stroke(label, INK, 3)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		local scale = Create("UIScale", { Parent = label })
		table.insert(shouts, { Label = label, Stroke = stroke, Scale = scale, Life = 0, Y = 130 })
	end
	local shoutIndex = 0

	local function shout(text: string, color: Color3?, y: number?)
		shoutIndex = shoutIndex % SHOUT_COUNT + 1
		local s = shouts[shoutIndex]
		local long = (utf8.len(text) or #text) > 12
		s.Y = y or 128
		s.Life = 1
		local label = s.Label
		label.Text = text
		label.TextColor3 = color or rgb(255, 220, 50)
		label.Size = UDim2.fromOffset(long and 250 or 220, long and 26 or 40)
		local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			constraint.MaxTextSize = long and 22 or 36
		end
		label.Rotation = random:NextNumber(-8, 8)
		label.Position = UDim2.fromOffset(MX, s.Y)
		label.TextTransparency = 0
		s.Stroke.Transparency = 0
		s.Scale.Scale = 0.3
		label.Visible = true
	end

	local function updateShouts(dt: number)
		for _, s in ipairs(shouts) do
			if s.Life > 0 then
				s.Life -= dt
				local age = 1 - s.Life
				if s.Life <= 0 then
					s.Label.Visible = false
				else
					-- Apparition élastique puis montée en fondu
					s.Scale.Scale = age < 0.2 and 0.3 + easeOutBack(age / 0.2) * 0.8 or 1.1
					if age > 0.55 then
						local k = (age - 0.55) / 0.45
						s.Label.Position = UDim2.fromOffset(MX, s.Y - 26 * k)
						s.Label.TextTransparency = k
						s.Stroke.Transparency = k
					end
				end
			end
		end
	end

	------------------------------------------------------------------
	-- Paliers : couleurs + décors
	------------------------------------------------------------------
	local tierIndex = 0
	local shownLevel = 0
	local tierAnim = {
		Twinkles = {} :: { TextLabel },
		Beacon = nil :: Frame?,
		BeaconBeam = nil :: Frame?,
		Shine = nil :: Frame?,
		Glow = nil :: Frame?,
		Digital = nil :: TextLabel?,
		DigitalValue = -1,
		SteamTimer = 1,
		NeonStrokes = {} :: { UIStroke },
	}

	local function buildDecor(index: number)
		local style = TIERS[index]
		decorBack:ClearAllChildren()
		decorFront:ClearAllChildren()
		if tierAnim.Shine then
			tierAnim.Shine:Destroy()
		end
		tierAnim.Twinkles = {}
		tierAnim.Beacon = nil
		tierAnim.BeaconBeam = nil
		tierAnim.Shine = nil
		tierAnim.Glow = nil
		tierAnim.Digital = nil
		tierAnim.DigitalValue = -1
		tierAnim.NeonStrokes = {}

		if style.Wood then
			-- Veinage du bois sur les colonnes
			for _, x in ipairs(PILLAR_X) do
				for _, gx in ipairs({ 5, 11 }) do
					box({ Position = UDim2.fromOffset(x + gx, CROWN_Y + 30), Size = UDim2.fromOffset(1, FLOOR_Y - CROWN_Y - 50), BackgroundColor3 = darker(style.Frame, 0.3), BackgroundTransparency = 0.5, ZIndex = 1, Parent = decorFront })
				end
			end
		end
		if style.Rope then
			-- Cordes enroulées sur les colonnes
			for _, x in ipairs(PILLAR_X) do
				for _, y in ipairs({ 96, 150 }) do
					local rope = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + PILLAR_W / 2, y), Size = UDim2.fromOffset(PILLAR_W + 6, 10), BackgroundColor3 = WHITE, ZIndex = 2, Parent = decorFront }, 3)
					UIUtil.Gradient(rope, stripes(7, rgb(232, 204, 146), rgb(184, 146, 90)), 60)
				end
			end
			for _, x in ipairs({ MX - 104, MX - 60, MX + 60, MX + 104 }) do
				dot(decorFront, x, CROWN_Y + 4, 4, style.Bolt, 3)
			end
		end
		if style.Bands then
			-- Ferrures sur les colonnes et aux bouts de la traverse
			for _, x in ipairs(PILLAR_X) do
				for _, y in ipairs({ 100, 160, 214 }) do
					local band = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + PILLAR_W / 2, y), Size = UDim2.fromOffset(PILLAR_W + 4, 7), BackgroundColor3 = WHITE, ZIndex = 2, Parent = decorFront }, 1)
					UIUtil.Gradient(band, beamSeq(rgb(84, 86, 96)), 90)
					dot(band, (PILLAR_W + 4) / 2, 3.5, 3, rgb(170, 174, 184), 3)
				end
			end
		end
		if style.Rivets then
			for i = 0, 8 do
				dot(decorFront, MX - 104 + i * 26, CROWN_Y + 4, 3, style.Bolt, 3)
				dot(decorFront, MX - 104 + i * 26, CROWN_Y + CROWN_H - 4, 3, style.Bolt, 3)
			end
		end
		if style.Beacon then
			-- Gyrophare sur la traverse (à gauche)
			local baseColor = style.Neon and rgb(255, 60, 200) or rgb(255, 150, 20)
			box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(36, 67), Size = UDim2.fromOffset(14, 4), BackgroundColor3 = rgb(50, 52, 60), ZIndex = 3, Parent = decorFront }, 1)
			local beacon = box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(36, 64), Size = UDim2.fromOffset(12, 10), BackgroundColor3 = baseColor, ZIndex = 3, Parent = decorFront }, 5)
			UIUtil.Gradient(beacon, seq(WHITE, rgb(210, 210, 210)), 90)
			local beam = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(36, 59), Size = UDim2.fromOffset(34, 5), BackgroundColor3 = baseColor, BackgroundTransparency = 0.5, ZIndex = 2, Parent = decorFront }, UDim.new(1, 0))
			tierAnim.Beacon = beacon
			tierAnim.BeaconBeam = beam
		end
		if style.Digital then
			-- Afficheur numérique de pression sur la traverse
			local screen = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX + 70, CROWN_Y + CROWN_H / 2), Size = UDim2.fromOffset(44, 16), BackgroundColor3 = rgb(10, 16, 12), ZIndex = 4, Parent = decorFront }, 3)
			UIUtil.Stroke(screen, rgb(120, 130, 140), 1)
			tierAnim.Digital = Create("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Mono,
				Text = "0000",
				TextColor3 = rgb(80, 255, 140),
				TextSize = 11,
				ZIndex = 5,
				Parent = screen,
			})
		end
		if style.Shine then
			-- Reflet qui passe sur la traverse
			local shineFrame = box({ Position = UDim2.fromOffset(-40, 3), Size = UDim2.new(0, 34, 1, -6), BackgroundColor3 = WHITE, ZIndex = 8, Parent = crown })
			local gradient = UIUtil.Gradient(shineFrame, ColorSequence.new(WHITE), 20)
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			tierAnim.Shine = shineFrame
		end
		if style.Sparkle then
			for _, pos in ipairs({ Vector2.new(MX - 120, 110), Vector2.new(MX + 112, 132), Vector2.new(MX - 106, 180), Vector2.new(MX + 30, 42), Vector2.new(MX - 30, 116) }) do
				local star = UIUtil.Label({
					Text = "✦",
					Font = Theme.Fonts.Title,
					TextColor3 = style.Sparkle,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(pos.X, pos.Y),
					Size = UDim2.fromOffset(14, 14),
					MaxTextSize = 14,
					ZIndex = 4,
					Parent = decorFront,
				})
				table.insert(tierAnim.Twinkles, star)
			end
		end
		if style.Gems then
			-- Rubis sur la traverse et l'enclume
			for _, x in ipairs({ MX - 90, MX - 30, MX + 30 }) do
				local gem = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, CROWN_Y + CROWN_H / 2), Size = UDim2.fromOffset(9, 9), Rotation = 45, BackgroundColor3 = rgb(220, 20, 60), ZIndex = 4, Parent = decorFront }, 2)
				UIUtil.Stroke(gem, rgb(255, 220, 120), 1.5)
				UIUtil.Gradient(gem, seq(rgb(255, 180, 190), rgb(200, 200, 200)), 45)
			end
			for _, x in ipairs({ MX - 70, MX + 70 }) do
				local gem = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, FLOOR_Y - 9), Size = UDim2.fromOffset(8, 8), Rotation = 45, BackgroundColor3 = rgb(220, 20, 60), ZIndex = 4, Parent = decorFront }, 2)
				UIUtil.Stroke(gem, rgb(255, 220, 120), 1.5)
			end
		end
		if style.Crystal then
			-- Cristaux aux pieds des colonnes et sur la traverse
			for _, x in ipairs({ PILLAR_X[1] - 6, PILLAR_X[2] + PILLAR_W + 6 }) do
				for j, h in ipairs({ 16, 11 }) do
					local shard = box({
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromOffset(x + (j - 1.5) * 7, FLOOR_Y - 6),
						Size = UDim2.fromOffset(7, h),
						Rotation = (j - 1.5) * 24,
						BackgroundColor3 = rgb(180, 240, 255),
						BackgroundTransparency = 0.1,
						ZIndex = 4,
						Parent = decorFront,
					}, 3)
					UIUtil.Gradient(shard, seq(WHITE, rgb(120, 200, 255)), 90)
					local stroke = UIUtil.Stroke(shard, style.Neon and style.Outline or WHITE, 1, 0.2)
					if style.Neon then
						table.insert(tierAnim.NeonStrokes, stroke)
					end
				end
			end
		end
		if style.Neon then
			-- Lueur sous l'enclume
			tierAnim.Glow = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX, FLOOR_Y), Size = UDim2.fromOffset(230, 12), BackgroundColor3 = rgb(0, 230, 255), BackgroundTransparency = 0.5, ZIndex = 1, Parent = decorBack }, UDim.new(1, 0))
		end
	end

	local function applyTier(index: number)
		local style = TIERS[index]
		card.BackgroundColor3 = style.Floor
		local footTop = style.WallTop:Lerp(style.WallBottom, (FLOOR_Y - 20) / FLOOR_Y)
		wallGradient.Color = seq(style.WallTop, style.WallBottom)
		wallFootGradient.Color = seq(footTop, style.WallBottom)
		cardStroke.Color = style.CardStroke
		for _, seam in ipairs(seams) do
			seam.BackgroundColor3 = style.Seam
		end
		floorGrid.Visible = style.Neon == true
		floorTapeGradient.Color = style.Neon and stripes(40, rgb(0, 230, 255), rgb(255, 60, 200)) or stripes(40, rgb(255, 200, 30), INK)
		titleLabel.TextColor3 = style.Title
		counterLabel.TextColor3 = style.Title
		speedLabel.TextColor3 = style.Dark and rgb(255, 190, 90) or Theme.Colors.Orange

		local outlineT = style.Neon and 0 or 0.3
		local outlineW = style.Neon and 2 or 1
		for _, pillar in ipairs(pillars) do
			pillar.Gradient.Color = style.Wood and stripes(5, lighter(style.Frame, 0.12), darker(style.Frame, 0.1)) or cylinderSeq(style.Frame)
			pillar.Gradient.Rotation = 0
			pillar.Stroke.Color = style.Outline
			pillar.Stroke.Thickness = outlineW
			pillar.Stroke.Transparency = outlineT
		end
		for _, gradient in ipairs(feetGradients) do
			gradient.Color = beamSeq(style.Frame)
		end
		housingGradient.Color = cylinderSeq(style.Frame)
		housingStroke.Color = style.Outline
		capGradient.Color = beamSeq(darker(style.Frame, 0.1))
		crownGradient.Color = style.Wood and stripes(6, lighter(style.Frame, 0.1), darker(style.Frame, 0.08)) or beamSeq(style.Frame)
		crownGradient.Rotation = 90
		crownStroke.Color = style.Outline
		crownStroke.Thickness = style.Neon and 2.5 or 2
		crownStripeGradient.Color = stripes(22, style.AccentA, style.AccentB)
		rodGradient.Color = cylinderSeq(style.Chrome)
		glandGradient.Color = beamSeq(darker(style.Frame, 0.15))
		plateGradient.Color = beamSeq(style.Frame)
		plateStroke.Color = style.Outline
		plateStroke.Thickness = style.Neon and 2 or 1.5
		plateStripeGradient.Color = stripes(16, style.AccentA, style.AccentB)
		for _, gradient in ipairs(guideGradients) do
			gradient.Color = beamSeq(darker(style.Frame, 0.12))
		end
		die.BackgroundColor3 = darker(style.Frame, 0.55)
		bolsterGradient.Color = beamSeq(darker(style.Frame, 0.05))
		bolsterStroke.Color = style.Outline
		bolsterStripeGradient.Color = stripes(18, style.AccentA, style.AccentB)
		motorGradient.Color = stripes(8, lighter(style.Frame, 0.1), darker(style.Frame, 0.25))
		motorStroke.Color = style.Outline
		tankGradient.Color = cylinderSeq(darker(style.Frame, 0.05))
		tankStroke.Color = style.Outline
		for _, segment in ipairs(hoseSegments) do
			segment.BackgroundColor3 = style.Hose
		end
		for _, fitting in ipairs(fittings) do
			fitting.BackgroundColor3 = style.Fitting
		end
		gauge2.Visible = style.Gauge2 == true
		mainBezel.Color = style.Neon and style.Outline or INK
		consoleStroke.Color = style.Neon and style.Outline or INK
		tierChip.BackgroundColor3 = style.Chip
		tierChipLabel.TextColor3 = style.ChipText
		tierChipStroke.Color = style.Dark and style.Chip or WHITE
		buildDecor(index)
		if style.Neon then
			for _, pillar in ipairs(pillars) do
				table.insert(tierAnim.NeonStrokes, pillar.Stroke)
			end
			table.insert(tierAnim.NeonStrokes, crownStroke)
			table.insert(tierAnim.NeonStrokes, plateStroke)
			table.insert(tierAnim.NeonStrokes, bolsterStroke)
			table.insert(tierAnim.NeonStrokes, housingStroke)
		end
	end

	-- Petit flash blanc sur toute la carte (changement de palier)
	local function flashCard()
		local flash = box({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.2,
			ZIndex = 40,
			Parent = card,
		}, 18)
		UIUtil.Tween(flash, 0.6, { BackgroundTransparency = 1 })
		Debris:AddItem(flash, 0.65)
	end

	local function refreshLevel(celebrate: boolean)
		local level = currentLevel()
		if level == shownLevel then
			return
		end
		local newTier = tierForLevel(level)
		local tierChanged = newTier ~= tierIndex
		shownLevel = level
		tierIndex = newTier
		local style = TIERS[newTier]
		levelBadgeLabel.Text = style.Icon
		tierChipLabel.Text = Locale.T("Lv. %s", tostring(level)) .. " · " .. Locale.Pick(style.Name)
		if tierChanged then
			applyTier(newTier)
		end
		if celebrate then
			tierChipScale.Scale = 1.35
			UIUtil.Tween(tierChipScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			if tierChanged then
				flashCard()
				ctx.Sound.Play("Buy", 1.1)
				if effectsOn() then
					for _ = 1, 18 do
						local angle = random:NextNumber(0, math.pi * 2)
						local speed = random:NextNumber(80, 200)
						emit(MX, 130, math.cos(angle) * speed, math.sin(angle) * speed - 60, random:NextInteger(4, 7), pickFrom({ style.Chip, style.AccentA, WHITE }, random), random:NextNumber(0.6, 1), 260, false)
					end
				end
				shout(style.Icon .. " " .. Locale.Pick(style.Shout), style.Chip, 140)
			end
		end
	end

	------------------------------------------------------------------
	-- Objets : construction
	------------------------------------------------------------------
	local kit: Kit = {
		Part = function(parent, x, y, w, h, color, z, radius, transparency)
			local frame = box({
				Position = UDim2.fromScale(x, y),
				Size = UDim2.fromScale(w, h),
				BackgroundColor3 = color,
				BackgroundTransparency = transparency or 0,
				ZIndex = z or 2,
				Parent = parent,
			})
			if radius then
				UIUtil.Corner(frame, radius)
			end
			return frame
		end,
		Gradient = function(frame, color, rotation)
			return UIUtil.Gradient(frame, color, rotation or 0)
		end,
		Stroke = function(frame, color, thickness, transparency)
			return UIUtil.Stroke(frame, color, thickness or 1, transparency or 0)
		end,
		Random = random,
	}

	type Entry = {
		Holder: Frame,
		W: number,
		H: number,
		X: number,
		Words: Words,
		Colors: { Color3 },
		Main: Color3,
		Special: string?,
		Wobble: number,
		Built: Built?,
		Label: TextLabel?,
		Splat: Frame?,
		Icon: string?,
		NoPile: boolean?,
	}

	local lastKind = ""

	local function newEntry(x: number): Entry
		local style = TIERS[math.max(1, tierIndex)]
		local roll = random:NextNumber()
		local drawn: Drawn? = nil
		local emoji: EmojiItem? = nil
		for _ = 1, 3 do
			roll = random:NextNumber()
			drawn, emoji = nil, nil
			if roll < 0.22 and #style.Drawn > 0 then
				drawn = DRAWN[pickFrom(style.Drawn, random)]
			elseif roll < 0.36 and #style.Emoji > 0 then
				emoji = pickFrom(style.Emoji, random)
			elseif roll < 0.86 then
				local target = random:NextNumber() * GENERAL_WEIGHT
				for _, def in ipairs(GENERAL) do
					target -= def.Weight
					if target <= 0 then
						drawn = def
						break
					end
				end
				drawn = drawn or GENERAL[1]
			else
				emoji = pickFrom(EMOJI_ITEMS, random)
			end
			local kind = drawn and drawn.Id or (emoji and emoji.Icon) or ""
			if kind ~= lastKind then
				lastKind = kind
				break
			end
		end

		local holder = box({
			Name = "Item",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(x, BELT_Y),
			Size = UDim2.fromOffset(60, 60),
			BackgroundTransparency = 1,
			ZIndex = 7,
			Parent = rig,
		})
		if drawn then
			holder.Size = UDim2.fromOffset(drawn.W, drawn.H)
			local built = drawn.Build(kit, holder)
			return {
				Holder = holder, W = drawn.W, H = drawn.H, X = x, Words = drawn.Words,
				Colors = built.Colors, Main = built.Main, Special = drawn.Special, Wobble = drawn.Wobble or 1.5, Built = built,
			}
		end
		local item = emoji or EMOJI_ITEMS[1]
		local size = 58
		holder.Size = UDim2.fromOffset(size, size)
		local label = UIUtil.Label({ Text = item.Icon, Size = UDim2.fromScale(1, 1), MaxTextSize = 56, ZIndex = 3, Parent = holder })
		local splat = box({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = item.Color, Visible = false, ZIndex = 2, Parent = holder }, PILL)
		UIUtil.Stroke(splat, darker(item.Color, 0.35), 1.5)
		UIUtil.Gradient(splat, SHADE_V, 90)
		return {
			Holder = holder, W = size, H = size, X = x, Words = item.Words,
			Colors = { item.Color, lighter(item.Color, 0.35) }, Main = item.Color, Wobble = 1.5,
			Label = label, Splat = splat, Icon = item.Icon,
		}
	end

	local function placeEntry(entry: Entry, x: number)
		entry.X = x
		entry.Holder.Position = UDim2.fromOffset(x, BELT_Y)
	end

	------------------------------------------------------------------
	-- Bac : la galette tombe dedans
	------------------------------------------------------------------
	local binCount = 0
	local function dropIntoBin(entry: Entry)
		local holder = entry.Holder
		if entry.NoPile or not holder.Parent then
			holder:Destroy()
			return
		end
		holder.ZIndex = 5
		UIUtil.Tween(holder, 0.35, {
			Position = UDim2.fromOffset(BIN_X, BIN_TOP + 26),
			Size = UDim2.fromOffset(BIN_W - 10, 7),
			Rotation = random:NextNumber(-25, 25),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.36, function()
			holder:Destroy()
			if not ctx.IsAlive() then
				return
			end
			binCount += 1
			local level = binCount % 6
			binFill.BackgroundColor3 = darker(entry.Main, 0.1)
			binFill.Size = UDim2.fromOffset(BIN_W - 12, level * 2 + (level > 0 and 4 or 0))
			binScale.Scale = 1.06
			UIUtil.Tween(binScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			if effectsOn() then
				puff(BIN_X, BIN_TOP + 4, 10, 0, -14, rgb(230, 230, 230))
			end
			if level == 0 then
				-- Bac plein : il tasse tout d'un coup
				binFill.Size = UDim2.fromOffset(BIN_W - 12, 16)
				UIUtil.Tween(binFill, 0.4, { Size = UDim2.fromOffset(BIN_W - 12, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
	end

	------------------------------------------------------------------
	-- Effets du CRUNCH
	------------------------------------------------------------------
	local shakeTime = 0
	local shakePower = 1

	local function crumbs(colors: { Color3 }, count: number, y: number)
		for _ = 1, count do
			local color = colors[random:NextInteger(1, #colors)]
			if random:NextNumber() < 0.15 then
				color = WHITE
			end
			local dir = random:NextNumber() < 0.5 and -1 or 1
			emit(MX + random:NextNumber(-34, 34), y, dir * random:NextNumber(60, 220), -random:NextNumber(80, 260), random:NextInteger(3, 8), color, random:NextNumber(0.55, 0.9), 700, random:NextNumber() < 0.4)
		end
	end

	local function sparks(colors: { Color3 }, count: number)
		for _ = 1, count do
			local angle = random:NextNumber(-math.pi * 0.95, -math.pi * 0.05)
			local speed = random:NextNumber(160, 320)
			emit(MX + random:NextNumber(-60, 60), BELT_Y - 4, math.cos(angle) * speed, math.sin(angle) * speed, 5, colors[random:NextInteger(1, #colors)], random:NextNumber(0.25, 0.45), 320, false, true)
		end
	end

	local function shockwave(color: Color3)
		shockRing.Size = UDim2.fromOffset(40, 8)
		shockStroke.Color = color
		shockStroke.Transparency = 0
		UIUtil.Tween(shockRing, 0.35, { Size = UDim2.fromOffset(290, 34) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		UIUtil.Tween(shockStroke, 0.35, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		impactFlash.BackgroundTransparency = 0.35
		UIUtil.Tween(impactFlash, 0.25, { BackgroundTransparency = 1 })
	end

	------------------------------------------------------------------
	-- Cycle de la presse (machine à états, pilotée par OnRender)
	------------------------------------------------------------------
	local phase = "Idle"
	local phaseTime = 0
	local phaseDuration = 0
	local queue: { Entry } = {}
	local current: Entry? = nil -- objet sous la presse
	local outgoing: Entry? = nil -- galette qui repart sur le tapis
	local plateY = PLATE_TOP
	local phaseStartPlate = PLATE_TOP
	local squeezeDepth = 0
	local turbo = false
	local pendingTurbo = false
	local crushed = 0
	local pressure = 0
	local cooldownEnd = 0
	local shownCooldown = ""
	local beltOffset = 0
	local beltBase = 0
	local factor = 1
	type Mover = { Entry: Entry, From: number, To: number }
	local movers: { Mover } = {}

	local function setPhase(name: string)
		phase = name
		phaseTime = 0
		phaseStartPlate = plateY
		local speedMul = factor
		if turbo and (name == "Descend" or name == "Squeeze") then
			speedMul *= 4
		end
		phaseDuration = (DURATIONS[name] or 0.5) / speedMul
	end

	local function dropIn(entry: Entry)
		-- Arrive par le haut (trémie) et rebondit sur le tapis
		entry.Holder.Position = UDim2.fromOffset(entry.X, BELT_Y - 60)
		UIUtil.Tween(entry.Holder, 0.45, { Position = UDim2.fromOffset(entry.X, BELT_Y) }, Enum.EasingStyle.Bounce)
	end

	-- Le tapis avance d'un pas : galette -> sortie, file -> presse
	local function loadNext()
		factor = speedFactor()
		speedLabel.Text = "⚡ x" .. (math.floor(factor * 10 + 0.5) / 10)
		table.clear(movers)
		if outgoing then
			table.insert(movers, { Entry = outgoing, From = MX, To = EXIT_X })
		end
		while #queue < 1 do
			local entry = newEntry(SLOT_X[#queue + 1])
			table.insert(queue, entry)
		end
		current = table.remove(queue, 1)
		if current then
			table.insert(movers, { Entry = current, From = current.X, To = MX })
		end
		for i, entry in ipairs(queue) do
			table.insert(movers, { Entry = entry, From = entry.X, To = SLOT_X[i] })
		end
		beltBase = beltOffset
		setPhase("Load")
	end

	local function finishLoad()
		for _, mover in ipairs(movers) do
			placeEntry(mover.Entry, mover.To)
		end
		table.clear(movers)
		if outgoing then
			dropIntoBin(outgoing)
			outgoing = nil
		end
		-- La file se remplit par le haut
		while #queue < #SLOT_X do
			local entry = newEntry(SLOT_X[#queue + 1])
			table.insert(queue, entry)
			dropIn(entry)
		end
	end

	local function itemHeight(): number
		if current then
			return current.Holder.Size.Y.Offset
		end
		return 0
	end

	-- Le moment CRUNCH
	local function onCrunch()
		local entry = current
		if not entry then
			return
		end
		local effects = effectsOn()
		local style = TIERS[math.max(1, tierIndex)]
		crushed += 1
		counterLabel.Text = "💥 " .. crushed
		counterScale.Scale = 1.35
		UIUtil.Tween(counterScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Crush", random:NextNumber(0.85, 1.15) * (turbo and 0.85 or 1))

		-- Secousse de la machine (plus forte aux paliers élevés et en turbo)
		shakeTime = turbo and 0.38 or 0.26
		shakePower = 1 + (tierIndex - 1) * 0.06 + (turbo and 0.4 or 0)

		local words = Locale.Pick(entry.Words)
		local word = words[random:NextInteger(1, #words)]
		if turbo then
			word = "TURBO " .. word
		end
		shout(word, turbo and rgb(255, 90, 60) or nil, nil)

		plateFlash.BackgroundTransparency = 0.15
		UIUtil.Tween(plateFlash, 0.3, { BackgroundTransparency = 1 })
		shockwave(style.Neon and rgb(0, 230, 255) or WHITE)

		local debrisColors = table.clone(entry.Colors)
		for _, color in ipairs(style.Debris) do
			table.insert(debrisColors, color)
		end
		crumbs(debrisColors, effects and (turbo and 18 or 13) or 4, BELT_Y - 10)
		if effects then
			-- Poussière au ras du tapis + vapeur du vérin
			for _, dir in ipairs({ -1, 1 }) do
				puff(MX + dir * 64, BELT_Y - 6, 12, dir * 46, -16, style.Dark and rgb(170, 170, 190) or rgb(236, 236, 240))
			end
			if style.Steam or style.Neon then
				puff(MX + 34, CYL_Y + 8, 10, 26, -18)
				puff(MX - 34, CYL_Y + 8, 10, -26, -18)
			end
			if style.Sparkle then
				sparks({ style.Sparkle, WHITE }, style.Neon and 14 or 9)
			elseif turbo or tierIndex >= 3 then
				sparks({ rgb(255, 200, 60), rgb(255, 250, 200) }, turbo and 8 or 4)
			end
		end

		if entry.Label then
			entry.Label.Visible = false
			if entry.Splat then
				entry.Splat.Visible = true
			end
			if effects then
				-- Morceaux de l'emoji qui s'envolent
				for _ = 1, 2 do
					local bit = UIUtil.Label({
						Text = entry.Icon or "",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(MX, BELT_Y - 12),
						Size = UDim2.fromOffset(20, 20),
						MaxTextSize = 20,
						ZIndex = 12,
						Parent = fx,
					})
					UIUtil.Tween(bit, 0.55, {
						Position = UDim2.fromOffset(MX + random:NextNumber(-110, 110), BELT_Y - random:NextNumber(40, 90)),
						Rotation = random:NextNumber(-360, 360),
						TextTransparency = 1,
					}, Enum.EasingStyle.Quad)
					Debris:AddItem(bit, 0.6)
				end
			end
		end
		local built = entry.Built
		if built and built.Fillings then
			-- Macarons : la crème déborde
			for _, filling in ipairs(built.Fillings) do
				UIUtil.Tween(filling, 0.15, { Size = UDim2.fromScale(1.14, 0.3) }, Enum.EasingStyle.Back)
			end
		end
		if entry.Special == "Melon" and built and built.Body then
			-- Pastèque : l'intérieur rouge apparaît
			if built.Gradient then
				built.Gradient.Enabled = false
			end
			built.Body.BackgroundColor3 = rgb(236, 60, 72)
			if built.Stroke then
				built.Stroke.Color = rgb(40, 132, 48)
				built.Stroke.Thickness = 3
			end
			if effects then
				crumbs({ rgb(30, 30, 30), rgb(255, 90, 100) }, 6, BELT_Y - 8)
			end
		elseif entry.Special == "Pop" then
			entry.Holder.Visible = false
			entry.NoPile = true
			if effects then
				for _ = 1, 14 do
					emit(MX + random:NextNumber(-20, 20), BELT_Y - 20, random:NextNumber(-200, 200), -random:NextNumber(120, 300), 5, pickFrom(entry.Colors, random), random:NextNumber(0.7, 1.1), 420, false)
				end
			end
		elseif entry.Special == "Paint" and effects then
			for _ = 1, 10 do
				emit(MX + random:NextNumber(-30, 30), BELT_Y - 8, random:NextNumber(-240, 240), -random:NextNumber(40, 200), random:NextInteger(5, 9), entry.Main, random:NextNumber(0.5, 0.8), 600, true)
			end
		end
	end

	local function onRise()
		local entry = current
		current = nil
		if not entry then
			return
		end
		if entry.Special == "Sponge" then
			-- L'éponge reprend sa forme... puis repart quand même
			UIUtil.Tween(entry.Holder, 0.4, { Size = UDim2.fromOffset(entry.W, entry.H) }, Enum.EasingStyle.Back)
			shout(Locale.T("...and it's back"), nil, nil)
		end
		outgoing = entry
	end

	------------------------------------------------------------------
	-- Bouton START : écrasement manuel
	------------------------------------------------------------------
	ctx.Connect(startButton.MouseButton1Down, function()
		startButton.Position = UDim2.fromOffset(CONSOLE_W / 2, 53)
	end)
	ctx.Connect(startButton.MouseButton1Up, function()
		startButton.Position = UDim2.fromOffset(CONSOLE_W / 2, 49)
	end)
	ctx.Connect(startButton.MouseLeave, function()
		startButton.Position = UDim2.fromOffset(CONSOLE_W / 2, 49)
	end)
	ctx.Connect(startButton.Activated, function()
		if not ctx.HasFeature("PressStart") then
			return
		end
		local now = os.clock()
		if now < cooldownEnd then
			ctx.Sound.Play("Error", 1)
			UIUtil.Shake(startGroup)
			return
		end
		cooldownEnd = now + cooldown
		ctx.Interact("Press")
		ctx.Sound.Play("Click", 0.7)
		startScale.Scale = 0.85
		UIUtil.Tween(startScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		if phase == "Descend" or phase == "Squeeze" then
			turbo = true
			-- Accélère la phase en cours (en gardant la progression)
			local progress = phaseDuration > 0 and phaseTime / phaseDuration or 1
			phaseDuration /= 4
			phaseTime = progress * phaseDuration
		else
			pendingTurbo = true
		end
	end)

	ctx.OnBonus("Press", function(payload)
		local amount = tonumber(payload.Amount)
		if amount then
			ctx.FloatText(container, UDim2.fromOffset(MX, 110), "+" .. ctx.Format.Format(amount), Theme.Colors.Gold, 30)
		end
	end)

	------------------------------------------------------------------
	-- Palier initial + suivi du niveau
	------------------------------------------------------------------
	refreshLevel(false)
	ctx.Connect(ctx.State.Changed, function()
		refreshLevel(true)
	end)

	for i = 1, #SLOT_X do
		table.insert(queue, newEntry(SLOT_X[i]))
	end

	------------------------------------------------------------------
	-- Boucle (une seule connexion)
	------------------------------------------------------------------
	loadNext()

	local clock = 0
	local lastRollerOffset = -1
	local lastPressure = -1
	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		if not visible() then
			return
		end
		clock += dt
		phaseTime += dt
		local t = phaseDuration > 0 and math.clamp(phaseTime / phaseDuration, 0, 1) or 1
		local targetPressure = 0

		if phase == "Load" then
			plateY = PLATE_TOP
			local e = easeInOut(t)
			for _, mover in ipairs(movers) do
				placeEntry(mover.Entry, mover.From + (mover.To - mover.From) * e)
			end
			beltOffset = beltBase + SPACING * e
			if t >= 1 then
				finishLoad()
				turbo = pendingTurbo
				pendingTurbo = false
				squeezeDepth = current and current.H * 0.24 or 0
				setPhase("Descend")
			end
		elseif phase == "Descend" then
			local contact = BELT_Y - itemHeight() - PLATE_H
			plateY = phaseStartPlate + (contact - phaseStartPlate) * easeInOut(t)
			targetPressure = 0.15 + 0.2 * t
			if t >= 1 then
				setPhase("Squeeze")
			end
		elseif phase == "Squeeze" then
			local entry = current
			if entry then
				-- Se tasse en tremblant, s'élargit un peu
				local height = entry.H - squeezeDepth * (t * t)
				local wobble = math.sin(clock * 60) * entry.Wobble * t
				entry.Holder.Size = UDim2.fromOffset(entry.W * (1 + 0.12 * t) + wobble, height)
				if entry.Label then
					entry.Label.Rotation = random:NextNumber(-6, 6) * t
				end
			end
			plateY = BELT_Y - itemHeight() - PLATE_H
			targetPressure = 0.4 + 0.5 * t
			shakeTime = math.max(shakeTime, 0.03 * t)
			if t >= 1 then
				setPhase("Crunch")
				onCrunch()
			end
		elseif phase == "Crunch" then
			-- Écrasé d'un coup, un peu plus bas que la galette finale
			local squashed = FLAT_H * 0.6
			local entry = current
			if entry then
				local startH = entry.H - squeezeDepth
				local height = startH + (squashed - startH) * t
				entry.Holder.Size = UDim2.fromOffset(entry.W * (1.12 + 0.55 * t), height)
				if entry.Label then
					entry.Label.Rotation = 0
				end
				plateY = BELT_Y - height - PLATE_H
			else
				plateY = BELT_Y - squashed - PLATE_H
			end
			targetPressure = 1
			if t >= 1 then
				setPhase("Hold")
			end
		elseif phase == "Hold" then
			-- Petit rebond de la galette (et du plateau) : "boing"
			local squashed = FLAT_H * 0.6
			local height = squashed + (FLAT_H - squashed) * easeOutBack(t)
			local entry = current
			if entry then
				entry.Holder.Size = UDim2.fromOffset(entry.W * (1.67 - 0.17 * easeOut(t)), height)
			end
			plateY = BELT_Y - height - PLATE_H
			targetPressure = 0.9
			if t >= 1 then
				setPhase("Rise")
				onRise()
				turbo = false
			end
		elseif phase == "Rise" then
			plateY = phaseStartPlate + (PLATE_TOP - phaseStartPlate) * easeOut(t)
			targetPressure = 0.1
			if t >= 1 then
				plateY = PLATE_TOP
				loadNext()
			end
		end

		-- Plateau + tige
		plate.Position = UDim2.fromOffset(MX, plateY)
		rod.Size = UDim2.fromOffset(20, math.max(4, plateY - (CROWN_Y + CROWN_H) + 4))

		-- Pression : manomètres, voyant d'huile, afficheur, voyants
		pressure += (targetPressure - pressure) * math.min(1, dt * 8)
		if math.abs(pressure - lastPressure) > 0.002 then
			lastPressure = pressure
			mainNeedle.Rotation = -120 + pressure * 240
			tankNeedle.Rotation = -120 + pressure * 220
			if gauge2.Visible then
				gauge2Needle.Rotation = -120 + pressure * 200
			end
			oil.Size = UDim2.fromScale(1, 0.72 - pressure * 0.3)
			local digital = tierAnim.Digital
			if digital then
				local value = math.floor(pressure * 3200 / 50) * 50
				if value ~= tierAnim.DigitalValue then
					tierAnim.DigitalValue = value
					digital.Text = string.format("%04d", value)
				end
			end
		end
		local pressing = phase == "Squeeze" or phase == "Crunch" or phase == "Hold"
		local lampColor = pressing and RED or Theme.Colors.Green
		if led.BackgroundColor3 ~= lampColor then
			led.BackgroundColor3 = lampColor
			statusLamp.BackgroundColor3 = lampColor
		end

		-- Tapis + rouleaux (seulement quand la bande bouge)
		if beltOffset ~= lastRollerOffset then
			lastRollerOffset = beltOffset
			beltStripes.Position = UDim2.fromOffset(-(beltOffset % BELT_PERIOD), 0)
			local angle = (beltOffset / 4.5) * 57.3
			for _, roller in ipairs(rollers) do
				roller.Rotation = angle
			end
		end

		updateParticles(dt)
		updatePuffs(dt)
		updateShouts(dt)

		-- Animations du palier
		local style = TIERS[math.max(1, tierIndex)]
		for i, star in ipairs(tierAnim.Twinkles) do
			local wave = 0.5 + 0.5 * math.sin(clock * 3 + i * 1.9)
			star.TextTransparency = 0.1 + (1 - wave) * 0.8
			star.Rotation = math.sin(clock + i) * 15
		end
		local beacon = tierAnim.Beacon
		local beam = tierAnim.BeaconBeam
		if beacon and beam then
			-- Gyrophare : faisceau qui tourne (largeur qui oscille) + éclat
			local spin = math.sin(clock * 7)
			beam.Size = UDim2.fromOffset(10 + math.abs(spin) * 34, 5)
			beam.BackgroundTransparency = 0.35 + (1 - math.abs(spin)) * 0.55
			beacon.BackgroundTransparency = spin > 0 and 0 or 0.25
		end
		local shineFrame = tierAnim.Shine
		if shineFrame then
			local sweep = (clock * 0.45) % 1.6 -- passe puis marque une pause
			shineFrame.Position = UDim2.fromOffset(-40 + sweep * 200, 3)
		end
		local glow = tierAnim.Glow
		if glow then
			glow.BackgroundTransparency = 0.45 + 0.3 * math.sin(clock * 4)
		end
		if style.Neon then
			-- Contours néon qui changent de couleur
			local hue = (clock * 0.12) % 1
			local neon = Color3.fromHSV(hue, 0.75, 1)
			for _, stroke in ipairs(tierAnim.NeonStrokes) do
				stroke.Color = neon
			end
			cardStroke.Color = Color3.fromHSV((hue + 0.5) % 1, 0.7, 1)
		end
		if style.Steam and effectsOn() then
			-- Vapeur qui s'échappe du vérin de temps en temps
			tierAnim.SteamTimer -= dt
			if tierAnim.SteamTimer <= 0 then
				tierAnim.SteamTimer = random:NextNumber(1.2, 2.6)
				puff(MX + 32, CYL_Y + 4, 7, random:NextNumber(4, 14), -22)
			end
		end

		-- Secousse de la machine (la carte, le mur et le contour restent immobiles)
		if shakeTime > 0 then
			shakeTime -= dt
			local strength = math.clamp(shakeTime * 18, 0.6, 3) * math.min(shakePower, 1.5)
			rig.Position = UDim2.fromOffset(random:NextNumber(-strength, strength), random:NextNumber(-strength, strength))
		elseif rig.Position ~= UDim2.new() then
			rig.Position = UDim2.new()
		end

		-- Recharge du bouton START
		if startGroup.Visible then
			local remaining = cooldownEnd - os.clock()
			local text = remaining > 0 and string.format("%.1f", remaining) or "START"
			if text ~= shownCooldown then
				shownCooldown = text
				startButton.Text = text
				startButton.BackgroundColor3 = remaining > 0 and rgb(150, 110, 112) or RED
				buttonSide.BackgroundColor3 = remaining > 0 and rgb(96, 70, 72) or rgb(150, 16, 24)
				local k = remaining > 0 and math.clamp(1 - remaining / cooldown, 0, 1) or 1
				chargeFill.Size = UDim2.fromScale(k, 1)
				chargeFill.BackgroundColor3 = remaining > 0 and rgb(255, 190, 40) or Theme.Colors.Green
			end
		end
	end)
end

function Press.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Press
