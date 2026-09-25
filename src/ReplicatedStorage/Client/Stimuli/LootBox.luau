--[[
	LootBox (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > LootBox

	Coffre au trésor "premium" (slot CR, 170x170) façon jeu mobile, dessiné
	entièrement en code avec des formes superposées :
	  - carte violette royale avec reflet, halo lumineux qui "respire"
	    derrière le coffre (plus fort et doré quand un coffre est prêt) ;
	  - coffre illustré : planches de bois (dégradé, lignes, veines),
	    renforts dorés avec rivets, rebord doré, couvercle bombé avec
	    reflet, serrure dorée dont le trou de serrure s'illumine, ombre
	    douce au sol qui suit les sauts ;
	  - animations au repos : léger flottement, reflets étincelants sur le
	    métal ; quand un coffre est prêt : petits sauts d'impatience,
	    étincelles autour, bulle "PRÊT !" qui rebondit ;
	  - anneau de charge en arc (segments en dégradé jaune -> orange) +
	    pourcentage en bas ; pastille rouge = coffres en stock (avec "pop").
	Clic -> OpenChest (serveur, protégé par pcall + verrou "opening") :
	le coffre tremble de plus en plus fort, la serrure explose, le couvercle
	bascule, des rayons et des particules de la couleur du rang jaillissent,
	puis une carte récompense monte du coffre (nom du rang, étoiles de
	rareté, gain qui défile). Légendaire = rayons en plus, confettis, flash
	et gros message.
	Bouton "?" : carte des chances (barres colorées + %) calculées depuis
	les poids (Weight) de Config.LootBox.Tiers.

	Tout est construit dans ctx.Container (nettoyé par le StimulusManager) ;
	les particules et reflets sont des réserves recyclées (~150 objets).
]]

local LootBox = {}
LootBox.Slot = "CR"

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

-- Géométrie (pixels "design" de la carte 170x170)
local RING_SEGMENTS = 24 -- segments de l'anneau de charge
local RING_RADIUS = 67
local RING_ARC = 270 -- degrés (ouverture en bas pour le pourcentage)
local CHEST_W = 92
local CHEST_H = 80
local HINGE_Y = 36 -- haut du corps du coffre (charnière du couvercle)
local LID_W = 84
local LID_H = 28
local LID_INNER_H = 22
local REWARD_Y = 50 -- centre final de la carte récompense
local GLINT_POOL = 4 -- reflets recyclés
local SPARK_POOL = 8 -- éclats recyclés
local MIN_SHAKE_TIME = 0.9 -- durée minimale du tremblement avant l'ouverture

-- Couleurs
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local CARD_TOP = Color3.fromRGB(116, 72, 212)
local CARD_BOTTOM = Color3.fromRGB(44, 20, 100)
local IDLE_GLOW = Color3.fromRGB(190, 150, 255)
local WOOD_LIGHT = Color3.fromRGB(206, 134, 68)
local WOOD = Color3.fromRGB(164, 96, 44)
local WOOD_DARK = Color3.fromRGB(106, 56, 22)
local WOOD_OUTLINE = Color3.fromRGB(58, 28, 10)
local WOOD_INSIDE = Color3.fromRGB(64, 30, 10)
local GOLD_LIGHT = Color3.fromRGB(255, 246, 176)
local GOLD = Color3.fromRGB(255, 198, 42)
local GOLD_DARK = Color3.fromRGB(204, 128, 0)
local GOLD_EDGE = Color3.fromRGB(120, 70, 0)
local KEY_DARK = Color3.fromRGB(46, 22, 6)
local KEY_GLOW = Color3.fromRGB(255, 244, 160)
local RING_TRACK = Color3.fromRGB(26, 10, 62)
local RING_START = Color3.fromRGB(255, 232, 80)
local RING_END = Color3.fromRGB(255, 118, 36)

local EFFECT_TEXT_Y = 40 -- hauteur (dans la carte) des textes flottants

function LootBox.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Create = UIUtil.Create
	local Format = ctx.Format
	local config = ctx.Config.LootBox
	local tiers = config.Tiers
	local container: Frame = ctx.Container
	local random = Random.new()

	-- Taille de la carte = slot - 2 x 2 px (marge pour que son contour ne soit pas coupé)
	local slotSize = ctx.GetSlotSize and ctx.GetSlotSize() or Vector2.new(170, 170)
	local width = (slotSize.X > 0 and slotSize.X or 170) - 4
	local height = (slotSize.Y > 0 and slotSize.Y or 170) - 4
	local cx = width / 2
	local cy = height / 2 - 1 -- centre de l'anneau
	local chestCY = cy + 2 -- centre du coffre

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
	-- Petits outils de dessin
	------------------------------------------------------------------
	local function box(parent: Instance, props: { [string]: any }): any
		props.BorderSizePixel = 0
		if props.BackgroundColor3 == nil then
			props.BackgroundColor3 = WHITE
		end
		props.Parent = parent
		return Create("Frame", props)
	end

	local function round(object: Instance)
		UIUtil.Corner(object, UDim.new(1, 0))
	end

	local function vGradient(object: Instance, top: Color3, bottom: Color3): UIGradient
		return Create("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90, Parent = object })
	end

	-- Métal doré "bombé" (clair au milieu) ; rotation 0 = bande verticale
	local function metal(object: Instance, rotation: number)
		Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, GOLD_DARK),
				ColorSequenceKeypoint.new(0.4, GOLD_LIGHT),
				ColorSequenceKeypoint.new(0.7, GOLD),
				ColorSequenceKeypoint.new(1, GOLD_DARK),
			}),
			Rotation = rotation,
			Parent = object,
		})
	end

	local function fadeEnds(): NumberSequence
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	-- Rivet doré (petite bille avec reflet en diagonale)
	local function rivet(parent: Instance, position: UDim2, size: number, z: number)
		local dot = box(parent, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			ZIndex = z,
		})
		round(dot)
		Create("UIGradient", { Color = ColorSequence.new(GOLD_LIGHT, GOLD_EDGE), Rotation = 45, Parent = dot })
	end

	-- Forme au dessus arrondi et au bas carré (couvercle bombé) :
	-- un cadre arrondi + deux "bouche-coins" en bas qui suivent le dégradé
	local function roundedTop(parent: Instance, z: number, top: Color3, bottom: Color3, radius: number, position: UDim2, size: UDim2): any
		local cap = box(parent, { Position = position, Size = size, ZIndex = z })
		UIUtil.Corner(cap, radius)
		vGradient(cap, top, bottom)
		local middle = top:Lerp(bottom, 0.5)
		for _, side in ipairs({ 0, 1 }) do
			local filler = box(cap, {
				AnchorPoint = Vector2.new(side, 1),
				Position = UDim2.fromScale(side, 1),
				Size = UDim2.new(0, radius, 0.5, 0),
				ZIndex = z,
			})
			vGradient(filler, middle, bottom)
		end
		return cap
	end

	------------------------------------------------------------------
	-- Carte (toute la carte est cliquable)
	------------------------------------------------------------------
	local card = Create("TextButton", {
		Name = "Card",
		-- 2 px de marge : le contour de la carte n'est pas coupé par le slot
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = container,
	})
	UIUtil.Corner(card, 20)
	UIUtil.Stroke(card, Theme.Colors.CardBorder, 2)
	vGradient(card, CARD_TOP, CARD_BOTTOM)
	local cardScale = Create("UIScale", { Parent = card })

	-- Reflet en haut de la carte
	local sheen = box(card, {
		Size = UDim2.new(1, 0, 0.55, 0),
		ZIndex = 2,
	})
	UIUtil.Corner(sheen, 20)
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.84, 1),
		Parent = sheen,
	})

	-- Texte flottant dans le calque Overlay (le slot coupe ce qui dépasse).
	-- `point` = position en pixels "design" dans la carte.
	local function floatText(point: Vector2, text: string, color: Color3?, size: number?)
		local interface = ctx.Interface
		if interface and interface.ScreenToCanvas and ctx.Overlay then
			local ratio = card.AbsoluteSize.X / math.max(1, width)
			local canvas = interface.ScreenToCanvas(card.AbsolutePosition + point * ratio)
			ctx.FloatText(ctx.Overlay, UDim2.fromOffset(canvas.X, canvas.Y), text, color, size)
		else
			ctx.FloatText(card, UDim2.fromOffset(point.X, point.Y), text, color, size)
		end
	end

	------------------------------------------------------------------
	-- Halo + rayons (derrière le coffre)
	------------------------------------------------------------------
	local glowOuter = box(card, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, chestCY + 2),
		Size = UDim2.fromOffset(124, 124),
		BackgroundColor3 = IDLE_GLOW,
		BackgroundTransparency = 0.9,
		ZIndex = 3,
	})
	round(glowOuter)
	local glowInner = box(glowOuter, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64),
		BackgroundColor3 = IDLE_GLOW,
		BackgroundTransparency = 0.85,
		ZIndex = 3,
	})
	round(glowInner)

	local function makeRays(count: number, size: number): (Frame, { Frame })
		local holder = UIUtil.Rays(card, GOLD, count, size, UDim2.fromOffset(cx, chestCY - 6), 4)
		holder.Visible = false
		local bars = {}
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("Frame") then
				child.BackgroundTransparency = 1
				table.insert(bars, child)
			end
		end
		return holder, bars
	end
	local rays, rayBars = makeRays(6, 240)
	local bigRays, bigRayBars = makeRays(6, 300)

	------------------------------------------------------------------
	-- Anneau de charge (arc de segments)
	------------------------------------------------------------------
	local segments = {}
	for index = 1, RING_SEGMENTS do
		local t = (index - 0.5) / RING_SEGMENTS
		local angle = math.rad(-RING_ARC / 2 + RING_ARC * t) -- 0 = midi, sens horaire
		local segment = box(card, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx + math.sin(angle) * RING_RADIUS, cy - math.cos(angle) * RING_RADIUS),
			Size = UDim2.fromOffset(11, 5),
			Rotation = math.deg(angle),
			BackgroundColor3 = RING_TRACK,
			BackgroundTransparency = 0.45,
			ZIndex = 5,
		})
		UIUtil.Corner(segment, UDim.new(1, 0))
		segments[index] = {
			Frame = segment,
			Color = RING_START:Lerp(RING_END, (index - 1) / math.max(1, RING_SEGMENTS - 1)),
			Fill = 0,
		}
	end

	local percentPill = UIUtil.Label({
		Text = "0 %",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, height - 17),
		Size = UDim2.fromOffset(66, 20),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = RING_TRACK,
		MaxTextSize = 13,
		ZIndex = 23,
		Parent = card,
	})
	UIUtil.Corner(percentPill, UDim.new(1, 0))
	UIUtil.Stroke(percentPill, RING_START, 1.5, 0.35)

	------------------------------------------------------------------
	-- Ombre au sol
	------------------------------------------------------------------
	local shadow = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, chestCY + CHEST_H / 2 - 1),
		Size = UDim2.fromOffset(88, 14),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = card,
	})
	local shadowScale = Create("UIScale", { Parent = shadow })
	local shadowOuter = box(shadow, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.78,
		ZIndex = 6,
	})
	round(shadowOuter)
	local shadowInner = box(shadow, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.62),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.7,
		ZIndex = 6,
	})
	round(shadowInner)

	------------------------------------------------------------------
	-- Le coffre (groupe 92x80, coordonnées locales)
	------------------------------------------------------------------
	local chest = Create("Frame", {
		Name = "Chest",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, chestCY),
		Size = UDim2.fromOffset(CHEST_W, CHEST_H),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = card,
	})
	local chestScale = Create("UIScale", { Parent = chest })
	local chestMidX = CHEST_W / 2

	-- Dessous du couvercle (visible quand il est ouvert)
	local lidInner = box(chest, {
		Name = "LidInner",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(chestMidX, HINGE_Y + 1),
		Size = UDim2.fromOffset(LID_W, 0),
		Visible = false,
		ZIndex = 1,
	})
	UIUtil.Corner(lidInner, 8)
	UIUtil.Stroke(lidInner, WOOD_OUTLINE, 2)
	vGradient(lidInner, WOOD_DARK, WOOD_INSIDE)
	local lidInnerTrim = box(lidInner, {
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.new(1, -8, 0, 4),
		ZIndex = 1,
	})
	UIUtil.Corner(lidInnerTrim, 2)
	metal(lidInnerTrim, 90)

	-- Faisceau de lumière qui sort du coffre ouvert
	local beam = box(chest, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(chestMidX, HINGE_Y + 2),
		Size = UDim2.fromOffset(70, 86),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.6, 0.55),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
		Parent = beam,
	})
	UIUtil.Corner(beam, 18)

	-- Corps en bois
	local body = box(chest, {
		Name = "Body",
		Position = UDim2.fromOffset(6, HINGE_Y),
		Size = UDim2.fromOffset(80, 40),
		ZIndex = 3,
	})
	UIUtil.Corner(body, 6)
	UIUtil.Stroke(body, WOOD_OUTLINE, 2)
	vGradient(body, WOOD, WOOD_DARK)
	-- Planches : ligne sombre + liseré clair
	for _, y in ipairs({ 13, 26 }) do
		box(body, {
			Position = UDim2.fromOffset(2, y),
			Size = UDim2.new(1, -4, 0, 1),
			BackgroundColor3 = WOOD_OUTLINE,
			BackgroundTransparency = 0.35,
			ZIndex = 3,
		})
		box(body, {
			Position = UDim2.fromOffset(2, y + 1),
			Size = UDim2.new(1, -4, 0, 1),
			BackgroundTransparency = 0.82,
			ZIndex = 3,
		})
	end
	-- Veines du bois
	for _, grain in ipairs({ { 21, 6, 8 }, { 69, 19, 7 }, { 22, 31, 6 } }) do
		local streak = box(body, {
			Position = UDim2.fromOffset(grain[1], grain[2]),
			Size = UDim2.fromOffset(grain[3], 1),
			BackgroundColor3 = WOOD_OUTLINE,
			BackgroundTransparency = 0.6,
			ZIndex = 3,
		})
		round(streak)
	end
	-- Renforts dorés verticaux + rivets
	for _, x in ipairs({ 12, 61 }) do
		local band = box(body, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, 7, 1, 0),
			ZIndex = 4,
		})
		metal(band, 0)
		rivet(band, UDim2.new(0.5, 0, 0, 9), 4, 4)
		rivet(band, UDim2.new(0.5, 0, 1, -8), 4, 4)
	end
	-- Bande dorée du bas
	local bottomTrim = box(body, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 4),
		ZIndex = 5,
	})
	UIUtil.Corner(bottomTrim, 2)
	metal(bottomTrim, 90)

	-- Couvercle bombé (face avant) : s'écrase quand il bascule
	local lid = Create("Frame", {
		Name = "Lid",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(chestMidX, HINGE_Y),
		Size = UDim2.fromOffset(LID_W, LID_H),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = chest,
	})
	-- Contour sombre (un peu plus grand, derrière)
	roundedTop(lid, 4, WOOD_OUTLINE, WOOD_OUTLINE, 14, UDim2.fromOffset(-2, -2), UDim2.new(1, 4, 1, 2))
	local lidFace = roundedTop(lid, 5, WOOD_LIGHT, WOOD, 12, UDim2.new(), UDim2.fromScale(1, 1))
	-- Détails du couvercle (au-dessus de la face et de ses bouche-coins)
	local lidGloss = box(lidFace, {
		Position = UDim2.new(0, 12, 0.12, 0),
		Size = UDim2.new(1, -24, 0.14, 0),
		BackgroundTransparency = 0.5,
		ZIndex = 6,
	})
	round(lidGloss)
	box(lidFace, {
		Position = UDim2.new(0, 3, 0.62, 0),
		Size = UDim2.new(1, -6, 0, 1),
		BackgroundColor3 = WOOD_OUTLINE,
		BackgroundTransparency = 0.45,
		ZIndex = 6,
	})
	for _, x in ipairs({ 14, 63 }) do
		local band = box(lidFace, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, 7, 1, 0),
			ZIndex = 7,
		})
		metal(band, 0)
		rivet(band, UDim2.fromScale(0.5, 0.4), 4, 7)
	end

	-- Rebord doré entre le couvercle et le corps
	local rim = box(chest, {
		Position = UDim2.fromOffset(4, HINGE_Y - 3),
		Size = UDim2.fromOffset(84, 6),
		ZIndex = 5,
	})
	UIUtil.Corner(rim, 3)
	UIUtil.Stroke(rim, GOLD_EDGE, 1)
	metal(rim, 90)
	for _, x in ipairs({ 10, 28, 56, 74 }) do
		rivet(rim, UDim2.new(0, x, 0.5, 0), 3, 5)
	end

	-- Lueur qui déborde de l'ouverture (couvercle ouvert)
	local mouthGlow = box(chest, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(chestMidX, HINGE_Y - 1),
		Size = UDim2.fromOffset(78, 10),
		BackgroundColor3 = GOLD_LIGHT,
		BackgroundTransparency = 1,
		ZIndex = 6,
	})
	round(mouthGlow)

	-- Serrure (halo + plaque + trou de serrure)
	local lockHolder = Create("Frame", {
		Name = "Lock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(chestMidX, HINGE_Y + 6),
		Size = UDim2.fromOffset(22, 26),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = chest,
	})
	local lockScale = Create("UIScale", { Parent = lockHolder })
	local lockGlow = box(lockHolder, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 1,
		ZIndex = 7,
	})
	round(lockGlow)
	local plate = box(lockHolder, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 22),
		ZIndex = 8,
	})
	UIUtil.Corner(plate, 5)
	local plateStroke = UIUtil.Stroke(plate, GOLD_EDGE, 1.5)
	Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, GOLD_LIGHT),
			ColorSequenceKeypoint.new(0.5, GOLD),
			ColorSequenceKeypoint.new(1, GOLD_DARK),
		}),
		Rotation = 60,
		Parent = plate,
	})
	local plateShine = box(plate, {
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(3, 9),
		BackgroundTransparency = 0.4,
		ZIndex = 8,
	})
	round(plateShine)
	local keyhole = box(plate, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = KEY_DARK,
		ZIndex = 9,
	})
	round(keyhole)
	local keySlot = box(plate, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, 1),
		Size = UDim2.fromOffset(3, 7),
		BackgroundColor3 = KEY_DARK,
		ZIndex = 9,
	})
	UIUtil.Corner(keySlot, 1)

	-- Fait disparaître / réapparaître la serrure
	local function fadeLock(alpha: number, duration: number)
		UIUtil.Tween(plate, duration, { BackgroundTransparency = alpha })
		UIUtil.Tween(plateStroke, duration, { Transparency = alpha })
		UIUtil.Tween(plateShine, duration, { BackgroundTransparency = 0.4 + 0.6 * alpha })
		UIUtil.Tween(keyhole, duration, { BackgroundTransparency = alpha })
		UIUtil.Tween(keySlot, duration, { BackgroundTransparency = alpha })
	end

	------------------------------------------------------------------
	-- Reflets (étoiles à 4 branches) et éclats : réserves recyclées
	------------------------------------------------------------------
	local glints = {}
	for index = 1, GLINT_POOL do
		local holder = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 17,
			Parent = card,
		})
		for _, rotation in ipairs({ 0, 90 }) do
			local arm = box(holder, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, 3),
				Rotation = rotation,
				ZIndex = 17,
			})
			round(arm)
			Create("UIGradient", { Transparency = fadeEnds(), Parent = arm })
		end
		glints[index] = { Frame = holder, Scale = Create("UIScale", { Scale = 0, Parent = holder }), Busy = false }
	end

	local function spawnGlint(position: Vector2, size: number)
		for _, glint in ipairs(glints) do
			if not glint.Busy then
				glint.Busy = true
				local frame = glint.Frame
				frame.Position = UDim2.fromOffset(position.X, position.Y)
				frame.Size = UDim2.fromOffset(size, size)
				frame.Rotation = 0
				frame.Visible = true
				glint.Scale.Scale = 0
				UIUtil.Tween(glint.Scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
				UIUtil.Tween(frame, 0.6, { Rotation = 90 })
				task.delay(0.28, function()
					if frame.Parent then
						UIUtil.Tween(glint.Scale, 0.3, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					end
				end)
				task.delay(0.62, function()
					glint.Busy = false
					if frame.Parent then
						frame.Visible = false
					end
				end)
				return
			end
		end
	end

	local sparks = {}
	for index = 1, SPARK_POOL do
		local spark = box(card, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(8, 8),
			Rotation = 45,
			Visible = false,
			ZIndex = 18,
		})
		UIUtil.Corner(spark, 2)
		sparks[index] = { Frame = spark, Busy = false }
	end

	local function launchSparks(origin: Vector2, color: Color3, count: number, minDistance: number, maxDistance: number)
		if not effectsOn() then
			return
		end
		local launched = 0
		for _, spark in ipairs(sparks) do
			if launched >= count then
				break
			end
			if not spark.Busy then
				launched += 1
				spark.Busy = true
				local frame = spark.Frame
				local angle = random:NextNumber(0, math.pi * 2)
				local distance = random:NextNumber(minDistance, maxDistance)
				local duration = random:NextNumber(0.45, 0.7)
				frame.Position = UDim2.fromOffset(origin.X, origin.Y)
				frame.Size = UDim2.fromOffset(9, 9)
				frame.Rotation = 45
				frame.BackgroundColor3 = color:Lerp(WHITE, random:NextNumber(0, 0.5))
				frame.BackgroundTransparency = 0
				frame.Visible = true
				UIUtil.Tween(frame, duration, {
					Position = UDim2.fromOffset(origin.X + math.cos(angle) * distance, origin.Y + math.sin(angle) * distance),
					Size = UDim2.fromOffset(2, 2),
					Rotation = 45 + random:NextNumber(-200, 200),
					BackgroundTransparency = 1,
				}, Enum.EasingStyle.Quart)
				task.delay(duration, function()
					spark.Busy = false
					if frame.Parent then
						frame.Visible = false
					end
				end)
			end
		end
	end

	-- Flash blanc local (cercle qui s'agrandit)
	local flash = box(card, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, chestCY - 4),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		ZIndex = 19,
	})
	round(flash)

	------------------------------------------------------------------
	-- Carte récompense (monte du coffre)
	------------------------------------------------------------------
	local reward = box(card, {
		Name = "Reward",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, REWARD_Y),
		Size = UDim2.fromOffset(132, 64),
		Visible = false,
		ZIndex = 20,
	})
	UIUtil.Corner(reward, 12)
	local rewardStroke = UIUtil.Stroke(reward, GOLD, 2.5)
	local rewardGradient = vGradient(reward, GOLD_LIGHT, WHITE)
	local rewardScale = Create("UIScale", { Parent = reward })

	local tierLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = GOLD,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(1, -10, 0, 19),
		MaxTextSize = 18,
		ZIndex = 21,
		Parent = reward,
	})
	local tierStroke = UIUtil.Stroke(tierLabel, Theme.Colors.TextDark, 1.5)
	tierStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local starRow = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 23),
		Size = UDim2.new(1, -10, 0, 14),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = reward,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = starRow,
	})
	local stars = {}
	for index = 1, math.clamp(#tiers, 1, 5) do
		local star = Create("TextLabel", {
			Text = "★",
			Font = Theme.Fonts.Title,
			TextSize = 15,
			TextColor3 = GOLD,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(14, 14),
			LayoutOrder = index,
			ZIndex = 21,
			Parent = starRow,
		})
		local starStroke = Create("UIStroke", {
			Color = GOLD_EDGE,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = star,
		})
		stars[index] = { Label = star, Stroke = starStroke, Scale = Create("UIScale", { Parent = star }) }
	end

	local amountLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.TextDark,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 38),
		Size = UDim2.new(1, -10, 0, 22),
		MaxTextSize = 21,
		ZIndex = 21,
		Parent = reward,
	})
	local amountScale = Create("UIScale", { Parent = amountLabel })

	------------------------------------------------------------------
	-- Bulle "PRÊT !", pastille de stock, bouton "?"
	------------------------------------------------------------------
	local callout = UIUtil.Label({
		Text = Locale.T("READY!"),
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(70, 30, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, 20),
		Size = UDim2.fromOffset(66, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		MaxTextSize = 15,
		Visible = false,
		ZIndex = 23,
		Parent = card,
	})
	UIUtil.Corner(callout, UDim.new(1, 0))
	UIUtil.Stroke(callout, WOOD_OUTLINE, 2)
	vGradient(callout, GOLD_LIGHT, Color3.fromRGB(255, 160, 30))
	local calloutScale = Create("UIScale", { Scale = 0, Parent = callout })

	-- (le dégradé teinterait aussi le texte : fond et chiffre séparés)
	local badge = box(card, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(width - 17, 17),
		Size = UDim2.fromOffset(24, 24),
		Visible = false,
		ZIndex = 24,
	})
	UIUtil.Corner(badge, UDim.new(1, 0))
	UIUtil.Stroke(badge, WHITE, 2)
	vGradient(badge, Color3.fromRGB(255, 92, 92), Color3.fromRGB(200, 20, 30))
	local badgeScale = Create("UIScale", { Parent = badge })
	local badgeText = UIUtil.Label({
		Text = "0",
		Font = Theme.Fonts.Number,
		TextColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = 15,
		ZIndex = 24,
		Parent = badge,
	})

	local oddsButton = Create("TextButton", {
		Name = "Odds",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(17, 17),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "?",
		TextColor3 = WHITE,
		TextSize = 15,
		ZIndex = 25,
		Parent = card,
	})
	UIUtil.Corner(oddsButton, UDim.new(1, 0))
	UIUtil.Stroke(oddsButton, WHITE, 1.5, 0.35)

	------------------------------------------------------------------
	-- Carte des chances (bouton "?")
	------------------------------------------------------------------
	local totalWeight = 0
	for _, tier in ipairs(tiers) do
		totalWeight += math.max(0, tonumber(tier.Weight) or 0)
	end

	local function percentOf(tier): number
		if totalWeight <= 0 then
			return 0
		end
		return math.max(0, tonumber(tier.Weight) or 0) / totalWeight * 100
	end

	local function percentText(percent: number): string
		if totalWeight <= 0 then
			return "?"
		end
		if percent >= 10 or math.abs(percent - math.floor(percent + 0.5)) < 0.05 then
			return tostring(math.floor(percent + 0.5)) .. " %"
		end
		return string.format("%.1f %%", percent)
	end

	local oddsPanel = Create("TextButton", {
		Name = "OddsPanel",
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 30,
		Visible = false,
		Parent = card,
	})
	UIUtil.Corner(oddsPanel, 16)
	UIUtil.Stroke(oddsPanel, Theme.Colors.Purple, 2, 0.1)
	vGradient(oddsPanel, WHITE, Color3.fromRGB(240, 234, 255))
	local oddsScale = Create("UIScale", { Parent = oddsPanel })
	UIUtil.Label({
		Text = Locale.T("🎲 Odds"),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		Position = UDim2.fromOffset(10, 5),
		Size = UDim2.new(1, -20, 0, 20),
		MaxTextSize = 16,
		ZIndex = 31,
		Parent = oddsPanel,
	})
	local panelHeight = height - 8
	local rowCount = math.max(1, #tiers)
	local rowHeight = math.min(30, math.floor((panelHeight - 28 - 18) / rowCount))
	local oddsFills = {}
	for index, tier in ipairs(tiers) do
		local y = 28 + (index - 1) * rowHeight
		local tierColor: Color3 = tier.Color or GOLD
		local percent = percentOf(tier)
		UIUtil.Label({
			Text = Locale.T(tostring(tier.Name or tier.Id)),
			Font = Theme.Fonts.Title,
			TextColor3 = tierColor:Lerp(Theme.Colors.TextDark, 0.3),
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.new(1, -76, 0, rowHeight - 14),
			MaxTextSize = 13,
			ZIndex = 31,
			Parent = oddsPanel,
		})
		UIUtil.Label({
			Text = percentText(percent),
			Font = Theme.Fonts.Number,
			TextColor3 = Theme.Colors.TextDark,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, y),
			Size = UDim2.fromOffset(56, rowHeight - 14),
			MaxTextSize = 13,
			ZIndex = 31,
			Parent = oddsPanel,
		})
		local track = box(oddsPanel, {
			Position = UDim2.fromOffset(12, y + rowHeight - 13),
			Size = UDim2.new(1, -24, 0, 8),
			BackgroundColor3 = Color3.fromRGB(226, 220, 240),
			ClipsDescendants = true,
			ZIndex = 31,
		})
		round(track)
		local fill = box(track, {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = WHITE,
			ZIndex = 32,
		})
		round(fill)
		Create("UIGradient", { Color = ColorSequence.new(tierColor:Lerp(WHITE, 0.45), tierColor), Parent = fill })
		oddsFills[index] = { Frame = fill, Target = math.max(0.04, percent / 100) }
	end
	UIUtil.Label({
		Text = Locale.T("Tap to close"),
		TextColor3 = Theme.Colors.TextDim,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -16, 0, 13),
		MaxTextSize = 11,
		ZIndex = 31,
		Parent = oddsPanel,
	})

	local oddsToken = 0
	local function setOdds(show: boolean)
		oddsToken += 1
		oddsPanel.Visible = show
		if not show then
			return
		end
		oddsScale.Scale = 0.8
		UIUtil.Tween(oddsScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Click", 1.4)
		local token = oddsToken
		for index, entry in ipairs(oddsFills) do
			entry.Frame.Size = UDim2.fromScale(0, 1)
			task.delay(0.05 + index * 0.07, function()
				if token == oddsToken and entry.Frame.Parent then
					UIUtil.Tween(entry.Frame, 0.45, { Size = UDim2.fromScale(entry.Target, 1) }, Enum.EasingStyle.Quart)
				end
			end)
		end
		-- Fermeture automatique
		task.delay(7, function()
			if token == oddsToken and oddsPanel.Parent then
				oddsPanel.Visible = false
			end
		end)
	end
	ctx.Connect(oddsButton.Activated, function()
		setOdds(not oddsPanel.Visible)
	end)
	ctx.Connect(oddsPanel.Activated, function()
		setOdds(false)
	end)
	ctx.Connect(oddsButton.MouseEnter, function()
		UIUtil.Tween(oddsButton, 0.12, { BackgroundTransparency = 0.6 })
	end)
	ctx.Connect(oddsButton.MouseLeave, function()
		UIUtil.Tween(oddsButton, 0.12, { BackgroundTransparency = 0.8 })
	end)

	------------------------------------------------------------------
	-- Suivi du stock et de la charge
	------------------------------------------------------------------
	local stored, serverProgress, maxStored = readChests()
	local progressTime = os.clock()
	local shownFill = 0
	local opening = false
	local calloutShown = false
	local pillText = ""
	local pillOverride = ""
	local pillOverrideUntil = 0

	local function setCallout(show: boolean)
		if show == calloutShown then
			return
		end
		calloutShown = show
		if show then
			callout.Visible = true
			calloutScale.Scale = 0.2
			UIUtil.Tween(calloutScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			UIUtil.Tween(calloutScale, 0.18, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.2, function()
				if not calloutShown and callout.Parent then
					callout.Visible = false
				end
			end)
		end
	end

	local function refreshStock()
		badge.Visible = stored > 0
		badgeText.Text = stored > 99 and "99+" or tostring(math.floor(stored))
		callout.Text = stored >= maxStored and Locale.T("FULL!") or Locale.T("READY!")
		setCallout(stored >= 1 and not opening)
	end
	refreshStock()

	local function showPillMessage(text: string, seconds: number)
		pillOverride = text
		pillOverrideUntil = os.clock() + seconds
	end

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
			refreshStock()
			if gained and not opening then
				-- Nouveau coffre prêt : "pop" du badge + étincelles
				ctx.Sound.Play("Bonus", 1.4)
				badgeScale.Scale = 1.8
				UIUtil.Tween(badgeScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
				launchSparks(Vector2.new(cx, chestCY - 6), GOLD, 6, 30, 60)
				floatText(Vector2.new(cx, EFFECT_TEXT_Y), "+1 📦", GOLD, 22)
			end
		end
	end)

	------------------------------------------------------------------
	-- Animation continue
	------------------------------------------------------------------
	local elapsed = 0
	local shakeAmount = 0 -- tremblement (ouverture / refus)
	local charge = 0 -- 0..1 : montée en tension pendant l'ouverture
	local glowLevel = 0.3
	local glowColor = IDLE_GLOW
	local glowTarget = IDLE_GLOW
	local raysAlpha = 1 -- 1 = rayons invisibles
	local raysTarget = 1
	local bigRaysOn = false
	local glintClock = 0
	local legendaryName: Color3? = nil -- couleur du nom qui scintille (légendaire)

	local function drawRing(fill: number, shimmer: boolean)
		local wavePosition = (elapsed * 0.7) % 1.4 - 0.2
		for index, segment in ipairs(segments) do
			local amount = math.clamp(fill * RING_SEGMENTS - (index - 1), 0, 1)
			if shimmer or math.abs(amount - segment.Fill) > 0.002 then
				segment.Fill = amount
				local color = segment.Color
				if shimmer then
					local distance = math.abs(index / RING_SEGMENTS - wavePosition)
					color = color:Lerp(WHITE, math.max(0, 1 - distance * 7) * 0.75)
				end
				segment.Frame.BackgroundColor3 = RING_TRACK:Lerp(color, amount)
				segment.Frame.BackgroundTransparency = 0.45 * (1 - amount)
			end
		end
	end

	ctx.OnRender(function(dt: number)
		elapsed += dt
		local ready = stored >= 1 and not opening
		local full = stored >= maxStored

		-- Charge (prédite entre deux états du serveur)
		local target
		if full then
			target = 1
		else
			target = math.clamp(serverProgress + (os.clock() - progressTime) / (config.ChargeInterval or 120), 0, 1)
		end
		shownFill += (target - shownFill) * math.min(1, dt * 6)
		if target < shownFill - 0.5 then
			shownFill = target -- nouveau cycle : on repart de zéro
		end
		drawRing(full and 1 or shownFill, full)

		local text
		if os.clock() < pillOverrideUntil then
			text = pillOverride
		elseif full then
			text = Locale.T("FULL")
		else
			text = math.floor(target * 100) .. " %"
		end
		if text ~= pillText then
			pillText = text
			percentPill.Text = text
			percentPill.TextColor3 = text == pillOverride and Theme.Colors.Yellow or WHITE
		end

		-- Mouvement du coffre : tremblement, sauts d'impatience ou flottement
		local offsetX, offsetY, rotation = 0, 0, 0
		if shakeAmount > 0 then
			offsetX = math.sin(elapsed * 61) * shakeAmount * 0.55
			offsetY = math.sin(elapsed * 43) * shakeAmount * 0.2
			rotation = math.sin(elapsed * 53) * shakeAmount * 0.9
		elseif ready then
			offsetY = math.sin(elapsed * 2.4) * 1.5
			local phase = elapsed % 2.3
			if phase < 0.55 then
				local hop = math.sin(phase / 0.55 * math.pi)
				offsetY -= hop * 11
				rotation = math.sin(phase / 0.55 * math.pi * 2) * 5
			end
		elseif not opening then
			offsetY = math.sin(elapsed * 2) * 2.5 - 1
		end
		chest.Position = UDim2.fromOffset(cx + offsetX, chestCY + offsetY)
		chest.Rotation = rotation
		if not opening then
			chestScale.Scale = 1 + math.max(0, -offsetY - 3) * 0.004
		end

		-- Ombre : plus petite et plus claire quand le coffre est en l'air
		local lift = math.max(0, -offsetY)
		shadowScale.Scale = math.clamp(1 - lift * 0.035, 0.55, 1.05)
		shadowInner.BackgroundTransparency = 0.7 + lift * 0.015

		-- Halo qui respire (plus fort quand un coffre attend)
		local wanted = opening and 1 or (stored >= 1 and 0.85 or 0.3)
		glowLevel += (wanted - glowLevel) * math.min(1, dt * 3)
		if not opening then
			glowTarget = stored >= 1 and GOLD or IDLE_GLOW
		end
		glowColor = glowColor:Lerp(glowTarget, math.min(1, dt * 5))
		local pulse = 0.5 + 0.5 * math.sin(elapsed * (stored >= 1 and 4 or 2))
		glowOuter.BackgroundColor3 = glowColor
		glowInner.BackgroundColor3 = glowColor:Lerp(WHITE, 0.3)
		glowOuter.BackgroundTransparency = 1 - (0.06 + 0.16 * glowLevel) * (0.7 + 0.3 * pulse)
		glowInner.BackgroundTransparency = 1 - (0.08 + 0.3 * glowLevel) * (0.65 + 0.35 * pulse)
		local glowSize = 116 + glowLevel * 10 + pulse * 8 * glowLevel
		glowOuter.Size = UDim2.fromOffset(glowSize, glowSize)

		-- Trou de serrure lumineux
		local keyLight
		if opening then
			keyLight = charge
		elseif ready then
			keyLight = 0.35 + 0.65 * pulse
		else
			keyLight = 0.1 * pulse
		end
		keyhole.BackgroundColor3 = KEY_DARK:Lerp(KEY_GLOW, keyLight)
		keySlot.BackgroundColor3 = keyhole.BackgroundColor3
		lockGlow.BackgroundTransparency = 1 - 0.5 * keyLight

		-- Bulle "PRÊT !" qui rebondit
		if calloutShown then
			-- (rebond limité : la bulle ne touche jamais le bord de la carte)
			callout.Position = UDim2.fromOffset(cx, 20 - math.abs(math.sin(elapsed * 4.5)) * 3)
			callout.Rotation = math.sin(elapsed * 2.2) * 3
		end

		-- Reflets : étincelles autour du coffre prêt, reflets sur le métal sinon
		if effectsOn() then
			glintClock += dt
			local interval = ready and 0.32 or (opening and 0.15 or 1.4)
			if glintClock >= interval then
				glintClock = 0
				if ready or opening then
					local angle = random:NextNumber(0, math.pi * 2)
					local distance = random:NextNumber(40, 58)
					spawnGlint(
						Vector2.new(cx + math.cos(angle) * distance, chestCY - 4 + math.sin(angle) * distance * 0.85),
						random:NextInteger(12, 18)
					)
				else
					-- Sur le rebord doré, le couvercle ou la serrure
					local spots = { Vector2.new(-38, -8), Vector2.new(30, -8), Vector2.new(-22, -26), Vector2.new(4, 2), Vector2.new(24, -30) }
					local spot = spots[random:NextInteger(1, #spots)]
					spawnGlint(Vector2.new(cx + spot.X, chestCY + offsetY + spot.Y), random:NextInteger(10, 14))
				end
			end
		end

		-- Rayons tournants
		raysAlpha += (raysTarget - raysAlpha) * math.min(1, dt * 6)
		if raysTarget >= 1 and raysAlpha > 0.985 then
			raysAlpha = 1
		end
		local raysVisible = raysAlpha < 1
		rays.Visible = raysVisible
		bigRays.Visible = raysVisible and bigRaysOn
		if raysVisible then
			rays.Rotation = elapsed * 28
			for _, bar in ipairs(rayBars) do
				bar.BackgroundTransparency = raysAlpha
			end
			if bigRaysOn then
				bigRays.Rotation = 15 - elapsed * 40
				local alpha = math.min(1, raysAlpha + 0.1)
				for _, bar in ipairs(bigRayBars) do
					bar.BackgroundTransparency = alpha
				end
			end
		end

		-- Nom légendaire qui scintille
		local shine = legendaryName
		if shine then
			tierLabel.TextColor3 = shine:Lerp(WHITE, 0.5 + 0.5 * math.sin(elapsed * 12))
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
		for index, tier in ipairs(tiers) do
			if tier.Id == id then
				return tier, index
			end
		end
		return tiers[1], 1
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

	-- Le couvercle bascule : la face avant s'écrase, puis le dessous apparaît
	local function flipLid(open: boolean): boolean
		if open then
			UIUtil.Tween(lid, 0.1, { Size = UDim2.fromOffset(LID_W, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if not waitAlive(0.1) then
				return false
			end
			lid.Visible = false
			lidInner.Size = UDim2.fromOffset(LID_W, 0)
			lidInner.Visible = true
			UIUtil.Tween(lidInner, 0.3, { Size = UDim2.fromOffset(LID_W, LID_INNER_H) }, Enum.EasingStyle.Back)
		else
			UIUtil.Tween(lidInner, 0.1, { Size = UDim2.fromOffset(LID_W, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if not waitAlive(0.1) then
				return false
			end
			lidInner.Visible = false
			lid.Size = UDim2.fromOffset(LID_W, 0)
			lid.Visible = true
			UIUtil.Tween(lid, 0.3, { Size = UDim2.fromOffset(LID_W, LID_H) }, Enum.EasingStyle.Back)
		end
		return true
	end

	-- Gain qui défile de 0 à `amount`
	local function countUp(amount: number, duration: number)
		task.spawn(function()
			local started = os.clock()
			local ticks = 0
			while ctx.IsAlive() and reward.Visible do
				local t = math.min(1, (os.clock() - started) / duration)
				local eased = 1 - (1 - t) ^ 3
				amountLabel.Text = "+" .. Format.Format(math.floor(amount * eased))
				if t >= 1 then
					break
				end
				if t * 6 >= ticks + 1 then
					ticks += 1
					ctx.Sound.Play("Click", 1.1 + ticks * 0.12)
				end
				task.wait()
			end
			if ctx.IsAlive() then
				amountLabel.Text = "+" .. Format.Format(amount)
				amountScale.Scale = 1.3
				UIUtil.Tween(amountScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
	end

	local rewardToken = 0

	local function showReward(tier, tierIndex: number, color: Color3, amount: number, legendary: boolean)
		rewardToken += 1
		tierLabel.Text = Locale.T(tostring(tier.Name or tier.Id))
		tierLabel.TextColor3 = color
		legendaryName = legendary and color or nil
		rewardStroke.Color = color
		rewardGradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.72), WHITE)
		amountLabel.Text = "+0"
		amountScale.Scale = 1
		for index, star in ipairs(stars) do
			local filled = index <= tierIndex
			star.Label.TextColor3 = filled and GOLD or Color3.fromRGB(205, 205, 215)
			star.Stroke.Color = filled and GOLD_EDGE or Color3.fromRGB(160, 160, 175)
			star.Scale.Scale = 0
		end

		reward.Position = UDim2.fromOffset(cx, chestCY + 4)
		rewardScale.Scale = 0.25
		reward.Visible = true
		UIUtil.Tween(reward, 0.5, { Position = UDim2.fromOffset(cx, REWARD_Y) }, Enum.EasingStyle.Back)
		UIUtil.Tween(rewardScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)

		-- Étoiles une par une
		task.spawn(function()
			if not waitAlive(0.3) then
				return
			end
			for index, star in ipairs(stars) do
				if not reward.Visible then
					return
				end
				UIUtil.Tween(star.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
				if index <= tierIndex then
					ctx.Sound.Play("Pop", 1 + index * 0.12)
				end
				if not waitAlive(0.09) then
					return
				end
			end
		end)
		countUp(amount, legendary and 1.4 or 0.9)
	end

	local function hideReward()
		legendaryName = nil
		local token = rewardToken
		UIUtil.Tween(rewardScale, 0.22, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.24, function()
			if token == rewardToken and reward.Parent then
				reward.Visible = false
			end
		end)
	end

	-- Petit coup de secousse de toute la carte (légendaire)
	local function jolt()
		task.spawn(function()
			for step = 1, 8 do
				if not ctx.IsAlive() then
					return
				end
				card.Rotation = (step % 2 == 0 and 1 or -1) * (9 - step) * 0.5
				task.wait(0.03)
			end
			if card.Parent then
				card.Rotation = 0
			end
		end)
	end

	local function reveal(result): number
		local tier, tierIndex = findTier(result.Tier)
		local color: Color3 = tier.Color or GOLD
		local amount = tonumber(result.Amount) or 0
		local amountText = "+" .. Format.Format(amount)
		local legendary = tier.Id == "Legendary" or tierIndex >= #tiers

		-- 1) La serrure saute
		shakeAmount = 0
		charge = 1
		ctx.Sound.Play("Chest", 1)
		UIUtil.Tween(lockScale, 0.25, { Scale = 1.9 }, Enum.EasingStyle.Quad)
		fadeLock(1, 0.22)
		UIUtil.Tween(lockGlow, 0.25, { BackgroundTransparency = 1 })
		launchSparks(Vector2.new(cx, chestCY + HINGE_Y + 6 - CHEST_H / 2), GOLD, 5, 20, 45)

		-- 2) Le couvercle bascule, la lumière jaillit
		chestScale.Scale = 1.14
		UIUtil.Tween(chestScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Elastic)
		if not flipLid(true) then
			return 0
		end
		flash.Size = UDim2.fromOffset(20, 20)
		flash.BackgroundTransparency = 0.15
		UIUtil.Tween(flash, 0.45, { Size = UDim2.fromOffset(210, 210), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		beam.BackgroundColor3 = color:Lerp(WHITE, 0.25)
		UIUtil.Tween(beam, 0.25, { BackgroundTransparency = 0 })
		mouthGlow.BackgroundColor3 = color:Lerp(WHITE, 0.55)
		UIUtil.Tween(mouthGlow, 0.2, { BackgroundTransparency = 0.1 })
		glowTarget = color
		for _, bar in ipairs(rayBars) do
			bar.BackgroundColor3 = color
		end
		for _, bar in ipairs(bigRayBars) do
			bar.BackgroundColor3 = color:Lerp(WHITE, 0.35)
		end
		bigRaysOn = legendary
		raysTarget = 0.2

		if effectsOn() then
			ctx.Effects.Burst(card, UDim2.fromOffset(cx, chestCY - 12), color, 6 + tierIndex * 4)
		end
		launchSparks(Vector2.new(cx, chestCY - 10), color, SPARK_POOL, 40, 80)

		-- 3) La carte récompense monte
		showReward(tier, tierIndex, color, amount, legendary)
		floatText(Vector2.new(cx, EFFECT_TEXT_Y), amountText, color, legendary and 34 or 26)

		if legendary then
			ctx.Sound.Play("Jackpot", 1)
			ctx.Effects.Flash(color, 0.45)
			ctx.Effects.BigMessage(Locale.T("🏆 %s CHEST! %s", Locale.T(tostring(tier.Name)), amountText), color, 2.8)
			jolt()
			if effectsOn() then
				ctx.Effects.Confetti(90)
			end
		elseif tierIndex >= 3 then
			ctx.Sound.Play("SlotWin", 1.1)
			if effectsOn() then
				ctx.Effects.Confetti(30)
			end
		elseif tierIndex == 2 then
			ctx.Sound.Play("Bonus", 1.2)
		else
			ctx.Sound.Play("Cash", 1)
		end
		return legendary and 3.4 or 2.5
	end

	local function closeChest()
		hideReward()
		raysTarget = 1
		bigRaysOn = false
		charge = 0
		UIUtil.Tween(beam, 0.3, { BackgroundTransparency = 1 })
		UIUtil.Tween(mouthGlow, 0.25, { BackgroundTransparency = 1 })
		if not flipLid(false) then
			return
		end
		ctx.Sound.Play("Bounce", 0.8)
		chestScale.Scale = 0.94
		UIUtil.Tween(chestScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		-- La serrure revient
		lockScale.Scale = 0.2
		fadeLock(0, 0.15)
		UIUtil.Tween(lockScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
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
			showPillMessage(Locale.T("Not yet!"), 1.4)
			return
		end

		opening = true
		setOdds(false)
		setCallout(false)
		oddsButton.Visible = false
		ctx.Sound.Play("Open", 1)

		task.spawn(function()
			local started = os.clock()
			-- Tremblement de plus en plus fort pendant l'appel serveur
			local shaking = true
			task.spawn(function()
				while shaking and ctx.IsAlive() do
					local t = os.clock() - started
					shakeAmount = math.min(9, 1.5 + t * 9)
					charge = math.min(1, t / MIN_SHAKE_TIME)
					chestScale.Scale = 1 + charge * 0.06 + math.sin(t * 30) * 0.015 * charge
					task.wait()
				end
			end)

			local callOk, success, result = pcall(function()
				return ctx.Net.Function("OpenChest"):InvokeServer()
			end)
			local alive = waitAlive(math.max(0, MIN_SHAKE_TIME - (os.clock() - started)))
			shaking = false
			shakeAmount = 0
			if not alive then
				return
			end

			if callOk and success == true and type(result) == "table" then
				local hold = reveal(result)
				if hold <= 0 or not waitAlive(hold) then
					return
				end
				closeChest()
				if not waitAlive(0.3) then
					return
				end
			else
				local message = (callOk and type(result) == "string") and result or Locale.T("The chest is stuck 🔒")
				charge = 0
				chestScale.Scale = 1
				ctx.Sound.Play("Error", 1)
				wobble()
				ctx.Notify(message, Theme.Colors.Red)
			end

			opening = false
			oddsButton.Visible = true
			refreshStock()
		end)
	end

	ctx.Connect(card.Activated, open)
end

return LootBox
