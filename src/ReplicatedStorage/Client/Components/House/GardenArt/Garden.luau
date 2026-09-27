--[[
	Garden (ModuleScript) — (v9.1) dessins de la déco du jardin 🌷
	Emplacement : ReplicatedStorage > Client > Components > House > GardenArt > Garden
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas, y = 100).
	Ids = Config.House.GardenDecor (tulipes, nain, flamant rose, bain
	d'oiseaux, ruche, mare aux canards, citrouilles, bonhomme de neige,
	puits à vœux, trampoline, arc-en-ciel, statue de licorne).
]]

local Garden = {}

-- Parterre de tulipes dans une jardinière en bois
Garden.TulipBed = function(body, kit, _entry)
	local C = kit.C
	local colors = { C.Pink, C.Red, C.Butter, C.Lilac, C.Pink }
	for index, color in ipairs(colors) do
		local x = 18 + (index - 1) * 16
		local top = 44 + (index % 2) * 8
		kit.Line(body, x, top + 6, x, 80, 3, C.LeafDark, 0, 1)
		kit.Blob(body, x + 5, 70 - (index % 2) * 4, 10, 16, C.Leaf, { Z = 1, Rotation = 30, Thickness = 1.2 })
		local cup = kit.Part(body, x - 7, top - 8, 14, 16, color, { Radius = 6, Z = 2, Thickness = 1.3 })
		kit.Box(cup, 4, -3, 6, 6, color, 0, 1).Rotation = 45
		kit.Shine(cup, 3, 3, 3, 6, 3, 0.4)
	end
	local box = kit.Part(body, 6, 76, 88, 22, C.Wood, { Radius = 6, Z = 4, Shine = true })
	for index = 1, 3 do
		kit.Box(box, index * 22, 3, 2, 16, kit.Darken(C.Wood, 0.2), 0.4, 2)
	end
	kit.Heart(body, 50, 87, 12, C.Pink, 0, 5)
	return nil
end

-- Nain de jardin (bonnet rouge, barbe blanche, petite pelle)
Garden.GardenGnome = function(body, kit, _entry)
	local C = kit.C
	kit.Blob(body, 50, 94, 44, 10, C.GreyDark, { Z = 1, Outline = false, Shade = false, T = 0.5 })
	kit.Part(body, 32, 60, 36, 36, C.Blue, { Radius = 12, Z = 2, Shine = true })
	kit.Part(body, 34, 84, 14, 12, C.Brown, { Radius = 5, Z = 3 })
	kit.Part(body, 52, 84, 14, 12, C.Brown, { Radius = 5, Z = 3 })
	kit.Box(body, 32, 76, 36, 5, C.Brown, 0, 3)
	kit.Blob(body, 50, 50, 30, 26, C.Peach, { Z = 4, Shine = true })
	kit.Face(body, 50, 48, 20, { Eyes = "happy", Mouth = "none", Z = 7 })
	kit.Blob(body, 50, 60, 30, 24, C.White, { Z = 5 })
	kit.Circle(body, 50, 52, 8, 7, C.Blush, 0, 6)
	local hat = kit.Triangle(body, 50, 10, 34, 34, C.Red, 4)
	local _ = hat
	kit.Blob(body, 50, 40, 36, 10, kit.Darken(C.Red, 0.1), { Z = 5 })
	kit.Circle(body, 50, 12, 8, 8, C.White, 0, 6)
	-- pelle
	kit.Line(body, 74, 56, 80, 92, 3, C.WoodDark, 0, 3)
	kit.Part(body, 74, 86, 12, 12, C.GreyDark, { Radius = 4, Z = 4 })
	return nil
end

