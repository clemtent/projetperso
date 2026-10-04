--[[
	RaceMenu (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > RaceMenu

	🏁 Menu des courses de rue (v11, RACE11), dans la ScreenGui "RaceGui"
	de RaceHud. 3 onglets :
	  - 🏁 COURSES : la liste des 7 parcours (couleur, icône, tours, longueur,
	    état : libre / N inscrits + départ dans X s / en course, ta médaille)
	    et la FICHE du parcours choisi : grand tracé, description, virages,
	    temps des MÉDAILLES (or / argent / bronze), ton record + ta médaille,
	    record du serveur et TOP 5 avec les AVATARS, boutons S'inscrire /
	    Quitter et 👁️ Regarder (course en cours) ;
	  - 📊 MES STATS : carte de RANG (Bronze III -> Diamant, barre d'XP,
	    prochain palier), tuiles (courses, victoires, podiums, % de
	    victoires, dépassements, meilleur dérapage, distance, records),
	    GRAPHE des places de tes 20 dernières courses (points or / argent /
	    bronze), tableau par parcours (courses, victoires, meilleur temps,
	    médaille, voiture) ;
	  - 🏆 CLASSEMENT : pilotes du serveur par XP (avatar, rang, victoires) et
	    podiums des records de chaque parcours (avatars).
	Ordinateur + téléphone (UIScale).

	API (RaceClient) :
	  RaceMenu.Build(root, callbacks)   { Join(routeId, joined), Watch(routeId), Close() }
	  RaceMenu.Destroy()
	  RaceMenu.SetOpen(open) / RaceMenu.IsOpen()
	  RaceMenu.Update(data)  { Sub, Foot, Routes = { RouteCard }, Rank, Tiles, History, RouteStats, Pilots, Records,
	                           StatsKey, BoardKey (texte : stats / classement reconstruits s'ils changent) }
	  RaceMenu.SetTab(tab) ("Races" | "Stats" | "Board") / RaceMenu.Debug()
]]

local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)
local RaceHud = require(script.Parent.RaceHud)

local RaceMenu = {}

local C = RaceHud.Colors
local rgb = Color3.fromRGB
local label = RaceHud.Label
local box = RaceHud.Box
local button = RaceHud.Button

local W, H = 940, 560

local parts: { [string]: any } = {}
local callbacks: { [string]: any } = {}
local open = false
local tab = "Races"
local selected: string? = nil
local lastData: any = nil

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

local function avatar(parent: Instance, size: number, pos: UDim2, z: number): (Frame, ImageLabel, TextLabel)
	local holder = box({ Name = "Av", Parent = parent, Color = C.WHITE, Size = UDim2.fromOffset(size, size), Position = pos, Radius = UDim.new(1, 0), ZIndex = z, Clip = true })
	local img = UIUtil.Create("ImageLabel", { Name = "Img", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = "", ZIndex = z + 1, Parent = holder })
	local emoji = label({ Name = "E", Parent = holder, Text = "", TextSize = math.floor(size * 0.6), ZIndex = z + 2 })
	return holder, img, emoji
end

local function setAvatar(img: ImageLabel, emoji: TextLabel, userId: any)
	local id = tonumber(userId) or 0
	if id > 0 then
		img.Image = UIUtil.HeadshotUrl(id, 150)
		emoji.Text = ""
	else
		img.Image = ""
		emoji.Text = "🤖"
	end
end

local function clear(holder: Instance, keep: { [string]: boolean }?)
	for _, child in ipairs(holder:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") and not child:IsA("UICorner") and not child:IsA("UIStroke")
			and not child:IsA("UIPadding") and not child:IsA("UIGradient") and not (keep and keep[child.Name]) then
			child:Destroy()
		end
	end
end

local function color3(c: any, default: Color3): Color3
	if typeof(c) == "Color3" then
		return c
	end
	if type(c) == "table" and type(c[1]) == "number" then
		return rgb(c[1], c[2] or 0, c[3] or 0)
	end
	return default
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildFrame(root: Frame)
	local dim = box({ Name = "MenuDim", Parent = root, Color = rgb(0, 0, 0), Transparency = 0.45, Visible = false, ZIndex = 20 })
	UIUtil.SinkClicks(dim)
	local holder = box({ Name = "MenuHolder", Parent = dim, Transparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(W, H), ZIndex = 21 })
	local scale = UIUtil.Create("UIScale", { Parent = holder })
	local panel = box({ Name = "Menu", Parent = holder, Color = C.WHITE, Size = UDim2.fromScale(1, 1), Radius = UDim.new(0, 22), Stroke = C.PINK, StrokeThickness = 3, ZIndex = 21, Clip = true })
	UIUtil.Gradient(panel, ColorSequence.new(C.PANEL2, C.PANEL), 90)
	local band = box({ Name = "Band", Parent = panel, Transparency = 1, Size = UDim2.new(1, -44, 0, 10), Position = UDim2.fromOffset(22, 8), ZIndex = 22, Clip = true })
	RaceHud.Checker(band, 70, 2, 22)
	label({ Name = "Title", Parent = panel, Text = T("🏁 Street races"), TextSize = 30, Size = UDim2.fromOffset(330, 40), Position = UDim2.fromOffset(22, 22),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 22 })
	local sub = label({ Name = "Sub", Parent = panel, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Color = C.SOFT, Size = UDim2.fromOffset(560, 20),
		Position = UDim2.fromOffset(24, 60), XAlign = Enum.TextXAlignment.Left, Scaled = true, ZIndex = 22 })
	-- badge de rang (en haut à droite)
	local badge = box({ Name = "RankBadge", Parent = panel, Color = C.INK, Transparency = 0.2, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 22),
		Size = UDim2.fromOffset(250, 52), Radius = UDim.new(0, 14), Stroke = C.GOLD, ZIndex = 22 })
	local badgeIcon = label({ Name = "Icon", Parent = badge, Text = "🥉", TextSize = 30, Size = UDim2.fromOffset(44, 52), Position = UDim2.fromOffset(4, 0), ZIndex = 23 })
	local badgeText = label({ Name = "Text", Parent = badge, Text = "", TextSize = 17, Size = UDim2.new(1, -56, 0, 24), Position = UDim2.fromOffset(50, 4),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 23 })
	local badgeBar = box({ Name = "Bar", Parent = badge, Color = rgb(30, 26, 44), Size = UDim2.new(1, -60, 0, 10), Position = UDim2.fromOffset(50, 32), Radius = UDim.new(1, 0), ZIndex = 23, Clip = true })
	local badgeFill = box({ Name = "Fill", Parent = badgeBar, Color = C.GOLD, Size = UDim2.fromScale(0.3, 1), Radius = UDim.new(1, 0), ZIndex = 24 })
	UIUtil.Gradient(badgeFill, ColorSequence.new(C.PINK, C.GOLD), 0)
	local close = UIUtil.CloseButton({ Name = "CloseRace", Size = 40, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 26), ZIndex = 24 })
	close.Parent = panel
	close.Activated:Connect(function()
		if callbacks.Close then
			callbacks.Close()
		end
	end)
	-- onglets
	local tabs = {}
	for k, spec in ipairs({ { "Races", T("🏁 Races") }, { "Stats", T("📊 My stats") }, { "Board", T("🏆 Leaderboard") } }) do
		local b = button({ Name = "Tab_" .. spec[1], Parent = panel, Text = spec[2], TextSize = 17, Color = rgb(70, 56, 100), Size = UDim2.fromOffset(170, 34),
			Position = UDim2.fromOffset(22 + (k - 1) * 178, 84), Radius = UDim.new(1, 0), ZIndex = 23 })
		b.Activated:Connect(function()
			RaceMenu.SetTab(spec[1])
		end)
		tabs[spec[1]] = b
	end
	local foot = label({ Name = "Foot", Parent = panel, Text = "", Font = Theme.Fonts.Body, TextSize = 14, Color = C.SOFT, Size = UDim2.new(1, -40, 0, 22),
		Position = UDim2.new(0, 20, 1, -28), Scaled = true, ZIndex = 22 })
	local pages = {}
	for _, id in ipairs({ "Races", "Stats", "Board" }) do
		pages[id] = box({ Name = "Page_" .. id, Parent = panel, Transparency = 1, Size = UDim2.new(1, -32, 0, H - 160), Position = UDim2.fromOffset(16, 128), ZIndex = 22, Visible = id == tab })
	end
	parts.Dim = dim
	parts.Holder = holder
	parts.Scale = scale
	parts.Panel = panel
	parts.Sub = sub
	parts.Foot = foot
	parts.Tabs = tabs
	parts.Pages = pages
	parts.BadgeIcon = badgeIcon
	parts.BadgeText = badgeText
	parts.BadgeFill = badgeFill
	parts.Badge = badge
end

-- Onglet COURSES : liste + fiche
local function buildRaces()
	local page = parts.Pages.Races
	local list = UIUtil.Create("ScrollingFrame", {
		Name = "List", BackgroundColor3 = C.INK, BackgroundTransparency = 0.4, BorderSizePixel = 0, Size = UDim2.fromOffset(300, H - 164),
		CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ZIndex = 23, Parent = page,
	})
	UIUtil.Corner(list, 14)
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	UIUtil.Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10), Parent = list })
	local detail = box({ Name = "Detail", Parent = page, Color = C.INK, Transparency = 0.4, Size = UDim2.fromOffset(W - 32 - 312, H - 164), Position = UDim2.fromOffset(312, 0),
		Radius = UDim.new(0, 14), ZIndex = 23 })
	local DW = W - 32 - 312
	-- tracé
	local map = box({ Name = "Map", Parent = detail, Color = C.WHITE, Size = UDim2.fromOffset(236, 236), Position = UDim2.fromOffset(12, 12), Radius = UDim.new(0, 14), ZIndex = 24, Clip = true })
	UIUtil.Gradient(map, ColorSequence.new(rgb(74, 108, 86), rgb(42, 60, 52)), 90)
	local mapLine = box({ Name = "Line", Parent = map, Transparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(200, 200), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 25 })
	local mapShadow = box({ Name = "Shadow", Parent = map, Transparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(200, 200), Position = UDim2.new(0.5, 2, 0.5, 3), ZIndex = 24 })
	-- en-tête
	local icon = label({ Name = "Icon", Parent = detail, Text = "", TextSize = 38, Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(260, 10), ZIndex = 24 })
	local name = label({ Name = "Name", Parent = detail, Text = "", TextSize = 26, Size = UDim2.fromOffset(DW - 320, 34), Position = UDim2.fromOffset(310, 10), XAlign = Enum.TextXAlignment.Left,
		Scaled = true, ZIndex = 24 })
	local desc = label({ Name = "Desc", Parent = detail, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Color = C.SOFT, Size = UDim2.fromOffset(DW - 320, 20), Position = UDim2.fromOffset(310, 42),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, ZIndex = 24 })
	local chips = label({ Name = "Chips", Parent = detail, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Size = UDim2.fromOffset(DW - 272, 22), Position = UDim2.fromOffset(262, 68),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, Rich = true, ZIndex = 24 })
	-- médailles
	local medalRow = box({ Name = "Medals", Parent = detail, Transparency = 1, Size = UDim2.fromOffset(DW - 272, 46), Position = UDim2.fromOffset(262, 96), ZIndex = 24 })
	local medalPills = {}
	for k, spec in ipairs({ { "🥇", C.GOLD }, { "🥈", C.SILVER }, { "🥉", C.BRONZE } }) do
		local pill = box({ Name = "M" .. k, Parent = medalRow, Color = C.PANEL2, Size = UDim2.new(1 / 3, -6, 1, 0), Position = UDim2.new((k - 1) / 3, 0, 0, 0), Radius = UDim.new(0, 12),
			Stroke = spec[2], ZIndex = 25 })
		label({ Name = "I", Parent = pill, Text = spec[1], TextSize = 24, Size = UDim2.fromOffset(36, 46), Position = UDim2.fromOffset(2, 0), ZIndex = 26 })
		local t = label({ Name = "T", Parent = pill, Text = "", Font = Theme.Fonts.Number, TextSize = 18, Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(36, 0), ZIndex = 26 })
		medalPills[k] = { Pill = pill, Text = t }
	end
	local mine = label({ Name = "Mine", Parent = detail, Text = "", TextSize = 17, Color = C.MINT, Size = UDim2.fromOffset(DW - 272, 24), Position = UDim2.fromOffset(262, 150),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, Rich = true, ZIndex = 24 })
	-- record du serveur
	local rec = box({ Name = "Record", Parent = detail, Color = C.PANEL2, Size = UDim2.fromOffset(DW - 272, 62), Position = UDim2.fromOffset(262, 182), Radius = UDim.new(0, 14),
		Stroke = C.GOLD, ZIndex = 24 })
	local _, recImg, recEmoji = avatar(rec, 48, UDim2.fromOffset(8, 7), 25)
	local recTitle = label({ Name = "Title", Parent = rec, Text = T("🏆 Server record"), Font = Theme.Fonts.Body, TextSize = 13, Color = C.GOLD, Size = UDim2.new(1, -70, 0, 18),
		Position = UDim2.fromOffset(64, 6), XAlign = Enum.TextXAlignment.Left, ZIndex = 25 })
	local recText = label({ Name = "Text", Parent = rec, Text = "", TextSize = 18, Size = UDim2.new(1, -70, 0, 26), Position = UDim2.fromOffset(64, 26), XAlign = Enum.TextXAlignment.Left,
		Scaled = true, ZIndex = 25 })
	-- top 5
	local top = box({ Name = "Top", Parent = detail, Transparency = 1, Size = UDim2.fromOffset(300, 140), Position = UDim2.fromOffset(12, 256), ZIndex = 24 })
	label({ Name = "H", Parent = top, Text = T("Best laps on this server"), Font = Theme.Fonts.Body, TextSize = 13, Color = C.SOFT, Size = UDim2.new(1, 0, 0, 16), XAlign = Enum.TextXAlignment.Left, ZIndex = 25 })
	local topRows = {}
	for k = 1, 5 do
		local row = box({ Name = "R" .. k, Parent = top, Color = C.WHITE, Transparency = 0.94, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 18 + (k - 1) * 24), Radius = UDim.new(0, 7), ZIndex = 25 })
		local pos = label({ Name = "Pos", Parent = row, Text = tostring(k), Font = Theme.Fonts.Number, TextSize = 14, Color = RaceHud.PlaceColor(k), Size = UDim2.fromOffset(20, 22), ZIndex = 26 })
		local _, img, emoji = avatar(row, 18, UDim2.fromOffset(22, 2), 26)
		local nm = label({ Name = "Name", Parent = row, Text = "", Font = Theme.Fonts.Body, TextSize = 14, Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(46, 0),
			XAlign = Enum.TextXAlignment.Left, Truncate = true, ZIndex = 26 })
		local tm = label({ Name = "Time", Parent = row, Text = "", Font = Theme.Fonts.Number, TextSize = 14, Color = C.MINT, Size = UDim2.fromOffset(70, 22), AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 26 })
		local _ = pos
		topRows[k] = { Row = row, Img = img, Emoji = emoji, Name = nm, Time = tm }
	end
	-- état + boutons
	local status = label({ Name = "Status", Parent = detail, Text = "", TextSize = 18, Size = UDim2.fromOffset(DW - 336, 26), Position = UDim2.fromOffset(324, 262),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, Wrap = true, ZIndex = 24 })
	local join = button({ Name = "Join", Parent = detail, Text = T("Join"), TextSize = 22, Size = UDim2.fromOffset(DW - 336, 52), Position = UDim2.fromOffset(324, 296), ZIndex = 25 })
	local watch = button({ Name = "Watch", Parent = detail, Text = T("👁️ Watch"), TextSize = 18, Color = rgb(70, 150, 220), Size = UDim2.fromOffset(DW - 336, 40), Position = UDim2.fromOffset(324, 352),
		ZIndex = 25, Visible = false })
	join.Activated:Connect(function()
		local d = parts.Current
		if d and callbacks.Join then
			callbacks.Join(d.Id, d.Joined)
		end
	end)
	watch.Activated:Connect(function()
		local d = parts.Current
		if d and callbacks.Watch then
			callbacks.Watch(d.Id)
		end
	end)
	parts.List = list
	parts.ListRows = {}
	parts.D = {
		Map = map, Line = mapLine, Shadow = mapShadow, Icon = icon, Name = name, Desc = desc, Chips = chips, Medals = medalPills, Mine = mine,
		RecImg = recImg, RecEmoji = recEmoji, RecText = recText, RecTitle = recTitle, Top = topRows, Status = status, Join = join, Watch = watch,
	}
