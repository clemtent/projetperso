--[[
	Tabletop (ModuleScript) — petits objets à poser partout (tables, étagères, lit...) 🧁
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Tabletop
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas : posés sur un meuble,
	leurs pieds sont sur le dessus du meuble).
]]

local Art = {}

----------------------------------------------------------------------
-- Petits outils partagés
----------------------------------------------------------------------

-- Assiette vue un peu de dessus (ovale + creux) ; (cx, cy) = centre
local function plate(kit, parent, cx, cy, w, color, z)
	local C = kit.C
	kit.Blob(parent, cx, cy, w, w * 0.3, color or C.White, { Z = z, Thickness = 1.4 })
	kit.Blob(parent, cx, cy - w * 0.02, w * 0.66, w * 0.17, kit.Darken(color or C.White, 0.06), { Z = (z or 1) + 1, Outline = false, Shade = false })
end

-- Petite flamme de bougie qui vacille
local function flame(kit, parent, cx, bottom, w, h, z, phase)
	local C = kit.C
	local holder = kit.Group(parent, cx - w / 2, bottom - h, w, h, z)
	kit.Circle(holder, w / 2, h * 0.62, w, h * 0.72, C.Orange, 0, 1)
	kit.Circle(holder, w / 2, h * 0.7, w * 0.55, h * 0.45, C.Butter, 0, 2)
	kit.Animate(holder, "Flicker", 0.15, 1, phase or 0)
	return holder
end

-- Petit livre couché (tranche vers nous) ; (x, y) = haut gauche
local function book(kit, parent, x, y, w, h, color, z)
	local C = kit.C
	local cover = kit.Part(parent, x, y, w, h, color, { Radius = 2, Z = z, Thickness = 1.3 })
	kit.Box(cover, 3, h * 0.28, w - 8, h * 0.44, C.Cream, 0, 2) -- pages
	kit.Box(cover, w - 6, 1.5, 3, h - 3, kit.Lighten(color, 0.3), 0, 2)
	return cover
end

----------------------------------------------------------------------
-- 🖼️ Déco
----------------------------------------------------------------------

-- Pile de livres pastel + lunettes rondes
Art.BookStack = function(body, kit, _item)
	local C = kit.C
	book(kit, body, 8, 78, 84, 20, C.Lilac, 1)
	book(kit, body, 14, 58, 72, 20, C.Mint, 2)
	book(kit, body, 4, 40, 80, 18, C.Pink, 3)
	book(kit, body, 18, 24, 62, 16, C.Butter, 4)
	-- petites lunettes posées dessus
	for _, x in ipairs({ 38, 58 }) do
		local lens = kit.Circle(body, x, 16, 15, 15, C.Glass, 0.35, 5)
		kit.Stroke(lens, C.Ink, 2)
	end
	kit.Line(body, 45, 16, 51, 16, 2, C.Ink, 0, 5)
	return nil
end

-- Coussin cœur qui sourit, petit nœud sur le dessus
Art.HeartPillow = function(body, kit, _item)
	local C = kit.C
	kit.Heart(body, 50, 56, 96, kit.Darken(C.Pink, 0.18), 0, 1)
	local heart = kit.Heart(body, 50, 54, 88, C.Pink, 0, 2)
	kit.Shine(heart, 18, 20, 18, 7, 3)
	kit.Face(heart, 44, 44, 34, { Eyes = "happy", Mouth = "smile", Z = 4 })
	-- nœud
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(body, 50 + side * 9 - 7, 12, 14, 12, C.White, { Radius = 5, Z = 3, Rotation = side * 18 })
	end
	kit.Blob(body, 50, 18, 8, 8, C.White, { Z = 4 })
	return nil
end

-- Coussin rond "pleine lune" endormie, brodé d'un croissant et d'une étoile
Art.MoonPillow = function(body, kit, _item)
	local C = kit.C
	local pillow = kit.Part(body, 6, 22, 88, 76, C.Butter, { Radius = 34, Z = 1, Shine = true })
	for _, spot in ipairs({ { 8, 8 }, { 80, 8 }, { 8, 68 }, { 80, 68 } }) do
		kit.Circle(pillow, spot[1], spot[2], 9, 9, kit.Darken(C.Butter, 0.08), 0, 1) -- coins bombés
	end
	kit.Face(pillow, 44, 44, 34, { Eyes = "closed", Mouth = "cat", Z = 3 })
	-- croissant brodé (2 cercles) + étoile
	kit.Circle(pillow, 20, 20, 14, 14, C.Lilac, 0, 2)
	kit.Circle(pillow, 24, 17, 12, 12, C.Butter, 0, 3)
	local star = kit.Sparkle(body, 76, 36, 16, C.Pink, 0, 4)
	kit.Animate(star, "Breathe", 0.08, 1.2, 0)
	-- passepoil
	kit.Box(pillow, 12, 72, 64, 2, kit.Darken(C.Butter, 0.2), 0.3, 2)
	return nil
end

-- Cadre photo sur pied : photo d'un chat devant un arc-en-ciel
Art.PhotoFrame = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 62, 60, 80, 99, 5, C.WoodDark, 0, 1) -- béquille
	local frame = kit.Part(body, 10, 12, 80, 86, C.PinkSoft, { Radius = 10, Z = 2, Shine = true })
	for _, spot in ipairs({ { 8, 8 }, { 72, 8 }, { 8, 78 }, { 72, 78 } }) do
		kit.Heart(frame, spot[1], spot[2], 8, C.Pink, 0, 3)
	end
	local photo = kit.Part(frame, 12, 12, 56, 62, C.Sky, { Radius = 4, Z = 2, Thickness = 1.2, Shade = false })
	kit.Blob(photo, 28, 62, 70, 30, C.Leaf, { Z = 2, Outline = false, Shade = false })
	for index, color in ipairs({ C.Red, C.Butter, C.Mint }) do
		local arc = kit.Circle(photo, 28, 46, 60 - index * 10, 60 - index * 10, C.White, 1, 1)
		kit.Stroke(arc, color, 2.4)
	end
	local cat = kit.Blob(photo, 28, 44, 24, 20, C.White, { Z = 3, Thickness = 1.2 })
	kit.Face(cat, 12, 10, 14, { Eyes = "happy", Mouth = "cat", Z = 2 })
	return nil
