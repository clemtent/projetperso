--[[
	BankLayout (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > BankLayout

	🏦 Géométrie PARTAGÉE de la Banque Dopamine (v11, BANK11) : le client la
	construit (BankBuild) et le serveur s'en sert pour vérifier les
	distances (guichets, distributeurs, casse). Pur (WorldLayout + CFrame).

	Emplacement : zone "Bank" de WorldLayout.Facilities si elle existe, sinon
	le terrain réservé par CITY11 : centre ville (120, 540), façade au NORD
	(LookVector -Z, vers la rue du marché z = 480). Rectangle réservé :
	x 84..156, z 502..568 (marches comprises).

	Repère LOCAL de la banque (origine = centre du bâtiment, au sol, y = 0 ;
	-Z = devant / la rue ; vu de la rue on regarde vers +Z, donc +X local est
	à GAUCHE du passant). Plancher du hall : y = FLOOR.
	  - façade (colonnes) z = -FRONT ; marches de z = -FRONT à -STEPS_END ;
	  - hall z -FRONT..COUNTER ; guichets en z = COUNTER ; espace du personnel
	    COUNTER..VAULT_WALL ; porte du coffre au centre de VAULT_WALL ;
	    chambre forte VAULT_WALL..BACK ;
	  - ruelle de service à +X (x HALF_W..ALLEY) : porte du personnel,
	    boîtier d'alarme, plan du casse.
]]

local WorldLayout = require(script.Parent.WorldLayout)

local BankLayout = {}

-- Dimensions (studs, échelle Roblox SCALE11)
BankLayout.CITY_X = 120
BankLayout.CITY_Z = 540
BankLayout.HALF_W = 29 -- demi-largeur du bâtiment (x -29..29)
BankLayout.ALLEY = 35.5 -- bord extérieur de la ruelle de service (+X) / du côté -X
BankLayout.FRONT = 21 -- façade (colonnade devant, en z -21..-25)
BankLayout.PORTICO = 26 -- bord avant du portique
BankLayout.STEPS_END = 36 -- bas des marches (z = -36)
BankLayout.BACK = 26 -- mur du fond (z = +26)
BankLayout.FLOOR = 3.6 -- plancher du hall (4 marches de 0,9)
BankLayout.HALL_H = 24 -- hauteur sous plafond du hall
BankLayout.COUNTER = 5 -- ligne des guichets (face clients)
BankLayout.VAULT_WALL = 13 -- mur de la chambre forte
BankLayout.VAULT_HALF = 11 -- demi-largeur de la chambre forte
BankLayout.STAFF_DOOR_Z = 9 -- porte du personnel (mur +X)
BankLayout.COUNTERS = 4

-- Repère de la banque (au sol, LookVector = façade -> rue)
function BankLayout.CFrame(count: number): CFrame
	local ok, zone = pcall(function()
		return (WorldLayout :: any).Facility(count, "Bank")
	end)
	if ok and type(zone) == "table" and type(zone.X) == "number" and type(zone.Z) == "number" then
		return WorldLayout.CityCFrame(zone.X, zone.Z, tonumber(zone.Yaw) or 0, tonumber(zone.Y) or 0)
	end
	return WorldLayout.CityCFrame(BankLayout.CITY_X, BankLayout.CITY_Z, 0, 0)
end

-- Point local -> monde
function BankLayout.World(count: number, x: number, y: number, z: number): Vector3
	return BankLayout.CFrame(count) * Vector3.new(x, y, z)
end

-- Points d'intérêt en coordonnées LOCALES (Vector3, y au sol de l'endroit)
function BankLayout.LocalPoints(): { [string]: any }
	local F = BankLayout.FLOOR
	local counters = {}
	local n = BankLayout.COUNTERS
	for i = 1, n do
		-- guichets 1..4 de gauche à droite vus du hall (+X à gauche) ; espacés de 8,5 studs
		local x = ((n + 1) / 2 - i) * 8.5
		table.insert(counters, Vector3.new(x, F, BankLayout.COUNTER - 2.2))
	end
	local piles = {}
	-- butin de la chambre forte : 2 rangées de 4 (lingots, plateaux de diamants)
	for row = 0, 1 do
		for i = 0, 3 do
			local x = -7.5 + i * 5
			local z = BankLayout.VAULT_WALL + 5 + row * 5
			table.insert(piles, Vector3.new(x, F, z))
		end
	end
	return {
		Door = Vector3.new(0, F, -BankLayout.FRONT),
		Counters = counters,
		-- distributeurs : 2 sur la façade (sous le portique), 2 dans le hall
		ATMs = {
			Vector3.new(-17, F, -BankLayout.FRONT - 1.4),
			Vector3.new(17, F, -BankLayout.FRONT - 1.4),
			Vector3.new(-26.2, F, -1.2),
			Vector3.new(-26.2, F, 2.6),
		},
		Luxury = Vector3.new(-20, F, -13), -- comptoir du bijoutier (boutique de luxe)
		Deposit = Vector3.new(24, F, -10), -- salle des coffres individuels (mur +X du hall)
		Rates = Vector3.new(0, F, -6), -- panneau du cours du diamant
		Lobby = Vector3.new(32.3, 0.6, -14), -- plan du casse (ruelle de service)
		Hack = Vector3.new(30.8, 0.6, -2.5), -- boîtier d'alarme (dehors, ruelle, au pied du quai)
		StaffDoor = Vector3.new(BankLayout.HALF_W, F, BankLayout.STAFF_DOOR_Z),
		Drill = Vector3.new(0, F, BankLayout.VAULT_WALL - 4), -- devant la porte ronde du coffre
		Piles = piles,
	}