end

local function listRow(order: number): { [string]: any }
	local row = Instance.new("TextButton")
	row.Name = "Route" .. order
	row.AutoButtonColor = true
	row.Text = ""
	row.BorderSizePixel = 0
	row.BackgroundColor3 = C.PANEL2
	row.Size = UDim2.new(1, 0, 0, 54)
	row.LayoutOrder = order
	row.ZIndex = 24
	row.Parent = parts.List
	UIUtil.Corner(row, 12)
	local stroke = UIUtil.Stroke(row, rgb(120, 90, 160), 2)
	local stripe = box({ Name = "Stripe", Parent = row, Color = C.GOLD, Size = UDim2.fromOffset(6, 38), Position = UDim2.fromOffset(6, 8), Radius = UDim.new(1, 0), ZIndex = 25 })
	local icon = label({ Name = "Icon", Parent = row, Text = "", TextSize = 24, Size = UDim2.fromOffset(34, 54), Position = UDim2.fromOffset(14, 0), ZIndex = 25 })
	local name = label({ Name = "Name", Parent = row, Text = "", TextSize = 16, Size = UDim2.new(1, -94, 0, 24), Position = UDim2.fromOffset(50, 5), XAlign = Enum.TextXAlignment.Left,
		Scaled = true, ZIndex = 25 })
	local info = label({ Name = "Info", Parent = row, Text = "", Font = Theme.Fonts.Body, TextSize = 13, Color = C.SOFT, Size = UDim2.new(1, -94, 0, 18), Position = UDim2.fromOffset(50, 29),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, ZIndex = 25 })
	local medal = label({ Name = "Medal", Parent = row, Text = "", TextSize = 22, Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 2), ZIndex = 25 })
	local dot = box({ Name = "Dot", Parent = row, Color = C.MINT, Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -8), Radius = UDim.new(1, 0), ZIndex = 25 })
	local r = { Button = row, Stroke = stroke, Stripe = stripe, Icon = icon, Name = name, Info = info, Medal = medal, Dot = dot, Id = "" }
	row.Activated:Connect(function()
		if r.Id ~= "" then
			selected = r.Id
			if lastData then
				RaceMenu.Update(lastData)
			end
		end
	end)
	return r
