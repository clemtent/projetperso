--[[
	Leaderboard (ModuleScript) — classement global
	Emplacement : ReplicatedStorage > Client > Components > Panels > Leaderboard
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local Leaderboard = {
	Title = "🥇 Classement mondial",
	Subtitle = "Les plus gros cerveaux du jeu",
	Color = Theme.Colors.Blue,
}

local MEDALS = { "🥇", "🥈", "🥉" }
-- Fond légèrement teinté pour le podium (or, argent, bronze)
local PODIUM_COLORS = {
	Color3.fromRGB(255, 246, 214),
	Color3.fromRGB(240, 242, 246),
	Color3.fromRGB(250, 234, 222),
}
local rows = {}
local emptyLabel: TextLabel

local function refresh(top)
	top = top or {}
	local localId = Players.LocalPlayer.UserId
	for index, row in ipairs(rows) do
		local entry = top[index]
		row.Frame.Visible = entry ~= nil
		if entry then
			local rank = entry.Rank or index
			row.Rank.Text = MEDALS[rank] or ("#" .. tostring(rank))
			row.Name.Text = tostring(entry.Name or "?")
			row.Value.Text = NumberFormatter.Format(entry.Value or 0) .. " 💧"
			local isMe = entry.UserId == localId
			local podium = PODIUM_COLORS[rank]
			row.Frame.BackgroundColor3 = isMe and Color3.fromRGB(225, 240, 255) or (podium or Theme.Colors.PanelLight)
			row.Stroke.Color = isMe and Theme.Colors.Blue or Theme.Colors.Disabled
			row.Name.TextColor3 = isMe and Theme.Colors.Blue or Theme.Colors.Text
		end
	end
	emptyLabel.Visible = #top == 0
end

function Leaderboard.Build(content: Frame)
	UIUtil.Label({
		Text = "Dopamine totale gagnée depuis toujours (mis à jour chaque minute)",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 24),
		MaxTextSize = 16,
		Parent = content,
	})

	local list = UIUtil.Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -32),
		Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Blue,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 2),
		Parent = list,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	for index = 1, Config.Leaderboard.Size do
		local frame = UIUtil.Create("Frame", {
			Size = UDim2.new(1, -12, 0, 38),
			BackgroundColor3 = Theme.Colors.PanelLight,
			LayoutOrder = index,
			Visible = false,
			Parent = list,
		})
		UIUtil.Corner(frame, 10)
		local stroke = UIUtil.Stroke(frame, Theme.Colors.Disabled, 1.5)
		local rank = UIUtil.Label({
			Font = Theme.Fonts.Title,
			Size = UDim2.new(0, 60, 1, -6),
			Position = UDim2.fromOffset(6, 3),
			MaxTextSize = 20,
			Parent = frame,
		})
		local name = UIUtil.Label({
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.55, -70, 1, -8),
			Position = UDim2.fromOffset(70, 4),
			MaxTextSize = 18,
			Parent = frame,
		})
		local value = UIUtil.Label({
			Font = Theme.Fonts.Number,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.45, -14, 1, -8),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 4),
			MaxTextSize = 18,
			Parent = frame,
		})
		rows[index] = { Frame = frame, Stroke = stroke, Rank = rank, Name = name, Value = value }
	end

	emptyLabel = UIUtil.Label({
		Text = "Classement en cours de chargement...\n(Il ne fonctionne que dans un jeu publié avec l'accès aux API activé.)",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(0, 60),
		MaxTextSize = 17,
		Parent = content,
	})

	refresh(ClientState.Leaderboard)
	ClientState.LeaderboardChanged:Connect(refresh)
end

return Leaderboard
