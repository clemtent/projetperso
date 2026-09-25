--[[
	Windows (ModuleScript) — dessins des fenêtres 🪟
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Windows
	Contrat : voir HouseArt (boîte 100 x 100, objets muraux centrés).
	Chaque fenêtre = cadre + rebord (+ rideaux) et une VUE dessinée dans un
	groupe découpé (clip) : nuages, pluie, coucher de soleil, océan, ville...
]]

local Art = {}

local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- Aides partagées
----------------------------------------------------------------------

-- Couleur prolongée au-delà de `bottom` (pour un dégradé plus haut que la vitre)
local function extend(top: Color3, bottom: Color3, k: number): Color3
	return Color3.new(
		math.clamp(top.R + (bottom.R - top.R) * k, 0, 1),
		math.clamp(top.G + (bottom.G - top.G) * k, 0, 1),
		math.clamp(top.B + (bottom.B - top.B) * k, 0, 1)
	)
end

-- Rideaux noués de part et d'autre (tringle + 2 pans + embrasses)
local function curtains(body, kit, x, y, w, h, fw, color, tie, rod)
	local rodY = y - fw - 5
	local left, right = x - fw - 10, x + w + fw + 10
	kit.Part(body, left, rodY, right - left, 4, rod, { Radius = -1, Z = 9, Shade = false })
	for _, px in ipairs({ left, right }) do
		kit.Circle(body, px, rodY + 2, 7, 7, rod, 0, 9)
	end
	local tieY = y + h * 0.56
	local bottom = y + h + 4
	for _, side in ipairs({ -1, 1 }) do
		local cx = if side < 0 then x - fw + 5 else x + w + fw - 5
		kit.Part(body, cx - 9, rodY + 1, 18, tieY - rodY + 2, color, { Radius = 6, Z = 10, Shade = 0.08 })
		kit.Line(body, cx - side * 2, rodY + 5, cx - side * 1, tieY - 3, 1.4, kit.Darken(color, 0.12), 0.3, 11)
		kit.Blob(body, cx + side * 3, (tieY + bottom) / 2, 22, bottom - tieY + 4, color, { Z = 11, Shade = 0.1 })
		kit.Part(body, cx - 11, tieY - 3, 22, 6, tie, { Radius = -1, Z = 12 })
		kit.Circle(body, cx + side * 9, tieY, 6, 6, tie, 0, 12)
	end
end

