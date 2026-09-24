--[[
	DVD (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > DVD

	Les logos "DOPA" qui rebondissent partout sur l'écran, façon vieil
	écran de veille (logo 100 % original dessiné en code : un disque
	brillant qui tourne + "DOPA" + une pastille "DISQUE").
	  - Trajectoires données par le SERVEUR (ClientState.DVDSetup) et
	    calculées avec DVDMath depuis l'heure serveur : fluide et identique
	    quel que soit le nombre d'images par seconde.
	  - À chaque rebond : nouvelle couleur, petit écrasement, "+X" flottant
	    (purement visuel, le serveur compte les rebonds lui-même) et son
	    "Bounce" si l'amélioration "DVDSound" est possédée.
	  - Coin touché : on prévient le serveur (DVDCorner), qui VÉRIFIE.
	  - Clic sur un logo : bonus (DVDClick), temps de recharge commun à
	    tous les logos (ils pâlissent pendant la recharge).
	  - Envoie la taille réelle du logo au serveur (DVDResize).
]]

local DVD = {}
DVD.Slot = "Overlay"

local RESIZE_INTERVAL = 0.6 -- temps minimum entre deux envois DVDResize
local COOLDOWN_FADE = 0.55 -- transparence des logos pendant la recharge
local MIN_SOUND_GAP = 0.07 -- évite la cacophonie avec 10 logos

-- Petites phrases quand un logo frôle un coin sans le toucher
local NEAR_MISS = { "presque... 😩", "à un pixel !", "noooon 😭", "si près...", "la prochaine ?", "argh !" }
local CORNER_TEXTS = { "COIN !!! 📀", "DANS LE COIN !!!", "PILE DANS LE COIN !" }

function DVD.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Config = ctx.Config
	local DVDMath = ctx.DVDMath
	local settings = Config.DVD
	local colors = settings.Colors
	local container: Frame = ctx.Container
	local random = Random.new()

	local logoSize: Vector2 = settings.LogoSize
	local useImage = settings.LogoImage ~= nil and settings.LogoImage ~= ""

	local logos = {} -- [index] = objet logo (voir createLogo)
	local cooldownUntil = 0
	local cooling = false
	local lastSoundTime = 0

	local function getData()
		return ctx.State.Data
	end

	local function effectsOn(): boolean
		local data = getData()
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Sonde invisible de la taille d'un logo (sert à mesurer la taille réelle,
	-- sans être faussée par les animations d'écrasement)
	local probe = UIUtil.Create("Frame", {
		Name = "SizeProbe",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(logoSize.X, logoSize.Y),
		Visible = false,
		Parent = container,
	})

	-- Taille du logo en fraction de l'écran
	local function measure(): (number?, number?)
		local parentSize = container.AbsoluteSize
		local size = probe.AbsoluteSize
		if parentSize.X < 1 or parentSize.Y < 1 or size.X < 1 or size.Y < 1 then
			return nil, nil
		end
		return size.X / parentSize.X, size.Y / parentSize.Y
	end

	------------------------------------------------------------------
	-- Construction d'un logo
	------------------------------------------------------------------
	local function createLogo(index: number)
		local logo = {
			Index = index,
			Params = nil :: any,
			LastX = nil :: number?,
			LastY = nil :: number?,
			ColorIndex = ((index - 1) % #colors) + 1,
			Fades = {} :: { { any } }, -- { instance, propriété, valeur normale }
		}
		local color = colors[logo.ColorIndex]

		local button = UIUtil.Create("TextButton", {
			Name = "DVDLogo" .. index,
			Size = UDim2.fromOffset(logoSize.X, logoSize.Y),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Visible = false,
			ZIndex = 5,
			Parent = container,
		})

		-- Corps visuel (le bouton garde sa taille, seul le corps s'écrase)
		local body = UIUtil.Create("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 5,
			Parent = button,
		})
		local bodyScale = UIUtil.Create("UIScale", { Scale = 0, Parent = body })
		logo.Button = button
		logo.Body = body
		logo.Scale = bodyScale

		if useImage then
			-- Image personnalisée (blanche, recolorée)
			local image = UIUtil.Create("ImageLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = settings.LogoImage,
				ImageColor3 = color,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 6,
				Parent = body,
			})
			logo.Image = image
			table.insert(logo.Fades, { image, "ImageTransparency", 0 })
		else
			-- Disque brillant (à gauche)
			local discSize = math.floor(logoSize.Y * 0.78)
			local disc = UIUtil.Create("Frame", {
				Name = "Disc",
				Size = UDim2.fromOffset(discSize, discSize),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 2, 0.5, 0),
				BackgroundColor3 = color,
				ZIndex = 6,
				Parent = body,
			})
			UIUtil.Corner(disc, UDim.new(1, 0))
			local discStroke = UIUtil.Stroke(disc, Theme.Colors.Border, 2, 0.15)
			-- Reflet arc-en-ciel qui tourne (effet "disque")
			local shine = UIUtil.Gradient(disc, ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.35, Color3.fromRGB(190, 190, 190)),
				ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.65, Color3.fromRGB(200, 200, 200)),
				ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
			}), 0)
			-- Sillon du disque
			local groove = UIUtil.Create("Frame", {
				Size = UDim2.fromScale(0.62, 0.62),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 7,
				Parent = disc,
			})
			UIUtil.Corner(groove, UDim.new(1, 0))
			local grooveStroke = UIUtil.Stroke(groove, Color3.new(1, 1, 1), 2, 0.45)
			-- Trou central
			local hole = UIUtil.Create("Frame", {
				Size = UDim2.fromScale(0.24, 0.24),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 8,
				Parent = disc,
			})
			UIUtil.Corner(hole, UDim.new(1, 0))
			local holeStroke = UIUtil.Stroke(hole, Theme.Colors.Border, 1.5, 0.2)

			-- "DOPA" en gros
			local textLeft = discSize + 6
			local title = UIUtil.Label({
				Name = "Title",
				Text = "DOPA",
				Font = Theme.Fonts.Title,
				TextColor3 = color,
				Size = UDim2.new(1, -textLeft, 0.6, 0),
				Position = UDim2.new(0, textLeft, 0.02, 0),
				MaxTextSize = 44,
				ZIndex = 6,
				Parent = body,
			})
			local titleStroke = UIUtil.Stroke(title, Theme.Colors.Border, 2, 0.1)
			titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

			-- Pastille "DISQUE"
			local pill = UIUtil.Create("Frame", {
				Name = "Pill",
				Size = UDim2.new(1, -textLeft - 2, 0.3, 0),
				Position = UDim2.new(0, textLeft, 0.64, 0),
				BackgroundColor3 = color,
				ZIndex = 6,
				Parent = body,
			})
			UIUtil.Corner(pill, UDim.new(1, 0))
			local pillStroke = UIUtil.Stroke(pill, Theme.Colors.Border, 1.5, 0.15)
			local pillText = UIUtil.Label({
				Text = "DISQUE",
				Font = Theme.Fonts.Title,
				TextColor3 = Theme.ContrastText(color),
				Size = UDim2.fromScale(0.9, 0.85),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				MaxTextSize = 16,
				ZIndex = 7,
				Parent = pill,
			})

			logo.Disc = disc
			logo.Shine = shine
			logo.Title = title
			logo.Pill = pill
			logo.PillText = pillText
			table.insert(logo.Fades, { disc, "BackgroundTransparency", 0 })
			table.insert(logo.Fades, { discStroke, "Transparency", 0.15 })
			table.insert(logo.Fades, { grooveStroke, "Transparency", 0.45 })
			table.insert(logo.Fades, { hole, "BackgroundTransparency", 0 })
			table.insert(logo.Fades, { holeStroke, "Transparency", 0.2 })
			table.insert(logo.Fades, { title, "TextTransparency", 0 })
			table.insert(logo.Fades, { titleStroke, "Transparency", 0.1 })
			table.insert(logo.Fades, { pill, "BackgroundTransparency", 0 })
			table.insert(logo.Fades, { pillStroke, "Transparency", 0.15 })
			table.insert(logo.Fades, { pillText, "TextTransparency", 0 })
		end

		-- Survol : le logo gonfle un peu (PC)
		ctx.Connect(button.MouseEnter, function()
			if not cooling then
				UIUtil.Tween(bodyScale, 0.15, { Scale = 1.08 }, Enum.EasingStyle.Back)
			end
		end)
		ctx.Connect(button.MouseLeave, function()
			UIUtil.Tween(bodyScale, 0.15, { Scale = 1 })
		end)

		-- Clic : bonus avec temps de recharge commun
		ctx.Connect(button.Activated, function()
			if not ctx.IsAlive() then
				return
			end
			local center = UDim2.new(button.Position.X.Scale, logoSize.X / 2, button.Position.Y.Scale, logoSize.Y / 2)
			if os.clock() < cooldownUntil then
				-- Encore en recharge : petit "non" et le temps restant
				UIUtil.Shake(body)
				ctx.FloatText(container, center, "⏳ " .. math.ceil(cooldownUntil - os.clock()) .. " s", Theme.Colors.TextDim, 20)
				return
			end
			cooldownUntil = os.clock() + settings.ClickCooldown
			ctx.Net.Event("DVDClick"):FireServer(logo.Index)
			ctx.Sound.Play("Click", 1.3)
			bodyScale.Scale = 0.8
			UIUtil.Tween(bodyScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			if effectsOn() then
				ctx.Effects.Burst(container, center, colors[logo.ColorIndex], 14)
			end
		end)

		return logo
	end

	-- Applique une couleur à tout le logo (petite transition)
	local function applyColor(logo, color: Color3)
		if logo.Image then
			UIUtil.Tween(logo.Image, 0.15, { ImageColor3 = color })
			return
		end
		UIUtil.Tween(logo.Disc, 0.15, { BackgroundColor3 = color })
		UIUtil.Tween(logo.Title, 0.15, { TextColor3 = color })
		UIUtil.Tween(logo.Pill, 0.15, { BackgroundColor3 = color })
		logo.PillText.TextColor3 = Theme.ContrastText(color)
	end

	local function nextColor(logo)
		-- Jamais deux fois la même couleur de suite
		local newIndex = random:NextInteger(1, #colors)
		if newIndex == logo.ColorIndex then
			newIndex = newIndex % #colors + 1
		end
		logo.ColorIndex = newIndex
		applyColor(logo, colors[newIndex])
	end

	local function setFaded(faded: boolean)
		for _, logo in ipairs(logos) do
			for _, entry in ipairs(logo.Fades) do
				local target = faded and math.max(entry[3], COOLDOWN_FADE) or entry[3]
				UIUtil.Tween(entry[1], 0.25, { [entry[2]] = target })
			end
		end
	end

	------------------------------------------------------------------
	-- Envoi de la taille au serveur (limité à 1 envoi / 0,6 s)
	------------------------------------------------------------------
	local lastSentW, lastSentH = 0, 0
	local lastSendTime = -math.huge
	local pendingSend = false
	local pendingForce = false

	local function sendSize(force: boolean)
		if not ctx.IsAlive() or #logos == 0 then
			return
		end
		local w, h = measure()
		if not w or not h then
			return
		end
		if not force and math.abs(w - lastSentW) < 0.002 and math.abs(h - lastSentH) < 0.002 then
			return
		end
		lastSentW, lastSentH = w, h
		lastSendTime = os.clock()
		ctx.Net.Event("DVDResize"):FireServer(w, h)
	end

	local function requestSend(force: boolean)
		pendingForce = pendingForce or force
		if pendingSend then
			return
		end
		local wait = RESIZE_INTERVAL - (os.clock() - lastSendTime)
		pendingSend = true
		-- Toujours un petit délai : laisse le temps aux tailles de se stabiliser
		task.delay(math.max(0.1, wait), function()
			pendingSend = false
			local f = pendingForce
			pendingForce = false
			sendSize(f)
		end)
	end

	------------------------------------------------------------------
	-- Synchronisation avec DVDSetup
	------------------------------------------------------------------
	local function applySetup(setup)
		if not ctx.IsAlive() then
			return
		end
		local list = (setup and setup.Logos) or {}
		local previousCount = #logos

		-- Crée les logos manquants
		for index = #logos + 1, #list do
			local logo = createLogo(index)
			logos[index] = logo
			UIUtil.Tween(logo.Scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			if cooling then
				for _, entry in ipairs(logo.Fades) do
					(entry[1] :: any)[entry[2]] = math.max(entry[3], COOLDOWN_FADE)
				end
			end
		end
		-- Retire les logos en trop
		for index = #logos, #list + 1, -1 do
			local logo = logos[index]
			logos[index] = nil
			local button = logo.Button
			UIUtil.Tween(logo.Scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.delay(0.3, function()
				button:Destroy()
			end)
		end
		-- Nouveaux paramètres de trajectoire
		for index, params in ipairs(list) do
			local logo = logos[index]
			logo.Params = params
			logo.LastX, logo.LastY = nil, nil
			logo.Button.Visible = true
		end

		if #list > 0 then
			-- Premier logo (ou retour après la détox) : on envoie la vraie taille
			-- si le serveur utilise une taille différente
			local w, h = measure()
			local first = list[1]
			local mismatch = w ~= nil
				and h ~= nil
				and type(first.W) == "number"
				and type(first.H) == "number"
				and (math.abs(first.W - w) > 0.003 or math.abs(first.H - h) > 0.003)
			requestSend(previousCount == 0 and mismatch)
		end
	end

	ctx.Connect(ctx.State.DVDSetupChanged, applySetup)
	ctx.Connect(container:GetPropertyChangedSignal("AbsoluteSize"), function()
		requestSend(false)
	end)
	applySetup(ctx.State.DVDSetup)

	------------------------------------------------------------------
	-- Rebonds (visuels)
	------------------------------------------------------------------
	local function onBounce(logo, x: number, y: number, w: number, h: number, bouncedX: boolean, bouncedY: boolean)
		nextColor(logo)

		-- Écrasement contre le mur
		local scale = logo.Scale
		scale.Scale = bouncedX and 0.88 or 0.92
		UIUtil.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

		-- Point de contact (au milieu du bord touché)
		local contactX = x + w / 2
		local contactY = y + h / 2
		if bouncedX then
			contactX = (x < 0.5 - w / 2) and x or (x + w)
		end
		if bouncedY and not bouncedX then
			contactY = (y < 0.5 - h / 2) and y or (y + h)
		end

		local data = getData()
		local value = data and data.BounceValue or 0
		if value > 0 then
			ctx.FloatText(
				container,
				UDim2.fromScale(x + w / 2, y + h / 2),
				"+" .. ctx.Format.Format(value),
				colors[logo.ColorIndex],
				24
			)
		end
		if effectsOn() then
			ctx.Effects.Burst(container, UDim2.fromScale(contactX, contactY), colors[logo.ColorIndex], 4)
		end

		if ctx.HasFeature("DVDSound") then
			local now = os.clock()
			if now - lastSoundTime >= MIN_SOUND_GAP then
				lastSoundTime = now
				ctx.Sound.Play("Bounce", random:NextNumber(1.25, 1.75))
			end
		end
	end

	local function onCorner(logo, x: number, y: number, w: number, h: number)
		local center = UDim2.fromScale(x + w / 2, y + h / 2)
		ctx.FloatText(container, center, CORNER_TEXTS[random:NextInteger(1, #CORNER_TEXTS)], Theme.Colors.Gold, 44)
		if effectsOn() then
			ctx.Effects.Burst(container, center, Theme.Colors.Gold, 30)
			ctx.Effects.Burst(container, center, nil, 20)
		end
		local scale = logo.Scale
		scale.Scale = 1.5
		UIUtil.Tween(scale, 0.6, { Scale = 1 }, Enum.EasingStyle.Elastic)
	end

	------------------------------------------------------------------
	-- Boucle d'affichage
	------------------------------------------------------------------
	local tolerance = settings.CornerTolerance
	ctx.OnRender(function()
		if #logos == 0 then
			return
		end
		local t = workspace:GetServerTimeNow()
		local w, h = measure()
		w = w or (logoSize.X / 1280)
		h = h or (logoSize.Y / 720)

		-- Fin de la recharge : les logos reprennent leurs couleurs
		local isCooling = os.clock() < cooldownUntil
		if isCooling ~= cooling then
			cooling = isCooling
			setFaded(isCooling)
			if not isCooling then
				for _, logo in ipairs(logos) do
					logo.Scale.Scale = 1.15
					UIUtil.Tween(logo.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				end
			end
		end

		for index, logo in ipairs(logos) do
			local params = logo.Params
			if params then
				local x, y = DVDMath.Position(params, t)
				logo.Button.Position = UDim2.fromScale(x, y)
				if logo.Shine then
					logo.Shine.Rotation = (t * 140 + index * 50) % 360
				end

				local indexX, indexY = DVDMath.BounceIndex(params, t)
				local lastX, lastY = logo.LastX, logo.LastY
				local bouncedX = lastX ~= nil and indexX ~= lastX
				local bouncedY = lastY ~= nil and indexY ~= lastY

				if bouncedX or bouncedY then
					onBounce(logo, x, y, w, h, bouncedX, bouncedY)
				end

				if bouncedX and lastX then
					-- Numéro du bord touché = le plus grand des deux segments
					local k = math.max(indexX, lastX)
					if DVDMath.IsCornerAtBounceX(params, k, tolerance) then
						ctx.Net.Event("DVDCorner"):FireServer(index, k)
						onCorner(logo, x, y, w, h)
					else
						-- Frôlé ? (à moins de 3 % d'un coin)
						local _, rangeY = DVDMath.Ranges(params)
						if math.min(y, rangeY - y) < 0.03 then
							ctx.FloatText(
								container,
								UDim2.fromScale(x + w / 2, y + h / 2 + 0.06),
								NEAR_MISS[random:NextInteger(1, #NEAR_MISS)],
								Theme.Colors.TextDim,
								22
							)
						end
					end
				end

				logo.LastX, logo.LastY = indexX, indexY
			end
		end
	end)

	------------------------------------------------------------------
	-- Bonus confirmé par le serveur : "+X" au niveau du logo cliqué
	------------------------------------------------------------------
	ctx.OnBonus("DVD", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local logo = logos[tonumber(payload.Index) or 1] or logos[1]
		local position = UDim2.fromScale(0.5, 0.4)
		if logo then
			local button = logo.Button
			position = UDim2.new(button.Position.X.Scale, logoSize.X / 2, button.Position.Y.Scale, 0)
		end
		-- (le son "Bonus" est déjà joué par StimulusManager)
		ctx.FloatText(container, position, "+" .. ctx.Format.Format(tonumber(payload.Amount) or 0), Theme.Colors.Gold, 40)
	end)
end

function DVD.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return DVD
