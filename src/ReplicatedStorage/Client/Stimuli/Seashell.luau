--[[
	Seashell (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Seashell

	🐚 Coquillage (gains x1,5, après 1 visite à l'océan) : une coquille
	Saint-Jacques nacrée ouverte (éventail rose pêche à rayures, coupe
	devant) posée sur une petite flaque d'eau turquoise ; au milieu, une
	perle qui brille doucement (halo qui respire, reflet, éclat qui passe).
	Des reflets d'eau ondulent sous la coquille et de petites bulles
	montent vers la surface.
	Calque Background, place donnée par Cosmos/Zones (de préférence en bas,
	« au fond de la mer »). ≤ 20 images/s, ~50 instances, bulles recyclées.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local Seashell = {}
Seashell.Slot = "Background"

local ID = "Seashell"
local BOX_W, BOX_H = 124, 116
local HINGE_X, HINGE_Y = 62, 72 -- charnière (centre de l'éventail)
local FAN_R = 48
local PEARL_Y = 66
local BUBBLES = 4

function Seashell.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local dark = Kit.IsDark(ctx)
	local piece = Kit.Piece(ctx.Container, "Seashell", BOX_W, BOX_H)

	local content: Frame? = nil
	local glows: { Frame } = {}
	local glint: Frame? = nil
	local highlight: Frame? = nil
	local shimmers: { { Frame: Frame, Phase: number, Base: Vector2 } } = {}
	type Bubble = { Frame: Frame, Stroke: UIStroke, P: number, X: number, Speed: number, Size: number }
	local bubbles: { Bubble } = {}

	local function build()
		if content then
			content:Destroy()
		end
		table.clear(glows)
		table.clear(shimmers)
		table.clear(bubbles)
		local root = Kit.Box(piece.Frame, { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		content = root
		local outline = if dark then Kit.Rgb(255, 214, 222) else Kit.Rgb(214, 104, 128)

		-- Flaque d'eau + reflets
		local pool = Kit.Ellipse(root, HINGE_X, 100, 120, 22, if dark then Kit.Rgb(90, 200, 255) else Kit.Rgb(110, 214, 226), if dark then 0.55 else 0.45, 1)
		pool.Name = "Pool"
		for index, spec in ipairs({ { 36, 98, 26 }, { 76, 103, 34 }, { 58, 94, 18 } }) do
			local line = Kit.Box(root, {
				Name = "Shimmer",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(spec[1], spec[2]),
				Size = UDim2.fromOffset(spec[3], 3),
				Color = Color3.new(1, 1, 1),
				Alpha = 0.4,
				ZIndex = 2,
			})
			Kit.Corner(line)
			table.insert(shimmers, { Frame = line, Phase = index * 2.1, Base = Vector2.new(spec[1], spec[2]) })
		end

		-- Halo de la perle (derrière l'éventail : lueur nacrée)
		for index, spec in ipairs({ { 96, 0.86 }, { 66, 0.74 } }) do
			local glow = Kit.Circle(root, HINGE_X, PEARL_Y, spec[1], Kit.Rgb(255, 214, 236), spec[2], 2 + index)
			glow.Name = "Glow"
			table.insert(glows, glow)
		end

		-- Éventail (moitié haute d'un disque) + rayures
		local fanClip = Kit.Box(root, {
			Name = "Fan",
			Position = UDim2.fromOffset(HINGE_X - FAN_R - 4, HINGE_Y - FAN_R - 4),
			Size = UDim2.fromOffset(FAN_R * 2 + 8, FAN_R + 4),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 5,
		})
		local fan = Kit.Circle(fanClip, FAN_R + 4, FAN_R + 4, FAN_R * 2, Color3.new(1, 1, 1), 0, 5)
		Kit.Gradient(fan, ColorSequence.new(Kit.Rgb(255, 222, 196), Kit.Rgb(255, 150, 172)), nil, 90)
		Kit.Stroke(fan, outline, 2, if dark then 0.35 else 0)
		for index = -2, 2 do
			Kit.Box(fanClip, {
				Name = "Rib",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromOffset(FAN_R + 4, FAN_R + 4),
				Size = UDim2.fromOffset(2, FAN_R - 8),
				Rotation = index * 30,
				Color = Kit.Rgb(255, 250, 244),
				Alpha = 0.35,
				ZIndex = 6,
			})
		end

		-- Perle
		local pearl = Kit.Circle(root, HINGE_X, PEARL_Y, 24, Color3.new(1, 1, 1), 0, 7)
		pearl.Name = "Pearl"
		Kit.Gradient(pearl, ColorSequence.new(Color3.new(1, 1, 1), Kit.Rgb(236, 214, 255)), nil, 60)
		if not dark then
			Kit.Stroke(pearl, Kit.Rgb(206, 176, 230), 1, 0)
		end
		highlight = Kit.Circle(root, HINGE_X - 5, PEARL_Y - 6, 7, Color3.new(1, 1, 1), 0, 8)

		-- Coupe avant (moitié basse d'une ellipse), devant la perle
		local bowlClip = Kit.Box(root, {
			Name = "Bowl",
			Position = UDim2.fromOffset(HINGE_X - 56, HINGE_Y),
			Size = UDim2.fromOffset(112, 24),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 9,
		})
		local bowl = Kit.Ellipse(bowlClip, 56, 0, 104, 40, Color3.new(1, 1, 1), 0, 9)
		Kit.Gradient(bowl, ColorSequence.new(Kit.Rgb(255, 196, 186), Kit.Rgb(238, 128, 150)), nil, 90)
		Kit.Stroke(bowl, outline, 2, if dark then 0.35 else 0)

		-- Éclat qui passe sur la perle
		glint = Kit.Glint(root, HINGE_X + 7, PEARL_Y - 8, 14, Color3.new(1, 1, 1), 10)

		-- Bulles
		for _ = 1, BUBBLES do
			local size = random:NextInteger(5, 9)
			local frame = Kit.Box(root, {
				Name = "Bubble",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
				Color = Color3.new(1, 1, 1),
				Alpha = 0.75,
				ZIndex = 10,
			})
			Kit.Corner(frame)
			local stroke = Kit.Stroke(frame, if dark then Kit.Rgb(200, 240, 255) else Kit.Rgb(80, 170, 200), 1, 0.2)
			table.insert(bubbles, { Frame = frame, Stroke = stroke, P = random:NextNumber(), X = random:NextNumber(26, 98), Speed = random:NextNumber(0.25, 0.4), Size = size })
		end
	end

	build()
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		build()
	end)

	Zones.Request(ID, {
		{ W = BOX_W, H = BOX_H, Anchor = Vector2.new(0.62, 0.97), MinScale = 0.45, MaxScale = 1.15 },
	}, function(placements)
		Kit.Place(piece, placements[1])
	end)

	Kit.Loop(ctx, 20, function(dt, t)
		if not piece.Placed then
			return
		end
		-- La perle respire
		local breath = 0.5 + 0.5 * math.sin(t * 1.6)
		local outer, inner = glows[1], glows[2]
		if outer and inner then
			outer.BackgroundTransparency = 0.9 - breath * 0.08
			inner.BackgroundTransparency = 0.8 - breath * 0.14
			inner.Size = UDim2.fromOffset(62 + breath * 8, 62 + breath * 8)
		end
		local shine = highlight
		if shine then
			shine.BackgroundTransparency = 0.1 + 0.3 * (1 - breath)
		end
		-- Éclat : passe toutes les ~4 s
		local sparkle = glint
		if sparkle then
			local p = (t % 4) / 4
			local on = if p < 0.12 then math.sin(p / 0.12 * math.pi) else 0
			sparkle.Size = UDim2.fromOffset(4 + on * 14, 4 + on * 14)
			sparkle.Visible = on > 0.02
			sparkle.Rotation = p * 90
		end
		-- Reflets d'eau qui ondulent
		for _, s in ipairs(shimmers) do
			local wave = math.sin(t * 1.2 + s.Phase)
			s.Frame.Position = UDim2.fromOffset(s.Base.X + wave * 5, s.Base.Y)
			s.Frame.BackgroundTransparency = 0.35 + 0.4 * (0.5 + 0.5 * math.sin(t * 2 + s.Phase))
		end
		-- Bulles qui montent en zigzag
		if effects then
			for _, b in ipairs(bubbles) do
				b.P += dt * b.Speed
				if b.P >= 1 then
					b.P -= 1
					b.X = random:NextNumber(30, 94)
				end
				local y = 70 - b.P * 70
				b.Frame.Position = UDim2.fromOffset(b.X + math.sin(b.P * 12) * 3, y)
				local fade = if b.P < 0.15 then 1 - b.P / 0.15 elseif b.P > 0.75 then (b.P - 0.75) / 0.25 else 0
				b.Frame.BackgroundTransparency = 0.75 + fade * 0.25
				b.Stroke.Transparency = 0.2 + fade * 0.8
			end
		end
	end)
end

function Seashell.Stop(_ctx)
	Zones.Release(ID)
end

return Seashell
