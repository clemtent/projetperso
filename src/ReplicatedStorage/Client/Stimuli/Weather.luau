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

	v9 - CHASSEUR D'ORAGES (amélioration StormChaser, 8 niveaux, lue avec
	ctx.GetLevel("StormChaser"), mise à jour en direct) : une bande "orage"
	au-dessus du bandeau d'actu (dans la barre du haut de Roblox ; sur le
	bandeau lui-même s'il n'y a pas de barre) :
	  - nuages d'orage avec éclairs silencieux (plus fréquents et plus
	    nombreux à chaque niveau), pluie, petite route ;
	  - la camionnette du chasseur d'orages patrouille, s'arrête pour
	    scanner (radar qui balaie, ondes), fonce vers chaque éclair à
	    attraper et poursuit la tornade ; elle s'équipe au fil des niveaux :
	    radar et antenne (1), gyrophare (2), ondes radar + pluie (3), éclairs
	    de décor plus fréquents (4), TORNADE (5, plus grosse ensuite),
	    anémomètre (6), débris dans la tornade (7), livrée dorée (8) ;
	  - les éclairs à attraper sont plus grands, plus lumineux et plus
	    ramifiés, les nuages d'ambiance plus sombres et agités.
	Aucun son ajouté (les éclairs de décor sont silencieux).
]]

local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Weather = {}
Weather.Slot = "Overlay"

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

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
local CHASER_STEP = 1 / 30 -- mise à jour de la bande "chasseur d'orages"
local VAN_SPEED = 95 -- pixels / seconde (en marche arrière : x 0.6)

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

local TAGS = {
	en = { "⚡ catch it!", "⚡ quick!", "⚡ zap?", "⚡ click!", "⚡ here!" },
	fr = { "⚡ attrape !", "⚡ vite !", "⚡ zap ?", "⚡ clique !", "⚡ ici !" },
}
local CHEERS = {
	en = { "ELECTRIFYING!", "ZAP!", "WHAT REFLEXES!", "SHOCKING!", "JOLT!", "100,000 VOLTS!" },
	fr = { "ÉLECTRISANT !", "ZAP !", "QUEL RÉFLEXE !", "FOUDROYANT !", "CHOC !", "100 000 VOLTS !" },
}

