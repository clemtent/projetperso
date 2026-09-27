--[[
	Cool92Adventure (ModuleScript) — (v9.2) aventure 🚀🦖🏴 : dinos, espace,
	robots, pirates, ninjas, super-héros (affiches maison, aucune marque),
	aquarium à requins, lampes néon
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Cool92Adventure
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au
	sol, centrés pour les objets muraux).
]]

local Art = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local NAVY = rgb(52, 60, 100)
local DARK = rgb(44, 46, 64)
local DARKER = rgb(30, 32, 46)
local CYAN = rgb(60, 222, 255)
local RED = rgb(236, 66, 76)
local ORANGE = rgb(255, 152, 56)
local STEEL = rgb(176, 186, 206)
local CHROME = rgb(214, 222, 236)
local BLUE = rgb(80, 150, 255)
local DINO = rgb(120, 200, 110)
local BONE = rgb(246, 238, 220)
local LAVA = rgb(255, 110, 50)

-- Éclair (3 segments) dans la zone (x, y) de hauteur h
local function bolt(kit, parent, x, y, h, color, z, thick)
	local g = kit.Group(parent, x, y, h * 0.7, h, z)
	local t = thick or h * 0.16
	kit.Line(g, h * 0.55, 0, h * 0.16, h * 0.52, t, color, 0, 1)
	kit.Line(g, h * 0.16, h * 0.52, h * 0.54, h * 0.48, t, color, 0, 1)
	kit.Line(g, h * 0.54, h * 0.48, h * 0.14, h, t, color, 0, 1)
	return g
end

-- Bulles qui montent (aquarium, lampe à lave)
local function bubbles(kit, parent, list, z)
	for index, b in ipairs(list) do
		local bubble = kit.Circle(parent, b[1], b[2], b[3], b[3], WHITE, 0.45, z)
		kit.Stroke(bubble, WHITE, 1, 0.3)
		kit.Animate(bubble, "Bob", 3, 1.4, index * 0.9)
	end
end

----------------------------------------------------------------------
-- 🧸 Peluches
----------------------------------------------------------------------

-- T-rex en peluche (grosse tête, petits bras, dents, piques)
Art.TRexPlush = function(body, kit, _item)
	local C = kit.C
	local dark = kit.Darken(DINO, 0.2)
	-- queue + piques du dos
	kit.Blob(body, 20, 76, 40, 22, DINO, { Z = 1, Rotation = -20 })
	for index = 0, 3 do
		kit.Triangle(body, 30 + index * 9, 30 + index * 9, 10, 10, C.Butter, 1)
	end
	-- corps + ventre
	local belly = kit.Blob(body, 52, 70, 50, 50, DINO, { Z = 2, Shine = true })
	kit.Blob(belly, 28, 30, 30, 34, rgb(236, 246, 200), { Z = 2, Outline = false })
	for index = 0, 2 do
		kit.Box(belly, 18, 20 + index * 8, 20, 1.5, kit.Darken(DINO, 0.1), 0.4, 3)
	end
	-- pattes
	for _, x in ipairs({ 40, 64 }) do
		kit.Blob(body, x, 94, 18, 12, dark, { Z = 3 })
	end
	-- petits bras
	kit.Blob(body, 72, 58, 12, 7, DINO, { Z = 4, Rotation = 30 })
	-- tête
	local head = kit.Part(body, 44, 12, 50, 36, DINO, { Radius = 16, Z = 5, Shine = true })
	kit.Face(head, 28, 14, 20, { Eyes = "big", Mouth = "none", Z = 3 })
	kit.Part(head, 8, 24, 40, 8, rgb(255, 170, 190), { Radius = 4, Z = 2, Outline = false }) -- bouche
	for index = 0, 4 do
		kit.TriangleDown(head, 12 + index * 7, 24, 5, 5, WHITE, 3) -- dents
	end
	kit.Circle(head, 44, 8, 3, 3, dark, 0, 3) -- narine
	return nil
end

