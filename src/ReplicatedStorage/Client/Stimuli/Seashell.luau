--[[
	Seashell (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Seashell

	🐚 Coquillage (gains x1,5, après 1 visite à l'océan) : une coquille
	Saint-Jacques nacrée ouverte (éventail de côtes arrondies rose pêche,
	bord festonné, charnière, lèvre avant) posée sur une petite flaque d'eau
	turquoise ; entre les deux valves, une perle qui brille doucement (halo
	qui respire, reflet, éclat qui passe). Des reflets d'eau ondulent sous la
	coquille et de petites bulles montent vers la surface.
	Calque Background, place donnée par Cosmos/Zones (de préférence en bas,
	« au fond de la mer »). ≤ 20 images/s, ~58 instances, bulles recyclées.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local Seashell = {}
Seashell.Slot = "Background"

local ID = "Seashell"
local BOX_W, BOX_H = 120, 106
local HINGE_X, HINGE_Y = 60, 74 -- charnière (centre de l'éventail)
local RIB_LENGTH = 52
local RIB_ANGLES = { -64, 64, -32, 32, 0 } -- côtés d'abord, celle du milieu par-dessus
local PEARL_Y = 67
local BUBBLES = 3

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
	type Bubble = { Frame: Frame, Stroke: UIStroke, P: number, X: number, Speed: number }
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
		local outline = if dark then Kit.Rgb(255, 222, 228) else Kit.Rgb(214, 104, 128)
		local outlineAlpha = if dark then 0.45 else 0

		-- Flaque d'eau + reflets
		local pool = Kit.Ellipse(root, HINGE_X, 94, 116, 20, if dark then Kit.Rgb(90, 200, 255) else Kit.Rgb(110, 214, 226), if dark then 0.55 else 0.4, 1)
		pool.Name = "Pool"
		for index, spec in ipairs({ { 30, 93, 22 }, { 80, 97, 30 }, { 56, 90, 14 } }) do
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

		-- Halo nacré de la perle (derrière l'éventail)
		for index, spec in ipairs({ { 104, 0.86 }, { 70, 0.74 } }) do
			local glow = Kit.Circle(root, HINGE_X, PEARL_Y - 8, spec[1], Kit.Rgb(255, 214, 236), spec[2], 2 + index)
			glow.Name = "Glow"
			table.insert(glows, glow)
		end

		-- Éventail : côtes arrondies qui rayonnent depuis la charnière (bord
		-- festonné). Une rotation Roblox tourne autour du CENTRE du cadre :
		-- chaque côte est donc centrée à mi-longueur, dans sa direction.
		for index, angle in ipairs(RIB_ANGLES) do
			local middle = angle == 0
			local length = RIB_LENGTH - math.abs(angle) * 0.06
			local radians = math.rad(angle)
			local rib = Kit.Box(root, {
				Name = "Rib",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(HINGE_X + math.sin(radians) * length / 2, HINGE_Y - math.cos(radians) * length / 2),
				Size = UDim2.fromOffset(if middle then 26 else 24, length),
				Rotation = angle,
				Color = if index % 2 == 0 then Kit.Rgb(255, 176, 186) else Kit.Rgb(255, 204, 186),
				ZIndex = 5,
			})
			Kit.Corner(rib, 12)
			Kit.Gradient(rib, ColorSequence.new(Kit.Rgb(255, 250, 244), Kit.Rgb(236, 226, 232)), nil, 90)
			Kit.Stroke(rib, outline, 1.5, outlineAlpha)
		end
		-- Charnière (oreillettes)
		local hinge = Kit.Box(root, {
			Name = "Hinge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(HINGE_X, HINGE_Y - 2),
			Size = UDim2.fromOffset(34, 12),
			Color = Kit.Rgb(255, 190, 176),
			ZIndex = 6,
		})
		Kit.Corner(hinge, 5)
		Kit.Stroke(hinge, outline, 1.5, outlineAlpha)

		-- Perle
		local pearl = Kit.Circle(root, HINGE_X, PEARL_Y, 24, Color3.new(1, 1, 1), 0, 7)
		pearl.Name = "Pearl"
		Kit.Gradient(pearl, ColorSequence.new(Color3.new(1, 1, 1), Kit.Rgb(232, 210, 255)), nil, 60)
		if not dark then
			Kit.Stroke(pearl, Kit.Rgb(206, 176, 230), 1, 0)
		end
		highlight = Kit.Circle(root, HINGE_X - 5, PEARL_Y - 6, 7, Color3.new(1, 1, 1), 0, 8)

		-- Lèvre avant (valve du bas, moitié basse d'une ellipse), devant la perle
		local lipClip = Kit.Box(root, {
			Name = "Lip",
			Position = UDim2.fromOffset(HINGE_X - 50, HINGE_Y),
			Size = UDim2.fromOffset(100, 20),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 9,
		})
		local lip = Kit.Ellipse(lipClip, 50, 0, 92, 32, Color3.new(1, 1, 1), 0, 9)
		Kit.Gradient(lip, ColorSequence.new(Kit.Rgb(255, 204, 190), Kit.Rgb(240, 138, 156)), nil, 90)
		Kit.Stroke(lip, outline, 1.5, outlineAlpha)

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
			table.insert(bubbles, { Frame = frame, Stroke = stroke, P = random:NextNumber(), X = random:NextNumber(30, 90), Speed = random:NextNumber(0.25, 0.4) })
		end
	end

	build()
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		build()
	end)

	Zones.Request(ID, {
		{ W = BOX_W, H = BOX_H, Anchor = Vector2.new(0.62, 0.97), MinScale = 0.4, MaxScale = 1.15 },
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
			inner.Size = UDim2.fromOffset(66 + breath * 8, 66 + breath * 8)
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
					b.X = random:NextNumber(30, 90)
				end
				local y = 66 - b.P * 64
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
