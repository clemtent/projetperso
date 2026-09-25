--[[
	Electronics (ModuleScript) — dessins 📺 Électronique
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Electronics
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- Aides partagées
----------------------------------------------------------------------

-- Petits pixels : lignes de "x" / "." regroupées en bandes (peu de Frames)
local function pixels(parent, kit, x, y, size, rows, color, z)
	for r, row in ipairs(rows) do
		local start = nil
		for c = 1, #row + 1 do
			local on = c <= #row and row:sub(c, c) == "x"
			if on and not start then
				start = c
			elseif not on and start then
				kit.Box(parent, x + (start - 1) * size, y + (r - 1) * size, (c - start) * size, size, color, 0, z)
				start = nil
			end
		end
	end
end

local PIXEL_HEART = {
	".xx.xx.",
	"xxxxxxx",
	"xxxxxxx",
	".xxxxx.",
	"..xxx..",
	"...x...",
}

local PIXEL_INVADER = {
	"..x.....x..",
	"...x...x...",
	"..xxxxxxx..",
	".xx.xxx.xx.",
	"xxxxxxxxxxx",
	"x.xxxxxxx.x",
	"x.x.....x.x",
	"...xx.xx...",
}

-- Écran lumineux : dégradé, voile qui pulse doucement, reflet de verre
local function screen(parent, kit, x, y, w, h, top, bottom, z, radius, phase)
	local s = kit.Part(parent, x, y, w, h, WHITE, {
		Radius = radius or 4,
		Z = z,
		Outline = kit.C.Ink,
		Thickness = 1.2,
		Shade = false,
	})
	kit.Gradient(s, top, bottom, 90)
	local veil = kit.Box(s, 0, 0, w, h, WHITE, 0.82, 7)
	kit.Round(veil, radius or 4)
	kit.Animate(veil, "Pulse", 0.18, 1, phase or 0)
	kit.Shine(s, w * 0.08, h * 0.08, w * 0.3, math.max(1.5, h * 0.06), 8, 0.45)
	return s
end

-- Note de musique (tête ovale + hampe + crochet) ; renvoie son conteneur
local function note(parent, kit, cx, cy, s, color, z)
	local g = kit.Group(parent, cx - s / 2, cy - s / 2, s, s, z)
	kit.Blob(g, s * 0.35, s * 0.8, s * 0.46, s * 0.36, color, { Rotation = -20, Outline = false, Shade = false, Z = 2 })
	kit.Box(g, s * 0.52, s * 0.08, math.max(1.2, s * 0.12), s * 0.74, color, 0, 2)
	kit.Line(g, s * 0.58, s * 0.12, s * 0.9, s * 0.36, math.max(1.2, s * 0.12), color, 0, 2)
	return g
end

-- Bobine / disque qui tourne : pivot centré, renvoie le pivot
local function reel(parent, kit, cx, cy, d, color, z, speed, phase)
	local p = kit.Pivot(parent, cx, cy, z)
	kit.Blob(p, 0, 0, d, d, color, { Z = 1 })
	local hub = kit.OutlineOf(color)
	for i = 0, 2 do
		local a = math.rad(i * 120 - 90)
		kit.Circle(p, math.cos(a) * d * 0.26, math.sin(a) * d * 0.26, d * 0.26, d * 0.26, kit.Lighten(color, 0.55), 0, 2)
	end
	kit.Circle(p, 0, 0, d * 0.18, d * 0.18, hub, 0, 3)
	kit.Animate(p, "Spin", 1, speed or 0.25, phase or 0)
	return p
end

----------------------------------------------------------------------
-- Dessins
----------------------------------------------------------------------

-- Téléphone à cadran rose : combiné sur son support, cadran crème, cordon bouclé
Art.RotaryPhone = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 160, 196)
	-- cordon en tire-bouchon (côté gauche)
	for i = 0, 4 do
		local y = 44 + i * 9
		kit.Line(body, 9, y, 5, y + 4.5, 2, kit.OutlineOf(pink), 0, 1)
		kit.Line(body, 5, y + 4.5, 9, y + 9, 2, kit.OutlineOf(pink), 0, 1)
	end
	kit.Part(body, 22, 40, 56, 22, pink, { Radius = 10, Z = 2 }) -- haut du socle
	kit.Part(body, 12, 52, 76, 46, pink, { Radius = 16, Z = 3, Shade = 0.2, Shine = true }) -- socle
	for _, x in ipairs({ 28, 72 }) do
		kit.Part(body, x - 4, 32, 8, 12, kit.Darken(pink, 0.06), { Radius = 3, Z = 1 }) -- fourches
	end
	-- combiné
	kit.Blob(body, 17, 36, 22, 15, pink, { Z = 4 })
	kit.Blob(body, 83, 36, 22, 15, pink, { Z = 4 })
	kit.Part(body, 12, 22, 76, 13, pink, { Radius = -1, Z = 5, Shine = true })
	-- cadran
	local dial = kit.Blob(body, 50, 76, 36, 36, C.Cream, { Z = 5 })
	for i = 0, 8 do
		local a = math.rad(-70 + i * 32)
		local hole = kit.Circle(dial, 18 + math.cos(a) * 12.5, 18 + math.sin(a) * 12.5, 5.4, 5.4, C.PinkSoft, 0, 2)
		kit.Stroke(hole, kit.OutlineOf(C.PinkSoft), 1)
	end
	kit.Circle(dial, 18, 18, 12, 12, pink, 0, 3)
	kit.Heart(dial, 18, 18, 7.5, C.PinkDeep, 0, 4)
	kit.Line(dial, 30, 26, 33, 30, 2, C.GreyDark, 0, 4) -- butée
	return nil
end

-- Radio rétro menthe : poignée, antenne, grille à cœur, cadran de fréquence
Art.RetroRadio = function(body, kit, _item)
	local C = kit.C
	local mint = kit.Lighten(C.Mint, 0.3)
	kit.Part(body, 26, 24, 48, 34, WHITE, { T = 1, Radius = 12, Thickness = 4, Outline = C.WoodDark, Z = 1 }) -- poignée
	kit.Line(body, 78, 44, 92, 10, 2.2, C.GreyDark, 0, 1) -- antenne
	kit.Circle(body, 92, 10, 5.5, 5.5, C.Pink, 0, 1)
	for _, x in ipairs({ 16, 76 }) do
		kit.Part(body, x, 92, 8, 8, C.WoodDark, { Radius = 2, Z = 1 })
	end
	local radio = kit.Part(body, 6, 40, 88, 56, mint, { Radius = 14, Z = 2, Shade = 0.18, Shine = true })
	kit.Box(radio, 0, 9, 88, 3, WHITE, 0.4, 2) -- liseré
	-- haut-parleur à cœur
	local grille = kit.Blob(body, 31, 71, 36, 36, C.Cream, { Z = 3 })
	for i = 0, 3 do
		kit.Box(grille, 7, 8 + i * 6, 22, 1.6, kit.OutlineOf(C.Cream), 0.55, 2)
	end
	kit.Heart(grille, 18, 18, 16, C.Pink, 0, 3)
	kit.Animate(grille, "Breathe", 0.03, 1.4, 0.3)
	-- cadran de fréquence
	local tuner = kit.Part(body, 56, 50, 32, 16, C.Butter, { Radius = 4, Z = 3, Outline = kit.OutlineOf(C.Butter) })
	for i = 0, 5 do
		kit.Box(tuner, 4 + i * 4.8, 3, 1.2, i % 2 == 0 and 5 or 3, kit.OutlineOf(C.Butter), 0.2, 2)
	end
	local needle = kit.Box(tuner, 14, 2, 1.8, 12, C.Red, 0, 3)
	kit.Animate(needle, "Drift", 5, 0.4, 0)
	-- boutons
	for index, color in ipairs({ C.Pink, C.Lilac }) do
		local knob = kit.Blob(body, 62 + (index - 1) * 20, 80, 13, 13, color, { Z = 3, Shine = true })
		kit.Box(knob, 5.6, 1.5, 1.8, 5, kit.OutlineOf(color), 0, 4)
	end
	local n = note(body, kit, 12, 28, 11, C.PinkDeep, 6)
	kit.Animate(n, "Bob", 2.5, 1, 0.5)
	return nil
end

-- Smartphone à coque lapin : écran avec icônes d'applis et cœur "like"
Art.Smartphone = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 176, 206)
	for _, x in ipairs({ 39, 61 }) do
		local ear = kit.Blob(body, x, 16, 11, 22, pink, { Z = 1 })
		kit.Blob(ear, 5.5, 12, 5, 14, C.PinkSoft, { Z = 2, Outline = false, Shade = false })
	end
	kit.Part(body, 26, 16, 48, 84, pink, { Radius = 12, Z = 2, Shade = 0.15 })
	local s = screen(body, kit, 30, 21, 40, 74, C.LilacSoft, C.PinkSoft, 3, 8, 0.2)
	kit.Part(s, 14, 3, 12, 3.5, C.Ink, { Radius = -1, Z = 9, Outline = false, Shade = false }) -- encoche
	-- bulle de notification
	local bubble = kit.Part(s, 5, 10, 30, 12, WHITE, { Radius = 5, Z = 3, Thickness = 1, Shade = false })
	kit.Heart(bubble, 7, 6, 7, C.Heart, 0, 2)
	kit.Box(bubble, 13, 3.4, 13, 1.8, C.Grey, 0, 2)
	kit.Box(bubble, 13, 6.6, 9, 1.8, C.Grey, 0, 2)
	-- gros cœur qui bat
	local big = kit.Heart(s, 20, 34, 16, C.Heart, 0, 3)
	kit.Animate(big, "Breathe", 0.08, 2.2, 0)
	-- icônes d'applis
	local colors = { C.Mint, C.Butter, C.Sky, C.Lilac, C.Peach, C.Pink }
	for i, color in ipairs(colors) do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		kit.Part(s, 5 + col * 11, 48 + row * 10.5, 8, 8, color, { Radius = 3, Z = 3, Thickness = 1, Shade = false })
	end
	kit.Part(s, 13, 69, 14, 2, WHITE, { Radius = -1, Z = 3, Outline = false, Shade = false })
	return { Glow = C.PinkSoft }
