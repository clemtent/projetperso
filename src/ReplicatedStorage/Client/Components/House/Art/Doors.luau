--[[
	Doors (ModuleScript) — dessins 🚪 Portes
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Doors
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
	Les portes sont posées au sol (y = 100), contre le mur.
]]

local Art = {}

local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- Aides partagées
----------------------------------------------------------------------

-- Forme en arche posée au sol : coins arrondis en haut seulement (le bas est
-- coupé net à y = 100). Renvoie la forme (ses enfants se placent dedans).
local function arch(parent, kit, x, y, w, color, radius, z, options)
	local pad = 3
	local g = kit.Group(parent, x - pad, y - pad, w + pad * 2, 100 - y + pad, z, true)
	local opts = options or {}
	opts.Radius = radius
	opts.Z = 1
	return kit.Part(g, pad, pad, w, 100 - y + radius + 4, color, opts)
end

-- Poignée ronde dorée avec reflet
local function knob(parent, kit, cx, cy, size, color)
	local k = kit.Blob(parent, cx, cy, size, size, color or kit.C.Gold, { Z = 6 })
	kit.Circle(k, size * 0.34, size * 0.32, size * 0.3, size * 0.3, WHITE, 0.3, 2)
	return k
end

-- Paillasson devant la porte
local function doormat(parent, kit, cx, w, color)
	local mat = kit.Part(parent, cx - w / 2, 95, w, 5, color, { Radius = 2, Z = 7, Shade = 0.1 })
	for i = 0, math.floor(w / 6) - 1 do
		kit.Box(mat, 2 + i * 6, 0.5, 1.2, 4, kit.Lighten(color, 0.3), 0.3, 2)
	end
	return mat
end

----------------------------------------------------------------------
-- Dessins
----------------------------------------------------------------------

-- Porte en bois classique : chambranle, 4 panneaux, couronne de feuilles, poignée dorée
Art.WoodenDoor = function(body, kit, _item)
	local C = kit.C
	arch(body, kit, 16, 2, 68, C.WoodDark, 10, 1, { Shade = 0.15 })
	local door = arch(body, kit, 22, 8, 56, C.Wood, 6, 2, { Shade = 0.18 })
	for _, x in ipairs({ 16, 38 }) do
		kit.Box(door, x, 0, 1, 92, C.WoodDark, 0.8, 2) -- veines du bois
	end
	for _, p in ipairs({ { 5, 8, 21, 32 }, { 30, 8, 21, 32 }, { 5, 48, 21, 38 }, { 30, 48, 21, 38 } }) do
		local panel = kit.Part(door, p[1], p[2], p[3], p[4], C.WoodLight, { Radius = 4, Z = 2, Shade = 0.2 })
		kit.Box(panel, 2, 2, p[3] - 4, 2, WHITE, 0.6, 2)
	end
	-- charnières
	for _, y in ipairs({ 18, 76 }) do
		kit.Part(body, 20, y, 5, 8, C.GreyDark, { Radius = 1, Z = 4 })
	end
	-- couronne de feuilles
	local wreath = kit.Group(body, 30, 10, 40, 40, 5)
	kit.Line(wreath, 20, 0, 20, 8, 1.4, C.Red, 0, 1) -- ruban
	for i = 0, 11 do
		local a = math.rad(i * 30)
		local leaf = kit.Blob(wreath, 20 + math.cos(a) * 10, 20 + math.sin(a) * 10, 10, 7, i % 2 == 0 and C.Leaf or C.LeafDark, { Z = 2, Rotation = i * 30 + 90, Thickness = 1.2 })
		leaf.ZIndex = 2 + i % 2
	end
	for _, b in ipairs({ { 12, 13 }, { 29, 15 }, { 26, 28 } }) do
		kit.Circle(wreath, b[1], b[2], 4, 4, C.Red, 0, 4)
	end
	kit.Blob(wreath, 15, 31, 9, 7, C.Pink, { Z = 5, Rotation = -20 })
	kit.Blob(wreath, 25, 31, 9, 7, C.Pink, { Z = 5, Rotation = 20 })
	kit.Circle(wreath, 20, 31, 4.5, 4.5, C.PinkDeep, 0, 6)
	-- poignée et serrure
	local plate = kit.Part(body, 66, 54, 7, 16, C.Butter, { Radius = 3, Z = 5 })
	kit.Circle(plate, 3.5, 11, 2.2, 2.2, C.Ink, 0, 2)
	kit.Box(plate, 3, 11, 1, 3, C.Ink, 0, 2)
	knob(body, kit, 69.5, 60, 8)
	doormat(body, kit, 50, 50, C.Blush)
	kit.Heart(body, 50, 97.5, 4, WHITE, 0, 8)
	return nil
