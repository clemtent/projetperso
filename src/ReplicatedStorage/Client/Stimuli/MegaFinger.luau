--[[
	MegaFinger (ModuleScript - stimulus) — amélioration "Méga doigt" (10 niveaux)
	Emplacement : ReplicatedStorage > Client > Stimuli > MegaFinger

	Une "tour de force" de fête foraine (placée par Gear/GearLayout) : le palet
	monte d'un cran à chaque clic ; quand il touche la cloche, une MAIN GÉANTE
	descend du haut de l'écran et ÉCRASE le bouton (le bouton s'aplatit, onde
	de choc, poussière, "BAM !"), puis remonte.
	Nombre de clics nécessaires (N, affiché sur la tour) : 40, 34, 28, 24, 20,
	17, 14, 12, 10, 8 (il baisse à chaque niveau).
	La tour change aussi à chaque niveau : bois, rayures de fête foraine,
	acier, ampoules, chrome, or, ampoules arc-en-ciel et cloche en diamant...
	et la main géante grossit, avec plus d'ondes de choc.
	Tout est réutilisé (main géante, anneaux, poussière) ; rien au repos, sauf
	un reflet sur la cloche de temps en temps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Gear = script.Parent:WaitForChild("Gear")
local GearKit = require(Gear:WaitForChild("GearKit"))
local GearPiece = require(Gear:WaitForChild("GearPiece"))
local HandArt = require(Gear:WaitForChild("HandArt"))

local MegaFinger = {}
MegaFinger.Slot = "Background" -- sous l'interface (main géante et effets : calque Overlay)

local W, H = 60, 136
local INK = Color3.fromRGB(56, 36, 50)
local CLICKS = { 40, 34, 28, 24, 20, 17, 14, 12, 10, 8 }
local RAIL_TOP, RAIL_BOTTOM = 30, 110 -- course du palet (y du centre)

local active: { [any]: any } = {}
local smashers: { [any]: () -> () } = {}

local function clicksFor(level: number): number
	return CLICKS[math.clamp(level, 1, #CLICKS)]
end

-- Couleurs de la tour selon le niveau
local function towerStyle(level: number)
	if level >= 9 then
		return { Pole = Color3.fromRGB(255, 206, 70), Base = Color3.fromRGB(230, 160, 40), Bulbs = true, Rainbow = level >= 10 }
	elseif level >= 7 then
		return { Pole = Color3.fromRGB(214, 222, 236), Base = Color3.fromRGB(150, 160, 180), Bulbs = true }
	elseif level >= 5 then
		return { Pole = Color3.fromRGB(176, 186, 204), Base = Color3.fromRGB(110, 118, 136), Bulbs = level >= 6 }
	elseif level >= 3 then
		return { Pole = Color3.fromRGB(255, 255, 255), Base = Color3.fromRGB(220, 60, 70), Stripes = true, Bulbs = level >= 4 }
	end
	return { Pole = Color3.fromRGB(214, 160, 104), Base = Color3.fromRGB(160, 104, 60), Wood = true, Bulbs = level >= 2 }
end

function MegaFinger.Start(ctx)
	local animator = GearKit.Animator(ctx)
	local random = ctx.Random
	local piece = GearPiece.new(ctx, {
		Id = "MegaFinger",
		Size = Vector2.new(W, H),
		Priority = 2,
		MinScale = 0.42,
		MaxScale = 1,
		GlowColor = Color3.fromRGB(255, 226, 190),
		ContainerZ = 1103,
		Anchor = function(button, _canvas)
			-- À droite du bouton (après le bouton 🏠)
			return Vector2.new(button.X1 + 110, (button.Y0 + button.Y1) / 2 + 40)
		end,
	}, animator)
	active[ctx] = piece

	local count = 0
	local smashing = false
	local art: Frame? = nil
	local puck: Frame? = nil
	local bell: Frame? = nil
	local counter: TextLabel? = nil
	local bulbs: { Frame } = {}

	------------------------------------------------------------------
	-- La tour
	------------------------------------------------------------------

	local function puckY(value: number, total: number): number
		return RAIL_BOTTOM - (RAIL_BOTTOM - RAIL_TOP) * math.clamp(value / total, 0, 1)
	end

	local function build(level: number)
		animator:Stop("puck", true)
		animator:Stop("bell", true)
		if art then
			art:Destroy()
		end
		table.clear(bulbs)
		local style = towerStyle(level)
		local total = clicksFor(level)
		local root = Instance.new("Frame")
		root.Name = "Art"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromOffset(W, H)
		root.ZIndex = 2

		-- Socle + cible
		GearKit.Outlined(root, 6, 118, 48, 16, style.Base, {
			Name = "Base",
			Radius = 5,
			Outline = 2.2,
			OutlineColor = INK,
			Z = 4,
			LineZ = 1,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 190, 190)),
		})
		GearKit.Outlined(root, 16, 113, 28, 7, Color3.fromRGB(235, 60, 70), { Name = "Pad", Radius = 3, Outline = 2, OutlineColor = INK, Z = 5, LineZ = 1 })
		GearKit.Box(root, 20, 114, 20, 2, Color3.new(1, 1, 1), { Name = "PadShine", Radius = "round", Transparency = 0.4, Z = 6 })

		-- Mât
		local pole = GearKit.Outlined(root, 21, 22, 18, 94, style.Pole, {
			Name = "Pole",
			Radius = 5,
			Outline = 2.2,
			OutlineColor = INK,
			Z = 3,
			LineZ = 1,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 205, 205)),
			GradientRotation = 0,
		})
		if style.Stripes then
			for index = 0, 5 do
				GearKit.Box(pole, 0, 6 + index * 15, 18, 6, Color3.fromRGB(235, 60, 70), { Name = "Stripe", Z = 4 })
			end
		elseif style.Wood then
			for index = 0, 2 do
				GearKit.Box(pole, 4 + index * 5, 4, 1.2, 86, Color3.fromRGB(150, 96, 56), { Name = "Grain", Transparency = 0.5, Z = 4 })
			end
		end
		-- Graduations (une par clic, au plus 12)
		local marks = math.min(total, 12)
		for index = 1, marks - 1 do
			local y = RAIL_BOTTOM - (RAIL_BOTTOM - RAIL_TOP) * index / marks
			GearKit.Box(root, 23, y - 0.8, index % 3 == 0 and 9 or 6, 1.6, INK, { Name = "Mark", Transparency = 0.25, Z = 5 })
		end
		-- Rail du palet
		GearKit.Box(root, 29, 26, 2, 88, INK, { Name = "Rail", Transparency = 0.35, Z = 5 })

		-- Ampoules sur les côtés
		if style.Bulbs then
			for index = 0, 5 do
				for side = 0, 1 do
					local color = style.Rainbow and GearKit.Rainbow(index / 6 + side * 0.08, 0.6, 1) or Color3.fromRGB(255, 236, 140)
					local bulb = GearKit.Box(root, side == 0 and 16 or 44, 34 + index * 14, 5, 5, color, {
						Name = "Bulb",
						Anchor = Vector2.new(0.5, 0.5),
						Radius = "round",
						Z = 6,
					})
					table.insert(bulbs, bulb)
				end
			end
		end

		-- Cloche
		local bellFrame = Instance.new("Frame")
		bellFrame.Name = "BellHolder"
		bellFrame.BackgroundTransparency = 1
		bellFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		bellFrame.Position = UDim2.fromOffset(30, 14)
		bellFrame.Size = UDim2.fromOffset(30, 26)
		bellFrame.ZIndex = 7
		local bellColor = level >= 10 and Color3.fromRGB(190, 245, 255) or Color3.fromRGB(255, 200, 50)
		local dome = GearKit.Outlined(bellFrame, 3, 1, 24, 22, bellColor, {
			Name = "Bell",
			Radius = 11,
			Outline = 2,
			OutlineColor = INK,
			Z = 3,
			LineZ = 1,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), level >= 10 and Color3.fromRGB(150, 200, 255) or Color3.fromRGB(230, 140, 30)),
		})
		GearKit.Outlined(bellFrame, 0, 19, 30, 6, bellColor:Lerp(Color3.new(0, 0, 0), 0.12), { Name = "Rim", Radius = 3, Outline = 2, OutlineColor = INK, Z = 4, LineZ = 1 })
		GearKit.Shine(dome, 5, 4, 5, 9, 0.3, 5, -15)
		bellFrame.Parent = root

		-- Palet
		local puckFrame = GearKit.Outlined(root, 17, 0, 26, 9, Color3.fromRGB(255, 90, 150), {
			Name = "Puck",
			Radius = "round",
			Outline = 2,
			OutlineColor = INK,
			Z = 9,
			LineZ = 8,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(220, 120, 160)),
		})
		GearKit.Shine(puckFrame, 4, 1.5, 9, 2.5, 0.35, 10)
		local puckLine = root:FindFirstChild("PuckLine") :: Frame?
		puck = puckFrame

		-- Compteur de clics restants (pastille)
		local badge = GearKit.Outlined(root, 42, 2, 18, 18, Color3.fromRGB(45, 40, 62), { Name = "Badge", Radius = "round", Outline = 1.6, OutlineColor = Color3.new(1, 1, 1), Z = 12, LineZ = 11 })
		local label = Instance.new("TextLabel")
		label.Name = "Count"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = ctx.Theme.Fonts.Title
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = 11
		label.ZIndex = 13
		label.Parent = badge
		counter = label

		root.Parent = piece.Content
		art = root
		bell = bellFrame

		-- Place du palet
		local y = puckY(count, total)
		puckFrame.Position = UDim2.fromOffset(17, y - 4.5)
		if puckLine then
			puckLine.Position = UDim2.fromOffset(15, y - 6.5)
		end
		label.Text = tostring(math.max(0, total - count))
	end
	build(math.max(1, piece.Level))

	local function movePuck(to: number, duration: number)
		local frame = puck
		if not frame or not art then
			return
		end
		local line = (art :: Frame):FindFirstChild("PuckLine") :: Frame?
		local from = frame.Position.Y.Offset + 4.5
		animator:Play("puck", duration, function(t)
			local y = from + (to - from) * GearKit.Ease.OutBack(t)
			frame.Position = UDim2.fromOffset(17, y - 4.5)
			if line then
				line.Position = UDim2.fromOffset(15, y - 6.5)
			end
		end)
	end

	local function ringBell()
		local holder = bell
		if not holder then
			return
		end
		local list = bulbs
		animator:Play("bell", 0.6, function(t)
			holder.Rotation = math.sin(t * math.pi * 6) * 18 * (1 - t)
			for index, bulb in ipairs(list) do
				local on = math.floor(t * 12 + index) % 2 == 0
				bulb.BackgroundTransparency = on and 0 or 0.6
			end
		end, function()
			holder.Rotation = 0
			for _, bulb in ipairs(list) do
				bulb.BackgroundTransparency = 0
			end
		end)
	end

	------------------------------------------------------------------
	-- La main géante (réutilisée) + effets de l'écrasement
	------------------------------------------------------------------

	local giant = Instance.new("Frame")
	giant.Name = "GiantHand"
	giant.BackgroundTransparency = 1
	giant.AnchorPoint = Vector2.new(0.5, 0.5)
	giant.Size = UDim2.fromOffset(HandArt.Size, HandArt.Size)
	giant.Rotation = 180
	giant.ZIndex = 40
	giant.Visible = false
	local giantScale = Instance.new("UIScale")
	giantScale.Scale = 2.6
	giantScale.Parent = giant
	local giantHand = HandArt.Build(giant, { Style = "Giant", Level = 15 })
	if giantHand.Face then
		giantHand.Face.Rotation = 180 -- visage à l'endroit
	end
	-- Traits de vitesse au-dessus de la main
	local giantLines = {}
	for index = 1, 4 do
		local line = GearKit.Box(giant, 18 + index * 16, 100, 3, 34, Color3.new(1, 1, 1), {
			Name = "Speed",
			Radius = "round",
			Z = 0,
			Transparency = 0.3,
		})
		table.insert(giantLines, line)
	end
	giant.Parent = piece.FX

	local function shockRing(index: number)
		local ring = Instance.new("Frame")
		ring.Name = "Shock" .. index
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 38
		ring.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(255, 220, 90)
		stroke.Parent = ring
		ring.Parent = piece.FX
		return ring
	end
	local rings = { shockRing(1), shockRing(2), shockRing(3) }
	local dust = GearKit.Pool(6, function()
		local puff = GearKit.Box(piece.FX, 0, 0, 16, 16, Color3.fromRGB(240, 236, 250), {
			Name = "Dust",
			Anchor = Vector2.new(0.5, 0.5),
			Radius = "round",
			Z = 37,
			Visible = false,
		})
		return puff
	end)

	-- "BAM !" : étoile à 8 branches + texte
	local burst = Instance.new("Frame")
	burst.Name = "Burst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.BackgroundTransparency = 1
	burst.Size = UDim2.fromOffset(84, 84)
	burst.ZIndex = 42
	burst.Visible = false
	for index = 0, 1 do
		GearKit.Box(burst, 42, 42, 60, 60, Color3.fromRGB(255, 215, 50), {
			Name = "Spike",
			Anchor = Vector2.new(0.5, 0.5),
			Rotation = index * 45,
			Radius = 6,
			Z = 42,
			Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 150, 40)),
		})
	end
	local burstLabel = Instance.new("TextLabel")
	burstLabel.Name = "Text"
	burstLabel.BackgroundTransparency = 1
	burstLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	burstLabel.Position = UDim2.fromScale(0.5, 0.5)
	burstLabel.Size = UDim2.fromOffset(84, 30)
	burstLabel.Font = ctx.Theme.Fonts.Title
	burstLabel.Text = Locale.T("BAM!")
	burstLabel.TextSize = 22
	burstLabel.TextColor3 = Color3.fromRGB(235, 40, 60)
	burstLabel.Rotation = -8
	burstLabel.ZIndex = 44
	local burstStroke = Instance.new("UIStroke")
	burstStroke.Color = Color3.new(1, 1, 1)
	burstStroke.Thickness = 2
	burstStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	burstStroke.Parent = burstLabel
	burstLabel.Parent = burst
	local burstScale = Instance.new("UIScale")
	burstScale.Parent = burst
	burst.Parent = piece.FX

	-- Écrasement du bouton : UNE animation (Tween) réutilisée, comme le "squish"
	-- de la colonne centrale (le bouton garde sa taille de repos 1 x 1)
	local squashTween: Tween? = nil
	local squashButton: GuiObject? = nil
	local function squashButtonNow(strength: number)
		local button = GearKit.GetButton()
		if not button then
			return
		end
		local size = button.Size
		-- Seulement si le bouton a sa taille "relative" habituelle (sinon on n'y touche pas)
		if size.X.Offset ~= 0 or size.Y.Offset ~= 0 or size.X.Scale < 0.5 or size.X.Scale > 1.3 then
			return
		end
		if squashButton ~= button or not squashTween then
			squashButton = button
			squashTween = TweenService:Create(
				button,
				TweenInfo.new(0.55, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(1, 1) }
			)
		end
		button.Size = UDim2.fromScale(1 + 0.22 * strength, 1 - 0.34 * strength)
		local tween = squashTween
		if tween then
			tween:Play()
		end
	end

	local function smash(level: number)
		local button = GearKit.GetButtonRect()
		if not button then
			smashing = false
			return
		end
		smashing = true
		local effects = GearKit.EffectsOn(ctx)
		local cx = (button.X0 + button.X1) / 2
		local top = button.Y0
		local bw = button.X1 - button.X0
		local scale = 2.3 + level * 0.09 -- la main grossit avec le niveau
		giantScale.Scale = scale
		local tip = (HandArt.Size / 2 - HandArt.TipY) * scale
		local hitY = top - tip + 7 -- le bout du doigt enfonce un peu le bouton
		local startY = -HandArt.Size * scale * 0.6
		local ringCount = level >= 8 and 3 or (level >= 4 and 2 or 1)
		local impactDone = false

		giant.Visible = true
		giant.Position = UDim2.fromOffset(cx, startY)
		for _, line in ipairs(giantLines) do
			line.Visible = effects
		end

		local function impact()
			impactDone = true
			squashButtonNow(math.clamp(0.7 + level * 0.03, 0.7, 1))
			if not effects then
				return
			end
			-- Ondes de choc (ovales aplatis)
			for index = 1, ringCount do
				local ring = rings[index]
				local stroke = ring:FindFirstChild("Stroke") :: UIStroke
				local delay = (index - 1) * 0.08
				stroke.Color = level >= 10 and GearKit.Rainbow(index / 3, 0.7, 1) or Color3.fromRGB(255, 220, 90)
				animator:Play(ring, 0.55 + delay, function(t)
					local k = math.clamp((t * (0.55 + delay) - delay) / 0.55, 0, 1)
					ring.Visible = k > 0 and k < 1
					local e = GearKit.Ease.OutCubic(k)
					local w = bw * (0.9 + 1.5 * e)
					ring.Position = UDim2.fromOffset(cx, (button.Y0 + button.Y1) / 2 + 4)
					ring.Size = UDim2.fromOffset(w, w * 0.34)
					stroke.Transparency = 0.05 + 0.95 * k
					stroke.Thickness = 5 - 3.5 * k
				end, function()
					ring.Visible = false
				end)
			end
			-- Poussière sur les côtés du bouton
			for index = 1, 6 do
				local puff = dust:Next()
				local side = index <= 3 and -1 or 1
				local sx = side < 0 and button.X0 + 8 or button.X1 - 8
				local sy = button.Y1 - 2
				local vx = side * random:NextNumber(26, 60)
				local vy = -random:NextNumber(4, 22)
				local size = random:NextNumber(10, 18)
				animator:Play(puff, 0.6, function(t)
					puff.Visible = t < 1
					local e = GearKit.Ease.OutCubic(t)
					puff.Position = UDim2.fromOffset(sx + vx * e, sy + vy * e)
					local s = size * (0.6 + 0.8 * e)
					puff.Size = UDim2.fromOffset(s, s)
					puff.BackgroundTransparency = 0.15 + 0.85 * t
				end, function()
					puff.Visible = false
				end)
			end
			-- "BAM !"
			local bx = math.min(button.X1 + 26, GearKit.CanvasSize().X - 50)
			burst.Position = UDim2.fromOffset(bx, button.Y0 - 6)
			animator:Play(burst, 0.75, function(t)
				burst.Visible = t < 1
				burstScale.Scale = (0.4 + 0.75 * GearKit.Ease.OutBack(math.min(1, t * 3))) * (level >= 6 and 1.15 or 1)
				burst.Rotation = -6 + 12 * t
				local fade = math.max(0, (t - 0.65) / 0.35)
				burstLabel.TextTransparency = fade
				burstStroke.Transparency = fade
				for _, spike in ipairs(burst:GetChildren()) do
					if spike:IsA("Frame") then
						spike.BackgroundTransparency = fade
					end
				end
			end, function()
				burst.Visible = false
			end)
		end

		-- Descente (0 -> 0.2), appui (0.2 -> 0.45), remontée (0.45 -> 1)
		animator:Play(giant, 1.0, function(t)
			local y
			if t < 0.2 then
				y = startY + (hitY - startY) * GearKit.Ease.InQuad(t / 0.2)
			elseif t < 0.45 then
				if not impactDone then
					impact()
				end
				y = hitY + math.sin((t - 0.2) / 0.25 * math.pi) * 3
			else
				y = hitY + (startY - hitY) * GearKit.Ease.InQuad((t - 0.45) / 0.55)
			end
			giant.Position = UDim2.fromOffset(cx + (t < 0.45 and math.sin(t * 90) * (t > 0.2 and 2 or 0) or 0), y)
			for _, line in ipairs(giantLines) do
				line.BackgroundTransparency = t < 0.2 and 0.3 or 1
			end
			giantHand.ArtScale.Scale = 1
		end, function()
			giant.Visible = false
			smashing = false
		end)
	end

	------------------------------------------------------------------
	-- Clics
	------------------------------------------------------------------

	local function onClick()
		if not piece:IsShown() then
			return
		end
		local level = math.max(1, piece.Level)
		local total = clicksFor(level)
		if smashing then
			return -- (le palet attend que la main soit remontée)
		end
		count += 1
		local label = counter
		if count >= total then
			count = 0
			smashing = true
			movePuck(RAIL_TOP - 8, 0.12)
			ringBell()
			if label then
				label.Text = "0"
			end
			task.delay(0.12, function()
				if ctx.IsAlive() then
					smash(level)
					movePuck(puckY(0, total), 0.5)
					if counter then
						counter.Text = tostring(total)
					end
				end
			end)
		else
			movePuck(puckY(count, total), 0.2)
			if label then
				label.Text = tostring(total - count)
			end
		end
	end

	ctx.Connect(ctx.State.Clicked, function()
		if ctx.IsVisible() then
			onClick()
		end
	end)

	piece.OnLevel = function(level, _previous)
		count = math.min(count, clicksFor(level) - 1)
		build(level)
	end

	-- Au repos : les ampoules clignotent / la cloche brille de temps en temps
	GearKit.Every(ctx, 6, 10, function()
		if piece:IsShown() and not smashing then
			local holder = bell
			if holder then
				animator:Play("bell", 0.5, function(t)
					holder.Rotation = math.sin(t * math.pi * 4) * 6 * (1 - t)
				end, function()
					holder.Rotation = 0
				end)
			end
		end
	end)

	-- (debug / aperçu) : déclenche l'écrasement tout de suite
	smashers[ctx] = function()
		if not smashing then
			smash(math.max(1, piece.Level))
		end
	end
end

function MegaFinger.Stop(ctx)
	local piece = active[ctx]
	active[ctx] = nil
	smashers[ctx] = nil
	if piece then
		piece:Destroy()
	end
end

-- (debug) écrasement immédiat pour tous les MegaFinger actifs
function MegaFinger.DebugSmash()
	for _, smash in pairs(smashers) do
		smash()
	end
end

return MegaFinger
