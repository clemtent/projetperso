--[[
	Fun91 (ModuleScript) — (v9.1) nouveaux jouets, électronique, cuisine 🧸📺🍰
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Fun91
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas).
]]

local Art = {}

local WHITE = Color3.new(1, 1, 1)

-- Cubes de l'alphabet (A B C empilés)
Art.ToyBlocks = function(body, kit, _item)
	local C = kit.C
	for index, b in ipairs({ { 8, 64, C.Pink, "A" }, { 52, 64, C.Sky, "B" }, { 30, 28, C.Butter, "C" } }) do
		local block = kit.Part(body, b[1], b[2], 36, 36, b[3], { Radius = 6, Z = index, Shine = true })
		kit.Part(block, 5, 5, 26, 26, kit.Lighten(b[3], 0.5), { Radius = 4, Z = 2, Outline = false, Shade = false })
		kit.Text(block, b[4], 18, 19, 20, kit.Darken(b[3], 0.35), 3)
	end
	return nil
end

-- Xylophone (lames arc-en-ciel, maillets, notes)
Art.Xylophone = function(body, kit, _item)
	local C = kit.C
	local colors = { C.Red, C.Orange, C.Yellow, C.Leaf, C.Sky, C.Lilac }
	kit.Line(body, 8, 66, 92, 58, 5, C.WoodDark, 0, 1)
	kit.Line(body, 8, 90, 92, 82, 5, C.WoodDark, 0, 1)
	for index, color in ipairs(colors) do
		local h = 40 - index * 3
		local x = 8 + (index - 1) * 14
		local bar = kit.Part(body, x, 78 - h / 2 - index * 1.4, 12, h, color, { Radius = 4, Z = 2, Shine = true })
		kit.Circle(bar, 6, 5, 3, 3, WHITE, 0.2, 2)
		kit.Circle(bar, 6, h - 5, 3, 3, WHITE, 0.2, 2)
	end
	local mallet = kit.Pivot(body, 70, 40, 4)
	kit.Line(mallet, 0, 0, 16, -22, 2.5, C.WoodLight, 0, 1)
	kit.Blob(mallet, 0, 0, 10, 10, C.Pink, { Z = 2 })
	kit.Animate(mallet, "Sway", 10, 2, 0)
	local note = kit.Text(body, "♪", 88, 26, 14, C.PinkDeep, 5)
	kit.Animate(note, "Bob", 3, 1, 0.3)
	return nil
end

-- Diable en boîte (ressort qui rebondit, clown souriant)
Art.JackInTheBox = function(body, kit, _item)
	local C = kit.C
	local box = kit.Part(body, 16, 56, 68, 44, C.Sky, { Radius = 8, Z = 3, Shine = true })
	for index = 0, 2 do
		kit.Diamond(box, 14 + index * 20, 22, 10, index == 1 and C.Butter or C.Pink, 0, 2)
	end
	kit.Part(body, 84, 70, 10, 6, C.Gold, { Radius = 3, Z = 2 }) -- manivelle
	kit.Line(body, 94, 73, 94, 62, 3, C.Gold, 0, 2)
	kit.Part(body, 12, 50, 50, 8, C.Pink, { Radius = 4, Z = 4, Rotation = -28 }) -- couvercle ouvert
	local jack = kit.Group(body, 0, 0, 100, 100, 2)
	kit.Animate(jack, "Bob", 4, 2.2, 0)
	for index = 0, 3 do
		kit.Part(jack, 42, 40 + index * 5, 16, 4, C.GreyDark, { Radius = 2, Z = 1, Outline = false })
	end
	local head = kit.Blob(jack, 50, 28, 30, 28, C.Cream, { Z = 2, Shine = true })
	kit.Face(head, 15, 16, 20, { Eyes = "happy", Mouth = "o", Z = 3 })
	kit.Circle(jack, 50, 32, 7, 7, C.Red, 0, 4)
	kit.Triangle(jack, 50, 0, 26, 18, C.Lilac, 3)
	kit.Circle(jack, 50, 2, 7, 7, C.Butter, 0, 4)
	return nil
