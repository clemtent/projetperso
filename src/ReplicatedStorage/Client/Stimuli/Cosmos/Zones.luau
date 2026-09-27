--[[
	Cosmos > Zones (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Cosmos > Zones

	Planificateur de place partagé par les 10 stimuli « cosmiques » (SleepMode,
	DeepFocus, Seashell, DreamMachine, Aurora, TimeWarp, GalaxyStream,
	Singularity, InfiniteScroll, Multiverse). Ils sont tous dans le calque
	Background (SOUS les cartes et la colonne centrale) : ils ne cachent jamais
	une information, mais il faut les poser là où le fond se voit vraiment.

	  - Profondeur : chaque stimulus a un ZIndex fixe (Zones.Depth) dans le
	    calque Background, au-dessus du fond du thème (0) et du mode néon
	    (~50) : ciel lointain (aurore, rivière d'étoiles) -> anneaux et
	    horloge -> objets (lune, machine à rêves...).
	  - Place : une grille d'occupation (cases de 8 px "design") marque tout
	    ce qui cache le fond : bandeau d'actualités, cartes des slots
	    réellement présentes (L1, CL, R3...), colonne centrale (bouton,
	    compteur, pastilles, jauge, barre d'améliorations dont la largeur
	    réelle est lue). Chaque OBJET demande une ou plusieurs places (taille
	    "design", forme de rechange, point préféré, échelle min / max) ; les
	    demandes sont servies par priorité (Zones.Priority) et chaque place
	    accordée est retirée de la grille : deux objets ne se chevauchent
	    jamais et un objet n'est jamais posé sous une carte.
	    Sur PC, en fin de partie, il reste surtout les « gouttières » entre
	    les cartes du bas et les couloirs entre les slots de côté et la
	    colonne ; sur téléphone / tablette, de grands espaces sur les côtés.
	  - Replanification regroupée (jamais à chaque image) quand l'écran
	    change (appareil, taille), qu'une carte apparaît / disparaît, que la
	    barre d'améliorations change de largeur ou qu'un stimulus cosmique
	    démarre / s'arrête. Un objet qui change de place glisse (tween).

	Les effets d'ambiance (aurore, rivière d'étoiles, anneaux de
	concentration, onde du temps) n'ont pas de place réservée : ils passent
	derrière tout, très transparents, et évitent le compteur
	(Zones.GetTextRects).

	API :
	  Zones.Attach(ctx)                        -- ZIndex du conteneur (profondeur)
	  Zones.Request(id, items, onPlace)        -- demande / met à jour des places
	  Zones.Release(id)                        -- libère (Stop du stimulus)
	  Zones.GetCanvas() -> Vector2             -- taille de la toile ("design")
	  Zones.GetFocus() -> Vector2              -- centre du compteur
	  Zones.GetTextRects() -> { Rect }         -- zones de texte à ne pas brouiller
	  Zones.Changed                            -- Signal : mise en page recalculée
	Item = { W, H, AltW?, AltH?, Anchor = Vector2 (fraction de la toile),
	         MinScale?, MaxScale?, Gap? }
	Placement = { X, Y (centre, px de la toile), Scale, Alt, W, H } ou false
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
	AltW: number?,
	AltH: number?,
	Anchor: Vector2,
	MinScale: number?,
	MaxScale: number?,
	Gap: number?,
}

export type Placement = {
	X: number,
	Y: number,
	Scale: number,
	Alt: boolean,
	W: number,
	H: number,
}

type Request = {
	Id: string,
	Priority: number,
	Items: { Item },
	OnPlace: (placements: { Placement | false }) -> (),
	Signature: string?,
}

-- ZIndex des conteneurs dans le calque Background : fond du thème = 0,
-- mode néon ~ 50 (ordre de l'amélioration), nuages de l'orage = 1000
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
	DreamMachine = 1,
	SleepMode = 2,
	Singularity = 3,
	TimeWarp = 4,
	Seashell = 5,
	Multiverse = 6,
	InfiniteScroll = 7,
}

Zones.Changed = Signal.new()

local CELL = 8 -- taille d'une case de la grille (pixels "design")
local EDGE = 4 -- marge le long des bords de la toile
local TICKER_HEIGHT = 32
local SCALE_WEIGHT = 0.55 -- préférence "plus gros" face à "plus près du point préféré"
local REPLAN_DELAY = 0.12
local BAR_MAX_HALF = 346 -- demi-largeur max de la barre d'améliorations (660 + marges)
local BAR_CHANGE = 12 -- replanifie si la barre change de plus de 12 px

-- Échelles essayées (de la plus grande à la plus petite)
local SCALES = { 1.5, 1.4, 1.3, 1.2, 1.1, 1, 0.92, 0.85, 0.78, 0.72, 0.66, 0.6, 0.55, 0.5, 0.45, 0.4, 0.36, 0.32 }

-- Colonne centrale (pixels "design" depuis le haut de la toile), d'après
-- CenterColumn / UpgradeBar : pastilles sur 2 rangées (PC, tablette) ou 1
-- rangée (téléphone), jauge de combo, barre d'améliorations.
local COLUMN = {
	Desktop = { PillsBottom = 294, Row1Half = 336, Row2Half = 300, TwoRows = true, BarHeight = 118 },
	Tablet = { PillsBottom = 302, Row1Half = 336, Row2Half = 300, TwoRows = true, BarHeight = 118 },
	Phone = { PillsBottom = 262, Row1Half = 300, Row2Half = 300, TwoRows = false, BarHeight = 102 },
}

local requests: { [string]: Request } = {}
local bound = false
local planPending = false
local planning = false
local planAgain = false

-- Grille : Occ[j * cols + i + 1] = 1 si la case (i, j) est prise ; Sat = sommes cumulées
local grid = {
	Cols = 0,
	Rows = 0,
	Occ = {} :: { number },
	Sat = {} :: { number },
}

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

----------------------------------------------------------------------
-- Barre d'améliorations : largeur réelle (ScrollingFrame "Cards")
----------------------------------------------------------------------

local cardsFrame: GuiObject? = nil
local lastBarHalf = BAR_MAX_HALF

local function measureBarHalf(): number
	local cards = cardsFrame
	if not cards or not cards.Parent then
		cards = nil
		cardsFrame = nil
		local main = Interface.Layers and Interface.Layers.Main
		local bar = main and main:FindFirstChild("UpgradeBar", true)
		local found = bar and bar:FindFirstChild("Cards")
		if found and found:IsA("GuiObject") then
			cards = found
			cardsFrame = found
			found:GetPropertyChangedSignal("Size"):Connect(function()
				if found ~= cardsFrame then
					return
				end
				local size = found.Size
				local half = size.X.Scale == 0 and math.clamp(size.X.Offset / 2 + 4, 40, BAR_MAX_HALF) or BAR_MAX_HALF
				if math.abs(half - lastBarHalf) >= BAR_CHANGE then
					Zones.Schedule()
				end
			end)
		end
	end
	if not cards then
		return BAR_MAX_HALF
	end
	local size = cards.Size
	if size.X.Scale ~= 0 or size.X.Offset <= 0 then
		return BAR_MAX_HALF
	end
	return math.clamp(size.X.Offset / 2 + 4, 40, BAR_MAX_HALF)
end

----------------------------------------------------------------------
-- Ce qui cache le fond
----------------------------------------------------------------------

-- Zones de texte (bouton, compteur) : les effets d'ambiance les évitent
function Zones.GetTextRects(): { Rect }
	local cx = Zones.GetCanvas().X / 2
	return {
		{ X = cx - 182, Y = 24, W = 346, H = 110 }, -- bouton, pastilles VIP / boost, maison, chapeau
		{ X = cx - 240, Y = 126, W = 480, H = 80 }, -- compteur + Dopamine par seconde
	}
end

local function columnRects(canvas: Vector2): { Rect }
	local cx = canvas.X / 2
	local m = COLUMN[device()]
	local rects = Zones.GetTextRects()
	if m.TwoRows then
		table.insert(rects, { X = cx - m.Row1Half, Y = 202, W = m.Row1Half * 2, H = 48 })
		table.insert(rects, { X = cx - m.Row2Half, Y = 248, W = m.Row2Half * 2, H = m.PillsBottom - 248 })
	else
		table.insert(rects, { X = cx - m.Row1Half, Y = 202, W = m.Row1Half * 2, H = m.PillsBottom - 202 })
	end
	-- Jauge de combo
	table.insert(rects, { X = cx - 156, Y = m.PillsBottom, W = 312, H = 24 })
	-- Barre d'améliorations (largeur réelle)
	local barHalf = measureBarHalf()
	lastBarHalf = barHalf
	table.insert(rects, { X = cx - barHalf, Y = m.PillsBottom + 22, W = barHalf * 2, H = m.BarHeight })
	return rects
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
	for name, def in pairs(Slots.Definitions) do
		local position = Slots.GetPlacement(name)
		if samePosition(position, child.Position) then
			local cx = position.X.Scale * canvas.X + position.X.Offset
			local cy = position.Y.Scale * canvas.Y + position.Y.Offset
			if def.Anchor == "T" then
				return { X = 0, Y = cy - def.H / 2, W = canvas.X, H = def.H }
			end
			local k = Slots.GetScale(name)
			local w, h = def.W * k, def.H * k
			return { X = cx - w / 2, Y = cy - h / 2, W = w, H = h }
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

----------------------------------------------------------------------
-- Grille d'occupation
----------------------------------------------------------------------

local function mark(rect: Rect, pad: number)
	local cols, rows, occ = grid.Cols, grid.Rows, grid.Occ
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

local function buildSat()
	local cols, rows, occ = grid.Cols, grid.Rows, grid.Occ
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
	grid.Sat = sat
end

-- Nombre de cases prises dans [i, i + w) x [j, j + h)
local function takenCount(i: number, j: number, w: number, h: number): number
	local stride = grid.Cols + 1
	local sat = grid.Sat
	return sat[(j + h) * stride + i + w + 1] - sat[j * stride + i + w + 1] - sat[(j + h) * stride + i + 1] + sat[j * stride + i + 1]
end

local function resetGrid(canvas: Vector2)
	grid.Cols = math.max(1, math.ceil(canvas.X / CELL))
	grid.Rows = math.max(1, math.ceil(canvas.Y / CELL))
	grid.Occ = table.create(grid.Cols * grid.Rows, 0)
	-- Bords de la toile
	mark({ X = 0, Y = 0, W = canvas.X, H = EDGE }, 0)
	mark({ X = 0, Y = canvas.Y - EDGE, W = canvas.X, H = EDGE }, 0)
	mark({ X = 0, Y = 0, W = EDGE, H = canvas.Y }, 0)
	mark({ X = canvas.X - EDGE, Y = 0, W = EDGE, H = canvas.Y }, 0)
	for _, rect in ipairs(blockedRects(canvas)) do
		mark(rect, 2)
	end
	buildSat()
end

-- Meilleure place pour un objet : pour chaque case libre (coin haut-gauche),
-- plus grande échelle qui tient (recherche dichotomique), puis score =
-- distance au point préféré - bonus de taille.
local function search(item: Item, canvas: Vector2): Placement?
	local gap = item.Gap or 6
	local minScale = item.MinScale or 0.5
	local maxScale = item.MaxScale or 1
	local scales = {}
	for _, s in ipairs(SCALES) do
		if s <= maxScale + 1e-6 and s >= minScale - 1e-6 then
			table.insert(scales, s)
		end
	end
	if #scales == 0 then
		table.insert(scales, math.clamp(1, minScale, maxScale))
	end
	local shapes = { { item.W, item.H, false } }
	if item.AltW and item.AltH then
		table.insert(shapes, { item.AltW, item.AltH, true })
	end
	local anchorX, anchorY = item.Anchor.X * canvas.X, item.Anchor.Y * canvas.Y
	local diagonal = math.max(1, canvas.Magnitude)
	local cols, rows, occ = grid.Cols, grid.Rows, grid.Occ

	local best: Placement? = nil
	local bestScore = math.huge
	for _, shape in ipairs(shapes) do
		local w, h = shape[1], shape[2]
		-- Taille en cases pour chaque échelle
		local cellsW, cellsH = {}, {}
		for index, s in ipairs(scales) do
			cellsW[index] = math.ceil((w * s + gap * 2) / CELL)
			cellsH[index] = math.ceil((h * s + gap * 2) / CELL)
		end
		local smallW, smallH = cellsW[#scales], cellsH[#scales]
		for j = 0, rows - smallH do
			local base = j * cols
			for i = 0, cols - smallW do
				if occ[base + i + 1] == 0 and takenCount(i, j, smallW, smallH) == 0 then
					-- Plus grande échelle qui tient ici (les échelles vont en décroissant)
					local lo, hi = 1, #scales -- hi tient toujours
					while lo < hi do
						local mid = (lo + hi) // 2
						local cw, ch = cellsW[mid], cellsH[mid]
						if i + cw <= cols and j + ch <= rows and takenCount(i, j, cw, ch) == 0 then
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
						best = { X = centreX, Y = centreY, Scale = s, Alt = shape[3] :: boolean, W = w, H = h }
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
			table.insert(parts, string.format("%d,%d,%.2f,%s", math.floor(p.X + 0.5), math.floor(p.Y + 0.5), p.Scale, p.Alt and "a" or "n"))
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

local function plan()
	local canvas = Zones.GetCanvas()
	resetGrid(canvas)
	local results: { { Request: Request, Placements: { Placement | false } } } = {}
	for _, request in ipairs(sortedRequests()) do
		local placements: { Placement | false } = {}
		for index, item in ipairs(request.Items) do
			local found = search(item, canvas)
			if found then
				local w, h = found.W * found.Scale, found.H * found.Scale
				mark({ X = found.X - w / 2, Y = found.Y - h / 2, W = w, H = h }, item.Gap or 6)
				buildSat()
				placements[index] = found
			else
				placements[index] = false
			end
		end
		table.insert(results, { Request = request, Placements = placements })
	end
	-- Rappels (hors de la boucle de calcul)
	for _, result in ipairs(results) do
		local request = result.Request
		if requests[request.Id] == request then
			local signature = signatureOf(result.Placements)
			if signature ~= request.Signature then
				request.Signature = signature
				local ok, err = pcall(request.OnPlace, result.Placements)
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
		if next(requests) == nil then
			return
		end
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
-- API
----------------------------------------------------------------------

-- Profondeur du stimulus : ZIndex de son conteneur dans le calque Background
function Zones.Attach(ctx)
	local depth = Zones.Depth[ctx.Feature]
	if depth and ctx.Container then
		ctx.Container.ZIndex = depth
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
	}
	if previous then
		previous.Signature = nil
	end
	Zones.Schedule()
end

function Zones.Release(id: string)
	if requests[id] then
		requests[id] = nil
		Zones.Schedule()
	end
end

return Zones
