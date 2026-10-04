--[[
	HouseSwitches (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > HouseSwitches

	🚶 Dopamine Town (v11 HOUSE11) : règles PARTAGÉES (serveur + client) des
	interrupteurs et des rideaux de la maison 3D, LUMIÈRE PAR LUMIÈRE et
	FENÊTRE PAR FENÊTRE.

	Clés d'une pièce :
	  - lumières : "C" = plafonnier ; chaque lampe posée = "<ItemId>#<n>"
	    (n = rang de cet objet parmi les lampes du même type de la pièce, dans
	    l'ordre de room.Placed : la clé survit à un déplacement de la lampe) ;
	  - fenêtres : "F1", "F2" (fenêtres de la façade, de gauche à droite vues
	    de la rue) et "B" (fenêtre du fond, côté jardin).
	Clés du hall (pièce spéciale HALL_ID = "Hall") : "C1", "C2"... (lampe de
	plafond de chaque étage) et "K" (lampe de la console de l'entrée).

	Données sauvegardées (HouseService) : room.Off = { clé } (lumières
	éteintes), room.Shut = { clé } (rideaux fermés) ; house.HallOff = { clé }.
	Absent = allumé / ouvert. (Anciennes sauvegardes v9.8 : room.LightsOff /
	room.CurtainsClosed = true -> tout éteint / tout fermé.)

	Copie répliquée pour la ville (attributs du propriétaire) :
	  "HouseLightsOff"      = "R1:C,R1:FloorLamp#1,Hall:K"
	  "HouseCurtainsClosed" = "R1:F1,R4:B"
	Un Id de pièce seul ("R1", ancien format) = toute la pièce.

	API :
	  HouseSwitches.IsLamp(itemId) -> boolean
	  HouseSwitches.LampKeys(placed) -> { [index] = clé }, { clé }
	  HouseSwitches.LightKeys(placed) -> { "C", clés des lampes... }
	  HouseSwitches.IsWindowKey(key) / HouseSwitches.IsHallKey(key, floors?)
	  HouseSwitches.HallKeys(floors) -> { "C1", ..., "K" }
	  HouseSwitches.Encode({ { Id, Keys } }) -> texte ; HouseSwitches.Decode(texte) -> { [Id] = { [clé] = true } }
	  HouseSwitches.Has(map, roomId, key) -> boolean  (clé ou "*" = toute la pièce)
	  HouseSwitches.CleanList(list, valid?) -> { clé } (sans doublon, borné)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HouseSwitches = {}

HouseSwitches.CEILING = "C"
HouseSwitches.HALL_ID = "Hall"
HouseSwitches.WINDOW_KEYS = { "F1", "F2", "B" }
HouseSwitches.MAX_KEYS = 32 -- clés gardées par pièce (au-delà : ignorées)
HouseSwitches.MAX_KEY_LENGTH = 48

local WINDOW_SET = { F1 = true, F2 = true, B = true }

-- Est-ce une lampe (a son propre interrupteur) ? Catégorie "Lights" de la
-- boutique, ou un nom de lampe / lustre / bougie (même règle que v9.8)
function HouseSwitches.IsLamp(itemId: any): boolean
	if type(itemId) ~= "string" then
		return false
	end
	local item = Config.HouseItemsById and Config.HouseItemsById[itemId]
	if type(item) == "table" and item.Category == "Lights" then
		return true
	end
	return string.find(itemId, "Lamp", 1, true) ~= nil or string.find(itemId, "Chandelier", 1, true) ~= nil
		or string.find(itemId, "Candle", 1, true) ~= nil
end

-- Clé de chaque lampe posée : { [index dans placed] = "ItemId#n" } + liste ordonnée
function HouseSwitches.LampKeys(placed: any): ({ [number]: string }, { string })
	local byIndex: { [number]: string } = {}
	local list: { string } = {}
	if type(placed) ~= "table" then
		return byIndex, list
	end
	local seen: { [string]: number } = {}
	for index, entry in ipairs(placed) do
		local id = type(entry) == "table" and entry.I or nil
		if type(id) == "string" and HouseSwitches.IsLamp(id) then
			local n = (seen[id] or 0) + 1
			seen[id] = n
			local key = id .. "#" .. n
			byIndex[index] = key
			table.insert(list, key)
		end
	end
	return byIndex, list
end

-- Toutes les lumières d'une pièce : plafonnier d'abord, puis les lampes
function HouseSwitches.LightKeys(placed: any): { string }
	local _, lamps = HouseSwitches.LampKeys(placed)
	local keys = { HouseSwitches.CEILING }
	for _, key in ipairs(lamps) do
		table.insert(keys, key)
	end
	return keys
end

function HouseSwitches.IsWindowKey(key: any): boolean
	return type(key) == "string" and WINDOW_SET[key] == true
end

-- Lumières du hall : plafonnier de chaque étage ("C1".."Cn") + lampe de la console ("K")
function HouseSwitches.HallKeys(floors: number?): { string }
	local keys = {}
	for floor = 1, math.clamp(math.floor(tonumber(floors) or 3), 1, 6) do
		table.insert(keys, "C" .. floor)
	end
	table.insert(keys, "K")
	return keys
end

function HouseSwitches.IsHallKey(key: any, floors: number?): boolean
	if type(key) ~= "string" then
		return false
	end
	return table.find(HouseSwitches.HallKeys(floors or 6), key) ~= nil
end

-- Liste propre : chaînes courtes, sans doublon, bornée ; `valid` (facultatif) filtre
function HouseSwitches.CleanList(list: any, valid: ((string) -> boolean)?): { string }
	local out: { string } = {}
	if type(list) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, key in ipairs(list) do
		if #out >= HouseSwitches.MAX_KEYS then
			break
		end
		if type(key) == "string" and #key > 0 and #key <= HouseSwitches.MAX_KEY_LENGTH and not string.find(key, "[,:]")
			and not seen[key] and (valid == nil or valid(key)) then
			seen[key] = true
			table.insert(out, key)
		end
	end
	return out
end

-- { { Id = "R1", Keys = { "C", "F1" } }, ... } -> "R1:C,R1:F1"
function HouseSwitches.Encode(entries: { { Id: string, Keys: { string } } }): string
	local parts = {}
	for _, entry in ipairs(entries) do
		for _, key in ipairs(entry.Keys) do
			table.insert(parts, entry.Id .. ":" .. key)
		end
	end
	return table.concat(parts, ",")
end

-- "R1:C,R4" -> { R1 = { C = true }, R4 = { ["*"] = true } }
function HouseSwitches.Decode(text: any): { [string]: { [string]: boolean } }
	local map: { [string]: { [string]: boolean } } = {}
	if type(text) ~= "string" then
		return map
	end
	for token in string.gmatch(text, "[^,]+") do
		local id, key = string.match(token, "^([^:]+):(.+)$")
		if not id then
			id, key = token, "*"
		end
		local set = map[id :: string]
		if not set then
			set = {}
			map[id :: string] = set
		end
		set[key :: string] = true
	end
	return map
end

-- La clé `key` de la pièce `roomId` est-elle dans la carte (ou toute la pièce) ?
function HouseSwitches.Has(map: { [string]: { [string]: boolean } }, roomId: string, key: string): boolean
	local set = map[roomId]
	return set ~= nil and (set[key] == true or set["*"] == true)
end

return HouseSwitches