-- Ninja en peluche (capuche noire, bandeau rouge qui flotte, étoile en tissu)
Art.NinjaPlush = function(body, kit, _item)
	local C = kit.C
	-- rubans du bandeau (flottent)
	local tails = kit.Pivot(body, 22, 34, 1)
	kit.Part(tails, -20, -4, 22, 7, RED, { Radius = 3, Z = 1, Rotation = -18 })
	kit.Part(tails, -18, 4, 18, 6, RED, { Radius = 3, Z = 1, Rotation = 14 })
	kit.Animate(tails, "Sway", 8, 2.4, 0)
	-- corps
	local suit = kit.Blob(body, 50, 76, 50, 42, DARK, { Z = 2, Shine = true })
	kit.Box(suit, 6, 18, 38, 5, RED, 0, 2) -- ceinture
	for _, x in ipairs({ 38, 62 }) do
		kit.Blob(body, x, 95, 16, 10, DARKER, { Z = 3 })
	end
	-- tête
	local head = kit.Blob(body, 50, 38, 56, 50, DARK, { Z = 4, Shine = true })
	local slit = kit.Part(head, 8, 16, 40, 18, rgb(255, 220, 196), { Radius = 8, Z = 2, Outline = false })
	kit.Face(slit, 20, 10, 20, { Eyes = "happy", Mouth = "none", Z = 3 })
	kit.Box(head, 2, 10, 52, 5, RED, 0, 3) -- bandeau
	-- étoile en tissu dans la main
	local star = kit.Group(body, 70, 62, 20, 20, 6)
	kit.Diamond(star, 10, 10, 11, STEEL, 0, 1)
	kit.Box(star, 1, 8.5, 18, 3, STEEL, 0, 1)
	kit.Box(star, 8.5, 1, 3, 18, STEEL, 0, 1)
	kit.Circle(star, 10, 10, 4, 4, DARKER, 0, 2)
	kit.Animate(star, "Sway", 12, 1.5, 0)
	kit.Sparkle(body, 86, 22, 9, C.Butter, 0, 7)
	return nil
end

----------------------------------------------------------------------
-- 🖼️ Affiches, aquarium
----------------------------------------------------------------------

-- Affiche de super-héros (héros maison "éclair", cape, ville au loin)
Art.HeroPoster = function(body, kit, _item)
	local C = kit.C
	local poster = kit.Part(body, 12, 4, 76, 92, WHITE, { Radius = 3, Z = 1 })
	local art = kit.Group(poster, 4, 4, 68, 84, 2, true)
	local sky = kit.Box(art, 0, 0, 68, 84, WHITE, 0, 1)
	kit.Gradient(sky, rgb(90, 130, 240), rgb(255, 180, 120), 90)
	for index = 0, 4 do
		kit.Box(art, index * 14, 58 - (index % 3) * 8, 12, 40, rgb(60, 70, 130), 0.1, 2) -- ville
	end
	kit.Circle(art, 52, 18, 16, 16, C.Butter, 0.2, 2)
	-- cape qui flotte
	local cape = kit.Pivot(art, 34, 34, 3)
	kit.Part(cape, -18, 0, 36, 34, RED, { Radius = 10, Z = 1 })
	kit.Animate(cape, "Sway", 4, 1.6, 0)
	-- héros
	local suit = kit.Part(art, 22, 34, 24, 26, BLUE, { Radius = 8, Z = 4, Shine = true })
	bolt(kit, suit, 7, 4, 16, C.Butter, 3)
	kit.Part(art, 10, 34, 12, 7, BLUE, { Radius = 3, Z = 4, Rotation = -40 }) -- bras levé
	kit.Blob(art, 10, 30, 8, 8, RED, { Z = 5 }) -- poing
	local head = kit.Blob(art, 34, 26, 20, 18, rgb(255, 220, 196), { Z = 5, Shine = true })
	kit.Part(head, 1, 5, 18, 5, RED, { Radius = 2, Z = 2, Outline = false }) -- masque
	kit.Face(head, 10, 9, 12, { Eyes = "dot", Mouth = "smile", Blush = false, Z = 3 })
	kit.Text(art, "HERO!", 34, 74, 14, C.Butter, 6).TextStrokeTransparency = 0
	return { WallShadow = Vector2.new(76, 92) }
end

-- Affiche de BD "POW!" (explosion, points de trame, traits de vitesse)
Art.ComicPoster = function(body, kit, _item)
	local C = kit.C
	local poster = kit.Part(body, 8, 6, 84, 88, rgb(80, 200, 255), { Radius = 3, Z = 1, Shine = true })
	for row = 0, 7 do
		for col = 0, 7 do
			kit.Circle(poster, 6 + col * 10.5, 6 + row * 10.5, 3, 3, WHITE, 0.55, 2) -- trame
		end
	end
	-- explosion (carrés tournés)
	local burst = kit.Group(body, 14, 16, 72, 66, 3)
	for index = 0, 5 do
		local ray = kit.Box(burst, 6, 26, 60, 16, C.Butter, 0, 1)
		ray.Rotation = index * 30
		kit.Stroke(ray, RED, 2, 0)
	end
	kit.Blob(burst, 36, 34, 52, 40, C.Butter, { Z = 2, Outline = RED, Thickness = 2 })
	local word = kit.Text(burst, "POW!", 36, 34, 22, RED, 3)
	word.TextStrokeColor3 = WHITE
	word.TextStrokeTransparency = 0
	word.Rotation = -8
	kit.Animate(word, "Breathe", 0.06, 2, 0)
	for index = 0, 2 do
		kit.Line(body, 12, 80 + index * 4, 30 - index * 4, 80 + index * 4, 2, WHITE, 0.2, 4)
	end
	return { WallShadow = Vector2.new(84, 88) }
end

