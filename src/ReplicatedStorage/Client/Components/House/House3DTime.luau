--[[
	House3DTime (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DTime

	v9.9 🕰️📅 SCALE99 : les objets "de l'heure" de la maison sont VRAIS.
	  - Horloges (réveil, coucou, horloge chat, pendule, horloge comtoise) :
	    aiguilles en 3D qui montrent l'heure LOCALE du joueur (os.date),
	    trotteuse qui avance d'un cran par seconde, minutes et heures qui
	    glissent. Une aiguille est construite droite (vers 12 h) par la
	    recette ; on la tourne autour de l'axe du cadran (son axe Z local =
	    la normale du cadran, vers celui qui regarde) : ça marche aussi
	    quand le modèle est déplacé (mode édition, chaise tirée...), en
	    miroir (entry.F) et dans la vue 3D de l'interface.
	  - Calendrier mural : page du mois en cours (photo du mois, nom du mois
	    en français, année, grille des jours qui commence le lundi, jour
	    d'aujourd'hui entouré en rouge, jours passés estompés, dimanches en
	    rouge) ; la page se redessine toute seule à minuit.
	Un seul Heartbeat pour tout (branché seulement s'il y a des horloges ou
	des calendriers vivants, débranché sinon) ; au plus une mise à jour par
	seconde ; les aiguilles loin de la caméra (> 90 studs) attendent.
	Aucune lumière, aucun son.

	API :
	  House3DTime.Hand(b, kind, cx, cy, z, length, tail, width, thick, color, material?) -> BasePart
	      kind = "H" (heures) | "M" (minutes) | "S" (trotteuse) ; unités de la
	      recette ; (cx, cy) = axe, z = arrière de l'aiguille, `length` = de
	      l'axe à la pointe, `tail` = queue derrière l'axe
	  House3DTime.CalendarPage(part, face, canvas?) -> SurfaceGui
	  House3DTime.Angles(date?) -> (heure, minute, seconde) en radians (sens horaire)
	  House3DTime.Month(year, month) -> { Days, First (1 = lundi .. 7 = dimanche) }
	  House3DTime.MONTHS (noms français)
]]

local RunService = game:GetService("RunService")

local House3DTime = {}

House3DTime.MONTHS = {
	"janvier", "février", "mars", "avril", "mai", "juin",
	"juillet", "août", "septembre", "octobre", "novembre", "décembre",
}
local WEEKDAYS = { "L", "M", "M", "J", "V", "S", "D" }
local WEEKDAY_NAMES = { "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche" }

local rgb = Color3.fromRGB
local TAU = math.pi * 2
local FAR = 90 -- (studs) au-delà : les aiguilles attendent que l'on s'approche

----------------------------------------------------------------------
-- Date
----------------------------------------------------------------------

type Date = { year: number, month: number, day: number, hour: number, min: number, sec: number }

local function now(): Date
	local ok, t = pcall(function()
		return os.date("*t")
	end)
	if ok and type(t) == "table" and tonumber(t.year) then
		return {
			year = tonumber(t.year) or 2026,
			month = tonumber(t.month) or 1,
			day = tonumber(t.day) or 1,
			hour = tonumber(t.hour) or 12,
			min = tonumber(t.min) or 0,
			sec = tonumber(t.sec) or 0,
		}
	end
	return { year = 2026, month = 1, day = 1, hour = 12, min = 0, sec = 0 }
end

local function leap(year: number): boolean
	return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