end

-- Trou de souris : arche en bois, souris qui pointe le museau, morceau de fromage
Art.MouseHole = function(body, kit, _item)
	local C = kit.C
	arch(body, kit, 10, 20, 80, C.WoodLight, 40, 1, { Shade = 0.15 })
	local hole = arch(body, kit, 18, 28, 64, Color3.fromRGB(78, 52, 72), 32, 2, { Outline = C.WoodDark, Shade = false })
	kit.Gradient(hole, Color3.fromRGB(150, 150, 150), WHITE, 90)
	kit.Circle(hole, 22, 30, 10, 5, C.Butter, 0.75, 2) -- petite lueur au fond
	-- souris qui dépasse
	local mouse = kit.Group(body, 20, 50, 50, 50, 3)
	kit.Animate(mouse, "Bob", 1.5, 0.8, 0)
	for _, x in ipairs({ 12, 36 }) do
		local ear = kit.Blob(mouse, x, 18, 18, 18, C.Grey, { Z = 1 })
		kit.Circle(ear, 9, 9, 11, 11, C.PinkSoft, 0, 2)
	end
	local head = kit.Blob(mouse, 24, 34, 34, 30, C.Grey, { Z = 2, Shine = true })
	kit.Face(head, 17, 14, 22, { Eyes = "big", Mouth = "cat", Z = 3 })
	kit.Circle(head, 17, 19, 4, 3, C.Pink, 0, 4) -- nez
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(mouse, 24 + side * 10, 38, 24 + side * 20, 36, 1, C.GreyDark, 0.2, 4)
		kit.Line(mouse, 24 + side * 10, 40, 24 + side * 20, 42, 1, C.GreyDark, 0.2, 4)
		kit.Blob(mouse, 24 + side * 8, 48, 8, 5, C.PinkSoft, { Z = 5 }) -- pattes
	end
	-- fromage
	local cheese = kit.Part(body, 72, 84, 24, 14, C.Butter, { Radius = 3, Z = 5, Outline = C.Gold, Shade = 0.15 })
	kit.Part(body, 72, 80, 24, 6, kit.Lighten(C.Butter, 0.3), { Radius = 3, Z = 4, Outline = C.Gold, Rotation = -6 })
	for _, h in ipairs({ { 5, 5, 4 }, { 14, 8, 3 }, { 19, 3, 2.5 } }) do
		kit.Circle(cheese, h[1], h[2], h[3], h[3], C.Gold, 0.2, 2)
	end
	kit.Heart(body, 50, 12, 10, C.Pink, 0, 4)
	return nil
end

