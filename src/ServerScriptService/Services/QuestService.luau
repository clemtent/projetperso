--[[
	QuestService (ModuleScript)
	Emplacement : ServerScriptService > Services > QuestService

	Quêtes simples (ex. "Fais 50 clics"). Le joueur a toujours
	Config.Quests.ActiveCount quêtes actives. Une quête terminée donne sa
	récompense automatiquement et est remplacée par une nouvelle.
	  - Un modèle avec une Feature n'est proposé que si le joueur la possède.
	  - Les quêtes n'avancent qu'une fois le menu "Quêtes" débloqué.
	  - Types : Clicks, Earn, Buy, Bounces, Bubbles, Spawns, Combo, Casino, Chests.
	  - Les quêtes sont gardées après une détox.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local QuestService = {}

local services
local random = Random.new()

local QUESTS_FEATURE = "Quests"

-- Types de quêtes existants (d'après la config)
local validTypes = {}
for _, template in ipairs(Config.Quests.Pool) do
	validTypes[template.Type] = true
end

function QuestService:Init(allServices)
	services = allServices
end

local function isTemplateAvailable(data, template): boolean
	return template.Feature == nil or Formulas.HasFeature(data, template.Feature)
end

-- Crée une nouvelle quête en évitant les types déjà actifs
local function generateQuest(player: Player, data, activeQuests)
	local usedTypes = {}
	for _, quest in ipairs(activeQuests) do
		usedTypes[quest.Type] = true
	end

	local available = {}
	local candidates = {}
	for _, template in ipairs(Config.Quests.Pool) do
		if isTemplateAvailable(data, template) then
			table.insert(available, template)
			if not usedTypes[template.Type] then
				table.insert(candidates, template)
			end
		end
	end
	if #candidates == 0 then
		candidates = (#available > 0) and available or Config.Quests.Pool
	end

	local template = candidates[random:NextInteger(1, #candidates)]
	local stats = services.GameService:GetStats(player)

	local goal
	if template.GoalSeconds then
		-- Objectif "à l'échelle" : X secondes de production
		local seconds = template.GoalSeconds[random:NextInteger(1, #template.GoalSeconds)]
		goal = Formulas.ScaledReward(stats, seconds, template.MinGoal or 100)
	else
		goal = template.Goals[random:NextInteger(1, #template.Goals)]
	end

	return {
		Type = template.Type,
		Goal = goal,
		Progress = 0,
		Text = string.format(template.Text, NumberFormatter.Format(goal)),
		Reward = Formulas.ScaledReward(stats, template.RewardSeconds, template.MinReward),
	}
end

local function isValidQuest(quest): boolean
	return type(quest) == "table"
		and type(quest.Type) == "string"
		and validTypes[quest.Type] == true
		and type(quest.Goal) == "number"
		and type(quest.Progress) == "number"
		and type(quest.Text) == "string"
		and type(quest.Reward) == "number"
end

-- Complète la liste des quêtes si nécessaire (nouveau joueur, config modifiée...)
function QuestService:PlayerReady(player: Player, data)
	-- Nettoie les quêtes invalides ou dont le type n'existe plus dans la config
	local cleaned = {}
	for _, quest in ipairs(data.Quests) do
		if isValidQuest(quest) and #cleaned < Config.Quests.ActiveCount then
			table.insert(cleaned, quest)
		end
	end
	data.Quests = cleaned

	while #data.Quests < Config.Quests.ActiveCount do
		table.insert(data.Quests, generateQuest(player, data, data.Quests))
	end
end

-- Remplace toutes les quêtes par des nouvelles (à l'échelle de la production actuelle)
function QuestService:Regenerate(player: Player)
	local data = services.DataService:GetData(player)
	if not data then
		return
	end
	data.Quests = {}
	while #data.Quests < Config.Quests.ActiveCount do
		table.insert(data.Quests, generateQuest(player, data, data.Quests))
	end
	services.GameService:MarkDirty(player)
end

-- Fait avancer les quêtes d'un type donné
function QuestService:Progress(player: Player, questType: string, amount: number)
	local data = services.DataService:GetData(player)
	if not data or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	if not Formulas.HasFeature(data, QUESTS_FEATURE) then
		return -- menu des quêtes pas encore débloqué
	end

	local completed = {}
	for index, quest in ipairs(data.Quests) do
		if quest.Type == questType and quest.Progress < quest.Goal then
			quest.Progress = math.min(quest.Goal, quest.Progress + amount)
			if quest.Progress >= quest.Goal then
				table.insert(completed, index)
			end
		end
	end

	if #completed == 0 then
		return
	end

	-- D'abord on remplace les quêtes terminées, ENSUITE on donne les récompenses
	-- (évite de modifier la liste pendant qu'on la parcourt)
	local rewards = {}
	for _, index in ipairs(completed) do
		local quest = data.Quests[index]
		table.insert(rewards, quest)
		data.Stats.QuestsCompleted += 1
		local others = table.clone(data.Quests)
		table.remove(others, index)
		data.Quests[index] = generateQuest(player, data, others)
	end

	for _, quest in ipairs(rewards) do
		services.GameService:AddDopamine(player, quest.Reward, false)
		services.GameService:Notify(player, {
			Type = "Quest",
			Title = "QUÊTE TERMINÉE !",
			Text = "📜 " .. quest.Text .. "  (+" .. NumberFormatter.Format(quest.Reward) .. ")",
		})
	end
	services.GameService:MarkDirty(player)
end

return QuestService
