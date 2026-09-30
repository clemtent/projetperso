--[[
	RaceProps (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > RaceProps

	🏁 Décor 3D des courses de rue (v10, RACE10), construit CÔTÉ CLIENT et
	en flux par RaceClient (rien sur le serveur) :
	  - QG DES COURSES (zone "RaceMeet" de LAYOUT10) : dalle d'asphalte avec
	    marquages, stand des stands (3 box à rideaux levés, auvent rayé,
	    enseigne "STREET RACES"), comptoir d'inscription (invite E), grand
	    TABLEAU DES RECORDS (SurfaceGui), feux de départ décoratifs, podium
	    1-2-3, piles de pneus, cônes, drapeaux à damier ;
	  - PORTIQUE DE DÉPART (à la ligne de chaque parcours) : 2 piliers, poutre
	    en treillis, banderole au nom du parcours, 5 blocs de FEUX (rouges
	    puis verts : SetLights), ligne de départ à damier et cases de grille
	    peintes (SurfaceGui sur pièces invisibles : aucun z-fight) ;
	  - ARCHE D'ARRIVÉE (sprint) avec banderole à damier ;
	  - ARCHES DE PORTE gonflables (la prochaine brille, SetGateState).
	Aucune vraie lumière (Neon doux), aucun son. Tout est ancré, sans
	collision, sans requête, sans contact (sauf rien).

	API :
	  RaceProps.BuildHQ(cf: CFrame, w: number, d: number) -> (Model, parts : { Prompt: BasePart, Board: BasePart })
	  RaceProps.BuildGantry(cf: CFrame, width: number, title: string, finish: boolean?) -> (Model, { Lights: { { Red, Green } } })
	  RaceProps.SetLights(lights, stage)   stage : 0 éteint, 1..5 rouges allumés, 6 = verts (GO)
	  RaceProps.BuildArch(cf: CFrame, width: number, index: number) -> Model
	  RaceProps.SetGateState(model, state)  "next" | "later" | "done"
	  RaceProps.GridMarks(parent, cfs: { CFrame }) (cases peintes)
]]

local RaceProps = {}

local M = Enum.Material
local rgb = Color3.fromRGB

local INK = rgb(34, 30, 40)
local ASPHALT = rgb(58, 58, 64)
local CONCRETE = rgb(196, 192, 186)
local WHITE = rgb(246, 244, 240)
local RED = rgb(222, 48, 62)
local PINK = rgb(255, 110, 170)
local STEEL = rgb(150, 156, 166)
local DARK = rgb(44, 44, 52)
local YELLOW = rgb(255, 204, 60)
local CYAN = rgb(80, 220, 240)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		if shape == "Cyl" then
			q.Shape = Enum.PartType.Cylinder
		elseif shape == "Ball" then
			q.Shape = Enum.PartType.Ball
		end
		p = q
	end
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = size.X * size.Y * size.Z > 30
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
RaceProps.Part = part

-- Pièce invisible qui porte une SurfaceGui (marquages au sol, textes)
local function canvas(parent: Instance, name: string, size: Vector3, cf: CFrame, face: Enum.NormalId, pps: number): (BasePart, SurfaceGui)
	local p = part(parent, name, size, cf, WHITE)
	p.Transparency = 1
	p.CastShadow = false
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Gui"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps
	sg.LightInfluence = 1
	sg.MaxDistance = 400
	sg.Parent = p
	return p, sg
end

local function frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = WHITE
	for k, v in pairs(props) do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

-- Damier (cases n x m) dans une Frame
local function checker(parent: Instance, cols: number, rows: number, a: Color3, b: Color3, z: number?)
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			frame(parent, {
				Name = "Sq",
				BackgroundColor3 = if (i + j) % 2 == 0 then a else b,
				Size = UDim2.fromScale(1 / cols, 1 / rows),
				Position = UDim2.fromScale(i / cols, j / rows),
				ZIndex = z or 1,
			})
		end
	end
end
RaceProps.Checker = checker

-- Drapeau à damier sur son mât
local function flag(parent: Instance, base: CFrame, height: number)
	part(parent, "FlagPole", Vector3.new(height, 0.3, 0.3), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), STEEL, M.Metal, "Cyl")
	part(parent, "FlagKnob", Vector3.new(0.5, 0.5, 0.5), base * CFrame.new(0, height + 0.2, 0), YELLOW, M.Metal, "Ball")
	local cloth, sg = canvas(parent, "Flag", Vector3.new(3.6, 2.4, 0.06), base * CFrame.new(1.95, height - 1.4, 0) * CFrame.Angles(0, 0, math.rad(-3)), Enum.NormalId.Front, 20)
	cloth.Transparency = 0
	cloth.Color = WHITE
	cloth.Material = M.Fabric
	checker(sg, 6, 4, INK, WHITE)
	local back = sg:Clone()
	back.Face = Enum.NormalId.Back
	back.Parent = cloth
