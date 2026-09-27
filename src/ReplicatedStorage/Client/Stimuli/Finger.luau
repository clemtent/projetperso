--[[
	Finger (ModuleScript - stimulus) — amélioration "Doigt musclé" (15 niveaux)
	Emplacement : ReplicatedStorage > Client > Stimuli > Finger

	Une petite main kawaii posée juste à côté du gros bouton (placée par
	Gear/GearLayout dans l'espace libre, jamais sur le compteur, les pastilles
	ou une carte). Elle vise le bouton et le TAPE à chaque clic : le bout du
	doigt vient toucher le bord du bouton (étoile d'impact + traits de vitesse).
	Chaque niveau la rend plus musclée et plus stylée (voir Gear/HandArt :
	joues, plis, bandeau éponge, bague, vernis, muscles, sueur, diamant,
	veines, bandeau doré, aura, lunettes...). Niveau 15 : de temps en temps
	elle "flexe" fièrement (et tous les 12 clics).
	Aucune animation au repos, sauf un petit geste toutes les 5 à 9 s.
]]

local Gear = script.Parent:WaitForChild("Gear")
local GearKit = require(Gear:WaitForChild("GearKit"))
local GearPiece = require(Gear:WaitForChild("GearPiece"))
local HandArt = require(Gear:WaitForChild("HandArt"))

local Finger = {}
Finger.Slot = "Background" -- sous l'interface (effets de clic : calque Overlay)

local FOOTPRINT = 90
local TOUCH_RANGE = 46 -- au-delà (en px), le doigt fait juste un petit "coup" dans le vide

local active: { [any]: any } = {}

function Finger.Start(ctx)
	local animator = GearKit.Animator(ctx)
	local piece = GearPiece.new(ctx, {
		Id = "Finger",
		Size = Vector2.new(FOOTPRINT, FOOTPRINT),
		Priority = 1,
		MinScale = 0.42,
		MaxScale = 1,
		Near = 60,
		GlowColor = Color3.fromRGB(255, 236, 214),
		ContainerZ = 97,
		Anchor = function(button, _canvas)
			-- À gauche du bouton, un peu plus bas : le doigt vise vers le haut / la droite
			return Vector2.new(button.X0 - 50, (button.Y0 + button.Y1) / 2 + 6)
		end,
	}, animator)
	active[ctx] = piece

	-- Cadre qui vise le bouton (tourné) ; la main est dessinée dedans
	local aim = Instance.new("Frame")
	aim.Name = "Aim"
	aim.BackgroundTransparency = 1
	aim.AnchorPoint = Vector2.new(0.5, 0.5)
	aim.Position = UDim2.fromScale(0.5, 0.5)
	aim.Size = UDim2.fromOffset(FOOTPRINT, FOOTPRINT)
	aim.ZIndex = 3
	aim.Parent = piece.Content

	-- Traits de vitesse (derrière la main, le long de l'axe du doigt)
	local speedLines = {}
	for index = 1, 3 do
		local line = GearKit.Box(aim, 0, 0, 2.5, 16, Color3.fromRGB(255, 255, 255), {
			Name = "Speed",
			Anchor = Vector2.new(0.5, 0.5),
			Radius = "round",
			Z = 1,
			Visible = false,
		})
		line.Position = UDim2.fromOffset(FOOTPRINT / 2 + (index - 2) * 22, FOOTPRINT / 2 + 34 + math.abs(index - 2) * -6)
		table.insert(speedLines, line)
	end

	local hand: HandArt.Hand
	local aimAngle = 0
	local dir = Vector2.new(0, -1)
	local reach = 12
	local touching = false
	local lastTap = 0
	local taps = 0

	-- Impact (sur la toile) : étoile + anneau, réutilisés
	local impact = GearKit.Star(piece.FX, 0, 0, 22, Color3.fromRGB(255, 236, 120), 20)
	impact.Visible = false
	local ring = Instance.new("Frame")
	ring.Name = "ImpactRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 19
	ring.Visible = false
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(255, 255, 255)
	ringStroke.Thickness = 2
	ringStroke.Parent = ring
	ring.Parent = piece.FX

	local dropBase: { [Frame]: UDim2 } = {}

	local function buildHand(level: number)
		if hand then
			animator:Stop("tap", true)
			animator:Stop("flex", true)
			animator:Stop("drops")
			hand.Root:Destroy()
		end
		hand = HandArt.Build(aim, { Level = level })
		if hand.Face then
			hand.Face.Rotation = -aimAngle
		end
		table.clear(dropBase)
		for _, drop in ipairs(hand.Drops) do
			dropBase[drop] = drop.Position
		end
	end
	buildHand(math.max(1, piece.Level))

	-- Vise le bouton depuis la place donnée par la mise en page
	local function aimAt(placement)
		local reachCanvas
		aimAngle, dir, reachCanvas, touching = HandArt.Aim(placement, hand and hand.ArtScale.Scale or 1, TOUCH_RANGE)
		aim.Rotation = aimAngle
		if hand and hand.Face then
			hand.Face.Rotation = -aimAngle
		end
		reach = reachCanvas / math.max(placement.Scale, 0.05)
	end

	piece.OnPlaced = function(placement, _first)
		aimAt(placement)
	end

	piece.OnLevel = function(level, _previous)
		buildHand(level)
		local placement = piece.Placement
		if placement then
			aimAt(placement)
		end
	end

	-- Pose "flex" (niveau 15) : la main gonfle fièrement, étincelles
	local function flex()
		if not piece:IsShown() or not hand then
			return
		end
		local base = HandArt.Features(piece.Level).Scale
		local artScale = hand.ArtScale
		animator:Play("flex", 0.9, function(t)
			artScale.Scale = base * (1 + 0.16 * GearKit.Bump(math.min(1, t * 1.6)))
			aim.Rotation = aimAngle + math.sin(t * math.pi * 3) * 7 * (1 - t)
		end, function()
			artScale.Scale = base
			aim.Rotation = aimAngle
		end)
		piece:Celebrate()
	end

	-- Le TAP : le doigt frappe le bouton puis revient
	local function tap()
		if not piece:IsShown() or not hand then
			return
		end
		lastTap = os.clock()
		taps += 1
		local placement = piece.Placement :: any
		local level = piece.Level
		local strikeEnd, holdEnd = 0.28, 0.42
		local showLines = level >= 2 and GearKit.EffectsOn(ctx)
		animator:Play("tap", 0.2, function(t)
			local offset
			if t < strikeEnd then
				offset = GearKit.Ease.InQuad(t / strikeEnd)
			elseif t < holdEnd then
				offset = 1
			else
				offset = 1 - GearKit.Ease.OutQuad((t - holdEnd) / (1 - holdEnd))
			end
			local d = dir * reach * offset
			-- (le cadre est tourné : on déplace dans le repère de la toile, pas du cadre)
			aim.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
			HandArt.Squash(hand, (touching and t >= strikeEnd * 0.9 and t < holdEnd + 0.12) and 1 or 0)
			for _, line in ipairs(speedLines) do
				line.Visible = showLines and t < holdEnd
				line.BackgroundTransparency = 0.25 + 0.6 * math.min(1, t / holdEnd)
			end
		end, function()
			aim.Position = UDim2.fromScale(0.5, 0.5)
			HandArt.Squash(hand, 0)
			for _, line in ipairs(speedLines) do
				line.Visible = false
			end
		end)

		-- Impact au bout du doigt
		if GearKit.EffectsOn(ctx) then
			local center = Vector2.new(placement.CX, placement.CY)
			local tipDistance = (HandArt.Size / 2 - HandArt.TipY) * hand.ArtScale.Scale * placement.Scale
			local hit = center + dir * (tipDistance + reach * placement.Scale)
			local big = level >= 10
			local color = level >= 12 and Color3.fromRGB(255, 205, 60) or Color3.fromRGB(255, 240, 150)
			animator:Play("impact", 0.3, function(t)
				local k = math.clamp((t - 0.18) / 0.82, 0, 1)
				local visible = t >= 0.18 and k < 1
				impact.Visible = visible
				ring.Visible = visible and (touching or big)
				if not visible then
					return
				end
				local s = (big and 30 or 22) * (0.5 + 0.8 * GearKit.Ease.OutQuad(k))
				impact.Position = UDim2.fromOffset(hit.X, hit.Y)
				impact.Size = UDim2.fromOffset(s * (1 - k * 0.4), s * (1 - k * 0.4))
				impact.Rotation = 45 * k
				for _, arm in ipairs(impact:GetChildren()) do
					if arm:IsA("Frame") then
						arm.BackgroundColor3 = color
						arm.BackgroundTransparency = k
					end
				end
				local r = 10 + 30 * GearKit.Ease.OutQuad(k)
				ring.Position = UDim2.fromOffset(hit.X, hit.Y)
				ring.Size = UDim2.fromOffset(r, r)
				ringStroke.Transparency = 0.2 + 0.8 * k
				ringStroke.Color = color
			end, function()
				impact.Visible = false
				ring.Visible = false
			end)
		end

		-- Gouttes de sueur qui sautillent
		if #hand.Drops > 0 then
			local drops = hand.Drops
			animator:Play("drops", 0.35, function(t)
				for index, drop in ipairs(drops) do
					local base = dropBase[drop]
					if base then
						drop.Position = base - UDim2.fromOffset(0, GearKit.Bump(t) * (3 + index))
					end
				end
			end)
		end

		if level >= 15 and taps % 12 == 0 then
			task.delay(0.22, flex)
		end
	end

	ctx.Connect(ctx.State.Clicked, function()
		if ctx.IsVisible() then
			tap()
		end
	end)

	-- Petite vie au repos : un geste de temps en temps (seulement si on ne clique pas)
	GearKit.Every(ctx, 5, 9, function()
		if not piece:IsShown() or os.clock() - lastTap < 2.5 then
			return
		end
		if piece.Level >= 15 then
			flex()
		else
			animator:Play("wiggle", 0.6, function(t)
				aim.Rotation = aimAngle + math.sin(t * math.pi * 2) * 8 * (1 - t)
			end, function()
				aim.Rotation = aimAngle
			end)
		end
	end)
end

function Finger.Stop(ctx)
	local piece = active[ctx]
	active[ctx] = nil
	if piece then
		piece:Destroy()
	end
end

return Finger
