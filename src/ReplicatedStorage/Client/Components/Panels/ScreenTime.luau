--[[
	ScreenTime (ModuleScript) — "Temps d'écran"
	Emplacement : ReplicatedStorage > Client > Components > Panels > ScreenTime

	Combien de temps le joueur a passé ici :
	  - trois cartes (session, aujourd'hui, depuis toujours) avec icône et
	    petite comparaison rigolote ; les compteurs défilent EN DIRECT ;
	  - une pastille de commentaire (pas très tendre) selon aujourd'hui ;
	  - un graphique des derniers jours : barres en dégradé qui poussent à
	    l'ouverture, valeur au-dessus de chaque barre, ligne de moyenne,
	    aujourd'hui mis en valeur.
	Débloqué par l'amélioration "Temps d'écran" (Feature "ScreenTime").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Locale = require(ReplicatedStorage.Shared.Locale)

-- Title / Subtitle en anglais : traduits par PanelManager
local ScreenTime = {
	Title = "⏱️ Screen Time",
	Subtitle = "Time spent here (no judgment… well, a little)",
	Color = Theme.Colors.Dark,
	Size = Vector2.new(660, 540),
}

-- index = wday (1 = dimanche)
local DAY_NAMES = {
	en = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" },
	fr = { "Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam" },
}
local MAX_EXTRAPOLATION = 30 -- secondes ajoutées localement entre deux mises à jour
local PLOT_TOP = 30 -- place au-dessus des barres (valeurs)
local BAR_AREA = 0.78 -- part de la hauteur utile occupée par la plus grande barre

-- Commentaires selon le temps passé aujourd'hui (secondes) ; Text en anglais, traduit à l'affichage
local COMMENTS = {
	{ Limit = 10 * 60, Icon = "🙂", Text = "That's reasonable.", Color = Theme.Colors.Green },
	{ Limit = 30 * 60, Icon = "🤔", Text = "It's starting to add up...", Color = Theme.Colors.Orange },
	{ Limit = 60 * 60, Icon = "🌳", Text = "Maybe go outside for a bit...", Color = Theme.Colors.Orange },
	{ Limit = 3 * 3600, Icon = "👀", Text = "Your eyes are not thanking you.", Color = Theme.Colors.Red },
	{ Limit = math.huge, Icon = "🚨", Text = "You have a problem.", Color = Theme.Colors.Red },
}

type Stat = { Value: TextLabel, Sub: TextLabel }
type Bar = { Column: Frame, Bar: Frame, Gradient: UIGradient, Value: TextLabel, Day: TextLabel, Ratio: number }

local stats: { [string]: Stat } = {} -- Session / Today / Total
local commentChip: Frame
local commentIcon: TextLabel
local commentText: TextLabel
local liveDot: Frame
local bars: { Bar } = {}
local plot: Frame
local averageLine: Frame
local averageLabel: TextLabel
local base = { Session = 0, Today = 0, Total = 0 }
local lastUpdateClock = os.clock()
local lastComment = ""
local visible = false

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function statCard(parent: Frame, order: number, icon: string, title: string, color: Color3): Stat
	local card = UIUtil.Create("Frame", {
		Name = "Stat" .. order,
		Size = UDim2.new(1 / 3, -8, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = parent,
	})
	UIUtil.Corner(card, Theme.Radius.L)
	UIUtil.Stroke(card, color, 1.5, 0.55)
	UIUtil.Gradient(card, ColorSequence.new(Color3.new(1, 1, 1), color:Lerp(Color3.new(1, 1, 1), 0.86)), 90)

	local bubble = UIUtil.Create("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(12, 12),
		BackgroundColor3 = color,
		Parent = card,
	})
	UIUtil.Corner(bubble, UDim.new(1, 0))
	UIUtil.Stroke(bubble, color:Lerp(Color3.new(0, 0, 0), 0.25), 1.5, 0.3)
	UIUtil.Gradient(bubble, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)), 90)
	UIUtil.Label({
		Text = icon,
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		MaxTextSize = 22,
		Parent = bubble,
	})
	UIUtil.Label({
		Text = title,
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -66, 0, 18),
		Position = UDim2.fromOffset(60, 12),
		MaxTextSize = 14,
		Parent = card,
	})
	local value = UIUtil.Label({
		Name = "Value",
		Text = "0s",
		Font = Theme.Fonts.Number,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -66, 0, 28),
		Position = UDim2.fromOffset(60, 30),
		MaxTextSize = 26,
		Parent = card,
	})
	local sub = UIUtil.Label({
		Name = "Sub",
		Text = "",
		TextColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.fromOffset(12, 64),
		MaxTextSize = 13,
		Parent = card,
	})
	return { Value = value, Sub = sub }