end

local function tyreStack(parent: Instance, base: CFrame, count: number, color: Color3?)
	for k = 0, count - 1 do
		local cf = base * CFrame.new(0, 0.55 + k * 1.02, 0) * CFrame.Angles(0, 0, math.rad(90))
		part(parent, "Tyre", Vector3.new(1, 2.6, 2.6), cf, DARK, M.Rubber, "Cyl")
		if k % 2 == 1 then
			part(parent, "TyreBand", Vector3.new(0.5, 2.62, 2.62), cf, color or RED, M.SmoothPlastic, "Cyl")
		end
	end
end

local function cone(parent: Instance, base: CFrame)
	part(parent, "ConeBase", Vector3.new(1.3, 0.16, 1.3), base * CFrame.new(0, 0.08, 0), rgb(255, 120, 40), M.SmoothPlastic)
	part(parent, "Cone", Vector3.new(1.3, 0.8, 0.8), base * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 120, 40), M.SmoothPlastic, "Cyl")
	part(parent, "ConeTop", Vector3.new(0.9, 0.5, 0.5), base * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), WHITE, M.SmoothPlastic, "Cyl")
	part(parent, "ConeTip", Vector3.new(0.6, 0.3, 0.3), base * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 120, 40), M.SmoothPlastic, "Cyl")
end

-- Bloc de feux de départ (boîtier + 2 feux rouges au-dessus, 2 verts en dessous)
local function lightPod(parent: Instance, cf: CFrame): { any }
	part(parent, "PodHousing", Vector3.new(1.5, 3.2, 0.9), cf, INK, M.SmoothPlastic)
	part(parent, "PodVisor", Vector3.new(1.6, 0.12, 0.5), cf * CFrame.new(0, 1.62, -0.55), INK, M.SmoothPlastic)
	local reds, greens = {}, {}
	for k, y in ipairs({ 0.95, 0.2, -0.55, -1.3 }) do
		local lamp = part(parent, if k <= 2 then "RedLamp" else "GreenLamp", Vector3.new(0.7, 0.7, 0.3), cf * CFrame.new(0, y, -0.46) * CFrame.Angles(0, math.rad(90), 0), rgb(70, 30, 34), M.SmoothPlastic, "Cyl")
		lamp.Size = Vector3.new(0.12, 0.7, 0.7)
		lamp.CFrame = cf * CFrame.new(0, y, -0.47) * CFrame.Angles(0, math.rad(90), 0)
		if k <= 2 then
			table.insert(reds, lamp)
		else
			lamp.Color = rgb(30, 60, 40)
			table.insert(greens, lamp)
		end
	end
	return { Red = reds, Green = greens }
end

----------------------------------------------------------------------
-- QG des courses
----------------------------------------------------------------------

