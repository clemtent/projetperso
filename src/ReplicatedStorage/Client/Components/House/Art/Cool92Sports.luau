--[[
	Cool92Sports (ModuleScript) — (v9.2) sport 🏀 et véhicules 🏎️
	(haltères, panier de ballons, skates, panier de basket, cage de foot,
	maillot encadré, sac de frappe, surf, BMX, étagère à trophées, voiture
	télécommandée, garage à petites voitures, tapis circuit, moto chromée)
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Cool92Sports
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
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
local BALL = rgb(250, 140, 60)
local STEEL = rgb(176, 186, 206)
local CHROME = rgb(214, 222, 236)
local BLUE = rgb(80, 150, 255)
local GREEN = rgb(96, 196, 110)

----------------------------------------------------------------------
-- Petits outils
----------------------------------------------------------------------

-- Ballon de basket (coutures noires)
local function basketball(kit, parent, cx, cy, d, z)
	local ball = kit.Blob(parent, cx, cy, d, d, BALL, { Z = z, Shine = true })
	local seam = kit.Darken(BALL, 0.55)
	kit.Box(ball, d / 2 - 0.6, 1, 1.2, d - 2, seam, 0, 2)
	kit.Box(ball, 1, d / 2 - 0.6, d - 2, 1.2, seam, 0, 2)
	local arc = kit.Blob(ball, d * 0.08, d / 2, d * 0.5, d * 0.9, BALL, { Z = 2, T = 1, Outline = seam, Thickness = 1.1, Shade = false })
	local arc2 = kit.Blob(ball, d * 0.92, d / 2, d * 0.5, d * 0.9, BALL, { Z = 2, T = 1, Outline = seam, Thickness = 1.1, Shade = false })
	local _ = arc
	local _2 = arc2
	return ball
end

-- Ballon de foot (blanc à pentagones)
local function football(kit, parent, cx, cy, d, z)
	local ball = kit.Blob(parent, cx, cy, d, d, WHITE, { Z = z, Shine = true })
	kit.Diamond(ball, d / 2, d / 2, d * 0.26, DARK, 0, 2)
	for _, p in ipairs({ { 0.16, 0.3 }, { 0.84, 0.3 }, { 0.28, 0.86 }, { 0.72, 0.86 }, { 0.5, 0.06 } }) do
		kit.Circle(ball, d * p[1], d * p[2], d * 0.2, d * 0.2, DARK, 0, 2)
	end
	return ball
end

-- Roue à rayons qui tourne ; (cx, cy) centre, d diamètre
local function wheel(kit, parent, cx, cy, d, tire, rim, z, speed)
	local w = kit.Blob(parent, cx, cy, d, d, tire, { Z = z })
	kit.Circle(w, d / 2, d / 2, d * 0.72, d * 0.72, rim, 0, 2)
	kit.Circle(w, d / 2, d / 2, d * 0.56, d * 0.56, kit.Darken(rim, 0.25), 0.4, 3)
	local spokes = kit.Pivot(w, d / 2, d / 2, 4)
	for index = 0, 3 do
		local spoke = kit.Box(spokes, -0.6, -d * 0.34, 1.2, d * 0.68, rim, 0, 1)
		spoke.Rotation = index * 45
	end
	kit.Circle(w, d / 2, d / 2, d * 0.18, d * 0.18, CHROME, 0, 5)
	kit.Animate(spokes, "Spin", 1, speed or 0.4, cx)
	return w
end

-- Rangée de flammes (langues orange + cœur jaune) dans la zone (x, y, w, h)
local function flames(kit, parent, x, y, w, h, z)
	local C = kit.C
	local n = 3
	local step = w / n
	for k = 0, n - 1 do
		local cx = x + step * (k + 0.5)
		local th = h * (k == 1 and 1 or 0.74)
		kit.Circle(parent, cx, y + h - step * 0.35, step * 1.15, step * 0.85, ORANGE, 0, z)
		kit.Triangle(parent, cx, y + h - th, step * 1.05, th - step * 0.3, ORANGE, z, 0, 8)
		kit.Circle(parent, cx, y + h - step * 0.3, step * 0.6, step * 0.5, C.Butter, 0, z + 1)
		kit.Triangle(parent, cx, y + h - th * 0.58, step * 0.55, th * 0.5, C.Butter, z + 1, 0, 6)
	end
end

----------------------------------------------------------------------
-- 🏀 Sport
----------------------------------------------------------------------

-- Deux haltères (poids bleus et orange, poignée chromée)
Art.Dumbbells = function(body, kit, _item)
	local function dumbbell(cx, cy, w, color, z)
		kit.Part(body, cx - w * 0.3, cy - 3, w * 0.6, 6, CHROME, { Radius = 3, Z = z })
		for _, side in ipairs({ -1, 1 }) do
			kit.Part(body, cx + side * w * 0.36 - w * 0.08, cy - w * 0.2, w * 0.16, w * 0.4, color, { Radius = 4, Z = z + 1, Shine = true })
			kit.Part(body, cx + side * w * 0.48 - w * 0.05, cy - w * 0.14, w * 0.1, w * 0.28, kit.Darken(color, 0.15), { Radius = 3, Z = z + 1 })
		end
	end
	dumbbell(46, 86, 70, BLUE, 2)
	dumbbell(54, 62, 62, ORANGE, 5)
	kit.Sparkle(body, 86, 46, 10, CYAN, 0, 8)
	return nil
end

-- Panier en fil de fer plein de ballons (basket, foot, tennis, rugby)
Art.SportsBallBin = function(body, kit, _item)
	local C = kit.C
	basketball(kit, body, 32, 40, 30, 1)
	football(kit, body, 64, 38, 28, 1)
	local tennis = kit.Blob(body, 48, 30, 18, 18, rgb(210, 240, 90), { Z = 2, Shine = true })
	kit.Blob(tennis, 2, 9, 12, 16, rgb(210, 240, 90), { Z = 2, T = 1, Outline = WHITE, Thickness = 1.2, Shade = false })
	local rugby = kit.Blob(body, 80, 44, 26, 16, rgb(170, 100, 70), { Z = 2, Shine = true, Rotation = -30 })
	kit.Box(rugby, 8, 7, 10, 1.5, WHITE, 0, 2)
	-- panier grillagé
	local basket = kit.Part(body, 12, 48, 76, 50, STEEL, { Radius = 8, Z = 3, T = 0.35 })
	for index = 1, 6 do
		kit.Box(basket, index * 10.8, 2, 1.5, 46, CHROME, 0, 2)
	end
	for index = 1, 3 do
		kit.Box(basket, 2, index * 12, 72, 1.5, CHROME, 0, 2)
	end
	kit.Part(body, 8, 44, 84, 8, CHROME, { Radius = 4, Z = 4, Shine = true })
	for _, x in ipairs({ 18, 76 }) do
		kit.Blob(body, x, 97, 10, 6, DARK, { Z = 4 })
	end
	local _ = C
	return nil
end

-- Présentoir mural à skateboards (3 planches décorées)
Art.SkateRack = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 4, 44, 92, 10, rgb(170, 120, 86), { Radius = 3, Z = 1, Shine = true })
	for index = 0, 2 do
		local x = 12 + index * 28
		kit.Part(body, x + 7, 42, 4, 14, STEEL, { Radius = 2, Z = 5 }) -- crochet
		local deck = kit.Part(body, x, 8, 20, 84, ({ DARK, RED, BLUE })[index + 1], { Radius = 10, Z = 3, Shine = true })
		if index == 0 then
			-- flammes
			kit.Box(deck, 0, 74, 20, 10, ORANGE, 0, 2)
			flames(kit, deck, 1, 46, 18, 30, 2)
		elseif index == 1 then
			-- étoiles
			for k = 0, 2 do
				kit.Sparkle(deck, 10, 18 + k * 22, 12, WHITE, 0, 2)
			end
		else
			-- bandes
			for k = 0, 3 do
				kit.Box(deck, 0, 16 + k * 16, 20, 5, CYAN, 0.1, 2)
			end
		end
		-- roues (vues de dos)
		for _, y in ipairs({ 16, 66 }) do
			kit.Box(deck, 2, y, 16, 2.5, STEEL, 0, 4)
			kit.Circle(deck, 1, y + 1, 5, 5, C.Butter, 0, 5)
			kit.Circle(deck, 19, y + 1, 5, 5, C.Butter, 0, 5)
		end
	end
	return { WallShadow = Vector2.new(92, 86) }
end

-- Panier de basket sur pied (panneau, cercle orange, filet, ballon qui rebondit)
Art.BasketHoop = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 22, 84, 44, 14, DARK, { Radius = 7, Z = 1, Shine = true }) -- lest
	kit.Part(body, 38, 20, 7, 68, STEEL, { Radius = 3, Z = 2, Shine = true })
	kit.Line(body, 44, 26, 58, 18, 5, STEEL, 0, 2)
	-- panneau
	local board = kit.Part(body, 50, 2, 48, 34, WHITE, { Radius = 4, Z = 3, Shine = true })
	kit.Stroke(board, NAVY, 2, 0)
	local square = kit.Part(board, 15, 14, 18, 14, WHITE, { Radius = 1, Z = 2, Outline = RED, Thickness = 2, Shade = false })
	local _ = square
	-- cercle + filet
	kit.Part(body, 60, 32, 28, 4, ORANGE, { Radius = 2, Z = 5 })
	for index = 0, 4 do
		local x = 62 + index * 6
		kit.Line(body, x, 36, 64 + index * 5, 52, 1.2, WHITE, 0.1, 4)
	end
	kit.Line(body, 63, 44, 85, 44, 1.2, WHITE, 0.1, 4)
	kit.Line(body, 64, 51, 84, 51, 1.2, WHITE, 0.1, 4)
	-- ballon qui rebondit
	local bouncer = kit.Group(body, 0, 0, 100, 100, 6)
	basketball(kit, bouncer, 78, 78, 20, 1)
	kit.Animate(bouncer, "Bob", 4, 2.2, 0)
	kit.Blob(body, 78, 97, 16, 4, DARKER, { Z = 1, Outline = false, Shade = false, T = 0.6 })
	local _c = C
	return nil