end

-- Onglet STATS
local function buildStats()
	local page = parts.Pages.Stats
	local card = box({ Name = "RankCard", Parent = page, Color = C.INK, Transparency = 0.3, Size = UDim2.fromOffset(300, 170), Radius = UDim.new(0, 16), Stroke = C.GOLD, StrokeThickness = 3, ZIndex = 23 })
	local icon = label({ Name = "Icon", Parent = card, Text = "", TextSize = 60, Size = UDim2.fromOffset(90, 90), Position = UDim2.fromOffset(8, 10), ZIndex = 24 })
	local name = label({ Name = "Name", Parent = card, Text = "", TextSize = 28, Size = UDim2.fromOffset(190, 36), Position = UDim2.fromOffset(100, 22), XAlign = Enum.TextXAlignment.Left,
		Scaled = true, ZIndex = 24 })
	local xp = label({ Name = "Xp", Parent = card, Text = "", Font = Theme.Fonts.Body, TextSize = 15, Color = C.SOFT, Size = UDim2.fromOffset(190, 20), Position = UDim2.fromOffset(100, 60),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 24 })
	local bar = box({ Name = "Bar", Parent = card, Color = rgb(30, 26, 44), Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 110), Radius = UDim.new(1, 0), ZIndex = 24, Clip = true })
	local fill = box({ Name = "Fill", Parent = bar, Color = C.GOLD, Size = UDim2.fromScale(0, 1), Radius = UDim.new(1, 0), ZIndex = 25 })
	UIUtil.Gradient(fill, ColorSequence.new(C.PINK, C.GOLD), 0)
	local nextText = label({ Name = "Next", Parent = card, Text = "", Font = Theme.Fonts.Body, TextSize = 14, Color = C.SOFT, Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 132),
		XAlign = Enum.TextXAlignment.Left, Scaled = true, ZIndex = 24 })
	-- tuiles
	local tilesHolder = box({ Name = "Tiles", Parent = page, Transparency = 1, Size = UDim2.fromOffset(W - 32 - 312, 170), Position = UDim2.fromOffset(312, 0), ZIndex = 23 })
	UIUtil.Create("UIGridLayout", { CellSize = UDim2.fromOffset(141, 81), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tilesHolder })
	local tiles = {}
	for k = 1, 8 do
		local tile = box({ Name = "Tile" .. k, Parent = tilesHolder, Color = C.INK, Transparency = 0.3, Radius = UDim.new(0, 12), ZIndex = 24 })
		tile.LayoutOrder = k
		local v = label({ Name = "V", Parent = tile, Text = "", Font = Theme.Fonts.Number, TextSize = 26, Color = C.WHITE, Size = UDim2.new(1, -10, 0, 40), Position = UDim2.fromOffset(5, 8),
			Scaled = true, ZIndex = 25 })
		local l = label({ Name = "L", Parent = tile, Text = "", Font = Theme.Fonts.Body, TextSize = 13, Color = C.SOFT, Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 50),
			Scaled = true, ZIndex = 25 })
		tiles[k] = { V = v, L = l }
	end
	-- graphe des places
	local graph = box({ Name = "Graph", Parent = page, Color = C.INK, Transparency = 0.3, Size = UDim2.fromOffset(440, H - 164 - 182), Position = UDim2.fromOffset(0, 182),
		Radius = UDim.new(0, 16), ZIndex = 23 })
	label({ Name = "H", Parent = graph, Text = T("📈 Your last races (place)"), Font = Theme.Fonts.Body, TextSize = 14, Color = C.SOFT, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(12, 6),
		XAlign = Enum.TextXAlignment.Left, ZIndex = 24 })
	local plot = box({ Name = "Plot", Parent = graph, Transparency = 1, Size = UDim2.fromOffset(380, H - 164 - 182 - 50), Position = UDim2.fromOffset(44, 32), ZIndex = 24 })
	for k, place in ipairs({ 1, 4, 8 }) do
		local y = (place - 1) / 7
		box({ Name = "Grid", Parent = plot, Color = C.WHITE, Transparency = 0.88, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, y, 0), ZIndex = 24 })
		label({ Name = "Y", Parent = graph, Text = "P" .. place, Font = Theme.Fonts.Number, TextSize = 12, Color = C.SOFT, Size = UDim2.fromOffset(30, 14), AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(8, 32 + y * plot.Size.Y.Offset), ZIndex = 24 })
		local _ = k
	end
	local lineHolder = box({ Name = "Line", Parent = plot, Transparency = 1, Size = plot.Size, ZIndex = 25 })
	local empty = label({ Name = "Empty", Parent = graph, Text = T("No race yet: your curve starts with the first one!"), Font = Theme.Fonts.Body, TextSize = 15, Color = C.SOFT,
		Size = UDim2.new(1, -40, 0, 60), Position = UDim2.fromOffset(20, 70), Wrap = true, ZIndex = 26 })
	-- tableau par parcours
	local tbl = UIUtil.Create("ScrollingFrame", {
		Name = "Table", BackgroundColor3 = C.INK, BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.fromOffset(W - 32 - 452, H - 164 - 182),
		Position = UDim2.fromOffset(452, 182), CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, ZIndex = 23, Parent = page,
	})
	UIUtil.Corner(tbl, 16)
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tbl })
	UIUtil.Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10), Parent = tbl })
	parts.S = { Icon = icon, Name = name, Xp = xp, Fill = fill, Next = nextText, Card = card, Tiles = tiles, Plot = plot, Line = lineHolder, Empty = empty, Table = tbl }