-- cf : centre de la zone au sol (dessus du trottoir), -Z local = vers la route
function RaceProps.BuildHQ(cf: CFrame, w: number, d: number): (Model, { [string]: any })
	local model = Instance.new("Model")
	model.Name = "RaceHQ"
	local W, D = math.max(40, w - 2), math.max(30, d - 2)
	-- dalle (dessus à +0,3) avec bordure
	part(model, "Pad", Vector3.new(W, 0.8, D), cf * CFrame.new(0, -0.1, 0), ASPHALT, M.Asphalt).CastShadow = false
	part(model, "CurbFront", Vector3.new(W, 0.5, 0.6), cf * CFrame.new(0, 0.05, -D / 2 + 0.3), CONCRETE, M.Concrete)
	-- marquages : places de stationnement + damier au sol (SurfaceGui sur pièces invisibles)
	local _, marks = canvas(model, "Marks", Vector3.new(W - 2, 0.05, D - 2), cf * CFrame.new(0, 0.33, 0), Enum.NormalId.Top, 6)
	for k = 0, 5 do
		frame(marks, { Name = "Bay", BackgroundColor3 = WHITE, BackgroundTransparency = 0.15, Size = UDim2.new(0, 3, 0.36, 0), Position = UDim2.new(0.5 + k * 0.075, 0, 0.06, 0) })
	end
	local strip = frame(marks, { Name = "Checker", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -18) })
	checker(strip, 60, 2, INK, WHITE)
	text(marks, { Name = "Paint", Text = "🏁 RACE HQ", TextColor3 = rgb(255, 214, 90), TextTransparency = 0.1, Size = UDim2.new(0.34, 0, 0.16, 0), Position = UDim2.new(0.06, 0, 0.1, 0), Rotation = 0 })

	-- STAND (au fond, à gauche) : 3 box, auvent rayé, enseigne
	local bx0, bx1 = -W / 2 + 2, W * 0.1
	local bw = bx1 - bx0
	local bz0 = D / 2 - 13
	local bh = 9
	local center = (bx0 + bx1) / 2
	part(model, "BackWall", Vector3.new(bw, bh, 0.8), cf * CFrame.new(center, bh / 2 + 0.3, D / 2 - 0.9), WHITE, M.Concrete)
	part(model, "SideL", Vector3.new(0.8, bh, 12), cf * CFrame.new(bx0 + 0.4, bh / 2 + 0.3, bz0 + 6), WHITE, M.Concrete)
	part(model, "SideR", Vector3.new(0.8, bh, 12), cf * CFrame.new(bx1 - 0.4, bh / 2 + 0.3, bz0 + 6), WHITE, M.Concrete)
	part(model, "Roof", Vector3.new(bw + 1.6, 0.8, 14.6), cf * CFrame.new(center, bh + 0.7, bz0 + 5.5), rgb(70, 72, 84), M.Metal)
	part(model, "Floor", Vector3.new(bw - 1.6, 0.2, 11.4), cf * CFrame.new(center, 0.4, bz0 + 6.2), rgb(150, 150, 156), M.Concrete).CastShadow = false
	-- 3 box : piliers + rideaux levés + intérieur (établis, pneus)
	for k = 0, 3 do
		local x = bx0 + 0.4 + k * (bw - 0.8) / 3
		part(model, "Pillar", Vector3.new(1, bh, 1), cf * CFrame.new(math.clamp(x, bx0 + 0.9, bx1 - 0.9), bh / 2 + 0.3, bz0 + 0.5), RED, M.SmoothPlastic)
	end
	for k = 0, 2 do
		local x = bx0 + 0.4 + (k + 0.5) * (bw - 0.8) / 3
		local doorW = (bw - 0.8) / 3 - 1.2
		part(model, "Shutter", Vector3.new(doorW, 1.4, 0.5), cf * CFrame.new(x, bh - 0.4, bz0 + 0.6), STEEL, M.CorrugatedMetal)
		part(model, "Bench", Vector3.new(doorW * 0.7, 2.4, 1.6), cf * CFrame.new(x, 1.5, D / 2 - 2.4), rgb(90, 96, 110), M.Metal)
		part(model, "BenchTop", Vector3.new(doorW * 0.72, 0.2, 1.7), cf * CFrame.new(x, 2.8, D / 2 - 2.4), rgb(176, 120, 70), M.Wood)
		part(model, "ToolBoard", Vector3.new(doorW * 0.7, 3, 0.2), cf * CFrame.new(x, 5.2, D / 2 - 1.4), rgb(64, 64, 76), M.SmoothPlastic)
		tyreStack(model, cf * CFrame.new(x + doorW * 0.36, 0.3, D / 2 - 5), 3, if k == 1 then YELLOW else RED)
	end
	-- auvent rayé
	for k = 0, 9 do
		local sx = bx0 + (k + 0.5) * bw / 10
		part(model, "Awning", Vector3.new(bw / 10, 0.2, 3.2), cf * CFrame.new(sx, bh - 0.9, bz0 - 1.3) * CFrame.Angles(math.rad(-16), 0, 0), if k % 2 == 0 then RED else WHITE, M.Fabric)
	end
	-- enseigne sur le toit
	local sign, sgs = canvas(model, "Sign", Vector3.new(bw * 0.8, 3.2, 0.4), cf * CFrame.new(center, bh + 2.9, bz0 + 0.4), Enum.NormalId.Front, 24)
	sign.Transparency = 0
	sign.Color = INK
	local signBg = frame(sgs, { Name = "Bg", BackgroundColor3 = INK, Size = UDim2.fromScale(1, 1) })
	local band = frame(signBg, { Name = "Band", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.16, 0), Position = UDim2.fromScale(0, 0.84) })
	checker(band, 40, 2, INK, WHITE, 2)
	text(signBg, { Name = "Title", Text = "🏁 STREET RACES", TextColor3 = rgb(255, 214, 90), Size = UDim2.fromScale(0.92, 0.7), Position = UDim2.fromScale(0.04, 0.06), ZIndex = 3 })
	part(model, "SignPostL", Vector3.new(0.4, 1.6, 0.4), cf * CFrame.new(center - bw * 0.3, bh + 1.1, bz0 + 0.6), STEEL, M.Metal)
	part(model, "SignPostR", Vector3.new(0.4, 1.6, 0.4), cf * CFrame.new(center + bw * 0.3, bh + 1.1, bz0 + 0.6), STEEL, M.Metal)

	-- COMPTOIR d'inscription (devant le stand) : invite E
	local counterCf = cf * CFrame.new(center, 0, bz0 - 5)
	part(model, "Counter", Vector3.new(7, 3.4, 1.8), counterCf * CFrame.new(0, 2, 0), WHITE, M.SmoothPlastic)
	part(model, "CounterTop", Vector3.new(7.4, 0.25, 2.2), counterCf * CFrame.new(0, 3.82, 0), rgb(176, 120, 70), M.Wood)
	local _, face = canvas(model, "CounterFace", Vector3.new(6.6, 2.6, 0.05), counterCf * CFrame.new(0, 2.1, -0.93), Enum.NormalId.Front, 30)
	local fbg = frame(face, { Name = "Bg", BackgroundColor3 = RED, Size = UDim2.fromScale(1, 1) })
	local fb = frame(fbg, { Name = "Band", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.78) })
	checker(fb, 22, 2, INK, WHITE, 2)
	text(fbg, { Name = "T", Text = "SIGN UP · E", Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.12), ZIndex = 3 })
	-- écran d'inscription sur le comptoir
	part(model, "ScreenStand", Vector3.new(0.3, 1.2, 0.3), counterCf * CFrame.new(1.8, 4.5, 0.3), DARK, M.Metal)
	local screen, ssg = canvas(model, "Screen", Vector3.new(2.6, 1.7, 0.2), counterCf * CFrame.new(1.8, 5.8, 0.3) * CFrame.Angles(math.rad(-10), 0, 0), Enum.NormalId.Front, 60)
	screen.Transparency = 0
	screen.Color = DARK
	local sbg = frame(ssg, { Name = "Bg", BackgroundColor3 = rgb(20, 24, 40), Size = UDim2.fromScale(1, 1) })
	text(sbg, { Name = "T", Text = "🏁 3 · 2 · 1 · GO", TextColor3 = CYAN, Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.25) })
	local prompt = part(model, "PromptAnchor", Vector3.new(1, 1, 1), counterCf * CFrame.new(0, 3.5, -1.4), WHITE)
	prompt.Transparency = 1

	-- TABLEAU DES RECORDS (à droite) sur 2 poteaux, face à la route
	local boardCf = cf * CFrame.new(W * 0.3, 0, D / 2 - 6)
	local bW, bH = math.min(20, W * 0.34), 11
	part(model, "BoardPostL", Vector3.new(0.9, 7, 0.9), boardCf * CFrame.new(-bW / 2 + 1.5, 3.8, 0.5), STEEL, M.Metal)
	part(model, "BoardPostR", Vector3.new(0.9, 7, 0.9), boardCf * CFrame.new(bW / 2 - 1.5, 3.8, 0.5), STEEL, M.Metal)
	part(model, "BoardFrame", Vector3.new(bW + 0.8, bH + 0.8, 0.7), boardCf * CFrame.new(0, 6.8 + bH / 2, 0.55), INK, M.SmoothPlastic)
	local boardPart, boardGui = canvas(model, "Board", Vector3.new(bW, bH, 0.3), boardCf * CFrame.new(0, 6.8 + bH / 2, 0.1), Enum.NormalId.Front, 32)
	boardPart.Transparency = 0
	boardPart.Color = rgb(20, 22, 34)
	boardGui.LightInfluence = 0.3
	boardGui.MaxDistance = 260

	-- feux de départ décoratifs (arbre) près de la route
	local treeCf = cf * CFrame.new(W / 2 - 3, 0, -D / 2 + 3)
	part(model, "TreePole", Vector3.new(0.6, 7.5, 0.6), treeCf * CFrame.new(0, 3.9, 0), STEEL, M.Metal)
	local deco = {}
	for k = 0, 2 do
		table.insert(deco, lightPod(model, treeCf * CFrame.new(0, 6.4 - k * 0.2, 0) * CFrame.new((k - 1) * 1.6, 1.4, -0.5)))
	end
	-- podium 1-2-3
	local podCf = cf * CFrame.new(-W / 2 + 7, 0, -D / 2 + 7)
	for _, spec in ipairs({ { 0, 2.2, "1", YELLOW }, { -3.2, 1.5, "2", rgb(200, 206, 216) }, { 3.2, 1, "3", rgb(214, 150, 90) } }) do
		local step = part(model, "PodiumStep", Vector3.new(3.1, spec[2], 3), podCf * CFrame.new(spec[1], 0.3 + spec[2] / 2, 0), WHITE, M.SmoothPlastic)
		local _ = step
		local _, ng = canvas(model, "PodiumNum", Vector3.new(2.4, spec[2] * 0.8, 0.05), podCf * CFrame.new(spec[1], 0.3 + spec[2] / 2, -1.53), Enum.NormalId.Front, 40)
		text(ng, { Name = "N", Text = spec[3], TextColor3 = spec[4], Size = UDim2.fromScale(1, 1) })
	end
	-- pneus, cônes, drapeaux
	tyreStack(model, cf * CFrame.new(-W / 2 + 1.8, 0.3, -D / 2 + 1.8), 4)
	tyreStack(model, cf * CFrame.new(W / 2 - 1.8, 0.3, D / 2 - 1.8), 4, YELLOW)
	for k = 0, 4 do
		cone(model, cf * CFrame.new(-W * 0.2 + k * 4.2, 0.3, -D / 2 + 1.6))
	end
	flag(model, cf * CFrame.new(-W / 2 + 1, 0.3, -D / 2 + 4), 7)
	flag(model, cf * CFrame.new(W / 2 - 7, 0.3, -D / 2 + 1), 7)
	return model, { Prompt = prompt, Board = boardPart, BoardGui = boardGui, Screen = sbg, Deco = deco }
