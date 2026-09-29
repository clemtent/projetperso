--[[
	DeskGames (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DeskGames

	v9.8 🎮 "Desk Runner" : quand on s'assoit au bureau gamer (DeskMode), le
	GRAND écran du bureau devient un vrai jeu de course façon Subway,
	JOUABLE :
	  - 3 voies ; ← → (ou A / D, Q) pour changer de voie, ↑ / Espace / W / Z
	    pour sauter, ↓ / S pour rouler ; glisser le doigt sur téléphone ;
	  - trains (on change de voie), barrières basses (on saute), portiques
	    (on roule dessous), pièces ; la vitesse augmente ;
	  - score (distance + 10 x pièces), record, écran de fin, on rejoue ;
	  - récompense : la partie passe par l'arcade (jeu solo caché
	    "DeskRunner" : graine du serveur, le serveur REJOUE la partie, mêmes
	    plafonds du jour que les autres jeux). Sans arcade débloquée : score
	    seulement.
	La simulation est Shared > DeskRunnerLogic (la même que le serveur) ; ce
	module la fait tourner à pas fixe et la DESSINE dans la toile de l'écran
	(LiveProps.SetOverride), avec des cadres créés une fois puis recyclés :
	ciel, ville en parallaxe, voies en perspective (ballast, traverses qui
	défilent, rails, murets), trains (face avant, toit, flanc), barrières,
	portiques, pièces qui tournent, coureur animé (course, saut, roulade,
	chute), ombre, HUD, compte à rebours, écran de fin.
	Aucun son n'est ajouté.

	API (appelée par DeskMode) :
	  DeskGames.Start(deskHandle) -> boolean     (prend le grand écran)
	  DeskGames.Stop()                           (rend l'écran)
	  DeskGames.IsRunning() -> boolean
	  DeskGames.Input(action)                    (1 gauche, 2 droite, 3 saut, 4 roulade)
	  DeskGames.Screen() -> ScreenRec?           (l'écran pris)
	  DeskGames.State() -> { Phase, Score, Coins, Best, ... }   (tests)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Logic = require(ReplicatedStorage.Shared.DeskRunnerLogic)
local LiveProps = require(script.Parent.LiveProps)

local DeskGames = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local FONT_BLACK = Enum.Font.GothamBlack
local FONT_BOLD = Enum.Font.GothamBold

local TICK = Logic.TICK
local LANE_W = 2.2 -- (m) écart entre deux voies
local CAM_BACK = 4 -- (m) caméra derrière le coureur
local CAM_H = 3.1 -- (m) hauteur de la caméra
local FAR = 90 -- (m) rien n'est dessiné au-delà
local SLEEPER_GAP = 1.25
local SLEEPERS = 26
local TRAIN_H = 2.3
local TRAIN_W = 1.9
local COUNTDOWN = 2.4
local POOL = { Train = 6, Bar = 8, Coin = 18, Pop = 4 }

----------------------------------------------------------------------
-- Réseau (arcade) : jamais bloquant
----------------------------------------------------------------------

local netModule: any = nil
local function arcade(): RemoteFunction?
	if netModule == nil then
		local ok, result = pcall(require, ReplicatedStorage.Shared.Net)
		netModule = ok and result or false
	end
	if not netModule then
		return nil
	end
	local ok, remote = pcall(function()
		return netModule.Function("Arcade")
	end)
	return ok and remote or nil
end

----------------------------------------------------------------------
-- État du jeu (indépendant de la toile : survit à une reconstruction)
----------------------------------------------------------------------

type Game = {
	Phase: string, -- "Title" | "Countdown" | "Play" | "Crash" | "Over"
	PhaseTime: number,
	Sim: Logic.State?,
	Seed: number,
	Token: any,
	Ranked: boolean,
	Waiting: boolean, -- réponse du serveur attendue (début de partie)
	Inputs: { number },
	Queue: { number },
	Acc: number,
	LaneX: number,
	Best: number,
	Result: { [string]: any }?,
	ResultText: string,
	Clock: number,
	Coins: number,
	Popups: number,
	Shake: number,
	Note: string,
}

local game_: Game = {
	Phase = "Title",
	PhaseTime = 0,
	Sim = nil,
	Seed = 1,
	Token = nil,
	Ranked = false,
	Waiting = false,
	Inputs = {},
	Queue = {},
	Acc = 0,
	LaneX = 0,
	Best = 0,
	Result = nil,
	ResultText = "",
	Clock = 0,
	Coins = 0,
	Popups = 0,
	Shake = 0,
	Note = "",
}

local desk: any = nil
local screenRec: any = nil
local view: any = nil -- dessin courant (voir buildView)
local heartbeat: RBXScriptConnection? = nil
local serial = 0 -- (réponses du serveur d'une ancienne partie ignorées)

----------------------------------------------------------------------
-- Dessin : petits outils
----------------------------------------------------------------------

local function frame(parent: Instance, name: string, color: Color3, z: number, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function corner(parent: GuiObject, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(1, 0)
	c.Parent = parent
end

local function grad(parent: GuiObject, a: Color3, b: Color3, rotation: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation
	g.Parent = parent
	return g
end

local function text(parent: Instance, name: string, value: string, size: number, color: Color3, z: number, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = font or FONT_BLACK
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeColor3 = rgb(30, 16, 50)
	l.TextStrokeTransparency = 0.35
	l.Text = value
	l.ZIndex = z
	l.Parent = parent
	return l
end

local function place(f: GuiObject, x: number, y: number, w: number, h: number)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
end

-- Trait (cadre tourné) de (x0, y0) à (x1, y1)
local function segment(f: GuiObject, x0: number, y0: number, x1: number, y1: number, thickness: number)
	local dx, dy = x1 - x0, y1 - y0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
	f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), thickness)
	f.Rotation = math.deg(math.atan2(dy, dx))
end

local function formatInt(value: number): string
	local digits = tostring(math.floor(value))
	local out = digits:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

----------------------------------------------------------------------
-- La vue (construite dans la toile de l'écran)
----------------------------------------------------------------------

local function buildView(gui: SurfaceGui, canvas: Vector2): any
	local W, H = canvas.X, canvas.Y
	local v: any = { W = W, H = H }
	local root = frame(gui, "DeskRunner", rgb(120, 180, 255), 1)
	place(root, 0, 0, W, H)
	root.ClipsDescendants = true
	v.Root = root
	-- projection
	local F = W * 0.5
	local HY = H - F * CAM_H / CAM_BACK - H * 0.06
	v.F, v.HY, v.CX = F, HY, W / 2
	v.CamX = 0
	function v.Project(x: number, y: number, z: number): (number, number, number)
		local d = math.max(0.35, z + CAM_BACK)
		return v.CX + F * (x - v.CamX) / d, HY + F * (CAM_H - y) / d, F / d
	end
	-- ciel : dégradé, soleil, nuages
	local sky = frame(root, "Sky", WHITE, 1)
	place(sky, 0, 0, W, HY + 2)
	grad(sky, rgb(98, 162, 255), rgb(255, 206, 222), 90)
	local sun = frame(root, "Sun", rgb(255, 238, 150), 2)
	place(sun, W * 0.74, HY * 0.18, H * 0.16, H * 0.16)
	corner(sun)
	local glow = frame(root, "SunGlow", rgb(255, 238, 150), 2, 0.75)
	place(glow, W * 0.74 - H * 0.06, HY * 0.18 - H * 0.06, H * 0.28, H * 0.28)
	corner(glow)
	v.Clouds = {}
	for index = 1, 4 do
		local cloud = frame(root, "Cloud", WHITE, 3, 0.1)
		place(cloud, 0, HY * (0.12 + (index % 3) * 0.12), H * (0.2 + (index % 2) * 0.08), H * 0.06)
		corner(cloud)
		local puff = frame(cloud, "Puff", WHITE, 3)
		puff.AnchorPoint = Vector2.new(0.5, 1)
		puff.Position = UDim2.fromScale(0.45, 0.4)
		puff.Size = UDim2.fromScale(0.5, 1.3)
		corner(puff)
		table.insert(v.Clouds, { Frame = cloud, X = W * index / 4, Speed = 4 + index * 2 })
	end
	-- ville en parallaxe (deux plans)
	v.Skyline = {}
	for layer = 1, 2 do
		local count = layer == 1 and 12 or 9
		for index = 1, count do
			local h = H * (layer == 1 and (0.08 + (index * 37 % 7) * 0.018) or (0.12 + (index * 53 % 5) * 0.03))
			local w = W * (layer == 1 and 0.09 or 0.12)
			local color = layer == 1 and rgb(170, 160, 214) or rgb(120, 104, 170)
			local building = frame(root, "Building", color, 3 + layer)
			local x = (index - 1) * W * 1.25 / count - W * 0.1
			place(building, x, HY - h, w, h + 2)
			if layer == 2 then
				for row = 0, math.floor(h / 9) - 1 do
					local windows = frame(building, "Windows", rgb(255, 230, 160), 6, 0.45)
					place(windows, 3, 4 + row * 9, w - 6, 3)
				end
				local roof = frame(building, "Roof", rgb(96, 84, 150), 6)
				place(roof, -1, 0, w + 2, 3)
			end
			table.insert(v.Skyline, { Frame = building, X = x, Layer = layer })
		end
	end
	-- sol (talus + ballast en bandes) : trapèze des 3 voies + bas-côtés
	local ground = frame(root, "Ground", rgb(122, 150, 96), 6)
	place(ground, 0, HY, W, H - HY)
	grad(ground, rgb(150, 176, 110), rgb(96, 128, 76), 90)
	v.Bands = {}
	local BANDS = 18
	for index = 1, BANDS do
		local band = frame(root, "Ballast", rgb(150, 134, 128), 7)
		local z0 = FAR * ((index - 1) / BANDS) ^ 2 - 2.2
		local z1 = FAR * (index / BANDS) ^ 2 - 2.2
		v.Bands[index] = { Frame = band, Z0 = z0, Z1 = z1 }
	end
	-- lits de voie (plus sombres) sous chaque voie
	v.Beds = {}
	for lane = -1, 1 do
		for index = 1, 10 do
			local bed = frame(root, "Bed", rgb(104, 92, 92), 8)
			local z0 = FAR * ((index - 1) / 10) ^ 2 - 2.2
			local z1 = FAR * (index / 10) ^ 2 - 2.2
			table.insert(v.Beds, { Frame = bed, Lane = lane, Z0 = z0, Z1 = z1 })
		end
	end
	-- traverses qui défilent
	v.Sleepers = {}
	for index = 1, SLEEPERS do
		local sleeper = frame(root, "Sleeper", rgb(122, 84, 60), 9)
		table.insert(v.Sleepers, sleeper)
		local _ = index
	end
	-- rails (droites qui filent vers l'horizon) + murets de chaque côté
	v.Rails = {}
	for lane = -1, 1 do
		for _, side in ipairs({ -1, 1 }) do
			local rail = frame(root, "Rail", rgb(226, 228, 240), 10)
			table.insert(v.Rails, { Frame = rail, X = lane * LANE_W + side * 0.55 })
		end
	end
	v.Walls = {}
	for _, side in ipairs({ -1, 1 }) do
		local wall = frame(root, "WallTop", rgb(255, 150, 196), 11)
		local face = frame(root, "WallFace", rgb(236, 120, 170), 10)
		table.insert(v.Walls, { Top = wall, Face = face, X = side * (LANE_W * 1.5 + 0.7) })
	end
	-- trains (face avant + toit + flanc en bandes verticales)
	v.Trains = {}
	for index = 1, POOL.Train do
		local body = frame(root, "Train", rgb(236, 74, 96), 20)
		body.AnchorPoint = Vector2.new(0.5, 1)
		corner(body, UDim.new(0.08, 0))
		local windshield = frame(body, "Windshield", rgb(170, 222, 255), 21)
		windshield.Position = UDim2.fromScale(0.1, 0.1)
		windshield.Size = UDim2.fromScale(0.8, 0.32)
		corner(windshield, UDim.new(0.18, 0))
		local shine = frame(windshield, "Shine", WHITE, 22, 0.55)
		shine.Position = UDim2.fromScale(0.08, 0.12)
		shine.Size = UDim2.fromScale(0.3, 0.18)
		corner(shine)
		local stripe = frame(body, "Stripe", rgb(255, 222, 110), 21)
		stripe.Position = UDim2.fromScale(0, 0.56)
		stripe.Size = UDim2.fromScale(1, 0.08)
		local sign = text(body, "Sign", "DOPA", 12, rgb(255, 240, 150), 22)
		sign.TextStrokeTransparency = 1
		sign.Position = UDim2.fromScale(0.2, 0.44)
		sign.Size = UDim2.fromScale(0.6, 0.1)
		sign.TextScaled = true
		local lamps = {}
		for _, lx in ipairs({ 0.12, 0.72 }) do
			local lamp = frame(body, "Lamp", rgb(255, 250, 210), 22)
			lamp.Position = UDim2.fromScale(lx, 0.72)
			lamp.Size = UDim2.fromScale(0.16, 0.1)
			corner(lamp)
			table.insert(lamps, lamp)
		end
		local bumper = frame(body, "Bumper", rgb(60, 56, 70), 21)
		bumper.Position = UDim2.fromScale(0.04, 0.9)
		bumper.Size = UDim2.fromScale(0.92, 0.08)
		local roof = frame(root, "Roof", rgb(190, 60, 82), 19)
		local sides = {}
		for k = 1, 6 do
			local strip = frame(root, "TrainSide", rgb(196, 58, 80), 19)
			strip.AnchorPoint = Vector2.new(0.5, 1)
			table.insert(sides, strip)
		end
		table.insert(v.Trains, { Body = body, Roof = roof, Sides = sides })
		local _ = index
	end
	-- barrières basses (rayées) et portiques hauts
	v.Bars = {}
	for index = 1, POOL.Bar do
		local holder = frame(root, "Barrier", BLACK, 20, 1)
		holder.AnchorPoint = Vector2.new(0.5, 1)
		local plank = frame(holder, "Plank", WHITE, 22)
		local stripes = Instance.new("UIGradient")
		local keypoints = {}
		for i = 1, 8 do
			local color = i % 2 == 1 and rgb(236, 50, 70) or WHITE
			table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / 8, color))
			table.insert(keypoints, ColorSequenceKeypoint.new(math.min(1, i / 8 - 0.002), color))
		end
		keypoints[#keypoints] = ColorSequenceKeypoint.new(1, WHITE)
		stripes.Color = ColorSequence.new(keypoints)
		stripes.Rotation = 20
		stripes.Parent = plank
		local legs = {}
		for _, lx in ipairs({ 0.08, 0.84 }) do
			local leg = frame(holder, "Leg", rgb(70, 70, 86), 21)
			table.insert(legs, { Frame = leg, X = lx })
		end
		local signBox = frame(holder, "Sign", rgb(255, 214, 60), 23)
		corner(signBox, UDim.new(0.2, 0))
		local sign = text(signBox, "Text", "⚠", 12, rgb(60, 40, 10), 24, FONT_BLACK)
		sign.TextStrokeTransparency = 1
		sign.Size = UDim2.fromScale(1, 1)
		sign.TextScaled = true
		table.insert(v.Bars, { Holder = holder, Plank = plank, Legs = legs, Sign = signBox })
		local _ = index
	end
	-- pièces
	v.Coins = {}
	for index = 1, POOL.Coin do
		local coin = frame(root, "Coin", rgb(255, 208, 50), 25)
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		corner(coin)
		local stroke = Instance.new("UIStroke")
		stroke.Color = rgb(214, 140, 20)
		stroke.Thickness = 1.5
		stroke.Parent = coin
		local inner = frame(coin, "Inner", rgb(255, 234, 120), 26)
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.fromScale(0.52, 0.52)
		corner(inner)
		table.insert(v.Coins, coin)
		local _ = index
	end
	-- ombre + coureur (vu de dos)
	local shadow = frame(root, "Shadow", BLACK, 60, 0.62)
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(shadow)
	v.Shadow = shadow
	local runner = frame(root, "Runner", BLACK, 61, 1)
	runner.AnchorPoint = Vector2.new(0.5, 1)
	v.Runner = runner
	local function part(name: string, color: Color3, z: number, round: boolean?): Frame
		local p = frame(runner, name, color, z)
		p.AnchorPoint = Vector2.new(0.5, 0)
		if round then
			corner(p)
		end
		return p
	end
	v.LegL = part("LegL", rgb(54, 64, 130), 42)
	v.LegR = part("LegR", rgb(54, 64, 130), 42)
	v.ShoeL = part("ShoeL", rgb(255, 92, 150), 43, true)
	v.ShoeR = part("ShoeR", rgb(255, 92, 150), 43, true)
	v.ArmL = part("ArmL", rgb(255, 150, 70), 42)
	v.ArmR = part("ArmR", rgb(255, 150, 70), 42)
	v.Body = part("Body", rgb(255, 140, 60), 44)
	corner(v.Body, UDim.new(0.3, 0))
	v.Pack = part("Pack", rgb(80, 206, 170), 45)
	corner(v.Pack, UDim.new(0.25, 0))
	v.Head = part("Head", rgb(120, 70, 50), 46, true) -- (cheveux, vu de dos)
	v.Cap = part("Cap", rgb(60, 140, 255), 47)
	corner(v.Cap, UDim.new(0.5, 0))
	v.Ball = part("Ball", rgb(255, 140, 60), 44, true) -- (roulade)
	-- éclats "+1" des pièces
	v.Pops = {}
	for index = 1, POOL.Pop do
		local pop = text(root, "Pop", "+1", math.floor(H * 0.06), rgb(255, 230, 90), 75)
		pop.AnchorPoint = Vector2.new(0.5, 0.5)
		pop.Size = UDim2.fromOffset(60, 24)
		pop.Visible = false
		table.insert(v.Pops, { Label = pop, T = 1, X = 0, Y = 0 })
		local _ = index
	end
	-- HUD
	local hud = H * 0.07
	local scoreBox = frame(root, "ScoreBox", rgb(20, 14, 40), 70, 0.35)
	place(scoreBox, 8, 8, W * 0.3, hud * 1.7)
	corner(scoreBox, UDim.new(0, 8))
	v.Score = text(scoreBox, "Score", "0", math.floor(hud * 0.95), WHITE, 71)
	v.Score.Position = UDim2.fromOffset(8, 2)
	v.Score.Size = UDim2.new(1, -16, 0.6, 0)
	v.Score.TextXAlignment = Enum.TextXAlignment.Left
	v.CoinsLabel = text(scoreBox, "Coins", "🪙 0", math.floor(hud * 0.62), rgb(255, 226, 110), 71, FONT_BOLD)
	v.CoinsLabel.Position = UDim2.new(0, 8, 0.58, 0)
	v.CoinsLabel.Size = UDim2.new(1, -16, 0.4, 0)
	v.CoinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	v.BestLabel = text(root, "Best", "", math.floor(hud * 0.6), rgb(255, 240, 200), 71, FONT_BOLD)
	v.BestLabel.AnchorPoint = Vector2.new(1, 0)
	v.BestLabel.Position = UDim2.new(1, -10, 0, 10)
	v.BestLabel.Size = UDim2.fromOffset(W * 0.4, hud)
	v.BestLabel.TextXAlignment = Enum.TextXAlignment.Right
	v.Rank = text(root, "Rank", "", math.floor(hud * 0.5), rgb(200, 255, 210), 71, FONT_BOLD)
	v.Rank.AnchorPoint = Vector2.new(1, 0)
	v.Rank.Position = UDim2.new(1, -10, 0, 10 + hud)
	v.Rank.Size = UDim2.fromOffset(W * 0.5, hud * 0.8)
	v.Rank.TextXAlignment = Enum.TextXAlignment.Right
	-- messages au centre (titre, compte à rebours, fin)
	local panel = frame(root, "Panel", rgb(24, 14, 48), 80, 0.18)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(W * 0.72, H * 0.62)
	corner(panel, UDim.new(0, 14))
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = rgb(255, 120, 200)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel
	v.Panel = panel
	v.Title = text(panel, "Title", "", math.floor(H * 0.12), WHITE, 81)
	v.Title.Position = UDim2.fromScale(0, 0.06)
	v.Title.Size = UDim2.fromScale(1, 0.26)
	v.Line1 = text(panel, "Line1", "", math.floor(H * 0.065), rgb(255, 226, 120), 81, FONT_BOLD)
	v.Line1.Position = UDim2.fromScale(0.04, 0.36)
	v.Line1.Size = UDim2.fromScale(0.92, 0.16)
	v.Line1.TextWrapped = true
	v.Line2 = text(panel, "Line2", "", math.floor(H * 0.052), rgb(200, 240, 255), 81, FONT_BOLD)
	v.Line2.Position = UDim2.fromScale(0.04, 0.54)
	v.Line2.Size = UDim2.fromScale(0.92, 0.18)
	v.Line2.TextWrapped = true
	v.Hint = text(panel, "Hint", "", math.floor(H * 0.048), rgb(236, 226, 255), 81, FONT_BOLD)
	v.Hint.Position = UDim2.fromScale(0.04, 0.76)
	v.Hint.Size = UDim2.fromScale(0.92, 0.18)
	v.Hint.TextWrapped = true
	v.Big = text(root, "Countdown", "", math.floor(H * 0.3), WHITE, 85)
	v.Big.AnchorPoint = Vector2.new(0.5, 0.5)
	v.Big.Position = UDim2.fromScale(0.5, 0.42)
	v.Big.Size = UDim2.fromOffset(W, H * 0.4)
	v.Big.TextStrokeColor3 = rgb(200, 40, 130)
	v.Big.TextStrokeTransparency = 0
	v.Controls = text(root, "Controls", "", math.floor(H * 0.045), WHITE, 71, FONT_BOLD)
	v.Controls.AnchorPoint = Vector2.new(0.5, 1)
	v.Controls.Position = UDim2.new(0.5, 0, 1, -4)
	v.Controls.Size = UDim2.fromOffset(W, H * 0.07)
	v.Flash = frame(root, "Flash", WHITE, 90, 1)
	place(v.Flash, 0, 0, W, H)
	-- mise en place des éléments fixes (rails, murets)
	for _, rail in ipairs(v.Rails) do
		local x0, y0 = v.Project(rail.X, 0, -2.2)
		local x1, y1 = v.Project(rail.X, 0, FAR)
		segment(rail.Frame, x0, y0, x1, y1, math.max(1.5, W * 0.005))
	end
	return v
end

----------------------------------------------------------------------
-- Rendu d'une image
----------------------------------------------------------------------

local function showOnly(list: { any }, used: number, field: string?)
	for index = used + 1, #list do
		local item = list[index]
		local f = field and item[field] or item
		if f.Visible then
			f.Visible = false
		end
	end
end

local function render(v: any, dt: number)
	local g = game_
	local s = g.Sim
	local W, H = v.W, v.H
	g.Clock += dt
	local distance = s and (s.Distance + s.Speed * g.Acc) or g.Clock * 6
	local laneTarget = s and s.Lane or 0
	g.LaneX += (laneTarget * LANE_W - g.LaneX) * math.min(1, dt * 16)
	v.CamX = g.LaneX * 0.35
	local shake = g.Shake > 0 and (math.random() - 0.5) * g.Shake * W * 0.02 or 0
	v.Root.Position = UDim2.fromOffset(shake, 0)
	g.Shake = math.max(0, g.Shake - dt * 2.5)
	-- nuages / ville (parallaxe)
	for _, cloud in ipairs(v.Clouds) do
		cloud.X = (cloud.X - cloud.Speed * dt) % (W * 1.3)
		cloud.Frame.Position = UDim2.fromOffset(cloud.X - W * 0.15, cloud.Frame.Position.Y.Offset)
	end
	for _, building in ipairs(v.Skyline) do
		local px = building.X - v.CamX * (building.Layer == 1 and 6 or 12)
		building.Frame.Position = UDim2.fromOffset(px, building.Frame.Position.Y.Offset)
	end
	-- ballast + lits de voie (bandes : trapèzes)
	for _, band in ipairs(v.Bands) do
		local xl, y0 = v.Project(-LANE_W * 1.5 - 0.7, 0, band.Z1)
		local xr = v.Project(LANE_W * 1.5 + 0.7, 0, band.Z1)
		local _, y1 = v.Project(0, 0, band.Z0)
		place(band.Frame, xl, y0, xr - xl, y1 - y0 + 1)
	end
	for _, bed in ipairs(v.Beds) do
		local xl, y0 = v.Project(bed.Lane * LANE_W - 0.9, 0, bed.Z1)
		local xr = v.Project(bed.Lane * LANE_W + 0.9, 0, bed.Z1)
		local _, y1 = v.Project(0, 0, bed.Z0)
		place(bed.Frame, xl, y0, xr - xl, y1 - y0 + 1)
	end
	-- traverses
	local phase = distance % SLEEPER_GAP
	for index, sleeper in ipairs(v.Sleepers) do
		local z = (index - 1) * SLEEPER_GAP - phase - 1.6
		local xl, y = v.Project(-LANE_W * 1.5 - 0.3, 0, z)
		local xr, _, scale = v.Project(LANE_W * 1.5 + 0.3, 0, z)
		place(sleeper, xl, y - scale * 0.12, xr - xl, math.max(1, scale * 0.16))
		sleeper.BackgroundTransparency = math.clamp((z - 20) / 12, 0, 0.8)
	end
	-- rails et murets (suivent la caméra)
	for _, rail in ipairs(v.Rails) do
		local x0, y0 = v.Project(rail.X, 0, -2.2)
		local x1, y1 = v.Project(rail.X, 0, FAR)
		segment(rail.Frame, x0, y0, x1, y1, math.max(1.5, W * 0.005))
	end
	for _, wall in ipairs(v.Walls) do
		local x0, y0 = v.Project(wall.X, 0.9, -2.2)
		local x1, y1 = v.Project(wall.X, 0.9, FAR)
		segment(wall.Top, x0, y0, x1, y1, math.max(2, W * 0.012))
		local fx0, fy0 = v.Project(wall.X, 0.45, -2.2)
		local fx1, fy1 = v.Project(wall.X, 0.45, FAR)
		segment(wall.Face, fx0, fy0, fx1, fy1, math.max(3, W * 0.05))
	end
	-- obstacles
	local trains, bars, coins = 0, 0, 0
	if s then
		for _, o in ipairs(s.Obstacles) do
			local z = o.P - distance
			if z < FAR and z + o.Len > -CAM_BACK + 0.6 then
				local x = o.Lane * LANE_W
				-- (plus proche = au-dessus ; le coureur est entre ce qui est devant et derrière lui)
				local depthZ = z < 0 and 64 or (30 + math.clamp(math.floor((FAR - z) / FAR * 26), 0, 26))
				if o.Kind == "Train" and trains < #v.Trains then
					trains += 1
					local t = v.Trains[trains]
					local zf = math.max(z, -CAM_BACK + 0.8)
					local cx, by, scale = v.Project(x, 0, zf)
					local visibleFront = z > -CAM_BACK + 0.8
					t.Body.Visible = visibleFront
					if visibleFront then
						t.Body.Position = UDim2.fromOffset(cx, by)
						t.Body.Size = UDim2.fromOffset(TRAIN_W * scale, TRAIN_H * scale)
						t.Body.ZIndex = depthZ + 2
					end
					-- toit (du nez à l'arrière)
					local zb = z + o.Len
					local rx0, ry0, s0 = v.Project(x, TRAIN_H, zf)
					local rx1, ry1, s1 = v.Project(x, TRAIN_H, zb)
					t.Roof.Visible = true
					place(t.Roof, math.min(rx0 - TRAIN_W * s0 / 2, rx1 - TRAIN_W * s1 / 2), ry1, math.max(rx0 + TRAIN_W * s0 / 2, rx1 + TRAIN_W * s1 / 2) - math.min(rx0 - TRAIN_W * s0 / 2, rx1 - TRAIN_W * s1 / 2), math.max(1, ry0 - ry1))
					t.Roof.ZIndex = depthZ
					-- flanc (côté de la voie centrale) en 6 bandes
					local side = o.Lane == 0 and 0 or -o.Lane
					for k, strip in ipairs(t.Sides) do
						if side == 0 then
							strip.Visible = false
						else
							local za = zf + (zb - zf) * (k - 1) / #t.Sides
							local zc = zf + (zb - zf) * k / #t.Sides
							local ax, ay, sa = v.Project(x + side * TRAIN_W / 2, 0, za)
							local bx = v.Project(x + side * TRAIN_W / 2, 0, zc)
							strip.Visible = true
							strip.Position = UDim2.fromOffset((ax + bx) / 2, ay)
							strip.Size = UDim2.fromOffset(math.max(1, math.abs(bx - ax) + 1), TRAIN_H * sa)
							strip.BackgroundColor3 = rgb(196, 58, 80):Lerp(rgb(120, 40, 64), (k - 1) / #t.Sides)
							strip.ZIndex = depthZ + 1
						end
					end
				elseif (o.Kind == "Low" or o.Kind == "High") and bars < #v.Bars then
					bars += 1
					local b = v.Bars[bars]
					local cx, by, scale = v.Project(x, 0, math.max(z, -CAM_BACK + 0.8))
					local high = o.Kind == "High"
					local w, h = 1.9 * scale, (high and 2.1 or 0.8) * scale
					b.Holder.Visible = true
					b.Holder.Position = UDim2.fromOffset(cx, by)
					b.Holder.Size = UDim2.fromOffset(w, h)
					b.Holder.ZIndex = depthZ + 2
					local plankH = high and 0.26 or 0.42
					b.Plank.Position = UDim2.fromScale(0, high and 0 or 0.12)
					b.Plank.Size = UDim2.fromScale(1, plankH)
					b.Plank.ZIndex = depthZ + 4
					for _, leg in ipairs(b.Legs) do
						leg.Frame.Position = UDim2.fromScale(leg.X, high and 0.2 or 0.5)
						leg.Frame.Size = UDim2.fromScale(0.08, high and 0.8 or 0.5)
						leg.Frame.ZIndex = depthZ + 3
					end
					b.Sign.Visible = high
					b.Sign.Position = UDim2.fromScale(0.38, 0.02)
					b.Sign.Size = UDim2.fromScale(0.24, 0.22)
					b.Sign.ZIndex = depthZ + 5
					local label = b.Sign:FindFirstChild("Text")
					if label and label:IsA("TextLabel") then
						label.ZIndex = depthZ + 6
					end
				elseif o.Kind == "Coin" and not o.Taken and coins < #v.Coins and z > -CAM_BACK + 1 then
					coins += 1
					local c = v.Coins[coins]
					local cx, cy, scale = v.Project(x, 0.55 + o.Y, z)
					local size = 0.55 * scale
					c.Visible = true
					c.Position = UDim2.fromOffset(cx, cy)
					c.Size = UDim2.fromOffset(size * (0.35 + 0.65 * math.abs(math.cos(g.Clock * 5 + o.P))), size)
					c.ZIndex = depthZ + 3
					local inner = c:FindFirstChild("Inner")
					if inner and inner:IsA("GuiObject") then
						inner.ZIndex = depthZ + 4
					end
				end
			end
		end
	end
	for index = trains + 1, #v.Trains do
		local t = v.Trains[index]
		t.Body.Visible = false
		t.Roof.Visible = false
		for _, strip in ipairs(t.Sides) do
			strip.Visible = false
		end
	end
	showOnly(v.Bars, bars, "Holder")
	showOnly(v.Coins, coins, nil)
	-- coureur
	local height = s and Logic.Height(s) or 0
	local rolling = s ~= nil and s.RollTick > 0
	local crashed = g.Phase == "Crash" or g.Phase == "Over"
	local rx, ry, scale = v.Project(g.LaneX, height, 0)
	local gx, gy = v.Project(g.LaneX, 0, 0)
	local rw, rh = 0.9 * scale, 1.35 * scale
	v.Shadow.Position = UDim2.fromOffset(gx, gy)
	v.Shadow.Size = UDim2.fromOffset(rw * (1 - height * 0.18), rw * 0.22)
	v.Runner.Position = UDim2.fromOffset(rx, ry)
	v.Runner.Size = UDim2.fromOffset(rw, rh)
	local run = g.Clock * (s and s.Speed or 6) * 0.9
	local swing = (g.Phase == "Play" and height <= 0.01) and math.sin(run) or 0
	local airborne = height > 0.05
	v.Ball.Visible = rolling and not crashed
	for _, name in ipairs({ "LegL", "LegR", "ShoeL", "ShoeR", "ArmL", "ArmR", "Body", "Pack", "Head", "Cap" }) do
		v[name].Visible = not (rolling and not crashed)
	end
	if rolling and not crashed then
		v.Ball.Position = UDim2.fromScale(0.5, 0.45)
		v.Ball.Size = UDim2.fromScale(0.9, 0.55)
		v.Ball.Rotation = (g.Clock * 720) % 360
	else
		local tuck = airborne and 0.12 or 0
		v.Body.Position = UDim2.fromScale(0.5, 0.3 + tuck * 0.3)
		v.Body.Size = UDim2.fromScale(0.62, 0.36)
		v.Pack.Position = UDim2.fromScale(0.5, 0.33 + tuck * 0.3)
		v.Pack.Size = UDim2.fromScale(0.46, 0.26)
		v.Head.Position = UDim2.fromScale(0.5 + (crashed and 0.12 or 0), 0.04 + tuck * 0.3)
		v.Head.Size = UDim2.fromScale(0.46, 0.3)
		v.Cap.Position = UDim2.fromScale(0.5 + (crashed and 0.12 or 0), 0.02 + tuck * 0.3)
		v.Cap.Size = UDim2.fromScale(0.5, 0.12)
		local legY = 0.62 - tuck
		v.LegL.Position = UDim2.fromScale(0.36, legY)
		v.LegR.Position = UDim2.fromScale(0.64, legY)
		v.LegL.Size = UDim2.fromScale(0.2, 0.32 - tuck)
		v.LegR.Size = UDim2.fromScale(0.2, 0.32 - tuck)
		v.LegL.Rotation = swing * 28 + (airborne and -20 or 0)
		v.LegR.Rotation = -swing * 28 + (airborne and 20 or 0)
		-- (course vue de dos : les pieds montent l'un après l'autre)
		v.ShoeL.Position = UDim2.fromScale(0.36 - swing * 0.04, 0.9 - tuck - math.max(0, swing) * 0.12)
		v.ShoeR.Position = UDim2.fromScale(0.64 + swing * 0.04, 0.9 - tuck - math.max(0, -swing) * 0.12)
		v.ShoeL.Size = UDim2.fromScale(0.26, 0.1)
		v.ShoeR.Size = UDim2.fromScale(0.26, 0.1)
		local armUp = airborne and 1 or 0
		v.ArmL.Position = UDim2.fromScale(0.16, 0.32)
		v.ArmR.Position = UDim2.fromScale(0.84, 0.32)
		v.ArmL.Size = UDim2.fromScale(0.14, 0.3)
		v.ArmR.Size = UDim2.fromScale(0.14, 0.3)
		v.ArmL.Rotation = crashed and 60 or (-swing * 30 + armUp * 150)
		v.ArmR.Rotation = crashed and -60 or (swing * 30 - armUp * 150)
	end
	v.Runner.Rotation = crashed and 12 or (g.LaneX - laneTarget * LANE_W) * -6
	-- éclats "+1"
	for _, pop in ipairs(v.Pops) do
		if pop.T < 1 then
			pop.T += dt / 0.6
			pop.Label.Visible = pop.T < 1
			pop.Label.Position = UDim2.fromOffset(pop.X, pop.Y - pop.T * H * 0.12)
			pop.Label.TextTransparency = math.max(0, pop.T - 0.5) * 2
			pop.Label.TextStrokeTransparency = 0.35 + math.max(0, pop.T - 0.5)
		end
	end
	-- HUD
	local score = s and s.Score or 0
	v.Score.Text = formatInt(score)
	v.CoinsLabel.Text = "🪙 " .. formatInt(s and s.Coins or 0)
	v.BestLabel.Text = Locale.T("🏆 Best %s", formatInt(math.max(g.Best, crashed and 0 or score)))
	v.Rank.Text = g.Note
	v.Flash.BackgroundTransparency = math.min(1, 0.3 + (1 - g.Shake) * 0.7)
	-- panneaux
	local phaseName = g.Phase
	v.Panel.Visible = phaseName == "Title" or phaseName == "Over"
	v.Big.Visible = phaseName == "Countdown"
	v.Controls.Visible = phaseName == "Play" and s ~= nil and s.Tick < 150
	v.Controls.Text = Locale.T("← → change lane · ↑ jump · ↓ roll")
	if phaseName == "Title" then
		v.Title.Text = "🏃 DESK RUNNER"
		v.Line1.Text = Locale.T("Dodge the trains, grab the coins!")
		v.Line2.Text = g.Best > 0 and Locale.T("🏆 Best %s", formatInt(g.Best)) or Locale.T("← → change lane · ↑ jump · ↓ roll")
		v.Hint.Text = (math.floor(g.Clock * 2) % 2 == 0) and Locale.T("Press ↑ or Space to play") or ""
	elseif phaseName == "Countdown" then
		local left = COUNTDOWN - g.PhaseTime
		v.Big.Text = g.Waiting and left <= 0 and "…" or (left > 1.6 and "3" or (left > 0.8 and "2" or (left > 0 and "1" or "GO!")))
		v.Big.Rotation = math.sin(g.Clock * 9) * 3
	elseif phaseName == "Over" then
		v.Title.Text = Locale.T("💥 Ouch!")
		v.Line1.Text = Locale.T("Score %s · 🪙 %s", formatInt(score), formatInt(s and s.Coins or 0))
		v.Line2.Text = g.ResultText
		v.Hint.Text = g.PhaseTime > 0.8 and ((math.floor(g.Clock * 2) % 2 == 0) and Locale.T("Press ↑ or Space to play again") or "") or ""
	end
end

----------------------------------------------------------------------
-- Déroulement d'une partie
----------------------------------------------------------------------

local function setPhase(phase: string)
	game_.Phase = phase
	game_.PhaseTime = 0
end

local function popCoin()
	local v = view
	if not v then
		return
	end
	for _, pop in ipairs(v.Pops) do
		if pop.T >= 1 then
			local x, y = v.Project(game_.LaneX, 1.9, 0)
			pop.T = 0
			pop.X, pop.Y = x, y
			pop.Label.Text = "+" .. tostring(Logic.COIN_POINTS)
			return
		end
	end
end

local function resultText(result: { [string]: any }): string
	if result.Rejected then
		return Locale.T("Score only (no reward for this run)")
	end
	local parts = {}
	local stars = tonumber(result.Stars) or 0
	table.insert(parts, string.rep("⭐", stars) .. string.rep("☆", 3 - stars))
	if (tonumber(result.Tickets) or 0) > 0 then
		table.insert(parts, "+" .. tostring(result.Tickets) .. " 🎟️")
	end
	if (tonumber(result.Trophies) or 0) > 0 then
		table.insert(parts, "+" .. tostring(result.Trophies) .. " 🏆")
	end
	if (tonumber(result.Dopamine) or 0) > 0 then
		local ok, formatter = pcall(require, ReplicatedStorage.Shared.NumberFormatter)
		local amount = ok and formatter.Format(result.Dopamine) or tostring(math.floor(result.Dopamine))
		table.insert(parts, "+" .. amount .. " 🧠")
	end
	if result.Capped then
		table.insert(parts, Locale.T("(daily rewards reached)"))
	elseif stars == 0 then
		table.insert(parts, Locale.T("Reach %s for a reward", formatInt(Logic.Rules.Thresholds[1])))
	end
	return table.concat(parts, "   ")
end

local function beginCountdown()
	local g = game_
	serial += 1
	local mine = serial
	g.Sim = nil
	g.Result = nil
	g.ResultText = ""
	g.Inputs = {}
	g.Queue = {}
	g.Acc = 0
	g.Token = nil
	g.Ranked = false
	g.Waiting = true
	g.Seed = math.random(1, 2147483646)
	g.Note = ""
	setPhase("Countdown")
	local remote = arcade()
	if not remote then
		g.Waiting = false
		g.Note = Locale.T("Score only")
		return
	end
	task.spawn(function()
		local okCall, ok, reply = pcall(function()
			return remote:InvokeServer("solo:start", { Game = "DeskRunner", Difficulty = "Normal" })
		end)
		if mine ~= serial then
			return
		end
		if okCall and ok == true and type(reply) == "table" and type(reply.Seed) == "number" then
			g.Seed = reply.Seed
			g.Token = reply.Token
			g.Ranked = true
			if type(reply.Best) == "number" then
				g.Best = math.max(g.Best, reply.Best)
			end
			g.Note = Locale.T("🎟️ Arcade rewards on")
		else
			g.Note = Locale.T("Score only")
		end
		g.Waiting = false
	end)
end

local function startRun()
	local g = game_
	g.Sim = Logic.New(g.Seed)
	g.Acc = 0
	g.LaneX = 0
	setPhase("Play")
end

local function finishRun()
	local g = game_
	local s = g.Sim
	if not s then
		return
	end
	g.Best = math.max(g.Best, s.Score)
	setPhase("Over")
	if not g.Ranked or g.Token == nil then
		g.ResultText = s.Score >= g.Best and s.Score > 0 and Locale.T("🎉 New best!") or ""
		return
	end
	g.ResultText = Locale.T("Checking your run…")
	local mine = serial
	local token = g.Token
	local inputs = table.clone(g.Inputs)
	local ticks = s.Tick
	local remote = arcade()
	task.spawn(function()
		if not remote then
			return
		end
		local okCall, ok, result = pcall(function()
			return remote:InvokeServer("solo:finish", { Token = token, Inputs = inputs, Ticks = ticks })
		end)
		if mine ~= serial then
			return
		end
		if okCall and ok == true and type(result) == "table" then
			g.Result = result
			g.ResultText = resultText(result)
			if type(result.Best) == "number" then
				g.Best = math.max(g.Best, result.Best)
			end
		else
			g.ResultText = Locale.T("Score only (no reward for this run)")
		end
	end)
end

local function onStep(dt: number)
	local g = game_
	dt = math.min(dt, 0.1)
	g.PhaseTime += dt
	if g.Phase == "Countdown" then
		if g.PhaseTime >= COUNTDOWN and (not g.Waiting or g.PhaseTime >= COUNTDOWN + 2.5) then
			if g.Waiting then
				g.Waiting = false
				g.Ranked = false
				g.Note = Locale.T("Score only")
			end
			startRun()
		end
	elseif g.Phase == "Play" then
		local s = g.Sim
		if s then
			g.Acc += dt
			local steps = 0
			while g.Acc >= TICK and steps < 6 and s.Alive do
				g.Acc -= TICK
				steps += 1
				if s.Pending == nil and #g.Queue > 0 then
					local action = table.remove(g.Queue, 1)
					if Logic.Input(s, action) and #g.Inputs < 12000 then
						table.insert(g.Inputs, s.Tick + 1)
						table.insert(g.Inputs, action)
					end
				end
				local event = Logic.Step(s)
				if event == "coin" then
					popCoin()
				elseif event == "crash" then
					g.Shake = 1
					setPhase("Crash")
					break
				end
				if s.Tick >= Logic.MAX_TICKS then
					s.Alive = false
					setPhase("Crash")
					break
				end
			end
			if g.Acc > TICK * 6 then
				g.Acc = TICK -- (image très lente : on ne rattrape pas indéfiniment)
			end
		end
	elseif g.Phase == "Crash" then
		if g.PhaseTime > 0.9 then
			finishRun()
		end
	end
	local v = view
	if v then
		local ok, err = pcall(render, v, dt)
		if not ok then
			warn("[DeskGames] " .. tostring(err))
			view = nil
		end
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

local OVERRIDE = {
	Canvas = function(aspect: number): Vector2
		local h = 280
		return Vector2.new(math.floor(h * math.clamp(aspect, 0.8, 3) + 0.5), h)
	end,
	Build = function(gui: SurfaceGui, canvas: Vector2): any
		local v = buildView(gui, canvas)
		view = v
		local screen = { Kind = "DeskRunner", Root = v.Root, Real = false, Failed = false }
		function screen.Step(_self: any, _dt: number) end -- (le jeu dessine chaque image lui-même)
		function screen.Destroy(_self: any)
			if view == v then
				view = nil
			end
			v.Root:Destroy()
		end
		return screen
	end,
}

function DeskGames.IsRunning(): boolean
	return desk ~= nil
end

function DeskGames.Screen(): any
	return screenRec
end

function DeskGames.Start(handle: any): boolean
	if type(handle) ~= "table" or not handle.Alive or handle.Kind ~= "Desk" then
		return false
	end
	if desk == handle then
		return true
	end
	DeskGames.Stop()
	local rec = LiveProps.MainScreen(handle)
	if not rec then
		return false
	end
	desk = handle
	screenRec = rec
	serial += 1
	game_.Sim = nil
	game_.Note = ""
	setPhase("Title")
	LiveProps.SetOverride(rec, OVERRIDE)
	heartbeat = RunService.RenderStepped:Connect(onStep)
	return true
end

function DeskGames.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	local rec = screenRec
	screenRec = nil
	desk = nil
	serial += 1
	if rec then
		LiveProps.SetOverride(rec, nil)
	end
	view = nil
	game_.Sim = nil
	game_.Queue = {}
	setPhase("Title")
end

-- 1 = gauche, 2 = droite, 3 = saut, 4 = roulade
function DeskGames.Input(action: number): boolean
	if not desk then
		return false
	end
	local g = game_
	if g.Phase == "Title" or (g.Phase == "Over" and g.PhaseTime > 0.8) then
		if action == 3 or action == 0 then
			beginCountdown()
			return true
		end
		return false
	end
	if g.Phase == "Play" and g.Sim and g.Sim.Alive then
		if #g.Queue < 3 then
			table.insert(g.Queue, action)
		end
		return true
	end
	return false
end

function DeskGames.State(): { [string]: any }
	local s = game_.Sim
	return {
		Phase = game_.Phase,
		Score = s and s.Score or 0,
		Coins = s and s.Coins or 0,
		Lane = s and s.Lane or 0,
		Tick = s and s.Tick or 0,
		Best = game_.Best,
		Ranked = game_.Ranked,
		Inputs = #game_.Inputs,
		ResultText = game_.ResultText,
	}
end

-- (tests) avance le jeu sans RenderStepped
function DeskGames._Step(dt: number)
	onStep(dt)
end

return DeskGames