end

-- Onglet CLASSEMENT
local function buildBoard()
	local page = parts.Pages.Board
	local pilots = UIUtil.Create("ScrollingFrame", {
		Name = "Pilots", BackgroundColor3 = C.INK, BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.fromOffset(440, H - 164),
		CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, ZIndex = 23, Parent = page,
	})
	UIUtil.Corner(pilots, 16)
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pilots })
	UIUtil.Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10), Parent = pilots })
	local records = UIUtil.Create("ScrollingFrame", {
		Name = "Records", BackgroundColor3 = C.INK, BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.fromOffset(W - 32 - 452, H - 164),
		Position = UDim2.fromOffset(452, 0), CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, ZIndex = 23, Parent = page,
	})
	UIUtil.Corner(records, 16)
	UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = records })
	UIUtil.Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10), Parent = records })
	parts.B = { Pilots = pilots, Records = records }
end

function RaceMenu.Build(root: Frame, cb: { [string]: any })
	RaceMenu.Destroy()
	callbacks = cb or {}
	buildFrame(root)
	buildRaces()
	buildStats()
	buildBoard()
	RaceHud.OnLayout(function()
		RaceMenu.Layout()
	end)
	RaceMenu.Layout()
	RaceMenu.SetTab(tab)
end

function RaceMenu.Layout()
	if not parts.Holder then
		return
	end
	local root = RaceHud.Root()
	if not root then
		return
	end
	local rw, rh = root.Size.X.Offset, root.Size.Y.Offset
	local s = math.min(1, (rw - 16) / W, (rh - 70) / H)
	parts.Scale.Scale = math.max(0.5, s)
