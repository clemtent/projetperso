--[[
	RaceHud (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > RaceHud

	🏁 Interface des courses de rue (v10, RACE10) : ScreenGui "RaceGui"
	(gardée visible en ville : KEEP_GUIS), piloté par RaceClient.
	  - bouton rond 🏁 au volant (hors course) : ouvre le MENU ;
	  - MENU "🏁 Courses de rue" : 4 cartes (aperçu du tracé, tours,
	    longueur, record du serveur, ton meilleur temps, état : libre /
	    N inscrits + départ dans X s / course en cours), bouton S'inscrire,
	    courses récompensées aujourd'hui ;
	  - SALLE D'ATTENTE (bandeau en haut) : parcours, inscrits, départ dans
	    X s, bouton Quitter ;
	  - EN COURSE : place (grand), tour, chrono, écart avec la voiture de
	    devant, meilleur tour ; FLÈCHE vers la prochaine porte (+ porte n / N,
	    distance) ; MINI-CARTE (tracé + points des coureurs) ; boutons 🔄 porte
	    (F) et 🏳️ abandon ; 3-2-1-GO géant, "MAUVAIS SENS", flash des portes ;
	  - RÉSULTATS : podium animé (colonnes qui montent l'une après l'autre,
	    photos, temps), classement complet, ta récompense, confettis.
	Ordinateur + téléphone (UIScale, disposition resserrée sur téléphone).

	API (RaceClient) :
	  RaceHud.Build(callbacks)  { Join(routeId), Leave(), Reset(), Menu(open) }
	  RaceHud.Destroy()
	  RaceHud.SetRaceButton(visible)
	  RaceHud.SetMenu(open, cards?, info?)   cards = { { Id, Name, Icon, Desc, Laps, Km, Record, Best, Status, StatusColor, CanJoin, Joined, Preview } }
	  RaceHud.SetLobby(info?)                { Title, Text }
	  RaceHud.SetRace(info?)                 { Place, Count, Lap, Laps, Time, Gap, Best, Cp, Cps, Arrow (deg), Dist, Wrong }
	  RaceHud.SetMinimap(points?, dots?)     points = { { u, v } } (0..1) ; dots = { { u, v, color, me } }
	  RaceHud.Countdown(text, color?)        gros texte qui "pop"
	  RaceHud.Flash(text, color?)
	  RaceHud.ShowResults(res) / RaceHud.HideResults()
	  RaceHud.IsMenuOpen() / RaceHud.Debug()
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local RaceHud = {}

RaceHud.GUI_NAME = "RaceGui"

local rgb = Color3.fromRGB
local INK = rgb(34, 26, 44)
local PANEL = rgb(40, 30, 56)
local PANEL2 = rgb(58, 44, 80)
local WHITE = rgb(255, 255, 255)
local PINK = rgb(255, 110, 170)
local PINK_DEEP = rgb(236, 72, 140)
local GOLD = rgb(255, 204, 60)
local SILVER = rgb(206, 212, 224)
local BRONZE = rgb(222, 152, 96)
local MINT = rgb(110, 226, 170)
local CYAN = rgb(90, 220, 240)
local RED = rgb(240, 70, 80)
local SOFT = rgb(214, 196, 236)

local gui: ScreenGui? = nil
local parts: { [string]: any } = {}
local callbacks: { [string]: any } = {}
local conns: { RBXScriptConnection } = {}
local phone = false
local menuOpen = false
local countdownTween: Tween? = nil
local flashToken = 0
local resultsToken = 0

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = props.Font or Theme.Fonts.Title
	l.TextColor3 = props.Color or WHITE
	l.TextSize = props.TextSize or 18
	l.TextWrapped = props.Wrap == true
	l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Center
	l.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
	l.Text = props.Text or ""
	l.Name = props.Name or "Label"
	l.Size = props.Size or UDim2.fromScale(1, 1)
	l.Position = props.Position or UDim2.new()
	l.AnchorPoint = props.AnchorPoint or Vector2.zero
	l.ZIndex = props.ZIndex or 2
	l.RichText = props.Rich == true
	if props.Scaled then
		l.TextScaled = true
		UIUtil.Create("UITextSizeConstraint", { MaxTextSize = props.TextSize or 18, MinTextSize = 8, Parent = l })
	end
	l.Parent = props.Parent
	return l
end

local function box(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Name = props.Name or "Box"
	f.BackgroundColor3 = props.Color or PANEL
	f.BackgroundTransparency = props.Transparency or 0
	f.Size = props.Size or UDim2.fromScale(1, 1)
	f.Position = props.Position or UDim2.new()
	f.AnchorPoint = props.AnchorPoint or Vector2.zero
	f.ZIndex = props.ZIndex or 1
	f.Visible = props.Visible ~= false
	f.ClipsDescendants = props.Clip == true
	if props.Radius then
		UIUtil.Corner(f, props.Radius)
	end
	if props.Stroke then
		UIUtil.Stroke(f, props.Stroke, props.StrokeThickness or 2)
	end
	f.Parent = props.Parent
	return f
end

local function button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.Name = props.Name or "Button"
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = props.Color or PINK_DEEP
	b.Size = props.Size or UDim2.fromOffset(120, 40)
	b.Position = props.Position or UDim2.new()
	b.AnchorPoint = props.AnchorPoint or Vector2.zero
	b.Font = Theme.Fonts.Title
	b.TextColor3 = props.TextColor or WHITE
	b.TextSize = props.TextSize or 18
	b.Text = props.Text or ""
	b.ZIndex = props.ZIndex or 3
	b.Visible = props.Visible ~= false
	UIUtil.Corner(b, props.Radius or UDim.new(0, 12))
	if props.Stroke ~= false then
		UIUtil.Stroke(b, props.StrokeColor or WHITE, 2, 0.35)
	end
	b.Parent = props.Parent
	pcall(UIUtil.AnimateButton, b)
	return b
end

-- Damier (bandeau décoratif)
local function checker(parent: Instance, cols: number, rows: number, z: number)
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			box({ Name = "Sq", Parent = parent, Color = if (i + j) % 2 == 0 then INK else WHITE, Size = UDim2.fromScale(1 / cols, 1 / rows),
				Position = UDim2.fromScale(i / cols, j / rows), ZIndex = z })
		end
	end
end

-- Ligne brisée dessinée avec des Frames (points en 0..1 dans `holder`)
local function drawLine(holder: Frame, points: { { number } }, color: Color3, thickness: number, z: number, closed: boolean?)
	for _, child in ipairs(holder:GetChildren()) do
		if child.Name == "Seg" then
			child:Destroy()
		end
	end
	-- (tailles en pixels "design" : le support a une taille fixe en offset)
	local w = math.max(4, holder.Size.X.Offset)
	local h = math.max(4, holder.Size.Y.Offset)
	local n = #points
	local last = if closed then n else n - 1
	for i = 1, last do
		local a = points[i]
		local b = points[(i % n) + 1]
		local ax, ay = a[1] * w, a[2] * h
		local bx, by = b[1] * w, b[2] * h
		local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
		if len > 0.5 then
			local seg = box({ Name = "Seg", Parent = holder, Color = color, AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(len + thickness * 0.6, thickness), Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2), ZIndex = z })
			seg.Rotation = math.deg(math.atan2(by - ay, bx - ax))
			UIUtil.Corner(seg, UDim.new(1, 0))
		end
	end
	-- départ : drapeau à damier
	local start = holder:FindFirstChild("Start")
	if not start then
		start = label({ Name = "Start", Parent = holder, Text = "🏁", TextSize = 14, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(18, 18), ZIndex = z + 1 })
	end
	if points[1] then
		start.Position = UDim2.fromOffset(points[1][1] * w + 5, points[1][2] * h)
	end
end
RaceHud.DrawLine = drawLine

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildMenu(root: Frame)
	local dim = box({ Name = "MenuDim", Parent = root, Color = rgb(0, 0, 0), Transparency = 0.45, Visible = false, ZIndex = 20 })
	UIUtil.SinkClicks(dim)
	local panel = box({ Name = "Menu", Parent = dim, Color = PANEL, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(800, 470), Radius = UDim.new(0, 22), Stroke = PINK, StrokeThickness = 3, ZIndex = 21 })
	panel.BackgroundColor3 = WHITE
	UIUtil.Gradient(panel, ColorSequence.new(PANEL2, PANEL), 90)
	local band = box({ Name = "Band", Parent = panel, Transparency = 1, Size = UDim2.new(1, -44, 0, 10), Position = UDim2.fromOffset(22, 8), ZIndex = 22, Clip = true })
	checker(band, 60, 2, 22)
	label({ Name = "Title", Parent = panel, Text = T("🏁 Street races"), TextSize = 32, Size = UDim2.new(1, -120, 0, 40), Position = UDim2.fromOffset(24, 22),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 22 })
	local sub = label({ Name = "Sub", Parent = panel, Text = "", Font = Theme.Fonts.Body, TextSize = 16, Color = SOFT, Size = UDim2.new(1, -120, 0, 22),
		Position = UDim2.fromOffset(26, 62), XAlign = Enum.TextXAlignment.Left, ZIndex = 22 })
	local close = UIUtil.CloseButton({ Name = "CloseRace", Size = 40, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 20), ZIndex = 24 })
	close.Parent = panel
	close.Activated:Connect(function()
		if callbacks.Menu then
			callbacks.Menu(false)
		end
	end)
	local list = box({ Name = "Cards", Parent = panel, Transparency = 1, Size = UDim2.new(1, -32, 1, -150), Position = UDim2.fromOffset(16, 96), ZIndex = 22 })
	local grid = UIUtil.Create("UIGridLayout", { CellSize = UDim2.fromOffset(183, 306), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = list })
	local foot = label({ Name = "Foot", Parent = panel, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Color = SOFT, Size = UDim2.new(1, -40, 0, 34),
		Position = UDim2.new(0, 20, 1, -46), Wrap = true, ZIndex = 22 })
	parts.MenuDim = dim
	parts.Menu = panel
	parts.MenuSub = sub
	parts.Cards = list
	parts.CardGrid = grid
	parts.MenuFoot = foot
	parts.CardList = {}
end

local function buildCard(parent: Instance, order: number): { [string]: any }
	local card = box({ Name = "Card" .. order, Parent = parent, Color = rgb(28, 22, 40), Radius = UDim.new(0, 16), Stroke = rgb(120, 90, 160), ZIndex = 23 })
	card.LayoutOrder = order
	local map = box({ Name = "Map", Parent = card, Color = rgb(52, 70, 60), Size = UDim2.new(1, -20, 0, 96), Position = UDim2.fromOffset(10, 10), Radius = UDim.new(0, 10), ZIndex = 24, Clip = true })
	map.BackgroundColor3 = WHITE
	UIUtil.Gradient(map, ColorSequence.new(rgb(74, 108, 86), rgb(46, 66, 58)), 90)
	local lineHolder = box({ Name = "Line", Parent = map, Transparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(80, 80),
		Position = UDim2.fromScale(0.5, 0.5), ZIndex = 25 })
	local icon = label({ Name = "Icon", Parent = card, Text = "", TextSize = 30, Size = UDim2.fromOffset(40, 36), Position = UDim2.fromOffset(8, 112), ZIndex = 24 })
	local name = label({ Name = "Name", Parent = card, Text = "", TextSize = 18, Size = UDim2.new(1, -54, 0, 36), Position = UDim2.fromOffset(48, 112), XAlign = Enum.TextXAlignment.Left,
		Scaled = true, ZIndex = 24 })
	local info = label({ Name = "Info", Parent = card, Text = "", Font = Theme.Fonts.Body, TextSize = 14, Color = SOFT, Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 148),
		Wrap = true, Scaled = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, ZIndex = 24 })
	local record = label({ Name = "Record", Parent = card, Text = "", Font = Theme.Fonts.Body, TextSize = 14, Color = GOLD, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 184),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, ZIndex = 24 })
	local best = label({ Name = "Best", Parent = card, Text = "", Font = Theme.Fonts.Body, TextSize = 14, Color = MINT, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 204),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, ZIndex = 24 })
	local status = label({ Name = "Status", Parent = card, Text = "", Font = Theme.Fonts.Title, TextSize = 14, Color = WHITE, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 228),
		Scaled = true, ZIndex = 24 })
	local join = button({ Name = "Join", Parent = card, Text = T("Join"), Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 1, -50), ZIndex = 25 })
	return { Card = card, Map = map, Line = lineHolder, Icon = icon, Name = name, Info = info, Record = record, Best = best, Status = status, Join = join, Id = "" }