end

-- Petite voiture rose (roues, phares, drapeau)
Art.ToyCar = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 150, 196)
	kit.Part(body, 26, 38, 44, 28, kit.Lighten(pink, 0.15), { Radius = 12, Z = 1 })
	kit.Part(body, 32, 44, 32, 16, C.Glass, { Radius = 6, Z = 2 })
	kit.Box(body, 47, 44, 2, 16, WHITE, 0.2, 3)
	local car = kit.Part(body, 6, 56, 88, 30, pink, { Radius = 12, Z = 3, Shine = true })
	kit.Circle(car, 82, 12, 8, 8, C.Butter, 0, 2)
	kit.Heart(car, 44, 14, 12, WHITE, 0, 2)
	for _, x in ipairs({ 26, 74 }) do
		local wheel = kit.Blob(body, x, 88, 22, 22, C.Ink, { Z = 4 })
		kit.Circle(wheel, 11, 11, 10, 10, C.Grey, 0, 2)
		kit.Animate(wheel, "Spin", 1, 0.2, 0)
	end
	kit.Line(body, 28, 38, 28, 16, 2, C.GreyDark, 0, 0)
	local flag = kit.Part(body, 28, 14, 16, 10, C.Butter, { Radius = 2, Z = 0 })
	kit.Animate(flag, "Sway", 6, 2, 0)
	return nil
end

-- Pile de peluches (ours, lapin, chat empilés)
Art.PlushPile = function(body, kit, _item)
	local C = kit.C
	local function plush(cx, cy, w, color, earKind, z)
		if earKind == "bunny" then
			for _, side in ipairs({ -1, 1 }) do
				kit.Blob(body, cx + side * w * 0.2, cy - w * 0.62, w * 0.22, w * 0.5, color, { Z = z })
			end
		elseif earKind == "cat" then
			for _, side in ipairs({ -1, 1 }) do
				kit.Part(body, cx + side * w * 0.26 - w * 0.12, cy - w * 0.46, w * 0.24, w * 0.24, color, { Radius = 3, Z = z, Rotation = 45 })
			end
		else
			for _, side in ipairs({ -1, 1 }) do
				kit.Circle(body, cx + side * w * 0.34, cy - w * 0.36, w * 0.28, w * 0.28, color, 0, z)
			end
		end
		local head = kit.Blob(body, cx, cy, w, w * 0.86, color, { Z = z + 1, Shine = true })
		kit.Face(head, w / 2, w * 0.46, w * 0.6, { Mouth = earKind == "cat" and "cat" or "smile", Z = 3 })
	end
	kit.Blob(body, 50, 86, 90, 28, C.Wood, { Z = 1 }) -- corps de l'ours du bas
	plush(28, 74, 40, C.Wood, "bear", 2)
	plush(72, 74, 38, C.PinkSoft, "bunny", 2)
	plush(50, 40, 36, C.Butter, "cat", 5)
	kit.Heart(body, 50, 96, 12, C.Pink, 0, 8)
	return nil
end

-- Ordinateur rétro (écran vert qui défile, disquette)
Art.RetroComputer = function(body, kit, _item)
	local C = kit.C
	local beige = Color3.fromRGB(246, 236, 214)
	kit.Part(body, 10, 80, 80, 18, beige, { Radius = 5, Z = 1, Shine = true }) -- clavier
	for row = 0, 1 do
		for col = 0, 7 do
			kit.Box(body, 16 + col * 9, 84 + row * 6, 7, 4, kit.Darken(beige, 0.15), 0, 2)
		end
	end
	local case = kit.Part(body, 16, 10, 68, 64, beige, { Radius = 10, Z = 2, Shine = true })
	local screen = kit.Part(case, 8, 8, 52, 38, Color3.fromRGB(60, 80, 90), { Radius = 8, Z = 2 })
	for index = 0, 3 do
		local line = kit.Box(screen, 6, 6 + index * 7, 20 + (index * 13) % 22, 3, C.Mint, 0.1, 2)
		kit.Animate(line, "Pulse", 0.5, 1.5, index)
	end
	kit.Heart(screen, 42, 28, 10, C.Pink, 0, 3)
	kit.Box(case, 20, 52, 26, 4, kit.Darken(beige, 0.2), 0, 3) -- fente disquette
	kit.Part(body, 70, 62, 16, 16, C.Lilac, { Radius = 2, Z = 3, Rotation = 12 })
	return nil
