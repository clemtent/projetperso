--[[
	LiveScreens (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > LiveScreens

	v9.5 🖥️ Ce qui passe sur les écrans 3D des objets "Dopamine Setup"
	(LiveProps crée la SurfaceGui, ce module la remplit et l'anime) :
	  - "Runner" : mini jeu de course façon Subway (voie en perspective,
	    traverses qui défilent, rails, pièces, trains qu'on évite, saut,
	    compteur de pièces et de distance) ;
	  - "Live"   : mini live stream (streameur qui parle et cligne des yeux,
	    badge 🔴 LIVE, spectateurs, chat qui défile, cœurs, objectif) ;
	  - "DVD"    : le logo DVD qui rebondit, change de couleur, fête les coins ;
	  - "News"   : flash info (logo, présentateur, bandeau "Breaking news",
	    titres absurdes, bandeau défilant) ;
	  - "Music"  : petit écran LCD de la chaîne hi-fi (morceau en cours,
	    égaliseur).
	Tout est dessiné UNE fois en Frames / TextLabels (≈ 30 à 60 instances par
	écran), puis seulement déplacé / recoloré : aucune création par image.
	Step(dt) est appelé par LiveProps (≤ 30 fois / s, seulement si l'écran est
	proche et visible).

	API :
	  LiveScreens.New(kind, gui: SurfaceGui, canvas: Vector2) -> Screen
	  screen:Step(dt)   screen:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

local LiveScreens = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local FONT_BLACK = Enum.Font.GothamBlack
local FONT_BOLD = Enum.Font.GothamBold
local FONT = Enum.Font.Gotham

export type Screen = {
	Kind: string,
	Root: Frame,
	Step: (self: Screen, dt: number) -> (),
	Destroy: (self: Screen) -> (),
}

local random = Random.new()

----------------------------------------------------------------------
-- Aides de dessin
----------------------------------------------------------------------

local function box(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, z: number?, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.ZIndex = z or 1
	frame.Parent = parent
	return frame
end

local function round(frame: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius and UDim.new(0, radius) or UDim.new(1, 0)
	corner.Parent = frame
end

local function gradient(frame: GuiObject, a: Color3, b: Color3, rotation: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation
	g.Parent = frame
	return g
end

local function label(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3, font: Enum.Font?, z: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.Font = font or FONT_BOLD
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.ZIndex = z or 5
	l.Parent = parent
	return l
end

local function stroke(textLabel: TextLabel, color: Color3, transparency: number)
	textLabel.TextStrokeColor3 = color
	textLabel.TextStrokeTransparency = transparency
end

-- Trait (Frame tourné) d'un point à un autre
local function line(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number, thickness: number, color: Color3, z: number?): Frame
	local dx, dy = x1 - x0, y1 - y0
	local length = math.sqrt(dx * dx + dy * dy)
	local frame = box(parent, name, (x0 + x1) / 2, (y0 + y1) / 2, thickness, length, color, z)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Rotation = math.deg(math.atan2(dx, -dy))
	return frame
end

local function newRoot(gui: SurfaceGui, canvas: Vector2, color: Color3): Frame
	local root = box(gui, "Live", 0, 0, canvas.X, canvas.Y, color)
	root.ClipsDescendants = true
	return root
end

local function formatInt(value: number): string
	local text = tostring(math.floor(value))
	local out = text:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

----------------------------------------------------------------------
-- 🏃 RUNNER : course façon Subway
----------------------------------------------------------------------

local LANES = { -1, 0, 1 }

local function newRunner(gui: SurfaceGui, canvas: Vector2): Screen
	local W, H = canvas.X, canvas.Y
	local root = newRoot(gui, canvas, rgb(120, 170, 255))
	gradient(root, rgb(96, 150, 255), rgb(255, 196, 214), 90)
	local horizon = math.floor(H * 0.4)
	local bottom = H
	local cx = W / 2
	local half = W * 0.46 -- demi-largeur de la voie en bas
	-- soleil, nuages, ville au loin
	local sun = box(root, "Sun", W * 0.78, H * 0.08, 26, 26, rgb(255, 236, 140), 2)
	round(sun)
	for index = 1, 2 do
		local cloud = box(root, "Cloud", W * (0.12 + index * 0.3), H * (0.06 + index * 0.05), 40, 10, WHITE, 2, 0.15)
		round(cloud)
	end
	local skyline = { 0.05, 0.12, 0.2, 0.3, 0.62, 0.7, 0.8, 0.9 }
	for index, x in ipairs(skyline) do
		local h = 14 + (index * 37 % 5) * 7
		local building = box(root, "Building", W * x, horizon - h, W * 0.085, h, rgb(120 + index * 6, 110, 170), 2)
		for row = 0, math.floor(h / 8) - 1 do
			box(building, "Window", 3, 3 + row * 8, W * 0.085 - 6, 3, rgb(255, 230, 150), 3, 0.35)
		end
	end
	-- sol (murs de soutènement / ballast)
	local ground = box(root, "Ground", 0, horizon, W, H - horizon, rgb(150, 130, 160), 3)
	gradient(ground, rgb(170, 150, 185), rgb(96, 86, 110), 90)
	-- bandes de la voie (traverses qui défilent)
	local BANDS = 14
	local bands: { Frame } = {}
	local bandT: { number } = {}
	for index = 1, BANDS do
		local t0 = (index - 1) / BANDS
		local t1 = index / BANDS
		local y0 = horizon + (bottom - horizon) * t0
		local y1 = horizon + (bottom - horizon) * t1
		local mid = (t0 + t1) / 2
		local w = half * 2 * (0.12 + 0.88 * mid)
		local band = box(root, "Band", cx - w / 2, y0, w, y1 - y0 + 1, rgb(110, 96, 90), 4)
		table.insert(bands, band)
		table.insert(bandT, mid)
	end
	-- rails (du point de fuite vers le bas)
	for _, k in ipairs({ -1, -0.36, 0.36, 1 }) do
		line(root, "Rail", cx + k * half * 0.12, horizon, cx + k * half * 0.96, bottom, 2, rgb(230, 226, 240), 5)
	end
	for _, k in ipairs({ -1.12, 1.12 }) do
		line(root, "Wall", cx + k * half * 0.12, horizon, cx + k * half * 1.02, bottom, 4, rgb(255, 150, 200), 5)
	end
	-- position à l'écran d'une profondeur z (0 = près, 1 = horizon)
	local function project(z: number): (number, number)
		local s = 1 / (1 + z * 6)
		local t = (s - 1 / 7) / (1 - 1 / 7)
		return horizon + (bottom - horizon) * t, 0.12 + 0.88 * t
	end
	-- pièces
	type Coin = { Frame: Frame, Lane: number, Z: number }
	local coins: { Coin } = {}
	for index = 1, 5 do
		local frame = box(root, "Coin", 0, 0, 10, 10, rgb(255, 214, 60), 8)
		frame.AnchorPoint = Vector2.new(0.5, 1)
		round(frame)
		local ring = Instance.new("UIStroke")
		ring.Color = rgb(220, 150, 20)
		ring.Thickness = 1.5
		ring.Parent = frame
		table.insert(coins, { Frame = frame, Lane = LANES[index % 3 + 1], Z = index / 5 })
	end
	-- train (face avant)
	local train = box(root, "Train", 0, 0, 40, 50, rgb(236, 70, 90), 7)
	train.AnchorPoint = Vector2.new(0.5, 1)
	round(train, 4)
	local windshield = box(train, "Windshield", 0, 0, 10, 10, rgb(170, 220, 255), 8)
	windshield.Position = UDim2.fromScale(0.12, 0.1)
	windshield.Size = UDim2.fromScale(0.76, 0.34)
	round(windshield, 3)
	local stripe = box(train, "Stripe", 0, 0, 10, 10, rgb(255, 230, 120), 8)
	stripe.Position = UDim2.fromScale(0, 0.56)
	stripe.Size = UDim2.fromScale(1, 0.08)
	for _, hx in ipairs({ 0.18, 0.7 }) do
		local lamp = box(train, "Lamp", 0, 0, 10, 10, rgb(255, 250, 200), 9)
		lamp.Position = UDim2.fromScale(hx, 0.72)
		lamp.Size = UDim2.fromScale(0.12, 0.1)
		round(lamp)
	end
	local trainLane, trainZ = 1, 1
	-- coureur
	local runner = Instance.new("Frame")
	runner.Name = "Runner"
	runner.BackgroundTransparency = 1
	runner.Size = UDim2.fromOffset(24, 34)
	runner.AnchorPoint = Vector2.new(0.5, 1)
	runner.ZIndex = 20
	runner.Parent = root
	local shadow = box(root, "Shadow", 0, 0, 22, 6, BLACK, 19, 0.6)
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	round(shadow)
	local legs = {}
	for index, x in ipairs({ 7, 13 }) do
		local leg = box(runner, "Leg", x, 20, 5, 13, rgb(60, 70, 140), 21)
		leg.AnchorPoint = Vector2.new(0.5, 0)
		legs[index] = leg
		box(leg, "Shoe", -1, 10, 7, 4, rgb(255, 90, 140), 22)
	end
	local body = box(runner, "Body", 3, 8, 18, 15, rgb(255, 140, 60), 22)
	round(body, 4)
	box(runner, "Pack", 5, 10, 14, 10, rgb(90, 200, 160), 21)
	local head = box(runner, "Head", 6, -1, 12, 12, rgb(255, 214, 180), 23)
	round(head)
	local cap = box(runner, "Cap", 5, -2, 14, 5, rgb(60, 140, 255), 24)
	round(cap, 2)
	-- interface (pièces, distance)
	local coinsLabel = label(root, "Coins", "🪙 0", 6, 4, 100, 16, 13, WHITE, FONT_BLACK, 30)
	stroke(coinsLabel, rgb(120, 60, 20), 0.2)
	local distLabel = label(root, "Distance", "0 m", W - 106, 4, 100, 16, 13, WHITE, FONT_BLACK, 30)
	distLabel.TextXAlignment = Enum.TextXAlignment.Right
	stroke(distLabel, rgb(40, 40, 90), 0.2)
	local combo = label(root, "Combo", "", 0, H * 0.46, W, 18, 14, rgb(255, 240, 120), FONT_BLACK, 30)
	combo.TextXAlignment = Enum.TextXAlignment.Center
	stroke(combo, rgb(200, 60, 120), 0.1)

	local phase = 0
	local distance = random:NextInteger(100, 900)
	local collected = random:NextInteger(0, 40)
	local lane, laneX = 0, 0
	local jump = 0
	local run = 0
	local comboTime = 0
	local speed = 0.55
	local screen = {} :: Screen
	screen.Kind = "Runner"
	screen.Root = root
	local laneStep = half * 0.62
	function screen.Step(_self: Screen, dt: number)
		phase = (phase + dt * speed * 7) % 2
		run += dt * 14
		distance += dt * 38
		-- traverses
		for index, band in ipairs(bands) do
			local t = bandT[index]
			local depth = 1 / (0.12 + t) + phase
			local dark = math.floor(depth * 1.3) % 2 == 0
			band.BackgroundColor3 = dark and rgb(96, 80, 76) or rgb(150, 126, 112)
		end
		-- train
		trainZ -= dt * speed * 0.8
		if trainZ < -0.08 then
			trainZ = 1
			trainLane = LANES[random:NextInteger(1, 3)]
		end
		if trainLane == lane and trainZ < 0.45 and trainZ > 0 then
			-- esquive : voie voisine libre
			lane = lane == 0 and (random:NextNumber() < 0.5 and -1 or 1) or 0
		end
		local ty, ts = project(math.max(0, trainZ))
		train.Visible = trainZ > -0.05
		train.Position = UDim2.fromOffset(cx + trainLane * laneStep * ts, ty)
		train.Size = UDim2.fromOffset(laneStep * 0.9 * ts, laneStep * 1.1 * ts)
		train.ZIndex = 7
		-- pièces
		for _, coin in ipairs(coins) do
			coin.Z -= dt * speed
			if coin.Z < 0.02 then
				if coin.Lane == lane and jump <= 0 then
					collected += 1
					comboTime = 0.6
				end
				coin.Z = 1
				coin.Lane = LANES[random:NextInteger(1, 3)]
			end
			local y, s = project(coin.Z)
			local size = 3 + 10 * s
			coin.Frame.Position = UDim2.fromOffset(cx + coin.Lane * laneStep * s, y - 2 * s)
			coin.Frame.Size = UDim2.fromOffset(size * (0.55 + 0.45 * math.abs(math.cos(run * 0.3 + coin.Z * 9))), size)
			coin.Frame.ZIndex = coin.Z < trainZ and 10 or 6
		end
		-- saut de temps en temps
		if jump <= 0 and random:NextNumber() < dt * 0.25 then
			jump = 0.7
		end
		local lift = 0
		if jump > 0 then
			jump -= dt
			local t = 1 - math.max(0, jump) / 0.7
			lift = math.sin(t * math.pi) * H * 0.18
		end
		laneX += (lane * laneStep - laneX) * math.min(1, dt * 10)
		local groundY = H - 8
		runner.Position = UDim2.fromOffset(cx + laneX, groundY - lift - math.abs(math.sin(run)) * 2)
		shadow.Position = UDim2.fromOffset(cx + laneX, groundY)
		shadow.Size = UDim2.fromOffset(22 - lift * 0.2, 6)
		legs[1].Rotation = math.sin(run) * 35
		legs[2].Rotation = -math.sin(run) * 35
		coinsLabel.Text = "🪙 " .. formatInt(collected)
		distLabel.Text = formatInt(distance) .. " m"
		if comboTime > 0 then
			comboTime -= dt
			combo.Text = "+1 🪙"
			combo.TextTransparency = 1 - math.clamp(comboTime / 0.6, 0, 1)
		else
			combo.Text = ""
		end
	end
	function screen.Destroy(_self: Screen)
		root:Destroy()
	end
	return screen
end

----------------------------------------------------------------------
-- 🔴 LIVE : mini live stream
----------------------------------------------------------------------

local CHAT_LINES = {
	"W stream 🔥", "gg!!", "lol 😂", "first!", "💖💖💖", "that setup tho 😳", "POG", "+1 🧠", "can I be a mod?", "hi from France 🇫🇷",
	"go go go", "10/10 🎉", "clicking with you 👆", "insane 🤯", "no way", "the DVD logo!!", "chat is this real", "🍿🍿",
}
local CHAT_NAMES = { "Ana", "BobbyX", "Chloé", "D_Wave", "Emma", "Farid", "Gaby99", "HugoGG", "Inès", "Jules", "KiraCat", "Léo" }
local NAME_COLORS = { rgb(255, 120, 170), rgb(120, 220, 255), rgb(255, 214, 90), rgb(140, 240, 150), rgb(200, 150, 255), rgb(255, 160, 90) }

local function newLive(gui: SurfaceGui, canvas: Vector2): Screen
	local W, H = canvas.X, canvas.Y
	local root = newRoot(gui, canvas, rgb(60, 40, 90))
	local videoW = math.floor(W * 0.66)
	local video = box(root, "Video", 0, 0, videoW, H, rgb(70, 46, 110), 2)
	gradient(video, rgb(92, 60, 150), rgb(255, 120, 190), 60)
	-- chambre du streameur : bande LED, posters, étagère
	local led = box(video, "Led", 0, math.floor(H * 0.1), videoW, 3, rgb(255, 90, 200), 3)
	box(video, "Poster", videoW * 0.08, H * 0.2, videoW * 0.16, H * 0.26, rgb(120, 220, 255), 3)
	box(video, "Poster2", videoW * 0.76, H * 0.18, videoW * 0.14, H * 0.2, rgb(255, 214, 90), 3)
	box(video, "Shelf", videoW * 0.7, H * 0.44, videoW * 0.26, 3, rgb(60, 40, 70), 3)
	local plush = box(video, "Plush", videoW * 0.76, H * 0.44 - 12, 12, 12, rgb(255, 170, 200), 3)
	round(plush)
	-- streameur (corps, tête, cheveux, yeux, bouche, casque, micro)
	local sx = videoW * 0.46
	local hoodie = box(video, "Hoodie", sx - 34, H * 0.62, 68, H * 0.5, rgb(255, 120, 170), 5)
	round(hoodie, 16)
	local head = box(video, "Head", sx - 20, H * 0.3, 40, 42, rgb(255, 214, 186), 6)
	round(head, 18)
	local hair = box(head, "Hair", -2, -4, 44, 16, rgb(90, 60, 150), 7)
	round(hair, 8)
	local eyes = {}
	for index, ex in ipairs({ 11, 25 }) do
		local eye = box(head, "Eye", ex, 18, 5, 6, rgb(40, 30, 50), 8)
		round(eye)
		eyes[index] = eye
	end
	local mouth = box(head, "Mouth", 16, 30, 9, 3, rgb(180, 60, 80), 8)
	round(mouth, 2)
	local band = box(video, "Headset", sx - 23, H * 0.26, 46, 5, rgb(40, 40, 52), 8)
	round(band, 3)
	for _, ex in ipairs({ -26, 18 }) do
		local cup = box(video, "Cup", sx + ex, H * 0.38, 9, 16, rgb(40, 40, 52), 8)
		round(cup, 4)
	end
	local mic = box(video, "Mic", sx + 22, H * 0.56, 7, 18, rgb(60, 60, 70), 8)
	round(mic, 3)
	-- badge LIVE + spectateurs
	local badge = box(video, "LiveBadge", 6, 6, 42, 16, rgb(236, 40, 60), 10)
	round(badge, 4)
	local liveText = label(badge, "Text", Locale.T("🔴 LIVE"), 0, 0, 42, 16, 10, WHITE, FONT_BLACK, 11)
	liveText.TextXAlignment = Enum.TextXAlignment.Center
	local viewersBox = box(video, "Viewers", 52, 6, 62, 16, BLACK, 10, 0.45)
	round(viewersBox, 4)
	local viewers = label(viewersBox, "Text", "👁 1 234", 0, 0, 62, 16, 10, WHITE, FONT_BOLD, 11)
	viewers.TextXAlignment = Enum.TextXAlignment.Center
	-- objectif d'abonnés
	local goal = box(video, "Goal", 6, H - 16, videoW - 12, 10, BLACK, 10, 0.5)
	round(goal, 5)
	local goalFill = box(goal, "Fill", 0, 0, 10, 10, rgb(120, 240, 170), 11)
	round(goalFill, 5)
	local goalText = label(goal, "Text", "", 0, 0, videoW - 12, 10, 8, WHITE, FONT_BOLD, 12)
	goalText.TextXAlignment = Enum.TextXAlignment.Center
	-- cœurs qui montent
	local hearts = {}
	for index = 1, 3 do
		local heart = label(video, "Heart", "💖", videoW - 26, H, 18, 18, 14, WHITE, FONT, 12)
		hearts[index] = { Label = heart, T = index * 0.7 }
	end
	-- chat (à droite)
	local chatW = W - videoW
	local chat = box(root, "Chat", videoW, 0, chatW, H, rgb(24, 20, 36), 3)
	local title = label(chat, "Title", Locale.T("💬 Live chat"), 6, 2, chatW - 8, 16, 10, rgb(200, 190, 230), FONT_BLACK, 5)
	local _ = title
	local LINES = 6
	local lineH = math.floor((H - 22) / LINES)
	local rows = {}
	for index = 1, LINES do
		local row = label(chat, "Line", "", 6, 20 + (index - 1) * lineH, chatW - 10, lineH, 9, WHITE, FONT, 5)
		row.RichText = true
		row.TextWrapped = true
		row.TextYAlignment = Enum.TextYAlignment.Top
		rows[index] = row
	end
	local messages: { string } = {}
	local function pushMessage()
		local name = CHAT_NAMES[random:NextInteger(1, #CHAT_NAMES)]
		local color = NAME_COLORS[random:NextInteger(1, #NAME_COLORS)]
		local text = Locale.T(CHAT_LINES[random:NextInteger(1, #CHAT_LINES)])
		local hex = string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
		table.insert(messages, '<font color="' .. hex .. '"><b>' .. name .. "</b></font> " .. text)
		while #messages > LINES do
			table.remove(messages, 1)
		end
		for index, row in ipairs(rows) do
			row.Text = messages[index] or ""
		end
	end
	for _ = 1, LINES do
		pushMessage()
	end

	local clock = 0
	local chatTimer = 0
	local talk = 0
	local blink = 2
	local viewerCount = random:NextInteger(800, 4000)
	local follows = random:NextInteger(200, 900)
	local screen = {} :: Screen
	screen.Kind = "Live"
	screen.Root = root
	function screen.Step(_self: Screen, dt: number)
		clock += dt
		chatTimer += dt
		if chatTimer > 1.1 then
			chatTimer = 0
			pushMessage()
			viewerCount = math.max(100, viewerCount + random:NextInteger(-12, 20))
			viewers.Text = "👁 " .. formatInt(viewerCount)
			if random:NextNumber() < 0.3 then
				follows += 1
			end
		end
		-- bouche qui parle, clignement, tête qui bouge
		talk += dt
		if talk > 0.12 then
			talk = 0
			mouth.Size = UDim2.fromOffset(9, random:NextInteger(2, 7))
		end
		blink -= dt
		local closed = blink < 0.12
		if blink < 0 then
			blink = random:NextNumber(2, 4)
		end
		for _, eye in ipairs(eyes) do
			eye.Size = UDim2.fromOffset(5, closed and 1 or 6)
		end
		head.Position = UDim2.fromOffset(sx - 20 + math.sin(clock * 1.7) * 2, H * 0.3 + math.sin(clock * 2.3) * 1.5)
		led.BackgroundColor3 = Color3.fromHSV((clock * 0.1) % 1, 0.7, 1)
		-- cœurs
		for _, heart in ipairs(hearts) do
			heart.T += dt
			local t = heart.T % 2.1 / 2.1
			heart.Label.Position = UDim2.fromOffset(videoW - 26 + math.sin(heart.T * 3) * 5, H * (1 - t) - 10)
			heart.Label.TextTransparency = t
		end
		-- objectif
		local goalMax = (math.floor(follows / 1000) + 1) * 1000
		local ratio = follows / goalMax
		goalFill.Size = UDim2.fromOffset(math.max(10, (videoW - 12) * ratio), 10)
		goalText.Text = Locale.T("Follower goal %s/%s", formatInt(follows), formatInt(goalMax))
	end
	function screen.Destroy(_self: Screen)
		root:Destroy()
	end
	return screen
end

----------------------------------------------------------------------
-- 📀 DVD : le logo qui rebondit
----------------------------------------------------------------------

local DVD_COLORS = { rgb(255, 46, 136), rgb(0, 200, 255), rgb(157, 78, 221), rgb(40, 200, 40), rgb(255, 190, 0), rgb(255, 110, 20) }

local function newDVD(gui: SurfaceGui, canvas: Vector2): Screen
	local W, H = canvas.X, canvas.Y
	local root = newRoot(gui, canvas, rgb(6, 6, 12))
	local LW, LH = math.floor(W * 0.24), math.floor(W * 0.14)
	local logo = Instance.new("Frame")
	logo.Name = "Logo"
	logo.BackgroundTransparency = 1
	logo.Size = UDim2.fromOffset(LW, LH)
	logo.ZIndex = 3
	logo.Parent = root
	local word = label(logo, "Word", "DVD", 0, 0, LW, LH * 0.6, math.floor(LH * 0.56), DVD_COLORS[1], FONT_BLACK, 4)
	word.TextXAlignment = Enum.TextXAlignment.Center
	local disc = box(logo, "Disc", LW * 0.08, LH * 0.62, LW * 0.84, LH * 0.34, DVD_COLORS[1], 4)
	round(disc)
	local video = label(disc, "Video", "VIDEO", 0, 0, LW * 0.84, LH * 0.34, math.floor(LH * 0.2), rgb(6, 6, 12), FONT_BLACK, 5)
	video.TextXAlignment = Enum.TextXAlignment.Center
	local glow = box(root, "Glow", 0, 0, LW + 16, LH + 16, DVD_COLORS[1], 2, 0.85)
	round(glow, 12)
	-- affichage "lecteur" + fête des coins
	local osd = label(root, "OSD", "▶ PLAY", 8, H - 18, 120, 14, 10, rgb(120, 255, 140), FONT_BOLD, 6)
	osd.TextTransparency = 0.3
	local corner = label(root, "Corner", Locale.T("CORNER!!! 🎉"), 0, H * 0.38, W, H * 0.24, math.floor(H * 0.16), rgb(255, 230, 90), FONT_BLACK, 8)
	corner.TextXAlignment = Enum.TextXAlignment.Center
	stroke(corner, rgb(200, 40, 120), 0)
	corner.Visible = false
	local x, y = random:NextNumber(0, W - LW), random:NextNumber(0, H - LH)
	local vx, vy = W * 0.2 * (random:NextNumber() < 0.5 and -1 or 1), H * 0.24 * (random:NextNumber() < 0.5 and -1 or 1)
	local colorIndex = 1
	local flash = 0
	local party = 0
	local played = random:NextInteger(0, 3000)
	local screen = {} :: Screen
	screen.Kind = "DVD"
	screen.Root = root
	local function setColor(index: number)
		local color = DVD_COLORS[index]
		word.TextColor3 = color
		disc.BackgroundColor3 = color
		glow.BackgroundColor3 = color
	end
	function screen.Step(_self: Screen, dt: number)
		x += vx * dt
		y += vy * dt
		local hitX, hitY = false, false
		if x <= 0 then
			x, vx, hitX = 0, math.abs(vx), true
		elseif x >= W - LW then
			x, vx, hitX = W - LW, -math.abs(vx), true
		end
		if y <= 0 then
			y, vy, hitY = 0, math.abs(vy), true
		elseif y >= H - LH then
			y, vy, hitY = H - LH, -math.abs(vy), true
		end
		if hitX or hitY then
			colorIndex = colorIndex % #DVD_COLORS + 1
			setColor(colorIndex)
			flash = 0.3
			-- presque dans le coin : on fête quand même (c'est le moment attendu)
			local nearX = x < LW * 0.12 or x > W - LW * 1.12
			local nearY = y < LH * 0.12 or y > H - LH * 1.12
			if (hitX and hitY) or (hitX and nearY) or (hitY and nearX) then
				party = 1.8
			end
		end
		logo.Position = UDim2.fromOffset(x, y)
		glow.Position = UDim2.fromOffset(x - 8, y - 8)
		if flash > 0 then
			flash -= dt
		end
		glow.BackgroundTransparency = 0.85 - math.max(0, flash) * 1.5
		if party > 0 then
			party -= dt
			corner.Visible = true
			corner.TextColor3 = Color3.fromHSV((party * 1.5) % 1, 0.6, 1)
			corner.Rotation = math.sin(party * 12) * 4
		else
			corner.Visible = false
		end
		played += dt
		osd.Text = string.format("▶ PLAY  %02d:%02d", math.floor(played / 60) % 60, math.floor(played) % 60)
	end
	function screen.Destroy(_self: Screen)
		root:Destroy()
	end
	setColor(colorIndex)
	return screen
end

----------------------------------------------------------------------
-- 📰 NEWS : flash info
----------------------------------------------------------------------

local HEADLINES = {
	"LOCAL PLAYER CLICKS 10,000 TIMES, FEELS GREAT",
	"DVD LOGO FINALLY HITS THE CORNER, CROWD GOES WILD",
	"SCIENTISTS CONFIRM: BUBBLE WRAP IS STILL SATISFYING",
	"PIGEON ELECTED MAYOR, PROMISES MORE CRUMBS",
	"HYDRAULIC PRESS CRUSHES RUBBER DUCK, DUCK IS FINE",
	"WINDMILL SPINS FASTER THAN EVER, EXPERTS SAY 'WOW'",
	"DOPAMINE LEVELS AT AN ALL-TIME HIGH IN DOPAMINE TOWN",
}

local function newNews(gui: SurfaceGui, canvas: Vector2): Screen
	local W, H = canvas.X, canvas.Y
	local root = newRoot(gui, canvas, rgb(20, 40, 90))
	gradient(root, rgb(30, 70, 160), rgb(10, 20, 60), 90)
	-- décor du plateau : écrans, présentateur
	for index = 0, 3 do
		box(root, "Wall", W * (0.05 + index * 0.24), H * 0.12, W * 0.2, H * 0.3, rgb(60, 110, 200), 2, 0.4)
	end
	local anchorX = W * 0.66
	local suit = box(root, "Suit", anchorX, H * 0.44, W * 0.24, H * 0.4, rgb(40, 44, 70), 3)
	round(suit, 14)
	box(suit, "Tie", W * 0.11, 4, W * 0.02, H * 0.2, rgb(230, 50, 70), 4)
	local head = box(root, "Head", anchorX + W * 0.07, H * 0.2, W * 0.1, W * 0.1, rgb(250, 210, 180), 4)
	round(head)
	local hair = box(head, "Hair", -1, -2, W * 0.1 + 2, W * 0.035, rgb(80, 60, 50), 5)
	round(hair, 6)
	local desk = box(root, "Desk", W * 0.52, H * 0.66, W * 0.46, H * 0.1, rgb(220, 226, 240), 5)
	round(desk, 4)
	-- logo de la chaîne + direct
	local logoBox = box(root, "Logo", 8, 8, W * 0.34, H * 0.13, WHITE, 6)
	round(logoBox, 4)
	local logoText = label(logoBox, "Text", "🧠 DOPA NEWS", 6, 0, W * 0.34 - 8, H * 0.13, math.floor(H * 0.075), rgb(200, 30, 60), FONT_BLACK, 7)
	local _ = logoText
	local live = box(root, "Live", W - 52, 8, 44, 16, rgb(220, 30, 50), 6)
	round(live, 4)
	local liveText = label(live, "Text", Locale.T("LIVE"), 0, 0, 44, 16, 10, WHITE, FONT_BLACK, 7)
	liveText.TextXAlignment = Enum.TextXAlignment.Center
	-- bandeau "Breaking news" + titre
	local bandY = H * 0.62
	local breaking = box(root, "Breaking", 0, bandY, W * 0.4, H * 0.1, rgb(220, 30, 50), 8)
	local breakingText = label(breaking, "Text", Locale.T("BREAKING NEWS"), 6, 0, W * 0.4 - 8, H * 0.1, math.floor(H * 0.06), WHITE, FONT_BLACK, 9)
	local _b = breakingText
	local headlineBox = box(root, "Headline", 0, bandY + H * 0.1, W, H * 0.16, WHITE, 8)
	local headline = label(headlineBox, "Text", "", 8, 0, W - 16, H * 0.16, math.floor(H * 0.058), rgb(20, 24, 50), FONT_BLACK, 9)
	headline.TextWrapped = true
	-- bandeau défilant
	local ticker = box(root, "Ticker", 0, H - H * 0.12, W, H * 0.12, rgb(250, 200, 40), 8)
	local tickerText = label(ticker, "Text", "", 0, 0, W * 4, H * 0.12, math.floor(H * 0.06), rgb(30, 20, 20), FONT_BOLD, 9)
	local parts = {}
	for _, text in ipairs(HEADLINES) do
		table.insert(parts, Locale.T(text))
	end
	tickerText.Text = table.concat(parts, "   •   ")
	local tickerW = W * 4
	tickerText.Size = UDim2.fromOffset(tickerW, H * 0.12)
	local scroll = 0
	local index = random:NextInteger(1, #HEADLINES)
	local timer = 0
	local clock = 0
	headline.Text = Locale.T(HEADLINES[index])
	local screen = {} :: Screen
	screen.Kind = "News"
	screen.Root = root
	function screen.Step(_self: Screen, dt: number)
		clock += dt
		timer += dt
		if timer > 6 then
			timer = 0
			index = index % #HEADLINES + 1
			headline.Text = Locale.T(HEADLINES[index])
		end
		scroll = (scroll + dt * W * 0.18) % (tickerW * 0.8)
		tickerText.Position = UDim2.fromOffset(W - scroll, 0)
		live.BackgroundTransparency = (math.floor(clock * 2) % 2 == 0) and 0 or 0.35
		head.Position = UDim2.fromOffset(anchorX + W * 0.07 + math.sin(clock * 1.3) * 1.5, H * 0.2 + math.sin(clock * 3.1) * 0.8)
		breaking.BackgroundColor3 = rgb(220, 30, 50):Lerp(rgb(255, 80, 90), (math.sin(clock * 4) + 1) / 2)
	end
	function screen.Destroy(_self: Screen)
		root:Destroy()
	end
	return screen
end

----------------------------------------------------------------------
-- 🎵 MUSIC : écran LCD de la chaîne hi-fi
----------------------------------------------------------------------

local soundModule: any = nil
local function sound(): any
	if soundModule == nil then
		local ok, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("SoundManager") :: ModuleScript) :: any
		end)
		soundModule = ok and result or false
	end
	return soundModule or nil
end

local function newMusic(gui: SurfaceGui, canvas: Vector2): Screen
	local W, H = canvas.X, canvas.Y
	local root = newRoot(gui, canvas, rgb(10, 30, 40))
	gradient(root, rgb(20, 60, 70), rgb(8, 20, 30), 90)
	local title = label(root, "Track", "", 6, 2, W * 3, H * 0.5, math.floor(H * 0.34), rgb(140, 255, 220), FONT_BOLD, 3)
	local state = label(root, "State", "▶", W - 26, 2, 22, H * 0.5, math.floor(H * 0.34), rgb(140, 255, 220), FONT_BLACK, 4)
	state.TextXAlignment = Enum.TextXAlignment.Right
	local BARS = 12
	local bars = {}
	local barW = (W - 12) / BARS
	for index = 1, BARS do
		local bar = box(root, "Eq", 6 + (index - 1) * barW, H - 4, barW - 2, 4, Color3.fromHSV(0.45 - index * 0.025, 0.7, 1), 3)
		bar.AnchorPoint = Vector2.new(0, 1)
		bars[index] = bar
	end
	local scroll = 0
	local infoTimer = 0
	local playing = true
	local levels = table.create(BARS, 0.2)
	local clock = 0
	local function refresh()
		local name = Locale.T("lofi beats 🎧 to study to")
		local manager = sound()
		if manager and type(manager.GetMusicInfo) == "function" then
			local ok, info = pcall(manager.GetMusicInfo)
			if ok and type(info) == "table" then
				if type(info.Name) == "string" then
					name = info.Name
				end
				playing = info.Playing == true
			end
		end
		title.Text = "♪ " .. name .. "   ♪ " .. name
		state.Text = playing and "▶" or "❚❚"
	end
	refresh()
	local screen = {} :: Screen
	screen.Kind = "Music"
	screen.Root = root
	function screen.Step(_self: Screen, dt: number)
		clock += dt
		infoTimer += dt
		if infoTimer > 1 then
			infoTimer = 0
			refresh()
		end
		scroll = (scroll + dt * 24) % math.max(40, W * 1.2)
		title.Position = UDim2.fromOffset(6 - scroll, 2)
		for index, bar in ipairs(bars) do
			local target = playing and (0.25 + 0.75 * math.abs(math.sin(clock * (2 + index * 0.37) + index))) or 0.08
			levels[index] += (target - levels[index]) * math.min(1, dt * 12)
			bar.Size = UDim2.fromOffset(barW - 2, math.max(2, levels[index] * H * 0.44))
		end
	end
	function screen.Destroy(_self: Screen)
		root:Destroy()
	end
	return screen
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

local MAKERS: { [string]: (gui: SurfaceGui, canvas: Vector2) -> Screen } = {
	Runner = newRunner,
	Live = newLive,
	DVD = newDVD,
	News = newNews,
	Music = newMusic,
}

-- Couleur "ambiante" d'un type d'écran (écran éteint au loin, bords incurvés)
LiveScreens.Tints = {
	Runner = rgb(110, 170, 255),
	Live = rgb(200, 100, 220),
	DVD = rgb(30, 30, 60),
	News = rgb(60, 110, 220),
	Music = rgb(60, 200, 170),
}

function LiveScreens.Has(kind: string): boolean
	return MAKERS[kind] ~= nil
end

function LiveScreens.New(kind: string, gui: SurfaceGui, canvas: Vector2): Screen
	local maker = MAKERS[kind] or newDVD
	return maker(gui, canvas)
end

return LiveScreens