end

-- Appareil photo instantané bleu ciel : gros objectif, bande arc-en-ciel, photo qui sort
Art.InstantCamera = function(body, kit, _item)
	local C = kit.C
	local sky = Color3.fromRGB(176, 220, 255)
	-- photo qui sort par le haut
	local photo = kit.Part(body, 56, 8, 30, 34, WHITE, { Radius = 2, Z = 1, Rotation = 10, Thickness = 1.2 })
	local pic = kit.Box(photo, 3, 3, 24, 20, C.Sky, 0, 2)
	kit.Gradient(pic, C.Sky, C.PinkSoft, 90)
	kit.Heart(pic, 12, 10, 10, C.Heart, 0, 3)
	kit.Part(body, 14, 28, 66, 20, sky, { Radius = 8, Z = 2 }) -- dessus
	local cam = kit.Part(body, 6, 38, 88, 60, sky, { Radius = 14, Z = 3, Shade = 0.18, Shine = true })
	-- bande arc-en-ciel
	for i, color in ipairs({ C.Red, C.Orange, C.Yellow, C.Mint, C.Blue }) do
		kit.Box(cam, 18 + i * 3, 0, 3, 60, color, 0.15, 2)
	end
	kit.Part(body, 16, 31, 18, 11, C.Cream, { Radius = 3, Z = 2 }) -- flash
	kit.Box(body, 18, 33, 14, 7, C.Butter, 0.2, 2)
	kit.Part(body, 64, 43, 16, 11, C.Navy, { Radius = 3, Z = 4 }) -- viseur
	kit.Shine(body, 66, 45, 5, 2.5, 5)
	kit.Blob(body, 74, 34, 9, 6, C.Red, { Z = 2 }) -- déclencheur
	-- objectif
	kit.Blob(body, 50, 72, 44, 44, C.Cream, { Z = 5 })
	kit.Blob(body, 50, 72, 32, 32, C.GreyDark, { Z = 6 })
	local lens = kit.Blob(body, 50, 72, 22, 22, C.Navy, { Z = 7 })
	kit.Gradient(lens, C.Lilac, C.Navy, 45)
	kit.Circle(lens, 7, 7, 6, 6, WHITE, 0.2, 2)
	kit.Circle(lens, 15, 15, 3, 3, WHITE, 0.5, 2)
	kit.Heart(body, 84, 88, 8, C.PinkDeep, 0, 5)
	return nil
end

-- Ordinateur portable lilas : écran avec visage souriant, clavier et pavé tactile
Art.Laptop = function(body, kit, _item)
	local C = kit.C
	local lilac = Color3.fromRGB(214, 196, 255)
	kit.Part(body, 12, 18, 76, 58, lilac, { Radius = 8, Z = 2, Shade = 0.12 }) -- capot
	local s = screen(body, kit, 17, 23, 66, 46, C.Sky, C.LilacSoft, 3, 5, 0.6)
	kit.Face(s, 33, 24, 28, { Eyes = "big", Mouth = "cat", Z = 3 })
	for i, pos in ipairs({ { 9, 10 }, { 57, 12 }, { 54, 35 } }) do
		local h = kit.Heart(s, pos[1], pos[2], 7 - i, C.Heart, 0.1, 3)
		kit.Animate(h, "Bob", 1.5, 1, i)
	end
	kit.Sparkle(s, 11, 36, 7, WHITE, 0, 3)
	kit.Circle(body, 50, 20.5, 2, 2, C.Ink, 0, 4) -- webcam
	-- base / clavier
	local base = kit.Part(body, 4, 74, 92, 22, kit.Lighten(lilac, 0.2), { Radius = 6, Z = 4, Shade = 0.2 })
	for row = 0, 2 do
		kit.Box(base, 12 + row * 2, 3 + row * 4, 68 - row * 4, 2.4, kit.OutlineOf(lilac), 0.45, 2)
	end
	kit.Part(base, 36, 15, 20, 5, kit.Lighten(lilac, 0.5), { Radius = 2, Z = 2, Thickness = 1, Shade = false })
	kit.Heart(base, 80, 15, 7, C.Pink, 0, 3) -- autocollant
	kit.Part(body, 2, 94, 96, 5, kit.Darken(lilac, 0.05), { Radius = -1, Z = 3 })
	return { Glow = C.Sky }
end