-- Porte de jardin : arche verte, vitre avec ciel, vigne fleurie, pot de fleurs
Art.GardenDoor = function(body, kit, _item)
	local C = kit.C
	local sage = Color3.fromRGB(150, 206, 168)
	arch(body, kit, 16, 2, 68, C.Cream, 34, 1, { Shade = 0.12 })
	local door = arch(body, kit, 22, 8, 56, sage, 28, 2, { Shade = 0.18 })
	-- fenêtre en arche
	local glass = kit.Part(door, 8, 6, 40, 38, C.Glass, { Radius = 20, Z = 2, Outline = C.Cream, Thickness = 2.5, Shade = false })
	kit.Gradient(glass, C.Sky, WHITE, 90)
	kit.Cloud(glass, 14, 26, 14, WHITE, 0.1, 2)
	kit.Circle(glass, 30, 10, 7, 7, C.Butter, 0, 2)
	kit.Box(glass, 19, 0, 2.4, 38, C.Cream, 0, 3)
	kit.Box(glass, 0, 22, 40, 2.4, C.Cream, 0, 3)
	kit.Shine(glass, 5, 10, 3, 10, 4, 0.4)
	-- panneau bas avec tulipe
	local panel = kit.Part(door, 10, 52, 36, 32, kit.Lighten(sage, 0.3), { Radius = 5, Z = 2, Shade = 0.15 })
	kit.Line(panel, 18, 26, 18, 14, 1.6, C.LeafDark, 0, 2)
	kit.Blob(panel, 13, 21, 8, 4, C.Leaf, { Z = 2, Rotation = -30, Outline = false, Shade = false })
	kit.Blob(panel, 18, 11, 9, 10, C.Pink, { Z = 3, Outline = false, Shade = false })
	knob(body, kit, 70, 62, 8, C.Gold)
	-- vigne fleurie sur le chambranle
	local leaves = { { 16, 84 }, { 20, 70 }, { 15, 56 }, { 19, 42 }, { 23, 28 }, { 31, 16 }, { 44, 8 }, { 58, 6 } }
	for i, p in ipairs(leaves) do
		kit.Blob(body, p[1], p[2], 9, 6, i % 2 == 0 and C.Leaf or C.LeafDark, { Z = 5, Rotation = i * 40, Thickness = 1.2 })
	end
	for i, p in ipairs({ { 18, 62 }, { 22, 36 }, { 38, 10 }, { 64, 8 }, { 17, 92 } }) do
		local color = ({ C.Pink, C.Butter, C.Lilac, C.Pink, C.Butter })[i]
		local f = kit.Circle(body, p[1], p[2], 7, 7, color, 0, 6)
		kit.Stroke(f, kit.OutlineOf(color), 1)
		kit.Circle(f, 3.5, 3.5, 2.6, 2.6, i % 2 == 0 and C.Orange or C.Yellow, 0, 2)
	end
	-- pot de fleurs
	kit.Part(body, 80, 84, 16, 15, C.Orange, { Radius = 3, Z = 6, Shade = 0.2, Shine = true })
	kit.Part(body, 78, 82, 20, 5, kit.Lighten(C.Orange, 0.2), { Radius = 2, Z = 7 })
	kit.Blob(body, 84, 76, 8, 12, C.Leaf, { Z = 5, Rotation = -25 })
	kit.Blob(body, 93, 76, 8, 12, C.LeafDark, { Z = 5, Rotation = 25 })
	local bloom = kit.Blob(body, 88, 68, 12, 12, C.Pink, { Z = 6 })
	kit.Circle(bloom, 6, 6, 5, 5, C.Butter, 0, 2)
	kit.Animate(bloom, "Sway", 6, 0.8, 0)
	return nil
end

-- Porte cœur : rose, grande fenêtre en cœur, poignée cœur, guirlande de petits cœurs
Art.HeartDoor = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 168, 206)
	arch(body, kit, 16, 6, 68, C.PinkDeep, 14, 1, { Shade = 0.15 })
	local door = arch(body, kit, 22, 12, 56, pink, 10, 2, { Shade = 0.2 })
	-- fenêtre cœur
	kit.Heart(door, 28, 24, 38, C.PinkMist, 0, 2)
	local glass = kit.Heart(door, 28, 24.5, 33, C.Glass, 0, 3)
	for _, child in ipairs(glass:GetChildren()) do
		kit.Gradient(child, WHITE, C.PinkSoft, 90)
	end
	kit.Heart(door, 28, 25, 12, C.Heart, 0.15, 4)
	kit.Shine(door, 16, 14, 7, 3, 5, 0.3)
	-- panneau bas
	local panel = kit.Part(door, 9, 50, 38, 32, kit.Lighten(pink, 0.3), { Radius = 8, Z = 2, Shade = 0.15 })
	for i = 0, 2 do
		kit.Heart(panel, 9 + i * 10, 16, 6, C.PinkDeep, 0.3, 2)
	end
	-- poignée cœur
	kit.Heart(body, 70, 60, 9, C.Gold, 0, 6)
	kit.Circle(body, 68.5, 58, 2.4, 2.4, WHITE, 0.3, 7)
	-- cœur au fronton + petits cœurs
	kit.Heart(body, 50, 6, 17, kit.OutlineOf(C.Heart), 0, 4)
	local top = kit.Heart(body, 50, 6.3, 14, C.Heart, 0, 5)
	kit.Animate(top, "Breathe", 0.06, 1.6, 0)
	for i, x in ipairs({ 36, 64 }) do
		local h = kit.Heart(body, x, 5, 7, C.Lilac, 0, 4)
		kit.Animate(h, "Bob", 1.5, 1, i * 1.5)
	end
	doormat(body, kit, 50, 48, C.PinkDeep)
	return nil