end

-- Juke-box (arche lumineuse, disques, bulles de couleur)
Art.Jukebox = function(body, kit, _item)
	local C = kit.C
	local wood = Color3.fromRGB(200, 120, 110)
	local cabinet = kit.Part(body, 12, 18, 76, 82, wood, { Radius = 30, Z = 1, Shine = true })
	local _ = cabinet
	local arch = kit.Part(body, 18, 22, 64, 30, C.Butter, { Radius = 26, Z = 2 })
	local bulbs = {}
	for index = 0, 5 do
		local a = math.pi * (index / 5)
		local color = ({ C.Pink, C.Sky, C.Mint })[index % 3 + 1]
		local halo = kit.Circle(arch, 32 - math.cos(a) * 24, 26 - math.sin(a) * 18, 13, 13, color, 0.6, 2)
		local bulb = kit.Circle(arch, 32 - math.cos(a) * 24, 26 - math.sin(a) * 18, 7, 7, color, 0, 3)
		bulb:SetAttribute("Phase", index * 0.9)
		table.insert(bulbs, bulb)
		table.insert(bulbs, halo)
	end
	local window = kit.Part(body, 26, 46, 48, 24, C.Glass, { Radius = 6, Z = 3 })
	local record = kit.Blob(window, 24, 14, 26, 26, C.Ink, { Z = 2 })
	kit.Circle(record, 13, 13, 9, 9, C.Pink, 0, 2)
	kit.Animate(record, "Spin", 1, 0.5, 0)
	local speaker = kit.Part(body, 26, 74, 48, 20, kit.Darken(wood, 0.2), { Radius = 6, Z = 3 })
	for index = 0, 3 do
		kit.Box(speaker, 4, 3 + index * 4, 40, 2, C.Gold, 0.2, 2)
	end
	local note = kit.Text(body, "♫", 90, 30, 14, C.PinkDeep, 5)
	kit.Animate(note, "Bob", 3, 1, 0)
	return { Bulbs = bulbs, Glow = Color3.fromRGB(255, 220, 150) }
end

-- Flipper (plateau incliné, bille qui file, lumières)
Art.PinballMachine = function(body, kit, _item)
	local C = kit.C
	local purple = Color3.fromRGB(170, 120, 230)
	for _, x in ipairs({ 16, 80 }) do
		kit.Part(body, x, 64, 6, 36, C.GreyDark, { Radius = 2, Z = 1 })
	end
	local table_ = kit.Part(body, 8, 48, 84, 22, purple, { Radius = 8, Z = 2, Shine = true })
	kit.Box(table_, 6, 4, 72, 12, C.Navy, 0.2, 2)
	local ball = kit.Circle(table_, 30, 10, 6, 6, WHITE, 0, 3)
	kit.Animate(ball, "Drift", 20, 1.2, 0)
	local head = kit.Part(body, 56, 6, 38, 50, purple, { Radius = 8, Z = 3, Shine = true })
	local screen = kit.Part(head, 5, 6, 28, 26, C.Navy, { Radius = 5, Z = 2 })
	kit.Text(screen, "★", 14, 13, 16, C.Butter, 3)
	local bulbs = {}
	for index = 0, 2 do
		local color = ({ C.Pink, C.Butter, C.Mint })[index + 1]
		local halo = kit.Circle(head, 10 + index * 9, 40, 11, 11, color, 0.6, 2)
		local bulb = kit.Circle(head, 10 + index * 9, 40, 6, 6, color, 0, 3)
		bulb:SetAttribute("Phase", index * 1.4)
		table.insert(bulbs, bulb)
		table.insert(bulbs, halo)
	end
	return { Bulbs = bulbs }
