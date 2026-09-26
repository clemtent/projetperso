--[[
	DVD (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > DVD

	Les logos qui rebondissent partout sur l'écran, façon vieil écran de
	veille de lecteur DVD (5 logos au maximum : un par niveau). Le logo est
	dessiné en Frames, dans l'esprit du classique "DVD VIDEO" :
	  - le mot "DVD" en gras italique, couleur du logo, avec un léger
	    vernis (dégradé clair en haut) et un fin contour ;
	  - dessous, le disque aplati (ellipse) brillant : reflet blanc,
	    sillons, anneau holographique qui tourne, et "VIDEO" en creux ;
	  - un halo coloré discret et une traînée (3 silhouettes du logo placées
	    un peu plus tôt sur la même trajectoire).
	Comportement :
	  - trajectoires données par le SERVEUR (ClientState.DVDSetup) et
	    calculées avec DVDMath depuis l'heure serveur : fluide et identique
	    quel que soit le nombre d'images par seconde ;
	  - à chaque rebond : nouvelle couleur, écrasement contre le mur, flash
	    du halo, "+X" flottant (visuel : le serveur compte les rebonds) et son
	    "Bounce" si "DVDSound" est possédé ;
	  - coin touché : on prévient le serveur (DVDCorner), qui VÉRIFIE ; à
	    l'écran, grande fête : ondes de choc depuis le coin, logo qui tourne
	    sur lui-même en arc-en-ciel, confettis, flash doré, "COIN !!!" ;
	  - clic sur un logo : bonus (DVDClick), recharge commune à tous les
	    logos (ils pâlissent pendant la recharge et laissent passer les clics) ;
	  - envoie la taille réelle du logo au serveur (DVDResize).
	Performance : une seule boucle OnRender, aucune création d'instance par
	image (les ondes de choc sont réutilisées).
]]

local DVD = {}
DVD.Slot = "Overlay"

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local WORDMARK = "DVD" -- mot principal du logo
local RESIZE_INTERVAL = 0.6 -- temps minimum entre deux envois DVDResize
local COOLDOWN_FADE = 0.6 -- transparence des logos pendant la recharge
local MIN_SOUND_GAP = 0.07 -- évite la cacophonie avec plusieurs logos
local TRAIL_LAG = 0.055 -- retard (s) de chaque silhouette de la traînée
local TRAIL_ALPHA = { 0.72, 0.83, 0.91 } -- transparence des silhouettes
local GLOW_ALPHA = 0.9 -- transparence normale du halo
local RAINBOW_TIME = 2.6 -- durée de l'arc-en-ciel après un coin
local RING_COUNT = 3 -- ondes de choc réutilisées

local INK = Color3.fromRGB(16, 12, 30) -- lettres "VIDEO" (en creux)
local WHITE = Color3.new(1, 1, 1)

-- Police du mot "DVD" : gras italique
local WORD_FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local VIDEO_FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)

-- Petites phrases quand un logo frôle un coin sans le toucher
local NEAR_MISS = {
	en = { "almost... 😩", "one pixel off!", "noooo 😭", "so close...", "next time?", "argh!", "the corner dodged!" },
	fr = { "presque... 😩", "à un pixel !", "noooon 😭", "si près...", "la prochaine ?", "argh !", "le coin a esquivé !" },
}
local CORNER_TEXTS = {
	en = { "CORNER!!! 📀", "RIGHT IN THE CORNER!!!", "PERFECT CORNER HIT!", "IT HIT THE CORNER!!!" },
	fr = { "COIN !!! 📀", "DANS LE COIN !!!", "PILE DANS LE COIN !", "IL A TOUCHÉ LE COIN !!!" },
}

-- Tire une phrase au hasard dans la liste de la langue du joueur
local function pickLine(variants, random: Random): string
	local list = Locale.Pick(variants)
	return list[random:NextInteger(1, #list)]
end

-- Reflet "holographique" de l'anneau du disque
local HOLO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 200)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 240, 150)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 255, 220)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(140, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 200)),
})

-- Vernis vertical "multiplié" sur la couleur (clair en haut, plus sombre en bas)
local GLOSS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
	ColorSequenceKeypoint.new(0.5, Color3.new(0.93, 0.93, 0.93)),
	ColorSequenceKeypoint.new(1, Color3.new(0.68, 0.68, 0.68)),
})

