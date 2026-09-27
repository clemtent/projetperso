--[[
	Aurora (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Aurora

	🌌 Aurore boréale (gains x2, après 2 visites à l'océan) : deux rideaux
	d'aurore pendent du haut du ciel sur toute la largeur de l'écran (voiles
	violet -> turquoise -> vert, ourlet lumineux en bas), parcourus de rayons
	verticaux qui ondulent, avec quelques étoiles.
	L'ourlet dessine une arche : juste au-dessus du bouton au centre (jamais
	sur le compteur), il descend le long des couloirs entre les cartes sur
	les côtés : c'est là que le fond se voit en fin de partie.
	Effet d'ambiance (pas de place réservée, sous les cartes). Clair :
	couleurs aquarelle plus profondes ; sombre : couleurs néon.
	≤ 12 images/s, ~55 instances, rien créé par image.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local Aurora = {}
Aurora.Slot = "Background"

local VEILS = 8 -- voiles par rideau
local RAYS = 8
local STARS = 5
local TOP = 24 -- haut des voiles (sous le bandeau d'actualités)
local HEM_CENTRE = 60 -- ourlet au centre : juste au-dessus du bouton
local HEM_DIP = 150 -- de combien l'ourlet descend vers les bords

type Curtain = {
	Lift: number, -- décalage de l'ourlet (px)
	Amp: number,
	Speed: number,
	Phase: number,
	Frames: { Frame },
}

local function palette(dark: boolean, index: number): { Color3 }
	-- { haut, milieu, ourlet }
	if dark then
		return if index == 1
			then { Color3.fromRGB(170, 110, 255), Color3.fromRGB(70, 210, 255), Color3.fromRGB(100, 255, 180) }
			else { Color3.fromRGB(255, 110, 210), Color3.fromRGB(140, 120, 255), Color3.fromRGB(110, 240, 255) }
	end
	return if index == 1
		then { Color3.fromRGB(150, 96, 236), Color3.fromRGB(40, 166, 228), Color3.fromRGB(30, 196, 140) }
		else { Color3.fromRGB(230, 90, 186), Color3.fromRGB(120, 100, 236), Color3.fromRGB(40, 190, 220) }
end

function Aurora.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local dark = Kit.IsDark(ctx)
	local container: Frame = ctx.Container

	local root: Frame? = nil
	local curtains: { Curtain } = {}
	type Ray = { Frame: Frame, X: number, Phase: number, Length: number }
	local rays: { Ray } = {}
	local stars: { { Frame: Frame, Phase: number } } = {}
	local canvas = Zones.GetCanvas()

	-- Hauteur de l'ourlet à l'abscisse x (arche : haut au centre, bas sur les côtés)
	local function hem(x: number, lift: number): number
		local half = canvas.X / 2
		local ratio = math.clamp(math.abs(x - half) / half, 0, 1)
		return HEM_CENTRE + lift + HEM_DIP * ratio ^ 1.6
	end

	local function build()
		if root then
			root:Destroy()
		end
		table.clear(curtains)
		table.clear(rays)
		table.clear(stars)
		canvas = Zones.GetCanvas()
		local holder = Kit.Box(container, { Name = "Aurora", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		root = holder

		local specs = {
			{ Lift = 0, Amp = 9, Speed = 0.4, Alpha = if dark then 0.34 else 0.4 },
			{ Lift = -16, Amp = 7, Speed = -0.3, Alpha = if dark then 0.42 else 0.48 },
		}
		for index, spec in ipairs(specs) do
			local colors = palette(dark, index)
			local curtain: Curtain = { Lift = spec.Lift, Amp = spec.Amp, Speed = spec.Speed, Phase = random:NextNumber(0, 6), Frames = {} }
			local sequence = Kit.Colors({ 0, colors[1], 0.55, colors[2], 1, colors[3] })
			local fade = Kit.Fade({ 0, 1, 0.4, 0.62, 0.86, 0.1, 1, 0.55 })
			for _ = 1, VEILS do
				local veil = Kit.Box(holder, {
					Name = "Veil",
					AnchorPoint = Vector2.new(0.5, 1),
					Color = Color3.new(1, 1, 1),
					Alpha = spec.Alpha,
					ZIndex = index,
				})
				Kit.Gradient(veil, sequence, fade, 90)
				table.insert(curtain.Frames, veil)
			end
			table.insert(curtains, curtain)
		end

		-- Rayons (fins traits lumineux près de l'ourlet)
		local rayColor = if dark then Kit.Rgb(200, 255, 230) else Kit.Rgb(40, 190, 150)
		for index = 1, RAYS do
			local frame = Kit.Box(holder, {
				Name = "Ray",
				AnchorPoint = Vector2.new(0.5, 1),
				Color = rayColor,
				Alpha = if dark then 0.25 else 0.35,
				ZIndex = 3,
			})
			Kit.Gradient(frame, nil, Kit.Fade({ 0, 1, 0.7, 0.3, 1, 0.1 }), 90)
			table.insert(rays, {
				Frame = frame,
				X = (index - 0.5) / RAYS + random:NextNumber(-0.04, 0.04),
				Phase = random:NextNumber(0, 6),
				Length = random:NextNumber(36, 60),
			})
		end

		-- Étoiles du ciel
		for _ = 1, STARS do
			local star = Kit.Diamond(
				holder,
				random:NextNumber(0.05, 0.95) * canvas.X,
				random:NextNumber(34, 56),
				random:NextInteger(3, 5),
				if dark then Kit.Rgb(255, 255, 255) else Kit.Rgb(255, 190, 80),
				0,
				4
			)
			table.insert(stars, { Frame = star, Phase = random:NextNumber(0, 6) })
		end
	end

	-- Place voiles et rayons le long de l'ourlet (onde qui avance)
	local function layout(t: number)
		local width = canvas.X
		local step = width / (VEILS - 1)
		for _, curtain in ipairs(curtains) do
			local phase = curtain.Phase + t * curtain.Speed
			for s, veil in ipairs(curtain.Frames) do
				local x = (s - 1) * step
				local bottom = hem(x, curtain.Lift) + math.sin(phase + s * 0.95) * curtain.Amp
				veil.Position = UDim2.fromOffset(x, bottom)
				veil.Size = UDim2.fromOffset(step * 1.5, math.max(24, bottom - TOP))
			end
		end
		for _, ray in ipairs(rays) do
			local x = ray.X * width + math.sin(t * 0.6 + ray.Phase) * 10
			local bottom = hem(x, 0) + 2
			ray.Frame.Position = UDim2.fromOffset(x, bottom)
			ray.Frame.Size = UDim2.fromOffset(3, ray.Length * (0.75 + 0.25 * math.sin(t * 1.3 + ray.Phase)))
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

	Kit.Loop(ctx, 12, function(_dt, t)
		if effects then
			layout(t)
			for _, ray in ipairs(rays) do
				ray.Frame.BackgroundTransparency = (if dark then 0.25 else 0.35) + 0.35 * (0.5 + 0.5 * math.sin(t * 2.2 + ray.Phase))
			end
		end
		for _, star in ipairs(stars) do
			star.Frame.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(t * 1.8 + star.Phase))
		end
	end)
end

return Aurora
