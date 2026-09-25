--[[
	Pets (ModuleScript) — dessins des animaux 🐾 (ils respirent, clignent des yeux, remuent la queue)
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Pets
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

local HALF_PI = math.pi / 2 -- décalage de phase pour un balancement "en miroir"

----------------------------------------------------------------------
-- Aides communes
----------------------------------------------------------------------

-- Conteneur qui respire : UIScale autour du bas-centre (les pattes restent au sol)
-- les enfants se placent par rapport au coin (x, y)
local function breather(parent, kit, x, y, w, h, z)
	local g = kit.Group(parent, x, y, w, h, z)
	g.AnchorPoint = Vector2.new(0.5, 1)
	g.Position = UDim2.fromOffset(x + w / 2, y + h)
	return g
end

-- Oreille pointue : carré arrondi tourné à 45° (la pointe dépasse de la tête), intérieur rose
local function ear(parent, kit, cx, cy, size, color, inner, tilt, z)
	local frame = kit.Part(parent, cx - size / 2, cy - size / 2, size, size, color, {
		Radius = size * 0.24,
		Rotation = 45 + tilt,
		Z = z,
		Shade = false,
	})
	if inner then
		kit.Part(frame, size * 0.2, size * 0.2, size * 0.46, size * 0.46, inner, {
			Radius = size * 0.14,
			Z = 2,
			Outline = false,
			Shade = false,
		})
	end
	return frame
end

-- Petit museau : truffe + bouche en ω
local function snout(parent, kit, x, y, size, z)
	local C = kit.C
	kit.Blob(parent, x, y, size * 0.5, size * 0.34, C.Ink, { Z = z, Outline = false, Shade = false })
	local t = math.max(1, size * 0.1)
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(parent, x, y + size * 0.1, x + side * size * 0.2, y + size * 0.38, t, C.Ink, 0, z)
		kit.Line(parent, x + side * size * 0.2, y + size * 0.38, x + side * size * 0.4, y + size * 0.22, t, C.Ink, 0, z)
	end
end

----------------------------------------------------------------------
-- Dessins
----------------------------------------------------------------------

-- Poussin : boule jaune qui sort de sa coquille, toupet et petites ailes qui battent
Art.Chick = function(body, kit, _item)
	local C = kit.C
	local yellow = Color3.fromRGB(255, 222, 110)
	local wingColor = Color3.fromRGB(255, 205, 90)
	local chick = breather(body, kit, 0, 0, 100, 92, 3)
	local tuft = kit.Pivot(chick, 50, 36, 1)
	kit.Blob(tuft, -3, -5, 6, 13, yellow, { Rotation = -28, Thickness = 1.4 })
	kit.Blob(tuft, 3, -6, 6, 14, yellow, { Rotation = 18, Thickness = 1.4 })
	kit.Animate(tuft, "Sway", 8, 1.1, 0.4)
	for index, side in ipairs({ -1, 1 }) do
		local wing = kit.Pivot(chick, 50 + side * 22, 58, 1)
		kit.Blob(wing, side * 5, 3, 13, 18, wingColor, { Rotation = side * -35, Thickness = 1.4 })
		kit.Animate(wing, "Sway", 14, 1.6, (index - 1) * HALF_PI)
	end
	kit.Blob(chick, 50, 62, 54, 50, yellow, { Z = 2, Shine = true })
	kit.Face(chick, 50, 58, 30, { Mouth = "none", Z = 4 })
	kit.Diamond(chick, 50, 63.5, 6.5, C.Orange, 0, 5)
	kit.Animate(chick, "Breathe", 0.03, 1, 0.2)
	-- coquille
	local shell = kit.Group(body, 14, 74, 72, 26, 5, true)
	kit.Blob(shell, 36, 0, 68, 52, C.Cream, { Z = 1, Thickness = 1.8, Shade = 0.2 })
	local shellLine = kit.OutlineOf(C.Cream)
	for k = 0, 5 do
		local d = kit.Diamond(body, 22 + k * 11.2, 75.5, 8, C.Cream, 0, 6)
		kit.Stroke(d, shellLine, 1.4)
	end
	kit.Box(body, 18, 75.5, 64, 6, C.Cream, 0, 7)
	return nil
end

-- Poisson rouge dans son bocal rond : il nage, les bulles montent, l'algue ondule
Art.Goldfish = function(body, kit, _item)
	local C = kit.C
	local glassLine = Color3.fromRGB(130, 175, 215)
	-- eau (bas du bocal)
	local water = kit.Group(body, 8, 34, 84, 66, 2, true)
	kit.Blob(water, 42, 26, 84, 76, C.Sky, { Z = 1, T = 0.45, Outline = false, Shade = 0.25 })
	kit.Part(body, 21, 32, 58, 5, kit.Lighten(C.Sky, 0.5), { Radius = -1, Z = 3, T = 0.15, Outline = false, Shade = false })
	for _, p in ipairs({ { 38, 90, C.Pink }, { 47, 93, C.Butter }, { 57, 92, C.Mint }, { 65, 89, C.Lilac } }) do
		kit.Blob(body, p[1], p[2], 9, 6, p[3], { Z = 3, Thickness = 1.1, Shade = false })
	end
	local weed = kit.Pivot(body, 30, 90, 3)
	kit.Blob(weed, -1, -12, 6, 24, C.Green, { Rotation = -8, Thickness = 1.2, Shade = false })
	kit.Blob(weed, 5, -9, 5, 18, C.Leaf, { Rotation = 12, Thickness = 1.2, Shade = false })
	kit.Animate(weed, "Sway", 7, 0.8, 1.2)
	-- poisson
	local fish = kit.Group(body, 34, 46, 38, 28, 5)
	local orange, fin = Color3.fromRGB(255, 150, 80), Color3.fromRGB(255, 190, 130)
	local tail = kit.Pivot(fish, 8, 14, 1)
	kit.Blob(tail, -5, -5, 13, 10, fin, { Rotation = -35, Thickness = 1.3 })
	kit.Blob(tail, -5, 5, 13, 10, fin, { Rotation = 35, Thickness = 1.3 })
	kit.Animate(tail, "Sway", 12, 2.2, 0)
	kit.Blob(fish, 19, 3, 11, 8, fin, { Z = 1, Rotation = -20, Thickness = 1.3 })
	kit.Blob(fish, 21, 14, 28, 21, orange, { Z = 2, Shine = true })
	kit.Blob(fish, 18, 19, 7, 5, fin, { Z = 3, Rotation = 30, Thickness = 1.1, Shade = false })
	kit.Face(fish, 25, 13, 14, { Mouth = "o", Spacing = 0.7, Z = 4 })
	kit.Animate(fish, "Drift", 7, 0.35, 0)
	for index, b in ipairs({ { 70, 44, 5 }, { 74, 36, 3.5 }, { 66, 60, 4 } }) do
		local bubble = kit.Circle(body, b[1], b[2], b[3], b[3], C.White, 0.5, 6)
		kit.Stroke(bubble, C.White, 1, 0.1)
		kit.Animate(bubble, "Bob", 2, 0.8, index * 1.9)
	end
	-- bocal
	kit.Blob(body, 50, 60, 84, 76, C.Glass, { Z = 7, T = 0.82, Outline = glassLine, Thickness = 2, Shade = false })
	kit.Part(body, 28, 18, 44, 8, C.Glass, { Radius = -1, Z = 8, T = 0.35, Outline = glassLine })
	kit.Shine(body, 18, 46, 5, 20, 9, 0.35)
	kit.Shine(body, 20, 70, 4, 5, 9, 0.45)
	return nil
end

-- Chat endormi roulé en boule dans son panier : yeux fermés, "z" qui flottent, queue qui pend
Art.SleepyCat = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(255, 200, 150)
	local stripe = kit.Darken(fur, 0.18)
	kit.Blob(body, 50, 68, 84, 16, C.PinkSoft, { Z = 2 })
	local cat = breather(body, kit, 0, 0, 100, 76, 3)
	kit.Blob(cat, 58, 58, 58, 32, fur, { Z = 2, Shine = true })
	for _, s in ipairs({ { 56, 44 }, { 65, 44 }, { 74, 46 } }) do
		kit.Line(cat, s[1], s[2], s[1] + 1.5, s[2] + 6, 2.6, stripe, 0, 3)
	end
	ear(cat, kit, 21, 44, 12, fur, C.Pink, -22, 1)
	ear(cat, kit, 39, 41, 12, fur, C.Pink, 10, 1)
	kit.Blob(cat, 31, 57, 36, 30, fur, { Z = 4, Shine = true })
	kit.Line(cat, 31, 42.5, 31, 47, 2.4, stripe, 0, 5)
	kit.Face(cat, 31, 59, 24, { Eyes = "closed", Mouth = "cat", Z = 6 })
	kit.Animate(cat, "Breathe", 0.03, 0.6, 0)
	-- panier
	kit.Part(body, 8, 70, 84, 30, C.WoodLight, { Radius = 12, Z = 5, Shade = 0.18 })
	for _, y in ipairs({ 81, 89 }) do
		kit.Box(body, 10, y, 80, 2, C.Wood, 0, 6)
	end
	kit.Part(body, 4, 66, 92, 10, C.Wood, { Radius = -1, Z = 6, Shine = true })
	-- pattes posées sur le rebord
	for _, x in ipairs({ 28, 40 }) do
		kit.Blob(body, x, 67, 10, 7, kit.Lighten(fur, 0.3), { Z = 7, Thickness = 1.3 })
	end
	-- queue qui pend du panier
	local tail = kit.Pivot(body, 84, 66, 7)
	kit.Blob(tail, 3, 11, 9, 26, fur, { Rotation = -10, Thickness = 1.5 })
	kit.Blob(tail, 5, 21, 7, 8, stripe, { Rotation = -10, Outline = false, Shade = false })
	kit.Animate(tail, "Sway", 6, 0.5, 0.8)
	-- z z z
	for index, z in ipairs({ { "z", 56, 36, 11 }, { "z", 66, 25, 14 }, { "Z", 78, 13, 17 } }) do
		local label = kit.Text(body, z[1], z[2], z[3], z[4], index == 2 and C.Purple or C.Lilac, 8)
		kit.Animate(label, "Bob", 2, 0.6, index * 1.4)
	end
	return nil
end

-- Petite tortue : carapace à motifs, tête qui sort et hoche doucement
Art.Turtle = function(body, kit, _item)
	local C = kit.C
	local shellColor = Color3.fromRGB(115, 195, 135)
	local skin = Color3.fromRGB(175, 228, 170)
	for _, x in ipairs({ 24, 58 }) do
		kit.Blob(body, x, 88, 14, 14, skin, { Z = 1, Thickness = 1.4 })
	end
	kit.Blob(body, 7, 78, 10, 6, skin, { Z = 1, Rotation = 20, Thickness = 1.3 })
	local head = kit.Pivot(body, 72, 72, 2)
	kit.Blob(head, 4, -5, 16, 12, skin, { Z = 1, Rotation = -30, Thickness = 1.4 })
	kit.Blob(head, 14, -14, 26, 24, skin, { Z = 2, Shine = true })
	kit.Face(head, 15, -13, 18, { Z = 3 })
	kit.Animate(head, "Bob", 1.2, 0.8, 0.5)
	local shell = breather(body, kit, 0, 0, 90, 84, 3)
	local clip = kit.Group(shell, 6, 32, 72, 44, 1, true)
	kit.Blob(clip, 36, 44, 72, 86, shellColor, { Z = 1, Thickness = 2 })
	local tile = kit.Lighten(shellColor, 0.3)
	kit.Blob(clip, 36, 22, 22, 17, tile, { Z = 2, Thickness = 1.2, Shade = false })
	kit.Blob(clip, 15, 32, 14, 14, tile, { Z = 2, Thickness = 1.2, Shade = false })
	kit.Blob(clip, 57, 32, 14, 14, tile, { Z = 2, Thickness = 1.2, Shade = false })
	kit.Shine(clip, 18, 12, 12, 4, 3, 0.45)
	kit.Part(shell, 2, 71, 80, 11, kit.Darken(shellColor, 0.06), { Radius = -1, Z = 3, Shade = 0.12 })
	kit.Animate(shell, "Breathe", 0.02, 0.7, 1.1)
	return nil
end

-- Chiot heureux : oreilles tombantes, tache sur l'œil, langue, collier à cœur, queue qui remue
Art.Puppy = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(255, 238, 215)
	local spot = Color3.fromRGB(215, 160, 115)
	local tail = kit.Pivot(body, 70, 86, 1)
	kit.Blob(tail, 6, -9, 9, 22, spot, { Rotation = 35, Thickness = 1.4 })
	kit.Animate(tail, "Sway", 18, 2.4, 0)
	local pup = breather(body, kit, 0, 0, 100, 98, 2)
	kit.Blob(pup, 50, 78, 48, 38, fur, { Z = 1, Shine = true })
	for _, x in ipairs({ 40, 60 }) do
		kit.Blob(pup, x, 94, 14, 9, fur, { Z = 3, Thickness = 1.4 })
	end
	kit.Part(pup, 33, 61, 34, 7, C.Pink, { Radius = -1, Z = 4 })
	kit.Heart(pup, 50, 70, 9, C.Gold, 0, 5)
	kit.Blob(pup, 50, 43, 58, 46, fur, { Z = 3, Shine = true })
	kit.Blob(pup, 62, 39, 16, 14, spot, { Z = 4, Outline = false, Shade = false })
	for index, side in ipairs({ -1, 1 }) do
		local flop = kit.Pivot(pup, 50 + side * 25, 28, 5)
		kit.Blob(flop, side * 2, 13, 16, 29, spot, { Rotation = side * -18, Thickness = 1.5 })
		kit.Animate(flop, "Sway", 4, 1, (index - 1) * HALF_PI)
	end
	kit.Face(pup, 50, 43, 34, { Mouth = "none", Z = 6 })
	kit.Blob(pup, 50, 54, 22, 14, C.White, { Z = 6, Thickness = 1.2, Shade = false })
	kit.Blob(pup, 50, 59, 6, 7, C.Pink, { Z = 6, Thickness = 1.1, Shade = false })
	snout(pup, kit, 50, 51, 11, 7)
	kit.Animate(pup, "Breathe", 0.025, 1.1, 0.3)
	return nil
end

-- Lapin tout doux : longues oreilles (une tombante), petite carotte, pompon
Art.Bunny = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(255, 250, 252)
	kit.Circle(body, 75, 88, 14, 14, fur, 0, 1)
	local bun = breather(body, kit, 0, 0, 100, 98, 2)
	for index, e in ipairs({ { 42, -10 }, { 58, 28 } }) do
		local earPivot = kit.Pivot(bun, e[1], 38, 1)
		earPivot.Rotation = e[2]
		kit.Part(earPivot, -6.5, -36, 13, 40, fur, { Radius = -1, Z = 1 })
		kit.Part(earPivot, -3, -31, 6, 28, C.PinkSoft, { Radius = -1, Z = 2, Outline = false, Shade = false })
		kit.Animate(earPivot, "Sway", 4, 0.9, index * 1.7)
	end
	kit.Blob(bun, 50, 80, 46, 34, fur, { Z = 2, Shine = true })
	kit.Blob(bun, 50, 54, 48, 38, fur, { Z = 3, Shine = true })
	kit.Face(bun, 50, 55, 30, { Mouth = "cat", Z = 5 })
	for _, x in ipairs({ 42, 58 }) do
		kit.Blob(bun, x, 94, 13, 8, fur, { Z = 4, Thickness = 1.4 })
	end
	-- carotte
	local carrot = kit.Pivot(bun, 50, 84, 5)
	carrot.Rotation = 25
	kit.Blob(carrot, 3, -7, 7, 11, C.Leaf, { Rotation = 20, Z = 1, Thickness = 1.1 })
	kit.Blob(carrot, -3, -7, 7, 11, C.Green, { Rotation = -20, Z = 1, Thickness = 1.1 })
	kit.Part(carrot, -5, -4, 10, 18, C.Orange, { Radius = 5, Z = 2 })
	kit.Line(carrot, -2, 3, 1, 3, 1.2, kit.Darken(C.Orange, 0.25), 0, 3)
	kit.Animate(bun, "Breathe", 0.025, 0.9, 1.4)
	return nil
end

-- Hamster qui court dans sa roue (la roue tourne, le hamster sautille)
Art.Hamster = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 50, 50, 28, 96, 4, C.GreyDark, 0, 1)
	kit.Line(body, 50, 50, 72, 96, 4, C.GreyDark, 0, 1)
	kit.Part(body, 18, 93, 64, 7, C.Wood, { Radius = -1, Z = 7, Shine = true })
	local ring = kit.Circle(body, 50, 50, 84, 84, C.Sky, 0.82, 2)
	kit.Stroke(ring, C.Blue, 3.5)
	local wheel = kit.Pivot(body, 50, 50, 3)
	for k = 0, 3 do
		local a = math.rad(k * 45)
		local dx, dy = math.cos(a) * 40, math.sin(a) * 40
		kit.Line(wheel, -dx, -dy, dx, dy, 1.6, C.Blue, 0.45, 1)
	end
	for k = 0, 11 do
		local a = math.rad(k * 30)
		kit.Circle(wheel, math.cos(a) * 40.5, math.sin(a) * 40.5, 3.5, 3.5, C.White, 0, 2)
	end
	kit.Animate(wheel, "Spin", 1, 0.6, 0)
	local hub = kit.Circle(body, 50, 50, 9, 9, C.Sky, 0, 6)
	kit.Stroke(hub, C.Blue, 1.6)
	-- hamster
	local fur = Color3.fromRGB(255, 196, 135)
	local ham = kit.Group(body, 30, 58, 40, 32, 5)
	for _, x in ipairs({ 12, 28 }) do
		kit.Blob(ham, x, 30, 7, 4.5, C.Pink, { Z = 1, Thickness = 1 })
	end
	for _, x in ipairs({ 13, 29 }) do
		local e = kit.Blob(ham, x, 6, 10, 10, fur, { Z = 1, Thickness = 1.3 })
		kit.Circle(e, 5, 5, 5, 5, C.Pink, 0.2, 2)
	end
	kit.Blob(ham, 20, 18, 38, 26, fur, { Z = 2, Shine = true })
	kit.Blob(ham, 23, 24, 22, 12, C.Cream, { Z = 3, Outline = false, Shade = false })
	kit.Face(ham, 22, 15, 20, { Mouth = "cat", Z = 4 })
	kit.Animate(ham, "Bob", 1.5, 3, 0)
	return nil
end

-- Perroquet sur son perchoir : il se balance, gonfle ses plumes, longue queue colorée
Art.Parrot = function(body, kit, _item)
	local C = kit.C
	local red = Color3.fromRGB(250, 115, 115)
	kit.Part(body, 47, 42, 6, 54, C.WoodDark, { Radius = 3, Z = 1 })
	kit.Part(body, 28, 93, 44, 7, C.Wood, { Radius = -1, Z = 2, Shine = true })
	kit.Part(body, 16, 40, 68, 6, C.Wood, { Radius = -1, Z = 4 })
	-- mangeoire
	kit.Part(body, 70, 31, 13, 10, C.Sky, { Radius = 3, Z = 3, Shine = true })
	for _, x in ipairs({ 73, 76.5, 80 }) do
		kit.Circle(body, x, 31, 3, 3, C.Butter, 0, 2)
	end
	-- oiseau (pivot sur les pattes)
	local bird = kit.Pivot(body, 42, 42, 5)
	kit.Blob(bird, -4, 16, 9, 36, C.Blue, { Z = 1, Rotation = 10 })
	kit.Blob(bird, 3, 15, 8, 32, C.Butter, { Z = 1, Rotation = -6 })
	local g = breather(bird, kit, -22, -52, 44, 52, 2)
	kit.Blob(g, 22, 34, 30, 36, red, { Z = 1, Shine = true })
	kit.Blob(g, 25, 40, 15, 20, kit.Lighten(red, 0.35), { Z = 2, Outline = false, Shade = false })
	local wing = kit.Pivot(g, 14, 24, 3)
	kit.Blob(wing, -2, 10, 15, 28, C.Sky, { Rotation = 14, Z = 1 })
	kit.Blob(wing, -4, 21, 10, 10, C.Butter, { Rotation = 14, Z = 2, Thickness = 1.2 })
	kit.Animate(wing, "Sway", 5, 1.2, 0.6)
	kit.Blob(g, 17, 3, 6, 11, red, { Z = 3, Rotation = -28, Thickness = 1.3 })
	kit.Blob(g, 23, 1, 6, 12, kit.Lighten(red, 0.2), { Z = 3, Rotation = 5, Thickness = 1.3 })
	kit.Blob(g, 23, 15, 30, 27, red, { Z = 4, Shine = true })
	kit.Blob(g, 28, 15, 15, 13, C.White, { Z = 5, Outline = false, Shade = false })
	kit.Face(g, 25, 15, 17, { Mouth = "none", Spacing = 0.6, Z = 6 })
	kit.Blob(g, 36, 19, 11, 12, C.Cream, { Z = 7, Rotation = 20, Thickness = 1.3 })
	kit.Blob(g, 35, 24, 7, 5, C.GreyDark, { Z = 6, Thickness = 1.1 })
	kit.Animate(g, "Breathe", 0.03, 1, 0.2)
	for _, x in ipairs({ -5, 5 }) do
		kit.Blob(bird, x, 0, 6, 5, C.Grey, { Z = 3, Thickness = 1.1 })
	end
	kit.Animate(bird, "Sway", 3, 0.7, 0)
	return nil
end

-- Renard tout doux : grandes oreilles, joues blanches, énorme queue touffue qui balance
Art.Fox = function(body, kit, _item)
	local C = kit.C
	local orange = Color3.fromRGB(255, 160, 95)
	local paw = Color3.fromRGB(175, 105, 85)
	local tail = kit.Pivot(body, 64, 92, 1)
	kit.Blob(tail, 14, -18, 26, 46, orange, { Rotation = 30, Shine = true })
	kit.Blob(tail, 24, -35, 16, 15, C.Cream, { Rotation = 30, Thickness = 1.4 })
	kit.Animate(tail, "Sway", 5, 0.8, 0.3)
	local fox = breather(body, kit, 0, 0, 100, 98, 2)
	kit.Blob(fox, 46, 78, 44, 38, orange, { Z = 1 })
	kit.Blob(fox, 46, 80, 22, 26, C.Cream, { Z = 2, Thickness = 1.2, Shade = false })
	for _, x in ipairs({ 38, 54 }) do
		kit.Blob(fox, x, 94, 11, 9, paw, { Z = 3, Thickness = 1.4 })
	end
	ear(fox, kit, 29, 30, 19, orange, C.Cream, -14, 1)
	ear(fox, kit, 63, 30, 19, orange, C.Cream, 14, 1)
	kit.Blob(fox, 46, 48, 54, 40, orange, { Z = 3, Shine = true })
	kit.Blob(fox, 36, 58, 24, 16, C.Cream, { Z = 4, Outline = false, Shade = false })
	kit.Blob(fox, 56, 58, 24, 16, C.Cream, { Z = 4, Outline = false, Shade = false })
	kit.Face(fox, 46, 49, 32, { Mouth = "none", Z = 6 })
	snout(fox, kit, 46, 55, 10, 7)
	kit.Animate(fox, "Breathe", 0.025, 0.9, 0.7)
	return nil
end

-- Bébé dragon : ailes qui battent, cornes, ventre rayé, queue en pique, petit trésor et lueur
Art.Dragon = function(body, kit, _item)
	local C = kit.C
	local scale = Color3.fromRGB(150, 220, 200)
	local wingColor = C.PinkSoft
	local bone = C.Lilac
	-- trésor
	for _, c in ipairs({ { 20, 95, 18 }, { 80, 95, 18 }, { 84, 89, 14 }, { 15, 90, 12 } }) do
		kit.Blob(body, c[1], c[2], c[3], c[3] * 0.45, C.Gold, { Z = 5, Thickness = 1.3 })
	end
	local gem = kit.Diamond(body, 26, 88, 8, C.Sky, 0, 6)
	kit.Stroke(gem, C.Blue, 1.2)
	-- queue
	local tail = kit.Pivot(body, 66, 90, 1)
	kit.Blob(tail, 12, -2, 30, 12, scale, { Rotation = -25, Thickness = 1.6 })
	kit.Diamond(tail, 27, -10, 10, C.Pink, 0, 2)
	kit.Animate(tail, "Sway", 6, 0.8, 0.4)
	-- ailes (derrière le corps, battement en miroir)
	for index, side in ipairs({ -1, 1 }) do
		local wing = kit.Pivot(body, 50 + side * 14, 62, 2)
		kit.Blob(wing, side * 14, -12, 26, 20, wingColor, { Rotation = side * -30, Z = 1, Thickness = 1.5 })
		kit.Blob(wing, side * 19, -2, 18, 13, wingColor, { Rotation = side * -10, Z = 1, Thickness = 1.5 })
		kit.Line(wing, 0, 0, side * 27, -22, 2.4, bone, 0, 2)
		kit.Circle(wing, side * 27, -22, 4, 4, bone, 0, 2)
		kit.Animate(wing, "Sway", 10, 1.3, (index - 1) * HALF_PI)
	end
	local dragon = breather(body, kit, 0, 0, 100, 98, 3)
	kit.Blob(dragon, 50, 76, 50, 42, scale, { Z = 1, Shine = true })
	kit.Blob(dragon, 50, 80, 28, 30, C.Butter, { Z = 2, Thickness = 1.3, Shade = 0.08 })
	for _, y in ipairs({ 74, 81, 88 }) do
		kit.Line(dragon, 42, y, 58, y, 1.4, C.Gold, 0.35, 3)
	end
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(dragon, 50 + side * 16, 74, 9, 15, scale, { Z = 3, Rotation = side * -20, Thickness = 1.4 })
		kit.Blob(dragon, 50 + side * 12, 95, 15, 9, scale, { Z = 3, Thickness = 1.4 })
		kit.Blob(dragon, 50 + side * 13, 19, 8, 15, C.Cream, { Z = 0, Rotation = side * 22, Thickness = 1.4 })
	end
	for _, s in ipairs({ { 50, 21, 8 }, { 42, 23, 6 }, { 58, 23, 6 } }) do
		local spike = kit.Diamond(dragon, s[1], s[2], s[3], C.Pink, 0, 1)
		kit.Stroke(spike, C.PinkDeep, 1.2)
	end
	kit.Blob(dragon, 50, 43, 60, 44, scale, { Z = 4, Shine = true })
	kit.Face(dragon, 50, 42, 36, { Eyes = "big", Mouth = "none", Z = 6 })
	kit.Blob(dragon, 50, 55, 24, 12, kit.Lighten(scale, 0.35), { Z = 5, Thickness = 1.3, Shade = false })
	for _, side in ipairs({ -1, 1 }) do
		kit.Circle(dragon, 50 + side * 4, 53, 2.2, 2.2, kit.Darken(scale, 0.4), 0, 6)
	end
	kit.Line(dragon, 46, 57.5, 50, 59.5, 1.6, C.Ink, 0, 6)
	kit.Line(dragon, 50, 59.5, 54, 57.5, 1.6, C.Ink, 0, 6)
	kit.Animate(dragon, "Breathe", 0.025, 0.9, 0.1)
	-- étincelles magiques
	for index, s in ipairs({ { 12, 38, 10 }, { 88, 28, 8 }, { 84, 62, 6 } }) do
		local spark = kit.Sparkle(body, s[1], s[2], s[3], C.Butter, 0, 7)
		kit.Animate(spark, "Bob", 2, 0.7, index * 2.3)
	end
	return { Glow = Color3.fromRGB(200, 255, 225) }
end

return Art