end

-- Mini cage de foot (poteaux blancs, filet, ballon)
Art.FootballGoal = function(body, kit, _item)
	local net = kit.Group(body, 10, 20, 80, 76, 1)
	for index = 0, 8 do
		kit.Box(net, index * 10, 0, 1.2, 76, WHITE, 0.35, 1)
	end
	for index = 0, 7 do
		kit.Box(net, 0, index * 10, 80, 1.2, WHITE, 0.35, 1)
	end
	kit.Part(body, 6, 16, 88, 7, WHITE, { Radius = 3, Z = 3, Shine = true, Outline = STEEL })
	for _, x in ipairs({ 6, 87 }) do
		kit.Part(body, x, 16, 7, 84, WHITE, { Radius = 3, Z = 3, Shine = true, Outline = STEEL })
	end
	for index = 0, 3 do
		kit.Box(body, 7, 26 + index * 18, 5, 6, RED, 0, 4) -- bandes rouges
		kit.Box(body, 88, 26 + index * 18, 5, 6, RED, 0, 4)
	end
	local ball = kit.Group(body, 0, 0, 100, 100, 5)
	football(kit, ball, 50, 86, 22, 1)
	kit.Animate(ball, "Drift", 3, 1, 0)
	kit.Blob(body, 50, 98, 20, 4, DARKER, { Z = 2, Outline = false, Shade = false, T = 0.6 })
	return nil
