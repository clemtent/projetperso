--[[
	Cool92Music (ModuleScript) — (v9.2) musique rock 🎸 (ampli, guitare
	électrique à flammes, batterie, cabine de DJ)
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Cool92Music
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au sol).
]]

local Art = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local DARK = rgb(44, 46, 64)
local DARKER = rgb(30, 32, 46)
local CYAN = rgb(60, 222, 255)
local MAGENTA = rgb(255, 84, 196)
local LIME = rgb(140, 240, 110)
local RED = rgb(236, 66, 76)
local ORANGE = rgb(255, 152, 56)
local STEEL = rgb(176, 186, 206)
local CHROME = rgb(214, 222, 236)

-- Petit éclair (logo) dans la zone (x, y) de hauteur h
local function bolt(kit, parent, x, y, h, color, z)
	local g = kit.Group(parent, x, y, h * 0.7, h, z)
	kit.Line(g, h * 0.55, 0, h * 0.18, h * 0.5, h * 0.16, color, 0, 1)
	kit.Line(g, h * 0.18, h * 0.5, h * 0.52, h * 0.5, h * 0.16, color, 0, 1)
	kit.Line(g, h * 0.52, h * 0.5, h * 0.15, h, h * 0.16, color, 0, 1)
	return g
end

-- Note de musique qui flotte
local function note(kit, parent, x, y, color, phase)
	local label = kit.Text(parent, "♪", x, y, 14, color, 8)
	kit.Animate(label, "Bob", 3, 1.2, phase)
	return label
end

-- Ampli de guitare (grille, boutons, logo éclair, câble)
Art.GuitarAmp = function(body, kit, _item)
	local C = kit.C
	local amp = kit.Part(body, 8, 22, 84, 76, DARKER, { Radius = 8, Z = 1, Shine = true })
	kit.Part(body, 32, 16, 36, 8, DARK, { Radius = 4, Z = 0 }) -- poignée
	local panel = kit.Part(amp, 4, 4, 76, 16, C.Gold, { Radius = 4, Z = 2 })
	for index = 0, 4 do
		local knob = kit.Circle(panel, 10 + index * 12, 8, 8, 8, DARKER, 0, 2)
		kit.Box(knob, 3.4, 1, 1.2, 3.5, WHITE, 0, 2)
	end
	local led = kit.Circle(panel, 70, 8, 5, 5, RED, 0, 2)
	kit.Animate(led, "Pulse", 0.6, 1.5, 0)
	local grille = kit.Part(amp, 6, 24, 72, 46, rgb(70, 64, 80), { Radius = 5, Z = 2 })
	for row = 0, 7 do
		kit.Box(grille, 3, 3 + row * 5.5, 66, 1.4, rgb(96, 90, 110), 0, 2)
	end
	local cone = kit.Circle(grille, 36, 23, 30, 30, DARKER, 0.2, 3)
	kit.Animate(cone, "Breathe", 0.05, 3, 0)
	bolt(kit, grille, 30, 12, 20, C.Butter, 4)
	-- câble jack
	kit.Line(body, 90, 80, 98, 96, 2.5, DARKER, 0, 2)
	note(kit, body, 90, 14, CYAN, 0)
	return nil
end

-- Guitare électrique à flammes sur son support
Art.ElectricGuitar = function(body, kit, _item)
	local C = kit.C
	-- support en A
	kit.Line(body, 34, 98, 50, 70, 3, DARK, 0, 1)
	kit.Line(body, 66, 98, 50, 70, 3, DARK, 0, 1)
	-- manche + tête
	kit.Part(body, 46, 6, 8, 56, rgb(150, 96, 60), { Radius = 3, Z = 2 })
	for index = 0, 5 do
		kit.Box(body, 46, 12 + index * 8, 8, 1, CHROME, 0, 3) -- frettes
	end
	local head = kit.Part(body, 42, 0, 16, 12, DARKER, { Radius = 4, Z = 3 })
	for index = 0, 2 do
		kit.Circle(head, 2, 3 + index * 3.5, 3, 3, CHROME, 0, 2)
		kit.Circle(head, 14, 3 + index * 3.5, 3, 3, CHROME, 0, 2)
	end
	-- corps (double pointe) rouge + flammes
	kit.Part(body, 22, 52, 18, 20, RED, { Radius = 8, Z = 3, Rotation = -30 })
	kit.Part(body, 60, 50, 18, 20, RED, { Radius = 8, Z = 3, Rotation = 30 })
	local guitarBody = kit.Blob(body, 50, 76, 52, 40, RED, { Z = 4, Shine = true })
	for k = 0, 2 do
		local cx = 14 + k * 12
		kit.Circle(guitarBody, cx, 32, 14, 10, ORANGE, 0, 2)
		kit.Triangle(guitarBody, cx, 16 - (k == 1 and 6 or 0), 12, 18 + (k == 1 and 6 or 0), ORANGE, 2, 0, 8)
		kit.Triangle(guitarBody, cx, 24, 6, 10, C.Butter, 3, 0, 6)
	end
	-- micros, chevalet, cordes
	for index = 0, 1 do
		kit.Part(guitarBody, 16, 8 + index * 9, 20, 5, DARKER, { Radius = 2, Z = 4 })
	end
	kit.Part(guitarBody, 18, 28, 16, 4, CHROME, { Radius = 2, Z = 4 })
	for index = 0, 3 do
		kit.Box(body, 47.5 + index * 1.6, 12, 0.6, 76, WHITE, 0.3, 5)
	end
	kit.Circle(guitarBody, 44, 30, 5, 5, C.Gold, 0, 4)
	note(kit, body, 86, 30, MAGENTA, 1)
	return nil
