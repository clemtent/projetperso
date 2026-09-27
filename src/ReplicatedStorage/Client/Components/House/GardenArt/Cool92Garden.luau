--[[
	Cool92Garden (ModuleScript) — (v9.2) déco "cool" du jardin 🏀⛺
	Emplacement : ReplicatedStorage > Client > Components > House > GardenArt > Cool92Garden
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas, y = 100).
	Ids = Config.House.GardenDecor (panier de basket, tente, barbecue, cage
	de foot, rampe de skate, cabane dans l'arbre, statue de dino).
]]

local Garden = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local DARK = rgb(44, 46, 64)
local DARKER = rgb(30, 32, 46)
local RED = rgb(236, 66, 76)
local ORANGE = rgb(255, 152, 56)
local STEEL = rgb(176, 186, 206)
local BLUE = rgb(80, 150, 255)
local WOOD = rgb(186, 130, 90)

-- Panier de basket de l'allée (poteau, panneau, filet, ballon)
Garden.YardHoop = function(body, kit, _entry)
	kit.Blob(body, 50, 96, 60, 8, DARKER, { Z = 1, Outline = false, Shade = false, T = 0.6 })
	kit.Part(body, 44, 26, 8, 72, STEEL, { Radius = 3, Z = 2, Shine = true })
	local board = kit.Part(body, 20, 4, 60, 36, WHITE, { Radius = 4, Z = 3, Shine = true })
	kit.Stroke(board, BLUE, 2.5, 0)
	local square = kit.Part(board, 20, 16, 20, 14, WHITE, { Radius = 1, Z = 2, Outline = RED, Thickness = 2, Shade = false })
	local _ = square
	kit.Part(body, 34, 38, 32, 4, ORANGE, { Radius = 2, Z = 5 })
	for index = 0, 4 do
		kit.Line(body, 36 + index * 7, 42, 38 + index * 6, 56, 1.2, WHITE, 0.1, 4)
	end
	local ball = kit.Blob(body, 72, 86, 20, 20, rgb(250, 140, 60), { Z = 6, Shine = true })
	kit.Box(ball, 9.4, 1, 1.2, 18, rgb(120, 60, 30), 0, 2)
	kit.Box(ball, 1, 9.4, 18, 1.2, rgb(120, 60, 30), 0, 2)
	kit.Animate(ball, "Bob", 3, 2, 0)
	return nil
end

-- Tente de camping (toile orange, ouverture, lanterne, fanion)
Garden.CampTent = function(body, kit, _entry)
	local C = kit.C
	kit.Blob(body, 50, 96, 90, 8, rgb(110, 160, 90), { Z = 1, Outline = false, Shade = false, T = 0.4 })
	local tent = kit.Triangle(body, 50, 22, 92, 76, ORANGE, 2)
	local _ = tent
	kit.Triangle(body, 50, 22, 60, 76, rgb(255, 180, 90), 3)
	kit.Triangle(body, 50, 50, 26, 48, DARK, 4) -- ouverture
	kit.Line(body, 50, 22, 50, 10, 2, WOOD, 0, 1)
	local flag = kit.Part(body, 50, 8, 14, 9, RED, { Radius = 2, Z = 1 })
	kit.Animate(flag, "Sway", 6, 2, 0)
	for _, x in ipairs({ 6, 94 }) do
		kit.Line(body, x, 98, x < 50 and 22 or 78, 70, 1.2, WHITE, 0.2, 5)
	end
	local lantern = kit.Part(body, 76, 80, 12, 16, C.Butter, { Radius = 4, Z = 5, Shine = true })
	kit.Animate(lantern, "Pulse", 0.3, 1.5, 0)
	kit.Part(body, 78, 76, 8, 4, DARK, { Radius = 2, Z = 6 })
	return { Glow = C.Butter }
end

-- Barbecue (cuve ronde, grille, saucisses, fumée qui monte)
Garden.BBQGrill = function(body, kit, _entry)
	for _, spec in ipairs({ { 30, 98, 40, 62 }, { 70, 98, 60, 62 } }) do
		kit.Line(body, spec[1], spec[2], spec[3], spec[4], 3, DARK, 0, 1)
	end
	kit.Blob(body, 30, 96, 10, 10, DARKER, { Z = 2 })
	local bowl = kit.Part(body, 18, 44, 64, 28, RED, { Radius = 14, Z = 3, Shine = true })
	kit.Box(bowl, 6, 0, 52, 3, DARKER, 0, 2)
	kit.Part(body, 14, 42, 72, 5, STEEL, { Radius = 2, Z = 4 }) -- grille
	for index, x in ipairs({ 26, 42, 58 }) do
		local sausage = kit.Part(body, x, 34, 14, 7, rgb(200, 100, 70), { Radius = 3, Z = 5, Shine = true })
		kit.Box(sausage, 3, 2, 8, 1, rgb(120, 60, 40), 0.3, 2)
		local _ = index
	end
	for index = 0, 2 do
		local puff = kit.Blob(body, 40 + index * 12, 22 - index * 8, 14 - index * 2, 12 - index * 2, rgb(230, 230, 240), { Z = 6, Outline = false })
		kit.Animate(puff, "Bob", 3, 1, index)
	end
	kit.Part(body, 80, 50, 14, 4, STEEL, { Radius = 2, Z = 4 }) -- poignée
	return nil
end

