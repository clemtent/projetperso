--[[
	DVD (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > DVD

	Les logos qui rebondissent partout sur l'écran, façon vieil écran de
	veille de lecteur DVD (5 logos au maximum : un par niveau). v9 : le logo
	est dessiné en Frames, net à toutes les tailles :
	  - "DVD" en gras italique, couleur du logo, avec un léger vernis, un
	    fin contour sombre (lisible sur n'importe quel fond) et une ombre
	    décalée qui lui donne du relief ;
	  - dessous, le disque aplati : une VRAIE ellipse (7 pilules inscrites
	    dans l'ellipse, calculées), reflet blanc, reflet holographique qui
	    glisse, et "VIDEO" en creux ;
	  - un halo doux (3 couches) de la couleur du logo, qui s'illumine à
	    chaque rebond, et une traînée discrète (3 silhouettes du logo placées
	    un peu plus tôt sur la même trajectoire).
	Comportement :
	  - trajectoires données par le SERVEUR (ClientState.DVDSetup) et
	    calculées avec DVDMath depuis l'heure serveur : fluide et identique
	    quel que soit le nombre d'images par seconde ;
	  - à chaque rebond : nouvelle couleur, écrasement contre le mur, flash
	    du halo, éclaboussure de lumière au point de contact, "+X" flottant
	    (visuel : le serveur compte les rebonds) et son "Bounce" si
	    "DVDSound" est possédé ;
	  - coin touché : on prévient le serveur (DVDCorner), qui VÉRIFIE ; à
	    l'écran, grande fête : ondes de choc et gerbe de rayons depuis le
	    coin, tampon "COIN !!!" qui claque près du coin, logo qui tourne sur
	    lui-même en arc-en-ciel, étincelles, confettis, flash doré ;
	  - clic sur un logo : bonus (DVDClick), recharge commune à tous les
	    logos (ils pâlissent pendant la recharge et laissent passer les clics) ;
	  - envoie la taille réelle du logo au serveur (DVDResize).
	Performance : une seule boucle OnRender, aucune création d'instance par
	image (ondes, rayons, éclaboussures et tampon sont réutilisés).
]]

local DVD = {}
DVD.Slot = "Overlay"

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local WORDMARK = "DVD" -- mot principal du logo
local MAX_LOGOS = 5
local RESIZE_INTERVAL = 0.6 -- temps minimum entre deux envois DVDResize
local MIN_SOUND_GAP = 0.07 -- évite la cacophonie avec plusieurs logos
local TRAIL_LAG = 0.05 -- retard (s) de chaque silhouette de la traînée
local TRAIL_ALPHA = { 0.8, 0.88, 0.94 } -- transparence des silhouettes
local GLOW_ALPHA = 0.9 -- transparence de chaque couche du halo
local GLOW_FLASH = 0.7 -- halo au moment d'un rebond
local RAINBOW_TIME = 2.6 -- durée de l'arc-en-ciel après un coin
local SPIN_TIME = 0.8 -- tour sur soi-même après un coin
local RING_COUNT = 3 -- ondes de choc réutilisées
local SPLASH_COUNT = 4 -- éclaboussures de lumière réutilisées
local SPLASH_TIME = 0.45
local BURST_TIME = 1.1 -- gerbe de rayons du coin
local STAMP_TIME = 1.9 -- tampon "COIN !!!"

local INK = Color3.fromRGB(16, 12, 30) -- lettres "VIDEO" (en creux)
local PALE = Color3.fromRGB(170, 168, 190) -- couleur "en recharge"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD_TOP = Color3.fromRGB(255, 244, 170)
local GOLD_BOTTOM = Color3.fromRGB(255, 176, 40)

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
	ColorSequenceKeypoint.new(0.5, Color3.new(0.95, 0.95, 0.95)),
	ColorSequenceKeypoint.new(1, Color3.new(0.72, 0.72, 0.72)),
})

-- Le disque aplati est une ellipse (demi-axes a, b). UICorner ne sait faire
-- que des pilules : on superpose des pilules OPAQUES dont les coins touchent
-- l'ellipse (de la plus fine et large à la plus haute et étroite). Renvoie
-- { { largeur, hauteur }, ... } en pixels "design".
local function ellipseLayers(a: number, b: number): { { number } }
	local layers = {}
	for _, f in ipairs({ 0.36, 0.56, 0.72, 0.84, 0.93, 0.98, 1 }) do
		local halfH = b * f
		local halfW = math.min(a, halfH + a * math.sqrt(math.max(0, 1 - f * f)))
		table.insert(layers, { halfW * 2, halfH * 2 })
	end
	return layers
end

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

	local function pill(props: { [string]: any }): Frame
		local f = UIUtil.Create("Frame", props)
		UIUtil.Corner(f, UDim.new(1, 0))
		return f
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
	-- Effets réutilisés : ondes de choc, rayons, éclaboussures, tampon
	------------------------------------------------------------------
	local rings = {}
	for i = 1, RING_COUNT do
		local ring = pill({
			Name = "CornerRing" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 8,
			Parent = container,
		})
		local stroke = UIUtil.Stroke(ring, Theme.Colors.Gold, 6, 0)
		table.insert(rings, { Frame = ring, Stroke = stroke, Age = -2, Delay = (i - 1) * 0.13 })
	end

	-- Gerbe de rayons (16 rayons) qui s'ouvre et tourne depuis le coin
	local burst = UIUtil.Rays(container, GOLD_TOP, 8, 60, UDim2.fromScale(0, 0), 7)
	burst.Name = "CornerBurst"
	burst.Visible = false
	local burstBars = {}
	for _, bar in ipairs(burst:GetChildren()) do
		if bar:IsA("Frame") then
			-- largeur proportionnelle : les rayons s'élargissent avec la gerbe
			bar.Size = UDim2.fromScale(0.06, 1)
			table.insert(burstBars, bar)
		end
	end
	local burstAge = -1

	-- Éclaboussures de lumière au point de contact d'un rebond
	local splashes = {}
	for i = 1, SPLASH_COUNT do
		local splash = pill({
			Name = "Splash" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 3,
			Parent = container,
		})
		local core = pill({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.45, 0.45), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, ZIndex = 3, Parent = splash })
		table.insert(splashes, { Frame = splash, Core = core, Age = -1 })
	end
	local nextSplash = 1

	-- Tampon "COIN !!!" (badge doré qui claque près du coin)
	local stamp = pill({
		Name = "CornerStamp",
		Size = UDim2.fromOffset(250, 58),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 9,
		Parent = container,
	})
	UIUtil.Gradient(stamp, ColorSequence.new(GOLD_TOP, GOLD_BOTTOM), 90)
	local stampStroke = UIUtil.Stroke(stamp, Color3.fromRGB(120, 60, 0), 3, 0)
	local stampShine = pill({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.new(1, -30, 0, 8), BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, ZIndex = 9, Parent = stamp })
	local stampLabel = UIUtil.Label({
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(1, -24, 1, -12),
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(110, 40, 0),
		MaxTextSize = 34,
		ZIndex = 10,
		Parent = stamp,
	})
	local stampScale = UIUtil.Create("UIScale", { Scale = 0, Parent = stamp })
	local stampAge = -1

	------------------------------------------------------------------
	-- Construction d'un logo
	------------------------------------------------------------------
	local DISC_Y = 62
	local DISC_LAYERS = ellipseLayers(W / 2 - 9, 13)

	-- Dessine le mot + le disque (logo complet, ou silhouette de traînée) ;
	-- renvoie les pièces à colorer
	local function drawMark(parent: Instance, z: number, full: boolean)
		local parts = { Disc = {} :: { Frame } }
		if full then
			-- Ombre décalée (relief) sous le mot
			parts.Shadow = UIUtil.Label(place({ Name = "WordShadow", Text = WORDMARK, MaxTextSize = 60, TextTransparency = 0.15, ZIndex = z + 1, Parent = parent }, W / 2 + 4.5, 26.5, W - 10, 46))
			parts.Shadow.FontFace = WORD_FONT
		end
		-- Mot "DVD"
		parts.Word = UIUtil.Label(place({ Name = "Word", Text = WORDMARK, MaxTextSize = 60, ZIndex = z + 2, Parent = parent }, W / 2 + 2, 24, W - 10, 46))
		parts.Word.FontFace = WORD_FONT
		-- Disque aplati (silhouette : une seule pilule, sinon les recouvrements
		-- transparents se verraient)
		for i = (full and 1 or 3), (full and #DISC_LAYERS or 3) do
			local layer = DISC_LAYERS[i]
			table.insert(parts.Disc, pill(place({ Name = "Disc" .. i, ZIndex = z + 1, Parent = parent }, W / 2, DISC_Y, layer[1], layer[2])))
		end
		if not full then
			return parts
		end
		UIUtil.Gradient(parts.Word, GLOSS, 90)
		parts.WordStroke = UIUtil.Stroke(parts.Word, BLACK, 1.4, 0.25)
		parts.WordStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		-- Reflet brillant en haut du disque
		parts.Gloss = pill(place({ Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, ZIndex = z + 3, Parent = parent }, W / 2 - 12, DISC_Y - 7.5, W - 80, 3.5))
		-- Reflet irisé en bas du disque (dégradé holographique qui glisse)
		local sheen = pill(place({ Name = "Sheen", BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, ZIndex = z + 3, Parent = parent }, W / 2 + 8, DISC_Y + 8, W - 72, 3))
		parts.Holo = UIUtil.Gradient(sheen, HOLO, 0)
		-- "VIDEO" en creux
		parts.Video = UIUtil.Label(place({
			Name = "Video",
			Text = Locale.T("VIDEO"),
			TextColor3 = INK,
			MaxTextSize = 17,
			ZIndex = z + 4,
			Parent = parent,
		}, W / 2, DISC_Y + 0.5, W - 60, 16))
		parts.Video.FontFace = VIDEO_FONT
		return parts
	end

	-- Couleur du logo (dérivées : ombre, contour, halo, traînée). En recharge
	-- le logo pâlit (couleur mêlée de gris) sans devenir transparent : les
	-- pièces du disque se recouvrent et ne doivent pas se voir.
	local function paint(logo, color: Color3)
		local main = (cooling and not logo.Rainbow) and color:Lerp(PALE, 0.72) or color
		if logo.Image then
			logo.Image.ImageColor3 = main
		else
			logo.Word.TextColor3 = main
			logo.Shadow.TextColor3 = main:Lerp(BLACK, 0.62)
			logo.WordStroke.Color = main:Lerp(BLACK, 0.72)
			for _, piece in ipairs(logo.Disc) do
				piece.BackgroundColor3 = main
			end
		end
		for _, glow in ipairs(logo.Glow) do
			glow.BackgroundColor3 = color
		end
		for _, part in ipairs(logo.GhostParts) do
			(part[1] :: any)[part[2]] = color
		end
	end

	local function createLogo(index: number)
		local logo = {
			Index = index,
			Params = nil :: any,
			LastX = nil :: number?,
			LastY = nil :: number?,
			ColorIndex = ((index - 1) % #colors) + 1,
			Ghosts = {} :: { Frame },
			GhostParts = {} :: { { any } }, -- { instance, propriété } recolorés à chaque rebond
			Glow = {} :: { Frame },
			Disc = {} :: { Frame },
			RainbowUntil = 0,
			SpinUntil = 0,
			Rainbow = false,
			Button = nil :: any,
			Hit = nil :: any,
			Body = nil :: any,
			Scale = nil :: any,
			Holo = nil :: any,
			Word = nil :: any,
			Shadow = nil :: any,
			WordStroke = nil :: any,
			Image = nil :: any,
		}

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
			local marks = drawMark(ghost, 1, false)
			marks.Word.TextTransparency = TRAIL_ALPHA[k]
			logo.Ghosts[k] = ghost
			table.insert(logo.GhostParts, { marks.Word, "TextColor3" })
			for _, piece in ipairs(marks.Disc) do
				piece.BackgroundTransparency = TRAIL_ALPHA[k]
				table.insert(logo.GhostParts, { piece, "BackgroundColor3" })
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

		-- Halo doux (3 ellipses superposées : plus lumineux au centre)
		for i, size in ipairs({ { 1.16, 1.02 }, { 0.96, 0.8 }, { 0.74, 0.58 } }) do
			local glow = pill({
				Name = "Glow" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.52),
				Size = UDim2.fromScale(size[1], size[2]),
				BackgroundTransparency = GLOW_ALPHA,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = body,
			})
			table.insert(logo.Glow, glow)
		end

		if useImage then
			-- Image personnalisée (blanche, recolorée)
			logo.Image = UIUtil.Create("ImageLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = settings.LogoImage,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 7,
				Parent = body,
			})
		else
			local parts = drawMark(body, 5, true)
			logo.Holo = parts.Holo
			logo.Word = parts.Word
			logo.Shadow = parts.Shadow
			logo.WordStroke = parts.WordStroke
			logo.Disc = parts.Disc
		end
		paint(logo, colors[logo.ColorIndex])

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

	local function nextColor(logo)
		-- Jamais deux fois la même couleur de suite
		local newIndex = random:NextInteger(1, #colors)
		if newIndex == logo.ColorIndex then
			newIndex = newIndex % #colors + 1
		end
		logo.ColorIndex = newIndex
		if os.clock() >= logo.RainbowUntil then
			paint(logo, colors[newIndex])
		end
	end

	-- Recharge : les logos pâlissent, le halo s'éteint, les clics passent
	local function setFaded(faded: boolean)
		for _, logo in ipairs(logos) do
			logo.Hit.Visible = not faded
			paint(logo, colors[logo.ColorIndex])
			for _, glow in ipairs(logo.Glow) do
				UIUtil.Tween(glow, 0.25, { BackgroundTransparency = faded and 1 or GLOW_ALPHA })
			end
			if logo.Word then
				UIUtil.Tween(logo.Word, 0.25, { TextTransparency = faded and 0.3 or 0 })
				UIUtil.Tween(logo.Shadow, 0.25, { TextTransparency = faded and 0.6 or 0.15 })
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
		local count = math.min(#list, MAX_LOGOS)
		local previousCount = #logos

		-- Crée les logos manquants
		for index = #logos + 1, count do
			local logo = createLogo(index)
			logos[index] = logo
			UIUtil.Tween(logo.Scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			if cooling then
				for _, glow in ipairs(logo.Glow) do
					glow.BackgroundTransparency = 1
				end
			end
		end
		-- Retire les logos en trop
		for index = #logos, count + 1, -1 do
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
		for index = 1, count do
			local logo = logos[index]
			logo.Params = list[index]
			logo.LastX, logo.LastY = nil, nil
			logo.Button.Visible = true
		end

		if count > 0 then
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
	local function splashAt(position: UDim2, color: Color3)
		local splash = splashes[nextSplash]
		nextSplash = nextSplash % #splashes + 1
		splash.Frame.Position = position
		splash.Frame.BackgroundColor3 = color
		splash.Core.BackgroundColor3 = color:Lerp(WHITE, 0.6)
		splash.Age = 0
		splash.Frame.Visible = true
	end

	local function onBounce(logo, x: number, y: number, w: number, h: number, bouncedX: boolean, bouncedY: boolean, corner: boolean)
		nextColor(logo)
		local color = colors[logo.ColorIndex]

		-- Écrasement contre le mur (le corps s'aplatit puis reprend sa forme)
		local body = logo.Body
		if bouncedX and bouncedY then
			body.Size = UDim2.fromScale(0.86, 0.86)
		elseif bouncedX then
			body.Size = UDim2.fromScale(0.82, 1.1)
		else
			body.Size = UDim2.fromScale(1.1, 0.8)
		end
		UIUtil.Tween(body, 0.42, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)

		-- Flash du halo (doux)
		if not cooling then
			for _, glow in ipairs(logo.Glow) do
				glow.BackgroundTransparency = GLOW_FLASH
				UIUtil.Tween(glow, 0.55, { BackgroundTransparency = GLOW_ALPHA })
			end
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
		if value > 0 and not corner then
			ctx.FloatText(container, UDim2.fromScale(x + w / 2, y + h / 2), "+" .. ctx.Format.Format(value), color, 24)
		end
		if effectsOn() then
			splashAt(UDim2.fromScale(contactX, contactY), color)
			ctx.Effects.Burst(container, UDim2.fromScale(contactX, contactY), color, 5)
		end

		if ctx.HasFeature("DVDSound") then
			local now = os.clock()
			if now - lastSoundTime >= MIN_SOUND_GAP then
				lastSoundTime = now
				ctx.Sound.Play("Bounce", random:NextNumber(1.25, 1.75))
			end
		end
	end

	-- Fête du coin : ondes de choc + rayons depuis le coin, tampon "COIN !!!",
	-- arc-en-ciel, tour sur soi-même, étincelles, confettis
	local function onCorner(logo, x: number, y: number, w: number, h: number)
		local center = UDim2.fromScale(x + w / 2, y + h / 2)
		-- Coin exact touché (le plus proche du logo)
		local cornerX = (x + w / 2 < 0.5) and 0 or 1
		local cornerY = (y + h / 2 < 0.5) and 0 or 1
		local corner = UDim2.fromScale(cornerX, cornerY)
		for i, ring in ipairs(rings) do
			ring.Frame.Position = corner
			ring.Age = -ring.Delay
			ring.Stroke.Color = i == 2 and WHITE or Theme.Colors.Gold
		end
		-- Tampon près du coin, juste au-delà du logo (vers l'intérieur de l'écran)
		stampLabel.Text = pickLine(CORNER_TEXTS, random)
		stamp.AnchorPoint = Vector2.new(cornerX, cornerY)
		stamp.Position = UDim2.new(cornerX, cornerX == 0 and 30 or -30, cornerY, cornerY == 0 and H + 34 or -(H + 34))
		stamp.Rotation = (cornerX == cornerY) and -7 or 7
		stampAge = 0
		stamp.Visible = true
		stamp.BackgroundTransparency = 0
		stampLabel.TextTransparency = 0
		stampStroke.Transparency = 0
		stampShine.BackgroundTransparency = 0.45
		stampScale.Scale = 0
		if effectsOn() then
			burst.Position = corner
			burst.Size = UDim2.fromOffset(60, 60)
			burstAge = 0
			burst.Visible = true
			ctx.Effects.Burst(container, center, Theme.Colors.Gold, 26)
			ctx.Effects.Burst(container, corner, nil, 24)
			if type(Effects.Confetti) == "function" then
				pcall(Effects.Confetti, 45)
			end
			if type(Effects.Flash) == "function" then
				pcall(Effects.Flash, Theme.Colors.Gold, 0.3)
			end
		end
		logo.RainbowUntil = os.clock() + RAINBOW_TIME
		logo.SpinUntil = os.clock() + SPIN_TIME
		local scale = logo.Scale
		scale.Scale = 1.55
		UIUtil.Tween(scale, 0.8, { Scale = 1 }, Enum.EasingStyle.Elastic)
		for _, glow in ipairs(logo.Glow) do
			glow.BackgroundColor3 = Theme.Colors.Gold
			glow.BackgroundTransparency = 0.45
			UIUtil.Tween(glow, 1.6, { BackgroundTransparency = GLOW_ALPHA })
		end
	end

	-- Effets réutilisés : avancent à chaque image, se cachent une fois finis
	local function updateEffects(dt: number)
		for _, ring in ipairs(rings) do
			if ring.Age > -1 and ring.Age < 1 then
				ring.Age += dt / 0.9
				if ring.Age >= 1 then
					ring.Frame.Visible = false
				elseif ring.Age >= 0 then
					local k = 1 - (1 - ring.Age) ^ 3
					local size = 30 + k * 560
					ring.Frame.Size = UDim2.fromOffset(size, size)
					ring.Stroke.Transparency = ring.Age
					ring.Stroke.Thickness = 9 - ring.Age * 7
					ring.Frame.Visible = true
				end
			end
		end
		if burstAge >= 0 then
			burstAge += dt
			local p = burstAge / BURST_TIME
			if p >= 1 then
				burstAge = -1
				burst.Visible = false
			else
				local size = 60 + (1 - (1 - p) ^ 2) * 900
				burst.Size = UDim2.fromOffset(size, size)
				burst.Rotation = p * 40
				local alpha = 0.15 + p * 0.85
				for _, bar in ipairs(burstBars) do
					bar.BackgroundTransparency = alpha
				end
			end
		end
		for _, splash in ipairs(splashes) do
			if splash.Age >= 0 then
				splash.Age += dt
				local p = splash.Age / SPLASH_TIME
				if p >= 1 then
					splash.Age = -1
					splash.Frame.Visible = false
				else
					local size = 12 + (1 - (1 - p) ^ 2) * 70
					splash.Frame.Size = UDim2.fromOffset(size, size)
					splash.Frame.BackgroundTransparency = 0.55 + p * 0.45
					splash.Core.BackgroundTransparency = 0.2 + p * 0.8
				end
			end
		end
		if stampAge >= 0 then
			stampAge += dt
			local p = stampAge / STAMP_TIME
			if p >= 1 then
				stampAge = -1
				stamp.Visible = false
			else
				-- Claque (0 -> 1.25 -> 1), reste, puis s'efface en montant un peu
				local t = stampAge
				stampScale.Scale = t < 0.14 and (t / 0.14) * 1.25 or (t < 0.3 and 1.25 - (t - 0.14) / 0.16 * 0.25 or 1)
				local fade = math.clamp((p - 0.75) / 0.25, 0, 1)
				stamp.BackgroundTransparency = fade
				stampLabel.TextTransparency = fade
				stampStroke.Transparency = fade
				stampShine.BackgroundTransparency = 0.45 + fade * 0.55
			end
		end
	end

	------------------------------------------------------------------
	-- Boucle d'affichage
	------------------------------------------------------------------
	local tolerance = settings.CornerTolerance
	ctx.OnRender(function(dt: number)
		updateEffects(dt)

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

				-- Reflet holographique qui glisse
				if logo.Holo then
					logo.Holo.Offset = Vector2.new(math.sin(t * 1.3 + index) * 0.5, 0)
				end

				-- Après un coin : arc-en-ciel + tour sur soi-même
				if clock < logo.RainbowUntil then
					logo.Rainbow = true
					paint(logo, Color3.fromHSV((clock * 1.4 + index * 0.2) % 1, 0.75, 1))
					for _, glow in ipairs(logo.Glow) do
						glow.BackgroundColor3 = Theme.Colors.Gold
					end
				elseif logo.Rainbow then
					logo.Rainbow = false
					paint(logo, colors[logo.ColorIndex])
				end
				if clock < logo.SpinUntil then
					local k = 1 - (logo.SpinUntil - clock) / SPIN_TIME
					logo.Body.Rotation = 360 * (1 - (1 - k) ^ 3)
				elseif logo.Body.Rotation ~= 0 then
					logo.Body.Rotation = 0
				end

				local indexX, indexY = DVDMath.BounceIndex(params, t)
				local lastX, lastY = logo.LastX, logo.LastY
				local bouncedX = lastX ~= nil and indexX ~= lastX
				local bouncedY = lastY ~= nil and indexY ~= lastY
				-- Numéro du bord touché = le plus grand des deux segments
				local k = (bouncedX and lastX) and math.max(indexX, lastX) or nil
				local corner = k ~= nil and DVDMath.IsCornerAtBounceX(params, k, tolerance)

				if bouncedX or bouncedY then
					onBounce(logo, x, y, w, h, bouncedX, bouncedY, corner)
				end

				if corner and k then
					ctx.Net.Event("DVDCorner"):FireServer(index, k)
					onCorner(logo, x, y, w, h)
				elseif k then
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
