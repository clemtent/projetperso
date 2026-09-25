--[[
	Daily (ModuleScript) — calendrier du cadeau quotidien
	Emplacement : ReplicatedStorage > Client > Components > Panels > Daily

	Calendrier "premium" sur 7 jours, façon jeu mobile :
	  - en-tête animé : rayons qui tournent, étincelles, gros paquet cadeau
	    qui se trémousse quand il est disponible, pastilles (série, gain du
	    jour) et anneau de compte à rebours (segments) jusqu'au prochain cadeau ;
	  - 7 cartes-jours : paquets cadeaux dessinés (papier et ruban de couleur
	    différente chaque jour), le jour 7 est un gros coffre à diamant
	    lumineux. États :
	      récupéré     -> tampon ✔, carte grisée ;
	      aujourd'hui  -> bordure dorée scintillante, halo, rebond, ruban
	                      "AUJOURD'HUI" ;
	      demain       -> ruban "DEMAIN", sablier ;
	      à venir      -> cadenas, gris doux ;
	  - montant par jour : valeur exacte du serveur pour aujourd'hui,
	    estimation (même formule que DailyRewardService) pour les autres
	    jours, ou un multiplicateur "x" si la production est inconnue ;
	  - jauge de série 🔥 avec progression vers le coffre du jour 7 ;
	  - gros bouton "RÉCUPÉRER" (reflet qui balaie, pulsation, halo) ;
	  - séquence de récupération : le paquet tremble puis s'ouvre, flash,
	    confettis, gouttes de Dopamine qui jaillissent, montant qui défile,
	    tampon sur la carte du jour. Ensuite : état "déjà récupéré".
	Les animations ne tournent que fenêtre ouverte (RenderStepped branché
	dans OnOpen, débranché dans OnClose).
	Débloqué par l'amélioration "Calendrier" (Feature "Daily").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)

local PANEL_SIZE = Vector2.new(780, 590)

-- Title / Subtitle en anglais : traduits par PanelManager
local Daily = {
	Title = "🎁 Daily Gift",
	Subtitle = "Come back every day: your streak makes the gift bigger",
	Color = Theme.Colors.Pink,
	Size = PANEL_SIZE,
	FixedLayout = true, -- mise en page fixe : défile dans la fenêtre sur petit écran
}

----------------------------------------------------------------------
-- Réglages de mise en page (pixels "design" de la zone de contenu)
----------------------------------------------------------------------

local CONTENT_WIDTH = PANEL_SIZE.X - 40 -- largeur utile (voir PanelManager.Register)
local DAYS = math.max(1, Config.Daily.MaxStreakBonus)
local GAP = 8 -- espace entre les cartes
local BIG_RATIO = 1.45 -- largeur du dernier jour (en "cartes")
local UNIT = (CONTENT_WIDTH - (DAYS - 1) * GAP) / ((DAYS - 1) + BIG_RATIO)

local HERO_HEIGHT = 112
local CARDS_Y = 134
local CARD_HEIGHT = 158
local METER_Y = 304
local AMOUNT_Y = 346
local BUTTON_Y = 404
local BUTTON_SIZE = Vector2.new(360, 64)
local HINT_Y = 476

local GIFT_SIZE = math.floor(math.min(UNIT - 26, 64))
local CHEST_SIZE = math.floor(math.min(UNIT * BIG_RATIO - 40, 72))
local HERO_GIFT_POS = UDim2.new(0, 72, 0.5, 4)
local RING_SIZE = 96
local RING_RADIUS = 39
local RING_SEGMENTS = 36
local SECONDS_PER_DAY = 86400
local ICON = "💧"

----------------------------------------------------------------------
-- Couleurs
----------------------------------------------------------------------

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Theme.Colors.Gold
local GOLD_LIGHT = Color3.fromRGB(255, 232, 130)
local GREY = Color3.fromRGB(200, 202, 210)
local HERO_TOP = Color3.fromRGB(255, 72, 150)
local HERO_BOTTOM = Color3.fromRGB(255, 150, 60)
local PINK_DARK = Theme.Colors.Pink:Lerp(BLACK, 0.3)
local GREEN_DARK = Theme.Colors.Green:Lerp(BLACK, 0.4)
local CHEST_PURPLE = Color3.fromRGB(130, 60, 225)

-- Papier / ruban de chaque paquet (le dernier jour est le coffre)
local GIFT_COLORS = {
	{ Paper = Theme.Colors.Pink, Ribbon = Theme.Colors.Yellow },
	{ Paper = Theme.Colors.Blue, Ribbon = Color3.fromRGB(255, 95, 95) },
	{ Paper = Theme.Colors.Green, Ribbon = Theme.Colors.Purple },
	{ Paper = Theme.Colors.Orange, Ribbon = Theme.Colors.Cyan },
	{ Paper = Theme.Colors.Purple, Ribbon = Theme.Colors.Gold },
	{ Paper = Theme.Colors.Cyan, Ribbon = Theme.Colors.Pink },
}

----------------------------------------------------------------------
-- Types et état
----------------------------------------------------------------------

type Part = { Object: Instance, Prop: string, Color: Color3 }

-- Illustration (paquet ou coffre) dessinée avec des Frames
type Art = {
	Frame: Frame,
	Lid: Frame,
	LidBase: UDim2,
	Size: number,
	Parts: { Part }, -- éléments colorés (pour les repeindre en gris)
	Diamond: TextLabel?,
	DiamondBase: UDim2?,
}

type Card = {
	Day: number,
	Big: boolean,
	Card: Frame,
	Fill: UIGradient,
	Glow: Frame,
	Stroke: UIStroke,
	Shimmer: UIGradient,
	Title: TextLabel,
	Art: Art,
	Rays: Frame?,
	Pill: Frame,
	Amount: TextLabel,
	Dim: Frame,
	Stamp: Frame,
	StampScale: UIScale,
	Lock: Frame,
	LockLabel: TextLabel,
	Ribbon: Frame,
	RibbonLabel: TextLabel,
	State: string,
	Busy: boolean, -- animé par la séquence de récupération
}

local random = Random.new()
local built = false
local contentFrame: Frame
local cards: { Card } = {}

-- En-tête
local heroRays: Frame
local heroHalo: Frame
local heroGift: Art
local heroStatus: TextLabel
local streakChip: Frame
local rewardChip: Frame
local sparkles: { TextLabel } = {}
local segments: { Frame } = {}
local ringTime: TextLabel
local ringCaption: TextLabel

-- Jauge de série
local meterFill: Frame
local flameTip: TextLabel
local flameScale: UIScale
local streakLabel: TextLabel
local goalLabel: TextLabel
local meterRatio = -1

-- Montant, bouton, astuce
local amountCaption: TextLabel
local amountLabel: TextLabel
local button: TextButton
local buttonLabel: TextLabel
local buttonGlow: Frame
local shine: Frame
local hintLabel: TextLabel

local currentInfo: any = nil -- dernier Data.Daily affiché
local latestData: any = nil -- dernier état reçu (même pendant la séquence)
local lastInfoClock = 0
local tomorrowText = ""
local claiming = false -- appel serveur en cours
local celebrating = false -- séquence de récupération en cours
local lastRefusal = 0
local animation: RBXScriptConnection? = nil
local animStart = 0
local textClock = 0
local buttonPulsing = false

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function isAvailable(): boolean
	return currentInfo ~= nil and currentInfo.Available == true
end

-- Secondes restantes avant le prochain cadeau (prédites localement)
local function remainingSeconds(): number
	local info = currentInfo
	if not info then
		return 0
	end
	return math.max(0, (tonumber(info.NextIn) or 0) - (os.clock() - lastInfoClock))
end

-- Secondes de production offertes pour une série donnée (comme le serveur)
local function rewardSeconds(streak: number): number
	local capped = math.clamp(streak, 1, DAYS)
	return Config.Daily.BaseRewardSeconds + (capped - 1) * Config.Daily.StreakBonusSeconds
end

-- Estimation de la récompense pour une série donnée (même formule que
-- DailyRewardService.computeReward) ; nil si la production est inconnue
local function estimateReward(data, streak: number): number?
	local perSecond = tonumber(data and data.PerSecond)
	local clickValue = tonumber(data and data.ClickValue)
	if not perSecond or not clickValue then
		return nil
	end
	local capped = math.clamp(streak, 1, DAYS)
	return Formulas.ScaledReward(
		{ PerSecond = perSecond, ClickValue = clickValue },
		rewardSeconds(capped),
		Config.Daily.MinReward * capped
	)
end

local function formatReward(value: number): string
	return "+" .. NumberFormatter.Format(value, 1) .. " " .. ICON
end

local function setChipText(chip: Frame, text: string)
	local label = chip:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = text
	end
end

-- Position (en échelle) d'un point d'un élément, dans la zone de contenu
local function toContent(object: GuiObject, ax: number, ay: number): UDim2
	local size = contentFrame.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return UDim2.fromScale(0.5, 0.5)
	end
	local point = object.AbsolutePosition + object.AbsoluteSize * Vector2.new(ax, ay) - contentFrame.AbsolutePosition
	return UDim2.fromScale(point.X / size.X, point.Y / size.Y)
end

-- "Trémoussement" périodique : secousse rapide qui s'amortit, puis pause
local function wiggle(t: number): number
	local phase = t % 2.4
	if phase < 0.7 then
		return math.sin(phase * 38) * 11 * (1 - phase / 0.7)
	end
	return 0
end

local function shade(object: Instance)
	UIUtil.Gradient(object, ColorSequence.new(WHITE, Color3.fromRGB(205, 205, 205)), 90)
end

local function paint(parts: { Part }, object: Instance, prop: string, color: Color3)
	table.insert(parts, { Object = object, Prop = prop, Color = color })
	local target: any = object
	target[prop] = color
end

local function block(parent: Instance, name: string, props: { [string]: any }): Frame
	props.Name = name
	props.BorderSizePixel = 0
	props.Parent = parent
	return UIUtil.Create("Frame", props)
end

local function round(object: Instance)
	UIUtil.Corner(object, UDim.new(1, 0))
end

----------------------------------------------------------------------
-- Illustrations : paquet cadeau et coffre à diamant
----------------------------------------------------------------------

local function artFrame(parent: Instance, size: number, z: number, name: string): Frame
	local frame = UIUtil.Create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z,
	})
	-- Les dessins (paquet, coffre) gardent leurs couleurs en mode sombre
	frame:SetAttribute("DarkSkinIgnore", true)
	frame.Parent = parent
	return frame
