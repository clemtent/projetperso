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
	Colonnes de la maison : [cage d'escalier (HALL_W)] [pièce 1] [pièce 2]...
	étage 1 = rez-de-chaussée (comme HouseCommon.SlotCell).
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
WorldLayout.DEPTH = 20 -- profondeur INTÉRIEURE d'une pièce
WorldLayout.WALL_H = 12 -- hauteur sous plafond
WorldLayout.SLAB = 1 -- épaisseur d'un plancher (le rez-de-chaussée est surélevé d'autant)
WorldLayout.STORY = 13 -- WALL_H + SLAB
WorldLayout.HALL_W = 12 -- cage d'escalier (à gauche de la maison)
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

-- Porte d'entrée (dans la cage d'escalier) et passages entre pièces
WorldLayout.DOOR_W = 5
WorldLayout.DOOR_H = 8
WorldLayout.PASS_W = 5 -- passage entre deux pièces / cage -> pièce (centré en profondeur)
WorldLayout.PASS_H = 8.5

-- Escalier (dans la cage) : volée k (étage k -> k+1), bande de gauche de la
-- cage, de la profondeur STAIR_D0 (bas) à STAIR_D1 (haut) ; trémie dans le
-- plancher du dessus entre STAIR_HOLE_D0 et STAIR_D1
WorldLayout.STAIR_W = 5
WorldLayout.STAIR_D0 = 3
WorldLayout.STAIR_D1 = 17
WorldLayout.STAIR_HOLE_D0 = 7.5

export type SizeDef = { Floors: number, Columns: number, Width: number? }

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
		Height = floors * WorldLayout.STORY,
		Left = -width / 2,
	}
end

-- Emplacement -> (étage, colonne) ; même règle que HouseCommon.SlotCell
function WorldLayout.SlotCell(size: SizeDef?, slot: number): (number, number)
	local _, columns = sizeOf(size)
	local s = math.max(1, math.floor(finite(slot, 1)))
	return math.floor((s - 1) / columns) + 1, (s - 1) % columns + 1
end

-- Hauteur (y) du DESSUS du plancher de l'étage `floor`
function WorldLayout.FloorY(floor: number): number
	return (math.max(1, floor) - 1) * WorldLayout.STORY + WorldLayout.SLAB
end

-- Bords extérieurs (x gauche, x droite) d'une colonne de pièces (murs compris)
function WorldLayout.ColumnSpan(size: SizeDef?, column: number): (number, number)
	local dims = WorldLayout.Dims(size)
	local x0 = dims.Left + WorldLayout.HALL_W + (column - 1) * dims.Pitch
	return x0, x0 + dims.Pitch
end

-- Bords de la cage d'escalier
function WorldLayout.HallSpan(size: SizeDef?): (number, number)
	local dims = WorldLayout.Dims(size)
	return dims.Left, dims.Left + WorldLayout.HALL_W
end

-- x du milieu de la porte d'entrée (couloir de la cage, à droite de l'escalier)
function WorldLayout.DoorX(size: SizeDef?): number
	local x0 = WorldLayout.HallSpan(size)
	return x0 + WorldLayout.STAIR_W + (WorldLayout.HALL_W - WorldLayout.STAIR_W) / 2
end

-- Intérieur d'une pièce (repère local) : xMin, xMax, yFloor, dMin, dMax
function WorldLayout.RoomInterior(size: SizeDef?, slot: number): (number, number, number, number, number)
	local floor, column = WorldLayout.SlotCell(size, slot)
	local x0, x1 = WorldLayout.ColumnSpan(size, column)
	local t = WorldLayout.WALL_T
	return x0 + t, x1 - t, WorldLayout.FloorY(floor), t, t + WorldLayout.DEPTH
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

-- Objet au sol : (X, Y) -> (x, z du centre) ; `fw` / `fd` = empreinte
function WorldLayout.FloorForward(dims: RoomDims, X: number, Y: number, fw: number, fd: number): (number, number)
	local t = depthT(dims, finite(Y, 0.8))
	local limit = math.max(0, dims.W / 2 - fw / 2 - 0.1)
	local x = math.clamp(mapX(dims, finite(X, 0.5), t), -limit, limit)
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

-- Rayon du centre des parcelles : les coins avant de deux parcelles voisines
-- ne se touchent jamais
function WorldLayout.PlotRadius(count: number): number
	local n = math.max(3, count)
	local front = (WorldLayout.PLOT_W / 2 + 6) / math.tan(math.pi / n)
	return math.max(front, WorldLayout.PLAZA_R + 150) + WorldLayout.PLOT_D / 2
end

-- Parcelle `index` (1..count) : centre (x, z) par rapport au centre de la ville,
-- et angle (radians) de sa direction depuis le centre
function WorldLayout.PlotPlace(index: number, count: number): (number, number, number)
	local radius = WorldLayout.PlotRadius(count)
	local angle = (index - 1) / count * math.pi * 2
	local x, z = math.sin(angle) * radius, math.cos(angle) * radius
	return x, z, angle
end

-- Rayon de la route circulaire (devant les parcelles)
function WorldLayout.RingRoadRadius(count: number): number
	return WorldLayout.PlotRadius(count) - WorldLayout.PLOT_D / 2 - 9
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
	local floor = math.floor((y - WorldLayout.SLAB + 0.5) / WorldLayout.STORY) + 1
	if floor < 1 or floor > dims.Floors then
		return nil
	end
	local rel = x - dims.Left - WorldLayout.HALL_W
	if rel < 0 or rel > dims.Columns * dims.Pitch then
		return nil
	end
	local column = math.clamp(math.floor(rel / dims.Pitch) + 1, 1, dims.Columns)
	return (floor - 1) * dims.Columns + column
end

return WorldLayout
