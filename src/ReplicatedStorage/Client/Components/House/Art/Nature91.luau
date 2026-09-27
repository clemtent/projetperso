--[[
	Nature91 (ModuleScript) — (v9.1) plantes, lumières, fenêtres, portes et
	animaux 🪴💡🪟🚪🐾
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Nature91
	Contrat : voir HouseArt ; animaux : voir Art/Pets (parties "animal" dans
	des groupes dont le nom commence par "Pet", le reste = leur maison).
]]

local Art = {}

local WHITE = Color3.new(1, 1, 1)

-- Pot arrondi avec bord et petit visage
local function pot(body, kit, x, y, w, h, color, face)
	local frame = kit.Part(body, x, y, w, h, color, { Radius = 8, Z = 5, Shine = true })
	kit.Part(body, x - 3, y - 2, w + 6, 8, kit.Darken(color, 0.06), { Radius = 4, Z = 6 })
	if face then
		kit.Face(frame, w / 2, h * 0.55, math.min(w, h) * 0.6, { Z = 3 })
	end
	return frame
end

-- Groupe qui respire (échelle ancrée en bas au centre)
local function breather(parent, kit, x, y, w, h, z)
	local g = kit.Group(parent, x, y, w, h, z)
	g.AnchorPoint = Vector2.new(0.5, 1)
	g.Position = UDim2.fromOffset(x + w / 2, y + h)
	return g
end

-- Trio de succulentes dans des petits pots pastel
Art.SucculentTrio = function(body, kit, _item)
	local C = kit.C
	for index, p in ipairs({ { 6, C.Pink, 0.9 }, { 36, C.Sky, 1.1 }, { 66, C.Butter, 0.9 } }) do
		local cx = p[1] + 14
		local s = p[3]
		for k = 0, 4 do
			local angle = -60 + k * 30
			local leaf = kit.Blob(body, cx + math.sin(math.rad(angle)) * 7 * s, 62 - math.cos(math.rad(angle)) * 8 * s, 9 * s, 18 * s, k % 2 == 0 and C.Mint or C.Leaf, { Z = 2, Rotation = angle, Thickness = 1.2 })
			local _ = leaf
		end
		kit.Blob(body, cx, 66, 12 * s, 12 * s, C.Mint, { Z = 3 })
		if index == 2 then
			kit.Circle(body, cx, 50, 7, 7, C.Pink, 0, 4) -- petite fleur
		end
		pot(body, kit, p[1], 70, 28, 28, p[2], index == 2)
	end
	return nil
end

-- Pot de lavande (épis violets qui ondulent)
Art.LavenderPot = function(body, kit, _item)
	local C = kit.C
	local purple = Color3.fromRGB(170, 130, 230)
	for index = 0, 6 do
		local x = 28 + index * 7.3
		local sway = kit.Pivot(body, x, 64, 2)
		kit.Line(sway, 0, 0, (index - 3) * 2, -40 - (index % 2) * 8, 1.6, C.LeafDark, 0, 1)
		for bud = 0, 3 do
			kit.Blob(sway, (index - 3) * 2 * (0.6 + bud * 0.1), -30 - (index % 2) * 8 - bud * 4, 6, 7, purple, { Z = 2, Thickness = 1, Shade = false })
		end
		kit.Animate(sway, "Sway", 4, 0.8, index * 0.6)
	end
	pot(body, kit, 22, 62, 56, 36, C.Cream, true)
	kit.Heart(body, 70, 86, 10, purple, 0, 8)
	return nil
end