end

----------------------------------------------------------------------
-- Portique de départ / arche d'arrivée
----------------------------------------------------------------------

-- cf : centre de la ligne au sol (dessus de la chaussée), -Z = sens de la course
function RaceProps.BuildGantry(cf: CFrame, width: number, title: string, finish: boolean?): (Model, { [string]: any })
	local model = Instance.new("Model")
	model.Name = if finish then "RaceFinish" else "RaceGantry"
	local half = width / 2 + 1.6
	local H = 12.5
	for _, side in ipairs({ -1, 1 }) do
		local x = side * half
		part(model, "PillarBase", Vector3.new(2.6, 0.8, 2.6), cf * CFrame.new(x, 0.4, 0), CONCRETE, M.Concrete)
		part(model, "Pillar", Vector3.new(1.4, H, 1.4), cf * CFrame.new(x, H / 2 + 0.5, 0), if finish then WHITE else RED, M.SmoothPlastic)
		part(model, "PillarStripe", Vector3.new(1.46, 1.2, 1.46), cf * CFrame.new(x, 2.4, 0), YELLOW, M.SmoothPlastic)
		part(model, "PillarStripe", Vector3.new(1.46, 1.2, 1.46), cf * CFrame.new(x, 4.8, 0), YELLOW, M.SmoothPlastic)
	end
	-- poutre en treillis (2 membrures + diagonales)
	local span = half * 2 + 1.4
	part(model, "BeamTop", Vector3.new(span, 0.5, 1.2), cf * CFrame.new(0, H + 0.2, 0), STEEL, M.Metal)
	part(model, "BeamLow", Vector3.new(span, 0.5, 1.2), cf * CFrame.new(0, H - 1.9, 0), STEEL, M.Metal)
	local n = math.max(4, math.floor(span / 3))
	for k = 0, n - 1 do
		local x0 = -span / 2 + (k + 0.5) * span / n
		local ang = if k % 2 == 0 then math.rad(40) else math.rad(-40)
		part(model, "Diag", Vector3.new(0.25, 2.6, 0.25), cf * CFrame.new(x0, H - 0.85, 0) * CFrame.Angles(0, 0, ang), STEEL, M.Metal)
	end
	-- banderole (les deux faces)
	local bannerW = math.min(span - 4, 26)
	local banner, bsg = canvas(model, "Banner", Vector3.new(bannerW, 2.6, 0.2), cf * CFrame.new(0, H - 3.8, 0), Enum.NormalId.Front, 28)
	banner.Transparency = 0
	banner.Color = INK
	local bg = frame(bsg, { Name = "Bg", BackgroundColor3 = if finish then WHITE else INK, Size = UDim2.fromScale(1, 1) })
	if finish then
		checker(bg, 36, 4, INK, WHITE)
	else
		local l = frame(bg, { Name = "L", BackgroundTransparency = 1, Size = UDim2.new(0.12, 0, 1, 0) })
		checker(l, 3, 4, INK, WHITE, 2)
		local r = frame(bg, { Name = "R", BackgroundTransparency = 1, Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.fromScale(0.88, 0) })
		checker(r, 3, 4, INK, WHITE, 2)
		text(bg, { Name = "Title", Text = title, TextColor3 = rgb(255, 214, 90), Size = UDim2.fromScale(0.72, 0.8), Position = UDim2.fromScale(0.14, 0.1), ZIndex = 3 })
	end
	local back = bsg:Clone()
	back.Face = Enum.NormalId.Back
	back.Parent = banner
	for _, side in ipairs({ -1, 1 }) do
		part(model, "BannerRope", Vector3.new(0.12, 1.6, 0.12), cf * CFrame.new(side * (bannerW / 2 - 0.6), H - 1.9, 0), INK, M.Fabric)
	end
	-- feux de départ : 5 blocs sous la poutre (face à la grille : +Z)
	local lights = {}
	if not finish then
		for k = 1, 5 do
			local x = (k - 3) * 2.2
			part(model, "PodHanger", Vector3.new(0.2, 0.9, 0.2), cf * CFrame.new(x, H - 2.4, 0.9), INK, M.Metal)
			table.insert(lights, lightPod(model, cf * CFrame.new(x, H - 4.4, 1.2) * CFrame.Angles(0, math.pi, 0)))
		end
	end
	-- ligne au sol : damier (pièce invisible + SurfaceGui, 0,04 au-dessus de la chaussée)
	local _, line = canvas(model, "Line", Vector3.new(width, 0.05, 2.4), cf * CFrame.new(0, 0.04, 0), Enum.NormalId.Top, 10)
	checker(line, math.max(8, math.floor(width / 1.2)), 2, INK, WHITE)
	return model, { Lights = lights }
