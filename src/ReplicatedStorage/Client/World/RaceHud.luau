--[[
	RaceHud (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > RaceHud

	🏁 Interface des courses de rue PENDANT la course (v10 RACE10, v11
	RACE11) : ScreenGui "RaceGui" (gardée visible en ville : KEEP_GUIS),
	pilotée par RaceClient. Le menu, les stats et les classements sont dans
	RaceMenu (même ScreenGui, racine "Menu").
	  - bouton rond 🏁 au volant (hors course) : ouvre le MENU ;
	  - SALLE D'ATTENTE (bandeau en haut) : parcours, inscrits, départ dans
	    X s, bouton Quitter ;
	  - EN COURSE :
	      · TOUR DES TEMPS (à gauche, comme à la télé) : P2/6, tour, chrono,
	        puis chaque coureur (place, couleur, nom, écart avec le 1er ; toi
	        en surbrillance), dernier tour / meilleur tour ;
	      · FLÈCHE vers la prochaine porte (porte n / N, distance) et, juste
	        dessous, l'ÉCART AVEC TON FANTÔME à chaque porte (vert = en avance) ;
	      · NITRO : 3 charges + jauge (dérapage, aspiration), bouton (Maj / N
	        ou le bouton), lueur pendant le boost ;
	      · DRIFT : compteur qui pop quand tu dérapes ;
	      · changement de place (▲ P2), "DERNIER TOUR", 3-2-1-GO géant,
	        "MAUVAIS SENS", flash des portes, mini-carte (tracé + coureurs),
	        boutons 🔄 porte (F) et 🏳️ abandon ;
	  - SPECTATEUR : barre du bas (qui tu regardes, place, ◀ ▶, Quitter) ;
	  - RÉSULTATS : podium animé (colonnes qui montent, photos), classement
	    complet qui glisse ligne par ligne (temps, écart, meilleur tour),
	    médaille du parcours (tampon), NOUVEAU RECORD, récompense qui défile,
	    barre d'XP qui se remplit (+ passage de rang), confettis, boutons
	    "Rejouer" et "Génial !".
	Ordinateur + téléphone (UIScale, disposition resserrée sur téléphone).

	API (RaceClient) :
	  RaceHud.Build(callbacks)  { Leave(), Reset(), Nitro(), Menu(open), Spectate(dir), StopSpectate(), Rematch(routeId) }
	  RaceHud.Destroy() / RaceHud.Root() (racine pour RaceMenu) / RaceHud.IsPhone()
	  RaceHud.SetRaceButton(visible)
	  RaceHud.SetLobby(info?)                { Text }
	  RaceHud.SetRace(info?)                 { Place, Count, Lap, Laps, Time, LastLap, Best, Cp, Arrow, Wrong,
	                                           Running, Tower = { { Pos, Name, Gap, Color, Me, Out } },
	                                           Nitro = { Charges, Max, Gauge, Boost } }
	  RaceHud.SetMinimap(points?, dots?, closed?)
	  RaceHud.Countdown(text, color?) / RaceHud.Flash(text, color?)
	  RaceHud.Delta(seconds, label?)         écart avec le fantôme (vert / rouge)
	  RaceHud.Drift(points) / RaceHud.PlaceChange(place, up) / RaceHud.Banner(text, color?)
	  RaceHud.SetSpectate(info?)             { Name, Place, Count, Lap }
	  RaceHud.ShowResults(res) / RaceHud.HideResults()
	  RaceHud.Debug()
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
local NITRO = rgb(90, 170, 255)
RaceHud.Colors = { INK = INK, PANEL = PANEL, PANEL2 = PANEL2, WHITE = WHITE, PINK = PINK, PINK_DEEP = PINK_DEEP, GOLD = GOLD, SILVER = SILVER,
	BRONZE = BRONZE, MINT = MINT, CYAN = CYAN, RED = RED, SOFT = SOFT, NITRO = NITRO }

local TOWER_ROWS = 8

local gui: ScreenGui? = nil
local parts: { [string]: any } = {}
local callbacks: { [string]: any } = {}
local conns: { RBXScriptConnection } = {}
local phone = false
local countdownTween: Tween? = nil
local flashToken = 0
local resultsToken = 0
local deltaToken = 0
local driftToken = 0
local bannerToken = 0
local placeToken = 0
local layoutHooks: { () -> () } = {}

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
	l.TextTruncate = if props.Truncate then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None
	if props.Scaled then
		l.TextScaled = true
		UIUtil.Create("UITextSizeConstraint", { MaxTextSize = props.TextSize or 18, MinTextSize = 8, Parent = l })
	end
	l.Parent = props.Parent
	return l
end
RaceHud.Label = label

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
RaceHud.Box = box

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
RaceHud.Button = button

-- Damier (bandeau décoratif)
local function checker(parent: Instance, cols: number, rows: number, z: number)
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			box({ Name = "Sq", Parent = parent, Color = if (i + j) % 2 == 0 then INK else WHITE, Size = UDim2.fromScale(1 / cols, 1 / rows),
				Position = UDim2.fromScale(i / cols, j / rows), ZIndex = z })
		end
	end
end
RaceHud.Checker = checker

-- Ligne brisée dessinée avec des Frames (points en 0..1 dans `holder`)
local function drawLine(holder: Frame, points: { { number } }, color: Color3, thickness: number, z: number, closed: boolean?, noFlag: boolean?)
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
	if noFlag then
		return
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

local function fadeOut(lbl: TextLabel, delay: number, token: () -> boolean)
	task.delay(delay, function()
		if token() and lbl.Parent then
			TweenService:Create(lbl, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			local st = lbl:FindFirstChildOfClass("UIStroke")
			if st then
				TweenService:Create(st, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			end
		end
	end)
end

----------------------------------------------------------------------
-- Construction : HUD de course
----------------------------------------------------------------------

local function buildTower(root: Frame)
	local tower = box({ Name = "Tower", Parent = root, Color = PANEL, Transparency = 0.1, Size = UDim2.fromOffset(236, 120), Position = UDim2.fromOffset(104, 150),
		Radius = UDim.new(0, 16), Stroke = PINK, Visible = false, ZIndex = 5, Clip = true })
	-- en-tête : place / tour / chrono
	local head = box({ Name = "Head", Parent = tower, Color = INK, Transparency = 0.15, Size = UDim2.new(1, 0, 0, 62), ZIndex = 6 })
	local place = label({ Name = "Place", Parent = head, Text = "1", Font = Theme.Fonts.Number, TextSize = 50, Size = UDim2.fromOffset(52, 56), Position = UDim2.fromOffset(8, 3), ZIndex = 7 })
	UIUtil.Create("UIStroke", { Color = INK, Thickness = 2, Parent = place })
	local count = label({ Name = "Count", Parent = head, Text = "/4", Font = Theme.Fonts.Number, TextSize = 22, Color = SOFT, Size = UDim2.fromOffset(40, 26),
		Position = UDim2.fromOffset(58, 28), XAlign = Enum.TextXAlignment.Left, ZIndex = 7 })
	local lap = label({ Name = "Lap", Parent = head, Text = "", TextSize = 16, Color = SOFT, Size = UDim2.fromOffset(128, 22), Position = UDim2.fromOffset(102, 5),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 7 })
	local time = label({ Name = "Time", Parent = head, Text = "0:00.00", Font = Theme.Fonts.Number, TextSize = 26, Color = GOLD, Size = UDim2.fromOffset(128, 30),
		Position = UDim2.fromOffset(100, 26), XAlign = Enum.TextXAlignment.Left, ZIndex = 7 })
	local rowsHolder = box({ Name = "Rows", Parent = tower, Transparency = 1, Size = UDim2.new(1, -12, 0, TOWER_ROWS * 24), Position = UDim2.fromOffset(6, 66), ZIndex = 6 })
	local rows = {}
	for k = 1, TOWER_ROWS do
		local row = box({ Name = "Row" .. k, Parent = rowsHolder, Color = WHITE, Transparency = 1, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, (k - 1) * 24),
			Radius = UDim.new(0, 6), ZIndex = 6 })
		local pos = label({ Name = "Pos", Parent = row, Text = "", Font = Theme.Fonts.Number, TextSize = 15, Color = INK, Size = UDim2.fromOffset(22, 20), Position = UDim2.fromOffset(2, 1), ZIndex = 8 })
		local posBg = box({ Name = "PosBg", Parent = row, Color = WHITE, Size = UDim2.fromOffset(22, 20), Position = UDim2.fromOffset(2, 1), Radius = UDim.new(0, 5), ZIndex = 7 })
		local stripe = box({ Name = "Stripe", Parent = row, Color = CYAN, Size = UDim2.fromOffset(4, 16), Position = UDim2.fromOffset(28, 3), Radius = UDim.new(0, 2), ZIndex = 7 })
		local name = label({ Name = "Name", Parent = row, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(36, 0),
			XAlign = Enum.TextXAlignment.Left, Truncate = true, ZIndex = 7 })
		local gap = label({ Name = "Gap", Parent = row, Text = "", Font = Theme.Fonts.Number, TextSize = 14, Color = SOFT, Size = UDim2.fromOffset(62, 20), AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 1), XAlign = Enum.TextXAlignment.Right, ZIndex = 7 })
		rows[k] = { Row = row, Pos = pos, PosBg = posBg, Stripe = stripe, Name = name, Gap = gap }
	end
	local foot = label({ Name = "Foot", Parent = tower, Text = "", Font = Theme.Fonts.Body, TextSize = 14, Color = MINT, Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(10, 70),
		XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Wrap = true, Rich = true, ZIndex = 6 })
	parts.Tower = tower
	parts.Place = place
	parts.Count = count
	parts.Lap = lap
	parts.Time = time
	parts.TowerRows = rows
	parts.TowerHolder = rowsHolder
	parts.TowerFoot = foot
end

local function buildNitro(root: Frame)
	local holder = box({ Name = "Nitro", Parent = root, Color = PANEL, Transparency = 0.12, AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(206, 66),
		Position = UDim2.new(1, -174, 1, -12), Radius = UDim.new(0, 16), Stroke = NITRO, Visible = false, ZIndex = 5 })
	local pips = {}
	for k = 1, 3 do
		local pip = box({ Name = "Pip" .. k, Parent = holder, Color = rgb(60, 66, 90), Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(10 + (k - 1) * 22, 8),
			Radius = UDim.new(1, 0), Stroke = INK, ZIndex = 6 })
		label({ Name = "I", Parent = pip, Text = "🔥", TextSize = 11, ZIndex = 7 })
		pips[k] = pip
	end
	local bar = box({ Name = "Bar", Parent = holder, Color = rgb(30, 30, 46), Size = UDim2.fromOffset(66, 10), Position = UDim2.fromOffset(10, 34), Radius = UDim.new(1, 0), ZIndex = 6, Clip = true })
	local fill = box({ Name = "Fill", Parent = bar, Color = NITRO, Size = UDim2.fromScale(0, 1), Radius = UDim.new(1, 0), ZIndex = 7 })
	UIUtil.Gradient(fill, ColorSequence.new(rgb(120, 230, 255), rgb(80, 120, 255)), 0)
	local hint = label({ Name = "Hint", Parent = holder, Text = T("charge: drift / draft"), Font = Theme.Fonts.Body, TextSize = 11, Color = SOFT, Size = UDim2.fromOffset(78, 14),
		Position = UDim2.fromOffset(4, 47), Scaled = true, ZIndex = 6 })
	local btn = button({ Name = "NitroBtn", Parent = holder, Text = "🔥 NITRO", TextSize = 17, Color = rgb(40, 90, 200), StrokeColor = CYAN, Size = UDim2.fromOffset(110, 50),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), ZIndex = 7 })
	local key = label({ Name = "Key", Parent = btn, Text = "Shift", Font = Theme.Fonts.Body, TextSize = 11, Color = SOFT, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.fromOffset(80, 13), ZIndex = 8 })
	btn.Activated:Connect(function()
		if callbacks.Nitro then
			callbacks.Nitro()
		end
	end)
	local glow = box({ Name = "BoostGlow", Parent = root, Color = NITRO, Transparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	UIUtil.Gradient(glow, ColorSequence.new(NITRO, NITRO), 0).Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.12, 1),
		NumberSequenceKeypoint.new(0.88, 1),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	parts.Nitro = holder
	parts.NitroPips = pips
	parts.NitroFill = fill
	parts.NitroBtn = btn
	parts.NitroKey = key
	parts.NitroHint = hint
	parts.BoostGlow = glow
end

local function buildRaceHud(root: Frame)
	buildTower(root)
	buildNitro(root)
	-- flèche vers la prochaine porte (en haut au milieu, sous le compteur)
	local arrowBox = box({ Name = "Arrow", Parent = root, Color = PANEL, Transparency = 0.15, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(240, 44),
		Position = UDim2.new(0.5, 0, 0, 112), Radius = UDim.new(1, 0), Stroke = CYAN, Visible = false, ZIndex = 5 })
	local dial = box({ Name = "Dial", Parent = arrowBox, Transparency = 1, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 2), ZIndex = 6 })
	local needle = UIUtil.Icon("Up", { Size = 28, Color = CYAN, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 7, Parent = dial })
	local cpText = label({ Name = "Cp", Parent = arrowBox, Text = "", TextSize = 16, Size = UDim2.new(1, -52, 1, 0), Position = UDim2.fromOffset(48, 0), XAlign = Enum.TextXAlignment.Left, ZIndex = 6 })
	-- écart avec le fantôme (sous la flèche)
	local delta = label({ Name = "Delta", Parent = root, Text = "", Font = Theme.Fonts.Number, TextSize = 30, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.fromOffset(300, 34), ZIndex = 9 })
	UIUtil.Create("UIStroke", { Name = "Stroke", Color = INK, Thickness = 3, Parent = delta })
	-- mini-carte (en bas à droite)
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
	local wrong = box({ Name = "WrongWay", Parent = root, Color = RED, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 200), Size = UDim2.fromOffset(330, 50),
		Radius = UDim.new(0, 14), Stroke = WHITE, Visible = false, ZIndex = 10 })
	label({ Name = "T", Parent = wrong, Text = T("⛔ WRONG WAY"), TextSize = 28, ZIndex = 11 })
	local flash = label({ Name = "Flash", Parent = root, Text = "", TextSize = 30, Color = CYAN, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 44), ZIndex = 11 })
	UIUtil.Create("UIStroke", { Name = "Stroke", Color = INK, Thickness = 3, Parent = flash })
	-- bannière (dernier tour, nitro...)
	local banner = box({ Name = "Banner", Parent = root, Color = INK, Transparency = 0.1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromOffset(460, 62), Radius = UDim.new(0, 14), Stroke = GOLD, StrokeThickness = 3, Visible = false, ZIndex = 11, Clip = true })
	local bannerBand = box({ Name = "Band", Parent = banner, Transparency = 1, Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 1, -8), ZIndex = 12, Clip = true })
	checker(bannerBand, 46, 1, 12)
	local bannerText = label({ Name = "T", Parent = banner, Text = "", TextSize = 34, Color = GOLD, Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 0), ZIndex = 12 })
	-- dérapage
	local drift = label({ Name = "Drift", Parent = root, Text = "", TextSize = 30, Color = rgb(255, 160, 80), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -30, 0.44, 0),
		Size = UDim2.fromOffset(300, 40), XAlign = Enum.TextXAlignment.Right, ZIndex = 9 })
	UIUtil.Create("UIStroke", { Name = "Stroke", Color = INK, Thickness = 3, Parent = drift })
	local driftScale = UIUtil.Create("UIScale", { Parent = drift })
	-- changement de place
	local placeFx = label({ Name = "PlaceFx", Parent = root, Text = "", Font = Theme.Fonts.Number, TextSize = 34, Color = MINT, Position = UDim2.fromOffset(256, 108),
		Size = UDim2.fromOffset(120, 40), XAlign = Enum.TextXAlignment.Left, ZIndex = 9 })
	UIUtil.Create("UIStroke", { Name = "Stroke", Color = INK, Thickness = 3, Parent = placeFx })
	-- salle d'attente
	local lobby = box({ Name = "Lobby", Parent = root, Color = PANEL, Transparency = 0.08, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.fromOffset(500, 54), Radius = UDim.new(1, 0), Stroke = GOLD, Visible = false, ZIndex = 6 })
	local lobbyText = label({ Name = "Text", Parent = lobby, Text = "", TextSize = 18, Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(22, 0), XAlign = Enum.TextXAlignment.Left,
		Scaled = true, ZIndex = 7 })
	local lobbyLeave = button({ Name = "LeaveLobby", Parent = lobby, Text = T("Leave"), TextSize = 16, Color = rgb(120, 100, 140), Size = UDim2.fromOffset(84, 38),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), ZIndex = 8 })
	lobbyLeave.Activated:Connect(function()
		if callbacks.Leave then
			callbacks.Leave()
		end
	end)
	-- spectateur
	local spec = box({ Name = "Spectate", Parent = root, Color = PANEL, Transparency = 0.06, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(560, 64), Radius = UDim.new(0, 18), Stroke = CYAN, StrokeThickness = 3, Visible = false, ZIndex = 8 })
	local specPrev = button({ Name = "Prev", Parent = spec, Text = "◀", TextSize = 22, Color = rgb(70, 60, 100), Size = UDim2.fromOffset(48, 44), Position = UDim2.fromOffset(10, 10), ZIndex = 9 })
	local specNext = button({ Name = "Next", Parent = spec, Text = "▶", TextSize = 22, Color = rgb(70, 60, 100), Size = UDim2.fromOffset(48, 44), Position = UDim2.fromOffset(64, 10), ZIndex = 9 })
	local specText = label({ Name = "Text", Parent = spec, Text = "", TextSize = 18, Size = UDim2.new(1, -250, 1, -8), Position = UDim2.fromOffset(122, 4), XAlign = Enum.TextXAlignment.Left,
		Scaled = true, Rich = true, ZIndex = 9 })
	local specQuit = button({ Name = "StopWatch", Parent = spec, Text = T("Stop watching"), TextSize = 15, Color = rgb(120, 100, 140), Size = UDim2.fromOffset(120, 44),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), ZIndex = 9 })
	specPrev.Activated:Connect(function()
		if callbacks.Spectate then
			callbacks.Spectate(-1)
		end
	end)
	specNext.Activated:Connect(function()
		if callbacks.Spectate then
			callbacks.Spectate(1)
		end
	end)
	specQuit.Activated:Connect(function()
		if callbacks.StopSpectate then
			callbacks.StopSpectate()
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
	parts.Arrow = arrowBox
	parts.Needle = needle
	parts.CpText = cpText
	parts.Delta = delta
	parts.Mini = mini
	parts.MiniLine = miniLine
	parts.MiniDots = miniDots
	parts.Reset = reset
	parts.Quit = quit
	parts.Big = big
	parts.BigScale = bigScale
	parts.Wrong = wrong
	parts.Flash = flash
	parts.Banner = banner
	parts.BannerText = bannerText
	parts.Drift = drift
	parts.DriftScale = driftScale
	parts.PlaceFx = placeFx
	parts.Lobby = lobby
	parts.LobbyText = lobbyText
	parts.Spectate = spec
	parts.SpecText = specText
	parts.RaceButton = raceBtn
	parts.RaceTag = raceTag
	parts.Dots = {}
end

----------------------------------------------------------------------
-- Construction : résultats
----------------------------------------------------------------------

local RES_W, RES_H = 900, 480

local function buildResults(root: Frame)
	local dim = box({ Name = "ResultsDim", Parent = root, Color = rgb(0, 0, 0), Transparency = 0.4, Visible = false, ZIndex = 30, Clip = true })
	UIUtil.SinkClicks(dim)
	-- support (échelle téléphone) ; la carte "pop" à l'intérieur
	local holder = box({ Name = "ResultsHolder", Parent = dim, Transparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(RES_W, RES_H), ZIndex = 31 })
	parts.ResultsScale = UIUtil.Create("UIScale", { Parent = holder })
	local card = box({ Name = "Results", Parent = holder, Color = PANEL, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(RES_W, RES_H),
		Radius = UDim.new(0, 24), Stroke = GOLD, StrokeThickness = 3, ZIndex = 31, Clip = true })
	card.BackgroundColor3 = WHITE
	UIUtil.Gradient(card, ColorSequence.new(PANEL2, PANEL), 90)
	local band = box({ Name = "Band", Parent = card, Transparency = 1, Size = UDim2.new(1, -48, 0, 12), Position = UDim2.fromOffset(24, 10), ZIndex = 32, Clip = true })
	checker(band, 70, 2, 32)
	local title = label({ Name = "Title", Parent = card, Text = "", TextSize = 30, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 26), ZIndex = 32 })
	-- podium (à gauche)
	local stage = box({ Name = "Stage", Parent = card, Transparency = 1, Size = UDim2.fromOffset(380, 270), Position = UDim2.fromOffset(20, 70), ZIndex = 32 })
	local columns = {}
	for _, spec in ipairs({ { 2, 0.18, 96, SILVER }, { 1, 0.5, 136, GOLD }, { 3, 0.82, 70, BRONZE } }) do
		local col = box({ Name = "Col" .. spec[1], Parent = stage, Transparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(spec[2], 1),
			Size = UDim2.fromOffset(118, 270), ZIndex = 33 })
		local block = box({ Name = "Block", Parent = col, Color = spec[4], AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(114, 0),
			Radius = UDim.new(0, 10), ZIndex = 34, Clip = true })
		UIUtil.Gradient(block, ColorSequence.new(spec[4]:Lerp(WHITE, 0.3), spec[4]:Lerp(INK, 0.25)), 90)
		label({ Name = "Num", Parent = block, Text = tostring(spec[1]), TextSize = 44, Font = Theme.Fonts.Number, Color = WHITE, Size = UDim2.new(1, 0, 0, 54), ZIndex = 35 })
		local head = box({ Name = "Head", Parent = col, Color = WHITE, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -spec[3] - 46), Size = UDim2.fromOffset(62, 62),
			Radius = UDim.new(1, 0), Stroke = spec[4], StrokeThickness = 3, ZIndex = 35, Clip = true })
		local img = UIUtil.Create("ImageLabel", { Name = "Img", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = "", ZIndex = 36, Parent = head })
		local emoji = label({ Name = "Emoji", Parent = head, Text = "", TextSize = 36, ZIndex = 37 })
		local name = label({ Name = "Name", Parent = col, Text = "", TextSize = 16, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -spec[3] - 24),
			Size = UDim2.fromOffset(140, 20), Scaled = true, ZIndex = 35 })
		local time = label({ Name = "Time", Parent = col, Text = "", TextSize = 15, Font = Theme.Fonts.Body, Color = SOFT, AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -spec[3] - 4), Size = UDim2.fromOffset(140, 18), ZIndex = 35 })
		columns[spec[1]] = { Col = col, Block = block, Height = spec[3], Head = head, Img = img, Emoji = emoji, Name = name, Time = time }
	end
	-- classement complet (à droite)
	local list = box({ Name = "Standings", Parent = card, Color = INK, Transparency = 0.35, Size = UDim2.fromOffset(460, 270), Position = UDim2.fromOffset(418, 70),
		Radius = UDim.new(0, 14), ZIndex = 32, Clip = true })
	local hdr = box({ Name = "Hdr", Parent = list, Transparency = 1, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 4), ZIndex = 33 })
	for _, h in ipairs({ { T("Pilot"), 46, 180, Enum.TextXAlignment.Left }, { T("Time"), 230, 80, Enum.TextXAlignment.Right }, { T("Gap"), 312, 64, Enum.TextXAlignment.Right },
		{ T("Best lap"), 378, 66, Enum.TextXAlignment.Right } }) do
		label({ Name = "H", Parent = hdr, Text = h[1], Font = Theme.Fonts.Body, TextSize = 13, Color = SOFT, Size = UDim2.fromOffset(h[3], 22), Position = UDim2.fromOffset(h[2], 0),
			XAlign = h[4], Scaled = true, ZIndex = 34 })
	end
	local resRows = {}
	for k = 1, 8 do
		local row = box({ Name = "R" .. k, Parent = list, Color = WHITE, Transparency = 0.94, Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 28 + (k - 1) * 30),
			Radius = UDim.new(0, 8), ZIndex = 33, Visible = false })
		local pos = label({ Name = "Pos", Parent = row, Text = "", Font = Theme.Fonts.Number, TextSize = 17, Size = UDim2.fromOffset(24, 28), Position = UDim2.fromOffset(4, 0), ZIndex = 34 })
		local av = box({ Name = "Av", Parent = row, Color = WHITE, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(30, 3), Radius = UDim.new(1, 0), ZIndex = 34, Clip = true })
		local avImg = UIUtil.Create("ImageLabel", { Name = "Img", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = "", ZIndex = 35, Parent = av })
		local avEmoji = label({ Name = "E", Parent = av, Text = "", TextSize = 15, ZIndex = 36 })
		local name = label({ Name = "Name", Parent = row, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Size = UDim2.fromOffset(170, 28), Position = UDim2.fromOffset(58, 0),
			XAlign = Enum.TextXAlignment.Left, Truncate = true, ZIndex = 34 })
		local time = label({ Name = "Time", Parent = row, Text = "", Font = Theme.Fonts.Number, TextSize = 15, Size = UDim2.fromOffset(80, 28), Position = UDim2.fromOffset(222, 0),
			XAlign = Enum.TextXAlignment.Right, ZIndex = 34 })
		local gap = label({ Name = "Gap", Parent = row, Text = "", Font = Theme.Fonts.Number, TextSize = 14, Color = SOFT, Size = UDim2.fromOffset(64, 28), Position = UDim2.fromOffset(304, 0),
			XAlign = Enum.TextXAlignment.Right, ZIndex = 34 })
		local lap = label({ Name = "Lap", Parent = row, Text = "", Font = Theme.Fonts.Number, TextSize = 14, Color = MINT, Size = UDim2.fromOffset(66, 28), Position = UDim2.fromOffset(370, 0),
			XAlign = Enum.TextXAlignment.Right, ZIndex = 34 })
		resRows[k] = { Row = row, Pos = pos, Img = avImg, Emoji = avEmoji, Name = name, Time = time, Gap = gap, Lap = lap }
	end
	-- bas : médaille, récompense, XP, record
	local summary = box({ Name = "Summary", Parent = card, Color = INK, Transparency = 0.3, Size = UDim2.new(1, -40, 0, 112), Position = UDim2.fromOffset(20, 350),
		Radius = UDim.new(0, 16), ZIndex = 32 })
	local medal = box({ Name = "Medal", Parent = summary, Color = rgb(60, 50, 84), Size = UDim2.fromOffset(92, 92), Position = UDim2.fromOffset(10, 10), Radius = UDim.new(1, 0),
		Stroke = GOLD, StrokeThickness = 3, ZIndex = 33 })
	local medalIcon = label({ Name = "Icon", Parent = medal, Text = "", TextSize = 48, Size = UDim2.new(1, 0, 0, 62), ZIndex = 34 })
	local medalText = label({ Name = "T", Parent = medal, Text = "", TextSize = 12, Color = SOFT, Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 62), Scaled = true, ZIndex = 34 })
	local medalScale = UIUtil.Create("UIScale", { Parent = medal })
	local mine = label({ Name = "Mine", Parent = summary, Text = "", TextSize = 22, Color = GOLD, Size = UDim2.new(1, -330, 0, 30), Position = UDim2.fromOffset(116, 8),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, Rich = true, ZIndex = 33 })
	local detail = label({ Name = "Detail", Parent = summary, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Color = SOFT, Size = UDim2.new(1, -330, 0, 22), Position = UDim2.fromOffset(116, 38),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, Rich = true, ZIndex = 33 })
	local rankText = label({ Name = "Rank", Parent = summary, Text = "", TextSize = 16, Size = UDim2.new(1, -330, 0, 20), Position = UDim2.fromOffset(116, 62),
		XAlign = Enum.TextXAlignment.Left, Rich = true, ZIndex = 33 })
	local xpBar = box({ Name = "XpBar", Parent = summary, Color = rgb(30, 26, 44), Size = UDim2.new(1, -330, 0, 14), Position = UDim2.fromOffset(116, 86), Radius = UDim.new(1, 0),
		ZIndex = 33, Clip = true })
	local xpFill = box({ Name = "Fill", Parent = xpBar, Color = PINK, Size = UDim2.fromScale(0, 1), Radius = UDim.new(1, 0), ZIndex = 34 })
	UIUtil.Gradient(xpFill, ColorSequence.new(PINK, GOLD), 0)
	local stamp = label({ Name = "Stamp", Parent = card, Text = "", TextSize = 30, Color = RED, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(RES_W / 2 + 10, 324),
		Size = UDim2.fromOffset(250, 46), Visible = false, ZIndex = 40 })
	UIUtil.Create("UIStroke", { Color = WHITE, Thickness = 3, Parent = stamp })
	stamp.Rotation = -8
	local stampScale = UIUtil.Create("UIScale", { Parent = stamp })
	-- boutons
	local rematch = button({ Name = "Rematch", Parent = summary, Text = T("🔁 Race again"), TextSize = 17, Color = rgb(70, 150, 220), Size = UDim2.fromOffset(190, 44),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), ZIndex = 34 })
	local ok = button({ Name = "Ok", Parent = summary, Text = T("Awesome!"), Size = UDim2.fromOffset(190, 44), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), ZIndex = 34 })
	ok.Activated:Connect(function()
		RaceHud.HideResults()
	end)
	rematch.Activated:Connect(function()
		local id = parts.ResultsRoute
		RaceHud.HideResults()
		if callbacks.Rematch and id then
			callbacks.Rematch(id)
		end
	end)
	parts.ResultsDim = dim
	parts.Results = card
	parts.ResultsTitle = title
	parts.Columns = columns
	parts.ResRows = resRows
	parts.ResultsMine = mine
	parts.ResultsDetail = detail
	parts.ResultsRank = rankText
	parts.XpFill = xpFill
	parts.Medal = medal
	parts.MedalIcon = medalIcon
	parts.MedalText = medalText
	parts.MedalScale = medalScale
	parts.Stamp = stamp
	parts.StampScale = stampScale
	parts.ResultsOk = ok
	parts.Rematch = rematch