-- Fenêtre : cadre (rectangle ou arche), vitre avec VUE découpée, reflets,
-- croisillon, rebord et rideaux. Renvoie la vue (coordonnées locales w x h).
-- o = { X, Y, W, H, Arch, Radius, Frame, Border, Sky = { haut, bas }, Cross,
--       Curtain, Tie, Rod, Sill }
local function window(body, kit, o)
	local C = kit.C
	local x, y, w, h = o.X or 22, o.Y or 16, o.W or 56, o.H or 58
	local arch = o.Arch == true
	local r = if arch then w / 2 else (o.Radius or 5)
	local fw = o.Border or 6
	local fc = o.Frame or C.Cream
	local extra = if arch then w else 0
	-- cadre (le bas d'une arche est caché sous le rebord)
	local frameClip = kit.Group(body, x - fw - 3, y - fw - 3, w + fw * 2 + 6, h + fw + 6, 2, true)
	kit.Part(frameClip, 3, 3, w + fw * 2, h + fw * 2 + extra, fc, { Radius = r + fw, Shine = false, Shade = 0.1 })
	-- vue
	local view = kit.Group(body, x, y, w, h, 3, true)
	local sky = o.Sky or { C.Sky, C.PinkMist }
	local back = kit.Box(view, 0, 0, w, h + extra, WHITE, 0, 1)
	kit.Round(back, r)
	kit.Gradient(back, sky[1], extend(sky[1], sky[2], (h + extra) / h), 90)
	-- bord intérieur (cache les coins de la découpe)
	local rimClip = kit.Group(body, x - 4, y - 4, w + 8, h + 4, 5, true)
	local rim = kit.Box(rimClip, 4, 4, w, h + extra, WHITE, 1, 1)
	kit.Round(rim, r)
	kit.Stroke(rim, kit.Darken(fc, 0.12), 2.6, 0)
	-- croisillon
	local cross = o.Cross or "+"
	if cross == "+" or cross == "|" then
		kit.Part(body, x + w / 2 - 2, y, 4, h, fc, { Radius = 1, Z = 6, Thickness = 1.2, Shade = false })
	end
	if cross == "+" or cross == "-" then
		kit.Part(body, x, y + h * 0.5 - 2, w, 4, fc, { Radius = 1, Z = 6, Thickness = 1.2, Shade = false })
	end
	-- reflets sur la vitre
	kit.Line(body, x + 5, y + h * 0.36, x + w * 0.2, y + h * 0.36 - w * 0.15, 3, WHITE, 0.5, 7)
	kit.Line(body, x + 6, y + h * 0.36 + 7, x + w * 0.3, y + h * 0.36 + 7 - w * 0.24, 1.6, WHITE, 0.62, 7)
	-- rebord
	if o.Sill ~= false then
		local sillColor = o.SillColor or kit.Lighten(fc, 0.15)
		kit.Part(body, x - fw - 7, y + h + 1, w + fw * 2 + 14, 8, sillColor, { Radius = 3, Z = 8, Shine = true })
		kit.Part(body, x - fw - 3, y + h + 8, w + fw * 2 + 6, 4, kit.Darken(sillColor, 0.1), { Radius = 2, Z = 7 })
	end
	if o.Curtain then
		curtains(body, kit, x, y, w, h, fw, o.Curtain, o.Tie or C.PinkDeep, o.Rod or C.WoodDark)
	end
	return view, w, h
end

-- Petits oiseaux en "v"
local function bird(parent, kit, cx, cy, size, color)
	kit.Line(parent, cx - size, cy - size * 0.5, cx, cy, 1.4, color, 0, 4)
	kit.Line(parent, cx, cy, cx + size, cy - size * 0.5, 1.4, color, 0, 4)
end

-- Montagne arrondie (carré tourné à 45°) avec sa pointe en (px, py)
local function mountain(parent, kit, px, py, side, color, snow, z)
	local diag = side / math.sqrt(2)
	kit.Part(parent, px - side / 2, py + diag - side / 2, side, side, color, { Rotation = 45, Radius = 5, Z = z, Shade = false })
	if snow then
		local s = side * 0.36
		local d = s / math.sqrt(2)
		kit.Part(parent, px - s / 2, py + d - s / 2 + 0.4, s, s, WHITE, { Rotation = 45, Radius = 4, Z = z + 1, Outline = false, Shade = false })
		for _, side2 in ipairs({ -1, 1 }) do
			kit.Circle(parent, px + side2 * d * 0.55, py + d * 1.25, d * 0.8, d * 0.7, WHITE, 0, z + 1)
		end
	end
end

-- Petite étoile scintillante (losange) dans le ciel
local function twinkle(parent, kit, cx, cy, size, color, phase)
	local dot = kit.Diamond(parent, cx, cy, size, color, 0, 3)
	kit.Animate(dot, "Pulse", 0.7, 1.2, phase)
	return dot
end

-- Fait "pulser" tous les morceaux d'un conteneur
local function pulseAll(kit, holder, amp, speed, phase)
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("GuiObject") then
			kit.Animate(child, "Pulse", amp, speed, phase)
		end
	end
end

----------------------------------------------------------------------
-- Dessins
----------------------------------------------------------------------

-- Fenêtre à rideaux : ciel bleu, soleil, nuages, collines ; pot de fleurs
Art.CurtainWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		Frame = C.Cream,
		Sky = { Color3.fromRGB(140, 205, 255), Color3.fromRGB(225, 242, 255) },
		Curtain = Color3.fromRGB(255, 170, 200),
		Tie = C.PinkDeep,
	})
	kit.Circle(view, w - 12, 12, 20, 20, C.Butter, 0.5, 2)
	kit.Circle(view, w - 12, 12, 13, 13, C.Butter, 0, 2)
	local c1 = kit.Cloud(view, 16, 22, 22, WHITE, 0, 3)
	kit.Animate(c1, "Drift", 3, 0.3, 0)
	local c2 = kit.Cloud(view, 40, 32, 16, WHITE, 0.1, 3)
	kit.Animate(c2, "Drift", 2.5, 0.4, 2)
	kit.Blob(view, 14, h + 4, 50, 26, C.Leaf, { Z = 4, Shade = false, Thickness = 1.2 })
	kit.Blob(view, w - 10, h + 6, 56, 26, C.Mint, { Z = 4, Shade = false, Thickness = 1.2 })
	-- pot de fleurs sur le rebord
	kit.Part(body, 62, 66, 12, 12, C.Peach, { Radius = 3, Z = 13 })
	kit.Line(body, 68, 66, 68, 60, 1.4, C.LeafDark, 0, 12)
	kit.Circle(body, 68, 58, 8, 8, C.Pink, 0, 13)
	kit.Circle(body, 68, 58, 3, 3, C.Butter, 0, 14)
	return { WallShadow = Vector2.new(0.78, 0.78) }
