--[[
	Achievements (ModuleScript) — panneau des succès
	Emplacement : ReplicatedStorage > Client > Components > Panels > Achievements

	Grille de tous les succès (débloqués en couleur, les autres grisés avec
	leur progression). Chaque succès donne un bonus permanent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local Achievements = {
	Title = "🏆 Succès",
	Subtitle = "Chaque succès donne un bonus permanent",
	Color = Theme.Colors.Purple,
}

local header: TextLabel
local items = {}

local function statValue(data, statName: string): number
	local value = data.Stats and data.Stats[statName]
	if value == nil then
		value = data[statName]
	end
	return (type(value) == "number") and value or 0
end

function Achievements.Build(content: Frame)
	header = UIUtil.Label({
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 24),
		MaxTextSize = 17,
		Parent = content,
	})

	local list = UIUtil.Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -32),
		Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Purple,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 4),
		Parent = list,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 72),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	for index, achievement in ipairs(Config.Achievements) do
		local card = UIUtil.Create("Frame", {
			BackgroundColor3 = Theme.Colors.PanelLight,
			LayoutOrder = index,
			Parent = list,
		})
		UIUtil.Corner(card, 12)
		local stroke = UIUtil.Stroke(card, Theme.Colors.Disabled, 1.5)

		local icon = UIUtil.Label({
			Text = achievement.Icon,
			Size = UDim2.fromOffset(48, 48),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			MaxTextSize = 34,
			Parent = card,
		})
		local name = UIUtil.Label({
			Text = achievement.Name,
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -70, 0, 22),
			Position = UDim2.fromOffset(62, 7),
			MaxTextSize = 17,
			Parent = card,
		})
		local progress = UIUtil.Label({
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -70, 0, 18),
			Position = UDim2.fromOffset(62, 29),
			MaxTextSize = 14,
			Parent = card,
		})
		UIUtil.Label({
			Text = "🎁 +" .. NumberFormatter.Format(achievement.Reward),
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -70, 0, 16),
			Position = UDim2.fromOffset(62, 49),
			MaxTextSize = 13,
			Parent = card,
		})

		items[achievement.Id] = { Card = card, Stroke = stroke, Icon = icon, Name = name, Progress = progress, Achievement = achievement }
	end
end

function Achievements.Update(data)
	local unlocked = 0
	for id, ui in pairs(items) do
		local achievement = ui.Achievement
		local done = data.Achievements and data.Achievements[id] == true
		if done then
			unlocked += 1
			ui.Card.BackgroundColor3 = Color3.fromRGB(245, 235, 255)
			ui.Stroke.Color = Theme.Colors.Purple
			ui.Stroke.Thickness = 2
			ui.Icon.TextTransparency = 0
			ui.Name.TextColor3 = Theme.Colors.Purple
			ui.Progress.Text = "✔ Débloqué"
		else
			ui.Card.BackgroundColor3 = Theme.Colors.PanelLight
			ui.Stroke.Color = Theme.Colors.Disabled
			ui.Stroke.Thickness = 1.5
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
