--[[
	Multiverse (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Multiverse

	🪐 Multivers (gains x3, après 8 visites à l'océan) : trois portails
	tourbillonnants (bord arc-en-ciel qui tourne, halo), chacun montrant un
	mini monde parallèle où un autre « toi » clique aussi : une petite
	planète avec un minuscule bouton « Clique-moi » qui s'enfonce, et un
	« +1 » qui s'envole.
	  - monde bonbon (ciel rose, planète menthe) ;
	  - monde océan (nuit bleue, planète bleue et son voilier) ;
	  - monde lave (ciel violet, planète orange à anneau).
	Chaque portail est posé séparément par Cosmos/Zones (sur les côtés de
	préférence). ≤ 20 images/s, ~17 instances par portail.
]]

local Cosmos = script.Parent:WaitForChild("Cosmos")
local Kit = require(Cosmos:WaitForChild("Kit"))
local Zones = require(Cosmos:WaitForChild("Zones"))

local Multiverse = {}
Multiverse.Slot = "Background"

local ID = "Multiverse"
local BOX = 74
local C = BOX / 2

type World = {
	Name: string,
	SkyTop: Color3,
	SkyBottom: Color3,
	Planet: Color3,
	PlanetDark: Color3,
	Glow: Color3,
	Anchor: Vector2,
}

local WORLDS: { World } = {
	{
		Name = "Candy",
		SkyTop = Color3.fromRGB(255, 170, 214),
		SkyBottom = Color3.fromRGB(255, 214, 236),
		Planet = Color3.fromRGB(150, 236, 200),
		PlanetDark = Color3.fromRGB(80, 196, 160),
		Glow = Color3.fromRGB(255, 120, 200),
		Anchor = Vector2.new(0.14, 0.5),
	},
	{
		Name = "Ocean",
		SkyTop = Color3.fromRGB(28, 40, 110),
		SkyBottom = Color3.fromRGB(70, 110, 200),
		Planet = Color3.fromRGB(90, 190, 255),
		PlanetDark = Color3.fromRGB(40, 110, 220),
		Glow = Color3.fromRGB(80, 170, 255),
		Anchor = Vector2.new(0.86, 0.46),
	},
	{
		Name = "Lava",
		SkyTop = Color3.fromRGB(90, 40, 140),
		SkyBottom = Color3.fromRGB(190, 80, 150),
		Planet = Color3.fromRGB(255, 176, 80),
		PlanetDark = Color3.fromRGB(230, 90, 60),
		Glow = Color3.fromRGB(255, 130, 70),
		Anchor = Vector2.new(0.5, 0.97),
	},
}

local RIM = Kit.Colors({
	0,
	Color3.fromRGB(255, 110, 200),
	0.33,
	Color3.fromRGB(120, 200, 255),
	0.66,
	Color3.fromRGB(190, 130, 255),
	1,
	Color3.fromRGB(255, 110, 200),
})

function Multiverse.Start(ctx)
	Zones.Attach(ctx)
	local random = Random.new()
	local effects = Kit.Effects(ctx)
	local dark = Kit.IsDark(ctx)

	type Portal = {
		Piece: any,
		Content: Frame?,
		Rim: UIGradient?,
		Glow: Frame?,
		Planet: Frame?,
		Button: Frame?,
		Plus: TextLabel?,
		Stars: { Frame },
		Phase: number,
	}
	local portals: { Portal } = {}

	local function buildPortal(portal: Portal, world: World)
		if portal.Content then
			portal.Content:Destroy()
		end
		table.clear(portal.Stars)
		local root = Kit.Box(portal.Piece.Frame, { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		portal.Content = root

		portal.Glow = Kit.Circle(root, C, C, BOX - 2, world.Glow, if dark then 0.72 else 0.8, 1)
		-- Ciel du monde
		local sky = Kit.Circle(root, C, C, 56, Color3.new(1, 1, 1), 0, 2)
		sky.Name = "Sky"
		Kit.Gradient(sky, ColorSequence.new(world.SkyTop, world.SkyBottom), nil, 90)
		for _, spec in ipairs({ { 0.3, 0.28, 4 }, { 0.72, 0.36, 3 } }) do
			local star = Kit.Diamond(root, BOX * spec[1], BOX * spec[2], spec[3], Kit.Rgb(255, 250, 220), 0, 3)
			table.insert(portal.Stars, star)
		end
		-- Planète
		local planet = Kit.Box(root, {
			Name = "Planet",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(C, C + 9),
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			ZIndex = 4,
		})
		portal.Planet = planet
		local ball = Kit.Circle(planet, 14, 14, 28, Color3.new(1, 1, 1), 0, 4)
		Kit.Gradient(ball, ColorSequence.new(world.Planet, world.PlanetDark), nil, 60)
		if world.Name == "Lava" then
			local ringFrame = Kit.Ellipse(planet, 14, 16, 44, 10, Color3.new(1, 1, 1), 1, 5)
			Kit.Stroke(ringFrame, Kit.Rgb(255, 226, 170), 2, 0.1)
		elseif world.Name == "Ocean" then
			-- Petit voilier
			Kit.Box(planet, { Name = "Sail", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(21, 2), Size = UDim2.fromOffset(6, 8), Rotation = 8, Color = Color3.new(1, 1, 1), ZIndex = 5 })
		end
		-- Minuscule bouton « Clique-moi » sur la planète (l'autre toi clique aussi)
		local button = Kit.Box(planet, {
			Name = "TinyButton",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(if world.Name == "Ocean" then 11 else 14, 3),
			Size = UDim2.fromOffset(13, 6),
			Color = Kit.Rgb(236, 236, 240),
			ZIndex = 6,
		})
		Kit.Corner(button, 3)
		Kit.Stroke(button, Kit.Rgb(40, 40, 50), 1, 0)
		portal.Button = button
		local plus = Kit.Text(root, "+1", C, C - 12, 10, Kit.Rgb(255, 236, 120), 7)
		plus.TextTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = Kit.Rgb(70, 40, 100)
		stroke.Thickness = 1
		stroke.Parent = plus
		portal.Plus = plus
		-- Bord tourbillonnant
		local rim, rimStroke = Kit.Ring(root, C, C, 58, Color3.new(1, 1, 1), 4, 0, 8)
		rim.Name = "Rim"
		portal.Rim = Kit.Gradient(rimStroke, RIM, nil, 0)
	end

	local function buildAll()
		for index, portal in ipairs(portals) do
			buildPortal(portal, WORLDS[index])
		end
	end

	local items = {}
	for index, world in ipairs(WORLDS) do
		local piece = Kit.Piece(ctx.Container, "Portal" .. world.Name, BOX, BOX)
		portals[index] = { Piece = piece, Content = nil, Rim = nil, Glow = nil, Planet = nil, Button = nil, Plus = nil, Stars = {}, Phase = random:NextNumber(0, 6) }
		table.insert(items, { W = BOX, H = BOX, Anchor = world.Anchor, MinScale = 0.4, MaxScale = 1.1, Gap = 3 })
	end
	buildAll()
	Kit.WatchTheme(ctx, function(isDark)
		dark = isDark
		buildAll()
	end)

	Zones.Request(ID, items, function(placements)
		for index, portal in ipairs(portals) do
			Kit.Place(portal.Piece, placements[index])
		end
	end)

	Kit.Loop(ctx, 20, function(_dt, t)
		for index, portal in ipairs(portals) do
			if portal.Piece.Placed then
				local rim = portal.Rim
				if rim then
					rim.Rotation = (t * (60 + index * 15) + index * 120) % 360
				end
				local glow = portal.Glow
				if glow then
					glow.BackgroundTransparency = (if dark then 0.72 else 0.8) + 0.08 * math.sin(t * 2 + portal.Phase)
				end
				local planet = portal.Planet
				if planet then
					planet.Position = UDim2.fromOffset(C, C + 9 + math.sin(t * 1.4 + portal.Phase) * 1.5)
				end
				-- Le mini bouton s'enfonce toutes les ~1,6 s, un « +1 » s'envole
				local cycle = (t / 1.6 + portal.Phase) % 1
				local button = portal.Button
				if button then
					button.Size = if cycle < 0.12 then UDim2.fromOffset(14, 4) else UDim2.fromOffset(13, 6)
				end
				local plus = portal.Plus
				if plus and effects then
					plus.Position = UDim2.fromOffset(C + 4, C - 6 - cycle * 16)
					plus.TextTransparency = if cycle < 0.1 then 1 - cycle / 0.1 elseif cycle > 0.6 then (cycle - 0.6) / 0.4 else 0
				end
				for starIndex, star in ipairs(portal.Stars) do
					star.BackgroundTransparency = 0.2 + 0.6 * (0.5 + 0.5 * math.sin(t * 2.5 + starIndex + portal.Phase))
				end
			end
		end
	end)
end

function Multiverse.Stop(_ctx)
	Zones.Release(ID)
end

return Multiverse
