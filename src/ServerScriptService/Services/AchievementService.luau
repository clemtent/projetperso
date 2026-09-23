--[[
	AchievementService (ModuleScript)
	Emplacement : ServerScriptService > Services > AchievementService

	Vérifie les succès (définis dans Config.Achievements) et donne les
	récompenses. Appelé automatiquement par GameService quand l'état change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local AchievementService = {}

local services

function AchievementService:Init(allServices)
	services = allServices
end

-- Valeur actuelle d'une statistique (dans data.Stats, ou à la racine comme Rebirths)
function AchievementService:GetStatValue(data, statName: string): number
	local value = data.Stats[statName]
	if value == nil then
		value = data[statName]
	end
	return (type(value) == "number") and value or 0
end

function AchievementService:Check(player: Player)
	local data = services.DataService:GetData(player)
	if not data then
		return
	end

	for _, achievement in ipairs(Config.Achievements) do
		if not data.Achievements[achievement.Id] then
			local value = self:GetStatValue(data, achievement.Stat)
			if value >= achievement.Goal then
				data.Achievements[achievement.Id] = true
				services.GameService:AddDopamine(player, achievement.Reward, false)
				services.GameService:Notify(player, {
					Type = "Achievement",
					Icon = achievement.Icon,
					Title = "SUCCÈS DÉBLOQUÉ !",
					Text = achievement.Icon .. " " .. achievement.Name .. "  (+" .. NumberFormatter.Format(achievement.Reward) .. ")",
				})
			end
		end
	end
end

return AchievementService
