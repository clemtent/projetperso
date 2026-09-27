--[[
	Cool92Gaming (ModuleScript) — (v9.2) coin gamer 🎮 + meubles "cool"
	(chaise de course, bureau gamer, pouf, casier, table de briques, lits
	superposés, lit voiture de course)
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Cool92Gaming
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).

	Style : même rendu "autocollant" que le reste (contours doux, reflets),
	mais en couleurs de gamer : bleu nuit, néons cyan / magenta / vert,
	rouge course. Les dessus des tables, sièges et lits sont déclarés dans
	House/HouseSurfaces (mêmes coordonnées).
]]

local Art = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local NAVY = rgb(52, 60, 100)
local DARK = rgb(44, 46, 64)
local DARKER = rgb(30, 32, 46)
local CYAN = rgb(60, 222, 255)
local MAGENTA = rgb(255, 84, 196)
local LIME = rgb(140, 240, 110)
local RED = rgb(236, 66, 76)
local ORANGE = rgb(255, 152, 56)
local STEEL = rgb(176, 186, 206)
local SCREEN = rgb(36, 40, 78)

----------------------------------------------------------------------
-- Petits outils
----------------------------------------------------------------------

-- Manette (vue de face) centrée en (cx, cy), largeur w
local function controller(kit, parent, cx, cy, w, color, z)
	local C = kit.C
	local zz = z or 3
	for _, side in ipairs({ -1, 1 }) do
		kit.Blob(parent, cx + side * w * 0.3, cy + w * 0.14, w * 0.34, w * 0.4, color, { Z = zz, Thickness = 1.2 })
	end
	local pad = kit.Part(parent, cx - w / 2, cy - w * 0.2, w, w * 0.38, color, { Radius = math.floor(w * 0.16), Z = zz + 1, Shine = true, Thickness = 1.3 })
	-- croix directionnelle
	local s = w * 0.06
	kit.Box(pad, w * 0.2 - s * 1.5, w * 0.19 - s / 2, s * 3, s, WHITE, 0.1, 3)
	kit.Box(pad, w * 0.2 - s / 2, w * 0.19 - s * 1.5, s, s * 3, WHITE, 0.1, 3)
	-- boutons
	for index, spec in ipairs({ { 0.8, 0.1, C.Butter }, { 0.88, 0.19, RED }, { 0.72, 0.19, CYAN }, { 0.8, 0.28, LIME } }) do
		kit.Circle(pad, w * spec[1], w * spec[2], s * 1.3, s * 1.3, spec[3], 0, 3)
		local _ = index
	end
	-- sticks
	kit.Circle(pad, w * 0.38, w * 0.27, s * 1.7, s * 1.7, DARKER, 0, 3)
	kit.Circle(pad, w * 0.62, w * 0.27, s * 1.7, s * 1.7, DARKER, 0, 3)
	return pad
end

-- Bande de LED qui respire (cyan -> magenta), ancrée en (x, y)
local function ledStrip(kit, parent, x, y, w, h, z)
	local strip = kit.Box(parent, x, y, w, h, WHITE, 0, z)
	kit.Round(strip)
	kit.Gradient(strip, CYAN, MAGENTA, 0)
	local glow = kit.Box(parent, x - 2, y - 2, w + 4, h + 4, CYAN, 0.7, (z or 2) - 1)
	kit.Round(glow)
	kit.Animate(glow, "Pulse", 0.25, 1.4, x)
	return strip
end

-- Ventilateur RGB (anneau lumineux + pales qui tournent)
local function fan(kit, parent, cx, cy, size, color, z, phase)
	local ring = kit.Circle(parent, cx, cy, size, size, DARKER, 0, z)
	kit.Stroke(ring, color, 2, 0)
	local halo = kit.Circle(parent, cx, cy, size + 4, size + 4, color, 0.75, z - 1)
	kit.Animate(halo, "Pulse", 0.2, 1.2, phase or 0)
	local rotor = kit.Pivot(ring, size / 2, size / 2, 2)
	for index = 0, 2 do
		-- une pale par pivot tourné (les enfants tournent autour du pivot)
		local arm = kit.Pivot(rotor, 0, 0, 1)
		arm.Rotation = index * 120
		local blade = kit.Box(arm, -size * 0.07, -size * 0.42, size * 0.14, size * 0.36, kit.Lighten(color, 0.3), 0.15, 1)
		kit.Round(blade)
	end
	kit.Circle(ring, size / 2, size / 2, size * 0.26, size * 0.26, color, 0, 3)
	kit.Animate(rotor, "Spin", 1, 0.8, phase or 0)
	return ring
