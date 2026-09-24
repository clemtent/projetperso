--[[
	Casino (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Casino

	Machine à sous (UNIQUEMENT avec la Dopamine du jeu) dans le slot R2 :
	  - 3 rouleaux qui défilent (colonnes de symboles de Config.Casino),
	    ombrés en haut / en bas, avec une ligne de gain rouge ;
	  - jetons de mise (Config.Casino.BetFractions affichés en %) ;
	  - bouton "JOUER" + levier cliquable qui s'abaisse ;
	  - ampoules du fronton qui clignotent (en folie quand on gagne).
	Le résultat vient TOUJOURS du serveur (CasinoSpin) : les rouleaux se
	lancent tout de suite puis s'arrêtent un par un sur les symboles reçus
	(avec un petit suspense si les deux premiers sont identiques).
]]

local Casino = {}
Casino.Slot = "R2"

local REEL_W = 64
local REEL_H = 72
local CELL_H = 40 -- hauteur d'un symbole sur le rouleau
local STRIP_LENGTH = 24 -- symboles par bande (recyclés en boucle)
local MAX_SPEED = 20 -- symboles / seconde
local MIN_SPIN_TIME = 0.8

local CHIP_COLORS = {
	Color3.fromRGB(245, 245, 245),
	Color3.fromRGB(230, 50, 60),
	Color3.fromRGB(40, 120, 230),
	Color3.fromRGB(35, 35, 40),
}

local LOSS_TEXTS = {
	"Presque ! (non)",
	"La maison gagne toujours 🏠",
	"Retente, ça va passer… peut-être",
	"Ta Dopamine est partie en vacances 🏖️",
	"Aïe. On dira que c'était un test.",
	"Le cerveau a dit non 🧠❌",
	"C'était pour du beurre… ah non.",
	"Les rouleaux ont le trac aujourd'hui",
}

local WIN_TEXTS = {
	"GAGNÉ ! 🎉",
	"Ça tourne bien ! 💸",
	"La chance te sourit 😎",
	"Dopamine en cascade ! 🤑",
}

local ATTRACT_TEXTS = {
	"Tente ta chance ! 🍀",
	"Paire = remboursé (ou presque)",
	"Aucun Robux ici, promis 🤞",
}

-- Recul "Back" plus doux que la version standard (petit rebond à l'arrêt)
local function easeOutSoftBack(t: number): number
	local c1 = 0.9
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
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

	local width = container.Size.X.Offset > 0 and container.Size.X.Offset or 288
	local height = container.Size.Y.Offset > 0 and container.Size.Y.Offset or 180

	local gold = Theme.Colors.Gold
	local white = Color3.new(1, 1, 1)

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function getDopamine(): number
		local data = ctx.State.Data
		return (data and tonumber(data.Dopamine)) or 0
	end

	------------------------------------------------------------------
	-- Carrosserie de la machine
	------------------------------------------------------------------
	local card = Create("Frame", {
		Name = "Machine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = container,
	})
	UIUtil.Corner(card, 18)
	UIUtil.Stroke(card, Theme.Colors.CardBorder, 2)
	UIUtil.Gradient(card, ColorSequence.new(Color3.fromRGB(205, 36, 64), Color3.fromRGB(112, 12, 36)), 90)

	-- Liseré doré intérieur
	local trim = Create("Frame", {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = card,
	})
	UIUtil.Corner(trim, 15)
	UIUtil.Stroke(trim, gold, 1.5, 0.35)

	------------------------------------------------------------------
	-- Fronton : titre + ampoules
	------------------------------------------------------------------
	local bulbs = {}
	local bulbXs = { 18, 32, 46, 60, width - 60, width - 46, width - 32, width - 18 }
	for index, x in ipairs(bulbXs) do
		local bulb = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, 17),
			Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = gold,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = card,
		})
		UIUtil.Corner(bulb, UDim.new(1, 0))
		UIUtil.Stroke(bulb, Color3.fromRGB(90, 20, 10), 1, 0.3)
		bulbs[index] = bulb
	end

	local titlePill = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(width / 2, 17),
		Size = UDim2.fromOffset(150, 20),
		BackgroundColor3 = Color3.fromRGB(45, 4, 16),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(titlePill, UDim.new(1, 0))
	UIUtil.Stroke(titlePill, gold, 1.5)
	UIUtil.Label({
		Text = "🎰 MACHINE À SOUS",
		Font = Theme.Fonts.Title,
		TextColor3 = gold,
		Size = UDim2.new(1, -10, 1, -4),
		Position = UDim2.fromOffset(5, 2),
		MaxTextSize = 14,
		ZIndex = 4,
		Parent = titlePill,
	})

	------------------------------------------------------------------
	-- Fenêtre des rouleaux
	------------------------------------------------------------------
	local windowX, windowY = 10, 31
	local windowW = REEL_W * 3 + 6 * 2 + 8
	local window = Create("Frame", {
		Name = "Window",
		Position = UDim2.fromOffset(windowX, windowY),
		Size = UDim2.fromOffset(windowW, REEL_H + 8),
		BackgroundColor3 = Color3.fromRGB(28, 8, 16),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Corner(window, 10)
	local windowStroke = UIUtil.Stroke(window, gold, 2)

	local reels = {}
	local function wrap(index: number): number
		return ((index - 1) % STRIP_LENGTH) + 1
	end

	for r = 1, 3 do
		local reelFrame = Create("Frame", {
			Name = "Reel" .. r,
			Position = UDim2.fromOffset(4 + (r - 1) * (REEL_W + 6), 4),
			Size = UDim2.fromOffset(REEL_W, REEL_H),
			BackgroundColor3 = white,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 3,
			Parent = window,
		})
		UIUtil.Corner(reelFrame, 6)
		UIUtil.Gradient(reelFrame, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(215, 205, 195)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 252, 244)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 205, 195)),
		}), 90)

		-- Halo de victoire derrière le symbole du milieu
		local glow = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(REEL_W / 2, REEL_H / 2),
			Size = UDim2.fromOffset(REEL_W - 6, CELL_H),
			BackgroundColor3 = gold,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = reelFrame,
		})
		UIUtil.Corner(glow, 8)

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
				Size = UDim2.fromOffset(REEL_W, CELL_H),
				Position = UDim2.fromOffset(REEL_W / 2, REEL_H / 2),
				Font = Theme.Fonts.Title,
				MaxTextSize = 32,
				ZIndex = 4,
				Parent = reelFrame,
			})
			labels[k] = { Label = label, Shown = "" }
		end

		-- Ombre haut / bas pour l'effet "cylindre"
		local shade = Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = reelFrame,
		})
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(0.3, 1),
				NumberSequenceKeypoint.new(0.7, 1),
				NumberSequenceKeypoint.new(1, 0.3),
			}),
			Parent = shade,
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

	-- Ligne de gain
	local payline = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.new(1, -4, 0, 2),
		BackgroundColor3 = Theme.Colors.Red,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = window,
	})

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
			label.TextTransparency = blur and 0.35 or 0
		end
	end

	for _, reel in ipairs(reels) do
		renderReel(reel)
	end

	------------------------------------------------------------------
	-- Levier
	------------------------------------------------------------------
	local leverX = windowX + windowW + (width - (windowX + windowW)) / 2 - 2
	local leverBottom = 104
	local knobTop = 42
	local track = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(leverX, 38),
		Size = UDim2.fromOffset(10, leverBottom - 38 + 4),
		BackgroundColor3 = Color3.fromRGB(40, 8, 18),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	local stick = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(leverX, leverBottom),
		Size = UDim2.fromOffset(5, leverBottom - knobTop),
		BackgroundColor3 = Color3.fromRGB(210, 210, 220),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Gradient(stick, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 140, 150)), 0)
	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(leverX, knobTop),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Theme.Colors.Red,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Corner(knob, UDim.new(1, 0))
	UIUtil.Stroke(knob, Color3.fromRGB(80, 0, 10), 1.5)
	UIUtil.Gradient(knob, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150)), 60)
	local shine = Create("Frame", {
		Position = UDim2.fromOffset(5, 4),
		Size = UDim2.fromOffset(7, 5),
		BackgroundColor3 = white,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = knob,
	})
	UIUtil.Corner(shine, UDim.new(1, 0))
	local leverCap = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(leverX, leverBottom + 2),
		Size = UDim2.fromOffset(24, 12),
		BackgroundColor3 = gold,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Corner(leverCap, 4)
	UIUtil.Stroke(leverCap, Color3.fromRGB(90, 50, 0), 1)
	local leverButton = Create("TextButton", {
		Name = "Lever",
		Position = UDim2.fromOffset(leverX - 20, 28),
		Size = UDim2.fromOffset(40, leverBottom - 28 + 12),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 8,
		Parent = card,
	})

	local function pullLever()
		UIUtil.Tween(knob, 0.14, { Position = UDim2.fromOffset(leverX, leverBottom - 10) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UIUtil.Tween(stick, 0.14, { Size = UDim2.fromOffset(5, 10) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.16, function()
			if knob.Parent and stick.Parent then
				UIUtil.Tween(knob, 0.7, { Position = UDim2.fromOffset(leverX, knobTop) }, Enum.EasingStyle.Elastic)
				UIUtil.Tween(stick, 0.7, { Size = UDim2.fromOffset(5, leverBottom - knobTop) }, Enum.EasingStyle.Elastic)
			end
		end)
	end

	------------------------------------------------------------------
	-- Ligne d'info (mise, résultat, blagues)
	------------------------------------------------------------------
	local info = UIUtil.Label({
		Name = "Info",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = white,
		Position = UDim2.fromOffset(10, 114),
		Size = UDim2.new(1, -20, 0, 18),
		MaxTextSize = 14,
		ZIndex = 3,
		Parent = card,
	})
	local infoStroke = UIUtil.Stroke(info, Color3.fromRGB(60, 0, 15), 1.5)
	infoStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local infoLockUntil = 0

	local function setInfo(text: string, color: Color3?, lockSeconds: number?)
		info.Text = text
		info.TextColor3 = color or white
		if lockSeconds then
			infoLockUntil = os.clock() + lockSeconds
		end
	end

	------------------------------------------------------------------
	-- Jetons de mise + bouton JOUER
	------------------------------------------------------------------
	local fractions = config.BetFractions or { 0.01 }
	local selected = math.min(1, #fractions)
	local chips = {}
	local rowY = height - 40
	local chipW = 40
	local chipGap = 5

	local function percentText(fraction: number): string
		local percent = fraction * 100
		local rounded = math.floor(percent + 0.5)
		if math.abs(percent - rounded) < 1e-6 then
			return tostring(rounded) .. "%"
		end
		return string.format("%.1f%%", percent)
	end

	local function currentBet(): number
		local fraction = fractions[selected] or 0.01
		return math.max(config.MinBet or 1, math.floor(getDopamine() * fraction))
	end

	local function refreshChips()
		for index, chip in ipairs(chips) do
			local isSelected = index == selected
			chip.Stroke.Color = isSelected and gold or Color3.fromRGB(30, 30, 30)
			chip.Stroke.Thickness = isSelected and 3 or 1.5
			UIUtil.Tween(chip.Scale, 0.2, { Scale = isSelected and 1.1 or 0.94 }, Enum.EasingStyle.Back)
		end
	end

	for index, fraction in ipairs(fractions) do
		if index > 4 then
			break -- pas la place pour plus de 4 jetons
		end
		local color = CHIP_COLORS[index] or CHIP_COLORS[1]
		local chip = Create("TextButton", {
			Name = "Chip" .. index,
			Position = UDim2.fromOffset(9 + (index - 1) * (chipW + chipGap), rowY),
			Size = UDim2.fromOffset(chipW, 30),
			BackgroundColor3 = color,
			AutoButtonColor = false,
			Font = Theme.Fonts.Number,
			Text = percentText(fraction),
			TextColor3 = Theme.ContrastText(color),
			TextSize = 14,
			ZIndex = 4,
			Parent = card,
		})
		UIUtil.Corner(chip, UDim.new(1, 0))
		local stroke = UIUtil.Stroke(chip, Color3.fromRGB(30, 30, 30), 1.5)
		-- Petit pointillé de jeton de poker (bordure intérieure en tirets)
		local ring = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 1, -8),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = chip,
		})
		UIUtil.Corner(ring, UDim.new(1, 0))
		UIUtil.Stroke(ring, Theme.ContrastText(color), 1, 0.6)
		local scale = Create("UIScale", { Scale = 0.94, Parent = chip })
		chips[index] = { Button = chip, Stroke = stroke, Scale = scale }

		ctx.Connect(chip.Activated, function()
			if selected == index then
				return
			end
			selected = index
			refreshChips()
			ctx.Sound.Play("Click", 1.3 + index * 0.08)
			setInfo("Mise : " .. Format.Format(currentBet()) .. " Dopamine", gold, 1.5)
		end)
	end
	refreshChips()

	local playButton = UIUtil.NeonButton({
		Name = "Play",
		Text = "JOUER",
		Color = gold,
		Size = UDim2.fromOffset(width - (9 + 4 * (chipW + chipGap)) - 9, 32),
		Position = UDim2.fromOffset(9 + 4 * (chipW + chipGap), rowY - 1),
		MaxTextSize = 18,
		ZIndex = 4,
		Parent = card,
	})

	-- Fermé (Config.Casino.Enabled = false)
	local enabled = config.Enabled ~= false
	if not enabled then
		UIUtil.SetButtonEnabled(playButton, false)
		local closed = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(windowX + windowW / 2, windowY + (REEL_H + 8) / 2),
			Size = UDim2.fromOffset(windowW + 10, 30),
			Rotation = -8,
			BackgroundColor3 = Theme.Colors.Yellow,
			BorderSizePixel = 0,
			ZIndex = 9,
			Parent = card,
		})
		UIUtil.Stroke(closed, Theme.Colors.Border, 2)
		UIUtil.Label({
			Text = "🚧 FERMÉ POUR TRAVAUX 🚧",
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.TextDark,
			Size = UDim2.new(1, -8, 1, -6),
			Position = UDim2.fromOffset(4, 3),
			MaxTextSize = 16,
			ZIndex = 10,
			Parent = closed,
		})
		setInfo("Revenez plus tard (ou jamais) 😴", white)
	end

	------------------------------------------------------------------
	-- Animation (rouleaux, ampoules)
	------------------------------------------------------------------
	local partyUntil = 0
	local bulbClock = 0
	local bulbStep = 0
	local elapsed = 0
	local partyColors = { Theme.Colors.Yellow, Theme.Colors.Cyan, Theme.Colors.Pink, Theme.Colors.Green, white }

	ctx.OnRender(function(dt: number)
		elapsed += dt
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

		-- Ampoules : chenillard calme, ou arc-en-ciel rapide en cas de gain
		local party = os.clock() < partyUntil
		bulbClock += dt
		local interval = party and 0.07 or 0.35
		if bulbClock >= interval then
			bulbClock = 0
			bulbStep += 1
			for index, bulb in ipairs(bulbs) do
				if party then
					bulb.BackgroundColor3 = partyColors[((index + bulbStep) % #partyColors) + 1]
					bulb.BackgroundTransparency = 0
				else
					local on = (index + bulbStep) % 2 == 0
					bulb.BackgroundColor3 = gold
					bulb.BackgroundTransparency = on and 0 or 0.65
				end
			end
		end

		-- Lueur de la ligne de gain
		payline.BackgroundTransparency = 0.35 + math.sin(elapsed * 3) * 0.15
	end)

	------------------------------------------------------------------
	-- Partie
	------------------------------------------------------------------
	local spinning = false

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
						UIUtil.Tween(glow, 0.18, { BackgroundTransparency = 0.25 })
						task.wait(0.2)
						if not glow.Parent then
							return
						end
						UIUtil.Tween(glow, 0.18, { BackgroundTransparency = 0.8 })
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
		local center = UDim2.fromOffset(windowX + windowW / 2, windowY + REEL_H / 2)

		if payout > bet then
			highlightWinners(result.Reels)
			partyUntil = os.clock() + (multiplier >= 25 and 3.5 or 1.8)
			ctx.Sound.Play("SlotWin", multiplier >= 25 and 1.1 or 1)
			local text = "+" .. Format.Format(payout)
			ctx.FloatText(card, center, text, gold, multiplier >= 10 and 34 or 26)
			setInfo(WIN_TEXTS[random:NextInteger(1, #WIN_TEXTS)] .. " " .. Format.Multiplier(multiplier), gold, 3)
			UIUtil.Tween(windowStroke, 0.1, { Color = white, Thickness = 4 })
			task.delay(0.6, function()
				if windowStroke.Parent then
					UIUtil.Tween(windowStroke, 0.4, { Color = gold, Thickness = 2 })
				end
			end)
			if effectsOn() then
				ctx.Effects.Burst(card, center, gold, multiplier >= 10 and 18 or 10)
			end
			if multiplier >= 25 then
				ctx.Sound.Play("Jackpot", 1)
				ctx.Effects.Flash(gold, 0.45)
				ctx.Effects.BigMessage("🎰 JACKPOT ! " .. text, gold, 2.5)
				if effectsOn() then
					ctx.Effects.Confetti(70)
				end
			elseif multiplier >= 6 and effectsOn() then
				ctx.Effects.Confetti(25)
			end
		elseif payout > 0 then
			highlightWinners(result.Reels)
			ctx.Sound.Play("Cash", 0.8)
			ctx.FloatText(card, center, "+" .. Format.Format(payout), white, 22)
			setInfo("Remboursé en partie (" .. Format.Multiplier(multiplier) .. ") 🙃", Color3.fromRGB(255, 225, 160), 2.5)
		else
			ctx.Sound.Play("Error", 0.75)
			UIUtil.Shake(window)
			setInfo(LOSS_TEXTS[random:NextInteger(1, #LOSS_TEXTS)], Color3.fromRGB(255, 205, 205), 2.5)
		end
	end

	local function play()
		if spinning or not ctx.IsAlive() then
			return
		end
		if not enabled then
			ctx.Sound.Play("Error", 1)
			UIUtil.Shake(playButton)
			return
		end
		local minBet = config.MinBet or 1
		if getDopamine() < minBet then
			ctx.Sound.Play("Error", 1)
			UIUtil.Shake(playButton)
			setInfo("Il faut au moins " .. Format.Format(minBet) .. " Dopamine 😬", Color3.fromRGB(255, 205, 205), 2)
			return
		end

		spinning = true
		UIUtil.SetButtonEnabled(playButton, false)
		pullLever()
		ctx.Sound.Play("SlotSpin", 1)
		for _, reel in ipairs(reels) do
			reel.Mode = "spin"
			reel.Glow.BackgroundTransparency = 1
		end
		setInfo("Ça tourne… 🎲", white)

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
					setInfo("🤞 Allez… allez…", Theme.Colors.Yellow)
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
				local message = (callOk and type(result) == "string") and result or "La machine fait grève 🔧"
				ctx.Sound.Play("Error", 1)
				UIUtil.Shake(window)
				setInfo(message, Color3.fromRGB(255, 205, 205), 2.5)
			end

			spinning = false
			UIUtil.SetButtonEnabled(playButton, true)
		end)
	end

	ctx.Connect(playButton.Activated, play)
	ctx.Connect(leverButton.Activated, play)

	------------------------------------------------------------------
	-- Ligne d'info au repos : mise actuelle / petites annonces
	------------------------------------------------------------------
	local bestSymbol = symbols[1]
	for _, symbol in ipairs(symbols) do
		if (symbol.Triple or 0) > (bestSymbol.Triple or 0) then
			bestSymbol = symbol
		end
	end
	local attract = table.clone(ATTRACT_TEXTS)
	if bestSymbol then
		table.insert(attract, "Triple " .. bestSymbol.Icon .. " = " .. Format.Multiplier(bestSymbol.Triple or 0) .. " !")
	end

	task.spawn(function()
		local tick = 0
		while ctx.IsAlive() do
			if enabled and not spinning and os.clock() >= infoLockUntil then
				tick += 1
				if tick % 8 == 0 then
					setInfo(attract[random:NextInteger(1, #attract)], Color3.fromRGB(255, 230, 170), 2)
				else
					setInfo("Mise : " .. Format.Format(currentBet()) .. " Dopamine", white)
				end
			end
			task.wait(0.5)
		end
	end)
end

return Casino
