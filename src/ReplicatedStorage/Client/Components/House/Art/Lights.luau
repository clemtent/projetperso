--[[
	Lights (ModuleScript) — dessins des lumières 💡
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Lights
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
	Chaque lumière renvoie Glow (halo dessiné par la pièce, plus fort la nuit).
]]

local Art = {}

local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- Aides partagées
----------------------------------------------------------------------

-- Silhouette : formes collées avec UN seul contour (calque contour dessous,
-- calque couleur dessus). shapes = { { x, y, w, h, rayon? (nil = ovale) } }
local function silhouette(parent, kit, shapes, color, z, thick)
	local holder = kit.Group(parent, 0, 0, 100, 100, z)
	local ink = kit.OutlineOf(color)
	local t = thick or 1.6
	for _, s in ipairs(shapes) do
		local edge = kit.Box(holder, s[1] - t, s[2] - t, s[3] + t * 2, s[4] + t * 2, ink, 0, 1)
		kit.Round(edge, if s[5] then s[5] + t else -1)
	end
	for _, s in ipairs(shapes) do
		local fill = kit.Box(holder, s[1], s[2], s[3], s[4], color, 0, 2)
		kit.Round(fill, s[5] or -1)
	end
	return holder
end

-- Fait "pulser" tous les morceaux d'un conteneur (cœur, étincelle, triangle...)
local function pulseAll(kit, holder, amp, speed, phase)
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("GuiObject") then
			kit.Animate(child, "Pulse", amp, speed, phase)
		end
	end
end

-- Suspension : fil qui monte jusqu'à y = -60, pivot en haut du fil (tout
-- l'objet se balance). Renvoie un calque en coordonnées de la boîte.
local function hang(body, kit, bottom, cordColor, amp, phase)
	local pivot = kit.Pivot(body, 50, -60, 2)
	local layer = kit.Group(pivot, -50, 60, 100, 100, 1)
	kit.Line(layer, 50, -60, 50, bottom, 1.8, cordColor, 0, 1)
	kit.Animate(pivot, "Sway", amp, 0.7, phase)
	return layer
end

-- Petite flamme en goutte (pointe en haut), base en (cx, baseY)
local function flame(parent, kit, cx, baseY, size, z, phase)
	local C = kit.C
	local holder = kit.Group(parent, 0, 0, 100, 100, z)
	local w, h = size * 0.62, size
	local outer = kit.Circle(holder, cx, baseY - w / 2, w, w, C.Orange, 0, 2)
	local tip = kit.Diamond(holder, cx, baseY - w * 0.95, w * 0.62, C.Orange, 0, 2)
	local inner = kit.Circle(holder, cx, baseY - w * 0.42, w * 0.55, w * 0.62, C.Butter, 0, 3)
	local core = kit.Diamond(holder, cx, baseY - w * 0.78, w * 0.34, C.Butter, 0, 3)
	kit.Animate(outer, "Flicker", 0.22, 1, phase)
	kit.Animate(tip, "Flicker", 0.3, 1, phase + 0.4)
	kit.Animate(inner, "Flicker", 0.15, 1.2, phase + 0.8)
	kit.Animate(core, "Flicker", 0.2, 1.1, phase + 1.3)
	return holder, h
end

