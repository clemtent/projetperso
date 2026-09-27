--[[
	HousePatterns (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HousePatterns

	Dessine les motifs des papiers peints et des sols UNIQUEMENT avec des
	Frames (pas d'image à importer) :
	  Murs : Plain (lambris), Stripes, Checker (vichy), Dots, Hearts, Stars
	         (étincelles), Clouds, Bricks, Wood (lambris de bois), Waves
	         (écailles / vaguelettes) ; v9.1 : Plaid (écossais), Flowers,
	         Diamonds (arlequin), Chevron, Moons ; v9.2 : Flag (damier
	         d'arrivée), Bolts (éclairs), Camo, Racing (bandes de course),
	         Carbon, Graffiti, Planets (espace), NeonGrid.
	  Sols : Plain, Checker, Wood, Tiles, Carpet, Marble, Herringbone
	         (parquet) ; v9.1 : Terrazzo, Mosaic, Grass, Clouds, Starry ;
	         v9.2 : Concrete, Court (basket), Turf (foot), TreadPlate (tôle),
	         Road, Lava — en PERSPECTIVE : les rangées grandissent vers
	         l'avant et les colonnes s'écartent depuis le centre (lignes de
	         fuite), sans aucune rotation.
	Le conteneur doit couper son contenu (ClipsDescendants) ; son fond
	prend la couleur A. `unit` agrandit / réduit le motif (1 dans la pièce,
	plus petit dans les aperçus de la boutique).
	Nombre de Frames limité (≈ 60 à 300 selon le motif et la largeur).

	API :
	  HousePatterns.BuildWall(container, largeur, hauteur, style, unit?)
	  HousePatterns.BuildFloor(container, largeur, hauteur, style, unit?)
	  (style = { Pattern, A, B } ; les anciens motifs sont remplacés)
]]

local HousePatterns = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local SQRT2 = math.sqrt(2)

type Style = { Pattern: string, A: Color3, B: Color3 }

----------------------------------------------------------------------
-- Formes de base
----------------------------------------------------------------------

local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, transparency: number?, z: number?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.ZIndex = z or 1
	frame.Parent = parent
	return frame
end

local function roundify(frame: Frame, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(1, 0)
	corner.Parent = frame
end

-- Cercle (ou ovale) centré
local function circle(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, transparency: number?, z: number?): Frame
	local frame = box(parent, cx - w / 2, cy - h / 2, w, h, color, transparency, z)
	roundify(frame)
	return frame
end

-- Carré tourné de 45° (losange) centré
local function diamond(parent: Instance, cx: number, cy: number, side: number, color: Color3, transparency: number?, z: number?): Frame
	local frame = box(parent, 0, 0, side, side, color, transparency, z)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(cx, cy)
	frame.Rotation = 45
	return frame
end

-- Cœur (2 cercles + un losange) centré, de largeur `width`
local function heart(parent: Instance, cx: number, cy: number, width: number, color: Color3, transparency: number?, z: number?)
	local a = width / (1 + 1 / SQRT2)
	local shift = a * 0.073 -- recentre la forme verticalement
	local centerY = cy + shift
	local offset = a / (2 * SQRT2)
	diamond(parent, cx, centerY, a, color, transparency, z)
	circle(parent, cx - offset, centerY - offset, a, a, color, transparency, z)
	circle(parent, cx + offset, centerY - offset, a, a, color, transparency, z)
end

-- Étincelle à 4 branches (losange + 2 bâtonnets arrondis)
local function sparkle(parent: Instance, cx: number, cy: number, size: number, color: Color3, transparency: number?, z: number?)
	diamond(parent, cx, cy, size * 0.36, color, transparency, z)
	local thin = math.max(1, size * 0.13)
	local vertical = box(parent, cx - thin / 2, cy - size / 2, thin, size, color, transparency, z)
	roundify(vertical)
	local horizontal = box(parent, cx - size / 2, cy - thin / 2, size, thin, color, transparency, z)
	roundify(horizontal)
end

-- Nuage (base arrondie + 2 bosses), `cy` = bas du nuage
local function cloud(parent: Instance, cx: number, cy: number, width: number, color: Color3, transparency: number?, z: number?)
	local baseH = width * 0.34
	local base = box(parent, cx - width / 2, cy - baseH, width, baseH, color, transparency, z)
	roundify(base)
	circle(parent, cx - width * 0.14, cy - baseH, width * 0.5, width * 0.5, color, transparency, z)
	circle(parent, cx + width * 0.2, cy - baseH * 0.9, width * 0.36, width * 0.36, color, transparency, z)
end

-- Pseudo-aléatoire stable (même dessin à chaque reconstruction)
local function noise(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

local function clear(container: GuiObject): Frame
	local old = container:FindFirstChild("Pattern")
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Frame")
	holder.Name = "Pattern"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 1
	return holder
end

----------------------------------------------------------------------
-- Murs
----------------------------------------------------------------------

local WALL: { [string]: (holder: Frame, w: number, h: number, a: Color3, b: Color3, u: number) -> () } = {}

-- Uni : lambris en bas (couleur B), moulure claire et petits panneaux
WALL.Plain = function(holder, w, h, a, b, u)
	local bandTop = h * 0.64
	box(holder, 0, bandTop, w, h - bandTop, b)
	box(holder, 0, bandTop - 3 * u, w, 5 * u, a:Lerp(WHITE, 0.6))
	box(holder, 0, bandTop + 2 * u, w, 1.5 * u, b:Lerp(BLACK, 0.12), 0.4)
	local panel = 96 * u
	local x = panel * 0.5
	while x < w do
		local frame = box(holder, x - panel * 0.36, bandTop + 12 * u, panel * 0.72, (h - bandTop) - 22 * u, b:Lerp(WHITE, 0.25), 0.35)
		roundify(frame, UDim.new(0, 4 * u))
		x += panel
	end
	-- Petits motifs discrets sur le haut du mur
	local step = 58 * u
	local row = 0
	local y = 26 * u
	while y < bandTop - 16 * u do
		local offset = (row % 2) * step / 2
		local cx = step / 2 + offset
		while cx < w do
			diamond(holder, cx, y, 5 * u, b, 0.35)
			cx += step
		end
		y += step * 0.7
		row += 1
	end
end

-- Rayures verticales (+ fines rayures au milieu des bandes claires)
WALL.Stripes = function(holder, w, _h, _a, b, u)
	local stripe = 24 * u
	local x = 0
	while x < w do
		local frame = box(holder, x + stripe, 0, stripe, 10000, b)
		frame.Size = UDim2.new(0, stripe, 1, 0)
		local pin = box(holder, x + stripe / 2 - u, 0, 2 * u, 10000, b, 0.45)
		pin.Size = UDim2.new(0, 2 * u, 1, 0)
		x += stripe * 2
	end
end

-- Vichy : bandes semi-transparentes dans les deux sens (carreaux plus foncés aux croisements)
WALL.Checker = function(holder, w, h, _a, b, u)
	local cell = 26 * u
	local x = 0
	while x < w do
		local frame = box(holder, x, 0, cell, h, b, 0.35)
		frame.Size = UDim2.new(0, cell, 1, 0)
		x += cell * 2
	end
	local y = 0
	while y < h do
		local frame = box(holder, 0, y, w, cell, b, 0.35)
		frame.Size = UDim2.new(1, 0, 0, cell)
		y += cell * 2
	end
end

-- Pois en quinconce
WALL.Dots = function(holder, w, h, _a, b, u)
	local step = 60 * u
	local diameter = 16 * u
	local row = 0
	local y = step * 0.4
	while y < h + diameter do
		local cx = (row % 2) * step / 2 + step * 0.3
		while cx < w + diameter do
			circle(holder, cx, y, diameter, diameter, b)
			cx += step
		end
		y += step * 0.72
		row += 1
	end
end

-- Cœurs en quinconce (deux teintes)
WALL.Hearts = function(holder, w, h, _a, b, u)
	local step = 88 * u
	local size = 24 * u
	local light = b:Lerp(WHITE, 0.35)
	local row = 0
	local y = step * 0.45
	while y < h - size * 0.4 do
		local cx = (row % 2) * step / 2 + step * 0.35
		local index = 0
		while cx < w - size * 0.4 do
			local sizeHere = size * (0.8 + 0.4 * noise(cx, y))
			heart(holder, cx, y, sizeHere, (index + row) % 3 == 0 and light or b)
			cx += step
			index += 1
		end
		y += step * 0.62
		row += 1
	end
end

-- Étincelles (tailles variées) + petits points
WALL.Stars = function(holder, w, h, a, b, u)
	local step = 90 * u
	local row = 0
	local y = step * 0.4
	while y < h do
		local cx = (row % 2) * step / 2 + step * 0.3
		local index = 0
		while cx < w do
			local n = noise(cx, y)
			local size = (16 + 20 * n) * u
			sparkle(holder, cx + (n - 0.5) * 16 * u, y + (noise(y, cx) - 0.5) * 12 * u, size, b, n > 0.7 and 0 or 0.15)
			if index % 2 == 0 then
				circle(holder, cx + step * 0.5, y + step * 0.28, 4 * u, 4 * u, b:Lerp(a, 0.2), 0.2)
			end
			cx += step
			index += 1
		end
		y += step * 0.66
		row += 1
	end
end

-- Nuages moelleux
WALL.Clouds = function(holder, w, h, a, b, u)
	local step = 150 * u
	local rows = math.max(1, math.floor(h / (86 * u)))
	for row = 0, rows - 1 do
		local y = (row + 0.72) * (h / rows)
		local cx = (row % 2) * step / 2 + step * 0.35
		while cx < w + step do
			local n = noise(cx, row)
			local width = (60 + 30 * n) * u
			cloud(holder, cx, y, width, b, 0.05 + n * 0.15)
			-- Petite étoile entre deux nuages
			sparkle(holder, cx + step * 0.5, y - 40 * u * (0.5 + n), 9 * u, b:Lerp(a, 0.1), 0.25)
			cx += step
		end
	end
end

-- Briques (joints clairs couleur A, briques couleur B en nuances)
WALL.Bricks = function(holder, w, h, a, b, u)
	local brickW = 70 * u
	local brickH = 28 * u
	local mortar = 4 * u
	local row = 0
	local y = mortar
	while y < h do
		local x = (row % 2 == 0) and -brickW / 2 or 0
		while x < w do
			local n = noise(x + 3, y + 7)
			local tone = b:Lerp(a, n * 0.35)
			local brick = box(holder, x + mortar / 2, y, brickW - mortar, brickH, tone)
			if n > 0.72 then
				-- Petit reflet sur quelques briques
				box(brick, 4 * u, 3 * u, (brickW - mortar) * 0.4, 2 * u, WHITE, 0.55)
			end
			x += brickW
		end
		y += brickH + mortar
		row += 1
	end
end

-- Lambris de bois vertical (planches, joints, nœuds)
WALL.Wood = function(holder, w, h, a, b, u)
	local plank = 46 * u
	local seam = b:Lerp(BLACK, 0.18)
	local index = 0
	local x = 0
	while x < w do
		if index % 2 == 1 then
			local tone = box(holder, x, 0, plank, h, b, 0.55)
			tone.Size = UDim2.new(0, plank, 1, 0)
		end
		local line = box(holder, x, 0, 3 * u, h, seam, 0.15)
		line.Size = UDim2.new(0, 3 * u, 1, 0)
		local n = noise(index, 1)
		if n > 0.45 then
			circle(holder, x + plank * (0.3 + 0.4 * n), h * (0.2 + 0.6 * noise(index, 2)), 11 * u, 6 * u, seam, 0.45)
		end
		-- Veine du bois
		local grain = box(holder, x + plank * (0.25 + 0.5 * noise(index, 3)), 0, 1.5 * u, h, a:Lerp(b, 0.7), 0.5)
		grain.Size = UDim2.new(0, 1.5 * u, 1, 0)
		x += plank
		index += 1
	end
end

-- Écailles / vaguelettes : rangées de cercles qui se chevauchent
WALL.Waves = function(holder, w, h, a, b, u)
	local diameter = 74 * u
	local stepX = 66 * u
	local stepY = 40 * u
	local tones = { b, a:Lerp(b, 0.5), b:Lerp(WHITE, 0.3) }
	local row = 0
	local y = -diameter * 0.3
	while y < h + diameter * 0.2 do
		local offset = (row % 2) * stepX / 2 - stepX / 2
		local x = offset
		local color = tones[row % #tones + 1]
		while x < w + stepX do
			circle(holder, x + stepX / 2, y + diameter / 2, diameter, diameter, color, 0, row + 1)
			x += stepX
		end
		y += stepY
		row += 1
	end
end

-- (v9.1) Écossais : larges bandes croisées (B) + fins filets blancs
WALL.Plaid = function(holder, w, h, a, b, u)
	local cell = 64 * u
	local x = 0
	while x < w do
		local band = box(holder, x, 0, cell * 0.42, h, b, 0.45)
		band.Size = UDim2.new(0, cell * 0.42, 1, 0)
		local thread = box(holder, x + cell * 0.66, 0, 2 * u, h, WHITE, 0.35)
		thread.Size = UDim2.new(0, 2 * u, 1, 0)
		x += cell
	end
	local y = 0
	while y < h do
		local band = box(holder, 0, y, w, cell * 0.42, b, 0.45)
		band.Size = UDim2.new(1, 0, 0, cell * 0.42)
		local thread = box(holder, 0, y + cell * 0.66, w, 2 * u, WHITE, 0.35)
		thread.Size = UDim2.new(1, 0, 0, 2 * u)
		local dark = box(holder, 0, y + cell * 0.18, w, 3 * u, b:Lerp(BLACK, 0.2), 0.55)
		dark.Size = UDim2.new(1, 0, 0, 3 * u)
		y += cell
	end
	local _ = a
end

-- (v9.1) Petites fleurs à 5 pétales (B) au cœur jaune, en quinconce
WALL.Flowers = function(holder, w, h, a, b, u)
	local step = 70 * u
	local petal = 11 * u
	local heartColor = Color3.fromRGB(255, 214, 110)
	local petalColor = b
	if (b.R + b.G + b.B) / 3 > 0.95 then
		-- pétales blancs sur fond clair : un contour pastel pour les voir
		petalColor = a:Lerp(Color3.fromRGB(255, 190, 210), 0.5)
	end
	local row = 0
	local y = step * 0.4
	while y < h + petal do
		local cx = (row % 2) * step / 2 + step * 0.3
		while cx < w + petal do
			local n = noise(cx, y)
			local scale = 0.8 + n * 0.4
			for k = 0, 4 do
				local angle = k / 5 * math.pi * 2 + n
				circle(holder, cx + math.cos(angle) * petal * 0.62 * scale, y + math.sin(angle) * petal * 0.62 * scale,
					petal * scale, petal * scale, petalColor, 0.05)
			end
			circle(holder, cx, y, petal * 0.7 * scale, petal * 0.7 * scale, heartColor, 0)
			if n > 0.55 then
				-- petite feuille
				local leaf = circle(holder, cx + step * 0.3, y + step * 0.18, 12 * u, 6 * u, Color3.fromRGB(150, 210, 140), 0.25)
				leaf.Rotation = -30
			end
			cx += step
		end
		y += step * 0.7
		row += 1
	end
end

-- (v9.1) Arlequin : losanges B (en quinconce) + fins points blancs
WALL.Diamonds = function(holder, w, h, a, b, u)
	local step = 56 * u
	local row = 0
	local y = 0
	while y < h + step do
		local cx = (row % 2) * step / 2
		while cx < w + step do
			diamond(holder, cx, y, step * 0.5, b, 0.1)
			circle(holder, cx + step / 2, y, 4 * u, 4 * u, WHITE, 0.3)
			cx += step
		end
		y += step / 2
		row += 1
	end
	local _ = a
end

-- (v9.1) Chevrons : zigzags horizontaux (segments tournés), 2 teintes
WALL.Chevron = function(holder, w, h, a, b, u)
	local seg = 40 * u
	local thick = 13 * u
	local rowGap = 46 * u
	local tones = { b, b:Lerp(a, 0.45) }
	local row = 0
	local y = rowGap * 0.5
	while y < h + rowGap do
		local x = 0
		local index = 0
		local color = tones[row % 2 + 1]
		while x < w + seg do
			local up = index % 2 == 0
			local frame = box(holder, 0, 0, seg * 1.02 + thick * 0.4, thick, color, 0)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromOffset(x + seg * 0.5, y)
			frame.Rotation = up and -32 or 32
			roundify(frame, UDim.new(0, thick * 0.3))
			x += seg * 0.86
			index += 1
		end
		y += rowGap
		row += 1
	end
end

-- (v9.1) Lunes endormies et étoiles
WALL.Moons = function(holder, w, h, a, b, u)
	local step = 92 * u
	local row = 0
	local y = step * 0.42
	while y < h + 10 * u do
		local cx = (row % 2) * step / 2 + step * 0.32
		while cx < w + 10 * u do
			local n = noise(cx, y)
			local size = (22 + 10 * n) * u
			local moon = circle(holder, cx, y, size, size, b)
			-- croissant : un disque couleur du fond "croque" la lune
			circle(moon, size * 0.72, size * 0.36, size * 0.82, size * 0.82, a, 0)
			sparkle(holder, cx + step * 0.46, y + step * 0.2, (8 + 6 * n) * u, b, 0.15)
			circle(holder, cx - step * 0.28, y + step * 0.3, 4 * u, 4 * u, b, 0.3)
			cx += step
		end
		y += step * 0.66
		row += 1
	end
end

----------------------------------------------------------------------
-- (v9.2) Murs "cool" : damier de course, éclairs, camouflage, bandes de
-- course, fibre de carbone, graffitis, planètes, grille néon
----------------------------------------------------------------------

-- Trait (segment arrondi) entre deux points
local function segment(parent: Instance, x1: number, y1: number, x2: number, y2: number, thick: number, color: Color3, transparency: number?, z: number?): Frame
	local dx, dy = x2 - x1, y2 - y1
	local frame = box(parent, 0, 0, math.sqrt(dx * dx + dy * dy) + thick, thick, color, transparency, z)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	frame.Rotation = math.deg(math.atan2(dy, dx))
	roundify(frame)
	return frame
end

-- Anneau / ovale vide (contour seulement)
local function ring(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, thick: number, transparency: number?, z: number?): Frame
	local frame = circle(parent, cx, cy, w, h, color, 1, z)
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thick
	line.Transparency = transparency or 0
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = frame
	return frame
end

-- Éclair (3 segments) de hauteur `size`, centré en (cx, cy)
local function bolt(parent: Instance, cx: number, cy: number, size: number, color: Color3, transparency: number?, z: number?)
	local x, y = cx - size * 0.35, cy - size / 2
	local t = size * 0.17
	segment(parent, x + size * 0.55, y, x + size * 0.16, y + size * 0.52, t, color, transparency, z)
	segment(parent, x + size * 0.16, y + size * 0.52, x + size * 0.54, y + size * 0.48, t, color, transparency, z)
	segment(parent, x + size * 0.54, y + size * 0.48, x + size * 0.14, y + size, t, color, transparency, z)
end

-- Damier de drapeau d'arrivée (grandes cases B) + léger drapé
WALL.Flag = function(holder, w, h, a, b, u)
	local cell = 44 * u
	local row = 0
	local y = 0
	while y < h do
		local col = row % 2
		local x = col * cell
		while x < w do
			box(holder, x, y, cell, cell, b)
			x += cell * 2
		end
		y += cell
		row += 1
	end
	-- plis du drapeau : bandes claires / sombres très douces
	local fold = 180 * u
	local x = 0
	local index = 0
	while x < w do
		local band = box(holder, x, 0, fold * 0.45, h, index % 2 == 0 and WHITE or BLACK, 0.9)
		band.Size = UDim2.new(0, fold * 0.45, 1, 0)
		x += fold * 0.5
		index += 1
	end
	local _ = a
end

-- Éclairs en quinconce (B) + petits points
WALL.Bolts = function(holder, w, h, a, b, u)
	local step = 110 * u
	local row = 0
	local y = step * 0.4
	while y < h + step * 0.2 do
		local cx = (row % 2) * step / 2 + step * 0.3
		while cx < w + step * 0.2 do
			local n = noise(cx, y)
			bolt(holder, cx, y, (30 + 14 * n) * u, b, 0.05)
			circle(holder, cx + step * 0.5, y + step * 0.1, 5 * u, 5 * u, b:Lerp(a, 0.4), 0.2)
			circle(holder, cx + step * 0.28, y - step * 0.22, 3 * u, 3 * u, WHITE, 0.4)
			cx += step
		end
		y += step * 0.62
		row += 1
	end
end

-- Camouflage : taches arrondies en 3 teintes (B, B foncé, A clair)
WALL.Camo = function(holder, w, h, a, b, u)
	local tones = { b, b:Lerp(BLACK, 0.3), a:Lerp(WHITE, 0.25), b:Lerp(a, 0.5) }
	local step = 62 * u
	local row = 0
	local y = 0
	while y < h + step do
		local x = (row % 2) * step / 2 - step * 0.3
		local index = 0
		while x < w + step do
			local n = noise(x + 1, y + 2)
			local m = noise(y + 5, x + 3)
			local blob = circle(holder, x + (n - 0.5) * step * 0.6, y + (m - 0.5) * step * 0.5,
				(46 + 40 * n) * u, (26 + 22 * m) * u, tones[(index + row) % #tones + 1], 0)
			blob.Rotation = (n - 0.5) * 120
			x += step
			index += 1
		end
		y += step * 0.55
		row += 1
	end
end

-- Bandes de course : damier sous le plafond, double bande B, filets blancs
WALL.Racing = function(holder, w, h, a, b, u)
	local cell = 14 * u
	for row = 0, 1 do
		local x = row * cell
		while x < w do
			box(holder, x, 6 * u + row * cell, cell, cell, WHITE, 0.05)
			x += cell * 2
		end
	end
	local mid = h * 0.46
	local big = box(holder, 0, mid, w, 40 * u, b)
	big.Size = UDim2.new(1, 0, 0, 40 * u)
	local small = box(holder, 0, mid + 52 * u, w, 14 * u, b)
	small.Size = UDim2.new(1, 0, 0, 14 * u)
	for _, y in ipairs({ mid - 7 * u, mid + 44 * u, mid + 70 * u }) do
		local pin = box(holder, 0, y, w, 3 * u, WHITE, 0.1)
		pin.Size = UDim2.new(1, 0, 0, 3 * u)
	end
	-- traits de vitesse
	for index = 0, 5 do
		local y = h * 0.2 + noise(index, 4) * h * 0.18
		local x = noise(4, index) * w * 0.85
		local streak = box(holder, x, y, (60 + 60 * noise(index, 9)) * u, 3 * u, WHITE, 0.6)
		roundify(streak)
	end
	local _ = a
end

-- Fibre de carbone : rangées de reflets tissés (dégradés alternés)
local CARBON_WEAVE = (function()
	local points = {}
	for index = 0, 18 do
		table.insert(points, NumberSequenceKeypoint.new(index / 18, index % 2 == 0 and 0.2 or 0.85))
	end
	return NumberSequence.new(points)
end)()
WALL.Carbon = function(holder, w, h, a, b, u)
	local rowH = 12 * u
	local span = 9 * 22 * u -- 9 mailles par cadre
	local row = 0
	local y = 0
	while y < h do
		local x = (row % 2 == 0) and 0 or -11 * u
		while x < w do
			local strip = box(holder, x, y, span, rowH, b, 0)
			local weave = Instance.new("UIGradient")
			weave.Transparency = CARBON_WEAVE
			weave.Parent = strip
			x += span
		end
		-- fine ligne sombre entre deux rangées
		local seam = box(holder, 0, y + rowH - u, w, u, a:Lerp(BLACK, 0.35), 0.4)
		seam.Size = UDim2.new(1, 0, 0, u)
		y += rowH
		row += 1
	end
	-- reflet diagonal (vernis)
	local gloss = box(holder, w * 0.3, -h * 0.2, w * 0.18, h * 1.5, WHITE, 0.9)
	gloss.Rotation = 20
end

-- Graffitis : mur de béton clair (joints), gros tags en bulles, taches,
-- coulures et petites étoiles (couleurs vives, B + cyan + jaune)
local TAGS = { "COOL", "GG", "WOW!", "YO!", "EPIC" }
WALL.Graffiti = function(holder, w, h, a, b, u)
	local seam = a:Lerp(BLACK, 0.12)
	local y = 60 * u
	while y < h do
		local line = box(holder, 0, y, w, 2 * u, seam, 0.3)
		line.Size = UDim2.new(1, 0, 0, 2 * u)
		y += 60 * u
	end
	local colors = { b, Color3.fromRGB(60, 200, 255), Color3.fromRGB(255, 210, 60), Color3.fromRGB(120, 230, 110) }
	local step = 250 * u
	local index = 0
	local x = step * 0.45
	while x < w + step * 0.3 do
		local color = colors[index % #colors + 1]
		local cy = h * (0.34 + 0.22 * noise(index, 3))
		-- tache de peinture + coulures
		local splash = circle(holder, x, cy, 170 * u, 90 * u, color:Lerp(WHITE, 0.55), 0.35)
		splash.Rotation = (noise(index, 5) - 0.5) * 20
		for drip = 0, 2 do
			local dx = x + (drip - 1) * 40 * u + noise(index, drip) * 16 * u
			local length = (24 + 40 * noise(drip, index)) * u
			local d = box(holder, dx, cy + 30 * u, 6 * u, length, color, 0.1)
			roundify(d)
		end
		-- tag en lettres "bulles" (contour sombre)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(x, cy)
		label.Size = UDim2.fromOffset(220 * u, 80 * u)
		label.Font = Enum.Font.FredokaOne
		label.Text = TAGS[index % #TAGS + 1]
		label.TextSize = math.max(8, math.floor(54 * u))
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.fromRGB(40, 36, 60)
		label.TextStrokeTransparency = 0
		label.Rotation = (noise(index, 7) - 0.5) * 16
		label.ZIndex = 2
		label.Parent = holder
		-- étoiles et couronne griffonnées
		sparkle(holder, x + 100 * u, cy - 44 * u, 20 * u, colors[(index + 1) % #colors + 1], 0, 2)
		sparkle(holder, x - 96 * u, cy + 50 * u, 14 * u, WHITE, 0.1, 2)
		x += step
		index += 1
	end
end

-- Espace profond : étoiles, planètes (certaines à anneau), étoiles filantes
WALL.Planets = function(holder, w, h, a, b, u)
	for index = 1, math.floor(w * h / (2600 * u * u)) do
		local s = (2 + 3 * noise(index, 1)) * u
		circle(holder, noise(index, 2) * w, noise(3, index) * h, s, s, WHITE, 0.2 + 0.5 * noise(index, 4))
	end
	local palette = { b, Color3.fromRGB(255, 150, 110), Color3.fromRGB(190, 150, 255), Color3.fromRGB(120, 230, 170) }
	local step = 190 * u
	local index = 0
	local x = step * 0.4
	while x < w + step * 0.3 do
		local n = noise(index, 11)
		local cy = h * (0.22 + 0.55 * n)
		local size = (34 + 36 * noise(11, index)) * u
		local color = palette[index % #palette + 1]
		local planet = circle(holder, x, cy, size, size, color, 0, 2)
		-- ombre (croissant sombre) + reflet
		circle(planet, size * 0.62, size * 0.6, size * 0.9, size * 0.9, a, 0.55, 2)
		circle(planet, size * 0.3, size * 0.28, size * 0.22, size * 0.16, WHITE, 0.4, 3)
		if index % 2 == 0 then
			local band = box(holder, 0, 0, size * 1.8, 5 * u, color:Lerp(WHITE, 0.5), 0.15, 3)
			band.AnchorPoint = Vector2.new(0.5, 0.5)
			band.Position = UDim2.fromOffset(x, cy + size * 0.05)
			band.Rotation = -16
			roundify(band)
		end
		sparkle(holder, x + step * 0.45, cy - step * 0.25, 16 * u, WHITE, 0.1, 2)
		-- étoile filante
		if index % 3 == 1 then
			local tail = box(holder, 0, 0, 90 * u, 3 * u, WHITE, 0.2, 2)
			tail.AnchorPoint = Vector2.new(1, 0.5)
			tail.Position = UDim2.fromOffset(x + step * 0.3, cy + step * 0.35)
			tail.Rotation = -24
			local fade = Instance.new("UIGradient")
			fade.Transparency = NumberSequence.new(1, 0)
			fade.Parent = tail
			roundify(tail)
		end
		x += step
		index += 1
	end
end

-- Grille néon : lignes lumineuses (B) + points aux croisements, lueur en bas
WALL.NeonGrid = function(holder, w, h, a, b, u)
	local cell = 46 * u
	local x = cell / 2
	while x < w do
		local line = box(holder, x, 0, 2 * u, h, b, 0.45)
		line.Size = UDim2.new(0, 2 * u, 1, 0)
		x += cell
	end
	local y = cell / 2
	local row = 0
	while y < h do
		local line = box(holder, 0, y, w, 2 * u, b, 0.45)
		line.Size = UDim2.new(1, 0, 0, 2 * u)
		if row % 2 == 1 then
			local cx = cell / 2 + math.floor(noise(row, 3) * (w / cell)) * cell
			circle(holder, cx, y, 10 * u, 10 * u, WHITE, 0.1, 2)
			circle(holder, cx, y, 22 * u, 22 * u, b, 0.6, 2)
		end
		y += cell
		row += 1
	end
	local glowBand = box(holder, 0, h * 0.55, w, h * 0.45, b, 0.4)
	glowBand.Size = UDim2.new(1, 0, 0.45, 0)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(1, 0.55)
	fade.Parent = glowBand
	local _ = a
end

----------------------------------------------------------------------
-- Sols (perspective)
----------------------------------------------------------------------

type Row = { Y: number, H: number, K: number }

-- Rangées de plus en plus hautes vers l'avant. K = hauteur / hauteur de la rangée avant.
local function perspectiveRows(h: number, count: number, ratio: number): { Row }
	local rows = {}
	local total = 0
	for index = 0, count - 1 do
		total += ratio ^ index
	end
	local first = h / total
	local y = 0
	local front = first * ratio ^ (count - 1)
	for index = 0, count - 1 do
		local height = first * ratio ^ index
		table.insert(rows, { Y = y, H = height, K = height / front })
		y += height
	end
	return rows
end

-- Largeur des cases d'une rangée : les colonnes s'écartent vers l'avant, mais
-- doucement (une perspective trop forte ferait des "escaliers" sur les côtés)
local function cellWidth(front: number, k: number): number
	return front * (0.62 + 0.38 * k)
end

-- Colonnes d'une rangée (bords gauche) : centrées sur le milieu, largeur `cellW`
local function columns(w: number, cellW: number, phase: number?): (number, number)
	local center = w / 2 + (phase or 0) * cellW
	local first = -math.ceil(center / cellW) - 1
	local last = math.ceil((w - center) / cellW) + 1
	return first, last
end

local FLOOR: { [string]: (holder: Frame, w: number, h: number, a: Color3, b: Color3, u: number) -> () } = {}

-- Uni : quelques reflets doux en perspective
FLOOR.Plain = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 5, 1.3)
	for index, row in ipairs(rows) do
		if index % 2 == 0 then
			box(holder, 0, row.Y, w, row.H, b, 0.55)
		end
	end
	for index = 1, 4 do
		local cx = w * (index / 5)
		circle(holder, cx, h * 0.55, 110 * u, 18 * u, a:Lerp(WHITE, 0.6), 0.55)
	end
end

-- Damier en perspective
FLOOR.Checker = function(holder, w, h, _a, b, u)
	local rows = perspectiveRows(h, 7, 1.17)
	local frontW = rows[#rows].H * 1.6
	for index, row in ipairs(rows) do
		local cellW = cellWidth(frontW, row.K)
		local center = w / 2
		local first, last = columns(w, cellW)
		for j = first, last do
			if (index + j) % 2 == 0 then
				box(holder, center + j * cellW, row.Y, cellW, row.H + 0.5, b)
			end
		end
	end
	-- Léger reflet
	box(holder, 0, 0, w, h * 0.35, WHITE, 0.88)
	local _ = u
end

-- Parquet de planches (joints décalés d'une rangée à l'autre)
FLOOR.Wood = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 6, 1.2)
	local frontL = rows[#rows].H * 4.2
	local seam = b:Lerp(BLACK, 0.2)
	for index, row in ipairs(rows) do
		local length = cellWidth(frontL, row.K)
		local phase = noise(index, 5)
		local first, last = columns(w, length, phase)
		local center = w / 2 + phase * length
		for j = first, last do
			local x = center + j * length
			if (j + index) % 2 == 0 then
				box(holder, x, row.Y, length, row.H, b, 0.5)
			end
			box(holder, x, row.Y, math.max(1, 2 * u * row.K + 0.6), row.H, seam, 0.25)
			if noise(j, index) > 0.6 then
				box(holder, x + length * 0.2, row.Y + row.H * 0.45, length * 0.35, math.max(1, 1.2 * u), a:Lerp(b, 0.8), 0.45)
			end
		end
		box(holder, 0, row.Y, w, math.max(1, 2 * u * row.K + 0.4), seam, 0.3)
	end
end

-- Carrelage (joints couleur B)
FLOOR.Tiles = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 6, 1.2)
	local frontW = rows[#rows].H * 1.5
	for index, row in ipairs(rows) do
		local cellW = cellWidth(frontW, row.K)
		local grout = math.max(1, 3 * u * row.K + 0.5)
		local first, last = columns(w, cellW)
		local center = w / 2
		for j = first, last do
			local x = center + j * cellW
			box(holder, x - grout / 2, row.Y, grout, row.H, b)
			if (index + j) % 3 == 0 then
				-- Reflet dans le coin de quelques carreaux
				box(holder, x + cellW * 0.12, row.Y + row.H * 0.15, cellW * 0.22, math.max(1, row.H * 0.1), WHITE, 0.45)
			end
		end
		box(holder, 0, row.Y, w, grout, b)
	end
	local _ = a
end

-- Moquette : bandes douces + petites touffes
FLOOR.Carpet = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 9, 1.12)
	for index, row in ipairs(rows) do
		if index % 2 == 0 then
			box(holder, 0, row.Y, w, row.H, b, 0.35)
		end
		if index % 2 == 1 then
			local step = 90 * u * row.K + 30 * u
			local x = noise(index, 9) * step
			while x < w do
				local size = (3 + 4 * row.K) * u
				circle(holder, x, row.Y + row.H * 0.5, size * 1.8, size, a:Lerp(WHITE, 0.45), 0.35)
				x += step * (0.8 + noise(x, index) * 0.6)
			end
		end
	end
end

-- Marbre : grandes dalles + veines fines (tournées, loin des bords)
FLOOR.Marble = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 4, 1.3)
	local frontW = rows[#rows].H * 2
	local vein = b:Lerp(BLACK, 0.12)
	for index, row in ipairs(rows) do
		local cellW = cellWidth(frontW, row.K)
		local first, last = columns(w, cellW)
		local center = w / 2
		for j = first, last do
			local x = center + j * cellW
			if (index + j) % 2 == 0 then
				box(holder, x, row.Y, cellW, row.H, b, 0.7)
			end
			box(holder, x, row.Y, math.max(1, 1.5 * u), row.H, vein, 0.45)
			local n = noise(j + 11, index)
			if x > 0 and x + cellW < w then
				local length = cellW * (0.35 + 0.3 * n)
				local veinFrame = box(holder, 0, 0, length, math.max(1, 1.4 * u), vein, 0.35)
				veinFrame.AnchorPoint = Vector2.new(0.5, 0.5)
				veinFrame.Position = UDim2.fromOffset(x + cellW * (0.35 + 0.3 * n), row.Y + row.H * (0.35 + 0.3 * noise(index, j)))
				veinFrame.Rotation = (n - 0.5) * 50 * row.K
			end
		end
		box(holder, 0, row.Y, w, math.max(1, 1.5 * u), vein, 0.45)
	end
	box(holder, 0, 0, w, h * 0.3, a:Lerp(WHITE, 0.8), 0.6)
end

-- Parquet "bâtons rompus" : blocs de 2 lames, alternés horizontal / vertical
FLOOR.Herringbone = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 6, 1.2)
	local frontW = rows[#rows].H * 1.8
	local seam = b:Lerp(BLACK, 0.25)
	local alt = a:Lerp(b, 0.55)
	for index, row in ipairs(rows) do
		local cellW = cellWidth(frontW, row.K)
		local gap = math.max(1, 1.5 * u * row.K + 0.4)
		local first, last = columns(w, cellW)
		local center = w / 2
		for j = first, last do
			local x = center + j * cellW
			local horizontal = (index + j) % 2 == 0
			local cell = box(holder, x + gap / 2, row.Y + gap / 2, cellW - gap, row.H - gap, horizontal and a or alt)
			if horizontal then
				box(cell, 0, (row.H - gap) / 2 - gap / 2, cellW - gap, gap, seam, 0.3)
			else
				box(cell, (cellW - gap) / 2 - gap / 2, 0, gap, row.H - gap, seam, 0.3)
			end
		end
	end
	local _ = u
end

-- (v9.1) Terrazzo : éclats de couleurs (plus gros vers l'avant)
FLOOR.Terrazzo = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 7, 1.16)
	local chips = { b, b:Lerp(WHITE, 0.4), Color3.fromRGB(255, 214, 120), Color3.fromRGB(150, 206, 240), b:Lerp(BLACK, 0.15) }
	for index, row in ipairs(rows) do
		local step = (38 + 30 * row.K) * u
		local x = noise(index, 3) * step
		while x < w do
			local n = noise(x, index)
			local size = (4 + 7 * row.K * (0.5 + n)) * u
			local chip = circle(holder, x, row.Y + row.H * (0.2 + 0.6 * noise(index, x)), size * 1.5, size, chips[math.floor(n * #chips) % #chips + 1], 0.05)
			chip.Rotation = (n - 0.5) * 80
			x += step * (0.6 + n * 0.8)
		end
	end
	box(holder, 0, 0, w, h * 0.3, a:Lerp(WHITE, 0.7), 0.6)
end

-- (v9.1) Mosaïque : petits carreaux en nuances (joints clairs)
FLOOR.Mosaic = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 9, 1.12)
	local frontW = rows[#rows].H * 1.1
	for index, row in ipairs(rows) do
		local cellW = cellWidth(frontW, row.K)
		local gap = math.max(1, 2 * u * row.K)
		local first, last = columns(w, cellW)
		local center = w / 2
		for j = first, last do
			local n = noise(j + 5, index)
			if n > 0.3 then
				local tone = a:Lerp(b, 0.35 + n * 0.65)
				if n > 0.93 then
					tone = WHITE
				end
				box(holder, center + j * cellW + gap / 2, row.Y + gap / 2, cellW - gap, row.H - gap, tone, 0)
			end
		end
	end
end

-- (v9.1) Gazon d'intérieur : bandes tondues + touffes et petites fleurs
FLOOR.Grass = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 8, 1.14)
	for index, row in ipairs(rows) do
		if index % 2 == 0 then
			box(holder, 0, row.Y, w, row.H, b, 0.45)
		end
		local step = (26 + 26 * row.K) * u
		local x = noise(index, 11) * step
		while x < w do
			local n = noise(x, index + 4)
			local tuft = (3 + 5 * row.K) * u
			local blade = box(holder, x, row.Y + row.H * 0.5 - tuft, math.max(1, 2 * u * row.K), tuft * 1.6, b:Lerp(BLACK, 0.18), 0.1)
			blade.Rotation = (n - 0.5) * 40
			if n > 0.86 then
				local petal = (4 + 4 * row.K) * u
				circle(holder, x + 6 * u, row.Y + row.H * 0.4, petal, petal, n > 0.93 and Color3.fromRGB(255, 190, 214) or WHITE, 0)
				circle(holder, x + 6 * u, row.Y + row.H * 0.4, petal * 0.4, petal * 0.4, Color3.fromRGB(255, 214, 110), 0)
			end
			x += step * (0.6 + n * 0.8)
		end
	end
	local _ = a
end

-- (v9.1) Nuages moelleux (sol) : gros nuages blancs en perspective
FLOOR.Clouds = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 4, 1.35)
	for index, row in ipairs(rows) do
		local width = (90 + 80 * row.K) * u
		local x = (index % 2) * width / 2 - width * 0.3
		while x < w + width do
			local n = noise(x, index)
			cloud(holder, x, row.Y + row.H * 0.95, width * (0.8 + n * 0.3), b, 0.1 + n * 0.2)
			x += width * 1.1
		end
	end
	local _ = a
end

-- (v9.1) Moquette étoilée : fond sombre (A) + étoiles et petits points (B)
FLOOR.Starry = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 7, 1.16)
	for index, row in ipairs(rows) do
		if index % 2 == 0 then
			box(holder, 0, row.Y, w, row.H, a:Lerp(WHITE, 0.08), 0.3)
		end
		local step = (50 + 50 * row.K) * u
		local x = noise(index, 2) * step
		while x < w do
			local n = noise(x, index + 9)
			if n > 0.45 then
				sparkle(holder, x, row.Y + row.H * 0.5, (6 + 10 * row.K * n) * u, b, 0.1)
			else
				circle(holder, x, row.Y + row.H * 0.5, (2 + 2 * row.K) * u, (2 + 2 * row.K) * u, b, 0.3)
			end
			x += step * (0.5 + n * 0.8)
		end
	end
end

----------------------------------------------------------------------
-- (v9.2) Sols "cool" : béton de skatepark, terrain de basket, pelouse de
-- foot, tôle à damier, route, roche de lave
----------------------------------------------------------------------

-- Béton : dalles (joints en perspective), mouchetures, traces de roues
FLOOR.Concrete = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 4, 1.3)
	local frontW = rows[#rows].H * 2.2
	for index, row in ipairs(rows) do
		local cellW = cellWidth(frontW, row.K)
		local first, last = columns(w, cellW, 0.5)
		local center = w / 2 + 0.5 * cellW
		for j = first, last do
			box(holder, center + j * cellW, row.Y, math.max(1, 2 * u * row.K), row.H, b, 0.35)
			if noise(j, index) > 0.7 then
				circle(holder, center + (j + 0.5) * cellW, row.Y + row.H * 0.5, cellW * 0.5, row.H * 0.5, b, 0.75)
			end
		end
		box(holder, 0, row.Y, w, math.max(1, 2 * u * row.K), b, 0.35)
		local step = (30 + 30 * row.K) * u
		local x = noise(index, 6) * step
		while x < w do
			local s = (1.5 + 1.5 * row.K) * u
			circle(holder, x, row.Y + row.H * noise(x, index), s, s, b:Lerp(BLACK, 0.2), 0.4)
			x += step * (0.5 + noise(x, 2))
		end
	end
	-- traces de roues de skate
	for index = 0, 1 do
		local trail = box(holder, w * (0.15 + index * 0.4), h * (0.5 + index * 0.2), w * 0.3, 2 * u, b:Lerp(BLACK, 0.3), 0.6)
		trail.Rotation = -6 + index * 10
		roundify(trail)
	end
end

-- Terrain de basket : parquet clair + lignes peintes (B) + raquette colorée
FLOOR.Court = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 7, 1.16)
	local frontL = rows[#rows].H * 5
	local seam = a:Lerp(BLACK, 0.18)
	for index, row in ipairs(rows) do
		local length = cellWidth(frontL, row.K)
		local phase = noise(index, 8)
		local first, last = columns(w, length, phase)
		local center = w / 2 + phase * length
		for j = first, last do
			local x = center + j * length
			if (j + index) % 2 == 0 then
				box(holder, x, row.Y, length, row.H, a:Lerp(WHITE, 0.12), 0.4)
			end
			box(holder, x, row.Y, math.max(1, 1.5 * u * row.K), row.H, seam, 0.4)
		end
		box(holder, 0, row.Y, w, math.max(1, 1.2 * u * row.K), seam, 0.45)
	end
	local thick = math.max(2, 4 * u)
	-- ligne de fond, ligne médiane, rond central, raquette
	local back = box(holder, 0, h * 0.14, w, thick, b, 0.05, 3)
	back.Size = UDim2.new(1, 0, 0, thick)
	box(holder, w / 2 - thick / 2, h * 0.14, thick, h * 0.86, b, 0.05, 3)
	local paint = box(holder, w / 2 - w * 0.13, h * 0.14, w * 0.26, h * 0.34, Color3.fromRGB(230, 90, 70), 0.25, 2)
	local _ = paint
	ring(holder, w / 2, h * 0.48, w * 0.2, h * 0.24, b, thick, 0.05, 3)
	ring(holder, w / 2, h * 0.14, w * 0.7, h * 1.3, b, thick, 0.1, 3)
end

-- Pelouse de foot : bandes tondues (clair / foncé) + lignes blanches
FLOOR.Turf = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 6, 1.2)
	local frontW = rows[#rows].H * 2.4
	for index, row in ipairs(rows) do
		local cellW = cellWidth(frontW, row.K)
		local first, last = columns(w, cellW)
		local center = w / 2
		for j = first, last do
			if j % 2 == 0 then
				box(holder, center + j * cellW, row.Y, cellW, row.H + 0.5, b, 0.2)
			end
		end
		local step = (20 + 24 * row.K) * u
		local x = noise(index, 13) * step
		while x < w do
			local tuft = (2 + 4 * row.K) * u
			local blade = box(holder, x, row.Y + row.H * 0.4, math.max(1, 1.6 * u * row.K), tuft * 1.5, b:Lerp(BLACK, 0.2), 0.3)
			blade.Rotation = (noise(x, index) - 0.5) * 40
			x += step * (0.6 + noise(x, index + 3) * 0.8)
		end
	end
	local thick = math.max(2, 4 * u)
	local line = box(holder, 0, h * 0.2, w, thick, WHITE, 0.05, 3)
	line.Size = UDim2.new(1, 0, 0, thick)
	box(holder, w / 2 - thick / 2, h * 0.2, thick, h * 0.8, WHITE, 0.05, 3)
	ring(holder, w / 2, h * 0.58, w * 0.24, h * 0.44, WHITE, thick, 0.05, 3)
	circle(holder, w / 2, h * 0.58, 8 * u, 5 * u, WHITE, 0, 3)
	local _ = a
end

-- Tôle à damier (métal) : petits reliefs en losange alternés, reflets
FLOOR.TreadPlate = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 9, 1.1)
	local frontW = rows[#rows].H * 1.3
	for index, row in ipairs(rows) do
		local cellW = cellWidth(frontW, row.K)
		local first, last = columns(w, cellW, (index % 2) * 0.5)
		local center = w / 2 + (index % 2) * 0.5 * cellW
		for j = first, last do
			local dash = box(holder, 0, 0, cellW * 0.55, math.max(2, row.H * 0.2), b, 0.1)
			dash.AnchorPoint = Vector2.new(0.5, 0.5)
			dash.Position = UDim2.fromOffset(center + (j + 0.5) * cellW, row.Y + row.H * 0.5)
			dash.Rotation = ((j + index) % 2 == 0) and 28 or -28
			roundify(dash)
		end
	end
	box(holder, 0, 0, w, h * 0.35, WHITE, 0.8)
	local _ = a
	local _u = u
end

-- Route : asphalte moucheté, bords blancs, tirets jaunes (B), passage piéton
FLOOR.Road = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 7, 1.15)
	for index, row in ipairs(rows) do
		local step = (26 + 26 * row.K) * u
		local x = noise(index, 17) * step
		while x < w do
			local s = (1.5 + 2 * row.K) * u
			circle(holder, x, row.Y + row.H * noise(x, index + 1), s, s, index % 2 == 0 and a:Lerp(WHITE, 0.25) or a:Lerp(BLACK, 0.25), 0.3)
			x += step * (0.5 + noise(x, index))
		end
	end
	local thick = math.max(2, 4 * u)
	for _, y in ipairs({ h * 0.1, h * 0.9 }) do
		local edge = box(holder, 0, y, w, thick * (y > h / 2 and 1.6 or 1), WHITE, 0.1, 3)
		edge.Size = UDim2.new(1, 0, 0, thick * (y > h / 2 and 1.6 or 1))
	end
	-- tirets au milieu (plus grands vers l'avant : rangée centrale)
	local dashW = 60 * u
	local x = dashW * 0.3
	while x < w do
		box(holder, x, h * 0.48, dashW, thick * 1.3, b, 0.05, 3)
		x += dashW * 2
	end
	-- passage piéton (bandes verticales qui s'élargissent vers l'avant)
	local cx = w * 0.78
	for index = -3, 3 do
		local top = h * 0.12
		local bar = box(holder, cx + index * 22 * u, top, 12 * u, h * 0.78 - top + h * 0.1, WHITE, 0.2, 2)
		bar.Rotation = index * 2
	end
end

-- Roche de lave : plaques sombres, fissures incandescentes (B) + lueurs
FLOOR.Lava = function(holder, w, h, a, b, u)
	local rows = perspectiveRows(h, 5, 1.25)
	for index, row in ipairs(rows) do
		local cellW = (80 + 90 * row.K) * u
		local x = noise(index, 21) * cellW - cellW
		while x < w + cellW do
			local n = noise(x, index)
			local rock = circle(holder, x + cellW / 2, row.Y + row.H / 2, cellW * 0.92, row.H * 0.9, a:Lerp(WHITE, 0.08 + n * 0.08), 0, 2)
			rock.Rotation = (n - 0.5) * 10
			-- fissure lumineuse entre deux plaques
			local crack = box(holder, x + cellW - 2 * u, row.Y + row.H * 0.1, math.max(2, 3 * u * row.K), row.H * 0.8, b, 0.05, 1)
			crack.Rotation = (n - 0.5) * 30
			if n > 0.6 then
				circle(holder, x + cellW, row.Y + row.H * 0.5, cellW * 0.4, row.H * 0.7, b, 0.7, 1)
			end
			x += cellW
		end
		box(holder, 0, row.Y, w, math.max(2, 2.5 * u * row.K), b, 0.25, 1)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

local function build(set, container: GuiObject, width: number, height: number, style: Style?, unit: number?)
	local holder = clear(container)
	local u = unit or 1
	if style then
		container.BackgroundColor3 = style.A
		local painter = set[style.Pattern] or set.Plain
		local ok, err = pcall(painter, holder, width, height, style.A, style.B, u)
		if not ok then
			warn("[HousePatterns] Motif " .. tostring(style.Pattern) .. " : " .. tostring(err))
		end
	end
	holder.Parent = container
end

-- Papier peint dans `container` (taille width x height, px de maquette)
function HousePatterns.BuildWall(container: GuiObject, width: number, height: number, style: Style?, unit: number?)
	build(WALL, container, width, height, style, unit)
end

-- Sol en perspective dans `container`
function HousePatterns.BuildFloor(container: GuiObject, width: number, height: number, style: Style?, unit: number?)
	build(FLOOR, container, width, height, style, unit)
end

-- Formes réutilisées par la pièce (détails dessinés à la main)
HousePatterns.Box = box
HousePatterns.Circle = circle
HousePatterns.Heart = heart
HousePatterns.Sparkle = sparkle
HousePatterns.Cloud = cloud
HousePatterns.Diamond = diamond
HousePatterns.Round = roundify

return HousePatterns
