--[[
	WorldLayout (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > WorldLayout

	🚶 Dopamine Town : géométrie PARTAGÉE serveur + client (+ tests), sans
	aucun service Roblox. Le serveur s'en sert pour placer les parcelles, faire
	apparaître les personnages devant les portes et vérifier les sièges / les
	intrus ; le client pour construire les maisons au même endroit et pour
	convertir les déplacements de meubles 3D <-> positions 2D (X / Y de
	HouseCommon.Placed). Une seule source de vérité : la 2D.

	Repère d'une maison ("local") : x vers la DROITE d'un visiteur qui regarde
	la façade depuis la place, y vers le haut (0 = sol de la parcelle),
	d = profondeur depuis la façade (0 = mur de devant, D = mur du fond).
	Colonnes de la maison : [cage d'escalier (HallWidth)] [pièce 1] [pièce 2]...
	étage 1 = rez-de-chaussée (comme HouseCommon.SlotCell).

	Correspondance 2D -> 3D d'une pièce (HouseRoom : X 0..1 de gauche à droite,
	Y 0..1 de haut en bas, WallRatio = limite mur / sol) :
	  - objet au sol : X -> x (linéaire, marges), Y (WallRatio..1) -> d
	    (Y = WallRatio : contre le mur du fond, Y = 1 : devant), courbe douce
	    (DepthCurve) comme l'aperçu 3D ; inverse exact (LocalToFloor) ;
	  - objet au mur : X -> x, Y (0..WallRatio) -> hauteur du CENTRE sur le mur
	    du fond (Y = 0 : plafond) ; inverse exact (LocalToWall).
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
WorldLayout.DEPTH = 20 -- profondeur d'une pièce
WorldLayout.WALL_H = 12 -- hauteur sous plafond
WorldLayout.SLAB = 1 -- épaisseur d'un plancher (le rez-de-chaussée est surélevé d'autant)
WorldLayout.STORY = 13 -- WALL_H + SLAB
WorldLayout.HALL_W = 12 -- cage d'escalier (à gauche de la maison)
WorldLayout.WALL_T = 0.8 -- épaisseur des murs
WorldLayout.MARGIN = 0.6 -- marge entre un objet posé et un mur
WorldLayout.DEPTH_CURVE = 1.35
WorldLayout.WALL_RATIO = 0.46 -- (valeur par défaut : Config.House.WallRatio)
WorldLayout.ROOF_H = 9

-- Parcelles
WorldLayout.PLOT_W = 162 -- largeur (le manoir 3 x 4 tient dedans)
WorldLayout.PLOT_D = 84 -- profondeur
WorldLayout.GARDEN_D = 30 -- jardin entre la rue et la façade
WorldLayout.MIN_PLOTS = 4
WorldLayout.MAX_PLOTS = 12
WorldLayout.PLAZA_R = 64 -- rayon de la place centrale
WorldLayout.SPAWN_FRONT = 7 -- (studs) apparition devant la porte

-- Porte d'entrée (dans la cage d'escalier) et passages entre pièces
WorldLayout.DOOR_W = 5
WorldLayout.DOOR_H = 8
WorldLayout.PASS_W = 5 -- passage entre deux pièces / cage -> pièce
WorldLayout.PASS_H = 8.5
WorldLayout.PASS_D = 10 -- profondeur du centre des passages

-- Escalier (dans la cage) : volée k (étage k -> k+1), bande de gauche
WorldLayout.STAIR_W = 5
WorldLayout.STAIR_D0 = 2 -- première marche (profondeur)
WorldLayout.STAIR_D1 = 16 -- arrivée (profondeur)
WorldLayout.STAIR_HOLE_D0 = 6.5 -- trémie dans le plancher du dessus (hauteur de tête)

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

-- Largeur (studs) d'une pièce pour une taille de maison
function WorldLayout.RoomWidth(size: SizeDef?): number
	local _, _, width = sizeOf(size)
	return WorldLayout.ROOM_BASE_PX * width * WorldLayout.PX
end

-- Largeur 2D (px de maquette) d'une pièce (pour HouseSurfaces)
function WorldLayout.RoomWidthPx(size: SizeDef?): number
	local _, _, width = sizeOf(size)
	return math.floor(WorldLayout.ROOM_BASE_PX * width + 0.5)
end

export type Dims = {
	Floors: number,
	Columns: number,
	RoomW: number,
	Width: number, -- largeur totale (cage + pièces)
	Depth: number,
	Height: number, -- jusqu'au plafond du dernier étage
	Left: number, -- x du bord gauche (murs centrés sur les lignes)
}

function WorldLayout.Dims(size: SizeDef?): Dims
	local floors, columns = sizeOf(size)
	local roomW = WorldLayout.RoomWidth(size)
	local width = WorldLayout.HALL_W + columns * roomW
	return {
		Floors = floors,
		Columns = columns,
		RoomW = roomW,
		Width = width,
		Depth = WorldLayout.DEPTH,
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

-- Bords (x gauche, x droite) d'une colonne de pièces (lignes des murs)
function WorldLayout.ColumnSpan(size: SizeDef?, column: number): (number, number)
	local dims = WorldLayout.Dims(size)
	local x0 = dims.Left + WorldLayout.HALL_W + (column - 1) * dims.RoomW
	return x0, x0 + dims.RoomW
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

-- Boîte intérieure d'une pièce (repère local) : xMin, xMax, yFloor, dMin, dMax
function WorldLayout.RoomInterior(size: SizeDef?, slot: number): (number, number, number, number, number)
	local floor, column = WorldLayout.SlotCell(size, slot)
	local x0, x1 = WorldLayout.ColumnSpan(size, column)
	local t = WorldLayout.WALL_T / 2
	return x0 + t, x1 - t, WorldLayout.FloorY(floor), t, WorldLayout.DEPTH - t
end

----------------------------------------------------------------------
-- 2D <-> 3D (repère local de la maison)
----------------------------------------------------------------------

local function wallRatioOf(ratio: number?): number
	return math.clamp(finite(ratio, WorldLayout.WALL_RATIO), 0.1, 0.9)
end

-- Objet au sol : (X, Y) 2D -> (x, d) local, dans la pièce `slot`
function WorldLayout.FloorToLocal(size: SizeDef?, slot: number, X: number, Y: number, wallRatio: number?): (number, number)
	local ratio = wallRatioOf(wallRatio)
	local xMin, xMax, _, dMin, dMax = WorldLayout.RoomInterior(size, slot)
	local m = WorldLayout.MARGIN
	local x = xMin + m + math.clamp(finite(X, 0.5), 0, 1) * (xMax - xMin - 2 * m)
	local t = math.clamp((finite(Y, 0.8) - ratio) / (1 - ratio), 0, 1)
	local fromBack = t ^ WorldLayout.DEPTH_CURVE
	local d = (dMax - m) - fromBack * ((dMax - m) - (dMin + m))
	return x, d
end

-- Inverse : (x, d) local -> (X, Y) 2D (bornés à la pièce)
function WorldLayout.LocalToFloor(size: SizeDef?, slot: number, x: number, d: number, wallRatio: number?): (number, number)
	local ratio = wallRatioOf(wallRatio)
	local xMin, xMax, _, dMin, dMax = WorldLayout.RoomInterior(size, slot)
	local m = WorldLayout.MARGIN
	local X = math.clamp((finite(x, 0) - (xMin + m)) / math.max(0.01, xMax - xMin - 2 * m), 0, 1)
	local span = math.max(0.01, (dMax - m) - (dMin + m))
	local fromBack = math.clamp(((dMax - m) - finite(d, 0)) / span, 0, 1)
	local t = fromBack ^ (1 / WorldLayout.DEPTH_CURVE)
	return X, ratio + t * (1 - ratio)
end

-- Objet au mur (mur du fond) : (X, Y) 2D -> (x, y du centre) local
function WorldLayout.WallToLocal(size: SizeDef?, slot: number, X: number, Y: number, wallRatio: number?): (number, number)
	local ratio = wallRatioOf(wallRatio)
	local xMin, xMax, yFloor = WorldLayout.RoomInterior(size, slot)
	local m = WorldLayout.MARGIN
	local x = xMin + m + math.clamp(finite(X, 0.5), 0, 1) * (xMax - xMin - 2 * m)
	local h = (1 - math.clamp(finite(Y, ratio / 2), 0, ratio) / ratio) * WorldLayout.WALL_H
	return x, yFloor + h
end

function WorldLayout.LocalToWall(size: SizeDef?, slot: number, x: number, y: number, wallRatio: number?): (number, number)
	local ratio = wallRatioOf(wallRatio)
	local xMin, xMax, yFloor = WorldLayout.RoomInterior(size, slot)
	local m = WorldLayout.MARGIN
	local X = math.clamp((finite(x, 0) - (xMin + m)) / math.max(0.01, xMax - xMin - 2 * m), 0, 1)
	local h = math.clamp(finite(y, 0) - yFloor, 0, WorldLayout.WALL_H)
	return X, ratio * (1 - h / WorldLayout.WALL_H)
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
-- et angle (radians) de la direction "vers la place" (LookVector)
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
	local toPlaza = WorldLayout.Origin() - center
	return CFrame.lookAt(center, center + Vector3.new(toPlaza.X, 0, toPlaza.Z))
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

-- Données "Town" d'un joueur, réparées (sauvegardes abîmées, anciennes)
function WorldLayout.SanitizeTown(raw: any, now: number): TownData
	local town = type(raw) == "table" and raw or {}
	local day = WorldLayout.DayNumber(now)
	local likeDay = math.floor(finite(town.LikeDay, 0))
	local liked: { [string]: boolean } = {}
	local given = math.max(0, math.floor(finite(town.LikesGiven, 0)))
	if likeDay == day and type(town.Liked) == "table" then
		local count = 0
		for key, value in pairs(town.Liked) do
			if type(key) == "string" and #key <= 20 and value == true and count < 200 then
				liked[key] = true
				count += 1
			end
		end
	else
		given = 0
	end
	local rewardDay = math.floor(finite(town.RewardDay, 0))
	local rewards = math.max(0, math.floor(finite(town.LikedRewards, 0)))
	if rewardDay ~= day then
		rewards = 0
	end
	return {
		Open = WorldLayout.NormalizeOpen(town.Open),
		Likes = math.clamp(math.floor(finite(town.Likes, 0)), 0, 1e9),
		Visits = math.clamp(math.floor(finite(town.Visits, 0)), 0, 1e9),
		LikeDay = day,
		Liked = liked,
		LikesGiven = if likeDay == day then given else 0,
		LikedRewards = rewards,
		RewardDay = day,
	}
end

-- Un "j'aime" de `liker` pour la maison de `ownerId` est-il permis ?
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

-- Point (repère local de la maison) dans la maison ? (marge en studs)
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
	if rel < 0 or rel > dims.Columns * dims.RoomW then
		return nil
	end
	local column = math.clamp(math.floor(rel / dims.RoomW) + 1, 1, dims.Columns)
	return (floor - 1) * dims.Columns + column
end

return WorldLayout
