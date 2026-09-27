--[[
	CoralKeys (ModuleScript - stimulus) — amélioration "Clavier corail" (10 niveaux,
	après une visite à l'océan)
	Emplacement : ReplicatedStorage > Client > Stimuli > CoralKeys

	Un clavier venu de l'océan : boîtier turquoise, touches galets couleur
	corail / coquillage / sable / lagon, posé sur un tapis de sable avec une
	frange d'écume.
	v9.1 : un VRAI clavier QWERTY cliquable (Gear/ClickableKeys, comme le
	clavier mécanique) : chaque touche frappée s'enfonce, joue un son de
	touche plus doux (Config.ClickSounds Keyboard1..5 selon le niveau, plus
	grave), fait monter une bulle et compte comme un vrai clic. Trop petit
	pour viser ? badge 🔍 -> grand clavier corail flottant. Le vrai clavier
	du joueur l'anime aussi (le clavier mécanique, s'il est là, compte le clic).
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
local GearClick = require(Gear:WaitForChild("GearClick"))
local ClickableKeys = require(Gear:WaitForChild("ClickableKeys"))

local CoralKeys = {}
CoralKeys.Slot = "Background" -- sous l'interface (effets de clic : calque Overlay)

local STEP_FULL = 24 -- pas d'une touche (touche + écart) du clavier posé, échelle 1
local STEP_MINI = 21

-- Place en plus autour du boîtier : écume (haut), coquillages (bas), algues (côtés)
local function coralGeometry(layout: string, step: number): KeyboardArt.Geometry
	return KeyboardArt.Geometry(layout, step, step * 0.45, step * 0.5, step * 0.22)
end

local GEO_FULL = coralGeometry("Full", STEP_FULL)
local GEO_MINI = coralGeometry("Mini", STEP_MINI)
local FULL = Vector2.new(GEO_FULL.W, GEO_FULL.H)
local MINI = Vector2.new(GEO_MINI.W, GEO_MINI.H)
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


local function keyColorFn(level: number): (key: KeyboardArt.Key) -> Color3
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

-- Dessine le clavier corail pour un pas de touche `step`.
-- Renvoie (touches, largeur, hauteur, poisson-clown ou nil).
local function drawCoral(root: Instance, layout: string, step: number, level: number): ({ KeyboardArt.Key }, number, number, Frame?)
	local geo = coralGeometry(layout, step)
	local W, H = geo.W, geo.H
	local s = step / STEP_FULL

	-- Tapis de sable + frange d'écume
	local top = 6 * s
	GearKit.Outlined(root, 0, top, W, H - top, Color3.fromRGB(252, 228, 182), {
		Name = "Sand",
		Radius = 16 * s,
		Outline = 2 * s,
		OutlineColor = Color3.fromRGB(196, 150, 90),
		Z = 2,
		LineZ = 1,
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(236, 214, 190)),
	})
	GearKit.Box(root, 0, top, W, 11 * s, Color3.fromRGB(120, 222, 230), { Name = "Foam", Radius = 12 * s, Z = 3, Transparency = 0.15 })
	local dots = math.floor((W - 20 * s) / (22 * s))
	for index = 0, dots do
		GearKit.Box(root, 8 * s + index * 22 * s, top + 5 * s + (index % 2) * 2 * s, 12 * s, 5 * s, Color3.new(1, 1, 1), { Name = "FoamDot", Radius = "round", Z = 3, Transparency = 0.1 })
	end
	for index, ripple in ipairs({ { 0.14, 0.955 }, { 0.62, 0.96 }, { 0.38, 0.975 }, { 0.84, 0.95 } }) do
		GearKit.Box(root, W * ripple[1], H * ripple[2] - 4 * s, (18 + index * 4) * s, 1.8 * s, Color3.fromRGB(214, 176, 120), {
			Name = "Ripple",
			Radius = "round",
			Z = 3,
			Transparency = 0.35,
		})
	end

	-- Lueur lagon (bioluminescence)
	if level >= 8 then
		GearKit.Box(root, geo.CaseX - 6 * s, geo.CaseY - 6 * s, geo.CaseW + 12 * s, geo.CaseH + 12 * s, Color3.fromRGB(90, 255, 230), { Name = "Glow", Radius = 18 * s, Z = 4, Transparency = 0.45 })
	end

	-- Algues (à gauche, le long du boîtier)
	if level >= 3 then
		for strand = 0, 1 do
			for leaf = 0, 3 do
				GearKit.Outlined(root, 1 * s + strand * 5 * s + (leaf % 2) * 3 * s, geo.CaseY + geo.CaseH - 12 * s - leaf * 14 * s - strand * 6 * s, 7 * s, 15 * s, Color3.fromRGB(96, 206, 120), {
					Name = "Leaf",
					Radius = "round",
					Rotation = (leaf % 2 == 0) and -18 or 18,
					Outline = 1.2 * s,
					OutlineColor = Color3.fromRGB(40, 120, 70),
					Z = 12,
					LineZ = 11,
				})
			end
		end
	end

	-- Boîtier + plaque + touches galets
	GearKit.Outlined(root, geo.CaseX, geo.CaseY, geo.CaseW, geo.CaseH, Color3.fromRGB(84, 206, 206), {
		Name = "Case",
		Radius = 13 * s,
		Outline = 2.2 * s,
		OutlineColor = INK,
		Z = 6,
		LineZ = 5,
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 225, 235)),
	})
	GearKit.Box(root, geo.CaseX + 6 * s, geo.CaseY + 2 * s, geo.CaseW - 12 * s, 2.5 * s, Color3.new(1, 1, 1), { Name = "CaseShine", Radius = "round", Transparency = 0.4, Z = 7 })
	GearKit.Box(root, geo.KeysX - 3 * s, geo.KeysY - 3 * s, geo.KeysW + 6 * s, geo.KeysH + 6 * s, Color3.fromRGB(30, 112, 142), { Name = "Plate", Radius = 8 * s, Z = 7 })
	local keys = KeyboardArt.Build(root, layout, geo.KeysX, geo.KeysY, geo.KeysW, geo.KeysH, {
		Color = keyColorFn(level),
		LegendColor = function(_key: KeyboardArt.Key): Color3
			return INK
		end,
		Radius = 0.32, -- touches "galets"
		Z = 8,
	})

	-- Branches de corail (coin haut gauche du boîtier)
	if level >= 7 then
		local coral = Color3.fromRGB(255, 110, 150)
		local line = Color3.fromRGB(170, 40, 80)
		local bx, by = geo.CaseX + 12 * s, geo.CaseY - 16 * s
		GearKit.Outlined(root, bx, by, 5 * s, 20 * s, coral, { Name = "Coral", Radius = "round", Outline = 1.2 * s, OutlineColor = line, Z = 14, LineZ = 13 })
		GearKit.Outlined(root, bx - 6 * s, by + 5 * s, 5 * s, 13 * s, coral, { Name = "Coral", Radius = "round", Rotation = -35, Outline = 1.2 * s, OutlineColor = line, Z = 14, LineZ = 13 })
		GearKit.Outlined(root, bx + 6 * s, by + 4 * s, 5 * s, 13 * s, coral, { Name = "Coral", Radius = "round", Rotation = 35, Outline = 1.2 * s, OutlineColor = line, Z = 14, LineZ = 13 })
		for _, dot in ipairs({ { bx + 2.5 * s, by - 1 * s }, { bx - 7 * s, by + 4 * s }, { bx + 11 * s, by + 3 * s } }) do
			GearKit.Box(root, dot[1], dot[2], 4.5 * s, 4.5 * s, Color3.fromRGB(255, 200, 220), { Name = "Polyp", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Z = 15 })
		end
	end

	-- Étoile de mer, coquillage, palourde (sur le sable, sous le boîtier)
	local sandY = geo.CaseY + geo.CaseH
	local sandH = H - sandY
	if level >= 4 then
		starfish(root, W - 16 * s, sandY + sandH * 0.52, 20 * s, 14)
	end
	if level >= 5 then
		local shell = GearKit.Outlined(root, 8 * s, sandY + sandH * 0.3, 17 * s, 11 * s, Color3.fromRGB(255, 190, 200), {
			Name = "Shell",
			Radius = 6 * s,
			Outline = 1.2 * s,
			OutlineColor = Color3.fromRGB(190, 90, 120),
			Z = 14,
			LineZ = 13,
		})
		for index = 1, 3 do
			GearKit.Box(shell, index * 4.2 * s, 2 * s, 1.3 * s, 8 * s, Color3.fromRGB(210, 120, 150), { Name = "Ridge", Z = 15 })
		end
	end
	if level >= 9 then
		GearKit.Outlined(root, W / 2 - 12 * s, sandY + sandH * 0.3, 24 * s, 10 * s, Color3.fromRGB(170, 150, 230), {
			Name = "Clam",
			Radius = 5 * s,
			Outline = 1.2 * s,
			OutlineColor = Color3.fromRGB(90, 70, 160),
			Z = 14,
			LineZ = 13,
		})
		local pearl = GearKit.Box(root, W / 2, sandY + sandH * 0.3 + 1 * s, 9 * s, 9 * s, Color3.fromRGB(255, 252, 255), { Name = "Pearl", Anchor = Vector2.new(0.5, 0.5), Radius = "round", Z = 15 })
		GearKit.Shine(pearl, 1.5 * s, 1.5 * s, 3 * s, 3 * s, 0, 16)
	end

	-- Poisson-clown (dans l'écume, en haut à droite)
	local fish: Frame? = nil
	if level >= 6 then
		local holder = Instance.new("Frame")
		holder.Name = "Fish"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Size = UDim2.fromOffset(26 * s, 15 * s)
		holder.Position = UDim2.fromOffset(W - 34 * s, top + 6 * s)
		holder.ZIndex = 16
		GearKit.Outlined(holder, 18 * s, 2.5 * s, 8 * s, 10 * s, Color3.fromRGB(255, 140, 40), { Name = "Tail", Rotation = 45, Radius = 2 * s, Outline = 1.2 * s, OutlineColor = INK, Z = 2, LineZ = 1 })
		local body = GearKit.Outlined(holder, 1 * s, 1 * s, 20 * s, 13 * s, Color3.fromRGB(255, 140, 40), { Name = "Body", Radius = "round", Outline = 1.2 * s, OutlineColor = INK, Z = 3, LineZ = 1 })
		GearKit.Box(body, 7.5 * s, 0, 3 * s, 13 * s, Color3.new(1, 1, 1), { Name = "Stripe", Z = 4 })
		GearKit.Box(body, 3 * s, 4 * s, 2.6 * s, 2.6 * s, Color3.fromRGB(30, 30, 40), { Name = "Eye", Radius = "round", Z = 5 })
		holder.Parent = root
		fish = holder
	end
	return keys, W, H, fish
end

function CoralKeys.Start(ctx)
	local animator = GearKit.Animator(ctx)
	local piece = GearPiece.new(ctx, {
		Id = "CoralKeys",
		Size = FULL,
		Shapes = { MINI },
		Priority = 2.5, -- v9.1 : cliquable -> avant les accessoires décoratifs
		MinScale = 0.3,
		MaxScale = 1,
		SizePenalty = 420,
		GlowColor = Color3.fromRGB(170, 250, 240),
		ContainerZ = 1102,
		Anchor = function(button, _canvas)
			-- Sous le clavier mécanique, à gauche
			return Vector2.new(button.X0 - 170, button.Y1 + 215)
		end,
	}, animator)
	local random = ctx.Random

	local fish: Frame? = nil
	local fishHome = Vector2.zero

	local function level(): number
		return math.max(1, piece.Level)
	end

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

	-- Bulle qui monte depuis un point de la toile
	local function releaseBubbleAt(origin: Vector2, big: boolean)
		if not GearKit.EffectsOn(ctx) then
			return
		end
		local bubble = bubbles:Next()
		local placeScale = math.max(0.7, piece.PlaceScale.Scale)
		local size = (big and random:NextNumber(10, 16) or random:NextNumber(6, 11)) * placeScale
		local rise = random:NextNumber(46, 78) * placeScale
		local wobble = random:NextNumber(3, 7)
		local phase = random:NextNumber(0, math.pi * 2)
		local duration = random:NextNumber(0.8, 1.1)
		local stroke = bubble:FindFirstChild("Stroke") :: UIStroke?
		animator:Play(bubble, duration, function(t)
			bubble.Visible = t < 1
			local popping = t > 0.86
			local sz = size * (0.6 + 0.4 * math.min(1, t * 3)) * (popping and (1 + (t - 0.86) * 4) or 1)
			bubble.Size = UDim2.fromOffset(sz, sz)
			bubble.Position = UDim2.fromOffset(origin.X + math.sin(phase + t * 7) * wobble, origin.Y - rise * GearKit.Ease.OutQuad(t))
			local fade = popping and (t - 0.86) / 0.14 or 0
			bubble.BackgroundTransparency = 0.7 + 0.3 * fade
			if stroke then
				stroke.Transparency = 0.15 + 0.85 * fade
			end
		end, function()
			bubble.Visible = false
		end)
	end

	local function releaseBubble(fromLocal: Vector2, big: boolean)
		local origin = piece:ToCanvas(fromLocal)
		if origin then
			releaseBubbleAt(origin, big)
		end
	end

	-- Le poisson sursaute
	local function fishJump()
		local swimmer = fish
		if swimmer then
			animator:Play("fishJump", 0.3, function(t)
				swimmer.Rotation = math.sin(t * math.pi * 4) * 14 * (1 - t)
			end)
		end
	end

	local keys
	keys = ClickableKeys.new(ctx, piece, animator, {
		Id = "CoralKeys",
		InputPriority = 2,
		StepFull = STEP_FULL,
		StepMini = STEP_MINI,
		Draw = drawCoral,
		Title = function(): string
			return ClickableKeys.TitleFor("🪸", "Coral Keyboard", level())
		end,
		Tray = Color3.fromRGB(18, 70, 96),
		BadgeInk = INK,
		Lit = function(lv: number): Color3?
			return lv >= 8 and Color3.fromRGB(120, 255, 235) or nil
		end,
		SoundPitch = 0.86, -- plus doux, plus grave
		OnBuilt = function(_root, _list, extra)
			animator:Stop("fish", true)
			fish = extra
			if extra then
				fishHome = Vector2.new(extra.Position.X.Offset, extra.Position.Y.Offset)
			end
		end,
		OnStrike = function(_key: KeyboardArt.Key, point: Vector2?)
			-- Une bulle monte de la touche frappée (clavier posé)
			if point and not keys.Panel:IsOpen() then
				releaseBubbleAt(point, level() >= 10)
			end
			fishJump()
		end,
	})
	keys:Build(level())
	piece.OnLevel = function(lv, _previous)
		keys:LevelChanged(lv)
	end

	-- Clic sur le gros bouton (ou autre accessoire) : touches + bulles
	ctx.Connect(ctx.State.Clicked, function()
		if not ctx.IsVisible() or not piece:IsShown() or GearClick.Source == "CoralKeys" then
			return
		end
		local lv = level()
		local pressed = KeyboardArt.Pick(keys.Keys, 2, random)
		for index, key in ipairs(pressed) do
			keys:AnimateKey(key, (index - 1) * 0.04)
		end
		for index = 1, bubblesPerClick(lv) do
			local key = pressed[(index - 1) % math.max(1, #pressed) + 1]
			if key then
				releaseBubble(Vector2.new(key.X + key.W / 2 + random:NextNumber(-6, 6), key.Y), lv >= 10)
			end
		end
		fishJump()
	end)

	-- Au repos : une bulle, et le poisson fait un petit tour
	GearKit.Every(ctx, 3, 5.5, function()
		if not piece:IsShown() then
			return
		end
		local width = piece.Size.X
		releaseBubble(Vector2.new(random:NextNumber(width * 0.2, width * 0.8), 20), false)
		keys:Wiggle()
		local swimmer = fish
		if swimmer and random:NextNumber() < 0.5 then
			local home = fishHome
			local lastStep = -1
			animator:Play("fish", 2.4, function(t)
				local step = math.floor(t * 72) -- (≤ 30 images/s)
				if step == lastStep then
					return
				end
				lastStep = step
				local k = step / 72
				local angle = k * math.pi * 2
				local x = home.X - math.min(70, piece.Size.X * 0.45) * math.sin(angle * 0.5)
				local y = home.Y + math.sin(angle) * 3
				swimmer.Position = UDim2.fromOffset(x, y)
				swimmer.Rotation = math.cos(angle * 3) * 6
			end, function()
				swimmer.Position = UDim2.fromOffset(home.X, home.Y)
				swimmer.Rotation = 0
			end)
		end
	end)

	active[ctx] = { Piece = piece, Keys = keys }
end

function CoralKeys.Stop(ctx)
	local entry = active[ctx]
	active[ctx] = nil
	if entry then
		entry.Keys:Destroy()
		entry.Piece:Destroy()
	end
end

return CoralKeys
