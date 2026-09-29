--[[
	Modern98 (ModuleScript) — (v9.8 CATALOG98) meubles modernes, loft
	industriel, déco, lumières, plantes, tech, cuisine, coin gamer et sport
	Emplacement : ReplicatedStorage > Client > Components > House > Art > Modern98
	Contrat : voir HouseArt (boîte 100 x 100, pieds en bas pour les objets au
	sol, objets muraux centrés).

	Style : le même rendu "autocollant" que le reste (contours doux, reflets,
	ombrages) mais en couleurs RÉALISTES (chêne, noyer, acier, béton, cuir,
	marbre, verre fumé) : ce ne sont pas des objets kawaii, donc pas de
	visages. Les dessus des tables, étagères, sièges et lits sont déclarés
	dans House/HouseSurfaces (mêmes coordonnées que les dessins et que les
	modèles 3D de House3DLuxe).
]]

local Art = {}

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
local LEATHER_DARK = rgb(104, 56, 36)
local LINEN = rgb(226, 220, 208)
local GREIGE = rgb(176, 168, 158)
local SLATE = rgb(92, 104, 122)
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
local AMBER = rgb(255, 196, 110)
local BLUE = rgb(70, 130, 220)
local GREEN_FELT = rgb(40, 140, 90)

----------------------------------------------------------------------
-- Petits outils
----------------------------------------------------------------------

-- Pied fin (tube) de meuble moderne
local function leg(kit, parent, x, top, bottom, w, color, z)
	return kit.Part(parent, x - w / 2, top, w, bottom - top, color, { Radius = math.max(1, w / 2), Z = z or 1, Thickness = 1.2 })
end

-- Pot (bas y = bas du pot), largeur en haut `w`, hauteur `h`
local function pot(kit, parent, cx, bottom, w, h, color, z)
	local zz = z or 3
	local body = kit.Part(parent, cx - w * 0.42, bottom - h, w * 0.84, h, color, { Radius = 5, Z = zz, Shine = true })
	kit.Part(parent, cx - w / 2, bottom - h - 2, w, 6, kit.Lighten(color, 0.12), { Radius = 3, Z = zz + 1 })
	return body
end

-- Feuille ovale inclinée (centre cx, cy)
local function leaf(kit, parent, cx, cy, w, h, color, rotation, z)
	local l = kit.Blob(parent, cx, cy, w, h, color, { Z = z or 4, Rotation = rotation, Thickness = 1.2 })
	kit.Line(l, w * 0.5, h * 0.12, w * 0.5, h * 0.88, 1, kit.Darken(color, 0.25), 0.3, 2)
	return l
end

