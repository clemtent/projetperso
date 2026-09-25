--[[
	Furniture (ModuleScript) — dessins des meubles 🛋️
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Furniture
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

----------------------------------------------------------------------
-- Petits outils partagés
----------------------------------------------------------------------

-- Flamme (goutte : ovale en bas + pointe arrondie) ; `bottom` = y du bas ; vacille
local function flame(kit, parent, cx, bottom, w, h, color, z, phase)
	local holder = kit.Group(parent, cx - w / 2, bottom - h, w, h, z)
	local bulbH = math.min(h * 0.62, w * 1.05)
	kit.Circle(holder, w / 2, h - bulbH / 2, w, bulbH, color, 0, 1)
	local side = w * 0.62
	local tip = kit.Box(holder, 0, 0, side, side, color, 0, 1)
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromOffset(w / 2, side * 0.71)
	tip.Rotation = 45
	kit.Round(tip, side * 0.22)
	local stretch = h - bulbH / 2 - side * 0.71
	if stretch > side * 0.5 then
		-- flamme haute : on relie la pointe au bas par un ovale étroit
		kit.Circle(holder, w / 2, (side * 0.71 + h - bulbH / 2) / 2, side * 0.95, stretch + side * 0.4, color, 0, 1)
	end
	kit.Animate(holder, "Flicker", 0, 1, phase)
	return holder
end

-- Canard en plastique (regarde à droite) ; (cx, bottom) = milieu du bas
local function duck(kit, parent, cx, bottom, size, z)
	local C = kit.C
	local s = size / 20
	local holder = kit.Group(parent, cx - 10 * s, bottom - 18 * s, 20 * s, 18 * s, z)
	kit.Blob(holder, 9 * s, 12.5 * s, 18 * s, 11 * s, C.Yellow, { Z = 1 })
	kit.Blob(holder, 13 * s, 5.5 * s, 10 * s, 10 * s, C.Yellow, { Z = 2, Shine = true })
	kit.Blob(holder, 19 * s, 7 * s, 5 * s, 3 * s, C.Orange, { Z = 3, Thickness = 1 })
	kit.Circle(holder, 14.5 * s, 4.5 * s, 2 * s, 2.2 * s, C.Ink, 0, 3)
	kit.Blob(holder, 6.5 * s, 11 * s, 7 * s, 4.5 * s, kit.Lighten(C.Yellow, 0.35), { Z = 2, Outline = false, Shade = false })
	return holder
end

-- Paire de pieds de meuble
local function feet(kit, body, xs, top, w, h, color, z)
	for _, x in ipairs(xs) do
		kit.Part(body, x, top, w, h, color, { Radius = 2, Z = z or 1 })
	end
end

----------------------------------------------------------------------
-- Meubles
----------------------------------------------------------------------

-- Chaise en bois : dossier à barreaux avec un cœur, coussin rose
Art.WoodenChair = function(body, kit, _item)
	local C = kit.C
	feet(kit, body, { 28, 66 }, 64, 6, 34, C.WoodDark, 1) -- pieds arrière
	for _, x in ipairs({ 20, 72 }) do
		kit.Part(body, x, 10, 8, 56, C.Wood, { Radius = 3, Z = 2 }) -- montants
	end
	for _, x in ipairs({ 36, 47, 58 }) do
		kit.Part(body, x, 20, 6, 34, C.WoodLight, { Radius = 3, Z = 2 }) -- barreaux
	end
	local top = kit.Part(body, 15, 5, 70, 17, C.WoodLight, { Radius = 8, Z = 3, Shine = true })
	kit.Heart(top, 35, 9, 10, C.Pink, 0, 4)
	kit.Part(body, 10, 58, 80, 11, C.WoodLight, { Radius = 5, Z = 4 }) -- assise
	local cushion = kit.Part(body, 15, 50, 70, 12, C.PinkSoft, { Radius = -1, Z = 5, Shine = true })
	for _, x in ipairs({ 22, 35, 48 }) do
		kit.Circle(cushion, x, 6, 2.2, 2.2, C.Pink, 0.2, 4) -- points de couture
	end
	kit.Part(body, 22, 84, 56, 4, C.WoodDark, { Radius = 2, Z = 2 }) -- barreau bas
	feet(kit, body, { 13, 79 }, 66, 8, 34, C.Wood, 3) -- pieds avant
	return nil
end

-- Carton de rangement ouvert : rabats, jouets qui dépassent, petit visage
Art.StorageBox = function(body, kit, _item)
	local C = kit.C
	local kraft = Color3.fromRGB(236, 190, 140)
	kit.Part(body, 0, 36, 34, 12, kit.Darken(kraft, 0.06), { Radius = 3, Z = 1, Rotation = -22 })
	kit.Part(body, 66, 36, 34, 12, kit.Darken(kraft, 0.06), { Radius = 3, Z = 1, Rotation = 22 })
	kit.Part(body, 12, 38, 76, 14, kit.Darken(kraft, 0.3), { Radius = 3, Z = 1, Shade = false }) -- intérieur
	kit.Blob(body, 34, 40, 22, 22, C.Pink, { Z = 2, Shine = true }) -- balle
	local block = kit.Part(body, 54, 30, 18, 18, C.Sky, { Radius = 4, Z = 2, Rotation = 12 })
	kit.Text(block, "A", 9, 9, 11, C.White, 3)
	kit.Line(body, 76, 46, 82, 24, 3, C.Lilac, 0, 2) -- baguette
	kit.Sparkle(body, 83, 22, 12, C.Yellow, 0, 3)
	local front = kit.Part(body, 8, 46, 84, 52, kraft, { Radius = 6, Z = 4, Shade = 0.16, Shine = true })
	kit.Box(front, 36, 0, 12, 52, kit.Lighten(kraft, 0.35), 0.1, 2) -- scotch
	kit.Face(front, 42, 28, 30, { Eyes = "dot", Mouth = "cat", Z = 4 })
	kit.Heart(front, 72, 40, 9, C.PinkDeep, 0, 3)
	return nil
end

-- Échelle en bois avec un plaid rayé posé sur un barreau
Art.Ladder = function(body, kit, _item)
	local C = kit.C
	local function leftX(y)
		return 30 + (99 - y) / 96 * 9
	end
	local function rightX(y)
		return 70 - (99 - y) / 96 * 9
	end
	for _, y in ipairs({ 16, 38, 60, 82 }) do
		local x1, x2 = leftX(y), rightX(y)
		kit.Part(body, x1, y - 3, x2 - x1, 6, C.WoodLight, { Radius = 3, Z = 1 })
	end
	for _, rail in ipairs({ { 30, 39 }, { 70, 61 } }) do
		local frame = kit.Line(body, rail[1], 97, rail[2], 4, 7, C.Wood, 0, 2)
		kit.Stroke(frame, kit.OutlineOf(C.Wood), 1.6)
		kit.Gradient(frame, C.White, Color3.new(0.88, 0.88, 0.88), 0)
		kit.Part(body, rail[1] - 4.5, 94, 9, 6, C.WoodDark, { Radius = 2, Z = 3 }) -- patins
	end
	-- plaid
	local blanket = kit.Part(body, 32, 34, 36, 40, C.PinkSoft, { Radius = 5, Z = 4, Shine = true })
	for _, y in ipairs({ 14, 26 }) do
		kit.Box(blanket, 0, y, 36, 4, C.Pink, 0.1, 2)
	end
	for index = 0, 4 do
		kit.Line(body, 36 + index * 7, 74, 36 + index * 7, 79, 2, C.Pink, 0, 3) -- franges
	end
	local fold = kit.Part(body, 30, 31, 40, 9, kit.Lighten(C.PinkSoft, 0.3), { Radius = -1, Z = 5 })
	kit.Heart(fold, 20, 4.5, 6, C.PinkDeep, 0, 3)
	return nil
end

-- Table de chevet lilas : tiroir à lune, veilleuse lune endormie
Art.Nightstand = function(body, kit, _item)
	local C = kit.C
	local lilac = Color3.fromRGB(214, 196, 250)
	feet(kit, body, { 18, 76 }, 88, 6, 12, C.WoodDark, 1)
	local cabinet = kit.Part(body, 14, 50, 72, 42, lilac, { Radius = 6, Z = 2 })
	for index, y in ipairs({ 6, 23 }) do
		local drawer = kit.Part(cabinet, 6, y, 60, 14, kit.Lighten(lilac, 0.45), { Radius = 4, Z = 2 })
		if index == 1 then
			kit.Circle(drawer, 30, 7, 9, 9, C.Butter, 0, 2) -- lune (croissant)
			kit.Circle(drawer, 33, 5.5, 8, 8, kit.Lighten(lilac, 0.45), 0, 3)
		else
			kit.Blob(drawer, 30, 7, 10, 5, C.Gold, { Z = 2, Thickness = 1 })
		end
	end
	kit.Part(body, 8, 44, 84, 9, C.WoodLight, { Radius = 4, Z = 3, Shine = true }) -- plateau
	-- veilleuse
	kit.Part(body, 43, 38, 14, 7, C.Wood, { Radius = 3, Z = 2 })
	local moon = kit.Blob(body, 50, 24, 28, 28, C.Butter, { Z = 3, Shine = true })
	kit.Circle(moon, 21, 18, 5, 5, kit.Darken(C.Butter, 0.08), 0, 2)
	kit.Circle(moon, 7, 20, 3, 3, kit.Darken(C.Butter, 0.08), 0, 2)
	kit.Face(moon, 14, 15, 16, { Eyes = "closed", Mouth = "smile", Z = 3 })
	kit.Sparkle(body, 76, 22, 9, C.Butter, 0, 4)
	kit.Sparkle(body, 24, 30, 6, C.White, 0, 4)
	return { Glow = C.Butter }
end

-- Valise de voyage menthe : poignée, sangles, autocollants, roulettes
Art.Suitcase = function(body, kit, _item)
	local C = kit.C
	local mint = Color3.fromRGB(150, 222, 196)
	kit.Part(body, 38, 14, 24, 18, C.Brown, { Radius = 7, Z = 1, T = 1, Outline = C.Brown, Thickness = 4, Shade = false })
	for _, x in ipairs({ 24, 72 }) do
		kit.Circle(body, x, 95, 8, 8, C.GreyDark, 0, 1)
	end
	local case = kit.Part(body, 14, 26, 72, 68, mint, { Radius = 12, Z = 2, Shine = true, Shade = 0.16 })
	kit.Box(case, 0, 30, 72, 3, kit.Darken(mint, 0.15), 0, 2) -- fermeture
	for _, x in ipairs({ 13, 52 }) do
		local strap = kit.Part(case, x, -1, 7, 70, C.Brown, { Radius = 2, Z = 3 })
		kit.Part(strap, -1, 36, 9, 7, C.Gold, { Radius = 2, Z = 2, Thickness = 1 })
	end
	local sticker = kit.Blob(case, 36, 17, 18, 18, C.PinkSoft, { Z = 4, Thickness = 1.2 })
	kit.Heart(sticker, 9, 9, 10, C.Pink, 0, 2)
	local star = kit.Part(case, 25, 44, 18, 13, C.Butter, { Radius = 3, Z = 4, Thickness = 1.2, Rotation = -10 })
	kit.Sparkle(star, 9, 6.5, 10, C.Orange, 0, 2)
	kit.Circle(case, 36, 63, 6, 4, C.White, 0.5, 4)
	return nil
end

-- Toilettes royales : couronne dorée, lunette rose, petit visage
Art.Toilet = function(body, kit, _item)
	local C = kit.C
	local porcelain = Color3.fromRGB(250, 250, 255)
	local tank = kit.Part(body, 26, 20, 48, 34, porcelain, { Radius = 7, Z = 1, Shine = true })
	kit.Blob(tank, 36, 12, 7, 7, C.Gold, { Z = 2, Thickness = 1 }) -- bouton chasse
	kit.Heart(tank, 24, 20, 9, C.Pink, 0, 2)
	kit.Part(body, 22, 16, 56, 8, porcelain, { Radius = 4, Z = 2 }) -- couvercle
	-- couronne
	for _, x in ipairs({ 40, 50, 60 }) do
		kit.Part(body, x - 4.5, 5, 9, 9, C.Gold, { Radius = 2, Z = 2, Rotation = 45, Thickness = 1.2 })
		kit.Circle(body, x, 3, 4, 4, C.Butter, 0, 3)
	end
	local band = kit.Part(body, 35, 10, 30, 7, C.Gold, { Radius = 2, Z = 3, Thickness = 1.2 })
	kit.Diamond(band, 15, 3.5, 3.5, C.Heart, 0, 2)
	-- cuvette + pied
	kit.Part(body, 36, 76, 28, 20, porcelain, { Radius = 6, Z = 3 })
	local bowl = kit.Part(body, 14, 58, 72, 26, porcelain, { Radius = 13, Z = 4 })
	kit.Face(bowl, 36, 12, 22, { Eyes = "happy", Mouth = "smile", Z = 3 })
	kit.Blob(body, 50, 58, 82, 14, C.PinkSoft, { Z = 5, Shine = true }) -- lunette
	kit.Part(body, 30, 93, 40, 7, C.Gold, { Radius = 3, Z = 4, Thickness = 1.2, Shine = true }) -- socle doré
	return nil
end

-- Commode aux tiroirs pastel arc-en-ciel, cactus et cadre photo
Art.DrawerCabinet = function(body, kit, _item)
	local C = kit.C
	feet(kit, body, { 16, 78 }, 90, 6, 10, C.WoodDark, 1)
	local cabinet = kit.Part(body, 10, 28, 80, 64, C.Cream, { Radius = 6, Z = 2 })
	local colors = { C.PinkSoft, Color3.fromRGB(255, 236, 180), C.MintSoft, C.LilacSoft }
	for index, color in ipairs(colors) do
		local drawer = kit.Part(cabinet, 5, 4 + (index - 1) * 15, 70, 12, color, { Radius = 4, Z = 2, Thickness = 1.3 })
		kit.Blob(drawer, 35, 6, 9, 5, kit.Darken(color, 0.2), { Z = 2, Thickness = 1 })
	end
	kit.Part(body, 6, 24, 88, 8, C.WoodLight, { Radius = 4, Z = 3, Shine = true }) -- plateau
	-- cactus
	local cactus = kit.Blob(body, 26, 12, 12, 20, C.Leaf, { Z = 4 })
	kit.Face(cactus, 6, 8, 10, { Eyes = "dot", Mouth = "none", Z = 3 })
	kit.Blob(body, 19, 12, 5, 9, C.Leaf, { Z = 3 })
	kit.Circle(body, 26, 2.5, 4, 4, C.Pink, 0, 5)
	kit.Part(body, 18, 17, 16, 9, C.Orange, { Radius = 2, Z = 5 })
	-- cadre photo
	local frame = kit.Part(body, 56, 4, 24, 21, C.Wood, { Radius = 3, Z = 4, Rotation = 4 })
	local photo = kit.Part(frame, 3.5, 3.5, 17, 14, C.Sky, { Radius = 2, Z = 2, Outline = false, Shade = false })
	kit.Heart(photo, 8.5, 7, 8, C.Pink, 0, 2)
	return nil
end

-- Lit mezzanine : lit en hauteur, échelle, guirlande et petit bureau dessous
Art.LoftBed = function(body, kit, _item)
	local C = kit.C
	local frameColor = Color3.fromRGB(245, 235, 250)
	for _, x in ipairs({ 5, 87 }) do
		kit.Part(body, x, 6, 8, 94, frameColor, { Radius = 3, Z = 5 }) -- montants
	end
	kit.Part(body, 2, 42, 96, 9, C.WoodLight, { Radius = 3, Z = 4 }) -- sommier
	kit.Part(body, 10, 32, 80, 12, C.White, { Radius = 5, Z = 2 }) -- matelas
	local blanket = kit.Part(body, 36, 27, 54, 17, C.Lilac, { Radius = 6, Z = 3, Shine = true })
	for _, p in ipairs({ { 14, 10 }, { 28, 7 }, { 42, 11 } }) do
		kit.Heart(blanket, p[1], p[2], 6, C.LilacSoft, 0, 2)
	end
	local pillow = kit.Blob(body, 24, 29, 24, 13, C.PinkSoft, { Z = 3, Shine = true })
	kit.Heart(pillow, 16, 7, 5, C.Pink, 0, 2)
	-- garde-corps
	kit.Part(body, 5, 18, 50, 5, frameColor, { Radius = 2, Z = 6 })
	for _, x in ipairs({ 36, 51 }) do
		kit.Part(body, x, 22, 4, 22, frameColor, { Radius = 2, Z = 6 })
	end
	-- guirlande lumineuse sous le lit
	kit.Line(body, 14, 54, 86, 54, 1.2, C.GreyDark, 0.3, 2)
	local bulbs = { C.Butter, C.Pink, C.Mint, C.Sky, C.Butter, C.Pink }
	for index, color in ipairs(bulbs) do
		local bulb = kit.Circle(body, 18 + (index - 1) * 12, 57, 5, 6, color, 0, 3)
		kit.Animate(bulb, "Pulse", 0.4, 1, index * 1.3)
	end
	-- petit bureau
	kit.Part(body, 16, 74, 42, 5, C.Wood, { Radius = 2, Z = 3 })
	feet(kit, body, { 19, 51 }, 78, 4, 22, C.WoodDark, 2)
	local screen = kit.Part(body, 22, 63, 17, 11, C.Sky, { Radius = 2, Z = 3 }) -- écran
	kit.Heart(screen, 8.5, 5.5, 6, C.White, 0, 2)
	kit.Part(body, 28, 70, 4, 5, C.GreyDark, { Radius = 1, Z = 2, Outline = false })
	kit.Blob(body, 49, 70, 8, 8, C.Pink, { Z = 3 }) -- tasse
	-- échelle
	for _, x in ipairs({ 66, 80 }) do
		kit.Part(body, x, 44, 4, 56, C.Wood, { Radius = 2, Z = 7 })
	end
	for _, y in ipairs({ 58, 72, 86 }) do
		kit.Part(body, 67, y, 16, 4, C.WoodLight, { Radius = 2, Z = 6 })
	end
	return nil
end

-- Bureau d'étude : lampe articulée, livres, pot à crayons, pomme
Art.StudyDesk = function(body, kit, _item)
	local C = kit.C
	-- caisson + pied
	local pedestal = kit.Part(body, 8, 54, 32, 44, C.Cream, { Radius = 4, Z = 1 })
	for _, y in ipairs({ 5, 23 }) do
		local drawer = kit.Part(pedestal, 4, y, 24, 15, C.MintSoft, { Radius = 3, Z = 2, Thickness = 1.3 })
		kit.Blob(drawer, 12, 7.5, 8, 4, C.Mint, { Z = 2, Thickness = 1 })
	end
	kit.Part(body, 83, 54, 7, 44, C.Wood, { Radius = 2, Z = 1 })
	kit.Part(body, 40, 60, 44, 4, C.WoodDark, { Radius = 2, Z = 1 })
	kit.Part(body, 3, 48, 94, 8, C.WoodLight, { Radius = 3, Z = 3, Shine = true }) -- plateau
	-- lampe
	kit.Blob(body, 17, 46, 16, 6, C.Mint, { Z = 2 })
	kit.Line(body, 17, 45, 12, 26, 3, C.GreyDark, 0, 1)
	kit.Line(body, 12, 26, 26, 14, 3, C.GreyDark, 0, 1)
	kit.Circle(body, 12, 26, 5, 5, C.Mint, 0, 2)
	local shade = kit.Part(body, 22, 10, 22, 12, C.Mint, { Radius = 6, Z = 3, Rotation = 24, Shine = true })
	kit.Circle(shade, 11, 12, 8, 6, C.Butter, 0, 2)
	-- livres
	local books = { { 44, 40, 30, C.Pink }, { 46, 34, 26, C.Sky }, { 43, 29, 28, C.Butter } }
	for _, b in ipairs(books) do
		local book = kit.Part(body, b[1], b[2], b[3], 6, b[4], { Radius = 2, Z = 4, Thickness = 1.3 })
		kit.Box(book, b[3] - 5, 1.5, 3, 3, C.White, 0.2, 2)
	end
	kit.Blob(body, 58, 24, 9, 9, C.Red, { Z = 4, Shine = true }) -- pomme
	kit.Blob(body, 61, 18.5, 5, 3, C.Leaf, { Z = 5, Thickness = 1, Rotation = -20 })
	-- pot à crayons
	for index, color in ipairs({ C.Yellow, C.Pink, C.Sky }) do
		local x = 80 + (index - 2) * 4
		kit.Line(body, x, 42, x + (index - 2) * 3, 24, 3, color, 0, 4)
	end
	local cup = kit.Part(body, 74, 32, 16, 17, C.Lilac, { Radius = 4, Z = 5, Shine = true })
	kit.Heart(cup, 8, 10, 7, C.White, 0, 2)
	return nil
end

-- Bibliothèque garnie : livres de toutes les couleurs, plante, bocal à cœurs
Art.Bookshelf = function(body, kit, _item)
	local C = kit.C
	feet(kit, body, { 14, 80 }, 94, 6, 6, C.WoodDark, 1)
	kit.Part(body, 8, 10, 84, 86, C.Wood, { Radius = 6, Z = 2 })
	kit.Part(body, 13, 15, 74, 76, kit.Darken(C.Wood, 0.28), { Radius = 3, Z = 3, Outline = false })
	for _, y in ipairs({ 38, 64 }) do
		kit.Part(body, 10, y, 80, 5, C.WoodLight, { Radius = 2, Z = 5 })
	end
	local palette = { C.Pink, C.Sky, C.Butter, C.Mint, C.Lilac, C.Peach, C.PinkSoft }
	local function book(x, bottom, w, h, color, rot)
		return kit.Part(body, x, bottom - h, w, h, color, { Radius = 2, Z = 4, Thickness = 1.2, Rotation = rot })
	end
	-- rayon du haut
	local shelf1 = { { 16, 8, 19 }, { 24, 7, 16 }, { 31, 9, 20 }, { 40, 7, 17 } }
	for index, b in ipairs(shelf1) do
		book(b[1], 38, b[2], b[3], palette[index], nil)
	end
	book(49, 38, 7, 18, palette[5], 14)
	-- bocal à cœurs
	local jar = kit.Part(body, 66, 23, 16, 15, C.Glass, { Radius = 5, Z = 4, T = 0.2, Shine = true })
	kit.Heart(jar, 5, 9, 6, C.Pink, 0, 2)
	kit.Heart(jar, 11, 8, 5, C.PinkDeep, 0, 2)
	kit.Part(body, 67, 20, 14, 4, C.Pink, { Radius = 2, Z = 5, Thickness = 1 })
	-- rayon du milieu : pile couchée + livres debout
	for index, b in ipairs({ { 16, 26, C.Mint }, { 18, 22, C.Pink }, { 17, 20, C.Butter } }) do
		kit.Part(body, b[1], 64 - index * 6, b[2], 6, b[3], { Radius = 2, Z = 4, Thickness = 1.2 })
	end
	local shelf2 = { { 48, 8, 20 }, { 56, 7, 18 }, { 63, 9, 21 }, { 72, 7, 17 } }
	for index, b in ipairs(shelf2) do
		book(b[1], 64, b[2], b[3], palette[index + 3], nil)
	end
	-- rayon du bas
	local shelf3 = { { 16, 9, 21 }, { 25, 7, 18 }, { 32, 8, 20 }, { 60, 8, 19 }, { 68, 9, 21 }, { 77, 7, 17 } }
	for index, b in ipairs(shelf3) do
		book(b[1], 90, b[2], b[3], palette[(index % #palette) + 1], nil)
	end
	local ball = kit.Blob(body, 50, 83, 14, 14, C.PinkSoft, { Z = 4, Shine = true })
	kit.Face(ball, 7, 7.5, 12, { Eyes = "dot", Mouth = "smile", Z = 3 })
	-- plante sur le dessus
	kit.Part(body, 66, 0, 14, 11, C.Peach, { Radius = 3, Z = 6 })
	for _, leaf in ipairs({ { 68, -4, -30 }, { 76, -5, 30 }, { 62, 6, -70 } }) do
		kit.Blob(body, leaf[1], leaf[2], 8, 12, C.Leaf, { Z = 5, Rotation = leaf[3], Thickness = 1.2 })
	end
	return nil
end

-- Canapé moelleux rose : dossier, 2 coussins, accoudoirs ronds, petits pieds
Art.Sofa = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 170, 200)
	for _, x in ipairs({ 12, 82 }) do
		kit.Part(body, x, 88, 6, 12, C.WoodDark, { Radius = 2, Z = 2 })
	end
	kit.Part(body, 8, 30, 84, 44, pink, { Radius = 18, Z = 2 }) -- dossier
	kit.Part(body, 4, 62, 92, 30, pink, { Radius = 12, Z = 3, Shade = 0.18 }) -- assise
	for _, x in ipairs({ 16, 51 }) do
		local cushion = kit.Part(body, x, 38, 33, 30, kit.Lighten(pink, 0.35), { Radius = 12, Z = 4, Shine = true })
		kit.Circle(cushion, 16.5, 15, 3, 3, kit.OutlineOf(pink), 0.3, 3) -- bouton capitonné
	end
	for _, x in ipairs({ 0, 80 }) do
		kit.Part(body, x, 48, 20, 42, kit.Darken(pink, 0.04), { Radius = 10, Z = 5, Shine = true }) -- accoudoirs
	end
	kit.Heart(body, 50, 80, 10, C.PinkDeep, 0, 6)
	-- petit coussin menthe
	local pillow = kit.Part(body, 60, 44, 20, 18, C.MintSoft, { Radius = 7, Z = 6, Rotation = 12, Shine = true })
	kit.Face(pillow, 10, 10, 13, { Eyes = "happy", Mouth = "smile", Z = 3 })
	return nil
end

-- Pouf pêche : grosse pêche moelleuse avec sa feuille et un visage
Art.Beanbag = function(body, kit, _item)
	local C = kit.C
	local peach = Color3.fromRGB(255, 186, 160)
	local bag = kit.Blob(body, 50, 64, 92, 70, peach, { Z = 2, Shade = 0.14, Shine = true })
	kit.Gradient(bag, Color3.fromRGB(255, 236, 210), Color3.fromRGB(255, 200, 215), 90)
	kit.Blob(bag, 64, 30, 34, 30, C.Pink, { Z = 1, T = 0.6, Outline = false, Shade = false }) -- joue rosée
	kit.Line(bag, 46, 4, 42, 24, 2.4, kit.OutlineOf(peach), 0.35, 2) -- sillon
	kit.Blob(body, 50, 34, 30, 7, kit.Darken(peach, 0.08), { Z = 3, Outline = false, Shade = false, T = 0.3 }) -- creux
	kit.Line(body, 50, 30, 52, 22, 3, C.Brown, 0, 3)
	kit.Blob(body, 62, 23, 20, 10, C.Leaf, { Z = 4, Rotation = -18, Shine = true })
	kit.Blob(body, 40, 25, 14, 8, C.LeafDark, { Z = 3, Rotation = 24 })
	kit.Face(body, 50, 70, 30, { Eyes = "happy", Mouth = "cat", Z = 5 })
	return nil
end

-- Coiffeuse : miroir cœur avec ampoules, flacons de parfum, rouge à lèvres
Art.VanityTable = function(body, kit, _item)
	local C = kit.C
	-- miroir
	kit.Part(body, 46, 46, 8, 12, C.Gold, { Radius = 2, Z = 1 })
	kit.Heart(body, 50, 30, 60, kit.OutlineOf(C.Pink), 0, 2)
	kit.Heart(body, 50, 30, 56, C.Pink, 0, 3)
	local glass = kit.Heart(body, 50, 30.5, 44, C.Glass, 0, 4)
	kit.Gradient(glass, C.White, Color3.fromRGB(200, 210, 255), 90)
	kit.Line(body, 37, 25, 43, 19, 3, C.White, 0.2, 5)
	kit.Line(body, 38, 32, 40, 30, 3, C.White, 0.2, 5)
	for index, p in ipairs({ { 30, 10 }, { 50, 12 }, { 70, 10 }, { 24, 30 }, { 76, 30 } }) do
		local bulb = kit.Circle(body, p[1], p[2], 6, 6, C.Butter, 0, 6)
		kit.Stroke(bulb, C.Gold, 1)
		kit.Animate(bulb, "Pulse", 0.35, 0.8, index * 1.7)
	end
	-- table
	kit.Part(body, 4, 56, 92, 8, C.Cream, { Radius = 4, Z = 3, Shine = true })
	local apron = kit.Part(body, 9, 63, 82, 13, C.PinkSoft, { Radius = 4, Z = 2 })
	kit.Blob(apron, 41, 6.5, 10, 5, C.Gold, { Z = 2, Thickness = 1 })
	for _, x in ipairs({ 11, 83 }) do
		kit.Part(body, x, 72, 6, 26, C.Cream, { Radius = 3, Z = 1 })
		kit.Blob(body, x + 3, 98, 9, 5, C.Gold, { Z = 2, Thickness = 1 })
	end
	-- parfums et rouge à lèvres
	local bottle = kit.Part(body, 12, 44, 14, 14, C.LilacSoft, { Radius = 5, Z = 5, Shine = true, T = 0.1 })
	kit.Circle(bottle, 7, 9, 7, 5, C.Lilac, 0.2, 2)
	kit.Blob(body, 19, 41, 7, 6, C.Gold, { Z = 6, Thickness = 1 })
	kit.Part(body, 78, 48, 7, 10, C.Gold, { Radius = 2, Z = 5, Thickness = 1 })
	kit.Part(body, 79, 41, 5, 9, C.Red, { Radius = 2, Z = 4, Thickness = 1 })
	kit.Blob(body, 88, 54, 10, 7, C.MintSoft, { Z = 5 })
	return nil
end

-- Armoire pastel : une porte ouverte sur une robe rose, carton à chapeau
Art.Wardrobe = function(body, kit, _item)
	local C = kit.C
	local lilac = Color3.fromRGB(222, 206, 252)
	feet(kit, body, { 14, 80 }, 92, 6, 8, C.WoodDark, 1)
	local cabinet = kit.Part(body, 8, 16, 84, 78, lilac, { Radius = 6, Z = 2 })
	kit.Part(body, 4, 10, 92, 9, kit.Lighten(lilac, 0.4), { Radius = 4, Z = 3, Shine = true }) -- corniche
	-- porte gauche (fermée)
	local door = kit.Part(cabinet, 4, 5, 37, 56, kit.Lighten(lilac, 0.3), { Radius = 4, Z = 2 })
	local panel = kit.Part(door, 5, 5, 27, 46, kit.Lighten(lilac, 0.55), { Radius = 8, Z = 2, Thickness = 1.2 })
	kit.Heart(panel, 13.5, 20, 11, C.Pink, 0, 2)
	kit.Circle(door, 33, 30, 4, 4, C.Gold, 0, 3)
	-- intérieur + penderie
	local inside = kit.Part(cabinet, 43, 5, 37, 56, kit.Darken(lilac, 0.28), { Radius = 3, Z = 2, Outline = false })
	kit.Line(inside, 3, 6, 34, 6, 2, C.GreyDark, 0, 2)
	kit.Line(inside, 12, 6, 12, 11, 1.5, C.GreyDark, 0, 2)
	kit.Part(inside, 7, 10, 10, 10, C.Pink, { Radius = 3, Z = 3 }) -- haut de la robe
	kit.Triangle(inside, 12, 16, 22, 28, C.Pink, 3, 0, 8) -- jupe
	kit.Heart(inside, 12, 25, 6, C.White, 0, 4)
	kit.Line(inside, 27, 6, 27, 11, 1.5, C.GreyDark, 0, 2)
	kit.Part(inside, 21, 10, 12, 26, C.Mint, { Radius = 3, Z = 3 }) -- chemise
	-- porte ouverte (vue de profil)
	kit.Part(body, 91, 20, 8, 58, kit.Lighten(lilac, 0.3), { Radius = 3, Z = 4 })
	-- tiroir du bas
	local drawer = kit.Part(cabinet, 4, 63, 76, 11, kit.Lighten(lilac, 0.3), { Radius = 3, Z = 2 })
	kit.Blob(drawer, 38, 5.5, 10, 4, C.Gold, { Z = 2, Thickness = 1 })
	-- carton à chapeau
	local hatbox = kit.Part(body, 16, -2, 30, 13, C.PinkSoft, { Radius = 4, Z = 4 })
	kit.Box(hatbox, 13, 0, 4, 13, C.Pink, 0, 2)
	kit.Part(body, 14, -5, 34, 5, C.Pink, { Radius = 2, Z = 5 })
	kit.Heart(body, 31, -7, 8, C.PinkDeep, 0, 6)
	return nil
end

-- Fauteuil gamer rose à oreilles de chat, sur roulettes
Art.GamingChair = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 160, 200)
	-- piètement
	kit.Line(body, 20, 93, 80, 93, 5, C.GreyDark, 0, 1)
	kit.Line(body, 34, 90, 66, 90, 5, C.GreyDark, 0, 1)
	for _, x in ipairs({ 20, 80, 36, 64 }) do
		kit.Circle(body, x, 97, 6, 6, C.Ink, 0, 2)
	end
	kit.Part(body, 46, 74, 8, 18, C.Grey, { Radius = 2, Z = 1 })
	-- oreilles
	for _, x in ipairs({ 33, 67 }) do
		local ear = kit.Part(body, x - 8, 6, 16, 16, pink, { Radius = 4, Z = 2, Rotation = 45 })
		kit.Part(ear, 2.5, 2.5, 8, 8, C.PinkSoft, { Radius = 3, Z = 2, Outline = false, Shade = false })
	end
	-- dossier
	local back = kit.Part(body, 22, 10, 56, 58, pink, { Radius = 16, Z = 3, Shade = 0.16 })
	local stripe = kit.Part(back, 15, 8, 26, 44, C.White, { Radius = 10, Z = 2, Shine = true })
	kit.Face(stripe, 13, 22, 20, { Eyes = "big", Mouth = "cat", Z = 3 })
	kit.Heart(stripe, 13, 5, 7, C.Pink, 0, 3)
	-- assise + accoudoirs
	kit.Part(body, 16, 62, 68, 14, pink, { Radius = 7, Z = 4, Shine = true })
	for _, x in ipairs({ 8, 80 }) do
		kit.Part(body, x + 4, 56, 4, 14, C.GreyDark, { Radius = 2, Z = 4 })
		kit.Part(body, x, 51, 12, 7, C.White, { Radius = 3, Z = 5 })
	end
	return nil
end

-- Douche à l'italienne : carrelage menthe, pommeau, gouttes, rideau, canard
Art.Shower = function(body, kit, _item)
	local C = kit.C
	local wall = kit.Part(body, 8, 8, 84, 86, C.MintSoft, { Radius = 5, Z = 1 })
	for index = 1, 4 do
		kit.Box(wall, index * 16.8, 0, 1.5, 86, C.White, 0.1, 2)
	end
	for index = 1, 4 do
		kit.Box(wall, 0, index * 17, 84, 1.5, C.White, 0.1, 2)
	end
	-- tuyau + pommeau
	kit.Line(body, 78, 64, 78, 14, 3.5, C.Grey, 0, 2)
	kit.Line(body, 78, 14, 60, 14, 3.5, C.Grey, 0, 2)
	local head = kit.Part(body, 48, 14, 24, 10, C.Grey, { Radius = 5, Z = 3, Shine = true })
	for index = 0, 3 do
		kit.Circle(head, 5 + index * 4.7, 7.5, 2, 2, C.GreyDark, 0, 2)
	end
	kit.Circle(body, 72, 64, 7, 7, C.Pink, 0, 3)
	kit.Circle(body, 84, 64, 7, 7, C.Sky, 0, 3)
	-- gouttes qui tombent
	for index, p in ipairs({ { 52, 32 }, { 58, 44 }, { 64, 30 }, { 55, 58 }, { 67, 50 }, { 61, 70 } }) do
		local drop = kit.Line(body, p[1], p[2], p[1] - 1, p[2] + 6, 2.4, C.Sky, 0.1, 4)
		kit.Animate(drop, "Bob", 2.5, 1.6, index * 0.9)
	end
	-- receveur
	kit.Part(body, 2, 90, 96, 10, C.White, { Radius = 4, Z = 5, Shine = true })
	-- rideau + tringle
	kit.Line(body, 4, 6, 96, 6, 3, C.Gold, 0, 6)
	local curtain = kit.Part(body, 6, 6, 26, 82, C.PinkSoft, { Radius = 6, Z = 5 })
	for _, x in ipairs({ 7, 14, 20 }) do
		kit.Box(curtain, x, 4, 2, 76, C.Pink, 0.5, 2)
	end
	kit.Heart(curtain, 11, 40, 7, C.Pink, 0, 3)
	for _, x in ipairs({ 10, 18, 26 }) do
		kit.Circle(body, x, 6, 5, 5, C.Gold, 0, 7)
	end
	duck(kit, body, 80, 92, 16, 6)
	return nil
end

-- Baignoire à pieds dorés débordant de mousse, canard et bulles
Art.Bathtub = function(body, kit, _item)
	local C = kit.C
	for _, x in ipairs({ 20, 80 }) do
		kit.Blob(body, x, 94, 14, 12, C.Gold, { Z = 1, Shine = true })
	end
	-- robinet
	kit.Line(body, 12, 48, 12, 30, 4, C.Gold, 0, 1)
	kit.Line(body, 12, 30, 22, 30, 4, C.Gold, 0, 1)
	kit.Line(body, 22, 30, 22, 35, 4, C.Gold, 0, 1)
	kit.Circle(body, 7, 40, 5, 5, C.Pink, 0, 2)
	-- mousse
	local foam = { { 22, 44, 18 }, { 36, 40, 20 }, { 52, 39, 22 }, { 68, 42, 18 }, { 80, 45, 14 }, { 44, 46, 14 }, { 60, 47, 12 } }
	for _, f in ipairs(foam) do
		kit.Blob(body, f[1], f[2], f[3], f[3], C.White, { Z = 2, Outline = C.Sky, Thickness = 1.3, Shade = 0.06 })
	end
	duck(kit, body, 64, 36, 16, 3)
	local tub = kit.Part(body, 6, 50, 88, 40, C.White, { Radius = 18, Z = 4, Shade = 0.14 })
	kit.Gradient(tub, C.White, Color3.fromRGB(255, 220, 236), 90)
	kit.Box(tub, 0, 14, 88, 4, C.Pink, 0.3, 2)
	kit.Heart(tub, 44, 26, 10, C.Pink, 0, 3)
	kit.Part(body, 2, 46, 96, 9, C.White, { Radius = -1, Z = 5, Shine = true }) -- rebord
	-- bulles qui flottent
	for index, b in ipairs({ { 30, 22, 8 }, { 84, 26, 6 }, { 44, 12, 5 }, { 74, 10, 7 } }) do
		local bubble = kit.Blob(body, b[1], b[2], b[3], b[3], C.Glass, { Z = 6, T = 0.5, Outline = C.Sky, Thickness = 1, Shade = false })
		kit.Circle(bubble, b[3] * 0.32, b[3] * 0.32, b[3] * 0.3, b[3] * 0.3, C.White, 0.1, 2)
		kit.Animate(bubble, "Bob", 2, 0.8, index * 1.4)
	end
	return nil
end

-- Cheminée en briques roses : feu qui crépite, bûches, bougies sur le manteau
Art.Fireplace = function(body, kit, _item)
	local C = kit.C
	local brick = Color3.fromRGB(240, 164, 164)
	local wall = kit.Part(body, 6, 20, 88, 76, brick, { Radius = 5, Z = 1 })
	local mortar = kit.Lighten(brick, 0.35)
	for _, b in ipairs({ { 4, 8 }, { 60, 6 }, { 10, 22 }, { 66, 20 }, { 2, 38 }, { 68, 36 }, { 8, 54 }, { 62, 52 } }) do
		kit.Part(wall, b[1], b[2], 16, 7, mortar, { Radius = 2, Z = 2, Outline = false, Shade = false, T = 0.3 })
	end
	-- foyer
	local hearth = kit.Part(body, 24, 40, 52, 58, Color3.fromRGB(70, 40, 58), { Radius = 24, Z = 2, Thickness = 2.5, Outline = C.Cream })
	local glow = kit.Box(hearth, 0, 20, 52, 38, C.Orange, 0.2, 1)
	kit.Round(glow, 20)
	kit.Fade(glow, 1, 0, 90)
	kit.Animate(glow, "Pulse", 0.35, 1.2, 0)
	-- flammes
	flame(kit, hearth, 26, 50, 30, 40, C.Orange, 3, 0)
	flame(kit, hearth, 15, 50, 16, 24, C.Orange, 3, 1.7)
	flame(kit, hearth, 37, 50, 15, 26, C.Orange, 3, 3.1)
	flame(kit, hearth, 26, 51, 20, 28, C.Yellow, 4, 0.8)
	flame(kit, hearth, 26, 51, 10, 16, C.Cream, 5, 2.2)
	-- bûches
	kit.Part(hearth, 8, 47, 36, 7, C.Brown, { Radius = -1, Z = 6, Rotation = 8 })
	kit.Part(hearth, 8, 47, 36, 7, kit.Darken(C.Brown, 0.1), { Radius = -1, Z = 6, Rotation = -8 })
	for index, p in ipairs({ { 12, 18 }, { 40, 22 }, { 32, 8 } }) do
		local ember = kit.Circle(hearth, p[1], p[2], 3, 3, C.Butter, 0, 7)
		kit.Animate(ember, "Bob", 1.5, 1.3, index * 2.1)
	end
	-- dalle + manteau
	kit.Part(body, 2, 94, 96, 6, C.Cream, { Radius = 3, Z = 3 })
	kit.Part(body, 0, 14, 100, 10, C.Cream, { Radius = 4, Z = 3, Shine = true })
	-- guirlande de cœurs sous le manteau
	kit.Line(body, 10, 27, 90, 27, 1.2, C.White, 0.3, 4)
	for index = 0, 2 do
		kit.Heart(body, 18 + index * 32, 30, 8, C.PinkDeep, 0, 4)
	end
	-- déco du manteau : bougies, cadre, plante
	for index, x in ipairs({ 12, 20 }) do
		local h = if index == 1 then 12 else 9
		kit.Part(body, x - 3, 14 - h, 6, h, C.PinkMist, { Radius = 2, Z = 2 })
		local wick = kit.Blob(body, x, 14 - h - 3, 4, 6, C.Orange, { Z = 2, Outline = false, Shade = false })
		kit.Animate(wick, "Flicker", 0.3, 1, index * 1.9)
	end
	local frame = kit.Part(body, 40, -2, 22, 16, C.Gold, { Radius = 3, Z = 2 })
	local picture = kit.Part(frame, 3, 3, 16, 10, C.Sky, { Radius = 2, Z = 2, Outline = false, Shade = false })
	kit.Heart(picture, 8, 5, 7, C.Pink, 0, 2)
	kit.Part(body, 78, 6, 12, 9, C.Peach, { Radius = 2, Z = 2 })
	kit.Blob(body, 80, 2, 7, 10, C.Leaf, { Z = 1, Rotation = -25 })
	kit.Blob(body, 88, 2, 7, 10, C.Leaf, { Z = 1, Rotation = 25 })
	return { Glow = C.Orange }
end

-- Lit à baldaquin de princesse : couronne, voilages noués, tête de lit cœur
Art.CanopyBed = function(body, kit, _item)
	local C = kit.C
	local gold = C.Gold
	-- montants
	for _, x in ipairs({ 5, 89 }) do
		kit.Part(body, x, 12, 6, 86, C.Cream, { Radius = 3, Z = 1 })
	end
	-- tête de lit
	local headboard = kit.Part(body, 18, 34, 64, 40, C.PinkSoft, { Radius = 20, Z = 2 })
	for _, p in ipairs({ { 14, 14 }, { 50, 14 }, { 32, 26 } }) do
		kit.Circle(headboard, p[1], p[2], 3, 3, C.Pink, 0.2, 2)
	end
	kit.Heart(body, 50, 30, 18, gold, 0, 3)
	kit.Heart(body, 50, 30, 12, C.PinkDeep, 0, 4)
	-- matelas, oreillers, couverture
	kit.Part(body, 12, 64, 76, 14, C.White, { Radius = 6, Z = 3 })
	for _, x in ipairs({ 36, 64 }) do
		local pillow = kit.Blob(body, x, 63, 28, 14, C.PinkMist, { Z = 4, Shine = true })
		kit.Heart(pillow, 18, 8, 6, C.Pink, 0, 2)
	end
	local blanket = kit.Part(body, 10, 70, 80, 18, C.Pink, { Radius = 6, Z = 5, Shine = true })
	kit.Gradient(blanket, C.White, Color3.fromRGB(255, 200, 225), 90)
	for index = 0, 6 do
		kit.Circle(blanket, 6 + index * 11.3, 18, 9, 7, C.PinkSoft, 0, 2) -- volants
	end
	kit.Heart(blanket, 40, 8, 8, C.White, 0, 3)
	-- pied de lit
	kit.Part(body, 6, 86, 88, 9, C.Cream, { Radius = 4, Z = 6 })
	feet(kit, body, { 8, 86 }, 94, 6, 6, gold, 5)
	-- baldaquin
	kit.Part(body, 0, 6, 100, 9, C.Cream, { Radius = 4, Z = 7, Shine = true })
	for index = 0, 6 do
		kit.Circle(body, 7 + index * 14.3, 16, 15, 11, C.Pink, 0, 6) -- festons
	end
	-- voilages noués
	for _, side in ipairs({ -1, 1 }) do
		local x = if side < 0 then 1 else 83
		local drape = kit.Part(body, x, 12, 16, 48, C.PinkSoft, { Radius = 8, Z = 8, T = 0.15, Rotation = side * 4 })
		kit.Box(drape, 7, 4, 2, 40, C.White, 0.4, 2)
		kit.Part(body, x + 2, 58, 12, 32, C.PinkSoft, { Radius = 6, Z = 8, T = 0.15, Rotation = -side * 5 })
		kit.Heart(body, x + 8, 59, 11, C.PinkDeep, 0, 9) -- nœud
	end
	-- couronne
	for _, x in ipairs({ 40, 50, 60 }) do
		kit.Part(body, x - 4.5, -3, 9, 9, gold, { Radius = 2, Z = 8, Rotation = 45, Thickness = 1.2 })
		kit.Circle(body, x, -5, 4, 4, C.Butter, 0, 9)
	end
	local band = kit.Part(body, 36, 1, 28, 7, gold, { Radius = 2, Z = 9, Thickness = 1.2 })
	kit.Diamond(band, 14, 3.5, 3.5, C.Heart, 0, 2)
	return nil
end

-- Lit nuage : gros nuage moelleux, oreiller endormi, couette étoilée, rêves
Art.CloudBed = function(body, kit, _item)
	local C = kit.C
	local bed = kit.Group(body, 0, 0, 100, 100, 2)
	kit.Animate(bed, "Bob", 1.5, 0.6, 0)
	local line = Color3.fromRGB(190, 170, 235)
	local function puffs(list, color, z)
		for _, p in ipairs(list) do
			kit.Circle(bed, p[1], p[2], p[3] + 3.2, p[3] * p[4] + 3.2, line, 0, z) -- contour
		end
		for _, p in ipairs(list) do
			local puff = kit.Circle(bed, p[1], p[2], p[3], p[3] * p[4], color, 0, z + 1)
			kit.Gradient(puff, C.White, Color3.fromRGB(236, 226, 255), 90)
		end
	end
	-- tête de lit nuage
	puffs({ { 14, 48, 24, 1 }, { 26, 38, 26, 1 }, { 12, 64, 20, 1 } }, C.White, 1)
	-- nuage du lit
	puffs({
		{ 14, 80, 26, 0.8 },
		{ 32, 74, 30, 0.8 },
		{ 52, 72, 30, 0.8 },
		{ 72, 74, 30, 0.8 },
		{ 88, 80, 22, 0.9 },
		{ 50, 86, 84, 0.26 },
	}, C.White, 3)
	-- oreiller endormi
	local pillow = kit.Blob(bed, 26, 60, 28, 16, C.PinkSoft, { Z = 6, Shine = true })
	kit.Face(pillow, 14, 8, 16, { Eyes = "closed", Mouth = "smile", Z = 3 })
	-- couette étoilée
	local quilt = kit.Part(bed, 38, 57, 58, 18, C.Lilac, { Radius = 9, Z = 7, Shine = true })
	kit.Gradient(quilt, C.White, Color3.fromRGB(215, 200, 255), 90)
	for _, p in ipairs({ { 14, 10, 6 }, { 30, 7, 5 }, { 44, 11, 6 } }) do
		kit.Sparkle(quilt, p[1], p[2], p[3], C.Butter, 0, 3)
	end
	kit.Circle(quilt, 22, 13, 2, 2, C.White, 0, 3)
	kit.Circle(quilt, 50, 5, 2, 2, C.White, 0, 3)
	-- lune et étoiles
	local moon = kit.Blob(bed, 76, 22, 20, 20, C.Butter, { Z = 5, Shine = true })
	kit.Face(moon, 10, 11, 13, { Eyes = "closed", Mouth = "none", Z = 3 })
	for index, s in ipairs({ { 52, 30, 10 }, { 92, 42, 8 }, { 44, 14, 7 }, { 62, 46, 6 } }) do
		local star = kit.Sparkle(bed, s[1], s[2], s[3], if index % 2 == 0 then C.Pink else C.Butter, 0, 6)
		kit.Animate(star, "Bob", 1.5, 1.1, index * 1.3)
	end
	for index, z in ipairs({ { 40, 44, 9 }, { 46, 36, 7 } }) do
		local label = kit.Text(bed, "z", z[1], z[2], z[3], C.Purple, 8)
		kit.Animate(label, "Bob", 2, 0.9, index * 0.8)
	end
	return { Glow = Color3.fromRGB(215, 195, 255) }
end

-- Source chaude : bassin de pierres, capybara au yuzu, vapeur qui ondule
Art.HotSpring = function(body, kit, _item)
	local C = kit.C
	local stone = Color3.fromRGB(196, 190, 204)
	-- panneau ♨
	kit.Part(body, 85, 22, 4, 40, C.WoodDark, { Radius = 2, Z = 1 })
	local sign = kit.Part(body, 75, 16, 24, 16, C.WoodLight, { Radius = 4, Z = 2, Shine = true })
	kit.Text(sign, "♨", 12, 8.5, 12, C.Red, 3)
	-- pierres du fond
	for _, s in ipairs({ { 9, 64, 20, 16 }, { 27, 58, 22, 14 }, { 50, 56, 26, 14 }, { 73, 58, 22, 14 }, { 91, 64, 20, 16 } }) do
		kit.Blob(body, s[1], s[2], s[3], s[4], stone, { Z = 3 })
	end
	-- eau
	local water = kit.Blob(body, 50, 75, 96, 32, C.Sky, { Z = 4, Outline = kit.Darken(C.Sky, 0.25) })
	kit.Gradient(water, Color3.fromRGB(215, 255, 245), Color3.fromRGB(150, 205, 250), 90)
	kit.Blob(water, 72, 12, 18, 3.5, C.White, { Z = 2, T = 0.3, Outline = false, Shade = false })
	kit.Blob(water, 20, 20, 12, 3, C.White, { Z = 2, T = 0.3, Outline = false, Shade = false })
	-- capybara (coupé à la surface de l'eau)
	local bath = kit.Group(body, 0, 0, 100, 77, 5, true)
	local fur = Color3.fromRGB(205, 150, 105)
	for _, x in ipairs({ 30, 52 }) do
		kit.Blob(bath, x, 55, 8, 7, kit.Darken(fur, 0.1), { Z = 1 })
	end
	local head = kit.Blob(bath, 41, 70, 36, 32, fur, { Z = 2, Shine = true })
	kit.Blob(head, 18, 20, 22, 13, kit.Lighten(fur, 0.4), { Z = 2, Outline = false, Shade = false })
	kit.Face(head, 18, 13, 26, { Eyes = "closed", Mouth = "none", Z = 3 })
	kit.Blob(head, 18, 18.5, 7, 4, C.Ink, { Z = 4, Outline = false, Shade = false })
	kit.Blob(bath, 41, 52, 14, 13, C.Orange, { Z = 3, Shine = true }) -- yuzu
	kit.Blob(bath, 46, 46, 8, 4.5, C.Leaf, { Z = 4, Rotation = -25, Thickness = 1 })
	kit.Line(body, 24, 77, 32, 77, 1.6, C.White, 0.2, 6) -- ronds dans l'eau
	kit.Line(body, 50, 77, 58, 77, 1.6, C.White, 0.2, 6)
	-- pierres de devant
	for _, s in ipairs({ { 8, 90, 20, 16 }, { 27, 94, 22, 12 }, { 50, 95, 26, 10 }, { 73, 94, 22, 12 }, { 92, 90, 20, 16 } }) do
		kit.Blob(body, s[1], s[2], s[3], s[4], stone, { Z = 7, Shine = true })
	end
	kit.Blob(body, 27, 90, 8, 3.5, C.Leaf, { Z = 8, Outline = false, Shade = false, T = 0.2 }) -- mousse
	kit.Blob(body, 76, 91, 6, 3, C.Leaf, { Z = 8, Outline = false, Shade = false, T = 0.2 })
	-- serviette pliée + seau
	local towel = kit.Part(body, 82, 76, 18, 9, C.PinkSoft, { Radius = 3, Z = 8, Shine = true })
	kit.Box(towel, 0, 5, 18, 2, C.Pink, 0.2, 2)
	local bucket = kit.Part(body, 1, 72, 14, 13, C.WoodLight, { Radius = 3, Z = 8 })
	kit.Box(bucket, 0, 3, 14, 2, C.WoodDark, 0.2, 2)
	kit.Box(bucket, 0, 9, 14, 2, C.WoodDark, 0.2, 2)
	-- vapeur
	for index, w in ipairs({ { 18, 50 }, { 64, 44 }, { 82, 54 } }) do
		local wisp = kit.Group(body, w[1] - 10, w[2] - 30, 20, 34, 9)
		kit.Circle(wisp, 10, 26, 14, 12, C.White, 0.35, 1)
		kit.Circle(wisp, 12, 16, 11, 10, C.White, 0.45, 1)
		kit.Circle(wisp, 9, 7, 8, 8, C.White, 0.55, 1)
		kit.Animate(wisp, "Bob", 3, 0.7, index * 1.6)
	end
	return nil
end

return Art