end

----------------------------------------------------------------------
-- 🎮 Jeux vidéo
----------------------------------------------------------------------

-- Casque gamer sur son support (oreillettes RGB, micro)
Art.RGBHeadset = function(body, kit, _item)
	kit.Blob(body, 50, 94, 58, 12, DARK, { Z = 1, Shine = true })
	kit.Part(body, 46, 34, 8, 60, STEEL, { Radius = 4, Z = 2, Shine = true })
	kit.Blob(body, 50, 34, 30, 10, STEEL, { Z = 3 })
	-- arceau (moitié haute d'un anneau)
	local clip = kit.Group(body, 14, 8, 72, 40, 4, true)
	local band = kit.Part(clip, 3, 3, 66, 66, DARK, { Radius = -1, T = 1, Outline = DARK, Thickness = 8, Shade = false })
	local _ = band
	local pad = kit.Part(body, 32, 8, 36, 10, NAVY, { Radius = 5, Z = 5, Shine = true })
	kit.Box(pad, 8, 3, 20, 3, CYAN, 0.2, 3)
	-- oreillettes
	for index, side in ipairs({ -1, 1 }) do
		local cx = 50 + side * 34
		local halo = kit.Blob(body, cx, 60, 30, 38, index == 1 and CYAN or MAGENTA, { Z = 5, Outline = false, Shade = false, T = 0.55 })
		kit.Animate(halo, "Pulse", 0.35, 1.6, index * 1.7)
		local cup = kit.Blob(body, cx, 60, 24, 32, DARK, { Z = 6, Shine = true })
		local ring = kit.Blob(cup, 12, 16, 14, 20, DARKER, { Z = 2, Outline = index == 1 and CYAN or MAGENTA, Thickness = 2.5, Shade = false })
		kit.Diamond(ring, 7, 10, 5, index == 1 and CYAN or MAGENTA, 0, 2)
		kit.Line(body, cx, 26, cx, 44, 5, DARK, 0, 4)
	end
	-- micro
	kit.Line(body, 20, 70, 36, 84, 3, DARK, 0, 7)
	kit.Blob(body, 38, 85, 9, 7, DARKER, { Z = 8 })
	local tip = kit.Circle(body, 38, 85, 4, 4, LIME, 0, 9)
	kit.Animate(tip, "Pulse", 0.6, 1.2, 0)
	return { Glow = CYAN }
end

-- Console de salon + deux manettes
Art.ConsoleSet = function(body, kit, _item)
	local C = kit.C
	-- console (boîtier noir, bande lumineuse)
	local console = kit.Part(body, 14, 34, 72, 34, DARK, { Radius = 8, Z = 1, Shine = true })
	kit.Part(console, 4, 4, 64, 10, NAVY, { Radius = 4, Z = 2, Outline = false })
	local light = kit.Box(console, 8, 18, 40, 3, CYAN, 0, 3)
	kit.Round(light)
	kit.Animate(light, "Pulse", 0.5, 1.2, 0)
	kit.Box(console, 52, 18, 10, 3, WHITE, 0.3, 3)
	kit.Circle(console, 62, 26, 6, 6, LIME, 0, 3) -- bouton marche
	for index = 0, 4 do
		kit.Box(console, 8 + index * 6, 26, 3, 4, DARKER, 0, 3) -- aérations
	end
	-- câble
	kit.Line(body, 86, 60, 94, 84, 2, DARKER, 0, 1)
	-- deux manettes posées devant
	local red = controller(kit, body, 30, 82, 38, RED, 4)
	local blue = controller(kit, body, 70, 86, 38, rgb(80, 150, 255), 6)
	blue.Rotation = 8
	red.Rotation = -6
	kit.Sparkle(body, 90, 28, 10, C.Butter, 0, 8)
	return nil
end

-- Enseigne néon "GG" (bon match !) sur panneau sombre
Art.NeonGG = function(body, kit, _item)
	local C = kit.C
	local halo = kit.Part(body, 4, 18, 92, 64, MAGENTA, { Radius = 16, Z = 1, Outline = false, Shade = false, T = 0.72 })
	kit.Animate(halo, "Pulse", 0.2, 1.3, 0)
	local board = kit.Part(body, 8, 22, 84, 56, DARKER, { Radius = 12, Z = 2 })
	kit.Stroke(board, MAGENTA, 2.5, 0.1)
	for index = 0, 1 do
		kit.Circle(board, 8 + index * 68, 8, 4, 4, STEEL, 0, 2) -- vis
	end
	-- néon : lettres claires + halo cyan (copie floue derrière)
	local halo2 = kit.Text(board, "GG", 42, 28, 42, CYAN, 3)
	halo2.TextTransparency = 0.55
	local text = kit.Text(board, "GG", 42, 28, 38, rgb(210, 250, 255), 4)
	text.TextStrokeColor3 = CYAN
	text.TextStrokeTransparency = 0
	kit.Animate(halo2, "Bob", 1, 1.5, 0)
	kit.Animate(text, "Bob", 1, 1.5, 0)
	-- petite manette + étincelles néon
	local pad = controller(kit, body, 50, 76, 22, MAGENTA, 5)
	local _ = pad
	kit.Sparkle(body, 16, 30, 10, C.Butter, 0, 6)
	kit.Sparkle(body, 86, 72, 8, CYAN, 0, 6)
	return { Glow = CYAN, WallShadow = Vector2.new(84, 56) }
end

-- PC gamer : écran avec jeu, tour vitrée à ventilateurs RGB, clavier lumineux
Art.GamerPC = function(body, kit, _item)
	local C = kit.C
	-- tour
	local tower = kit.Part(body, 66, 20, 30, 76, DARK, { Radius = 6, Z = 1, Shine = true })
	local glass = kit.Part(tower, 4, 6, 22, 58, rgb(20, 24, 44), { Radius = 4, Z = 2, Outline = CYAN, Thickness = 1.2 })
	fan(kit, glass, 11, 14, 16, CYAN, 3, 0)
	fan(kit, glass, 11, 34, 16, MAGENTA, 3, 1.3)
	kit.Box(glass, 3, 46, 16, 6, LIME, 0.2, 3) -- carte graphique
	kit.Shine(glass, 2, 2, 4, 30, 5, 0.6)
	kit.Circle(tower, 15, 70, 5, 5, LIME, 0, 3)
	-- écran
	kit.Part(body, 34, 58, 8, 22, STEEL, { Radius = 3, Z = 2 })
	kit.Blob(body, 38, 84, 30, 8, STEEL, { Z = 3 })
	local monitor = kit.Part(body, 2, 14, 64, 46, DARKER, { Radius = 6, Z = 4 })
	local screen = kit.Part(monitor, 4, 4, 56, 36, SCREEN, { Radius = 4, Z = 2, Outline = false })
	kit.Gradient(screen, rgb(120, 170, 255), rgb(255, 150, 200), 90)
	-- jeu : montagnes, héros, pièce
	kit.Triangle(screen, 16, 16, 26, 20, rgb(90, 90, 170), 2)
	kit.Triangle(screen, 38, 12, 30, 24, rgb(110, 100, 190), 2)
	kit.Box(screen, 0, 30, 56, 6, LIME, 0, 3)
	local hero = kit.Part(screen, 22, 20, 8, 10, RED, { Radius = 3, Z = 4, Thickness = 1 })
	kit.Animate(hero, "Bob", 2, 2, 0)
	local coin = kit.Circle(screen, 40, 14, 6, 6, C.Butter, 0, 4)
	kit.Animate(coin, "Bob", 1.5, 2.5, 1)
	kit.Text(screen, "x99", 10, 6, 7, WHITE, 5)
	-- clavier lumineux + souris
	ledStrip(kit, body, 6, 94, 56, 2, 5)
	local keyboard = kit.Part(body, 4, 84, 60, 11, DARK, { Radius = 3, Z = 6 })
	for index = 0, 9 do
		local key = kit.Box(keyboard, 3 + index * 5.6, 3, 4, 4, index % 2 == 0 and CYAN or MAGENTA, 0.15, 2)
		kit.Round(key, 1)
	end
	local mouse = kit.Blob(body, 60, 90, 10, 12, DARK, { Z = 7 })
	kit.Box(mouse, 4.5, 2, 1, 4, LIME, 0, 2)
	return { Glow = CYAN }
end

-- Télé géante (au mur) : jeu de course à l'écran, barre de son
Art.BigScreenTV = function(body, kit, _item)
	local C = kit.C
	local frame = kit.Part(body, 2, 18, 96, 58, DARKER, { Radius = 5, Z = 1 })
	local screen = kit.Group(frame, 3, 3, 90, 50, 2, true)
	local sky = kit.Box(screen, 0, 0, 90, 50, WHITE, 0, 1)
	kit.Gradient(sky, rgb(90, 150, 255), rgb(255, 176, 150), 90)
	kit.Circle(screen, 70, 16, 14, 14, C.Butter, 0, 2) -- soleil
	kit.Triangle(screen, 20, 12, 40, 16, rgb(120, 110, 200), 2)
	kit.Triangle(screen, 72, 14, 50, 14, rgb(100, 100, 190), 2)
	kit.Box(screen, 0, 26, 90, 24, rgb(110, 200, 110), 0, 3)
	-- route en perspective + bandes blanches qui défilent
	kit.Triangle(screen, 45, 22, 70, 28, rgb(80, 84, 100), 4, 0, 14)
	for index = 0, 2 do
		local dash = kit.Box(screen, 44, 28 + index * 7, 2 + index, 4 + index, WHITE, 0.1, 5)
		kit.Animate(dash, "Pulse", 0.8, 3, index * 0.8)
	end
	-- voiture du joueur
	local car = kit.Part(screen, 36, 38, 18, 9, RED, { Radius = 4, Z = 6, Thickness = 1 })
	kit.Box(car, 4, 1, 10, 3, CYAN, 0.2, 2)
	kit.Animate(car, "Drift", 2, 1.2, 0)
	-- compteur
	local hud = kit.Part(screen, 4, 4, 24, 11, DARKER, { Radius = 3, Z = 7, T = 0.25, Outline = false })
	kit.Text(hud, "1ST", 12, 5.5, 8, C.Butter, 3)
	local speed = kit.Part(screen, 62, 4, 24, 11, DARKER, { Radius = 3, Z = 7, T = 0.25, Outline = false })
	kit.Text(speed, "240", 12, 5.5, 8, CYAN, 3)
	-- pied mural + barre de son
	kit.Part(body, 22, 78, 56, 7, DARK, { Radius = 3, Z = 2 })
	for index = 0, 6 do
		kit.Circle(body, 28 + index * 7.4, 81.5, 3, 3, DARKER, 0, 3)
	end
	local led = kit.Circle(body, 92, 72, 3, 3, LIME, 0, 3)
	kit.Animate(led, "Pulse", 0.6, 1, 0)
	return { Glow = rgb(150, 200, 255), WallShadow = Vector2.new(96, 64) }
end

-- Borne d'arcade néon (fronton lumineux, envahisseur à l'écran, joystick)
Art.NeonArcade = function(body, kit, _item)
	local C = kit.C
	local cabinet = kit.Part(body, 14, 6, 72, 94, DARKER, { Radius = 8, Z = 1, Shine = true })
	for _, x in ipairs({ 14, 82 }) do
		kit.Box(body, x, 12, 4, 86, x < 50 and CYAN or MAGENTA, 0.1, 2) -- flancs néon
	end
	local _ = cabinet
	-- fronton
	local marquee = kit.Part(body, 18, 8, 64, 16, NAVY, { Radius = 5, Z = 3 })
	kit.Gradient(marquee, rgb(255, 120, 220), rgb(120, 140, 255), 0)
	local title = kit.Text(marquee, "ARCADE", 32, 8, 11, WHITE, 3)
	title.TextStrokeColor3 = MAGENTA
	title.TextStrokeTransparency = 0
	local bulbs = {}
	for index = 0, 4 do
		local color = index % 2 == 0 and CYAN or C.Butter
		local halo = kit.Circle(body, 22 + index * 14, 27, 8, 8, color, 0.6, 4)
		local bulb = kit.Circle(body, 22 + index * 14, 27, 4, 4, color, 0, 5)
		bulb:SetAttribute("Phase", index * 0.8)
		table.insert(bulbs, bulb)
		table.insert(bulbs, halo)
	end
	-- écran : envahisseur en pixels + score
	local screen = kit.Part(body, 22, 32, 56, 34, rgb(16, 20, 40), { Radius = 5, Z = 3, Outline = CYAN, Thickness = 1.5 })
	local invader = kit.Group(screen, 18, 8, 22, 16, 2)
	local pixels = { "0100010", "0011100", "0111110", "1101011", "1111111", "1010101" }
	for row, line in ipairs(pixels) do
		for col = 1, #line do
			if string.sub(line, col, col) == "1" then
				kit.Box(invader, (col - 1) * 3, (row - 1) * 2.6, 3, 2.6, LIME, 0, 1)
			end
		end
	end
	kit.Animate(invader, "Drift", 8, 1.2, 0)
	kit.Text(screen, "HI 9990", 28, 5, 6, C.Butter, 4)
	kit.Box(screen, 24, 28, 8, 3, CYAN, 0, 3) -- vaisseau
	-- tableau de commandes
	local panel = kit.Part(body, 16, 66, 68, 12, NAVY, { Radius = 4, Z = 4, Shine = true })
	kit.Line(panel, 16, 6, 14, -4, 2.5, STEEL, 0, 2)
	kit.Circle(panel, 14, -5, 7, 7, RED, 0, 3)
	for index, color in ipairs({ CYAN, MAGENTA, LIME, C.Butter }) do
		kit.Circle(panel, 34 + index * 7, 6, 5.5, 5.5, color, 0, 3)
	end
	-- trappe à pièces lumineuse
	local door = kit.Part(body, 36, 82, 28, 14, DARK, { Radius = 3, Z = 3 })
	for index = 0, 1 do
		local slot = kit.Box(door, 7 + index * 10, 4, 4, 6, ORANGE, 0, 2)
		kit.Animate(slot, "Pulse", 0.5, 1.5, index)
	end
	return { Bulbs = bulbs, Glow = MAGENTA }