-- Console de poche : écran vert à cœur en pixels, croix, boutons A/B
Art.RetroHandheld = function(body, kit, _item)
	local C = kit.C
	local shell = Color3.fromRGB(236, 226, 255)
	local g = kit.Part(body, 20, 6, 60, 92, shell, { Radius = 10, Z = 2, Shade = 0.16, Shine = true })
	kit.Box(g, 0, 5, 60, 1.4, kit.OutlineOf(shell), 0.6, 2)
	local bezel = kit.Part(body, 26, 14, 48, 38, Color3.fromRGB(120, 110, 150), { Radius = 5, Z = 3 })
	kit.Circle(bezel, 4, 19, 3, 3, C.Red, 0, 3) -- voyant
	local s = screen(body, kit, 33, 18, 34, 28, Color3.fromRGB(200, 240, 190), Color3.fromRGB(160, 214, 160), 4, 2, 0.1)
	local heart = kit.Group(s, 10, 6, 14, 12, 3)
	pixels(heart, kit, 0, 0, 2, PIXEL_HEART, C.LeafDark, 2)
	kit.Animate(heart, "Bob", 1, 1.3, 0)
	kit.Box(s, 4, 22, 26, 1.6, C.LeafDark, 0.5, 3)
	-- croix directionnelle
	kit.Part(body, 26, 66, 18, 6, C.Ink, { Radius = 2, Z = 3, Outline = false })
	kit.Part(body, 32, 60, 6, 18, C.Ink, { Radius = 2, Z = 3, Outline = false })
	-- boutons A / B
	kit.Blob(body, 60, 72, 10, 10, C.Pink, { Z = 3, Shine = true })
	kit.Blob(body, 70, 64, 10, 10, C.PinkDeep, { Z = 3, Shine = true })
	-- start / select
	for _, x in ipairs({ 42, 54 }) do
		kit.Part(body, x, 82, 9, 3, C.GreyDark, { Radius = -1, Z = 3, Outline = false, Rotation = -25 })
	end
	-- grille de haut-parleur
	for i = 0, 3 do
		kit.Line(body, 60 + i * 4, 94, 66 + i * 4, 86, 1.6, kit.OutlineOf(shell), 0.3, 3)
	end
	return nil
end

-- Télé rétro en bois : écran bombé avec un visage, antennes lapin, boutons
Art.RetroTV = function(body, kit, _item)
	local C = kit.C
	local wood = Color3.fromRGB(240, 186, 160)
	kit.Line(body, 26, 84, 20, 99, 4.5, C.WoodDark, 0, 1)
	kit.Line(body, 74, 84, 80, 99, 4.5, C.WoodDark, 0, 1)
	kit.Line(body, 50, 22, 30, 3, 2.2, C.GreyDark, 0, 1)
	kit.Line(body, 50, 22, 72, 1, 2.2, C.GreyDark, 0, 1)
	kit.Circle(body, 30, 3, 5.5, 5.5, C.Pink, 0, 1)
	kit.Circle(body, 72, 1, 5.5, 5.5, C.Mint, 0, 1)
	kit.Blob(body, 50, 24, 18, 10, C.GreyDark, { Z = 1 })
	local cab = kit.Part(body, 6, 22, 88, 66, wood, { Radius = 16, Z = 2, Shade = 0.18, Shine = true })
	kit.Box(cab, 0, 58, 88, 2, kit.OutlineOf(wood), 0.7, 2)
	kit.Part(body, 12, 28, 58, 52, C.Cream, { Radius = 14, Z = 3 })
	local s = screen(body, kit, 16, 32, 50, 44, C.MintSoft, C.Sky, 4, 12, 0.4)
	kit.Face(s, 25, 22, 30, { Eyes = "big", Mouth = "smile", Z = 3 })
	kit.Sparkle(s, 42, 10, 7, WHITE, 0, 3)
	-- boutons et haut-parleur
	for i, color in ipairs({ C.Pink, C.Butter }) do
		local knob = kit.Blob(body, 82, 36 + (i - 1) * 15, 11, 11, color, { Z = 3, Shine = true })
		kit.Box(knob, 4.6, 1.2, 1.8, 4.5, kit.OutlineOf(color), 0, 4)
	end
	for i = 0, 3 do
		kit.Part(body, 75, 60 + i * 4.5, 14, 2, kit.OutlineOf(wood), { Radius = -1, Z = 3, Outline = false, Shade = false, T = 0.35 })
	end
	return { Glow = C.MintSoft }
end

-- Tourne-disque en valise : couvercle ouvert, vinyle qui tourne, bras de lecture
Art.RecordPlayer = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 176, 200)
	local lid = kit.Part(body, 8, 12, 84, 42, kit.Darken(pink, 0.06), { Radius = 10, Z = 1 })
	kit.Part(lid, 5, 5, 74, 32, kit.Lighten(pink, 0.4), { Radius = 7, Z = 2, Outline = false, Shade = false })
	kit.Heart(lid, 42, 20, 14, C.PinkDeep, 0.2, 3)
	local base = kit.Part(body, 4, 44, 92, 54, pink, { Radius = 12, Z = 2, Shade = 0.2, Shine = true })
	kit.Part(base, 5, 5, 82, 38, kit.Lighten(pink, 0.3), { Radius = 8, Z = 2, Shade = false })
	kit.Box(base, 0, 45, 92, 1.6, kit.OutlineOf(pink), 0.5, 2)
	-- vinyle
	local disc = kit.Pivot(body, 38, 67, 3)
	kit.Blob(disc, 0, 0, 38, 38, Color3.fromRGB(70, 60, 90), { Z = 1 })
	kit.Line(disc, -12, -8, -5, -14, 2, WHITE, 0.6, 3) -- reflet qui tourne
	kit.Animate(disc, "Spin", 1, 0.33, 0)
	for _, d in ipairs({ 30, 22 }) do
		local ring = kit.Circle(disc, 0, 0, d, d, WHITE, 1, 2)
		kit.Stroke(ring, Color3.fromRGB(120, 105, 140), 1, 0.2)
	end
	local label = kit.Circle(disc, 0, 0, 13, 13, C.Pink, 0, 4)
	kit.Heart(label, 6.5, 6, 6, WHITE, 0, 2)
	kit.Shine(body, 25, 55, 10, 3, 6, 0.55)
	-- bras de lecture
	kit.Blob(body, 80, 56, 11, 11, C.Grey, { Z = 5, Shine = true })
	kit.Line(body, 80, 56, 76, 76, 2.6, C.Grey, 0, 5)
	kit.Line(body, 76, 76, 64, 82, 2.6, C.Grey, 0, 5)
	kit.Part(body, 58, 79, 9, 6, C.GreyDark, { Radius = 2, Z = 6, Rotation = -25 })
	-- boutons
	kit.Blob(body, 84, 89, 7, 7, C.Mint, { Z = 4 })
	kit.Blob(body, 74, 89, 7, 7, C.Butter, { Z = 4 })
	for i, pos in ipairs({ { 10, 26 }, { 90, 16 } }) do
		local n = note(body, kit, pos[1], pos[2], 11 - i, i == 1 and C.PinkDeep or C.Purple, 7)
		kit.Animate(n, "Bob", 2.5, 1, i * 1.7)
	end
	return nil
end

