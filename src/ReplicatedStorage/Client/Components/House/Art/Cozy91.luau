--[[
	Cozy91 (ModuleScript) — (v9.1) nouveaux meubles et déco 🛋️🖼️
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Cozy91
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au
	sol, objets muraux centrés). Les dessus où l'on pose des objets sont
	déclarés dans HouseSurfaces (coffre, étagère échelle, kotatsu, fauteuil
	cœur, canapé chat, hamac...).
]]

local Art = {}

local WHITE = Color3.new(1, 1, 1)

-- Petits pieds ronds en bois
local function feet(body, kit, xs, y, h, color)
	for _, x in ipairs(xs) do
		kit.Part(body, x - 4, y, 8, h, color, { Radius = 3, Z = 1 })
	end
end

-- Coffre à jouets : coffre rose à rayures, couvercle bombé entrouvert, jouets qui dépassent
Art.ToyChest = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 176, 206)
	feet(body, kit, { 18, 82 }, 90, 10, C.WoodDark)
	-- jouets qui dépassent
	kit.Blob(body, 30, 36, 18, 18, C.Sky, { Z = 1, Shine = true }) -- ballon
	kit.Box(body, 29, 27, 2, 18, WHITE, 0.3, 2)
	local bear = kit.Blob(body, 66, 34, 20, 18, C.Wood, { Z = 1 })
	kit.Face(bear, 10, 10, 12, { Z = 3 })
	kit.Circle(body, 58, 26, 8, 8, C.Wood, 0, 1)
	kit.Circle(body, 74, 26, 8, 8, C.Wood, 0, 1)
	local chest = kit.Part(body, 8, 44, 84, 48, pink, { Radius = 10, Z = 3, Shine = true })
	for index = 0, 3 do
		kit.Box(chest, 8 + index * 20, 0, 8, 48, WHITE, 0.55, 2)
	end
	kit.Part(body, 4, 32, 92, 16, kit.Darken(pink, 0.08), { Radius = 8, Z = 4 }) -- couvercle
	kit.Part(body, 42, 52, 16, 14, C.Butter, { Radius = 4, Z = 5 }) -- serrure
	kit.Heart(body, 50, 58, 8, C.PinkDeep, 0, 6)
	kit.Face(body, 50, 76, 22, { Eyes = "happy", Z = 6 })
	return nil
end

-- Pouf tout doux (rond, capitonné, petit pompon)
Art.Pouf = function(body, kit, _item)
	local C = kit.C
	local lilac = Color3.fromRGB(214, 190, 255)
	kit.Blob(body, 50, 76, 76, 44, lilac, { Z = 2, Shine = true, Shade = 0.16 })
	kit.Blob(body, 50, 60, 72, 22, kit.Lighten(lilac, 0.25), { Z = 3 })
	for _, x in ipairs({ 32, 50, 68 }) do
		kit.Circle(body, x, 80, 4, 4, kit.OutlineOf(lilac), 0.4, 4)
	end
	kit.Circle(body, 50, 56, 7, 7, C.Pink, 0, 4)
	kit.Face(body, 50, 78, 20, { Eyes = "closed", Z = 5 })
	return nil
end

-- Étagère échelle (3 tablettes : on y pose des objets)
Art.LadderShelf = function(body, kit, _item)
	local C = kit.C
	local wood = C.WoodLight
	kit.Line(body, 34, 4, 14, 99, 5, C.WoodDark, 0, 1)
	kit.Line(body, 66, 4, 86, 99, 5, C.WoodDark, 0, 1)
	for index, spot in ipairs({ { 26, 74, 12 }, { 18, 82, 42 }, { 10, 90, 72 } }) do
		local shelf = kit.Part(body, spot[1] - 2, spot[3], spot[2] - spot[1] + 4, 6, wood, { Radius = 2, Z = 2 })
		local _ = shelf
		-- petits pompons de décor sous les tablettes
		kit.Circle(body, spot[1] + 4, spot[3] + 9, 4, 4, index == 2 and C.Pink or C.Mint, 0, 2)
	end
	kit.Heart(body, 50, 92, 10, C.Pink, 0, 3)
	return nil