function DVD.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Config = ctx.Config
	local DVDMath = ctx.DVDMath
	local Effects = ctx.Effects
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
	-- Ondes de choc (fête du coin), réutilisées
	------------------------------------------------------------------
	local rings = {}
	for i = 1, RING_COUNT do
		local ring = UIUtil.Create("Frame", {
			Name = "CornerRing" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 8,
			Parent = container,
		})
		UIUtil.Corner(ring, UDim.new(1, 0))
		local stroke = UIUtil.Stroke(ring, Theme.Colors.Gold, 6, 0)
		table.insert(rings, { Frame = ring, Stroke = stroke, Age = -1, Delay = (i - 1) * 0.14 })
	end

	------------------------------------------------------------------
	-- Construction d'un logo
	------------------------------------------------------------------
	-- Ellipse (le disque aplati) : union de pilules de plus en plus hautes et
	-- étroites (UICorner ne sait faire que des pilules) ; renvoie les pièces
	local DISC_Y = 61
	local DISC_LAYERS = { { W - 22, 9 }, { W - 34, 15 }, { W - 56, 20 }, { W - 88, 24 } }
	local function drawDisc(parent: Instance, color: Color3, z: number, layers: number): { Frame }
		local pieces = {}
		for i = 1, layers do
			local layer = DISC_LAYERS[i]
			local piece = UIUtil.Create("Frame", place({ Name = "Disc" .. i, BackgroundColor3 = color, ZIndex = z, Parent = parent }, W / 2, DISC_Y, layer[1], layer[2]))
			UIUtil.Corner(piece, UDim.new(1, 0))
			table.insert(pieces, piece)
		end
		return pieces
	end

	-- Dessine le mot + le disque (logo complet ou silhouette de traînée)
	local function drawMark(parent: Instance, color: Color3, z: number, full: boolean)
		local parts = {}
		-- Mot "DVD"
		local word = UIUtil.Label(place({
			Name = "Word",
			Text = WORDMARK,
			TextColor3 = color,
			MaxTextSize = 60,
			ZIndex = z + 2,
			Parent = parent,
		}, W / 2 + 2, 24, W - 10, 46))
		word.FontFace = WORD_FONT
		parts.Word = word
		-- Disque aplati (silhouette : une seule pilule, sinon les recouvrements
		-- transparents se verraient)
		parts.Disc = drawDisc(parent, color, z + 1, full and #DISC_LAYERS or 1)
		if not full then
			return parts
		end
		UIUtil.Gradient(word, GLOSS, 90)
		local wordStroke = UIUtil.Stroke(word, color:Lerp(Color3.new(0, 0, 0), 0.55), 1.5, 0.35)
		wordStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		parts.WordStroke = wordStroke
		-- Reflet brillant en haut du disque
		local gloss = UIUtil.Create("Frame", place({ Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, ZIndex = z + 3, Parent = parent }, W / 2 - 10, DISC_Y - 7.5, W - 76, 3.5))
		UIUtil.Corner(gloss, UDim.new(1, 0))
		parts.Gloss = gloss
		-- Reflet irisé en bas du disque (dégradé holographique qui glisse)
		local sheen = UIUtil.Create("Frame", place({ Name = "Sheen", BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, ZIndex = z + 3, Parent = parent }, W / 2 + 8, DISC_Y + 8, W - 70, 3))
		UIUtil.Corner(sheen, UDim.new(1, 0))
		parts.Holo = UIUtil.Gradient(sheen, HOLO, 0)
		parts.Sheen = sheen
		-- "VIDEO" en creux
		local video = UIUtil.Label(place({
			Name = "Video",
			Text = Locale.T("VIDEO"),
			TextColor3 = INK,
			MaxTextSize = 16,
			ZIndex = z + 4,
			Parent = parent,
		}, W / 2, DISC_Y + 0.5, W - 64, 15))
		video.FontFace = VIDEO_FONT
		parts.Video = video
		return parts
	end

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
			RainbowUntil = 0,
			SpinUntil = 0,
			Rainbow = false,
			Button = nil :: any,
			Hit = nil :: any,
			Body = nil :: any,
			Scale = nil :: any,
			Glow = nil :: any,
			Holo = nil :: any,
			Word = nil :: any,
			WordStroke = nil :: any,
		}
		local color = colors[logo.ColorIndex]

		-- Traînée : silhouettes du logo derrière tous les logos (ZIndex plus bas)
		for k = 1, #TRAIL_ALPHA do
			local ghost = UIUtil.Create("Frame", {
				Name = "DVDTrail" .. index .. "_" .. k,
				Size = UDim2.fromOffset(W, H),
				BackgroundTransparency = 1,
				Visible = false,
				ZIndex = 2,
				Parent = container,
			})
			local marks = drawMark(ghost, color, 1, false)
			marks.Word.TextTransparency = TRAIL_ALPHA[k]
			logo.Ghosts[k] = ghost
			table.insert(logo.Tinted, { marks.Word, "TextColor3" })
			for _, piece in ipairs(marks.Disc) do
				piece.BackgroundTransparency = TRAIL_ALPHA[k]
				table.insert(logo.Tinted, { piece, "BackgroundColor3" })
			end
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
			ZIndex = 12,
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

		-- Halo coloré (ellipse douce derrière le logo, flashe à chaque rebond)
		local glow = UIUtil.Create("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.06, 1.1),
			BackgroundColor3 = color,
			BackgroundTransparency = GLOW_ALPHA,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = body,
		})
		UIUtil.Corner(glow, UDim.new(1, 0))
		local glowCore = UIUtil.Create("Frame", {
			Name = "GlowCore",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.6),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = glow,
		})
		UIUtil.Corner(glowCore, UDim.new(1, 0))
		logo.Glow = glow
		table.insert(logo.Tinted, { glow, "BackgroundColor3" })
		table.insert(logo.Tinted, { glowCore, "BackgroundColor3" })
		table.insert(logo.Fades, { glow, "BackgroundTransparency", GLOW_ALPHA })
		table.insert(logo.Fades, { glowCore, "BackgroundTransparency", 0.55 })

		if useImage then
			-- Image personnalisée (blanche, recolorée)
			local image = UIUtil.Create("ImageLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = settings.LogoImage,
				ImageColor3 = color,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 7,
				Parent = body,
			})
			table.insert(logo.Tinted, { image, "ImageColor3" })
			table.insert(logo.Fades, { image, "ImageTransparency", 0 })
		else
			local parts = drawMark(body, color, 5, true)
			logo.Holo = parts.Holo
			logo.Word = parts.Word
			table.insert(logo.Tinted, { parts.Word, "TextColor3" })
			table.insert(logo.Fades, { parts.Word, "TextTransparency", 0 })
			table.insert(logo.Fades, { parts.WordStroke, "Transparency", 0.35 })
			for _, piece in ipairs(parts.Disc) do
				table.insert(logo.Tinted, { piece, "BackgroundColor3" })
				table.insert(logo.Fades, { piece, "BackgroundTransparency", 0 })
			end
			table.insert(logo.Fades, { parts.Gloss, "BackgroundTransparency", 0.5 })
			table.insert(logo.Fades, { parts.Sheen, "BackgroundTransparency", 0.35 })
			table.insert(logo.Fades, { parts.Video, "TextTransparency", 0 })
			logo.WordStroke = parts.WordStroke
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
				ctx.FloatText(container, center, Locale.T("⏳ %ds", math.ceil(cooldownUntil - os.clock())), Theme.Colors.TextDim, 20)
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
	local function applyColor(logo, color: Color3, instant: boolean?)
		for _, entry in ipairs(logo.Tinted) do
			if instant then
				(entry[1] :: any)[entry[2]] = color
			else
				UIUtil.Tween(entry[1], 0.15, { [entry[2]] = color })
			end
		end
		if logo.WordStroke then
			logo.WordStroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.55)
		end
	end

	local function nextColor(logo)
		-- Jamais deux fois la même couleur de suite
		local newIndex = random:NextInteger(1, #colors)
		if newIndex == logo.ColorIndex then
			newIndex = newIndex % #colors + 1
		end
		logo.ColorIndex = newIndex
		if os.clock() >= logo.RainbowUntil then
			applyColor(logo, colors[newIndex])
		end
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
			body.Size = UDim2.fromScale(0.84, 1.08)
		else
			body.Size = UDim2.fromScale(1.08, 0.82)
		end
		UIUtil.Tween(body, 0.4, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)

		-- Flash du halo
		local glow = logo.Glow
		if not cooling then
			glow.BackgroundTransparency = 0.6
			UIUtil.Tween(glow, 0.5, { BackgroundTransparency = GLOW_ALPHA })
		end

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
			ctx.FloatText(container, UDim2.fromScale(x + w / 2, y + h / 2), "+" .. ctx.Format.Format(value), colors[logo.ColorIndex], 24)
		end
		if effectsOn() then
			ctx.Effects.Burst(container, UDim2.fromScale(contactX, contactY), colors[logo.ColorIndex], 5)
		end

		if ctx.HasFeature("DVDSound") then
			local now = os.clock()
			if now - lastSoundTime >= MIN_SOUND_GAP then
				lastSoundTime = now
				ctx.Sound.Play("Bounce", random:NextNumber(1.25, 1.75))
			end
		end
	end

	-- Fête du coin : ondes de choc, arc-en-ciel, tour sur soi-même, confettis
	local function onCorner(logo, x: number, y: number, w: number, h: number)
		local center = UDim2.fromScale(x + w / 2, y + h / 2)
		-- Coin exact touché (le plus proche du logo)
		local cornerX = (x + w / 2 < 0.5) and 0 or 1
		local cornerY = (y + h / 2 < 0.5) and 0 or 1
		ctx.FloatText(container, center, pickLine(CORNER_TEXTS, random), Theme.Colors.Gold, 46)
		for i, ring in ipairs(rings) do
			ring.Frame.Position = UDim2.fromScale(cornerX, cornerY)
			ring.Age = -ring.Delay
			ring.Stroke.Color = i == 2 and WHITE or Theme.Colors.Gold
		end
		if effectsOn() then
			ctx.Effects.Burst(container, center, Theme.Colors.Gold, 30)
			ctx.Effects.Burst(container, UDim2.fromScale(cornerX, cornerY), nil, 24)
			if type(Effects.Confetti) == "function" then
				pcall(Effects.Confetti, 60)
			end
			if type(Effects.Flash) == "function" then
				pcall(Effects.Flash, Theme.Colors.Gold, 0.35)
			end
		end
		logo.RainbowUntil = os.clock() + RAINBOW_TIME
		logo.SpinUntil = os.clock() + 0.7
		local scale = logo.Scale
		scale.Scale = 1.5
		UIUtil.Tween(scale, 0.7, { Scale = 1 }, Enum.EasingStyle.Elastic)
		local glow = logo.Glow
		glow.BackgroundColor3 = Theme.Colors.Gold
		glow.BackgroundTransparency = 0.25
		UIUtil.Tween(glow, 1.4, { BackgroundTransparency = GLOW_ALPHA })
	end

	------------------------------------------------------------------
	-- Boucle d'affichage
	------------------------------------------------------------------
	local tolerance = settings.CornerTolerance
	ctx.OnRender(function(dt: number)
		-- Ondes de choc du coin
		for _, ring in ipairs(rings) do
			if ring.Age < 1 and ring.Age > -1 then
				ring.Age += dt / 0.9
				if ring.Age >= 1 then
					ring.Frame.Visible = false
				elseif ring.Age >= 0 then
					local k = 1 - (1 - ring.Age) ^ 3
					local size = 30 + k * 520
					ring.Frame.Size = UDim2.fromOffset(size, size)
					ring.Stroke.Transparency = ring.Age
					ring.Stroke.Thickness = 8 - ring.Age * 6
					ring.Frame.Visible = true
				end
			end
		end

		if #logos == 0 then
			return
		end
		local t = workspace:GetServerTimeNow()
		local clock = os.clock()
		local w, h = measure()
		w = w or (W / 1280)
		h = h or (H / 720)

		-- Fin de la recharge : les logos reprennent leurs couleurs
		local isCooling = clock < cooldownUntil
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

				-- Silhouettes : la même trajectoire, un peu plus tôt
				for k, ghost in ipairs(logo.Ghosts) do
					if wantTrail then
						local gx, gy = DVDMath.Position(params, t - k * TRAIL_LAG)
						ghost.Position = UDim2.fromScale(gx, gy)
					end
					if ghost.Visible ~= wantTrail then
						ghost.Visible = wantTrail
					end
				end

				-- Anneau holographique qui tourne
				if logo.Holo then
					logo.Holo.Offset = Vector2.new(math.sin(t * 1.3 + index) * 0.5, 0)
				end

				-- Après un coin : arc-en-ciel + tour sur soi-même
				if clock < logo.RainbowUntil then
					applyColor(logo, Color3.fromHSV((clock * 1.4 + index * 0.2) % 1, 0.8, 1), true)
					logo.Glow.BackgroundColor3 = Theme.Colors.Gold
					logo.Rainbow = true
				elseif logo.Rainbow then
					logo.Rainbow = false
					applyColor(logo, colors[logo.ColorIndex])
				end
				if clock < logo.SpinUntil then
					local k = 1 - (logo.SpinUntil - clock) / 0.7
					logo.Body.Rotation = 360 * (1 - (1 - k) ^ 3)
				elseif logo.Body.Rotation ~= 0 then
					logo.Body.Rotation = 0
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
								pickLine(NEAR_MISS, random),
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