-- Grand aquarium à requins (deux requins mignons, corail, coffre, bulles)
Art.SharkTank = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 4, 76, 92, 22, DARK, { Radius = 5, Z = 1, Shine = true })
	for index = 0, 1 do
		kit.Part(body, 8 + index * 44, 80, 40, 14, NAVY, { Radius = 3, Z = 2 })
	end
	local tank = kit.Part(body, 2, 8, 96, 70, rgb(120, 200, 245), { Radius = 6, Z = 3, Outline = STEEL, Thickness = 2.5 })
	kit.Gradient(tank, rgb(150, 225, 255), rgb(40, 110, 200), 90)
	local water = kit.Group(tank, 3, 3, 90, 64, 2, true)
	kit.Box(water, 0, 54, 90, 10, rgb(240, 214, 170), 0, 1) -- sable
	for index, x in ipairs({ 10, 18, 78 }) do
		kit.Part(water, x, 34 + index * 3, 5, 24, index == 3 and rgb(255, 150, 120) or rgb(110, 200, 120), { Radius = 3, Z = 1, Outline = false })
	end
	local chest = kit.Part(water, 60, 46, 16, 10, rgb(170, 110, 70), { Radius = 3, Z = 2 })
	kit.Box(chest, 0, 3, 16, 2, C.Gold, 0, 2)
	-- requins (corps gris-bleu, ventre blanc, aileron)
	local function shark(x, y, scale, phase)
		local g = kit.Group(water, x, y, 40 * scale, 20 * scale, 4)
		local s = kit.Blob(g, 20 * scale, 10 * scale, 34 * scale, 14 * scale, rgb(130, 150, 190), { Z = 2, Shine = true })
		kit.Blob(s, 16 * scale, 10 * scale, 24 * scale, 6 * scale, WHITE, { Z = 1, Outline = false, Shade = false })
		kit.Triangle(g, 20 * scale, 0, 10 * scale, 7 * scale, rgb(130, 150, 190), 1)
		kit.Triangle(g, 2 * scale, 4 * scale, 10 * scale, 12 * scale, rgb(130, 150, 190), 1)
		kit.Face(s, 26 * scale, 6 * scale, 10 * scale, { Eyes = "happy", Mouth = "cat", Z = 3 })
		kit.Animate(g, "Drift", 12, 0.6, phase)
		return g
	end
	shark(16, 8, 1, 0)
	shark(40, 30, 0.8, 2)
	bubbles(kit, water, { { 80, 14, 5 }, { 84, 26, 3 }, { 8, 20, 4 } }, 5)
	-- couvercle + lampe
	kit.Part(body, 0, 4, 100, 7, DARK, { Radius = 3, Z = 4 })
	local lamp = kit.Box(body, 20, 10, 60, 2, CYAN, 0.2, 5)
	kit.Animate(lamp, "Pulse", 0.4, 1, 0)
	return { Glow = rgb(120, 210, 255) }
end

----------------------------------------------------------------------
-- 💡 Lumières
----------------------------------------------------------------------

-- Enseigne néon éclair (jaune) sur panneau sombre
Art.LightningNeon = function(body, kit, _item)
	local C = kit.C
	local halo = kit.Part(body, 10, 6, 80, 88, C.Butter, { Radius = 18, Z = 1, Outline = false, Shade = false, T = 0.75 })
	kit.Animate(halo, "Pulse", 0.2, 1.1, 0)
	local board = kit.Part(body, 14, 10, 72, 80, DARKER, { Radius = 14, Z = 2 })
	kit.Stroke(board, CYAN, 2, 0.3)
	local glow = bolt(kit, board, 16, 8, 64, rgb(255, 240, 150), 2, 12)
	local _ = glow
	local core = bolt(kit, board, 16, 8, 64, WHITE, 3, 5)
	kit.Animate(core, "Pulse", 0.5, 3, 0)
	return { Glow = C.Butter, WallShadow = Vector2.new(72, 80) }
end

-- Lampe œuf de dino (coquille fêlée qui brille, bébé dino qui regarde)
Art.DinoEggLamp = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 94, 58, 12, rgb(170, 120, 86), { Z = 1, Shine = true }) -- nid
	local glow = kit.Blob(body, 50, 56, 70, 78, C.Butter, { Z = 1, Outline = false, Shade = false, T = 0.7 })
	kit.Animate(glow, "Pulse", 0.2, 1.2, 0)
	local egg = kit.Blob(body, 50, 60, 50, 66, rgb(250, 244, 220), { Z = 2, Shine = true })
	for _, spot in ipairs({ { 12, 20, 8 }, { 34, 44, 10 }, { 16, 50, 6 } }) do
		kit.Circle(egg, spot[1], spot[2], spot[3], spot[3], DINO, 0.3, 2)
	end
	-- fêlure en zigzag + lumière
	for index = 0, 4 do
		kit.Line(egg, 4 + index * 9, 20 + (index % 2) * 6, 13 + index * 9, 20 + ((index + 1) % 2) * 6, 2, C.Gold, 0, 3)
	end
	-- bébé dino qui sort la tête
	local head = kit.Blob(body, 50, 30, 30, 24, DINO, { Z = 3, Shine = true })
	kit.Face(head, 15, 12, 18, { Eyes = "big", Mouth = "smile", Z = 3 })
	kit.Animate(head, "Bob", 1.5, 1, 0)
	return { Glow = rgb(255, 230, 150) }