end

-- Table kotatsu (couette à carreaux, plateau en bois, clémentines)
Art.KotatsuTable = function(body, kit, _item)
	local C = kit.C
	local quilt = Color3.fromRGB(255, 196, 150)
	kit.Part(body, 2, 42, 96, 8, C.Wood, { Radius = 3, Z = 3, Shine = true }) -- plateau
	local blanket = kit.Part(body, 6, 48, 88, 48, quilt, { Radius = 12, Z = 2, Shade = 0.18 })
	for index = 0, 3 do
		kit.Box(blanket, 0, 8 + index * 11, 88, 3, C.Red, 0.55, 2)
	end
	for index = 0, 4 do
		kit.Box(blanket, 8 + index * 18, 0, 3, 48, C.Red, 0.55, 2)
	end
	kit.Blob(body, 12, 94, 18, 10, quilt, { Z = 2 }) -- coin qui retombe
	kit.Blob(body, 88, 94, 18, 10, quilt, { Z = 2 })
	kit.Face(body, 50, 72, 22, { Eyes = "closed", Z = 4 })
	return nil
end

-- Fauteuil cœur (dossier en cœur rose, coussin, pieds dorés)
Art.HeartArmchair = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 140, 186)
	feet(body, kit, { 22, 78 }, 88, 12, C.Gold)
	kit.Heart(body, 50, 38, 84, kit.OutlineOf(pink), 0, 1)
	kit.Heart(body, 50, 38, 78, pink, 0, 2)
	kit.Shine(body, 24, 18, 14, 6, 3, 0.4)
	local seat = kit.Part(body, 14, 62, 72, 28, kit.Lighten(pink, 0.15), { Radius = 12, Z = 4, Shine = true })
	kit.Part(seat, 6, 2, 60, 10, kit.Lighten(pink, 0.45), { Radius = -1, Z = 2 })
	for _, x in ipairs({ 6, 76 }) do
		kit.Part(body, x, 50, 18, 40, kit.Darken(pink, 0.06), { Radius = 9, Z = 5 })
	end
	kit.Heart(body, 50, 76, 12, WHITE, 0, 5)
	return nil
end

-- Hamac à rayures entre deux poteaux, qui se balance doucement
Art.Hammock = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 6, 20, 8, 80, C.WoodDark, { Radius = 3, Z = 1 })
	kit.Part(body, 86, 20, 8, 80, C.WoodDark, { Radius = 3, Z = 1 })
	kit.Blob(body, 10, 18, 12, 8, C.Leaf, { Z = 2 })
	kit.Blob(body, 90, 18, 12, 8, C.Leaf, { Z = 2 })
	local swing = kit.Pivot(body, 50, 28, 3)
	kit.Animate(swing, "Sway", 3, 0.5, 0.2)
	kit.Line(swing, -40, 0, -26, 30, 2, C.Brown, 0, 1)
	kit.Line(swing, 40, 0, 26, 30, 2, C.Brown, 0, 1)
	local bed = kit.Part(swing, -34, 24, 68, 24, C.Mint, { Radius = 12, Z = 2, Shade = 0.2 })
	for index = 0, 3 do
		kit.Box(bed, 4 + index * 16, 0, 7, 24, C.Butter, 0.25, 2)
	end
	kit.Blob(swing, -20, 30, 18, 12, C.PinkSoft, { Z = 3, Shine = true }) -- coussin
	kit.Heart(swing, -20, 30, 8, C.Pink, 0, 4)
	return nil
end

