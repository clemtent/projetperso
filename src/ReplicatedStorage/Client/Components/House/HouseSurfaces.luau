--[[
	HouseSurfaces (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseSurfaces

	"On peut poser des objets SUR les meubles" + les chaises à table + les
	places des animaux :
	  - SURFACES : dessus des meubles (tables vides, bureaux, commodes,
	    étagères, lits, canapé, fauteuils, chaises, plan de travail, frigo,
	    étagère MURALE...) en unités de la boîte de dessin 100 x 100
	    (x0, x1, y) ; un petit objet (Formulas.CanGoOnFurniture : déco,
	    plantes, nourriture, lampes, jouets, peluches, coussins, animaux...)
	    peut s'y poser (le serveur accepte alors Y >= TabletopMinY) ;
	  - SIÈGES et TABLES : une chaise / un tabouret / un banc glissé près
	    d'une table se range sur un de ses côtés (tournée vers elle), derrière
	    (le dossier dépasse du plateau) ou devant ; elle suit ensuite la
	    table quand on la déplace (Dependents) et passe devant / derrière
	    elle au bon moment (Order) ;
	  - PET_SPOTS : où les animaux vont dormir / manger / boire / jouer /
	    griffer / se percher / se cacher (niche, arbre à chat, gamelle...) ;
	  - support d'un objet posé (le meuble sous ses pieds) et table d'une
	    chaise, déduits de la géométrie seule (rien de plus n'est sauvegardé,
	    à part F = chaise retournée vers la table) ;
	  - ORDRE D'AFFICHAGE : muraux, tapis, puis le sol (couche Z, puis Y) ;
	    un objet posé sur un meuble passe juste devant son meuble, une chaise
	    derrière / à côté d'une table juste derrière elle, une chaise devant
	    juste devant (après ce qui est posé sur la table).
	Coordonnées d'un objet posé : X, Y = fraction de la pièce (pieds pour
	les objets au sol, centre pour les objets muraux), taille à l'écran =
	item.Size x S px de maquette.
	Aucune interface ici (utilisé par l'éditeur, les animaux et les
	mini-pièces de la vue d'ensemble).
]]

local HouseCommon = require(script.Parent.HouseCommon)

type Item = HouseCommon.Item
type Placed = HouseCommon.Placed

local HouseSurfaces = {}

-- Dessus des meubles : { x0, x1, y } (boîte 100 x 100)
local SURFACES: { [string]: { { number } } } = {
	-- meubles d'origine
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
	GamingChair = { { 20, 80, 63 } },
	Bathtub = { { 4, 96, 46 } },
	Aquarium = { { 5, 95, 16 } },
	RetroTV = { { 10, 90, 23 } },
	Stove = { { 6, 94, 38 } },
	Fridge = { { 24, 76, 4 } },
	SundaeBar = { { 5, 95, 54 } },
	Toilet = { { 26, 74, 18 } },
	-- v9 : tables et meubles à dessus vide (Art/Tables)
	SideTable = { { 8, 92, 38 } },
	CafeTable = { { 6, 94, 30 } },
	CoffeeTable = { { 3, 97, 51 } },
	DiningTable = { { 2, 98, 35 } },
	BarTable = { { 12, 88, 16 } },
	Dresser = { { 4, 96, 37 } },
	TVStand = { { 2, 98, 53 } },
	KitchenIsland = { { 2, 98, 37 } },
	PicnicTable = { { 4, 96, 39 }, { 2, 98, 71 } },
	BigDesk = { { 2, 98, 37 } },
	-- v9 : sièges (un chat sur la chaise, une peluche dans le fauteuil...)
	MushroomStool = { { 24, 76, 15 } },
	FloorCushion = { { 18, 82, 49 } },
	DiningChair = { { 32, 82, 52 } },
	BarStool = { { 26, 74, 26 } },
	Armchair = { { 22, 78, 63 } },
	GardenBench = { { 8, 92, 59 } },
	RockingChair = { { 26, 80, 57 } },
	DoubleBed = { { 10, 90, 58 } },
	EggChair = { { 50, 78, 61 } },
	-- v9 : étagère MURALE (objet mural : boîte centrée sur son Y)
	FloatingShelf = { { 6, 94, 34 }, { 6, 94, 72 } },
}

-- Meubles "lits" : les animaux grimpeurs y font la sieste
local BEDS: { [string]: boolean } = {
	LoftBed = true,
	CanopyBed = true,
	CloudBed = true,
	Sofa = true,
	DoubleBed = true,
	Armchair = true,
	EggChair = true,
	FloorCushion = true,
	GardenBench = true,
}

-- Sièges : View = "Side" (dessin de profil qui regarde à droite : retourné
-- pour regarder vers la gauche), "Front" (de face) ou "Round" (tabouret,
-- coussin : pareil de tous les côtés) ; Half = demi-largeur visible
-- (fraction de la taille) ; Front = distance centre -> bord avant (profil)
export type SeatInfo = { View: string, Half: number, Front: number? }
local SEATS: { [string]: SeatInfo } = {
	WoodenChair = { View = "Front", Half = 0.4 },
	GamingChair = { View = "Front", Half = 0.34 },
	DiningChair = { View = "Side", Half = 0.33, Front = 0.34 },
	RockingChair = { View = "Side", Half = 0.4, Front = 0.3 },
	MushroomStool = { View = "Round", Half = 0.42 },
	FloorCushion = { View = "Round", Half = 0.46 },
	BarStool = { View = "Round", Half = 0.3 },
	Armchair = { View = "Front", Half = 0.48 },
	GardenBench = { View = "Front", Half = 0.46 },
	Beanbag = { View = "Round", Half = 0.46 },
}

-- Tables "où l'on s'assoit" (chaises rangées autour)
local TABLES: { [string]: boolean } = {
	DiningTable = true,
	CafeTable = true,
	CoffeeTable = true,
	SideTable = true,
	BarTable = true,
	KitchenIsland = true,
	PicnicTable = true,
	BigDesk = true,
	StudyDesk = true,
	VanityTable = true,
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
local SNAP_SIDE = 0.012 -- débord gauche / droite accepté
local SUPPORT_EPS = 0.006 -- tolérance pour retrouver le meuble sous un objet

-- Chaises autour d'une table (fractions de la hauteur de la pièce)
local SIDE_DY = 0.006 -- côté : juste derrière la table (le plateau passe devant l'assise)
local BEHIND_DY = 0.03 -- derrière : au moins ça...
local BEHIND_MAX = 0.085 -- ...au plus ça (grande table, petite chaise)
local BEHIND_PEEK = 0.03 -- le dossier dépasse du plateau d'environ ça
local FRONT_DY = 0.03 -- devant
local TUCK = 0.12 -- (fraction de la taille) l'avant d'une chaise de profil glisse sous le plateau
local SEAT_EPS_Y = 0.007
local SEAT_EPS_X = 0.035
local SEAT_SNAP_X = 0.1 -- (fraction de la largeur) distance d'aimantation autour d'une place
local SEAT_SNAP_Y = 0.075

export type Surface = {
	Entry: Placed,
	L: number, -- bords (fraction de la largeur de la pièce)
	R: number,
	Y: number, -- hauteur du dessus (fraction de la hauteur)
	Base: number, -- bas du meuble (pieds d'un meuble au sol, bas d'une étagère murale)
	Index: number, -- n° du dessus (meuble à plusieurs dessus)
}

-- Place d'une chaise à une table
export type SeatSpot = {
	Table: Placed,
	Kind: string, -- "Left" | "Right" | "Behind" | "Front"
	X: number,
	Y: number,
	F: boolean?, -- la chaise doit être retournée (regarde à gauche)
	L: number, -- bornes du plateau (pour les indices visuels)
	R: number,
	Top: number,
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

function HouseSurfaces.IsSeat(itemId: string): boolean
	return SEATS[itemId] ~= nil
end

function HouseSurfaces.Seat(itemId: string): SeatInfo?
	return SEATS[itemId]
end

function HouseSurfaces.IsTable(itemId: string): boolean
	return TABLES[itemId] == true and SURFACES[itemId] ~= nil
end

-- Petit objet qu'on peut poser sur un meuble (même règle que le serveur)
function HouseSurfaces.CanStandOn(item: Item?): boolean
	return HouseCommon.CanGoOnFurniture(item)
end

function HouseSurfaces.MinY(): number
	return tonumber((HouseCommon.Config :: any).TabletopMinY) or 0.12
end

-- Boîte 100 x 100 d'un objet posé -> pièce (fractions). Objet au sol : ses
-- pieds (y = 100) sont en entry.Y ; objet mural : son centre (y = 50).
-- Objet retourné (F) : la boîte est lue en miroir (x -> 100 - x).
function HouseSurfaces.BoxToRoom(entry: Placed, item: Item, bx: number, by: number, roomW: number, roomH: number): (number, number)
	local k = item.Size * entry.S / 100
	local anchor = item.Placement == "Wall" and 50 or 100
	if entry.F == true then
		bx = 100 - bx
	end
	return (entry.X * roomW + (bx - 50) * k) / roomW, (entry.Y * roomH - (anchor - by) * k) / roomH
end

-- Pièce (fractions) -> boîte 100 x 100 d'un objet posé
function HouseSurfaces.RoomToBox(entry: Placed, item: Item, x: number, y: number, roomW: number, roomH: number): (number, number)
	local k = math.max(1e-3, item.Size * entry.S / 100)
	local anchor = item.Placement == "Wall" and 50 or 100
	local bx = 50 + (x - entry.X) * roomW / k
	if entry.F == true then
		bx = 100 - bx
	end
	return bx, anchor - (entry.Y - y) * roomH / k
end

-- Bas d'un objet posé (fraction de la hauteur)
local function baseOf(entry: Placed, item: Item, roomH: number): number
	if item.Placement == "Wall" then
		return entry.Y + item.Size * entry.S * 0.5 / math.max(1, roomH)
	end
	return entry.Y
end

-- Surfaces d'un objet posé (fractions de la pièce)
function HouseSurfaces.Of(entry: Placed, roomW: number, roomH: number): { Surface }
	local result: { Surface } = {}
	local item = HouseCommon.ItemsById[entry.I]
	local list = SURFACES[entry.I]
	if not item or not list then
		return result
	end
	local base = baseOf(entry, item, roomH)
	for index, s in ipairs(list) do
		local a, y = HouseSurfaces.BoxToRoom(entry, item, s[1], s[3], roomW, roomH)
		local b = HouseSurfaces.BoxToRoom(entry, item, s[2], s[3], roomW, roomH)
		-- (objet retourné : les bords s'inversent)
		table.insert(result, { Entry = entry, L = math.min(a, b), R = math.max(a, b), Y = y, Base = base, Index = index })
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
				if x >= surface.L - SNAP_SIDE and x <= surface.R + SNAP_SIDE
					and y >= surface.Y - SNAP_UP and y <= surface.Y + down
					and surface.Y >= minY and surface.Y - height * 0.92 > -0.02 then
					-- (le plus proche en hauteur ; à égalité, le meuble le plus en avant)
					local score = math.abs(y - surface.Y) - surface.Base * 0.001
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

-- Toutes les surfaces où cet objet peut aller (indices pendant un glissement)
function HouseSurfaces.All(list: { Placed }, height: number, roomW: number, roomH: number, skip: { [Placed]: boolean }?): { Surface }
	local result: { Surface } = {}
	local minY = HouseSurfaces.MinY()
	for _, other in ipairs(list) do
		if not excluded(other, skip) and SURFACES[other.I] then
			for _, surface in ipairs(HouseSurfaces.Of(other, roomW, roomH)) do
				if surface.Y >= minY and surface.Y - height * 0.92 > -0.02 and surface.R - surface.L > 0.01 then
					table.insert(result, surface)
				end
			end
		end
	end
	return result
end

-- Meuble sur lequel un objet est posé (nil = au sol / au mur)
function HouseSurfaces.SupportOf(entry: Placed, list: { Placed }, roomW: number, roomH: number): Surface?
	local item = HouseCommon.ItemsById[entry.I]
	if not item or item.Placement ~= "Floor" or not HouseCommon.CanGoOnFurniture(item) then
		return nil
	end
	local best: Surface? = nil
	local bestScore = math.huge
	for _, other in ipairs(list) do
		if other ~= entry and SURFACES[other.I] then
			for _, surface in ipairs(HouseSurfaces.Of(other, roomW, roomH)) do
				local dy = math.abs(surface.Y - entry.Y)
				if dy <= SUPPORT_EPS and surface.Base > entry.Y + 0.002 and entry.X >= surface.L - 0.01 and entry.X <= surface.R + 0.01
					and dy < bestScore then
					bestScore = dy
					best = surface
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------------
-- Chaises à table
----------------------------------------------------------------------

-- Plateau d'une table (1er dessus) : (gauche, droite, haut) en fractions
local function tableTop(tableEntry: Placed, roomW: number, roomH: number): (number?, number?, number?)
	local surfaces = HouseSurfaces.Of(tableEntry, roomW, roomH)
	local top = surfaces[1]
	if not top then
		return nil, nil, nil
	end
	return top.L, top.R, top.Y
end

-- Demi-largeur visible d'une chaise (fraction de la largeur de la pièce)
local function seatHalf(info: SeatInfo, item: Item, scale: number, roomW: number): number
	return item.Size * scale * info.Half / math.max(1, roomW)
end

-- Places possibles d'une chaise autour d'une table. `px` = x voulu (pour
-- derrière / devant : la chaise glisse le long de la table)
function HouseSurfaces.SeatSpots(tableEntry: Placed, seatItem: Item, seatScale: number, px: number, roomW: number, roomH: number): { SeatSpot }
	local spots: { SeatSpot } = {}
	local info = SEATS[seatItem.Id]
	if not info or not HouseSurfaces.IsTable(tableEntry.I) then
		return spots
	end
	local l, r, top = tableTop(tableEntry, roomW, roomH)
	if not l or not r or not top then
		return spots
	end
	local size = seatItem.Size * seatScale / math.max(1, roomW)
	local half = seatHalf(info, seatItem, seatScale, roomW)
	local reach
	if info.View == "Side" then
		-- l'avant de la chaise (profil) glisse un peu sous le plateau
		reach = ((info.Front or half) - TUCK) * seatItem.Size * seatScale / math.max(1, roomW)
	else
		reach = half * 0.8
	end
	local sideY = tableEntry.Y - SIDE_DY
	table.insert(spots, { Table = tableEntry, Kind = "Left", X = l - reach, Y = sideY, F = nil, L = l, R = r, Top = top })
	table.insert(spots, { Table = tableEntry, Kind = "Right", X = r + reach, Y = sideY, F = info.View == "Side" or nil, L = l, R = r, Top = top })
	-- derrière / devant : le long du plateau (si la chaise tient dessous)
	local inner = math.max(0, (r - l) / 2 - half * 0.7)
	local mid = (l + r) / 2
	local x = math.clamp(px, mid - inner, mid + inner)
	if r - l >= size * 0.5 then
		-- derrière : assez loin pour que le dossier dépasse un peu du plateau
		local tableTopHeight = tableEntry.Y - top
		local seatHeight = seatItem.Size * seatScale * 0.9 / math.max(1, roomH)
		local behind = math.clamp(tableTopHeight - seatHeight + BEHIND_PEEK, BEHIND_DY, BEHIND_MAX)
		table.insert(spots, { Table = tableEntry, Kind = "Behind", X = x, Y = tableEntry.Y - behind, F = nil, L = l, R = r, Top = top })
		table.insert(spots, { Table = tableEntry, Kind = "Front", X = x, Y = tableEntry.Y + FRONT_DY, F = nil, L = l, R = r, Top = top })
	end
	return spots
end

-- Place la plus proche d'une chaise qu'on déplace (pieds en x, y) : nil si
-- aucune table n'est assez près
function HouseSurfaces.FindSeat(list: { Placed }, seatEntry: Placed, x: number, y: number, roomW: number, roomH: number, skip: { [Placed]: boolean }?): SeatSpot?
	local item = HouseCommon.ItemsById[seatEntry.I]
	if not item or not SEATS[item.Id] then
		return nil
	end
	local best: SeatSpot? = nil
	local bestScore = math.huge
	for _, other in ipairs(list) do
		if other ~= seatEntry and not excluded(other, skip) and HouseSurfaces.IsTable(other.I) then
			for _, spot in ipairs(HouseSurfaces.SeatSpots(other, item, seatEntry.S, x, roomW, roomH)) do
				local dx = math.abs(x - spot.X) / SEAT_SNAP_X
				local dy = math.abs(y - spot.Y) / SEAT_SNAP_Y
				if dx <= 1 and dy <= 1 then
					local score = dx * dx + dy * dy
					if score < bestScore then
						bestScore = score
						best = spot
					end
				end
			end
		end
	end
	return best
end

-- Table à laquelle une chaise est rangée (et la place) ; nil sinon
function HouseSurfaces.SeatedAt(seatEntry: Placed, list: { Placed }, roomW: number, roomH: number): SeatSpot?
	local item = HouseCommon.ItemsById[seatEntry.I]
	if not item or not SEATS[item.Id] then
		return nil
	end
	local best: SeatSpot? = nil
	local bestScore = math.huge
	for _, other in ipairs(list) do
		if other ~= seatEntry and HouseSurfaces.IsTable(other.I) then
			for _, spot in ipairs(HouseSurfaces.SeatSpots(other, item, seatEntry.S, seatEntry.X, roomW, roomH)) do
				local dy = math.abs(seatEntry.Y - spot.Y)
				local dx = math.abs(seatEntry.X - spot.X)
				if dy <= SEAT_EPS_Y and dx <= SEAT_EPS_X then
					local score = dy * 4 + dx
					if score < bestScore then
						bestScore = score
						best = spot
					end
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------------
-- Ce qui suit un meuble
----------------------------------------------------------------------

-- Objets posés (directement ou non) sur `entry`, et chaises rangées à cette
-- table (avec ce qui est posé dessus) : ils bougent avec elle. 2e valeur :
-- le parent direct de chacun (meuble porteur ou table de la chaise).
function HouseSurfaces.Dependents(entry: Placed, list: { Placed }, roomW: number, roomH: number): ({ Placed }, { [Placed]: Placed })
	local result: { Placed } = {}
	if not SURFACES[entry.I] then
		return result, {}
	end
	-- (une seule passe pour connaître le support / la table de chacun)
	local parentOf: { [Placed]: Placed } = {}
	for _, other in ipairs(list) do
		if other ~= entry then
			local support = HouseSurfaces.SupportOf(other, list, roomW, roomH)
			if support then
				parentOf[other] = support.Entry
			else
				local seat = HouseSurfaces.SeatedAt(other, list, roomW, roomH)
				if seat then
					parentOf[other] = seat.Table
				end
			end
		end
	end
	local seen: { [Placed]: boolean } = { [entry] = true }
	local queue = { entry }
	while #queue > 0 do
		local current = table.remove(queue, 1) :: Placed
		for _, other in ipairs(list) do
			if not seen[other] and parentOf[other] == current then
				seen[other] = true
				table.insert(result, other)
				table.insert(queue, other)
			end
		end
	end
	return result, parentOf
end

-- Préférence d'un petit objet pour un meuble quand on le pose depuis
-- l'inventaire : 2 = idéal (nourriture sur une table, coussin sur un lit...),
-- 1 = possible, 0 = à éviter (le joueur peut quand même l'y mettre)
local SOFT_ITEMS: { [string]: boolean } = {
	HeartPillow = true,
	MoonPillow = true,
	BlanketStack = true,
}
function HouseSurfaces.Preference(item: Item, furnitureId: string): number
	local bed = BEDS[furnitureId] == true
	local seat = SEATS[furnitureId] ~= nil
	if item.Category == "Kitchen" then
		return (bed or seat) and 0 or (TABLES[furnitureId] and 2 or 1)
	elseif SOFT_ITEMS[item.Id] or item.Category == "Toys" or item.Category == "Pets" then
		return bed and 2 or 1
	end
	return (bed or seat) and 0 or 1
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

-- Liste triée de l'arrière vers l'avant : un objet posé sur un meuble est
-- dessiné juste devant ce meuble (et ce qui est devant le meuble reste
-- devant lui) ; une chaise rangée à côté / derrière une table juste avant
-- elle, une chaise devant la table juste après ce qui est posé dessus.
function HouseSurfaces.Order(list: { Placed }, roomW: number, roomH: number, rankOf: RankOf?): { Placed }
	local rank = rankOf or defaultRank
	-- Parent direct (meuble porteur ou table) et niveau relatif à lui
	local parentOf: { [Placed]: Placed } = {}
	local stepOf: { [Placed]: number } = {}
	for _, entry in ipairs(list) do
		local support = HouseSurfaces.SupportOf(entry, list, roomW, roomH)
		if support then
			parentOf[entry] = support.Entry
			stepOf[entry] = 1
		else
			local seat = HouseSurfaces.SeatedAt(entry, list, roomW, roomH)
			if seat then
				parentOf[entry] = seat.Table
				stepOf[entry] = seat.Kind == "Front" and 10 or -20
			end
		end
	end
	local rootOf: { [Placed]: Placed } = {}
	local levelOf: { [Placed]: number } = {}
	for _, entry in ipairs(list) do
		local root = entry
		local level = 0
		local depth = 0
		-- (chaîne courte : une tasse sur un livre sur une table ; un chat sur une chaise à table)
		while parentOf[root] and depth < 5 do
			level += stepOf[root] or 1
			root = parentOf[root]
			depth += 1
		end
		rootOf[entry] = root
		levelOf[entry] = level
	end
	local indexOf: { [Placed]: number } = {}
	for index, entry in ipairs(list) do
		indexOf[entry] = index
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
			return (indexOf[ra] or 0) < (indexOf[rb] or 0)
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
		if a.X ~= b.X then
			return a.X < b.X
		end
		return (indexOf[a] or 0) < (indexOf[b] or 0)
	end)
	return sorted
end

return HouseSurfaces
