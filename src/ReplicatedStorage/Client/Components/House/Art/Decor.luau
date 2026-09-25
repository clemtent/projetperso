--[[
	Decor (ModuleScript) — dessins 🖼️ déco
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Decor
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

----------------------------------------------------------------------
-- Petits outils partagés
----------------------------------------------------------------------

-- Étoile dodue à 5 branches (5 pilules + un rond) ; renvoie son conteneur
local function star(kit, parent, cx, cy, r, color, z, t)
	local holder = kit.Group(parent, cx - r, cy - r, r * 2, r * 2, z)
	local th = r * 0.42
	local len = r - th / 2
	for i = 0, 4 do
		local a = math.rad(-90 + i * 72)
		kit.Line(holder, r, r, r + math.cos(a) * len, r + math.sin(a) * len, th, color, t, 1)
	end
	kit.Circle(holder, r, r, r * 0.95, r * 0.95, color, t, 1)
	return holder
end

-- Étoile avec contour (une étoile foncée un peu plus grande derrière)
local function outlinedStar(kit, parent, cx, cy, r, color, z)
	local holder = kit.Group(parent, cx - r - 2, cy - r - 2, r * 2 + 4, r * 2 + 4, z)
	star(kit, holder, r + 2, r + 2, r + 1.6, kit.OutlineOf(color), 1)
	star(kit, holder, r + 2, r + 2, r, color, 2)
	return holder
end

-- Croissant de lune (ronds alignés sur un arc, ouvert vers la droite)
local function crescent(kit, parent, cx, cy, r, color, z, count)
	local holder = kit.Group(parent, cx - r, cy - r, r * 2, r * 2, z)
	local n = count or 9
	local arc = r * 0.6
	for i = 0, n - 1 do
		local k = i / (n - 1) * 2 - 1 -- -1..1
		local a = math.rad(k * 145)
		local d = r * (0.8 - 0.55 * math.abs(k) ^ 1.4)
		kit.Circle(holder, r - math.cos(a) * arc, r + math.sin(a) * arc, d, d, color, 0, 1)
	end
	return holder
end

-- Triangle rectangle net (carré tourné dans un cadre qui découpe) ;
-- `corner` = coin de l'angle droit rempli : "TL", "TR", "BL", "BR"
local function wedge(kit, parent, x, y, w, h, corner, color, t, z)
	local clip = kit.Group(parent, x, y, w, h, z, true)
	local rx = if corner == "TL" or corner == "BL" then 0 else w
	local ry = if corner == "TL" or corner == "TR" then 0 else h
	local x1, y1 = w - rx, ry
	local x2, y2 = rx, h - ry
	local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
	local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	local dx, dy = (x2 - x1) / len, (y2 - y1) / len
	local nx, ny = -dy, dx
	if nx * (rx - mx) + ny * (ry - my) < 0 then
		nx, ny = -nx, -ny
	end
	local s = (w + h) * 2
	local square = kit.Box(clip, 0, 0, s, s, color, t, 1)
	square.AnchorPoint = Vector2.new(0.5, 0.5)
	square.Position = UDim2.fromOffset(mx + nx * s / 2, my + ny * s / 2)
	square.Rotation = math.deg(math.atan2(dy, dx))
	return clip
end

-- Fanion pointe en bas, bords nets (2 demi-triangles)
local function pennant(kit, parent, cx, top, w, h, color, z)
	local holder = kit.Group(parent, cx - w / 2, top, w, h, z)
	wedge(kit, holder, 0, 0, w / 2 + 0.3, h, "TR", color, 0, 1)
	wedge(kit, holder, w / 2 - 0.3, 0, w / 2 + 0.3, h, "TL", color, 0, 1)
	return holder
end

-- Petit nœud (2 boucles + nœud central)
local function bow(kit, parent, cx, cy, w, color, z)
	local holder = kit.Group(parent, cx - w / 2, cy - w / 2, w, w, z)
	kit.Blob(holder, w * 0.27, w * 0.5, w * 0.5, w * 0.42, color, { Rotation = -12, Z = 1, Thickness = 1.2 })
	kit.Blob(holder, w * 0.73, w * 0.5, w * 0.5, w * 0.42, color, { Rotation = 12, Z = 1, Thickness = 1.2 })
	kit.Blob(holder, w * 0.5, w * 0.5, w * 0.26, w * 0.3, kit.Darken(color, 0.08), { Z = 2, Thickness = 1.2 })
	return holder
end

-- Clou + ficelle en V pour accrocher un cadre
local function hanger(kit, parent, cx, nailY, x1, x2, attachY, z)
	local C = kit.C
	kit.Line(parent, x1, attachY, cx, nailY, 1.2, C.WoodDark, 0, z)
	kit.Line(parent, cx, nailY, x2, attachY, 1.2, C.WoodDark, 0, z)
	kit.Circle(parent, cx, nailY, 4.5, 4.5, C.GreyDark, 0, (z or 1) + 1)
end

-- Fil qui pend en arc (segments) ; renvoie la fonction y(x)
local function sagString(kit, parent, x1, x2, y0, sag, segments, color, thick, z)
	local function yAt(x)
		local k = (x - x1) / (x2 - x1)
		return y0 + math.sin(k * math.pi) * sag
	end
	local step = (x2 - x1) / segments
	for i = 0, segments - 1 do
		local a = x1 + i * step
		local b = a + step
		kit.Line(parent, a, yAt(a), b, yAt(b), thick, color, 0, z)
	end
	return yAt
end

----------------------------------------------------------------------
-- Dessins
----------------------------------------------------------------------

-- Tapis tricoté : ovale à anneaux pastel, points de tricot, franges et pelote
Art.KnittedRug = function(body, kit, _item)
	local C = kit.C
	local rose = Color3.fromRGB(255, 160, 196)
	-- franges aux deux bouts
	for _, side in ipairs({ -1, 1 }) do
		for i = -2, 2 do
			local a = math.rad(i * 14)
			local x = 50 + side * 49 * math.cos(a)
			local y = 84 + 15 * math.sin(a)
			kit.Line(body, x, y, x + side * 6, y + 1, 2, C.Cream, 0, 1)
		end
	end
	kit.Blob(body, 50, 84, 100, 30, rose, { Z = 2, Shade = 0.08 })
	kit.Blob(body, 50, 84, 82, 23, C.Cream, { Z = 3, Outline = false, Shade = false })
	kit.Blob(body, 50, 84, 66, 18, Color3.fromRGB(170, 230, 205), { Z = 4, Outline = false, Shade = false })
	kit.Blob(body, 50, 84, 46, 12, Color3.fromRGB(210, 190, 250), { Z = 5, Outline = false, Shade = false })
	kit.Blob(body, 50, 84, 26, 6.5, C.PinkSoft, { Z = 6, Outline = false, Shade = false })
	-- points de tricot sur l'anneau extérieur
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		kit.Circle(body, 50 + math.cos(a) * 45.5, 84 + math.sin(a) * 13.3, 3, 1.8, C.White, 0.35, 3)
	end
	-- pelote de laine et aiguilles
	kit.Line(body, 70, 84, 80, 78, 1.2, C.PinkDeep, 0.2, 7)
	kit.Line(body, 76, 64, 92, 76, 1.6, C.WoodLight, 0, 7)
	kit.Line(body, 90, 63, 78, 78, 1.6, C.WoodLight, 0, 7)
	local ball = kit.Blob(body, 84, 76, 17, 15, C.Pink, { Z = 8, Shine = true })
	kit.Line(ball, 3, 5, 12, 12, 1.2, C.PinkDeep, 0.3, 2)
	kit.Line(ball, 6, 2, 15, 9, 1.2, C.PinkDeep, 0.3, 2)
	kit.Circle(body, 76, 64, 3.5, 3.5, C.Pink, 0, 7)
	kit.Circle(body, 90, 63, 3.5, 3.5, C.Mint, 0, 7)
	return { Flat = true }
end

-- Autocollant cœur : bord blanc découpé, cœur brillant avec un petit visage
Art.HeartSticker = function(body, kit, _item)
	local C = kit.C
	kit.Heart(body, 50, 52, 92, kit.OutlineOf(C.Pink), 0, 2)
	kit.Heart(body, 50, 52, 88, C.White, 0, 3)
	kit.Heart(body, 50, 52, 74, C.Pink, 0, 4)
	kit.Heart(body, 47, 49, 52, Color3.fromRGB(255, 160, 200), 0.35, 5)
	kit.Shine(body, 22, 30, 14, 7, 7, 0.2).Rotation = -40
	kit.Circle(body, 34, 42, 4, 4, C.White, 0.2, 7)
	kit.Face(body, 50, 58, 34, { Eyes = "big", Mouth = "cat", Z = 8 })
	kit.Sparkle(body, 86, 20, 12, C.Butter, 0, 9)
	kit.Sparkle(body, 12, 82, 9, C.White, 0, 9)
	return { WallShadow = Vector2.new(0.85, 0.8) }
end

-- Nœud géant : deux grandes boucles à pois, rubans qui pendent
Art.GiantBow = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 150, 196)
	local deep = kit.Darken(pink, 0.12)
	kit.Part(body, 30, 50, 14, 42, deep, { Radius = 5, Z = 2, Rotation = 22 })
	kit.Part(body, 56, 50, 14, 42, deep, { Radius = 5, Z = 2, Rotation = -22 })
	for _, side in ipairs({ -1, 1 }) do
		local loop = kit.Blob(body, 50 + side * 24, 40, 46, 36, pink, { Z = 3, Rotation = side * 14, Shine = side < 0 })
		kit.Blob(loop, 23 - side * 9, 18, 14, 16, deep, { Z = 2, Outline = false, Shade = false, T = 0.2 })
		for _, dot in ipairs({ { 12, 10 }, { 30, 25 }, { 34, 8 } }) do
			local dx = if side < 0 then dot[1] else 46 - dot[1]
			kit.Circle(loop, dx, dot[2], 5, 5, C.White, 0.1, 3)
		end
	end
	local knot = kit.Part(body, 40, 29, 20, 23, deep, { Radius = 8, Z = 5, Shine = true })
	kit.Heart(knot, 10, 12, 8, C.White, 0.1, 3)
	return { WallShadow = Vector2.new(0.9, 0.7) }
end

-- Calendrier mural : anneaux, bandeau rose, grille des jours, un jour en cœur
Art.WallCalendar = function(body, kit, _item)
	local C = kit.C
	hanger(kit, body, 50, 6, 32, 68, 20, 1)
	local page = kit.Part(body, 18, 18, 64, 72, C.White, { Radius = 6, Z = 2 })
	kit.Part(body, 22, 88, 58, 5, kit.Darken(C.Cream, 0.04), { Radius = 3, Z = 1 })
	local head = kit.Part(page, 0, 0, 64, 22, C.Pink, { Radius = 6, Z = 2, Shade = 0.1 })
	kit.Text(head, "JUNE", 32, 13, 11, C.White, 3)
	for _, x in ipairs({ 14, 26, 38, 50 }) do
		kit.Part(page, x - 2, -5, 4, 9, C.GreyDark, { Radius = -1, Z = 4, Outline = false, Shade = false })
	end
	for row = 0, 2 do
		for col = 0, 4 do
			local x = 6 + col * 11
			local y = 28 + row * 12
			if row == 1 and col == 3 then
				kit.Heart(page, x + 4, y + 4.5, 11, C.Heart, 0, 4)
			else
				local cell = kit.Box(page, x, y, 8, 8, if (row + col) % 4 == 0 then C.MintSoft else C.PinkMist, 0, 3)
				kit.Round(cell, 2)
			end
		end
	end
	return { WallShadow = Vector2.new(0.66, 0.72) }
end

-- Tableau encadré : cadre doré, paysage (ciel, soleil souriant, collines, nuage)
Art.FramedPicture = function(body, kit, _item)
	local C = kit.C
	hanger(kit, body, 50, 2, 26, 74, 16, 1)
	local frame = kit.Part(body, 6, 14, 88, 74, C.Gold, { Radius = 6, Z = 2, Shine = true, Thickness = 2 })
	kit.Part(frame, 7, 7, 74, 60, C.Cream, { Radius = 3, Z = 2, Shade = false })
	local view = kit.Group(frame, 11, 11, 66, 52, 3, true)
	local sky = kit.Box(view, 0, 0, 66, 52, C.Sky, 0, 1)
	kit.Gradient(sky, Color3.fromRGB(190, 225, 255), Color3.fromRGB(255, 225, 240))
	local sun = kit.Circle(view, 48, 16, 16, 16, C.Butter, 0, 2)
	kit.Face(sun, 8, 8.5, 12, { Eyes = "happy", Mouth = "none", Z = 3 })
	kit.Cloud(view, 20, 22, 20, C.White, 0.05, 2)
	kit.Blob(view, 14, 58, 60, 34, C.Mint, { Z = 3, Outline = false, Shade = 0.1 })
	kit.Blob(view, 54, 60, 64, 30, C.Leaf, { Z = 4, Outline = false, Shade = 0.1 })
	kit.Circle(view, 30, 44, 4, 4, C.Pink, 0, 5)
	kit.Circle(view, 40, 49, 3.5, 3.5, C.White, 0, 5)
	kit.Circle(view, 52, 47, 3.5, 3.5, C.Pink, 0, 5)
	for _, p in ipairs({ { 4, 4 }, { 84, 4 }, { 4, 70 }, { 84, 70 } }) do
		kit.Circle(frame, p[1], p[2], 5, 5, kit.Lighten(C.Gold, 0.4), 0, 4)
	end
	return { WallShadow = Vector2.new(0.88, 0.76) }
end

-- Bouquet de ballons : 3 ballons ronds + 1 cœur, ficelles nouées par un nœud
Art.Balloons = function(body, kit, _item)
	local C = kit.C
	local tieX, tieY = 50, 90
	local specs = {
		{ x = 28, y = 36, color = C.Pink, face = true, z = 4 },
		{ x = 54, y = 22, color = C.Sky, z = 2 },
		{ x = 76, y = 42, color = C.Butter, z = 3 },
	}
	for index, s in ipairs(specs) do
		local p = kit.Pivot(body, tieX, tieY, s.z)
		local bx, by = s.x - tieX, s.y - tieY
		kit.Line(p, 0, 0, bx, by + 18, 1, C.Ink, 0.45, 1)
		kit.Diamond(p, bx, by + 18, 5, kit.Darken(s.color, 0.1), 0, 2)
		local balloon = kit.Blob(p, bx, by, 32, 37, s.color, { Z = 3, Shine = true })
		kit.Circle(balloon, 24, 11, 3, 3, C.White, 0.3, 3)
		if s.face then
			kit.Face(balloon, 16, 21, 18, { Eyes = "happy", Mouth = "smile", Z = 4 })
		end
		kit.Animate(p, "Sway", 3, 0.7, index * 1.7)
	end
	local hp = kit.Pivot(body, tieX, tieY, 5)
	kit.Line(hp, 0, 0, 12, -26, 1, C.Ink, 0.45, 1)
	kit.Heart(hp, 13, -34, 18, C.Heart, 0, 2)
	kit.Shine(hp, 7, -40, 4, 3, 3, 0.3)
	kit.Animate(hp, "Sway", 4, 0.9, 4.2)
	bow(kit, body, tieX, tieY, 13, C.PinkDeep, 8)
	return { WallShadow = Vector2.new(0, 0) }
end

-- Pendule de cheminée : boîtier en bois arrondi, cadran crème, aiguilles
Art.MantelClock = function(body, kit, _item)
	local C = kit.C
	for _, x in ipairs({ 22, 72 }) do
		kit.Blob(body, x + 3, 96, 10, 8, C.Gold, { Z = 1 })
	end
	kit.Part(body, 12, 82, 76, 13, C.WoodDark, { Radius = 5, Z = 2 })
	kit.Part(body, 18, 44, 64, 42, C.Wood, { Radius = 8, Z = 3 })
	kit.Blob(body, 50, 46, 64, 50, C.Wood, { Z = 2, Shine = true })
	kit.Circle(body, 50, 19, 7, 7, C.Gold, 0, 4)
	local dial = kit.Blob(body, 50, 52, 38, 38, C.Cream, { Z = 5, Outline = C.Gold, Thickness = 3 })
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local r = if i % 3 == 0 then 3 else 1.8
		kit.Circle(dial, 19 + math.sin(a) * 14, 19 - math.cos(a) * 14, r, r, C.Ink, 0.1, 2)
	end
	kit.Line(dial, 19, 19, 19, 9, 2.2, C.Ink, 0, 3)
	local minute = kit.Pivot(dial, 19, 19, 3)
	kit.Line(minute, 0, 0, 9, 5, 1.6, C.PinkDeep, 0, 1)
	kit.Animate(minute, "Spin", 0, 0.02, 0)
	kit.Circle(dial, 19, 19, 4, 4, C.Gold, 0, 4)
	kit.Heart(body, 50, 88.5, 7, C.Butter, 0, 4)
	return nil
end

-- Poster carte du monde : papier penché, océan, continents, trajet en pointillés
Art.MapPoster = function(body, kit, _item)
	local C = kit.C
	local paper = kit.Part(body, 6, 12, 88, 74, C.Cream, { Radius = 4, Z = 2, Rotation = -3 })
	local sea = kit.Part(paper, 5, 5, 78, 64, Color3.fromRGB(175, 222, 255), { Radius = 3, Z = 2, Outline = Color3.fromRGB(140, 190, 230), Thickness = 1, Shade = 0.08 })
	kit.Box(sea, 2, 21, 74, 1, C.White, 0.5, 2)
	kit.Box(sea, 2, 43, 74, 1, C.White, 0.5, 2)
	local land = Color3.fromRGB(150, 215, 140)
	local sand = Color3.fromRGB(250, 220, 150)
	local opts = { Z = 3, Thickness = 1, Outline = C.LeafDark }
	kit.Blob(sea, 15, 18, 20, 16, land, opts) -- Amérique du Nord
	kit.Blob(sea, 21, 42, 11, 20, land, { Z = 3, Thickness = 1, Outline = C.LeafDark, Rotation = -15 })
	kit.Blob(sea, 39, 17, 10, 9, land, opts) -- Europe
	kit.Blob(sea, 40, 36, 14, 20, sand, { Z = 3, Thickness = 1, Outline = C.WoodDark }) -- Afrique
	kit.Blob(sea, 57, 19, 28, 17, land, opts) -- Asie
	kit.Blob(sea, 64, 48, 13, 9, sand, { Z = 3, Thickness = 1, Outline = C.WoodDark }) -- Australie
	-- trajet en pointillés vers un cœur
	for i = 0, 6 do
		local k = i / 6
		kit.Circle(sea, 17 + k * 44, 22 - math.sin(k * math.pi) * 12 + k * 4, 2, 2, C.PinkDeep, 0, 4)
	end
	kit.Heart(sea, 64, 26, 9, C.Heart, 0, 5)
	kit.Sparkle(sea, 8, 58, 9, C.Butter, 0, 4)
	for _, x in ipairs({ 2, 80 }) do
		local tape = kit.Box(body, x, 7, 18, 8, C.Pink, 0.3, 4)
		tape.Rotation = if x < 50 then -30 else 30
	end
	return { WallShadow = Vector2.new(0.9, 0.78) }
end

-- Guirlande de fanions : fil qui pend, fanions pastel avec pois et repli
Art.PartyBunting = function(body, kit, _item)
	local C = kit.C
	local colors = { C.Pink, C.Butter, C.Mint, C.Sky, C.Lilac, Color3.fromRGB(255, 180, 140), C.Pink }
	local yAt = sagString(kit, body, -2, 102, 30, 16, 6, C.Ink, 1.4, 3)
	kit.Circle(body, -2, 30, 4, 4, C.GreyDark, 0, 4)
	kit.Circle(body, 102, 30, 4, 4, C.GreyDark, 0, 4)
	for i = 1, #colors do
		local x = -2 + (i - 0.5) / #colors * 104
		local y = yAt(x) - 1
		local color = colors[i]
		local flag = pennant(kit, body, x, y, 13, 20, color, 2)
		kit.Box(flag, 0, 0, 13, 3, kit.Darken(color, 0.12), 0, 2)
		kit.Circle(flag, 6.5, 8, 3.5, 3.5, C.White, 0.2, 3)
	end
	return { WallShadow = Vector2.new(0, 0) }
end

-- Miroir cœur : cadre cœur rose, verre bleuté avec reflets, petit nœud
Art.HeartMirror = function(body, kit, _item)
	local C = kit.C
	kit.Heart(body, 50, 54, 96, kit.OutlineOf(C.Pink), 0, 2)
	kit.Heart(body, 50, 54, 92, C.Pink, 0, 3)
	kit.Heart(body, 50, 54.5, 78, C.PinkSoft, 0, 4)
	kit.Heart(body, 50, 55, 70, Color3.fromRGB(205, 232, 255), 0, 5)
	kit.Heart(body, 50, 57, 50, Color3.fromRGB(225, 242, 255), 0, 6)
	kit.Line(body, 28, 50, 40, 38, 5, C.White, 0.3, 7)
	kit.Line(body, 32, 60, 50, 42, 3, C.White, 0.45, 7)
	local glint = kit.Sparkle(body, 64, 42, 10, C.White, 0, 8)
	kit.Animate(glint, "Breathe", 0.25, 1.2, 0)
	bow(kit, body, 50, 20, 20, C.PinkDeep, 9)
	kit.Heart(body, 50, 83, 7, C.PinkDeep, 0, 8)
	return { WallShadow = Vector2.new(0.9, 0.85) }
end

-- Pile de cadeaux : 3 paquets pastel avec rubans et nœuds
Art.GiftPile = function(body, kit, _item)
	local C = kit.C
	local function gift(x, y, w, h, color, ribbon, z, dots)
		local box = kit.Part(body, x, y, w, h, color, { Radius = 4, Z = z })
		if dots then
			for _, d in ipairs({ { 0.2, 0.3 }, { 0.78, 0.25 }, { 0.25, 0.75 }, { 0.8, 0.72 } }) do
				kit.Circle(box, d[1] * w, d[2] * h + 3, 3.5, 3.5, C.White, 0.3, 2)
			end
		end
		kit.Box(box, w / 2 - 3, 0, 6, h, ribbon, 0, 3)
		kit.Part(body, x - 2, y - 2, w + 4, 9, kit.Lighten(color, 0.15), { Radius = 3, Z = z + 1, Shine = true })
		kit.Box(body, x + w / 2 - 3, y - 2, 6, 9, ribbon, 0, z + 2)
		bow(kit, body, x + w / 2, y - 6, 16, ribbon, z + 3)
	end
	gift(10, 58, 50, 40, C.Pink, C.Mint, 2, true)
	gift(58, 70, 32, 28, C.Lilac, C.Butter, 2)
	gift(20, 30, 30, 26, C.MintSoft, C.PinkDeep, 6)
	kit.Sparkle(body, 80, 50, 10, C.Butter, 0, 9)
	return nil
end

-- Amphore : panse ronde, col, anses, frise grecque et pied
Art.Vase = function(body, kit, _item)
	local C = kit.C
	local clay = Color3.fromRGB(245, 170, 140)
	local band = C.Cream
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(body, 50 + side * 17 - 7, 20, 14, 26, clay, { Radius = -1, Z = 1, T = 1, Thickness = 3.5, Outline = kit.Darken(clay, 0.12), Shade = false })
	end
	kit.Part(body, 36, 90, 28, 8, kit.Darken(clay, 0.1), { Radius = 3, Z = 2 })
	kit.Part(body, 42, 84, 16, 8, clay, { Radius = 2, Z = 3 })
	kit.Blob(body, 50, 60, 56, 50, clay, { Z = 4, Shine = true })
	kit.Part(body, 40, 16, 20, 26, clay, { Radius = 4, Z = 3 })
	kit.Part(body, 34, 12, 32, 8, kit.Lighten(clay, 0.1), { Radius = -1, Z = 5 })
	local stripe = kit.Part(body, 23, 54, 54, 12, band, { Radius = 3, Z = 5, Thickness = 1.2, Shade = false })
	for i = 0, 5 do
		kit.Diamond(stripe, 5 + i * 8.8, 6, 4.5, if i % 2 == 0 then C.PinkDeep else clay, 0, 2)
	end
	kit.Box(body, 28, 72, 44, 2, kit.Darken(clay, 0.15), 0.3, 5)
	kit.Box(body, 29, 44, 42, 2, kit.Darken(clay, 0.15), 0.3, 5)
	return nil
end

-- Étoiles phosphorescentes : grande étoile souriante, petites étoiles, lune
Art.GlowStars = function(body, kit, _item)
	local C = kit.C
	local glow = Color3.fromRGB(236, 255, 190)
	local halo = kit.Circle(body, 42, 48, 60, 60, glow, 0.75, 1)
	kit.Animate(halo, "Pulse", 0.2, 0.8, 0)
	kit.Circle(halo, 30, 30, 40, 40, glow, 0.5, 1)
	local big = outlinedStar(kit, body, 42, 50, 24, glow, 3)
	kit.Face(big, 26, 28, 18, { Eyes = "happy", Mouth = "smile", Z = 4 })
	local moon = crescent(kit, body, 78, 24, 16, Color3.fromRGB(255, 245, 180), 3, 8)
	kit.Animate(moon, "Bob", 1.5, 0.8, 1)
	for index, s in ipairs({ { 14, 18, 8 }, { 82, 70, 10 }, { 22, 84, 7 } }) do
		local small = star(kit, body, s[1], s[2], s[3], if index % 2 == 0 then glow else Color3.fromRGB(210, 250, 230), 2)
		kit.Animate(small, "Breathe", 0.08, 1.3, index * 1.1)
	end
	kit.Sparkle(body, 90, 44, 8, C.White, 0, 3)
	return { Glow = glow, WallShadow = Vector2.new(0, 0) }
end

-- Attrape-rêves : cercle rose, toile étoilée, perles et plumes qui se balancent
Art.DreamCatcher = function(body, kit, _item)
	local C = kit.C
	local cx, cy, r = 50, 34, 25
	kit.Line(body, cx, cy - r, cx, -2, 1.2, C.WoodDark, 0, 1)
	kit.Circle(body, cx, -2, 4.5, 4.5, C.GreyDark, 0, 2)
	-- toile (octogramme)
	local pts = {}
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 - math.pi / 2
		pts[i] = { cx + math.cos(a) * (r - 1), cy + math.sin(a) * (r - 1) }
	end
	for i = 0, 7 do
		local a, b = pts[i], pts[(i + 3) % 8]
		kit.Line(body, a[1], a[2], b[1], b[2], 1, C.White, 0.15, 3)
	end
	kit.Part(body, cx - r, cy - r, r * 2, r * 2, C.White, { Radius = -1, T = 1, Outline = kit.OutlineOf(C.Pink), Thickness = 6, Shade = false, Z = 4 })
	kit.Part(body, cx - r, cy - r, r * 2, r * 2, C.White, { Radius = -1, T = 1, Outline = C.Pink, Thickness = 3.4, Shade = false, Z = 5 })
	kit.Heart(body, cx, cy, 9, C.PinkDeep, 0, 6)
	for _, b in ipairs({ { cx - r, cy, C.Mint }, { cx + r, cy, C.Butter } }) do
		kit.Circle(body, b[1], b[2], 6, 6, b[3], 0, 6)
	end
	-- plumes suspendues
	local feathers = {
		{ a = 130, len = 12, color = C.Lilac },
		{ a = 90, len = 18, color = C.Pink },
		{ a = 50, len = 12, color = C.Mint },
	}
	for index, f in ipairs(feathers) do
		local a = math.rad(f.a)
		local p = kit.Pivot(body, cx + math.cos(a) * r, cy + math.sin(a) * r, 3)
		kit.Line(p, 0, 0, 0, f.len, 1, C.WoodDark, 0, 1)
		kit.Circle(p, 0, f.len - 3, 5, 5, C.Butter, 0, 3)
		local feather = kit.Blob(p, 0, f.len + 12, 10, 26, f.color, { Z = 2, Shine = true })
		kit.Line(feather, 5, 3, 5, 26, 1, kit.OutlineOf(f.color), 0.3, 2)
		kit.Line(feather, 5, 12, 9, 9, 1, C.White, 0.3, 2)
		kit.Line(feather, 5, 18, 1, 15, 1, C.White, 0.3, 2)
		kit.Animate(p, "Sway", 6, 0.9, index * 1.3)
	end
	return { WallShadow = Vector2.new(0, 0) }
end

-- Coucou : chalet en bois, toit en planches, oiseau à la porte, balancier et pommes de pin
Art.CuckooClock = function(body, kit, _item)
	local C = kit.C
	-- chaînes et poids
	for _, w in ipairs({ { 37, 84 }, { 63, 90 } }) do
		kit.Line(body, w[1], 70, w[1], w[2] - 6, 1.2, C.GreyDark, 0, 1)
		local cone = kit.Blob(body, w[1], w[2], 8, 13, C.Brown, { Z = 2 })
		kit.Line(cone, 1, 4, 7, 4, 1, kit.Darken(C.Brown, 0.25), 0.2, 2)
		kit.Line(cone, 1, 8, 7, 8, 1, kit.Darken(C.Brown, 0.25), 0.2, 2)
	end
	-- balancier
	local pendulum = kit.Pivot(body, 50, 70, 1)
	kit.Line(pendulum, 0, 0, 0, 20, 2, C.Gold, 0, 1)
	local bob = kit.Blob(pendulum, 0, 22, 11, 11, C.Gold, { Z = 2, Shine = true })
	kit.Heart(bob, 5.5, 5.8, 5, C.White, 0.2, 3)
	kit.Animate(pendulum, "Sway", 12, 1.3, 0)
	-- corps + pignon
	kit.Part(body, 26, 32, 48, 42, C.Wood, { Radius = 5, Z = 3 })
	kit.Triangle(body, 50, 12, 50, 24, C.WoodLight, 3, nil, 10)
	local left = kit.Line(body, 16, 38, 51, 9, 9, C.Brown, 0, 4)
	kit.Stroke(left, kit.OutlineOf(C.Brown), 1.4)
	local right = kit.Line(body, 49, 9, 84, 38, 9, C.Brown, 0, 4)
	kit.Stroke(right, kit.OutlineOf(C.Brown), 1.4)
	kit.Blob(body, 44, 7, 10, 6, C.Leaf, { Z = 5, Rotation = -25 })
	kit.Blob(body, 56, 7, 10, 6, C.Leaf, { Z = 5, Rotation = 25 })
	kit.Circle(body, 50, 8, 5, 5, C.Heart, 0, 6)
	-- porte et oiseau
	kit.Part(body, 43, 18, 14, 15, C.Ink, { Radius = 6, Z = 5, Outline = C.WoodDark })
	local bird = kit.Group(body, 40, 16, 20, 20, 6)
	local head = kit.Blob(bird, 10, 11, 12, 11, C.Butter, { Z = 1 })
	kit.Circle(head, 3.5, 4.5, 2.2, 2.6, C.Ink, 0, 2)
	kit.Circle(head, 8.5, 4.5, 2.2, 2.6, C.Ink, 0, 2)
	kit.Circle(head, 2.5, 7.5, 2.5, 1.6, C.Blush, 0.3, 2)
	kit.Circle(head, 9.5, 7.5, 2.5, 1.6, C.Blush, 0.3, 2)
	kit.Diamond(bird, 10, 14, 3.5, C.Orange, 0, 2)
	kit.Animate(bird, "Bob", 1.2, 0.9, 0)
	-- cadran
	local dial = kit.Blob(body, 50, 54, 28, 28, C.Cream, { Z = 5, Outline = C.WoodDark, Thickness = 2 })
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		kit.Circle(dial, 14 + math.sin(a) * 10, 14 - math.cos(a) * 10, 2.4, 2.4, C.Ink, 0.1, 2)
	end
	kit.Line(dial, 14, 14, 14, 6, 1.8, C.Ink, 0, 3)
	kit.Line(dial, 14, 14, 20, 16, 1.6, C.PinkDeep, 0, 3)
	kit.Circle(dial, 14, 14, 3, 3, C.Gold, 0, 4)
	return { WallShadow = Vector2.new(0.7, 0.7) }
end

-- Globe de bureau : sphère bleue et continents, anneau doré, pied en bois
Art.DeskGlobe = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 94, 44, 10, C.WoodDark, { Z = 1 })
	kit.Part(body, 36, 84, 28, 10, C.Wood, { Radius = 4, Z = 2, Shine = true })
	kit.Part(body, 46, 72, 8, 14, C.Gold, { Radius = 2, Z = 1 })
	kit.Part(body, 17, 11, 66, 66, C.White, { Radius = -1, T = 1, Outline = kit.OutlineOf(C.Gold), Thickness = 5, Shade = false, Z = 2 })
	kit.Part(body, 17, 11, 66, 66, C.White, { Radius = -1, T = 1, Outline = C.Gold, Thickness = 3, Shade = false, Z = 3 })
	local globe = kit.Blob(body, 50, 44, 56, 56, Color3.fromRGB(150, 205, 250), { Z = 4 })
	local lands = kit.Group(globe, 0, 0, 56, 56, 2)
	local land = Color3.fromRGB(140, 215, 140)
	local o = { Z = 1, Thickness = 1.2, Outline = C.LeafDark, Shade = false }
	kit.Blob(lands, 18, 17, 18, 13, land, o)
	kit.Blob(lands, 20, 34, 10, 16, land, { Z = 1, Thickness = 1.2, Outline = C.LeafDark, Shade = false, Rotation = -20 })
	kit.Blob(lands, 38, 20, 16, 12, land, o)
	kit.Blob(lands, 38, 38, 12, 12, Color3.fromRGB(250, 220, 150), { Z = 1, Thickness = 1.2, Outline = C.WoodDark, Shade = false })
	kit.Animate(lands, "Drift", 1.5, 0.4, 0)
	local equator = kit.Blob(globe, 28, 28, 56, 14, C.White, { Z = 3, T = 1, Outline = false, Shade = false })
	kit.Stroke(equator, C.White, 1, 0.45)
	kit.Shine(globe, 10, 9, 12, 6, 4, 0.3).Rotation = -35
	kit.Circle(body, 50, 11, 6, 6, C.Gold, 0, 5)
	kit.Circle(body, 50, 77, 6, 6, C.Gold, 0, 5)
	return nil
