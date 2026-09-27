--[[
	TimeWarp (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > TimeWarp

	⏳ Distorsion temporelle (gains x2, après 3 visites à l'océan) : une grande
	horloge translucide (cadran crème, bord doré, 12 graduations, aiguilles)
	dont les aiguilles tournent tranquillement... puis s'emballent en
	« vitesse lumière » quelques secondes (aiguilles fantômes qui traînent
	derrière), avant de ralentir. Des ondes du temps s'élargissent autour du
	cadran, et à chaque emballement une grande onde très pâle traverse tout
	le fond de l'écran (visible entre toutes les cartes).
	Calque Background : l'horloge est posée par Cosmos/Zones ; l'onde est un
	simple anneau agrandi (aucune création par image). ≤ 20 images/s.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local TimeWarp = {}
TimeWarp.Slot = "Background"

local ID = "TimeWarp"
local BOX = 108
local C = BOX / 2 -- centre du cadran
local FACE = 84
local RIPPLES = 3
local WARP_EVERY = 7 -- secondes entre deux emballements
local WARP_TIME = 1.8
local WAVE_TIME = 3.2

function TimeWarp.Start(ctx)
	Zones.Attach(ctx)
	local effects = Kit.Effects(ctx)
	local dark = Kit.IsDark(ctx)
	local piece = Kit.Piece(ctx.Container, "Clock", BOX, BOX)

	-- Grande onde (dans tout le conteneur, derrière l'horloge)
	local wave, waveStroke = Kit.Ring(ctx.Container, 0, 0, 10, Kit.Rgb(255, 214, 140), 2, 1, 1)
	wave.Name = "TimeWave"
	wave.Visible = false

	local content: Frame? = nil
	local hourHand: Frame? = nil
	local minuteHand: Frame? = nil
	local ghosts: { Frame } = {}
	local ripples: { { Frame: Frame, Stroke: UIStroke, Offset: number } } = {}
	local face: Frame? = nil

	local function build()
		if content then
			content:Destroy()
		end
		table.clear(ghosts)
		table.clear(ripples)
		local root = Kit.Box(piece.Frame, { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		content = root
		local gold = Kit.Rgb(232, 176, 82)
		local handColor = if dark then Kit.Rgb(255, 240, 214) else Kit.Rgb(110, 74, 40)

		-- Ondes du temps autour du cadran
		for index = 1, RIPPLES do
			local ring, stroke = Kit.Ring(root, C, C, FACE, gold, 2, 1, 1)
			ring.Name = "Ripple"
			table.insert(ripples, { Frame = ring, Stroke = stroke, Offset = (index - 1) / RIPPLES })
		end

		-- Cadran translucide
		local dial = Kit.Circle(root, C, C, FACE, Color3.new(1, 1, 1), if dark then 0.45 else 0.3, 2)
		dial.Name = "Face"
		Kit.Gradient(dial, ColorSequence.new(Kit.Rgb(255, 250, 232), Kit.Rgb(255, 222, 170)), nil, 45)
		Kit.Stroke(dial, gold, 3, 0)
		face = dial
		local inner = Kit.Ring(root, C, C, FACE - 18, gold, 1, 0.55, 3)
		inner.Name = "InnerRing"

		-- 12 graduations (4 grandes)
		for hour = 0, 11 do
			local angle = hour * math.pi / 6
			local major = hour % 3 == 0
			local radius = FACE / 2 - (if major then 8 else 6)
			Kit.Box(root, {
				Name = "Tick",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(C + math.sin(angle) * radius, C - math.cos(angle) * radius),
				Size = UDim2.fromOffset(if major then 3 else 2, if major then 9 else 5),
				Rotation = hour * 30,
				Color = if major then gold else handColor,
				Alpha = if major then 0 else 0.35,
				ZIndex = 3,
			})
		end

		-- Aiguilles fantômes (traînée pendant l'emballement)
		for index = 1, 2 do
			local ghost = Kit.Box(root, {
				Name = "Ghost",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromOffset(C, C),
				Size = UDim2.fromOffset(3, 34),
				Color = gold,
				Alpha = 1,
				ZIndex = 4,
			})
			ghosts[index] = ghost
		end
		-- Aiguilles
		local hour = Kit.Box(root, {
			Name = "HourHand",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(C, C),
			Size = UDim2.fromOffset(5, 23),
			Color = handColor,
			ZIndex = 5,
		})
		Kit.Corner(hour, 3)
		hourHand = hour
		local minute = Kit.Box(root, {
			Name = "MinuteHand",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(C, C),
			Size = UDim2.fromOffset(3, 35),
			Color = handColor,
			ZIndex = 6,
		})
		Kit.Corner(minute, 2)
		minuteHand = minute
		Kit.Circle(root, C, C, 9, gold, 0, 7)
	end

	build()
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		build()
	end)

	local centre = Vector2.new(-1000, -1000) -- centre de l'horloge sur la toile
	Zones.Request(ID, {
		{ W = BOX, H = BOX, Anchor = Vector2.new(0.2, 0.56), MinScale = 0.4, MaxScale = 1.15 },
	}, function(placements)
		local placement = placements[1]
		Kit.Place(piece, placement)
		if placement then
			centre = Vector2.new(placement.X, placement.Y)
		end
	end)

	local minuteAngle, hourAngle = 40, 300
	local ghostAngles = { 40, 40 }
	local warpClock = 3
	local waveClock = -1
	Kit.Loop(ctx, 20, function(dt, t)
		if not piece.Placed then
			return
		end
		-- Vitesse des aiguilles : calme, puis emballement (accélère / ralentit)
		warpClock += dt
		local warp = 0
		if warpClock >= WARP_EVERY then
			local p = (warpClock - WARP_EVERY) / WARP_TIME
			if p >= 1 then
				warpClock = 0
			else
				warp = math.sin(p * math.pi)
				if waveClock < 0 and p > 0.3 then
					waveClock = 0
				end
			end
		end
		local speed = 36 + warp * 900 -- degrés / seconde
		minuteAngle = (minuteAngle + speed * dt) % 360
		hourAngle = (hourAngle + speed * dt / 12) % 360
		local minute, hour = minuteHand, hourHand
		if minute and hour then
			minute.Rotation = minuteAngle
			hour.Rotation = hourAngle
		end
		-- Fantômes : suivent l'aiguille avec un retard (visibles pendant l'emballement)
		for index, ghost in ipairs(ghosts) do
			local lag = index * 0.045 * speed
			ghostAngles[index] = minuteAngle - lag
			ghost.Rotation = ghostAngles[index]
			ghost.BackgroundTransparency = 1 - warp * (if index == 1 then 0.55 else 0.3)
		end
		local dial = face
		if dial then
			dial.Rotation = warp * math.sin(t * 20) * 2
		end
		-- Ondes autour du cadran
		for _, ripple in ipairs(ripples) do
			local p = (t * (0.35 + warp * 0.9) + ripple.Offset) % 1
			local size = FACE + p * (BOX - FACE)
			ripple.Frame.Size = UDim2.fromOffset(size, size)
			ripple.Stroke.Transparency = 0.35 + p * 0.65
		end
		-- Grande onde qui traverse le fond
		if waveClock >= 0 and effects then
			waveClock += dt
			local p = waveClock / WAVE_TIME
			if p >= 1 then
				waveClock = -1
				wave.Visible = false
			else
				local canvas = Zones.GetCanvas()
				local size = 60 + p * canvas.Magnitude * 1.1
				wave.Visible = true
				wave.Position = UDim2.fromOffset(centre.X, centre.Y)
				wave.Size = UDim2.fromOffset(size, size)
				waveStroke.Thickness = 2 + p * 6
				waveStroke.Transparency = 0.45 + p * 0.55
			end
		end
	end)
end

function TimeWarp.Stop(_ctx)
	Zones.Release(ID)
end

return TimeWarp
