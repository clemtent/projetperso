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
WorldLayout.MAX_PLOTS = 12
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

-- Escalier (v9.4, dans la cage) : une volée droite par étage (étage k -> k+1),
-- au MILIEU de la cage (face à la porte d'entrée), couloirs de chaque côté.
-- 13 marches de STAIR_RISE (1 stud) x STAIR_TREAD (1,4 stud) : pente ~35,5°.
-- Bas de la volée à STAIR_D0 (vestibule devant), haut à STAIR_D1 (palier du
-- fond, toute la largeur de la cage). Trémie dans le plancher du dessus entre
-- STAIR_HOLE_D0 et STAIR_D1 : là où la marche dépasse WALL_H - HEADROOM, pour
-- garder >= HEADROOM studs sous le plancher partout sur le chemin.
-- Collision : une rampe lisse invisible (pas de marche où l'avatar accroche).
WorldLayout.STAIR_W = 5
WorldLayout.STAIR_RISE = 1
WorldLayout.STAIR_STEPS = 13 -- = STORY / STAIR_RISE
WorldLayout.STAIR_TREAD = 1.4
WorldLayout.STAIR_D0 = 4
WorldLayout.STAIR_D1 = 4 + 13 * 1.4 -- 22,2
-- (v9.8 HOUSE98 : 7,5 -> 8,5 studs de hauteur libre : trémie plus longue)
WorldLayout.HEADROOM = 8.5
WorldLayout.STAIR_HOLE_D0 = 4 + (12 - 8.5) * 1.4 -- 8,9 (marche à 3,5 : 12 - 3,5 = 8,5 de hauteur libre)

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

-- x du milieu de la porte d'entrée = milieu de la cage (l'escalier lui fait face)
function WorldLayout.DoorX(size: SizeDef?): number
	local x0, x1 = WorldLayout.HallSpan(size)
	return (x0 + x1) / 2
end

-- Bande de l'escalier (x gauche, x droite) : centrée dans la cage
function WorldLayout.StairSpan(size: SizeDef?): (number, number)
	local x = WorldLayout.DoorX(size)
	return x - WorldLayout.STAIR_W / 2, x + WorldLayout.STAIR_W / 2
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

-- Hauteur (au-dessus du sol de l'étage) du dessus de la rampe / des marches à
-- la profondeur d (0 avant STAIR_D0, STORY après STAIR_D1)
function WorldLayout.StairHeight(d: number): number
	local t = (d - WorldLayout.STAIR_D0) / (WorldLayout.STAIR_D1 - WorldLayout.STAIR_D0)
	return math.clamp(t, 0, 1) * WorldLayout.STORY
end

-- Pente de la volée (degrés)
function WorldLayout.StairSlope(): number
	return math.deg(math.atan2(WorldLayout.STORY, WorldLayout.STAIR_D1 - WorldLayout.STAIR_D0))
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
-- Parcelles autour de la place (anneau)
----------------------------------------------------------------------

function WorldLayout.PlotCount(maxPlayers: any): number
	return math.clamp(math.floor(finite(maxPlayers, 8)), WorldLayout.MIN_PLOTS, WorldLayout.MAX_PLOTS)
end

-- (v9.4) Emplacements autour de la place : count + 1 ; l'emplacement 0
-- (direction +Z depuis le centre) est l'ENTRÉE de la ville (porte, place
-- d'accueil), les parcelles 1..count suivent dans le sens des angles
function WorldLayout.PlotSlots(count: number): number
	return math.max(3, count) + 1
end

-- Angle (radians) de l'emplacement `slot` (0 = entrée)
function WorldLayout.SlotAngle(slot: number, count: number): number
	return slot / WorldLayout.PlotSlots(count) * math.pi * 2
end

-- Rayon du centre des parcelles : les coins avant de deux parcelles voisines
-- ne se touchent jamais
function WorldLayout.PlotRadius(count: number): number
	local m = WorldLayout.PlotSlots(count)
	local front = (WorldLayout.PLOT_W / 2 + 6) / math.tan(math.pi / m)
	return math.max(front, WorldLayout.PLAZA_R + 150) + WorldLayout.PLOT_D / 2
end

-- Parcelle `index` (1..count) : centre (x, z) par rapport au centre de la ville,
-- et angle (radians) de sa direction depuis le centre
function WorldLayout.PlotPlace(index: number, count: number): (number, number, number)
	local radius = WorldLayout.PlotRadius(count)
	local angle = WorldLayout.SlotAngle(index, count)
	local x, z = math.sin(angle) * radius, math.cos(angle) * radius
	return x, z, angle
end

-- Distance du centre au bord avant (côté rue) des parcelles
function WorldLayout.PlotFrontRadius(count: number): number
	return WorldLayout.PlotRadius(count) - WorldLayout.PLOT_D / 2
end

-- Axe du boulevard (distance du centre à l'axe de chaque côté droit du
-- polygone, devant les parcelles : trottoir extérieur collé aux parcelles)
function WorldLayout.RingRoadRadius(count: number): number
	return WorldLayout.PlotFrontRadius(count) - WorldLayout.WALK_W - WorldLayout.ROAD_W / 2
end

-- Bord intérieur du boulevard (trottoir intérieur compris)
function WorldLayout.RingInnerRadius(count: number): number
	return WorldLayout.RingRoadRadius(count) - WorldLayout.ROAD_W / 2 - WorldLayout.WALK_W
end

-- Distance du centre à la porte de la ville (sur l'axe +Z)
function WorldLayout.GateDistance(count: number): number
	return WorldLayout.PlotFrontRadius(count) + WorldLayout.GATE_BACK
end

-- Rayon des murs invisibles (bord du pré)
function WorldLayout.TownRadius(count: number): number
	return WorldLayout.PlotRadius(count) + WorldLayout.PLOT_D / 2 + WorldLayout.TOWN_MARGIN
end

-- Distance (le long de la direction "vers la place") entre le centre de la
-- parcelle et la façade de la maison
function WorldLayout.HouseFrontOffset(): number
	return WorldLayout.PLOT_D / 2 - WorldLayout.GARDEN_D
end

----------------------------------------------------------------------
-- Repères Roblox (CFrame) : utilisés en jeu uniquement (pas dans les tests)
----------------------------------------------------------------------

-- Centre de la ville (loin de la Baseplate du lieu)
WorldLayout.ORIGIN_X, WorldLayout.ORIGIN_Y, WorldLayout.ORIGIN_Z = 0, 60, 2600

function WorldLayout.Origin(): Vector3
	return Vector3.new(WorldLayout.ORIGIN_X, WorldLayout.ORIGIN_Y, WorldLayout.ORIGIN_Z)
end

-- Parcelle : centre au niveau du sol, LookVector = vers la place
function WorldLayout.PlotCFrame(index: number, count: number): CFrame
	local x, z = WorldLayout.PlotPlace(index, count)
	local center = WorldLayout.Origin() + Vector3.new(x, 0, z)
	return CFrame.lookAt(center, center - Vector3.new(x, 0, z))
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

-- (v9.8, FAIR98) 🎡 FÊTE FORAINE : derrière la mairie, dans le secteur
-- arrière de l'anneau (axe -Z), rectangle FAIR_W x FAIR_D dont le bord
-- avant est à FAIR_NEAR studs du centre. Tient de 4 à 12 parcelles (bord
-- du boulevard, lac, jardin, terrain de basket : vérifié). Repère : centre
-- du sol de la fête (FairRides.GROUND au-dessus du pré), LookVector vers
-- la place (l'entrée) ; x local ∈ [-FAIR_W/2, FAIR_W/2], z ∈ [-FAIR_D/2, FAIR_D/2].
WorldLayout.FAIR_W = 110
WorldLayout.FAIR_D = 76
WorldLayout.FAIR_NEAR = 100
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