end

-- Guirlande de polaroïds : fil qui pend, 4 photos tenues par des pinces
Art.PhotoString = function(body, kit, _item)
	local C = kit.C
	local yAt = sagString(kit, body, -2, 102, 24, 12, 6, C.WoodDark, 1.2, 2)
	kit.Circle(body, -2, 24, 4, 4, C.GreyDark, 0, 3)
	kit.Circle(body, 102, 24, 4, 4, C.GreyDark, 0, 3)
	local xs = { 13, 38, 62, 87 }
	local tilts = { -8, 5, -4, 9 }
	local pins = { C.Pink, C.Mint, C.Butter, C.Lilac }
	for i, x in ipairs(xs) do
		local p = kit.Pivot(body, x, yAt(x), 3)
		local card = kit.Part(p, -11, 1, 22, 27, C.White, { Radius = 2, Z = 1, Rotation = tilts[i], Outline = C.Grey, Thickness = 1.2, Shade = 0.06 })
		if i == 1 then
			local photo = kit.Box(card, 3, 3, 16, 16, C.PinkSoft, 0, 2)
			kit.Heart(photo, 8, 8.5, 11, C.Heart, 0, 2)
		elseif i == 2 then
			local photo = kit.Box(card, 3, 3, 16, 16, C.Sky, 0, 2)
			kit.Circle(photo, 11, 5, 6, 6, C.Butter, 0, 2)
			kit.Box(photo, 0, 11, 16, 5, C.Leaf, 0, 3)
			kit.Circle(photo, 5, 12, 10, 6, C.Leaf, 0, 3)
		elseif i == 3 then
			local photo = kit.Box(card, 3, 3, 16, 16, C.LilacSoft, 0, 2)
			local cat = kit.Circle(photo, 8, 10, 12, 10, C.Butter, 0, 3)
			kit.Diamond(photo, 3.5, 5.5, 4, C.Butter, 0, 2)
			kit.Diamond(photo, 12.5, 5.5, 4, C.Butter, 0, 2)
			kit.Face(cat, 6, 5.5, 9, { Eyes = "happy", Mouth = "cat", Z = 2 })
		else
			local photo = kit.Box(card, 3, 3, 16, 16, C.Navy, 0, 2)
			star(kit, photo, 8, 9, 5, C.Butter, 2)
			kit.Circle(photo, 3.5, 3.5, 2, 2, C.White, 0, 2)
			kit.Circle(photo, 13, 13.5, 1.6, 1.6, C.White, 0, 2)
		end
		kit.Line(card, 4, 23, 12, 23, 1.2, C.Grey, 0, 2)
		kit.Part(p, -2.5, -3, 5, 9, pins[i], { Radius = 2, Z = 3, Thickness = 1.2 })
		kit.Animate(p, "Sway", 3, 0.8, i * 1.4)
	end
	return { WallShadow = Vector2.new(0, 0) }
