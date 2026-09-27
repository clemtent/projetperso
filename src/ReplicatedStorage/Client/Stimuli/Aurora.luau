--[[
	Aurora (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Aurora

	🌌 Aurore boréale (gains x2, après 2 visites à l'océan) : deux rideaux
	d'aurore pendent du haut du ciel sur toute la largeur de l'écran. Chaque
	rideau est fait de bandes verticales arrondies (les « plis » du rideau :
	violet en haut qui se fond dans le ciel -> turquoise -> ourlet vert
	lumineux et arrondi en bas) qui ondulent lentement, avec quelques
	étoiles au-dessus.
	L'ourlet dessine une arche : juste au-dessus du bouton au centre (jamais
	sur le compteur), il descend le long des couloirs entre les cartes sur
	les côtés : c'est là que le fond se voit en fin de partie.
	Effet d'ambiance (pas de place réservée, sous les cartes). Clair :
	couleurs aquarelle plus profondes ; sombre : couleurs néon.
	≤ 12 images/s, ~63 instances, rien créé par image.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local Aurora = {}
Aurora.Slot = "Background"

local STARS = 5
local TOP = 22 -- haut des bandes (sous le bandeau d'actualités)
local HEM_CENTRE = 60 -- ourlet au centre : juste au-dessus du bouton
local HEM_DIP = 150 -- de combien l'ourlet descend vers les bords

type Curtain = {
	Count: number,
	Lift: number, -- décalage de l'ourlet (px)
	Amp: number,
	Speed: number,
	Phase: number,
	Widen: number, -- largeur d'une bande / pas
	Frames: { Frame },
	Seeds: { number },
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
		table.clear(stars)
		canvas = Zones.GetCanvas()
		local holder = Kit.Box(container, { Name = "Aurora", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		root = holder

		local specs = {
			{ Count = 11, Lift = 0, Amp = 10, Speed = 0.45, Widen = 1.35, Alpha = if dark then 0.38 else 0.46 },
			{ Count = 8, Lift = -18, Amp = 8, Speed = -0.32, Widen = 1.1, Alpha = if dark then 0.5 else 0.56 },
		}
		for index, spec in ipairs(specs) do
			local colors = palette(dark, index)
			local curtain: Curtain = {
				Count = spec.Count,
				Lift = spec.Lift,
				Amp = spec.Amp,
				Speed = spec.Speed,
				Phase = random:NextNumber(0, 6),
				Widen = spec.Widen,
				Frames = {},
				Seeds = {},
			}
			-- Bande : haut transparent -> milieu turquoise -> ourlet lumineux arrondi
			local sequence = Kit.Colors({ 0, colors[1], 0.55, colors[2], 1, colors[3] })
			local fade = Kit.Fade({ 0, 1, 0.42, 0.64, 0.84, 0.12, 1, 0.3 })
			for _ = 1, spec.Count do
				local strip = Kit.Box(holder, {
					Name = "Fold",
					AnchorPoint = Vector2.new(0.5, 1),
					Color = Color3.new(1, 1, 1),
					Alpha = spec.Alpha,
					ZIndex = index,
				})
				Kit.Corner(strip, UDim.new(0.5, 0))
				Kit.Gradient(strip, sequence, fade, 90)
				table.insert(curtain.Frames, strip)
				table.insert(curtain.Seeds, random:NextNumber(0, 6))
			end
			table.insert(curtains, curtain)
		end

		-- Étoiles du ciel
		for _ = 1, STARS do
			local star = Kit.Diamond(
				holder,
				random:NextNumber(0.05, 0.95) * canvas.X,
				random:NextNumber(32, 52),
				random:NextInteger(3, 5),
				if dark then Kit.Rgb(255, 255, 255) else Kit.Rgb(255, 190, 80),
				0,
				4
			)
			table.insert(stars, { Frame = star, Phase = random:NextNumber(0, 6) })
		end
	end

	-- Place les bandes le long de l'ourlet (onde qui avance)
	local function layout(t: number)
		local width = canvas.X
		for _, curtain in ipairs(curtains) do
			local step = width / (curtain.Count - 1)
			local phase = curtain.Phase + t * curtain.Speed
			for s, strip in ipairs(curtain.Frames) do
				local seed = curtain.Seeds[s]
				local x = (s - 1) * step + math.sin(t * 0.35 + seed) * step * 0.12
				local bottom = hem(x, curtain.Lift) + math.sin(phase + s * 0.9) * curtain.Amp
				strip.Position = UDim2.fromOffset(x, bottom)
				strip.Size = UDim2.fromOffset(step * curtain.Widen, math.max(24, bottom - TOP - 6 + math.sin(t * 0.8 + seed * 2) * 8))
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

	Kit.Loop(ctx, 12, function(_dt, t)
		if effects then
			layout(t)
		end
		for _, star in ipairs(stars) do
			star.Frame.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(t * 1.8 + star.Phase))
		end
	end)
end

return Aurora