end

-- Lampe à lave en forme de fusée (bulles de lave qui montent et descendent)
Art.RocketLavaLamp = function(body, kit, _item)
	local C = kit.C
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(body, 50 + side * 20 - 7, 72, 14, 24, RED, { Radius = 4, Z = 1, Rotation = side * 18 })
	end
	kit.Part(body, 32, 80, 36, 18, CHROME, { Radius = 6, Z = 3, Shine = true })
	local glass = kit.Part(body, 34, 22, 32, 60, rgb(110, 60, 160), { Radius = 16, Z = 2 })
	kit.Gradient(glass, rgb(160, 100, 220), rgb(60, 30, 110), 90)
	for index, b in ipairs({ { 14, 44, 12 }, { 20, 26, 9 }, { 10, 14, 7 } }) do
		local blob = kit.Blob(glass, b[1], b[2], b[3], b[3] * 1.2, LAVA, { Z = 2, Outline = false })
		kit.Animate(blob, "Bob", 6, 0.6, index * 1.4)
	end
	kit.Shine(glass, 5, 6, 5, 30, 4, 0.5)
	kit.Triangle(body, 50, 4, 30, 20, CHROME, 3) -- nez
	local window = kit.Blob(body, 50, 36, 12, 12, CYAN, { Z = 4, Outline = CHROME, Thickness = 2 })
	local _ = window
	kit.Sparkle(body, 82, 20, 9, C.Butter, 0, 6)
	return { Glow = LAVA }
end

----------------------------------------------------------------------
-- 🚀 Aventure
----------------------------------------------------------------------

-- Parchemin ninja (rouleau suspendu : lune, bambou, chat ninja, étoile)
Art.NinjaBanner = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 30, 4, 50, -4, 1.5, DARK, 0, 1)
	kit.Line(body, 70, 4, 50, -4, 1.5, DARK, 0, 1)
	local scroll = kit.Part(body, 22, 6, 56, 86, rgb(250, 240, 214), { Radius = 2, Z = 2, Shine = true })
	kit.Part(body, 16, 2, 68, 7, rgb(150, 96, 60), { Radius = 3, Z = 3 })
	kit.Part(body, 16, 90, 68, 7, rgb(150, 96, 60), { Radius = 3, Z = 3 })
	kit.Circle(scroll, 36, 22, 22, 22, RED, 0, 2) -- soleil rouge
	for index = 0, 2 do
		kit.Part(scroll, 6 + index * 4, 34 + index * 6, 3, 48, rgb(110, 170, 110), { Radius = 1, Z = 3, Outline = false })
	end
	-- chat ninja
	local cat = kit.Blob(scroll, 32, 62, 28, 24, DARK, { Z = 4 })
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(scroll, 32 + side * 9 - 4, 46, 8, 8, DARK, { Radius = 2, Z = 3, Rotation = 45 })
	end
	local mask = kit.Part(cat, 4, 6, 20, 8, rgb(255, 230, 210), { Radius = 4, Z = 2, Outline = false })
	kit.Face(mask, 10, 5, 14, { Eyes = "happy", Mouth = "none", Blush = false, Z = 3 })
	kit.Box(cat, 0, 3, 28, 3, RED, 0, 3)
	local star = kit.Group(scroll, 38, 72, 14, 14, 5)
	kit.Diamond(star, 7, 7, 8, STEEL, 0, 1)
	kit.Box(star, 0, 6, 14, 2, STEEL, 0, 1)
	kit.Box(star, 6, 0, 2, 14, STEEL, 0, 1)
	kit.Animate(star, "Spin", 1, 0.5, 0)
	kit.Sparkle(body, 86, 60, 8, C.Butter, 0, 4)
	return { WallShadow = Vector2.new(60, 90) }
end