end

-- Étagère murale : planche avec dentelle, livres, plante, lapin et bocal de bonbons
Art.WallShelf = function(body, kit, _item)
	local C = kit.C
	for i = 0, 8 do
		kit.Circle(body, 12 + i * 9.5, 69, 8, 8, C.PinkSoft, 0, 1)
	end
	kit.Part(body, 4, 60, 92, 9, C.Wood, { Radius = 3, Z = 3, Shine = true })
	for _, x in ipairs({ 16, 78 }) do
		kit.Part(body, x, 66, 6, 14, C.WoodDark, { Radius = 2, Z = 2 })
	end
	-- livres
	kit.Part(body, 8, 34, 7, 26, C.Pink, { Radius = 2, Z = 2 })
	kit.Part(body, 15, 38, 7, 22, C.Sky, { Radius = 2, Z = 2 })
	kit.Part(body, 23, 36, 7, 25, C.Mint, { Radius = 2, Z = 1, Rotation = 14 })
	for _, x in ipairs({ 8, 15 }) do
		kit.Box(body, x + 1, 44, 5, 2, C.White, 0.3, 3)
	end
	-- plante en pot
	kit.Blob(body, 40, 36, 8, 16, C.Leaf, { Z = 2, Rotation = -30 })
	kit.Blob(body, 52, 34, 8, 16, C.Leaf, { Z = 2, Rotation = 30 })
	kit.Blob(body, 46, 32, 8, 18, C.LeafDark, { Z = 2 })
	local pot = kit.Part(body, 38, 45, 16, 15, C.Peach, { Radius = 4, Z = 3 })
	kit.Heart(pot, 8, 9, 6, C.PinkDeep, 0, 2)
	-- lapin
	kit.Part(body, 60, 30, 5, 14, C.White, { Radius = -1, Z = 2, Rotation = -10 })
	kit.Part(body, 69, 30, 5, 14, C.White, { Radius = -1, Z = 2, Rotation = 10 })
	local bunny = kit.Blob(body, 66, 50, 20, 20, C.White, { Z = 3 })
	kit.Face(bunny, 10, 9, 13, { Eyes = "dot", Mouth = "cat", Z = 2 })
	-- bocal de bonbons
	local jar = kit.Part(body, 78, 42, 15, 18, C.Glass, { Radius = 4, Z = 3, T = 0.25, Shine = true })
	kit.Circle(jar, 4.5, 12, 5, 5, C.Pink, 0, 2)
	kit.Circle(jar, 10, 13, 5, 5, C.Butter, 0, 2)
	kit.Circle(jar, 7, 8, 5, 5, C.Mint, 0, 2)
	kit.Part(body, 77, 38, 17, 6, C.PinkDeep, { Radius = 2, Z = 4 })
	return { WallShadow = Vector2.new(0.92, 0.5) }
