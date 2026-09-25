--[[
	Kitchen (ModuleScript) — dessins 🍰 de la cuisine
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Kitchen
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- Petits outils partagés
----------------------------------------------------------------------

-- Volute de vapeur (3 traits blancs en zigzag) qui monte et descend
local function steam(body, kit, x, bottom, h, phase)
	local g = kit.Group(body, x - 6, bottom - h, 12, h, 8)
	local pts = { { 6, h }, { 3, h * 0.66 }, { 8.5, h * 0.33 }, { 5, 0 } }
	for i = 1, 3 do
		local a, b = pts[i], pts[i + 1]
		kit.Line(g, a[1], a[2], b[1], b[2], 2.6, WHITE, 0.15 + i * 0.15, 1)
	end
	kit.Animate(g, "Bob", 1.5, 0.8, phase)
	return g
end

-- Fraise (ovale rouge, pépins, collerette verte)
local function strawberry(parent, kit, cx, cy, s, z)
	local C = kit.C
	local berry = kit.Blob(parent, cx, cy, s, s * 1.08, C.Red, { Z = z, Thickness = 1.2 })
	for _, p in ipairs({ { 0.3, 0.42 }, { 0.66, 0.5 }, { 0.46, 0.74 } }) do
		kit.Circle(berry, s * p[1], s * 1.08 * p[2], math.max(1.2, s * 0.1), math.max(1.4, s * 0.13), C.Butter, 0, 2)
	end
	kit.Shine(berry, s * 0.18, s * 0.16, s * 0.2, s * 0.14, 3, 0.3)
	kit.Blob(parent, cx, cy - s * 0.5, s * 0.72, s * 0.3, C.Leaf, { Z = (z or 2) + 1, Thickness = 1.1, Shade = false })
	return berry
end

-- Anneau (anse de tasse, de théière...) : contour foncé + couleur + bord intérieur
local function ring(parent, kit, x, y, w, h, color, thick, z)
	local ink = kit.OutlineOf(color)
	kit.Part(parent, x, y, w, h, color, { Radius = -1, T = 1, Outline = ink, Thickness = thick + 3, Shade = false, Z = z })
	kit.Part(parent, x, y, w, h, color, { Radius = -1, T = 1, Outline = color, Thickness = thick, Shade = false, Z = z })
	kit.Part(parent, x + 1.4, y + 1.4, w - 2.8, h - 2.8, color, { Radius = -1, T = 1, Outline = ink, Thickness = 1.4, Shade = false, Z = z })
end

-- Formes unies avec un seul contour (sous-couche foncée puis remplissage)
local function union(parent, kit, shapes, color, z, thickness)
	local ink = kit.OutlineOf(color)
	local t = thickness or 1.6
	local fills = {}
	for _, s in ipairs(shapes) do
		local r = if s[5] < 0 then -1 else s[5] + t
		kit.Part(parent, s[1] - t, s[2] - t, s[3] + 2 * t, s[4] + 2 * t, ink, { Radius = r, Z = z, Outline = false, Shade = false })
	end
	for _, s in ipairs(shapes) do
		table.insert(fills, kit.Part(parent, s[1], s[2], s[3], s[4], color, { Radius = s[5], Z = z + 1, Outline = false, Shade = false }))
	end
	return fills
end

-- Coulure (pilule verticale arrondie)
local function drip(parent, kit, x, y, w, h, color, z, outline)
	return kit.Part(parent, x - w / 2, y, w, h, color, { Radius = -1, Z = z, Outline = outline or false, Shade = false, Thickness = 1.2 })
end

-- Cupcake : caissette rayée, crème en tourbillon, cerise
local function cupcake(parent, kit, cx, bottom, s, frost, wrap, z)
	local C = kit.C
	local cup = kit.Part(parent, cx - s * 0.34, bottom - s * 0.44, s * 0.68, s * 0.44, wrap, { Radius = 3, Z = z })
	for _, k in ipairs({ 0.33, 0.66 }) do
		kit.Box(cup, s * 0.68 * k - 0.6, 2, 1.2, s * 0.44 - 4, kit.OutlineOf(wrap), 0.55, 2)
	end
	kit.Blob(parent, cx, bottom - s * 0.46, s * 0.86, s * 0.28, frost, { Z = z + 1 })
	kit.Blob(parent, cx, bottom - s * 0.65, s * 0.62, s * 0.24, frost, { Z = z + 2, Shine = true })
	kit.Blob(parent, cx, bottom - s * 0.8, s * 0.32, s * 0.18, frost, { Z = z + 3 })
	kit.Blob(parent, cx, bottom - s * 0.93, s * 0.2, s * 0.2, C.Red, { Z = z + 4, Thickness = 1.1, Shine = true })
	return cup
end

-- Onigiri : triangle arrondi (losange + base), nori, visage
local function onigiri(parent, kit, cx, bottom, w, z, eyes)
	local rice = Color3.fromRGB(255, 253, 248)
	local ink = kit.OutlineOf(Color3.fromRGB(225, 215, 215))
	local h = w * 0.95
	local s = w * 0.62
	local cyD = bottom - h * 0.46
	kit.Part(parent, cx - (s + 3.2) / 2, cyD - (s + 3.2) / 2, s + 3.2, s + 3.2, ink, { Rotation = 45, Radius = s * 0.3 + 1.6, Outline = false, Shade = false, Z = z })
	kit.Part(parent, cx - w / 2, bottom - h * 0.5, w, h * 0.5, rice, { Radius = w * 0.22, Z = z + 1, Outline = ink })
	kit.Part(parent, cx - s / 2, cyD - s / 2, s, s, rice, { Rotation = 45, Radius = s * 0.3, Outline = false, Shade = false, Z = z + 2 })
	kit.Part(parent, cx - w * 0.2, bottom - h * 0.3, w * 0.4, h * 0.3, Color3.fromRGB(60, 80, 70), { Radius = 2, Z = z + 3 })
	kit.Face(parent, cx, bottom - h * 0.47, w * 0.5, { Eyes = eyes, Mouth = "smile", Z = z + 3 })
	kit.Shine(parent, cx - w * 0.3, bottom - h * 0.52, w * 0.12, w * 0.07, z + 3, 0.2)
	return nil
end

-- Donut vu de biais : pâte, glaçage, trou, vermicelles
local function donut(parent, kit, cx, cy, w, icing, sprinkles, z, rot)
	local g = kit.Group(parent, cx - w / 2, cy - w * 0.42, w, w * 0.84, z)
	g.Rotation = rot or 0
	local h = w * 0.84
	kit.Blob(g, w / 2, h / 2, w, h, Color3.fromRGB(235, 175, 105), { Z = 1 })
	local top = kit.Blob(g, w / 2, h * 0.45, w * 0.88, h * 0.72, icing, { Z = 2, Shine = true })
	kit.Blob(g, w / 2, h * 0.4, w * 0.22, h * 0.14, Color3.fromRGB(190, 125, 85), { Z = 3, Outline = false, Shade = false })
	for i, p in ipairs({ { 0.2, 0.55, 30 }, { 0.72, 0.3, -40 }, { 0.8, 0.62, 70 } }) do
		local sp = kit.Box(top, w * 0.88 * p[1], h * 0.72 * p[2], w * 0.1, 1.6, sprinkles[(i - 1) % #sprinkles + 1], 0, 4)
		sp.Rotation = p[3]
		kit.Round(sp)
	end
	return g
end

----------------------------------------------------------------------
-- Petits plats
----------------------------------------------------------------------

-- Tasse de chocolat chaud rose : guimauves, vapeur, visage content
Art.CocoaMug = function(body, kit, _item)
	local C = kit.C
	local mug = Color3.fromRGB(255, 188, 212)
	ring(body, kit, 60, 50, 26, 32, mug, 4.5, 2)
	local cup = kit.Part(body, 14, 36, 54, 62, mug, { Radius = 14, Z = 4, Shine = true })
	for _, p in ipairs({ { 8, 44 }, { 46, 52 }, { 10, 20 } }) do
		kit.Circle(cup, p[1], p[2], 5, 5, WHITE, 0.45, 2)
	end
	kit.Blob(body, 41, 38, 54, 14, kit.Lighten(mug, 0.45), { Z = 5 })
	kit.Blob(body, 41, 39, 44, 8, Color3.fromRGB(150, 90, 70), { Z = 6, Outline = false, Shade = false })
	kit.Part(body, 29, 32, 9, 8, WHITE, { Radius = 2.5, Z = 7, Rotation = -12 })
	kit.Part(body, 41, 31, 9, 8, C.PinkSoft, { Radius = 2.5, Z = 7, Rotation = 10 })
	kit.Part(body, 49, 34, 8, 7, WHITE, { Radius = 2.5, Z = 7, Rotation = 25 })
	steam(body, kit, 34, 26, 20, 0)
	steam(body, kit, 50, 24, 16, 1.7)
	kit.Face(body, 41, 70, 26, { Eyes = "happy", Mouth = "cat", Z = 6 })
	return nil
end

-- Bouteille de lait fraise : capuchon en tissu vichy, étiquette fraise, visage
Art.StrawberryMilk = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 185, 210)
	union(body, kit, { { 36, 22, 28, 24, 8 }, { 23, 38, 54, 60, 18 } }, pink, 2)
	kit.Shine(body, 29, 46, 5, 30, 4, 0.35)
	kit.Shine(body, 40, 26, 3.5, 10, 4, 0.35)
	local cap = kit.Part(body, 31, 13, 38, 13, WHITE, { Radius = 5, Z = 5 })
	for i = 0, 4 do
		kit.Box(cap, 2 + i * 7, 1.5 + (i % 2) * 5, 5, 5, C.Pink, 0.3, 2)
	end
	kit.Part(body, 32, 24, 36, 3, C.PinkDeep, { Radius = -1, Z = 6, Outline = false })
	kit.Blob(body, 66, 26, 8, 6, C.PinkDeep, { Z = 7, Rotation = 25 })
	kit.Blob(body, 69, 30, 7, 5, C.PinkDeep, { Z = 7, Rotation = 70 })
	kit.Blob(body, 50, 77, 36, 28, WHITE, { Z = 4, Outline = kit.OutlineOf(C.PinkSoft) })
	strawberry(body, kit, 50, 78, 15, 5)
	kit.Heart(body, 37, 76, 6, C.Pink, 0, 6)
	kit.Heart(body, 63, 76, 6, C.Pink, 0, 6)
	kit.Face(body, 50, 54, 24, { Eyes = "dot", Mouth = "o", Z = 5 })
	return nil
end

-- Pastèque entière rayée + tranche souriante devant
Art.Watermelon = function(body, kit, _item)
	local C = kit.C
	local green = Color3.fromRGB(125, 205, 115)
	local stripe = Color3.fromRGB(70, 150, 80)
	local melon = kit.Blob(body, 36, 64, 62, 56, green, { Z = 2, Shine = true })
	for _, s in ipairs({ { 31, 7, 52 }, { 14, 5, 38 }, { 48, 5, 38 } }) do
		kit.Blob(melon, s[1], 28, s[2], s[3], stripe, { Z = 2, Outline = false, Shade = false })
	end
	kit.Line(body, 36, 37, 38, 31, 2.4, C.WoodDark, 0, 3)
	local g = kit.Group(body, 36, 68, 60, 32, 4, true)
	kit.Circle(g, 30, 0, 62, 62, Color3.fromRGB(90, 175, 90), 0, 1)
	kit.Circle(g, 30, 0, 54, 54, Color3.fromRGB(235, 250, 220), 0, 2)
	local flesh = kit.Circle(g, 30, 0, 48, 48, Color3.fromRGB(255, 105, 120), 0, 3)
	kit.Gradient(flesh, WHITE, Color3.fromRGB(235, 225, 225), 90)
	kit.Box(g, 0, 0, 60, 1.6, kit.OutlineOf(Color3.fromRGB(90, 175, 90)), 0, 5)
	for _, p in ipairs({ { 12, 8, 30 }, { 48, 8, -30 }, { 22, 17, 15 }, { 38, 17, -15 }, { 30, 20, 0 } }) do
		local seed = kit.Circle(g, p[1], p[2], 2.4, 3.6, Color3.fromRGB(70, 40, 50), 0, 4)
		seed.Rotation = p[3]
	end
	kit.Face(g, 30, 8, 22, { Eyes = "happy", Mouth = "smile", Z = 5 })
	return nil
end

-- Théière menthe : couvercle rose, bec, anse, petits cœurs, vapeur
Art.Teapot = function(body, kit, _item)
	local C = kit.C
	local mint = Color3.fromRGB(165, 228, 205)
	ring(body, kit, 70, 52, 22, 30, mint, 4.5, 1)
	kit.Part(body, 4, 55, 28, 11, mint, { Radius = 5, Rotation = 48, Z = 2 })
	kit.Blob(body, 8, 48, 8, 6, kit.Darken(mint, 0.25), { Z = 3, Outline = false, Rotation = 48 })
	kit.Part(body, 34, 90, 32, 8, kit.Darken(mint, 0.1), { Radius = 4, Z = 2 })
	local pot = kit.Blob(body, 50, 70, 58, 46, mint, { Z = 3, Shine = true })
	kit.Heart(pot, 9, 26, 7, C.Pink, 0, 3)
	kit.Heart(pot, 49, 26, 7, C.Pink, 0, 3)
	kit.Blob(body, 50, 48, 38, 10, C.PinkSoft, { Z = 4 })
	kit.Blob(body, 50, 42, 26, 10, kit.Lighten(C.Pink, 0.35), { Z = 5, Shine = true })
	kit.Blob(body, 50, 35, 9, 8, C.Pink, { Z = 6 })
	kit.Face(body, 50, 72, 24, { Eyes = "dot", Mouth = "cat", Z = 6 })
	steam(body, kit, 8, 42, 18, 0.6)
	return nil
end

-- Boîte de donuts ouverte : couvercle, 3 donuts glacés
Art.DonutBox = function(body, kit, _item)
	local C = kit.C
	local box = Color3.fromRGB(255, 190, 215)
	local lid = kit.Part(body, 10, 28, 80, 36, kit.Lighten(box, 0.4), { Radius = 6, Z = 1, Rotation = -6 })
	kit.Heart(lid, 40, 16, 14, C.Pink, 0, 2)
	local sprinkles = { C.Sky, C.Butter, C.Mint, WHITE }
	donut(body, kit, 24, 60, 30, Color3.fromRGB(255, 160, 200), sprinkles, 3, -12)
	donut(body, kit, 76, 60, 30, Color3.fromRGB(160, 105, 85), sprinkles, 3, 12)
	donut(body, kit, 50, 55, 32, Color3.fromRGB(190, 240, 215), { C.Pink, C.Lilac, WHITE }, 4, 0)
	local front = kit.Part(body, 6, 66, 88, 32, box, { Radius = 6, Z = 7, Shine = true })
	kit.Box(front, 0, 23, 88, 4, WHITE, 0.3, 2)
	kit.Face(front, 44, 14, 24, { Eyes = "happy", Mouth = "cat", Z = 3 })
	kit.Heart(front, 12, 12, 8, C.PinkDeep, 0, 3)
	kit.Heart(front, 76, 12, 8, C.PinkDeep, 0, 3)
	return nil
end

-- Pudding tremblotant : caramel qui coule, crème, cerise (respire)
Art.Pudding = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 94, 80, 12, C.LilacSoft, { Z = 1 })
	local g = kit.Group(body, 22, 36, 56, 58, 2)
	g.AnchorPoint = Vector2.new(0.5, 1)
	g.Position = UDim2.fromOffset(50, 94)
	local custard = Color3.fromRGB(255, 226, 140)
	local caramel = Color3.fromRGB(200, 120, 60)
	union(g, kit, { { 7, 10, 42, 32, 14 }, { 1, 26, 54, 30, 12 } }, custard, 1)
	kit.Part(g, 6, 10, 44, 13, caramel, { Radius = 7, Z = 4, Shine = true })
	for _, d in ipairs({ { 12, 10 }, { 22, 7 }, { 37, 12 }, { 45, 6 } }) do
		drip(g, kit, d[1], 16, 4.5, d[2], caramel, 4)
	end
	kit.Shine(g, 5, 30, 4, 12, 5, 0.3)
	kit.Blob(g, 28, 7, 18, 9, WHITE, { Z = 5 })
	kit.Blob(g, 28, 3, 10, 7, WHITE, { Z = 6 })
	kit.Line(g, 29, -4, 33, -11, 1.4, C.LeafDark, 0, 5)
	kit.Blob(g, 29, -3, 9, 9, C.Red, { Z = 7, Thickness = 1.2, Shine = true })
	kit.Face(g, 28, 41, 28, { Eyes = "dot", Mouth = "o", Z = 6 })
	kit.Animate(g, "Breathe", 0.03, 1.3, 0)
	return nil
end

-- Part de fraisier : génoise, crème, fraises, chantilly, visage
Art.StrawberryCake = function(body, kit, _item)
	local C = kit.C
	local sponge = Color3.fromRGB(255, 222, 150)
	kit.Blob(body, 50, 95, 84, 10, C.PinkMist, { Z = 1 })
	local low = kit.Part(body, 16, 72, 68, 22, sponge, { Radius = 4, Z = 2 })
	kit.Part(body, 16, 64, 68, 10, WHITE, { Radius = 3, Z = 3 })
	for _, x in ipairs({ 25, 41, 57, 73 }) do
		local slice = kit.Blob(body, x, 69, 10, 7, C.Red, { Z = 4, Thickness = 1.1 })
		kit.Blob(slice, 5, 3.5, 5, 3, C.PinkSoft, { Z = 2, Outline = false, Shade = false })
	end
	kit.Part(body, 16, 54, 68, 12, sponge, { Radius = 3, Z = 3 })
	kit.Part(body, 14, 46, 72, 11, WHITE, { Radius = 5, Z = 5, Outline = kit.OutlineOf(C.PinkSoft) })
	for _, d in ipairs({ { 22, 13 }, { 38, 9 }, { 64, 14 }, { 78, 8 } }) do
		drip(body, kit, d[1], 52, 5, d[2], WHITE, 6)
	end
	kit.Blob(body, 32, 44, 20, 10, WHITE, { Z = 6, Outline = kit.OutlineOf(C.PinkSoft) })
	kit.Blob(body, 68, 44, 14, 8, WHITE, { Z = 6, Outline = kit.OutlineOf(C.PinkSoft) })
	strawberry(body, kit, 32, 34, 16, 7)
	kit.Face(low, 34, 10, 18, { Eyes = "happy", Mouth = "cat", Z = 3 })
	return nil
end

-- Panier en osier : anse, tissu vichy, deux croissants dorés
Art.CroissantBasket = function(body, kit, _item)
	local C = kit.C
	local g = kit.Group(body, 14, 16, 72, 44, 1, true)
	ring(g, kit, 8, 8, 56, 80, C.Wood, 4, 1)
	local cloth = kit.Part(body, 10, 46, 80, 16, C.PinkSoft, { Radius = 6, Z = 2, Rotation = -3 })
	for i = 0, 6 do
		kit.Box(cloth, 3 + i * 11, 2 + (i % 2) * 6, 6, 6, C.Pink, 0.3, 2)
	end
	local gold = Color3.fromRGB(242, 182, 95)
	local function croissant(cx, cy, rot, z)
		local cg = kit.Group(body, cx - 25, cy - 14, 50, 28, z)
		cg.Rotation = rot
		for _, p in ipairs({ { 5, 21, 10, 9 }, { 45, 21, 10, 9 }, { 12, 16, 15, 17 }, { 38, 16, 15, 17 }, { 25, 13, 19, 23 } }) do
			local seg = kit.Blob(cg, p[1], p[2], p[3], p[4], if p[3] < 12 then kit.Darken(gold, 0.1) else gold, { Z = 1, Shade = false })
			kit.Gradient(seg, Color3.fromRGB(255, 245, 215), Color3.fromRGB(215, 165, 130), 90)
		end
		kit.Shine(cg, 20, 4, 9, 3, 3, 0.3)
		kit.Shine(cg, 8, 11, 4, 2.5, 3, 0.4)
		return cg
	end
	croissant(32, 42, -14, 3)
	local front = croissant(64, 44, 12, 4)
	kit.Face(front, 25, 15, 15, { Eyes = "dot", Mouth = "smile", Z = 4 })
	local basket = kit.Part(body, 12, 60, 76, 38, C.Wood, { Radius = 12, Z = 5, Shine = true })
	for _, y in ipairs({ 12, 21, 30 }) do
		kit.Box(basket, 4, y, 68, 1.6, C.WoodDark, 0.45, 2)
	end
	for i = 0, 3 do
		kit.Box(basket, 12 + i * 16, 4 + (i % 2) * 9, 1.6, 7, C.WoodDark, 0.45, 2)
	end
	kit.Part(body, 8, 57, 84, 9, C.WoodLight, { Radius = -1, Z = 6 })
	kit.Heart(body, 50, 84, 10, C.Pink, 0, 7)
	return nil
end

-- Bubble tea : gobelet, perles de tapioca, couvercle bombé, grosse paille
Art.BubbleTea = function(body, kit, _item)
	local C = kit.C
	local tea = Color3.fromRGB(238, 200, 165)
	kit.Line(body, 56, 40, 66, 4, 7, C.Pink, 0, 1)
	kit.Blob(body, 50, 34, 40, 22, C.Glass, { Z = 2, T = 0.45 })
	local cup = kit.Part(body, 28, 36, 44, 62, C.Glass, { Radius = 9, Z = 3, T = 0.35 })
	local fill = kit.Part(cup, 3, 8, 38, 51, tea, { Radius = 7, Z = 1, Outline = false })
	kit.Gradient(fill, WHITE, Color3.fromRGB(220, 200, 200), 90)
	for _, p in ipairs({ { 8, 45 }, { 16, 47 }, { 24, 45 }, { 32, 47 }, { 12, 39 }, { 22, 40 }, { 30, 39 } }) do
		local pearl = kit.Circle(fill, p[1], p[2], 7, 7, Color3.fromRGB(90, 55, 60), 0, 2)
		kit.Circle(pearl, 2.4, 2.2, 2.2, 2.2, WHITE, 0.4, 2)
	end
	kit.Shine(cup, 5, 10, 4, 22, 3, 0.35)
	kit.Part(body, 24, 32, 52, 8, kit.Lighten(C.Pink, 0.45), { Radius = -1, Z = 4 })
	kit.Face(body, 50, 58, 24, { Eyes = "dot", Mouth = "cat", Z = 5 })
	kit.Heart(body, 50, 26, 7, C.PinkDeep, 0, 4)
	return nil
end

-- Présentoir à cupcakes : 2 étages, 4 cupcakes pastel
Art.CupcakeStand = function(body, kit, _item)
	local C = kit.C
	local gold = C.Gold
	kit.Part(body, 47, 44, 6, 48, gold, { Radius = 3, Z = 1 })
	kit.Blob(body, 50, 96, 30, 7, gold, { Z = 1 })
	kit.Blob(body, 50, 90, 90, 9, C.PinkSoft, { Z = 2 })
	kit.Blob(body, 50, 54, 58, 7, C.PinkSoft, { Z = 2 })
	cupcake(body, kit, 20, 89, 28, Color3.fromRGB(255, 190, 220), C.Sky, 3)
	cupcake(body, kit, 80, 89, 28, Color3.fromRGB(200, 240, 220), C.Pink, 3)
	cupcake(body, kit, 50, 91, 30, Color3.fromRGB(230, 210, 255), C.Butter, 5)
	local top = cupcake(body, kit, 50, 53, 34, Color3.fromRGB(255, 240, 245), C.Pink, 3)
	kit.Face(top, 11.5, 8, 14, { Eyes = "happy", Mouth = "smile", Z = 3 })
	kit.Sparkle(body, 84, 30, 8, C.Butter, 0, 8)
	return nil
end

-- Bol de ramen : œuf, naruto, nori, nouilles, baguettes, vapeur
Art.RamenBowl = function(body, kit, _item)
	local C = kit.C
	local bowl = Color3.fromRGB(255, 150, 165)
	local nori = kit.Part(body, 62, 34, 14, 26, Color3.fromRGB(55, 85, 70), { Radius = 2, Z = 2, Rotation = 14 })
	kit.Box(nori, 4, 2, 1.4, 20, WHITE, 0.8, 2)
	kit.Box(nori, 9, 2, 1.4, 20, WHITE, 0.8, 2)
	local g = kit.Group(body, 8, 60, 84, 40, 1, true)
	local front = kit.Circle(g, 42, 0, 84, 76, bowl, 0, 1)
	kit.Stroke(front, kit.OutlineOf(bowl), 1.6)
	kit.Gradient(front, WHITE, Color3.fromRGB(225, 215, 215), 90)
	kit.Box(g, 10, 12, 64, 4, WHITE, 0.3, 2)
	for _, x in ipairs({ 16, 68 }) do
		kit.Circle(g, x, 24, 5, 5, WHITE, 0.35, 2)
	end
	kit.Blob(body, 50, 60, 86, 14, kit.Lighten(bowl, 0.35), { Z = 3 })
	kit.Blob(body, 50, 60, 76, 9, Color3.fromRGB(245, 190, 110), { Z = 4, Outline = false })
	for _, x in ipairs({ 17, 27, 43, 62, 74 }) do
		kit.Line(body, x, 61, x + 3, 57, 2, C.Butter, 0, 5)
		kit.Line(body, x + 3, 57, x + 6, 61, 2, C.Butter, 0, 5)
	end
	kit.Blob(body, 32, 54, 18, 13, WHITE, { Z = 6 })
	kit.Blob(body, 32, 55, 10, 8, C.Orange, { Z = 7, Outline = false, Shine = true })
	local naruto = kit.Blob(body, 54, 55, 15, 11, WHITE, { Z = 6 })
	kit.Part(naruto, 4, 3, 7, 5, C.Pink, { Radius = -1, T = 1, Outline = C.Pink, Thickness = 1.4, Shade = false, Z = 2 })
	kit.Blob(body, 70, 57, 8, 5, C.Leaf, { Z = 6, Outline = false })
	kit.Line(body, 58, 60, 92, 30, 3, C.WoodLight, 0, 8)
	kit.Line(body, 62, 62, 94, 36, 3, C.Wood, 0, 8)
	kit.Face(g, 42, 21, 24, { Eyes = "happy", Mouth = "smile", Z = 3 })
	steam(body, kit, 40, 44, 22, 0)
	steam(body, kit, 22, 44, 16, 1.4)
	return nil
end

-- Assiette d'onigiris (2 boulettes de riz souriantes)
Art.OnigiriPlate = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 93, 94, 14, C.Sky, { Z = 1 })
	kit.Blob(body, 50, 92, 76, 8, kit.Lighten(C.Sky, 0.5), { Z = 1, Outline = false })
	onigiri(body, kit, 32, 90, 40, 2, "dot")
	onigiri(body, kit, 66, 93, 44, 6, "happy")
	kit.Blob(body, 87, 88, 11, 6, C.Leaf, { Z = 10, Rotation = -25 })
	kit.Blob(body, 90, 92, 8, 8, C.PinkDeep, { Z = 11, Shine = true, Thickness = 1.2 })
	return nil
end

-- Pot de miel : miel qui coule, cuillère en bois, abeille qui vole
Art.HoneyPot = function(body, kit, _item)
	local C = kit.C
	local pot = Color3.fromRGB(255, 205, 120)
	local honey = Color3.fromRGB(250, 170, 40)
	kit.Line(body, 58, 40, 76, 12, 3, C.WoodDark, 0, 1)
	local dip = kit.Blob(body, 78, 10, 10, 12, C.WoodLight, { Z = 2, Rotation = 30 })
	kit.Box(dip, 0, 4, 10, 1.4, C.WoodDark, 0.3, 2)
	kit.Box(dip, 0, 7.5, 10, 1.4, C.WoodDark, 0.3, 2)
	local p = kit.Blob(body, 50, 70, 64, 54, pot, { Z = 2, Shine = true })
	kit.Part(body, 30, 36, 40, 12, kit.Darken(pot, 0.06), { Radius = 5, Z = 3 })
	kit.Blob(body, 50, 38, 34, 7, honey, { Z = 4, Outline = false })
	for _, d in ipairs({ { 34, 12 }, { 44, 20 }, { 58, 9 }, { 66, 15 } }) do
		drip(body, kit, d[1], 40, 6, d[2], honey, 4)
	end
	kit.Box(p, 4, 22, 56, 2, kit.Darken(pot, 0.2), 0.5, 2)
	kit.Face(body, 50, 72, 26, { Eyes = "big", Mouth = "smile", Z = 5 })
	local bee = kit.Group(body, 6, 16, 22, 18, 7)
	kit.Blob(bee, 9, 4, 8, 7, WHITE, { Z = 1, T = 0.3 })
	kit.Blob(bee, 14, 4, 8, 7, WHITE, { Z = 1, T = 0.3 })
	local b = kit.Blob(bee, 11, 11, 16, 12, C.Butter, { Z = 2 })
	kit.Box(b, 5, 0, 2.2, 12, C.Ink, 0.1, 2)
	kit.Box(b, 10, 0, 2.2, 12, C.Ink, 0.1, 2)
	kit.Circle(b, 13.4, 4.5, 2, 2, C.Ink, 0, 3)
	kit.Animate(bee, "Bob", 2.5, 1, 0.3)
	return nil
end

-- Bento : riz souriant + umeboshi, tamagoyaki, saucisse pieuvre, brocoli
Art.BentoBox = function(body, kit, _item)
	local C = kit.C
	local box = Color3.fromRGB(255, 160, 185)
	local lid = kit.Part(body, 14, 22, 72, 30, kit.Lighten(box, 0.25), { Radius = 8, Z = 1, Rotation = -7 })
	kit.Box(lid, 30, 0, 10, 30, C.Sky, 0.1, 2)
	kit.Part(body, 6, 44, 88, 38, kit.Darken(box, 0.05), { Radius = 8, Z = 2 })
	kit.Part(body, 11, 48, 40, 28, WHITE, { Radius = 5, Z = 3, Outline = kit.OutlineOf(C.Cream) })
	kit.Blob(body, 21, 55, 9, 9, C.PinkDeep, { Z = 5, Shine = true })
	kit.Blob(body, 23, 51, 5, 3, C.LeafDark, { Z = 6, Outline = false, Rotation = -20 })
	kit.Face(body, 32, 64, 22, { Eyes = "happy", Mouth = "smile", Z = 4 })
	kit.Part(body, 54, 48, 36, 28, C.Cream, { Radius = 5, Z = 3 })
	for _, x in ipairs({ 57, 67 }) do
		local tama = kit.Part(body, x, 51, 10, 11, C.Butter, { Radius = 3, Z = 4 })
		kit.Box(tama, 2, 3, 6, 1.2, C.Orange, 0.3, 2)
		kit.Box(tama, 2, 6.5, 6, 1.2, C.Orange, 0.3, 2)
	end
	-- Saucisse pieuvre
	local red = Color3.fromRGB(245, 110, 110)
	for i = 0, 3 do
		kit.Part(body, 76.5 + i * 3.2, 58, 2.6, 7, red, { Radius = -1, Z = 4, Thickness = 1 })
	end
	local octo = kit.Blob(body, 82, 55, 13, 11, red, { Z = 5, Shine = true })
	kit.Circle(octo, 4, 5.5, 1.8, 1.8, C.Ink, 0, 3)
	kit.Circle(octo, 9, 5.5, 1.8, 1.8, C.Ink, 0, 3)
	for i = 0, 2 do
		kit.Blob(body, 60 + i * 5, 70 - (i % 2) * 2, 7, 7, C.Leaf, { Z = 4 + i % 2 })
	end
	strawberry(body, kit, 82, 71, 9, 4)
	local front = kit.Part(body, 6, 76, 88, 22, box, { Radius = 8, Z = 6, Shine = true })
	kit.Box(front, 36, 0, 16, 22, C.Sky, 0.1, 2)
	kit.Heart(front, 44, 11, 8, WHITE, 0, 3)
	return nil
end

-- Bocal à cookies : couvercle ourson, cookies au chocolat derrière le verre
Art.CookieJar = function(body, kit, _item)
	local C = kit.C
	local cookie = Color3.fromRGB(235, 175, 100)
	local chip = Color3.fromRGB(110, 70, 55)
	local function oneCookie(cx, cy, w, z)
		local c = kit.Blob(body, cx, cy, w, w * 0.8, cookie, { Z = z })
		for _, p in ipairs({ { 0.3, 0.35 }, { 0.62, 0.3 }, { 0.48, 0.65 }, { 0.75, 0.62 } }) do
			kit.Circle(c, w * p[1], w * 0.8 * p[2], 3, 2.6, chip, 0, 2)
		end
		return c
	end
	kit.Part(body, 20, 38, 60, 60, C.Glass, { Radius = 16, Z = 1, T = 0.4, Outline = false })
	oneCookie(36, 86, 26, 2)
	oneCookie(63, 84, 26, 2)
	oneCookie(47, 68, 26, 2)
	oneCookie(64, 57, 22, 2)
	local jar = kit.Part(body, 20, 38, 60, 60, C.Glass, { Radius = 16, Z = 3, T = 0.85, Shade = false })
	kit.Shine(jar, 6, 10, 5, 36, 3, 0.25)
	kit.Shine(jar, 50, 40, 3, 10, 3, 0.4)
	local pink = Color3.fromRGB(255, 175, 200)
	for _, x in ipairs({ 32, 68 }) do
		kit.Blob(body, x, 20, 13, 13, pink, { Z = 4 })
		kit.Circle(body, x, 20, 6, 6, C.PinkSoft, 0, 5)
	end
	kit.Blob(body, 50, 30, 50, 22, pink, { Z = 5, Shine = true })
	kit.Part(body, 18, 34, 64, 8, kit.Darken(pink, 0.08), { Radius = 4, Z = 6 })
	kit.Face(body, 50, 30, 18, { Eyes = "dot", Mouth = "cat", Z = 7 })
	oneCookie(88, 92, 18, 8)
	return nil
end

----------------------------------------------------------------------
-- Gros électroménager
----------------------------------------------------------------------

-- Frigo rétro menthe : congélateur souriant, aimants, dessin et liste
Art.Fridge = function(body, kit, _item)
	local C = kit.C
	local mint = Color3.fromRGB(170, 230, 212)
	local door = kit.Lighten(mint, 0.25)
	for _, x in ipairs({ 22, 70 }) do
		kit.Part(body, x, 92, 8, 8, C.GreyDark, { Radius = 2, Z = 1 })
	end
	local fridge = kit.Part(body, 14, 2, 72, 92, mint, { Radius = 16, Z = 2, Shade = 0.15 })
	kit.Shine(fridge, 4, 14, 3.5, 60, 3, 0.4)
	local top = kit.Part(body, 18, 6, 64, 28, door, { Radius = 12, Z = 3, Shine = true })
	local main = kit.Part(body, 18, 37, 64, 51, door, { Radius = 12, Z = 3 })
	kit.Part(body, 70, 14, 5, 13, C.Cream, { Radius = -1, Z = 4, Shine = true })
	kit.Part(body, 70, 43, 5, 24, C.Cream, { Radius = -1, Z = 4, Shine = true })
	kit.Face(top, 26, 14, 26, { Eyes = "big", Mouth = "cat", Z = 3 })
	kit.Part(body, 22, 88, 56, 4, kit.Darken(mint, 0.15), { Radius = 2, Z = 3 })
	-- Aimants et papiers
	kit.Heart(main, 11, 9, 9, C.Pink, 0, 5)
	kit.Sparkle(main, 42, 8, 10, C.Yellow, 0, 5)
	local photo = kit.Part(main, 6, 17, 22, 24, WHITE, { Radius = 2, Z = 3, Rotation = -6 })
	local pic = kit.Box(photo, 2.5, 2.5, 17, 14, C.Sky, 0, 2)
	kit.Circle(pic, 13, 4, 5, 5, C.Yellow, 0, 2)
	kit.Blob(pic, 6, 14, 18, 10, C.Leaf, { Z = 2, Outline = false, Shade = false })
	kit.Heart(photo, 11, 20, 4, C.Pink, 0, 3)
	kit.Circle(main, 17, 18, 5, 5, C.Red, 0, 5)
	local note = kit.Part(main, 32, 20, 18, 22, C.Butter, { Radius = 2, Z = 3, Rotation = 5 })
	for i = 0, 2 do
		kit.Box(note, 3, 6 + i * 5, 12 - i * 3, 1.4, C.GreyDark, 0.4, 2)
	end
	kit.Circle(main, 41, 21, 5, 5, C.Lilac, 0, 5)
	kit.Blob(main, 25, 46, 6, 6, C.Mint, { Z = 5 })
	kit.Blob(main, 33, 46, 6, 6, C.Sky, { Z = 5 })
	kit.Blob(main, 41, 46, 6, 6, C.Pink, { Z = 5 })
	return nil
end

-- Cuisinière rose rétro : horloge, poêle + œuf, casserole souriante, four chaud
Art.Stove = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 185, 208)
	local back = kit.Part(body, 10, 8, 80, 30, kit.Lighten(pink, 0.4), { Radius = 8, Z = 1 })
	local clock = kit.Blob(back, 40, 9, 13, 13, WHITE, { Z = 2 })
	kit.Line(clock, 6.5, 6.5, 6.5, 3, 1.4, C.Ink, 0, 2)
	kit.Line(clock, 6.5, 6.5, 9.5, 6.5, 1.4, C.Ink, 0, 2)
	-- Poêle et œuf
	kit.Line(body, 6, 26, 18, 30, 3.5, C.WoodDark, 0, 4)
	kit.Part(body, 16, 28, 30, 8, C.GreyDark, { Radius = 4, Z = 4 })
	kit.Blob(body, 31, 28, 30, 7, Color3.fromRGB(90, 86, 100), { Z = 4, Outline = false })
	kit.Blob(body, 31, 26, 20, 6, WHITE, { Z = 5 })
	kit.Blob(body, 31, 25, 8, 5, C.Yellow, { Z = 6, Shine = true })
	-- Casserole souriante
	kit.Part(body, 56, 20, 7, 4, C.Lilac, { Radius = 2, Z = 4 })
	kit.Part(body, 87, 20, 7, 4, C.Lilac, { Radius = 2, Z = 4 })
	local pot = kit.Part(body, 60, 14, 29, 22, C.Lilac, { Radius = 6, Z = 5, Shine = true })
	kit.Blob(body, 74.5, 14, 33, 7, kit.Lighten(C.Lilac, 0.3), { Z = 6 })
	kit.Blob(body, 74.5, 10, 7, 5, C.Pink, { Z = 7 })
	kit.Face(pot, 14.5, 13, 17, { Eyes = "happy", Mouth = "smile", Z = 3 })
	steam(body, kit, 68, 8, 16, 0)
	steam(body, kit, 81, 6, 14, 1.3)
	-- Corps et four
	kit.Part(body, 6, 36, 88, 7, WHITE, { Radius = 3, Z = 3 })
	local stove = kit.Part(body, 8, 40, 84, 54, pink, { Radius = 10, Z = 2 })
	kit.Shine(stove, 3, 6, 3, 30, 3, 0.4)
	for _, x in ipairs({ 12, 24, 60, 72 }) do
		local knob = kit.Blob(stove, x, 9, 8, 8, WHITE, { Z = 3 })
		kit.Line(knob, 4, 4, 4, 1.5, 1.4, C.PinkDeep, 0, 2)
	end
	local screen = kit.Part(stove, 34, 5, 16, 8, Color3.fromRGB(80, 60, 80), { Radius = 2, Z = 3 })
	kit.Heart(screen, 8, 4, 5, C.Pink, 0, 2)
	local oven = kit.Part(body, 14, 56, 72, 34, kit.Lighten(pink, 0.3), { Radius = 8, Z = 3 })
	kit.Part(oven, 6, 3, 60, 5, C.Cream, { Radius = -1, Z = 3, Shine = true })
	local window = kit.Part(oven, 9, 11, 54, 19, Color3.fromRGB(110, 60, 75), { Radius = 6, Z = 2 })
	local warm = kit.Box(window, 3, 3, 48, 13, C.Orange, 0.55, 2)
	kit.Round(warm, 4)
	kit.Animate(warm, "Pulse", 0.25, 0.8, 0)
	kit.Box(window, 8, 13, 38, 1.6, C.GreyDark, 0, 3)
	for _, x in ipairs({ 15, 27, 39 }) do
		kit.Blob(window, x, 10.5, 9, 5, C.Butter, { Z = 3, Thickness = 1 })
	end
	kit.Line(window, 38, 4, 46, 12, 2, WHITE, 0.6, 4)
	for _, x in ipairs({ 14, 78 }) do
		kit.Part(body, x, 92, 8, 7, C.GreyDark, { Radius = 2, Z = 1 })
	end
	return nil