end

-- Porte shoji coulissante : treillis de bois, papier crème, branche de sakura, entrouverte
Art.ShojiDoor = function(body, kit, _item)
	local C = kit.C
	local wood = Color3.fromRGB(200, 146, 106)
	local paper = Color3.fromRGB(255, 250, 238)
	kit.Part(body, 8, 2, 84, 98, C.WoodDark, { Radius = 3, Z = 1, Shade = 0.1 })
	-- lumière chaude dans l'entrebâillement
	local light = kit.Box(body, 13, 7, 14, 90, C.Butter, 0, 2)
	kit.Gradient(light, kit.Lighten(C.Butter, 0.4), C.Peach, 90)
	kit.Animate(light, "Pulse", 0.15, 0.6, 0)
	local function panel(x, z)
		local p = kit.Part(body, x, 7, 38, 91, wood, { Radius = 2, Z = z, Shade = 0.12 })
		local sheet = kit.Part(p, 4, 4, 30, 79, paper, { Radius = 0, Z = 2, Outline = false, Shade = 0.05 })
		for i = 1, 2 do
			kit.Box(sheet, i * 10 - 0.8, 0, 1.6, 79, wood, 0, 4)
		end
		for i = 1, 5 do
			kit.Box(sheet, 0, i * 13.2 - 0.8, 30, 1.6, wood, 0, 4)
		end
		kit.Box(p, 4, 84, 30, 1.4, kit.OutlineOf(wood), 0.5, 3)
		return p, sheet
	end
	local left = panel(26, 3)
	local right, sheet = panel(50, 4)
	kit.Circle(left, 5, 46, 4, 7, C.WoodDark, 0.3, 3) -- poignée creuse
	kit.Circle(right, 33, 46, 4, 7, C.WoodDark, 0.3, 3)
	-- branche de sakura peinte
	kit.Line(sheet, 30, 12, 14, 26, 2, C.Brown, 0.1, 3)
	kit.Line(sheet, 20, 21, 12, 14, 1.4, C.Brown, 0.1, 3)
	kit.Line(sheet, 16, 24, 6, 32, 1.4, C.Brown, 0.1, 3)
	for i, p in ipairs({ { 24, 17 }, { 12, 13 }, { 16, 27 }, { 6, 32 }, { 28, 11 } }) do
		local b = kit.Circle(sheet, p[1], p[2], 6 - (i % 2), 6 - (i % 2), C.Pink, 0.05, 5)
		kit.Circle(b, (6 - (i % 2)) / 2, (6 - (i % 2)) / 2, 2, 2, C.PinkDeep, 0, 2)
	end
	-- pétales qui tombent
	for i, p in ipairs({ { 20, 60 }, { 84, 70 } }) do
		local petal = kit.Blob(body, p[1], p[2], 5, 3.5, C.PinkSoft, { Z = 7, Rotation = 30 * i, Thickness = 1 })
		kit.Animate(petal, "Bob", 3, 0.7, i * 1.5)
	end
	return nil
end

