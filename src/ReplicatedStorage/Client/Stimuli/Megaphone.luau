--[[
	Megaphone (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Megaphone

	Toutes les 4 à 9 secondes, un GROS mot d'encouragement est "crié" à
	l'écran ("INCROYABLE !!!", "LET'S GO"...) : il arrive en s'écrasant,
	tremble, laisse un écho et une onde de choc, puis s'envole.
	Crie aussi quand il se passe quelque chose de spécial (jackpot, rush,
	succès). Purement visuel : aucune récompense, aucun appel serveur.
]]

local Debris = game:GetService("Debris")

local Megaphone = {}
Megaphone.Slot = "Overlay"

local MAX_ACTIVE = 2

local WORDS = {
	"INCROYABLE !!!", "WOW", "ÉNORME", "LET'S GO", "MAGNIFIQUE", "QUEL CLIC !", "LÉGENDAIRE",
	"PHÉNOMÉNAL", "OUI OUI OUI", "C'EST FOU", "TROP FORT", "MONSTRUEUX", "INARRÊTABLE",
	"DOPAMINE !!!", "ALLEZ ALLEZ", "BRAVO CHAMPION", "IMPRESSIONNANT", "WAOUH", "ON Y CROIT",
	"RECORD ?!", "EXTRAORDINAIRE", "LA FOLIE", "PLUS VITE !", "ENCORE !!!", "GIGANTESQUE",
	"SPECTACULAIRE", "HISTORIQUE", "ÇA CLIQUE SEC", "OH LÀ LÀ", "SENSATIONNEL", "QUEL TALENT",
	"CLIQUE CLIQUE", "TU ES EN FEU", "IN-CRO-YABLE", "PERSONNE N'Y CROYAIT",
}

-- Petits commentaires (parfois) sous le mot crié
local ASIDES = {
	"(le voisin a entendu)", "(pardon pour le bruit)", "(ton chat s'est réveillé)",
	"(volume au maximum)", "(c'est le mégaphone qui parle)", "(même ta plante est fière)",
	"(on ne sait pas pourquoi on crie)", "(les piles sont presque vides)", "(ça résonne jusqu'à Brest)",
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

	-- Crie un mot à l'écran
	local function shout(word: string, palette: { Color3 }?, withAside: boolean?)
		if not ctx.IsAlive() or active >= MAX_ACTIVE then
			return
		end
		active += 1
		local colors = palette or PALETTES[random:NextInteger(1, #PALETTES)]
		local effects = effectsOn()

		-- Position au hasard autour du centre (évite les bords)
		local position = UDim2.fromScale(random:NextNumber(0.3, 0.7), random:NextNumber(0.22, 0.7))
		local holder = UIUtil.Create("Frame", {
			Name = "Shout",
			Size = UDim2.fromOffset(620, 120),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Rotation = random:NextNumber(-9, 9),
			BackgroundTransparency = 1,
			ZIndex = 30,
			Parent = container,
		})
		local holderScale = UIUtil.Create("UIScale", { Scale = 2.6, Parent = holder })

		-- Onde de choc (anneau qui s'agrandit)
		if effects then
			local ring = UIUtil.Create("Frame", {
				Size = UDim2.fromOffset(80, 80),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = position,
				BackgroundTransparency = 1,
				ZIndex = 29,
				Parent = container,
			})
			UIUtil.Corner(ring, UDim.new(1, 0))
			local ringStroke = UIUtil.Stroke(ring, colors[2], 8, 0.1)
			task.delay(0.12, function()
				if ring.Parent then
					UIUtil.Tween(ring, 0.55, { Size = UDim2.fromOffset(620, 620) }, Enum.EasingStyle.Quart)
					UIUtil.Tween(ringStroke, 0.55, { Transparency = 1, Thickness = 1 }, Enum.EasingStyle.Quart)
				end
			end)
			Debris:AddItem(ring, 0.8)
		end

		-- Icône 📢 qui arrive par la gauche
		local icon = UIUtil.Label({
			Text = "📢",
			Size = UDim2.fromOffset(84, 84),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, -80, 0.5, 0),
			Rotation = -20,
			TextTransparency = 1,
			MaxTextSize = 80,
			ZIndex = 31,
			Parent = holder,
		})

		-- Le mot
		local label = UIUtil.Label({
			Text = word,
			Font = Enum.Font.LuckiestGuy,
			TextColor3 = Color3.new(1, 1, 1),
			TextTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			MaxTextSize = 96,
			ZIndex = 32,
			Parent = holder,
		})
		UIUtil.Gradient(label, ColorSequence.new(colors[1], colors[2]), 90)
		local stroke = UIUtil.Stroke(label, Theme.Colors.TextDark, 5, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.LineJoinMode = Enum.LineJoinMode.Round

		-- Petit commentaire en dessous
		local aside: TextLabel? = nil
		if withAside ~= false and random:NextNumber() < 0.4 then
			local sub = UIUtil.Label({
				Text = ASIDES[random:NextInteger(1, #ASIDES)],
				Font = Theme.Fonts.Body,
				TextColor3 = Theme.Colors.TextDark,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 1,
				TextTransparency = 1,
				Size = UDim2.fromOffset(330, 28),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 2),
				MaxTextSize = 20,
				ZIndex = 33,
				Parent = holder,
			})
			UIUtil.Corner(sub, UDim.new(1, 0))
			aside = sub
		end

		ctx.Sound.Play("Megaphone", random:NextNumber(0.85, 1.15))

		-- 1) Écrasement à l'arrivée
		UIUtil.Tween(holderScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UIUtil.Tween(label, 0.12, { TextTransparency = 0 })
		UIUtil.Tween(stroke, 0.12, { Transparency = 0 })
		UIUtil.Tween(icon, 0.25, { TextTransparency = 0, Position = UDim2.new(0, -6, 0.5, 0), Rotation = 12 }, Enum.EasingStyle.Back)

		task.spawn(function()
			task.wait(0.18)
			if not holder.Parent or not ctx.IsAlive() then
				active -= 1
				return
			end

			-- Écho (copie fantôme qui s'agrandit)
			if effects then
				local echo = UIUtil.Label({
					Text = word,
					Font = Enum.Font.LuckiestGuy,
					TextColor3 = colors[2],
					TextTransparency = 0.45,
					Size = UDim2.fromScale(1, 1),
					MaxTextSize = 96,
					ZIndex = 31,
					Parent = holder,
				})
				local echoScale = UIUtil.Create("UIScale", { Parent = echo })
				UIUtil.Tween(echoScale, 0.5, { Scale = 1.5 })
				UIUtil.Tween(echo, 0.5, { TextTransparency = 1 })
				Debris:AddItem(echo, 0.55)
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
				UIUtil.Tween(stroke, 0.35, { Transparency = 1 })
				UIUtil.Tween(icon, 0.35, { TextTransparency = 1 })
				if aside then
					UIUtil.Tween(aside, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
				end
				Debris:AddItem(holder, 0.45)
			end
			active -= 1
		end)
	end

	-- Cri périodique
	task.spawn(function()
		task.wait(random:NextNumber(1.5, 3))
		while ctx.IsAlive() do
			shout(WORDS[random:NextInteger(1, #WORDS)])
			task.wait(random:NextNumber(4, 9))
		end
	end)

	-- Cris spéciaux quand il se passe quelque chose
	local specials = {
		Jackpot = { "JACKPOT !!!", PALETTES[1] },
		Rush = { "C'EST LE RUSH !!!", PALETTES[5] },
		Achievement = { "SUCCÈS !!!", PALETTES[4] },
		Unlock = { "NOUVEAUTÉ !", PALETTES[2] },
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
			shout(special[1], special[2], false)
		end)
	end
end

function Megaphone.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return Megaphone