-- Flamant rose sur une patte (se balance doucement)
Garden.PinkFlamingo = function(body, kit, _entry)
	local C = kit.C
	local pink = Color3.fromRGB(255, 150, 190)
	kit.Line(body, 48, 64, 48, 98, 3, kit.Darken(pink, 0.3), 0, 1)
	kit.Line(body, 48, 78, 58, 72, 2.5, kit.Darken(pink, 0.3), 0, 1)
	local bird = kit.Pivot(body, 48, 64, 2)
	kit.Animate(bird, "Sway", 3, 0.6, 0.4)
	kit.Blob(bird, 4, -8, 44, 28, pink, { Z = 2, Shine = true })
	kit.Blob(bird, 14, -12, 22, 14, kit.Darken(pink, 0.08), { Z = 3, Rotation = -20 })
	kit.Line(bird, -12, -12, -14, -46, 6, pink, 0, 2)
	kit.Blob(bird, -10, -50, 18, 16, pink, { Z = 3, Shine = true })
	kit.Circle(bird, -7, -52, 3.5, 3.5, C.Ink, 0, 4)
	kit.Part(bird, -26, -52, 12, 7, C.White, { Radius = 3, Z = 3, Rotation = 20 })
	kit.Part(bird, -28, -48, 6, 5, C.Ink, { Radius = 2, Z = 4, Rotation = 20, Outline = false })
	kit.Circle(bird, -12, -46, 5, 3, C.Blush, 0.3, 4)
	return nil
end

-- Bain d'oiseaux en pierre + un petit oiseau bleu
Garden.Birdbath = function(body, kit, _entry)
	local C = kit.C
	local stone = Color3.fromRGB(226, 220, 240)
	kit.Part(body, 32, 88, 36, 10, kit.Darken(stone, 0.08), { Radius = 4, Z = 1 })
	kit.Part(body, 43, 56, 14, 34, stone, { Radius = 5, Z = 2, Shine = true })
	kit.Blob(body, 50, 54, 76, 18, stone, { Z = 3, Shine = true })
	kit.Blob(body, 50, 50, 60, 9, C.Sky, { Z = 4, Outline = false, Shade = false })
	kit.Shine(body, 30, 47, 14, 3, 5, 0.3)
	local bird = kit.Group(body, 0, 0, 100, 100, 6)
	kit.Animate(bird, "Bob", 1.5, 1.2, 0.2)
	kit.Blob(bird, 68, 38, 18, 14, C.Blue, { Z = 1, Shine = true })
	kit.Blob(bird, 76, 32, 12, 11, C.Blue, { Z = 2 })
	kit.Circle(bird, 78, 31, 2.5, 2.5, C.Ink, 0, 3)
	kit.Part(bird, 82, 32, 6, 4, C.Orange, { Radius = 2, Z = 3, Outline = false })
	kit.Blob(bird, 64, 38, 10, 7, C.Sky, { Z = 3, Outline = false })
	return nil
end

-- Ruche en paille + abeilles qui tournent autour
Garden.Beehive = function(body, kit, _entry)
	local C = kit.C
	kit.Part(body, 26, 84, 48, 14, C.WoodDark, { Radius = 4, Z = 1 })
	local straw = Color3.fromRGB(246, 200, 110)
	for index = 0, 3 do
		local w = 56 - index * 10
		kit.Part(body, 50 - w / 2, 70 - index * 13, w, 16, index % 2 == 0 and straw or kit.Darken(straw, 0.08), { Radius = 8, Z = 2 + index })
	end
	kit.Circle(body, 50, 74, 12, 10, C.Brown, 0, 8)
	kit.Face(body, 50, 56, 18, { Eyes = "happy", Z = 9 })
	kit.Blob(body, 58, 26, 6, 10, C.Gold, { Z = 9, Rotation = 30 })
	for index, spot in ipairs({ { 18, 36 }, { 82, 44 } }) do
		local bee = kit.Group(body, 0, 0, 100, 100, 10)
		kit.Animate(bee, index == 1 and "Drift" or "Bob", 4, 1.4, index)
		kit.Blob(bee, spot[1], spot[2], 12, 9, C.Yellow, { Z = 1 })
		kit.Box(bee, spot[1] - 1, spot[2] - 4, 2.5, 8, C.Ink, 0, 2)
		kit.Blob(bee, spot[1] - 2, spot[2] - 7, 7, 5, C.White, { Z = 0, T = 0.3, Outline = false })
	end
	return nil
end