end

local function buildRaceHud(root: Frame)
	-- place / tour / chrono (en haut à gauche)
	local panel = box({ Name = "RacePanel", Parent = root, Color = PANEL, Transparency = 0.12, Size = UDim2.fromOffset(250, 112), Position = UDim2.fromOffset(12, 108),
		Radius = UDim.new(0, 18), Stroke = PINK, Visible = false, ZIndex = 5 })
	local place = label({ Name = "Place", Parent = panel, Text = "1", Font = Theme.Fonts.Number, TextSize = 56, Size = UDim2.fromOffset(70, 60), Position = UDim2.fromOffset(8, 2), ZIndex = 6 })
	UIUtil.Create("UIStroke", { Color = INK, Thickness = 2, Parent = place })
	local count = label({ Name = "Count", Parent = panel, Text = "/4", Font = Theme.Fonts.Number, TextSize = 24, Color = SOFT, Size = UDim2.fromOffset(46, 30),
		Position = UDim2.fromOffset(70, 30), XAlign = Enum.TextXAlignment.Left, ZIndex = 6 })
	local lap = label({ Name = "Lap", Parent = panel, Text = "", TextSize = 18, Size = UDim2.fromOffset(120, 24), Position = UDim2.fromOffset(122, 6), XAlign = Enum.TextXAlignment.Left, ZIndex = 6 })
	local time = label({ Name = "Time", Parent = panel, Text = "0:00.00", Font = Theme.Fonts.Number, TextSize = 26, Color = GOLD, Size = UDim2.fromOffset(124, 30),
		Position = UDim2.fromOffset(120, 28), XAlign = Enum.TextXAlignment.Left, ZIndex = 6 })
	local gap = label({ Name = "Gap", Parent = panel, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Color = SOFT, Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(12, 62), XAlign = Enum.TextXAlignment.Left, Scaled = true, ZIndex = 6 })
	local bestLap = label({ Name = "BestLap", Parent = panel, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Color = MINT, Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(12, 84), XAlign = Enum.TextXAlignment.Left, ZIndex = 6 })
	-- flèche vers la prochaine porte (en haut au milieu, sous le compteur)
	local arrowBox = box({ Name = "Arrow", Parent = root, Color = PANEL, Transparency = 0.15, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(230, 44),
		Position = UDim2.new(0.5, 0, 0, 112), Radius = UDim.new(1, 0), Stroke = CYAN, Visible = false, ZIndex = 5 })
	local dial = box({ Name = "Dial", Parent = arrowBox, Transparency = 1, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 2), ZIndex = 6 })
	local needle = UIUtil.Icon("Up", { Size = 28, Color = CYAN, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 7, Parent = dial })
	local cpText = label({ Name = "Cp", Parent = arrowBox, Text = "", TextSize = 16, Size = UDim2.new(1, -52, 1, 0), Position = UDim2.fromOffset(48, 0), XAlign = Enum.TextXAlignment.Left, ZIndex = 6 })
	-- mini-carte (en haut à droite)
	local mini = box({ Name = "Minimap", Parent = root, Color = rgb(40, 56, 50), Transparency = 0.1, AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(150, 150),
		Position = UDim2.new(1, -12, 1, -12), Radius = UDim.new(0, 18), Stroke = WHITE, Visible = false, ZIndex = 5, Clip = true })
	local miniLine = box({ Name = "Line", Parent = mini, Transparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(126, 126), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
	local miniDots = box({ Name = "Dots", Parent = mini, Transparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(126, 126), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 8 })
	-- boutons 🔄 (F) et 🏳️
	local reset = button({ Name = "ResetCp", Parent = root, Text = "🔄 F", TextSize = 20, Color = rgb(70, 150, 220), Size = UDim2.fromOffset(84, 48),
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -172), Visible = false, ZIndex = 6 })
	reset.Activated:Connect(function()
		if callbacks.Reset then
			callbacks.Reset()
		end
	end)
	local quit = button({ Name = "Quit", Parent = root, Text = "🏳️", TextSize = 22, Color = rgb(120, 100, 140), Size = UDim2.fromOffset(52, 48),
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -104, 1, -172), Visible = false, ZIndex = 6 })
	quit.Activated:Connect(function()
		if callbacks.Leave then
			callbacks.Leave()
		end
	end)
	-- textes au centre
	local big = label({ Name = "Countdown", Parent = root, Text = "", TextSize = 130, Font = Theme.Fonts.Number, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(620, 150), Scaled = true, ZIndex = 12 })
	UIUtil.Create("UIStroke", { Name = "Stroke", Color = INK, Thickness = 5, Parent = big })
	local bigScale = UIUtil.Create("UIScale", { Parent = big })
	local wrong = box({ Name = "WrongWay", Parent = root, Color = RED, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 166), Size = UDim2.fromOffset(330, 50),
		Radius = UDim.new(0, 14), Stroke = WHITE, Visible = false, ZIndex = 10 })
	label({ Name = "T", Parent = wrong, Text = T("⛔ WRONG WAY"), TextSize = 28, ZIndex = 11 })
	local flash = label({ Name = "Flash", Parent = root, Text = "", TextSize = 30, Color = CYAN, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 44), ZIndex = 11 })
	UIUtil.Create("UIStroke", { Name = "Stroke", Color = INK, Thickness = 3, Parent = flash })
	-- salle d'attente
	local lobby = box({ Name = "Lobby", Parent = root, Color = PANEL, Transparency = 0.08, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.fromOffset(470, 54), Radius = UDim.new(1, 0), Stroke = GOLD, Visible = false, ZIndex = 6 })
	local lobbyText = label({ Name = "Text", Parent = lobby, Text = "", TextSize = 18, Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(22, 0), XAlign = Enum.TextXAlignment.Left,
		Scaled = true, ZIndex = 7 })
	local lobbyLeave = button({ Name = "LeaveLobby", Parent = lobby, Text = T("Leave"), TextSize = 16, Color = rgb(120, 100, 140), Size = UDim2.fromOffset(84, 38),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), ZIndex = 8 })
	lobbyLeave.Activated:Connect(function()
		if callbacks.Leave then
			callbacks.Leave()
		end
	end)
	-- bouton 🏁 (au volant)
	local raceBtn = button({ Name = "RaceButton", Parent = root, Text = "🏁", TextSize = 30, Color = rgb(40, 34, 56), StrokeColor = GOLD, Size = UDim2.fromOffset(60, 60),
		Position = UDim2.new(0, 22, 0.5, 140), Radius = UDim.new(1, 0), Visible = false, ZIndex = 5 })
	local raceTag = label({ Name = "Tag", Parent = raceBtn, Text = T("Races"), TextSize = 14, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1),
		Size = UDim2.fromOffset(90, 18), ZIndex = 6 })
	UIUtil.Create("UIStroke", { Color = INK, Thickness = 1.5, Parent = raceTag })
	raceBtn.Activated:Connect(function()
		if callbacks.Menu then
			callbacks.Menu(true)
		end
	end)
	parts.RacePanel = panel
	parts.Place = place
	parts.Count = count
	parts.Lap = lap
	parts.Time = time
	parts.Gap = gap
	parts.BestLap = bestLap
	parts.Arrow = arrowBox
	parts.Needle = needle
	parts.CpText = cpText
	parts.Mini = mini
	parts.MiniLine = miniLine
	parts.MiniDots = miniDots
	parts.Reset = reset
	parts.Quit = quit
	parts.Big = big
	parts.BigScale = bigScale
	parts.Wrong = wrong
	parts.Flash = flash
	parts.Lobby = lobby
	parts.LobbyText = lobbyText
	parts.RaceButton = raceBtn
	parts.RaceTag = raceTag
	parts.Dots = {}
