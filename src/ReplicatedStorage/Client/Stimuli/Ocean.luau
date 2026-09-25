--[[
	Ocean (ModuleScript - cinématique, PAS une Feature)
	Emplacement : ReplicatedStorage > Client > Stimuli > Ocean

	Cinématique "Aller à l'océan" (détox / rebirth), jouée par le
	StimulusManager sur Notify { Type = "Detox" } :
	  Ocean.Play(ctx) remplit ctx.Container (plein écran, calque Cinematic)
	  et BLOQUE ~6 s, puis rend la main (le manager détruit le cadre).
	Au programme : ciel de fin de journée, soleil et son halo, nuages qui
	dérivent, 4 couches de vagues qui ondulent, reflets qui scintillent,
	deux mouettes, puis les textes "Respire..." (avec un cercle de
	respiration), "Tout est calme." et "Rebirth x<mult>".
]]

local Ocean = {}
Ocean.Slot = "Cinematic" -- pour la documentation : plein écran, calque Cinematic

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local HORIZON = 0.58

local WAVE_LAYERS = {
	{ Top = HORIZON, Color = Color3.fromRGB(120, 196, 228), Humps = 14, Speed = 0.5, Amp = 0.02 },
	{ Top = HORIZON + 0.09, Color = Color3.fromRGB(78, 164, 216), Humps = 12, Speed = 0.65, Amp = 0.025 },
	{ Top = HORIZON + 0.19, Color = Color3.fromRGB(44, 128, 198), Humps = 10, Speed = 0.8, Amp = 0.03 },
	{ Top = HORIZON + 0.3, Color = Color3.fromRGB(22, 96, 170), Humps = 8, Speed = 1, Amp = 0.035 },
}