-- Terrarium suspendu (bulle de verre, fougère, champignon)
Art.HangingTerrarium = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 50, 0, 50, 22, 1.5, C.Brown, 0, 1)
	local swing = kit.Pivot(body, 50, 2, 2)
	kit.Animate(swing, "Sway", 4, 0.6, 0)
	local glass = kit.Blob(swing, 0, 56, 60, 56, C.Glass, { Z = 1, T = 0.35, Outline = C.Sky })
	kit.Blob(glass, 30, 44, 50, 20, C.Brown, { Z = 2, Outline = false, Shade = false })
	kit.Blob(glass, 22, 38, 12, 20, C.Leaf, { Z = 3, Rotation = -25 })
	kit.Blob(glass, 34, 34, 12, 24, C.LeafDark, { Z = 3, Rotation = 18 })
	local cap = kit.Blob(glass, 42, 40, 12, 8, C.Red, { Z = 4 })
	kit.Circle(cap, 4, 3, 3, 3, WHITE, 0, 2)
	kit.Shine(glass, 10, 10, 6, 14, 5, 0.3)
	kit.Part(swing, -8, 26, 16, 6, C.Gold, { Radius = 3, Z = 2 })
	return { WallShadow = Vector2.new(0.5, 0.55) }
end

-- Bol de lotus (eau, fleur rose, feuilles rondes, poisson rouge)
Art.LotusBowl = function(body, kit, _item)
	local C = kit.C
	local bowl = kit.Part(body, 8, 62, 84, 36, C.Sky, { Radius = 16, Z = 3, Shine = true })
	kit.Blob(body, 50, 64, 80, 12, Color3.fromRGB(140, 210, 240), { Z = 4, Outline = false })
	kit.Face(bowl, 42, 22, 20, { Eyes = "happy", Z = 3 })
	kit.Blob(body, 26, 62, 26, 9, C.Leaf, { Z = 5 })
	kit.Blob(body, 74, 63, 22, 8, C.LeafDark, { Z = 5 })
	local flower = kit.Group(body, 0, 0, 100, 100, 6)
	kit.Animate(flower, "Bob", 1.5, 0.8, 0)
	for k = -2, 2 do
		kit.Blob(flower, 50 + k * 7, 50 - (2 - math.abs(k)) * 3, 12, 24, k % 2 == 0 and C.Pink or C.PinkSoft, { Z = 1 + (2 - math.abs(k)), Rotation = k * 22 })
	end
	kit.Circle(flower, 50, 54, 8, 6, C.Butter, 0, 5)
	return nil
end

-- Arbre arc-en-ciel (feuillage multicolore, fruits-cœurs, étincelles)
Art.RainbowTree = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 44, 58, 12, 34, C.Wood, { Radius = 4, Z = 1 })
	pot(body, kit, 28, 84, 44, 16, C.Lilac, false)
	local crown = kit.Group(body, 0, 0, 100, 100, 2)
	kit.Animate(crown, "Breathe", 0.02, 0.8, 0)
	local colors = { C.Red, C.Orange, C.Yellow, C.Leaf, C.Sky, C.Lilac }
	for index, color in ipairs(colors) do
		local a = (index - 1) / #colors * math.pi * 2
		kit.Blob(crown, 50 + math.cos(a) * 26, 36 + math.sin(a) * 18, 36, 32, color, { Z = index, Shine = true })
	end
	kit.Blob(crown, 50, 36, 40, 34, WHITE, { Z = 8, Shine = true })
	kit.Face(crown, 50, 36, 22, { Eyes = "happy", Z = 9 })
	for index, spot in ipairs({ { 18, 12 }, { 84, 20 }, { 50, 2 } }) do
		local sparkle = kit.Sparkle(body, spot[1], spot[2], 12, WHITE, 0, 10)
		kit.Animate(sparkle, "Pulse", 0.7, 1.3, index)
	end
	return { Glow = Color3.fromRGB(255, 230, 250) }
end

-- Lampe tulipe (abat-jour en fleur, tige verte)
Art.TulipLamp = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 94, 44, 12, C.Mint, { Z = 1, Shine = true })
	kit.Line(body, 50, 92, 50, 44, 4, C.LeafDark, 0, 2)
	kit.Blob(body, 60, 70, 18, 8, C.Leaf, { Z = 2, Rotation = -30 })
	local shade = kit.Part(body, 26, 14, 48, 36, C.Pink, { Radius = 16, Z = 3, Shine = true })
	for _, x in ipairs({ 22, 36, 50 }) do
		kit.Part(body, x + 2, 6, 14, 18, C.Pink, { Radius = 7, Z = 2 })
	end
	local bulb = kit.Circle(shade, 24, 30, 16, 10, C.Butter, 0, 2)
	kit.Animate(bulb, "Pulse", 0.3, 1, 0)
	return { Glow = Color3.fromRGB(255, 200, 220) }
