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

-- Texte dans la langue du joueur
local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

local function onItemShop(player: Player, action: any, cosmeticId: any)
	if not RateLimiter.Check(player, "ItemShop", 0.2) then
		return false, T(player, "Slow down!")
	end
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, T(player, "Loading...")
	end
	if not Formulas.HasFeature(data, "ItemShop") then
		return false, T(player, "The shop isn't unlocked yet")
	end
	if type(action) ~= "string" or type(cosmeticId) ~= "string" or #cosmeticId > 64 then
		return false, T(player, "Invalid request")
	end
	local cosmetic = Config.CosmeticsById[cosmeticId]
	if not cosmetic then
		return false, T(player, "Unknown item")
	end

	local cosmetics = data.Cosmetics
	local slot = cosmetic.Slot
	if slot ~= "Hat" and slot ~= "Skin" then
		return false, T(player, "Invalid item")
	end
	local name = T(player, cosmetic.Name)

	if action == "buy" then
		if cosmetics.Owned[cosmeticId] then
			return false, T(player, "You already own this item")
		end
		if data.Dopamine < cosmetic.Cost then
			return false, T(player, "Not enough %s", Config.Game.CurrencyName)
		end
		data.Dopamine -= cosmetic.Cost
		cosmetics.Owned[cosmeticId] = true
		cosmetics.Equipped[slot] = cosmeticId -- équipé tout de suite
		data.Stats.CosmeticsBought += 1
		services.GameService:SendState(player)
		return true, T(player, "%s %s bought! (%s)", cosmetic.Icon, name, NumberFormatter.Format(cosmetic.Cost))
	elseif action == "equip" then
		if not cosmetics.Owned[cosmeticId] then
			return false, T(player, "You don't own this item")
		end
		cosmetics.Equipped[slot] = cosmeticId
		services.GameService:SendState(player)
		return true, T(player, "%s %s equipped", cosmetic.Icon, name)
	elseif action == "unequip" then
		cosmetics.Equipped[slot] = ""
		services.GameService:SendState(player)
		return true, T(player, "%s %s removed", cosmetic.Icon, name)
	end
	return false, T(player, "Invalid request")
end

function CosmeticService:Start()
	Net.Function("ItemShop").OnServerInvoke = onItemShop
end

return CosmeticService