-- Canapé chat (oreilles, moustaches, pattes, queue)
Art.CatSofa = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(255, 214, 180)
	feet(body, kit, { 16, 84 }, 90, 10, C.WoodDark)
	-- oreilles
	for _, side in ipairs({ -1, 1 }) do
		local ear = kit.Part(body, 50 + side * 26 - 10, 6, 20, 20, fur, { Radius = 5, Z = 1, Rotation = 45 })
		kit.Part(ear, 5, 5, 10, 10, C.Pink, { Radius = 3, Z = 2, Outline = false, Shade = false })
	end
	local back = kit.Part(body, 10, 16, 80, 54, fur, { Radius = 28, Z = 2, Shine = true })
	kit.Face(back, 40, 22, 26, { Mouth = "cat", Z = 3 })
	for _, side in ipairs({ -1, 1 }) do
		for k = 0, 1 do
			kit.Line(back, 40 + side * 16, 26 + k * 4, 40 + side * 30, 24 + k * 7, 1.2, kit.OutlineOf(fur), 0.2, 3)
		end
	end
	local seat = kit.Part(body, 8, 62, 84, 28, kit.Lighten(fur, 0.2), { Radius = 12, Z = 4, Shine = true })
	local _ = seat
	-- pattes (accoudoirs)
	for _, x in ipairs({ 2, 78 }) do
		local paw = kit.Part(body, x, 50, 20, 40, fur, { Radius = 10, Z = 5 })
		for toe = 0, 2 do
			kit.Circle(paw, 5 + toe * 5, 34, 4, 4, C.Pink, 0.2, 2)
		end
	end
	local tail = kit.Pivot(body, 90, 70, 0)
	kit.Blob(tail, 4, -14, 10, 30, fur, { Rotation = 20 })
	kit.Animate(tail, "Sway", 8, 0.6, 0.5)
	return nil
end

-- Trône de cristal (dossier en éventail de cristaux, coussin royal)
Art.CrystalThrone = function(body, kit, _item)
	local C = kit.C
	local crystal = Color3.fromRGB(196, 226, 255)
	local lilac = Color3.fromRGB(214, 190, 255)
	for index = -3, 3 do
		local h = 60 - math.abs(index) * 8
		local shard = kit.Part(body, 50 + index * 11 - 6, 64 - h, 12, h, index % 2 == 0 and crystal or lilac, { Radius = 5, Z = 1 + (3 - math.abs(index)), Shine = true })
		local _ = shard
		kit.Diamond(body, 50 + index * 11, 64 - h, 12, index % 2 == 0 and crystal or lilac, 0, 1 + (3 - math.abs(index)))
	end
	kit.Part(body, 16, 58, 68, 30, C.Gold, { Radius = 10, Z = 6, Shine = true })
	kit.Part(body, 20, 54, 60, 16, C.PinkSoft, { Radius = -1, Z = 7, Shine = true })
	for _, x in ipairs({ 10, 74 }) do
		kit.Part(body, x, 50, 16, 40, crystal, { Radius = 8, Z = 8, Shine = true })
	end
	feet(body, kit, { 22, 78 }, 88, 12, C.Gold)
	kit.Heart(body, 50, 76, 12, C.Heart, 0, 8)
	for index, spot in ipairs({ { 20, 10 }, { 82, 16 }, { 50, 2 } }) do
		local sparkle = kit.Sparkle(body, spot[1], spot[2], 12, WHITE, 0, 9)
		kit.Animate(sparkle, "Pulse", 0.7, 1.3, index)
	end
	return { Glow = Color3.fromRGB(200, 220, 255) }
end

-- Tapis cœur (à plat, bordure festonnée)
Art.HeartRug = function(body, kit, _item)
	local C = kit.C
	local flat = kit.Group(body, 0, 60, 100, 40, 1)
	kit.Blob(flat, 50, 20, 96, 38, C.Pink, { Z = 1, Shade = false })
	kit.Blob(flat, 50, 20, 84, 30, C.PinkSoft, { Z = 2, Outline = false, Shade = false })
	kit.Heart(flat, 50, 20, 26, C.Heart, 0, 3)
	for index = 0, 6 do
		kit.Circle(flat, 14 + index * 12, 36, 6, 4, WHITE, 0.2, 3)
	end
	return { Flat = true }
end