end

function RaceMenu.Destroy()
	if parts.Dim then
		parts.Dim:Destroy()
	end
	table.clear(parts)
	open = false
end

function RaceMenu.IsOpen(): boolean
	return open
end

function RaceMenu.SetOpen(isOpen: boolean)
	if not parts.Dim then
		return
	end
	local was = open
	open = isOpen
	parts.Dim.Visible = isOpen
	if isOpen and not was then
		UIUtil.Pop(parts.Panel, 0.92, 0.18)
	end
end

function RaceMenu.SetTab(id: string)
	if not parts.Pages or not parts.Pages[id] then
		return
	end
	tab = id
	for key, page in pairs(parts.Pages) do
		page.Visible = key == id
		local b = parts.Tabs[key]
		if b then
			b.BackgroundColor3 = if key == id then C.PINK_DEEP else rgb(70, 56, 100)
		end
	end
end

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

local function updateRaces(data: any)
	local routes = data.Routes or {}
	if selected == nil or not (function()
		for _, r in ipairs(routes) do
			if r.Id == selected then
				return true
			end
		end
		return false
	end)() then
		selected = nil
		for _, r in ipairs(routes) do
			if r.Joined then
				selected = r.Id
			end
		end
		selected = selected or (routes[1] and routes[1].Id)
	end
	for k, r in ipairs(routes) do
		local row = parts.ListRows[k]
		if not row then
			row = listRow(k)
			parts.ListRows[k] = row
		end
		row.Id = r.Id
		local col = color3(r.Color, C.GOLD)
		row.Stripe.BackgroundColor3 = col
		row.Icon.Text = r.Icon or "🏁"
		row.Name.Text = r.Name or ""
		row.Info.Text = r.Short or ""
		row.Medal.Text = r.MyMedalIcon or ""
		row.Dot.BackgroundColor3 = r.StatusColor or C.MINT
		local isSel = r.Id == selected
		row.Button.BackgroundColor3 = if isSel then rgb(84, 64, 120) else C.PANEL2
		row.Stroke.Color = if r.Joined then C.GOLD elseif isSel then col else rgb(120, 90, 160)
		row.Stroke.Thickness = if isSel or r.Joined then 3 else 2
	end
	for k = #routes + 1, #parts.ListRows do
		parts.ListRows[k].Button:Destroy()
		parts.ListRows[k] = nil
	end
	local cur = nil
	for _, r in ipairs(routes) do
		if r.Id == selected then
			cur = r
		end
	end
	parts.Current = cur
	local D = parts.D
	if not cur then
		return
	end
	local col = color3(cur.Color, C.GOLD)
	D.Icon.Text = cur.Icon or "🏁"
	D.Name.Text = cur.Name or ""
	D.Desc.Text = cur.Desc or ""
	D.Chips.Text = cur.Chips or ""
	if cur.Preview and parts.PreviewKey ~= cur.PreviewKey then
		parts.PreviewKey = cur.PreviewKey
		RaceHud.DrawLine(D.Shadow, cur.Preview, rgb(20, 24, 22), 7, 24, cur.Closed, true)
		RaceHud.DrawLine(D.Line, cur.Preview, col, 5, 26, cur.Closed)
	end
	for k, key in ipairs({ "Gold", "Silver", "Bronze" }) do
		local m = cur.Medals and cur.Medals[key]
		D.Medals[k].Text.Text = if m then cur.FormatTime(m) else "-"
		D.Medals[k].Pill.BackgroundColor3 = if (cur.MyMedal or 0) > 0 and (cur.MyMedal :: number) <= k then rgb(80, 64, 110) else C.PANEL2
	end
	D.Mine.Text = cur.Mine or ""
	if cur.Record then
		D.RecText.Text = string.format("%s · %s", tostring(cur.Record.Name), cur.FormatTime(cur.Record.Time))
		setAvatar(D.RecImg, D.RecEmoji, cur.Record.UserId)
	else
		D.RecText.Text = T("No record yet: be the first!")
		D.RecImg.Image = ""
		D.RecEmoji.Text = "🏁"
	end
	for k, row in ipairs(D.Top) do
		local t = cur.Top and cur.Top[k]
		row.Row.Visible = t ~= nil
		if t then
			row.Name.Text = tostring(t.Name)
			row.Time.Text = cur.FormatTime(t.Time)
			setAvatar(row.Img, row.Emoji, t.UserId)
		end
	end
	D.Status.Text = cur.Status or ""
	D.Status.TextColor3 = cur.StatusColor or C.WHITE
	D.Join.Text = if cur.Joined then T("Leave") else T("Join")
	D.Join.BackgroundColor3 = if cur.Joined then rgb(120, 100, 140) elseif cur.CanJoin then C.PINK_DEEP else rgb(90, 84, 100)
	D.Watch.Visible = cur.CanWatch == true