end

-- Fenêtre nuageuse (arche menthe) : gros nuage souriant et nuages qui passent
Art.CloudyWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		Arch = true,
		Frame = C.MintSoft,
		Sky = { Color3.fromRGB(120, 195, 255), Color3.fromRGB(210, 238, 255) },
		Curtain = C.Lilac,
		Tie = C.Butter,
		Rod = C.Purple,
	})
	local big = kit.Cloud(view, w / 2, h * 0.64, 40, WHITE, 0, 3)
	kit.Animate(big, "Drift", 2, 0.25, 0)
	kit.Face(big, 18, 16, 16, { Eyes = "happy", Mouth = "smile", Z = 3 })
	local small = kit.Cloud(view, 14, h * 0.34, 18, WHITE, 0.05, 2)
	kit.Animate(small, "Drift", 4, 0.3, 1.5)
	local small2 = kit.Cloud(view, w - 12, h * 0.9, 22, WHITE, 0.05, 2)
	kit.Animate(small2, "Drift", 3, 0.35, 3)
	return { WallShadow = Vector2.new(0.78, 0.8) }
end

-- Fenêtre pluvieuse : nuage gris qui boude, pluie, gouttes sur la vitre
Art.RainyWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		Frame = Color3.fromRGB(255, 232, 160),
		Sky = { Color3.fromRGB(125, 145, 185), Color3.fromRGB(195, 208, 230) },
		Curtain = Color3.fromRGB(150, 200, 255),
		Tie = C.Yellow,
		Rod = C.Navy,
	})
	local rain = kit.Group(view, 0, 0, w, h, 2)
	for index = 0, 9 do
		local rx = 4 + (index * 37) % w
		local ry = 18 + (index * 23) % (h - 22)
		kit.Line(rain, rx, ry, rx - 2.5, ry + 7, 1.6, WHITE, 0.3, 1)
	end
	kit.Animate(rain, "Bob", 2.5, 2.2, 0)
	local cloud = kit.Cloud(view, w / 2, 26, 44, Color3.fromRGB(215, 212, 232), 0, 3)
	kit.Face(cloud, 22, 18, 16, { Eyes = "closed", Mouth = "o", Z = 3 })
	kit.Animate(cloud, "Drift", 2, 0.3, 0.4)
	kit.Blob(view, w / 2, h + 3, w + 10, 14, Color3.fromRGB(150, 165, 200), { Z = 2, Outline = false, Shade = false })
	-- gouttes sur la vitre
	for _, d in ipairs({ { 30, 58, 3 }, { 36, 70, 4 }, { 64, 50, 3 }, { 70, 64, 4 } }) do
		kit.Circle(body, d[1], d[2], d[3], d[3] * 1.3, WHITE, 0.35, 7)
	end
	return { WallShadow = Vector2.new(0.78, 0.78) }
end

