--[[
	ScreenTime (ModuleScript) — "Temps d'écran"
	Emplacement : ReplicatedStorage > Client > Components > Panels > ScreenTime

	Combien de temps le joueur a passé ici : session, aujourd'hui, total,
	+ graphique des derniers jours et un petit commentaire (pas très tendre).
	Débloqué par l'amélioration "Temps d'écran" (Feature "ScreenTime").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local ScreenTime = {
	Title = "⏱️ Temps d'écran",
	Subtitle = "Le temps passé ici (on ne juge pas… un peu)",
	Color = Theme.Colors.Dark,
	Size = Vector2.new(660, 520),
}

local DAY_NAMES = { "Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam" } -- index = wday (1 = dimanche)
local MAX_EXTRAPOLATION = 30 -- secondes ajoutées localement entre deux mises à jour

-- Commentaires selon le temps passé aujourd'hui (secondes)
local COMMENTS = {
	{ Limit = 10 * 60, Text = "C'est raisonnable. 🙂", Color = Theme.Colors.Green },
	{ Limit = 30 * 60, Text = "Ça commence à faire beaucoup... 🤔", Color = Theme.Colors.Orange },
	{ Limit = 60 * 60, Text = "Il faudrait peut-être sortir... 🌳", Color = Theme.Colors.Orange },
	{ Limit = 3 * 3600, Text = "Tes yeux ne te remercient pas. 👀", Color = Theme.Colors.Red },
	{ Limit = math.huge, Text = "Tu as un problème. 🚨", Color = Theme.Colors.Red },
}

local valueLabels: { [string]: TextLabel } = {} -- Session / Today / Total
local commentLabel: TextLabel
local bars = {}
local base = { Session = 0, Today = 0, Total = 0 }
local lastUpdateClock = os.clock()
local visible = false

local function statBox(parent: Frame, order: number, title: string): TextLabel
	local box = UIUtil.Create("Frame", {
		Size = UDim2.new(1 / 3, -8, 1, 0),
		BackgroundColor3 = Theme.Colors.PanelLight,
		LayoutOrder = order,
		Parent = parent,
	})
	UIUtil.Corner(box, 12)
	UIUtil.Stroke(box, Theme.Colors.Disabled, 1.5)
	UIUtil.Label({
		Text = title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.fromOffset(6, 8),
		MaxTextSize = 15,
		Parent = box,
	})
	return UIUtil.Label({
		Text = "0s",
		Font = Theme.Fonts.Number,
		Size = UDim2.new(1, -12, 0, 34),
		Position = UDim2.fromOffset(6, 30),
		MaxTextSize = 30,
		Parent = box,
	})
end

local function commentFor(today: number)
	for _, comment in ipairs(COMMENTS) do
		if today < comment.Limit then
			return comment
		end
	end
	return COMMENTS[#COMMENTS]
end

local function refreshTimes()
	local extra = math.min(os.clock() - lastUpdateClock, MAX_EXTRAPOLATION)
	valueLabels.Session.Text = NumberFormatter.Time(base.Session + extra)
	valueLabels.Today.Text = NumberFormatter.Time(base.Today + extra)
	valueLabels.Total.Text = NumberFormatter.Time(base.Total + extra)
	local comment = commentFor(base.Today + extra)
	commentLabel.Text = comment.Text
	commentLabel.TextColor3 = comment.Color
end

function ScreenTime.Build(content: Frame)
	local row = UIUtil.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundTransparency = 1,
		Parent = content,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	valueLabels.Session = statBox(row, 1, "Cette session")
	valueLabels.Today = statBox(row, 2, "Aujourd'hui")
	valueLabels.Total = statBox(row, 3, "Depuis toujours")

	commentLabel = UIUtil.Label({
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 82),
		MaxTextSize = 24,
		Parent = content,
	})

	-- Graphique en barres des derniers jours
	local chart = UIUtil.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 270),
		Position = UDim2.fromOffset(0, 122),
		BackgroundColor3 = Theme.Colors.PanelLight,
		Parent = content,
	})
	UIUtil.Corner(chart, 14)
	UIUtil.Stroke(chart, Theme.Colors.Disabled, 1.5)
	UIUtil.Label({
		Text = "Les " .. Config.ScreenTime.DaysKept .. " derniers jours",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 8),
		MaxTextSize = 15,
		Parent = chart,
	})

	local plot = UIUtil.Create("Frame", {
		Size = UDim2.new(1, -24, 1, -40),
		Position = UDim2.fromOffset(12, 32),
		BackgroundTransparency = 1,
		Parent = chart,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = plot,
	})

	local count = Config.ScreenTime.DaysKept
	for index = 1, count do
		local column = UIUtil.Create("Frame", {
			Size = UDim2.new(1 / count, -10, 1, 0),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = plot,
		})
		local value = UIUtil.Label({
			Text = "",
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 16),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -24),
			MaxTextSize = 12,
			Parent = column,
		})
		local bar = UIUtil.Create("Frame", {
			Size = UDim2.new(0.7, 0, 0, 2),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -24),
			BackgroundColor3 = index == count and Theme.Colors.Red or Theme.Colors.Dark,
			Parent = column,
		})
		UIUtil.Corner(bar, 6)
		local day = UIUtil.Label({
			Text = "",
			Font = Theme.Fonts.Title,
			Size = UDim2.new(1, 0, 0, 20),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			MaxTextSize = 14,
			Parent = column,
		})
		bars[index] = { Bar = bar, Value = value, Day = day }
	end

	-- Le temps défile pendant que la fenêtre est ouverte
	task.spawn(function()
		while content.Parent do
			if visible and content.Visible then
				refreshTimes()
			end
			task.wait(1)
		end
	end)
end

function ScreenTime.OnOpen()
	visible = true
end

function ScreenTime.Update(data)
	local info = data.ScreenTime
	if type(info) ~= "table" then
		return
	end
	base.Session = info.Session or 0
	base.Today = info.Today or 0
	base.Total = info.Total or 0
	lastUpdateClock = os.clock()
	refreshTimes()

	-- Barres (plus ancien -> aujourd'hui)
	local days = info.Days or {}
	local count = #bars
	local maxValue = 60
	for i = 1, count do
		local value = days[#days - count + i] or 0
		maxValue = math.max(maxValue, value)
	end
	local todayWday = (os.date("!*t") :: any).wday or 1
	for i, ui in ipairs(bars) do
		local value = days[#days - count + i] or 0
		if i == count then
			value = math.max(value, base.Today)
		end
		local ratio = math.clamp(value / maxValue, 0, 1)
		ui.Bar.Size = UDim2.new(0.7, 0, math.max(0.01, ratio * 0.78), 0)
		ui.Value.Position = UDim2.new(0, 0, 1 - math.max(0.01, ratio * 0.78), -26)
		ui.Value.Text = value > 0 and NumberFormatter.Time(value) or ""
		local offset = count - i -- jours avant aujourd'hui
		local wday = ((todayWday - 1 - offset) % 7) + 1
		ui.Day.Text = offset == 0 and "Auj." or DAY_NAMES[wday]
	end
end

-- Appelé par PanelManager quand la fenêtre se ferme (pour ne plus rafraîchir)
function ScreenTime.OnClose()
	visible = false
end

-- Accès direct (debug)
function ScreenTime.GetToday(): number
	local data = ClientState.Data
	local info = data and data.ScreenTime
	return (info and info.Today) or 0
end

return ScreenTime