-- Mare aux canards (nénuphar, deux canetons)
Garden.DuckPond = function(body, kit, _entry)
	local C = kit.C
	kit.Blob(body, 50, 84, 96, 28, C.GreyDark, { Z = 1, T = 0.2 })
	kit.Blob(body, 50, 82, 88, 22, C.Sky, { Z = 2, Shine = true })
	kit.Blob(body, 26, 82, 16, 7, C.Leaf, { Z = 3 })
	kit.Circle(body, 26, 80, 6, 6, C.Pink, 0, 4)
	for index, x in ipairs({ 54, 74 }) do
		local duck = kit.Group(body, 0, 0, 100, 100, 5)
		kit.Animate(duck, "Bob", 1.2, 1, index)
		local s = index == 1 and 1 or 0.8
		kit.Blob(duck, x, 74, 18 * s, 12 * s, C.Butter, { Z = 1, Shine = true })
		kit.Blob(duck, x + 7 * s, 66, 11 * s, 10 * s, C.Butter, { Z = 2 })
		kit.Circle(duck, x + 9 * s, 65, 2.5, 2.5, C.Ink, 0, 3)
		kit.Part(duck, x + 11 * s, 67, 6 * s, 4 * s, C.Orange, { Radius = 2, Z = 3, Outline = false })
	end
	for index = 0, 2 do
		kit.Circle(body, 40 + index * 8, 88, 12, 3, C.White, 0.5, 3)
	end
	return nil
end

-- Petit champ de citrouilles souriantes
Garden.PumpkinPatch = function(body, kit, _entry)
	local C = kit.C
	kit.Blob(body, 50, 94, 90, 10, C.Brown, { Z = 1, Outline = false, T = 0.3 })
	for index, p in ipairs({ { 30, 78, 34 }, { 68, 74, 42 }, { 50, 88, 24 } }) do
		local cx, cy, w = p[1], p[2], p[3]
		local color = index == 3 and C.Butter or C.Orange
		kit.Blob(body, cx - w * 0.22, cy, w * 0.6, w * 0.8, kit.Darken(color, 0.06), { Z = index * 2 })
		kit.Blob(body, cx + w * 0.22, cy, w * 0.6, w * 0.8, kit.Darken(color, 0.06), { Z = index * 2 })
		kit.Blob(body, cx, cy, w * 0.6, w * 0.84, color, { Z = index * 2 + 1, Shine = true })
		kit.Part(body, cx - 2, cy - w * 0.52, 5, 8, C.LeafDark, { Radius = 2, Z = index * 2 + 1 })
		kit.Face(body, cx, cy + 2, w * 0.5, { Eyes = "happy", Z = index * 2 + 1 })
	end
	kit.Blob(body, 84, 60, 16, 10, C.Leaf, { Z = 2, Rotation = -20 })
	return nil
end

-- Bonhomme de neige (écharpe rose, bonnet, bras en brindilles)
Garden.Snowman = function(body, kit, _entry)
	local C = kit.C
	kit.Blob(body, 50, 76, 48, 42, C.White, { Z = 1, Shine = true })
	kit.Blob(body, 50, 42, 36, 32, C.White, { Z = 2, Shine = true })
	kit.Face(body, 50, 42, 22, { Z = 5 })
	kit.Part(body, 52, 43, 10, 5, C.Orange, { Radius = 2, Z = 6, Rotation = 10 })
	kit.Part(body, 32, 54, 36, 8, C.Pink, { Radius = 4, Z = 4 })
	kit.Part(body, 56, 56, 8, 18, C.Pink, { Radius = 3, Z = 4, Rotation = -10 })
	kit.Part(body, 34, 20, 32, 12, C.Lilac, { Radius = 6, Z = 4 })
	kit.Circle(body, 50, 16, 10, 10, C.White, 0, 5)
	kit.Line(body, 28, 70, 10, 58, 2.5, C.WoodDark, 0, 1)
	kit.Line(body, 72, 70, 90, 58, 2.5, C.WoodDark, 0, 1)
	for index = 0, 2 do
		kit.Circle(body, 50, 68 + index * 9, 4, 4, C.Ink, 0, 3)
	end
	return nil
end

-- Puits à vœux (toit de tuiles roses, seau, petite étincelle)
Garden.WishingWell = function(body, kit, _entry)
	local C = kit.C
	local stone = Color3.fromRGB(214, 206, 232)
	kit.Part(body, 22, 66, 56, 32, stone, { Radius = 8, Z = 3, Shine = true })
	for row = 0, 1 do
		for col = 0, 2 do
			kit.Box(body, 26 + col * 17 + row * 8, 72 + row * 12, 14, 8, kit.Darken(stone, 0.08), 0.3, 4)
		end
	end
	kit.Blob(body, 50, 66, 56, 10, C.Navy, { Z = 2 })
	kit.Part(body, 24, 28, 6, 40, C.Wood, { Radius = 2, Z = 1 })
	kit.Part(body, 70, 28, 6, 40, C.Wood, { Radius = 2, Z = 1 })
	kit.Triangle(body, 50, 10, 70, 24, C.Pink, 5)
	kit.Box(body, 14, 32, 72, 4, kit.Darken(C.Pink, 0.2), 0, 5)
	kit.Line(body, 50, 36, 50, 52, 1.5, C.Brown, 0, 2)
	kit.Part(body, 44, 50, 12, 10, C.WoodDark, { Radius = 3, Z = 3 })
	local wish = kit.Sparkle(body, 74, 50, 12, C.Butter, 0, 6)
	kit.Animate(wish, "Bob", 2, 1, 0.5)
	return nil
