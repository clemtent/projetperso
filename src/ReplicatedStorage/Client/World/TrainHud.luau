--[[
	TrainHud (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TrainHud

	🚂 Interface du train de Dopamine Town (v11, TRAIN11) : ScreenGui
	"TrainGui" (gardée visible en ville : KEEP_GUIS de TownClient), pilotée
	par TrainClient :
	  - CARTE DE GARE (près d'un quai) : nom de la gare, prochains trains
	    (ligne, direction, "À quai · départ 0:12" ou "dans 2:31"), petit plan
	    de la ligne de ceinture (4 gares, les 2 trains en direct) ;
	  - EN VOYAGE : bandeau "🚂 Dopamine Express → Prochain arrêt : Gare des
	    Lofts · 0:42", barre de progression entre deux gares, bouton
	    "🚪 Descendre" (aussi : saut) ;
	  - CONVOI DE DIAMANTS : bandeau en haut ("💎 Le convoi de diamants
	    s'arrête à Gare X dans 1:42" / "en gare : 2:55 pour le braquer !"),
	    distance jusqu'au quai.
	Les mini-jeux, l'équipe, les sacs et les récompenses du braquage sont
	l'interface générique de BANK11 (HeistClient).
	Ordinateur + téléphone (UIScale). Aucun son.

	API :
	  TrainHud.Build(callbacks)   { Leave() }
	  TrainHud.Destroy()
	  TrainHud.SetStation(info?)  { Name, Rows = { { Icon, Line, Dir, When, Now } }, Map = { Stations = {k -> {X,Y}}, Trains = { {X, Y, Color} } , Here } }
	  TrainHud.SetRide(info?)     { Line, Next, When, Progress, Color }
	  TrainHud.SetHeist(info?)    { Title, Sub, Hot }
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local TrainHud = {}

TrainHud.GUI_NAME = "TrainGui"

local rgb = Color3.fromRGB
local INK = rgb(20, 24, 36)
local PANEL = rgb(24, 30, 46)
local GOLD = rgb(255, 206, 84)
local WHITE = rgb(246, 246, 250)
local MUTED = rgb(170, 178, 196)
local CYAN = rgb(110, 220, 255)

local gui: ScreenGui? = nil
local refs: any = {}
local callbacks: any = {}

local function T(text: string): string
	return Locale.T(text)
end

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, th: number, tr: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = th
	s.Transparency = tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function text(parent: Instance, name: string, size: UDim2, pos: UDim2, value: string, color: Color3, font: Enum.Font?, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = value
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = font or Enum.Font.GothamBold
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 30
	c.Parent = l
	return l
end

local function isPhone(): boolean
	local camera = workspace.CurrentCamera
	local small = camera ~= nil and math.min(camera.ViewportSize.X, camera.ViewportSize.Y) < 520
	return small or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
end

function TrainHud.IsPhone(): boolean
	return isPhone()
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TrainHud.Build(cb: any)
	TrainHud.Destroy()
	callbacks = cb or {}
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = TrainHud.GUI_NAME
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 18
	local scale = Instance.new("UIScale")
	scale.Scale = if isPhone() then 0.78 else 1
	scale.Parent = screen
	gui = screen

	-- CARTE DE GARE (à gauche, au milieu de l'écran)
	local card = frame(screen, "StationCard", UDim2.fromOffset(330, 236), UDim2.new(0, 14, 0.42, 0), PANEL, 0.08)
	card.AnchorPoint = Vector2.new(0, 0.5)
	card.Visible = false
	corner(card, 14)
	stroke(card, GOLD, 2, 0.35)
	local head = frame(card, "Head", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 0), rgb(24, 40, 70))
	corner(head, 14)
	frame(head, "HeadFill", UDim2.new(1, 0, 0, 14), UDim2.new(0, 0, 1, -14), rgb(24, 40, 70))
	local title = text(head, "Title", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(12, 7), "", WHITE, Enum.Font.GothamBlack)
	local rows = {}
	for i = 1, 2 do
		local y = 46 + (i - 1) * 46
		local row = frame(card, "Row" .. i, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, y), INK, 0.2)
		corner(row, 8)
		local icon = text(row, "Icon", UDim2.fromOffset(30, 30), UDim2.fromOffset(6, 5), "🚂", WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		local line = text(row, "Line", UDim2.new(0.62, -40, 0, 18), UDim2.fromOffset(40, 3), "", WHITE, Enum.Font.GothamBold)
		local dir = text(row, "Dir", UDim2.new(0.62, -40, 0, 14), UDim2.fromOffset(40, 22), "", MUTED, Enum.Font.Gotham)
		local when = text(row, "When", UDim2.new(0.38, -8, 0, 30), UDim2.new(0.62, 0, 0, 5), "", GOLD, Enum.Font.GothamBlack, Enum.TextXAlignment.Right)
		rows[i] = { Frame = row, Icon = icon, Line = line, Dir = dir, When = when }
	end
	-- plan de la ligne (carré arrondi, 4 gares, trains en direct)
	local map = frame(card, "Map", UDim2.new(1, -16, 0, 92), UDim2.fromOffset(8, 140), rgb(18, 22, 34), 0.1)
	corner(map, 8)
	local loop = frame(map, "Loop", UDim2.fromOffset(150, 70), UDim2.new(0.5, 0, 0.5, 0), rgb(0, 0, 0), 1)
	loop.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(loop, 18)
	stroke(loop, rgb(150, 150, 170), 3, 0)
	local stationDots, trainDots = {}, {}
	for k = 1, 4 do
		local d = frame(map, "Stop" .. k, UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.5), WHITE)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		corner(d, 5)
		stroke(d, INK, 2)
		stationDots[k] = d
	end
	for i = 1, 2 do
		local d = frame(map, "Train" .. i, UDim2.fromOffset(14, 14), UDim2.fromScale(0.5, 0.5), if i == 1 then rgb(220, 40, 60) else rgb(0, 170, 180))
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.ZIndex = 3
		corner(d, 7)
		stroke(d, WHITE, 2)
		trainDots[i] = d
	end
	local legend = text(map, "Legend", UDim2.new(1, -12, 0, 14), UDim2.new(0, 6, 1, -16), "", MUTED, Enum.Font.Gotham)
	refs.Card = card
	refs.Title = title
	refs.Rows = rows
	refs.Map = map
	refs.StationDots = stationDots
	refs.TrainDots = trainDots
	refs.Legend = legend

	-- BANDEAU DE VOYAGE (en bas, au centre)
	local ride = frame(screen, "Ride", UDim2.fromOffset(460, 78), UDim2.new(0.5, 0, 1, -118), PANEL, 0.06)
	ride.AnchorPoint = Vector2.new(0.5, 1)
	ride.Visible = false
	corner(ride, 14)
	stroke(ride, GOLD, 2, 0.35)
	local rideLine = text(ride, "Line", UDim2.new(1, -150, 0, 22), UDim2.fromOffset(14, 8), "", WHITE, Enum.Font.GothamBlack)
	local rideNext = text(ride, "Next", UDim2.new(1, -150, 0, 20), UDim2.fromOffset(14, 32), "", GOLD, Enum.Font.GothamBold)
	local bar = frame(ride, "Bar", UDim2.new(1, -150, 0, 8), UDim2.fromOffset(14, 60), rgb(60, 66, 84))
	corner(bar, 4)
	local fill = frame(bar, "Fill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), CYAN)
	corner(fill, 4)
	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.Size = UDim2.fromOffset(120, 54)
	leave.Position = UDim2.new(1, -130, 0.5, -27)
	leave.BackgroundColor3 = rgb(230, 80, 70)
	leave.Text = "🚪 " .. T("Get off")
	leave.TextColor3 = WHITE
	leave.TextScaled = true
	leave.Font = Enum.Font.GothamBlack
	leave.AutoButtonColor = true
	leave.Parent = ride
	corner(leave, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = leave
	leave.Activated:Connect(function()
		if callbacks.Leave then
			pcall(callbacks.Leave)
		end
	end)
	refs.Ride = ride
	refs.RideLine = rideLine
	refs.RideNext = rideNext
	refs.RideFill = fill

	-- BANDEAU DU CONVOI (en haut, au centre)
	local heist = frame(screen, "Heist", UDim2.fromOffset(520, 62), UDim2.new(0.5, 0, 0, 64), rgb(40, 16, 60), 0.05)
	heist.AnchorPoint = Vector2.new(0.5, 0)
	heist.Visible = false
	corner(heist, 14)
	stroke(heist, rgb(150, 230, 255), 2, 0.2)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(rgb(70, 30, 110), rgb(20, 60, 110))
	grad.Parent = heist
	local hTitle = text(heist, "Title", UDim2.new(1, -24, 0, 28), UDim2.fromOffset(12, 5), "", WHITE, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	local hSub = text(heist, "Sub", UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 35), "", rgb(180, 240, 255), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	refs.Heist = heist
	refs.HeistTitle = hTitle
	refs.HeistSub = hSub
	refs.HeistStroke = heist:FindFirstChildOfClass("UIStroke")

	screen.Parent = playerGui
end

function TrainHud.Destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
	refs = {}
end

----------------------------------------------------------------------
-- Mises à jour
----------------------------------------------------------------------

function TrainHud.SetStation(info: any?)
	local card = refs.Card
	if not card then
		return
	end
	if not info then
		card.Visible = false
		return
	end
	card.Visible = true
	refs.Title.Text = "🚉 " .. info.Name
	for i, row in ipairs(refs.Rows) do
		local r = info.Rows and info.Rows[i]
		row.Frame.Visible = r ~= nil
		if r then
			row.Icon.Text = r.Icon or "🚂"
			row.Line.Text = r.Line or ""
			row.Dir.Text = r.Dir or ""
			row.When.Text = r.When or ""
			row.When.TextColor3 = if r.Now then rgb(120, 255, 150) else GOLD
		end
	end
	local m = info.Map
	if m then
		for k, d in ipairs(refs.StationDots) do
			local p = m.Stations and m.Stations[k]
			if p then
				d.Position = UDim2.new(0.5, p.X * 75, 0.5, p.Y * 35)
				d.BackgroundColor3 = if k == m.Here then GOLD else WHITE
				d.Size = if k == m.Here then UDim2.fromOffset(14, 14) else UDim2.fromOffset(10, 10)
			end
		end
		for i, d in ipairs(refs.TrainDots) do
			local p = m.Trains and m.Trains[i]
			d.Visible = p ~= nil
			if p then
				d.Position = UDim2.new(0.5, p.X * 75, 0.5, p.Y * 35)
			end
		end
		refs.Legend.Text = m.Legend or ""
	end
end

function TrainHud.SetRide(info: any?)
	local ride = refs.Ride
	if not ride then
		return
	end
	if not info then
		ride.Visible = false
		return
	end
	ride.Visible = true
	refs.RideLine.Text = info.Line or ""
	refs.RideNext.Text = info.Next or ""
	refs.RideFill.Size = UDim2.fromScale(math.clamp(info.Progress or 0, 0, 1), 1)
end

function TrainHud.SetHeist(info: any?)
	local h = refs.Heist
	if not h then
		return
	end
	if not info then
		h.Visible = false
		return
	end
	h.Visible = true
	refs.HeistTitle.Text = info.Title or ""
	refs.HeistSub.Text = info.Sub or ""
	if refs.HeistStroke then
		refs.HeistStroke.Color = if info.Hot then rgb(255, 120, 80) else rgb(150, 230, 255)
	end
end

function TrainHud.Debug(): any
	return {
		Built = gui ~= nil,
		Card = refs.Card and refs.Card.Visible or false,
		Ride = refs.Ride and refs.Ride.Visible or false,
		Heist = refs.Heist and refs.Heist.Visible or false,
		Title = refs.Title and refs.Title.Text or nil,
		HeistTitle = refs.HeistTitle and refs.HeistTitle.Text or nil,
	}
end

return TrainHud