end

----------------------------------------------------------------------
-- Grands plats et desserts de fête
----------------------------------------------------------------------

-- Plateau de sushis : geta en bois, nigiris saumon / thon, makis, wasabi
Art.SushiPlatter = function(body, kit, _item)
	local C = kit.C
	for _, x in ipairs({ 14, 76 }) do
		kit.Part(body, x, 86, 10, 12, C.WoodDark, { Radius = 2, Z = 1 })
	end
	kit.Part(body, 4, 66, 92, 16, C.WoodLight, { Radius = 4, Z = 2 })
	kit.Part(body, 4, 78, 92, 10, C.Wood, { Radius = 4, Z = 3, Shine = true })
	local function nigiri(cx, fish, stripes, z, eyes)
		kit.Blob(body, cx, 67, 26, 13, WHITE, { Z = z })
		local f = kit.Part(body, cx - 15, 55, 30, 12, fish, { Radius = 6, Z = z + 1, Rotation = -4, Shine = true })
		for _, x in ipairs({ 9, 16, 23 }) do
			local l = kit.Box(f, x, 1, 1.6, 10, stripes, 0.2, 2)
			l.Rotation = 20
		end
		kit.Face(body, cx, 63, 14, { Eyes = eyes, Mouth = "smile", Z = z + 2 })
	end
	nigiri(20, Color3.fromRGB(255, 160, 120), WHITE, 4, "happy")
	nigiri(47, Color3.fromRGB(240, 95, 115), Color3.fromRGB(255, 160, 170), 4, "dot")
	for _, x in ipairs({ 72, 88 }) do
		kit.Blob(body, x, 63, 16, 16, Color3.fromRGB(50, 70, 60), { Z = 4 })
		kit.Circle(body, x, 62, 11, 11, WHITE, 0, 5)
		kit.Circle(body, x - 1, 62, 5, 5, C.Orange, 0, 6)
		kit.Circle(body, x + 2, 61, 3, 3, C.Leaf, 0, 6)
	end
	kit.Blob(body, 68, 76, 10, 6, C.Leaf, { Z = 7, Shine = true })
	for i = 0, 2 do
		kit.Blob(body, 80 + i * 4, 76 - (i % 2), 7, 5, C.PinkSoft, { Z = 7 + i, Rotation = -20 + i * 20 })
	end
	kit.Heart(body, 24, 76, 6, C.Pink, 0, 7)
	return nil
