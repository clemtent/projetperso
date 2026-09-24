--[[
	Runner (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Runner

	Un "jeu de course infini" qui tourne tout seul dans un coin de l'écran,
	comme une vidéo de téléphone qu'on regarde du coin de l'œil :
	  - 3 voies en perspective (rails, traverses qui défilent vers nous),
	    murs colorés sur les côtés, lampadaires, ciel, nuages, soleil ;
	  - des trains et des barrières arrivent du fond et grossissent ;
	  - le coureur (vu de dos, dessiné en formes) change de voie avec un
	    petit saut, saute les barrières et ramasse les pièces ;
	  - score de pièces, distance, record, barre de lecture "vidéo" et
	    sous-titres absurdes. De temps en temps... il se prend une barrière.
	Tout est dessiné avec des Frames. Purement visuel : aucun appel serveur.
]]

local Debris = game:GetService("Debris")

local Runner = {}
Runner.Slot = "L3"

----------------------------------------------------------------------
-- Réglages (unités "monde" = pixels à la profondeur z = 1)
----------------------------------------------------------------------
local BEZEL = 6 -- bord du "téléphone"
local Z_NEAR = 0.6 -- en dessous : l'objet est passé derrière la caméra
local Z_FAR = 9 -- apparition au loin
local CHAR_Z = 1.45 -- profondeur du coureur
local LANES = { -112, 0, 112 } -- centre des 3 voies
local RAIL_OFFSET = 36 -- écart des rails autour du centre d'une voie
local TRACK_HALF = 172 -- demi-largeur du ballast
local WALL_X = 250 -- position des murs
local WALL_H = 150 -- hauteur des murs
local POLE_X = 208 -- lampadaires
local TIE_COUNT = 11 -- traverses par voie
local TIE_GAP = 0.72
local TIE_DEPTH = 0.09
local POLE_COUNT = 3 -- lampadaires par côté
local POLE_GAP = 2.3
local WAVE_GAP = 3.1 -- distance entre deux vagues d'obstacles
local LOOK_AHEAD = 2.6 -- distance à laquelle le coureur "voit" les trains
local JUMP_TIME = 0.6
local JUMP_HEIGHT = 40
local BASE_SPEED = 3
local MAX_SPEED = 4.6
local SPEED_RAMP = 0.025 -- gain de vitesse par seconde
local VIDEO_LENGTH = 24 -- durée de la fausse barre de lecture (s)

local TRAIN_COLORS = {
	Color3.fromRGB(235, 72, 72),
	Color3.fromRGB(60, 140, 235),
	Color3.fromRGB(255, 186, 40),
	Color3.fromRGB(70, 190, 120),
	Color3.fromRGB(160, 90, 220),
}

-- Sous-titres façon "vidéo virale"
local CAPTIONS = {
	"attends la fin 😳",
	"il est trop fort",
	"ASMR de rails 🚆",
	"niveau 9999",
	"personne ne l'arrête",
	"POV : tu révises",
	"partie 47 sans pause",
	"il court depuis 2019",
	"ses genoux vont bien ?",
	"regarde ses baskets 👟",
	"la casquette tient toujours",
	"record du monde ??",
	"ce son sur les rails 😌",
	"part 2 dans les coms",
}

-- Commentaires après une chute
local CRASH_LINES = {
	"Il n'a pas vu la barrière.",
	"Il regardait son téléphone.",
	"C'est la faute du lag.",
	"Même les pros tombent.",
	"Il avait mis ses lacets ensemble.",
	"La barrière a triché.",
	"On coupe ça au montage.",
}

function Runner.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()

	local slotW = container.Size.X.Offset > 0 and container.Size.X.Offset or 384
	local slotH = container.Size.Y.Offset > 0 and container.Size.Y.Offset or 268
	local SW = slotW - BEZEL * 2
	local SH = slotH - BEZEL * 2
	local CX = SW / 2
	local HY = math.floor(SH * 0.36) -- ligne d'horizon
	local G = SH + 10 - HY -- hauteur de la caméra (sol à z = 1 : juste sous l'écran)
	local VP = Vector2.new(CX, HY) -- point de fuite

	-- Projection monde -> écran
	local function project(wx: number, wy: number, z: number): (number, number)
		return CX + wx / z, HY + (G - wy) / z
	end

	-- Ordre d'affichage selon la profondeur (plus proche = au-dessus)
	local function depthZ(z: number): number
		return 10 + math.clamp(math.floor((Z_FAR + 3 - z) * 5), 0, 70)
	end

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	------------------------------------------------------------------
	-- Cadre "téléphone" + écran
	------------------------------------------------------------------
	local device = Create("Frame", {
		Name = "Device",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(26, 26, 34),
		BorderSizePixel = 0,
		Parent = container,
	})
	UIUtil.Corner(device, 16)
	UIUtil.Stroke(device, Theme.Colors.Border, 2)

	local screen = Create("Frame", {
		Name = "Screen",
		Position = UDim2.fromOffset(BEZEL, BEZEL),
		Size = UDim2.fromOffset(SW, SH),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = device,
	})
	-- Ciel : bleu en haut, pêche vers l'horizon
	local horizonRatio = math.clamp(HY / SH, 0.1, 0.9)
	UIUtil.Gradient(
		screen,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(86, 168, 255)),
			ColorSequenceKeypoint.new(horizonRatio * 0.85, Color3.fromRGB(178, 222, 255)),
			ColorSequenceKeypoint.new(horizonRatio, Color3.fromRGB(255, 222, 186)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 222, 186)),
		}),
		90
	)

	-- Soleil (halo + disque)
	local sunX, sunY = SW * 0.8, HY - 38
	local sunGlow = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(sunX, sunY),
		Size = UDim2.fromOffset(62, 62),
		BackgroundColor3 = Color3.fromRGB(255, 244, 190),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = screen,
	})
	UIUtil.Corner(sunGlow, UDim.new(1, 0))
	local sun = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(sunX, sunY),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Color3.fromRGB(255, 226, 120),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = screen,
	})
	UIUtil.Corner(sun, UDim.new(1, 0))

	-- Nuages (3 bulles blanches chacun), qui dérivent lentement
	local clouds = {}
	for i = 1, 3 do
		local width = random:NextNumber(46, 70)
		local cloud = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(SW * (i - 0.6) / 3, random:NextNumber(14, HY - 34)),
			Size = UDim2.fromOffset(width, width * 0.42),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = screen,
		})
		for _, part in ipairs({ { 0, 0.35, 0.5, 0.65 }, { 0.28, 0, 0.45, 1 }, { 0.55, 0.25, 0.45, 0.75 } }) do
			local puff = Create("Frame", {
				Position = UDim2.fromScale(part[1], part[2]),
				Size = UDim2.fromScale(part[3], part[4]),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = cloud,
			})
			UIUtil.Corner(puff, UDim.new(1, 0))
		end
		table.insert(clouds, { Frame = cloud, X = SW * (i - 0.6) / 3, Y = cloud.Position.Y.Offset, Speed = random:NextNumber(4, 9) })
	end

	-- Silhouette de ville à l'horizon
	local x = -6
	while x < SW do
		local width = random:NextInteger(16, 32)
		local height = random:NextInteger(14, 44)
		local building = Create("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset(x, HY + 1),
			Size = UDim2.fromOffset(width, height),
			BackgroundColor3 = (random:NextNumber() < 0.5) and Color3.fromRGB(168, 176, 228) or Color3.fromRGB(150, 158, 214),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = screen,
		})
		if random:NextNumber() < 0.3 then
			UIUtil.Corner(building, 4)
		end
		x += width + random:NextInteger(-4, 4)
	end

	------------------------------------------------------------------
	-- Décor en perspective : murs, sol, ballast (demi-plans découpés)
	------------------------------------------------------------------

	-- Un grand cadre tourné dont un bord suit la droite p1 -> p2, du côté de `toward`
	local function halfPlane(parent: Instance, origin: Vector2, p1: Vector2, p2: Vector2, toward: Vector2, color: Color3, z: number)
		local delta = p2 - p1
		local length = delta.Magnitude
		if length < 1e-3 then
			return
		end
		local dir = delta / length
		local normal = Vector2.new(-dir.Y, dir.X)
		if (toward - p1):Dot(normal) < 0 then
			normal = -normal
		end
		local big = 900
		local center = (p1 + p2) / 2 + normal * (big / 2) - origin
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(length + big * 2, big),
			Rotation = math.deg(math.atan2(dir.Y, dir.X)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = parent,
		})
	end

	-- Trait entre deux points
	local function line(parent: Instance, p1: Vector2, p2: Vector2, thickness: number, color: Color3, z: number): Frame
		local delta = p2 - p1
		local mid = (p1 + p2) / 2
		return Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(mid.X, mid.Y),
			Size = UDim2.fromOffset(delta.Magnitude, thickness),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = parent,
		})
	end

	local SIDES = {
		{ Sign = -1, Wall = Color3.fromRGB(238, 150, 100), Band = Color3.fromRGB(255, 92, 150), Lower = Color3.fromRGB(214, 122, 82) },
		{ Sign = 1, Wall = Color3.fromRGB(132, 150, 232), Band = Color3.fromRGB(0, 208, 220), Lower = Color3.fromRGB(106, 120, 206) },
	}
	local groundColor = Color3.fromRGB(176, 166, 154)
	local bedColor = Color3.fromRGB(122, 110, 102)
	local below = Vector2.new(CX, SH + 200) -- point toujours "sous" les droites qui passent par le point de fuite

	for _, side in ipairs(SIDES) do
		local s = side.Sign
		local originX = s < 0 and 0 or CX
		local clip = Create("Frame", {
			Name = s < 0 and "LeftSide" or "RightSide",
			Position = UDim2.fromOffset(originX, 0),
			Size = UDim2.fromOffset(s < 0 and CX or SW - CX, SH),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 4,
			Parent = screen,
		})
		local origin = Vector2.new(originX, 0)
		local function wallPoint(height: number): Vector2
			local px, py = project(s * WALL_X, height, 1)
			return Vector2.new(px, py)
		end
		halfPlane(clip, origin, VP, wallPoint(WALL_H), below, side.Wall, 1)
		halfPlane(clip, origin, VP, wallPoint(100), below, side.Band, 2)
		halfPlane(clip, origin, VP, wallPoint(80), below, side.Lower, 3)
		halfPlane(clip, origin, VP, wallPoint(0), below, groundColor, 4)
		local bx, by = project(s * TRACK_HALF, 0, 1)
		halfPlane(clip, origin, VP, Vector2.new(bx, by), below, bedColor, 5)
		-- Arête claire en haut du mur
		local cap = line(clip, VP - origin, wallPoint(WALL_H) - origin, 3, Color3.new(1, 1, 1), 6)
		cap.BackgroundTransparency = 0.35
	end

	-- Rails (fixes) : dégradé clair -> sombre dans l'épaisseur
	for _, laneX in ipairs(LANES) do
		for _, offset in ipairs({ -RAIL_OFFSET, RAIL_OFFSET }) do
			local px, py = project(laneX + offset, 0, 0.95)
			local rail = line(screen, VP, Vector2.new(px, py), 3, Color3.new(1, 1, 1), 6)
			UIUtil.Gradient(rail, ColorSequence.new(Color3.fromRGB(235, 238, 245), Color3.fromRGB(90, 92, 105)), 90)
		end
	end

	-- Brume à l'horizon (adoucit le point de fuite)
	local fog = Create("Frame", {
		Position = UDim2.fromOffset(0, HY - 8),
		Size = UDim2.fromOffset(SW, 40),
		BackgroundColor3 = Color3.fromRGB(255, 240, 225),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = screen,
	})
	local fogGradient = UIUtil.Gradient(fog, ColorSequence.new(Color3.fromRGB(255, 240, 225)), 90)
	fogGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})

	------------------------------------------------------------------
	-- Traverses et lampadaires (réutilisés en boucle)
	------------------------------------------------------------------
	local ties = {}
	for laneIndex, laneX in ipairs(LANES) do
		for i = 1, TIE_COUNT do
			local tie = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(128, 88, 60),
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = screen,
			})
			table.insert(ties, { Frame = tie, X = laneX, Index = i, Lane = laneIndex })
		end
	end

	local poles = {}
	for _, side in ipairs(SIDES) do
		for i = 1, POLE_COUNT do
			local pole = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = Color3.fromRGB(70, 72, 86),
				BorderSizePixel = 0,
				Parent = screen,
			})
			local arm = Create("Frame", {
				AnchorPoint = Vector2.new(side.Sign < 0 and 0 or 1, 0.5),
				BackgroundColor3 = Color3.fromRGB(70, 72, 86),
				BorderSizePixel = 0,
				Parent = screen,
			})
			local bulb = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(side.Sign < 0 and 0.85 or 0.15, 0.4),
				Size = UDim2.fromScale(0.4, 1.8),
				BackgroundColor3 = Color3.fromRGB(255, 238, 150),
				BorderSizePixel = 0,
				Parent = arm,
			})
			UIUtil.Corner(bulb, UDim.new(0.5, 0))
			table.insert(poles, { Pole = pole, Arm = arm, Sign = side.Sign, Index = i })
		end
	end

	------------------------------------------------------------------
	-- Le coureur (vu de dos)
	------------------------------------------------------------------
	local groundY = HY + G / CHAR_Z
	local charW, charH = 46, 72

	local shadow = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(40, 10),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		ZIndex = depthZ(CHAR_Z) - 1,
		Parent = screen,
	})
	UIUtil.Corner(shadow, UDim.new(1, 0))

	local hero = Create("Frame", {
		Name = "Hero",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(charW, charH),
		BackgroundTransparency = 1,
		ZIndex = depthZ(CHAR_Z),
		Parent = screen,
	})

	local function part(props: { [string]: any }, radius: UDim?): Frame
		props.BorderSizePixel = 0
		local frame = Create("Frame", props)
		UIUtil.Corner(frame, radius or UDim.new(0.3, 0))
		return frame
	end

	local legGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(52, 72, 146)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(52, 72, 146)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(250, 250, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 215, 225)),
	})
	local legL = part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.32, 0.66), Size = UDim2.fromScale(0.2, 0.34), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1, Parent = hero })
	local legR = part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.68, 0.66), Size = UDim2.fromScale(0.2, 0.34), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1, Parent = hero })
	UIUtil.Gradient(legL, legGradient, 90)
	UIUtil.Gradient(legR, legGradient, 90)
	local hoodie = Color3.fromRGB(255, 122, 48)
	local hoodieDark = Color3.fromRGB(222, 92, 30)
	local armL = part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.1, 0.36), Size = UDim2.fromScale(0.17, 0.3), BackgroundColor3 = hoodieDark, ZIndex = 1, Parent = hero })
	local armR = part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.9, 0.36), Size = UDim2.fromScale(0.17, 0.3), BackgroundColor3 = hoodieDark, ZIndex = 1, Parent = hero })
	local body = part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.31), Size = UDim2.fromScale(0.8, 0.42), BackgroundColor3 = hoodie, ZIndex = 2, Parent = hero })
	part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.12), Size = UDim2.fromScale(0.62, 0.7), BackgroundColor3 = Color3.fromRGB(38, 172, 160), ZIndex = 3, Parent = body }, UDim.new(0.25, 0))
	local head = part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(0.56, 0.36), BackgroundColor3 = Color3.fromRGB(72, 46, 32), ZIndex = 4, Parent = hero }, UDim.new(1, 0))
	local cap = part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, -0.06), Size = UDim2.fromScale(1, 0.56), BackgroundColor3 = Color3.fromRGB(232, 40, 62), ZIndex = 5, Parent = head }, UDim.new(0.5, 0))
	part({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.fromScale(0.56, 0.32), BackgroundColor3 = Color3.fromRGB(170, 20, 40), ZIndex = 6, Parent = cap }, UDim.new(0.4, 0))

	------------------------------------------------------------------
	-- HUD (pièces, distance, record, barre de lecture, sous-titres)
	------------------------------------------------------------------
	local coinPill = Create("Frame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(74, 24),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 90,
		Parent = screen,
	})
	UIUtil.Corner(coinPill, UDim.new(1, 0))
	local coinIcon = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(17, 17),
		BackgroundColor3 = Color3.fromRGB(255, 204, 40),
		BorderSizePixel = 0,
		ZIndex = 91,
		Parent = coinPill,
	})
	UIUtil.Corner(coinIcon, UDim.new(1, 0))
	UIUtil.Stroke(coinIcon, Color3.fromRGB(200, 130, 10), 1.5)
	local coinLabel = UIUtil.Label({
		Text = "0",
		Font = Theme.Fonts.Number,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(26, 2),
		Size = UDim2.new(1, -30, 1, -4),
		MaxTextSize = 18,
		ZIndex = 91,
		Parent = coinPill,
	})
	local coinScale = Create("UIScale", { Parent = coinPill })

	local distanceLabel = UIUtil.Label({
		Text = "0 m",
		Font = Theme.Fonts.Number,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(120, 24),
		MaxTextSize = 22,
		ZIndex = 90,
		Parent = screen,
	})
	local distanceStroke = UIUtil.Stroke(distanceLabel, Color3.fromRGB(20, 20, 30), 2)
	distanceStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local bestLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(255, 236, 140),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 29),
		Size = UDim2.fromOffset(140, 15),
		MaxTextSize = 13,
		ZIndex = 90,
		Parent = screen,
	})
	local bestStroke = UIUtil.Stroke(bestLabel, Color3.fromRGB(20, 20, 30), 1.5)
	bestStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Barre de lecture (comme une vidéo)
	local progressBack = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 90,
		Parent = screen,
	})
	local progressFill = Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Red,
		BorderSizePixel = 0,
		ZIndex = 91,
		Parent = progressBack,
	})
	local progressKnob = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Colors.Red,
		BorderSizePixel = 0,
		ZIndex = 92,
		Parent = progressBack,
	})
	UIUtil.Corner(progressKnob, UDim.new(1, 0))
	local timeLabel = UIUtil.Label({
		Text = "0:00 / 0:24",
		Font = Theme.Fonts.Mono,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -7),
		Size = UDim2.fromOffset(90, 13),
		MaxTextSize = 12,
		ZIndex = 90,
		Parent = screen,
	})
	local timeStroke = UIUtil.Stroke(timeLabel, Color3.new(0, 0, 0), 1, 0.4)
	timeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Sous-titre "vidéo virale"
	local caption = UIUtil.Label({
		Text = "",
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, HY + 28),
		Size = UDim2.fromOffset(SW - 40, 26),
		MaxTextSize = 22,
		ZIndex = 93,
		Parent = screen,
	})
	local captionStroke = UIUtil.Stroke(caption, Color3.new(0, 0, 0), 2.5, 1)
	captionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local captionScale = Create("UIScale", { Parent = caption })

	-- Flash + message de chute
	local flash = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 95,
		Parent = screen,
	})
	local crashTitle = UIUtil.Label({
		Text = "💥 AÏE !",
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Color3.fromRGB(255, 220, 60),
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(SW - 40, 48),
		MaxTextSize = 44,
		ZIndex = 96,
		Parent = screen,
	})
	local crashTitleStroke = UIUtil.Stroke(crashTitle, Color3.fromRGB(30, 20, 20), 3, 1)
	crashTitleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local crashTitleScale = Create("UIScale", { Parent = crashTitle })
	local crashSub = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(SW - 30, 22),
		MaxTextSize = 18,
		ZIndex = 96,
		Parent = screen,
	})
	local crashSubStroke = UIUtil.Stroke(crashSub, Color3.fromRGB(30, 20, 20), 2, 1)
	crashSubStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	------------------------------------------------------------------
	-- Obstacles et pièces
	------------------------------------------------------------------
	local objects = {} -- { Kind, Lane, Z, Frame, Width, Height, Lift, Phase }

	local function spawnTrain(lane: number)
		local color = TRAIN_COLORS[random:NextInteger(1, #TRAIN_COLORS)]
		local face = Create("Frame", {
			Name = "Train",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = screen,
		})
		UIUtil.Corner(face, UDim.new(0.12, 0))
		UIUtil.Gradient(face, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 195)), 90)
		local windshield = Create("Frame", {
			Position = UDim2.fromScale(0.1, 0.1),
			Size = UDim2.fromScale(0.8, 0.32),
			BackgroundColor3 = Color3.fromRGB(40, 52, 76),
			BorderSizePixel = 0,
			Parent = face,
		})
		UIUtil.Corner(windshield, UDim.new(0.2, 0))
		UIUtil.Gradient(windshield, ColorSequence.new(Color3.fromRGB(140, 220, 255), Color3.fromRGB(60, 80, 120)), 60)
		Create("Frame", {
			Position = UDim2.fromScale(0, 0.52),
			Size = UDim2.fromScale(1, 0.09),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Parent = face,
		})
		for _, lightX in ipairs({ 0.2, 0.8 }) do
			local light = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(lightX, 0.75),
				Size = UDim2.fromScale(0.17, 0.13),
				BackgroundColor3 = Color3.fromRGB(255, 246, 170),
				BorderSizePixel = 0,
				Parent = face,
			})
			UIUtil.Corner(light, UDim.new(1, 0))
		end
		table.insert(objects, { Kind = "Train", Lane = lane, Z = Z_FAR, Frame = face, Width = 98, Height = 118, Lift = 0, Phase = 0 })
	end

	local function spawnBarrier(lane: number)
		local root = Create("Frame", {
			Name = "Barrier",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Parent = screen,
		})
		for _, legX in ipairs({ 0.14, 0.86 }) do
			Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(legX, 0.45),
				Size = UDim2.fromScale(0.08, 0.55),
				BackgroundColor3 = Color3.fromRGB(70, 70, 82),
				BorderSizePixel = 0,
				Parent = root,
			})
		end
		local board = Create("Frame", {
			Size = UDim2.fromScale(1, 0.55),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = root,
		})
		UIUtil.Corner(board, UDim.new(0.2, 0))
		-- Rayures rouges et blanches (dégradé à bords nets)
		local keypoints = {}
		local stripes = 6
		for i = 0, stripes - 1 do
			local c = (i % 2 == 0) and Color3.fromRGB(232, 36, 48) or Color3.new(1, 1, 1)
			table.insert(keypoints, ColorSequenceKeypoint.new(i / stripes, c))
			table.insert(keypoints, ColorSequenceKeypoint.new(math.min(1, (i + 1) / stripes - 0.001), c))
		end
		keypoints[#keypoints] = ColorSequenceKeypoint.new(1, keypoints[#keypoints].Value)
		UIUtil.Gradient(board, ColorSequence.new(keypoints), 20)
		table.insert(objects, { Kind = "Barrier", Lane = lane, Z = Z_FAR, Frame = root, Width = 94, Height = 44, Lift = 0, Phase = 0 })
	end

	local function spawnCoin(lane: number, z: number)
		local coin = Create("Frame", {
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 208, 40),
			BorderSizePixel = 0,
			Parent = screen,
		})
		UIUtil.Corner(coin, UDim.new(1, 0))
		UIUtil.Gradient(coin, ColorSequence.new(Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 176, 20)), 90)
		local inner = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.55, 0.55),
			BackgroundColor3 = Color3.fromRGB(230, 150, 10),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = coin,
		})
		UIUtil.Corner(inner, UDim.new(1, 0))
		table.insert(objects, { Kind = "Coin", Lane = lane, Z = z, Frame = coin, Width = 24, Height = 24, Lift = 26, Phase = random:NextNumber(0, 6) })
	end

	local function spawnWave()
		local free = random:NextInteger(1, 3)
		local kinds = {}
		for lane = 1, 3 do
			if lane ~= free then
				local roll = random:NextNumber()
				if roll < 0.45 then
					spawnTrain(lane)
					kinds[lane] = "Train"
				elseif roll < 0.8 then
					spawnBarrier(lane)
					kinds[lane] = "Barrier"
				end
			end
		end
		-- Pièces : souvent sur la voie libre, parfois derrière une barrière
		local coinLane = free
		if random:NextNumber() < 0.3 then
			local other = random:NextInteger(1, 3)
			if kinds[other] ~= "Train" then
				coinLane = other
			end
		end
		for k = 0, random:NextInteger(3, 5) - 1 do
			spawnCoin(coinLane, Z_FAR + 0.45 + k * 0.42)
		end
	end

	local function removeObject(index: number)
		local object = objects[index]
		table.remove(objects, index)
		if object and object.Frame then
			object.Frame:Destroy()
		end
	end

	local function clearObjects()
		for i = #objects, 1, -1 do
			removeObject(i)
		end
	end

	------------------------------------------------------------------
	-- État de la partie
	------------------------------------------------------------------
	local speed = BASE_SPEED
	local runTime = 0
	local scroll = 0 -- défilement total (pour traverses / lampadaires)
	local waveTravel = WAVE_GAP * 0.6
	local coins = 0
	local distance = 0
	local shownDistance = -1
	local best = 0
	local state = "run" -- "run" | "crash"
	local crashTime = 0
	local lane = 2 -- voie visée
	local heroX = LANES[2] -- position latérale actuelle (monde)
	local jumpTime = JUMP_TIME -- >= JUMP_TIME : au sol
	local jumpScale = 1
	local phase = 0
	local decideTimer = 0
	local blunderAt = os.clock() + random:NextNumber(45, 90)
	local captionTimer = random:NextNumber(4, 8)
	local videoTime = 0
	local shownSecond = -1
	local clock = 0

	local function currentLane(): number
		local bestLane, bestDist = 2, math.huge
		for i, laneX in ipairs(LANES) do
			local d = math.abs(heroX - laneX)
			if d < bestDist then
				bestLane, bestDist = i, d
			end
		end
		return bestLane
	end

	-- Premier objet d'un type dans une voie, entre deux profondeurs
	local function findInLane(laneIndex: number, kind: string, zMin: number, zMax: number)
		for _, object in ipairs(objects) do
			if object.Kind == kind and object.Lane == laneIndex and object.Z >= zMin and object.Z <= zMax then
				return object
			end
		end
		return nil
	end

	local function coinsAhead(laneIndex: number): number
		local count = 0
		for _, object in ipairs(objects) do
			if object.Kind == "Coin" and object.Lane == laneIndex and object.Z > CHAR_Z and object.Z < CHAR_Z + 3.5 then
				count += 1
			end
		end
		return count
	end

	local function laneSafe(laneIndex: number): boolean
		return findInLane(laneIndex, "Train", CHAR_Z - 0.35, CHAR_Z + LOOK_AHEAD + 0.6) == nil
	end

	local function startJump(scale: number)
		if jumpTime < JUMP_TIME then
			return
		end
		jumpTime = 0
		jumpScale = scale
	end

	local function goToLane(target: number)
		if target ~= lane then
			lane = target
			startJump(0.45) -- petit saut d'esquive
		end
	end

	local function showCaption(text: string)
		caption.Text = text
		caption.TextTransparency = 0
		captionStroke.Transparency = 0
		captionScale.Scale = 0.4
		UIUtil.Tween(captionScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(2.6, function()
			if ctx.IsAlive() and caption.Text == text then
				UIUtil.Tween(caption, 0.3, { TextTransparency = 1 })
				UIUtil.Tween(captionStroke, 0.3, { Transparency = 1 })
			end
		end)
	end

	local function collectCoin(index: number)
		local object = objects[index]
		table.remove(objects, index)
		coins += 1
		coinLabel.Text = tostring(coins)
		coinScale.Scale = 1.25
		UIUtil.Tween(coinScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		if coins % 25 == 0 then
			if effectsOn() then
				ctx.Effects.Burst(screen, UDim2.fromOffset(40, 20), Color3.fromRGB(255, 208, 40), 6)
			end
			showCaption(coins .. " pièces !! 🤑")
		end
		local frame = object.Frame
		UIUtil.Tween(frame, 0.35, { Position = UDim2.fromOffset(20, 20), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 0.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(frame, 0.4)
	end

	local function crash()
		if state == "crash" then
			return
		end
		state = "crash"
		crashTime = 0
		best = math.max(best, math.floor(distance))
		flash.BackgroundTransparency = 0.1
		UIUtil.Tween(flash, 0.45, { BackgroundTransparency = 1 })
		UIUtil.Tween(hero, 0.35, { Rotation = 80 }, Enum.EasingStyle.Back)
		crashSub.Text = CRASH_LINES[random:NextInteger(1, #CRASH_LINES)]
		crashTitle.Text = "💥 AÏE !"
		crashTitleScale.Scale = 0.3
		UIUtil.Tween(crashTitleScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		UIUtil.Tween(crashTitle, 0.15, { TextTransparency = 0 })
		UIUtil.Tween(crashTitleStroke, 0.15, { Transparency = 0 })
		UIUtil.Tween(crashSub, 0.3, { TextTransparency = 0 })
		UIUtil.Tween(crashSubStroke, 0.3, { Transparency = 0 })
	end

	local function restart()
		state = "run"
		clearObjects()
		speed = BASE_SPEED
		runTime = 0
		waveTravel = WAVE_GAP * 0.4
		coins = 0
		coinLabel.Text = "0"
		distance = 0
		lane = 2
		heroX = LANES[2]
		jumpTime = JUMP_TIME
		hero.Rotation = 0
		bestLabel.Text = best > 0 and ("Record : " .. best .. " m") or ""
		blunderAt = os.clock() + random:NextNumber(45, 90)
		UIUtil.Tween(crashTitle, 0.25, { TextTransparency = 1 })
		UIUtil.Tween(crashTitleStroke, 0.25, { Transparency = 1 })
		UIUtil.Tween(crashSub, 0.25, { TextTransparency = 1 })
		UIUtil.Tween(crashSubStroke, 0.25, { Transparency = 1 })
		showCaption("nouvelle partie 🔁")
	end

	------------------------------------------------------------------
	-- Boucle d'animation
	------------------------------------------------------------------
	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt

		-- Nuages
		for _, cloud in ipairs(clouds) do
			cloud.X -= cloud.Speed * dt
			if cloud.X < -50 then
				cloud.X = SW + 50
			end
			cloud.Frame.Position = UDim2.fromOffset(cloud.X, cloud.Y)
		end

		-- Barre de lecture (boucle)
		videoTime = (videoTime + dt) % VIDEO_LENGTH
		local ratio = videoTime / VIDEO_LENGTH
		progressFill.Size = UDim2.fromScale(ratio, 1)
		progressKnob.Position = UDim2.fromScale(ratio, 0.5)
		local second = math.floor(videoTime)
		if second ~= shownSecond then
			shownSecond = second
			timeLabel.Text = string.format("0:%02d / 0:%02d", second, VIDEO_LENGTH)
		end

		-- Vitesse du monde
		if state == "run" then
			runTime += dt
			speed = math.min(MAX_SPEED, BASE_SPEED + runTime * SPEED_RAMP)
		else
			speed = math.max(0, speed - dt * 12)
		end
		local travel = speed * dt
		scroll += travel
		distance += travel * 8

		-- Traverses
		local tieSpan = TIE_COUNT * TIE_GAP
		for _, tie in ipairs(ties) do
			local z = 0.95 + ((tie.Index - 1) * TIE_GAP - scroll) % tieSpan
			local top = HY + G / (z + TIE_DEPTH)
			local bottom = HY + G / z
			local frame = tie.Frame
			if top > SH then
				frame.Visible = false
			else
				frame.Visible = true
				frame.Position = UDim2.fromOffset(CX + tie.X / z, top)
				frame.Size = UDim2.fromOffset(92 / z, math.max(1, bottom - top))
			end
		end

		-- Lampadaires
		local poleSpan = POLE_COUNT * POLE_GAP
		for _, pole in ipairs(poles) do
			local z = 0.7 + ((pole.Index - 1) * POLE_GAP + (pole.Sign > 0 and POLE_GAP * 0.5 or 0) - scroll) % poleSpan
			local px, py = project(pole.Sign * POLE_X, 0, z)
			local zIndex = depthZ(z)
			pole.Pole.Position = UDim2.fromOffset(px, py)
			pole.Pole.Size = UDim2.fromOffset(math.max(1, 6 / z), 124 / z)
			pole.Pole.ZIndex = zIndex
			local ax, ay = project(pole.Sign * POLE_X, 120, z)
			pole.Arm.Position = UDim2.fromOffset(ax, ay)
			pole.Arm.Size = UDim2.fromOffset(34 / z, math.max(1, 4 / z))
			pole.Arm.ZIndex = zIndex
		end

		-- Nouvelles vagues
		if state == "run" then
			waveTravel += travel
			if waveTravel >= WAVE_GAP then
				waveTravel -= WAVE_GAP
				spawnWave()
			end
		end

		-- Décisions du coureur
		local effLane = currentLane()
		if state == "run" then
			if findInLane(lane, "Train", CHAR_Z - 0.3, CHAR_Z + LOOK_AHEAD) then
				-- Un train arrive : on cherche la meilleure voie libre
				local bestLane, bestScore = nil, -math.huge
				for candidate = 1, 3 do
					if candidate ~= lane and laneSafe(candidate) then
						local score = -math.abs(candidate - lane) + coinsAhead(candidate) * 0.3 + random:NextNumber() * 0.1
						if score > bestScore then
							bestLane, bestScore = candidate, score
						end
					end
				end
				if bestLane then
					goToLane(bestLane)
				end
			else
				decideTimer -= dt
				if decideTimer <= 0 then
					decideTimer = random:NextNumber(0.25, 0.5)
					-- Va chercher les pièces (une voie à la fois)
					local here = coinsAhead(lane)
					for _, step in ipairs({ -1, 1 }) do
						local candidate = lane + step
						if candidate >= 1 and candidate <= 3 and laneSafe(candidate) and coinsAhead(candidate) > here and random:NextNumber() < 0.75 then
							goToLane(candidate)
							break
						end
					end
				end
			end

			-- Barrière juste devant : on saute (sauf quand c'est l'heure de la bêtise)
			local reach = CHAR_Z + 0.2 + speed * 0.1
			local barrier = findInLane(effLane, "Barrier", CHAR_Z, reach) or findInLane(lane, "Barrier", CHAR_Z, reach)
			if barrier then
				if blunderAt == math.huge or os.clock() >= blunderAt then
					blunderAt = math.huge -- il "oublie" de sauter
				elseif jumpTime >= JUMP_TIME then
					startJump(1)
				elseif jumpScale < 1 then
					-- Petit saut d'esquive en cours : on le transforme en grand saut
					if jumpTime > 0.3 then
						jumpTime = 0
					end
					jumpScale = 1
				end
			end
		end

		-- Mouvement latéral + saut
		local targetX = LANES[lane]
		heroX += (targetX - heroX) * math.min(1, dt * 14)
		local height = 0
		if jumpTime < JUMP_TIME then
			jumpTime += dt
			height = math.sin(math.pi * math.clamp(jumpTime / JUMP_TIME, 0, 1)) * JUMP_HEIGHT * jumpScale
		end

		-- Objets (déplacement, collisions)
		for i = #objects, 1, -1 do
			local object = objects[i]
			local prevZ = object.Z
			object.Z -= travel
			if object.Z < Z_NEAR then
				removeObject(i)
			else
				local z = object.Z
				local frame = object.Frame
				local gx, gy = project(LANES[object.Lane], object.Lift, z)
				local width = object.Width / z
				if object.Kind == "Coin" then
					width *= math.max(0.18, math.abs(math.cos(clock * 5 + object.Phase)))
				end
				frame.Visible = z <= Z_FAR + 2.5
				frame.Position = UDim2.fromOffset(gx, gy)
				frame.Size = UDim2.fromOffset(width, object.Height / z)
				frame.ZIndex = depthZ(z)

				-- Test sur le trajet parcouru pendant l'image ([z, prevZ]) et non sur
				-- un seul point : à faible FPS, un objet peut sauter toute la fenêtre
				if state == "run" and object.Lane == effLane and prevZ > CHAR_Z - 0.12 and z < CHAR_Z + 0.12 then
					if object.Kind == "Coin" then
						collectCoin(i)
					elseif object.Kind == "Barrier" and height < 14 and z <= CHAR_Z then
						crash()
					elseif object.Kind == "Train" and z <= CHAR_Z + 0.05 then
						crash()
					end
				end
			end
		end

		-- Dessin du coureur
		local screenX = CX + heroX / CHAR_Z
		local running = state == "run"
		if running then
			phase += dt * (10 + speed * 2)
		end
		local bob = running and math.abs(math.sin(phase)) * 3 or 0
		hero.Position = UDim2.fromOffset(screenX, groundY - height - bob + (running and 0 or 10))
		if running then
			hero.Rotation = math.clamp((targetX - heroX) * 0.12, -14, 14)
		end
		if height > 2 then
			legL.Position = UDim2.fromScale(0.32, 0.6)
			legR.Position = UDim2.fromScale(0.68, 0.6)
			armL.Rotation = -150
			armR.Rotation = 150
		else
			local swing = math.sin(phase)
			legL.Position = UDim2.fromScale(0.32, 0.66 + swing * 0.05)
			legR.Position = UDim2.fromScale(0.68, 0.66 - swing * 0.05)
			armL.Rotation = swing * 35
			armR.Rotation = swing * 35
		end
		local shadowScale = 1 - math.clamp(height / JUMP_HEIGHT, 0, 1) * 0.45
		shadow.Position = UDim2.fromOffset(screenX, groundY - 2)
		shadow.Size = UDim2.fromOffset(40 * shadowScale, 10 * shadowScale)

		-- Distance affichée
		local meters = math.floor(distance)
		if meters ~= shownDistance then
			shownDistance = meters
			distanceLabel.Text = meters .. " m"
		end

		-- Chute : pause, puis nouvelle partie
		if state == "crash" then
			crashTime += dt
			local shake = crashTime < 0.3 and (0.3 - crashTime) * 20 or 0
			device.Position = UDim2.fromOffset(random:NextNumber(-shake, shake), random:NextNumber(-shake, shake))
			if crashTime >= 2.2 then
				device.Position = UDim2.new()
				restart()
			end
		end

		-- Sous-titres de temps en temps
		captionTimer -= dt
		if captionTimer <= 0 then
			captionTimer = random:NextNumber(9, 16)
			if state == "run" then
				showCaption(CAPTIONS[random:NextInteger(1, #CAPTIONS)])
			end
		end
	end)
end

function Runner.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Runner