end

-- Lampe méduse (cloche lumineuse, tentacules qui ondulent)
Art.JellyfishLamp = function(body, kit, _item)
	local C = kit.C
	local jelly = Color3.fromRGB(190, 170, 255)
	kit.Blob(body, 50, 94, 50, 12, C.Navy, { Z = 1, Shine = true })
	local float = kit.Group(body, 0, 0, 100, 100, 2)
	kit.Animate(float, "Bob", 4, 0.8, 0)
	for index = 0, 4 do
		local tentacle = kit.Pivot(float, 30 + index * 10, 50, 1)
		kit.Blob(tentacle, 0, 16, 5, 30, index % 2 == 0 and C.Pink or C.Sky, { Z = 1, T = 0.2, Thickness = 1 })
		kit.Animate(tentacle, "Sway", 8, 1.2, index)
	end
	local bell = kit.Blob(float, 50, 40, 60, 44, jelly, { Z = 3, T = 0.1, Shine = true })
	kit.Face(bell, 30, 24, 22, { Z = 3 })
	kit.Box(float, 20, 52, 60, 6, jelly, 0.2, 3)
	return { Glow = Color3.fromRGB(200, 170, 255) }
end

-- Enseigne néon étoile (contour qui clignote)
Art.NeonStar = function(body, kit, _item)
	local C = kit.C
	local neon = Color3.fromRGB(255, 210, 90)
	kit.Part(body, 10, 12, 80, 76, Color3.fromRGB(70, 60, 110), { Radius = 12, Z = 1 })
	local star = kit.Sparkle(body, 50, 48, 58, neon, 0, 2)
	kit.Animate(star, "Pulse", 0.25, 2, 0)
	kit.Diamond(body, 50, 48, 22, neon, 0, 3)
	kit.Circle(body, 50, 48, 10, 10, WHITE, 0, 4)
	local bulbs = {}
	for index = 0, 5 do
		local x = 18 + index * 12.8
		local halo = kit.Circle(body, x, 80, 9, 9, C.Pink, 0.6, 2)
		local dot = kit.Circle(body, x, 80, 5, 5, C.Pink, 0, 3)
		dot:SetAttribute("Phase", index * 1.1)
		table.insert(bulbs, dot)
		table.insert(bulbs, halo)
	end
	return { Glow = neon, Bulbs = bulbs, WallShadow = Vector2.new(0.8, 0.76) }
end

-- Fenêtre cintrée (arc, croisillons, lune et étoiles, jardinière)
Art.ArchWindow = function(body, kit, _item)
	local C = kit.C
	local frame = kit.Part(body, 16, 6, 68, 84, C.Cream, { Radius = 34, Z = 1 })
	local glass = kit.Part(frame, 6, 6, 56, 74, Color3.fromRGB(150, 180, 250), { Radius = 28, Z = 2, Outline = false })
	kit.Gradient(glass, Color3.fromRGB(160, 170, 255), WHITE, 90)
	local moon = kit.Circle(glass, 36, 20, 14, 14, C.Butter, 0, 3)
	kit.Circle(moon, 10, 4, 12, 12, Color3.fromRGB(170, 180, 255), 0, 2)
	for index, spot in ipairs({ { 14, 18 }, { 20, 40 }, { 42, 44 } }) do
		local star = kit.Sparkle(glass, spot[1], spot[2], 7, WHITE, 0, 3)
		kit.Animate(star, "Pulse", 0.6, 1, index)
	end
	kit.Box(body, 49, 12, 3, 76, C.Cream, 0, 3)
	kit.Box(body, 22, 50, 56, 3, C.Cream, 0, 3)
	kit.Part(body, 10, 86, 80, 8, C.Cream, { Radius = 3, Z = 4 })
	for index, color in ipairs({ C.Pink, C.Butter, C.Lilac }) do
		kit.Circle(body, 30 + (index - 1) * 20, 84, 10, 10, color, 0, 5)
	end
	return { WallShadow = Vector2.new(0.72, 0.9) }
