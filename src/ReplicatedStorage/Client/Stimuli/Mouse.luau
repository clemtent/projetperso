--[[
	Mouse (ModuleScript - stimulus) — amélioration "Souris gaming" (10 niveaux)
	Emplacement : ReplicatedStorage > Client > Stimuli > Mouse

	Une souris gaming vue de dessus, posée dans l'espace libre près de la
	colonne centrale (Gear/GearLayout). À chaque clic : le bouton gauche
	s'enfonce, des ondes de clic s'élargissent et les lumières RGB avancent.
	Chaque niveau ajoute quelque chose :
	  1 souris noire + câble          2 molette lumineuse
	  3 boutons latéraux               4 logo RGB
	  5 bande RGB                      6 tapis de souris (bord arc-en-ciel)
	  7 coque "nid d'abeille"          8 voyants DPI + ondes plus grandes
	  9 sans fil (ondes radio)         10 édition dorée, tout en RGB
	Au repos : les lumières "respirent" de temps en temps.
]]

local Gear = script.Parent:WaitForChild("Gear")
local GearKit = require(Gear:WaitForChild("GearKit"))
local GearPiece = require(Gear:WaitForChild("GearPiece"))

local Mouse = {}
Mouse.Slot = "Background" -- sous l'interface (effets de clic : calque Overlay)

local W, H = 72, 104
local INK = Color3.fromRGB(40, 34, 56)

local active: { [any]: any } = {}