end

-- Gâteau d'anniversaire : 2 étages, coulures, bougies qui vacillent (lueur)
Art.BirthdayCake = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 180, 205)
	local cream = Color3.fromRGB(255, 246, 228)
	kit.Part(body, 40, 94, 20, 5, C.Gold, { Radius = 2, Z = 1 })
	kit.Blob(body, 50, 94, 92, 8, C.LilacSoft, { Z = 2 })
	local low = kit.Part(body, 12, 58, 76, 36, pink, { Radius = 10, Z = 3, Shine = true })
	kit.Part(body, 11, 56, 78, 9, WHITE, { Radius = 5, Z = 4 })
	for _, d in ipairs({ { 17, 9 }, { 28, 5 }, { 40, 11 }, { 58, 6 }, { 70, 10 }, { 82, 6 } }) do
		drip(body, kit, d[1], 60, 5, d[2], WHITE, 4)
	end
	for i = 0, 5 do
		kit.Circle(body, 18 + i * 12.8, 92, 7, 6, WHITE, 0, 5)
	end
	for _, p in ipairs({ { 10, 26, C.Sky, 30 }, { 62, 22, C.Butter, -30 }, { 66, 30, C.Mint, 60 }, { 6, 16, C.Lilac, -50 } }) do
		local sp = kit.Box(low, p[1], p[2], 5, 1.8, p[3], 0, 3)
		sp.Rotation = p[4]
		kit.Round(sp)
	end
	kit.Face(low, 38, 20, 26, { Eyes = "happy", Mouth = "o", Z = 3 })
	-- Bougies
	for i, p in ipairs({ { 38, C.Mint }, { 50, C.Pink }, { 62, C.Lilac } }) do
		local x = p[1]
		local candle = kit.Part(body, x - 2.5, 12 + (i % 2) * 3, 5, 24, p[2], { Radius = 2, Z = 5 })
		kit.Box(candle, 0, 6, 5, 2, WHITE, 0.3, 2)
		kit.Box(candle, 0, 13, 5, 2, WHITE, 0.3, 2)
		local flame = kit.Blob(body, x, 6 + (i % 2) * 3, 7, 10, C.Orange, { Z = 6, Outline = false })
		kit.Blob(flame, 3.5, 6, 3.5, 5, C.Butter, { Z = 2, Outline = false, Shade = false })
		kit.Animate(flame, "Flicker", 0.25, 1, i * 1.7)
	end
	local top = kit.Part(body, 26, 32, 48, 26, cream, { Radius = 8, Z = 6, Shine = true })
	kit.Heart(top, 24, 15, 10, C.Pink, 0, 3)
	kit.Part(body, 25, 30, 50, 8, pink, { Radius = 4, Z = 7 })
	for _, d in ipairs({ { 32, 7 }, { 46, 4 }, { 58, 8 }, { 68, 5 } }) do
		drip(body, kit, d[1], 34, 4.5, d[2], pink, 7)
	end
	kit.Blob(body, 18, 53, 9, 9, C.Red, { Z = 8, Shine = true })
	kit.Blob(body, 82, 53, 9, 9, C.Red, { Z = 8, Shine = true })
	return { Glow = Color3.fromRGB(255, 200, 120) }