end

-- Carillon (fūrin) : cloche de verre peinte, papier à vœux qui se balance
Art.WindChime = function(body, kit, _item)
	local C = kit.C
	local pv = kit.Pivot(body, 50, -6, 2)
	kit.Line(pv, 0, 0, 0, 18, 1.2, C.PinkDeep, 0, 1)
	kit.Line(pv, 0, 30, 0, 64, 1, C.Ink, 0.4, 1)
	-- papier
	local strip = kit.Pivot(pv, 0, 62, 1)
	local paper = kit.Part(strip, -7, 0, 14, 34, C.PinkSoft, { Radius = 2, Z = 1, Shine = true })
	kit.Box(paper, 0, 26, 14, 3, C.Pink, 0, 2)
	kit.Heart(paper, 7, 15, 7, C.Heart, 0, 2)
	kit.Animate(strip, "Sway", 9, 1.1, 0.5)
	-- cloche
	local bell = kit.Part(pv, -19, 16, 38, 32, C.Glass, { Radius = 16, Z = 3, T = 0.2, Shine = true })
	kit.Circle(bell, 19, 26, 5, 5, C.Mint, 0, 2)
	local fish = kit.Blob(bell, 13, 18, 10, 7, C.Red, { Z = 2, Outline = false, Shade = false })
	kit.Circle(fish, 7, 3, 1.6, 1.6, C.White, 0, 2)
	kit.Diamond(bell, 7, 18, 5, C.Red, 0, 2)
	kit.Circle(bell, 27, 12, 4, 4, C.Pink, 0, 2)
	kit.Circle(bell, 31, 17, 3, 3, C.Pink, 0, 2)
	kit.Circle(bell, 25, 20, 2.5, 2.5, C.Blush, 0, 2)
	kit.Part(pv, -20, 43, 40, 6, kit.Lighten(C.Glass, 0.2), { Radius = 3, Z = 4, T = 0.1 })
	kit.Circle(pv, 0, 17, 9, 5, C.PinkDeep, 0, 4)
	kit.Animate(pv, "Sway", 3, 0.8, 0)
	return { WallShadow = Vector2.new(0, 0) }