end

-- Pile de plaids pliés (carreaux, torsades) + petit ruban
Art.BlanketStack = function(body, kit, _item)
	local C = kit.C
	local colors = { C.MintSoft, C.PinkSoft, C.LilacSoft, kit.Lighten(C.Butter, 0.4) }
	for index, color in ipairs(colors) do
		local y = 100 - index * 22
		local fold = kit.Part(body, 6 + (index % 2) * 4, y, 86, 22, color, { Radius = 9, Z = index, Shine = index == #colors })
		kit.Box(fold, 6, 9, 74, 2, kit.Darken(color, 0.18), 0.3, 2)
		if index == 2 then
			for x = 12, 72, 12 do
				kit.Box(fold, x, 2, 2, 18, kit.Darken(color, 0.15), 0.4, 2)
			end
		end
	end
	kit.Heart(body, 50, 24, 12, C.PinkDeep, 0, 6)
	return nil
end

-- Tirelire cochon rose
Art.PiggyBank = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 178, 204)
	for _, x in ipairs({ 26, 40, 60, 74 }) do
		kit.Part(body, x - 5, 82, 10, 16, kit.Darken(pink, 0.1), { Radius = 4, Z = 1 })
	end
	local pig = kit.Blob(body, 50, 60, 88, 60, pink, { Z = 2, Shine = true })
	kit.Box(pig, 38, 3, 12, 3, kit.Darken(pink, 0.4), 0, 2) -- fente
	for _, x in ipairs({ 30, 60 }) do
		kit.Part(body, x - 7, 26, 14, 14, pink, { Radius = 4, Z = 1, Rotation = 45 }) -- oreilles
	end
	local nose = kit.Blob(body, 16, 62, 20, 16, kit.Darken(pink, 0.08), { Z = 3 })
	kit.Circle(nose, 7, 8, 4, 5, kit.Darken(pink, 0.45), 0, 2)
	kit.Circle(nose, 13, 8, 4, 5, kit.Darken(pink, 0.45), 0, 2)
	kit.Face(body, 36, 52, 26, { Eyes = "dot", Mouth = "none", Z = 4 })
	local coin = kit.Blob(body, 48, 16, 16, 16, C.Gold, { Z = 3, Shine = true })
	kit.Text(coin, "$", 8, 8, 10, kit.Darken(C.Gold, 0.4), 2)
	kit.Animate(coin, "Bob", 2.5, 1, 0)
	return nil
end

-- Boule à neige : petit chalet, sapin, flocons qui tombent
Art.SnowGlobe = function(body, kit, _item)
	local C = kit.C
	local base = kit.Part(body, 16, 78, 68, 20, C.WoodLight, { Radius = 6, Z = 1, Shine = true })
	kit.Heart(base, 34, 10, 10, C.Pink, 0, 2)
	local globe = kit.Circle(body, 50, 46, 76, 76, C.Glass, 0.3, 2)
	kit.Stroke(globe, kit.Darken(C.Glass, 0.3), 2)
	-- (pas de découpe : les formes restent dans la boule)
	kit.Blob(globe, 38, 62, 58, 18, C.White, { Z = 1, Outline = false, Shade = false })
	local house = kit.Part(globe, 18, 38, 20, 18, C.PinkSoft, { Radius = 3, Z = 2, Thickness = 1.2 })
	kit.Box(house, 7, 9, 6, 9, C.WoodDark, 0, 2)
	kit.Triangle(globe, 28, 26, 26, 14, C.Red, 3)
	kit.Triangle(globe, 52, 22, 20, 34, C.LeafDark, 2)
	for index = 1, 6 do
		local flake = kit.Circle(globe, 14 + index * 8, 14 + (index * 17) % 30, 4, 4, C.White, 0, 4)
		kit.Animate(flake, "Bob", 3, 0.7, index)
	end
	kit.Shine(globe, 14, 12, 12, 22, 5, 0.3)
	return nil
end

-- Boîte à musique : couvercle ouvert (miroir), danseuse qui tourne
Art.MusicBox = function(body, kit, _item)
	local C = kit.C
	-- couvercle ouvert derrière la boîte (on voit son miroir)
	local lid = kit.Part(body, 12, 22, 76, 38, C.Pink, { Radius = 8, Z = 1 })
	local mirror = kit.Part(lid, 6, 5, 64, 26, Color3.fromRGB(230, 244, 255), { Radius = 5, Z = 2, Thickness = 1.2, Shade = false })
	kit.Shine(mirror, 8, 4, 16, 5, 3)
	kit.Heart(lid, 38, 34, 6, C.Gold, 0, 3)
	local box = kit.Part(body, 8, 58, 84, 40, C.Pink, { Radius = 8, Z = 2, Shine = true })
	kit.Box(box, 0, 12, 84, 4, C.Gold, 0, 2)
	kit.Heart(box, 42, 27, 13, C.White, 0, 3)
	kit.Blob(body, 94, 80, 8, 12, C.Gold, { Z = 3, Thickness = 1 }) -- clé
	-- danseuse sur son pied
	local dancer = kit.Pivot(body, 50, 60, 3)
	kit.Part(dancer, -1.5, -8, 3, 8, C.Gold, { Radius = 1, Z = 1, Outline = false })
	kit.Blob(dancer, 0, -13, 24, 9, C.LilacSoft, { Z = 2, Thickness = 1.2 }) -- tutu
	kit.Part(dancer, -4, -26, 8, 13, C.Lilac, { Radius = 4, Z = 3 })
	kit.Line(dancer, -3, -24, -12, -33, 2.4, C.Peach, 0, 3)
	kit.Line(dancer, 3, -24, 12, -33, 2.4, C.Peach, 0, 3)
	kit.Blob(dancer, 0, -32, 11, 11, C.Peach, { Z = 4, Thickness = 1.2 })
	kit.Blob(dancer, 0, -38, 8, 5, C.Brown, { Z = 5, Thickness = 1 })
	kit.Animate(dancer, "Sway", 6, 1.3, 0)
	-- notes
	for index, x in ipairs({ 6, 92 }) do
		local note = kit.Text(body, index == 1 and "🎵" or "🎶", x, 34, 14, C.PinkDeep, 5)
		kit.Animate(note, "Bob", 3, 0.8, index * 1.3)
	end
	return nil
end

-- Mini aquarium rond : poisson, algue, bulles
Art.MiniAquarium = function(body, kit, _item)
	local C = kit.C
	local stand = kit.Part(body, 20, 84, 60, 14, C.WoodLight, { Radius = 5, Z = 1, Shine = true })
	kit.Box(stand, 6, 6, 48, 2, C.WoodDark, 0.3, 2)
	local bowl = kit.Circle(body, 50, 50, 86, 76, C.Glass, 0.3, 2)
	kit.Stroke(bowl, kit.Darken(C.Glass, 0.35), 2)
	-- eau (ovale dans le bas du bocal) + sable
	kit.Blob(bowl, 43, 44, 78, 52, Color3.fromRGB(150, 210, 250), { Z = 1, Outline = false, Shade = false, T = 0.15 })
	kit.Blob(bowl, 43, 64, 56, 12, C.Butter, { Z = 2, Outline = false, Shade = false })
	for _, x in ipairs({ 24, 31 }) do
		local weed = kit.Pivot(bowl, x, 64, 3)
		kit.Blob(weed, 0, -12, 7, 26, C.Leaf, { Thickness = 1.1 })
		kit.Animate(weed, "Sway", 8, 0.7, x)
	end
	local fish = kit.Group(bowl, 44, 34, 30, 18, 4)
	kit.Blob(fish, 12, 9, 22, 16, C.Orange, { Z = 2, Shine = true })
	kit.Part(fish, 20, 3, 10, 12, kit.Darken(C.Orange, 0.1), { Radius = 3, Z = 1, Rotation = 45 })
	kit.Circle(fish, 7, 7, 3, 3, C.Ink, 0, 3)
	kit.Animate(fish, "Drift", 6, 0.6, 0)
	for index = 1, 3 do
		local bubble = kit.Circle(bowl, 34 + index * 6, 30 - index * 5, 4 + index, 4 + index, C.White, 0.4, 5)
		kit.Animate(bubble, "Bob", 2, 1.1, index)
	end
	kit.Shine(bowl, 14, 10, 10, 22, 6, 0.3)
	return nil
end

-- Coffret à bijoux royal : couvercle bombé, perles, diamants
Art.JewelryBox = function(body, kit, _item)
	local C = kit.C
	local velvet = Color3.fromRGB(180, 120, 220)
	for _, x in ipairs({ 18, 82 }) do
		kit.Blob(body, x, 94, 12, 10, C.Gold, { Z = 1, Shine = true })
	end
	local box = kit.Part(body, 8, 54, 84, 40, velvet, { Radius = 8, Z = 2, Shine = true })
	kit.Box(box, 0, 3, 84, 4, C.Gold, 0, 2)
	kit.Box(box, 0, 32, 84, 4, C.Gold, 0, 2)
	local lock = kit.Part(box, 36, 12, 12, 14, C.Gold, { Radius = 3, Z = 3 })
	kit.Circle(lock, 6, 6, 4, 4, kit.Darken(C.Gold, 0.45), 0, 2)
	-- collier de perles qui dépasse
	for index = 0, 6 do
		kit.Circle(body, 22 + index * 9, 52 + math.abs(index - 3) * -2, 7, 7, C.White, 0, 4)
	end
	-- couvercle bombé
	local lid = kit.Part(body, 6, 28, 88, 26, kit.Lighten(velvet, 0.12), { Radius = 12, Z = 3, Shine = true })
	kit.Box(lid, 0, 20, 88, 3, C.Gold, 0, 2)
	-- couronne + diamant
	local crown = kit.Part(body, 36, 10, 28, 18, C.Gold, { Radius = 3, Z = 4, Shine = true })
	for _, x in ipairs({ 4, 14, 24 }) do
		kit.Diamond(crown, x, 0, 8, C.Gold, 0, 1)
	end
	kit.Diamond(crown, 14, 10, 8, C.Sky, 0, 3)
	local sparkle = kit.Sparkle(body, 82, 18, 16, C.White, 0, 5)
	kit.Animate(sparkle, "Breathe", 0.15, 1.6, 0)
	return { Glow = Color3.fromRGB(255, 230, 160) }
end

----------------------------------------------------------------------
-- 🍰 Cuisine
----------------------------------------------------------------------

-- Coupe de fruits : pommes, banane, raisin
Art.FruitBowl = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 44, 18, 14, C.Lilac, { Z = 1 }) -- raisin (derrière)
	for index, g in ipairs({ { 36, 40 }, { 44, 36 }, { 40, 46 } }) do
		kit.Circle(body, g[1], g[2], 11, 11, index == 2 and C.Purple or C.Lilac, 0, 2)
	end
	local banana = kit.Part(body, 50, 34, 38, 12, C.Yellow, { Radius = -1, Z = 2, Rotation = -18, Shine = true })
	kit.Box(banana, 34, 3, 4, 5, C.Brown, 0, 2)
	kit.Blob(body, 30, 56, 26, 24, C.Red, { Z = 3, Shine = true })
	kit.Blob(body, 68, 56, 26, 24, C.Leaf, { Z = 3, Shine = true })
	for _, x in ipairs({ 30, 68 }) do
		kit.Line(body, x, 45, x + 2, 40, 2.2, C.Brown, 0, 4)
	end
	local bowl = kit.Part(body, 6, 58, 88, 30, C.Sky, { Radius = -1, Z = 4, Shine = true })
	kit.Box(bowl, 10, 3, 68, 3, C.White, 0.4, 2)
	kit.Part(body, 30, 86, 40, 12, kit.Darken(C.Sky, 0.1), { Radius = 5, Z = 3 })
	kit.Heart(bowl, 44, 16, 10, C.White, 0, 3)
	return nil