end

-- Tour de pancakes : sirop d'érable qui coule, beurre, fraise, myrtilles
Art.PancakeTower = function(body, kit, _item)
	local C = kit.C
	local cake = Color3.fromRGB(242, 190, 115)
	local syrup = Color3.fromRGB(200, 115, 50)
	kit.Blob(body, 50, 94, 90, 10, C.Sky, { Z = 1 })
	for i = 0, 5 do
		local jitter = ({ 0, -2, 2, -1, 1, -2 })[i + 1]
		local pc = kit.Part(body, 14 + jitter, 83 - i * 8, 72, 11, cake, { Radius = -1, Z = 2 + i, Shade = false })
		kit.Gradient(pc, Color3.fromRGB(255, 240, 210), Color3.fromRGB(215, 175, 140), 90)
	end
	kit.Blob(body, 50, 44, 64, 9, syrup, { Z = 9, Outline = false })
	for _, d in ipairs({ { 22, 22 }, { 36, 10 }, { 60, 14 }, { 76, 30 } }) do
		drip(body, kit, d[1], 44, 5.5, d[2], syrup, 9)
	end
	kit.Part(body, 42, 32, 16, 10, C.Butter, { Radius = 3, Z = 10, Shine = true })
	strawberry(body, kit, 30, 38, 11, 10)
	kit.Circle(body, 68, 40, 8, 8, C.Blue, 0, 10)
	kit.Circle(body, 74, 42, 7, 7, C.Navy, 0, 10)
	kit.Face(body, 50, 73, 22, { Eyes = "dot", Mouth = "smile", Z = 9 })
	return nil
