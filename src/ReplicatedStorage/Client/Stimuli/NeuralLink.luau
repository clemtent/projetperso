--[[
	NeuralLink (ModuleScript - stimulus) — amélioration "Neural Link" (1 niveau,
	après 3 visites à l'océan)
	Emplacement : ReplicatedStorage > Client > Stimuli > NeuralLink

	Un petit cerveau kawaii qui brille (casque à électrodes), posé dans
	l'espace libre (Gear/GearLayout), relié au gros bouton par un câble
	neuronal. À chaque clic, une impulsion lumineuse part du cerveau, suit le
	câble et fait une étincelle au bouton ; le cerveau "pulse" et ses
	électrodes s'allument.
	Tout le dessin (cerveau + câble "Gear_NeuralCable") est SOUS l'interface
	(Slot "Background") : le câble ne recouvre jamais une carte, le compteur ou
	un bouton, il se glisse dessous quand il doit les traverser. Seule
	l'étincelle d'arrivée (passagère) est dans le calque Overlay.
	Au repos : de temps en temps une "pensée" (impulsion douce) et un clin d'œil.
]]

local Gear = script.Parent:WaitForChild("Gear")
local GearKit = require(Gear:WaitForChild("GearKit"))
local GearPiece = require(Gear:WaitForChild("GearPiece"))

local NeuralLink = {}
NeuralLink.Slot = "Background" -- sous l'interface (étincelles : calque Overlay)

local W, H = 104, 90
local INK = Color3.fromRGB(128, 48, 104)
local PINK = Color3.fromRGB(255, 176, 208)
local FOLD = Color3.fromRGB(226, 112, 166)
local SEGMENTS = 18

local active: { [any]: () -> () } = {}

-- Point d'une courbe de Bézier cubique
local function bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: number): Vector2
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

