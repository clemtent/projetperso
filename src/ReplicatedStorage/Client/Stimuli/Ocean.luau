--[[
	Ocean (ModuleScript - cinématique, PAS une Feature)
	Emplacement : ReplicatedStorage > Client > Stimuli > Ocean

	Cinématique "Aller à l'océan" (détox / rebirth), jouée par le
	StimulusManager sur Notify { Type = "Detox" } :
	  Ocean.Play(ctx) remplit ctx.Container (plein écran, calque Cinematic)
	  et BLOQUE ~8,8 s (le manager coupe tout à 10 s), puis rend la main (le
	  manager détruit le cadre).

	v9 :
	  1. LA MARÉE MONTE : une vague (crête d'écume, embruns) monte du bas de
	     l'écran et recouvre toute l'interface en 0,45 s. La remise à zéro
	     du jeu (état envoyé juste après le Notify) se fait derrière elle.
	  2. Elle redescend et découvre, de haut en bas, un coucher de soleil
	     sur la plage : ciel dégradé, étoiles qui s'allument, soleil qui se
	     couche derrière la mer (halos, lueur de l'horizon), nuages roses
	     éclairés par dessous, voilier, mouettes, 4 couches de vagues avec
	     écume, reflets dorés du soleil sur l'eau, sable mouillé.
	  3. RESPIRATION : "Inspire..." (le cercle gonfle, la vague monte sur le
	     sable) puis "Expire..." (le cercle dégonfle, la vague redescend),
	     puis "Tout est calme."
	  4. RÉVÉLATION : flash, rayons dorés qui tournent, halo, pastille
	     "RENAISSANCE n°N", le multiplicateur qui compte de l'ancien au
	     nouveau ("x2 -> x2,5") puis rebondit, étincelles en gerbe, braises
	     qui montent ; texte "Tes gains sont multipliés pour toujours".
	  5. LA MARÉE REPART : une dernière vague recouvre la plage puis se
	     retire vers le bas et découvre l'interface toute neuve ; elle laisse
	     de l'écume qui éclate, et un reflet "propre" balaie l'écran.
	Sons inchangés : "Detox" au départ, "Bonus" à la révélation.
	Tout le décor déborde du cadre (EXTEND) pour couvrir aussi l'encoche et
	la barre du haut. Une seule boucle ctx.OnRender anime tout ; rien n'est
	créé après le départ.
]]

local Ocean = {}
Ocean.Slot = "Cinematic" -- pour la documentation : plein écran, calque Cinematic

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local EXTEND = 140 -- débord du décor autour du cadre (encoche, barre du haut)
local HORIZON = 0.56
local BEACH_Y = 0.87 -- haut du sable
local TEXT_Y = 0.35 -- centre des textes
local TIDE_RISE = 0.36
local TIDE_DRAIN = 0.72
local CREST = 46 -- hauteur de la crête d'écume au-dessus de l'eau

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(34, 26, 72) -- contour des textes

local WAVE_LAYERS = {
	{ Top = HORIZON, Color = Color3.fromRGB(164, 128, 196), Humps = 16, Speed = 0.45, Amp = 0.012, Foam = false },
	{ Top = HORIZON + 0.07, Color = Color3.fromRGB(104, 112, 196), Humps = 13, Speed = 0.6, Amp = 0.018, Foam = false },
	{ Top = HORIZON + 0.15, Color = Color3.fromRGB(56, 92, 176), Humps = 11, Speed = 0.75, Amp = 0.024, Foam = true },
	{ Top = HORIZON + 0.23, Color = Color3.fromRGB(30, 70, 150), Humps = 9, Speed = 0.9, Amp = 0.03, Foam = true },
}

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeInOutSine(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

local function easeOutBack(t: number): number
	local c = 1.7
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

function Ocean.Play(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()

	-- Données du rebirth (payload du Notify "Detox")
	local payload = type(ctx.Payload) == "table" and ctx.Payload or {}
	local multiplier = tonumber(ctx.Multiplier) or tonumber(payload.Multiplier)
	if not multiplier then
		local data = ctx.State.Data
		multiplier = (data and tonumber(data.RebirthMultiplier)) or 1
	end
	local rebirths = tonumber(ctx.Rebirths) or tonumber(payload.Rebirths) or 0
	-- Multiplicateur d'avant (pour le compteur qui monte)
	local previous = 1
	if rebirths > 1 and ctx.Formulas and type(ctx.Formulas.GetRebirthMultiplier) == "function" then
		local ok, value = pcall(ctx.Formulas.GetRebirthMultiplier, rebirths - 1)
		if ok and type(value) == "number" and value < multiplier then
			previous = value
		end
	end
	previous = math.min(previous, multiplier)

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

	local function frame(props: { [string]: any }): Frame
		props.BorderSizePixel = 0
		return Create("Frame", props)
	end

	local function round(guiObject: GuiObject)
		UIUtil.Corner(guiObject, UDim.new(1, 0))
	end

	local function vertical(guiObject: GuiObject, keypoints: { ColorSequenceKeypoint }): UIGradient
		return Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(keypoints), Parent = guiObject })
	end

	------------------------------------------------------------------
	-- Scène (cadre = zone sûre ; les éléments plein écran débordent)
	------------------------------------------------------------------
	local scene = frame({
		Name = "Scene",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 1,
		Parent = container,
	})

	-- Ciel : nuit en haut -> violet -> rose -> or à l'horizon
	local sky = frame({
		Name = "Sky",
		Position = UDim2.fromOffset(-EXTEND, -EXTEND),
		Size = UDim2.new(1, EXTEND * 2, HORIZON, EXTEND + 12),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = scene,
	})
	vertical(sky, {
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 30, 84)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(84, 62, 148)),
		ColorSequenceKeypoint.new(0.58, Color3.fromRGB(214, 104, 150)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(255, 150, 112)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 208, 140)),
	})

	-- Étoiles (s'allument peu à peu)
	local stars = {}
	for _ = 1, 20 do
		local size = random:NextNumber(2, 4)
		local star = frame({
			Name = "Star",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(random:NextNumber(0.02, 0.98), 0, random:NextNumber(0, 0.26), -random:NextNumber(0, EXTEND * 0.8)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(255, 250, 230),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = scene,
		})
		round(star)
		table.insert(stars, { Frame = star, Phase = random:NextNumber(0, math.pi * 2), Speed = random:NextNumber(1.5, 3.5), Delay = random:NextNumber(0, 1) })
	end

	-- Soleil (se couche derrière la mer) + halos
	local sunStart = HORIZON - 0.19
	local sunEnd = HORIZON + 0.035
	local sunHolder = frame({
		Name = "Sun",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, sunStart),
		Size = UDim2.fromOffset(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = scene,
	})
	local halos = {}
	for _, info in ipairs({ { 520, 0.9 }, { 330, 0.8 }, { 210, 0.62 } }) do
		local halo = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(info[1], info[1]),
			BackgroundColor3 = Color3.fromRGB(255, 196, 140),
			BackgroundTransparency = info[2],
			ZIndex = 3,
			Parent = sunHolder,
		})
		round(halo)
		table.insert(halos, { Frame = halo, Base = info[2] })
	end
	local sunDisc = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(130, 130),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
		Parent = sunHolder,
	})
	round(sunDisc)
	vertical(sunDisc, {
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 214)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 208, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 90)),
	})

	-- Lueur de l'horizon
	local horizonGlow = frame({
		Name = "HorizonGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, HORIZON),
		Size = UDim2.new(1, EXTEND * 2, 0, 70),
		BackgroundColor3 = Color3.fromRGB(255, 226, 170),
		BackgroundTransparency = 0.35,
		ZIndex = 5,
		Parent = scene,
	})
	Create("UIGradient", {
		Color = ColorSequence.new(WHITE),
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = horizonGlow,
	})

	-- Nuages roses (éclairés par dessous)
	local clouds = {}
	local cloudDefs = { { 0.14, 0.14, 250, 30 }, { 0.47, 0.07, 190, 24 }, { 0.8, 0.18, 230, 28 }, { 0.3, 0.3, 170, 20 } }
	for _, def in ipairs(cloudDefs) do
		local cloud = frame({
			Name = "Cloud",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(def[1], def[2]),
			Size = UDim2.fromOffset(def[3], def[4]),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.12,
			ZIndex = 6,
			Parent = scene,
		})
		round(cloud)
		local colors = {
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 108, 176)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(236, 140, 170)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 196, 150)),
		}
		vertical(cloud, colors)
		for _, puff in ipairs({ { 0.34, 1.5 }, { 0.62, 1.15 } }) do
			local size = def[4] * puff[2]
			local bubble = frame({
				AnchorPoint = Vector2.new(0.5, 0.7),
				Position = UDim2.fromScale(puff[1], 0.4),
				Size = UDim2.fromOffset(size * 1.3, size),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.12,
				ZIndex = 6,
				Parent = cloud,
			})
			round(bubble)
			vertical(bubble, colors)
		end
		table.insert(clouds, { Frame = cloud, X = def[1], Y = def[2], Speed = random:NextNumber(0.004, 0.009) })
	end

	-- Mouettes (deux ailes qui battent)
	local gulls = {}
	for index = 1, 3 do
		local holder = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromOffset(34, 16),
			BackgroundTransparency = 1,
			ZIndex = 7,
			Parent = scene,
		})
		local wings = {}
		for side = -1, 1, 2 do
			local wing = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, side * 7, 0.5, 0),
				Size = UDim2.fromOffset(16, 3),
				BackgroundColor3 = Color3.fromRGB(58, 40, 86),
				ZIndex = 7,
				Parent = holder,
			})
			round(wing)
			table.insert(wings, { Frame = wing, Side = side })
		end
		table.insert(gulls, {
			Frame = holder,
			Wings = wings,
			Phase = random:NextNumber(0, math.pi * 2),
			Speed = random:NextNumber(0.045, 0.07),
			X = -0.04 - index * 0.09,
			Y = 0.16 + index * 0.055,
		})
	end

	------------------------------------------------------------------
	-- Mer : couches de vagues (bosses arrondies + corps + écume)
	------------------------------------------------------------------
	local layers = {}
	for index, def in ipairs(WAVE_LAYERS) do
		local z = index == 1 and 8 or 8 + index -- (le voilier est entre la 1re et la 2e couche)
		local layer = frame({
			Name = "Wave",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, def.Top),
			Size = UDim2.new(1.3, EXTEND * 2, 1 - def.Top, EXTEND + 30),
			BackgroundTransparency = 1,
			ZIndex = z,
			Parent = scene,
		})
		local body = frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = def.Color,
			ZIndex = z,
			Parent = layer,
		})
		vertical(body, {
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(210, 210, 230)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 190)),
		})
		for hump = 1, def.Humps do
			local bump = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((hump - 0.5) / def.Humps, 0),
				Size = UDim2.fromScale(1.12 / def.Humps, 1),
				BackgroundColor3 = def.Color,
				ZIndex = z,
				Parent = layer,
			})
			Create("UIAspectRatioConstraint", {
				AspectRatio = 3.4,
				DominantAxis = Enum.DominantAxis.Width,
				Parent = bump,
			})
			round(bump)
		end
		if def.Foam then
			-- Petits traits d'écume sur la crête
			for foamIndex = 1, 7 do
				local foam = frame({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(foamIndex / 8 + random:NextNumber(-0.03, 0.03), 0, 0, random:NextNumber(-6, 4)),
					Size = UDim2.fromOffset(random:NextInteger(40, 90), 3),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.45,
					ZIndex = z,
					Parent = layer,
				})
				round(foam)
			end
		end
		table.insert(layers, { Frame = layer, Def = def, Phase = random:NextNumber(0, math.pi * 2) })
	end

	-- Voilier sur l'horizon (silhouette)
	local boat = frame({
		Name = "Boat",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.74, 0, HORIZON, 3),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = scene,
	})
	local hull = frame({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(28, 5),
		BackgroundColor3 = Color3.fromRGB(56, 36, 80),
		ZIndex = 9,
		Parent = boat,
	})
	UIUtil.Corner(hull, 3)
	local sail = frame({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 1, 1, -6),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Color3.fromRGB(70, 46, 96),
		ZIndex = 9,
		Parent = boat,
	})
	-- Voile triangulaire : moitié d'un carré (dégradé à bord net)
	Create("UIGradient", {
		Color = ColorSequence.new(WHITE),
		Rotation = 45,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.495, 0),
			NumberSequenceKeypoint.new(0.505, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = sail,
	})
	frame({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.fromOffset(2, 24),
		BackgroundColor3 = Color3.fromRGB(56, 36, 80),
		ZIndex = 9,
		Parent = boat,
	})

	-- Reflets dorés du soleil sur l'eau (chemin de lumière)
	local glints = {}
	for index = 1, 12 do
		local depth = index / 12
		local glint = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5 + random:NextNumber(-0.04, 0.04) * (0.4 + depth), 0, HORIZON + 0.015 + depth * (BEACH_Y - HORIZON - 0.05), 0),
			Size = UDim2.fromOffset(math.floor(18 + depth * 60 * random:NextNumber(0.6, 1.2)), 3),
			BackgroundColor3 = Color3.fromRGB(255, 226, 150),
			BackgroundTransparency = 1,
			ZIndex = 13,
			Parent = scene,
		})
		round(glint)
		table.insert(glints, { Frame = glint, Phase = random:NextNumber(0, math.pi * 2), Speed = random:NextNumber(1.5, 3.2) })
	end

	------------------------------------------------------------------
	-- Plage : sable, sable mouillé, nappe d'eau qui monte et descend
	------------------------------------------------------------------
	local sand = frame({
		Name = "Sand",
		Position = UDim2.new(0, -EXTEND, BEACH_Y, 0),
		Size = UDim2.new(1, EXTEND * 2, 1 - BEACH_Y, EXTEND),
		BackgroundColor3 = WHITE,
		ZIndex = 14,
		Parent = scene,
	})
	vertical(sand, {
		ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 170, 136)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(240, 196, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(226, 172, 124)),
	})
	-- Nappe (translucide) + ligne d'écume à son bord
	local swash = frame({
		Name = "Swash",
		Position = UDim2.new(0, -EXTEND, BEACH_Y, -4),
		Size = UDim2.new(1, EXTEND * 2, 0, 30),
		BackgroundColor3 = Color3.fromRGB(96, 206, 226),
		BackgroundTransparency = 0.25,
		ZIndex = 15,
		Parent = scene,
	})
	Create("UIGradient", {
		Color = ColorSequence.new(WHITE),
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.8, 0.45),
			NumberSequenceKeypoint.new(1, 0.7),
		}),
		Parent = swash,
	})
	local swashFoam = frame({
		Name = "SwashFoam",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.1,
		ZIndex = 16,
		Parent = swash,
	})
	round(swashFoam)
	for dot = 1, 14 do
		local size = random:NextInteger(5, 11)
		local bubble = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(dot / 15 + random:NextNumber(-0.02, 0.02), 0, 1, random:NextNumber(-3, 2)),
			Size = UDim2.fromOffset(size, size * 0.7),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.2,
			ZIndex = 16,
			Parent = swash,
		})
		round(bubble)
	end
	local swashHeight = 30 -- hauteur de la nappe (animée : respiration)

	------------------------------------------------------------------
	-- Respiration (cercle) + textes
	------------------------------------------------------------------
	local ring = frame({
		Name = "Breath",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, TEXT_Y),
		Size = UDim2.fromOffset(190, 190),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = scene,
	})
	round(ring)
	local ringStroke = UIUtil.Stroke(ring, WHITE, 3, 1)
	local ringScale = Create("UIScale", { Scale = 0.6, Parent = ring })
	local ringInner = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = ring,
	})
	round(ringInner)

	local function label(props: { [string]: any }): (TextLabel, UIStroke)
		local thickness = props.StrokeThickness or 2
		props.StrokeThickness = nil
		local text = UIUtil.Label(props)
		local stroke = UIUtil.Stroke(text, INK, thickness, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		return text, stroke
	end

	local mainText, mainStroke = label({
		Name = "MainText",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, TEXT_Y),
		Size = UDim2.new(0.8, 0, 0, 70),
		MaxTextSize = 56,
		TextTransparency = 1,
		ZIndex = 22,
		Parent = scene,
	})

	local function showText(textLabel: TextLabel, stroke: UIStroke, text: string, duration: number)
		textLabel.Text = text
		UIUtil.Tween(textLabel, duration, { TextTransparency = 0 }, Enum.EasingStyle.Sine)
		UIUtil.Tween(stroke, duration, { Transparency = 0.3 }, Enum.EasingStyle.Sine)
	end

	local function hideText(textLabel: TextLabel, stroke: UIStroke, duration: number)
		UIUtil.Tween(textLabel, duration, { TextTransparency = 1 }, Enum.EasingStyle.Sine)
		UIUtil.Tween(stroke, duration, { Transparency = 1 }, Enum.EasingStyle.Sine)
	end

	------------------------------------------------------------------
	-- Révélation : rayons, halo, pastille, multiplicateur, sous-titre
	------------------------------------------------------------------
	local reveal = frame({
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, TEXT_Y),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 24,
		Parent = scene,
	})
	local rays = frame({
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 640),
		BackgroundTransparency = 1,
		ZIndex = 24,
		Parent = reveal,
	})
	local rayBars = {}
	for index = 1, 10 do
		local bar = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, index % 2 == 0 and 30 or 18, 1, 0),
			Rotation = (index - 1) * 18,
			BackgroundColor3 = Color3.fromRGB(255, 226, 140),
			BackgroundTransparency = 0.5,
			ZIndex = 24,
			Parent = rays,
		})
		Create("UIGradient", {
			Color = ColorSequence.new(WHITE),
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = bar,
		})
		table.insert(rayBars, bar)
	end
	local raysScale = Create("UIScale", { Scale = 0.2, Parent = rays })
	local glow = frame({
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 300),
		BackgroundColor3 = Color3.fromRGB(255, 240, 200),
		BackgroundTransparency = 0.72,
		ZIndex = 25,
		Parent = reveal,
	})
	round(glow)
	local glowScale = Create("UIScale", { Scale = 0.3, Parent = glow })

	local badge = frame({
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -92),
		Size = UDim2.fromOffset(250, 40),
		BackgroundColor3 = WHITE,
		ZIndex = 27,
		Parent = reveal,
	})
	round(badge)
	UIUtil.Gradient(badge, ColorSequence.new(Color3.fromRGB(255, 236, 150), Color3.fromRGB(255, 176, 60)), 90)
	UIUtil.Stroke(badge, WHITE, 2.5, 0)
	local badgeScale = Create("UIScale", { Scale = 0.2, Parent = badge })
	UIUtil.Label({
		Name = "BadgeText",
		Text = Locale.T("REBIRTH #%s", tostring(math.max(1, math.floor(rebirths + 0.5)))),
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(80, 40, 20),
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 1, -8),
		MaxTextSize = 26,
		ZIndex = 28,
		Parent = badge,
	})

	local multText, multStroke = label({
		Name = "Multiplier",
		Text = ctx.Format.Multiplier(previous),
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 8),
		Size = UDim2.fromOffset(520, 120),
		MaxTextSize = 108,
		ZIndex = 27,
		StrokeThickness = 5,
		Parent = reveal,
	})
	multText.TextTransparency = 0
	multStroke.Transparency = 0.05
	UIUtil.Gradient(multText, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 252, 220)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 216, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 40)),
	}), 90)
	local multScale = Create("UIScale", { Scale = 0.3, Parent = multText })

	local subText, subStroke = label({
		Name = "SubText",
		Text = Locale.T("Your gains are multiplied forever 🌊"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 92),
		Size = UDim2.fromOffset(640, 36),
		MaxTextSize = 30,
		TextTransparency = 1,
		ZIndex = 27,
		Parent = reveal,
	})

	-- Étincelles (gerbe à la révélation, puis braises qui montent ; réserve)
	local SPARKS = 18
	local sparks = {}
	for index = 1, SPARKS do
		local spark = UIUtil.Label({
			Name = "Spark",
			Text = index % 3 == 0 and "✨" or "•",
			TextColor3 = index % 2 == 0 and Color3.fromRGB(255, 226, 120) or WHITE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
			MaxTextSize = 26,
			TextTransparency = 1,
			Visible = false,
			ZIndex = 29,
			Parent = scene,
		})
		sparks[index] = { Label = spark, Age = 1, Life = 1, X = 0, Y = 0, VX = 0, VY = 0, Spin = 0 }
	end
	local nextSpark = 1

	local function emitSpark(x: number, y: number, vx: number, vy: number, life: number)
		local spark = sparks[nextSpark]
		nextSpark = nextSpark % SPARKS + 1
		spark.Age = 0
		spark.Life = life
		spark.X, spark.Y, spark.VX, spark.VY = x, y, vx, vy
		spark.Spin = random:NextNumber(-200, 200)
		spark.Label.Visible = true
	end

	-- Flash blanc de la révélation
	local flash = frame({
		Name = "Flash",
		Position = UDim2.fromOffset(-EXTEND, -EXTEND),
		Size = UDim2.new(1, EXTEND * 2, 1, EXTEND * 2),
		BackgroundColor3 = Color3.fromRGB(255, 248, 230),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = scene,
	})

	------------------------------------------------------------------
	-- Écume laissée sur l'interface quand la marée repart (éclate)
	------------------------------------------------------------------
	local FOAM_COUNT = 26
	local foams = {}
	for _ = 1, FOAM_COUNT do
		local size = random:NextInteger(9, 26)
		local foam = frame({
			Name = "Foam",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0.03, 0.97), random:NextNumber(0.04, 0.96)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(214, 244, 255),
			BackgroundTransparency = 0.45,
			Visible = false,
			ZIndex = 2,
			Parent = container,
		})
		round(foam)
		local stroke = UIUtil.Stroke(foam, Color3.fromRGB(96, 186, 232), 1.5, 0.2)
		local foamShine = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.34, 0.32),
			Size = UDim2.fromScale(0.34, 0.24),
			Rotation = -35,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.1,
			ZIndex = 2,
			Parent = foam,
		})
		round(foamShine)
		table.insert(foams, {
			Frame = foam,
			Stroke = stroke,
			Scale = Create("UIScale", { Parent = foam }),
			Y = foam.Position.Y.Scale,
			State = "Hidden", -- Hidden -> Shown -> Popping -> Done
			PopAt = 0,
			Age = 0,
		})
	end

	-- Reflet "tout propre" qui balaie l'écran à la fin
	local shine = frame({
		Name = "CleanShine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.2, 0.5),
		Size = UDim2.new(0, 90, 1.6, 0),
		Rotation = 18,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		Visible = false,
		ZIndex = 2,
		Parent = container,
	})
	Create("UIGradient", {
		Color = ColorSequence.new(WHITE),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = shine,
	})

	------------------------------------------------------------------
	-- La marée (vague plein écran, crête d'écume en haut)
	------------------------------------------------------------------
	local tide = frame({
		Name = "Tide",
		Position = UDim2.new(0, -EXTEND, 1, EXTEND + CREST),
		Size = UDim2.new(1, EXTEND * 2, 1, EXTEND * 2 + CREST * 2),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = container,
	})
	vertical(tide, {
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 226, 236)),
		ColorSequenceKeypoint.new(0.08, Color3.fromRGB(40, 176, 210)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(20, 110, 180)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 56, 130)),
	})
	-- Reflets obliques dans l'eau
	for index = 1, 5 do
		local streak = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(index / 6, 0.3 + (index % 3) * 0.15),
			Size = UDim2.fromOffset(random:NextInteger(120, 260), 5),
			Rotation = -8,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.8,
			ZIndex = 3,
			Parent = tide,
		})
		round(streak)
	end
	-- Crête : bande d'écume, bosses arrondies, embruns
	local crestBand = frame({
		Name = "Crest",
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.05,
		ZIndex = 4,
		Parent = tide,
	})
	crestBand.Position = UDim2.fromOffset(0, 0)
	-- Deux rangées de bouillons d'écume (grands et clairs derrière, petits devant)
	for rowIndex, rowDef in ipairs({ { Count = 18, Min = 60, Max = 96, Y = -6, T = 0.3 }, { Count = 30, Min = 26, Max = 54, Y = 6, T = 0.02 } }) do
		for index = 1, rowDef.Count do
			local size = random:NextInteger(rowDef.Min, rowDef.Max)
			local bump = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new((index - 0.5) / rowDef.Count, random:NextNumber(-10, 10), 0, rowDef.Y + random:NextNumber(-5, 5)),
				Size = UDim2.fromOffset(size, size * random:NextNumber(0.55, 0.75)),
				BackgroundColor3 = rowIndex == 1 and Color3.fromRGB(226, 248, 252) or WHITE,
				BackgroundTransparency = rowDef.T,
				ZIndex = 4,
				Parent = tide,
			})
			round(bump)
		end
	end
	for _ = 1, 30 do
		local size = random:NextInteger(5, 14)
		local spray = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(random:NextNumber(0, 1), 0, 0, -random:NextNumber(18, CREST + 10)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = random:NextNumber(0.1, 0.5),
			ZIndex = 4,
			Parent = tide,
		})
		round(spray)
	end

	local tidePhase = "Idle" -- Idle | Rise | Drain
	local tideT = 0
	local tideTop = 1.2 -- position du haut de la vague (0 = haut de l'écran, 1 = bas)
	local finalDrain = false

	local function setTide(top: number)
		tideTop = top
		-- top : 0 -> haut du débord, 1 -> bas du débord (en proportion + débords)
		tide.Position = UDim2.new(0, -EXTEND, top, (top * 2 - 1) * (EXTEND + CREST))
	end
	setTide(1)

	------------------------------------------------------------------
	-- Animation continue (une seule boucle)
	------------------------------------------------------------------
	local time = 0
	local sunProgress = 0 -- 0..1 : coucher du soleil
	local starLevel = 0 -- 0..1 : étoiles visibles
	local breath = 0 -- -1..1 : nappe de la plage (respiration)
	local breathTarget = 0
	local revealAge = -1
	local counting = -1
	local sparkClock = 0
	local shineAge = -1

	ctx.OnRender(function(dt: number)
		time += dt

		-- Marée
		if tidePhase == "Rise" then
			tideT = math.min(1, tideT + dt / TIDE_RISE)
			setTide(1 - easeOutCubic(tideT))
		elseif tidePhase == "Drain" then
			tideT = math.min(1, tideT + dt / TIDE_DRAIN)
			setTide(easeInOutSine(tideT) * 1.02)
			if tideT >= 1 then
				tidePhase = "Idle"
				tide.Visible = false
			end
		end

		-- Écume laissée derrière (fin) : apparaît quand l'eau la découvre, puis éclate
		if finalDrain then
			local height = container.AbsoluteSize.Y / math.max(0.01, ctx.Interface.Scale or 1)
			local edge = tideTop * height + (tideTop * 2 - 1) * (EXTEND + CREST) - CREST
			for _, foam in ipairs(foams) do
				if foam.State == "Hidden" then
					if edge > foam.Y * height + 10 then
						foam.State = "Shown"
						foam.Frame.Visible = true
						foam.PopAt = time + random:NextNumber(0.1, 0.5)
					end
				elseif foam.State == "Shown" then
					if time >= foam.PopAt then
						foam.State = "Popping"
						foam.Age = 0
					end
				elseif foam.State == "Popping" then
					foam.Age = math.min(1, foam.Age + dt / 0.2)
					foam.Scale.Scale = 1 + 0.7 * foam.Age
					foam.Frame.BackgroundTransparency = 0.45 + 0.55 * foam.Age
					foam.Stroke.Transparency = 0.2 + 0.8 * foam.Age
					if foam.Age >= 1 then
						foam.State = "Done"
						foam.Frame.Visible = false
					end
				end
			end
		end
		if shineAge >= 0 then
			shineAge += dt
			local p = math.min(1, shineAge / 0.65)
			shine.Visible = p < 1
			shine.Position = UDim2.fromScale(-0.15 + 1.3 * easeInOutSine(p), 0.5)
		end

		if not scene.Visible then
			return
		end

		-- Vagues (va-et-vient)
		for _, layer in ipairs(layers) do
			local def = layer.Def
			local x = 0.5 + math.sin(time * def.Speed + layer.Phase) * def.Amp
			local y = def.Top + math.sin(time * def.Speed * 1.4 + layer.Phase) * 0.005
			layer.Frame.Position = UDim2.fromScale(x, y)
		end
		-- Reflets dorés
		for _, glint in ipairs(glints) do
			glint.Frame.BackgroundTransparency = 0.2 + (math.sin(time * glint.Speed + glint.Phase) + 1) * 0.36
		end
		-- Nuages, soleil, étoiles
		for _, cloud in ipairs(clouds) do
			cloud.X += cloud.Speed * dt
			cloud.Frame.Position = UDim2.fromScale(cloud.X, cloud.Y)
		end
		sunProgress = math.min(1, sunProgress + dt / 8.5)
		sunHolder.Position = UDim2.fromScale(0.5, sunStart + (sunEnd - sunStart) * easeInOutSine(sunProgress))
		for index, halo in ipairs(halos) do
			halo.Frame.BackgroundTransparency = halo.Base + 0.03 * math.sin(time * 1.2 + index)
		end
		starLevel = math.min(1, starLevel + dt / 6)
		for _, star in ipairs(stars) do
			local level = math.clamp(starLevel * 1.6 - star.Delay * 0.6, 0, 1)
			star.Frame.BackgroundTransparency = 1 - level * (0.55 + 0.45 * (0.5 + 0.5 * math.sin(time * star.Speed + star.Phase)))
		end
		-- Mouettes
		for _, gull in ipairs(gulls) do
			gull.X += gull.Speed * dt
			local bob = math.sin(time * 1.3 + gull.Phase) * 0.01
			gull.Frame.Position = UDim2.fromScale(gull.X, gull.Y + bob)
			local flap = 16 + math.sin(time * 6 + gull.Phase) * 16
			for _, wing in ipairs(gull.Wings) do
				wing.Frame.Rotation = -wing.Side * flap
			end
		end
		-- Voilier qui dérive et tangue
		boat.Position = UDim2.new(0.74 - time * 0.004, 0, HORIZON, 3 + math.sin(time * 1.6) * 1.2)
		boat.Rotation = math.sin(time * 1.3) * 3
		-- Nappe d'eau sur le sable (suit la respiration)
		breath += (breathTarget - breath) * math.min(1, dt * 1.8)
		local height = 26 + breath * 22 + math.sin(time * 1.1) * 3
		if math.abs(height - swashHeight) > 0.2 then
			swashHeight = height
			swash.Size = UDim2.new(1, EXTEND * 2, 0, swashHeight)
		end

		-- Révélation : rayons qui tournent, halo qui pulse, compteur, étincelles
		if revealAge >= 0 then
			revealAge += dt
			rays.Rotation = time * 14
			glowScale.Scale = (0.3 + 0.7 * easeOutBack(math.min(1, revealAge / 0.5))) * (1 + 0.06 * math.sin(time * 3))
			if counting >= 0 then
				counting = math.min(1, counting + dt / 0.9)
				local value = previous + (multiplier - previous) * easeOutCubic(counting)
				multText.Text = ctx.Format.Multiplier(counting >= 1 and multiplier or value)
				if counting >= 1 then
					counting = -1
					multScale.Scale = 1.28
					UIUtil.Tween(multScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
					for _ = 1, 8 do
						local angle = random:NextNumber(0, math.pi * 2)
						local speed = random:NextNumber(260, 420)
						emitSpark(0.5, TEXT_Y, math.cos(angle) * speed, math.sin(angle) * speed - 60, random:NextNumber(0.7, 1))
					end
				end
			end
			-- Braises qui montent
			sparkClock += dt
			if sparkClock >= 0.14 then
				sparkClock = 0
				emitSpark(random:NextNumber(0.2, 0.8), TEXT_Y + random:NextNumber(0.12, 0.3), random:NextNumber(-20, 20), -random:NextNumber(60, 130), random:NextNumber(1.2, 1.8))
			end
		end
		-- Étincelles (position en échelle + vitesse en pixels)
		for _, spark in ipairs(sparks) do
			if spark.Age < 1 then
				spark.Age = math.min(1, spark.Age + dt / spark.Life)
				local t = spark.Age * spark.Life
				local drag = 1 - spark.Age * 0.5
				spark.Label.Position = UDim2.new(spark.X, spark.VX * t * drag, spark.Y, spark.VY * t * drag + 120 * t * t)
				spark.Label.Rotation = spark.Spin * t
				spark.Label.TextTransparency = spark.Age ^ 1.6
				if spark.Age >= 1 then
					spark.Label.Visible = false
				end
			end
		end
	end)

	------------------------------------------------------------------
	-- Déroulé (~8,8 s)
	------------------------------------------------------------------
	-- 1. La marée monte et recouvre l'interface
	ctx.Sound.Play("Detox", 1)
	tidePhase, tideT = "Rise", 0
	if not waitAlive(TIDE_RISE + 0.06) then
		return
	end
	-- 2. Derrière la vague : la plage au coucher du soleil ; la vague redescend
	scene.Visible = true
	tidePhase, tideT = "Drain", 0
	if not waitAlive(0.3) then
		return
	end

	-- 3. Respiration
	UIUtil.Tween(ringStroke, 0.5, { Transparency = 0.25 })
	UIUtil.Tween(ring, 0.5, { BackgroundTransparency = 0.9 })
	UIUtil.Tween(ringInner, 0.5, { BackgroundTransparency = 0.93 })
	showText(mainText, mainStroke, Locale.T("Breathe in..."), 0.5)
	breathTarget = 1
	UIUtil.Tween(ringScale, 1.6, { Scale = 1.22 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if not waitAlive(1.6) then
		return
	end
	mainText.Text = Locale.T("Breathe out...")
	breathTarget = -0.6
	UIUtil.Tween(ringScale, 1.4, { Scale = 0.7 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if not waitAlive(1.4) then
		return
	end

	-- "Tout est calme."
	UIUtil.Tween(ringStroke, 0.4, { Transparency = 1 })
	UIUtil.Tween(ring, 0.4, { BackgroundTransparency = 1 })
	UIUtil.Tween(ringInner, 0.4, { BackgroundTransparency = 1 })
	breathTarget = 0
	hideText(mainText, mainStroke, 0.25)
	if not waitAlive(0.25) then
		return
	end
	showText(mainText, mainStroke, Locale.T("All is calm."), 0.4)
	if not waitAlive(0.8) then
		return
	end
	hideText(mainText, mainStroke, 0.25)
	if not waitAlive(0.25) then
		return
	end

	-- 4. Révélation du nouveau multiplicateur
	flash.BackgroundTransparency = 0.25
	UIUtil.Tween(flash, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	reveal.Visible = true
	revealAge = 0
	UIUtil.Tween(raysScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
	UIUtil.Tween(badgeScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	multScale.Scale = 0.3
	UIUtil.Tween(multScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	for _ = 1, 10 do
		local angle = random:NextNumber(0, math.pi * 2)
		local speed = random:NextNumber(180, 380)
		emitSpark(0.5, TEXT_Y, math.cos(angle) * speed, math.sin(angle) * speed - 40, random:NextNumber(0.8, 1.2))
	end
	ctx.Sound.Play("Bonus", 0.8)
	if not waitAlive(0.35) then
		return
	end
	counting = 0
	UIUtil.Tween(subText, 0.5, { TextTransparency = 0 }, Enum.EasingStyle.Sine)
	UIUtil.Tween(subStroke, 0.5, { Transparency = 0.3 }, Enum.EasingStyle.Sine)
	if not waitAlive(1.5) then
		return
	end

	-- 5. La marée revient, puis se retire en découvrant l'interface toute neuve
	tide.Visible = true
	tidePhase, tideT = "Rise", 0
	if not waitAlive(TIDE_RISE + 0.06) then
		return
	end
	scene.Visible = false
	finalDrain = true
	tidePhase, tideT = "Drain", 0
	if not waitAlive(TIDE_DRAIN) then
		return
	end
	shineAge = 0
	waitAlive(0.75)
end

return Ocean