-- Coucher de soleil (arche pêche) : ciel rose-orangé, soleil sur la mer, oiseaux
Art.SunsetWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		Arch = true,
		Frame = Color3.fromRGB(255, 214, 190),
		Sky = { Color3.fromRGB(190, 150, 235), Color3.fromRGB(255, 180, 150) },
		Curtain = C.Cream,
		Tie = C.Orange,
		Rod = C.WoodDark,
		Cross = "|",
	})
	local horizon = h * 0.64
	local sun = kit.Circle(view, w / 2, horizon, 30, 30, C.Butter, 0, 2)
	kit.Gradient(sun, WHITE, Color3.fromRGB(255, 200, 150), 90)
	kit.Face(sun, 15, 9, 14, { Eyes = "happy", Mouth = "none", Z = 2 })
	local sea = kit.Box(view, 0, horizon, w, h - horizon, Color3.fromRGB(170, 120, 210), 0, 3)
	kit.Gradient(sea, WHITE, Color3.fromRGB(180, 170, 220), 90)
	for index, s in ipairs({ { 22, 4 }, { 14, 9 }, { 8, 14 } }) do
		local glint = kit.Box(view, w / 2 - s[1] / 2, horizon + s[2], s[1], 2.4, C.Butter, 0.15, 4)
		kit.Round(glint)
		kit.Animate(glint, "Pulse", 0.5, 1, index)
	end
	bird(view, kit, 16, 16, 4, C.Purple)
	bird(view, kit, 24, 22, 3, C.Purple)
	return { WallShadow = Vector2.new(0.78, 0.8) }
end

-- Hublot : anneau doré à rivets, océan, poissons, algues et bulles
Art.PortholeWindow = function(body, kit, _item)
	local C = kit.C
	local brass = Color3.fromRGB(245, 205, 120)
	local cx, cy, d = 50, 50, 60
	kit.Circle(body, cx, cy, d + 30, d + 30, kit.OutlineOf(brass), 0, 1)
	local view = kit.Group(body, cx - d / 2, cy - d / 2, d, d, 2, true)
	local sea = kit.Circle(view, d / 2, d / 2, d, d, WHITE, 0, 1)
	kit.Gradient(sea, Color3.fromRGB(150, 220, 255), Color3.fromRGB(70, 140, 220), 90)
	kit.Line(view, 14, -4, 30, 40, 5, WHITE, 0.8, 2)
	kit.Line(view, 30, -4, 44, 34, 3, WHITE, 0.82, 2)
	local sand = kit.Group(view, 0, 46, d, 14, 3, true)
	kit.Circle(sand, d / 2, d / 2 - 46, d, d, Color3.fromRGB(255, 225, 170), 0, 1)
	kit.Circle(sand, 40, 5, 7, 4, C.Pink, 0, 2) -- coquillage
	for index, s in ipairs({ { 12, 36, 18 }, { 18, 40, 13 }, { 50, 38, 16 } }) do
		local weed = kit.Part(view, s[1] - 2.5, s[2], 5, s[3], C.Leaf, { Radius = -1, Z = 2, Thickness = 1.2 })
		kit.Animate(weed, "Sway", 8, 0.8, index * 1.3)
	end
	local function fish(fx, fy, size, color, flip, phase)
		local g = kit.Group(view, 0, 0, d, d, 4)
		local dir = if flip then -1 else 1
		kit.Diamond(g, fx - dir * size * 0.55, fy, size * 0.5, kit.Darken(color, 0.08), 0, 1)
		kit.Blob(g, fx, fy, size, size * 0.66, color, { Z = 2, Thickness = 1.2 })
		kit.Circle(g, fx + dir * size * 0.22, fy - size * 0.06, size * 0.16, size * 0.16, C.Ink, 0, 3)
		kit.Circle(g, fx + dir * size * 0.08, fy + size * 0.12, size * 0.16, size * 0.1, C.Blush, 0.3, 3)
		kit.Animate(g, "Drift", 4, 0.5, phase)
	end
	fish(24, 20, 15, Color3.fromRGB(255, 160, 190), false, 0)
	fish(42, 34, 11, C.Butter, true, 2)
	for index, b in ipairs({ { 46, 14, 4 }, { 50, 8, 3 }, { 16, 30, 3 } }) do
		local bubble = kit.Circle(view, b[1], b[2], b[3], b[3], WHITE, 0.6, 5)
		kit.Stroke(bubble, WHITE, 1, 0.2)
		kit.Animate(bubble, "Bob", 2, 0.9, index)
	end
	-- anneau doré (recouvre les coins de la découpe) + rivets
	local ring = kit.Circle(body, cx, cy, d, d, brass, 1, 4)
	kit.Stroke(ring, brass, 13, 0)
	local lip = kit.Circle(body, cx, cy, d, d, brass, 1, 5)
	kit.Stroke(lip, kit.Darken(brass, 0.15), 2.4, 0)
	for index = 0, 7 do
		local a = math.rad(index * 45 + 22.5)
		kit.Circle(body, cx + math.sin(a) * 37, cy - math.cos(a) * 37, 5, 5, kit.Lighten(brass, 0.4), 0, 6)
	end
	kit.Line(body, 30, 38, 38, 28, 3, WHITE, 0.5, 7)
	return { WallShadow = Vector2.new(0.86, 0.86) }