-- Portique torii vermillon : linteau relevé, plaque, corde shimenawa et clochette
Art.ToriiGate = function(body, kit, _item)
	local C = kit.C
	local red = Color3.fromRGB(250, 112, 102)
	local black = Color3.fromRGB(84, 58, 84)
	-- piliers
	for _, x in ipairs({ 22, 70 }) do
		kit.Part(body, x, 26, 9, 68, red, { Radius = 2, Z = 2, Shade = 0.2 })
		kit.Part(body, x - 2, 88, 13, 12, black, { Radius = 2, Z = 3 })
		kit.Box(body, x + 2, 30, 2, 56, WHITE, 0.7, 3)
	end
	-- nuki (traverse basse)
	kit.Part(body, 10, 36, 80, 7, red, { Radius = 2, Z = 4, Shade = 0.15 })
	-- plaque centrale
	kit.Part(body, 46, 22, 8, 16, red, { Radius = 1, Z = 3 })
	local plaque = kit.Part(body, 42, 21, 16, 14, black, { Radius = 2, Z = 5, Outline = C.Gold, Thickness = 1.6 })
	kit.Heart(plaque, 8, 7, 7, C.Gold, 0, 2)
	-- shimaki + kasagi (linteau aux bouts relevés)
	kit.Part(body, 8, 17, 84, 7, red, { Radius = 2, Z = 4, Shade = 0.15 })
	kit.Part(body, 10, 8, 80, 10, black, { Radius = 3, Z = 5, Shine = true })
	kit.Part(body, -1, 5, 24, 9, black, { Radius = 4, Z = 4, Rotation = 9 })
	kit.Part(body, 77, 5, 24, 9, black, { Radius = 4, Z = 4, Rotation = -9 })
	-- corde sacrée avec papiers zigzag
	local rope = kit.Part(body, 24, 45, 52, 6, C.Butter, { Radius = -1, Z = 5, Outline = C.Gold })
	for i = 0, 5 do
		kit.Line(rope, 4 + i * 8, 1, 8 + i * 8, 5, 1.2, C.Gold, 0.2, 2)
	end
	for _, x in ipairs({ 32, 68 }) do
		local paper = kit.Group(body, x - 4, 50, 8, 16, 5)
		for k = 0, 3 do
			kit.Part(paper, (k % 2) * 3, k * 4, 5, 4.4, WHITE, { Radius = 0.5, Z = 1, Outline = C.Grey, Thickness = 1, Shade = false })
		end
		kit.Animate(paper, "Sway", 5, 0.8, x)
	end
	-- clochette qui se balance
	local bell = kit.Pivot(body, 50, 50, 6)
	kit.Line(bell, 0, 0, 0, 10, 1.2, C.Red, 0, 1)
	local b = kit.Blob(bell, 0, 15, 11, 11, C.Gold, { Z = 2, Shine = true })
	kit.Box(b, 2, 6.5, 7, 1.2, kit.OutlineOf(C.Gold), 0.3, 2)
	kit.Animate(bell, "Sway", 10, 0.9, 0)
	-- pétales
	for i, p in ipairs({ { 40, 70 }, { 60, 80 }, { 86, 60 } }) do
		local petal = kit.Blob(body, p[1], p[2], 5, 3.5, C.PinkSoft, { Z = 7, Rotation = 40 * i, Thickness = 1 })
		kit.Animate(petal, "Drift", 3, 0.6, i)
	end
	return nil
end

