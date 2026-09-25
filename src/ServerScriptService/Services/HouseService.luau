--[[
	HouseService (ModuleScript)
	Emplacement : ServerScriptService > Services > HouseService

	🏠 Ma maison (Config.House) : une pièce kawaii à décorer, gardée pour
	toujours (même après l'océan).
	  - on achète des objets avec la Dopamine (prix x CostGrowth par
	    exemplaire déjà possédé, Formulas.GetHouseItemPrice) ;
	  - on achète / choisit la taille de la maison, le papier peint et le sol ;
	  - le client envoie la disposition des objets posés ("saveLayout"),
	    le serveur vérifie TOUT (objets possédés, nombre max, zones mur/sol) ;
	  - le Confort des objets posés donne un bonus sur TOUS les gains
	    (GameService:GetStats le multiplie dans le bonus).

	Données : data.House = {
		Size = "Studio", Wallpaper = id, Floor = id,
		OwnedSizes = { [id] = true }, OwnedWallpapers = { [id] = true }, OwnedFloors = { [id] = true },
		Items = { [itemId] = nombre possédé },
		Placed = { { I = itemId, X = 0..1, Y = 0..1, S = 0.6..1.6, Z = 0..999 }, ... },
	}
	Stats : HouseItemsBought, HouseComfort (meilleur confort atteint).

	RemoteFunction House (action, argument) -> (succès, message) :
	  "buyItem" itemId | "buySize" sizeId | "setSize" sizeId
	  "buyWallpaper" id | "setWallpaper" id | "buyFloor" id | "setFloor" id
	  "saveLayout" { { I, X, Y, S, Z }, ... }
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

local MAX_ID_LENGTH = 64
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

-- Garde les `maxItems` premiers objets posés ; renvoie le nombre rangé
local function trimPlaced(house, maxItems: number): number
	local removed = 0
	while #house.Placed > maxItems do
		table.remove(house.Placed)
		removed += 1
	end
	return removed
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

-- Corrige une sauvegarde abîmée ou devenue incohérente avec la config
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
	if type(house.Wallpaper) ~= "string" or not house.OwnedWallpapers[house.Wallpaper] then
		house.Wallpaper = DEFAULT_WALLPAPER
	end
	if type(house.Floor) ~= "string" or not house.OwnedFloors[house.Floor] then
		house.Floor = DEFAULT_FLOOR
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

	-- Objets posés : connus, possédés, dans la bonne zone, pas plus que la taille
	local maxItems = Formulas.GetHouseSize(data).MaxItems
	local placed, used = {}, {}
	if type(house.Placed) == "table" then
		for _, entry in ipairs(house.Placed) do
			if #placed >= maxItems then
				break
			end
			local id = type(entry) == "table" and entry.I or nil
			local item = type(id) == "string" and Config.HouseItemsById[id] or nil
			if item and (used[id] or 0) < (items[id] or 0) then
				used[id] = (used[id] or 0) + 1
				table.insert(placed, normalizeEntry(entry, item))
			end
		end
	end
	house.Placed = placed

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

-- Emménage dans une taille possédée ; range les objets en trop
local function moveInto(player: Player, data, size): (boolean, string)
	local house = data.House
	house.Size = size.Id
	local stored = trimPlaced(house, size.MaxItems)
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
	if size.Order > current.Order then
		house.Size = sizeId
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

local function buySkin(player: Player, data, kind: string, id: string): (boolean, string)
	local skin = SKINS[kind]
	local entry = skin.Lookup[id]
	if not entry then
		return false, T(player, skin.Unknown)
	end
	local house = data.House
	local owned = house[skin.OwnedKey]
	if owned[id] then
		return false, T(player, skin.AlreadyOwned)
	end
	if not isValidNumber(entry.Cost) or entry.Cost < 0 or data.Dopamine < entry.Cost then
		return false, T(player, "Not enough %s", Config.Game.CurrencyName)
	end
	data.Dopamine -= entry.Cost
	owned[id] = true
	house[kind] = id -- appliqué tout de suite
	services.GameService:SendState(player)
	return true, T(player, skin.Bought, entry.Icon or "", T(player, entry.Name), NumberFormatter.Format(entry.Cost))
end

local function setSkin(player: Player, data, kind: string, id: string): (boolean, string)
	local skin = SKINS[kind]
	local entry = skin.Lookup[id]
	if not entry then
		return false, T(player, skin.Unknown)
	end
	local house = data.House
	if not house[skin.OwnedKey][id] then
		return false, T(player, skin.NotOwned)
	end
	house[kind] = id
	services.GameService:SendState(player)
	return true, T(player, skin.Applied, entry.Icon or "", T(player, entry.Name))
end

-- Nouvelle disposition envoyée par le client : tout est vérifié, puis
-- elle REMPLACE l'ancienne
local function saveLayout(player: Player, data, list: any): (boolean, string)
	if type(list) ~= "table" then
		return false, T(player, "Invalid request")
	end
	local house = data.House
	local maxItems = Formulas.GetHouseSize(data).MaxItems

	-- Doit être une vraie liste 1..n, de taille raisonnable
	local count = 0
	for key in pairs(list) do
		count += 1
		if count > maxItems then
			return false, T(player, "Too many items for this house (max %d)", maxItems)
		end
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return false, T(player, "Invalid request")
		end
	end

	local placed, used = {}, {}
	for index = 1, count do
		local entry = list[index]
		if type(entry) ~= "table" then
			return false, T(player, "Invalid request")
		end
		local id = entry.I
		if type(id) ~= "string" or #id > MAX_ID_LENGTH then
			return false, T(player, "Invalid request")
		end
		local item = Config.HouseItemsById[id]
		if not item then
			return false, T(player, "Unknown house item")
		end
		local n = (used[id] or 0) + 1
		if n > (house.Items[id] or 0) then
			return false, T(player, "You don't own enough %s %s", item.Icon, T(player, item.Name))
		end
		used[id] = n
		table.insert(placed, normalizeEntry(entry, item))
	end

	house.Placed = placed
	updateComfortStat(data)
	services.GameService:SendState(player)
	return true, T(player, "🏠 Layout saved")
end

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

	if type(argument) ~= "string" or #argument == 0 or #argument > MAX_ID_LENGTH then
		return false, T(player, "Invalid request")
	end
	if action == "buyItem" then
		return buyItem(player, data, argument)
	elseif action == "buySize" then
		return buySize(player, data, argument)
	elseif action == "setSize" then
		return setSize(player, data, argument)
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