end

-- Assiette de pizza : parts garnies, une part soulevée (fil de fromage)
Art.PizzaPlate = function(body, kit, _item)
	local C = kit.C
	plate(kit, body, 50, 84, 96, C.White, 1)
	local pizza = kit.Blob(body, 46, 74, 76, 28, C.Orange, { Z = 3 })
	kit.Blob(pizza, 38, 12, 64, 18, C.Butter, { Z = 2, Outline = false, Shade = false })
	for _, p in ipairs({ { 18, 11 }, { 38, 7 }, { 54, 13 }, { 30, 18 } }) do
		kit.Circle(pizza, p[1], p[2], 8, 6, C.Red, 0, 3)
	end
	kit.Circle(pizza, 46, 19, 5, 4, C.Leaf, 0, 3)
	-- part triangulaire soulevée (pointe en bas)
	local slice = kit.Pivot(body, 78, 56, 4)
	slice.Rotation = 16
	kit.TriangleDown(slice, 0, -18, 26, 34, C.Butter, 1)
	kit.Part(slice, -14, -22, 28, 7, kit.Darken(C.Orange, 0.05), { Radius = 3, Z = 2 }) -- croûte
	kit.Circle(slice, -3, -8, 7, 6, C.Red, 0, 2)
	kit.Circle(slice, 4, 2, 5, 4, C.Red, 0, 2)
	kit.Line(body, 70, 74, 74, 86, 2, C.Butter, 0, 5) -- fil de fromage
	return nil
