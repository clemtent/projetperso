--[[
	NeonMode (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > NeonMode

	Mode néon (calque Background, sous tout le reste) : reprise du fond
	animé de la v1, version "nuit électrique" :
	  - dégradé sombre qui tourne et pulse vers le rose / violet / cyan ;
	  - orbes lumineux qui dérivent lentement ;
	  - petites étoiles qui scintillent en haut ;
	  - grille rétro en perspective qui défile en bas de l'écran.
	Au démarrage, le néon "grésille" puis s'allume (comme un vrai tube),
	et l'interface passe en mode sombre (ctx.SetDarkMode). Pendant un
	Dopamine Rush, tout s'accélère et devient plus vif.

	v3 : si le joueur a équipé un thème (autre que "Classique"), le fond
	néon devient un peu translucide pour laisser deviner le thème acheté.
	À l'arrêt, le mode sombre suit de nouveau le thème (un thème sombre
	reste sombre).
]]

local NeonMode = {}
NeonMode.Slot = "Background"

local ORB_COUNT = 10
local STAR_COUNT = 14
local H_LINES = 9 -- lignes horizontales de la grille
local V_LINES = 7 -- lignes "fuyantes" de chaque côté du centre
local HORIZON = 0.64 -- hauteur de l'horizon (fraction de l'écran)

local BASE_TOP = Color3.fromRGB(18, 6, 40)
local BASE_MID = Color3.fromRGB(44, 10, 78)
local BASE_BOTTOM = Color3.fromRGB(6, 18, 48)
local THEMED_TRANSPARENCY = 0.22 -- transparence du fond néon au-dessus d'un thème acheté

-- Thème équipé (table de Config.Themes) ou nil
local function equippedTheme(ctx): any
	local data = ctx.State.Data
	local themes = data and data.Themes
	local id = themes and themes.Equipped
	return type(id) == "string" and ctx.Config.ThemesById[id] or nil
end

