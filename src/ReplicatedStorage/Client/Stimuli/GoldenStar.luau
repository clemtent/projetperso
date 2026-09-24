--[[
	GoldenStar (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > GoldenStar

	Étoiles dorées qui apparaissent au hasard (décidé par le SERVEUR via
	l'événement Spawn "Golden") : halo qui pulse, rayons qui tournent,
	petites étincelles en orbite... et elles s'en vont vite !
	Un clic = ClaimSpawn (le serveur vérifie puis envoie le bonus), et le
	bonus confirmé s'affiche en gros "+X" doré à l'endroit de l'étoile.
]]

local Debris = game:GetService("Debris")

local GoldenStar = {}
GoldenStar.Slot = "Overlay"

local MAX_STARS = 5
local RAY_COUNT = 6
local WARNING_TIME = 1.5 -- dernières secondes : l'étoile s'impatiente

local TAGS = { "vite !!", "attrape-moi", "clique ici ✨", "je brille !", "c'est moi 🌟", "par ici !" }
local HURRY_TAGS = { "trop tard ?", "je pars !", "bye bye...", "dépêche !" }
local CHEERS = { "QUELLE CHANCE !", "ÉTOILE ATTRAPÉE !", "DORÉ !!!", "BRILLANT !", "RÉFLEXES DE CHAT !" }

function GoldenStar.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()

	local stars = {} -- [id] = étoile active
	local count = 0
	local positions = {} -- [id] = UDim2 (pour placer le "+X" du bonus)
	local lastPosition = UDim2.fromScale(0.5, 0.45)

	local gold = Theme.Colors.Gold
	local orange = Theme.Colors.Orange

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Fait disparaître tous les éléments visuels d'une étoile
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

	local function removeStar(star, popped: boolean)
		if star.Done then
			return
		end
		star.Done = true
		stars[star.Id] = nil
		count -= 1
		local scale = star.Scale
		if popped then
			UIUtil.Tween(scale, 0.3, { Scale = 1.8 }, Enum.EasingStyle.Quad)
			fadeAll(star.Button, 0.3)
		else
			UIUtil.Tween(scale, 0.35, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		Debris:AddItem(star.Button, 0.4)
	end

	local function spawnStar(info)
		if not ctx.IsAlive() or type(info) ~= "table" or info.Id == nil then
			return
		end
		if stars[info.Id] or count >= MAX_STARS then
			return
		end
		local x = math.clamp(tonumber(info.X) or 0.5, 0.05, 0.95)
		local y = math.clamp(tonumber(info.Y) or 0.5, 0.08, 0.92)
		local lifetime = math.max(1, tonumber(info.Lifetime) or 6)
		local basePosition = UDim2.fromScale(x, y)

		-- Bouton principal (zone cliquable généreuse pour le tactile)
		local button = UIUtil.Create("TextButton", {
			Name = "GoldenStar",
			Size = UDim2.fromOffset(100, 100),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = basePosition,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 20,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Scale = 0, Parent = button })

		-- Halo (cercles concentriques de plus en plus transparents)
		local halo = UIUtil.Create("Frame", {
			Name = "Halo",
			Size = UDim2.fromOffset(180, 180),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 20,
			Parent = button,
		})
		local haloScale = UIUtil.Create("UIScale", { Parent = halo })
		for i, spec in ipairs({ { 1, 0.88 }, { 0.75, 0.78 }, { 0.55, 0.62 } }) do
			local ring = UIUtil.Create("Frame", {
				Size = UDim2.fromScale(spec[1], spec[1]),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = i == 3 and Theme.Colors.Yellow or gold,
				BackgroundTransparency = spec[2],
				ZIndex = 20,
				Parent = halo,
			})
			UIUtil.Corner(ring, UDim.new(1, 0))
		end

		-- Rayons qui tournent
		local rays = {}
		for i = 1, RAY_COUNT do
			local ray = UIUtil.Create("Frame", {
				Size = UDim2.fromOffset(200, 8),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = Theme.Colors.Yellow,
				BackgroundTransparency = 0.2,
				Rotation = (i - 1) * (180 / RAY_COUNT),
				ZIndex = 21,
				Parent = button,
			})
			UIUtil.Corner(ray, UDim.new(1, 0))
			UIUtil.Create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.35, 0.55),
					NumberSequenceKeypoint.new(0.5, 0.3),
					NumberSequenceKeypoint.new(0.65, 0.55),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = ray,
			})
			rays[i] = ray
		end

		-- Médaillon doré
		local disc = UIUtil.Create("Frame", {
			Name = "Disc",
			Size = UDim2.fromOffset(78, 78),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 22,
			Parent = button,
		})
		UIUtil.Corner(disc, UDim.new(1, 0))
		local discStroke = UIUtil.Stroke(disc, Color3.new(1, 1, 1), 3, 0)
		local discGradient = UIUtil.Gradient(disc, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Colors.Yellow),
			ColorSequenceKeypoint.new(0.5, gold),
			ColorSequenceKeypoint.new(1, orange),
		}), 45)
		UIUtil.Label({
			Text = "🌟",
			Size = UDim2.fromScale(0.78, 0.78),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 56,
			ZIndex = 23,
			Parent = disc,
		})

		-- Étincelles en orbite
		local sparkles = {}
		for i = 1, 2 do
			sparkles[i] = UIUtil.Label({
				Text = "✨",
				Size = UDim2.fromOffset(26, 26),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				MaxTextSize = 24,
				ZIndex = 24,
				Parent = button,
			})
		end

		-- Petite étiquette "vite !!"
		local tag = UIUtil.Label({
			Text = TAGS[random:NextInteger(1, #TAGS)],
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.TextDark,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(104, 24),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 4),
			MaxTextSize = 17,
			ZIndex = 25,
			Parent = button,
		})
		UIUtil.Corner(tag, UDim.new(1, 0))
		UIUtil.Stroke(tag, Theme.Colors.Border, 1.5, 0.1)

		local star = {
			Id = info.Id,
			Button = button,
			Scale = scale,
			HaloScale = haloScale,
			Rays = rays,
			Disc = disc,
			DiscStroke = discStroke,
			DiscGradient = discGradient,
			Sparkles = sparkles,
			Tag = tag,
			Base = basePosition,
			Born = os.clock(),
			Lifetime = lifetime,
			Phase = random:NextNumber(0, math.pi * 2),
			Hurry = false,
			Done = false,
		}
		stars[info.Id] = star
		count += 1

		-- Apparition
		UIUtil.Tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Golden", 1.4)

		-- Clic : on réclame l'étoile au serveur
		ctx.Connect(button.Activated, function()
			if star.Done or not ctx.IsAlive() then
				return
			end
			local position = button.Position
			positions[star.Id] = position
			lastPosition = position
			ctx.ClaimSpawn(star.Id)
			ctx.Sound.Play("Golden", 1.8)
			if effectsOn() then
				ctx.Effects.Burst(container, position, gold, 24)
				ctx.Effects.Burst(container, position, nil, 12)
				ctx.Effects.Flash(Theme.Colors.Yellow, 0.2)
			end
			removeStar(star, true)
			-- On oublie la position après un moment
			task.delay(6, function()
				positions[star.Id] = nil
			end)
		end)
	end

	-- Animation de toutes les étoiles (une seule connexion)
	ctx.OnRender(function()
		local now = os.clock()
		for _, star in pairs(stars) do
			local age = now - star.Born
			local left = star.Lifetime - age
			if left <= 0 then
				removeStar(star, false)
			else
				local t = now + star.Phase
				-- Flotte doucement
				star.Button.Position = star.Base + UDim2.fromOffset(math.sin(t * 1.3) * 10, math.cos(t * 1.7) * 8)
				-- Halo qui respire
				star.HaloScale.Scale = 1 + math.sin(t * 5) * 0.1
				-- Rayons qui tournent
				local spin = t * 45
				for i, ray in ipairs(star.Rays) do
					ray.Rotation = spin + (i - 1) * (180 / RAY_COUNT)
				end
				star.DiscGradient.Rotation = (t * 120) % 360
				-- Étincelles en orbite
				for i, sparkle in ipairs(star.Sparkles) do
					local angle = t * 3 + i * math.pi
					sparkle.Position = UDim2.new(0.5, math.cos(angle) * 56, 0.5, math.sin(angle) * 48)
				end
				-- Pulsation (après l'apparition)
				if age > 0.45 then
					if left < WARNING_TIME then
						-- Pressée de partir : tremble et clignote
						if not star.Hurry then
							star.Hurry = true
							star.Tag.Text = HURRY_TAGS[random:NextInteger(1, #HURRY_TAGS)]
							star.Tag.BackgroundColor3 = Theme.Colors.Red
							star.Tag.TextColor3 = Theme.Colors.TextLight
						end
						star.Scale.Scale = 1 + math.sin(t * 22) * 0.07
						star.Disc.Rotation = math.sin(t * 30) * 12
						star.DiscStroke.Color = (math.floor(now * 8) % 2 == 0) and Theme.Colors.Red or Color3.new(1, 1, 1)
					else
						star.Scale.Scale = 1 + math.sin(t * 9) * 0.06
						star.Disc.Rotation = math.sin(t * 3) * 12
					end
				end
			end
		end
	end)

	ctx.OnSpawn("Golden", spawnStar)

	-- Bonus confirmé : gros "+X" doré
	ctx.OnBonus("Golden", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local position = (payload.SpawnId and positions[payload.SpawnId]) or lastPosition
		ctx.FloatText(container, position, "+" .. ctx.Format.Format(tonumber(payload.Amount) or 0), gold, 60)
		ctx.FloatText(container, position + UDim2.fromOffset(0, 50), CHEERS[random:NextInteger(1, #CHEERS)], orange, 26)
	end)
end

function GoldenStar.Stop(_ctx)
	-- Les étoiles vivent dans ctx.Container (détruit par le StimulusManager)
end

return GoldenStar
