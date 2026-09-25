--[[
	HouseService (ModuleScript)
	Emplacement : ServerScriptService > Services > HouseService

	🏠 Ma maison (Config.House) : une maison de poupée à plusieurs pièces,
	gardée pour toujours (même après l'océan).
	  - la maison (taille) est une grille Floors x Columns de pièces ; on en
	    achète une plus grande avec la Dopamine ;
	  - chaque pièce a un type (salon, chambre, cuisine...), un emplacement
	    dans la grille (déplaçable), son papier peint, son sol et ses objets ;
	  - on achète des pièces (prix x RoomCostGrowth par pièce), des objets
	    (prix x CostGrowth par exemplaire), des papiers peints et des sols ;
	  - le client envoie la disposition des pièces ("saveLayout"), le
	    serveur vérifie TOUT (objets possédés toutes pièces confondues,
	    nombre max par pièce, zones mur/sol) ;
	  - le Confort des objets posés (x1,5 pour les objets "préférés" de leur
	    pièce : harmonie) donne un bonus sur TOUS les gains.

	Données : data.House = {
		Size = "Studio",
		OwnedSizes = { [id] = true }, OwnedWallpapers = { [id] = true }, OwnedFloors = { [id] = true },
		Items = { [itemId] = nombre possédé },
		Rooms = { { Id = "R1", Type = "Living", Slot = 1..MaxRooms, Wallpaper = id, Floor = id,
			Placed = { { I = itemId, X = 0..1, Y = 0..1, S = 0.6..1.6, Z = 0..999 }, ... } }, ... },
		NextRoom = 2, -- prochain numéro d'Id de pièce
	}
	Emplacement (Slot) : (étage - 1) x Columns + colonne ; étage 1 = rez-de-chaussée.
	Les anciennes sauvegardes (une seule pièce : Wallpaper / Floor / Placed)
	deviennent un salon.
	Stats : HouseItemsBought, HouseComfort (meilleur confort atteint).

	RemoteFunction House (action, argument) -> (succès, message) :
	  "buyItem" itemId | "buySize" sizeId | "setSize" sizeId
	  "buyRoom" typeId | { Type, Slot? }
	  "moveRoom" { Room, Slot }   (échange si l'emplacement est pris)
	  "setRoomType" { Room, Type }
	  "buyWallpaper" / "setWallpaper" / "buyFloor" / "setFloor" { Room, Id } (ou Id seul = 1re pièce)
	  "saveLayout" { Rooms = { [roomId] = { { I, X, Y, S, Z }, ... } } }  (ou { Room, Placed })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local HouseService = {}

local services

local HOUSE = Config.House
local DEFAULT_SIZE = HOUSE.Sizes[1].Id
local DEFAULT_WALLPAPER = HOUSE.Wallpapers[1].Id
local DEFAULT_FLOOR = HOUSE.Floors[1].Id

local DEFAULT_ROOM_TYPE = HOUSE.RoomTypes[1].Id

local MAX_ID_LENGTH = 64
local MAX_ROOM_ID_LENGTH = 16
local BUY_INTERVAL = 0.1 -- secondes entre deux achats / changements
local LAYOUT_INTERVAL = 0.5 -- secondes entre deux sauvegardes de disposition
local MIN_SCALE, MAX_SCALE = 0.6, 1.6
local MAX_Z = 999
-- Zones : objets "Wall" en haut (Y <= WallRatio), objets "Floor" en bas
-- (Y >= WallRatio x 0.85 : un peu de marge pour les objets posés contre le mur)
local WALL_MAX_Y = HOUSE.WallRatio
local FLOOR_MIN_Y = HOUSE.WallRatio * 0.85

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Arrondi (sauvegarde plus légère)
local function round(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

local function numberOr(value, default: number): number
	if isValidNumber(value) then
		return value
	end
	return default
end

-- Texte dans la langue du joueur
local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

-- Un objet posé, corrigé : coordonnées bornées, dans la bonne zone
local function normalizeEntry(entry, item)
	local minY, maxY = FLOOR_MIN_Y, 1
	if item.Placement == "Wall" then
		minY, maxY = 0, WALL_MAX_Y
	end
	local x = math.clamp(numberOr(entry.X, 0.5), 0, 1)
	local y = math.clamp(numberOr(entry.Y, (minY + maxY) / 2), minY, maxY)
	local s = math.clamp(numberOr(entry.S, 1), MIN_SCALE, MAX_SCALE)
	local z = math.clamp(math.floor(numberOr(entry.Z, 0)), 0, MAX_Z)
	return {
		I = item.Id,
		X = round(x, 0.0001),
		Y = math.clamp(round(y, 0.0001), minY, maxY),
		S = math.clamp(round(s, 0.001), MIN_SCALE, MAX_SCALE),
		Z = z,
	}
end

-- Garde les `maxItems` premiers objets posés d'une pièce ; renvoie le nombre rangé
local function trimPlaced(room, maxItems: number): number
	local removed = 0
	while #room.Placed > maxItems do
		table.remove(room.Placed)
		removed += 1
	end
	return removed
end

-- Changement de taille : les objets gardent leur place "en px" autour du
-- centre de la pièce (la déco ne s'étire pas dans une maison plus grande).
-- Si la déco ne tient pas dans la nouvelle largeur, on la resserre à la place.
local LAYOUT_MARGIN = 0.05 -- marge gauche / droite (fraction de la largeur)
local function refitLayout(room, oldSize, newSize)
	local oldWidth = tonumber(oldSize and oldSize.Width) or 1
	local newWidth = tonumber(newSize and newSize.Width) or 1
	if oldWidth <= 0 or newWidth <= 0 or oldWidth == newWidth or #room.Placed == 0 then
		return
	end
	-- Étendue actuelle de la déco (en largeurs de "studio")
	local minX, maxX = math.huge, -math.huge
	for _, entry in ipairs(room.Placed) do
		local px = (entry.X - 0.5) * oldWidth
		minX = math.min(minX, px)
		maxX = math.max(maxX, px)
	end
	local half = (0.5 - LAYOUT_MARGIN) * newWidth
	local factor = 1
	local spread = math.max(-minX, maxX)
	if spread > half and spread > 0 then
		factor = half / spread -- trop large : on resserre autour du centre
	end
	for _, entry in ipairs(room.Placed) do
		local px = (entry.X - 0.5) * oldWidth * factor
		entry.X = round(math.clamp(0.5 + px / newWidth, 0, 1), 0.0001)
	end
end

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

-- Emplacement -> (étage, colonne) et inverse, pour une grille de `columns`
local function slotToCell(slot: number, columns: number): (number, number)
	return math.floor((slot - 1) / columns) + 1, (slot - 1) % columns + 1
end

local function cellToSlot(floor: number, column: number, columns: number): number
	return (floor - 1) * columns + column
end

local function findRoom(house, roomId: any)
	if type(roomId) ~= "string" then
		return nil
	end
	for _, room in ipairs(house.Rooms) do
		if room.Id == roomId then
			return room
		end
	end
	return nil
end

local function roomAtSlot(house, slot: number)
	for _, room in ipairs(house.Rooms) do
		if room.Slot == slot then
			return room
		end
	end
	return nil
end

-- Premier emplacement libre (rez-de-chaussée d'abord), nil si la maison est pleine
local function firstFreeSlot(house, maxRooms: number): number?
	for slot = 1, maxRooms do
		if not roomAtSlot(house, slot) then
			return slot
		end
	end
	return nil
end

-- Style de départ d'une pièce : celui du type s'il est possédé, sinon le 1er
local function defaultStyles(house, roomType): (string, string)
	local wallpaper = roomType.Wallpaper
	if type(wallpaper) ~= "string" or not house.OwnedWallpapers[wallpaper] then
		wallpaper = DEFAULT_WALLPAPER
	end
	local floor = roomType.Floor
	if type(floor) ~= "string" or not house.OwnedFloors[floor] then
		floor = DEFAULT_FLOOR
	end
	return wallpaper, floor
end

local function newRoom(house, typeId: string, slot: number)
	local roomType = Formulas.GetRoomType(typeId)
	local id = "R" .. tostring(house.NextRoom)
	house.NextRoom += 1
	local wallpaper, floor = defaultStyles(house, roomType)
	return { Id = id, Type = roomType.Id, Slot = slot, Wallpaper = wallpaper, Floor = floor, Placed = {} }
end

-- Déménagement : chaque pièce garde son étage / sa colonne si possible,
-- sinon elle prend le premier emplacement libre ; la déco est recalée pour
-- la nouvelle largeur de pièce et les objets en trop sont rangés.
local function refitRooms(house, oldSize, newSize): number
	local stored = 0
	local taken = {}
	local pending = {}
	for _, room in ipairs(house.Rooms) do
		local floor, column = slotToCell(room.Slot, oldSize.Columns)
		if floor <= newSize.Floors and column <= newSize.Columns then
			local slot = cellToSlot(floor, column, newSize.Columns)
			if not taken[slot] then
				taken[slot] = true
				room.Slot = slot
			else
				table.insert(pending, room)
			end
		else
			table.insert(pending, room)
		end
	end
	for _, room in ipairs(pending) do
		for slot = 1, newSize.MaxRooms do
			if not taken[slot] then
				taken[slot] = true
				room.Slot = slot
				break
			end
		end
	end
	for _, room in ipairs(house.Rooms) do
		refitLayout(room, oldSize, newSize)
		stored += trimPlaced(room, newSize.RoomItems)
	end
	return stored
end

-- Met à jour le meilleur confort atteint (stat)
local function updateComfortStat(data)
	local comfort = Formulas.GetHouseComfort(data)
	local stats = data.Stats
	if not isValidNumber(stats.HouseComfort) or comfort > stats.HouseComfort then
		stats.HouseComfort = comfort
	end
end

-- Garde seulement les ids connus (valeur true) d'une table { [id] = true }
local function cleanOwnedMap(map, lookup)
	local clean = {}
	if type(map) == "table" then
		for id, value in pairs(map) do
			if value == true and type(id) == "string" and lookup[id] then
				clean[id] = true
			end
		end
	end
	return clean
end

-- Objets posés d'une pièce, corrigés : connus, pas plus que possédés
-- (`used` compte les exemplaires déjà posés dans les autres pièces), au
-- plus `maxItems`
local function cleanPlaced(list, owned, used, maxItems: number)
	local placed = {}
	if type(list) ~= "table" then
		return placed
	end
	for _, entry in ipairs(list) do
		if #placed >= maxItems then
			break
		end
		local id = type(entry) == "table" and entry.I or nil
		local item = type(id) == "string" and Config.HouseItemsById[id] or nil
		if item and (used[id] or 0) < (owned[id] or 0) then
			used[id] = (used[id] or 0) + 1
			table.insert(placed, normalizeEntry(entry, item))
		end
	end
	return placed
end

-- Corrige une sauvegarde abîmée ou devenue incohérente avec la config
-- (et transforme l'ancienne maison à une pièce en maison à pièces)
local function sanitizeHouse(data)
	local house = data.House

	house.OwnedSizes = cleanOwnedMap(house.OwnedSizes, Config.HouseSizesById)
	house.OwnedSizes[DEFAULT_SIZE] = true
	house.OwnedWallpapers = cleanOwnedMap(house.OwnedWallpapers, Config.HouseWallpapersById)
	house.OwnedWallpapers[DEFAULT_WALLPAPER] = true
	house.OwnedFloors = cleanOwnedMap(house.OwnedFloors, Config.HouseFloorsById)
	house.OwnedFloors[DEFAULT_FLOOR] = true

	if type(house.Size) ~= "string" or not house.OwnedSizes[house.Size] then
		house.Size = DEFAULT_SIZE
	end

	-- Objets possédés : nombres entiers > 0, jamais plus que MaxOwned
	local items = {}
	if type(house.Items) == "table" then
		for id, count in pairs(house.Items) do
			local item = type(id) == "string" and Config.HouseItemsById[id] or nil
			if item and isValidNumber(count) and count >= 1 then
				local n = math.floor(count)
				if item.MaxOwned then
					n = math.min(n, item.MaxOwned)
				end
				items[id] = n
			end
		end
	end
	house.Items = items

	-- Ancienne sauvegarde (une seule pièce) -> un salon
	if type(house.Rooms) ~= "table" or #house.Rooms == 0 then
		house.Rooms = {
			{
				Id = "R1",
				Type = DEFAULT_ROOM_TYPE,
				Slot = 1,
				Wallpaper = house.Wallpaper,
				Floor = house.Floor,
				Placed = house.Placed,
			},
		}
	end
	house.Wallpaper = nil
	house.Floor = nil
	house.Placed = nil

	-- Trop de pièces pour la maison actuelle (sauvegarde abîmée) : on prend
	-- la plus petite maison possédée où elles tiennent
	local size = Formulas.GetHouseSize(data)
	if #house.Rooms > size.MaxRooms then
		for _, candidate in ipairs(HOUSE.Sizes) do
			if house.OwnedSizes[candidate.Id] and candidate.MaxRooms >= #house.Rooms then
				house.Size = candidate.Id
				size = candidate
				break
			end
		end
	end

	-- Pièces : Id unique, type connu, emplacement unique dans la grille,
	-- styles possédés, objets vérifiés (toutes pièces confondues)
	local rooms, ids, slots, used = {}, {}, {}, {}
	local highest = 0
	for _, raw in ipairs(house.Rooms) do
		if #rooms >= size.MaxRooms then
			break
		end
		if type(raw) == "table" then
			local id = raw.Id
			if type(id) ~= "string" or #id == 0 or #id > MAX_ROOM_ID_LENGTH or ids[id] then
				id = nil
			end
			local slot = raw.Slot
			if not isValidNumber(slot) or slot % 1 ~= 0 or slot < 1 or slot > size.MaxRooms or slots[slot] then
				slot = nil
			end
			local roomType = Formulas.GetRoomType(raw.Type)
			local fallbackWallpaper, fallbackFloor = defaultStyles(house, roomType)
			local room = {
				Id = id or "",
				Type = roomType.Id,
				Slot = slot or 0,
				Wallpaper = (type(raw.Wallpaper) == "string" and house.OwnedWallpapers[raw.Wallpaper]) and raw.Wallpaper
					or fallbackWallpaper,
				Floor = (type(raw.Floor) == "string" and house.OwnedFloors[raw.Floor]) and raw.Floor or fallbackFloor,
				Placed = cleanPlaced(raw.Placed, items, used, size.RoomItems),
			}
			if id then
				ids[id] = true
				local number = tonumber(string.match(id, "^R(%d+)$"))
				if number then
					highest = math.max(highest, number)
				end
			end
			if slot then
				slots[slot] = true
			end
			table.insert(rooms, room)
		end
	end
	if #rooms == 0 then
		table.insert(rooms, { Id = "R1", Type = DEFAULT_ROOM_TYPE, Slot = 1, Wallpaper = DEFAULT_WALLPAPER, Floor = DEFAULT_FLOOR, Placed = {} })
		highest = 1
	end
	if not isValidNumber(house.NextRoom) or house.NextRoom <= highest then
		house.NextRoom = highest + 1
	end
	house.NextRoom = math.floor(house.NextRoom)
	for _, room in ipairs(rooms) do
		if room.Id == "" then
			room.Id = "R" .. tostring(house.NextRoom)
			house.NextRoom += 1
		end
		if room.Slot == 0 then
			for slot = 1, size.MaxRooms do
				if not slots[slot] then
					slots[slot] = true
					room.Slot = slot
					break
				end
			end
		end
	end
	house.Rooms = rooms

	if not isValidNumber(data.Stats.HouseItemsBought) or data.Stats.HouseItemsBought < 0 then
		data.Stats.HouseItemsBought = 0
	end
	updateComfortStat(data)
end

----------------------------------------------------------------------
-- API utilisée par les autres services
----------------------------------------------------------------------

function HouseService:Init(allServices)
	services = allServices
end

-- Confort actuel (objets posés)
function HouseService:GetComfort(player: Player): number
	local data = services.DataService:GetData(player)
	if not data then
		return 0
	end
	return Formulas.GetHouseComfort(data)
end

-- Multiplicateur de gains de la maison (1 = aucun bonus)
function HouseService:GetBonus(player: Player): number
	return Formulas.GetHouseBonus(self:GetComfort(player))
end

-- Commande de test /house (Studio) : toutes les tailles, papiers peints,
-- sols, et au moins un exemplaire de chaque objet
function HouseService:DebugGrantAll(player: Player): boolean
	local data = services.DataService:GetData(player)
	if not data then
		return false
	end
	local house = data.House
	for _, size in ipairs(HOUSE.Sizes) do
		house.OwnedSizes[size.Id] = true
	end
	for _, wallpaper in ipairs(HOUSE.Wallpapers) do
		house.OwnedWallpapers[wallpaper.Id] = true
	end
	for _, floor in ipairs(HOUSE.Floors) do
		house.OwnedFloors[floor.Id] = true
	end
	for _, item in ipairs(HOUSE.Items) do
		house.Items[item.Id] = math.max(house.Items[item.Id] or 0, 1)
	end
	-- La plus grande maison, avec une pièce de chaque type (gratuit)
	local biggest = HOUSE.Sizes[#HOUSE.Sizes]
	refitRooms(house, Formulas.GetHouseSize(data), biggest)
	house.Size = biggest.Id
	for _, roomType in ipairs(HOUSE.RoomTypes) do
		local slot = firstFreeSlot(house, biggest.MaxRooms)
		if not slot then
			break
		end
		local exists = false
		for _, room in ipairs(house.Rooms) do
			if room.Type == roomType.Id then
				exists = true
				break
			end
		end
		if not exists then
			table.insert(house.Rooms, newRoom(house, roomType.Id, slot))
		end
	end
	updateComfortStat(data)
	services.GameService:SendState(player)
	return true
end

----------------------------------------------------------------------
-- Actions (RemoteFunction House)
----------------------------------------------------------------------

local function buyItem(player: Player, data, itemId: string): (boolean, string)
	local item = Config.HouseItemsById[itemId]
	if not item then
		return false, T(player, "Unknown house item")
	end
	local house = data.House
	local owned = house.Items[itemId] or 0
	local name = T(player, item.Name)
	if item.MaxOwned and owned >= item.MaxOwned then
		return false, T(player, "You can't have more %s %s", item.Icon, name)
	end
	local price = Formulas.GetHouseItemPrice(item, owned)
	if not isValidNumber(price) or price < 0 or data.Dopamine < price then
		return false, T(player, "Not enough %s", Config.Game.CurrencyName)
	end
	data.Dopamine -= price
	house.Items[itemId] = owned + 1
	data.Stats.HouseItemsBought += 1
	services.GameService:SendState(player)
	return true, T(player, "%s %s added to your house! (%s)", item.Icon, name, NumberFormatter.Format(price))
end

-- Emménage dans une taille possédée (les pièces gardent leur place si possible)
local function moveInto(player: Player, data, size): (boolean, string)
	local house = data.House
	if #house.Rooms > size.MaxRooms then
		return false, T(player, "Too many rooms for this house (max %d)", size.MaxRooms)
	end
	local stored = refitRooms(house, Formulas.GetHouseSize(data), size)
	house.Size = size.Id
	updateComfortStat(data)
	services.GameService:SendState(player)
	local name = T(player, size.Name)
	if stored > 0 then
		return true, T(player, "%s Welcome to your %s! (%d items stored)", size.Icon, name, stored)
	end
	return true, T(player, "%s Welcome to your %s!", size.Icon, name)
end

local function buySize(player: Player, data, sizeId: string): (boolean, string)
	local size = Config.HouseSizesById[sizeId]
	if not size then
		return false, T(player, "Unknown house size")
	end
	local house = data.House
	if house.OwnedSizes[sizeId] then
		return false, T(player, "You already own this house")
	end
	if not isValidNumber(size.Cost) or size.Cost < 0 or data.Dopamine < size.Cost then
		return false, T(player, "Not enough %s", Config.Game.CurrencyName)
	end
	data.Dopamine -= size.Cost
	house.OwnedSizes[sizeId] = true
	-- On emménage tout de suite si la nouvelle maison est plus grande
	local current = Formulas.GetHouseSize(data)
	if size.Order > current.Order and #house.Rooms <= size.MaxRooms then
		refitRooms(house, current, size)
		house.Size = sizeId
		updateComfortStat(data)
	end
	services.GameService:SendState(player)
	return true, T(player, "%s %s unlocked! (%s)", size.Icon, T(player, size.Name), NumberFormatter.Format(size.Cost))
end

local function setSize(player: Player, data, sizeId: string): (boolean, string)
	local size = Config.HouseSizesById[sizeId]
	if not size then
		return false, T(player, "Unknown house size")
	end
	if not data.House.OwnedSizes[sizeId] then
		return false, T(player, "You don't own this house yet")
	end
	return moveInto(player, data, size)
end

-- Nouvelle pièce (argument : typeId, ou { Type, Slot? })
local function buyRoom(player: Player, data, argument: any): (boolean, string)
	local typeId, wantedSlot = argument, nil
	if type(argument) == "table" then
		typeId, wantedSlot = argument.Type, argument.Slot
	end
	if type(typeId) ~= "string" or not Config.HouseRoomTypesById[typeId] then
		return false, T(player, "Unknown room type")
	end
	local house = data.House
	local size = Formulas.GetHouseSize(data)
	if #house.Rooms >= size.MaxRooms then
		return false, T(player, "Your house is full: move to a bigger house!")
	end
	local slot: number? = nil
	if wantedSlot ~= nil then
		if not isValidNumber(wantedSlot) or wantedSlot % 1 ~= 0 or wantedSlot < 1 or wantedSlot > size.MaxRooms then
			return false, T(player, "Invalid request")
		end
		if roomAtSlot(house, wantedSlot) then
			return false, T(player, "This spot is already taken")
		end
		slot = wantedSlot
	else
		slot = firstFreeSlot(house, size.MaxRooms)
	end
	if not slot then
		return false, T(player, "Your house is full: move to a bigger house!")
	end
	local price = Formulas.GetRoomCost(#house.Rooms)
	if not isValidNumber(price) or price < 0 or data.Dopamine < price then
		return false, T(player, "Not enough %s", Config.Game.CurrencyName)
	end
	data.Dopamine -= price
	local room = newRoom(house, typeId, slot)
	table.insert(house.Rooms, room)
	services.GameService:SendState(player)
	local roomType = Formulas.GetRoomType(typeId)
	return true, T(player, "%s New room: %s! (%s)", roomType.Icon, T(player, roomType.Name), NumberFormatter.Format(price))
end

-- Déplace une pièce dans la grille (échange avec la pièce déjà là)
local function moveRoom(player: Player, data, argument: any): (boolean, string)
	if type(argument) ~= "table" then
		return false, T(player, "Invalid request")
	end
	local house = data.House
	local room = findRoom(house, argument.Room)
	local slot = argument.Slot
	local size = Formulas.GetHouseSize(data)
	if not room or not isValidNumber(slot) or slot % 1 ~= 0 or slot < 1 or slot > size.MaxRooms then
		return false, T(player, "Invalid request")
	end
	if room.Slot == slot then
		return true, T(player, "🏠 Room moved")
	end
	local other = roomAtSlot(house, slot)
	if other then
		other.Slot = room.Slot
	end
	room.Slot = slot
	services.GameService:SendState(player)
	return true, T(player, "🏠 Room moved")
end

-- Change le type d'une pièce (gratuit ; les objets restent)
local function setRoomType(player: Player, data, argument: any): (boolean, string)
	if type(argument) ~= "table" then
		return false, T(player, "Invalid request")
	end
	local room = findRoom(data.House, argument.Room)
	local typeId = argument.Type
	if not room or type(typeId) ~= "string" or not Config.HouseRoomTypesById[typeId] then
		return false, T(player, "Invalid request")
	end
	room.Type = typeId
	updateComfortStat(data)
	services.GameService:SendState(player)
	local roomType = Formulas.GetRoomType(typeId)
	return true, T(player, "%s This room is now: %s", roomType.Icon, T(player, roomType.Name))
end

-- Papier peint et sol : même logique (kind = "Wallpaper" | "Floor")
local SKINS = {
	Wallpaper = {
		Lookup = Config.HouseWallpapersById,
		OwnedKey = "OwnedWallpapers",
		Unknown = "Unknown wallpaper",
		AlreadyOwned = "You already own this wallpaper",
		NotOwned = "You don't own this wallpaper",
		Bought = "🎨 %s %s wallpaper bought! (%s)",
		Applied = "🎨 %s %s wallpaper applied",
	},
	Floor = {
		Lookup = Config.HouseFloorsById,
		OwnedKey = "OwnedFloors",
		Unknown = "Unknown floor",
		AlreadyOwned = "You already own this floor",
		NotOwned = "You don't own this floor",
		Bought = "🧱 %s %s floor bought! (%s)",
		Applied = "🧱 %s %s floor applied",
	},
}

-- Argument d'un style : { Room, Id } (ou Id seul = 1re pièce)
local function skinTarget(house, argument: any): (any, any)
	if type(argument) == "string" then
		return house.Rooms[1], argument
	end
	if type(argument) == "table" and type(argument.Id) == "string" and #argument.Id <= MAX_ID_LENGTH then
		return findRoom(house, argument.Room), argument.Id
	end
	return nil, nil
end

local function buySkin(player: Player, data, kind: string, argument: any): (boolean, string)
	local skin = SKINS[kind]
	local house = data.House
	local room, id = skinTarget(house, argument)
	if not room or not id then
		return false, T(player, "Invalid request")
	end
	local entry = skin.Lookup[id]
	if not entry then
		return false, T(player, skin.Unknown)
	end
	local owned = house[skin.OwnedKey]
	if owned[id] then
		return false, T(player, skin.AlreadyOwned)
	end
	if not isValidNumber(entry.Cost) or entry.Cost < 0 or data.Dopamine < entry.Cost then
		return false, T(player, "Not enough %s", Config.Game.CurrencyName)
	end
	data.Dopamine -= entry.Cost
	owned[id] = true
	room[kind] = id -- appliqué tout de suite à la pièce
	services.GameService:SendState(player)
	return true, T(player, skin.Bought, entry.Icon or "", T(player, entry.Name), NumberFormatter.Format(entry.Cost))
end

local function setSkin(player: Player, data, kind: string, argument: any): (boolean, string)
	local skin = SKINS[kind]
	local house = data.House
	local room, id = skinTarget(house, argument)
	if not room or not id then
		return false, T(player, "Invalid request")
	end
	local entry = skin.Lookup[id]
	if not entry then
		return false, T(player, skin.Unknown)
	end
	if not house[skin.OwnedKey][id] then
		return false, T(player, skin.NotOwned)
	end
	room[kind] = id
	services.GameService:SendState(player)
	return true, T(player, skin.Applied, entry.Icon or "", T(player, entry.Name))
end

-- Vérifie une liste d'objets posés venue du client (vraie liste 1..n)
local function readPlacedList(player: Player, list: any, maxItems: number): ({ any }?, string?)
	if type(list) ~= "table" then
		return nil, T(player, "Invalid request")
	end
	local count = 0
	for key in pairs(list) do
		count += 1
		if count > maxItems then
			return nil, T(player, "Too many items in this room (max %d)", maxItems)
		end
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return nil, T(player, "Invalid request")
		end
	end
	local result = {}
	for index = 1, count do
		local entry = list[index]
		if type(entry) ~= "table" then
			return nil, T(player, "Invalid request")
		end
		local id = entry.I
		if type(id) ~= "string" or #id > MAX_ID_LENGTH then
			return nil, T(player, "Invalid request")
		end
		local item = Config.HouseItemsById[id]
		if not item then
			return nil, T(player, "Unknown house item")
		end
		table.insert(result, normalizeEntry(entry, item))
	end
	return result, nil
end

-- Nouvelle disposition de une ou plusieurs pièces (déplacer un objet d'une
-- pièce à l'autre = les deux pièces dans le même envoi). Tout est vérifié,
-- puis les listes REMPLACENT les anciennes.
local function saveLayout(player: Player, data, argument: any): (boolean, string)
	if type(argument) ~= "table" then
		return false, T(player, "Invalid request")
	end
	local house = data.House
	local size = Formulas.GetHouseSize(data)
	local lists = argument.Rooms
	if lists == nil and argument.Room ~= nil then
		lists = { [argument.Room] = argument.Placed }
	end
	if type(lists) ~= "table" then
		return false, T(player, "Invalid request")
	end

	local updates = {}
	local count = 0
	for roomId, list in pairs(lists) do
		count += 1
		if count > size.MaxRooms then
			return false, T(player, "Invalid request")
		end
		local room = findRoom(house, roomId)
		if not room then
			return false, T(player, "Unknown room")
		end
		local placed, message = readPlacedList(player, list, size.RoomItems)
		if not placed then
			return false, message or T(player, "Invalid request")
		end
		updates[room] = placed
	end

	-- Exemplaires posés, toutes pièces confondues (nouvelles listes comprises)
	local used = {}
	for _, room in ipairs(house.Rooms) do
		for _, entry in ipairs(updates[room] or room.Placed) do
			used[entry.I] = (used[entry.I] or 0) + 1
		end
	end
	for id, n in pairs(used) do
		if n > (house.Items[id] or 0) then
			local item = Config.HouseItemsById[id]
			return false, T(player, "You don't own enough %s %s", item.Icon, T(player, item.Name))
		end
	end

	for room, placed in pairs(updates) do
		room.Placed = placed
	end
	updateComfortStat(data)
	services.GameService:SendState(player)
	return true, T(player, "🏠 Layout saved")
end

local STRING_ACTIONS = { buyItem = true, buySize = true, setSize = true }

local function onHouse(player: Player, action: any, argument: any)
	if type(action) ~= "string" or #action > 32 then
		return false, T(player, "Invalid request")
	end
	local isLayout = action == "saveLayout"
	if isLayout then
		if not RateLimiter.Check(player, "HouseLayout", LAYOUT_INTERVAL) then
			return false, T(player, "Slow down!")
		end
	elseif not RateLimiter.Check(player, "House", BUY_INTERVAL) then
		return false, T(player, "Slow down!")
	end
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, T(player, "Loading...")
	end
	if isLayout then
		return saveLayout(player, data, argument)
	end

	if STRING_ACTIONS[action] then
		if type(argument) ~= "string" or #argument == 0 or #argument > MAX_ID_LENGTH then
			return false, T(player, "Invalid request")
		end
		if action == "buyItem" then
			return buyItem(player, data, argument)
		elseif action == "buySize" then
			return buySize(player, data, argument)
		end
		return setSize(player, data, argument)
	end
	if type(argument) ~= "string" and type(argument) ~= "table" then
		return false, T(player, "Invalid request")
	end
	if action == "buyRoom" then
		return buyRoom(player, data, argument)
	elseif action == "moveRoom" then
		return moveRoom(player, data, argument)
	elseif action == "setRoomType" then
		return setRoomType(player, data, argument)
	elseif action == "buyWallpaper" then
		return buySkin(player, data, "Wallpaper", argument)
	elseif action == "setWallpaper" then
		return setSkin(player, data, "Wallpaper", argument)
	elseif action == "buyFloor" then
		return buySkin(player, data, "Floor", argument)
	elseif action == "setFloor" then
		return setSkin(player, data, "Floor", argument)
	end
	return false, T(player, "Invalid request")
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function HouseService:PlayerReady(_player: Player, data)
	sanitizeHouse(data)
end

function HouseService:Start()
	Net.Function("House").OnServerInvoke = function(player: Player, action: any, argument: any)
		local ok, success, message = pcall(onHouse, player, action, argument)
		if not ok then
			warn("[HouseService] Erreur pour " .. player.Name .. " :", success)
			return false, T(player, "Invalid request")
		end
		return success, message
	end
end

return HouseService
