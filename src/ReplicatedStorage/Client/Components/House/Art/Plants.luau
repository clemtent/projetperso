--[[
	Plants (ModuleScript) — dessins des plantes 🪴
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Plants
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

local SQRT2 = math.sqrt(2)

----------------------------------------------------------------------
-- Aides communes
----------------------------------------------------------------------

-- Pot kawaii (corps + rebord en pilule), posé sur `bottom` ; renvoie (corps, y du visage)
local function pot(parent, kit, cx, bottom, w, h, color, z)
	local zz = z or 5
	local rimH = math.clamp(h * 0.27, 6, 11)
	local bodyW = w * 0.84
	local base = kit.Part(parent, cx - bodyW / 2, bottom - h + rimH * 0.5, bodyW, h - rimH * 0.5, color, {
		Radius = math.min(12, bodyW * 0.28),
		Z = zz,
		Shade = 0.16,
	})
	kit.Part(parent, cx - w / 2, bottom - h, w, rimH, kit.Lighten(color, 0.2), { Radius = -1, Z = zz + 1, Shine = true })
	-- terre qui dépasse un peu du rebord
	kit.Blob(parent, cx, bottom - h + 1, w * 0.74, 6, kit.C.WoodDark, { Z = zz - 1, Outline = false, Shade = false })
	return base, bottom - (h - rimH) / 2 + 1
end

-- Feuille ovale partant de (px, py) dans la direction `angle` (degrés, 0 = droite, -90 = haut)
local function leaf(parent, kit, px, py, angle, len, wid, color, z, vein)
	local a = math.rad(angle)
	local cx, cy = px + math.cos(a) * len / 2, py + math.sin(a) * len / 2
	local frame = kit.Blob(parent, cx, cy, len, wid, color, { Z = z, Rotation = angle, Shade = false, Thickness = 1.4 })
	if vein ~= false then
		kit.Line(frame, len * 0.14, wid / 2, len * 0.78, wid / 2, math.max(1, wid * 0.1), kit.Darken(color, 0.2), 0.25, 2)
	end
	return frame
end

-- Conteneur plein cadre qui "respire" depuis le point (ax, ay) (UIScale autour de l'ancre)
local function anchored(parent, kit, ax, ay, z)
	local g = kit.Group(parent, 0, 0, 100, 100, z)
	g.AnchorPoint = Vector2.new(ax / 100, ay / 100)
	g.Position = UDim2.fromOffset(ax, ay)
	return g
end

-- Étage de sapin : carré arrondi tourné à 45° coupé à mi-hauteur (triangle aux coins doux)
-- + ourlet festonné en bas ; `apex` = y de la pointe, `half` = demi-largeur
local function tier(parent, kit, cx, apex, half, color, z)
	local clip = kit.Group(parent, cx - half - 4, apex - 4, half * 2 + 8, half + 4, z, true)
	local side = half * SQRT2
	kit.Part(clip, half + 4 - side / 2, 4 + half - side / 2, side, side, color, {
		Radius = 7,
		Rotation = 45,
		Z = 1,
		Shade = false,
		Thickness = 1.8,
	})
	kit.Part(parent, cx - half + 3, apex + half - 6, half * 2 - 6, 8, color, { Radius = -1, Z = z + 1, Shade = 0.18, Thickness = 1.8 })
	kit.Shine(clip, half + 4 - half * 0.34, 4 + half * 0.42, half * 0.22, 3, 2, 0.55)
	return clip
end

-- Petite fleur ronde à 5 pétales (cerisier, bouquet)
local function blossom(parent, kit, x, y, r, color, heart, z)
	local zz = z or 4
	for index = 0, 4 do
		local a = math.rad(index * 72 - 90)
		kit.Blob(parent, x + math.cos(a) * r * 0.52, y + math.sin(a) * r * 0.52, r * 0.78, r * 0.78, color, {
			Z = zz,
			Shade = false,
			Thickness = 1,
		})
	end
	kit.Circle(parent, x, y, r * 0.42, r * 0.42, heart, 0, zz + 1)
end

----------------------------------------------------------------------
-- Dessins
----------------------------------------------------------------------

-- Petite pousse : deux feuilles rondes dans un pot pêche qui sourit
Art.Sprout = function(body, kit, _item)
	local C = kit.C
	local stem = kit.Pivot(body, 50, 64, 3)
	kit.Line(stem, 0, 2, 0, -22, 3.5, C.LeafDark, 0, 1)
	leaf(stem, kit, 0, -20, -155, 25, 17, C.Leaf, 2)
	leaf(stem, kit, 0, -20, -25, 25, 17, Color3.fromRGB(150, 220, 130), 2)
	kit.Animate(stem, "Sway", 4, 0.8, 0.3)
	local _, faceY = pot(body, kit, 50, 100, 52, 38, C.Peach)
	kit.Face(body, 50, faceY, 24, { Z = 8 })
	return nil
end

-- Pot de tulipes : trois tulipes (rose, rouge, beurre) et un petit cœur sur le pot
Art.TulipPot = function(body, kit, _item)
	local C = kit.C
	local stems = kit.Pivot(body, 50, 68, 3)
	local heads = {
		{ -15, -40, C.Pink },
		{ 1, -52, Color3.fromRGB(250, 105, 125) },
		{ 16, -38, C.Butter },
	}
	for _, h in ipairs(heads) do
		kit.Line(stems, 0, 0, h[1], h[2], 2.6, C.Green, 0, 1)
	end
	leaf(stems, kit, -2, 0, -118, 32, 10, C.Leaf, 2)
	leaf(stems, kit, 2, 0, -62, 30, 10, C.Leaf, 2)
	for _, h in ipairs(heads) do
		local x, y, color = h[1], h[2], h[3]
		kit.Blob(stems, x, y - 4, 8, 14, kit.Darken(color, 0.12), { Z = 3, Shade = false })
		kit.Blob(stems, x - 3.5, y, 10, 16, color, { Z = 4, Rotation = -14, Shade = false, Thickness = 1.3 })
		kit.Blob(stems, x + 3.5, y, 10, 16, color, { Z = 4, Rotation = 14, Shade = false, Thickness = 1.3 })
	end
	kit.Animate(stems, "Sway", 2.5, 0.7, 1.1)
	local _, faceY = pot(body, kit, 50, 100, 48, 34, C.Lilac)
	kit.Heart(body, 50, faceY, 11, C.White, 0.15, 8)
	return nil
end

-- Petit cactus rigolo : bras levés, visage, fleur rose sur la tête
Art.TinyCactus = function(body, kit, _item)
	local C = kit.C
	local green = Color3.fromRGB(125, 205, 140)
	local cactus = anchored(body, kit, 50, 76, 3)
	for _, side in ipairs({ -1, 1 }) do
		local arm = kit.Pivot(cactus, 50 + side * 12, 58, 1)
		kit.Blob(arm, side * 6, -7, 10, 20, green, { Rotation = side * 28, Shade = false })
		kit.Animate(arm, "Sway", 5, 0.9, side)
	end
	kit.Part(cactus, 35, 28, 30, 52, green, { Radius = -1, Z = 2, Shine = true })
	kit.Face(cactus, 50, 54, 22, { Mouth = "cat", Z = 4 })
	for _, p in ipairs({ { 41, 38 }, { 60, 40 }, { 40, 68 }, { 60, 70 } }) do
		kit.Line(cactus, p[1] - 1, p[2] - 1, p[1] + 1, p[2] + 1, 1.3, kit.Darken(green, 0.35), 0.2, 3)
	end
	for _, dx in ipairs({ -4, 4 }) do
		kit.Blob(cactus, 50 + dx, 28, 9, 8, C.Pink, { Z = 3, Shade = false, Thickness = 1.2 })
	end
	kit.Blob(cactus, 50, 24, 8, 9, C.Pink, { Z = 3, Shade = false, Thickness = 1.2 })
	kit.Circle(cactus, 50, 27.5, 4, 4, C.Yellow, 0, 4)
	kit.Animate(cactus, "Breathe", 0.015, 1, 0.4)
	local potBody = pot(body, kit, 50, 100, 46, 28, Color3.fromRGB(240, 160, 120))
	kit.Box(potBody, 4, 12, potBody.Size.X.Offset - 8, 3, C.Cream, 0.2, 2)
	return nil
end

-- Pot de marguerites : trois marguerites (celle du milieu sourit), pot à pois
Art.DaisyPot = function(body, kit, _item)
	local C = kit.C
	local stems = kit.Pivot(body, 50, 70, 3)
	local flowers = { { -17, -34, 8 }, { 17, -32, 8 }, { 1, -50, 10 } }
	for _, f in ipairs(flowers) do
		kit.Line(stems, 0, 0, f[1], f[2], 2.4, C.Green, 0, 1)
	end
	leaf(stems, kit, -1, -4, -140, 22, 10, C.Leaf, 2)
	leaf(stems, kit, 1, -8, -40, 20, 9, C.Leaf, 2)
	local petalLine = Color3.fromRGB(215, 200, 225)
	for index, f in ipairs(flowers) do
		local x, y, r = f[1], f[2], f[3]
		for k = 0, 3 do
			local a = math.rad(k * 45)
			local dx, dy = math.cos(a) * r * 0.62, math.sin(a) * r * 0.62
			local petal = kit.Line(stems, x - dx, y - dy, x + dx, y + dy, r * 0.62, C.White, 0, 3)
			kit.Stroke(petal, petalLine, 1.1)
		end
		kit.Blob(stems, x, y, r * 0.95, r * 0.95, C.Yellow, { Z = 4, Shade = false, Thickness = 1.2 })
		if index == 3 then
			kit.Face(stems, x, y + 0.5, r * 0.95, { Mouth = "none", Blush = false, Z = 5 })
		end
	end
	kit.Animate(stems, "Sway", 2.5, 0.8, 2.2)
	local potBody = pot(body, kit, 50, 100, 48, 32, C.Sky)
	for _, p in ipairs({ { 8, 8 }, { 20, 16 }, { 32, 8 } }) do
		kit.Circle(potBody, p[1], p[2], 4.5, 4.5, C.White, 0.1, 2)
	end
	return nil
end

-- Plante en pot : éventail de grandes feuilles, pot crème à bande rose qui sourit
Art.PottedPlant = function(body, kit, _item)
	local C = kit.C
	local foliage = kit.Pivot(body, 50, 64, 3)
	local light = Color3.fromRGB(145, 215, 125)
	local leaves = {
		{ -90, 50, C.LeafDark, 1 },
		{ -114, 46, C.Leaf, 2 },
		{ -66, 46, C.Leaf, 2 },
		{ -140, 40, light, 3 },
		{ -40, 40, light, 3 },
		{ -166, 30, C.Leaf, 4 },
		{ -14, 30, C.Leaf, 4 },
	}
	for _, l in ipairs(leaves) do
		leaf(foliage, kit, 0, 0, l[1], l[2], 15, l[3], l[4])
	end
	kit.Animate(foliage, "Sway", 2, 0.6, 0.8)
	local potBody, faceY = pot(body, kit, 50, 100, 60, 40, C.Cream)
	kit.Box(potBody, 0, 22, potBody.Size.X.Offset, 5, C.PinkSoft, 0, 2)
	kit.Face(body, 50, faceY - 3, 22, { Z = 8 })
	return nil
end

-- Herbes séchées : trois bouquets suspendus à une tringle (romarin, lavande, basilic)
Art.HangingHerbs = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 50, 16, 14, 32, 1.4, C.WoodDark, 0, 2)
	kit.Line(body, 50, 16, 86, 32, 1.4, C.WoodDark, 0, 2)
	kit.Circle(body, 50, 16, 6, 6, C.GreyDark, 0, 4)
	kit.Part(body, 8, 29, 84, 7, C.Wood, { Radius = -1, Z = 5, Shine = true })
	local kinds = {
		{ 24, "rosemary" },
		{ 50, "lavender" },
		{ 76, "basil" },
	}
	for index, k in ipairs(kinds) do
		local bundle = kit.Pivot(body, k[1], 33, 3)
		kit.Line(bundle, 0, 0, 0, 9, 1.3, C.WoodDark, 0, 1)
		for _, dx in ipairs({ -2.5, 0, 2.5 }) do
			kit.Line(bundle, dx * 0.6, 8, dx, 14, 1.6, Color3.fromRGB(150, 150, 90), 0, 1)
		end
		kit.Part(bundle, -5.5, 12, 11, 5, C.PinkDeep, { Radius = -1, Z = 4, Shade = false, Thickness = 1.2 })
		if k[2] == "rosemary" then
			for _, a in ipairs({ 65, 78, 90, 102, 115 }) do
				leaf(bundle, kit, 0, 15, a, 30, 6, Color3.fromRGB(95, 160, 120), 2, false)
			end
		elseif k[2] == "lavender" then
			for _, a in ipairs({ 72, 90, 108 }) do
				local r = math.rad(a)
				local ex, ey = math.cos(r) * 20, 15 + math.sin(r) * 20
				kit.Line(bundle, 0, 15, ex, ey, 1.6, C.Green, 0, 1)
				leaf(bundle, kit, ex, ey, a, 16, 7, C.Lilac, 3, false)
			end
		else
			for _, l in ipairs({ { 70, 18 }, { 110, 18 }, { 90, 22 }, { 55, 13 }, { 125, 13 } }) do
				leaf(bundle, kit, 0, 15, l[1], l[2] + 4, 12, C.Leaf, 2)
			end
		end
		kit.Animate(bundle, "Sway", 3, 0.7, index * 1.7)
	end
	return { WallShadow = Vector2.new(0.8, 0.45) }
end

-- Pothos suspendu : suspension en macramé, pot blanc qui sourit, lianes de feuilles-cœurs
Art.HangingPothos = function(body, kit, _item)
	local C = kit.C
	kit.Circle(body, 50, 2, 6, 6, C.GreyDark, 0, 6)
	local hanger = kit.Pivot(body, 50, 2, 3)
	local cord = C.WoodLight
	for _, x in ipairs({ -19, 0, 19 }) do
		kit.Line(hanger, 0, 0, x, 36, 1.6, cord, 0, 1)
	end
	kit.Circle(hanger, 0, 12, 6, 6, C.Wood, 0, 2)
	local light, dark = Color3.fromRGB(165, 222, 130), C.Leaf
	-- lianes (derrière le pot)
	local vines = {
		{ -19, { { -3, 10 }, { -7, 22 }, { -5, 34 }, { -9, 46 }, { -6, 58 } } },
		{ 19, { { 3, 10 }, { 7, 22 }, { 4, 34 } } },
	}
	for index, v in ipairs(vines) do
		local vine = kit.Pivot(hanger, v[1], 36, 2)
		local px, py = 0, 0
		for n, p in ipairs(v[2]) do
			kit.Line(vine, px, py, p[1], p[2], 1.8, C.LeafDark, 0, 1)
			px, py = p[1], p[2]
			local heart = kit.Heart(vine, p[1] + (n % 2 == 0 and 3 or -3), p[2] + 2, 11, n % 2 == 0 and light or dark, 0, 2)
			heart.Rotation = (n % 2 == 0 and -25 or 25)
		end
		kit.Animate(vine, "Sway", 4, 0.8, index * 2.1)
	end
	-- feuilles au-dessus du rebord
	for _, l in ipairs({ { -8, -125, dark }, { 2, -80, light }, { 10, -50, dark } }) do
		leaf(hanger, kit, l[1], 36, l[2], 16, 11, l[3], 3)
	end
	local _, faceY = pot(hanger, kit, 0, 66, 42, 30, C.Cream, 5)
	kit.Face(hanger, 0, faceY, 20, { Z = 8 })
	kit.Animate(hanger, "Sway", 1.5, 0.6, 0.5)
	return { WallShadow = Vector2.new(0.42, 0.5) }
end

-- Tournesol : grande fleur souriante sur sa tige, pot en terre cuite
Art.Sunflower = function(body, kit, _item)
	local C = kit.C
	local flower = kit.Pivot(body, 50, 72, 3)
	kit.Line(flower, 0, 2, 0, -46, 4, C.Green, 0, 1)
	leaf(flower, kit, 0, -16, -160, 20, 12, C.Leaf, 2)
	leaf(flower, kit, 0, -24, -20, 20, 12, C.Leaf, 2)
	local hy = -48
	local petalLine = Color3.fromRGB(225, 160, 40)
	for k = 0, 5 do
		local a = math.rad(k * 30)
		local dx, dy = math.cos(a) * 14, math.sin(a) * 14
		local petal = kit.Line(flower, -dx, hy - dy, dx, hy + dy, 10, C.Yellow, 0, 3)
		kit.Stroke(petal, petalLine, 1.3)
	end
	kit.Blob(flower, 0, hy, 24, 24, Color3.fromRGB(205, 140, 90), { Z = 4, Shade = 0.1 })
	kit.Face(flower, 0, hy + 1, 18, { Eyes = "happy", Z = 5 })
	kit.Animate(flower, "Sway", 2, 0.6, 1.4)
	pot(body, kit, 50, 100, 42, 30, Color3.fromRGB(240, 160, 120))
	return nil
end

-- Bouquet dans un vase en verre, gros nœud rose
Art.Bouquet = function(body, kit, _item)
	local C = kit.C
	local flowers = kit.Pivot(body, 50, 62, 3)
	leaf(flowers, kit, 0, -4, -155, 22, 9, C.Leaf, 1)
	leaf(flowers, kit, 0, -4, -25, 22, 9, C.Leaf, 1)
	leaf(flowers, kit, 0, -4, -105, 30, 8, C.LeafDark, 1)
	for _, f in ipairs({ { -12, -22, 12, C.Pink }, { 11, -24, 11, Color3.fromRGB(255, 170, 120) }, { -1, -36, 10, C.Lilac } }) do
		local x, y, r, color = f[1], f[2], f[3], f[4]
		kit.Blob(flowers, x, y, r * 2, r * 1.85, color, { Z = 3, Shine = true })
		kit.Blob(flowers, x, y + 0.5, r * 1.1, r * 0.95, kit.Darken(color, 0.12), { Z = 4, Shade = false, Thickness = 1.2 })
		kit.Line(flowers, x - r * 0.25, y, x + r * 0.2, y - r * 0.15, 1.4, kit.Lighten(color, 0.4), 0.2, 5)
	end
	blossom(flowers, kit, -22, -8, 8, C.White, C.Yellow, 4)
	blossom(flowers, kit, 22, -8, 8, C.Sky, C.White, 4)
	for _, p in ipairs({ { -24, -30 }, { 24, -38 }, { 6, -46 } }) do
		kit.Circle(flowers, p[1], p[2], 4, 4, C.White, 0, 2)
	end
	kit.Animate(flowers, "Sway", 1.8, 0.6, 0.2)
	-- vase
	for _, dx in ipairs({ -3, 0, 3 }) do
		kit.Line(body, 50 + dx * 0.4, 64, 50 + dx, 94, 2, C.Green, 0.2, 4)
	end
	kit.Blob(body, 50, 88, 36, 18, C.Sky, { Z = 4, T = 0.45, Outline = false, Shade = false })
	kit.Blob(body, 50, 83, 42, 34, C.Glass, { Z = 5, T = 0.45, Outline = Color3.fromRGB(130, 170, 210) })
	kit.Part(body, 40, 58, 20, 12, C.Glass, { Z = 5, T = 0.45, Radius = 4, Outline = Color3.fromRGB(130, 170, 210) })
	kit.Shine(body, 34, 74, 4, 12, 6, 0.3)
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(body, 50 + side * 6, 68, 11, 7, C.Pink, { Z = 7, Rotation = side * 20, Shade = false, Thickness = 1.2 })
		kit.Line(body, 50 + side * 1, 70, 50 + side * 5, 78, 2.5, C.Pink, 0, 6)
	end
	kit.Circle(body, 50, 68, 5, 5, C.PinkDeep, 0, 8)
	return nil
end

-- Rose rouge sous cloche de verre, sur un socle en bois
Art.RedRose = function(body, kit, _item)
	local C = kit.C
	local red = Color3.fromRGB(240, 80, 100)
	kit.Line(body, 50, 86, 50, 52, 3, C.LeafDark, 0, 3)
	leaf(body, kit, 50, 74, -155, 15, 9, C.Leaf, 3)
	leaf(body, kit, 50, 68, -25, 15, 9, C.Leaf, 3)
	local rose = kit.Pivot(body, 50, 46, 4)
	kit.Blob(rose, -8, 2, 12, 15, kit.Darken(red, 0.12), { Z = 1, Rotation = -30, Shade = false })
	kit.Blob(rose, 8, 2, 12, 15, kit.Darken(red, 0.12), { Z = 1, Rotation = 30, Shade = false })
	kit.Blob(rose, 0, 0, 22, 20, red, { Z = 2, Shine = true })
	kit.Blob(rose, 0, -3, 13, 9, kit.Darken(red, 0.18), { Z = 3, Shade = false, Thickness = 1.2 })
	kit.Line(rose, -3, -3, 3, -4, 1.5, kit.Lighten(red, 0.35), 0.1, 4)
	kit.Animate(rose, "Bob", 0.8, 0.6, 0.5)
	local petal = kit.Blob(body, 60, 84, 6, 4, red, { Z = 5, Rotation = 25, Shade = false, Thickness = 1 })
	kit.Animate(petal, "Drift", 1.5, 0.4, 1)
	-- cloche
	kit.Part(body, 25, 16, 50, 76, C.Glass, { Radius = 25, Z = 6, T = 0.72, Outline = Color3.fromRGB(140, 180, 215), Thickness = 2, Shade = false })
	kit.Blob(body, 50, 14, 11, 9, C.Glass, { Z = 7, T = 0.3, Outline = Color3.fromRGB(140, 180, 215) })
	kit.Shine(body, 31, 28, 5, 26, 8, 0.35)
	kit.Shine(body, 32, 58, 4, 6, 8, 0.45)
	kit.Sparkle(body, 66, 30, 9, C.White, 0, 8)
	-- socle
	kit.Part(body, 20, 86, 60, 8, C.Wood, { Radius = -1, Z = 7 })
	kit.Part(body, 24, 92, 52, 8, C.WoodDark, { Radius = 3, Z = 6 })
	kit.Circle(body, 50, 96, 4, 4, C.Gold, 0, 8)
	return nil
end

-- Feuille de monstera (fentes sombres et nervure)
local function monsteraLeaf(parent, kit, px, py, angle, size, color, z)
	local a = math.rad(angle)
	local len, wid = size, size * 0.86
	local frame = kit.Blob(parent, px + math.cos(a) * len / 2, py + math.sin(a) * len / 2, len, wid, color, {
		Z = z,
		Rotation = angle,
		Shade = false,
		Thickness = 1.6,
	})
	local dark = kit.Darken(color, 0.28)
	kit.Line(frame, len * 0.06, wid / 2, len * 0.88, wid / 2, 1.6, dark, 0, 2)
	local ks = if size >= 28 then { 0.3, 0.5, 0.7 } else { 0.38, 0.64 }
	for _, k in ipairs(ks) do
		local e = 0.5 - 0.5 * math.sqrt(1 - (2 * k - 1) ^ 2) -- bord de l'ovale à cette abscisse
		kit.Line(frame, len * (k - 0.03), wid * e + 1.2, len * k + len * 0.04, wid * 0.4, 2.2, dark, 0, 2)
		kit.Line(frame, len * (k - 0.03), wid * (1 - e) - 1.2, len * k + len * 0.04, wid * 0.6, 2.2, dark, 0, 2)
	end
end

-- Monstera : grandes feuilles fendues sur un pot blanc façon terrazzo
Art.Monstera = function(body, kit, _item)
	local C = kit.C
	local plant = kit.Pivot(body, 50, 66, 3)
	local green, deep = Color3.fromRGB(95, 185, 110), Color3.fromRGB(80, 165, 100)
	local leaves = {
		{ -24, -6, -172, 24, deep },
		{ 24, -8, -8, 24, deep },
		{ -16, -26, -140, 30, green },
		{ 16, -32, -48, 32, green },
		{ -1, -36, -94, 28, Color3.fromRGB(110, 200, 120) },
	}
	for index, l in ipairs(leaves) do
		kit.Line(plant, 0, 0, l[1], l[2], 2.4, C.LeafDark, 0, 1)
		monsteraLeaf(plant, kit, l[1], l[2], l[3], l[4], l[5], index + 1)
	end
	kit.Animate(plant, "Sway", 1.5, 0.5, 2.6)
	local potBody = pot(body, kit, 50, 100, 54, 34, Color3.fromRGB(252, 247, 242))
	for _, d in ipairs({ { 7, 8, C.Pink }, { 20, 18, C.Sky }, { 33, 9, C.Butter }, { 12, 22, C.Mint } }) do
		kit.Circle(potBody, d[1], d[2], 4, 3.5, d[3], 0.1, 2)
	end
	return nil
end

-- Hibiscus : buisson vert foncé et deux grandes fleurs tropicales
Art.Hibiscus = function(body, kit, _item)
	local C = kit.C
	local bush = kit.Pivot(body, 50, 70, 3)
	for index, l in ipairs({ { -160, 24 }, { -130, 30 }, { -100, 32 }, { -75, 32 }, { -45, 30 }, { -18, 24 } }) do
		leaf(bush, kit, 0, 0, l[1], l[2], 11, index % 2 == 0 and C.LeafDark or C.Green, 1)
	end
	for _, f in ipairs({ { -11, -30, 13, Color3.fromRGB(255, 105, 150) }, { 14, -20, 11, Color3.fromRGB(255, 150, 120) } }) do
		local x, y, r, color = f[1], f[2], f[3], f[4]
		for k = 0, 4 do
			local a = math.rad(k * 72 - 90)
			kit.Blob(bush, x + math.cos(a) * r * 0.5, y + math.sin(a) * r * 0.5, r * 1.05, r * 0.95, color, {
				Z = 4,
				Rotation = k * 72,
				Shade = false,
				Thickness = 1.2,
			})
		end
		kit.Circle(bush, x, y, r * 0.55, r * 0.55, kit.Darken(color, 0.25), 0, 5)
		kit.Line(bush, x, y, x + r * 0.45, y - r * 0.75, 1.6, kit.Darken(color, 0.1), 0, 6)
		kit.Circle(bush, x + r * 0.5, y - r * 0.82, 3.5, 3.5, C.Yellow, 0, 6)
	end
	kit.Line(bush, 12, -24, 22, -36, 1.8, C.LeafDark, 0, 2)
	kit.Blob(bush, 23, -38, 6, 9, C.Pink, { Z = 3, Rotation = 30, Shade = false, Thickness = 1.2 })
	kit.Animate(bush, "Sway", 2, 0.6, 3.1)
	pot(body, kit, 50, 100, 44, 30, C.Mint)
	return nil
end

-- Trèfle à quatre feuilles (quatre cœurs) dans un petit pot qui sourit, étincelles dorées
Art.LuckyClover = function(body, kit, _item)
	local C = kit.C
	local clover = kit.Pivot(body, 50, 70, 3)
	kit.Line(clover, 0, 2, 1, -28, 3, C.LeafDark, 0, 1)
	local cy = -36
	local green = Color3.fromRGB(100, 200, 110)
	for k = 0, 3 do
		local a = math.rad(k * 90 - 90)
		local h = kit.Heart(clover, math.cos(a) * 8.5, cy + math.sin(a) * 8.5, 19, k % 2 == 0 and green or C.Leaf, 0, 2)
		h.Rotation = k * 90
	end
	kit.Circle(clover, 0, cy, 5, 5, C.LeafDark, 0, 3)
	kit.Animate(clover, "Sway", 3, 0.7, 0.9)
	kit.Sparkle(body, 22, 30, 9, C.Gold, 0, 6)
	kit.Sparkle(body, 80, 44, 7, C.Gold, 0, 6)
	local _, faceY = pot(body, kit, 50, 100, 46, 32, C.MintSoft)
	kit.Face(body, 50, faceY, 20, { Eyes = "happy", Z = 8 })
	return nil
end

-- Terrarium : bocal en verre, mousse, succulente, champignon et petit escargot
Art.Terrarium = function(body, kit, _item)
	local C = kit.C
	-- contenu (derrière le verre)
	kit.Part(body, 21, 66, 58, 31, C.Brown, { Radius = 19, Z = 2, Outline = false, Shade = 0.25 })
	kit.Box(body, 22, 78, 56, 4, C.Butter, 0.2, 2)
	for _, p in ipairs({ { 30, 88, 7 }, { 46, 91, 5 }, { 64, 89, 7 } }) do
		kit.Circle(body, p[1], p[2], p[3], p[3] * 0.7, C.Grey, 0, 3)
	end
	kit.Blob(body, 50, 69, 56, 10, C.Green, { Z = 3, Shade = false, Thickness = 1.2 })
	leaf(body, kit, 30, 68, -130, 14, 7, C.Mint, 4, false)
	leaf(body, kit, 30, 68, -50, 14, 7, C.Mint, 4, false)
	leaf(body, kit, 30, 68, -90, 16, 7, Color3.fromRGB(130, 220, 185), 4, false)
	kit.Part(body, 69, 58, 4, 10, C.Cream, { Radius = 2, Z = 4, Thickness = 1.2 })
	kit.Blob(body, 71, 58, 12, 8, C.Red, { Z = 5, Thickness = 1.2 })
	kit.Circle(body, 68.5, 57, 2.5, 2.5, C.White, 0, 6)
	-- escargot
	local snail = kit.Group(body, 38, 49, 28, 18, 5)
	kit.Part(snail, 2, 12, 24, 6, C.Butter, { Radius = -1, Z = 1, Thickness = 1.2 })
	kit.Blob(snail, 21, 9, 8, 11, C.Butter, { Z = 2, Thickness = 1.2 })
	kit.Line(snail, 20, 4, 18, -1, 1, C.Ink, 0, 1)
	kit.Line(snail, 23, 4, 25, -1, 1, C.Ink, 0, 1)
	kit.Blob(snail, 10, 8, 14, 13, C.Pink, { Z = 3, Shine = true, Thickness = 1.3 })
	kit.Circle(snail, 10, 8.5, 6, 6, C.PinkDeep, 0.3, 4)
	kit.Face(snail, 21.5, 9, 8, { Mouth = "none", Z = 3 })
	kit.Animate(snail, "Drift", 3, 0.3, 0.7)
	-- bocal
	kit.Part(body, 20, 22, 60, 76, C.Glass, { Radius = 20, Z = 7, T = 0.74, Outline = Color3.fromRGB(140, 180, 215), Thickness = 2, Shade = false })
	kit.Part(body, 31, 16, 38, 9, C.Glass, { Radius = -1, Z = 8, T = 0.45, Outline = Color3.fromRGB(140, 180, 215) })
	kit.Part(body, 35, 5, 30, 13, C.WoodLight, { Radius = 4, Z = 6, Shine = true })
	kit.Shine(body, 26, 32, 4.5, 22, 9, 0.35)
	kit.Sparkle(body, 70, 34, 8, C.White, 0, 9)
	return nil
end

-- Branche de cerisier dans un vase : fleurs roses, boutons et pétales qui tombent
Art.CherryBlossom = function(body, kit, _item)
	local C = kit.C
	local branch = kit.Pivot(body, 50, 60, 3)
	local brown = Color3.fromRGB(140, 95, 80)
	local segments = {
		{ 0, 0, -8, -24, 3.6 },
		{ -8, -24, -22, -42, 3 },
		{ -8, -24, -4, -52, 2.6 },
		{ 0, 0, 10, -22, 3.4 },
		{ 10, -22, 26, -36, 2.8 },
		{ 10, -22, 32, -16, 2.4 },
		{ -22, -42, -36, -36, 2.2 },
	}
	for _, s in ipairs(segments) do
		kit.Line(branch, s[1], s[2], s[3], s[4], s[5], brown, 0, 1)
	end
	local petal, heart = Color3.fromRGB(255, 200, 220), C.PinkDeep
	for _, f in ipairs({ { -22, -43, 13 }, { -4, -53, 12 }, { 26, -37, 13 }, { 32, -16, 11 }, { -36, -35, 10 }, { 4, -28, 10 } }) do
		blossom(branch, kit, f[1], f[2], f[3], petal, heart, 2)
	end
	for _, b in ipairs({ { -14, -30 }, { 18, -30 }, { -30, -46 }, { 38, -22 } }) do
		kit.Blob(branch, b[1], b[2], 5, 5, C.Pink, { Z = 2, Shade = false, Thickness = 1 })
	end
	kit.Animate(branch, "Sway", 1.5, 0.5, 0.6)
	local fall1 = kit.Blob(body, 18, 70, 5, 4, petal, { Z = 6, Rotation = 30, Shade = false, Thickness = 1 })
	kit.Animate(fall1, "Bob", 3, 0.5, 0.3)
	local fall2 = kit.Blob(body, 82, 58, 5, 4, petal, { Z = 6, Rotation = -20, Shade = false, Thickness = 1 })
	kit.Animate(fall2, "Drift", 3, 0.5, 1.9)
	-- vase
	local vase = Color3.fromRGB(235, 228, 255)
	kit.Part(body, 36, 62, 28, 38, vase, { Radius = 12, Z = 5, Shine = true })
	kit.Part(body, 41, 55, 18, 12, vase, { Radius = 4, Z = 4 })
	kit.Part(body, 38, 53, 24, 5, kit.Lighten(vase, 0.3), { Radius = -1, Z = 6 })
	kit.Box(body, 36.8, 78, 26.4, 4, C.PinkSoft, 0, 6)
	blossom(body, kit, 50, 90, 7, C.Pink, C.White, 6)
	return nil
end

-- Petit sapin en pot : trois étages doux, pommes de pin, pot bleu qui sourit
Art.MiniPine = function(body, kit, _item)
	local C = kit.C
	local tree = anchored(body, kit, 50, 76, 3)
	local green = Color3.fromRGB(95, 180, 120)
	kit.Part(tree, 45, 56, 10, 20, C.WoodDark, { Radius = 3, Z = 1 })
	tier(tree, kit, 50, 28, 34, kit.Darken(green, 0.06), 2)
	tier(tree, kit, 50, 14, 26, green, 4)
	tier(tree, kit, 50, 2, 18, kit.Lighten(green, 0.08), 6)
	for _, p in ipairs({ { 38, 54, C.Pink }, { 64, 50, C.Butter }, { 44, 33, C.Sky }, { 58, 20, C.Pink } }) do
		kit.Circle(tree, p[1], p[2], 5, 5, p[3], 0, 9)
	end
	kit.Heart(tree, 50, 2, 8, C.Pink, 0, 9)
	kit.Animate(tree, "Breathe", 0.012, 0.8, 0.5)
	local snow = kit.Circle(body, 84, 30, 4, 4, C.White, 0.1, 6)
	kit.Animate(snow, "Bob", 3, 0.4, 0.2)
	local potBody, faceY = pot(body, kit, 50, 100, 44, 28, C.Sky)
	kit.Face(body, 50, faceY, 18, { Z = 8 })
	kit.Box(potBody, 0, 3, potBody.Size.X.Offset, 2.5, C.White, 0.4, 2)
	return nil
end

-- Champignon géant : chapeau rouge à pois, pied crème qui sourit, deux petits champignons
Art.GiantMushroom = function(body, kit, _item)
	local C = kit.C
	local red = Color3.fromRGB(245, 95, 110)
	-- petits champignons
	for _, m in ipairs({ { 12, 13, C.Pink, 0.5 }, { 88, 10, C.Butter, 2.2 } }) do
		local mini = kit.Pivot(body, m[1], 100, 3)
		local s = m[2]
		kit.Part(mini, -s * 0.2, -s * 1.05, s * 0.4, s * 1.05, C.Cream, { Radius = 3, Z = 1, Thickness = 1.2 })
		kit.Part(mini, -s * 0.6, -s * 1.4, s * 1.2, s * 0.6, m[3], { Radius = -1, Z = 2, Thickness = 1.3 })
		kit.Circle(mini, -s * 0.15, -s * 1.2, s * 0.2, s * 0.2, C.White, 0, 3)
		kit.Animate(mini, "Sway", 4, 0.7, m[4])
	end
	local shroom = anchored(body, kit, 50, 100, 4)
	-- pied
	kit.Part(shroom, 30, 50, 40, 50, C.Cream, { Radius = 16, Z = 1, Shine = true })
	kit.Face(shroom, 50, 75, 26, { Z = 3 })
	-- chapeau (demi-ovale découpé)
	local cap = kit.Group(shroom, 2, 6, 96, 48, 3, true)
	kit.Blob(cap, 48, 48, 92, 88, red, { Z = 1, Thickness = 2 })
	kit.Part(shroom, 4, 46, 92, 12, kit.Darken(red, 0.08), { Radius = -1, Z = 4, Shade = 0.1 })
	kit.Part(shroom, 16, 53, 68, 6, C.PinkSoft, { Radius = -1, Z = 2, Shade = false })
	for _, d in ipairs({ { 28, 22, 13 }, { 58, 14, 10 }, { 76, 32, 12 }, { 46, 36, 8 }, { 14, 40, 6 } }) do
		kit.Blob(cap, d[1] - 2, d[2] - 6 + 6, d[3], d[3] * 0.85, C.White, { Z = 2, Shade = false, Outline = false })
	end
	kit.Shine(cap, 20, 10, 16, 5, 3, 0.4)
	kit.Animate(shroom, "Breathe", 0.012, 0.7, 1.3)
	-- touffes d'herbe
	for _, g in ipairs({ { 26, 97, -110 }, { 28, 97, -75 }, { 72, 97, -105 }, { 74, 97, -70 } }) do
		leaf(body, kit, g[1], g[2], g[3], 10, 4, C.Leaf, 5, false)
	end
	return nil
end

-- Arbre d'intérieur : feuillage en nuage avec petites pommes, grand pot rose qui sourit
Art.IndoorTree = function(body, kit, _item)
	local C = kit.C
	local tree = kit.Pivot(body, 50, 64, 3)
	kit.Part(tree, -4, -34, 8, 36, C.WoodDark, { Radius = 3, Z = 1 })
	kit.Line(tree, 0, -20, 10, -30, 3, C.WoodDark, 0, 1)
	local g1, g2, g3 = C.LeafDark, C.Leaf, Color3.fromRGB(150, 220, 130)
	local puffs = {
		{ -22, -40, 34, 30, g1 },
		{ 22, -42, 34, 30, g1 },
		{ -14, -58, 36, 32, g2 },
		{ 14, -60, 36, 32, g2 },
		{ 0, -50, 44, 36, g2 },
		{ 0, -72, 34, 26, g3 },
	}
	for index, p in ipairs(puffs) do
		kit.Blob(tree, p[1], p[2], p[3], p[4], p[5], { Z = index + 1, Shade = 0.08, Thickness = 1.6 })
	end
	kit.Shine(tree, -8, -80, 12, 4, 9, 0.45)
	for _, a in ipairs({ { -22, -44 }, { 18, -52 }, { -6, -62 }, { 26, -38 }, { 6, -40 } }) do
		local apple = kit.Blob(tree, a[1], a[2], 7, 7, C.Red, { Z = 8, Thickness = 1.1 })
		kit.Circle(apple, 2.2, 2.2, 2, 2, C.White, 0.2, 2)
	end
	kit.Animate(tree, "Sway", 1.2, 0.5, 1.7)
	local potBody, faceY = pot(body, kit, 50, 100, 54, 38, C.PinkSoft)
	kit.Face(body, 50, faceY, 24, { Z = 8 })
	kit.Box(potBody, 0, 4, potBody.Size.X.Offset, 3, C.Pink, 0.3, 2)
	return nil
end

-- Bambou à vœux (Tanabata) : tiges vertes, feuilles fines, papiers à vœux colorés
Art.Bamboo = function(body, kit, _item)
	local C = kit.C
	local plant = kit.Pivot(body, 50, 80, 3)
	local green = Color3.fromRGB(130, 200, 110)
	local stalks = { { -10, -70 }, { 2, -80 }, { 13, -62 } }
	for index, s in ipairs(stalks) do
		local x, top = s[1], s[2]
		local stalk = kit.Part(plant, x - 4, top, 8, -top + 2, kit.Lighten(green, (index - 1) * 0.08), { Radius = 4, Z = 2 + index, Shine = true })
		for y = 14, -top - 8, 16 do
			kit.Box(stalk, -0.5, y, 9, 2, kit.Darken(green, 0.3), 0.2, 2)
		end
	end
	local leaves = {
		{ -10, -64, -150, 22 },
		{ -10, -50, -170, 18 },
		{ 2, -76, -60, 22 },
		{ 2, -72, -115, 20 },
		{ 13, -56, -25, 22 },
		{ 13, -44, -5, 18 },
		{ -10, -36, -165, 16 },
	}
	for _, l in ipairs(leaves) do
		leaf(plant, kit, l[1], l[2], l[3], l[4], 6.5, C.Leaf, 6, false)
	end
	local papers = {
		{ -26, -62, C.Pink },
		{ -24, -40, C.Sky },
		{ 22, -70, C.Butter },
		{ 30, -48, C.Lilac },
		{ 26, -30, C.Mint },
	}
	for index, p in ipairs(papers) do
		local strip = kit.Pivot(plant, p[1], p[2], 7)
		kit.Line(strip, 0, 0, 0, 5, 1, C.Ink, 0.3, 1)
		kit.Part(strip, -3.5, 4, 7, 14, p[3], { Radius = 1.5, Z = 2, Thickness = 1.2 })
		kit.Animate(strip, "Sway", 6, 0.9, index * 1.3)
	end
	kit.Animate(plant, "Sway", 1, 0.4, 0.9)
	-- jardinière en bois
	kit.Part(body, 28, 76, 44, 24, C.WoodLight, { Radius = 5, Z = 5 })
	kit.Part(body, 25, 74, 50, 7, C.Wood, { Radius = -1, Z = 6, Shine = true })
	kit.Box(body, 29, 88, 42, 2.5, C.Wood, 0, 6)
	kit.Heart(body, 50, 89, 9, C.PinkDeep, 0, 7)
	return nil
end

-- Palmier en pot : tronc écaillé courbé, grandes palmes, noix de coco
Art.PalmTree = function(body, kit, _item)
	local C = kit.C
	local palm = kit.Pivot(body, 50, 72, 3)
	local trunk = { { 0, -4 }, { 1, -12 }, { 2.5, -20 }, { 4, -28 }, { 5.5, -36 }, { 6.5, -44 }, { 7, -52 } }
	for index, t in ipairs(trunk) do
		kit.Blob(palm, t[1], t[2], 15 - index * 0.6, 11, index % 2 == 0 and C.Wood or C.WoodLight, { Z = index, Thickness = 1.4 })
	end
	local top = kit.Pivot(palm, 7, -56, 9)
	local fronds = {
		{ -165, 36, C.LeafDark },
		{ -15, 36, C.LeafDark },
		{ -125, 34, C.Leaf },
		{ -55, 34, C.Leaf },
		{ 160, 32, C.Green },
		{ 20, 32, C.Green },
		{ -90, 26, Color3.fromRGB(150, 220, 130) },
	}
	for index, f in ipairs(fronds) do
		leaf(top, kit, 0, 0, f[1], f[2], 13, f[3], index)
	end
	for _, c in ipairs({ { -5, 4 }, { 4, 5 }, { 0, -1 } }) do
		local nut = kit.Blob(top, c[1], c[2], 9, 9, C.Brown, { Z = 9, Thickness = 1.2 })
		kit.Circle(nut, 2.5, 2.5, 2.5, 2.5, C.White, 0.4, 2)
	end
	kit.Animate(top, "Sway", 2.5, 0.6, 0.4)
	kit.Animate(palm, "Sway", 0.8, 0.4, 2)
	-- panier tressé
	kit.Part(body, 28, 72, 44, 28, C.WoodLight, { Radius = 10, Z = 5, Shade = 0.18 })
	for _, y in ipairs({ 80, 88 }) do
		kit.Box(body, 30, y, 40, 2, C.Wood, 0, 6)
	end
	kit.Part(body, 25, 69, 50, 8, C.Wood, { Radius = -1, Z = 7, Shine = true })
	return nil
end

-- Sapin de fête : étoile, guirlande lumineuse qui scintille, boules, cadeaux
Art.HolidayTree = function(body, kit, _item)
	local C = kit.C
	local green = Color3.fromRGB(90, 175, 115)
	kit.Part(body, 45, 70, 10, 14, C.WoodDark, { Radius = 3, Z = 1 })
	tier(body, kit, 50, 34, 40, kit.Darken(green, 0.06), 2)
	tier(body, kit, 50, 18, 30, green, 4)
	tier(body, kit, 50, 6, 20, kit.Lighten(green, 0.08), 6)
	kit.Face(body, 50, 44, 20, { Eyes = "happy", Z = 8 })
	-- guirlandes + ampoules
	local colors = { C.Heart, C.Butter, C.Sky, C.Mint, C.Lilac }
	local garlands = {
		{ 36, 24, 64, 20, 3 },
		{ 28, 53, 72, 48, 4 },
		{ 18, 72, 82, 66, 5 },
	}
	local n = 0
	for _, g in ipairs(garlands) do
		kit.Line(body, g[1], g[2], g[3], g[4], 1.4, C.Gold, 0.2, 8)
		for k = 0, g[5] - 1 do
			local t = (k + 0.5) / g[5]
			n += 1
			local bulb = kit.Circle(body, g[1] + (g[3] - g[1]) * t, g[2] + (g[4] - g[2]) * t + 2, 5.5, 5.5, colors[(n - 1) % #colors + 1], 0, 9)
			kit.Stroke(bulb, C.White, 1, 0.3)
			kit.Animate(bulb, "Pulse", 0.6, 1.2, n * 1.37)
		end
	end
	for _, b in ipairs({ { 32, 42, C.PinkDeep }, { 70, 40, C.Blue }, { 38, 62, C.Gold }, { 64, 61, C.Pink } }) do
		local ball = kit.Blob(body, b[1], b[2], 8, 8, b[3], { Z = 8, Thickness = 1.2 })
		kit.Circle(ball, 2.4, 2.4, 2.4, 2.4, C.White, 0.2, 2)
	end
	-- étoile
	local star = kit.Pivot(body, 50, 6, 9)
	kit.Part(star, -7, -7, 14, 14, C.Yellow, { Radius = 1, Z = 1, Outline = C.Gold })
	kit.Part(star, -7, -7, 14, 14, C.Yellow, { Radius = 1, Z = 2, Rotation = 45, Outline = C.Gold })
	kit.Shine(star, -4, -4, 4, 3, 3, 0.3)
	kit.Animate(star, "Sway", 6, 0.6, 0)
	-- seau + cadeaux
	kit.Part(body, 38, 80, 24, 20, C.Red, { Radius = 5, Z = 3 })
	kit.Part(body, 36, 78, 28, 6, kit.Lighten(C.Red, 0.25), { Radius = -1, Z = 4, Shine = true })
	for _, g in ipairs({ { 8, 82, 22, 18, C.Sky, C.Pink }, { 72, 86, 20, 14, C.Pink, C.Butter } }) do
		local x, y, w, h = g[1], g[2], g[3], g[4]
		local gift = kit.Part(body, x, y, w, h, g[5], { Radius = 3, Z = 5, Shine = true })
		kit.Box(gift, w / 2 - 2, 0, 4, h, g[6], 0, 2)
		kit.Blob(body, x + w / 2 - 4, y - 1, 8, 6, g[6], { Z = 6, Rotation = -20, Shade = false, Thickness = 1.2 })
		kit.Blob(body, x + w / 2 + 4, y - 1, 8, 6, g[6], { Z = 6, Rotation = 20, Shade = false, Thickness = 1.2 })
	end
	return { Glow = Color3.fromRGB(255, 225, 150) }
end

return Art
