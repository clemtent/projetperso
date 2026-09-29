--[[
	Luxe98 (ModuleScript) — (v9.8 CATALOG98) 💎 objets de luxe et objets
	"incroyables" (tunnel aquarium, cascade intérieure, dragon d'or, mini
	montagnes russes...), grand lustre, dôme planétarium, et les télés XXL /
	l'écran de home cinéma du "Dopamine Setup"
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Luxe98
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au
	sol, objets muraux centrés).

	Style : rendu "autocollant" du jeu, mais matières de luxe réalistes
	(marbre veiné, or, velours, laque blanche, verre, eau). Les dessus
	(lits, méridienne, billard, fauteuils, trône) sont déclarés dans
	House/HouseSurfaces (mêmes hauteurs que les modèles 3D de House3DLuxe).
]]

local Art = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local GOLD = rgb(236, 190, 70)
local GOLD_DARK = rgb(180, 136, 40)
local GOLD_LIGHT = rgb(255, 226, 130)
local MARBLE = rgb(242, 240, 238)
local MARBLE_VEIN = rgb(186, 184, 196)
local VELVET = rgb(120, 60, 150)
local VELVET_DARK = rgb(84, 40, 110)
local WALNUT = rgb(120, 78, 52)
local WALNUT_DARK = rgb(84, 54, 38)
local IRON = rgb(60, 62, 72)
local IRON_DARK = rgb(34, 36, 44)
local STEEL = rgb(190, 196, 208)
local WATER = rgb(80, 180, 230)
local WATER_DEEP = rgb(30, 110, 190)
local WATER_LIGHT = rgb(170, 230, 250)
local STONE = rgb(150, 146, 140)
local STONE_DARK = rgb(104, 100, 98)
local LEAF = rgb(84, 150, 84)
local LEAF_DARK = rgb(52, 110, 62)
local CYAN = rgb(60, 222, 255)
local MAGENTA = rgb(255, 84, 196)
local RED = rgb(220, 60, 60)
local AMBER = rgb(255, 196, 110)
local FIRE = rgb(255, 140, 50)
local SCREEN = rgb(24, 26, 44)

----------------------------------------------------------------------
-- Petits outils
----------------------------------------------------------------------

-- Petit poisson (vers la droite si dir = 1)
local function fish(kit, parent, cx, cy, size, color, dir, z)
	local g = kit.Pivot(parent, cx, cy, z or 4)
	kit.Blob(g, 0, 0, size, size * 0.6, color, { Z = 2, Thickness = 1, Shine = true })
	kit.Triangle(g, -dir * size * 0.55, -size * 0.3, size * 0.4, size * 0.6, kit.Darken(color, 0.1), 1)
	kit.Circle(g, dir * size * 0.25, -size * 0.06, size * 0.14, size * 0.14, rgb(30, 30, 40), 0, 3)
	kit.Animate(g, "Drift", 3 * dir, 0.6, cx * 0.1)
	return g
end

-- Bulles qui montent (animées)
local function bubbles(kit, parent, x, y, n, z)
	for k = 0, n - 1 do
		local b = kit.Circle(parent, x + (k % 2) * 3, y - k * 7, 3 + k % 2, 3 + k % 2, WHITE, 0.45, z or 5)
		kit.Stroke(b, WATER_LIGHT, 0.8, 0.3)
		kit.Animate(b, "Bob", 2, 1.2, k * 0.8 + x * 0.1)
	end
end

-- Pied griffe doré
local function clawFoot(kit, parent, cx, y, w, z)
	kit.Blob(parent, cx, y - w * 0.3, w, w * 0.8, GOLD, { Z = z or 1, Shine = true })
end

-- Veines du marbre
local function veins(kit, parent, w, h, z)
	kit.Line(parent, w * 0.1, h * 0.2, w * 0.45, h * 0.6, 1, MARBLE_VEIN, 0.3, z or 2)
	kit.Line(parent, w * 0.45, h * 0.6, w * 0.8, h * 0.35, 1, MARBLE_VEIN, 0.4, z or 2)
	kit.Line(parent, w * 0.6, h * 0.9, w * 0.9, h * 0.7, 0.8, MARBLE_VEIN, 0.5, z or 2)
end

----------------------------------------------------------------------
-- 💎 Luxe
----------------------------------------------------------------------

-- Méridienne en velours (dossier arrondi à gauche, capitons, pieds dorés) : dessus y = 62
Art.VelvetChaise = function(body, kit, _item)
	for _, x in ipairs({ 14, 86 }) do
		kit.Part(body, x - 2, 88, 4, 11, GOLD, { Radius = 2, Z = 1 })
	end
	kit.Part(body, 6, 26, 30, 64, VELVET, { Radius = 15, Z = 2, Shine = true })
	for row = 0, 3 do
		kit.Circle(body, 14 + (row % 2) * 7, 38 + row * 10, 2.4, 2.4, VELVET_DARK, 0, 3)
		kit.Circle(body, 28 - (row % 2) * 7, 38 + row * 10, 2.4, 2.4, VELVET_DARK, 0, 3)
	end
	kit.Part(body, 8, 66, 88, 24, VELVET_DARK, { Radius = 10, Z = 3 })
	kit.Part(body, 10, 58, 86, 14, VELVET, { Radius = 7, Z = 4, Shine = true })
	kit.Part(body, 10, 88, 86, 3, GOLD, { Radius = 1, Z = 5 })
	kit.Part(body, 26, 50, 22, 12, rgb(236, 210, 120), { Radius = 6, Z = 5, Rotation = -10 }) -- coussin
	return nil
end

