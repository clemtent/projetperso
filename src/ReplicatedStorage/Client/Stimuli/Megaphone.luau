--[[
	Megaphone (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Megaphone

	Toutes les 4 à 9 secondes, un GROS mot d'encouragement est "crié" à
	l'écran ("INCROYABLE !!!", "LET'S GO"...) : il arrive en s'écrasant,
	tremble, laisse un écho et une onde de choc, puis s'envole.
	Crie aussi quand il se passe quelque chose de spécial (jackpot, rush,
	succès). Purement visuel : aucune récompense, aucun appel serveur.
]]

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Megaphone = {}
Megaphone.Slot = "Overlay"

local MAX_ACTIVE = 2

local WORDS = {
	en = {
		"INCREDIBLE!!!", "WOW", "HUGE", "LET'S GO", "MAGNIFICENT", "WHAT A CLICK!", "LEGENDARY",
		"PHENOMENAL", "YES YES YES", "INSANE", "SO GOOD", "MONSTROUS", "UNSTOPPABLE",
		"DOPAMINE!!!", "COME ON COME ON", "BRAVO CHAMP", "IMPRESSIVE", "WHOA", "BELIEVE IT",
		"RECORD?!", "EXTRAORDINARY", "MADNESS", "FASTER!", "MORE!!!", "GIGANTIC",
		"SPECTACULAR", "HISTORIC", "CLICKING HARD", "OH MY", "SENSATIONAL", "WHAT TALENT",
		"CLICK CLICK", "YOU'RE ON FIRE", "UN-BE-LIEV-ABLE", "NOBODY SAW THIS COMING",
	},
	fr = {
		"INCROYABLE !!!", "WOW", "ÉNORME", "LET'S GO", "MAGNIFIQUE", "QUEL CLIC !", "LÉGENDAIRE",
		"PHÉNOMÉNAL", "OUI OUI OUI", "C'EST FOU", "TROP FORT", "MONSTRUEUX", "INARRÊTABLE",
		"DOPAMINE !!!", "ALLEZ ALLEZ", "BRAVO CHAMPION", "IMPRESSIONNANT", "WAOUH", "ON Y CROIT",
		"RECORD ?!", "EXTRAORDINAIRE", "LA FOLIE", "PLUS VITE !", "ENCORE !!!", "GIGANTESQUE",
		"SPECTACULAIRE", "HISTORIQUE", "ÇA CLIQUE SEC", "OH LÀ LÀ", "SENSATIONNEL", "QUEL TALENT",
		"CLIQUE CLIQUE", "TU ES EN FEU", "IN-CRO-YABLE", "PERSONNE N'Y CROYAIT",
	},
}

-- Petits commentaires (parfois) sous le mot crié
local ASIDES = {
	en = {
		"(the neighbors heard that)", "(sorry about the noise)", "(your cat woke up)",
		"(volume at max)", "(this is the megaphone talking)", "(even your plant is proud)",
		"(we don't know why we're yelling)", "(batteries almost dead)", "(they heard it in Alaska)",
	},
	fr = {
		"(le voisin a entendu)", "(pardon pour le bruit)", "(ton chat s'est réveillé)",
		"(volume au maximum)", "(c'est le mégaphone qui parle)", "(même ta plante est fière)",
		"(on ne sait pas pourquoi on crie)", "(les piles sont presque vides)", "(ça résonne jusqu'à Brest)",
	},
}

-- Dégradés "hype" (haut -> bas)
local PALETTES = {
	{ Color3.fromRGB(255, 236, 70), Color3.fromRGB(255, 120, 20) },
	{ Color3.fromRGB(255, 120, 200), Color3.fromRGB(157, 60, 230) },
	{ Color3.fromRGB(120, 245, 255), Color3.fromRGB(30, 110, 240) },
	{ Color3.fromRGB(150, 255, 120), Color3.fromRGB(20, 170, 70) },
	{ Color3.fromRGB(255, 150, 120), Color3.fromRGB(230, 30, 60) },
}

function Megaphone.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()
	local active = 0
	local lastSpecial = 0

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	------------------------------------------------------------------
	-- v8 : MAX_ACTIVE "rigs" construits une fois et réutilisés (avant :
	-- ~12 instances créées puis détruites à chaque cri). Nouveau : éclat
	-- de rayons derrière le mot, onde de choc double, texte en relief.
	------------------------------------------------------------------
	local function buildRig()
		local holder = UIUtil.Create("Frame", {
			Name = "Shout",
			Size = UDim2.fromOffset(620, 120),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 30,
			Parent = container,
		})
		local holderScale = UIUtil.Create("UIScale", { Scale = 1, Parent = holder })
		-- Éclat de rayons (derrière le mot)
		local burst = UIUtil.Rays(holder, Color3.new(1, 1, 1), 8, 300, UDim2.fromScale(0.5, 0.5), 29)
		burst.Name = "Burst"
		local burstScale = UIUtil.Create("UIScale", { Scale = 0, Parent = burst })
		local burstBars = {}
		for _, bar in ipairs(burst:GetChildren()) do
			if bar:IsA("Frame") then
				table.insert(burstBars, bar)
			end
		end
		-- Ondes de choc (dans le conteneur : elles débordent du mot)
		local rings = {}
		for index = 1, 2 do
			local ring = UIUtil.Create("Frame", {
				Name = "Shockwave",
				Size = UDim2.fromOffset(80, 80),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Visible = false,
				ZIndex = 29,
				Parent = container,
			})
			UIUtil.Corner(ring, UDim.new(1, 0))
			rings[index] = { Frame = ring, Stroke = UIUtil.Stroke(ring, Color3.new(1, 1, 1), 8, 1) }
		end
		local icon = UIUtil.Label({
			Text = "📢",
			Size = UDim2.fromOffset(84, 84),
			AnchorPoint = Vector2.new(1, 0.5),
			TextTransparency = 1,
			MaxTextSize = 80,
			ZIndex = 31,
			Parent = holder,
		})
		-- Ombre portée du mot (relief)
		local shadow = UIUtil.Label({
			Name = "Shadow",
			Text = "",
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = Theme.Colors.TextDark,
			TextTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(4, 6),
			MaxTextSize = 96,
			ZIndex = 31,
			Parent = holder,
		})
		local label = UIUtil.Label({
			Text = "",
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = Color3.new(1, 1, 1),
			TextTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			MaxTextSize = 96,
			ZIndex = 32,
			Parent = holder,
		})
		local gradient = UIUtil.Gradient(label, ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)), 90)
		local stroke = UIUtil.Stroke(label, Theme.Colors.TextDark, 5, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		-- Écho (copie fantôme qui s'agrandit)
		local echo = UIUtil.Label({
			Text = "",
			Font = Enum.Font.LuckiestGuy,
			TextTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			MaxTextSize = 96,
			ZIndex = 31,
			Parent = holder,
		})
		local echoScale = UIUtil.Create("UIScale", { Parent = echo })
		-- Petit commentaire en dessous
		local aside = UIUtil.Label({
			Text = "",
			Font = Theme.Fonts.Body,
			TextColor3 = Theme.Colors.TextDark,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			TextTransparency = 1,
			Size = UDim2.fromOffset(330, 28),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 2),
			MaxTextSize = 20,
			Visible = false,
			ZIndex = 33,
			Parent = holder,
		})
		UIUtil.Corner(aside, UDim.new(1, 0))
		return {
			Holder = holder,
			Scale = holderScale,
			Burst = burst,
			BurstScale = burstScale,
			BurstBars = burstBars,
			Rings = rings,
			Icon = icon,
			Shadow = shadow,
			Label = label,
			Gradient = gradient,
			Stroke = stroke,
			Echo = echo,
			EchoScale = echoScale,
			Aside = aside,
			Busy = false,
		}
	end

	local rigs = {}
	for index = 1, MAX_ACTIVE do
		rigs[index] = buildRig()
	end

	-- Crie un mot à l'écran
	local function shout(word: string, palette: { Color3 }?, withAside: boolean?)
		if not ctx.IsAlive() or active >= MAX_ACTIVE then
			return
		end
		local rig
		for _, candidate in ipairs(rigs) do
			if not candidate.Busy then
				rig = candidate
				break
			end
		end
		if not rig then
			return
		end
		rig.Busy = true
		active += 1
		local colors = palette or PALETTES[random:NextInteger(1, #PALETTES)]
		local effects = effectsOn()

		-- Position au hasard autour du centre (évite les bords)
		local position = UDim2.fromScale(random:NextNumber(0.3, 0.7), random:NextNumber(0.22, 0.7))
		local holder = rig.Holder
		holder.Position = position
		holder.Rotation = random:NextNumber(-9, 9)
		holder.Visible = true
		rig.Scale.Scale = 2.6
		rig.Label.Text = word
		rig.Shadow.Text = word
		rig.Echo.Text = word
		rig.Label.TextTransparency = 1
		rig.Shadow.TextTransparency = 1
		rig.Stroke.Transparency = 1
		rig.Gradient.Color = ColorSequence.new(colors[1], colors[2])
		rig.Echo.TextColor3 = colors[2]
		rig.Echo.TextTransparency = 1
		rig.EchoScale.Scale = 1
		rig.Icon.TextTransparency = 1
		rig.Icon.Position = UDim2.new(0, -80, 0.5, 0)
		rig.Icon.Rotation = -20
		for _, bar in ipairs(rig.BurstBars) do
			bar.BackgroundColor3 = colors[1]:Lerp(Color3.new(1, 1, 1), 0.35)
		end
		rig.BurstScale.Scale = 0
		rig.Burst.Rotation = random:NextNumber(0, 45)
		rig.Burst.Visible = effects

		-- Ondes de choc (anneaux qui s'agrandissent)
		if effects then
			for index, ring in ipairs(rig.Rings) do
				local frame, ringStroke = ring.Frame, ring.Stroke
				frame.Position = position
				frame.Size = UDim2.fromOffset(80, 80)
				frame.Visible = true
				ringStroke.Color = index == 1 and colors[2] or colors[1]
				ringStroke.Thickness = index == 1 and 8 or 4
				ringStroke.Transparency = 1
				task.delay(0.1 + (index - 1) * 0.12, function()
					if frame.Parent then
						ringStroke.Transparency = index == 1 and 0.1 or 0.3
						UIUtil.Tween(frame, 0.55, { Size = UDim2.fromOffset(620, 620) }, Enum.EasingStyle.Quart)
						UIUtil.Tween(ringStroke, 0.55, { Transparency = 1, Thickness = 1 }, Enum.EasingStyle.Quart)
					end
				end)
			end
		end

		-- Petit commentaire en dessous
		local aside: TextLabel? = nil
		if withAside ~= false and random:NextNumber() < 0.4 then
			local asides = Locale.Pick(ASIDES)
			rig.Aside.Text = asides[random:NextInteger(1, #asides)]
			rig.Aside.TextTransparency = 1
			rig.Aside.BackgroundTransparency = 1
			rig.Aside.Visible = true
			aside = rig.Aside
		else
			rig.Aside.Visible = false
		end

		ctx.Sound.Play("Megaphone", random:NextNumber(0.85, 1.15))

		-- 1) Écrasement à l'arrivée
		local holderScale, label, stroke, icon = rig.Scale, rig.Label, rig.Stroke, rig.Icon
		UIUtil.Tween(holderScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UIUtil.Tween(label, 0.12, { TextTransparency = 0 })
		UIUtil.Tween(rig.Shadow, 0.12, { TextTransparency = 0.55 })
		UIUtil.Tween(stroke, 0.12, { Transparency = 0 })
		UIUtil.Tween(icon, 0.25, { TextTransparency = 0, Position = UDim2.new(0, -6, 0.5, 0), Rotation = 12 }, Enum.EasingStyle.Back)
		if effects then
			UIUtil.Tween(rig.BurstScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			UIUtil.Tween(rig.Burst, 1.6, { Rotation = rig.Burst.Rotation + 40 }, Enum.EasingStyle.Linear)
		end

		task.spawn(function()
			task.wait(0.18)
			if not holder.Parent or not ctx.IsAlive() then
				active -= 1
				rig.Busy = false
				return
			end

			-- Écho
			if effects then
				rig.Echo.TextTransparency = 0.45
				UIUtil.Tween(rig.EchoScale, 0.5, { Scale = 1.5 })
				UIUtil.Tween(rig.Echo, 0.5, { TextTransparency = 1 })
			end

			if aside then
				UIUtil.Tween(aside, 0.2, { TextTransparency = 0, BackgroundTransparency = 0.1 })
			end

			-- 2) Tremblement
			local base = position
			for i = 1, 8 do
				if not holder.Parent then
					break
				end
				local strength = (9 - i) * 1.6
				holder.Position = base + UDim2.fromOffset(random:NextNumber(-strength, strength), random:NextNumber(-strength, strength))
				task.wait(0.03)
			end
			if holder.Parent then
				holder.Position = base
				-- 3) Respiration
				UIUtil.Tween(holderScale, 0.6, { Scale = 1.07 }, Enum.EasingStyle.Sine)
				UIUtil.Tween(icon, 0.6, { Rotation = -6 }, Enum.EasingStyle.Sine)
				task.wait(0.65)
			end

			-- 4) S'envole en disparaissant
			if holder.Parent then
				UIUtil.Tween(holder, 0.4, { Position = base - UDim2.fromOffset(0, 40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				UIUtil.Tween(holderScale, 0.4, { Scale = 0.85 })
				UIUtil.Tween(label, 0.35, { TextTransparency = 1 })
				UIUtil.Tween(rig.Shadow, 0.35, { TextTransparency = 1 })
				UIUtil.Tween(stroke, 0.35, { Transparency = 1 })
				UIUtil.Tween(icon, 0.35, { TextTransparency = 1 })
				UIUtil.Tween(rig.BurstScale, 0.3, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				if aside then
					UIUtil.Tween(aside, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
				end
				task.wait(0.45)
				if holder.Parent then
					holder.Visible = false
					for _, ring in ipairs(rig.Rings) do
						ring.Frame.Visible = false
					end
				end
			end
			active -= 1
			rig.Busy = false
		end)
	end

	-- Cri périodique
	task.spawn(function()
		task.wait(random:NextNumber(1.5, 3))
		while ctx.IsAlive() do
			-- (pas de cri quand une fenêtre est ouverte par-dessus)
			if ctx.GetVisibility == nil or ctx.GetVisibility() == "Visible" then
				local words = Locale.Pick(WORDS)
				shout(words[random:NextInteger(1, #words)])
			end
			task.wait(random:NextNumber(4, 9))
		end
	end)

	-- Cris spéciaux quand il se passe quelque chose (texte anglais traduit au moment du cri)
	local specials = {
		Jackpot = { "JACKPOT!!!", PALETTES[1] },
		Rush = { "IT'S RUSH TIME!!!", PALETTES[5] },
		Achievement = { "ACHIEVEMENT!!!", PALETTES[4] },
		Unlock = { "NEW STUFF!", PALETTES[2] },
	}
	if ctx.State.NotifyReceived then
		ctx.Connect(ctx.State.NotifyReceived, function(payload)
			if type(payload) ~= "table" then
				return
			end
			local special = specials[payload.Type]
			if not special then
				return
			end
			-- Les succès restent discrets tant que la fonctionnalité n'est pas débloquée
			if payload.Type == "Achievement" and not ctx.HasFeature("Achievements") then
				return
			end
			local now = os.clock()
			if now - lastSpecial < 2 then
				return
			end
			lastSpecial = now
			shout(Locale.T(special[1]), special[2], false)
		end)
	end
end

function Megaphone.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Megaphone