-- Jour de la semaine (Sakamoto) : 1 = lundi .. 7 = dimanche (arithmétique
-- pure : ne dépend ni de os.time ni du fuseau)
local function weekday(year: number, month: number, day: number): number
	local offsets = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
	local y = month < 3 and year - 1 or year
	local w = (y + y // 4 - y // 100 + y // 400 + offsets[month] + day) % 7 -- 0 = dimanche
	return w == 0 and 7 or w
end

function House3DTime.Month(year: number, month: number): { Days: number, First: number }
	local days = ({ 31, leap(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[month] or 30
	return { Days = days, First = weekday(year, month, 1) }
end

-- Angles des aiguilles (radians, sens horaire depuis 12 h)
function House3DTime.Angles(date: Date?): (number, number, number)
	local d = date or now()
	local s = d.sec
	local m = d.min + s / 60
	local h = (d.hour % 12) + m / 60
	return h / 12 * TAU, m / 60 * TAU, s / 60 * TAU
end

----------------------------------------------------------------------
-- Registre (aiguilles, calendriers) et battement unique
----------------------------------------------------------------------

type HandState = { Kind: string, R: number, A: number }
type PageState = { Gui: SurfaceGui, Key: string }

local hands: { [BasePart]: HandState } = setmetatable({}, { __mode = "k" }) :: any
local pages: { [SurfaceGui]: PageState } = setmetatable({}, { __mode = "k" }) :: any
local connection: RBXScriptConnection? = nil
local lastSecond = -1
local lastPageCheck = 0
local drawPage: (gui: SurfaceGui, date: Date) -> ()

-- Pose une aiguille à l'angle `a` (autour de son axe Z local, sens horaire vu de devant)
local function pose(part: BasePart, state: HandState, a: number)
	if math.abs(a - state.A) < 1e-4 then
		return
	end
	local axis = part.CFrame * CFrame.new(0, -state.R, 0) * CFrame.Angles(0, 0, state.A)
	part.CFrame = axis * CFrame.Angles(0, 0, -a) * CFrame.new(0, state.R, 0)
	state.A = a
end

local function angleOf(kind: string, h: number, m: number, s: number): number
	if kind == "S" then
		return s
	elseif kind == "M" then
		return m
	end
	return h
end

local function step()
	local date = now()
	if date.sec == lastSecond then
		return
	end
	lastSecond = date.sec
	local h, m, s = House3DTime.Angles(date)
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local alive = false
	for part, state in pairs(hands) do
		if part.Parent == nil then
			hands[part] = nil
		else
			alive = true
			-- (dans le monde : seulement près de la caméra ; vue 3D : toujours)
			local near = true
			if eye and part:IsDescendantOf(workspace) then
				near = (part.Position - eye).Magnitude <= FAR
			end
			if near then
				pose(part, state, angleOf(state.Kind, h, m, s))
			end
		end
	end
	-- calendriers : le jour a-t-il changé ? (toutes les 5 s suffisent)
	local clock = os.clock()
	if clock - lastPageCheck >= 5 then
		lastPageCheck = clock
		local key = string.format("%d-%d-%d", date.year, date.month, date.day)
		for gui, state in pairs(pages) do
			if gui.Parent == nil then
				pages[gui] = nil
			else
				alive = true
				if state.Key ~= key then
					state.Key = key
					pcall(drawPage, gui, date)
				end
			end
		end
	elseif next(pages) ~= nil then
		alive = true
	end
	if not alive and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureRunning()
	if connection or not RunService:IsClient() then
		return
	end
	local acc = 1
	connection = RunService.Heartbeat:Connect(function(dt: number)
		-- (5 fois par seconde suffit : la trotteuse avance d'un cran par seconde)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local ok, err = pcall(step)
		if not ok then
			warn("[House3DTime] " .. tostring(err))
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end
	end)
end

----------------------------------------------------------------------
-- Aiguilles
----------------------------------------------------------------------

function House3DTime.Hand(b: any, kind: string, cx: number, cy: number, z: number, length: number, tail: number, width: number, thick: number, color: Color3, material: Enum.Material?): BasePart
	local total = length + tail
	local part: BasePart = b.BoxR(CFrame.new(cx, cy + (length - tail) / 2, z + thick / 2), width, total, thick, color, material or Enum.Material.SmoothPlastic)
	part.Name = kind == "S" and "SecondHand" or (kind == "M" and "MinuteHand" or "HourHand")
	part.CastShadow = false
	-- distance (studs) de l'axe au centre de la pièce, le long de son axe Y
	local r = part.Size.Y * ((length - tail) / 2) / math.max(0.01, total)
	local state: HandState = { Kind = kind, R = r, A = 0 }
	hands[part] = state
	local h, m, s = House3DTime.Angles()
	pose(part, state, angleOf(kind, h, m, s))
	ensureRunning()
	return part
end

----------------------------------------------------------------------
-- Calendrier : photo du mois + grille
----------------------------------------------------------------------

type Theme = { Sky0: Color3, Sky1: Color3, Far: Color3, Near: Color3, Accent: Color3, Motif: string, Sun: Color3? }

-- Une "photo" par mois (saisons de l'hémisphère nord)
local THEMES: { Theme } = {
	{ Sky0 = rgb(150, 190, 230), Sky1 = rgb(225, 238, 250), Far = rgb(236, 242, 250), Near = rgb(250, 252, 255), Accent = rgb(70, 120, 190), Motif = "Snow", Sun = rgb(255, 250, 230) },
	{ Sky0 = rgb(120, 150, 200), Sky1 = rgb(240, 214, 222), Far = rgb(214, 224, 240), Near = rgb(246, 248, 252), Accent = rgb(120, 110, 190), Motif = "Cabin" },
	{ Sky0 = rgb(120, 190, 240), Sky1 = rgb(220, 240, 250), Far = rgb(140, 196, 120), Near = rgb(110, 176, 90), Accent = rgb(60, 160, 90), Motif = "Daffodils", Sun = rgb(255, 236, 150) },
	{ Sky0 = rgb(130, 196, 245), Sky1 = rgb(250, 230, 240), Far = rgb(150, 200, 130), Near = rgb(120, 186, 100), Accent = rgb(230, 110, 150), Motif = "Blossom", Sun = rgb(255, 240, 180) },
	{ Sky0 = rgb(110, 180, 240), Sky1 = rgb(210, 236, 252), Far = rgb(120, 180, 100), Near = rgb(96, 160, 80), Accent = rgb(220, 70, 90), Motif = "Tulips", Sun = rgb(255, 238, 160) },
	{ Sky0 = rgb(100, 170, 235), Sky1 = rgb(250, 226, 200), Far = rgb(160, 150, 200), Near = rgb(120, 100, 170), Accent = rgb(130, 90, 190), Motif = "Lavender", Sun = rgb(255, 226, 140) },
	{ Sky0 = rgb(60, 160, 230), Sky1 = rgb(190, 230, 250), Far = rgb(40, 150, 200), Near = rgb(246, 222, 170), Accent = rgb(20, 140, 190), Motif = "Beach", Sun = rgb(255, 230, 120) },
	{ Sky0 = rgb(120, 90, 170), Sky1 = rgb(255, 170, 110), Far = rgb(60, 110, 170), Near = rgb(236, 196, 150), Accent = rgb(230, 110, 70), Motif = "Sunset", Sun = rgb(255, 200, 110) },
	{ Sky0 = rgb(120, 180, 230), Sky1 = rgb(250, 236, 200), Far = rgb(170, 170, 90), Near = rgb(226, 190, 90), Accent = rgb(200, 140, 50), Motif = "Harvest", Sun = rgb(255, 222, 140) },
	{ Sky0 = rgb(130, 170, 220), Sky1 = rgb(250, 220, 180), Far = rgb(200, 120, 60), Near = rgb(150, 110, 60), Accent = rgb(210, 100, 40), Motif = "Autumn", Sun = rgb(255, 214, 140) },
	{ Sky0 = rgb(150, 160, 180), Sky1 = rgb(220, 222, 226), Far = rgb(120, 136, 150), Near = rgb(96, 120, 130), Accent = rgb(90, 110, 140), Motif = "Mist" },
	{ Sky0 = rgb(20, 30, 70), Sky1 = rgb(60, 70, 130), Far = rgb(220, 230, 245), Near = rgb(245, 248, 255), Accent = rgb(190, 40, 50), Motif = "Christmas", Sun = rgb(250, 246, 220) },
}

local function frame(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, round: number?, z: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.ZIndex = z or 1
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = round >= 1 and UDim.new(1, 0) or UDim.new(0, math.floor(round * 100 + 0.5))
		corner.Parent = f
	end
	f.Parent = parent
	return f
end

local function circle(parent: Instance, cx: number, cy: number, d: number, color: Color3, z: number?): Frame
	return frame(parent, cx - d / 2, cy - d / 2, d, d, color, 1, z)
end

local function label(parent: Instance, x: number, y: number, w: number, h: number, text: string, size: number, color: Color3, font: Enum.Font?, z: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Text = text
	t.TextSize = size
	t.TextColor3 = color
	t.Font = font or Enum.Font.GothamBold
	t.ZIndex = z or 3
	t.Parent = parent
	return t
end

local function gradient(target: GuiObject, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = target
end

-- Petit arbre "boule" (tronc + feuillage)
local function tree(parent: Instance, x: number, base: number, h: number, leaf: Color3, z: number)
	frame(parent, x - h * 0.05, base - h * 0.45, h * 0.1, h * 0.45, rgb(110, 80, 60), nil, z)
	circle(parent, x, base - h * 0.62, h * 0.62, leaf, z + 1)
	circle(parent, x - h * 0.16, base - h * 0.5, h * 0.4, leaf:Lerp(Color3.new(0, 0, 0), 0.08), z + 1)
end

-- Sapin (3 étages de losanges aplatis)
local function pine(parent: Instance, x: number, base: number, h: number, color: Color3, z: number)
	frame(parent, x - h * 0.05, base - h * 0.18, h * 0.1, h * 0.18, rgb(100, 70, 50), nil, z)
	for index = 0, 2 do
		local s = h * (0.44 - index * 0.11)
		local cy = base - h * (0.32 + index * 0.22)
		local f = frame(parent, x - s / 2, cy - s / 2, s, s, color:Lerp(Color3.new(1, 1, 1), index * 0.05), nil, z + 1)
		f.Rotation = 45
	end
end

-- Photo du mois dans `holder` (w x h px)
local function paintPhoto(holder: Frame, month: number, w: number, h: number)
	local theme = THEMES[month] or THEMES[1]
	local sky = frame(holder, 0, 0, w, h, Color3.new(1, 1, 1), nil, 1)
	gradient(sky, theme.Sky0, theme.Sky1)
	local horizon = h * 0.62
	if theme.Sun then
		circle(holder, w * 0.74, h * 0.26, h * 0.2, theme.Sun, 2)
		local halo = circle(holder, w * 0.74, h * 0.26, h * 0.34, theme.Sun, 2)
		halo.BackgroundTransparency = 0.75
	end
	local motif = theme.Motif
	if motif == "Christmas" then
		for index = 1, 18 do
			local sx = (index * 53) % w
			local sy = (index * 29) % math.floor(horizon * 0.8)
			circle(holder, sx, sy + 4, 2 + index % 2, rgb(255, 250, 220), 2)
		end
	end
	-- collines lointaines puis sol proche (grands disques coupés par le cadre)
	circle(holder, w * 0.2, horizon + h * 0.5, w * 1.1, theme.Far, 3)
	circle(holder, w * 0.85, horizon + h * 0.56, w * 1.0, theme.Far:Lerp(Color3.new(0, 0, 0), 0.06), 3)
	if motif == "Beach" or motif == "Sunset" then
		-- mer, vaguelettes, plage
		local sea = frame(holder, 0, horizon - 4, w, h * 0.22, theme.Far, nil, 4)
		gradient(sea, theme.Far, theme.Far:Lerp(Color3.new(1, 1, 1), 0.25))
		for index = 0, 5 do
			frame(holder, 12 + index * (w / 6), horizon + 6 + (index % 2) * 8, w / 10, 2, rgb(255, 255, 255), 1, 5).BackgroundTransparency = 0.3
		end
		circle(holder, w * 0.5, h + w * 0.7, w * 2.0, theme.Near, 5)
		if motif == "Beach" then
			-- parasol rayé + serviette
			frame(holder, w * 0.3, h * 0.66, 3, h * 0.24, rgb(240, 240, 240), nil, 6)
			local top = frame(holder, w * 0.3 - 30, h * 0.62, 62, 18, theme.Accent, 1, 7)
			top.Size = UDim2.fromOffset(62, 20)
			frame(holder, w * 0.55, h * 0.86, 40, 12, rgb(250, 110, 120), 0.2, 6)
		else
			-- reflet du soleil couchant
			frame(holder, w * 0.74 - 16, horizon + 2, 32, 3, theme.Sun or rgb(255, 200, 110), 1, 6)
			frame(holder, w * 0.74 - 10, horizon + 10, 20, 3, theme.Sun or rgb(255, 200, 110), 1, 6)
		end
		return
	end
	circle(holder, w * 0.5, horizon + w * 0.95, w * 2.1, theme.Near, 4)
	if motif == "Snow" or motif == "Christmas" or motif == "Cabin" then
		for index = 0, 4 do
			pine(holder, 18 + index * (w / 5) + (index % 2) * 8, horizon + 14 + (index % 3) * 6, 36 + (index % 2) * 12, rgb(40, 90, 70), 5)
		end
		if motif == "Cabin" then
			local cabin = frame(holder, w * 0.56, horizon - 6, 50, 30, rgb(150, 90, 60), nil, 6)
			frame(cabin, 18, 12, 12, 18, rgb(90, 50, 40), nil, 7)
			frame(cabin, 4, 6, 10, 9, rgb(255, 220, 140), nil, 7)
			local roof = frame(holder, w * 0.56 - 4, horizon - 16, 58, 12, rgb(250, 250, 255), 0.3, 7)
			roof.Size = UDim2.fromOffset(58, 12)
		elseif motif == "Christmas" then
			pine(holder, w * 0.6, horizon + 26, 70, rgb(30, 110, 70), 6)
			for index = 0, 5 do
				circle(holder, w * 0.6 - 18 + (index * 13) % 36, horizon - 10 + index * 5, 6, index % 2 == 0 and theme.Accent or rgb(255, 214, 90), 9)
			end
			circle(holder, w * 0.6, horizon - 20, 9, rgb(255, 220, 90), 9)
		end
		-- flocons
		for index = 1, 22 do
			circle(holder, (index * 37) % w, (index * 23) % math.floor(h * 0.95), 2 + index % 3, rgb(255, 255, 255), 8).BackgroundTransparency = 0.15
		end
	elseif motif == "Blossom" then
		frame(holder, w * 0.34, horizon - 52, 8, 70, rgb(110, 70, 60), nil, 5)
		for index = 0, 9 do
			local a = index / 10 * TAU
			circle(holder, w * 0.35 + math.cos(a) * 36, horizon - 58 + math.sin(a) * 22, 34, index % 2 == 0 and rgb(255, 190, 214) or rgb(250, 160, 196), 6)
		end
		for index = 1, 14 do
			circle(holder, (index * 41) % w, horizon + 10 + (index * 13) % 40, 4, rgb(255, 200, 220), 7)
		end
		tree(holder, w * 0.8, horizon + 8, 40, rgb(110, 170, 90), 5)
	elseif motif == "Daffodils" or motif == "Tulips" or motif == "Lavender" or motif == "Harvest" then
		-- rangées de fleurs / de blé qui fuient vers l'horizon
		for row = 0, 4 do
			local y = horizon + 8 + row * 12
			local count = 8 + row * 3
			for index = 0, count - 1 do
				local x = (index + 0.5) * w / count + (row % 2) * 4
				local d = 3 + row * 1.6
				local color = theme.Accent
				if motif == "Daffodils" then
					color = index % 3 == 0 and rgb(255, 255, 240) or rgb(255, 214, 60)
				elseif motif == "Tulips" then
					color = ({ rgb(230, 60, 80), rgb(255, 150, 190), rgb(255, 200, 70) })[(row % 3) + 1]
				elseif motif == "Harvest" then
					color = rgb(240, 200, 100):Lerp(rgb(200, 150, 60), (index % 3) / 3)
				end
				circle(holder, x, y, d, color, 6)
			end
		end
		if motif == "Harvest" then
			tree(holder, w * 0.18, horizon + 4, 44, rgb(150, 150, 60), 5)
		else
			tree(holder, w * 0.86, horizon + 4, 40, theme.Far:Lerp(Color3.new(0, 0, 0), 0.2), 5)
		end
	elseif motif == "Autumn" then
		for index = 0, 5 do
			local leaf = ({ rgb(220, 110, 40), rgb(240, 170, 50), rgb(190, 60, 40) })[(index % 3) + 1]
			tree(holder, 20 + index * (w / 6), horizon + 12 + (index % 2) * 8, 46 + (index % 3) * 8, leaf, 5)
		end
		for index = 1, 16 do
			circle(holder, (index * 43) % w, horizon + 24 + (index * 11) % 30, 4, rgb(230, 130, 50), 8)
		end
	elseif motif == "Mist" then
		-- lac brumeux, arbres nus
		local lake = frame(holder, 0, horizon + 4, w, h * 0.2, rgb(150, 170, 186), nil, 5)
		gradient(lake, rgb(170, 186, 200), rgb(120, 140, 160))
		for index = 0, 3 do
			local x = 20 + index * 70
			frame(holder, x, horizon - 40, 4, 48, rgb(80, 80, 90), nil, 6)
			local branch = frame(holder, x - 8, horizon - 32, 20, 2, rgb(80, 80, 90), nil, 6)
			branch.Rotation = -30
		end
		local fog = frame(holder, 0, horizon - 20, w, 30, rgb(235, 238, 242), nil, 7)
		fog.BackgroundTransparency = 0.45
	end
end

-- Dessine la page du mois de `date` dans la toile (canvas 300 x 420 px)
drawPage = function(gui: SurfaceGui, date: Date)
	for _, child in ipairs(gui:GetChildren()) do
		child:Destroy()
	end
	local W, H = gui.CanvasSize.X, gui.CanvasSize.Y
	local theme = THEMES[date.month] or THEMES[1]
	local paper = frame(gui, 0, 0, W, H, rgb(252, 251, 247), nil, 1)
	paper.Name = "Page"
	-- trous de la reliure
	for index = 0, 13 do
		circle(paper, 18 + index * (W - 36) / 13, 9, 7, rgb(70, 66, 64), 2)
	end
	-- photo (moitié haute) avec un fin liseré blanc
	local photoH = math.floor(H * 0.44)
	local holder = frame(paper, 10, 20, W - 20, photoH, rgb(255, 255, 255), nil, 2)
	holder.ClipsDescendants = true
	pcall(paintPhoto, holder, date.month, W - 20, photoH)
	-- bandeau : mois + année
	local bandY = 20 + photoH + 6
	local band = frame(paper, 10, bandY, W - 20, 34, theme.Accent, 0.06, 2)
	label(band, 12, 0, W - 110, 34, string.upper(House3DTime.MONTHS[date.month] or ""), 22, rgb(255, 255, 255), Enum.Font.GothamBlack, 3).TextXAlignment = Enum.TextXAlignment.Left
	label(band, W - 100, 0, 76, 34, tostring(date.year), 20, rgb(255, 255, 255), Enum.Font.GothamBold, 3).TextXAlignment = Enum.TextXAlignment.Right
	-- jours de la semaine
	local gridX, cellW = 12, (W - 24) / 7
	local headY = bandY + 40
	for index, name in ipairs(WEEKDAYS) do
		label(paper, gridX + (index - 1) * cellW, headY, cellW, 16, name, 13, index == 7 and rgb(200, 50, 60) or rgb(110, 104, 110), Enum.Font.GothamBold, 3)
	end
	frame(paper, 12, headY + 18, W - 24, 1, rgb(210, 204, 200), nil, 2)
	-- grille (6 semaines au plus)
	local info = House3DTime.Month(date.year, date.month)
	local rows = math.ceil((info.First - 1 + info.Days) / 7)
	local gridY = headY + 22
	local cellH = math.min(26, (H - gridY - 22) / rows)
	for day = 1, info.Days do
		local slot = info.First - 1 + day - 1
		local col = slot % 7
		local row = slot // 7
		local x = gridX + col * cellW
		local y = gridY + row * cellH
		local sunday = col == 6
		local past = day < date.day
		local color = sunday and rgb(200, 50, 60) or rgb(50, 46, 52)
		local t = label(paper, x, y, cellW, cellH, tostring(day), 15, color, day == date.day and Enum.Font.GothamBlack or Enum.Font.Gotham, 4)
		if past then
			t.TextTransparency = 0.55
		end
		if day == date.day then
			-- AUJOURD'HUI : entouré au feutre rouge
			local ring = circle(paper, x + cellW / 2, y + cellH / 2, math.min(cellW, cellH) + 4, rgb(255, 255, 255), 3)
			ring.BackgroundTransparency = 1
			local stroke = Instance.new("UIStroke")
			stroke.Color = rgb(220, 40, 50)
			stroke.Thickness = 3
			stroke.Parent = ring
		end
	end
	-- pied de page : la date complète
	local wd = weekday(date.year, date.month, date.day)
	label(paper, 12, H - 22, W - 24, 18, string.format("Aujourd'hui : %s %d %s", WEEKDAY_NAMES[wd], date.day, House3DTime.MONTHS[date.month] or ""), 12, rgb(150, 140, 150), Enum.Font.GothamMedium, 3)
end

-- Toile du calendrier sur la face `face` de `part` (page redessinée à minuit)
function House3DTime.CalendarPage(part: BasePart, face: Enum.NormalId, canvas: Vector2?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CalendarPage"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas or Vector2.new(300, 420)
	gui.LightInfluence = 0.6
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.MaxDistance = 160
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	local date = now()
	local ok, err = pcall(drawPage, gui, date)
	if not ok then
		warn("[House3DTime] Calendrier : " .. tostring(err))
	end
	pages[gui] = { Gui = gui, Key = string.format("%d-%d-%d", date.year, date.month, date.day) }
	ensureRunning()
	return gui
end

return House3DTime