end

-- Sucette géante arc-en-ciel sur son pot à bonbons (tourbillon qui tourne)
Art.GiantLollipop = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 47, 50, 6, 34, WHITE, { Radius = 3, Z = 2 })
	for _, y in ipairs({ 60, 70 }) do
		kit.Line(body, 47.5, y + 3, 52.5, y - 1, 1.8, C.Pink, 0, 3)
	end
	local potColor = Color3.fromRGB(190, 225, 250)
	for _, p in ipairs({ { 38, 78, C.Pink }, { 50, 76, C.Butter }, { 62, 78, C.Mint } }) do
		kit.Blob(body, p[1], p[2], 10, 10, p[3], { Z = 3 })
	end
	kit.Part(body, 28, 78, 44, 8, kit.Lighten(potColor, 0.3), { Radius = 4, Z = 5 })
	local pot = kit.Part(body, 32, 84, 36, 15, potColor, { Radius = 6, Z = 4, Shine = true })
	kit.Heart(pot, 18, 7.5, 7, C.Pink, 0, 3)
	kit.Blob(body, 50, 30, 60, 60, WHITE, { Z = 4, Outline = C.PinkDeep, Thickness = 2 })
	local swirl = kit.Pivot(body, 50, 30, 5)
	local colors = { C.Pink, C.Butter, C.Mint, C.Sky, C.Lilac, C.Peach }
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local petal = kit.Box(swirl, 0, 0, 26, 12, colors[i + 1], 0, 1)
		petal.AnchorPoint = Vector2.new(0.5, 0.5)
		petal.Position = UDim2.fromOffset(math.cos(a) * 14, math.sin(a) * 14)
		petal.Rotation = i * 60 + 35
		kit.Round(petal)
	end
	kit.Animate(swirl, "Spin", 1, 0.06, 0)
	kit.Blob(body, 50, 30, 22, 22, WHITE, { Z = 6, Outline = kit.OutlineOf(C.PinkSoft) })
	kit.Face(body, 50, 31, 18, { Eyes = "big", Mouth = "cat", Z = 7 })
	kit.Shine(body, 30, 10, 12, 6, 8, 0.3)
	kit.Blob(body, 43, 62, 14, 9, C.PinkDeep, { Z = 6, Rotation = 20 })
	kit.Blob(body, 57, 62, 14, 9, C.PinkDeep, { Z = 6, Rotation = -20 })
	kit.Blob(body, 50, 62, 6, 6, C.Pink, { Z = 7 })
	kit.Sparkle(body, 86, 14, 10, C.Butter, 0, 8)
	kit.Sparkle(body, 12, 46, 8, C.Sky, 0, 8)
	return nil
