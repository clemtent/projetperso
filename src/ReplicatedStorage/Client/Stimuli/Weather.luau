--[[
	Weather (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Weather

	Orage "illustré" :
	  - ambiance (calque Background, sous les cartes des slots) : de gros
	    nuages duveteux faits de nombreuses bouffées rondes superposées
	    (chacune ombrée du haut clair vers le bas plus sombre, reflets
	    blancs, ombre portée), plus de petits nuages lointains, plus pâles,
	    qui dérivent moins vite (parallaxe, qui suit aussi un peu la
	    souris) ; pluie en traits dégradés qui s'écrasent en éclaboussures ;
	  - quand le SERVEUR envoie un Spawn "Lightning" : un nuage d'orage
	    sombre (lueurs internes qui clignotent) apparaît en (X, Y), un éclair
	    ramifié (halo, cœur lumineux, branches plus fines, colonne de
	    lumière) se dessine de haut en bas avec un stroboscope, flash de
	    l'écran et tonnerre ; le nuage d'ambiance le plus proche s'assombrit
	    et s'illumine de l'intérieur.
	Il faut cliquer sur l'éclair avant qu'il ne disparaisse (Lifetime) :
	ClaimSpawn, et le "+X" confirmé (OnBonus "Lightning") s'affiche à
	l'impact.
]]

local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local Weather = {}
Weather.Slot = "Overlay"

local MAX_BOLTS = 2
local DROPS_PER_CLOUD = 10
local DROPS_LOW_EFFECTS = 4
local SPLASHES_PER_CLOUD = 4
local RAIN_FALL = 74 -- distance de chute des gouttes sous le nuage (pixels "design")

local BOLT_W = 160
local BOLT_H = 244
local BOLT_TOP = 50 -- départ de l'éclair (sous le nuage d'orage)
local BOLT_IMPACT = 206 -- point d'impact dans le cadre de l'éclair
local BOLT_ANCHOR_Y = BOLT_IMPACT / BOLT_H
local STROBE_TIME = 0.45

-- Formes des nuages : bouffées { x, y, diamètre } de l'arrière vers l'avant,
-- base arrondie { x, y, largeur, hauteur }, reflets { x, y, diamètre }
local SHAPES = {
	Big = {
		W = 156,
		H = 78,
		Puffs = {
			{ 58, 0, 60 },
			{ 26, 16, 46 },
			{ 98, 12, 48 },
			{ 4, 36, 36 },
			{ 124, 32, 32 },
			{ 40, 34, 38 },
			{ 80, 32, 40 },
		},
		Base = { 8, 46, 142, 30 },
		Highlights = { { 70, 6, 26 }, { 36, 22, 16 }, { 106, 18, 16 } },
	},
	Small = {
		W = 96,
		H = 46,
		Puffs = {
			{ 32, 0, 38 },
			{ 12, 12, 28 },
			{ 58, 8, 30 },
			{ 0, 24, 22 },
			{ 72, 22, 22 },
		},
		Base = { 4, 28, 88, 18 },
		Highlights = {},
	},
	Storm = {
		W = 150,
		H = 70,
		Puffs = {
			{ 52, 0, 54 },
			{ 22, 14, 42 },
			{ 90, 10, 46 },
			{ 2, 32, 34 },
			{ 116, 30, 32 },
			{ 40, 28, 40 },
			{ 76, 28, 40 },
		},
		Base = { 6, 42, 138, 28 },
		Highlights = { { 62, 6, 20 }, { 98, 16, 14 } },
	},
}

local TAGS = { "⚡ attrape !", "⚡ vite !", "⚡ zap ?", "⚡ clique !", "⚡ ici !" }
local CHEERS = { "ÉLECTRISANT !", "ZAP !", "QUEL RÉFLEXE !", "FOUDROYANT !", "CHOC !", "100 000 VOLTS !" }