end

-- Maillot encadré (numéro 10, bandes)
Art.JerseyFrame = function(body, kit, _item)
	local C = kit.C
	local frame = kit.Part(body, 8, 6, 84, 88, DARK, { Radius = 4, Z = 1, Shine = true })
	kit.Part(frame, 5, 5, 74, 78, rgb(236, 240, 248), { Radius = 2, Z = 2, Outline = false })
	-- maillot : manches, corps, col
	for _, side in ipairs({ -1, 1 }) do
		kit.Part(body, 50 + side * 28 - 10, 22, 20, 18, BLUE, { Radius = 5, Z = 3, Rotation = side * 30 })
	end
	local shirt = kit.Part(body, 28, 18, 44, 62, BLUE, { Radius = 8, Z = 4, Shine = true })
	kit.Box(shirt, 0, 44, 44, 5, WHITE, 0, 2)
	kit.Box(shirt, 0, 51, 44, 3, RED, 0, 2)
	kit.Blob(shirt, 22, 2, 16, 10, rgb(236, 240, 248), { Z = 3 })
	kit.Text(shirt, "10", 22, 24, 22, WHITE, 3)
	kit.Sparkle(body, 22, 84, 8, C.Butter, 0, 5)
	-- petite plaque dorée
	kit.Part(body, 38, 84, 24, 5, C.Gold, { Radius = 2, Z = 5 })
	return { WallShadow = Vector2.new(84, 88) }