end

local function buildResults(root: Frame)
	local dim = box({ Name = "ResultsDim", Parent = root, Color = rgb(0, 0, 0), Transparency = 0.4, Visible = false, ZIndex = 30, Clip = true })
	UIUtil.SinkClicks(dim)
	local card = box({ Name = "Results", Parent = dim, Color = PANEL, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(720, 480),
		Radius = UDim.new(0, 24), Stroke = GOLD, StrokeThickness = 3, ZIndex = 31 })
	card.BackgroundColor3 = WHITE
	UIUtil.Gradient(card, ColorSequence.new(PANEL2, PANEL), 90)
	local band = box({ Name = "Band", Parent = card, Transparency = 1, Size = UDim2.new(1, -48, 0, 12), Position = UDim2.fromOffset(24, 10), ZIndex = 32, Clip = true })
	checker(band, 60, 2, 32)
	local title = label({ Name = "Title", Parent = card, Text = "", TextSize = 30, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 26), ZIndex = 32 })
	local stage = box({ Name = "Stage", Parent = card, Transparency = 1, Size = UDim2.fromOffset(420, 250), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 68), ZIndex = 32 })
	local columns = {}
	for i, spec in ipairs({ { 2, 0.18, 104, SILVER }, { 1, 0.5, 146, GOLD }, { 3, 0.82, 76, BRONZE } }) do
		local col = box({ Name = "Col" .. spec[1], Parent = stage, Transparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(spec[2], 1),
			Size = UDim2.fromOffset(128, 250), ZIndex = 33 })
		local block = box({ Name = "Block", Parent = col, Color = spec[4], AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(124, 0),
			Radius = UDim.new(0, 10), ZIndex = 34, Clip = true })
		UIUtil.Gradient(block, ColorSequence.new(spec[4]:Lerp(WHITE, 0.3), spec[4]:Lerp(INK, 0.25)), 90)
		label({ Name = "Num", Parent = block, Text = tostring(spec[1]), TextSize = 46, Font = Theme.Fonts.Number, Color = WHITE, Size = UDim2.new(1, 0, 0, 56), ZIndex = 35 })
		local head = box({ Name = "Head", Parent = col, Color = WHITE, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -spec[3] - 46), Size = UDim2.fromOffset(62, 62),
			Radius = UDim.new(1, 0), Stroke = spec[4], StrokeThickness = 3, ZIndex = 35, Clip = true })
		local img = UIUtil.Create("ImageLabel", { Name = "Img", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = "", ZIndex = 36, Parent = head })
		local emoji = label({ Name = "Emoji", Parent = head, Text = "", TextSize = 36, ZIndex = 37 })
		local name = label({ Name = "Name", Parent = col, Text = "", TextSize = 16, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -spec[3] - 24),
			Size = UDim2.fromOffset(150, 20), Scaled = true, ZIndex = 35 })
		local time = label({ Name = "Time", Parent = col, Text = "", TextSize = 15, Font = Theme.Fonts.Body, Color = SOFT, AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -spec[3] - 4), Size = UDim2.fromOffset(150, 18), ZIndex = 35 })
		columns[spec[1]] = { Col = col, Block = block, Height = spec[3], Head = head, Img = img, Emoji = emoji, Name = name, Time = time }
		local _ = i
	end
	local rows = label({ Name = "Rows", Parent = card, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Color = SOFT, Size = UDim2.new(1, -60, 0, 44), Position = UDim2.fromOffset(30, 324),
		Wrap = true, Rich = true, ZIndex = 32 })
	local mine = label({ Name = "Mine", Parent = card, Text = "", TextSize = 22, Color = GOLD, Size = UDim2.new(1, -60, 0, 30), Position = UDim2.fromOffset(30, 370), Scaled = true, Rich = true, ZIndex = 32 })
	local ok = button({ Name = "Ok", Parent = card, Text = T("Awesome!"), Size = UDim2.fromOffset(200, 48), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), ZIndex = 33 })
	ok.Activated:Connect(function()
		RaceHud.HideResults()
	end)
	parts.ResultsDim = dim
	parts.Results = card
	parts.ResultsTitle = title
	parts.Columns = columns
	parts.ResultsRows = rows
	parts.ResultsMine = mine
	parts.ResultsOk = ok