end

-- Casque de réalité virtuelle pro sur présentoir, deux manettes anneaux
Art.VRHeadset = function(body, kit, _item)
	local C = kit.C
	-- présentoir
	kit.Part(body, 24, 64, 52, 30, WHITE, { Radius = 6, Z = 1, Shine = true })
	kit.Box(body, 24, 88, 52, 6, STEEL, 0, 2)
	kit.Blob(body, 50, 64, 56, 10, rgb(236, 240, 250), { Z = 2 })
	-- casque
	local strap = kit.Part(body, 22, 24, 56, 40, DARK, { Radius = 18, Z = 3, T = 1, Outline = DARK, Thickness = 5, Shade = false })
	local _ = strap
	local visor = kit.Part(body, 14, 30, 72, 30, WHITE, { Radius = 14, Z = 4, Shine = true })
	local glass = kit.Part(visor, 6, 5, 60, 18, DARKER, { Radius = 9, Z = 2 })
	kit.Gradient(glass, rgb(60, 80, 150), rgb(20, 24, 50), 90)
	local stripe = kit.Box(glass, 6, 7, 48, 3, CYAN, 0, 3)
	kit.Round(stripe)
	kit.Animate(stripe, "Pulse", 0.6, 1.3, 0)
	kit.Shine(glass, 6, 2, 16, 3, 4, 0.4)
	for _, x in ipairs({ 16, 44 }) do
		kit.Circle(glass, x, 13, 3, 3, MAGENTA, 0.2, 3)
	end
	-- manettes anneaux
	for index, side in ipairs({ -1, 1 }) do
		local cx = 50 + side * 40
		local ring = kit.Blob(body, cx, 78, 20, 20, WHITE, { Z = 5, T = 1, Outline = STEEL, Thickness = 3, Shade = false })
		local _r = ring
		kit.Part(body, cx - 4, 78, 8, 20, DARK, { Radius = 4, Z = 6, Shine = true })
		local led = kit.Circle(body, cx, 70, 4, 4, index == 1 and CYAN or MAGENTA, 0, 7)
		kit.Animate(led, "Pulse", 0.5, 1.5, index)
	end
	kit.Sparkle(body, 88, 22, 12, C.Butter, 0, 8)
	kit.Sparkle(body, 12, 20, 8, CYAN, 0, 8)
	return nil
