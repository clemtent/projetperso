--[[
	Disco (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Disco

	v9 : une VRAIE boule à facettes (calque Overlay), suspendue par une
	chaîne au-dessus du bandeau d'actu, à droite de la colonne centrale
	(x = centre + 360 : au-dessus des cartes du haut, sans cacher R1 / CR ;
	la chaîne monte dans la barre du haut de Roblox) :
	  - la boule : 7 rangées de facettes carrées projetées sur une sphère
	    (plus étroites vers les bords = relief), ombrées par une lumière en
	    haut à gauche, séparées par des joints sombres ; en tournant, un
	    motif de luminosité défile sur chaque rangée (scintillement), des
	    reflets colorés passent et des facettes flashent (étoile ✦) ;
	    gros reflet doux fixe, calotte + anneau + chaîne, léger balancement ;
	  - fins rayons de lumière qui partent de la boule et balayent l'écran
	    en tournant (ils s'estompent au loin), 3 larges faisceaux colorés
	    qui vont et viennent, et une pluie de petites taches de lumière
	    projetées (les reflets des facettes) qui glissent sur tout l'écran,
	    plus 3 halos colorés très doux ;
	  - rien n'est cliquable : les clics passent à travers.
	Spectaculaire mais pas éblouissant : tout est semi-transparent, les
	rayons sont fins. Coût : UNE boucle OnRender, mise à jour 30 fois par
	seconde (facettes 12 fois par seconde) ; aucune création d'instance
	après le départ. Effets coupés (⚙️) : moins de rayons, pas de taches.
]]

local Disco = {}
Disco.Slot = "Overlay"

local BALL_X = 360 -- décalage depuis le centre de l'écran
local BALL_Y = 18 -- centre de la boule (le bandeau d'actu fait y 0-30 ; les cartes commencent à y = 40)
local BALL_D = 50
local PIVOT_Y = -74 -- point d'attache de la chaîne (au-dessus de l'écran)
local UPDATE_STEP = 1 / 30
local FACET_STEP = 1 / 12
local RAY_COUNT = 12
local BEAM_COUNT = 3
local SPOT_COUNT = 20
local POOL_COUNT = 3
local SPARKLE_COUNT = 4
local RING = 24 -- facettes sur le tour complet d'une rangée
local SPIN_SPEED = 3 -- facettes / seconde (la boule fait un tour en ~8 s)
local SWEEP_SPEED = 13 -- degrés / seconde (rayons et taches)
local RANGE_MIN, RANGE_MAX = 6, 174 -- angles visibles (0 = droite, 90 = bas)

local WHITE = Color3.new(1, 1, 1)
local GROUT = Color3.fromRGB(46, 48, 62)

local PALETTE = {
	Color3.fromRGB(255, 96, 206), -- rose
	Color3.fromRGB(86, 222, 255), -- cyan
	Color3.fromRGB(176, 116, 255), -- violet
	Color3.fromRGB(255, 214, 96), -- or
	Color3.fromRGB(128, 255, 170), -- menthe
}

-- Rangées (latitudes en degrés, du haut vers le bas) et colonnes (longitudes)
local LATITUDES = { 70, 57, 44, 31, 18, 6, -6, -18, -31, -44, -57, -70 }
local LONGITUDES = { -75, -60, -45, -30, -15, 0, 15, 30, 45, 60, 75 }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Fondu en entrée / sortie de la zone visible (0..1)
local function edgeFade(angle: number): number
	return math.clamp(math.min(angle - RANGE_MIN, RANGE_MAX - angle) / 18, 0, 1)
end

function Disco.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end
	local fullEffects = effectsOn()

	local root = Create("Frame", {
		Name = "Disco",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 1,
		Parent = container,
	})

	local function round(guiObject: GuiObject)
		UIUtil.Corner(guiObject, UDim.new(1, 0))
	end

	------------------------------------------------------------------
	-- Halos colorés très doux (derrière tout)
	------------------------------------------------------------------
	local pools = {}
	if fullEffects then
		for index = 1, POOL_COUNT do
			local size = random:NextInteger(200, 280)
			local pool = Create("Frame", {
				Name = "Pool",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = PALETTE[index],
				BackgroundTransparency = 0.93,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = root,
			})
			round(pool)
			table.insert(pools, {
				Frame = pool,
				A = random:NextNumber(0.1, 0.22),
				B = random:NextNumber(0.08, 0.18),
				P = random:NextNumber(0, math.pi * 2),
				Q = random:NextNumber(0, math.pi * 2),
				Hue = index / POOL_COUNT,
			})
		end
	end

	------------------------------------------------------------------
	-- Larges faisceaux colorés (vont et viennent) et fins rayons
	------------------------------------------------------------------
	local beams = {}
	for index = 1, (fullEffects and BEAM_COUNT or 2) do
		local beam = Create("Frame", {
			Name = "Beam",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(1500, random:NextInteger(28, 38)),
			BackgroundColor3 = PALETTE[index],
			BackgroundTransparency = 0.62,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = root,
		})
		Create("UIGradient", {
			Color = ColorSequence.new(WHITE),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.2, 0.25),
				NumberSequenceKeypoint.new(0.65, 0.85),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = beam,
		})
		table.insert(beams, {
			Frame = beam,
			Length = 1500,
			Base = 45 + (index - 1) * (90 / math.max(1, BEAM_COUNT - 1)),
			Amp = random:NextNumber(26, 40),
			Freq = random:NextNumber(0.22, 0.4) * (index % 2 == 0 and -1 or 1),
			Phase = random:NextNumber(0, math.pi * 2),
			Hue = (index - 1) / BEAM_COUNT,
		})
	end

	local rays = {}
	for index = 1, (fullEffects and RAY_COUNT or 5) do
		local length = random:NextInteger(520, 1250)
		local ray = Create("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(length, random:NextInteger(2, 5)),
			BackgroundColor3 = WHITE:Lerp(PALETTE[(index - 1) % #PALETTE + 1], 0.35),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = root,
		})
		Create("UIGradient", {
			Color = ColorSequence.new(WHITE),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
		table.insert(rays, {
			Frame = ray,
			Length = length,
			Offset = (index - 1) * (RANGE_MAX - RANGE_MIN) / (fullEffects and RAY_COUNT or 5) + random:NextNumber(-6, 6),
			Alpha = random:NextNumber(0.3, 0.5),
			Twinkle = random:NextNumber(0, math.pi * 2),
		})
	end

	------------------------------------------------------------------
	-- Taches de lumière projetées (les reflets des facettes)
	------------------------------------------------------------------
	local spots = {}
	if fullEffects then
		for index = 1, SPOT_COUNT do
			-- Distance = fraction de la distance au bord de l'écran dans sa direction
			local reach = random:NextNumber(0.12, 0.95)
			local size = math.floor(5 + reach * 5 + random:NextNumber(0, 3))
			local color = PALETTE[(index - 1) % #PALETTE + 1]
			-- Halo coloré (doux) + cœur lumineux (petit carré arrondi, en losange)
			local glow = Create("Frame", {
				Name = "Spot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size * 3, size * 3),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.8,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = root,
			})
			round(glow)
			local core = Create("Frame", {
				Name = "Core",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = WHITE:Lerp(color, 0.3),
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Rotation = 45,
				ZIndex = 5,
				Parent = glow,
			})
			UIUtil.Corner(core, math.max(1, math.floor(size / 3)))
			table.insert(spots, {
				Frame = glow,
				Core = core,
				Reach = reach,
				Offset = random:NextNumber(0, RANGE_MAX - RANGE_MIN),
				Speed = SWEEP_SPEED * random:NextNumber(0.8, 1.2) * (reach < 0.35 and 1.15 or 1),
				Alpha = random:NextNumber(0.65, 0.9),
				Twinkle = random:NextNumber(0, math.pi * 2),
			})
		end
	end

	------------------------------------------------------------------
	-- La boule, sa calotte et sa chaîne (dans un support qui se balance
	-- autour du point d'attache : Rotation tourne autour du CENTRE d'un
	-- cadre, donc le support est centré sur le point d'attache)
	------------------------------------------------------------------
	local radius = BALL_D / 2
	local hang = BALL_Y - PIVOT_Y -- distance point d'attache -> centre de la boule
	local half = hang + radius + 10
	local holder = Create("Frame", {
		Name = "Hanger",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, BALL_X, 0, PIVOT_Y),
		Size = UDim2.fromOffset(half * 2, half * 2),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})
	local ballX, ballY = half, half + hang -- centre de la boule dans le support

	-- Chaîne : maillons ovales (creux) et maillons vus de profil, alternés
	local capTop = ballY - radius - 6
	local linkY = half + 2
	local linkIndex = 0
	while linkY < capTop - 3 do
		linkIndex += 1
		if linkIndex % 2 == 1 then
			local link = Create("Frame", {
				Name = "Link",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(ballX, linkY),
				Size = UDim2.fromOffset(6, 9),
				BackgroundTransparency = 1,
				ZIndex = 6,
				Parent = holder,
			})
			round(link)
			UIUtil.Stroke(link, Color3.fromRGB(196, 198, 214), 1.6, 0)
		else
			Create("Frame", {
				Name = "Link",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(ballX, linkY - 1),
				Size = UDim2.fromOffset(2, 11),
				BackgroundColor3 = Color3.fromRGB(150, 152, 170),
				BorderSizePixel = 0,
				ZIndex = 7,
				Parent = holder,
			})
		end
		linkY += 7
	end
	-- Anneau + calotte
	local eye = Create("Frame", {
		Name = "Eye",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(ballX, capTop - 1),
		Size = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = holder,
	})
	round(eye)
	UIUtil.Stroke(eye, Color3.fromRGB(214, 216, 230), 2, 0)
	local cap = Create("Frame", {
		Name = "Cap",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(ballX, capTop + 2),
		Size = UDim2.fromOffset(14, 7),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = holder,
	})
	UIUtil.Corner(cap, 3)
	UIUtil.Gradient(cap, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 122, 140)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(246, 246, 252)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 98, 116)),
	}), 0)
	UIUtil.Stroke(cap, Color3.fromRGB(30, 30, 40), 1, 0.4)

	-- Halo coloré autour de la boule
	local halo = Create("Frame", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(ballX, ballY),
		Size = UDim2.fromOffset(BALL_D + 26, BALL_D + 26),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = holder,
	})
	round(halo)

	-- Boule : joints sombres (fond), facettes par-dessus
	local ball = Create("Frame", {
		Name = "Ball",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(ballX, ballY),
		Size = UDim2.fromOffset(BALL_D, BALL_D),
		BackgroundColor3 = GROUT,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = holder,
	})
	round(ball)
	UIUtil.Stroke(ball, Color3.fromRGB(20, 20, 30), 1.2, 0.2)

	-- Facettes : projection des rangées / colonnes sur la sphère
	local lightLength = math.sqrt(0.45 ^ 2 + 0.55 ^ 2 + 0.7 ^ 2)
	local lightX, lightY, lightZ = -0.45 / lightLength, -0.55 / lightLength, 0.7 / lightLength
	local facets = {}
	for row = 1, #LATITUDES - 1 do
		local top, bottom = math.rad(LATITUDES[row]), math.rad(LATITUDES[row + 1])
		local middle = (top + bottom) / 2
		local y1 = radius - radius * math.sin(top)
		local y2 = radius - radius * math.sin(bottom)
		for column = 1, #LONGITUDES - 1 do
			local left, right = math.rad(LONGITUDES[column]), math.rad(LONGITUDES[column + 1])
			local x1 = radius + radius * math.cos(middle) * math.sin(left)
			local x2 = radius + radius * math.cos(middle) * math.sin(right)
			local width, height = x2 - x1 - 1, y2 - y1 - 1
			if width >= 1.2 and height >= 1.2 then
				local lon = (left + right) / 2
				-- Normale (x droite, y bas, z vers nous) : ombrage fixe (lumière en haut à gauche)
				local nx, ny, nz = math.cos(middle) * math.sin(lon), -math.sin(middle), math.cos(middle) * math.cos(lon)
				local lambert = math.max(0, nx * lightX + ny * lightY + nz * lightZ)
				local shade = (0.3 + 0.7 * lambert ^ 0.8) * (0.55 + 0.45 * nz)
				local facet = Create("Frame", {
					Name = "Facet",
					Position = UDim2.fromOffset(x1 + 0.5, y1 + 0.5),
					Size = UDim2.fromOffset(width, height),
					BackgroundColor3 = Color3.new(shade, shade, shade),
					BorderSizePixel = 0,
					ZIndex = 8,
					Parent = ball,
				})
				table.insert(facets, {
					Frame = facet,
					Row = row,
					Column = column,
					Shade = shade,
					Center = Vector2.new(x1 + width / 2, y1 + height / 2),
					Flash = 0,
				})
			end
		end
	end

	-- Motifs de luminosité / de reflets colorés, un par rangée (tour complet)
	local patterns = {}
	for row = 1, #LATITUDES - 1 do
		local values, tints = {}, {}
		for index = 1, RING do
			local roll = random:NextNumber()
			values[index] = roll < 0.12 and random:NextNumber(0.95, 1.25) or random:NextNumber(0.25, 0.85)
			tints[index] = random:NextNumber() < 0.14 and random:NextInteger(1, #PALETTE) or 0
		end
		patterns[row] = { Values = values, Tints = tints, Offset = random:NextNumber(0, RING) }
	end

	-- Reflet doux fixe (la lumière ne tourne pas avec la boule)
	local shine = Create("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(radius * 0.62, radius * 0.56),
		Size = UDim2.fromOffset(19, 13),
		Rotation = -35,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.38,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = ball,
	})
	round(shine)
	local shineCore = Create("Frame", {
		Name = "ShineCore",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 4),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = shine,
	})
	round(shineCore)

	------------------------------------------------------------------
	-- Étincelles ✦ sur les facettes qui flashent (réserve recyclée)
	------------------------------------------------------------------
	local sparkles = {}
	for index = 1, SPARKLE_COUNT do
		local star = UIUtil.Label({
			Name = "Sparkle",
			Text = "✦",
			TextColor3 = WHITE,
			TextTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			MaxTextSize = 18,
			Visible = false,
			ZIndex = 12,
			Parent = holder,
		})
		local stroke = UIUtil.Stroke(star, Color3.fromRGB(110, 70, 170), 1, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		sparkles[index] = { Label = star, Stroke = stroke, Scale = Create("UIScale", { Scale = 0.2, Parent = star }), Age = 1, Spin = 0 }
	end
	local nextSparkle = 1

	local function flashFacet()
		local facet = facets[random:NextInteger(1, #facets)]
		-- Surtout les facettes bien éclairées (face à nous)
		if facet.Shade < 0.45 then
			facet = facets[random:NextInteger(1, #facets)]
		end
		facet.Flash = 1
		local sparkle = sparkles[nextSparkle]
		nextSparkle = nextSparkle % SPARKLE_COUNT + 1
		sparkle.Age = 0
		sparkle.Spin = random:NextNumber(-60, 60)
		sparkle.Label.Position = UDim2.fromOffset(ballX - radius + facet.Center.X, ballY - radius + facet.Center.Y)
		sparkle.Label.Visible = true
	end

	local function stepSparkles(dt: number)
		for _, sparkle in ipairs(sparkles) do
			if sparkle.Age < 1 then
				sparkle.Age = math.min(1, sparkle.Age + dt / 0.6)
				local age = sparkle.Age
				local grow = math.clamp(age / 0.3, 0, 1)
				sparkle.Scale.Scale = 0.2 + 0.9 * math.sin(grow * math.pi / 2) - 0.5 * math.max(0, age - 0.3)
				sparkle.Label.TextTransparency = age ^ 2
				sparkle.Stroke.Transparency = 0.4 + 0.6 * age
				sparkle.Label.Rotation = sparkle.Spin * age
				if sparkle.Age >= 1 then
					sparkle.Label.Visible = false
				end
			end
		end
	end

	------------------------------------------------------------------
	-- Animation (30 fois par seconde ; facettes 12 fois par seconde)
	------------------------------------------------------------------
	local time = 0
	local pending = 0
	local facetClock = 0
	local flashClock = 0
	local spin = 0

	local function updateFacets(hue: number)
		local tintBoost = 0.28 + 0.1 * math.sin(time * 1.7)
		for _, facet in ipairs(facets) do
			local pattern = patterns[facet.Row]
			local position = (facet.Column + spin + pattern.Offset) % RING
			local index = math.floor(position)
			local frac = position - index
			local a = pattern.Values[index + 1]
			local b = pattern.Values[(index + 1) % RING + 1]
			local value = lerp(a, b, frac)
			local brightness = math.min(1, facet.Shade * (0.62 + 0.7 * value))
			local color = Color3.new(brightness * 0.97, brightness * 0.98, math.min(1, brightness * 1.05))
			local tint = pattern.Tints[index + 1]
			if tint > 0 then
				local tintColor = PALETTE[(tint + math.floor(hue * #PALETTE)) % #PALETTE + 1]
				color = color:Lerp(tintColor, tintBoost * math.min(1, facet.Shade + 0.3))
			end
			if facet.Flash > 0 then
				color = color:Lerp(WHITE, facet.Flash)
				facet.Flash = math.max(0, facet.Flash - FACET_STEP * 3.5)
			end
			facet.Frame.BackgroundColor3 = color
		end
	end

	ctx.OnRender(function(dt: number)
		pending += dt
		if pending < UPDATE_STEP then
			return
		end
		local step = math.min(pending, 0.1)
		pending = 0
		time += step
		spin = (spin + step * SPIN_SPEED) % RING
		local hue = (time * 0.05) % 1

		-- Balancement (autour du point d'attache) et centre de la boule
		local sway = math.sin(time * 0.9) * 2.2
		holder.Rotation = sway
		local swayRad = math.rad(sway)
		local cx = BALL_X - hang * math.sin(swayRad)
		local cy = PIVOT_Y + hang * math.cos(swayRad)

		-- Larges faisceaux (vont et viennent, couleur qui change doucement)
		for _, beam in ipairs(beams) do
			local angle = beam.Base + math.sin(time * beam.Freq + beam.Phase) * beam.Amp
			local radians = math.rad(angle)
			local halfLength = beam.Length / 2
			beam.Frame.Position = UDim2.new(0.5, cx + math.cos(radians) * halfLength, 0, cy + math.sin(radians) * halfLength)
			beam.Frame.Rotation = angle
			beam.Frame.BackgroundColor3 = Color3.fromHSV((hue + beam.Hue) % 1, 0.72, 1)
			beam.Frame.BackgroundTransparency = 0.58 + 0.12 * (0.5 + 0.5 * math.sin(time * 1.3 + beam.Phase))
		end

		-- Fins rayons : ils tournent avec la boule, entrent d'un côté et sortent de l'autre
		local sweepRange = RANGE_MAX - RANGE_MIN
		for _, ray in ipairs(rays) do
			local angle = RANGE_MIN + (ray.Offset + time * SWEEP_SPEED) % sweepRange
			local radians = math.rad(angle)
			local halfLength = ray.Length / 2
			ray.Frame.Position = UDim2.new(0.5, cx + math.cos(radians) * halfLength, 0, cy + math.sin(radians) * halfLength)
			ray.Frame.Rotation = angle
			local alpha = ray.Alpha * edgeFade(angle) * (0.75 + 0.25 * math.sin(time * 4 + ray.Twinkle))
			ray.Frame.BackgroundTransparency = 1 - alpha
		end

		-- Taches de lumière (reflets projetés qui glissent sur l'écran, toujours dedans)
		local canvas = ctx.Interface.CanvasSize or Vector2.new(1280, 720)
		local originX = canvas.X / 2 + cx
		for _, spot in ipairs(spots) do
			local angle = RANGE_MIN + (spot.Offset + time * spot.Speed) % sweepRange
			local radians = math.rad(angle)
			local dx, dy = math.cos(radians), math.sin(radians)
			local toEdgeX = dx > 0.01 and (canvas.X - originX) / dx or (dx < -0.01 and originX / -dx or math.huge)
			local toEdgeY = dy > 0.01 and (canvas.Y - cy) / dy or math.huge
			local distance = math.min(toEdgeX, toEdgeY, 1400) * spot.Reach
			spot.Frame.Position = UDim2.new(0.5, cx + dx * distance, 0, cy + dy * distance)
			local alpha = spot.Alpha * edgeFade(angle) * (0.65 + 0.35 * math.sin(time * 3.2 + spot.Twinkle))
			spot.Core.BackgroundTransparency = 1 - alpha
			spot.Frame.BackgroundTransparency = 1 - alpha * 0.28
		end

		-- Halos colorés (courbes de Lissajous)
		for _, pool in ipairs(pools) do
			pool.Frame.Position = UDim2.fromScale(0.5 + math.sin(time * pool.A + pool.P) * 0.42, 0.55 + math.sin(time * pool.B + pool.Q) * 0.36)
			pool.Frame.BackgroundColor3 = Color3.fromHSV((hue + pool.Hue) % 1, 0.65, 1)
		end

		halo.BackgroundColor3 = Color3.fromHSV(hue, 0.35, 1)
		halo.BackgroundTransparency = 0.78 + 0.06 * math.sin(time * 2.4)

		-- Facettes
		facetClock += step
		if facetClock >= FACET_STEP then
			facetClock = 0
			updateFacets(hue)
		end

		-- Facettes qui flashent + étincelles
		flashClock += step
		if flashClock >= 0.45 then
			flashClock = random:NextNumber(-0.2, 0.1)
			flashFacet()
		end
		stepSparkles(step)
	end)
end

return Disco