-- Maquette de volcan (lave qui coule, fumée qui monte)
Art.VolcanoModel = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 4, 88, 92, 10, rgb(110, 190, 110), { Radius = 4, Z = 1, Shine = true })
	local mountain = kit.Triangle(body, 50, 30, 84, 62, rgb(150, 100, 80), 2)
	local _ = mountain
	kit.Triangle(body, 50, 30, 60, 44, rgb(170, 118, 92), 3)
	kit.Blob(body, 50, 32, 22, 8, DARKER, { Z = 4 })
	-- lave
	kit.Blob(body, 50, 34, 18, 8, LAVA, { Z = 5 })
	kit.Line(body, 46, 36, 36, 60, 5, LAVA, 0, 5)
	kit.Line(body, 54, 36, 62, 70, 5, ORANGE, 0, 5)
	kit.Line(body, 36, 60, 30, 78, 4, LAVA, 0, 5)
	-- fumée
	for index = 0, 2 do
		local puff = kit.Blob(body, 44 + index * 8, 18 - index * 7, 16 - index * 2, 14 - index * 2, rgb(220, 220, 230), { Z = 6, Outline = false })
		kit.Animate(puff, "Bob", 3, 1, index)
	end
	-- petit panneau "science"
	local sign = kit.Part(body, 72, 70, 20, 12, WHITE, { Radius = 2, Z = 6 })
	kit.Text(sign, "!", 10, 6, 10, RED, 2)
	kit.Line(body, 82, 82, 82, 90, 2, rgb(150, 96, 60), 0, 5)
	local _c = C
	return { Glow = LAVA }
end

-- Mobile du système solaire (soleil, planètes qui se balancent)
Art.PlanetMobile = function(body, kit, _item)
	local C = kit.C
	kit.Line(body, 50, 0, 50, 14, 1.5, DARK, 0, 1)
	kit.Part(body, 8, 12, 84, 4, rgb(170, 120, 86), { Radius = 2, Z = 2 })
	local specs = {
		{ 12, 40, 12, rgb(255, 180, 120) },
		{ 30, 58, 16, rgb(100, 170, 255) },
		{ 70, 54, 18, rgb(255, 120, 110) },
		{ 88, 38, 12, rgb(170, 140, 255) },
	}
	for index, p in ipairs(specs) do
		local swing = kit.Pivot(body, p[1], 14, 3)
		kit.Line(swing, 0, 0, 0, p[2] - 14, 1, DARK, 0.2, 1)
		local planet = kit.Blob(swing, 0, p[2] - 14, p[3], p[3], p[4], { Z = 2, Shine = true })
		if index == 3 then
			local ring = kit.Box(swing, -p[3] * 0.9, p[2] - 15, p[3] * 1.8, 3, C.Butter, 0, 3)
			ring.Rotation = -18
			kit.Round(ring)
		end
		local _ = planet
		kit.Animate(swing, "Sway", 6, 0.8, index)
	end
	-- soleil au centre
	local sunSwing = kit.Pivot(body, 50, 14, 4)
	kit.Line(sunSwing, 0, 0, 0, 26, 1, DARK, 0.2, 1)
	local sun = kit.Blob(sunSwing, 0, 44, 30, 30, C.Butter, { Z = 2, Shine = true })
	kit.Face(sun, 15, 16, 18, { Eyes = "happy", Mouth = "smile", Z = 3 })
	kit.Animate(sunSwing, "Sway", 3, 0.6, 0)
	return { WallShadow = Vector2.new(0, 0) }
end

-- Maquette de bateau pirate (voiles, drapeau à tête de mort mignonne)
Art.PirateShip = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 30, 88, 40, 10, rgb(150, 96, 60), { Radius = 3, Z = 1, Shine = true })
	kit.Part(body, 46, 76, 8, 14, rgb(120, 80, 50), { Radius = 2, Z = 1 })
	local ship = kit.Group(body, 0, 0, 100, 100, 2)
	kit.Animate(ship, "Sway", 3, 0.9, 0)
	local sail = rgb(250, 244, 228)
	-- mâts
	kit.Part(ship, 49, 10, 4, 62, rgb(120, 80, 50), { Radius = 2, Z = 1 })
	kit.Part(ship, 24, 30, 3, 42, rgb(120, 80, 50), { Radius = 2, Z = 1 })
	-- voiles gonflées (rayées de rouge) + foc triangulaire
	local top = kit.Part(ship, 36, 16, 30, 20, sail, { Radius = 9, Z = 2, Shine = true })
	kit.Box(top, 0, 8, 30, 4, RED, 0.1, 2)
	local main = kit.Part(ship, 30, 38, 42, 26, sail, { Radius = 12, Z = 2, Shine = true })
	kit.Box(main, 0, 8, 42, 4, RED, 0.1, 2)
	kit.Box(main, 0, 16, 42, 4, RED, 0.1, 2)
	local back = kit.Part(ship, 12, 38, 24, 22, sail, { Radius = 9, Z = 2 })
	kit.Box(back, 0, 9, 24, 4, RED, 0.1, 2)
	kit.Triangle(ship, 84, 30, 22, 34, sail, 2)
	kit.Line(ship, 51, 14, 92, 62, 1, rgb(120, 80, 50), 0.2, 1)
	-- drapeau pirate (tête de mort mignonne) en haut du grand mât
	local flag = kit.Part(ship, 53, 6, 20, 13, DARKER, { Radius = 2, Z = 3 })
	local skull = kit.Blob(flag, 10, 5.5, 8, 7, WHITE, { Z = 2, Outline = false })
	kit.Circle(skull, 2.5, 3, 2, 2, DARKER, 0, 2)
	kit.Circle(skull, 5.5, 3, 2, 2, DARKER, 0, 2)
	kit.Line(flag, 5, 10, 15, 12, 1.2, WHITE, 0, 2)
	kit.Line(flag, 15, 10, 5, 12, 1.2, WHITE, 0, 2)
	-- coque (proue relevée)
	kit.Triangle(ship, 90, 58, 14, 14, rgb(150, 96, 60), 3)
	local hull = kit.Part(ship, 6, 62, 86, 18, rgb(150, 96, 60), { Radius = 9, Z = 4, Shine = true })
	kit.Box(hull, 4, 4, 78, 3, C.Gold, 0, 2)
	for index = 0, 3 do
		kit.Circle(hull, 18 + index * 16, 11, 5, 5, DARKER, 0, 2) -- hublots
	end
	kit.Part(ship, 2, 56, 18, 10, rgb(150, 96, 60), { Radius = 3, Z = 3 }) -- château arrière
	return nil
