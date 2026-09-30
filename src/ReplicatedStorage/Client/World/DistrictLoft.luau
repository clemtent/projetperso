--[[
	DistrictLoft (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DistrictLoft

	🏭 Dopamine Town (v10, CITY10) : l'identité du QUARTIER DES LOFTS
	(industriel), construite côté CLIENT, en flux (TownStreetLife ;
	emplacements calculés par CityPlan dans le quartier "Loft") :
	  - "LftWarehouse" : entrepôt en brique à toit en sheds (verrières),
	    grandes baies à petits carreaux d'acier, quai de chargement, porte
	    sectionnelle ondulée, escalier de secours, château d'eau sur le toit,
	    cheminée d'usine cerclée, enseigne peinte "Manufacture 1908" ;
	  - "LftMural"     : mur de street art (fresque colorée en SurfaceGui,
	    tag), bombes de peinture, une artiste qui peint ;
	  - "LftRail"      : voie ferrée (ballast, traverses, rails) le long de
	    x, longueur spot.Size.X ; "LftWagon" : wagon de marchandises tagué
	    et heurtoir ;
	  - "LftFoodTrucks": cour de food trucks (3 camions avec comptoir,
	    auvent, menu), guirlandes de guinguette, tables, file de clients ;
	  - "LftContainers": conteneurs empilés transformés (boutique, bar) ;
	  - "LftLamp"      : lampadaire industriel (suspension à grille) ;
	  - "LftFence"     : clôture grillagée (longueur spot.Size.X).
	Repère F : au sol, au centre de l'emprise, -Z = côté rue.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local CityKit = require(script.Parent.CityKit)

local DistrictLoft = {}

local M = CityKit.M
local rgb = CityKit.rgb
local Box, Part, Column, Wedge, Egg, Glow, Text = CityKit.Box, CityKit.Part, CityKit.Column, CityKit.Wedge, CityKit.Egg, CityKit.Glow, CityKit.Text
local hash = CityKit.Hash

local BRICK = rgb(150, 76, 56)
local BRICK_D = rgb(112, 56, 44)
local STEEL = rgb(60, 64, 72)
local STEEL_L = rgb(150, 156, 164)
local RUST = rgb(150, 84, 50)
local CONCRETE = rgb(176, 174, 168)
local WARM = rgb(255, 222, 170)
local GLASS = rgb(120, 150, 170)
local WHITE = rgb(250, 250, 248)
local WOOD = rgb(150, 104, 66)

DistrictLoft.FOOT = {
	LftWarehouse = Vector2.new(40, 34),
	LftMural = Vector2.new(28, 10),
	LftFoodTrucks = Vector2.new(40, 30),
	LftContainers = Vector2.new(24, 16),
	LftWagon = Vector2.new(30, 8),
}

----------------------------------------------------------------------
-- 🏭 Entrepôt
----------------------------------------------------------------------

-- baie vitrée à petits carreaux d'acier (face -Z du repère R)
local function steelWindow(m: Model, R: CFrame, x: number, y0: number, w: number, h: number, lit: boolean)
	local g = Box(m, "BayGlass", R, x - w / 2, x + w / 2, y0, y0 + h, -0.06, 0, lit and WARM or GLASS, M.Glass)
	if lit then
		Glow(g)
	end
	for k = 1, 3 do
		local xx = x - w / 2 + k * w / 4
		Box(m, "BayMullion", R, xx - 0.08, xx + 0.08, y0, y0 + h, -0.14, -0.06, STEEL, M.Metal)
	end
	for k = 1, 3 do
		local yy = y0 + k * h / 4
		Box(m, "BayTransom", R, x - w / 2, x + w / 2, yy - 0.08, yy + 0.08, -0.14, -0.06, STEEL, M.Metal)
	end
	Box(m, "BayLintel", R, x - w / 2 - 0.4, x + w / 2 + 0.4, y0 + h, y0 + h + 0.8, -0.3, 0, BRICK_D, M.Brick)
	Box(m, "BaySill", R, x - w / 2 - 0.3, x + w / 2 + 0.3, y0 - 0.4, y0, -0.4, 0, CONCRETE, M.Concrete)
end

local function buildWarehouse(m: Model, F: CFrame, seed: number)
	local W, D, H = 36, 26, 18
	local B = F * CFrame.new(0, 0, 3)
	Box(m, "Hall", B, -W / 2, W / 2, 0, H, -D / 2, D / 2, BRICK, M.Brick, true)
	Box(m, "Plinth", B, -W / 2 - 0.2, W / 2 + 0.2, 0, 1.4, -D / 2 - 0.2, D / 2 + 0.2, CONCRETE, M.Concrete, true)
	-- pilastres en brique plus sombre
	for i = 0, 4 do
		local x = -W / 2 + i * W / 4
		Box(m, "Pilaster", B, x - 0.8, x + 0.8, 1.4, H + 0.6, -D / 2 - 0.5, -D / 2, BRICK_D, M.Brick)
	end
	Box(m, "Coping", B, -W / 2 - 0.4, W / 2 + 0.4, H, H + 0.6, -D / 2 - 0.4, D / 2 + 0.4, CONCRETE, M.Concrete)
	-- sheds : 4 dents (pente + verrière verticale face au nord)
	local teeth = 4
	local tw = D / teeth
	for i = 0, teeth - 1 do
		local z0 = -D / 2 + i * tw
		Wedge(m, "ShedRoof", Vector3.new(W - 0.4, 4.2, tw), B * CFrame.new(0, H + 0.6 + 2.1, z0 + tw / 2) * CFrame.Angles(0, math.pi, 0), rgb(84, 86, 94), M.Metal)
		local g = Box(m, "ShedGlass", B, -W / 2 + 0.4, W / 2 - 0.4, H + 0.65, H + 4.6, z0 - 0.22, z0 - 0.04, GLASS, M.Glass)
		if hash(seed, i + 40) < 0.5 then
			Glow(g)
			g.Color = WARM
		end
	end
	-- baies de l'étage (face rue) + enseigne peinte
	for i = 0, 3 do
		local x = -W / 2 + (i + 0.5) * W / 4
		steelWindow(m, B * CFrame.new(0, 0, -D / 2), x, 9.4, 6, 6.2, hash(seed, i) < 0.4)
	end
	local ghost = Box(m, "GhostSign", B, -W / 2 + 2, W / 2 - 2, 16.2, 17.8, -D / 2 - 0.04, -D / 2, BRICK, M.Brick)
	Text(ghost, Enum.NormalId.Front, Locale.T("MANUFACTURE 1908 · LOFTS"), rgb(236, 226, 200), nil, Enum.Font.Arcade, 180)
	-- rez-de-chaussée : porte sectionnelle ondulée + quai, porte vitrée d'atelier
	local dockX = -W / 4
	Box(m, "Dock", B, dockX - 6, dockX + 6, 0, 3.6, -D / 2 - 4.5, -D / 2, CONCRETE, M.Concrete, true)
	Box(m, "DockBumper", B, dockX - 4, dockX - 3, 2.4, 3.4, -D / 2 - 4.7, -D / 2 - 4.5, rgb(30, 30, 34), M.Rubber)
	Box(m, "DockBumper", B, dockX + 3, dockX + 4, 2.4, 3.4, -D / 2 - 4.7, -D / 2 - 4.5, rgb(30, 30, 34), M.Rubber)
	Box(m, "RollDoor", B, dockX - 4.5, dockX + 4.5, 3.6, 8.6, -D / 2 - 0.1, -D / 2, STEEL_L, M.CorrodedMetal)
	for k = 0, 8 do
		local y = 3.9 + k * 0.55
		Box(m, "RollSlat", B, dockX - 4.5, dockX + 4.5, y, y + 0.12, -D / 2 - 0.16, -D / 2 - 0.1, rgb(120, 126, 134), M.Metal)
	end
	Box(m, "DockCanopy", B, dockX - 6.5, dockX + 6.5, 9.2, 9.6, -D / 2 - 5, -D / 2, STEEL, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		CityKit.Rod(m, "CanopyTie", (B * CFrame.new(dockX + sx * 6, 9.6, -D / 2 - 4.8)).Position, (B * CFrame.new(dockX + sx * 6, 13.5, -D / 2)).Position, 0.14, STEEL, M.Metal)
	end
	-- porte d'atelier vitrée + marches
	local doorX = W / 4
	Box(m, "DoorFrame", B, doorX - 3.2, doorX + 3.2, 1.4, 8.8, -D / 2 - 0.2, -D / 2, STEEL, M.Metal)
	Glow(Box(m, "DoorGlass", B, doorX - 2.8, doorX + 2.8, 1.4, 8.4, -D / 2 - 0.26, -D / 2 - 0.2, WARM, M.Glass))
	Box(m, "DoorStep", B, doorX - 3.6, doorX + 3.6, 0, 1.4, -D / 2 - 2, -D / 2, CONCRETE, M.Concrete, true)
	Box(m, "DoorStep2", B, doorX - 3.6, doorX + 3.6, 0, 0.7, -D / 2 - 3, -D / 2 - 2, CONCRETE, M.Concrete, true)
	-- escalier de secours (côté droit) : paliers + limons
	local sx = W / 2
	for f = 0, 2 do
		local y = 6 + f * 5
		Box(m, "FireLanding", B, sx, sx + 3, y, y + 0.25, -4, 4, STEEL, M.DiamondPlate)
		Box(m, "FireRail", B, sx + 2.85, sx + 3, y + 0.25, y + 3.4, -4, 4, STEEL, M.Metal)
		if f < 2 then
			CityKit.Beam(m, "FireStair", (B * CFrame.new(sx + 1.5, y + 0.2, 3.6)).Position, (B * CFrame.new(sx + 1.5, y + 5.2, -3.6)).Position, 2.6, 0.3, STEEL, M.DiamondPlate)
		end
	end
	-- château d'eau sur le toit + cheminée d'usine
	local T = B * CFrame.new(-W / 2 + 7, H + 0.6, D / 2 - 7)
	for _, a in ipairs({ 0.8, 2.4, 3.9, 5.5 }) do
		local p = T * CFrame.new(math.cos(a) * 2.6, 0, math.sin(a) * 2.6)
		Column(m, "TowerLeg", p, 0, 0, 0, 7, 0.4, STEEL, M.Metal)
	end
	Column(m, "TowerTank", T, 0, 0, 7, 13, 6.4, rgb(140, 100, 70), M.WoodPlanks)
	for _, y in ipairs({ 8, 10, 12 }) do
		Column(m, "TowerHoop", T, 0, 0, y, y + 0.16, 6.55, STEEL, M.Metal)
	end
	for k = 0, 3 do
		local R = T * CFrame.Angles(0, k * math.pi / 2, 0)
		Wedge(m, "TowerCone", Vector3.new(4.6, 2.2, 2.3), R * CFrame.new(0, 14.1, -1.15), rgb(70, 72, 80), M.Metal)
	end
	local C = B * CFrame.new(W / 2 - 4, 0, D / 2 + 3)
	Column(m, "Stack", C, 0, 0, 0, 40, 3.6, BRICK_D, M.Brick, true)
	Column(m, "StackBase", C, 0, 0, 0, 6, 4.6, BRICK_D, M.Brick, true)
	for _, y in ipairs({ 14, 26, 38 }) do
		Column(m, "StackBand", C, 0, 0, y, y + 0.5, 3.9, STEEL, M.Metal)
	end
	-- baies des côtés
	for _, side in ipairs({ -1, 1 }) do
		local R = B * CFrame.new(side * W / 2, 0, 0) * CFrame.Angles(0, -side * math.pi / 2, 0)
		for i = 0, 2 do
			steelWindow(m, R, -D / 2 + (i + 0.5) * D / 3 - 0, 8, 4.6, 6, false)
		end
	end
	-- un livreur avec un chariot devant le quai
	local w = CityKit.Npc(m, "worker", seed * 3 + 7, B * CFrame.new(dockX + 2, 0, -D / 2 - 7) * CFrame.Angles(0, math.pi + 0.3, 0), "none", true)
	CityKit.Idle(w, "push", hash(seed, 5) * 6)
	for k = 0, 2 do
		Box(m, "Pallet", B, dockX - 5 + k * 3.4, dockX - 2.4 + k * 3.4, 3.6, 4, -D / 2 - 4.2, -D / 2 - 1.6, WOOD, M.WoodPlanks)
		Box(m, "Carton", B, dockX - 4.7 + k * 3.4, dockX - 2.7 + k * 3.4, 4, 5.6 + (k % 2) * 0.8, -D / 2 - 3.9, -D / 2 - 1.9, rgb(190, 150, 100), M.Cardboard)
	end
end

----------------------------------------------------------------------
-- 🎨 Street art
----------------------------------------------------------------------

local MURAL_COLORS = { rgb(255, 80, 140), rgb(70, 200, 255), rgb(255, 214, 40), rgb(140, 90, 255), rgb(60, 220, 140), rgb(255, 120, 40) }

local function buildMural(m: Model, F: CFrame, seed: number)
	local L, H = 26, 11
	local wall = Box(m, "MuralWall", F, -L / 2, L / 2, 0, H, 0, 1.4, BRICK, M.Brick, true)
	Box(m, "MuralCap", F, -L / 2 - 0.2, L / 2 + 0.2, H, H + 0.4, -0.2, 1.6, CONCRETE, M.Concrete)
	local gui = CityKit.Canvas(wall, Enum.NormalId.Front, 220, 10)
	-- fond en dégradé + formes + visage souriant + tag
	local bg = CityKit.Blob(gui, 0.5, 0.5, 1, 1, CityKit.Pick(MURAL_COLORS, seed, 1))
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(CityKit.Pick(MURAL_COLORS, seed, 2), CityKit.Pick(MURAL_COLORS, seed, 3))
	grad.Rotation = 20
	grad.Parent = bg
	for i = 0, 7 do
		local x, y = 0.08 + hash(seed, i) * 0.84, 0.12 + hash(seed, i + 20) * 0.7
		local s = 0.1 + hash(seed, i + 40) * 0.2
		CityKit.Blob(gui, x, y, s, s * 2.2, CityKit.Pick(MURAL_COLORS, seed, i + 5), 1, hash(seed, i + 60) * 90)
	end
	-- grand visage (cerveau souriant = logo du jeu)
	CityKit.Blob(gui, 0.5, 0.52, 0.34, 0.8, rgb(255, 170, 200), 1)
	CityKit.Blob(gui, 0.44, 0.44, 0.05, 0.12, rgb(30, 30, 40), 1)
	CityKit.Blob(gui, 0.56, 0.44, 0.05, 0.12, rgb(30, 30, 40), 1)
	CityKit.Blob(gui, 0.5, 0.66, 0.14, 0.07, rgb(200, 40, 80), 1)
	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.Size = UDim2.fromScale(0.34, 0.24)
	tag.Position = UDim2.fromScale(0.64, 0.7)
	tag.Text = "DOPA!"
	tag.Font = Enum.Font.Arcade
	tag.TextScaled = true
	tag.TextColor3 = WHITE
	tag.TextStrokeTransparency = 0
	tag.Rotation = -8
	tag.Parent = gui
	-- bombes au sol, escabeau, artiste qui peint
	for k = 0, 4 do
		Column(m, "SprayCan", F, -6 + k * 0.6, -1.2 - (k % 2) * 0.4, 0, 0.9, 0.34, CityKit.Pick(MURAL_COLORS, seed, k + 9), M.Metal)
	end
	local S = F * CFrame.new(4, 0, -1.6)
	for _, sx in ipairs({ -1, 1 }) do
		CityKit.Rod(m, "LadderRail", (S * CFrame.new(sx * 0.8, 0, -0.9)).Position, (S * CFrame.new(sx * 0.8, 5.4, 0)).Position, 0.14, STEEL_L, M.Metal)
		CityKit.Rod(m, "LadderBack", (S * CFrame.new(sx * 0.8, 0, 0.9)).Position, (S * CFrame.new(sx * 0.8, 5.4, 0)).Position, 0.14, STEEL_L, M.Metal)
	end
	local artist = CityKit.Npc(m, "pedestrian", seed * 17 + 3, F * CFrame.new(-2, 0, -2.4), "none", true)
	CityKit.Idle(artist, "wave", 0)
end

----------------------------------------------------------------------
-- 🚂 Voie ferrée, wagon
----------------------------------------------------------------------

local function buildRail(m: Model, F: CFrame, seed: number, spot: any)
	local L = spot and spot.Size and spot.Size.X or 40
	Box(m, "Ballast", F, -L / 2, L / 2, -0.2, 0.5, -3.6, 3.6, rgb(120, 112, 104), M.Slate)
	local n = math.max(1, math.floor(L / 2.6))
	for i = 0, n - 1 do
		local x = -L / 2 + (i + 0.5) * L / n
		Box(m, "Sleeper", F, x - 0.45, x + 0.45, 0.5, 0.85, -2.8, 2.8, rgb(96, 78, 60), M.Wood)
	end
	for _, z in ipairs({ -1.45, 1.45 }) do
		Box(m, "RailFoot", F, -L / 2, L / 2, 0.85, 1.0, z - 0.3, z + 0.3, rgb(110, 100, 94), M.CorrodedMetal)
		Box(m, "RailHead", F, -L / 2, L / 2, 1.0, 1.35, z - 0.14, z + 0.14, STEEL_L, M.Metal)
	end
	local _ = seed
end

local function buildWagon(m: Model, F: CFrame, seed: number)
	-- wagon couvert (sur les rails : x = le long de la voie)
	local L, W, H = 26, 6.6, 9
	local body = CityKit.Pick({ rgb(140, 70, 50), rgb(60, 90, 120), rgb(90, 110, 70) }, seed, 1)
	for _, x in ipairs({ -L / 2 + 4, L / 2 - 4 }) do
		for _, z in ipairs({ -1.45, 1.45 }) do
			for _, dx in ipairs({ -1.4, 1.4 }) do
				Part(m, "WagonWheel", Vector3.new(0.4, 2.2, 2.2), F * CFrame.new(x + dx, 2.45, z) * CFrame.Angles(0, math.pi / 2, 0), rgb(50, 50, 54), M.Metal, "Cyl")
			end
		end
		Box(m, "Bogie", F, x - 2.4, x + 2.4, 2, 3.2, -1.9, 1.9, rgb(40, 40, 44), M.Metal)
	end
	Box(m, "Chassis", F, -L / 2, L / 2, 3.2, 4, -W / 2, W / 2, rgb(40, 40, 44), M.Metal)
	local box = Box(m, "WagonBox", F, -L / 2 + 0.3, L / 2 - 0.3, 4, 4 + H, -W / 2 + 0.2, W / 2 - 0.2, body, M.CorrodedMetal, true)
	Box(m, "WagonRoof", F, -L / 2 + 0.1, L / 2 - 0.1, 4 + H, 4.6 + H, -W / 2, W / 2, rgb(80, 80, 86), M.Metal)
	for i = 0, 8 do
		local x = -L / 2 + 1.6 + i * (L - 3.2) / 8
		for _, z in ipairs({ -W / 2 + 0.12, W / 2 - 0.12 }) do
			Box(m, "WagonRib", F, x - 0.15, x + 0.15, 4, 4 + H, z - 0.1, z + 0.1, body:Lerp(Color3.new(0, 0, 0), 0.25), M.Metal)
		end
	end
	Box(m, "SlideDoor", F, -3, 3, 4.4, 3.6 + H, -W / 2 + 0.02, -W / 2 + 0.1, body:Lerp(Color3.new(1, 1, 1), 0.1), M.CorrodedMetal)
	-- tag sur la caisse
	local gui = CityKit.Canvas(box, Enum.NormalId.Front, 160, 8)
	CityKit.Blob(gui, 0.22, 0.5, 0.26, 0.6, CityKit.Pick(MURAL_COLORS, seed, 4), 0.5, -6)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(0.3, 0.5)
	lbl.Position = UDim2.fromScale(0.08, 0.25)
	lbl.Text = "ZAP"
	lbl.TextScaled = true
	lbl.Font = Enum.Font.Arcade
	lbl.TextColor3 = WHITE
	lbl.Parent = gui
	-- heurtoir au bout de la voie
	local S = F * CFrame.new(L / 2 + 3, 0, 0)
	Box(m, "BufferFrame", S, -0.6, 0.6, 0.5, 4.2, -3.2, 3.2, rgb(200, 40, 40), M.Metal, true)
	for _, z in ipairs({ -1.6, 1.6 }) do
		Part(m, "BufferPad", Vector3.new(1, 1.2, 1.2), S * CFrame.new(-1, 3.2, z), rgb(40, 40, 44), M.Metal, "Cyl")
	end
end

----------------------------------------------------------------------
-- 🌮 Cour des food trucks
----------------------------------------------------------------------

local function foodTruck(m: Model, T: CFrame, color: Color3, label: string, seed: number)
	-- camion : cabine à gauche (-x), caisse, comptoir côté -Z
	Box(m, "TruckBox", T, -4, 6, 1.6, 10, -3.2, 3.2, color, M.SmoothPlastic, true)
	Box(m, "TruckCab", T, -8, -4, 1.6, 7.6, -3, 3, color:Lerp(Color3.new(1, 1, 1), 0.2), M.SmoothPlastic, true)
	Box(m, "Windshield", T, -8.06, -7.94, 4.4, 7, -2.6, 2.6, GLASS, M.Glass)
	for _, x in ipairs({ -6, 3.6 }) do
		for _, z in ipairs({ -3, 3 }) do
			Part(m, "Tyre", Vector3.new(0.9, 2.4, 2.4), T * CFrame.new(x, 1.2, z) * CFrame.Angles(0, math.pi / 2, 0), rgb(30, 30, 34), M.Rubber, "Cyl")
		end
	end
	Box(m, "Hatch", T, -3, 5, 4.6, 8.2, -3.24, -3.2, rgb(30, 30, 34), M.SmoothPlastic)
	Glow(Box(m, "HatchInside", T, -2.8, 4.8, 4.8, 8, -3.2, -3.16, WARM, M.SmoothPlastic))
	Box(m, "Counter", T, -3.2, 5.2, 4.3, 4.6, -4.4, -3.2, rgb(200, 200, 206), M.Metal)
	Box(m, "HatchFlap", T, -3.2, 5.2, 8.2, 8.4, -5.4, -3.2, color:Lerp(Color3.new(0, 0, 0), 0.15), M.SmoothPlastic)
	local sign = Box(m, "TruckSign", T, -3.5, 5.5, 8.6, 9.8, -3.3, -3.2, WHITE, M.SmoothPlastic)
	Text(sign, Enum.NormalId.Front, label, color, nil, Enum.Font.FredokaOne, 120)
	local chef = CityKit.Npc(m, "baker", seed, T * CFrame.new(1, 1.6, -1.6) * CFrame.Angles(0, math.pi, 0), "none", false)
	CityKit.Idle(chef, "scan", hash(seed, 1) * 7)
end

local function buildFoodTrucks(m: Model, F: CFrame, seed: number)
	Box(m, "Court", F, -20, 20, -0.1, 0.18, -15, 15, rgb(120, 120, 124), M.Asphalt, true)
	foodTruck(m, F * CFrame.new(-12, 0.18, 8) * CFrame.Angles(0, 0, 0), rgb(240, 90, 60), "🌮 " .. Locale.T("Tacos"), seed + 1)
	foodTruck(m, F * CFrame.new(10, 0.18, 8), rgb(60, 150, 220), "🍔 " .. Locale.T("Burgers"), seed + 2)
	foodTruck(m, F * CFrame.new(-2, 0.18, -10) * CFrame.Angles(0, math.pi, 0), rgb(250, 190, 40), "🍜 " .. Locale.T("Noodles"), seed + 3)
	-- guirlande de guinguette entre 4 mâts
	local masts = { Vector3.new(-18, 0, -13), Vector3.new(18, 0, -13), Vector3.new(18, 0, 13), Vector3.new(-18, 0, 13) }
	for _, p in ipairs(masts) do
		Column(m, "Mast", F, p.X, p.Z, 0.18, 12, 0.4, STEEL, M.Metal, true)
	end
	for i = 1, 4 do
		local a, b = masts[i], masts[i % 4 + 1]
		local n = 7
		for k = 0, n do
			local f = k / n
			local sag = math.sin(f * math.pi) * 1.8
			local p = (F * CFrame.new(a.X + (b.X - a.X) * f, 11.6 - sag, a.Z + (b.Z - a.Z) * f)).Position
			if k > 0 and k < n then
				Glow(CityKit.Ball(m, "Bulb", p, 0.45, CityKit.Pick({ WARM, rgb(255, 180, 120), rgb(255, 240, 200) }, seed, k + i * 9), M.Glass))
			end
		end
		local mid = (F * CFrame.new((a.X + b.X) / 2, 11.6 - 1.8, (a.Z + b.Z) / 2)).Position
		CityKit.Rod(m, "Wire", (F * CFrame.new(a.X, 11.6, a.Z)).Position, mid, 0.05, rgb(30, 30, 34), M.SmoothPlastic)
		CityKit.Rod(m, "Wire", mid, (F * CFrame.new(b.X, 11.6, b.Z)).Position, 0.05, rgb(30, 30, 34), M.SmoothPlastic)
	end
	-- tables hautes (mange-debout en tourets) + clients
	for i = 0, 2 do
		local T = F * CFrame.new(-8 + i * 8, 0.18, 0)
		Column(m, "Spool", T, 0, 0, 0, 3.6, 3.2, WOOD, M.WoodPlanks, true)
		Column(m, "SpoolTop", T, 0, 0, 3.6, 3.9, 3.8, rgb(170, 124, 84), M.WoodPlanks)
		local c = CityKit.Npc(m, CityKit.Pick({ "pedestrian", "shopper", "jogger" }, seed, i), seed * 19 + i, T * CFrame.new(0, 0, 2.6) * CFrame.Angles(0, 0, 0), i == 1 and "coffee" or "none", true)
		CityKit.Idle(c, "talk", i * 1.7)
	end
	-- file devant le camion à tacos
	for k = 0, 2 do
		local q = CityKit.Npc(m, CityKit.Pick({ "pedestrian", "kid", "shopper", "elder" }, seed, k + 30), seed * 23 + k, F * CFrame.new(-10 + k * 0.6, 0.18, 2.2 - k * 2.2) * CFrame.Angles(0, math.pi, 0), k == 0 and "phone" or "none", true)
		CityKit.Idle(q, "idle", k * 2.3)
	end
end

----------------------------------------------------------------------
-- 📦 Conteneurs, lampadaire industriel, clôture
----------------------------------------------------------------------

local function container(m: Model, C: CFrame, color: Color3, open: boolean)
	local L, W, H = 12, 5, 5.4
	local shell = Box(m, "Container", C, -L / 2, L / 2, 0, H, -W / 2, W / 2, color, M.CorrodedMetal, true)
	local _ = shell
	for i = 0, 9 do
		local x = -L / 2 + 0.6 + i * (L - 1.2) / 9
		for _, z in ipairs({ -W / 2, W / 2 }) do
			Box(m, "Corrugation", C, x - 0.14, x + 0.14, 0.3, H - 0.3, z - 0.08, z + 0.08, color:Lerp(Color3.new(0, 0, 0), 0.18), M.Metal)
		end
	end
	if open then
		Glow(Box(m, "ContainerWindow", C, -4, 3, 1.4, 4.4, -W / 2 - 0.14, -W / 2 - 0.08, WARM, M.Glass))
		Box(m, "ContainerFlap", C, -4.4, 3.4, 4.6, 4.8, -W / 2 - 2.2, -W / 2 - 0.1, color, M.Metal)
	end
end

local function buildContainers(m: Model, F: CFrame, seed: number)
	local cols = { rgb(200, 60, 50), rgb(40, 110, 170), rgb(240, 180, 40), rgb(60, 140, 90) }
	container(m, F * CFrame.new(-6, 0, 2), CityKit.Pick(cols, seed, 1), true)
	container(m, F * CFrame.new(6.2, 0, 2), CityKit.Pick(cols, seed, 2), true)
	container(m, F * CFrame.new(0, 5.42, 2.4) * CFrame.Angles(0, 0.05, 0), CityKit.Pick(cols, seed, 3), false)
	-- escalier métallique vers le conteneur du haut + terrasse
	CityKit.Beam(m, "Stair", (F * CFrame.new(10.8, 0, -3)).Position, (F * CFrame.new(10.8, 5.4, 2)).Position, 2.4, 0.3, STEEL, M.DiamondPlate)
	local sign = Box(m, "ContainerSign", F, -5, 5, 11, 12.6, -0.2, 0, rgb(30, 30, 34), M.Metal)
	Text(sign, Enum.NormalId.Front, "📦 " .. Locale.T("Container market"), rgb(255, 214, 40), nil, Enum.Font.Arcade, 160)
	Column(m, "SignPole", F, -4.6, -0.1, 10.8, 11.1, 0.2, STEEL, M.Metal)
	local seller = CityKit.Npc(m, "salesperson", seed * 29 + 1, F * CFrame.new(-6, 0, -1.6) * CFrame.Angles(0, math.pi, 0), "tablet", true)
	CityKit.Idle(seller, "type", 3)
end

local function buildLamp(m: Model, F: CFrame, _seed: number)
	Column(m, "LampFoot", F, 0, 0, 0, 0.8, 1, STEEL, M.Metal, true)
	Column(m, "LampPole", F, 0, 0, 0.8, 13, 0.4, STEEL, M.Metal, true)
	Box(m, "LampArm", F, -0.1, 0.1, 12.6, 12.9, -3.2, 0, STEEL, M.Metal)
	CityKit.Rod(m, "LampCable", (F * CFrame.new(0, 12.6, -3)).Position, (F * CFrame.new(0, 11.4, -3)).Position, 0.06, rgb(30, 30, 34), M.SmoothPlastic)
	Egg(m, "LampShade", F * CFrame.new(0, 11.1, -3), Vector3.new(1.8, 0.9, 1.8), rgb(40, 70, 60), M.Metal)
	Glow(CityKit.Ball(m, "LampBulb", (F * CFrame.new(0, 10.6, -3)).Position, 0.6, WARM, M.Glass))
	for k = 0, 3 do
		local a = k * math.pi / 2
		CityKit.Rod(m, "LampCage", (F * CFrame.new(math.cos(a) * 0.5, 10.7, -3 + math.sin(a) * 0.5)).Position, (F * CFrame.new(math.cos(a) * 0.3, 10.1, -3 + math.sin(a) * 0.3)).Position, 0.05, rgb(30, 30, 34), M.Metal)
	end
end

local function buildFence(m: Model, F: CFrame, seed: number, spot: any)
	local L = spot and spot.Size and spot.Size.X or 20
	local n = math.max(1, math.floor(L / 8 + 0.5))
	for i = 0, n do
		local x = -L / 2 + i * L / n
		Column(m, "FencePost", F, x, 0, 0, 7, 0.24, STEEL_L, M.Metal, true)
	end
	Box(m, "FenceTopRail", F, -L / 2, L / 2, 6.8, 7, -0.08, 0.08, STEEL_L, M.Metal)
	local mesh = Box(m, "FenceMesh", F, -L / 2, L / 2, 0.2, 6.8, -0.03, 0.03, STEEL_L, M.DiamondPlate, true)
	mesh.Transparency = 0.6
	local _ = seed
end

DistrictLoft.BUILDERS = {
	LftWarehouse = buildWarehouse,
	LftMural = buildMural,
	LftRail = buildRail,
	LftWagon = buildWagon,
	LftFoodTrucks = buildFoodTrucks,
	LftContainers = buildContainers,
	LftLamp = buildLamp,
	LftFence = buildFence,
}
DistrictLoft.BIG = { LftWarehouse = true, LftFoodTrucks = true, LftWagon = true, LftRail = true, LftMural = true }
DistrictLoft.IMPOSTORS = {
	LftWarehouse = function(m: Model, F: CFrame)
		local B = F * CFrame.new(0, 0, 3)
		Box(m, "ImpHall", B, -18, 18, 0, 18.6, -13, 13, BRICK, M.Brick, true)
		Column(m, "ImpStack", B * CFrame.new(14, 0, 16), 0, 0, 0, 40, 3.6, BRICK_D, M.Brick, true)
	end,
	LftRail = function(m: Model, F: CFrame, _seed: number, spot: any)
		local L = spot and spot.Size and spot.Size.X or 40
		Box(m, "ImpBallast", F, -L / 2, L / 2, -0.2, 0.9, -3.6, 3.6, rgb(120, 112, 104), M.Slate)
	end,
}

return DistrictLoft
