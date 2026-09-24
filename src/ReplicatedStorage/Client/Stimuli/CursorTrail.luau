--[[
	CursorTrail (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > CursorTrail

	Traînée magique : des étincelles arc-en-ciel suivent la souris (et le
	doigt sur mobile / tablette), tournoient, tombent un peu et s'éteignent.
	Chaque clic / toucher fait une petite gerbe d'étoiles.
	Purement visuel, non cliquable. 40 étincelles maximum, recyclées.
]]

local UserInputService = game:GetService("UserInputService")

local CursorTrail = {}
CursorTrail.Slot = "Overlay"

local MAX_SPARKLES = 40
local EMIT_SPACING = 14 -- distance (pixels "design") entre deux étincelles
local MAX_PER_FRAME = 3
local EMOJI_CHANCE = 0.18 -- parfois un ✨ / ⭐ au lieu d'un losange
local EMOJIS = { "✨", "⭐", "💫" }

function CursorTrail.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()

	local pool = {}
	local nextSlot = 1
	local hue = random:NextNumber()

	local pointer: Vector2? = nil -- dernière position connue (pixels écran réels)
	local lastEmit: Vector2? = nil
	local burstQueue = {} -- positions des clics à traiter

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Crée toutes les étincelles une seule fois (recyclage circulaire)
	for i = 1, MAX_SPARKLES do
		local label = UIUtil.Create("TextLabel", {
			Name = "Sparkle",
			Size = UDim2.fromOffset(10, 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Theme.Fonts.Body,
			Text = "",
			TextSize = 18,
			Active = false,
			Selectable = false,
			Visible = false,
			ZIndex = 60,
			Parent = container,
		})
		UIUtil.Corner(label, 3)
		local stroke = UIUtil.Stroke(label, Theme.Colors.Border, 1, 0.55)
		pool[i] = {
			Label = label,
			Stroke = stroke,
			Alive = false,
			Life = 0,
			MaxLife = 1,
			Pos = Vector2.zero,
			Vel = Vector2.zero,
			Size = 10,
			Spin = 0,
			Emoji = false,
		}
	end

	-- Émet une étincelle à `position` (pixels écran réels)
	local function emit(position: Vector2, velocity: Vector2, big: boolean?)
		local sparkle = pool[nextSlot]
		nextSlot = nextSlot % MAX_SPARKLES + 1

		hue = (hue + 0.035) % 1
		local color = Color3.fromHSV(hue, 0.8, 1)
		local isEmoji = random:NextNumber() < EMOJI_CHANCE
		local size = big and random:NextNumber(12, 18) or random:NextNumber(7, 13)

		sparkle.Alive = true
		sparkle.Emoji = isEmoji
		sparkle.Pos = position
		sparkle.Vel = velocity
		sparkle.Life = 0
		sparkle.MaxLife = random:NextNumber(0.45, 0.8)
		sparkle.Size = isEmoji and size * 1.8 or size
		sparkle.Spin = random:NextNumber(-360, 360)

		local label: TextLabel = sparkle.Label
		label.Rotation = 45
		if isEmoji then
			label.Text = EMOJIS[random:NextInteger(1, #EMOJIS)]
			label.TextSize = math.floor(sparkle.Size)
			label.TextTransparency = 0
			label.BackgroundTransparency = 1
			sparkle.Stroke.Enabled = false
		else
			label.Text = ""
			label.BackgroundColor3 = color
			label.BackgroundTransparency = 0
			sparkle.Stroke.Enabled = true
			sparkle.Stroke.Transparency = 0.55
		end
		label.Visible = true
	end

	-- Position du pointeur (même repère que AbsolutePosition)
	ctx.Connect(UserInputService.InputChanged, function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	ctx.Connect(UserInputService.InputBegan, function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			local position = Vector2.new(input.Position.X, input.Position.Y)
			if kind == Enum.UserInputType.Touch then
				-- Nouveau doigt : pas de trait depuis l'ancienne position
				pointer = position
				lastEmit = position
			end
			if #burstQueue < 4 then
				table.insert(burstQueue, position)
			end
		end
	end)
	ctx.Connect(UserInputService.InputEnded, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			pointer = nil
			lastEmit = nil
		end
	end)

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		local origin = container.AbsolutePosition
		local area = container.AbsoluteSize
		if area.X < 1 or area.Y < 1 then
			return
		end
		-- Pixels réels par pixel "design" (échelle de l'interface)
		local k = area.Y / 720
		local effects = effectsOn()

		-- Traînée : étincelles espacées le long du déplacement
		local current = pointer
		if current then
			if not lastEmit then
				lastEmit = current
			else
				local from = lastEmit :: Vector2
				local delta = current - from
				local distance = delta.Magnitude
				local spacing = EMIT_SPACING * k * (effects and 1 or 2.5)
				if distance >= spacing then
					local steps = math.min(MAX_PER_FRAME, math.floor(distance / spacing))
					for i = 1, steps do
						local point = from + delta * (i / steps)
						local drift = Vector2.new(random:NextNumber(-30, 30), random:NextNumber(-40, 10)) * k
						emit(point, drift - delta.Unit * 25 * k)
					end
					lastEmit = current
				end
			end
		end

		-- Gerbes de clic
		if #burstQueue > 0 then
			for _, position in ipairs(burstQueue) do
				local count = effects and 8 or 3
				local offset = random:NextNumber(0, math.pi * 2)
				for i = 1, count do
					local angle = offset + (i / count) * math.pi * 2
					local speed = random:NextNumber(110, 170) * k
					emit(position, Vector2.new(math.cos(angle), math.sin(angle)) * speed, true)
				end
			end
			table.clear(burstQueue)
		end

		-- Animation des étincelles vivantes
		local gravity = 160 * k
		for _, sparkle in ipairs(pool) do
			if sparkle.Alive then
				sparkle.Life += dt
				local ratio = sparkle.Life / sparkle.MaxLife
				local label: TextLabel = sparkle.Label
				if ratio >= 1 then
					sparkle.Alive = false
					label.Visible = false
				else
					sparkle.Vel = sparkle.Vel * (1 - math.min(1, 2.5 * dt)) + Vector2.new(0, gravity * dt)
					sparkle.Pos += sparkle.Vel * dt
					local relative = (sparkle.Pos - origin) / area
					label.Position = UDim2.fromScale(relative.X, relative.Y)
					label.Rotation += sparkle.Spin * dt
					-- Grossit vite puis rétrécit en s'éteignant
					local grow = ratio < 0.15 and (ratio / 0.15) or (1 - (ratio - 0.15) / 0.85)
					local size = math.max(1, sparkle.Size * (0.3 + 0.7 * grow))
					if sparkle.Emoji then
						label.TextSize = math.floor(size)
						label.Size = UDim2.fromOffset(size, size)
						label.TextTransparency = ratio * ratio
					else
						label.Size = UDim2.fromOffset(size, size)
						label.BackgroundTransparency = ratio * ratio
						sparkle.Stroke.Transparency = 0.55 + 0.45 * ratio
					end
				end
			end
		end
	end)
end

function CursorTrail.Stop(_ctx)
	-- Les étincelles sont dans ctx.Container (détruit par le StimulusManager)
end

return CursorTrail