end

local function updateStats(data: any)
	local S = parts.S
	local rank = data.Rank
	if rank then
		S.Icon.Text = rank.Icon or "🥉"
		S.Name.Text = rank.LabelText or ""
		S.Name.TextColor3 = rank.Color or C.WHITE
		S.Xp.Text = rank.XpText or ""
		S.Fill.Size = UDim2.fromScale(math.clamp(rank.Progress or 0, 0, 1), 1)
		S.Next.Text = rank.NextText or ""
		local stroke = S.Card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = rank.Color or C.GOLD
		end
		parts.BadgeIcon.Text = rank.Icon or "🥉"
		parts.BadgeText.Text = rank.LabelText or ""
		parts.BadgeText.TextColor3 = rank.Color or C.WHITE
		parts.BadgeFill.Size = UDim2.fromScale(math.clamp(rank.Progress or 0, 0, 1), 1)
	end
	for k, tile in ipairs(S.Tiles) do
		local t = data.Tiles and data.Tiles[k]
		tile.V.Text = if t then t[1] else ""
		tile.L.Text = if t then t[2] else ""
	end
	-- graphe : places des dernières courses (la plus ancienne à gauche)
	local hist = data.History or {}
	clear(S.Line)
	S.Empty.Visible = #hist == 0
	local n = #hist
	if n > 0 then
		local w, h = S.Plot.Size.X.Offset, S.Plot.Size.Y.Offset
		local pts = {}
		for i = n, 1, -1 do
			local e = hist[i]
			local u = if n == 1 then 0.5 else (n - i) / (n - 1)
			local place = if (e.P or 0) > 0 then e.P else 8
			local v = (math.clamp(place, 1, 8) - 1) / 7
			table.insert(pts, { u, v, e })
		end
		if n >= 2 then
			RaceHud.DrawLine(S.Line, pts, C.PINK, 3, 25, false, true)
		end
		for _, p in ipairs(pts) do
			local e = p[3]
			local place = e.P or 0
			local dotColor = if place == 0 then rgb(120, 110, 130) else RaceHud.PlaceColor(place)
			local dot = box({ Name = "Pt", Parent = S.Line, Color = dotColor, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12),
				Position = UDim2.fromOffset(p[1] * w, p[2] * h), Radius = UDim.new(1, 0), ZIndex = 27 })
			UIUtil.Stroke(dot, C.INK, 1.5)
			if e.Icon then
				label({ Name = "PtIcon", Parent = S.Line, Text = e.Icon, TextSize = 12, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(16, 14),
					Position = UDim2.fromOffset(p[1] * w, p[2] * h - 6), ZIndex = 28 })
			end
		end
	end
	-- tableau par parcours
	clear(S.Table)
	local header = box({ Name = "Hdr", Parent = S.Table, Transparency = 1, Size = UDim2.new(1, 0, 0, 18), ZIndex = 24 })
	header.LayoutOrder = 0
	for _, h in ipairs({ { T("Route"), 0, 150, Enum.TextXAlignment.Left }, { T("Races"), 152, 50, Enum.TextXAlignment.Center }, { T("Wins"), 204, 50, Enum.TextXAlignment.Center },
		{ T("Best"), 256, 80, Enum.TextXAlignment.Right }, { "", 340, 70, Enum.TextXAlignment.Center } }) do
		label({ Name = "H", Parent = header, Text = h[1], Font = Theme.Fonts.Body, TextSize = 12, Color = C.SOFT, Size = UDim2.fromOffset(h[3], 18), Position = UDim2.fromOffset(h[2], 0),
			XAlign = h[4], ZIndex = 25 })
	end
	for k, r in ipairs(data.RouteStats or {}) do
		local row = box({ Name = "Row" .. k, Parent = S.Table, Color = C.WHITE, Transparency = 0.93, Size = UDim2.new(1, 0, 0, 30), Radius = UDim.new(0, 8), ZIndex = 24 })
		row.LayoutOrder = k
		label({ Name = "N", Parent = row, Text = (r.Icon or "") .. " " .. (r.Name or ""), Font = Theme.Fonts.Body, TextSize = 14, Size = UDim2.fromOffset(150, 30), Position = UDim2.fromOffset(4, 0),
			XAlign = Enum.TextXAlignment.Left, Truncate = true, ZIndex = 25 })
		label({ Name = "R", Parent = row, Text = tostring(r.Races or 0), Font = Theme.Fonts.Number, TextSize = 15, Size = UDim2.fromOffset(50, 30), Position = UDim2.fromOffset(152, 0), ZIndex = 25 })
		label({ Name = "W", Parent = row, Text = tostring(r.Wins or 0), Font = Theme.Fonts.Number, TextSize = 15, Color = C.GOLD, Size = UDim2.fromOffset(50, 30), Position = UDim2.fromOffset(204, 0), ZIndex = 25 })
		label({ Name = "T", Parent = row, Text = r.Best or "-", Font = Theme.Fonts.Number, TextSize = 15, Color = C.MINT, Size = UDim2.fromOffset(80, 30), Position = UDim2.fromOffset(256, 0),
			XAlign = Enum.TextXAlignment.Right, ZIndex = 25 })
		label({ Name = "M", Parent = row, Text = r.Extra or "", TextSize = 15, Size = UDim2.fromOffset(80, 30), Position = UDim2.fromOffset(340, 0), Scaled = true, ZIndex = 25 })
	end