end

-- Sac de frappe sur potence (se balance), gants
Art.BoxingBag = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 8, 8, 8, 90, DARK, { Radius = 3, Z = 1, Shine = true })
	kit.Part(body, 2, 92, 30, 8, DARKER, { Radius = 3, Z = 2 })
	kit.Part(body, 8, 8, 64, 7, DARK, { Radius = 3, Z = 1 })
	local swing = kit.Pivot(body, 60, 14, 3)
	kit.Line(swing, 0, 0, -6, 12, 1.5, STEEL, 0, 1)
	kit.Line(swing, 0, 0, 6, 12, 1.5, STEEL, 0, 1)
	local bag = kit.Part(swing, -16, 12, 32, 66, RED, { Radius = 14, Z = 2, Shine = true })
	kit.Box(bag, 0, 12, 32, 5, DARKER, 0, 2)
	kit.Box(bag, 0, 50, 32, 5, DARKER, 0, 2)
	kit.Sparkle(bag, 16, 32, 12, WHITE, 0.1, 3)
	kit.Animate(swing, "Sway", 4, 1.2, 0)
	-- gants accrochés au poteau
	for index = 0, 1 do
		local glove = kit.Blob(body, 18 + index * 9, 52 + index * 6, 14, 16, BLUE, { Z = 4 + index, Shine = true })
		kit.Box(glove, 2, 11, 10, 4, WHITE, 0, 2)
	end
	local _ = C
	return nil
end

-- Planche de surf sur son support (vague, aileron)
Art.Surfboard = function(body, kit, _item)
	local C = kit.C
	kit.Part(body, 26, 84, 48, 12, rgb(170, 120, 86), { Radius = 4, Z = 1, Shine = true })
	local board = kit.Part(body, 34, 4, 32, 90, WHITE, { Radius = 16, Z = 2, Shine = true, Rotation = 6 })
	kit.Box(board, 14.5, 4, 3, 82, rgb(170, 120, 86), 0.3, 2) -- latte centrale
	local wave = kit.Part(board, 0, 36, 32, 22, CYAN, { Radius = 0, Z = 3, Outline = false })
	for index = 0, 2 do
		kit.Circle(wave, 5 + index * 11, 0, 12, 10, WHITE, 0, 2)
	end
	kit.Box(board, 0, 62, 32, 6, ORANGE, 0, 3)
	kit.Circle(board, 16, 20, 12, 12, C.Butter, 0, 3) -- soleil
	kit.Triangle(body, 50, 84, 12, 10, NAVY, 3) -- aileron
	return nil
end

