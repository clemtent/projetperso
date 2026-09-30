--[[
	TownVehicles (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownVehicles

	🚌 Véhicules du décor de Dopamine Town (v9.7, VEHICLES97), appelés aux
	endroits "véhicules" de TownEntrance / TownStreets / TownNature.
	Budget de pièces du serveur serré (ville ≤ ~5000) : le serveur ne pose
	que ce qui doit exister pour tout le monde et coûte peu ;
	le lourd (bus complet avec sièges, vélos à rayons, trottinettes, camion
	de livraison, voitures garées en plus) est construit CÔTÉ CLIENT et en
	flux par TownTraffic à partir de "places" (TownKit.VehicleSpot : 0 pièce),
	avec, pour les gros véhicules, une boîte invisible solide côté serveur.
	  - Bus(parent, cf)            : bus de ville garé (client) + boîte solide ;
	  - FoodTruck(parent, cf)      : food truck "🌮 Taco Party" (serveur,
	                                 version légère ~50 pièces) ;
	  - DeliveryVan(parent, cf)    : camion "📦 Dopa Express" (client) + boîte ;
	  - ParkingRow(parent, rowCF, bays, seed, serverCars)
	                               : places marquées le long d'un trottoir
	                                 (lignes au sol, serveur) + voitures
	                                 alignées, roues sur la chaussée, modèles
	                                 et couleurs variés ; `serverCars`
	                                 voitures construites par le serveur,
	                                 les autres par le client ;
	  - TwoWheelers(parent, cf, n, seed) : trottinettes / scooter garés (client).
	rowCF : au niveau de la chaussée, sur l'arête du trottoir ; LookVector =
	du trottoir vers la chaussée ; les places s'alignent le long de
	RightVector (voitures tournées vers +RightVector : leur côté droit est
	contre le trottoir, conduite à droite).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarModels = require(ReplicatedStorage.Shared.CarModels)
local VehicleModels = require(ReplicatedStorage.Shared.VehicleModels)
local TownKit = require(script.Parent.TownKit)

local TownVehicles = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part
local hash = TownKit.Hash

TownVehicles.BAY_LENGTH = 13
TownVehicles.BAY_DEPTH = 6.2
TownVehicles.CURB_GAP = 0.5

-- Modèles garés (≤ 13 studs : tiennent dans une place) et teintes réalistes
TownVehicles.PARKED_KINDS = { "CityCar", "Hatchback", "SUV", "BubbleCar", "CityCar", "Hatchback", "Pickup", "SportsCar", "Van" }
TownVehicles.PARKED_COLORS = {
	Color3.fromRGB(246, 244, 240), -- blanc nacré
	Color3.fromRGB(176, 182, 192), -- gris argent
	Color3.fromRGB(38, 38, 48), -- noir
	Color3.fromRGB(56, 90, 170), -- bleu jean
	Color3.fromRGB(220, 44, 64), -- rouge cerise
	Color3.fromRGB(255, 150, 196), -- rose bonbon
	Color3.fromRGB(130, 200, 255), -- bleu ciel
	Color3.fromRGB(128, 222, 190), -- menthe
	Color3.fromRGB(255, 212, 80), -- jaune
	Color3.fromRGB(186, 156, 246), -- lilas
	Color3.fromRGB(34, 110, 76), -- vert anglais
}

-- Choix stable (même ville à chaque démarrage) d'une voiture garée
function TownVehicles.PickCar(seed: number, index: number): (string, Color3, { [string]: any })
	local kinds, colors = TownVehicles.PARKED_KINDS, TownVehicles.PARKED_COLORS
	-- (graines bien mélangées : deux voitures voisines n'ont presque jamais la même teinte)
	local kind = kinds[math.floor(hash(seed * 1.618 + index * 7.31, 31) * #kinds) % #kinds + 1]
	local color = colors[(math.floor(hash(seed * 2.414 + 3.3, 57) * #colors) + index * 4) % #colors + 1]
	local opts: { [string]: any } = { Detail = "Parked" }
	local roll = hash(seed * 0.707 + index * 5.9, 83)
	if roll < 0.18 then
		opts.Stripe = true
	elseif roll < 0.3 and (kind == "CityCar" or kind == "Hatchback" or kind == "SUV") then
		opts.RoofColor = if color.R + color.G + color.B > 1.8 then Color3.fromRGB(38, 38, 48) else Color3.fromRGB(246, 244, 240)
	end
	return kind, color, opts
end

----------------------------------------------------------------------
-- Places de stationnement marquées + voitures garées
----------------------------------------------------------------------

function TownVehicles.ParkingRow(parent: Instance, rowCF: CFrame, bays: number, seed: number, serverCars: number): Model
	local model = TownKit.Model(parent, "Parking")
	local L, depth = TownVehicles.BAY_LENGTH, TownVehicles.BAY_DEPTH
	local x0 = -bays * L / 2
	-- séparateurs (même blanc / matière que les autres lignes : jamais de z-fighting)
	for i = 0, bays do
		-- (v9.9) +0,04 : au-dessus des rustines d'enrobé de la chaussée (TownRoads)
		part(model, "BayLine", Vector3.new(0.3, 0.1, depth), rowCF * CFrame.new(x0 + i * L, 0.04, -depth / 2 - 0.05), C.Line, M.SmoothPlastic, "deco")
	end
	-- une place libre (réaliste), les autres occupées
	local empty = math.floor(hash(seed, 7) * bays) % bays
	local placed = 0
	for i = 0, bays - 1 do
		if i ~= empty then
			local kind, color, opts = TownVehicles.PickCar(seed, i)
			local width = CarModels.Dimensions(kind).X
			local cf = rowCF * CFrame.new(x0 + (i + 0.5) * L, 0, -(TownVehicles.CURB_GAP + width / 2)) * CFrame.Angles(0, -math.pi / 2, 0)
			if placed < serverCars then
				TownKit.Car(model, cf, color, kind, opts)
			else
				TownKit.VehicleSpot(model, "Car", cf, { CarId = kind, Color = color, Stripe = opts.Stripe == true, RoofColor = opts.RoofColor })
			end
			placed += 1
		end
	end
	model:SetAttribute("Bays", bays)
	return model
end

----------------------------------------------------------------------
-- Gros véhicules
----------------------------------------------------------------------

-- 🚌 bus de ville garé (portes côté +X) : construit par le client, boîte solide ici
function TownVehicles.Bus(parent: Instance, cf: CFrame): Instance
	local B = VehicleModels.BUS
	local size = Vector3.new(B.W, 8.1, B.L)
	return TownKit.VehicleSpot(parent, "Bus", cf, { Variant = "Full" }, { Size = size, CF = cf * CFrame.new(0, 0.7 + size.Y / 2, 0) })
end

-- 📦 camion de livraison garé : construit par le client, boîte solide ici
function TownVehicles.DeliveryVan(parent: Instance, cf: CFrame): Instance
	local size = Vector3.new(6.6, 7.4, 17)
	return TownKit.VehicleSpot(parent, "DeliveryVan", cf, {}, { Size = size, CF = cf * CFrame.new(0, 0.8 + size.Y / 2, 0) })
end

-- 🌮 food truck (serveur, version légère : visible par tous, solide)
function TownVehicles.FoodTruck(parent: Instance, cf: CFrame, color: Color3?): Model
	local model = VehicleModels.FoodTruck({ Detail = "Light", Color = color, Solid = true })
	model:PivotTo(cf)
	model.Parent = parent
	TownKit.Stats.Parts += tonumber(model:GetAttribute("PartCount")) or 0
	return model
end

-- 🛴 trottinettes / 🛵 scooter garés en épi (client), le long de X de `cf`
function TownVehicles.TwoWheelers(parent: Instance, cf: CFrame, count: number, seed: number)
	local colors = { Color3.fromRGB(64, 200, 170), Color3.fromRGB(255, 132, 184), Color3.fromRGB(126, 196, 255), Color3.fromRGB(255, 208, 72) }
	for i = 0, count - 1 do
		local scooter = hash(seed, 11 + i) < 0.3
		local kind = if scooter then "Scooter" else "KickScooter"
		local spot = cf * CFrame.new(i * (if scooter then 2.4 else 1.6), 0, 0) * CFrame.Angles(0, math.rad((hash(seed, 13 + i) - 0.5) * 16), 0)
		TownKit.VehicleSpot(parent, kind, spot, { Color = colors[(seed + i) % #colors + 1] })
	end
end

return TownVehicles
