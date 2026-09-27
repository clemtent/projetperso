--[[
	DreamMachine (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > DreamMachine

	💤 Machine à rêves (+/s, 10 niveaux, après 2 visites à l'océan) : une
	petite machine rétro (corps lavande, écran « z », bouton, voyants,
	ampoule qui s'allume) souffle des bulles de pensée vers des NUAGES DE
	RÊVE ; dans le premier nuage, des moutons sautent une barrière l'un
	après l'autre (compter les moutons !). Chaque niveau ajoute quelque chose :
	  1 : machine + 1 nuage + 1 mouton     6 : 3e nuage (lune et étoiles)
	  2 : voyants qui clignotent            7 : 3e mouton
	  3 : 2e nuage (mouton qui dort)        8 : liseré doré + étincelles
	  4 : 2e mouton                         9 : ampoule arc-en-ciel
	  5 : rayon de rêve (lumière)          10 : 4e mouton + « zZ » de la machine
	Trois mises en page, Cosmos/Zones choisit celle qui se voit le mieux :
	HAUTE (nuages empilés au-dessus de la machine : gouttières entre les
	cartes du bas sur PC), LARGE (nuages à droite : bas des téléphones) ou
	CARRÉE (2-3 nuages autour de la machine : côtés des tablettes).
	Calque Background, ≤ 20 images/s, objets recyclés.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local DreamMachine = {}
DreamMachine.Slot = "Background"

local UPGRADE_ID = "DreamMachine"
local MAX_LEVEL = 10

-- Tailles de la boîte selon le nombre de nuages (1, 2, 3)
local TALL_W = 106
local TALL_H = { 222, 292, 366 }
local WIDE_H = 160
local WIDE_W = { 238, 340, 438 }
local SQUARE_W, SQUARE_H = 238, 176 -- 2 ou 3 nuages

-- Formes (index Cosmos/Zones) : 0 = haute, 1 = large, 2 = carrée
local TALL, WIDE, SQUARE = 0, 1, 2

-- Nuages : taille intérieure
local CLOUD_SIZE = {
	Vector2.new(104, 76),
	Vector2.new(92, 58),
	Vector2.new(84, 54),
}

local function cloudCount(level: number): number
	return if level >= 6 then 3 elseif level >= 3 then 2 else 1
end

local function sheepCount(level: number): number
	return if level >= 10 then 4 elseif level >= 7 then 3 elseif level >= 4 then 2 else 1
end

-- Positions (centre) : machine, ampoule, bulles, nuages, selon la mise en page
type Layout = {
	W: number,
	H: number,
	Device: Vector2,
	Bulb: Vector2,
	Bubbles: { Vector3 }, -- x, y, diamètre
	Clouds: { Vector2 },
	Beam: { Vector2 }, -- début, fin
}

local function layoutFor(shape: number, clouds: number): Layout
	if shape == WIDE then
		local w = WIDE_W[clouds]
		return {
			W = w,
			H = WIDE_H,
			Device = Vector2.new(52, 116),
			Bulb = Vector2.new(70, 82),
			Bubbles = { Vector3.new(86, 70, 6), Vector3.new(98, 58, 9), Vector3.new(112, 46, 12) },
			Clouds = { Vector2.new(178, 70), Vector2.new(288, 104), Vector2.new(390, 60) },
			Beam = { Vector2.new(70, 82), Vector2.new(170, 70) },
		}
	elseif shape == SQUARE and clouds >= 2 then
		return {
			W = SQUARE_W,
			H = SQUARE_H,
			Device = Vector2.new(54, 138),
			Bulb = Vector2.new(73, 102),
			Bubbles = { Vector3.new(88, 90, 6), Vector3.new(100, 78, 9), Vector3.new(114, 66, 12) },
			Clouds = { Vector2.new(180, 52), Vector2.new(54, 44), Vector2.new(184, 140) },
			Beam = { Vector2.new(73, 102), Vector2.new(176, 58) },
		}
	end
	local h = TALL_H[clouds]
	return {
		W = TALL_W,
		H = h,
		Device = Vector2.new(53, h - 36),
		Bulb = Vector2.new(72, h - 72),
		Bubbles = { Vector3.new(78, h - 90, 6), Vector3.new(70, h - 103, 9), Vector3.new(59, h - 118, 12) },
		Clouds = { Vector2.new(53, h - 166), Vector2.new(50, h - 252), Vector2.new(56, h - 326) },
		Beam = { Vector2.new(72, h - 72), Vector2.new(53, h - 160) },
	}
end

function DreamMachine.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local level = math.clamp(ctx.GetLevel(UPGRADE_ID), 1, MAX_LEVEL)
	local dark = Kit.IsDark(ctx)
	local shape = TALL
	local piece = Kit.Piece(ctx.Container, "DreamMachine", TALL_W, TALL_H[1])

	-- Éléments animés (remplis par build)
	local content: Frame? = nil
	type Sheep = { Frame: Frame, Offset: number }
	local sheep: { Sheep } = {}
	local cloud1: Frame? = nil
	local floaters: { { Frame: Frame, Base: UDim2, Phase: number, Amp: number } } = {}
	local lights: { Frame } = {}
	local twinkles: { { Frame: Frame, Phase: number } } = {}
	local bulb: Frame? = nil
	local bulbGlow: Frame? = nil
	local beam: UIGradient? = nil
	local screenZ: TextLabel? = nil
	local sleeper: Frame? = nil
	local floatZs: { { Label: TextLabel, Origin: Vector2, Offset: number } } = {}

	local function float(frame: Frame, amplitude: number)
		table.insert(floaters, { Frame = frame, Base = frame.Position, Phase = random:NextNumber(0, math.pi * 2), Amp = amplitude })
	end

	-- Mouton (corps laineux, tête et pattes sombres). (x, y) = centre.
	-- 6 instances (7 avec contour) : corps + coins, tête + coins, 2 pattes.
	local function makeSheep(parent: Instance, x: number, y: number, z: number, outline: boolean?): Frame
		local body = Kit.Box(parent, {
			Name = "Sheep",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(20, 14),
			Color = Color3.new(1, 1, 1),
			ZIndex = z,
		})
		Kit.Corner(body, 7)
		if outline then
			Kit.Stroke(body, Kit.Rgb(150, 140, 200), 1, 0)
		end
		local head = Kit.Ellipse(body, 19, 6, 8, 9, Kit.Rgb(64, 56, 84), 0, z + 1)
		head.Name = "Head"
		Kit.Box(body, { Name = "LegA", Position = UDim2.fromOffset(4, 13), Size = UDim2.fromOffset(2, 4), Color = Kit.Rgb(64, 56, 84), ZIndex = z })
		Kit.Box(body, { Name = "LegB", Position = UDim2.fromOffset(13, 13), Size = UDim2.fromOffset(2, 4), Color = Kit.Rgb(64, 56, 84), ZIndex = z })
		return body
	end

	-- Nuage de rêve : intérieur "ciel du soir" + bord blanc duveteux.
	-- Renvoie l'intérieur (qui découpe son contenu).
	local function makeCloud(parent: Instance, index: number, centre: Vector2): Frame
		local size = CLOUD_SIZE[index]
		local rim = if dark then Color3.new(1, 1, 1) else Kit.Rgb(214, 206, 252)
		local holder = Kit.Box(parent, {
			Name = "Cloud" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(centre.X, centre.Y),
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundTransparency = 1,
			ZIndex = 4,
		})
		-- Bosses du nuage (derrière l'intérieur)
		local bumps = if index == 1 then { { 0.3, 34 }, { 0.68, 28 } } else { { 0.42, 30 } }
		for _, bump in ipairs(bumps) do
			local puff = Kit.Circle(holder, size.X * bump[1], 4, bump[2], rim, 0, 4)
			puff.Name = "Puff"
		end
		local inside = Kit.Box(holder, {
			Name = "Inside",
			Size = UDim2.fromScale(1, 1),
			Color = Color3.new(1, 1, 1),
			ClipsDescendants = true,
			ZIndex = 5,
		})
		Kit.Corner(inside, 18)
		local top = if index == 1 then Kit.Rgb(126, 150, 246) else Kit.Rgb(108, 116, 226)
		local bottom = if index == 1 then Kit.Rgb(178, 150, 240) else Kit.Rgb(84, 70, 170)
		Kit.Gradient(inside, ColorSequence.new(top, bottom), nil, 90)
		Kit.Stroke(inside, rim, 3, 0)
		float(holder, if index == 1 then 1.5 else 2.2)
		return inside
	end

	local function build()
		if content then
			content:Destroy()
		end
		table.clear(sheep)
		table.clear(floaters)
		table.clear(lights)
		table.clear(twinkles)
		table.clear(floatZs)
		bulb, bulbGlow, beam, screenZ, sleeper, cloud1 = nil, nil, nil, nil, nil, nil

		local clouds = cloudCount(level)
		local layout = layoutFor(shape, clouds)
		piece.Frame.Size = UDim2.fromOffset(layout.W, layout.H)
		local ink = Kit.Ink(dark)
		local root = Kit.Box(piece.Frame, {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		})
		content = root

		-- Rayon de rêve (niveau 5+) : de l'ampoule vers le 1er nuage
		if level >= 5 then
			local from, to = layout.Beam[1], layout.Beam[2]
			local delta = to - from
			local ray = Kit.Box(root, {
				Name = "Beam",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2),
				Size = UDim2.fromOffset(delta.Magnitude, 26),
				Rotation = math.deg(math.atan2(delta.Y, delta.X)),
				Color = Kit.Rgb(255, 236, 150),
				Alpha = if dark then 0.35 else 0.45,
				ZIndex = 2,
			})
			beam = Kit.Gradient(ray, nil, Kit.Fade({ 0, 0.25, 0.45, 0.6, 1, 1 }), 0)
		end

		-- Nuages de rêve
		for index = 1, clouds do
			local inside = makeCloud(root, index, layout.Clouds[index])
			local size = CLOUD_SIZE[index]
			if index == 1 then
				cloud1 = inside
				-- Herbe + barrière
				local grass = Kit.Box(inside, {
					Name = "Grass",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -3),
					Size = UDim2.new(1, -14, 0, 11),
					Color = Kit.Rgb(122, 214, 132),
					ZIndex = 6,
				})
				Kit.Corner(grass, 5)
				local wood = Kit.Rgb(196, 140, 96)
				local fx, groundY = size.X / 2, size.Y - 12
				for _, dx in ipairs({ -8, 8 }) do
					Kit.Box(inside, { Name = "Post", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(fx + dx, groundY + 2), Size = UDim2.fromOffset(4, 21), Color = wood, ZIndex = 7 })
				end
				for _, dy in ipairs({ -15, -7 }) do
					Kit.Box(inside, { Name = "Rail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(fx, groundY + dy), Size = UDim2.fromOffset(28, 3), Color = wood, ZIndex = 7 })
				end
				-- Moutons (recyclés : traversent le nuage en boucle)
				local count = sheepCount(level)
				for k = 1, count do
					local body = makeSheep(inside, -20, groundY - 8, 9)
					table.insert(sheep, { Frame = body, Offset = (k - 1) / count })
				end
				-- Deux étoiles dans le ciel du rêve
				for _, spec in ipairs({ { 0.16, 0.22, 4 }, { 0.84, 0.3, 3 } }) do
					local star = Kit.Diamond(inside, size.X * spec[1], size.Y * spec[2], spec[3], Kit.Rgb(255, 246, 204), 0, 6)
					table.insert(twinkles, { Frame = star, Phase = random:NextNumber(0, 6) })
				end
			elseif index == 2 then
				-- Un mouton qui dort sur un petit nuage-lit
				local bed = Kit.Ellipse(inside, size.X / 2, size.Y - 13, 46, 14, Kit.Rgb(222, 216, 255), 0.15, 6)
				bed.Name = "Bed"
				local body = makeSheep(inside, size.X / 2 - 2, size.Y - 24, 8, true)
				body.Rotation = -6
				sleeper = body
				local z = Kit.Text(inside, "z", size.X / 2 + 16, size.Y - 38, 12, Kit.Rgb(240, 236, 255), 9)
				table.insert(floatZs, { Label = z, Origin = Vector2.new(size.X / 2 + 14, size.Y - 34), Offset = 0 })
			else
				-- Lune (croissant : "morsure" au dégradé exact du ciel) et étoiles
				local skyTop, skyBottom = Kit.Rgb(108, 116, 226), Kit.Rgb(84, 70, 170)
				local moonX, moonY = size.X * 0.38, size.Y * 0.52
				Kit.Circle(inside, moonX, moonY, 26, Kit.Rgb(255, 226, 130), 0, 6)
				local biteY = moonY - 6
				local bite = Kit.Circle(inside, moonX + 9, biteY, 22, Color3.new(1, 1, 1), 0, 7)
				Kit.Gradient(bite, ColorSequence.new(skyTop:Lerp(skyBottom, (biteY - 11) / size.Y), skyTop:Lerp(skyBottom, (biteY + 11) / size.Y)), nil, 90)
				for _, spec in ipairs({ { 0.7, 0.3, 5 }, { 0.8, 0.66, 3 }, { 0.58, 0.8, 3 } }) do
					local star = Kit.Diamond(inside, size.X * spec[1], size.Y * spec[2], spec[3], Kit.Rgb(255, 246, 204), 0, 8)
					table.insert(twinkles, { Frame = star, Phase = random:NextNumber(0, 6) })
				end
			end
		end

		-- Bulles de pensée
		for _, spec in ipairs(layout.Bubbles) do
			local bubble = Kit.Circle(root, spec.X, spec.Y, spec.Z, if dark then Kit.Rgb(236, 232, 255) else Color3.new(1, 1, 1), 0, 3)
			bubble.Name = "Thought"
			if not dark then
				Kit.Stroke(bubble, Kit.Rgb(170, 158, 230), 1, 0)
			end
			float(bubble, 1.2)
		end

		-- Machine
		local d = layout.Device
		local bodyColor = Kit.Rgb(206, 186, 255)
		-- Ampoule sur sa tige (à droite, au-dessus)
		local b = layout.Bulb
		Kit.Box(root, { Name = "Stem", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(b.X, b.Y + 4), Size = UDim2.fromOffset(3, d.Y - 26 - b.Y - 4), Color = Kit.Rgb(150, 126, 210), ZIndex = 9 })
		bulbGlow = Kit.Circle(root, b.X, b.Y, 26, Kit.Rgb(255, 232, 140), 0.7, 9)
		bulb = Kit.Circle(root, b.X, b.Y, 14, Kit.Rgb(255, 226, 120), 0, 10)
		local body = Kit.Box(root, {
			Name = "Machine",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(d.X, d.Y),
			Size = UDim2.fromOffset(86, 52),
			Color = Color3.new(1, 1, 1),
			ZIndex = 11,
		})
		Kit.Corner(body, 16)
		Kit.Gradient(body, ColorSequence.new(bodyColor, Kit.Rgb(150, 122, 236)), nil, 90)
		Kit.Stroke(body, if level >= 8 then Kit.Rgb(255, 200, 90) elseif dark then Kit.Rgb(236, 226, 255) else ink, if level >= 8 then 2.5 else 2, if dark and level < 8 then 0.3 else 0)
		-- Pieds
		Kit.Box(root, { Name = "Feet", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(d.X, d.Y + 22), Size = UDim2.fromOffset(62, 9), Color = Kit.Rgb(120, 96, 196), ZIndex = 10 })
		-- Écran rond avec un « z »
		local screen = Kit.Circle(body, 26, 26, 32, Kit.Rgb(40, 40, 104), 0, 12)
		screenZ = Kit.Text(screen, "z", 16, 15, 17, Kit.Rgb(255, 232, 150), 13)
		-- Bouton rose
		Kit.Circle(body, 66, 18, 12, Kit.Rgb(255, 138, 196), 0, 12)
		-- Voyants (clignotent au niveau 2+)
		for index, color in ipairs({ Kit.Rgb(120, 240, 190), Kit.Rgb(255, 150, 210), Kit.Rgb(255, 226, 120) }) do
			local light = Kit.Box(body, {
				Name = "Light",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(52 + index * 7, 38),
				Size = UDim2.fromOffset(5, 5),
				Color = color,
				Alpha = if level >= 2 then 0 else 0.55,
				Rotation = 45,
				ZIndex = 12,
			})
			table.insert(lights, light)
		end

		-- Étincelles autour de la machine (niveau 8+)
		if level >= 8 then
			for _, spec in ipairs({ { -48, -24, 7 }, { 50, -30, 5 }, { -42, 22, 5 } }) do
				local star = Kit.Diamond(root, d.X + spec[1], d.Y + spec[2], spec[3], Kit.Rgb(255, 214, 110), 0, 12)
				table.insert(twinkles, { Frame = star, Phase = random:NextNumber(0, 6) })
			end
		end

		-- « zZ » de la machine (niveau 10)
		if level >= 10 then
			for index = 1, 2 do
				local z = Kit.Text(root, if index == 1 then "z" else "Z", d.X - 30, d.Y - 36, 12 + index * 3, Kit.Rgb(236, 230, 255), 12)
				local stroke = Instance.new("UIStroke")
				stroke.Color = if dark then Kit.Rgb(70, 56, 140) else ink
				stroke.Thickness = 1.5
				stroke.Parent = z
				table.insert(floatZs, { Label = z, Origin = Vector2.new(d.X - 30, d.Y - 34), Offset = (index - 1) / 2 })
			end
		end
	end

	local function request()
		local clouds = cloudCount(level)
		local shapes = { Vector2.new(WIDE_W[clouds], WIDE_H) }
		if clouds >= 2 then
			table.insert(shapes, Vector2.new(SQUARE_W, SQUARE_H))
		end
		Zones.Request(UPGRADE_ID, {
			{
				W = TALL_W,
				H = TALL_H[clouds],
				Shapes = shapes,
				Anchor = Vector2.new(0.3, 0.84),
				MinScale = 0.45,
				MaxScale = 1.15,
				Force = true, -- la machine à rêves doit TOUJOURS se voir
			},
		}, function(placements)
			local placement = placements[1]
			if placement and placement.Shape ~= shape then
				shape = placement.Shape
				build()
			end
			Kit.Place(piece, placement)
		end)
	end

	build()
	request()

	Kit.WatchLevel(ctx, UPGRADE_ID, function(newLevel)
		local oldClouds = cloudCount(level)
		level = math.clamp(newLevel, 1, MAX_LEVEL)
		build()
		if cloudCount(level) ~= oldClouds then
			request()
		end
		Kit.Bump(piece)
	end)
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		build()
	end)

	-- Animation (20 images/s)
	Kit.Loop(ctx, 20, function(_dt, t)
		if not piece.Placed then
			return
		end
		-- Moutons : entrent à gauche, sautent la barrière, sortent à droite
		local inside = cloud1
		if inside then
			local width = CLOUD_SIZE[1].X
			local groundY = CLOUD_SIZE[1].Y - 20
			local fence = width / 2
			for _, s in ipairs(sheep) do
				local p = (t / 3.6 + s.Offset) % 1
				local x = -16 + p * (width + 32)
				local dx = (x - fence) / 21
				local lift = if math.abs(dx) < 1 then 22 * (1 - dx * dx) else math.abs(math.sin(p * 44)) * 1.5
				s.Frame.Position = UDim2.fromOffset(x, groundY - lift)
				s.Frame.Rotation = if math.abs(dx) < 1 then -dx * 16 else 0
			end
		end
		-- Nuages et bulles qui flottent
		for _, item in ipairs(floaters) do
			local base = item.Base
			item.Frame.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + math.sin(t * 1.1 + item.Phase) * item.Amp)
		end
		-- Voyants
		if level >= 2 then
			for index, light in ipairs(lights) do
				light.BackgroundTransparency = if math.floor(t * 3 + index) % 3 == 0 then 0.6 else 0
			end
		end
		-- Ampoule (arc-en-ciel au niveau 9+)
		local glow = bulbGlow
		if glow then
			glow.BackgroundTransparency = 0.62 + 0.18 * math.sin(t * 2.4)
			if level >= 9 then
				local color = Color3.fromHSV((t * 0.18) % 1, 0.45, 1)
				glow.BackgroundColor3 = color
				local core = bulb
				if core then
					core.BackgroundColor3 = color
				end
			end
		end
		local ray = beam
		if ray then
			ray.Offset = Vector2.new(math.sin(t * 1.6) * 0.08, 0)
		end
		local z = screenZ
		if z then
			z.Position = UDim2.fromOffset(16, 15 + math.sin(t * 2) * 2)
		end
		local sleeping = sleeper
		if sleeping then
			sleeping.Rotation = -6 + math.sin(t * 1.4) * 4
		end
		for _, fz in ipairs(floatZs) do
			local p = (t / 2.8 + fz.Offset) % 1
			fz.Label.Position = UDim2.fromOffset(fz.Origin.X + p * 12, fz.Origin.Y - p * 18)
			fz.Label.TextTransparency = if p < 0.2 then 1 - p / 0.2 elseif p > 0.7 then (p - 0.7) / 0.3 else 0
		end
		-- Étoiles qui scintillent (fixes si le joueur a coupé les effets)
		if effects then
			for _, star in ipairs(twinkles) do
				star.Frame.BackgroundTransparency = 0.1 + 0.6 * (0.5 + 0.5 * math.sin(t * 2.2 + star.Phase))
			end
		end
	end)
end

function DreamMachine.Stop(_ctx)
	Zones.Release(UPGRADE_ID)
end

return DreamMachine