-- BMX (roues qui tournent, cadre vert néon, guidon)
Art.BMXBike = function(body, kit, _item)
	local frameColor = rgb(120, 230, 120)
	wheel(kit, body, 22, 72, 40, DARKER, STEEL, 1)
	wheel(kit, body, 78, 72, 40, DARKER, STEEL, 1)
	-- cadre
	kit.Line(body, 22, 72, 46, 72, 4, frameColor, 0, 3)
	kit.Line(body, 46, 72, 38, 46, 4, frameColor, 0, 3)
	kit.Line(body, 38, 46, 70, 46, 4, frameColor, 0, 3)
	kit.Line(body, 46, 72, 70, 46, 4, frameColor, 0, 3)
	kit.Line(body, 70, 46, 78, 72, 4, frameColor, 0, 3)
	kit.Line(body, 22, 72, 38, 46, 3, frameColor, 0, 3)
	-- selle, guidon, pédalier, repose-pieds
	kit.Line(body, 38, 46, 36, 38, 3, STEEL, 0, 3)
	kit.Part(body, 26, 32, 20, 7, DARK, { Radius = 3, Z = 4, Shine = true })
	kit.Line(body, 70, 46, 66, 26, 3, STEEL, 0, 4)
	kit.Line(body, 58, 26, 76, 22, 4, DARK, 0, 5)
	kit.Blob(body, 46, 72, 12, 12, CHROME, { Z = 4 })
	kit.Line(body, 46, 72, 52, 84, 2.5, STEEL, 0, 4)
	kit.Part(body, 50, 82, 10, 4, DARK, { Radius = 2, Z = 5 })
	kit.Part(body, 76, 68, 10, 6, STEEL, { Radius = 2, Z = 5 }) -- repose-pied
	return nil
end