function Weather.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()

	local white = Color3.new(1, 1, 1)
	local yellow = Theme.Colors.Yellow
	local boltCore = Color3.fromRGB(255, 253, 230)
	local boltEdge = Color3.fromRGB(255, 205, 50)
	local boltGlow = Color3.fromRGB(255, 232, 120)
	local cloudColor = Color3.fromRGB(236, 240, 248)
	local cloudStorm = Color3.fromRGB(128, 136, 158)
	local farColor = Color3.fromRGB(214, 222, 236)
	local stormColor = Color3.fromRGB(84, 90, 114)
	local rainColor = Color3.fromRGB(120, 175, 235)
	local innerLight = Color3.fromRGB(255, 246, 205)

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function circle(parent: Instance, x: number, y: number, diameter: number, color: Color3, zIndex: number, transparency: number?): Frame
		local frame = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(diameter, diameter),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = parent,
		})
		UIUtil.Corner(frame, UDim.new(1, 0))
		return frame
	end

	-- Segment de droite (cadre tourné) entre deux points
	local function line(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, zIndex: number, transparency: number?): Frame
		local delta = b - a
		local middle = (a + b) / 2
		local frame = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(delta.Magnitude + thickness * 0.8, thickness),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(middle.X, middle.Y),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = parent,
		})
		UIUtil.Corner(frame, UDim.new(1, 0))
		return frame
	end

	-- Dégradé vertical "multiplicatif" : haut = couleur de fond, bas plus sombre
	local function shade(parent: Instance, bottom: Color3)
		UIUtil.Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, white),
				ColorSequenceKeypoint.new(0.55, white:Lerp(bottom, 0.4)),
				ColorSequenceKeypoint.new(1, bottom),
			}),
			Parent = parent,
		})
	end

	------------------------------------------------------------------
	-- Nuage duveteux
	------------------------------------------------------------------
	local function makeCloud(parent: Instance, shapeName: string, color: Color3, zIndex: number, options: { [string]: any }?)
		local shape = SHAPES[shapeName]
		local opts = options or {}
		local transparency = opts.Transparency or 0
		local bottomTint = opts.Bottom or Color3.fromRGB(176, 184, 204)
		local root = UIUtil.Create("Frame", {
			Name = "Cloud",
			Size = UDim2.fromOffset(shape.W, shape.H),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Parent = parent,
		})

		-- Ombre portée (ellipse sombre sous le nuage)
		local shadow: Frame? = nil
		if opts.Shadow then
			local base = shape.Base
			shadow = circle(root, base[1] + 6, base[2] + 10, base[3] - 12, Color3.fromRGB(40, 50, 80), zIndex - 1, 0.82)
			local s = shadow :: Frame
			s.Size = UDim2.fromOffset(base[3] - 12, base[4])
		end

		local puffs: { Frame } = {}
		for _, puff in ipairs(shape.Puffs) do
			local frame = circle(root, puff[1], puff[2], puff[3], color, zIndex, transparency)
			shade(frame, bottomTint)
			table.insert(puffs, frame)
		end
		local base = shape.Base
		local baseFrame = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(base[3], base[4]),
			Position = UDim2.fromOffset(base[1], base[2]),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = root,
		})
		UIUtil.Corner(baseFrame, UDim.new(1, 0))
		UIUtil.Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(white:Lerp(bottomTint, 0.45), bottomTint),
			Parent = baseFrame,
		})
		table.insert(puffs, baseFrame)

		-- Reflets (bords éclairés par le dessus)
		for _, highlight in ipairs(shape.Highlights) do
			local frame = circle(root, highlight[1], highlight[2], highlight[3], white, zIndex + 1, opts.HighlightTransparency or 0.45)
			UIUtil.Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new(0, 1),
				Parent = frame,
			})
		end

		-- Lueur interne (orage) : invisible au repos
		local glow: Frame? = nil
		if opts.Glow then
			glow = circle(root, shape.W * 0.22, shape.H * 0.1, shape.W * 0.56, innerLight, zIndex + 2, 1)
			UIUtil.Create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.1),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = glow,
			})
		end

		return {
			Root = root,
			Shape = shape,
			Puffs = puffs,
			Glow = glow,
			Shadow = shadow,
			Color = color,
			Flash = 0, -- intensité de la lueur interne (0..1)
		}
	end

	local function setCloudColor(cloud, color: Color3)
		if cloud.Color == color then
			return
		end
		cloud.Color = color
		for _, puff in ipairs(cloud.Puffs) do
			puff.BackgroundColor3 = color
		end
	end

	------------------------------------------------------------------
	-- Ambiance : dans le calque Background (sous les cartes des slots) :
	-- les nuages et leur pluie ne cachent jamais la bourse (R1) ni le live
	-- (L1). Les éclairs, cliquables, restent dans ctx.Container (Overlay).
	------------------------------------------------------------------
	local ambientHolder = UIUtil.Create("Frame", {
		Name = "WeatherAmbient",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 1000, -- au-dessus du fond NeonMode / du thème
		Parent = ctx.Interface.Layers.Background or container,
	})
	-- Détruit avec le conteneur (arrêt du stimulus, détox)
	container.Destroying:Connect(function()
		ambientHolder:Destroy()
	end)

	-- Nuages lointains (petits, pâles, lents)
	local farClouds = {}
	local farRanges = {
		{ Min = 0.1, Max = 0.24, Anchor = 0, Y = 64 },
		{ Min = 0.76, Max = 0.9, Anchor = 1, Y = 56 },
	}
	for index, range in ipairs(farRanges) do
		local cloud = makeCloud(ambientHolder, "Small", farColor, 2, { Transparency = 0.35, Bottom = Color3.fromRGB(190, 198, 216) })
		cloud.Root.AnchorPoint = Vector2.new(range.Anchor, 0)
		cloud.Range = range
		cloud.Phase = random:NextNumber(0, math.pi * 2) + index * 2
		table.insert(farClouds, cloud)
	end

	-- Gros nuages de pluie (à gauche et à droite de la colonne centrale)
	local ambient = {}
	local ranges = {
		{ Min = 0.012, Max = 0.16, Anchor = 0 },
		{ Min = 0.84, Max = 0.988, Anchor = 1 },
	}
	local dropCount = effectsOn() and DROPS_PER_CLOUD or DROPS_LOW_EFFECTS
	for index, range in ipairs(ranges) do
		local cloud = makeCloud(ambientHolder, "Big", cloudColor, 6, { Shadow = true, Glow = true })
		local shape = cloud.Shape
		cloud.Root.AnchorPoint = Vector2.new(range.Anchor, 0)
		cloud.Range = range
		cloud.Phase = random:NextNumber(0, math.pi * 2) + index
		cloud.StormUntil = 0
		cloud.Drops = {}
		cloud.Splashes = {}
		cloud.NextSplash = 1
		for _ = 1, dropCount do
			local drop = UIUtil.Create("Frame", {
				Size = UDim2.fromOffset(2, 13),
				AnchorPoint = Vector2.new(0.5, 1),
				Rotation = 14,
				BackgroundColor3 = rainColor,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = cloud.Root,
			})
			UIUtil.Corner(drop, UDim.new(1, 0))
			UIUtil.Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new(1, 0.1),
				Parent = drop,
			})
			table.insert(cloud.Drops, {
				Frame = drop,
				X = random:NextNumber(16, shape.W - 16),
				Y = random:NextNumber(0, RAIN_FALL),
				Speed = random:NextNumber(110, 160),
			})
		end
		for _ = 1, SPLASHES_PER_CLOUD do
			local splash = UIUtil.Create("Frame", {
				Size = UDim2.fromOffset(8, 3),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Visible = false,
				ZIndex = 4,
				Parent = cloud.Root,
			})
			UIUtil.Corner(splash, UDim.new(1, 0))
			local stroke = UIUtil.Stroke(splash, rainColor, 1.2, 0.2)
			table.insert(cloud.Splashes, { Frame = splash, Stroke = stroke, Age = 1, Active = false })
		end
		table.insert(ambient, cloud)
	end

	local function splashAt(cloud, x: number)
		local splash = cloud.Splashes[cloud.NextSplash]
		cloud.NextSplash = cloud.NextSplash % #cloud.Splashes + 1
		if not splash then
			return
		end
		splash.Active = true
		splash.Age = 0
		splash.Frame.Position = UDim2.fromOffset(x, cloud.Shape.H - 6 + RAIN_FALL)
		splash.Frame.Visible = true
	end

	------------------------------------------------------------------
	-- Éclairs
	------------------------------------------------------------------
	local bolts: { [string]: any } = {}
	local boltCount = 0
	local positions: { [string]: UDim2 } = {}
	local lastPosition = UDim2.fromScale(0.5, 0.5)

	local function fadeAll(root: Instance, duration: number)
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("TextLabel") then
				UIUtil.Tween(item, duration, { TextTransparency = 1, BackgroundTransparency = 1 })
			elseif item:IsA("Frame") then
				UIUtil.Tween(item, duration, { BackgroundTransparency = 1 })
			elseif item:IsA("UIStroke") then
				UIUtil.Tween(item, duration, { Transparency = 1 })
			end
		end
	end

	local function removeBolt(bolt, claimed: boolean)
		if bolt.Done then
			return
		end
		bolt.Done = true
		bolts[bolt.Id] = nil
		boltCount -= 1
		if claimed then
			UIUtil.Tween(bolt.Scale, 0.3, { Scale = 1.3 }, Enum.EasingStyle.Quad)
		else
			UIUtil.Tween(bolt.Scale, 0.35, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		fadeAll(bolt.Root, 0.3)
		Debris:AddItem(bolt.Root, 0.4)
	end

	-- Le nuage d'ambiance le plus proche devient orageux et s'illumine
	local function stormNearestCloud(x: number)
		local best, bestDistance = nil, math.huge
		for _, cloud in ipairs(ambient) do
			local center = (cloud.Range.Min + cloud.Range.Max) / 2
			local distance = math.abs(center - x)
			if distance < bestDistance then
				best, bestDistance = cloud, distance
			end
		end
		if best then
			best.StormUntil = os.clock() + 1.6
			best.Flash = 1
		end
	end

	local function spawnBolt(info)
		if not ctx.IsAlive() or type(info) ~= "table" or type(info.Id) ~= "string" then
			return
		end
		if bolts[info.Id] or boltCount >= MAX_BOLTS then
			return
		end
		local x = math.clamp(tonumber(info.X) or 0.5, 0.06, 0.94)
		local y = math.clamp(tonumber(info.Y) or 0.5, 0.1, 0.92)
		local lifetime = math.max(1, tonumber(info.Lifetime) or 2.5)
		local variant = math.floor(tonumber(info.Variant) or 1)
		local shape = Random.new(variant) -- forme déterministe selon la variante

		-- Décalage pour que le nuage ne sorte pas par le haut
		local extra = math.max(0, BOLT_IMPACT + 34 - y * 720)
		local position = UDim2.new(x, 0, y, extra)

		local root = UIUtil.Create("TextButton", {
			Name = "Lightning",
			Size = UDim2.fromOffset(BOLT_W, BOLT_H),
			AnchorPoint = Vector2.new(0.5, BOLT_ANCHOR_Y),
			Position = position,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 30,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Scale = 0.7, Parent = root })
		UIUtil.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

		-- Colonne de lumière derrière l'éclair
		local shaft = UIUtil.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(BOLT_W / 2, BOLT_TOP - 10),
			Size = UDim2.fromOffset(70, BOLT_IMPACT - BOLT_TOP + 30),
			BackgroundColor3 = boltGlow,
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			ZIndex = 30,
			Parent = root,
		})
		UIUtil.Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = shaft,
		})

		-- Points du zigzag principal
		local points = {}
		local steps = 8
		local side = (variant % 2 == 0) and 1 or -1
		for i = 0, steps do
			local py = BOLT_TOP + (BOLT_IMPACT - BOLT_TOP) * i / steps + (i > 0 and i < steps and shape:NextNumber(-4, 4) or 0)
			local px = BOLT_W / 2
			if i > 0 and i < steps then
				side = -side
				px += side * shape:NextNumber(6, 22)
			elseif i == steps then
				px += shape:NextNumber(-6, 6)
			end
			table.insert(points, Vector2.new(math.clamp(px, 20, BOLT_W - 20), py))
		end

		-- Segments : halo large + cœur lumineux (contour doré), révélés par groupe
		local groups: { { Frame } } = {}
		local cores: { Frame } = {}
		local glows: { Frame } = {}
		local function addSegment(group: { Frame }, a: Vector2, b: Vector2, width: number)
			local glow = line(root, a, b, width + 12, boltGlow, 31, 0.78)
			local core = line(root, a, b, width, boltCore, 33)
			UIUtil.Stroke(core, boltEdge, width >= 4 and 1.5 or 1, 0)
			glow.Visible, core.Visible = false, false
			table.insert(group, glow)
			table.insert(group, core)
			table.insert(cores, core)
			table.insert(glows, glow)
		end
		for i = 1, #points - 1 do
			local group = {}
			local width = 6 - (i / #points) * 2 -- plus fin vers le bas
			addSegment(group, points[i], points[i + 1], width)
			table.insert(groups, group)
		end
		-- Deux branches plus fines
		local branchFrom = { 2 + shape:NextInteger(0, 1), 4 + shape:NextInteger(0, 1) }
		for _, index in ipairs(branchFrom) do
			local from = points[index]
			local group = groups[index] or groups[#groups]
			local dir = (from.X >= BOLT_W / 2) and 1 or -1
			local mid = from + Vector2.new(dir * shape:NextNumber(18, 30), shape:NextNumber(14, 24))
			local tip = mid + Vector2.new(dir * shape:NextNumber(6, 16), shape:NextNumber(12, 20))
			addSegment(group, from, mid, 3)
			addSegment(group, mid, tip, 2)
		end

		-- Nuage d'orage sombre au sommet (lueurs internes)
		local storm = makeCloud(root, "Storm", stormColor, 36, {
			Glow = true,
			Bottom = Color3.fromRGB(120, 124, 140),
			HighlightTransparency = 0.8,
		})
		storm.Root.Position = UDim2.fromOffset((BOLT_W - storm.Shape.W) / 2, 0)

		-- Impact : halo + anneau qui pulse + trace au sol
		local impact = points[#points]
		local scorch = circle(root, impact.X - 20, impact.Y - 4, 40, Color3.fromRGB(60, 40, 10), 30, 0.7)
		scorch.Size = UDim2.fromOffset(40, 9)
		local impactGlow = circle(root, impact.X - 26, impact.Y - 26, 52, boltGlow, 32, 0.5)
		UIUtil.Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = impactGlow,
		})
		local ring = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(64, 64),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(impact.X, impact.Y),
			BackgroundTransparency = 1,
			ZIndex = 32,
			Parent = root,
		})
		UIUtil.Corner(ring, UDim.new(1, 0))
		local ringStroke = UIUtil.Stroke(ring, yellow, 3, 0.1)
		local ringScale = UIUtil.Create("UIScale", { Parent = ring })

		-- Étiquette
		local tag = UIUtil.Label({
			Text = TAGS[random:NextInteger(1, #TAGS)],
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.TextDark,
			BackgroundColor3 = yellow,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(92, 22),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(BOLT_W / 2, BOLT_IMPACT + 12),
			MaxTextSize = 15,
			ZIndex = 38,
			Parent = root,
		})
		UIUtil.Corner(tag, UDim.new(1, 0))
		UIUtil.Stroke(tag, Theme.Colors.Border, 1.5, 0.1)

		local bolt = {
			Id = info.Id,
			Root = root,
			Scale = scale,
			Cores = cores,
			Glows = glows,
			Shaft = shaft,
			ImpactGlow = impactGlow,
			RingScale = ringScale,
			RingStroke = ringStroke,
			Storm = storm,
			Base = position,
			Born = os.clock(),
			Lifetime = lifetime,
			Done = false,
		}
		bolts[info.Id] = bolt
		boltCount += 1

		-- Frappe : le zigzag se dessine de haut en bas (très vite)
		task.spawn(function()
			for _, group in ipairs(groups) do
				if bolt.Done or not root.Parent then
					return
				end
				for _, frame in ipairs(group) do
					frame.Visible = true
				end
				task.wait(0.015)
			end
		end)

		ctx.Sound.Play("Thunder", 0.8 + random:NextNumber() * 0.2)
		if effectsOn() then
			ctx.Effects.Flash(Color3.fromRGB(255, 250, 225), 0.32)
			task.delay(0.14, function()
				if ctx.IsAlive() then
					ctx.Effects.Flash(Color3.fromRGB(230, 240, 255), 0.18)
				end
			end)
		end
		storm.Flash = 1
		stormNearestCloud(x)

		-- Clic : on attrape l'éclair
		ctx.Connect(root.Activated, function()
			if bolt.Done or not ctx.IsAlive() then
				return
			end
			local impactPosition = UDim2.new(x, 0, y, extra)
			positions[bolt.Id] = impactPosition
			lastPosition = impactPosition
			ctx.ClaimSpawn(bolt.Id)
			ctx.Sound.Play("Thunder", 1.5)
			if effectsOn() then
				ctx.Effects.Burst(container, impactPosition, yellow, 18)
				ctx.Effects.Burst(container, impactPosition, nil, 8)
			end
			removeBolt(bolt, true)
			local id = bolt.Id
			task.delay(6, function()
				positions[id] = nil
			end)
		end)
	end

	------------------------------------------------------------------
	-- Animation (une seule connexion)
	------------------------------------------------------------------
	local camera = workspace.CurrentCamera
	local parallax = Vector2.zero

	-- Lueur interne d'un nuage : éclairs aléatoires qui retombent
	local function updateGlow(cloud, dt: number, chance: number)
		if cloud.Glow == nil then
			return
		end
		if chance > 0 and random:NextNumber() < chance * dt then
			cloud.Flash = random:NextNumber(0.5, 1)
		end
		cloud.Flash = math.max(0, cloud.Flash - dt * 4)
		cloud.Glow.BackgroundTransparency = 1 - cloud.Flash * 0.85
	end

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		local now = os.clock()

		-- Parallaxe : suit un peu la souris (lissée)
		if camera and camera.ViewportSize.X > 0 then
			local mouse = UserInputService:GetMouseLocation()
			local target = Vector2.new(
				math.clamp(mouse.X / camera.ViewportSize.X * 2 - 1, -1, 1),
				math.clamp(mouse.Y / camera.ViewportSize.Y * 2 - 1, -1, 1)
			)
			parallax = parallax:Lerp(target, math.min(1, dt * 3))
		end

		-- Nuages lointains : lents, peu de parallaxe
		for _, cloud in ipairs(farClouds) do
			local range = cloud.Range
			local drift = 0.5 + 0.5 * math.sin(now * 0.05 + cloud.Phase)
			local sx = range.Min + (range.Max - range.Min) * drift
			cloud.Root.Position = UDim2.new(sx, -parallax.X * 3, 0, range.Y + math.sin(now * 0.6 + cloud.Phase) * 2 - parallax.Y * 2)
		end

		-- Gros nuages de pluie
		for _, cloud in ipairs(ambient) do
			local range = cloud.Range
			local drift = 0.5 + 0.5 * math.sin(now * 0.08 + cloud.Phase)
			local sx = range.Min + (range.Max - range.Min) * drift
			local bob = math.sin(now * 0.9 + cloud.Phase) * 3
			local stormy = now < cloud.StormUntil
			local rumble = stormy and math.sin(now * 55) * 1.5 or 0
			cloud.Root.Position = UDim2.new(sx, rumble - parallax.X * 8, 0, 34 + bob - parallax.Y * 4)
			setCloudColor(cloud, stormy and cloudStorm or cloudColor)
			updateGlow(cloud, dt, stormy and 7 or 0)

			-- Pluie + éclaboussures
			local shapeH = cloud.Shape.H
			for _, drop in ipairs(cloud.Drops) do
				drop.Y += drop.Speed * dt * (stormy and 1.4 or 1)
				if drop.Y > RAIN_FALL then
					splashAt(cloud, drop.X - RAIN_FALL * 0.25)
					drop.Y = 0
					drop.X = random:NextNumber(16, cloud.Shape.W - 16)
				end
				drop.Frame.Position = UDim2.fromOffset(drop.X - drop.Y * 0.25, shapeH - 8 + drop.Y)
			end
			for _, splash in ipairs(cloud.Splashes) do
				if splash.Active then
					splash.Age += dt * 3
					if splash.Age >= 1 then
						splash.Active = false
						splash.Frame.Visible = false
					else
						splash.Frame.Size = UDim2.fromOffset(6 + splash.Age * 12, 2 + splash.Age * 3)
						splash.Stroke.Transparency = 0.2 + splash.Age * 0.8
					end
				end
			end
		end

		-- Éclairs
		for _, bolt in pairs(bolts) do
			local age = now - bolt.Born
			local left = bolt.Lifetime - age
			if left <= 0 then
				removeBolt(bolt, false)
			else
				-- Stroboscope au début, puis léger scintillement
				local coreAlpha
				if age < STROBE_TIME then
					coreAlpha = (math.floor(age * 28) % 3 == 1) and 0.85 or 0
				else
					coreAlpha = random:NextNumber(0, 0.18)
				end
				for _, core in ipairs(bolt.Cores) do
					core.BackgroundTransparency = coreAlpha
				end
				local glowAlpha = 0.74 + math.sin(now * 22) * 0.08 + coreAlpha * 0.2
				for _, glow in ipairs(bolt.Glows) do
					glow.BackgroundTransparency = glowAlpha
				end
				bolt.Shaft.BackgroundTransparency = 0.78 + math.sin(now * 9) * 0.06 + coreAlpha * 0.2
				bolt.ImpactGlow.BackgroundTransparency = 0.35 + math.sin(now * 12) * 0.15
				-- Anneau qui s'agrandit en boucle
				local cycle = (age * 1.6) % 1
				bolt.RingScale.Scale = 0.6 + cycle * 0.9
				bolt.RingStroke.Transparency = cycle
				-- Nuage d'orage : grondement + lueurs internes
				local storm = bolt.Storm
				storm.Root.Position = UDim2.fromOffset((BOLT_W - storm.Shape.W) / 2 + math.sin(now * 50) * 1.2, 0)
				updateGlow(storm, dt, 5)
				-- Presque fini : tremble
				if left < 0.6 then
					bolt.Root.Position = bolt.Base + UDim2.fromOffset(math.sin(now * 40) * 2, 0)
				end
			end
		end
	end)

	ctx.OnSpawn("Lightning", spawnBolt)

	-- Bonus confirmé : "+X ⚡" à l'impact
	ctx.OnBonus("Lightning", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local position = (payload.SpawnId and positions[payload.SpawnId]) or lastPosition
		ctx.FloatText(container, position, "+" .. ctx.Format.Format(tonumber(payload.Amount) or 0) .. " ⚡", Theme.Colors.Gold, 44)
		ctx.FloatText(container, position + UDim2.fromOffset(0, 44), CHEERS[random:NextInteger(1, #CHEERS)], Theme.Colors.Orange, 24)
	end)
end

function Weather.Stop(_ctx)
	-- Éclairs dans ctx.Container (détruit par le StimulusManager) ; nuages
	-- d'ambiance dans le calque Background, détruits avec ce conteneur
end

return Weather
