--[[
	GalaxyStream (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > GalaxyStream

	🌠 Rivière galactique (+/s, 10 niveaux, après 5 visites à l'océan) : une
	rivière d'étoiles traverse le fond de l'écran : un voile lumineux violet
	/ rose avec un courant plus clair au milieu, et des étoiles qui coulent le
	long du courant, scintillent et se recyclent au bout.
	Le tracé est choisi parmi plusieurs courbes (diagonales, arches, S) : celle
	qui passe le plus dans le fond VISIBLE (Cosmos/Zones.PickPath : ni cartes,
	ni colonne, ni objets posés), recalculé quand la mise en page change.
	Chaque niveau rend la rivière plus dense et plus lumineuse :
	  - étoiles : 10 + 3 par niveau (40 au niveau 10), voile plus large ;
	  - niveau 4+ : éclats dorés ; niveau 7+ : étoiles filantes le long du
	    courant ; niveau 10 : courant central doré.
	Effet d'ambiance (sous les cartes). ≤ 15 images/s, particules recyclées.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local GalaxyStream = {}
GalaxyStream.Slot = "Background"

local ID = "GalaxyStream"
local MAX_LEVEL = 10
local SAMPLES = 48 -- points du chemin (précalculés)
local BAND_SEGMENTS = 6

-- Tracés possibles (4 points de contrôle, fractions de la toile)
local ROUTES = {
	{ Vector2.new(-0.06, 0.97), Vector2.new(0.3, 0.8), Vector2.new(0.62, 0.62), Vector2.new(1.06, 0.2) }, -- bas-gauche -> haut-droite
	{ Vector2.new(-0.06, 0.2), Vector2.new(0.38, 0.42), Vector2.new(0.62, 0.74), Vector2.new(1.06, 0.98) }, -- haut-gauche -> bas-droite
	{ Vector2.new(0.24, -0.06), Vector2.new(0.2, 0.62), Vector2.new(0.8, 0.42), Vector2.new(0.76, 1.06) }, -- S (couloir gauche, gouttière droite)
	{ Vector2.new(0.76, -0.06), Vector2.new(0.8, 0.62), Vector2.new(0.2, 0.42), Vector2.new(0.24, 1.06) }, -- S miroir
	{ Vector2.new(-0.06, 0.6), Vector2.new(0.3, 1.1), Vector2.new(0.7, 1.1), Vector2.new(1.06, 0.6) }, -- arche basse
}

local STAR_COLORS_DARK = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(200, 224, 255),
	Color3.fromRGB(255, 200, 240),
	Color3.fromRGB(200, 180, 255),
}
local STAR_COLORS_LIGHT = {
	Color3.fromRGB(120, 80, 230),
	Color3.fromRGB(60, 120, 230),
	Color3.fromRGB(230, 80, 170),
	Color3.fromRGB(150, 90, 240),
}

local function starCount(level: number): number
	return 10 + 3 * level
end

function GalaxyStream.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local level = math.clamp(ctx.GetLevel(ID), 1, MAX_LEVEL)
	local dark = Kit.IsDark(ctx)
	local container: Frame = ctx.Container

	local root: Frame? = nil
	local route = 1
	local points: { Vector2 } = {}
	local normals: { Vector2 } = {}
	type Star = { Frame: Frame, U: number, Lane: number, Speed: number, Phase: number, Twinkle: boolean }
	local stars: { Star } = {}
	local streak: Frame? = nil
	local streakU = -1

	local function width(): number
		return 64 + level * 5
	end

	-- Chemin en pixels (toile) + normales
	local function computePath()
		local canvas = Zones.GetCanvas()
		table.clear(points)
		table.clear(normals)
		local controls = ROUTES[route]
		for index = 0, SAMPLES do
			local p = Zones.Bezier(controls, index / SAMPLES)
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
		return a:Lerp(b, k), normals[math.min(#normals, i + 1)]
	end

	local function build()
		if root then
			root:Destroy()
		end
		table.clear(stars)
		streak = nil
		computePath()
		local holder = Kit.Box(container, { Name = "GalaxyStream", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		root = holder

		-- Voile de la rivière + courant central : segments le long de la courbe
		local edge = if dark then Kit.Rgb(160, 110, 255) else Kit.Rgb(140, 100, 240)
		local other = if dark then Kit.Rgb(255, 130, 210) else Kit.Rgb(236, 110, 196)
		local core = (if dark then 0.6 else 0.66) - level * 0.012
		local fade = Kit.Fade({ 0, 1, 0.3, core + 0.16, 0.5, core, 0.7, core + 0.16, 1, 1 })
		local coreColor = if level >= 10 then Kit.Rgb(255, 222, 140) elseif dark then Kit.Rgb(240, 230, 255) else Kit.Rgb(255, 255, 255)
		local w = width()
		for s = 1, BAND_SEGMENTS do
			local a = pathAt((s - 1) / BAND_SEGMENTS)
			local b = pathAt(s / BAND_SEGMENTS)
			local delta = b - a
			local centre = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			local rotation = math.deg(math.atan2(delta.Y, delta.X))
			local segment = Kit.Box(holder, {
				Name = "Band",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = centre,
				Size = UDim2.fromOffset(delta.Magnitude + w * 0.5, w),
				Rotation = rotation,
				Color = Color3.new(1, 1, 1),
				ZIndex = 1,
			})
			Kit.Gradient(segment, ColorSequence.new(edge, other), fade, 90)
			Kit.Box(holder, {
				Name = "Current",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = centre,
				Size = UDim2.fromOffset(delta.Magnitude + 8, 6),
				Rotation = rotation,
				Color = coreColor,
				Alpha = math.clamp((if dark then 0.72 else 0.6) - level * 0.02, 0.4, 0.8),
				ZIndex = 2,
			})
		end

		-- Étoiles qui coulent
		local palette = if dark then STAR_COLORS_DARK else STAR_COLORS_LIGHT
		for index = 1, starCount(level) do
			local gold = level >= 4 and index % 6 == 0
			local size = if gold then 7 elseif index % 4 == 0 then 5 else random:NextInteger(3, 4)
			local frame = Kit.Box(holder, {
				Name = "Star",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
				Rotation = 45,
				Color = if gold then Kit.Rgb(255, 204, 90) else palette[(index - 1) % #palette + 1],
				ZIndex = 3,
			})
			table.insert(stars, {
				Frame = frame,
				U = random:NextNumber(),
				Lane = random:NextNumber(-1, 1) * random:NextNumber(0.15, 1),
				Speed = random:NextNumber(0.02, 0.045),
				Phase = random:NextNumber(0, 6),
				Twinkle = index % 2 == 0,
			})
		end

		-- Étoile filante (niveau 7+)
		if level >= 7 then
			local line = Kit.Box(holder, {
				Name = "ShootingStar",
				AnchorPoint = Vector2.new(1, 0.5),
				Size = UDim2.fromOffset(52, 3),
				Color = if dark then Color3.new(1, 1, 1) else Kit.Rgb(255, 196, 80),
				Alpha = 1,
				ZIndex = 4,
			})
			Kit.Gradient(line, nil, Kit.Fade({ 0, 1, 1, 0 }), 0)
			streak = line
		end
	end

	-- Choisit le tracé le plus visible (après chaque planification des places)
	local function pickRoute(force: boolean?)
		local best = Zones.PickPath(ROUTES, width())
		if best ~= route or force then
			route = best
			build()
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
		local resized = (now - lastCanvas).Magnitude > 1
		lastCanvas = now
		pickRoute(resized)
	end)
	-- Pas encore d'objet cosmique à placer : planification quand même (pour le tracé)
	Zones.Schedule()

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
				star.Frame.BackgroundTransparency = 0.05 + 0.6 * (0.5 + 0.5 * math.sin(t * 2.6 + star.Phase))
			end
		end
		local line = streak
		if line and effects then
			if streakU < 0 then
				if random:NextNumber() < dt * 0.3 then
					streakU = 0
				end
			else
				streakU += dt * 0.5
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
