--[[
	Achievements (ModuleScript) — panneau des succès
	Emplacement : ReplicatedStorage > Client > Components > Panels > Achievements
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local Achievements = {
	Title = "🏆 SUCCÈS",
	Color = Theme.Colors.Yellow,
}

local header: TextLabel
local items = {}

local function statValue(data, statName: string): number
	local value = data.Stats[statName]
	if value == nil then
		value = data[statName]
	end
	return (type(value) == "number") and value or 0
end

function Achievements.Build(content: Frame)
	header = UIUtil.Label({
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 26),
		MaxTextSize = 17,
		Parent = content,
	})

	local list = UIUtil.Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -34),
		Position = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Yellow,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = content,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 74),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	for index, achievement in ipairs(Config.Achievements) do
		local card = UIUtil.Create("Frame", {
			BackgroundColor3 = Theme.Colors.Card,
			LayoutOrder = index,
			Parent = list,
		})
		UIUtil.Corner(card, 14)
		local stroke = UIUtil.Stroke(card, Theme.Colors.Disabled, 2)

		local icon = UIUtil.Label({
			Text = achievement.Icon,
			Size = UDim2.fromOffset(50, 50),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			MaxTextSize = 36,
			Parent = card,
		})
		local name = UIUtil.Label({
			Text = achievement.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -70, 0, 22),
			Position = UDim2.fromOffset(62, 8),
			MaxTextSize = 16,
			Parent = card,
		})
		local progress = UIUtil.Label({
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -70, 0, 18),
			Position = UDim2.fromOffset(62, 30),
			MaxTextSize = 13,
			Parent = card,
		})
		UIUtil.Label({
			Text = "🎁 +" .. NumberFormatter.Format(achievement.Reward),
			TextColor3 = Theme.Colors.Yellow,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -70, 0, 16),
			Position = UDim2.fromOffset(62, 50),
			MaxTextSize = 13,
			Parent = card,
		})

		items[achievement.Id] = { Stroke = stroke, Icon = icon, Name = name, Progress = progress, Achievement = achievement }
	end
end

function Achievements.Update(data)
	local unlocked = 0
	for id, ui in pairs(items) do
		local achievement = ui.Achievement
		local done = data.Achievements[id] == true
		if done then
			unlocked += 1
			ui.Stroke.Color = Theme.Colors.Yellow
			ui.Icon.TextTransparency = 0
			ui.Name.TextColor3 = Theme.Colors.Yellow
			ui.Progress.Text = "✔ Débloqué"
		else
			ui.Stroke.Color = Theme.Colors.Disabled
			ui.Icon.TextTransparency = 0.6
			ui.Name.TextColor3 = Theme.Colors.TextDim
			local value = math.min(statValue(data, achievement.Stat), achievement.Goal)
			ui.Progress.Text = NumberFormatter.Format(value) .. " / " .. NumberFormatter.Format(achievement.Goal)
		end
	end
	header.Text = string.format(
		"%d / %d débloqués  •  bonus permanent +%d %%",
		unlocked,
		#Config.Achievements,
		math.floor(unlocked * Config.AchievementBonus * 100 + 0.5)
	)
end

return Achievements
