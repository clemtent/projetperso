--[[
	HouseCommon (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseCommon

	Outils partagés de "🏠 Ma maison" côté client :
	  - accès typé à Config.House (tailles, papiers peints, sols, objets) ;
	  - lecture de ClientState.Data.House (avec valeurs par défaut) : la
	    maison est une grille de pièces (Rooms), chacune avec son type, son
	    emplacement (Slot), son papier peint, son sol et ses objets ;
	  - prix (Formulas.GetHouseItemPrice), exemplaires possédés / posés,
	    confort et bonus (mêmes formules que le serveur) ;
	  - bornes des zones "Wall" (haut) / "Floor" (bas) de la pièce ;
	  - appel du serveur : Net.Function("House"):InvokeServer(action, arg)
	    protégé par pcall ;
	  - palette kawaii (roses, lilas, menthe) utilisée par tous les modules
	    de la maison.
	Aucune interface ici (utilisé aussi par la colonne centrale pour son badge).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)

export type Item = {
	Id: string,
	Name: string,
	Icon: string,
	Category: string,
	Placement: string, -- "Floor" | "Wall"
	Size: number,
	Cost: number,
	CostGrowth: number,
	Comfort: number,
	MaxOwned: number?,
	Order: number?,
}

export type SizeDef = {
	Id: string,
	Name: string,
	Icon: string,
	Cost: number,
	Floors: number, -- étages
	Columns: number, -- pièces par étage
	MaxRooms: number, -- Floors x Columns
	Width: number, -- largeur relative d'une pièce
	RoomItems: number, -- objets posés max par pièce
	Exterior: string, -- "Cottage" | "Townhouse" | "Loft" | "Mansion"
	Order: number?,
}

export type RoomTypeDef = {
	Id: string,
	Name: string,
	Icon: string,
	Wallpaper: string,
	Floor: string,
	Categories: { string },
	Items: { string },
	FavoriteCategories: { [string]: boolean },
	FavoriteItems: { [string]: boolean },
	Order: number?,
}

export type Style = {
	Id: string,
	Name: string,
	Icon: string?,
	Cost: number,
	Pattern: string,
	A: Color3,
	B: Color3,
	Order: number?,
}

export type Category = { Id: string, Name: string, Icon: string, Order: number? }

-- Un objet posé (format du serveur)
export type Placed = { I: string, X: number, Y: number, S: number, Z: number }

-- Une pièce (format du serveur) ; Slot = (étage - 1) x Columns + colonne,
-- étage 1 = rez-de-chaussée
export type Room = {
	Id: string,
	Type: string,
	Slot: number,
	Wallpaper: string,
	Floor: string,
	Placed: { Placed },
}

export type HouseData = {
	Size: string,
	OwnedSizes: { [string]: boolean },
	OwnedWallpapers: { [string]: boolean },
	OwnedFloors: { [string]: boolean },
	Items: { [string]: number },
	Rooms: { Room },
}

export type HouseConfig = {
	ComfortBonusPerPoint: number,
	MaxComfortBonus: number,
	WallRatio: number,
	RoomCost: number,
	RoomCostGrowth: number,
	HarmonyBonus: number,
	Sizes: { SizeDef },
	RoomTypes: { RoomTypeDef },
	Wallpapers: { Style },
	Floors: { Style },
	Categories: { Category },
	Items: { Item },
}

local HouseCommon = {}

-- Config typée (le tableau de Config.luau mélange des objets avec / sans MaxOwned)
local rawConfig = (Config :: any).House
local EMPTY_CONFIG: HouseConfig = {
	ComfortBonusPerPoint = 0,
	MaxComfortBonus = 0,
	WallRatio = 0.46,
	RoomCost = 0,
	RoomCostGrowth = 1,
	HarmonyBonus = 0,
	Sizes = {
		{ Id = "Studio", Name = "Cozy studio", Icon = "🏠", Cost = 0, Floors = 1, Columns = 1, MaxRooms = 1, Width = 1,
			RoomItems = 25, Exterior = "Cottage" },
	},
	RoomTypes = {},
	Wallpapers = {},
	Floors = {},
	Categories = {},
	Items = {},
}
HouseCommon.Config = (type(rawConfig) == "table" and rawConfig or EMPTY_CONFIG) :: HouseConfig

HouseCommon.ItemsById = ((Config :: any).HouseItemsById or {}) :: { [string]: Item }
HouseCommon.SizesById = ((Config :: any).HouseSizesById or {}) :: { [string]: SizeDef }
HouseCommon.WallpapersById = ((Config :: any).HouseWallpapersById or {}) :: { [string]: Style }
HouseCommon.FloorsById = ((Config :: any).HouseFloorsById or {}) :: { [string]: Style }
HouseCommon.CategoriesById = ((Config :: any).HouseCategoriesById or {}) :: { [string]: Category }
HouseCommon.RoomTypesById = ((Config :: any).HouseRoomTypesById or {}) :: { [string]: RoomTypeDef }

-- Échelle des objets posés (bornes du serveur) et pas des boutons ➕ / ➖
HouseCommon.MIN_SCALE = 0.6
HouseCommon.MAX_SCALE = 1.6
HouseCommon.SCALE_STEP = 0.1
-- Couche de départ d'un objet posé (Z) : de la place pour "reculer" (0..999)
HouseCommon.DEFAULT_Z = 100
HouseCommon.MAX_Z = 999

-- Palette kawaii
HouseCommon.Colors = {
	Pink = Color3.fromRGB(255, 126, 182),
	PinkDeep = Color3.fromRGB(236, 72, 140),
	PinkSoft = Color3.fromRGB(255, 214, 232),
	PinkMist = Color3.fromRGB(255, 240, 247),
	Lilac = Color3.fromRGB(183, 148, 246),
	LilacSoft = Color3.fromRGB(236, 224, 255),
	Mint = Color3.fromRGB(110, 214, 176),
	MintSoft = Color3.fromRGB(214, 247, 234),
	Cream = Color3.fromRGB(255, 247, 236),
	Peach = Color3.fromRGB(255, 190, 160),
	Sky = Color3.fromRGB(150, 205, 255),
	Butter = Color3.fromRGB(255, 226, 130),
	Heart = Color3.fromRGB(255, 79, 139),
	Wood = Color3.fromRGB(214, 164, 120),
	WoodDark = Color3.fromRGB(160, 110, 78),
	Ink = Color3.fromRGB(92, 58, 96), -- texte "chocolat-prune" sur fond pastel
}

-- Fond pastel de la vignette d'un objet, selon sa catégorie
local CATEGORY_TINTS: { [string]: Color3 } = {
	Furniture = Color3.fromRGB(255, 228, 206),
	Decor = Color3.fromRGB(255, 222, 238),
	Toys = Color3.fromRGB(255, 240, 200),
	Plants = Color3.fromRGB(216, 245, 222),
	Electronics = Color3.fromRGB(214, 232, 255),
	Kitchen = Color3.fromRGB(255, 226, 222),
	Doors = Color3.fromRGB(236, 224, 210),
	Windows = Color3.fromRGB(214, 240, 255),
	Lights = Color3.fromRGB(255, 244, 196),
	Pets = Color3.fromRGB(255, 232, 214),
}

function HouseCommon.CategoryTint(categoryId: string): Color3
	return CATEGORY_TINTS[categoryId] or HouseCommon.Colors.PinkSoft
end

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

local function mapOf(value): { [string]: any }
	if type(value) == "table" then
		return value
	end
	return {}
end

local function readPlaced(list: any): { Placed }
	local placed = {}
	if type(list) == "table" then
		for _, entry in ipairs(list) do
			if type(entry) == "table" and type(entry.I) == "string" then
				table.insert(placed, {
					I = entry.I,
					X = tonumber(entry.X) or 0.5,
					Y = tonumber(entry.Y) or 0.8,
					S = tonumber(entry.S) or 1,
					Z = tonumber(entry.Z) or 0,
				})
			end
		end
	end
	return placed
end

-- Maison du joueur (jamais nil : valeurs par défaut avant le premier état ;
-- une ancienne maison à une seule pièce devient un salon)
function HouseCommon.GetHouse(data: any): HouseData
	local house = type(data) == "table" and data.House or nil
	local config = HouseCommon.Config
	local firstSize = config.Sizes[1]
	local firstWallpaper = config.Wallpapers[1]
	local firstFloor = config.Floors[1]
	local firstType = config.RoomTypes[1]
	if type(house) ~= "table" then
		house = {}
	end
	local rooms: { Room } = {}
	local ok, rawRooms = pcall(Formulas.GetHouseRooms, house)
	if ok and type(rawRooms) == "table" then
		for index, raw in ipairs(rawRooms) do
			if type(raw) == "table" then
				table.insert(rooms, {
					Id = type(raw.Id) == "string" and raw.Id or ("R" .. index),
					Type = type(raw.Type) == "string" and raw.Type or (firstType and firstType.Id or "Living"),
					Slot = tonumber(raw.Slot) or index,
					Wallpaper = type(raw.Wallpaper) == "string" and raw.Wallpaper
						or (type(house.Wallpaper) == "string" and house.Wallpaper)
						or (firstWallpaper and firstWallpaper.Id or ""),
					Floor = type(raw.Floor) == "string" and raw.Floor
						or (type(house.Floor) == "string" and house.Floor)
						or (firstFloor and firstFloor.Id or ""),
					Placed = readPlaced(raw.Placed),
				})
			end
		end
	end
	if #rooms == 0 then
		table.insert(rooms, {
			Id = "R1",
			Type = firstType and firstType.Id or "Living",
			Slot = 1,
			Wallpaper = firstWallpaper and firstWallpaper.Id or "",
			Floor = firstFloor and firstFloor.Id or "",
			Placed = {},
		})
	end
	return {
		Size = type(house.Size) == "string" and house.Size or (firstSize and firstSize.Id or "Studio"),
		OwnedSizes = mapOf(house.OwnedSizes),
		OwnedWallpapers = mapOf(house.OwnedWallpapers),
		OwnedFloors = mapOf(house.OwnedFloors),
		Items = mapOf(house.Items),
		Rooms = rooms,
	}
end

function HouseCommon.GetSize(house: HouseData): SizeDef
	return HouseCommon.SizesById[house.Size] or HouseCommon.Config.Sizes[1]
end

-- Pièce par Id (nil si elle n'existe pas)
function HouseCommon.GetRoom(house: HouseData, roomId: string?): Room?
	for _, room in ipairs(house.Rooms) do
		if room.Id == roomId then
			return room
		end
	end
	return nil
end

-- Pièce à un emplacement de la grille (nil si vide)
function HouseCommon.RoomAtSlot(house: HouseData, slot: number): Room?
	for _, room in ipairs(house.Rooms) do
		if room.Slot == slot then
			return room
		end
	end
	return nil
end

-- Emplacement -> (étage, colonne) ; étage 1 = rez-de-chaussée
function HouseCommon.SlotCell(size: SizeDef, slot: number): (number, number)
	return math.floor((slot - 1) / size.Columns) + 1, (slot - 1) % size.Columns + 1
end

function HouseCommon.CellSlot(size: SizeDef, floor: number, column: number): number
	return (floor - 1) * size.Columns + column
end

function HouseCommon.GetRoomType(room: Room?): RoomTypeDef
	local roomType = room and HouseCommon.RoomTypesById[room.Type]
	return roomType or HouseCommon.Config.RoomTypes[1]
end

function HouseCommon.GetRoomWallpaper(room: Room?): Style?
	return (room and HouseCommon.WallpapersById[room.Wallpaper]) or HouseCommon.Config.Wallpapers[1]
end

function HouseCommon.GetRoomFloor(room: Room?): Style?
	return (room and HouseCommon.FloorsById[room.Floor]) or HouseCommon.Config.Floors[1]
end

-- Vrai si l'objet est un "préféré" de la pièce (bonus d'harmonie)
function HouseCommon.IsFavorite(room: Room?, item: Item): boolean
	local ok, value = pcall(Formulas.IsRoomFavorite, HouseCommon.GetRoomType(room), item)
	return ok and value == true
end

-- Confort d'un objet dans une pièce (harmonie comprise)
function HouseCommon.PlacedComfort(room: Room?, item: Item): number
	local ok, value = pcall(Formulas.GetPlacedComfort, HouseCommon.GetRoomType(room), item)
	if ok and type(value) == "number" then
		return value
	end
	return item.Comfort
end

-- Prix de la prochaine pièce
function HouseCommon.RoomCost(house: HouseData): number
	local ok, value = pcall(Formulas.GetRoomCost, #house.Rooms)
	if ok and type(value) == "number" then
		return value
	end
	return math.huge
end

-- Anciennes fonctions (1re pièce) : pour le code qui ne connaît qu'une pièce
function HouseCommon.GetWallpaper(house: HouseData): Style?
	return HouseCommon.GetRoomWallpaper(house.Rooms[1])
end

function HouseCommon.GetFloor(house: HouseData): Style?
	return HouseCommon.GetRoomFloor(house.Rooms[1])
end

-- Exemplaires possédés d'un objet
function HouseCommon.Owned(house: HouseData, itemId: string): number
	return math.max(0, math.floor(tonumber(house.Items[itemId]) or 0))
end

-- Exemplaires posés d'un objet dans une disposition
function HouseCommon.PlacedCount(placed: { Placed }, itemId: string): number
	local count = 0
	for _, entry in ipairs(placed) do
		if entry.I == itemId then
			count += 1
		end
	end
	return count
end

-- Prix du prochain exemplaire
function HouseCommon.Price(item: Item, owned: number): number
	return Formulas.GetHouseItemPrice(item, owned)
end

-- Vrai si on ne peut plus en acheter (MaxOwned atteint)
function HouseCommon.IsMaxed(item: Item, owned: number): boolean
	return item.MaxOwned ~= nil and owned >= (item.MaxOwned :: number)
end

-- Dopamine sûre (sans l'extrapolation des gains passifs)
function HouseCommon.Dopamine(): number
	local ok, value = pcall(ClientState.GetConfirmedDopamine)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

-- Dispositions "en cours" : { [roomId] = objets posés } remplace celles du serveur
export type Overrides = { [string]: { Placed } }

local function layoutOf(room: Room, overrides: Overrides?): { Placed }
	return (overrides and overrides[room.Id]) or room.Placed
end

-- Exemplaires d'un objet posés dans TOUTES les pièces
function HouseCommon.PlacedTotal(house: HouseData, itemId: string, overrides: Overrides?): number
	local count = 0
	for _, room in ipairs(house.Rooms) do
		count += HouseCommon.PlacedCount(layoutOf(room, overrides), itemId)
	end
	return count
end

-- Exemplaires encore rangés (possédés - posés partout)
function HouseCommon.Available(house: HouseData, itemId: string, overrides: Overrides?): number
	return math.max(0, HouseCommon.Owned(house, itemId) - HouseCommon.PlacedTotal(house, itemId, overrides))
end

-- Confort total de la maison (même calcul que le serveur : objets possédés,
-- RoomItems par pièce, harmonie), avec des dispositions en cours éventuelles
function HouseCommon.Comfort(house: HouseData, overrides: Overrides?): number
	local rooms = {}
	for _, room in ipairs(house.Rooms) do
		table.insert(rooms, { Id = room.Id, Type = room.Type, Slot = room.Slot, Placed = layoutOf(room, overrides) })
	end
	local ok, value = pcall(Formulas.GetHouseComfort, {
		House = { Size = house.Size, Items = house.Items, Rooms = rooms },
	})
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

-- Confort d'une seule pièce (sans tenir compte des autres pièces)
function HouseCommon.RoomComfort(house: HouseData, room: Room, placed: { Placed }?): number
	local ok, value = pcall(Formulas.GetHouseComfort, {
		House = {
			Size = house.Size,
			Items = house.Items,
			Rooms = { { Id = room.Id, Type = room.Type, Slot = 1, Placed = placed or room.Placed } },
		},
	})
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

-- Bonus en % sur tous les gains (ex. 17 pour +17 %)
function HouseCommon.BonusPercent(comfort: number): number
	local ok, multiplier = pcall(Formulas.GetHouseBonus, comfort)
	if ok and type(multiplier) == "number" then
		return math.max(0, (multiplier - 1) * 100)
	end
	return 0
end

-- "17" / "2.5" : pourcentage lisible
function HouseCommon.FormatPercent(value: number): string
	if value >= 10 or math.abs(value - math.floor(value)) < 0.05 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%.1f", value)
end

-- Objets jamais achetés qu'on peut se payer maintenant (badges)
function HouseCommon.AffordableNew(data: any, dopamine: number): { string }
	local result = {}
	if type(data) ~= "table" then
		return result
	end
	local house = HouseCommon.GetHouse(data)
	for _, item in ipairs(HouseCommon.Config.Items) do
		if HouseCommon.Owned(house, item.Id) == 0 and dopamine >= HouseCommon.Price(item, 0) then
			table.insert(result, item.Id)
		end
	end
	return result
end

-- Nom traduit d'un objet / d'une entrée de config
function HouseCommon.Name(entry: { Name: string }): string
	return Locale.T(entry.Name)
end

----------------------------------------------------------------------
-- Zones de la pièce
----------------------------------------------------------------------

-- Bornes (Y) de la zone d'un objet : "Wall" = haut, "Floor" = bas
-- (un peu plus serrées que celles du serveur : l'objet reste bien dans sa zone)
function HouseCommon.ZoneBounds(placement: string): (number, number)
	local ratio = HouseCommon.Config.WallRatio
	if placement == "Wall" then
		return 0.1, ratio - 0.03
	end
	return ratio + 0.035, 0.985
end

-- Position corrigée d'un objet : dans sa zone, sans sortir de la pièce.
-- `roomWidth` / `roomHeight` : taille de la pièce en px de maquette.
function HouseCommon.ClampPosition(item: Item, x: number, y: number, scale: number, roomWidth: number, roomHeight: number): (number, number)
	local half = (item.Size * scale * 0.38) / math.max(1, roomWidth)
	half = math.clamp(half, 0.015, 0.2)
	local minY, maxY = HouseCommon.ZoneBounds(item.Placement)
	local ratio = HouseCommon.Config.WallRatio
	local sizeY = (item.Size * scale) / math.max(1, roomHeight)
	if item.Placement == "Wall" then
		-- Objet centré sur Y : il reste (presque) entier sur le mur, sans
		-- passer sous le plafond ni trop descendre sur le sol
		local halfY = sizeY * 0.4
		minY = math.max(minY, halfY + 0.02)
		maxY = math.max(0.1, math.min(maxY, ratio - halfY * 0.7))
		if minY > maxY then
			-- Objet plus haut que le mur : centré sur le mur
			minY = math.min(maxY, ratio / 2 + 0.02)
			maxY = minY
		end
	else
		-- Objet posé par ses pieds : sa tête ne traverse pas le plafond
		minY = math.min(maxY, math.max(minY, sizeY * 0.92 - 0.02))
	end
	return math.clamp(x, half, 1 - half), math.clamp(y, minY, maxY)
end

----------------------------------------------------------------------
-- Serveur
----------------------------------------------------------------------

-- Appel protégé : (succès, message?)
function HouseCommon.Invoke(action: string, argument: any): (boolean, string?)
	local ok, success, message = pcall(function()
		return Net.Function("House"):InvokeServer(action, argument)
	end)
	if not ok then
		return false, Locale.T("Network error, try again.")
	end
	return success == true, message ~= nil and tostring(message) or nil
end

-- Petit hachage déterministe d'un texte (détails "aléatoires" mais stables)
function HouseCommon.Hash(text: string): number
	local hash = 5381
	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % 2147483647
	end
	return hash
end

return HouseCommon
