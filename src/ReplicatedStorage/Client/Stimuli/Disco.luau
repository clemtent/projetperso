--[[
	Disco (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Disco

	Boule disco (calque Overlay) suspendue en haut, à droite de la colonne
	centrale (x = centre + 360) : une mosaïque de petites facettes qui
	"tournent" et scintillent, avec des reflets colorés.
	Elle projette des faisceaux de lumière translucides qui balayent tout
	l'écran en changeant de couleur, et quelques taches de lumière qui se
	promènent. Rien n'est cliquable : les clics passent à travers.
]]

local Debris = game:GetService("Debris")

local Disco = {}
Disco.Slot = "Overlay"

local BALL_X = 360 -- décalage depuis le centre de l'écran
local BALL_Y = 74
local BALL_SIZE = 58
local TILE = 8 -- taille d'une facette (avec 1 px d'écart)
local GRID = 7 -- facettes par ligne / colonne
local PATTERN_W = 14 -- largeur du motif qui "tourne"
local BEAM_LENGTH = 1500
local MAX_SPARKLES = 5

function Disco.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local root = Create("Frame", {
		Name = "Disco",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 1,
		Parent = container,
	})

	------------------------------------------------------------------
	-- Taches de lumière (derrière les faisceaux)
	------------------------------------------------------------------
	local spots = {}
	if effectsOn() then
		for index = 1, 4 do
			local size = random:NextInteger(140, 220)
			local spot = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.88,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = root,
			})
			UIUtil.Corner(spot, UDim.new(1, 0))
			table.insert(spots, {
				Frame = spot,
				A = random:NextNumber(0.15, 0.35),
				B = random:NextNumber(0.12, 0.3),
				P = random:NextNumber(0, math.pi * 2),
				Q = random:NextNumber(0, math.pi * 2),
				Hue = index / 4,
			})
		end
	end

	------------------------------------------------------------------
	-- Faisceaux
	------------------------------------------------------------------
	local beams = {}
	local beamCount = effectsOn() and 6 or 3
	for index = 1, beamCount do
		local beam = Create("Frame", {
			Name = "Beam",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(BEAM_LENGTH, random:NextInteger(40, 70)),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = root,
		})
		-- Lumineux près de la boule, s'efface au loin
		Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.62),
				NumberSequenceKeypoint.new(0.4, 0.84),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = beam,
		})
		table.insert(beams, {
			Frame = beam,
			-- La boule est à droite : les faisceaux partent surtout vers le bas / la gauche
			Base = 60 + (index - 1) * (110 / math.max(1, beamCount - 1)),
			Amp = random:NextNumber(18, 38),
			Freq = random:NextNumber(0.35, 0.8) * (random:NextNumber() < 0.5 and -1 or 1),
			Phase = random:NextNumber(0, math.pi * 2),
			Hue = (index - 1) / beamCount,
		})
	end

	------------------------------------------------------------------
	-- La boule
	------------------------------------------------------------------
	local ballPosition = UDim2.new(0.5, BALL_X, 0, BALL_Y)

	-- Fil (depuis le bas du bandeau d'actu)
	Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, BALL_X, 0, 28),
		Size = UDim2.fromOffset(2, BALL_Y - 28 - BALL_SIZE / 2 + 2),
		BackgroundColor3 = Color3.fromRGB(70, 70, 80),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = root,
	})

	-- Halo coloré autour de la boule
	local halo = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = ballPosition,
		Size = UDim2.fromOffset(BALL_SIZE + 34, BALL_SIZE + 34),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = root,
	})
	UIUtil.Corner(halo, UDim.new(1, 0))

	local ball = Create("Frame", {
		Name = "Ball",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = ballPosition,
		Size = UDim2.fromOffset(BALL_SIZE, BALL_SIZE),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = root,
	})
	UIUtil.Corner(ball, UDim.new(1, 0))
	UIUtil.Stroke(ball, Color3.fromRGB(40, 40, 50), 1.5, 0.2)
	UIUtil.Gradient(ball, ColorSequence.new(Color3.fromRGB(235, 235, 245), Color3.fromRGB(95, 95, 115)), 45)

	-- Facettes (seulement celles qui tiennent dans le cercle)
	local tiles = {}
	local radius = BALL_SIZE / 2
	local gridOrigin = (BALL_SIZE - GRID * TILE) / 2
	for i = 0, GRID - 1 do
		for j = 0, GRID - 1 do
			local cx = gridOrigin + i * TILE + TILE / 2 - radius
			local cy = gridOrigin + j * TILE + TILE / 2 - radius
			local far = math.sqrt((math.abs(cx) + TILE / 2) ^ 2 + (math.abs(cy) + TILE / 2) ^ 2)
			if far <= radius + 2 then
				local distance = math.sqrt(cx * cx + cy * cy)
				local tile = Create("Frame", {
					Position = UDim2.fromOffset(gridOrigin + i * TILE, gridOrigin + j * TILE),
					Size = UDim2.fromOffset(TILE - 1, TILE - 1),
					BackgroundColor3 = Color3.fromRGB(200, 200, 210),
					BackgroundTransparency = 0.1,
					BorderSizePixel = 0,
					ZIndex = 6,
					Parent = ball,
				})
				-- Plus sombre sur les bords (effet de sphère), plus clair en haut à gauche
				local shade = 1 - (distance / radius) * 0.4 - (cx + cy) / BALL_SIZE * 0.2
				table.insert(tiles, { Frame = tile, I = i, J = j, Shade = math.clamp(shade, 0.35, 1.1) })
			end
		end
	end

	-- Reflet
	local highlight = Create("Frame", {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(12, 9),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = ball,
	})
	UIUtil.Corner(highlight, UDim.new(1, 0))

	-- Motif de luminosité qui défile (donne l'illusion de rotation)
	local pattern = {}
	for x = 1, PATTERN_W do
		pattern[x] = {}
		for y = 1, GRID do
			pattern[x][y] = random:NextNumber(0.55, 1)
		end
	end

	------------------------------------------------------------------
	-- Étincelles autour de la boule
	------------------------------------------------------------------
	local sparkles = 0
	local function spawnSparkle()
		if sparkles >= MAX_SPARKLES then
			return
		end
		sparkles += 1
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(radius + 4, radius + 26)
		local star = UIUtil.Label({
			Text = random:NextNumber() < 0.6 and "✦" or "✨",
			TextColor3 = Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = ballPosition + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance),
			Size = UDim2.fromOffset(16, 16),
			MaxTextSize = 16,
			ZIndex = 9,
			Parent = root,
		})
		local stroke = UIUtil.Stroke(star, Color3.fromRGB(90, 60, 140), 1, 0.3)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		local scale = Create("UIScale", { Scale = 0.1, Parent = star })
		UIUtil.Tween(scale, 0.25, { Scale = 1.1 }, Enum.EasingStyle.Back)
		UIUtil.Tween(star, 0.7, { TextTransparency = 1, Rotation = random:NextNumber(-90, 90) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UIUtil.Tween(stroke, 0.7, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(star, 0.75)
		task.delay(0.75, function()
			sparkles -= 1
		end)
	end

	------------------------------------------------------------------
	-- Animation
	------------------------------------------------------------------
	local time = 0
	local tileClock = 0
	local sparkleClock = 0
	local rotationStep = 0

	ctx.OnRender(function(dt: number)
		time += dt

		-- Faisceaux qui balayent (pivot = la boule)
		for _, beam in ipairs(beams) do
			local angle = beam.Base + math.sin(time * beam.Freq + beam.Phase) * beam.Amp
			local radians = math.rad(angle)
			local half = BEAM_LENGTH / 2
			beam.Frame.Position = UDim2.new(0.5, BALL_X + math.cos(radians) * half, 0, BALL_Y + math.sin(radians) * half)
			beam.Frame.Rotation = angle
			beam.Frame.BackgroundColor3 = Color3.fromHSV((time * 0.08 + beam.Hue) % 1, 0.7, 1)
			beam.Frame.BackgroundTransparency = 0.15 + (math.sin(time * 2.3 + beam.Phase) + 1) * 0.15
		end

		-- Taches de lumière (courbes de Lissajous)
		for _, spot in ipairs(spots) do
			spot.Frame.Position = UDim2.fromScale(
				0.5 + math.sin(time * spot.A + spot.P) * 0.45,
				0.55 + math.sin(time * spot.B + spot.Q) * 0.38
			)
			spot.Frame.BackgroundColor3 = Color3.fromHSV((time * 0.05 + spot.Hue) % 1, 0.6, 1)
		end

		local hueColor = Color3.fromHSV((time * 0.08) % 1, 0.8, 1)
		halo.BackgroundColor3 = hueColor
		halo.BackgroundTransparency = 0.78 + math.sin(time * 3) * 0.06

		-- Facettes (10 fois par seconde suffit)
		tileClock += dt
		if tileClock >= 0.1 then
			tileClock = 0
			rotationStep += 1
			local flash = random:NextInteger(1, math.max(1, #tiles))
			for index, tile in ipairs(tiles) do
				local column = ((tile.I + rotationStep) % PATTERN_W) + 1
				local value = pattern[column][tile.J + 1] * tile.Shade
				local grey = Color3.new(math.min(1, value), math.min(1, value), math.min(1, value * 1.04))
				if index == flash then
					tile.Frame.BackgroundColor3 = Color3.new(1, 1, 1)
				else
					-- Reflets colorés des faisceaux
					tile.Frame.BackgroundColor3 = grey:Lerp(hueColor, (column % 4 == 0) and 0.45 or 0.12)
				end
			end
		end

		-- Étincelles
		if effectsOn() then
			sparkleClock += dt
			if sparkleClock >= 0.35 then
				sparkleClock = 0
				spawnSparkle()
			end
		end
	end)
end

return Disco