-- Casque à oreilles de chat : arceau rose, oreillettes avec coussinets de patte
Art.CatHeadphones = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 170, 204)
	-- oreilles de chat (derrière l'arceau)
	-- (carrés arrondis tournés : la moitié basse est cachée par l'arceau)
	local ears = kit.Group(body, 0, -10, 100, 32, 1, true)
	for _, side in ipairs({ -1, 1 }) do
		local ear = kit.Part(ears, 50 + side * 18 - 13, 12, 26, 26, pink, { Radius = 5, Z = 1, Rotation = 45 + side * 15, Shade = false })
		kit.Part(ear, 4, 4, 12, 12, C.PinkSoft, { Radius = 4, Z = 2, Outline = false, Shade = false })
	end
	-- arceau (moitié haute d'un anneau)
	local band = kit.Group(body, 4, 6, 92, 50, 2, true)
	kit.Part(band, 10, 10, 72, 80, WHITE, { T = 1, Radius = -1, Thickness = 10, Outline = kit.OutlineOf(pink) })
	kit.Part(band, 10, 10, 72, 80, WHITE, { T = 1, Radius = -1, Thickness = 7, Outline = pink })
	kit.Line(body, 16, 50, 16, 62, 7, pink, 0, 2)
	kit.Line(body, 84, 50, 84, 62, 7, pink, 0, 2)
	-- oreillettes
	for _, side in ipairs({ -1, 1 }) do
		local cx = 50 + side * 32
		kit.Part(body, cx - 12, 56, 24, 42, C.PinkSoft, { Radius = 12, Z = 3 }) -- coussin
		local cup = kit.Blob(body, cx - side * 6, 77, 28, 40, pink, { Z = 4, Shade = 0.18, Shine = true })
		-- coussinet de patte
		kit.Circle(cup, 14, 23, 11, 9, C.PinkSoft, 0, 3)
		for i = -1, 1 do
			kit.Circle(cup, 14 + i * 5, 14.5 - math.abs(i) * -1 - (i == 0 and 2 or 0), 5, 5, C.PinkSoft, 0, 3)
		end
	end
	for i, pos in ipairs({ { 46, 40 }, { 58, 30 } }) do
		local n = note(body, kit, pos[1], pos[2] + 4, 11 - i * 2, i == 1 and C.PinkDeep or C.Purple, 6)
		kit.Animate(n, "Bob", 2, 1, i * 1.3)
	end
	return nil
end

-- Enceinte basse : caisson lilas, tweeter, gros woofer qui pulse, notes
Art.Speaker = function(body, kit, _item)
	local C = kit.C
	local lilac = Color3.fromRGB(200, 176, 250)
	for _, x in ipairs({ 24, 68 }) do
		kit.Part(body, x, 94, 8, 6, C.Ink, { Radius = 2, Z = 1, Outline = false })
	end
	local cab = kit.Part(body, 18, 8, 64, 88, lilac, { Radius = 12, Z = 2, Shade = 0.18, Shine = true })
	kit.Circle(cab, 56, 7, 3.5, 3.5, C.Mint, 0, 3) -- voyant
	-- tweeter
	kit.Blob(body, 50, 28, 22, 22, C.Cream, { Z = 3 })
	local tw = kit.Blob(body, 50, 28, 13, 13, C.GreyDark, { Z = 4 })
	kit.Circle(tw, 4.5, 4, 3.5, 3.5, WHITE, 0.4, 2)
	-- woofer
	kit.Blob(body, 50, 68, 46, 46, C.Cream, { Z = 3 })
	local cone = kit.Blob(body, 50, 68, 36, 36, Color3.fromRGB(110, 96, 140), { Z = 4 })
	kit.Gradient(cone, Color3.fromRGB(170, 150, 200), Color3.fromRGB(110, 96, 140), 45)
	local cap = kit.Circle(cone, 18, 18, 14, 14, C.Pink, 0, 2)
	kit.Heart(cap, 7, 7, 7, WHITE, 0.2, 2)
	kit.Animate(cone, "Breathe", 0.05, 3, 0)
	-- notes et ondes
	for i, pos in ipairs({ { 10, 30 }, { 90, 44 }, { 88, 16 } }) do
		local n = note(body, kit, pos[1], pos[2], 12 - i, i == 2 and C.Purple or C.PinkDeep, 6)
		kit.Animate(n, "Bob", 2.5, 1.2, i * 1.1)
	end
	return nil
end

-- Robot aspirateur : disque blanc avec visage, capteur, nœud rose ; il se promène
Art.RobotVacuum = function(body, kit, _item)
	local C = kit.C
	local g = kit.Group(body, 0, 0, 100, 100, 2)
	kit.Animate(g, "Drift", 5, 0.5, 0)
	for _, x in ipairs({ 24, 76 }) do
		kit.Blob(g, x, 96, 12, 7, C.Ink, { Z = 1, Outline = false })
	end
	kit.Part(g, 6, 70, 88, 26, Color3.fromRGB(236, 232, 248), { Radius = 12, Z = 2, Shade = 0.2 }) -- flanc
	local top = kit.Blob(g, 50, 70, 88, 22, WHITE, { Z = 3, Shade = 0.08 })
	kit.Blob(top, 44, 11, 40, 10, C.MintSoft, { Z = 2, Outline = kit.Lighten(C.Mint, 0.2), Thickness = 1, Shade = false })
	kit.Shine(top, 10, 4, 18, 3, 3)
	kit.Part(g, 42, 60, 16, 6, C.Mint, { Radius = -1, Z = 4 }) -- capteur
	kit.Part(g, 6, 76, 88, 3, C.Lilac, { Radius = 0, Z = 3, Outline = false, Shade = false, T = 0.4 })
	kit.Face(g, 50, 86, 28, { Eyes = "dot", Mouth = "smile", Z = 5 })
	-- nœud
	kit.Blob(g, 72, 60, 11, 8, C.Pink, { Z = 5, Rotation = -20 })
	kit.Blob(g, 82, 60, 11, 8, C.Pink, { Z = 5, Rotation = 20 })
	kit.Circle(g, 77, 60, 5, 5, C.PinkDeep, 0, 6)
	-- brosse latérale
	local brush = kit.Pivot(g, 10, 94, 6)
	for i = 0, 2 do
		local a = math.rad(i * 120)
		kit.Line(brush, 0, 0, math.cos(a) * 7, math.sin(a) * 3, 1.4, C.GreyDark, 0, 1)
	end
	kit.Animate(brush, "Spin", 1, 1.5, 0)
	kit.Sparkle(body, 94, 58, 8, C.Butter, 0, 3)
	kit.Sparkle(body, 4, 62, 6, C.Sky, 0, 3)
	return nil
end

-- Climatiseur mural kawaii : visage endormi, volet, souffle frais et flocons
Art.AirConditioner = function(body, kit, _item)
	local C = kit.C
	local unit = kit.Part(body, 4, 24, 92, 42, WHITE, { Radius = 14, Z = 2, Outline = Color3.fromRGB(170, 176, 206), Shade = 0.14, Shine = true })
	kit.Box(unit, 6, 8, 80, 1.2, C.Grey, 0.4, 2)
	kit.Part(body, 10, 54, 80, 8, Color3.fromRGB(150, 150, 180), { Radius = 3, Z = 3 }) -- sortie d'air
	for i = 0, 2 do
		kit.Box(body, 14, 55.5 + i * 2, 72, 1, Color3.fromRGB(120, 120, 150), 0, 4)
	end
	kit.Part(body, 12, 60, 76, 4, WHITE, { Radius = -1, Z = 5, Rotation = 3 }) -- volet
	kit.Face(body, 30, 40, 26, { Eyes = "closed", Mouth = "cat", Z = 4 })
	local screenBox = kit.Part(body, 66, 32, 22, 11, C.Navy, { Radius = 3, Z = 3 })
	kit.Box(screenBox, 3, 3, 6, 5, C.Sky, 0, 2)
	kit.Box(screenBox, 11, 3, 6, 5, C.Sky, 0, 2)
	kit.Circle(body, 84, 48, 3.5, 3.5, C.Mint, 0, 4)
	-- souffle d'air frais
	for i = 0, 2 do
		local wave = kit.Group(body, 18 + i * 22, 68, 20, 18, 3)
		for j = 0, 2 do
			local x0 = 2 + j * 2
			kit.Line(wave, x0 + (j % 2) * 4, j * 5, x0 + ((j + 1) % 2) * 4, j * 5 + 5, 1.8, C.Sky, 0.2, 1)
		end
		kit.Animate(wave, "Bob", 2, 1.2, i * 0.9)
	end
	for i, pos in ipairs({ { 12, 84 }, { 58, 92 }, { 90, 80 } }) do
		local flake = kit.Sparkle(body, pos[1], pos[2], 8 - i, i == 2 and C.Sky or WHITE, 0, 4)
		kit.Animate(flake, "Bob", 2, 0.9, i)
	end
	return { WallShadow = Vector2.new(0.92, 0.44) }
end

-- Ordinateur de bureau : écran avec fenêtre et cœur en pixels, tour à LED, clavier, souris
Art.DesktopPC = function(body, kit, _item)
	local C = kit.C
	local cream = Color3.fromRGB(250, 246, 255)
	-- tour
	local tower = kit.Part(body, 74, 34, 22, 64, Color3.fromRGB(214, 196, 255), { Radius = 5, Z = 1, Shade = 0.2, Shine = true })
	local led = kit.Box(tower, 3, 6, 3, 52, WHITE, 0, 2)
	kit.Round(led, -1)
	kit.Gradient(led, C.Pink, C.Sky, 90)
	kit.Animate(led, "Pulse", 0.4, 1.5, 0)
	local fan = kit.Blob(tower, 13, 18, 12, 12, C.Navy, { Z = 2 })
	kit.Heart(fan, 6, 6, 6, C.Pink, 0, 2)
	kit.Circle(tower, 13, 50, 5, 5, C.Mint, 0, 2)
	-- écran
	kit.Part(body, 36, 60, 12, 14, C.Grey, { Radius = 2, Z = 2 })
	kit.Part(body, 26, 70, 32, 7, C.Grey, { Radius = -1, Z = 3 })
	kit.Part(body, 6, 8, 72, 54, cream, { Radius = 8, Z = 3, Shade = 0.12 })
	local s = screen(body, kit, 10, 12, 64, 44, C.Sky, C.LilacSoft, 4, 4, 0.8)
	kit.Cloud(s, 12, 40, 16, WHITE, 0.2, 2)
	kit.Cloud(s, 56, 16, 12, WHITE, 0.3, 2)
	local win = kit.Part(s, 16, 6, 34, 30, WHITE, { Radius = 3, Z = 3, Thickness = 1, Shade = false })
	kit.Box(win, 0, 0, 34, 6, C.PinkSoft, 0, 2)
	for i, color in ipairs({ C.Red, C.Butter, C.Mint }) do
		kit.Circle(win, 4 + (i - 1) * 4, 3, 2.6, 2.6, color, 0, 3)
	end
	local ph = kit.Group(win, 10, 10, 14, 12, 3)
	pixels(ph, kit, 0, 0, 2, PIXEL_HEART, C.Heart, 2)
	kit.Animate(ph, "Breathe", 0.06, 2, 0)
	kit.Line(s, 54, 28, 54, 36, 1.6, C.Ink, 0, 4) -- curseur
	kit.Line(s, 54, 28, 59, 33, 1.6, C.Ink, 0, 4)
	kit.Circle(body, 42, 58.5, 2.5, 2.5, C.Mint, 0, 5)
	-- clavier
	local kb = kit.Part(body, 4, 84, 62, 13, WHITE, { Radius = 4, Z = 5, Shade = 0.18 })
	for row = 0, 1 do
		for col = 0, 4 do
			kit.Part(kb, 4 + col * 10.8 + row * 3, 2.5 + row * 4.5, 9, 3.4, col == 2 and C.PinkSoft or C.LilacSoft, { Radius = 1, Z = 2, Outline = false, Shade = false })
		end
	end
	-- souris
	local mouse = kit.Blob(body, 76, 92, 11, 13, C.Pink, { Z = 6, Shine = true })
	kit.Box(mouse, 5, 0, 1, 5, kit.OutlineOf(C.Pink), 0, 2)
	return { Glow = C.Sky }
end

-- Console de salon rétro : cartouche rose, boîtier crème, manette reliée par un fil
Art.GameConsole = function(body, kit, _item)
	local C = kit.C
	local cream = Color3.fromRGB(246, 242, 255)
	local cart = kit.Part(body, 32, 18, 36, 26, C.Pink, { Radius = 4, Z = 1, Shade = 0.15 })
	local label = kit.Part(cart, 5, 4, 26, 12, C.Butter, { Radius = 2, Z = 2, Thickness = 1, Shade = false })
	kit.Heart(label, 13, 6, 8, C.Heart, 0, 2)
	kit.Part(body, 26, 34, 48, 10, C.Lilac, { Radius = 4, Z = 2 })
	local console = kit.Part(body, 8, 38, 84, 30, cream, { Radius = 12, Z = 3, Shade = 0.18, Shine = true })
	kit.Box(console, 0, 20, 84, 1.4, C.Grey, 0.2, 2)
	for i = 0, 1 do
		kit.Part(body, 16 + i * 10, 58, 7, 5, C.GreyDark, { Radius = 2, Z = 4, Outline = false })
	end
	kit.Part(body, 60, 55, 10, 6, C.Pink, { Radius = 2, Z = 4 }) -- power
	kit.Part(body, 74, 55, 10, 6, C.Lilac, { Radius = 2, Z = 4 }) -- reset
	kit.Circle(body, 50, 58, 3.5, 3.5, C.Mint, 0, 4)
	-- fil
	kit.Line(body, 19, 63, 16, 74, 1.8, C.GreyDark, 0, 4)
	kit.Line(body, 16, 74, 26, 80, 1.8, C.GreyDark, 0, 4)
	-- manette
	local pad = Color3.fromRGB(190, 170, 250)
	kit.Blob(body, 32, 88, 22, 20, pad, { Z = 5 })
	kit.Blob(body, 68, 88, 22, 20, pad, { Z = 5 })
	kit.Part(body, 22, 72, 56, 20, pad, { Radius = 10, Z = 6, Shade = 0.15, Shine = true })
	kit.Box(body, 27.5, 79, 11, 3.6, C.Ink, 0, 7)
	kit.Box(body, 31.2, 75.3, 3.6, 11, C.Ink, 0, 7)
	for i, pos in ipairs({ { 66, 77 }, { 72, 82 }, { 60, 82 }, { 66, 87 } }) do
		kit.Circle(body, pos[1], pos[2], 5, 5, ({ C.Pink, C.Mint, C.Sky, C.Butter })[i], 0, 7)
	end
	kit.Part(body, 44, 83, 5, 2.4, C.GreyDark, { Radius = -1, Z = 7, Outline = false })
	kit.Part(body, 51, 83, 5, 2.4, C.GreyDark, { Radius = -1, Z = 7, Outline = false })
	return nil
end

-- Micro de karaoké qui chante : tête rose avec visage, bague dorée, socle, notes
Art.KaraokeMic = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 94, 46, 11, C.Lilac, { Z = 1 })
	kit.Part(body, 47, 72, 6, 20, C.Grey, { Radius = 2, Z = 1 })
	local handle = kit.Part(body, 40, 44, 20, 36, WHITE, { Radius = 8, Z = 2, Shade = 0.2 })
	kit.Gradient(handle, C.LilacSoft, C.Lilac, 0)
	local ledRing = kit.Box(handle, 2, 16, 16, 3, C.Pink, 0, 2)
	kit.Gradient(ledRing, C.Pink, C.Sky, 0)
	kit.Animate(ledRing, "Pulse", 0.6, 2, 0)
	kit.Sparkle(handle, 10, 28, 5, WHITE, 0, 2)
	kit.Part(body, 36, 40, 28, 8, C.Gold, { Radius = 3, Z = 3, Shine = true })
	local head = kit.Blob(body, 50, 25, 42, 40, C.Pink, { Z = 4, Shade = 0.18, Shine = true })
	kit.Box(head, 3, 29, 36, 1.6, kit.OutlineOf(C.Pink), 0.6, 2)
	kit.Face(head, 21, 24, 24, { Eyes = "happy", Mouth = "o", Z = 3 })
	for i, pos in ipairs({ { 12, 18 }, { 88, 28 }, { 84, 6 } }) do
		local n = note(body, kit, pos[1], pos[2], 12 - i * 1.5, i == 2 and C.Purple or C.PinkDeep, 6)
		kit.Animate(n, "Bob", 2.5, 1, i * 1.4)
	end
	kit.Sparkle(body, 16, 50, 7, C.Butter, 0, 6)
	return nil
end

-- Borne d'arcade : fronton lumineux, écran avec envahisseur en pixels, joystick, boutons
Art.ArcadeMachine = function(body, kit, _item)
	local C = kit.C
	local lilac = Color3.fromRGB(186, 160, 250)
	kit.Part(body, 20, 94, 60, 6, C.Ink, { Radius = 2, Z = 1, Outline = false })
	local cab = kit.Part(body, 16, 4, 68, 92, lilac, { Radius = 8, Z = 2, Shade = 0.2, Shine = true })
	for _, x in ipairs({ 3, 61 }) do
		kit.Box(cab, x, 20, 4, 70, kit.Lighten(lilac, 0.35), 0, 2) -- liserés
	end
	-- fronton
	local marquee = kit.Part(body, 20, 8, 60, 16, C.PinkSoft, { Radius = 4, Z = 3 })
	kit.Gradient(marquee, C.PinkSoft, C.Pink, 90)
	local lit = kit.Box(marquee, 0, 0, 60, 16, WHITE, 0.6, 2)
	kit.Round(lit, 4)
	kit.Animate(lit, "Pulse", 0.4, 1.6, 0)
	for i = 0, 2 do
		kit.Heart(marquee, 18 + i * 12, 8, i == 1 and 10 or 7, i == 1 and C.Heart or WHITE, 0, 3)
	end
	-- écran
	kit.Part(body, 22, 27, 56, 36, C.Navy, { Radius = 5, Z = 3 })
	local s = screen(body, kit, 26, 30, 48, 30, Color3.fromRGB(60, 50, 120), Color3.fromRGB(30, 30, 70), 4, 3, 0.3)
	local inv = kit.Group(s, 13, 5, 22, 16, 3)
	pixels(inv, kit, 0, 0, 2, PIXEL_INVADER, C.Mint, 2)
	kit.Animate(inv, "Drift", 4, 0.8, 0)
	for i = 0, 3 do
		kit.Box(s, 6 + i * 11, 25, 6, 1.6, C.Butter, 0.2, 3)
	end
	kit.Sparkle(s, 6, 8, 5, C.Butter, 0, 3)
	-- panneau de commande
	kit.Part(body, 10, 64, 80, 13, C.Pink, { Radius = 4, Z = 5, Shade = 0.2 })
	kit.Line(body, 30, 70, 30, 60, 2.4, C.GreyDark, 0, 6)
	kit.Blob(body, 30, 59, 9, 9, C.Red, { Z = 7, Shine = true })
	for i, color in ipairs({ C.Butter, C.Mint, C.Sky }) do
		kit.Blob(body, 50 + (i - 1) * 10, 70, 7, 5, color, { Z = 6 })
	end
	-- portillon à pièces
	local door = kit.Part(body, 38, 80, 24, 14, kit.Darken(lilac, 0.08), { Radius = 3, Z = 3 })
	for i = 0, 1 do
		local slot = kit.Box(door, 5 + i * 9, 4, 5, 6, C.Orange, 0, 2)
		kit.Round(slot, 1)
		kit.Box(slot, 2, 1, 1, 4, C.Ink, 0, 2)
	end
	return { Glow = C.Pink }
end

-- Projecteur de cinéma vintage : deux bobines qui tournent, objectif, faisceau
Art.Projector = function(body, kit, _item)
	local C = kit.C
	local grey = Color3.fromRGB(196, 190, 226)
	-- faisceau
	local beam = kit.Triangle(body, 96, 46, 30, 26, C.Butter, 1, 0.55, 10)
	beam.Rotation = -90
	for _, child in ipairs(beam:GetChildren()) do
		kit.Animate(child, "Pulse", 0.3, 1.2, 0)
	end
	-- pied
	kit.Part(body, 10, 88, 64, 10, C.WoodDark, { Radius = 4, Z = 1 })
	kit.Part(body, 36, 80, 12, 10, C.GreyDark, { Radius = 2, Z = 1 })
	-- bras des bobines
	kit.Line(body, 28, 34, 38, 54, 3, C.GreyDark, 0, 1)
	kit.Line(body, 62, 30, 52, 54, 3, C.GreyDark, 0, 1)
	reel(body, kit, 28, 32, 30, C.Pink, 2, 0.3, 0)
	reel(body, kit, 64, 28, 30, C.Mint, 2, 0.3, 1.3)
	kit.Line(body, 14, 34, 18, 56, 1.8, C.Ink, 0, 1) -- pellicule
	-- corps
	local main = kit.Part(body, 10, 50, 62, 32, grey, { Radius = 8, Z = 3, Shade = 0.18, Shine = true })
	kit.Box(main, 4, 20, 54, 1.4, kit.OutlineOf(grey), 0.5, 2)
	for i = 0, 2 do
		kit.Box(main, 34 + i * 6, 6, 3, 10, kit.OutlineOf(grey), 0.5, 2)
	end
	kit.Blob(body, 22, 72, 7, 7, C.Pink, { Z = 4 })
	kit.Blob(body, 32, 72, 7, 7, C.Butter, { Z = 4 })
	-- objectif
	kit.Part(body, 70, 57, 16, 18, C.GreyDark, { Radius = 3, Z = 2 })
	local lens = kit.Blob(body, 86, 66, 9, 22, C.Glass, { Z = 3 })
	kit.Gradient(lens, WHITE, C.Butter, 0)
	return { Glow = C.Butter }
end

-- Piano à queue rose et crème : couvercle relevé, pupitre avec partition, clavier
Art.GrandPiano = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 196, 216)
	-- couvercle relevé et béquille
	kit.Line(body, 82, 48, 80, 23, 2, C.Gold, 0, 1)
	kit.Part(body, 6, 28.5, 86, 7, pink, { Radius = 3, Z = 2, Rotation = -16, Shine = true })
	kit.Part(body, 8, 38, 82, 12, kit.Darken(pink, 0.1), { Radius = 4, Z = 1 }) -- intérieur
	-- pupitre et partition
	local sheet = kit.Part(body, 34, 30, 32, 17, WHITE, { Radius = 2, Z = 3, Thickness = 1.2 })
	for i = 0, 2 do
		kit.Box(sheet, 3, 4 + i * 3.5, 26, 0.8, C.Grey, 0, 2)
	end
	note(sheet, kit, 10, 7, 8, C.Ink, 3)
	note(sheet, kit, 22, 9, 7, C.PinkDeep, 3)
	kit.Part(body, 30, 44, 40, 4, C.WoodDark, { Radius = 2, Z = 4 })
	-- caisse
	local case = kit.Part(body, 4, 46, 92, 20, pink, { Radius = 6, Z = 3, Shade = 0.2, Shine = true })
	kit.Box(case, 0, 17, 92, 1.4, C.Gold, 0.2, 2)
	-- clavier
	local keys = kit.Part(body, 10, 58, 80, 12, WHITE, { Radius = 2, Z = 5, Outline = C.GreyDark, Thickness = 1.2, Shade = 0.1 })
	local keyW = 80 / 14
	for i = 1, 13 do
		kit.Box(keys, i * keyW - 0.4, 6, 0.8, 6, C.Grey, 0, 2)
	end
	for i = 0, 13 do
		local k = i % 7
		if k ~= 2 and k ~= 6 and i < 13 then
			kit.Part(keys, (i + 1) * keyW - 1.8, 0, 3.6, 7, C.Ink, { Radius = 1, Z = 3, Outline = false, Shade = false })
		end
	end
	-- pieds, lyre et pédales
	for _, x in ipairs({ 10, 82 }) do
		kit.Part(body, x, 66, 8, 30, pink, { Radius = 3, Z = 2 })
		kit.Blob(body, x + 4, 96, 10, 6, C.Gold, { Z = 3 })
	end
	kit.Part(body, 46, 66, 8, 24, kit.Darken(pink, 0.05), { Radius = 3, Z = 2 })
	kit.Part(body, 38, 88, 24, 6, pink, { Radius = 2, Z = 3 })
	for i = 0, 2 do
		kit.Part(body, 41 + i * 7, 93, 4, 4, C.Gold, { Radius = 1, Z = 4 })
	end
	local n = note(body, kit, 90, 10, 11, C.PinkDeep, 6)
	kit.Animate(n, "Bob", 2.5, 1, 0)
	local n2 = note(body, kit, 10, 16, 9, C.Purple, 6)
	kit.Animate(n2, "Bob", 2.5, 1, 1.6)
	return nil
end

-- Télescope à étoiles : tube lilas à bagues dorées sur trépied, étoiles scintillantes
Art.Telescope = function(body, kit, _item)
	local C = kit.C
	local lilac = Color3.fromRGB(190, 170, 250)
	-- trépied
	kit.Line(body, 50, 60, 50, 97, 4, C.WoodDark, 0, 1)
	kit.Line(body, 50, 60, 24, 98, 4.5, C.Wood, 0, 2)
	kit.Line(body, 50, 60, 76, 98, 4.5, C.Wood, 0, 2)
	kit.Blob(body, 50, 60, 14, 12, C.GreyDark, { Z = 3 })
	kit.Line(body, 34, 80, 66, 80, 2, C.WoodDark, 0, 2)
	-- tube incliné
	local angle = -28
	local ux, uy = math.cos(math.rad(angle)), math.sin(math.rad(angle))
	local cx, cy = 48, 44
	local function along(t, n)
		return cx + ux * t - uy * n, cy + uy * t + ux * n
	end
	local fx, fy = along(0, -14)
	kit.Part(body, fx - 12, fy - 3.5, 24, 7, C.Navy, { Radius = 3, Z = 3, Rotation = angle }) -- chercheur
	local tube = kit.Part(body, cx - 36, cy - 10, 72, 20, lilac, { Radius = 8, Z = 4, Rotation = angle, Shade = 0.2, Shine = true })
	kit.Sparkle(tube, 40, 10, 9, WHITE, 0.1, 3)
	for _, t in ipairs({ -18, 18 }) do
		local bx, by = along(t, 0)
		kit.Part(body, bx - 2.5, by - 11, 5, 22, C.Gold, { Radius = 2, Z = 5, Rotation = angle })
	end
	local lx, ly = along(38, 0)
	kit.Part(body, lx - 4, ly - 13, 8, 26, kit.Darken(lilac, 0.1), { Radius = 3, Z = 5, Rotation = angle })
	local glass = kit.Part(body, lx - 1.5, ly - 10, 5, 20, C.Glass, { Radius = -1, Z = 6, Rotation = angle })
	kit.Gradient(glass, WHITE, C.Sky, 90)
	local ex, ey = along(-40, 0)
	kit.Part(body, ex - 5, ey - 4, 10, 8, C.GreyDark, { Radius = 2, Z = 3, Rotation = angle })
	-- étoiles
	for i, s in ipairs({ { 86, 6, 11, C.Butter }, { 94, 26, 7, C.Pink }, { 70, 4, 6, C.Sky }, { 12, 14, 7, C.Butter } }) do
		local star = kit.Sparkle(body, s[1], s[2], s[3], s[4], 0, 7)
		kit.Animate(star, "Breathe", 0.15, 1.5, i * 1.1)
	end
	return nil
end

-- Mini machine à sous : dôme à ampoules, trois rouleaux (jackpot cœurs), levier, pièces
Art.SlotMachine = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 150, 190)
	-- levier
	kit.Line(body, 88, 58, 94, 24, 3, C.Grey, 0, 1)
	kit.Blob(body, 94, 22, 11, 11, C.Red, { Z = 2, Shine = true })
	kit.Part(body, 82, 52, 10, 12, C.GreyDark, { Radius = 3, Z = 1 })
	-- dôme à ampoules
	local dome = kit.Blob(body, 50, 26, 62, 36, C.Butter, { Z = 1, Shade = 0.15 })
	kit.Gradient(dome, C.Butter, C.Gold, 90)
	for i = 0, 6 do
		local a = math.rad(180 + i * 30)
		local bulb = kit.Circle(body, 50 + math.cos(a) * 25, 28 + math.sin(a) * 13, 5, 5, i % 2 == 0 and WHITE or C.PinkSoft, 0, 2)
		kit.Animate(bulb, "Pulse", 0.6, 3, i % 2 * 1.3)
	end
	kit.Heart(body, 50, 20, 11, C.Heart, 0, 2)
	-- caisse
	local cab = kit.Part(body, 12, 28, 76, 62, pink, { Radius = 12, Z = 3, Shade = 0.2, Shine = true })
	kit.Box(cab, 0, 40, 76, 1.4, kit.OutlineOf(pink), 0.5, 2)
	local frame = kit.Part(body, 18, 36, 64, 30, C.Gold, { Radius = 6, Z = 4 })
	for i = 0, 2 do
		local r = kit.Part(frame, 4 + i * 19.5, 4, 17, 22, WHITE, { Radius = 3, Z = 2, Thickness = 1, Shade = false })
		kit.Gradient(r, WHITE, C.LilacSoft, 90)
		kit.Box(r, 0, 0, 17, 4, C.Grey, 0.5, 2)
		kit.Box(r, 0, 18, 17, 4, C.Grey, 0.5, 2)
		kit.Heart(r, 8.5, 11, 12, ({ C.Heart, C.Pink, C.PinkDeep })[i + 1], 0, 3)
	end
	kit.Box(frame, 2, 14.5, 60, 1.2, C.Red, 0.4, 3) -- ligne de gain
	kit.Sparkle(body, 80, 36, 8, WHITE, 0, 6)
	-- boutons
	for i, color in ipairs({ C.Mint, C.Sky, C.Red }) do
		kit.Part(body, 26 + (i - 1) * 17, 69, 12, 5, color, { Radius = -1, Z = 4 })
	end
	-- plateau à pièces
	kit.Part(body, 22, 78, 56, 10, C.Navy, { Radius = 3, Z = 4 })
	for i, pos in ipairs({ { 36, 80 }, { 44, 81 }, { 52, 79 }, { 60, 81 } }) do
		local coin = kit.Blob(body, pos[1], pos[2], 8, 7, C.Yellow, { Z = 5, Outline = C.Gold })
		kit.Box(coin, 3.2, 1.5, 1.4, 4, C.Gold, 0, 2)
		if i == 3 then
			kit.Animate(coin, "Bob", 1, 1.5, 0)
		end
	end
	kit.Part(body, 8, 88, 84, 10, kit.Darken(pink, 0.12), { Radius = 5, Z = 2 })
	return { Glow = C.Butter }
