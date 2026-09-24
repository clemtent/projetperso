--[[
	Achievements (ModuleScript) — panneau des succès
	Emplacement : ReplicatedStorage > Client > Components > Panels > Achievements

	Chaque succès est un MÉDAILLON (palier bronze / argent / or / diamant
	selon la taille de l'objectif, voir AchievementPopup.Tier) :
	  - débloqué : médaillon en couleur, "✔ Débloqué" et la récompense ;
	  - verrouillé : médaillon gris avec icône fantôme et cadenas, barre de
	    progression (valeur / objectif) ;
	  - pastille "🏅 Badge Roblox" quand le succès donne un vrai badge
	    (Config.Achievements[].BadgeId ~= 0).
	En-tête : progression globale, bonus permanent, nombre de badges.
	Onglets : Tous / Débloqués / À faire.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local AchievementPopup = require(script.Parent.Parent.AchievementPopup)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local Achievements = {
	Title = "🏆 Succès",
	Subtitle = "Chaque succès donne un bonus permanent",
	Color = Theme.Colors.Purple,
	Size = Vector2.new(760, 590),
}

type Item = {
	Achievement: any,
	Cell: Frame,
	Card: Frame,
	Stroke: UIStroke,
	Medallion: AchievementPopup.Medallion,
	Name: TextLabel,
	Status: TextLabel,
	Track: Frame,
	Fill: Frame,
	Done: boolean?,
}

local items: { Item } = {}
local filter = "All"
local summaryLabel: TextLabel
local progressFill: Frame
local bonusChip: Frame
local badgeChip: Frame

local function statValue(data, statName: string): number
	local value = data.Stats and data.Stats[statName]
	if value == nil then
		value = data[statName]
	end
	return (type(value) == "number") and value or 0
end

local function hasBadge(achievement): boolean
	return (tonumber(achievement.BadgeId) or 0) > 0
end

local function setChipText(chip: Frame, text: string)
	local label = chip:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = text
	end
end

local function applyFilter()
	for _, item in ipairs(items) do
		local done = item.Done == true
		item.Cell.Visible = filter == "All" or (filter == "Done" and done) or (filter == "Todo" and not done)
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildHeader(content: Frame)
	local header = UIUtil.Create("Frame", {
		Name = "Summary",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = content,
	})
	UIUtil.Corner(header, Theme.Radius.L)
	UIUtil.Stroke(header, Theme.Colors.Purple, 1.5, 0.55)
	UIUtil.Gradient(header, ColorSequence.new(Color3.fromRGB(250, 244, 255), Color3.fromRGB(236, 222, 255)), 0)

	local trophy = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		BackgroundColor3 = Theme.Colors.Purple,
		Parent = header,
	})
	UIUtil.Corner(trophy, UDim.new(1, 0))
	UIUtil.Gradient(trophy, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)), 90)
	UIUtil.Label({
		Text = "🏆",
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		MaxTextSize = 24,
		Parent = trophy,
	})

	summaryLabel = UIUtil.Label({
		Name = "Count",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -70, 0, 22),
		Position = UDim2.fromOffset(68, 10),
		MaxTextSize = 19,
		Parent = header,
	})
	local track = UIUtil.Create("Frame", {
		Name = "Progress",
		Size = UDim2.new(0.5, -70, 0, 10),
		Position = UDim2.fromOffset(68, 40),
		BackgroundColor3 = Color3.fromRGB(225, 215, 240),
		Parent = header,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	progressFill = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	UIUtil.Corner(progressFill, UDim.new(1, 0))
	UIUtil.Gradient(progressFill, ColorSequence.new(Theme.Colors.Pink, Theme.Colors.Purple), 0)

	local chips = UIUtil.Create("Frame", {
		Name = "Chips",
		Size = UDim2.new(0.5, -12, 0, 26),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		BackgroundTransparency = 1,
		Parent = header,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	bonusChip = UIUtil.Chip({
		Text = "",
		Color = Theme.Colors.Purple,
		TextColor3 = Theme.Colors.TextLight,
		Height = 26,
		TextSize = 13,
		LayoutOrder = 1,
		Parent = chips,
	})
	badgeChip = UIUtil.Chip({
		Text = "",
		Color = Theme.Colors.Robux,
		TextColor3 = Theme.Colors.TextLight,
		Height = 26,
		TextSize = 13,
		LayoutOrder = 2,
		Visible = false,
		Parent = chips,
	})
end

local function buildItem(grid: ScrollingFrame, achievement, order: number)
	local tier = AchievementPopup.Tier(achievement)
	local cell = UIUtil.Create("Frame", {
		Name = tostring(achievement.Id),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = grid,
	})
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.fromOffset(0, 2),
		BackgroundColor3 = Theme.Colors.Card,
		ZIndex = 2,
		Parent = cell,
	})
	UIUtil.Corner(card, Theme.Radius.L)
	local stroke = UIUtil.Stroke(card, Theme.Colors.Divider, 1.5)

	local medallion = AchievementPopup.Medallion(card, 64, achievement)
	medallion.Frame.AnchorPoint = Vector2.new(0.5, 0)
	medallion.Frame.Position = UDim2.new(0.5, 0, 0, 10)
	medallion.Frame.ZIndex = 3

	if hasBadge(achievement) then
		local badge = UIUtil.Chip({
			Name = "Badge",
			Text = "🏅 Badge Roblox",
			Color = Theme.Colors.Robux,
			TextColor3 = Theme.Colors.TextLight,
			Height = 18,
			TextSize = 10,
			ZIndex = 5,
			Parent = card,
		})
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -6, 0, 6)
	end
	local tierChip = UIUtil.Chip({
		Name = "Tier",
		Text = tier.Name,
		Color = tier.Bottom,
		TextColor3 = Theme.ContrastText(tier.Bottom),
		Height = 16,
		TextSize = 10,
		ZIndex = 5,
		Parent = card,
	})
	tierChip.Position = UDim2.fromOffset(6, 6)

	local name = UIUtil.Label({
		Name = "AchievementName",
		Text = tostring(achievement.Name),
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.fromOffset(6, 90),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = card,
	})
	local status = UIUtil.Label({
		Name = "Status",
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -12, 0, 15),
		Position = UDim2.fromOffset(6, 111),
		MaxTextSize = 12,
		ZIndex = 3,
		Parent = card,
	})
	local track = UIUtil.Create("Frame", {
		Name = "Track",
		Size = UDim2.new(1, -24, 0, 6),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		BackgroundColor3 = Theme.Colors.PanelLight,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	local fill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = tier.Bottom,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = track,
	})
	UIUtil.Corner(fill, UDim.new(1, 0))

	-- Survol : léger soulèvement
	card.MouseEnter:Connect(function()
		UIUtil.Tween(card, 0.15, { Position = UDim2.fromOffset(0, -1) })
	end)
	card.MouseLeave:Connect(function()
		UIUtil.Tween(card, 0.15, { Position = UDim2.fromOffset(0, 2) })
	end)

	table.insert(items, {
		Achievement = achievement,
		Cell = cell,
		Card = card,
		Stroke = stroke,
		Medallion = medallion,
		Name = name,
		Status = status,
		Track = track,
		Fill = fill,
		Done = nil,
	})
