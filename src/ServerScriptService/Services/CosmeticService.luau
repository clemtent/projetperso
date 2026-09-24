--[[
	CosmeticService (ModuleScript)
	Emplacement : ServerScriptService > Services > CosmeticService

	Boutique d'objets (débloquée par l'amélioration "Boutique d'objets") :
	chapeaux (emoji posé sur le bouton) et skins (couleurs du bouton).
	Les objets achetés sont gardés pour toujours et donnent chacun un petit
	bonus de gains permanent (Config.CosmeticBonus).
	RemoteFunction ItemShop ("buy" | "equip" | "unequip", cosmeticId).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local CosmeticService = {}

local services

function CosmeticService:Init(allServices)
	services = allServices
end

local function onItemShop(player: Player, action: any, cosmeticId: any)
	if not RateLimiter.Check(player, "ItemShop", 0.2) then
		return false, "Doucement !"
	end
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, "Chargement en cours..."
	end
	if not Formulas.HasFeature(data, "ItemShop") then
		return false, "La boutique n'est pas encore débloquée"
	end
	if type(action) ~= "string" or type(cosmeticId) ~= "string" or #cosmeticId > 64 then
		return false, "Requête invalide"
	end
	local cosmetic = Config.CosmeticsById[cosmeticId]
	if not cosmetic then
		return false, "Objet inconnu"
	end

	local cosmetics = data.Cosmetics
	local slot = cosmetic.Slot
	if slot ~= "Hat" and slot ~= "Skin" then
		return false, "Objet invalide"
	end

	if action == "buy" then
		if cosmetics.Owned[cosmeticId] then
			return false, "Tu as déjà cet objet"
		end
		if data.Dopamine < cosmetic.Cost then
			return false, "Pas assez de " .. Config.Game.CurrencyName
		end
		data.Dopamine -= cosmetic.Cost
		cosmetics.Owned[cosmeticId] = true
		cosmetics.Equipped[slot] = cosmeticId -- équipé tout de suite
		data.Stats.CosmeticsBought += 1
		services.GameService:SendState(player)
		return true, string.format("%s %s acheté ! (%s)", cosmetic.Icon, cosmetic.Name, NumberFormatter.Format(cosmetic.Cost))
	elseif action == "equip" then
		if not cosmetics.Owned[cosmeticId] then
			return false, "Tu ne possèdes pas cet objet"
		end
		cosmetics.Equipped[slot] = cosmeticId
		services.GameService:SendState(player)
		return true, cosmetic.Icon .. " " .. cosmetic.Name .. " équipé"
	elseif action == "unequip" then
		cosmetics.Equipped[slot] = ""
		services.GameService:SendState(player)
		return true, cosmetic.Icon .. " " .. cosmetic.Name .. " retiré"
	end
	return false, "Requête invalide"
end

function CosmeticService:Start()
	Net.Function("ItemShop").OnServerInvoke = onItemShop
end

return CosmeticService