end

-- Simulateur de course : siège baquet, volant, pédalier, écran
Art.RacingRig = function(body, kit, _item)
	local C = kit.C
	-- châssis
	kit.Part(body, 2, 90, 96, 8, DARK, { Radius = 3, Z = 1, Shine = true })
	kit.Part(body, 60, 44, 6, 48, STEEL, { Radius = 2, Z = 2 })
	-- écran au-dessus
	kit.Part(body, 76, 22, 4, 30, STEEL, { Radius = 2, Z = 1 })
	local screen = kit.Part(body, 56, 4, 42, 26, DARKER, { Radius = 4, Z = 2 })
	local view = kit.Group(screen, 3, 3, 36, 20, 2, true)
	local sky = kit.Box(view, 0, 0, 36, 20, WHITE, 0, 1)
	kit.Gradient(sky, rgb(100, 160, 255), rgb(255, 190, 150), 90)
	kit.Triangle(view, 18, 8, 34, 12, rgb(80, 84, 100), 2, 0, 8)
	kit.Box(view, 17, 12, 2, 3, WHITE, 0, 3)
	kit.Box(view, 16.5, 16, 3, 4, WHITE, 0, 3)
	-- siège baquet (rouge et noir)
	local seat = kit.Part(body, 6, 24, 38, 60, DARKER, { Radius = 14, Z = 3, Shine = true })
	kit.Part(seat, 8, 4, 22, 14, RED, { Radius = 6, Z = 2 })
	kit.Box(seat, 10, 22, 4, 34, RED, 0, 2)
	kit.Box(seat, 24, 22, 4, 34, RED, 0, 2)
	kit.Circle(seat, 19, 10, 5, 5, WHITE, 0.2, 3)
	kit.Part(body, 8, 70, 50, 16, DARK, { Radius = 7, Z = 4, Shine = true }) -- assise
	kit.Box(body, 14, 72, 38, 3, RED, 0, 5)
	-- volant sur sa colonne
	kit.Line(body, 63, 48, 54, 52, 5, STEEL, 0, 5)
	local wheel = kit.Blob(body, 52, 52, 22, 22, WHITE, { Z = 6, T = 1, Outline = DARKER, Thickness = 4, Shade = false })
	local hub = kit.Blob(wheel, 11, 11, 9, 9, DARKER, { Z = 2 })
	kit.Circle(hub, 4.5, 4.5, 3, 3, RED, 0, 2)
	kit.Animate(wheel, "Sway", 8, 1.2, 0)
	-- pédalier
	kit.Part(body, 76, 76, 16, 14, DARK, { Radius = 3, Z = 3 })
	for index = 0, 1 do
		kit.Part(body, 78 + index * 7, 70, 5, 10, STEEL, { Radius = 2, Z = 4, Rotation = -12 })
	end
	kit.Sparkle(body, 48, 16, 9, C.Butter, 0, 7)
	return nil
