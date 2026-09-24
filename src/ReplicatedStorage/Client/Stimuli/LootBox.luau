--[[
	LootBox (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > LootBox

	Coffre mystère (slot CR) dessiné en code : corps en bois, couvercle,
	bandes dorées, serrure. Il se recharge avec le temps de jeu
	(State.Data.Chests : Stored / Progress / Max) :
	  - jauge "Prochain coffre" en bas (prédite en douceur côté client) ;
	  - pastille rouge = nombre de coffres en stock ;
	  - quand un coffre est prêt, il sautille et brille pour qu'on le touche.
	Clic -> OpenChest (serveur) : le coffre tremble, le couvercle saute,
	des rayons de la couleur du rang tournent, puis le rang (Commun, Rare,
	Épique, LÉGENDAIRE) et le gain s'affichent. Légendaire = gros message
	+ confettis.
	Bouton "?" : affiche les chances (%) de chaque rang, calculées depuis
	les poids (Weight) de Config.LootBox.Tiers.
]]

local Debris = game:GetService("Debris")

local LootBox = {}
LootBox.Slot = "CR"

local CHEST_Y = 84 -- centre vertical du coffre dans la carte
local RAY_COUNT = 6 -- barres (chacune donne 2 rayons opposés)
local MAX_SPARKLES = 4

local EMPTY_HINTS = {
	"Ça charge… ⏳",
	"Patience, petit scarabée",
	"Le coffre fait la sieste 😴",
}

local READY_HINTS = {
	"Touche pour ouvrir !",
	"Ouvre-moi ! 👀",
	"Qu'y a-t-il dedans ?",
}

function LootBox.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local Format = ctx.Format
	local config = ctx.Config.LootBox
	local container: Frame = ctx.Container
	local random = Random.new()

	local width = container.Size.X.Offset > 0 and container.Size.X.Offset or 170
	local height = container.Size.Y.Offset > 0 and container.Size.Y.Offset or 170
	local centerX = width / 2

	local gold = Theme.Colors.Gold
	local white = Color3.new(1, 1, 1)
	local wood = Color3.fromRGB(176, 104, 48)
	local woodDark = Color3.fromRGB(110, 60, 24)
	local woodLine = Color3.fromRGB(70, 36, 12)

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function readChests(): (number, number, number)
		local data = ctx.State.Data
		local chests = data and data.Chests
		if type(chests) ~= "table" then
			return 0, 0, config.MaxStored or 5
		end
		return tonumber(chests.Stored) or 0, tonumber(chests.Progress) or 0, tonumber(chests.Max) or config.MaxStored or 5
	end

	------------------------------------------------------------------
	-- Carte (toute la carte est cliquable)
	------------------------------------------------------------------
	local card = Create("TextButton", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = white,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = container,
	})
	UIUtil.Corner(card, 18)
	UIUtil.Stroke(card, Theme.Colors.CardBorder, 2)
	UIUtil.Gradient(card, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(234, 224, 255)), 90)
	local cardScale = Create("UIScale", { Parent = card })

	-- Texte flottant dessiné dans le calque Overlay : il monte de 100 px et
	-- serait coupé par le slot (ClipsDescendants). `point` = position en
	-- pixels "design" dans `guiObject` (qui fait `designW` de large).
	local function floatOnOverlay(guiObject: GuiObject, designW: number, point: Vector2, text: string, color: Color3?, size: number?)
		local ratio = guiObject.AbsoluteSize.X / math.max(1, designW)
		local canvas = ctx.Interface.ScreenToCanvas(guiObject.AbsolutePosition + point * ratio)
		ctx.FloatText(ctx.Overlay, UDim2.fromOffset(canvas.X, canvas.Y), text, color, size)
	end

	local title = UIUtil.Label({
		Text = "Coffre mystère",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		Position = UDim2.fromOffset(34, 6),
		Size = UDim2.new(1, -68, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		ZIndex = 2,
		Parent = card,
	})

	-- Pastille : coffres en stock
	local badge = UIUtil.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -20, 0, 18),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Red,
		Font = Theme.Fonts.Number,
		TextColor3 = white,
		Text = "0",
		MaxTextSize = 16,
		Visible = false,
		ZIndex = 12,
		Parent = card,
	})
	UIUtil.Corner(badge, UDim.new(1, 0))
	UIUtil.Stroke(badge, white, 2)
	local badgeScale = Create("UIScale", { Parent = badge })

	------------------------------------------------------------------
	-- Lueur + rayons (derrière le coffre)
	------------------------------------------------------------------
	local glow = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centerX, CHEST_Y),
		Size = UDim2.fromOffset(112, 112),
		BackgroundColor3 = gold,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Corner(glow, UDim.new(1, 0))

	local rays = {}
	for index = 1, RAY_COUNT do
		local ray = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(centerX, CHEST_Y - 6),
			Size = UDim2.fromOffset(230, 16),
			BackgroundColor3 = gold,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = card,
		})
		Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.35, 0.35),
				NumberSequenceKeypoint.new(0.5, 0.1),
				NumberSequenceKeypoint.new(0.65, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
		rays[index] = { Frame = ray, Base = (index - 1) * (180 / RAY_COUNT) }
	end

	------------------------------------------------------------------
	-- Le coffre (groupe 96x76)
	------------------------------------------------------------------
	local chest = Create("Frame", {
		Name = "Chest",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centerX, CHEST_Y),
		Size = UDim2.fromOffset(96, 76),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = card,
	})
	local chestScale = Create("UIScale", { Parent = chest })

	local shadow = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(48, 73),
		Size = UDim2.fromOffset(82, 10),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = chest,
	})
	UIUtil.Corner(shadow, UDim.new(1, 0))

	-- Lumière qui sort du coffre ouvert
	local innerLight = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(48, 32),
		Size = UDim2.fromOffset(74, 12),
		BackgroundColor3 = gold,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = chest,
	})
	UIUtil.Corner(innerLight, UDim.new(1, 0))

	local body = Create("Frame", {
		Position = UDim2.fromOffset(8, 30),
		Size = UDim2.fromOffset(80, 42),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = chest,
	})
	UIUtil.Corner(body, 8)
	UIUtil.Stroke(body, woodLine, 2)
	UIUtil.Gradient(body, ColorSequence.new(wood, woodDark), 90)
	-- Planches
	for _, y in ipairs({ 14, 28 }) do
		Create("Frame", {
			Position = UDim2.fromOffset(2, y),
			Size = UDim2.new(1, -4, 0, 1),
			BackgroundColor3 = woodLine,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = body,
		})
	end
	for _, x in ipairs({ 10, 63 }) do
		local band = Create("Frame", {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, 7, 1, 0),
			BackgroundColor3 = gold,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = body,
		})
		UIUtil.Gradient(band, ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(200, 140, 0)), 0)
	end

	local lidRest = UDim2.fromOffset(48, 34)
	local lid = Create("Frame", {
		Name = "Lid",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = lidRest,
		Size = UDim2.fromOffset(86, 28),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = chest,
	})
	UIUtil.Corner(lid, 12)
	UIUtil.Stroke(lid, woodLine, 2)
	UIUtil.Gradient(lid, ColorSequence.new(Color3.fromRGB(206, 132, 70), wood), 90)
	for _, x in ipairs({ 13, 66 }) do
		local band = Create("Frame", {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, 7, 1, 0),
			BackgroundColor3 = gold,
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = lid,
		})
		UIUtil.Gradient(band, ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(200, 140, 0)), 0)
	end
	-- Serrure (accrochée au couvercle : elle part avec lui)
	local lock = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(16, 18),
		BackgroundColor3 = gold,
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = lid,
	})
	UIUtil.Corner(lock, 4)
	UIUtil.Stroke(lock, Color3.fromRGB(110, 70, 0), 1.5)
	local keyhole = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = woodLine,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = lock,
	})
	UIUtil.Corner(keyhole, UDim.new(1, 0))

	------------------------------------------------------------------
	-- Textes : indice, rang, gain
	------------------------------------------------------------------
	local hint = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.TextDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(centerX, 124),
		Size = UDim2.new(1, -16, 0, 16),
		MaxTextSize = 13,
		ZIndex = 4,
		Parent = card,
	})

	local tierLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = gold,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centerX, 20),
		Size = UDim2.new(1, -12, 0, 26),
		MaxTextSize = 22,
		TextTransparency = 1,
		ZIndex = 13,
		Parent = card,
	})
	local tierStroke = UIUtil.Stroke(tierLabel, Theme.Colors.TextDark, 2, 1)
	tierStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local tierScale = Create("UIScale", { Parent = tierLabel })

	local amountLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDark,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(centerX, 131),
		Size = UDim2.new(1, -12, 0, 22),
		MaxTextSize = 20,
		TextTransparency = 1,
		ZIndex = 13,
		Parent = card,
	})
	local amountStroke = UIUtil.Stroke(amountLabel, white, 2, 1)
	amountStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	------------------------------------------------------------------
	-- Jauge de recharge
	------------------------------------------------------------------
	local bar = Create("Frame", {
		Name = "Charge",
		Position = UDim2.fromOffset(12, height - 26),
		Size = UDim2.new(1, -24, 0, 16),
		BackgroundColor3 = Color3.fromRGB(230, 230, 236),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Corner(bar, UDim.new(1, 0))
	UIUtil.Stroke(bar, Theme.Colors.Border, 1.5)
	local fill = Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = bar,
	})
	UIUtil.Corner(fill, UDim.new(1, 0))
	UIUtil.Gradient(fill, ColorSequence.new(Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 130, 30)), 0)
	local barText = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		Size = UDim2.new(1, -8, 1, -2),
		Position = UDim2.fromOffset(4, 1),
		MaxTextSize = 11,
		ZIndex = 6,
		Parent = bar,
	})

	------------------------------------------------------------------
	-- Chances de chaque rang (bouton "?")
	------------------------------------------------------------------
	local totalWeight = 0
	for _, tier in ipairs(config.Tiers) do
		totalWeight += math.max(0, tonumber(tier.Weight) or 0)
	end

	local function percentText(weight: number): string
		if totalWeight <= 0 then
			return "?"
		end
		local percent = weight / totalWeight * 100
		if percent >= 10 or math.abs(percent - math.floor(percent + 0.5)) < 0.05 then
			return tostring(math.floor(percent + 0.5)) .. " %"
		end
		return string.format("%.1f %%", percent)
	end

	local oddsButton = Create("TextButton", {
		Name = "Odds",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(18, 16),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Color3.fromRGB(240, 236, 255),
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "?",
		TextColor3 = Theme.Colors.Purple,
		TextSize = 15,
		ZIndex = 14,
		Parent = card,
	})
	UIUtil.Corner(oddsButton, UDim.new(1, 0))
	UIUtil.Stroke(oddsButton, Theme.Colors.Purple, 1.5, 0.2)

	-- Carte des chances (par-dessus le coffre ; un appui la ferme)
	local oddsPanel = Create("TextButton", {
		Name = "OddsPanel",
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = white,
		BackgroundTransparency = 0.02,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 30,
		Visible = false,
		Parent = card,
	})
	UIUtil.Corner(oddsPanel, 14)
	UIUtil.Stroke(oddsPanel, Theme.Colors.Purple, 1.5, 0.3)
	local oddsScale = Create("UIScale", { Parent = oddsPanel })
	UIUtil.Label({
		Text = "🎲 Chances",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 20),
		MaxTextSize = 16,
		ZIndex = 31,
		Parent = oddsPanel,
	})
	local rowCount = math.max(1, #config.Tiers)
	local rowHeight = math.min(24, math.floor((height - 12 - 34 - 18) / rowCount))
	for index, tier in ipairs(config.Tiers) do
		local y = 30 + (index - 1) * rowHeight
		local tierColor: Color3 = tier.Color or gold
		local dot = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(12, y + rowHeight / 2),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = tierColor,
			BorderSizePixel = 0,
			ZIndex = 31,
			Parent = oddsPanel,
		})
		UIUtil.Corner(dot, UDim.new(1, 0))
		UIUtil.Label({
			Text = tostring(tier.Name or tier.Id),
			Font = Theme.Fonts.Title,
			TextColor3 = tierColor:Lerp(Theme.Colors.TextDark, 0.35),
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(28, y + 2),
			Size = UDim2.new(1, -90, 0, rowHeight - 4),
			MaxTextSize = 14,
			ZIndex = 31,
			Parent = oddsPanel,
		})
		UIUtil.Label({
			Text = percentText(math.max(0, tonumber(tier.Weight) or 0)),
			Font = Theme.Fonts.Number,
			TextColor3 = Theme.Colors.TextDark,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, y + 2),
			Size = UDim2.fromOffset(60, rowHeight - 4),
			MaxTextSize = 14,
			ZIndex = 31,
			Parent = oddsPanel,
		})
	end
	UIUtil.Label({
		Text = "Touche pour fermer",
		TextColor3 = Theme.Colors.TextDim,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -16, 0, 14),
		MaxTextSize = 11,
		ZIndex = 31,
		Parent = oddsPanel,
	})

	local oddsToken = 0
	local function setOdds(show: boolean)
		oddsToken += 1
		oddsPanel.Visible = show
		if show then
			oddsScale.Scale = 0.85
			UIUtil.Tween(oddsScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			ctx.Sound.Play("Click", 1.4)
			-- Fermeture automatique
			local token = oddsToken
			task.delay(6, function()
				if token == oddsToken and oddsPanel.Parent then
					oddsPanel.Visible = false
				end
			end)
		end
	end
	ctx.Connect(oddsButton.Activated, function()
		setOdds(not oddsPanel.Visible)
	end)
	ctx.Connect(oddsPanel.Activated, function()
		setOdds(false)
	end)

	------------------------------------------------------------------
	-- Suivi du stock et de la charge
	------------------------------------------------------------------
	local stored, serverProgress, maxStored = readChests()
	local progressTime = os.clock()
	local shownFill = 0
	local opening = false
	local hintIndex = random:NextInteger(1, 3)

	local function refreshBadge()
		badge.Visible = stored > 0
		badge.Text = tostring(math.floor(stored))
	end

	local function refreshHint()
		if opening then
			return
		end
		hint.TextColor3 = Theme.Colors.TextDim
		if stored >= 1 then
			hint.Text = READY_HINTS[((hintIndex - 1) % #READY_HINTS) + 1]
			hint.TextColor3 = Theme.Colors.Purple
		else
			hint.Text = EMPTY_HINTS[((hintIndex - 1) % #EMPTY_HINTS) + 1]
		end
	end

	refreshBadge()
	refreshHint()

	ctx.Connect(ctx.State.Changed, function()
		local newStored, newProgress, newMax = readChests()
		if newProgress ~= serverProgress then
			serverProgress = newProgress
			progressTime = os.clock()
		end
		maxStored = newMax
		if newStored ~= stored then
			local gained = newStored > stored
			stored = newStored
			refreshBadge()
			refreshHint()
			if gained and not opening then
				-- Nouveau coffre prêt : petit "pop" du badge
				ctx.Sound.Play("Bonus", 1.4)
				badgeScale.Scale = 1.6
				UIUtil.Tween(badgeScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
				floatOnOverlay(card, width, Vector2.new(centerX, CHEST_Y - 30), "+1 📦", Theme.Colors.Purple, 22)
			end
		end
	end)

	------------------------------------------------------------------
	-- Animation continue
	------------------------------------------------------------------
	local elapsed = 0
	local shakeAmount = 0 -- tremblement pendant l'ouverture
	local raysAlpha = 1 -- 1 = rayons invisibles
	local sparkles = 0
	local sparkleClock = 0
	local barLastText = ""

	local function spawnSparkle()
		if sparkles >= MAX_SPARKLES or not effectsOn() then
			return
		end
		sparkles += 1
		local star = UIUtil.Label({
			Text = random:NextNumber() < 0.5 and "✨" or "⭐",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(centerX + random:NextNumber(-52, 52), CHEST_Y + random:NextNumber(-40, 20)),
			Size = UDim2.fromOffset(18, 18),
			MaxTextSize = 16,
			ZIndex = 11,
			Parent = card,
		})
		local scale = Create("UIScale", { Scale = 0.2, Parent = star })
		UIUtil.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		UIUtil.Tween(star, 0.8, {
			TextTransparency = 1,
			Position = star.Position + UDim2.fromOffset(0, -14),
			Rotation = random:NextNumber(-40, 40),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(star, 0.85)
		task.delay(0.85, function()
			sparkles -= 1
		end)
	end

	ctx.OnRender(function(dt: number)
		elapsed += dt

		-- Charge (prédite entre deux états du serveur)
		local target
		if stored >= maxStored then
			target = 1
		else
			target = math.clamp(serverProgress + (os.clock() - progressTime) / (config.ChargeInterval or 90), 0, 1)
		end
		shownFill += (target - shownFill) * math.min(1, dt * 6)
		if target < shownFill - 0.5 then
			shownFill = target -- nouveau cycle : on repart de zéro
		end
		fill.Size = UDim2.fromScale(shownFill, 1)
		local text = stored >= maxStored and "Plein ! Ouvre-moi 😤" or ("Prochain : " .. math.floor(target * 100) .. " %")
		if text ~= barLastText then
			barLastText = text
			barText.Text = text
		end

		-- Coffre : tremblement (ouverture) ou petit saut d'impatience
		local offsetX, offsetY, rotation = 0, 0, 0
		if shakeAmount > 0 then
			offsetX = math.sin(elapsed * 55) * shakeAmount * 0.6
			rotation = math.sin(elapsed * 47) * shakeAmount
		elseif stored >= 1 and not opening then
			local phase = elapsed % 2.2
			if phase < 0.45 then
				local hop = math.sin(phase / 0.45 * math.pi)
				offsetY = -hop * 9
				rotation = math.sin(phase / 0.45 * math.pi * 2) * 5
			end
			glow.BackgroundTransparency = 0.78 + math.sin(elapsed * 3) * 0.08
			sparkleClock += dt
			if sparkleClock > 0.55 then
				sparkleClock = 0
				spawnSparkle()
			end
		elseif not opening then
			glow.BackgroundTransparency = math.min(1, glow.BackgroundTransparency + dt)
		end
		chest.Position = UDim2.fromOffset(centerX + offsetX, CHEST_Y + offsetY)
		chest.Rotation = rotation

		-- Rayons tournants
		if raysAlpha < 1 then
			for _, ray in ipairs(rays) do
				ray.Frame.Rotation = ray.Base + elapsed * 40
				ray.Frame.BackgroundTransparency = raysAlpha
			end
		end
	end)

	-- Survol (PC)
	ctx.Connect(card.MouseEnter, function()
		UIUtil.Tween(cardScale, 0.15, { Scale = 1.03 }, Enum.EasingStyle.Back)
	end)
	ctx.Connect(card.MouseLeave, function()
		UIUtil.Tween(cardScale, 0.15, { Scale = 1 })
	end)

	------------------------------------------------------------------
	-- Ouverture
	------------------------------------------------------------------
	local function findTier(id: any)
		for index, tier in ipairs(config.Tiers) do
			if tier.Id == id then
				return tier, index
			end
		end
		return config.Tiers[1], 1
	end

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

	local function closeChest()
		UIUtil.Tween(lid, 0.35, { Position = lidRest, Rotation = 0 }, Enum.EasingStyle.Back)
		UIUtil.Tween(innerLight, 0.3, { BackgroundTransparency = 1 })
		glow.BackgroundColor3 = gold
		UIUtil.Tween(tierLabel, 0.3, { TextTransparency = 1 })
		UIUtil.Tween(tierStroke, 0.3, { Transparency = 1 })
		UIUtil.Tween(amountLabel, 0.3, { TextTransparency = 1 })
		UIUtil.Tween(amountStroke, 0.3, { Transparency = 1 })
		UIUtil.Tween(title, 0.3, { TextTransparency = 0 })
		UIUtil.Tween(hint, 0.3, { TextTransparency = 0 })
		oddsButton.Visible = true
		task.spawn(function()
			local startAlpha = raysAlpha
			for i = 1, 10 do
				raysAlpha = startAlpha + (1 - startAlpha) * (i / 10)
				task.wait(0.03)
			end
			raysAlpha = 1
			for _, ray in ipairs(rays) do
				if ray.Frame.Parent then
					ray.Frame.BackgroundTransparency = 1
				end
			end
		end)
	end

	local function reveal(result)
		local tier, tierIndex = findTier(result.Tier)
		local color: Color3 = tier.Color or gold
		local amount = tonumber(result.Amount) or 0
		local amountText = "+" .. Format.Format(amount)

		shakeAmount = 0
		ctx.Sound.Play("Chest", 1)
		-- Le couvercle saute
		UIUtil.Tween(lid, 0.35, { Position = lidRest + UDim2.fromOffset(-10, -26), Rotation = -32 }, Enum.EasingStyle.Back)
		chestScale.Scale = 1.25
		UIUtil.Tween(chestScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)
		innerLight.BackgroundColor3 = color
		innerLight.BackgroundTransparency = 0.1
		glow.BackgroundColor3 = color
		glow.BackgroundTransparency = 0.6
		for _, ray in ipairs(rays) do
			ray.Frame.BackgroundColor3 = color
		end
		raysAlpha = 0.35

		-- Rang + gain
		title.TextTransparency = 1
		hint.TextTransparency = 1
		oddsButton.Visible = false
		oddsPanel.Visible = false
		tierLabel.Text = tostring(tier.Name or tier.Id)
		tierLabel.TextColor3 = color
		tierLabel.TextTransparency = 0
		tierStroke.Transparency = 0
		tierScale.Scale = 0.2
		UIUtil.Tween(tierScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		amountLabel.Text = amountText
		amountLabel.TextTransparency = 0
		amountStroke.Transparency = 0

		if effectsOn() then
			ctx.Effects.Burst(card, UDim2.fromOffset(centerX, CHEST_Y - 10), color, 6 + tierIndex * 4)
		end
		floatOnOverlay(card, width, Vector2.new(centerX, CHEST_Y - 20), amountText, color, 26)

		if tier.Id == "Legendary" or tierIndex >= #config.Tiers then
			ctx.Sound.Play("Jackpot", 1)
			ctx.Effects.Flash(color, 0.5)
			ctx.Effects.BigMessage("📦 " .. tostring(tier.Name) .. " ! " .. amountText, color, 2.5)
			if effectsOn() then
				ctx.Effects.Confetti(80)
			end
		elseif tierIndex >= 3 then
			ctx.Sound.Play("SlotWin", 1.1)
			if effectsOn() then
				ctx.Effects.Confetti(30)
			end
		elseif tierIndex == 2 then
			ctx.Sound.Play("Bonus", 1.2)
		end
	end

	-- Petit "non" : le coffre gigote (UIUtil.Shake serait écrasé par l'animation)
	local function wobble()
		shakeAmount = 7
		task.delay(0.3, function()
			if not opening then
				shakeAmount = 0
			end
		end)
	end

	local function open()
		if opening or not ctx.IsAlive() then
			return
		end
		if stored < 1 then
			ctx.Sound.Play("Error", 1)
			wobble()
			hint.Text = "Pas encore de coffre ! ⏳"
			hint.TextColor3 = Theme.Colors.Red
			return
		end

		opening = true
		hint.Text = "Ouverture… 🤞"
		hint.TextColor3 = Theme.Colors.TextDark
		ctx.Sound.Play("Open", 1)

		task.spawn(function()
			local started = os.clock()
			-- Tremblement de plus en plus fort pendant l'appel serveur
			local shaking = true
			task.spawn(function()
				while shaking and ctx.IsAlive() do
					shakeAmount = math.min(10, 2 + (os.clock() - started) * 12)
					task.wait()
				end
			end)

			local callOk, success, result = pcall(function()
				return ctx.Net.Function("OpenChest"):InvokeServer()
			end)
			local ok = waitAlive(math.max(0, 0.7 - (os.clock() - started)))
			shaking = false
			shakeAmount = 0
			if not ok then
				return
			end

			if callOk and success == true and type(result) == "table" then
				reveal(result)
				if not waitAlive(2) then
					return
				end
				closeChest()
				if not waitAlive(0.35) then
					return
				end
			else
				local message = (callOk and type(result) == "string") and result or "Le coffre est coincé 🔒"
				ctx.Sound.Play("Error", 1)
				wobble()
				ctx.Notify(message, Theme.Colors.Red)
			end

			opening = false
			hintIndex += 1
			refreshHint()
		end)
	end

	ctx.Connect(card.Activated, open)

	-- Change le petit texte de temps en temps
	task.spawn(function()
		while ctx.IsAlive() do
			task.wait(6)
			if not ctx.IsAlive() then
				break
			end
			hintIndex += 1
			refreshHint()
		end
	end)
end

return LootBox