end

-- Guirlande de lunes : fil, lunes (une qui dort), étoiles et nuage qui pendent
Art.MoonGarland = function(body, kit, _item)
	local C = kit.C
	local yAt = sagString(kit, body, -2, 102, 12, 8, 4, C.WoodDark, 1.2, 1)
	local moon = Color3.fromRGB(255, 232, 150)
	local items = {
		{ x = 12, len = 16, kind = "star", color = C.Lilac },
		{ x = 31, len = 34, kind = "moon", r = 11 },
		{ x = 50, len = 18, kind = "bigmoon", r = 19 },
		{ x = 69, len = 32, kind = "cloud" },
		{ x = 88, len = 18, kind = "star", color = C.Pink },
	}
	for index, it in ipairs(items) do
		local p = kit.Pivot(body, it.x, yAt(it.x), 2)
		kit.Line(p, 0, 0, 0, it.len, 1, C.Ink, 0.4, 1)
		if it.kind == "star" then
			star(kit, p, 0, it.len + 8, 9, it.color, 2)
		elseif it.kind == "moon" then
			crescent(kit, p, 4, it.len + it.r - 2, it.r, moon, 2, 7)
		elseif it.kind == "bigmoon" then
			local m = crescent(kit, p, 6, it.len + it.r - 3, it.r, moon, 2, 9)
			kit.Face(m, it.r * 0.42, it.r * 1.05, 11, { Eyes = "closed", Mouth = "none", Z = 3 })
		else
			kit.Cloud(p, 0, it.len + 13, 22, C.White, 0, 2)
		end
		kit.Animate(p, "Sway", 5, 0.7, index * 1.3)
	end
	return { WallShadow = Vector2.new(0, 0) }