end

-- Projecteur d'hologrammes (base ronde, faisceau, planète qui tourne)
Art.Hologram = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 90, 60, 18, C.GreyDark, { Z = 1, Shine = true })
	kit.Blob(body, 50, 84, 40, 10, C.Sky, { Z = 2, Outline = false })
	local beam = kit.Triangle(body, 50, 20, 60, 66, C.Sky, 1, 0.75, 10)
	local _ = beam
	local holo = kit.Group(body, 0, 0, 100, 100, 3)
	kit.Animate(holo, "Bob", 3, 1, 0)
	local planet = kit.Blob(holo, 50, 36, 30, 30, C.Mint, { Z = 1, T = 0.25, Outline = C.Sky })
	kit.Circle(planet, 10, 10, 8, 6, WHITE, 0.4, 2)
	local ring = kit.Part(holo, 30, 34, 40, 6, C.Sky, { Radius = 3, Z = 2, T = 0.3, Rotation = -14, Shade = false })
	kit.Animate(ring, "Pulse", 0.4, 1.5, 0)
	for index, spot in ipairs({ { 24, 20 }, { 78, 26 }, { 70, 56 } }) do
		local sparkle = kit.Sparkle(holo, spot[1], spot[2], 8, C.Sky, 0.1, 3)
		kit.Animate(sparkle, "Pulse", 0.7, 1.4, index)
	end
	return { Glow = Color3.fromRGB(150, 220, 255) }
end

-- Trois glaces à l'eau dans un verre
Art.Popsicles = function(body, kit, _item)
	local C = kit.C
	for index, p in ipairs({ { 30, C.Pink, -14 }, { 50, C.Butter, 0 }, { 70, C.Mint, 14 } }) do
		local stick = kit.Pivot(body, p[1], 70, index)
		stick.Rotation = p[3]
		kit.Part(stick, -3, -12, 6, 24, C.WoodLight, { Radius = 2, Z = 1 })
		local ice = kit.Part(stick, -11, -48, 22, 38, p[2], { Radius = 10, Z = 2, Shine = true })
		kit.Box(ice, 0, 22, 22, 5, kit.Darken(p[2], 0.12), 0, 2)
		kit.Face(ice, 11, 14, 14, { Z = 3 })
	end
	kit.Part(body, 26, 64, 48, 36, C.Glass, { Radius = 8, Z = 5, T = 0.3 })
	kit.Shine(body, 30, 68, 5, 20, 6, 0.3)
	return nil
end

-- Gaufrier (ouvert : gaufre dorée en cœur)
Art.WaffleMaker = function(body, kit, _item)
	local C = kit.C
	local shell = Color3.fromRGB(255, 190, 210)
	kit.Part(body, 10, 34, 80, 26, shell, { Radius = 12, Z = 1, Rotation = -8 }) -- couvercle ouvert
	local base = kit.Part(body, 8, 64, 84, 34, shell, { Radius = 12, Z = 2, Shine = true })
	local waffle = kit.Heart(base, 42, 12, 36, C.Butter, 0, 2)
	local _ = waffle
	for index = 0, 2 do
		kit.Box(base, 30 + index * 8, 2, 2, 18, kit.Darken(C.Butter, 0.25), 0.3, 3)
		kit.Box(base, 28, 4 + index * 6, 28, 2, kit.Darken(C.Butter, 0.25), 0.3, 3)
	end
	kit.Circle(base, 72, 22, 6, 6, C.Mint, 0, 3)
	local steam = kit.Text(body, "~", 50, 26, 16, WHITE, 4)
	kit.Animate(steam, "Bob", 2, 1, 0)
	return nil
end