end

-- Ville la nuit : ciel violet, lune endormie, immeubles aux fenêtres allumées
Art.CityNightWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		Frame = C.LilacSoft,
		Sky = { Color3.fromRGB(45, 45, 100), Color3.fromRGB(130, 95, 180) },
		Curtain = Color3.fromRGB(160, 125, 225),
		Tie = C.Butter,
		Rod = C.Navy,
	})
	local moon = kit.Circle(view, w - 13, 13, 14, 14, C.Butter, 0, 2)
	kit.Face(moon, 7, 7, 10, { Eyes = "closed", Mouth = "none", Z = 2 })
	for index, s in ipairs({ { 8, 8 }, { 22, 14 }, { 34, 6 }, { 18, 26 } }) do
		twinkle(view, kit, s[1], s[2], 2.6, WHITE, index)
	end
	local towers = {
		{ 0, 30, 12, Color3.fromRGB(95, 80, 160) },
		{ 10, 20, 12, Color3.fromRGB(120, 95, 185) },
		{ 21, 34, 11, Color3.fromRGB(85, 70, 145) },
		{ 31, 24, 13, Color3.fromRGB(110, 90, 175) },
		{ 43, 32, 14, Color3.fromRGB(90, 75, 155) },
	}
	for index, t in ipairs(towers) do
		kit.Part(view, t[1], t[2], t[3], h - t[2] + 4, t[4], { Radius = 2, Z = 3 + index % 2, Thickness = 1.2, Shade = false })
	end
	local lit = { { 3, 36 }, { 3, 44 }, { 14, 26 }, { 14, 34 }, { 25, 40 }, { 35, 30 }, { 35, 38 }, { 47, 38 }, { 47, 46 }, { 25, 48 } }
	for index, p in ipairs(lit) do
		local win = kit.Box(view, p[1], p[2], 3.4, 3.4, C.Butter, 0, 6)
		kit.Round(win, 1)
		if index % 3 == 0 then
			kit.Animate(win, "Pulse", 0.8, 0.5, index)
		end
	end
	return { WallShadow = Vector2.new(0.78, 0.78) }
end