-- Statue de marbre (buste antique sur colonne cannelée)
Art.MarbleStatue = function(body, kit, _item)
	kit.Part(body, 24, 90, 52, 10, MARBLE, { Radius = 2, Z = 1, Shine = true })
	local column = kit.Part(body, 32, 52, 36, 40, MARBLE, { Radius = 2, Z = 2, Shine = true })
	for k = 1, 4 do
		kit.Box(column, k * 7, 2, 1.4, 36, MARBLE_VEIN, 0.4, 2)
	end
	kit.Part(body, 28, 48, 44, 6, MARBLE, { Radius = 2, Z = 3 })
	-- buste
	local bust = kit.Part(body, 30, 30, 40, 20, MARBLE, { Radius = 10, Z = 4, Shine = true })
	veins(kit, bust, 40, 20, 2)
	kit.Part(body, 44, 22, 12, 10, MARBLE, { Radius = 4, Z = 4 })
	local head = kit.Blob(body, 50, 14, 22, 26, MARBLE, { Z = 5, Shine = true })
	-- profil : nez, couronne de laurier
	kit.Line(head, 8, 12, 10, 15, 1.2, MARBLE_VEIN, 0, 2)
	for k = 0, 4 do
		kit.Blob(body, 40 + k * 5, 4 + math.abs(k - 2) * 1.2, 6, 4, rgb(210, 190, 120), { Z = 6, Rotation = (k - 2) * 20 })
	end
	return nil
end

-- Lit king size (tête de lit capitonnée haute, parure satinée) : dessus y = 60
Art.KingBed = function(body, kit, _item)
	kit.Part(body, 2, 14, 18, 80, rgb(236, 226, 214), { Radius = 8, Z = 1, Shine = true })
	for row = 0, 5 do
		kit.Circle(body, 8 + (row % 2) * 6, 22 + row * 11, 2.4, 2.4, rgb(196, 180, 164), 0, 2)
	end
	kit.Part(body, 4, 76, 94, 20, WALNUT, { Radius = 4, Z = 2, Shine = true })
	for _, x in ipairs({ 10, 92 }) do
		kit.Part(body, x - 3, 94, 6, 6, GOLD, { Radius = 2, Z = 1 })
	end
	kit.Part(body, 8, 62, 90, 16, WHITE, { Radius = 6, Z = 3 })
	local duvet = kit.Part(body, 38, 58, 60, 24, rgb(90, 70, 130), { Radius = 7, Z = 4, Shine = true })
	kit.Box(duvet, 0, 3, 12, 18, rgb(236, 220, 180), 0, 2)
	kit.Part(body, 70, 74, 28, 10, GOLD, { Radius = 4, Z = 5 }) -- plaid
	kit.Blob(body, 26, 56, 24, 16, WHITE, { Z = 5, Shine = true })
	kit.Blob(body, 30, 52, 20, 14, rgb(236, 220, 180), { Z = 6, Shine = true })
	kit.Blob(body, 34, 58, 12, 9, rgb(90, 70, 130), { Z = 7 })
	return nil
end

-- Billard (tapis vert, poches, bandes en bois, queue, boules) : dessus y = 44
Art.PoolTable = function(body, kit, _item)
	for _, x in ipairs({ 12, 50, 88 }) do
		local legPart = kit.Part(body, x - 5, 50, 10, 44, WALNUT_DARK, { Radius = 3, Z = 1, Shine = true })
		kit.Box(legPart, 0, 18, 10, 3, GOLD, 0, 2)
		kit.Part(body, x - 7, 92, 14, 7, WALNUT_DARK, { Radius = 3, Z = 1 })
	end
	local frame = kit.Part(body, 2, 42, 96, 14, WALNUT, { Radius = 4, Z = 2, Shine = true })
	kit.Box(frame, 4, 5, 88, 1.6, GOLD, 0.2, 2)
	local felt = kit.Part(body, 6, 38, 88, 7, rgb(30, 130, 80), { Radius = 3, Z = 3 })
	kit.Box(felt, 0, 0, 88, 1.4, rgb(60, 170, 110), 0, 2)
	for _, x in ipairs({ 6, 50, 94 }) do
		kit.Circle(body, x, 42, 7, 7, IRON_DARK, 0, 4)
	end
	-- boules + queue
	local colors = { rgb(250, 250, 240), rgb(240, 200, 40), RED, rgb(40, 90, 200), rgb(30, 30, 30), rgb(120, 50, 150) }
	for index, c in ipairs(colors) do
		kit.Circle(body, 28 + index * 7, 35 - (index % 2), 6, 6, c, 0, 5)
	end
	kit.Line(body, 10, 30, 30, 36, 2, rgb(214, 180, 120), 0, 6)
	kit.Line(body, 58, 24, 92, 34, 2.4, rgb(214, 180, 120), 0, 6)
	kit.Line(body, 90, 33.4, 93, 34.4, 2.4, IRON_DARK, 0, 7)
	-- lampe de billard au-dessus
	kit.Line(body, 30, 0, 30, 8, 1, IRON, 0, 1)
	kit.Line(body, 70, 0, 70, 8, 1, IRON, 0, 1)
	kit.Part(body, 22, 8, 56, 8, rgb(30, 90, 60), { Radius = 4, Z = 2, Shine = true })
	local glow = kit.Box(body, 26, 16, 48, 3, AMBER, 0.3, 2)
	kit.Animate(glow, "Pulse", 0.2, 1, 0)
	return { Glow = AMBER }
end