end

-- Carafe de citronnade + verre avec paille
Art.Lemonade = function(body, kit, _item)
	local C = kit.C
	local jug = kit.Part(body, 8, 24, 52, 74, C.Glass, { Radius = 14, Z = 1, T = 0.2 })
	kit.Part(jug, 4, 20, 44, 50, C.Yellow, { Radius = 12, Z = 1, Outline = false, Shade = false, T = 0.1 })
	kit.Circle(jug, 18, 36, 12, 12, kit.Lighten(C.Yellow, 0.4), 0, 2) -- rondelle
	kit.Circle(jug, 32, 50, 10, 10, kit.Lighten(C.Yellow, 0.4), 0, 2)
	local handle = kit.Circle(body, 60, 52, 20, 30, C.White, 1, 0)
	kit.Stroke(handle, kit.Darken(C.Glass, 0.3), 3)
	kit.Part(body, 6, 20, 56, 8, C.White, { Radius = 4, Z = 2 })
	kit.Shine(jug, 6, 8, 6, 30, 3, 0.3)
	-- verre
	local glass = kit.Part(body, 66, 54, 26, 44, C.Glass, { Radius = 6, Z = 3, T = 0.2 })
	kit.Part(glass, 2, 12, 22, 30, C.Yellow, { Radius = 5, Z = 1, Outline = false, Shade = false, T = 0.1 })
	kit.Line(body, 82, 58, 88, 36, 3, C.Pink, 0, 4)
	kit.Blob(body, 72, 54, 14, 10, kit.Lighten(C.Yellow, 0.2), { Z = 4, Thickness = 1.1 })
	return nil
end

-- Service à thé : théière fleurie + 2 tasses sur un plateau
Art.TeaSet = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 2, 88, 96, 10, C.WoodLight, { Radius = 5, Z = 1, Shine = true }) -- plateau
	-- théière
	local spout = kit.Line(body, 62, 62, 76, 48, 6, C.White, 0, 2)
	kit.Stroke(spout, kit.OutlineOf(C.White), 1.3)
	local handle = kit.Circle(body, 28, 62, 16, 22, C.White, 1, 2)
	kit.Stroke(handle, kit.OutlineOf(C.White), 3)
	local pot = kit.Blob(body, 48, 64, 40, 36, C.White, { Z = 3, Shine = true })
	kit.Circle(pot, 12, 20, 8, 8, C.Pink, 0, 2)
	kit.Circle(pot, 26, 14, 7, 7, C.Mint, 0, 2)
	kit.Blob(body, 48, 46, 22, 8, C.PinkSoft, { Z = 4 })
	kit.Blob(body, 48, 41, 7, 6, C.Pink, { Z = 5 })
	-- tasses
	for _, x in ipairs({ 16, 84 }) do
		local cup = kit.Part(body, x - 10, 74, 20, 14, C.PinkSoft, { Radius = 6, Z = 4, Shine = true })
		kit.Heart(cup, 10, 7, 6, C.Pink, 0, 2)
		kit.Blob(body, x, 88, 26, 6, C.White, { Z = 3, Thickness = 1.1 })
	end
	local steam = kit.Line(body, 76, 42, 80, 32, 2, C.White, 0.4, 3)
	kit.Animate(steam, "Drift", 2, 1, 0)
	return nil