end

-- "s" du pluriel ("1 day" / "2 days", "1 jour" / "2 jours", "0 day(s)" selon la langue)
local function pluralS(count: number): string
	if Locale.IsFrench() then
		return count > 1 and "s" or ""
	end
	return count ~= 1 and "s" or ""
end

-- Paquet : boîte + couvercle + ruban en croix + nœud à deux boucles
local function buildGift(parent: Instance, size: number, paper: Color3, ribbon: Color3, z: number): Art
	local parts: { Part } = {}
	local frame = artFrame(parent, size, z, "Gift")
	local edge = paper:Lerp(BLACK, 0.35)
	local ribbonEdge = ribbon:Lerp(BLACK, 0.3)

	-- Boîte
	local body = block(frame, "Body", {
		Size = UDim2.fromScale(0.78, 0.52),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		ZIndex = z,
	})
	UIUtil.Corner(body, math.max(3, math.floor(size * 0.07)))
	paint(parts, body, "BackgroundColor3", paper)
	paint(parts, UIUtil.Stroke(body, edge, 1.5, 0.2), "Color", edge)
	shade(body)
	local bodyRibbon = block(body, "Ribbon", {
		Size = UDim2.fromScale(0.2, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		ZIndex = z + 1,
	})
	paint(parts, bodyRibbon, "BackgroundColor3", ribbon)
	local gloss = block(body, "Gloss", {
		Size = UDim2.fromScale(0.08, 0.6),
		Position = UDim2.fromScale(0.1, 0.18),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = z + 1,
	})
	round(gloss)

	-- Couvercle (porte le nœud : ils s'envolent ensemble à l'ouverture)
	local lid = block(frame, "Lid", {
		Size = UDim2.fromScale(0.92, 0.2),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.49),
		ZIndex = z + 2,
	})
	UIUtil.Corner(lid, math.max(3, math.floor(size * 0.06)))
	paint(parts, lid, "BackgroundColor3", paper:Lerp(WHITE, 0.12))
	paint(parts, UIUtil.Stroke(lid, edge, 1.5, 0.2), "Color", edge)
	shade(lid)
	local lidRibbon = block(lid, "Ribbon", {
		Size = UDim2.fromScale(0.18, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		ZIndex = z + 3,
	})
	paint(parts, lidRibbon, "BackgroundColor3", ribbon)

	-- Nœud : deux boucles inclinées + le centre
	local loopSize = UDim2.fromOffset(math.floor(size * 0.3), math.floor(size * 0.2))
	for side = -1, 1, 2 do
		local loop = block(lid, "Loop", {
			Size = loopSize,
			AnchorPoint = Vector2.new(side < 0 and 1 or 0, 1),
			Position = UDim2.new(0.5, -side, 0, math.floor(size * 0.03)),
			Rotation = side < 0 and 18 or -18,
			ZIndex = z + 3,
		})
		UIUtil.Corner(loop, UDim.new(0.5, 0))
		paint(parts, loop, "BackgroundColor3", ribbon)
		paint(parts, UIUtil.Stroke(loop, ribbonEdge, 1.5, 0.1), "Color", ribbonEdge)
		local hole = block(loop, "Hole", {
			Size = UDim2.fromScale(0.42, 0.36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side < 0 and 0.42 or 0.58, 0.5),
			ZIndex = z + 4,
		})
		round(hole)
		paint(parts, hole, "BackgroundColor3", ribbonEdge)
	end
	local knotSize = math.max(6, math.floor(size * 0.14))
	local knot = block(lid, "Knot", {
		Size = UDim2.fromOffset(knotSize, knotSize),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 1),
		ZIndex = z + 5,
	})
	round(knot)
	paint(parts, knot, "BackgroundColor3", ribbon:Lerp(WHITE, 0.15))
	paint(parts, UIUtil.Stroke(knot, ribbonEdge, 1.5, 0.1), "Color", ribbonEdge)

	return { Frame = frame, Lid = lid, LidBase = lid.Position, Size = size, Parts = parts }
end