function NeonMode.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Create = UIUtil.Create
	local container: Frame = ctx.Container
	local random = Random.new()

	local pink = Color3.fromRGB(255, 46, 136)
	local purple = Color3.fromRGB(157, 78, 221)
	local cyan = Color3.fromRGB(0, 240, 255)
	local orbColors = { pink, cyan, purple }

	ctx.SetDarkMode(true)

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function rushActive(): boolean
		local rush = ctx.State.Rush
		return type(rush) == "table" and rush.Active == true
	end

	------------------------------------------------------------------
	-- Fond dégradé
	------------------------------------------------------------------
	local frame = Create("Frame", {
		Name = "Neon",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), -- blanc : le dégradé donne les couleurs
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = container,
	})
	local gradient = UIUtil.Gradient(frame, ColorSequence.new({
		ColorSequenceKeypoint.new(0, BASE_TOP),
		ColorSequenceKeypoint.new(0.5, BASE_MID),
		ColorSequenceKeypoint.new(1, BASE_BOTTOM),
	}), 45)

	-- Tout ce qui doit apparaître en fondu : { objet, propriété, valeur cible }
	local fades = {}
	local function addFade(instance: Instance, property: string, target: number)
		table.insert(fades, { instance, property, target })
		local object: any = instance
		object[property] = 1
	end

	------------------------------------------------------------------
	-- Orbes lumineux (comme la v1)
	------------------------------------------------------------------
	local orbs = {}
	local orbCount = effectsOn() and ORB_COUNT or math.floor(ORB_COUNT / 2)
	for _ = 1, orbCount do
		local size = random:NextInteger(140, 340)
		local orb = Create("Frame", {
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 1)),
			BackgroundColor3 = orbColors[random:NextInteger(1, #orbColors)],
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = frame,
		})
		UIUtil.Corner(orb, UDim.new(1, 0))
		-- Bord qui s'efface (faux dégradé radial)
		Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = random:NextInteger(0, 360),
			Parent = orb,
		})
		addFade(orb, "BackgroundTransparency", random:NextNumber(0.7, 0.82))
		table.insert(orbs, orb)
	end

	-- Chaque orbe dérive vers un point au hasard, encore et encore
	for _, orb in ipairs(orbs) do
		task.spawn(function()
			while ctx.IsAlive() and orb.Parent do
				local duration = random:NextNumber(6, 12) / (rushActive() and 3 or 1)
				UIUtil.Tween(orb, duration, {
					Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 0.9)),
				}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(duration)
			end
		end)
	end

	------------------------------------------------------------------
	-- Étoiles
	------------------------------------------------------------------
	local stars = {}
	for _ = 1, STAR_COUNT do
		local size = random:NextInteger(2, 4)
		local star = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0.02, 0.98), random:NextNumber(0.06, HORIZON - 0.12)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = frame,
		})
		UIUtil.Corner(star, UDim.new(1, 0))
		table.insert(stars, { Frame = star, Phase = random:NextNumber(0, math.pi * 2), Speed = random:NextNumber(1.5, 4) })
	end

	------------------------------------------------------------------
	-- Horizon + grille rétro
	------------------------------------------------------------------
	local horizonGlow = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundColor3 = pink,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = frame,
	})
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.55),
		}),
		Parent = horizonGlow,
	})
	addFade(horizonGlow, "BackgroundTransparency", 0)

	local horizonLine = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = pink,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = frame,
	})
	Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(1, 0.9),
		}),
		Parent = horizonLine,
	})
	addFade(horizonLine, "BackgroundTransparency", 0)

	local grid = Create("Frame", {
		Name = "Grid",
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.fromScale(1, 1 - HORIZON),
		BackgroundColor3 = Color3.fromRGB(10, 0, 24),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = frame,
	})
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Parent = grid,
	})
	addFade(grid, "BackgroundTransparency", 0)

	local hLines = {}
	for index = 1, H_LINES do
		local line = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = pink,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = grid,
		})
		hLines[index] = line
	end

	local vLines = {}
	for k = -V_LINES, V_LINES do
		local line = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = pink,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = grid,
		})
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.95),
				NumberSequenceKeypoint.new(1, 0.35),
			}),
			Parent = line,
		})
		addFade(line, "BackgroundTransparency", 0)
		table.insert(vLines, { Frame = line, K = k })
	end

	-- Lignes fuyantes : partent du centre de l'horizon vers le bas.
	-- Calcul en "hauteurs de grille" (le rapport largeur/hauteur ne dépend
	-- pas de l'échelle de l'écran).
	local function layoutGrid()
		local absolute = grid.AbsoluteSize
		if absolute.Y < 1 then
			return
		end
		local aspect = absolute.X / absolute.Y
		for _, entry in ipairs(vLines) do
			local dx = entry.K * aspect * 0.2
			local length = math.sqrt(dx * dx + 1)
			local mid = aspect / 2 + dx / 2
			entry.Frame.Size = UDim2.new(0, 2, length, 0)
			entry.Frame.Position = UDim2.fromScale(mid / aspect, 0.5)
			entry.Frame.Rotation = -math.deg(math.atan2(dx, 1))
		end
	end
	layoutGrid()
	ctx.Connect(grid:GetPropertyChangedSignal("AbsoluteSize"), layoutGrid)

	------------------------------------------------------------------
	-- Allumage : le tube néon grésille puis s'allume
	------------------------------------------------------------------
	local brightness = 0 -- 0 = éteint, 1 = allumé (multiplie les transparences)
	local baseTransparency = 0 -- 0 = néon opaque ; > 0 au-dessus d'un thème acheté
	local function applyBrightness(value: number)
		brightness = value
		frame.BackgroundTransparency = 1 - value * (1 - baseTransparency)
		for _, fade in ipairs(fades) do
			local instance = fade[1]
			if instance.Parent then
				local object: any = instance
				object[fade[2]] = 1 - (1 - fade[3]) * value
			end
		end
	end

	-- Thème acheté : on le laisse deviner sous le néon
	local function refreshThemeBlend()
		local theme = equippedTheme(ctx)
		local target = (theme and theme.Id ~= "Classic") and THEMED_TRANSPARENCY or 0
		if target ~= baseTransparency then
			baseTransparency = target
			applyBrightness(brightness)
		end
	end
	ctx.Connect(ctx.State.Changed, refreshThemeBlend)
	refreshThemeBlend()

	task.spawn(function()
		local steps = { 0.3, 0.05, 0.7, 0.2, 0.9, 0.5, 1 }
		for _, value in ipairs(steps) do
			if not ctx.IsAlive() then
				return
			end
			applyBrightness(value)
			task.wait(0.07)
		end
		-- Fondu final vers la pleine luminosité
		if ctx.IsAlive() then
			applyBrightness(1)
		end
	end)

	------------------------------------------------------------------
	-- Animation (dégradé, étoiles, grille)
	------------------------------------------------------------------
	local time = 0
	local gridScroll = 0
	ctx.OnRender(function(dt: number)
		local rush = rushActive()
		local speed = rush and 4 or 1
		time += dt * speed

		gradient.Rotation = (45 + time * 8) % 360
		gradient.Offset = Vector2.new(math.sin(time * 0.3) * 0.25, math.cos(time * 0.2) * 0.25)

		local pulse = (math.sin(time * 0.5) + 1) / 2
		local top = BASE_TOP:Lerp(pink, rush and 0.4 or pulse * 0.22)
		local mid = BASE_MID:Lerp(purple, pulse * 0.3)
		local bottom = BASE_BOTTOM:Lerp(cyan, rush and 0.35 or (1 - pulse) * 0.22)
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(0.5, mid),
			ColorSequenceKeypoint.new(1, bottom),
		})

		-- Étoiles qui scintillent
		for _, star in ipairs(stars) do
			local twinkle = (math.sin(time * star.Speed + star.Phase) + 1) / 2
			star.Frame.BackgroundTransparency = 1 - (0.25 + twinkle * 0.65) * brightness
		end

		-- Grille : les lignes horizontales avancent vers le joueur
		gridScroll = (gridScroll + dt * speed * 0.22) % 1
		local lineColor = pink:Lerp(cyan, (math.sin(time * 0.4) + 1) / 4)
		for index, line in ipairs(hLines) do
			local z = ((index - 1) / H_LINES + gridScroll) % 1
			local y = z ^ 2.1
			line.Position = UDim2.fromScale(0, y)
			line.BackgroundTransparency = 1 - (0.15 + z * 0.6) * brightness
			line.BackgroundColor3 = lineColor
		end
		for _, entry in ipairs(vLines) do
			entry.Frame.BackgroundColor3 = lineColor
		end
		horizonLine.BackgroundColor3 = lineColor
	end)

	-- Petit flash rose à l'allumage
	ctx.Effects.Flash(pink, 0.25)
end

function NeonMode.Stop(ctx)
	-- Le néon ne demande plus le mode sombre...
	ctx.SetDarkMode(false)
	-- ... mais un thème sombre le garde : on recalcule depuis le thème
	-- (après le gestionnaire de stimuli, qui recalcule aussi le mode sombre)
	local State = ctx.State
	task.defer(function()
		local theme = equippedTheme(ctx)
		State.SetDarkMode((theme ~= nil and theme.Dark == true) or State.HasFeature("NeonMode"))
	end)
end

return NeonMode