end

-- Chariot à glaces : auvent rayé, vitrine de bacs, grande coupe glacée
Art.SundaeBar = function(body, kit, _item)
	local C = kit.C
	local mint = Color3.fromRGB(185, 235, 218)
	for _, x in ipairs({ 11, 85 }) do
		kit.Part(body, x, 8, 4, 52, WHITE, { Radius = 2, Z = 1 })
	end
	local awning = kit.Part(body, 4, -2, 92, 13, C.Pink, { Radius = 6, Z = 4 })
	for i = 0, 3 do
		kit.Box(awning, 8 + i * 22, 0, 11, 13, WHITE, 0.1, 2)
	end
	for i = 0, 5 do
		kit.Blob(body, 11.7 + i * 15.3, 11, 15.3, 9, if i % 2 == 0 then C.Pink else WHITE, { Z = 3 })
	end
	for _, x in ipairs({ 20, 80 }) do
		kit.Blob(body, x, 93, 13, 13, C.GreyDark, { Z = 2 })
		kit.Circle(body, x, 93, 5, 5, C.Grey, 0, 3)
	end
	local cart = kit.Part(body, 8, 58, 84, 34, mint, { Radius = 8, Z = 3, Shine = true })
	for _, p in ipairs({ { 22, C.Pink }, { 42, Color3.fromRGB(150, 100, 80) }, { 62, C.Butter } }) do
		kit.Blob(cart, p[1], 18, 16, 10, p[2], { Z = 2 })
	end
	local glass = kit.Part(cart, 8, 10, 68, 18, C.Glass, { Radius = 5, Z = 3, T = 0.55 })
	kit.Shine(glass, 4, 3, 16, 3, 2, 0.3)
	kit.Part(body, 4, 54, 92, 8, C.Cream, { Radius = 4, Z = 5 })
	-- Coupe glacée
	kit.Blob(body, 50, 54, 20, 5, C.LilacSoft, { Z = 6 })
	kit.Part(body, 48, 46, 4, 8, C.LilacSoft, { Radius = 1, Z = 6 })
	kit.Line(body, 60, 30, 68, 14, 3.2, Color3.fromRGB(120, 75, 60), 0, 6)
	kit.Line(body, 62.5, 25, 64.5, 21, 3.4, C.Butter, 0, 6)
	kit.Blob(body, 40, 33, 21, 18, C.Pink, { Z = 7, Shine = true })
	kit.Blob(body, 60, 33, 21, 18, C.Mint, { Z = 7 })
	local mid = kit.Blob(body, 50, 24, 21, 18, C.Butter, { Z = 8, Shine = true })
	kit.Face(mid, 10.5, 10.5, 14, { Eyes = "happy", Mouth = "smile", Z = 3 })
	kit.Blob(body, 50, 14.5, 13, 8, WHITE, { Z = 9 })
	kit.Blob(body, 50, 9, 7, 7, C.Red, { Z = 10, Shine = true })
	local coupe = kit.Group(body, 29, 40, 42, 12, 9, true)
	local cg = kit.Circle(coupe, 21, 0, 42, 24, C.LilacSoft, 0, 1)
	kit.Stroke(cg, kit.OutlineOf(C.Lilac), 1.6)
	kit.Box(coupe, 8, 3, 26, 2, WHITE, 0.3, 2)
	kit.Part(body, 28, 38, 44, 4, kit.Lighten(C.Lilac, 0.5), { Radius = -1, Z = 10 })
	-- Bocal de vermicelles et cornet
	local jar = kit.Part(body, 13, 40, 13, 15, C.Glass, { Radius = 3, Z = 6, T = 0.3 })
	for _, p in ipairs({ { 3, 5, C.Pink }, { 8, 8, C.Sky }, { 4, 11, C.Butter }, { 9, 3, C.Mint } }) do
		kit.Box(jar, p[1], p[2], 3, 1.6, p[3], 0, 2)
	end
	kit.Part(body, 12, 36, 15, 5, C.Pink, { Radius = 2, Z = 7 })
	kit.TriangleDown(body, 83, 40, 12, 14, C.WoodLight, 6, 0, 6)
	kit.Blob(body, 83, 37, 14, 11, C.Lilac, { Z = 7, Shine = true })
	return nil