end

local function layout()
	local screen = gui
	if not screen or not parts.Root then
		return
	end
	local size = screen.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	phone = touch and math.min(size.X, size.Y) < 500
	local designW, designH = if phone then 820 else 1100, if phone then 430 else 620
	local scale = math.clamp(math.min(size.X / designW, size.Y / designH), 0.45, 1.35)
	parts.Scale.Scale = scale
	parts.Root.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
	-- téléphone : panneaux plus compacts, bouton 🏁 sous la colonne des voitures
	parts.RacePanel.Position = if phone then UDim2.fromOffset(10, 96) else UDim2.fromOffset(12, 108)
	parts.RaceButton.Position = if phone then UDim2.fromOffset(14, 316) else UDim2.new(0, 22, 0.5, 140)
	parts.RaceTag.Visible = not phone
	local mini = if phone then 116 else 150
	parts.Mini.Size = UDim2.fromOffset(mini, mini)
	parts.MiniLine.Size = UDim2.fromOffset(mini - 24, mini - 24)
	parts.MiniDots.Size = UDim2.fromOffset(mini - 24, mini - 24)
	if parts.MiniPoints then
		drawLine(parts.MiniLine, parts.MiniPoints, WHITE, 4, 6, parts.MiniClosed)
	end
	parts.Arrow.Position = if phone then UDim2.new(0.5, 0, 0, 96) else UDim2.new(0.5, 0, 0, 112)
	parts.Lobby.Position = parts.Arrow.Position
	parts.Reset.Position = UDim2.new(1, -12, 1, -(mini + 22))
	parts.Quit.Position = UDim2.new(1, -104, 1, -(mini + 22))
	parts.Menu.Size = if phone then UDim2.fromOffset(800, 412) else UDim2.fromOffset(800, 470)
	parts.CardGrid.CellSize = if phone then UDim2.fromOffset(183, 250) else UDim2.fromOffset(183, 306)
	for _, c in ipairs(parts.CardList) do
		c.Map.Size = if phone then UDim2.new(1, -20, 0, 60) else UDim2.new(1, -20, 0, 96)
		local lineSize = if phone then 52 else 80
		if c.Line.Size.X.Offset ~= lineSize then
			c.Line.Size = UDim2.fromOffset(lineSize, lineSize)
			c.PreviewKey = nil -- (redessiné à la prochaine mise à jour)
		end
		local top = if phone then 72 else 112
		c.Icon.Position = UDim2.fromOffset(8, top)
		c.Name.Position = UDim2.fromOffset(48, top)
		c.Info.Position = UDim2.fromOffset(10, top + 36)
		c.Info.Visible = not phone
		c.Record.Position = UDim2.fromOffset(10, top + (if phone then 36 else 72))
		c.Best.Position = UDim2.fromOffset(10, top + (if phone then 56 else 92))
		c.Status.Position = UDim2.fromOffset(10, top + (if phone then 78 else 116))
	end
	parts.Results.Size = if phone then UDim2.fromOffset(720, 410) else UDim2.fromOffset(720, 480)