end

function Achievements.Build(content: Frame)
	buildHeader(content)

	UIUtil.Tabs({
		Parent = content,
		Tabs = {
			{ Id = "All", Text = "🏆 Tous" },
			{ Id = "Done", Text = "✔ Débloqués" },
			{ Id = "Todo", Text = "🎯 À faire" },
		},
		Color = Theme.Colors.Purple,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 72),
		Selected = filter,
		OnSelect = function(id: string)
			filter = id
			applyFilter()
		end,
	})

	local grid = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -114),
		Position = UDim2.fromOffset(0, 114),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.Purple,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 6),
		Parent = grid,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.25, -8, 0, 150),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	for index, achievement in ipairs(Config.Achievements) do
		buildItem(grid, achievement, index)
	end
end

function Achievements.Update(data)
	local unlocked = 0
	local badges, badgesTotal = 0, 0
	local unlockedMap = data.Achievements or {}
	for _, item in ipairs(items) do
		local achievement = item.Achievement
		local done = unlockedMap[achievement.Id] == true
		if done then
			unlocked += 1
		end
		if hasBadge(achievement) then
			badgesTotal += 1
			if done then
				badges += 1
			end
		end
		if item.Done ~= done then
			local wasLocked = item.Done == false
			item.Done = done
			item.Medallion.Set(done)
			if done and wasLocked then
				UIUtil.Pop(item.Card, 1.12, 0.45)
			end
		end
		local tier = AchievementPopup.Tier(achievement)
		if done then
			item.Stroke.Color = tier.Ring
			item.Stroke.Transparency = 0.2
			item.Card.BackgroundColor3 = tier.Top:Lerp(Color3.new(1, 1, 1), 0.75)
			item.Name.TextColor3 = Theme.Colors.Text
			item.Status.Text = "✔ Débloqué  •  🎁 +" .. NumberFormatter.Format(tonumber(achievement.Reward) or 0)
			item.Status.TextColor3 = tier.Ring
			item.Track.Visible = false
		else
			item.Stroke.Color = Theme.Colors.Divider
			item.Stroke.Transparency = 0
			item.Card.BackgroundColor3 = Theme.Colors.Card
			item.Name.TextColor3 = Theme.Colors.TextDim
			local goal = math.max(1, tonumber(achievement.Goal) or 1)
			local value = math.min(statValue(data, achievement.Stat), goal)
			item.Status.Text = NumberFormatter.Format(value) .. " / " .. NumberFormatter.Format(goal)
			item.Status.TextColor3 = Theme.Colors.TextDim
			item.Track.Visible = true
			item.Fill.Size = UDim2.fromScale(math.clamp(value / goal, 0, 1), 1)
		end
	end
	applyFilter()

	local total = #Config.Achievements
	summaryLabel.Text = string.format("%d / %d succès débloqués", unlocked, total)
	progressFill.Size = UDim2.fromScale(total > 0 and unlocked / total or 0, 1)
	setChipText(bonusChip, string.format("📈 Bonus +%d %%", math.floor(unlocked * Config.AchievementBonus * 100 + 0.5)))
	badgeChip.Visible = badgesTotal > 0
	if badgesTotal > 0 then
		setChipText(badgeChip, string.format("🏅 %d / %d badges", badges, badgesTotal))
	end
end

return Achievements
