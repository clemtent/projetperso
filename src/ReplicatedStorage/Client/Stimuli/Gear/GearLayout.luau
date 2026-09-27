--[[
	GearLayout (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > GearLayout

	Range les accessoires de clic possédés (doigt, clavier, souris, tour de
	force du Méga doigt, clavier corail, cerveau du Neural Link...) dans l'espace
	LIBRE autour de la colonne centrale, sans jamais recouvrir :
	  - les cartes des stimuli (calque Slots, bandeau d'actu compris) ;
	  - le bouton "Click me" (+ chapeau / robot), le bouton 🏠, les pastilles
	    VIP / bonus / boost, le compteur de Dopamine, la ligne "par seconde",
	    les pastilles des menus, la jauge de combo, la barre d'améliorations ;
	  - les objets marqués par l'attribut LayoutObstacle = true dans les calques
	    Overlay / Background (convention partagée avec les autres stimuli) ;
	  - les autres accessoires (jamais deux accessoires l'un sur l'autre).

	Principe : une grille de cases de 8 px "design" marque ce qui est occupé
	(avec une marge), une table de sommes cumulées répond en O(1) "ce rectangle
	est-il libre ?". Chaque accessoire (par ordre de priorité) cherche la place
	libre la plus proche de son point préféré, à la plus grande taille possible
	(il rétrécit jusqu'à MinScale s'il le faut, puis jusqu'à 25 % en dernier
	recours ; sinon il est caché). Un accessoire garde sa place tant qu'elle
	reste valable (pas de sauts inutiles) ; tout est recalculé quand l'écran
	change (téléphone / tablette / rotation).

	Déclencheurs : inscription d'un accessoire, Features qui changent (nouvelle
	carte), Slots.Changed / changement d'échelle ou d'appareil, et une petite
	vérification toutes les 1,2 s (compteur qui s'allonge, pastille de boost
	qui apparaît...). Aucun calcul image par image.

	API :
	  GearLayout.Register(id, spec)   spec = {
	      Size = Vector2 (taille à l'échelle 1, pixels "design"),
	      Priority = number (plus petit = placé d'abord),
	      Anchor = function(button: Rect, canvas: Vector2): Vector2 (centre préféré),
	      MinScale, MaxScale, Near (écart max. avec le bouton, en px, facultatif),
	      OnPlace = function(placement | nil) }
	  GearLayout.Unregister(id)
	  GearLayout.GetPlacement(id) -> placement | nil
	  GearLayout.Changed : Signal (id, placement | nil)
	  placement = { CX, CY, Scale, W, H, Rect, Button (rectangle du bouton) }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local Slots = require(Client.Slots)
local Signal = require(ReplicatedStorage.Shared.Signal)
local GearKit = require(script.Parent.GearKit)

type Rect = GearKit.Rect

export type Placement = {
	CX: number,
	CY: number,
	Scale: number,
	W: number,
	H: number,
	Rect: Rect,
	Button: Rect,
}

export type Spec = {
	Size: Vector2,
	Priority: number,
	Anchor: (button: Rect, canvas: Vector2) -> Vector2,
	MinScale: number?,
	MaxScale: number?,
	Near: number?,
	OnPlace: (placement: Placement?) -> (),
}

type Piece = { Id: string, Spec: Spec, Placement: Placement? }

local GearLayout = {}
GearLayout.Changed = Signal.new() -- (id, placement | nil)

local CELL = 8 -- taille d'une case de la grille (pixels "design")
local MARGIN = 7 -- espace laissé autour des obstacles quand on place (grille)
local EXACT_MARGIN = 6 -- même chose au pixel près (affinage)
local KEEP_MARGIN = 1 -- tolérance pour garder une place déjà prise (évite les sauts)
local PIECE_GAP = 6 -- espace entre deux accessoires
local EDGE = 6 -- marge au bord de l'écran
local SIZE_PENALTY = 300 -- "coût" (en px de distance) d'un accessoire 2x plus petit ... x2
local CHECK_INTERVAL = 1.2
local LAST_RESORT_SCALE = 0.25

local pieces: { [string]: Piece } = {}
local running = false
local generation = 0
local scheduled = false
local forceNext = false
local connections: { any } = {}
local lastButton: Rect? = nil
local lastCanvas: Vector2? = nil
local checkCount = 0

----------------------------------------------------------------------
-- Obstacles (rectangles sur la toile)
----------------------------------------------------------------------

local function validRect(rect: Rect): boolean
	return rect.X1 - rect.X0 > 0.5 and rect.Y1 - rect.Y0 > 0.5
end

local function inflate(rect: Rect, left: number, top: number, right: number?, bottom: number?): Rect
	return {
		X0 = rect.X0 - left,
		Y0 = rect.Y0 - top,
		X1 = rect.X1 + (right or left),
		Y1 = rect.Y1 + (bottom or top),
	}
end

local function union(a: Rect?, b: Rect): Rect
	if not a then
		return b
	end
	return {
		X0 = math.min(a.X0, b.X0),
		Y0 = math.min(a.Y0, b.Y0),
		X1 = math.max(a.X1, b.X1),
		Y1 = math.max(a.Y1, b.Y1),
	}
end

local function addObject(list: { Rect }, object: Instance, left: number?, top: number?, right: number?, bottom: number?)
	if not object:IsA("GuiObject") or not object.Visible then
		return
	end
	local rect = GearKit.CanvasRect(object)
	if validRect(rect) then
		table.insert(list, inflate(rect, left or 0, top or 0, right, bottom))
	end
end

-- Rectangle FINAL d'un cadre de slot (même pendant son animation "pop") :
-- on retrouve son emplacement par sa position, puis taille x échelle du slot
local function slotRect(frame: GuiObject): Rect
	local rect = GearKit.CanvasRect(frame)
	local ok, name = pcall(function()
		for slotName in pairs(Slots.Definitions) do
			local position = Slots.GetPlacement(slotName)
			if position == frame.Position then
				return slotName
			end
		end
		return nil
	end)
	if ok and name and frame.Size.X.Scale == 0 then
		local scale = Slots.GetScale(name)
		local cx, cy = (rect.X0 + rect.X1) / 2, (rect.Y0 + rect.Y1) / 2
		local w, h = frame.Size.X.Offset * scale, frame.Size.Y.Offset * scale
		return { X0 = cx - w / 2, Y0 = cy - h / 2, X1 = cx + w / 2, Y1 = cy + h / 2 }
	end
	return rect
end

-- Colonne centrale : chaque élément visible (pas le grand cadre transparent)
local function collectColumn(list: { Rect }, column: Instance)
	for _, child in ipairs(column:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			local name = child.Name
			if name == "Stack" then
				for _, item in ipairs(child:GetChildren()) do
					if item:IsA("GuiObject") and item.Visible then
						if item.Name == "Counter" then
							-- Le nombre + "Dopamine" (avec de la place pour grandir)
							local counted = false
							for _, label in ipairs(item:GetChildren()) do
								if label:IsA("GuiObject") and label.Visible then
									counted = true
									addObject(list, label, 22, 2)
								end
							end
							if not counted then
								addObject(list, item)
							end
						elseif item.Name == "Pills" and not item:IsA("ScrollingFrame") then
							-- Rangée des menus : seulement les pastilles visibles
							local box: Rect? = nil
							for _, pill in ipairs(item:GetChildren()) do
								if pill:IsA("GuiObject") and pill.Visible then
									local rect = GearKit.CanvasRect(pill)
									if validRect(rect) then
										box = union(box, rect)
									end
								end
							end
							if box then
								table.insert(list, inflate(box, 4, 2))
							else
								addObject(list, item)
							end
						else
							addObject(list, item)
							-- Enfants qui dépassent (bandeau Rush sur la ligne "par seconde"...)
							for _, sub in ipairs(item:GetChildren()) do
								if sub:IsA("GuiObject") and sub.Visible and sub.ZIndex > 1 then
									addObject(list, sub)
								end
							end
						end
					end
				end
			elseif name == "ClickerHolder" then
				addObject(list, child, 2, 2)
				for _, sub in ipairs(child:GetChildren()) do
					if sub:IsA("GuiObject") and sub.Visible and sub.Name ~= "ClickButton" and not string.find(sub.Name, "Shadow") then
						addObject(list, sub) -- chapeau, robot de l'auto-clic
					end
				end
			elseif name == "StatusLeft" then
				for _, chip in ipairs(child:GetChildren()) do
					addObject(list, chip, 2, 2)
				end
			elseif name == "HouseHolder" then
				-- Le badge "99+" déborde en haut à droite
				addObject(list, child, 2, 10, 16, 2)
			else
				addObject(list, child)
			end
		end
	end
end

-- Objets persistants connus des autres stimuli plein écran (sans attribut)
local KNOWN_OVERLAY = {
	Disco = { "Ball" }, -- boule disco accrochée au bandeau d'actu
}

-- Objets marqués LayoutObstacle = true dans un calque plein écran (hors accessoires)
local function collectMarked(list: { Rect }, layer: Instance?)
	if not layer then
		return
	end
	for containerName, names in pairs(KNOWN_OVERLAY) do
		local container = layer:FindFirstChild(containerName)
		if container and container:IsA("GuiObject") and container.Visible then
			for _, name in ipairs(names) do
				local item = container:FindFirstChild(name, true)
				if item then
					addObject(list, item, 10, 10)
				end
			end
		end
	end
	for _, container in ipairs(layer:GetChildren()) do
		if container:IsA("GuiObject") and container.Visible then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("GuiObject") and item.Visible and item:GetAttribute("LayoutObstacle") == true
					and not string.find(item.Name, "^Gear_") then
					addObject(list, item)
				end
				for _, sub in ipairs(item:GetChildren()) do
					if sub:IsA("GuiObject") and sub.Visible and sub:GetAttribute("LayoutObstacle") == true
						and not string.find(sub.Name, "^Gear_") then
						addObject(list, sub)
					end
				end
			end
		end
	end
end

local function collectObstacles(canvas: Vector2): { Rect }
	local list: { Rect } = {}
	local layers = Interface.Layers
	if not layers then
		return list
	end
	local slots = layers.Slots
	if slots then
		for _, frame in ipairs(slots:GetChildren()) do
			if frame:IsA("GuiObject") and frame.Visible then
				local rect = slotRect(frame)
				if validRect(rect) then
					table.insert(list, rect)
				end
			end
		end
	end
	local main = layers.Main
	if main then
		for _, child in ipairs(main:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				if child.Name == "CenterColumn" then
					collectColumn(list, child)
				else
					local rect = GearKit.CanvasRect(child)
					-- (les cadres plein écran ne sont pas des obstacles)
					if validRect(rect) and (rect.X1 - rect.X0) < canvas.X * 0.9 then
						table.insert(list, rect)
					end
				end
			end
		end
	end
	collectMarked(list, layers.Overlay)
	collectMarked(list, layers.Background)
	return list
end

local function intersects(a: Rect, b: Rect, margin: number): boolean
	return a.X0 < b.X1 + margin and b.X0 < a.X1 + margin and a.Y0 < b.Y1 + margin and b.Y0 < a.Y1 + margin
end

----------------------------------------------------------------------
-- Grille d'occupation + sommes cumulées
----------------------------------------------------------------------

type Grid = {
	Cols: number,
	Rows: number,
	Occ: { number },
	Sat: { number },
}

local function newGrid(canvas: Vector2): Grid
	local cols = math.max(1, math.ceil(canvas.X / CELL))
	local rows = math.max(1, math.ceil(canvas.Y / CELL))
	return { Cols = cols, Rows = rows, Occ = table.create(cols * rows, 0), Sat = {} }
end

local function markRect(grid: Grid, x0: number, y0: number, x1: number, y1: number)
	local cols, rows = grid.Cols, grid.Rows
	local c0 = math.max(0, math.floor(x0 / CELL))
	local c1 = math.min(cols - 1, math.ceil(x1 / CELL) - 1)
	local r0 = math.max(0, math.floor(y0 / CELL))
	local r1 = math.min(rows - 1, math.ceil(y1 / CELL) - 1)
	local occ = grid.Occ
	for r = r0, r1 do
		local base = r * cols
		for c = c0, c1 do
			occ[base + c + 1] = 1
		end
	end
end

local function buildSat(grid: Grid)
	local cols, rows = grid.Cols, grid.Rows
	local width = cols + 1
	local sat = table.create((rows + 1) * width, 0)
	local occ = grid.Occ
	for r = 1, rows do
		local rowSum = 0
		local occBase = (r - 1) * cols
		local base = r * width
		local previous = (r - 1) * width
		for c = 1, cols do
			rowSum += occ[occBase + c]
			sat[base + c + 1] = sat[previous + c + 1] + rowSum
		end
	end
	grid.Sat = sat
end

-- Vrai si le bloc de cases [c0, c0 + cw[ x [r0, r0 + ch[ est entièrement libre
local function isFree(grid: Grid, c0: number, r0: number, cw: number, ch: number): boolean
	if c0 < 0 or r0 < 0 or c0 + cw > grid.Cols or r0 + ch > grid.Rows then
		return false
	end
	local width = grid.Cols + 1
	local sat = grid.Sat
	local a = sat[r0 * width + c0 + 1]
	local b = sat[r0 * width + c0 + cw + 1]
	local c = sat[(r0 + ch) * width + c0 + 1]
	local d = sat[(r0 + ch) * width + c0 + cw + 1]
	return d - b - c + a == 0
end

----------------------------------------------------------------------
-- Recherche d'une place
----------------------------------------------------------------------

local function makePlacement(cx: number, cy: number, scale: number, spec: Spec, button: Rect): Placement
	local w, h = spec.Size.X * scale, spec.Size.Y * scale
	return {
		CX = cx,
		CY = cy,
		Scale = scale,
		W = w,
		H = h,
		Rect = { X0 = cx - w / 2, Y0 = cy - h / 2, X1 = cx + w / 2, Y1 = cy + h / 2 },
		Button = button,
	}
end

-- Meilleure place pour `spec` entre les échelles maxScale et minScale (nil si aucune)
local function search(grid: Grid, spec: Spec, button: Rect, canvas: Vector2, maxScale: number, minScale: number, near: number?): Placement?
	local anchor = spec.Anchor(button, canvas)
	local bestCost = math.huge
	local best: Placement? = nil
	local scale = maxScale
	while scale >= minScale - 1e-4 do
		local penalty = (1 - scale / maxScale) * SIZE_PENALTY
		if penalty >= bestCost then
			break
		end
		local w, h = spec.Size.X * scale, spec.Size.Y * scale
		local cw, ch = math.max(1, math.ceil(w / CELL)), math.max(1, math.ceil(h / CELL))
		-- Zone de recherche (limitée autour du bouton si Near)
		local cMin, cMax = 0, grid.Cols - cw
		local rMin, rMax = 0, grid.Rows - ch
		if near then
			cMin = math.max(cMin, math.floor((button.X0 - near - w) / CELL) - 1)
			cMax = math.min(cMax, math.ceil((button.X1 + near) / CELL) + 1)
			rMin = math.max(rMin, math.floor((button.Y0 - near - h) / CELL) - 1)
			rMax = math.min(rMax, math.ceil((button.Y1 + near) / CELL) + 1)
		end
		local foundHere: { number }? = nil
		local function try(c0: number, r0: number)
			local cx = (c0 + cw / 2) * CELL
			local cy = (r0 + ch / 2) * CELL
			local dx, dy = cx - anchor.X, cy - anchor.Y
			local cost = math.sqrt(dx * dx + dy * dy) + penalty
			if cost < bestCost and isFree(grid, c0, r0, cw, ch) then
				if near then
					local rect = { X0 = cx - w / 2, Y0 = cy - h / 2, X1 = cx + w / 2, Y1 = cy + h / 2 }
					if GearKit.RectGap(rect, button) > near then
						return
					end
				end
				bestCost = cost
				best = makePlacement(cx, cy, scale, spec, button)
				foundHere = { c0, r0 }
			end
		end
		-- Passe grossière (1 case sur 2), puis affinage autour du meilleur
		for r0 = rMin, rMax, 2 do
			for c0 = cMin, cMax, 2 do
				try(c0, r0)
			end
		end
		local found = foundHere
		if found then
			for r0 = found[2] - 2, found[2] + 2 do
				for c0 = found[1] - 2, found[1] + 2 do
					if r0 >= rMin and r0 <= rMax and c0 >= cMin and c0 <= cMax then
						try(c0, r0)
					end
				end
			end
		end
		scale *= 0.9
	end
	return best
end

-- Test exact (sans grille) : rectangle libre ?
local function exactFree(rect: Rect, obstacles: { Rect }, placed: { Rect }, canvas: Vector2): boolean
	if rect.X0 < EDGE or rect.Y0 < EDGE or rect.X1 > canvas.X - EDGE or rect.Y1 > canvas.Y - EDGE then
		return false
	end
	for _, obstacle in ipairs(obstacles) do
		if intersects(rect, obstacle, EXACT_MARGIN) then
			return false
		end
	end
	for _, other in ipairs(placed) do
		if intersects(rect, other, PIECE_GAP) then
			return false
		end
	end
	return true
end

-- Affinage : la grille est prudente (jusqu'à une case perdue de chaque côté).
-- Autour de la place trouvée, on cherche au pixel près la position qui permet
-- la plus grande taille (et la plus proche du point préféré).
local function refine(placement: Placement, spec: Spec, obstacles: { Rect }, placed: { Rect }, button: Rect, canvas: Vector2, near: number?): Placement
	local anchor = spec.Anchor(button, canvas)
	local maxScale = spec.MaxScale or 1
	local size = spec.Size
	local function fits(cx: number, cy: number, scale: number): boolean
		local w, h = size.X * scale, size.Y * scale
		local rect = { X0 = cx - w / 2, Y0 = cy - h / 2, X1 = cx + w / 2, Y1 = cy + h / 2 }
		if near and GearKit.RectGap(rect, button) > near then
			return false
		end
		return exactFree(rect, obstacles, placed, canvas)
	end
	local function cost(cx: number, cy: number, scale: number): number
		local dx, dy = cx - anchor.X, cy - anchor.Y
		return math.sqrt(dx * dx + dy * dy) + (1 - scale / maxScale) * SIZE_PENALTY
	end
	local bestX, bestY, bestScale = placement.CX, placement.CY, placement.Scale
	if not fits(bestX, bestY, bestScale) then
		return placement
	end
	local bestCost = cost(bestX, bestY, bestScale)
	local startX, startY, startScale = bestX, bestY, bestScale
	for dy = -12, 12, 3 do
		for dx = -12, 12, 3 do
			local cx, cy = startX + dx, startY + dy
			if fits(cx, cy, startScale) then
				-- Plus grande échelle possible ici (dichotomie)
				local lo, hi = startScale, maxScale
				if fits(cx, cy, hi) then
					lo = hi
				else
					for _ = 1, 6 do
						local mid = (lo + hi) / 2
						if fits(cx, cy, mid) then
							lo = mid
						else
							hi = mid
						end
					end
				end
				local c = cost(cx, cy, lo)
				if c < bestCost - 0.5 then
					bestCost = c
					bestX, bestY, bestScale = cx, cy, lo
				end
			end
		end
	end
	if bestX == startX and bestY == startY and bestScale == startScale then
		return placement
	end
	return makePlacement(bestX, bestY, bestScale, spec, button)
end

-- La place actuelle est-elle toujours bonne ?
local function stillValid(placement: Placement, spec: Spec, obstacles: { Rect }, placed: { Rect }, button: Rect, canvas: Vector2): boolean
	local rect = placement.Rect
	if rect.X0 < 0 or rect.Y0 < 0 or rect.X1 > canvas.X or rect.Y1 > canvas.Y then
		return false
	end
	for _, obstacle in ipairs(obstacles) do
		if intersects(rect, obstacle, KEEP_MARGIN) then
			return false
		end
	end
	for _, other in ipairs(placed) do
		if intersects(rect, other, 2) then
			return false
		end
	end
	local old = placement.Button
	local moved = math.abs(old.X0 - button.X0) + math.abs(old.Y0 - button.Y0) + math.abs(old.X1 - button.X1) + math.abs(old.Y1 - button.Y1)
	if spec.Near and (moved > 4 or GearKit.RectGap(rect, button) > spec.Near + 4) then
		return false
	end
	return true
end

local function samePlacement(a: Placement?, b: Placement?): boolean
	if a == nil or b == nil then
		return a == b
	end
	local aa, bb = a :: Placement, b :: Placement
	if math.abs(aa.CX - bb.CX) > 0.5 or math.abs(aa.CY - bb.CY) > 0.5 or math.abs(aa.Scale - bb.Scale) > 1e-3 then
		return false
	end
	local ba, bbtn = aa.Button, bb.Button
	return math.abs(ba.X0 - bbtn.X0) < 0.5 and math.abs(ba.Y0 - bbtn.Y0) < 0.5 and math.abs(ba.X1 - bbtn.X1) < 0.5
end

local function orderedPieces(): { Piece }
	local list = {}
	for _, piece in pairs(pieces) do
		table.insert(list, piece)
	end
	table.sort(list, function(a, b)
		if a.Spec.Priority ~= b.Spec.Priority then
			return a.Spec.Priority < b.Spec.Priority
		end
		return a.Id < b.Id
	end)
	return list
end

local function notify(piece: Piece, placement: Placement?)
	piece.Placement = placement
	local ok, err = pcall(piece.Spec.OnPlace, placement)
	if not ok then
		warn("[GearLayout] " .. piece.Id .. " : " .. tostring(err))
	end
	GearLayout.Changed:Fire(piece.Id, placement)
end

----------------------------------------------------------------------
-- Calcul complet
----------------------------------------------------------------------

local retryScheduled = false

local function doLayout(force: boolean)
	local button = GearKit.GetButtonRect()
	if not button then
		-- Bouton pas encore construit / mis en page : on réessaie un peu plus tard
		if not retryScheduled then
			retryScheduled = true
			task.delay(0.5, function()
				retryScheduled = false
				if running then
					GearLayout.Request(force)
				end
			end)
		end
		return
	end
	local canvas = GearKit.CanvasSize()
	local obstacles = collectObstacles(canvas)
	local grid = newGrid(canvas)
	for _, obstacle in ipairs(obstacles) do
		markRect(grid, obstacle.X0 - MARGIN, obstacle.Y0 - MARGIN, obstacle.X1 + MARGIN, obstacle.Y1 + MARGIN)
	end
	markRect(grid, 0, 0, canvas.X, EDGE)
	markRect(grid, 0, canvas.Y - EDGE, canvas.X, canvas.Y)
	markRect(grid, 0, 0, EDGE, canvas.Y)
	markRect(grid, canvas.X - EDGE, 0, canvas.X, canvas.Y)
	buildSat(grid)

	local placed: { Rect } = {}
	local results: { [Piece]: Placement? } = {}
	for _, piece in ipairs(orderedPieces()) do
		local spec = piece.Spec
		local current = piece.Placement
		local placement: Placement? = nil
		if current and not force and stillValid(current, spec, obstacles, placed, button, canvas) then
			placement = makePlacement(current.CX, current.CY, current.Scale, spec, button)
		else
			local maxScale = spec.MaxScale or 1
			local minScale = math.min(maxScale, spec.MinScale or 0.45)
			placement = search(grid, spec, button, canvas, maxScale, minScale, spec.Near)
			local near = spec.Near
			if not placement then
				-- Dernier recours : plus petit, et n'importe où
				near = nil
				placement = search(grid, spec, button, canvas, minScale * 0.9, maxScale * LAST_RESORT_SCALE, nil)
			end
			if placement then
				placement = refine(placement, spec, obstacles, placed, button, canvas, near)
			end
		end
		results[piece] = placement
		if placement then
			local rect = placement.Rect
			table.insert(placed, rect)
			markRect(grid, rect.X0 - PIECE_GAP, rect.Y0 - PIECE_GAP, rect.X1 + PIECE_GAP, rect.Y1 + PIECE_GAP)
			buildSat(grid)
		end
	end

	lastButton = button
	lastCanvas = canvas
	for piece, placement in pairs(results) do
		if pieces[piece.Id] == piece and not samePlacement(piece.Placement, placement) then
			notify(piece, placement)
		end
	end
	-- (accessoires sans place : results[piece] = nil, pairs ne les voit pas)
	for _, piece in pairs(pieces) do
		if results[piece] == nil and piece.Placement ~= nil then
			notify(piece, nil)
		end
	end
end

----------------------------------------------------------------------
-- Vérification périodique (bon marché : pas de grille)
----------------------------------------------------------------------

local function check()
	local button = GearKit.GetButtonRect()
	if not button then
		return
	end
	local canvas = GearKit.CanvasSize()
	local previousCanvas = lastCanvas
	if not previousCanvas or math.abs(previousCanvas.X - canvas.X) > 1 or math.abs(previousCanvas.Y - canvas.Y) > 1 then
		GearLayout.Request(true)
		return
	end
	local previous = lastButton
	if not previous or math.abs(previous.X0 - button.X0) + math.abs(previous.Y0 - button.Y0) > 3 then
		GearLayout.Request(false)
		return
	end
	local obstacles = collectObstacles(canvas)
	local hidden = false
	for _, piece in pairs(pieces) do
		local placement = piece.Placement
		if placement then
			for _, obstacle in ipairs(obstacles) do
				if intersects(placement.Rect, obstacle, KEEP_MARGIN) then
					GearLayout.Request(false)
					return
				end
			end
		else
			hidden = true
		end
	end
	-- Un accessoire sans place : de la place a peut-être été libérée
	checkCount += 1
	if hidden and checkCount % 5 == 0 then
		GearLayout.Request(false)
	end
end

local function loop(gen: number)
	task.delay(CHECK_INTERVAL, function()
		if gen ~= generation or not running then
			return
		end
		local ok, err = pcall(check)
		if not ok then
			warn("[GearLayout] vérification : " .. tostring(err))
		end
		loop(gen)
	end)
end

local function start()
	if running then
		return
	end
	running = true
	generation += 1
	local function forced()
		GearLayout.Request(true)
	end
	table.insert(connections, Slots.Changed:Connect(forced))
	table.insert(connections, Interface.ScaleChanged:Connect(forced))
	table.insert(connections, Interface.DeviceChanged:Connect(forced))
	table.insert(connections, ClientState.FeaturesChanged:Connect(function()
		-- (les cadres des nouveaux stimuli sont créés par StimulusManager juste avant)
		GearLayout.Request(false)
	end))
	loop(generation)
end

local function stop()
	running = false
	generation += 1
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	lastButton = nil
	lastCanvas = nil
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Demande un nouveau calcul (regroupé : un seul calcul pour plusieurs demandes)
function GearLayout.Request(force: boolean?)
	if force then
		forceNext = true
	end
	if scheduled or not running then
		return
	end
	scheduled = true
	task.delay(0.06, function()
		scheduled = false
		if not running then
			return
		end
		local useForce = forceNext
		forceNext = false
		local ok, err = pcall(doLayout, useForce)
		if not ok then
			warn("[GearLayout] " .. tostring(err))
		end
	end)
end

function GearLayout.Register(id: string, spec: Spec)
	pieces[id] = { Id = id, Spec = spec, Placement = nil }
	start()
	GearLayout.Request(false)
end

function GearLayout.Unregister(id: string)
	local piece = pieces[id]
	if not piece then
		return
	end
	pieces[id] = nil
	GearLayout.Changed:Fire(id, nil)
	if next(pieces) == nil then
		stop()
	end
end

function GearLayout.GetPlacement(id: string): Placement?
	local piece = pieces[id]
	return piece and piece.Placement or nil
end

function GearLayout.IsRegistered(id: string): boolean
	return pieces[id] ~= nil
end

-- (debug / tests) : { [id] = placement }
function GearLayout.Snapshot(): { [string]: Placement? }
	local out = {}
	for id, piece in pairs(pieces) do
		out[id] = piece.Placement
	end
	return out
end

return GearLayout