-- Fenêtre sakura (arche en bois) : branche fleurie, mont Fuji, pétales qui tombent
Art.SakuraWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		Arch = true,
		Frame = C.WoodLight,
		Sky = { Color3.fromRGB(190, 225, 255), Color3.fromRGB(255, 232, 244) },
		Curtain = C.Cream,
		Tie = C.Pink,
		Rod = C.WoodDark,
		Cross = "|",
	})
	mountain(view, kit, w * 0.62, h * 0.52, 34, Color3.fromRGB(200, 190, 240), true, 2)
	kit.Blob(view, w / 2, h + 4, w + 20, 18, Color3.fromRGB(255, 200, 225), { Z = 4, Shade = false, Thickness = 1.2 })
	local wood = C.WoodDark
	kit.Line(view, -4, 22, 26, 28, 3.4, wood, 0, 5)
	kit.Line(view, 26, 28, 46, 22, 2.6, wood, 0, 5)
	kit.Line(view, 14, 25, 24, 12, 2, wood, 0, 5)
	local blossom = Color3.fromRGB(255, 180, 210)
	for _, b in ipairs({ { 24, 11, 9 }, { 46, 21, 9 }, { 34, 27, 8 }, { 8, 23, 8 }, { 17, 33, 7 }, { 40, 15, 7 } }) do
		kit.Circle(view, b[1], b[2], b[3], b[3], blossom, 0, 6)
		kit.Circle(view, b[1], b[2], b[3] * 0.34, b[3] * 0.34, C.PinkDeep, 0, 7)
	end
	for index, p in ipairs({ { 12, 44 }, { 30, 40 }, { 48, 48 }, { 38, 54 } }) do
		local petal = kit.Blob(view, p[1], p[2], 4.5, 3, blossom, { Z = 6, Outline = false, Shade = false, Rotation = index * 40 })
		kit.Animate(petal, if index % 2 == 0 then "Drift" else "Bob", 2.5, 0.6, index * 1.4)
	end
	return { WallShadow = Vector2.new(0.78, 0.8) }
end

-- Vue montagne (large cadre en bois) : sommets enneigés, sapins, prairie
Art.MountainWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		X = 14,
		Y = 18,
		W = 72,
		H = 54,
		Frame = C.Wood,
		Border = 6,
		Sky = { Color3.fromRGB(130, 195, 255), Color3.fromRGB(230, 245, 255) },
		Curtain = Color3.fromRGB(245, 150, 150),
		Tie = C.Cream,
		Rod = C.WoodDark,
	})
	local cloud = kit.Cloud(view, 58, 16, 18, WHITE, 0, 5)
	kit.Animate(cloud, "Drift", 4, 0.25, 0)
	mountain(view, kit, 22, 12, 44, Color3.fromRGB(180, 170, 230), true, 2)
	mountain(view, kit, 50, 20, 40, Color3.fromRGB(150, 160, 220), true, 3)
	kit.Blob(view, w * 0.3, h + 6, w * 1.1, 26, C.Leaf, { Z = 6, Shade = false, Thickness = 1.2 })
	kit.Blob(view, w * 0.85, h + 8, w * 0.7, 30, C.Green, { Z = 6, Shade = false, Thickness = 1.2 })
	for _, t in ipairs({ { 10, 38, 1 }, { 60, 36, 1.2 }, { 68, 42, 0.9 } }) do
		local s = t[3]
		kit.Box(view, t[1] - 1, t[2] + 11 * s, 2.4, 4 * s, C.WoodDark, 0, 7)
		kit.Triangle(view, t[1], t[2], 11 * s, 13 * s, C.LeafDark, 8, 0, 5)
	end
	bird(view, kit, 38, 10, 3, C.Navy)
	return { WallShadow = Vector2.new(0.86, 0.72) }
end