end

----------------------------------------------------------------------
-- Mises à jour
----------------------------------------------------------------------

local function commentFor(today: number)
	for _, comment in ipairs(COMMENTS) do
		if today < comment.Limit then
			return comment
		end
	end
	return COMMENTS[#COMMENTS]
end

-- Comparaisons rigolotes sous les compteurs
local function funnyTotal(seconds: number): string
	local films = seconds / (2 * 3600)
	if films >= 1 then
		return Locale.T("≈ %s two-hour movie%s 🎬", NumberFormatter.Format(films, 1), films >= 2 and "s" or "")
	end
	local episodes = seconds / (22 * 60)
	if episodes >= 1 then
		return Locale.T("≈ %s TV episode%s 📺", NumberFormatter.Format(episodes, 1), episodes >= 2 and "s" or "")
	end
	return Locale.T("≈ %s three-second videos 📱", tostring(math.floor(seconds / 3 + 0.5)))
end

local function refreshTimes()
	local extra = math.min(os.clock() - lastUpdateClock, MAX_EXTRAPOLATION)
	local session = base.Session + extra
	local today = base.Today + extra
	local total = base.Total + extra
	stats.Session.Value.Text = NumberFormatter.Time(session)
	stats.Today.Value.Text = NumberFormatter.Time(today)
	stats.Total.Value.Text = NumberFormatter.Time(total)
	stats.Session.Sub.Text = Locale.T("● live since you arrived")
	stats.Today.Sub.Text = Locale.T("%.1f%% of your day", today / 864)
	stats.Total.Sub.Text = funnyTotal(total)

	local comment = commentFor(today)
	commentIcon.Text = comment.Icon
	commentText.Text = Locale.T(comment.Text)
	commentText.TextColor3 = comment.Color:Lerp(Color3.new(0, 0, 0), 0.35)
	commentChip.BackgroundColor3 = comment.Color:Lerp(Color3.new(1, 1, 1), 0.85)
	local stroke = commentChip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = comment.Color
	end
	if comment.Text ~= lastComment then
		lastComment = comment.Text
		UIUtil.Pop(commentChip, 1.15, 0.4)
	end
end

-- Fait pousser les barres (à l'ouverture)
local function growBars()
	for index, ui in ipairs(bars) do
		ui.Bar.Size = UDim2.new(0.62, 0, 0, 0)
		task.delay((index - 1) * 0.04, function()
			UIUtil.Tween(ui.Bar, 0.5, { Size = UDim2.new(0.62, 0, ui.Ratio * BAR_AREA, 0) }, Enum.EasingStyle.Back)
		end)
	end
end

----------------------------------------------------------------------
-- API du panneau
----------------------------------------------------------------------

function ScreenTime.Build(content: Frame)
	local row = UIUtil.Create("Frame", {
		Name = "Stats",
		Size = UDim2.new(1, 0, 0, 90),
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
	stats.Session = statCard(row, 1, "⏳", Locale.T("This session"), Theme.Colors.Blue)
	stats.Today = statCard(row, 2, "📅", Locale.T("Today"), Theme.Colors.Orange)
	stats.Total = statCard(row, 3, "♾️", Locale.T("All time"), Theme.Colors.Purple)

	-- Point "en direct" qui pulse sur la carte Session
	local sessionCard = row:FindFirstChild("Stat1") :: Frame?
	if sessionCard then
		liveDot = UIUtil.Create("Frame", {
			Name = "Live",
			Size = UDim2.fromOffset(8, 8),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 14),
			BackgroundColor3 = Theme.Colors.Red,
			Parent = sessionCard,
		})
		UIUtil.Corner(liveDot, UDim.new(1, 0))
	end

	-- Pastille de commentaire
	commentChip = UIUtil.Create("Frame", {
		Name = "Comment",
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 102),
		BackgroundColor3 = Theme.Colors.PanelLight,
		Parent = content,
	})
	UIUtil.Corner(commentChip, UDim.new(1, 0))
	UIUtil.Stroke(commentChip, Theme.Colors.Green, 1.5, 0.3)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 16),
		Parent = commentChip,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = commentChip,
	})
	commentIcon = UIUtil.Create("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "🙂",
		TextSize = 20,
		LayoutOrder = 1,
		Parent = commentChip,
	})
	commentText = UIUtil.Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = 18,
		LayoutOrder = 2,
		Parent = commentChip,
	})

	-- Graphique en barres des derniers jours
	local chart = UIUtil.Create("Frame", {
		Name = "Chart",
		Size = UDim2.new(1, 0, 1, -150),
		Position = UDim2.fromOffset(0, 150),
		BackgroundColor3 = Theme.Colors.Surface,
		Parent = content,
	})
	UIUtil.Corner(chart, Theme.Radius.L)
	UIUtil.Stroke(chart, Theme.Colors.Divider, 1.5)
	UIUtil.Label({
		Text = Locale.T("📊 Last %s days", tostring(Config.ScreenTime.DaysKept)),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.6, 0, 0, 20),
		Position = UDim2.fromOffset(14, 10),
		MaxTextSize = 16,
		Parent = chart,
	})

	plot = UIUtil.Create("Frame", {
		Name = "Plot",
		Size = UDim2.new(1, -28, 1, -(36 + 26)),
		Position = UDim2.fromOffset(14, 36),
		BackgroundTransparency = 1,
		Parent = chart,
	})
	-- Lignes de repère discrètes
	for k = 1, 3 do
		UIUtil.Create("Frame", {
			Name = "Guide" .. k,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 1 - BAR_AREA * k / 3),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.Colors.Divider,
			BorderSizePixel = 0,
			Parent = plot,
		})
	end
	-- Ligne de moyenne (pointillés) + étiquette
	averageLine = UIUtil.Create("Frame", {
		Name = "Average",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = plot,
	})
	for k = 0, 39 do
		UIUtil.Create("Frame", {
			Position = UDim2.fromScale(k / 40, 0),
			Size = UDim2.new(1 / 80, 0, 1, 0),
			BackgroundColor3 = Theme.Colors.Purple,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = averageLine,
		})
	end
	-- Étiquette de la moyenne : en haut à droite du graphique (légende), jamais
	-- sur les valeurs des barres (la ligne peut passer à leur hauteur)
	averageLabel = UIUtil.Create("TextLabel", {
		Name = "AverageLabel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 11),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Purple,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = Theme.Colors.TextLight,
		TextSize = 12,
		ZIndex = 4,
		Visible = false,
		Parent = chart,
	})
	UIUtil.Corner(averageLabel, UDim.new(1, 0))
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		Parent = averageLabel,
	})

	local columns = UIUtil.Create("Frame", {
		Name = "Columns",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = plot,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = columns,
	})

	local count = Config.ScreenTime.DaysKept
	for index = 1, count do
		local column = UIUtil.Create("Frame", {
			Name = "Day" .. index,
			Size = UDim2.new(1 / count, -8, 1, 0),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			ZIndex = 2,
			Parent = columns,
		})
		local isToday = index == count
		local color = isToday and Theme.Colors.Pink or Theme.Colors.Blue
		local bar = UIUtil.Create("Frame", {
			Name = "Bar",
			Size = UDim2.new(0.62, 0, 0, 0),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 2,
			Parent = column,
		})
		UIUtil.Corner(bar, 8)
		local gradient = UIUtil.Gradient(bar, ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color), 90)
		local value = UIUtil.Create("TextLabel", {
			Name = "Value",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, -3),
			Size = UDim2.fromOffset(80, 14),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = "",
			TextColor3 = isToday and Theme.Colors.Pink:Lerp(Color3.new(0, 0, 0), 0.3) or Theme.Colors.TextDim,
			TextSize = 12,
			ZIndex = 3,
			Parent = bar,
		})
		local day = UIUtil.Label({
			Name = "DayName",
			Text = "",
			Font = Theme.Fonts.Title,
			TextColor3 = isToday and Theme.Colors.Pink:Lerp(Color3.new(0, 0, 0), 0.3) or Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 18),
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0, 0, 1, 4),
			MaxTextSize = 13,
			ZIndex = 2,
			Parent = column,
		})
		bars[index] = { Column = column, Bar = bar, Gradient = gradient, Value = value, Day = day, Ratio = 0 }
	end
	-- (la zone des barres laisse la place aux valeurs au-dessus)
	plot.Size = UDim2.new(1, -28, 1, -(36 + 26 + PLOT_TOP))
	plot.Position = UDim2.fromOffset(14, 36 + PLOT_TOP)

	-- Le temps défile pendant que la fenêtre est ouverte (+ point "en direct")
	task.spawn(function()
		local blink = false
		while content.Parent do
			if visible and content.Visible then
				refreshTimes()
				blink = not blink
				if liveDot then
					UIUtil.Tween(liveDot, 0.4, { BackgroundTransparency = blink and 0 or 0.7 })
				end
			end
			task.wait(1)
		end
	end)
