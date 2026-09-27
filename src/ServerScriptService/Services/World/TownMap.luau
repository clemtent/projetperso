--[[
	TownMap (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownMap

	🚶 Dopamine Town : construit UNE fois, au démarrage du serveur, le décor
	commun dans Workspace > DopamineTown (quelques centaines de Parts, rien
	par image) :
	  - grand pré pastel, place centrale pavée (anneaux roses), fontaine à
	    trois vasques (jet d'eau en particules), bancs (vrais Seat), arbres
	    ronds, lampadaires (quelques vraies lumières), point d'apparition en
	    cœur, panneau "Dopamine Town" ;
	  - une route circulaire + une allée vers chaque parcelle ;
	  - N parcelles (WorldLayout) : pelouse, allée jusqu'à la porte, petite
	    clôture, boîte aux lettres et panneau du propriétaire (nom, ❤️, 👀,
	    🔓) mis à jour par WorldService (SetPlotSign) ;
	  - murs invisibles au bord du pré (on ne tombe pas).
	Les MAISONS ne sont pas ici : chaque client les construit (HouseBuilder).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)

local TownMap = {}

TownMap.FOLDER_NAME = "DopamineTown"

local M = Enum.Material
local GRASS = Color3.fromRGB(150, 222, 150)
local PLOT_GRASS = Color3.fromRGB(170, 232, 168)
local PAVE = Color3.fromRGB(255, 232, 238)
local PAVE_PINK = Color3.fromRGB(255, 196, 218)
local PAVE_LILAC = Color3.fromRGB(226, 212, 255)
local ROAD = Color3.fromRGB(206, 196, 222)
local PATH = Color3.fromRGB(255, 240, 222)
local WHITE = Color3.fromRGB(255, 255, 255)
local WOOD = Color3.fromRGB(214, 164, 120)
local WATER = Color3.fromRGB(120, 206, 255)
local LAMP_POLE = Color3.fromRGB(120, 96, 150)
local LAMP_GLOW = Color3.fromRGB(255, 236, 190)
local CANOPIES = { Color3.fromRGB(255, 182, 214), Color3.fromRGB(140, 220, 170), Color3.fromRGB(196, 170, 250), Color3.fromRGB(255, 214, 150) }

export type PlotInfo = {
	Index: number,
	Model: Model,
	CFrame: CFrame,
	HouseCFrame: CFrame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Stats: TextLabel,
	Board: BasePart,
}

export type Town = {
	Folder: Folder,
	Plots: { PlotInfo },
	Spawn: SpawnLocation,
	PlazaCFrame: CFrame,
	Seats: Folder,
}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Disque plat (cylindre couché) de rayon r, dessus à la hauteur y
local function disc(parent: Instance, name: string, center: Vector3, radius: number, thickness: number, color: Color3, material: Enum.Material?): BasePart
	local p = part(parent, name, Vector3.new(thickness, radius * 2, radius * 2), CFrame.new(center - Vector3.new(0, thickness / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(center), color, material)
	;(p :: Part).Shape = Enum.PartType.Ball
	p.CanCollide = false
	return p
end

local function cylinderUp(parent: Instance, name: string, bottom: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

local function surfaceText(board: BasePart, face: Enum.NormalId, pixelsPerStud: number): (SurfaceGui, Frame)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0.2
	gui.MaxDistance = 400
	gui.Parent = board
	local frame = Instance.new("Frame")
	frame.Name = "Body"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 244, 250), Color3.fromRGB(255, 214, 236))
	gradient.Rotation = 90
	gradient.Parent = frame
	return gui, frame
end

local function label(parent: Instance, name: string, text: string, y: number, h: number, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(0.04, y)
	l.Size = UDim2.fromScale(0.92, h)
	l.Font = font
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Parent = parent
	return l
end

----------------------------------------------------------------------
-- Décor de la place
----------------------------------------------------------------------

local function tree(parent: Instance, base: Vector3, height: number, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Tree"
	model.Parent = parent
	cylinderUp(model, "Trunk", base, height, 1.6, WOOD, M.Wood)
	ball(model, "Canopy", base + Vector3.new(0, height + 1.5, 0), height * 0.75, color, M.SmoothPlastic)
	ball(model, "Canopy2", base + Vector3.new(1.6, height - 0.2, 0.8), height * 0.5, color:Lerp(WHITE, 0.15), M.SmoothPlastic)
end

local lightCount = 0
local function lamp(parent: Instance, base: Vector3, withLight: boolean)
	local model = Instance.new("Model")
	model.Name = "Lamp"
	model.Parent = parent
	cylinderUp(model, "Pole", base, 9, 0.5, LAMP_POLE, M.Metal)
	local head = ball(model, "Glow", base + Vector3.new(0, 9.6, 0), 1.8, LAMP_GLOW, M.Neon)
	part(model, "Cap", Vector3.new(2, 0.3, 2), CFrame.new(base + Vector3.new(0, 10.6, 0)), LAMP_POLE, M.Metal).CanCollide = false
	if withLight and lightCount < 10 then
		lightCount += 1
		local light = Instance.new("PointLight")
		light.Color = LAMP_GLOW
		light.Range = 18
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = head
	end
end

local function bench(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Bench"
	model.Parent = parent
	-- (vrai Seat : on s'assoit en marchant dessus ou avec le bouton "sauter" pour se lever)
	local seat = part(model, "Seat", Vector3.new(6, 0.5, 2), cf * CFrame.new(0, 1.7, 0), WOOD, M.Wood, "Seat")
	seat.CanCollide = true
	part(model, "Back", Vector3.new(6, 2, 0.4), cf * CFrame.new(0, 3, 0.9), WOOD, M.Wood)
	part(model, "LegL", Vector3.new(0.4, 1.5, 1.8), cf * CFrame.new(-2.6, 0.75, 0), LAMP_POLE, M.Metal)
	part(model, "LegR", Vector3.new(0.4, 1.5, 1.8), cf * CFrame.new(2.6, 0.75, 0), LAMP_POLE, M.Metal)
end

local function fountain(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "Fountain"
	model.Parent = parent
	cylinderUp(model, "Basin", center, 2.2, 22, PAVE_PINK, M.SmoothPlastic)
	cylinderUp(model, "Water", center + Vector3.new(0, 1.2, 0), 1.2, 19.6, WATER, M.Glass).Transparency = 0.25
	cylinderUp(model, "Pillar", center, 6, 2.4, WHITE, M.Marble)
	cylinderUp(model, "Bowl", center + Vector3.new(0, 6, 0), 1.2, 9, PAVE_LILAC, M.SmoothPlastic)
	cylinderUp(model, "Pillar2", center + Vector3.new(0, 7.2, 0), 3, 1.4, WHITE, M.Marble)
	cylinderUp(model, "Bowl2", center + Vector3.new(0, 10.2, 0), 0.8, 4.6, PAVE_PINK, M.SmoothPlastic)
	local heart = ball(model, "Top", center + Vector3.new(0, 12.2, 0), 2.4, Color3.fromRGB(255, 110, 170), M.Neon)
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255), Color3.fromRGB(255, 255, 255))
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.9) })
	spray.Lifetime = NumberRange.new(1.2, 1.6)
	spray.Rate = 26
	spray.Speed = NumberRange.new(10, 13)
	spray.SpreadAngle = Vector2.new(18, 18)
	spray.Acceleration = Vector3.new(0, -16, 0)
	spray.Parent = heart
end

local function sign(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "TownSign"
	model.Parent = parent
	part(model, "PostL", Vector3.new(0.8, 9, 0.8), cf * CFrame.new(-7, 4.5, 0), WOOD, M.Wood)
	part(model, "PostR", Vector3.new(0.8, 9, 0.8), cf * CFrame.new(7, 4.5, 0), WOOD, M.Wood)
	local board = part(model, "Board", Vector3.new(16, 5, 0.6), cf * CFrame.new(0, 7.5, 0), WHITE, M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local _, body = surfaceText(board, face, 40)
		label(body, "Title", "🚶 Dopamine Town", 0.1, 0.5, Color3.fromRGB(236, 72, 140), Enum.Font.FredokaOne)
		label(body, "Subtitle", "💖 hang out • visit • like 💖", 0.62, 0.28, Color3.fromRGB(120, 90, 160), Enum.Font.GothamBold)
	end
end

----------------------------------------------------------------------
-- Parcelles
----------------------------------------------------------------------

local function buildPlot(parent: Instance, index: number, count: number): PlotInfo
	local plotCF = WorldLayout.PlotCFrame(index, count)
	local houseCF = WorldLayout.HouseCFrame(plotCF)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("OwnerId", 0)
	model.Parent = parent
	local W, D = WorldLayout.PLOT_W, WorldLayout.PLOT_D
	local base = part(model, "Lawn", Vector3.new(W, 0.4, D), plotCF * CFrame.new(0, 0.2, 0), PLOT_GRASS, M.Grass)
	base:SetAttribute("PlotIndex", index)
	-- Allée : de la route jusqu'à la porte (x de la porte : taille inconnue ici,
	-- l'allée est large et centrée sur la cage d'un studio ; le client pose le
	-- perron devant la vraie porte)
	local front = WorldLayout.HouseFrontOffset()
	local pathLength = D / 2 - front + 2
	part(model, "Path", Vector3.new(10, 0.5, pathLength), plotCF * CFrame.new(0, 0.26, -(front + pathLength / 2) + 1), PATH, M.Pebble)
	-- Petite clôture (côtés + fond), basse et sans collision gênante
	local fence = Color3.fromRGB(255, 250, 244)
	part(model, "FenceL", Vector3.new(0.5, 2.2, D), plotCF * CFrame.new(-W / 2, 1.1, 0), fence, M.Wood)
	part(model, "FenceR", Vector3.new(0.5, 2.2, D), plotCF * CFrame.new(W / 2, 1.1, 0), fence, M.Wood)
	part(model, "FenceB", Vector3.new(W, 2.2, 0.5), plotCF * CFrame.new(0, 1.1, D / 2), fence, M.Wood)
	-- Panneau du propriétaire (près de la route, à droite de l'allée)
	local signCF = plotCF * CFrame.new(10, 0, -D / 2 + 3) * CFrame.Angles(0, math.rad(180), 0)
	part(model, "SignPost", Vector3.new(0.6, 6, 0.6), signCF * CFrame.new(0, 3, 0), WOOD, M.Wood)
	local board = part(model, "SignBoard", Vector3.new(11, 5.2, 0.5), signCF * CFrame.new(0, 7.2, 0), WHITE, M.SmoothPlastic)
	local _, body = surfaceText(board, Enum.NormalId.Back, 36)
	local title = label(body, "Title", "✨ Free plot", 0.06, 0.34, Color3.fromRGB(236, 72, 140), Enum.Font.FredokaOne)
	local subtitle = label(body, "Subtitle", "", 0.42, 0.22, Color3.fromRGB(120, 90, 160), Enum.Font.GothamBold)
	local stats = label(body, "Stats", "", 0.68, 0.26, Color3.fromRGB(92, 58, 96), Enum.Font.GothamBold)
	-- Boîte aux lettres
	local mailCF = plotCF * CFrame.new(-8, 0, -D / 2 + 3)
	part(model, "MailPost", Vector3.new(0.4, 3.4, 0.4), mailCF * CFrame.new(0, 1.7, 0), WOOD, M.Wood)
	part(model, "MailBox", Vector3.new(1.4, 1.2, 2), mailCF * CFrame.new(0, 3.8, 0), Color3.fromRGB(255, 140, 188), M.SmoothPlastic)
	part(model, "MailFlag", Vector3.new(0.12, 0.8, 0.4), mailCF * CFrame.new(0.75, 4.2, 0.4), Color3.fromRGB(255, 80, 120), M.SmoothPlastic)
	model.PrimaryPart = base
	return {
		Index = index,
		Model = model,
		CFrame = plotCF,
		HouseCFrame = houseCF,
		Title = title,
		Subtitle = subtitle,
		Stats = stats,
		Board = board,
	}
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TownMap.Build(plotCount: number): Town
	local old = workspace:FindFirstChild(TownMap.FOLDER_NAME)
	if old then
		old:Destroy()
	end
	lightCount = 0
	local origin = WorldLayout.Origin()
	local folder = Instance.new("Folder")
	folder.Name = TownMap.FOLDER_NAME

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = folder
	local seats = Instance.new("Folder")
	seats.Name = "Seats"
	seats.Parent = folder

	local plotRadius = WorldLayout.PlotRadius(plotCount)
	local outer = plotRadius + WorldLayout.PLOT_D / 2 + 50
	-- Pré (disque) + anneau plus foncé sous les parcelles
	disc(decor, "Meadow", origin, outer, 4, GRASS, M.Grass)
	-- Route circulaire (segments)
	local roadR = WorldLayout.RingRoadRadius(plotCount)
	local segments = 40
	local segLen = 2 * math.pi * roadR / segments + 1.2
	for i = 1, segments do
		local a = (i - 0.5) / segments * math.pi * 2
		local p = origin + Vector3.new(math.sin(a) * roadR, 0.15, math.cos(a) * roadR)
		-- (lookAt vers le centre : l'axe X de la pièce suit la route)
		part(decor, "Road", Vector3.new(segLen, 0.3, 12), CFrame.lookAt(p, origin + Vector3.new(0, 0.15, 0)), ROAD, M.SmoothPlastic)
	end
	-- Place : pavés, anneaux, fontaine
	disc(decor, "Plaza", origin + Vector3.new(0, 0.4, 0), WorldLayout.PLAZA_R, 0.5, PAVE, M.Slate)
	disc(decor, "PlazaRing", origin + Vector3.new(0, 0.45, 0), WorldLayout.PLAZA_R * 0.72, 0.5, PAVE_PINK, M.Slate)
	disc(decor, "PlazaInner", origin + Vector3.new(0, 0.5, 0), WorldLayout.PLAZA_R * 0.55, 0.5, PAVE_LILAC, M.Slate)
	fountain(decor, origin + Vector3.new(0, 0.5, 0))
	-- Massifs de fleurs autour de l'anneau rose (petites boules pastel)
	local FLOWERS = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 214, 110), Color3.fromRGB(190, 150, 255), Color3.fromRGB(255, 255, 255) }
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * math.pi * 2 + math.pi / 8
		local r = WorldLayout.PLAZA_R * 0.64
		local center = origin + Vector3.new(math.sin(a) * r, 0.5, math.cos(a) * r)
		local bed = disc(decor, "FlowerBed", center + Vector3.new(0, 0.6, 0), 3.2, 0.6, Color3.fromRGB(150, 110, 90), M.Ground)
		bed.CanCollide = false
		ball(decor, "Leaves", center + Vector3.new(0, 1.1, 0), 4.2, GRASS, M.Grass)
		for k = 1, 3 do
			local b = k / 3 * math.pi * 2 + i
			ball(decor, "Flower", center + Vector3.new(math.cos(b) * 1.3, 2.6, math.sin(b) * 1.3), 1.3, FLOWERS[(i + k) % #FLOWERS + 1], M.SmoothPlastic)
		end
	end
	-- Bancs autour de la fontaine (face à elle)
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * math.pi * 2
		local p = origin + Vector3.new(math.sin(a) * 22, 0.5, math.cos(a) * 22)
		bench(decor, CFrame.lookAt(p, origin + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(180), 0))
	end
	-- Arbres et lampadaires au bord de la place
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2 + 0.2
		local r = WorldLayout.PLAZA_R + 6
		tree(decor, origin + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r), 7 + (i % 3), CANOPIES[i % #CANOPIES + 1])
	end
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * math.pi * 2
		local r = WorldLayout.PLAZA_R - 3
		lamp(decor, origin + Vector3.new(math.sin(a) * r, 0.5, math.cos(a) * r), i % 2 == 0)
	end
	-- Panneau d'entrée (côté parcelle 1)
	sign(decor, CFrame.lookAt(origin + Vector3.new(0, 0.5, WorldLayout.PLAZA_R * 0.62), origin + Vector3.new(0, 0.5, 0)))

	-- Point d'apparition (cœur rose) : RespawnLocation des joueurs de la ville
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(origin + Vector3.new(0, 0.7, WorldLayout.PLAZA_R * 0.4))
	spawn.Color = Color3.fromRGB(255, 150, 196)
	spawn.Material = M.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Parent = decor

	-- Parcelles + allées depuis la place + arbres entre les parcelles
	local plots: { PlotInfo } = {}
	for index = 1, plotCount do
		local info = buildPlot(plotsFolder, index, plotCount)
		plots[index] = info
		local x, z, angle = WorldLayout.PlotPlace(index, plotCount)
		local dir = Vector3.new(x, 0, z).Unit
		local from, to = WorldLayout.PLAZA_R - 2, roadR - 5
		local mid = origin + dir * ((from + to) / 2) + Vector3.new(0, 0.2, 0)
		part(decor, "Walk", Vector3.new(8, 0.3, to - from), CFrame.lookAt(mid, mid + dir), PATH, M.Pebble)
		-- lampadaire au bout de l'allée, arbres entre deux parcelles
		lamp(decor, origin + dir * (roadR - 9) + Vector3.new(0, 0, 0) + Vector3.new(dir.Z, 0, -dir.X) * 6, index % 3 == 0)
		local between = angle + math.pi / plotCount
		local treeR = roadR + 8
		tree(decor, origin + Vector3.new(math.sin(between) * treeR, 0, math.cos(between) * treeR), 8, CANOPIES[index % #CANOPIES + 1])
		local midR = (from + to) / 2
		tree(decor, origin + Vector3.new(math.sin(between) * midR, 0, math.cos(between) * midR), 6 + index % 3, CANOPIES[(index + 1) % #CANOPIES + 1])
		-- petit bosquet dans le pré (loin des allées)
		for k = 1, 3 do
			local a = angle + math.pi / plotCount * (0.45 + 0.35 * ((index + k) % 3) / 2) * (k % 2 == 0 and -1 or 1)
			local r = from + (to - from) * (0.2 + 0.25 * k)
			tree(decor, origin + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r), 5 + (index + k) % 4, CANOPIES[(index + k) % #CANOPIES + 1])
		end
	end

	-- Murs invisibles au bord du pré
	local walls = 28
	for i = 1, walls do
		local a = (i - 0.5) / walls * math.pi * 2
		local p = origin + Vector3.new(math.sin(a) * (outer - 2), 20, math.cos(a) * (outer - 2))
		local wall = part(decor, "Edge", Vector3.new(2 * math.pi * outer / walls + 4, 44, 2), CFrame.lookAt(p, origin + Vector3.new(0, 20, 0)), WHITE, M.SmoothPlastic)
		wall.Transparency = 1
		wall.CastShadow = false
	end

	-- (les clients recalculent les parcelles avec WorldLayout : même nombre)
	folder:SetAttribute("PlotCount", plotCount)
	folder.Parent = workspace
	return {
		Folder = folder,
		Plots = plots,
		Spawn = spawn,
		PlazaCFrame = CFrame.new(spawn.Position + Vector3.new(0, 3, 0)),
		Seats = seats,
	}
end

-- Panneau d'une parcelle (textes déjà dans la langue... du propriétaire : noms, chiffres)
function TownMap.SetPlotSign(plot: PlotInfo, title: string, subtitle: string, stats: string)
	plot.Title.Text = title
	plot.Subtitle.Text = subtitle
	plot.Stats.Text = stats
end

return TownMap