end

-- Mêmes points en coordonnées du MONDE
function BankLayout.Points(count: number): { [string]: any }
	local cf = BankLayout.CFrame(count)
	local function w(v: Vector3): Vector3
		return cf * v
	end
	local L = BankLayout.LocalPoints()
	local out = {}
	for k, v in pairs(L) do
		if typeof(v) == "Vector3" then
			out[k] = w(v)
		elseif type(v) == "table" then
			local list = {}
			for i, p in ipairs(v) do
				list[i] = w(p)
			end
			out[k] = list
		end
	end
	return out
end

-- Planques (points de livraison du butin) : endroits libres de la case
-- d'entrée, à 200..320 studs de la banque, hors des rails du train.
local DROP_CANDIDATES = {
	{ -150, 330 }, { -185, 405 }, { -160, 575 }, { 185, 345 }, { 186, 420 }, { -120, 300 }, { -186, 470 }, { 184, 600 },
}
local dropCache: { [number]: { Vector3 } } = {}

function BankLayout.Drops(count: number, isClear: ((x: number, z: number) -> boolean)?): { Vector3 }
	local n = WorldLayout.PlotCount(count)
	if not isClear and dropCache[n] then
		return dropCache[n]
	end
	local bank = BankLayout.CFrame(n).Position - WorldLayout.Origin()
	local list = {}
	for _, c in ipairs(DROP_CANDIDATES) do
		local x, z = c[1], c[2]
		local d = math.sqrt((x - bank.X) ^ 2 + (z - bank.Z) ^ 2)
		local free = d >= 150 and WorldLayout.IsFreeAt(n, x, z, 7)
		if free and isClear then
			free = isClear(x, z)
		end
		if free then
			table.insert(list, WorldLayout.CityPoint(x, WorldLayout.GROUND_Y, z))
		end
	end
	if #list == 0 then
		-- (secours : jamais vide) devant le portail de la ville
		table.insert(list, WorldLayout.CityPoint(-120, WorldLayout.GROUND_Y, 300))
	end
	if not isClear then
		dropCache[n] = list
	end
	return list
end

-- Point (monde) dans l'emprise de la banque (marge en studs) ?
function BankLayout.Inside(count: number, p: Vector3, margin: number?): boolean
	local lp = BankLayout.CFrame(count):PointToObjectSpace(p)
	local m = margin or 0
	return math.abs(lp.X) <= BankLayout.ALLEY + m and lp.Z >= -BankLayout.STEPS_END - m and lp.Z <= BankLayout.BACK + 2 + m
end

return BankLayout