-- Panier vapeur en bambou (raviolis qui fument)
Art.DumplingSteamer = function(body, kit, _item)
	local C = kit.C
	local bamboo = Color3.fromRGB(226, 190, 130)
	kit.Part(body, 8, 66, 84, 32, bamboo, { Radius = 10, Z = 1, Shine = true })
	kit.Box(body, 8, 76, 84, 3, kit.Darken(bamboo, 0.2), 0.3, 2)
	for index, x in ipairs({ 26, 50, 74 }) do
		local dumpling = kit.Blob(body, x, 60, 24, 20, C.Cream, { Z = 3, Shine = true })
		kit.Face(dumpling, 12, 12, 12, { Eyes = index == 2 and "happy" or "dot", Z = 2 })
		kit.Line(body, x - 5, 51, x + 5, 51, 1.5, kit.OutlineOf(C.Cream), 0.3, 4)
	end
	for index = 0, 2 do
		local steam = kit.Blob(body, 30 + index * 20, 30, 10, 18, WHITE, { Z = 4, T = 0.4, Outline = false, Shade = false })
		kit.Animate(steam, "Bob", 3, 1, index)
	end
	return nil
end

-- Évier de cuisine (plan de travail : on y pose des choses, robinet, bulles)
Art.KitchenSink = function(body, kit, _item)
	local C = kit.C
	local cabinet = kit.Part(body, 4, 44, 92, 56, C.MintSoft, { Radius = 8, Z = 1, Shine = true })
	for _, x in ipairs({ 8, 50 }) do
		kit.Part(cabinet, x, 10, 38, 40, WHITE, { Radius = 5, Z = 2, T = 0.2 })
		kit.Circle(cabinet, x + (x < 40 and 34 or 4), 30, 4, 4, C.Gold, 0, 3)
	end
	kit.Part(body, 2, 38, 96, 8, WHITE, { Radius = 3, Z = 2 }) -- plan de travail
	kit.Part(body, 30, 36, 40, 6, C.Grey, { Radius = 3, Z = 3 }) -- cuve
	kit.Line(body, 50, 38, 50, 18, 4, C.GreyDark, 0, 3)
	kit.Line(body, 50, 18, 38, 22, 4, C.GreyDark, 0, 3)
	local drop = kit.Circle(body, 38, 28, 4, 5, C.Sky, 0, 4)
	kit.Animate(drop, "Bob", 3, 2, 0)
	for index = 0, 2 do
		local bubble = kit.Circle(body, 32 + index * 8, 30 - index * 4, 7, 7, WHITE, 0.3, 4)
		kit.Animate(bubble, "Bob", 2, 1, index)
	end
	return nil
end

-- Maison en pain d'épices (glaçage, bonbons, fumée sucrée)
Art.GingerbreadHouse = function(body, kit, _item)
	local C = kit.C
	local ginger = Color3.fromRGB(196, 130, 80)
	kit.Blob(body, 50, 94, 90, 12, WHITE, { Z = 1, Outline = false })
	local house = kit.Part(body, 18, 48, 64, 48, ginger, { Radius = 6, Z = 2, Shine = true })
	kit.Part(house, 24, 22, 16, 26, kit.Darken(ginger, 0.25), { Radius = 7, Z = 2 })
	kit.Heart(house, 32, 30, 8, C.Pink, 0, 3)
	for _, x in ipairs({ 6, 46 }) do
		local win = kit.Part(house, x, 8, 12, 12, C.Butter, { Radius = 3, Z = 2 })
		kit.Box(win, 5, 0, 2, 12, WHITE, 0, 2)
	end
	kit.Triangle(body, 50, 14, 84, 38, kit.Darken(ginger, 0.1), 3)
	for index = 0, 6 do
		kit.Circle(body, 12 + index * 12.7, 51, 9, 7, WHITE, 0, 4) -- glaçage
	end
	for index, color in ipairs({ C.Red, C.Mint, C.Pink, C.Sky }) do
		kit.Circle(body, 30 + (index - 1) * 13, 38 - (index % 2) * 8, 6, 6, color, 0, 4)
	end
	kit.Part(body, 66, 18, 10, 16, C.Pink, { Radius = 2, Z = 2 })
	local smoke = kit.Circle(body, 71, 12, 8, 8, WHITE, 0.3, 2)
	kit.Animate(smoke, "Bob", 3, 0.8, 0)
	return nil
end

return Art