-- Géode d'améthyste géante (coquille de pierre, cristaux violets, socle)
Art.AmethystGeode = function(body, kit, _item)
	kit.Part(body, 26, 88, 48, 12, IRON_DARK, { Radius = 3, Z = 1, Shine = true })
	kit.Part(body, 34, 80, 32, 10, IRON, { Radius = 2, Z = 1 })
	local shell = kit.Blob(body, 50, 46, 70, 76, STONE, { Z = 2, Shine = true })
	kit.Blob(shell, 35, 38, 58, 64, rgb(236, 230, 240), { Z = 2, Outline = false })
	local inner = kit.Blob(shell, 35, 38, 50, 56, rgb(110, 60, 160), { Z = 3, Outline = false })
	local purples = { rgb(170, 110, 230), rgb(140, 80, 210), rgb(200, 150, 250), rgb(120, 70, 190) }
	local n = 0
	for row = 0, 4 do
		for col = 0, 3 do
			n += 1
			local d = kit.Diamond(inner, 8 + col * 11 + (row % 2) * 5, 8 + row * 10, 8 + (n % 3) * 2, purples[(n % #purples) + 1], 0, 2 + n % 2)
			local _ = d
		end
	end
	local glow = kit.Circle(inner, 25, 28, 30, 30, rgb(220, 180, 255), 0.6, 4)
	kit.Animate(glow, "Pulse", 0.25, 0.8, 0)
	kit.Sparkle(body, 64, 24, 10, WHITE, 0, 6)
	kit.Sparkle(body, 38, 58, 7, WHITE, 0, 6)
	return { Glow = rgb(200, 150, 250) }
end

-- Cheminée murale design (longue flamme derrière la vitre, pierre)
Art.ModernFireplace = function(body, kit, _item)
	local slab = kit.Part(body, 2, 22, 96, 56, rgb(64, 64, 70), { Radius = 3, Z = 1, Shine = true })
	kit.Box(slab, 0, 0, 96, 6, rgb(90, 90, 96), 0, 2)
	local box = kit.Part(body, 8, 38, 84, 28, rgb(20, 18, 22), { Radius = 2, Z = 2, Outline = STEEL, Thickness = 2 })
	-- lit de galets + flammes
	for k = 0, 9 do
		kit.Blob(box, 6 + k * 8, 25, 9, 5, k % 2 == 0 and rgb(200, 196, 190) or rgb(150, 146, 144), { Z = 3, Outline = false })
	end
	for k = 0, 7 do
		local flame = kit.Blob(box, 9 + k * 10, 16, 8, 16 + (k % 3) * 3, k % 2 == 0 and FIRE or rgb(255, 200, 80), { Z = 2, Outline = false, T = 0.1 })
		kit.Animate(flame, "Flicker", 0.25, 1, k * 0.7)
	end
	local glass = kit.Box(box, 0, 0, 84, 28, WHITE, 0.88, 4)
	local _ = glass
	kit.Line(box, 6, 22, 20, 4, 2, WHITE, 0.7, 5)
	return { Glow = FIRE, WallShadow = Vector2.new(96, 56) }
end

-- Rangée de fauteuils de cinéma (3 sièges cuir rouge, porte-gobelets) : dessus y = 62
Art.CinemaRecliners = function(body, kit, _item)
	local leather = rgb(170, 40, 50)
	kit.Part(body, 2, 90, 96, 9, IRON_DARK, { Radius = 3, Z = 1 })
	for index = 0, 2 do
		local x = 4 + index * 32
		kit.Part(body, x + 2, 24, 26, 44, leather, { Radius = 10, Z = 2, Shine = true })
		kit.Part(body, x + 5, 28, 20, 18, kit.Darken(leather, 0.15), { Radius = 8, Z = 3 })
		kit.Part(body, x + 2, 58, 26, 18, leather, { Radius = 7, Z = 4, Shine = true })
		kit.Part(body, x + 4, 74, 22, 16, kit.Darken(leather, 0.2), { Radius = 5, Z = 3 }) -- repose-pieds
	end
	for index = 0, 3 do
		local x = 2 + index * 32
		kit.Part(body, x - 2, 46, 8, 44, rgb(40, 36, 40), { Radius = 3, Z = 5, Shine = true })
		kit.Circle(body, x + 2, 48, 5, 5, IRON, 0, 6) -- porte-gobelet
	end
	-- pop-corn
	kit.Part(body, 62, 36, 8, 10, WHITE, { Radius = 1, Z = 6 })
	kit.Box(body, 62, 38, 2, 8, RED, 0, 7)
	kit.Box(body, 66, 38, 2, 8, RED, 0, 7)
	for k = 0, 3 do
		kit.Circle(body, 63 + k * 2, 35 - k % 2, 4, 4, rgb(255, 240, 190), 0, 7)
	end
	local led = kit.Box(body, 4, 88, 92, 2, AMBER, 0.2, 2)
	kit.Animate(led, "Pulse", 0.3, 1, 0)
	return nil
end

-- Piano de concert blanc (couvercle ouvert, clavier, pédales dorées)
Art.WhitePiano = function(body, kit, _item)
	for _, x in ipairs({ 18, 82 }) do
		kit.Part(body, x - 4, 58, 8, 40, rgb(236, 236, 240), { Radius = 3, Z = 1, Shine = true })
		kit.Circle(body, x, 97, 7, 5, GOLD, 0, 2)
	end
	-- couvercle levé + béquille
	kit.Line(body, 70, 50, 70, 16, 2, GOLD, 0, 1)
	local lid = kit.Part(body, 14, 8, 80, 10, WHITE, { Radius = 5, Z = 2, Rotation = -14, Shine = true })
	local _ = lid
	local case = kit.Part(body, 6, 34, 90, 26, WHITE, { Radius = 12, Z = 3, Shine = true })
	kit.Box(case, 6, 4, 70, 1.4, GOLD, 0.2, 2)
	-- clavier
	local keys = kit.Part(body, 4, 54, 50, 9, WHITE, { Radius = 2, Z = 4, Outline = rgb(150, 150, 160) })
	for k = 0, 11 do
		kit.Box(keys, 2 + k * 4, 0, 0.6, 9, rgb(170, 170, 180), 0, 2)
		if k % 7 ~= 2 and k % 7 ~= 6 then
			kit.Box(keys, 4.4 + k * 4, 0, 2, 5, rgb(30, 30, 36), 0, 3)
		end
	end
	-- lyre + pédales
	kit.Part(body, 42, 76, 8, 14, rgb(236, 236, 240), { Radius = 2, Z = 2 })
	for k = 0, 2 do
		kit.Part(body, 40 + k * 4, 90, 3, 5, GOLD, { Radius = 1, Z = 3 })
	end
	kit.Text(body, "♪", 80, 26, 12, GOLD_DARK, 5)
	return nil
end

-- Jacuzzi (cuve ronde, eau turquoise, bulles, marches, LED) : assis dedans
Art.Jacuzzi = function(body, kit, _item)
	kit.Part(body, 0, 60, 100, 40, rgb(236, 230, 220), { Radius = 10, Z = 1, Shine = true })
	for k = 0, 5 do
		kit.Box(body, 4 + k * 16, 64, 1, 34, rgb(214, 204, 190), 0, 2)
	end
	kit.Part(body, 2, 54, 96, 10, rgb(210, 200, 186), { Radius = 5, Z = 3 })
	local water = kit.Part(body, 8, 44, 84, 14, WATER, { Radius = 7, Z = 4, T = 0.1, Shine = true })
	kit.Gradient(water, WATER_LIGHT, WATER_DEEP, 90)
	for k = 0, 5 do
		local foam = kit.Blob(water, 10 + k * 13, 3, 12, 6, WHITE, { Z = 3, Outline = false, T = 0.2 })
		kit.Animate(foam, "Breathe", 0.12, 1.4, k)
	end
	bubbles(kit, body, 30, 42, 4, 6)
	bubbles(kit, body, 66, 40, 4, 6)
	-- LED bleue + marches
	local led = kit.Box(body, 10, 70, 80, 2, CYAN, 0.2, 3)
	kit.Animate(led, "Pulse", 0.4, 1, 0)
	kit.Part(body, 36, 90, 28, 8, rgb(214, 204, 190), { Radius = 2, Z = 4 })
	-- serviettes roulées + bougie
	kit.Part(body, 76, 46, 16, 8, WHITE, { Radius = 4, Z = 5 })
	kit.Part(body, 78, 40, 12, 7, rgb(160, 210, 230), { Radius = 3, Z = 6 })
	kit.Part(body, 10, 44, 6, 8, rgb(250, 240, 220), { Radius = 2, Z = 5 })
	local flame = kit.Blob(body, 13, 42, 3, 5, FIRE, { Z = 6, Outline = false })
	kit.Animate(flame, "Flicker", 0.3, 1, 0)
	return { Glow = CYAN }
end

-- Mur d'aquarium (grand bassin encastré, coraux, poissons, lumière)
Art.AquariumWall = function(body, kit, _item)
	local frame = kit.Part(body, 2, 4, 96, 96, IRON_DARK, { Radius = 4, Z = 1, Shine = true })
	local tank = kit.Part(frame, 4, 8, 88, 76, WATER, { Radius = 2, Z = 2, Outline = false })
	kit.Gradient(tank, WATER_LIGHT, WATER_DEEP, 90)
	local clip = kit.Group(tank, 0, 0, 88, 76, 3, true)
	-- sable + coraux + algues
	kit.Blob(clip, 44, 78, 100, 20, rgb(236, 214, 160), { Z = 1, Outline = false })
	for index, s in ipairs({ { 12, rgb(255, 110, 120) }, { 30, rgb(255, 170, 80) }, { 60, rgb(200, 110, 230) }, { 78, rgb(255, 130, 160) } }) do
		for k = 0, 2 do
			kit.Line(clip, s[1], 70, s[1] + (k - 1) * 6, 54 - k * 3, 3, s[2], 0, 2)
		end
		local _ = index
	end
	for _, x in ipairs({ 22, 48, 70 }) do
		local weed = kit.Line(clip, x, 72, x + 2, 36, 3, LEAF, 0, 1)
		kit.Animate(weed, "Sway", 4, 0.8, x)
	end
	fish(kit, clip, 24, 22, 12, rgb(255, 150, 40), 1, 4)
	fish(kit, clip, 62, 32, 10, rgb(255, 220, 60), -1, 4)
	fish(kit, clip, 40, 44, 14, rgb(60, 140, 255), 1, 4)
	fish(kit, clip, 74, 14, 9, rgb(255, 100, 140), -1, 4)
	fish(kit, clip, 14, 40, 8, WHITE, -1, 4)
	bubbles(kit, clip, 80, 60, 5, 5)
	-- rayons de lumière
	for k = 0, 2 do
		local ray = kit.Box(clip, 10 + k * 28, 0, 10, 76, WHITE, 0.85, 5)
		ray.Rotation = 12
	end
	kit.Part(body, 2, 4, 96, 8, rgb(60, 62, 70), { Radius = 3, Z = 3 })
	kit.Part(body, 2, 88, 96, 12, rgb(80, 64, 50), { Radius = 3, Z = 3, Shine = true })
	return { Glow = WATER_LIGHT }
end

-- Mini montagnes russes (maquette : rails, looping, wagonnets qui roulent)
Art.RollercoasterModel = function(body, kit, _item)
	kit.Part(body, 2, 90, 96, 10, rgb(60, 140, 90), { Radius = 4, Z = 1, Shine = true })
	-- piliers
	for _, spec in ipairs({ { 14, 60 }, { 30, 30 }, { 46, 50 }, { 84, 44 } }) do
		kit.Part(body, spec[1] - 1.5, spec[2], 3, 90 - spec[2], rgb(230, 230, 240), { Radius = 1, Z = 2 })
	end
	-- rail (points reliés)
	local rail = { { 4, 80 }, { 14, 60 }, { 24, 34 }, { 30, 28 }, { 36, 34 }, { 46, 50 }, { 56, 66 }, { 66, 72 }, { 74, 66 }, { 78, 54 },
		{ 76, 40 }, { 70, 34 }, { 64, 40 }, { 66, 52 }, { 76, 58 }, { 88, 44 }, { 96, 36 } }
	for index = 1, #rail - 1 do
		local a, c = rail[index], rail[index + 1]
		kit.Line(body, a[1], a[2], c[1], c[2], 3.4, RED, 0, 3)
		kit.Line(body, a[1], a[2] + 2.4, c[1], c[2] + 2.4, 1.2, rgb(160, 30, 40), 0, 3)
	end
	-- 3 wagonnets sur la descente
	for k = 0, 2 do
		local x = 38 + k * 6
		local y = 38 + k * 9
		local car = kit.Part(body, x - 3, y - 6, 7, 6, k == 0 and rgb(255, 214, 60) or rgb(60, 160, 255), { Radius = 2, Z = 5, Rotation = 55 })
		kit.Circle(car, 3.5, -1, 3.4, 3.4, rgb(240, 200, 170), 0, 2)
	end
	-- entrée + drapeaux
	kit.Part(body, 4, 76, 16, 14, rgb(255, 230, 180), { Radius = 2, Z = 4 })
	kit.Triangle(body, 12, 66, 20, 10, rgb(236, 72, 120), 5)
	local flag = kit.Box(body, 96, 30, 6, 4, rgb(255, 214, 60), 0, 5)
	kit.Animate(flag, "Sway", 8, 1.2, 0)
	return nil
end

-- Trône en or (dossier haut sculpté, velours rouge, lions) : dessus y = 58
Art.GoldThrone = function(body, kit, _item)
	kit.Part(body, 14, 92, 72, 8, GOLD_DARK, { Radius = 3, Z = 1, Shine = true }) -- estrade
	local back = kit.Part(body, 24, 2, 52, 62, GOLD, { Radius = 14, Z = 2, Shine = true })
	kit.Part(back, 8, 12, 36, 44, rgb(170, 30, 50), { Radius = 10, Z = 2, Shine = true })
	kit.Diamond(back, 26, 30, 8, GOLD_LIGHT, 0, 3)
	-- couronne en haut du dossier
	for k = 0, 2 do
		kit.Triangle(body, 38 + k * 12, -6, 10, 12, GOLD, 3)
		kit.Circle(body, 38 + k * 12, -6, 5, 5, rgb(236, 72, 100), 0, 4)
	end
	kit.Part(body, 22, 56, 56, 12, rgb(170, 30, 50), { Radius = 6, Z = 4, Shine = true })
	kit.Part(body, 20, 66, 60, 26, GOLD, { Radius = 6, Z = 3, Shine = true })
	for _, x in ipairs({ 22, 78 }) do
		kit.Part(body, x - 8, 40, 16, 30, GOLD, { Radius = 7, Z = 5, Shine = true }) -- accoudoirs
		kit.Blob(body, x, 40, 16, 14, GOLD_LIGHT, { Z = 6, Shine = true }) -- tête de lion
		kit.Circle(body, x, 42, 5, 4, GOLD_DARK, 0, 7)
		clawFoot(kit, body, x, 94, 12, 4)
	end
	kit.Sparkle(body, 88, 14, 10, GOLD_LIGHT, 0, 8)
	kit.Sparkle(body, 12, 30, 7, WHITE, 0, 8)
	return { Glow = GOLD_LIGHT }
end

-- Cascade intérieure (mur de pierre, eau qui tombe, bassin, plantes)
Art.IndoorWaterfall = function(body, kit, _item)
	local wall = kit.Part(body, 8, 2, 84, 80, STONE, { Radius = 4, Z = 1, Shine = true })
	for index, s in ipairs({ { 10, 10, 20 }, { 50, 8, 24 }, { 28, 30, 18 }, { 62, 34, 20 }, { 12, 54, 22 }, { 56, 58, 18 } }) do
		kit.Part(wall, s[1], s[2], s[3], 14, index % 2 == 0 and STONE_DARK or rgb(170, 164, 156), { Radius = 5, Z = 2, Thickness = 1 })
	end
	-- nappe d'eau (bandes qui descendent)
	local fall = kit.Group(body, 30, 6, 40, 76, 3, true)
	kit.Box(fall, 0, 0, 40, 76, WATER, 0.25, 1)
	for k = 0, 5 do
		local streak = kit.Box(fall, 3 + k * 6.4, 0, 2, 30, WATER_LIGHT, 0.3, 2)
		kit.Animate(streak, "Bob", 10, 1.4 + k * 0.1, k)
	end
	-- bassin
	kit.Part(body, 0, 80, 100, 20, STONE_DARK, { Radius = 6, Z = 4, Shine = true })
	local pool = kit.Part(body, 6, 78, 88, 8, WATER, { Radius = 4, Z = 5, Shine = true })
	kit.Gradient(pool, WATER_LIGHT, WATER_DEEP, 90)
	for k = 0, 3 do
		local splash = kit.Blob(body, 38 + k * 8, 78, 8, 5, WHITE, { Z = 6, Outline = false, T = 0.3 })
		kit.Animate(splash, "Breathe", 0.2, 1.6, k)
	end
	-- fougères de chaque côté
	for _, x in ipairs({ 10, 90 }) do
		for k = 0, 2 do
			kit.Blob(body, x + (k - 1) * 5, 74 - k * 6, 10, 20, k % 2 == 0 and LEAF or LEAF_DARK, { Z = 7, Rotation = (k - 1) * 25 })
		end
	end
	return { Glow = WATER_LIGHT }
end

-- Lit capsule spatiale (coque blanche, hublot, néon bleu) : on s'y couche
Art.CapsuleBed = function(body, kit, _item)
	kit.Part(body, 6, 90, 88, 8, IRON, { Radius = 3, Z = 1 })
	local shell = kit.Part(body, 2, 22, 96, 72, rgb(240, 242, 248), { Radius = 34, Z = 2, Shine = true })
	kit.Box(shell, 8, 60, 80, 2, rgb(200, 204, 214), 0, 2)
	local inner = kit.Part(shell, 10, 12, 76, 44, rgb(40, 50, 90), { Radius = 20, Z = 2 })
	-- étoiles dans le ciel de la capsule
	for k = 0, 7 do
		local star = kit.Circle(inner, 8 + (k * 17) % 60, 6 + (k * 11) % 20, 2, 2, WHITE, 0.1, 2)
		kit.Animate(star, "Pulse", 0.6, 1, k)
	end
	kit.Part(inner, 4, 28, 68, 14, rgb(200, 210, 240), { Radius = 6, Z = 3 }) -- matelas
	kit.Part(inner, 30, 24, 42, 16, rgb(90, 120, 220), { Radius = 6, Z = 4 }) -- couette
	kit.Blob(inner, 18, 30, 16, 10, WHITE, { Z = 4 })
	local neon = kit.Part(shell, 10, 58, 76, 2, CYAN, { Radius = 1, Z = 3, Outline = false })
	kit.Animate(neon, "Pulse", 0.4, 1, 0)
	-- panneau de contrôle + écusson
	kit.Part(body, 80, 30, 12, 20, IRON_DARK, { Radius = 3, Z = 4 })
	for k = 0, 2 do
		kit.Circle(body, 86, 35 + k * 5, 3, 3, ({ RED, CYAN, rgb(140, 240, 110) })[k + 1], 0, 5)
	end
	kit.Text(body, "🚀", 50, 84, 10, WHITE, 5)
	return { Glow = CYAN }
end

-- Statue de dragon d'or (corps enroulé, ailes, perle)
Art.DragonStatue = function(body, kit, _item)
	kit.Part(body, 10, 88, 80, 12, rgb(60, 50, 50), { Radius = 3, Z = 1, Shine = true })
	kit.Part(body, 16, 84, 68, 6, GOLD_DARK, { Radius = 2, Z = 2 })
	-- ailes
	for _, dir in ipairs({ -1, 1 }) do
		local wing = kit.Pivot(body, 50 + dir * 10, 40, 2)
		for k = 0, 3 do
			local rib = kit.Line(wing, 0, 0, dir * (26 - k * 4), -24 + k * 10, 2, GOLD_DARK, 0, 1)
			local _ = rib
		end
		kit.Triangle(wing, dir * 16, -24, 26, 30, GOLD, 1, 0.1)
		kit.Animate(wing, "Sway", 3, 0.8, dir)
	end
	-- corps (anneaux)
	local coil = { { 30, 78, 26 }, { 50, 74, 28 }, { 70, 70, 24 }, { 62, 56, 22 }, { 46, 50, 22 }, { 42, 36, 20 } }
	for index, s in ipairs(coil) do
		local seg = kit.Blob(body, s[1], s[2], s[3], s[3] * 0.8, GOLD, { Z = 3 + index % 2, Shine = true })
		for k = 0, 2 do
			kit.Box(seg, s[3] * 0.2 + k * s[3] * 0.2, s[3] * 0.1, 2, 2, GOLD_DARK, 0.2, 2)
		end
	end
	-- tête
	local head = kit.Blob(body, 50, 22, 28, 20, GOLD, { Z = 6, Shine = true })
	kit.Circle(head, 20, 8, 5, 5, RED, 0, 3)
	kit.Line(head, 22, 16, 30, 16, 1.4, GOLD_DARK, 0, 3)
	kit.Triangle(body, 40, 6, 6, 10, GOLD_DARK, 7)
	kit.Triangle(body, 50, 4, 6, 10, GOLD_DARK, 7)
	-- moustaches
	kit.Line(body, 62, 26, 80, 32, 1.4, GOLD_LIGHT, 0, 7)
	kit.Line(body, 62, 28, 76, 38, 1.4, GOLD_LIGHT, 0, 7)
	-- perle
	local pearl = kit.Circle(body, 84, 60, 12, 12, rgb(240, 236, 255), 0, 6)
	kit.Shine(pearl, 2, 2, 4, 3, 3, 0.2)
	local halo = kit.Circle(body, 84, 60, 20, 20, rgb(200, 220, 255), 0.6, 5)
	kit.Animate(halo, "Pulse", 0.3, 1, 0)
	return { Glow = GOLD_LIGHT }
end

-- Tunnel aquarium (arche de verre où l'on passe dessous, poissons, raie)
Art.AquariumTunnel = function(body, kit, _item)
	local arch = kit.Part(body, 0, 4, 100, 96, IRON_DARK, { Radius = 48, Z = 1, Shine = true })
	local water = kit.Part(arch, 4, 4, 92, 92, WATER, { Radius = 44, Z = 2, Outline = false })
	kit.Gradient(water, WATER_LIGHT, WATER_DEEP, 90)
	local clip = kit.Group(water, 0, 0, 92, 92, 3, true)
	-- raie manta + poissons + tortue
	local ray = kit.Pivot(clip, 46, 20, 4)
	kit.Diamond(ray, 0, 0, 20, rgb(60, 70, 110), 0, 1)
	kit.Line(ray, 0, 6, 0, 20, 1.4, rgb(60, 70, 110), 0, 1)
	kit.Animate(ray, "Drift", 10, 0.4, 0)
	fish(kit, clip, 18, 36, 10, rgb(255, 150, 40), 1, 5)
	fish(kit, clip, 72, 40, 12, rgb(255, 220, 60), -1, 5)
	fish(kit, clip, 30, 16, 8, rgb(255, 100, 140), 1, 5)
	fish(kit, clip, 64, 12, 9, WHITE, -1, 5)
	local turtle = kit.Pivot(clip, 76, 24, 5)
	kit.Blob(turtle, 0, 0, 16, 11, rgb(100, 150, 90), { Z = 2, Shine = true })
	kit.Blob(turtle, 9, -1, 6, 5, rgb(140, 180, 110), { Z = 1 })
	kit.Animate(turtle, "Bob", 2, 0.7, 0)
	bubbles(kit, clip, 12, 60, 4, 6)
	bubbles(kit, clip, 82, 64, 4, 6)
	-- le passage (tunnel sous l'eau) : sol + arche intérieure en verre
	local passage = kit.Part(clip, 22, 50, 48, 50, rgb(170, 220, 240), { Radius = 24, Z = 6, T = 0.35, Outline = rgb(220, 240, 255), Thickness = 2 })
	kit.Box(passage, 0, 36, 48, 14, rgb(60, 70, 90), 0, 2)
	kit.Box(passage, 22, 36, 4, 14, rgb(90, 100, 120), 0, 3)
	for k = 0, 2 do
		kit.Box(clip, 22, 60 + k * 10, 48, 1, WHITE, 0.6, 7)
	end
	kit.Part(body, 0, 92, 100, 8, rgb(70, 72, 84), { Radius = 3, Z = 3 })
	return { Glow = WATER_LIGHT }
end

----------------------------------------------------------------------
-- 💡 Lumières de luxe
----------------------------------------------------------------------

-- Dôme planétarium (demi-sphère étoilée qui tourne, socle)
Art.PlanetariumDome = function(body, kit, _item)
	kit.Part(body, 26, 84, 48, 14, IRON_DARK, { Radius = 5, Z = 1, Shine = true })
	kit.Part(body, 44, 60, 12, 26, IRON, { Radius = 3, Z = 2 })
	local halo = kit.Circle(body, 50, 44, 90, 70, rgb(120, 100, 255), 0.8, 1)
	kit.Animate(halo, "Pulse", 0.12, 0.8, 0)
	local dome = kit.Circle(body, 50, 44, 70, 70, rgb(30, 30, 80), 0, 3)
	kit.Stroke(dome, rgb(150, 130, 255), 2, 0)
	local sky = kit.Pivot(dome, 35, 35, 2)
	for k = 0, 13 do
		local a = k * 2.4
		local r = 6 + (k * 7) % 26
		kit.Sparkle(sky, math.cos(a) * r, math.sin(a) * r, 3 + k % 3 * 2, k % 3 == 0 and rgb(255, 230, 150) or WHITE, 0, 1)
	end
	kit.Circle(sky, 14, -12, 10, 10, rgb(255, 170, 100), 0, 2) -- planète
	kit.Animate(sky, "Spin", 1, 0.05, 0)
	kit.Shine(dome, 14, 10, 18, 7, 4, 0.55)
	return { Glow = rgb(150, 130, 255) }
end

-- Grand lustre en cristal (étages de pampilles, bougies, chaîne dorée)
Art.GrandChandelier = function(body, kit, _item)
	kit.Line(body, 50, 0, 50, 14, 2, GOLD_DARK, 0, 1)
	kit.Part(body, 42, 12, 16, 6, GOLD, { Radius = 3, Z = 2 })
	local bulbs = {}
	for tier = 0, 2 do
		local w = 40 + tier * 26
		local y = 26 + tier * 18
		kit.Part(body, 50 - w / 2, y, w, 5, GOLD, { Radius = 3, Z = 3 + tier, Shine = true })
		local n = 3 + tier * 2
		for k = 0, n - 1 do
			local x = 50 - w / 2 + 4 + k * (w - 8) / math.max(1, n - 1)
			local drop = kit.Diamond(body, x, y + 11, 5, rgb(220, 240, 255), 0.1, 6)
			kit.Line(body, x, y + 4, x, y + 9, 0.8, rgb(220, 240, 255), 0.2, 5)
			kit.Animate(drop, "Sway", 6, 0.8, x)
			-- bougie + flamme
			kit.Part(body, x - 1.5, y - 7, 3, 7, rgb(250, 244, 230), { Radius = 1, Z = 4 + tier })
			local flame = kit.Blob(body, x, y - 9, 3.4, 5, AMBER, { Z = 7, Outline = false })
			kit.Animate(flame, "Flicker", 0.3, 1, x)
			table.insert(bulbs, flame)
		end
	end
	for k = 0, 4 do
		kit.Line(body, 50, 18, 20 + k * 15, 62, 1, GOLD_DARK, 0.3, 2)
	end
	local drop = kit.Diamond(body, 50, 86, 10, rgb(220, 240, 255), 0, 8)
	kit.Animate(drop, "Sway", 4, 0.6, 0)
	local halo = kit.Circle(body, 50, 50, 100, 70, AMBER, 0.8, 1)
	table.insert(bulbs, halo)
	return { Glow = AMBER, Bulbs = bulbs, WallShadow = Vector2.new(0, 0) }
end

----------------------------------------------------------------------
-- 📺 Télés XXL et écran de home cinéma (Dopamine Setup, DESK98)
----------------------------------------------------------------------

-- Scène "live" du clicker sur un écran (streameur, chat, compteur)
local function liveScene(kit, screen, w, h)
	local clip = kit.Group(screen, 0, 0, w, h, 2, true)
	kit.Box(clip, 0, 0, w, h, rgb(60, 40, 110), 0, 1)
	kit.Gradient(kit.Box(clip, 0, 0, w, h, WHITE, 0, 1), rgb(120, 80, 220), rgb(236, 90, 170), 90)
	-- streameur
	kit.Blob(clip, w * 0.34, h * 0.95, w * 0.34, h * 0.5, rgb(60, 60, 90), { Z = 2, Outline = false })
	kit.Circle(clip, w * 0.34, h * 0.5, w * 0.18, w * 0.18, rgb(255, 214, 180), 0, 3)
	kit.Box(clip, w * 0.24, h * 0.36, w * 0.2, h * 0.08, rgb(90, 60, 50), 0, 4)
	-- chat du live
	local chat = kit.Box(clip, w * 0.66, h * 0.1, w * 0.3, h * 0.8, rgb(20, 20, 40), 0.35, 3)
	kit.Round(chat, 3)
	for k = 0, 3 do
		kit.Box(chat, 3, 4 + k * h * 0.17, w * 0.24 - (k % 2) * 6, 2.4, k % 2 == 0 and CYAN or MAGENTA, 0.1, 2)
	end
	local live = kit.Box(clip, 4, 4, 22, 9, RED, 0, 5)
	kit.Round(live, 2)
	kit.Text(live, "LIVE", 11, 4.5, 6, WHITE, 2)
	kit.Animate(live, "Pulse", 0.5, 2, 0)
	kit.Text(clip, "👁 12.4K", w * 0.2, h - 8, 6, WHITE, 5)
end

-- Télé cinéma XXL sur pied (bords ultra-fins, barre de son, pieds chromés)
Art.SetupTVCinemaXXL = function(body, kit, _item)
	for _, x in ipairs({ 16, 84 }) do
		kit.Line(body, x, 86, x + (x < 50 and -6 or 6), 99, 3, STEEL, 0, 1)
	end
	local panel = kit.Part(body, 0, 22, 100, 60, rgb(20, 20, 26), { Radius = 2, Z = 2, Outline = rgb(90, 92, 100), Thickness = 1.2 })
	local screen = kit.Part(panel, 1.5, 1.5, 97, 57, SCREEN, { Radius = 1, Z = 2, Outline = false, Shade = false })
	liveScene(kit, screen, 97, 57)
	kit.Line(screen, 60, 4, 80, 30, 6, WHITE, 0.88, 6)
	kit.Part(body, 14, 86, 72, 7, rgb(40, 40, 48), { Radius = 3, Z = 3, Shine = true })
	kit.Box(body, 18, 88, 64, 3, rgb(70, 70, 84), 0, 4)
	kit.Text(body, "XXL", 90, 16, 8, CYAN, 4)
	return { Glow = rgb(170, 110, 255) }
end

-- Télé murale XXL (très fine, ambilight derrière, sans pied)
Art.SetupTVWallXXL = function(body, kit, _item)
	local halo = kit.Part(body, -4, 12, 108, 70, CYAN, { Radius = 12, Z = 1, T = 0.72, Outline = false, Shade = false })
	kit.Animate(halo, "Pulse", 0.15, 1, 0)
	local panel = kit.Part(body, 0, 18, 100, 60, rgb(20, 20, 26), { Radius = 2, Z = 2, Outline = rgb(90, 92, 100), Thickness = 1.2 })
	local screen = kit.Part(panel, 1.5, 1.5, 97, 57, SCREEN, { Radius = 1, Z = 2, Outline = false, Shade = false })
	liveScene(kit, screen, 97, 57)
	kit.Line(screen, 60, 4, 80, 30, 6, WHITE, 0.88, 6)
	kit.Box(body, 46, 76, 8, 1.2, STEEL, 0, 3)
	return { Glow = CYAN, WallShadow = Vector2.new(100, 60) }
end

-- Écran de home cinéma (toile géante bordée de noir, carter enroulable,
-- petit projecteur suspendu qui éclaire la toile)
Art.SetupCinemaScreen = function(body, kit, _item)
	kit.Part(body, -2, 6, 104, 8, rgb(40, 40, 48), { Radius = 4, Z = 2, Shine = true })
	local border = kit.Part(body, 0, 12, 100, 66, rgb(16, 16, 20), { Radius = 1, Z = 1, Outline = false })
	local canvas = kit.Part(border, 3, 3, 94, 60, WHITE, { Radius = 1, Z = 2, Outline = false, Shade = false })
	liveScene(kit, canvas, 94, 60)
	kit.Box(body, 46, 78, 8, 6, rgb(40, 40, 48), 0, 2) -- poignée de la toile
	-- projecteur suspendu (coin haut droit) + son faisceau
	kit.Line(body, 90, -6, 90, 2, 1.4, IRON, 0, 4)
	kit.Part(body, 80, 0, 20, 9, rgb(236, 238, 244), { Radius = 3, Z = 5, Shine = true })
	local lens = kit.Circle(body, 84, 5, 6, 6, rgb(60, 100, 160), 0, 6)
	kit.Animate(lens, "Pulse", 0.3, 1.2, 0)
	kit.Line(body, 82, 8, 50, 44, 18, WHITE, 0.9, 3)
	kit.Text(body, "🎬", 8, 86, 10, WHITE, 5)
	return { Glow = rgb(170, 110, 255), WallShadow = Vector2.new(100, 66) }
end

return Art