end

local function updateBoard(data: any)
	local B = parts.B
	clear(B.Pilots)
	local title = label({ Name = "Title", Parent = B.Pilots, Text = T("🏎️ Drivers on this server"), TextSize = 17, Size = UDim2.new(1, 0, 0, 24), XAlign = Enum.TextXAlignment.Left, ZIndex = 24 })
	title.LayoutOrder = 0
	local pilots = data.Pilots or {}
	if #pilots == 0 then
		local e = label({ Name = "Empty", Parent = B.Pilots, Text = T("No driver yet: race to appear here!"), Font = Theme.Fonts.Body, TextSize = 15, Color = C.SOFT,
			Size = UDim2.new(1, 0, 0, 40), Wrap = true, ZIndex = 24 })
		e.LayoutOrder = 1
	end
	for k, p in ipairs(pilots) do
		local row = box({ Name = "P" .. k, Parent = B.Pilots, Color = if p.Me then rgb(90, 70, 130) else C.PANEL2, Size = UDim2.new(1, 0, 0, 44), Radius = UDim.new(0, 12), ZIndex = 24 })
		row.LayoutOrder = k
		label({ Name = "Pos", Parent = row, Text = tostring(k), Font = Theme.Fonts.Number, TextSize = 18, Color = RaceHud.PlaceColor(k), Size = UDim2.fromOffset(28, 44), ZIndex = 25 })
		local _, img, emoji = avatar(row, 34, UDim2.fromOffset(30, 5), 25)
		setAvatar(img, emoji, p.UserId)
		label({ Name = "N", Parent = row, Text = tostring(p.Name), TextSize = 16, Size = UDim2.new(1, -230, 0, 22), Position = UDim2.fromOffset(72, 3), XAlign = Enum.TextXAlignment.Left,
			Truncate = true, Color = if p.Me then C.GOLD else C.WHITE, ZIndex = 25 })
		label({ Name = "Rk", Parent = row, Text = p.RankText or "", Font = Theme.Fonts.Body, TextSize = 13, Color = p.RankColor or C.SOFT, Size = UDim2.new(1, -230, 0, 18),
			Position = UDim2.fromOffset(72, 23), XAlign = Enum.TextXAlignment.Left, ZIndex = 25 })
		label({ Name = "X", Parent = row, Text = p.Right or "", Font = Theme.Fonts.Number, TextSize = 14, Color = C.MINT, Size = UDim2.fromOffset(150, 44), AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0), XAlign = Enum.TextXAlignment.Right, Rich = true, ZIndex = 25 })
	end
	clear(B.Records)
	for k, rec in ipairs(data.Records or {}) do
		local card = box({ Name = "Rec" .. k, Parent = B.Records, Color = C.PANEL2, Size = UDim2.new(1, 0, 0, 92), Radius = UDim.new(0, 12), ZIndex = 24 })
		card.LayoutOrder = k
		box({ Name = "Stripe", Parent = card, Color = color3(rec.Color, C.GOLD), Size = UDim2.fromOffset(6, 76), Position = UDim2.fromOffset(6, 8), Radius = UDim.new(1, 0), ZIndex = 25 })
		label({ Name = "N", Parent = card, Text = (rec.Icon or "") .. " " .. (rec.Name or ""), TextSize = 15, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(18, 3),
			XAlign = Enum.TextXAlignment.Left, ZIndex = 25 })
		for i = 1, 3 do
			local t = rec.Top and rec.Top[i]
			local x = 18 + (i - 1) * 140
			if t then
				local _, img, emoji = avatar(card, 30, UDim2.fromOffset(x, 30), 25)
				setAvatar(img, emoji, t.UserId)
				label({ Name = "TN", Parent = card, Text = ({ "🥇", "🥈", "🥉" })[i] .. " " .. tostring(t.Name), Font = Theme.Fonts.Body, TextSize = 13, Size = UDim2.fromOffset(100, 18),
					Position = UDim2.fromOffset(x + 34, 30), XAlign = Enum.TextXAlignment.Left, Truncate = true, ZIndex = 25 })
				label({ Name = "TT", Parent = card, Text = t.Text or "", Font = Theme.Fonts.Number, TextSize = 14, Color = C.MINT, Size = UDim2.fromOffset(100, 18),
					Position = UDim2.fromOffset(x + 34, 48), XAlign = Enum.TextXAlignment.Left, ZIndex = 25 })
			elseif i == 1 then
				label({ Name = "E", Parent = card, Text = T("No record yet: be the first!"), Font = Theme.Fonts.Body, TextSize = 14, Color = C.SOFT, Size = UDim2.new(1, -30, 0, 30),
					Position = UDim2.fromOffset(18, 36), XAlign = Enum.TextXAlignment.Left, ZIndex = 25 })
			end
		end
	end
end

function RaceMenu.Update(data: any)
	if not parts.Panel or type(data) ~= "table" then
		return
	end
	lastData = data
	parts.Sub.Text = data.Sub or ""
	parts.Foot.Text = data.Foot or ""
	pcall(updateRaces, data)
	-- (stats / classement : reconstruits seulement quand leurs données changent)
	if data.StatsKey == nil or data.StatsKey ~= parts.StatsKey then
		parts.StatsKey = data.StatsKey
		pcall(updateStats, data)
	end
	if data.BoardKey == nil or data.BoardKey ~= parts.BoardKey then
		parts.BoardKey = data.BoardKey
		pcall(updateBoard, data)
	end
end

function RaceMenu.Selected(): string?
	return selected
end

function RaceMenu.Select(id: string)
	selected = id
	if lastData then
		RaceMenu.Update(lastData)
	end
end

function RaceMenu.Debug(): any
	return { Parts = parts, Tab = function()
		return tab
	end }
end

local _ = TweenService
return RaceMenu