end

----------------------------------------------------------------------
-- 🛋️ Meubles cool (tables, sièges, lits)
----------------------------------------------------------------------

-- Pouf gamer (gris anthracite, liseré néon, logo manette)
Art.GamerBeanbag = function(body, kit, _item)
	local base = rgb(76, 72, 112)
	kit.Blob(body, 50, 96, 84, 12, DARKER, { Z = 1, Outline = false, Shade = false, T = 0.6 })
	local bag = kit.Blob(body, 50, 74, 92, 50, base, { Z = 2, Shine = true })
	kit.Blob(body, 56, 48, 64, 34, kit.Lighten(base, 0.1), { Z = 3, Shine = true }) -- dossier
	local seam = kit.Blob(bag, 46, 30, 76, 14, base, { Z = 2, T = 1, Outline = CYAN, Thickness = 2, Shade = false })
	local _ = seam
	kit.Animate(seam, "Pulse", 0.4, 1.2, 0)
	local logo = controller(kit, body, 50, 80, 26, MAGENTA, 4)
	local _l = logo
	return nil
end

-- Casier de vestiaire (2 portes, aérations, numéro, autocollants)
Art.LockerCabinet = function(body, kit, _item)
	local C = kit.C
	local blue = rgb(80, 130, 220)
	kit.Part(body, 6, 8, 88, 90, blue, { Radius = 5, Z = 1, Shine = true })
	kit.Box(body, 6, 94, 88, 6, kit.Darken(blue, 0.35), 0, 2)
	for index = 0, 1 do
		local door = kit.Part(body, 10 + index * 42, 12, 38, 80, kit.Lighten(blue, 0.08), { Radius = 3, Z = 2 })
		for vent = 0, 3 do
			kit.Box(door, 8, 6 + vent * 5, 22, 2.5, kit.Darken(blue, 0.3), 0, 2)
		end
		kit.Part(door, index == 0 and 30 or 4, 38, 4, 12, STEEL, { Radius = 2, Z = 3 })
		local plate = kit.Part(door, 11, 58, 16, 10, WHITE, { Radius = 2, Z = 3 })
		kit.Text(plate, index == 0 and "23" or "7", 8, 5, 8, C.Ink, 2)
	end
	-- autocollants : éclair et étoile
	local bolt = kit.Group(body, 18, 44, 18, 16, 4)
	kit.Line(bolt, 12, 0, 6, 8, 3, C.Butter, 0, 1)
	kit.Line(bolt, 6, 8, 12, 8, 3, C.Butter, 0, 1)
	kit.Line(bolt, 12, 8, 6, 16, 3, C.Butter, 0, 1)
	kit.Sparkle(body, 72, 48, 12, WHITE, 0, 4)
	return nil
