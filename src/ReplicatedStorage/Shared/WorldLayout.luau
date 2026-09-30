--[[
	WorldLayout (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > WorldLayout

	🚶 Dopamine Town : géométrie PARTAGÉE serveur + client (+ tests), sans
	aucun service Roblox (sauf les petites fonctions CFrame, en jeu seulement).
	Le serveur s'en sert pour placer les parcelles, faire apparaître les
	personnages devant les portes et vérifier les sièges / les intrus ; le
	client pour construire les maisons au même endroit et pour convertir les
	déplacements de meubles 3D <-> positions 2D (X / Y de HouseCommon.Placed).
	Une seule source de vérité : la 2D.

	Repère d'une maison ("local") : x vers la DROITE d'un visiteur qui regarde
	la façade depuis la place, y vers le haut (0 = sol de la parcelle),
	d = profondeur depuis la façade (0 = face avant du mur de devant).
	Colonnes de la maison : [pièce 1] [pièce 2]... avec la cage d'escalier
	(HALL_W) là où la maison 2D dessine l'entrée (HallAfter : à droite, ou
	au milieu pour le manoir) ; étage 1 = rez-de-chaussée (comme
	HouseCommon.SlotCell), posé sur un soubassement de PLINTH studs.
	Chaque pièce = une coque House3DScene.BuildRoomShell (murs de WALL_T HORS
	de l'intérieur) dont les objets sont placés par House3DScene.PlaceItems.
	Correspondance 2D -> 3D d'une pièce (HouseRoom : X 0..1 de gauche à droite,
	Y 0..1 de haut en bas, WallRatio = limite mur / sol) : MÊME calcul que
	House3DLayout (perspective des murs de côté 2D, courbe de profondeur) ;
	FloorInverse / WallInverse le défont (déplacer un meuble avec l'avatar).
	Rotation (champ R facultatif d'un objet posé) : degrés entiers multiples de
	15 dans 15..345 ; nil / absent = 0 (anciennes sauvegardes).
]]

local WorldLayout = {}

----------------------------------------------------------------------
-- Dimensions (studs)
----------------------------------------------------------------------

WorldLayout.PX = 0.036 -- studs par px de maquette 2D (objets à taille d'avatar)
WorldLayout.ROOM_BASE_PX = 760 -- largeur 2D d'une pièce de largeur 1 (= HouseRoom.BASE_WIDTH)
WorldLayout.ROOM_HEIGHT_PX = 440 -- hauteur 2D d'une pièce (= HouseRoom.HEIGHT)
WorldLayout.DEPTH = 24 -- profondeur INTÉRIEURE d'une pièce (v9.4 : 24, place pour un vrai escalier)
WorldLayout.WALL_H = 12 -- hauteur sous plafond
WorldLayout.SLAB = 1 -- épaisseur d'un plancher
WorldLayout.PLINTH = 2 -- (v9.4) soubassement : le rez-de-chaussée est à PLINTH + SLAB (perron à marches)
WorldLayout.STORY = 13 -- WALL_H + SLAB
WorldLayout.HALL_W = 12 -- cage d'escalier (là où la maison 2D dessine l'entrée : voir HallAfter)
WorldLayout.WALL_T = 1 -- épaisseur des murs (= coque BuildRoomShell : murs HORS de l'intérieur)
WorldLayout.WALL_RATIO = 0.46 -- (valeur par défaut : Config.House.WallRatio)
WorldLayout.ROOF_H = 9
-- (= House3DLayout : murs de côté en perspective de la pièce 2D, courbe de profondeur)
WorldLayout.SIDE_PX = 42
WorldLayout.DEPTH_CURVE = 1.35

-- Parcelles
WorldLayout.PLOT_W = 176 -- largeur (le manoir 3 x 4 et ses tourelles tiennent dedans)
WorldLayout.PLOT_D = 84 -- profondeur
WorldLayout.GARDEN_D = 30 -- jardin entre la rue et la façade
WorldLayout.MIN_PLOTS = 4
WorldLayout.MAX_PLOTS = 50 -- (v10 LAYOUT10 : 12 -> 50, la grande ville ; voir Districts)
WorldLayout.PLAZA_R = 64 -- rayon de la place centrale
WorldLayout.SPAWN_FRONT = 7 -- (studs) apparition devant la porte
-- (v9.4) Rues de la ville : boulevard polygonal (un côté droit devant chaque
-- parcelle), avenue principale de l'entrée (+Z) à la place
WorldLayout.ROAD_W = 20 -- chaussée du boulevard (2 voies)
WorldLayout.WALK_W = 6 -- trottoirs
WorldLayout.AVENUE_W = 16 -- chaussée de l'avenue / des rues
WorldLayout.GROUND_Y = 0.4 -- dessus du pré et des pelouses (repère : Origin().Y)
WorldLayout.ROAD_Y = 0.5 -- dessus de la chaussée
WorldLayout.WALK_Y = 1 -- dessus des trottoirs et de la place (bordure de 0,5)
WorldLayout.GATE_BACK = 60 -- porte de la ville : distance depuis le bord des parcelles côté rue
WorldLayout.SPAWN_INSIDE = 12 -- apparition : juste à l'intérieur de la porte
WorldLayout.TOWN_MARGIN = 140 -- pré au-delà du fond des parcelles (murs invisibles) ; v9.8 : 80 -> 140 (MégaDopa agrandi)

-- Porte d'entrée (dans la cage d'escalier) et passages entre pièces
-- (v9.8 HOUSE98 : "la tête touche" -> toutes les portes font au moins
-- 6 x 9 studs : 6,5 x 9,5 ; la porte d'entrée devient une porte DOUBLE)
WorldLayout.DOOR_W = 6.5
WorldLayout.DOOR_H = 9.5
WorldLayout.PASS_W = 6.5 -- passage entre deux pièces / cage -> pièce (centré en profondeur)
WorldLayout.PASS_H = 9.5

-- Escalier (v9.9 HOUSE99 : "l'escalier est au milieu de l'entrée, ça n'a
-- aucun sens") : une volée droite par étage (étage k -> k+1) LE LONG DU MUR
-- DE DROITE de la cage (StairSpan : bande de STAIR_W), plus jamais face à la
-- porte. Le couloir d'entrée (CorridorSpan, ~7,4 studs) reste libre à gauche,
-- de la porte d'entrée jusqu'à la porte de derrière (vestibule meublé devant).
-- 18 contremarches de STORY / 18 (0,72 stud) ; bas de la volée à STAIR_D0
-- (le battant de la porte d'entrée s'ouvre devant), haut au palier du fond
-- (StairRun : STAIR_D1, ou MANSION_STAIR_D1 : dans le manoir, le passage vers
-- les pièces de DROITE est au fond de la cage, derrière le haut de la volée).
-- Giron = longueur / 17 : ~1,06 stud (pente ~34°) ; manoir ~0,91 (~38°).
-- Les volées des étages sont empilées dans la même bande (12 studs libres
-- entre deux volées). Trémie dans le plancher du dessus (StairHole) : là où
-- le nez des marches dépasse WALL_H - HEADROOM (>= 8,5 studs libres).
-- Collision : une rampe lisse invisible (pas de marche où l'avatar accroche).
-- Tout est dérivé de STORY / DEPTH / WALL_T : les pièces peuvent changer de taille.
WorldLayout.STAIR_W = 4.3 -- largeur de la bande (limon côté couloir compris)
WorldLayout.STAIR_RISERS = 18
WorldLayout.STAIR_STEPS = 18 -- (compat : = STAIR_RISERS)
WorldLayout.STAIR_RISE = WorldLayout.STORY / 18 -- 0,72
WorldLayout.STAIR_D0 = WorldLayout.WALL_T + 2.8 -- 3,8 : premier nez de marche (d)
WorldLayout.STAIR_D1 = WorldLayout.WALL_T + WorldLayout.DEPTH - 3.2 -- 21,8 : arrivée (palier du fond)
WorldLayout.MANSION_BACK_PASS = 5 -- (manoir) passage cage -> pièces de droite, au fond
WorldLayout.MANSION_STAIR_D1 = WorldLayout.WALL_T + WorldLayout.DEPTH - 0.4 - WorldLayout.MANSION_BACK_PASS - 0.3 -- 19,3
WorldLayout.STAIR_TREAD = (WorldLayout.STAIR_D1 - WorldLayout.STAIR_D0) / (WorldLayout.STAIR_RISERS - 1) -- 1,06
-- (v9.8 HOUSE98 : 7,5 -> 8,5 studs de hauteur libre)
WorldLayout.HEADROOM = 8.5
WorldLayout.STAIR_HOLE_D0 = WorldLayout.STAIR_D0
	+ (WorldLayout.WALL_H - WorldLayout.HEADROOM - WorldLayout.STAIR_RISE) / WorldLayout.STAIR_RISE * WorldLayout.STAIR_TREAD -- ~7,9

-- (v9.8 HOUSE98) Porte de DERRIÈRE (vers le jardin) : au rez-de-chaussée,
-- dans le mur du fond de la cage, derrière l'escalier (couloir du fond
-- STAIR_D1..DEPTH, toute la largeur de la cage), même taille que la porte
-- d'entrée ; dehors : palier + BACK_STEPS marches + rampe invisible.
WorldLayout.BACK_LANDING = 3 -- profondeur du palier (studs)
WorldLayout.BACK_STEPS = 3 -- contremarches jusqu'à la pelouse
WorldLayout.BACK_TREAD = 1.25 -- giron d'une marche
WorldLayout.BACK_WALL_OUT = 0.3 -- le mur du fond déborde de 0,3 derrière les pièces

export type SizeDef = { Floors: number, Columns: number, Width: number?, Exterior: string?, Id: string? }

-- Style extérieur (= HouseExterior 2D) d'une taille de maison
local STYLE_BY_SIZE = { Studio = "Cottage", Apartment = "Townhouse", Loft = "Loft", Mansion = "Mansion" }
function WorldLayout.StyleOf(size: SizeDef?): string
	if type(size) ~= "table" then
		return "Cottage"
	end
	local style = size.Exterior or (size.Id and STYLE_BY_SIZE[size.Id :: string])
	return type(style) == "string" and style or "Cottage"
end

local function finite(value: any, default: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return default
end

local function sizeOf(size: SizeDef?): (number, number, number)
	local floors = math.clamp(math.floor(finite(size and size.Floors, 1)), 1, 6)
	local columns = math.clamp(math.floor(finite(size and size.Columns, 1)), 1, 8)
	local width = math.clamp(finite(size and size.Width, 1), 0.5, 2)
	return floors, columns, width
end

local function sizeOfColumns(size: SizeDef?): number
	local _, columns = sizeOf(size)
	return columns
end

-- Largeur 2D (px de maquette) d'une pièce (pour HouseSurfaces / House3DLayout)
function WorldLayout.RoomWidthPx(size: SizeDef?): number
	local _, _, width = sizeOf(size)
	return math.floor(WorldLayout.ROOM_BASE_PX * width + 0.5)
end

-- Largeur INTÉRIEURE (studs) d'une pièce pour une taille de maison
function WorldLayout.RoomWidth(size: SizeDef?): number
	return WorldLayout.RoomWidthPx(size) * WorldLayout.PX
end

export type Dims = {
	Floors: number,
	Columns: number,
	RoomW: number, -- largeur intérieure d'une pièce
	Pitch: number, -- largeur d'une colonne (pièce + ses deux murs)
	Width: number, -- largeur totale (cage + colonnes)
	Depth: number, -- profondeur totale (pièce + murs avant / arrière)
	Height: number, -- jusqu'au plafond du dernier étage
	Left: number, -- x du bord gauche
}

function WorldLayout.Dims(size: SizeDef?): Dims
	local floors, columns = sizeOf(size)
	local roomW = WorldLayout.RoomWidth(size)
	local pitch = roomW + 2 * WorldLayout.WALL_T
	local width = WorldLayout.HALL_W + columns * pitch
	return {
		Floors = floors,
		Columns = columns,
		RoomW = roomW,
		Pitch = pitch,
		Width = width,
		Depth = WorldLayout.DEPTH + 2 * WorldLayout.WALL_T,
		Height = WorldLayout.PLINTH + floors * WorldLayout.STORY,
		Left = -width / 2,
	}
end

-- (v9.4) Nombre de colonnes de pièces À GAUCHE de la cage d'escalier : comme
-- la maison 2D (HouseExterior) — entrée à droite (chaumière, maison de ville,
-- loft), travée centrale pour le manoir
function WorldLayout.HallAfter(size: SizeDef?): number
	local _, columns = sizeOf(size)
	if WorldLayout.StyleOf(size) == "Mansion" then
		return math.floor(columns / 2)
	end
	return columns
end

-- Emplacement -> (étage, colonne) ; même règle que HouseCommon.SlotCell
function WorldLayout.SlotCell(size: SizeDef?, slot: number): (number, number)
	local _, columns = sizeOf(size)
	local s = math.max(1, math.floor(finite(slot, 1)))
	return math.floor((s - 1) / columns) + 1, (s - 1) % columns + 1
end

-- Hauteur (y) du DESSUS du plancher de l'étage `floor`
function WorldLayout.FloorY(floor: number): number
	return WorldLayout.PLINTH + (math.max(1, floor) - 1) * WorldLayout.STORY + WorldLayout.SLAB
end

-- Bords extérieurs (x gauche, x droite) d'une colonne de pièces (murs compris)
function WorldLayout.ColumnSpan(size: SizeDef?, column: number): (number, number)
	local dims = WorldLayout.Dims(size)
	local hall = column > WorldLayout.HallAfter(size) and WorldLayout.HALL_W or 0
	local x0 = dims.Left + hall + (column - 1) * dims.Pitch
	return x0, x0 + dims.Pitch
end

-- Bords de la cage d'escalier
function WorldLayout.HallSpan(size: SizeDef?): (number, number)
	local dims = WorldLayout.Dims(size)
	local x0 = dims.Left + WorldLayout.HallAfter(size) * dims.Pitch
	return x0, x0 + WorldLayout.HALL_W
end

-- Colonne de pièces qui contient x (repère local), nil = cage ou dehors
function WorldLayout.ColumnAt(size: SizeDef?, x: number): number?
	local dims = WorldLayout.Dims(size)
	local hall0, hall1 = WorldLayout.HallSpan(size)
	if x < dims.Left or x > dims.Left + dims.Width or (x > hall0 and x < hall1) then
		return nil
	end
	local rel = x - dims.Left - (x >= hall1 and WorldLayout.HALL_W or 0)
	return math.clamp(math.floor(rel / dims.Pitch) + 1, 1, dims.Columns)
end

-- x du milieu de la porte d'entrée = milieu de la cage (v9.9 : l'escalier
-- est le long du mur de droite, la porte donne sur le couloir d'entrée)
function WorldLayout.DoorX(size: SizeDef?): number
	local x0, x1 = WorldLayout.HallSpan(size)
	return (x0 + x1) / 2
end

-- (v9.9 HOUSE99) Épaisseur de la peau des murs intérieurs de la cage
WorldLayout.HALL_SKIN = 0.15

-- Bande de l'escalier (x gauche, x droite) : contre le mur de DROITE de la cage
-- (x gauche = limon côté couloir, x droite = face intérieure du mur)
function WorldLayout.StairSpan(size: SizeDef?): (number, number)
	local _, h1 = WorldLayout.HallSpan(size)
	local x1 = h1 - WorldLayout.HALL_SKIN
	return x1 - WorldLayout.STAIR_W, x1
end

-- (v9.9) Couloir d'entrée libre (x gauche, x droite) : de la face intérieure
-- du mur de gauche de la cage au limon de l'escalier
function WorldLayout.CorridorSpan(size: SizeDef?): (number, number)
	local h0 = WorldLayout.HallSpan(size)
	local s0 = WorldLayout.StairSpan(size)
	return h0 + WorldLayout.HALL_SKIN, s0
end

-- (v9.9) x du milieu du couloir (chemins des animaux, tests)
function WorldLayout.CorridorX(size: SizeDef?): number
	local x0, x1 = WorldLayout.CorridorSpan(size)
	return (x0 + x1) / 2
end

-- (v9.9) Une volée : premier nez de marche d0, arrivée d1 (d), giron, hauteur
-- de marche. Manoir : arrivée plus tôt (passage du fond vers la droite)
function WorldLayout.StairRun(size: SizeDef?): (number, number, number, number)
	local d0 = WorldLayout.STAIR_D0
	-- (pièces à DROITE de la cage = manoir : leur passage est au fond)
	local d1 = if WorldLayout.HallAfter(size) < sizeOfColumns(size) then WorldLayout.MANSION_STAIR_D1 else WorldLayout.STAIR_D1
	local tread = (d1 - d0) / (WorldLayout.STAIR_RISERS - 1)
	return d0, d1, tread, WorldLayout.STAIR_RISE
end

-- (v9.9) Trémie (d0, d1) dans le plancher de l'étage du dessus : là où le nez
-- des marches dépasse WALL_H - HEADROOM, jusqu'à l'arrivée
function WorldLayout.StairHole(size: SizeDef?): (number, number)
	local d0, d1, tread, rise = WorldLayout.StairRun(size)
	return d0 + (WorldLayout.WALL_H - WorldLayout.HEADROOM - rise) / rise * tread, d1
end

-- (v9.8 HOUSE98) Porte de derrière : x du milieu (repère local de la maison)
-- = milieu de la cage, comme la porte d'entrée (même largeur DOOR_W)
function WorldLayout.BackDoorX(size: SizeDef?): number
	return WorldLayout.DoorX(size)
end

-- d de la face EXTÉRIEURE du mur du fond (seuil de la porte de derrière,
-- au niveau du rez-de-chaussée FloorY(1))
function WorldLayout.BackDoorD(size: SizeDef?): number
	return WorldLayout.Dims(size).Depth + WorldLayout.BACK_WALL_OUT
end

-- d du pied des marches de derrière (sur la pelouse du jardin) : tout ce qui
-- est entre BackDoorD et ça, sur x = BackDoorX ± (DOOR_W / 2 + 1), doit
-- rester libre (palier, marches, rampe)
function WorldLayout.BackStepsD(size: SizeDef?): number
	return WorldLayout.BackDoorD(size) + WorldLayout.BACK_LANDING + WorldLayout.BACK_STEPS * WorldLayout.BACK_TREAD
end

-- Hauteur (au-dessus du sol de l'étage) de la rampe de collision à la
-- profondeur d (v9.9 : ligne du MILIEU des marches, parallèle aux nez : pieds
-- à ± une demi-marche des girons ; 0 avant d0 - giron / 2 ; au milieu de la
-- dernière marche, un bout plus raide rejoint le palier au ras, à d1)
function WorldLayout.StairHeight(d: number, size: SizeDef?): number
	local d0, d1, tread, rise = WorldLayout.StairRun(size)
	local knee = d1 - tread / 2
	local h
	if d <= knee then
		h = (d - d0 + tread / 2) / tread * rise
	else
		h = WorldLayout.STORY - rise + (d - knee) / (tread / 2) * rise
	end
	return math.clamp(h, 0, WorldLayout.STORY)
end

-- (v9.9) Hauteur du dessus du giron (nez de marche) sous d (0 avant la 1re marche)
function WorldLayout.StepTop(d: number, size: SizeDef?): number
	local d0, d1, tread, rise = WorldLayout.StairRun(size)
	if d < d0 then
		return 0
	elseif d >= d1 then
		return WorldLayout.STORY
	end
	return (math.floor((d - d0) / tread) + 1) * rise
end

-- Pente de la volée (degrés)
function WorldLayout.StairSlope(size: SizeDef?): number
	local _, _, tread, rise = WorldLayout.StairRun(size)
	return math.deg(math.atan2(rise, tread))
end

-- (v9.9 HOUSE99) Passage d'un côté d'une pièce (d0, d1 : profondeur, repère
-- local de la maison). Au milieu de la profondeur, sauf dans le manoir : le
-- passage de la cage vers les pièces de DROITE est au fond (derrière le haut
-- de la volée, qui longe ce mur). `side` = "Left" | "Right" (côté de la pièce)
function WorldLayout.PassageSpan(size: SizeDef?, column: number, side: string): (number, number)
	local T = WorldLayout.WALL_T
	local hall = WorldLayout.HallAfter(size)
	if side == "Left" and column == hall + 1 then
		local d1 = T + WorldLayout.DEPTH - 0.4
		return d1 - WorldLayout.MANSION_BACK_PASS, d1
	end
	local mid = T + WorldLayout.DEPTH / 2
	return mid - WorldLayout.PASS_W / 2, mid + WorldLayout.PASS_W / 2
end

-- (v9.9) Passages des murs de la cage : { Left = { d0, d1 }?, Right = { d0, d1 }? }
function WorldLayout.HallPassages(size: SizeDef?): { [string]: { number } }
	local hall = WorldLayout.HallAfter(size)
	local columns = sizeOfColumns(size)
	local out: { [string]: { number } } = {}
	if hall >= 1 then
		local a, b = WorldLayout.PassageSpan(size, hall, "Right")
		out.Left = { a, b }
	end
	if hall < columns then
		local a, b = WorldLayout.PassageSpan(size, hall + 1, "Left")
		out.Right = { a, b }
	end
	return out
end

-- Côtés d'une colonne qui ont un passage (voisin ou cage) : { "Left"?, "Right"? }
function WorldLayout.RoomDoors(size: SizeDef?, column: number): { string }
	local _, columns = sizeOf(size)
	local hall = WorldLayout.HallAfter(size)
	local doors = {}
	if column > 1 or hall == 0 then
		table.insert(doors, "Left")
	end
	if column < columns or hall == columns then
		table.insert(doors, "Right")
	end
	return doors
end

-- Intérieur d'une pièce (repère local) : xMin, xMax, yFloor, dMin, dMax
function WorldLayout.RoomInterior(size: SizeDef?, slot: number): (number, number, number, number, number)
	local floor, column = WorldLayout.SlotCell(size, slot)
	local x0, x1 = WorldLayout.ColumnSpan(size, column)
	local t = WorldLayout.WALL_T
	return x0 + t, x1 - t, WorldLayout.FloorY(floor), t, t + WorldLayout.DEPTH
end

-- (v9.8 HOUSE98) VRAIE fenêtre du mur du fond d'une pièce (côté jardin) :
-- même place et même largeur que la fenêtre de la pièce 2D (HouseRoom : à
-- gauche, 104 x 92 px, 36 px sous le haut du mur ; = House3DScene
-- windowRect), mais prolongée vers le haut jusqu'à BACK_WINDOW_TOP (la
-- partie du mur au-dessus de la 2D, où aucun objet mural ne va) : une
-- porte-fenêtre en hauteur. -> (x0, x1, y0, y1) par rapport au milieu de la
-- pièce (x) et au dessus de son sol (y)
WorldLayout.BACK_WINDOW_TOP = 9.6
function WorldLayout.BackWindowRect(size: SizeDef?, wallRatio: number?): (number, number, number, number)
	local roomWpx = WorldLayout.RoomWidthPx(size)
	local side = WorldLayout.SIDE_PX
	local wallPx = math.floor(WorldLayout.ROOM_HEIGHT_PX * math.clamp(finite(wallRatio, WorldLayout.WALL_RATIO), 0.1, 0.9) + 0.5)
	local k = roomWpx / math.max(1, roomWpx - 2 * side)
	local x2D = side + math.floor(roomWpx * 0.1) + 52
	local cx = ((x2D - side) * k - roomWpx / 2) * WorldLayout.PX
	local ww, wh = 104 * k * WorldLayout.PX, 92 * WorldLayout.PX
	local cy = (wallPx - 36) * WorldLayout.PX - wh / 2
	return cx - ww / 2, cx + ww / 2, cy - wh / 2, math.max(cy + wh / 2, WorldLayout.BACK_WINDOW_TOP)
end

-- Centre du dessus du sol d'une pièce (repère local) : x, y, d
function WorldLayout.RoomCenter(size: SizeDef?, slot: number): (number, number, number)
	local xMin, xMax, yFloor, dMin, dMax = WorldLayout.RoomInterior(size, slot)
	return (xMin + xMax) / 2, yFloor, (dMin + dMax) / 2
end

----------------------------------------------------------------------
-- 2D <-> 3D dans une pièce (même calcul que House3DLayout / PlaceItems)
----------------------------------------------------------------------
-- Repère de la pièce : x vers la droite (0 = milieu), z depuis la face
-- intérieure du mur du fond vers l'avant (0..D). Objet au sol : (x, z) =
-- CENTRE de son empreinte (profondeur fd). Objet mural : y = BAS de sa
-- boîte 2D (pivot du modèle), k = studs par unité (boîte 100 x 100).
-- (House3DLayout écarte aussi les objets qui se chevauchent et colle
-- certains meubles au mur : l'inverse retombe sur la même 2D à ces petits
-- écarts près.)

export type RoomDims = { PX: number, RoomWpx: number, RoomHpx: number, WallPx: number, WallRatio: number, W: number, D: number, WH: number }

function WorldLayout.RoomDims(size: SizeDef?, wallRatio: number?): RoomDims
	local ratio = math.clamp(finite(wallRatio, WorldLayout.WALL_RATIO), 0.1, 0.9)
	local roomWpx = WorldLayout.RoomWidthPx(size)
	return {
		PX = WorldLayout.PX,
		RoomWpx = roomWpx,
		RoomHpx = WorldLayout.ROOM_HEIGHT_PX,
		WallPx = math.floor(WorldLayout.ROOM_HEIGHT_PX * ratio + 0.5),
		WallRatio = ratio,
		W = roomWpx * WorldLayout.PX,
		D = WorldLayout.DEPTH,
		WH = WorldLayout.WALL_H,
	}
end

local function depthT(dims: RoomDims, Y: number): number
	return math.clamp((Y - dims.WallRatio) / math.max(0.05, 1 - dims.WallRatio), 0, 1)
end

-- X 2D -> x (studs, 0 = milieu) à la profondeur t (perspective de la 2D)
local function mapX(dims: RoomDims, X: number, t: number): number
	local sidePx = WorldLayout.SIDE_PX * (1 - math.clamp(t, 0, 1))
	local px = (X * dims.RoomWpx - sidePx) / math.max(1, dims.RoomWpx - 2 * sidePx) * dims.RoomWpx
	return (px - dims.RoomWpx / 2) * dims.PX
end

local function unmapX(dims: RoomDims, x: number, t: number): number
	local sidePx = WorldLayout.SIDE_PX * (1 - math.clamp(t, 0, 1))
	local px = x / dims.PX + dims.RoomWpx / 2
	return (px * math.max(1, dims.RoomWpx - 2 * sidePx) / dims.RoomWpx + sidePx) / dims.RoomWpx
end

-- (v9.6) Meuble "contre le mur" (House3DRecipes Info.Wall : armoire,
-- bibliothèque, frigo...) : collé au mur du fond tant que t < WALL_SNAP_T
-- (même règle que House3DLayout)
WorldLayout.WALL_SNAP_T = 0.55

-- Objet au sol : (X, Y) -> (x, z du centre) ; `fw` / `fd` = empreinte ;
-- `againstWall` = meuble collé au mur du fond (voir WALL_SNAP_T)
function WorldLayout.FloorForward(dims: RoomDims, X: number, Y: number, fw: number, fd: number, againstWall: boolean?): (number, number)
	local t = depthT(dims, finite(Y, 0.8))
	local limit = math.max(0, dims.W / 2 - fw / 2 - 0.1)
	local x = math.clamp(mapX(dims, finite(X, 0.5), t), -limit, limit)
	if againstWall == true and t < WorldLayout.WALL_SNAP_T then
		return x, fd / 2 + 0.08
	end
	local zFront = (t ^ WorldLayout.DEPTH_CURVE) * dims.D
	local z = math.clamp(zFront - fd / 2, fd / 2 + 0.08, math.max(fd / 2 + 0.08, dims.D - fd / 2 - 0.1))
	return x, z
end

-- Inverse : (x, z du centre) -> (X, Y) bornés à la zone du sol
function WorldLayout.FloorInverse(dims: RoomDims, x: number, z: number, fd: number): (number, number)
	local zFront = math.clamp(finite(z, 0) + fd / 2, 0, dims.D)
	local t = (zFront / dims.D) ^ (1 / WorldLayout.DEPTH_CURVE)
	local X = math.clamp(unmapX(dims, finite(x, 0), t), 0, 1)
	return X, math.clamp(dims.WallRatio + t * (1 - dims.WallRatio), dims.WallRatio, 1)
end

-- Objet mural : (X, Y) -> (x, y du pivot = bas de la boîte 2D) ; k = studs par unité
function WorldLayout.WallForward(dims: RoomDims, X: number, Y: number, fw: number, k: number): (number, number)
	local half = math.min(fw / 2, dims.W / 2)
	local limit = math.max(0, dims.W / 2 - half - 0.1)
	local x = math.clamp(mapX(dims, finite(X, 0.5), 0), -limit, limit)
	local centerY = math.clamp((dims.WallPx - finite(Y, 0.2) * dims.RoomHpx) * dims.PX, 0.4, dims.WH - 0.2)
	return x, centerY - 50 * k
end

function WorldLayout.WallInverse(dims: RoomDims, x: number, y: number, k: number): (number, number)
	local X = math.clamp(unmapX(dims, finite(x, 0), 0), 0, 1)
	local centerY = finite(y, 0) + 50 * k
	local Y = (dims.WallPx - centerY / dims.PX) / dims.RoomHpx
	return X, math.clamp(Y, 0, dims.WallRatio)
end

-- Arrondi comme le serveur (HouseService : X / Y à 0,0001)
function WorldLayout.Round4(value: number): number
	return math.floor(value / 0.0001 + 0.5) * 0.0001
end

----------------------------------------------------------------------
-- (v9.6) ZONE VALIDE d'un objet posé : UNE seule définition (fractions de
-- la pièce 2D), utilisée par l'éditeur 2D (HouseCommon.ClampPosition),
-- l'édition 3D de la ville (FurnitureEdit : le fantôme 3D est borné à ce qui
-- retombe DANS la pièce 2D) et le serveur (HouseService : vérification à la
-- sauvegarde et réparation des anciennes dispositions au chargement).
--   - X : l'objet reste (presque) entier dans la largeur de la pièce ;
--   - objet au sol : pieds dans la bande du sol, tête sous le plafond ;
--     `raisedMinY` = Y min d'un petit objet qui peut monter SUR un meuble ;
--   - objet mural : centre sur le mur, sans passer sous le plafond ni sur le sol.
----------------------------------------------------------------------
WorldLayout.AREA_HALF_W = 0.38 -- demi-largeur visible (fraction de la taille de l'objet)
WorldLayout.FLOOR_GAP = 0.035 -- haut de la bande du sol = WallRatio + ça
WorldLayout.FLOOR_MAX_Y = 0.985 -- pieds au plus bas
WorldLayout.WALL_MIN_Y = 0.1 -- centre d'un objet mural au plus haut
WorldLayout.WALL_GAP = 0.03 -- ... et au plus bas : WallRatio - ça

-- (x0, x1, y0, y1) ; `sizePx` = item.Size x S (px de maquette)
function WorldLayout.PlacementArea(placement: string?, sizePx: number, roomWpx: number, roomHpx: number, wallRatio: number?, raisedMinY: number?): (number, number, number, number)
	local ratio = math.clamp(finite(wallRatio, WorldLayout.WALL_RATIO), 0.1, 0.9)
	local size = math.max(0, finite(sizePx, 80))
	local half = math.clamp(size * WorldLayout.AREA_HALF_W / math.max(1, finite(roomWpx, WorldLayout.ROOM_BASE_PX)), 0.015, 0.2)
	local sizeY = size / math.max(1, finite(roomHpx, WorldLayout.ROOM_HEIGHT_PX))
	local minY, maxY
	if placement == "Wall" then
		-- sur le MUR DU FOND (entre les murs de côté en perspective de la 2D,
		-- SIDE_PX de chaque côté) : là où la 3D peut le montrer
		local wpx = math.max(1, finite(roomWpx, WorldLayout.ROOM_BASE_PX))
		local side = math.min(WorldLayout.SIDE_PX, wpx * 0.25)
		local inner = wpx - 2 * side
		local halfPx = math.min(size * WorldLayout.AREA_HALF_W, wpx * 0.5)
		local wx0 = (halfPx * inner / wpx + side) / wpx
		local wx1 = ((wpx - halfPx) * inner / wpx + side) / wpx
		if wx0 > wx1 then
			wx0, wx1 = 0.5, 0.5
		end
		half = wx0
		-- centré sur Y : (presque) entier sur le mur
		local halfY = sizeY * 0.4
		minY = math.max(WorldLayout.WALL_MIN_Y, halfY + 0.02)
		maxY = math.max(WorldLayout.WALL_MIN_Y, math.min(ratio - WorldLayout.WALL_GAP, ratio - halfY * 0.7))
		if minY > maxY then
			-- objet plus haut que le mur : centré sur le mur
			minY = math.min(maxY, ratio / 2 + 0.02)
			maxY = minY
		end
	else
		maxY = WorldLayout.FLOOR_MAX_Y
		minY = ratio + WorldLayout.FLOOR_GAP
		local raised = raisedMinY ~= nil and finite(raisedMinY, minY) or nil
		if raised then
			minY = raised
		end
		-- posé par ses pieds : la tête ne traverse pas le plafond
		minY = math.min(maxY, math.max(minY, sizeY * 0.92 - 0.02))
	end
	-- (zone symétrique : mur du fond comme sol)
	return half, 1 - half, minY, maxY
end

-- Valeur bornée puis arrondie à 0,0001 SANS ressortir des bornes
local function roundInside(value: number, low: number, high: number): number
	local r = WorldLayout.Round4(math.clamp(value, low, high))
	if r < low - 1e-9 then
		r += 0.0001
	elseif r > high + 1e-9 then
		r -= 0.0001
	end
	return r
end

-- Position bornée à la zone ET arrondie comme la sauvegarde
function WorldLayout.ClampToArea(X: number, Y: number, x0: number, x1: number, y0: number, y1: number): (number, number)
	return roundInside(finite(X, 0.5), x0, x1), roundInside(finite(Y, (y0 + y1) / 2), y0, y1)
end

-- Objet au sol visé en 3D (x, z du centre) -> position PERMISE : (x, z) à
-- montrer + (X, Y) à sauvegarder. Le fantôme est TOUJOURS l'image 2D -> 3D
-- de ce qui sera sauvé (même rendu qu'après un rechargement).
function WorldLayout.FloorClamp(dims: RoomDims, x: number, z: number, fw: number, fd: number, x0: number, x1: number, y0: number, y1: number, againstWall: boolean?): (number, number, number, number)
	local X, Y = WorldLayout.FloorInverse(dims, x, z, fd)
	X, Y = WorldLayout.ClampToArea(X, Y, x0, x1, y0, y1)
	local x2, z2 = WorldLayout.FloorForward(dims, X, Y, fw, fd, againstWall)
	return x2, z2, X, Y
end

-- Objet mural visé en 3D (x, y du pivot) -> (x, y) à montrer + (X, Y) à sauvegarder
function WorldLayout.WallClamp(dims: RoomDims, x: number, y: number, fw: number, k: number, x0: number, x1: number, y0: number, y1: number): (number, number, number, number)
	local X, Y = WorldLayout.WallInverse(dims, x, y, k)
	X, Y = WorldLayout.ClampToArea(X, Y, x0, x1, y0, y1)
	local x2, y2 = WorldLayout.WallForward(dims, X, Y, fw, k)
	return x2, y2, X, Y
end

-- Grille d'aimant (studs) : valeur arrondie au pas
function WorldLayout.Snap(value: number, step: number): number
	if step <= 0 then
		return value
	end
	return math.floor(value / step + 0.5) * step
end

----------------------------------------------------------------------
-- Rotation (champ R)
----------------------------------------------------------------------

WorldLayout.ROTATION_STEP = 15

-- Valeur sûre du champ R : entier multiple de 15 dans 15..345, nil pour 0
function WorldLayout.NormalizeRotation(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	local step = WorldLayout.ROTATION_STEP
	local r = (math.floor(value / step + 0.5) * step) % 360
	if r == 0 then
		return nil
	end
	return r
end

-- Tourne de `delta` degrés (ex. +45) : nouvelle valeur du champ R
function WorldLayout.Rotate(value: any, delta: number): number?
	local current = WorldLayout.NormalizeRotation(value) or 0
	return WorldLayout.NormalizeRotation(current + delta)
end

----------------------------------------------------------------------
-- (v10 LAYOUT10) LA GRANDE VILLE : centre-ville, quartiers, autoroute
----------------------------------------------------------------------
-- Repère "ville" (toutes les fonctions PURES ci-dessous) : x, z en studs
-- depuis le centre de la place (Origin), y depuis Origin().Y (sol des
-- pelouses GROUND_Y, chaussée ROAD_Y). +Z = vers l'entrée (sud), -Z =
-- mairie / fête foraine (nord). Les fonctions en CFrame (en jeu) sont plus
-- bas : WorldLayout.CityPoint / CityCFrame / PlotCFrame...
--
-- Plan : un QUADRILLAGE 3 x 3 de cases, séparées par des avenues (axes
-- x, z = ±DOWNTOWN_B et ±BELT_R) :
--   - case du milieu : le CENTRE-VILLE (place, mairie, boutiques, fête
--     foraine, lac et parc) dans le boulevard carré (±DOWNTOWN_B) ;
--   - case sud (0, +1) : l'ENTRÉE (porte, coin gourmand, MégaDopa,
--     concession, point de rendez-vous des courses) sur l'avenue d'entrée
--     (x = 0) qui file jusqu'à l'échangeur sud de l'autoroute ;
--   - cases des QUARTIERS (DISTRICT_DEFS) : chaumières à l'ouest, maisons de
--     ville à l'est, lofts au sud-est, manoirs sur la colline au nord,
--     quartier mixte au sud-ouest ;
--   - cases nord-ouest / nord-est : bois des collines et parc des sports ;
--   - tout autour, au-delà de l'avenue de ceinture (±BELT_R), l'AUTOROUTE
--     (anneau carré aux coins arrondis, ±HIGHWAY_R, 2 x 2 voies) avec 4
--     échangeurs en losange (la route locale passe SUR l'autoroute par un
--     pont) ; celui du sud prolonge l'avenue d'entrée.
-- Chaque quartier : des rues de quartier (STREET_W) qui relient les deux
-- avenues de sa case, avec une rangée de parcelles de chaque côté (façades
-- sur la rue), rangées dos à dos entre deux rues. Le nombre de parcelles de
-- chaque quartier suit le nombre de joueurs (PlotCount) : les colonnes les
-- plus proches du centre d'abord ; les places vides d'une colonne entamée
-- sont des chantiers ("Lots"), le reste de la case est libre ("Free").

WorldLayout.DOWNTOWN_B = 250 -- axe du boulevard carré du centre-ville
WorldLayout.BELT_R = 860 -- axe de l'avenue de ceinture (carré) : AU PLUS (voir BeltR(count))
WorldLayout.BELT_MIN = 640 -- ... au moins (la case de l'entrée : MégaDopa, rendez-vous des courses)
WorldLayout.GRID_AXES = { -860, -250, 250, 860 } -- axes des avenues (x comme z)
WorldLayout.GRID_HALF = 16 -- demi-emprise d'une avenue (chaussée ROAD_W / 2 + trottoir WALK_W)
WorldLayout.STREET_W = 16 -- chaussée d'une rue de quartier (2 voies)
WorldLayout.STREET_HALF = 14 -- demi-emprise d'une rue de quartier (8 + trottoir 6)
WorldLayout.UNIT_D = 196 -- rangée (84) + rue (28) + rangée (84)
WorldLayout.PLOT_GAP = 12 -- entre deux parcelles voisines d'une rangée
WorldLayout.MANSION_GAP = 64 -- entre deux manoirs (murs de pierre, cyprès)
WorldLayout.MANSION_RISE = 5 -- (studs) la colline des manoirs : plateau surélevé
WorldLayout.MANSION_RAMP = 26 -- longueur des rampes d'accès au plateau
WorldLayout.HIGHWAY_R = 1110 -- axe de l'autoroute AU PLUS (voir HighwayR(count) = BeltR + HIGHWAY_GAP)
WorldLayout.HIGHWAY_GAP = 250 -- de l'axe de la ceinture à l'axe de l'autoroute
WorldLayout.HIGHWAY_W = 58 -- emprise des chaussées : 2 x (2 voies de 11 + BAU) + terre-plein central
WorldLayout.HIGHWAY_MEDIAN = 8 -- terre-plein central (largeur)
WorldLayout.HIGHWAY_LANES = { 10.5, 21.5 } -- décalage des voies depuis l'axe (à droite du sens de circulation)
WorldLayout.HIGHWAY_CORNER = 240 -- rayon des virages de l'anneau
WorldLayout.BRIDGE_Y = 18 -- dessus du tablier des ponts au-dessus de l'autoroute (hauteur libre ~16)
WorldLayout.BRIDGE_HALF = 38 -- demi-longueur du tablier (au-dessus de l'emprise + accotements)
WorldLayout.BRIDGE_RAMP = 150 -- longueur des rampes d'approche du pont
WorldLayout.RAMP_JUNCTION = 212 -- distance axe de l'autoroute -> carrefour des bretelles
WorldLayout.RAMP_T = 380 -- distance (le long de l'autoroute) du départ / de l'arrivée des bretelles
WorldLayout.RAMP_W = 12 -- chaussée d'une bretelle (1 voie + accotements)
WorldLayout.OUTSIDE_END = 250 -- bout de la route au-delà du pont (rond-point / aire)
-- Vitesses (studs / s) : rue de quartier, avenue, ceinture, autoroute, bretelle
WorldLayout.SPEED = { Street = 30, Avenue = 40, Belt = 48, Highway = 65, Ramp = 42, Downtown = 32 }
-- (v10) Case de l'entrée : la porte reste PIÉTONNE (place d'accueil) ; les
-- voitures arrivent par la route de l'entrée (x = 0) qui part du rond-point
-- du dépose-minute (derrière la porte, TownEntrance) vers la ceinture et
-- l'échangeur sud, et par la rue du marché (z = MARKET_STREET_Z) qui relie
-- les deux avenues x = ±DOWNTOWN_B au sud de MégaDopa et de la concession.
WorldLayout.ARRIVAL_LOOP = 66 -- centre du rond-point : porte + 66 (sur l'axe)
WorldLayout.ARRIVAL_LOOP_R = 14 -- rayon de la trajectoire des voitures dans le rond-point
WorldLayout.MARKET_STREET_Z = 480

-- Quartiers résidentiels (ordre = ordre des parcelles ; Cell = case du
-- quadrillage ; Axis = sens des rues ; Cap = parcelles au plus ; Weight =
-- part des parcelles quand il y a peu de joueurs ; K = parcelles par rangée)
export type DistrictDef = {
	Id: string,
	Name: string,
	Emoji: string,
	Styles: { string },
	Cell: { number },
	Axis: string,
	Cap: number,
	Weight: number,
	K: number,
	Gap: number,
	Margin: number, -- (studs) du bord de la case côté centre-ville à la 1re parcelle
	Rise: number,
	Gated: boolean,
}
WorldLayout.DISTRICT_DEFS = {
	{ Id = "Cottage", Name = "Cottage Village", Emoji = "🏡", Styles = { "Cottage" }, Cell = { -1, 0 }, Axis = "X", Cap = 12, Weight = 3.0, K = 3, Gap = 12, Margin = 13, Rise = 0, Gated = false },
	{ Id = "Townhouse", Name = "Townhouse Streets", Emoji = "🏘️", Styles = { "Townhouse" }, Cell = { 1, 0 }, Axis = "X", Cap = 12, Weight = 2.6, K = 3, Gap = 12, Margin = 13, Rise = 0, Gated = false },
	{ Id = "Loft", Name = "Loft District", Emoji = "🏭", Styles = { "Loft" }, Cell = { 1, 1 }, Axis = "X", Cap = 12, Weight = 2.2, K = 3, Gap = 12, Margin = 13, Rise = 0, Gated = false },
	{ Id = "Mansion", Name = "Mansion Hills", Emoji = "🏰", Styles = { "Mansion" }, Cell = { 0, -1 }, Axis = "Z", Cap = 8, Weight = 1.7, K = 2, Gap = 64, Margin = 40, Rise = 5, Gated = true },
	{ Id = "Mixed", Name = "Mixed Quarter", Emoji = "🏙️", Styles = {}, Cell = { -1, 1 }, Axis = "X", Cap = 12, Weight = 1.5, K = 3, Gap = 12, Margin = 13, Rise = 0, Gated = false },
} :: { DistrictDef }

-- (bornes d'une case du quadrillage, sans les emprises des avenues)
local function cellRect(i: number, j: number, beltR: number?): (number, number, number, number)
	local B, R, h = WorldLayout.DOWNTOWN_B, beltR or WorldLayout.BELT_R, WorldLayout.GRID_HALF
	local function span(k: number): (number, number)
		if k < 0 then
			return -R + h, -B - h
		elseif k > 0 then
			return B + h, R - h
		end
		return -B + h, B - h
	end
	local x0, x1 = span(i)
	local z0, z1 = span(j)
	return x0, x1, z0, z1
end
WorldLayout.CellRect = cellRect

-- Nombre de parcelles par quartier pour `count` parcelles (plus forte
-- moyenne pondérée d'abord, comme une répartition proportionnelle)
local allocCache: { [number]: { number } } = {}
local function allocation(count: number): { number }
	local cached = allocCache[count]
	if cached then
		return cached
	end
	local defs = WorldLayout.DISTRICT_DEFS
	local alloc = table.create(#defs, 0)
	for _ = 1, count do
		local best, bestScore = nil, math.huge
		for d, def in ipairs(defs) do
			if alloc[d] < def.Cap then
				local score = (alloc[d] + 1) / def.Weight
				if score < bestScore - 1e-9 then
					best, bestScore = d, score
				end
			end
		end
		if not best then
			break
		end
		alloc[best] += 1
	end
	allocCache[count] = alloc
	return alloc
end

-- Forme d'un quartier de `n` parcelles : rangées dos à dos (1 ou 2 rues),
-- colonnes utilisées (les plus proches du centre-ville d'abord)
local function districtShape(def: DistrictDef, n: number): (number, number)
	-- (2 rues dès 5 parcelles : la ville reste compacte, les colonnes
	-- s'ajoutent ensuite)
	local units = n > 4 and 2 or 1
	local kUsed = math.max(1, math.min(def.K, math.ceil(math.max(n, 1) / (units * 2))))
	return units, kUsed
end

-- (v10) La ville GRANDIT avec le nombre de joueurs : l'avenue de ceinture
-- (et l'autoroute, HIGHWAY_GAP plus loin) est juste assez loin pour les
-- colonnes de parcelles utilisées ; BELT_MIN..BELT_R
local beltCache: { [number]: number } = {}
function WorldLayout.BeltR(count: number?): number
	local n = WorldLayout.PlotCount(count)
	local cached = beltCache[n]
	if cached then
		return cached
	end
	local alloc = allocation(n)
	local B, h = WorldLayout.DOWNTOWN_B, WorldLayout.GRID_HALF
	local need = WorldLayout.BELT_MIN
	for d, def in ipairs(WorldLayout.DISTRICT_DEFS) do
		local units, kUsed = districtShape(def, alloc[d])
		local span = def.Margin + kUsed * WorldLayout.PLOT_W + (kUsed - 1) * def.Gap + def.Margin
		need = math.max(need, B + h + span + h)
		local vIdx = def.Axis == "X" and def.Cell[2] or def.Cell[1]
		if vIdx ~= 0 then
			need = math.max(need, B + h + units * WorldLayout.UNIT_D + 40 + h)
		end
	end
	local r = math.min(WorldLayout.BELT_R, math.ceil(need / 10) * 10)
	beltCache[n] = r
	return r
end

function WorldLayout.HighwayR(count: number?): number
	return WorldLayout.BeltR(count) + WorldLayout.HIGHWAY_GAP
end

-- Rectangle (centre x, z, largeur en x, profondeur en z) : repère ville ;
-- Y (facultatif) : hauteur du sol (plateau de la colline des manoirs)
export type Rect = { X: number, Z: number, W: number, D: number, Y: number? }
-- Emplacement d'une parcelle (repère ville) : centre au sol, Look = vers sa rue
export type PlotPlace = { Index: number, X: number, Y: number, Z: number, LookX: number, LookZ: number, Yaw: number, District: string, Slot: number, Street: number }
export type Lot = { X: number, Y: number, Z: number, LookX: number, LookZ: number, Yaw: number, W: number, D: number, District: string }
export type Street = { Id: string, X0: number, Z0: number, X1: number, Z1: number, Y: number, Width: number, Half: number }
export type District = {
	Id: string,
	Name: string,
	Emoji: string,
	Style: string,
	Styles: { string },
	Cell: { number },
	Bounds: Rect, -- toute la case du quartier
	Built: Rect, -- partie occupée (parcelles + rues)
	Rise: number, -- y du plateau (manoirs), 0 ailleurs
	Plateau: Rect?, -- (Rise > 0) le plateau surélevé (dessus à GROUND_Y + Rise)
	Gated: boolean,
	Capacity: number,
	Plots: { number }, -- index globaux des parcelles
	Lots: { Lot }, -- places vides (chantiers permanents)
	Free: { Rect }, -- zones libres pour les repères (ni parcelle, ni rue)
	Streets: { Street },
	Gates: { { X: number, Z: number, Yaw: number } }, -- entrées (quartier fermé)
}

local function yawOf(lx: number, lz: number): number
	-- angle (radians) tel que CFrame.Angles(0, yaw, 0).LookVector = (lx, 0, lz)
	return math.atan2(-lx, -lz)
end
WorldLayout.YawOf = yawOf

local cityCache: { [number]: any } = {}

-- Construit (une fois par nombre de parcelles) les quartiers et parcelles
local function buildCity(count: number): any
	local cached = cityCache[count]
	if cached then
		return cached
	end
	local alloc = allocation(count)
	local beltR = WorldLayout.BeltR(count)
	local districts: { District } = {}
	local plots: { PlotPlace } = {}
	local W, D = WorldLayout.PLOT_W, WorldLayout.PLOT_D
	local SH = WorldLayout.STREET_HALF
	for d, def in ipairs(WorldLayout.DISTRICT_DEFS) do
		local n = alloc[d]
		local x0, x1, z0, z1 = cellRect(def.Cell[1], def.Cell[2], beltR)
		-- u = le long des rues, v = en travers
		local alongX = def.Axis == "X"
		local u0, u1, v0, v1
		if alongX then
			u0, u1, v0, v1 = x0, x1, z0, z1
		else
			u0, u1, v0, v1 = z0, z1, x0, x1
		end
		-- côté du centre-ville : là où |u| est le plus petit
		local nearU, dirU
		if math.abs(u0) < math.abs(u1) then
			nearU, dirU = u0, 1
		else
			nearU, dirU = u1, -1
		end
		local gap = def.Gap
		local pitch = W + gap
		local margin = def.Margin
		local units, kUsed = districtShape(def, n)
		local vc = (v0 + v1) / 2
		local streetsV: { number } = {}
		if units == 1 then
			streetsV = { vc }
		else
			streetsV = { vc - WorldLayout.UNIT_D / 2, vc + WorldLayout.UNIT_D / 2 }
		end
		-- rangées : (v du centre de la parcelle, sens du regard en v, rue)
		local rowList: { { V: number, Look: number, Street: number } } = {}
		for s, sv in ipairs(streetsV) do
			table.insert(rowList, { V = sv - SH - D / 2, Look = 1, Street = s })
			table.insert(rowList, { V = sv + SH + D / 2, Look = -1, Street = s })
		end
		-- les rangées du milieu d'abord (plus près des autres rangées)
		table.sort(rowList, function(a, b)
			local da, db = math.abs(a.V - vc), math.abs(b.V - vc)
			if math.abs(da - db) > 1e-6 then
				return da < db
			end
			return a.V < b.V
		end)
		local rise = def.Rise
		local entry: District = {
			Id = def.Id,
			Name = def.Name,
			Emoji = def.Emoji,
			Style = def.Id,
			Styles = def.Styles,
			Cell = def.Cell,
			Bounds = { X = (x0 + x1) / 2, Z = (z0 + z1) / 2, W = x1 - x0, D = z1 - z0 },
			Built = { X = 0, Z = 0, W = 0, D = 0 },
			Rise = rise,
			Gated = def.Gated,
			Capacity = def.Cap,
			Plots = {},
			Lots = {},
			Free = {},
			Streets = {},
			Gates = {},
		}
		local function toXZ(u: number, v: number): (number, number)
			if alongX then
				return u, v
			end
			return v, u
		end
		local function rect(ua: number, ub: number, va: number, vb: number): Rect
			local xa, za = toXZ(math.min(ua, ub), math.min(va, vb))
			local xb, zb = toXZ(math.max(ua, ub), math.max(va, vb))
			return { X = (xa + xb) / 2, Z = (za + zb) / 2, W = math.abs(xb - xa), D = math.abs(zb - za) }
		end
		local placed = 0
		for c = 1, kUsed do
			local u = nearU + dirU * (margin + W / 2 + (c - 1) * pitch)
			for _, row in ipairs(rowList) do
				local x, z = toXZ(u, row.V)
				local lx, lz = toXZ(0, row.Look)
				if placed < n then
					placed += 1
					local index = #plots + 1
					local place: PlotPlace = {
						Index = index,
						X = x,
						Y = rise,
						Z = z,
						LookX = lx,
						LookZ = lz,
						Yaw = yawOf(lx, lz),
						District = def.Id,
						Slot = placed,
						Street = row.Street,
					}
					plots[index] = place
					table.insert(entry.Plots, index)
				else
					table.insert(entry.Lots, { X = x, Y = rise, Z = z, LookX = lx, LookZ = lz, Yaw = yawOf(lx, lz), W = W, D = D, District = def.Id })
				end
			end
		end
		-- rues : d'une avenue à l'autre (toute la case + les demi-emprises)
		local h = WorldLayout.GRID_HALF
		for s, sv in ipairs(streetsV) do
			local ax, az = toXZ(u0 - h, sv)
			local bx, bz = toXZ(u1 + h, sv)
			table.insert(entry.Streets, { Id = def.Id .. "_" .. s, X0 = ax, Z0 = az, X1 = bx, Z1 = bz, Y = rise, Width = WorldLayout.STREET_W, Half = SH })
			if def.Gated then
				-- portails aux deux bouts (au bord de la case, regard vers l'extérieur)
				local gx0, gz0 = toXZ(u0 + 3, sv)
				local gx1, gz1 = toXZ(u1 - 3, sv)
				local lx0, lz0 = toXZ(-1, 0)
				local lx1, lz1 = toXZ(1, 0)
				table.insert(entry.Gates, { X = gx0, Z = gz0, Yaw = yawOf(lx0, lz0) })
				table.insert(entry.Gates, { X = gx1, Z = gz1, Yaw = yawOf(lx1, lz1) })
			end
		end
		-- partie bâtie, zones libres
		local vMin = streetsV[1] - SH - D
		local vMax = streetsV[#streetsV] + SH + D
		local uEnd = nearU + dirU * (margin + kUsed * pitch - gap / 2)
		local uNear = nearU + dirU * math.max(0, margin - gap / 2)
		entry.Built = rect(uNear, uEnd, vMin, vMax)
		local farU = dirU > 0 and u1 or u0
		if math.abs(farU - uEnd) > 30 then
			table.insert(entry.Free, rect(uEnd + dirU * 2, farU - dirU * 2, vMin, vMax))
		end
		if math.abs(uNear - nearU) > 20 then
			-- (bande côté centre-ville : trottoir planté, entrée du quartier)
			table.insert(entry.Free, rect(nearU + dirU * 2, uNear - dirU * 1, vMin, vMax))
		end
		if vMin - v0 > 20 then
			table.insert(entry.Free, rect(u0 + 2, u1 - 2, v0 + 2, vMin - 2))
		end
		if v1 - vMax > 20 then
			table.insert(entry.Free, rect(u0 + 2, u1 - 2, vMax + 2, v1 - 2))
		end
		-- (bandes entre la rue et les rangées libres : déjà dans Free au-delà
		-- de uEnd ; les rues traversent Free -> rectangles coupés par les rues)
		local cutFree: { Rect } = {}
		for _, r in ipairs(entry.Free) do
			local pieces = { r }
			for _, st in ipairs(entry.Streets) do
				local nextPieces = {}
				for _, piece in ipairs(pieces) do
					-- rue le long de x (z constant) ou de z (x constant)
					local horizontal = math.abs(st.Z1 - st.Z0) < 1e-6
					if horizontal then
						local za, zb = piece.Z - piece.D / 2, piece.Z + piece.D / 2
						local s0, s1 = st.Z0 - st.Half - 1, st.Z0 + st.Half + 1
						if s1 <= za or s0 >= zb then
							table.insert(nextPieces, piece)
						else
							if s0 - za > 8 then
								table.insert(nextPieces, { X = piece.X, W = piece.W, Z = (za + s0) / 2, D = s0 - za })
							end
							if zb - s1 > 8 then
								table.insert(nextPieces, { X = piece.X, W = piece.W, Z = (s1 + zb) / 2, D = zb - s1 })
							end
						end
					else
						local xa, xb = piece.X - piece.W / 2, piece.X + piece.W / 2
						local s0, s1 = st.X0 - st.Half - 1, st.X0 + st.Half + 1
						if s1 <= xa or s0 >= xb then
							table.insert(nextPieces, piece)
						else
							if s0 - xa > 8 then
								table.insert(nextPieces, { Z = piece.Z, D = piece.D, X = (xa + s0) / 2, W = s0 - xa })
							end
							if xb - s1 > 8 then
								table.insert(nextPieces, { Z = piece.Z, D = piece.D, X = (s1 + xb) / 2, W = xb - s1 })
							end
						end
					end
				end
				pieces = nextPieces
			end
			for _, piece in ipairs(pieces) do
				table.insert(cutFree, piece)
			end
		end
		-- (colline des manoirs) plateau : du haut des rampes d'une avenue à
		-- l'autre, autour des rangées ; les zones libres sont coupées à son bord
		if rise > 0 then
			local top = WorldLayout.GRID_HALF + 2 + WorldLayout.MANSION_RAMP - WorldLayout.GRID_HALF
			local pv0, pv1 = math.max(v0, vMin - 8), math.min(v1, vMax + 8)
			local plateau = rect(u0 + top, u1 - top, pv0, pv1)
			plateau.Y = rise
			entry.Plateau = plateau
			local px0, px1 = plateau.X - plateau.W / 2, plateau.X + plateau.W / 2
			local pz0, pz1 = plateau.Z - plateau.D / 2, plateau.Z + plateau.D / 2
			local split: { Rect } = {}
			for _, r in ipairs(cutFree) do
				-- morceaux : dedans (Y = rise) / dehors (Y = 0), découpés en x puis en z
				local xs = { r.X - r.W / 2, r.X + r.W / 2 }
				for _, c in ipairs({ px0, px1 }) do
					if c > xs[1] + 8 and c < xs[#xs] - 8 then
						table.insert(xs, (#xs), c)
					end
				end
				table.sort(xs)
				local zs = { r.Z - r.D / 2, r.Z + r.D / 2 }
				for _, c in ipairs({ pz0, pz1 }) do
					if c > zs[1] + 8 and c < zs[#zs] - 8 then
						table.insert(zs, (#zs), c)
					end
				end
				table.sort(zs)
				for a = 1, #xs - 1 do
					for b = 1, #zs - 1 do
						local cx, cz = (xs[a] + xs[a + 1]) / 2, (zs[b] + zs[b + 1]) / 2
						local inside = cx > px0 and cx < px1 and cz > pz0 and cz < pz1
						table.insert(split, { X = cx, Z = cz, W = xs[a + 1] - xs[a], D = zs[b + 1] - zs[b], Y = inside and rise or 0 })
					end
				end
			end
			cutFree = split
		end
		entry.Free = cutFree
		table.insert(districts, entry)
	end
	local city = { Count = count, Districts = districts, Plots = plots }
	cityCache[count] = city
	return city
end

-- Nombre de parcelles : Players.MaxPlayers borné à MIN_PLOTS..MAX_PLOTS
-- (le serveur le lit une fois ; 8 par défaut)
function WorldLayout.PlotCount(maxPlayers: any): number
	return math.clamp(math.floor(finite(maxPlayers, 8)), WorldLayout.MIN_PLOTS, WorldLayout.MAX_PLOTS)
end

-- Quartiers (liste en lecture seule, en cache : ne pas modifier)
function WorldLayout.Districts(count: number): { District }
	return buildCity(WorldLayout.PlotCount(count)).Districts
end

-- Quartier par identifiant ("Cottage", "Townhouse", "Loft", "Mansion", "Mixed")
function WorldLayout.District(count: number, id: string): District?
	for _, d in ipairs(WorldLayout.Districts(count)) do
		if d.Id == id then
			return d
		end
	end
	return nil
end

-- Emplacement PUR d'une parcelle (repère ville), nil hors 1..count
function WorldLayout.PlotPlaceData(index: number, count: number): PlotPlace?
	return buildCity(WorldLayout.PlotCount(count)).Plots[index]
end

-- Quartier d'une parcelle
function WorldLayout.PlotDistrict(index: number, count: number): District?
	local place = WorldLayout.PlotPlaceData(index, count)
	if not place then
		return nil
	end
	return WorldLayout.District(count, place.District)
end

-- Taille d'une parcelle (la même partout ; les manoirs ont plus d'espace
-- ENTRE les parcelles, pas de plus grandes parcelles)
function WorldLayout.PlotSize(_index: number?, _count: number?): (number, number)
	return WorldLayout.PLOT_W, WorldLayout.PLOT_D
end

-- Places vides des quartiers (chantiers permanents) : { Lot } en repère ville
function WorldLayout.FillerLots(count: number): { Lot }
	local out = {}
	for _, d in ipairs(WorldLayout.Districts(count)) do
		for _, lot in ipairs(d.Lots) do
			table.insert(out, lot)
		end
	end
	return out
end

-- Quartier d'un style de maison (StyleOf) ; "Mixed" si aucun n'a ce style
function WorldLayout.DistrictForStyle(style: string?): string
	for _, def in ipairs(WorldLayout.DISTRICT_DEFS) do
		if table.find(def.Styles, style) then
			return def.Id
		end
	end
	return "Mixed"
end

-- Distance entre deux quartiers (centres de case) : repli vers le plus proche
local function districtCenter(id: string): (number, number)
	for _, def in ipairs(WorldLayout.DISTRICT_DEFS) do
		if def.Id == id then
			local x0, x1, z0, z1 = cellRect(def.Cell[1], def.Cell[2], WorldLayout.BELT_R)
			return (x0 + x1) / 2, (z0 + z1) / 2
		end
	end
	return 0, 0
end

-- Parcelle à donner à un joueur qui arrive : une parcelle LIBRE du quartier
-- de son style, sinon du quartier le plus proche qui en a une (puis la plus
-- proche du centre-ville dans ce quartier). `isFree(index)` dit si une
-- parcelle est libre. -> index ou nil (ville pleine)
function WorldLayout.PickPlot(count: number, style: string?, isFree: (number) -> boolean): number?
	local want = WorldLayout.DistrictForStyle(style)
	local wx, wz = districtCenter(want)
	local order: { District } = {}
	for _, d in ipairs(WorldLayout.Districts(count)) do
		table.insert(order, d)
	end
	table.sort(order, function(a, b)
		if a.Id == want then
			return b.Id ~= want
		elseif b.Id == want then
			return false
		end
		local ax, az = districtCenter(a.Id)
		local bx, bz = districtCenter(b.Id)
		local da = (ax - wx) ^ 2 + (az - wz) ^ 2
		local db = (bx - wx) ^ 2 + (bz - wz) ^ 2
		if math.abs(da - db) > 1e-6 then
			return da < db
		end
		return a.Id < b.Id
	end)
	for _, d in ipairs(order) do
		for _, index in ipairs(d.Plots) do
			if isFree(index) then
				return index
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- (v10) Compat : anciennes fonctions de l'anneau (le centre-ville est un
-- carré : 4 "emplacements" = ses 4 côtés, 0 = entrée +Z, 1 = +X...)
----------------------------------------------------------------------

function WorldLayout.PlotSlots(_count: number?): number
	return 4
end

function WorldLayout.SlotAngle(slot: number, _count: number?): number
	return slot / 4 * math.pi * 2
end

-- Distance du centre au bord extérieur du boulevard du centre-ville
function WorldLayout.PlotFrontRadius(_count: number?): number
	return WorldLayout.DOWNTOWN_B + WorldLayout.ROAD_W / 2 + WorldLayout.WALK_W
end

function WorldLayout.PlotRadius(count: number?): number
	return WorldLayout.PlotFrontRadius(count) + WorldLayout.PLOT_D / 2
end

-- Axe du boulevard (carré) du centre-ville
function WorldLayout.RingRoadRadius(_count: number?): number
	return WorldLayout.DOWNTOWN_B
end

-- Bord intérieur du boulevard (trottoir intérieur compris)
function WorldLayout.RingInnerRadius(count: number?): number
	return WorldLayout.RingRoadRadius(count) - WorldLayout.ROAD_W / 2 - WorldLayout.WALK_W
end

-- Distance du centre à la porte de la ville (sur l'axe +Z)
function WorldLayout.GateDistance(count: number?): number
	return WorldLayout.PlotFrontRadius(count) + WorldLayout.GATE_BACK
end

-- Rayon des murs invisibles (bord du pré) : au-delà des bouts des échangeurs
function WorldLayout.TownRadius(count: number?): number
	return WorldLayout.HighwayR(count) + WorldLayout.OUTSIDE_END + 120
end

-- Parcelle `index` : centre (x, z) en repère ville et angle (radians) de sa
-- direction "vers l'extérieur" (le regard vers la rue = -(sin a, cos a))
function WorldLayout.PlotPlace(index: number, count: number): (number, number, number)
	local place = WorldLayout.PlotPlaceData(index, count)
	if not place then
		return 0, 0, 0
	end
	return place.X, place.Z, math.atan2(-place.LookX, -place.LookZ)
end

-- Distance (le long de la direction "vers la rue") entre le centre de la
-- parcelle et la façade de la maison
function WorldLayout.HouseFrontOffset(): number
	return WorldLayout.PLOT_D / 2 - WorldLayout.GARDEN_D
end

----------------------------------------------------------------------
-- (v10) Réseau routier : graphe PUR (en cache par nombre de parcelles)
----------------------------------------------------------------------
-- Nœud : { Id, X, Y, Z, Kind } (Y = dessus de la chaussée, repère ville)
-- Arête : { Id, A, B, Kind, Lanes, Width, Speed, OneWay, Highway, Ramp,
--   Bridge, Sidewalk, Points } ; Points = polyligne A -> B (axe de la
--   chaussée, {X, Y, Z}) ; Lanes = voies PAR SENS (OneWay : voies dans le
--   sens A -> B) ; voie k à droite du sens de circulation, décalage
--   LaneOffsets[k] depuis l'axe ; Sidewalk = largeur des trottoirs (0 = aucun).
-- Kind : "Downtown" | "Avenue" | "Belt" | "Street" | "Entrance" |
--   "Connector" | "Highway" | "Ramp" | "Outside" | "Roundabout".
export type RoadNode = { Id: string, X: number, Y: number, Z: number, Kind: string }
export type RoadPoint = { X: number, Y: number, Z: number }
export type RoadEdge = {
	Id: string,
	A: string,
	B: string,
	Kind: string,
	Lanes: number,
	LaneOffsets: { number },
	Width: number,
	Speed: number,
	OneWay: boolean,
	Highway: boolean,
	Ramp: boolean,
	Bridge: boolean,
	Sidewalk: number,
	Length: number,
	Points: { RoadPoint },
}
export type Crossing = { X: number, Y: number, Z: number, Yaw: number, Length: number, Width: number }
export type RoadGraph = {
	Nodes: { [string]: RoadNode },
	NodeList: { RoadNode },
	Edges: { RoadEdge },
	Adjacent: { [string]: { RoadEdge } },
	Crossings: { Crossing },
}

local graphCache: { [number]: RoadGraph } = {}

local function r2(v: number): number
	return math.floor(v * 2 + 0.5) / 2
end

local function polyLength(points: { RoadPoint }): number
	local len = 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		len += math.sqrt((b.X - a.X) ^ 2 + (b.Y - a.Y) ^ 2 + (b.Z - a.Z) ^ 2)
	end
	return len
end

-- Repère d'un échangeur : centre sur l'axe de l'autoroute, n = vers
-- l'extérieur, t = sens de la chaussée extérieure (circulation à droite)
local INTERCHANGES = {
	{ Id = "S", NX = 0, NZ = 1 },
	{ Id = "E", NX = 1, NZ = 0 },
	{ Id = "N", NX = 0, NZ = -1 },
	{ Id = "W", NX = -1, NZ = 0 },
}
WorldLayout.INTERCHANGES = INTERCHANGES

local function ixFrame(ix: any, H: number): (number, number, number, number, number, number)
	local nx, nz = ix.NX, ix.NZ
	local tx, tz = nz, -nx
	return nx * H, nz * H, nx, nz, tx, tz
end

-- Point de l'échangeur (t, n) -> repère ville
local function ixPoint(ix: any, H: number, t: number, n: number, y: number?): RoadPoint
	local cx, cz, nx, nz, tx, tz = ixFrame(ix, H)
	return { X = cx + tx * t + nx * n, Y = y or WorldLayout.ROAD_Y, Z = cz + tz * t + nz * n }
end

-- Axe de l'autoroute : anneau carré aux coins arrondis, dans le sens de la
-- chaussée EXTÉRIEURE (S : +X, E : -Z, N : -X, O : +Z), points tous les ~40
-- studs dans les virages. `closed` : le dernier point rejoint le premier.
local highwayCache: { [number]: { RoadPoint } } = {}
function WorldLayout.HighwayPath(count: number?): { RoadPoint }
	local key = WorldLayout.PlotCount(count)
	local cachedPath = highwayCache[key]
	if cachedPath then
		return cachedPath
	end
	local H, Rc = WorldLayout.HighwayR(key), WorldLayout.HIGHWAY_CORNER
	local y = WorldLayout.ROAD_Y
	local pts: { RoadPoint } = {}
	-- 4 coins (centre du virage), en partant du côté sud vers l'est
	local corners = {
		{ cx = H - Rc, cz = H - Rc, a0 = 0 }, -- sud-est : de (H-Rc, H) vers (H, H-Rc)
		{ cx = H - Rc, cz = -(H - Rc), a0 = 1 },
		{ cx = -(H - Rc), cz = -(H - Rc), a0 = 2 },
		{ cx = -(H - Rc), cz = H - Rc, a0 = 3 },
	}
	-- angle polaire (x = sin, z = cos) : sud = 0, est = pi/2, nord = pi, ouest = 3pi/2
	for k, c in ipairs(corners) do
		local start = (k - 1) * math.pi / 2
		local steps = 8
		for s = 0, steps do
			local a = start + s / steps * (math.pi / 2)
			table.insert(pts, { X = c.cx + math.sin(a) * Rc, Y = y, Z = c.cz + math.cos(a) * Rc })
		end
	end
	highwayCache[key] = pts
	return pts
end

-- Décalage des voies de l'autoroute depuis l'axe (à droite du sens)
function WorldLayout.HighwayLanes(): { number }
	return WorldLayout.HIGHWAY_LANES
end

-- Profil en long d'une route qui passe sur un pont au-dessus de
-- l'autoroute : y de la chaussée à la distance n (depuis l'axe de
-- l'autoroute, le long de la route)
function WorldLayout.BridgeProfile(n: number): number
	local a = math.abs(n)
	local half, ramp, top = WorldLayout.BRIDGE_HALF, WorldLayout.BRIDGE_RAMP, WorldLayout.BRIDGE_Y
	local base = WorldLayout.ROAD_Y
	if a <= half then
		return base + top
	elseif a >= half + ramp then
		return base
	end
	-- (raccord doux : cosinus)
	local f = (a - half) / ramp
	return base + top * (0.5 + 0.5 * math.cos(f * math.pi))
end

-- Stations (n, le long de la route depuis l'axe de l'autoroute) du profil
-- d'un pont : bouts au sol (±RAMP_JUNCTION), rampes en BRIDGE_RAMP_STEPS
-- tronçons, tablier plat. Le serveur (tablier) et le graphe (Points) se
-- servent des MÊMES stations : les voitures roulent sur le tablier.
WorldLayout.BRIDGE_RAMP_STEPS = 6
function WorldLayout.BridgeStations(): { number }
	local J, half, ramp = WorldLayout.RAMP_JUNCTION, WorldLayout.BRIDGE_HALF, WorldLayout.BRIDGE_RAMP
	local k = WorldLayout.BRIDGE_RAMP_STEPS
	local out = { -J }
	for i = 0, k do
		table.insert(out, -(half + ramp) + ramp * i / k)
	end
	for i = 0, k do
		table.insert(out, half + ramp * i / k)
	end
	table.insert(out, J)
	return out
end

local function buildGraph(count: number): RoadGraph
	local cachedGraph = graphCache[count]
	if cachedGraph then
		return cachedGraph
	end
	local city = buildCity(count)
	local nodes: { [string]: RoadNode } = {}
	local nodeList: { RoadNode } = {}
	local edges: { RoadEdge } = {}
	local crossings: { Crossing } = {}
	local y0 = WorldLayout.ROAD_Y
	local function node(x: number, z: number, y: number?, kind: string?): string
		local id = "n" .. r2(x) .. "_" .. r2(z)
		local existing = nodes[id]
		if not existing then
			local n: RoadNode = { Id = id, X = r2(x), Y = y or y0, Z = r2(z), Kind = kind or "Point" }
			nodes[id] = n
			table.insert(nodeList, n)
		elseif kind == "Junction" then
			existing.Kind = "Junction"
		end
		return id
	end
	local function addEdge(a: string, b: string, kind: string, opts: any): RoadEdge
		local na, nb = nodes[a], nodes[b]
		local points = opts.Points or { { X = na.X, Y = na.Y, Z = na.Z }, { X = nb.X, Y = nb.Y, Z = nb.Z } }
		local lanes = opts.Lanes or 1
		local offsets = opts.LaneOffsets
		if not offsets then
			offsets = {}
			local laneW = opts.LaneW or (opts.Width or 20) / (opts.OneWay and lanes or 2 * lanes)
			for k = 1, lanes do
				if opts.OneWay then
					table.insert(offsets, (k - 0.5 - lanes / 2) * laneW)
				else
					table.insert(offsets, (k - 0.5) * laneW)
				end
			end
		end
		local e: RoadEdge = {
			Id = "e" .. (#edges + 1),
			A = a,
			B = b,
			Kind = kind,
			Lanes = lanes,
			LaneOffsets = offsets,
			Width = opts.Width or 20,
			Speed = opts.Speed or WorldLayout.SPEED.Avenue,
			OneWay = opts.OneWay == true,
			Highway = opts.Highway == true,
			Ramp = opts.Ramp == true,
			Bridge = opts.Bridge == true,
			Sidewalk = opts.Sidewalk or 0,
			Length = polyLength(points),
			Points = points,
		}
		table.insert(edges, e)
		return e
	end
	-- Routes droites découpées à chaque carrefour : { A = {x, z}, B = {x, z}, cuts = {t...}, opts }
	local lines = {}
	local function line(ax: number, az: number, bx: number, bz: number, kind: string, opts: any)
		local l = { AX = ax, AZ = az, BX = bx, BZ = bz, Kind = kind, Opts = opts, Cuts = { 0, 1 }, Y = opts.Y or y0 }
		table.insert(lines, l)
		return l
	end
	local B, R = WorldLayout.DOWNTOWN_B, WorldLayout.BeltR(count)
	local H = WorldLayout.HighwayR(count)
	local avenueOpts = { Width = WorldLayout.ROAD_W, Lanes = 1, Speed = WorldLayout.SPEED.Avenue, Sidewalk = WorldLayout.WALK_W }
	local beltOpts = { Width = WorldLayout.ROAD_W, Lanes = 1, Speed = WorldLayout.SPEED.Belt, Sidewalk = WorldLayout.WALK_W }
	local downtownOpts = { Width = WorldLayout.ROAD_W, Lanes = 1, Speed = WorldLayout.SPEED.Downtown, Sidewalk = WorldLayout.WALK_W }
	-- quadrillage : x = ±B (de -R à R), z = ±B, ceinture x = ±R, z = ±R
	for _, a in ipairs({ -B, B }) do
		line(a, -R, a, R, "Avenue", avenueOpts)
		line(-R, a, R, a, "Avenue", avenueOpts)
	end
	for _, a in ipairs({ -R, R }) do
		line(a, -R, a, R, "Belt", beltOpts)
		line(-R, a, R, a, "Belt", beltOpts)
	end
	-- centre-ville : avenue d'entrée (x = 0) de la place au boulevard, puis
	-- l'entrée jusqu'à la ceinture ; rues latérales ±X de la place au boulevard
	local street0 = WorldLayout.PLAZA_R + 30
	line(0, street0, 0, B, "Downtown", { Width = WorldLayout.AVENUE_W, Lanes = 1, Speed = WorldLayout.SPEED.Downtown, Sidewalk = WorldLayout.WALK_W })
	-- route de l'entrée : du rond-point du dépose-minute à la ceinture
	local loopZ = WorldLayout.GateDistance(count) + WorldLayout.ARRIVAL_LOOP
	local loopR = WorldLayout.ARRIVAL_LOOP_R
	line(0, loopZ + loopR, 0, R, "Entrance", avenueOpts)
	-- rue du marché (au sud de MégaDopa et de la concession)
	line(-B, WorldLayout.MARKET_STREET_Z, B, WorldLayout.MARKET_STREET_Z, "Avenue", avenueOpts)
	line(street0, 0, B, 0, "Downtown", downtownOpts)
	line(-street0, 0, -B, 0, "Downtown", downtownOpts)
	-- rues des quartiers
	for _, d in ipairs(city.Districts) do
		for _, st in ipairs(d.Streets) do
			line(st.X0, st.Z0, st.X1, st.Z1, "Street", { Width = st.Width, Lanes = 1, Speed = WorldLayout.SPEED.Street, Sidewalk = WorldLayout.WALK_W, Y = st.Y, Rise = d.Rise })
		end
	end
	-- carrefours : intersections des lignes (axes parallèles à x ou z)
	local function param(l: any, x: number, z: number): number?
		local dx, dz = l.BX - l.AX, l.BZ - l.AZ
		local len2 = dx * dx + dz * dz
		local t = ((x - l.AX) * dx + (z - l.AZ) * dz) / len2
		local px, pz = l.AX + dx * t, l.AZ + dz * t
		if (px - x) ^ 2 + (pz - z) ^ 2 > 0.01 or t < -1e-6 or t > 1 + 1e-6 then
			return nil
		end
		return math.clamp(t, 0, 1)
	end
	local junctions: { { X: number, Z: number } } = {}
	for i = 1, #lines do
		for j = i + 1, #lines do
			local a, b = lines[i], lines[j]
			local aHoriz = math.abs(a.AZ - a.BZ) < 1e-6
			local bHoriz = math.abs(b.AZ - b.BZ) < 1e-6
			if aHoriz ~= bHoriz then
				local x = aHoriz and b.AX or a.AX
				local z = aHoriz and a.AZ or b.AZ
				local ta, tb = param(a, x, z), param(b, x, z)
				if ta and tb then
					table.insert(a.Cuts, ta)
					table.insert(b.Cuts, tb)
					table.insert(junctions, { X = x, Z = z })
				end
			end
		end
	end
	-- raccords des connecteurs d'échangeur à la ceinture (milieux des côtés)
	for _, ix in ipairs(INTERCHANGES) do
		local x, z = ix.NX * R, ix.NZ * R
		for _, l in ipairs(lines) do
			if l.Kind == "Belt" then
				local t = param(l, x, z)
				if t then
					table.insert(l.Cuts, t)
				end
			end
		end
	end
	for _, l in ipairs(lines) do
		table.sort(l.Cuts)
		local rise = l.Opts.Rise or 0
		local prev: string? = nil
		local prevT = -1
		for _, t in ipairs(l.Cuts) do
			if t - prevT > 1e-6 then
				local x, z = l.AX + (l.BX - l.AX) * t, l.AZ + (l.BZ - l.AZ) * t
				local id = node(x, z, y0, (t > 1e-6 and t < 1 - 1e-6) and "Junction" or "Junction")
				if prev then
					local na, nb = nodes[prev], nodes[id]
					local pts = { { X = na.X, Y = na.Y, Z = na.Z }, { X = nb.X, Y = nb.Y, Z = nb.Z } }
					if rise > 0 then
						-- (colline des manoirs : rampes aux deux bouts du plateau)
						local len = math.sqrt((nb.X - na.X) ^ 2 + (nb.Z - na.Z) ^ 2)
						local ramp = WorldLayout.MANSION_RAMP
						local startU = WorldLayout.GRID_HALF + 2
						pts = {}
						local stations = { 0, startU, startU + ramp, len - startU - ramp, len - startU, len }
						for _, s in ipairs(stations) do
							local f = s / len
							local yy = y0
							if s > startU + ramp - 1e-6 and s < len - startU - ramp + 1e-6 then
								yy = y0 + rise
							end
							table.insert(pts, { X = na.X + (nb.X - na.X) * f, Y = yy, Z = na.Z + (nb.Z - na.Z) * f })
						end
					end
					addEdge(prev, id, l.Kind, {
						Width = l.Opts.Width,
						Lanes = l.Opts.Lanes,
						Speed = l.Opts.Speed,
						Sidewalk = l.Opts.Sidewalk,
						Points = pts,
					})
				end
				prev = id
				prevT = t
			end
		end
	end
	-- rond-point du dépose-minute (derrière la porte) : 4 nœuds, sens unique
	do
		local cz = WorldLayout.GateDistance(count) + WorldLayout.ARRIVAL_LOOP
		local rr = WorldLayout.ARRIVAL_LOOP_R
		local ids = {}
		for q = 0, 3 do
			local a = q * math.pi / 2
			ids[q + 1] = node(math.sin(a) * rr, cz + math.cos(a) * rr, y0, "Roundabout")
		end
		for q = 1, 4 do
			local a0 = (q - 1) * math.pi / 2
			local pts = {}
			for s2 = 0, 4 do
				local a = a0 + s2 / 4 * math.pi / 2
				table.insert(pts, { X = math.sin(a) * rr, Y = y0, Z = cz + math.cos(a) * rr })
			end
			addEdge(ids[q], ids[q % 4 + 1], "Roundabout", { Width = 10, Lanes = 1, OneWay = true, Speed = 16, Sidewalk = 0, LaneOffsets = { 0 }, Points = pts })
		end
	end
	-- passages piétons : sur chaque bras de chaque carrefour avec trottoirs
	local seen: { [string]: boolean } = {}
	for _, jn in ipairs(junctions) do
		local key = r2(jn.X) .. "_" .. r2(jn.Z)
		if not seen[key] then
			seen[key] = true
			local id = "n" .. key
			for _, e in ipairs(edges) do
				if (e.A == id or e.B == id) and e.Sidewalk > 0 then
					local from = e.A == id and e.Points[1] or e.Points[#e.Points]
					local to = e.A == id and e.Points[2] or e.Points[#e.Points - 1]
					local dx, dz = to.X - from.X, to.Z - from.Z
					local len = math.sqrt(dx * dx + dz * dz)
					if len > 60 then
						local ux, uz = dx / len, dz / len
						local back = WorldLayout.GRID_HALF + 5
						table.insert(crossings, {
							X = from.X + ux * back,
							Y = from.Y,
							Z = from.Z + uz * back,
							-- (la bande traverse la chaussée : regard le long de la route)
							Yaw = yawOf(ux, uz),
							Length = e.Width,
							Width = 5,
						})
					end
				end
			end
		end
	end
	-- AUTOROUTE : anneau (arêtes à double sens, 2 voies par sens), coupé aux
	-- départs / arrivées des bretelles
	local hw = WorldLayout.HighwayPath(count)
	local T = WorldLayout.RAMP_T
	local hwOpts = {
		Width = WorldLayout.HIGHWAY_W,
		Lanes = 2,
		LaneOffsets = WorldLayout.HIGHWAY_LANES,
		Speed = WorldLayout.SPEED.Highway,
		Highway = true,
		Sidewalk = 0,
	}
	-- points de coupe (sur les côtés droits) : (t = ±RAMP_T, n = 0) de chaque échangeur
	local cutPoints: { RoadPoint } = {}
	for _, ix in ipairs(INTERCHANGES) do
		for _, t in ipairs({ -T, T }) do
			table.insert(cutPoints, ixPoint(ix, H, t, 0))
		end
	end
	-- polyligne fermée + points de coupe insérés à leur place
	local ring: { RoadPoint } = {}
	for i = 1, #hw do
		table.insert(ring, hw[i])
		local a, b = hw[i], hw[i % #hw + 1]
		local inserts = {}
		for _, c in ipairs(cutPoints) do
			local dx, dz = b.X - a.X, b.Z - a.Z
			local len2 = dx * dx + dz * dz
			if len2 > 1 then
				local t = ((c.X - a.X) * dx + (c.Z - a.Z) * dz) / len2
				local px, pz = a.X + dx * t, a.Z + dz * t
				if t > 1e-6 and t < 1 - 1e-6 and (px - c.X) ^ 2 + (pz - c.Z) ^ 2 < 0.25 then
					table.insert(inserts, { T = t, P = c })
				end
			end
		end
		table.sort(inserts, function(p, q)
			return p.T < q.T
		end)
		for _, ins in ipairs(inserts) do
			local p = ins.P :: RoadPoint
			table.insert(ring, { X = p.X, Y = p.Y, Z = p.Z, Cut = true } :: any)
		end
	end
	-- premier point de coupe comme départ
	local startIdx = 1
	for i, p in ipairs(ring) do
		if (p :: any).Cut then
			startIdx = i
			break
		end
	end
	local nRing = #ring
	local segPts: { RoadPoint } = { ring[startIdx] }
	local segStart = node(ring[startIdx].X, ring[startIdx].Z, y0, "Highway")
	for k = 1, nRing do
		local p = ring[(startIdx + k - 1) % nRing + 1]
		table.insert(segPts, { X = p.X, Y = p.Y, Z = p.Z })
		if (p :: any).Cut then
			local id = node(p.X, p.Z, y0, "Highway")
			local opts = table.clone(hwOpts)
			opts.Points = segPts
			addEdge(segStart, id, "Highway", opts)
			segStart = id
			segPts = { { X = p.X, Y = p.Y, Z = p.Z } }
		end
	end
	-- ÉCHANGEURS en losange : connecteur de la ceinture au pont, pont,
	-- route au-delà (rond-point), 4 bretelles
	local J = WorldLayout.RAMP_JUNCTION
	local outEnd = WorldLayout.OUTSIDE_END
	local rampOpts = { Width = WorldLayout.RAMP_W, Lanes = 1, OneWay = true, Speed = WorldLayout.SPEED.Ramp, Ramp = true, Sidewalk = 0, LaneOffsets = { 0 } }
	for _, ix in ipairs(INTERCHANGES) do
		local beltN = -(H - R) -- n de la ceinture
		local pBelt = ixPoint(ix, H, 0, beltN)
		local pCity = ixPoint(ix, H, 0, -J)
		local pOut = ixPoint(ix, H, 0, J)
		local pEnd = ixPoint(ix, H, 0, outEnd)
		local nBelt = node(pBelt.X, pBelt.Z, y0, "Junction")
		local nCity = node(pCity.X, pCity.Z, y0, "Junction")
		local nOut = node(pOut.X, pOut.Z, y0, "Junction")
		local nEnd = node(pEnd.X, pEnd.Z, y0, "Roundabout")
		local connectorKind = ix.Id == "S" and "Entrance" or "Connector"
		addEdge(nBelt, nCity, connectorKind, { Width = WorldLayout.ROAD_W, Lanes = 1, Speed = WorldLayout.SPEED.Avenue, Sidewalk = WorldLayout.WALK_W })
		-- pont : profil en long (points tous les 15 studs)
		local bridgePts: { RoadPoint } = {}
		for _, n in ipairs(WorldLayout.BridgeStations()) do
			table.insert(bridgePts, ixPoint(ix, H, 0, n, WorldLayout.BridgeProfile(n)))
		end
		addEdge(nCity, nOut, "Connector", { Width = WorldLayout.ROAD_W, Lanes = 1, Speed = WorldLayout.SPEED.Avenue, Sidewalk = 3, Bridge = true, Points = bridgePts })
		addEdge(nOut, nEnd, "Outside", { Width = WorldLayout.ROAD_W, Lanes = 1, Speed = WorldLayout.SPEED.Avenue, Sidewalk = WorldLayout.WALK_W })
		-- petit rond-point au bout (demi-tour) : 4 nœuds autour de nEnd
		local rr = 22
		local ringIds = {}
		for q = 0, 3 do
			local a = q * math.pi / 2
			local p = ixPoint(ix, H, math.sin(a) * rr, outEnd + math.cos(a) * rr)
			ringIds[q + 1] = node(p.X, p.Z, y0, "Roundabout")
		end
		for q = 1, 4 do
			local a0 = (q - 1) * math.pi / 2
			local pts = {}
			for s = 0, 4 do
				local a = a0 + s / 4 * math.pi / 2
				table.insert(pts, ixPoint(ix, H, math.sin(a) * rr, outEnd + math.cos(a) * rr))
			end
			addEdge(ringIds[q], ringIds[q % 4 + 1], "Roundabout", { Width = 12, Lanes = 1, OneWay = true, Speed = 20, Sidewalk = 0, LaneOffsets = { 0 }, Points = pts })
		end
		-- le bout de la route rejoint le rond-point (côté ville du cercle : q = 3 -> angle pi)
		-- (nEnd est au centre : on remplace l'arête nOut -> nEnd par nOut -> bas du cercle)
		local last = edges[#edges - 4]
		local south = ringIds[3]
		last.B = south
		last.Points = { { X = nodes[nOut].X, Y = y0, Z = nodes[nOut].Z }, { X = nodes[south].X, Y = y0, Z = nodes[south].Z } }
		last.Length = polyLength(last.Points)
		nodes[nEnd] = nil
		for i2, nd in ipairs(nodeList) do
			if nd.Id == nEnd then
				table.remove(nodeList, i2)
				break
			end
		end
		-- bretelles (chaussée côté ville = sens -t, chaussée extérieure = sens +t)
		local hwIn = node(ixPoint(ix, H, T, 0).X, ixPoint(ix, H, T, 0).Z, y0, "Highway") -- +T
		local hwOut = node(ixPoint(ix, H, -T, 0).X, ixPoint(ix, H, -T, 0).Z, y0, "Highway") -- -T
		local edgeN = WorldLayout.HIGHWAY_W / 2
		local function rampPts(list: { { number } }): { RoadPoint }
			local out = {}
			for _, tn in ipairs(list) do
				table.insert(out, ixPoint(ix, H, tn[1], tn[2]))
			end
			return out
		end
		-- sortie côté ville (vient de +t, roule vers -t) : +T -> carrefour ville
		addEdge(hwIn, nCity, "Ramp", (function()
			local o = table.clone(rampOpts)
			o.Points = rampPts({ { T, -WorldLayout.HIGHWAY_LANES[2] }, { T - 70, -edgeN - 4 }, { T - 170, -edgeN - 30 }, { 110, -J + 60 }, { 24, -J + 6 }, { 0, -J } })
			return o
		end)())
		-- entrée côté ville : carrefour ville -> -T (roule vers -t)
		addEdge(nCity, hwOut, "Ramp", (function()
			local o = table.clone(rampOpts)
			o.Points = rampPts({ { 0, -J }, { -24, -J + 6 }, { -110, -J + 60 }, { -(T - 170), -edgeN - 30 }, { -(T - 70), -edgeN - 4 }, { -T, -WorldLayout.HIGHWAY_LANES[2] } })
			return o
		end)())
		-- sortie extérieure (vient de -t, roule vers +t) : -T -> carrefour extérieur
		addEdge(hwOut, nOut, "Ramp", (function()
			local o = table.clone(rampOpts)
			o.Points = rampPts({ { -T, WorldLayout.HIGHWAY_LANES[2] }, { -(T - 70), edgeN + 4 }, { -(T - 170), edgeN + 30 }, { -110, J - 60 }, { -24, J - 6 }, { 0, J } })
			return o
		end)())
		-- entrée extérieure : carrefour extérieur -> +T (roule vers +t)
		addEdge(nOut, hwIn, "Ramp", (function()
			local o = table.clone(rampOpts)
			o.Points = rampPts({ { 0, J }, { 24, J - 6 }, { 110, J - 60 }, { T - 170, edgeN + 30 }, { T - 70, edgeN + 4 }, { T, WorldLayout.HIGHWAY_LANES[2] } })
			return o
		end)())
	end
	-- voisins
	local adjacent: { [string]: { RoadEdge } } = {}
	for _, e in ipairs(edges) do
		adjacent[e.A] = adjacent[e.A] or {}
		table.insert(adjacent[e.A], e)
		if not e.OneWay then
			adjacent[e.B] = adjacent[e.B] or {}
			table.insert(adjacent[e.B], e)
		end
	end
	local graph: RoadGraph = { Nodes = nodes, NodeList = nodeList, Edges = edges, Adjacent = adjacent, Crossings = crossings }
	graphCache[count] = graph
	return graph
end

-- Graphe routier de la ville (en cache : ne pas modifier)
function WorldLayout.RoadGraph(count: number): RoadGraph
	return buildGraph(WorldLayout.PlotCount(count))
end

-- Polyligne d'une arête dans le sens `fromId` -> l'autre bout
function WorldLayout.EdgePoints(edge: RoadEdge, fromId: string?): { RoadPoint }
	if fromId == nil or fromId == edge.A then
		return edge.Points
	end
	local out = table.create(#edge.Points)
	for i = #edge.Points, 1, -1 do
		table.insert(out, edge.Points[i])
	end
	return out
end

-- Plus court chemin (Dijkstra, longueurs des arêtes, sens uniques
-- respectés) : liste d'arêtes + liste des nœuds, ou nil
function WorldLayout.RoutePath(count: number, fromId: string, toId: string): ({ RoadEdge }?, { string }?)
	local g = WorldLayout.RoadGraph(count)
	if not g.Nodes[fromId] or not g.Nodes[toId] then
		return nil, nil
	end
	local dist: { [string]: number } = { [fromId] = 0 }
	local via: { [string]: RoadEdge } = {}
	local done: { [string]: boolean } = {}
	while true do
		local best, bestD = nil, math.huge
		for id, dd in pairs(dist) do
			if not done[id] and dd < bestD then
				best, bestD = id, dd
			end
		end
		if not best or best == toId then
			break
		end
		done[best] = true
		for _, e in ipairs(g.Adjacent[best] or {}) do
			local other = e.A == best and e.B or e.A
			local nd = bestD + e.Length
			if nd < (dist[other] or math.huge) then
				dist[other] = nd
				via[other] = e
			end
		end
	end
	if not dist[toId] then
		return nil, nil
	end
	local pathEdges, pathNodes = {}, { toId }
	local cur = toId
	while cur ~= fromId do
		local e = via[cur]
		table.insert(pathEdges, 1, e)
		cur = e.A == cur and e.B or e.A
		table.insert(pathNodes, 1, cur)
	end
	return pathEdges, pathNodes
end

-- Nœud le plus proche d'un point (repère ville) ; `filter(node)` facultatif
function WorldLayout.NearestNode(count: number, x: number, z: number, filter: ((RoadNode) -> boolean)?): RoadNode?
	local best, bestD = nil, math.huge
	for _, n in ipairs(WorldLayout.RoadGraph(count).NodeList) do
		if not filter or filter(n) then
			local d = (n.X - x) ^ 2 + (n.Z - z) ^ 2
			if d < bestD then
				best, bestD = n, d
			end
		end
	end
	return best
end

-- Point le plus proche sur la chaussée : (arête, x, y, z, distance, t 0..1 le long de l'arête)
function WorldLayout.NearestRoad(count: number, x: number, z: number, filter: ((RoadEdge) -> boolean)?): (RoadEdge?, number, number, number, number, number)
	local bestE, bx, by, bz, bestD, bestT = nil, 0, 0, 0, math.huge, 0
	for _, e in ipairs(WorldLayout.RoadGraph(count).Edges) do
		if not filter or filter(e) then
			local acc = 0
			for i = 2, #e.Points do
				local a, b = e.Points[i - 1], e.Points[i]
				local dx, dz = b.X - a.X, b.Z - a.Z
				local len2 = dx * dx + dz * dz
				local seg = math.sqrt(len2 + (b.Y - a.Y) ^ 2)
				local t = len2 > 0 and math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / len2, 0, 1) or 0
				local px, pz = a.X + dx * t, a.Z + dz * t
				local d = math.sqrt((px - x) ^ 2 + (pz - z) ^ 2)
				if d < bestD then
					bestE, bx, by, bz, bestD = e, px, a.Y + (b.Y - a.Y) * t, pz, d
					bestT = e.Length > 0 and (acc + seg * t) / e.Length or 0
				end
				acc += seg
			end
		end
	end
	return bestE, bx, by, bz, bestD, bestT
end

-- Point à la distance `s` le long d'une polyligne : x, y, z, direction (dx, dz)
function WorldLayout.PointAlong(points: { RoadPoint }, s: number): (number, number, number, number, number)
	local remain = math.max(0, s)
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local seg = math.sqrt((b.X - a.X) ^ 2 + (b.Y - a.Y) ^ 2 + (b.Z - a.Z) ^ 2)
		if remain <= seg or i == #points then
			local t = seg > 0 and math.clamp(remain / seg, 0, 1) or 0
			local hl = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
			local dx, dz = 0, -1
			if hl > 1e-6 then
				dx, dz = (b.X - a.X) / hl, (b.Z - a.Z) / hl
			end
			return a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t, dx, dz
		end
		remain -= seg
	end
	local p = points[#points]
	return p.X, p.Y, p.Z, 0, -1
end

-- Nœuds nommés utiles aux courses (RACE10) : carrefours remarquables
function WorldLayout.RaceAnchors(count: number): { [string]: string }
	local B, R = WorldLayout.DOWNTOWN_B, WorldLayout.BeltR(count)
	local H = WorldLayout.HighwayR(count)
	local out: { [string]: string } = {}
	local g = WorldLayout.RoadGraph(count)
	local function id(x: number, z: number): string
		return "n" .. r2(x) .. "_" .. r2(z)
	end
	for name, p in pairs({
		DowntownSE = { B, B }, DowntownSW = { -B, B }, DowntownNE = { B, -B }, DowntownNW = { -B, -B },
		BeltSE = { R, R }, BeltSW = { -R, R }, BeltNE = { R, -R }, BeltNW = { -R, -R },
		BeltS = { 0, R }, BeltN = { 0, -R }, BeltE = { R, 0 }, BeltW = { -R, 0 },
		EntranceBoulevard = { 0, B },
		EntranceLoop = { 0, WorldLayout.GateDistance(count) + WorldLayout.ARRIVAL_LOOP + WorldLayout.ARRIVAL_LOOP_R },
		MarketStreetW = { -B, WorldLayout.MARKET_STREET_Z }, MarketStreetE = { B, WorldLayout.MARKET_STREET_Z },
	}) do
		local key = id(p[1], p[2])
		if g.Nodes[key] then
			out[name] = key
		end
	end
	for _, ix in ipairs(INTERCHANGES) do
		local pc = ixPoint(ix, H, 0, -WorldLayout.RAMP_JUNCTION)
		local po = ixPoint(ix, H, 0, WorldLayout.RAMP_JUNCTION)
		local ph = ixPoint(ix, H, WorldLayout.RAMP_T, 0)
		out["Ramp" .. ix.Id .. "City"] = id(pc.X, pc.Z)
		out["Ramp" .. ix.Id .. "Out"] = id(po.X, po.Z)
		out["Highway" .. ix.Id] = id(ph.X, ph.Z)
	end
	return out
end

----------------------------------------------------------------------
-- (v10) Lieux réservés (repère ville) : rectangles orientés
----------------------------------------------------------------------
-- { Id, Name, Kind, X, Z, W (largeur, x local), D (profondeur, z local),
--   Yaw (radians : CFrame.Angles(0, Yaw, 0)), Y }. Kind : "Downtown" |
--   "Facility" | "District" | "Nature" | "Highway". Un point est "dans" un
--   lieu s'il est dans son rectangle (repère local).
export type Zone = { Id: string, Name: string, Kind: string, X: number, Z: number, W: number, D: number, Yaw: number, Y: number }

-- (v10) point de rendez-vous des courses (RACE10) : à gauche de l'avenue
-- d'entrée (ligne droite de ~530 studs entre la porte et la ceinture)
WorldLayout.RACE_MEET_Z = 560
WorldLayout.RACE_MEET_W = 44 -- (x) profondeur depuis le trottoir
WorldLayout.RACE_MEET_D = 64 -- (z) le long de l'avenue

local zoneCache: { [number]: { Zone } } = {}
function WorldLayout.Facilities(count: number): { Zone }
	local n = WorldLayout.PlotCount(count)
	local cached = zoneCache[n]
	if cached then
		return cached
	end
	local B, R, H = WorldLayout.DOWNTOWN_B, WorldLayout.BeltR(n), WorldLayout.HighwayR(n)
	local gate = WorldLayout.GateDistance(n)
	local front = WorldLayout.PlotFrontRadius(n)
	local zones: { Zone } = {}
	local function add(id: string, name: string, kind: string, x: number, z: number, w: number, d: number, yaw: number?, y: number?)
		table.insert(zones, { Id = id, Name = name, Kind = kind, X = x, Z = z, W = w, D = d, Yaw = yaw or 0, Y = y or 0 })
	end
	local inner = B - WorldLayout.ROAD_W / 2 - WorldLayout.WALK_W
	add("Downtown", "Downtown", "Downtown", 0, 0, 2 * inner, 2 * inner)
	add("Plaza", "Main square", "Downtown", 0, 0, 2 * (WorldLayout.PLAZA_R + 30), 2 * (WorldLayout.PLAZA_R + 30))
	add("TownHall", "Town hall", "Downtown", 0, -(WorldLayout.PLAZA_R + 16), 60, 30)
	add("Fair", "Fun fair", "Facility", 0, -(WorldLayout.FAIR_NEAR + WorldLayout.FAIR_D / 2), WorldLayout.FAIR_W, WorldLayout.FAIR_D)
	add("MusicStage", "Music stage", "Downtown", math.sin(math.rad(225)) * 42, math.cos(math.rad(225)) * 42, 24, 16)
	add("FoodCorner", "Food corner", "Facility", 70, front + 9 + WorldLayout.FOOD_D / 2, WorldLayout.FOOD_W, WorldLayout.FOOD_D)
	add("Gate", "Town gate", "Facility", 0, gate, 64, 24)
	add("Market", "MégaDopa", "Facility", WorldLayout.MARKET_X + WorldLayout.MARKET_D / 2, gate + 20 + WorldLayout.MARKET_W / 2, WorldLayout.MARKET_D, WorldLayout.MARKET_W)
	add("MarketLot", "MégaDopa parking", "Facility", WorldLayout.MARKET_X - WorldLayout.MARKET_LOT / 2, gate + 20 + WorldLayout.MARKET_W / 2, WorldLayout.MARKET_LOT, WorldLayout.MARKET_W)
	add("Dealership", "Car dealer", "Facility", -(WorldLayout.DEALER_X + WorldLayout.DEALER_D / 2), gate + WorldLayout.DEALER_Z0 + WorldLayout.DEALER_W / 2, WorldLayout.DEALER_D, WorldLayout.DEALER_W)
	-- (W = le long de l'avenue, D = profondeur ; regard vers l'avenue, +X)
	add("RaceMeet", "Race meeting point", "Facility", -(WorldLayout.GRID_HALF + 4 + WorldLayout.RACE_MEET_W / 2), WorldLayout.RACE_MEET_Z, WorldLayout.RACE_MEET_D, WorldLayout.RACE_MEET_W, -math.pi / 2)
	-- case sud, au-delà du rendez-vous des courses : gare routière / parc relais (libre pour CITY10)
	local s0, s1 = gate + 20 + WorldLayout.MARKET_W + 16, R - WorldLayout.GRID_HALF - 4
	local sp0 = math.max(s0, WorldLayout.RACE_MEET_Z + WorldLayout.RACE_MEET_D / 2 + 8)
	if s1 - sp0 >= 30 then
		add("SouthPark", "South park", "Nature", 0, (sp0 + s1) / 2, 2 * (B - WorldLayout.GRID_HALF - 4), s1 - sp0)
	end
	-- cases nord-ouest / nord-est : bois des collines, parc des sports
	do
		local x0, x1, z0, z1 = cellRect(-1, -1, R)
		add("HillWoods", "Hill woods", "Nature", (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0)
		x0, x1, z0, z1 = cellRect(1, -1, R)
		add("SportsPark", "Sports park", "Nature", (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0)
	end
	for _, d in ipairs(WorldLayout.Districts(n)) do
		add("District_" .. d.Id, d.Name, "District", d.Bounds.X, d.Bounds.Z, d.Bounds.W, d.Bounds.D, 0, d.Rise)
	end
	-- échangeurs : aire de repos au sud, belvédères ailleurs (au bout de la route extérieure)
	for _, ix in ipairs(INTERCHANGES) do
		local p = ixPoint(ix, H, 0, WorldLayout.OUTSIDE_END)
		local yaw = yawOf(-ix.NX, -ix.NZ)
		add("Interchange_" .. ix.Id, "Interchange", "Highway", ix.NX * H, ix.NZ * H, (ix.NX ~= 0) and 2 * WorldLayout.RAMP_JUNCTION + 40 or 2 * WorldLayout.RAMP_T + 40, (ix.NX ~= 0) and 2 * WorldLayout.RAMP_T + 40 or 2 * WorldLayout.RAMP_JUNCTION + 40)
		add(ix.Id == "S" and "RestArea" or ("Lookout_" .. ix.Id), ix.Id == "S" and "Rest area" or "Lookout", "Highway", p.X + ix.NX * 40, p.Z + ix.NZ * 40, 70, 50, yaw)
	end
	zoneCache[n] = zones
	return zones
end

function WorldLayout.Facility(count: number, id: string): Zone?
	for _, z in ipairs(WorldLayout.Facilities(count)) do
		if z.Id == id then
			return z
		end
	end
	return nil
end

-- Point (x, z) dans un lieu (marge en studs, > 0 = plus large)
function WorldLayout.InZone(zone: Zone, x: number, z: number, margin: number?): boolean
	local c, s = math.cos(zone.Yaw), math.sin(zone.Yaw)
	local dx, dz = x - zone.X, z - zone.Z
	-- repère local : x = RightVector, z = -LookVector (CFrame.Angles(0, yaw, 0))
	local lx = dx * c - dz * s
	local lz = dx * s + dz * c
	local m = margin or 0
	return math.abs(lx) <= zone.W / 2 + m and math.abs(lz) <= zone.D / 2 + m
end

-- Distance (x, z) à l'axe d'une arête (polyligne), à plat
local function edgeDistance(e: RoadEdge, x: number, z: number): number
	local best = math.huge
	for i = 2, #e.Points do
		local a, b = e.Points[i - 1], e.Points[i]
		local dx, dz = b.X - a.X, b.Z - a.Z
		local len2 = dx * dx + dz * dz
		local t = len2 > 0 and math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / len2, 0, 1) or 0
		best = math.min(best, math.sqrt((a.X + dx * t - x) ^ 2 + (a.Z + dz * t - z) ^ 2))
	end
	return best
end
WorldLayout.EdgeDistance = edgeDistance

-- Sur une route (chaussée + trottoirs + `margin`) ?
function WorldLayout.OnRoad(count: number, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	for _, e in ipairs(WorldLayout.RoadGraph(count).Edges) do
		local half = e.Width / 2 + e.Sidewalk + m
		-- (boîte englobante d'abord)
		local p1, p2 = e.Points[1], e.Points[#e.Points]
		local minX, maxX = math.min(p1.X, p2.X), math.max(p1.X, p2.X)
		local minZ, maxZ = math.min(p1.Z, p2.Z), math.max(p1.Z, p2.Z)
		for _, p in ipairs(e.Points) do
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		end
		if x >= minX - half and x <= maxX + half and z >= minZ - half and z <= maxZ + half then
			if edgeDistance(e, x, z) <= half then
				return true
			end
		end
	end
	return false
end

-- Sur une parcelle (ou une place vide de quartier) ? (marge en studs)
function WorldLayout.OnPlot(count: number, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	local city = buildCity(WorldLayout.PlotCount(count))
	local W, D = WorldLayout.PLOT_W, WorldLayout.PLOT_D
	local function inside(p: any): boolean
		local dx, dz = x - p.X, z - p.Z
		-- largeur le long de la rue (perpendiculaire au regard)
		local along = math.abs(dx * p.LookZ - dz * p.LookX)
		local across = math.abs(dx * p.LookX + dz * p.LookZ)
		return along <= W / 2 + m and across <= D / 2 + m
	end
	for _, p in ipairs(city.Plots) do
		if inside(p) then
			return true
		end
	end
	for _, d in ipairs(city.Districts) do
		for _, lot in ipairs(d.Lots) do
			if inside(lot) then
				return true
			end
		end
	end
	return false
end

-- Place libre en ville (ni route, ni parcelle, ni lieu réservé sauf les
-- zones de type "Downtown" / "District" / "Nature", qui accueillent le décor)
-- pour un objet de rayon r
function WorldLayout.IsFreeAt(count: number, x: number, z: number, r: number): boolean
	if WorldLayout.OnRoad(count, x, z, r) or WorldLayout.OnPlot(count, x, z, r) then
		return false
	end
	for _, zone in ipairs(WorldLayout.Facilities(count)) do
		if (zone.Kind == "Facility" or zone.Kind == "Highway") and WorldLayout.InZone(zone, x, z, r) then
			return false
		end
	end
	if math.sqrt(x * x + z * z) < WorldLayout.PLAZA_R + 26 + r then
		return false
	end
	return math.max(math.abs(x), math.abs(z)) < WorldLayout.TownRadius(count) - 20 - r
end

----------------------------------------------------------------------
-- Repères Roblox (CFrame) : utilisés en jeu uniquement (pas dans les tests)
----------------------------------------------------------------------

-- Centre de la ville (loin de la Baseplate du lieu)
WorldLayout.ORIGIN_X, WorldLayout.ORIGIN_Y, WorldLayout.ORIGIN_Z = 0, 60, 2600

function WorldLayout.Origin(): Vector3
	return Vector3.new(WorldLayout.ORIGIN_X, WorldLayout.ORIGIN_Y, WorldLayout.ORIGIN_Z)
end

-- (v10) Point / repère en jeu depuis le repère ville (x, y, z depuis Origin)
function WorldLayout.CityPoint(x: number, y: number, z: number): Vector3
	return WorldLayout.Origin() + Vector3.new(x, y, z)
end

-- Repère au sol : position (x, y, z) ville, CFrame.Angles(0, yaw, 0)
function WorldLayout.CityCFrame(x: number, z: number, yaw: number?, y: number?): CFrame
	return CFrame.new(WorldLayout.CityPoint(x, y or 0, z)) * CFrame.Angles(0, yaw or 0, 0)
end

-- Parcelle : centre au niveau du sol (Origin().Y, + MANSION_RISE sur la
-- colline des manoirs), LookVector = vers SA RUE (v10 ; avant : vers la place)
function WorldLayout.PlotCFrame(index: number, count: number): CFrame
	local place = WorldLayout.PlotPlaceData(index, count)
	if not place then
		return CFrame.new(WorldLayout.Origin())
	end
	local center = WorldLayout.CityPoint(place.X, place.Y, place.Z)
	return CFrame.lookAt(center, center + Vector3.new(place.LookX, 0, place.LookZ))
end

-- (v10) Place vide d'un quartier (FillerLots) : même repère qu'une parcelle
function WorldLayout.LotCFrame(lot: Lot): CFrame
	local center = WorldLayout.CityPoint(lot.X, lot.Y, lot.Z)
	return CFrame.lookAt(center, center + Vector3.new(lot.LookX, 0, lot.LookZ))
end

-- (v10) Lieu réservé (Facilities) : centre au sol, CFrame.Angles(0, Yaw, 0)
function WorldLayout.ZoneCFrame(zone: Zone): CFrame
	return WorldLayout.CityCFrame(zone.X, zone.Z, zone.Yaw, zone.Y)
end

-- (v9.4) Porte de la ville : centre de l'arche au sol, LookVector = vers la place
function WorldLayout.GateCFrame(count: number): CFrame
	local p = WorldLayout.Origin() + Vector3.new(0, WorldLayout.WALK_Y, WorldLayout.GateDistance(count))
	return CFrame.lookAt(p, p - Vector3.new(0, 0, 1))
end

-- Apparition à l'entrée : pieds ~3 studs au-dessus du pavé, juste à
-- l'intérieur de la porte, regard vers l'avenue et la place
function WorldLayout.EntranceCFrame(count: number): CFrame
	local p = WorldLayout.Origin() + Vector3.new(0, WorldLayout.WALK_Y + 3, WorldLayout.GateDistance(count) - WorldLayout.SPAWN_INSIDE)
	return CFrame.lookAt(p, p - Vector3.new(0, 0, 1))
end

-- (v9.7, BUILDINGS97) 🛒 Supermarché, hors de la porte, à droite de la
-- route d'arrivée (en venant de la ville) : façade tournée vers la route
-- (-X monde), parking entre les deux. (v9.8, MARKET98) agrandi à 104 x 68,
-- reculé (+Z : l'entrée fait face au rond-point) ; tient dans les murs de
-- 4 à 12 parcelles (TOWN_MARGIN 140 ; coin le plus loin : x = 148,
-- z = porte + 124) sans toucher les parcelles, la route ni le rond-point.
WorldLayout.MARKET_W = 104 -- façade (le long de la route) ; v9.7 : 70
WorldLayout.MARKET_D = 68 -- profondeur ; v9.7 : 48
WorldLayout.MARKET_X = 74 -- distance de la façade à l'axe de la route
WorldLayout.MARKET_LOT = 42 -- profondeur du parking devant la façade (trottoir compris : +10)

-- Pied de la façade (milieu), LookVector vers la route ; volume derrière (+Z local)
function WorldLayout.MarketCFrame(count: number): CFrame
	local p = WorldLayout.Origin() + Vector3.new(WorldLayout.MARKET_X, WorldLayout.WALK_Y, WorldLayout.GateDistance(count) + 20 + WorldLayout.MARKET_W / 2)
	return CFrame.lookAt(p, p - Vector3.new(1, 0, 0))
end

-- (v9.8, CARS98) 🚗 CONCESSION AUTO, hors de la porte, à GAUCHE de la route
-- d'arrivée (le miroir du supermarché) : grand hall vitré DEALER_W (façade,
-- le long de la route) x DEALER_D (profondeur), façade tournée vers la route
-- (+X monde) ; parvis avec le plateau tournant entre le hall et la route.
-- Tout est relatif à la porte : tient de 4 à 12 parcelles (derrière le fond
-- des parcelles, avant le rond-point, dans les murs).
WorldLayout.DEALER_W = 70
WorldLayout.DEALER_D = 50
WorldLayout.DEALER_X = 60 -- distance de la façade à l'axe de la route
WorldLayout.DEALER_Z0 = 14 -- début du hall après la porte (le long de la route)

-- Pied de la façade (milieu), LookVector vers la route ; volume derrière (+Z local)
function WorldLayout.DealershipCFrame(count: number): CFrame
	local p = WorldLayout.Origin() + Vector3.new(-WorldLayout.DEALER_X, WorldLayout.WALK_Y, WorldLayout.GateDistance(count) + WorldLayout.DEALER_Z0 + WorldLayout.DEALER_W / 2)
	return CFrame.lookAt(p, p + Vector3.new(1, 0, 0))
end

-- (v9.8, FAIR98) 🎡 FÊTE FORAINE : derrière la mairie, dans le secteur
-- arrière de l'anneau (axe -Z), rectangle FAIR_W x FAIR_D dont le bord
-- avant est à FAIR_NEAR studs du centre. Tient de 4 à 12 parcelles (bord
-- du boulevard, lac, jardin, terrain de basket : vérifié). Repère : centre
-- du sol de la fête (FairRides.GROUND au-dessus du pré), LookVector vers
-- la place (l'entrée) ; x local ∈ [-FAIR_W/2, FAIR_W/2], z ∈ [-FAIR_D/2, FAIR_D/2].
WorldLayout.FAIR_W = 110
WorldLayout.FAIR_D = 72
WorldLayout.FAIR_NEAR = 104 -- (couloir de ~14 studs derrière la mairie)
WorldLayout.FAIR_GROUND = 0.15

function WorldLayout.FairCFrame(): CFrame
	local p = WorldLayout.Origin() + Vector3.new(0, WorldLayout.GROUND_Y + WorldLayout.FAIR_GROUND, -(WorldLayout.FAIR_NEAR + WorldLayout.FAIR_D / 2))
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end

-- (v9.8, FAIR98) 🍦 Coin gourmand (ancienne place de la concession, à
-- droite de la place d'accueil) : centre au sol, LookVector vers le
-- boulevard (-Z monde) ; x local = x monde ; FOOD_W x FOOD_D
WorldLayout.FOOD_W = 40
WorldLayout.FOOD_D = 44
function WorldLayout.FoodCornerCFrame(count: number): CFrame
	local p = WorldLayout.Origin() + Vector3.new(70, WorldLayout.WALK_Y, WorldLayout.PlotFrontRadius(count) + 9 + WorldLayout.FOOD_D / 2)
	return CFrame.lookAt(p, p - Vector3.new(0, 0, 1))
end

-- Centre de la place, au sol (dessus du pavé)
function WorldLayout.PlazaCFrame(): CFrame
	return CFrame.new(WorldLayout.Origin() + Vector3.new(0, WorldLayout.WALK_Y, 0))
end

-- Maison : milieu de la façade au sol, regarde DANS la maison (RightVector =
-- droite du visiteur qui arrive de la place)
function WorldLayout.HouseCFrame(plotCF: CFrame): CFrame
	local front = plotCF.Position + plotCF.LookVector * WorldLayout.HouseFrontOffset()
	return CFrame.lookAt(front, front - plotCF.LookVector)
end

-- Point du repère local (x, y, d) -> monde
function WorldLayout.ToWorld(houseCF: CFrame, x: number, y: number, d: number): Vector3
	return houseCF * Vector3.new(x, y, -d)
end

-- Monde -> repère local (x, y, d)
function WorldLayout.ToLocal(houseCF: CFrame, point: Vector3): (number, number, number)
	local p = houseCF:PointToObjectSpace(point)
	return p.X, p.Y, -p.Z
end

-- Pivot de la coque d'une pièce (House3DScene.BuildRoomShell : centre du
-- dessus du sol, mur du fond vers -Z)
function WorldLayout.ShellPivot(houseCF: CFrame, size: SizeDef?, slot: number): CFrame
	local x, y, d = WorldLayout.RoomCenter(size, slot)
	return houseCF * CFrame.new(x, y, -d)
end

-- Repère de la pièce pour la 2D <-> 3D (face intérieure du mur du fond, +Z vers l'avant)
function WorldLayout.RoomFrame(houseCF: CFrame, size: SizeDef?, slot: number): CFrame
	return WorldLayout.ShellPivot(houseCF, size, slot) * CFrame.new(0, 0, -WorldLayout.DEPTH / 2)
end

-- Apparition devant la porte d'entrée (regarde la maison)
function WorldLayout.DoorSpawn(houseCF: CFrame, size: SizeDef?): CFrame
	local x = WorldLayout.DoorX(size)
	local position = WorldLayout.ToWorld(houseCF, x, 3.2, -WorldLayout.SPAWN_FRONT)
	local target = WorldLayout.ToWorld(houseCF, x, 3.2, 5)
	return CFrame.lookAt(position, target)
end

-- Centre d'une pièce (pour y apparaître)
function WorldLayout.RoomSpawn(houseCF: CFrame, size: SizeDef?, slot: number): CFrame
	local xMin, xMax, yFloor, dMin, dMax = WorldLayout.RoomInterior(size, slot)
	local x = (xMin + xMax) / 2
	local position = WorldLayout.ToWorld(houseCF, x, yFloor + 3.2, dMin + (dMax - dMin) * 0.35)
	return CFrame.lookAt(position, WorldLayout.ToWorld(houseCF, x, yFloor + 3.2, dMax))
end

----------------------------------------------------------------------
-- Accès / visites / "j'aime" (règles pures, testées)
----------------------------------------------------------------------

WorldLayout.OPEN_MODES = { "Everyone", "Friends", "Nobody" }
WorldLayout.DEFAULT_OPEN = "Everyone"
WorldLayout.LIKES_PER_DAY = 10 -- "j'aime" donnés par visiteur et par jour
WorldLayout.LIKE_REWARD_SECONDS = 20 -- visiteur : 20 s de sa production
WorldLayout.LIKED_REWARD_SECONDS = 60 -- propriétaire : 60 s de sa production
WorldLayout.LIKED_REWARDS_PER_DAY = 30 -- "j'aime" reçus récompensés par jour

function WorldLayout.NormalizeOpen(mode: any): string
	if type(mode) == "string" and table.find(WorldLayout.OPEN_MODES, mode) then
		return mode
	end
	return WorldLayout.DEFAULT_OPEN
end

-- Le visiteur peut-il entrer ? (le propriétaire toujours)
function WorldLayout.CanEnter(mode: any, isOwner: boolean, isFriend: boolean): boolean
	if isOwner then
		return true
	end
	local open = WorldLayout.NormalizeOpen(mode)
	if open == "Everyone" then
		return true
	elseif open == "Friends" then
		return isFriend == true
	end
	return false
end

function WorldLayout.DayNumber(now: number): number
	return math.floor(finite(now, 0) / 86400)
end

export type TownData = {
	Open: string,
	Likes: number,
	Visits: number,
	LikeDay: number,
	Liked: { [string]: boolean }, -- maisons aimées aujourd'hui (UserId en texte)
	LikesGiven: number, -- "j'aime" donnés aujourd'hui
	LikedRewards: number, -- "j'aime" reçus récompensés aujourd'hui
	RewardDay: number,
}

-- Données "Town" d'un joueur, réparées (sauvegardes abîmées, anciennes, nouveau jour)
function WorldLayout.SanitizeTown(raw: any, now: number): TownData
	local town = type(raw) == "table" and raw or {}
	local day = WorldLayout.DayNumber(now)
	local sameDay = math.floor(finite(town.LikeDay, -1)) == day
	local liked: { [string]: boolean } = {}
	local given = 0
	if sameDay then
		given = math.max(0, math.floor(finite(town.LikesGiven, 0)))
		if type(town.Liked) == "table" then
			local count = 0
			for key, value in pairs(town.Liked) do
				if type(key) == "string" and #key <= 20 and value == true and count < 200 then
					liked[key] = true
					count += 1
				end
			end
		end
	end
	local rewards = 0
	if math.floor(finite(town.RewardDay, -1)) == day then
		rewards = math.max(0, math.floor(finite(town.LikedRewards, 0)))
	end
	return {
		Open = WorldLayout.NormalizeOpen(town.Open),
		Likes = math.clamp(math.floor(finite(town.Likes, 0)), 0, 1e9),
		Visits = math.clamp(math.floor(finite(town.Visits, 0)), 0, 1e9),
		LikeDay = day,
		Liked = liked,
		LikesGiven = given,
		LikedRewards = rewards,
		RewardDay = day,
	}
end

-- Un "j'aime" de `likerId` pour la maison de `ownerId` est-il permis ?
-- -> (ok, raison) avec raison = "Self" | "Already" | "Limit"
function WorldLayout.CanLike(likerTown: TownData, likerId: number, ownerId: number): (boolean, string?)
	if likerId == ownerId then
		return false, "Self"
	end
	if likerTown.Liked[tostring(ownerId)] then
		return false, "Already"
	end
	if likerTown.LikesGiven >= WorldLayout.LIKES_PER_DAY then
		return false, "Limit"
	end
	return true, nil
end

-- Enregistre un "j'aime" (après CanLike) ; renvoie true si le propriétaire
-- reçoit encore sa récompense aujourd'hui
function WorldLayout.ApplyLike(likerTown: TownData, ownerTown: TownData, ownerId: number): boolean
	likerTown.Liked[tostring(ownerId)] = true
	likerTown.LikesGiven += 1
	ownerTown.Likes += 1
	if ownerTown.LikedRewards < WorldLayout.LIKED_REWARDS_PER_DAY then
		ownerTown.LikedRewards += 1
		return true
	end
	return false
end

-- Récompense (Dopamine) = secondes de production, jamais négative / infinie
function WorldLayout.RewardAmount(perSecond: any, seconds: number): number
	local rate = finite(perSecond, 0)
	if rate <= 0 then
		return 0
	end
	return math.min(rate * seconds, 1e300)
end

-- Point (repère local de la maison) dans la maison ? (marge en studs, < 0 = plus strict)
function WorldLayout.InsideHouse(size: SizeDef?, x: number, y: number, d: number, margin: number?): boolean
	local dims = WorldLayout.Dims(size)
	local m = margin or 0
	return x >= dims.Left - m and x <= dims.Left + dims.Width + m and d >= -m and d <= dims.Depth + m
		and y >= -2 and y <= dims.Height + WorldLayout.ROOF_H
end

-- Pièce (emplacement) qui contient un point local, sinon nil (cage / dehors)
function WorldLayout.SlotAt(size: SizeDef?, x: number, y: number, d: number): number?
	local dims = WorldLayout.Dims(size)
	if d < 0 or d > dims.Depth then
		return nil
	end
	local floor = math.floor((y - WorldLayout.PLINTH - WorldLayout.SLAB + 0.5) / WorldLayout.STORY) + 1
	if floor < 1 or floor > dims.Floors then
		return nil
	end
	-- (v9.4) la cage peut être à droite ou au milieu : WorldLayout.ColumnAt
	local column = WorldLayout.ColumnAt(size, x)
	if not column then
		return nil
	end
	return (floor - 1) * dims.Columns + column
end

return WorldLayout