end

-- Coffre au trésor ouvert (pièces d'or, gemmes, étincelles)
Art.PirateChest = function(body, kit, _item)
	local C = kit.C
	local wood = rgb(170, 110, 70)
	-- couvercle ouvert (derrière)
	local lid = kit.Part(body, 10, 18, 80, 28, wood, { Radius = 14, Z = 1, Shine = true })
	kit.Box(lid, 36, 0, 8, 28, C.Gold, 0, 2)
	-- trésor
	for index = 0, 6 do
		local coin = kit.Blob(body, 18 + index * 11, 48 - (index % 3) * 4, 14, 12, C.Gold, { Z = 2, Shine = true })
		kit.Text(coin, "$", 7, 6, 7, rgb(180, 130, 40), 2)
	end
	kit.Diamond(body, 36, 40, 10, RED, 0, 3)
	kit.Diamond(body, 62, 38, 9, CYAN, 0, 3)
	kit.Blob(body, 50, 34, 12, 12, rgb(160, 255, 170), { Z = 3, Shine = true })
	-- caisse
	local chest = kit.Part(body, 8, 50, 84, 46, wood, { Radius = 8, Z = 4, Shine = true })
	for _, x in ipairs({ 8, 68 }) do
		kit.Box(chest, x, 0, 8, 46, C.Gold, 0, 2)
	end
	kit.Box(chest, 0, 18, 84, 4, kit.Darken(wood, 0.25), 0, 2)
	local lock = kit.Part(chest, 34, 8, 16, 16, C.Gold, { Radius = 4, Z = 3, Shine = true })
	kit.Circle(lock, 8, 7, 4, 4, DARKER, 0, 2)
	kit.Box(lock, 7, 8, 2, 5, DARKER, 0, 2)
	for index, p in ipairs({ { 20, 22 }, { 80, 26 }, { 52, 14 } }) do
		local s = kit.Sparkle(body, p[1], p[2], 10, C.Butter, 0, 6)
		kit.Animate(s, "Pulse", 0.7, 1.5, index)
	end
	return { Glow = C.Butter }
end

-- Maquette de fusée sur sa tour de lancement (fumée au décollage)
Art.RocketModel = function(body, kit, _item)
	local C = kit.C
	-- tour de lancement
	kit.Part(body, 72, 12, 8, 80, RED, { Radius = 2, Z = 1 })
	for index = 0, 5 do
		kit.Line(body, 72, 16 + index * 12, 80, 26 + index * 12, 1.5, kit.Darken(RED, 0.3), 0, 2)
	end
	kit.Part(body, 58, 36, 16, 4, STEEL, { Radius = 2, Z = 2 })
	kit.Part(body, 10, 88, 80, 10, STEEL, { Radius = 4, Z = 1, Shine = true })
	-- fumée
	for index, p in ipairs({ { 30, 88, 20 }, { 54, 90, 18 }, { 42, 94, 24 } }) do
		local puff = kit.Blob(body, p[1], p[2], p[3], p[3] * 0.7, WHITE, { Z = 5, Outline = rgb(220, 220, 232) })
		kit.Animate(puff, "Breathe", 0.08, 2, index)
	end
	-- fusée
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(body, 42 + side * 14 - 6, 64, 12, 22, RED, { Radius = 4, Z = 2, Rotation = side * 16 })
	end
	local rocket = kit.Part(body, 32, 20, 24, 64, WHITE, { Radius = 12, Z = 3, Shine = true })
	kit.Box(rocket, 0, 40, 24, 5, RED, 0, 2)
	local window = kit.Blob(rocket, 12, 20, 12, 12, CYAN, { Z = 3, Outline = STEEL, Thickness = 2 })
	kit.Shine(window, 2, 2, 4, 3, 2, 0.3)
	kit.Triangle(body, 44, 4, 22, 22, RED, 4)
	local flame = kit.Blob(body, 44, 88, 10, 12, ORANGE, { Z = 4, Outline = false })
	kit.Animate(flame, "Flicker", 0.4, 1, 0)
	kit.Sparkle(body, 16, 20, 10, C.Butter, 0, 6)
	return nil
end

-- Télescope d'observatoire (gros tube blanc, pied, chercheur, cadrans)
Art.Observatory = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 26, 86, 48, 12, DARK, { Radius = 5, Z = 1, Shine = true })
	kit.Part(body, 44, 50, 12, 40, STEEL, { Radius = 4, Z = 2, Shine = true })
	kit.Blob(body, 50, 50, 22, 22, DARK, { Z = 3 })
	local tube = kit.Part(body, 6, 26, 84, 26, WHITE, { Radius = 12, Z = 4, Shine = true, Rotation = -28 })
	kit.Box(tube, 22, 0, 6, 26, NAVY, 0, 2)
	kit.Box(tube, 60, 0, 6, 26, NAVY, 0, 2)
	kit.Part(body, 78, 0, 18, 32, DARK, { Radius = 6, Z = 5, Rotation = -28 }) -- pare-soleil
	kit.Part(body, 22, 16, 30, 7, STEEL, { Radius = 3, Z = 5, Rotation = -28 }) -- chercheur
	local dial = kit.Circle(body, 50, 50, 10, 10, C.Gold, 0, 6)
	kit.Box(dial, 4.4, 1, 1.2, 4, DARKER, 0, 2)
	for index, p in ipairs({ { 14, 8 }, { 88, 46 }, { 30, 70 } }) do
		local s = kit.Sparkle(body, p[1], p[2], 10, index == 2 and CYAN or C.Butter, 0, 7)
		kit.Animate(s, "Pulse", 0.7, 1, index)
	end
	return nil
