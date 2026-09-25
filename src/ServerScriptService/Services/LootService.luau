--[[
	LootService (ModuleScript)
	Emplacement : ServerScriptService > Services > LootService

	Coffre mystère (débloqué par l'amélioration "Coffre mystère") :
	  - se remplit avec le temps de jeu (Charge, appelé par le tick passif
	    de GameService) : 1 coffre toutes les ChargeInterval secondes, au
	    maximum MaxStored coffres en réserve ;
	  - le joueur l'ouvre avec la RemoteFunction OpenChest : le serveur tire
	    la rareté (poids de Config.LootBox.Tiers) et donne la récompense.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local LootService = {}

local services
local random = Random.new()
local settings = Config.LootBox

function LootService:Init(allServices)
	services = allServices
end

-- Remplit la jauge du coffre (appelé à chaque tick passif)
function LootService:Charge(player: Player, data, elapsed: number)
	if not Formulas.HasFeature(data, settings.Feature) then
		return
	end
	local chests = data.Chests
	if chests.Stored >= settings.MaxStored then
		chests.Progress = 0
		return
	end
	chests.Progress += elapsed / settings.ChargeInterval
	while chests.Progress >= 1 and chests.Stored < settings.MaxStored do
		chests.Progress -= 1
		chests.Stored += 1
	end
	if chests.Stored >= settings.MaxStored then
		chests.Progress = 0
	end
	services.GameService:MarkDirty(player)
end

-- Ajoute des coffres (commande de test /chest)
function LootService:AddChests(player: Player, count: number)
	local data = services.DataService:GetData(player)
	if not data then
		return
	end
	data.Chests.Stored = math.clamp(data.Chests.Stored + count, 0, settings.MaxStored)
	services.GameService:MarkDirty(player)
end

-- Tire une rareté selon les poids
local function pickTier()
	local total = 0
	for _, tier in ipairs(settings.Tiers) do
		total += tier.Weight
	end
	local roll = random:NextNumber(0, total)
	for _, tier in ipairs(settings.Tiers) do
		roll -= tier.Weight
		if roll <= 0 then
			return tier
		end
	end
	return settings.Tiers[1]
end

-- Texte dans la langue du joueur
local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

local function onOpen(player: Player)
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, T(player, "Loading...")
	end
	if not Formulas.HasFeature(data, settings.Feature) then
		return false, T(player, "The mystery chest isn't unlocked yet")
	end
	if data.Chests.Stored < 1 then
		return false, T(player, "No chests to open, be patient...")
	end
	if not RateLimiter.Check(player, "OpenChest", settings.OpenCooldown) then
		return false, T(player, "Slow down!")
	end

	local tier = pickTier()
	local amount = Formulas.ScaledReward(services.GameService:GetStats(player), tier.RewardSeconds, 100)

	data.Chests.Stored -= 1
	data.Stats.ChestsOpened += 1
	services.GameService:AddDopamine(player, amount, true)
	services.QuestService:Progress(player, "Chests", 1)
	services.GameService:SendState(player)

	if tier.Id == "Legendary" then
		local displayName, formatted = player.DisplayName, NumberFormatter.Format(amount)
		services.GameService:NotifyAll(function(lang)
			return {
				Type = "Info",
				Text = Locale.TFor(lang, "📦 %s opened a %s chest (+%s)!", displayName, Locale.TFor(lang, tier.Name), formatted),
			}
		end, player)
	end

	return true, { Tier = tier.Id, Amount = amount }
end

function LootService:Start()
	Net.Function("OpenChest").OnServerInvoke = onOpen
end

return LootService