end

----------------------------------------------------------------------
-- Disposition (ordinateur / téléphone)
----------------------------------------------------------------------

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
	-- téléphone : tour des temps à droite sous les boutons du haut (la colonne des voitures est à gauche)
	parts.Tower.AnchorPoint = if phone then Vector2.new(1, 0) else Vector2.zero
	-- (ordinateur : à droite de la colonne des boutons de la voiture, sous la pastille de distance)
	parts.Tower.Position = if phone then UDim2.new(1, -74, 0, 50) else UDim2.fromOffset(104, 150)
	parts.PlaceFx.Position = if phone then UDim2.new(1, -330, 0, 54) else UDim2.fromOffset(348, 154)
	parts.RaceButton.Position = if phone then UDim2.fromOffset(14, 316) else UDim2.new(0, 22, 0.5, 140)
	parts.RaceTag.Visible = not phone
	local mini = if phone then 112 else 150
	parts.Mini.Size = UDim2.fromOffset(mini, mini)
	parts.MiniLine.Size = UDim2.fromOffset(mini - 24, mini - 24)
	parts.MiniDots.Size = UDim2.fromOffset(mini - 24, mini - 24)
	if parts.MiniPoints then
		drawLine(parts.MiniLine, parts.MiniPoints, WHITE, 4, 6, parts.MiniClosed)
	end
	parts.Arrow.Position = if phone then UDim2.new(0.5, 0, 0, 96) else UDim2.new(0.5, 0, 0, 112)
	parts.Delta.Position = if phone then UDim2.new(0.5, 0, 0, 142) else UDim2.new(0.5, 0, 0, 160)
	parts.Lobby.Position = parts.Arrow.Position
	parts.Reset.Position = UDim2.new(1, -12, 1, -(mini + 22))
	parts.Quit.Position = UDim2.new(1, -104, 1, -(mini + 22))
	-- nitro : à gauche de la mini-carte ; téléphone : plus gros bouton
	parts.Nitro.Position = UDim2.new(1, -(mini + 24), 1, -12)
	parts.Nitro.Size = if phone then UDim2.fromOffset(196, 72) else UDim2.fromOffset(206, 66)
	parts.NitroBtn.Size = if phone then UDim2.fromOffset(104, 60) else UDim2.fromOffset(110, 50)
	parts.NitroKey.Visible = not phone
	parts.Spectate.Size = if phone then UDim2.fromOffset(520, 60) else UDim2.fromOffset(560, 64)
	-- résultats : la carte est réduite sur téléphone
	if parts.ResultsScale then
		parts.ResultsScale.Scale = if phone then math.min(0.78, (designH - 16) / RES_H) else 1
	end
	for _, hook in ipairs(layoutHooks) do
		pcall(hook)
	end