-- Vue plage (grand cadre blanc) : soleil, mer qui scintille, sable, palmier, parasol
Art.BeachWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		X = 12,
		Y = 16,
		W = 76,
		H = 58,
		Frame = Color3.fromRGB(235, 248, 255),
		Sky = { Color3.fromRGB(110, 200, 255), Color3.fromRGB(215, 242, 255) },
		Curtain = Color3.fromRGB(140, 215, 235),
		Tie = C.Butter,
		Rod = C.Blue,
	})
	local halo = kit.Circle(view, 14, 13, 22, 22, C.Butter, 0.55, 2)
	kit.Animate(halo, "Pulse", 0.3, 0.6, 0)
	kit.Circle(view, 14, 13, 14, 14, C.Yellow, 0, 2)
	local cloud = kit.Cloud(view, 44, 17, 18, WHITE, 0, 2)
	kit.Animate(cloud, "Drift", 4, 0.25, 1)
	bird(view, kit, 30, 10, 3, C.Navy)
	local seaY = h * 0.5
	local sea = kit.Box(view, 0, seaY, w, h - seaY, C.Blue, 0, 3)
	kit.Gradient(sea, Color3.fromRGB(140, 200, 250), WHITE, 90)
	for index, wv in ipairs({ { 10, 4, 14 }, { 40, 7, 16 }, { 24, 11, 12 } }) do
		local wave = kit.Box(view, wv[1], seaY + wv[2], wv[3], 2, WHITE, 0.3, 4)
		kit.Round(wave)
		kit.Animate(wave, "Drift", 3, 0.5, index * 1.7)
	end
	kit.Blob(view, w * 0.45, h + 8, w * 1.3, 30, Color3.fromRGB(255, 228, 170), { Z = 5, Shade = false, Thickness = 1.2 })
	-- parasol
	kit.Line(view, 24, 36, 26, 56, 1.6, C.WoodDark, 0, 6)
	local umbrella = kit.Group(view, 12, 29, 26, 8, 7, true)
	kit.Circle(umbrella, 13, 8, 26, 16, C.Pink, 0, 1)
	kit.Box(umbrella, 10, 0, 6, 8, WHITE, 0, 2)
	kit.Circle(view, 40, 52, 4, 3, C.Red, 0, 6) -- crabe / coquillage
	-- palmier
	local trunk = { { 62, 58 }, { 62, 48 }, { 60, 38 }, { 56, 28 } }
	for index = 1, #trunk - 1 do
		local a, b = trunk[index], trunk[index + 1]
		kit.Line(view, a[1], a[2], b[1], b[2], 5, C.WoodLight, 0, 6 + index)
	end
	for index, a in ipairs({ -150, -110, -60, -20, 25 }) do
		local rad = math.rad(a)
		local len = 16
		kit.Part(view, 56 + math.cos(rad) * len * 0.5 - len / 2, 28 + math.sin(rad) * len * 0.5 - 3.5, len, 7, C.Leaf, {
			Radius = -1,
			Z = 10 + index % 2,
			Rotation = a,
			Thickness = 1.2,
			Shade = false,
		})
	end
	kit.Circle(view, 55, 31, 4, 4, C.Brown, 0, 12)
	kit.Circle(view, 59, 31, 4, 4, C.WoodDark, 0, 12)
	return { WallShadow = Vector2.new(0.88, 0.8) }
end

-- Étoile filante (arche lilas) : nuit étoilée, lune, colline et maisonnette
Art.ShootingStarWindow = function(body, kit, _item)
	local C = kit.C
	local view, w, h = window(body, kit, {
		Arch = true,
		Frame = C.Lilac,
		Sky = { Color3.fromRGB(30, 28, 80), Color3.fromRGB(120, 85, 180) },
		Curtain = Color3.fromRGB(110, 90, 185),
		Tie = C.Butter,
		Rod = C.Navy,
		Cross = "|",
	})
	kit.Circle(view, 40, 16, 12, 12, C.Butter, 0, 2)
	kit.Circle(view, 44, 13, 11, 11, Color3.fromRGB(34, 32, 86), 0, 2)
	for index, s in ipairs({ { 12, 14 }, { 26, 8 }, { 48, 28 }, { 8, 34 }, { 30, 30 } }) do
		twinkle(view, kit, s[1], s[2], 2.6, if index % 2 == 0 then C.Butter else WHITE, index * 0.8)
	end
	-- étoile filante
	local shooter = kit.Group(view, 0, 0, w, h, 5)
	local tail = kit.Line(shooter, 4, 16, 26, 30, 4, C.Lilac, 0, 1)
	kit.Fade(tail, 1, 0.2, 0)
	local core = kit.Line(shooter, 10, 20, 26, 30, 1.6, WHITE, 0, 2)
	kit.Fade(core, 1, 0, 0)
	kit.Sparkle(shooter, 27, 31, 12, C.Butter, 0, 3)
	kit.Circle(shooter, 27, 31, 4, 4, WHITE, 0, 4)
	kit.Animate(shooter, "Drift", 3, 0.6, 0)
	-- colline et maisonnette
	kit.Blob(view, w * 0.3, h + 8, w * 1.1, 30, Color3.fromRGB(70, 60, 130), { Z = 6, Shade = false, Thickness = 1.2 })
	kit.Blob(view, w * 0.9, h + 6, w * 0.7, 22, Color3.fromRGB(90, 75, 150), { Z = 6, Shade = false, Thickness = 1.2 })
	kit.Part(view, 36, 42, 11, 9, C.PinkSoft, { Radius = 1.5, Z = 7, Thickness = 1.2, Shade = false })
	kit.Part(view, 37.3, 34.5, 8.5, 8.5, C.Pink, { Radius = 1.5, Z = 8, Rotation = 45, Thickness = 1.2, Shade = false })
	local lamp = kit.Box(view, 39.5, 44.5, 3.4, 3.4, C.Butter, 0, 9)
	kit.Animate(lamp, "Pulse", 0.4, 0.6, 0)
	return { WallShadow = Vector2.new(0.78, 0.8) }
