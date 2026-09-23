--[[
	SideMenu (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > SideMenu

	Colonne de boutons à gauche : Quêtes, Succès, Rebirth, Cadeau,
	Classement, Paramètres. Une pastille rouge "!" signale ce qui est
	disponible (cadeau à récupérer, rebirth possible).
]]

local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local PanelManager = require(script.Parent.PanelManager)

local SideMenu = {}

local ENTRIES = {
	{ Panel = "Quests", Icon = "📜", Label = "Quêtes", Color = Theme.Colors.Green },
	{ Panel = "Achievements", Icon = "🏆", Label = "Succès", Color = Theme.Colors.Yellow },
	{ Panel = "Rebirth", Icon = "♻️", Label = "Rebirth", Color = Theme.Colors.Pink },
	{ Panel = "Daily", Icon = "🎁", Label = "Cadeau", Color = Theme.Colors.Orange },
	{ Panel = "Leaderboard", Icon = "🥇", Label = "Top", Color = Theme.Colors.Cyan },
	{ Panel = "Settings", Icon = "⚙️", Label = "Options", Color = Theme.Colors.Purple },
}

local badges = {} -- [panel] = Frame

function SideMenu.Build(parent: Frame)
	local column = UIUtil.Create("Frame", {
		Name = "SideMenu",
		Size = UDim2.fromOffset(84, 6 * 76 + 5 * 8),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 36),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = column,
	})

	for index, entry in ipairs(ENTRIES) do
		local button = UIUtil.NeonButton({
			Name = entry.Panel,
			Size = UDim2.fromOffset(84, 76),
			Color = Theme.Colors.Panel,
			StrokeColor = entry.Color,
			LayoutOrder = index,
			CornerRadius = 18,
			Parent = column,
		})
		UIUtil.Label({
			Text = entry.Icon,
			Size = UDim2.new(1, 0, 0, 38),
			Position = UDim2.fromOffset(0, 2),
			MaxTextSize = 34,
			Parent = button,
		})
		UIUtil.Label({
			Text = entry.Label,
			TextColor3 = entry.Color,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 44),
			MaxTextSize = 14,
			Parent = button,
		})
		button.Activated:Connect(function()
			PanelManager.Toggle(entry.Panel)
		end)

		-- Pastille de notification
		local badge = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(22, 22),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			BackgroundColor3 = Theme.Colors.Red,
			Visible = false,
			ZIndex = 3,
			Parent = button,
		})
		UIUtil.Corner(badge, UDim.new(1, 0))
		UIUtil.Stroke(badge, Color3.new(1, 1, 1), 2)
		UIUtil.Label({ Text = "!", Size = UDim2.fromScale(1, 1), ZIndex = 4, MaxTextSize = 16, Parent = badge })
		badges[entry.Panel] = badge
	end

	-- Pastilles selon l'état
	ClientState.Changed:Connect(function(data)
		badges.Daily.Visible = data.Daily.Available
		badges.Rebirth.Visible = data.Dopamine >= data.RebirthCost
	end)

	-- Les pastilles rebondissent pour attirer l'œil
	RunService.RenderStepped:Connect(function()
		local offset = math.abs(math.sin(os.clock() * 5)) * 4
		for _, badge in pairs(badges) do
			if badge.Visible then
				badge.Position = UDim2.new(1, -4, 0, 4 - offset)
			end
		end
	end)
end

return SideMenu