end

-- Table de briques à construire (plateau vert à picots, pieds en briques)
Art.BrickTable = function(body, kit, _item)
	local C = kit.C
	local green = rgb(96, 196, 110)
	-- pieds : piles de briques de couleur
	for _, spec in ipairs({ { 6, RED, C.Butter }, { 80, rgb(80, 150, 255), ORANGE } }) do
		for level = 0, 2 do
			local color = level % 2 == 0 and spec[2] or spec[3]
			local brick = kit.Part(body, spec[1], 52 + level * 16, 14, 16, color, { Radius = 2, Z = 1 + level, Thickness = 1.2 })
			kit.Box(brick, 2, 2, 10, 2, WHITE, 0.6, 2)
		end
	end
	-- plateau (vu un peu de dessus) : chant + dessus plat
	kit.Part(body, 2, 42, 96, 12, kit.Darken(green, 0.2), { Radius = 3, Z = 5 })
	local top = kit.Part(body, 2, 36, 96, 10, green, { Radius = 3, Z = 6, Shine = true })
	for index = 0, 11 do
		kit.Circle(top, 5 + index * 7.8, 5, 4, 3, kit.Lighten(green, 0.3), 0, 2)
	end
	-- briques rangées dans le bac du dessous
	kit.Part(body, 22, 80, 56, 16, rgb(240, 240, 250), { Radius = 4, Z = 2 })
	for index, color in ipairs({ RED, C.Butter, rgb(80, 150, 255), green, ORANGE }) do
		kit.Part(body, 25 + (index - 1) * 10, 74 + (index % 2) * 3, 9, 8, color, { Radius = 2, Z = 3, Thickness = 1 })
	end
	return nil