-- Bibliothèque secrète : étagères de livres, un livre-levier penché, clé suspendue, rai de lumière
Art.SecretDoor = function(body, kit, _item)
	local C = kit.C
	-- rai de lumière derrière (porte entrouverte)
	local ray = kit.Box(body, 84, 4, 6, 96, C.Butter, 0, 1)
	kit.Gradient(ray, C.Butter, C.Orange, 90)
	kit.Animate(ray, "Pulse", 0.35, 0.7, 0)
	kit.Part(body, 10, 2, 76, 98, C.WoodDark, { Radius = 4, Z = 2, Shade = 0.12 })
	local back = kit.Part(body, 15, 7, 66, 88, Color3.fromRGB(120, 78, 64), { Radius = 2, Z = 3, Outline = false })
	kit.Gradient(back, Color3.fromRGB(170, 170, 170), WHITE, 90)
	for _, y in ipairs({ 27, 49, 71 }) do
		kit.Part(body, 13, y, 70, 4, C.Wood, { Radius = 1, Z = 5, Shade = false })
	end
	kit.Part(body, 13, 93, 70, 7, C.Wood, { Radius = 1, Z = 5 })
	-- livres (largeur, hauteur, couleur) posés sur chaque planche
	local P = { C.Pink, C.Mint, C.Lilac, C.Sky, C.Butter, C.Peach, C.PinkDeep, C.Blue, C.Leaf }
	local shelves = {
		{ y = 27, books = { { 6, 16, 1 }, { 5, 14, 4 }, { 7, 17, 3 }, { 5, 12, 5 }, { 6, 15, 2 } } },
		{ y = 49, books = { { 6, 16, 8 }, { 7, 14, 6 }, { 5, 15, 9 }, { 6, 13, 1 } } },
		{ y = 71, books = { { 5, 15, 2 }, { 6, 17, 7 }, { 5, 13, 4 }, { 7, 16, 3 }, { 5, 14, 5 }, { 6, 15, 6 } } },
		{ y = 93, books = { { 8, 18, 3 }, { 7, 16, 1 }, { 6, 17, 4 }, { 8, 15, 5 } } },
	}
	for s, shelf in ipairs(shelves) do
		local x = s == 1 and 30 or 17
		for i, bk in ipairs(shelf.books) do
			local color = P[bk[3]]
			local book = kit.Part(body, x, shelf.y - bk[2], bk[1], bk[2], color, { Radius = 1.5, Z = 4, Thickness = 1.2, Shade = 0.15 })
			if (i + s) % 3 == 0 then
				kit.Box(book, 0, 3, bk[1], 1.6, kit.Lighten(color, 0.5), 0, 2)
			end
			x += bk[1] + 1
		end
	end
	-- livre-levier penché (étagère 2)
	local lever = kit.Part(body, 48, 33, 6, 16, C.Red, { Radius = 1.5, Z = 4, Rotation = 18, Thickness = 1.2 })
	kit.Box(lever, 0, 3, 6, 1.6, C.Gold, 0, 2)
	-- petite plante (étagère 1)
	kit.Part(body, 18, 19, 10, 8, C.Orange, { Radius = 2, Z = 4 })
	kit.Blob(body, 20, 15, 6, 9, C.Leaf, { Z = 3, Rotation = -20 })
	kit.Blob(body, 26, 15, 6, 9, C.LeafDark, { Z = 3, Rotation = 20 })
	-- boîte à cœur (étagère 3)
	local box = kit.Part(body, 60, 61, 16, 10, C.PinkSoft, { Radius = 2, Z = 4 })
	kit.Heart(box, 8, 5, 6, C.Heart, 0, 2)
	-- globe (étagère 4)
	kit.Part(body, 63, 88, 12, 5, C.Gold, { Radius = 2, Z = 4 })
	local globe = kit.Blob(body, 69, 80, 14, 14, C.Sky, { Z = 4, Shine = true })
	kit.Blob(globe, 5, 6, 6, 5, C.Leaf, { Z = 2, Outline = false, Shade = false })
	-- clé suspendue
	local key = kit.Pivot(body, 76, 9, 7)
	kit.Circle(key, 0, 0, 2.4, 2.4, C.GreyDark, 0, 1)
	local ring = kit.Part(key, -3.5, 1, 7, 7, WHITE, { T = 1, Radius = -1, Outline = C.Gold, Thickness = 2, Shade = false })
	ring.ZIndex = 2
	kit.Box(key, -0.9, 8, 1.8, 11, C.Gold, 0, 2)
	kit.Box(key, 0.9, 14, 3, 1.6, C.Gold, 0, 2)
	kit.Box(key, 0.9, 17, 2.4, 1.6, C.Gold, 0, 2)
	kit.Animate(key, "Sway", 8, 0.8, 0)
	return nil
end

-- Ascenseur privé : cadre doré, portes argentées au cœur, cadran à aiguille, boutons d'appel
Art.Elevator = function(body, kit, _item)
	local C = kit.C
	local silver = Color3.fromRGB(226, 224, 242)
	kit.Part(body, 10, 2, 80, 98, C.Butter, { Radius = 6, Z = 1, Outline = C.Gold, Shade = 0.15 })
	kit.Part(body, 17, 26, 66, 74, Color3.fromRGB(150, 140, 180), { Radius = 3, Z = 2 })
	-- portes
	for i = 0, 1 do
		local d = kit.Part(body, 19 + i * 31.5, 28, 30.5, 72, silver, { Radius = 1, Z = 3, Outline = Color3.fromRGB(170, 166, 200), Thickness = 1.2, Shade = false })
		kit.Gradient(d, i == 0 and WHITE or Color3.fromRGB(215, 212, 232), i == 0 and Color3.fromRGB(215, 212, 232) or WHITE, 0)
		local inset = kit.Part(d, 4, 6, 22.5, 60, silver, { Radius = 2, Z = 2, Outline = Color3.fromRGB(190, 186, 214), Thickness = 1, Shade = false })
		inset.BackgroundTransparency = 1
		kit.Shine(d, 6 + i * 12, 8, 3, 30, 4, 0.5)
	end
	kit.Heart(body, 50, 56, 22, C.PinkSoft, 0, 4)
	kit.Heart(body, 50, 56.5, 14, C.Pink, 0, 5)
	kit.Box(body, 49.4, 28, 1.2, 72, Color3.fromRGB(150, 140, 180), 0, 6) -- jointure
	-- cadran d'étage
	local dialGroup = kit.Group(body, 32, 4, 36, 21, 3, true)
	kit.Part(dialGroup, 3, 3, 30, 30, C.Cream, { Radius = -1, Outline = C.Gold, Thickness = 2 })
	for i = 0, 4 do
		local a = math.rad(180 + i * 45)
		kit.Circle(body, 50 + math.cos(a) * 11, 22 + math.sin(a) * 11, 2.4, 2.4, i == 2 and C.Heart or C.GreyDark, 0, 5)
	end
	local needle = kit.Pivot(body, 50, 22, 6)
	kit.Line(needle, 0, 0, 0, -10, 1.8, C.Red, 0, 1)
	needle.Rotation = -30
	kit.Animate(needle, "Sway", 55, 0.3, 0)
	kit.Circle(body, 50, 22, 4, 4, C.Gold, 0, 7)
	-- boutons d'appel
	local panel = kit.Part(body, 86, 48, 10, 22, C.Gold, { Radius = 3, Z = 6, Shine = true })
	kit.Circle(panel, 5, 6, 5, 5, C.Cream, 0, 2)
	local lit = kit.Circle(panel, 5, 15, 5, 5, C.Heart, 0, 2)
	kit.Animate(lit, "Pulse", 0.5, 1.5, 0)
	kit.Sparkle(body, 16, 12, 8, WHITE, 0, 6)
	kit.Sparkle(body, 84, 16, 6, WHITE, 0, 6)
	return nil