-- Étoile à 5 branches (triangles autour d'un cœur rond), centrée en (cx, cy)
local function star(parent, kit, cx, cy, radius, color, z, slices)
	local holder = kit.Group(parent, 0, 0, 100, 100, z)
	local inner = radius * 0.47
	local baseW = 2 * inner * math.sin(math.rad(36))
	local d = inner * math.cos(math.rad(36))
	local h = radius - d
	for index = 0, 4 do
		local a = index * 72
		local dist = d + h / 2
		local px = cx + math.sin(math.rad(a)) * dist
		local py = cy - math.cos(math.rad(a)) * dist
		local tri = kit.Triangle(holder, px, py - h / 2, baseW, h, color, 1, nil, slices or 7)
		tri.Rotation = a
	end
	kit.Circle(holder, cx, cy, inner * 2.1, inner * 2.1, color, 0, 2)
	return holder
end

----------------------------------------------------------------------
-- Dessins
----------------------------------------------------------------------

-- Bougie parfumée : bougie rose qui coule, petite flamme, soucoupe
Art.ScentedCandle = function(body, kit, _item)
	local C = kit.C
	local wax = Color3.fromRGB(255, 186, 212)
	kit.Part(body, 14, 88, 72, 12, C.Lilac, { Radius = -1, Z = 2, Shine = true }) -- soucoupe
	kit.Part(body, 28, 44, 44, 50, wax, { Radius = 9, Z = 3, Shine = true })
	-- cire fondue sur le dessus (avec 2 coulures)
	silhouette(body, kit, {
		{ 26, 38, 48, 14, 7 },
		{ 31, 44, 8, 18 },
		{ 56, 44, 7, 13 },
	}, Color3.fromRGB(255, 226, 238), 4)
	kit.Face(body, 50, 74, 28, { Eyes = "happy", Mouth = "smile", Z = 5 })
	kit.Line(body, 50, 39, 50, 31, 2.6, C.Ink, 0, 5) -- mèche
	local glow = kit.Circle(body, 50, 18, 34, 34, C.Butter, 0.72, 1)
	kit.Animate(glow, "Pulse", 0.18, 0.9, 0.3)
	flame(body, kit, 50, 33, 26, 6, 0.2)
	return { Glow = Color3.fromRGB(255, 200, 120) }
end

-- Ampoule suspendue : douille lilas, ampoule jaune avec filament cœur et visage
Art.HangingBulb = function(body, kit, _item)
	local C = kit.C
	local layer = hang(body, kit, 22, C.Ink, 4, 0.5)
	local glow = kit.Circle(layer, 50, 58, 70, 70, C.Butter, 0.75, 1)
	kit.Animate(glow, "Pulse", 0.15, 0.8, 0)
	kit.Part(layer, 40, 16, 20, 18, C.Lilac, { Radius = 4, Z = 5, Shine = true }) -- douille
	kit.Line(layer, 41, 23, 59, 23, 1.6, kit.OutlineOf(C.Lilac), 0.3, 6)
	kit.Line(layer, 41, 28, 59, 28, 1.6, kit.OutlineOf(C.Lilac), 0.3, 6)
	kit.Part(layer, 41, 30, 18, 12, C.Butter, { Radius = 4, Z = 2 }) -- col
	local bulb = kit.Blob(layer, 50, 58, 46, 46, C.Butter, { Z = 3 })
	kit.Gradient(bulb, Color3.fromRGB(255, 252, 225), Color3.fromRGB(255, 220, 140), 90)
	kit.Shine(layer, 32, 42, 7, 12, 5, 0.25)
	kit.Line(layer, 46, 33, 47.5, 44, 1.4, C.Orange, 0, 4)
	kit.Line(layer, 54, 33, 52.5, 44, 1.4, C.Orange, 0, 4)
	kit.Heart(layer, 50, 46, 9, C.Orange, 0, 4)
	kit.Face(layer, 50, 64, 26, { Eyes = "happy", Mouth = "smile", Z = 5 })
	return { Glow = Color3.fromRGB(255, 236, 150), WallShadow = Vector2.new(0.4, 0.45) }
end

-- Guirlande : 2 festons de fil vert, ampoules pastel qui scintillent
Art.FairyLights = function(body, kit, _item)
	local C = kit.C
	local colors = {
		Color3.fromRGB(255, 130, 185),
		Color3.fromRGB(255, 214, 100),
		Color3.fromRGB(120, 225, 185),
		Color3.fromRGB(180, 150, 255),
		Color3.fromRGB(255, 165, 120),
		Color3.fromRGB(130, 195, 255),
	}
	local function wireAt(u)
		return -4 + u * 108, 20 + 26 * math.abs(math.sin(u * math.pi * 2))
	end
	local segments = 12
	local px, py = wireAt(0)
	for index = 1, segments do
		local x, y = wireAt(index / segments)
		kit.Line(body, px, py, x, y, 2, C.LeafDark, 0, 2)
		px, py = x, y
	end
	for _, u in ipairs({ 0, 0.5, 1 }) do
		local x, y = wireAt(u)
		kit.Circle(body, x, y, 6, 6, C.PinkDeep, 0, 3) -- punaise
	end
	for index = 0, 9 do
		local u = (index + 0.5) / 10
		local x, y = wireAt(u)
		local color = colors[index % #colors + 1]
		local halo = kit.Circle(body, x, y + 9, 20, 20, color, 0.72, 1)
		kit.Part(body, x - 2.5, y - 1, 5, 5, C.LeafDark, { Radius = 1.5, Z = 4, Outline = false, Shade = false })
		local bulb = kit.Part(body, x - 4.5, y + 3, 9, 12, color, { Radius = -1, Z = 3, Thickness = 1.2 })
		kit.Animate(bulb, "Pulse", 0.4, 1.1, index * 1.7)
		kit.Animate(halo, "Pulse", 0.28, 1.1, index * 1.7)
	end
	return { Glow = Color3.fromRGB(255, 220, 170), WallShadow = Vector2.new(0, 0) }
end

-- Lanterne en papier : boule corail à côtes, chapeaux dorés, pompon, visage
Art.PaperLantern = function(body, kit, _item)
	local C = kit.C
	local red = Color3.fromRGB(255, 125, 135)
	local layer = hang(body, kit, 24, Color3.fromRGB(200, 70, 90), 3, 1.1)
	kit.Part(layer, 38, 22, 24, 8, C.Gold, { Radius = 3, Z = 5, Shine = true })
	kit.Part(layer, 38, 74, 24, 8, C.Gold, { Radius = 3, Z = 5 })
	local lantern = kit.Blob(layer, 50, 52, 64, 50, red, { Z = 3, Shine = true })
	kit.Gradient(lantern, Color3.fromRGB(255, 205, 190), Color3.fromRGB(235, 185, 185), 90)
	local inside = kit.Circle(layer, 50, 54, 34, 28, C.Butter, 0.55, 4)
	kit.Animate(inside, "Pulse", 0.25, 0.8, 0.6)
	for _, w in ipairs({ 44, 20 }) do
		kit.Blob(layer, 50, 52, w, 50, red, { T = 1, Z = 4, Outline = kit.Darken(red, 0.18), Thickness = 1.2, Shade = false })
	end
	kit.Face(layer, 50, 56, 24, { Eyes = "happy", Mouth = "cat", Z = 6 })
	kit.Line(layer, 50, 82, 50, 88, 2, C.Gold, 0, 2)
	kit.Part(layer, 46, 87, 8, 14, C.PinkDeep, { Radius = 3, Z = 3 }) -- pompon
	kit.Circle(layer, 50, 87, 6, 6, C.Gold, 0, 4)
	return { Glow = Color3.fromRGB(255, 140, 120), WallShadow = Vector2.new(0.55, 0.55) }
end

-- Grand lampadaire : pied menthe, abat-jour rose à franges, tirette
Art.FloorLamp = function(body, kit, _item)
	local C = kit.C
	local shade = Color3.fromRGB(255, 180, 210)
	kit.Part(body, 28, 90, 44, 10, C.Mint, { Radius = -1, Z = 2, Shine = true })
	kit.Part(body, 47, 34, 6, 58, C.MintSoft, { Radius = 3, Z = 1 })
	kit.Blob(body, 50, 62, 12, 7, C.Mint, { Z = 2 })
	local beam = kit.TriangleDown(body, 50, 38, 40, 22, C.Butter, 1, 0.8, 6)
	beam.Rotation = 180
	pulseAll(kit, beam, 0.15, 0.7, 0)
	kit.Blob(body, 50, 38, 16, 9, C.Butter, { Z = 2, Outline = false })
	-- dôme (moitié haute d'un ovale) + bordure + franges
	local dome = kit.Group(body, 18, 4, 64, 32, 3, true)
	kit.Blob(dome, 32, 32, 56, 56, shade, { Shine = true })
	kit.Part(body, 18, 30, 64, 9, kit.Lighten(shade, 0.25), { Radius = -1, Z = 4 })
	for index = 0, 5 do
		kit.Circle(body, 25 + index * 10, 41, 7, 7, C.PinkDeep, 0, 3)
	end
	kit.Heart(body, 50, 20, 11, C.PinkDeep, 0, 5)
	kit.Line(body, 68, 39, 68, 52, 1.2, C.GreyDark, 0, 2)
	kit.Circle(body, 68, 53, 4.5, 4.5, C.Gold, 0, 3)
	return { Glow = Color3.fromRGB(255, 225, 160) }
end

-- Petite lampe à huile (diya) : coupelle pêche à pois, bec, flamme
Art.OilLamp = function(body, kit, _item)
	local C = kit.C
	local clay = Color3.fromRGB(255, 176, 140)
	kit.Part(body, 38, 88, 24, 12, kit.Darken(clay, 0.08), { Radius = 4, Z = 2 })
	kit.Part(body, 66, 54, 24, 13, clay, { Radius = -1, Z = 2, Rotation = -18 }) -- bec
	local bowl = kit.Group(body, 12, 60, 76, 32, 3, true)
	kit.Blob(bowl, 38, 0, 72, 60, clay, { Shine = false })
	kit.Blob(body, 49, 61, 76, 13, kit.Lighten(clay, 0.2), { Z = 4 }) -- rebord
	kit.Blob(body, 49, 61, 60, 7, Color3.fromRGB(240, 190, 90), { Z = 5, Outline = false, Shade = false }) -- huile
	for _, x in ipairs({ 24, 76 }) do
		kit.Circle(body, x, 74, 5, 5, C.PinkSoft, 0, 5)
	end
	kit.Face(body, 50, 76, 24, { Eyes = "happy", Mouth = "smile", Z = 6 })
	kit.Line(body, 80, 52, 83, 46, 2.4, C.Ink, 0, 5)
	local glow = kit.Circle(body, 83, 32, 30, 30, C.Butter, 0.72, 1)
	kit.Animate(glow, "Pulse", 0.2, 0.9, 1)
	flame(body, kit, 83, 48, 24, 6, 0.7)
	return { Glow = Color3.fromRGB(255, 196, 110) }
end

-- Veilleuse étoile : grosse étoile dodue avec visage endormi, socle nuage
Art.StarNightLight = function(body, kit, _item)
	local C = kit.C
	local halo = kit.Circle(body, 50, 46, 84, 84, C.Butter, 0.78, 1)
	kit.Animate(halo, "Pulse", 0.15, 0.6, 0)
	star(body, kit, 50, 48, 45, C.Gold, 2, 7)
	star(body, kit, 50, 49, 40, C.Butter, 3, 7)
	kit.Shine(body, 36, 36, 8, 5, 5, 0.3)
	kit.Face(body, 50, 52, 30, { Eyes = "closed", Mouth = "smile", Z = 6 })
	kit.Part(body, 28, 86, 44, 14, C.Lilac, { Radius = 6, Z = 7, Shine = true }) -- socle
	kit.Circle(body, 50, 93, 5, 5, C.Butter, 0, 8)
	return { Glow = Color3.fromRGB(255, 232, 140) }
end

-- Lampe feu d'artifice : rayons pastel autour d'un cœur doré, pointes qui scintillent
Art.SparklerLights = function(body, kit, _item)
	local C = kit.C
	local colors = { C.Gold, C.Pink, C.Lilac, C.Mint, C.Sky, C.Orange }
	local wheel = kit.Pivot(body, 50, 50, 2)
	for index = 0, 11 do
		local a = math.rad(index * 30)
		local long = index % 2 == 0
		local r2 = if long then 42 else 31
		local sx, sy = math.sin(a), -math.cos(a)
		local color = colors[index % #colors + 1]
		kit.Line(wheel, sx * 13, sy * 13, sx * r2, sy * r2, if long then 3.4 else 2.6, color, 0, 1)
		local tip = kit.Circle(wheel, sx * (r2 + 4), sy * (r2 + 4), if long then 7 else 5, if long then 7 else 5, kit.Lighten(color, 0.3), 0, 2)
		kit.Animate(tip, "Pulse", 0.7, 1.4, index * 0.8)
	end
	kit.Animate(wheel, "Spin", 1, 0.03, 0)
	kit.Blob(body, 50, 50, 24, 24, C.Butter, { Z = 4, Shine = true })
	kit.Sparkle(body, 50, 50, 16, C.Orange, 0, 5)
	for _, p in ipairs({ { 22, 20 }, { 80, 78 } }) do
		local sp = kit.Sparkle(body, p[1], p[2], 10, WHITE, 0, 5)
		pulseAll(kit, sp, 0.8, 1.2, p[1] * 0.1)
	end
	return { Glow = Color3.fromRGB(255, 220, 160), WallShadow = Vector2.new(0.5, 0.5) }
end

-- Lampe nuage : nuage moelleux endormi avec breloques (cœur, goutte, étoile)
Art.CloudLamp = function(body, kit, _item)
	local C = kit.C
	local charms = {
		{ 32, 84, C.Pink, "heart" },
		{ 50, 90, C.Sky, "drop" },
		{ 68, 82, C.Butter, "star" },
	}
	for index, c in ipairs(charms) do
		local pivot = kit.Pivot(body, c[1], 60, 1)
		local len = c[2] - 60
		kit.Line(pivot, 0, 0, 0, len - 3, 1.2, C.GreyDark, 0.2, 1)
		if c[4] == "heart" then
			kit.Heart(pivot, 0, len + 1, 11, c[3], 0, 2)
		elseif c[4] == "drop" then
			kit.Circle(pivot, 0, len + 2, 9, 9, c[3], 0, 2)
			kit.Diamond(pivot, 0, len - 1.5, 6.4, c[3], 0, 2)
		else
			kit.Sparkle(pivot, 0, len + 1, 13, C.Gold, 0, 2)
		end
		kit.Animate(pivot, "Sway", 6, 0.9, index * 1.3)
	end
	local cloud = kit.Group(body, 0, 0, 100, 100, 3)
	silhouette(cloud, kit, {
		{ 10, 44, 80, 30 },
		{ 18, 34, 34, 34 },
		{ 38, 20, 40, 40 },
		{ 62, 34, 28, 28 },
	}, Color3.fromRGB(255, 252, 240), 1, 2)
	local warm = kit.Circle(cloud, 52, 52, 48, 26, C.Butter, 0.6, 2)
	kit.Animate(warm, "Pulse", 0.3, 0.7, 0)
	kit.Shine(cloud, 44, 26, 12, 5, 3, 0.2)
	kit.Face(cloud, 50, 54, 30, { Eyes = "closed", Mouth = "smile", Z = 4 })
	kit.Animate(cloud, "Bob", 1.5, 0.6, 0.2)
	return { Glow = Color3.fromRGB(255, 244, 200), WallShadow = Vector2.new(0.8, 0.45) }
end

-- Enseigne néon : plaque violette, gros cœur néon rose et petit cœur lilas
Art.NeonHeart = function(body, kit, _item)
	local C = kit.C
	local plate = Color3.fromRGB(78, 56, 118)
	kit.Part(body, 8, 12, 84, 72, plate, { Radius = 14, Z = 2, Shade = 0.2 })
	for _, p in ipairs({ { 14, 18 }, { 86, 18 }, { 14, 78 }, { 86, 78 } }) do
		kit.Circle(body, p[1], p[2], 4, 4, C.Grey, 0, 3)
	end
	local function neon(cx, cy, size, tube, core, z, phase)
		local glow = kit.Heart(body, cx, cy, size + 6, tube, 0.55, z)
		pulseAll(kit, glow, 0.3, 1, phase)
		kit.Heart(body, cx, cy, size, tube, 0, z)
		kit.Heart(body, cx, cy, size - 5, core, 0, z)
		kit.Heart(body, cx, cy, size - 10, tube, 0, z)
		kit.Heart(body, cx, cy, size - 16, plate, 0, z)
	end
	neon(44, 46, 54, C.Heart, C.PinkSoft, 4, 0)
	neon(68, 62, 30, C.Lilac, C.LilacSoft, 5, 1.5)
	kit.Line(body, 70, 84, 76, 100, 1.6, C.GreyDark, 0, 1) -- fil électrique
	return { Glow = Color3.fromRGB(255, 90, 170), WallShadow = Vector2.new(0.84, 0.72) }
end

-- Lampe lune : sphère crème à cratères sur socle en bois, lune qui dort
Art.MoonLamp = function(body, kit, _item)
	local C = kit.C
	local moonColor = Color3.fromRGB(255, 244, 205)
	kit.Part(body, 30, 84, 40, 16, C.WoodLight, { Radius = 6, Z = 2, Shine = true })
	kit.Blob(body, 50, 84, 36, 8, C.Wood, { Z = 3 })
	local moon = kit.Blob(body, 50, 50, 66, 66, moonColor, { Z = 4, Shade = 0.1 })
	moon.AnchorPoint = Vector2.new(0.5, 0.5)
	moon.Position = UDim2.fromOffset(50, 50)
	local crater = kit.Darken(moonColor, 0.1)
	for _, c in ipairs({ { 18, 18, 12 }, { 50, 16, 8 }, { 14, 44, 7 }, { 52, 50, 11 }, { 30, 56, 6 } }) do
		kit.Circle(moon, c[1], c[2], c[3], c[3], crater, 0.25, 2)
	end
	kit.Shine(moon, 10, 8, 12, 6, 3, 0.3)
	kit.Face(moon, 34, 36, 32, { Eyes = "closed", Mouth = "smile", Z = 4 })
	kit.Animate(moon, "Breathe", 0.015, 0.6, 0)
	kit.Sparkle(body, 86, 22, 12, C.Butter, 0, 5)
	kit.Text(body, "z", 80, 36, 9, C.Lilac, 5)
	return { Glow = Color3.fromRGB(255, 244, 200) }
end

-- Boule à facettes : suspendue, facettes pastel, reflets qui tournent autour
Art.DiscoBall = function(body, kit, _item)
	local C = kit.C
	local layer = hang(body, kit, 18, C.GreyDark, 2, 0.3)
	kit.Part(layer, 44, 14, 12, 9, C.Grey, { Radius = 3, Z = 4 })
	local ball = kit.Blob(layer, 50, 50, 58, 58, Color3.fromRGB(226, 222, 240), { Z = 3, Shade = 0.2 })
	local tile = kit.Darken(C.Grey, 0.25)
	for _, dy in ipairs({ -19, -9.5, 0, 9.5, 19 }) do
		local half = math.sqrt(29 * 29 - dy * dy) - 1.5
		kit.Line(ball, 29 - half, 29 + dy, 29 + half, 29 + dy, 1.1, tile, 0.35, 2)
	end
	for _, w in ipairs({ 20, 42 }) do
		kit.Blob(ball, 29, 29, w, 58, WHITE, { T = 1, Z = 2, Outline = tile, Thickness = 1.1, Shade = false })
	end
	local pastel = { C.Pink, C.Sky, C.Butter, C.Mint, C.Lilac, WHITE }
	for index, p in ipairs({ { 16, 14 }, { 34, 24 }, { 22, 36 }, { 42, 38 }, { 30, 48 }, { 12, 26 } }) do
		local sq = kit.Box(ball, p[1], p[2], 7, 7, pastel[index], 0.05, 3)
		kit.Round(sq, 1.5)
		kit.Animate(sq, "Pulse", 0.8, 1.3, index * 1.1)
	end
	kit.Shine(ball, 12, 9, 12, 7, 4, 0.2)
	local spin = kit.Pivot(layer, 50, 50, 5)
	for index = 0, 3 do
		local a = math.rad(index * 90 + 25)
		local r = if index % 2 == 0 then 40 else 37
		local sp = kit.Sparkle(spin, math.sin(a) * r, -math.cos(a) * r, if index % 2 == 0 then 11 else 8, pastel[index + 1], 0, 1)
		pulseAll(kit, sp, 0.5, 1.5, index)
	end
	kit.Animate(spin, "Spin", 1, 0.08, 0)
	return { Glow = Color3.fromRGB(230, 200, 255), WallShadow = Vector2.new(0.55, 0.55) }
end

-- Projecteur arc-en-ciel : petit projecteur mignon qui dessine un arc-en-ciel
Art.RainbowProjector = function(body, kit, _item)
	local C = kit.C
	local arc = kit.Group(body, 2, 4, 96, 54, 2, true)
	local bands = {
		Color3.fromRGB(255, 140, 155),
		Color3.fromRGB(255, 190, 130),
		Color3.fromRGB(255, 230, 140),
		Color3.fromRGB(150, 225, 180),
		Color3.fromRGB(150, 200, 255),
		Color3.fromRGB(190, 160, 250),
	}
	for index, color in ipairs(bands) do
		local r = 40 - (index - 1) * 5
		local ring = kit.Circle(arc, 48, 54, r * 2, r * 2, color, 1, 1)
		kit.Stroke(ring, color, 5, 0.05)
	end
	local beam = kit.TriangleDown(body, 50, 42, 30, 28, C.Butter, 1, 0.72, 7)
	pulseAll(kit, beam, 0.18, 0.8, 0)
	for index, x in ipairs({ 12, 88 }) do
		local puff = kit.Group(body, x - 50, 0, 100, 100, 4)
		silhouette(puff, kit, {
			{ 36, 52, 28, 12 },
			{ 40, 45, 14, 14 },
			{ 48, 42, 14, 16 },
		}, WHITE, 1, 1.4)
		kit.Animate(puff, "Bob", 1.2, 0.8, index * 1.7)
	end
	-- projecteur
	kit.Part(body, 30, 66, 40, 28, C.PinkSoft, { Radius = 12, Z = 5, Shine = true })
	kit.Part(body, 34, 92, 8, 6, C.Pink, { Radius = 2, Z = 4 })
	kit.Part(body, 58, 92, 8, 6, C.Pink, { Radius = 2, Z = 4 })
	kit.Blob(body, 50, 66, 18, 10, C.Lilac, { Z = 6 })
	kit.Blob(body, 50, 65, 10, 5, WHITE, { Z = 7, Outline = false, Shade = false })
	kit.Face(body, 50, 82, 24, { Eyes = "dot", Mouth = "smile", Z = 6 })
	local sp = kit.Sparkle(body, 20, 16, 10, WHITE, 0, 5)
	pulseAll(kit, sp, 0.8, 1.2, 0.5)
	return { Glow = Color3.fromRGB(200, 160, 255), WallShadow = Vector2.new(0.4, 0.3) }
end

-- Lampe à lave : socle lilas, fiole rose où flottent des bulles de lave
Art.LavaLamp = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 29, 76, 42, 24, C.Purple, { Radius = 10, Z = 2, Shine = true }) -- socle
	kit.Part(body, 33, 72, 34, 6, C.Gold, { Radius = -1, Z = 4 })
	kit.Part(body, 38, 6, 24, 12, C.Purple, { Radius = 6, Z = 4 }) -- chapeau
	kit.Part(body, 36, 15, 28, 4, C.Gold, { Radius = -1, Z = 5 })
	local glass = kit.Part(body, 32, 16, 36, 58, C.Pink, { Radius = 15, Z = 3, Shade = false })
	kit.Gradient(glass, Color3.fromRGB(255, 225, 240), Color3.fromRGB(255, 170, 200), 90)
	local lava = kit.Group(body, 34, 18, 32, 54, 4, true)
	local blobColor = Color3.fromRGB(255, 110, 120)
	for index, b in ipairs({ { 16, 12, 11, 12 }, { 11, 27, 14, 15 }, { 21, 38, 10, 9 }, { 16, 54, 30, 14 } }) do
		local blob = kit.Circle(lava, b[1], b[2], b[3], b[4], blobColor, 0, 1)
		kit.Gradient(blob, Color3.fromRGB(255, 200, 120), WHITE, 90)
		if index < 4 then
			kit.Animate(blob, "Bob", 3 + index, 0.35, index * 1.9)
		end
	end
	kit.Shine(body, 37, 26, 4, 22, 6, 0.4)
	kit.Face(body, 50, 88, 22, { Eyes = "dot", Mouth = "smile", Color = C.White, Z = 5 })
	return { Glow = Color3.fromRGB(255, 120, 90) }
end

-- Lampe OVNI : soucoupe suspendue, petit alien dans la bulle, rayon vert
Art.UFOLamp = function(body, kit, _item)
	local C = kit.C
	local layer = hang(body, kit, 26, C.GreyDark, 3, 2)
	local beam = kit.Triangle(layer, 50, 56, 50, 38, C.Mint, 1, 0.7, 8)
	pulseAll(kit, beam, 0.2, 0.9, 0)
	-- alien
	kit.Line(layer, 50, 30, 50, 24, 1.4, C.LeafDark, 0, 2)
	kit.Circle(layer, 50, 24, 5, 5, C.Pink, 0, 2)
	kit.Blob(layer, 50, 40, 20, 18, C.Mint, { Z = 3 })
	kit.Face(layer, 50, 41, 16, { Eyes = "big", Mouth = "smile", Z = 4 })
	local dome = kit.Blob(layer, 50, 42, 36, 36, C.Glass, { Z = 5, T = 0.55, Shade = false })
	kit.Stroke(dome, C.Sky, 1.6, 0)
	kit.Shine(layer, 38, 30, 6, 9, 6, 0.3)
	kit.Blob(layer, 50, 56, 84, 22, C.Lilac, { Z = 7, Shine = true })
	kit.Blob(layer, 50, 62, 34, 10, C.Purple, { Z = 6 })
	local lights = { C.Butter, C.Pink, C.Mint, C.Pink, C.Butter }
	for index, x in ipairs({ 22, 36, 50, 64, 78 }) do
		local y = 57 + math.abs(x - 50) * -0.06
		local dot = kit.Circle(layer, x, y, 6, 6, lights[index], 0, 8)
		kit.Animate(dot, "Pulse", 0.7, 1.6, index * 0.9)
	end
	return { Glow = Color3.fromRGB(150, 255, 200), WallShadow = Vector2.new(0.7, 0.35) }
end

-- Lustre en cristal : bras dorés en U, 4 bougies, gouttes de cristal scintillantes
Art.CrystalChandelier = function(body, kit, _item)
	local C = kit.C
	local gold = C.Gold
	local layer = hang(body, kit, 12, gold, 2, 0.8)
	kit.Part(layer, 42, 8, 16, 8, gold, { Radius = 3, Z = 3 })
	kit.Line(layer, 50, 14, 50, 50, 4, gold, 0, 2)
	-- bras (moitié basse d'un ovale doré)
	local arms = kit.Group(layer, 10, 44, 80, 24, 3, true)
	local ring = kit.Circle(arms, 40, 0, 72, 34, gold, 1, 1)
	kit.Stroke(ring, gold, 3.6, 0)
	local inner = kit.Group(layer, 24, 44, 52, 18, 3, true)
	local ring2 = kit.Circle(inner, 26, 0, 40, 22, gold, 1, 1)
	kit.Stroke(ring2, gold, 3, 0)
	kit.Blob(layer, 50, 54, 22, 14, gold, { Z = 4, Shine = true })
	-- gouttes de cristal
	local crystals = { C.LilacSoft, C.Glass, C.PinkSoft, C.Glass, C.LilacSoft }
	for index, d in ipairs({ { 22, 60, 68 }, { 36, 64, 76 }, { 50, 62, 82 }, { 64, 64, 76 }, { 78, 60, 68 } }) do
		kit.Line(layer, d[1], d[2], d[1], d[3] - 4, 1, gold, 0.3, 2)
		local gem = kit.Diamond(layer, d[1], d[3], 8, crystals[index], 0, 3)
		kit.Stroke(gem, C.Sky, 1, 0.1)
		kit.Animate(gem, "Pulse", 0.5, 1.4, index * 1.2)
	end
	-- bougies
	for index, x in ipairs({ 14, 30, 70, 86 }) do
		local y = if index == 1 or index == 4 then 44 else 52
		kit.Part(layer, x - 3, y - 12, 6, 12, C.Cream, { Radius = 2, Z = 4 })
		kit.Blob(layer, x, y, 13, 6, gold, { Z = 5 })
		flame(layer, kit, x, y - 12, 12, 5, index * 0.9)
	end
	for index, p in ipairs({ { 50, 30 }, { 8, 72 }, { 92, 70 } }) do
		local sp = kit.Sparkle(layer, p[1], p[2], if index == 1 then 12 else 9, WHITE, 0, 6)
		pulseAll(kit, sp, 0.8, 1.1, index * 1.4)
	end
	return { Glow = Color3.fromRGB(190, 230, 255), WallShadow = Vector2.new(0.7, 0.5) }
end

-- Soleil de poche : soleil joufflu aux grands yeux, rayons qui tournent doucement
Art.PocketSun = function(body, kit, _item)
	local C = kit.C
	local halo = kit.Circle(body, 50, 50, 100, 100, C.Butter, 0.75, 1)
	kit.Animate(halo, "Pulse", 0.15, 0.7, 0)
	local rays = kit.Pivot(body, 50, 50, 2)
	for index = 0, 11 do
		local a = index * 30
		local long = index % 2 == 0
		local len = if long then 18 else 12
		local w = if long then 9 else 7
		local dist = if long then 40 else 38
		local cx = math.sin(math.rad(a)) * dist
		local cy = -math.cos(math.rad(a)) * dist
		kit.Part(rays, cx - w / 2, cy - len / 2, w, len, if long then C.Orange else C.Yellow, { Radius = -1, Rotation = a, Z = 1 })
	end
	kit.Animate(rays, "Spin", 1, 0.03, 0)
	local sun = kit.Blob(body, 50, 50, 66, 66, C.Yellow, { Z = 3, Shade = false })
	sun.AnchorPoint = Vector2.new(0.5, 0.5)
	sun.Position = UDim2.fromOffset(50, 50)
	kit.Gradient(sun, Color3.fromRGB(255, 245, 190), Color3.fromRGB(255, 205, 120), 90)
	kit.Shine(sun, 12, 9, 16, 8, 3, 0.25)
	kit.Face(sun, 33, 36, 40, { Eyes = "big", Mouth = "smile", Z = 3 })
	kit.Animate(sun, "Breathe", 0.02, 0.8, 0)
	for index, p in ipairs({ { 12, 14, 12 }, { 90, 24, 9 }, { 86, 88, 12 } }) do
		local sp = kit.Sparkle(body, p[1], p[2], p[3], WHITE, 0, 5)
		pulseAll(kit, sp, 0.8, 1.1, index * 1.3)
	end
	local puff = kit.Cloud(body, 20, 96, 30, WHITE, 0, 6)
	kit.Animate(puff, "Drift", 2, 0.5, 0)
	return { Glow = Color3.fromRGB(255, 214, 90), WallShadow = Vector2.new(0.7, 0.7) }
end

return Art