function Ocean.Play(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()
	local white = Color3.new(1, 1, 1)

	-- Données du rebirth (payload du Notify "Detox")
	local payload = type(ctx.Payload) == "table" and ctx.Payload or {}
	local multiplier = tonumber(ctx.Multiplier) or tonumber(payload.Multiplier)
	if not multiplier then
		local data = ctx.State.Data
		multiplier = (data and tonumber(data.RebirthMultiplier)) or 1
	end
	local rebirths = tonumber(ctx.Rebirths) or tonumber(payload.Rebirths) or 0

	-- Attend `seconds` ; faux si la cinématique a été coupée
	local function waitAlive(seconds: number): boolean
		local finish = os.clock() + seconds
		while os.clock() < finish do
			if not ctx.IsAlive() or not container.Parent then
				return false
			end
			task.wait()
		end
		return ctx.IsAlive() and container.Parent ~= nil
	end

	------------------------------------------------------------------
	-- Groupe (fondu de toute la scène d'un coup)
	------------------------------------------------------------------
	local scene = Create("CanvasGroup", {
		Name = "Scene",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = white,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 1,
		Parent = container,
	})

	-- Ciel
	local sky = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = scene,
	})
	UIUtil.Gradient(sky, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(116, 176, 236)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(190, 208, 240)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(255, 212, 178)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 236, 210)),
	}), 90)

	-- Soleil + halos
	local sunHolder = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, HORIZON, -10),
		Size = UDim2.fromOffset(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = scene,
	})
	for _, info in ipairs({ { 400, 0.88 }, { 260, 0.75 }, { 150, 0 } }) do
		local size, transparency = info[1], info[2]
		local disc = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = transparency == 0 and Color3.fromRGB(255, 244, 214) or Color3.fromRGB(255, 214, 160),
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = sunHolder,
		})
		UIUtil.Corner(disc, UDim.new(1, 0))
	end

	-- Nuages (3 bulles chacun)
	local clouds = {}
	for index = 1, 3 do
		local cloud = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.15 + (index - 1) * 0.33 + random:NextNumber(-0.05, 0.05), 0.12 + random:NextNumber(0, 0.16)),
			Size = UDim2.fromOffset(150, 40),
			BackgroundColor3 = white,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = scene,
		})
		UIUtil.Corner(cloud, UDim.new(1, 0))
		for _, puff in ipairs({ { 0.35, 56 }, { 0.62, 44 } }) do
			local bubble = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(puff[1], 0.2),
				Size = UDim2.fromOffset(puff[2], puff[2]),
				BackgroundColor3 = white,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = cloud,
			})
			UIUtil.Corner(bubble, UDim.new(1, 0))
		end
		table.insert(clouds, { Frame = cloud, Speed = random:NextNumber(0.006, 0.014) })
	end

	-- Mouettes (deux ailes qui battent)
	local gulls = {}
	for index = 1, 2 do
		local holder = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(-0.05 - (index - 1) * 0.08, 0.22 + (index - 1) * 0.07),
			Size = UDim2.fromOffset(34, 16),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = scene,
		})
		local wings = {}
		for side = -1, 1, 2 do
			local wing = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, side * 7, 0.5, 0),
				Size = UDim2.fromOffset(17, 3),
				BackgroundColor3 = Color3.fromRGB(60, 64, 80),
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = holder,
			})
			UIUtil.Corner(wing, UDim.new(1, 0))
			table.insert(wings, { Frame = wing, Side = side })
		end
		table.insert(gulls, {
			Frame = holder,
			Wings = wings,
			Phase = random:NextNumber(0, math.pi * 2),
			Speed = random:NextNumber(0.13, 0.18),
			X = holder.Position.X.Scale,
			Y = holder.Position.Y.Scale,
		})
	end

	------------------------------------------------------------------
	-- Mer : couches de vagues (bosses arrondies + corps)
	------------------------------------------------------------------
	local layers = {}
	for index, def in ipairs(WAVE_LAYERS) do
		local layer = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, def.Top),
			Size = UDim2.fromScale(1.3, 1 - def.Top + 0.08),
			BackgroundTransparency = 1,
			ZIndex = 4 + index,
			Parent = scene,
		})
		Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = def.Color,
			BorderSizePixel = 0,
			ZIndex = 4 + index,
			Parent = layer,
		})
		for hump = 1, def.Humps do
			local bump = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((hump - 0.5) / def.Humps, 0),
				Size = UDim2.fromScale(1.4 / def.Humps, 1),
				BackgroundColor3 = def.Color,
				BorderSizePixel = 0,
				ZIndex = 4 + index,
				Parent = layer,
			})
			Create("UIAspectRatioConstraint", {
				AspectRatio = 3,
				DominantAxis = Enum.DominantAxis.Width,
				Parent = bump,
			})
			UIUtil.Corner(bump, UDim.new(1, 0))
		end
		table.insert(layers, { Frame = layer, Def = def, Phase = random:NextNumber(0, math.pi * 2) })
	end

	-- Reflets du soleil sur l'eau
	local glints = {}
	for _ = 1, 12 do
		local glint = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + random:NextNumber(-0.18, 0.18), HORIZON + random:NextNumber(0.03, 0.35)),
			Size = UDim2.fromOffset(random:NextInteger(24, 70), 3),
			BackgroundColor3 = Color3.fromRGB(255, 246, 220),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 10,
			Parent = scene,
		})
		UIUtil.Corner(glint, UDim.new(1, 0))
		table.insert(glints, { Frame = glint, Phase = random:NextNumber(0, math.pi * 2), Speed = random:NextNumber(1.5, 3.5) })
	end

	------------------------------------------------------------------
	-- Textes + cercle de respiration
	------------------------------------------------------------------
	local textY = 0.32
	local ring = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, textY),
		Size = UDim2.fromOffset(170, 170),
		BackgroundColor3 = white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = scene,
	})
	UIUtil.Corner(ring, UDim.new(1, 0))
	local ringStroke = UIUtil.Stroke(ring, white, 3, 1)
	local ringScale = Create("UIScale", { Scale = 0.6, Parent = ring })

	local mainText = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = white,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, textY),
		Size = UDim2.new(0.8, 0, 0, 84),
		MaxTextSize = 64,
		TextTransparency = 1,
		ZIndex = 12,
		Parent = scene,
	})
	local mainStroke = UIUtil.Stroke(mainText, Color3.fromRGB(30, 70, 120), 2, 1)
	mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local mainScale = Create("UIScale", { Parent = mainText })

	local subText = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Body,
		TextColor3 = white,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, textY, 62),
		Size = UDim2.new(0.8, 0, 0, 32),
		MaxTextSize = 26,
		TextTransparency = 1,
		ZIndex = 12,
		Parent = scene,
	})
	local subStroke = UIUtil.Stroke(subText, Color3.fromRGB(30, 70, 120), 1.5, 1)
	subStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local function showText(label: TextLabel, stroke: UIStroke, text: string, duration: number)
		label.Text = text
		UIUtil.Tween(label, duration, { TextTransparency = 0 }, Enum.EasingStyle.Sine)
		UIUtil.Tween(stroke, duration, { Transparency = 0.35 }, Enum.EasingStyle.Sine)
	end

	local function hideText(label: TextLabel, stroke: UIStroke, duration: number)
		UIUtil.Tween(label, duration, { TextTransparency = 1 }, Enum.EasingStyle.Sine)
		UIUtil.Tween(stroke, duration, { Transparency = 1 }, Enum.EasingStyle.Sine)
	end

	------------------------------------------------------------------
	-- Animation continue (vagues, reflets, nuages, mouettes)
	------------------------------------------------------------------
	local time = 0
	ctx.OnRender(function(dt: number)
		time += dt
		for _, layer in ipairs(layers) do
			local def = layer.Def
			local x = 0.5 + math.sin(time * def.Speed + layer.Phase) * def.Amp
			local y = def.Top + math.sin(time * def.Speed * 1.4 + layer.Phase) * 0.006
			layer.Frame.Position = UDim2.fromScale(x, y)
		end
		for _, glint in ipairs(glints) do
			glint.Frame.BackgroundTransparency = 0.35 + (math.sin(time * glint.Speed + glint.Phase) + 1) * 0.32
		end
		for _, cloud in ipairs(clouds) do
			local position = cloud.Frame.Position
			cloud.Frame.Position = UDim2.fromScale(position.X.Scale + cloud.Speed * dt, position.Y.Scale)
		end
		for _, gull in ipairs(gulls) do
			gull.X += gull.Speed * dt
			local bob = math.sin(time * 1.3 + gull.Phase) * 0.012
			gull.Frame.Position = UDim2.fromScale(gull.X, gull.Y + bob)
			local flap = 18 + math.sin(time * 7 + gull.Phase) * 16
			for _, wing in ipairs(gull.Wings) do
				-- Aile gauche : bout intérieur plus bas (rotation positive), et inversement
				wing.Frame.Rotation = -wing.Side * flap
			end
		end
	end)

	------------------------------------------------------------------
	-- Déroulé (~6 s)
	------------------------------------------------------------------
	ctx.Sound.Play("Detox", 1)
	UIUtil.Tween(scene, 1, { GroupTransparency = 0 }, Enum.EasingStyle.Sine)
	UIUtil.Tween(sunHolder, 6, { Position = UDim2.new(0.5, 0, HORIZON, -40) }, Enum.EasingStyle.Sine)
	if not waitAlive(0.8) then
		return
	end

	-- "Respire..." + cercle qui gonfle (inspiration)
	showText(mainText, mainStroke, Locale.T("Breathe..."), 0.6)
	UIUtil.Tween(ringStroke, 0.5, { Transparency = 0.4 })
	UIUtil.Tween(ringScale, 1.6, { Scale = 1.25 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if not waitAlive(1.6) then
		return
	end
	hideText(mainText, mainStroke, 0.4)
	UIUtil.Tween(ringScale, 0.6, { Scale = 0.8 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	UIUtil.Tween(ringStroke, 0.6, { Transparency = 1 })
	if not waitAlive(0.4) then
		return
	end

	-- "Tout est calme."
	showText(mainText, mainStroke, Locale.T("All is calm."), 0.5)
	if not waitAlive(1.2) then
		return
	end
	hideText(mainText, mainStroke, 0.3)
	if not waitAlive(0.3) then
		return
	end

	-- "Rebirth x<mult>"
	mainScale.Scale = 0.6
	mainText.TextColor3 = Color3.fromRGB(255, 244, 200)
	showText(mainText, mainStroke, Locale.T("Rebirth %s", ctx.Format.Multiplier(multiplier)), 0.35)
	UIUtil.Tween(mainScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	local visit = rebirths > 0 and Locale.T("Ocean visit #%s • ", tostring(rebirths)) or ""
	showText(subText, subStroke, visit .. Locale.T("your gains are multiplied forever 🌊"), 0.5)
	ctx.Sound.Play("Bonus", 0.8)
	if not waitAlive(1.3) then
		return
	end

	-- Retour au jeu
	UIUtil.Tween(scene, 0.8, { GroupTransparency = 1 }, Enum.EasingStyle.Sine)
	waitAlive(0.8)
end

return Ocean
