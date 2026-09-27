--[[
	SleepMode (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > SleepMode

	😴 Mode veille (gains hors-ligne, 5 niveaux, conservé après l'océan) :
	un hublot de nuit (bulle bleu nuit) où dort une lune en croissant (œil
	fermé, joues roses, petit sourire), qui respire doucement ; des « z »
	s'envolent de sa tête et des étoiles scintillent autour.
	Chaque niveau ajoute quelque chose :
	  1 : lune + 4 étoiles + 1 « z »
	  2 : 6 étoiles, « zZ »
	  3 : un nuage-oreiller sous le hublot
	  4 : 9 étoiles, « zzZ », halo de lune plus fort
	  5 : 12 étoiles, bord doré et étoiles filantes
	Calque Background (sous les cartes), place donnée par Cosmos/Zones (de
	préférence en haut à droite ; en fin de partie, dans un espace libre).
	Clair / sombre : couleurs adaptées (reconstruit au changement de thème).
	Animation ≤ 20 images/s, ~50 instances au niveau 5, rien créé par image.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local SleepMode = {}
SleepMode.Slot = "Background"

local UPGRADE_ID = "SleepMode"
local BOX_W, BOX_H = 120, 130

-- Géométrie (pixels "design" dans la boîte 120 x 130)
local BUBBLE = { X = 56, Y = 76, D = 100 }
local MOON = { X = 50, Y = 78, D = 58 }
local BITE = { X = 70, Y = 64, D = 50 }

-- Étoiles dans le ciel du hublot (hors du croissant) : x, y, taille
local STARS = {
	{ 86, 48, 6 },
	{ 28, 55, 4 },
	{ 96, 72, 5 },
	{ 66, 50, 3 },
	{ 90, 98, 4 },
	{ 40, 36, 4 },
	{ 84, 76, 3 },
	{ 58, 33, 5 },
	{ 16, 78, 3 },
	{ 98, 88, 3 },
	{ 80, 110, 4 },
	{ 74, 39, 3 },
}

local function starCount(level: number): number
	return ({ 4, 6, 6, 9, 12 })[math.clamp(level, 1, 5)]
end

local function zCount(level: number): number
	return if level >= 4 then 3 elseif level >= 2 then 2 else 1
end

function SleepMode.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local piece = Kit.Piece(ctx.Container, "SleepMoon", BOX_W, BOX_H)
	local level = math.clamp(ctx.GetLevel(UPGRADE_ID), 1, 5)
	local dark = Kit.IsDark(ctx)

	-- Éléments animés (remplis par build)
	local content: Frame? = nil
	local stars: { { Frame: Frame, Phase: number, Speed: number } } = {}
	local zs: { { Label: TextLabel, Base: number, Offset: number } } = {}
	local moonGroup: Frame? = nil
	local halo: Frame? = nil
	local haloBase = 0.8
	local shooting: Frame? = nil
	local shootClock = 0
	local shootNext = 2.5

	local function build()
		if content then
			content:Destroy()
		end
		table.clear(stars)
		table.clear(zs)
		shooting = nil

		local ink = Kit.Ink(dark)
		local root = Kit.Box(piece.Frame, {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		})
		content = root

		-- Lueur de lune autour du hublot
		Kit.Circle(root, BUBBLE.X, BUBBLE.Y, BUBBLE.D + 18, Kit.Rgb(255, 232, 160), if dark then 0.78 else 0.7, 1)

		-- Hublot de nuit (dégradé bleu nuit -> violet)
		local skyTop = Kit.Rgb(30, 36, 92)
		local skyBottom = Kit.Rgb(72, 48, 132)
		local bubble = Kit.Circle(root, BUBBLE.X, BUBBLE.Y, BUBBLE.D, Color3.new(1, 1, 1), 0, 2)
		Kit.Gradient(bubble, ColorSequence.new(skyTop, skyBottom), nil, 90)
		local rimColor = if level >= 5 then Kit.Rgb(255, 208, 102) elseif dark then Kit.Rgb(196, 186, 255) else Kit.Rgb(150, 136, 226)
		Kit.Stroke(bubble, rimColor, if level >= 5 then 3 else 2, if dark then 0.15 else 0)

		-- Étoiles du hublot
		for index = 1, starCount(level) do
			local spec = STARS[index]
			local star = Kit.Diamond(root, spec[1], spec[2], spec[3], Kit.Rgb(255, 246, 204), 0, 3)
			table.insert(stars, { Frame = star, Phase = random:NextNumber(0, math.pi * 2), Speed = random:NextNumber(1.2, 2.6) })
		end

		-- Étoile filante (niveau 5)
		if level >= 5 then
			local streak = Kit.Box(root, {
				Name = "ShootingStar",
				AnchorPoint = Vector2.new(1, 0.5),
				Size = UDim2.fromOffset(26, 2),
				Rotation = 28,
				Color = Kit.Rgb(255, 250, 225),
				Alpha = 1,
				ZIndex = 3,
			})
			Kit.Gradient(streak, nil, Kit.Fade({ 0, 1, 0.8, 0.2, 1, 0 }), 0)
			shooting = streak
		end

		-- Lune (groupe qui "respire")
		local group = Kit.Box(root, {
			Name = "Moon",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 4,
		})
		moonGroup = group
		haloBase = if level >= 4 then 0.72 else 0.8
		halo = Kit.Circle(group, MOON.X, MOON.Y, MOON.D + 16, Kit.Rgb(255, 236, 170), haloBase, 4)
		local moon = Kit.Circle(group, MOON.X, MOON.Y, MOON.D, Color3.new(1, 1, 1), 0, 5)
		Kit.Gradient(moon, ColorSequence.new(Kit.Rgb(255, 244, 196), Kit.Rgb(255, 208, 110)), nil, 45)
		-- "Morsure" couleur du ciel : même dégradé que le hublot à cette hauteur
		local top = (BITE.Y - BITE.D / 2 - (BUBBLE.Y - BUBBLE.D / 2)) / BUBBLE.D
		local bottom = (BITE.Y + BITE.D / 2 - (BUBBLE.Y - BUBBLE.D / 2)) / BUBBLE.D
		local bite = Kit.Circle(group, BITE.X, BITE.Y, BITE.D, Color3.new(1, 1, 1), 0, 6)
		Kit.Gradient(bite, ColorSequence.new(skyTop:Lerp(skyBottom, top), skyTop:Lerp(skyBottom, bottom)), nil, 90)
		-- Visage endormi (sur la partie épaisse du croissant)
		local face = Kit.Rgb(122, 84, 60)
		Kit.Arc(group, 39, 80, 11, 8, face, 2, 7)
		Kit.Arc(group, 46, 91, 7, 5, face, 1.5, 7)
		Kit.Circle(group, 31, 91, 8, Kit.Rgb(255, 138, 160), 0.35, 7)

		-- Nuage-oreiller (niveau 3+)
		if level >= 3 then
			local cloud = if dark then Kit.Rgb(226, 222, 255) else Color3.new(1, 1, 1)
			for _, spec in ipairs({ { 36, 118, 30 }, { 58, 122, 36 }, { 82, 118, 28 } }) do
				local puff = Kit.Circle(root, spec[1], spec[2], spec[3], cloud, 0, 8)
				if not dark then
					Kit.Stroke(puff, Kit.Rgb(196, 188, 240), 1.5, 0)
				end
			end
		end

		-- « z » qui s'envolent
		local zColor = Kit.Rgb(240, 236, 255)
		for index = 1, zCount(level) do
			local label = Kit.Text(root, if index == 3 then "Z" else "z", 64, 44, 11 + index * 3, zColor, 9)
			local stroke = Instance.new("UIStroke")
			stroke.Color = if dark then Kit.Rgb(60, 48, 120) else ink
			stroke.Thickness = 1.5
			stroke.Parent = label
			label.TextTransparency = 1
			table.insert(zs, { Label = label, Base = 11 + index * 3, Offset = (index - 1) / 3 })
		end
	end

	build()
	Kit.WatchLevel(ctx, UPGRADE_ID, function(newLevel)
		level = math.clamp(newLevel, 1, 5)
		build()
		Kit.Bump(piece)
	end)
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		build()
	end)

	Zones.Request(UPGRADE_ID, {
		{ W = BOX_W, H = BOX_H, Anchor = Vector2.new(0.86, 0.2), MinScale = 0.5, MaxScale = 1.3 },
	}, function(placements)
		Kit.Place(piece, placements[1])
	end)

	-- Animation (20 images/s)
	local effects = Kit.Effects(ctx)
	Kit.Loop(ctx, 20, function(dt, t)
		if not piece.Placed then
			return
		end
		-- Étoiles qui scintillent
		for _, star in ipairs(stars) do
			star.Frame.BackgroundTransparency = 0.15 + 0.6 * (0.5 + 0.5 * math.sin(t * star.Speed + star.Phase))
		end
		-- Respiration de la lune (bercement lent)
		local group = moonGroup
		if group then
			group.Position = UDim2.fromOffset(0, math.sin(t * 1.3) * 1.6)
		end
		local glow = halo
		if glow then
			glow.BackgroundTransparency = haloBase + 0.08 * math.sin(t * 1.3)
		end
		-- « z » : montent en diagonale, grossissent, s'effacent
		for _, z in ipairs(zs) do
			local p = (t / 3.6 + z.Offset) % 1
			local label = z.Label
			label.Position = UDim2.fromOffset(60 + p * 48 + math.sin(p * 9) * 3, 46 - p * 42)
			label.TextSize = math.floor(z.Base * (0.75 + 0.45 * p) + 0.5)
			label.Rotation = -12 + math.sin(p * 7) * 10
			label.TextTransparency = if p < 0.15 then 1 - p / 0.15 elseif p > 0.7 then (p - 0.7) / 0.3 else 0
		end
		-- Étoile filante (niveau 5)
		local streak = shooting
		if streak and effects then
			shootClock += dt
			if shootClock >= shootNext then
				local p = (shootClock - shootNext) / 0.7
				if p >= 1 then
					shootClock = 0
					shootNext = random:NextNumber(3.5, 6)
					streak.BackgroundTransparency = 1
				else
					streak.Position = UDim2.fromOffset(34 + p * 52, 40 + p * 26)
					streak.BackgroundTransparency = if p < 0.2 then 1 - p / 0.2 elseif p > 0.7 then (p - 0.7) / 0.3 else 0
				end
			end
		end
	end)
end

function SleepMode.Stop(_ctx)
	Zones.Release(UPGRADE_ID)
end

return SleepMode
