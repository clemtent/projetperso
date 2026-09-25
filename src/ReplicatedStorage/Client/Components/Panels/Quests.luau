--[[
	Quests (ModuleScript) — panneau des quêtes
	Emplacement : ReplicatedStorage > Client > Components > Panels > Quests

	Les quêtes actives (une quête finie est remplacée tout de suite).
	v5 : le texte d'une quête est rendu ici dans la langue du joueur à
	partir de Config.Quests.Pool (même Type) + objectif ; à défaut, le
	texte envoyé par le serveur (quest.Text).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)

-- Title / Subtitle en anglais : traduits par PanelManager
local Quests = {
	Title = "📜 Quests",
	Subtitle = "Current goals",
	Color = Theme.Colors.Orange,
}

-- Modèles de quêtes par Type (Config.Quests.Pool)
local templatesByType: { [string]: any } = {}
for _, template in ipairs(Config.Quests.Pool) do
	if type(template.Type) == "string" then
		templatesByType[template.Type] = template
	end
end

-- Texte d'une quête dans la langue du joueur ("Click 50 times" / "Fais 50 clics")
local function questText(quest): string
	local template = type(quest.Type) == "string" and templatesByType[quest.Type] or nil
	local goal = tonumber(quest.Goal)
	if template and type(template.Text) == "string" and goal then
		return Locale.T(template.Text, NumberFormatter.Format(goal))
	end
	return tostring(quest.Text or "")
end

local cards = {}
local emptyLabel: TextLabel

function Quests.Build(content: Frame)
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	UIUtil.Label({
		Text = Locale.T("Complete quests to earn bonuses! A new quest replaces each finished one."),
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
		UIUtil.Corner(card, 14)
		UIUtil.Stroke(card, Theme.Colors.CardBorder, 1.5)

		local text = UIUtil.Label({
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -30, 0, 28),
			Position = UDim2.fromOffset(15, 10),
			MaxTextSize = 20,
			Parent = card,
		})
		local reward = UIUtil.Label({
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -30, 0, 20),
			Position = UDim2.fromOffset(15, 40),
			MaxTextSize = 16,
			Parent = card,
		})

		local bar = UIUtil.Create("Frame", {
			Size = UDim2.new(1, -30, 0, 22),
			Position = UDim2.fromOffset(15, 66),
			BackgroundColor3 = Theme.Colors.PanelLight,
			ClipsDescendants = true,
			Parent = card,
		})
		UIUtil.Corner(bar, 11)
		UIUtil.Stroke(bar, Theme.Colors.CardBorder, 1, 0.5)
		local fill = UIUtil.Create("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = bar,
		})
		UIUtil.Corner(fill, 11)
		UIUtil.Gradient(fill, ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.Orange), 0)
		local progress = UIUtil.Label({
			Font = Theme.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			MaxTextSize = 15,
			Parent = bar,
		})

		cards[index] = { Card = card, Text = text, Reward = reward, Fill = fill, Progress = progress }
	end

	emptyLabel = UIUtil.Label({
		Text = Locale.T("No quests for now..."),
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 99,
		Visible = false,
		MaxTextSize = 18,
		Parent = content,
	})
end

function Quests.Update(data)
	local quests = data.Quests or {}
	for index, ui in ipairs(cards) do
		local quest = quests[index]
		ui.Card.Visible = quest ~= nil
		if quest then
			ui.Text.Text = questText(quest)
			ui.Reward.Text = Locale.T("🎁 Reward: +%s Dopamine", NumberFormatter.Format(quest.Reward or 0))
			local goal = math.max(1, quest.Goal or 1)
			local ratio = math.clamp((quest.Progress or 0) / goal, 0, 1)
			UIUtil.Tween(ui.Fill, 0.25, { Size = UDim2.fromScale(ratio, 1) })
			ui.Progress.Text = NumberFormatter.Format(quest.Progress or 0) .. " / " .. NumberFormatter.Format(goal)
		end
	end
	emptyLabel.Visible = #quests == 0
end

return Quests