function NeuralLink.Start(ctx)
	local animator = GearKit.Animator(ctx)
	local random = ctx.Random
	local piece = GearPiece.new(ctx, {
		Id = "NeuralLink",
		Size = Vector2.new(W, H),
		Priority = 6,
		MinScale = 0.42,
		MaxScale = 1,
		GlowColor = Color3.fromRGB(255, 200, 240),
		ContainerZ = 91,
		Anchor = function(button, _canvas)
			-- En haut à droite du bouton (au-dessus de la souris)
			return Vector2.new(button.X1 + 200, button.Y0 + 30)
		end,
	}, animator)

	------------------------------------------------------------------
	-- Le cerveau
	------------------------------------------------------------------

	local root = Instance.new("Frame")
	root.Name = "Art"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromOffset(W / 2, H / 2)
	root.Size = UDim2.fromOffset(W, H)
	root.ZIndex = 2
	local pulseScale = Instance.new("UIScale")
	pulseScale.Parent = root

	-- Halo
	local halo = GearKit.Box(root, W / 2, 44, 116, 100, Color3.fromRGB(255, 140, 220), { Name = "Halo", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.86, Z = 1 })
	local haloCore = GearKit.Box(root, W / 2, 44, 88, 74, Color3.fromRGB(255, 170, 230), { Name = "HaloCore", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.8, Z = 1 })

	-- Tronc cérébral (le câble en sort)
	GearKit.Outlined(root, 46, 60, 12, 22, Color3.fromRGB(240, 146, 186), { Name = "Stem", Radius = 5, Outline = 2.2, OutlineColor = INK, Z = 3, LineZ = 2 })
	GearKit.Outlined(root, 44, 78, 16, 8, Color3.fromRGB(90, 90, 120), { Name = "Port", Radius = 3, Outline = 2, OutlineColor = INK, Z = 4, LineZ = 2 })

	-- Lobes
	local lobeGradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(240, 210, 225))
	for _, lobe in ipairs({
		{ 10, 26, 40, 34 },
		{ 25, 11, 34, 30 },
		{ 46, 11, 34, 30 },
		{ 56, 25, 38, 35 },
		{ 20, 36, 64, 30 },
	}) do
		GearKit.Outlined(root, lobe[1], lobe[2], lobe[3], lobe[4], PINK, {
			Name = "Lobe",
			Radius = "round",
			Outline = 2.6,
			OutlineColor = INK,
			Z = 5,
			LineZ = 2,
			Gradient = lobeGradient,
		})
	end
	-- Sillon central + circonvolutions
	GearKit.Box(root, 51, 13, 2.2, 24, FOLD, { Name = "Fissure", Radius = "round", Z = 6 })
	for _, fold in ipairs({
		{ 16, 32, 12, 30 },
		{ 30, 20, 11, -40 },
		{ 36, 30, 9, 20 },
		{ 60, 20, 11, 40 },
		{ 64, 30, 9, -20 },
		{ 76, 34, 12, -30 },
		{ 18, 48, 10, -15 },
		{ 76, 50, 10, 15 },
	}) do
		GearKit.Box(root, fold[1], fold[2], fold[3], 2.4, FOLD, { Name = "Fold", Radius = "round", Rotation = fold[4], Z = 6 })
	end
	GearKit.Shine(root, 28, 16, 12, 6, 0.45, 7, -20)

	-- Visage
	local eyes = {}
	for side = 0, 1 do
		local ex = side == 0 and 40 or 59
		local eye = GearKit.Box(root, ex, 42, 5.5, 7, Color3.fromRGB(70, 30, 60), { Name = "Eye", Radius = "round", Z = 8 })
		GearKit.Box(eye, 1, 1, 2.2, 2.2, Color3.new(1, 1, 1), { Name = "Glint", Radius = "round", Z = 9 })
		table.insert(eyes, eye)
		GearKit.Box(root, side == 0 and 32 or 64, 50, 8, 4, Color3.fromRGB(255, 110, 150), { Name = "Blush", Radius = "round", Transparency = 0.35, Z = 7 })
	end
	GearKit.Box(root, 49, 51, 6, 3.5, Color3.fromRGB(170, 50, 90), { Name = "Mouth", Radius = "round", Z = 8 })

	-- Casque à électrodes
	GearKit.Outlined(root, 16, 6, 72, 6, Color3.fromRGB(232, 234, 246), { Name = "Band", Radius = "round", Outline = 2, OutlineColor = INK, Z = 10, LineZ = 9 })
	local electrodes = {}
	for index, ex in ipairs({ 20, 52, 84 }) do
		local glow = GearKit.Box(root, ex, 8, 18, 18, Color3.fromRGB(120, 240, 255), { Name = "NodeGlow", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.6, Z = 10 })
		local node = GearKit.Outlined(root, ex - 5, 3, 10, 10, Color3.fromRGB(120, 240, 255), { Name = "Node", Radius = "round", Outline = 1.8, OutlineColor = INK, Z = 12, LineZ = 11 })
		GearKit.Box(node, 2, 2, 3, 3, Color3.new(1, 1, 1), { Name = "Core", Radius = "round", Z = 13 })
		electrodes[index] = { Glow = glow, Node = node }
	end
	root.Parent = piece.Content

	------------------------------------------------------------------
	-- Le câble (calque Background) + impulsions
	------------------------------------------------------------------

	local cable = Instance.new("Frame")
	cable.Name = "Gear_NeuralCable"
	cable.BackgroundTransparency = 1
	cable.Size = UDim2.fromScale(1, 1)
	cable.ZIndex = 1 -- sous le cerveau (le conteneur est déjà sous l'interface)
	cable.Visible = false
	cable.Active = false
	cable.Parent = ctx.Container

	local segments = {}
	for index = 1, SEGMENTS do
		local outer = GearKit.Box(cable, 0, 0, 10, 7, Color3.fromRGB(70, 56, 100), { Name = "Segment", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Z = 1 })
		local core = GearKit.Box(cable, 0, 0, 10, 2.6, Color3.fromRGB(255, 150, 225), { Name = "Core", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.25, Z = 2 })
		segments[index] = { Outer = outer, Core = core }
	end

	local pulses = GearKit.Pool(3, function()
		local dot = GearKit.Box(cable, 0, 0, 14, 14, Color3.fromRGB(255, 140, 230), { Name = "Pulse", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Transparency = 0.2, Z = 4, Visible = false })
		GearKit.Box(dot, 4, 4, 6, 6, Color3.new(1, 1, 1), { Name = "Core", Radius = "round", Z = 5 })
		return dot
	end)

	-- Étincelle au bouton (au-dessus : calque Overlay)
	local sparks = GearKit.Pool(2, function()
		local ring = Instance.new("Frame")
		ring.Name = "Spark"
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.BackgroundColor3 = Color3.fromRGB(255, 200, 250)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 24
		ring.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Color = Color3.fromRGB(255, 130, 230)
		stroke.Thickness = 2.5
		stroke.Parent = ring
		GearKit.Star(ring, 0, 0, 12, Color3.new(1, 1, 1), 25).Position = UDim2.fromScale(0.5, 0.5)
		ring.Parent = piece.FX
		return ring
	end)

	local path = { Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero }
	local attach = Vector2.zero

	local function layCable(placement: any)
		if not placement then
			cable.Visible = false
			return
		end
		local button = placement.Button
		local center = Vector2.new(placement.CX, placement.CY)
		-- Le câble sort du casque si le bouton est au-dessus, sinon du tronc cérébral
		local up = (button.Y0 + button.Y1) / 2 < center.Y - 10
		local port = piece:ToCanvas(up and Vector2.new(52, 3) or Vector2.new(52, 84))
		if not port then
			return
		end
		local portDir = up and Vector2.new(0, -1) or Vector2.new(0, 1)
		-- Point d'arrivée : bord du bouton le plus proche, un peu à l'intérieur (le câble passe dessous)
		local edge = GearKit.ClosestOnRect(button, center)
		local normal = Vector2.zero
		if edge.X <= button.X0 + 0.5 then
			normal = Vector2.new(-1, 0)
		elseif edge.X >= button.X1 - 0.5 then
			normal = Vector2.new(1, 0)
		elseif edge.Y <= button.Y0 + 0.5 then
			normal = Vector2.new(0, -1)
		else
			normal = Vector2.new(0, 1)
		end
		attach = edge
		local finish = edge - normal * 10
		local distance = (finish - port).Magnitude
		path[1] = port
		path[2] = port + portDir * math.clamp(distance * 0.35, 24, 90)
		path[3] = edge + normal * math.clamp(distance * 0.35, 20, 80)
		path[4] = finish
		local previous = path[1]
		for index = 1, SEGMENTS do
			local point = bezier(path[1], path[2], path[3], path[4], index / SEGMENTS)
			local delta = point - previous
			local length = delta.Magnitude
			local mid = (point + previous) / 2
			local angle = math.deg(math.atan2(delta.Y, delta.X))
			local segment = segments[index]
			for _, frame in ipairs({ segment.Outer, segment.Core }) do
				frame.Position = UDim2.fromOffset(mid.X, mid.Y)
				frame.Rotation = angle
			end
			local thickness = 7 * math.max(0.6, placement.Scale)
			segment.Outer.Size = UDim2.fromOffset(length + thickness, thickness)
			segment.Core.Size = UDim2.fromOffset(length + 2, thickness * 0.38)
			previous = point
		end
		cable.Visible = true
	end

	piece.OnPlaced = function(placement, _first)
		layCable(placement)
	end
	piece.OnHidden = function()
		cable.Visible = false
	end

	-- Impulsion le long du câble (dim = pensée au repos)
	local function firePulse(dim: boolean)
		if not piece:IsShown() or not cable.Visible then
			return
		end
		local dot = pulses:Next()
		local size = dim and 9 or 14
		animator:Play(dot, dim and 0.8 or 0.38, function(t)
			dot.Visible = t < 1
			local e = GearKit.Ease.InOutSine(t)
			local point = bezier(path[1], path[2], path[3], path[4], e)
			dot.Position = UDim2.fromOffset(point.X, point.Y)
			local s = size * (0.8 + 0.3 * GearKit.Bump(t))
			dot.Size = UDim2.fromOffset(s, s)
			dot.BackgroundTransparency = dim and 0.45 or 0.15
		end, function()
			dot.Visible = false
			if not dim and GearKit.EffectsOn(ctx) then
				local ring = sparks:Next()
				local stroke = ring:FindFirstChild("Stroke") :: UIStroke
				local at = attach
				animator:Play(ring, 0.3, function(t)
					ring.Visible = t < 1
					local s = 10 + 26 * GearKit.Ease.OutCubic(t)
					ring.Position = UDim2.fromOffset(at.X, at.Y)
					ring.Size = UDim2.fromOffset(s, s)
					stroke.Transparency = t
					ring.Rotation = 90 * t
				end, function()
					ring.Visible = false
				end)
			end
		end)
	end

	local function brainPulse()
		animator:Play("brain", 0.26, function(t)
			local b = GearKit.Bump(t)
			pulseScale.Scale = 1 + 0.07 * b
			halo.BackgroundTransparency = 0.86 - 0.3 * b
			haloCore.BackgroundTransparency = 0.8 - 0.3 * b
			for _, electrode in ipairs(electrodes) do
				electrode.Glow.BackgroundTransparency = 0.6 - 0.45 * b
			end
		end)
	end

	ctx.Connect(ctx.State.Clicked, function()
		if not ctx.IsVisible() or not piece:IsShown() then
			return
		end
		brainPulse()
		firePulse(false)
	end)

	-- Au repos : une pensée + un clin d'œil
	GearKit.Every(ctx, 3.5, 6, function()
		if not piece:IsShown() then
			return
		end
		firePulse(true)
		if random:NextNumber() < 0.6 then
			animator:Play("blink", 0.18, function(t)
				local closed = t < 0.6
				for _, eye in ipairs(eyes) do
					eye.Size = UDim2.fromOffset(5.5, closed and 1.6 or 7)
					eye.Position = UDim2.fromOffset(eye.Position.X.Offset, closed and 45 or 42)
				end
			end)
		end
	end)

	active[ctx] = function()
		piece:Destroy()
		if cable.Parent then
			cable:Destroy()
		end
	end
end

function NeuralLink.Stop(ctx)
	local cleanup = active[ctx]
	active[ctx] = nil
	if cleanup then
		cleanup()
	end
end

return NeuralLink
