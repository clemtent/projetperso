--[[
	DVD (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > DVD

	Les logos "DOPA" qui rebondissent partout sur l'écran, façon vieil
	écran de veille. Logo 100 % original dessiné en code, style "badge"
	premium : une plaque sombre vernie avec un liseré lumineux, un disque
	brillant (anneau holographique qui tourne + reflet de lumière qui
	passe), le mot "DOPA" en gras (dégradé + contour) et une pastille
	"VIDÉO". Chaque logo a sa propre plaque opaque : quand plusieurs logos
	se croisent, ils passent proprement l'un devant l'autre (lisibles).
	  - Trajectoires données par le SERVEUR (ClientState.DVDSetup) et
	    calculées avec DVDMath depuis l'heure serveur : fluide et identique
	    quel que soit le nombre d'images par seconde.
	  - Traînée : 2 "fantômes" colorés placés sur la trajectoire un peu
	    plus tôt (DVDMath), halo coloré autour de la plaque.
	  - À chaque rebond : nouvelle couleur, écrasement contre le mur, flash
	    du halo, "+X" flottant (purement visuel, le serveur compte les
	    rebonds lui-même) et son "Bounce" si "DVDSound" est possédé.
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
local TRAIL_LAG = 0.07 -- retard (s) de chaque fantôme de la traînée
local TRAIL_ALPHA = { 0.8, 0.9 } -- transparence des 2 fantômes
local GLOW_ALPHA = 0.8 -- transparence normale du halo

local PLATE_COLOR = Color3.fromRGB(64, 56, 108) -- haut de la plaque (le bas est assombri)
local INK = Color3.fromRGB(18, 14, 34) -- contours sombres
local WHITE = Color3.new(1, 1, 1)

-- Petites phrases quand un logo frôle un coin sans le toucher
local NEAR_MISS = { "presque... 😩", "à un pixel !", "noooon 😭", "si près...", "la prochaine ?", "argh !" }
local CORNER_TEXTS = { "COIN !!! 📀", "DANS LE COIN !!!", "PILE DANS LE COIN !" }

-- Reflet "holographique" de l'anneau du disque
local HOLO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 200)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 240, 150)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 255, 220)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(140, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 200)),
})

-- Bande de lumière (le reste est invisible) : on fait glisser son Offset
local SWEEP = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.4, 1),
	NumberSequenceKeypoint.new(0.5, 0.35),
	NumberSequenceKeypoint.new(0.6, 1),
	NumberSequenceKeypoint.new(1, 1),
})

-- Ombrage vertical "multiplié" sur la couleur de fond (clair en haut)
local function shade(bottom: number): ColorSequence
	return ColorSequence.new(WHITE, Color3.new(bottom, bottom, bottom))