end

function RaceHud.Build(cb: { [string]: any })
	RaceHud.Destroy()
	callbacks = cb or {}
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild(RaceHud.GUI_NAME)
	if old then
		old:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = RaceHud.GUI_NAME
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 22
	screen.Parent = playerGui
	gui = screen
	local root = UIUtil.Create("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromOffset(1100, 620), Parent = screen })
	parts.Root = root
	parts.Scale = UIUtil.Create("UIScale", { Parent = root })
	buildRaceHud(root)
	buildMenu(root)
	buildResults(root)
	table.insert(conns, screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	layout()
end

function RaceHud.Destroy()
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(parts)
	menuOpen = false
end

function RaceHud.IsBuilt(): boolean
	return gui ~= nil
end

----------------------------------------------------------------------
-- Mises à jour
----------------------------------------------------------------------

function RaceHud.SetRaceButton(visible: boolean)
	if parts.RaceButton then
		parts.RaceButton.Visible = visible
	end
end

function RaceHud.IsMenuOpen(): boolean
	return menuOpen
end

function RaceHud.SetMenu(open: boolean, cards: { any }?, info: { [string]: any }?)
	if not parts.MenuDim then
		return
	end
	local wasOpen = menuOpen
	menuOpen = open
	parts.MenuDim.Visible = open
	if not open then
		return
	end
	if not wasOpen then
		UIUtil.Pop(parts.Menu, 0.92, 0.18)
	end
	if info then
		parts.MenuSub.Text = info.Sub or ""
		parts.MenuFoot.Text = info.Foot or ""
	end
	for index, data in ipairs(cards or {}) do
		local c = parts.CardList[index]
		if not c then
			c = buildCard(parts.Cards, index)
			parts.CardList[index] = c
			local card = c
			card.Join.Activated:Connect(function()
				if callbacks.Join and card.Id ~= "" then
					callbacks.Join(card.Id, card.Joined)
				end
			end)
			layout()
		end
		c.Id = data.Id
		c.Joined = data.Joined == true
		c.Icon.Text = data.Icon or "🏁"
		c.Name.Text = data.Name or ""
		c.Info.Text = data.Info or ""
		c.Record.Text = data.Record or ""
		c.Best.Text = data.Best or ""
		c.Status.Text = data.Status or ""
		c.Status.TextColor3 = data.StatusColor or WHITE
		c.Join.Text = if data.Joined then T("Leave") else T("Join")
		c.Join.BackgroundColor3 = if data.Joined then rgb(120, 100, 140) elseif data.CanJoin then PINK_DEEP else rgb(90, 84, 100)
		c.Card:FindFirstChildOfClass("UIStroke").Color = if data.Joined then GOLD else rgb(120, 90, 160)
		if data.Preview and c.PreviewKey ~= data.PreviewKey then
			c.PreviewKey = data.PreviewKey
			drawLine(c.Line, data.Preview, WHITE, 3, 26, data.Closed)
		end
	end
end

function RaceHud.SetLobby(info: { [string]: any }?)
	if not parts.Lobby then
		return
	end
	parts.Lobby.Visible = info ~= nil
	if info then
		parts.LobbyText.Text = info.Text or ""
	end
end

function RaceHud.SetRace(info: { [string]: any }?)
	if not parts.RacePanel then
		return
	end
	local on = info ~= nil
	parts.RacePanel.Visible = on
	parts.Arrow.Visible = on and info ~= nil and info.Cp ~= nil
	parts.Mini.Visible = on
	parts.Reset.Visible = on and info ~= nil and info.Running == true
	parts.Quit.Visible = on and info ~= nil and info.Running == true
	if not on then
		parts.Wrong.Visible = false
		return
	end
	local i = info :: { [string]: any }
	parts.Place.Text = tostring(i.Place or 1)
	parts.Place.TextColor3 = if i.Place == 1 then GOLD elseif i.Place == 2 then SILVER elseif i.Place == 3 then BRONZE else WHITE
	parts.Count.Text = "/" .. tostring(i.Count or 1)
	parts.Lap.Text = if (i.Laps or 1) > 1 then T("Lap %d/%d", math.clamp(i.Lap or 1, 1, i.Laps), i.Laps) else T("Sprint")
	parts.Time.Text = i.Time or "0:00.00"
	parts.Gap.Text = i.Gap or ""
	parts.BestLap.Text = i.Best or ""
	if i.Cp then
		parts.CpText.Text = i.Cp
		parts.Needle.Rotation = i.Arrow or 0
	end
	parts.Wrong.Visible = i.Wrong == true
end

-- points : { { u, v } } (0..1) ; dots : { { u, v, color, me } }
function RaceHud.SetMinimap(points: { { number } }?, dots: { { any } }?, closed: boolean?)
	if not parts.Mini then
		return
	end
	if points then
		parts.MiniPoints = points
		parts.MiniClosed = closed
		drawLine(parts.MiniLine, points, WHITE, 4, 6, closed)
	end
	if dots then
		local holder = parts.MiniDots
		local w = math.max(4, holder.Size.X.Offset)
		local h = math.max(4, holder.Size.Y.Offset)
		for k, d in ipairs(dots) do
			local dot = parts.Dots[k]
			if not dot then
				dot = box({ Name = "Dot", Parent = holder, Color = WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), Radius = UDim.new(1, 0), ZIndex = 9 })
				UIUtil.Stroke(dot, INK, 1.5)
				parts.Dots[k] = dot
			end
			dot.Visible = true
			dot.BackgroundColor3 = d[3] or WHITE
			dot.Size = if d[4] then UDim2.fromOffset(14, 14) else UDim2.fromOffset(9, 9)
			dot.ZIndex = if d[4] then 10 else 9
			dot.Position = UDim2.fromOffset(d[1] * w, d[2] * h)
		end
		for k = #dots + 1, #parts.Dots do
			parts.Dots[k].Visible = false
		end
	end
end

function RaceHud.Countdown(text: string, color: Color3?)
	local big = parts.Big
	if not big then
		return
	end
	big.Text = text
	big.TextColor3 = color or WHITE
	big.TextTransparency = 0
	local bigStroke = big:FindFirstChild("Stroke") :: UIStroke?
	if bigStroke then
		bigStroke.Transparency = 0
	end
	if countdownTween then
		countdownTween:Cancel()
	end
	parts.BigScale.Scale = 1.6
	local tween = TweenService:Create(parts.BigScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	countdownTween = tween
	tween:Play()
	if text ~= "" then
		local stamp = text
		task.delay(0.85, function()
			local b = parts.Big
			if b and b.Text == stamp then
				TweenService:Create(b, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
				local st = b:FindFirstChild("Stroke")
				if st then
					TweenService:Create(st, TweenInfo.new(0.25), { Transparency = 1 }):Play()
				end
				task.delay(0.3, function()
					if parts.Big == b and b.Text == stamp then
						b.Text = ""
					end
				end)
			end
		end)
	end
end

function RaceHud.Flash(text: string, color: Color3?)
	local f = parts.Flash
	if not f then
		return
	end
	flashToken += 1
	local token = flashToken
	f.Text = text
	f.TextColor3 = color or CYAN
	f.TextTransparency = 0
	local fStroke = f:FindFirstChild("Stroke") :: UIStroke?
	if fStroke then
		fStroke.Transparency = 0
	end
	f.Position = UDim2.fromScale(0.5, 0.52)
	TweenService:Create(f, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.48) }):Play()
	task.delay(1.3, function()
		local fl = parts.Flash
		if flashToken == token and fl then
			TweenService:Create(fl, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			local st = fl:FindFirstChild("Stroke")
			if st then
				TweenService:Create(st, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
			task.delay(0.45, function()
				if flashToken == token and parts.Flash == fl then
					fl.Text = ""
				end
			end)
		end
	end)
end

----------------------------------------------------------------------
-- Résultats : podium animé
----------------------------------------------------------------------

local function confetti(parent: Instance)
	local colors = { PINK, GOLD, CYAN, MINT, WHITE, rgb(186, 156, 246) }
	for k = 1, 46 do
		local x = math.random()
		local piece = box({ Name = "Confetti", Parent = parent, Color = colors[(k % #colors) + 1], AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(8 + math.random() * 6, 5 + math.random() * 4), Position = UDim2.new(x, 0, 0, -20), ZIndex = 40 })
		piece.Rotation = math.random(0, 180)
		local fall = 2.2 + math.random() * 1.6
		TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.new(x + (math.random() - 0.5) * 0.2, 0, 1, 30),
			Rotation = piece.Rotation + math.random(180, 540),
		}):Play()
		task.delay(fall + 0.1, function()
			piece:Destroy()
		end)
	end
end

-- res = { Title, Rows = { { Place, Name, UserId, AI, Time, Finished, Dnf } }, Mine = texte riche, Others = texte riche }
function RaceHud.ShowResults(res: { [string]: any })
	if not parts.ResultsDim then
		return
	end
	RaceHud.SetMenu(false)
	resultsToken += 1
	local token = resultsToken
	parts.ResultsDim.Visible = true
	parts.ResultsTitle.Text = res.Title or ""
	parts.ResultsRows.Text = res.Others or ""
	parts.ResultsMine.Text = res.Mine or ""
	UIUtil.Pop(parts.Results, 0.85, 0.25)
	local byPlace = {}
	for _, row in ipairs(res.Rows or {}) do
		byPlace[row.Place] = row
	end
	-- colonnes : 3e, puis 2e, puis 1er (le suspense), qui montent en douceur
	for _, place in ipairs({ 3, 2, 1 }) do
		local c = parts.Columns[place]
		local row = byPlace[place]
		c.Block.Size = UDim2.fromOffset(124, 0)
		c.Head.Visible = false
		c.Name.Visible = false
		c.Time.Visible = false
		if row then
			c.Name.Text = row.Name or ""
			c.Time.Text = row.TimeText or ""
			if row.AI or (row.UserId or 0) <= 0 then
				c.Img.Image = ""
				c.Emoji.Text = "🤖"
			else
				c.Img.Image = UIUtil.HeadshotUrl(row.UserId, 150)
				c.Emoji.Text = ""
			end
		end
	end
	task.spawn(function()
		for step, place in ipairs({ 3, 2, 1 }) do
			task.wait(if step == 1 then 0.35 else 0.45)
			if token ~= resultsToken or not parts.Columns then
				return
			end
			local c = parts.Columns[place]
			if byPlace[place] then
				TweenService:Create(c.Block, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(124, c.Height) }):Play()
				task.delay(0.35, function()
					if token ~= resultsToken or not parts.Columns then
						return
					end
					c.Head.Visible = true
					c.Name.Visible = true
					c.Time.Visible = true
					UIUtil.Pop(c.Head, 0.4, 0.3)
				end)
			end
		end
		task.wait(0.5)
		if token == resultsToken and parts.ResultsDim then
			confetti(parts.ResultsDim)
		end
	end)
end

function RaceHud.HideResults()
	resultsToken += 1
	if parts.ResultsDim then
		parts.ResultsDim.Visible = false
	end
end

function RaceHud.Debug(): any
	return { Parts = parts, Layout = layout, IsPhone = function()
		return phone
	end }
end

return RaceHud