-- Coffre violet cerclé d'or, gros diamant posé dessus
local function buildChest(parent: Instance, size: number, z: number): Art
	local parts: { Part } = {}
	local frame = artFrame(parent, size, z, "Chest")
	local goldEdge = Color3.fromRGB(190, 120, 0)

	local body = block(frame, "Body", {
		Size = UDim2.fromScale(0.86, 0.42),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		ZIndex = z,
	})
	UIUtil.Corner(body, math.max(3, math.floor(size * 0.06)))
	paint(parts, body, "BackgroundColor3", CHEST_PURPLE)
	paint(parts, UIUtil.Stroke(body, goldEdge, 2, 0), "Color", goldEdge)
	shade(body)
	for _, x in ipairs({ 0.2, 0.8 }) do
		local band = block(body, "Band", {
			Size = UDim2.fromScale(0.1, 1),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0),
			ZIndex = z + 1,
		})
		paint(parts, band, "BackgroundColor3", GOLD)
	end
	local plate = block(body, "Lock", {
		Size = UDim2.fromScale(0.2, 0.46),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		ZIndex = z + 2,
	})
	UIUtil.Corner(plate, 3)
	paint(parts, plate, "BackgroundColor3", GOLD)
	paint(parts, UIUtil.Stroke(plate, goldEdge, 1.5, 0), "Color", goldEdge)
	local keyhole = block(plate, "Keyhole", {
		Size = UDim2.fromScale(0.3, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		ZIndex = z + 3,
	})
	round(keyhole)
	paint(parts, keyhole, "BackgroundColor3", Color3.fromRGB(70, 40, 10))

	-- Couvercle bombé (coins du bas masqués par un rectangle)
	local lidColor = CHEST_PURPLE:Lerp(WHITE, 0.12)
	local lid = block(frame, "Lid", {
		Size = UDim2.fromScale(0.9, 0.26),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.57),
		ZIndex = z + 2,
	})
	UIUtil.Corner(lid, UDim.new(0.5, 0))
	paint(parts, lid, "BackgroundColor3", lidColor)
	local lidFill = block(lid, "Fill", {
		Size = UDim2.fromScale(1, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = z + 2,
	})
	paint(parts, lidFill, "BackgroundColor3", lidColor)
	for _, x in ipairs({ 0.2, 0.8 }) do
		local band = block(lid, "Band", {
			Size = UDim2.fromScale(0.1, 1),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0),
			ZIndex = z + 3,
		})
		paint(parts, band, "BackgroundColor3", GOLD)
	end
	local trim = block(lid, "Trim", {
		Size = UDim2.fromScale(1, 0.22),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		ZIndex = z + 3,
	})
	paint(parts, trim, "BackgroundColor3", GOLD)

	local diamondSize = math.floor(size * 0.44)
	local diamond = UIUtil.Label({
		Name = "Diamond",
		Text = "💎",
		Size = UDim2.fromOffset(diamondSize, diamondSize),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.36),
		MaxTextSize = diamondSize,
		ZIndex = z + 6,
		Parent = frame,
	})

	return {
		Frame = frame,
		Lid = lid,
		LidBase = lid.Position,
		Size = size,
		Parts = parts,
		Diamond = diamond,
		DiamondBase = diamond.Position,
	}
end

-- Repeint une illustration : "color" (normal), "soft" (adouci), "grey" (verrouillé)
local function paintArt(art: Art, mode: string)
	for _, part in ipairs(art.Parts) do
		local color = part.Color
		if mode == "grey" then
			color = GREY:Lerp(color, 0.18)
		elseif mode == "soft" then
			color = color:Lerp(GREY, 0.45)
		end
		local target: any = part.Object
		target[part.Prop] = color
	end
end

local function openLid(art: Art, side: number)
	local s = art.Size
	UIUtil.Tween(art.Lid, 0.35, {
		Position = art.LidBase + UDim2.fromOffset(side * s * 0.28, -s * 0.5),
		Rotation = side * 28,
	}, Enum.EasingStyle.Back)
	local diamond, base = art.Diamond, art.DiamondBase
	if diamond and base then
		UIUtil.Tween(diamond, 0.4, { Position = base + UDim2.fromOffset(0, -s * 0.3) }, Enum.EasingStyle.Back)
	end
end