end

-- Saladier : feuilles, tomates, œuf
Art.SaladBowl = function(body, kit, _item)
	local C = kit.C
	for index, leaf in ipairs({ { 30, 48, -30 }, { 50, 42, 0 }, { 70, 48, 30 }, { 40, 52, -12 }, { 60, 52, 14 } }) do
		kit.Blob(body, leaf[1], leaf[2], 26, 18, index % 2 == 0 and C.Leaf or C.Green, { Z = 1, Rotation = leaf[3] })
	end
	kit.Circle(body, 36, 50, 12, 12, C.Red, 0, 2)
	kit.Circle(body, 62, 48, 11, 11, C.Red, 0, 2)
	local egg = kit.Blob(body, 50, 52, 16, 12, C.White, { Z = 2 })
	kit.Circle(egg, 8, 6, 7, 7, C.Yellow, 0, 2)
	local bowl = kit.Part(body, 4, 56, 92, 34, C.White, { Radius = -1, Z = 3, Shine = true })
	kit.Box(bowl, 8, 12, 76, 4, C.Mint, 0.2, 2)
	kit.Part(body, 28, 86, 44, 12, kit.Darken(C.White, 0.08), { Radius = 5, Z = 2 })
	return nil
end

-- Grille-pain qui sourit, 2 tartines qui sautent
Art.Toaster = function(body, kit, _item)
	local C = kit.C
	for index, x in ipairs({ 34, 56 }) do
		local toast = kit.Part(body, x - 10, 18, 20, 24, C.WoodLight, { Radius = 7, Z = 1 })
		kit.Part(toast, 3, 3, 14, 18, kit.Lighten(C.WoodLight, 0.4), { Radius = 5, Z = 2, Outline = false, Shade = false })
		kit.Animate(toast, "Bob", 3, 1.4, index * 1.1)
	end
	local toaster = kit.Part(body, 10, 36, 80, 58, C.Mint, { Radius = 16, Z = 2, Shine = true })
	kit.Box(toaster, 18, 2, 18, 3, kit.Darken(C.Mint, 0.4), 0, 2)
	kit.Box(toaster, 40, 2, 18, 3, kit.Darken(C.Mint, 0.4), 0, 2)
	kit.Face(toaster, 38, 32, 30, { Eyes = "happy", Mouth = "smile", Z = 3 })
	kit.Part(body, 84, 50, 8, 14, C.Grey, { Radius = 3, Z = 3 }) -- levier
	kit.Part(body, 18, 92, 64, 6, kit.Darken(C.Mint, 0.3), { Radius = 3, Z = 1 })
	return nil
end

