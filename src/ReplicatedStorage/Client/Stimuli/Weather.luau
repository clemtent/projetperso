--[[
	Weather (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Weather

	Orage miniature : deux petits nuages mignons (avec une tête !) dérivent
	en haut de l'écran, de part et d'autre de la colonne centrale, et font
	tomber une petite pluie. Quand le SERVEUR envoie un Spawn "Lightning",
	un éclair en zigzag (dessiné en code : contour sombre, cœur jaune, halo)
	tombe d'un nuage fâché en (X, Y), avec flash et tonnerre. Il faut
	cliquer dessus avant qu'il ne disparaisse (Lifetime) : ClaimSpawn, et
	le "+X" confirmé (OnBonus "Lightning") s'affiche à l'impact.
]]

local Debris = game:GetService("Debris")

local Weather = {}
Weather.Slot = "Overlay"

local MAX_BOLTS = 3
local CLOUD_W = 112
local CLOUD_H = 58
local DROPS_PER_CLOUD = 10
local DROPS_LOW_EFFECTS = 4
local RAIN_FALL = 70 -- distance de chute des gouttes (pixels "design")

local BOLT_W = 150
local BOLT_H = 232
local BOLT_TOP = 48 -- départ de l'éclair (sous le petit nuage)
local BOLT_IMPACT = 198 -- point d'impact dans le cadre de l'éclair
local BOLT_ANCHOR_Y = BOLT_IMPACT / BOLT_H

local TAGS = { "⚡ attrape !", "⚡ vite !", "⚡ zap ?", "⚡ clique !", "⚡ ici !" }
local CHEERS = { "ÉLECTRISANT !", "ZAP !", "QUEL RÉFLEXE !", "FOUDROYANT !", "CHOC !", "100 000 VOLTS !" }

function Weather.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()

	local yellow = Theme.Colors.Yellow
	local boltCore = Color3.fromRGB(255, 244, 150)
	local boltOutline = Color3.fromRGB(70, 45, 0)
	local cloudColor = Color3.fromRGB(176, 186, 202)
	local cloudAngry = Color3.fromRGB(120, 128, 146)
	local stormColor = Color3.fromRGB(96, 104, 122)
	local rainColor = Color3.fromRGB(80, 150, 225)
	local faceColor = Color3.fromRGB(40, 40, 50)

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function circle(parent: Instance, x: number, y: number, diameter: number, color: Color3, zIndex: number): Frame
		local frame = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(diameter, diameter),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = parent,
		})
		UIUtil.Corner(frame, UDim.new(1, 0))
		return frame
	end

	-- Segment de droite (cadre tourné) entre deux points
	local function line(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, zIndex: number, transparency: number?): Frame
		local delta = b - a
		local middle = (a + b) / 2
		local frame = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(delta.Magnitude + thickness, thickness),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(middle.X, middle.Y),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = parent,
		})
		UIUtil.Corner(frame, UDim.new(1, 0))
		return frame
	end

	------------------------------------------------------------------
	-- Nuage mignon (bouffées rondes + petite tête)
	------------------------------------------------------------------
	local function makeCloud(parent: Instance, color: Color3, zIndex: number)
		local root = UIUtil.Create("Frame", {
			Name = "Cloud",
			Size = UDim2.fromOffset(CLOUD_W, CLOUD_H),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Parent = parent,
		})
		local puffs = {
			circle(root, 10, 12, 36, color, zIndex),
			circle(root, 32, 0, 48, color, zIndex),
			circle(root, 62, 8, 40, color, zIndex),
			circle(root, 80, 22, 30, color, zIndex),
		}
		local base = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(96, 30),
			Position = UDim2.fromOffset(8, 26),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = root,
		})
		UIUtil.Corner(base, UDim.new(1, 0))
		table.insert(puffs, base)
		-- Reflet clair sur le dessus
		local shine = circle(root, 42, 6, 18, Color3.new(1, 1, 1), zIndex + 1)
		shine.BackgroundTransparency = 0.55

		-- Visage
		local eyeL = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(6, 8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(46, 34),
			BackgroundColor3 = faceColor,
			BorderSizePixel = 0,
			ZIndex = zIndex + 2,
			Parent = root,
		})
		UIUtil.Corner(eyeL, UDim.new(1, 0))
		local eyeR = eyeL:Clone()
		eyeR.Position = UDim2.fromOffset(66, 34)
		eyeR.Parent = root
		local mouth = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(10, 4),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(56, 44),
			BackgroundColor3 = faceColor,
			BorderSizePixel = 0,
			ZIndex = zIndex + 2,
			Parent = root,
		})
		UIUtil.Corner(mouth, UDim.new(1, 0))
		local cheekL = circle(root, 34, 38, 9, Color3.fromRGB(255, 130, 160), zIndex + 1)
		cheekL.BackgroundTransparency = 0.45
		local cheekR = circle(root, 69, 38, 9, Color3.fromRGB(255, 130, 160), zIndex + 1)
		cheekR.BackgroundTransparency = 0.45
		-- Sourcils fâchés (cachés par défaut)
		local browL = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(11, 3),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(45, 26),
			Rotation = 25,
			BackgroundColor3 = faceColor,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = zIndex + 2,
			Parent = root,
		})
		local browR = browL:Clone()
		browR.Position = UDim2.fromOffset(67, 26)
		browR.Rotation = -25
		browR.Parent = root

		return {
			Root = root,
			Puffs = puffs,
			EyeL = eyeL,
			EyeR = eyeR,
			Mouth = mouth,
			Brows = { browL, browR },
			Color = color,
			Angry = false,
		}
	end

	local function setAngry(cloud, angry: boolean, normalColor: Color3, angryColor: Color3)
		if cloud.Angry == angry then
			return
		end
		cloud.Angry = angry
		for _, brow in ipairs(cloud.Brows) do
			brow.Visible = angry
		end
		for _, puff in ipairs(cloud.Puffs) do
			puff.BackgroundColor3 = angry and angryColor or normalColor
		end
		-- Bouche : ronde ("oh !") si fâché, petit sourire sinon
		cloud.Mouth.Size = angry and UDim2.fromOffset(8, 8) or UDim2.fromOffset(10, 4)
	end

	------------------------------------------------------------------
	-- Nuages d'ambiance (à gauche et à droite de la colonne centrale)
	------------------------------------------------------------------
	local ambient = {}
	local ranges = {
		{ Min = 0.015, Max = 0.17, Anchor = 0 },
		{ Min = 0.83, Max = 0.985, Anchor = 1 },
	}
	local dropCount = effectsOn() and DROPS_PER_CLOUD or DROPS_LOW_EFFECTS
	for index, range in ipairs(ranges) do
		local cloud = makeCloud(container, cloudColor, 5)
		cloud.Root.AnchorPoint = Vector2.new(range.Anchor, 0)
		cloud.Range = range
		cloud.Phase = random:NextNumber(0, math.pi * 2) + index
		cloud.NextBlink = os.clock() + random:NextNumber(1, 4)
		cloud.BlinkUntil = 0
		cloud.AngryUntil = 0
		cloud.Drops = {}
		for _ = 1, dropCount do
			local drop = UIUtil.Create("Frame", {
				Size = UDim2.fromOffset(2, 10),
				AnchorPoint = Vector2.new(0.5, 0),
				Rotation = 12,
				BackgroundColor3 = rainColor,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = cloud.Root,
			})
			table.insert(cloud.Drops, {
				Frame = drop,
				X = random:NextNumber(16, CLOUD_W - 16),
				Y = random:NextNumber(0, RAIN_FALL),
				Speed = random:NextNumber(90, 140),
			})
		end
		table.insert(ambient, cloud)
	end

	------------------------------------------------------------------
	-- Éclairs
	------------------------------------------------------------------
	local bolts: { [string]: any } = {}
	local boltCount = 0
	local positions: { [string]: UDim2 } = {}
	local lastPosition = UDim2.fromScale(0.5, 0.5)

	local function fadeAll(root: Instance, duration: number)
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("TextLabel") then
				UIUtil.Tween(item, duration, { TextTransparency = 1, BackgroundTransparency = 1 })
			elseif item:IsA("Frame") then
				UIUtil.Tween(item, duration, { BackgroundTransparency = 1 })
			elseif item:IsA("UIStroke") then
				UIUtil.Tween(item, duration, { Transparency = 1 })
			end
		end
	end

	local function removeBolt(bolt, claimed: boolean)
		if bolt.Done then
			return
		end
		bolt.Done = true
		bolts[bolt.Id] = nil
		boltCount -= 1
		if claimed then
			UIUtil.Tween(bolt.Scale, 0.3, { Scale = 1.35 }, Enum.EasingStyle.Quad)
		else
			UIUtil.Tween(bolt.Scale, 0.35, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		fadeAll(bolt.Root, 0.3)
		Debris:AddItem(bolt.Root, 0.4)
	end

	-- Le nuage d'ambiance le plus proche se fâche
	local function angerNearestCloud(x: number)
		local best, bestDistance = nil, math.huge
		for _, cloud in ipairs(ambient) do
			local center = (cloud.Range.Min + cloud.Range.Max) / 2
			local distance = math.abs(center - x)
			if distance < bestDistance then
				best, bestDistance = cloud, distance
			end
		end
		if best then
			best.AngryUntil = os.clock() + 1.4
		end
	end

	local function spawnBolt(info)
		if not ctx.IsAlive() or type(info) ~= "table" or type(info.Id) ~= "string" then
			return
		end
		if bolts[info.Id] or boltCount >= MAX_BOLTS then
			return
		end
		local x = math.clamp(tonumber(info.X) or 0.5, 0.06, 0.94)
		local y = math.clamp(tonumber(info.Y) or 0.5, 0.1, 0.92)
		local lifetime = math.max(1, tonumber(info.Lifetime) or 2.5)
		local variant = math.floor(tonumber(info.Variant) or 1)
		local shape = Random.new(variant) -- forme déterministe selon la variante

		-- Décalage pour que le petit nuage ne sorte pas par le haut
		local extra = math.max(0, BOLT_IMPACT + 34 - y * 720)
		local position = UDim2.new(x, 0, y, extra)

		local root = UIUtil.Create("TextButton", {
			Name = "Lightning",
			Size = UDim2.fromOffset(BOLT_W, BOLT_H),
			AnchorPoint = Vector2.new(0.5, BOLT_ANCHOR_Y),
			Position = position,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 30,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Scale = 1, Parent = root })

		-- Petit nuage d'orage, fâché
		local storm = makeCloud(root, stormColor, 36)
		storm.Root.Position = UDim2.fromOffset((BOLT_W - CLOUD_W) / 2, 0)
		setAngry(storm, true, stormColor, stormColor)

		-- Points du zigzag
		local points = {}
		local steps = 6
		for i = 0, steps do
			local py = BOLT_TOP + (BOLT_IMPACT - BOLT_TOP) * i / steps
			local px = BOLT_W / 2
			if i > 0 and i < steps then
				local side = (i % 2 == 1) and 1 or -1
				if variant % 2 == 0 then
					side = -side
				end
				px += side * shape:NextNumber(10, 24)
			elseif i == steps then
				px += shape:NextNumber(-6, 6)
			end
			table.insert(points, Vector2.new(px, py))
		end

		-- Segments : halo, contour sombre, cœur jaune (révélés un par un)
		local steps2: { { Frame } } = {}
		local cores: { Frame } = {}
		local glows: { Frame } = {}
		local function addSegment(a: Vector2, b: Vector2, width: number)
			local glow = line(root, a, b, width + 14, yellow, 31, 0.7)
			local outline = line(root, a, b, width + 4, boltOutline, 32)
			local core = line(root, a, b, width, boltCore, 33)
			glow.Visible, outline.Visible, core.Visible = false, false, false
			table.insert(steps2, { glow, outline, core })
			table.insert(cores, core)
			table.insert(glows, glow)
		end
		for i = 1, #points - 1 do
			addSegment(points[i], points[i + 1], 6)
			-- Petite branche sur le 2e coude
			if i == 2 then
				local from = points[3]
				local side = (from.X > BOLT_W / 2) and 1 or -1
				local mid = from + Vector2.new(side * 26, 22)
				addSegment(from, mid, 3)
				addSegment(mid, mid + Vector2.new(side * 8, 18), 2)
			end
		end

		-- Impact : halo + anneau qui pulse
		local impact = points[#points]
		local impactGlow = circle(root, impact.X - 22, impact.Y - 22, 44, yellow, 30)
		impactGlow.BackgroundTransparency = 0.5
		local ring = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(64, 64),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(impact.X, impact.Y),
			BackgroundTransparency = 1,
			ZIndex = 30,
			Parent = root,
		})
		UIUtil.Corner(ring, UDim.new(1, 0))
		local ringStroke = UIUtil.Stroke(ring, yellow, 3, 0.1)
		local ringScale = UIUtil.Create("UIScale", { Parent = ring })

		-- Étiquette
		local tag = UIUtil.Label({
			Text = TAGS[random:NextInteger(1, #TAGS)],
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.TextDark,
			BackgroundColor3 = yellow,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(92, 22),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(BOLT_W / 2, BOLT_IMPACT + 10),
			MaxTextSize = 15,
			ZIndex = 38,
			Parent = root,
		})
		UIUtil.Corner(tag, UDim.new(1, 0))
		UIUtil.Stroke(tag, Theme.Colors.Border, 1.5, 0.1)

		local bolt = {
			Id = info.Id,
			Root = root,
			Scale = scale,
			Cores = cores,
			Glows = glows,
			ImpactGlow = impactGlow,
			RingScale = ringScale,
			RingStroke = ringStroke,
			Storm = storm,
			Base = position,
			Born = os.clock(),
			Lifetime = lifetime,
			Done = false,
		}
		bolts[info.Id] = bolt
		boltCount += 1

		-- Frappe : le zigzag se dessine de haut en bas
		task.spawn(function()
			for _, group in ipairs(steps2) do
				if bolt.Done or not root.Parent then
					return
				end
				for _, frame in ipairs(group) do
					frame.Visible = true
				end
				task.wait(0.02)
			end
		end)

		ctx.Sound.Play("Thunder", 0.8 + random:NextNumber() * 0.2)
		if effectsOn() then
			ctx.Effects.Flash(Color3.fromRGB(255, 250, 215), 0.3)
		end
		angerNearestCloud(x)

		-- Clic : on attrape l'éclair
		ctx.Connect(root.Activated, function()
			if bolt.Done or not ctx.IsAlive() then
				return
			end
			local impactPosition = UDim2.new(x, 0, y, extra)
			positions[bolt.Id] = impactPosition
			lastPosition = impactPosition
			ctx.ClaimSpawn(bolt.Id)
			ctx.Sound.Play("Thunder", 1.5)
			if effectsOn() then
				ctx.Effects.Burst(container, impactPosition, yellow, 18)
				ctx.Effects.Burst(container, impactPosition, nil, 8)
			end
			removeBolt(bolt, true)
			local id = bolt.Id
			task.delay(6, function()
				positions[id] = nil
			end)
		end)
	end

	------------------------------------------------------------------
	-- Animation (une seule connexion)
	------------------------------------------------------------------
	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		local now = os.clock()

		-- Nuages d'ambiance
		for _, cloud in ipairs(ambient) do
			local range = cloud.Range
			local drift = 0.5 + 0.5 * math.sin(now * 0.08 + cloud.Phase)
			local sx = range.Min + (range.Max - range.Min) * drift
			local bob = math.sin(now * 0.9 + cloud.Phase) * 3
			local angry = now < cloud.AngryUntil
			local shake = angry and math.sin(now * 60) * 2 or 0
			cloud.Root.Position = UDim2.new(sx, shake, 0, 36 + bob)
			setAngry(cloud, angry, cloudColor, cloudAngry)

			-- Clignement des yeux
			if now >= cloud.NextBlink then
				cloud.BlinkUntil = now + 0.12
				cloud.NextBlink = now + random:NextNumber(2.5, 5.5)
			end
			local eyeHeight = (now < cloud.BlinkUntil) and 1 or 8
			if cloud.EyeL.Size.Y.Offset ~= eyeHeight then
				cloud.EyeL.Size = UDim2.fromOffset(6, eyeHeight)
				cloud.EyeR.Size = UDim2.fromOffset(6, eyeHeight)
			end

			-- Pluie
			for _, drop in ipairs(cloud.Drops) do
				drop.Y += drop.Speed * dt
				if drop.Y > RAIN_FALL then
					drop.Y = 0
					drop.X = random:NextNumber(16, CLOUD_W - 16)
				end
				drop.Frame.Position = UDim2.fromOffset(drop.X - drop.Y * 0.2, CLOUD_H - 8 + drop.Y)
				drop.Frame.BackgroundTransparency = 0.25 + 0.75 * (drop.Y / RAIN_FALL)
			end
		end

		-- Éclairs
		for _, bolt in pairs(bolts) do
			local age = now - bolt.Born
			local left = bolt.Lifetime - age
			if left <= 0 then
				removeBolt(bolt, false)
			else
				-- Scintillement
				local flicker = random:NextNumber(0, 0.25)
				for _, core in ipairs(bolt.Cores) do
					core.BackgroundTransparency = flicker
				end
				local glowAlpha = 0.6 + math.sin(now * 25) * 0.15
				for _, glow in ipairs(bolt.Glows) do
					glow.BackgroundTransparency = glowAlpha
				end
				bolt.ImpactGlow.BackgroundTransparency = 0.45 + math.sin(now * 12) * 0.15
				-- Anneau qui s'agrandit en boucle
				local cycle = (age * 1.6) % 1
				bolt.RingScale.Scale = 0.6 + cycle * 0.9
				bolt.RingStroke.Transparency = cycle
				-- Le petit nuage tremble de colère
				bolt.Storm.Root.Position = UDim2.fromOffset((BOLT_W - CLOUD_W) / 2 + math.sin(now * 50) * 1.5, 0)
				-- Presque fini : clignote
				if left < 0.6 then
					bolt.Root.Position = bolt.Base + UDim2.fromOffset(math.sin(now * 40) * 2, 0)
				end
			end
		end
	end)

	ctx.OnSpawn("Lightning", spawnBolt)

	-- Bonus confirmé : "+X ⚡" à l'impact
	ctx.OnBonus("Lightning", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local position = (payload.SpawnId and positions[payload.SpawnId]) or lastPosition
		ctx.FloatText(container, position, "+" .. ctx.Format.Format(tonumber(payload.Amount) or 0) .. " ⚡", Theme.Colors.Gold, 44)
		ctx.FloatText(container, position + UDim2.fromOffset(0, 44), CHEERS[random:NextInteger(1, #CHEERS)], Theme.Colors.Orange, 24)
	end)
end

function Weather.Stop(_ctx)
	-- Nuages et éclairs vivent dans ctx.Container (détruit par le StimulusManager)
end

return Weather
