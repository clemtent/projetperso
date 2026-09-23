--[[
	Quests (ModuleScript) — panneau des quêtes
	Emplacement : ReplicatedStorage > Client > Components > Panels > Quests
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Config = require(ReplicatedStorage.Shared.Config)

local Quests = {
	Title = "📜 QUÊTES",
	Color = Theme.Colors.Green,
}

local cards = {}

function Quests.Build(content: Frame)
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	UIUtil.Label({
		Text = "Termine des quêtes pour gagner des bonus ! Une nouvelle quête remplace chaque quête finie.",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 0,
		MaxTextSize = 16,
		Parent = content,
	})

	for index = 1, Config.Quests.ActiveCount do
		local card = UIUtil.Create("Frame", {
			Size = UDim2.new(1, 0, 0, 100),
			BackgroundColor3 = Theme.Colors.Card,
			LayoutOrder = index,
			Parent = content,
		})
		UIUtil.Corner(card, 16)
		UIUtil.Stroke(card, Theme.Colors.Green, 2, 0.4)

		local text = UIUtil.Label({
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -30, 0, 28),
			Position = UDim2.fromOffset(15, 10),
			MaxTextSize = 20,
			Parent = card,
		})
		local reward = UIUtil.Label({
			TextColor3 = Theme.Colors.Yellow,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -30, 0, 20),
			Position = UDim2.fromOffset(15, 40),
			MaxTextSize = 16,
			Parent = card,
		})

		local bar = UIUtil.Create("Frame", {
			Size = UDim2.new(1, -30, 0, 22),
			Position = UDim2.fromOffset(15, 66),
			BackgroundColor3 = Theme.Colors.Panel,
			ClipsDescendants = true,
			Parent = card,
		})
		UIUtil.Corner(bar, 11)
		local fill = UIUtil.Create("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = bar,
		})
		UIUtil.Corner(fill, 11)
		UIUtil.Gradient(fill, ColorSequence.new(Theme.Colors.Green, Theme.Colors.Cyan), 0)
		local progress = UIUtil.Label({
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			MaxTextSize = 15,
			Parent = bar,
		})

		cards[index] = { Card = card, Text = text, Reward = reward, Fill = fill, Progress = progress }
	end
end

function Quests.Update(data)
	for index, ui in ipairs(cards) do
		local quest = data.Quests[index]
		ui.Card.Visible = quest ~= nil
		if quest then
			ui.Text.Text = quest.Text
			ui.Reward.Text = "🎁 Récompense : +" .. NumberFormatter.Format(quest.Reward)
			local ratio = math.clamp(quest.Progress / quest.Goal, 0, 1)
			UIUtil.Tween(ui.Fill, 0.25, { Size = UDim2.fromScale(ratio, 1) })
			ui.Progress.Text = NumberFormatter.Format(quest.Progress) .. " / " .. NumberFormatter.Format(quest.Goal)
		end
	end
end

return Quests