-- Tour de macarons pastel
Art.MacaronTower = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 95, 70, 8, C.Gold, { Z = 1 }) -- présentoir
	kit.Part(body, 46, 84, 8, 10, C.Gold, { Radius = 3, Z = 1 })
	local colors = { C.PinkSoft, C.MintSoft, C.LilacSoft, kit.Lighten(C.Butter, 0.3), C.Pink }
	local rows = { { 5, 82 }, { 4, 66 }, { 3, 50 }, { 2, 34 }, { 1, 18 } }
	for r, row in ipairs(rows) do
		local count, y = row[1], row[2]
		for index = 1, count do
			local x = 50 + (index - (count + 1) / 2) * 17
			local color = colors[(r + index) % #colors + 1]
			local mac = kit.Part(body, x - 8, y - 6, 16, 12, color, { Radius = -1, Z = 2 + r, Thickness = 1.2 })
			kit.Box(mac, 1, 5, 14, 2, C.Cream, 0, 2)
		end
	end
	kit.Heart(body, 50, 8, 12, C.PinkDeep, 0, 9)
	return nil
end

-- Micro-ondes mignon : hublot, pop-corn qui éclate
Art.Microwave = function(body, kit, _item)
	local C = kit.C
	local oven = kit.Part(body, 4, 30, 92, 64, C.PinkSoft, { Radius = 12, Z = 1, Shine = true })
	local door = kit.Part(oven, 6, 8, 58, 48, C.Glass, { Radius = 8, Z = 2, Thickness = 1.3 })
	local inside = kit.Part(door, 5, 5, 48, 38, Color3.fromRGB(255, 236, 170), { Radius = 5, Z = 2, Outline = false, Shade = false, T = 0.1 })
	local bag = kit.Part(inside, 16, 10, 16, 24, C.White, { Radius = 3, Z = 2, Thickness = 1.1 })
	kit.Box(bag, 3, 6, 10, 3, C.Red, 0, 2)
	for index, p in ipairs({ { 12, 9 }, { 34, 7 }, { 26, 4 } }) do
		local corn = kit.Circle(inside, p[1], p[2], 7, 6, C.White, 0, 3)
		kit.Animate(corn, "Bob", 2, 1.6, index)
	end
	kit.Face(oven, 78, 18, 18, { Eyes = "dot", Mouth = "cat", Z = 3 })
	for index = 0, 2 do
		kit.Circle(oven, 78, 34 + index * 7, 5, 5, index == 0 and C.Pink or C.White, 0, 3)
	end
	for _, x in ipairs({ 16, 80 }) do
		kit.Part(body, x, 92, 8, 6, C.GreyDark, { Radius = 2, Z = 0 })
	end
	return nil
end

----------------------------------------------------------------------
-- 🪴 Plantes
----------------------------------------------------------------------

-- Vase rond et bouquet de tulipes / marguerites
Art.FlowerVase = function(body, kit, _item)
	local C = kit.C
	for index, stem in ipairs({ { 34, 16, -14 }, { 50, 8, 0 }, { 66, 16, 14 }, { 42, 24, -6 }, { 58, 24, 8 } }) do
		kit.Line(body, 50, 60, stem[1], stem[2] + 8, 3, C.LeafDark, 0, 1)
		local color = ({ C.Pink, C.Butter, C.Lilac, C.PinkDeep, C.White })[index]
		local flower = kit.Pivot(body, stem[1], stem[2] + 4, 2)
		if index % 2 == 1 then
			kit.Part(flower, -7, -8, 14, 14, color, { Radius = 5, Z = 1 }) -- tulipe
			kit.Triangle(flower, -3, -12, 5, 6, color, 2)
			kit.Triangle(flower, 3, -12, 5, 6, color, 2)
		else
			for petal = 0, 4 do
				local a = petal * math.pi * 2 / 5
				kit.Circle(flower, math.cos(a) * 5, math.sin(a) * 5 - 2, 7, 7, color, 0, 1)
			end
			kit.Circle(flower, 0, -2, 5, 5, C.Yellow, 0, 2)
		end
		kit.Animate(flower, "Sway", 3, 0.6, index)
	end
	kit.Blob(body, 32, 50, 16, 8, C.Leaf, { Z = 2, Rotation = -30 })
	kit.Blob(body, 68, 50, 16, 8, C.Leaf, { Z = 2, Rotation = 30 })
	local vase = kit.Blob(body, 50, 78, 50, 44, C.Sky, { Z = 3, Shine = true })
	kit.Part(body, 38, 52, 24, 10, kit.Darken(C.Sky, 0.08), { Radius = 4, Z = 4 })
	kit.Heart(vase, 25, 24, 12, C.White, 0, 3)
	return nil
end

-- Petit bonsaï dans un pot bas
Art.Bonsai = function(body, kit, _item)
	local C = kit.C
	local trunk = C.Brown
	kit.Line(body, 50, 84, 44, 60, 8, trunk, 0, 1)
	kit.Line(body, 44, 60, 56, 40, 7, trunk, 0, 1)
	kit.Line(body, 50, 52, 30, 44, 5, trunk, 0, 1)
	kit.Line(body, 54, 44, 72, 34, 5, trunk, 0, 1)
	for index, puff in ipairs({ { 28, 38, 30 }, { 54, 26, 36 }, { 76, 30, 28 }, { 42, 30, 24 } }) do
		local cloud = kit.Blob(body, puff[1], puff[2], puff[3], puff[3] * 0.7, index % 2 == 0 and C.LeafDark or C.Leaf, { Z = 2, Shine = true })
		kit.Animate(cloud, "Breathe", 0.03, 0.5, index)
	end
	kit.Circle(body, 60, 24, 6, 6, C.Pink, 0, 3) -- fleur
	local pot = kit.Part(body, 12, 80, 76, 18, C.Peach, { Radius = 5, Z = 3, Shine = true })
	kit.Box(pot, 0, 0, 76, 5, kit.Darken(C.Peach, 0.12), 0, 2)
	kit.Blob(body, 50, 81, 60, 6, C.Brown, { Z = 2, Outline = false, Shade = false })
	return nil
end

----------------------------------------------------------------------
-- 💡 Lumières
----------------------------------------------------------------------

-- Lampe de bureau articulée (abat-jour menthe qui éclaire)
Art.DeskLamp = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 34, 95, 44, 10, C.Mint, { Z = 1, Shine = true })
	kit.Line(body, 34, 92, 26, 54, 5, C.GreyDark, 0, 2)
	kit.Line(body, 26, 54, 52, 26, 5, C.GreyDark, 0, 2)
	kit.Circle(body, 26, 54, 9, 9, C.Mint, 0, 3)
	local shade = kit.Pivot(body, 56, 24, 4)
	shade.Rotation = 30
	kit.Part(shade, -18, -10, 36, 22, C.Mint, { Radius = 9, Z = 2, Shine = true })
	kit.Blob(shade, 0, 12, 18, 8, C.Butter, { Z = 3, Outline = false })
	local beam = kit.Triangle(body, 72, 36, 40, 50, C.Butter, 1, 0.75)
	beam.Rotation = -30
	return { Glow = Color3.fromRGB(255, 240, 180) }
end

-- Lampe champignon qui brille (pois lumineux)
Art.MushroomLamp = function(body, kit, _item)
	local C = kit.C
	local stem = kit.Part(body, 36, 50, 28, 46, C.Cream, { Radius = 12, Z = 1 })
	kit.Face(stem, 14, 20, 18, { Eyes = "closed", Mouth = "cat", Z = 3 })
	kit.Blob(body, 50, 96, 50, 8, C.Leaf, { Z = 0 })
	local cap = kit.Part(body, 6, 8, 88, 50, C.Lilac, { Radius = -1, Z = 2, Shine = true })
	local dots = {}
	for index, d in ipairs({ { 18, 18, 11 }, { 44, 10, 14 }, { 70, 18, 11 }, { 30, 32, 8 }, { 58, 32, 8 } }) do
		local dot = kit.Circle(cap, d[1], d[2], d[3], d[3], C.Butter, 0, 2)
		kit.Animate(dot, "Pulse", 0.35, 1, index)
		table.insert(dots, dot)
	end
	kit.Part(body, 14, 50, 72, 8, kit.Darken(C.Lilac, 0.25), { Radius = -1, Z = 1, Outline = false })
	return { Glow = Color3.fromRGB(230, 200, 255) }