end

-- Fontaine à chocolat : 3 plateaux, rideaux de chocolat, fraises et guimauves
Art.ChocolateFountain = function(body, kit, _item)
	local C = kit.C
	local choco = Color3.fromRGB(160, 95, 70)
	local metal = Color3.fromRGB(255, 200, 220)
	kit.Part(body, 47, 8, 6, 66, C.Gold, { Radius = 3, Z = 1 })
	-- Socle rempli de chocolat
	local base = kit.Part(body, 16, 72, 68, 24, metal, { Radius = 10, Z = 2, Shine = true })
	kit.Box(base, 4, 16, 60, 2, WHITE, 0.5, 2)
	kit.Blob(body, 50, 72, 70, 12, kit.Lighten(metal, 0.3), { Z = 3 })
	kit.Blob(body, 50, 72, 60, 7, choco, { Z = 4, Outline = false })
	kit.Face(base, 34, 11, 24, { Eyes = "happy", Mouth = "smile", Z = 3 })
	-- Plateaux et rideaux
	local tiers = { { 18, 22 }, { 36, 36 }, { 54, 50 } }
	for i, t in ipairs(tiers) do
		local y, w = t[1], t[2]
		local nextY = if i < #tiers then tiers[i + 1][1] else 72
		local curtain = kit.Part(body, 50 - w / 2 + 1, y, w - 2, nextY - y, choco, { Radius = 2, Z = 3 + i * 2, Outline = false, T = 0.3 })
		kit.Box(curtain, w * 0.22, 3, 1.8, nextY - y - 6, WHITE, 0.7, 2)
		kit.Box(curtain, w * 0.62, 5, 1.8, nextY - y - 9, WHITE, 0.75, 2)
		kit.Animate(curtain, "Pulse", 0.15, 1, i)
		kit.Blob(body, 50, y + 2, w + 4, 8, metal, { Z = 4 + i * 2 })
		kit.Blob(body, 50, y, w, 5, choco, { Z = 4 + i * 2, Outline = C.Gold, Thickness = 1.4 })
	end
	kit.Blob(body, 50, 10, 9, 9, metal, { Z = 12, Shine = true })
	kit.Heart(body, 50, 3, 9, C.Pink, 0, 12)
	-- Brochettes de fraises et guimauves
	kit.Line(body, 8, 96, 14, 64, 1.8, C.WoodLight, 0, 12)
	strawberry(body, kit, 14, 62, 10, 13)
	kit.Blob(body, 14, 66, 10, 5, choco, { Z = 13, Outline = false })
	kit.Line(body, 92, 96, 86, 64, 1.8, C.WoodLight, 0, 12)
	kit.Part(body, 81, 57, 10, 9, C.PinkSoft, { Radius = 3, Z = 13 })
	kit.Part(body, 81, 64, 10, 5, choco, { Radius = 2, Z = 14, Outline = false })
	kit.Sparkle(body, 22, 30, 8, C.Butter, 0, 12)
	return nil