end

-- Porte en bonbons : tablette de chocolat, glaçage coulant, sucres d'orge, sucettes, bonbon-poignée
Art.CandyDoor = function(body, kit, _item)
	local C = kit.C
	local choco = Color3.fromRGB(160, 104, 86)
	-- porte chocolat
	local door = arch(body, kit, 24, 14, 52, choco, 8, 2, { Shade = 0.15 })
	for row = 0, 3 do
		for col = 0, 1 do
			kit.Part(door, 5 + col * 22, 10 + row * 19, 20, 16, kit.Lighten(choco, 0.12), { Radius = 3, Z = 2, Shade = 0.3, Thickness = 1.2 })
		end
	end
	-- glaçage rose coulant
	kit.Part(body, 20, 8, 60, 12, C.PinkSoft, { Radius = 6, Z = 4, Shade = 0.08 })
	for _, d in ipairs({ { 28, 12 }, { 41, 8 }, { 55, 14 }, { 68, 9 } }) do
		kit.Part(body, d[1], 14, 6, d[2], C.PinkSoft, { Radius = -1, Z = 3, Shade = false })
	end
	for i, s in ipairs({ { 26, 11, 30 }, { 35, 14, -40 }, { 46, 10, 10 }, { 57, 13, 60 }, { 66, 10, -20 }, { 74, 13, 45 } }) do
		local color = ({ C.Mint, C.Butter, C.Sky, C.Lilac, C.Heart, C.Orange })[i]
		kit.Part(body, s[1] - 2, s[2] - 0.8, 4, 1.8, color, { Radius = -1, Z = 5, Outline = false, Shade = false, Rotation = s[3] })
	end
	-- poignée bonbon emballé
	kit.Diamond(body, 63, 60, 6, C.Mint, 0, 5)
	kit.Diamond(body, 75, 60, 6, C.Mint, 0, 5)
	local candy = kit.Blob(body, 69, 60, 10, 8, C.Mint, { Z = 6, Shine = true })
	kit.Box(candy, 3, 0, 1.6, 8, WHITE, 0.3, 2)
	-- sucres d'orge (montants rayés)
	for _, x in ipairs({ 12, 78 }) do
		local post = kit.Part(body, x, 26, 10, 74, WHITE, { Radius = 3, Z = 3, Shade = 0.15, Outline = kit.OutlineOf(C.Pink) })
		local stripes = kit.Group(post, 0, 0, 10, 74, 2, true)
		for i = 0, 7 do
			kit.Box(stripes, -4, 2 + i * 9.5, 18, 3.2, C.Pink, 0, 1).Rotation = -35
		end
		-- sucette au sommet
		local pop = kit.Blob(body, x + 5, 20, 20, 20, C.Pink, { Z = 4, Outline = kit.OutlineOf(C.Pink) })
		kit.Circle(pop, 10, 10, 14, 14, WHITE, 0, 2)
		kit.Circle(pop, 10, 10, 9, 9, x < 50 and C.Mint or C.Lilac, 0, 3)
		kit.Circle(pop, 10, 10, 4, 4, WHITE, 0, 4)
		kit.Circle(pop, 6, 5, 4, 3, WHITE, 0.4, 5)
		kit.Animate(pop, "Spin", 1, x < 50 and 0.12 or -0.12, 0)
	end
	-- boules de gomme au sol
	for i, g in ipairs({ { 28, C.Mint }, { 38, C.Butter }, { 72, C.Lilac } }) do
		local drop = kit.Part(body, g[1] - 5, 91, 10, 9, g[2], { Radius = 4, Z = 7, Shine = true })
		kit.Round(drop, 5)
		if i == 2 then
			kit.Animate(drop, "Bob", 0.8, 1, 0)
		end
	end
	kit.Heart(body, 50, 46, 12, C.Heart, 0, 5)
	return nil