end

-- Fenêtre galaxie (grande arche dorée) : nébuleuse, galaxie qui tourne, planète
Art.GalaxyWindow = function(body, kit, _item)
	local C = kit.C
	local gold = Color3.fromRGB(245, 205, 110)
	local view, w, h = window(body, kit, {
		Arch = true,
		X = 20,
		Y = 12,
		W = 60,
		H = 64,
		Frame = gold,
		Border = 7,
		Sky = { Color3.fromRGB(35, 20, 80), Color3.fromRGB(150, 80, 190) },
		Curtain = Color3.fromRGB(125, 85, 200),
		Tie = gold,
		Rod = gold,
		Cross = "none",
	})
	kit.Circle(view, 16, 26, 36, 30, C.Pink, 0.75, 2)
	kit.Circle(view, 44, 46, 40, 32, C.Sky, 0.8, 2)
	-- galaxie spirale
	local spiral = kit.Pivot(view, 20, 26, 3)
	kit.Blob(spiral, 0, 0, 30, 10, C.LilacSoft, { T = 0.45, Outline = false, Shade = false, Rotation = 25 })
	kit.Blob(spiral, 0, 0, 30, 10, C.PinkSoft, { T = 0.55, Outline = false, Shade = false, Rotation = -35 })
	kit.Circle(spiral, 0, 0, 8, 8, C.Butter, 0, 2)
	kit.Animate(spiral, "Spin", 1, 0.04, 0)
	-- planète à anneau
	local planet = kit.Blob(view, 42, 46, 20, 20, C.Peach, { Z = 4, Shine = true })
	kit.Face(planet, 10, 11, 14, { Eyes = "happy", Mouth = "smile", Z = 3 })
	kit.Blob(view, 42, 47, 34, 8, gold, { T = 1, Z = 5, Outline = C.Butter, Thickness = 2, Shade = false, Rotation = -16 })
	kit.Circle(view, 14, 50, 6, 6, C.MintSoft, 0, 4)
	for index, s in ipairs({ { 36, 10 }, { 50, 22 }, { 8, 40 }, { 28, 58 }, { 54, 60 }, { 30, 38 } }) do
		twinkle(view, kit, s[1], s[2], 2.4, if index % 2 == 0 then C.Butter else WHITE, index * 0.9)
	end
	for index, s in ipairs({ { 44, 16, 9 }, { 10, 60, 7 }, { 24, 8, 6 } }) do
		local sp = kit.Sparkle(view, s[1], s[2], s[3], WHITE, 0, 6)
		pulseAll(kit, sp, 0.7, 1, index * 1.3)
	end
	-- joyau sur le haut de l'arche
	kit.Part(body, 45, 1, 10, 10, C.Pink, { Radius = 2, Z = 8, Rotation = 45, Shine = true })
	return { Glow = Color3.fromRGB(190, 140, 255), WallShadow = Vector2.new(0.8, 0.86) }
end

return Art
