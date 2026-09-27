--[[
	GalaxyStream (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > GalaxyStream

	🌠 Rivière galactique (+/s, 10 niveaux, après 5 visites à l'océan) : une
	rivière d'étoiles traverse tout le fond de l'écran en diagonale douce
	(du bas à gauche vers le haut à droite, SOUS le compteur) : un voile
	lumineux violet / rose et des étoiles qui coulent le long du courant,
	scintillent et se recyclent au bout.
	Chaque niveau rend la rivière plus dense et plus lumineuse :
	  - étoiles : 14 + 3 par niveau (44 au niveau 10) ;
	  - voile de plus en plus lumineux et large ;
	  - niveau 4+ : des éclats dorés ; niveau 7+ : étoiles filantes le long
	    du courant ; niveau 10 : cœur brillant de la rivière.
	Effet d'ambiance (pas de place réservée, passe derrière les cartes et se
	voit dans tous les espaces libres). ≤ 15 images/s, particules recyclées.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local GalaxyStream = {}
GalaxyStream.Slot = "Background"

local ID = "GalaxyStream"
local MAX_LEVEL = 10
local SAMPLES = 48 -- points du chemin (précalculés)
local BAND_SEGMENTS = 5

local STAR_COLORS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(200, 220, 255),
	Color3.fromRGB(255, 200, 240),
	Color3.fromRGB(190, 170, 255),
}

local function starCount(level: number): number
	return 14 + 3 * level
end

-- Courbe de la rivière (fractions de la toile) : Bézier cubique
local P0, P1, P2, P3 = Vector2.new(-0.06, 0.97), Vector2.new(0.3, 0.8), Vector2.new(0.62, 0.62), Vector2.new(1.06, 0.2)

local function bezier(u: number): Vector2
	local a = 1 - u
	return P0 * (a * a * a) + P1 * (3 * a * a * u) + P2 * (3 * a * u * u) + P3 * (u * u * u)
end

function GalaxyStream.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local level = math.clamp(ctx.GetLevel(ID), 1, MAX_LEVEL)
	local dark = Kit.IsDark(ctx)
	local container: Frame = ctx.Container

	local root: Frame? = nil
	local points: { Vector2 } = {}
	local normals: { Vector2 } = {}
	local band: { Frame } = {}
	type Star = { Frame: Frame, U: number, Lane: number, Speed: number, Phase: number, Twinkle: boolean }
	local stars: { Star } = {}
	local streak: Frame? = nil
	local streakU = -1

	-- Chemin en pixels (toile) + normales
	local function computePath()
		local canvas = Zones.GetCanvas()
		table.clear(points)
		table.clear(normals)
		for index = 0, SAMPLES do
			local p = bezier(index / SAMPLES)
			points[index + 1] = Vector2.new(p.X * canvas.X, p.Y * canvas.Y)
		end
		for index = 1, #points do
			local a = points[math.max(1, index - 1)]
			local b = points[math.min(#points, index + 1)]
			local d = (b - a).Unit
			normals[index] = Vector2.new(-d.Y, d.X)
		end
	end

	-- Point du chemin (u de 0 à 1) + normale
	local function pathAt(u: number): (Vector2, Vector2)
		local f = math.clamp(u, 0, 1) * SAMPLES
		local i = math.floor(f)
		local k = f - i
		local a, b = points[i + 1], points[math.min(#points, i + 2)]
		return a:Lerp(b, k), normals[i + 1]
	end

	local function width(): number
		return 70 + level * 6
	end

	local function build()
		if root then
			root:Destroy()
		end
		table.clear(band)
		table.clear(stars)
		streak = nil
		computePath()
		local holder = Kit.Box(container, { Name = "GalaxyStream", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		root = holder

		-- Voile de la rivière : segments le long de la courbe
		local veilColor = if dark then Kit.Rgb(170, 120, 255) else Kit.Rgb(150, 110, 240)
		local core = if dark then 0.62 - level * 0.012 else 0.72 - level * 0.012
		local fade = Kit.Fade({ 0, 1, 0.3, core + 0.14, 0.5, core, 0.7, core + 0.14, 1, 1 })
		for s = 1, BAND_SEGMENTS do
			local u0, u1 = (s - 1) / BAND_SEGMENTS, s / BAND_SEGMENTS
			local a = pathAt(u0)
			local b = pathAt(u1)
			local delta = b - a
			local segment = Kit.Box(holder, {
				Name = "Band",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
				Size = UDim2.fromOffset(delta.Magnitude + 60, width()),
				Rotation = math.deg(math.atan2(delta.Y, delta.X)),
				Color = Color3.new(1, 1, 1),
				ZIndex = 1,
			})
			Kit.Corner(segment, width() / 2)
			Kit.Gradient(segment, ColorSequence.new(veilColor, if dark then Kit.Rgb(255, 140, 210) else Kit.Rgb(240, 120, 200)), fade, 90)
			table.insert(band, segment)
		end

		-- Étoiles qui coulent
		for index = 1, starCount(level) do
			local gold = level >= 4 and index % 7 == 0
			local size = if gold then 5 elseif index % 5 == 0 then 4 else random:NextInteger(2, 3)
			local color = if gold then Kit.Rgb(255, 214, 110) else STAR_COLORS[(index - 1) % #STAR_COLORS + 1]
			if not dark and not gold then
				color = color:Lerp(Kit.Rgb(120, 90, 220), 0.45)
			end
			local frame = Kit.Box(holder, {
				Name = "Star",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
				Rotation = 45,
				Color = color,
				ZIndex = 2,
			})
			table.insert(stars, {
				Frame = frame,
				U = random:NextNumber(),
				Lane = random:NextNumber(-1, 1) * random:NextNumber(0.2, 1),
				Speed = random:NextNumber(0.018, 0.04),
				Phase = random:NextNumber(0, 6),
				Twinkle = index % 2 == 0,
			})
		end

		-- Étoile filante (niveau 7+)
		if level >= 7 then
			local line = Kit.Box(holder, {
				Name = "ShootingStar",
				AnchorPoint = Vector2.new(1, 0.5),
				Size = UDim2.fromOffset(46, 2),
				Color = Color3.new(1, 1, 1),
				Alpha = 1,
				ZIndex = 3,
			})
			Kit.Gradient(line, nil, Kit.Fade({ 0, 1, 1, 0 }), 0)
			streak = line
		end

		-- Cœur brillant (niveau 10) : un 2e voile fin au centre du courant
		if level >= 10 then
			for s = 1, BAND_SEGMENTS do
				local source = band[s]
				local coreLine = Kit.Box(holder, {
					Name = "Core",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = source.Position,
					Size = UDim2.fromOffset(source.Size.X.Offset - 40, 10),
					Rotation = source.Rotation,
					Color = Kit.Rgb(255, 236, 255),
					Alpha = if dark then 0.6 else 0.7,
					ZIndex = 1,
				})
				Kit.Corner(coreLine, 5)
			end
		end
	end

	build()
	Kit.WatchLevel(ctx, ID, function(newLevel)
		level = math.clamp(newLevel, 1, MAX_LEVEL)
		build()
	end)
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		build()
	end)
	local lastCanvas = Zones.GetCanvas()
	ctx.Connect(Zones.Changed, function()
		local now = Zones.GetCanvas()
		if (now - lastCanvas).Magnitude > 1 then
			lastCanvas = now
			build()
		end
	end)

	Kit.Loop(ctx, 15, function(dt, t)
		local half = width() / 2 - 6
		local count = if effects then #stars else math.floor(#stars / 2)
		for index = 1, count do
			local star = stars[index]
			star.U += dt * star.Speed
			if star.U > 1 then
				star.U -= 1
			end
			local p, n = pathAt(star.U)
			local sway = math.sin(t * 0.7 + star.Phase) * 0.12
			local position = p + n * ((star.Lane + sway) * half)
			star.Frame.Position = UDim2.fromOffset(position.X, position.Y)
			if star.Twinkle then
				star.Frame.BackgroundTransparency = 0.1 + 0.7 * (0.5 + 0.5 * math.sin(t * 2.6 + star.Phase))
			end
		end
		local line = streak
		if line and effects then
			if streakU < 0 then
				if random:NextNumber() < dt * 0.25 then
					streakU = 0
				end
			else
				streakU += dt * 0.45
				if streakU > 1 then
					streakU = -1
					line.BackgroundTransparency = 1
				else
					local p = pathAt(streakU)
					local q = pathAt(math.min(1, streakU + 0.01))
					local d = q - p
					line.Position = UDim2.fromOffset(p.X, p.Y)
					line.Rotation = math.deg(math.atan2(d.Y, d.X))
					line.BackgroundTransparency = if streakU < 0.1 then 1 - streakU / 0.1 elseif streakU > 0.85 then (streakU - 0.85) / 0.15 else 0
				end
			end
		end
	end)
end

return GalaxyStream