end

-- Carpes koinobori : mât, 3 carpes à écailles qui flottent au vent
Art.CarpStreamer = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 11, 6, 5, 92, C.WoodLight, { Radius = 2, Z = 1 })
	kit.Circle(body, 13.5, 6, 10, 10, C.Gold, 0, 2)
	local carps = {
		{ y = 22, len = 80, h = 20, color = Color3.fromRGB(110, 130, 200) },
		{ y = 48, len = 70, h = 18, color = C.Pink },
		{ y = 72, len = 58, h = 15, color = C.Sky },
	}
	for index, c in ipairs(carps) do
		local p = kit.Pivot(body, 16, c.y, 3 + index)
		local len, h = c.len, c.h
		local light = kit.Lighten(c.color, 0.45)
		for _, side in ipairs({ -1, 1 }) do
			kit.Blob(p, len - 8, side * h * 0.28, 16, h * 0.42, kit.Darken(c.color, 0.06), { Z = 1, Rotation = side * 30 })
		end
		local fish = kit.Part(p, 0, -h / 2, len - 10, h, c.color, { Radius = -1, Z = 2, Shine = true })
		kit.Box(fish, 6, h * 0.62, len - 26, h * 0.2, light, 0.2, 2)
		for i = 0, 3 do
			local sx = 18 + i * (len - 38) / 3
			kit.Circle(fish, sx, h * 0.34, h * 0.36, h * 0.36, light, 0.45, 2)
		end
		kit.Part(p, -2, -h / 2 + 1, 6, h - 2, C.White, { Radius = -1, Z = 3, Thickness = 1.2 })
		local eye = kit.Circle(fish, 11, h * 0.42, h * 0.42, h * 0.42, C.White, 0, 3)
		kit.Circle(eye, h * 0.21, h * 0.21, h * 0.24, h * 0.24, C.Ink, 0, 2)
		kit.Animate(p, "Sway", 3, 0.9, index * 0.9)
	end
	return { WallShadow = Vector2.new(0, 0) }
end

-- Aquarium : bac d'eau sur un meuble, algues, poissons kawaii, bulles
Art.Aquarium = function(body, kit, _item)
	local C = kit.C
	-- meuble
	local stand = kit.Part(body, 8, 80, 84, 20, C.WoodLight, { Radius = 5, Z = 1 })
	kit.Part(stand, 5, 5, 35, 11, kit.Lighten(C.WoodLight, 0.2), { Radius = 3, Z = 2, Thickness = 1.2 })
	kit.Part(stand, 44, 5, 35, 11, kit.Lighten(C.WoodLight, 0.2), { Radius = 3, Z = 2, Thickness = 1.2 })
	kit.Circle(stand, 37, 10.5, 3, 3, C.Gold, 0, 3)
	kit.Circle(stand, 47, 10.5, 3, 3, C.Gold, 0, 3)
	-- bac
	local tank = kit.Part(body, 6, 22, 88, 60, C.Glass, { Radius = 5, Z = 2, Outline = Color3.fromRGB(120, 175, 220), Thickness = 2.2, Shade = false })
	kit.Gradient(tank, Color3.fromRGB(215, 242, 255), Color3.fromRGB(140, 200, 245))
	local view = kit.Group(tank, 0, 5, 88, 55, 2, true)
	kit.Box(view, 0, 0, 88, 2, C.White, 0.3, 1)
	kit.Blob(view, 44, 56, 104, 18, C.Butter, { Z = 4, Outline = false, Shade = 0.1 })
	kit.Circle(view, 20, 50, 4, 3, C.Pink, 0, 5)
	kit.Circle(view, 60, 51, 5, 3.5, C.Lilac, 0, 5)
	-- algues
	for index, a in ipairs({ { 12, 50, 26 }, { 76, 50, 30 }, { 83, 51, 20 } }) do
		local p = kit.Pivot(view, a[1], a[2], 3)
		kit.Line(p, 0, 0, -2, -a[3], 5, if index == 2 then C.LeafDark else C.Leaf, 0, 1)
		kit.Line(p, 0, 0, 5, -a[3] * 0.6, 4, C.Leaf, 0, 1)
		kit.Animate(p, "Sway", 6, 0.6, index * 1.5)
	end
	-- corail rose
	kit.Blob(view, 64, 44, 8, 16, C.Pink, { Z = 3, Rotation = -20 })
	kit.Blob(view, 69, 42, 7, 18, C.Pink, { Z = 3, Rotation = 15 })
	-- poissons
	local function fish(x, y, w, color, stripes, phase)
		local g = kit.Group(view, x - w / 2, y - w * 0.35, w * 1.3, w * 0.7, 6)
		kit.Blob(g, w * 0.12, w * 0.35, w * 0.35, w * 0.45, kit.Darken(color, 0.05), { Z = 1, Thickness = 1.2 })
		local b = kit.Blob(g, w * 0.7, w * 0.35, w, w * 0.7, color, { Z = 2, Thickness = 1.2, Shine = true })
		if stripes then
			kit.Box(b, w * 0.42, 0, w * 0.12, w * 0.7, C.White, 0, 2)
		end
		kit.Circle(b, w * 0.75, w * 0.3, w * 0.16, w * 0.18, C.Ink, 0, 3)
		kit.Circle(b, w * 0.7, w * 0.47, w * 0.16, w * 0.09, C.Blush, 0.3, 3)
		kit.Animate(g, "Drift", 7, 0.35 + phase * 0.05, phase)
	end
	fish(30, 18, 16, C.Orange, true, 0)
	fish(60, 30, 13, C.Pink, false, 2)
	fish(26, 38, 10, C.Sky, false, 4)
	-- bulles
	for index, b in ipairs({ { 50, 12, 4 }, { 54, 20, 3 }, { 18, 26, 3.5 }, { 74, 14, 2.5 } }) do
		local bubble = kit.Circle(view, b[1], b[2], b[3], b[3], C.White, 0.35, 7)
		kit.Stroke(bubble, C.White, 1, 0.2)
		kit.Animate(bubble, "Bob", 2, 0.8, index * 1.1)
	end
	-- reflets sur la vitre + couvercle
	kit.Line(body, 14, 64, 26, 32, 3, C.White, 0.55, 4)
	kit.Line(body, 20, 70, 28, 50, 2, C.White, 0.65, 4)
	kit.Part(body, 3, 17, 94, 8, C.Mint, { Radius = 4, Z = 5, Shine = true })
	return { Glow = Color3.fromRGB(150, 215, 255) }
end