local function closeLid(art: Art)
	UIUtil.Tween(art.Lid, 0.3, { Position = art.LidBase, Rotation = 0 })
	local diamond, base = art.Diamond, art.DiamondBase
	if diamond and base then
		UIUtil.Tween(diamond, 0.3, { Position = base })
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildHero(content: Frame)
	local hero = UIUtil.Create("Frame", {
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, HERO_HEIGHT),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		Parent = content,
	})
	UIUtil.Corner(hero, Theme.Radius.L)
	UIUtil.Stroke(hero, HERO_TOP, 1.5, 0.3)
	UIUtil.Gradient(hero, ColorSequence.new(HERO_TOP, HERO_BOTTOM), 20)

	-- Grosses bulles claires pour la profondeur
	for index, spec in ipairs({ { 0.62, -0.5, 190 }, { 0.93, 1.1, 150 } }) do
		local bubble = UIUtil.Create("Frame", {
			Name = "Bubble" .. index,
			Size = UDim2.fromOffset(spec[3], spec[3]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.88,
			ZIndex = 1,
			Parent = hero,
		})
		round(bubble)
	end

	-- Étincelles
	local seeded = Random.new(7)
	for index = 1, 12 do
		local star = UIUtil.Label({
			Name = "Sparkle" .. index,
			Text = index % 3 == 0 and "✦" or "•",
			TextColor3 = WHITE,
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(seeded:NextNumber(0.2, 0.8), seeded:NextNumber(0.1, 0.9)),
			MaxTextSize = index % 3 == 0 and 14 or 10,
			ZIndex = 2,
			Parent = hero,
		})
		star:SetAttribute("Phase", seeded:NextNumber(0, math.pi * 2))
		table.insert(sparkles, star)
	end

	-- Gros paquet devant des rayons
	heroRays = UIUtil.Rays(hero, WHITE, 10, 240, HERO_GIFT_POS, 2)
	heroHalo = UIUtil.Create("Frame", {
		Name = "Halo",
		Size = UDim2.fromOffset(92, 92),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = HERO_GIFT_POS,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		ZIndex = 2,
		Parent = hero,
	})
	round(heroHalo)
	heroGift = buildGift(hero, 78, Theme.Colors.Purple, GOLD, 3)
	heroGift.Frame.Position = HERO_GIFT_POS

	local title = UIUtil.Label({
		Name = "HeroTitle",
		Text = Locale.T("Gift Calendar"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(140 + 130), 0, 30),
		Position = UDim2.fromOffset(140, 12),
		MaxTextSize = 26,
		ZIndex = 4,
		Parent = hero,
	})
	local titleStroke = UIUtil.Stroke(title, PINK_DARK, 1.5, 0.35)
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	heroStatus = UIUtil.Label({
		Name = "Status",
		Text = "",
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(140 + 130), 0, 20),
		Position = UDim2.fromOffset(140, 44),
		MaxTextSize = 16,
		ZIndex = 4,
		Parent = hero,
	})

	local chips = UIUtil.Create("Frame", {
		Name = "Chips",
		Size = UDim2.new(1, -(140 + 130), 0, 26),
		Position = UDim2.fromOffset(140, 72),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = hero,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	streakChip = UIUtil.Chip({
		Name = "StreakChip",
		Text = Locale.T("🔥 Streak: –"),
		Color = WHITE,
		TextColor3 = PINK_DARK,
		StrokeColor = WHITE,
		Height = 26,
		TextSize = 14,
		LayoutOrder = 1,
		ZIndex = 4,
		Parent = chips,
	})
	rewardChip = UIUtil.Chip({
		Name = "RewardChip",
		Text = "",
		Color = Color3.fromRGB(90, 20, 70),
		TextColor3 = WHITE,
		StrokeColor = WHITE,
		Height = 26,
		TextSize = 14,
		LayoutOrder = 2,
		ZIndex = 4,
		Parent = chips,
	})
	rewardChip.BackgroundTransparency = 0.35

	-- Anneau de compte à rebours (segments qui s'allument au fil de la journée)
	local ring = UIUtil.Create("Frame", {
		Name = "Countdown",
		Size = UDim2.fromOffset(RING_SIZE, RING_SIZE),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -66, 0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = hero,
	})
	local disc = UIUtil.Create("Frame", {
		Name = "Disc",
		Size = UDim2.new(1, -20, 1, -20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82,
		ZIndex = 4,
		Parent = ring,
	})
	round(disc)
	UIUtil.Stroke(disc, WHITE, 1.5, 0.5)
	for index = 1, RING_SEGMENTS do
		local angle = (index - 1) / RING_SEGMENTS * math.pi * 2
		local segment = UIUtil.Create("Frame", {
			Name = "Segment" .. index,
			Size = UDim2.fromOffset(4, 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(angle) * RING_RADIUS, 0.5, -math.cos(angle) * RING_RADIUS),
			Rotation = math.deg(angle),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = ring,
		})
		UIUtil.Corner(segment, 2)
		segments[index] = segment
	end
	ringTime = UIUtil.Label({
		Name = "Time",
		Text = "…",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		Size = UDim2.new(1, -30, 0, 24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -6),
		MaxTextSize = 20,
		ZIndex = 6,
		Parent = ring,
	})
	ringCaption = UIUtil.Label({
		Name = "Caption",
		Text = "",
		TextColor3 = WHITE,
		Size = UDim2.new(1, -30, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 13),
		MaxTextSize = 11,
		ZIndex = 6,
		Parent = ring,
	})
end

local function buildCard(row: Frame, day: number): Card
	local big = day == DAYS
	local x = (day - 1) * (UNIT + GAP)
	local width = big and UNIT * BIG_RATIO or UNIT
	local holder = UIUtil.Create("Frame", {
		Name = "Day" .. day,
		Size = UDim2.new(width / CONTENT_WIDTH, 0, 1, 0),
		Position = UDim2.fromScale(x / CONTENT_WIDTH, 0),
		BackgroundTransparency = 1,
		Parent = row,
	})

	-- Halo derrière la carte (jour actuel / coffre)
	local glow = UIUtil.Create("Frame", {
		Name = "Glow",
		Size = UDim2.new(1, 16, 1, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.6,
		Visible = false,
		ZIndex = 1,
		Parent = holder,
	})
	UIUtil.Corner(glow, Theme.Radius.L + 8)
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
		Parent = glow,
	})

	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = holder,
	})
	UIUtil.Corner(card, Theme.Radius.L)
	local fill = UIUtil.Gradient(card, ColorSequence.new(WHITE, WHITE), 90)
	local stroke = UIUtil.Stroke(card, Theme.Colors.Divider, 1.5)
	local shimmer = UIUtil.Create("UIGradient", {
		Enabled = false,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, GOLD),
			ColorSequenceKeypoint.new(0.5, WHITE),
			ColorSequenceKeypoint.new(1, GOLD),
		}),
		Parent = stroke,
	})
	UIUtil.Shadow(card, 3, 0.9, 2)

	local title = UIUtil.Label({
		Name = "DayTitle",
		Text = big and Locale.T("DAY %s • MEGA", tostring(day)) or Locale.T("DAY %s", tostring(day)),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(6, 12),
		MaxTextSize = 14,
		ZIndex = 5,
		Parent = card,
	})

	-- Rayons dorés derrière le coffre (coupés aux bords de la carte)
	local rays: Frame? = nil
	if big then
		local clip = UIUtil.Create("Frame", {
			Name = "RayClip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 4,
			Parent = card,
		})
		rays = UIUtil.Rays(clip, GOLD, 8, math.floor(width * 1.15), UDim2.new(0.5, 0, 0, 70), 4)
	end

	local artArea = UIUtil.Create("Frame", {
		Name = "ArtArea",
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = card,
	})
	local art: Art
	if big then
		art = buildChest(artArea, CHEST_SIZE, 5)
		art.Frame.Position = UDim2.new(0.5, 0, 0.5, 4) -- le diamant dépasse en haut
	else
		local colors = GIFT_COLORS[((day - 1) % #GIFT_COLORS) + 1]
		art = buildGift(artArea, GIFT_SIZE, colors.Paper, colors.Ribbon, 5)
	end

	-- Pastille du montant
	local pill = UIUtil.Create("Frame", {
		Name = "Reward",
		Size = UDim2.new(1, -12, 0, 26),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		BackgroundColor3 = Theme.Colors.PanelLight,
		ZIndex = 5,
		Parent = card,
	})
	round(pill)
	local amount = UIUtil.Label({
		Name = "Amount",
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromOffset(5, 3),
		MaxTextSize = 15,
		ZIndex = 6,
		Parent = pill,
	})

	-- Voile blanc (jour récupéré)
	local dim = UIUtil.Create("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.38,
		Visible = false,
		ZIndex = 20,
		Parent = card,
	})
	UIUtil.Corner(dim, Theme.Radius.L)

	-- Tampon "✔"
	local stamp = UIUtil.Create("Frame", {
		Name = "Stamp",
		Size = UDim2.fromOffset(54, 54),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 70),
		Rotation = -14,
		BackgroundColor3 = Theme.Colors.Green,
		Visible = false,
		ZIndex = 21,
		Parent = card,
	})
	round(stamp)
	UIUtil.Stroke(stamp, WHITE, 3)
	UIUtil.Gradient(stamp, ColorSequence.new(WHITE, Color3.fromRGB(185, 185, 185)), 90)
	local innerRing = UIUtil.Create("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, -10, 1, -10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = stamp,
	})
	round(innerRing)
	UIUtil.Stroke(innerRing, WHITE, 1.5, 0.3)
	UIUtil.Label({
		Name = "Check",
		Text = "✔",
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		Size = UDim2.fromScale(0.62, 0.62),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 30,
		ZIndex = 23,
		Parent = stamp,
	})
	local stampScale = UIUtil.Create("UIScale", { Parent = stamp })

	-- Cadenas / sablier
	local lock = UIUtil.Create("Frame", {
		Name = "Lock",
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -5, 0, 32),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 21,
		Parent = card,
	})
	round(lock)
	UIUtil.Stroke(lock, Theme.Colors.Divider, 1)
	local lockLabel = UIUtil.Label({
		Text = "🔒",
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.fromOffset(3, 3),
		MaxTextSize = 13,
		ZIndex = 22,
		Parent = lock,
	})

	-- Ruban "AUJOURD'HUI" / "DEMAIN" à cheval sur le haut de la carte
	local ribbon = UIUtil.Create("Frame", {
		Name = "Ribbon",
		Size = UDim2.new(1, 6, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Theme.Colors.Pink,
		Visible = false,
		ZIndex = 22,
		Parent = card,
	})
	UIUtil.Corner(ribbon, 7)
	UIUtil.Stroke(ribbon, WHITE, 1.5)
	shade(ribbon)
	local ribbonLabel = UIUtil.Label({
		Text = Locale.T("TODAY"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		Size = UDim2.new(1, -8, 1, -4),
		Position = UDim2.fromOffset(4, 2),
		MaxTextSize = 12,
		ZIndex = 23,
		Parent = ribbon,
	})

	return {
		Day = day,
		Big = big,
		Card = card,
		Fill = fill,
		Glow = glow,
		Stroke = stroke,
		Shimmer = shimmer,
		Title = title,
		Art = art,
		Rays = rays,
		Pill = pill,
		Amount = amount,
		Dim = dim,
		Stamp = stamp,
		StampScale = stampScale,
		Lock = lock,
		LockLabel = lockLabel,
		Ribbon = ribbon,
		RibbonLabel = ribbonLabel,
		State = "",
		Busy = false,
	}
end

local function buildMeter(content: Frame)
	local meter = UIUtil.Create("Frame", {
		Name = "StreakMeter",
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, METER_Y),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local badge = UIUtil.Create("Frame", {
		Name = "Flame",
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = WHITE,
		Parent = meter,
	})
	round(badge)
	UIUtil.Stroke(badge, Theme.Colors.Orange:Lerp(BLACK, 0.2), 1.5, 0.2)
	UIUtil.Gradient(badge, ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.Red), 90)
	UIUtil.Label({
		Text = "🔥",
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		MaxTextSize = 20,
		Parent = badge,
	})
	streakLabel = UIUtil.Label({
		Name = "Streak",
		Text = Locale.T("Streak: –"),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 146, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		MaxTextSize = 18,
		Parent = meter,
	})

	local track = UIUtil.Create("Frame", {
		Name = "Track",
		Size = UDim2.new(1, -(200 + 118), 0, 16),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 200, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 234, 216),
		Parent = meter,
	})
	round(track)
	UIUtil.Stroke(track, Theme.Colors.Orange, 1, 0.6)
	meterFill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})
	round(meterFill)
	UIUtil.Gradient(meterFill, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Colors.Yellow),
		ColorSequenceKeypoint.new(0.5, Theme.Colors.Orange),
		ColorSequenceKeypoint.new(1, Theme.Colors.Red),
	}), 0)
	for k = 1, DAYS - 1 do
		UIUtil.Create("Frame", {
			Name = "Notch" .. k,
			Size = UDim2.new(0, 2, 1, -6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(k / DAYS, 0, 0.5, 0),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = track,
		})
	end
	local goal = UIUtil.Create("Frame", {
		Name = "Goal",
		Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
		Parent = track,
	})
	round(goal)
	UIUtil.Stroke(goal, Theme.Colors.Purple, 2, 0.2)
	UIUtil.Label({
		Text = "💎",
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		MaxTextSize = 18,
		ZIndex = 5,
		Parent = goal,
	})
	flameTip = UIUtil.Label({
		Name = "FlameTip",
		Text = "🔥",
		Size = UDim2.fromOffset(28, 28),
		AnchorPoint = Vector2.new(0.5, 0.65),
		Position = UDim2.fromScale(0, 0.5),
		MaxTextSize = 24,
		ZIndex = 6,
		Parent = track,
	})
	flameScale = UIUtil.Create("UIScale", { Parent = flameTip })
	goalLabel = UIUtil.Label({
		Name = "GoalText",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Purple:Lerp(BLACK, 0.2),
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0, 96, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		MaxTextSize = 15,
		Parent = meter,
	})
end

local function buildButton(content: Frame)
	local center = UDim2.new(0.5, 0, 0, BUTTON_Y + BUTTON_SIZE.Y / 2)
	buttonGlow = UIUtil.Create("Frame", {
		Name = "ClaimGlow",
		Size = UDim2.fromOffset(BUTTON_SIZE.X + 28, BUTTON_SIZE.Y + 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		BackgroundColor3 = Theme.Colors.Pink,
		BackgroundTransparency = 0.7,
		Visible = false,
		ZIndex = 1,
		Parent = content,
	})
	round(buttonGlow)

	button = UIUtil.NeonButton({
		Name = "Claim",
		Text = "",
		Size = UDim2.fromOffset(BUTTON_SIZE.X, BUTTON_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Color = Theme.Colors.Pink,
		CornerRadius = math.floor(BUTTON_SIZE.Y / 2),
		ZIndex = 3,
		Parent = content,
	})

	-- Reflet qui balaie le bouton (CanvasGroup : coupé aux coins arrondis).
	-- Le bouton a un UIPadding (8 / 4 px) : on le compense.
	local clip = UIUtil.Create("CanvasGroup", {
		Name = "ShineClip",
		Size = UDim2.new(1, 16, 1, 8),
		Position = UDim2.fromOffset(-8, -4),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = button,
	})
	round(clip)
	shine = UIUtil.Create("Frame", {
		Name = "Shine",
		Size = UDim2.new(0, 46, 2, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.2, 0.5),
		Rotation = 18,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
		Parent = clip,
	})
	UIUtil.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = shine,
	})

	buttonLabel = UIUtil.Label({
		Name = "Label",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = 28,
		ZIndex = 5,
		Parent = button,
	})
	local labelStroke = UIUtil.Stroke(buttonLabel, PINK_DARK, 1.5, 0.4)
	labelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
end

----------------------------------------------------------------------
-- Mises à jour
----------------------------------------------------------------------

local function setCardState(card: Card, state: string, text: string)
	local previous = card.State
	if previous == state then
		-- Même état (mise à jour fréquente) : seul le montant peut changer
		card.Amount.Text = text
		return
	end
	card.State = state
	local today = state == "today"
	local claimed = state == "claimed"
	local tomorrow = state == "tomorrow"
	local locked = state == "locked"
	local art = card.Art

	card.Card.Position = UDim2.new()
	art.Frame.Rotation = 0
	art.Lid.Position = art.LidBase
	art.Lid.Rotation = 0
	paintArt(art, (locked and "grey") or (tomorrow and "soft") or "color")

	card.Card.BackgroundColor3 = (today or tomorrow) and WHITE or Theme.Colors.Surface
	local tint = Theme.Colors.PanelLight
	if today then
		tint = Theme.Colors.Pink:Lerp(WHITE, 0.8)
	elseif card.Big and not claimed then
		tint = Theme.Colors.Purple:Lerp(WHITE, 0.84)
	elseif tomorrow then
		tint = Theme.Colors.Blue:Lerp(WHITE, 0.88)
	end
	card.Fill.Color = ColorSequence.new(WHITE, tint)

	card.Stroke.Color = (today and GOLD) or (tomorrow and Theme.Colors.Blue) or Theme.Colors.Divider
	card.Stroke.Thickness = today and 3 or 1.5
	card.Stroke.Transparency = tomorrow and 0.35 or 0
	card.Shimmer.Enabled = today
	card.Glow.Visible = today or (card.Big and not claimed)
	card.Glow.BackgroundColor3 = today and GOLD or Theme.Colors.Purple
	card.Glow.BackgroundTransparency = today and 0.5 or 0.78

	card.Dim.Visible = claimed
	card.Dim.BackgroundTransparency = 0.38
	card.Stamp.Visible = claimed
	card.Stamp.Rotation = -14
	card.StampScale.Scale = 1
	card.Lock.Visible = locked or tomorrow
	card.LockLabel.Text = tomorrow and "⏳" or "🔒"
	card.Ribbon.Visible = today or tomorrow
	card.Ribbon.BackgroundColor3 = today and Theme.Colors.Pink or Theme.Colors.Blue
	card.RibbonLabel.Text = today and Locale.T("TODAY") or Locale.T("TOMORROW")
	card.Title.TextColor3 = today and PINK_DARK or Theme.Colors.TextDim

	card.Pill.BackgroundColor3 = (today and Theme.Colors.Pink)
		or (claimed and Theme.Colors.Green:Lerp(WHITE, 0.72))
		or Theme.Colors.PanelLight
	card.Amount.TextColor3 = (today and WHITE) or (claimed and GREEN_DARK) or Theme.Colors.TextDim
	card.Amount.Text = text

	if card.Rays then
		card.Rays.Visible = not claimed
	end
	local diamond, base = art.Diamond, art.DiamondBase
	if diamond and base then
		diamond.Position = base
		diamond.Rotation = 0
		diamond.TextTransparency = locked and 0.2 or 0
	end
	-- Nouveau "jour actuel" (ex. minuit passé fenêtre ouverte) : petit pop
	if today and previous ~= "" and previous ~= state then
		UIUtil.Pop(card.Card, 0.85, 0.4)
	end
end

local function setMeter(claimedCount: number, activeStreak: number, todayIsLast: boolean)
	local ratio = math.clamp(claimedCount / DAYS, 0, 1)
	if ratio ~= meterRatio then
		meterRatio = ratio
		UIUtil.Tween(meterFill, 0.5, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quint)
		UIUtil.Tween(flameTip, 0.5, { Position = UDim2.fromScale(ratio, 0.5) }, Enum.EasingStyle.Quint)
	end
	flameTip.TextTransparency = claimedCount > 0 and 0 or 0.45
	streakLabel.Text = Locale.T("Streak: %d day%s", activeStreak, pluralS(activeStreak))
	local left = DAYS - claimedCount
	if left <= 0 then
		goalLabel.Text = Locale.T("💎 MAX!")
	elseif todayIsLast then
		goalLabel.Text = Locale.T("💎 today!")
	else
		goalLabel.Text = Locale.T("💎 in %d d", left)
	end
end

local function setButton(mode: string)
	if mode == "ready" then
		UIUtil.SetButtonEnabled(button, true)
		buttonLabel.Text = Locale.T("🎁  CLAIM")
		buttonLabel.TextTransparency = 0
	elseif mode == "busy" then
		button:SetAttribute("Enabled", false)
		buttonLabel.Text = Locale.T("OPENING…")
		buttonLabel.TextTransparency = 0
	elseif mode == "party" then
		button:SetAttribute("Enabled", false)
		buttonLabel.Text = Locale.T("🎉  WELL DONE!")
		buttonLabel.TextTransparency = 0
	elseif mode == "claimed" then
		UIUtil.SetButtonEnabled(button, false)
		buttonLabel.Text = Locale.T("✔  ALREADY CLAIMED")
		buttonLabel.TextTransparency = 0.1
	else
		UIUtil.SetButtonEnabled(button, false)
		buttonLabel.Text = Locale.T("Loading…")
		buttonLabel.TextTransparency = 0.2
	end
end

-- Anneau : chenillard doré si le cadeau est prêt, sinon la part de la
-- journée écoulée (le segment de tête clignote)
local function refreshRing(t: number)
	local info = currentInfo
	if not info then
		for _, segment in ipairs(segments) do
			segment.BackgroundColor3 = WHITE
			segment.BackgroundTransparency = 0.75
		end
		return
	end
	if info.Available == true then
		for index, segment in ipairs(segments) do
			local wave = 0.5 + 0.5 * math.sin(t * 7 - index * (math.pi * 4 / RING_SEGMENTS))
			segment.BackgroundColor3 = WHITE:Lerp(GOLD_LIGHT, wave)
			segment.BackgroundTransparency = 0.05 + 0.3 * (1 - wave)
		end
		return
	end
	local elapsed = math.clamp(1 - remainingSeconds() / SECONDS_PER_DAY, 0, 1)
	local lit = math.floor(elapsed * RING_SEGMENTS + 0.5)
	for index, segment in ipairs(segments) do
		segment.BackgroundColor3 = WHITE
		if index < lit then
			segment.BackgroundTransparency = 0.05
		elseif index == lit then
			segment.BackgroundTransparency = 0.05 + 0.5 * (0.5 + 0.5 * math.sin(t * 6))
		else
			segment.BackgroundTransparency = 0.72
		end
	end
end

-- Textes qui dépendent du temps (anneau, astuce)
local function refreshTimers()
	local info = currentInfo
	if not info then
		ringTime.Text = "…"
		ringCaption.Text = Locale.T("loading")
		return
	end
	if info.Available == true then
		ringTime.Text = Locale.T("READY!")
		ringCaption.Text = Locale.T("open it quick")
		return
	end
	local remaining = remainingSeconds()
	ringTime.Text = UIUtil.FormatClock(remaining)
	if remaining <= 0 then
		ringCaption.Text = Locale.T("almost here…")
		hintLabel.Text = Locale.T("⏳ Your next gift is on its way…")
	else
		ringCaption.Text = Locale.T("next gift")
		hintLabel.Text = Locale.T("⏳ Next gift in %s", NumberFormatter.Time(remaining)) .. tomorrowText
	end
end

-- Applique un état serveur à tout le panneau
local function apply(data)
	if not built then
		return
	end
	local info = data and data.Daily
	if type(info) ~= "table" then
		-- Pas encore d'état (ou calendrier absent) : squelette propre
		currentInfo = nil
		heroStatus.Text = Locale.T("Loading the calendar...")
		setChipText(streakChip, Locale.T("🔥 Streak: –"))
		rewardChip.Visible = false
		for _, card in ipairs(cards) do
			setCardState(card, "locked", "…")
		end
		setMeter(0, 0, false)
		amountCaption.Text = Locale.T("TODAY'S REWARD")
		amountLabel.Text = "…"
		amountLabel.TextColor3 = Theme.Colors.TextDim
		setButton("loading")
		hintLabel.Text = Locale.T("Loading...")
		refreshTimers()
		return
	end

	currentInfo = info
	lastInfoClock = os.clock()
	local available = info.Available == true
	local streak = math.max(0, math.floor(tonumber(info.Streak) or 0))
	local reward = tonumber(info.Reward) or 0
	-- Série de jours déjà faits (le jour du cadeau disponible n'est pas compté)
	local activeStreak = available and math.max(0, streak - 1) or streak
	local todayIndex = available and math.clamp(streak, 1, DAYS) or nil
	local claimedCount = if todayIndex then todayIndex - 1 else math.min(streak, DAYS)
	local reference = math.max(1, todayIndex or claimedCount)

	for day, card in ipairs(cards) do
		local state = "locked"
		if day <= claimedCount then
			state = "claimed"
		elseif day == todayIndex then
			state = "today"
		elseif not available and day == claimedCount + 1 then
			state = "tomorrow"
		end
		local text
		if state == "claimed" then
			text = Locale.T("✔ Claimed")
		elseif state == "today" then
			text = formatReward(reward)
		else
			local estimate = estimateReward(data, day)
			if estimate then
				text = "≈ " .. formatReward(estimate)
			else
				local ratio = rewardSeconds(day) / rewardSeconds(reference)
				text = NumberFormatter.Multiplier(math.floor(ratio * 10 + 0.5) / 10)
			end
		end
		setCardState(card, state, text)
	end

	-- Estimation de demain (pour l'astuce du compte à rebours)
	tomorrowText = ""
	if not available then
		local tomorrow = estimateReward(data, streak + 1)
		if tomorrow then
			tomorrowText = Locale.T("  •  tomorrow ≈ %s", formatReward(tomorrow))
		end
	end

	-- En-tête
	if available then
		heroStatus.Text = streak > 1 and Locale.T("Day %d of your streak: your gift is waiting!", streak)
			or Locale.T("Your daily gift is waiting!")
		setChipText(rewardChip, "🎁 " .. formatReward(reward))
	else
		heroStatus.Text = streak >= DAYS and Locale.T("Max streak! A 💎 chest awaits you every day.")
			or Locale.T("Well done! Come back tomorrow for day %d.", claimedCount + 1)
		setChipText(rewardChip, Locale.T("✔ Claimed today"))
	end
	rewardChip.Visible = true
	setChipText(streakChip, Locale.T("🔥 Streak: %d day%s", activeStreak, pluralS(activeStreak)))

	setMeter(claimedCount, activeStreak, todayIndex == DAYS)

	-- Montant + bouton
	if available then
		amountCaption.Text = Locale.T("DAY %d REWARD", todayIndex or 1)
		amountLabel.Text = formatReward(reward)
		amountLabel.TextColor3 = PINK_DARK
		setButton("ready")
		hintLabel.Text = Locale.T("Come back every day: the reward grows with your streak 🔥")
	else
		amountCaption.Text = Locale.T("✔ CLAIMED TODAY")
		amountLabel.Text = formatReward(reward)
		amountLabel.TextColor3 = GREEN_DARK
		setButton("claimed")
	end
	refreshTimers()
end

----------------------------------------------------------------------
-- Séquence de récupération
----------------------------------------------------------------------

-- Onde de lumière qui s'élargit
local function lightBurst(origin: UDim2)
	local wave = UIUtil.Create("Frame", {
		Name = "LightBurst",
		Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = origin,
		BackgroundColor3 = GOLD_LIGHT,
		BackgroundTransparency = 0.15,
		ZIndex = 55,
		Parent = contentFrame,
	})
	round(wave)
	UIUtil.Tween(wave, 0.5, { Size = UDim2.fromOffset(220, 220), BackgroundTransparency = 1 }, Enum.EasingStyle.Quart)
	task.delay(0.55, function()
		wave:Destroy()
	end)
end

-- Gouttes de Dopamine qui jaillissent du paquet, montent puis retombent
local function flyDrops(origin: UDim2, count: number)
	for index = 1, count do
		task.delay((index - 1) * 0.03, function()
			if not contentFrame.Parent then
				return
			end
			local drop = UIUtil.Label({
				Name = "Drop",
				Text = ICON,
				Size = UDim2.fromOffset(26, 26),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = origin,
				Rotation = random:NextNumber(-25, 25),
				MaxTextSize = 24,
				ZIndex = 60,
				Parent = contentFrame,
			})
			local scale = UIUtil.Create("UIScale", { Scale = 0.3, Parent = drop })
			UIUtil.Tween(scale, 0.25, { Scale = random:NextNumber(0.9, 1.25) }, Enum.EasingStyle.Back)
			local apex = origin + UDim2.fromOffset(random:NextNumber(-130, 130), random:NextNumber(-170, -90))
			UIUtil.Tween(drop, 0.5, { Position = apex }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.5, function()
				if not drop.Parent then
					return
				end
				UIUtil.Tween(drop, 0.45, {
					Position = apex + UDim2.fromOffset(random:NextNumber(-20, 20), 50),
					Rotation = drop.Rotation + random:NextNumber(-60, 60),
					TextTransparency = 1,
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.delay(0.5, function()
					drop:Destroy()
				end)
			end)
		end)
	end
end

-- Le montant défile de 0 à `amount` (avec petits "tintements")
local function countUp(amount: number, duration: number)
	local start = os.clock()
	local lastTick = 0
	amountLabel.TextColor3 = GREEN_DARK
	while true do
		local k = math.clamp((os.clock() - start) / duration, 0, 1)
		local eased = 1 - (1 - k) ^ 3
		amountLabel.Text = formatReward(amount * eased)
		if k >= 1 then
			break
		end
		if os.clock() - lastTick > 0.11 then
			lastTick = os.clock()
			SoundManager.Play("Cash", 0.9 + 0.6 * k)
			UIUtil.Pop(amountLabel, 1.08, 0.12)
		end
		task.wait()
	end
	UIUtil.Pop(amountLabel, 1.35, 0.4)
end

-- Tampon "✔" qui s'écrase sur la carte du jour
local function stampCard(card: Card)
	card.Dim.Visible = true
	card.Dim.BackgroundTransparency = 1
	UIUtil.Tween(card.Dim, 0.3, { BackgroundTransparency = 0.38 })
	card.Stamp.Visible = true
	card.Stamp.Rotation = -40
	card.StampScale.Scale = 2.6
	UIUtil.Tween(card.StampScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	UIUtil.Tween(card.Stamp, 0.28, { Rotation = -14 }, Enum.EasingStyle.Back)
	card.Ribbon.Visible = false
	card.Glow.Visible = false
	card.Shimmer.Enabled = false
	card.Stroke.Color = Theme.Colors.Divider
	card.Stroke.Thickness = 1.5
	card.Pill.BackgroundColor3 = Theme.Colors.Green:Lerp(WHITE, 0.72)
	card.Amount.Text = Locale.T("✔ Claimed")
	card.Amount.TextColor3 = GREEN_DARK
	task.delay(0.2, function()
		if not card.Card.Parent then
			return
		end
		SoundManager.Play("Pop", 0.85)
		UIUtil.Shake(card.Card)
		Effects.Burst(contentFrame, toContent(card.Stamp, 0.5, 0.5), Theme.Colors.Green, 10)
	end)
end

local function claimSequence(card: Card?, amount: number, message: string)
	setButton("party")
	if card then
		card.Busy = true
		card.Card.Position = UDim2.new()
	end

	-- 1. Suspense : le paquet tremble de plus en plus fort
	SoundManager.Play("Chest", 1)
	local start = os.clock()
	while os.clock() - start < 0.5 do
		local k = (os.clock() - start) / 0.5
		local angle = math.sin(os.clock() * 55) * (3 + 12 * k)
		heroGift.Frame.Rotation = angle
		if card then
			card.Art.Frame.Rotation = angle
		end
		task.wait()
	end
	heroGift.Frame.Rotation = 0

	-- 2. Ouverture : couvercle qui saute, flash, confettis, gouttes
	openLid(heroGift, -1)
	local origin = UDim2.fromScale(0.5, 0.35)
	if card then
		card.Art.Frame.Rotation = 0
		openLid(card.Art, 1)
		origin = toContent(card.Art.Frame, 0.5, 0.45)
	end
	SoundManager.Play("Jackpot", 1.1)
	Effects.Flash(Theme.Colors.Pink, 0.25)
	Effects.Confetti(90)
	lightBurst(origin)
	Effects.Burst(contentFrame, origin, GOLD, 16)
	flyDrops(origin, 16)
	Effects.FloatingText(contentFrame, origin + UDim2.fromOffset(0, -40), formatReward(amount), GOLD, 30)

	-- 3. Le montant défile
	amountCaption.Text = Locale.T("🎉 GIFT CLAIMED!")
	countUp(amount, 1)

	-- 4. Tampon sur la carte + notification
	if card then
		stampCard(card)
	end
	Notifications.Toast(tostring(message or ""), Theme.Colors.Pink, 5, Locale.T("🎁 Gift claimed!"))
	task.wait(0.9)
	closeLid(heroGift)
	if card then
		closeLid(card.Art)
	end
	task.wait(0.35)
end

local function onClaim()
	if claiming or celebrating then
		return
	end
	if not button:GetAttribute("Enabled") then
		SoundManager.Play("Error", 0.7)
		UIUtil.Shake(button)
		-- Petit rappel (pas plus d'une fois toutes les 3 s)
		if currentInfo and not isAvailable() and os.clock() - lastRefusal > 3 then
			lastRefusal = os.clock()
			Notifications.Toast(
				Locale.T("Already claimed today! Next gift in %s.", NumberFormatter.Time(remainingSeconds())),
				Theme.Colors.Orange,
				3
			)
		end
		return
	end

	-- Carte et montant du jour AVANT l'appel (l'état change pendant)
	local info = currentInfo
	local todayIndex = math.clamp(math.floor(tonumber(info and info.Streak) or 1), 1, DAYS)
	local card = cards[todayIndex]
	local expected = tonumber(info and info.Reward) or 0

	claiming = true
	setButton("busy")
	SoundManager.Play("Click", 1.1)
	local ok, success, message = pcall(function()
		return Net.Function("ClaimDaily"):InvokeServer()
	end)

	if ok and success then
		celebrating = true
		claiming = false
		-- Montant exact : état reçu après la récupération (même série, mêmes stats)
		local after = latestData and latestData.Daily
		local amount = expected
		if type(after) == "table" and after.Available ~= true and tonumber(after.Reward) then
			amount = tonumber(after.Reward) :: number
		end
		task.spawn(function()
			local done, err = pcall(claimSequence, card, amount, tostring(message or ""))
			if not done then
				warn("[Daily] Erreur pendant l'animation : " .. tostring(err))
			end
			-- Remise à zéro (même si l'animation a été interrompue)
			heroGift.Lid.Position = heroGift.LidBase
			heroGift.Lid.Rotation = 0
			heroGift.Frame.Rotation = 0
			if card then
				card.Busy = false
				card.State = "" -- force le redessin complet de la carte
			end
			celebrating = false
			apply(latestData or ClientState.Data)
		end)
	else
		claiming = false
		SoundManager.Play("Error", 0.7)
		Notifications.Toast(
			ok and tostring(message or Locale.T("Not possible right now.")) or Locale.T("Network error, try again."),
			Theme.Colors.Red
		)
		apply(latestData or ClientState.Data)
	end
end

----------------------------------------------------------------------
-- Animations (fenêtre ouverte seulement)
----------------------------------------------------------------------

local function stopAnimation()
	local connection = animation
	if connection then
		connection:Disconnect()
		animation = nil
	end
end

local function resetButtonPulse()
	if buttonPulsing then
		buttonPulsing = false
		button.Size = UDim2.fromOffset(BUTTON_SIZE.X, BUTTON_SIZE.Y)
		buttonGlow.Visible = false
		shine.Visible = false
	end
end

local function animate(dt: number)
	if not contentFrame.Parent then
		stopAnimation()
		return
	end
	local t = os.clock() - animStart
	local available = isAvailable()

	-- En-tête
	heroRays.Rotation = (heroRays.Rotation + dt * (available and 24 or 8)) % 360
	heroHalo.BackgroundTransparency = available and (0.7 + 0.12 * math.sin(t * 4)) or 0.84
	for _, star in ipairs(sparkles) do
		local phase = star:GetAttribute("Phase") or 0
		star.TextTransparency = 0.15 + 0.7 * (0.5 + 0.5 * math.sin(t * 2.5 + phase))
	end
	if not celebrating then
		local gift = heroGift.Frame
		if available then
			gift.Rotation = wiggle(t)
			gift.Position = HERO_GIFT_POS + UDim2.fromOffset(0, -math.abs(math.sin(t * 3)) * 5)
		else
			gift.Rotation = math.sin(t * 1.4) * 3
			gift.Position = HERO_GIFT_POS + UDim2.fromOffset(0, math.sin(t * 2) * 3)
		end
	end
	refreshRing(t)

	-- Cartes
	for _, card in ipairs(cards) do
		local rays = card.Rays
		if rays and rays.Visible then
			rays.Rotation = (rays.Rotation + dt * 25) % 360
		end
		if not card.Busy then
			local diamond, base = card.Art.Diamond, card.Art.DiamondBase
			if diamond and base then
				diamond.Position = base + UDim2.fromOffset(0, math.sin(t * 2.2) * 3)
				diamond.Rotation = math.sin(t * 1.6) * 6
			end
			if card.State == "today" then
				card.Card.Position = UDim2.fromOffset(0, -math.abs(math.sin(t * 3.2)) * 6)
				card.Art.Frame.Rotation = wiggle(t + 0.35)
				card.Glow.BackgroundTransparency = 0.3 + 0.35 * (0.5 + 0.5 * math.sin(t * 4))
				card.Shimmer.Rotation = (t * 140) % 360
			elseif card.Big and card.State ~= "claimed" then
				card.Glow.BackgroundTransparency = 0.74 + 0.12 * math.sin(t * 2)
			end
		end
	end

	-- Flamme de la jauge
	flameTip.Rotation = math.sin(t * 9) * 8
	flameScale.Scale = 1 + 0.1 * math.sin(t * 13)

	-- Bouton : pulsation, halo et reflet qui balaie
	if available and not claiming and not celebrating then
		buttonPulsing = true
		local pulse = 1 + 0.03 * math.sin(t * 4.5)
		button.Size = UDim2.fromOffset(BUTTON_SIZE.X * pulse, BUTTON_SIZE.Y * pulse)
		buttonGlow.Visible = true
		buttonGlow.BackgroundTransparency = 0.6 + 0.25 * math.sin(t * 4.5)
		local sweep = (t % 2.6) / 0.75
		shine.Visible = sweep < 1
		shine.Position = UDim2.fromScale(-0.2 + 1.4 * math.min(sweep, 1), 0.5)
	else
		resetButtonPulse()
	end

	-- Textes du compte à rebours (4 fois par seconde)
	textClock += dt
	if textClock >= 0.25 then
		textClock = 0
		if not celebrating then
			refreshTimers()
		end
	end
end

----------------------------------------------------------------------
-- API du panneau
----------------------------------------------------------------------

function Daily.Build(content: Frame)
	contentFrame = content
	buildHero(content)

	local row = UIUtil.Create("Frame", {
		Name = "Days",
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		Position = UDim2.fromOffset(0, CARDS_Y),
		BackgroundTransparency = 1,
		Parent = content,
	})
	for day = 1, DAYS do
		cards[day] = buildCard(row, day)
	end

	buildMeter(content)

	amountCaption = UIUtil.Label({
		Name = "AmountCaption",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, AMOUNT_Y),
		MaxTextSize = 13,
		Parent = content,
	})
	amountLabel = UIUtil.Label({
		Name = "Amount",
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = PINK_DARK,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, AMOUNT_Y + 16),
		MaxTextSize = 34,
		Parent = content,
	})

	buildButton(content)
	button.Activated:Connect(onClaim)

	hintLabel = UIUtil.Label({
		Name = "Hint",
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, HINT_Y),
		MaxTextSize = 14,
		Parent = content,
	})

	built = true
	latestData = ClientState.Data
	apply(latestData)
end

function Daily.Update(data)
	latestData = data
	-- Pendant l'appel serveur / l'animation, on garde l'affichage : l'état
	-- le plus récent est appliqué à la fin de la séquence
	if claiming or celebrating then
		return
	end
	apply(data)
end

function Daily.OnOpen()
	if not built then
		return
	end
	stopAnimation()
	animStart = os.clock()
	textClock = 0
	refreshTimers()
	animation = RunService.RenderStepped:Connect(animate)
end

function Daily.OnClose()
	stopAnimation()
	if built then
		resetButtonPulse()
	end
end

return Daily