end

-- Trampoline (filet, ressorts, un ballon qui rebondit)
Garden.Trampoline = function(body, kit, _entry)
	local C = kit.C
	for _, x in ipairs({ 16, 34, 66, 84 }) do
		kit.Line(body, x, 72, x + (x < 50 and -4 or 4), 98, 3, C.GreyDark, 0, 1)
	end
	kit.Blob(body, 50, 70, 92, 20, C.Sky, { Z = 2 })
	kit.Blob(body, 50, 69, 76, 12, C.Navy, { Z = 3, Outline = false })
	for index = 0, 5 do
		kit.Line(body, 16 + index * 13, 63, 18 + index * 13, 67, 1.5, C.White, 0.2, 4)
	end
	local ball = kit.Group(body, 0, 0, 100, 100, 5)
	kit.Animate(ball, "Bob", 10, 1.4, 0)
	local b = kit.Blob(ball, 50, 36, 22, 22, C.Pink, { Z = 1, Shine = true })
	kit.Box(b, 10, 0, 2, 22, C.White, 0.2, 2)
	kit.Sparkle(body, 22, 30, 10, C.Butter, 0, 6)
	return nil
end

-- Arc-en-ciel posé sur deux nuages
Garden.RainbowArch = function(body, kit, _entry)
	local C = kit.C
	local colors = { C.Red, C.Orange, C.Yellow, C.Leaf, C.Sky, C.Lilac }
	local clip = kit.Group(body, 0, 0, 100, 76, 1, true)
	-- anneaux (contours épais de cercles vides), moitié haute seulement
	for index, color in ipairs(colors) do
		local size = 86 - (index - 1) * 11
		local ring = kit.Circle(clip, 50, 80, size, size, color, 1, index)
		kit.Stroke(ring, color, 5.6, 0)
	end
	kit.Cloud(body, 18, 92, 38, C.White, 0, 3)
	kit.Cloud(body, 82, 92, 38, C.White, 0, 3)
	local sparkle = kit.Sparkle(body, 50, 18, 12, C.White, 0, 4)
	kit.Animate(sparkle, "Pulse", 0.6, 1, 0.3)
	return nil
end

-- Statue de licorne en marbre sur un socle doré
Garden.UnicornStatue = function(body, kit, _entry)
	local C = kit.C
	local marble = Color3.fromRGB(248, 244, 255)
	kit.Part(body, 22, 80, 56, 18, C.Gold, { Radius = 5, Z = 1, Shine = true })
	kit.Heart(body, 50, 89, 10, C.Pink, 0, 2)
	kit.Blob(body, 48, 62, 44, 26, marble, { Z = 2, Shine = true })
	for _, x in ipairs({ 32, 44, 56, 64 }) do
		kit.Part(body, x - 3, 66, 7, 16, marble, { Radius = 3, Z = 1 })
	end
	kit.Part(body, 60, 34, 14, 30, marble, { Radius = 6, Z = 3, Rotation = 18 })
	kit.Blob(body, 72, 30, 24, 18, marble, { Z = 4, Shine = true })
	kit.Circle(body, 76, 28, 3, 3, C.Ink, 0, 5)
	kit.Triangle(body, 72, 6, 7, 18, C.Gold, 5)
	for index, color in ipairs({ C.Pink, C.Lilac, C.Sky }) do
		kit.Blob(body, 60 - index * 3, 30 + index * 6, 10, 8, color, { Z = 4 })
	end
	kit.Blob(body, 24, 56, 12, 18, C.Pink, { Z = 1, Rotation = -30 })
	local shine = kit.Sparkle(body, 22, 34, 12, C.Butter, 0, 6)
	kit.Animate(shine, "Pulse", 0.6, 1.2, 1)
	return nil
end

return Garden