-- Piñata lama : bandes de papier pastel à franges, tête avec visage et fleur, corde
Art.Pinata = function(body, kit, _item)
	local C = kit.C
	local p = kit.Pivot(body, 56, -14, 2)
	kit.Line(p, 0, 0, 0, 56, 1.4, C.WoodDark, 0, 1)
	local colors = { C.Pink, C.Butter, C.Mint, C.Sky, C.Lilac }
	local function stripes(x, y, w, h, n, z, offset, fringe)
		local sh = h / n
		for i = 0, n - 1 do
			local color = colors[(i + offset) % #colors + 1]
			local s = kit.Part(p, x, y + i * sh, w, sh + 0.8, color, { Radius = 3, Z = z, Thickness = 1.2, Shade = false })
			if fringe then
				kit.Box(s, 2, sh - 2, w - 4, 1.4, kit.Darken(color, 0.14), 0.1, 2)
			end
		end
	end
	for i, x in ipairs({ -24, -13, 8, 19 }) do
		stripes(x, 60, 8, 22, 2, 1, i + 1, false) -- pattes
	end
	kit.Blob(p, 32, 46, 10, 14, C.Heart, { Z = 1, Rotation = 35 }) -- queue
	stripes(-28, 38, 60, 28, 4, 2, 0, true) -- corps
	stripes(-38, 16, 16, 26, 3, 3, 3, true) -- cou
	-- tête
	kit.Part(p, -40, -8, 7, 14, C.Pink, { Radius = -1, Z = 3, Rotation = -14 })
	kit.Part(p, -27, -8, 7, 14, C.Pink, { Radius = -1, Z = 3, Rotation = 14 })
	local head = kit.Part(p, -46, -1, 30, 22, C.Pink, { Radius = 9, Z = 4, Shine = true })
	kit.Blob(head, 15, 16, 16, 9, C.PinkSoft, { Z = 2, Outline = false, Shade = false })
	kit.Face(head, 15, 11, 17, { Eyes = "dot", Mouth = "smile", Z = 3 })
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		kit.Circle(p, -22 + math.cos(a) * 3, -3 + math.sin(a) * 3, 5, 5, C.Butter, 0, 5)
	end
	kit.Circle(p, -22, -3, 3.5, 3.5, C.Orange, 0, 6)
	kit.Animate(p, "Sway", 4, 0.8, 0)
	return { WallShadow = Vector2.new(0.75, 0.7) }
end

-- Trophée doré : coupe à anses, étoile, socle en bois avec plaque
Art.GoldenTrophy = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 24, 84, 52, 14, C.WoodDark, { Radius = 3, Z = 1 })
	kit.Part(body, 38, 88, 24, 6, C.Butter, { Radius = 2, Z = 2, Thickness = 1 })
	kit.Part(body, 32, 76, 36, 10, C.Gold, { Radius = 3, Z = 2, Shine = true })
	kit.Part(body, 45, 56, 10, 22, C.Gold, { Radius = 2, Z = 2 })
	kit.Blob(body, 50, 64, 18, 7, C.Gold, { Z = 3 })
	for _, x in ipairs({ 10, 68 }) do
		kit.Part(body, x, 18, 22, 24, C.Gold, { Radius = -1, T = 1, Thickness = 5, Outline = kit.OutlineOf(C.Gold), Shade = false, Z = 2 })
		kit.Part(body, x, 18, 22, 24, C.Gold, { Radius = -1, T = 1, Thickness = 3, Outline = C.Gold, Shade = false, Z = 3 })
	end
	kit.Blob(body, 50, 50, 30, 20, C.Gold, { Z = 3 })
	local cup = kit.Part(body, 24, 12, 52, 44, C.Gold, { Radius = 20, Z = 4, Shade = 0.2 })
	kit.Line(cup, 9, 12, 8, 26, 4, C.White, 0.4, 3)
	kit.Part(body, 20, 10, 60, 8, kit.Lighten(C.Gold, 0.25), { Radius = -1, Z = 5 })
	outlinedStar(kit, body, 50, 34, 10, C.Butter, 6)
	for index, s in ipairs({ { 14, 10, 10 }, { 88, 50, 8 }, { 84, 8, 6 } }) do
		local sp = kit.Sparkle(body, s[1], s[2], s[3], if index == 2 then C.White else C.Butter, 0, 7)
		kit.Animate(sp, "Breathe", 0.2, 1.4, index)
	end
	return nil
end

-- Boule de cristal : sphère lilas avec brume qui tourne, étoiles, socle doré
Art.CrystalBall = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 26, 84, 48, 13, C.Purple, { Radius = 6, Z = 1, Shine = true })
	local ball = kit.Blob(body, 50, 48, 60, 60, C.White, { Z = 2, Shade = false, T = 0.05, Outline = C.Purple, Thickness = 2 })
	kit.Gradient(ball, Color3.fromRGB(245, 235, 255), Color3.fromRGB(190, 160, 250))
	local mist = kit.Group(ball, 0, 0, 60, 60, 2)
	kit.Circle(mist, 22, 26, 24, 16, C.Pink, 0.55, 1)
	kit.Circle(mist, 38, 38, 22, 14, C.Sky, 0.55, 1)
	kit.Circle(mist, 36, 20, 14, 10, C.White, 0.5, 1)
	kit.Animate(mist, "Spin", 0, 0.06, 0)
	for index, s in ipairs({ { 22, 36, 8 }, { 40, 24, 10 }, { 32, 46, 5 } }) do
		local sp = kit.Sparkle(ball, s[1], s[2], s[3], C.White, 0, 4)
		kit.Animate(sp, "Breathe", 0.25, 1.1, index * 1.7)
	end
	kit.Shine(ball, 11, 10, 16, 8, 5, 0.2).Rotation = -40
	kit.Circle(ball, 12, 22, 4, 4, C.White, 0.2, 5)
	kit.Part(body, 28, 74, 44, 12, C.Gold, { Radius = -1, Z = 3, Shine = true })
	for _, x in ipairs({ 34, 50, 66 }) do
		kit.Diamond(body, x, 80, 4, C.PinkDeep, 0, 4)
	end
	return { Glow = Color3.fromRGB(200, 160, 255) }
end

-- Statue moaï : grosse tête de pierre qui fait la sieste, chapeau, mousse et fleur
Art.MoaiStatue = function(body, kit, _item)
	local C = kit.C
	local stone = Color3.fromRGB(196, 190, 212)
	local dark = kit.Darken(stone, 0.14)
	kit.Part(body, 6, 88, 88, 11, kit.Darken(stone, 0.2), { Radius = 4, Z = 1 })
	for _, g in ipairs({ { 10, 88 }, { 16, 86 }, { 86, 88 }, { 80, 87 } }) do
		kit.Blob(body, g[1], g[2], 6, 10, C.Leaf, { Z = 2, Thickness = 1 })
	end
	local torso = kit.Part(body, 18, 62, 64, 28, stone, { Radius = 12, Z = 2 })
	kit.Line(torso, 8, 12, 24, 22, 2, dark, 0.2, 2)
	kit.Line(torso, 56, 12, 40, 22, 2, dark, 0.2, 2)
	for _, x in ipairs({ 22, 70 }) do
		kit.Part(body, x, 30, 8, 26, stone, { Radius = 4, Z = 3 })
	end
	local head = kit.Part(body, 27, 12, 46, 58, stone, { Radius = 12, Z = 4, Shine = true })
	kit.Part(body, 31, 3, 38, 13, Color3.fromRGB(235, 160, 150), { Radius = 5, Z = 5, Shine = true })
	kit.Part(head, -2, 14, 50, 9, dark, { Radius = 4, Z = 2, Shade = false })
	kit.Face(head, 23, 28, 34, { Eyes = "closed", Mouth = "none", Z = 3 })
	local nose = kit.Part(head, 17, 18, 12, 28, kit.Lighten(stone, 0.12), { Radius = 5, Z = 4 })
	kit.Circle(nose, 3.5, 24, 3, 2.5, dark, 0, 2)
	kit.Circle(nose, 8.5, 24, 3, 2.5, dark, 0, 2)
	kit.Part(head, 13, 49, 20, 5, dark, { Radius = 2.5, Z = 4, Shade = false })
	kit.Blob(head, 8, 6, 12, 7, C.Leaf, { Z = 3, Outline = false, T = 0.15 })
	-- fleur derrière l'oreille
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		kit.Circle(body, 74 + math.cos(a) * 3.5, 30 + math.sin(a) * 3.5, 6, 6, C.Pink, 0, 6)
	end
	kit.Circle(body, 74, 30, 4, 4, C.Yellow, 0, 7)
	return nil
end

