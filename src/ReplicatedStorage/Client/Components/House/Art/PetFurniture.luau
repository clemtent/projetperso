--[[
	PetFurniture (ModuleScript) — dessins 🐾 des affaires des animaux :
	gamelle, panier de jouets, coussin, griffoir, fontaine, niche, cage à
	oiseaux, arbre à chat. Les animaux posés dans la pièce viennent s'en
	servir (House/HousePets + House/HouseSurfaces : places "PetSpots").
	Emplacement : ReplicatedStorage > Client > Components > House > Art > PetFurniture
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

----------------------------------------------------------------------
-- Aides communes
----------------------------------------------------------------------

-- Empreinte de patte (coussinet + 3 doigts)
local function paw(parent, kit, cx, cy, size, color, t, z)
	kit.Blob(parent, cx, cy + size * 0.12, size * 0.56, size * 0.46, color, { Z = z, T = t, Outline = false, Shade = false })
	for _, d in ipairs({ { -0.34, -0.26 }, { 0, -0.42 }, { 0.34, -0.26 } }) do
		kit.Circle(parent, cx + d[1] * size, cy + d[2] * size, size * 0.24, size * 0.26, color, t or 0, z)
	end
end

-- Petit os (deux boules à chaque bout)
local function bone(parent, kit, cx, cy, length, color, rotation, z)
	local p = kit.Pivot(parent, cx, cy, z)
	p.Rotation = rotation or 0
	local r = length * 0.26
	kit.Part(p, -length / 2 + r * 0.5, -r * 0.42, length - r, r * 0.84, color, { Radius = -1, Z = 1, Thickness = 1.2, Shade = false })
	for _, side in ipairs({ -1, 1 }) do
		for _, dy in ipairs({ -1, 1 }) do
			kit.Circle(p, side * (length / 2 - r * 0.45), dy * r * 0.36, r * 0.9, r * 0.9, color, 0, 2)
		end
	end
	return p
end

-- Corde de sisal (poteau à griffer) : bande beige + rayures
local function sisal(parent, kit, x, y, w, h, z)
	local C = kit.C
	local rope = Color3.fromRGB(236, 214, 170)
	local post = kit.Part(parent, x, y, w, h, rope, { Radius = 3, Z = z, Shade = 0.1 })
	kit.Gradient(post, Color3.fromRGB(255, 255, 255), Color3.fromRGB(226, 226, 226), 0)
	local line = kit.Darken(rope, 0.18)
	local step = 5
	local yy = 3
	while yy < h - 2 do
		kit.Box(post, 1, yy, w - 2, 1.4, line, 0.25, 2)
		yy += step
	end
	-- griffures
	kit.Line(post, w * 0.3, h * 0.3, w * 0.45, h * 0.46, 1.2, C.White, 0.3, 3)
	kit.Line(post, w * 0.55, h * 0.32, w * 0.7, h * 0.48, 1.2, C.White, 0.3, 3)
	return post
end

----------------------------------------------------------------------
-- Dessins
----------------------------------------------------------------------

-- Gamelle rose avec une patte, pleine de croquettes, et un petit os
Art.PetBowl = function(body, kit, _item)
	local C = kit.C
	local bowl = C.Pink
	-- croquettes (derrière le rebord)
	local kibble = { Color3.fromRGB(196, 132, 92), Color3.fromRGB(226, 164, 110), Color3.fromRGB(176, 112, 80) }
	for index, k in ipairs({ { 30, 60 }, { 40, 56 }, { 50, 54 }, { 60, 56 }, { 70, 60 }, { 36, 64 }, { 46, 61 }, { 56, 61 }, { 65, 64 } }) do
		kit.Blob(body, k[1], k[2], 11, 9, kibble[index % 3 + 1], { Z = 2, Thickness = 1.1, Shade = false })
	end
	kit.Heart(body, 50, 51, 9, C.Heart, 0, 3)
	-- bol
	local base = kit.Part(body, 12, 64, 76, 32, bowl, { Radius = 14, Z = 4, Shade = 0.2 })
	kit.Gradient(base, Color3.fromRGB(255, 255, 255), Color3.fromRGB(225, 225, 225), 90)
	kit.Part(body, 6, 60, 88, 11, kit.Lighten(bowl, 0.25), { Radius = -1, Z = 5, Shine = true })
	kit.Part(body, 18, 92, 64, 7, kit.Darken(bowl, 0.12), { Radius = -1, Z = 3, Shade = false })
	paw(body, kit, 50, 80, 16, C.White, 0.1, 6)
	-- os à côté
	bone(body, kit, 86, 93, 20, C.Cream, -18, 7)
	local spark = kit.Sparkle(body, 18, 48, 8, C.Butter, 0, 7)
	kit.Animate(spark, "Bob", 2, 0.8, 0.4)
	return nil
end

-- Panier en osier rempli de jouets : balle de tennis, os, souris, corde
Art.PetToys = function(body, kit, _item)
	local C = kit.C
	-- jouets qui dépassent (derrière le rebord)
	local rope = kit.Pivot(body, 30, 52, 2)
	rope.Rotation = -24
	kit.Part(rope, -4, -24, 8, 30, C.Sky, { Radius = -1, Z = 1, Thickness = 1.2 })
	for k = 0, 3 do
		kit.Line(rope, -4, -20 + k * 7, 4, -16 + k * 7, 1.5, C.White, 0.2, 2)
	end
	kit.Blob(rope, 0, -26, 10, 7, C.PinkDeep, { Z = 3, Thickness = 1.1 })
	bone(body, kit, 64, 42, 30, C.Cream, 28, 3)
	-- souris en peluche
	local mouse = kit.Group(body, 36, 36, 26, 22, 4)
	kit.Circle(mouse, 6, 5, 9, 9, C.Grey, 0, 1)
	kit.Circle(mouse, 6, 5, 5, 5, C.PinkSoft, 0, 2)
	kit.Blob(mouse, 14, 13, 22, 16, C.Grey, { Z = 3, Shine = true })
	kit.Face(mouse, 11, 13, 12, { Mouth = "none", Z = 4 })
	-- balle de tennis (elle rebondit un peu)
	local ball = kit.Group(body, 58, 44, 22, 22, 5)
	local b = kit.Blob(ball, 11, 11, 21, 21, Color3.fromRGB(214, 240, 110), { Z = 1, Shine = true })
	kit.Line(b, 3, 6, 10, 11, 1.6, C.White, 0, 2)
	kit.Line(b, 10, 11, 18, 5, 1.6, C.White, 0, 2)
	kit.Animate(ball, "Bob", 1.6, 1.3, 0.2)
	-- panier
	local basket = kit.Part(body, 10, 60, 80, 38, C.WoodLight, { Radius = 12, Z = 6, Shade = 0.18 })
	for _, y in ipairs({ 11, 19, 27 }) do
		kit.Box(basket, 3, y, 74, 2, C.Wood, 0.1, 2)
	end
	for x = 10, 70, 12 do
		kit.Box(basket, x, 4, 2, 30, C.Wood, 0.45, 2)
	end
	kit.Part(body, 5, 56, 90, 10, C.Wood, { Radius = -1, Z = 7, Shine = true })
	-- étiquette cœur
	kit.Part(body, 40, 72, 20, 16, C.PinkSoft, { Radius = 5, Z = 8 })
	kit.Heart(body, 50, 80, 10, C.Heart, 0, 9)
	return nil
end

-- Coussin rond pour animaux : gros boudin lilas, fond crème, os en peluche
Art.PetBed = function(body, kit, _item)
	local C = kit.C
	local rim = Color3.fromRGB(196, 170, 246)
	-- boudin arrière
	kit.Blob(body, 50, 66, 94, 40, rim, { Z = 1, Shade = 0.15 })
	-- coussin intérieur
	local cushion = kit.Blob(body, 50, 76, 76, 24, C.Cream, { Z = 2, Thickness = 1.4, Shade = 0.1 })
	for _, s in ipairs({ { 28, 10 }, { 50, 7 }, { 72, 11 } }) do
		kit.Circle(cushion, s[1], s[2], 3, 3, C.PinkSoft, 0, 2)
	end
	-- os en peluche
	bone(body, kit, 70, 74, 24, C.White, -14, 3)
	-- boudin avant (plus bas : on voit dedans)
	kit.Part(body, 4, 80, 92, 19, kit.Lighten(rim, 0.1), { Radius = -1, Z = 4, Shine = true, Shade = 0.2 })
	for _, x in ipairs({ 22, 50, 78 }) do
		kit.Line(body, x, 82, x, 96, 1.4, kit.Darken(rim, 0.15), 0.35, 5)
	end
	paw(body, kit, 50, 89.5, 9, C.White, 0.15, 5)
	for index, h in ipairs({ { 20, 50, 7 }, { 82, 46, 6 } }) do
		local heart = kit.Heart(body, h[1], h[2], h[3], C.Pink, 0.1, 6)
		kit.Animate(heart, "Bob", 1.5, 0.7, index * 1.7)
	end
	return nil
end

-- Griffoir : socle moquette, poteau de sisal griffé, plateau rond et pompon qui se balance
Art.ScratchingPost = function(body, kit, _item)
	local C = kit.C
	local carpet = Color3.fromRGB(255, 186, 206)
	-- socle
	kit.Part(body, 10, 86, 80, 12, carpet, { Radius = 5, Z = 1, Shine = true, Shade = 0.2 })
	kit.Part(body, 14, 96, 72, 4, kit.Darken(carpet, 0.2), { Radius = -1, Z = 0, Shade = false })
	-- poteau
	sisal(body, kit, 39, 22, 22, 66, 2)
	-- plateau
	kit.Part(body, 22, 14, 56, 11, carpet, { Radius = -1, Z = 3, Shine = true })
	kit.Part(body, 26, 9, 48, 9, kit.Lighten(carpet, 0.35), { Radius = -1, Z = 4, Thickness = 1.3, Shade = false })
	-- pompon au bout d'une ficelle (pendule)
	local toy = kit.Pivot(body, 72, 22, 5)
	kit.Line(toy, 0, 0, 0, 30, 1.2, C.GreyDark, 0.2, 1)
	kit.Blob(toy, 0, 34, 12, 12, C.Lilac, { Z = 2, Shine = true })
	kit.Circle(toy, -2, 32, 3, 3, C.White, 0.3, 3)
	kit.Animate(toy, "Sway", 12, 0.9, 0.3)
	-- pattes brodées sur le socle
	paw(body, kit, 22, 92, 7, C.White, 0.2, 2)
	paw(body, kit, 78, 92, 7, C.White, 0.2, 2)
	return nil
end

-- Fontaine à eau : vasque ronde, dôme menthe souriant, jet d'eau et bulles
Art.PetFountain = function(body, kit, _item)
	local C = kit.C
	local mint = Color3.fromRGB(150, 222, 214)
	-- bec verseur et gouttes qui retombent en arc dans la vasque
	for index, d in ipairs({ { 55, 24, 6 }, { 62, 22, 5.5 }, { 69, 26, 5 }, { 74, 34, 4.5 }, { 77, 44, 4 }, { 79, 54, 3.5 } }) do
		local drop = kit.Circle(body, d[1], d[2], d[3], d[3], kit.Lighten(C.Sky, 0.15), 0.05, 6)
		kit.Stroke(drop, kit.Darken(C.Sky, 0.1), 1, 0.3)
		kit.Animate(drop, "Pulse", 0.5, 2.2, -index * 0.45)
	end
	-- dôme
	local dome = kit.Blob(body, 50, 56, 50, 44, mint, { Z = 3, Shine = true })
	kit.Face(dome, 25, 22, 24, { Eyes = "happy", Mouth = "smile", Z = 4 })
	kit.Part(body, 44, 26, 12, 10, kit.Darken(mint, 0.15), { Radius = 4, Z = 4, Shine = true })
	kit.Part(body, 46, 21, 12, 6, kit.Darken(mint, 0.1), { Radius = -1, Z = 5 })
	-- vasque et eau
	kit.Part(body, 6, 70, 88, 16, kit.Lighten(C.Sky, 0.25), { Radius = -1, Z = 5, T = 0.05, Shine = true })
	local water = kit.Part(body, 12, 72, 76, 6, C.Sky, { Radius = -1, Z = 6, Outline = false, Shade = false })
	kit.Animate(water, "Pulse", 0.3, 1, 1.2)
	kit.Part(body, 10, 80, 80, 18, mint, { Radius = 8, Z = 7, Shade = 0.22 })
	paw(body, kit, 50, 89, 8, C.White, 0.15, 8)
	for index, b in ipairs({ { 28, 66, 5 }, { 72, 64, 4 }, { 20, 58, 3 } }) do
		local bubble = kit.Circle(body, b[1], b[2], b[3], b[3], C.White, 0.4, 8)
		kit.Stroke(bubble, C.Sky, 1, 0.2)
		kit.Animate(bubble, "Bob", 2, 0.9, index * 1.3)
	end
	return nil
end

-- Niche : toit de tuiles rose avec un cœur, planches crème, porte ronde, écriteau os
Art.DogHouse = function(body, kit, _item)
	local C = kit.C
	local wall = Color3.fromRGB(255, 226, 196)
	local roof = Color3.fromRGB(240, 120, 140)
	local plank = kit.Darken(wall, 0.12)
	-- murs
	local walls = kit.Part(body, 14, 44, 72, 54, wall, { Radius = 4, Z = 2, Shade = 0.14 })
	for _, y in ipairs({ 13, 26, 39 }) do
		kit.Box(walls, 2, y, 68, 1.6, plank, 0.2, 2)
	end
	-- porte (arche sombre)
	local door = kit.Group(body, 33, 58, 34, 40, 3, true)
	kit.Part(door, 0, 0, 34, 60, Color3.fromRGB(92, 62, 86), { Radius = -1, Z = 1, Thickness = 1.8, Shade = 0.25 })
	kit.Blob(door, 17, 44, 30, 12, Color3.fromRGB(70, 46, 70), { Z = 2, Outline = false, Shade = false })
	kit.Part(body, 31, 56, 38, 5, C.Cream, { Radius = -1, Z = 4 })
	-- toit
	kit.Triangle(body, 50, 6, 104, 44, roof, 5, 0, 30)
	-- reflet sur le pan gauche du toit
	kit.Line(body, 30, 36, 46, 16, 2.4, kit.Lighten(roof, 0.4), 0.2, 6)
	-- tuiles en festons
	for index = 0, 4 do
		kit.Circle(body, 12 + index * 19, 49, 20, 10, kit.Darken(roof, 0.08), 0, 6)
	end
	kit.Part(body, 0, 42, 100, 6, kit.Darken(roof, 0.15), { Radius = -1, Z = 7, Shine = true })
	local heart = kit.Heart(body, 50, 26, 14, C.White, 0.05, 7)
	kit.Animate(heart, "Breathe", 0.06, 1.2, 0.3)
	-- écriteau os au-dessus de la porte (il se balance)
	local sign = kit.Pivot(body, 50, 45, 8)
	kit.Line(sign, -6, 0, -6, 5, 1, C.GreyDark, 0.2, 1)
	kit.Line(sign, 6, 0, 6, 5, 1, C.GreyDark, 0.2, 1)
	bone(sign, kit, 0, 8, 22, C.Cream, 0, 2)
	kit.Animate(sign, "Sway", 3, 0.7, 0.8)
	-- petite gamelle devant
	kit.Part(body, 76, 88, 20, 10, C.Sky, { Radius = 4, Z = 8, Shine = true })
	kit.Part(body, 74, 86, 24, 4, kit.Lighten(C.Sky, 0.3), { Radius = -1, Z = 9 })
	return nil
end

-- Cage à oiseaux dorée : dôme de barreaux, anneau, balançoire, mangeoire et socle
Art.BirdCage = function(body, kit, _item)
	local C = kit.C
	local gold = C.Gold
	local line = kit.Darken(gold, 0.2)
	-- fond de la cage (verre bleuté léger)
	kit.Blob(body, 50, 36, 64, 44, C.Glass, { Z = 1, T = 0.55, Outline = false, Shade = false })
	kit.Part(body, 18, 36, 64, 44, C.Glass, { Radius = 2, Z = 1, T = 0.55, Outline = false, Shade = false })
	-- balançoire (pendule)
	local swing = kit.Pivot(body, 50, 20, 3)
	kit.Line(swing, -9, 0, -9, 34, 1.2, line, 0, 1)
	kit.Line(swing, 9, 0, 9, 34, 1.2, line, 0, 1)
	kit.Part(swing, -13, 33, 26, 4, C.Wood, { Radius = -1, Z = 2 })
	kit.Heart(swing, 0, 44, 7, C.Pink, 0.1, 2)
	kit.Animate(swing, "Sway", 6, 0.8, 0.2)
	-- mangeoire
	kit.Part(body, 22, 66, 14, 8, C.Sky, { Radius = 3, Z = 3, Shine = true })
	kit.Circle(body, 26, 66, 3, 3, C.Butter, 0, 4)
	kit.Circle(body, 31, 66, 3, 3, C.Butter, 0, 4)
	-- barreaux (dôme = arc + montants)
	local dome = kit.Blob(body, 50, 36, 66, 46, gold, { Z = 5, T = 1, Outline = gold, Thickness = 2.6, Shade = false })
	dome.BackgroundTransparency = 1
	for _, x in ipairs({ 17, 83 }) do
		kit.Line(body, x, 34, x, 82, 2.6, gold, 0, 5)
	end
	for _, x in ipairs({ 30, 42, 50, 58, 70 }) do
		local top = 36 - math.sqrt(math.max(0, 1 - ((x - 50) / 33) ^ 2)) * 22
		kit.Line(body, x, top + 1, x, 82, 1.6, gold, 0.1, 5)
	end
	kit.Line(body, 17, 54, 83, 54, 1.4, gold, 0.2, 5)
	-- anneau et petit cœur en haut
	local ring = kit.Circle(body, 50, 5, 9, 9, gold, 1, 6)
	kit.Stroke(ring, gold, 2)
	kit.Blob(body, 50, 13, 9, 7, gold, { Z = 6, Shine = true })
	-- base et pied
	kit.Part(body, 12, 78, 76, 10, C.PinkSoft, { Radius = -1, Z = 6, Shine = true })
	kit.Part(body, 44, 88, 12, 6, gold, { Radius = 2, Z = 5 })
	kit.Part(body, 30, 93, 40, 6, C.Pink, { Radius = -1, Z = 6, Shade = 0.2 })
	local note = kit.Text(body, "♪", 84, 18, 12, C.Purple, 7)
	kit.Animate(note, "Bob", 2, 0.8, 1.2)
	return nil
end

-- Arbre à chat : socle, poteaux de sisal, niche ronde, plateau bas et
-- coussin tout en haut, pompons qui pendent
Art.CatTree = function(body, kit, _item)
	local C = kit.C
	local carpet = Color3.fromRGB(206, 186, 250)
	local carpetB = Color3.fromRGB(255, 196, 214)
	-- socle
	kit.Part(body, 4, 88, 92, 10, carpet, { Radius = 5, Z = 1, Shine = true, Shade = 0.2 })
	-- poteaux
	sisal(body, kit, 68, 62, 10, 28, 2)
	sisal(body, kit, 22, 80, 10, 10, 2)
	sisal(body, kit, 30, 22, 10, 34, 2)
	-- niche (cube avec trou rond)
	local cube = kit.Part(body, 6, 52, 42, 30, carpetB, { Radius = 7, Z = 3, Shine = true, Shade = 0.18 })
	kit.Blob(cube, 21, 17, 18, 18, Color3.fromRGB(110, 70, 100), { Z = 2, Thickness = 1.4, Shade = 0.3 })
	paw(cube, kit, 36, 7, 6, C.White, 0.25, 2)
	-- plateau bas (à droite)
	kit.Part(body, 52, 56, 44, 9, carpetB, { Radius = -1, Z = 4, Shine = true })
	-- coussin rond tout en haut
	kit.Part(body, 12, 14, 48, 12, carpet, { Radius = -1, Z = 4, Shine = true })
	kit.Part(body, 16, 9, 40, 8, kit.Lighten(carpet, 0.35), { Radius = -1, Z = 5, Thickness = 1.3, Shade = false })
	kit.Heart(body, 36, 20, 7, C.White, 0.1, 6)
	-- pompons
	for index, p in ipairs({ { 90, 64, C.Butter, 22 }, { 14, 25, C.Mint, 16 } }) do
		local toy = kit.Pivot(body, p[1], p[2], 6)
		kit.Line(toy, 0, 0, 0, p[4], 1.1, C.GreyDark, 0.2, 1)
		kit.Blob(toy, 0, p[4] + 4, 9, 9, p[3], { Z = 2, Shine = true })
		kit.Animate(toy, "Sway", 10, 0.8, index * 1.4)
	end
	return nil
end

return Art