end

function ScreenTime.OnOpen()
	visible = true
	if stats.Session then
		refreshTimes()
		growBars()
	end
end

function ScreenTime.Update(data)
	local info = data.ScreenTime
	if type(info) ~= "table" or not stats.Session then
		return
	end
	base.Session = tonumber(info.Session) or 0
	base.Today = tonumber(info.Today) or 0
	base.Total = tonumber(info.Total) or 0
	lastUpdateClock = os.clock()
	refreshTimes()

	-- Barres (plus ancien -> aujourd'hui)
	local days = type(info.Days) == "table" and info.Days or {}
	local count = #bars
	local values = {}
	local maxValue = 60
	local sum, nonZero = 0, 0
	for i = 1, count do
		local value = tonumber(days[#days - count + i]) or 0
		if i == count then
			value = math.max(value, base.Today)
		end
		values[i] = value
		maxValue = math.max(maxValue, value)
		if value > 0 then
			sum += value
			nonZero += 1
		end
	end
	local todayWday = (os.date("!*t") :: any).wday or 1
	for i, ui in ipairs(bars) do
		local value = values[i]
		local ratio = math.clamp(value / maxValue, 0, 1)
		if value > 0 then
			ratio = math.max(ratio, 0.03)
		end
		ui.Ratio = ratio
		-- Mise à jour douce (sauf pendant l'animation d'ouverture)
		ui.Bar.Size = UDim2.new(0.62, 0, ratio * BAR_AREA, 0)
		ui.Value.Text = value > 0 and NumberFormatter.Time(value) or ""
		local offset = count - i -- jours avant aujourd'hui
		local wday = ((todayWday - 1 - offset) % 7) + 1
		ui.Day.Text = offset == 0 and Locale.T("Today") or Locale.Pick(DAY_NAMES)[wday]
	end

	-- Moyenne des jours joués
	local average = nonZero > 0 and sum / nonZero or 0
	averageLine.Visible = average > 0
	averageLabel.Visible = average > 0
	if average > 0 then
		averageLine.Position = UDim2.fromScale(0, 1 - math.clamp(average / maxValue, 0, 1) * BAR_AREA)
		averageLabel.Text = Locale.T("Average %s", NumberFormatter.Time(average))
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