-- Tire une phrase au hasard dans la liste de la langue du joueur
local function pickLine(variants, random: Random): string
	local list = Locale.Pick(variants)
	return list[random:NextInteger(1, #list)]
end

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

	-- Niveau de StormChaser (0 = pas acheté) et réaction de la camionnette aux éclairs
	local chaserLevel = 0
	local onBoltSpawned: (x: number) -> () = function(_x: number) end

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
		-- StormChaser : éclairs plus grands
		UIUtil.Tween(scale, 0.25, { Scale = 1 + 0.04 * chaserLevel }, Enum.EasingStyle.Back)

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
		-- StormChaser : éclairs plus ramifiés
		if chaserLevel >= 3 then
			table.insert(branchFrom, 6 + shape:NextInteger(0, 1))
		end
		if chaserLevel >= 6 then
			table.insert(branchFrom, 3)
		end
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
			Text = pickLine(TAGS, random),
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
		onBoltSpawned(x)

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

	------------------------------------------------------------------
	-- v9 : CHASSEUR D'ORAGES (StormChaser). Tout est créé une fois ; le
	-- niveau ne fait qu'afficher / cacher / agrandir des éléments.
	------------------------------------------------------------------
	local chaser = UIUtil.Create("Frame", {
		Name = "StormChaser",
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = container,
	})
	local stripHeight = 60
	local roadY = 58
	local canvasWidth = 1280

	-- Bande dans la barre du haut de Roblox (au-dessus de la zone sûre), ou
	-- sur le bandeau d'actu s'il n'y a pas de barre
	local function layoutStrip()
		local canvas = ctx.Interface.CanvasSize or Vector2.new(1280, 720)
		canvasWidth = canvas.X
		local scale = math.max(0.01, ctx.Interface.Scale or 1)
		local inset = 0
		pcall(function()
			local topLeft = GuiService:GetGuiInset()
			inset = topLeft.Y / scale
		end)
		if inset >= 34 then
			stripHeight = math.min(inset, 110)
			chaser.Position = UDim2.fromOffset(0, -stripHeight)
		else
			stripHeight = 40
			chaser.Position = UDim2.fromOffset(0, 0)
		end
		chaser.Size = UDim2.new(1, 0, 0, stripHeight)
		roadY = stripHeight - 2
	end
	layoutStrip()
	ctx.Connect(ctx.Interface.ScaleChanged, layoutStrip)

	local function box(props: { [string]: any }): Frame
		props.BorderSizePixel = 0
		return UIUtil.Create("Frame", props)
	end

	-- Lueur de la bande quand un éclair de décor frappe
	local skyFlash = box({
		Name = "SkyFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(214, 226, 255),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = chaser,
	})
	local skyFlashLevel = 0

	-- Route (tirets jaunes)
	local road = box({
		Name = "Road",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Color3.fromRGB(52, 54, 72),
		BackgroundTransparency = 0.1,
		ZIndex = 6,
		Parent = chaser,
	})
	for index = 1, 18 do
		box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(index / 19, 0.5),
			Size = UDim2.fromOffset(9, 1),
			BackgroundColor3 = Color3.fromRGB(255, 212, 80),
			BackgroundTransparency = 0.15,
			ZIndex = 6,
			Parent = road,
		})
	end

	-- Nuages d'orage de la bande (plus nombreux avec le niveau)
	local STRIP_CLOUDS = { { X = 0.26, Level = 1 }, { X = 0.63, Level = 1 }, { X = 0.45, Level = 3 }, { X = 0.8, Level = 5 } }
	local stripClouds = {}
	for _, def in ipairs(STRIP_CLOUDS) do
		local cloud = makeCloud(chaser, "Storm", Color3.fromRGB(150, 158, 186), 7, {
			Glow = true,
			Bottom = Color3.fromRGB(96, 102, 130),
			HighlightTransparency = 0.6,
		})
		cloud.Root.AnchorPoint = Vector2.new(0.5, 0)
		cloud.Root.Visible = false
		cloud.Scaler = UIUtil.Create("UIScale", { Scale = 0.5, Parent = cloud.Root })
		cloud.Def = def
		cloud.Phase = random:NextNumber(0, math.pi * 2)
		cloud.X = def.X
		table.insert(stripClouds, cloud)
	end

	-- Pluie de la bande
	local stripRain = {}
	for index = 1, 14 do
		local drop = box({
			Name = "Drop",
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(1.5, 7),
			Rotation = 12,
			BackgroundColor3 = rainColor,
			Visible = false,
			ZIndex = 6,
			Parent = chaser,
		})
		UIUtil.Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(white),
			Transparency = NumberSequence.new(1, 0.15),
			Parent = drop,
		})
		stripRain[index] = { Frame = drop, Cloud = (index - 1) % #STRIP_CLOUDS + 1, X = random:NextNumber(-26, 26), Y = random:NextNumber(0, 1), Speed = random:NextNumber(0.9, 1.4) }
	end

	-- Éclairs de décor (silencieux) : 2 zigzags recyclés, 4 segments chacun
	local ambientBolts = {}
	for index = 1, 2 do
		local holder = box({
			Name = "AmbientBolt",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 8,
			Parent = chaser,
		})
		local segments = {}
		for segment = 1, 4 do
			local glowFrame = box({ AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = boltGlow, BackgroundTransparency = 0.55, ZIndex = 8, Parent = holder })
			UIUtil.Corner(glowFrame, UDim.new(1, 0))
			local core = box({ AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = boltCore, ZIndex = 9, Parent = holder })
			UIUtil.Corner(core, UDim.new(1, 0))
			segments[segment] = { Glow = glowFrame, Core = core }
		end
		ambientBolts[index] = { Holder = holder, Segments = segments, Age = 1 }
	end

	local function placeSegment(frame: Frame, a: Vector2, b: Vector2, thickness: number)
		local delta = b - a
		local middle = (a + b) / 2
		frame.Size = UDim2.fromOffset(delta.Magnitude + thickness * 0.8, thickness)
		frame.Position = UDim2.fromOffset(middle.X, middle.Y)
		frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end

	local function stripCloudPosition(cloud): (number, number)
		local scale = cloud.Scaler.Scale
		return cloud.X * canvasWidth, -6 + cloud.Shape.H * scale * 0.85
	end

	local function fireAmbientBolt()
		local visible = {}
		for _, cloud in ipairs(stripClouds) do
			if cloud.Root.Visible then
				table.insert(visible, cloud)
			end
		end
		if #visible == 0 then
			return
		end
		local cloud = visible[random:NextInteger(1, #visible)]
		local bolt = ambientBolts[1].Age >= 1 and ambientBolts[1] or ambientBolts[2]
		local x0, y0 = stripCloudPosition(cloud)
		x0 += random:NextNumber(-18, 18)
		local x1 = x0 + random:NextNumber(-22, 22)
		local width = 2 + math.min(2, chaserLevel * 0.3)
		local last = Vector2.new(x0, y0)
		for index, segment in ipairs(bolt.Segments) do
			local t = index / #bolt.Segments
			local nextPoint = Vector2.new(x0 + (x1 - x0) * t + (index < #bolt.Segments and random:NextNumber(-9, 9) or 0), y0 + (roadY - y0) * t)
			placeSegment(segment.Glow, last, nextPoint, width + 6)
			placeSegment(segment.Core, last, nextPoint, width)
			last = nextPoint
		end
		bolt.Age = 0
		bolt.Holder.Visible = true
		cloud.Flash = 1
		skyFlashLevel = math.max(skyFlashLevel, 0.2 + chaserLevel * 0.02)
	end

	------------------------------------------------------------------
	-- La camionnette (dessinée face à droite ; recule pour aller à gauche)
	------------------------------------------------------------------
	local van = box({
		Name = "ChaserVan",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(72, 44),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = chaser,
	})
	local vanScale = UIUtil.Create("UIScale", { Parent = van })
	local ink = Color3.fromRGB(34, 34, 52)
	-- Galerie de toit
	box({ Name = "Rack", Position = UDim2.fromOffset(9, 15), Size = UDim2.fromOffset(46, 3), BackgroundColor3 = Color3.fromRGB(62, 64, 84), ZIndex = 10, Parent = van })
	-- Carrosserie
	local body = box({ Name = "Body", Position = UDim2.fromOffset(2, 17), Size = UDim2.fromOffset(66, 20), BackgroundColor3 = white, ZIndex = 11, Parent = van })
	UIUtil.Corner(body, 6)
	UIUtil.Gradient(body, ColorSequence.new(white, Color3.fromRGB(206, 214, 230)), 90)
	UIUtil.Stroke(body, ink, 1.5, 0)
	local stripe = box({ Name = "Stripe", Position = UDim2.fromOffset(2, 28), Size = UDim2.fromOffset(66, 4), BackgroundColor3 = Color3.fromRGB(255, 140, 30), ZIndex = 12, Parent = van })
	for index, spec in ipairs({ { 8, 20, 14, 7 }, { 26, 20, 15, 7 } }) do
		local window = box({ Name = "Window" .. index, Position = UDim2.fromOffset(spec[1], spec[2]), Size = UDim2.fromOffset(spec[3], spec[4]), BackgroundColor3 = Color3.fromRGB(46, 78, 130), ZIndex = 12, Parent = van })
		UIUtil.Corner(window, 2)
	end
	local windshield = box({ Name = "Windshield", Position = UDim2.fromOffset(51, 19), Size = UDim2.fromOffset(14, 9), BackgroundColor3 = Color3.fromRGB(70, 116, 178), ZIndex = 12, Parent = van })
	UIUtil.Corner(windshield, 3)
	box({ Name = "Glare", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.4, 0.45), Size = UDim2.fromOffset(10, 1.5), Rotation = -30, BackgroundColor3 = white, BackgroundTransparency = 0.35, ZIndex = 13, Parent = windshield })
	local headlight = box({ Name = "Headlight", Position = UDim2.fromOffset(65, 29), Size = UDim2.fromOffset(4, 3), BackgroundColor3 = Color3.fromRGB(255, 236, 150), ZIndex = 13, Parent = van })
	UIUtil.Corner(headlight, 1)
	local reverseLight = box({ Name = "Reverse", Position = UDim2.fromOffset(1, 29), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = Color3.fromRGB(255, 70, 70), ZIndex = 13, Parent = van })
	local decal = UIUtil.Label({
		Name = "Decal",
		Text = "⚡",
		Position = UDim2.fromOffset(42, 20),
		Size = UDim2.fromOffset(9, 9),
		MaxTextSize = 9,
		ZIndex = 13,
		Parent = van,
	})
	-- Roues (le rayon tourne)
	local wheels = {}
	for _, wheelX in ipairs({ 16, 54 }) do
		local wheel = box({ Name = "Wheel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(wheelX, 37), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(28, 28, 36), ZIndex = 13, Parent = van })
		UIUtil.Corner(wheel, UDim.new(1, 0))
		local hubcap = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Color3.fromRGB(184, 188, 202), ZIndex = 14, Parent = wheel })
		UIUtil.Corner(hubcap, UDim.new(1, 0))
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 1.5), BackgroundColor3 = Color3.fromRGB(96, 98, 112), ZIndex = 15, Parent = wheel })
		table.insert(wheels, wheel)
	end
	-- Radar (antenne parabolique qui balaie)
	box({ Name = "DishMast", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(19, 16), Size = UDim2.fromOffset(2, 6), BackgroundColor3 = Color3.fromRGB(84, 86, 104), ZIndex = 11, Parent = van })
	local dish = box({ Name = "Dish", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(19, 8), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, ZIndex = 12, Parent = van })
	local bowl = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(16, 8), BackgroundColor3 = white, ZIndex = 12, Parent = dish })
	UIUtil.Corner(bowl, UDim.new(1, 0))
	UIUtil.Gradient(bowl, ColorSequence.new(white, Color3.fromRGB(150, 158, 180)), 90)
	UIUtil.Stroke(bowl, ink, 1, 0.2)
	box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1.5, 7), BackgroundColor3 = Color3.fromRGB(84, 86, 104), ZIndex = 13, Parent = dish })
	local feed = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -7), Size = UDim2.fromOffset(3.5, 3.5), BackgroundColor3 = Color3.fromRGB(255, 196, 60), ZIndex = 13, Parent = dish })
	UIUtil.Corner(feed, UDim.new(1, 0))
	-- Antenne + voyant rouge
	box({ Name = "Antenna", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(47, 16), Size = UDim2.fromOffset(1.5, 17), BackgroundColor3 = Color3.fromRGB(70, 72, 92), ZIndex = 11, Parent = van })
	local antennaTip = box({ Name = "AntennaTip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(47, -1), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(255, 60, 60), ZIndex = 12, Parent = van })
	UIUtil.Corner(antennaTip, UDim.new(1, 0))
	-- Gyrophare (niveau 2+)
	local lightbar = box({ Name = "Lightbar", Position = UDim2.fromOffset(29, 12), Size = UDim2.fromOffset(12, 4), BackgroundTransparency = 1, Visible = false, ZIndex = 12, Parent = van })
	local lightRed = box({ Size = UDim2.fromOffset(6, 4), BackgroundColor3 = Color3.fromRGB(255, 50, 60), ZIndex = 12, Parent = lightbar })
	local lightBlue = box({ Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(6, 4), BackgroundColor3 = Color3.fromRGB(60, 120, 255), ZIndex = 12, Parent = lightbar })
	UIUtil.Corner(lightRed, 2)
	UIUtil.Corner(lightBlue, 2)
	-- Anémomètre (niveau 6+) : 3 coupelles qui tournent
	local anemometer = box({ Name = "Anemometer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(58, 7), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Visible = false, ZIndex = 12, Parent = van })
	box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1.5, 9), BackgroundColor3 = Color3.fromRGB(84, 86, 104), ZIndex = 11, Parent = anemometer })
	local cups = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, ZIndex = 12, Parent = anemometer })
	for cup = 0, 2 do
		local angle = math.rad(cup * 120)
		local dot = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(angle) * 5, 0.5, math.sin(angle) * 5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(255, 196, 60), ZIndex = 12, Parent = cups })
		UIUtil.Corner(dot, UDim.new(1, 0))
	end
	-- Ondes radar (niveau 3+), recyclées
	local waves = {}
	for index = 1, 2 do
		local ring = box({ Name = "RadarWave", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Visible = false, ZIndex = 9, Parent = chaser })
		UIUtil.Corner(ring, UDim.new(1, 0))
		waves[index] = { Frame = ring, Stroke = UIUtil.Stroke(ring, Color3.fromRGB(120, 255, 180), 1.5, 0.2), Age = 1 }
	end

	------------------------------------------------------------------
	-- Tornade (niveau 5+) : anneaux qui ondulent + débris
	------------------------------------------------------------------
	local tornado = box({ Name = "Tornado", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1, Visible = false, ZIndex = 9, Parent = chaser })
	local tornadoScale = UIUtil.Create("UIScale", { Parent = tornado })
	local funnel = {}
	for index = 1, 8 do
		local t = (index - 1) / 7 -- 0 = haut (large), 1 = bas (étroit)
		local ring = box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(48 - 40 * t, 9),
			BackgroundColor3 = Color3.fromRGB(196, 202, 224):Lerp(Color3.fromRGB(126, 130, 158), t),
			BackgroundTransparency = 0.08 + 0.14 * t,
			ZIndex = 9,
			Parent = tornado,
		})
		UIUtil.Corner(ring, UDim.new(1, 0))
		UIUtil.Gradient(ring, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 150, 170)),
			ColorSequenceKeypoint.new(0.45, white),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 120, 145)),
		}), 0)
		funnel[index] = { Frame = ring, T = t }
	end
	local debris = {}
	for index = 1, 6 do
		local bit = box({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = index % 2 == 0 and Color3.fromRGB(120, 86, 60) or Color3.fromRGB(96, 150, 80), Visible = false, ZIndex = 10, Parent = tornado })
		debris[index] = { Frame = bit, Phase = random:NextNumber(0, math.pi * 2), Height = random:NextNumber(0.35, 0.9), Speed = random:NextNumber(4, 7) }
	end

	------------------------------------------------------------------
	-- État + niveau
	------------------------------------------------------------------
	local vanX = canvasWidth * random:NextNumber(0.3, 0.6)
	local vanTarget = vanX
	local vanState = "Scan" -- "Drive" | "Scan"
	local scanUntil = 0
	local wheelAngle = 0
	local hopAge = 1
	local chaserClock = 0
	local chaserPending = 0
	local ambientTimer = 2
	local waveTimer = 0
	local tornadoPhase = random:NextNumber(0, math.pi * 2)
	local tornadoX = canvasWidth * 0.6
	local rainCount = 0

	local function applyChaser(level: number, animate: boolean)
		level = math.clamp(math.floor(level), 0, 8)
		if level == chaserLevel and chaser.Visible == (level > 0) then
			return
		end
		local previous = chaserLevel
		chaserLevel = level
		chaser.Visible = level > 0
		if level <= 0 then
			return
		end
		for _, cloud in ipairs(stripClouds) do
			cloud.Root.Visible = level >= cloud.Def.Level
			cloud.Scaler.Scale = math.clamp(stripHeight / 120, 0.38, 0.6) * (1 + 0.04 * level)
		end
		rainCount = level >= 3 and math.min(#stripRain, 4 + level * 2) or 0
		for index, drop in ipairs(stripRain) do
			drop.Frame.Visible = index <= rainCount
		end
		lightbar.Visible = level >= 2
		anemometer.Visible = level >= 6
		stripe.BackgroundColor3 = level >= 8 and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(255, 140, 30)
		decal.Text = level >= 8 and "🌪️" or "⚡"
		vanScale.Scale = math.clamp(stripHeight / 62, 0.7, 1.25) * (0.98 + 0.03 * level)
		tornado.Visible = level >= 5
		tornadoScale.Scale = math.clamp(stripHeight / 64, 0.6, 1.4) * (0.78 + 0.13 * math.max(0, level - 5))
		for _, bit in ipairs(debris) do
			bit.Frame.Visible = level >= 7
		end
		-- Niveau acheté : la camionnette saute, un éclair frappe
		if animate and level > previous then
			hopAge = 0
			ambientTimer = 0.15
			if ctx.EffectsEnabled() then
				ctx.Effects.Burst(container, UDim2.fromOffset(vanX, chaser.Position.Y.Offset + roadY - 26), yellow, 10)
			end
		end
	end

	-- Un éclair à attraper apparaît : la camionnette fonce vers lui
	onBoltSpawned = function(x: number)
		if chaserLevel <= 0 then
			return
		end
		vanTarget = math.clamp(x * canvasWidth, canvasWidth * 0.2, canvasWidth * 0.8)
		vanState = "Drive"
	end

	local function updateChaser(dt: number)
		if chaserLevel <= 0 then
			return
		end
		chaserPending += dt
		if chaserPending < CHASER_STEP then
			return
		end
		local step = math.min(chaserPending, 0.1)
		chaserPending = 0
		chaserClock += step
		local t = chaserClock

		-- Nuages (dérive lente) + lueurs internes
		for _, cloud in ipairs(stripClouds) do
			if cloud.Root.Visible then
				cloud.X = cloud.Def.X + math.sin(t * 0.05 + cloud.Phase) * 0.04
				cloud.Root.Position = UDim2.fromOffset(cloud.X * canvasWidth, -6 + math.sin(t * 0.7 + cloud.Phase) * 1.5)
				updateGlow(cloud, step, 0.25 + chaserLevel * 0.08)
			end
		end

		-- Éclairs de décor : de plus en plus fréquents
		ambientTimer -= step
		if ambientTimer <= 0 then
			ambientTimer = random:NextNumber(0.7, 1.3) * math.max(1.1, 6.5 - chaserLevel * 0.7)
			if effectsOn() or random:NextNumber() < 0.4 then
				fireAmbientBolt()
			end
		end
		for _, bolt in ipairs(ambientBolts) do
			if bolt.Age < 1 then
				bolt.Age = math.min(1, bolt.Age + step / 0.35)
				local strobe = (math.floor(bolt.Age * 12) % 3 == 1) and 0.7 or 0
				for _, segment in ipairs(bolt.Segments) do
					segment.Core.BackgroundTransparency = math.max(strobe, bolt.Age ^ 2)
					segment.Glow.BackgroundTransparency = 0.55 + 0.45 * bolt.Age
				end
				if bolt.Age >= 1 then
					bolt.Holder.Visible = false
				end
			end
		end
		skyFlashLevel = math.max(0, skyFlashLevel - step * 2.5)
		skyFlash.BackgroundTransparency = 1 - skyFlashLevel

		-- Pluie
		for index = 1, rainCount do
			local drop = stripRain[index]
			local cloud = stripClouds[drop.Cloud]
			if cloud and cloud.Root.Visible then
				local cx, cy = stripCloudPosition(cloud)
				drop.Y += step * drop.Speed * 1.6
				if drop.Y > 1 then
					drop.Y = 0
					drop.X = random:NextNumber(-26, 26)
				end
				drop.Frame.Position = UDim2.fromOffset(cx + drop.X - drop.Y * 6, cy + (roadY - cy) * drop.Y)
			end
		end

		-- Tornade : erre au milieu de la bande, entonnoir qui ondule
		if chaserLevel >= 5 then
			tornadoX = canvasWidth * (0.5 + 0.2 * math.sin(t * 0.09 + tornadoPhase))
			tornado.Position = UDim2.fromOffset(tornadoX, roadY)
			local height = 60
			for index, ring in ipairs(funnel) do
				local sway = math.sin(t * 6 + index * 0.9) * (2 + ring.T * 5)
				ring.Frame.Position = UDim2.fromOffset(30 + sway + math.sin(t * 1.3) * ring.T * 4, 5 + (height - 10) * ring.T)
			end
			if chaserLevel >= 7 then
				for _, bit in ipairs(debris) do
					local angle = t * bit.Speed + bit.Phase
					bit.Frame.Position = UDim2.fromOffset(30 + math.cos(angle) * (14 - bit.Height * 8), height * bit.Height + math.sin(angle) * 3)
					bit.Frame.Rotation = angle * 60
				end
			end
		end

		-- Camionnette : patrouille / scanne / poursuit
		if vanState == "Scan" and os.clock() >= scanUntil then
			if chaserLevel >= 5 then
				-- Garde ses distances avec la tornade
				local side = (vanX < tornadoX) and -1 or 1
				vanTarget = math.clamp(tornadoX + side * 80, canvasWidth * 0.2, canvasWidth * 0.8)
			else
				vanTarget = canvasWidth * random:NextNumber(0.24, 0.76)
			end
			vanState = "Drive"
		end
		local moving = 0
		if vanState == "Drive" then
			local dx = vanTarget - vanX
			local speedNow = VAN_SPEED * (dx < 0 and 0.6 or 1)
			if math.abs(dx) <= speedNow * step then
				vanX = vanTarget
				vanState = "Scan"
				scanUntil = os.clock() + random:NextNumber(1.8, 3.4)
			else
				moving = dx > 0 and 1 or -1
				vanX += moving * speedNow * step
			end
			wheelAngle += moving * speedNow * step * 9.5
		end
		hopAge = math.min(1, hopAge + step / 0.45)
		local hop = math.sin(hopAge * math.pi) * 9 * (1 - hopAge * 0.3)
		local bob = moving ~= 0 and math.sin(t * 22) * 0.6 or 0
		van.Position = UDim2.fromOffset(vanX, roadY + 1 - hop + bob)
		for _, wheel in ipairs(wheels) do
			wheel.Rotation = wheelAngle
		end
		reverseLight.BackgroundTransparency = moving < 0 and 0 or 0.8
		headlight.BackgroundTransparency = (math.floor(t * 2) % 2 == 0) and 0 or 0.25
		-- Radar : balaie en scannant, rangé en roulant
		dish.Rotation = vanState == "Scan" and math.sin(t * 2.4) * 42 or dish.Rotation * 0.8
		antennaTip.BackgroundTransparency = (t % 1) < 0.5 and 0 or 0.75
		if chaserLevel >= 2 then
			local blink = math.floor(t * 7) % 2 == 0
			lightRed.BackgroundTransparency = blink and 0 or 0.7
			lightBlue.BackgroundTransparency = blink and 0.7 or 0
		end
		if chaserLevel >= 6 then
			cups.Rotation = (t * 420) % 360
		end
		-- Ondes radar pendant le scan
		if chaserLevel >= 3 and vanState == "Scan" then
			waveTimer -= step
			if waveTimer <= 0 then
				waveTimer = 0.55
				local wave = waves[1].Age >= waves[2].Age and waves[1] or waves[2]
				wave.Age = 0
				wave.Frame.Visible = true
			end
		end
		local dishX = vanX + (19 - 36) * vanScale.Scale
		local dishY = roadY + 1 - hop - (44 - 8) * vanScale.Scale
		for _, wave in ipairs(waves) do
			if wave.Age < 1 then
				wave.Age = math.min(1, wave.Age + step / 0.9)
				local size = 8 + 46 * wave.Age
				wave.Frame.Size = UDim2.fromOffset(size, size)
				wave.Frame.Position = UDim2.fromOffset(dishX, dishY)
				wave.Stroke.Transparency = 0.2 + 0.8 * wave.Age
				if wave.Age >= 1 then
					wave.Frame.Visible = false
				end
			end
		end
	end

	applyChaser(tonumber(ctx.GetLevel("StormChaser")) or 0, false)
	ctx.Connect(ctx.State.Changed, function()
		applyChaser(tonumber(ctx.GetLevel("StormChaser")) or 0, true)
	end)

	------------------------------------------------------------------
	-- Animation (une seule connexion)
	------------------------------------------------------------------
	local camera = workspace.CurrentCamera
	local parallax = Vector2.zero
	local ambientPending = 0

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		local now = os.clock()
		updateChaser(dt)

		-- Ambiance (nuages, pluie, parallaxe) : 30 fois par seconde suffisent
		ambientPending += dt
		if ambientPending >= 1 / 30 then
			local ambientDt = math.min(ambientPending, 0.1)
			ambientPending = 0

			-- Parallaxe : suit un peu la souris (lissée)
			if camera and camera.ViewportSize.X > 0 then
				local mouse = UserInputService:GetMouseLocation()
				local target = Vector2.new(
					math.clamp(mouse.X / camera.ViewportSize.X * 2 - 1, -1, 1),
					math.clamp(mouse.Y / camera.ViewportSize.Y * 2 - 1, -1, 1)
				)
				parallax = parallax:Lerp(target, math.min(1, ambientDt * 3))
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
				-- StormChaser : nuages plus sombres et lueurs internes au hasard
				setCloudColor(cloud, stormy and cloudStorm or cloudColor:Lerp(cloudStorm, 0.07 * chaserLevel))
				updateGlow(cloud, ambientDt, stormy and 7 or chaserLevel * 0.12)

				-- Pluie + éclaboussures
				local shapeH = cloud.Shape.H
				for _, drop in ipairs(cloud.Drops) do
					drop.Y += drop.Speed * ambientDt * (stormy and 1.4 or 1)
					if drop.Y > RAIN_FALL then
						splashAt(cloud, drop.X - RAIN_FALL * 0.25)
						drop.Y = 0
						drop.X = random:NextNumber(16, cloud.Shape.W - 16)
					end
					drop.Frame.Position = UDim2.fromOffset(drop.X - drop.Y * 0.25, shapeH - 8 + drop.Y)
				end
				for _, splash in ipairs(cloud.Splashes) do
					if splash.Active then
						splash.Age += ambientDt * 3
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
				local glowAlpha = 0.74 - 0.03 * chaserLevel + math.sin(now * 22) * 0.08 + coreAlpha * 0.2
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
		ctx.FloatText(container, position + UDim2.fromOffset(0, 44), pickLine(CHEERS, random), Theme.Colors.Orange, 24)
	end)
end

function Weather.Stop(_ctx)
	-- Éclairs dans ctx.Container (détruit par le StimulusManager) ; nuages
	-- d'ambiance dans le calque Background, détruits avec ce conteneur
end

return Weather