function Mouse.Start(ctx)
	local animator = GearKit.Animator(ctx)
	local piece = GearPiece.new(ctx, {
		Id = "Mouse",
		Size = Vector2.new(W, H),
		Priority = 4,
		MinScale = 0.42,
		MaxScale = 1,
		GlowColor = Color3.fromRGB(190, 240, 255),
		ContainerZ = 95,
		Anchor = function(button, _canvas)
			-- En bas à droite du bouton (le clavier est à gauche)
			return Vector2.new(button.X1 + 150, button.Y1 + 100)
		end,
	}, animator)
	active[ctx] = piece

	local art: Frame? = nil
	local leftButton: Frame? = nil
	local leftBase: Color3 = Color3.new()
	local rgbParts: { Frame } = {} -- parties colorées (teinte qui avance)
	local rgbGradients: { UIGradient } = {}
	local signalBars: { Frame } = {}
	local hue = 0.55

	-- Ondes de clic (sur la toile), réutilisées
	local ripples = GearKit.Pool(3, function()
		local ring = Instance.new("Frame")
		ring.Name = "Ripple"
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 22
		ring.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Thickness = 2.5
		stroke.Color = Color3.fromRGB(120, 230, 255)
		stroke.Parent = ring
		ring.Parent = piece.FX
		return ring
	end)

	local function applyHue()
		local color = GearKit.Rainbow(hue, 0.7, 1)
		for _, part in ipairs(rgbParts) do
			part.BackgroundColor3 = color
		end
		for _, gradient in ipairs(rgbGradients) do
			gradient.Offset = Vector2.new((hue * 2) % 1 - 0.5, 0)
		end
	end

	local function build(level: number)
		animator:Stop("press", true)
		animator:Stop("breathe", true)
		if art then
			art:Destroy()
		end
		table.clear(rgbParts)
		table.clear(rgbGradients)
		table.clear(signalBars)
		local root = Instance.new("Frame")
		root.Name = "Art"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromOffset(W, H)
		root.ZIndex = 2

		local gold = level >= 10
		local wireless = level >= 9

		-- Tapis de souris (bord arc-en-ciel)
		if level >= 6 then
			local _, edge = GearKit.Outlined(root, 3, 12, W - 6, H - 15, Color3.fromRGB(34, 30, 52), {
				Name = "Pad",
				Radius = 12,
				Outline = 2.5,
				OutlineColor = Color3.new(1, 1, 1),
				Z = 2,
				LineZ = 1,
			})
			local gradient = Instance.new("UIGradient")
			gradient.Color = GearKit.RainbowSequence(0, 0.85)
			gradient.Rotation = 90
			gradient.Parent = edge
			table.insert(rgbGradients, gradient)
			GearKit.Box(root, 8, H - 12, 14, 4, Color3.fromRGB(80, 74, 110), { Name = "PadLogo", Radius = "round", Z = 3 })
		end

		-- Câble ou ondes radio
		if wireless then
			for index = 1, 3 do
				local bar = GearKit.Box(root, W / 2, 14 - index * 3.2, 6 + index * 7, 2.4, Color3.fromRGB(120, 230, 255), {
					Name = "Signal",
					Anchor = Vector2.new(0.5, 0.5),
					Radius = "round",
					Z = 4,
					Transparency = 0.15,
				})
				table.insert(signalBars, bar)
			end
		else
			GearKit.Outlined(root, W / 2 - 1.5, 0, 3, 26, level >= 5 and Color3.fromRGB(80, 80, 110) or Color3.fromRGB(60, 60, 72), {
				Name = "Cable",
				Radius = 1.5,
				Outline = 1.2,
				OutlineColor = INK,
				Z = 4,
				LineZ = 3,
			})
		end

		-- Corps (capsule + dos plus large = forme d'œuf)
		local bodyColor = gold and Color3.fromRGB(255, 200, 70) or Color3.fromRGB(46, 46, 58)
		local bodyGradient = gold and ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(225, 150, 40))
			or ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 190))
		GearKit.Outlined(root, 16, 22, 40, 70, bodyColor, { Name = "Body", Radius = 20, Outline = 2.4, OutlineColor = INK, Z = 6, LineZ = 5, Gradient = bodyGradient })
		GearKit.Outlined(root, 13, 50, 46, 46, bodyColor, { Name = "Palm", Radius = "round", Outline = 2.4, OutlineColor = INK, Z = 6, LineZ = 5, Gradient = bodyGradient })
		if level >= 3 then
			GearKit.Outlined(root, 9, 50, 6, 9, Color3.fromRGB(90, 90, 110), { Name = "Side1", Radius = 2, Outline = 1.6, OutlineColor = INK, Z = 6, LineZ = 5 })
			GearKit.Outlined(root, 9, 61, 6, 9, Color3.fromRGB(90, 90, 110), { Name = "Side2", Radius = 2, Outline = 1.6, OutlineColor = INK, Z = 6, LineZ = 5 })
		end

		-- Boutons gauche / droit + séparation
		local buttonColor = gold and Color3.fromRGB(255, 220, 110) or Color3.fromRGB(70, 70, 86)
		local left = GearKit.Box(root, 18.5, 24.5, 16, 26, buttonColor, { Name = "LeftButton", Radius = 8, Z = 7 })
		GearKit.Box(root, 37.5, 24.5, 16, 26, buttonColor, { Name = "RightButton", Radius = 8, Z = 7 })
		GearKit.Box(root, 35, 23, 2, 30, INK, { Name = "Split", Z = 8 })
		GearKit.Shine(left, 3, 3, 4, 10, 0.55, 8)
		leftButton = left
		leftBase = buttonColor

		-- Molette
		local wheelColor = level >= 2 and Color3.fromRGB(110, 235, 255) or Color3.fromRGB(150, 150, 165)
		if level >= 2 then
			GearKit.Box(root, 36, 36, 16, 22, wheelColor, { Name = "WheelGlow", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.6, Z = 8 })
		end
		local wheel = GearKit.Outlined(root, 32.5, 28, 7, 15, wheelColor, { Name = "Wheel", Radius = 3.5, Outline = 1.4, OutlineColor = INK, Z = 10, LineZ = 9 })
		for index = 0, 2 do
			GearKit.Box(wheel, 1, 3 + index * 4, 5, 1.3, INK, { Name = "Tread", Transparency = 0.4, Z = 11 })
		end
		if level >= 2 then
			table.insert(rgbParts, wheel)
		end

		-- Voyants DPI
		if level >= 8 then
			local dpi = { Color3.fromRGB(255, 80, 90), Color3.fromRGB(255, 210, 60), Color3.fromRGB(90, 240, 120) }
			for index, color in ipairs(dpi) do
				GearKit.Box(root, 30 + (index - 1) * 5, 55, 3, 3, color, { Name = "Dpi", Radius = "round", Z = 9 })
			end
		end

		-- Coque nid d'abeille
		if level >= 7 then
			local holes = { { 26, 64 }, { 36, 62 }, { 46, 64 }, { 21, 73 }, { 31, 72 }, { 41, 72 }, { 51, 73 }, { 26, 81 }, { 36, 81 }, { 46, 81 } }
			for _, hole in ipairs(holes) do
				GearKit.Box(root, hole[1], hole[2], 5, 5, gold and Color3.fromRGB(190, 120, 30) or Color3.fromRGB(24, 24, 32), {
					Name = "Hole",
					Anchor = Vector2.new(0.5, 0.5),
					Radius = "round",
					Z = 9,
				})
			end
		end

		-- Logo RGB
		if level >= 4 then
			local logoY = level >= 7 and 89 or 72
			local glow = GearKit.Box(root, 36, logoY, 18, 18, Color3.fromRGB(255, 120, 220), { Name = "LogoGlow", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.55, Z = 9 })
			local logo = GearKit.Box(root, 36, logoY, 9, 9, Color3.fromRGB(255, 120, 220), { Name = "Logo", Anchor = Vector2.new(0.5, 0.5), Rotation = 45, Radius = 2, Z = 10 })
			GearKit.Shine(logo, 1.5, 1.5, 3, 3, 0.2, 11)
			table.insert(rgbParts, glow)
			table.insert(rgbParts, logo)
		end

		-- Bande RGB (au dos)
		if level >= 5 then
			local strip = GearKit.Box(root, 20, 92, 32, 3.5, Color3.new(1, 1, 1), {
				Name = "Strip",
				Radius = "round",
				Z = 9,
				Gradient = GearKit.RainbowSequence(0, 0.8),
				GradientRotation = 0,
			})
			local gradient = strip:FindFirstChildOfClass("UIGradient")
			if gradient then
				table.insert(rgbGradients, gradient)
			end
		end

		-- Reflet du dos
		GearKit.Shine(root, 20, 56, 8, 18, gold and 0.35 or 0.7, 12, -12)

		root.Parent = piece.Content
		art = root
		applyHue()
	end
	build(math.max(1, piece.Level))

	piece.OnLevel = function(level, _previous)
		build(level)
	end

	local function click()
		if not piece:IsShown() then
			return
		end
		local level = math.max(1, piece.Level)
		if level >= 2 then
			hue = (hue + 0.08) % 1
			applyHue()
		end
		-- Bouton gauche enfoncé
		local button = leftButton
		if button then
			local pressed = leftBase:Lerp(Color3.fromRGB(20, 20, 30), 0.45)
			animator:Play("press", 0.14, function(t)
				local amount = t < 0.3 and t / 0.3 or 1 - (t - 0.3) / 0.7
				button.Position = UDim2.fromOffset(18.5, 24.5 + 1.2 * amount)
				button.BackgroundColor3 = leftBase:Lerp(pressed, amount)
			end)
		end
		-- Ondes radio (sans fil)
		if #signalBars > 0 then
			local bars = signalBars
			animator:Play("signal", 0.35, function(t)
				for index, bar in ipairs(bars) do
					local k = math.clamp(t * 3 - (index - 1) * 0.5, 0, 1)
					bar.BackgroundTransparency = 0.15 + 0.7 * GearKit.Bump(k)
				end
			end)
		end
		-- Ondes de clic
		if GearKit.EffectsOn(ctx) then
			local origin = piece:ToCanvas(Vector2.new(27, 36))
			if origin then
				local count = level >= 8 and 2 or 1
				local maxSize = (level >= 8 and 62 or 44) * math.max(0.6, piece.PlaceScale.Scale)
				local color = level >= 5 and GearKit.Rainbow(hue, 0.6, 1) or Color3.fromRGB(130, 225, 255)
				for index = 1, count do
					local ring = ripples:Next()
					local stroke = ring:FindFirstChild("Stroke") :: UIStroke
					local delay = (index - 1) * 0.08
					stroke.Color = color
					animator:Play(ring, 0.42 + delay, function(t)
						local k = math.clamp((t * (0.42 + delay) - delay) / 0.42, 0, 1)
						ring.Visible = k > 0 and k < 1
						local e = GearKit.Ease.OutCubic(k)
						local s = 10 + (maxSize - 10) * e
						ring.Position = UDim2.fromOffset(origin.X, origin.Y)
						ring.Size = UDim2.fromOffset(s, s)
						stroke.Transparency = 0.1 + 0.9 * k
						stroke.Thickness = 3 - 1.8 * k
					end, function()
						ring.Visible = false
					end)
				end
			end
		end
	end

	ctx.Connect(ctx.State.Clicked, function()
		if ctx.IsVisible() then
			click()
		end
	end)

	-- Au repos : les lumières respirent (un tour d'arc-en-ciel lent)
	GearKit.Every(ctx, 4, 7, function()
		if not piece:IsShown() or piece.Level < 2 then
			return
		end
		local start = hue
		local lastStep = -1
		animator:Play("breathe", 1.2, function(t)
			-- (≤ 30 mises à jour par seconde : animation d'ambiance)
			local step = math.floor(t * 36)
			if step == lastStep then
				return
			end
			lastStep = step
			hue = (start + 0.25 * GearKit.Ease.InOutSine(step / 36)) % 1
			applyHue()
		end)
	end)
end

function Mouse.Stop(ctx)
	local piece = active[ctx]
	active[ctx] = nil
	if piece then
		piece:Destroy()
	end
end

return Mouse
