--[[
	House3DFloor (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DFloor

	Motifs des sols de la vue 3D (House3D), dessinés À PLAT (vue de dessus) :
	dans la pièce 2D, HousePatterns dessine le sol déjà en perspective (les
	rangées grandissent vers l'avant) ; posé sur un vrai sol 3D, ce dessin
	aurait une double perspective. On reprend donc les mêmes motifs et les
	mêmes couleurs (A / B du style), mais en grille régulière : c'est la
	caméra 3D qui fait la perspective.
	  Motifs : Plain, Checker, Wood, Tiles, Carpet, Marble, Herringbone
	  (+ v9.1 : Terrazzo, Mosaic, Grass, Clouds, Starry ; v9.2 : Concrete,
	  Court, Turf, TreadPlate, Road, Lava ; motif inconnu = uni).
	  + la pelouse du socle (herbe, touffes et petites fleurs, comme la
	    pelouse sous la maison en 2D).
	Uniquement des Frames (comme HousePatterns) ; `container` doit couper
	son contenu (ClipsDescendants). Coordonnées en px de maquette.

	API :
	  House3DFloor.Paint(container, largeur, profondeur, style, unit?)
	  House3DFloor.Lawn(container, largeur, profondeur, bordure)
]]

local HousePatterns = require(script.Parent.HousePatterns)

local House3DFloor = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle
local Round = HousePatterns.Round

type Style = { Pattern: string, A: Color3, B: Color3 }
type Painter = (holder: Frame, w: number, h: number, a: Color3, b: Color3, u: number) -> ()

-- Pseudo-aléatoire stable (même dessin à chaque ouverture)
local function noise(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

local FLOOR: { [string]: Painter } = {}
local FLOWERS_3D = {
	Color3.fromRGB(255, 126, 182),
	Color3.fromRGB(255, 226, 130),
	WHITE,
	Color3.fromRGB(183, 148, 246),
}

-- Uni : grandes bandes douces + quelques reflets
FLOOR.Plain = function(holder, w, h, a, b, u)
	local band = 96 * u
	local index = 0
	local y = 0
	while y < h do
		if index % 2 == 1 then
			Box(holder, 0, y, w, band, b, 0.6)
		end
		y += band
		index += 1
	end
	for i = 1, 5 do
		local cx = w * (i / 6) + (noise(i, 2) - 0.5) * 60 * u
		local cy = h * (0.2 + 0.6 * noise(i, 3))
		Circle(holder, cx, cy, 130 * u, 60 * u, a:Lerp(WHITE, 0.6), 0.6)
	end
end

-- Damier (carreaux de 64 px) + léger reflet
FLOOR.Checker = function(holder, w, h, _a, b, u)
	local cell = 64 * u
	local rows = math.ceil(h / cell)
	local cols = math.ceil(w / cell)
	-- (centré : la pièce commence et finit sur des demi-carreaux réguliers)
	local ox = (w - cols * cell) / 2
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			if (row + col) % 2 == 0 then
				Box(holder, ox + col * cell, row * cell, cell, cell + 0.5, b)
			end
		end
	end
	Box(holder, 0, 0, w, h * 0.3, WHITE, 0.9)
end

-- Parquet : lames horizontales, joints décalés, nuances et veines
FLOOR.Wood = function(holder, w, h, a, b, u)
	local row = 30 * u
	local seam = b:Lerp(BLACK, 0.2)
	local index = 0
	local y = 0
	while y < h do
		local x = -noise(index, 1) * 200 * u
		local plank = 0
		while x < w do
			local length = (170 + noise(index, plank) * 110) * u
			if (plank + index) % 2 == 0 then
				Box(holder, x, y, length, row, b, 0.5)
			end
			Box(holder, x, y, math.max(1, 2 * u), row, seam, 0.3)
			if noise(plank + 3, index) > 0.55 then
				Box(holder, x + length * 0.2, y + row * 0.45, length * 0.4, math.max(1, 1.2 * u), a:Lerp(b, 0.8), 0.45)
			end
			x += length
			plank += 1
		end
		Box(holder, 0, y, w, math.max(1, 2 * u), seam, 0.3)
		y += row
		index += 1
	end
end

-- Carrelage : joints couleur B, reflets dans quelques carreaux
FLOOR.Tiles = function(holder, w, h, _a, b, u)
	local cell = 70 * u
	local grout = 3 * u
	local x = (w % cell) / 2
	local col = 0
	while x < w do
		local line = Box(holder, x - grout / 2, 0, grout, h, b)
		line.Size = UDim2.new(0, grout, 1, 0)
		x += cell
		col += 1
	end
	local y = 0
	local row = 0
	while y < h do
		Box(holder, 0, y - grout / 2, w, grout, b)
		local cx = (w % cell) / 2
		local index = 0
		while cx < w do
			if (row + index) % 3 == 0 then
				local shine = Box(holder, cx + cell * 0.14, y + cell * 0.14, cell * 0.26, 4 * u, WHITE, 0.45)
				Round(shine)
			end
			cx += cell
			index += 1
		end
		y += cell
		row += 1
	end
end

-- Moquette : bandes douces + petites touffes
FLOOR.Carpet = function(holder, w, h, a, b, u)
	local band = 44 * u
	local index = 0
	local y = 0
	while y < h do
		if index % 2 == 0 then
			Box(holder, 0, y, w, band, b, 0.35)
		else
			local step = 70 * u
			local x = noise(index, 9) * step
			while x < w do
				local size = (5 + 3 * noise(x, index)) * u
				Circle(holder, x, y + band * 0.5, size * 1.8, size, a:Lerp(WHITE, 0.45), 0.35)
				x += step * (0.8 + noise(x, index) * 0.6)
			end
		end
		y += band
		index += 1
	end
end

-- Marbre : grandes dalles + veines fines
FLOOR.Marble = function(holder, w, h, a, b, u)
	local cell = 150 * u
	local vein = b:Lerp(BLACK, 0.12)
	local row = 0
	local y = 0
	while y < h do
		local col = 0
		local x = (w % cell) / 2 - cell
		while x < w do
			if (row + col) % 2 == 0 then
				Box(holder, x, y, cell, cell, b, 0.7)
			end
			Box(holder, x, y, math.max(1, 1.5 * u), cell, vein, 0.45)
			local n = noise(col + 11, row)
			local length = cell * (0.4 + 0.3 * n)
			local line = Box(holder, 0, 0, length, math.max(1, 1.4 * u), vein, 0.35)
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromOffset(x + cell * (0.35 + 0.3 * n), y + cell * (0.3 + 0.4 * noise(row, col)))
			line.Rotation = (n - 0.5) * 70
			x += cell
			col += 1
		end
		Box(holder, 0, y, w, math.max(1, 1.5 * u), vein, 0.45)
		y += cell
		row += 1
	end
	Box(holder, 0, 0, w, h * 0.25, a:Lerp(WHITE, 0.8), 0.6)
end

-- Bâtons rompus : blocs de 2 lames, alternés horizontal / vertical
FLOOR.Herringbone = function(holder, w, h, a, b, u)
	local cell = 52 * u
	local seam = b:Lerp(BLACK, 0.25)
	local alt = a:Lerp(b, 0.55)
	local gap = math.max(1, 1.6 * u)
	local row = 0
	local y = 0
	while y < h do
		local col = 0
		local x = (w % cell) / 2 - cell
		while x < w do
			local horizontal = (row + col) % 2 == 0
			local block = Box(holder, x + gap / 2, y + gap / 2, cell - gap, cell - gap, horizontal and a or alt)
			if horizontal then
				Box(block, 0, (cell - gap) / 2 - gap / 2, cell - gap, gap, seam, 0.3)
			else
				Box(block, (cell - gap) / 2 - gap / 2, 0, gap, cell - gap, seam, 0.3)
			end
			x += cell
			col += 1
		end
		y += cell
		row += 1
	end
end

-- v9.1 : Terrazzo (éclats colorés), Mosaic (petits carreaux), Grass (herbe),
-- Clouds (nuages), Starry (ciel étoilé)
FLOOR.Terrazzo = function(holder, w, h, a, b, u)
	local chips = { b, b:Lerp(WHITE, 0.4), a:Lerp(BLACK, 0.18), Color3.fromRGB(255, 170, 190), Color3.fromRGB(150, 205, 255) }
	local step = 26 * u
	local index = 0
	local y = step / 2
	while y < h do
		local x = step / 2 + noise(index, 1) * step
		while x < w do
			index += 1
			local size = (5 + 7 * noise(index, 2)) * u
			local chip = Box(holder, x, y + (noise(index, 3) - 0.5) * step, size * 1.4, size, chips[index % #chips + 1], 0.1)
			chip.Rotation = noise(index, 4) * 180
			Round(chip, UDim.new(0.35, 0))
			x += step * (0.7 + noise(index, 5) * 0.8)
		end
		y += step
	end
end

FLOOR.Mosaic = function(holder, w, h, a, b, u)
	local cell = 22 * u
	local colors = { a, b, a:Lerp(b, 0.5), b:Lerp(WHITE, 0.35) }
	local row = 0
	local y = 0
	while y < h do
		local col = 0
		local x = 0
		while x < w do
			local color = colors[(row * 3 + col + math.floor(noise(row, col) * 3)) % #colors + 1]
			Box(holder, x + 1 * u, y + 1 * u, cell - 2 * u, cell - 2 * u, color, 0)
			x += cell
			col += 1
		end
		y += cell
		row += 1
	end
end

FLOOR.Grass = function(holder, w, h, a, b, u)
	local step = 34 * u
	local index = 0
	local y = step / 2
	while y < h do
		local x = noise(index, 7) * step
		while x < w do
			index += 1
			Circle(holder, x, y, step * 0.7, step * 0.34, index % 2 == 0 and b or a:Lerp(b, 0.5), 0.25)
			if noise(index, 8) > 0.82 then
				local petal = FLOWERS_3D[index % #FLOWERS_3D + 1]
				Circle(holder, x + step * 0.2, y - step * 0.1, 7 * u, 7 * u, petal, 0, 2)
			end
			x += step * (0.6 + noise(index, 9) * 0.7)
		end
		y += step * 0.7
	end
end

FLOOR.Clouds = function(holder, w, h, a, b, u)
	local step = 150 * u
	local index = 0
	local y = step * 0.4
	while y < h + step * 0.3 do
		local x = (index % 2) * step * 0.5
		while x < w + step * 0.3 do
			index += 1
			HousePatterns.Cloud(holder, x, y, step * (0.55 + noise(index, 1) * 0.25), b, 0.25, 1)
			x += step
		end
		y += step * 0.6
	end
	Box(holder, 0, 0, w, h, a:Lerp(WHITE, 0.6), 0.85)
end

FLOOR.Starry = function(holder, w, h, a, b, u)
	local step = 60 * u
	local index = 0
	local y = step / 2
	while y < h do
		local x = noise(index, 3) * step
		while x < w do
			index += 1
			local size = (8 + 10 * noise(index, 4)) * u
			HousePatterns.Sparkle(holder, x, y + (noise(index, 5) - 0.5) * step * 0.6, size, b, 0.1, 2)
			if noise(index, 6) > 0.6 then
				Circle(holder, x + step * 0.4, y + step * 0.25, 3 * u, 3 * u, a:Lerp(WHITE, 0.7), 0.2, 2)
			end
			x += step * (0.7 + noise(index, 7) * 0.8)
		end
		y += step * 0.8
	end
end

-- v9.2 : sols "sport / gamer" (vus de dessus, la caméra 3D fait la perspective)
-- Anneau (contour seul) centré
local function ring(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, thickness: number, z: number?): Frame
	local frame = Box(parent, cx - w / 2, cy - h / 2, w, h, color, 1, z)
	Round(frame)
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = frame
	return frame
end

-- Béton : grandes dalles, joints, mouchetures, quelques fissures
FLOOR.Concrete = function(holder, w, h, a, b, u)
	local cell = 140 * u
	local seam = b:Lerp(BLACK, 0.15)
	local x = (w % cell) / 2
	while x < w do
		Box(holder, x, 0, math.max(1, 2 * u), h, seam, 0.35)
		x += cell
	end
	local y = cell * 0.6
	while y < h do
		Box(holder, 0, y, w, math.max(1, 2 * u), seam, 0.35)
		y += cell
	end
	for index = 1, math.floor(w * h / (900 * u * u)) do
		local size = (2 + 3 * noise(index, 1)) * u
		Circle(holder, noise(index, 2) * w, noise(index, 3) * h, size, size, index % 3 == 0 and a:Lerp(WHITE, 0.4) or b, 0.45)
	end
	for index = 1, 6 do
		local crack = Box(holder, noise(index, 4) * w, noise(index, 5) * h, (40 + 50 * noise(index, 6)) * u, math.max(1, 1.2 * u), seam, 0.3)
		crack.Rotation = (noise(index, 7) - 0.5) * 120
	end
end

-- Terrain de basket : parquet + lignes blanches (bords, milieu, rond central, raquettes)
FLOOR.Court = function(holder, w, h, a, b, u)
	FLOOR.Wood(holder, w, h, a, a:Lerp(BLACK, 0.08), u)
	local line = math.max(2, 5 * u)
	local m = 24 * u
	local frame = Box(holder, m, m, w - 2 * m, h - 2 * m, b, 1, 3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = b
	stroke.Thickness = line
	stroke.Parent = frame
	Box(holder, w / 2 - line / 2, m, line, h - 2 * m, b, 0, 3)
	ring(holder, w / 2, h / 2, 130 * u, 130 * u, b, line, 3)
	Circle(holder, w / 2, h / 2, 36 * u, 36 * u, Color3.fromRGB(240, 110, 60), 0.1, 3)
	for _, side in ipairs({ -1, 1 }) do
		local keyW, keyH = 150 * u, 150 * u
		local kx = side < 0 and m or w - m - keyW
		Box(holder, kx, h / 2 - keyH / 2, keyW, keyH, Color3.fromRGB(240, 110, 60), 0.55, 2)
		local key = Box(holder, kx, h / 2 - keyH / 2, keyW, keyH, b, 1, 3)
		local keyStroke = Instance.new("UIStroke")
		keyStroke.Color = b
		keyStroke.Thickness = line
		keyStroke.Parent = key
		ring(holder, side < 0 and m + keyW or w - m - keyW, h / 2, 110 * u, 110 * u, b, line, 3)
		ring(holder, side < 0 and m or w - m, h / 2, 520 * u, h * 0.86, b, line, 3)
	end
end

-- Pelouse de foot : bandes de tonte, lignes blanches, rond central
FLOOR.Turf = function(holder, w, h, a, b, u)
	local band = 60 * u
	local x = 0
	local index = 0
	while x < w do
		Box(holder, x, 0, band, h, index % 2 == 0 and b or a:Lerp(WHITE, 0.08), index % 2 == 0 and 0.2 or 0.5)
		x += band
		index += 1
	end
	local white = Color3.fromRGB(250, 252, 255)
	local line = math.max(2, 4 * u)
	local m = 20 * u
	local frame = Box(holder, m, m, w - 2 * m, h - 2 * m, white, 1, 3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = white
	stroke.Thickness = line
	stroke.Parent = frame
	Box(holder, w / 2 - line / 2, m, line, h - 2 * m, white, 0, 3)
	ring(holder, w / 2, h / 2, 150 * u, 150 * u, white, line, 3)
	Circle(holder, w / 2, h / 2, 10 * u, 10 * u, white, 0, 3)
	for _, side in ipairs({ -1, 1 }) do
		local bw, bh = 120 * u, 230 * u
		local box = Box(holder, side < 0 and m or w - m - bw, h / 2 - bh / 2, bw, bh, white, 1, 3)
		local boxStroke = Instance.new("UIStroke")
		boxStroke.Color = white
		boxStroke.Thickness = line
		boxStroke.Parent = box
	end
end

-- Tôle larmée : petits reliefs en diagonale, alternés
FLOOR.TreadPlate = function(holder, w, h, a, b, u)
	local step = 26 * u
	local row = 0
	local y = step / 2
	while y < h do
		local col = 0
		local x = step / 2
		while x < w do
			local bar = Box(holder, x - 7 * u, y - 2 * u, 14 * u, 4 * u, (row + col) % 2 == 0 and b or a:Lerp(WHITE, 0.3), 0.1)
			bar.Rotation = (row + col) % 2 == 0 and 45 or -45
			Round(bar)
			x += step
			col += 1
		end
		y += step
		row += 1
	end
	Box(holder, 0, 0, w, h * 0.3, WHITE, 0.88)
end

-- Route : asphalte, pointillés jaunes au milieu, bords blancs, passage piéton
FLOOR.Road = function(holder, w, h, a, b, u)
	for index = 1, math.floor(w * h / (700 * u * u)) do
		local size = (2 + 2 * noise(index, 1)) * u
		Circle(holder, noise(index, 2) * w, noise(index, 3) * h, size, size, a:Lerp(WHITE, 0.2 + 0.2 * noise(index, 4)), 0.4)
	end
	local white = Color3.fromRGB(245, 245, 245)
	Box(holder, 0, 18 * u, w, 5 * u, white, 0.1, 2)
	Box(holder, 0, h - 23 * u, w, 5 * u, white, 0.1, 2)
	local x = 20 * u
	while x < w do
		Box(holder, x, h / 2 - 4 * u, 50 * u, 8 * u, b, 0, 2)
		x += 90 * u
	end
	local cross = w * 0.72
	for index = 0, 6 do
		Box(holder, cross, 34 * u + index * (h - 68 * u) / 7, 70 * u, (h - 68 * u) / 14, white, 0.05, 3)
	end
end

-- Lave : roche sombre en plaques, fissures et flaques qui brillent
FLOOR.Lava = function(holder, w, h, a, b, u)
	local glow = b:Lerp(Color3.fromRGB(255, 220, 90), 0.35)
	for index = 1, 26 do
		local cx, cy = noise(index, 1) * w, noise(index, 2) * h
		local length = (60 + 90 * noise(index, 3)) * u
		local crack = Box(holder, cx, cy, length, (3 + 3 * noise(index, 4)) * u, b, 0, 2)
		crack.Rotation = noise(index, 5) * 180
		Round(crack)
		local core = Box(holder, cx + length * 0.2, cy, length * 0.5, 1.5 * u, glow, 0, 3)
		core.Rotation = crack.Rotation
	end
	for index = 1, 8 do
		local size = (26 + 30 * noise(index, 6)) * u
		local pool = Circle(holder, noise(index, 7) * w, noise(index, 8) * h, size * 1.4, size, b, 0.05, 2)
		pool.Name = "Pool"
		Circle(holder, noise(index, 7) * w, noise(index, 8) * h, size * 0.8, size * 0.5, glow, 0, 3)
	end
	for index = 1, 30 do
		local size = (5 + 6 * noise(index, 9)) * u
		Circle(holder, noise(index, 10) * w, noise(index, 11) * h, size, size, a:Lerp(WHITE, 0.12), 0.3)
	end
end

-- Sol à plat dans `container` (largeur x profondeur en px de maquette) ;
-- le haut du conteneur = le fond de la pièce (côté mur)
function House3DFloor.Paint(container: Frame, width: number, depth: number, style: Style?, unit: number?)
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
	if style then
		container.BackgroundColor3 = style.A
		local painter = FLOOR[style.Pattern] or FLOOR.Plain
		local ok, err = pcall(painter, holder, width, depth, style.A, style.B, unit or 1)
		if not ok then
			warn("[House3DFloor] Motif " .. tostring(style.Pattern) .. " : " .. tostring(err))
		end
	end
	holder.Parent = container
end

-- Pelouse du socle (px de la toile) : herbe en dégradé, touffes, fleurs le
-- long des bords (`border` = largeur de la bande visible autour de la pièce)
local GRASS = Color3.fromRGB(150, 222, 150)
local GRASS_DARK = Color3.fromRGB(108, 190, 118)
local FLOWERS = {
	Color3.fromRGB(255, 126, 182),
	Color3.fromRGB(255, 226, 130),
	WHITE,
	Color3.fromRGB(183, 148, 246),
}

function House3DFloor.Lawn(container: Frame, width: number, depth: number, border: number)
	container.BackgroundColor3 = GRASS
	local shade = Box(container, 0, 0, width, depth, WHITE, 0, 1)
	shade.Size = UDim2.fromScale(1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(170, 232, 168), Color3.fromRGB(136, 208, 140))
	gradient.Parent = shade
	-- Touffes d'herbe et fleurs sur toute la bordure (le milieu est sous la maison)
	local step = math.max(10, border * 0.55)
	local index = 0
	local function spot(x: number, y: number)
		index += 1
		local n = noise(index, 4)
		Circle(container, x, y, step * 0.55, step * 0.32, GRASS:Lerp(GRASS_DARK, 0.4 + n * 0.3), 0.15, 2)
		if n > 0.45 then
			local petal = FLOWERS[index % #FLOWERS + 1]
			local r = step * 0.1
			local fx = x + step * 0.3
			local fy = y - step * 0.05
			for _, d in ipairs({ Vector2.new(-1, 0), Vector2.new(1, 0), Vector2.new(0, -1), Vector2.new(0, 1) }) do
				Circle(container, fx + d.X * r, fy + d.Y * r, r * 1.6, r * 1.6, petal, 0, 3)
			end
			Circle(container, fx, fy, r * 1.1, r * 1.1, Color3.fromRGB(255, 200, 120), 0, 4)
		end
	end
	local x = step * 0.5
	while x < width do
		spot(x + (noise(x, 1) - 0.5) * step * 0.4, border * (0.3 + 0.4 * noise(x, 2)))
		spot(x + (noise(x, 3) - 0.5) * step * 0.4, depth - border * (0.3 + 0.4 * noise(x, 5)))
		x += step
	end
	local y = border
	while y < depth - border do
		spot(border * (0.3 + 0.4 * noise(y, 6)), y)
		spot(width - border * (0.3 + 0.4 * noise(y, 7)), y)
		y += step
	end
end

return House3DFloor