end

-- Statue d'astronaute sur un rocher lunaire (salue, drapeau étoile)
Art.AstronautStatue = function(body, kit, _item)
	local C = kit.C
	kit.Blob(body, 50, 90, 92, 20, rgb(200, 196, 220), { Z = 1, Shine = true })
	kit.Circle(body, 30, 90, 12, 5, rgb(170, 166, 196), 0, 2)
	-- drapeau
	kit.Line(body, 84, 84, 84, 26, 2, STEEL, 0, 2)
	local flag = kit.Part(body, 84, 26, 16, 12, BLUE, { Radius = 2, Z = 2 })
	kit.Sparkle(flag, 8, 6, 8, WHITE, 0, 2)
	kit.Animate(flag, "Sway", 3, 1.5, 0)
	-- sac à dos, corps, jambes
	kit.Part(body, 28, 42, 44, 34, CHROME, { Radius = 8, Z = 3 })
	local suit = kit.Part(body, 32, 44, 36, 36, WHITE, { Radius = 12, Z = 4, Shine = true })
	local panel = kit.Part(suit, 10, 10, 16, 10, NAVY, { Radius = 3, Z = 2 })
	for index, color in ipairs({ RED, C.Butter, CYAN }) do
		kit.Circle(panel, 3 + (index - 1) * 5, 5, 3, 3, color, 0, 2)
	end
	for _, x in ipairs({ 36, 52 }) do
		kit.Part(body, x, 74, 12, 16, WHITE, { Radius = 5, Z = 3 })
		kit.Part(body, x - 1, 86, 14, 6, STEEL, { Radius = 3, Z = 4 })
	end
	-- bras qui salue
	local arm = kit.Pivot(body, 66, 50, 5)
	kit.Part(arm, 0, -22, 10, 24, WHITE, { Radius = 5, Z = 1 })
	kit.Blob(arm, 5, -24, 12, 12, STEEL, { Z = 2 })
	kit.Animate(arm, "Sway", 12, 1.6, 0)
	kit.Part(body, 22, 50, 12, 22, WHITE, { Radius = 5, Z = 3, Rotation = 12 })
	-- casque
	local helmet = kit.Blob(body, 50, 30, 40, 36, WHITE, { Z = 6, Shine = true })
	local visor = kit.Part(helmet, 6, 8, 28, 20, rgb(40, 50, 100), { Radius = 10, Z = 2 })
	kit.Gradient(visor, rgb(90, 120, 220), rgb(30, 30, 80), 90)
	kit.Face(visor, 14, 11, 16, { Eyes = "happy", Mouth = "smile", Color = WHITE, Blush = false, Z = 3 })
	kit.Shine(visor, 3, 2, 8, 4, 4, 0.4)
	return nil
end

