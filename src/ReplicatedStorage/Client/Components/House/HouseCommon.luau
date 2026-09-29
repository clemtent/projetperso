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
	  - bornes des zones "Wall" (haut) / "Floor" (bas) de la pièce, et
	    règle "peut être posé SUR un meuble" (CanGoOnFurniture, même règle
	    que le serveur : Formulas.CanGoOnFurniture) ;
	  - objets posés { I, X, Y, S, Z, F? } : F = dessin retourné (miroir) ;
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
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)

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
	Tabletop: boolean?, -- true / false : force "peut être posé sur un meuble"
	RequiresUpgrade: string?, -- (v9.5) amélioration du clicker à posséder pour l'acheter
	Setup: any?, -- (v9.5) "Dopamine Setup" : comportement live (voir Config.House.Items)
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
	Trim: string?, -- (v9.6) look du type (gratuit pour la pièce)
	Mood: string?,
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

-- Un objet posé (format du serveur) ; F = dessin retourné (miroir) ;
-- C = couleur (Config.House.Tints, nil = couleurs d'origine)
export type Placed = { I: string, X: number, Y: number, S: number, Z: number, F: boolean?, C: string?, R: number? }

-- Une pièce (format du serveur) ; Slot = (étage - 1) x Columns + colonne,
-- étage 1 = rez-de-chaussée
export type Room = {
	Id: string,
	Type: string,
	Slot: number,
	Wallpaper: string,
	Floor: string,
	Trim: string, -- (v9.1) boiseries (Config.House.Trims)
	Mood: string, -- (v9.1) ambiance / lumière (Config.House.Moods)
	View: string, -- (v9.1) vue par la fenêtre (Config.House.Views)
	Placed: { Placed },
}

-- (v9.1) Entrée de personnalisation (boiseries, ambiance, vue, façade, toit,
-- motif du toit, déco du jardin, couleur d'objet) : champs selon le genre
export type Look = {
	Id: string,
	Name: string,
	Icon: string,
	Cost: number?,
	RequiresRebirths: number?,
	Color: Color3?,
	Tint: Color3?,
	Tint2: Color3?,
	Amount: number?,
	Light: Color3?,
	Brightness: number?,
	Effect: string?,
	Kind: string?,
	Sky: Color3?,
	Horizon: Color3?,
	Ground: Color3?,
	Pattern: string?,
	Order: number?,
}

export type HouseData = {
	Size: string,
	OwnedSizes: { [string]: boolean },
	OwnedWallpapers: { [string]: boolean },
	OwnedFloors: { [string]: boolean },
	Items: { [string]: number },
	Rooms: { Room },
	-- (v9.1) personnalisation : possédés par genre ({ [id] = true }), extérieur
	Owned: { [string]: { [string]: boolean } },
	Facade: string,
	Roof: string,
	RoofStyle: string,
	Garden: { string },
}

export type HouseConfig = {
	ComfortBonusPerPoint: number,
	MaxComfortBonus: number,
	WallRatio: number,
	TabletopMaxSize: number?,
	TabletopMinY: number?,
	LegacyTabletopSize: number?,
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
	-- (v9.2) les nouvelles catégories donnent leur teinte dans Config (Tint)
	local entry = Config.HouseCategoriesById[categoryId]
	local configured = entry and entry.Tint
	return CATEGORY_TINTS[categoryId] or (typeof(configured) == "Color3" and configured) or HouseCommon.Colors.PinkSoft
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
					F = entry.F == true or nil,
					C = type(entry.C) == "string" and entry.C or nil,
					R = tonumber(entry.R), -- v9.3 : rotation 3D (Dopamine Town), en degrés
				})
			end
		end
	end
	return placed
end

-- (v9.1) Genres de personnalisation (Config.HouseLookKinds)
export type LookKind = { Kind: string, List: { Look }, Owned: string, Scope: string, Field: string, ById: { [string]: Look } }
local LOOK_KINDS = ((Config :: any).HouseLookKinds or {}) :: { [string]: LookKind }
local LOOKS_BY_ID = ((Config :: any).HouseLooksById or {}) :: { [string]: { [string]: Look } }
HouseCommon.LookKinds = LOOK_KINDS
HouseCommon.TintsById = ((Config :: any).HouseTintsById or {}) :: { [string]: Look }
HouseCommon.Tints = ((Config.House :: any).Tints or {}) :: { Look }
HouseCommon.GardenSlots = tonumber((Config.House :: any).GardenSlots) or 6

-- (v9.8 GARDEN98) places de déco du jardin avec les agrandissements du jardin
-- (Config.Garden.Expansion[data.Garden.Level].DecorSlots : 6 / 8 / 10 / 12),
-- même règle que HouseService (serveur) ; data = état du joueur (ClientState.Data par défaut)
function HouseCommon.GardenSlotsFor(data: any?): number
	local source = data or ClientState.Data
	local garden = type(source) == "table" and source.Garden or nil
	local level = type(garden) == "table" and tonumber(garden.Level) or 0
	local levels = Config.Garden and (Config.Garden :: any).Expansion
	local entry = type(levels) == "table" and level and level == level and levels[math.floor(level)] or nil
	return math.max(HouseCommon.GardenSlots, type(entry) == "table" and tonumber(entry.DecorSlots) or 0)
end

-- Id valide d'un genre (sinon la 1re entrée de la liste)
local function lookId(kind: string, value: any): string
	local byId = LOOKS_BY_ID[kind]
	if type(value) == "string" and byId and byId[value] then
		return value
	end
	local def = LOOK_KINDS[kind]
	local first = def and def.List[1]
	return first and first.Id or ""
end

-- Entrée d'un genre par id (la 1re si inconnue)
function HouseCommon.Look(kind: string, id: string?): Look?
	local byId = LOOKS_BY_ID[kind]
	return byId and byId[lookId(kind, id)] or nil
end

-- Vrai si le joueur possède cette entrée (la 1re est gratuite, sauf jardin)
function HouseCommon.OwnsLook(house: HouseData, kind: string, id: string): boolean
	local map = house.Owned[kind]
	return map ~= nil and map[id] == true
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
					Trim = lookId("Trim", raw.Trim),
					Mood = lookId("Mood", raw.Mood),
					View = lookId("View", raw.View),
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
			Trim = lookId("Trim", nil),
			Mood = lookId("Mood", nil),
			View = lookId("View", nil),
			Placed = {},
		})
	end
	-- (v9.1) personnalisation : possédés par genre (la 1re entrée est gratuite)
	local owned: { [string]: { [string]: boolean } } = {}
	for kind, def in pairs(LOOK_KINDS) do
		local map = table.clone(mapOf(house[def.Owned]))
		local first = def.List[1]
		if first and def.Scope ~= "Garden" then
			map[first.Id] = true
		end
		owned[kind] = map
	end
	local garden: { string } = {}
	if type(house.Garden) == "table" then
		for _, id in ipairs(house.Garden) do
			if type(id) == "string" and LOOKS_BY_ID.Garden and LOOKS_BY_ID.Garden[id] then
				table.insert(garden, id)
			end
		end
	end
	return {
		Owned = owned,
		Facade = lookId("Facade", house.Facade),
		Roof = lookId("Roof", house.Roof),
		RoofStyle = lookId("RoofStyle", house.RoofStyle),
		Garden = garden,
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

-- Visites à l'océan nécessaires pour une entrée (objet, style, maison)
function HouseCommon.RequiredRebirths(entry: any): number
	local ok, value = pcall(Formulas.GetHouseRequiredRebirths, entry)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

-- (v9.5) Amélioration du clicker exigée par un objet "Dopamine Setup"
-- (item.RequiresUpgrade = Id de Config.Upgrades, au moins 1 niveau :
-- data.Upgrades[id] >= 1, même règle que HouseService) : renvoie
-- l'amélioration qui manque, nil si rien ne manque
function HouseCommon.MissingUpgrade(data: any, entry: any): any?
	local upgradeId = type(entry) == "table" and entry.RequiresUpgrade or nil
	if type(upgradeId) ~= "string" then
		return nil
	end
	local upgrades = type(data) == "table" and data.Upgrades or nil
	local level = type(upgrades) == "table" and tonumber(upgrades[upgradeId]) or 0
	if level and level == level and level >= 1 then
		return nil
	end
	return Config.UpgradesById[upgradeId] or { Id = upgradeId, Name = upgradeId, Icon = "🔒" }
end

-- Vrai si l'entrée est débloquée pour ces données (visites à l'océan et,
-- v9.5, amélioration exigée)
function HouseCommon.IsUnlocked(data: any, entry: any): boolean
	if HouseCommon.MissingUpgrade(data, entry) ~= nil then
		return false
	end
	local ok, value = pcall(Formulas.IsHouseEntryUnlocked, data, entry)
	if ok and type(value) == "boolean" then
		return value
	end
	return true