-- Étagère à trophées (coupe d'or, médaille, ballon doré, plaque étoile)
Art.TrophyShelf = function(body, kit, _item)
	local C = kit.C
	local wood = rgb(160, 110, 78)
	kit.Part(body, 4, 66, 92, 8, wood, { Radius = 3, Z = 1, Shine = true })
	for _, x in ipairs({ 12, 80 }) do
		kit.Triangle(body, x + 4, 74, 8, 12, kit.Darken(wood, 0.2), 1) -- équerres
	end
	-- coupe d'or
	kit.Part(body, 12, 56, 26, 10, DARK, { Radius = 2, Z = 2 })
	kit.Part(body, 21, 44, 8, 14, C.Gold, { Radius = 3, Z = 2 })
	local cup = kit.Part(body, 10, 16, 30, 30, C.Gold, { Radius = 12, Z = 3, Shine = true })
	kit.Text(cup, "1", 15, 14, 16, rgb(160, 110, 40), 2)
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(body, 25 + side * 17, 26, 10, 14, C.Gold, { Z = 2, T = 1, Outline = C.Gold, Thickness = 3, Shade = false })
	end
	-- ballon doré sur socle
	kit.Part(body, 44, 58, 20, 8, DARK, { Radius = 2, Z = 2 })
	local ball = kit.Blob(body, 54, 46, 20, 20, C.Gold, { Z = 3, Shine = true })
	kit.Box(ball, 9.4, 1, 1.2, 18, rgb(180, 130, 40), 0, 2)
	kit.Box(ball, 1, 9.4, 18, 1.2, rgb(180, 130, 40), 0, 2)
	-- médaille d'argent sur ruban
	kit.Line(body, 76, 30, 82, 46, 4, RED, 0, 2)
	kit.Line(body, 88, 30, 82, 46, 4, BLUE, 0, 2)
	local medal = kit.Blob(body, 82, 52, 16, 16, CHROME, { Z = 3, Shine = true })
	kit.Sparkle(medal, 8, 8, 9, WHITE, 0, 2)
	-- étincelles
	for index, p in ipairs({ { 8, 12 }, { 46, 30 }, { 94, 20 } }) do
		local s = kit.Sparkle(body, p[1], p[2], 8, C.Butter, 0, 5)
		kit.Animate(s, "Pulse", 0.6, 1.2, index)
	end
	return { WallShadow = Vector2.new(92, 20) }
end

----------------------------------------------------------------------
-- 🏎️ Véhicules
----------------------------------------------------------------------

-- Monster truck télécommandé (grosses roues) + sa télécommande
Art.RCCar = function(body, kit, _item)
	local C = kit.C
	-- télécommande (derrière)
	local remote = kit.Part(body, 70, 34, 26, 30, DARK, { Radius = 6, Z = 1, Shine = true })
	kit.Line(body, 90, 34, 96, 8, 2, STEEL, 0, 1)
	kit.Circle(body, 96, 8, 4, 4, RED, 0, 1)
	kit.Circle(remote, 8, 12, 8, 8, DARKER, 0, 2)
	kit.Circle(remote, 18, 20, 8, 8, DARKER, 0, 2)
	-- carrosserie
	local cab = kit.Part(body, 22, 36, 38, 22, ORANGE, { Radius = 8, Z = 3, Shine = true })
	kit.Part(cab, 6, 4, 26, 10, rgb(170, 220, 255), { Radius = 4, Z = 2 })
	local car = kit.Part(body, 6, 50, 70, 22, ORANGE, { Radius = 8, Z = 4, Shine = true })
	flames(kit, car, 30, 2, 24, 16, 2)
	kit.Circle(car, 66, 8, 6, 6, C.Butter, 0, 3) -- phare
	-- grosses roues
	for _, x in ipairs({ 20, 62 }) do
		local w = kit.Blob(body, x, 80, 28, 28, DARKER, { Z = 5 })
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			kit.Box(w, 14 + math.cos(a) * 12 - 2, 14 + math.sin(a) * 12 - 2, 4, 4, DARK, 0, 2)
		end
		local hub = kit.Circle(w, 14, 14, 12, 12, STEEL, 0, 3)
		local _ = hub
	end
	return nil
end

-- Garage à petites voitures (2 étages, rampe, ascenseur, voitures)
Art.ToyGarage = function(body, kit, _item)
	local C = kit.C
	local base = kit.Part(body, 4, 84, 92, 14, rgb(90, 96, 116), { Radius = 5, Z = 1, Shine = true })
	for index = 0, 3 do
		kit.Box(base, 10 + index * 22, 6, 10, 2, WHITE, 0.2, 2) -- marquage
	end
	-- étage + piliers
	for _, x in ipairs({ 10, 84 }) do
		kit.Part(body, x, 44, 6, 42, RED, { Radius = 2, Z = 2 })
	end
	kit.Part(body, 6, 40, 70, 8, rgb(236, 240, 248), { Radius = 3, Z = 3, Shine = true })
	-- rampe
	kit.Part(body, 50, 60, 52, 7, BLUE, { Radius = 3, Z = 4, Rotation = -22 })
	-- tour + ascenseur + panneau
	kit.Part(body, 76, 8, 16, 78, rgb(236, 240, 248), { Radius = 4, Z = 2 })
	local lift = kit.Part(body, 78, 30, 12, 10, C.Butter, { Radius = 2, Z = 3 })
	kit.Animate(lift, "Bob", 10, 0.8, 0)
	local sign = kit.Part(body, 8, 16, 58, 18, NAVY, { Radius = 5, Z = 3, Shine = true })
	kit.Text(sign, "GARAGE", 29, 9, 11, C.Butter, 2)
	-- voitures
	for _, spec in ipairs({ { 18, 32, RED, 4 }, { 40, 76, rgb(120, 220, 120), 5 }, { 60, 50, BLUE, 5 } }) do
		local car = kit.Part(body, spec[1], spec[2], 18, 8, spec[3], { Radius = 3, Z = spec[4], Shine = true, Thickness = 1.2 })
		kit.Box(car, 5, 1, 8, 3, rgb(200, 235, 255), 0, 2)
		kit.Circle(body, spec[1] + 4, spec[2] + 8, 5, 5, DARKER, 0, spec[4] + 1)
		kit.Circle(body, spec[1] + 14, spec[2] + 8, 5, 5, DARKER, 0, spec[4] + 1)
	end
	return nil
end

-- Tapis circuit (piste grise, ligne de départ à damier, petite voiture)
Art.RaceTrackRug = function(body, kit, _item)
	local C = kit.C
	local rug = kit.Blob(body, 50, 82, 98, 34, GREEN, { Z = 1, Shine = true })
	local track = kit.Blob(rug, 49, 17, 82, 26, rgb(96, 100, 116), { Z = 2, Outline = WHITE, Thickness = 2, Shade = false })
	kit.Blob(track, 41, 13, 46, 10, GREEN, { Z = 2, Outline = WHITE, Thickness = 1.5, Shade = false })
	-- tirets au milieu
	for index = 0, 3 do
		kit.Box(track, 20 + index * 12, 2.5, 6, 1.2, C.Butter, 0, 3)
		kit.Box(track, 20 + index * 12, 22.5, 6, 1.2, C.Butter, 0, 3)
	end
	-- ligne de départ à damier
	for row = 0, 2 do
		for col = 0, 1 do
			kit.Box(track, 68 + col * 2.5, 18 + row * 2.4, 2.5, 2.4, (row + col) % 2 == 0 and WHITE or DARKER, 0, 4)
		end
	end
	local car = kit.Part(rug, 20, 23, 12, 6, RED, { Radius = 3, Z = 5, Thickness = 1 })
	kit.Animate(car, "Drift", 6, 0.8, 0)
	kit.Triangle(rug, 88, 8, 8, 10, C.Butter, 4) -- petit cône
	return { Flat = true }
end

-- Moto chromée (réservoir rouge à flammes, moteur chromé, phare)
Art.Motorbike = function(body, kit, _item)
	local C = kit.C
	wheel(kit, body, 18, 76, 36, DARKER, CHROME, 1, 0.3)
	wheel(kit, body, 82, 76, 36, DARKER, CHROME, 1, 0.3)
	-- fourche + bras oscillant
	kit.Line(body, 82, 76, 70, 34, 4, CHROME, 0, 3)
	kit.Line(body, 18, 76, 44, 66, 4, DARK, 0, 3)
	-- moteur chromé + échappement
	local engine = kit.Part(body, 36, 54, 28, 22, CHROME, { Radius = 6, Z = 4, Shine = true })
	for index = 0, 2 do
		kit.Box(engine, 3, 4 + index * 5, 22, 2, STEEL, 0, 2)
	end
	kit.Line(body, 40, 76, 6, 70, 5, CHROME, 0, 2)
	kit.Blob(body, 6, 70, 8, 8, DARK, { Z = 3 })
	-- réservoir, selle, garde-boue
	local tank = kit.Part(body, 40, 36, 32, 20, RED, { Radius = 10, Z = 5, Shine = true })
	flames(kit, tank, 4, 4, 22, 14, 2)
	kit.Line(body, 18, 76, 28, 48, 4, DARK, 0, 3)
	kit.Part(body, 16, 42, 30, 10, DARKER, { Radius = 5, Z = 5, Shine = true })
	kit.Part(body, 4, 50, 22, 6, RED, { Radius = 3, Z = 2 })
	kit.Part(body, 72, 52, 22, 6, RED, { Radius = 3, Z = 2 })
	-- guidon + phare
	kit.Line(body, 70, 34, 60, 22, 3, CHROME, 0, 6)
	kit.Part(body, 56, 18, 10, 5, DARKER, { Radius = 2, Z = 7 })
	local lamp = kit.Blob(body, 78, 38, 14, 14, CHROME, { Z = 6, Shine = true })
	kit.Circle(lamp, 7, 7, 9, 9, C.Butter, 0, 2)
	return { Glow = rgb(255, 236, 170) }
end

return Art