-- Squelette de T-rex (musée : os crème sur un socle avec plaque)
Art.DinoSkeleton = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 4, 88, 92, 10, DARK, { Radius = 4, Z = 1, Shine = true })
	local plaque = kit.Part(body, 38, 90, 24, 6, C.Gold, { Radius = 2, Z = 2 })
	local _ = plaque
	-- supports
	kit.Line(body, 40, 88, 42, 56, 2, STEEL, 0, 1)
	kit.Line(body, 70, 88, 64, 50, 2, STEEL, 0, 1)
	-- colonne vertébrale (queue -> cou)
	local spine = { { 4, 70 }, { 16, 62 }, { 28, 56 }, { 40, 52 }, { 52, 50 }, { 62, 46 }, { 70, 38 }, { 74, 30 } }
	for index = 1, #spine - 1 do
		kit.Line(body, spine[index][1], spine[index][2], spine[index + 1][1], spine[index + 1][2], 3, BONE, 0, 3)
		kit.Blob(body, spine[index][1], spine[index][2], 7, 6, BONE, { Z = 4, Thickness = 1.1 })
	end
	-- côtes
	for index = 0, 3 do
		local x = 44 + index * 6
		kit.Blob(body, x, 62, 6, 22 - index * 2, BONE, { Z = 2, T = 1, Outline = BONE, Thickness = 2.2, Shade = false })
	end
	-- pattes
	kit.Line(body, 46, 58, 40, 76, 4, BONE, 0, 3)
	kit.Line(body, 40, 76, 44, 88, 3.5, BONE, 0, 3)
	kit.Line(body, 58, 56, 60, 76, 4, BONE, 0, 3)
	kit.Line(body, 60, 76, 56, 88, 3.5, BONE, 0, 3)
	kit.Line(body, 68, 44, 74, 52, 2, BONE, 0, 3) -- petit bras
	kit.Line(body, 74, 30, 72, 26, 3, BONE, 0, 3) -- cou
	-- crâne
	local skull = kit.Part(body, 64, 12, 34, 20, BONE, { Radius = 8, Z = 5, Shine = true })
	kit.Circle(skull, 12, 8, 7, 7, DARK, 0, 2)
	kit.Part(skull, 10, 14, 24, 5, DARK, { Radius = 2, Z = 2, Outline = false })
	for index = 0, 3 do
		kit.TriangleDown(skull, 14 + index * 5, 14, 3.5, 4, WHITE, 3)
	end
	local jaw = kit.Part(body, 68, 32, 28, 6, BONE, { Radius = 3, Z = 5 })
	kit.Animate(jaw, "Bob", 1, 1.4, 0)
	return nil
end

-- Robot géant (mech bleu et blanc, visière lumineuse, cœur d'énergie)
Art.MechRobot = function(body, kit, _item)
	local C = kit.C
	local white = rgb(240, 244, 252)
	-- jambes
	for _, x in ipairs({ 30, 56 }) do
		kit.Part(body, x, 64, 14, 26, STEEL, { Radius = 4, Z = 1 })
		kit.Part(body, x - 4, 86, 22, 12, BLUE, { Radius = 5, Z = 2, Shine = true })
	end
	-- bras
	for index, side in ipairs({ -1, 1 }) do
		local arm = kit.Pivot(body, 50 + side * 30, 36, 3)
		kit.Part(arm, -8, 0, 16, 34, white, { Radius = 7, Z = 1, Shine = true })
		kit.Blob(arm, 0, 38, 18, 16, BLUE, { Z = 2 })
		kit.Animate(arm, "Sway", 5, 1, index * 1.5)
		kit.Blob(body, 50 + side * 30, 36, 20, 20, BLUE, { Z = 4, Shine = true }) -- épaule
	end
	-- torse + cœur d'énergie
	local torso = kit.Part(body, 26, 30, 48, 40, white, { Radius = 10, Z = 5, Shine = true })
	kit.Box(torso, 0, 30, 48, 4, BLUE, 0, 2)
	local core = kit.Circle(torso, 24, 16, 16, 16, CYAN, 0, 3)
	kit.Stroke(core, BLUE, 2, 0)
	kit.Animate(core, "Pulse", 0.5, 1.6, 0)
	kit.Circle(torso, 24, 16, 7, 7, WHITE, 0.1, 4)
	-- tête + visière + antenne
	kit.Line(body, 50, 12, 50, 2, 2, STEEL, 0, 5)
	local tip = kit.Circle(body, 50, 2, 6, 6, RED, 0, 6)
	kit.Animate(tip, "Pulse", 0.6, 2, 0)
	local head = kit.Part(body, 34, 8, 32, 24, white, { Radius = 8, Z = 6, Shine = true })
	local visor = kit.Part(head, 4, 7, 24, 10, DARKER, { Radius = 5, Z = 2 })
	for _, x in ipairs({ 7, 17 }) do
		local eye = kit.Box(visor, x - 3, 3, 6, 4, CYAN, 0, 2)
		kit.Round(eye, 2)
		kit.Animate(eye, "Pulse", 0.4, 1.2, x)
	end
	kit.Sparkle(body, 12, 16, 10, C.Butter, 0, 7)
	return { Glow = CYAN }
end

return Art