-- Fontaine d'intérieur : trois vasques, jets d'eau, gouttes et petit canard
Art.Fountain = function(body, kit, _item)
	local C = kit.C
	local stone = Color3.fromRGB(238, 232, 250)
	local rim = kit.Lighten(stone, 0.5)
	local water = Color3.fromRGB(160, 215, 255)
	-- bassin
	local basin = kit.Part(body, 4, 72, 92, 26, stone, { Radius = 10, Z = 2 })
	kit.Box(basin, 2, 13, 88, 4, C.PinkSoft, 0, 2)
	for _, x in ipairs({ 22, 46, 70 }) do
		kit.Heart(basin, x, 15, 7, C.Pink, 0, 3)
	end
	kit.Blob(body, 50, 72, 96, 18, rim, { Z = 3 })
	local pool = kit.Blob(body, 50, 73, 82, 11, water, { Z = 4, Outline = false })
	kit.Circle(pool, 20, 5, 3, 2, C.Gold, 0, 2)
	kit.Circle(pool, 60, 7, 3, 2, C.Gold, 0, 2)
	local ripple = kit.Blob(pool, 41, 5.5, 28, 5, C.White, { Z = 2, T = 0.6, Outline = false, Shade = false })
	kit.Animate(ripple, "Pulse", 0.35, 0.9, 0)
	-- colonne + vasque du milieu
	kit.Part(body, 43, 44, 14, 30, stone, { Radius = 3, Z = 5 })
	kit.Blob(body, 50, 47, 54, 18, stone, { Z = 6 })
	kit.Blob(body, 50, 42, 58, 10, rim, { Z = 7 })
	kit.Blob(body, 50, 42, 46, 5, water, { Z = 8, Outline = false })
	-- colonne + vasque du haut
	kit.Part(body, 47, 22, 6, 20, stone, { Radius = 2, Z = 9 })
	kit.Blob(body, 50, 25, 32, 10, stone, { Z = 10 })
	kit.Blob(body, 50, 21, 34, 6, rim, { Z = 11 })
	kit.Blob(body, 50, 21, 26, 3, water, { Z = 12, Outline = false })
	kit.Circle(body, 50, 15, 7, 7, stone, 0, 12)
	-- jets et rideaux d'eau
	kit.Line(body, 50, 13, 50, 1, 4, water, 0.2, 13)
	kit.Circle(body, 50, 1, 7, 5, C.White, 0.2, 13)
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(body, 50 + side * 16, 22, 50 + side * 19, 40, 3, water, 0.3, 7)
		kit.Line(body, 50 + side * 28, 43, 50 + side * 33, 72, 4, water, 0.3, 4)
		kit.Line(body, 50 + side * 2, 4, 50 + side * 10, 14, 2, water, 0.3, 13)
	end
	for index, d in ipairs({ { 38, 8 }, { 62, 10 }, { 22, 58 }, { 80, 60 } }) do
		local drop = kit.Circle(body, d[1], d[2], 3, 4, water, 0.1, 13)
		kit.Animate(drop, "Bob", 2, 1.2, index * 1.3)
	end
	-- canard
	local duck = kit.Group(body, 62, 60, 20, 16, 9)
	kit.Blob(duck, 9, 12, 14, 8, C.Yellow, { Z = 1, Thickness = 1.2 })
	local head = kit.Blob(duck, 13, 5.5, 8, 8, C.Yellow, { Z = 2, Thickness = 1.2 })
	kit.Circle(head, 5, 3.2, 1.6, 1.8, C.Ink, 0, 2)
	kit.Blob(duck, 18, 6.5, 4, 2.5, C.Orange, { Z = 3, Outline = false })
	kit.Animate(duck, "Drift", 4, 0.3, 0)
	return nil
end

-- Gemme géante : diamant rose à facettes qui flotte sur un coussin de velours
Art.GiantGem = function(body, kit, _item)
	local C = kit.C
	local velvet = Color3.fromRGB(190, 130, 230)
	kit.Part(body, 14, 80, 72, 16, velvet, { Radius = 8, Z = 1 })
	kit.Blob(body, 50, 82, 68, 12, kit.Lighten(velvet, 0.15), { Z = 2, Shine = true })
	for _, x in ipairs({ 14, 86 }) do
		kit.Circle(body, x, 94, 6, 7, C.Gold, 0, 3)
	end
	local gem = kit.Group(body, 0, 0, 100, 100, 4)
	local ink = Color3.fromRGB(190, 80, 140)
	local light = Color3.fromRGB(255, 220, 238)
	local mid = Color3.fromRGB(255, 165, 206)
	local deep = Color3.fromRGB(240, 115, 175)
	-- contour
	kit.Box(gem, 33, 17.5, 34, 22, ink, 0, 1)
	wedge(kit, gem, 15, 17.5, 18.4, 21.5, "BR", ink, 0, 1)
	wedge(kit, gem, 66.6, 17.5, 18.4, 21.5, "BL", ink, 0, 1)
	wedge(kit, gem, 15, 38, 35.4, 44, "TR", ink, 0, 1)
	wedge(kit, gem, 49.6, 38, 35.4, 44, "TL", ink, 0, 1)
	-- couronne
	kit.Box(gem, 35, 20, 30, 18.5, light, 0, 2)
	wedge(kit, gem, 18, 20, 17.4, 18.5, "BR", mid, 0, 2)
	wedge(kit, gem, 64.6, 20, 17.4, 18.5, "BL", deep, 0, 2)
	-- pavillon
	wedge(kit, gem, 18, 38, 32.3, 40, "TR", mid, 0, 2)
	wedge(kit, gem, 49.7, 38, 32.3, 40, "TL", deep, 0, 2)
	wedge(kit, gem, 36, 38, 14.3, 40, "TR", light, 0, 3)
	wedge(kit, gem, 49.7, 38, 14.3, 40, "TL", mid, 0, 3)
	kit.Box(gem, 18, 37, 64, 2.5, C.White, 0.3, 4)
	kit.Line(gem, 36, 21, 42, 37, 1.2, C.White, 0.4, 4)
	kit.Line(gem, 64, 21, 58, 37, 1.2, C.White, 0.4, 4)
	kit.Shine(gem, 38, 23, 12, 4, 5, 0.25)
	kit.Face(gem, 50, 50, 20, { Eyes = "big", Mouth = "cat", Z = 6 })
	kit.Animate(gem, "Bob", 2, 0.8, 0)
	for index, s in ipairs({ { 14, 14, 12 }, { 88, 28, 9 }, { 84, 64, 7 }, { 12, 52, 7 } }) do
		local sp = kit.Sparkle(body, s[1], s[2], s[3], if index % 2 == 0 then C.White else C.PinkSoft, 0, 8)
		kit.Animate(sp, "Breathe", 0.25, 1.2, index * 1.4)
	end
	return { Glow = Color3.fromRGB(255, 170, 220) }
end

-- Planète flottante : sphère lilas souriante, anneau doré, petite lune, étoiles
Art.FloatingPlanet = function(body, kit, _item)
	local C = kit.C
	local g = kit.Group(body, 0, 0, 100, 100, 2)
	local ringA = C.Butter
	local ringB = C.Peach
	local function ring(parent, cx, cy, z)
		kit.Part(parent, cx - 50, cy - 13, 100, 26, C.White, { Radius = -1, T = 1, Outline = kit.OutlineOf(ringA), Thickness = 7, Shade = false, Z = z })
		kit.Part(parent, cx - 50, cy - 13, 100, 26, C.White, { Radius = -1, T = 1, Outline = ringA, Thickness = 5, Shade = false, Z = z + 1 })
		kit.Part(parent, cx - 41, cy - 9, 82, 18, C.White, { Radius = -1, T = 1, Outline = ringB, Thickness = 2.5, Shade = false, Z = z + 1 })
	end
	ring(g, 50, 54, 1)
	local planet = kit.Blob(g, 50, 50, 56, 56, Color3.fromRGB(200, 172, 255), { Z = 4, Shine = true })
	kit.Blob(planet, 28, 16, 44, 7, C.PinkSoft, { Z = 2, Outline = false, Shade = false, T = 0.3 })
	kit.Blob(planet, 28, 42, 48, 8, C.Pink, { Z = 2, Outline = false, Shade = false, T = 0.5 })
	kit.Face(planet, 28, 30, 24, { Eyes = "big", Mouth = "smile", Z = 3 })
	local front = kit.Group(g, 0, 54, 100, 20, 6, true)
	ring(front, 50, 0, 1)
	kit.Animate(g, "Bob", 3, 0.6, 0)
	local moon = kit.Blob(body, 88, 16, 13, 13, C.Cream, { Z = 3 })
	kit.Circle(moon, 4, 5, 3, 3, C.Grey, 0.3, 2)
	kit.Circle(moon, 8.5, 8.5, 2, 2, C.Grey, 0.3, 2)
	kit.Animate(moon, "Bob", 2, 0.9, 2)
	for index, s in ipairs({ { 12, 18, 10 }, { 14, 84, 8 }, { 86, 86, 9 } }) do
		local sp = kit.Sparkle(body, s[1], s[2], s[3], if index == 2 then C.Butter else C.White, 0, 3)
		kit.Animate(sp, "Breathe", 0.2, 1.2, index)
	end
	return { Glow = Color3.fromRGB(210, 180, 255), WallShadow = Vector2.new(0, 0) }
end

return Art