end

-- Parabole murale : support, antenne blanche au visage, ondes qui s'échappent
Art.SatelliteDish = function(body, kit, _item)
	local C = kit.C
	local plate = kit.Part(body, 8, 58, 16, 28, C.Grey, { Radius = 3, Z = 1 })
	kit.Circle(plate, 8, 5, 3, 3, C.GreyDark, 0, 2)
	kit.Circle(plate, 8, 23, 3, 3, C.GreyDark, 0, 2)
	kit.Line(body, 16, 72, 42, 62, 5, C.GreyDark, 0, 1)
	local dish = kit.Blob(body, 48, 48, 50, 66, WHITE, { Z = 3, Rotation = -32, Shade = 0.18, Outline = Color3.fromRGB(170, 170, 200) })
	kit.Blob(dish, 27, 33, 38, 54, C.LilacSoft, { Z = 2, Outline = false, Shade = 0.1 })
	kit.Face(body, 42, 56, 22, { Eyes = "happy", Mouth = "smile", Z = 4 })
	kit.Circle(body, 54, 42, 5, 5, C.GreyDark, 0, 4)
	kit.Line(body, 54, 42, 72, 29, 2.4, C.GreyDark, 0, 4)
	kit.Part(body, 68, 22, 12, 10, C.Pink, { Radius = 3, Z = 5, Rotation = -40, Shine = true })
	-- ondes (quarts de cercle)
	local waves = kit.Group(body, 78, 0, 24, 24, 6, true)
	for i, r in ipairs({ 8, 14, 20 }) do
		local ring = kit.Part(waves, -r, 24 - r, r * 2, r * 2, WHITE, { T = 1, Radius = -1, Thickness = 2, Outline = i % 2 == 0 and C.Pink or C.Sky, Shade = false })
		kit.Animate(ring, "Breathe", 0.08, 1.8, i * 0.7)
	end
	kit.Sparkle(body, 90, 34, 7, C.Butter, 0, 6)
	return { WallShadow = Vector2.new(0.62, 0.66) }