-- Guirlande d'étoiles (fil qui ondule, étoiles qui scintillent)
Art.StarGarland = function(body, kit, _item)
	local C = kit.C
	local bulbs = {}
	local colors = { C.Butter, C.Pink, C.Sky, C.Lilac, C.Mint }
	for index = 0, 6 do
		local x = 6 + index * 14.6
		local y = 38 + math.sin(index / 6 * math.pi) * 18
		if index > 0 then
			local px = 6 + (index - 1) * 14.6
			local py = 38 + math.sin((index - 1) / 6 * math.pi) * 18
			kit.Line(body, px, py, x, y, 1.5, C.GreyDark, 0, 1)
		end
		local color = colors[index % #colors + 1]
		local halo = kit.Circle(body, x, y + 10, 20, 20, color, 0.6, 1)
		local star = kit.Sparkle(body, x, y + 10, 16, color, 0, 2)
		kit.Diamond(body, x, y + 10, 8, WHITE, 0.3, 3)
		star:SetAttribute("Phase", index * 1.1)
		local core = star:FindFirstChildWhichIsA("Frame")
		if core then
			core:SetAttribute("Phase", index * 1.1)
			table.insert(bulbs, core)
			table.insert(bulbs, halo)
		end
	end
	return { Bulbs = bulbs, WallShadow = Vector2.new(0, 0) }
end

-- Horloge chat (tête de chat, yeux qui suivent le balancier-queue)
Art.KittyClock = function(body, kit, _item)
	local C = kit.C
	local black = Color3.fromRGB(96, 84, 120)
	for _, side in ipairs({ -1, 1 }) do
		local ear = kit.Part(body, 50 + side * 20 - 9, 10, 18, 18, black, { Radius = 4, Z = 1, Rotation = 45 })
		kit.Part(ear, 4, 4, 10, 10, C.Pink, { Radius = 3, Z = 2, Outline = false, Shade = false })
	end
	local head = kit.Blob(body, 50, 38, 60, 50, black, { Z = 2, Shine = true })
	local dial = kit.Blob(head, 30, 28, 34, 34, C.Cream, { Z = 2 })
	for index = 0, 3 do
		local a = index * math.pi / 2
		kit.Circle(dial, 17 + math.sin(a) * 12, 17 - math.cos(a) * 12, 3, 3, C.Ink, 0, 3)
	end
	local hands = kit.Pivot(dial, 17, 17, 4)
	kit.Box(hands, -1, -11, 2, 11, C.Ink, 0, 1)
	kit.Box(hands, -1, -1, 8, 2, C.Ink, 0, 1)
	kit.Animate(hands, "Spin", 1, 0.05, 0)
	kit.Circle(dial, 17, 17, 4, 4, C.Pink, 0, 5)
	kit.Face(head, 30, 12, 26, { Mouth = "none", Color = C.Butter, Z = 4 })
	local tail = kit.Pivot(body, 50, 60, 1)
	kit.Blob(tail, 0, 18, 10, 36, black, { Z = 1 })
	kit.Circle(tail, 0, 34, 12, 12, C.Pink, 0, 2)
	kit.Animate(tail, "Sway", 14, 1.4, 0)
	return { WallShadow = Vector2.new(0.6, 0.7) }
end

-- Tapisserie arc-en-ciel (tissage à franges sur un bâton)
Art.Tapestry = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 14, 14, 86, 14, 5, C.WoodDark, 0, 3)
	kit.Line(body, 40, 14, 50, 4, 1.5, C.Brown, 0, 1)
	kit.Line(body, 60, 14, 50, 4, 1.5, C.Brown, 0, 1)
	local cloth = kit.Part(body, 20, 14, 60, 62, C.Cream, { Radius = 4, Z = 2 })
	local colors = { C.Red, C.Orange, C.Yellow, C.Leaf, C.Sky, C.Lilac }
	for index, color in ipairs(colors) do
		local arc = kit.Circle(cloth, 30, 56, 56 - index * 7, 56 - index * 7, color, 1, 2)
		kit.Stroke(arc, color, 3.2, 0)
	end
	kit.Box(cloth, 0, 56, 60, 6, C.Cream, 0, 3)
	kit.Cloud(cloth, 12, 58, 18, WHITE, 0, 4)
	kit.Cloud(cloth, 48, 58, 18, WHITE, 0, 4)
	for index = 0, 9 do
		kit.Line(body, 23 + index * 6, 76, 23 + index * 6, 88 + (index % 2) * 3, 2, colors[index % #colors + 1], 0, 1)
	end
	return { WallShadow = Vector2.new(0.6, 0.75) }
end

-- Papillons encadrés (cadre doré, trois papillons qui battent des ailes)
Art.ButterflyFrame = function(body, kit, _item)
	local C = kit.C
	local frame = kit.Part(body, 12, 16, 76, 68, C.Gold, { Radius = 8, Z = 1, Shine = true })
	kit.Part(frame, 6, 6, 64, 56, C.MintSoft, { Radius = 5, Z = 2, Outline = false })
	for index, b in ipairs({ { 34, 36, C.Pink }, { 62, 30, C.Sky }, { 50, 60, C.Butter } }) do
		local fly = kit.Pivot(body, b[1], b[2], 3)
		for _, side in ipairs({ -1, 1 }) do
			local wing = kit.Blob(fly, side * 6, -3, 12, 14, b[3], { Z = 1, Thickness = 1.2 })
			kit.Circle(wing, 6, 6, 4, 4, WHITE, 0.3, 2)
			kit.Blob(fly, side * 5, 6, 8, 8, kit.Darken(b[3], 0.1), { Z = 1, Thickness = 1.2 })
		end
		kit.Part(fly, -1.5, -8, 3, 18, C.Ink, { Radius = 1, Z = 2, Outline = false, Shade = false })
		kit.Animate(fly, "Breathe", 0.08, 2, index)
	end
	return { WallShadow = Vector2.new(0.76, 0.7) }
end

-- Tapis nuage (à plat, tout doux, petites étoiles)
Art.CloudRug = function(body, kit, _item)
	local C = kit.C
	local flat = kit.Group(body, 0, 58, 100, 42, 1)
	local sky = Color3.fromRGB(214, 236, 255)
	for _, b in ipairs({ { 24, 24, 40 }, { 50, 18, 50 }, { 76, 24, 40 }, { 50, 28, 90 } }) do
		kit.Blob(flat, b[1], b[2], b[3], b[3] * 0.5, sky, { Z = 1, Shade = false, Thickness = 1.4 })
	end
	for _, b in ipairs({ { 24, 24, 34 }, { 50, 18, 44 }, { 76, 24, 34 }, { 50, 28, 82 } }) do
		kit.Blob(flat, b[1], b[2], b[3], b[3] * 0.44, WHITE, { Z = 2, Outline = false, Shade = false })
	end
	for index, x in ipairs({ 30, 52, 72 }) do
		kit.Sparkle(flat, x, 24 + (index % 2) * 4, 8, C.Butter, 0, 3)
	end
	return { Flat = true }
end

-- Mannequin de couture (robe rose en cours, mètre ruban, épingles)
Art.Mannequin = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 50, 70, 50, 94, 3, C.WoodDark, 0, 1)
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(body, 50, 92, 50 + side * 18, 99, 3, C.WoodDark, 0, 1)
	end
	kit.Blob(body, 50, 6, 10, 8, C.WoodDark, { Z = 1 })
	local torso = kit.Part(body, 32, 8, 36, 40, C.Cream, { Radius = 14, Z = 2, Shine = true })
	local _ = torso
	-- robe
	kit.Part(body, 34, 26, 32, 18, C.Pink, { Radius = 6, Z = 3 })
	kit.Triangle(body, 50, 38, 56, 38, C.Pink, 3)
	for index = 0, 3 do
		kit.Circle(body, 30 + index * 13, 76, 12, 8, C.PinkSoft, 0, 4)
	end
	kit.Heart(body, 50, 32, 10, WHITE, 0, 4)
	-- mètre ruban
	kit.Line(body, 34, 14, 56, 44, 2.5, C.Butter, 0, 5)
	kit.Line(body, 56, 44, 60, 60, 2.5, C.Butter, 0, 5)
	for index = 0, 2 do
		kit.Circle(body, 60 + index * 4, 18 + index * 3, 3, 3, C.Red, 0, 5)
	end
	return nil
end

-- Harpe dorée (cordes qui vibrent, notes de musique)
Art.Harp = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 22, 88, 56, 12, C.Gold, { Radius = 5, Z = 1 })
	kit.Line(body, 26, 90, 26, 22, 7, C.Gold, 0, 2)
	kit.Line(body, 26, 22, 78, 40, 7, C.Gold, 0, 2)
	kit.Line(body, 78, 40, 72, 90, 8, kit.Darken(C.Gold, 0.1), 0, 2)
	kit.Blob(body, 26, 18, 14, 14, C.Gold, { Z = 3, Shine = true })
	kit.Heart(body, 26, 18, 8, C.Pink, 0, 4)
	for index = 0, 6 do
		local x = 32 + index * 6
		local top = 24 + index * 2.4
		local string = kit.Line(body, x, top, x, 86, 1.4, Color3.fromRGB(255, 236, 190), 0, 1)
		kit.Animate(string, "Drift", 0.6, 3, index)
	end
	for index, note in ipairs({ { 86, 24 }, { 12, 44 } }) do
		local label = kit.Text(body, index == 1 and "♪" or "♫", note[1], note[2], 14, C.PinkDeep, 5)
		kit.Animate(label, "Bob", 3, 0.8, index)
	end
	return { Glow = Color3.fromRGB(255, 230, 160) }
