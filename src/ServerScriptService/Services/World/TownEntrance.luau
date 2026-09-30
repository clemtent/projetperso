--[[
	TownEntrance (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownEntrance

	🏰 L'ENTRÉE de Dopamine Town (v9.4), sur l'axe +Z (emplacement 0) :
	  - la GRANDE PORTE : deux tours en pierre (socle, meurtrières, corniche,
	    toit pointu, drapeaux), arche en voussoirs avec clé de voûte en cœur,
	    fronton "DOPAMINE TOWN" lisible des deux côtés, cadre néon, cœur
	    lumineux, lanternes (vraies lumières), murets et piliers de chaque côté ;
	  - la PLACE D'ACCUEIL (entre la porte et le boulevard) : pavage, rosace
	    d'apparition, panneau "Bienvenue", PLAN de la ville avec le nom des
	    propriétaires (mis à jour par TownMap), jardinières, arbres, bancs,
	    lampadaires, arceaux à vélos, haies ;
	  - dehors : route d'arrivée, rond-point, abribus + bus qui vient de
	    déposer les joueurs, parking avec voitures.
	Le joueur apparaît juste à l'intérieur de la porte et regarde l'avenue
	(WorldLayout.EntranceCFrame).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)
local TownVehicles = require(script.Parent.TownVehicles) -- (v9.7, VEHICLES97) bus, 2-roues
local TownStreets = require(script.Parent.TownStreets) -- (v9.9, CITY99) tronçons des routes réalistes (client)

local TownEntrance = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part

local WALK_Y = WorldLayout.WALK_Y
local ROAD_Y = WorldLayout.ROAD_Y

local PLAZA_HALF = 38 -- demi-largeur de la place d'accueil
local OPENING = 13 -- demi-largeur du passage sous l'arche
local TOWER = 9 -- largeur d'une tour

export type MapBoard = {
	Labels: { [number]: TextLabel },
	Markers: { [number]: Frame },
}

----------------------------------------------------------------------
-- La grande porte
----------------------------------------------------------------------

local function tower(model: Instance, cf: CFrame, flagColor: Color3)
	local stone = Color3.fromRGB(246, 232, 218)
	local trim = Color3.fromRGB(255, 196, 214)
	local roof = Color3.fromRGB(150, 116, 206)
	part(model, "TowerPlinth", Vector3.new(TOWER + 2, 3, TOWER + 2), cf * CFrame.new(0, 1.5, 0), C.StoneDark, M.Granite, "solid")
	part(model, "Tower", Vector3.new(TOWER, 26, TOWER), cf * CFrame.new(0, 16, 0), stone, M.Limestone, "solid")
	part(model, "TowerBand", Vector3.new(TOWER + 0.6, 1, TOWER + 0.6), cf * CFrame.new(0, 13, 0), trim, M.Marble, "deco")
	part(model, "TowerCornice", Vector3.new(TOWER + 1.6, 1.4, TOWER + 1.6), cf * CFrame.new(0, 29.7, 0), trim, M.Marble, "decoS")
	-- créneaux
	for _, x in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			part(model, "Merlon", Vector3.new(2.2, 2.2, 2.2), cf * CFrame.new(x * (TOWER / 2 - 0.3), 31.5, z * (TOWER / 2 - 0.3)), stone, M.Limestone, "deco")
		end
	end
	-- toit pointu (deux paires de coins) + drapeau
	for r = 0, 1 do
		local rot = CFrame.Angles(0, r * math.pi / 2, 0)
		TownKit.Wedge(model, "Spire", Vector3.new(TOWER, 9, TOWER / 2), cf * CFrame.new(0, 35.1, 0) * rot * CFrame.new(0, 0, -TOWER / 4), roof, M.Slate, "decoS")
		TownKit.Wedge(model, "Spire", Vector3.new(TOWER, 9, TOWER / 2), cf * CFrame.new(0, 35.1, 0) * rot * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -TOWER / 4), roof, M.Slate, "decoS")
	end
	TownKit.Column(model, "FlagPole", (cf * CFrame.new(0, 39.4, 0)).Position, 7, 0.3, C.MetalLight, M.Metal, "deco")
	part(model, "Flag", Vector3.new(4.6, 2.8, 0.15), cf * CFrame.new(2.4, 44.8, 0), flagColor, M.Fabric, "deco")
	-- meurtrières (des deux côtés)
	for _, z in ipairs({ -1, 1 }) do
		for _, y in ipairs({ 19, 24.5 }) do
			part(model, "Slit", Vector3.new(0.9, 3, 0.2), cf * CFrame.new(0, y, z * (TOWER / 2 + 0.05)), C.Ink, M.SmoothPlastic, "deco")
		end
		part(model, "Crest", Vector3.new(3.4, 3.4, 0.3), cf * CFrame.new(0, 8.5, z * (TOWER / 2 + 0.1)) * CFrame.Angles(0, 0, math.rad(45)), C.Pink, M.Marble, "deco")
	end
end

local function lantern(model: Instance, cf: CFrame, withLight: boolean)
	part(model, "LanternArm", Vector3.new(0.3, 0.3, 2.2), cf * CFrame.new(0, 0, -1.1), C.Metal, M.Metal, "deco")
	part(model, "LanternTop", Vector3.new(1.6, 0.5, 1.6), cf * CFrame.new(0, -0.4, -2.2), C.Metal, M.Metal, "deco")
	-- (v9.6 : verre mat le jour, Neon la nuit seulement ; lumière 30 / 1.6 -> 18 / 0.9)
	local glow = TownKit.Glow(part(model, "LanternGlow", Vector3.new(1.1, 1.8, 1.1), cf * CFrame.new(0, -1.6, -2.2), C.Glow, M.SmoothPlastic, "deco"))
	part(model, "LanternBase", Vector3.new(1.4, 0.3, 1.4), cf * CFrame.new(0, -2.6, -2.2), C.Metal, M.Metal, "deco")
	if withLight then
		TownKit.Light(glow, C.Glow, 18, 0.9)
	end
end

local function gate(folder: Instance, gcf: CFrame)
	local model = TownKit.Model(folder, "Gate")
	local towerX = OPENING + TOWER / 2
	for _, sx in ipairs({ -1, 1 }) do
		tower(model, gcf * CFrame.new(sx * towerX, 0, 0), sx < 0 and C.Pink or C.Lilac)
		-- lanternes côté ville et côté route
		for _, z in ipairs({ -1, 1 }) do
			local face = gcf * CFrame.new(sx * towerX, 11.5, z * (TOWER / 2)) * CFrame.Angles(0, z > 0 and math.pi or 0, 0)
			lantern(model, face, z < 0)
		end
		-- muret + pilier au bout
		local wallLen = PLAZA_HALF - (towerX + TOWER / 2) + 6
		local wx = sx * (towerX + TOWER / 2 + wallLen / 2)
		part(model, "Wall", Vector3.new(wallLen, 6, 2.4), gcf * CFrame.new(wx, 3, 0), Color3.fromRGB(246, 232, 218), M.Limestone, "solid")
		part(model, "WallCap", Vector3.new(wallLen, 0.6, 3), gcf * CFrame.new(wx, 6.3, 0), Color3.fromRGB(255, 196, 214), M.Marble, "deco")
		local px = sx * (towerX + TOWER / 2 + wallLen + 1.5)
		part(model, "Pillar", Vector3.new(3, 8, 3), gcf * CFrame.new(px, 4, 0), Color3.fromRGB(246, 232, 218), M.Limestone, "solid")
		TownKit.Ball(model, "PillarBall", (gcf * CFrame.new(px, 9, 0)).Position, 2.4, C.Pink, M.Marble, "deco")
	end
	-- arche (9 voussoirs sur un demi-cercle) + clé de voûte en cœur
	local spring = 15
	local radius = OPENING
	local n = 9
	for i = 0, n - 1 do
		local a0 = i / n * math.pi
		local a1 = (i + 1) / n * math.pi
		local p0 = gcf * Vector3.new(math.cos(a0) * radius, spring + math.sin(a0) * radius, 0)
		local p1 = gcf * Vector3.new(math.cos(a1) * radius, spring + math.sin(a1) * radius, 0)
		local mid = (p0 + p1) / 2
		local out = (mid - (gcf * Vector3.new(0, spring, 0))).Unit
		-- (v9.6 z-fighting : les voussoirs se chevauchent de 0.3 ; profondeur
		-- alternée 4 / 4.12 pour que leurs faces avant / arrière ne soient pas confondues)
		local block = part(model, "Voussoir", Vector3.new((p1 - p0).Magnitude + 0.3, 2.6, i % 2 == 0 and 4.12 or 4), CFrame.fromMatrix(mid + out * 1.1, (p1 - p0).Unit, out), i % 2 == 0 and Color3.fromRGB(255, 214, 226) or Color3.fromRGB(246, 232, 218), M.Limestone, "solid")
		block.CastShadow = true
	end
	-- remplissage au-dessus de l'arche (écoinçons) + fronton
	-- (au-dessus de l'extrados, sans empiéter sous l'arche)
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "Spandrel", Vector3.new(3, 7, 3.4), gcf * CFrame.new(sx * 12, spring + 11, 0), Color3.fromRGB(246, 232, 218), M.Limestone, "solid")
		part(model, "Spandrel", Vector3.new(3.5, 3.4, 3.4), gcf * CFrame.new(sx * 8.75, spring + 12.7, 0), Color3.fromRGB(246, 232, 218), M.Limestone, "solid")
	end
	part(model, "Keystone", Vector3.new(2.6, 3.2, 4.8), gcf * CFrame.new(0, spring + radius + 0.4, 0), C.HotPink, M.Marble, "deco")
	-- fronton "DOPAMINE TOWN" (lisible des deux côtés)
	-- (entre les deux tours, au-dessus de l'arche)
	local boardW = 2 * OPENING - 0.6
	local boardY = spring + radius + 5.4
	part(model, "Lintel", Vector3.new(2 * OPENING, 1.2, 4.2), gcf * CFrame.new(0, boardY - 4, 0), Color3.fromRGB(255, 196, 214), M.Marble, "decoS")
	local board = part(model, "NameBoard", Vector3.new(boardW, 6.8, 1.6), gcf * CFrame.new(0, boardY, 0), Color3.fromRGB(255, 244, 250), M.SmoothPlastic, "solid")
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local _, body = TownKit.Surface(board, face, 24, nil, 900, 0.5)
		local title = TownKit.Label(body, "Title", "DOPAMINE TOWN", 0.03, 0.06, 0.94, 0.62, C.HotPink, Enum.Font.FredokaOne, false)
		local stroke = Instance.new("UIStroke")
		stroke.Color = C.White
		stroke.Thickness = 4
		stroke.Parent = title
		TownKit.Label(body, "Subtitle", "🧠 Welcome! 💖", 0.1, 0.68, 0.8, 0.28, C.Plum, Enum.Font.GothamBold, true)
	end
	for _, y in ipairs({ 3.6, -3.6 }) do
		-- (v9.6 : liseré en marbre rose, plus un tube Neon de 26 studs qui éblouit)
		part(model, "Rim", Vector3.new(boardW + 0.4, 0.35, 1.8), gcf * CFrame.new(0, boardY + y, 0), C.Pink, M.Marble, "deco")
	end
	-- cœur au sommet (deux boules + un carré tourné) ; v9.6 : marbre, plus Neon
	local heart = gcf * CFrame.new(0, boardY + 5.8, 0)
	TownKit.Ball(model, "Heart", (heart * CFrame.new(-1.15, 0.7, 0)).Position, 3, C.HotPink, M.Marble, "deco")
	TownKit.Ball(model, "Heart", (heart * CFrame.new(1.15, 0.7, 0)).Position, 3, C.HotPink, M.Marble, "deco")
	part(model, "HeartTip", Vector3.new(2.6, 2.6, 1.2), heart * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(45)), C.HotPink, M.Marble, "deco")
	return model