end

-- Casque de réalité virtuelle : visière blanche, écran aux yeux lumineux, sangle
Art.VRGoggles = function(body, kit, _item)
	local C = kit.C
	local strap = kit.Part(body, 10, 34, 80, 56, WHITE, { T = 1, Radius = 24, Thickness = 7, Outline = C.Lilac, Z = 1 })
	strap.Rotation = 0
	kit.Part(body, 36, 28, 28, 10, C.Lilac, { Radius = -1, Z = 1 })
	local visor = kit.Part(body, 8, 42, 84, 46, WHITE, { Radius = 18, Z = 2, Shade = 0.2, Shine = true, Outline = Color3.fromRGB(170, 160, 210) })
	kit.Box(visor, 40, 40, 4, 6, C.Grey, 0.3, 2)
	local s = screen(body, kit, 16, 48, 68, 32, Color3.fromRGB(70, 60, 130), Color3.fromRGB(40, 36, 90), 3, 13, 0.5)
	-- yeux lumineux ^ ^
	for _, x in ipairs({ 22, 46 }) do
		kit.Line(s, x - 6, 18, x, 11, 3, C.Mint, 0, 3)
		kit.Line(s, x, 11, x + 6, 18, 3, C.Mint, 0, 3)
	end
	kit.Circle(s, 14, 23, 7, 3.5, C.Pink, 0.3, 3)
	kit.Circle(s, 54, 23, 7, 3.5, C.Pink, 0.3, 3)
	kit.Heart(s, 34, 22, 6, C.Pink, 0, 3)
	for i, pos in ipairs({ { 10, 30 }, { 92, 36 } }) do
		local sp = kit.Sparkle(body, pos[1], pos[2], 8, i == 1 and C.Butter or C.Sky, 0, 6)
		kit.Animate(sp, "Breathe", 0.15, 1.5, i)
	end
	return { Glow = C.Mint }
