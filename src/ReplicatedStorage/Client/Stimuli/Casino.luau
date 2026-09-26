--[[
	Casino (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Casino

	🎰 Machine chanceuse (slot R2, 288x180) : des tours GRATUITS, jamais de
	mise. Un jeton s'obtient toutes les Config.Casino.TokenInterval secondes
	de jeu (max MaxTokens) ; chaque tour en coûte un et rapporte des
	SECONDES de production (paire, triple, ou petit lot de consolation).
	  - carrosserie bordeaux laquée, liseré or, fronton "LUCKY MACHINE" et
	    ampoules en chenillard (autour de la vitrine aussi) qui s'affolent
	    en arc-en-ciel quand on gagne ;
	  - 3 rouleaux en verre bombé : flou de mouvement pendant la rotation
	    (symboles fantômes + traînées), arrêt élastique un par un ;
	  - levier chromé (on peut le tirer) ;
	  - compteur de jetons + jauge de recharge et minuteur ("+1 dans 0:42") ;
	  - écran LED (messages) + bouton "📜 Gains" : table des gains avec la
	    valeur RÉELLE de chaque combinaison (selon ta production actuelle) ;
	  - gain : halo des symboles gagnants, pièces qui tombent ; gros lot :
	    bannière à rayons tournants, flash, confettis.
	Le résultat vient TOUJOURS du serveur (CasinoSpin) ; le client prédit
	seulement la jauge de recharge entre deux états (State.Data.Casino).
	Fermée (State.Data.CasinoEnabled = false) : pancarte "FERMÉ".
]]

local Casino = {}
Casino.Slot = "R2"

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

-- Dimensions (pixels "design") : la carrosserie est rentrée de 2 px pour
-- que son contour ne soit pas coupé par le slot
local W = 284
local H = 176

-- Vitrine des rouleaux (intérieur) et son cadre chromé à ampoules
local WINDOW_X, WINDOW_Y = 13, 35
local WINDOW_W, WINDOW_H = 204, 68
local CHROME_PAD = 7
local REEL_GAP = 4
local REEL_W = math.floor((WINDOW_W - 8 - REEL_GAP * 2) / 3)
local REEL_H = WINDOW_H - 8
local CELL_H = 40 -- hauteur d'un symbole sur le rouleau
local STRIP_LENGTH = 24 -- symboles par bande (recyclés en boucle)
local MAX_SPEED = 22 -- symboles / seconde
local BLUR_SPEED = 7 -- au-delà : flou de mouvement
local MIN_SPIN_TIME = 0.8

local LED_Y = 115
local ROW_Y = 135
local ROW_H = 37
local MAX_COINS = 12

local GOLD = Color3.fromRGB(255, 200, 60)
local GOLD_LIGHT = Color3.fromRGB(255, 240, 170)
local GOLD_DARK = Color3.fromRGB(170, 110, 20)
local CHROME_LIGHT = Color3.fromRGB(250, 250, 255)
local CHROME_DARK = Color3.fromRGB(120, 124, 138)
local LACQUER_TOP = Color3.fromRGB(196, 28, 58)
local LACQUER_BOTTOM = Color3.fromRGB(92, 6, 28)
local LED_BG = Color3.fromRGB(22, 6, 10)
local LED_TEXT = Color3.fromRGB(255, 176, 60)
local WHITE = Color3.new(1, 1, 1)
local BAD = Color3.fromRGB(255, 150, 150)

local MISS_TEXTS = {
	en = {
		"Nothing lined up… a little consolation 🍬",
		"Almost! Here's a tiny treat 🍭",
		"The reels were shy this time 🙈",
		"No match, but never empty-handed ✨",
		"Warm-up spin! 🔥",
	},
	fr = {
		"Rien d'aligné… un petit lot de consolation 🍬",
		"Presque ! Voilà une petite douceur 🍭",
		"Les rouleaux étaient timides 🙈",
		"Pas de paire, mais jamais les mains vides ✨",
		"Tour d'échauffement ! 🔥",
	},
}

local WIN_TEXTS = {
	en = {
		"WINNER! 🎉",
		"Lucky you! 🍀",
		"Lady Luck is smiling 😎",
		"Dopamine waterfall! 🤑",
	},
	fr = {
		"GAGNÉ ! 🎉",
		"Quelle chance ! 🍀",
		"La chance te sourit 😎",
		"Dopamine en cascade ! 🤑",
	},
}

local ATTRACT_TEXTS = {
	en = {
		"Free spins, no bet! 🍀",
		"Every spin wins something ✨",
		"Tap 📜 to see the prizes",
		"Pull the lever! 🕹️",
	},
	fr = {
		"Tours gratuits, aucune mise ! 🍀",
		"Chaque tour rapporte quelque chose ✨",
		"Touche 📜 pour voir les gains",
		"Tire le levier ! 🕹️",
	},
}

-- Recul "Back" plus doux que la version standard (petit rebond à l'arrêt)
local function easeOutSoftBack(t: number): number
	local c1 = 0.9
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

local function clockText(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Casino.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local Format = ctx.Format
	local config = ctx.Config.Casino
	local symbols = config.Symbols
	local symbolsById = ctx.Config.CasinoSymbolsById
	local container: Frame = ctx.Container
	local random = Random.new()

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Visible à l'écran ? (ctx.IsVisible si le manager le fournit)
	local function isVisible(): boolean
		local fn = ctx.IsVisible
		if type(fn) == "function" then
			local ok, result = pcall(fn)
			return not ok or result ~= false
		end
		return true
	end

	-- Petits constructeurs
	local function frame(props: { [string]: any }): Frame
		props.BorderSizePixel = 0
		if props.BackgroundTransparency == nil and props.BackgroundColor3 == nil then
			props.BackgroundTransparency = 1
		end
		return Create("Frame", props)
	end

	local function round(guiObject: Instance, radius: number?)
		UIUtil.Corner(guiObject, radius and UDim.new(0, radius) or UDim.new(1, 0))
	end

	local function vGradient(parent: Instance, keypoints: { { number | Color3 } }, rotation: number?): UIGradient
		local list = {}
		for _, point in ipairs(keypoints) do
			table.insert(list, ColorSequenceKeypoint.new(point[1] :: number, point[2] :: Color3))
		end
		return UIUtil.Gradient(parent, ColorSequence.new(list), rotation or 90)
	end

	local function fade(parent: Instance, points: { { number } }, rotation: number?): UIGradient
		local list = {}
		for _, point in ipairs(points) do
			table.insert(list, NumberSequenceKeypoint.new(point[1], point[2]))
		end
		return Create("UIGradient", { Rotation = rotation or 90, Transparency = NumberSequence.new(list), Parent = parent })
	end

	-- Contour doré dégradé (UIGradient sous l'UIStroke)
	local function goldStroke(parent: Instance, thickness: number): UIStroke
		local stroke = UIUtil.Stroke(parent, WHITE, thickness, 0)
		vGradient(stroke, { { 0, GOLD_LIGHT }, { 0.45, GOLD }, { 1, GOLD_DARK } }, 90)
		return stroke
	end

	-- Gain estimé (en Dopamine) pour `seconds` de production, avec les stats actuelles
	local function rewardFor(seconds: number): number
		local data = ctx.State.Data
		local stats = {
			PerSecond = (data and tonumber(data.PerSecond)) or 0,
			ClickValue = (data and tonumber(data.ClickValue)) or 0,
		}
		local missSeconds = math.max(1, config.MissRewardSeconds or 1)
		local minimum = (config.MinReward or 0) * math.max(1, seconds / missSeconds)
		local ok, amount = pcall(ctx.Formulas.ScaledReward, stats, seconds, minimum)
		return ok and amount or minimum
	end

	------------------------------------------------------------------
	-- Carrosserie
	------------------------------------------------------------------
	local card = frame({
		Name = "Machine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = container,
	})
	round(card, 18)
	vGradient(card, { { 0, LACQUER_TOP }, { 0.55, Color3.fromRGB(150, 16, 44) }, { 1, LACQUER_BOTTOM } })
	goldStroke(card, 2)

	-- Reflet laqué (bande claire en haut)
	local sheen = frame({
		Name = "Sheen",
		Size = UDim2.new(1, -8, 0.42, 0),
		Position = UDim2.fromOffset(4, 3),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.88,
		ZIndex = 1,
		Parent = card,
	})
	round(sheen, 15)
	fade(sheen, { { 0, 0.2 }, { 1, 1 } })

	------------------------------------------------------------------
	-- Fronton : titre doré + ampoules
	------------------------------------------------------------------
	local marquee = frame({
		Name = "Marquee",
		Position = UDim2.fromOffset(7, 5),
		Size = UDim2.fromOffset(W - 14, 24),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = card,
	})
	round(marquee, 9)
	vGradient(marquee, { { 0, Color3.fromRGB(64, 8, 24) }, { 1, Color3.fromRGB(26, 2, 10) } })
	goldStroke(marquee, 1.5)

	local titleLabel = UIUtil.Label({
		Name = "Title",
		Text = Locale.T("★ LUCKY MACHINE ★"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(170, 20),
		MaxTextSize = 17,
		ZIndex = 4,
		Parent = marquee,
	})
	local titleGradient = vGradient(titleLabel, { { 0, GOLD_LIGHT }, { 0.5, GOLD }, { 1, Color3.fromRGB(230, 140, 20) } })
	local titleStroke = UIUtil.Stroke(titleLabel, Color3.fromRGB(70, 20, 0), 1.2, 0)
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local titleScale = Create("UIScale", { Parent = titleLabel })

	-- Ampoules : une seule Frame chacune, le "halo" est son UIStroke
	local bulbs: { { Frame: Frame, Stroke: UIStroke, Order: number } } = {}
	local function addBulb(parent: Instance, x: number, y: number, size: number, order: number)
		local bulb = frame({
			Name = "Bulb",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = GOLD,
			ZIndex = 4,
			Parent = parent,
		})
		round(bulb)
		local stroke = UIUtil.Stroke(bulb, GOLD, 2, 0.55)
		table.insert(bulbs, { Frame = bulb, Stroke = stroke, Order = order })
	end
	-- Fronton : 4 de chaque côté du titre
	local marqueeW = W - 14
	for k = 0, 3 do
		addBulb(marquee, 10 + k * 11, 12, 5, k)
		addBulb(marquee, marqueeW - 10 - k * 11, 12, 5, k)
	end

	------------------------------------------------------------------
	-- Vitrine : cadre chromé (avec ampoules) + verre
	------------------------------------------------------------------
	local chrome = frame({
		Name = "Chrome",
		Position = UDim2.fromOffset(WINDOW_X - CHROME_PAD, WINDOW_Y - CHROME_PAD),
		Size = UDim2.fromOffset(WINDOW_W + CHROME_PAD * 2, WINDOW_H + CHROME_PAD * 2),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = card,
	})
	round(chrome, 12)
	vGradient(chrome, { { 0, CHROME_LIGHT }, { 0.35, Color3.fromRGB(190, 194, 206) }, { 0.5, CHROME_DARK }, { 0.7, Color3.fromRGB(210, 214, 224) }, { 1, Color3.fromRGB(150, 154, 168) } })
	UIUtil.Stroke(chrome, Color3.fromRGB(50, 10, 20), 1, 0.2)
	-- Ampoules dans le cadre (haut et bas), numérotées dans le sens du chenillard
	local chromeW = WINDOW_W + CHROME_PAD * 2
	local chromeH = WINDOW_H + CHROME_PAD * 2
	local bulbCount = 12
	for k = 0, bulbCount - 1 do
		local x = 12 + k * (chromeW - 24) / (bulbCount - 1)
		addBulb(chrome, x, 3.5, 4, k)
		addBulb(chrome, chromeW - x, chromeH - 3.5, 4, bulbCount + k)
	end
	-- Ordre du chenillard
	table.sort(bulbs, function(a, b)
		return a.Order < b.Order
	end)

	local window = frame({
		Name = "Window",
		Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundColor3 = Color3.fromRGB(16, 4, 8),
		ZIndex = 3,
		Parent = card,
	})
	round(window, 8)
	local windowStroke = UIUtil.Stroke(window, GOLD, 1.5, 0.3)

	local reels = {}
	local function wrap(index: number): number
		return ((index - 1) % STRIP_LENGTH) + 1
	end

	for r = 1, 3 do
		local reelFrame = frame({
			Name = "Reel" .. r,
			Position = UDim2.fromOffset(4 + (r - 1) * (REEL_W + REEL_GAP), 4),
			Size = UDim2.fromOffset(REEL_W, REEL_H),
			BackgroundColor3 = WHITE,
			ClipsDescendants = true,
			ZIndex = 4,
			Parent = window,
		})
		round(reelFrame, 6)
		-- Cylindre : ivoire au centre, plus sombre en haut / en bas
		vGradient(reelFrame, {
			{ 0, Color3.fromRGB(160, 150, 140) },
			{ 0.28, Color3.fromRGB(240, 234, 222) },
			{ 0.5, Color3.fromRGB(255, 253, 246) },
			{ 0.72, Color3.fromRGB(240, 234, 222) },
			{ 1, Color3.fromRGB(160, 150, 140) },
		})

		-- Halo de victoire derrière le symbole du milieu
		local glow = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(REEL_W / 2, REEL_H / 2),
			Size = UDim2.fromOffset(REEL_W - 4, CELL_H - 2),
			BackgroundColor3 = GOLD,
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = reelFrame,
		})
		round(glow, 8)
		fade(glow, { { 0, 0.6 }, { 0.5, 0 }, { 1, 0.6 } }, 0)

		-- Bande de symboles (mélangés)
		local strip = {}
		for i = 1, STRIP_LENGTH do
			strip[i] = symbols[((i - 1) % #symbols) + 1].Id
		end
		for i = STRIP_LENGTH, 2, -1 do
			local j = random:NextInteger(1, i)
			strip[i], strip[j] = strip[j], strip[i]
		end

		-- 4 symboles visibles (recyclés) + 2 "fantômes" chacun pour le flou
		local labels = {}
		for k = 1, 4 do
			local label = UIUtil.Label({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(REEL_W, CELL_H - 6),
				Position = UDim2.fromOffset(REEL_W / 2, REEL_H / 2),
				Font = Theme.Fonts.Title,
				MaxTextSize = 30,
				ZIndex = 5,
				Parent = reelFrame,
			})
			local ghosts = {}
			for g = -1, 1, 2 do
				local ghost = UIUtil.Label({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromScale(1, 1),
					Position = UDim2.new(0.5, 0, 0.5, g * CELL_H * 0.22),
					Font = Theme.Fonts.Title,
					MaxTextSize = 30,
					TextTransparency = 0.72,
					Visible = false,
					ZIndex = 5,
					Parent = label,
				})
				table.insert(ghosts, ghost)
			end
			labels[k] = { Label = label, Ghosts = ghosts, Shown = "" }
		end

		-- Traînées de mouvement (visibles seulement à grande vitesse)
		local streaks = frame({
			Name = "Streaks",
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 6,
			Parent = reelFrame,
		})
		for s = 1, 3 do
			local line = frame({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(s / 4, 0, 0, 0),
				Size = UDim2.new(0, 2, 1, 0),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.55,
				ZIndex = 6,
				Parent = streaks,
			})
			fade(line, { { 0, 1 }, { 0.5, 0.2 }, { 1, 1 } })
		end
		local tint = frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(255, 250, 235),
			BackgroundTransparency = 0.55,
			ZIndex = 6,
			Parent = streaks,
		})
		fade(tint, { { 0, 0.3 }, { 0.5, 0.8 }, { 1, 0.3 } })

		-- Ombre intérieure (haut / bas) pour la profondeur
		local shade = frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			ZIndex = 7,
			Parent = reelFrame,
		})
		fade(shade, { { 0, 0.15 }, { 0.25, 0.85 }, { 0.5, 1 }, { 0.75, 0.85 }, { 1, 0.15 } })
		-- Reflet de la vitre (bande blanche en haut)
		local glass = frame({
			Position = UDim2.fromOffset(3, 2),
			Size = UDim2.new(1, -6, 0, 13),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.55,
			ZIndex = 8,
			Parent = reelFrame,
		})
		round(glass, 5)
		fade(glass, { { 0, 0.1 }, { 1, 1 } })

		reels[r] = {
			Frame = reelFrame,
			Glow = glow,
			Strip = strip,
			Labels = labels,
			Streaks = streaks,
			Blurred = false,
			Pos = random:NextInteger(1, STRIP_LENGTH),
			Speed = 0,
			Mode = "idle", -- "idle" | "spin" | "stop"
			StopFrom = 0,
			StopTo = 0,
			StopT = 0,
			StopDur = 1,
			Scale = Create("UIScale", { Parent = reelFrame }),
		}
	end

	-- Séparateurs chromés entre les rouleaux
	for r = 1, 2 do
		local separator = frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(4 + r * (REEL_W + REEL_GAP) - REEL_GAP / 2, 3),
			Size = UDim2.fromOffset(3, WINDOW_H - 6),
			BackgroundColor3 = WHITE,
			ZIndex = 9,
			Parent = window,
		})
		round(separator, 2)
		UIUtil.Gradient(separator, ColorSequence.new(CHROME_LIGHT, CHROME_DARK), 0)
	end

	-- Ligne de gain : halo + trait + flèches
	local paylineGlow = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 0, 12),
		BackgroundColor3 = Color3.fromRGB(255, 70, 70),
		BackgroundTransparency = 0.5,
		ZIndex = 9,
		Parent = window,
	})
	fade(paylineGlow, { { 0, 1 }, { 0.5, 0.2 }, { 1, 1 } })
	local payline = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 0, 2),
		BackgroundColor3 = Color3.fromRGB(255, 60, 60),
		BackgroundTransparency = 0.25,
		ZIndex = 10,
		Parent = window,
	})
	local arrows = {}
	for side = 0, 1 do
		local arrow = UIUtil.Label({
			Text = side == 0 and "▶" or "◀",
			Font = Theme.Fonts.Title,
			TextColor3 = GOLD,
			AnchorPoint = Vector2.new(side, 0.5),
			Position = UDim2.new(side, side == 0 and -8 or 8, 0.5, 0),
			Size = UDim2.fromOffset(8, 12),
			MaxTextSize = 10,
			ZIndex = 10,
			Parent = window,
		})
		table.insert(arrows, arrow)
	end

	-- Affiche la bande d'un rouleau selon sa position (symbole `Pos` au centre)
	local function renderReel(reel)
		local base = math.floor(reel.Pos)
		local blur = reel.Speed > BLUR_SPEED
		local blurChanged = blur ~= reel.Blurred
		reel.Blurred = blur
		if blurChanged then
			reel.Streaks.Visible = blur
		end
		for k = 1, 4 do
			local index = base - 1 + (k - 1)
			local entry = reel.Labels[k]
			local label = entry.Label
			local id = reel.Strip[wrap(index)]
			if entry.Shown ~= id then
				entry.Shown = id
				local symbol = symbolsById[id]
				local icon = symbol and symbol.Icon or "?"
				label.Text = icon
				for _, ghost in ipairs(entry.Ghosts) do
					ghost.Text = icon
				end
			end
			-- Les indices plus grands sont au-dessus : la bande descend
			label.Position = UDim2.fromOffset(REEL_W / 2, REEL_H / 2 - (index - reel.Pos) * CELL_H)
			if blurChanged then
				label.TextTransparency = blur and 0.38 or 0
				for _, ghost in ipairs(entry.Ghosts) do
					ghost.Visible = blur
				end
			end
		end
	end

	for _, reel in ipairs(reels) do
		renderReel(reel)
	end

	------------------------------------------------------------------
	-- Levier chromé
	------------------------------------------------------------------
	local leverX = WINDOW_X + WINDOW_W + CHROME_PAD + (W - (WINDOW_X + WINDOW_W + CHROME_PAD)) / 2
	local leverBottom = 96
	local knobTop = 44
	local stickLength = leverBottom - knobTop

	-- Rainure (où le levier descend) et support chromé
	local groove = frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(leverX, knobTop - 4),
		Size = UDim2.fromOffset(10, leverBottom - knobTop + 8),
		BackgroundColor3 = Color3.fromRGB(40, 4, 14),
		BackgroundTransparency = 0.35,
		ZIndex = 2,
		Parent = card,
	})
	round(groove, 5)
	local mount = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(leverX, leverBottom + 4),
		Size = UDim2.fromOffset(30, 20),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = card,
	})
	round(mount, 6)
	vGradient(mount, { { 0, CHROME_LIGHT }, { 0.5, Color3.fromRGB(170, 174, 188) }, { 1, CHROME_DARK } })
	UIUtil.Stroke(mount, Color3.fromRGB(40, 8, 16), 1, 0.3)
	local mountSlot = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(8, 12),
		BackgroundColor3 = Color3.fromRGB(30, 30, 36),
		ZIndex = 4,
		Parent = mount,
	})
	round(mountSlot, 4)

	local stick = frame({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(leverX, leverBottom + 2),
		Size = UDim2.fromOffset(6, stickLength),
		BackgroundColor3 = WHITE,
		ZIndex = 5,
		Parent = card,
	})
	round(stick, 3)
	UIUtil.Gradient(stick, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 154, 168)),
		ColorSequenceKeypoint.new(0.35, CHROME_LIGHT),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 114, 128)),
	}), 0)

	local knob = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(leverX, knobTop),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = WHITE,
		ZIndex = 6,
		Parent = card,
	})
	round(knob)
	UIUtil.Gradient(knob, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 110)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(225, 20, 36)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 0, 12)),
	}), 60)
	UIUtil.Stroke(knob, Color3.fromRGB(70, 0, 8), 1.2, 0.1)
	local knobShine = frame({
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.fromOffset(9, 5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.2,
		Rotation = -25,
		ZIndex = 7,
		Parent = knob,
	})
	round(knobShine)
	-- Petite flèche "tire-moi" qui rebondit à côté du levier (quand on peut jouer)
	local pullHint = UIUtil.Label({
		Text = "▼",
		Font = Theme.Fonts.Title,
		TextColor3 = GOLD_LIGHT,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(leverX, knobTop + 22),
		Size = UDim2.fromOffset(12, 10),
		MaxTextSize = 10,
		ZIndex = 4,
		Parent = card,
	})

	local leverButton = Create("TextButton", {
		Name = "LuckyLever",
		Position = UDim2.fromOffset(leverX - 20, knobTop - 16),
		Size = UDim2.fromOffset(40, leverBottom - knobTop + 30),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 12,
		Parent = card,
	})

	local function pullLever()
		local down = leverBottom - 6
		UIUtil.Tween(knob, 0.16, { Position = UDim2.fromOffset(leverX, down) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UIUtil.Tween(stick, 0.16, { Size = UDim2.fromOffset(6, leverBottom + 2 - down) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			if knob.Parent and stick.Parent then
				UIUtil.Tween(knob, 0.8, { Position = UDim2.fromOffset(leverX, knobTop) }, Enum.EasingStyle.Elastic)
				UIUtil.Tween(stick, 0.8, { Size = UDim2.fromOffset(6, stickLength) }, Enum.EasingStyle.Elastic)
			end
		end)
	end

	ctx.Connect(leverButton.MouseEnter, function()
		UIUtil.Tween(knob, 0.15, { Size = UDim2.fromOffset(27, 27) }, Enum.EasingStyle.Back)
	end)
	ctx.Connect(leverButton.MouseLeave, function()
		UIUtil.Tween(knob, 0.15, { Size = UDim2.fromOffset(24, 24) })
	end)

	------------------------------------------------------------------
	-- Écran LED (messages) + bouton "📜 Gains"
	------------------------------------------------------------------
	local led = frame({
		Name = "Led",
		Position = UDim2.fromOffset(7, LED_Y),
		Size = UDim2.fromOffset(W - 14, 16),
		BackgroundColor3 = LED_BG,
		ZIndex = 3,
		Parent = card,
	})
	round(led, 5)
	UIUtil.Stroke(led, Color3.fromRGB(0, 0, 0), 1, 0.3)
	local info = UIUtil.Label({
		Name = "Info",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = LED_TEXT,
		Position = UDim2.fromOffset(7, 1),
		Size = UDim2.new(1, -76, 1, -2),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 12,
		ZIndex = 4,
		Parent = led,
	})
	local infoLockUntil = 0

	local function setInfo(text: string, color: Color3?, lockSeconds: number?)
		info.Text = text
		info.TextColor3 = color or LED_TEXT
		if lockSeconds then
			infoLockUntil = os.clock() + lockSeconds
		end
	end

	local payButton = Create("TextButton", {
		Name = "LuckyPaytable",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.fromOffset(66, 12),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = Locale.T("📜 Payouts"),
		TextColor3 = Color3.fromRGB(60, 20, 0),
		TextSize = 10,
		TextScaled = true,
		ZIndex = 5,
		Parent = led,
	})
	Create("UITextSizeConstraint", { MaxTextSize = 10, MinTextSize = 6, Parent = payButton })
	Create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = payButton })
	round(payButton)
	vGradient(payButton, { { 0, GOLD_LIGHT }, { 1, GOLD } })
	UIUtil.AnimateButton(payButton, 1.06, 0.94)

	------------------------------------------------------------------
	-- Table des gains (par-dessus toute la machine)
	------------------------------------------------------------------
	local paytable = Create("TextButton", {
		Name = "PaytablePanel",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(W - 8, H - 8),
		BackgroundColor3 = Color3.fromRGB(24, 4, 12),
		BackgroundTransparency = 0.03,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 40,
		Parent = card,
	})
	round(paytable, 15)
	goldStroke(paytable, 1.5)
	local paytableScale = Create("UIScale", { Parent = paytable })
	local ptTitle = UIUtil.Label({
		Text = Locale.T("📜 Payouts"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -90, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		ZIndex = 41,
		Parent = paytable,
	})
	vGradient(ptTitle, { { 0, GOLD_LIGHT }, { 1, GOLD } })
	UIUtil.Label({
		Text = Locale.T("Tap to close"),
		Font = Theme.Fonts.Body,
		TextColor3 = Color3.fromRGB(230, 190, 170),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 7),
		Size = UDim2.fromOffset(80, 13),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 10,
		ZIndex = 41,
		Parent = paytable,
	})
	-- En-têtes des colonnes
	local COL_TRIPLE, COL_PAIR = 96, 186
	for _, header in ipairs({ { COL_TRIPLE, Locale.T("3 alike") }, { COL_PAIR, Locale.T("2 alike") } }) do
		UIUtil.Label({
			Text = header[2],
			Font = Theme.Fonts.Title,
			TextColor3 = Color3.fromRGB(255, 200, 150),
			Position = UDim2.fromOffset(header[1], 23),
			Size = UDim2.fromOffset(80, 11),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 10,
			ZIndex = 41,
			Parent = paytable,
		})
	end

	local sorted = table.clone(symbols)
	table.sort(sorted, function(a, b)
		return (a.Triple or 0) > (b.Triple or 0)
	end)
	local paytableRows = {}
	local ROW_TOP, ROW_STEP = 35, 17
	for index, symbol in ipairs(sorted) do
		if index > 6 then
			break
		end
		local y = ROW_TOP + (index - 1) * ROW_STEP
		local stripe = frame({
			Position = UDim2.fromOffset(6, y),
			Size = UDim2.new(1, -12, 0, ROW_STEP - 2),
			BackgroundColor3 = index % 2 == 1 and Color3.fromRGB(70, 12, 30) or Color3.fromRGB(46, 8, 20),
			BackgroundTransparency = 0.2,
			ZIndex = 41,
			Parent = paytable,
		})
		round(stripe, 5)
		UIUtil.Label({
			Text = symbol.Icon .. symbol.Icon .. symbol.Icon,
			Font = Theme.Fonts.Title,
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.fromOffset(72, ROW_STEP - 2),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 13,
			ZIndex = 42,
			Parent = stripe,
		})
		local tripleLabel = UIUtil.Label({
			Text = "",
			Font = Theme.Fonts.Number,
			TextColor3 = GOLD_LIGHT,
			Position = UDim2.fromOffset(COL_TRIPLE - 6, 0),
			Size = UDim2.fromOffset(86, ROW_STEP - 2),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 12,
			ZIndex = 42,
			Parent = stripe,
		})
		local pairLabel = UIUtil.Label({
			Text = "",
			Font = Theme.Fonts.Number,
			TextColor3 = WHITE,
			Position = UDim2.fromOffset(COL_PAIR - 6, 0),
			Size = UDim2.fromOffset(76, ROW_STEP - 2),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 12,
			ZIndex = 42,
			Parent = stripe,
		})
		table.insert(paytableRows, { Symbol = symbol, Triple = tripleLabel, Pair = pairLabel })
	end
	local paytableFooter = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Body,
		TextColor3 = Color3.fromRGB(255, 220, 170),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -16, 0, 13),
		MaxTextSize = 11,
		ZIndex = 41,
		Parent = paytable,
	})

	-- Valeurs réelles (selon la production actuelle du joueur)
	local function refreshPaytable()
		for _, row in ipairs(paytableRows) do
			local symbol = row.Symbol
			row.Triple.Text = "+" .. Format.Format(rewardFor(symbol.Triple or 0)) .. "  <font color=\"#C8A07A\">" .. Locale.T("%s s", tostring(symbol.Triple or 0)) .. "</font>"
			row.Triple.RichText = true
			row.Pair.Text = "+" .. Format.Format(rewardFor(symbol.Pair or 0)) .. "  <font color=\"#A08080\">" .. Locale.T("%s s", tostring(symbol.Pair or 0)) .. "</font>"
			row.Pair.RichText = true
		end
		paytableFooter.Text = Locale.T("No match: +%s · everything is free 🎁", Format.Format(rewardFor(config.MissRewardSeconds or 0)))
	end

	local paytableOpen = false
	local paytableToken = 0
	local function setPaytable(open: boolean)
		if paytableOpen == open then
			return
		end
		paytableOpen = open
		paytableToken += 1
		local token = paytableToken
		if open then
			refreshPaytable()
			paytable.Visible = true
			paytableScale.Scale = 0.6
			UIUtil.Tween(paytableScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			task.delay(10, function()
				if token == paytableToken and paytableOpen then
					setPaytable(false)
				end
			end)
		else
			UIUtil.Tween(paytableScale, 0.15, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.15, function()
				if token == paytableToken and paytable.Parent then
					paytable.Visible = false
				end
			end)
		end
	end
	ctx.Connect(payButton.Activated, function()
		ctx.Sound.Play("Click", 1.2)
		setPaytable(not paytableOpen)
	end)
	ctx.Connect(paytable.Activated, function()
		setPaytable(false)
	end)

	------------------------------------------------------------------
	-- Jetons : compteur + jauge de recharge (prédite entre deux états)
	------------------------------------------------------------------
	local tokenPanel = frame({
		Name = "Tokens",
		Position = UDim2.fromOffset(7, ROW_Y),
		Size = UDim2.fromOffset(120, ROW_H),
		BackgroundColor3 = LED_BG,
		ZIndex = 3,
		Parent = card,
	})
	round(tokenPanel, 10)
	goldStroke(tokenPanel, 1)

	-- Pièce-jeton dessinée (or, anneau, étoile)
	local coinIcon = frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
		Parent = tokenPanel,
	})
	round(coinIcon)
	vGradient(coinIcon, { { 0, GOLD_LIGHT }, { 0.5, GOLD }, { 1, GOLD_DARK } }, 45)
	UIUtil.Stroke(coinIcon, Color3.fromRGB(130, 70, 0), 1.2, 0)
	local coinInner = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		ZIndex = 5,
		Parent = coinIcon,
	})
	round(coinInner)
	UIUtil.Stroke(coinInner, Color3.fromRGB(190, 120, 10), 1, 0.2)
	UIUtil.Label({
		Text = "★",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(150, 80, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(14, 14),
		MaxTextSize = 13,
		ZIndex = 6,
		Parent = coinIcon,
	})
	local coinScale = Create("UIScale", { Parent = coinIcon })

	local tokenCount = UIUtil.Label({
		Name = "Count",
		Text = "",
		RichText = true,
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		Position = UDim2.fromOffset(38, 2),
		Size = UDim2.fromOffset(78, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		ZIndex = 4,
		Parent = tokenPanel,
	})
	local barBack = frame({
		Position = UDim2.fromOffset(38, 19),
		Size = UDim2.fromOffset(74, 5),
		BackgroundColor3 = Color3.fromRGB(70, 20, 30),
		ZIndex = 4,
		Parent = tokenPanel,
	})
	round(barBack)
	local barFill = frame({
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 5,
		Parent = barBack,
	})
	round(barFill)
	vGradient(barFill, { { 0, GOLD_LIGHT }, { 1, Color3.fromRGB(255, 150, 20) } }, 0)
	local timerLabel = UIUtil.Label({
		Name = "Refill",
		Text = "",
		Font = Theme.Fonts.Body,
		TextColor3 = Color3.fromRGB(255, 205, 150),
		Position = UDim2.fromOffset(38, 25),
		Size = UDim2.fromOffset(78, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 10,
		ZIndex = 4,
		Parent = tokenPanel,
	})

	-- Dernier état reçu (jetons, progression, instant de réception)
	local tokenBase = {
		Tokens = config.StartTokens or 0,
		Progress = 0,
		Max = config.MaxTokens or 10,
		Interval = config.TokenInterval or 60,
		At = os.clock(),
		Known = false,
	}

	local function readServerTokens(casino: any)
		if type(casino) ~= "table" then
			return
		end
		local tokens = tonumber(casino.Tokens)
		if not tokens then
			return
		end
		tokenBase.Tokens = math.max(0, math.floor(tokens))
		tokenBase.Progress = math.clamp(tonumber(casino.Progress) or 0, 0, 1)
		tokenBase.Max = tonumber(casino.Max) or tokenBase.Max
		tokenBase.Interval = math.max(1, tonumber(casino.Interval) or tokenBase.Interval)
		tokenBase.At = os.clock()
		tokenBase.Known = true
	end

	-- (jetons, progression 0..1, secondes avant le prochain)
	local function currentTokens(): (number, number, number)
		local tokens = tokenBase.Tokens
		if tokens >= tokenBase.Max then
			return tokens, 1, 0
		end
		local progress = tokenBase.Progress + (os.clock() - tokenBase.At) / tokenBase.Interval
		if progress >= 1 then
			-- Le serveur va l'envoyer : on l'affiche déjà (jamais plus d'un d'avance)
			return tokens + 1, 0, 0
		end
		return tokens, progress, (1 - progress) * tokenBase.Interval
	end

	------------------------------------------------------------------
	-- Bouton JOUER (gros, doré)
	------------------------------------------------------------------
	local playX = 7 + 120 + 6
	local playButton = Create("TextButton", {
		Name = "LuckySpin",
		Position = UDim2.fromOffset(playX, ROW_Y),
		Size = UDim2.fromOffset(W - 7 - playX, ROW_H),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		Parent = card,
	})
	round(playButton, 12)
	local playGradient = vGradient(playButton, { { 0, Color3.fromRGB(255, 218, 90) }, { 0.5, Color3.fromRGB(255, 170, 20) }, { 1, Color3.fromRGB(205, 110, 0) } })
	local playStroke = UIUtil.Stroke(playButton, Color3.fromRGB(90, 40, 0), 1.5, 0)
	local playShine = frame({
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.new(1, -8, 0.45, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		ZIndex = 6,
		Parent = playButton,
	})
	round(playShine, 9)
	-- Reflet qui balaie le bouton de temps en temps
	local playSweep = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.3, 0, 0.5, 0),
		Size = UDim2.new(0, 18, 1.6, 0),
		Rotation = 20,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = 6,
		Parent = playButton,
	})
	fade(playSweep, { { 0, 1 }, { 0.5, 0.2 }, { 1, 1 } }, 0)
	local playClip = frame({ Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 6, Parent = playButton })
	round(playClip, 12)
	playSweep.Parent = playClip
	local playLabel = UIUtil.Label({
		Text = Locale.T("SPIN"),
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(80, 20, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -10, 0, 19),
		MaxTextSize = 18,
		ZIndex = 7,
		Parent = playButton,
	})
	local playSub = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(120, 45, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -10, 0, 11),
		MaxTextSize = 10,
		ZIndex = 7,
		Parent = playButton,
	})
	UIUtil.AnimateButton(playButton, 1.04, 0.93)

	------------------------------------------------------------------
	-- Pièces qui tombent (réserve réutilisée) et bannière gros lot
	------------------------------------------------------------------
	local coins = {}
	for _ = 1, MAX_COINS do
		local coin = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 30,
			Parent = card,
		})
		round(coin)
		vGradient(coin, { { 0, GOLD_LIGHT }, { 0.5, GOLD }, { 1, GOLD_DARK } }, 45)
		UIUtil.Stroke(coin, Color3.fromRGB(150, 90, 0), 1.2, 0)
		table.insert(coins, { Label = coin, Active = false, X = 0, Y = 0, VX = 0, VY = 0, Spin = 0, Angle = 0 })
	end
	local activeCoins = 0

	local function dropCoins(count: number)
		if not effectsOn() then
			return
		end
		local launched = 0
		for _, coin in ipairs(coins) do
			if launched >= count then
				break
			end
			if not coin.Active then
				coin.Active = true
				coin.X = WINDOW_X + WINDOW_W / 2 + random:NextNumber(-60, 60)
				coin.Y = WINDOW_Y + WINDOW_H / 2
				coin.VX = random:NextNumber(-70, 70)
				coin.VY = random:NextNumber(-190, -110)
				coin.Spin = random:NextNumber(8, 16)
				coin.Angle = random:NextNumber(0, math.pi)
				coin.Label.Visible = true
				launched += 1
				activeCoins += 1
			end
		end
	end

	local jackpot = frame({
		Name = "Jackpot",
		Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 20,
		Parent = card,
	})
	round(jackpot, 8)
	local jackpotBg = frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(60, 0, 20),
		BackgroundTransparency = 0.12,
		ZIndex = 20,
		Parent = jackpot,
	})
	round(jackpotBg, 8)
	local rays = UIUtil.Rays(jackpot, GOLD, 8, 260, UDim2.fromScale(0.5, 0.5), 21)
	local jackpotLabel = UIUtil.Label({
		Text = Locale.T("JACKPOT!"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.new(1, -20, 0, 32),
		MaxTextSize = 30,
		ZIndex = 22,
		Parent = jackpot,
	})
	vGradient(jackpotLabel, { { 0, GOLD_LIGHT }, { 1, Color3.fromRGB(255, 150, 0) } })
	local jackpotStroke = UIUtil.Stroke(jackpotLabel, Color3.fromRGB(80, 20, 0), 2, 0)
	jackpotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local jackpotAmount = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.new(1, -20, 0, 18),
		MaxTextSize = 17,
		ZIndex = 22,
		Parent = jackpot,
	})
	local jackpotScale = Create("UIScale", { Parent = jackpot })
	local jackpotUntil = 0

	local function showJackpot(amountText: string)
		jackpot.Visible = true
		jackpotAmount.Text = amountText
		jackpotScale.Scale = 0.3
		UIUtil.Tween(jackpotScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		jackpotUntil = os.clock() + 3
	end

	------------------------------------------------------------------
	-- Fermée : Data.CasinoEnabled = false (règle calculée par le serveur)
	------------------------------------------------------------------
	local function casinoEnabled(): boolean
		local data = ctx.State.Data
		if data and data.CasinoEnabled ~= nil then
			return data.CasinoEnabled == true
		end
		return config.Enabled ~= false
	end

	local closedVeil = Create("TextButton", {
		Name = "Closed",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 4, 10),
		BackgroundTransparency = 0.25,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 50,
		Visible = false,
		Parent = card,
	})
	round(closedVeil, 18)
	local sign = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(200, 70),
		BackgroundColor3 = WHITE,
		Rotation = -3,
		ZIndex = 51,
		Parent = closedVeil,
	})
	round(sign, 12)
	vGradient(sign, { { 0, Color3.fromRGB(235, 60, 70) }, { 1, Color3.fromRGB(150, 10, 30) } })
	goldStroke(sign, 2)
	UIUtil.Label({
		Text = Locale.T("🚧 CLOSED 🚧"),
		Font = Theme.Fonts.Title,
		TextColor3 = GOLD_LIGHT,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(1, -20, 0, 30),
		MaxTextSize = 26,
		ZIndex = 52,
		Parent = sign,
	})
	UIUtil.Label({
		Text = Locale.T("Come back later 😴"),
		Font = Theme.Fonts.Body,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.new(1, -20, 0, 16),
		MaxTextSize = 13,
		ZIndex = 52,
		Parent = sign,
	})

	------------------------------------------------------------------
	-- Affichage des jetons / du bouton (appelé 4 fois par seconde)
	------------------------------------------------------------------
	local enabled = true
	local spinning = false
	local lastTokens = -1
	local canPlay = false

	local function refreshTokens()
		local tokens, progress, remaining = currentTokens()
		local max = tokenBase.Max
		tokenCount.Text = string.format("%d<font color=\"#C89080\" size=\"12\"> / %d</font>", tokens, max)
		if tokens >= max then
			barFill.Size = UDim2.fromScale(1, 1)
			timerLabel.Text = Locale.T("FULL") .. " ✨"
		else
			barFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
			timerLabel.Text = Locale.T("+1 in %s", clockText(remaining))
		end
		if lastTokens >= 0 and tokens > lastTokens and not spinning then
			-- Nouveau jeton : la pièce saute
			coinScale.Scale = 1.35
			UIUtil.Tween(coinScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		lastTokens = tokens

		canPlay = enabled and not spinning and tokens >= 1
		playGradient.Enabled = canPlay
		playButton.BackgroundColor3 = canPlay and WHITE or Color3.fromRGB(125, 105, 110)
		playShine.BackgroundTransparency = canPlay and 0.6 or 0.85
		playStroke.Color = canPlay and Color3.fromRGB(90, 40, 0) or Color3.fromRGB(60, 30, 40)
		playSweep.Visible = canPlay
		pullHint.Visible = canPlay
		if spinning then
			playLabel.Text = Locale.T("SPIN")
			playSub.Text = Locale.T("Good luck! 🍀")
		elseif tokens >= 1 or not enabled then
			playLabel.Text = Locale.T("SPIN")
			playSub.Text = Locale.T("FREE · 1 token")
		else
			playLabel.Text = Locale.T("NO TOKENS")
			playSub.Text = Locale.T("Next in %s", clockText(remaining))
		end
		playLabel.TextColor3 = canPlay and Color3.fromRGB(80, 20, 0) or Color3.fromRGB(235, 220, 225)
		playSub.TextColor3 = canPlay and Color3.fromRGB(120, 45, 0) or Color3.fromRGB(220, 195, 200)
	end

	local function applyState()
		local data = ctx.State.Data
		if data and not spinning then
			readServerTokens(data.Casino)
		end
		local now = casinoEnabled()
		closedVeil.Visible = not now
		if now ~= enabled then
			enabled = now
			if not now then
				setInfo(Locale.T("Closed for now 😴"), LED_TEXT)
				setPaytable(false)
			end
		end
		refreshTokens()
	end
	enabled = not casinoEnabled() -- force la première application
	applyState()
	ctx.Connect(ctx.State.Changed, applyState)

	------------------------------------------------------------------
	-- Animation (rouleaux, ampoules, ligne de gain, pièces, gros lot)
	------------------------------------------------------------------
	local partyUntil = 0
	local winGlowUntil = 0
	local bulbClock = 0
	local bulbStep = 0
	local elapsed = 0
	local slowClock = 0
	local partyColors = { Theme.Colors.Yellow, Theme.Colors.Cyan, Theme.Colors.Pink, Theme.Colors.Green, WHITE, Theme.Colors.Orange }
	local lastParty = false
	local nextSweep = 2

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		local reelsMoving = false
		for _, reel in ipairs(reels) do
			if reel.Mode ~= "idle" then
				reelsMoving = true
				break
			end
		end
		-- Hors écran et rien d'important en cours : on ne dessine rien
		if not reelsMoving and activeCoins == 0 and not isVisible() then
			return
		end
		elapsed += dt
		local now = os.clock()

		for _, reel in ipairs(reels) do
			if reel.Mode == "spin" then
				reel.Speed = math.min(MAX_SPEED, reel.Speed + dt * 70)
				reel.Pos += reel.Speed * dt
				renderReel(reel)
			elseif reel.Mode == "stop" then
				reel.StopT += dt
				local t = math.min(1, reel.StopT / reel.StopDur)
				reel.Pos = reel.StopFrom + (reel.StopTo - reel.StopFrom) * easeOutSoftBack(t)
				reel.Speed = MAX_SPEED * (1 - t) * (1 - t)
				if t >= 1 then
					reel.Pos = reel.StopTo
					reel.Speed = 0
					reel.Mode = "idle"
					ctx.Sound.Play("SlotSpin", 0.9 + random:NextNumber(0, 0.3))
					reel.Scale.Scale = 1.06
					UIUtil.Tween(reel.Scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				end
				renderReel(reel)
			end
		end

		-- Ampoules : chenillard (1 sur 3), ou arc-en-ciel rapide en cas de gain
		local party = now < partyUntil
		bulbClock += dt
		local interval = party and 0.06 or (spinning and 0.08 or 0.22)
		if bulbClock >= interval or party ~= lastParty then
			bulbClock = 0
			bulbStep += 1
			lastParty = party
			for index, bulb in ipairs(bulbs) do
				if party then
					local color = partyColors[((index + bulbStep) % #partyColors) + 1]
					bulb.Frame.BackgroundColor3 = color
					bulb.Frame.BackgroundTransparency = 0
					bulb.Stroke.Color = color
					bulb.Stroke.Transparency = 0.3
				else
					local on = (bulb.Order + bulbStep) % 3 == 0
					bulb.Frame.BackgroundColor3 = on and GOLD_LIGHT or GOLD_DARK
					bulb.Frame.BackgroundTransparency = on and 0 or 0.35
					bulb.Stroke.Color = GOLD
					bulb.Stroke.Transparency = on and 0.35 or 1
				end
			end
		end

		-- Titre : dégradé qui ondule, pulse pendant la fête
		titleGradient.Offset = Vector2.new(0, math.sin(elapsed * 2) * 0.25)
		titleScale.Scale = party and (1 + math.abs(math.sin(elapsed * 10)) * 0.08) or 1

		-- Ligne de gain : respiration, éclatante après un gain
		local winGlow = now < winGlowUntil
		local wave = math.sin(elapsed * (winGlow and 14 or 3))
		if winGlow then
			paylineGlow.BackgroundColor3 = GOLD
			payline.BackgroundColor3 = GOLD_LIGHT
			paylineGlow.Size = UDim2.new(1, -4, 0, 18 + wave * 4)
			paylineGlow.BackgroundTransparency = 0.1
		else
			paylineGlow.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
			payline.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
			paylineGlow.Size = UDim2.new(1, -4, 0, 12)
			paylineGlow.BackgroundTransparency = 0.55 + wave * 0.15
		end
		local push = math.abs(math.sin(elapsed * 4)) * 2
		arrows[1].Position = UDim2.new(0, -8 + push, 0.5, 0)
		arrows[2].Position = UDim2.new(1, 8 - push, 0.5, 0)

		-- Flèche du levier et reflet du bouton
		if canPlay then
			pullHint.Position = UDim2.fromOffset(leverX, knobTop + 22 + math.abs(math.sin(elapsed * 3)) * 5)
			nextSweep -= dt
			if nextSweep <= 0 then
				nextSweep = 3.5
				playSweep.Position = UDim2.new(-0.3, 0, 0.5, 0)
				UIUtil.Tween(playSweep, 0.7, { Position = UDim2.new(1.3, 0, 0.5, 0) }, Enum.EasingStyle.Quad)
			end
		end

		-- Pièces (gravité)
		if activeCoins > 0 then
			for _, coin in ipairs(coins) do
				if coin.Active then
					coin.VY += 520 * dt
					coin.X += coin.VX * dt
					coin.Y += coin.VY * dt
					if coin.Y > H + 20 then
						coin.Active = false
						coin.Label.Visible = false
						activeCoins -= 1
					else
						coin.Angle += coin.Spin * dt
						coin.Label.Position = UDim2.fromOffset(coin.X, coin.Y)
						coin.Label.Size = UDim2.fromOffset(math.max(2, 14 * math.abs(math.cos(coin.Angle))), 14)
					end
				end
			end
		end

		-- Bannière gros lot : rayons qui tournent, puis disparition
		if jackpot.Visible then
			rays.Rotation = (rays.Rotation + dt * 60) % 360
			jackpotLabel.Rotation = math.sin(elapsed * 6) * 3
			if now > jackpotUntil then
				jackpot.Visible = false
			end
		end

		-- Jetons / minuteur : 4 fois par seconde
		slowClock += dt
		if slowClock >= 0.25 then
			slowClock = 0
			refreshTokens()
		end
	end)

	------------------------------------------------------------------
	-- Partie
	------------------------------------------------------------------
	local function stopReel(reel, id: string, extraDelay: number?)
		local base = math.floor(reel.Pos)
		local target = base + 5 + (extraDelay and 3 or 0)
		reel.Strip[wrap(target)] = id
		reel.StopFrom = reel.Pos
		reel.StopTo = target
		reel.StopT = 0
		local distance = target - reel.Pos
		reel.StopDur = math.clamp(3.9 * distance / math.max(reel.Speed, 1), 0.5, extraDelay and 2 or 1.3)
		reel.Mode = "stop"
	end

	local function allStopped(): boolean
		for _, reel in ipairs(reels) do
			if reel.Mode ~= "idle" then
				return false
			end
		end
		return true
	end

	-- Attend `seconds` ; renvoie false si le stimulus a été arrêté entre-temps
	local function waitAlive(seconds: number): boolean
		local finish = os.clock() + seconds
		while os.clock() < finish do
			if not ctx.IsAlive() then
				return false
			end
			task.wait()
		end
		return ctx.IsAlive()
	end

	local function randomMissIds(): { string }
		-- Trois symboles différents (si possible) : on ne ment pas au joueur
		local pool = {}
		for _, symbol in ipairs(symbols) do
			table.insert(pool, symbol.Id)
		end
		for i = #pool, 2, -1 do
			local j = random:NextInteger(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
		return { pool[1], pool[2] or pool[1], pool[3] or pool[1] }
	end

	local function highlightWinners(ids: { string })
		local counts = {}
		for _, id in ipairs(ids) do
			counts[id] = (counts[id] or 0) + 1
		end
		for index, reel in ipairs(reels) do
			if (counts[ids[index]] or 0) >= 2 then
				local glow = reel.Glow
				task.spawn(function()
					for _ = 1, 4 do
						if not glow.Parent then
							return
						end
						UIUtil.Tween(glow, 0.18, { BackgroundTransparency = 0.05 })
						task.wait(0.2)
						if not glow.Parent then
							return
						end
						UIUtil.Tween(glow, 0.18, { BackgroundTransparency = 0.6 })
						task.wait(0.2)
					end
					if glow.Parent then
						UIUtil.Tween(glow, 0.3, { BackgroundTransparency = 1 })
					end
				end)
			end
		end
	end

	local function showResult(result, ids: { string })
		local reward = tonumber(result.Reward) or 0
		local matched = ctx.Formulas.GetCasinoMultiplier(ids)
		local big = result.Big == true or matched >= 240
		local center = UDim2.fromOffset(WINDOW_X + WINDOW_W / 2, WINDOW_Y + WINDOW_H / 2)
		local text = "+" .. Format.Format(reward)

		if matched > 0 then
			local triple = ids[1] == ids[2] and ids[2] == ids[3]
			highlightWinners(ids)
			partyUntil = os.clock() + (big and 3.5 or (triple and 2.4 or 1.6))
			winGlowUntil = os.clock() + 2
			ctx.Sound.Play("SlotWin", big and 1.1 or 1)
			ctx.FloatText(card, center, text, GOLD, big and 34 or (triple and 30 or 26))
			local winTexts = Locale.Pick(WIN_TEXTS)
			setInfo(winTexts[random:NextInteger(1, #winTexts)] .. " " .. text, GOLD_LIGHT, 3)
			UIUtil.Tween(windowStroke, 0.1, { Color = WHITE, Thickness = 3, Transparency = 0 })
			task.delay(0.6, function()
				if windowStroke.Parent then
					UIUtil.Tween(windowStroke, 0.4, { Color = GOLD, Thickness = 1.5, Transparency = 0.3 })
				end
			end)
			dropCoins(big and MAX_COINS or (triple and 8 or 4))
			if effectsOn() then
				ctx.Effects.Burst(card, center, GOLD, triple and 18 or 10)
			end
			if big then
				showJackpot(text)
				ctx.Sound.Play("Jackpot", 1)
				ctx.Effects.Flash(GOLD, 0.45)
				ctx.Effects.BigMessage(Locale.T("🎰 JACKPOT! %s", text), GOLD, 2.5)
				if effectsOn() then
					ctx.Effects.Confetti(70)
				end
			elseif triple and effectsOn() then
				ctx.Effects.Confetti(25)
			end
		else
			-- Rien d'aligné : petit lot de consolation
			ctx.Sound.Play("Error", 0.75)
			UIUtil.Shake(window)
			ctx.FloatText(card, center, text, WHITE, 20)
			local missTexts = Locale.Pick(MISS_TEXTS)
			setInfo(missTexts[random:NextInteger(1, #missTexts)], Color3.fromRGB(255, 215, 170), 2.5)
		end
	end

	local function play()
		if spinning or not ctx.IsAlive() then
			return
		end
		if not enabled or not casinoEnabled() then
			ctx.Sound.Play("Error", 1)
			UIUtil.Shake(playButton)
			return
		end
		local tokens, _, remaining = currentTokens()
		if tokens < 1 then
			ctx.Sound.Play("Error", 1)
			UIUtil.Shake(playButton)
			UIUtil.Shake(tokenPanel)
			setInfo(Locale.T("No tokens! Next one in %s ⏳", clockText(remaining)), BAD, 2)
			return
		end

		spinning = true
		setPaytable(false)
		jackpot.Visible = false
		pullLever()
		ctx.Sound.Play("SlotSpin", 1)
		for _, reel in ipairs(reels) do
			reel.Mode = "spin"
			reel.Glow.BackgroundTransparency = 1
		end
		setInfo(Locale.T("Spinning… 🎲"), LED_TEXT)
		-- Le jeton part tout de suite (le serveur confirmera)
		tokenBase.Tokens = math.max(0, tokenBase.Tokens - 1)
		refreshTokens()

		task.spawn(function()
			local started = os.clock()
			local callOk, success, result = pcall(function()
				return ctx.Net.Function("CasinoSpin"):InvokeServer()
			end)
			if not waitAlive(math.max(0, MIN_SPIN_TIME - (os.clock() - started))) then
				return
			end

			local list = callOk and success == true and type(result) == "table" and (result.Symbols or result.Reels)
			local valid = type(list) == "table"
			local ids = {}
			if valid then
				for index = 1, 3 do
					local id = list[index]
					if type(id) ~= "string" or not symbolsById[id] then
						id = symbols[1].Id
					end
					ids[index] = id
				end
				readServerTokens(result)
			else
				ids = randomMissIds()
				-- Refusé : on reprend le dernier état connu
				local data = ctx.State.Data
				if data then
					readServerTokens(data.Casino)
				end
			end

			-- Arrêts successifs (suspense si les deux premiers sont identiques)
			for index = 1, 3 do
				local suspense = valid and index == 3 and ids[1] == ids[2]
				if suspense then
					setInfo(Locale.T("🤞 Come on… come on…"), Theme.Colors.Yellow)
					partyUntil = os.clock() + 1
				end
				stopReel(reels[index], ids[index], suspense and 1 or nil)
				if not waitAlive(0.32) then
					return
				end
			end
			while not allStopped() do
				if not ctx.IsAlive() then
					return
				end
				task.wait()
			end

			if valid then
				showResult(result, ids)
			else
				local message = (callOk and type(result) == "string") and result or Locale.T("The machine is on strike 🔧")
				ctx.Sound.Play("Error", 1)
				UIUtil.Shake(window)
				setInfo(message, BAD, 2.5)
			end

			spinning = false
			refreshTokens()
		end)
	end

	ctx.Connect(playButton.Activated, play)
	ctx.Connect(leverButton.Activated, play)

	------------------------------------------------------------------
	-- Écran LED au repos : petites annonces
	------------------------------------------------------------------
	local bestSymbol = symbols[1]
	for _, symbol in ipairs(symbols) do
		if (symbol.Triple or 0) > (bestSymbol.Triple or 0) then
			bestSymbol = symbol
		end
	end
	local attract = table.clone(Locale.Pick(ATTRACT_TEXTS))

	task.spawn(function()
		local tick = 0
		while ctx.IsAlive() do
			if enabled and not spinning and os.clock() >= infoLockUntil then
				tick += 1
				local phase = tick % 3
				if phase == 0 and bestSymbol then
					local icon = bestSymbol.Icon
					setInfo(Locale.T("Triple %s = %s!", icon .. icon .. icon, "+" .. Format.Format(rewardFor(bestSymbol.Triple or 0))), GOLD_LIGHT)
				elseif phase == 1 then
					setInfo(attract[random:NextInteger(1, #attract)], Color3.fromRGB(255, 220, 150))
				else
					setInfo(Locale.T("1 free token every %s of play", clockText(tokenBase.Interval)), LED_TEXT)
				end
			end
			task.wait(3)
		end
	end)
end

return Casino
