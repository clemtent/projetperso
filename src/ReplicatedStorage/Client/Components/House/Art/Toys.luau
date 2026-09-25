--[[
	Toys (ModuleScript) — dessins 🧸 jouets
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Toys
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

----------------------------------------------------------------------
-- Aides partagées
----------------------------------------------------------------------

-- Pivot + calque 100 x 100 : on dessine avec les coordonnées de la boîte,
-- et le tout tourne autour de (px, py)
local function rig(parent, kit, px, py, z)
	local pivot = kit.Pivot(parent, px, py, z)
	local layer = kit.Group(pivot, -px, -py, 100, 100, 1)
	return pivot, layer
end

-- Calque qui "respire" depuis le sol (échelle ancrée en bas au centre)
local function breathing(body, kit, amp, phase)
	local layer = kit.Group(body, 0, 0, 100, 100, 2)
	layer.AnchorPoint = Vector2.new(0.5, 1)
	layer.Position = UDim2.fromOffset(50, 100)
	kit.Animate(layer, "Breathe", amp, 1, phase)
	return layer
end

-- Cœur avec contour (un cœur foncé un peu plus grand derrière)
local function heartOutlined(parent, kit, cx, cy, w, color, z)
	kit.Heart(parent, cx, cy + 0.5, w + 3.6, kit.OutlineOf(color), 0, z)
	return kit.Heart(parent, cx, cy, w, color, 0, z + 1)
end

-- Pointe arrondie (carré tourné à 45°) : oreille de chat, piquant de dino...
local function point(parent, kit, cx, cy, size, color, rotation, z, inner)
	local frame = kit.Part(parent, cx - size / 2, cy - size / 2, size, size, color, { Radius = size * 0.22, Z = z, Rotation = rotation, Shade = false })
	if inner then
		kit.Part(frame, size * 0.14, size * 0.14, size * 0.52, size * 0.52, inner, { Radius = size * 0.14, Z = 2, Outline = false, Shade = false })
	end
	return frame
end

-- Museau (ours, chien) : truffe + petite bouche "w"
local function muzzle(parent, kit, cx, cy, w, h, color, nose, z)
	local C = kit.C
	local frame = kit.Blob(parent, cx, cy, w, h, color, { Z = z, Thickness = 1.3, Shade = 0.06 })
	local truffle = kit.Blob(frame, w / 2, h * 0.3, w * 0.36, h * 0.32, nose, { Z = 3, Outline = false, Shade = false })
	kit.Circle(truffle, w * 0.1, h * 0.09, w * 0.1, h * 0.08, C.White, 0.3, 2)
	kit.Line(frame, w / 2, h * 0.44, w / 2, h * 0.6, 1.3, C.Ink, 0, 2)
	kit.Line(frame, w / 2 - w * 0.15, h * 0.68, w / 2, h * 0.6, 1.3, C.Ink, 0, 2)
	kit.Line(frame, w / 2, h * 0.6, w / 2 + w * 0.15, h * 0.68, 1.3, C.Ink, 0, 2)
	return frame
end

-- Nœud (2 boucles + un nœud central)
local function bow(parent, kit, cx, cy, w, color, z)
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(parent, cx + side * w * 0.27, cy, w * 0.54, w * 0.4, color, { Z = z, Rotation = -side * 14, Thickness = 1.3 })
	end
	kit.Blob(parent, cx, cy, w * 0.24, w * 0.28, kit.Darken(color, 0.06), { Z = z + 1, Thickness = 1.3 })
end

-- Peluche assise vue de face : corps, ventre, pieds, bras, tête dans un pivot
-- au cou (pour pencher la tête). Oreilles / visage : dans `Head` (tête Z = 4).
local function plush(root, kit, o)
	local color = o.Color
	local limb = o.Limb or color
	local light = o.Light or kit.Lighten(color, 0.5)
	local bw, bh = o.BodyW or 50, o.BodyH or 38
	local torso = kit.Blob(root, 50, 97 - bh / 2, bw, bh, color, { Z = 3 })
	if o.Belly ~= false then
		kit.Blob(torso, bw / 2, bh * 0.58, bw * 0.56, bh * 0.6, light, { Z = 2, Outline = false, Shade = false })
	end
	for _, side in ipairs({ -1, 1 }) do
		local foot = kit.Blob(root, 50 + side * bw * 0.3, 92, bw * 0.38, 14, limb, { Z = 4 })
		kit.Blob(foot, bw * 0.19, 7.5, bw * 0.2, 7, o.Paw or light, { Z = 2, Outline = false, Shade = false })
		kit.Blob(root, 50 + side * bw * 0.43, 97 - bh * 0.6, 13, bh * 0.56, limb, { Z = 5, Rotation = -side * 26 })
	end
	local neck, head = rig(root, kit, 50, 97 - bh + 4, 6)
	local skull = kit.Blob(head, 50, o.HeadY or 40, o.HeadW or 58, o.HeadH or 46, color, { Z = 4, Shine = true })
	return { Torso = torso, Neck = neck, Head = head, Skull = skull }
end

-- Cheval vu de profil (tourné vers la droite), origine = centre du corps,
-- k = échelle. o = { X, Y, K, Coat, Mane = { couleurs }, Saddle, Hoof, Legs }
-- Legs = liste de { x1, y1, x2, y2, x3?, y3?, far? } (coordonnées "cheval")
local function horse(parent, kit, o)
	local C = kit.C
	local k, ox, oy = o.K, o.X, o.Y
	local function X(v)
		return ox + v * k
	end
	local function Y(v)
		return oy + v * k
	end
	local coat = o.Coat
	local far = kit.Darken(coat, 0.1)
	local mane = o.Mane
	-- queue (derrière)
	for index, color in ipairs(mane) do
		kit.Blob(parent, X(-25 - index * 3), Y(-4 + index * 5), 10 * k, 22 * k, color, { Z = 1, Rotation = 30 + index * 14, Thickness = 1.3 })
	end
	-- jambes (le haut est caché par le corps)
	local legT = 6 * k
	for _, leg in ipairs(o.Legs) do
		local color = if leg[7] then far else coat
		local z = if leg[7] then 1 else 2
		local ex, ey = leg[3], leg[4]
		kit.Line(parent, X(leg[1]), Y(leg[2]), X(leg[3]), Y(leg[4]), legT, color, 0, z)
		if leg[5] then
			kit.Line(parent, X(leg[3]), Y(leg[4]), X(leg[5]), Y(leg[6]), legT, color, 0, z)
			ex, ey = leg[5], leg[6]
		end
		kit.Circle(parent, X(ex), Y(ey), legT * 1.25, legT * 1.1, o.Hoof, 0, z)
	end
	-- corps, cou, tête
	kit.Blob(parent, X(0), Y(0), 50 * k, 28 * k, coat, { Z = 3, Shine = true })
	kit.Blob(parent, X(17), Y(-15), 17 * k, 32 * k, coat, { Z = 4, Rotation = 30, Shade = false })
	local headFrame = kit.Blob(parent, X(29), Y(-29), 30 * k, 16 * k, coat, { Z = 5, Rotation = 32, Shade = false })
	kit.Blob(parent, X(39), Y(-22), 13 * k, 12 * k, C.PinkSoft, { Z = 6, Thickness = 1.3 })
	kit.Circle(parent, X(41), Y(-22.5), 2 * k, 2.4 * k, C.Ink, 0.3, 7)
	point(parent, kit, X(19), Y(-39), 8 * k, coat, 20, 3, C.PinkSoft)
	local eye = kit.Circle(parent, X(27), Y(-31), 4 * k, 4.8 * k, C.Ink, 0, 7)
	kit.Circle(eye, 1.3 * k, 1.3 * k, 1.6 * k, 1.6 * k, C.White, 0, 2)
	kit.Circle(parent, X(31), Y(-25), 6 * k, 3.5 * k, C.Blush, 0.35, 7)
	-- crinière (boucles le long du cou)
	local curls = { { 13, -37, 12 }, { 8, -29, 12 }, { 5, -20, 11 }, { 3, -11, 9 }, { 21, -41, 9 } }
	for index, curl in ipairs(curls) do
		kit.Blob(parent, X(curl[1]), Y(curl[2]), curl[3] * k, curl[3] * k, mane[(index - 1) % #mane + 1], { Z = 6, Thickness = 1.3 })
	end
	-- selle et tapis
	kit.Part(parent, X(-13), Y(-13), 22 * k, 14 * k, o.Blanket, { Radius = 4 * k, Z = 5, Shade = false })
	kit.Part(parent, X(-10), Y(-17), 16 * k, 8 * k, o.Saddle, { Radius = 4 * k, Z = 6, Shine = true })
	return headFrame
end

----------------------------------------------------------------------
-- Petits jouets
----------------------------------------------------------------------

-- Yo-yo rose : disque, anneau, motif qui tourne, ficelle et boucle pour le doigt
Art.YoYo = function(body, kit, _item)
	local C = kit.C
	local g = kit.Group(body, 0, 0, 100, 100, 2)
	kit.Line(g, 50, 72, 50, 24, 1.6, C.Ink, 0.25, 1)
	kit.Part(g, 43, 10, 14, 14, C.White, { Radius = -1, T = 1, Outline = C.Lilac, Thickness = 2.4, Shade = false, Z = 1 })
	kit.Blob(g, 50, 74, 46, 46, C.Pink, { Z = 3, Shine = true })
	kit.Blob(g, 50, 74, 32, 32, C.PinkSoft, { Z = 4, Outline = kit.Lighten(C.PinkDeep, 0.3), Thickness = 1.3 })
	local spin = kit.Pivot(g, 50, 74, 5)
	for _, a in ipairs({ 0, 120, 240 }) do
		local r = math.rad(a)
		kit.Heart(spin, math.sin(r) * 9, -math.cos(r) * 9, 7, C.PinkDeep, 0.1, 1)
	end
	kit.Blob(g, 50, 74, 8, 8, C.White, { Z = 6, Outline = C.PinkDeep, Thickness = 1.2 })
	kit.Animate(spin, "Spin", 0, 0.25, 0.4)
	kit.Animate(g, "Bob", 1.5, 0.8, 0.2)
	return nil
end

-- Ballon de plage : quartiers colorés, pôle blanc, léger roulis
Art.BeachBall = function(body, kit, _item)
	local C = kit.C
	local pivot, layer = rig(body, kit, 50, 69, 2)
	pivot.Rotation = -18
	kit.Blob(layer, 50, 69, 58, 58, C.Pink, { Z = 2, Shade = 0.16 })
	kit.Blob(layer, 50, 69, 40, 58, C.White, { Z = 3, Outline = false, Shade = 0.1 })
	kit.Blob(layer, 50, 69, 22, 58, C.Sky, { Z = 4, Outline = false, Shade = 0.12 })
	kit.Blob(layer, 50, 69, 6, 58, C.Butter, { Z = 5, Outline = false, Shade = false })
	kit.Blob(layer, 50, 42.5, 11, 6, C.White, { Z = 6, Thickness = 1.2 })
	kit.Shine(layer, 28, 52, 7, 12, 7, 0.3)
	kit.Animate(pivot, "Sway", 5, 0.5, 0.3)
	return nil
end

-- Canard de bain jaune, vu de 3/4, qui se dandine
Art.RubberDucky = function(body, kit, _item)
	local C = kit.C
	local yellow = Color3.fromRGB(255, 222, 110)
	local pivot, layer = rig(body, kit, 50, 97, 2)
	point(layer, kit, 22, 67, 16, yellow, 25, 2)
	kit.Blob(layer, 46, 79, 62, 36, yellow, { Z = 3, Shine = true })
	kit.Blob(layer, 38, 79, 24, 15, kit.Lighten(yellow, 0.35), { Z = 4, Rotation = -14, Thickness = 1.3 })
	kit.Blob(layer, 61, 48, 36, 34, yellow, { Z = 5, Shine = true })
	point(layer, kit, 61, 32, 9, yellow, 45, 4)
	kit.Face(layer, 61, 47, 24, { Eyes = "dot", Mouth = "none", Z = 7 })
	kit.Blob(layer, 62, 55, 15, 8, C.Orange, { Z = 8, Thickness = 1.3 })
	kit.Line(layer, 57, 55.5, 67, 55.5, 1, kit.Darken(C.Orange, 0.25), 0.3, 9)
	kit.Animate(pivot, "Sway", 4, 0.7, 0.6)
	return nil
end

-- Pièces de puzzle (tenon avec contour ; le raccord est masqué)
local function puzzlePiece(parent, kit, x, y, s, color, knobs, rotation, z)
	local g = kit.Group(parent, x, y, s, s, z)
	g.Rotation = rotation
	kit.Part(g, 0, 0, s, s, color, { Radius = 4, Z = 2, Shade = false })
	kit.Shine(g, 3.5, 3.5, s * 0.3, 3.5, 4)
	local r = s * 0.17
	for _, side in ipairs(knobs) do
		local kx, ky, cw, ch
		if side == "R" then
			kx, ky, cw, ch = s + r * 0.55, s / 2, 4.4, r * 1.5
		elseif side == "L" then
			kx, ky, cw, ch = -r * 0.55, s / 2, 4.4, r * 1.5
		elseif side == "T" then
			kx, ky, cw, ch = s / 2, -r * 0.55, r * 1.5, 4.4
		else
			kx, ky, cw, ch = s / 2, s + r * 0.55, r * 1.5, 4.4
		end
		kit.Blob(g, kx, ky, r * 2, r * 2, color, { Z = 1, Shade = false })
		local cx = if side == "R" then s else if side == "L" then 0 else s / 2
		local cy = if side == "T" then 0 else if side == "B" then s else s / 2
		kit.Box(g, cx - cw / 2, cy - ch / 2, cw, ch, color, 0, 3)
	end
	return g
end

Art.PuzzlePieces = function(body, kit, _item)
	local C = kit.C
	puzzlePiece(body, kit, 50, 67, 31, C.Mint, { "T" }, 6, 2)
	puzzlePiece(body, kit, 12, 66, 32, C.Pink, { "R", "T" }, -3, 3)
	local top = puzzlePiece(body, kit, 30, 24, 30, C.Butter, { "L", "B" }, -14, 4)
	kit.Animate(top, "Bob", 1.2, 0.7, 0.5)
	kit.Sparkle(body, 80, 40, 9, C.Lilac, 0, 5)
	return nil
end

-- Dé géant façon cube arrondi : face avant, dessus, côté, points en cœur
Art.GiantDice = function(body, kit, _item)
	local C = kit.C
	local white = Color3.fromRGB(255, 252, 250)
	local pip = C.PinkDeep
	kit.Part(body, 26, 32, 56, 22, kit.Lighten(C.PinkMist, 0.3), { Radius = 9, Z = 2, Shade = false })
	kit.Part(body, 62, 38, 20, 56, C.PinkSoft, { Radius = 9, Z = 1, Shade = 0.1 })
	local front = kit.Part(body, 14, 44, 56, 54, white, { Radius = 11, Z = 3, Shine = true, Shade = 0.08 })
	for _, p in ipairs({ { 14, 14 }, { 42, 14 }, { 14, 40 }, { 42, 40 } }) do
		local dot = kit.Circle(front, p[1], p[2], 9, 9, pip, 0, 2)
		kit.Circle(dot, 3, 3, 3, 3, C.White, 0.4, 2)
	end
	kit.Heart(front, 28, 27, 13, C.Heart, 0, 2)
	for _, p in ipairs({ { 42, 38 }, { 54, 38 }, { 66, 38 } }) do
		kit.Circle(body, p[1] + 6, p[2] + 5, 7, 4, pip, 0, 4)
	end
	kit.Circle(body, 76, 56, 4, 7, pip, 0.1, 2)
	kit.Circle(body, 76, 78, 4, 7, pip, 0.1, 2)
	return nil
end

-- Baguette magique : cœur ailé avec un visage, bâton sucre d'orge, étincelles
Art.MagicWand = function(body, kit, _item)
	local C = kit.C
	local pivot, layer = rig(body, kit, 42, 98, 3)
	pivot.Rotation = 14
	local stick = kit.Part(layer, 39, 50, 6, 48, C.White, { Radius = 3, Z = 2 })
	for index = 0, 4 do
		kit.Box(stick, 0.5, 5 + index * 8.5, 5, 3.2, C.Pink, 0.1, 2)
	end
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(layer, 42 + side * 18, 32, 17, 11, C.White, { Z = 3, Rotation = side * 24, Outline = C.Lilac, Thickness = 1.3 })
		kit.Blob(layer, 42 + side * 20, 38, 12, 8, C.LilacSoft, { Z = 2, Rotation = side * 32, Outline = C.Lilac, Thickness = 1.3 })
	end
	kit.Part(layer, 36, 48, 12, 6, C.Gold, { Radius = 3, Z = 4 })
	heartOutlined(layer, kit, 42, 34, 28, C.Pink, 5)
	kit.Shine(layer, 32, 27, 6, 4, 8)
	kit.Face(layer, 42, 36, 15, { Eyes = "happy", Mouth = "smile", Z = 8 })
	local sparkles = {
		kit.Sparkle(body, 80, 26, 11, C.Butter, 0, 6),
		kit.Sparkle(body, 16, 44, 8, C.Lilac, 0, 6),
		kit.Sparkle(body, 82, 62, 7, C.Pink, 0, 6),
	}
	for index, sparkle in ipairs(sparkles) do
		kit.Animate(sparkle, "Bob", 2, 0.8, index * 1.7)
	end
	kit.Animate(pivot, "Sway", 3, 0.5, 0.1)
	return { Glow = C.PinkSoft }
end

----------------------------------------------------------------------
-- Peluches
----------------------------------------------------------------------

-- Ours en peluche brun : museau, nœud papillon bleu, cœur cousu
Art.TeddyBear = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(205, 150, 105)
	local light = Color3.fromRGB(245, 215, 175)
	local root = breathing(body, kit, 0.012, 0.3)
	local p = plush(root, kit, { Color = fur, Light = light, BodyW = 50, BodyH = 38, HeadY = 38, HeadW = 58, HeadH = 46 })
	for _, side in ipairs({ -1, 1 }) do
		local ear = kit.Blob(p.Head, 50 + side * 22, 19, 19, 18, fur, { Z = 3 })
		kit.Circle(ear, 9.5, 10, 10, 9, light, 0, 2)
	end
	muzzle(p.Head, kit, 50, 49, 22, 15, light, C.Brown, 5)
	kit.Face(p.Head, 50, 38, 32, { Eyes = "dot", Mouth = "none", Z = 6 })
	bow(root, kit, 50, 62, 20, C.Sky, 7)
	kit.Heart(p.Torso, 32, 22, 9, C.Heart, 0, 3)
	kit.Animate(p.Neck, "Sway", 3, 0.6, 0.2)
	return nil
end

-- Lapin blanc : longues oreilles (une qui bouge), carotte dans les bras
Art.BunnyPlush = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(255, 246, 250)
	local root = breathing(body, kit, 0.012, 1.1)
	local p = plush(root, kit, { Color = fur, Light = C.PinkMist, Paw = C.PinkSoft, BodyW = 48, BodyH = 36, HeadY = 46, HeadW = 54, HeadH = 42 })
	local left = kit.Blob(p.Head, 40, 14, 14, 36, fur, { Z = 3, Rotation = -8 })
	kit.Blob(left, 7, 17, 6, 25, C.PinkSoft, { Z = 2, Outline = false, Shade = false })
	local earPivot, ear = rig(p.Head, kit, 59, 30, 3)
	local right = kit.Blob(ear, 62, 14, 14, 36, fur, { Z = 1, Rotation = 12 })
	kit.Blob(right, 7, 17, 6, 25, C.PinkSoft, { Z = 2, Outline = false, Shade = false })
	kit.Face(p.Head, 50, 46, 30, { Eyes = "big", Mouth = "cat", Z = 6 })
	kit.Blob(p.Head, 50, 47.6, 4, 3, C.Pink, { Z = 7, Outline = false, Shade = false })
	-- carotte
	kit.Blob(root, 50, 79, 10, 24, C.Orange, { Z = 4, Rotation = 28, Thickness = 1.3 })
	kit.Blob(root, 57, 66, 6, 11, C.Leaf, { Z = 4, Rotation = 10, Thickness = 1.2 })
	kit.Blob(root, 61, 69, 6, 11, C.Leaf, { Z = 4, Rotation = 55, Thickness = 1.2 })
	kit.Animate(earPivot, "Sway", 6, 0.7, 0.4)
	kit.Animate(p.Neck, "Sway", 2.5, 0.5, 1.3)
	return nil
end

-- Chaton gris tigré : oreilles pointues, moustaches, clochette, queue qui balance
Art.KittyPlush = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(206, 200, 226)
	local stripe = kit.Darken(fur, 0.2)
	local root = breathing(body, kit, 0.012, 2.1)
	local tailPivot, tail = rig(root, kit, 70, 92, 1)
	kit.Blob(tail, 80, 76, 11, 32, fur, { Z = 1, Rotation = 22 })
	kit.Blob(tail, 85.5, 63, 9, 9, stripe, { Z = 2, Outline = false, Shade = false })
	local p = plush(root, kit, { Color = fur, Light = C.Cream, Paw = C.PinkSoft, BodyW = 48, BodyH = 36, HeadY = 42, HeadW = 62, HeadH = 44 })
	point(p.Head, kit, 30, 24, 19, fur, 33, 2, C.PinkSoft)
	point(p.Head, kit, 70, 24, 19, fur, 57, 2, C.PinkSoft)
	for _, s in ipairs({ { 50, 21, 50, 28 }, { 43, 22, 44, 27 }, { 57, 22, 56, 27 } }) do
		kit.Line(p.Head, s[1], s[2], s[3], s[4], 2.4, stripe, 0, 6)
	end
	kit.Face(p.Head, 50, 43, 32, { Eyes = "dot", Mouth = "cat", Z = 6 })
	kit.Blob(p.Head, 50, 45, 4, 3, C.Pink, { Z = 7, Outline = false, Shade = false })
	for _, side in ipairs({ -1, 1 }) do
		kit.Line(p.Head, 50 + side * 21, 45, 50 + side * 30, 43, 1.1, C.Ink, 0.35, 6)
		kit.Line(p.Head, 50 + side * 21, 48, 50 + side * 30, 49, 1.1, C.Ink, 0.35, 6)
	end
	kit.Part(root, 36, 62, 28, 5, C.Pink, { Radius = 3, Z = 7, Shade = false })
	local bell = kit.Blob(root, 50, 68, 8, 8, C.Gold, { Z = 8, Thickness = 1.2 })
	kit.Box(bell, 1.5, 4.5, 5, 1, kit.Darken(C.Gold, 0.3), 0, 2)
	kit.Animate(tailPivot, "Sway", 8, 0.8, 0.7)
	kit.Animate(p.Neck, "Sway", 2.5, 0.5, 2.2)
	return nil
end

-- Chiot crème : oreilles tombantes, tache sur l'œil, langue, collier + médaille
Art.PuppyPlush = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(248, 228, 198)
	local brown = Color3.fromRGB(196, 140, 100)
	local root = breathing(body, kit, 0.012, 3.3)
	local tailPivot, tail = rig(root, kit, 70, 86, 1)
	kit.Blob(tail, 76, 78, 10, 18, brown, { Z = 1, Rotation = 40 })
	local p = plush(root, kit, { Color = fur, Light = C.Cream, Paw = brown, BodyW = 50, BodyH = 38, HeadY = 40, HeadW = 60, HeadH = 46 })
	kit.Circle(p.Head, 60, 37, 14, 13, kit.Lighten(brown, 0.25), 0, 5)
	kit.Blob(p.Head, 50, 58, 7, 8, C.Pink, { Z = 4, Thickness = 1.2 })
	muzzle(p.Head, kit, 50, 51, 22, 14, C.White, C.Ink, 5)
	kit.Face(p.Head, 50, 40, 32, { Eyes = "happy", Mouth = "none", Z = 6 })
	for _, side in ipairs({ -1, 1 }) do
		local earPivot, ear = rig(p.Head, kit, 50 + side * 25, 26, 7)
		kit.Blob(ear, 50 + side * 28, 40, 15, 28, brown, { Z = 1, Rotation = -side * 14 })
		kit.Animate(earPivot, "Sway", 3, 0.6, side)
	end
	kit.Part(root, 35, 60, 30, 6, C.Red, { Radius = 3, Z = 7, Shade = false })
	kit.Blob(root, 50, 67, 8, 8, C.Gold, { Z = 8, Thickness = 1.2 })
	kit.Animate(tailPivot, "Sway", 14, 2.2, 0.1)
	return nil
end

-- Grenouille : gros yeux sur le dessus, grand sourire, petite couronne
Art.FroggyPlush = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(150, 215, 125)
	local root = breathing(body, kit, 0.014, 4.4)
	local p = plush(root, kit, { Color = fur, Light = Color3.fromRGB(228, 246, 190), Paw = kit.Lighten(fur, 0.4), BodyW = 54, BodyH = 32, HeadY = 55, HeadW = 72, HeadH = 40 })
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(p.Head, 50 + side * 17, 40, 24, 22, fur, { Z = 3 })
	end
	kit.Face(p.Head, 50, 43, 42, { Eyes = "big", Spacing = 0.8, Mouth = "none", Blush = false, Z = 6 })
	for _, side in ipairs({ -1, 1 }) do
		kit.Circle(p.Head, 50 + side * 22, 59, 11, 6, C.Blush, 0.3, 6)
	end
	kit.Line(p.Head, 39, 57, 45, 61, 2, C.Ink, 0, 6)
	kit.Line(p.Head, 45, 61, 55, 61, 2, C.Ink, 0, 6)
	kit.Line(p.Head, 55, 61, 61, 57, 2, C.Ink, 0, 6)
	-- couronne
	for _, x in ipairs({ 43, 50, 57 }) do
		kit.Diamond(p.Head, x, 28, 5, C.Gold, 0, 3)
	end
	kit.Part(p.Head, 42, 28, 16, 7, C.Gold, { Radius = 2, Z = 4 })
	kit.Circle(p.Head, 50, 31.5, 3.5, 3.5, C.PinkDeep, 0, 5)
	kit.Animate(p.Neck, "Sway", 2, 0.5, 4.1)
	return nil
end

-- Dino menthe : piquants roses sur la tête et la queue, ventre rayé, "rawr"
Art.DinoPlush = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(150, 222, 196)
	local root = breathing(body, kit, 0.012, 5.2)
	local tailPivot, tail = rig(root, kit, 66, 90, 1)
	point(tail, kit, 80, 76, 9, C.Pink, 45, 1)
	point(tail, kit, 89, 70, 8, C.Pink, 45, 1)
	kit.Blob(tail, 82, 84, 34, 15, fur, { Z = 2, Rotation = -30 })
	local p = plush(root, kit, { Color = fur, Light = C.Butter, Paw = kit.Darken(fur, 0.15), BodyW = 50, BodyH = 38, HeadY = 40, HeadW = 60, HeadH = 46 })
	kit.Box(p.Torso, 16, 20, 18, 1.6, kit.Darken(C.Butter, 0.15), 0, 3)
	kit.Box(p.Torso, 17, 26, 16, 1.6, kit.Darken(C.Butter, 0.15), 0, 3)
	point(p.Head, kit, 50, 18, 13, C.Pink, 45, 2)
	point(p.Head, kit, 37, 21, 10, C.Pink, 35, 2)
	point(p.Head, kit, 63, 21, 10, C.Pink, 55, 2)
	kit.Face(p.Head, 50, 41, 32, { Eyes = "happy", Mouth = "o", Z = 6 })
	for _, x in ipairs({ 46, 54 }) do
		kit.Circle(p.Head, x, 33, 2, 1.6, kit.Darken(fur, 0.35), 0, 6)
	end
	for _, s in ipairs({ { 30, 49 }, { 70, 49 } }) do
		kit.Circle(p.Head, s[1], s[2] - 20, 5, 5, kit.Darken(fur, 0.1), 0, 5)
	end
	kit.Animate(tailPivot, "Sway", 6, 0.7, 0.9)
	kit.Animate(p.Neck, "Sway", 2.5, 0.5, 5.3)
	return nil
end

-- Hamster tout rond : joues gonflées, graine de tournesol entre les pattes
Art.HamsterPlush = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(250, 196, 132)
	local cream = Color3.fromRGB(255, 244, 228)
	local root = breathing(body, kit, 0.02, 6.1)
	for _, side in ipairs({ -1, 1 }) do
		local ear = kit.Blob(root, 50 + side * 21, 42, 15, 14, fur, { Z = 2 })
		kit.Circle(ear, 7.5, 7.5, 8, 7, C.PinkSoft, 0, 2)
		kit.Blob(root, 50 + side * 12, 97, 12, 6, C.PinkSoft, { Z = 2, Thickness = 1.2 })
	end
	local ball = kit.Blob(root, 50, 69, 72, 58, fur, { Z = 3, Shine = true })
	kit.Blob(ball, 36, 38, 52, 38, cream, { Z = 2, Outline = false, Shade = false })
	kit.Blob(ball, 36, 11, 8, 10, kit.Darken(fur, 0.12), { Z = 2, Outline = false, Shade = false })
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(ball, 36 + side * 21, 29, 20, 16, cream, { Z = 3, Outline = false, Shade = false })
	end
	kit.Face(root, 50, 60, 32, { Eyes = "dot", Mouth = "cat", Z = 6 })
	kit.Blob(root, 50, 61.4, 4, 3, C.Pink, { Z = 7, Outline = false, Shade = false })
	local seed = kit.Blob(root, 50, 80, 10, 14, C.GreyDark, { Z = 7 })
	kit.Box(seed, 4.2, 2, 1.6, 10, C.White, 0.2, 2)
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(root, 50 + side * 6, 80, 8, 7, fur, { Z = 8, Thickness = 1.2 })
	end
	return nil
end

-- Pingouin : corps en œuf marine, masque en cœur, écharpe rose, ailerons qui saluent
Art.PenguinPlush = function(body, kit, _item)
	local C = kit.C
	local navy = Color3.fromRGB(88, 102, 160)
	local white = Color3.fromRGB(255, 252, 250)
	local root = breathing(body, kit, 0.012, 7.3)
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(root, 50 + side * 11, 96, 16, 8, C.Orange, { Z = 2, Thickness = 1.2 })
	end
	local flippers = {}
	for _, side in ipairs({ -1, 1 }) do
		local fp, flipper = rig(root, kit, 50 + side * 26, 62, 4)
		kit.Blob(flipper, 50 + side * 30, 74, 12, 26, navy, { Z = 1, Rotation = -side * 28 })
		table.insert(flippers, fp)
	end
	local egg = kit.Blob(root, 50, 62, 58, 72, navy, { Z = 3, Shine = true })
	kit.Blob(egg, 29, 50, 40, 40, white, { Z = 2, Outline = false, Shade = 0.08 })
	for _, side in ipairs({ -1, 1 }) do
		kit.Circle(egg, 29 + side * 7.5, 20, 24, 22, white, 0, 2)
	end
	kit.Face(root, 50, 47, 28, { Eyes = "big", Mouth = "none", Z = 6 })
	kit.Blob(root, 50, 51, 9, 6, C.Orange, { Z = 7, Thickness = 1.2 })
	kit.Part(root, 58, 62, 8, 20, C.Pink, { Radius = 3, Z = 6, Rotation = -10 })
	kit.Part(root, 27, 58, 46, 8, C.Pink, { Radius = 4, Z = 7, Shade = false })
	for _, y in ipairs({ 68, 74 }) do
		kit.Box(root, 59.5 - (y - 68) * 0.2, y, 7, 2, C.PinkSoft, 0, 7).Rotation = -10
	end
	kit.Animate(flippers[1], "Sway", 6, 0.9, 0.2)
	kit.Animate(flippers[2], "Sway", 6, 0.9, 1.9)
	return nil
end

-- Panda : oreilles et taches noires, reflets dans les yeux, tige de bambou
Art.PandaPlush = function(body, kit, _item)
	local C = kit.C
	local white = Color3.fromRGB(252, 250, 252)
	local black = Color3.fromRGB(78, 70, 92)
	local root = breathing(body, kit, 0.012, 8.2)
	-- bambou
	local bamboo = kit.Part(root, 64, 46, 7, 50, C.Leaf, { Radius = 3, Z = 4, Rotation = 18 })
	for _, y in ipairs({ 14, 30 }) do
		kit.Box(bamboo, 0, y, 7, 1.6, C.LeafDark, 0, 2)
	end
	kit.Blob(root, 79, 44, 7, 16, C.Leaf, { Z = 4, Rotation = 55, Thickness = 1.2 })
	local p = plush(root, kit, { Color = white, Limb = black, Belly = false, Paw = kit.Lighten(black, 0.25), BodyW = 52, BodyH = 38, HeadY = 40, HeadW = 60, HeadH = 46 })
	kit.Blob(p.Torso, 26, 6, 46, 12, black, { Z = 2, Outline = false, Shade = false })
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(p.Head, 50 + side * 22, 20, 18, 17, black, { Z = 3 })
		kit.Blob(p.Head, 50 + side * 11, 40, 13, 17, black, { Z = 5, Rotation = side * 32, Outline = false, Shade = false })
		local eye = kit.Circle(p.Head, 50 + side * 10.5, 39, 6, 6.5, white, 0, 6)
		local pupil = kit.Circle(eye, 3.5, 3.6, 4, 4.2, C.Ink, 0, 2)
		kit.Circle(pupil, 1.3, 1.3, 1.6, 1.6, white, 0, 2)
		kit.Circle(p.Head, 50 + side * 18, 50, 8, 5, C.Blush, 0.35, 6)
	end
	kit.Blob(p.Head, 50, 48, 7, 4.5, black, { Z = 6, Outline = false, Shade = false })
	kit.Line(p.Head, 47, 53, 50, 51.5, 1.3, black, 0, 6)
	kit.Line(p.Head, 50, 51.5, 53, 53, 1.3, black, 0, 6)
	kit.Animate(p.Neck, "Sway", 2.5, 0.5, 8.6)
	return nil
end

-- Licorne : corne dorée, frange arc-en-ciel, yeux fermés à cils, sabots lilas
Art.UnicornPlush = function(body, kit, _item)
	local C = kit.C
	local white = Color3.fromRGB(255, 250, 253)
	local rainbow = { C.Pink, C.Butter, C.Mint, C.Sky, C.Lilac }
	local root = breathing(body, kit, 0.012, 9.1)
	local tailPivot, tail = rig(root, kit, 70, 90, 1)
	for index, color in ipairs({ C.Lilac, C.Sky, C.Pink }) do
		kit.Blob(tail, 76 + index * 4, 84 - index * 7, 11, 22, color, { Z = index, Rotation = 30 - index * 6, Thickness = 1.3 })
	end
	local p = plush(root, kit, { Color = white, Light = C.PinkMist, Paw = C.Lilac, BodyW = 48, BodyH = 36, HeadY = 44, HeadW = 54, HeadH = 44 })
	for index, s in ipairs({ { 26, 34, 14 }, { 24, 47, 13 }, { 74, 34, 14 }, { 76, 47, 13 } }) do
		kit.Blob(p.Head, s[1], s[2], s[3], s[3], rainbow[index + 1], { Z = 3, Thickness = 1.3 })
	end
	point(p.Head, kit, 33, 25, 13, white, 30, 2, C.PinkSoft)
	point(p.Head, kit, 67, 25, 13, white, 60, 2, C.PinkSoft)
	for index, s in ipairs({ { 38, 27, 12 }, { 46, 25, 11 }, { 58, 25, 11 }, { 64, 29, 9 } }) do
		kit.Blob(p.Head, s[1], s[2], s[3], s[3], rainbow[index], { Z = 5, Thickness = 1.3 })
	end
	kit.Triangle(p.Head, 50, 1.5, 14, 25, kit.OutlineOf(C.Butter), 6, 0, 8)
	kit.Triangle(p.Head, 50, 4, 10, 21, C.Butter, 7, 0, 8)
	kit.Line(p.Head, 46.5, 20, 53.5, 18, 1.4, C.Gold, 0, 8)
	kit.Line(p.Head, 47.5, 14, 52.5, 12.5, 1.4, C.Gold, 0, 8)
	kit.Face(p.Head, 50, 42, 30, { Eyes = "closed", Mouth = "none", Z = 6 })
	for _, side in ipairs({ -1, 1 }) do
		local ex = 50 + side * 14.8
		kit.Line(p.Head, ex + side * 3.5, 39.6, ex + side * 5.5, 37.4, 1.2, C.Ink, 0, 6)
	end
	local snout = kit.Blob(p.Head, 50, 53, 28, 15, C.PinkSoft, { Z = 5, Thickness = 1.3 })
	kit.Circle(snout, 9, 5, 2.4, 2, C.Ink, 0.4, 2)
	kit.Circle(snout, 19, 5, 2.4, 2, C.Ink, 0.4, 2)
	kit.Line(snout, 11.5, 10, 14, 11.5, 1.3, C.Ink, 0, 2)
	kit.Line(snout, 14, 11.5, 16.5, 10, 1.3, C.Ink, 0, 2)
	local sparkle = kit.Sparkle(root, 76, 12, 10, C.Butter, 0, 8)
	kit.Animate(sparkle, "Bob", 2, 0.7, 0.3)
	kit.Animate(tailPivot, "Sway", 6, 0.6, 9.4)
	kit.Animate(p.Neck, "Sway", 2.5, 0.5, 9.2)
	return nil
end

-- Gros ours géant couleur miel : grand nœud rose, coussin cœur dans les bras
Art.BigBear = function(body, kit, _item)
	local C = kit.C
	local fur = Color3.fromRGB(240, 196, 140)
	local light = Color3.fromRGB(255, 236, 205)
	local root = breathing(body, kit, 0.01, 10.4)
	local p = plush(root, kit, { Color = fur, Light = light, BodyW = 58, BodyH = 42, HeadY = 36, HeadW = 64, HeadH = 50 })
	for _, side in ipairs({ -1, 1 }) do
		local ear = kit.Blob(p.Head, 50 + side * 25, 15, 21, 20, fur, { Z = 3 })
		kit.Circle(ear, 10.5, 11, 11, 10, light, 0, 2)
	end
	muzzle(p.Head, kit, 50, 47, 24, 16, light, C.Brown, 5)
	kit.Face(p.Head, 50, 36, 36, { Eyes = "happy", Mouth = "none", Z = 6 })
	bow(p.Head, kit, 71, 16, 18, C.Pink, 7)
	-- coussin cœur tenu contre le ventre
	heartOutlined(root, kit, 50, 78, 24, C.Heart, 4)
	kit.Shine(root, 42, 71, 5, 3, 6)
	kit.Part(root, 31, 58, 38, 6, C.PinkSoft, { Radius = 3, Z = 7, Shade = false })
	kit.Animate(p.Neck, "Sway", 2, 0.45, 10.2)
	return nil
end

----------------------------------------------------------------------
-- Jouets moyens
----------------------------------------------------------------------

-- Cerf-volant arc-en-ciel avec visage, queue à nœuds qui ondule
Art.Kite = function(body, kit, _item)
	local C = kit.C
	local pivot, layer = rig(body, kit, 50, 40, 2)
	local tailPivot, tail = rig(layer, kit, 50, 74, 1)
	kit.Line(tail, 50, 74, 44, 83, 1.3, C.Ink, 0.3, 1)
	kit.Line(tail, 44, 83, 54, 91, 1.3, C.Ink, 0.3, 1)
	kit.Line(tail, 54, 91, 46, 99, 1.3, C.Ink, 0.3, 1)
	bow(tail, kit, 44, 83, 11, C.Pink, 2)
	bow(tail, kit, 54, 91, 10, C.Mint, 2)
	bow(tail, kit, 46, 99, 9, C.Lilac, 2)
	local sail = kit.Part(layer, 25, 15, 50, 50, C.White, { Radius = 6, Z = 3, Rotation = 45, Shade = false, Outline = C.Ink, Thickness = 1.8 })
	local grad = kit.Gradient(sail, C.White, C.White, 45)
	local bands = { C.Pink, C.Peach, C.Butter, C.Mint, C.Sky, C.Lilac }
	local keys = {}
	for index, color in ipairs(bands) do
		local t0 = (index - 1) / #bands
		local t1 = index / #bands
		table.insert(keys, ColorSequenceKeypoint.new(if index == 1 then 0 else t0 + 0.01, color))
		table.insert(keys, ColorSequenceKeypoint.new(if index == #bands then 1 else t1 - 0.01, color))
	end
	grad.Color = ColorSequence.new(keys)
	kit.Line(layer, 50, 8, 50, 72, 1.4, C.White, 0.45, 4)
	kit.Line(layer, 18, 40, 82, 40, 1.4, C.White, 0.45, 4)
	kit.Face(layer, 50, 44, 22, { Eyes = "dot", Mouth = "smile", Z = 5 })
	kit.Shine(layer, 38, 22, 8, 4, 5).Rotation = -45
	kit.Animate(pivot, "Sway", 4, 0.5, 0.2)
	kit.Animate(tailPivot, "Sway", 9, 0.9, 0.8)
	return { WallShadow = Vector2.new(0.55, 0.7) }
end

-- Robot jouet : écran-visage lumineux, antenne qui clignote, bras qui saluent
Art.ToyRobot = function(body, kit, _item)
	local C = kit.C
	local metal = Color3.fromRGB(170, 210, 245)
	for _, x in ipairs({ 36, 54 }) do
		kit.Part(body, x, 80, 10, 12, C.Grey, { Radius = 2, Z = 1 })
		kit.Part(body, x - 3, 90, 16, 8, kit.Darken(metal, 0.08), { Radius = 4, Z = 2 })
	end
	local arms = {}
	for _, side in ipairs({ -1, 1 }) do
		local ap, arm = rig(body, kit, 50 + side * 22, 60, 2)
		kit.Part(arm, 50 + side * 24 - 4, 58, 8, 18, C.Grey, { Radius = 4, Z = 1 })
		kit.Blob(arm, 50 + side * 24, 79, 11, 10, C.Butter, { Z = 2 })
		table.insert(arms, ap)
	end
	local torso = kit.Part(body, 27, 55, 46, 32, metal, { Radius = 9, Z = 3, Shine = true })
	local panel = kit.Part(torso, 10, 8, 26, 17, C.Cream, { Radius = 5, Z = 2, Thickness = 1.2 })
	kit.Heart(panel, 8, 8.5, 9, C.Heart, 0, 2)
	kit.Circle(panel, 17.5, 6, 4, 4, C.Mint, 0, 2)
	kit.Circle(panel, 17.5, 12, 4, 4, C.Butter, 0, 2)
	kit.Box(body, 45, 50, 10, 6, C.Grey, 0, 2)
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(body, 50 + side * 26 - 3, 30, 6, 12, C.Pink, { Radius = 3, Z = 3 })
	end
	local head = kit.Part(body, 25, 18, 50, 36, metal, { Radius = 11, Z = 4, Shine = true })
	local screen = kit.Part(head, 6, 6, 38, 24, C.Navy, { Radius = 7, Z = 2, Thickness = 1.3 })
	kit.Face(screen, 19, 13, 24, { Eyes = "big", Mouth = "smile", Color = C.Mint, Z = 3 })
	kit.Line(body, 50, 18, 50, 9, 2, C.GreyDark, 0, 2)
	local bulb = kit.Blob(body, 50, 7, 9, 9, C.Heart, { Z = 3, Thickness = 1.2 })
	kit.Circle(bulb, 3, 3, 2.5, 2.5, C.White, 0.2, 2)
	kit.Animate(bulb, "Pulse", 0.5, 0.8, 0.3)
	kit.Animate(arms[1], "Sway", 8, 0.7, 0.4)
	kit.Animate(arms[2], "Sway", 8, 0.7, 2.1)
	return nil
end

-- Tambour : peau crème, cerclages dorés, cordage en zigzag, baguettes qui tapent
Art.ToyDrum = function(body, kit, _item)
	local C = kit.C
	local shell = Color3.fromRGB(255, 150, 175)
	kit.Part(body, 14, 50, 72, 42, shell, { Radius = 8, Z = 2, Shine = true, Shade = 0.16 })
	kit.Part(body, 12, 86, 76, 11, C.Gold, { Radius = 5, Z = 4 })
	kit.Blob(body, 50, 50, 76, 22, C.Gold, { Z = 3 })
	kit.Blob(body, 50, 49, 66, 15, C.Cream, { Z = 4, Shade = false, Thickness = 1.3 })
	local xs = { 20, 30, 40, 50, 60, 70, 80 }
	for index = 1, #xs - 1 do
		local y1 = if index % 2 == 1 then 60 else 85
		local y2 = if index % 2 == 1 then 85 else 60
		kit.Line(body, xs[index], y1, xs[index + 1], y2, 2.2, C.White, 0.05, 3)
	end
	for index, side in ipairs({ -1, 1 }) do
		local sp, stick = rig(body, kit, 50 + side * 12, 50, 6)
		kit.Line(stick, 50 + side * 12, 50, 50 + side * 32, 24, 3, C.WoodLight, 0, 1)
		kit.Blob(stick, 50 + side * 32, 24, 8, 8, if side < 0 then C.Pink else C.Sky, { Z = 2 })
		kit.Animate(sp, "Sway", 7, 1.4, index * 1.6)
	end
	return nil
end

-- Poupées russes : 3 poupées pastel de tailles différentes, visages variés
local function doll(parent, kit, cx, h, color, eyes, z)
	local C = kit.C
	local w = h * 0.62
	local g = kit.Group(parent, 0, 0, 100, 100, z)
	local bodyH = h * 0.7
	kit.Blob(g, cx, 98 - bodyH / 2, w, bodyH, color, { Z = 3, Shine = true })
	local headD = w * 0.82
	local headCy = 98 - h + headD / 2
	kit.Blob(g, cx, headCy, headD, headD, color, { Z = 2 })
	local face = kit.Blob(g, cx, headCy + headD * 0.08, headD * 0.66, headD * 0.58, C.Cream, { Z = 4, Thickness = 1.2, Shade = false })
	kit.Blob(face, headD * 0.33, headD * 0.08, headD * 0.5, headD * 0.22, C.WoodDark, { Z = 2, Outline = false, Shade = false })
	kit.Face(g, cx, headCy + headD * 0.14, headD * 0.5, { Eyes = eyes, Z = 6 })
	kit.Blob(g, cx, 98 - bodyH * 0.4, w * 0.6, bodyH * 0.56, C.Cream, { Z = 4, Thickness = 1.2, Shade = false })
	kit.Heart(g, cx, 98 - bodyH * 0.42, w * 0.3, kit.Darken(color, 0.05), 0, 5)
	return g
end

Art.NestingDolls = function(body, kit, _item)
	local C = kit.C
	local big = doll(body, kit, 30, 70, C.Pink, "dot", 2)
	local mid = doll(body, kit, 63, 52, C.Lilac, "happy", 3)
	local small = doll(body, kit, 87, 36, C.Mint, "closed", 4)
	kit.Animate(big, "Sway", 1.5, 0.6, 0.1)
	kit.Animate(mid, "Sway", 2, 0.7, 1.4)
	kit.Animate(small, "Sway", 2.5, 0.8, 2.7)
	return nil
end

-- Guitare rose appuyée : caisse en 8, rosace, manche, cordes, sticker cœur
Art.PinkGuitar = function(body, kit, _item)
	local C = kit.C
	local pink = Color3.fromRGB(255, 160, 200)
	local pivot, layer = rig(body, kit, 50, 98, 2)
	pivot.Rotation = 10
	kit.Blob(layer, 50, 56, 34, 30, pink, { Z = 2, Shade = false })
	kit.Blob(layer, 50, 79, 46, 38, pink, { Z = 3, Shade = false, Shine = true })
	kit.Box(layer, 36, 60, 28, 10, pink, 0, 4)
	kit.Blob(layer, 50, 67, 15, 15, C.Cream, { Z = 5, Thickness = 1.3 })
	kit.Circle(layer, 50, 67, 10, 10, kit.OutlineOf(pink), 0, 6)
	kit.Part(layer, 46.5, 6, 7, 58, C.WoodLight, { Radius = 2, Z = 7, Shade = false })
	for _, y in ipairs({ 18, 30, 42 }) do
		kit.Box(layer, 46.5, y, 7, 1.2, C.Gold, 0, 8)
	end
	kit.Part(layer, 43, -4, 14, 14, C.PinkDeep, { Radius = 4, Z = 8 })
	for _, s in ipairs({ { 41, -1 }, { 41, 5 }, { 59, -1 }, { 59, 5 } }) do
		kit.Circle(layer, s[1], s[2], 4, 4, C.Butter, 0, 7)
	end
	kit.Part(layer, 41, 84, 18, 5, C.WoodDark, { Radius = 2, Z = 7 })
	for _, x in ipairs({ 48, 50, 52 }) do
		kit.Line(layer, x, 4, x, 86, 0.7, C.White, 0.1, 9)
	end
	kit.Heart(layer, 62, 82, 9, C.White, 0, 6)
	kit.Sparkle(layer, 36, 88, 6, C.White, 0.1, 6)
	return nil
end

----------------------------------------------------------------------
-- Grands jouets
----------------------------------------------------------------------

-- Cheval à bascule en bois : crinière rose, selle rouge, bascule qui berce
Art.RockingHorse = function(body, kit, _item)
	local C = kit.C
	local pivot, layer = rig(body, kit, 50, 95, 2)
	local wood = Color3.fromRGB(236, 196, 150)
	local rocker = { { 5, 78 }, { 20, 88 }, { 50, 93 }, { 80, 88 }, { 95, 78 } }
	horse(layer, kit, {
		X = 48,
		Y = 50,
		K = 1,
		Coat = wood,
		Mane = { C.Pink, C.PinkSoft, C.Lilac },
		Saddle = C.Red,
		Blanket = C.Sky,
		Hoof = C.WoodDark,
		Legs = {
			{ -10, 8, -24, 38, nil, nil, true },
			{ 12, 8, 26, 38, nil, nil, true },
			{ -14, 8, -28, 37 },
			{ 16, 8, 30, 37 },
		},
	})
	for index = 1, #rocker - 1 do
		local a, b = rocker[index], rocker[index + 1]
		kit.Line(layer, a[1], a[2], b[1], b[2], 6, C.WoodDark, 0, 4)
	end
	kit.Circle(layer, 5, 78, 7, 7, C.Pink, 0, 5)
	kit.Circle(layer, 95, 78, 7, 7, C.Pink, 0, 5)
	kit.Line(layer, 66, 20, 76, 26, 2.6, C.Gold, 0, 8)
	kit.Animate(pivot, "Sway", 4, 0.7, 0.2)
	return nil
end

-- Train à vapeur : locomotive souriante, wagon de cubes, roues qui tournent, fumée
Art.ToyTrain = function(body, kit, _item)
	local C = kit.C
	local wheels = {}
	local function wheel(cx, cy, d, color)
		local w = kit.Blob(body, cx, cy, d, d, color, { Z = 6, Shade = false })
		kit.Line(w, d * 0.18, d / 2, d * 0.82, d / 2, 1.6, C.White, 0.2, 2)
		kit.Line(w, d / 2, d * 0.18, d / 2, d * 0.82, 1.6, C.White, 0.2, 2)
		kit.Circle(w, d / 2, d / 2, d * 0.32, d * 0.32, C.Butter, 0, 3)
		table.insert(wheels, w)
	end
	-- wagon de cubes
	kit.Part(body, 5, 51, 11, 11, C.Mint, { Radius = 2, Z = 2, Rotation = -8 })
	kit.Part(body, 15, 47, 12, 12, C.Pink, { Radius = 2, Z = 2, Rotation = 10 })
	kit.Part(body, 25, 53, 9, 9, C.Sky, { Radius = 2, Z = 2, Rotation = -4 })
	kit.Part(body, 2, 60, 34, 22, C.Butter, { Radius = 5, Z = 3, Shine = true })
	kit.Box(body, 34, 78, 8, 3, C.GreyDark, 0, 2)
	-- locomotive
	kit.Part(body, 38, 80, 60, 6, C.Navy, { Radius = 3, Z = 3 })
	kit.Part(body, 62, 54, 34, 28, C.Sky, { Radius = 12, Z = 3, Shine = true })
	for _, x in ipairs({ 70, 86 }) do
		kit.Box(body, x, 55, 2.5, 26, C.Gold, 0, 4)
	end
	kit.Part(body, 80, 38, 10, 18, C.GreyDark, { Radius = 2, Z = 2 })
	kit.Part(body, 76, 33, 18, 7, C.GreyDark, { Radius = 3, Z = 3 })
	kit.Blob(body, 73, 54, 10, 7, C.Gold, { Z = 2 })
	kit.Part(body, 92, 78, 8, 10, C.Red, { Radius = 2, Z = 4, Rotation = -12 })
	kit.Part(body, 40, 40, 26, 44, C.Pink, { Radius = 5, Z = 4, Shine = true })
	kit.Part(body, 45, 46, 16, 13, C.Glass, { Radius = 4, Z = 5, Thickness = 1.3 })
	kit.Part(body, 37, 34, 32, 8, C.PinkDeep, { Radius = 4, Z = 6 })
	kit.Face(body, 79, 67, 18, { Eyes = "happy", Mouth = "smile", Z = 5 })
	wheel(53, 87, 20, C.PinkDeep)
	wheel(76, 90, 14, C.PinkDeep)
	wheel(90, 90, 14, C.PinkDeep)
	wheel(12, 88, 14, C.Lilac)
	wheel(27, 88, 14, C.Lilac)
	for _, w in ipairs(wheels) do
		kit.Animate(w, "Spin", 0, 0.3, 0)
	end
	local puffs = { kit.Cloud(body, 86, 30, 16, C.White, 0.1, 7), kit.Cloud(body, 76, 18, 12, C.White, 0.3, 7) }
	kit.Animate(puffs[1], "Bob", 2, 0.8, 0.3)
	kit.Animate(puffs[2], "Drift", 3, 0.6, 1.2)
	return nil
end

-- Fort en couverture : couverture à pois sur 2 chaises, guirlande lumineuse,
-- petits yeux qui brillent dans le noir, drapeau, coussins
Art.BlanketFort = function(body, kit, _item)
	local C = kit.C
	local blanket = Color3.fromRGB(255, 188, 214)
	for _, x in ipairs({ 3, 85 }) do
		kit.Part(body, x, 20, 12, 78, C.WoodLight, { Radius = 4, Z = 1 })
		kit.Circle(body, x + 6, 20, 9, 9, C.Wood, 0, 1)
	end
	local tent = kit.Group(body, 6, 24, 88, 74, 2, true)
	kit.Part(tent, 2, 2, 84, 120, blanket, { Radius = 30, Z = 1, Shade = 0.1 })
	for _, d in ipairs({ { 18, 18 }, { 44, 10 }, { 70, 18 }, { 12, 46 }, { 76, 46 }, { 20, 64 }, { 68, 64 } }) do
		kit.Circle(tent, d[1], d[2], 7, 7, C.White, 0.25, 2)
	end
	local door = kit.Part(tent, 27, 28, 34, 60, C.Navy, { Radius = 16, Z = 3, Shade = false })
	kit.Gradient(door, Color3.fromRGB(150, 130, 200), Color3.fromRGB(255, 220, 190), 90)
	kit.Face(tent, 44, 50, 20, { Eyes = "dot", Mouth = "none", Blush = false, Color = C.Butter, Z = 4 })
	kit.Blob(tent, 26, 56, 14, 58, kit.Lighten(blanket, 0.35), { Z = 5, Rotation = 12 })
	kit.Blob(tent, 62, 56, 14, 58, kit.Lighten(blanket, 0.35), { Z = 5, Rotation = -12 })
	kit.Part(body, 6, 90, 88, 8, C.PinkDeep, { Radius = 3, Z = 3, Shade = false })
	-- guirlande lumineuse
	local pts = { { 9, 30 }, { 29, 40 }, { 50, 43 }, { 71, 40 }, { 91, 30 } }
	for index = 1, #pts - 1 do
		kit.Line(body, pts[index][1], pts[index][2], pts[index + 1][1], pts[index + 1][2], 1, C.Ink, 0.4, 6)
	end
	local bulbs = {}
	local colors = { C.Butter, C.Mint, C.Sky, C.Lilac, C.Butter }
	for index, pt in ipairs({ { 19, 36 }, { 39, 42 }, { 50, 44.5 }, { 61, 42 }, { 81, 36 } }) do
		local halo = kit.Circle(body, pt[1], pt[2] + 3, 11, 11, colors[index], 0.6, 6)
		local bulb = kit.Blob(body, pt[1], pt[2] + 3, 5, 6.5, colors[index], { Z = 7, Thickness = 1 })
		table.insert(bulbs, bulb)
		table.insert(bulbs, halo)
	end
	-- drapeau
	kit.Line(body, 50, 25, 50, 6, 1.8, C.WoodDark, 0, 3)
	local flagPivot, flag = rig(body, kit, 50, 7, 3)
	kit.Part(flag, 50, 5, 15, 10, C.Mint, { Radius = 2, Z = 1 })
	kit.Heart(flag, 57.5, 10, 6, C.White, 0, 2)
	-- coussins
	kit.Blob(body, 16, 92, 24, 13, C.Lilac, { Z = 8, Shine = true })
	kit.Blob(body, 84, 93, 22, 11, C.Butter, { Z = 8, Shine = true })
	kit.Animate(flagPivot, "Sway", 7, 0.9, 0.2)
	return { Glow = C.Butter, Bulbs = bulbs }
end

-- Château de poupée : donjon rose, 2 tourelles à toit pointu, drapeaux, porte en arche
Art.DollCastle = function(body, kit, _item)
	local C = kit.C
	local wall = Color3.fromRGB(255, 214, 230)
	local tower = Color3.fromRGB(236, 224, 255)
	-- tour centrale (derrière)
	kit.Part(body, 39, 22, 22, 24, wall, { Radius = 3, Z = 1 })
	kit.Triangle(body, 50, 4, 28, 20, C.Pink, 1, 0, 8)
	kit.Circle(body, 50, 4, 5, 5, C.Gold, 0, 2)
	-- donjon
	for index = 0, 3 do
		kit.Part(body, 26 + index * 13, 34, 9, 10, wall, { Radius = 2, Z = 2 })
	end
	local keep = kit.Part(body, 24, 40, 52, 58, wall, { Radius = 4, Z = 3, Shade = 0.1 })
	local door = kit.Part(keep, 17, 34, 18, 24, C.WoodDark, { Radius = 9, Z = 2 })
	kit.Circle(door, 13, 14, 3, 3, C.Gold, 0, 2)
	kit.Heart(keep, 26, 26, 8, C.Heart, 0, 2)
	local window = kit.Part(keep, 19, 7, 14, 12, C.Sky, { Radius = 6, Z = 2, Thickness = 1.3 })
	kit.Box(window, 6.3, 0, 1.4, 12, C.White, 0.2, 2)
	-- tourelles
	for _, s in ipairs({ { 6, 1 }, { 72, -1 } }) do
		local x = s[1]
		local t = kit.Part(body, x, 38, 22, 60, tower, { Radius = 4, Z = 4, Shine = true })
		kit.Part(t, 7, 12, 8, 13, C.Sky, { Radius = 4, Z = 2, Thickness = 1.2 })
		kit.Part(t, 7, 34, 8, 11, C.Sky, { Radius = 4, Z = 2, Thickness = 1.2 })
		kit.Triangle(body, x + 11, 12, 30, 26, C.Pink, 5, 0, 10)
		kit.Part(body, x - 3, 35, 28, 6, C.PinkDeep, { Radius = 3, Z = 6 })
		kit.Line(body, x + 11, 12, x + 11, 2, 1.4, C.GreyDark, 0, 5)
		local fp, flag = rig(body, kit, x + 11, 3, 6)
		kit.Part(flag, x + 11, 1, 10, 6, if x < 50 then C.Mint else C.Butter, { Radius = 1.5, Z = 1 })
		kit.Animate(fp, "Sway", 6, 0.9, x * 0.1)
	end
	kit.Part(body, 20, 94, 60, 5, C.Leaf, { Radius = 2.5, Z = 7 })
	for _, x in ipairs({ 22, 36, 64, 78 }) do
		kit.Circle(body, x, 94, 5, 5, if x < 50 then C.Pink else C.Butter, 0, 8)
	end
	return nil
end

-- Cheval de manège : cheval blanc sur une barre torsadée qui monte et descend
Art.CarouselHorse = function(body, kit, _item)
	local C = kit.C
	-- socle et toit
	kit.Part(body, 22, 86, 56, 12, C.PinkSoft, { Radius = 5, Z = 5, Shine = true })
	kit.Part(body, 20, 84, 60, 5, C.Gold, { Radius = 2.5, Z = 6 })
	for _, x in ipairs({ 32, 50, 68 }) do
		kit.Circle(body, x, 92, 4, 4, C.Heart, 0, 6)
	end
	kit.Part(body, 33, 0, 34, 7, C.Pink, { Radius = 3.5, Z = 5 })
	kit.Circle(body, 50, -2, 7, 7, C.Gold, 0, 4)
	-- barre torsadée
	local pole = kit.Part(body, 47.5, 5, 5, 81, C.Gold, { Radius = 2, Z = 4, Shade = false })
	pole.ClipsDescendants = true
	for index = 0, 9 do
		kit.Box(pole, -2, 2 + index * 8, 9, 2.6, C.White, 0.1, 2).Rotation = -30
	end
	-- cheval
	local g = kit.Group(body, 0, 0, 100, 100, 3)
	horse(g, kit, {
		X = 46,
		Y = 50,
		K = 1.1,
		Coat = Color3.fromRGB(255, 252, 250),
		Mane = { C.Lilac, C.Pink, C.Sky },
		Saddle = C.Heart,
		Blanket = C.Butter,
		Hoof = C.Gold,
		Legs = {
			{ -12, 6, -24, 20, -34, 24, true },
			{ 12, 6, 24, 10, 26, 22, true },
			{ -16, 6, -26, 18, -36, 20 },
			{ 16, 6, 28, 14, 24, 25 },
		},
	})
	kit.Heart(g, 41, 44, 7, C.White, 0, 7)
	kit.Animate(g, "Bob", 3, 0.6, 0.4)
	return nil
end

-- Fusée jouet : nez rose, hublot avec visage, ailerons, flamme qui vacille
Art.ToyRocket = function(body, kit, _item)
	local C = kit.C
	local flame = kit.Blob(body, 50, 88, 20, 22, C.Orange, { Z = 1, Outline = false, Shade = false })
	kit.Fade(flame, 0, 0.3, 90)
	local core = kit.Blob(body, 50, 86, 11, 14, C.Butter, { Z = 2, Outline = false, Shade = false })
	kit.Animate(flame, "Flicker", 0.35, 1, 0.1)
	kit.Animate(core, "Flicker", 0.3, 1.2, 0.8)
	local g = kit.Group(body, 0, 0, 100, 100, 3)
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(g, 50 + side * 18 - 6, 56, 12, 26, C.Pink, { Radius = 5, Z = 1, Rotation = side * 22 })
	end
	kit.Part(g, 40, 78, 20, 7, C.GreyDark, { Radius = 3, Z = 1 })
	kit.Part(g, 32, 10, 36, 72, C.White, { Radius = -1, Z = 2, Shine = true, Shade = 0.1 })
	local nose = kit.Group(g, 29, 8, 42, 26, 3, true)
	kit.Part(nose, 3, 2, 36, 72, C.Pink, { Radius = -1, Z = 1, Shade = 0.1 })
	kit.Part(g, 31, 32, 38, 5, C.PinkDeep, { Radius = 2.5, Z = 4 })
	kit.Blob(g, 50, 51, 22, 22, C.Grey, { Z = 4 })
	local glass = kit.Blob(g, 50, 51, 16, 16, C.Sky, { Z = 5, Thickness = 1.2 })
	kit.Face(glass, 8, 8.5, 12, { Eyes = "happy", Mouth = "smile", Z = 3 })
	kit.Shine(glass, 3, 2.5, 5, 3, 4)
	kit.Heart(g, 50, 68, 8, C.Heart, 0, 4)
	kit.Part(g, 47, 70, 6, 14, C.PinkDeep, { Radius = 3, Z = 5 })
	local sparkles = { kit.Sparkle(body, 16, 22, 10, C.Butter, 0, 6), kit.Sparkle(body, 84, 36, 8, C.Lilac, 0, 6), kit.Sparkle(body, 20, 66, 6, C.Sky, 0, 6) }
	for index, s in ipairs(sparkles) do
		kit.Animate(s, "Bob", 2, 0.7, index * 1.3)
	end
	kit.Animate(g, "Bob", 1.5, 0.9, 0.2)
	return { Glow = C.Orange }
end

-- Grande roue : roue qui tourne (nacelles qui restent droites), lumières, pied en A
Art.FerrisWheel = function(body, kit, _item)
	local C = kit.C
	local cx, cy, radius = 50, 42, 34
	kit.Part(body, 14, 90, 72, 9, C.Pink, { Radius = 4, Z = 1, Shine = true })
	local wheel = kit.Pivot(body, cx, cy, 2)
	kit.Part(wheel, -radius, -radius, radius * 2, radius * 2, C.White, { Radius = -1, T = 1, Outline = C.Pink, Thickness = 3.4, Shade = false, Z = 2 })
	kit.Part(wheel, -22, -22, 44, 44, C.White, { Radius = -1, T = 1, Outline = C.PinkSoft, Thickness = 2, Shade = false, Z = 2 })
	for _, a in ipairs({ 0, 45, 90, 135 }) do
		local r = math.rad(a)
		kit.Line(wheel, -math.cos(r) * radius, -math.sin(r) * radius, math.cos(r) * radius, math.sin(r) * radius, 1.6, C.Lilac, 0.1, 1)
	end
	local bulbs = {}
	local colors = { C.Pink, C.Mint, C.Butter, C.Sky, C.Lilac, C.Peach }
	for index = 0, 5 do
		local r = math.rad(index * 60 + 30)
		local bx, by = math.cos(r) * radius, math.sin(r) * radius
		local halo = kit.Circle(wheel, bx, by, 9, 9, C.Butter, 0.6, 3)
		local bulb = kit.Circle(wheel, bx, by, 4.5, 4.5, C.Butter, 0, 4)
		table.insert(bulbs, bulb)
		table.insert(bulbs, halo)
	end
	-- pied en A (devant la roue)
	kit.Line(body, cx, cy, 24, 92, 5, C.LilacSoft, 0, 3)
	kit.Line(body, cx, cy, 76, 92, 5, C.LilacSoft, 0, 3)
	kit.Line(body, 33, 72, 67, 72, 3, C.LilacSoft, 0, 3)
	for index = 0, 5 do
		local r = math.rad(index * 60 + 90)
		local gp = kit.Pivot(wheel, math.cos(r) * radius, math.sin(r) * radius, 5)
		local color = colors[index + 1]
		kit.Line(gp, 0, 0, 0, 3, 1.4, C.GreyDark, 0, 1)
		kit.Part(gp, -7, 3, 14, 12, color, { Radius = 4, Z = 2 })
		kit.Part(gp, -8, 1, 16, 5, kit.Darken(color, 0.12), { Radius = 2.5, Z = 3 })
		kit.Part(gp, -4, 7, 8, 4, C.Glass, { Radius = 2, Z = 3, Outline = false })
		kit.Animate(gp, "Spin", 0, -0.04, 0)
	end
	local hub = kit.Blob(body, cx, cy, 13, 13, C.Butter, { Z = 6 })
	kit.Heart(hub, 6.5, 6.5, 7, C.Heart, 0, 2)
	kit.Animate(wheel, "Spin", 0, 0.04, 0)
	return { Glow = C.Butter, Bulbs = bulbs }
end

return Art