end

-- Statue de cygne (marbre, couronne, sur un socle)
Art.SwanStatue = function(body, kit, _item)
	local C = kit.C
	local marble = Color3.fromRGB(250, 248, 255)
	kit.Part(body, 18, 84, 64, 16, Color3.fromRGB(226, 220, 244), { Radius = 5, Z = 1, Shine = true })
	kit.Blob(body, 56, 68, 56, 30, marble, { Z = 2, Shine = true })
	kit.Blob(body, 66, 60, 34, 22, kit.Darken(marble, 0.04), { Z = 3, Rotation = -20 }) -- aile
	kit.Line(body, 34, 64, 32, 30, 9, marble, 0, 3)
	kit.Blob(body, 36, 26, 18, 14, marble, { Z = 4, Shine = true })
	kit.Circle(body, 38, 24, 3, 3, C.Ink, 0, 5)
	kit.Part(body, 22, 26, 10, 6, C.Orange, { Radius = 3, Z = 5, Rotation = -12 })
	kit.Circle(body, 42, 28, 5, 3, C.Blush, 0.3, 5)
	for index = -1, 1 do
		kit.Diamond(body, 36 + index * 5, 16, 5, C.Gold, 0, 5)
	end
	local sparkle = kit.Sparkle(body, 80, 40, 12, C.Butter, 0, 6)
	kit.Animate(sparkle, "Pulse", 0.6, 1, 0.4)
	return nil
