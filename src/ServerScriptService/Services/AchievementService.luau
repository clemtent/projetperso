--[[
	AchievementService (ModuleScript)
	Emplacement : ServerScriptService > Services > AchievementService

	Vérifie les succès (définis dans Config.Achievements) et donne les
	récompenses. Appelé automatiquement par GameService quand l'état change.
	Si un succès a un BadgeId (Config.AchievementBadges), le vrai badge
	Roblox est aussi donné (BadgeService), y compris pour les succès déjà
	débloqués avant que le badge existe (vérifié à la connexion).
]]

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local AchievementService = {}

local services

function AchievementService:Init(allServices)
	services = allServices
end

-- Donne le badge Roblox d'un succès (en arrière-plan, jamais bloquant)
local function awardBadge(player: Player, achievement)
	local badgeId = achievement.BadgeId
	if type(badgeId) ~= "number" or badgeId <= 0 then
		return
	end
	task.spawn(function()
		local okHas, has = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		if okHas and has then
			return
		end
		local ok, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not ok then
			warn("[AchievementService] Badge " .. tostring(badgeId) .. " non donné :", err)
		end
	end)
end

-- À la connexion : badges des succès déjà débloqués (si le badge a été ajouté après)
function AchievementService:PlayerReady(player: Player, data)
	for _, achievement in ipairs(Config.Achievements) do
		if data.Achievements[achievement.Id] then
			awardBadge(player, achievement)
		end
	end
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
					Id = achievement.Id,
					Name = achievement.Name,
					Reward = achievement.Reward,
					BadgeAwarded = achievement.BadgeId > 0,
				})
				awardBadge(player, achievement)
			end
		end
	end
end

return AchievementService