end

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
	local W, H = logoSize.X, logoSize.Y

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

	-- Couleur du mot "DOPA" : la couleur du logo, éclaircie pour rester lisible
	local function inkFor(color: Color3): Color3
		return color:Lerp(WHITE, 0.3)
	end

	-- Élément centré sur (cx, cy) en pixels du logo, mais exprimé en
	-- proportions : l'écrasement (taille du corps) déforme tout le dessin
	local function place(props: { [string]: any }, cx: number, cy: number, w: number, h: number): { [string]: any }
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.fromScale(cx / W, cy / H)
		props.Size = UDim2.fromScale(w / W, h / H)
		if props.BorderSizePixel == nil then
			props.BorderSizePixel = 0
		end
		return props
	end

	-- Sonde invisible de la taille d'un logo (sert à mesurer la taille réelle,
	-- sans être faussée par les animations d'écrasement)
	local probe = UIUtil.Create("Frame", {
		Name = "SizeProbe",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(W, H),
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
			Ghosts = {} :: { Frame },
			Tinted = {} :: { { any } }, -- { instance, propriété } recolorés à chaque rebond
		}
		local color = colors[logo.ColorIndex]

		-- Traînée : 2 fantômes derrière tous les logos (ZIndex plus bas)
		for k = 1, #TRAIL_ALPHA do
			local ghost = UIUtil.Create("Frame", {
				Name = "DVDTrail" .. index .. "_" .. k,
				Size = UDim2.fromOffset(W, H),
				BackgroundColor3 = color,
				BackgroundTransparency = TRAIL_ALPHA[k],
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 2,
				Parent = container,
			})
			UIUtil.Corner(ghost, 18)
			logo.Ghosts[k] = ghost
			table.insert(logo.Tinted, { ghost, "BackgroundColor3" })
		end

		-- Racine = simple Frame (ne capte pas les clics) ; la zone cliquable
		-- est un bouton enfant "Hit", masqué pendant la recharge pour que les
		-- clics passent au bouton principal / aux cartes en dessous.
		local button = UIUtil.Create("Frame", {
			Name = "DVDLogo" .. index,
			Size = UDim2.fromOffset(W, H),
			BackgroundTransparency = 1,
			Active = false,
			Visible = false,
			ZIndex = 5,
			Parent = container,
		})
		local hit = UIUtil.Create("TextButton", {
			Name = "Hit",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Visible = not cooling,
			ZIndex = 9,
			Parent = button,
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
		logo.Hit = hit
		logo.Body = body
		logo.Scale = bodyScale

		-- Halo coloré (déborde un peu de la plaque, flashe à chaque rebond)
		local glow = UIUtil.Create("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 14, 1, 14),
			BackgroundColor3 = color,
			BackgroundTransparency = GLOW_ALPHA,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = body,
		})
		UIUtil.Corner(glow, 24)
		logo.Glow = glow
		table.insert(logo.Tinted, { glow, "BackgroundColor3" })

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
			table.insert(logo.Tinted, { image, "ImageColor3" })
			table.insert(logo.Fades, { image, "ImageTransparency", 0 })
		else
			-- Plaque vernie (sombre, dégradé vertical, liseré de la couleur du logo)
			local plate = UIUtil.Create("Frame", {
				Name = "Plate",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = PLATE_COLOR,
				BackgroundTransparency = 0.04,
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = body,
			})
			UIUtil.Corner(plate, 18)
			UIUtil.Gradient(plate, shade(0.3), 90)
			local plateStroke = UIUtil.Stroke(plate, color, 2.5, 0.1)
			table.insert(logo.Tinted, { plateStroke, "Color" })

			-- Disque brillant
			local DX, DY, DS = 37, H / 2, 58
			local disc = UIUtil.Create("Frame", place({ Name = "Disc", BackgroundColor3 = color, ZIndex = 3, Parent = body }, DX, DY, DS, DS))
			UIUtil.Corner(disc, UDim.new(1, 0))
			UIUtil.Gradient(disc, shade(0.55), 45)
			local discStroke = UIUtil.Stroke(disc, WHITE, 2, 0.25)
			table.insert(logo.Tinted, { disc, "BackgroundColor3" })

			-- Anneau holographique (dégradé arc-en-ciel sur le contour, qui tourne)
			local ring = UIUtil.Create("Frame", place({ Name = "Ring", BackgroundTransparency = 1, ZIndex = 4, Parent = body }, DX, DY, 38, 38))
			UIUtil.Corner(ring, UDim.new(1, 0))
			local ringStroke = UIUtil.Stroke(ring, WHITE, 5, 0.3)
			local holo = UIUtil.Gradient(ringStroke, HOLO, 0)

			-- Moyeu
			local hub = UIUtil.Create("Frame", place({ Name = "Hub", BackgroundColor3 = INK, ZIndex = 5, Parent = body }, DX, DY, 15, 15))
			UIUtil.Corner(hub, UDim.new(1, 0))
			local hubStroke = UIUtil.Stroke(hub, WHITE, 2, 0.15)

			-- Reflet fixe (en haut à gauche)
			local highlight = UIUtil.Create("Frame", place({
				Name = "Highlight",
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.45,
				Rotation = -35,
				ZIndex = 6,
				Parent = body,
			}, DX - 11, DY - 13, 20, 8))
			UIUtil.Corner(highlight, UDim.new(1, 0))

			-- Balayage de lumière qui traverse le disque de temps en temps
			local sweep = UIUtil.Create("Frame", place({
				Name = "Sweep",
				BackgroundColor3 = WHITE,
				ZIndex = 6,
				Parent = body,
			}, DX, DY, DS, DS))
			UIUtil.Corner(sweep, UDim.new(1, 0))
			local sweepGradient = UIUtil.Create("UIGradient", {
				Transparency = SWEEP,
				Rotation = 25,
				Offset = Vector2.new(-1, 0),
				Parent = sweep,
			})

			-- Mot "DOPA" : ombre portée + texte dégradé avec contour
			local TX, TW = 72 + (W - 76) / 2, W - 76
			local shadowLabel = UIUtil.Label(place({
				Name = "TitleShadow",
				Text = "DOPA",
				Font = Enum.Font.FredokaOne,
				TextColor3 = Color3.new(0, 0, 0),
				TextTransparency = 0.45,
				MaxTextSize = 40,
				ZIndex = 6,
				Parent = body,
			}, TX + 1.5, 30.5, TW, 34))
			local title = UIUtil.Label(place({
				Name = "Title",
				Text = "DOPA",
				Font = Enum.Font.FredokaOne,
				TextColor3 = inkFor(color),
				MaxTextSize = 40,
				ZIndex = 7,
				Parent = body,
			}, TX, 28, TW, 34))
			UIUtil.Gradient(title, shade(0.72), 90)
			local titleStroke = UIUtil.Stroke(title, INK, 2, 0)
			titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

			-- Pastille "VIDÉO"
			local pill = UIUtil.Create("Frame", place({ Name = "Pill", BackgroundColor3 = color, ZIndex = 6, Parent = body }, TX, 60, TW - 10, 17))
			UIUtil.Corner(pill, UDim.new(1, 0))
			UIUtil.Gradient(pill, shade(0.7), 90)
			local pillStroke = UIUtil.Stroke(pill, WHITE, 1, 0.45)
			local pillText = UIUtil.Label({
				Name = "Text",
				Text = "VIDÉO",
				Font = Theme.Fonts.Title,
				TextColor3 = Theme.ContrastText(color),
				Size = UDim2.fromScale(0.9, 0.9),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				MaxTextSize = 13,
				ZIndex = 7,
				Parent = pill,
			})
			table.insert(logo.Tinted, { pill, "BackgroundColor3" })

			logo.Holo = holo
			logo.Sweep = sweepGradient
			logo.Title = title
			logo.PillText = pillText
			table.insert(logo.Fades, { plate, "BackgroundTransparency", 0.04 })
			table.insert(logo.Fades, { plateStroke, "Transparency", 0.1 })
			table.insert(logo.Fades, { disc, "BackgroundTransparency", 0 })
			table.insert(logo.Fades, { discStroke, "Transparency", 0.25 })
			table.insert(logo.Fades, { ringStroke, "Transparency", 0.3 })
			table.insert(logo.Fades, { hub, "BackgroundTransparency", 0 })
			table.insert(logo.Fades, { hubStroke, "Transparency", 0.15 })
			table.insert(logo.Fades, { highlight, "BackgroundTransparency", 0.45 })
			table.insert(logo.Fades, { sweep, "BackgroundTransparency", 0 })
			table.insert(logo.Fades, { shadowLabel, "TextTransparency", 0.45 })
			table.insert(logo.Fades, { title, "TextTransparency", 0 })
			table.insert(logo.Fades, { titleStroke, "Transparency", 0 })
			table.insert(logo.Fades, { pill, "BackgroundTransparency", 0 })
			table.insert(logo.Fades, { pillStroke, "Transparency", 0.45 })
			table.insert(logo.Fades, { pillText, "TextTransparency", 0 })
		end

		-- Survol : le logo gonfle un peu (PC)
		ctx.Connect(hit.MouseEnter, function()
			if not cooling then
				UIUtil.Tween(bodyScale, 0.15, { Scale = 1.08 }, Enum.EasingStyle.Back)
			end
		end)
		ctx.Connect(hit.MouseLeave, function()
			UIUtil.Tween(bodyScale, 0.15, { Scale = 1 })
		end)

		-- Clic : bonus avec temps de recharge commun
		ctx.Connect(hit.Activated, function()
			if not ctx.IsAlive() then
				return
			end
			local center = UDim2.new(button.Position.X.Scale, W / 2, button.Position.Y.Scale, H / 2)
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
		for _, entry in ipairs(logo.Tinted) do
			UIUtil.Tween(entry[1], 0.15, { [entry[2]] = color })
		end
		if logo.Title then
			UIUtil.Tween(logo.Title, 0.15, { TextColor3 = inkFor(color) })
		end
		if logo.PillText then
			logo.PillText.TextColor3 = Theme.ContrastText(color)
		end
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
			-- Pendant la recharge, les logos ne captent plus les clics
			logo.Hit.Visible = not faded
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
			local ghosts = logo.Ghosts
			UIUtil.Tween(logo.Scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			for _, ghost in ipairs(ghosts) do
				ghost.Visible = false
			end
			task.delay(0.3, function()
				button:Destroy()
				for _, ghost in ipairs(ghosts) do
					ghost:Destroy()
				end
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

		-- Écrasement contre le mur (le corps s'aplatit puis reprend sa forme)
		local body = logo.Body
		if bouncedX and bouncedY then
			body.Size = UDim2.fromScale(0.88, 0.88)
		elseif bouncedX then
			body.Size = UDim2.fromScale(0.82, 1.1)
		else
			body.Size = UDim2.fromScale(1.1, 0.8)
		end
		UIUtil.Tween(body, 0.4, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)

		-- Flash du halo
		local glow = logo.Glow
		glow.BackgroundTransparency = 0.35
		UIUtil.Tween(glow, 0.5, { BackgroundTransparency = GLOW_ALPHA })

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
		local glow = logo.Glow
		glow.BackgroundColor3 = Theme.Colors.Gold
		glow.BackgroundTransparency = 0.1
		UIUtil.Tween(glow, 1.2, { BackgroundTransparency = GLOW_ALPHA, BackgroundColor3 = colors[logo.ColorIndex] })
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
		w = w or (W / 1280)
		h = h or (H / 720)

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

		-- Traînée seulement si les effets sont activés (et pas en recharge)
		local wantTrail = effectsOn() and not cooling

		for index, logo in ipairs(logos) do
			local params = logo.Params
			if params then
				local x, y = DVDMath.Position(params, t)
				logo.Button.Position = UDim2.fromScale(x, y)

				-- Fantômes : la même trajectoire, un peu plus tôt
				for k, ghost in ipairs(logo.Ghosts) do
					if wantTrail then
						local gx, gy = DVDMath.Position(params, t - k * TRAIL_LAG)
						ghost.Position = UDim2.fromScale(gx, gy)
					end
					if ghost.Visible ~= wantTrail then
						ghost.Visible = wantTrail
					end
				end

				-- Disque : anneau holographique qui tourne + reflet qui passe
				if logo.Holo then
					logo.Holo.Rotation = (t * 120 + index * 50) % 360
				end
				if logo.Sweep then
					local p = (t / 2.8 + index * 0.37) % 1
					logo.Sweep.Offset = Vector2.new(-1 + p * 3.2, 0)
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
			position = UDim2.new(button.Position.X.Scale, W / 2, button.Position.Y.Scale, 0)
		end
		-- (le son "Bonus" est déjà joué par StimulusManager)
		ctx.FloatText(container, position, "+" .. ctx.Format.Format(tonumber(payload.Amount) or 0), Theme.Colors.Gold, 40)
	end)
end

function DVD.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return DVD