end

----------------------------------------------------------------------
-- Plan de la ville (propriétaires)
----------------------------------------------------------------------

local function mapBoard(folder: Instance, cf: CFrame, geo: TownKit.Geo): MapBoard
	local model = TownKit.Model(folder, "MapBoard")
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "Post", Vector3.new(0.8, 12, 0.8), cf * CFrame.new(sx * 8, 6, 0.2), C.Wood, M.Wood, "prop")
	end
	part(model, "Roof", Vector3.new(18.5, 0.6, 2.6), cf * CFrame.new(0, 12.2, 0.2) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(150, 116, 206), M.Slate, "deco")
	local board = part(model, "Board", Vector3.new(16, 9.6, 0.5), cf * CFrame.new(0, 6.6, 0.2), C.Wood, M.Wood, "solid")
	local _, body = TownKit.Surface(board, Enum.NormalId.Front, 36, Color3.fromRGB(252, 244, 226), 200, 0.5)
	TownKit.Stroke(body, Color3.fromRGB(176, 124, 84), 6)
	TownKit.Label(body, "Title", "🗺️ Town map", 0.03, 0.02, 0.5, 0.1, C.Ink, Enum.Font.FredokaOne, true)
	-- zone de la carte (carrée, à gauche) + légende (à droite)
	local map = Instance.new("Frame")
	map.Name = "Map"
	map.BackgroundColor3 = Color3.fromRGB(170, 222, 150)
	map.BorderSizePixel = 0
	map.Position = UDim2.fromScale(0.03, 0.13)
	map.Size = UDim2.fromScale(0.52, 0.84)
	map.Parent = body
	TownKit.Corner(map, 16)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = map
	local world = geo.PlotR + WorldLayout.PLOT_D / 2 + 8
	local function mapPos(x: number, z: number): UDim2
		return UDim2.fromScale(0.5 + x / world / 2, 0.5 + z / world / 2)
	end
	local function block(name: string, x: number, z: number, w: number, h: number, rot: number, color: Color3, z0: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = mapPos(x, z)
		f.Size = UDim2.fromScale(w / world / 2, h / world / 2)
		f.Rotation = rot
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z0
		f.Parent = map
		return f
	end
	-- boulevard (un trait par côté), avenue, rues, place
	local m = geo.Slots
	local sideLen = 2 * geo.Road * math.tan(geo.HalfAngle) + 8
	for k = 0, m - 1 do
		local a = geo.SlotAngle(k)
		block("Road", math.sin(a) * geo.Road, math.cos(a) * geo.Road, sideLen, 20, -math.deg(a), Color3.fromRGB(120, 122, 136), 2)
	end
	for _, slot in ipairs(geo.Streets) do
		local a = geo.SlotAngle(slot)
		local mid = (WorldLayout.PLAZA_R + geo.Road) / 2
		block("Street", math.sin(a) * mid, math.cos(a) * mid, slot == 0 and 30 or 18, geo.Road - WorldLayout.PLAZA_R, -math.deg(a), Color3.fromRGB(150, 152, 166), 2)
	end
	local plaza = block("Plaza", 0, 0, WorldLayout.PLAZA_R * 2, WorldLayout.PLAZA_R * 2, 0, Color3.fromRGB(255, 214, 226), 3)
	TownKit.Corner(plaza, 999)
	local fountainIcon = TownKit.Label(plaza, "Icon", "⛲", 0.2, 0.2, 0.6, 0.6, C.Ink, Enum.Font.GothamBold, false)
	fountainIcon.ZIndex = 4
	-- entrée : "vous êtes ici"
	local here = block("Here", 0, geo.Gate - 12, 44, 44, 0, C.HotPink, 6)
	TownKit.Corner(here, 999)
	TownKit.Stroke(here, C.White, 3)
	-- parcelles : pastille numérotée + étiquette dans la légende
	local labels, markers = {}, {}
	local legend = Instance.new("Frame")
	legend.Name = "Legend"
	legend.BackgroundTransparency = 1
	legend.Position = UDim2.fromScale(0.58, 0.13)
	legend.Size = UDim2.fromScale(0.4, 0.84)
	legend.Parent = body
	local count = geo.Count
	local rows = math.max(6, count + 1)
	for i = 1, count do
		local x, z, a = WorldLayout.PlotPlace(i, count)
		local lot = block("Lot" .. i, x, z, WorldLayout.PLOT_W, WorldLayout.PLOT_D, -math.deg(a), Color3.fromRGB(126, 196, 112), 3)
		TownKit.Stroke(lot, Color3.fromRGB(255, 255, 255), 1)
		local pin = block("Pin" .. i, x, z, 70, 70, 0, Color3.fromRGB(150, 150, 170), 5)
		TownKit.Corner(pin, 999)
		local num = TownKit.Label(pin, "N", tostring(i), 0.1, 0.1, 0.8, 0.8, C.White, Enum.Font.GothamBlack, false)
		num.ZIndex = 6
		markers[i] = pin
		local row = TownKit.Label(legend, "Row" .. i, i .. ". ✨ Free plot", 0, (i - 1) / rows, 1, 0.9 / rows, C.Ink, Enum.Font.GothamBold, false)
		row.TextXAlignment = Enum.TextXAlignment.Left
		labels[i] = row
	end
	local you = TownKit.Label(legend, "Here", "📍 You are here", 0, count / rows, 1, 0.9 / rows, C.HotPink, Enum.Font.GothamBlack, true)
	you.TextXAlignment = Enum.TextXAlignment.Left
	return { Labels = labels, Markers = markers }
end

-- Panneau de bienvenue
local function welcomeSign(folder: Instance, cf: CFrame)
	local model = TownKit.Model(folder, "WelcomeSign")
	part(model, "Base", Vector3.new(15, 1.6, 3), cf * CFrame.new(0, 0.8, 0), C.Stone, M.Limestone, "solid")
	part(model, "Planter", Vector3.new(14, 0.8, 2.2), cf * CFrame.new(0, 2, -0.2), C.GrassDark, M.Grass, "deco")
	for i = -3, 3 do
		TownKit.Ball(model, "Flower", (cf * CFrame.new(i * 1.9, 2.6, -0.6)).Position, 1.2, TownKit.FLOWERS[(i + 4) % #TownKit.FLOWERS + 1], M.SmoothPlastic, "deco")
	end
	local board = part(model, "Board", Vector3.new(14, 6, 0.6), cf * CFrame.new(0, 6, 0.6), Color3.fromRGB(255, 244, 250), M.SmoothPlastic, "solid")
	local _, body = TownKit.Surface(board, Enum.NormalId.Front, 36, nil, 260, 0.5)
	TownKit.Gradient(body, Color3.fromRGB(255, 240, 248), Color3.fromRGB(255, 212, 234), 90)
	body.BackgroundTransparency = 0
	TownKit.Stroke(body, C.Pink, 6)
	TownKit.Label(body, "Title", "✨ Welcome to Dopamine Town! ✨", 0.04, 0.08, 0.92, 0.36, C.HotPink, Enum.Font.FredokaOne, true)
	TownKit.Label(body, "Line1", "🏠 Visit the houses   ❤️ Leave likes", 0.06, 0.5, 0.88, 0.2, C.Plum, Enum.Font.GothamBold, true)
	TownKit.Label(body, "Line2", "⛲ Meet at the fountain   😀 Dance!", 0.06, 0.73, 0.88, 0.2, C.Plum, Enum.Font.GothamBold, true)
	part(model, "Frame", Vector3.new(14.8, 6.8, 0.4), cf * CFrame.new(0, 6, 0.95), C.Wood, M.Wood, "deco")
end

----------------------------------------------------------------------
-- Dehors : route, rond-point, bus, parking
----------------------------------------------------------------------

local function busStop(folder: Instance, cf: CFrame)
	local model = TownKit.Model(folder, "BusStop")
	part(model, "Slab", Vector3.new(12, 0.3, 5), cf * CFrame.new(0, 0.15, 0), C.Walk, M.Pavement, "solid")
	part(model, "Roof", Vector3.new(12.4, 0.5, 5.2), cf * CFrame.new(0, 8.4, 0), C.White, M.SmoothPlastic, "decoS")
	part(model, "BackGlass", Vector3.new(11, 6.6, 0.25), cf * CFrame.new(0, 4.6, 2.2), C.Glass, M.Glass, "deco").Transparency = 0.5
	for _, x in ipairs({ -5.8, 5.8 }) do
		part(model, "Post", Vector3.new(0.4, 8.2, 0.4), cf * CFrame.new(x * 0.99, 4.2, 2.2), C.MetalLight, M.Metal, "prop")
	end
	-- (v9.6 : vrai banc TownKit, dos à la vitre, plus une planche flottante)
	TownKit.Bench(model, cf * CFrame.new(0, 0.3, 0.9))
	local ad = part(model, "Ad", Vector3.new(0.3, 5.4, 3.4), cf * CFrame.new(6.1, 4.2, 0.4), C.White, M.SmoothPlastic, "deco")
	local _, body = TownKit.Surface(ad, Enum.NormalId.Right, 40, nil, 150, 0.5)
	TownKit.Gradient(body, Color3.fromRGB(255, 190, 222), Color3.fromRGB(190, 170, 255), 90)
	body.BackgroundTransparency = 0
	TownKit.Label(body, "Ad", "🧠 Click more!", 0.05, 0.3, 0.9, 0.4, C.White, Enum.Font.FredokaOne, true)
	TownKit.RoadSign(model, (cf * CFrame.new(-7.5, 0, -1.8)).Position, 0, Color3.fromRGB(60, 120, 220), "Rect")
end

local function outside(folder: Instance, geo: TownKit.Geo, gcf: CFrame)
	local model = TownKit.Model(folder, "Arrival")
	local len = 50
	gcf = gcf * CFrame.new(0, -WALK_Y, 0) -- (repère au niveau du pré)
	-- route depuis la porte, puis rond-point
	part(model, "Road", Vector3.new(16, 0.7, len), gcf * CFrame.new(0, ROAD_Y - 0.35, len / 2 + 3), C.Asphalt, M.Asphalt, "solid")
	for i = 0, 3 do
		-- (v9.8, CITY98) peinture au sol construite côté client (TownStreetLife)
		TownKit.LifeSpot("Paint", gcf * CFrame.new(0, ROAD_Y + 0.05, 10 + i * 11), 0, Vector3.new(0.4, 0.1, 5))
	end
	local loop = gcf * CFrame.new(0, 0, len + 16)
	-- (v9.8 z-fighting : l'anneau 0,03 au-dessus de la route qui y entre)
	TownKit.Disc(model, "Roundabout", (loop * CFrame.new(0, ROAD_Y + 0.03, 0)).Position, 20, 0.7, C.Asphalt, M.Asphalt, "solid")
	TownKit.Disc(model, "Island", (loop * CFrame.new(0, WALK_Y, 0)).Position, 8, 1.3, C.Curb, M.Concrete, "solid")
	TownKit.Disc(model, "IslandGrass", (loop * CFrame.new(0, WALK_Y + 0.05, 0)).Position, 7.2, 0.3, C.Lawn, M.Grass, "deco")
	TownKit.Tree(model, (loop * CFrame.new(0, WALK_Y, 0)).Position, 16, 77, "Cherry", { Tier = 1, Lawn = true }) -- (v9.7 NATURE97)
	-- bus arrêté devant l'abribus (il vient de déposer les joueurs)
	-- (v9.7, VEHICLES97) vrai bus de ville, portes côté abribus : construit
	-- côté client (TownTraffic : vitres, sièges, barres) ; boîte solide ici
	TownVehicles.Bus(model, gcf * CFrame.new(4.2, ROAD_Y, 28))
	busStop(model, gcf * CFrame.new(13, WALK_Y - 0.3, 30) * CFrame.Angles(0, math.rad(90), 0))
	part(model, "Sidewalk", Vector3.new(6, 1.3, len - 4), gcf * CFrame.new(11, WALK_Y - 0.65, len / 2 + 5), C.Walk, M.Pavement, "solid")
	-- parking (côté gauche en arrivant de la ville)
	local lot = gcf * CFrame.new(-31, 0, 26)
	part(model, "Parking", Vector3.new(30, 0.7, 34), lot * CFrame.new(0, ROAD_Y - 0.35, 0), C.AsphaltDark, M.Asphalt, "solid")
	for i = 0, 5 do
		part(model, "Bay", Vector3.new(0.3, 0.1, 11), lot * CFrame.new(-15 + i * 6, ROAD_Y + 0.05, -9), C.Line, M.SmoothPlastic, "deco")
	end
	local colors = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(255, 236, 150), Color3.fromRGB(250, 250, 250), Color3.fromRGB(200, 170, 250) }
	for i, bay in ipairs({ 0, 1, 4 }) do
		TownKit.Car(model, lot * CFrame.new(-12 + bay * 6, ROAD_Y, -9) * CFrame.Angles(0, math.pi, 0), colors[i], ({ "CityCar", "BubbleCar", "Hatchback" })[i], {}) -- (v9.6) CarModels
	end
	-- (v9.7, VEHICLES97) 2 places de plus occupées (voitures construites côté client)
	TownKit.VehicleSpot(model, "Car", lot * CFrame.new(-12 + 2 * 6, ROAD_Y, -9) * CFrame.Angles(0, math.pi, 0), { CarId = "CityCar", Color = Color3.fromRGB(220, 44, 64), Stripe = true })
	TownKit.VehicleSpot(model, "Car", lot * CFrame.new(-12 + 3 * 6, ROAD_Y, -9) * CFrame.Angles(0, math.pi, 0), { CarId = "BubbleCar", Color = Color3.fromRGB(128, 222, 190) })
	TownKit.Lamp(model, (lot * CFrame.new(0, ROAD_Y, 6)).Position, 0, false, true)
	geo.Reserve((loop * CFrame.new(0, 0, 0)).Position, 24)
	-- (v9.8, CITY98) vie de la rue (client) : on attend le bus, lampadaires
	-- le long de la route, poteau indicateur, colline au moulin à vent
	-- derrière le rond-point
	local stopCF = gcf * CFrame.new(13, WALK_Y - 0.3, 30) * CFrame.Angles(0, math.rad(90), 0)
	TownKit.LifeSpot("SitBench", stopCF * CFrame.new(0, 0.3, 0.9), 40)
	TownKit.LifeSpot("Wait", stopCF * CFrame.new(-3.6, 0.3, -1.4) * CFrame.Angles(0, 0.3, 0), 41)
	for i, z in ipairs({ 12, 44 }) do
		TownKit.LifeSpot("Lamppost", gcf * CFrame.new(9.6, WALK_Y, z) * CFrame.Angles(0, math.rad(90), 0), 50 + i)
	end
	for i, z in ipairs({ 14, 30 }) do
		TownKit.LifeSpot("Lamppost", gcf * CFrame.new(-9.8, WorldLayout.GROUND_Y, z) * CFrame.Angles(0, math.rad(-90), 0), 52 + i)
	end
	TownKit.LifeSpot("Signpost", gcf * CFrame.new(-11.5, WorldLayout.GROUND_Y, len - 4), 60)
	TownKit.LifeSpot("Bin", gcf * CFrame.new(12.6, WALK_Y, 22), 62)
	TownKit.LifeSpot("WindmillHill", gcf * CFrame.new(-24, WorldLayout.GROUND_Y, len + 68) * CFrame.Angles(0, math.rad(200), 0), 63)
	-- (v9.9, CITY99) route d'arrivée réaliste (client : TownRoads) : asphalte
	-- vivant, caniveau + bordure du trottoir, dalles, rond-point détaillé
	local along = gcf * CFrame.new(0, 0, len / 2 + 3) * CFrame.Angles(0, math.pi / 2, 0)
	-- (X local vers la porte : on s'arrête avant l'anneau du rond-point)
	TownStreets.Chunks("RoadSurface", along, -len / 2 + 8, len / 2 - 1, ROAD_Y, 0, 2, 16, 7001)
	local walkAlong = gcf * CFrame.new(0, 0, len / 2 + 5) * CFrame.Angles(0, math.pi / 2, 0)
	-- (X local vers la porte : le caniveau s'arrête avant l'anneau du rond-point)
	TownStreets.Chunks("CurbLine", walkAlong, -17, (len - 4) / 2, ROAD_Y, 8, WALK_Y - ROAD_Y, 0, 7002)
	-- (pas de dalles sous la dalle de l'abribus : gcf z 24..36 = X local -6..6)
	TownStreets.Chunks("Pavers", walkAlong, -(len - 4) / 2 + 0.5, (len - 4) / 2 - 0.5, WALK_Y, 11, 0, 5.8, 7003, { { -6.5, 6.5 } })
	TownKit.LifeSpot("Roundabout", loop * CFrame.new(0, ROAD_Y + 0.03, 0), 7004, Vector3.new(8, 0, 20))
	-- repères des lieux (poteaux indicateurs, client) : porte, MégaDopa,
	-- concession, coin gourmand
	TownKit.LifeSpot("Dest", CFrame.new(gcf.Position), 15)
	TownKit.LifeSpot("Dest", WorldLayout.MarketCFrame(geo.Count), 6)
	TownKit.LifeSpot("Dest", WorldLayout.DealershipCFrame(geo.Count), 7)
	TownKit.LifeSpot("Dest", WorldLayout.FoodCornerCFrame(geo.Count), 8)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

export type EntranceResult = { Map: MapBoard, Spawn: SpawnLocation }

function TownEntrance.Build(folder: Instance, geo: TownKit.Geo): EntranceResult
	local entrance = Instance.new("Folder")
	entrance.Name = "Entrance"
	entrance.Parent = folder
	local O = geo.Origin
	local gcf = WorldLayout.GateCFrame(geo.Count) -- LookVector vers la place ; +Z local = dehors
	local depth = geo.Gate - geo.Front
	-- place d'accueil : pavage, bande rose dans l'axe, bordures
	local center = O + Vector3.new(0, WALK_Y, geo.Front + depth / 2 + 2)
	part(entrance, "WelcomePlaza", Vector3.new(PLAZA_HALF * 2, 1.3, depth + 4), CFrame.new(center - Vector3.new(0, 0.65, 0)), C.Paving, M.Cobblestone, "solid")
	-- (v9.6 z-fighting : bande et bordures un peu en retrait des bords du pavage)
	part(entrance, "Band", Vector3.new(14, 0.2, depth + 3.9), CFrame.new(center + Vector3.new(0, 0.03, 0)), C.PavingRose, M.Cobblestone, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		part(entrance, "Border", Vector3.new(1.1, 0.2, depth + 3.9), CFrame.new(center + Vector3.new(sx * (PLAZA_HALF - 0.6), 0.04, 0)), C.StoneDark, M.Granite, "deco")
		-- haies le long des bords + arbres en bacs aux coins
		-- (v9.7 NATURE97) haie taillée au dessus arrondi
		if sx > 0 then
			-- (v9.9, CITY99) haie ouverte vers le 🍦 coin gourmand (passage de 7 studs)
			local z0, z1 = -3 - (depth - 14) / 2, -3 + (depth - 14) / 2
			local gap0, gap1 = -5.5, 1.5
			TownKit.Hedge(entrance, CFrame.new(center + Vector3.new(sx * (PLAZA_HALF - 2.4), 0, (z0 + gap0) / 2)) * CFrame.Angles(0, math.pi / 2, 0), gap0 - z0, 2.4, 3.2, 20 + sx)
			TownKit.Hedge(entrance, CFrame.new(center + Vector3.new(sx * (PLAZA_HALF - 2.4), 0, (gap1 + z1) / 2)) * CFrame.Angles(0, math.pi / 2, 0), z1 - gap1, 2.4, 3.2, 23 + sx)
		else
			TownKit.Hedge(entrance, CFrame.new(center + Vector3.new(sx * (PLAZA_HALF - 2.4), 0, -3)) * CFrame.Angles(0, math.pi / 2, 0), depth - 14, 2.4, 3.2, 20 + sx)
		end
		for _, dz in ipairs({ -depth / 2 + 6, depth / 2 - 10 }) do
			local p = center + Vector3.new(sx * (PLAZA_HALF - 8), 0, dz)
			part(entrance, "TreeBox", Vector3.new(4.4, 1.8, 4.4), CFrame.new(p + Vector3.new(0, 0.9, 0)), C.White, M.Concrete, "prop")
			TownKit.Tree(entrance, p + Vector3.new(0, 1.8, 0), 14, math.floor(p.X + dz), sx > 0 and "Cherry" or "Oak") -- (v9.7 NATURE97)
		end
		-- lampadaires (vraies lumières)
		TownKit.Lamp(entrance, center + Vector3.new(sx * 13, 0, 3), TownKit.Facing(Vector3.new(-sx, 0, 0)), true)
		-- jardinières le long de l'axe
		TownKit.Planter(entrance, CFrame.new(center + Vector3.new(sx * 18, 0, 6)), 8, 3, 3 + sx)
		TownKit.Planter(entrance, CFrame.new(center + Vector3.new(sx * 18, 0, -14)), 8, 3, 7 + sx)
		-- bancs face à l'axe
		local benchCF = CFrame.lookAt(center + Vector3.new(sx * 24, 0, -4), center + Vector3.new(0, 0, -4))
		TownKit.Bench(entrance, benchCF)
		TownKit.LifeSpot("SitBench", benchCF, 30 + sx) -- (v9.8, CITY98) un passant peut s'y asseoir
		-- (v9.8, CITY98) mobilier construit côté client : poubelle près du banc
		TownKit.LifeSpot("Bin", CFrame.new(center + Vector3.new(sx * 24.3, 0, -0.2)), 32 + sx)
	end
	-- rosace d'apparition (juste à l'intérieur de la porte)
	local spawnCF = WorldLayout.EntranceCFrame(geo.Count)
	local spawnGround = spawnCF.Position - Vector3.new(0, 3, 0)
	TownKit.Disc(entrance, "Rosette", spawnGround + Vector3.new(0, 0.08, 0), 7, 0.4, C.PavingLilac, M.Marble, "deco")
	TownKit.Disc(entrance, "RosetteInner", spawnGround + Vector3.new(0, 0.11, 0), 5.2, 0.4, C.White, M.Marble, "deco")
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local mid = spawnGround + d * 4.6 + Vector3.new(0, 0.14, 0)
		part(entrance, "RosetteRay", Vector3.new(0.9, 0.1, 4.4), CFrame.lookAt(mid, mid + d), i % 2 == 0 and C.Pink or C.Lilac, M.Marble, "deco")
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(5, 0.3, 5)
	spawn.CFrame = CFrame.new(spawnGround + Vector3.new(0, 0.08, 0)) -- (v9.6 : dessus à +0.23, au-dessus des rayons)
	spawn.Color = C.Pink
	spawn.Material = M.Marble
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.CastShadow = false
	spawn.Parent = entrance
	TownKit.Stats.Parts += 1
	-- la porte
	gate(entrance, gcf)
	-- panneau de bienvenue (à droite) + plan (à gauche), tournés vers l'arrivant
	welcomeSign(entrance, CFrame.lookAt(center + Vector3.new(19, 0, -24), center + Vector3.new(4, 0, 4)))
	local map = mapBoard(entrance, CFrame.lookAt(center + Vector3.new(-19, 0, -22), center + Vector3.new(-4, 0, 6)), geo)
	-- vélos
	TownKit.BikeRack(entrance, CFrame.new(center + Vector3.new(26, 0, 12)) * CFrame.Angles(0, math.rad(90), 0), 3)
	-- (v9.7, VEHICLES97) trottinettes / scooter garés à côté des vélos (client)
	TownVehicles.TwoWheelers(entrance, CFrame.new(center + Vector3.new(24.5, 0, 18.5)) * CFrame.Angles(0, math.rad(90), 0), 3, 4)
	-- (v9.8, CITY98) vie de la rue (client) : colonne d'affiches, distributeurs,
	-- gens qui discutent, fontaine à boire
	TownKit.LifeSpot("Morris", CFrame.new(center + Vector3.new(-27, 0, 11)), 1)
	TownKit.LifeSpot("Vending", CFrame.lookAt(center + Vector3.new(29, 0, -12), center + Vector3.new(0, 0, -12)), 2)
	TownKit.LifeSpot("Vending", CFrame.lookAt(center + Vector3.new(29, 0, -9.6), center + Vector3.new(0, 0, -9.6)), 3)
	TownKit.LifeSpot("DrinkFountain", CFrame.lookAt(center + Vector3.new(-9, 0, -22), center + Vector3.new(0, 0, -22)), 4)
	TownKit.LifeSpot("Chat", CFrame.new(center + Vector3.new(9, 0, -8)) * CFrame.Angles(0, 2.4, 0), 7)
	TownKit.LifeSpot("Chat", CFrame.new(center + Vector3.new(-8, 0, 6)) * CFrame.Angles(0, -0.8, 0), 8)
	-- (v9.9, CITY99) poteau indicateur à l'arrivée (vers tous les lieux de la ville)
	TownKit.LifeSpot("Direction", CFrame.new(center + Vector3.new(-12, 0, 12)), 320)
	-- (v9.9, CITY99) allées pavées vers le 🍦 coin gourmand : depuis la place
	-- d'accueil (par le passage dans la haie) et depuis le trottoir du boulevard
	local food = WorldLayout.FoodCornerCFrame(geo.Count)
	local foodX0 = food.Position.X - WorldLayout.FOOD_W / 2
	local y = geo.Origin.Y + WorldLayout.GROUND_Y
	local gz = center.Z - 2
	local x0 = center.X + PLAZA_HALF
	if foodX0 > x0 + 1 then
		TownKit.LifeSpot("Walkway", CFrame.new((x0 + foodX0) / 2 + 0.1, y, gz), 330, Vector3.new(foodX0 - x0 + 0.4, 1, 5))
	end
	local foodZ0 = food.Position.Z - WorldLayout.FOOD_D / 2
	local walkZ = geo.Origin.Z + geo.Front
	if foodZ0 > walkZ + 1 then
		TownKit.LifeSpot("Walkway", CFrame.new(food.Position.X, y, (walkZ + foodZ0) / 2) * CFrame.Angles(0, math.pi / 2, 0), 331, Vector3.new(foodZ0 - walkZ + 0.4, 1, 5))
	end
	-- dehors
	outside(entrance, geo, gcf)
	return { Map = map, Spawn = spawn }
end

return TownEntrance