end

-- stage : 0 éteint, 1..5 = blocs rouges allumés, 6 = tous verts (GO)
function RaceProps.SetLights(lights: { any }, stage: number)
	for k, pod in ipairs(lights) do
		local red = stage >= 1 and stage <= 5 and k <= stage
		local green = stage >= 6
		for _, lamp in ipairs(pod.Red) do
			lamp.Color = if red then rgb(255, 50, 50) else rgb(70, 30, 34)
			lamp.Material = if red then M.Neon else M.SmoothPlastic
		end
		for _, lamp in ipairs(pod.Green) do
			lamp.Color = if green then rgb(80, 255, 120) else rgb(30, 60, 40)
			lamp.Material = if green then M.Neon else M.SmoothPlastic
		end
	end
end

-- Cases de la grille peintes au sol (une pièce invisible + SurfaceGui par case)
function RaceProps.GridMarks(parent: Instance, cfs: { CFrame })
	for k, cf in ipairs(cfs) do
		local _, sg = canvas(parent, "GridBox", Vector3.new(6.4, 0.05, 11), cf * CFrame.new(0, 0.04, 0), Enum.NormalId.Top, 8)
		local box = frame(sg, { Name = "Box", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		frame(box, { Name = "Front", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 3) })
		frame(box, { Name = "L", BackgroundColor3 = WHITE, Size = UDim2.new(0, 3, 0.35, 0) })
		frame(box, { Name = "R", BackgroundColor3 = WHITE, Size = UDim2.new(0, 3, 0.35, 0), Position = UDim2.new(1, -3, 0, 0) })
		text(box, { Name = "N", Text = tostring(k), TextColor3 = WHITE, TextTransparency = 0.15, Size = UDim2.fromScale(0.5, 0.22), Position = UDim2.fromScale(0.25, 0.12) })
	end
end

----------------------------------------------------------------------
-- Arches de porte (gonflables)
----------------------------------------------------------------------

function RaceProps.BuildArch(cf: CFrame, width: number, index: number): Model
	local model = Instance.new("Model")
	model.Name = "RaceGate_" .. index
	local r = width / 2 + 1.2
	local rise = 9
	local seg = 11
	local tubeD = 2
	local parts = {}
	-- piliers
	for _, side in ipairs({ -1, 1 }) do
		local p = part(model, "Leg", Vector3.new(rise, tubeD, tubeD), cf * CFrame.new(side * r, rise / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), PINK, M.SmoothPlastic, "Cyl")
		p:SetAttribute("BaseColor", p.Color)
		table.insert(parts, p)
		part(model, "Foot", Vector3.new(3, 0.6, 3), cf * CFrame.new(side * r, 0.3, 0), INK, M.Rubber)
	end
	-- arc (demi-ellipse aplatie au-dessus des piliers)
	local prev: Vector3? = nil
	for k = 0, seg do
		local a = math.pi * k / seg
		local p = (cf * CFrame.new(-math.cos(a) * r, rise + math.sin(a) * r * 0.45, 0)).Position
		if prev then
			local mid = (prev + p) / 2
			local len = (p - prev).Magnitude + 0.5
			local c = CFrame.lookAt(mid, p) * CFrame.Angles(0, math.rad(90), 0)
			local tube = part(model, "Tube", Vector3.new(len, tubeD, tubeD), c, if k % 2 == 0 then PINK else WHITE, M.SmoothPlastic, "Cyl")
			tube:SetAttribute("BaseColor", tube.Color)
			table.insert(parts, tube)
		end
		prev = p
	end
	-- panneau "n" au sommet
	local _, sg = canvas(model, "Num", Vector3.new(4, 2, 0.05), cf * CFrame.new(0, rise + r * 0.45 - 2.2, -0.2), Enum.NormalId.Front, 30)
	local lbl = text(sg, { Name = "N", Text = tostring(index), TextColor3 = WHITE, Size = UDim2.fromScale(1, 1) })
	local _ = lbl
	-- rideau lumineux (visible seulement pour la prochaine porte)
	local veil = part(model, "Veil", Vector3.new(r * 2 - tubeD, rise + r * 0.3, 0.1), cf * CFrame.new(0, (rise + r * 0.3) / 2, 0), CYAN, M.Neon)
	veil.Transparency = 0.88
	veil.CastShadow = false
	model:SetAttribute("GateIndex", index)
	return model
end

function RaceProps.SetGateState(model: Model, state: string)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			if d.Name == "Veil" then
				d.Transparency = if state == "next" then 0.84 else 1
			elseif d.Name == "Tube" or d.Name == "Leg" then
				local base = d:GetAttribute("BaseColor")
				local color = if typeof(base) == "Color3" then base else PINK
				if state == "next" then
					d.Material = M.Neon
					d.Color = if d.Name == "Leg" then CYAN else color:Lerp(CYAN, 0.35)
				else
					d.Material = M.SmoothPlastic
					d.Color = color
				end
				d.Transparency = if state == "done" then 0.7 else 0
			end
		end
	end
end

return RaceProps
