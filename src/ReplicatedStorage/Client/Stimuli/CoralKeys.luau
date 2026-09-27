--[[
	CoralKeys (ModuleScript - stimulus) — amélioration "Clavier corail" (10 niveaux,
	après une visite à l'océan)
	Emplacement : ReplicatedStorage > Client > Stimuli > CoralKeys

	Un clavier venu de l'océan : boîtier turquoise, touches galets couleur
	corail / coquillage / sable / lagon, posé sur un tapis de sable avec une
	frange d'écume. À chaque clic, des touches s'enfoncent et des bulles
	montent (réutilisées : rien n'est créé pendant les clics).
	Chaque niveau ajoute quelque chose :
	  1 clavier corail + 1 bulle par clic   2 touches nacrées
	  3 algues                              4 étoile de mer + 2 bulles
	  5 coquillage                          6 poisson-clown qui nage
	  7 branches de corail + 3 bulles       8 touches bioluminescentes (lueur lagon)
	  9 palourde avec sa perle              10 touches sirène irisées + grosses bulles
	Au repos : une bulle monte de temps en temps (et le poisson fait un tour).
]]

local Gear = script.Parent:WaitForChild("Gear")
local GearKit = require(Gear:WaitForChild("GearKit"))
local GearPiece = require(Gear:WaitForChild("GearPiece"))
local KeyboardArt = require(Gear:WaitForChild("KeyboardArt"))

local CoralKeys = {}
CoralKeys.Slot = "Background" -- sous l'interface (effets de clic : calque Overlay)

local FULL = Vector2.new(184, 86)
local COMPACT = Vector2.new(80, 106) -- pavé "galets" (forme de rechange)
local INK = Color3.fromRGB(28, 70, 96)
local CORAL_PALETTE = {
	Color3.fromRGB(255, 138, 138),
	Color3.fromRGB(255, 204, 214),
	Color3.fromRGB(255, 236, 200),
	Color3.fromRGB(138, 232, 224),
}

local active: { [any]: any } = {}

local function bubblesPerClick(level: number): number
	if level >= 7 then
		return 3
	elseif level >= 4 then
		return 2
	end
	return 1
end

-- Étoile de mer : 5 branches autour d'un centre
local function starfish(parent: Instance, cx: number, cy: number, size: number, z: number)
	for index = 0, 4 do
		local angle = index * 72
		local r = math.rad(angle)
		local arm = GearKit.Box(parent, cx + math.sin(r) * size * 0.28, cy - math.cos(r) * size * 0.28, size * 0.3, size * 0.62, Color3.fromRGB(255, 150, 70), {
			Name = "Arm",
			Anchor = Vector2.new(0.5, 0.5),
			Radius = "round",
			Rotation = angle,
			Z = z,
		})
		GearKit.Box(arm, size * 0.1, size * 0.12, size * 0.1, size * 0.1, Color3.fromRGB(255, 230, 190), { Name = "Dot", Radius = "round", Z = z + 1 })
	end
	GearKit.Box(parent, cx, cy, size * 0.36, size * 0.36, Color3.fromRGB(255, 170, 90), { Name = "Center", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Z = z + 1 })
end

function CoralKeys.Start(ctx)
	local animator = GearKit.Animator(ctx)
	local piece = GearPiece.new(ctx, {
		Id = "CoralKeys",
		Size = FULL,
		Shapes = { COMPACT },
		Priority = 5,
		MinScale = 0.4,
		MaxScale = 1,
		GlowColor = Color3.fromRGB(170, 250, 240),
		ContainerZ = 1102,
		Anchor = function(button, _canvas)
			-- Sous le clavier mécanique, à gauche
			return Vector2.new(button.X0 - 160, button.Y1 + 205)
		end,
	}, animator)
	active[ctx] = piece
	local random = ctx.Random

	local art: Frame? = nil
	local keys: { KeyboardArt.Key } = {}
	local fish: Frame? = nil
	local fishHome = Vector2.new(150, 12)

	-- Bulles (sur la toile), réutilisées
	local bubbles = GearKit.Pool(9, function()
		local bubble = Instance.new("Frame")
		bubble.Name = "Bubble"
		bubble.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.BackgroundColor3 = Color3.fromRGB(190, 250, 255)
		bubble.BackgroundTransparency = 0.7
		bubble.BorderSizePixel = 0
		bubble.ZIndex = 22
		bubble.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = bubble
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 1.2
		stroke.Transparency = 0.15
		stroke.Parent = bubble
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BorderSizePixel = 0
		shine.Position = UDim2.fromScale(0.22, 0.18)
		shine.Size = UDim2.fromScale(0.28, 0.28)
		shine.ZIndex = 23
		local shineCorner = Instance.new("UICorner")
		shineCorner.CornerRadius = UDim.new(0.5, 0)
		shineCorner.Parent = shine
		shine.Parent = bubble
		bubble.Parent = piece.FX
		return bubble
	end)

	local function keyColor(level: number): (key: KeyboardArt.Key) -> Color3
		local count = 0
		return function(key: KeyboardArt.Key): Color3
			count += 1
			if level >= 10 then
				return GearKit.Rainbow(0.45 + key.Fx * 0.5 + key.Fy * 0.08, 0.32, 1) -- touches sirène
			end
			if level >= 2 and count % 5 == 0 then
				return Color3.fromRGB(252, 248, 255) -- nacre
			end
			return CORAL_PALETTE[(key.Row + key.Col) % #CORAL_PALETTE + 1]
		end
	end

	local function build(level: number)
		for _, key in ipairs(keys) do
			animator:Stop(key)
		end
		animator:Stop("fish", true)
		if art then
			art:Destroy()
		end
		table.clear(keys)
		fish = nil
		local compact = piece.Shape > 0
		local size = compact and COMPACT or FULL
		local W, H = size.X, size.Y
		local root = Instance.new("Frame")
		root.Name = "Art"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromOffset(W, H)
		root.ZIndex = 2

		-- Tapis de sable + frange d'écume
		GearKit.Outlined(root, 0, 6, W, H - 6, Color3.fromRGB(252, 228, 182), {
			Name = "Sand",
			Radius = 16,
			Outline = 2,
			OutlineColor = Color3.fromRGB(196, 150, 90),
			Z = 2,
			LineZ = 1,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(236, 214, 190)),
		})
		GearKit.Box(root, 0, 6, W, 9, Color3.fromRGB(120, 222, 230), { Name = "Foam", Radius = 12, Z = 3, Transparency = 0.15 })
		for index = 0, math.floor((W - 20) / 21) do
			GearKit.Box(root, 8 + index * 21, 11 + (index % 2) * 2, 12, 5, Color3.new(1, 1, 1), { Name = "FoamDot", Radius = "round", Z = 3, Transparency = 0.1 })
		end
		for index, ripple in ipairs({ { 0.1, 0.86 }, { 0.65, 0.9 }, { 0.38, 0.93 }, { 0.87, 0.82 } }) do
			GearKit.Box(root, W * ripple[1], H * ripple[2], math.min(18 + index * 3, W * 0.25), 1.8, Color3.fromRGB(214, 176, 120), {
				Name = "Ripple",
				Radius = "round",
				Z = 3,
				Transparency = 0.35,
			})
		end

		-- Boîtier : plein clavier ou pavé
		local caseX, caseY, caseW, caseH
		if compact then
			caseX, caseY, caseW, caseH = 10, 17, W - 20, H - 36
		else
			caseX, caseY, caseW, caseH = 13, 17, W - 26, 50
		end

		-- Lueur lagon (bioluminescence)
		if level >= 8 then
			GearKit.Box(root, caseX - 5, caseY - 5, caseW + 10, caseH + 10, Color3.fromRGB(90, 255, 230), { Name = "Glow", Radius = 18, Z = 4, Transparency = 0.45 })
		end

		-- Algues (à gauche)
		if level >= 3 then
			local strands = compact and 1 or 2
			for strand = 0, strands - 1 do
				for leaf = 0, 3 do
					GearKit.Outlined(root, 2 + strand * 5 + (leaf % 2) * 3, caseY + caseH - 9 - leaf * 12 - strand * 5, 6, 13, Color3.fromRGB(96, 206, 120), {
						Name = "Leaf",
						Radius = "round",
						Rotation = (leaf % 2 == 0) and -18 or 18,
						Outline = 1.2,
						OutlineColor = Color3.fromRGB(40, 120, 70),
						Z = 12,
						LineZ = 11,
					})
				end
			end
		end

		-- Boîtier + plaque + touches galets
		GearKit.Outlined(root, caseX, caseY, caseW, caseH, Color3.fromRGB(84, 206, 206), {
			Name = "Case",
			Radius = 13,
			Outline = 2.2,
			OutlineColor = INK,
			Z = 6,
			LineZ = 5,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 225, 235)),
		})
		GearKit.Box(root, caseX + 5, caseY + 2, caseW - 10, 3, Color3.new(1, 1, 1), { Name = "CaseShine", Radius = "round", Transparency = 0.4, Z = 7 })
		GearKit.Box(root, caseX + 4, caseY + 5, caseW - 8, caseH - 9, Color3.fromRGB(30, 112, 142), { Name = "Plate", Radius = 8, Z = 7 })
		local keyOptions = {
			Color = keyColor(level),
			Radius = 4,
			Gap = 1.8,
			Shine = true,
			Z = 8,
		}
		if compact then
			keys = KeyboardArt.Numpad(root, caseX + 6, caseY + 7, caseW - 12, caseH - 13, keyOptions)
		else
			keys = KeyboardArt.Keys(root, caseX + 6, caseY + 7, caseW - 12, caseH - 13, keyOptions)
		end

		-- Branches de corail (coin haut gauche du boîtier)
		if level >= 7 then
			local coral = Color3.fromRGB(255, 110, 150)
			local bx = caseX + 9
			GearKit.Outlined(root, bx, 2, 5, 18, coral, { Name = "Coral", Radius = "round", Outline = 1.2, OutlineColor = Color3.fromRGB(170, 40, 80), Z = 14, LineZ = 13 })
			GearKit.Outlined(root, bx - 6, 6, 5, 12, coral, { Name = "Coral", Radius = "round", Rotation = -35, Outline = 1.2, OutlineColor = Color3.fromRGB(170, 40, 80), Z = 14, LineZ = 13 })
			GearKit.Outlined(root, bx + 6, 5, 5, 12, coral, { Name = "Coral", Radius = "round", Rotation = 35, Outline = 1.2, OutlineColor = Color3.fromRGB(170, 40, 80), Z = 14, LineZ = 13 })
			for _, dot in ipairs({ { bx + 2.5, 1 }, { bx - 7, 5 }, { bx + 11, 4 } }) do
				GearKit.Box(root, dot[1], dot[2], 4, 4, Color3.fromRGB(255, 200, 220), { Name = "Polyp", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Z = 15 })
			end
		end

		-- Étoile de mer, coquillage, palourde (sur le sable)
		if level >= 4 then
			starfish(root, W - 13, H - 11, compact and 15 or 18, 14)
		end
		if level >= 5 then
			local shell = GearKit.Outlined(root, 5, H - 15, 15, 10, Color3.fromRGB(255, 190, 200), {
				Name = "Shell",
				Radius = 6,
				Outline = 1.2,
				OutlineColor = Color3.fromRGB(190, 90, 120),
				Z = 14,
				LineZ = 13,
			})
			for index = 1, 3 do
				GearKit.Box(shell, index * 3.8, 2, 1.2, 7, Color3.fromRGB(210, 120, 150), { Name = "Ridge", Z = 15 })
			end
		end
		if level >= 9 then
			GearKit.Outlined(root, W / 2 - 10, H - 13, 20, 9, Color3.fromRGB(170, 150, 230), {
				Name = "Clam",
				Radius = 5,
				Outline = 1.2,
				OutlineColor = Color3.fromRGB(90, 70, 160),
				Z = 14,
				LineZ = 13,
			})
			local pearl = GearKit.Box(root, W / 2, H - 13, 8, 8, Color3.fromRGB(255, 252, 255), { Name = "Pearl", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Z = 15 })
			GearKit.Shine(pearl, 1.5, 1.5, 3, 3, 0, 16)
		end

		-- Poisson-clown
		fishHome = compact and Vector2.new(W - 18, 11) or Vector2.new(150, 12)
		if level >= 6 then
			local holder = Instance.new("Frame")
			holder.Name = "Fish"
			holder.BackgroundTransparency = 1
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Size = UDim2.fromOffset(24, 14)
			holder.Position = UDim2.fromOffset(fishHome.X, fishHome.Y)
			holder.ZIndex = 16
			GearKit.Outlined(holder, 17, 2, 8, 10, Color3.fromRGB(255, 140, 40), { Name = "Tail", Rotation = 45, Radius = 2, Outline = 1.2, OutlineColor = INK, Z = 2, LineZ = 1 })
			local body = GearKit.Outlined(holder, 1, 1, 19, 12, Color3.fromRGB(255, 140, 40), { Name = "Body", Radius = "round", Outline = 1.2, OutlineColor = INK, Z = 3, LineZ = 1 })
			GearKit.Box(body, 7, 0, 3, 12, Color3.new(1, 1, 1), { Name = "Stripe", Z = 4 })
			GearKit.Box(body, 3, 3.5, 2.5, 2.5, Color3.fromRGB(30, 30, 40), { Name = "Eye", Radius = "round", Z = 5 })
			holder.Parent = root
			fish = holder
		end

		root.Parent = piece.Content
		art = root
	end
	build(math.max(1, piece.Level))

	piece.OnLevel = function(level, _previous)
		build(level)
	end
	piece.OnShape = function(_shape, _size)
		build(math.max(1, piece.Level))
	end

	local function releaseBubble(fromLocal: Vector2, big: boolean)
		if not GearKit.EffectsOn(ctx) then
			return
		end
		local origin = piece:ToCanvas(fromLocal)
		if not origin then
			return
		end
		local bubble = bubbles:Next()
		local size = (big and random:NextNumber(10, 16) or random:NextNumber(6, 11)) * math.max(0.7, piece.PlaceScale.Scale)
		local rise = random:NextNumber(46, 78) * math.max(0.7, piece.PlaceScale.Scale)
		local wobble = random:NextNumber(3, 7)
		local phase = random:NextNumber(0, math.pi * 2)
		local duration = random:NextNumber(0.8, 1.1)
		animator:Play(bubble, duration, function(t)
			bubble.Visible = t < 1
			local popping = t > 0.86
			local s = size * (0.6 + 0.4 * math.min(1, t * 3)) * (popping and (1 + (t - 0.86) * 4) or 1)
			bubble.Size = UDim2.fromOffset(s, s)
			bubble.Position = UDim2.fromOffset(origin.X + math.sin(phase + t * 7) * wobble, origin.Y - rise * GearKit.Ease.OutQuad(t))
			local fade = popping and (t - 0.86) / 0.14 or 0
			bubble.BackgroundTransparency = 0.7 + 0.3 * fade
			local stroke = bubble:FindFirstChild("Stroke") :: UIStroke?
			if stroke then
				stroke.Transparency = 0.15 + 0.85 * fade
			end
		end, function()
			bubble.Visible = false
		end)
	end

	local function click()
		if not piece:IsShown() or #keys == 0 then
			return
		end
		local level = math.max(1, piece.Level)
		local lit = level >= 8 and Color3.fromRGB(120, 255, 235) or nil
		local pressed = KeyboardArt.Pick(keys, 2, random)
		for index, key in ipairs(pressed) do
			local delay = (index - 1) * 0.04
			animator:Play(key, 0.18 + delay, function(t)
				local k = math.clamp((t * (0.18 + delay) - delay) / 0.18, 0, 1)
				local amount = k < 0.35 and k / 0.35 or 1 - (k - 0.35) / 0.65
				KeyboardArt.Press(key, amount, lit)
			end, function()
				KeyboardArt.Press(key, 0)
			end)
		end
		for index = 1, bubblesPerClick(level) do
			local key = pressed[(index - 1) % math.max(1, #pressed) + 1]
			if key then
				releaseBubble(Vector2.new(key.X + key.W / 2 + random:NextNumber(-6, 6), key.Y), level >= 10)
			end
		end
		-- Le poisson sursaute
		local swimmer = fish
		if swimmer then
			animator:Play("fishJump", 0.3, function(t)
				swimmer.Rotation = math.sin(t * math.pi * 4) * 14 * (1 - t)
			end)
		end
	end

	ctx.Connect(ctx.State.Clicked, function()
		if ctx.IsVisible() then
			click()
		end
	end)

	-- Au repos : une bulle, et le poisson fait un petit tour
	GearKit.Every(ctx, 3, 5.5, function()
		if not piece:IsShown() then
			return
		end
		local width = piece.Size.X
		releaseBubble(Vector2.new(random:NextNumber(width * 0.2, width * 0.8), 20), false)
		local swimmer = fish
		if swimmer and random:NextNumber() < 0.5 then
			local lastStep = -1
			animator:Play("fish", 2.4, function(t)
				local step = math.floor(t * 72) -- (≤ 30 images/s)
				if step == lastStep then
					return
				end
				lastStep = step
				local k = step / 72
				local angle = k * math.pi * 2
				local x = fishHome.X - math.min(60, piece.Size.X * 0.55) * math.sin(angle * 0.5)
				local y = fishHome.Y + math.sin(angle) * 3
				swimmer.Position = UDim2.fromOffset(x, y)
				swimmer.Rotation = math.cos(angle * 3) * 6
			end, function()
				swimmer.Position = UDim2.fromOffset(fishHome.X, fishHome.Y)
				swimmer.Rotation = 0
			end)
		end
	end)
end

function CoralKeys.Stop(ctx)
	local piece = active[ctx]
	active[ctx] = nil
	if piece then
		piece:Destroy()
	end
end

return CoralKeys