end

-- Portail des rêves : arche nacrée, tourbillon étoilé qui tourne, cœur lumineux, nuages
Art.DreamPortal = function(body, kit, _item)
	local C = kit.C
	local frame = arch(body, kit, 10, 4, 80, C.LilacSoft, 40, 1, { Outline = C.Gold, Thickness = 2.2, Shade = 0.12 })
	kit.Gradient(frame, WHITE, C.PinkSoft, 90)
	local portal = arch(body, kit, 19, 13, 62, C.Purple, 31, 2, { Outline = kit.Lighten(C.Gold, 0.3), Thickness = 2, Shade = false })
	kit.Gradient(portal, Color3.fromRGB(110, 70, 200), Color3.fromRGB(255, 130, 200), 90)
	-- tourbillon (bras en spirale) qui tourne
	local swirl = kit.Pivot(body, 50, 56, 3)
	local colors = { C.PinkSoft, C.Sky, WHITE, C.LilacSoft, C.PinkSoft, C.Sky }
	for i = 0, 5 do
		local a0 = math.rad(i * 60)
		local pts = {}
		for k = 0, 2 do
			local r = 6 + k * 11
			local a = a0 + math.rad(k * 38)
			table.insert(pts, { math.cos(a) * r, math.sin(a) * r })
		end
		for k = 1, 2 do
			kit.Line(swirl, pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2], 6 - k * 1.5, colors[i + 1], 0.15 + k * 0.15, 1)
		end
	end
	kit.Animate(swirl, "Spin", 1, 0.18, 0)
	local halo = kit.Circle(body, 50, 56, 26, 26, C.PinkSoft, 0.55, 4)
	kit.Animate(halo, "Pulse", 0.3, 1.2, 0)
	local core = kit.Circle(body, 50, 56, 14, 14, WHITE, 0.1, 5)
	kit.Animate(core, "Breathe", 0.1, 1.5, 0)
	kit.Heart(body, 50, 56, 8, C.Heart, 0, 6)
	-- étoiles dans le portail
	for i, s in ipairs({ { 34, 30, 6 }, { 66, 36, 5 }, { 36, 80, 5 }, { 64, 76, 7 } }) do
		local star = kit.Sparkle(body, s[1], s[2], s[3], WHITE, 0, 5)
		kit.Animate(star, "Bob", 2, 0.9, i * 1.3)
	end
	-- lune sur la clé de voûte
	kit.Circle(body, 50, 6, 14, 14, C.Butter, 0, 6)
	kit.Circle(body, 54, 4, 11, 11, C.LilacSoft, 0, 7)
	-- étoiles autour de l'arche
	for i, s in ipairs({ { 6, 20, 9, C.Butter }, { 94, 30, 8, C.Pink }, { 96, 8, 6, C.Sky }, { 4, 52, 6, C.Lilac } }) do
		local star = kit.Sparkle(body, s[1], s[2], s[3], s[4], 0, 6)
		kit.Animate(star, "Breathe", 0.2, 1.3, i)
	end
	-- nuages au pied
	kit.Cloud(body, 14, 101, 30, WHITE, 0, 8)
	kit.Cloud(body, 86, 101, 28, WHITE, 0, 8)
	kit.Cloud(body, 50, 102, 22, C.PinkMist, 0, 8)
	return { Glow = Color3.fromRGB(190, 140, 255) }
end

return Art