end

-- (RaceMenu) appelé à chaque changement de taille
function RaceHud.OnLayout(fn: () -> ())
	table.insert(layoutHooks, fn)
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
	buildResults(root)
	table.insert(conns, screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	layout()
end

function RaceHud.Root(): Frame?
	return parts.Root
end

function RaceHud.IsPhone(): boolean
	return phone
end

function RaceHud.Relayout()
	layout()
end

function RaceHud.Destroy()
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	table.clear(layoutHooks)
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(parts)
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

function RaceHud.SetLobby(info: { [string]: any }?)
	if not parts.Lobby then
		return
	end
	parts.Lobby.Visible = info ~= nil
	if info then
		parts.LobbyText.Text = info.Text or ""
	end
end

local function placeColor(place: number): Color3
	return if place == 1 then GOLD elseif place == 2 then SILVER elseif place == 3 then BRONZE else WHITE
end
RaceHud.PlaceColor = placeColor

local function setTower(i: { [string]: any })
	local tower = i.Tower or {}
	local rows = parts.TowerRows
	local max = if phone then 5 else TOWER_ROWS
	-- téléphone : les lignes autour de moi
	local first = 1
	if #tower > max then
		local mine = 1
		for k, r in ipairs(tower) do
			if r.Me then
				mine = k
			end
		end
		first = math.clamp(mine - math.floor(max / 2), 1, #tower - max + 1)
	end
	local shown = 0
	for k = 1, TOWER_ROWS do
		local r = tower[first + k - 1]
		local row = rows[k]
		if r and k <= max then
			shown += 1
			row.Row.Visible = true
			row.Row.BackgroundTransparency = if r.Me then 0.82 else 1
			row.Pos.Text = tostring(r.Pos)
			row.PosBg.BackgroundColor3 = placeColor(r.Pos)
			row.Stripe.BackgroundColor3 = r.Color or CYAN
			row.Name.Text = r.Name or ""
			row.Name.TextColor3 = if r.Me then GOLD elseif r.Out then rgb(150, 140, 160) else WHITE
			row.Gap.Text = r.Gap or ""
		else
			row.Row.Visible = false
		end
	end
	local foot = i.Foot or ""
	parts.TowerFoot.Text = foot
	parts.TowerFoot.Position = UDim2.fromOffset(10, 68 + shown * 24)
	parts.TowerHolder.Size = UDim2.new(1, -12, 0, shown * 24)
	parts.Tower.Size = UDim2.fromOffset(236, 68 + shown * 24 + (if foot ~= "" then 40 else 4))
end

local function setNitro(n: { [string]: any }?)
	local holder = parts.Nitro
	holder.Visible = n ~= nil
	if not n then
		parts.BoostGlow.BackgroundTransparency = 1
		return
	end
	local charges = math.floor(tonumber(n.Charges) or 0)
	for k, pip in ipairs(parts.NitroPips) do
		local on = k <= charges
		pip.BackgroundColor3 = if on then NITRO else rgb(60, 66, 90)
		pip.Visible = k <= (n.Max or 3)
	end
	parts.NitroFill.Size = UDim2.fromScale(math.clamp(tonumber(n.Gauge) or 0, 0, 1), 1)
	local boosting = (tonumber(n.Boost) or 0) > 0
	parts.NitroBtn.BackgroundColor3 = if boosting then CYAN elseif charges > 0 then rgb(40, 90, 200) else rgb(70, 70, 92)
	parts.NitroBtn.Text = if boosting then "🔥🔥🔥" else "🔥 NITRO"
	parts.BoostGlow.BackgroundTransparency = if boosting then 0.35 + 0.65 * (1 - math.clamp(tonumber(n.Boost) or 0, 0, 1)) else 1
end

function RaceHud.SetRace(info: { [string]: any }?)
	if not parts.Tower then
		return
	end
	local on = info ~= nil
	parts.Tower.Visible = on
	parts.Arrow.Visible = on and info ~= nil and info.Cp ~= nil
	parts.Mini.Visible = on
	parts.Reset.Visible = on and info ~= nil and info.Running == true
	parts.Quit.Visible = on and info ~= nil and info.Running == true
	if not on then
		parts.Wrong.Visible = false
		setNitro(nil)
		return
	end
	local i = info :: { [string]: any }
	parts.Place.Text = tostring(i.Place or 1)
	parts.Place.TextColor3 = placeColor(i.Place or 1)
	parts.Count.Text = "/" .. tostring(i.Count or 1)
	parts.Lap.Text = if (i.Laps or 1) > 1 then T("Lap %d/%d", math.clamp(i.Lap or 1, 1, i.Laps), i.Laps) else T("Sprint")
	parts.Time.Text = i.Time or "0:00.00"
	setTower(i)
	if i.Cp then
		parts.CpText.Text = i.Cp
		parts.Needle.Rotation = i.Arrow or 0
	end
	parts.Wrong.Visible = i.Wrong == true
	setNitro(if i.Running then i.Nitro else nil)
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
	fadeOut(f, 1.3, function()
		return flashToken == token
	end)
end

-- Écart avec le fantôme (s) : vert en avance, rouge en retard
function RaceHud.Delta(seconds: number?, prefix: string?)
	local d = parts.Delta
	if not d or seconds == nil then
		return
	end
	deltaToken += 1
	local token = deltaToken
	local s = seconds :: number
	d.Text = (prefix or "👻 ") .. string.format("%s%.2f s", if s <= 0 then "−" else "+", math.abs(s))
	d.TextColor3 = if s <= 0 then MINT else RED
	d.TextTransparency = 0
	local st = d:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 0
	end
	UIUtil.Pop(d, 0.7, 0.2)
	fadeOut(d, 2.2, function()
		return deltaToken == token
	end)
end

-- Compteur de dérapage (points de la glissade en cours)
function RaceHud.Drift(points: number)
	local d = parts.Drift
	if not d then
		return
	end
	driftToken += 1
	local token = driftToken
	d.Text = string.format("DRIFT  +%d", math.floor(points))
	d.TextTransparency = 0
	local st = d:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 0
	end
	parts.DriftScale.Scale = 1.15
	TweenService:Create(parts.DriftScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	fadeOut(d, 1.2, function()
		return driftToken == token
	end)
end

-- ▲ P2 / ▼ P3
function RaceHud.PlaceChange(place: number, up: boolean)
	local p = parts.PlaceFx
	if not p then
		return
	end
	placeToken += 1
	local token = placeToken
	p.Text = (if up then "▲ P" else "▼ P") .. tostring(place)
	p.TextColor3 = if up then MINT else RED
	p.TextTransparency = 0
	local st = p:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 0
	end
	UIUtil.Pop(p, 0.6, 0.25)
	fadeOut(p, 1.4, function()
		return placeToken == token
	end)
end

-- Bannière (dernier tour...)
function RaceHud.Banner(text: string, color: Color3?)
	local b = parts.Banner
	if not b then
		return
	end
	bannerToken += 1
	local token = bannerToken
	parts.BannerText.Text = text
	parts.BannerText.TextColor3 = color or GOLD
	b.Visible = true
	UIUtil.Pop(b, 0.6, 0.3)
	task.delay(2.2, function()
		if bannerToken == token and parts.Banner == b then
			b.Visible = false
		end
	end)
end

function RaceHud.SetSpectate(info: { [string]: any }?)
	if not parts.Spectate then
		return
	end
	parts.Spectate.Visible = info ~= nil
	if info then
		parts.SpecText.Text = info.Text or ""
	end
end

----------------------------------------------------------------------
-- Résultats : podium animé, classement, médaille, XP
----------------------------------------------------------------------

local function confetti(parent: Instance)
	local colors = { PINK, GOLD, CYAN, MINT, WHITE, rgb(186, 156, 246) }
	for k = 1, 52 do
		local x = math.random()
		local piece = box({ Name = "Confetti", Parent = parent, Color = colors[(k % #colors) + 1], AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(8 + math.random() * 6, 5 + math.random() * 4), Position = UDim2.new(x, 0, 0, -20), ZIndex = 45 })
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

local function setAvatar(img: ImageLabel, emoji: TextLabel, row: any)
	if row.AI or (tonumber(row.UserId) or 0) <= 0 then
		img.Image = ""
		emoji.Text = "🤖"
	else
		img.Image = UIUtil.HeadshotUrl(row.UserId, 150)
		emoji.Text = ""
	end
end

-- res = { Title, Route, Rows = { { Place, Name, UserId, AI, TimeText, GapText, LapText, Me } },
--         Mine (texte riche), Detail, Medal (0..3), MedalText, Stamp?, Xp = { From, To, Gain,
--         RankFrom, RankTo (RaceRules.Rank) }, Reward }
function RaceHud.ShowResults(res: { [string]: any })
	if not parts.ResultsDim then
		return
	end
	resultsToken += 1
	local token = resultsToken
	parts.ResultsRoute = res.Route
	parts.ResultsDim.Visible = true
	parts.ResultsTitle.Text = res.Title or ""
	parts.ResultsMine.Text = res.Mine or ""
	parts.ResultsDetail.Text = res.Detail or ""
	parts.Rematch.Visible = res.Route ~= nil
	UIUtil.Pop(parts.Results, 0.85, 0.25)
	local byPlace = {}
	for _, row in ipairs(res.Rows or {}) do
		byPlace[row.Place] = row
	end
	-- colonnes : 3e, puis 2e, puis 1er (le suspense), qui montent en douceur
	for _, place in ipairs({ 3, 2, 1 }) do
		local c = parts.Columns[place]
		local row = byPlace[place]
		c.Block.Size = UDim2.fromOffset(114, 0)
		c.Head.Visible = false
		c.Name.Visible = false
		c.Time.Visible = false
		if row then
			c.Name.Text = row.Name or ""
			c.Time.Text = row.TimeText or ""
			setAvatar(c.Img, c.Emoji, row)
		end
	end
	-- classement complet : lignes cachées puis glissées une à une
	for k, r in ipairs(parts.ResRows) do
		local row = (res.Rows or {})[k]
		r.Row.Visible = false
		if row then
			r.Pos.Text = tostring(row.Place)
			r.Pos.TextColor3 = placeColor(row.Place or 9)
			r.Name.Text = row.Name or ""
			r.Name.TextColor3 = if row.Me then GOLD else WHITE
			r.Time.Text = row.TimeText or ""
			r.Gap.Text = row.GapText or ""
			r.Lap.Text = row.LapText or ""
			r.Row.BackgroundTransparency = if row.Me then 0.8 else 0.94
			setAvatar(r.Img, r.Emoji, row)
		end
	end
	-- médaille / rang
	local medal = tonumber(res.Medal) or 0
	parts.MedalIcon.Text = if medal >= 1 and medal <= 3 then ({ "🥇", "🥈", "🥉" })[medal] else "🏁"
	parts.MedalText.Text = res.MedalText or ""
	parts.Medal.Visible = false
	parts.Stamp.Visible = false
	local xp = res.Xp
	if xp and xp.RankFrom then
		parts.ResultsRank.Text = string.format("%s <b>%s</b> · %d XP", xp.RankFrom.Icon or "", T(xp.RankFrom.Name or "") .. (if (xp.RankFrom.Division or 0) > 0 then " " .. ({ "I", "II", "III" })[xp.RankFrom.Division] else ""), math.floor(xp.From or 0))
		parts.XpFill.Size = UDim2.fromScale(math.clamp(xp.RankFrom.Progress or 0, 0, 1), 1)
	else
		parts.ResultsRank.Text = ""
		parts.XpFill.Size = UDim2.fromScale(0, 1)
	end
	task.spawn(function()
		for step, place in ipairs({ 3, 2, 1 }) do
			task.wait(if step == 1 then 0.35 else 0.42)
			if token ~= resultsToken or not parts.Columns then
				return
			end
			local c = parts.Columns[place]
			if byPlace[place] then
				TweenService:Create(c.Block, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(114, c.Height) }):Play()
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
		-- lignes du classement
		for k, r in ipairs(parts.ResRows) do
			if (res.Rows or {})[k] then
				task.wait(0.09)
				if token ~= resultsToken or not parts.ResRows then
					return
				end
				r.Row.Visible = true
				local target = r.Row.Position
				r.Row.Position = target + UDim2.fromOffset(60, 0)
				TweenService:Create(r.Row, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
			end
		end
		task.wait(0.25)
		if token ~= resultsToken or not parts.Medal then
			return
		end
		-- médaille (tampon)
		parts.Medal.Visible = true
		parts.MedalScale.Scale = 2.2
		TweenService:Create(parts.MedalScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		-- XP qui se remplit (+ passage de rang)
		if xp and xp.RankTo then
			task.wait(0.3)
			if token ~= resultsToken or not parts.XpFill then
				return
			end
			local up = xp.RankTo.Label ~= xp.RankFrom.Label
			if up then
				TweenService:Create(parts.XpFill, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, 1) }):Play()
				task.wait(0.5)
				if token ~= resultsToken or not parts.XpFill then
					return
				end
				parts.XpFill.Size = UDim2.fromScale(0, 1)
			end
			TweenService:Create(parts.XpFill, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(xp.RankTo.Progress or 0, 0, 1), 1) }):Play()
			local divTo = if (xp.RankTo.Division or 0) > 0 then " " .. ({ "I", "II", "III" })[xp.RankTo.Division] else ""
			parts.ResultsRank.Text = string.format("%s <b>%s</b> · %d XP  <font color=\"#6EE2AA\">+%d XP</font>%s", xp.RankTo.Icon or "", T(xp.RankTo.Name or "") .. divTo,
				math.floor(xp.To or 0), math.floor(xp.Gain or 0), if up then "  <font color=\"#FFCC3C\">" .. T("RANK UP!") .. "</font>" else "")
		end
		-- tampon "NOUVEAU RECORD"
		if res.Stamp and res.Stamp ~= "" then
			task.wait(0.3)
			if token ~= resultsToken or not parts.Stamp then
				return
			end
			parts.Stamp.Text = res.Stamp
			parts.Stamp.Visible = true
			parts.StampScale.Scale = 2.5
			TweenService:Create(parts.StampScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		task.wait(0.3)
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
