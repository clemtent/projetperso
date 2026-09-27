--[[
	DeepFocus (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > DeepFocus

	🧘 Concentration (+/s, 10 niveaux, après 1 visite à l'océan) : des anneaux
	zen concentriques, fins et calmes (menthe, turquoise, lavande), centrés
	sur le compteur de Dopamine, qui RESPIRENT lentement (inspire 4 s,
	expire 4 s) ; à chaque respiration, une onde douce part du centre.
	Chaque niveau ajoute un anneau (3 au niveau 1, 12 au niveau 10) et plus
	de lueur ; niveau 3+ : perles de concentration qui tournent sur les
	anneaux ; niveau 6+ : halo doux derrière le compteur ; niveau 10 :
	anneau extérieur doré.
	Effet d'ambiance (derrière la colonne centrale, très transparent : le
	compteur reste parfaitement lisible). Une seule propriété (UIScale)
	anime la respiration de tous les anneaux. ≤ 20 images/s.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local DeepFocus = {}
DeepFocus.Slot = "Background"

local ID = "DeepFocus"
local MAX_LEVEL = 10
local FIRST_RADIUS = 96
local RING_GAP = 21
local BREATH = 8 -- secondes par respiration complète
local CUT_BELOW = 22 -- les anneaux s'arrêtent 22 px sous le centre du compteur

local COLORS = {
	Color3.fromRGB(110, 220, 200),
	Color3.fromRGB(90, 190, 230),
	Color3.fromRGB(170, 150, 240),
}

local function ringCount(level: number): number
	return 2 + level
end

local function beadCount(level: number): number
	return if level >= 3 then math.min(5, math.floor((level - 1) / 2)) else 0
end

function DeepFocus.Start(ctx)
	Zones.Attach(ctx)
	local effects = Kit.Effects(ctx)
	local level = math.clamp(ctx.GetLevel(ID), 1, MAX_LEVEL)
	local dark = Kit.IsDark(ctx)
	local container: Frame = ctx.Container

	local root: Frame? = nil
	local breathScale: UIScale? = nil
	local pulse: Frame? = nil
	local pulseStroke: UIStroke? = nil
	local glow: Frame? = nil
	type Bead = { Frame: Frame, Radius: number, Speed: number, Angle: number }
	local beads: { Bead } = {}
	local maxRadius = FIRST_RADIUS

	local function build()
		if root then
			root:Destroy()
		end
		table.clear(beads)
		local focus = Zones.GetFocus()
		local rings = ringCount(level)
		maxRadius = FIRST_RADIUS + (rings - 1) * RING_GAP
		local size = maxRadius * 2 + 40
		-- Porteur centré sur le compteur (l'UIScale fait respirer tout)
		local holder = Kit.Box(container, {
			Name = "FocusRings",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(focus.X, focus.Y),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
		})
		root = holder
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		breathScale = scale
		local c = size / 2

		-- Halo doux derrière le compteur (niveau 6+)
		if level >= 6 then
			glow = Kit.Ellipse(holder, c, c, 420, 150, if dark then Kit.Rgb(90, 220, 200) else Kit.Rgb(150, 235, 220), 0.88, 1)
		else
			glow = nil
		end

		-- Les anneaux sont coupés juste sous le nombre : des arches au-dessus
		-- du bouton et autour du compteur, rien derrière la ligne "par
		-- seconde" ni les pastilles.
		local arch = Kit.Box(holder, {
			Name = "Arch",
			Size = UDim2.fromOffset(size, c + CUT_BELOW),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
		})

		-- Anneaux (plus transparents vers l'extérieur, plus lumineux à chaque niveau)
		for index = 1, rings do
			local radius = FIRST_RADIUS + (index - 1) * RING_GAP
			local golden = level >= 10 and index == rings
			local color = if golden then Kit.Rgb(255, 204, 100) else COLORS[(index - 1) % #COLORS + 1]
			local alpha = math.clamp(0.64 + index * 0.022 - level * 0.02, 0.42, 0.88)
			if not dark then
				alpha = math.clamp(alpha + 0.04, 0.44, 0.9)
			end
			local ring = Kit.Ring(arch, c, c, radius * 2, color, if golden then 3 else (if index % 3 == 1 then 2 else 1.5), alpha, 2)
			ring.Name = "Ring"
		end

		-- Onde de respiration
		local wave, stroke = Kit.Ring(arch, c, c, FIRST_RADIUS * 2, COLORS[1], 2, 1, 2)
		wave.Name = "Breath"
		pulse, pulseStroke = wave, stroke

		-- Perles de concentration (passent sous "l'horizon" du compteur)
		for index = 1, beadCount(level) do
			local ringIndex = 1 + (index * 2) % rings
			local radius = FIRST_RADIUS + (ringIndex - 1) * RING_GAP
			local bead = Kit.Circle(arch, c, c, 7, Kit.Rgb(255, 255, 255), 0, 3)
			Kit.Stroke(bead, COLORS[(index - 1) % #COLORS + 1], 2, 0)
			table.insert(beads, { Frame = bead, Radius = radius, Speed = (if index % 2 == 0 then -1 else 1) * (0.25 + index * 0.04), Angle = index * 1.3 - math.pi / 2 })
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
	ctx.Connect(Zones.Changed, function()
		local holder = root
		if holder then
			local focus = Zones.GetFocus()
			holder.Position = UDim2.fromOffset(focus.X, focus.Y)
		end
	end)

	Kit.Loop(ctx, 20, function(dt, t)
		local phase = (t % BREATH) / BREATH
		local breath = 0.5 - 0.5 * math.cos(phase * math.pi * 2) -- 0 -> 1 -> 0
		local scale = breathScale
		if scale then
			scale.Scale = 0.97 + breath * 0.06
		end
		local halo = glow
		if halo then
			halo.BackgroundTransparency = 0.9 - breath * 0.05
		end
		-- Onde : part du centre à chaque inspiration
		local wave, stroke = pulse, pulseStroke
		if wave and stroke and effects then
			local c = wave.Parent and (wave.Parent :: Frame).Size.X.Offset / 2 or 0
			local d = (FIRST_RADIUS * 0.6 + phase * (maxRadius - FIRST_RADIUS * 0.6 + 30)) * 2
			wave.Position = UDim2.fromOffset(c, c)
			wave.Size = UDim2.fromOffset(d, d)
			stroke.Transparency = 0.45 + phase * 0.55
		end
		for _, bead in ipairs(beads) do
			bead.Angle += bead.Speed * dt
			local holder = root
			if holder then
				local c = holder.Size.X.Offset / 2
				bead.Frame.Position = UDim2.fromOffset(c + math.cos(bead.Angle) * bead.Radius, c + math.sin(bead.Angle) * bead.Radius)
			end
		end
	end)
end

return DeepFocus