end

-- (v9.5) Pourquoi l'entrée est verrouillée : (genre, texte court traduit)
--   "Rebirths" : "Après N visites à l'océan" (le plus gros verrou d'abord)
--   "Upgrade"  : "Débloque 🏃 Coureur infini d'abord" (3e valeur = l'amélioration)
--   nil        : rien ne bloque
function HouseCommon.LockReason(data: any, entry: any): (string?, string?, any?)
	local ok, value = pcall(Formulas.IsHouseEntryUnlocked, data, entry)
	if ok and value == false then
		local required = HouseCommon.RequiredRebirths(entry)
		if required == 1 then
			return "Rebirths", Locale.T("After 1 ocean visit")
		end
		return "Rebirths", Locale.T("After %d ocean visits", required)
	end
	local upgrade = HouseCommon.MissingUpgrade(data, entry)
	if upgrade then
		local label = tostring(upgrade.Icon or "") .. " " .. Locale.T(tostring(upgrade.Name or upgrade.Id))
		return "Upgrade", Locale.T("Unlock %s first", label), upgrade
	end
	return nil, nil
end

-- Objets jamais achetés qu'on peut se payer maintenant (badges)
function HouseCommon.AffordableNew(data: any, dopamine: number): { string }
	local result = {}
	if type(data) ~= "table" then
		return result
	end
	local house = HouseCommon.GetHouse(data)
	for _, item in ipairs(HouseCommon.Config.Items) do
		if HouseCommon.Owned(house, item.Id) == 0 and dopamine >= HouseCommon.Price(item, 0) and HouseCommon.IsUnlocked(data, item) then
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

-- Vrai si l'objet peut être posé SUR un meuble (table, étagère, lit...) :
-- même règle que le serveur (Formulas.CanGoOnFurniture)
local tabletopCache: { [string]: boolean } = {}
function HouseCommon.CanGoOnFurniture(item: Item?): boolean
	if not item then
		return false
	end
	local cached = tabletopCache[item.Id]
	if cached ~= nil then
		return cached
	end
	local ok, value = pcall(Formulas.CanGoOnFurniture, item)
	local result = ok and value == true
	tabletopCache[item.Id] = result
	return result
end

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
-- `onSurface` : petit objet posé SUR un meuble (peut monter jusqu'à
-- Config.House.TabletopMinY, comme le permet le serveur).
-- (v9.6) Zone valide = WorldLayout.PlacementArea : LA MÊME que l'édition 3D
-- de la ville (FurnitureEdit) et que le serveur (HouseService).
function HouseCommon.PlacementArea(item: Item, scale: number, roomWidth: number, roomHeight: number, onSurface: boolean?): (number, number, number, number)
	local raised: number? = nil
	if item.Placement ~= "Wall" and onSurface == true and HouseCommon.CanGoOnFurniture(item) then
		raised = HouseCommon.Config.TabletopMinY
	end
	return WorldLayout.PlacementArea(item.Placement, item.Size * scale, roomWidth, roomHeight, HouseCommon.Config.WallRatio, raised)
end

function HouseCommon.ClampPosition(item: Item, x: number, y: number, scale: number, roomWidth: number, roomHeight: number, onSurface: boolean?): (number, number)
	local x0, x1, y0, y1 = HouseCommon.PlacementArea(item, scale, roomWidth, roomHeight, onSurface)
	return math.clamp(x, x0, x1), math.clamp(y, y0, y1)
end

-- (v9.6) Style "du type" d'une pièce (Config.House.RoomTypes Wallpaper /
-- Floor) : gratuit et débloqué POUR CETTE PIÈCE même s'il n'est pas acheté
-- (même règle que le serveur). kind = "Wallpaper" | "Floor"
function HouseCommon.IsRoomTypeStyle(room: Room?, kind: string, id: string): boolean
	if not room then
		return false
	end
	local roomType = HouseCommon.RoomTypesById[room.Type] :: any
	return roomType ~= nil and roomType[kind] == id
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
