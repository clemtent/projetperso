--[[
	Casino (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Casino

	Machine à sous "de luxe" (UNIQUEMENT avec la Dopamine du jeu) dans le
	slot R2 (288x180) :
	  - carrosserie bordeaux laquée, cadre chromé et liseré or dégradé ;
	  - fronton lumineux : titre doré + ampoules en chenillard (arc-en-ciel
	    en folie quand on gagne) ;
	  - 3 rouleaux en verre bombé (ombre de cylindre, reflet de vitre,
	    séparateurs chromés) avec une ligne de gain lumineuse et flèches ;
	  - écran LED (mise, messages) + bouton "GAINS" qui déroule la table
	    des paiements (paires / triples de Config.Casino + taux de retour) ;
	  - jetons de poker (Config.Casino.BetFractions en %) : le jeton choisi
	    se soulève et brille ;
	  - gros bouton "JOUER" + levier chromé animé (tirage, rebond élastique) ;
	  - gain : halo des symboles gagnants, pièces qui tombent ; JACKPOT
	    (x25 et plus) : bannière à rayons tournants, flash, confettis.
	Le résultat vient TOUJOURS du serveur (CasinoSpin) : les rouleaux se
	lancent tout de suite puis s'arrêtent un par un sur les symboles reçus
	(petit suspense si les deux premiers sont identiques).
	Fermée (State.Data.CasinoEnabled = false, ex. quand le jeu vend de la
	Dopamine contre des Robux) : panneau "FERMÉ" par-dessus la machine,
	et CasinoSpin n'est JAMAIS appelé.
]]

local Casino = {}
Casino.Slot = "R2"

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

-- Dimensions (pixels "design") : la carrosserie est rentrée de 2 px pour
-- que son contour ne soit pas coupé par le slot (ClipsDescendants)
local W = 284
local H = 176

local WINDOW_X, WINDOW_Y = 8, 36
local WINDOW_W, WINDOW_H = 230, 70
local REEL_GAP = 4
local REEL_W = math.floor((WINDOW_W - 10 - REEL_GAP * 2) / 3)
local REEL_H = WINDOW_H - 10
local CELL_H = 40 -- hauteur d'un symbole sur le rouleau
local STRIP_LENGTH = 24 -- symboles par bande (recyclés en boucle)
local MAX_SPEED = 20 -- symboles / seconde
local MIN_SPIN_TIME = 0.8

local LED_Y = 110
local ROW_Y = 131
local CHIP_SIZE = 34
local MAX_CHIPS = 4
local BULBS_PER_SIDE = 8 -- 2 rangées x 4 de chaque côté du titre
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

-- Couleurs des jetons (fond, centre)
local CHIP_COLORS = {
	{ Color3.fromRGB(240, 240, 244), Color3.fromRGB(255, 255, 255) },
	{ Color3.fromRGB(214, 36, 50), Color3.fromRGB(245, 90, 100) },
	{ Color3.fromRGB(30, 110, 220), Color3.fromRGB(90, 160, 250) },
	{ Color3.fromRGB(28, 28, 34), Color3.fromRGB(70, 70, 82) },
}

local LOSS_TEXTS = {
	en = {
		"So close! (not really)",
		"The house always wins 🏠",
		"Try again, it'll hit… maybe",
		"Your Dopamine went on vacation 🏖️",
		"Ouch. Let's call that a test run.",
		"The brain said no 🧠❌",
		"That was just practice… oh wait, no.",
		"The reels have stage fright today",
	},
	fr = {
		"Presque ! (non)",
		"La maison gagne toujours 🏠",
		"Retente, ça va passer… peut-être",
		"Ta Dopamine est partie en vacances 🏖️",
		"Aïe. On dira que c'était un test.",
		"Le cerveau a dit non 🧠❌",
		"C'était pour du beurre… ah non.",
		"Les rouleaux ont le trac aujourd'hui",
	},
}

local WIN_TEXTS = {
	en = {
		"WINNER! 🎉",
		"Now we're rolling! 💸",
		"Lady Luck is smiling 😎",
		"Dopamine waterfall! 🤑",
	},
	fr = {
		"GAGNÉ ! 🎉",
		"Ça tourne bien ! 💸",
		"La chance te sourit 😎",
		"Dopamine en cascade ! 🤑",
	},
}

local ATTRACT_TEXTS = {
	en = {
		"Try your luck! 🍀",
		"Pair = money back (almost)",
		"No Robux here, promise 🤞",
		"Tap PAYOUTS to see the prizes 📜",
	},
	fr = {
		"Tente ta chance ! 🍀",
		"Paire = remboursé (ou presque)",
		"Aucun Robux ici, promis 🤞",
		"Touche GAINS pour voir les gains 📜",
	},
}

-- Recul "Back" plus doux que la version standard (petit rebond à l'arrêt)
local function easeOutSoftBack(t: number): number
	local c1 = 0.9
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

local function percentText(fraction: number): string
	local percent = fraction * 100
	local rounded = math.floor(percent + 0.5)
	if math.abs(percent - rounded) < 1e-6 then
		return tostring(rounded) .. "%"
	end
	return string.format("%.1f%%", percent)
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

	local function getDopamine(): number
		local data = ctx.State.Data
		return (data and tonumber(data.Dopamine)) or 0
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

	-- Contour doré dégradé (UIGradient sous l'UIStroke)
	local function goldStroke(parent: Instance, thickness: number): UIStroke
		local stroke = UIUtil.Stroke(parent, WHITE, thickness, 0)
		vGradient(stroke, { { 0, GOLD_LIGHT }, { 0.45, GOLD }, { 1, GOLD_DARK } }, 90)
		return stroke
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
	goldStroke(card, 2) -- (2 px comme les autres cartes : 284 + 2 x 2 = largeur du slot, contour jamais coupé)

	-- Reflet laqué (bande claire en diagonale)
	local sheen = frame({
		Name = "Sheen",
		Size = UDim2.new(1, -8, 0.5, 0),
		Position = UDim2.fromOffset(4, 3),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.86,
		ZIndex = 1,
		Parent = card,
	})
	round(sheen, 15)
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = sheen,
	})

	-- Texte flottant dessiné dans le calque Overlay : il monte de 100 px et
	-- serait coupé par le slot (ClipsDescendants). `point` = position en
	-- pixels "design" dans la carrosserie.
	local function floatOnOverlay(point: Vector2, text: string, color: Color3?, size: number?)
		local ratio = card.AbsoluteSize.X / W
		local canvas = ctx.Interface.ScreenToCanvas(card.AbsolutePosition + point * ratio)
		ctx.FloatText(ctx.Overlay, UDim2.fromOffset(canvas.X, canvas.Y), text, color, size)
	end

	------------------------------------------------------------------
	-- Fronton : titre doré + ampoules en chenillard
	------------------------------------------------------------------
	local marquee = frame({
		Name = "Marquee",
		Position = UDim2.fromOffset(8, 5),
		Size = UDim2.fromOffset(W - 16, 27),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = card,
	})
	round(marquee, 9)
	vGradient(marquee, { { 0, Color3.fromRGB(60, 8, 22) }, { 1, Color3.fromRGB(26, 2, 10) } })
	goldStroke(marquee, 1.5)

	local titleLabel = UIUtil.Label({
		Name = "Title",
		Text = "★ DOPA SLOTS ★",
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(128, 22),
		MaxTextSize = 17,
		ZIndex = 4,
		Parent = marquee,
	})
	local titleGradient = vGradient(titleLabel, { { 0, GOLD_LIGHT }, { 0.5, GOLD }, { 1, Color3.fromRGB(230, 140, 20) } })
	local titleStroke = UIUtil.Stroke(titleLabel, Color3.fromRGB(70, 20, 0), 1.2, 0)
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local titleScale = Create("UIScale", { Parent = titleLabel })

	-- Ampoules : une seule Frame chacune, le "halo" est son UIStroke
	local bulbs: { { Frame: Frame, Stroke: UIStroke } } = {}
	local marqueeW = W - 16
	for side = 0, 1 do
		for column = 0, BULBS_PER_SIDE / 2 - 1 do
			for row = 0, 1 do
				local x
				if side == 0 then
					x = 12 + column * 16 + row * 8
				else
					x = marqueeW - 12 - (BULBS_PER_SIDE / 2 - 1 - column) * 16 - (1 - row) * 8
				end
				local bulb = frame({
					Name = "Bulb",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(x, row == 0 and 8 or 19),
					Size = UDim2.fromOffset(6, 6),
					BackgroundColor3 = GOLD,
					ZIndex = 3,
					Parent = marquee,
				})
				round(bulb)
				local stroke = UIUtil.Stroke(bulb, GOLD, 2, 0.55)
				table.insert(bulbs, { Frame = bulb, Stroke = stroke })
			end
		end
	end
	-- Ordre du chenillard : de gauche à droite
	table.sort(bulbs, function(a, b)
		return a.Frame.Position.X.Offset < b.Frame.Position.X.Offset
	end)

	------------------------------------------------------------------
	-- Fenêtre des rouleaux : cadre chromé + verre
	------------------------------------------------------------------
	local chrome = frame({
		Name = "Chrome",
		Position = UDim2.fromOffset(WINDOW_X - 3, WINDOW_Y - 3),
		Size = UDim2.fromOffset(WINDOW_W + 6, WINDOW_H + 6),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = card,
	})
	round(chrome, 12)
	vGradient(chrome, { { 0, CHROME_LIGHT }, { 0.35, Color3.fromRGB(190, 194, 206) }, { 0.5, CHROME_DARK }, { 0.7, Color3.fromRGB(210, 214, 224) }, { 1, Color3.fromRGB(150, 154, 168) } })
	UIUtil.Stroke(chrome, Color3.fromRGB(50, 10, 20), 1, 0.2)

	local window = frame({
		Name = "Window",
		Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		BackgroundColor3 = Color3.fromRGB(16, 4, 8),
		ZIndex = 3,
		Parent = card,
	})
	round(window, 9)
	local windowStroke = UIUtil.Stroke(window, GOLD, 1.5, 0.3)

	local reels = {}
	local function wrap(index: number): number
		return ((index - 1) % STRIP_LENGTH) + 1
	end

	for r = 1, 3 do
		local reelFrame = frame({
			Name = "Reel" .. r,
			Position = UDim2.fromOffset(5 + (r - 1) * (REEL_W + REEL_GAP), 5),
			Size = UDim2.fromOffset(REEL_W, REEL_H),
			BackgroundColor3 = WHITE,
			ClipsDescendants = true,
			ZIndex = 4,
			Parent = window,
		})
		round(reelFrame, 6)
		-- Cylindre : ivoire au centre, plus sombre en haut / en bas
		vGradient(reelFrame, {
			{ 0, Color3.fromRGB(170, 160, 150) },
			{ 0.28, Color3.fromRGB(240, 234, 222) },
			{ 0.5, Color3.fromRGB(255, 253, 246) },
			{ 0.72, Color3.fromRGB(240, 234, 222) },
			{ 1, Color3.fromRGB(170, 160, 150) },
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
		Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 0.6),
			}),
			Parent = glow,
		})

		-- Bande de symboles (mélangés)
		local strip = {}
		for i = 1, STRIP_LENGTH do
			strip[i] = symbols[((i - 1) % #symbols) + 1].Id
		end
		for i = STRIP_LENGTH, 2, -1 do
			local j = random:NextInteger(1, i)
			strip[i], strip[j] = strip[j], strip[i]
		end

		local labels = {}
		for k = 1, 4 do
			local label = UIUtil.Label({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(REEL_W, CELL_H - 4),
				Position = UDim2.fromOffset(REEL_W / 2, REEL_H / 2),
				Font = Theme.Fonts.Title,
				MaxTextSize = 30,
				ZIndex = 5,
				Parent = reelFrame,
			})
			labels[k] = { Label = label, Shown = "" }
		end

		-- Ombre intérieure (haut / bas) pour la profondeur
		local shade = frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			ZIndex = 6,
			Parent = reelFrame,
		})
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(0.25, 0.85),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(0.75, 0.85),
				NumberSequenceKeypoint.new(1, 0.15),
			}),
			Parent = shade,
		})
		-- Reflet de la vitre (bande blanche en haut)
		local glass = frame({
			Position = UDim2.fromOffset(3, 2),
			Size = UDim2.new(1, -6, 0, 14),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.55,
			ZIndex = 7,
			Parent = reelFrame,
		})
		round(glass, 5)
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = glass,
		})

		reels[r] = {
			Frame = reelFrame,
			Glow = glow,
			Strip = strip,
			Labels = labels,
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
			Position = UDim2.fromOffset(5 + r * (REEL_W + REEL_GAP) - REEL_GAP / 2, 3),
			Size = UDim2.fromOffset(3, WINDOW_H - 6),
			BackgroundColor3 = WHITE,
			ZIndex = 8,
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
		ZIndex = 8,
		Parent = window,
	})
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = paylineGlow,
	})
	local payline = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 0, 2),
		BackgroundColor3 = Color3.fromRGB(255, 60, 60),
		BackgroundTransparency = 0.2,
		ZIndex = 9,
		Parent = window,
	})
	local arrows = {}
	for side = 0, 1 do
		local arrow = UIUtil.Label({
			Text = side == 0 and "▶" or "◀",
			Font = Theme.Fonts.Title,
			TextColor3 = GOLD,
			AnchorPoint = Vector2.new(side, 0.5),
			Position = UDim2.new(side, side == 0 and -12 or 12, 0.5, 0),
			Size = UDim2.fromOffset(10, 14),
			MaxTextSize = 11,
			ZIndex = 9,
			Parent = window,
		})
		table.insert(arrows, arrow)
	end

	-- Affiche la bande d'un rouleau selon sa position (symbole `Pos` au centre)
	local function renderReel(reel)
		local base = math.floor(reel.Pos)
		local blur = reel.Speed > 8
		for k = 1, 4 do
			local index = base - 1 + (k - 1)
			local entry = reel.Labels[k]
			local label = entry.Label
			local id = reel.Strip[wrap(index)]
			if entry.Shown ~= id then
				entry.Shown = id
				local symbol = symbolsById[id]
				label.Text = symbol and symbol.Icon or "?"
			end
			-- Les indices plus grands sont au-dessus : la bande descend
			label.Position = UDim2.fromOffset(REEL_W / 2, REEL_H / 2 - (index - reel.Pos) * CELL_H)
			label.TextTransparency = blur and 0.4 or 0
		end
	end

	for _, reel in ipairs(reels) do
		renderReel(reel)
	end

	------------------------------------------------------------------
	-- Levier chromé
	------------------------------------------------------------------
	local leverX = WINDOW_X + WINDOW_W + (W - (WINDOW_X + WINDOW_W)) / 2
	local leverBottom = 94
	local knobTop = 44
	local stickLength = leverBottom - knobTop

	-- Support (boîtier chromé fixé sur le côté)
	local mount = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(leverX, leverBottom + 4),
		Size = UDim2.fromOffset(26, 20),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = card,
	})
	round(mount, 6)
	vGradient(mount, { { 0, CHROME_LIGHT }, { 0.5, Color3.fromRGB(170, 174, 188) }, { 1, CHROME_DARK } })
	UIUtil.Stroke(mount, Color3.fromRGB(40, 8, 16), 1, 0.3)
	local slot = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(8, 12),
		BackgroundColor3 = Color3.fromRGB(30, 30, 36),
		ZIndex = 4,
		Parent = mount,
	})
	round(slot, 4)

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
		Size = UDim2.fromOffset(22, 22),
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
		Size = UDim2.fromOffset(8, 5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.2,
		Rotation = -25,
		ZIndex = 7,
		Parent = knob,
	})
	round(knobShine)

	local leverButton = Create("TextButton", {
		Name = "Lever",
		Position = UDim2.fromOffset(leverX - 18, knobTop - 14),
		Size = UDim2.fromOffset(36, leverBottom - knobTop + 28),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 12,
		Parent = card,
	})

	local function pullLever()
		local down = leverBottom - 8
		UIUtil.Tween(knob, 0.16, { Position = UDim2.fromOffset(leverX, down) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UIUtil.Tween(stick, 0.16, { Size = UDim2.fromOffset(6, leverBottom + 2 - down) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			if knob.Parent and stick.Parent then
				UIUtil.Tween(knob, 0.8, { Position = UDim2.fromOffset(leverX, knobTop) }, Enum.EasingStyle.Elastic)
				UIUtil.Tween(stick, 0.8, { Size = UDim2.fromOffset(6, stickLength) }, Enum.EasingStyle.Elastic)
			end
		end)
	end

	-- Survol du levier : la boule brille un peu
	ctx.Connect(leverButton.MouseEnter, function()
		UIUtil.Tween(knob, 0.15, { Size = UDim2.fromOffset(25, 25) }, Enum.EasingStyle.Back)
	end)
	ctx.Connect(leverButton.MouseLeave, function()
		UIUtil.Tween(knob, 0.15, { Size = UDim2.fromOffset(22, 22) })
	end)

	------------------------------------------------------------------
	-- Écran LED (mise, résultat, blagues) + bouton "GAINS"
	------------------------------------------------------------------
	local led = frame({
		Name = "Led",
		Position = UDim2.fromOffset(8, LED_Y),
		Size = UDim2.fromOffset(W - 16, 17),
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
		Position = UDim2.fromOffset(6, 1),
		Size = UDim2.new(1, -60, 1, -2),
		MaxTextSize = 13,
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
		Name = "Paytable",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.fromOffset(50, 13),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = Locale.T("📜 PAYOUTS"),
		TextColor3 = Color3.fromRGB(60, 20, 0),
		TextSize = 10,
		TextScaled = true, -- le texte (traduit) reste dans la pastille
		ZIndex = 5,
		Parent = led,
	})
	Create("UITextSizeConstraint", { MaxTextSize = 10, MinTextSize = 6, Parent = payButton })
	Create("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), Parent = payButton })
	round(payButton)
	vGradient(payButton, { { 0, GOLD_LIGHT }, { 1, GOLD } })

	------------------------------------------------------------------
	-- Table des paiements (se déroule par-dessus les rouleaux)
	------------------------------------------------------------------
	local paytable = frame({
		Name = "PaytablePanel",
		Position = UDim2.fromOffset(WINDOW_X, WINDOW_Y - 4),
		Size = UDim2.fromOffset(WINDOW_W, WINDOW_H + 8),
		BackgroundColor3 = Color3.fromRGB(20, 4, 10),
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 14,
		Parent = card,
	})
	round(paytable, 9)
	goldStroke(paytable, 1.5)
	local paytableScale = Create("UIScale", { Parent = paytable })

	local sorted = table.clone(symbols)
	table.sort(sorted, function(a, b)
		return (a.Triple or 0) > (b.Triple or 0)
	end)
	for index, symbol in ipairs(sorted) do
		if index > 6 then
			break
		end
		local column = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		UIUtil.Label({
			Text = string.format("%s%s%s <font color=\"#FFD24A\">%s</font>  %s%s %s",
				symbol.Icon, symbol.Icon, symbol.Icon, Format.Multiplier(symbol.Triple or 0),
				symbol.Icon, symbol.Icon, Format.Multiplier(symbol.Pair or 0)),
			RichText = true,
			Font = Theme.Fonts.Title,
			TextColor3 = WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(8 + column * (WINDOW_W / 2 - 4), 4 + row * 18),
			Size = UDim2.fromOffset(WINDOW_W / 2 - 12, 17),
			MaxTextSize = 12,
			ZIndex = 15,
			Parent = paytable,
		})
	end
	local rtpText = Locale.T("Pair = small win · Triple = big win")
	local rtpOk, rtp = pcall(function()
		return ctx.Formulas.GetCasinoRTP()
	end)
	if rtpOk and type(rtp) == "number" and rtp > 0 then
		rtpText = Locale.T("Average return: %d %% · the house wins a little 🏠", math.floor(rtp * 100 + 0.5))
	end
	UIUtil.Label({
		Text = rtpText,
		Font = Theme.Fonts.Body,
		TextColor3 = Color3.fromRGB(255, 220, 170),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -16, 0, 14),
		MaxTextSize = 11,
		ZIndex = 15,
		Parent = paytable,
	})

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
			paytable.Visible = true
			paytableScale.Scale = 0.6
			UIUtil.Tween(paytableScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			task.delay(7, function()
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

	------------------------------------------------------------------
	-- Jetons de mise + bouton JOUER
	------------------------------------------------------------------
	local fractions = config.BetFractions or { 0.01 }
	local selected = math.min(1, #fractions)
	local chips = {}

	local function currentBet(): number
		local fraction = fractions[selected] or 0.01
		return math.max(config.MinBet or 1, math.floor(getDopamine() * fraction))
	end

	local playLabel: TextLabel? = nil
	local betLabel: TextLabel? = nil
	local function refreshBetLabel()
		if betLabel then
			betLabel.Text = Locale.T("Bet %s", Format.Format(currentBet()))
		end
	end

	local function refreshChips()
		for index, chip in ipairs(chips) do
			local isSelected = index == selected
			chip.Stroke.Color = isSelected and GOLD or Color3.fromRGB(20, 20, 24)
			chip.Stroke.Thickness = isSelected and 2.5 or 1.2
			UIUtil.Tween(chip.Scale, 0.25, { Scale = isSelected and 1.1 or 0.94 }, Enum.EasingStyle.Back)
			UIUtil.Tween(chip.Button, 0.25, { Position = UDim2.new(0.5, 0, 0.5, isSelected and -4 or 0) }, Enum.EasingStyle.Back)
			UIUtil.Tween(chip.Shadow, 0.25, {
				BackgroundTransparency = isSelected and 0.72 or 0.6,
				Size = UDim2.fromOffset(isSelected and 26 or 30, 7),
			})
		end
		refreshBetLabel()
	end

	local chipCount = math.min(#fractions, MAX_CHIPS)
	for index = 1, chipCount do
		local fraction = fractions[index]
		local colors = CHIP_COLORS[index] or CHIP_COLORS[1]
		local holder = frame({
			Name = "ChipHolder" .. index,
			Position = UDim2.fromOffset(8 + (index - 1) * (CHIP_SIZE + 5), ROW_Y),
			Size = UDim2.fromOffset(CHIP_SIZE + 2, 40),
			ZIndex = 4,
			Parent = card,
		})
		-- Ombre au sol (ellipse)
		local shadow = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 18),
			Size = UDim2.fromOffset(30, 7),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.6,
			ZIndex = 4,
			Parent = holder,
		})
		round(shadow)
		local chip = Create("TextButton", {
			Name = "Chip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(CHIP_SIZE, CHIP_SIZE),
			BackgroundColor3 = colors[1],
			AutoButtonColor = false,
			Text = "",
			ZIndex = 5,
			Parent = holder,
		})
		round(chip)
		local stroke = UIUtil.Stroke(chip, Color3.fromRGB(20, 20, 24), 1.2, 0)
		-- Plaquettes blanches sur la tranche (4 encoches)
		local spotColor = index == 1 and Color3.fromRGB(214, 36, 50) or WHITE
		for spot = 0, 3 do
			local angle = math.rad(spot * 90 + 45)
			frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.cos(angle) * 13.5, 0.5, math.sin(angle) * 13.5),
				Size = UDim2.fromOffset(7, 4),
				Rotation = spot * 90 + 45 + 90,
				BackgroundColor3 = spotColor,
				ZIndex = 6,
				Parent = chip,
			})
		end
		local inner = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(CHIP_SIZE - 12, CHIP_SIZE - 12),
			BackgroundColor3 = WHITE,
			ZIndex = 6,
			Parent = chip,
		})
		round(inner)
		UIUtil.Gradient(inner, ColorSequence.new(colors[2], colors[1]), 90)
		UIUtil.Stroke(inner, spotColor, 1, 0.35)
		UIUtil.Label({
			Text = percentText(fraction),
			Font = Theme.Fonts.Number,
			TextColor3 = Theme.ContrastText(colors[1]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9, 0.62),
			MaxTextSize = 11,
			ZIndex = 7,
			Parent = inner,
		})
		local scale = Create("UIScale", { Scale = 0.94, Parent = chip })
		chips[index] = { Button = chip, Stroke = stroke, Scale = scale, Shadow = shadow }

		ctx.Connect(chip.Activated, function()
			if selected == index then
				return
			end
			selected = index
			refreshChips()
			ctx.Sound.Play("Click", 1.3 + index * 0.08)
			setInfo(Locale.T("Bet: %s Dopamine", Format.Format(currentBet())), GOLD_LIGHT, 1.5)
		end)
	end

	-- Bouton JOUER (rouge laqué, contour doré, reflet)
	local playX = 8 + chipCount * (CHIP_SIZE + 5) + 4
	local playButton = Create("TextButton", {
		Name = "Play",
		Position = UDim2.fromOffset(playX, ROW_Y + 1),
		Size = UDim2.fromOffset(W - 8 - playX, 38),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		Parent = card,
	})
	round(playButton, 12)
	local playGradient = vGradient(playButton, { { 0, Color3.fromRGB(255, 214, 80) }, { 0.5, Color3.fromRGB(255, 170, 20) }, { 1, Color3.fromRGB(200, 110, 0) } })
	UIUtil.Stroke(playButton, Color3.fromRGB(90, 40, 0), 1.5, 0)
	local playShine = frame({
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.new(1, -8, 0.45, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		ZIndex = 6,
		Parent = playButton,
	})
	round(playShine, 9)
	playLabel = UIUtil.Label({
		Text = Locale.T("SPIN"),
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(80, 20, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -8, 0, 20),
		MaxTextSize = 19,
		ZIndex = 7,
		Parent = playButton,
	})
	betLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = Color3.fromRGB(110, 40, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -8, 0, 12),
		MaxTextSize = 11,
		ZIndex = 7,
		Parent = playButton,
	})
	UIUtil.AnimateButton(playButton, 1.04, 0.93)
	refreshChips()

	local function setPlayEnabled(value: boolean)
		playButton:SetAttribute("Enabled", value)
		playGradient.Enabled = value
		playButton.BackgroundColor3 = value and WHITE or Color3.fromRGB(120, 110, 110)
		playShine.BackgroundTransparency = value and 0.6 or 0.85
		if playLabel then
			playLabel.TextTransparency = value and 0 or 0.4
		end
	end

	------------------------------------------------------------------
	-- Pièces qui tombent (réserve réutilisée) et bannière JACKPOT
	------------------------------------------------------------------
	local coins = {}
	for _ = 1, MAX_COINS do
		-- Pièce dorée dessinée (elle "tourne" en s'aplatissant)
		local coin = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 18,
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
		ZIndex = 16,
		Parent = card,
	})
	round(jackpot, 9)
	local jackpotBg = frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(60, 0, 20),
		BackgroundTransparency = 0.15,
		ZIndex = 16,
		Parent = jackpot,
	})
	round(jackpotBg, 9)
	local rays = UIUtil.Rays(jackpot, GOLD, 8, 260, UDim2.fromScale(0.5, 0.5), 17)
	local jackpotLabel = UIUtil.Label({
		Text = Locale.T("JACKPOT!"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(1, -20, 0, 34),
		MaxTextSize = 32,
		ZIndex = 18,
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
		ZIndex = 18,
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
	-- Fermé : Data.CasinoEnabled = false (règle calculée par le serveur)
	------------------------------------------------------------------
	local function casinoEnabled(): boolean
		local data = ctx.State.Data
		if data and data.CasinoEnabled ~= nil then
			return data.CasinoEnabled == true
		end
		-- Pas encore d'état (ou ancien serveur) : même règle que le serveur
		if config.Enabled == false then
			return false
		end
		local monetization = ctx.Config.Monetization
		if ctx.Config.IsSellingForRobux and monetization and monetization.DisableCasinoWhenSelling then
			return false
		end
		return true
	end

	-- Voile sombre + pancarte suspendue (TextButton : bloque les clics)
	local closedVeil = Create("TextButton", {
		Name = "Closed",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 4, 10),
		BackgroundTransparency = 0.25,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 30,
		Visible = false,
		Parent = card,
	})
	round(closedVeil, 18)
	-- Deux cordes + pancarte
	for side = -1, 1, 2 do
		frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, side * 46, 0, 8),
			Size = UDim2.fromOffset(2, 44),
			Rotation = -side * 12,
			BackgroundColor3 = Color3.fromRGB(200, 180, 140),
			ZIndex = 31,
			Parent = closedVeil,
		})
	end
	local sign = frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.fromOffset(math.min(210, W - 40), 86),
		BackgroundColor3 = WHITE,
		Rotation = -3,
		ZIndex = 32,
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
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -20, 0, 30),
		MaxTextSize = 26,
		ZIndex = 33,
		Parent = sign,
	})
	UIUtil.Label({
		Text = Locale.T("The slot machine is taking a break."),
		Font = Theme.Fonts.Body,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.new(1, -20, 0, 16),
		MaxTextSize = 13,
		ZIndex = 33,
		Parent = sign,
	})
	UIUtil.Label({
		Text = Locale.T("Come back later 😴"),
		Font = Theme.Fonts.Body,
		TextColor3 = Color3.fromRGB(255, 210, 210),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 63),
		Size = UDim2.new(1, -20, 0, 14),
		MaxTextSize = 12,
		ZIndex = 33,
		Parent = sign,
	})

	local enabled = true
	local spinning = false
	local function applyEnabled()
		local now = casinoEnabled()
		closedVeil.Visible = not now
		if now ~= enabled then
			enabled = now
			if not now then
				setInfo(Locale.T("Closed for now 😴"), LED_TEXT)
				setPaytable(false)
			end
		end
		setPlayEnabled(enabled and not spinning)
		refreshBetLabel()
	end
	enabled = not casinoEnabled() -- force la première application
	applyEnabled()
	ctx.Connect(ctx.State.Changed, applyEnabled)

	------------------------------------------------------------------
	-- Animation (rouleaux, ampoules, ligne de gain, pièces, jackpot)
	------------------------------------------------------------------
	local partyUntil = 0
	local winGlowUntil = 0
	local bulbClock = 0
	local bulbStep = 0
	local elapsed = 0
	local partyColors = { Theme.Colors.Yellow, Theme.Colors.Cyan, Theme.Colors.Pink, Theme.Colors.Green, WHITE, Theme.Colors.Orange }
	local lastParty = false

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
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
				reel.Speed = MAX_SPEED * (1 - t)
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
		local interval = party and 0.06 or (spinning and 0.1 or 0.22)
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
					local on = (index + bulbStep) % 3 == 0
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
		for index, arrow in ipairs(arrows) do
			local push = math.abs(math.sin(elapsed * 4)) * 2
			arrow.Position = UDim2.new(index - 1, (index == 1 and -12 or 12) + (index == 1 and push or -push), 0.5, 0)
			arrow.TextColor3 = winGlow and GOLD_LIGHT or GOLD
		end

		-- Pièces (gravité, rebond sur le bas de la machine)
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

		-- Bannière jackpot : rayons qui tournent, puis disparition
		if jackpot.Visible then
			rays.Rotation = (rays.Rotation + dt * 60) % 360
			jackpotLabel.Rotation = math.sin(elapsed * 6) * 3
			if now > jackpotUntil then
				jackpot.Visible = false
			end
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

	local function randomLosingIds(): { string }
		-- Trois symboles différents (si possible) pour ne pas mentir au joueur
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

	local function showResult(result)
		local bet = tonumber(result.Bet) or 0
		local payout = tonumber(result.Payout) or 0
		local multiplier = tonumber(result.Multiplier) or 0
		local center = UDim2.fromOffset(WINDOW_X + WINDOW_W / 2, WINDOW_Y + WINDOW_H / 2)
		local centerPoint = Vector2.new(WINDOW_X + WINDOW_W / 2, WINDOW_Y + WINDOW_H / 2)

		if payout > bet then
			highlightWinners(result.Reels)
			partyUntil = os.clock() + (multiplier >= 25 and 3.5 or 1.8)
			winGlowUntil = os.clock() + 2
			ctx.Sound.Play("SlotWin", multiplier >= 25 and 1.1 or 1)
			local text = "+" .. Format.Format(payout)
			floatOnOverlay(centerPoint, text, GOLD, multiplier >= 10 and 34 or 26)
			local winTexts = Locale.Pick(WIN_TEXTS)
			setInfo(winTexts[random:NextInteger(1, #winTexts)] .. " " .. Format.Multiplier(multiplier), GOLD_LIGHT, 3)
			UIUtil.Tween(windowStroke, 0.1, { Color = WHITE, Thickness = 3, Transparency = 0 })
			task.delay(0.6, function()
				if windowStroke.Parent then
					UIUtil.Tween(windowStroke, 0.4, { Color = GOLD, Thickness = 1.5, Transparency = 0.3 })
				end
			end)
			dropCoins(multiplier >= 25 and MAX_COINS or (multiplier >= 6 and 8 or 4))
			if effectsOn() then
				ctx.Effects.Burst(card, center, GOLD, multiplier >= 10 and 18 or 10)
			end
			if multiplier >= 25 then
				showJackpot(text .. " " .. Format.Multiplier(multiplier))
				ctx.Sound.Play("Jackpot", 1)
				ctx.Effects.Flash(GOLD, 0.45)
				ctx.Effects.BigMessage(Locale.T("🎰 JACKPOT! %s", text), GOLD, 2.5)
				if effectsOn() then
					ctx.Effects.Confetti(70)
				end
			elseif multiplier >= 6 and effectsOn() then
				ctx.Effects.Confetti(25)
			end
		elseif payout > 0 then
			highlightWinners(result.Reels)
			winGlowUntil = os.clock() + 1
			ctx.Sound.Play("Cash", 0.8)
			floatOnOverlay(centerPoint, "+" .. Format.Format(payout), WHITE, 22)
			setInfo(Locale.T("Partly refunded (%s) 🙃", Format.Multiplier(multiplier)), Color3.fromRGB(255, 225, 160), 2.5)
		else
			ctx.Sound.Play("Error", 0.75)
			UIUtil.Shake(window)
			local lossTexts = Locale.Pick(LOSS_TEXTS)
			setInfo(lossTexts[random:NextInteger(1, #lossTexts)], Color3.fromRGB(255, 150, 150), 2.5)
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
		local minBet = config.MinBet or 1
		if getDopamine() < minBet then
			ctx.Sound.Play("Error", 1)
			UIUtil.Shake(playButton)
			setInfo(Locale.T("You need at least %s Dopamine 😬", Format.Format(minBet)), Color3.fromRGB(255, 150, 150), 2)
			return
		end

		spinning = true
		setPlayEnabled(false)
		setPaytable(false)
		jackpot.Visible = false
		pullLever()
		ctx.Sound.Play("SlotSpin", 1)
		for _, reel in ipairs(reels) do
			reel.Mode = "spin"
			reel.Glow.BackgroundTransparency = 1
		end
		setInfo(Locale.T("Spinning… 🎲"), LED_TEXT)

		local fraction = fractions[selected] or fractions[1]
		task.spawn(function()
			local started = os.clock()
			local callOk, success, result = pcall(function()
				return ctx.Net.Function("CasinoSpin"):InvokeServer(fraction)
			end)
			if not waitAlive(math.max(0, MIN_SPIN_TIME - (os.clock() - started))) then
				return
			end

			local valid = callOk and success == true and type(result) == "table" and type(result.Reels) == "table"
			local ids = {}
			if valid then
				for index = 1, 3 do
					local id = result.Reels[index]
					if type(id) ~= "string" or not symbolsById[id] then
						id = symbols[1].Id
					end
					ids[index] = id
				end
			else
				ids = randomLosingIds()
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
				showResult(result)
			else
				local message = (callOk and type(result) == "string") and result or Locale.T("The machine is on strike 🔧")
				ctx.Sound.Play("Error", 1)
				UIUtil.Shake(window)
				setInfo(message, Color3.fromRGB(255, 150, 150), 2.5)
			end

			spinning = false
			setPlayEnabled(enabled)
			refreshBetLabel()
		end)
	end

	ctx.Connect(playButton.Activated, play)
	ctx.Connect(leverButton.Activated, play)

	------------------------------------------------------------------
	-- Écran LED au repos : mise actuelle / petites annonces
	------------------------------------------------------------------
	local bestSymbol = symbols[1]
	for _, symbol in ipairs(symbols) do
		if (symbol.Triple or 0) > (bestSymbol.Triple or 0) then
			bestSymbol = symbol
		end
	end
	local attract = table.clone(Locale.Pick(ATTRACT_TEXTS))
	if bestSymbol then
		table.insert(attract, Locale.T("Triple %s = %s!", bestSymbol.Icon, Format.Multiplier(bestSymbol.Triple or 0)))
	end

	task.spawn(function()
		local tick = 0
		while ctx.IsAlive() do
			if enabled and not spinning and os.clock() >= infoLockUntil then
				tick += 1
				if tick % 8 == 0 then
					setInfo(attract[random:NextInteger(1, #attract)], Color3.fromRGB(255, 220, 150), 2)
				else
					setInfo(Locale.T("Bet: %s Dopamine", Format.Format(currentBet())), LED_TEXT)
				end
			end
			task.wait(0.5)
		end
	end)
end

return Casino
