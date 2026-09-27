--[[
	QuantumFinger (ModuleScript - stimulus) — amélioration "Doigt quantique"
	(10 niveaux, après 3 visites à l'océan)
	Emplacement : ReplicatedStorage > Client > Stimuli > QuantumFinger

	Le doigt est en "superposition" : des copies fantômes translucides (cyan,
	magenta, violet...) l'entourent en éventail, juste DERRIÈRE la vraie main
	(Stimuli/Finger). À chaque clic elles tapent aussi, en cascade, et des
	fantômes se "téléportent" autour du bouton pour le taper d'ailleurs, puis
	disparaissent (réutilisés : rien n'est créé pendant les clics).
	Chaque niveau ajoute quelque chose :
	  1 un fantôme               2 deux fantômes (cyan + magenta)
	  3 + un fantôme téléporté qui tape le bouton d'ailleurs
	  4 trois fantômes           5 effet "glitch" pendant les taps
	  6 quatre fantômes + 2 téléportés       7 champ quantique (anneau + électrons)
	  8 cinq fantômes            9 trois téléportés
	  10 six fantômes, couleurs arc-en-ciel
	Sans le doigt musclé, le doigt quantique prend sa propre place (GearLayout).
	Au repos : de temps en temps, les fantômes "décohèrent" (petit saut).
]]

local Gear = script.Parent:WaitForChild("Gear")
local GearKit = require(Gear:WaitForChild("GearKit"))
local GearLayout = require(Gear:WaitForChild("GearLayout"))
local HandArt = require(Gear:WaitForChild("HandArt"))

local QuantumFinger = {}
QuantumFinger.Slot = "Background" -- sous l'interface (fantômes téléportés : calque Overlay)

local FOOTPRINT = 90
local GLITCH_COLORS = {
	Color3.fromRGB(80, 226, 255),
	Color3.fromRGB(255, 84, 214),
	Color3.fromRGB(158, 116, 255),
	Color3.fromRGB(110, 255, 170),
	Color3.fromRGB(255, 214, 80),
	Color3.fromRGB(255, 120, 120),
}

local active: { [any]: () -> () } = {}

local function ghostCount(level: number): number
	return math.min(6, 1 + math.floor(level / 2))
end

local function teleportCount(level: number): number
	if level >= 9 then
		return 3
	elseif level >= 6 then
		return 2
	elseif level >= 3 then
		return 1
	end
	return 0
end

function QuantumFinger.Start(ctx)
	local animator = GearKit.Animator(ctx)
	local random = ctx.Random
	-- Derrière la vraie main (conteneur du doigt musclé : ZIndex 97), au-dessus
	-- des fonds animés du calque Background
	ctx.Container.ZIndex = 96
	local fx = GearKit.FXLayer(ctx, "Gear_QuantumFingerFX")

	local level = math.max(1, GearKit.Level(ctx, "QuantumFinger"))
	local host: any = nil -- placement suivi (doigt musclé, ou le nôtre)
	local ownPlacement: any = nil
	local ownRegistered = false
	local alive = true

	-- Groupe des fantômes (suit le doigt)
	local group = Instance.new("Frame")
	group.Name = "Gear_QuantumGhosts"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Size = UDim2.fromOffset(FOOTPRINT, FOOTPRINT)
	group.Visible = false
	group.ZIndex = 2
	local groupScale = Instance.new("UIScale")
	groupScale.Parent = group
	group.Parent = ctx.Container

	type GhostSlot = { Aim: Frame, Ghost: HandArt.Ghost, Offset: Vector2, Turn: number }
	local ghosts: { GhostSlot } = {}
	local field: Frame? = nil
	local electrons: { Frame } = {}
	local aimAngle, dir, reach = 0, Vector2.new(0, -1), 12

	-- Fantômes téléportés (sur la toile), réutilisés
	local teleports = {}
	for index = 1, 3 do
		local holder = Instance.new("Frame")
		holder.Name = "Teleport" .. index
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Size = UDim2.fromOffset(HandArt.Size, HandArt.Size)
		holder.Visible = false
		holder.ZIndex = 30
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		local ghost = HandArt.BuildGhost(holder, GLITCH_COLORS[index], 8, "Ghost")
		holder.Parent = fx
		table.insert(teleports, { Holder = holder, Scale = scale, Ghost = ghost })
	end

	local function tintFor(index: number): Color3
		if level >= 10 then
			return GearKit.Rainbow((index - 1) / 6 + 0.5, 0.65, 1)
		end
		return GLITCH_COLORS[(index - 1) % #GLITCH_COLORS + 1]
	end

	-- Éventail des fantômes derrière la main (perpendiculaire à la visée)
	local function layoutGhosts()
		local n = #ghosts
		local perp = Vector2.new(-dir.Y, dir.X)
		for index, slot in ipairs(ghosts) do
			local k = index - (n + 1) / 2
			if n == 1 then
				k = 0.8
			end
			-- (éventail serré : les fantômes restent près de la place du doigt)
			local spread = n <= 1 and 12 or math.min(11, 36 / (n - 1))
			local offset = perp * (k * spread) - dir * (5 + math.abs(k) * 3)
			slot.Offset = offset
			slot.Turn = k * (n <= 2 and 12 or 9)
			slot.Aim.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
			slot.Aim.Rotation = aimAngle + slot.Turn
		end
	end

	local function build()
		for _, slot in ipairs(ghosts) do
			animator:Stop(slot.Aim)
			slot.Aim:Destroy()
		end
		table.clear(ghosts)
		if field then
			field:Destroy()
			field = nil
		end
		table.clear(electrons)
		local fingerLevel = math.max(1, GearKit.Level(ctx, "Finger"))
		local count = ghostCount(level)
		-- Sans vrai doigt : un fantôme de plus, au centre, plus visible
		local standalone = not GearLayout.IsRegistered("Finger")
		for index = 1, count do
			local aimFrame = Instance.new("Frame")
			aimFrame.Name = "GhostAim"
			aimFrame.BackgroundTransparency = 1
			aimFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			aimFrame.Position = UDim2.fromScale(0.5, 0.5)
			aimFrame.Size = UDim2.fromOffset(HandArt.Size, HandArt.Size)
			aimFrame.ZIndex = 2
			local ghost = HandArt.BuildGhost(aimFrame, tintFor(index), fingerLevel)
			ghost.ArtScale.Scale *= 0.94
			aimFrame.Parent = group
			table.insert(ghosts, { Aim = aimFrame, Ghost = ghost, Offset = Vector2.zero, Turn = 0 })
		end
		if standalone then
			local aimFrame = Instance.new("Frame")
			aimFrame.Name = "GhostCore"
			aimFrame.BackgroundTransparency = 1
			aimFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			aimFrame.Position = UDim2.fromScale(0.5, 0.5)
			aimFrame.Size = UDim2.fromOffset(HandArt.Size, HandArt.Size)
			aimFrame.ZIndex = 3
			local ghost = HandArt.BuildGhost(aimFrame, Color3.fromRGB(170, 240, 255), 8)
			for _, part in ipairs(ghost.Parts) do
				part.BackgroundTransparency = 0.12
			end
			aimFrame.Parent = group
			table.insert(ghosts, 1, { Aim = aimFrame, Ghost = ghost, Offset = Vector2.zero, Turn = 0 })
		end
		-- Champ quantique : anneau + électrons
		if level >= 7 then
			local ring = Instance.new("Frame")
			ring.Name = "Field"
			ring.BackgroundTransparency = 1
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromOffset(FOOTPRINT * 1.02, FOOTPRINT * 1.02)
			ring.ZIndex = 1
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = ring
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(120, 230, 255)
			stroke.Thickness = 1.5
			stroke.Transparency = 0.45
			stroke.Parent = ring
			if level >= 10 then
				local gradient = Instance.new("UIGradient")
				gradient.Color = GearKit.RainbowSequence(0, 0.7)
				gradient.Parent = stroke
			end
			for index = 1, 3 do
				local dot = GearKit.Box(ring, 0, 0, 7, 7, GLITCH_COLORS[index], {
					Name = "Electron",
					Anchor = Vector2.new(0.5, 0.5),
					Radius = "round",
					Z = 2,
				})
				GearKit.Box(dot, 2, 2, 3, 3, Color3.new(1, 1, 1), { Name = "Core", Radius = "round", Z = 3 })
				table.insert(electrons, dot)
			end
			ring.Parent = group
			field = ring
		end
		layoutGhosts()
	end

	-- Électrons : sauts quantiques (positions au hasard sur l'anneau)
	local function jumpElectrons()
		for _, dot in ipairs(electrons) do
			local angle = random:NextNumber(0, math.pi * 2)
			dot.Position = UDim2.fromScale(0.5 + 0.5 * math.cos(angle), 0.5 + 0.5 * math.sin(angle))
		end
	end

	local function apply(placement: any)
		host = placement
		if not placement then
			group.Visible = false
			return
		end
		local artScale = HandArt.Features(math.max(1, GearKit.Level(ctx, "Finger"))).Scale
		local reachCanvas
		aimAngle, dir, reachCanvas = HandArt.Aim(placement, artScale)
		reach = reachCanvas / math.max(placement.Scale, 0.05)
		local first = not group.Visible
		group.Visible = true
		group.Position = UDim2.fromOffset(placement.CX, placement.CY)
		groupScale.Scale = placement.Scale
		layoutGhosts()
		jumpElectrons()
		if first then
			animator:Play("appear", 0.5, function(t)
				groupScale.Scale = placement.Scale * math.max(0.01, GearKit.Ease.OutBack(t))
			end)
		end
	end

	-- Hôte : le doigt musclé s'il existe, sinon notre propre place
	local function updateHost()
		if not alive then
			return
		end
		if GearLayout.IsRegistered("Finger") then
			if ownRegistered then
				ownRegistered = false
				ownPlacement = nil
				GearLayout.Unregister("QuantumFinger")
				build()
			end
			apply(GearLayout.GetPlacement("Finger"))
		else
			if not ownRegistered then
				ownRegistered = true
				GearLayout.Register("QuantumFinger", {
					Size = Vector2.new(FOOTPRINT, FOOTPRINT),
					Priority = 1.5,
					MinScale = 0.42,
					MaxScale = 1,
					Near = 60,
					Anchor = function(button, _canvas)
						return Vector2.new(button.X0 - 50, (button.Y0 + button.Y1) / 2 + 6)
					end,
					OnPlace = function(placement)
						ownPlacement = placement
						apply(placement)
					end,
				})
				build()
			end
			apply(ownPlacement)
		end
	end

	build()
	updateHost()
	ctx.Connect(GearLayout.Changed, function(id)
		if id == "Finger" or id == "QuantumFinger" then
			updateHost()
		end
	end)

	-- Nouveau niveau (doigt quantique OU doigt musclé : taille des fantômes)
	local fingerLevel = GearKit.Level(ctx, "Finger")
	ctx.Connect(ctx.State.Changed, function()
		local newLevel = math.max(1, GearKit.Level(ctx, "QuantumFinger"))
		local newFinger = GearKit.Level(ctx, "Finger")
		if newLevel ~= level or newFinger ~= fingerLevel then
			level = newLevel
			fingerLevel = newFinger
			build()
			if host then
				apply(host)
			end
		end
	end)

	-- Tap d'un fantôme téléporté autour du bouton
	local function teleportTap(entry: any, delay: number)
		local button = GearKit.GetButtonRect()
		if not button then
			return
		end
		local center = GearKit.Center(button)
		local halfW, halfH = (button.X1 - button.X0) / 2, (button.Y1 - button.Y0) / 2
		-- Un point sur une ellipse autour du bouton (plutôt au-dessus / sur les côtés)
		local angle = random:NextNumber(-math.pi * 0.95, math.pi * 0.15)
		local position = Vector2.new(center.X + math.cos(angle) * (halfW + 34), center.Y + math.sin(angle) * (halfH + 34))
		local angleToButton = GearKit.AimAngle(position, center)
		local toward = GearKit.AngleDir(angleToButton)
		local holder = entry.Holder
		local scale = entry.Scale
		local ghostScale = 0.62
		local tip = (HandArt.Size / 2 - HandArt.TipY) * entry.Ghost.ArtScale.Scale * ghostScale
		local gap = math.max(0, GearKit.RayToRect(position + toward * tip, toward, button))
		local strike = math.min(gap + 2, 40)
		holder.Rotation = angleToButton
		animator:Play(holder, 0.42 + delay, function(t)
			local k = math.clamp((t * (0.42 + delay) - delay) / 0.42, 0, 1)
			holder.Visible = k > 0 and k < 1
			if k <= 0 then
				return
			end
			local grow = math.min(1, k / 0.18)
			local fade = k > 0.75 and (k - 0.75) / 0.25 or 0
			scale.Scale = ghostScale * (0.4 + 0.6 * grow) * (1 - 0.3 * fade)
			local push = k < 0.45 and GearKit.Ease.InQuad(math.clamp((k - 0.15) / 0.3, 0, 1)) or 1 - GearKit.Ease.OutQuad((k - 0.45) / 0.55)
			local jitter = level >= 5 and (random:NextNumber(-2, 2)) or 0
			local p = position + toward * strike * push
			holder.Position = UDim2.fromOffset(p.X + jitter, p.Y)
			for _, part in ipairs(entry.Ghost.Parts) do
				part.BackgroundTransparency = 0.42 + 0.58 * math.max(fade, 1 - grow)
			end
		end, function()
			holder.Visible = false
		end)
	end

	local function onClick()
		if not host or not group.Visible then
			return
		end
		-- Les fantômes tapent en cascade
		for index, slot in ipairs(ghosts) do
			local aimFrame = slot.Aim
			local delay = index * 0.028
			local base = slot.Offset
			animator:Play(aimFrame, 0.2 + delay, function(t)
				local k = math.clamp((t * (0.2 + delay) - delay) / 0.2, 0, 1)
				local offset
				if k < 0.28 then
					offset = GearKit.Ease.InQuad(k / 0.28)
				elseif k < 0.42 then
					offset = 1
				else
					offset = 1 - GearKit.Ease.OutQuad((k - 0.42) / 0.58)
				end
				local jitter = Vector2.zero
				if level >= 5 and k > 0 and k < 0.6 then
					jitter = Vector2.new(random:NextNumber(-2.5, 2.5), random:NextNumber(-2.5, 2.5))
				end
				local d = base + dir * reach * offset + jitter
				aimFrame.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
			end, function()
				aimFrame.Position = UDim2.new(0.5, base.X, 0.5, base.Y)
			end)
		end
		if #electrons > 0 then
			jumpElectrons()
		end
		if GearKit.EffectsOn(ctx) then
			for index = 1, teleportCount(level) do
				teleportTap(teleports[index], (index - 1) * 0.05)
			end
		end
	end

	ctx.Connect(ctx.State.Clicked, function()
		if ctx.IsVisible() then
			onClick()
		end
	end)

	-- Au repos : décohérence (les fantômes sautent un instant)
	GearKit.Every(ctx, 3, 5, function()
		if not host or not group.Visible then
			return
		end
		for _, slot in ipairs(ghosts) do
			local aimFrame = slot.Aim
			local base = slot.Offset
			local shift = Vector2.new(random:NextNumber(-5, 5), random:NextNumber(-5, 5))
			animator:Play(aimFrame, 0.3, function(t)
				local on = t < 0.5
				local d = base + (on and shift or Vector2.zero)
				aimFrame.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
				aimFrame.Rotation = aimAngle + slot.Turn + (on and shift.X or 0)
			end, function()
				aimFrame.Position = UDim2.new(0.5, base.X, 0.5, base.Y)
				aimFrame.Rotation = aimAngle + slot.Turn
			end)
		end
		jumpElectrons()
	end)

	active[ctx] = function()
		alive = false
		if ownRegistered then
			ownRegistered = false
			GearLayout.Unregister("QuantumFinger")
		end
		if fx.Parent then
			fx:Destroy()
		end
	end
end

function QuantumFinger.Stop(ctx)
	local cleanup = active[ctx]
	active[ctx] = nil
	if cleanup then
		cleanup()
	end
end

return QuantumFinger