end

-- Chaise gamer de course (de face) : baquet rouge et noir, roulettes
Art.GamerChair = function(body, kit, _item)
	-- piètement étoile + roulettes
	kit.Part(body, 46, 70, 8, 18, STEEL, { Radius = 3, Z = 1 })
	kit.Part(body, 16, 86, 68, 6, DARK, { Radius = 3, Z = 2 })
	for _, x in ipairs({ 18, 50, 82 }) do
		kit.Blob(body, x, 94, 11, 9, DARKER, { Z = 3 })
	end
	-- dossier baquet avec ailes
	local back = kit.Part(body, 22, 6, 56, 64, DARKER, { Radius = 16, Z = 2, Shine = true })
	kit.Part(back, 14, 8, 28, 50, RED, { Radius = 10, Z = 2 })
	kit.Box(back, 26, 8, 4, 50, WHITE, 0.2, 3)
	for index = 0, 1 do
		kit.Part(back, 4 + index * 44, 20, 8, 38, RED, { Radius = 4, Z = 2 })
	end
	local pillow = kit.Part(back, 16, 4, 24, 10, DARK, { Radius = 5, Z = 4, Shine = true })
	kit.Circle(pillow, 12, 5, 4, 4, RED, 0, 2)
	-- accoudoirs
	for _, x in ipairs({ 12, 78 }) do
		kit.Part(body, x, 54, 10, 18, DARK, { Radius = 3, Z = 3 })
		kit.Part(body, x - 3, 50, 16, 6, DARKER, { Radius = 3, Z = 4 })
	end
	-- assise
	local seat = kit.Part(body, 20, 60, 60, 16, DARKER, { Radius = 7, Z = 4, Shine = true })
	kit.Box(seat, 20, 3, 20, 4, RED, 0, 2)
	return nil
end

-- Bureau gamer : plateau noir avec bande LED, pieds rouges en Z, range-câbles
Art.GamingDesk = function(body, kit, _item)
	-- pieds en Z
	for _, x in ipairs({ 8, 80 }) do
		kit.Part(body, x, 46, 12, 44, RED, { Radius = 3, Z = 1, Shine = true })
		kit.Part(body, x - 4, 90, 20, 8, DARK, { Radius = 3, Z = 2 })
	end
	kit.Box(body, 20, 50, 60, 3, DARKER, 0, 1) -- barre de renfort
	-- range-câbles
	local tray = kit.Part(body, 26, 50, 48, 8, DARK, { Radius = 2, Z = 2 })
	kit.Line(tray, 6, 4, 42, 6, 1.5, CYAN, 0.3, 2)
	-- plateau (chant + dessus)
	local edge = kit.Part(body, 2, 38, 96, 10, DARKER, { Radius = 3, Z = 3 })
	ledStrip(kit, edge, 4, 5, 88, 2.5, 3)
	local top = kit.Part(body, 2, 34, 96, 8, DARK, { Radius = 3, Z = 4, Shine = true })
	kit.Box(top, 6, 2, 84, 1.5, WHITE, 0.8, 2)
	return nil
end