end

-- Couronne sur un coussin de velours (brille)
Art.CrownCushion = function(body, kit, _item)
	local C = kit.C
	local velvet = Color3.fromRGB(200, 110, 190)
	kit.Blob(body, 50, 84, 84, 30, velvet, { Z = 1, Shine = true })
	for _, x in ipairs({ 10, 90 }) do
		kit.Circle(body, x, 90, 10, 10, C.Gold, 0, 2) -- glands
	end
	local crown = kit.Group(body, 0, 0, 100, 100, 3)
	kit.Animate(crown, "Bob", 1.5, 0.8, 0)
	kit.Part(crown, 24, 52, 52, 20, C.Gold, { Radius = 4, Z = 1, Shine = true })
	for index = 0, 2 do
		kit.Triangle(crown, 30 + index * 20, 32, 18, 24, C.Gold, 1)
		kit.Circle(crown, 30 + index * 20, 32, 7, 7, index == 1 and C.Pink or C.Sky, 0, 2)
	end
	for index, color in ipairs({ C.Red, C.Sky, C.Mint }) do
		kit.Diamond(crown, 34 + (index - 1) * 16, 62, 8, color, 0, 2)
	end
	for index, spot in ipairs({ { 16, 30 }, { 86, 40 } }) do
		local sparkle = kit.Sparkle(body, spot[1], spot[2], 12, WHITE, 0, 5)
		kit.Animate(sparkle, "Pulse", 0.7, 1.2, index)
	end
	return { Glow = Color3.fromRGB(255, 226, 150) }
end

return Art