end

-- Vitrail (rosace colorée qui brille)
Art.StainedGlass = function(body, kit, _item)
	local C = kit.C
	local lead = Color3.fromRGB(90, 76, 110)
	local frame = kit.Part(body, 14, 4, 72, 92, C.Cream, { Radius = 36, Z = 1 })
	local glass = kit.Part(frame, 6, 6, 60, 80, lead, { Radius = 30, Z = 2, Outline = false })
	local colors = { C.Pink, C.Sky, C.Butter, C.Mint, C.Lilac, C.Peach }
	for row = 0, 3 do
		for col = 0, 2 do
			local color = colors[(row * 3 + col) % #colors + 1]
			local pane = kit.Part(glass, 4 + col * 18, 30 + row * 12, 16, 10, color, { Radius = 2, Z = 2, Outline = false, Shade = false })
			local _ = pane
		end
	end
	local rose = kit.Circle(glass, 30, 16, 30, 30, C.Pink, 0, 3)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		kit.Circle(rose, 15 + math.cos(a) * 8, 15 + math.sin(a) * 8, 9, 9, colors[k + 1], 0, 2)
	end
	kit.Heart(rose, 15, 15, 9, WHITE, 0, 3)
	local shine = kit.Box(glass, 6, 6, 8, 70, WHITE, 0.7, 4)
	kit.Animate(shine, "Pulse", 0.2, 0.6, 0)
	return { Glow = Color3.fromRGB(255, 220, 240), WallShadow = Vector2.new(0.74, 0.94) }
end

-- Porte hollandaise pastel (moitié haute ouverte, couronne de fleurs)
Art.DutchDoor = function(body, kit, _item)
	local C = kit.C
	local mint = Color3.fromRGB(170, 226, 206)
	kit.Part(body, 16, 4, 68, 96, C.Cream, { Radius = 8, Z = 1 }) -- chambranle
	kit.Part(body, 22, 10, 56, 40, Color3.fromRGB(90, 76, 110), { Radius = 4, Z = 2 }) -- ouverture
	kit.Part(body, 24, 40, 52, 8, C.Wood, { Radius = 3, Z = 3 }) -- tablette
	kit.Blob(body, 40, 38, 12, 10, C.Peach, { Z = 4 })
	local top = kit.Part(body, 70, 10, 18, 40, mint, { Radius = 4, Z = 3 }) -- battant ouvert
	local _ = top
	local bottom = kit.Part(body, 22, 50, 56, 50, mint, { Radius = 4, Z = 3, Shine = true })
	kit.Part(bottom, 6, 8, 44, 34, kit.Lighten(mint, 0.3), { Radius = 4, Z = 2, Outline = false })
	kit.Circle(bottom, 46, 22, 5, 5, C.Gold, 0, 3)
	-- couronne de fleurs
	local wreath = kit.Circle(body, 50, 24, 20, 20, C.Leaf, 1, 5)
	kit.Stroke(wreath, C.Leaf, 4, 0)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		kit.Circle(body, 50 + math.cos(a) * 10, 24 + math.sin(a) * 10, 5, 5, k % 2 == 0 and C.Pink or C.Butter, 0, 6)
	end
	return nil
end

-- Porte de château (arche de pierre, grille dorée, drapeaux)
Art.CastleGate = function(body, kit, _item)
	local C = kit.C
	local stone = Color3.fromRGB(226, 218, 240)
	for _, x in ipairs({ 4, 76 }) do
		kit.Part(body, x, 20, 20, 80, stone, { Radius = 4, Z = 2, Shine = true })
		for k = 0, 1 do
			kit.Box(body, x + k * 12, 14, 8, 8, stone, 0, 2)
		end
		kit.Triangle(body, x + 10, 0, 22, 16, C.Lilac, 3)
		local flag = kit.Part(body, x + 10, -6, 12, 8, C.Pink, { Radius = 2, Z = 1 })
		kit.Animate(flag, "Sway", 6, 1.5, x)
	end
	kit.Part(body, 22, 16, 56, 84, stone, { Radius = 26, Z = 1, Shine = true })
	local door = kit.Part(body, 30, 30, 40, 70, Color3.fromRGB(150, 100, 90), { Radius = 20, Z = 3 })
	for k = 0, 3 do
		kit.Box(door, 5 + k * 9, 4, 3, 66, C.Gold, 0, 2)
	end
	for k = 0, 2 do
		kit.Box(door, 0, 18 + k * 18, 40, 3, C.Gold, 0, 2)
	end
	kit.Heart(body, 50, 22, 14, C.Heart, 0, 4)
	return nil
end

-- Caneton dans son nid (trottine, picore)
Art.Duckling = function(body, kit, _item)
	local C = kit.C
	local yellow = Color3.fromRGB(255, 230, 120)
	-- nid (sa maison)
	kit.Blob(body, 50, 90, 90, 20, C.WoodLight, { Z = 1 })
	for k = 0, 5 do
		kit.Line(body, 10 + k * 14, 84, 22 + k * 14, 96, 1.5, C.Wood, 0.2, 2)
	end
	local duck = breather(body, kit, 0, 0, 100, 90, 3)
	duck.Name = "Pet"
	kit.Blob(duck, 54, 66, 50, 36, yellow, { Z = 1, Shine = true })
	local wing = kit.Pivot(duck, 62, 64, 2)
	kit.Blob(wing, 4, 2, 20, 14, kit.Darken(yellow, 0.06), { Rotation = -20 })
	kit.Animate(wing, "Sway", 10, 1.4, 0)
	kit.Blob(duck, 36, 44, 32, 30, yellow, { Z = 3, Shine = true })
	kit.Face(duck, 36, 44, 22, { Mouth = "none", Z = 4 })
	kit.Part(duck, 14, 46, 14, 8, C.Orange, { Radius = 4, Z = 5 })
	kit.Blob(duck, 38, 28, 6, 8, yellow, { Z = 4, Rotation = 20 })
	kit.Animate(duck, "Breathe", 0.03, 1.2, 0)
	return nil
end

-- Petit manchot sur sa banquise (se dandine, écharpe)
Art.Penguin = function(body, kit, _item)
	local C = kit.C
	local navy = Color3.fromRGB(70, 76, 120)
	kit.Blob(body, 50, 92, 94, 18, Color3.fromRGB(226, 242, 255), { Z = 1, Shine = true }) -- banquise
	kit.Blob(body, 50, 97, 94, 8, C.Sky, { Z = 0, Outline = false })
	local bird = breather(body, kit, 0, 0, 100, 92, 3)
	bird.Name = "Pet"
	for _, side in ipairs({ -1, 1 }) do
		local flipper = kit.Pivot(bird, 50 + side * 22, 48, 1)
		kit.Blob(flipper, side * 4, 12, 10, 26, navy, { Rotation = side * -15 })
		kit.Animate(flipper, "Sway", 10, 1.2, side)
	end
	kit.Blob(bird, 50, 56, 48, 64, navy, { Z = 2, Shine = true })
	kit.Blob(bird, 50, 62, 34, 46, WHITE, { Z = 3, Outline = false })
	kit.Face(bird, 50, 42, 24, { Z = 4 })
	kit.Diamond(bird, 50, 48, 6, C.Orange, 0, 5)
	kit.Part(bird, 30, 52, 40, 8, C.Pink, { Radius = 4, Z = 5 }) -- écharpe
	kit.Part(bird, 58, 56, 8, 16, C.Pink, { Radius = 3, Z = 5, Rotation = -10 })
	for _, x in ipairs({ 40, 60 }) do
		kit.Blob(bird, x, 88, 14, 6, C.Orange, { Z = 4 })
	end
	kit.Animate(bird, "Sway", 4, 1.4, 0)
	return nil
end

-- Axolotl dans son aquarium (nage de gauche à droite, bulles)
Art.Axolotl = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 176, 206)
	local tank = kit.Part(body, 6, 26, 88, 72, C.Glass, { Radius = 10, Z = 1, T = 0.2, Shine = true })
	kit.Box(tank, 0, 56, 88, 16, Color3.fromRGB(240, 214, 170), 0, 2) -- sable
	kit.Blob(tank, 16, 50, 10, 24, C.Leaf, { Z = 2 })
	kit.Blob(tank, 72, 48, 10, 28, C.LeafDark, { Z = 2 })
	local swim = kit.Group(body, 0, 0, 100, 100, 3)
	kit.Animate(swim, "Drift", 14, 0.6, 0)
	kit.Blob(swim, 56, 64, 36, 16, pink, { Z = 1, Shine = true })
	kit.Blob(swim, 76, 64, 16, 8, pink, { Z = 1 })
	local head = kit.Blob(swim, 40, 60, 26, 22, pink, { Z = 2, Shine = true })
	kit.Face(head, 13, 12, 16, { Z = 3 })
	for _, side in ipairs({ -1, 1 }) do
		for k = 0, 2 do
			kit.Blob(swim, 40 + side * (14 + k * 2), 52 + k * 5, 8, 4, C.PinkDeep, { Z = 1, Rotation = side * (20 + k * 20), Thickness = 1 })
		end
	end
	for index = 0, 2 do
		local bubble = kit.Circle(body, 30 + index * 16, 40 - index * 5, 6, 6, WHITE, 0.4, 4)
		kit.Animate(bubble, "Bob", 4, 1, index)
	end
	kit.Part(body, 2, 22, 96, 8, C.Mint, { Radius = 3, Z = 5 }) -- couvercle
	return nil
