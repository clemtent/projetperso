--[[
	HouseSurfaces (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseSurfaces

	"On peut poser des objets SUR les meubles" + les places des animaux :
	  - SURFACES : dessus des meubles (tables, bureaux, tables de nuit,
	    étagères, commodes, manteau de cheminée, lits, canapé...) en unités
	    de la boîte de dessin 100 x 100 (x0, x1, y) ; un petit objet "Floor"
	    (Size <= Config.House.TabletopMaxSize) peut s'y poser (le serveur
	    accepte Y >= TabletopMinY pour ces objets) ;
	  - PET_SPOTS : où les animaux vont dormir / manger / boire / jouer /
	    griffer / se percher / se cacher (niche, arbre à chat, gamelle...) ;
	  - support d'un objet posé (le meuble sous ses pieds), déduit de la
	    géométrie seule (rien de plus n'est sauvegardé) ;
	  - ORDRE D'AFFICHAGE : muraux, tapis, puis le sol (couche Z, puis Y) ;
	    un objet posé sur un meuble passe juste devant son meuble.
	Coordonnées d'un objet posé : X, Y = fraction de la pièce (pieds pour
	les objets au sol), taille à l'écran = item.Size x S px de maquette.
	Aucune interface ici (utilisé par l'éditeur, les animaux et les
	mini-pièces de la vue d'ensemble).
]]

local HouseCommon = require(script.Parent.HouseCommon)

type Item = HouseCommon.Item
type Placed = HouseCommon.Placed

local HouseSurfaces = {}

-- Dessus des meubles : { x0, x1, y } (boîte 100 x 100)
local SURFACES: { [string]: { { number } } } = {
	WoodenChair = { { 16, 84, 52 } },
	StorageBox = { { 14, 86, 47 } },
	Nightstand = { { 8, 92, 44 } },
	DrawerCabinet = { { 8, 94, 24 } },
	StudyDesk = { { 4, 96, 48 } },
	Bookshelf = { { 8, 92, 9 } },
	VanityTable = { { 4, 96, 55 } },
	Wardrobe = { { 6, 94, 11 } },
	Fireplace = { { 2, 98, 14 } },
	LoftBed = { { 12, 86, 23 }, { 16, 56, 73 } },
	CanopyBed = { { 20, 80, 64 } },
	CloudBed = { { 12, 88, 55 } },
	Sofa = { { 24, 76, 62 } },
	Bathtub = { { 4, 96, 46 } },
	Aquarium = { { 5, 95, 16 } },
	RetroTV = { { 10, 90, 23 } },
	Stove = { { 6, 94, 38 } },
	SundaeBar = { { 5, 95, 54 } },
	Toilet = { { 26, 74, 18 } },
}

-- Meubles "lits" : les animaux grimpeurs y font la sieste
local BEDS: { [string]: boolean } = {
	LoftBed = true,
	CanopyBed = true,
	CloudBed = true,
	Sofa = true,
}

export type Spot = {
	X: number, -- boîte 100 x 100 (pieds de l'animal)
	Y: number,
	Act: string, -- "Sleep" | "Eat" | "Drink" | "Play" | "Scratch" | "Perch" | "Sit" | "Enter"
	Place: string?, -- "Behind" (derrière le meuble) | "Beside" (à côté) | nil = devant / dessus
	High: boolean?, -- place en hauteur (il faut sauter / voler)
	Birds: boolean?, -- réservée aux oiseaux
}

-- Places des animaux dans leurs affaires
local PET_SPOTS: { [string]: { Spot } } = {
	PetBowl = { { X = 50, Y = 64, Act = "Eat", Place = "Behind" } },
	PetFountain = { { X = 50, Y = 72, Act = "Drink", Place = "Behind" } },
	PetToys = { { X = 50, Y = 98, Act = "Play", Place = "Beside" } },
	PetBed = { { X = 50, Y = 86, Act = "Sleep" } },
	ScratchingPost = { { X = 50, Y = 98, Act = "Scratch", Place = "Beside" }, { X = 50, Y = 10, Act = "Perch", High = true } },
	DogHouse = { { X = 50, Y = 98, Act = "Enter" } },
	BirdCage = { { X = 50, Y = 12, Act = "Perch", High = true, Birds = true } },
	CatTree = {
		{ X = 36, Y = 12, Act = "Sleep", High = true },
		{ X = 74, Y = 57, Act = "Sit", High = true },
		{ X = 27, Y = 86, Act = "Enter" },
	},
}

local SNAP_UP = 0.1 -- (fraction de la hauteur) on "attrape" une surface un peu au-dessus...
local SNAP_DOWN = 0.07 -- ...ou un peu en dessous des pieds
local SUPPORT_EPS = 0.006 -- tolérance pour retrouver le meuble sous un objet

export type Surface = {
	Entry: Placed,
	L: number, -- bords (fraction de la largeur de la pièce)
	R: number,
	Y: number, -- hauteur du dessus (fraction de la hauteur)
	Base: number, -- pieds du meuble (Y du meuble)
}

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

function HouseSurfaces.Has(itemId: string): boolean
	return SURFACES[itemId] ~= nil
end

function HouseSurfaces.IsBed(itemId: string): boolean
	return BEDS[itemId] == true
end

function HouseSurfaces.Spots(itemId: string): { Spot }?
	return PET_SPOTS[itemId]
end

-- Données brutes (outils de rendu / tests)
function HouseSurfaces.Raw(itemId: string): { { number } }?
	return SURFACES[itemId]
end

-- Petit objet "de sol" qu'on peut poser sur un meuble
function HouseSurfaces.CanStandOn(item: Item?): boolean
	if not item or item.Placement ~= "Floor" then
		return false
	end
	local maxSize = tonumber((HouseCommon.Config :: any).TabletopMaxSize) or 0
	return item.Size <= maxSize
end

function HouseSurfaces.MinY(): number
	return tonumber((HouseCommon.Config :: any).TabletopMinY) or 0.22
end

-- Boîte 100 x 100 d'un objet posé -> pièce (fractions)
function HouseSurfaces.BoxToRoom(entry: Placed, item: Item, bx: number, by: number, roomW: number, roomH: number): (number, number)
	local k = item.Size * entry.S / 100
	return (entry.X * roomW + (bx - 50) * k) / roomW, (entry.Y * roomH - (100 - by) * k) / roomH
end

-- Pièce (fractions) -> boîte 100 x 100 d'un objet posé
function HouseSurfaces.RoomToBox(entry: Placed, item: Item, x: number, y: number, roomW: number, roomH: number): (number, number)
	local k = math.max(1e-3, item.Size * entry.S / 100)
	return 50 + (x - entry.X) * roomW / k, 100 - (entry.Y - y) * roomH / k
end

-- Surfaces d'un objet posé (fractions de la pièce)
function HouseSurfaces.Of(entry: Placed, roomW: number, roomH: number): { Surface }
	local result: { Surface } = {}
	local item = HouseCommon.ItemsById[entry.I]
	local list = SURFACES[entry.I]
	if not item or not list or item.Placement ~= "Floor" then
		return result
	end
	for _, s in ipairs(list) do
		local l, y = HouseSurfaces.BoxToRoom(entry, item, s[1], s[3], roomW, roomH)
		local r = HouseSurfaces.BoxToRoom(entry, item, s[2], s[3], roomW, roomH)
		table.insert(result, { Entry = entry, L = l, R = r, Y = y, Base = entry.Y })
	end
	return result
end

-- Objets qui ne doivent pas servir de support (l'objet lui-même et ce qu'il porte)
local function excluded(entry: Placed, skip: { [Placed]: boolean }?): boolean
	return skip ~= nil and skip[entry] == true
end

-- Surface la plus proche d'un point (pieds d'un objet qu'on déplace) ;
-- nil si aucune. `height` = hauteur de l'objet (fraction) : sa tête ne doit
-- pas traverser le plafond.
function HouseSurfaces.Find(list: { Placed }, x: number, y: number, height: number, roomW: number, roomH: number, skip: { [Placed]: boolean }?): Surface?
	local best: Surface? = nil
	local bestScore = math.huge
	local minY = HouseSurfaces.MinY()
	for _, other in ipairs(list) do
		if not excluded(other, skip) and SURFACES[other.I] then
			for _, surface in ipairs(HouseSurfaces.Of(other, roomW, roomH)) do
				local down = math.min(SNAP_DOWN, math.max(0.015, (surface.Base - surface.Y) * 0.55))
				local tolerance = 0.012
				if x >= surface.L - tolerance and x <= surface.R + tolerance
					and y >= surface.Y - SNAP_UP and y <= surface.Y + down
					and surface.Y >= minY and surface.Y - height * 0.92 > -0.02 then
					local score = math.abs(y - surface.Y)
					if score < bestScore then
						bestScore = score
						best = surface
					end
				end
			end
		end
	end
	return best
end

-- Meuble sur lequel un objet est posé (nil = au sol / au mur)
function HouseSurfaces.SupportOf(entry: Placed, list: { Placed }, roomW: number, roomH: number): Surface?
	local item = HouseCommon.ItemsById[entry.I]
	if not HouseSurfaces.CanStandOn(item) then
		return nil
	end
	local best: Surface? = nil
	local bestScore = math.huge
	for _, other in ipairs(list) do
		if other ~= entry and SURFACES[other.I] and other.Y > entry.Y then
			for _, surface in ipairs(HouseSurfaces.Of(other, roomW, roomH)) do
				local dy = math.abs(surface.Y - entry.Y)
				if dy <= SUPPORT_EPS and entry.X >= surface.L - 0.01 and entry.X <= surface.R + 0.01 and dy < bestScore then
					bestScore = dy
					best = surface
				end
			end
		end
	end
	return best
end

-- Objets posés (directement ou non) sur `entry`
function HouseSurfaces.Dependents(entry: Placed, list: { Placed }, roomW: number, roomH: number): { Placed }
	local result: { Placed } = {}
	if not SURFACES[entry.I] then
		return result
	end
	local seen: { [Placed]: boolean } = { [entry] = true }
	local queue = { entry }
	while #queue > 0 do
		local current = table.remove(queue, 1) :: Placed
		for _, other in ipairs(list) do
			if not seen[other] then
				local support = HouseSurfaces.SupportOf(other, list, roomW, roomH)
				if support and support.Entry == current then
					seen[other] = true
					table.insert(result, other)
					table.insert(queue, other)
				end
			end
		end
	end
	return result
end

----------------------------------------------------------------------
-- Ordre d'affichage
----------------------------------------------------------------------

-- Rang de zone : 0 = mural, 1 = à plat (tapis), 2 = au sol
export type RankOf = (entry: Placed) -> number

local function defaultRank(entry: Placed): number
	local item = HouseCommon.ItemsById[entry.I]
	if item and item.Placement == "Wall" then
		return 0
	end
	return 2
end

-- Liste triée de l'arrière vers l'avant : un objet posé sur un meuble
-- est dessiné juste devant ce meuble (et ce qui est devant le meuble
-- reste devant lui).
function HouseSurfaces.Order(list: { Placed }, roomW: number, roomH: number, rankOf: RankOf?): { Placed }
	local rank = rankOf or defaultRank
	local rootOf: { [Placed]: Placed } = {}
	local levelOf: { [Placed]: number } = {}
	for _, entry in ipairs(list) do
		local root = entry
		local level = 0
		local support = HouseSurfaces.SupportOf(entry, list, roomW, roomH)
		-- (chaîne courte : une tasse sur un livre sur une table)
		while support and level < 4 do
			root = support.Entry
			level += 1
			support = HouseSurfaces.SupportOf(root, list, roomW, roomH)
		end
		rootOf[entry] = root
		levelOf[entry] = level
	end
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		local ra, rb = rootOf[a], rootOf[b]
		local za, zb = rank(ra), rank(rb)
		if za ~= zb then
			return za < zb
		end
		if ra ~= rb then
			if ra.Z ~= rb.Z then
				return ra.Z < rb.Z
			end
			if ra.Y ~= rb.Y then
				return ra.Y < rb.Y
			end
			if ra.X ~= rb.X then
				return ra.X < rb.X
			end
			return (table.find(list, ra) or 0) < (table.find(list, rb) or 0)
		end
		local la, lb = levelOf[a], levelOf[b]
		if la ~= lb then
			return la < lb
		end
		if a.Z ~= b.Z then
			return a.Z < b.Z
		end
		if a.Y ~= b.Y then
			return a.Y < b.Y
		end
		return a.X < b.X
	end)
	return sorted
end

return HouseSurfaces
