--[[
	Runner (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Runner

	Un petit "jeu de course infini" façon jeu mobile, qui tourne tout seul
	dans le coin en haut à gauche (slot L1, 288x190) :
	  - ciel dégradé, soleil qui rayonne, nuages et deux couches de ville
	    en parallaxe (elles glissent quand la caméra suit le coureur) ;
	  - 3 voies en perspective : rails qui filent vers le point de fuite,
	    traverses qui défilent (largeur et épaisseur selon la profondeur),
	    murs tagués, lampadaires qui passent ;
	  - trains (vitres, phares, toit) garés ou qui foncent vers nous,
	    barrières basses (saut) et hautes (roulade), pièces qui tournent
	    et brillent ;
	  - le coureur (sweat à capuche, casquette à l'envers, sac à dos) court,
	    change de voie en se penchant, saute, roule, ramasse les pièces
	    (étincelles + "+1") ;
	  - de temps en temps un bonus : aimant 🧲 (les pièces viennent à lui)
	    ou jetpack 🚀 (il s'envole au-dessus des trains, lignes de vitesse).
	Tout est dessiné avec des Frames créées une seule fois puis recyclées
	(~180 objets, aucune création pendant la partie). Purement visuel :
	aucun appel serveur. Toutes les tailles dérivent de la taille du cadre.
]]

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Runner = {}
Runner.Slot = "L1"

----------------------------------------------------------------------
-- Réglages. Unités "monde" : 1 unité = 1 pixel à la profondeur z = 1
-- pour un écran de 280 px de large (tout est ensuite mis à l'échelle).
----------------------------------------------------------------------
local DESIGN_W = 280
local BEZEL = 4 -- bord du "téléphone"
local Z_NEAR = 0.6 -- en dessous : l'objet est passé derrière la caméra
local Z_FAR = 10 -- apparition au loin
local CHAR_Z = 1.45 -- profondeur du coureur
local LANES = { -80, 0, 80 } -- centre des 3 voies
local RAIL_OFFSET = 22 -- écart des rails autour du centre d'une voie
local TRACK_HALF = 122 -- demi-largeur du ballast
local WALL_X = 172 -- murs
local WALL_H = 70
local TIE_PER_LANE = 7 -- traverses par voie
local TIE_GAP = 0.6
local TIE_START = 0.62
local TIE_DEPTH = 0.1
local TIE_HALF = 30
local POLE_X = 146 -- lampadaires
local POLE_H = 96
local POLE_ARM = 24
local POLE_PER_SIDE = 2
local POLE_GAP = 2.7
local PANEL_LEN = 1.1 -- longueur (en profondeur) d'un graffiti
local TRAIN_W = 64
local TRAIN_H = 82
local TRAIN_LEN = 1.5
local ONCOMING_EXTRA = 2.4 -- vitesse en plus d'un train qui fonce vers nous
local BARRIER_W = 60
local COIN_SIZE = 22
local COIN_H = 22 -- hauteur du centre d'une pièce
local CHAR_W = 42
local CHAR_H = 62
local JUMP_TIME = 0.55
local JUMP_H = 44
local ROLL_TIME = 0.55
local JET_H = 100
local JET_TIME = 6.5
local MAGNET_TIME = 8
local BASE_SPEED = 3.3 -- profondeur parcourue par seconde
local MAX_SPEED = 4.8
local SPEED_RAMP = 0.02
local WAVE_GAP = 3.4 -- distance entre deux vagues d'obstacles
local BIG = 900 -- taille des demi-plans (murs, sol)

local TRAIN_POOL = 3
local BARRIER_POOL = 3
local COIN_POOL = 12
local SPARKLE_POOL = 5
local POP_POOL = 3
local SPEEDLINE_POOL = 5

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 208, 40)

local TRAIN_COLORS = {
	Color3.fromRGB(236, 64, 82),
	Color3.fromRGB(40, 132, 236),
	Color3.fromRGB(255, 184, 28),
	Color3.fromRGB(34, 186, 122),
	Color3.fromRGB(150, 82, 232),
}

-- Côtés de la voie : murs colorés avec une bande "tag"
local SIDE_DEFS = {
	{ Sign = -1, Wall = Color3.fromRGB(255, 142, 104), Stripe = Color3.fromRGB(255, 64, 150), Lower = Color3.fromRGB(226, 112, 82) },
	{ Sign = 1, Wall = Color3.fromRGB(128, 146, 246), Stripe = Color3.fromRGB(0, 212, 226), Lower = Color3.fromRGB(100, 116, 214) },
}
local GROUND_COLOR = Color3.fromRGB(212, 196, 172)
local BED_COLOR = Color3.fromRGB(128, 114, 108)

local GRAFFITI_WORDS = {
	en = { "DOPA", "WOW", "GG", "LOL", "YOLO", "RUN", "+1", "OMG", "EZ", "POG", "FAST", "GO!" },
	fr = { "DOPA", "WOW", "GG", "LOL", "YOLO", "RUN", "+1", "OMG", "EZ", "POG", "VITE", "GO!" },
}
local GRAFFITI_COLORS = {
	{ Color3.fromRGB(255, 70, 160), Color3.fromRGB(255, 190, 40) },
	{ Color3.fromRGB(40, 210, 230), Color3.fromRGB(150, 80, 240) },
	{ Color3.fromRGB(80, 220, 110), Color3.fromRGB(0, 150, 240) },
	{ Color3.fromRGB(255, 120, 40), Color3.fromRGB(240, 40, 90) },
}

-- Couleurs du coureur
local HOODIE = Color3.fromRGB(255, 96, 60)
local HOODIE_DARK = Color3.fromRGB(214, 66, 44)
local JEANS = Color3.fromRGB(52, 76, 168)
local SKIN = Color3.fromRGB(242, 192, 150)
local HAIR = Color3.fromRGB(74, 46, 30)
local CAP = Color3.fromRGB(40, 170, 255)
local CAP_DARK = Color3.fromRGB(20, 118, 214)
local PACK = Color3.fromRGB(255, 206, 40)
local PACK_DARK = Color3.fromRGB(242, 158, 20)
local JET = Color3.fromRGB(206, 212, 226)
local JET_DARK = Color3.fromRGB(140, 148, 170)

-- Rayures franches (dégradé à bords nets) : n bandes alternées
local function stripes(a: Color3, b: Color3, count: number): ColorSequence
	local keypoints = {}
	for i = 0, count - 1 do
		local color = (i % 2 == 0) and a or b
		table.insert(keypoints, ColorSequenceKeypoint.new(i / count, color))
		table.insert(keypoints, ColorSequenceKeypoint.new(math.min(1, (i + 1) / count - 0.002), color))
	end
	keypoints[#keypoints] = ColorSequenceKeypoint.new(1, keypoints[#keypoints].Value)
	return ColorSequence.new(keypoints)
end

function Runner.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()

	------------------------------------------------------------------
	-- Géométrie de l'écran et projection
	------------------------------------------------------------------
	local slotW = container.Size.X.Offset > 0 and container.Size.X.Offset or 288
	local slotH = container.Size.Y.Offset > 0 and container.Size.Y.Offset or 190
	local SW = slotW - BEZEL * 2
	local SH = slotH - BEZEL * 2
	local U = SW / DESIGN_W -- facteur d'échelle
	local CX = SW / 2
	local HY = math.floor(SH * 0.4) -- ligne d'horizon
	local CAM_H = (SH - HY + 8 * U) / U -- hauteur de la caméra (sol à z = 1 : juste sous l'écran)
	local VP = Vector2.new(CX, HY) -- point de fuite
	local BELOW = Vector2.new(CX, SH + 400) -- point toujours "sous" les droites qui passent par le point de fuite

	local camX = 0 -- la caméra suit un peu le coureur

	-- Projection monde -> écran
	local function sx(wx: number, z: number): number
		return CX + (wx - camX) * U / z
	end
	local function sy(wy: number, z: number): number
		return HY + (CAM_H - wy) * U / z
	end

	-- Ordre d'affichage selon la profondeur (plus proche = au-dessus)
	local function depthZ(z: number): number
		return 20 + math.clamp(math.floor((Z_FAR + 1 - z) * 8), 0, 100)
	end

	-- 0 avant `from`, 1 à partir de `to` (pour faire apparaître au loin)
	local function fade(z: number, from: number, to: number): number
		return math.clamp((z - from) / (to - from), 0, 1)
	end

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function frame(props: { [string]: any }, radius: UDim?): Frame
		props.BorderSizePixel = 0
		local f = Create("Frame", props)
		if radius then
			UIUtil.Corner(f, radius)
		end
		return f
	end

	local ROUND = UDim.new(1, 0)

	------------------------------------------------------------------
	-- Cadre "téléphone" + écran (le ciel est le dégradé de l'écran)
	------------------------------------------------------------------
	local device = frame({
		Name = "RunnerDevice",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(24, 24, 32),
		Parent = container,
	}, UDim.new(0, 12))
	UIUtil.Stroke(device, Theme.Colors.Border, 2)

	local screen = frame({
		Name = "Screen",
		Position = UDim2.fromOffset(BEZEL, BEZEL),
		Size = UDim2.fromOffset(SW, SH),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = device,
	}, UDim.new(0, 8))
	local horizon = math.clamp(HY / SH, 0.15, 0.85)
	UIUtil.Gradient(
		screen,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(36, 104, 232)),
			ColorSequenceKeypoint.new(horizon * 0.45, Color3.fromRGB(70, 158, 255)),
			ColorSequenceKeypoint.new(horizon * 0.85, Color3.fromRGB(160, 222, 255)),
			ColorSequenceKeypoint.new(horizon, Color3.fromRGB(255, 216, 176)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 216, 176)),
		}),
		90
	)

	-- Calques de l'écran (ZIndex entre frères, du fond vers l'avant)
	local function layer(name: string, zIndex: number): Frame
		return frame({
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Parent = screen,
		})
	end

	------------------------------------------------------------------
	-- Soleil (2 halos + disque)
	------------------------------------------------------------------
	local sunX, sunY = SW * 0.78, HY * 0.42
	local function sunDisc(size: number, color: Color3, transparency: number, zIndex: number): Frame
		return frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(sunX, sunY),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			ZIndex = zIndex,
			Parent = screen,
		}, ROUND)
	end
	local sunGlowOuter = sunDisc(84 * U, Color3.fromRGB(255, 246, 200), 0.8, 1)
	local sunGlowInner = sunDisc(48 * U, Color3.fromRGB(255, 238, 170), 0.5, 1)
	local sun = sunDisc(27 * U, WHITE, 0, 1)
	UIUtil.Gradient(sun, ColorSequence.new(Color3.fromRGB(255, 255, 232), Color3.fromRGB(255, 206, 80)), 90)

	------------------------------------------------------------------
	-- Nuages (3, qui dérivent ; parallaxe légère)
	------------------------------------------------------------------
	local clouds = {}
	for i = 1, 3 do
		local width = random:NextNumber(44, 66) * U
		local base = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(width, width * 0.34),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.04,
			ZIndex = 2,
			Parent = screen,
		}, ROUND)
		UIUtil.Gradient(base, ColorSequence.new(WHITE, Color3.fromRGB(214, 230, 255)), 90)
		frame({
			Position = UDim2.fromScale(0.12, -0.6),
			Size = UDim2.fromScale(0.4, 1.15),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.04,
			ZIndex = 2,
			Parent = base,
		}, ROUND)
		frame({
			Position = UDim2.fromScale(0.44, -0.38),
			Size = UDim2.fromScale(0.32, 0.9),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.04,
			ZIndex = 2,
			Parent = base,
		}, ROUND)
		table.insert(clouds, {
			Frame = base,
			X = SW * (i - 0.5) / 3 + random:NextNumber(-20, 20) * U,
			Y = random:NextNumber(0.2, 0.62) * HY,
			Width = width,
			Speed = random:NextNumber(4, 9) * U,
			Parallax = 0.03 + i * 0.015,
		})
	end

	------------------------------------------------------------------
	-- Ville à l'horizon : couche lointaine (brumeuse) + couche proche
	-- (fenêtres), plus larges que l'écran pour la parallaxe
	------------------------------------------------------------------
	local SKY_MARGIN = 24 * U
	local function skyline(name: string, zIndex: number, count: number, baseY: number, minH: number, maxH: number, near: boolean): Frame
		local holder = frame({
			Name = name,
			Position = UDim2.fromOffset(-SKY_MARGIN, 0),
			Size = UDim2.fromOffset(SW + SKY_MARGIN * 2, SH),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Parent = screen,
		})
		local totalW = SW + SKY_MARGIN * 2
		local step = totalW / count
		for i = 1, count do
			local w = step * random:NextNumber(0.95, 1.3)
			local h = random:NextNumber(minH, maxH) * U
			local x = (i - 1) * step - step * 0.1 + random:NextNumber(-3, 3) * U
			local b = frame({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromOffset(x, baseY),
				Size = UDim2.fromOffset(w, h + (baseY - HY)),
				BackgroundColor3 = WHITE,
				ZIndex = zIndex,
				Parent = holder,
			}, UDim.new(0, (i % 3 == 0) and 6 * U or 2 * U))
			if near then
				local body = (i % 2 == 0) and Color3.fromRGB(112, 120, 204) or Color3.fromRGB(134, 112, 196)
				local glass = Color3.fromRGB(186, 208, 255)
				UIUtil.Gradient(b, stripes(body, body:Lerp(glass, 0.55), 8), (i % 2 == 0) and 90 or 0)
			else
				UIUtil.Gradient(b, ColorSequence.new(Color3.fromRGB(172, 186, 238), Color3.fromRGB(214, 220, 248)), 90)
			end
		end
		return holder
	end
	local skyFar = skyline("SkyFar", 3, 6, HY + 2 * U, 18, 40, false)
	local skyNear = skyline("SkyNear", 4, 6, HY + 52 * U, 8, 26, true)

	------------------------------------------------------------------
	-- Murs et sol en perspective : demi-plans (grands cadres tournés)
	-- découpés par deux zones (gauche / droite du point de fuite)
	------------------------------------------------------------------

	-- Place un grand cadre tourné dont un bord suit la droite p1 -> p2, du côté de `toward`
	local function setHalfPlane(f: Frame, origin: Vector2, p1: Vector2, p2: Vector2, toward: Vector2)
		local delta = p2 - p1
		local length = delta.Magnitude
		if length < 1e-3 then
			f.Visible = false
			return
		end
		f.Visible = true
		local dir = delta / length
		local normal = Vector2.new(-dir.Y, dir.X)
		if (toward - p1):Dot(normal) < 0 then
			normal = -normal
		end
		local center = (p1 + p2) / 2 + normal * (BIG / 2) - origin
		f.Position = UDim2.fromOffset(center.X, center.Y)
		f.Size = UDim2.fromOffset(length + BIG * 2, BIG)
		f.Rotation = math.deg(math.atan2(dir.Y, dir.X))
	end

	-- Place un trait entre deux points
	local function setLine(f: Frame, p1: Vector2, p2: Vector2, thickness: number)
		local delta = p2 - p1
		local mid = (p1 + p2) / 2
		f.Position = UDim2.fromOffset(mid.X, mid.Y)
		f.Size = UDim2.fromOffset(delta.Magnitude, thickness)
		f.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end

	local sides = {}
	for _, def in ipairs(SIDE_DEFS) do
		local s = def.Sign
		local originX = s < 0 and 0 or CX
		local clip = frame({
			Name = s < 0 and "LeftSide" or "RightSide",
			Position = UDim2.fromOffset(originX, 0),
			Size = UDim2.fromOffset(s < 0 and CX or SW - CX, SH),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 5,
			Parent = screen,
		})
		local function plane(color: Color3, zIndex: number): Frame
			return frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				ZIndex = zIndex,
				Parent = clip,
			})
		end
		local side = {
			Sign = s,
			Origin = Vector2.new(originX, 0),
			Clip = clip,
			Wall = plane(def.Wall, 1),
			Stripe = plane(def.Stripe, 2),
			Lower = plane(def.Lower, 3),
			-- (ZIndex 4 : graffitis)
			Ground = plane(GROUND_COLOR, 5),
			Bed = plane(BED_COLOR, 6),
			Cap = plane(WHITE, 7),
		}
		side.Cap.BackgroundTransparency = 0.3
		table.insert(sides, side)
	end

	------------------------------------------------------------------
	-- Voie : traverses (qui défilent) et rails
	------------------------------------------------------------------
	local track = layer("Track", 6)

	local ties = {}
	for _, laneX in ipairs(LANES) do
		for i = 1, TIE_PER_LANE do
			local tie = frame({
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(150, 102, 66),
				ZIndex = 1,
				Parent = track,
			})
			table.insert(ties, { Frame = tie, X = laneX, Offset = (i - 1) * TIE_GAP })
		end
	end
	local TIE_CYCLE = TIE_PER_LANE * TIE_GAP

	local rails = {}
	for _, laneX in ipairs(LANES) do
		for _, offset in ipairs({ -RAIL_OFFSET, RAIL_OFFSET }) do
			local rail = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(236, 238, 248),
				ZIndex = 2,
				Parent = track,
			})
			-- Le bout lointain s'estompe dans la brume
			local gradient = UIUtil.Gradient(rail, ColorSequence.new(WHITE), 0)
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.75),
				NumberSequenceKeypoint.new(0.35, 0.1),
				NumberSequenceKeypoint.new(1, 0),
			})
			table.insert(rails, { Frame = rail, X = laneX + offset })
		end
	end

	-- Recalcule murs, sol et rails (seulement quand la caméra bouge)
	local function worldPoint(wx: number, wy: number): Vector2
		return Vector2.new(sx(wx, 1), sy(wy, 1))
	end
	local function updateStatic()
		for _, side in ipairs(sides) do
			local s = side.Sign
			local origin = side.Origin
			local top = worldPoint(s * WALL_X, WALL_H)
			setHalfPlane(side.Wall, origin, VP, top, BELOW)
			setHalfPlane(side.Stripe, origin, VP, worldPoint(s * WALL_X, 46), BELOW)
			setHalfPlane(side.Lower, origin, VP, worldPoint(s * WALL_X, 37), BELOW)
			setHalfPlane(side.Ground, origin, VP, worldPoint(s * WALL_X, 0), BELOW)
			setHalfPlane(side.Bed, origin, VP, worldPoint(s * TRACK_HALF, 0), BELOW)
			setLine(side.Cap, VP - origin, top - origin, math.max(1, 2 * U))
		end
		local thickness = math.max(1.5, 2.2 * U)
		for _, rail in ipairs(rails) do
			local far = Vector2.new(sx(rail.X, Z_FAR), sy(0, Z_FAR))
			local near = Vector2.new(sx(rail.X, 0.75), sy(0, 0.75))
			setLine(rail.Frame, far, near, thickness)
		end
	end

	------------------------------------------------------------------
	-- Monde (objets triés par profondeur)
	------------------------------------------------------------------
	local world = layer("World", 7)

	-- Brume à l'horizon : les objets lointains en sortent doucement
	local fog = frame({
		Name = "Fog",
		Position = UDim2.fromOffset(0, HY - 12 * U),
		Size = UDim2.fromOffset(SW, 30 * U),
		BackgroundColor3 = Color3.fromRGB(255, 236, 214),
		ZIndex = depthZ(6),
		Parent = world,
	})
	local fogGradient = UIUtil.Gradient(fog, ColorSequence.new(WHITE), 90)
	fogGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- Lampadaires (2 par côté, recyclés en boucle)
	local poles = {}
	for _, s in ipairs({ -1, 1 }) do
		for i = 1, POLE_PER_SIDE do
			local pole = frame({
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = Color3.fromRGB(70, 74, 96),
				Parent = world,
			})
			UIUtil.Gradient(pole, ColorSequence.new(Color3.fromRGB(150, 150, 170), WHITE), 0)
			local arm = frame({
				AnchorPoint = Vector2.new(s < 0 and 0 or 1, 0.5),
				BackgroundColor3 = Color3.fromRGB(70, 74, 96),
				Parent = world,
			})
			local glow = frame({
				AnchorPoint = Vector2.new(0.5, 0.2),
				Position = UDim2.fromScale(s < 0 and 0.92 or 0.08, 0.5),
				Size = UDim2.fromScale(0.42, 2.8),
				BackgroundColor3 = Color3.fromRGB(255, 244, 180),
				Parent = arm,
			}, ROUND)
			table.insert(poles, {
				Pole = pole,
				Arm = arm,
				Glow = glow,
				Sign = s,
				Offset = (i - 1) * POLE_GAP + (s > 0 and POLE_GAP / 2 or 0),
			})
		end
	end
	local POLE_CYCLE = POLE_PER_SIDE * POLE_GAP

	-- Graffitis sur les murs (2, recyclés ; dessinés entre le mur et le sol)
	local panels = {}
	local function restylePanel(panel)
		local side = sides[random:NextInteger(1, 2)]
		panel.Side = side
		panel.Frame.Parent = side.Clip
		local colors = GRAFFITI_COLORS[random:NextInteger(1, #GRAFFITI_COLORS)]
		panel.Gradient.Color = ColorSequence.new(colors[1], colors[2])
		panel.Gradient.Rotation = random:NextInteger(0, 1) * 90 + random:NextNumber(-20, 20)
		local graffitiWords = Locale.Pick(GRAFFITI_WORDS)
		panel.Label.Text = graffitiWords[random:NextInteger(1, #graffitiWords)]
		panel.Label.Rotation = random:NextNumber(-10, 10)
	end
	for i = 1, 2 do
		local f = frame({
			BackgroundColor3 = WHITE,
			ZIndex = 4,
			Visible = false,
			Parent = sides[1].Clip,
		}, UDim.new(0.14, 0))
		local label = UIUtil.Label({
			Text = "",
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = WHITE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.86, 0.72),
			ZIndex = 4,
			MaxTextSize = 60,
			Parent = f,
		})
		local stroke = UIUtil.Stroke(label, Color3.fromRGB(30, 24, 40), 1.5)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		local panel = {
			Frame = f,
			Gradient = UIUtil.Gradient(f, ColorSequence.new(WHITE), 0),
			Label = label,
			Stroke = stroke,
			Z = 3 + i * 3.8,
			Side = sides[1],
		}
		restylePanel(panel)
		table.insert(panels, panel)
	end

	------------------------------------------------------------------
	-- Trains (face avant détaillée + toit qui file vers le fond)
	------------------------------------------------------------------
	local trains = {}
	for _ = 1, TRAIN_POOL do
		local roof = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			Visible = false,
			Parent = world,
		}, UDim.new(0.2, 0))
		local roofGradient = UIUtil.Gradient(roof, ColorSequence.new(Color3.fromRGB(170, 172, 186), WHITE), 0)
		local body = frame({
			Name = "Train",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = WHITE,
			Visible = false,
			Parent = world,
		}, UDim.new(0.14, 0))
		UIUtil.Gradient(
			body,
			ColorSequence.new({
				ColorSequenceKeypoint.new(0, WHITE),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(236, 236, 240)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 184)),
			}),
			90
		)
		local windshield = frame({
			Position = UDim2.fromScale(0.12, 0.11),
			Size = UDim2.fromScale(0.76, 0.32),
			BackgroundColor3 = WHITE,
			Parent = body,
		}, UDim.new(0.22, 0))
		UIUtil.Gradient(windshield, ColorSequence.new(Color3.fromRGB(150, 222, 255), Color3.fromRGB(34, 52, 96)), 70)
		frame({
			Position = UDim2.fromScale(0.2, -0.15),
			Size = UDim2.fromScale(0.1, 1.3),
			Rotation = 28,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.55,
			Parent = windshield,
		})
		frame({
			Position = UDim2.fromScale(0, 0.52),
			Size = UDim2.fromScale(1, 0.08),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.1,
			Parent = body,
		})
		local function headlight(x: number): Frame
			local light = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.72),
				Size = UDim2.fromScale(0.16, 0.12),
				BackgroundColor3 = Color3.fromRGB(255, 248, 196),
				Parent = body,
			}, ROUND)
			return light
		end
		local headL = headlight(0.2)
		local headR = headlight(0.8)
		frame({
			Position = UDim2.fromScale(0.05, 0.86),
			Size = UDim2.fromScale(0.9, 0.14),
			BackgroundColor3 = Color3.fromRGB(56, 58, 70),
			Parent = body,
		}, UDim.new(0.3, 0))
		table.insert(trains, {
			Active = false,
			Body = body,
			Roof = roof,
			RoofGradient = roofGradient,
			HeadL = headL,
			HeadR = headR,
			Lane = 1,
			Z = Z_FAR,
			Extra = 0,
		})
	end

	------------------------------------------------------------------
	-- Barrières (basses : on saute ; hautes : on roule dessous)
	------------------------------------------------------------------
	local barriers = {}
	for _ = 1, BARRIER_POOL do
		local board = frame({
			Name = "Barrier",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = WHITE,
			Visible = false,
			Parent = world,
		}, UDim.new(0.18, 0))
		local gradient = UIUtil.Gradient(board, ColorSequence.new(WHITE), 25)
		local legs = {}
		for _, legX in ipairs({ 0.13, 0.87 }) do
			table.insert(
				legs,
				frame({
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(legX, 1),
					Size = UDim2.fromScale(0.07, 1),
					BackgroundColor3 = Color3.fromRGB(78, 82, 100),
					Parent = board,
				})
			)
		end
		local light = frame({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.05),
			Size = UDim2.fromScale(0.12, 0.42),
			BackgroundColor3 = Color3.fromRGB(255, 70, 60),
			Parent = board,
		}, ROUND)
		table.insert(barriers, {
			Active = false,
			Board = board,
			Gradient = gradient,
			Legs = legs,
			Light = light,
			Kind = "Low",
			Bottom = 22,
			Top = 40,
			Lane = 1,
			Z = Z_FAR,
			Handled = false,
			Phase = 0,
		})
	end

	------------------------------------------------------------------
	-- Pièces (tournent sur elles-mêmes, reflet qui balaie)
	------------------------------------------------------------------
	local coinSequence = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 30)),
		ColorSequenceKeypoint.new(0.38, Color3.fromRGB(255, 216, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 222)),
		ColorSequenceKeypoint.new(0.62, Color3.fromRGB(255, 216, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(226, 142, 16)),
	})
	local coinsPool = {}
	for _ = 1, COIN_POOL do
		local coin = frame({
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			Visible = false,
			Parent = world,
		}, ROUND)
		local gradient = UIUtil.Gradient(coin, coinSequence, 45)
		local stroke = UIUtil.Stroke(coin, Color3.fromRGB(196, 116, 8), 1)
		table.insert(coinsPool, {
			Active = false,
			Frame = coin,
			Gradient = gradient,
			Stroke = stroke,
			Lane = 1,
			X = 0,
			H = COIN_H,
			Z = Z_FAR,
			Phase = 0,
			Air = false,
			Pulled = false,
		})
	end

	------------------------------------------------------------------
	-- Bonus à ramasser (aimant / jetpack)
	------------------------------------------------------------------
	local pickupGlow = frame({
		Name = "PowerUp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 250, 210),
		BackgroundTransparency = 0.3,
		Visible = false,
		Parent = world,
	}, ROUND)
	local pickupStroke = UIUtil.Stroke(pickupGlow, WHITE, 1.5, 0.2)
	local pickupIcon = UIUtil.Label({
		Text = "🧲",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		MaxTextSize = 60,
		Parent = pickupGlow,
	})
	local pickup = { Active = false, Kind = "Magnet", Lane = 2, Z = Z_FAR }

	------------------------------------------------------------------
	-- Le coureur (vu de dos) : sweat, capuche, casquette à l'envers, sac
	------------------------------------------------------------------
	local CW = CHAR_W * U / CHAR_Z
	local CH = CHAR_H * U / CHAR_Z
	local charDepth = depthZ(CHAR_Z)

	local shadow = frame({
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.65,
		ZIndex = charDepth - 1,
		Parent = world,
	}, ROUND)

	local aura = frame({
		Name = "MagnetAura",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 90, 200),
		BackgroundTransparency = 0.9,
		Visible = false,
		ZIndex = charDepth + 1,
		Parent = world,
	}, ROUND)
	local auraStroke = UIUtil.Stroke(aura, Color3.fromRGB(255, 90, 200), 2, 0.2)

	local hero = frame({
		Name = "Hero",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(CW, CH),
		BackgroundTransparency = 1,
		ZIndex = charDepth,
		Parent = world,
	})

	local function limb(parent: Instance, props: { [string]: any }, radius: UDim?): Frame
		props.Parent = parent
		return frame(props, radius or UDim.new(0.4, 0))
	end

	local legs = {}
	for _, x in ipairs({ 0.35, 0.65 }) do
		local leg = limb(hero, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0.6),
			Size = UDim2.fromScale(0.2, 0.34),
			BackgroundColor3 = JEANS,
			ZIndex = 1,
		})
		UIUtil.Gradient(leg, ColorSequence.new(Color3.fromRGB(200, 200, 210), WHITE), 90)
		local shoe = limb(leg, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1.4, 0, 0, math.max(2, CH * 0.11)),
			BackgroundColor3 = WHITE,
			ZIndex = 1,
		})
		UIUtil.Gradient(
			shoe,
			ColorSequence.new({
				ColorSequenceKeypoint.new(0, WHITE),
				ColorSequenceKeypoint.new(0.58, Color3.fromRGB(236, 236, 244)),
				ColorSequenceKeypoint.new(0.6, Color3.fromRGB(236, 56, 70)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 36, 50)),
			}),
			90
		)
		table.insert(legs, { Frame = leg, X = x })
	end

	local arms = {}
	for _, x in ipairs({ 0.13, 0.87 }) do
		local arm = limb(hero, {
			AnchorPoint = Vector2.new(0.5, 0.05),
			Position = UDim2.fromScale(x, 0.31),
			Size = UDim2.fromScale(0.17, 0.3),
			BackgroundColor3 = HOODIE_DARK,
			ZIndex = 1,
		})
		limb(arm, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1.05, 0, 0, math.max(2, CW * 0.18)),
			BackgroundColor3 = SKIN,
		}, ROUND)
		table.insert(arms, { Frame = arm, X = x })
	end

	local torso = limb(hero, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromScale(0.66, 0.4),
		BackgroundColor3 = HOODIE,
		ZIndex = 2,
	}, UDim.new(0.3, 0))
	UIUtil.Gradient(
		torso,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 200, 200)),
			ColorSequenceKeypoint.new(0.5, WHITE),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
		}),
		0
	)
	limb(hero, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.29),
		Size = UDim2.fromScale(0.5, 0.14),
		BackgroundColor3 = HOODIE_DARK,
		ZIndex = 3,
	}, ROUND)
	local head = limb(hero, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.01),
		Size = UDim2.fromScale(0.44, 0.29),
		BackgroundColor3 = HAIR,
		ZIndex = 4,
	}, ROUND)
	local cap = limb(head, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, -0.08),
		Size = UDim2.fromScale(1.06, 0.62),
		BackgroundColor3 = CAP,
		ZIndex = 1,
	}, UDim.new(0.5, 0))
	UIUtil.Gradient(cap, ColorSequence.new(WHITE, Color3.fromRGB(200, 206, 220)), 90)
	-- Visière tournée vers l'arrière (donc vers nous)
	limb(head, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.9, 0.2),
		BackgroundColor3 = CAP_DARK,
		ZIndex = 2,
	}, UDim.new(0.5, 0))
	local backpack = limb(hero, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.35),
		Size = UDim2.fromScale(0.5, 0.3),
		BackgroundColor3 = PACK,
		ZIndex = 5,
	}, UDim.new(0.28, 0))
	local pocket = limb(backpack, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.72, 0.36),
		BackgroundColor3 = PACK_DARK,
	}, UDim.new(0.3, 0))
	-- Flammes du jetpack (cachées hors bonus)
	local flames = {}
	for _, x in ipairs({ 0.27, 0.73 }) do
		local flame = limb(backpack, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0.95),
			Size = UDim2.fromScale(0.3, 0.7),
			BackgroundColor3 = WHITE,
			Visible = false,
		}, UDim.new(0.5, 0))
		local gradient = UIUtil.Gradient(flame, ColorSequence.new(Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 96, 20)), 90)
		gradient.Transparency = NumberSequence.new(0, 0.85)
		table.insert(flames, flame)
	end

	------------------------------------------------------------------
	-- Effets (lignes de vitesse, étincelles, "+1")
	------------------------------------------------------------------
	local fxLayer = layer("FX", 8)

	local speedLines = {}
	for _ = 1, SPEEDLINE_POOL do
		table.insert(speedLines, {
			Frame = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 1,
				Visible = false,
				Parent = fxLayer,
			}),
			Angle = 0,
			R = 0,
			Speed = 0,
		})
	end
	local function resetSpeedLine(line)
		local roll = random:NextNumber()
		local degrees
		if roll < 0.3 then
			degrees = random:NextNumber(200, 252) -- ciel (pas derrière le coureur)
		elseif roll < 0.6 then
			degrees = random:NextNumber(288, 340)
		elseif roll < 0.8 then
			degrees = random:NextNumber(-25, 12) -- côté droit
		else
			degrees = random:NextNumber(168, 205) -- côté gauche
		end
		line.Angle = math.rad(degrees)
		line.R = random:NextNumber(14, 50) * U
		line.Speed = random:NextNumber(220, 340) * U
	end
	for _, line in ipairs(speedLines) do
		resetSpeedLine(line)
		line.R = random:NextNumber(14, 200) * U
	end

	local sparkles = {}
	for _ = 1, SPARKLE_POOL do
		table.insert(sparkles, {
			Frame = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(255, 244, 150),
				Visible = false,
				Parent = fxLayer,
			}),
			Life = 0,
			X = 0,
			Y = 0,
			VX = 0,
			VY = 0,
		})
	end

	local pops = {}
	for _ = 1, POP_POOL do
		local label = UIUtil.Label({
			Text = "+1",
			Font = Theme.Fonts.Title,
			TextColor3 = GOLD,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			MaxTextSize = 40,
			Parent = fxLayer,
		})
		local stroke = UIUtil.Stroke(label, Color3.fromRGB(90, 50, 0), 1.5)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		table.insert(pops, { Label = label, Stroke = stroke, Life = 0, X = 0, Y = 0, W = 40, H = 16 })
	end

	local function spawnSparkles(x: number, y: number, count: number)
		if not effectsOn() then
			return
		end
		for _ = 1, count do
			local chosen: any = nil
			for _, sparkle in ipairs(sparkles) do
				if sparkle.Life <= 0 then
					chosen = sparkle
					break
				end
			end
			if not chosen then
				return
			end
			local angle = random:NextNumber(0, math.pi * 2)
			local velocity = random:NextNumber(40, 90) * U
			chosen.Life = 0.45
			chosen.X, chosen.Y = x, y
			chosen.VX = math.cos(angle) * velocity
			chosen.VY = math.sin(angle) * velocity - 30 * U
			chosen.Frame.BackgroundColor3 = (random:NextNumber() < 0.5) and Color3.fromRGB(255, 244, 150) or WHITE
			chosen.Frame.Visible = true
		end
	end

	local function popText(text: string, x: number, y: number, color: Color3, width: number, height: number)
		-- Réutilise le "+1" libre, sinon le plus ancien
		local chosen = pops[1]
		for _, pop in ipairs(pops) do
			if pop.Life < chosen.Life then
				chosen = pop
			end
		end
		chosen.Life = 0.7
		chosen.X, chosen.Y = x, y
		chosen.W, chosen.H = width, height
		chosen.Label.Text = text
		chosen.Label.TextColor3 = color
		chosen.Label.Visible = true
	end

	------------------------------------------------------------------
	-- HUD (pièces, distance, bonus en cours)
	------------------------------------------------------------------
	local hud = layer("HUD", 9)

	local function pill(position: UDim2, size: UDim2, anchor: Vector2?): Frame
		local p = frame({
			AnchorPoint = anchor or Vector2.zero,
			Position = position,
			Size = size,
			BackgroundColor3 = Color3.fromRGB(16, 18, 30),
			BackgroundTransparency = 0.4,
			ZIndex = 1,
			Parent = hud,
		}, ROUND)
		UIUtil.Stroke(p, WHITE, 1, 0.65)
		return p
	end

	local coinPill = pill(UDim2.fromOffset(6 * U, 6 * U), UDim2.fromOffset(64 * U, 20 * U))
	local coinPillScale = Create("UIScale", { Parent = coinPill })
	local coinIcon = frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3 * U, 0.5, 0),
		Size = UDim2.fromOffset(14 * U, 14 * U),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = coinPill,
	}, ROUND)
	UIUtil.Gradient(coinIcon, coinSequence, 45)
	UIUtil.Stroke(coinIcon, Color3.fromRGB(196, 116, 8), 1)
	local coinLabel = UIUtil.Label({
		Text = "0",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(21 * U, 2 * U),
		Size = UDim2.new(1, -25 * U, 1, -4 * U),
		MaxTextSize = math.floor(16 * U),
		ZIndex = 2,
		Parent = coinPill,
	})

	local distPill = pill(UDim2.new(1, -6 * U, 0, 6 * U), UDim2.fromOffset(72 * U, 20 * U), Vector2.new(1, 0))
	local distLabel = UIUtil.Label({
		Text = "0 m",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		Position = UDim2.fromOffset(6 * U, 2 * U),
		Size = UDim2.new(1, -12 * U, 1, -4 * U),
		MaxTextSize = math.floor(16 * U),
		ZIndex = 2,
		Parent = distPill,
	})

	local powerPill = pill(UDim2.fromOffset(6 * U, 30 * U), UDim2.fromOffset(64 * U, 17 * U))
	powerPill.Visible = false
	local powerIcon = UIUtil.Label({
		Text = "🧲",
		Position = UDim2.fromOffset(3 * U, 1 * U),
		Size = UDim2.fromOffset(15 * U, 15 * U),
		MaxTextSize = 30,
		ZIndex = 2,
		Parent = powerPill,
	})
	local powerBack = frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 21 * U, 0.5, 0),
		Size = UDim2.new(1, -27 * U, 0, math.max(3, 5 * U)),
		BackgroundColor3 = Color3.fromRGB(60, 62, 80),
		ZIndex = 2,
		Parent = powerPill,
	}, ROUND)
	local powerFill = frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = GOLD,
		ZIndex = 3,
		Parent = powerBack,
	}, ROUND)

	------------------------------------------------------------------
	-- État de la partie
	------------------------------------------------------------------
	local clock = 0
	local runTime = 0
	local speed = BASE_SPEED
	local scroll = 0 -- distance parcourue (défilement des traverses, lampadaires)
	local waveDistance = 0
	local distance = 0
	local coinCount = 0
	local shownCoins, shownDistance = -1, -1
	local coinPulse = 0

	local targetLane = 2
	local runnerX = 0
	local runnerH = 0
	local lean = 0
	local runPhase = 0
	local jumpT = -1 -- < 0 : pas de saut en cours
	local rollT = -1 -- < 0 : pas de roulade en cours
	local wishLane, wishTimer = 2, 2

	local jetTime, magnetTime = 0, 0
	local powerTimer = random:NextNumber(9, 14) -- premier bonus assez tôt
	local pendingPower: string? = nil
	local airDistance, airLane, airCount = 0, 2, 0
	local lineStrength = 0
	local linesVisible = false
	local lastStaticCam = math.huge

	local function nearestLane(x: number): number
		local best, bestDistance = 2, math.huge
		for index, laneX in ipairs(LANES) do
			local d = math.abs(x - laneX)
			if d < bestDistance then
				best, bestDistance = index, d
			end
		end
		return best
	end

	------------------------------------------------------------------
	-- Apparition des objets
	------------------------------------------------------------------
	local function firstFree(pool)
		for _, object in ipairs(pool) do
			if not object.Active then
				return object
			end
		end
		return nil
	end

	local function spawnTrain(lane: number, z: number, oncoming: boolean)
		local train = firstFree(trains)
		if not train then
			return false
		end
		local color = TRAIN_COLORS[random:NextInteger(1, #TRAIN_COLORS)]
		train.Active = true
		train.Lane = lane
		train.Z = z
		train.Extra = oncoming and ONCOMING_EXTRA or 0
		train.Body.BackgroundColor3 = color
		train.Roof.BackgroundColor3 = color:Lerp(WHITE, 0.4)
		local lightColor = oncoming and Color3.fromRGB(255, 252, 214) or Color3.fromRGB(255, 222, 150)
		train.HeadL.BackgroundColor3 = lightColor
		train.HeadR.BackgroundColor3 = lightColor
		train.HeadL.BackgroundTransparency = oncoming and 0 or 0.35
		train.HeadR.BackgroundTransparency = oncoming and 0 or 0.35
		train.Body.Visible = true
		train.Roof.Visible = true
		return true
	end

	local function spawnBarrier(lane: number, z: number, kind: string)
		local barrier = firstFree(barriers)
		if not barrier then
			return false
		end
		barrier.Active = true
		barrier.Lane = lane
		barrier.Z = z
		barrier.Kind = kind
		barrier.Handled = false
		barrier.Phase = random:NextNumber(0, 6)
		if kind == "Low" then
			barrier.Bottom, barrier.Top = 22, 40
			barrier.Gradient.Color = stripes(Color3.fromRGB(236, 40, 52), WHITE, 7)
		else
			barrier.Bottom, barrier.Top = 60, 80
			barrier.Gradient.Color = stripes(Color3.fromRGB(255, 200, 20), Color3.fromRGB(34, 34, 44), 7)
		end
		local legScale = barrier.Bottom / (barrier.Top - barrier.Bottom)
		for _, leg in ipairs(barrier.Legs) do
			leg.Size = UDim2.fromScale(0.07, legScale)
		end
		barrier.Board.Visible = true
		return true
	end

	local function spawnCoin(lane: number, z: number, height: number, air: boolean)
		local coin = firstFree(coinsPool)
		if not coin then
			return
		end
		coin.Active = true
		coin.Lane = lane
		coin.X = LANES[lane]
		coin.H = height
		coin.Z = z
		coin.Phase = z * 2.2
		coin.Air = air
		coin.Pulled = false
		coin.Frame.Visible = true
	end

	local function laneIsEmpty(lane: number): boolean
		for _, pool in ipairs({ trains, barriers, coinsPool }) do
			for _, object in ipairs(pool) do
				if object.Active and object.Lane == lane then
					return false
				end
			end
		end
		return not (pickup.Active and pickup.Lane == lane)
	end

	local function anyTrain(): boolean
		for _, train in ipairs(trains) do
			if train.Active then
				return true
			end
		end
		return false
	end

	-- Une vague : une voie toujours libre, le reste trains / barrières / rien
	local function spawnWave(z: number)
		local trainsAllowed = jetTime <= 0 or jetTime > 3.5
		local free = random:NextInteger(1, 3)
		local kinds = { "None", "None", "None" }

		-- Parfois un train qui fonce vers nous (seul train à l'écran, voie vide)
		local oncoming: number? = nil
		if trainsAllowed and not anyTrain() and random:NextNumber() < 0.3 then
			local candidate = random:NextInteger(1, 3)
			if laneIsEmpty(candidate) then
				oncoming = candidate
				kinds[candidate] = "Oncoming"
				if free == candidate then
					free = candidate % 3 + 1
				end
			end
		end

		for lane = 1, 3 do
			if lane ~= free and kinds[lane] == "None" then
				local roll = random:NextNumber()
				if trainsAllowed and not oncoming and roll < 0.42 then
					kinds[lane] = "Train"
				elseif roll < 0.8 then
					kinds[lane] = (random:NextNumber() < 0.6) and "Low" or "High"
				end
			end
		end
		-- Jamais deux trains côte à côte : le coureur serait coincé
		if kinds[2] == "Train" and (kinds[1] == "Train" or kinds[3] == "Train") then
			kinds[2] = "Low"
		end

		for lane = 1, 3 do
			local kind = kinds[lane]
			if kind == "Train" or kind == "Oncoming" then
				if not spawnTrain(lane, z, kind == "Oncoming") then
					kinds[lane] = "None"
				end
			elseif kind == "Low" or kind == "High" then
				if not spawnBarrier(lane, z, kind) then
					kinds[lane] = "None"
				end
			end
		end

		-- Bonus sur la voie libre
		if pendingPower and not pickup.Active then
			pickup.Active = true
			pickup.Kind = pendingPower
			pickup.Lane = free
			pickup.Z = z + 1.3
			pickupIcon.Text = pendingPower == "Jetpack" and "🚀" or "🧲"
			pickupGlow.BackgroundColor3 = pendingPower == "Jetpack" and Color3.fromRGB(170, 226, 255) or Color3.fromRGB(255, 190, 200)
			pickupGlow.Visible = true
			pendingPower = nil
		end

		-- Pièces : sur la voie libre, ou en arc au-dessus d'une barrière basse
		local coinLane = free
		if random:NextNumber() < 0.4 then
			local other = random:NextInteger(1, 3)
			local kind = kinds[other]
			if kind == "Low" or kind == "High" or kind == "None" then
				coinLane = other
			end
		end
		local count = random:NextInteger(3, 5)
		local arc = kinds[coinLane] == "Low"
		for k = 0, count - 1 do
			local dz = (k - (count - 1) / 2) * 0.42
			local height = COIN_H
			if arc then
				height += 36 * math.max(0, 1 - (dz / 0.95) ^ 2)
			end
			spawnCoin(coinLane, z + dz, height, false)
		end
	end

	------------------------------------------------------------------
	-- Ramassage
	------------------------------------------------------------------
	local function collectCoin(coin, px: number, py: number)
		coin.Active = false
		coin.Frame.Visible = false
		coinCount += 1
		coinPulse = 1
		spawnSparkles(px, py, 2)
		popText("+1", px, py - 8 * U, GOLD, 34 * U, 15 * U)
	end

	local function activatePower(kind: string, px: number, py: number)
		if kind == "Jetpack" then
			jetTime = JET_TIME
			magnetTime = 0
			airLane = targetLane
			airCount = 0
			airDistance = 0
			jumpT, rollT = -1, -1
			powerIcon.Text = "🚀"
			powerFill.BackgroundColor3 = Color3.fromRGB(80, 200, 255)
			popText(Locale.T("JETPACK!"), CX, HY + 20 * U, Color3.fromRGB(120, 220, 255), 120 * U, 26 * U)
		else
			magnetTime = MAGNET_TIME
			jetTime = 0
			powerIcon.Text = "🧲"
			powerFill.BackgroundColor3 = Color3.fromRGB(255, 90, 170)
			popText(Locale.T("MAGNET!"), CX, HY + 20 * U, Color3.fromRGB(255, 120, 190), 120 * U, 26 * U)
		end
		powerPill.Visible = true
		spawnSparkles(px, py, 5)
	end

	------------------------------------------------------------------
	-- "IA" du coureur : choisit sa voie (évite les trains, vise les pièces)
	------------------------------------------------------------------

	-- Temps (s) avant qu'un train n'arrive sur le coureur dans cette voie
	local function laneDanger(lane: number): number
		local best = math.huge
		for _, train in ipairs(trains) do
			if train.Active and train.Lane == lane then
				local v = speed + train.Extra
				local leave = (train.Z + TRAIN_LEN - CHAR_Z + 0.3) / v
				if leave > 0 then
					best = math.min(best, math.max(0, (train.Z - CHAR_Z - 0.3) / v))
				end
			end
		end
		return best
	end

	local function laneAppeal(lane: number): number
		local score = 0
		for _, coin in ipairs(coinsPool) do
			if coin.Active and coin.Lane == lane and coin.Z > CHAR_Z and coin.Z < CHAR_Z + 3.5 then
				score += 0.5
			end
		end
		for _, barrier in ipairs(barriers) do
			if barrier.Active and barrier.Lane == lane and barrier.Z > CHAR_Z and barrier.Z < CHAR_Z + 3 then
				score -= 0.2
			end
		end
		if pickup.Active and pickup.Lane == lane and pickup.Z > CHAR_Z then
			score += 4
		end
		if lane == wishLane then
			score += 0.9
		end
		return score
	end

	local function chooseLane()
		local current = targetLane
		local danger = { laneDanger(1), laneDanger(2), laneDanger(3) }
		local bestLane, bestScore = current, -math.huge
		for lane = 1, 3 do
			local score = laneAppeal(lane) - math.abs(lane - current) * 0.8
			if danger[lane] < 1.1 then
				score -= 100 - danger[lane] * 20 -- plus le train est proche, pire c'est
			end
			if math.abs(lane - current) == 2 and danger[2] < 0.9 then
				score -= 80 -- impossible de traverser la voie du milieu
			end
			if lane == current then
				score += 0.3
			end
			if score > bestScore then
				bestLane, bestScore = lane, score
			end
		end
		if bestLane ~= current then
			targetLane = current + (bestLane > current and 1 or -1) -- une voie à la fois
		end
	end

	------------------------------------------------------------------
	-- Mise en place : décor placé, deux vagues déjà en route
	------------------------------------------------------------------
	updateStatic()
	lastStaticCam = camX
	spawnWave(Z_FAR - WAVE_GAP)
	spawnWave(Z_FAR)

	------------------------------------------------------------------
	-- Boucle principale
	------------------------------------------------------------------
	ctx.OnRender(function(rawDt: number)
		local dt = math.clamp(rawDt, 1 / 240, 1 / 20)
		clock += dt
		runTime += dt
		local fxOn = effectsOn()

		-- Vitesse (accélère doucement, plus vite en jetpack)
		local baseSpeed = math.min(MAX_SPEED, BASE_SPEED + runTime * SPEED_RAMP)
		local wantedSpeed = jetTime > 0 and baseSpeed * 1.3 or baseSpeed
		speed += (wantedSpeed - speed) * math.min(1, dt * 2)
		local move = speed * dt
		scroll += move
		distance += move * 6

		-- Bonus
		if jetTime > 0 then
			jetTime = math.max(0, jetTime - dt)
		end
		if magnetTime > 0 then
			magnetTime = math.max(0, magnetTime - dt)
		end
		if jetTime <= 0 and magnetTime <= 0 and not pendingPower and not pickup.Active then
			powerTimer -= dt
			if powerTimer <= 0 then
				pendingPower = (random:NextNumber() < 0.5) and "Jetpack" or "Magnet"
				powerTimer = random:NextNumber(16, 26)
			end
		end

		-- Nouvelles vagues
		waveDistance += move
		if waveDistance >= WAVE_GAP then
			waveDistance -= WAVE_GAP
			spawnWave(Z_FAR)
		end

		-- Pièces dans le ciel pendant le jetpack
		if jetTime > 1.6 then
			airDistance += move
			if airDistance >= 0.5 then
				airDistance -= 0.5
				airCount += 1
				if airCount % 5 == 0 then
					airLane = math.clamp(airLane + ((random:NextNumber() < 0.5) and -1 or 1), 1, 3)
				end
				spawnCoin(airLane, Z_FAR, JET_H + 28, true)
			end
		end

		------------------------------------------------------------------
		-- Le coureur
		------------------------------------------------------------------
		wishTimer -= dt
		if wishTimer <= 0 then
			wishLane = random:NextInteger(1, 3)
			wishTimer = random:NextNumber(1.5, 3.5)
		end

		if jetTime > 0.9 then
			-- En vol : suit la traînée de pièces
			local nearest: any, nearestZ = nil, math.huge
			for _, coin in ipairs(coinsPool) do
				if coin.Active and coin.Air and coin.Z > CHAR_Z and coin.Z < nearestZ then
					nearest, nearestZ = coin, coin.Z
				end
			end
			if nearest then
				targetLane = nearest.Lane
			end
		elseif math.abs(runnerX - LANES[targetLane]) < 10 then
			chooseLane()
		end

		local previousX = runnerX
		runnerX += (LANES[targetLane] - runnerX) * math.min(1, dt * 11)
		local vx = (runnerX - previousX) / dt
		lean += (math.clamp(vx * 0.06, -15, 15) - lean) * math.min(1, dt * 12)

		-- Sauts / roulades automatiques devant les barrières
		if jetTime <= 0 and runnerH < 60 then
			local myLane = nearestLane(runnerX)
			for _, barrier in ipairs(barriers) do
				if barrier.Active and not barrier.Handled and barrier.Lane == myLane then
					local timeTo = (barrier.Z - CHAR_Z) / speed
					if timeTo > 0 and timeTo < 0.27 then
						barrier.Handled = true
						if barrier.Kind == "Low" then
							if jumpT < 0 then
								jumpT = 0
								rollT = -1
							end
						else
							rollT = 0
							jumpT = -1
						end
					end
				end
			end
		end
		if jumpT >= 0 then
			jumpT += dt / JUMP_TIME
			if jumpT >= 1 then
				jumpT = -1
			end
		end
		if rollT >= 0 then
			rollT += dt / ROLL_TIME
			if rollT >= 1 then
				rollT = -1
			end
		end

		local heightTarget = 0
		if jetTime > 0 then
			heightTarget = JET_H
		elseif jumpT >= 0 then
			heightTarget = 4 * JUMP_H * jumpT * (1 - jumpT)
		end
		local slow = jetTime > 0 or (jumpT < 0 and runnerH > JUMP_H + 8)
		runnerH += (heightTarget - runnerH) * math.min(1, dt * (slow and 4 or 30))

		-- Caméra : suit un peu le coureur (parallaxe)
		camX += (runnerX * 0.42 - camX) * math.min(1, dt * 5)
		if math.abs(camX - lastStaticCam) > 0.03 then
			lastStaticCam = camX
			updateStatic()
		end

		------------------------------------------------------------------
		-- Décor
		------------------------------------------------------------------
		local pulse = 1 + math.sin(clock * 1.6) * 0.06
		sunGlowOuter.Size = UDim2.fromOffset(84 * U * pulse, 84 * U * pulse)
		sunGlowInner.Size = UDim2.fromOffset(48 * U * (2 - pulse), 48 * U * (2 - pulse))

		for _, cloud in ipairs(clouds) do
			cloud.X -= cloud.Speed * dt
			if cloud.X < -cloud.Width then
				cloud.X += SW + cloud.Width * 2
			end
			cloud.Frame.Position = UDim2.fromOffset(cloud.X - camX * cloud.Parallax * U, cloud.Y)
		end
		skyFar.Position = UDim2.fromOffset(-SKY_MARGIN - camX * 0.07 * U, 0)
		skyNear.Position = UDim2.fromOffset(-SKY_MARGIN - camX * 0.16 * U, 0)

		for _, tie in ipairs(ties) do
			local z = TIE_START + (tie.Offset - scroll) % TIE_CYCLE
			local top = sy(0, z + TIE_DEPTH)
			local f = tie.Frame
			f.Position = UDim2.fromOffset(sx(tie.X, z + TIE_DEPTH * 0.5), top)
			f.Size = UDim2.fromOffset(TIE_HALF * 2 * U / z, math.max(1, sy(0, z) - top))
			f.BackgroundTransparency = fade(z, 3.3, 4.8)
		end

		for _, pole in ipairs(poles) do
			local z = 0.55 + (pole.Offset - scroll) % POLE_CYCLE
			local x = sx(pole.Sign * POLE_X, z)
			local topY = sy(POLE_H, z)
			local t = fade(z, 4.5, 5.9)
			local depth = depthZ(z)
			pole.Pole.Position = UDim2.fromOffset(x, sy(0, z))
			pole.Pole.Size = UDim2.fromOffset(math.max(1, 4 * U / z), POLE_H * U / z)
			pole.Pole.BackgroundTransparency = t
			pole.Pole.ZIndex = depth
			pole.Arm.Position = UDim2.fromOffset(x, topY)
			pole.Arm.Size = UDim2.fromOffset(POLE_ARM * U / z, math.max(1, 3 * U / z))
			pole.Arm.BackgroundTransparency = t
			pole.Arm.ZIndex = depth
			pole.Glow.BackgroundTransparency = 0.1 + t * 0.9
		end

		for _, panel in ipairs(panels) do
			panel.Z -= move
			if panel.Z + PANEL_LEN < 1 then
				panel.Z = random:NextNumber(8, 12)
				restylePanel(panel)
			end
			local f = panel.Frame
			if panel.Z > 8 then
				f.Visible = false
			else
				local s = panel.Side.Sign
				local xNear = sx(s * WALL_X, panel.Z)
				local xFar = sx(s * WALL_X, panel.Z + PANEL_LEN)
				local midZ = panel.Z + PANEL_LEN / 2
				local top = sy(58, midZ)
				local t = fade(panel.Z, 6.3, 8)
				f.Visible = true
				f.Position = UDim2.fromOffset(math.min(xNear, xFar) - panel.Side.Origin.X, top)
				f.Size = UDim2.fromOffset(math.abs(xNear - xFar), sy(8, midZ) - top)
				f.BackgroundTransparency = t
				panel.Label.TextTransparency = t
				panel.Stroke.Transparency = t
			end
		end

		------------------------------------------------------------------
		-- Trains
		------------------------------------------------------------------
		for _, train in ipairs(trains) do
			if train.Active then
				train.Z -= move + train.Extra * dt
				if train.Z < Z_NEAR then
					train.Active = false
					train.Body.Visible = false
					train.Roof.Visible = false
				else
					local z = train.Z
					local laneX = LANES[train.Lane]
					local x = sx(laneX, z)
					local body = train.Body
					body.Position = UDim2.fromOffset(x, sy(0, z))
					body.Size = UDim2.fromOffset(TRAIN_W * U / z, TRAIN_H * U / z)
					body.ZIndex = depthZ(z)
					-- Toit : du haut de la face avant vers le haut de l'arrière du train
					local back = z + TRAIN_LEN
					local fy = sy(TRAIN_H, z)
					local bx, by = sx(laneX, back), sy(TRAIN_H, back)
					local dx, dy = x - bx, fy - by
					local roof = train.Roof
					roof.Position = UDim2.fromOffset((x + bx) / 2, (fy + by) / 2)
					roof.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), (TRAIN_W * U / z + TRAIN_W * U / back) * 0.46)
					roof.Rotation = math.deg(math.atan2(dy, dx))
					roof.ZIndex = depthZ(z + TRAIN_LEN * 0.5)
					if train.Extra > 0 then
						-- Phares qui clignotent : il fonce vers nous !
						local blink = (math.sin(clock * 16) > 0) and 0 or 0.4
						train.HeadL.BackgroundTransparency = blink
						train.HeadR.BackgroundTransparency = 0.4 - blink
					end
				end
			end
		end

		------------------------------------------------------------------
		-- Barrières
		------------------------------------------------------------------
		for _, barrier in ipairs(barriers) do
			if barrier.Active then
				barrier.Z -= move
				if barrier.Z < Z_NEAR then
					barrier.Active = false
					barrier.Board.Visible = false
				else
					local z = barrier.Z
					local board = barrier.Board
					board.Position = UDim2.fromOffset(sx(LANES[barrier.Lane], z), sy(barrier.Bottom, z))
					board.Size = UDim2.fromOffset(BARRIER_W * U / z, (barrier.Top - barrier.Bottom) * U / z)
					board.ZIndex = depthZ(z)
					local on = math.sin(clock * 7 + barrier.Phase) > 0
					barrier.Light.BackgroundColor3 = on and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(130, 30, 34)
				end
			end
		end

		------------------------------------------------------------------
		-- Pièces (aimant, ramassage)
		------------------------------------------------------------------
		local heroScreenX = sx(runnerX, CHAR_Z)
		local heroGroundY = sy(0, CHAR_Z)
		for _, coin in ipairs(coinsPool) do
			if coin.Active then
				local previousZ = coin.Z
				local collected = false
				if magnetTime > 0 and not coin.Pulled and coin.Z < CHAR_Z + 2.6 and coin.Z > CHAR_Z - 0.2 then
					coin.Pulled = true
				end
				if coin.Pulled then
					-- Aimant : la pièce file vers le coureur (au lieu de défiler)
					local k = math.min(1, dt * 10)
					coin.X += (runnerX - coin.X) * k
					coin.H += (runnerH + 30 - coin.H) * k
					coin.Z += (CHAR_Z - coin.Z) * math.min(1, dt * 8)
					collected = math.abs(coin.Z - CHAR_Z) < 0.15 and math.abs(coin.X - runnerX) < 16
				else
					coin.Z -= move
				end
				if collected then
					-- déjà ramassée par l'aimant
				elseif previousZ >= CHAR_Z and coin.Z < CHAR_Z then
					collected = math.abs(coin.X - runnerX) < 30 and coin.H > runnerH - 12 and coin.H < runnerH + CHAR_H + 12
				end
				local z = math.max(coin.Z, 0.3)
				local px, py = sx(coin.X, z), sy(coin.H, z)
				if collected then
					collectCoin(coin, px, py)
				elseif coin.Z < Z_NEAR then
					coin.Active = false
					coin.Frame.Visible = false
				else
					coin.Phase += dt * 6
					local size = COIN_SIZE * U / z
					local spin = math.abs(math.cos(coin.Phase))
					local f = coin.Frame
					f.Position = UDim2.fromOffset(px, py)
					f.Size = UDim2.fromOffset(size * math.max(0.16, spin), size)
					f.ZIndex = depthZ(z)
					coin.Gradient.Offset = Vector2.new(math.sin(clock * 2.4 + coin.Phase * 0.3) * 0.7, 0)
					coin.Stroke.Thickness = math.max(1, size * 0.08)
				end
			end
		end

		------------------------------------------------------------------
		-- Bonus à ramasser
		------------------------------------------------------------------
		if pickup.Active then
			local previousZ = pickup.Z
			pickup.Z -= move
			local z = math.max(pickup.Z, 0.3)
			local height = 30 + math.sin(clock * 4) * 5
			local px, py = sx(LANES[pickup.Lane], z), sy(height, z)
			if previousZ >= CHAR_Z and pickup.Z < CHAR_Z and math.abs(LANES[pickup.Lane] - runnerX) < 34 then
				pickup.Active = false
				pickupGlow.Visible = false
				activatePower(pickup.Kind, px, py)
			elseif pickup.Z < Z_NEAR then
				pickup.Active = false
				pickupGlow.Visible = false
			else
				local size = 30 * U / z * (1 + math.sin(clock * 6) * 0.06)
				pickupGlow.Position = UDim2.fromOffset(px, py)
				pickupGlow.Size = UDim2.fromOffset(size, size)
				pickupGlow.Rotation = math.sin(clock * 3) * 12
				pickupGlow.ZIndex = depthZ(z)
				pickupStroke.Thickness = math.max(1, size * 0.06)
			end
		end

		------------------------------------------------------------------
		-- Pose et animation du coureur
		------------------------------------------------------------------
		runPhase += dt * (9 + speed * 1.3)
		local sinP = math.sin(runPhase)
		local liftL, liftR = math.max(0, sinP), math.max(0, -sinP)
		local armSwing = sinP * 8
		local armLength = { 0.3 * (1 - 0.35 * liftR), 0.3 * (1 - 0.35 * liftL) }
		local armAngle = { armSwing, armSwing }
		local bob = math.abs(sinP) * 2 * U
		local widthMul, heightMul = 1, 1
		local flying = jetTime > 0 or runnerH > JUMP_H + 8

		if flying then
			-- Jetpack : jambes qui pendent, bras écartés
			local dangle = math.sin(clock * 4) * 0.15
			liftL, liftR = 0.25 + dangle, 0.25 - dangle
			armLength = { 0.26, 0.26 }
			armAngle = { 38, -38 }
			bob = math.sin(clock * 5) * 1.5 * U
		elseif rollT >= 0 then
			-- Roulade : boule écrasée
			local k = math.sin(math.pi * rollT)
			widthMul, heightMul = 1 + 0.15 * k, 1 - 0.42 * k
			liftL, liftR = 0.6 * k, 0.6 * k
			armLength = { 0.24, 0.24 }
			armAngle = { -20 * k, 20 * k }
			bob = 0
		elseif jumpT >= 0 then
			-- Saut : jambes repliées, bras levés
			liftL, liftR = 0.5, 0.5
			armLength = { 0.25, 0.25 }
			armAngle = { 32, -32 }
			bob = 0
		end

		for index, leg in ipairs(legs) do
			local lift = index == 1 and liftL or liftR
			leg.Frame.Size = UDim2.fromScale(0.2, 0.34 * (1 - 0.4 * lift))
			leg.Frame.Position = UDim2.fromScale(leg.X, 0.6 - 0.03 * lift)
		end
		for index, arm in ipairs(arms) do
			arm.Frame.Size = UDim2.fromScale(0.17, armLength[index])
			arm.Frame.Rotation = armAngle[index]
		end

		local heroY = sy(runnerH, CHAR_Z) - bob
		hero.Position = UDim2.fromOffset(heroScreenX, heroY)
		hero.Size = UDim2.fromOffset(CW * widthMul, CH * heightMul)
		hero.Rotation = lean + (flying and 0 or sinP * 2)

		local shadowScale = 1 - math.clamp(runnerH / 150, 0, 0.6)
		shadow.Position = UDim2.fromOffset(heroScreenX, heroGroundY)
		shadow.Size = UDim2.fromOffset(28 * U * shadowScale, 7 * U * shadowScale)
		shadow.BackgroundTransparency = 0.62 + math.clamp(runnerH / 100, 0, 1) * 0.25

		-- Jetpack : le sac devient un réacteur
		local jet = jetTime > 0
		backpack.BackgroundColor3 = jet and JET or PACK
		pocket.BackgroundColor3 = jet and JET_DARK or PACK_DARK
		for _, flame in ipairs(flames) do
			flame.Visible = jet
			if jet then
				flame.Size = UDim2.fromScale(0.3, 0.55 + random:NextNumber() * 0.45)
			end
		end

		-- Aimant : halo qui pulse autour du coureur
		if magnetTime > 0 then
			local size = CH * (1.25 + math.sin(clock * 8) * 0.08)
			aura.Visible = true
			aura.Position = UDim2.fromOffset(heroScreenX, heroY - CH * 0.5)
			aura.Size = UDim2.fromOffset(size, size)
			auraStroke.Transparency = magnetTime < 1.5 and ((math.sin(clock * 20) > 0) and 0.2 or 0.8) or 0.2
		else
			aura.Visible = false
		end

		------------------------------------------------------------------
		-- Lignes de vitesse (jetpack / grande vitesse)
		------------------------------------------------------------------
		local wanted = 0
		if fxOn then
			wanted = jetTime > 0 and 1 or math.clamp((speed - 4.3) / 0.5, 0, 1) * 0.45
		end
		lineStrength += (wanted - lineStrength) * math.min(1, dt * 3)
		if lineStrength > 0.02 then
			linesVisible = true
			for _, line in ipairs(speedLines) do
				line.R += line.Speed * dt * (jetTime > 0 and 1.4 or 1)
				if line.R > 210 * U then
					resetSpeedLine(line)
				end
				local length = 8 * U + line.R * 0.3
				local dirX, dirY = math.cos(line.Angle), math.sin(line.Angle)
				local r = line.R + length / 2
				local f = line.Frame
				f.Visible = true
				f.Position = UDim2.fromOffset(CX + dirX * r, HY + dirY * r)
				f.Size = UDim2.fromOffset(length, math.max(1, 1.5 * U))
				f.Rotation = math.deg(line.Angle)
				local appear = math.clamp((line.R - 14 * U) / (30 * U), 0, 1)
				f.BackgroundTransparency = 1 - lineStrength * appear * 0.7
			end
		elseif linesVisible then
			linesVisible = false
			for _, line in ipairs(speedLines) do
				line.Frame.Visible = false
			end
		end

		------------------------------------------------------------------
		-- Étincelles et "+1"
		------------------------------------------------------------------
		for _, sparkle in ipairs(sparkles) do
			if sparkle.Life > 0 then
				sparkle.Life -= dt
				local f = sparkle.Frame
				if sparkle.Life <= 0 then
					f.Visible = false
				else
					sparkle.VY += 140 * U * dt
					sparkle.X += sparkle.VX * dt
					sparkle.Y += sparkle.VY * dt
					local t = sparkle.Life / 0.45
					local size = 6 * U * (0.4 + 0.6 * t)
					f.Position = UDim2.fromOffset(sparkle.X, sparkle.Y)
					f.Size = UDim2.fromOffset(size, size)
					f.Rotation = 45 + (1 - t) * 180
					f.BackgroundTransparency = 1 - t
				end
			end
		end

		for _, pop in ipairs(pops) do
			if pop.Life > 0 then
				pop.Life -= dt
				local label = pop.Label
				if pop.Life <= 0 then
					label.Visible = false
				else
					pop.Y -= 26 * U * dt
					local grow = 1 + 0.45 * math.clamp((pop.Life - 0.55) / 0.15, 0, 1)
					local t = pop.Life < 0.25 and (1 - pop.Life / 0.25) or 0
					label.Position = UDim2.fromOffset(pop.X, pop.Y)
					label.Size = UDim2.fromOffset(pop.W * grow, pop.H * grow)
					label.TextTransparency = t
					pop.Stroke.Transparency = t
				end
			end
		end

		------------------------------------------------------------------
		-- HUD
		------------------------------------------------------------------
		if coinCount ~= shownCoins then
			shownCoins = coinCount
			coinLabel.Text = ctx.Format.WithSpaces(coinCount)
		end
		local meters = math.floor(distance)
		if meters ~= shownDistance then
			shownDistance = meters
			distLabel.Text = ctx.Format.WithSpaces(meters) .. " m"
		end
		if coinPulse > 0 then
			coinPulse = math.max(0, coinPulse - dt * 5)
			coinPillScale.Scale = 1 + 0.18 * coinPulse
		end
		if jetTime > 0 or magnetTime > 0 then
			local ratio = jetTime > 0 and jetTime / JET_TIME or magnetTime / MAGNET_TIME
			powerFill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		elseif powerPill.Visible then
			powerPill.Visible = false
		end
	end)
end

function Runner.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Runner
