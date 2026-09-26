--[[
	Garden (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Garden

	🌻 Jardin de Dopamine (slot R1, 288x190 ; remplace la bourse).
	Des parterres de terre (Config.Garden.BasePlots + niveau de "Flower
	Beds") où poussent des fleurs tirées au hasard par le SERVEUR
	(GardenService) : pousse -> bouton -> fleur épanouie. Une fleur éclose
	scintille : on la touche pour la cueillir (+X qui éclate, pétales), puis
	un nouveau bulbe est planté tout seul.
	  - ciel dégradé, soleil qui tourne, nuages qui dérivent, colline ;
	  - 2 papillons dessinés (ailes qui battent), un arrosoir qui passe
	    arroser les fleurs qui poussent (pour le plaisir : ça n'accélère rien) ;
	  - minuteur + jauge sous chaque parterre, "PRÊT !" quand c'est éclos ;
	  - bouton "Tout cueillir" dès que 2 fleurs ou plus sont prêtes.
	Données : State.Data.Garden = { Plots = { { Flower, PlantedAt, ReadyAt } }, Now }
	(dates du serveur ; le client ne fait qu'extrapoler l'heure du serveur).
	RemoteFunction "Garden" : ("harvest", index) / ("harvestAll").
]]

local Garden = {}
Garden.Slot = "R1"

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

-- Dimensions (pixels "design") : rentrées de 2 px (contour jamais coupé)
local W = 284
local H = 186

-- Parterre dessiné à cette taille "de base", puis mis à l'échelle (UIScale)
local PW, PH = 64, 76
local SOIL_Y = 46 -- haut du bac en bois dans un parterre
local SOIL_H = 16
local CHIP_Y = 64 -- minuteur
local CHIP_H = 12
local BASE_Y = SOIL_Y + 2 -- pied de la plante (dans la butte de terre)
local HEADER_H = 30
local MAX_DROPS = 8
local MAX_SPARKS = 3

local WHITE = Color3.new(1, 1, 1)
local SKY_TOP = Color3.fromRGB(150, 214, 255)
local SKY_BOTTOM = Color3.fromRGB(226, 247, 255)
local GRASS_TOP = Color3.fromRGB(128, 214, 96)
local GRASS_BOTTOM = Color3.fromRGB(64, 160, 70)
local SOIL_TOP = Color3.fromRGB(128, 82, 48)
local SOIL_BOTTOM = Color3.fromRGB(78, 44, 22)
local WOOD = Color3.fromRGB(150, 96, 52)
local WOOD_DARK = Color3.fromRGB(92, 54, 24)
local STEM = Color3.fromRGB(70, 170, 70)
local LEAF = Color3.fromRGB(96, 200, 90)
local GOLD = Color3.fromRGB(255, 205, 60)

-- Couleur des pétales (bouton, halo, pétales qui volent) par fleur
local PETALS = {
	Daisy = Color3.fromRGB(255, 250, 240),
	Tulip = Color3.fromRGB(255, 110, 160),
	Rose = Color3.fromRGB(235, 40, 70),
	Sunflower = Color3.fromRGB(255, 200, 30),
	Lotus = Color3.fromRGB(255, 190, 90),
}
local DEFAULT_PETAL = Color3.fromRGB(255, 150, 200)

local function clockText(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return string.format("%dh%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Garden.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local Format = ctx.Format
	local config = ctx.Config.Garden
	local container: Frame = ctx.Container
	local random = Random.new()

	local flowersById = {}
	for _, flower in ipairs(config.Flowers) do
		flowersById[flower.Id] = flower
	end

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function isVisible(): boolean
		local fn = ctx.IsVisible
		if type(fn) == "function" then
			local ok, result = pcall(fn)
			return not ok or result ~= false
		end
		return true
	end

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

	------------------------------------------------------------------
	-- Carte : ciel, soleil, nuages, colline
	------------------------------------------------------------------
	local card = frame({
		Name = "Garden",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = container,
	})
	round(card, 18)
	vGradient(card, { { 0, SKY_TOP }, { 0.6, SKY_BOTTOM }, { 1, SKY_BOTTOM } })
	-- Contour "bois" (en dehors de la carte : jamais coupé)
	local border = frame({
		Size = UDim2.fromOffset(W, H),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 60,
		Parent = container,
	})
	round(border, 18)
	local borderStroke = UIUtil.Stroke(border, WHITE, 2, 0)
	vGradient(borderStroke, { { 0, Color3.fromRGB(170, 116, 64) }, { 1, WOOD_DARK } })

	-- Soleil (rayons qui tournent lentement)
	local sunRays = UIUtil.Rays(card, Color3.fromRGB(255, 236, 140), 7, 92, UDim2.fromOffset(W - 30, 22), 1)
	local sun = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W - 30, 22),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = card,
	})
	round(sun)
	vGradient(sun, { { 0, Color3.fromRGB(255, 250, 190) }, { 1, Color3.fromRGB(255, 196, 40) } }, 45)
	UIUtil.Stroke(sun, Color3.fromRGB(255, 220, 90), 3, 0.55)

	-- Nuages (3 boules chacun), qui dérivent vers la droite
	local clouds = {}
	for c = 1, 2 do
		local cloud = frame({
			Position = UDim2.fromOffset(c == 1 and 60 or 170, c == 1 and 30 or 44),
			Size = UDim2.fromOffset(46, 18),
			ZIndex = 2,
			Parent = card,
		})
		for _, puff in ipairs({ { 0, 6, 20, 12 }, { 10, 0, 22, 18 }, { 24, 4, 22, 14 } }) do
			local ball = frame({
				Position = UDim2.fromOffset(puff[1], puff[2]),
				Size = UDim2.fromOffset(puff[3], puff[4]),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.1,
				ZIndex = 2,
				Parent = cloud,
			})
			round(ball)
		end
		local scale = Create("UIScale", { Scale = c == 1 and 0.9 or 0.7, Parent = cloud })
		clouds[c] = { Frame = cloud, X = c == 1 and 60 or 170, Y = c == 1 and 30 or 46, Speed = c == 1 and 5 or 3.2, Scale = scale }
	end

	-- Colline (grand ovale) : sa position dépend de la disposition des parterres.
	-- ClipsDescendants ne suit pas les coins arrondis : la colline est coupée
	-- au-dessus des coins du bas, et une bande arrondie fait le bas de la carte.
	local ground = frame({
		Name = "GroundBottom",
		Position = UDim2.fromOffset(0, H - 44),
		Size = UDim2.fromOffset(W, 44),
		BackgroundColor3 = GRASS_BOTTOM,
		ZIndex = 2,
		Parent = card,
	})
	round(ground, 18)
	local hillClip = frame({
		Name = "HillClip",
		Size = UDim2.fromOffset(W, H - 18),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = card,
	})
	local hillBack = frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.25, 0, 0, 70),
		Size = UDim2.fromOffset(W * 1.1, 300),
		BackgroundColor3 = Color3.fromRGB(160, 222, 120),
		ZIndex = 2,
		Parent = hillClip,
	})
	round(hillBack)
	local hill = frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(W * 1.8, 400),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = hillClip,
	})
	round(hill)
	vGradient(hill, { { 0, GRASS_TOP }, { 0.11, GRASS_BOTTOM }, { 1, GRASS_BOTTOM } })
	-- Palissade blanche au fond (seulement avec une rangée de parterres)
	local fence = frame({ Name = "Fence", Size = UDim2.fromOffset(W, 18), Visible = false, ZIndex = 4, Parent = card })
	for rail = 0, 1 do
		frame({
			Position = UDim2.fromOffset(0, 5 + rail * 7),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = Color3.fromRGB(235, 232, 225),
			ZIndex = 4,
			Parent = fence,
		})
	end
	for k = 0, math.floor(W / 12) do
		local picket = frame({
			Position = UDim2.fromOffset(3 + k * 12, 0),
			Size = UDim2.fromOffset(5, 18),
			BackgroundColor3 = WHITE,
			ZIndex = 4,
			Parent = fence,
		})
		UIUtil.Corner(picket, UDim.new(0, 2))
		UIUtil.Stroke(picket, Color3.fromRGB(190, 180, 170), 1, 0.3)
	end

	-- Touffes d'herbe et petites fleurs sauvages sur la colline (placées par layoutPlots)
	local tufts = {}
	for t = 1, 7 do
		local tuft = frame({ Size = UDim2.fromOffset(10, 8), ZIndex = 4, Parent = hillClip })
		for blade = -1, 1 do
			local bar = frame({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, blade * 3, 1, 0),
				Size = UDim2.fromOffset(2, blade == 0 and 8 or 6),
				Rotation = blade * 22,
				BackgroundColor3 = Color3.fromRGB(46, 130, 50),
				ZIndex = 4,
				Parent = tuft,
			})
			round(bar, 1)
		end
		if t % 3 == 0 then
			local bloom = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.fromOffset(4, 4),
				BackgroundColor3 = t % 2 == 0 and WHITE or Color3.fromRGB(255, 230, 90),
				ZIndex = 5,
				Parent = tuft,
			})
			round(bloom)
		end
		table.insert(tufts, tuft)
	end

	------------------------------------------------------------------
	-- En-tête : pancarte en bois + bouton "Tout cueillir" / prochain éclos
	------------------------------------------------------------------
	local sign = frame({
		Name = "Sign",
		Position = UDim2.fromOffset(7, 6),
		Size = UDim2.fromOffset(150, 21),
		BackgroundColor3 = WHITE,
		ZIndex = 20,
		Parent = card,
	})
	round(sign, 7)
	vGradient(sign, { { 0, Color3.fromRGB(196, 136, 78) }, { 1, WOOD } })
	UIUtil.Stroke(sign, WOOD_DARK, 1.5, 0)
	-- Veines du bois
	for v = 1, 2 do
		frame({
			Position = UDim2.fromOffset(8, 6 + (v - 1) * 8),
			Size = UDim2.new(1, -16, 0, 1),
			BackgroundColor3 = WOOD_DARK,
			BackgroundTransparency = 0.75,
			ZIndex = 20,
			Parent = sign,
		})
	end
	for side = 0, 1 do
		local nail = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(side, side == 0 and 5 or -5, 0.5, 0),
			Size = UDim2.fromOffset(3, 3),
			BackgroundColor3 = Color3.fromRGB(70, 50, 40),
			ZIndex = 21,
			Parent = sign,
		})
		round(nail)
	end
	local title = UIUtil.Label({
		Text = "🌻 " .. Locale.T("Dopamine Garden"),
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(255, 248, 225),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -16, 0, 16),
		MaxTextSize = 14,
		ZIndex = 22,
		Parent = sign,
	})
	local titleStroke = UIUtil.Stroke(title, WOOD_DARK, 1.2, 0)
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Pastille à droite : prochain éclos / "Tout cueillir"
	local pill = Create("TextButton", {
		Name = "GardenHarvestAll",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(W - 7, 7),
		Size = UDim2.fromOffset(104, 19),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 20,
		Parent = card,
	})
	round(pill)
	local pillGradient = vGradient(pill, { { 0, Color3.fromRGB(255, 255, 255) }, { 1, Color3.fromRGB(226, 240, 250) } })
	local pillStroke = UIUtil.Stroke(pill, Color3.fromRGB(80, 130, 90), 1.5, 0)
	local pillLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(40, 90, 50),
		Size = UDim2.new(1, -10, 1, -4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 12,
		ZIndex = 21,
		Parent = pill,
	})
	local pillScale = Create("UIScale", { Parent = pill })
	UIUtil.AnimateButton(pill, 1.05, 0.94)

	------------------------------------------------------------------
	-- Arrosoir (dessiné) + gouttes (réserve réutilisée)
	------------------------------------------------------------------
	local can = frame({
		Name = "WateringCan",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(176, 16),
		Size = UDim2.fromOffset(34, 24),
		ZIndex = 30,
		Parent = card,
	})
	local canHandle = frame({
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.fromOffset(14, 13),
		ZIndex = 30,
		Parent = can,
	})
	round(canHandle)
	UIUtil.Stroke(canHandle, Color3.fromRGB(30, 120, 140), 2.5, 0)
	local canSpout = frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(22, 15),
		Size = UDim2.fromOffset(13, 3),
		Rotation = -35,
		BackgroundColor3 = Color3.fromRGB(40, 150, 170),
		ZIndex = 30,
		Parent = can,
	})
	round(canSpout, 1)
	local canRose = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(33, 7),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.fromRGB(30, 120, 140),
		ZIndex = 31,
		Parent = can,
	})
	round(canRose)
	local canBody = frame({
		Position = UDim2.fromOffset(3, 8),
		Size = UDim2.fromOffset(21, 15),
		BackgroundColor3 = WHITE,
		ZIndex = 31,
		Parent = can,
	})
	round(canBody, 5)
	vGradient(canBody, { { 0, Color3.fromRGB(110, 220, 230) }, { 1, Color3.fromRGB(30, 150, 170) } }, 0)
	UIUtil.Stroke(canBody, Color3.fromRGB(20, 100, 120), 1, 0.1)
	frame({
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Color3.fromRGB(255, 220, 90),
		ZIndex = 32,
		Parent = canBody,
	})
	local canShine = frame({
		Position = UDim2.fromOffset(3, 2),
		Size = UDim2.fromOffset(4, 10),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.45,
		ZIndex = 32,
		Parent = canBody,
	})
	round(canShine)

	local drops = {}
	for _ = 1, MAX_DROPS do
		local drop = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(3, 5),
			BackgroundColor3 = Color3.fromRGB(90, 180, 255),
			BackgroundTransparency = 0.1,
			Visible = false,
			ZIndex = 29,
			Parent = card,
		})
		round(drop)
		table.insert(drops, { Frame = drop, Active = false, X = 0, Y = 0, VY = 0, Floor = 0 })
	end
	local activeDrops = 0

	-- État de l'arrosoir : "rest" | "fly" | "pour" | "back"
	local CAN_REST = Vector2.new(W + 30, 60) -- hors de la carte (recalculé par layoutPlots)
	local canState = {
		Mode = "rest",
		From = CAN_REST,
		To = CAN_REST,
		T = 0,
		Dur = 1,
		Pour = 0,
		Pos = CAN_REST,
		Tilt = 0,
		Target = 0, -- index du parterre arrosé
		Next = 4, -- secondes avant la prochaine tournée
	}

	------------------------------------------------------------------
	-- Papillons (dessinés : 2 ailes qui battent + corps)
	------------------------------------------------------------------
	local butterflies = {}
	local BUTTERFLY_COLORS = {
		{ Color3.fromRGB(255, 140, 200), Color3.fromRGB(255, 220, 120) },
		{ Color3.fromRGB(120, 170, 255), Color3.fromRGB(255, 255, 255) },
	}
	for b = 1, 2 do
		local holder = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(20, 16),
			ZIndex = 40,
			Parent = card,
		})
		local wings = {}
		for side = -1, 1, 2 do
			local wing = frame({
				AnchorPoint = Vector2.new(side == -1 and 1 or 0, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, -1),
				Size = UDim2.fromOffset(9, 11),
				BackgroundColor3 = BUTTERFLY_COLORS[b][1],
				ZIndex = 40,
				Parent = holder,
			})
			round(wing)
			UIUtil.Stroke(wing, Color3.fromRGB(80, 40, 70), 1, 0.3)
			local spot = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.4),
				Size = UDim2.fromScale(0.45, 0.35),
				BackgroundColor3 = BUTTERFLY_COLORS[b][2],
				ZIndex = 41,
				Parent = wing,
			})
			round(spot)
			local lower = frame({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0.75, 0),
				Size = UDim2.fromScale(0.7, 0.55),
				BackgroundColor3 = BUTTERFLY_COLORS[b][1]:Lerp(Color3.new(0, 0, 0), 0.12),
				ZIndex = 39,
				Parent = wing,
			})
			round(lower)
			table.insert(wings, wing)
		end
		local body = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(3, 11),
			BackgroundColor3 = Color3.fromRGB(60, 40, 50),
			ZIndex = 42,
			Parent = holder,
		})
		round(body)
		table.insert(butterflies, {
			Frame = holder,
			Wings = wings,
			Phase = random:NextNumber(0, math.pi * 2),
			Speed = b == 1 and 0.23 or 0.17,
			Flap = b == 1 and 15 or 12,
			CX = b == 1 and 90 or 200,
			CY = b == 1 and 70 or 100,
			LastX = 0,
		})
	end

	------------------------------------------------------------------
	-- Bulle d'info (une seule, réutilisée)
	------------------------------------------------------------------
	local bubble = frame({
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(130, 18),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 50,
		Parent = card,
	})
	round(bubble, 8)
	UIUtil.Stroke(bubble, Color3.fromRGB(70, 120, 80), 1.5, 0)
	local bubbleLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(40, 80, 50),
		Size = UDim2.new(1, -8, 1, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 11,
		ZIndex = 51,
		Parent = bubble,
	})
	local bubbleScale = Create("UIScale", { Parent = bubble })
	local bubbleUntil = 0

	local function showBubble(point: Vector2, text: string, bad: boolean?)
		bubbleLabel.Text = text
		bubbleLabel.TextColor3 = bad and Color3.fromRGB(170, 40, 40) or Color3.fromRGB(40, 80, 50)
		local x = math.clamp(point.X, 68, W - 68)
		bubble.Position = UDim2.fromOffset(x, math.max(20, point.Y))
		bubble.Visible = true
		bubbleScale.Scale = 0.5
		UIUtil.Tween(bubbleScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		bubbleUntil = os.clock() + 1.8
	end

	------------------------------------------------------------------
	-- Heure du serveur (extrapolée) et données
	------------------------------------------------------------------
	local serverOffset: number? = nil -- heure serveur = os.clock() + serverOffset
	local function serverNow(): number
		return os.clock() + (serverOffset or 0)
	end
	local function syncClock(now: any)
		now = tonumber(now)
		if not now then
			return
		end
		local offset = now - os.clock()
		-- Now est arrondi à la seconde inférieure (et arrive avec du retard) :
		-- la meilleure estimation est la plus grande, sauf gros écart
		if serverOffset == nil or offset > serverOffset or serverOffset - offset > 3 then
			serverOffset = offset
		end
	end

	------------------------------------------------------------------
	-- Parterres
	------------------------------------------------------------------
	type Plot = {
		Index: number,
		Holder: Frame,
		Scale: UIScale,
		Button: TextButton,
		Plant: Frame,
		PlantScale: UIScale,
		Stem: Frame,
		Leaves: { Frame },
		Bud: Frame,
		BudScale: UIScale,
		Head: TextLabel,
		HeadScale: UIScale,
		Halo: Frame,
		Sparks: { { Frame: Frame, Bars: { Frame } } },
		Chip: Frame,
		ChipFill: Frame,
		ChipLabel: TextLabel,
		Flower: string,
		PlantedAt: number,
		ReadyAt: number,
		Stage: string,
		Ripe: boolean,
		Pending: boolean,
		Sway: number,
		Popping: boolean,
	}
	local plots: { Plot } = {}
	local layoutCount = -1
	local plantBoost = 1 -- échelle des plantes (plus grandes s'il y a de la place)
	local plotArea = Instance.new("Frame")
	plotArea.Name = "Beds"
	plotArea.BackgroundTransparency = 1
	plotArea.BorderSizePixel = 0
	plotArea.Size = UDim2.fromScale(1, 1)
	plotArea.ZIndex = 5
	plotArea.Parent = card

	local function buildPlot(index: number): Plot
		local holder = frame({
			Name = "Plot" .. index,
			Size = UDim2.fromOffset(PW, PH),
			ZIndex = 5,
			Parent = plotArea,
		})
		local scale = Create("UIScale", { Parent = holder })

		-- Ombre au sol
		local shadow = frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(PW / 2, SOIL_Y + SOIL_H - 3),
			Size = UDim2.fromOffset(PW + 2, 7),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.78,
			ZIndex = 5,
			Parent = holder,
		})
		round(shadow)
		-- Butte de terre (derrière la planche)
		local soil = frame({
			Name = "Soil",
			Position = UDim2.fromOffset(5, SOIL_Y - 3),
			Size = UDim2.fromOffset(PW - 10, 13),
			BackgroundColor3 = WHITE,
			ZIndex = 6,
			Parent = holder,
		})
		round(soil)
		vGradient(soil, { { 0, SOIL_TOP }, { 1, SOIL_BOTTOM } })
		for p = 1, 4 do
			local pebble = frame({
				Position = UDim2.fromOffset(7 + (p - 1) * 11 + (p % 2) * 3, 3 + (p % 2) * 2),
				Size = UDim2.fromOffset(3 + p % 2, 2),
				BackgroundColor3 = Color3.fromRGB(56, 30, 14),
				BackgroundTransparency = 0.3,
				ZIndex = 6,
				Parent = soil,
			})
			round(pebble)
		end
		-- Planche avant du bac en bois (2 lattes, clous)
		local board = frame({
			Name = "Board",
			Position = UDim2.fromOffset(2, SOIL_Y + 4),
			Size = UDim2.fromOffset(PW - 4, SOIL_H - 4),
			BackgroundColor3 = WHITE,
			ZIndex = 7,
			Parent = holder,
		})
		round(board, 3)
		vGradient(board, { { 0, Color3.fromRGB(214, 150, 88) }, { 0.5, WOOD }, { 1, Color3.fromRGB(120, 72, 36) } })
		UIUtil.Stroke(board, WOOD_DARK, 1.2, 0)
		frame({
			Position = UDim2.new(0, 2, 0.5, 0),
			Size = UDim2.new(1, -4, 0, 1),
			BackgroundColor3 = WOOD_DARK,
			BackgroundTransparency = 0.45,
			ZIndex = 7,
			Parent = board,
		})
		for k = 1, 2 do
			frame({
				Position = UDim2.new(k / 3, 0, 0, 1),
				Size = UDim2.new(0, 1, 1, -2),
				BackgroundColor3 = WOOD_DARK,
				BackgroundTransparency = 0.55,
				ZIndex = 7,
				Parent = board,
			})
		end
		for side = 0, 1 do
			local nail = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(side, side == 0 and 4 or -4, 0.5, 0),
				Size = UDim2.fromOffset(2, 2),
				BackgroundColor3 = Color3.fromRGB(70, 50, 40),
				ZIndex = 7,
				Parent = board,
			})
			round(nail)
		end

		-- Plante : cadre 2x plus haut, centré sur le pied (la rotation se fait autour du pied)
		local plant = frame({
			Name = "Plant",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(PW / 2, BASE_Y),
			Size = UDim2.fromOffset(48, 96),
			ZIndex = 8,
			Parent = holder,
		})
		local halo = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -34),
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = GOLD,
			BackgroundTransparency = 1,
			ZIndex = 8,
			Parent = plant,
		})
		round(halo)
		fade(halo, { { 0, 0.1 }, { 0.6, 0.6 }, { 1, 1 } }, 0)
		local stem = frame({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.fromOffset(3, 10),
			BackgroundColor3 = WHITE,
			ZIndex = 9,
			Parent = plant,
		})
		round(stem, 2)
		UIUtil.Gradient(stem, ColorSequence.new(STEM:Lerp(WHITE, 0.2), STEM:Lerp(Color3.new(0, 0, 0), 0.2)), 0)
		local leaves = {}
		for side = -1, 1, 2 do
			local leaf = frame({
				AnchorPoint = Vector2.new(side == -1 and 1 or 0, 0.5),
				Size = UDim2.fromOffset(11, 5),
				Rotation = side * -28,
				BackgroundColor3 = WHITE,
				ZIndex = 9,
				Parent = plant,
			})
			round(leaf)
			UIUtil.Gradient(leaf, ColorSequence.new(LEAF:Lerp(WHITE, 0.25), LEAF:Lerp(Color3.new(0, 0, 0), 0.15)), 90)
			table.insert(leaves, leaf)
		end
		-- Bouton floral (dessiné) avec ses sépales
		local bud = frame({
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(10, 13),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 10,
			Parent = plant,
		})
		round(bud)
		for side = -1, 1, 2 do
			local sepal = frame({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, side * 3, 1, 1),
				Size = UDim2.fromOffset(5, 7),
				Rotation = side * 25,
				BackgroundColor3 = STEM,
				ZIndex = 11,
				Parent = bud,
			})
			round(sepal)
		end
		local budScale = Create("UIScale", { Parent = bud })
		-- Fleur épanouie (emoji de Config.Garden)
		local head = UIUtil.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(34, 34),
			Text = "",
			Font = Theme.Fonts.Title,
			MaxTextSize = 30,
			Visible = false,
			ZIndex = 11,
			Parent = plant,
		})
		local headScale = Create("UIScale", { Parent = head })
		-- Étincelles : petites croix lumineuses (2 barres) qui tournent autour de la fleur
		local sparks = {}
		for s = 1, MAX_SPARKS do
			local spark = frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(9, 9),
				Visible = false,
				ZIndex = 12,
				Parent = plant,
			})
			local color = s == 2 and WHITE or Color3.fromRGB(255, 240, 150)
			local bars = {}
			for b = 0, 1 do
				local bar = frame({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = b == 0 and UDim2.new(0, 1.5, 1, 0) or UDim2.new(1, 0, 0, 1.5),
					BackgroundColor3 = color,
					ZIndex = 12,
					Parent = spark,
				})
				round(bar, 1)
				table.insert(bars, bar)
			end
			table.insert(sparks, { Frame = spark, Bars = bars })
		end

		-- Minuteur (pastille + jauge)
		local chip = frame({
			Name = "Timer",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(PW / 2, CHIP_Y),
			Size = UDim2.fromOffset(PW - 8, CHIP_H),
			BackgroundColor3 = Color3.fromRGB(40, 60, 40),
			BackgroundTransparency = 0.25,
			ClipsDescendants = true,
			ZIndex = 12,
			Parent = holder,
		})
		round(chip)
		local chipFill = frame({
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.fromRGB(110, 210, 100),
			BackgroundTransparency = 0.25,
			ZIndex = 12,
			Parent = chip,
		})
		round(chipFill)
		local chipLabel = UIUtil.Label({
			Text = "",
			Font = Theme.Fonts.Number,
			TextColor3 = WHITE,
			Size = UDim2.new(1, -4, 1, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 10,
			ZIndex = 13,
			Parent = chip,
		})

		local button = Create("TextButton", {
			Name = "GardenPlot" .. index,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 20,
			Parent = holder,
		})

		return {
			Index = index,
			Holder = holder,
			Scale = scale,
			Button = button,
			Plant = plant,
			PlantScale = Create("UIScale", { Parent = plant }),
			Stem = stem,
			Leaves = leaves,
			Bud = bud,
			BudScale = budScale,
			Head = head,
			HeadScale = headScale,
			Halo = halo,
			Sparks = sparks,
			Chip = chip,
			ChipFill = chipFill,
			ChipLabel = chipLabel,
			Flower = "",
			PlantedAt = 0,
			ReadyAt = 0,
			Stage = "",
			Ripe = false,
			Pending = false,
			Sway = random:NextNumber(0, math.pi * 2),
			Popping = false,
		}
	end

	-- Centre (dans la carte) d'un point du parterre (coordonnées "de base")
	local function plotPoint(plot: Plot, x: number, y: number): Vector2
		local s = plot.Scale.Scale
		local pos = plot.Holder.Position
		return Vector2.new(pos.X.Offset + x * s, pos.Y.Offset + y * s)
	end

	-- Hauteur de la tête de la plante au-dessus du pied selon la pousse (0..1)
	local function stemHeight(progress: number, ripe: boolean): number
		if ripe then
			return 28
		elseif progress < 0.4 then
			return 5 + 13 * (progress / 0.4)
		end
		return 18 + 8 * ((progress - 0.4) / 0.6)
	end

	-- Met à jour le dessin de la plante (appelé 4 fois / s et à chaque changement)
	local function drawPlant(plot: Plot, progress: number, ripe: boolean)
		local flower = flowersById[plot.Flower]
		local petal = PETALS[plot.Flower] or DEFAULT_PETAL
		local stage = ripe and "bloom" or (progress < 0.4 and "sprout" or "bud")
		local height = stemHeight(progress, ripe)
		local centerY = 48 -- pied de la plante dans le cadre "Plant" (96 de haut)
		plot.Stem.Size = UDim2.fromOffset(stage == "sprout" and 2 or 3, height)
		-- Feuilles : en haut pour une pousse (cotylédons), à mi-hauteur ensuite
		local leafY = stage == "sprout" and (centerY - height + 2) or (centerY - height * 0.45)
		local leafScale = stage == "sprout" and (0.7 + 0.3 * math.min(1, progress / 0.4)) or 1
		for i, leaf in ipairs(plot.Leaves) do
			local side = i == 1 and -1 or 1
			leaf.Position = UDim2.new(0.5, side * 1, 0, leafY)
			leaf.Size = UDim2.fromOffset(math.floor(11 * leafScale + 0.5), math.max(3, math.floor(5 * leafScale + 0.5)))
		end
		if stage ~= plot.Stage then
			plot.Stage = stage
			plot.Bud.Visible = stage == "bud"
			plot.Head.Visible = stage == "bloom"
			plot.Bud.BackgroundColor3 = petal
			if stage == "bloom" then
				plot.Head.Text = flower and flower.Icon or "🌸"
				plot.Halo.BackgroundColor3 = petal:Lerp(GOLD, 0.5)
				plot.Halo.BackgroundTransparency = 0.35
				plot.HeadScale.Scale = 0.3
				UIUtil.Tween(plot.HeadScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			else
				plot.Halo.BackgroundTransparency = 1
			end
			for _, spark in ipairs(plot.Sparks) do
				spark.Frame.Visible = stage == "bloom"
			end
		end
		if stage == "bud" then
			local open = (progress - 0.4) / 0.6
			plot.Bud.Position = UDim2.new(0.5, 0, 0, centerY - height + 3)
			plot.BudScale.Scale = 0.65 + 0.45 * open
		elseif stage == "bloom" then
			plot.Head.Position = UDim2.new(0.5, 0, 0, centerY - height - 4)
			plot.Halo.Position = UDim2.new(0.5, 0, 0, centerY - height - 4)
		end
	end

	-- Minuteur + jauge + dessin d'un parterre (4 fois / s)
	local function refreshPlot(plot: Plot, now: number)
		if plot.Flower == "" then
			return
		end
		local total = math.max(1, plot.ReadyAt - plot.PlantedAt)
		local remaining = plot.ReadyAt - now
		local ripe = remaining <= 0
		local progress = math.clamp(1 - remaining / total, 0, 1)
		plot.Ripe = ripe
		if not plot.Popping then
			drawPlant(plot, progress, ripe)
		end
		if ripe then
			plot.ChipFill.Size = UDim2.fromScale(1, 1)
			plot.ChipFill.BackgroundColor3 = GOLD
			plot.ChipFill.BackgroundTransparency = 0
			plot.ChipLabel.Text = Locale.T("READY!")
			plot.ChipLabel.TextColor3 = Color3.fromRGB(110, 60, 0)
		else
			plot.ChipFill.Size = UDim2.fromScale(progress, 1)
			plot.ChipFill.BackgroundColor3 = Color3.fromRGB(110, 210, 100)
			plot.ChipFill.BackgroundTransparency = 0.25
			plot.ChipLabel.Text = "⏱ " .. clockText(remaining)
			plot.ChipLabel.TextColor3 = WHITE
		end
	end

	-- Dispose les parterres selon leur nombre (1 ou 2 rangées)
	local function layoutPlots(count: number)
		local top = HEADER_H + 2
		local areaW = W - 12
		local areaH = H - top - 4
		local rows = count <= 4 and 1 or 2
		local cols = math.ceil(count / rows)
		local gap = 4
		local cellW = (areaW - gap * (cols - 1)) / cols
		local cellH = (areaH - gap * (rows - 1)) / rows
		local scale = math.min(cellW / PW, cellH / PH, 1.45)
		local plotW, plotH = PW * scale, PH * scale
		-- Une seule rangée avec des parterres étroits : il reste du ciel, les plantes poussent plus haut
		plantBoost = rows == 1 and math.clamp(1.35 / scale, 1, 1.35) or 1
		for index, plot in ipairs(plots) do
			local row = math.floor((index - 1) / cols)
			local col = (index - 1) % cols
			local inRow = math.min(cols, count - row * cols)
			-- Rangée incomplète : centrée
			local rowWidth = inRow * plotW + (inRow - 1) * gap
			local x0 = 6 + (areaW - rowWidth) / 2
			local y
			if rows == 1 then
				y = H - 6 - plotH -- au sol, en bas de la carte
			else
				y = top + row * (cellH + gap) + (cellH - plotH)
			end
			plot.Holder.Position = UDim2.fromOffset(x0 + col * (plotW + gap), y)
			plot.Scale.Scale = scale
			plot.PlantScale.Scale = plantBoost
		end
		-- Colline : juste derrière la première rangée de terre
		local firstY = plots[1] and plots[1].Holder.Position.Y.Offset or 90
		local hillTop = firstY + SOIL_Y * scale - (rows == 1 and 30 or 12)
		hill.Position = UDim2.new(0.5, 0, 0, hillTop)
		hillBack.Position = UDim2.new(0.22, 0, 0, hillTop - 12)
		fence.Visible = rows == 1
		fence.Position = UDim2.fromOffset(0, hillTop + 16)
		-- Touffes : entre les parterres et sur les bords
		for t, tuft in ipairs(tufts) do
			local tx = 8 + (t - 1) * (W - 26) / (#tufts - 1) + (t % 2) * 5
			local ty = rows == 1 and (hillTop + 8 + (t % 3) * 5) or (H - 26 - (t % 2) * 2)
			tuft.Position = UDim2.fromOffset(tx, ty)
			tuft.Visible = rows == 1 or t == 1 or t == #tufts
		end
		-- Arrosoir : dans le ciel s'il y a de la place, sinon il attend hors de la carte
		if rows == 1 then
			CAN_REST = Vector2.new(W * 0.56, HEADER_H + 22)
		else
			CAN_REST = Vector2.new(W + 30, 60)
		end
		if canState.Mode == "rest" then
			canState.Pos = CAN_REST
		end
	end

	local harvest -- (défini plus bas)

	local function rebuild(count: number)
		for _, plot in ipairs(plots) do
			plot.Holder:Destroy()
		end
		table.clear(plots)
		for index = 1, count do
			local plot = buildPlot(index)
			plots[index] = plot
			ctx.Connect(plot.Button.Activated, function()
				harvest(plot)
			end)
			ctx.Connect(plot.Button.MouseEnter, function()
				if plot.Ripe and not plot.Popping then
					UIUtil.Tween(plot.HeadScale, 0.15, { Scale = 1.15 }, Enum.EasingStyle.Back)
				end
			end)
			ctx.Connect(plot.Button.MouseLeave, function()
				if plot.Ripe and not plot.Popping then
					UIUtil.Tween(plot.HeadScale, 0.15, { Scale = 1 })
				end
			end)
		end
		layoutCount = count
		layoutPlots(count)
	end

	-- Applique la liste de parterres du serveur
	local function applyPlots(list: any)
		if type(list) ~= "table" then
			return
		end
		local count = #list
		if count ~= layoutCount then
			rebuild(count)
		end
		local now = serverNow()
		for index, info in ipairs(list) do
			local plot = plots[index]
			if plot and type(info) == "table" and flowersById[info.Flower] then
				local plantedAt = tonumber(info.PlantedAt) or 0
				local readyAt = tonumber(info.ReadyAt) or plantedAt
				if plot.Flower ~= info.Flower or plot.PlantedAt ~= plantedAt then
					local replanted = plot.Flower ~= ""
					plot.Flower = info.Flower
					plot.PlantedAt = plantedAt
					plot.ReadyAt = readyAt
					plot.Stage = ""
					plot.Popping = false
					plot.HeadScale.Scale = 1
					plot.Head.TextTransparency = 0
					if replanted then
						-- Nouvelle pousse : petit "pop" de terre
						plot.PlantScale.Scale = 0.2 * plantBoost
						UIUtil.Tween(plot.PlantScale, 0.35, { Scale = plantBoost }, Enum.EasingStyle.Back)
					end
				end
				refreshPlot(plot, now)
			end
		end
	end

	------------------------------------------------------------------
	-- En-tête : "Tout cueillir" ou prochain éclos
	------------------------------------------------------------------
	local ripeCount = 0
	local harvestingAll = false
	local lastPillMode = ""
	local function refreshPill(now: number)
		ripeCount = 0
		local nextIn = math.huge
		for _, plot in ipairs(plots) do
			if plot.Flower ~= "" and not plot.Popping then
				if plot.Ripe then
					ripeCount += 1
				else
					nextIn = math.min(nextIn, plot.ReadyAt - now)
				end
			end
		end
		local mode
		if ripeCount >= 2 then
			mode = "all"
			pillLabel.Text = Locale.T("🧺 Harvest all (%d)", ripeCount)
		elseif ripeCount == 1 then
			mode = "one"
			pillLabel.Text = Locale.T("🌸 Tap the flower!")
		elseif nextIn < math.huge then
			mode = "wait"
			pillLabel.Text = Locale.T("⏱ Next bloom %s", clockText(nextIn))
		else
			mode = "wait"
			pillLabel.Text = "🌱"
		end
		if mode ~= lastPillMode then
			lastPillMode = mode
			local active = mode == "all"
			pillGradient.Color = active
					and ColorSequence.new(Color3.fromRGB(150, 235, 110), Color3.fromRGB(60, 170, 70))
				or ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(226, 240, 250))
			pillStroke.Color = active and Color3.fromRGB(30, 100, 40) or Color3.fromRGB(80, 130, 90)
			pillLabel.TextColor3 = active and WHITE or Color3.fromRGB(40, 90, 50)
			if active then
				pillScale.Scale = 0.6
				UIUtil.Tween(pillScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
	end

	------------------------------------------------------------------
	-- Arrosoir : va arroser un parterre (pour le plaisir)
	------------------------------------------------------------------
	local function sendCan(target: number)
		local plot = plots[target]
		if not plot then
			return
		end
		local point = plotPoint(plot, PW / 2, SOIL_Y - 30)
		canState.Mode = "fly"
		canState.From = canState.Pos
		canState.To = Vector2.new(math.clamp(point.X - 16, 20, W - 20), math.max(HEADER_H + 4, point.Y - 6))
		canState.T = 0
		canState.Dur = 0.7
		canState.Target = target
	end

	local function spawnDrop(x: number, y: number, floor: number)
		for _, drop in ipairs(drops) do
			if not drop.Active then
				drop.Active = true
				drop.X = x + random:NextNumber(-3, 3)
				drop.Y = y
				drop.VY = random:NextNumber(30, 60)
				drop.Floor = floor
				drop.Frame.Visible = true
				activeDrops += 1
				return
			end
		end
	end

	------------------------------------------------------------------
	-- Cueillette
	------------------------------------------------------------------
	local function popPlot(plot: Plot, reward: number, flowerId: string, big: boolean?)
		local petal = PETALS[flowerId] or DEFAULT_PETAL
		local point = plotPoint(plot, PW / 2, BASE_Y - 32 * plantBoost)
		plot.Popping = true
		UIUtil.Tween(plot.HeadScale, 0.18, { Scale = 1.7 }, Enum.EasingStyle.Back)
		UIUtil.Tween(plot.Head, 0.25, { TextTransparency = 1 })
		plot.Halo.BackgroundTransparency = 1
		for _, spark in ipairs(plot.Sparks) do
			spark.Frame.Visible = false
		end
		if effectsOn() then
			ctx.Effects.Burst(card, UDim2.fromOffset(point.X, point.Y), petal, big and 14 or 9)
		end
		ctx.FloatText(card, UDim2.fromOffset(point.X, point.Y - 6), "+" .. Format.Format(reward), GOLD, big and 28 or 22)
	end

	local function applyResult(result: any)
		if type(result) ~= "table" then
			return
		end
		syncClock(result.Now)
		-- Petit délai : l'éclat de la fleur se voit avant la nouvelle pousse
		task.delay(0.3, function()
			if ctx.IsAlive() then
				applyPlots(result.Plots)
			end
		end)
	end

	harvest = function(plot: Plot)
		if plot.Pending or plot.Popping or plot.Flower == "" then
			return
		end
		local now = serverNow()
		if now < plot.ReadyAt then
			-- Pas encore : on dit combien de temps, et l'arrosoir passe
			local flower = flowersById[plot.Flower]
			local name = flower and Locale.T(flower.Name) or ""
			showBubble(plotPoint(plot, PW / 2, SOIL_Y - 30), Locale.T("%s · ready in %s", name, clockText(plot.ReadyAt - now)))
			ctx.Sound.Play("Click", 0.9)
			UIUtil.Shake(plot.Plant)
			if canState.Mode == "rest" then
				sendCan(plot.Index)
			end
			return
		end
		plot.Pending = true
		plot.HeadScale.Scale = 0.85
		task.spawn(function()
			local callOk, success, result = pcall(function()
				return ctx.Net.Function("Garden"):InvokeServer("harvest", plot.Index)
			end)
			plot.Pending = false
			if not ctx.IsAlive() then
				return
			end
			if callOk and success == true and type(result) == "table" then
				local flower = flowersById[result.Flower or plot.Flower]
				local big = flower ~= nil and flower.Weight <= 9
				ctx.Sound.Play("Pop", big and 0.9 or 1.1)
				popPlot(plot, tonumber(result.Reward) or 0, result.Flower or plot.Flower, big)
				applyResult(result)
			else
				plot.HeadScale.Scale = 1
				ctx.Sound.Play("Error", 1)
				UIUtil.Shake(plot.Holder)
				local message = (callOk and type(result) == "string") and result or Locale.T("The garden is resting 🌙")
				showBubble(plotPoint(plot, PW / 2, SOIL_Y - 30), message, true)
			end
		end)
	end

	ctx.Connect(pill.Activated, function()
		if ripeCount < 2 or harvestingAll then
			if ripeCount == 1 then
				for _, plot in ipairs(plots) do
					if plot.Ripe then
						harvest(plot)
						break
					end
				end
			end
			return
		end
		harvestingAll = true
		task.spawn(function()
			local callOk, success, result = pcall(function()
				return ctx.Net.Function("Garden"):InvokeServer("harvestAll")
			end)
			harvestingAll = false
			if not ctx.IsAlive() then
				return
			end
			if callOk and success == true and type(result) == "table" and type(result.Harvested) == "table" then
				ctx.Sound.Play("Cash", 1)
				for order, entry in ipairs(result.Harvested) do
					local plot = type(entry) == "table" and plots[tonumber(entry.Plot) or 0]
					if plot then
						task.delay((order - 1) * 0.08, function()
							if ctx.IsAlive() then
								popPlot(plot, tonumber(entry.Reward) or 0, entry.Flower or plot.Flower)
							end
						end)
					end
				end
				applyResult(result)
				task.delay(0.35, function()
					if ctx.IsAlive() then
						ctx.FloatText(card, UDim2.fromOffset(W / 2, H / 2), "🧺 +" .. Format.Format(tonumber(result.Reward) or 0), GOLD, 30)
					end
				end)
			else
				ctx.Sound.Play("Error", 1)
				UIUtil.Shake(pill)
			end
		end)
	end)

	------------------------------------------------------------------
	-- État du serveur
	------------------------------------------------------------------
	local lastGarden = nil
	local function applyState()
		local data = ctx.State.Data
		local garden = data and data.Garden
		if type(garden) ~= "table" or garden == lastGarden then
			return
		end
		lastGarden = garden
		syncClock(garden.Now)
		applyPlots(garden.Plots)
		refreshPill(serverNow())
	end
	applyState()
	ctx.Connect(ctx.State.Changed, applyState)

	------------------------------------------------------------------
	-- Animation
	------------------------------------------------------------------
	local elapsed = 0
	local slowClock = 0

	local function lerp(a: number, b: number, t: number): number
		return a + (b - a) * t
	end
	local function smooth(t: number): number
		return t * t * (3 - 2 * t)
	end

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		if not isVisible() then
			return
		end
		elapsed += dt

		-- Soleil, nuages
		sunRays.Rotation = (sunRays.Rotation + dt * 8) % 360
		for _, cloud in ipairs(clouds) do
			cloud.X += cloud.Speed * dt
			if cloud.X > W + 10 then
				cloud.X = -60
			end
			cloud.Frame.Position = UDim2.fromOffset(cloud.X, cloud.Y)
		end

		-- Plantes : balancement (vent), fleurs mûres qui dansent et scintillent
		for _, plot in ipairs(plots) do
			local wind = math.sin(elapsed * 1.6 + plot.Sway) * (plot.Ripe and 6 or 3)
			plot.Plant.Rotation = wind
			if plot.Ripe and not plot.Popping then
				local pulse = (math.sin(elapsed * 3 + plot.Sway) + 1) / 2
				plot.Halo.BackgroundTransparency = 0.25 + pulse * 0.35
				local headY = plot.Head.Position.Y.Offset
				for s, spark in ipairs(plot.Sparks) do
					local angle = elapsed * 1.4 + s * (math.pi * 2 / MAX_SPARKS) + plot.Sway
					local twinkle = (math.sin(elapsed * 5 + s * 2) + 1) / 2
					spark.Frame.Position = UDim2.new(0.5, math.cos(angle) * 16, 0, headY + math.sin(angle) * 13)
					spark.Frame.Rotation = (elapsed * 90 + s * 40) % 360
					spark.Frame.Size = UDim2.fromOffset(4 + 5 * twinkle, 4 + 5 * twinkle)
					for _, bar in ipairs(spark.Bars) do
						bar.BackgroundTransparency = 0.6 - 0.6 * twinkle
					end
				end
			end
		end

		-- Papillons (Lissajous) : ailes qui battent, orientés vers leur direction
		for _, butterfly in ipairs(butterflies) do
			local t = elapsed * butterfly.Speed * math.pi * 2 + butterfly.Phase
			local x = butterfly.CX + math.sin(t) * 80 + math.sin(t * 2.3) * 16
			local y = butterfly.CY + math.sin(t * 1.7) * 26 + math.cos(t * 3.1) * 6
			x = math.clamp(x, 10, W - 10)
			y = math.clamp(y, HEADER_H + 6, H - 20)
			butterfly.Frame.Position = UDim2.fromOffset(x, y)
			local dx = x - butterfly.LastX
			butterfly.LastX = x
			butterfly.Frame.Rotation = math.clamp(dx * 4, -20, 20)
			local flap = math.abs(math.sin(elapsed * butterfly.Flap + butterfly.Phase))
			local width = math.max(2, math.floor(2 + 7 * flap + 0.5))
			for _, wing in ipairs(butterfly.Wings) do
				wing.Size = UDim2.fromOffset(width, 11)
			end
		end

		-- Arrosoir
		local cs = canState
		if cs.Mode == "rest" then
			cs.Pos = CAN_REST + Vector2.new(0, math.sin(elapsed * 2) * 1.5)
			cs.Tilt = math.sin(elapsed * 1.3) * 4
			cs.Next -= dt
			if cs.Next <= 0 then
				cs.Next = random:NextNumber(7, 11)
				-- Arrose un parterre qui pousse (au hasard)
				local candidates = {}
				for _, plot in ipairs(plots) do
					if not plot.Ripe and plot.Flower ~= "" then
						table.insert(candidates, plot.Index)
					end
				end
				if #candidates > 0 then
					sendCan(candidates[random:NextInteger(1, #candidates)])
				end
			end
		elseif cs.Mode == "fly" or cs.Mode == "back" then
			cs.T += dt
			local t = smooth(math.min(1, cs.T / cs.Dur))
			local arc = math.sin(t * math.pi) * -14
			cs.Pos = Vector2.new(lerp(cs.From.X, cs.To.X, t), lerp(cs.From.Y, cs.To.Y, t) + arc)
			cs.Tilt = math.sin(t * math.pi) * 8
			if t >= 1 then
				if cs.Mode == "fly" then
					cs.Mode = "pour"
					cs.Pour = 0
				else
					cs.Mode = "rest"
				end
			end
		elseif cs.Mode == "pour" then
			cs.Pour += dt
			cs.Tilt = lerp(cs.Tilt, 32, math.min(1, dt * 8))
			if cs.Pour > 0.25 and math.floor(cs.Pour * 14) ~= math.floor((cs.Pour - dt) * 14) and effectsOn() then
				local plot = plots[cs.Target]
				local floor = plot and plotPoint(plot, PW / 2, SOIL_Y + 3).Y or H - 20
				spawnDrop(cs.Pos.X + 17, cs.Pos.Y + 6, floor)
			end
			if cs.Pour > 1.5 then
				cs.Mode = "back"
				cs.From = cs.Pos
				cs.To = CAN_REST
				cs.T = 0
				cs.Dur = 0.8
			end
		end
		can.Position = UDim2.fromOffset(cs.Pos.X, cs.Pos.Y)
		can.Rotation = cs.Tilt

		-- Gouttes d'eau
		if activeDrops > 0 then
			for _, drop in ipairs(drops) do
				if drop.Active then
					drop.VY += 260 * dt
					drop.Y += drop.VY * dt
					if drop.Y >= drop.Floor then
						drop.Active = false
						drop.Frame.Visible = false
						activeDrops -= 1
					else
						drop.Frame.Position = UDim2.fromOffset(drop.X, drop.Y)
					end
				end
			end
		end

		-- Bulle d'info
		if bubble.Visible and os.clock() > bubbleUntil then
			bubble.Visible = false
		end

		-- Minuteurs (4 fois par seconde)
		slowClock += dt
		if slowClock >= 0.25 then
			slowClock = 0
			local now = serverNow()
			for _, plot in ipairs(plots) do
				local wasRipe = plot.Ripe
				refreshPlot(plot, now)
				if plot.Ripe and not wasRipe and plot.Flower ~= "" and effectsOn() then
					-- Une fleur vient d'éclore : petite étincelle
					local point = plotPoint(plot, PW / 2, BASE_Y - 32 * plantBoost)
					ctx.Effects.Burst(card, UDim2.fromOffset(point.X, point.Y), GOLD, 6)
				end
			end
			refreshPill(now)
			if lastPillMode == "all" then
				pillScale.Scale = 1 + math.abs(math.sin(elapsed * 3)) * 0.04
			end
		end
	end)
end

return Garden
