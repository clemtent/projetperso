--[[
	BoardKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > BoardKit

	📺 Dopamine Town (v9.9, SHOPS99) : les ÉCRANS DE CLASSEMENT façon
	régie télé (« Meilleur joueur du serveur », top Dopamine, top
	Renaissances…), dessinés dans une SurfaceGui sur la face d'une pièce :
	  - bandeau animé : logo de la chaîne « DOPA TV », titre, portée
	    (🌍 Monde / 🏠 Ce serveur), pastille « ● EN DIRECT » qui pulse,
	    heure réelle, liseré dégradé qui défile, reflet lumineux qui
	    balaie l'écran ;
	  - le N°1 en VEDETTE : couronne 👑 qui flotte, grande photo (vraie
	    tête de l'avatar : Players:GetUserThumbnailAsync, en cache ; repli
	    immédiat rbxthumb://), anneau doré, ruban « ⭐ Meilleur joueur du
	    serveur », nom et GROS chiffre ; petit éclat quand le N°1 change ;
	  - les rangs suivants : pastille de rang (argent, bronze…), photo,
	    nom, barre de progression relative au N°1, gros chiffre à droite,
	    flèche ▲ / ▼ quand un joueur gagne ou perd une place ; les lignes
	    GLISSENT jusqu'à leur nouvelle place (transition douce), les
	    nouvelles arrivent en fondu ; ta ligne est surlignée ;
	  - pied : « Toi : 3e · … » + bandeau défilant d'astuces, barre de page.
	Rien ne se crée à chaque image : SetData réécrit des textes, Step ne
	fait que déplacer / teinter des cadres existants (≤ 30 fois / s, et
	seulement quand l'écran est proche : c'est l'appelant qui décide).

	API :
	  BoardKit.Build(screen: BasePart, opts) -> Board
	    opts : { Face = NormalId?, PPS = number, MaxDistance = number?,
	             Title = string, Theme = "Dopamine" | "Rebirths" | "Server"
	             | "Hall", Rows = number? (lignes sous la vedette, 7),
	             HeroCaption = string?, Ticker = { string }? }
	  BoardKit.SetData(board, { Rows = { Row }, Scope = string?, Footer =
	             string?, Title = string?, HeroCaption = string? })
	    Row = { UserId: number, Name: string, Value: number, ValueText:
	            string, Rank: number, Mine: boolean? }
	  BoardKit.SetProgress(board, 0..1)      barre de page
	  BoardKit.Step(board, now)               animations (horloge os.clock)
	  BoardKit.Destroy(board)
]]

local Players = game:GetService("Players")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local BoardKit = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local GOLD = rgb(255, 206, 84)
local SILVER = rgb(206, 214, 228)
local BRONZE = rgb(222, 150, 96)

local THEMES: { [string]: { any } } = {
	Dopamine = { rgb(236, 72, 140), rgb(120, 90, 200) },
	Rebirths = { rgb(60, 170, 230), rgb(120, 90, 200) },
	Server = { rgb(255, 140, 80), rgb(236, 72, 140) },
	Hall = { rgb(255, 176, 60), rgb(236, 72, 140) },
}

export type Row = { UserId: number, Name: string, Value: number, ValueText: string, Rank: number, Mine: boolean? }

type RowSlot = {
	Frame: Frame,
	Badge: Frame,
	Rank: TextLabel,
	Image: ImageLabel,
	Initial: TextLabel,
	Name: TextLabel,
	Value: TextLabel,
	Trend: TextLabel,
	Fill: Frame,
	Stroke: UIStroke,
	Key: string?,
	Cur: number,
	Target: number,
	Alpha: number,
	TrendUntil: number,
}

export type Board = {
	Gui: SurfaceGui,
	Root: Frame,
	Title: TextLabel,
	Scope: TextLabel,
	Live: Frame,
	Clock: TextLabel,
	Sweep: Frame,
	Line: UIGradient,
	Crown: TextLabel,
	Hero: Frame,
	HeroImage: ImageLabel,
	HeroInitial: TextLabel,
	HeroName: TextLabel,
	HeroValue: TextLabel,
	HeroCaption: TextLabel,
	HeroRing: UIStroke,
	RingPx: number,
	HeroKey: string?,
	HeroFlash: number,
	Podium: { any }, -- (compatibilité : Podium[1] = la vedette)
	Rows: { RowSlot },
	Footer: TextLabel,
	Ticker: TextLabel,
	Bar: Frame,
	Empty: TextLabel,
	RowH: number,
	Y0: number,
	Ranks: { [string]: number },
	LastStep: number,
	LastClock: string,
}

----------------------------------------------------------------------
-- Photos des joueurs (cache ; repli immédiat rbxthumb://)
----------------------------------------------------------------------

local thumbs: { [number]: string } = {}
local asking: { [number]: boolean } = {}

local function headshot(userId: number): string
	if userId <= 0 then
		return ""
	end
	local cached = thumbs[userId]
	if cached then
		return cached
	end
	if not asking[userId] then
		asking[userId] = true
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			end)
			if ok and type(url) == "string" and url ~= "" then
				thumbs[userId] = url
			end
		end)
	end
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", math.floor(userId))
end

----------------------------------------------------------------------
-- Petits constructeurs d'interface
----------------------------------------------------------------------

local function frame(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, value: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font?, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(x, y)
	l.Size = UDim2.fromScale(w, h)
	l.Font = font or Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = value
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

local function round(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = parent
end

local function gradient(parent: Instance, a: Color3, b: Color3, rotation: number): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation
	g.Parent = parent
	return g
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Photo ronde (image + initiale dessous)
local function avatar(parent: Instance, x: number, y: number, size: number, ring: Color3?, ringPx: number?): (Frame, ImageLabel, TextLabel, UIStroke?)
	local f = Instance.new("Frame")
	f.Name = "Avatar"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(size, size)
	f.BackgroundColor3 = rgb(70, 60, 120)
	f.BorderSizePixel = 0
	f.Parent = parent
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = f
	round(f, 1)
	gradient(f, rgb(110, 96, 170), rgb(56, 46, 100), 90)
	local initial = label(f, "Initial", "", 0.15, 0.15, 0.7, 0.7, WHITE, Enum.Font.FredokaOne)
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = ""
	image.Parent = f
	round(image, 1)
	local s = nil
	if ring then
		s = stroke(f, ring, ringPx or 2)
	end
	return f, image, initial, s
end

local function keyOf(r: Row): string
	if r.UserId ~= 0 then
		return "u" .. tostring(r.UserId)
	end
	return "n" .. r.Name
end

local function badgeColor(rank: number): Color3
	if rank == 1 then
		return GOLD
	elseif rank == 2 then
		return SILVER
	elseif rank == 3 then
		return BRONZE
	end
	return rgb(84, 70, 150)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function BoardKit.Build(screen: BasePart, opts: { [string]: any }): Board
	local theme = THEMES[opts.Theme or "Dopamine"] or THEMES.Dopamine
	local accentA, accentB = theme[1] :: Color3, theme[2] :: Color3
	local pps = opts.PPS or 40
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = opts.Face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.MaxDistance = opts.MaxDistance or 320
	gui.ClipsDescendants = true
	gui.Parent = screen
	local px = (gui.Face == Enum.NormalId.Left or gui.Face == Enum.NormalId.Right) and screen.Size.Z * pps or screen.Size.X * pps
	local stroke1 = math.max(1, px / 300)
	local root = frame(gui, "Root", 0, 0, 1, 1, WHITE)
	gradient(root, rgb(16, 14, 40), rgb(38, 18, 66), 90)
	-- reflet qui balaie l'écran (dégradé de transparence)
	local sweep = frame(root, "Sweep", -0.4, 0, 0.3, 1, WHITE, 0)
	local sg = Instance.new("UIGradient")
	sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.9), NumberSequenceKeypoint.new(1, 1) })
	sg.Rotation = 20
	sg.Parent = sweep
	sweep.ZIndex = 8
	-- lignes discrètes du décor (plateau télé)
	for i = 1, 3 do
		local deco = frame(root, "Deco", 0, 0.2 + i * 0.2, 1, 0.002, WHITE, 0.94)
		deco.ZIndex = 1
	end
	-- bandeau du haut
	local head = frame(root, "Head", 0, 0, 1, 0.155, WHITE)
	head.ZIndex = 2
	gradient(head, accentA, accentB, 0)
	local channel = frame(head, "Channel", 0, 0, 0.15, 1, rgb(20, 16, 40))
	channel.ZIndex = 3
	label(channel, "Logo", "📺", 0.04, 0.12, 0.3, 0.76, WHITE, Enum.Font.GothamBlack).ZIndex = 4
	local tv = label(channel, "Name", "DOPA TV", 0.34, 0.2, 0.62, 0.6, WHITE, Enum.Font.GothamBlack, Enum.TextXAlignment.Left)
	tv.ZIndex = 4
	local title = label(head, "Title", Locale.T(opts.Title or "🏆 Leaderboard"), 0.17, 0.1, 0.44, 0.8, WHITE, Enum.Font.FredokaOne, Enum.TextXAlignment.Left)
	title.ZIndex = 3
	local chip = frame(head, "ScopeChip", 0.62, 0.2, 0.16, 0.6, WHITE, 0.78)
	chip.ZIndex = 3
	round(chip, 0.5)
	local scope = label(chip, "Scope", "", 0.06, 0.1, 0.88, 0.8, WHITE, Enum.Font.GothamBold)
	scope.ZIndex = 4
	local live = frame(head, "LiveChip", 0.79, 0.2, 0.11, 0.6, rgb(226, 40, 64))
	live.ZIndex = 3
	round(live, 0.5)
	local dot = frame(live, "Dot", 0.1, 0.3, 0.1, 0.4, WHITE)
	dot.ZIndex = 4
	local da = Instance.new("UIAspectRatioConstraint")
	da.AspectRatio = 1
	da.Parent = dot
	round(dot, 1)
	label(live, "Live", Locale.T("LIVE"), 0.26, 0.14, 0.68, 0.72, WHITE, Enum.Font.GothamBlack).ZIndex = 4
	local clock = label(head, "Clock", "--:--", 0.905, 0.2, 0.085, 0.6, WHITE, Enum.Font.GothamBlack)
	clock.ZIndex = 3
	-- liseré dégradé animé sous le bandeau
	local line = frame(root, "HeadLine", 0, 0.155, 1, 0.012, WHITE)
	line.ZIndex = 3
	local lg = Instance.new("UIGradient")
	lg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, accentA),
		ColorSequenceKeypoint.new(0.33, GOLD),
		ColorSequenceKeypoint.new(0.66, accentB),
		ColorSequenceKeypoint.new(1, accentA),
	})
	lg.Parent = line
	-- la VEDETTE (N°1)
	local hero = frame(root, "Hero", 0.02, 0.2, 0.33, 0.655, WHITE)
	hero.ZIndex = 2
	gradient(hero, rgb(92, 64, 40), rgb(40, 24, 60), 90)
	round(hero, 0.06)
	local heroStroke = stroke(hero, GOLD, stroke1 * 2)
	local crown = label(hero, "Crown", "👑", 0.35, 0.0, 0.3, 0.15, GOLD, Enum.Font.GothamBlack)
	crown.ZIndex = 4
	local heroAvatar, heroImage, heroInitial, heroRing = avatar(hero, 0.5, 0.37, 0.42, GOLD, stroke1 * 3)
	heroAvatar.ZIndex = 3
	heroImage.ZIndex = 5
	heroInitial.ZIndex = 4
	local badge = frame(hero, "Badge", 0.64, 0.46, 0.13, 0.13, GOLD)
	badge.ZIndex = 6
	local ba = Instance.new("UIAspectRatioConstraint")
	ba.AspectRatio = 1
	ba.Parent = badge
	round(badge, 1)
	label(badge, "Rank", "1", 0.15, 0.1, 0.7, 0.8, rgb(70, 44, 10), Enum.Font.FredokaOne).ZIndex = 7
	local ribbon = frame(hero, "Ribbon", 0.06, 0.615, 0.88, 0.085, GOLD)
	ribbon.ZIndex = 4
	round(ribbon, 0.4)
	gradient(ribbon, rgb(255, 226, 130), rgb(236, 170, 50), 90)
	local caption = label(ribbon, "Caption", Locale.T(opts.HeroCaption or "⭐ Best player on the server"), 0.04, 0.1, 0.92, 0.8, rgb(70, 40, 10), Enum.Font.GothamBlack)
	caption.ZIndex = 5
	local heroName = label(hero, "Name", "", 0.05, 0.71, 0.9, 0.11, WHITE, Enum.Font.GothamBlack)
	heroName.ZIndex = 4
	local heroValue = label(hero, "Value", "", 0.05, 0.82, 0.9, 0.14, GOLD, Enum.Font.FredokaOne)
	heroValue.ZIndex = 4
	-- les rangs suivants
	local count = opts.Rows or 7
	local y0, y1 = 0.2, 0.855
	local rowH = (y1 - y0) / count
	local rows: { RowSlot } = {}
	for i = 1, count do
		local f = frame(root, "Row" .. i, 0.37, y0 + (i - 1) * rowH, 0.61, rowH * 0.86, WHITE, 0.9)
		f.ZIndex = 2
		f.Visible = false
		round(f, 0.25)
		local s = stroke(f, WHITE, stroke1)
		s.Transparency = 1
		local b = frame(f, "Badge", 0.012, 0.12, 0.07, 0.76, rgb(84, 70, 150))
		b.ZIndex = 3
		local bar = Instance.new("UIAspectRatioConstraint")
		bar.AspectRatio = 1
		bar.Parent = b
		round(b, 1)
		local rank = label(b, "Rank", "", 0.1, 0.12, 0.8, 0.76, rgb(40, 30, 60), Enum.Font.FredokaOne)
		rank.ZIndex = 4
		local av, image, initial = avatar(f, 0.135, 0.5, 0.8)
		av.ZIndex = 3
		initial.ZIndex = 4
		image.ZIndex = 5
		local name = label(f, "Name", "", 0.19, 0.14, 0.36, 0.62, WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
		name.ZIndex = 3
		local trend = label(f, "Trend", "", 0.55, 0.2, 0.05, 0.56, rgb(120, 230, 150), Enum.Font.GothamBlack)
		trend.ZIndex = 3
		local value = label(f, "Value", "", 0.6, 0.1, 0.38, 0.7, rgb(255, 220, 130), Enum.Font.FredokaOne, Enum.TextXAlignment.Right)
		value.ZIndex = 3
		local track = frame(f, "Track", 0.19, 0.84, 0.79, 0.07, WHITE, 0.85)
		track.ZIndex = 3
		round(track, 1)
		local fill = frame(track, "Fill", 0, 0, 0.5, 1, WHITE)
		fill.ZIndex = 4
		round(fill, 1)
		gradient(fill, accentA, GOLD, 0)
		table.insert(rows, {
			Frame = f,
			Badge = b,
			Rank = rank,
			Image = image,
			Initial = initial,
			Name = name,
			Value = value,
			Trend = trend,
			Fill = fill,
			Stroke = s,
			Key = nil,
			Cur = i,
			Target = i,
			Alpha = 0,
			TrendUntil = 0,
		})
	end
	-- pied : ta place + bandeau défilant
	local you = frame(root, "You", 0.02, 0.875, 0.42, 0.085, WHITE, 0.86)
	you.ZIndex = 2
	round(you, 0.5)
	local footer = label(you, "Footer", "", 0.04, 0.1, 0.92, 0.8, rgb(255, 236, 160), Enum.Font.GothamBold)
	footer.ZIndex = 3
	local clip = frame(root, "TickerClip", 0.46, 0.875, 0.52, 0.085, rgb(10, 8, 24), 0.4)
	clip.ClipsDescendants = true
	clip.ZIndex = 2
	round(clip, 0.5)
	local tips = opts.Ticker or {
		"💧 Click, buy and climb the board!",
		"♻️ Rebirth to multiply your Dopamine",
		"❤️ Like houses in town",
	}
	local parts = {}
	for _, t in ipairs(tips) do
		table.insert(parts, Locale.T(t))
	end
	local ticker = label(clip, "Ticker", table.concat(parts, "     •     "), 1, 0.12, 2.2, 0.76, WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	ticker.ZIndex = 3
	local pageBack = frame(root, "PageBar", 0, 0.978, 1, 0.022, rgb(50, 40, 90))
	pageBack.ZIndex = 2
	local bar = frame(pageBack, "Fill", 0, 0, 0, 1, accentA)
	bar.ZIndex = 3
	local empty = label(root, "Empty", Locale.T("Loading the leaderboard…"), 0.1, 0.42, 0.8, 0.12, WHITE, Enum.Font.GothamBold)
	empty.ZIndex = 9
	local board: Board = {
		Gui = gui,
		Root = root,
		Title = title,
		Scope = scope,
		Live = dot,
		Clock = clock,
		Sweep = sweep,
		Line = lg,
		Crown = crown,
		Hero = hero,
		HeroImage = heroImage,
		HeroInitial = heroInitial,
		HeroName = heroName,
		HeroValue = heroValue,
		HeroCaption = caption,
		HeroRing = heroRing :: UIStroke,
		RingPx = stroke1 * 3,
		HeroKey = nil,
		HeroFlash = -10,
		Podium = { { Card = hero, Image = heroImage, Initial = heroInitial, Name = heroName, Value = heroValue } },
		Rows = rows,
		Footer = footer,
		Ticker = ticker,
		Bar = bar,
		Empty = empty,
		RowH = rowH,
		Y0 = y0,
		Ranks = {},
		LastStep = -1,
		LastClock = "",
	}
	local _ = heroStroke
	return board
end

----------------------------------------------------------------------
-- Données
----------------------------------------------------------------------

function BoardKit.SetData(board: Board, data: { [string]: any })
	local now = os.clock()
	local rows: { Row } = data.Rows or {}
	if data.Title then
		board.Title.Text = data.Title
	end
	if data.Scope then
		board.Scope.Text = data.Scope
	end
	if data.Footer then
		board.Footer.Text = data.Footer
	end
	if data.HeroCaption then
		board.HeroCaption.Text = data.HeroCaption
	end
	board.Empty.Visible = #rows == 0
	-- vedette
	local top = rows[1]
	board.Hero.Visible = top ~= nil
	if top then
		local key = keyOf(top)
		if board.HeroKey ~= key then
			if board.HeroKey ~= nil then
				board.HeroFlash = now
			end
			board.HeroKey = key
		end
		local url = headshot(top.UserId)
		if board.HeroImage.Image ~= url then
			board.HeroImage.Image = url
		end
		board.HeroInitial.Text = string.upper(string.sub(top.Name, 1, 1))
		board.HeroName.Text = (top.Mine and "⭐ " or "") .. top.Name
		board.HeroValue.Text = top.ValueText
	end
	-- lignes : chaque joueur garde « sa » ligne, qui glisse vers sa place
	local topValue = top and math.max(top.Value, 1e-9) or 1
	local used: { [RowSlot]: boolean } = {}
	local byKey: { [string]: RowSlot } = {}
	for _, slot in ipairs(board.Rows) do
		if slot.Key then
			byKey[slot.Key] = slot
		end
	end
	local wanted: { { Row: Row, Index: number } } = {}
	for i = 2, math.min(#rows, #board.Rows + 1) do
		table.insert(wanted, { Row = rows[i], Index = i - 1 })
	end
	local pending = {}
	for _, w in ipairs(wanted) do
		local slot = byKey[keyOf(w.Row)]
		if slot and not used[slot] then
			used[slot] = true
			slot.Target = w.Index
			table.insert(pending, { slot, w.Row })
		else
			table.insert(pending, { false, w.Row, w.Index })
		end
	end
	for _, p in ipairs(pending) do
		if p[1] == false then
			for _, slot in ipairs(board.Rows) do
				if not used[slot] then
					used[slot] = true
					slot.Key = keyOf(p[2])
					slot.Target = p[3]
					-- (nouvelle ligne : arrive du bas en fondu)
					slot.Cur = p[3] + 0.6
					slot.Alpha = 0
					p[1] = slot
					break
				end
			end
		end
	end
	for _, p in ipairs(pending) do
		local slot = p[1]
		local r: Row = p[2]
		if slot then
			local key = keyOf(r)
			local previous = board.Ranks[key]
			if previous and previous ~= r.Rank then
				slot.Trend.Text = r.Rank < previous and "▲" or "▼"
				slot.Trend.TextColor3 = r.Rank < previous and rgb(120, 230, 150) or rgb(255, 110, 120)
				slot.TrendUntil = now + 6
			elseif now > slot.TrendUntil then
				slot.Trend.Text = ""
			end
			slot.Frame.Visible = true
			slot.Rank.Text = tostring(r.Rank)
			slot.Badge.BackgroundColor3 = badgeColor(r.Rank)
			slot.Rank.TextColor3 = r.Rank <= 3 and rgb(50, 36, 20) or WHITE
			local url = headshot(r.UserId)
			if slot.Image.Image ~= url then
				slot.Image.Image = url
			end
			slot.Initial.Text = string.upper(string.sub(r.Name, 1, 1))
			slot.Name.Text = (r.Mine and "⭐ " or "") .. r.Name
			slot.Value.Text = r.ValueText
			slot.Fill.Size = UDim2.fromScale(math.clamp(r.Value / topValue, 0.03, 1), 1)
			slot.Frame.BackgroundColor3 = r.Mine and rgb(236, 72, 140) or WHITE
			slot.Stroke.Transparency = r.Mine and 0.2 or 1
			slot.Stroke.Color = GOLD
		end
	end
	for _, slot in ipairs(board.Rows) do
		if not used[slot] then
			slot.Key = nil
			slot.Frame.Visible = false
		end
	end
	local ranks = {}
	for _, r in ipairs(rows) do
		ranks[keyOf(r)] = r.Rank
	end
	board.Ranks = ranks
	BoardKit.Step(board, now)
end

function BoardKit.SetProgress(board: Board, f: number)
	board.Bar.Size = UDim2.fromScale(math.clamp(f, 0, 1), 1)
end

----------------------------------------------------------------------
-- Animations
----------------------------------------------------------------------

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" and t > 1e8 then
		return t
	end
	return os.time()
end

function BoardKit.Step(board: Board, now: number)
	if not board.Gui.Parent then
		return
	end
	local dt = board.LastStep < 0 and 1 or math.clamp(now - board.LastStep, 0, 1)
	board.LastStep = now
	-- « ● EN DIRECT » qui pulse, reflet, liseré, couronne
	board.Live.BackgroundTransparency = 0.45 + math.sin(now * 5) * 0.45
	local sweepT = (now % 7) / 7
	board.Sweep.Position = UDim2.fromScale(-0.4 + sweepT * 1.8, 0)
	board.Line.Offset = Vector2.new(((now * 0.12) % 2) - 1, 0)
	board.Crown.Position = UDim2.fromScale(0.35, 0.005 + math.sin(now * 2.2) * 0.012)
	board.Crown.Rotation = math.sin(now * 1.3) * 6
	-- petit éclat quand le N°1 change
	local flash = math.clamp(1 - (now - board.HeroFlash) / 1.2, 0, 1)
	board.HeroRing.Thickness = board.RingPx * (1 + flash * 1.5 + math.sin(now * 3) * 0.12)
	board.HeroValue.TextColor3 = GOLD:Lerp(WHITE, flash)
	-- lignes : glissement doux (ressort amorti) + fondu d'arrivée
	local k = 1 - math.exp(-dt * 7)
	for _, slot in ipairs(board.Rows) do
		if slot.Frame.Visible then
			slot.Cur += (slot.Target - slot.Cur) * k
			if math.abs(slot.Target - slot.Cur) < 0.002 then
				slot.Cur = slot.Target
			end
			slot.Alpha = math.min(1, slot.Alpha + dt * 2.5)
			slot.Frame.Position = UDim2.fromScale(0.37, board.Y0 + (slot.Cur - 1) * board.RowH)
			local base = slot.Stroke.Transparency < 1 and 0.25 or 0.9
			slot.Frame.BackgroundTransparency = 1 - (1 - base) * slot.Alpha
			slot.Name.TextTransparency = 1 - slot.Alpha
			slot.Value.TextTransparency = 1 - slot.Alpha
			if now > slot.TrendUntil and slot.Trend.Text ~= "" then
				slot.Trend.Text = ""
			end
		end
	end
	-- bandeau défilant (≈ 40 s pour un tour)
	local tickT = (now % 40) / 40
	board.Ticker.Position = UDim2.fromScale(1 - tickT * 3.3, 0.12)
	-- heure réelle dans le bandeau
	local text = os.date("%H:%M", math.floor(serverNow())) :: string
	if text ~= board.LastClock then
		board.LastClock = text
		board.Clock.Text = text
	end
end

-- Cadre « téléviseur » autour d'une pièce écran (face avant = -Z) :
-- liseré chromé (4 barres qui s'enfoncent dans le cadre du serveur derrière)
-- + plaque « DOPA TV » sous l'écran ; renvoie les pièces
function BoardKit.Frame(parent: Instance, screen: BasePart, opts: { [string]: any }?): { BasePart }
	local o = opts or {}
	local cf = screen.CFrame
	local w, h, d = screen.Size.X, screen.Size.Y, screen.Size.Z
	local lip = o.Lip or 0.22
	local z0, z1 = -d / 2 - 0.1, -d / 2 + 0.4
	local zc, depth = (z0 + z1) / 2, z1 - z0
	local chrome = o.Color or rgb(196, 200, 212)
	local parts = {}
	local function bar(name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = at
		p.Color = color
		p.Material = material
		p.Reflectance = material == Enum.Material.Metal and 0.2 or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		table.insert(parts, p)
		return p
	end
	local g = 0.03 -- (jamais de face confondue avec les côtés de l'écran)
	local full = w + 2 * (lip + g)
	bar("BezelTop", Vector3.new(full, lip, depth), cf * CFrame.new(0, h / 2 + g + lip / 2, zc), chrome, Enum.Material.Metal)
	bar("BezelBottom", Vector3.new(full, lip, depth), cf * CFrame.new(0, -h / 2 - g - lip / 2, zc), chrome, Enum.Material.Metal)
	bar("BezelLeft", Vector3.new(lip, h + 2 * g, depth), cf * CFrame.new(-w / 2 - g - lip / 2, 0, zc), chrome, Enum.Material.Metal)
	bar("BezelRight", Vector3.new(lip, h + 2 * g, depth), cf * CFrame.new(w / 2 + g + lip / 2, 0, zc), chrome, Enum.Material.Metal)
	local ph = o.PlateH or 0.35
	local plate = bar("TVPlate", Vector3.new(math.min(4.2, w * 0.3), ph, depth + 0.04), cf * CFrame.new(0, -h / 2 - g - lip - 0.02 - ph / 2, zc - 0.02), rgb(30, 28, 40), Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Plate"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.3
	gui.MaxDistance = 160
	gui.Parent = plate
	local l = label(gui, "Text", o.Plate or "📺 DOPA TV", 0.05, 0.1, 0.9, 0.8, rgb(236, 236, 246), Enum.Font.GothamBlack)
	l.ZIndex = 2
	return parts
end

function BoardKit.Destroy(board: Board)
	board.Gui:Destroy()
end

return BoardKit
