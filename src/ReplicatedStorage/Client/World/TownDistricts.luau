--[[
	TownDistricts (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownDistricts

	🏙️ Dopamine Town (v9.9, CITY99) : "plus de zone morte". Les nouveaux
	lieux posés par le serveur dans les coins les plus vides de l'anneau
	(TownNature : emplacements "SkatePark", "CommunityGarden",
	"SportsCorner" + une allée pavée qui les relie au réseau + un poteau
	indicateur), construits ICI côté client, en flux (TownStreetLife) :
	  - 🛹 SKATEPARK : dalle de béton à joints, 2 quarter-pipes à courbe
	    circulaire (vraies pentes où l'on peut courir), funbox avec
	    plans inclinés, rail de glisse, module "ledge" à arête d'acier,
	    grillage, mur de graffitis, lampadaires ; 2 SKATEURS (NPCModels)
	    qui roulent pour de vrai : aller-retour d'une rampe à l'autre (la
	    planche suit la courbe), tour de la funbox avec des ollies ;
	  - 🥕 JARDINS PARTAGÉS : haie basse et portail en arche, 6 carrés
	    potagers surélevés (salades, carottes, tomates tuteurées, citrouilles,
	    fraises, tournesols), serre vitrée, cabane à outils, composteurs,
	    récupérateur d'eau, brouette, arrosoir, épouvantail ; 2 jardiniers ;
	  - 🏓 COIN SPORT : 2 tables de ping-pong en béton (une partie EN COURS :
	    la balle fait l'aller-retour, rebond sur la table), terrain de
	    pétanque (boules, cochonnet) et ses joueurs, agrès de fitness (barre
	    fixe, barres parallèles, banc à abdos) sur sol souple.
	Tout est ancré ; rampes, dalles et gros modules sont solides (collision
	locale : on y court, on y saute) ; le reste est décor. Aucune lumière
	(verres "NightGlow" : Neon la nuit via TownAtmosphere), aucun son.
	Animation des personnages : à chaque image, seulement près de la caméra
	(< 110 studs), sans création d'instance.

	API (TownStreetLife) :
	  TownDistricts.BUILDERS : { [kind]: (m, F, seed) -> any }
	  TownDistricts.BIG      : types vus de loin
	  TownDistricts.Step(dt) : à chaque image (personnages proches)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local NPCModels = require(ReplicatedStorage.Shared.NPCModels)

local TownDistricts = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
local ANIM_R = 110

local CONCRETE = rgb(196, 196, 192)
local CONCRETE_D = rgb(170, 170, 166)
local STEEL = rgb(176, 180, 188)
local GRAPHITE = rgb(52, 54, 60)
local WOOD = rgb(176, 124, 84)
local WOOD_D = rgb(128, 88, 58)
local SOIL = rgb(96, 70, 52)
local LEAF = rgb(84, 150, 76)
local LEAF_D = rgb(60, 118, 58)
local WHITE = rgb(250, 250, 248)
local GLASS = rgb(200, 226, 236)

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?, solid: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = solid == true or size.Magnitude > 3
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Parent = parent
	return p
end

-- boîte par ses bornes (repère F)
local function box(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return newPart(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, nil, solid)
end

local function column(parent: Instance, name: string, F: CFrame, x: number, z: number, y0: number, y1: number, d: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return newPart(parent, name, Vector3.new(y1 - y0, d, d), F * CFrame.new(x, (y0 + y1) / 2, z) * UPRIGHT, color, material, "Cyl", solid)
end

local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local axis = b - a
	local up = math.abs(axis.Unit.Y) > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	return newPart(parent, name, Vector3.new(axis.Magnitude, d, d), CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0), color, material, "Cyl", solid)
end

local function egg(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	return newPart(parent, name, size, cf, color, material, "Egg")
end

local function glow(p: BasePart): BasePart
	p.Material = M.SmoothPlastic
	p:SetAttribute("NightGlow", true)
	return p
end

local function surfaceText(host: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, maxDistance: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.7
	gui.MaxDistance = maxDistance or 110
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = bg and 0 or 1
	label.BackgroundColor3 = bg or WHITE
	label.BorderSizePixel = 0
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBold
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	return label
end

local function lampPost(m: Model, F: CFrame, x: number, z: number, facing: number)
	local iron = rgb(56, 52, 70)
	local L = F * CFrame.new(x, 0, z) * CFrame.Angles(0, facing, 0)
	column(m, "LampFoot", L, 0, 0, -0.05, 0.9, 1.1, iron, M.Metal, true)
	column(m, "LampPole", L, 0, 0, 0.85, 12.2, 0.36, iron, M.Metal, true)
	box(m, "LampArm", L, -0.08, 0.08, 12.0, 12.2, -2.2, 0, iron, M.Metal)
	box(m, "LampHood", L, -0.7, 0.7, 11.9, 12.25, -2.8, -1.4, iron, M.Metal)
	glow(box(m, "LampGlass", L, -0.4, 0.4, 11.3, 11.9, -2.5, -1.7, rgb(255, 232, 180), M.SmoothPlastic))
end

-- Personnage (NPCModels) : décor si pas d'animation ; `solid` = capsule
local function npc(m: Model, style: string, seed: number, cf: CFrame, prop: string?, solid: boolean?): Model?
	local ok, model = pcall(function()
		return NPCModels.Build(style, { Seed = seed, Prop = prop or "none", Solid = solid ~= false })
	end)
	if not ok or not model then
		return nil
	end
	model.Parent = m
	model:PivotTo(cf)
	return model
end

----------------------------------------------------------------------
-- Acteurs animés (à chaque image, près de la caméra)
----------------------------------------------------------------------

type Actor = { Model: Model, Kind: string, Data: any, Phase: number }
local actors: { Actor } = {}

local function addActor(model: Model?, kind: string, data: any, phase: number)
	if model then
		table.insert(actors, { Model = model, Kind = kind, Data = data, Phase = phase })
	end
end

----------------------------------------------------------------------
-- 🛹 Skatepark
----------------------------------------------------------------------

local PAD_TOP = 0.3 -- dessus de la dalle au-dessus du sol
local QP_R = 4.6 -- rayon de courbure des quarter-pipes
local QP_MAX = math.rad(75) -- angle au sommet (lèvre)
local QP_CX = 7.2 -- |x| du bas de la courbe (le plat entre les deux rampes : -7,2..7,2)
local QP_W = 8 -- largeur des rampes (z)

-- Hauteur (au-dessus de la dalle) et pente du sol du skatepark à l'abscisse x
local function skateGround(x: number): (number, number)
	local ax = math.abs(x)
	if ax <= QP_CX then
		return 0, 0
	end
	local s = math.clamp((ax - QP_CX) / QP_R, 0, math.sin(QP_MAX))
	local a = math.asin(s)
	return QP_R * (1 - math.cos(a)), (x > 0 and 1 or -1) * a
end

-- Planche de skate (plateau à kicktails, 2 trucks, 4 roues) : `cf` =
-- dessous des roues, planche le long de X
local function skateboard(m: Model, name: string, color: Color3, at: CFrame): { BasePart }
	local parts = {}
	local function add(p: BasePart)
		table.insert(parts, p)
	end
	local deck = newPart(m, name .. "Deck", Vector3.new(2.3, 0.07, 0.72), CFrame.identity, color, M.Wood)
	add(deck)
	add(newPart(m, name .. "Grip", Vector3.new(2.28, 0.02, 0.7), CFrame.identity, rgb(34, 34, 38), M.Sand))
	for _, sx in ipairs({ -1, 1 }) do
		add(newPart(m, name .. "Tail", Vector3.new(0.4, 0.07, 0.66), CFrame.identity, color, M.Wood))
		add(newPart(m, name .. "Truck", Vector3.new(0.16, 0.12, 0.62), CFrame.identity, STEEL, M.Metal))
		for _, sz in ipairs({ -1, 1 }) do
			add(newPart(m, name .. "Wheel", Vector3.new(0.14, 0.2, 0.2), CFrame.identity, rgb(246, 240, 226), M.SmoothPlastic, "Cyl"))
		end
	end
	return parts
end

-- Repères (relatifs au dessous des roues) des pièces de la planche, même ordre
local BOARD_LOCAL: { CFrame } = (function()
	local list = { CFrame.new(0, 0.3, 0), CFrame.new(0, 0.345, 0) }
	for _, sx in ipairs({ -1, 1 }) do
		table.insert(list, CFrame.new(sx * 1.3, 0.34, 0) * CFrame.Angles(0, 0, sx * math.rad(16)))
		table.insert(list, CFrame.new(sx * 0.78, 0.2, 0))
		for _, sz in ipairs({ -1, 1 }) do
			table.insert(list, CFrame.new(sx * 0.78, 0.1, sz * 0.36) * CFrame.Angles(0, math.rad(90), 0))
		end
	end
	return list
end)()

local function buildSkatePark(m: Model, F: CFrame, seed: number)
	local W, D = 30, 20
	local P = F * CFrame.new(0, PAD_TOP, 0) -- dessus de la dalle
	box(m, "SkatePad", F, -W / 2, W / 2, -0.6, PAD_TOP, -D / 2, D / 2, CONCRETE, M.Concrete, true)
	-- joints de dilatation (quadrillage 5 x 5)
	for x = -W / 2 + 5, W / 2 - 5, 5 do
		box(m, "PadJoint", P, x - 0.05, x + 0.05, -0.3, 0.035, -D / 2 + 0.2, D / 2 - 0.2, CONCRETE_D, M.Concrete)
	end
	for z = -D / 2 + 5, D / 2 - 5, 5 do
		box(m, "PadJoint", P, -W / 2 + 0.2, W / 2 - 0.2, -0.33, 0.07, z - 0.05, z + 0.05, CONCRETE_D, M.Concrete)
	end
	-- 2 quarter-pipes (courbe circulaire en 7 dalles tangentes, lèvre en acier, plateforme, dos)
	for _, sx in ipairs({ -1, 1 }) do
		local n = 7
		local prev = Vector3.new(QP_CX, 0, 0)
		for i = 1, n do
			local a = QP_MAX * i / n
			local pt = Vector3.new(QP_CX + QP_R * math.sin(a), QP_R * (1 - math.cos(a)), 0)
			local mid = (prev + pt) / 2
			local len = (pt - prev).Magnitude
			local slope = math.atan2(pt.Y - prev.Y, pt.X - prev.X)
			-- dalle : dessus sur la corde, épaisseur 0,5 vers l'intérieur de la courbe
			local cf = P * CFrame.new(sx * mid.X, mid.Y, 0) * CFrame.Angles(0, 0, sx * slope) * CFrame.new(0, -0.25, 0)
			newPart(m, "RampSlab", Vector3.new(len + 0.12, 0.5, QP_W), cf, CONCRETE, M.Concrete, nil, true)
			-- massif en béton sous la dalle (marches cachées sous la courbe)
			local under = prev.Y - 0.45
			if under > 0.05 then
				local x0, x1 = prev.X, pt.X
				box(m, "RampFill", P, sx > 0 and x0 or -x1, sx > 0 and x1 or -x0, -0.3, under, -QP_W / 2 + 0.05, QP_W / 2 - 0.05, CONCRETE_D, M.Concrete)
			end
			prev = pt
		end
		local lipX = QP_CX + QP_R * math.sin(QP_MAX)
		local lipY = QP_R * (1 - math.cos(QP_MAX))
		-- plateforme + coping + dos + montants
		box(m, "Deck", P, sx > 0 and lipX + 0.05 or -lipX - 2.4, sx > 0 and lipX + 2.4 or -lipX - 0.05, lipY - 0.4, lipY, -QP_W / 2 - 0.05, QP_W / 2 + 0.05, CONCRETE_D, M.Concrete, true)
		rod(m, "Coping", (P * CFrame.new(sx * lipX, lipY - 0.05, -QP_W / 2)).Position, (P * CFrame.new(sx * lipX, lipY - 0.05, QP_W / 2)).Position, 0.3, STEEL, M.Metal)
		box(m, "RampBack", P, sx > 0 and lipX + 2.4 or -lipX - 2.6, sx > 0 and lipX + 2.6 or -lipX - 2.4, -0.3, lipY, -QP_W / 2, QP_W / 2, rgb(150, 150, 150), M.Concrete, true)
		-- garde-corps sur la plateforme
		for _, z in ipairs({ -QP_W / 2 + 0.2, QP_W / 2 - 0.2 }) do
			column(m, "RailPost", P, sx * (lipX + 2.3), z, lipY, lipY + 3.2, 0.18, GRAPHITE, M.Metal)
		end
		rod(m, "GuardRail", (P * CFrame.new(sx * (lipX + 2.3), lipY + 3.2, -QP_W / 2 + 0.2)).Position, (P * CFrame.new(sx * (lipX + 2.3), lipY + 3.2, QP_W / 2 - 0.2)).Position, 0.16, GRAPHITE, M.Metal)
	end
	-- funbox (plateau + 2 plans inclinés) au milieu, un peu décalée
	local FB = P * CFrame.new(0, 0, -5.4)
	box(m, "Funbox", FB, -2.2, 2.2, -0.3, 1.4, -1.8, 1.8, CONCRETE_D, M.Concrete, true)
	for _, sx in ipairs({ -1, 1 }) do
		wedge(m, "FunRamp", Vector3.new(3.6, 1.7, 3.4), FB * CFrame.new(sx * (2.2 + 1.7), 0.55, 0) * CFrame.Angles(0, sx > 0 and math.rad(-90) or math.rad(90), 0), CONCRETE, M.Concrete, true)
	end
	rod(m, "FunCoping", (FB * CFrame.new(-2.2, 1.4, -1.8)).Position, (FB * CFrame.new(2.2, 1.4, -1.8)).Position, 0.22, STEEL, M.Metal)
	-- rail de glisse
	local rail = P * CFrame.new(0, 0, 5.6)
	for _, x in ipairs({ -3.4, 0, 3.4 }) do
		column(m, "RailLeg", rail, x, 0, -0.1, 1.2, 0.2, GRAPHITE, M.Metal)
	end
	rod(m, "GrindRail", (rail * CFrame.new(-4.2, 1.25, 0)).Position, (rail * CFrame.new(4.2, 1.25, 0)).Position, 0.26, STEEL, M.Metal, true)
	-- ledge en béton à arête d'acier (côté fond)
	local ledge = P * CFrame.new(0, 0, 8.3)
	box(m, "Ledge", ledge, -5, 5, -0.3, 1.1, -0.8, 0.8, CONCRETE_D, M.Concrete, true)
	box(m, "LedgeEdge", ledge, -5.04, 5.04, 1.0, 1.15, -0.86, -0.7, STEEL, M.Metal)
	-- grillage sur les deux longs côtés (entrée au milieu du côté -Z)
	for _, sz in ipairs({ -1, 1 }) do
		for _, seg in ipairs(sz < 0 and { { -W / 2, -3 }, { 3, W / 2 } } or { { -W / 2, W / 2 } }) do
			local x0, x1 = seg[1], seg[2]
			local mesh = box(m, "FenceMesh", F, x0 + 0.1, x1 - 0.1, 0.4, 4.2, sz * (D / 2 + 0.6) - 0.04, sz * (D / 2 + 0.6) + 0.04, rgb(150, 156, 164), M.DiamondPlate, true)
			mesh.Transparency = 0.62
			box(m, "FenceTop", F, x0, x1, 4.2, 4.34, sz * (D / 2 + 0.6) - 0.08, sz * (D / 2 + 0.6) + 0.08, GRAPHITE, M.Metal)
			for x = x0, x1 + 0.01, (x1 - x0) / math.max(1, math.floor((x1 - x0) / 6)) do
				column(m, "FencePost", F, x, sz * (D / 2 + 0.6), -0.1, 4.4, 0.2, GRAPHITE, M.Metal)
			end
		end
	end
	-- mur de graffitis derrière le ledge (+Z), côté skatepark
	local wall = F * CFrame.new(0, 0, D / 2 + 2.4)
	local wallPart = box(m, "GraffitiWall", wall, -9, 9, 0, 5.2, -0.4, 0.4, rgb(210, 206, 200), M.Concrete, true)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Graffiti"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0.8
	gui.MaxDistance = 160
	gui.Parent = wallPart
	local tags = {
		{ "SKATE", 0.02, 0.05, 0.42, 0.55, rgb(255, 90, 160), Enum.Font.FredokaOne, -6 },
		{ "🧠DOPA", 0.44, 0.1, 0.34, 0.45, rgb(90, 200, 255), Enum.Font.LuckiestGuy, 4 },
		{ "★ CREW ★", 0.76, 0.2, 0.22, 0.3, rgb(255, 214, 60), Enum.Font.Bangers, -3 },
		{ "ollie!", 0.1, 0.62, 0.3, 0.3, rgb(140, 255, 140), Enum.Font.PermanentMarker, 3 },
		{ "♥ 2026", 0.5, 0.6, 0.3, 0.32, rgb(255, 130, 60), Enum.Font.Creepster, -5 },
	}
	for _, t in ipairs(tags) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(t[2] :: number, t[3] :: number)
		l.Size = UDim2.fromScale(t[4] :: number, t[5] :: number)
		l.Text = t[1] :: string
		l.TextScaled = true
		l.TextColor3 = t[6] :: Color3
		l.Font = t[7] :: Enum.Font
		l.Rotation = t[8] :: number
		l.TextStrokeTransparency = 0.2
		l.TextStrokeColor3 = rgb(30, 30, 40)
		l.Parent = gui
	end
	-- panneau d'entrée + lampadaires
	local sign = box(m, "SkateSign", F, -3.2, 3.2, 4.6, 5.8, -(D / 2 + 0.8), -(D / 2 + 0.6), rgb(30, 30, 40), M.Metal)
	surfaceText(sign, Enum.NormalId.Front, "🛹 " .. Locale.T("Skate park"), rgb(255, 214, 60), rgb(30, 30, 40), Enum.Font.FredokaOne, 120)
	lampPost(m, F, -W / 2 - 1.2, -D / 2 - 1.6, math.rad(-135))
	lampPost(m, F, W / 2 + 1.2, D / 2 + 1.6, math.rad(45))
	-- 2 skateurs : aller-retour entre les rampes, tour de la funbox
	local colors = { rgb(236, 72, 100), rgb(60, 140, 220) }
	for i = 1, 2 do
		local style = i == 1 and "kid" or "pedestrian"
		local rider = npc(m, style, seed * 13 + i, P, "none", false)
		local board = skateboard(m, "Board" .. i, colors[i], P * CFrame.new(0, 0, i * 3 - 4.5))
		for k, part in ipairs(board) do
			part.CFrame = P * CFrame.new(0, 0, i * 3 - 4.5) * BOARD_LOCAL[k]
		end
		addActor(rider, "Skater", { P = P, Board = board, Mode = i }, hash(seed, i) * 10)
	end
end

----------------------------------------------------------------------
-- 🥕 Jardins partagés
----------------------------------------------------------------------

local function raisedBed(m: Model, F: CFrame, kind: number, seed: number)
	local L, Wd, H = 6, 2.4, 0.9
	-- cadre en planches (4 côtés) + terre
	for _, sz in ipairs({ -1, 1 }) do
		box(m, "BedBoard", F, -L / 2, L / 2, 0, H, sz * Wd / 2 - 0.12, sz * Wd / 2 + 0.12, WOOD, M.WoodPlanks, true)
	end
	for _, sx in ipairs({ -1, 1 }) do
		box(m, "BedBoard", F, sx * L / 2 - 0.12, sx * L / 2 + 0.12, 0, H, -Wd / 2 + 0.12, Wd / 2 - 0.12, WOOD_D, M.WoodPlanks, true)
	end
	box(m, "BedSoil", F, -L / 2 + 0.12, L / 2 - 0.12, 0, H - 0.1, -Wd / 2 + 0.12, Wd / 2 - 0.12, SOIL, M.Ground)
	local top = H - 0.1
	if kind == 1 then
		-- salades : rangées de boules vert tendre
		for i = 0, 5 do
			for _, z in ipairs({ -0.55, 0.55 }) do
				egg(m, "Lettuce", F * CFrame.new(-2.4 + i * 0.96, top + 0.22, z), Vector3.new(0.72, 0.5, 0.72), (i % 2 == 0) and rgb(150, 206, 96) or rgb(120, 180, 80), M.Grass)
			end
		end
	elseif kind == 2 then
		-- carottes : fanes plumeuses + collet orange
		for i = 0, 7 do
			for _, z in ipairs({ -0.5, 0.5 }) do
				local x = -2.5 + i * 0.72
				egg(m, "CarrotTop", F * CFrame.new(x, top + 0.4, z), Vector3.new(0.34, 0.8, 0.34), LEAF, M.Grass)
				newPart(m, "CarrotNeck", Vector3.new(0.1, 0.18, 0.18), F * CFrame.new(x, top + 0.03, z) * UPRIGHT, rgb(246, 140, 40), M.SmoothPlastic, "Cyl")
			end
		end
	elseif kind == 3 then
		-- tomates tuteurées
		for i = 0, 3 do
			local x = -2.1 + i * 1.4
			column(m, "Stake", F, x, 0, top, top + 2.8, 0.1, rgb(190, 160, 110), M.Wood)
			egg(m, "TomatoPlant", F * CFrame.new(x, top + 1.3, 0), Vector3.new(1.1, 2.2, 1.1), LEAF_D, M.Grass)
			for k = 0, 2 do
				local a = k * 2.1 + i
				newPart(m, "Tomato", Vector3.new(0.3, 0.3, 0.3), F * CFrame.new(x + math.cos(a) * 0.45, top + 0.9 + k * 0.45, math.sin(a) * 0.45), (k == 2 and hash(seed, i) < 0.5) and rgb(250, 170, 60) or rgb(220, 40, 40), M.SmoothPlastic, "Ball")
			end
		end
	elseif kind == 4 then
		-- citrouilles (côtes) + grandes feuilles
		for i = 0, 2 do
			local x = -1.9 + i * 1.9
			egg(m, "Pumpkin", F * CFrame.new(x, top + 0.35, 0), Vector3.new(1.1, 0.75, 1.0), rgb(236, 128, 36), M.SmoothPlastic)
			newPart(m, "PumpkinStem", Vector3.new(0.3, 0.12, 0.12), F * CFrame.new(x, top + 0.8, 0) * UPRIGHT, rgb(110, 120, 60), M.Wood, "Cyl")
			egg(m, "PumpkinLeaf", F * CFrame.new(x + 0.6, top + 0.2, 0.6), Vector3.new(1.1, 0.2, 0.9), LEAF, M.Grass)
		end
	elseif kind == 5 then
		-- fraises : touffes + fruits rouges
		for i = 0, 5 do
			for _, z in ipairs({ -0.55, 0.55 }) do
				local x = -2.4 + i * 0.96
				egg(m, "StrawLeaves", F * CFrame.new(x, top + 0.18, z), Vector3.new(0.7, 0.34, 0.7), LEAF, M.Grass)
				egg(m, "Strawberry", F * CFrame.new(x + 0.28, top + 0.12, z + 0.2), Vector3.new(0.16, 0.2, 0.16), rgb(230, 30, 60), M.SmoothPlastic)
			end
		end
	else
		-- tournesols
		for i = 0, 3 do
			local x = -2.1 + i * 1.4
			local h = 3.2 + hash(seed, i) * 1.2
			column(m, "SunStem", F, x, 0, top, top + h, 0.16, LEAF_D, M.Grass)
			egg(m, "SunLeaf", F * CFrame.new(x + 0.35, top + h * 0.45, 0), Vector3.new(0.8, 0.12, 0.5), LEAF, M.Grass)
			local headCF = F * CFrame.new(x, top + h + 0.1, -0.15) * CFrame.Angles(math.rad(-20), 0, 0)
			newPart(m, "SunPetals", Vector3.new(0.12, 1.3, 1.3), headCF * CFrame.Angles(0, math.rad(90), 0), rgb(255, 204, 30), M.SmoothPlastic, "Cyl")
			newPart(m, "SunCenter", Vector3.new(0.16, 0.66, 0.66), headCF * CFrame.new(0, 0, -0.04) * CFrame.Angles(0, math.rad(90), 0), rgb(96, 60, 30), M.Grass, "Cyl")
		end
	end
end

local function buildCommunityGarden(m: Model, F: CFrame, seed: number)
	local W, D = 26, 20
	-- allées en gravier (en croix)
	box(m, "GardenPath", F, -1.2, 1.2, -0.3, 0.1, -D / 2, D / 2, rgb(214, 204, 184), M.Pebble)
	box(m, "GardenPath", F, -W / 2 + 1, W / 2 - 1, -0.32, 0.08, -1.1, 1.1, rgb(214, 204, 184), M.Pebble)
	-- haie basse (entrée au milieu du côté -Z) + portail en arche
	local hedge = rgb(70, 132, 66)
	for _, seg in ipairs({ { -W / 2, -2.2, -D / 2 }, { 2.2, W / 2, -D / 2 }, { -W / 2, W / 2, D / 2 } }) do
		local x0, x1, z = seg[1], seg[2], seg[3]
		egg(m, "Hedge", F * CFrame.new((x0 + x1) / 2, 0.8, z), Vector3.new(x1 - x0, 1.9, 1.3), hedge, M.Grass)
	end
	for _, sx in ipairs({ -1, 1 }) do
		egg(m, "Hedge", F * CFrame.new(sx * W / 2, 0.8, 0), Vector3.new(1.3, 1.9, D), hedge, M.Grass)
	end
	for _, sx in ipairs({ -1, 1 }) do
		column(m, "ArchPost", F, sx * 2.1, -D / 2, -0.1, 7, 0.4, WHITE, M.Wood, true)
	end
	for k = 0, 6 do
		local a = math.rad(180 * k / 6)
		local a2 = math.rad(180 * (k + 1) / 6)
		rod(m, "Arch", (F * CFrame.new(math.cos(a) * 2.1, 7 + math.sin(a) * 1.2, -D / 2)).Position, (F * CFrame.new(math.cos(a2) * 2.1, 7 + math.sin(a2) * 1.2, -D / 2)).Position, 0.3, WHITE, M.Wood)
	end
	local sign = box(m, "GardenSign", F, -1.9, 1.9, 5.6, 6.6, -D / 2 - 0.1, -D / 2 + 0.05, rgb(92, 140, 70), M.Wood)
	surfaceText(sign, Enum.NormalId.Front, "🥕 " .. Locale.T("Community gardens"), WHITE, rgb(92, 140, 70), Enum.Font.FredokaOne, 100)
	-- rosier grimpant sur l'arche
	for k = 0, 4 do
		egg(m, "Roses", F * CFrame.new(-1.8 + k * 0.9, 7.6 + math.sin(k) * 0.4, -D / 2), Vector3.new(0.9, 0.7, 0.7), k % 2 == 0 and rgb(236, 80, 120) or LEAF, M.Grass)
	end
	-- 6 carrés potagers (3 x 2 de part et d'autre de l'allée)
	local kind = 0
	for _, sz in ipairs({ -1, 1 }) do
		for i = 0, 2 do
			kind += 1
			local x = -8 + i * 8
			if not (sz > 0 and i == 2) then
				raisedBed(m, F * CFrame.new(x, 0, sz * 5.2), kind, seed * 7 + kind)
			end
		end
	end
	-- serre vitrée (coin arrière droit)
	local G = F * CFrame.new(8.6, 0, 6)
	box(m, "GreenBase", G, -3, 3, -0.2, 0.4, -2.4, 2.4, rgb(190, 184, 176), M.Brick, true)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			column(m, "GreenFrame", G, sx * 2.95, sz * 2.35, 0.4, 4.2, 0.12, WHITE, M.Metal)
		end
		local side = box(m, "GreenGlass", G, sx * 2.95 - 0.04, sx * 2.95 + 0.04, 0.4, 4.2, -2.3, 2.3, GLASS, M.Glass, true)
		side.Transparency = 0.6
		local roof = newPart(m, "GreenRoof", Vector3.new(3.4, 0.08, 4.9), G * CFrame.new(sx * 1.45, 4.95, 0) * CFrame.Angles(0, 0, sx * math.rad(-28)), GLASS, M.Glass)
		roof.Transparency = 0.55
	end
	local back = box(m, "GreenGlass", G, -2.9, 2.9, 0.4, 4.2, 2.31, 2.39, GLASS, M.Glass, true)
	back.Transparency = 0.6
	box(m, "GreenRidge", G, -0.1, 0.1, 5.7, 5.85, -2.45, 2.45, WHITE, M.Metal)
	for i = 0, 2 do
		egg(m, "Seedlings", G * CFrame.new(-1.6 + i * 1.6, 1.3, 1.2), Vector3.new(1.2, 0.7, 1.2), LEAF, M.Grass)
	end
	box(m, "PotBench", G, -2.6, 2.6, 0.4, 0.95, 0.6, 1.8, WOOD, M.Wood)
	-- cabane à outils (coin arrière gauche)
	local S = F * CFrame.new(-10.2, 0, 7) * CFrame.Angles(0, math.rad(90), 0)
	box(m, "Shed", S, -2, 2, -0.1, 4.4, -1.6, 1.6, rgb(120, 150, 110), M.WoodPlanks, true)
	for _, sz in ipairs({ -1, 1 }) do
		newPart(m, "ShedRoof", Vector3.new(4.6, 0.2, 2.1), S * CFrame.new(0, 4.9, sz * 0.9) * CFrame.Angles(sz * math.rad(-26), 0, 0), rgb(110, 70, 60), M.Slate)
	end
	box(m, "ShedDoor", S, -0.8, 0.8, 0, 3.4, -1.66, -1.6, rgb(90, 118, 84), M.Wood)
	-- outils appuyés contre la cabane : râteau, pelle
	rod(m, "RakeHandle", (S * CFrame.new(1.4, 0.1, -1.9)).Position, (S * CFrame.new(1.6, 3.6, -1.7)).Position, 0.12, rgb(170, 130, 90), M.Wood)
	box(m, "RakeHead", S, 1.0, 1.9, 0.05, 0.25, -2.0, -1.85, GRAPHITE, M.Metal)
	rod(m, "ShovelHandle", (S * CFrame.new(-1.4, 0.8, -1.9)).Position, (S * CFrame.new(-1.6, 3.8, -1.7)).Position, 0.12, rgb(170, 130, 90), M.Wood)
	box(m, "ShovelBlade", S, -1.6, -1.1, 0.05, 0.9, -2.0, -1.9, STEEL, M.Metal)
	-- composteurs, récupérateur d'eau, brouette, arrosoir
	for i = 0, 1 do
		local C = F * CFrame.new(-11 + i * 2.4, 0, -6.5)
		box(m, "Compost", C, -1, 1, 0, 1.6, -1, 1, WOOD_D, M.WoodPlanks, true)
		box(m, "CompostTop", C, -0.92, 0.92, 0, 1.45, -0.92, 0.92, SOIL, M.Ground)
	end
	column(m, "RainBarrel", F, 5.6, 8.6, 0, 2.6, 1.8, rgb(40, 90, 150), M.Plastic, true)
	column(m, "BarrelTap", F, 5.6, 7.6, 0.6, 0.8, 0.2, STEEL, M.Metal)
	local wb = F * CFrame.new(3.4, 0, -3.2) * CFrame.Angles(0, math.rad(30), 0)
	box(m, "Barrow", wb, -0.8, 0.8, 0.8, 1.5, -1.2, 1.0, rgb(46, 120, 80), M.Metal)
	newPart(m, "BarrowWheel", Vector3.new(0.3, 0.9, 0.9), wb * CFrame.new(0, 0.45, -1.4), GRAPHITE, M.Rubber, "Cyl")
	for _, sx in ipairs({ -1, 1 }) do
		rod(m, "BarrowHandle", (wb * CFrame.new(sx * 0.6, 1.2, 0.8)).Position, (wb * CFrame.new(sx * 0.7, 1.0, 2.4)).Position, 0.12, rgb(170, 130, 90), M.Wood)
	end
	egg(m, "BarrowSoil", wb * CFrame.new(0, 1.45, -0.1), Vector3.new(1.4, 0.5, 2.0), SOIL, M.Ground)
	column(m, "WateringCan", F, -3.4, 2.4, 0.1, 0.9, 0.8, rgb(60, 150, 110), M.Metal)
	rod(m, "CanSpout", (F * CFrame.new(-3.0, 0.6, 2.4)).Position, (F * CFrame.new(-2.4, 1.0, 2.4)).Position, 0.1, rgb(60, 150, 110), M.Metal)
	-- épouvantail
	local E = F * CFrame.new(0, 0, 3.4)
	column(m, "ScarePost", E, 0, 0, -0.1, 5.4, 0.2, WOOD_D, M.Wood)
	box(m, "ScareArms", E, -1.8, 1.8, 3.9, 4.1, -0.1, 0.1, WOOD_D, M.Wood)
	box(m, "ScareShirt", E, -0.8, 0.8, 2.8, 4.3, -0.35, 0.35, rgb(200, 70, 60), M.Fabric)
	newPart(m, "ScareHead", Vector3.new(0.9, 0.9, 0.9), E * CFrame.new(0, 4.85, 0), rgb(226, 204, 150), M.Fabric, "Ball")
	newPart(m, "ScareHatBrim", Vector3.new(0.08, 1.8, 1.8), E * CFrame.new(0, 5.25, 0) * UPRIGHT, rgb(210, 180, 100), M.Fabric, "Cyl")
	newPart(m, "ScareHatTop", Vector3.new(0.6, 0.9, 0.9), E * CFrame.new(0, 5.55, 0) * UPRIGHT, rgb(210, 180, 100), M.Fabric, "Cyl")
	-- 2 jardiniers
	local g1 = npc(m, "elder", seed * 5 + 1, F * CFrame.new(-4.2, 0, -2.6) * CFrame.Angles(0, math.rad(200), 0), "none")
	addActor(g1, "Idle", { Anim = "talk" }, hash(seed, 3) * 10)
	local g2 = npc(m, "worker", seed * 5 + 2, F * CFrame.new(5, 0, 2.3) * CFrame.Angles(0, math.rad(20), 0), "none")
	addActor(g2, "Idle", { Anim = "idle" }, hash(seed, 4) * 10)
end

----------------------------------------------------------------------
-- 🏓 Coin sport : ping-pong, pétanque, fitness
----------------------------------------------------------------------

local TABLE_TOP = 2.3 -- plateau d'une table de ping-pong (76 cm à l'échelle de l'avatar)

local function pingPong(m: Model, T: CFrame, playing: boolean, seed: number)
	-- pied en béton + plateau (2,74 x 1,525 m -> 8,3 x 4,6 studs) + lignes + filet
	box(m, "PPBase", T, -2.6, 2.6, -0.1, TABLE_TOP - 0.3, -0.4, 0.4, CONCRETE_D, M.Concrete, true)
	box(m, "PPTop", T, -4.15, 4.15, TABLE_TOP - 0.3, TABLE_TOP, -2.3, 2.3, rgb(40, 110, 90), M.Concrete, true)
	-- lignes blanches (dessus 0,03 au-dessus du plateau, en retrait des bords)
	box(m, "PPEdge", T, -4.1, 4.1, TABLE_TOP - 0.02, TABLE_TOP + 0.03, -2.26, -2.16, WHITE, M.SmoothPlastic)
	box(m, "PPEdge", T, -4.1, 4.1, TABLE_TOP - 0.02, TABLE_TOP + 0.03, 2.16, 2.26, WHITE, M.SmoothPlastic)
	box(m, "PPCenter", T, -4.1, 4.1, TABLE_TOP - 0.02, TABLE_TOP + 0.03, -0.04, 0.04, WHITE, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		box(m, "PPEnd", T, sx * 4.07 - 0.05, sx * 4.07 + 0.05, TABLE_TOP - 0.02, TABLE_TOP + 0.06, -2.16, 2.16, WHITE, M.SmoothPlastic)
	end
	box(m, "PPNet", T, -0.04, 0.04, TABLE_TOP, TABLE_TOP + 0.5, -2.45, 2.45, STEEL, M.DiamondPlate)
	box(m, "PPNetTop", T, -0.07, 0.07, TABLE_TOP + 0.48, TABLE_TOP + 0.56, -2.5, 2.5, WHITE, M.SmoothPlastic)
	if playing then
		local ball = newPart(m, "PPBall", Vector3.new(0.14, 0.14, 0.14), T * CFrame.new(0, TABLE_TOP + 1, 0), rgb(255, 250, 240), M.SmoothPlastic, "Ball")
		local players = {}
		for i, sx in ipairs({ -1, 1 }) do
			local p = npc(m, i == 1 and "kid" or "pedestrian", seed * 3 + i, T * CFrame.new(sx * 6.2, 0, 0) * CFrame.Angles(0, sx > 0 and math.rad(90) or math.rad(-90), 0), "none")
			players[i] = p
		end
		addActor(players[1], "PingPong", { T = T, Ball = ball, Players = players, Lead = true }, hash(seed, 7) * 5)
		addActor(players[2], "PingPong", { T = T, Players = players, Lead = false }, hash(seed, 7) * 5)
	end
end

local function buildSportsCorner(m: Model, F: CFrame, seed: number)
	local W, D = 24, 18
	-- sol : dalle claire (ping-pong), sable (pétanque), sol souple (fitness)
	box(m, "SportPad", F, -W / 2, 0, -0.5, 0.2, -D / 2, D / 2, rgb(208, 204, 196), M.Concrete, true)
	-- ping-pong : 2 tables (une partie en cours)
	pingPong(m, F * CFrame.new(-6, 0.2, -4.2), true, seed)
	pingPong(m, F * CFrame.new(-6, 0.2, 4.6), false, seed + 1)
	-- pétanque : terrain en sable stabilisé + bordure bois + boules
	local B = F * CFrame.new(6.2, 0, -4)
	box(m, "BoulePitch", B, -5.6, 5.6, -0.4, 0.12, -2.4, 2.4, rgb(222, 200, 160), M.Sand)
	for _, sz in ipairs({ -1, 1 }) do
		box(m, "BouleEdge", B, -5.8, 5.8, -0.2, 0.34, sz * 2.5 - 0.12, sz * 2.5 + 0.12, WOOD_D, M.Wood, true)
	end
	for _, sx in ipairs({ -1, 1 }) do
		box(m, "BouleEdge", B, sx * 5.7 - 0.12, sx * 5.7 + 0.12, -0.2, 0.34, -2.38, 2.38, WOOD_D, M.Wood, true)
	end
	newPart(m, "Jack", Vector3.new(0.2, 0.2, 0.2), B * CFrame.new(3.6, 0.22, 0.4), rgb(240, 200, 40), M.Wood, "Ball")
	for i = 0, 5 do
		local a = i * 1.3 + seed
		newPart(m, "Boule", Vector3.new(0.4, 0.4, 0.4), B * CFrame.new(3.2 + math.cos(a) * (0.6 + i * 0.25), 0.32, 0.4 + math.sin(a) * 0.7), STEEL, M.Metal, "Ball")
	end
	local p1 = npc(m, "elder", seed * 11 + 1, B * CFrame.new(-4, 0.12, 0.6) * CFrame.Angles(0, math.rad(-90), 0), "none")
	addActor(p1, "Idle", { Anim = "cheer" }, hash(seed, 21) * 10)
	-- fitness : sol souple + barre fixe, barres parallèles, banc à abdos
	local Fi = F * CFrame.new(6.2, 0, 4.6)
	box(m, "FitFloor", Fi, -5.6, 5.6, -0.4, 0.16, -3, 3, rgb(60, 110, 150), M.Rubber, true)
	for _, x in ipairs({ -4.6, -1.8 }) do
		column(m, "PullPost", Fi, x, 0, 0, 7.2, 0.3, rgb(40, 150, 90), M.Metal, true)
	end
	rod(m, "PullBar", (Fi * CFrame.new(-4.6, 7, 0)).Position, (Fi * CFrame.new(-1.8, 7, 0)).Position, 0.2, STEEL, M.Metal, true)
	for _, z in ipairs({ -0.9, 0.9 }) do
		for _, x in ipairs({ 0.6, 3.4 }) do
			column(m, "DipPost", Fi, x, z, 0, 3.6, 0.24, rgb(40, 150, 90), M.Metal, true)
		end
		rod(m, "DipBar", (Fi * CFrame.new(0.6, 3.6, z)).Position, (Fi * CFrame.new(3.4, 3.6, z)).Position, 0.2, STEEL, M.Metal, true)
	end
	local bench = Fi * CFrame.new(3.6, 0, -1.9) * CFrame.Angles(0, math.rad(90), 0)
	newPart(m, "SitUpBench", Vector3.new(3.2, 0.25, 1), bench * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(12)), rgb(30, 30, 34), M.Fabric, nil, true)
	for _, x in ipairs({ -1.2, 1.2 }) do
		column(m, "SitUpLeg", bench, x, 0, 0, x < 0 and 0.95 or 1.45, 0.2, STEEL, M.Metal)
	end
	local sign = box(m, "SportSign", F, -2.4, 2.4, 3.2, 4.2, -D / 2 - 0.1, -D / 2 + 0.05, rgb(40, 110, 170), M.Metal)
	surfaceText(sign, Enum.NormalId.Front, "🏓 " .. Locale.T("Sports corner"), WHITE, rgb(40, 110, 170), Enum.Font.FredokaOne, 100)
	column(m, "SignPost", F, -1.9, -D / 2, -0.1, 3.3, 0.16, GRAPHITE, M.Metal)
	column(m, "SignPost", F, 1.9, -D / 2, -0.1, 3.3, 0.16, GRAPHITE, M.Metal)
	lampPost(m, F, 0, D / 2 + 1.4, 0)
end

TownDistricts.BUILDERS = {
	SkatePark = buildSkatePark,
	CommunityGarden = buildCommunityGarden,
	SportsCorner = buildSportsCorner,
}
TownDistricts.BIG = { SkatePark = true, CommunityGarden = true, SportsCorner = true }

----------------------------------------------------------------------
-- Animation (à chaque image, près de la caméra)
----------------------------------------------------------------------

local function stepSkater(a: Actor, t: number)
	local d = a.Data
	local P: CFrame = d.P
	local pos, yaw, pitch, lift
	if d.Mode == 1 then
		-- aller-retour d'une rampe à l'autre : x(t) = A sin(ωt), la planche
		-- suit la courbe (vitesse nulle en haut : demi-tour naturel)
		-- (demi-tour à ~55° dans la courbe : le skateur ne se couche pas)
		local A = QP_CX + QP_R * math.sin(math.rad(55))
		local w = math.pi * 2 / 6.4
		local x = A * math.sin(w * t)
		local vx = A * w * math.cos(w * t)
		local h, slope = skateGround(x)
		pos = Vector3.new(x, h, 0.6)
		yaw = vx >= 0 and 0 or math.pi
		-- (la planche est le long de X ; dans la montée elle se cabre)
		pitch = slope * (vx >= 0 and 1 or -1)
		lift = 0
	else
		-- tour de la funbox (ellipse) avec un ollie à chaque passage devant
		local w = math.pi * 2 / 7.5
		local ang = w * t
		local x = math.cos(ang) * 6.2
		local z = -5.4 + math.sin(ang) * 3.4
		local vx, vz = -math.sin(ang) * 6.2, math.cos(ang) * 3.4
		pos = Vector3.new(x, 0, z)
		yaw = math.atan2(-vz, vx) -- (X local de la planche le long de la vitesse)
		local u = (ang / (math.pi * 2)) % 1
		lift = (u > 0.42 and u < 0.58) and math.sin((u - 0.42) / 0.16 * math.pi) * 1.1 or 0
		pitch = (u > 0.42 and u < 0.47) and 0.35 or 0
	end
	local boardCF = P * CFrame.new(pos + Vector3.new(0, lift, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, pitch)
	local frames = {}
	for i, part in ipairs(d.Board) do
		frames[i] = boardCF * BOARD_LOCAL[i]
	end
	workspace:BulkMoveTo(d.Board, frames, Enum.BulkMoveMode.FireCFrameChanged)
	-- le skateur : de profil sur la planche (regarde vers +Z de la planche),
	-- pieds sur le plateau, un peu fléchi
	local riderCF = boardCF * CFrame.new(0, 0.37, 0)
	NPCModels.Place(a.Model, riderCF)
	NPCModels.Animate(a.Model, "idle", t)
end

local function stepPingPong(a: Actor, t: number)
	local d = a.Data
	local T: CFrame = d.T
	-- un échange : la balle va de -X à +X en 0,9 s (rebond sur la table), et revient
	local period = 1.8
	local u = (t % period) / period
	local dir = u < 0.5 and 1 or -1
	local k = (u % 0.5) / 0.5
	local x0, x1 = -5.4 * dir, 5.4 * dir
	local x = x0 + (x1 - x0) * k
	-- rebond à 70 % du trajet (sur le demi-terrain d'en face)
	local y
	if k < 0.7 then
		local s = k / 0.7
		y = TABLE_TOP + 0.15 + 1.1 * 4 * s * (1 - s) + (1 - s) * 0.9
	else
		local s = (k - 0.7) / 0.3
		y = TABLE_TOP + 0.15 + 1.0 * 4 * s * (1 - s) * 0.9 + s * 0.9
	end
	if d.Lead and d.Ball then
		d.Ball.CFrame = T * CFrame.new(x, y, math.sin(t * 1.7) * 0.8)
	end
	-- le joueur frappe quand la balle arrive de son côté
	local mine = d.Lead and -1 or 1
	local hit = (dir == mine and k < 0.2) or (dir ~= mine and k > 0.85)
	NPCModels.Animate(a.Model, hit and "wave" or "idle", t)
end

function TownDistricts.Step(dt: number)
	if #actors == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local now = os.clock()
	for i = #actors, 1, -1 do
		local a = actors[i]
		if not a.Model.Parent then
			table.remove(actors, i)
		else
			local pivot = a.Model:GetPivot().Position
			if not eye or (pivot - eye).Magnitude < ANIM_R then
				local t = now + a.Phase
				local ok = pcall(function()
					if a.Kind == "Skater" then
						stepSkater(a, t)
					elseif a.Kind == "PingPong" then
						stepPingPong(a, t)
					else
						NPCModels.Animate(a.Model, a.Data.Anim or "idle", t)
					end
				end)
				if not ok then
					table.remove(actors, i)
				end
			end
		end
	end
	local _ = dt
end

-- (tests) nombre d'acteurs animés
function TownDistricts.Count(): number
	return #actors
end

return TownDistricts