end

-- Chouette endormie sur sa branche (s'envole la nuit… et le jour !)
Art.Owl = function(body, kit, _item)
	local C = kit.C
	local brown = Color3.fromRGB(190, 150, 120)
	-- branche + petites feuilles (sa maison)
	kit.Part(body, 4, 84, 92, 10, C.WoodDark, { Radius = 5, Z = 1 })
	kit.Part(body, 44, 92, 10, 8, C.WoodDark, { Radius = 3, Z = 1 })
	kit.Blob(body, 10, 82, 14, 8, C.Leaf, { Z = 2, Rotation = -20 })
	kit.Blob(body, 90, 82, 14, 8, C.Leaf, { Z = 2, Rotation = 20 })
	local owl = kit.Pivot(body, 50, 84, 3)
	owl.Name = "Pet"
	local g = breather(owl, kit, -30, -70, 60, 70, 1)
	for _, side in ipairs({ -1, 1 }) do
		local ear = kit.Part(g, 30 + side * 16 - 6, 4, 12, 12, brown, { Radius = 3, Z = 1, Rotation = 45 })
		local _ = ear
		local wing = kit.Pivot(g, 30 + side * 22, 34, 2)
		kit.Blob(wing, side * 2, 12, 14, 30, kit.Darken(brown, 0.1), { Rotation = side * -10 })
		kit.Animate(wing, "Sway", 6, 1, side)
	end
	kit.Blob(g, 30, 40, 50, 60, brown, { Z = 3, Shine = true })
	kit.Blob(g, 30, 48, 30, 34, C.Cream, { Z = 4, Outline = false })
	for _, side in ipairs({ -1, 1 }) do
		kit.Circle(g, 30 + side * 10, 26, 18, 18, C.Cream, 0, 5)
	end
	kit.Face(g, 30, 26, 30, { Eyes = "closed", Mouth = "none", Z = 6 })
	kit.Diamond(g, 30, 33, 6, C.Orange, 0, 7)
	for _, x in ipairs({ 24, 36 }) do
		kit.Blob(g, x, 70, 8, 5, C.Orange, { Z = 7 })
	end
	kit.Animate(g, "Breathe", 0.03, 0.8, 0)
	local zzz = kit.Text(body, "z", 80, 20, 12, C.Lilac, 6)
	zzz.Name = "PetZ" -- (s'envole avec la chouette)
	kit.Animate(zzz, "Bob", 2, 0.6, 0.3)
	return nil
end

return Art
