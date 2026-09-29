--[[
	House3DLuxe (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DLuxe

	(v9.8 CATALOG98) Modèles 3D des 65 nouveaux objets de la maison : moderne /
	minimaliste, loft industriel, déco, lumières, plantes, tech, cuisine,
	coin gamer, sport, 💎 luxe et objets "incroyables" (tunnel aquarium,
	cascade intérieure, dragon d'or, mini montagnes russes...). Les télés XXL
	et l'écran de home cinéma (catégorie Setup) sont dessinés par
	House3DSetup (DESK98), pas ici.

	Mêmes conventions que House3DRecipes (Register) : House3DKit.Builder,
	boîte 2D = 100 unités, y = hauteur depuis le sol, +z = le devant (le
	modèle final de BuildModel regarde -Z) ; objets muraux : z = 0 = le mur,
	y = 100 - y du dessin 2D. Les dessus (b.Top) sont aux hauteurs de
	HouseSurfaces (ctx.TopY) : ce qu'on pose dessus tombe juste. Les sièges
	(b.Seat) donnent une "SeatPart" dans le monde.
	Matières réalistes (bois, métal, cuir, tissu, marbre, verre) ; lumières
	douces (b.Light : Brightness <= 0.9, portée courte) ; Neon réservé aux
	petites pièces (ampoules, bandes LED, écrans).

	Branché par House3DRecipes : loadFamilies("House3DLuxe").
]]

local House3DKit = require(script.Parent.House3DKit)

type Builder = House3DKit.Builder

local House3DLuxe = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local OAK = rgb(214, 172, 120)
local OAK_DARK = rgb(170, 128, 84)
local WALNUT = rgb(128, 84, 56)
local WALNUT_DARK = rgb(92, 60, 42)
local STEEL = rgb(186, 192, 204)
local STEEL_DARK = rgb(112, 118, 132)
local IRON = rgb(64, 66, 76)
local IRON_DARK = rgb(40, 42, 50)
local CONCRETE = rgb(176, 174, 170)
local LEATHER = rgb(142, 80, 50)
local LINEN = rgb(226, 220, 208)
local GREIGE = rgb(176, 168, 158)
local MARBLE = rgb(240, 238, 236)
local MARBLE_VEIN = rgb(188, 186, 194)
local GLASS = rgb(186, 222, 236)
local LEAF = rgb(84, 150, 84)
local LEAF_DARK = rgb(52, 110, 62)
local LEAF_LIGHT = rgb(128, 190, 110)
local TERRACOTTA = rgb(206, 116, 80)
local CERAMIC = rgb(236, 232, 226)
local SCREEN = rgb(30, 36, 60)
local CYAN = rgb(60, 222, 255)
local MAGENTA = rgb(255, 84, 196)
local LIME = rgb(140, 240, 110)
local RED = rgb(226, 64, 70)
local ORANGE = rgb(255, 150, 60)
local AMBER = rgb(255, 214, 150)
local BLUE = rgb(70, 130, 220)
local GOLD = rgb(236, 190, 70)
local GOLD_DARK = rgb(180, 136, 40)
local GOLD_LIGHT = rgb(255, 226, 130)
local VELVET = rgb(120, 60, 150)
local WATER = rgb(80, 180, 230)
local WATER_DEEP = rgb(30, 110, 190)
local STONE = rgb(150, 146, 140)
local STONE_DARK = rgb(104, 100, 98)
local FIRE = rgb(255, 150, 60)
local FELT = rgb(30, 130, 80)
local darken = House3DKit.Darken
local lighten = House3DKit.Lighten

local R: { [string]: (b: Builder, ctx: any) -> () } = {}

----------------------------------------------------------------------
-- Petits outils
----------------------------------------------------------------------

local function glass(part: BasePart, transparency: number): BasePart
	part.Transparency = transparency
	part.CastShadow = false
	return part
end

-- Pièce lumineuse (Neon, pas d'ombre) : petites pièces seulement
local function glow(b: Builder, part: BasePart): BasePart
	b.Neon(part)
	return part
end

-- Rangée de livres posés sur une planche (bas = y), de x0 à x1, contre z
local BOOK_COLORS = { rgb(176, 64, 64), rgb(60, 96, 150), rgb(220, 190, 120), rgb(70, 120, 90), rgb(120, 80, 140), rgb(236, 226, 206), rgb(200, 120, 70) }
local function books(b: Builder, x0: number, x1: number, y: number, z: number, depth: number, maxH: number, seed: number)
	local x = x0
	local n = seed
	while x < x1 - 3 do
		n += 1
		local w = 3 + (n * 7) % 3
		local h = maxH * (0.7 + ((n * 13) % 5) * 0.07)
		if x + w > x1 then
			break
		end
		b.Box(x + w / 2, y, z, w - 0.3, h, depth, BOOK_COLORS[(n % #BOOK_COLORS) + 1], M.SmoothPlastic)
		x += w + 0.4
	end
end

-- Pot (bas = sol) avec terre ; renvoie le haut de la terre
local function pot(b: Builder, x: number, z: number, w: number, h: number, color: Color3, material: Enum.Material?): number
	b.Cyl(x, 0, z, w * 0.84, h - 3, color, material or M.SmoothPlastic)
	b.Cyl(x, h - 4, z, w, 4, lighten(color, 0.1), material or M.SmoothPlastic)
	b.Cyl(x, h - 3.2, z, w * 0.84, 2.6, rgb(92, 66, 48), M.Ground)
	return h - 0.6
end

-- Feuille plate (ovale fin) au bout d'une tige, orientée par (yaw, pitch)
local function leafAt(b: Builder, x: number, y: number, z: number, w: number, h: number, color: Color3, yaw: number, tilt: number)
	b.EggR(CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, tilt), w, h, 2.2, color, M.SmoothPlastic)
end

-- Petit poisson (ovale + queue) orienté vers +x (dir = 1) ou -x
local function fish(b: Builder, x: number, y: number, z: number, size: number, color: Color3, dir: number)
	b.Egg(x, y, z, size, size * 0.56, size * 0.34, color, M.SmoothPlastic)
	b.Wedge(x - dir * size * 0.62, y - size * 0.2, z, size * 0.34, size * 0.4, size * 0.12, darken(color, 0.1), dir > 0 and "Left" or "Right", M.SmoothPlastic)
	b.Ball(x + dir * size * 0.26, y + size * 0.06, z + size * 0.14, size * 0.12, rgb(30, 30, 40), M.SmoothPlastic)
end

-- Coussin carré posé (y = bas)
local function pillow(b: Builder, x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, lean: number?)
	b.EggR(CFrame.new(x, y + h / 2, z) * CFrame.Angles(lean or 0, 0, 0), w, h, d, color, M.Fabric)
end

----------------------------------------------------------------------
-- 🛋️ Moderne / minimaliste / loft
----------------------------------------------------------------------

R.SimpleChair = function(b, ctx)
	local seat = ctx.TopY(1, 44)
	local wood = b.Map(OAK)
	local white = b.Map(rgb(248, 248, 246))
	for _, sx in ipairs({ -1, 1 }) do
		b.Tube(sx * 22, 0, 18, sx * 20, seat - 4, 14, 5, wood, M.Wood)
		b.Tube(sx * 22, 0, -18, sx * 20, seat - 4, -14, 5, wood, M.Wood)
		b.Tube(sx * 18, seat, -16, sx * 16, seat + 30, -20, 4, wood, M.Wood)
	end
	b.Tube(-21, 14, 16.5, 21, 14, 16.5, 3, darken(wood, 0.1), M.Wood)
	b.Round(0, seat - 6, 0, 62, 6, 42, 8, white, M.SmoothPlastic)
	-- dossier incurvé (3 plaques)
	for index = -1, 1 do
		b.BoxR(CFrame.new(index * 15.5, seat + 36, -21 + math.abs(index) * 2.5) * CFrame.Angles(-0.12, -index * 0.28, 0), 16, 24, 3, white, M.SmoothPlastic)
	end
	b.Top(1, 0, seat, 2, 56, 36)
	b.Footprint(64, 46, seat + 48)
end

R.CoatRack = function(b, _ctx)
	local wood = b.Map(WALNUT)
	b.Cyl(0, 0, 0, 36, 3, darken(wood, 0.2), M.Wood)
	for index = 0, 2 do
		local a = index / 3 * math.pi * 2
		b.Tube(0, 14, 0, math.cos(a) * 16, 2, math.sin(a) * 16, 3, wood, M.Wood)
	end
	b.Cyl(0, 3, 0, 5, 90, wood, M.Wood)
	b.Ball(0, 94, 0, 8, b.Map(OAK), M.Wood)
	for index = 0, 3 do
		local a = index / 4 * math.pi * 2 + 0.4
		b.Tube(0, 84, 0, math.cos(a) * 10, 90, math.sin(a) * 10, 2.4, wood, M.Wood)
		b.Ball(math.cos(a) * 10, 90, math.sin(a) * 10, 4, b.Map(OAK), M.Wood)
	end
	-- manteau camel suspendu (côté gauche), écharpe rayée, chapeau
	local coat = b.Map(rgb(196, 150, 96))
	b.EggR(CFrame.new(-9, 62, 3) * CFrame.Angles(0, 0, 0.08), 18, 46, 12, coat, M.Fabric)
	b.Box(-9, 36, 3, 16, 12, 11, coat, M.Fabric)
	for index = 0, 2 do
		b.Ball(-4, 50 + index * 9, 9.2, 2.2, WALNUT_DARK, M.SmoothPlastic)
	end
	b.Box(8, 52, 4, 7, 34, 3, rgb(200, 60, 70), M.Fabric)
	for index = 0, 3 do
		b.Box(8, 56 + index * 8, 5.8, 7.4, 2, 0.8, WHITE, M.Fabric)
	end
	b.Cyl(12, 88, 6, 22, 1.6, rgb(60, 60, 72), M.Fabric)
	b.Cyl(12, 89.4, 6, 13, 9, rgb(60, 60, 72), M.Fabric)
	b.Cyl(12, 89.6, 6, 13.6, 2.2, rgb(170, 60, 60), M.Fabric)
	b.Footprint(40, 40, 100)
end

R.BarrelTable = function(b, ctx)
	local top = ctx.TopY(1, 70)
	local paint = b.Map(rgb(48, 96, 120))
	b.Cyl(0, 0, 0, 64, top - 4, paint, M.Metal)
	for _, y in ipairs({ 6, top * 0.45, top - 12 }) do
		b.Cyl(0, y, 0, 66, 2.5, darken(paint, 0.25), M.Metal)
	end
	-- étiquette peinte "DOPA" (plaque bombée à l'avant)
	b.Box(0, top * 0.55, 31.4, 26, 10, 1, rgb(240, 220, 170), M.SmoothPlastic)
	b.Box(0, top * 0.55 + 3.5, 32.1, 20, 2, 0.6, paint, M.SmoothPlastic)
	b.Cyl(0, top - 4, 0, 76, 4, b.Map(OAK), M.Wood)
	b.Top(1, 0, top, 0, 70, 70)
	b.Footprint(76, 76, top)
end

R.ModernBarStool = function(b, ctx)
	local seat = ctx.TopY(1, 70)
	local leather = b.Map(LEATHER)
	b.Cyl(0, 0, 0, 38, 2.5, STEEL_DARK, M.Metal)
	b.Cyl(0, 2.5, 0, 6, seat - 8, STEEL, M.Metal)
	-- repose-pieds en anneau (8 tubes)
	local ring = 14
	for index = 0, 7 do
		local a0, a1 = index / 8 * math.pi * 2, (index + 1) / 8 * math.pi * 2
		b.Tube(math.cos(a0) * ring, 28, math.sin(a0) * ring, math.cos(a1) * ring, 28, math.sin(a1) * ring, 2.4, STEEL, M.Metal)
	end
	for index = 0, 1 do
		local a = index * math.pi
		b.Tube(0, 28, 0, math.cos(a + 0.8) * ring, 28, math.sin(a + 0.8) * ring, 2, STEEL, M.Metal)
	end
	b.Cyl(0, seat - 9, 0, 34, 3, STEEL_DARK, M.Metal)
	b.Cyl(0, seat - 6, 0, 44, 6, leather, M.Leather)
	-- petit dossier bas
	b.BoxR(CFrame.new(0, seat + 6, -19) * CFrame.Angles(-0.15, 0, 0), 40, 12, 4, leather, M.Leather)
	for _, sx in ipairs({ -1, 1 }) do
		b.Tube(sx * 14, seat - 5, -16, sx * 14, seat + 2, -19, 3, STEEL, M.Metal)
	end
	b.Top(1, 0, seat, 2, 36, 34)
	b.Footprint(46, 46, seat + 13)
end

R.OakDesk = function(b, ctx)
	local top = ctx.TopY(1, 58)
	local x0, x1 = ctx.Span(1, -48, 48)
	local w, depth = x1 - x0, 50
	local oak = b.Map(OAK)
	-- pieds "épingle" (2 tiges par pied)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = sx * (w / 2 - 6), sz * (depth / 2 - 5)
			b.Tube(x, 0, z, x - sx * 2, top - 5, z - sz * 5, 1.8, IRON, M.Metal)
			b.Tube(x, 0, z, x - sx * 8, top - 5, z, 1.8, IRON, M.Metal)
		end
	end
	-- tiroir fin sous le plateau (à droite)
	b.Box(w * 0.2, top - 13, 2, w * 0.36, 8, depth - 8, OAK_DARK, M.Wood)
	b.Box(w * 0.2, top - 10, depth / 2 - 1.5, 10, 1.4, 1, IRON_DARK, M.Metal)
	b.Box(0, top - 5, 0, w, 5, depth, oak, M.Wood)
	b.Top(1, (x0 + x1) / 2, top, 0, w, depth)
	b.Footprint(w, depth, top)
end

R.MediaConsole = function(b, ctx)
	local top = ctx.TopY(1, 40)
	local walnut = b.Map(WALNUT)
	local depth = 38
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Tube(sx * 40, 11, sz * 13, sx * 44, 0, sz * 15, 3, WALNUT_DARK, M.Wood)
		end
	end
	b.Box(0, 10, 0, 96, top - 13, depth, walnut, M.Wood)
	for index = -1, 1 do
		local x = index * 31
		b.Box(x, 12, depth / 2, 29, top - 17, 1, lighten(walnut, 0.08), M.Wood)
		-- cannage (lattes claires)
		for k = 0, 4 do
			b.Box(x, 15 + k * (top - 22) / 5, depth / 2 + 0.6, 24, 1, 0.4, rgb(214, 186, 140), M.Fabric)
		end
		b.Box(x + (index == 0 and 12 or -12), 20, depth / 2 + 1, 1.6, 6, 1, GOLD, M.Metal)
	end
	b.Box(0, top - 3, 0, 98, 3, depth + 2, darken(walnut, 0.2), M.Wood)
	b.Top(1, 0, top, 0, 94, depth)
	b.Footprint(98, depth + 2, top)
end

R.GlassCoffeeTable = function(b, ctx)
	local top = ctx.TopY(1, 38)
	local depth = 56
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * 43, 0, sz * 23, 4, top - 3, 4, STEEL, M.Metal)
		end
		b.Box(sx * 43, 0, 0, 4, 3, depth - 8, STEEL_DARK, M.Metal)
	end
	glass(b.Box(0, top * 0.36, 0, 82, 2, depth - 12, GLASS, M.Glass), 0.4)
	-- livres + bougie sur l'étagère du bas
	b.Box(-18, top * 0.36 + 2, 4, 20, 3, 14, rgb(60, 96, 150), M.SmoothPlastic)
	b.Box(-18, top * 0.36 + 5, 4, 16, 2.4, 12, rgb(236, 226, 206), M.SmoothPlastic)
	b.Cyl(14, top * 0.36 + 2, -6, 8, 8, CERAMIC, M.SmoothPlastic)
	glass(b.Box(0, top - 3, 0, 98, 3, depth, b.Map(rgb(170, 214, 228)), M.Glass), 0.3)
	b.Top(1, 0, top, 0, 94, depth - 4)
	b.Footprint(98, depth, top)
end

R.LoftShelf = function(b, ctx)
	local depth = 30
	local levels = { ctx.TopY(1, 92), ctx.TopY(2, 66), ctx.TopY(3, 40), ctx.TopY(4, 14) }
	local plank = b.Map(rgb(176, 130, 88))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(sx * 42, 0, sz * (depth / 2 - 3), 4.5, levels[1] + 4, IRON_DARK, M.Metal)
		end
	end
	for index, y in ipairs(levels) do
		b.Box(0, y - 4, 0, 92, 4, depth, plank, M.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			b.Box(sx * 42, y - 7, 0, 3, 3, depth - 2, IRON, M.Metal) -- traverse sous la planche
		end
		b.Top(index, 0, y, depth * 0.2, 80, depth * 0.55)
	end
	-- déco au fond des rayons (le devant reste libre)
	books(b, -36, 0, levels[2], -8, 12, 18, 3)
	b.Cyl(22, levels[2], -7, 12, 12, TERRACOTTA, M.SmoothPlastic)
	b.Egg(19, levels[2] + 17, -7, 8, 12, 3, LEAF, M.SmoothPlastic)
	b.Egg(25, levels[2] + 16, -7, 8, 12, 3, LEAF_DARK, M.SmoothPlastic)
	b.Box(-24, levels[3], -7, 22, 13, 14, rgb(120, 118, 114), M.Metal)
	books(b, 2, 36, levels[3], -8, 12, 18, 11)
	b.Box(-20, levels[4], -6, 26, 12, 16, rgb(200, 170, 120), M.Fabric)
	b.Ball(22, levels[4] + 7, -6, 13, rgb(90, 90, 96), M.Metal)
	b.Footprint(94, depth, levels[1])
end

R.PlatformBed = function(b, ctx)
	local top = ctx.TopY(1, 30)
	local depth = 80
	local oak = b.Map(OAK)
	local duvet = b.Map(rgb(124, 140, 150))
	b.Box(2, 0, 0, 84, 3, depth - 10, OAK_DARK, M.Wood) -- socle en retrait
	b.Box(2, 3, 0, 94, 10, depth, oak, M.Wood)
	b.Box(2, 13, 0, 90, top - 13, depth - 4, WHITE, M.Fabric)
	b.Box(12, top - 6, 0, 68, 7, depth - 2, duvet, M.Fabric)
	b.Box(-19, top - 5.6, 0, 8, 7, depth - 1, rgb(210, 214, 216), M.Fabric)
	-- tête de lit capitonnée (à gauche)
	b.Round(-44, 3, 0, 10, 50, depth, 4, b.Map(GREIGE), M.Fabric)
	for k = 0, 2 do
		b.Box(-38.6, 16 + k * 12, 0, 0.8, 1.2, depth - 8, darken(GREIGE, 0.2), M.Fabric)
	end
	for _, z in ipairs({ -depth * 0.24, depth * 0.24 }) do
		b.EggR(CFrame.new(-32, top + 4, z) * CFrame.Angles(0, 0, -0.35), 18, 9, depth * 0.4, WHITE, M.Fabric)
	end
	b.EggR(CFrame.new(-26, top + 3, 0) * CFrame.Angles(0, 0, -0.3), 12, 8, 18, rgb(214, 196, 170), M.Fabric)
	b.Top(1, 6, top + 1, 0, 76, depth - 10)
	b.Footprint(100, depth, 53)
end

R.Workbench = function(b, ctx)
	local top = ctx.TopY(1, 60)
	local depth = 50
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Tube(sx * 36 - 8, 0, sz * 20, sx * 36, top - 6, sz * 18, 4, IRON, M.Metal)
			b.Tube(sx * 36 + 8, 0, sz * 20, sx * 36, top - 6, sz * 18, 4, IRON, M.Metal)
		end
	end
	b.Box(0, 22, 0, 72, 4, 38, IRON_DARK, M.Metal) -- étagère basse
	b.Box(18, 26, 2, 22, 12, 14, RED, M.Metal) -- caisse à outils
	b.Box(18, 38, 2, 10, 3, 3, IRON, M.Metal)
	b.Box(0, top - 7, 0, 98, 7, depth, b.Map(rgb(186, 140, 94)), M.WoodPlanks)
	-- étau à droite
	b.Box(40, top, depth / 2 - 6, 10, 6, 10, rgb(60, 110, 160), M.Metal)
	b.Tube(40, top + 3, depth / 2 - 1, 40, top + 3, depth / 2 + 6, 1.6, STEEL, M.Metal)
	b.Top(1, -4, top, 0, 84, depth)
	b.Footprint(98, depth, top + 6)
end

-- Canapé moderne : base, dossiers, coussins ; `chaise` = méridienne à droite
local function modernSofa(b: Builder, seat: number, fabric: Color3, chaise: boolean)
	local depth = 46
	for _, x in ipairs({ -44, 0, 44 }) do
		for _, z in ipairs({ -18, 18 }) do
			b.Cyl(x, 0, z, 4, 5, WALNUT, M.Wood)
		end
	end
	b.Box(0, 5, 0, 98, seat - 14, depth, darken(fabric, 0.12), M.Fabric)
	for index = -1, 1 do
		b.Cushion(index * 31, seat - 10, 4, 31, 10, depth - 12, lighten(fabric, 0.06), M.Fabric)
		b.BoxR(CFrame.new(index * 31, seat + 12, -depth / 2 + 6) * CFrame.Angles(-0.12, 0, 0), 30, 26, 10, fabric, M.Fabric)
	end
	b.Box(0, 5, -depth / 2 + 3, 98, seat + 14, 6, darken(fabric, 0.08), M.Fabric)
	if chaise then
		-- méridienne : prolonge l'assise vers l'avant, côté droit
		b.Box(32, 5, depth / 2 + 12, 34, seat - 14, 24, darken(fabric, 0.12), M.Fabric)
		b.Cushion(32, seat - 10, depth / 2 + 10, 33, 10, 26, lighten(fabric, 0.06), M.Fabric)
	else
		for _, sx in ipairs({ -1, 1 }) do
			b.Box(sx * 46, 5, 0, 7, seat, depth, fabric, M.Fabric)
		end
	end
	-- coussins déco
	pillow(b, -36, seat - 2, -8, 16, 16, 6, b.Map(rgb(214, 170, 90)), -0.3)
	pillow(b, -20, seat - 2, -9, 14, 14, 6, LINEN, -0.25)
end

R.SectionalSofa = function(b, ctx)
	local seat = ctx.TopY(1, 36)
	modernSofa(b, seat, b.Map(rgb(150, 156, 164)), true)
	b.Top(1, 0, seat, 4, 84, 30)
	b.Footprint(98, 82, seat + 26)
end

R.Chesterfield = function(b, ctx)
	local seat = ctx.TopY(1, 38)
	local leather = b.Map(LEATHER)
	local dark = darken(leather, 0.25)
	local depth = 48
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Ball(sx * 40, 3, sz * 18, 7, WALNUT_DARK, M.Wood)
		end
	end
	b.Box(0, 5, 0, 82, seat - 12, depth, dark, M.Leather)
	b.Cushion(-19, seat - 9, 4, 38, 10, depth - 10, leather, M.Leather)
	b.Cushion(19, seat - 9, 4, 38, 10, depth - 10, leather, M.Leather)
	-- dossier capitonné
	b.Box(0, 5, -depth / 2 + 5, 84, seat + 26, 10, leather, M.Leather)
	for row = 0, 2 do
		for col = 0, 6 do
			b.Ball(-36 + col * 12 + (row % 2) * 6, seat + 4 + row * 8, -depth / 2 + 10.2, 2.4, dark, M.Leather)
		end
	end
	-- accoudoirs roulés
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 44, 5, 0, 12, seat + 8, depth, leather, M.Leather)
		b.CylZ(sx * 44, seat + 12, 1, 16, depth + 2, lighten(leather, 0.06), M.Leather)
		for k = 0, 3 do
			b.Ball(sx * 44, seat - 2 - k * 6, depth / 2 + 0.4, 2, dark, M.Leather)
		end
	end
	b.Top(1, 0, seat, 4, 72, 36)
	b.Footprint(100, depth + 2, seat + 31)
end

R.BookshelfWall = function(b, ctx)
	local depth = 28
	local levels = { ctx.TopY(1, 96), ctx.TopY(2, 72), ctx.TopY(3, 48), ctx.TopY(4, 24) }
	local walnut = b.Map(WALNUT)
	b.Box(0, 0, -depth / 2 + 1.5, 94, levels[1], 3, WALNUT_DARK, M.Wood) -- fond
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 46, 0, 0, 4, levels[1], depth, walnut, M.Wood)
	end
	b.Box(0, 0, 0, 3, levels[1] - 4, depth, walnut, M.Wood) -- montant central
	b.Box(0, levels[1] - 4, 0, 96, 4, depth, walnut, M.Wood)
	b.Box(0, 0, 0, 88, 4, depth, walnut, M.Wood) -- socle
	for index = 2, 4 do
		b.Box(0, levels[index] - 3, 0, 88, 3, depth, walnut, M.Wood)
	end
	-- livres au fond des rayons (le devant reste libre pour poser des objets)
	local z = -5
	books(b, -43, -3, levels[2], z, 14, 19, 1)
	books(b, 3, 43, levels[2], z, 14, 19, 5)
	books(b, -43, -16, levels[3], z, 14, 18, 9)
	b.Ball(-9, levels[3] + 4, z, 8, GOLD, M.Metal)
	books(b, 3, 43, levels[3], z, 14, 18, 2)
	books(b, -43, -3, levels[4], z, 14, 19, 6)
	books(b, 3, 28, levels[4], z, 14, 19, 4)
	b.Cyl(36, levels[4], z, 9, 11, CERAMIC, M.SmoothPlastic)
	books(b, -43, -3, 4, z, 14, 17, 8)
	books(b, 3, 43, 4, z, 14, 17, 12)
	-- échelle de bibliothèque sur son rail doré
	b.CylX(0, levels[1] - 8, depth / 2 + 3, 2, 92, GOLD, M.Metal)
	for _, dx in ipairs({ 0, 12 }) do
		b.Tube(16 + dx, levels[1] - 8, depth / 2 + 3, 22 + dx, 0, depth / 2 + 18, 2.4, rgb(210, 180, 110), M.Wood)
	end
	for k = 1, 6 do
		local t = k / 7
		local y = levels[1] - 8 - t * (levels[1] - 8)
		b.CylX(22 + 6 * t, y, depth / 2 + 3 + 15 * t, 2, 12, rgb(210, 180, 110), M.Wood)
	end
	for index = 1, 4 do
		b.Top(index, 0, levels[index], index == 1 and 0 or depth * 0.25, 84, index == 1 and depth or depth * 0.45)
	end
	b.Footprint(96, depth + 30, levels[1])
end

R.MarbleIsland = function(b, ctx)
	local top = ctx.TopY(1, 60)
	local depth = 56
	local base = b.Map(rgb(66, 84, 96))
	b.Box(0, 0, 0, 92, 3, depth - 8, IRON_DARK, M.Metal) -- plinthe en retrait
	b.Box(0, 3, 0, 92, top - 7, depth - 6, base, M.Wood)
	for index = 0, 3 do
		local x = -34.5 + index * 23
		b.Box(x, 6, (depth - 6) / 2, 21, top - 14, 1, lighten(base, 0.08), M.Wood)
		b.Box(x + 6, top - 16, (depth - 6) / 2 + 0.8, 5, 1.6, 1, GOLD, M.Metal)
	end
	b.Box(0, top - 4, 0, 98, 4, depth, MARBLE, M.Marble)
	-- veines (fines incrustations sur le dessus, 0.06 plus haut)
	b.BoxR(CFrame.new(-18, top + 0.03, 6) * CFrame.Angles(0, 0.4, 0), 30, 0.06, 1, MARBLE_VEIN, M.Marble)
	b.BoxR(CFrame.new(20, top + 0.03, -10) * CFrame.Angles(0, -0.3, 0), 26, 0.06, 1, MARBLE_VEIN, M.Marble)
	-- corbeille de fruits + planche à découper
	b.Box(26, top, -12, 24, 2, 14, OAK, M.Wood)
	b.Cyl(-28, top, -10, 18, 4, CERAMIC, M.SmoothPlastic)
	for index, c in ipairs({ ORANGE, rgb(120, 190, 80), RED }) do
		b.Ball(-32 + index * 4, top + 6, -10 + (index % 2) * 3, 7, c, M.SmoothPlastic)
	end
	b.Top(1, 0, top, 4, 90, depth - 16)
	b.Footprint(98, depth, top)
end

----------------------------------------------------------------------
-- 🖼️ Déco
----------------------------------------------------------------------

R.RoundMirror = function(b, _ctx)
	local brass = b.Map(rgb(212, 176, 96))
	b.Tube(0, 96, 1, 0, 88, 2, 1, brass, M.Metal)
	b.CylZ(0, 46, 2, 86, 4, brass, M.Metal)
	b.CylZ(0, 46, 2.6, 76, 4, rgb(206, 226, 234), M.Glass)
	local shine = b.BoxR(CFrame.new(-14, 58, 4.7) * CFrame.Angles(0, 0, 0.7), 26, 3, 0.2, WHITE, M.Glass)
	glass(shine, 0.55)
	b.Footprint(86, 5, 100)
end

R.AbstractCanvas = function(b, _ctx)
	b.Box(0, 12, 1.5, 84, 76, 3, rgb(60, 56, 60), M.Wood)
	b.Box(0, 13, 2, 80, 72, 3, rgb(246, 242, 234), M.Fabric)
	-- aplats de peinture (0.4 devant la toile)
	b.CylZ(-16, 58, 3.7, 32, 0.4, b.Map(rgb(236, 120, 70)), M.SmoothPlastic)
	b.Box(10, 30, 3.9, 24, 44, 0.4, b.Map(rgb(40, 70, 120)), M.SmoothPlastic)
	b.CylZ(22, 30, 4.3, 22, 0.4, rgb(240, 200, 80), M.SmoothPlastic)
	b.Box(-24, 24, 3.7, 18, 12, 0.4, rgb(230, 170, 170), M.SmoothPlastic)
	b.BoxR(CFrame.new(0, 48, 4.7) * CFrame.Angles(0, 0, 0.55), 70, 2.4, 0.4, rgb(30, 30, 36), M.SmoothPlastic)
	b.Footprint(84, 5, 100)
end

R.GrandfatherClock = function(b, _ctx)
	local walnut = b.Map(WALNUT)
	local depth = 24
	b.Box(0, 0, 0, 48, 14, depth + 2, WALNUT_DARK, M.Wood)
	b.Box(0, 14, 0, 40, 56, depth, walnut, M.Wood)
	-- vitre du balancier
	b.Box(0, 20, depth / 2 - 1, 26, 44, 2, rgb(40, 28, 22), M.Wood)
	glass(b.Box(0, 20, depth / 2 + 0.5, 26, 44, 0.6, GLASS, M.Glass), 0.7)
	b.Tube(0, 60, depth / 2 - 2, 0, 32, depth / 2 - 2, 1.4, rgb(220, 186, 100), M.Metal)
	b.CylZ(0, 30, depth / 2 - 2, 10, 1.2, rgb(240, 200, 100), M.Metal)
	for _, x in ipairs({ -6, 6 }) do
		b.Cyl(x, 40, depth / 2 - 3, 2.4, 22, rgb(200, 170, 100), M.Metal) -- poids
	end
	-- tête + cadran
	b.Box(0, 70, 0, 48, 26, depth + 2, walnut, M.Wood)
	b.Box(0, 96, 0, 52, 4, depth + 4, WALNUT_DARK, M.Wood)
	b.CylZ(0, 82, depth / 2 + 1.6, 22, 1.4, rgb(210, 180, 110), M.Metal)
	b.CylZ(0, 82, depth / 2 + 2.2, 19, 1.4, rgb(250, 244, 226), M.SmoothPlastic)
	b.BoxR(CFrame.new(0, 85, depth / 2 + 3.1) * CFrame.Angles(0, 0, 0), 1, 7, 0.4, rgb(40, 36, 40), M.SmoothPlastic)
	b.BoxR(CFrame.new(2.4, 81, depth / 2 + 3.3) * CFrame.Angles(0, 0, 1.1), 1, 6, 0.4, rgb(40, 36, 40), M.SmoothPlastic)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		b.Box(math.sin(a) * 8, 82 + math.cos(a) * 8 - 0.6, depth / 2 + 3.1, 1.2, 1.2, 0.4, rgb(60, 50, 50), M.SmoothPlastic)
	end
	b.Footprint(52, depth + 4, 100)
end

----------------------------------------------------------------------
-- 💡 Lumières
----------------------------------------------------------------------

R.EdisonPendant = function(b, _ctx)
	-- rail fixé en haut du mur, 3 fils, 3 ampoules à filament
	b.Box(0, 96, 1.5, 60, 4, 3, IRON_DARK, M.Metal)
	b.Box(0, 97, 14, 60, 3, 22, IRON_DARK, M.Metal)
	for index, spec in ipairs({ { -20, 52, 12 }, { 0, 34, 20 }, { 20, 60, 8 } }) do
		local x, y, z = spec[1], spec[2], spec[3]
		b.Tube(x, 97, z, x, y + 12, z, 0.8, IRON_DARK, M.Fabric)
		b.Cyl(x, y + 7, z, 6, 6, rgb(170, 140, 90), M.Metal)
		local bulb = b.Egg(x, y, z, 12, 15, 12, rgb(255, 224, 170), M.Glass)
		glass(bulb, 0.25)
		glow(b, b.Tube(x - 2, y - 3, z, x, y + 4, z, 0.8, ORANGE, M.Neon))
		glow(b, b.Tube(x + 2, y - 3, z, x, y + 4, z, 0.8, ORANGE, M.Neon))
		if index == 2 then
			b.Light(bulb, AMBER, 12, 0.7)
		end
	end
	b.Footprint(62, 26, 100)
end

R.ArcFloorLamp = function(b, _ctx)
	b.Round(-33, 0, 0, 26, 10, 26, 3, MARBLE, M.Marble)
	local steel = b.Map(STEEL)
	House3DKit.Path(b, { { -33, 10, 0 }, { -33, 50, 0 }, { -26, 76, 0 }, { -10, 92, 0 }, { 10, 94, 0 }, { 26, 86, 0 }, { 34, 72, 0 } }, 2.4, steel, M.Metal)
	b.Egg(34, 66, 0, 28, 20, 28, steel, M.Metal)
	local bulb = glow(b, b.Egg(34, 58, 0, 14, 4, 14, rgb(255, 230, 170), M.Neon))
	b.Light(bulb, AMBER, 14, 0.8)
	b.Footprint(96, 30, 96)
end

-- Lettres "DOPA" en néon (chemins de tubes), plaque de plexi derrière
local LETTERS: { { { number } } } = {
	-- D
	{ { -38, 36 }, { -38, 64 }, { -30, 64 }, { -24, 58 }, { -24, 42 }, { -30, 36 }, { -38, 36 } },
	-- O
	{ { -12, 40 }, { -12, 60 }, { -7, 64 }, { -1, 64 }, { 4, 60 }, { 4, 40 }, { -1, 36 }, { -7, 36 }, { -12, 40 } },
	-- P
	{ { 14, 36 }, { 14, 64 }, { 24, 64 }, { 28, 60 }, { 28, 54 }, { 24, 50 }, { 14, 50 } },
	-- A
	{ { 34, 36 }, { 40, 64 }, { 46, 64 }, { 52, 36 } },
	{ { 37, 47 }, { 49, 47 } },
}
R.DopaNeon = function(b, _ctx)
	local plate = b.Round(0, 26, 1.5, 96, 48, 3, 1.2, rgb(40, 36, 60), M.Glass)
	glass(plate, 0.3)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ 30, 70 }) do
			b.CylZ(sx * 42, sy, 3.4, 3, 1, STEEL, M.Metal)
		end
	end
	local pink = b.Map(rgb(255, 120, 220))
	local first = #b.Parts + 1
	for _, letter in ipairs(LETTERS) do
		local points = {}
		for _, p in ipairs(letter) do
			table.insert(points, { p[1], p[2], 4.2 })
		end
		House3DKit.Path(b, points, 2.2, pink, M.Neon, true)
	end
	House3DKit.Path(b, { { -38, 30, 4.2 }, { 50, 30, 4.2 } }, 1.4, CYAN, M.Neon, true)
	for index = first, #b.Parts do
		b.Parts[index].CastShadow = false
		table.insert(b.Glows, b.Parts[index])
	end
	b.Light(b.Parts[first], MAGENTA, 10, 0.5)
	b.Footprint(96, 6, 100)
end

R.InfinityMirror = function(b, _ctx)
	b.CylZ(0, 50, 2.5, 88, 5, IRON_DARK, M.Metal)
	b.CylZ(0, 50, 3.2, 80, 5, rgb(16, 16, 30), M.Glass)
	local colors = { CYAN, rgb(150, 110, 255), MAGENTA, rgb(150, 110, 255), CYAN }
	for ring = 0, 4 do
		local r = 36 - ring * 6.5
		local z = 5.9 - ring * 0.25
		local points = {}
		for k = 0, 12 do
			local a = k / 12 * math.pi * 2
			table.insert(points, { math.cos(a) * r, 50 + math.sin(a) * r, z })
		end
		local first = #b.Parts + 1
		House3DKit.Path(b, points, 1.4 - ring * 0.15, colors[ring + 1], M.Neon, true)
		for index = first, #b.Parts do
			b.Parts[index].CastShadow = false
			table.insert(b.Glows, b.Parts[index])
		end
	end
	glass(b.CylZ(0, 50, 6.5, 80, 0.6, GLASS, M.Glass), 0.8)
	b.Footprint(88, 7, 100)
end

R.PlanetariumDome = function(b, _ctx)
	b.Cyl(0, 0, 0, 46, 8, IRON_DARK, M.Metal)
	b.Cyl(0, 8, 0, 10, 22, IRON, M.Metal)
	b.Cyl(0, 28, 0, 36, 5, IRON_DARK, M.Metal)
	local dome = b.Ball(0, 62, 0, 68, rgb(30, 30, 80), M.Glass)
	dome.Transparency = 0.1
	-- étoiles et planète à la surface du dôme
	for k = 0, 17 do
		local a = k * 2.39996
		local h = 0.15 + (k % 6) / 7
		local r = 34 * math.sqrt(1 - h * h)
		local star = b.Ball(math.cos(a) * r, 62 + h * 34, math.sin(a) * r, k % 3 == 0 and 3.4 or 2.2,
			k % 3 == 0 and rgb(255, 230, 150) or WHITE, M.Neon)
		glow(b, star)
	end
	local ring = glow(b, b.Cyl(0, 32.5, 0, 38, 1.2, rgb(150, 130, 255), M.Neon))
	b.Ball(22, 84, 18, 10, rgb(255, 170, 100), M.SmoothPlastic)
	b.Light(ring, rgb(160, 140, 255), 14, 0.7)
	b.Footprint(70, 70, 96)
end

R.GrandChandelier = function(b, _ctx)
	local gold = b.Map(GOLD)
	b.Box(0, 94, 1.5, 16, 6, 3, gold, M.Metal)
	b.Tube(0, 97, 3, 0, 97, 26, 2, gold, M.Metal)
	b.Tube(0, 97, 26, 0, 82, 26, 1.6, gold, M.Metal)
	b.Ball(0, 80, 26, 8, gold, M.Metal)
	local core = b.Egg(0, 70, 26, 12, 18, 12, rgb(220, 240, 255), M.Glass)
	core.Transparency = 0.1
	for tier = 0, 2 do
		local radius = 14 + tier * 12
		local y = 70 - tier * 12
		local n = 6 + tier * 2
		b.Cyl(0, y - 2, 26, radius * 2 + 4, 2.4, gold, M.Metal)
		for k = 0, n - 1 do
			local a = k / n * math.pi * 2 + tier * 0.3
			local x, z = math.cos(a) * radius, 26 + math.sin(a) * radius * 0.7
			b.Cyl(x, y + 0.4, z, 3, 7, rgb(250, 244, 230), M.SmoothPlastic)
			glow(b, b.Ball(x, y + 9, z, 3, rgb(255, 214, 140), M.Neon))
			for drop = 1, 2 do
				glass(b.Egg(x, y - 3 - drop * 6, z, 3.4, 6, 3.4, rgb(230, 245, 255), M.Glass), 0.2)
			end
		end
	end
	glass(b.Egg(0, 30, 26, 8, 14, 8, rgb(230, 245, 255), M.Glass), 0.1)
	b.Light(core, rgb(255, 236, 200), 18, 0.9)
	b.Footprint(80, 60, 100)
end

----------------------------------------------------------------------
-- 🪴 Plantes
----------------------------------------------------------------------

R.SnakePlant = function(b, _ctx)
	local soil = pot(b, 0, 0, 40, 30, CONCRETE, M.Concrete)
	local specs = { { -10, 0.14, 60, 0.5 }, { -3, 0.05, 72, 1.8 }, { 5, -0.08, 66, 3.1 }, { 12, -0.18, 54, 4.3 }, { 0, 0.02, 50, 5.4 }, { -6, -0.1, 58, 0.9 } }
	for index, s in ipairs(specs) do
		local h = s[3]
		local cf = CFrame.new(s[1], soil, (index % 3 - 1) * 5) * CFrame.Angles(0, s[4], 0) * CFrame.Angles(0, 0, s[2]) * CFrame.new(0, h / 2, 0)
		local color = index % 2 == 0 and LEAF_DARK or LEAF
		b.BoxR(cf, 7, h, 1.6, color, M.SmoothPlastic)
		b.BoxR(cf * CFrame.new(0, 0, 0), 8, h - 4, 1.2, rgb(210, 200, 90), M.SmoothPlastic)
		b.BoxR(cf * CFrame.new(0, h / 2, 0), 4, 5, 1.6, color, M.SmoothPlastic)
	end
	b.Footprint(40, 40, 100)
end

R.FiddleFig = function(b, _ctx)
	local soil = pot(b, 0, 0, 34, 24, CERAMIC, M.SmoothPlastic)
	local bark = rgb(120, 90, 60)
	b.Tube(0, soil, 0, -2, 70, 0, 3, bark, M.Wood)
	b.Tube(-1, 50, 0, -12, 64, 4, 2, bark, M.Wood)
	b.Tube(-1, 56, 0, 12, 76, -3, 2, bark, M.Wood)
	local spots = { { -14, 66, 4, 0.2, 0.5 }, { -20, 50, 2, 1.2, 0.9 }, { 12, 76, -4, 2.8, -0.4 }, { 18, 58, 3, 3.6, -0.9 }, { -2, 86, 0, 0.1, 0 },
		{ -8, 80, 6, 5.1, 0.3 }, { 8, 90, 2, 4.4, -0.2 }, { 8, 48, 8, 2.2, -0.6 }, { -12, 40, -6, 0.7, 0.7 } }
	for index, s in ipairs(spots) do
		local color = index % 3 == 0 and LEAF_LIGHT or (index % 2 == 0 and LEAF_DARK or LEAF)
		leafAt(b, s[1], s[2], s[3], 16, 20, color, s[4], s[5])
	end
	b.Footprint(56, 44, 100)
end

R.BirdOfParadise = function(b, _ctx)
	local soil = pot(b, 0, 0, 38, 22, rgb(60, 60, 64), M.SmoothPlastic)
	local specs = { { -24, 0.5, 70 }, { -8, 0.2, 86 }, { 8, -0.2, 82 }, { 22, -0.5, 68 }, { 0, 0.05, 94 }, { -14, 0.4, 60 } }
	for index, s in ipairs(specs) do
		local top = s[3]
		local x = s[1]
		local z = (index % 3 - 1) * 6
		b.Tube(0, soil, z * 0.3, x * 0.5, top - 26, z, 1.8, LEAF_DARK, M.SmoothPlastic)
		b.EggR(CFrame.new(x * 0.8, top - 12, z) * CFrame.Angles(0, index * 0.9, s[2]), 13, 32, 1.6, index % 2 == 0 and LEAF or LEAF_DARK, M.SmoothPlastic)
	end
	-- 2 fleurs "bec d'oiseau" (orange + bleu)
	for index, spec in ipairs({ { -16, 62, 6, 1 }, { 16, 58, -4, -1 } }) do
		local x, y, z, dir = spec[1], spec[2], spec[3], spec[4]
		b.Tube(x * 0.2, soil, 0, x, y, z, 1.4, rgb(60, 110, 90), M.SmoothPlastic)
		b.EggR(CFrame.new(x + dir * 5, y, z) * CFrame.Angles(0, 0, dir * 0.2), 14, 3, 3, rgb(60, 110, 90), M.SmoothPlastic)
		for k = 0, 2 do
			b.Wedge(x + dir * (2 + k * 3), y + 1.5, z, 3, 10 - k * 2, 2, k == 1 and rgb(80, 110, 220) or ORANGE, dir > 0 and "Right" or "Left", M.SmoothPlastic)
		end
		local _ = index
	end
	b.Footprint(60, 44, 100)
end

R.MapleBonsai = function(b, _ctx)
	local tray = b.Map(rgb(70, 90, 110))
	b.Round(0, 0, 0, 72, 10, 40, 5, tray, M.SmoothPlastic)
	b.Round(0, 10, 0, 76, 3, 44, 6, lighten(tray, 0.12), M.SmoothPlastic)
	b.Box(0, 12.2, 0, 64, 1.4, 34, rgb(110, 90, 70), M.Ground)
	b.Ball(20, 14, 6, 8, rgb(110, 150, 90), M.Grass) -- mousse
	local bark = rgb(110, 76, 56)
	b.Tube(4, 13, 0, -8, 36, 0, 6, bark, M.Wood)
	b.Tube(-8, 36, 0, 6, 54, 2, 5, bark, M.Wood)
	b.Tube(6, 54, 2, -4, 70, 0, 4, bark, M.Wood)
	b.Tube(-6, 40, 0, -26, 48, 4, 3, bark, M.Wood)
	b.Tube(4, 52, 2, 24, 60, -2, 3, bark, M.Wood)
	local reds = { rgb(214, 60, 50), rgb(236, 96, 60), rgb(180, 40, 44), rgb(246, 130, 80) }
	for index, s in ipairs({ { -26, 52, 4, 24 }, { 24, 64, -2, 26 }, { -4, 76, 0, 28 }, { 10, 70, 6, 22 }, { -14, 64, -4, 20 }, { 2, 86, 2, 18 } }) do
		b.Egg(s[1], s[2], s[3], s[4], s[4] * 0.62, s[4] * 0.8, reds[(index % #reds) + 1], M.SmoothPlastic)
	end
	b.Footprint(76, 44, 95)
end

R.OliveTree = function(b, _ctx)
	local soil = pot(b, 0, 0, 44, 26, TERRACOTTA, M.SmoothPlastic)
	local bark = rgb(128, 110, 90)
	b.Tube(0, soil, 0, -4, 56, 0, 7, bark, M.Wood)
	b.Tube(-4, 50, 0, -18, 70, 4, 4, bark, M.Wood)
	b.Tube(-3, 54, 0, 14, 74, -4, 4, bark, M.Wood)
	local olive = rgb(134, 158, 110)
	local silver = rgb(164, 184, 140)
	for index, s in ipairs({ { -20, 74, 4, 30 }, { 16, 78, -4, 32 }, { -2, 88, 0, 34 }, { -10, 64, -8, 24 }, { 12, 64, 8, 22 }, { -28, 62, 0, 18 }, { 28, 66, 0, 18 } }) do
		b.Egg(s[1], s[2], s[3], s[4], s[4] * 0.6, s[4] * 0.8, index % 2 == 0 and olive or silver, M.SmoothPlastic)
		if index % 2 == 1 then
			b.Ball(s[1] + s[4] * 0.3, s[2] - s[4] * 0.22, s[3] + s[4] * 0.3, 3, rgb(80, 64, 96), M.SmoothPlastic)
		end
	end
	b.Footprint(62, 50, 100)
end

R.MossWall = function(b, _ctx)
	local frame = b.Map(OAK_DARK)
	b.Box(0, 14, 1.5, 92, 72, 3, frame, M.Wood)
	b.Box(0, 18, 3.2, 84, 64, 1, rgb(60, 90, 50), M.Grass)
	local greens = { rgb(90, 150, 70), rgb(60, 120, 60), rgb(130, 180, 90), rgb(76, 136, 80) }
	local n = 0
	for row = 0, 3 do
		for col = 0, 5 do
			n += 1
			local x = -35 + col * 14 + (row % 2) * 5
			local y = 24 + row * 15 + (n % 3)
			b.Egg(x, y, 4.2, 16 + (n * 7) % 6, 14 + (n * 5) % 5, 3 + (n % 3), greens[(n % #greens) + 1], M.Grass)
		end
	end
	-- fougères qui dépassent
	for index, s in ipairs({ { -24, 64, 0.5 }, { 22, 40, -0.6 }, { 0, 30, 0.2 }, { 30, 72, -0.3 } }) do
		b.EggR(CFrame.new(s[1], s[2], 7) * CFrame.Angles(0.5, 0, s[3]), 8, 20, 1.4, LEAF_LIGHT, M.SmoothPlastic)
		local _ = index
	end
	b.Footprint(92, 9, 100)
end

----------------------------------------------------------------------
-- 📺 Tech
----------------------------------------------------------------------

R.SmartSpeaker = function(b, _ctx)
	local fabric = b.Map(rgb(96, 100, 112))
	b.Cyl(0, 0, 0, 44, 58, fabric, M.Fabric)
	b.Cyl(0, 58, 0, 44, 6, rgb(40, 42, 52), M.SmoothPlastic)
	local ring = glow(b, b.Cyl(0, 63.8, 0, 32, 0.8, CYAN, M.Neon))
	b.Cyl(0, 64, 0, 26, 0.8, rgb(40, 42, 52), M.SmoothPlastic)
	for _, x in ipairs({ -6, 6 }) do
		b.Cyl(x, 64.4, 0, 3, 0.6, rgb(90, 92, 104), M.SmoothPlastic)
	end
	b.Light(ring, CYAN, 6, 0.4)
	b.Footprint(44, 44, 65)
end

R.CameraDrone = function(b, _ctx)
	local body = b.Map(rgb(236, 238, 242))
	b.Round(0, 30, 0, 32, 14, 32, 8, body, M.SmoothPlastic)
	b.Egg(0, 44, 0, 20, 8, 18, darken(body, 0.05), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = sx * 30, sz * 24
			b.Tube(sx * 12, 38, sz * 10, x, 42, z, 4, IRON, M.SmoothPlastic)
			b.Cyl(x, 40, z, 7, 5, IRON_DARK, M.Metal)
			b.Cyl(x, 45, z, 28, 0.6, rgb(60, 60, 70), M.SmoothPlastic)
			b.Tube(sx * 10, 30, sz * 10, sx * 14, 2, sz * 12, 2, IRON, M.SmoothPlastic)
		end
	end
	b.Ball(0, 24, 10, 14, IRON_DARK, M.Metal)
	b.CylZ(0, 24, 16.5, 8, 1, rgb(60, 100, 160), M.Glass)
	glow(b, b.Ball(-10, 38, 16, 2.4, RED, M.Neon))
	b.Footprint(86, 70, 46)
end

R.Printer3D = function(b, _ctx)
	local depth = 50
	b.Box(0, 0, 0, 80, 14, depth, IRON_DARK, M.Metal)
	glow(b, b.Box(-24, 3, depth / 2, 20, 7, 0.6, rgb(60, 140, 200), M.Neon))
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 36, 14, -depth / 2 + 4, 4, 74, 4, IRON, M.Metal)
	end
	b.Box(0, 88, -depth / 2 + 4, 76, 6, 4, IRON, M.Metal)
	b.Box(0, 14, 0, 60, 4, 40, rgb(40, 40, 46), M.Metal) -- plateau
	-- objet imprimé : vase orange en couches
	for k = 0, 5 do
		local w = 18 - math.abs(k - 3) * 2
		b.Cyl(0, 18 + k * 4, 0, w, 4, k % 2 == 0 and ORANGE or rgb(236, 130, 50), M.SmoothPlastic)
	end
	b.CylX(0, 60, -depth / 2 + 8, 3, 70, STEEL, M.Metal)
	b.Box(0, 56, -depth / 2 + 12, 20, 12, 12, rgb(220, 60, 60), M.SmoothPlastic)
	b.Wedge(0, 50, -depth / 2 + 12, 5, 6, 5, IRON_DARK, "Front", M.Metal)
	-- bobine de filament à l'arrière
	b.CylZ(40, 70, -depth / 2 - 2, 20, 8, ORANGE, M.SmoothPlastic)
	b.CylZ(40, 70, -depth / 2 - 2, 7, 9, IRON_DARK, M.Metal)
	b.Footprint(90, depth + 10, 94)
end

R.ButlerRobot = function(b, _ctx)
	local shell = b.Map(rgb(240, 242, 246))
	b.Egg(0, 12, 0, 40, 22, 36, shell, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		b.CylX(sx * 14, 5, 6, 10, 5, IRON_DARK, M.Rubber)
	end
	b.Round(0, 20, 0, 34, 42, 26, 12, shell, M.SmoothPlastic)
	glow(b, b.CylZ(0, 46, 13.4, 10, 1, CYAN, M.Neon))
	-- nœud papillon
	b.Wedge(-3, 55, 13.2, 6, 5, 1.2, rgb(92, 104, 122), "Right", M.SmoothPlastic)
	b.Wedge(3, 55, 13.2, 6, 5, 1.2, rgb(92, 104, 122), "Left", M.SmoothPlastic)
	-- bras : un au repos, un qui tient le plateau
	b.Tube(-17, 56, 0, -24, 36, 4, 5, STEEL, M.Metal)
	b.Ball(-24, 35, 4, 6, STEEL_DARK, M.Metal)
	b.Tube(17, 56, 0, 30, 58, 10, 5, STEEL, M.Metal)
	b.Cyl(34, 58, 12, 24, 2, STEEL_DARK, M.Metal)
	b.Cyl(34, 60, 12, 8, 7, WHITE, M.SmoothPlastic)
	b.Cyl(34, 66.4, 12, 6, 0.6, rgb(110, 70, 40), M.SmoothPlastic)
	-- cou + tête écran
	b.Cyl(0, 62, 0, 8, 6, STEEL, M.Metal)
	b.Round(0, 68, 0, 36, 24, 26, 10, shell, M.SmoothPlastic)
	b.Round(0, 72, 11, 26, 14, 4, 5, SCREEN, M.SmoothPlastic)
	for _, x in ipairs({ -5, 5 }) do
		glow(b, b.CylZ(x, 79, 13.4, 5, 1, CYAN, M.Neon))
	end
	b.Tube(0, 92, 0, 0, 98, 0, 1.2, STEEL, M.Metal)
	glow(b, b.Ball(0, 98, 0, 4, RED, M.Neon))
	b.Footprint(70, 40, 100)
end

----------------------------------------------------------------------
-- 🍰 Cuisine
----------------------------------------------------------------------

R.StandMixer = function(b, _ctx)
	local cream = b.Map(rgb(236, 210, 170))
	b.Round(0, 0, 0, 64, 12, 40, 10, cream, M.SmoothPlastic)
	b.Round(24, 12, -4, 20, 52, 26, 8, cream, M.SmoothPlastic)
	b.Round(0, 52, -4, 66, 24, 26, 11, cream, M.SmoothPlastic)
	b.Box(0, 58, 9.6, 60, 1.6, 1, darken(cream, 0.12), M.SmoothPlastic)
	b.CylZ(24, 66, 9.6, 6, 1.4, STEEL, M.Metal)
	b.Tube(-12, 52, -4, -12, 34, -4, 3, STEEL_DARK, M.Metal)
	b.Egg(-12, 32, -4, 10, 14, 10, STEEL, M.Metal)
	b.Cyl(-12, 12, -4, 40, 26, STEEL, M.Metal)
	b.Cyl(-12, 37, -4, 36, 1.4, rgb(250, 244, 230), M.SmoothPlastic)
	b.Footprint(68, 42, 76)
end

R.EspressoMachine = function(b, _ctx)
	local depth = 42
	local steel = b.Map(STEEL)
	b.Box(0, 0, 0, 72, 76, depth, steel, M.Metal)
	b.Box(0, 76, 0, 76, 4, depth + 2, IRON, M.Metal)
	for _, x in ipairs({ -18, -2 }) do
		b.Cyl(x, 80, -4, 11, 8, WHITE, M.SmoothPlastic)
	end
	-- manomètre
	b.CylZ(18, 58, depth / 2 + 0.8, 16, 1.6, IRON, M.Metal)
	b.CylZ(18, 58, depth / 2 + 1.4, 13, 1.6, rgb(250, 248, 240), M.SmoothPlastic)
	b.BoxR(CFrame.new(19, 59.5, depth / 2 + 2.4) * CFrame.Angles(0, 0, -0.6), 1, 6, 0.4, RED, M.SmoothPlastic)
	-- groupe + porte-filtre + tasse
	b.Box(-8, 50, depth / 2 + 4, 24, 10, 10, IRON, M.Metal)
	b.Cyl(-8, 45, depth / 2 + 6, 14, 5, STEEL_DARK, M.Metal)
	b.Tube(-8, 47, depth / 2 + 6, -30, 45, depth / 2 + 16, 3.4, IRON_DARK, M.SmoothPlastic)
	b.Box(0, 10, depth / 2 + 6, 60, 4, 14, IRON_DARK, M.DiamondPlate) -- grille égouttoir
	b.Cyl(-8, 14, depth / 2 + 6, 14, 12, WHITE, M.SmoothPlastic)
	b.Cyl(-8, 25.6, depth / 2 + 6, 11, 0.6, rgb(110, 70, 40), M.SmoothPlastic)
	b.Tube(-8, 44, depth / 2 + 6, -8, 27, depth / 2 + 6, 1, rgb(110, 70, 40), M.SmoothPlastic)
	-- buse vapeur
	b.Tube(26, 50, depth / 2 + 2, 28, 30, depth / 2 + 8, 1.6, STEEL, M.Metal)
	b.Footprint(76, depth + 20, 88)
end

R.SteelFridge = function(b, ctx)
	local top = ctx.TopY(1, 97)
	local depth = 56
	local steel = b.Map(STEEL)
	b.Box(0, 0, 0, 84, 6, depth - 4, IRON, M.Metal)
	b.Box(0, 6, 0, 84, top - 6, depth, steel, M.Metal)
	b.Box(0, 8, depth / 2 + 0.5, 1.2, top - 10, 1, STEEL_DARK, M.Metal) -- jointure des portes
	for _, x in ipairs({ -4, 4 }) do
		b.Box(x, 44, depth / 2 + 3, 2.4, 36, 2.4, rgb(220, 224, 232), M.Metal)
		for _, y in ipairs({ 46, 78 }) do
			b.Box(x, y, depth / 2 + 1.6, 2.4, 1.4, 3, STEEL_DARK, M.Metal)
		end
	end
	-- distributeur d'eau + écran
	b.Box(-24, 52, depth / 2 + 0.6, 18, 26, 1.2, IRON_DARK, M.Metal)
	b.Box(-24, 55, depth / 2 + 1.4, 10, 10, 1.6, rgb(50, 60, 80), M.Metal)
	glow(b, b.Box(-24, 72, depth / 2 + 1.3, 12, 4, 0.4, CYAN, M.Neon))
	-- dessin d'enfant aimanté
	b.BoxR(CFrame.new(20, 76, depth / 2 + 0.7) * CFrame.Angles(0, 0, 0.08), 18, 14, 0.4, WHITE, M.SmoothPlastic)
	b.CylZ(20, 83, depth / 2 + 1.1, 3.4, 0.8, RED, M.SmoothPlastic)
	b.Top(1, 0, top, 0, 80, depth - 6)
	b.Footprint(84, depth + 4, top)
end

----------------------------------------------------------------------
-- 🎮 Gamer
----------------------------------------------------------------------

R.HexPanels = function(b, _ctx)
	local colors = { CYAN, rgb(150, 110, 255), MAGENTA, LIME, rgb(255, 180, 60), CYAN, MAGENTA }
	local spots = { { -20, 70 }, { 0, 80 }, { 20, 70 }, { -10, 50 }, { 10, 50 }, { 0, 30 }, { 30, 40 } }
	local function hexagon(x: number, y: number, z: number, side: number, depth: number, color: Color3, material: Enum.Material): { BasePart }
		local parts = {}
		for k = 0, 2 do
			table.insert(parts, b.BoxR(CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(30 + k * 60)), side, side * 1.732, depth, color, material))
		end
		return parts
	end
	for index, s in ipairs(spots) do
		local color = colors[index]
		for _, p in ipairs(hexagon(s[1], s[2], 1.5, 11.5, 2, color, M.Neon)) do
			glow(b, p)
		end
		hexagon(s[1], s[2], 2, 9.4, 2.4, rgb(26, 28, 44), M.SmoothPlastic)
		hexagon(s[1], s[2], 2.4, 4.6, 2.4, lighten(color, 0.4), M.Glass)
	end
	b.Light(b.Parts[1], rgb(150, 110, 255), 10, 0.5)
	b.Footprint(84, 4, 100)
end

R.FoosballTable = function(b, _ctx)
	local depth = 56
	local wood = b.Map(WALNUT)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * 40, 0, sz * 22, 7, 44, 7, WALNUT_DARK, M.Wood)
			b.Cyl(sx * 40, 0, sz * 22, 11, 3, IRON, M.Metal)
		end
	end
	b.Box(0, 44, 0, 92, 22, depth, wood, M.Wood)
	b.Box(0, 60, 0, 84, 1, depth - 8, rgb(40, 140, 90), M.Fabric)
	b.Box(0, 61, 0, 1.2, 0.2, depth - 8, WHITE, M.SmoothPlastic)
	-- 6 barres (avant-arrière) avec leurs joueurs et leurs poignées
	for index = 0, 5 do
		local x = -35 + index * 14
		local color = index % 2 == 0 and RED or BLUE
		b.CylZ(x, 68, 0, 2.2, depth + 24, STEEL, M.Metal)
		b.CylZ(x, 68, (index % 2 == 0 and 1 or -1) * (depth / 2 + 16), 4, 10, rgb(30, 30, 36), M.Rubber)
		for k = -1, 1 do
			local z = k * 14
			b.Box(x, 61.5, z, 4, 10, 3, color, M.SmoothPlastic)
			b.Ball(x, 73, z, 4.4, rgb(240, 210, 180), M.SmoothPlastic)
		end
	end
	b.Ball(3, 62.5, 4, 3, WHITE, M.SmoothPlastic)
	b.Footprint(92, depth + 44, 76)
end

R.AirHockey = function(b, _ctx)
	local depth = 56
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 38, 0, 0, 10, 40, depth - 10, IRON_DARK, M.Metal)
	end
	b.Box(0, 12, 0, 70, 4, depth - 16, IRON, M.Metal)
	b.Box(0, 40, 0, 96, 16, depth, b.Map(rgb(36, 40, 70)), M.SmoothPlastic)
	glow(b, b.Box(0, 44, depth / 2 + 0.3, 90, 2, 0.6, MAGENTA, M.Neon))
	b.Box(0, 56, 0, 88, 1, depth - 8, rgb(230, 240, 250), M.SmoothPlastic)
	b.Box(0, 57, 0, 1.2, 0.2, depth - 8, RED, M.SmoothPlastic)
	-- bandes de rebond
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(0, 56, sz * (depth / 2 - 2), 94, 4, 4, CYAN, M.SmoothPlastic)
	end
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 46, 56, 0, 4, 4, depth, CYAN, M.SmoothPlastic)
	end
	b.Cyl(-26, 57, 0, 12, 3, RED, M.SmoothPlastic)
	b.Cyl(-26, 60, 0, 5, 6, RED, M.SmoothPlastic)
	b.Cyl(26, 57, 4, 12, 3, BLUE, M.SmoothPlastic)
	b.Cyl(26, 60, 4, 5, 6, BLUE, M.SmoothPlastic)
	b.Cyl(4, 57, -6, 8, 1.2, IRON_DARK, M.SmoothPlastic)
	-- tableau des scores à l'arrière
	b.Box(0, 60, -depth / 2 + 2, 3, 26, 3, IRON, M.Metal)
	b.Box(0, 80, -depth / 2 + 2, 40, 14, 4, IRON_DARK, M.Metal)
	glow(b, b.Box(-8, 83, -depth / 2 + 4.2, 8, 8, 0.4, LIME, M.Neon))
	glow(b, b.Box(8, 83, -depth / 2 + 4.2, 8, 8, 0.4, LIME, M.Neon))
	b.Footprint(96, depth, 94)
end

R.ClawMachine = function(b, _ctx)
	local depth = 56
	local pink = b.Map(rgb(236, 72, 140))
	b.Box(0, 0, 0, 64, 36, depth, pink, M.SmoothPlastic)
	b.Wedge(0, 36, depth / 2 - 6, 64, 6, 12, pink, "Front", M.SmoothPlastic)
	b.Box(-12, 30, depth / 2 + 0.4, 30, 6, 1, IRON_DARK, M.SmoothPlastic)
	b.Cyl(-20, 36, depth / 2 - 5, 6, 3, RED, M.SmoothPlastic)
	b.Tube(-6, 36, depth / 2 - 5, -6, 44, depth / 2 - 5, 2, IRON, M.Metal)
	b.Ball(-6, 45, depth / 2 - 5, 6, RED, M.SmoothPlastic)
	b.Box(18, 8, depth / 2 + 0.4, 14, 16, 1, IRON_DARK, M.SmoothPlastic)
	-- vitrine (4 vitres + montants) remplie de peluches
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * 30, 42, sz * (depth / 2 - 2), 4, 42, 4, pink, M.SmoothPlastic)
		end
	end
	glass(b.Box(0, 42, depth / 2 - 2, 56, 42, 0.6, GLASS, M.Glass), 0.7)
	glass(b.Box(0, 42, -depth / 2 + 2, 56, 42, 0.6, GLASS, M.Glass), 0.7)
	for _, sx in ipairs({ -1, 1 }) do
		glass(b.Box(sx * 30, 42, 0, 0.6, 42, depth - 8, GLASS, M.Glass), 0.7)
	end
	local plush = { rgb(255, 200, 80), rgb(140, 200, 255), rgb(255, 150, 190), rgb(150, 220, 150), rgb(200, 160, 255), rgb(255, 170, 120) }
	for index = 0, 8 do
		local x = -18 + (index % 3) * 18
		local z = -14 + math.floor(index / 3) * 14
		local c = plush[(index % #plush) + 1]
		b.Ball(x, 48 + (index % 2) * 4, z, 13, c, M.Fabric)
		b.Ball(x - 3, 55 + (index % 2) * 4, z + 3, 3.4, c, M.Fabric)
		b.Ball(x + 3, 55 + (index % 2) * 4, z + 3, 3.4, c, M.Fabric)
	end
	-- pince
	b.Box(0, 84, 0, 64, 4, depth, IRON_DARK, M.SmoothPlastic)
	b.Tube(6, 84, 2, 6, 70, 2, 1, STEEL, M.Metal)
	b.Cyl(6, 66, 2, 8, 4, STEEL_DARK, M.Metal)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		b.Tube(6 + math.cos(a) * 3, 66, 2 + math.sin(a) * 3, 6 + math.cos(a) * 6, 60, 2 + math.sin(a) * 6, 1.4, STEEL, M.Metal)
	end
	-- fronton lumineux
	b.Round(0, 88, 2, 68, 12, depth - 4, 5, rgb(255, 214, 90), M.SmoothPlastic)
	glow(b, b.Box(0, 91, depth / 2 + 0.4, 40, 6, 0.6, rgb(255, 120, 190), M.Neon))
	b.Footprint(68, depth, 100)
end

R.TwinArcade = function(b, _ctx)
	local depth = 40
	for index, spec in ipairs({ { -24, rgb(120, 60, 200), CYAN }, { 24, rgb(220, 50, 120), LIME } }) do
		local x, color, neon = spec[1], b.Map(spec[2]), spec[3]
		b.Box(x, 0, -2, 44, 88, depth - 4, color, M.SmoothPlastic)
		-- fronton néon
		b.Box(x, 88, -2, 44, 12, depth - 4, darken(color, 0.25), M.SmoothPlastic)
		glow(b, b.Box(x, 90, depth / 2 - 3.6, 36, 8, 0.6, neon, M.Neon))
		-- écran incliné
		b.BoxR(CFrame.new(x, 68, depth / 2 - 6) * CFrame.Angles(-0.2, 0, 0), 38, 28, 2, rgb(20, 20, 30), M.SmoothPlastic)
		glow(b, b.BoxR(CFrame.new(x, 68, depth / 2 - 4.7) * CFrame.Angles(-0.2, 0, 0), 32, 22, 0.6, index == 1 and rgb(60, 90, 200) or rgb(200, 60, 140), M.Neon))
		-- panneau de commande
		b.Wedge(x, 44, depth / 2 + 3, 44, 8, 14, rgb(30, 30, 46), "Front", M.SmoothPlastic)
		b.Box(x, 38, depth / 2 + 3, 44, 6, 14, rgb(30, 30, 46), M.SmoothPlastic)
		b.Tube(x - 10, 46, depth / 2 + 2, x - 10, 52, depth / 2 + 2, 1.6, IRON, M.Metal)
		b.Ball(x - 10, 52, depth / 2 + 2, 4.6, RED, M.SmoothPlastic)
		for k = 0, 2 do
			b.Cyl(x + 4 + k * 6, 47.8 - k * 0.3, depth / 2 + 4, 4, 1.4, ({ RED, rgb(255, 214, 90), neon })[k + 1], M.SmoothPlastic)
		end
		b.Box(x, 16, depth / 2 - 3.6, 14, 10, 0.8, rgb(30, 30, 46), M.SmoothPlastic) -- fente à pièces
		glow(b, b.Box(x, 2, depth / 2 - 3.6, 40, 1.4, 0.6, neon, M.Neon))
	end
	b.Footprint(96, depth + 10, 100)
end

R.VRStation = function(b, _ctx)
	b.Cyl(0, 0, 0, 94, 1.4, rgb(40, 44, 70), M.Fabric)
	-- anneau lumineux fin (tubes) : pas de grand disque Neon
	local ring = {}
	for k = 0, 16 do
		local a = k / 16 * math.pi * 2
		table.insert(ring, { math.cos(a) * 36, 1.8, math.sin(a) * 36 })
	end
	local first = #b.Parts + 1
	House3DKit.Path(b, ring, 1.2, CYAN, M.Neon, true)
	for index = first, #b.Parts do
		glow(b, b.Parts[index])
	end
	for _, sx in ipairs({ -1, 1 }) do
		local x, z = sx * 42, -26
		b.Cyl(x, 0, z, 10, 2, IRON_DARK, M.Metal)
		b.Cyl(x, 2, z, 3, 74, IRON, M.Metal)
		b.Box(x, 76, z, 8, 7, 7, IRON_DARK, M.SmoothPlastic)
		glow(b, b.CylZ(x, 79.5, z + 3.6, 3, 0.6, RED, M.Neon))
	end
	-- socle + casque + manettes
	b.Round(0, 0, 0, 16, 40, 16, 6, rgb(236, 238, 244), M.SmoothPlastic)
	b.Round(0, 40, 0, 34, 16, 22, 8, rgb(240, 242, 248), M.SmoothPlastic)
	b.Round(0, 43, 9, 26, 10, 5, 4, rgb(30, 34, 50), M.SmoothPlastic)
	b.CylX(0, 50, -6, 3, 40, rgb(60, 60, 70), M.Fabric) -- sangle
	for _, sx in ipairs({ -1, 1 }) do
		b.Tube(sx * 22, 20, 10, sx * 22, 36, 12, 5, rgb(236, 238, 244), M.SmoothPlastic)
		b.CylZ(sx * 22, 38, 12, 9, 3, rgb(60, 60, 70), M.SmoothPlastic)
	end
	b.Footprint(94, 94, 84)
end

R.RacingCockpit = function(b, _ctx)
	-- châssis tubulaire
	b.Box(0, 0, 0, 92, 4, 40, IRON_DARK, M.Metal)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(0, 4, sz * 16, 90, 3, 3, IRON, M.Metal)
	end
	-- 3 écrans incurvés sur leur support
	b.Box(-10, 4, -16, 4, 50, 4, IRON, M.Metal)
	for index, spec in ipairs({ { -38, 0.5 }, { -10, 0 }, { 18, -0.5 } }) do
		local cf = CFrame.new(spec[1], 66, -16 + math.abs(spec[2]) * 12) * CFrame.Angles(0, spec[2], 0)
		b.BoxR(cf, 28, 18, 2, rgb(20, 20, 26), M.SmoothPlastic)
		glow(b, b.BoxR(cf * CFrame.new(0, 0, 1.3), 26, 16, 0.6, index == 2 and rgb(90, 160, 240) or rgb(70, 130, 210), M.Neon))
	end
	b.BoxR(CFrame.new(-10, 56, -16) * CFrame.Angles(0, 0, 0), 64, 3, 3, IRON, M.Metal)
	-- colonne du volant + volant
	b.Tube(-18, 4, 0, -18, 38, 2, 4, IRON, M.Metal)
	b.Tube(-18, 38, 2, -6, 42, 2, 3, IRON, M.Metal)
	b.CylX(-4, 44, 2, 16, 2, rgb(30, 30, 36), M.Rubber)
	b.CylX(-3, 44, 2, 5, 2, RED, M.SmoothPlastic)
	-- pédalier
	b.Wedge(-34, 4, 0, 10, 8, 20, IRON_DARK, "Left", M.Metal)
	for k = 0, 2 do
		b.BoxR(CFrame.new(-30, 10, -6 + k * 6) * CFrame.Angles(0, 0, 0.6), 1, 8, 4, STEEL, M.Metal)
	end
	-- siège baquet
	local red = b.Map(RED)
	b.Round(26, 4, 0, 26, 12, 34, 6, IRON, M.Metal)
	b.Round(24, 16, 0, 30, 8, 36, 8, red, M.Leather)
	b.BoxR(CFrame.new(40, 40, 0) * CFrame.Angles(0, 0, 0.25), 8, 44, 36, red, M.Leather)
	b.BoxR(CFrame.new(38, 40, 0) * CFrame.Angles(0, 0, 0.25), 2, 32, 20, rgb(30, 30, 36), M.Leather)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(26, 20, sz * 17, 26, 10, 4, red, M.Leather)
	end
	b.Seat(24, 24, 0, 24, 28)
	b.Footprint(94, 44, 76)
end

----------------------------------------------------------------------
-- 🏀 Sport
----------------------------------------------------------------------

R.YogaMat = function(b, _ctx)
	local mat = b.Map(rgb(120, 180, 170))
	b.Box(-12, 0, 6, 64, 1.2, 30, mat, M.Rubber)
	b.CylZ(24, 7, 6, 14, 30, mat, M.Rubber)
	b.CylZ(24, 7, 6, 6, 30.4, darken(mat, 0.2), M.Rubber)
	b.Ball(-16, 22, -12, 42, b.Map(rgb(150, 120, 220)), M.SmoothPlastic)
	for _, x in ipairs({ 30, 42 }) do
		b.CylZ(x, 4, -14, 8, 5, rgb(230, 80, 110), M.Rubber)
		b.CylZ(x, 4, -2, 8, 5, rgb(230, 80, 110), M.Rubber)
		b.CylZ(x, 4, -8, 2.6, 8, STEEL, M.Metal)
	end
	b.Footprint(90, 46, 43)
end

R.PingPongTable = function(b, ctx)
	local depth = 60
	local top = ctx.TopY(1, 50)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(sx * 38, 3, sz * 24, 4, top - 5, 4, IRON, M.Metal)
			b.Ball(sx * 38, 2, sz * 24, 5, IRON_DARK, M.Rubber)
		end
	end
	b.Box(0, 12, 0, 78, 3, 3, IRON, M.Metal)
	local blue = b.Map(rgb(40, 90, 170))
	b.Box(0, top - 2, 0, 98, 2.4, depth, blue, M.Wood)
	-- lignes blanches (0.06 au-dessus)
	b.Box(0, top + 0.4, depth / 2 - 1, 98, 0.06, 1.2, WHITE, M.SmoothPlastic)
	b.Box(0, top + 0.4, -depth / 2 + 1, 98, 0.06, 1.2, WHITE, M.SmoothPlastic)
	b.Box(-48, top + 0.4, 0, 1.2, 0.06, depth - 2.6, WHITE, M.SmoothPlastic)
	b.Box(48, top + 0.4, 0, 1.2, 0.06, depth - 2.6, WHITE, M.SmoothPlastic)
	b.Box(0, top + 0.4, 0, 98, 0.06, 0.8, WHITE, M.SmoothPlastic)
	-- filet (au milieu, de l'avant à l'arrière)
	glass(b.Box(0, top + 0.4, 0, 0.6, 7, depth + 4, WHITE, M.Fabric), 0.4)
	for _, sz in ipairs({ -1, 1 }) do
		b.Cyl(0, top - 3, sz * (depth / 2 + 2.5), 2, 11, IRON_DARK, M.Metal)
	end
	b.Box(0, top + 7, 0, 0.8, 1, depth + 4, WHITE, M.Fabric)
	-- raquettes + balle
	for _, spec in ipairs({ { -26, 8, RED }, { 30, -10, rgb(30, 30, 36) } }) do
		b.Cyl(spec[1], top + 0.5, spec[2], 14, 1, spec[3], M.Rubber)
		b.Box(spec[1] + 8, top + 0.5, spec[2], 9, 1.6, 3, WALNUT, M.Wood)
	end
	b.Ball(12, top + 12, 6, 3, rgb(255, 170, 60), M.SmoothPlastic)
	b.Top(1, -24, top + 0.5, 0, 44, depth - 6)
	b.Footprint(98, depth + 6, top + 8)
end

R.RowingMachine = function(b, _ctx)
	local frame = b.Map(IRON)
	b.Box(6, 8, 0, 88, 6, 12, frame, M.Metal)
	b.Box(-40, 0, 0, 12, 8, 34, IRON_DARK, M.Metal)
	b.Box(46, 0, 0, 8, 8, 26, IRON_DARK, M.Metal)
	-- volant ventilé (disque dans son carter)
	b.CylZ(-36, 26, 0, 32, 12, rgb(60, 62, 72), M.SmoothPlastic)
	b.CylZ(-36, 26, 0, 33, 4, rgb(230, 70, 80), M.SmoothPlastic)
	b.CylZ(-36, 26, 6.4, 10, 1, STEEL, M.Metal)
	-- bras + écran
	b.Tube(-30, 36, 0, -20, 58, 0, 3, frame, M.Metal)
	b.BoxR(CFrame.new(-18, 62, 0) * CFrame.Angles(0, 0, 0.3), 3, 14, 18, IRON_DARK, M.SmoothPlastic)
	glow(b, b.BoxR(CFrame.new(-16.2, 62.6, 0) * CFrame.Angles(0, 0, 0.3), 0.6, 10, 14, rgb(90, 200, 120), M.Neon))
	-- poignée + sangle
	b.Tube(-24, 30, 0, -12, 30, 0, 1, rgb(30, 30, 36), M.Fabric)
	b.CylZ(-10, 30, 0, 3, 22, rgb(30, 30, 36), M.Rubber)
	-- repose-pieds + siège
	for _, sz in ipairs({ -1, 1 }) do
		b.BoxR(CFrame.new(-16, 18, sz * 8) * CFrame.Angles(0, 0, 0.5), 12, 3, 9, rgb(230, 70, 80), M.Rubber)
	end
	b.Round(14, 14, 0, 22, 8, 22, 6, rgb(40, 40, 46), M.Leather)
	b.Seat(14, 22, 0, 20, 20)
	b.Footprint(100, 36, 70)
end

R.WeightBench = function(b, _ctx)
	local iron = b.Map(IRON)
	-- rack
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 36, 0, -14, 16, 4, 20, IRON_DARK, M.Metal)
		b.Box(sx * 36, 4, -14, 5, 80, 5, iron, M.Metal)
		b.Box(sx * 36, 60, -10, 7, 3, 8, IRON_DARK, M.Metal) -- crochets
	end
	-- barre + disques
	b.CylX(0, 65, -8, 2.2, 98, STEEL, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		b.CylX(sx * 43, 65, -8, 26, 3, rgb(40, 40, 46), M.Rubber)
		b.CylX(sx * 46, 65, -8, 20, 3, RED, M.Rubber)
	end
	-- banc
	b.Box(0, 0, 10, 8, 26, 8, IRON_DARK, M.Metal)
	b.Box(0, 0, 10, 60, 3, 10, IRON_DARK, M.Metal)
	b.Round(0, 26, 10, 64, 8, 20, 5, rgb(40, 40, 46), M.Leather)
	b.Box(0, 34, 19.2, 58, 1.4, 1, RED, M.Leather)
	-- haltère au sol
	b.CylX(30, 5, 28, 10, 4, rgb(60, 60, 70), M.Rubber)
	b.CylX(40, 5, 28, 10, 4, rgb(60, 60, 70), M.Rubber)
	b.CylX(35, 5, 28, 2.4, 10, STEEL, M.Metal)
	b.Seat(0, 34, 10, 40, 18)
	b.Footprint(100, 60, 84)
end

R.Treadmill = function(b, _ctx)
	local depth = 44
	b.Round(4, 0, 0, 92, 10, depth, 5, rgb(50, 52, 60), M.SmoothPlastic)
	b.Box(8, 10, 0, 76, 1.2, depth - 12, rgb(30, 30, 36), M.Rubber)
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(8, 10, sz * (depth / 2 - 4), 80, 2, 6, rgb(70, 72, 84), M.SmoothPlastic)
		b.Tube(-36, 8, sz * 18, -30, 64, sz * 18, 4, STEEL, M.Metal)
		b.Tube(-30, 52, sz * 18, -6, 52, sz * 18, 3, STEEL, M.Metal)
	end
	-- console
	b.BoxR(CFrame.new(-30, 70, 0) * CFrame.Angles(0, 0, 0.35), 6, 16, 40, IRON_DARK, M.SmoothPlastic)
	glow(b, b.BoxR(CFrame.new(-26.9, 71, 0) * CFrame.Angles(0, 0, 0.35), 0.6, 10, 26, CYAN, M.Neon))
	b.Ball(-24, 76, 14, 4, RED, M.SmoothPlastic)
	b.Cyl(-26, 66, -14, 5, 10, rgb(120, 200, 240), M.Glass)
	b.Footprint(100, depth, 80)
end

R.ClimbingWall = function(b, _ctx)
	local panel = b.Map(rgb(214, 200, 176))
	b.Box(0, 4, 2, 88, 92, 4, panel, M.WoodPlanks)
	for k = 1, 3 do
		b.Box(0, 4 + k * 23, 4.1, 88, 0.6, 0.2, darken(panel, 0.2), M.WoodPlanks)
	end
	local colors = { RED, BLUE, rgb(255, 200, 60), LIME, MAGENTA, ORANGE, CYAN }
	local holds = { { -30, 16 }, { -12, 26 }, { -24, 38 }, { 4, 42 }, { 20, 30 }, { -6, 56 }, { 16, 62 }, { -20, 70 }, { 2, 78 }, { 26, 84 },
		{ -32, 54 }, { 32, 48 }, { 10, 14 }, { -14, 88 } }
	for index, h in ipairs(holds) do
		local size = 7 + (index % 3) * 2
		b.EggR(CFrame.new(h[1], h[2], 5.2) * CFrame.Angles(0, 0, index * 0.4), size, size * 0.7, 4, colors[(index % #colors) + 1], M.SmoothPlastic)
	end
	b.Tube(36, 96, 8, 36, 4, 8, 1.6, rgb(255, 120, 60), M.Fabric)
	b.CylZ(36, 94, 6, 5, 4, STEEL, M.Metal)
	b.Footprint(88, 10, 100)
end

----------------------------------------------------------------------
-- 💎 Luxe
----------------------------------------------------------------------

R.VelvetChaise = function(b, ctx)
	local seat = ctx.TopY(1, 38)
	local velvet = b.Map(VELVET)
	local depth = 44
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(sx * 36, 0, sz * 16, 4, 12, GOLD, M.Metal)
		end
	end
	b.Box(4, 10, 0, 86, 2, depth, GOLD, M.Metal)
	b.Box(4, 12, 0, 86, seat - 20, depth, darken(velvet, 0.3), M.Fabric)
	b.Cushion(6, seat - 9, 0, 84, 10, depth, velvet, M.Fabric)
	-- dossier arrondi, haut à gauche
	b.Round(-38, 12, 0, 22, 64, depth, 10, velvet, M.Fabric)
	b.CylZ(-38, 76, 0, 22, depth, velvet, M.Fabric)
	for row = 0, 3 do
		for _, sz in ipairs({ -12, 0, 12 }) do
			b.Ball(-26.8, 34 + row * 10, sz + (row % 2) * 6, 2.4, darken(velvet, 0.3), M.Fabric)
		end
	end
	pillow(b, -20, seat - 1, 4, 20, 10, 12, rgb(236, 210, 120), 0)
	b.Top(1, 12, seat, 0, 70, depth - 8)
	b.Footprint(90, depth, 87)
end

R.MarbleStatue = function(b, _ctx)
	b.Box(0, 0, 0, 52, 10, 40, MARBLE, M.Marble)
	b.Cyl(0, 10, 0, 34, 38, MARBLE, M.Marble)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		b.Cyl(math.cos(a) * 16.4, 11, math.sin(a) * 16.4, 2, 36, MARBLE_VEIN, M.Marble)
	end
	b.Box(0, 48, 0, 44, 5, 36, MARBLE, M.Marble)
	-- buste drapé + tête + couronne de laurier
	b.Egg(0, 62, 0, 38, 22, 24, MARBLE, M.Marble)
	b.BoxR(CFrame.new(-8, 62, 11) * CFrame.Angles(0, 0, 0.6), 4, 20, 2, MARBLE_VEIN, M.Marble)
	b.Cyl(0, 68, 0, 11, 10, MARBLE, M.Marble)
	b.Egg(0, 86, 1, 20, 24, 22, MARBLE, M.Marble)
	b.Wedge(0, 83, 12.4, 4, 6, 3, MARBLE, "Front", M.Marble) -- nez
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		b.EggR(CFrame.new(math.cos(a) * 10, 93, 1 + math.sin(a) * 11) * CFrame.Angles(0, -a, 0.5), 3, 6, 2, rgb(210, 190, 120), M.Metal)
	end
	b.Footprint(52, 40, 99)
end

R.KingBed = function(b, ctx)
	local top = ctx.TopY(1, 40)
	local depth = 92
	local walnut = b.Map(WALNUT)
	local duvet = b.Map(rgb(90, 70, 130))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(sx * 42, 0, sz * 40, 5, 6, GOLD, M.Metal)
		end
	end
	b.Box(4, 6, 0, 92, 16, depth, walnut, M.Wood)
	b.Box(4, 22, 0, 90, top - 24, depth - 4, WHITE, M.Fabric)
	b.Box(18, top - 8, 0, 62, 9, depth - 2, duvet, M.Fabric)
	b.Box(-15, top - 7.6, 0, 10, 9, depth - 1, rgb(236, 220, 180), M.Fabric)
	b.Box(40, top - 7.2, 0, 16, 9, depth, GOLD, M.Fabric) -- plaid
	-- tête de lit capitonnée haute
	b.Round(-44, 6, 0, 12, 80, depth + 4, 5, rgb(236, 226, 214), M.Fabric)
	for row = 0, 5 do
		for col = -3, 3 do
			b.Ball(-37.6, 22 + row * 10, col * 12 + (row % 2) * 6, 2.4, rgb(196, 180, 164), M.Fabric)
		end
	end
	for _, z in ipairs({ -26, 0, 26 }) do
		b.EggR(CFrame.new(-30, top + 4, z) * CFrame.Angles(0, 0, -0.35), 20, 10, 26, WHITE, M.Fabric)
	end
	b.EggR(CFrame.new(-24, top + 4, -12) * CFrame.Angles(0, 0, -0.3), 14, 9, 20, rgb(236, 220, 180), M.Fabric)
	b.EggR(CFrame.new(-22, top + 3, 12) * CFrame.Angles(0, 0, -0.3), 10, 8, 14, duvet, M.Fabric)
	b.Top(1, 8, top + 1, 0, 74, depth - 12)
	b.Footprint(100, depth + 4, 86)
end

R.PoolTable = function(b, ctx)
	local top = ctx.TopY(1, 56)
	local depth = 64
	local walnut = b.Map(WALNUT)
	for _, x in ipairs({ -38, 0, 38 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Box(x, 0, sz * 24, 9, 8, 9, WALNUT_DARK, M.Wood)
			b.Box(x, 8, sz * 24, 7, top - 20, 7, walnut, M.Wood)
			b.Box(x, 22, sz * 24, 7.6, 2, 7.6, GOLD, M.Metal)
		end
	end
	b.Box(0, top - 12, 0, 98, 9, depth, walnut, M.Wood)
	b.Box(0, top - 8.4, depth / 2 + 0.2, 90, 1.4, 0.6, GOLD, M.Metal)
	b.Box(0, top - 3, 0, 86, 2, depth - 12, b.Map(FELT), M.Fabric)
	-- bandes (coussins verts) + cadre bois
	for _, sz in ipairs({ -1, 1 }) do
		b.Box(0, top - 3, sz * (depth / 2 - 4), 86, 4, 4, lighten(FELT, 0.1), M.Fabric)
		b.Box(0, top - 3, sz * (depth / 2 - 1), 98, 5, 2, walnut, M.Wood)
	end
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 45, top - 3, 0, 4, 4, depth - 12, lighten(FELT, 0.1), M.Fabric)
		b.Box(sx * 48, top - 3, 0, 2, 5, depth - 4, walnut, M.Wood)
	end
	-- poches
	for _, x in ipairs({ -45, 0, 45 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.Cyl(x, top - 2.9, sz * (depth / 2 - 4), 6, 4.2, IRON_DARK, M.Fabric)
		end
	end
	-- boules en triangle + boule blanche + queue
	local colors = { rgb(240, 200, 40), RED, rgb(40, 90, 200), rgb(30, 30, 30), rgb(120, 50, 150), ORANGE }
	local n = 0
	for row = 0, 2 do
		for k = 0, row do
			n += 1
			b.Ball(20 + row * 3.6, top + 1, (k - row / 2) * 4.2, 4, colors[(n % #colors) + 1], M.SmoothPlastic)
		end
	end
	b.Ball(-20, top + 1, 0, 4, rgb(250, 250, 240), M.SmoothPlastic)
	b.Tube(-24, top + 1.6, 2, -64, top + 6, 10, 1.6, rgb(214, 180, 120), M.Wood)
	b.Top(1, 0, top, 0, 80, depth - 16)
	b.Footprint(98, depth, top + 3)
end

R.AmethystGeode = function(b, _ctx)
	b.Box(0, 0, 0, 48, 10, 34, IRON_DARK, M.Metal)
	b.Box(0, 10, 0, 30, 8, 22, IRON, M.Metal)
	-- coquille de pierre (dos) + bord blanc + cristaux
	b.Egg(0, 54, -6, 70, 76, 30, STONE, M.Slate)
	b.Egg(0, 54, 2, 60, 66, 20, rgb(236, 230, 240), M.SmoothPlastic)
	b.Egg(0, 54, 4, 52, 58, 20, rgb(110, 60, 160), M.SmoothPlastic)
	local purples = { rgb(170, 110, 230), rgb(140, 80, 210), rgb(200, 150, 250), rgb(120, 70, 190) }
	local n = 0
	for row = 0, 4 do
		for col = 0, 3 do
			n += 1
			local x = -15 + col * 10 + (row % 2) * 5
			local y = 34 + row * 10
			local lean = CFrame.Angles(0.5 + (n % 3) * 0.2, 0, (col - 1.5) * 0.3)
			local crystal = b.BoxR(CFrame.new(x, y, 12) * lean, 4, 10, 4, purples[(n % #purples) + 1], M.Glass)
			crystal.Transparency = 0.15
		end
	end
	local heart = glow(b, b.Ball(0, 54, 8, 8, rgb(220, 180, 255), M.Neon))
	b.Light(heart, rgb(200, 150, 250), 10, 0.5)
	b.Footprint(70, 34, 92)
end

R.ModernFireplace = function(b, _ctx)
	local slab = b.Map(rgb(64, 64, 70))
	b.Box(0, 22, 3, 96, 56, 6, slab, M.Slate)
	b.Box(0, 72, 6.5, 96, 6, 1, rgb(90, 90, 96), M.Slate)
	-- foyer : boîte sombre en saillie, cadre inox, vitre
	b.Box(0, 34, 6.5, 84, 28, 1, rgb(20, 18, 22), M.Metal) -- fond du foyer
	b.Box(0, 34, 9, 84, 1.6, 5, rgb(30, 28, 32), M.Metal) -- sole
	b.Box(0, 60.4, 9, 84, 1.6, 5, rgb(30, 28, 32), M.Metal) -- linteau
	for _, x in ipairs({ -41.2, 41.2 }) do
		b.Box(x, 35.6, 9, 1.6, 24.8, 5, rgb(30, 28, 32), M.Metal)
	end
	for _, y in ipairs({ 33, 62 }) do
		b.Box(0, y, 11.4, 88, 1.4, 1, STEEL, M.Metal)
	end
	for _, x in ipairs({ -43.3, 43.3 }) do
		b.Box(x, 33, 11.4, 1.4, 30.4, 1, STEEL, M.Metal)
	end
	for k = 0, 9 do
		b.Egg(-36 + k * 8, 37.4, 9, 8, 4, 5, k % 2 == 0 and rgb(200, 196, 190) or rgb(150, 146, 144), M.Pebble)
	end
	local first = nil
	for k = 0, 7 do
		local flame = glow(b, b.Egg(-32 + k * 9, 44 + (k % 3), 8.4, 6, 12 + (k % 3) * 2, 3, k % 2 == 0 and FIRE or rgb(255, 200, 80), M.Neon))
		first = first or flame
	end
	glass(b.Box(0, 34.6, 11.2, 84, 27, 0.4, GLASS, M.Glass), 0.85)
	if first then
		b.Light(first, FIRE, 14, 0.8)
	end
	b.Footprint(96, 12, 100)
end

R.CinemaRecliners = function(b, ctx)
	local seat = ctx.TopY(1, 38)
	local leather = b.Map(rgb(170, 40, 50))
	local depth = 56
	b.Box(0, 0, 0, 98, 6, depth, IRON_DARK, M.Metal)
	glow(b, b.Box(0, 1, depth / 2 + 0.3, 92, 1.4, 0.6, AMBER, M.Neon))
	for index = -1, 1 do
		local x = index * 32
		b.Box(x, 6, 2, 26, seat - 16, depth - 8, darken(leather, 0.2), M.Leather)
		b.Cushion(x, seat - 10, 4, 26, 10, depth - 14, leather, M.Leather)
		b.BoxR(CFrame.new(x, seat + 14, -depth / 2 + 8) * CFrame.Angles(-0.25, 0, 0), 26, 36, 10, leather, M.Leather)
		b.BoxR(CFrame.new(x, seat + 16, -depth / 2 + 13.5) * CFrame.Angles(-0.25, 0, 0), 18, 16, 2, darken(leather, 0.15), M.Leather)
		-- repose-pieds déplié
		b.BoxR(CFrame.new(x, seat - 16, depth / 2 + 4) * CFrame.Angles(0.5, 0, 0), 22, 4, 18, darken(leather, 0.2), M.Leather)
	end
	for index = 0, 3 do
		local x = -48 + index * 32
		b.Box(x, 6, 2, 6, seat - 2, depth - 8, rgb(40, 36, 40), M.Leather)
		b.Cyl(x, seat + 4, 14, 5, 1.4, IRON, M.Metal) -- porte-gobelet
	end
	-- pot de pop-corn dans un porte-gobelet
	b.Cyl(16, seat + 5, 14, 5, 8, WHITE, M.SmoothPlastic)
	b.Cyl(16, seat + 5, 14, 5.2, 3, RED, M.SmoothPlastic)
	for k = 0, 3 do
		b.Ball(15 + (k % 2) * 2, seat + 13.5 + math.floor(k / 2), 13 + k % 2, 3, rgb(255, 240, 190), M.SmoothPlastic)
	end
	b.Top(1, 0, seat, 4, 90, depth - 20)
	b.Seat(0, seat, 4, 22, depth - 20)
	b.Footprint(100, depth + 12, seat + 32)
end

R.WhitePiano = function(b, _ctx)
	local lacquer = b.Map(rgb(248, 248, 252))
	-- caisse (côté droit arrondi = la queue du piano)
	b.Box(-12, 34, 0, 70, 20, 54, lacquer, M.SmoothPlastic)
	b.Cyl(22, 34, -6, 44, 20, lacquer, M.SmoothPlastic)
	b.Box(-12, 36, 27.2, 60, 1.2, 0.6, GOLD, M.Metal)
	-- pieds dorés
	for _, spec in ipairs({ { -40, 20 }, { -40, -20 }, { 34, -10 } }) do
		b.Cyl(spec[1], 0, spec[2], 8, 34, lacquer, M.SmoothPlastic)
		b.Cyl(spec[1], 0, spec[2], 9, 3, GOLD, M.Metal)
	end
	-- clavier
	b.Box(-12, 50, 30, 64, 4, 10, lacquer, M.SmoothPlastic)
	b.Box(-12, 54, 30, 60, 1.6, 9, WHITE, M.SmoothPlastic)
	for k = 0, 13 do
		if k % 7 ~= 2 and k % 7 ~= 6 then
			b.Box(-40 + k * 4.2, 55.6, 28, 2, 1.4, 5, rgb(30, 30, 36), M.SmoothPlastic)
		end
	end
	b.Box(-12, 56, 25, 64, 8, 2, lacquer, M.SmoothPlastic) -- pupitre
	b.BoxR(CFrame.new(-12, 62, 22) * CFrame.Angles(-0.25, 0, 0), 30, 12, 1.2, rgb(250, 244, 226), M.SmoothPlastic) -- partition
	-- couvercle ouvert + béquille
	-- (charnière le long du côté gauche, soulevé à droite par la béquille)
	local lift = 0.4
	b.BoxR(CFrame.new(-47 + 45 * math.cos(lift), 54 + 45 * math.sin(lift), -2) * CFrame.Angles(0, 0, lift), 90, 2, 56, lacquer, M.SmoothPlastic)
	b.Tube(26, 54, -4, 26, 53 + 73 * math.tan(lift), -4, 1.6, GOLD, M.Metal)
	-- lyre + pédales
	b.Box(-12, 6, 20, 10, 28, 4, lacquer, M.SmoothPlastic)
	for k = -1, 1 do
		b.Box(-12 + k * 4, 3, 24, 2.4, 1.6, 6, GOLD, M.Metal)
	end
	b.Footprint(100, 60, 94)
end

R.Jacuzzi = function(b, _ctx)
	local shell = b.Map(rgb(236, 230, 220))
	local rimTop = 38
	b.Cyl(0, 0, 0, 96, 28, shell, M.Marble)
	glow(b, b.Cyl(0, 14, 0, 96.6, 1.2, CYAN, M.Neon))
	-- fond clair + eau transparente bleue (on voit dedans)
	b.Cyl(0, 28, 0, 88, 0.6, rgb(190, 225, 240), M.SmoothPlastic)
	local water = glass(b.Cyl(0, 28.6, 0, 88, 6.4, b.Map(WATER), M.Glass), 0.35)
	b.Light(water, CYAN, 12, 0.5)
	-- margelle : anneau de 16 segments (extérieur 100, intérieur 88)
	local segments = 16
	for k = 0, segments - 1 do
		local angle = (k + 0.5) / segments * math.pi * 2
		local r = 47
		local chord = 2 * 50 * math.sin(math.pi / segments) + 0.4
		b.BoxR(CFrame.new(math.cos(angle) * r, 28 + (rimTop - 28) / 2, math.sin(angle) * r) * CFrame.Angles(0, -angle, 0), 6, rimTop - 28, chord,
			lighten(shell, 0.05), M.Marble)
	end
	-- bulles à la surface
	for k = 0, 13 do
		local a = k * 2.39996
		local r = 8 + (k * 7) % 30
		glass(b.Ball(math.cos(a) * r, 35.2 + (k % 3) * 0.5, math.sin(a) * r, 3 + k % 3, WHITE, M.Glass), 0.3)
	end
	-- marches, serviettes roulées, bougie
	b.Box(0, 0, 50, 36, 10, 12, lighten(shell, 0.05), M.Marble)
	b.CylX(30, rimTop + 4, 30, 8, 16, WHITE, M.Fabric)
	b.CylX(30, rimTop + 11, 30, 7, 14, rgb(160, 210, 230), M.Fabric)
	b.Cyl(-32, rimTop, 30, 5, 7, rgb(250, 240, 220), M.SmoothPlastic)
	glow(b, b.Ball(-32, rimTop + 8.4, 30, 2.4, FIRE, M.Neon))
	b.Seat(0, 30, -16, 40, 26)
	b.Footprint(100, 100, rimTop)
end

R.AquariumWall = function(b, _ctx)
	local depth = 36
	local frame = b.Map(IRON_DARK)
	b.Box(0, 0, 0, 98, 14, depth, b.Map(rgb(80, 64, 50)), M.Wood)
	b.Box(0, 14, 0, 98, 4, depth, frame, M.Metal)
	b.Box(0, 94, 0, 98, 6, depth, frame, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 47, 18, 0, 4, 76, depth, frame, M.Metal)
	end
	-- eau + fond + sable
	b.Box(0, 18, -depth / 2 + 1, 90, 76, 2, WATER_DEEP, M.SmoothPlastic)
	glass(b.Box(0, 18, 0, 90, 76, depth - 4, b.Map(WATER), M.Glass), 0.55)
	b.Box(0, 18, 0, 89, 6, depth - 5, rgb(236, 214, 160), M.Sand)
	-- coraux, algues, rochers
	for index, s in ipairs({ { -32, rgb(255, 110, 120) }, { -14, rgb(255, 170, 80) }, { 16, rgb(200, 110, 230) }, { 34, rgb(255, 130, 160) } }) do
		for k = 0, 2 do
			b.Tube(s[1], 24, -4 + k * 3, s[1] + (k - 1) * 5, 38 + k * 2, -2 + k * 2, 2.4, s[2], M.SmoothPlastic)
			b.Ball(s[1] + (k - 1) * 5, 38 + k * 2, -2 + k * 2, 4, s[2], M.SmoothPlastic)
		end
		local _ = index
	end
	for _, x in ipairs({ -24, 4, 26 }) do
		b.EggR(CFrame.new(x, 44, -8) * CFrame.Angles(0, 0, 0.1), 5, 40, 2, LEAF, M.SmoothPlastic)
	end
	b.Egg(-4, 26, 0, 16, 10, 12, STONE_DARK, M.Rock)
	fish(b, -22, 72, 4, 12, rgb(255, 150, 40), 1)
	fish(b, 18, 62, 2, 10, rgb(255, 220, 60), -1)
	fish(b, -2, 50, 6, 14, rgb(60, 140, 255), 1)
	fish(b, 30, 82, -2, 9, rgb(255, 100, 140), -1)
	fish(b, -34, 54, -4, 8, WHITE, -1)
	-- lumière douce au-dessus de l'eau
	local lamp = glow(b, b.Box(0, 92.6, 0, 80, 1.2, 8, rgb(200, 240, 255), M.Neon))
	b.Light(lamp, rgb(170, 230, 255), 14, 0.6)
	b.Footprint(98, depth, 100)
end

R.RollercoasterModel = function(b, _ctx)
	b.Round(0, 0, 0, 98, 6, 56, 5, rgb(60, 140, 90), M.Grass)
	local red = b.Map(RED)
	-- rail (chemin de tubes) : montée, descente, looping, virage
	local rail: { { number } } = {
		{ -44, 12, 16 }, { -34, 36, 14 }, { -24, 64, 10 }, { -16, 70, 6 }, { -8, 60, 2 }, { 0, 40, 0 }, { 8, 24, -2 }, { 18, 20, -4 },
	}
	-- looping (cercle vertical dans le plan x-y)
	for k = 0, 10 do
		local a = -math.pi / 2 + k / 10 * math.pi * 2
		table.insert(rail, { 28 + math.cos(a) * 12, 34 + math.sin(a) * 14, -6 - k * 0.8 })
	end
	table.insert(rail, { 40, 22, -18 })
	table.insert(rail, { 44, 26, -6 })
	table.insert(rail, { 38, 30, 10 })
	House3DKit.Path(b, rail, 2.6, red, M.Metal)
	-- piliers blancs
	for _, p in ipairs({ { -34, 36, 14 }, { -24, 64, 10 }, { -8, 60, 2 }, { 8, 24, -2 }, { 40, 22, -18 }, { 38, 30, 10 } }) do
		b.Cyl(p[1], 6, p[3], 2, p[2] - 7, rgb(236, 236, 244), M.Metal)
	end
	-- 3 wagonnets dans la descente
	for k = 0, 2 do
		local t = k * 0.28
		local x, y, z = -8 + t * 12, 60 - t * 50 + 3, 2 - t * 3
		b.BoxR(CFrame.new(x, y, z) * CFrame.Angles(0, 0, -1.1), 7, 5, 6, k == 0 and rgb(255, 214, 60) or rgb(60, 160, 255), M.SmoothPlastic)
	end
	-- gare + drapeau
	b.Box(-40, 6, 20, 16, 10, 12, rgb(255, 230, 180), M.Wood)
	b.Wedge(-40, 16, 20, 18, 6, 14, rgb(236, 72, 120), "Front", M.SmoothPlastic)
	b.Cyl(46, 6, 22, 1.2, 30, IRON, M.Metal)
	b.Box(49, 30, 22, 6, 4, 0.6, rgb(255, 214, 60), M.Fabric)
	b.Footprint(98, 56, 76)
end

R.GoldThrone = function(b, ctx)
	local seat = ctx.TopY(1, 42)
	local gold = b.Map(GOLD)
	local velvet = b.Map(rgb(170, 30, 50))
	local depth = 44
	b.Box(0, 0, 0, 76, 6, depth + 16, GOLD_DARK, M.Metal) -- estrade
	b.Box(0, 6, 0, 60, seat - 18, depth, gold, M.Metal)
	b.Cushion(0, seat - 12, 4, 54, 12, depth - 8, velvet, M.Fabric)
	-- dossier haut + velours + joyau
	b.Round(0, 6, -depth / 2 + 5, 54, 92, 10, 4, gold, M.Metal)
	b.Box(0, seat + 6, -depth / 2 + 10.4, 38, 42, 1, velvet, M.Fabric)
	b.BoxR(CFrame.new(0, seat + 32, -depth / 2 + 11.4) * CFrame.Angles(0, 0, math.pi / 4), 6, 6, 1, rgb(255, 80, 120), M.Glass)
	-- couronne en haut du dossier
	for k = -1, 1 do
		b.Wedge(k * 13 - 3, 98, -depth / 2 + 5, 6, 10, 8, gold, "Left", M.Metal)
		b.Wedge(k * 13 + 3, 98, -depth / 2 + 5, 6, 10, 8, gold, "Right", M.Metal)
		b.Ball(k * 13, 108, -depth / 2 + 5, 4, rgb(236, 72, 100), M.Glass)
	end
	-- accoudoirs + têtes de lion + pieds griffes
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * 32, 6, 0, 10, seat + 12, depth, gold, M.Metal)
		b.Ball(sx * 32, seat + 16, depth / 2 - 2, 14, GOLD_LIGHT, M.Metal)
		b.Ball(sx * 32, seat + 14, depth / 2 + 4, 5, GOLD_DARK, M.Metal)
		for _, sz in ipairs({ -1, 1 }) do
			b.Ball(sx * 30, 8, sz * (depth / 2 - 2), 10, GOLD_LIGHT, M.Metal)
		end
	end
	b.Top(1, 0, seat, 4, 40, depth - 12)
	b.Seat(0, seat, 4, 40, depth - 12)
	b.Footprint(76, depth + 16, 112)
end

R.IndoorWaterfall = function(b, _ctx)
	local depth = 40
	-- mur de pierres
	b.Box(0, 16, -depth / 2 + 6, 84, 80, 12, STONE, M.Slate)
	for index, s in ipairs({ { -30, 86, 20 }, { 24, 88, 22 }, { -26, 60, 18 }, { 30, 62, 20 }, { -32, 34, 20 }, { 28, 34, 18 } }) do
		b.EggR(CFrame.new(s[1], s[2], -depth / 2 + 13) * CFrame.Angles(0, 0, index * 0.5), s[3], 14, 8, index % 2 == 0 and STONE_DARK or rgb(170, 164, 156), M.Rock)
	end
	-- déversoir + nappe d'eau
	b.Box(0, 92, -depth / 2 + 14, 36, 3, 8, STEEL, M.Metal)
	glass(b.Box(0, 20, -depth / 2 + 16, 32, 72, 1.2, b.Map(WATER), M.Glass), 0.35)
	for k = 0, 4 do
		glass(b.Box(-12 + k * 6, 22, -depth / 2 + 17.2, 1.4, 68, 0.4, rgb(200, 240, 255), M.Glass), 0.3)
	end
	-- bassin de pierre + eau + remous
	b.Round(0, 0, 4, 98, 16, depth - 4, 8, STONE_DARK, M.Slate)
	local pool = glass(b.Round(0, 14, 4, 90, 3, depth - 10, 6, b.Map(WATER), M.Glass), 0.3)
	for k = 0, 4 do
		glass(b.Egg(-10 + k * 5, 17.4, -depth / 2 + 18 + (k % 2) * 3, 8, 2, 5, WHITE, M.Glass), 0.3)
	end
	b.Light(pool, rgb(170, 230, 255), 12, 0.5)
	-- fougères de chaque côté
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 3 do
			b.EggR(CFrame.new(sx * 40, 24 + k * 4, 8 + (k % 2) * 6) * CFrame.Angles(0.4, sx * k * 0.8, sx * (0.6 - k * 0.2)), 8, 24, 1.6,
				k % 2 == 0 and LEAF or LEAF_DARK, M.SmoothPlastic)
		end
	end
	b.Footprint(98, depth, 96)
end

R.CapsuleBed = function(b, _ctx)
	local shell = b.Map(rgb(240, 242, 248))
	local depth = 70
	b.Round(0, 0, 0, 90, 8, depth - 10, 6, IRON, M.Metal)
	b.Round(0, 8, 0, 98, 18, depth, 12, shell, M.SmoothPlastic)
	glow(b, b.Box(0, 24, depth / 2 + 0.3, 80, 1.2, 0.6, CYAN, M.Neon))
	-- matelas + couette + oreiller
	b.Box(0, 26, 0, 88, 8, depth - 8, rgb(200, 210, 240), M.Fabric)
	b.Box(14, 30, 0, 58, 6, depth - 6, b.Map(rgb(90, 120, 220)), M.Fabric)
	b.EggR(CFrame.new(-32, 38, 0) * CFrame.Angles(0, 0, -0.3), 16, 8, 30, WHITE, M.Fabric)
	-- coque : arceaux au-dessus (fond fermé, avant en verre)
	for k = 0, 8 do
		local a = k / 8 * math.pi
		local x, y = math.cos(a) * 46, 26 + math.sin(a) * 40
		b.BoxR(CFrame.new(x, y, -depth / 2 + 3) * CFrame.Angles(0, 0, a), 4, 18, 6, shell, M.SmoothPlastic)
	end
	b.Box(0, 26, -depth / 2 + 1.5, 86, 36, 3, rgb(40, 50, 90), M.SmoothPlastic)
	for k = 0, 7 do
		glow(b, b.Ball(-30 + (k * 17) % 60, 44 + (k * 11) % 16, -depth / 2 + 3.2, 1.6, WHITE, M.Neon))
	end
	-- verrière (demi-coque transparente)
	local canopy = glass(b.EggR(CFrame.new(0, 26, 2), 96, 84, depth - 8, rgb(190, 220, 255), M.Glass), 0.75)
	local _ = canopy
	-- panneau de contrôle
	b.Box(40, 30, depth / 2 - 6, 10, 16, 4, IRON_DARK, M.SmoothPlastic)
	for k = 0, 2 do
		glow(b, b.CylZ(40, 34 + k * 4, depth / 2 - 3.8, 2.4, 0.6, ({ RED, CYAN, LIME })[k + 1], M.Neon))
	end
	b.Seat(0, 34, 0, 50, 36)
	b.Footprint(98, depth, 68)
end

R.DragonStatue = function(b, _ctx)
	local gold = b.Map(GOLD)
	b.Round(0, 0, 0, 80, 10, 50, 6, rgb(60, 50, 50), M.Marble)
	b.Round(0, 10, 0, 68, 4, 40, 5, GOLD_DARK, M.Metal)
	-- corps enroulé (anneaux de boules)
	local coil = { { -24, 22, 6, 20 }, { -10, 20, 12, 22 }, { 8, 20, 10, 22 }, { 22, 24, 2, 20 }, { 18, 34, -8, 18 }, { 4, 40, -10, 18 }, { -8, 46, -4, 16 },
		{ -6, 58, 2, 15 }, { 0, 68, 4, 14 } }
	for index, s in ipairs(coil) do
		b.Ball(s[1], s[2], s[3], s[4], index % 2 == 0 and gold or lighten(gold, 0.08), M.Foil)
		-- écailles dorsales
		b.Wedge(s[1], s[2] + s[4] * 0.42, s[3], 3, 5, 5, GOLD_DARK, "Front", M.Metal)
	end
	-- queue
	b.Tube(-24, 22, 6, -40, 16, 14, 7, gold, M.Foil)
	b.Wedge(-44, 14, 16, 8, 6, 3, GOLD_DARK, "Left", M.Metal)
	-- ailes (membranes fines + nervures)
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 2 do
			b.Tube(sx * 6, 56, -6, sx * (22 + k * 8), 88 - k * 12, -10 - k * 4, 2, GOLD_DARK, M.Metal)
		end
		b.BoxR(CFrame.new(sx * 20, 72, -10) * CFrame.Angles(0.2, 0, sx * -0.9), 26, 30, 1, gold, M.Foil)
	end
	-- tête, cornes, yeux, moustaches
	b.Egg(4, 80, 10, 18, 14, 22, gold, M.Foil)
	b.Egg(4, 76, 22, 12, 9, 12, lighten(gold, 0.1), M.Foil)
	for _, sx in ipairs({ -1, 1 }) do
		b.Tube(4 + sx * 5, 86, 4, 4 + sx * 10, 96, -6, 2.4, GOLD_LIGHT, M.Metal)
		glow(b, b.Ball(4 + sx * 6, 82, 18, 3, RED, M.Neon))
		b.Tube(4 + sx * 4, 74, 26, 4 + sx * 18, 70, 34, 1, GOLD_LIGHT, M.Metal)
	end
	-- perle
	local pearl = b.Ball(32, 42, 20, 14, rgb(240, 236, 255), M.Glass)
	pearl.Transparency = 0.05
	b.Light(pearl, rgb(255, 236, 180), 8, 0.4)
	b.Footprint(80, 50, 98)
end

R.AquariumTunnel = function(b, _ctx)
	local depth = 64
	local frame = b.Map(IRON_DARK)
	local radius = 40
	local band = 12
	-- sol du passage
	b.Box(0, 0, 0, 100, 3, depth, rgb(70, 72, 84), M.Slate)
	b.Box(0, 3, 0, 40, 0.6, depth, rgb(90, 100, 120), M.Slate)
	-- arche : bande d'eau (verre bleu) entre deux arceaux métalliques
	local segments = 12
	for k = 0, segments - 1 do
		local a = (k + 0.5) / segments * math.pi
		local r = radius + band / 2
		local x, y = math.cos(a) * r, 3 + math.sin(a) * r
		local cf = CFrame.new(x, y, 0) * CFrame.Angles(0, 0, a)
		local width = 2 * r * math.sin(math.pi / segments / 2) * 2 + 0.6
		glass(b.BoxR(cf, band, width, depth - 4, b.Map(WATER), M.Glass), 0.45)
		for _, sz in ipairs({ -1, 1 }) do
			b.BoxR(CFrame.new(x, y, sz * (depth / 2 - 1)) * CFrame.Angles(0, 0, a), band + 2, width, 2, frame, M.Metal)
		end
	end
	-- pieds de l'arche
	for _, sx in ipairs({ -1, 1 }) do
		b.Box(sx * (radius + band / 2), 0, 0, band + 4, 4, depth, frame, M.Metal)
	end
	-- vie marine dans la bande d'eau
	local sea = { { 150, 0.3, rgb(255, 150, 40), 1 }, { 30, 0.5, rgb(255, 220, 60), -1 }, { 100, 0.9, rgb(60, 140, 255), 1 }, { 60, 0.15, rgb(255, 100, 140), -1 },
		{ 120, 0.7, WHITE, 1 }, { 20, 0.2, rgb(255, 170, 80), -1 } }
	for index, s in ipairs(sea) do
		local a = math.rad(s[1])
		local r = radius + band / 2
		fish(b, math.cos(a) * r, 3 + math.sin(a) * r, (s[2] - 0.5) * (depth - 16), 8, s[3], s[4])
		local _ = index
	end
	-- raie manta au sommet
	local top = 3 + radius + band / 2
	b.BoxR(CFrame.new(0, top, 6) * CFrame.Angles(0, math.pi / 4, 0), 12, 1.4, 12, rgb(60, 70, 110), M.SmoothPlastic)
	b.Tube(0, top, 6, 0, top, -8, 1, rgb(60, 70, 110), M.SmoothPlastic)
	-- lumière bleue douce
	local light = glow(b, b.Box(0, 3.6, 0, 4, 0.4, depth - 8, rgb(140, 220, 255), M.Neon))
	b.Light(light, rgb(150, 220, 255), 16, 0.6)
	b.Footprint(100, depth, top + band / 2)
end

----------------------------------------------------------------------
-- Branchement (House3DRecipes.loadFamilies("House3DLuxe"))
----------------------------------------------------------------------

function House3DLuxe.Has(itemId: string): boolean
	return R[itemId] ~= nil
end

function House3DLuxe.Register(recipes: { [string]: any }, _family: { [string]: any }, _helpers: any, _flags: any)
	for id, recipe in pairs(R) do
		if recipes[id] == nil then
			recipes[id] = recipe
		end
	end
end

return House3DLuxe
