--[[
	Singularity (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Singularity

	🕳️ Singularité (gains x3, après 5 visites à l'océan) : un petit trou noir
	(disque noir, anneau de photons lumineux, halo violet) entouré d'un
	disque d'accrétion orange -> rose -> violet qui tourne (le dégradé
	glisse) ; la moitié avant du disque passe DEVANT le trou, comme sur les
	vraies images. De petites particules tombent en spirale et disparaissent
	dans le trou, des étoiles lointaines s'étirent vers lui, et deux jets
	fins sortent des pôles.
	Calque Background, place donnée par Cosmos/Zones. ≤ 20 images/s,
	~35 instances, particules recyclées.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local Singularity = {}
Singularity.Slot = "Background"

local ID = "Singularity"
local BOX_W, BOX_H = 124, 92
local CX, CY = 62, 46 -- centre du trou
local DISK_W, DISK_H = 118, 30
local PARTICLES = 12
local STREAKS = 4
local OUTER_R, INNER_R = 58, 20

local DISK_COLORS = {
	0,
	Color3.fromRGB(255, 176, 92),
	0.25,
	Color3.fromRGB(255, 104, 150),
	0.5,
	Color3.fromRGB(176, 96, 255),
	0.75,
	Color3.fromRGB(255, 120, 170),
	1,
	Color3.fromRGB(255, 176, 92),
}

function Singularity.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local dark = Kit.IsDark(ctx)
	local piece = Kit.Piece(ctx.Container, "BlackHole", BOX_W, BOX_H)

	local content: Frame? = nil
	local diskGradients: { UIGradient } = {}
	local halo: Frame? = nil
	local ring: UIStroke? = nil
	local jets: { UIGradient } = {}
	type Particle = { Frame: Frame, R: number, A: number, Speed: number }
	local particles: { Particle } = {}
	type Streak = { Frame: Frame, Angle: number, D: number }
	local streaks: { Streak } = {}

	local function spawnParticle(p: Particle, fresh: boolean)
		p.R = if fresh then random:NextNumber(INNER_R + 4, OUTER_R) else OUTER_R + random:NextNumber(0, 6)
		p.A = random:NextNumber(0, math.pi * 2)
		p.Speed = random:NextNumber(0.8, 1.3)
	end

	local function build()
		if content then
			content:Destroy()
		end
		table.clear(diskGradients)
		table.clear(jets)
		table.clear(particles)
		table.clear(streaks)
		local root = Kit.Box(piece.Frame, { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		content = root
		local diskSequence = Kit.Colors(DISK_COLORS)
		local diskFade = Kit.Fade({ 0, 1, 0.12, 0.35, 0.5, 0.05, 0.88, 0.35, 1, 1 })

		-- Halo violet (lentille gravitationnelle)
		halo = Kit.Circle(root, CX, CY, 92, Kit.Rgb(150, 90, 255), if dark then 0.8 else 0.84, 1)
		-- Jets polaires
		for _, dir in ipairs({ -1, 1 }) do
			local jet = Kit.Box(root, {
				Name = "Jet",
				AnchorPoint = Vector2.new(0.5, if dir < 0 then 1 else 0),
				Position = UDim2.fromOffset(CX, CY),
				Size = UDim2.fromOffset(4, 40),
				Color = Kit.Rgb(170, 220, 255),
				ZIndex = 2,
			})
			table.insert(jets, Kit.Gradient(jet, nil, if dir < 0 then Kit.Fade({ 0, 1, 1, 0.3 }) else Kit.Fade({ 0, 0.3, 1, 1 }), 90))
		end
		-- Disque arrière (derrière le trou)
		local back = Kit.Ellipse(root, CX, CY, DISK_W, DISK_H, Color3.new(1, 1, 1), 0, 3)
		table.insert(diskGradients, Kit.Gradient(back, diskSequence, diskFade, 0))
		-- Anneau de photons + trou
		local photon
		photon, ring = Kit.Ring(root, CX, CY, 44, Kit.Rgb(255, 226, 180), 2.5, 0.05, 5)
		photon.Name = "PhotonRing"
		local hole = Kit.Circle(root, CX, CY, 40, Kit.Rgb(6, 4, 14), 0, 6)
		hole.Name = "Hole"
		-- Disque avant : moitié basse du même disque, devant le trou
		local clip = Kit.Box(root, {
			Name = "FrontDisk",
			Position = UDim2.fromOffset(CX - DISK_W / 2 - 2, CY),
			Size = UDim2.fromOffset(DISK_W + 4, DISK_H / 2 + 2),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 8,
		})
		local front = Kit.Ellipse(clip, DISK_W / 2 + 2, 0, DISK_W, DISK_H, Color3.new(1, 1, 1), 0, 8)
		table.insert(diskGradients, Kit.Gradient(front, diskSequence, diskFade, 0))

		-- Particules qui tombent en spirale
		for index = 1, PARTICLES do
			local dot = Kit.Box(root, {
				Name = "Dust",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(3, 3),
				Rotation = 45,
				Color = if index % 3 == 0 then Kit.Rgb(255, 240, 210) elseif index % 3 == 1 then Kit.Rgb(255, 170, 110) else Kit.Rgb(255, 130, 190),
				ZIndex = 4,
			})
			local p: Particle = { Frame = dot, R = 0, A = 0, Speed = 1 }
			spawnParticle(p, true)
			table.insert(particles, p)
		end
		-- Étoiles lointaines étirées vers le trou
		for index = 1, STREAKS do
			local line = Kit.Box(root, {
				Name = "Streak",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(10, 2),
				Color = if dark then Kit.Rgb(230, 220, 255) else Kit.Rgb(140, 110, 230),
				ZIndex = 2,
			})
			table.insert(streaks, { Frame = line, Angle = (index - 1) * math.pi / 2 + 0.6, D = random:NextNumber(0, 1) })
		end
	end

	build()
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		build()
	end)

	Zones.Request(ID, {
		{ W = BOX_W, H = BOX_H, Anchor = Vector2.new(0.78, 0.58), MinScale = 0.4, MaxScale = 1.2 },
	}, function(placements)
		Kit.Place(piece, placements[1])
	end)

	Kit.Loop(ctx, 20, function(dt, t)
		if not piece.Placed then
			return
		end
		-- Le disque tourne : le dégradé glisse (même phase devant / derrière)
		local offset = Vector2.new(((t * 0.22) % 1) - 0.5, 0)
		for _, gradient in ipairs(diskGradients) do
			gradient.Offset = offset
		end
		local glow = halo
		if glow then
			glow.BackgroundTransparency = (if dark then 0.8 else 0.84) + 0.05 * math.sin(t * 1.7)
		end
		local photon = ring
		if photon then
			photon.Transparency = 0.05 + 0.25 * (0.5 + 0.5 * math.sin(t * 3.1))
		end
		for index, jet in ipairs(jets) do
			jet.Offset = Vector2.new(0, (if index == 1 then 1 else -1) * (0.08 * math.sin(t * 4 + index)))
		end
		-- Particules : spirale vers l'intérieur (plus vite près du trou)
		local steps = if effects then #particles else math.floor(#particles / 2)
		for index = 1, steps do
			local p = particles[index]
			p.A += dt * p.Speed * (1.2 + 60 / p.R)
			p.R -= dt * p.Speed * (6 + 260 / p.R)
			if p.R <= INNER_R then
				spawnParticle(p, false)
			end
			local sin = math.sin(p.A)
			local frame = p.Frame
			frame.Position = UDim2.fromOffset(CX + math.cos(p.A) * p.R, CY + sin * p.R * 0.28)
			-- devant le trou quand la particule est dans la moitié basse du disque
			frame.ZIndex = if sin > 0 then 9 else 4
			frame.BackgroundTransparency = if p.R < INNER_R + 6 then 0.6 else 0
		end
		-- Traînées : glissent vers le trou puis réapparaissent au bord
		for _, s in ipairs(streaks) do
			s.D = (s.D + dt * 0.35) % 1
			local distance = 62 - s.D * 36
			local frame = s.Frame
			frame.Position = UDim2.fromOffset(CX + math.cos(s.Angle) * distance, CY + math.sin(s.Angle) * distance * 0.8)
			frame.Rotation = math.deg(math.atan2(math.sin(s.Angle) * 0.8, math.cos(s.Angle)))
			frame.Size = UDim2.fromOffset(6 + s.D * 12, 2)
			frame.BackgroundTransparency = if s.D < 0.2 then 1 - s.D / 0.2 else 0.2 + (s.D - 0.2) * 0.9
		end
	end)
end

function Singularity.Stop(_ctx)
	Zones.Release(ID)
end

return Singularity