-- Cage de foot du jardin (filet, ballon)
Garden.YardGoal = function(body, kit, _entry)
	local net = kit.Group(body, 10, 28, 80, 68, 1)
	for index = 0, 8 do
		kit.Box(net, index * 10, 0, 1.2, 68, WHITE, 0.35, 1)
	end
	for index = 0, 6 do
		kit.Box(net, 0, index * 10, 80, 1.2, WHITE, 0.35, 1)
	end
	kit.Part(body, 6, 24, 88, 7, WHITE, { Radius = 3, Z = 3, Shine = true, Outline = STEEL })
	for _, x in ipairs({ 6, 87 }) do
		kit.Part(body, x, 24, 7, 76, WHITE, { Radius = 3, Z = 3, Shine = true, Outline = STEEL })
	end
	local ball = kit.Blob(body, 60, 88, 20, 20, WHITE, { Z = 5, Shine = true })
	kit.Diamond(ball, 10, 10, 6, DARK, 0, 2)
	for _, p in ipairs({ { 3, 6 }, { 17, 6 }, { 6, 17 }, { 14, 17 } }) do
		kit.Circle(ball, p[1], p[2], 4, 4, DARK, 0, 2)
	end
	kit.Animate(ball, "Drift", 3, 1, 0)
	return nil
end

-- Rampe de skate (quart de lune en bois, bord métal, skate posé)
Garden.SkateRamp = function(body, kit, _entry)
	local C = kit.C
	-- profil en quart de cercle (creux) : tranches horizontales de bois
	local right, top, bottom, radius = 80, 30, 98, 70
	local slices = 22
	for index = 1, slices do
		local k = index / slices
		local width = radius * (1 - math.sqrt(math.max(0, 1 - k * k)))
		local y = top + (bottom - top) * (index - 1) / slices
		local slice = kit.Box(body, right - width - 2, y, width + 2, (bottom - top) / slices + 0.8, WOOD, 0, 1)
		local _ = slice
	end
	kit.Part(body, 80, 28, 16, 70, kit.Darken(WOOD, 0.1), { Radius = 2, Z = 2, Shine = true }) -- plateforme
	for index = 0, 3 do
		kit.Box(body, 82, 36 + index * 16, 12, 2, kit.Darken(WOOD, 0.3), 0, 3)
	end
	kit.Part(body, 74, 25, 24, 5, STEEL, { Radius = 2, Z = 3 }) -- bord (coping)
	kit.Part(body, 8, 94, 76, 5, kit.Darken(WOOD, 0.15), { Radius = 2, Z = 2 }) -- base
	-- skate posé en bas de la rampe
	kit.Part(body, 16, 86, 30, 5, RED, { Radius = 3, Z = 4 })
	kit.Circle(body, 21, 93, 5, 5, C.Butter, 0, 5)
	kit.Circle(body, 41, 93, 5, 5, C.Butter, 0, 5)
	kit.Sparkle(body, 56, 30, 10, C.Butter, 0, 5)
	return nil
end

-- Cabane dans l'arbre (tronc, feuillage, cabane en bois, échelle de corde)
Garden.Treehouse = function(body, kit, _entry)
	local C = kit.C
	kit.Part(body, 42, 44, 16, 56, rgb(150, 100, 70), { Radius = 5, Z = 1, Shine = true })
	kit.Blob(body, 50, 26, 96, 50, C.Leaf, { Z = 2, Shine = true })
	kit.Blob(body, 30, 36, 40, 30, C.LeafDark, { Z = 2 })
	local hut = kit.Part(body, 26, 36, 48, 30, WOOD, { Radius = 4, Z = 3, Shine = true })
	for index = 0, 3 do
		kit.Box(hut, 0, 6 + index * 7, 48, 1.5, kit.Darken(WOOD, 0.25), 0, 2)
	end
	kit.Part(hut, 18, 8, 12, 12, rgb(170, 220, 255), { Radius = 2, Z = 3 }) -- fenêtre
	kit.Triangle(body, 50, 20, 60, 18, RED, 4) -- toit
	local flag = kit.Part(body, 70, 8, 12, 8, BLUE, { Radius = 2, Z = 4 })
	kit.Line(body, 70, 8, 70, 22, 1.5, WOOD, 0, 4)
	kit.Animate(flag, "Sway", 6, 2, 0)
	-- échelle de corde
	for _, x in ipairs({ 30, 40 }) do
		kit.Line(body, x, 66, x, 98, 1.5, rgb(220, 190, 140), 0, 4)
	end
	for index = 0, 3 do
		kit.Box(body, 29, 70 + index * 8, 12, 2.5, WOOD, 0, 5)
	end
	return nil
end

-- Statue de dino (long cou, en pierre moussue, sur un socle)
Garden.DinoStatue = function(body, kit, _entry)
	local stone = rgb(150, 190, 150)
	kit.Part(body, 14, 86, 72, 12, rgb(170, 170, 186), { Radius = 4, Z = 1, Shine = true })
	kit.Blob(body, 40, 70, 56, 34, stone, { Z = 2, Shine = true })
	kit.Line(body, 58, 64, 74, 22, 10, stone, 0, 2)
	local head = kit.Blob(body, 78, 18, 22, 16, stone, { Z = 3, Shine = true })
	kit.Face(head, 12, 7, 12, { Eyes = "happy", Mouth = "smile", Z = 3 })
	kit.Line(body, 14, 72, 2, 82, 7, stone, 0, 2)
	for _, x in ipairs({ 26, 50 }) do
		kit.Part(body, x, 76, 10, 12, stone, { Radius = 3, Z = 3 })
	end
	for index = 0, 3 do
		kit.Triangle(body, 24 + index * 10, 50 - index * 2, 8, 8, rgb(120, 170, 120), 1)
	end
	kit.Blob(body, 36, 60, 14, 6, rgb(110, 180, 100), { Z = 3, Outline = false }) -- mousse
	return nil
end

return Garden
