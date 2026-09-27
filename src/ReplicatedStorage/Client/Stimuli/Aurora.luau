--[[
	Aurora (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Aurora

	🌌 Aurore boréale (gains x2, après 2 visites à l'océan) : deux rubans
	d'aurore ondulent en haut du ciel, sur toute la largeur de l'écran
	(voiles verticaux vert -> turquoise -> violet, bord bas plus lumineux,
	haut qui se fond dans le ciel), avec quelques étoiles qui scintillent.
	On les voit derrière le bouton et le compteur et entre les cartes du
	haut. Chaque ruban = 7 voiles (cadres + dégradé vertical) dont la
	hauteur et l'inclinaison suivent une onde qui avance.
	Effet d'ambiance (pas de place réservée) : très transparent, jamais
	sur le texte du compteur. Clair : couleurs plus profondes ; sombre :
	couleurs néon. ≤ 15 images/s, ~40 instances.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local Aurora = {}
Aurora.Slot = "Background"

local SEGMENTS = 7
local STARS = 7

type Ribbon = {
	Y: number, -- hauteur du bas du ruban (px, toile)
	Height: number,
	Amp: number,
	Speed: number,
	Phase: number,
	Alpha: number,
	Colors: { Color3 }, -- bas, milieu, haut
	Frames: { Frame },
	Gradients: { UIGradient },
}

local function palette(dark: boolean, index: number): { Color3 }
	if dark then
		return if index == 1
			then { Color3.fromRGB(90, 255, 180), Color3.fromRGB(70, 210, 255), Color3.fromRGB(190, 120, 255) }
			else { Color3.fromRGB(120, 255, 160), Color3.fromRGB(255, 120, 220), Color3.fromRGB(140, 110, 255) }
	end
	return if index == 1
		then { Color3.fromRGB(30, 200, 150), Color3.fromRGB(40, 170, 225), Color3.fromRGB(150, 100, 235) }
		else { Color3.fromRGB(60, 205, 130), Color3.fromRGB(235, 100, 190), Color3.fromRGB(120, 100, 240) }
end

function Aurora.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local dark = Kit.IsDark(ctx)
	local container: Frame = ctx.Container

	local root: Frame? = nil
	local ribbons: { Ribbon } = {}
	local stars: { { Frame: Frame, Phase: number } } = {}
	local canvas = Zones.GetCanvas()

	local function build()
		if root then
			root:Destroy()
		end
		table.clear(ribbons)
		table.clear(stars)
		canvas = Zones.GetCanvas()
		local holder = Kit.Box(container, { Name = "Aurora", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		root = holder

		local specs = {
			{ Y = 122, Height = 104, Amp = 12, Speed = 0.35, Alpha = if dark then 0.5 else 0.6 },
			{ Y = 92, Height = 76, Amp = 10, Speed = -0.25, Alpha = if dark then 0.58 else 0.68 },
		}
		for index, spec in ipairs(specs) do
			local colors = palette(dark, index)
			local ribbon: Ribbon = {
				Y = spec.Y,
				Height = spec.Height,
				Amp = spec.Amp,
				Speed = spec.Speed,
				Phase = random:NextNumber(0, 6),
				Alpha = spec.Alpha,
				Colors = colors,
				Frames = {},
				Gradients = {},
			}
			-- Voiles : dégradé vertical (haut transparent -> bas lumineux)
			local sequence = Kit.Colors({ 0, colors[3], 0.55, colors[2], 1, colors[1] })
			local fade = Kit.Fade({ 0, 1, 0.45, 0.55, 0.86, 0.12, 1, 0.9 })
			for s = 1, SEGMENTS do
				local veil = Kit.Box(holder, {
					Name = "Veil",
					AnchorPoint = Vector2.new(0.5, 1),
					Color = Color3.new(1, 1, 1),
					Alpha = spec.Alpha,
					ZIndex = index,
				})
				Kit.Corner(veil, 40)
				table.insert(ribbon.Gradients, Kit.Gradient(veil, sequence, fade, 90))
				ribbon.Frames[s] = veil
			end
			table.insert(ribbons, ribbon)
		end

		-- Étoiles du ciel (entre les rubans et le haut de l'écran)
		for _ = 1, STARS do
			local star = Kit.Diamond(
				holder,
				random:NextNumber(0.05, 0.95) * canvas.X,
				random:NextNumber(40, 118),
				random:NextInteger(3, 5),
				if dark then Kit.Rgb(255, 255, 255) else Kit.Rgb(255, 196, 90),
				0,
				3
			)
			table.insert(stars, { Frame = star, Phase = random:NextNumber(0, 6) })
		end
	end

	-- Place les voiles le long de l'onde (appelé à chaque image d'animation)
	local function layout(t: number)
		local width = canvas.X
		local step = width / (SEGMENTS - 1)
		for _, ribbon in ipairs(ribbons) do
			local phase = ribbon.Phase + t * ribbon.Speed
			for s, veil in ipairs(ribbon.Frames) do
				local x = (s - 1) * step
				local wave = math.sin(phase + s * 0.95)
				local slope = math.cos(phase + s * 0.95)
				veil.Position = UDim2.fromOffset(x, ribbon.Y + wave * ribbon.Amp)
				veil.Size = UDim2.fromOffset(step * 1.45, ribbon.Height * (0.8 + 0.3 * (0.5 + 0.5 * math.sin(phase * 1.3 + s * 1.7))))
				veil.Rotation = slope * 7
			end
			for s, gradient in ipairs(ribbon.Gradients) do
				gradient.Offset = Vector2.new(0, 0.06 * math.sin(t * 0.8 + s))
			end
		end
	end

	build()
	layout(0)
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		build()
		layout(0)
	end)
	ctx.Connect(Zones.Changed, function()
		local now = Zones.GetCanvas()
		if math.abs(now.X - canvas.X) > 1 then
			canvas = now
			layout(0)
		end
	end)

	Kit.Loop(ctx, 15, function(_dt, t)
		if effects then
			layout(t)
		end
		for _, star in ipairs(stars) do
			star.Frame.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(t * 1.8 + star.Phase))
		end
	end)
end

return Aurora
