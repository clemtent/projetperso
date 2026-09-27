--[[
	Cosmos > Zones (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Cosmos > Zones

	Planificateur de place partagé par les 10 stimuli « cosmiques » (SleepMode,
	DeepFocus, Seashell, DreamMachine, Aurora, TimeWarp, GalaxyStream,
	Singularity, InfiniteScroll, Multiverse). Ils sont tous dans le calque
	Background (SOUS les cartes et la colonne centrale) : ils ne cachent jamais
	une information, mais il faut les poser là où le fond se voit vraiment.

	  - Profondeur (convention du calque Background) : fond du thème 0, mode
	    néon ~50, COSMOS 301-310 (Zones.Depth : ciel lointain -> anneaux ->
	    objets), nuages de l'orage 1000, accessoires de clic 1101-1107.
	    Nos conteneurs découpent leur contenu (rien sous la barre Roblox).
	  - Territoire (règle du chef de projet) : les accessoires de clic
	    (CLICKGEAR) ont la « bande centrale » au-dessus du BAS RÉEL de la
	    barre d'améliorations (autour du bouton et du compteur, à côté des
	    pastilles, poches à côté de la barre). Les OBJETS cosmiques vont
	    partout ailleurs : gouttières entre les cartes du bas, couloirs entre
	    les slots de côté et CL / CR, espaces sous la barre, côtés libres.
	    Les effets d'ambiance (aurore, rivière d'étoiles, anneaux, ondes du
	    temps) peuvent passer partout, très transparents.
	  - Place : grille d'occupation (cases de 8 px "design") : bandeau
	    d'actualités, cartes des slots présentes, colonne centrale (rectangle
	    réel de la barre d'améliorations), bande des accessoires, et objets
	    des autres stimuli marqués LayoutObstacle = true (convention
	    partagée ; nos objets posés le sont aussi). Chaque objet demande une
	    ou plusieurs places (taille "design", formes de rechange, point
	    préféré, échelle min / max). Service en 2 tours : le 1er objet de
	    chaque stimulus (ordre Zones.Priority : la machine à rêves d'abord),
	    puis les objets en plus (2e / 3e portail, téléphones...). Ce qui ne
	    tient pas est « replié » en tout petit (échelle 0,25 minimum) plutôt
	    que de disparaître. Deux objets ne se chevauchent jamais.
	  - Stabilité : un objet garde sa place tant qu'elle reste libre (sauf si
	    une place nettement plus grande se libère, ex. après l'océan).
	  - Replanification regroupée (jamais à chaque image) : écran (appareil,
	    taille), carte qui apparaît / disparaît, barre qui change de taille,
	    stimulus cosmique qui démarre / s'arrête, et vérification toutes les
	    1,5 s (objet d'un autre stimulus posé sur un des nôtres).

	API :
	  Zones.Attach(ctx)                   -- profondeur + découpe du conteneur
	  Zones.Request(id, items, onPlace)   -- demande / met à jour des places
	  Zones.Release(id)                   -- libère (Stop du stimulus)
	  Zones.Schedule()                    -- demande une replanification
	  Zones.GetCanvas() -> Vector2        -- taille de la toile ("design")
	  Zones.GetFocus() -> Vector2         -- centre du compteur
	  Zones.PickPath(routes, width) -> i  -- courbe la plus visible (ambiance)
	  Zones.Bezier(points, u) -> Vector2
	  Zones.Changed                       -- Signal : mise en page recalculée
	Item = { W, H, Shapes? = { Vector2 } (formes de rechange), Anchor =
	         Vector2 (fraction de la toile), MinScale?, MaxScale?, Gap? }
	Placement = { X, Y (centre, px de la toile), Scale, Shape (0 = forme
	              principale, i = Shapes[i]), W, H, Folded? } ou false
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Slots = require(Client.Slots)
local Interface = require(Client.Interface)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Zones = {}

export type Rect = { X: number, Y: number, W: number, H: number }

export type Item = {
	W: number,
	H: number,
	Shapes: { Vector2 }?,
	Anchor: Vector2,
	MinScale: number?,
	MaxScale: number?,
	Gap: number?,
}

export type Placement = {
	X: number,
	Y: number,
	Scale: number,
	Shape: number,
	W: number,
	H: number,
	Folded: boolean?, -- replié en tout petit (pas de place à l'échelle minimale)
}

type Request = {
	Id: string,
	Priority: number,
	Items: { Item },
	OnPlace: (placements: { Placement | false }) -> (),
	Signature: string?,
	Previous: { Placement | false },
}

type Grid = {
	Cols: number,
	Rows: number,
	Occ: { number },
	Sat: { number },
}

-- ZIndex des conteneurs dans le calque Background (convention partagée)
Zones.Depth = {
	Aurora = 301,
	GalaxyStream = 302,
	DeepFocus = 303,
	TimeWarp = 304,
	InfiniteScroll = 305,
	Multiverse = 306,
	Seashell = 307,
	Singularity = 308,
	SleepMode = 309,
	DreamMachine = 310,
}

-- Ordre de service des demandes de place (plus petit = servi d'abord)
Zones.Priority = {
	DreamMachine = 1, -- place garantie : le joueur a demandé à la voir
	Seashell = 2,
	SleepMode = 3,
	Singularity = 4,
	Multiverse = 5,
	InfiniteScroll = 6,
	TimeWarp = 7, -- l'horloge est un bonus : ses ondes sont une ambiance
}

Zones.Changed = Signal.new()

local CELL = 8 -- taille d'une case de la grille (pixels "design")
local EDGE = 4 -- marge le long des bords de la toile
local TICKER_HEIGHT = 32
local SCALE_WEIGHT = 0.55 -- préférence "plus gros" face à "plus près du point préféré"
local MOVE_GAIN = 0.12 -- on ne quitte une place valable que pour une échelle nettement plus grande
local FOLD_SCALE = 0.25 -- dernier recours : objet replié en tout petit
local REPLAN_DELAY = 0.12
local CHECK_INTERVAL = 1.5
local BAR_MAX_HALF = 346 -- demi-largeur max de la barre d'améliorations (660 + marges)
local BAR_CHANGE = 12 -- replanifie si la barre change de plus de 12 px

-- Échelles essayées (de la plus grande à la plus petite)
local SCALES = { 1.5, 1.4, 1.3, 1.2, 1.1, 1, 0.92, 0.85, 0.78, 0.72, 0.66, 0.6, 0.55, 0.5, 0.45, 0.4, 0.36, 0.32, 0.28, 0.25 }

-- Colonne centrale (pixels "design" depuis le haut de la toile), d'après
-- CenterColumn / UpgradeBar ; sert aussi de secours si la barre est introuvable
local COLUMN = {
	Desktop = { PillsBottom = 294, Row1Half = 336, Row2Half = 300, TwoRows = true, BarHeight = 118 },
	Tablet = { PillsBottom = 302, Row1Half = 336, Row2Half = 300, TwoRows = true, BarHeight = 118 },
	Phone = { PillsBottom = 262, Row1Half = 300, Row2Half = 300, TwoRows = false, BarHeight = 102 },
}

-- Nos propres conteneurs (on ne s'évite pas soi-même)
local OWN = {}
for name in pairs(Zones.Depth) do
	OWN[name] = true
end

local requests: { [string]: Request } = {}
local bound = false
local planPending = false
local planning = false
local planAgain = false
local checking = false
-- Grille "visible" (sans la bande des accessoires) : pour Zones.PickPath
local viewGrid: Grid = { Cols = 0, Rows = 0, Occ = {}, Sat = {} }

----------------------------------------------------------------------
-- Toile, appareil
----------------------------------------------------------------------

function Zones.GetCanvas(): Vector2
	local canvas = Interface.CanvasSize
	if typeof(canvas) ~= "Vector2" or canvas.X < 100 or canvas.Y < 100 then
		return Vector2.new(1280, 720)
	end
	return canvas
end

local function device(): string
	local name = Interface.Device
	if COLUMN[name] then
		return name
	end
	return "Desktop"
end

-- Centre du compteur de Dopamine (anneaux de concentration...)
function Zones.GetFocus(): Vector2
	return Vector2.new(Zones.GetCanvas().X / 2, 156)
end

-- Rectangle (toile) d'un objet quelconque, d'après sa position à l'écran
local function screenRect(object: GuiObject): Rect?
	local scale = Interface.Scale
	if type(scale) ~= "number" or scale <= 0 then
		return nil
	end
	local size = object.AbsoluteSize / scale
	if size.X < 1 or size.Y < 1 then
		return nil
	end
	local topLeft = Interface.ScreenToCanvas(object.AbsolutePosition)
	return { X = topLeft.X, Y = topLeft.Y, W = size.X, H = size.Y }
end

----------------------------------------------------------------------
-- Barre d'améliorations : rectangle RÉEL (ScrollingFrame "Cards")
----------------------------------------------------------------------

local cardsFrame: GuiObject? = nil
local lastBar: Rect? = nil

local function findCards(): GuiObject?
	local cards = cardsFrame
	if cards and cards.Parent then
		return cards
	end
	cardsFrame = nil
	local main = Interface.Layers and Interface.Layers.Main
	local bar = main and main:FindFirstChild("UpgradeBar", true)
	local found = bar and bar:FindFirstChild("Cards")
	if found and found:IsA("GuiObject") then
		cardsFrame = found
		-- La barre change de taille (cartes ajoutées / retirées) : on replanifie
		found:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local previous = lastBar
			local now = if found == cardsFrame then screenRect(found) else nil
			if previous and now and (math.abs(now.W - previous.W) >= BAR_CHANGE or math.abs(now.Y + now.H - previous.Y - previous.H) >= BAR_CHANGE) then
				Zones.Schedule()
			end
		end)
		return found
	end
	return nil
end

-- Rectangle de la barre (toile) ; secours : taille lue / constantes
local function barRect(canvas: Vector2): Rect
	local cx = canvas.X / 2
	local m = COLUMN[device()]
	local cards = findCards()
	if cards and cards.Visible then
		local rect = screenRect(cards)
		if rect and rect.W > 20 and rect.H > 20 and rect.Y > 100 then
			lastBar = rect
			return rect
		end
		local size = cards.Size
		if size.X.Scale == 0 and size.X.Offset > 0 then
			local half = math.clamp(size.X.Offset / 2 + 4, 40, BAR_MAX_HALF)
			local fallback = { X = cx - half, Y = m.PillsBottom + 22, W = half * 2, H = m.BarHeight }
			lastBar = fallback
			return fallback
		end
	end
	local fallback = { X = cx - BAR_MAX_HALF, Y = m.PillsBottom + 22, W = BAR_MAX_HALF * 2, H = m.BarHeight }
	lastBar = fallback
	return fallback
end

----------------------------------------------------------------------
-- Ce qui cache le fond
----------------------------------------------------------------------

-- Bouton + compteur
local function textRects(canvas: Vector2): { Rect }
	local cx = canvas.X / 2
	return {
		{ X = cx - 182, Y = 24, W = 346, H = 110 }, -- bouton, pastilles VIP / boost, maison, chapeau
		{ X = cx - 240, Y = 126, W = 480, H = 80 }, -- compteur + Dopamine par seconde
	}
end

local function columnRects(canvas: Vector2): { Rect }
	local cx = canvas.X / 2
	local m = COLUMN[device()]
	local rects = textRects(canvas)
	if m.TwoRows then
		table.insert(rects, { X = cx - m.Row1Half, Y = 202, W = m.Row1Half * 2, H = 48 })
		table.insert(rects, { X = cx - m.Row2Half, Y = 248, W = m.Row2Half * 2, H = m.PillsBottom - 248 })
	else
		table.insert(rects, { X = cx - m.Row1Half, Y = 202, W = m.Row1Half * 2, H = m.PillsBottom - 202 })
	end
	table.insert(rects, { X = cx - 156, Y = m.PillsBottom, W = 312, H = 24 }) -- jauge de combo
	table.insert(rects, barRect(canvas))
	return rects
end

-- Rectangle "design" d'un slot (même vide) sur la toile
local function slotDesignRect(name: string, canvas: Vector2): Rect?
	local def = Slots.Definitions[name]
	if not def then
		return nil
	end
	local position = Slots.GetPlacement(name)
	local cx = position.X.Scale * canvas.X + position.X.Offset
	local cy = position.Y.Scale * canvas.Y + position.Y.Offset
	if def.Anchor == "T" then
		return { X = 0, Y = cy - def.H / 2, W = canvas.X, H = def.H }
	end
	local k = Slots.GetScale(name)
	local w, h = def.W * k, def.H * k
	return { X = cx - w / 2, Y = cy - h / 2, W = w, H = h }
end

local function samePosition(a: UDim2, b: UDim2): boolean
	return math.abs(a.X.Scale - b.X.Scale) < 1e-3
		and math.abs(a.Y.Scale - b.Y.Scale) < 1e-3
		and math.abs(a.X.Offset - b.X.Offset) < 1
		and math.abs(a.Y.Offset - b.Y.Offset) < 1
end

-- Rectangle (toile) d'un cadre du calque Slots : slot connu (définition +
-- échelle, même pendant l'animation d'apparition) ou cadre quelconque
local function slotRect(child: GuiObject, canvas: Vector2): Rect?
	for name in pairs(Slots.Definitions) do
		if samePosition(Slots.GetPlacement(name), child.Position) then
			return slotDesignRect(name, canvas)
		end
	end
	local size = child.Size
	local w = size.X.Scale * canvas.X + size.X.Offset
	local h = size.Y.Scale * canvas.Y + size.Y.Offset
	if w <= 0 or h <= 0 or (w >= canvas.X * 0.9 and h >= canvas.Y * 0.9) then
		return nil -- calque plein écran : on l'ignore
	end
	local uiScale = child:FindFirstChildOfClass("UIScale")
	local k = uiScale and uiScale.Scale or 1
	w *= k
	h *= k
	local position = child.Position
	local anchor = child.AnchorPoint
	return {
		X = position.X.Scale * canvas.X + position.X.Offset - anchor.X * w,
		Y = position.Y.Scale * canvas.Y + position.Y.Offset - anchor.Y * h,
		W = w,
		H = h,
	}
end

-- Bandeau + cartes des slots + colonne centrale
local function blockedRects(canvas: Vector2): { Rect }
	local rects: { Rect } = { { X = 0, Y = 0, W = canvas.X, H = TICKER_HEIGHT } }
	local layer = Interface.Layers and Interface.Layers.Slots
	if layer then
		for _, child in ipairs(layer:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				local rect = slotRect(child, canvas)
				if rect then
					table.insert(rects, rect)
				end
			end
		end
	end
	for _, rect in ipairs(columnRects(canvas)) do
		table.insert(rects, rect)
	end
	return rects
end

-- Bande des accessoires de clic (interdite à nos OBJETS) : entre CL et CR
-- au-dessus de leur bas, puis entre les slots de côté jusqu'au bas réel de
-- la barre d'améliorations. Les couloirs entre les slots de côté et CL / CR
-- (au-dessus du bas de CL) restent à nous.
local function gearBand(canvas: Vector2): { Rect }
	local cl, cr = slotDesignRect("CL", canvas), slotDesignRect("CR", canvas)
	local l1, r1 = slotDesignRect("L1", canvas), slotDesignRect("R1", canvas)
	if not (cl and cr) then
		return {}
	end
	local bar = barRect(canvas)
	local top = cl.Y + cl.H
	local left = if l1 then l1.X + l1.W else cl.X
	local right = if r1 then r1.X else cr.X + cr.W
	return {
		{ X = cl.X, Y = 0, W = cr.X + cr.W - cl.X, H = top },
		{ X = left, Y = top, W = right - left, H = math.max(0, bar.Y + bar.H - top) },
	}
end

-- Objets des AUTRES stimuli marqués LayoutObstacle = true (calques plein écran)
local function markedRects(): { Rect }
	local rects: { Rect } = {}
	local layers = Interface.Layers
	if not layers then
		return rects
	end
	for _, layerName in ipairs({ "Overlay", "Background" }) do
		local layer = layers[layerName]
		if layer then
			for _, container in ipairs(layer:GetChildren()) do
				if container:IsA("GuiObject") and container.Visible and not OWN[container.Name] then
					for _, item in ipairs(container:GetChildren()) do
						if item:IsA("GuiObject") and item.Visible then
							if item:GetAttribute("LayoutObstacle") == true then
								local rect = screenRect(item)
								if rect then
									table.insert(rects, rect)
								end
							end
							for _, sub in ipairs(item:GetChildren()) do
								if sub:IsA("GuiObject") and sub.Visible and sub:GetAttribute("LayoutObstacle") == true then
									local rect = screenRect(sub)
									if rect then
										table.insert(rects, rect)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return rects
end

----------------------------------------------------------------------
-- Grille d'occupation (Occ[j * cols + i + 1] = 1 si la case (i, j) est prise)
----------------------------------------------------------------------

local function newGrid(canvas: Vector2): Grid
	local cols = math.max(1, math.ceil(canvas.X / CELL))
	local rows = math.max(1, math.ceil(canvas.Y / CELL))
	return { Cols = cols, Rows = rows, Occ = table.create(cols * rows, 0), Sat = {} }
end

local function mark(g: Grid, rect: Rect, pad: number)
	local cols, rows, occ = g.Cols, g.Rows, g.Occ
	local i0 = math.max(0, math.floor((rect.X - pad) / CELL))
	local i1 = math.min(cols - 1, math.ceil((rect.X + rect.W + pad) / CELL) - 1)
	local j0 = math.max(0, math.floor((rect.Y - pad) / CELL))
	local j1 = math.min(rows - 1, math.ceil((rect.Y + rect.H + pad) / CELL) - 1)
	for j = j0, j1 do
		local base = j * cols
		for i = i0, i1 do
			occ[base + i + 1] = 1
		end
	end
end

-- Sommes cumulées : "ce rectangle est-il libre ?" en O(1)
local function buildSat(g: Grid)
	local cols, rows, occ = g.Cols, g.Rows, g.Occ
	local stride = cols + 1
	local sat = table.create(stride * (rows + 1), 0)
	for j = 1, rows do
		local rowSum = 0
		local base = j * stride
		local previous = (j - 1) * stride
		local occBase = (j - 1) * cols
		for i = 1, cols do
			rowSum += occ[occBase + i]
			sat[base + i + 1] = sat[previous + i + 1] + rowSum
		end
	end
	g.Sat = sat
end

-- Nombre de cases prises dans [i, i + w) x [j, j + h)
local function takenCount(g: Grid, i: number, j: number, w: number, h: number): number
	local stride = g.Cols + 1
	local sat = g.Sat
	return sat[(j + h) * stride + i + w + 1] - sat[j * stride + i + w + 1] - sat[(j + h) * stride + i + 1] + sat[j * stride + i + 1]
end

local function markEdges(g: Grid, canvas: Vector2)
	mark(g, { X = 0, Y = 0, W = canvas.X, H = EDGE }, 0)
	mark(g, { X = 0, Y = canvas.Y - EDGE, W = canvas.X, H = EDGE }, 0)
	mark(g, { X = 0, Y = 0, W = EDGE, H = canvas.Y }, 0)
	mark(g, { X = canvas.X - EDGE, Y = 0, W = EDGE, H = canvas.Y }, 0)
end

-- Rectangle occupé par une place (sans marge)
local function placementRect(p: Placement): Rect
	local w, h = p.W * p.Scale, p.H * p.Scale
	return { X = p.X - w / 2, Y = p.Y - h / 2, W = w, H = h }
end

-- Vrai si la place (avec sa marge) est entièrement libre dans la grille
local function isFree(g: Grid, p: Placement, gap: number): boolean
	local rect = placementRect(p)
	local i0 = math.floor((rect.X - gap) / CELL)
	local j0 = math.floor((rect.Y - gap) / CELL)
	local i1 = math.ceil((rect.X + rect.W + gap) / CELL)
	local j1 = math.ceil((rect.Y + rect.H + gap) / CELL)
	if i0 < 0 or j0 < 0 or i1 > g.Cols or j1 > g.Rows then
		return false
	end
	return takenCount(g, i0, j0, i1 - i0, j1 - j0) == 0
end

-- Meilleure place pour un objet entre les échelles minScale et maxScale :
-- pour chaque case libre (coin haut-gauche), plus grande échelle qui tient
-- (recherche dichotomique), puis score = distance au point préféré - bonus
-- de taille.
local function search(g: Grid, item: Item, canvas: Vector2, minScale: number, maxScale: number): Placement?
	local gap = item.Gap or 6
	local scales = {}
	for _, s in ipairs(SCALES) do
		if s <= maxScale + 1e-6 and s >= minScale - 1e-6 then
			table.insert(scales, s)
		end
	end
	if #scales == 0 then
		return nil
	end
	local shapes = { { item.W, item.H, 0 } }
	for index, extra in ipairs(item.Shapes or {}) do
		table.insert(shapes, { extra.X, extra.Y, index })
	end
	local anchorX, anchorY = item.Anchor.X * canvas.X, item.Anchor.Y * canvas.Y
	local diagonal = math.max(1, canvas.Magnitude)
	local cols, rows, occ = g.Cols, g.Rows, g.Occ

	local best: Placement? = nil
	local bestScore = math.huge
	for _, shape in ipairs(shapes) do
		local w, h = shape[1], shape[2]
		-- Taille en cases pour chaque échelle (la place est centrée dans les cases)
		local cellsW, cellsH = {}, {}
		for index, s in ipairs(scales) do
			cellsW[index] = math.ceil((w * s + gap * 2) / CELL)
			cellsH[index] = math.ceil((h * s + gap * 2) / CELL)
		end
		local smallW, smallH = cellsW[#scales], cellsH[#scales]
		for j = 0, rows - smallH do
			local base = j * cols
			for i = 0, cols - smallW do
				if occ[base + i + 1] == 0 and takenCount(g, i, j, smallW, smallH) == 0 then
					-- Plus grande échelle qui tient ici (les échelles vont en décroissant)
					local lo, hi = 1, #scales -- hi tient toujours
					while lo < hi do
						local mid = (lo + hi) // 2
						local cw, ch = cellsW[mid], cellsH[mid]
						if i + cw <= cols and j + ch <= rows and takenCount(g, i, j, cw, ch) == 0 then
							hi = mid
						else
							lo = mid + 1
						end
					end
					local s = scales[hi]
					local centreX = i * CELL + cellsW[hi] * CELL / 2
					local centreY = j * CELL + cellsH[hi] * CELL / 2
					local dx, dy = centreX - anchorX, centreY - anchorY
					local score = math.sqrt(dx * dx + dy * dy) / diagonal - s * SCALE_WEIGHT
					if score < bestScore then
						bestScore = score
						best = { X = centreX, Y = centreY, Scale = s, Shape = shape[3], W = w, H = h }
					end
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------------
-- Planification
----------------------------------------------------------------------

local function signatureOf(placements: { Placement | false }): string
	local parts = {}
	for _, p in ipairs(placements) do
		if p then
			table.insert(parts, string.format("%d,%d,%.2f,%d", math.floor(p.X + 0.5), math.floor(p.Y + 0.5), p.Scale, p.Shape))
		else
			table.insert(parts, "-")
		end
	end
	return table.concat(parts, ";")
end

local function sortedRequests(): { Request }
	local list = {}
	for _, request in pairs(requests) do
		table.insert(list, request)
	end
	table.sort(list, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority < b.Priority
		end
		return a.Id < b.Id
	end)
	return list
end

local function sameShapeAs(old: Placement, item: Item): boolean
	if old.W == item.W and old.H == item.H then
		return true
	end
	for _, extra in ipairs(item.Shapes or {}) do
		if old.W == extra.X and old.H == extra.Y then
			return true
		end
	end
	return false
end

local function plan()
	local canvas = Zones.GetCanvas()
	local blocked = blockedRects(canvas)
	local marked = markedRects()
	-- Grille des OBJETS : tout ce qui cache le fond + bande des accessoires
	local objects = newGrid(canvas)
	markEdges(objects, canvas)
	for _, rect in ipairs(blocked) do
		mark(objects, rect, 2)
	end
	for _, rect in ipairs(gearBand(canvas)) do
		mark(objects, rect, 0)
	end
	for _, rect in ipairs(marked) do
		mark(objects, rect, 2)
	end
	buildSat(objects)

	local order = sortedRequests()
	local results: { [Request]: { Placement | false } } = {}
	-- 2 tours : le 1er objet de chaque stimulus, puis les objets en plus
	local queue: { { Request: Request, Index: number } } = {}
	for _, request in ipairs(order) do
		results[request] = {}
		if request.Items[1] then
			table.insert(queue, { Request = request, Index = 1 })
		end
	end
	for _, request in ipairs(order) do
		for index = 2, #request.Items do
			table.insert(queue, { Request = request, Index = index })
		end
	end
	local function commit(request: Request, index: number, chosen: Placement, gap: number)
		mark(objects, placementRect(chosen), gap)
		buildSat(objects)
		results[request][index] = chosen
	end
	local missing: { { Request: Request, Index: number } } = {}
	for _, entry in ipairs(queue) do
		local request, index = entry.Request, entry.Index
		local item = request.Items[index]
		local gap = item.Gap or 6
		local chosen: Placement? = search(objects, item, canvas, item.MinScale or 0.5, item.MaxScale or 1)
		-- Stabilité : garder l'ancienne place si elle est encore libre
		local previous = request.Previous[index]
		if previous then
			local old = previous :: Placement
			local fresh = chosen
			if not old.Folded and sameShapeAs(old, item) and isFree(objects, old, gap) and (fresh == nil or fresh.Scale < old.Scale + MOVE_GAIN) then
				chosen = old
			end
		end
		if chosen then
			commit(request, index, chosen, gap)
		else
			table.insert(missing, entry)
		end
	end
	-- Dernier recours : replié en tout petit plutôt que disparaître
	for _, entry in ipairs(missing) do
		local request, index = entry.Request, entry.Index
		local item = request.Items[index]
		local gap = math.min(item.Gap or 6, 3)
		local folded = search(objects, item, canvas, FOLD_SCALE, item.MinScale or 0.5)
		if folded then
			folded.Folded = true
			commit(request, index, folded, gap)
		else
			results[request][index] = false
		end
	end

	-- Grille "visible" (ambiance) : sans la bande des accessoires
	local view = newGrid(canvas)
	markEdges(view, canvas)
	for _, rect in ipairs(blocked) do
		mark(view, rect, 2)
	end
	for _, rect in ipairs(marked) do
		mark(view, rect, 2)
	end
	for _, request in ipairs(order) do
		for _, p in pairs(results[request]) do
			if p then
				mark(view, placementRect(p), 2)
			end
		end
	end
	viewGrid = view

	-- Rappels (hors de la boucle de calcul)
	for _, request in ipairs(order) do
		if requests[request.Id] == request then
			local placements = results[request]
			for index = 1, #request.Items do
				if placements[index] == nil then
					placements[index] = false
				end
			end
			request.Previous = placements
			local signature = signatureOf(placements)
			if signature ~= request.Signature then
				request.Signature = signature
				local ok, err = pcall(request.OnPlace, placements)
				if not ok then
					warn("[Cosmos.Zones] Erreur dans le placement de " .. request.Id .. " : " .. tostring(err))
				end
			end
		end
	end
	Zones.Changed:Fire()
end

-- Demande une replanification (regroupée, jamais pendant une image de rendu)
function Zones.Schedule()
	if planning then
		planAgain = true
		return
	end
	if planPending then
		return
	end
	planPending = true
	task.delay(REPLAN_DELAY, function()
		planPending = false
		planning = true
		local ok, err = pcall(plan)
		planning = false
		if not ok then
			warn("[Cosmos.Zones] Erreur de planification : " .. tostring(err))
		end
		if planAgain then
			planAgain = false
			Zones.Schedule()
		end
	end)
end

-- Vérification lente : un objet d'un autre stimulus s'est-il posé sur un des nôtres ?
local function overlaps(a: Rect, b: Rect): boolean
	return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
end

local function check()
	local others = markedRects()
	if #others == 0 then
		return
	end
	for _, request in pairs(requests) do
		for _, p in ipairs(request.Previous) do
			if p then
				local mine = placementRect(p)
				for _, rect in ipairs(others) do
					if overlaps(mine, rect) then
						Zones.Schedule()
						return
					end
				end
			end
		end
	end
end

local function startChecks()
	if checking then
		return
	end
	checking = true
	task.spawn(function()
		while next(requests) ~= nil do
			task.wait(CHECK_INTERVAL)
			local ok, err = pcall(check)
			if not ok then
				warn("[Cosmos.Zones] Erreur de vérification : " .. tostring(err))
				break
			end
		end
		checking = false
	end)
end

local function bind()
	if bound then
		return
	end
	bound = true
	local function changed()
		Zones.Schedule()
	end
	Interface.ScaleChanged:Connect(changed)
	Interface.DeviceChanged:Connect(changed)
	Slots.Changed:Connect(changed)
	local layer = Interface.Layers and Interface.Layers.Slots
	if layer then
		layer.ChildAdded:Connect(changed)
		layer.ChildRemoved:Connect(changed)
	end
end

----------------------------------------------------------------------
-- Chemins (effets d'ambiance) : quelle courbe se voit le mieux ?
----------------------------------------------------------------------

-- Point d'une courbe de Bézier cubique (4 points en fractions de la toile)
function Zones.Bezier(points: { Vector2 }, u: number): Vector2
	local a = 1 - u
	return points[1] * (a * a * a) + points[2] * (3 * a * a * u) + points[3] * (3 * a * u * u) + points[4] * (u * u * u)
end

-- Parmi plusieurs courbes (4 points de contrôle chacune, fractions de la
-- toile), celle dont la bande de largeur `width` passe le plus dans le fond
-- VISIBLE (ni carte, ni colonne, ni objet posé). À appeler après une
-- planification (Zones.Changed).
function Zones.PickPath(candidates: { { Vector2 } }, width: number): number
	local canvas = Zones.GetCanvas()
	local grid = viewGrid
	if grid.Cols == 0 or #grid.Occ == 0 then
		return 1
	end
	local bestIndex, bestScore = 1, -1
	for index, points in ipairs(candidates) do
		local free = 0
		local previous = Zones.Bezier(points, 0)
		for step = 1, 60 do
			local p = Zones.Bezier(points, step / 60)
			local d = p - previous
			previous = p
			local length = math.max(1e-6, d.Magnitude)
			local normal = Vector2.new(-d.Y / length, d.X / length)
			for _, lane in ipairs({ -0.35, 0, 0.35 }) do
				local x = p.X * canvas.X + normal.X * lane * width
				local y = p.Y * canvas.Y + normal.Y * lane * width
				local i, j = math.floor(x / CELL), math.floor(y / CELL)
				if i >= 0 and j >= 0 and i < grid.Cols and j < grid.Rows and grid.Occ[j * grid.Cols + i + 1] == 0 then
					free += 1
				end
			end
		end
		if free > bestScore then
			bestIndex, bestScore = index, free
		end
	end
	return bestIndex
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Profondeur du stimulus (ZIndex de son conteneur dans le calque
-- Background) + découpe : rien ne déborde de la toile
function Zones.Attach(ctx)
	local container = ctx.Container
	if container then
		local depth = Zones.Depth[ctx.Feature]
		if depth then
			container.ZIndex = depth
		end
		container.ClipsDescendants = true
	end
	bind()
end

-- Demande (ou remplace) les places d'un stimulus. onPlace(placements) est
-- rappelé à chaque changement (placements[i] = Placement ou false).
function Zones.Request(id: string, items: { Item }, onPlace: (placements: { Placement | false }) -> ())
	bind()
	local previous = requests[id]
	requests[id] = {
		Id = id,
		Priority = Zones.Priority[id] or 50,
		Items = items,
		OnPlace = onPlace,
		Signature = nil,
		Previous = if previous then previous.Previous else {},
	}
	Zones.Schedule()
	startChecks()
end

function Zones.Release(id: string)
	if requests[id] then
		requests[id] = nil
		Zones.Schedule()
	end
end

return Zones