end

-- Batterie rock (grosse caisse à éclair, toms, caisse claire, cymbales)
Art.DrumKit = function(body, kit, _item)
	local C = kit.C
	local shell = rgb(80, 110, 230)
	-- cymbales sur pieds
	for index, spec in ipairs({ { 12, 26 }, { 88, 18 } }) do
		kit.Line(body, spec[1], spec[2], spec[1], 96, 2, STEEL, 0, 1)
		local cymbal = kit.Part(body, spec[1] - 14, spec[2] - 3, 28, 6, C.Gold, { Radius = -1, Z = 2, Shine = true })
		kit.Animate(cymbal, "Sway", 4, 2, index)
	end
	-- toms
	for _, x in ipairs({ 30, 58 }) do
		local tom = kit.Part(body, x, 26, 20, 16, shell, { Radius = 5, Z = 3, Shine = true })
		kit.Box(tom, 0, 0, 20, 3, WHITE, 0.1, 2)
	end
	-- caisse claire + tom basse
	kit.Line(body, 14, 60, 14, 96, 2, STEEL, 0, 2)
	local snare = kit.Part(body, 4, 52, 24, 12, CHROME, { Radius = 4, Z = 4, Shine = true })
	kit.Box(snare, 0, 0, 24, 3, WHITE, 0, 2)
	local floor = kit.Part(body, 74, 50, 24, 36, shell, { Radius = 6, Z = 3, Shine = true })
	kit.Box(floor, 0, 0, 24, 3, WHITE, 0.1, 2)
	-- grosse caisse
	local kick = kit.Blob(body, 50, 72, 50, 50, shell, { Z = 5, Shine = true })
	kit.Circle(kick, 25, 25, 42, 42, rgb(244, 246, 255), 0, 2)
	bolt(kit, kick, 18, 12, 26, C.Butter, 3)
	for index = 0, 5 do
		local a = index / 6 * math.pi * 2
		kit.Circle(kick, 25 + math.cos(a) * 23, 25 + math.sin(a) * 23, 3.5, 3.5, CHROME, 0, 3)
	end
	kit.Animate(kick, "Breathe", 0.02, 4, 0)
	-- baguettes croisées
	kit.Line(body, 34, 16, 50, 30, 2.5, rgb(236, 196, 150), 0, 6)
	kit.Line(body, 66, 16, 50, 30, 2.5, rgb(236, 196, 150), 0, 6)
	note(kit, body, 94, 44, CYAN, 0.5)
	return nil
end

-- Cabine de DJ : platines qui tournent, table de mixage, façade à égaliseur
Art.DJBooth = function(body, kit, _item)
	local C = kit.C
	-- façade lumineuse
	local front = kit.Part(body, 6, 44, 88, 54, DARKER, { Radius = 8, Z = 2 })
	for col = 0, 9 do
		local height = 6 + ((col * 7) % 5) * 6
		local bar = kit.Box(front, 6 + col * 7.8, 44 - height, 5.5, height, col % 3 == 0 and MAGENTA or (col % 3 == 1 and CYAN or LIME), 0, 2)
		kit.Round(bar, 2)
		kit.Animate(bar, "Pulse", 0.6, 2.2, col * 0.7)
	end
	kit.Text(front, "DJ", 44, 10, 14, WHITE, 3)
	-- plateau + platines
	kit.Part(body, 2, 34, 96, 12, DARK, { Radius = 4, Z = 3, Shine = true })
	for index, x in ipairs({ 22, 78 }) do
		local deck = kit.Blob(body, x, 36, 30, 12, DARKER, { Z = 4 })
		local record = kit.Blob(deck, 15, 6, 22, 8, rgb(20, 20, 26), { Z = 2, Outline = false })
		local label = kit.Circle(record, 11, 4, 7, 3.5, index == 1 and MAGENTA or CYAN, 0, 2)
		kit.Animate(label, "Drift", 3, 3, index)
	end
	-- table de mixage
	local mixer = kit.Part(body, 40, 28, 20, 10, rgb(60, 62, 84), { Radius = 3, Z = 5 })
	for index = 0, 2 do
		kit.Box(mixer, 3 + index * 6, 3, 2, 5, C.Butter, 0, 2)
	end
	-- casque posé + ordinateur portable
	local laptop = kit.Part(body, 60, 12, 26, 18, STEEL, { Radius = 3, Z = 2, Shine = true })
	kit.Part(laptop, 3, 3, 20, 12, rgb(40, 44, 90), { Radius = 2, Z = 2, Outline = false })
	kit.Blob(body, 24, 24, 20, 14, DARK, { Z = 2, T = 1, Outline = DARK, Thickness = 3, Shade = false })
	kit.Blob(body, 16, 30, 8, 10, RED, { Z = 3 })
	kit.Blob(body, 32, 30, 8, 10, RED, { Z = 3 })
	note(kit, body, 50, 8, MAGENTA, 0)
	return { Glow = MAGENTA }
end

return Art