end

-- Chandelier de cristal : 3 bougies, pampilles
Art.Candelabra = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 94, 48, 10, C.Gold, { Z = 1, Shine = true })
	kit.Part(body, 46, 52, 8, 42, C.Gold, { Radius = 4, Z = 2 })
	kit.Blob(body, 50, 74, 16, 10, C.Gold, { Z = 3, Shine = true })
	-- bras recourbés (segments dorés)
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(body, 50, 64, 50 + side * 18, 66, 4, C.Gold, 0, 2)
		kit.Line(body, 50 + side * 18, 66, 50 + side * 28, 58, 4, C.Gold, 0, 2)
	end
	for index, x in ipairs({ 22, 50, 78 }) do
		local top = index == 2 and 18 or 30
		kit.Blob(body, x, top + 26, 18, 6, C.Gold, { Z = 3 })
		kit.Part(body, x - 5, top, 10, 26, C.Cream, { Radius = 3, Z = 4, Shine = true })
		flame(kit, body, x, top + 1, 9, 14, 5, index)
		-- pampille de cristal
		local drop = kit.Diamond(body, x, top + 34, 6, C.Glass, 0.1, 5)
		kit.Stroke(drop, C.Sky, 1)
		kit.Animate(drop, "Sway", 8, 1, index)
	end
	return { Glow = Color3.fromRGB(255, 210, 140) }
end

----------------------------------------------------------------------
-- 📺 Électronique
----------------------------------------------------------------------

-- Réveil à deux cloches qui sourit
Art.AlarmClock = function(body, kit, _item)
	local C = kit.C
	for _, x in ipairs({ 26, 74 }) do
		kit.Blob(body, x, 20, 26, 18, C.Gold, { Z = 1, Shine = true })
	end
	kit.Line(body, 30, 12, 70, 12, 3, C.GreyDark, 0, 1)
	for _, x in ipairs({ 22, 78 }) do
		kit.Line(body, 50 + (x - 50) * 0.6, 84, x, 97, 5, C.GreyDark, 0, 1)
	end
	local clock = kit.Circle(body, 50, 56, 76, 76, C.Red, 0, 2)
	kit.Stroke(clock, kit.OutlineOf(C.Red), 1.6)
	local face = kit.Circle(clock, 38, 38, 58, 58, C.White, 0, 2)
	for index = 0, 3 do
		local a = index * math.pi / 2
		kit.Circle(face, 29 + math.cos(a) * 22, 29 + math.sin(a) * 22, 4, 4, C.Ink, 0, 2)
	end
	local hand = kit.Pivot(face, 29, 29, 3)
	kit.Part(hand, -1.5, -20, 3, 20, C.Ink, { Radius = 1, Outline = false, Shade = false })
	kit.Animate(hand, "Spin", 1, 0.08, 0)
	kit.Part(face, 27.5, 18, 3, 12, C.PinkDeep, { Radius = 1, Z = 3, Outline = false, Shade = false })
	kit.Circle(face, 29, 29, 5, 5, C.PinkDeep, 0, 4)
	return nil
end

-- Machine à écrire rétro avec une feuille
Art.Typewriter = function(body, kit, _item)
	local C = kit.C
	local paper = kit.Part(body, 28, 6, 44, 40, C.White, { Radius = 2, Z = 1, Thickness = 1.2 })
	for index = 0, 3 do
		kit.Box(paper, 5, 8 + index * 6, 34 - index * 5, 1.6, C.Grey, 0, 2)
	end
	kit.Heart(paper, 34, 32, 7, C.Pink, 0, 2)
	kit.Part(body, 14, 38, 72, 10, C.GreyDark, { Radius = 5, Z = 2 }) -- rouleau
	for _, x in ipairs({ 10, 90 }) do
		kit.Blob(body, x, 43, 10, 12, C.Grey, { Z = 3 })
	end
	local machine = kit.Part(body, 6, 46, 88, 50, C.Mint, { Radius = 10, Z = 3, Shine = true })
	for row = 0, 2 do
		for col = 0, 6 - row do
			kit.Circle(machine, 14 + col * 10 + row * 5, 12 + row * 10, 7, 7, C.Cream, 0, 2)
		end
	end
	kit.Part(machine, 26, 40, 36, 6, C.Cream, { Radius = 3, Z = 2 }) -- barre d'espace
	return nil
end

-- Ventilateur de bureau (pales qui tournent)
Art.DeskFan = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 94, 50, 12, C.Sky, { Z = 1, Shine = true })
	kit.Part(body, 45, 56, 10, 38, C.Sky, { Radius = 5, Z = 2 })
	local cage = kit.Circle(body, 50, 38, 74, 74, C.White, 0.55, 3)
	kit.Stroke(cage, kit.Darken(C.Sky, 0.25), 3)
	local blades = kit.Pivot(body, 50, 38, 4)
	for index = 0, 2 do
		local blade = kit.Pivot(blades, 0, 0, 1)
		blade.Rotation = index * 120
		kit.Blob(blade, 0, -15, 16, 28, index == 0 and C.Pink or C.PinkSoft, { Thickness = 1.3 })
	end
	kit.Animate(blades, "Spin", 1, 1.2, 0)
	kit.Circle(body, 50, 38, 12, 12, C.Butter, 0, 5)
	for index = 0, 2 do
		local wind = kit.Line(body, 84, 28 + index * 10, 96, 28 + index * 10, 2, C.Sky, 0.3, 2)
		kit.Animate(wind, "Drift", 3, 1.5, index)
	end
	return nil
end