-- Lits superposés (bleu nuit et rouge, échelle, étoiles)
Art.BunkBed = function(body, kit, _item)
	local C = kit.C
	local frameColor = rgb(96, 120, 190)
	for _, x in ipairs({ 4, 90 }) do
		kit.Part(body, x, 8, 7, 92, frameColor, { Radius = 3, Z = 6, Shine = true })
	end
	-- lit du haut
	kit.Part(body, 2, 38, 96, 8, kit.Darken(frameColor, 0.2), { Radius = 3, Z = 4 })
	kit.Part(body, 10, 26, 70, 12, WHITE, { Radius = 5, Z = 2 })
	local topBlanket = kit.Part(body, 34, 22, 46, 16, NAVY, { Radius = 6, Z = 3, Shine = true })
	for index = 0, 2 do
		kit.Sparkle(topBlanket, 8 + index * 14, 8, 7, C.Butter, 0, 2)
	end
	kit.Blob(body, 22, 26, 20, 11, rgb(210, 226, 255), { Z = 3, Shine = true })
	kit.Part(body, 4, 16, 44, 5, frameColor, { Radius = 2, Z = 7 }) -- garde-corps
	for _, x in ipairs({ 20, 34 }) do
		kit.Part(body, x, 20, 4, 18, frameColor, { Radius = 2, Z = 7 })
	end
	-- lit du bas
	kit.Part(body, 2, 84, 96, 9, kit.Darken(frameColor, 0.2), { Radius = 3, Z = 4 })
	kit.Part(body, 10, 70, 80, 14, WHITE, { Radius = 5, Z = 2 })
	local lowBlanket = kit.Part(body, 36, 66, 54, 18, RED, { Radius = 6, Z = 3, Shine = true })
	for index = 0, 2 do
		kit.Box(lowBlanket, 6 + index * 16, 2, 5, 14, WHITE, 0.55, 2)
	end
	kit.Blob(body, 24, 70, 22, 12, rgb(255, 226, 214), { Z = 3, Shine = true })
	-- échelle
	for _, x in ipairs({ 80, 92 }) do
		kit.Part(body, x, 36, 4, 50, rgb(210, 170, 120), { Radius = 2, Z = 8 })
	end
	for _, y in ipairs({ 48, 60, 72 }) do
		kit.Part(body, 80, y, 16, 4, rgb(236, 196, 150), { Radius = 2, Z = 8 })
	end
	return nil
end

-- Lit voiture de course (rouge, numéro 1, aileron, phares)
Art.RaceCarBed = function(body, kit, _item)
	local C = kit.C
	-- carrosserie
	local car = kit.Part(body, 2, 50, 96, 36, RED, { Radius = 14, Z = 3, Shine = true })
	kit.Box(car, 4, 22, 88, 4, WHITE, 0.2, 2) -- bande
	kit.Box(car, 4, 27, 88, 3, DARKER, 0.3, 2)
	local plate = kit.Blob(car, 70, 14, 20, 16, WHITE, { Z = 3 })
	kit.Text(plate, "1", 10, 8, 12, C.Ink, 2)
	kit.Circle(car, 92, 10, 6, 6, C.Butter, 0, 3) -- phare
	-- capot avant bombé + aileron arrière
	kit.Part(body, 70, 42, 28, 14, RED, { Radius = 8, Z = 2 })
	kit.Part(body, 0, 30, 8, 26, DARKER, { Radius = 3, Z = 2 })
	kit.Part(body, -2, 28, 22, 6, RED, { Radius = 3, Z = 4, Shine = true })
	-- matelas, oreiller, couette à damier
	kit.Part(body, 16, 40, 60, 14, WHITE, { Radius = 6, Z = 1 })
	kit.Blob(body, 26, 42, 20, 11, rgb(226, 236, 255), { Z = 2, Shine = true })
	local blanket = kit.Part(body, 40, 38, 36, 16, DARK, { Radius = 6, Z = 2 })
	for row = 0, 1 do
		for col = 0, 5 do
			if (row + col) % 2 == 0 then
				kit.Box(blanket, 3 + col * 5, 3 + row * 5, 5, 5, WHITE, 0.1, 2)
			end
		end
	end
	-- roues
	for _, x in ipairs({ 22, 78 }) do
		local wheel = kit.Blob(body, x, 86, 24, 24, DARKER, { Z = 5 })
		kit.Circle(wheel, 12, 12, 12, 12, STEEL, 0, 2)
		local spokes = kit.Pivot(wheel, 12, 12, 3)
		for index = 0, 2 do
			local spoke = kit.Box(spokes, -1, -5, 2, 10, DARK, 0, 1)
			spoke.Rotation = index * 60
		end
		kit.Animate(spokes, "Spin", 1, 0.3, x)
	end
	return nil
end

return Art