end

-- Machine à glace pilée : manivelle qui tourne, bloc de glace, dôme aux sirops
Art.ShavedIceMachine = function(body, kit, _item)
	local C = kit.C
	local blue = Color3.fromRGB(170, 222, 245)
	kit.Part(body, 6, 88, 88, 10, kit.Darken(blue, 0.08), { Radius = 5, Z = 2, Shine = true })
	kit.Part(body, 10, 18, 18, 72, blue, { Radius = 7, Z = 2 })
	local arm = kit.Part(body, 10, 10, 74, 18, blue, { Radius = 9, Z = 3, Shine = true })
	kit.Heart(arm, 16, 9, 7, C.Pink, 0, 3)
	-- Manivelle
	kit.Part(body, 56, 4, 8, 8, kit.Darken(blue, 0.1), { Radius = 2, Z = 2 })
	local crank = kit.Pivot(body, 60, 5, 4)
	kit.Blob(crank, 0, 0, 12, 12, C.Pink, { Z = 2, Shine = true })
	kit.Line(crank, 0, 0, 14, -5, 3, C.PinkDeep, 0, 1)
	kit.Blob(crank, 14, -5, 7, 7, WHITE, { Z = 3 })
	kit.Animate(crank, "Spin", 1, 0.25, 0)
	-- Bloc de glace sous le bras
	kit.Part(body, 56, 27, 8, 4, C.GreyDark, { Radius = 1, Z = 2 })
	local ice = kit.Part(body, 48, 30, 24, 17, Color3.fromRGB(195, 238, 255), { Radius = 3, Z = 3, Outline = kit.OutlineOf(C.Sky), Shade = 0.2 })
	kit.Box(ice, 0, 0, 24, 5, WHITE, 0.35, 2)
	kit.Line(ice, 4, 8, 4, 13, 2, WHITE, 0.2, 2)
	kit.Sparkle(ice, 18, 10, 7, WHITE, 0, 3)
	kit.Part(body, 46, 46, 28, 4, C.Grey, { Radius = 2, Z = 4 })
	for i = 0, 2 do
		local flake = kit.Circle(body, 54 + i * 6, 53 + (i % 2) * 3, 2.6, 2.6, WHITE, 0, 3)
		kit.Animate(flake, "Bob", 1.5, 1.4, i)
	end
	-- Montagne de glace pilée aux sirops dans sa coupe
	local dome = kit.Blob(body, 60, 70, 40, 30, WHITE, { Z = 4, Outline = kit.OutlineOf(C.Sky) })
	kit.Blob(dome, 11, 14, 18, 18, C.Pink, { Z = 2, T = 0.3, Outline = false })
	kit.Blob(dome, 29, 14, 18, 18, C.Sky, { Z = 2, T = 0.3, Outline = false })
	kit.Blob(dome, 20, 6, 16, 10, C.Butter, { Z = 2, T = 0.2, Outline = false })
	kit.Face(dome, 20, 16, 17, { Eyes = "dot", Mouth = "cat", Z = 3 })
	kit.Blob(body, 60, 56, 7, 7, C.Red, { Z = 6, Shine = true })
	local bowl = kit.Group(body, 36, 76, 48, 12, 5, true)
	local cup = kit.Circle(bowl, 24, 0, 48, 24, C.LilacSoft, 0, 1)
	kit.Stroke(cup, kit.OutlineOf(C.Lilac), 1.6)
	kit.Box(bowl, 6, 3, 36, 2.4, C.Pink, 0.2, 2)
	kit.Part(body, 35, 74, 50, 4, kit.Lighten(C.Lilac, 0.5), { Radius = -1, Z = 6 })
	kit.Part(body, 52, 86, 16, 3, C.Lilac, { Radius = 1, Z = 4 })
	-- Fanion 氷
	local flag = kit.Part(body, 12, 38, 14, 24, WHITE, { Radius = 2, Z = 4 })
	kit.Box(flag, 0, 17, 14, 7, C.Blue, 0.1, 2)
	kit.Text(flag, "氷", 7, 9, 10, C.Red, 3)
	-- Bouteille de sirop
	kit.Part(body, 84, 64, 4, 7, WHITE, { Radius = 1, Z = 3 })
	kit.Part(body, 80, 70, 12, 18, C.Pink, { Radius = 4, Z = 4, Shine = true })
	kit.Heart(body, 86, 81, 6, WHITE, 0, 5)
	kit.Sparkle(body, 90, 38, 8, C.Sky, 0, 7)
	kit.Sparkle(body, 36, 56, 6, WHITE, 0, 7)
	return nil
end

return Art