-- Tablette à dessin + stylet (un petit dessin de chat sur l'écran)
Art.DrawingTablet = function(body, kit, _item)
	local C = kit.C
	local stand = kit.Line(body, 70, 50, 84, 98, 5, C.GreyDark, 0, 1)
	stand.Name = "Stand"
	local tablet = kit.Part(body, 6, 28, 76, 70, C.Ink, { Radius = 10, Z = 2, Shine = true })
	local screen = kit.Part(tablet, 6, 6, 64, 58, Color3.fromRGB(255, 244, 250), { Radius = 5, Z = 2, Outline = false, Shade = false })
	local cat = kit.Circle(screen, 30, 32, 26, 22, C.White, 1, 2)
	kit.Stroke(cat, C.PinkDeep, 2)
	kit.Line(screen, 20, 21, 22, 14, 2, C.PinkDeep, 0, 3)
	kit.Line(screen, 38, 21, 36, 14, 2, C.PinkDeep, 0, 3)
	kit.Circle(screen, 25, 31, 3, 3, C.PinkDeep, 0, 3)
	kit.Circle(screen, 35, 31, 3, 3, C.PinkDeep, 0, 3)
	for index, color in ipairs({ C.Red, C.Butter, C.Mint, C.Sky }) do
		kit.Circle(screen, 8 + index * 9, 52, 6, 6, color, 0, 3)
	end
	local pen = kit.Pivot(body, 84, 30, 4)
	pen.Rotation = 30
	kit.Part(pen, -3, -2, 6, 36, C.Lilac, { Radius = 3 })
	kit.Part(pen, -1.5, 32, 3, 6, C.GreyDark, { Radius = 1 })
	return nil
end

----------------------------------------------------------------------
-- 🧸 Jouets
----------------------------------------------------------------------

-- Jeu de société : plateau, dés, pions
Art.BoardGame = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 4, 72, 92, 26, C.Red, { Radius = 5, Z = 1 }) -- boîte
	local board = kit.Part(body, 2, 64, 96, 16, C.Cream, { Radius = 4, Z = 2, Shine = true })
	for col = 0, 7 do
		kit.Box(board, 6 + col * 11, 3, 10, 10, col % 2 == 0 and C.Pink or C.Mint, 0.1, 2)
	end
	-- pions
	for index, p in ipairs({ { 24, C.Sky }, { 50, C.Butter }, { 76, C.Lilac } }) do
		local pawn = kit.Pivot(body, p[1], 66, 3)
		kit.Part(pawn, -7, -16, 14, 16, p[2], { Radius = 6, Z = 1 })
		kit.Blob(pawn, 0, -20, 12, 12, p[2], { Z = 2, Shine = true })
		kit.Animate(pawn, "Bob", 1.5, 1, index)
	end
	-- dé
	local die = kit.Part(body, 60, 34, 22, 22, C.White, { Radius = 5, Z = 4, Rotation = 12, Shine = true })
	for _, dot in ipairs({ { 6, 6 }, { 16, 16 }, { 11, 11 } }) do
		kit.Circle(die, dot[1], dot[2], 4, 4, C.Ink, 0, 2)
	end
	return nil
end

-- Peluche baleine bleue (petit jet d'eau)
Art.WhalePlush = function(body, kit, _item)
	local C = kit.C
	local blue = Color3.fromRGB(150, 196, 250)
	local tail = kit.Pivot(body, 86, 64, 1)
	kit.Blob(tail, 4, -12, 22, 14, blue, { Rotation = -30 })
	kit.Animate(tail, "Sway", 8, 0.8, 0)
	local whale = kit.Blob(body, 46, 70, 84, 56, blue, { Z = 2, Shine = true })
	kit.Blob(whale, 38, 44, 60, 20, kit.Lighten(blue, 0.55), { Z = 1, Outline = false, Shade = false })
	kit.Face(whale, 28, 22, 28, { Eyes = "big", Mouth = "smile", Z = 3 })
	kit.Blob(body, 66, 84, 18, 10, kit.Darken(blue, 0.08), { Z = 3, Rotation = 20 }) -- nageoire
	for index, x in ipairs({ 40, 46, 52 }) do
		local drop = kit.Circle(body, x, 26 - index % 2 * 6, 7, 9, C.Sky, 0, 3)
		kit.Animate(drop, "Bob", 3, 1.4, index)
	end
	kit.Line(body, 46, 42, 46, 32, 3, C.Sky, 0, 3)
	return nil
end

-- Peluche pieuvre rose aux tentacules qui ondulent
Art.OctopusPlush = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 160, 196)
	for index = 0, 5 do
		local x = 18 + index * 12.8
		local leg = kit.Pivot(body, x, 70, 1)
		kit.Part(leg, -6, 0, 12, 28, pink, { Radius = 6, Thickness = 1.3 })
		kit.Circle(leg, 0, 20, 4, 4, kit.Lighten(pink, 0.5), 0, 2)
		kit.Animate(leg, "Sway", 6, 1.1, index * 0.9)
	end
	local head = kit.Blob(body, 50, 46, 76, 62, pink, { Z = 2, Shine = true })
	kit.Face(head, 38, 36, 34, { Eyes = "happy", Mouth = "o", Z = 3 })
	kit.Circle(head, 20, 16, 7, 7, kit.Lighten(pink, 0.4), 0, 2)
	kit.Circle(head, 56, 12, 5, 5, kit.Lighten(pink, 0.4), 0, 2)
	-- petit chapeau
	local hat = kit.Part(body, 36, 8, 28, 12, C.Butter, { Radius = 4, Z = 3, Rotation = -8 })
	kit.Heart(hat, 14, 6, 6, C.PinkDeep, 0, 2)
	return nil
end

return Art