-- Rangée de livres sur une étagère (bas = y), de x0 à x1
local function books(kit, parent, x0, x1, y, maxH, seed, z)
	local colors = { rgb(176, 64, 64), rgb(60, 96, 150), rgb(220, 190, 120), rgb(70, 120, 90), rgb(120, 80, 140), rgb(236, 226, 206), rgb(200, 120, 70) }
	local x = x0
	local n = seed
	while x < x1 - 3 do
		n += 1
		local w = 3 + (n * 7) % 3
		local h = maxH * (0.7 + ((n * 13) % 5) * 0.07)
		if x + w > x1 then
			break
		end
		if n % 9 == 0 then
			-- un livre penché
			kit.Part(parent, x + 1, y - h + 2, w, h - 1, colors[(n % #colors) + 1], { Radius = 1, Z = z, Rotation = 14, Thickness = 1, Shade = false })
			x += w + 3
		else
			kit.Part(parent, x, y - h, w, h, colors[(n % #colors) + 1], { Radius = 1, Z = z, Thickness = 1, Shade = 0.18 })
			x += w + 0.6
		end
	end
end

-- Écran lumineux (néons gamer)
local function glowScreen(kit, parent, x, y, w, h, top, bottom, z)
	local s = kit.Part(parent, x, y, w, h, top, { Radius = 2, Z = z, Outline = IRON_DARK, Thickness = 1.4, Shade = false })
	kit.Gradient(s, WHITE, kit.Lighten(bottom, 0.1), 90)
	s.BackgroundColor3 = top
	return s
end

----------------------------------------------------------------------
-- 🛋️ Moderne / minimaliste / loft
----------------------------------------------------------------------

-- Chaise blanche (vue de face) : dessus d'assise en y = 56
Art.SimpleChair = function(body, kit, _item)
	for _, x in ipairs({ 26, 74 }) do
		leg(kit, body, x, 58, 100, 5, OAK, 1)
	end
	kit.Line(body, 30, 84, 70, 84, 3, OAK_DARK, 0, 1)
	kit.Part(body, 26, 8, 48, 30, WHITE, { Radius = 12, Z = 2, Shine = true })
	for _, x in ipairs({ 32, 68 }) do
		leg(kit, body, x, 34, 56, 4, OAK, 1)
	end
	kit.Part(body, 18, 52, 64, 10, rgb(248, 248, 246), { Radius = 5, Z = 3, Shine = true })
	return nil
end

-- Portemanteau sur pied (manteau, écharpe, chapeau)
Art.CoatRack = function(body, kit, _item)
	kit.Blob(body, 50, 97, 40, 7, WALNUT_DARK, { Z = 1 })
	for _, dx in ipairs({ -16, 16 }) do
		kit.Line(body, 50, 86, 50 + dx, 98, 3, WALNUT, 0, 1)
	end
	leg(kit, body, 50, 10, 94, 5, WALNUT, 2)
	for _, dx in ipairs({ -1, 1 }) do
		kit.Line(body, 50, 16, 50 + dx * 12, 10, 3, WALNUT, 0, 3)
		kit.Circle(body, 50 + dx * 12, 10, 5, 5, OAK, 0, 4)
	end
	kit.Circle(body, 50, 8, 7, 7, OAK, 0, 4)
	-- manteau camel
	local coat = kit.Part(body, 32, 14, 22, 50, rgb(196, 150, 96), { Radius = 6, Z = 5, Shine = true })
	kit.Line(coat, 11, 2, 11, 48, 1.2, rgb(150, 110, 70), 0.2, 2)
	for i = 0, 2 do
		kit.Circle(coat, 14, 16 + i * 10, 2.4, 2.4, WALNUT_DARK, 0, 3)
	end
	-- écharpe rayée + chapeau
	local scarf = kit.Part(body, 54, 14, 8, 36, rgb(200, 60, 70), { Radius = 3, Z = 6 })
	for i = 0, 3 do
		kit.Box(scarf, 0, 5 + i * 8, 8, 2, WHITE, 0.2, 2)
	end
	kit.Blob(body, 66, 16, 24, 6, rgb(60, 60, 72), { Z = 6 })
	kit.Part(body, 59, 4, 14, 12, rgb(60, 60, 72), { Radius = 5, Z = 7, Shine = true })
	kit.Box(body, 59, 11, 14, 2.5, rgb(170, 60, 60), 0, 8)
	return nil
end

-- Table d'appoint tonneau (métal peint, cerclages) : dessus en y = 30
Art.BarrelTable = function(body, kit, _item)
	local drum = kit.Part(body, 16, 32, 68, 66, rgb(48, 96, 120), { Radius = 10, Z = 1, Shine = true })
	kit.Gradient(drum, WHITE, rgb(170, 180, 190), 0)
	for _, y in ipairs({ 8, 30, 52 }) do
		kit.Box(drum, 0, y, 68, 3, rgb(34, 70, 90), 0, 2)
	end
	kit.Text(drum, "DOPA", 34, 42, 10, rgb(240, 220, 170), 3)
	kit.Part(body, 12, 26, 76, 8, OAK, { Radius = 4, Z = 2, Shine = true })
	return nil
end

-- Tabouret de bar moderne (pied tulipe, assise cuir) : dessus en y = 30
Art.ModernBarStool = function(body, kit, _item)
	kit.Blob(body, 50, 96, 40, 8, STEEL_DARK, { Z = 1, Shine = true })
	leg(kit, body, 50, 36, 94, 6, STEEL, 2)
	kit.Blob(body, 50, 70, 30, 5, STEEL, { Z = 3 })
	kit.Part(body, 36, 34, 28, 5, STEEL_DARK, { Radius = 2, Z = 3 })
	kit.Part(body, 28, 8, 44, 14, LEATHER, { Radius = 7, Z = 3, Shine = true })
	kit.Part(body, 26, 24, 48, 10, LEATHER, { Radius = 5, Z = 4, Shine = true })
	return nil
end

-- Bureau minimaliste en chêne (pieds épingles, tiroir fin) : dessus en y = 42
Art.OakDesk = function(body, kit, _item)
	for _, x in ipairs({ 8, 92 }) do
		kit.Line(body, x, 46, x - (x < 50 and -3 or 3), 99, 3, IRON, 0, 1)
		kit.Line(body, x + (x < 50 and 8 or -8), 46, x - (x < 50 and -3 or 3), 99, 3, IRON, 0, 1)
	end
	local drawer = kit.Part(body, 52, 46, 36, 9, OAK_DARK, { Radius = 2, Z = 2 })
	kit.Box(drawer, 13, 4, 10, 1.6, IRON_DARK, 0, 2)
	kit.Part(body, 1, 40, 98, 7, OAK, { Radius = 3, Z = 3, Shine = true })
	kit.Box(body, 6, 41.5, 60, 1.2, WHITE, 0.55, 4)
	return nil
end

-- Meuble média en noyer (portes cannées, pieds compas) : dessus en y = 60
Art.MediaConsole = function(body, kit, _item)
	for _, x in ipairs({ 10, 90 }) do
		kit.Line(body, x, 88, x + (x < 50 and -4 or 4), 99, 3, WALNUT_DARK, 0, 1)
	end
	local case = kit.Part(body, 2, 60, 96, 30, WALNUT, { Radius = 4, Z = 2, Shine = true })
	for index = 0, 2 do
		local door = kit.Part(case, 3 + index * 30.6, 3, 29, 24, kit.Lighten(WALNUT, 0.08), { Radius = 2, Z = 2, Thickness = 1.2 })
		-- cannage (lignes croisées)
		for k = 0, 4 do
			kit.Box(door, 3, 3 + k * 4.4, 23, 1, rgb(214, 186, 140), 0.35, 2)
		end
		kit.Box(door, index == 1 and 25 or 2, 9, 1.8, 6, rgb(210, 180, 110), 0, 3)
	end
	kit.Part(body, 1, 57, 98, 5, WALNUT_DARK, { Radius = 2, Z = 3 })
	return nil
end

-- Table basse en verre (plateau fumé, piètement acier) : dessus en y = 62
Art.GlassCoffeeTable = function(body, kit, _item)
	for _, x in ipairs({ 10, 90 }) do
		kit.Part(body, x - 3, 64, 6, 34, STEEL, { Radius = 2, Z = 1, Shine = true })
	end
	kit.Part(body, 8, 94, 84, 4, STEEL_DARK, { Radius = 2, Z = 1 })
	local shelf = kit.Part(body, 10, 80, 80, 4, GLASS, { Radius = 2, Z = 2, T = 0.35 })
	local _ = shelf
	-- livres + plateau décoratif sur l'étagère du bas
	kit.Part(body, 22, 74, 20, 6, rgb(60, 96, 150), { Radius = 1, Z = 3 })
	kit.Part(body, 24, 70, 16, 4, rgb(236, 226, 206), { Radius = 1, Z = 4 })
	local top = kit.Part(body, 1, 60, 98, 6, rgb(170, 214, 228), { Radius = 3, Z = 4, T = 0.2, Shine = true })
	kit.Box(top, 6, 1, 50, 1.2, WHITE, 0.3, 2)
	return nil
end

-- Étagère industrielle en tubes noirs + planches brutes (4 niveaux)
Art.LoftShelf = function(body, kit, _item)
	for _, x in ipairs({ 8, 92 }) do
		kit.Part(body, x - 2.5, 4, 5, 96, IRON_DARK, { Radius = 2, Z = 3, Shine = true })
		for _, y in ipairs({ 8, 34, 60, 86 }) do
			kit.Circle(body, x, y + 3, 7, 7, IRON, 0, 4)
		end
	end
	for index, y in ipairs({ 8, 34, 60, 86 }) do
		local plank = kit.Part(body, 4, y, 92, 6, rgb(176, 130, 88), { Radius = 1, Z = 2, Shine = true })
		kit.Box(plank, 20, 2.5, 30, 0.8, WALNUT, 0.5, 2)
		kit.Box(plank, 60, 1.6, 22, 0.8, WALNUT, 0.5, 2)
		if index == 2 then
			books(kit, body, 14, 50, 34, 20, 3, 1)
			kit.Part(body, 62, 22, 14, 12, TERRACOTTA, { Radius = 4, Z = 1 })
			leaf(kit, body, 66, 16, 8, 12, LEAF, -20, 1)
			leaf(kit, body, 72, 15, 8, 12, LEAF_DARK, 20, 1)
		elseif index == 3 then
			kit.Part(body, 16, 46, 22, 14, rgb(120, 118, 114), { Radius = 3, Z = 1 }) -- boîte en métal
			books(kit, body, 46, 86, 60, 20, 11, 1)
		elseif index == 4 then
			kit.Part(body, 20, 72, 26, 14, rgb(200, 170, 120), { Radius = 3, Z = 1 }) -- panier
			kit.Box(body, 22, 76, 22, 1.2, rgb(160, 120, 80), 0, 2)
			kit.Circle(body, 70, 80, 14, 12, rgb(90, 90, 96), 0, 1) -- globe industriel
		end
	end
	return nil
end

-- Lit plateforme bas (vue de profil, tête de lit capitonnée) : dessus y = 70
Art.PlatformBed = function(body, kit, _item)
	kit.Part(body, 2, 36, 12, 52, GREIGE, { Radius = 5, Z = 1, Shine = true })
	for k = 0, 2 do
		kit.Box(body, 4, 42 + k * 14, 8, 1.2, kit.Darken(GREIGE, 0.2), 0, 2)
	end
	kit.Part(body, 4, 84, 94, 12, OAK, { Radius = 3, Z = 2, Shine = true })
	kit.Box(body, 10, 96, 84, 3, OAK_DARK, 0, 1)
	kit.Part(body, 8, 72, 88, 14, WHITE, { Radius = 5, Z = 3 })
	local duvet = kit.Part(body, 36, 68, 62, 18, rgb(124, 140, 150), { Radius = 6, Z = 4, Shine = true })
	kit.Box(duvet, 0, 2, 10, 14, rgb(210, 214, 216), 0, 2)
	kit.Blob(body, 24, 68, 22, 12, WHITE, { Z = 5, Shine = true })
	kit.Blob(body, 26, 64, 16, 10, rgb(214, 196, 170), { Z = 6 })
	return nil
end

-- Table d'atelier loft (plateau massif, tréteaux acier, étau) : dessus y = 40
Art.Workbench = function(body, kit, _item)
	for _, x in ipairs({ 14, 86 }) do
		kit.Line(body, x - 8, 99, x, 44, 4, IRON, 0, 1)
		kit.Line(body, x + 8, 99, x, 44, 4, IRON, 0, 1)
	end
	kit.Part(body, 8, 76, 84, 5, IRON_DARK, { Radius = 2, Z = 2 })
	-- caisse à outils sur la barre
	kit.Part(body, 60, 64, 22, 12, RED, { Radius = 3, Z = 3, Shine = true })
	kit.Part(body, 66, 60, 10, 5, IRON, { Radius = 2, Z = 2 })
	local top = kit.Part(body, 1, 38, 98, 9, rgb(186, 140, 94), { Radius = 2, Z = 4, Shine = true })
	for k = 1, 5 do
		kit.Box(top, k * 16, 0, 0.8, 9, rgb(150, 106, 70), 0.3, 2)
	end
	return nil
end

-- Canapé d'angle moderne (tissu gris chiné, pieds bois) : dessus y = 64
Art.SectionalSofa = function(body, kit, _item)
	local fabric = rgb(150, 156, 164)
	for _, x in ipairs({ 8, 50, 92 }) do
		kit.Part(body, x - 2, 92, 4, 8, WALNUT, { Radius = 1, Z = 1 })
	end
	kit.Part(body, 2, 36, 96, 34, kit.Darken(fabric, 0.1), { Radius = 8, Z = 2 })
	-- dossiers (3 coussins)
	for index = 0, 2 do
		kit.Part(body, 6 + index * 30, 30, 30, 32, fabric, { Radius = 9, Z = 3, Shine = true })
	end
	-- méridienne à droite (plus avancée)
	kit.Part(body, 2, 62, 96, 30, kit.Darken(fabric, 0.05), { Radius = 8, Z = 4 })
	for index = 0, 2 do
		kit.Part(body, 6 + index * 30, 60, 30, 12, kit.Lighten(fabric, 0.08), { Radius = 6, Z = 5, Shine = true })
	end
	kit.Part(body, 66, 64, 32, 28, fabric, { Radius = 8, Z = 6, Shine = true })
	-- coussins déco
	kit.Part(body, 10, 44, 18, 16, rgb(214, 170, 90), { Radius = 5, Z = 6, Rotation = -8 })
	kit.Part(body, 26, 46, 16, 14, LINEN, { Radius = 5, Z = 6, Rotation = 6 })
	return nil
end

-- Canapé Chesterfield (cuir, capitons, accoudoirs roulés) : dessus y = 62
Art.Chesterfield = function(body, kit, _item)
	for _, x in ipairs({ 10, 90 }) do
		kit.Circle(body, x, 95, 6, 8, WALNUT_DARK, 0, 1)
	end
	local back = kit.Part(body, 8, 26, 84, 40, LEATHER, { Radius = 10, Z = 2, Shine = true })
	for row = 0, 2 do
		for col = 0, 6 do
			kit.Circle(back, 8 + col * 11.5 + (row % 2) * 5.5, 8 + row * 10, 2.4, 2.4, LEATHER_DARK, 0, 2)
		end
	end
	kit.Part(body, 10, 60, 80, 32, LEATHER_DARK, { Radius = 8, Z = 3 })
	kit.Part(body, 12, 58, 38, 14, LEATHER, { Radius = 6, Z = 4, Shine = true })
	kit.Part(body, 50, 58, 38, 14, LEATHER, { Radius = 6, Z = 4, Shine = true })
	for _, x in ipairs({ 2, 82 }) do
		local arm = kit.Part(body, x, 42, 16, 50, LEATHER, { Radius = 8, Z = 5, Shine = true })
		kit.Blob(arm, 8, 7, 18, 14, kit.Lighten(LEATHER, 0.1), { Z = 2 })
		for k = 0, 3 do
			kit.Circle(arm, 8, 18 + k * 8, 2, 2, LEATHER_DARK, 0, 3)
		end
	end
	return nil
end

-- Mur de bibliothèque (noyer, 4 niveaux, échelle) : dessus + 3 rayons
Art.BookshelfWall = function(body, kit, _item)
	local frame = kit.Part(body, 2, 2, 96, 98, WALNUT, { Radius = 3, Z = 1, Shine = true })
	kit.Box(frame, 4, 4, 88, 90, WALNUT_DARK, 0, 2)
	for _, y in ipairs({ 28, 52, 76 }) do
		kit.Part(body, 4, y, 92, 4, WALNUT, { Radius = 1, Z = 3 })
	end
	kit.Part(body, 48, 6, 4, 92, WALNUT, { Radius = 1, Z = 3 })
	books(kit, body, 7, 46, 28, 20, 1, 4)
	books(kit, body, 55, 94, 28, 20, 5, 4)
	books(kit, body, 7, 34, 52, 19, 9, 4)
	kit.Blob(body, 40, 48, 8, 8, rgb(230, 200, 120), { Z = 4 }) -- globe doré
	books(kit, body, 55, 94, 52, 19, 2, 4)
	books(kit, body, 7, 46, 76, 20, 6, 4)
	books(kit, body, 55, 80, 76, 20, 4, 4)
	kit.Part(body, 82, 66, 10, 10, CERAMIC, { Radius = 4, Z = 4 })
	books(kit, body, 7, 46, 97, 18, 8, 4)
	books(kit, body, 55, 94, 97, 18, 12, 4)
	-- échelle de bibliothèque sur son rail
	kit.Box(body, 4, 8, 92, 2, rgb(210, 180, 110), 0, 5)
	for _, dx in ipairs({ 0, 12 }) do
		kit.Line(body, 62 + dx, 8, 70 + dx, 100, 2.4, rgb(210, 180, 110), 0, 6)
	end
	for k = 1, 6 do
		local t = k / 7
		kit.Line(body, 62 + 8 * t, 8 + 92 * t, 74 + 8 * t, 8 + 92 * t, 2, rgb(210, 180, 110), 0, 6)
	end
	return nil
end

-- Îlot de cuisine en marbre (plateau veiné, façade bois, tabourets) : dessus y = 40
Art.MarbleIsland = function(body, kit, _item)
	local base = kit.Part(body, 4, 44, 92, 54, rgb(66, 84, 96), { Radius = 3, Z = 1, Shine = true })
	for index = 0, 3 do
		local door = kit.Part(base, 3 + index * 22, 4, 20, 46, rgb(78, 98, 112), { Radius = 2, Z = 2, Thickness = 1.1 })
		kit.Box(door, 8, 4, 4, 1.6, rgb(210, 180, 110), 0, 2)
	end
	local top = kit.Part(body, 1, 38, 98, 8, MARBLE, { Radius = 2, Z = 3, Shine = true })
	kit.Line(top, 10, 2, 40, 6, 1, MARBLE_VEIN, 0.2, 2)
	kit.Line(top, 50, 6, 80, 1, 1, MARBLE_VEIN, 0.3, 2)
	-- corbeille de fruits + planche
	kit.Part(body, 60, 34, 24, 4, OAK, { Radius = 2, Z = 4 })
	for index, c in ipairs({ ORANGE, rgb(120, 190, 80), RED }) do
		kit.Circle(body, 18 + index * 7, 33, 8, 8, c, 0, 4)
	end
	return nil
end

----------------------------------------------------------------------
-- 🖼️ Déco
----------------------------------------------------------------------

-- Miroir mural rond (cadre laiton, reflet)
Art.RoundMirror = function(body, kit, _item)
	kit.Line(body, 50, 2, 50, 12, 1.4, rgb(150, 120, 70), 0, 1)
	kit.Circle(body, 50, 54, 86, 86, rgb(212, 176, 96), 0, 2)
	local glass = kit.Circle(body, 50, 54, 76, 76, rgb(206, 226, 234), 0, 3)
	kit.Gradient(glass, WHITE, rgb(170, 196, 214), 135)
	kit.Line(glass, 18, 26, 40, 8, 5, WHITE, 0.45, 2)
	kit.Line(glass, 26, 38, 54, 14, 3, WHITE, 0.6, 2)
	return { WallShadow = Vector2.new(84, 84) }
end

-- Toile abstraite (formes de couleur, style galerie)
Art.AbstractCanvas = function(body, kit, _item)
	local canvas = kit.Part(body, 8, 12, 84, 76, rgb(246, 242, 234), { Radius = 1, Z = 1, Outline = rgb(60, 56, 60), Thickness = 2 })
	local clip = kit.Group(canvas, 3, 3, 78, 70, 2, true)
	kit.Circle(clip, 26, 28, 40, 40, rgb(236, 120, 70), 0, 1)
	kit.Box(clip, 42, 8, 30, 50, rgb(40, 70, 120), 0, 2)
	kit.Circle(clip, 60, 60, 28, 28, rgb(240, 200, 80), 0, 3)
	kit.Line(clip, 6, 62, 70, 20, 3, rgb(30, 30, 36), 0, 4)
	kit.Box(clip, 8, 50, 22, 14, rgb(230, 170, 170), 0, 2)
	return { WallShadow = Vector2.new(84, 76) }
end

-- Horloge de parquet (noyer, cadran, balancier doré qui oscille)
Art.GrandfatherClock = function(body, kit, _item)
	kit.Part(body, 26, 86, 48, 14, WALNUT_DARK, { Radius = 3, Z = 1 })
	local case = kit.Part(body, 30, 30, 40, 60, WALNUT, { Radius = 3, Z = 2, Shine = true })
	local window = kit.Part(case, 8, 6, 24, 46, rgb(40, 28, 22), { Radius = 10, Z = 2, Outline = rgb(210, 180, 110), Thickness = 1.6 })
	local swing = kit.Pivot(window, 12, 2, 3)
	kit.Box(swing, -1, 0, 2, 30, rgb(220, 186, 100), 0, 1)
	kit.Circle(swing, 0, 32, 10, 10, rgb(240, 200, 100), 0, 2)
	kit.Animate(swing, "Sway", 14, 1.4, 0)
	kit.Line(window, 7, 2, 7, 30, 1, rgb(200, 170, 100), 0.2, 2)
	kit.Line(window, 17, 2, 17, 26, 1, rgb(200, 170, 100), 0.2, 2)
	-- tête + cadran
	kit.Part(body, 26, 4, 48, 30, WALNUT, { Radius = 12, Z = 3, Shine = true })
	kit.Part(body, 24, 2, 52, 6, WALNUT_DARK, { Radius = 3, Z = 4 })
	local dial = kit.Circle(body, 50, 20, 22, 22, rgb(250, 244, 226), 0, 4)
	kit.Stroke(dial, rgb(210, 180, 110), 2, 0)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		kit.Circle(dial, 11 + math.sin(a) * 8, 11 - math.cos(a) * 8, 1.4, 1.4, rgb(60, 50, 50), 0, 2)
	end
	kit.Line(dial, 11, 11, 11, 5, 1.4, rgb(40, 36, 40), 0, 3)
	kit.Line(dial, 11, 11, 15, 13, 1.4, rgb(40, 36, 40), 0, 3)
	return nil
end

----------------------------------------------------------------------
-- 💡 Lumières
----------------------------------------------------------------------

-- Suspension : 3 ampoules Edison à filament au bout de leurs fils
Art.EdisonPendant = function(body, kit, _item)
	kit.Part(body, 22, 2, 56, 6, IRON_DARK, { Radius = 3, Z = 1 })
	local bulbs = {}
	for index, spec in ipairs({ { 30, 52 }, { 50, 70 }, { 70, 44 } }) do
		local x, y = spec[1], spec[2]
		kit.Line(body, x, 6, x, y - 12, 1.4, IRON_DARK, 0, 1)
		kit.Part(body, x - 3.5, y - 14, 7, 7, rgb(170, 140, 90), { Radius = 2, Z = 2 })
		local halo = kit.Circle(body, x, y, 30, 30, AMBER, 0.72, 1)
		local bulb = kit.Blob(body, x, y, 14, 18, rgb(255, 214, 150), { Z = 3, T = 0.1, Shine = true })
		kit.Line(bulb, 4, 6, 7, 12, 1, ORANGE, 0, 2)
		kit.Line(bulb, 10, 6, 7, 12, 1, ORANGE, 0, 2)
		kit.Animate(halo, "Pulse", 0.2, 1, index)
		table.insert(bulbs, bulb)
		table.insert(bulbs, halo)
	end
	return { Glow = AMBER, Bulbs = bulbs, WallShadow = Vector2.new(0, 0) }
end

-- Lampadaire arc (grand arc chromé, abat-jour dôme, socle marbre)
Art.ArcFloorLamp = function(body, kit, _item)
	kit.Part(body, 4, 88, 26, 12, MARBLE, { Radius = 3, Z = 2, Shine = true })
	kit.Line(body, 17, 88, 17, 40, 3, STEEL, 0, 1)
	kit.Line(body, 17, 40, 34, 14, 3, STEEL, 0, 1)
	kit.Line(body, 34, 14, 58, 6, 3, STEEL, 0, 1)
	kit.Line(body, 58, 6, 78, 14, 3, STEEL, 0, 1)
	kit.Line(body, 78, 14, 84, 28, 3, STEEL, 0, 1)
	local halo = kit.Circle(body, 84, 44, 44, 34, AMBER, 0.75, 1)
	kit.Animate(halo, "Pulse", 0.15, 1, 0)
	kit.Part(body, 70, 26, 28, 14, STEEL, { Radius = 14, Z = 3, Shine = true })
	kit.Blob(body, 84, 40, 16, 6, rgb(255, 230, 170), { Z = 4, Outline = false })
	return { Glow = AMBER }
end

-- Enseigne néon "DOPA" sur plaque de plexi
Art.DopaNeon = function(body, kit, _item)
	local plate = kit.Part(body, 4, 26, 92, 48, rgb(40, 36, 60), { Radius = 8, Z = 1, T = 0.25, Outline = rgb(120, 110, 160) })
	local _ = plate
	local glow = kit.Part(body, 8, 34, 84, 32, MAGENTA, { Radius = 10, Z = 1, T = 0.8, Outline = false, Shade = false })
	kit.Animate(glow, "Pulse", 0.15, 1.2, 0)
	local label = kit.Text(body, "DOPA", 50, 50, 30, rgb(255, 150, 230), 3)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = MAGENTA
	kit.Line(body, 14, 66, 86, 66, 2, CYAN, 0, 3)
	kit.Heart(body, 84, 34, 10, CYAN, 0, 4)
	return { Glow = MAGENTA, WallShadow = Vector2.new(0, 0) }
end

-- Miroir infini (cercles de LED qui s'enfoncent)
Art.InfinityMirror = function(body, kit, _item)
	kit.Circle(body, 50, 50, 88, 88, IRON_DARK, 0, 1)
	local colors = { CYAN, rgb(150, 110, 255), MAGENTA, rgb(150, 110, 255), CYAN, MAGENTA }
	for index = 0, 5 do
		local size = 78 - index * 12
		local ring = kit.Circle(body, 50, 50, size, size, rgb(16, 16, 30), 0, 2 + index)
		kit.Stroke(ring, colors[index + 1], 2.4 - index * 0.25, index * 0.12)
		kit.Animate(ring, "Breathe", 0.02, 1, index * 0.4)
	end
	kit.Shine(body, 20, 20, 14, 5, 9, 0.6)
	return { Glow = rgb(150, 110, 255), WallShadow = Vector2.new(88, 88) }
end

----------------------------------------------------------------------
-- 🪴 Plantes
----------------------------------------------------------------------

-- Sansevieria (feuilles droites bordées de jaune, pot béton)
Art.SnakePlant = function(body, kit, _item)
	local specs = { { 38, -10, 60 }, { 46, -4, 76 }, { 54, 3, 70 }, { 62, 12, 56 }, { 50, 0, 50 } }
	for index, s in ipairs(specs) do
		local l = kit.Part(body, s[1] - 5, 70 - s[3], 10, s[3], index % 2 == 0 and LEAF_DARK or LEAF, { Radius = 5, Z = 1 + index % 3, Rotation = s[2] })
		kit.Stroke(l, rgb(210, 200, 90), 1.4, 0)
		for k = 1, 3 do
			kit.Box(l, 2, k * s[3] / 4, 6, 1.4, rgb(40, 90, 50), 0.4, 2)
		end
	end
	pot(kit, body, 50, 100, 42, 32, CONCRETE, 5)
	return nil
end

-- Ficus lyrata (grandes feuilles en violon, pot blanc)
Art.FiddleFig = function(body, kit, _item)
	kit.Line(body, 50, 74, 48, 30, 3, rgb(120, 90, 60), 0, 1)
	kit.Line(body, 49, 50, 38, 34, 2, rgb(120, 90, 60), 0, 1)
	kit.Line(body, 49, 44, 62, 24, 2, rgb(120, 90, 60), 0, 1)
	local spots = { { 36, 34, -30 }, { 30, 50, -60 }, { 62, 24, 30 }, { 68, 42, 60 }, { 48, 16, 0 }, { 40, 20, -20 }, { 58, 10, 15 },
		{ 56, 52, 40 }, { 38, 60, -45 } }
	for index, s in ipairs(spots) do
		leaf(kit, body, s[1], s[2], 18, 22, index % 3 == 0 and LEAF_LIGHT or (index % 2 == 0 and LEAF_DARK or LEAF), s[3], 2 + index % 3)
	end
	pot(kit, body, 50, 100, 36, 26, CERAMIC, 6)
	return nil
end

-- Oiseau de paradis (grandes feuilles bananier + fleurs orange/bleu)
Art.BirdOfParadise = function(body, kit, _item)
	for index, s in ipairs({ { 30, -24, 56 }, { 44, -8, 70 }, { 58, 10, 66 }, { 70, 26, 52 }, { 50, 2, 80 } }) do
		local l = kit.Part(body, s[1] - 8, 78 - s[3], 16, s[3] - 14, index % 2 == 0 and LEAF or LEAF_DARK, { Radius = 8, Z = 1 + index % 3, Rotation = s[2] })
		kit.Box(l, 7.4, 2, 1.2, s[3] - 18, LEAF_LIGHT, 0.2, 2)
	end
	-- 2 fleurs "bec d'oiseau"
	for _, spec in ipairs({ { 36, 30, -20 }, { 64, 24, 18 } }) do
		local g = kit.Pivot(body, spec[1], spec[2], 6)
		g.Rotation = spec[3]
		kit.Part(g, -10, -2, 20, 5, rgb(60, 110, 90), { Radius = 2, Z = 1 })
		kit.Triangle(g, 2, -12, 10, 12, ORANGE, 2)
		kit.Triangle(g, 6, -10, 7, 9, rgb(250, 190, 60), 3)
		kit.Triangle(g, -2, -8, 6, 8, rgb(80, 110, 220), 3)
	end
	pot(kit, body, 50, 100, 40, 24, rgb(60, 60, 64), 7)
	return nil
end

-- Bonsaï érable rouge (tronc tordu, feuillage rouge, coupe plate)
Art.MapleBonsai = function(body, kit, _item)
	kit.Part(body, 14, 84, 72, 12, rgb(70, 90, 110), { Radius = 3, Z = 5, Shine = true })
	kit.Part(body, 10, 80, 80, 6, rgb(90, 112, 132), { Radius = 3, Z = 6 })
	kit.Blob(body, 50, 80, 64, 6, rgb(110, 90, 70), { Z = 4, Outline = false })
	kit.Line(body, 46, 80, 40, 60, 6, rgb(110, 76, 56), 0, 1)
	kit.Line(body, 40, 60, 54, 44, 5, rgb(110, 76, 56), 0, 1)
	kit.Line(body, 54, 44, 44, 30, 4, rgb(110, 76, 56), 0, 1)
	kit.Line(body, 44, 58, 26, 52, 3, rgb(110, 76, 56), 0, 1)
	kit.Line(body, 52, 46, 72, 40, 3, rgb(110, 76, 56), 0, 1)
	local reds = { rgb(214, 60, 50), rgb(236, 96, 60), rgb(180, 40, 44), rgb(246, 130, 80) }
	for index, s in ipairs({ { 24, 46, 26 }, { 72, 36, 28 }, { 44, 24, 30 }, { 58, 30, 24 }, { 34, 34, 22 }, { 50, 14, 20 } }) do
		local c = kit.Blob(body, s[1], s[2], s[3], s[3] * 0.72, reds[(index % #reds) + 1], { Z = 2 + index % 2, Shine = index % 2 == 0 })
		kit.Animate(c, "Sway", 1.2, 0.6, index)
	end
	return nil
end

-- Olivier en pot (tronc noueux, feuillage argenté, olives)
Art.OliveTree = function(body, kit, _item)
	kit.Line(body, 50, 78, 46, 44, 7, rgb(128, 110, 90), 0, 1)
	kit.Line(body, 46, 50, 32, 30, 4, rgb(128, 110, 90), 0, 1)
	kit.Line(body, 47, 46, 64, 26, 4, rgb(128, 110, 90), 0, 1)
	local olive = rgb(134, 158, 110)
	for index, s in ipairs({ { 30, 26, 34 }, { 66, 22, 36 }, { 48, 14, 36 }, { 40, 38, 28 }, { 60, 38, 26 }, { 22, 40, 20 }, { 78, 36, 20 } }) do
		local c = kit.Blob(body, s[1], s[2], s[3], s[3] * 0.62, index % 2 == 0 and olive or rgb(164, 184, 140), { Z = 2 + index % 2 })
		if index % 3 == 1 then
			kit.Blob(c, s[3] * 0.3, s[3] * 0.44, 3, 4, rgb(80, 64, 96), { Z = 2, Outline = false })
		end
	end
	pot(kit, body, 50, 100, 46, 26, TERRACOTTA, 5)
	return nil
end

-- Mur de mousse végétal (cadre bois, coussins de mousse de 3 verts, fougères)
Art.MossWall = function(body, kit, _item)
	local frame = kit.Part(body, 4, 14, 92, 72, OAK_DARK, { Radius = 3, Z = 1, Shine = true })
	local clip = kit.Group(frame, 4, 4, 84, 64, 2, true)
	local greens = { rgb(90, 150, 70), rgb(60, 120, 60), rgb(130, 180, 90), rgb(76, 136, 80) }
	local n = 0
	for row = 0, 4 do
		for col = 0, 6 do
			n += 1
			kit.Circle(clip, col * 14 + (row % 2) * 7, row * 15 + 4, 22 + (n * 7) % 8, 20 + (n * 5) % 7, greens[(n % #greens) + 1], 0, 1 + n % 3)
		end
	end
	for index, s in ipairs({ { 20, 20, -30 }, { 62, 40, 30 }, { 40, 52, -10 }, { 74, 16, 40 } }) do
		leaf(kit, clip, s[1], s[2], 10, 22, LEAF_LIGHT, s[3], 5 + index % 2)
	end
	return { WallShadow = Vector2.new(92, 72) }
end

----------------------------------------------------------------------
-- 📺 Tech
----------------------------------------------------------------------

-- Enceinte connectée (tissu gris, anneau lumineux bleu)
Art.SmartSpeaker = function(body, kit, _item)
	kit.Blob(body, 50, 96, 50, 8, rgb(80, 80, 90), { Z = 1, Outline = false, T = 0.5 })
	local speaker = kit.Part(body, 28, 34, 44, 64, rgb(96, 100, 112), { Radius = 20, Z = 2, Shine = true })
	for row = 0, 5 do
		for col = 0, 4 do
			kit.Circle(speaker, 8 + col * 7 + (row % 2) * 3.5, 22 + row * 7, 2.2, 2.2, rgb(70, 74, 86), 0, 2)
		end
	end
	kit.Part(body, 28, 30, 44, 10, rgb(40, 42, 52), { Radius = 5, Z = 3 })
	local ring = kit.Part(body, 32, 32, 36, 4, CYAN, { Radius = 2, Z = 4, Outline = false })
	kit.Animate(ring, "Pulse", 0.5, 1.4, 0)
	return { Glow = CYAN }
end

-- Drone caméra (4 hélices qui tournent, nacelle)
Art.CameraDrone = function(body, kit, _item)
	kit.Blob(body, 50, 96, 60, 6, rgb(90, 90, 100), { Z = 1, Outline = false, T = 0.6 })
	for _, dx in ipairs({ -1, 1 }) do
		kit.Line(body, 50, 60, 50 + dx * 32, 50, 4, IRON, 0, 2)
		kit.Line(body, 50 + dx * 14, 70, 50 + dx * 22, 86, 2, IRON, 0, 1) -- trains d'atterrissage
		local rotor = kit.Pivot(body, 50 + dx * 32, 46, 4)
		kit.Box(rotor, -16, -1.5, 32, 3, rgb(60, 60, 70), 0.2, 1)
		kit.Animate(rotor, "Spin", 1, 3, dx)
		kit.Circle(body, 50 + dx * 32, 48, 7, 5, IRON_DARK, 0, 3)
	end
	kit.Line(body, 34, 88, 44, 88, 2, IRON, 0, 1)
	kit.Line(body, 56, 88, 66, 88, 2, IRON, 0, 1)
	kit.Part(body, 32, 52, 36, 18, rgb(236, 238, 242), { Radius = 8, Z = 5, Shine = true })
	kit.Circle(body, 50, 76, 14, 14, IRON_DARK, 0, 5)
	local lens = kit.Circle(body, 50, 76, 8, 8, rgb(60, 100, 160), 0, 6)
	kit.Shine(lens, 1.5, 1.5, 3, 2, 3, 0.3)
	local led = kit.Circle(body, 38, 60, 3, 3, RED, 0, 6)
	kit.Animate(led, "Pulse", 0.8, 2, 0)
	return nil
end

-- Imprimante 3D (cadre, plateau, buse, objet en cours d'impression)
Art.Printer3D = function(body, kit, _item)
	kit.Part(body, 10, 84, 80, 14, IRON_DARK, { Radius = 3, Z = 1, Shine = true })
	local lcd = kit.Part(body, 16, 88, 20, 7, rgb(60, 140, 200), { Radius = 1, Z = 2, Outline = false })
	kit.Animate(lcd, "Pulse", 0.25, 1, 0)
	for _, x in ipairs({ 14, 82 }) do
		kit.Part(body, x, 12, 4, 74, IRON, { Radius = 1, Z = 2 })
	end
	kit.Part(body, 12, 8, 76, 6, IRON, { Radius = 2, Z = 3 })
	kit.Part(body, 20, 74, 60, 5, rgb(40, 40, 46), { Radius = 1, Z = 3 })
	-- objet imprimé (petit vase orange en couches)
	for k = 0, 5 do
		local w = 18 - math.abs(k - 3) * 2
		kit.Box(body, 50 - w / 2, 70 - k * 4, w, 4, k % 2 == 0 and ORANGE or rgb(236, 130, 50), 0, 4)
	end
	local head = kit.Part(body, 40, 32, 20, 12, rgb(220, 60, 60), { Radius = 3, Z = 5, Shine = true })
	kit.Animate(head, "Drift", 6, 1, 0)
	kit.Part(body, 16, 34, 68, 3, STEEL, { Radius = 1, Z = 4 })
	kit.Triangle(head, 10, 12, 5, 5, IRON_DARK, 2)
	-- bobine de filament
	kit.Circle(body, 86, 30, 16, 16, ORANGE, 0, 1)
	kit.Circle(body, 86, 30, 6, 6, IRON_DARK, 0, 2)
	return nil
end

-- Robot majordome (plateau, tête écran, roues)
Art.ButlerRobot = function(body, kit, _item)
	kit.Blob(body, 50, 96, 50, 8, rgb(120, 120, 130), { Z = 1, Outline = false, T = 0.5 })
	kit.Part(body, 32, 76, 36, 20, rgb(230, 234, 240), { Radius = 10, Z = 2, Shine = true })
	for _, x in ipairs({ 36, 64 }) do
		kit.Circle(body, x, 94, 10, 10, IRON_DARK, 0, 3)
	end
	local torso = kit.Part(body, 34, 36, 32, 42, rgb(240, 242, 246), { Radius = 12, Z = 3, Shine = true })
	kit.Circle(torso, 16, 22, 10, 10, CYAN, 0.2, 2)
	kit.Box(torso, 8, 32, 16, 2, SLATE, 0, 2) -- nœud papillon
	kit.Diamond(torso, 11, 33, 4, SLATE, 0, 3)
	kit.Diamond(torso, 21, 33, 4, SLATE, 0, 3)
	-- bras + plateau avec une tasse
	kit.Line(body, 34, 48, 18, 58, 5, STEEL, 0, 2)
	kit.Line(body, 66, 48, 82, 44, 5, STEEL, 0, 2)
	kit.Part(body, 70, 38, 28, 4, STEEL_DARK, { Radius = 2, Z = 4 })
	kit.Part(body, 78, 30, 10, 9, WHITE, { Radius = 3, Z = 5 })
	kit.Line(body, 84, 20, 84, 28, 1.2, WHITE, 0.4, 5)
	-- tête écran
	kit.Line(body, 50, 36, 50, 30, 4, STEEL, 0, 3)
	local head = kit.Part(body, 32, 8, 36, 24, rgb(236, 240, 244), { Radius = 10, Z = 4, Shine = true })
	local face = kit.Part(head, 5, 5, 26, 14, SCREEN, { Radius = 6, Z = 2, Outline = false })
	for _, x in ipairs({ 8, 18 }) do
		local eye = kit.Circle(face, x, 7, 5, 5, CYAN, 0, 2)
		kit.Animate(eye, "Blink", 1, 1, x)
	end
	kit.Line(body, 50, 8, 50, 2, 1.5, STEEL, 0, 3)
	local tip = kit.Circle(body, 50, 2, 4, 4, RED, 0, 4)
	kit.Animate(tip, "Pulse", 0.6, 1.5, 0)
	return nil
end

----------------------------------------------------------------------
-- 🍰 Cuisine
----------------------------------------------------------------------

-- Robot pâtissier (bol inox, tête inclinable, couleur crème)
Art.StandMixer = function(body, kit, _item)
	local cream = rgb(236, 210, 170)
	kit.Part(body, 18, 86, 64, 12, cream, { Radius = 6, Z = 1, Shine = true })
	kit.Part(body, 62, 36, 20, 54, cream, { Radius = 8, Z = 2, Shine = true })
	kit.Part(body, 22, 24, 64, 24, cream, { Radius = 12, Z = 3, Shine = true })
	kit.Box(body, 24, 40, 60, 2, rgb(200, 170, 130), 0, 4)
	kit.Circle(body, 74, 34, 6, 6, STEEL, 0, 4)
	kit.Line(body, 38, 48, 38, 62, 3, STEEL_DARK, 0, 2) -- fouet
	kit.Blob(body, 38, 64, 10, 14, STEEL, { Z = 2 })
	local bowl = kit.Part(body, 20, 62, 40, 26, STEEL, { Radius = 12, Z = 4, Shine = true })
	kit.Gradient(bowl, WHITE, rgb(150, 156, 170), 0)
	kit.Blob(body, 40, 62, 38, 6, rgb(250, 244, 230), { Z = 5 })
	return nil
end

-- Machine à expresso (inox, porte-filtre, tasse, vapeur)
Art.EspressoMachine = function(body, kit, _item)
	local case = kit.Part(body, 14, 24, 72, 74, STEEL, { Radius = 6, Z = 1, Shine = true })
	kit.Gradient(case, WHITE, rgb(150, 156, 170), 0)
	kit.Part(body, 12, 20, 76, 8, IRON, { Radius = 3, Z = 2 })
	-- 2 tasses au chaud sur le dessus
	kit.Part(body, 22, 12, 12, 9, WHITE, { Radius = 3, Z = 3 })
	kit.Part(body, 38, 12, 12, 9, WHITE, { Radius = 3, Z = 3 })
	-- manomètre
	local gauge = kit.Circle(body, 66, 40, 16, 16, rgb(250, 248, 240), 0, 3)
	kit.Stroke(gauge, IRON, 1.6, 0)
	kit.Line(gauge, 8, 8, 12, 4, 1.2, RED, 0, 2)
	-- groupe + porte-filtre
	kit.Part(body, 30, 36, 24, 10, IRON, { Radius = 3, Z = 3 })
	kit.Line(body, 42, 46, 18, 50, 4, IRON_DARK, 0, 3)
	kit.Part(body, 36, 44, 14, 6, STEEL_DARK, { Radius = 2, Z = 4 })
	-- tasse + café
	kit.Part(body, 34, 70, 16, 14, WHITE, { Radius = 4, Z = 4, Shine = true })
	kit.Box(body, 36, 70, 12, 2.4, rgb(110, 70, 40), 0, 5)
	kit.Line(body, 42, 50, 42, 70, 1.6, rgb(110, 70, 40), 0, 3)
	kit.Part(body, 22, 84, 56, 5, IRON_DARK, { Radius = 2, Z = 3 })
	for index = 0, 2 do
		local steam = kit.Circle(body, 70 + index * 4, 64 - index * 10, 7, 7, WHITE, 0.55, 5)
		kit.Animate(steam, "Bob", 2, 1, index)
	end
	return nil
end

-- Frigo américain inox (2 portes, distributeur d'eau) : dessus y = 3
Art.SteelFridge = function(body, kit, _item)
	local case = kit.Part(body, 8, 3, 84, 95, STEEL, { Radius = 5, Z = 1, Shine = true })
	kit.Gradient(case, WHITE, rgb(150, 156, 170), 0)
	kit.Box(case, 41.4, 2, 1.4, 90, STEEL_DARK, 0, 2)
	for _, x in ipairs({ 36, 48 }) do
		kit.Part(case, x - 1, 16, 3, 40, rgb(220, 224, 232), { Radius = 1, Z = 3 })
	end
	local panel = kit.Part(case, 12, 18, 18, 26, IRON_DARK, { Radius = 3, Z = 3 })
	kit.Part(panel, 5, 12, 8, 10, rgb(50, 60, 80), { Radius = 2, Z = 2 })
	local lcd = kit.Box(panel, 3, 3, 12, 5, CYAN, 0.2, 2)
	kit.Animate(lcd, "Pulse", 0.2, 1, 0)
	-- magnets + dessin d'enfant
	kit.Part(case, 54, 20, 18, 14, WHITE, { Radius = 1, Z = 3, Rotation = 5 })
	kit.Circle(case, 63, 19, 4, 4, RED, 0, 4)
	kit.Part(body, 10, 94, 80, 6, IRON, { Radius = 2, Z = 2 })
	return nil
end

----------------------------------------------------------------------
-- 🎮 Gamer
----------------------------------------------------------------------

-- Panneaux LED hexagonaux (nid d'abeille lumineux)
Art.HexPanels = function(body, kit, _item)
	local colors = { CYAN, rgb(150, 110, 255), MAGENTA, LIME, rgb(255, 180, 60), CYAN, MAGENTA }
	local spots = { { 30, 30 }, { 50, 20 }, { 70, 30 }, { 40, 50 }, { 60, 50 }, { 50, 70 }, { 80, 60 } }
	-- un hexagone = 3 rectangles (côté x côté*√3) tournés de 60° ; néon
	-- autour (grand hexagone de couleur), dalle sombre au centre
	local function hexagon(parent, side, color, transparency, z)
		for k = 0, 2 do
			local slab = kit.Box(parent, 0, 0, side, side * 1.732, color, transparency, z)
			slab.AnchorPoint = Vector2.new(0.5, 0.5)
			slab.Position = UDim2.fromOffset(0, 0)
			slab.Rotation = 30 + k * 60
		end
	end
	for index, s in ipairs(spots) do
		local hex = kit.Pivot(body, s[1], s[2], 1 + index)
		local color = colors[index]
		local halo = kit.Circle(hex, 0, 0, 30, 30, color, 0.78, 1)
		kit.Animate(halo, "Pulse", 0.2, 1.1, index * 0.7)
		local rim = kit.Pivot(hex, 0, 0, 2)
		hexagon(rim, 11.5, color, 0, 1)
		local core = kit.Pivot(hex, 0, 0, 3)
		hexagon(core, 9.2, rgb(26, 28, 44), 0, 1)
		local glow = kit.Pivot(hex, 0, 0, 4)
		hexagon(glow, 5, kit.Lighten(color, 0.35), 0.35, 1)
	end
	return { Glow = CYAN, WallShadow = Vector2.new(0, 0) }
end

-- Baby-foot (joueurs rouges et bleus sur leurs barres)
Art.FoosballTable = function(body, kit, _item)
	for _, x in ipairs({ 12, 88 }) do
		kit.Part(body, x - 4, 60, 8, 38, WALNUT_DARK, { Radius = 2, Z = 1 })
		kit.Part(body, x - 7, 94, 14, 5, IRON, { Radius = 2, Z = 1 })
	end
	local box = kit.Part(body, 4, 34, 92, 30, WALNUT, { Radius = 4, Z = 2, Shine = true })
	kit.Box(box, 4, 4, 84, 8, GREEN_FELT, 0, 2)
	kit.Box(box, 43, 4, 1, 8, WHITE, 0.3, 3)
	for index = 0, 5 do
		local x = 14 + index * 14
		kit.Line(body, x, 28, x, 40, 3, STEEL, 0, 3) -- barres (vues de face : poignées)
		local color = index % 2 == 0 and RED or BLUE
		local player = kit.Part(body, x - 3, 30, 6, 12, color, { Radius = 3, Z = 4 })
		kit.Circle(player, 3, 1, 6, 6, rgb(240, 210, 180), 0, 2)
		kit.Animate(player, "Sway", 6, 1.3, index)
	end
	kit.Part(body, 0, 38, 6, 6, IRON_DARK, { Radius = 3, Z = 5 })
	kit.Part(body, 94, 38, 6, 6, IRON_DARK, { Radius = 3, Z = 5 })
	kit.Circle(body, 50, 40, 5, 5, WHITE, 0, 5)
	return nil
end

-- Table de air hockey (bords néon, palets, maillets) : table plate
Art.AirHockey = function(body, kit, _item)
	for _, x in ipairs({ 12, 88 }) do
		kit.Part(body, x - 5, 58, 10, 40, IRON_DARK, { Radius = 2, Z = 1 })
	end
	kit.Part(body, 6, 70, 88, 6, IRON, { Radius = 2, Z = 1 })
	local table_ = kit.Part(body, 2, 40, 96, 22, rgb(36, 40, 70), { Radius = 5, Z = 2, Shine = true })
	kit.Stroke(table_, CYAN, 2, 0)
	local surface = kit.Part(body, 6, 36, 88, 8, rgb(230, 240, 250), { Radius = 3, Z = 3 })
	kit.Box(surface, 43, 0, 2, 8, RED, 0.3, 2)
	kit.Blob(body, 26, 36, 12, 6, RED, { Z = 4, Shine = true })
	kit.Blob(body, 76, 36, 12, 6, BLUE, { Z = 4, Shine = true })
	kit.Part(body, 23, 28, 6, 8, RED, { Radius = 3, Z = 5 })
	kit.Part(body, 73, 28, 6, 8, BLUE, { Radius = 3, Z = 5 })
	local puck = kit.Blob(body, 50, 38, 8, 4, IRON_DARK, { Z = 5 })
	kit.Animate(puck, "Drift", 12, 1.6, 0)
	local strip = kit.Box(body, 8, 58, 84, 2, MAGENTA, 0, 3)
	kit.Animate(strip, "Pulse", 0.4, 1.4, 0)
	-- tableau des scores
	local score = kit.Part(body, 30, 6, 40, 14, IRON_DARK, { Radius = 3, Z = 2 })
	kit.Text(score, "3 : 2", 20, 7, 10, LIME, 2)
	kit.Line(body, 50, 20, 50, 40, 2, IRON, 0, 1)
	return { Glow = CYAN }
end

-- Machine à pince (vitrine de peluches, pince qui se balance)
Art.ClawMachine = function(body, kit, _item)
	kit.Part(body, 18, 64, 64, 36, rgb(236, 72, 140), { Radius = 5, Z = 1, Shine = true })
	kit.Part(body, 22, 70, 36, 12, IRON_DARK, { Radius = 3, Z = 2 })
	kit.Circle(body, 30, 76, 6, 6, RED, 0, 3) -- bouton
	kit.Line(body, 44, 80, 44, 70, 3, IRON, 0, 3) -- joystick
	kit.Circle(body, 44, 69, 7, 7, RED, 0, 4)
	kit.Part(body, 64, 72, 12, 18, IRON_DARK, { Radius = 2, Z = 2 }) -- trappe
	local glass = kit.Part(body, 20, 18, 60, 48, rgb(200, 230, 250), { Radius = 3, Z = 2, T = 0.45 })
	kit.Stroke(glass, rgb(236, 72, 140), 3, 0)
	-- peluches entassées
	for index, s in ipairs({ { 28, 58, rgb(255, 200, 80) }, { 40, 60, rgb(140, 200, 255) }, { 54, 58, rgb(255, 150, 190) }, { 68, 60, rgb(150, 220, 150) },
		{ 34, 50, rgb(200, 160, 255) }, { 60, 50, rgb(255, 170, 120) } }) do
		kit.Blob(body, s[1], s[2], 14, 12, s[3], { Z = 3, Thickness = 1 })
		local _ = index
	end
	local claw = kit.Pivot(body, 52, 22, 5)
	kit.Box(claw, -0.6, 0, 1.2, 16, STEEL, 0, 1)
	kit.Part(claw, -5, 14, 10, 5, STEEL_DARK, { Radius = 2, Z = 2 })
	kit.Line(claw, -4, 19, -7, 26, 1.6, STEEL, 0, 1)
	kit.Line(claw, 4, 19, 7, 26, 1.6, STEEL, 0, 1)
	kit.Animate(claw, "Sway", 8, 1, 0)
	local sign = kit.Part(body, 16, 2, 68, 18, rgb(255, 214, 90), { Radius = 6, Z = 3, Shine = true })
	kit.Text(sign, "CLAW", 34, 9, 12, rgb(200, 40, 100), 2)
	return { Glow = rgb(255, 150, 200) }
end

----------------------------------------------------------------------
-- 🏀 Sport
----------------------------------------------------------------------

-- Tapis de yoga roulé à moitié + ballon de gym + haltères
Art.YogaMat = function(body, kit, _item)
	local mat = kit.Part(body, 4, 88, 70, 8, rgb(120, 180, 170), { Radius = 3, Z = 1, Shine = true })
	kit.Box(mat, 4, 2, 60, 1.2, WHITE, 0.6, 2)
	kit.Circle(body, 76, 88, 16, 16, rgb(120, 180, 170), 0, 2)
	kit.Circle(body, 76, 88, 8, 8, rgb(90, 150, 140), 0, 3)
	local ball = kit.Circle(body, 34, 62, 44, 44, rgb(150, 120, 220), 0, 3)
	kit.Stroke(ball, rgb(110, 84, 180), 1.4, 0)
	kit.Shine(ball, 8, 8, 14, 7, 3, 0.5)
	kit.Line(ball, 6, 22, 38, 22, 1.2, rgb(120, 96, 190), 0.4, 2)
	for _, x in ipairs({ 80, 92 }) do
		kit.Part(body, x - 4, 70, 8, 8, rgb(230, 80, 110), { Radius = 3, Z = 4 })
		kit.Part(body, x - 4, 50, 8, 8, rgb(230, 80, 110), { Radius = 3, Z = 4 })
		kit.Line(body, x, 58, x, 70, 3, STEEL, 0, 3)
	end
	return nil
end

-- Table de ping-pong (bleue, filet, raquettes, balle)
Art.PingPongTable = function(body, kit, _item)
	for _, x in ipairs({ 10, 90 }) do
		kit.Part(body, x - 3, 56, 6, 42, IRON, { Radius = 2, Z = 1 })
		kit.Circle(body, x, 97, 8, 5, IRON_DARK, 0, 2)
	end
	kit.Line(body, 14, 90, 86, 90, 3, IRON, 0, 1)
	local top = kit.Part(body, 1, 50, 98, 8, rgb(40, 90, 170), { Radius = 2, Z = 3, Shine = true })
	kit.Box(top, 1, 0, 96, 1.2, WHITE, 0, 2)
	kit.Box(top, 48.4, 0, 1.2, 8, WHITE, 0, 2)
	kit.Part(body, 48, 38, 3, 14, IRON_DARK, { Radius = 1, Z = 4 })
	local net = kit.Part(body, 36, 38, 28, 12, WHITE, { Radius = 1, Z = 4, T = 0.35, Outline = rgb(90, 90, 100) })
	for k = 1, 4 do
		kit.Box(net, k * 5.6, 0, 0.8, 12, rgb(120, 120, 130), 0.3, 2)
	end
	-- raquettes + balle
	for _, spec in ipairs({ { 20, RED, -20 }, { 78, rgb(30, 30, 36), 20 } }) do
		local p = kit.Pivot(body, spec[1], 44, 5)
		p.Rotation = spec[3]
		kit.Blob(p, 0, 0, 14, 12, spec[2], { Z = 1 })
		kit.Part(p, -1.5, 5, 3, 9, WALNUT, { Radius = 1, Z = 1 })
	end
	local ball = kit.Circle(body, 60, 30, 4, 4, rgb(255, 170, 60), 0, 6)
	kit.Animate(ball, "Bob", 5, 1.8, 0)
	return nil
end

-- Rameur (rail, siège coulissant, volant ventilé, écran)
Art.RowingMachine = function(body, kit, _item)
	kit.Part(body, 6, 82, 88, 6, IRON, { Radius = 3, Z = 1, Shine = true })
	kit.Part(body, 4, 90, 12, 8, IRON_DARK, { Radius = 2, Z = 1 })
	kit.Part(body, 84, 90, 12, 8, IRON_DARK, { Radius = 2, Z = 1 })
	local seat = kit.Part(body, 48, 70, 22, 10, rgb(40, 40, 46), { Radius = 4, Z = 3, Shine = true })
	kit.Animate(seat, "Drift", 10, 1, 0)
	-- volant + carter
	local wheel = kit.Circle(body, 18, 68, 30, 30, rgb(60, 62, 72), 0, 2)
	kit.Stroke(wheel, rgb(230, 70, 80), 2, 0)
	local fan = kit.Pivot(wheel, 15, 15, 2)
	for k = 0, 3 do
		local arm = kit.Pivot(fan, 0, 0, 1)
		arm.Rotation = k * 45
		kit.Box(arm, -1, -12, 2, 24, rgb(120, 124, 136), 0, 1)
	end
	kit.Animate(fan, "Spin", 1, 1.2, 0)
	kit.Line(body, 20, 64, 32, 46, 3, IRON, 0, 3)
	kit.Part(body, 26, 36, 16, 12, SCREEN, { Radius = 2, Z = 4, Outline = IRON_DARK })
	kit.Text(body, "500m", 34, 42, 7, LIME, 5)
	-- poignée + repose-pieds
	kit.Line(body, 30, 62, 42, 56, 2, IRON_DARK, 0, 4)
	kit.Part(body, 40, 52, 6, 8, rgb(40, 40, 46), { Radius = 2, Z = 5 })
	kit.Part(body, 34, 74, 10, 8, rgb(230, 70, 80), { Radius = 2, Z = 4 })
	return nil
end

-- Banc de musculation + rack + barre chargée
Art.WeightBench = function(body, kit, _item)
	-- rack
	for _, x in ipairs({ 14, 86 }) do
		kit.Part(body, x - 3, 18, 6, 80, IRON, { Radius = 1, Z = 1 })
		kit.Part(body, x - 8, 94, 16, 5, IRON_DARK, { Radius = 2, Z = 1 })
		kit.Part(body, x - 5, 38, 10, 4, IRON_DARK, { Radius = 1, Z = 2 })
	end
	kit.Line(body, 4, 36, 96, 36, 3, STEEL, 0, 3)
	for _, x in ipairs({ 8, 92 }) do
		kit.Part(body, x - 3, 22, 6, 28, rgb(40, 40, 46), { Radius = 3, Z = 4 })
		kit.Part(body, x + (x < 50 and 3 or -7), 26, 4, 20, RED, { Radius = 2, Z = 4 })
	end
	-- banc
	kit.Part(body, 46, 72, 8, 26, IRON_DARK, { Radius = 2, Z = 3 })
	kit.Part(body, 30, 94, 40, 5, IRON_DARK, { Radius = 2, Z = 3 })
	kit.Part(body, 24, 62, 52, 10, rgb(40, 40, 46), { Radius = 5, Z = 4, Shine = true })
	kit.Box(body, 28, 63, 44, 1.4, RED, 0.2, 5)
	-- haltères au sol
	kit.Part(body, 76, 86, 16, 8, rgb(60, 60, 70), { Radius = 4, Z = 5 })
	return nil
end

-- Tapis de course (console, bande qui défile, rampes)
Art.Treadmill = function(body, kit, _item)
	kit.Part(body, 6, 82, 88, 14, rgb(50, 52, 60), { Radius = 5, Z = 1, Shine = true })
	local belt = kit.Part(body, 10, 80, 76, 6, rgb(30, 30, 36), { Radius = 3, Z = 2 })
	local stripe = kit.Box(belt, 20, 2, 18, 2, rgb(90, 90, 100), 0, 2)
	kit.Animate(stripe, "Drift", 18, 2, 0)
	for _, x in ipairs({ 16, 26 }) do
		kit.Line(body, x, 82, x + 6, 26, 4, STEEL, 0, 1)
	end
	kit.Line(body, 22, 44, 50, 44, 3, STEEL, 0, 3)
	local console = kit.Part(body, 6, 16, 34, 16, IRON_DARK, { Radius = 4, Z = 4, Shine = true })
	local screen = kit.Part(console, 4, 3, 26, 10, SCREEN, { Radius = 2, Z = 2, Outline = false })
	kit.Text(screen, "8.5 km/h", 13, 5, 7, CYAN, 2)
	kit.Circle(body, 44, 24, 5, 5, RED, 0, 5)
	-- bouteille d'eau
	kit.Part(body, 40, 30, 5, 10, rgb(120, 200, 240), { Radius = 2, Z = 5, T = 0.2 })
	return { Glow = CYAN }
end

-- Mur d'escalade (panneau, prises de couleur, corde)
Art.ClimbingWall = function(body, kit, _item)
	local panel = kit.Part(body, 6, 4, 88, 92, rgb(214, 200, 176), { Radius = 3, Z = 1, Shine = true })
	for k = 1, 3 do
		kit.Box(panel, 0, k * 23, 88, 1, rgb(170, 156, 134), 0, 2)
		kit.Box(panel, k * 22, 0, 1, 92, rgb(170, 156, 134), 0, 2)
	end
	local colors = { RED, BLUE, rgb(255, 200, 60), LIME, MAGENTA, ORANGE, CYAN }
	local holds = { { 20, 84 }, { 38, 74 }, { 26, 62 }, { 54, 58 }, { 70, 70 }, { 44, 44 }, { 66, 38 }, { 30, 30 }, { 52, 22 }, { 76, 16 },
		{ 18, 46 }, { 82, 52 }, { 60, 86 }, { 36, 12 } }
	for index, h in ipairs(holds) do
		local hold = kit.Blob(body, h[1], h[2], 9 + index % 3 * 2, 7 + index % 2 * 2, colors[(index % #colors) + 1], { Z = 3, Rotation = index * 23, Shine = true })
		local _ = hold
	end
	kit.Line(body, 84, 4, 84, 96, 2, rgb(255, 120, 60), 0, 4)
	kit.Circle(body, 84, 6, 5, 5, STEEL, 0, 5)
	return { WallShadow = Vector2.new(88, 92) }
end

-- Station de réalité virtuelle (tapis rond, capteurs, casque sur socle)
Art.VRStation = function(body, kit, _item)
	local mat = kit.Blob(body, 50, 92, 94, 14, rgb(40, 44, 70), { Z = 1, Shine = true })
	kit.Stroke(mat, CYAN, 2, 0)
	local ring = kit.Blob(body, 50, 92, 70, 8, CYAN, { Z = 2, T = 0.6, Outline = false })
	kit.Animate(ring, "Pulse", 0.3, 1.2, 0)
	for _, x in ipairs({ 8, 92 }) do
		kit.Part(body, x - 2, 20, 4, 72, IRON, { Radius = 2, Z = 2 })
		local sensor = kit.Part(body, x - 5, 14, 10, 8, IRON_DARK, { Radius = 2, Z = 3 })
		local led = kit.Circle(sensor, 5, 4, 3, 3, RED, 0, 2)
		kit.Animate(led, "Pulse", 0.7, 1.6, x)
	end
	-- socle + casque + manettes
	kit.Part(body, 42, 54, 16, 34, rgb(236, 238, 244), { Radius = 5, Z = 3, Shine = true })
	local headset = kit.Part(body, 32, 36, 36, 20, rgb(240, 242, 248), { Radius = 9, Z = 4, Shine = true })
	kit.Part(headset, 4, 4, 28, 12, rgb(30, 34, 50), { Radius = 5, Z = 2 })
	kit.Line(body, 32, 44, 22, 40, 3, rgb(60, 60, 70), 0, 3)
	kit.Line(body, 68, 44, 78, 40, 3, rgb(60, 60, 70), 0, 3)
	for _, x in ipairs({ 24, 76 }) do
		local c = kit.Part(body, x - 5, 58, 10, 18, rgb(236, 238, 244), { Radius = 5, Z = 4 })
		kit.Circle(c, 5, 4, 8, 8, rgb(60, 60, 70), 0, 2)
	end
	kit.Sparkle(body, 86, 44, 10, CYAN, 0, 5)
	return { Glow = CYAN }
end

-- Cockpit de course pro (3 écrans incurvés, siège baquet, volant, pédales)
Art.RacingCockpit = function(body, kit, _item)
	-- 3 écrans
	for index, spec in ipairs({ { 4, 18, -10 }, { 34, 12, 0 }, { 66, 18, 10 } }) do
		local s = glowScreen(kit, body, spec[1], spec[2], 30, 20, rgb(80, 150, 230), rgb(40, 60, 120), 2)
		s.Rotation = spec[3]
		kit.Box(s, 0, 12, 30, 8, rgb(60, 60, 70), 0, 2) -- piste
		kit.Box(s, 14, 12, 2, 8, WHITE, 0.4, 3)
		local _ = index
	end
	kit.Part(body, 46, 32, 8, 16, IRON, { Radius = 2, Z = 1 })
	-- châssis
	kit.Part(body, 4, 86, 92, 8, IRON_DARK, { Radius = 3, Z = 2, Shine = true })
	kit.Line(body, 30, 88, 36, 58, 4, IRON, 0, 2)
	-- volant
	local wheel = kit.Circle(body, 36, 54, 22, 22, rgb(30, 30, 36), 0, 5)
	kit.Stroke(wheel, rgb(60, 60, 70), 2, 0)
	kit.Box(wheel, 3, 10, 16, 3, rgb(60, 60, 70), 0, 2)
	kit.Circle(wheel, 11, 11, 6, 6, RED, 0, 3)
	-- siège baquet
	kit.Part(body, 60, 34, 30, 44, RED, { Radius = 12, Z = 4, Shine = true })
	kit.Part(body, 66, 38, 18, 30, rgb(30, 30, 36), { Radius = 8, Z = 5 })
	kit.Part(body, 54, 70, 40, 16, RED, { Radius = 7, Z = 6, Shine = true })
	kit.Part(body, 12, 76, 16, 10, IRON, { Radius = 2, Z = 4 }) -- pédales
	kit.Sparkle(body, 92, 12, 9, rgb(255, 214, 90), 0, 7)
	return { Glow = rgb(80, 150, 230) }
end

-- Double borne d'arcade néon (2 bornes côte à côte, écrans animés)
Art.TwinArcade = function(body, kit, _item)
	for index, spec in ipairs({ { 4, rgb(120, 60, 200), CYAN }, { 52, rgb(220, 50, 120), LIME } }) do
		local x, color, neon = spec[1], spec[2], spec[3]
		local cab = kit.Part(body, x, 12, 44, 88, color, { Radius = 4, Z = 1 + index, Shine = true })
		kit.Stroke(cab, neon, 2, 0)
		local marquee = kit.Part(cab, 3, 3, 38, 12, rgb(30, 30, 46), { Radius = 3, Z = 2 })
		kit.Text(marquee, index == 1 and "DOPA" or "RUN!", 19, 6, 9, neon, 2)
		local scr = kit.Part(cab, 5, 18, 34, 26, SCREEN, { Radius = 3, Z = 2, Outline = rgb(20, 20, 30) })
		local sprite = kit.Box(scr, 6, 12, 6, 6, neon, 0, 2)
		kit.Animate(sprite, "Drift", 8, 1.2, index)
		kit.Box(scr, 20, 6, 4, 4, rgb(255, 214, 90), 0, 2)
		kit.Box(scr, 0, 22, 34, 4, rgb(60, 60, 90), 0, 2)
		local panel = kit.Part(cab, 2, 46, 40, 12, rgb(30, 30, 46), { Radius = 3, Z = 3 })
		kit.Circle(panel, 10, 6, 6, 6, RED, 0, 2)
		kit.Circle(panel, 26, 6, 5, 5, rgb(255, 214, 90), 0, 2)
		kit.Circle(panel, 33, 6, 5, 5, neon, 0, 2)
		kit.Part(cab, 14, 64, 16, 10, rgb(30, 30, 46), { Radius = 2, Z = 2 }) -- fente à pièces
		local glow = kit.Box(body, x - 2, 96, 48, 4, neon, 0.5, 1)
		kit.Animate(glow, "Pulse", 0.3, 1.3, index)
	end
	return { Glow = CYAN }
end

return Art