end

-- Home cinéma : grand écran (film de nuit étoilée), enceintes colonnes, meuble, pop-corn
Art.HomeCinema = function(body, kit, _item)
	local C = kit.C
	local dark = Color3.fromRGB(96, 84, 130)
	-- écran
	kit.Part(body, 12, 4, 76, 50, dark, { Radius = 6, Z = 2, Shade = 0.1 })
	local s = screen(body, kit, 15, 7, 70, 44, Color3.fromRGB(120, 110, 220), Color3.fromRGB(255, 170, 200), 3, 3, 0.2)
	kit.Circle(s, 52, 12, 11, 11, C.Butter, 0, 2) -- lune
	kit.Circle(s, 55, 10, 9, 9, Color3.fromRGB(150, 130, 220), 0, 2)
	kit.Blob(s, 18, 44, 50, 24, C.Mint, { Z = 3, Outline = false, Shade = false })
	kit.Blob(s, 52, 46, 50, 22, C.Leaf, { Z = 3, Outline = false, Shade = false })
	kit.Cloud(s, 26, 18, 16, WHITE, 0.2, 2)
	for i, pos in ipairs({ { 10, 8 }, { 36, 6 }, { 64, 22 } }) do
		local sp = kit.Sparkle(s, pos[1], pos[2], 5, WHITE, 0, 2)
		kit.Animate(sp, "Breathe", 0.2, 1.4, i)
	end
	-- barre de son
	local bar = kit.Part(body, 24, 56, 52, 6, dark, { Radius = -1, Z = 3 })
	kit.Box(bar, 6, 2, 40, 1.4, C.Grey, 0.4, 2)
	-- meuble TV
	local cab = kit.Part(body, 12, 64, 76, 30, C.WoodLight, { Radius = 6, Z = 2, Shade = 0.18, Shine = true })
	for i = 0, 1 do
		local d = kit.Part(cab, 4 + i * 35, 4, 33, 22, C.Wood, { Radius = 4, Z = 2, Shade = false, Thickness = 1.2 })
		kit.Circle(d, i == 0 and 28 or 5, 11, 3, 3, C.Gold, 0, 2)
	end
	kit.Part(body, 16, 93, 6, 6, C.WoodDark, { Radius = 2, Z = 1 })
	kit.Part(body, 78, 93, 6, 6, C.WoodDark, { Radius = 2, Z = 1 })
	-- enceintes colonnes
	for _, x in ipairs({ 1, 85 }) do
		local sp = kit.Part(body, x, 34, 14, 64, dark, { Radius = 5, Z = 3, Shade = 0.15, Shine = true })
		kit.Circle(sp, 7, 10, 7, 7, C.Grey, 0, 2)
		local w = kit.Circle(sp, 7, 28, 10, 10, C.Grey, 0, 2)
		kit.Circle(w, 5, 5, 4, 4, C.Pink, 0, 2)
		local w2 = kit.Circle(sp, 7, 46, 10, 10, C.Grey, 0, 2)
		kit.Circle(w2, 5, 5, 4, 4, C.Pink, 0, 2)
		kit.Animate(w, "Breathe", 0.06, 3, x)
		kit.Animate(w2, "Breathe", 0.06, 3, x + 1)
	end
	-- pop-corn
	for i, pos in ipairs({ { 58, 76 }, { 64, 73 }, { 70, 76 }, { 61, 70 }, { 67, 69 } }) do
		kit.Blob(body, pos[1], pos[2], 8, 7, i % 2 == 0 and C.Cream or C.Butter, { Z = 5, Thickness = 1 })
	end
	local bucket = kit.Part(body, 56, 76, 16, 22, WHITE, { Radius = 3, Z = 6, Thickness = 1.2 })
	for i = 0, 2 do
		kit.Box(bucket, 1.5 + i * 5, 0, 2.6, 22, C.Red, 0.1, 2)
	end
	return { Glow = C.LilacSoft }
end

return Art
