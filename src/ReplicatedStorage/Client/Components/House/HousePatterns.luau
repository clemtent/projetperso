--[[
	HousePatterns (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HousePatterns

	Dessine les motifs des papiers peints et des sols UNIQUEMENT avec des
	Frames (pas d'image à importer) :
	  Murs : Plain (lambris), Stripes, Checker (vichy), Dots, Hearts, Stars
	         (étincelles), Clouds, Bricks, Wood (lambris de bois), Waves
	         (écailles / vaguelettes).
	  Sols : Plain, Checker, Wood, Tiles, Carpet, Marble, Herringbone
	         (parquet) — en PERSPECTIVE : les rangées grandissent vers
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
