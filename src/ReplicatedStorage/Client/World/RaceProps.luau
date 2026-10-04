--[[
	RaceProps (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > RaceProps

	🏁 Décor 3D des courses de rue (v10 RACE10, v11 RACE11), construit CÔTÉ
	CLIENT et en flux par RaceClient (rien sur le serveur) :
	  - QG DES COURSES (zone "RaceMeet" de LAYOUT10) : dalle d'asphalte avec
	    marquages, bâtiment des stands (3 box, rideaux levés, établis, pneus)
	    surmonté de la TOUR DE CONTRÔLE vitrée, comptoir d'inscription (invite
	    E, hauteur 3,3), GRAND ÉCRAN LED (records par parcours AVEC LES
	    AVATARS + classement des pilotes par rang), TRIBUNE de 3 gradins
	    (assises 1,85, garde-corps 3,5), PLATEAU TOURNANT avec une voiture
	    d'exposition, podium 1-2-3 avec coupe dorée, arbre de feux de départ,
	    pneus, cônes, drapeaux à damier ;
	  - PORTIQUE DE DÉPART (à la ligne de chaque parcours) : 2 piliers à
	    bandes, poutre en treillis, banderole au nom du parcours, ÉCRAN LED
	    central (nom, 3-2-1-GO géant, état), 5 blocs de FEUX (rouges puis
	    verts : SetLights), ligne de départ à damier + "START", cases de
	    grille numérotées à l'échelle des voitures v11, MURETS rouge / blanc
	    le long de la grille, COMMISSAIRE qui agite le drapeau à damier ;
	  - ARCHE D'ARRIVÉE (sprint) à damier, banderole "FINISH" ;
	  - ARCHES DE PORTE gonflables numérotées (la prochaine brille, voile
	    lumineux + chevrons ; franchie : elle s'affaisse et s'efface) ;
	  - PANNEAUX À CHEVRONS à l'extérieur des virages (pendant SA course) ;
	  - FANTÔME (voiture translucide) et FLAMMES de nitro (pièces ancrées
	    déplacées par RaceClient).
	Aucune vraie lumière (Neon doux), aucun son. Tout est ancré, sans
	collision, sans requête, sans contact.

	API :
	  RaceProps.BuildHQ(cf, w, d) -> (Model, parts : { Prompt, Board, BoardGui,
	    Screen, Deco, Turntable = { Base: BasePart, Center: CFrame }, Pilots })
	  RaceProps.BuildGantry(cf, width, title, finish?) -> (Model, { Lights, Screen, Marshal })
	  RaceProps.SetLights(lights, stage)   stage : 0 éteint, 1..5 rouges allumés, 6 = verts (GO)
	  RaceProps.SetScreen(screen, big, small?, color?)  écran LED du portique
	  RaceProps.BuildArch(cf, width, index) -> Model
	  RaceProps.SetGateState(model, state)  "next" | "later" | "done"
	  RaceProps.GridMarks(parent, cfs)      cases peintes
	  RaceProps.BuildChevron(cf, turn) -> Model   (cf : pied du panneau, -Z = face à la route)
	  RaceProps.Ghostify(model)             voiture fantôme (translucide, sans collision)
	  RaceProps.BuildFlames(parent) -> { BasePart } (2 flammes de nitro)
	  RaceProps.WaveFlag(parts, t)          drapeau du commissaire
]]

local TweenService = game:GetService("TweenService")

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
local GLASS = rgb(120, 170, 200)
local SEAT_BLUE = rgb(40, 110, 200)

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
RaceProps.Canvas = canvas

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
RaceProps.Text = text
RaceProps.Frame = frame

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end
RaceProps.Corner = corner

-- Verso d'un panneau : pièce invisible un peu plus épaisse, retournée, qui
-- porte une copie de la SurfaceGui sur SA face avant (lisible des deux côtés)
local function backSide(parent: Instance, base: BasePart, sg: SurfaceGui)
	local p = part(parent, base.Name .. "Back", base.Size + Vector3.new(0, 0, 0.1), base.CFrame * CFrame.Angles(0, math.pi, 0), WHITE)
	p.Transparency = 1
	p.CastShadow = false
	local copy = sg:Clone()
	copy.Face = Enum.NormalId.Front
	copy.Parent = p
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

-- Drapeau à damier sur son mât (cloth = pièce qui flotte : WaveFlag)
local function flag(parent: Instance, base: CFrame, height: number): BasePart
	part(parent, "FlagPole", Vector3.new(height, 0.3, 0.3), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), STEEL, M.Metal, "Cyl")
	part(parent, "FlagKnob", Vector3.new(0.5, 0.5, 0.5), base * CFrame.new(0, height + 0.2, 0), YELLOW, M.Metal, "Ball")
	local cloth, sg = canvas(parent, "Flag", Vector3.new(3.6, 2.4, 0.06), base * CFrame.new(1.95, height - 1.4, 0) * CFrame.Angles(0, 0, math.rad(-3)), Enum.NormalId.Front, 20)
	cloth.Transparency = 0
	cloth.Color = WHITE
	cloth.Material = M.Fabric
	checker(sg, 6, 4, INK, WHITE)
	backSide(parent, cloth, sg)
	return cloth
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
		local lamp = part(parent, if k <= 2 then "RedLamp" else "GreenLamp", Vector3.new(0.12, 0.7, 0.7), cf * CFrame.new(0, y, -0.47) * CFrame.Angles(0, math.rad(90), 0), rgb(70, 30, 34), M.SmoothPlastic, "Cyl")
		if k <= 2 then
			table.insert(reds, lamp)
		else
			lamp.Color = rgb(30, 60, 40)
			table.insert(greens, lamp)
		end
	end
	return { Red = reds, Green = greens }
end

-- Muret de course (bloc en béton à bandes rouges / blanches), pied au sol
local function barrier(parent: Instance, cf: CFrame, length: number, k: number)
	part(parent, "Barrier", Vector3.new(1.2, 2.2, length), cf * CFrame.new(0, 1.1, 0), if k % 2 == 0 then RED else WHITE, M.SmoothPlastic)
	part(parent, "BarrierFoot", Vector3.new(1.8, 0.5, length - 0.02), cf * CFrame.new(0, 0.25, 0), CONCRETE, M.Concrete).CastShadow = false
end

-- Commissaire de piste (NPCModels, si dispo) + son grand drapeau à damier
local function marshal(parent: Instance, cf: CFrame, seed: number): any
	local info: { [string]: any } = {}
	local ok, NPCModels = pcall(function()
		return require(game:GetService("ReplicatedStorage").Shared.NPCModels) :: any
	end)
	if ok and NPCModels then
		local okB, npc = pcall(NPCModels.Build, "worker", { Seed = seed, Solid = false, Look = false, Name = "Marshal" })
		if okB and npc then
			npc.Parent = parent
			pcall(NPCModels.Place, npc, cf)
			info.Npc = npc
			info.Api = NPCModels
		end
	end
	-- grand drapeau à damier sur hampe, tenu à côté du commissaire
	local base = cf * CFrame.new(1.6, 0, -0.4)
	part(parent, "MarshalPole", Vector3.new(0.22, 8, 0.22), base * CFrame.new(0, 4, 0), STEEL, M.Metal)
	local cloth, sg = canvas(parent, "MarshalFlag", Vector3.new(4.2, 2.8, 0.06), base * CFrame.new(2.15, 6.4, 0), Enum.NormalId.Front, 18)
	cloth.Transparency = 0
	cloth.Color = WHITE
	cloth.Material = M.Fabric
	checker(sg, 7, 5, INK, WHITE)
	backSide(parent, cloth, sg)
	info.Flag = cloth
	info.FlagBase = base
	info.Back = parent:FindFirstChild("MarshalFlagBack")
	info.Cf = cf
	return info
end

-- Drapeau qui flotte (léger balancement) : info = résultat de marshal()
function RaceProps.WaveFlag(info: any, t: number)
	if type(info) ~= "table" or not info.Flag then
		return
	end
	local a = math.sin(t * 5.5) * 0.35
	local cf = info.FlagBase * CFrame.new(0, 6.4, 0) * CFrame.Angles(0, a, math.sin(t * 3.1) * 0.05) * CFrame.new(2.15, 0, 0)
	info.Flag.CFrame = cf
	if info.Back and info.Back:IsA("BasePart") then
		info.Back.CFrame = cf * CFrame.Angles(0, math.pi, 0)
	end
	if info.Npc and info.Api then
		pcall(info.Api.Animate, info.Npc, "wave", t)
	end
end

----------------------------------------------------------------------
-- QG des courses
----------------------------------------------------------------------

-- cf : centre de la zone au sol (dessus du trottoir), -Z local = vers la route
function RaceProps.BuildHQ(cf: CFrame, w: number, d: number): (Model, { [string]: any })
	local model = Instance.new("Model")
	model.Name = "RaceHQ"
	local W, D = math.max(48, w - 2), math.max(34, d - 2)
	local hw, hd = W / 2, D / 2
	-- dalle (dessus à +0,3) avec bordure
	part(model, "Pad", Vector3.new(W, 0.8, D), cf * CFrame.new(0, -0.1, 0), ASPHALT, M.Asphalt).CastShadow = false
	part(model, "CurbFront", Vector3.new(W + 0.1, 0.58, 0.6), cf * CFrame.new(0, 0.05, -hd + 0.26), CONCRETE, M.Concrete)
	-- marquages au sol (SurfaceGui sur pièce invisible ; lus depuis la route)
	local _, marks = canvas(model, "Marks", Vector3.new(W - 2, 0.05, D - 2), cf * CFrame.new(0, 0.33, 0) * CFrame.Angles(0, math.pi, 0), Enum.NormalId.Top, 6)
	local strip = frame(marks, { Name = "Checker", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -18) })
	checker(strip, 30, 1, INK, WHITE)
	text(marks, { Name = "Paint", Text = "🏁 RACE HQ", TextColor3 = rgb(255, 214, 90), TextTransparency = 0.1, Size = UDim2.new(0.3, 0, 0.12, 0), Position = UDim2.new(0.36, 0, 0.42, 0) })

	-- STANDS (au fond, à gauche) : 3 box, auvent rayé, tour de contrôle
	local bx0, bx1 = -hw + 1.5, 1
	local bw = bx1 - bx0
	local bz0 = hd - 13
	local bh = 10
	local center = (bx0 + bx1) / 2
	part(model, "BackWall", Vector3.new(bw, bh, 0.8), cf * CFrame.new(center, bh / 2 + 0.3, hd - 0.9), WHITE, M.Concrete)
	part(model, "SideL", Vector3.new(0.8, bh, 12), cf * CFrame.new(bx0 + 0.4, bh / 2 + 0.3, bz0 + 6), WHITE, M.Concrete)
	part(model, "SideR", Vector3.new(0.8, bh, 12), cf * CFrame.new(bx1 - 0.4, bh / 2 + 0.3, bz0 + 6), WHITE, M.Concrete)
	part(model, "Roof", Vector3.new(bw + 1.6, 0.8, 14.6), cf * CFrame.new(center, bh + 0.7, bz0 + 5.5), rgb(70, 72, 84), M.Metal)
	part(model, "Floor", Vector3.new(bw - 1.6, 0.2, 11.4), cf * CFrame.new(center, 0.4, bz0 + 6.2), rgb(150, 150, 156), M.Concrete).CastShadow = false
	for k = 0, 3 do
		local x = bx0 + 0.4 + k * (bw - 0.8) / 3
		part(model, "Pillar", Vector3.new(1, bh, 1), cf * CFrame.new(math.clamp(x, bx0 + 0.9, bx1 - 0.9), bh / 2 + 0.3, bz0 + 0.4), RED, M.SmoothPlastic)
	end
	for k = 0, 2 do
		local x = bx0 + 0.4 + (k + 0.5) * (bw - 0.8) / 3
		local doorW = (bw - 0.8) / 3 - 1.2
		part(model, "Shutter", Vector3.new(doorW, 1.4, 0.5), cf * CFrame.new(x, bh - 0.4, bz0 + 0.6), STEEL, M.DiamondPlate)
		part(model, "Bench", Vector3.new(doorW * 0.7, 3.0, 1.6), cf * CFrame.new(x, 1.8, hd - 2.4), rgb(90, 96, 110), M.Metal)
		part(model, "BenchTop", Vector3.new(doorW * 0.72, 0.2, 1.7), cf * CFrame.new(x, 3.4, hd - 2.4), rgb(176, 120, 70), M.Wood)
		part(model, "ToolBoard", Vector3.new(doorW * 0.7, 3, 0.2), cf * CFrame.new(x, 5.6, hd - 1.4), rgb(64, 64, 76), M.SmoothPlastic)
		tyreStack(model, cf * CFrame.new(x + doorW * 0.36, 0.3, hd - 5), 3, if k == 1 then YELLOW else RED)
	end
	for k = 0, 9 do
		local sx = bx0 + (k + 0.5) * bw / 10
		part(model, "Awning", Vector3.new(bw / 10, 0.2, 3.2), cf * CFrame.new(sx, bh - 0.9, bz0 - 1.3) * CFrame.Angles(math.rad(-16), 0, 0), if k % 2 == 0 then RED else WHITE, M.Fabric)
	end
	-- tour de contrôle vitrée sur le toit (côté droit du bâtiment)
	local tx = bx1 - 7
	local towerCf = cf * CFrame.new(tx, bh + 1.1, bz0 + 6)
	part(model, "TowerBase", Vector3.new(12, 0.6, 10), towerCf * CFrame.new(0, 0.3, 0), rgb(60, 62, 72), M.Metal)
	part(model, "TowerGlass", Vector3.new(11.4, 4.6, 9.4), towerCf * CFrame.new(0, 2.9, 0), GLASS, M.Glass).Transparency = 0.45
	part(model, "TowerRoof", Vector3.new(12.6, 0.6, 10.6), towerCf * CFrame.new(0, 5.5, 0), rgb(40, 42, 52), M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(model, "TowerPost", Vector3.new(0.4, 4.6, 0.4), towerCf * CFrame.new(sx * 5.6, 2.9, sz * 4.6), rgb(40, 42, 52), M.Metal)
		end
	end
	part(model, "TowerDesk", Vector3.new(9, 1.6, 1.2), towerCf * CFrame.new(0, 1.4, -3.6), DARK, M.SmoothPlastic)
	for k = -1, 1 do
		part(model, "TowerMonitor", Vector3.new(2, 1.3, 0.2), towerCf * CFrame.new(k * 2.8, 2.9, -3.4) * CFrame.Angles(math.rad(-12), 0, 0), rgb(40, 90, 140), M.Glass)
	end
	-- enseigne "RACE CONTROL" sur la tour
	local sign, sgs = canvas(model, "Sign", Vector3.new(11, 1.8, 0.3), towerCf * CFrame.new(0, 6.8, -4.9), Enum.NormalId.Front, 24)
	sign.Transparency = 0
	sign.Color = INK
	local signBg = frame(sgs, { Name = "Bg", BackgroundColor3 = INK, Size = UDim2.fromScale(1, 1) })
	local band = frame(signBg, { Name = "Band", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.16, 0), Position = UDim2.fromScale(0, 0.84) })
	checker(band, 40, 2, INK, WHITE, 2)
	text(signBg, { Name = "Title", Text = "🏁 RACE CONTROL", TextColor3 = rgb(255, 214, 90), Size = UDim2.fromScale(0.92, 0.7), Position = UDim2.fromScale(0.04, 0.06), ZIndex = 3 })
	-- enseigne "STREET RACES" sur l'avant du toit (gauche)
	local sign2, sgs2 = canvas(model, "Sign2", Vector3.new(bw * 0.5, 2.4, 0.3), cf * CFrame.new(bx0 + bw * 0.28, bh + 2.3, bz0 + 0.4), Enum.NormalId.Front, 24)
	sign2.Transparency = 0
	sign2.Color = INK
	local s2bg = frame(sgs2, { Name = "Bg", BackgroundColor3 = RED, Size = UDim2.fromScale(1, 1) })
	text(s2bg, { Name = "T", Text = "STREET RACES", Size = UDim2.fromScale(0.9, 0.76), Position = UDim2.fromScale(0.05, 0.12) })
	part(model, "SignPostL", Vector3.new(0.4, 1.4, 0.4), cf * CFrame.new(bx0 + bw * 0.12, bh + 1.0, bz0 + 0.6), STEEL, M.Metal)
	part(model, "SignPostR", Vector3.new(0.4, 1.4, 0.4), cf * CFrame.new(bx0 + bw * 0.44, bh + 1.0, bz0 + 0.6), STEEL, M.Metal)

	-- COMPTOIR d'inscription (devant les stands) : invite E (hauteur 3,3)
	local counterCf = cf * CFrame.new(center, 0, bz0 - 5.5)
	part(model, "Counter", Vector3.new(8, 3, 2), counterCf * CFrame.new(0, 1.8, 0), WHITE, M.SmoothPlastic)
	part(model, "CounterTop", Vector3.new(8.4, 0.3, 2.4), counterCf * CFrame.new(0, 3.45, 0), rgb(176, 120, 70), M.Wood)
	local _, face = canvas(model, "CounterFace", Vector3.new(7.6, 2.4, 0.05), counterCf * CFrame.new(0, 1.9, -1.03), Enum.NormalId.Front, 30)
	local fbg = frame(face, { Name = "Bg", BackgroundColor3 = RED, Size = UDim2.fromScale(1, 1) })
	local fb = frame(fbg, { Name = "Band", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.78) })
	checker(fb, 22, 2, INK, WHITE, 2)
	text(fbg, { Name = "T", Text = "SIGN UP · E", Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.12), ZIndex = 3 })
	part(model, "ScreenStand", Vector3.new(0.3, 1.2, 0.3), counterCf * CFrame.new(2.2, 4.2, 0.4), DARK, M.Metal)
	local screen, ssg = canvas(model, "Screen", Vector3.new(2.8, 1.8, 0.2), counterCf * CFrame.new(2.2, 5.5, 0.4) * CFrame.Angles(math.rad(-10), 0, 0), Enum.NormalId.Front, 60)
	screen.Transparency = 0
	screen.Color = DARK
	local sbg = frame(ssg, { Name = "Bg", BackgroundColor3 = rgb(20, 24, 40), Size = UDim2.fromScale(1, 1) })
	text(sbg, { Name = "T", Text = "🏁 3 · 2 · 1 · GO", TextColor3 = CYAN, Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.25) })
	local prompt = part(model, "PromptAnchor", Vector3.new(1, 1, 1), counterCf * CFrame.new(0, 3.5, -1.6), WHITE)
	prompt.Transparency = 1

	-- GRAND ÉCRAN LED (à droite, au fond) : records + pilotes (avec avatars)
	local boardCf = cf * CFrame.new(hw * 0.52, 0, hd - 2.2)
	local bW, bH = math.min(26, W * 0.42), 12.5
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "BoardPost", Vector3.new(1, 8.2, 1), boardCf * CFrame.new(sx * (bW / 2 - 2), 4.4, 0.7), STEEL, M.Metal)
		part(model, "BoardFoot", Vector3.new(2.2, 0.6, 2.2), boardCf * CFrame.new(sx * (bW / 2 - 2), 0.6, 0.7), CONCRETE, M.Concrete)
	end
	part(model, "BoardFrame", Vector3.new(bW + 1, bH + 1, 0.8), boardCf * CFrame.new(0, 8 + bH / 2, 0.6), INK, M.SmoothPlastic)
	part(model, "BoardCap", Vector3.new(bW + 1.4, 0.4, 1.4), boardCf * CFrame.new(0, 8.7 + bH, 0.6), RED, M.SmoothPlastic)
	local boardPart, boardGui = canvas(model, "Board", Vector3.new(bW, bH, 0.3), boardCf * CFrame.new(0, 8 + bH / 2, 0.08), Enum.NormalId.Front, 32)
	boardPart.Transparency = 0
	boardPart.Color = rgb(20, 22, 34)
	boardGui.LightInfluence = 0.2
	boardGui.MaxDistance = 300

	-- TRIBUNE (devant l'écran) : 3 gradins (marche 1,0 depuis la dalle),
	-- bancs à 1,85 au-dessus de chaque gradin, garde-corps 3,5
	local gx0, gx1 = 4, hw - 1.5
	local gwid = gx1 - gx0
	local gcx = (gx0 + gx1) / 2
	local gz0 = 0
	local topTier = 0
	for tier = 0, 2 do
		local z = gz0 + tier * 3 + 1.49
		local floorTop = 1.3 + tier * 1.0
		topTier = floorTop
		part(model, "StandTier", Vector3.new(gwid, floorTop, 2.98), cf * CFrame.new(gcx, floorTop / 2, z), CONCRETE, M.Concrete)
		local seatTop = floorTop + 1.85
		part(model, "StandSeat", Vector3.new(gwid - 1, 0.3, 1.6), cf * CFrame.new(gcx, seatTop - 0.15, z + 0.2), SEAT_BLUE, M.SmoothPlastic)
		part(model, "StandSeatBack", Vector3.new(gwid - 1, 1.4, 0.25), cf * CFrame.new(gcx, seatTop + 0.7, z + 1.05), SEAT_BLUE, M.SmoothPlastic)
		for k = 0, 3 do
			part(model, "StandLeg", Vector3.new(0.3, 1.7, 1.2), cf * CFrame.new(gx0 + 1.5 + k * (gwid - 3) / 3, floorTop + 0.85, z + 0.2), STEEL, M.Metal)
		end
	end
	-- garde-corps : arrière (3,5 au-dessus du dernier gradin) et côtés (même hauteur)
	local railY = topTier + 3.5
	part(model, "StandRailBack", Vector3.new(gwid, 0.25, 0.25), cf * CFrame.new(gcx, railY, gz0 + 8.85), STEEL, M.Metal)
	for k = 0, 4 do
		part(model, "StandRailPost", Vector3.new(0.2, 3.5, 0.2), cf * CFrame.new(gx0 + 0.3 + k * (gwid - 0.6) / 4, topTier + 1.75, gz0 + 8.85), STEEL, M.Metal)
	end
	for _, sx in ipairs({ gx0 + 0.15, gx1 - 0.15 }) do
		part(model, "StandRailSide", Vector3.new(0.25, 0.25, 8.6), cf * CFrame.new(sx, railY, gz0 + 4.5), STEEL, M.Metal)
		part(model, "StandRailSidePost", Vector3.new(0.2, railY - 1.3, 0.2), cf * CFrame.new(sx, 1.3 + (railY - 1.3) / 2, gz0 + 0.3), STEEL, M.Metal)
	end

	-- PLATEAU TOURNANT (devant, à gauche) : voiture d'exposition (RaceClient)
	local ttCenter = cf * CFrame.new(-hw + 10.6, 0.3, -hd + 10.6)
	part(model, "TurntableRim", Vector3.new(0.5, 20.4, 20.4), ttCenter * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), DARK, M.Metal, "Cyl")
	local ttBase = part(model, "Turntable", Vector3.new(0.3, 19.4, 19.4), ttCenter * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(210, 210, 216), M.DiamondPlate, "Cyl")
	ttBase.CastShadow = false

	-- podium 1-2-3 avec coupe (devant, au centre)
	local podCf = cf * CFrame.new(-1, 0, -hd + 6.5)
	for _, spec in ipairs({ { 0, 2.0, "1", YELLOW }, { -3.4, 1.4, "2", rgb(200, 206, 216) }, { 3.4, 0.9, "3", rgb(214, 150, 90) } }) do
		part(model, "PodiumStep", Vector3.new(3.3, spec[2], 3), podCf * CFrame.new(spec[1], 0.3 + spec[2] / 2, 0), WHITE, M.SmoothPlastic)
		local _, ng = canvas(model, "PodiumNum", Vector3.new(2.4, spec[2] * 0.8, 0.05), podCf * CFrame.new(spec[1], 0.3 + spec[2] / 2, -1.53), Enum.NormalId.Front, 40)
		text(ng, { Name = "N", Text = spec[3], TextColor3 = spec[4], Size = UDim2.fromScale(1, 1) })
	end
	local cupCf = podCf * CFrame.new(0, 2.3, 0.2)
	part(model, "CupFoot", Vector3.new(1.2, 0.3, 1.2), cupCf * CFrame.new(0, 0.15, 0), DARK, M.Marble)
	part(model, "CupStem", Vector3.new(0.7, 0.35, 0.35), cupCf * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), YELLOW, M.Metal, "Cyl")
	part(model, "CupBowl", Vector3.new(1.3, 1.3, 1.3), cupCf * CFrame.new(0, 1.35, 0), YELLOW, M.Metal, "Ball")
	part(model, "CupRim", Vector3.new(0.2, 1.36, 1.36), cupCf * CFrame.new(0, 1.65, 0) * CFrame.Angles(0, 0, math.rad(90)), YELLOW, M.Metal, "Cyl")
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "CupHandle", Vector3.new(0.18, 0.7, 0.18), cupCf * CFrame.new(sx * 0.78, 1.4, 0), YELLOW, M.Metal)
	end

	-- arbre de feux de départ (devant, à droite)
	local treeCf = cf * CFrame.new(hw - 3, 0, -hd + 3)
	part(model, "TreePole", Vector3.new(0.6, 7.5, 0.6), treeCf * CFrame.new(0, 3.9, 0), STEEL, M.Metal)
	local deco = {}
	for k = 0, 2 do
		table.insert(deco, lightPod(model, treeCf * CFrame.new(0, 6.4 - k * 0.2, 0) * CFrame.new((k - 1) * 1.6, 1.4, -0.5)))
	end
	-- pneus, cônes, drapeaux
	tyreStack(model, cf * CFrame.new(-hw + 1.8, 0.3, -1), 4)
	tyreStack(model, cf * CFrame.new(hw - 1.8, 0.3, hd - 1.8), 4, YELLOW)
	for k = 0, 3 do
		cone(model, cf * CFrame.new(6 + k * 4.2, 0.3, -hd + 1.6))
	end
	local flags = {
		flag(model, cf * CFrame.new(-hw + 1, 0.3, -hd + 1.2), 7),
		flag(model, cf * CFrame.new(hw - 8, 0.3, -hd + 1), 7),
	}
	return model, {
		Prompt = prompt,
		Board = boardPart,
		BoardGui = boardGui,
		Screen = sbg,
		Deco = deco,
		Flags = flags,
		Turntable = { Base = ttBase, Center = ttCenter * CFrame.new(0, 0.7, 0) },
	}
end

----------------------------------------------------------------------
-- Portique de départ / arche d'arrivée
----------------------------------------------------------------------

-- cf : centre de la ligne au sol (dessus de la chaussée), -Z = sens de la course
function RaceProps.BuildGantry(cf: CFrame, width: number, title: string, finish: boolean?, opts: any?): (Model, { [string]: any })
	local o = if type(opts) == "table" then opts else {}
	local model = Instance.new("Model")
	model.Name = if finish then "RaceFinish" else "RaceGantry"
	local half = width / 2 + 1.6
	local H = 14
	for _, side in ipairs({ -1, 1 }) do
		local x = side * half
		part(model, "PillarBase", Vector3.new(2.8, 0.8, 2.8), cf * CFrame.new(x, 0.4, 0), CONCRETE, M.Concrete)
		part(model, "Pillar", Vector3.new(1.6, H, 1.6), cf * CFrame.new(x, H / 2 + 0.5, 0), if finish then WHITE else RED, M.SmoothPlastic)
		for k = 0, 3 do
			part(model, "PillarStripe", Vector3.new(1.66, 1.1, 1.66), cf * CFrame.new(x, 2.2 + k * 2.4, 0), if finish then INK else YELLOW, M.SmoothPlastic)
		end
	end
	-- poutre en treillis (2 membrures + diagonales)
	local span = half * 2 + 1.3
	part(model, "BeamTop", Vector3.new(span, 0.55, 1.3), cf * CFrame.new(0, H + 0.2, 0), STEEL, M.Metal)
	part(model, "BeamLow", Vector3.new(span, 0.55, 1.3), cf * CFrame.new(0, H - 2.1, 0), STEEL, M.Metal)
	local n = math.max(4, math.floor(span / 3))
	for k = 0, n - 1 do
		local x0 = -span / 2 + (k + 0.5) * span / n
		local ang = if k % 2 == 0 then math.rad(40) else math.rad(-40)
		part(model, "Diag", Vector3.new(0.25, 2.9, 0.25), cf * CFrame.new(x0, H - 0.95, 0) * CFrame.Angles(0, 0, ang), STEEL, M.Metal)
	end
	-- banderole (les deux faces)
	local bannerW = math.min(span - 4, 28)
	local banner, bsg = canvas(model, "Banner", Vector3.new(bannerW, 2.8, 0.2), cf * CFrame.new(0, H + 1.9, 0), Enum.NormalId.Front, 28)
	banner.Transparency = 0
	banner.Color = INK
	local bg = frame(bsg, { Name = "Bg", BackgroundColor3 = if finish then WHITE else INK, Size = UDim2.fromScale(1, 1) })
	if finish then
		checker(bg, 36, 4, INK, WHITE)
		local tag = frame(bg, { Name = "Tag", BackgroundColor3 = INK, Size = UDim2.fromScale(0.36, 0.8), Position = UDim2.fromScale(0.32, 0.1), ZIndex = 2 })
		text(tag, { Name = "T", Text = "FINISH", TextColor3 = rgb(255, 214, 90), Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), ZIndex = 3 })
	else
		local l = frame(bg, { Name = "L", BackgroundTransparency = 1, Size = UDim2.new(0.12, 0, 1, 0) })
		checker(l, 3, 4, INK, WHITE, 2)
		local r = frame(bg, { Name = "R", BackgroundTransparency = 1, Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.fromScale(0.88, 0) })
		checker(r, 3, 4, INK, WHITE, 2)
		text(bg, { Name = "Title", Text = title, TextColor3 = rgb(255, 214, 90), Size = UDim2.fromScale(0.72, 0.8), Position = UDim2.fromScale(0.14, 0.1), ZIndex = 3 })
	end
	backSide(model, banner, bsg)
	local lights = {}
	local screenInfo = nil
	local marshalInfo = nil
	if not finish then
		-- feux de départ : 5 blocs sous la poutre (face à la grille : +Z)
		for k = 1, 5 do
			local x = (k - 3) * 2.2
			part(model, "PodHanger", Vector3.new(0.2, 0.9, 0.2), cf * CFrame.new(x, H - 2.6, 0.9), INK, M.Metal)
			table.insert(lights, lightPod(model, cf * CFrame.new(x, H - 4.6, 1.2) * CFrame.Angles(0, math.pi, 0)))
		end
		-- écrans LED sur les piliers, face à la grille (+Z) : 3-2-1-GO géant
		local screens = {}
		for _, side in ipairs({ -1, 1 }) do
			local scf = cf * CFrame.new(side * half, 7.2, 0.86) * CFrame.Angles(0, math.pi, 0)
			part(model, "LedFrame", Vector3.new(4.6, 3.6, 0.3), scf * CFrame.new(0, 0, 0.12), INK, M.SmoothPlastic)
			local lp, lsg = canvas(model, "Led", Vector3.new(4.2, 3.2, 0.1), scf * CFrame.new(0, 0, -0.06), Enum.NormalId.Front, 40)
			lp.Transparency = 0
			lp.Color = rgb(10, 12, 20)
			lsg.LightInfluence = 0
			local lbg = frame(lsg, { Name = "Bg", BackgroundColor3 = rgb(10, 12, 22), Size = UDim2.fromScale(1, 1) })
			local big = text(lbg, { Name = "Big", Text = "", TextColor3 = rgb(255, 80, 80), Size = UDim2.fromScale(0.9, 0.62), Position = UDim2.fromScale(0.05, 0.06) })
			local small = text(lbg, { Name = "Small", Text = title, TextColor3 = rgb(255, 214, 90), Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.72), Font = Enum.Font.GothamBold })
			table.insert(screens, { Big = big, Small = small })
		end
		screenInfo = screens
		-- ligne de départ : damier + "START" + cases de grille (+Z = derrière la ligne)
		local _, line = canvas(model, "Line", Vector3.new(width, 0.05, 2.6), cf * CFrame.new(0, 0.16, 0), Enum.NormalId.Top, 10)
		checker(line, math.max(8, math.floor(width / 1.3)), 2, INK, WHITE)
		local _, startTxt = canvas(model, "StartText", Vector3.new(math.min(width - 2, 14), 0.05, 3.2), cf * CFrame.new(0, 0.16, 4.4), Enum.NormalId.Top, 10)
		text(startTxt, { Name = "T", Text = "START", TextColor3 = WHITE, TextTransparency = 0.12, Size = UDim2.fromScale(1, 1) })
		-- murets rouge / blanc le long de la grille (hors chaussée, sur le bord)
		local gridLen = tonumber(o.GridLength) or 100
		local edge = width / 2 + 2.6
		local seg = 6
		for _, side in ipairs({ -1, 1 }) do
			local k = 0
			local z = 6
			while z + seg <= gridLen do
				barrier(model, cf * CFrame.new(side * edge, 0.1, z + seg / 2), seg - 0.15, k)
				k += 1
				z += seg
			end
		end
		-- commissaire de piste au bord de la ligne (côté droit)
		marshalInfo = marshal(model, cf * CFrame.new(edge + 2.8, 0.1, -3) * CFrame.Angles(0, math.rad(-90), 0), #title * 7)
	else
		local _, line = canvas(model, "Line", Vector3.new(width, 0.05, 3.2), cf * CFrame.new(0, 0.16, 0), Enum.NormalId.Top, 10)
		checker(line, math.max(8, math.floor(width / 1.3)), 2, INK, WHITE)
	end
	return model, { Lights = lights, Screens = screenInfo, Marshal = marshalInfo }
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

-- Écrans LED du portique : gros texte + petit texte
function RaceProps.SetScreen(screens: { any }?, big: string, small: string?, color: Color3?)
	for _, s in ipairs(screens or {}) do
		s.Big.Text = big
		s.Big.TextColor3 = color or rgb(255, 80, 80)
		if small then
			s.Small.Text = small
		end
	end
end

-- Cases de la grille peintes au sol (une pièce invisible + SurfaceGui par case)
function RaceProps.GridMarks(parent: Instance, cfs: { CFrame })
	for k, cf in ipairs(cfs) do
		local _, sg = canvas(parent, "GridBox", Vector3.new(8.6, 0.05, 20), cf * CFrame.new(0, 0.21, 0), Enum.NormalId.Top, 8)
		local box = frame(sg, { Name = "Box", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		frame(box, { Name = "Front", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 4) })
		frame(box, { Name = "L", BackgroundColor3 = WHITE, Size = UDim2.new(0, 4, 0.3, 0) })
		frame(box, { Name = "R", BackgroundColor3 = WHITE, Size = UDim2.new(0, 4, 0.3, 0), Position = UDim2.new(1, -4, 0, 0) })
		text(box, { Name = "N", Text = tostring(k), TextColor3 = WHITE, TextTransparency = 0.15, Size = UDim2.fromScale(0.5, 0.14), Position = UDim2.fromScale(0.25, 0.06) })
	end
end

----------------------------------------------------------------------
-- Arches de porte (gonflables)
----------------------------------------------------------------------

function RaceProps.BuildArch(cf: CFrame, width: number, index: number): Model
	local model = Instance.new("Model")
	model.Name = "RaceGate_" .. index
	local r = width / 2 + 1.4
	local rise = 10
	local seg = 11
	local tubeD = 2.2
	-- piliers
	for _, side in ipairs({ -1, 1 }) do
		local p = part(model, "Leg", Vector3.new(rise, tubeD, tubeD), cf * CFrame.new(side * r, rise / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), PINK, M.SmoothPlastic, "Cyl")
		p:SetAttribute("BaseColor", p.Color)
		part(model, "Foot", Vector3.new(3.2, 0.6, 3.2), cf * CFrame.new(side * r, 0.3, 0), INK, M.Rubber)
		-- panneau à chevrons sur chaque pied (sens de la course)
		local _, cg = canvas(model, "Chev", Vector3.new(2.2, 2.2, 0.05), cf * CFrame.new(side * r, 4, -tubeD / 2 - 0.08) * CFrame.Angles(0, math.pi, 0), Enum.NormalId.Front, 30)
		local cbg = frame(cg, { Name = "Bg", BackgroundColor3 = INK, BackgroundTransparency = 0.1, Size = UDim2.fromScale(1, 1) })
		corner(cbg, 8)
		text(cbg, { Name = "T", Text = tostring(index), TextColor3 = YELLOW, Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05) })
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
		end
		prev = p
	end
	-- panneau "n" au sommet (les deux faces)
	local np, sg = canvas(model, "Num", Vector3.new(5, 2.4, 0.2), cf * CFrame.new(0, rise + r * 0.45 - 2.5, 0), Enum.NormalId.Front, 30)
	np.Transparency = 0
	np.Color = INK
	local nbg = frame(sg, { Name = "Bg", BackgroundColor3 = INK, Size = UDim2.fromScale(1, 1) })
	text(nbg, { Name = "N", Text = if index == 0 then "🏁" else tostring(index), TextColor3 = WHITE, Size = UDim2.fromScale(0.9, 0.86), Position = UDim2.fromScale(0.05, 0.07) })
	backSide(model, np, sg)
	-- rideau lumineux (visible seulement pour la prochaine porte)
	local veil = part(model, "Veil", Vector3.new(r * 2 - tubeD, rise + r * 0.3, 0.1), cf * CFrame.new(0, (rise + r * 0.3) / 2, 0), CYAN, M.Neon)
	veil.Transparency = 1
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
				elseif state == "passed" then
					d.Material = M.Neon
					d.Color = rgb(110, 255, 150)
				else
					d.Material = M.SmoothPlastic
					d.Color = color
				end
				d.Transparency = if state == "done" then 0.7 else 0
			end
		end
	end
end

-- Porte franchie : flash vert, puis l'arche s'affaisse et s'efface (~0,9 s), détruite ensuite
function RaceProps.PassGate(model: Model)
	RaceProps.SetGateState(model, "passed")
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.15)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local goal: { [string]: any } = { CFrame = d.CFrame * CFrame.new(0, -2.5, 0) }
			if d.Transparency < 1 then
				goal.Transparency = 1
			end
			TweenService:Create(d, info, goal):Play()
		elseif d:IsA("SurfaceGui") then
			d.Enabled = false
		end
	end
	task.delay(1.1, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- Panneaux à chevrons (virages), fantôme, flammes de nitro
----------------------------------------------------------------------

-- cf : pied du panneau au sol, -Z = face à la route ; turn : +1 virage à
-- gauche (flèches vers la gauche vues de la route), -1 à droite
function RaceProps.BuildChevron(cf: CFrame, turn: number): Model
	local model = Instance.new("Model")
	model.Name = "RaceChevron"
	for _, sx in ipairs({ -2.4, 2.4 }) do
		part(model, "ChevPost", Vector3.new(0.3, 3.6, 0.3), cf * CFrame.new(sx, 1.8, 0.1), STEEL, M.Metal)
	end
	local board, sg = canvas(model, "ChevBoard", Vector3.new(6.4, 2.2, 0.2), cf * CFrame.new(0, 4.4, 0), Enum.NormalId.Front, 24)
	board.Transparency = 0
	board.Color = RED
	local bg = frame(sg, { Name = "Bg", BackgroundColor3 = RED, Size = UDim2.fromScale(1, 1) })
	-- la face avant (-Z) regarde la route : vue de face, la gauche du lecteur = +X local
	text(bg, { Name = "T", Text = if turn > 0 then "‹ ‹ ‹" else "› › ›", TextColor3 = WHITE, Size = UDim2.fromScale(0.94, 0.9), Position = UDim2.fromScale(0.03, 0.05) })
	part(model, "ChevBack", Vector3.new(6.5, 2.3, 0.1), cf * CFrame.new(0, 4.4, 0.16), WHITE, M.SmoothPlastic)
	return model
end

-- Voiture fantôme : translucide, bleutée, sans collision ni requête
function RaceProps.Ghostify(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Anchored = true
			d.Color = d.Color:Lerp(rgb(120, 220, 255), 0.55)
			d.Transparency = math.max(d.Transparency, 0.62)
			if d.Material == M.Neon then
				d.Material = M.SmoothPlastic
			end
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("Decal") or d:IsA("Texture") then
			d:Destroy()
		end
	end
	model.Name = "RaceGhost"
end

-- 2 flammes de nitro (cônes Neon), déplacées par RaceClient derrière la voiture
function RaceProps.BuildFlames(parent: Instance): { BasePart }
	local list = {}
	for k = 1, 2 do
		local outer = part(parent, "NitroFlame", Vector3.new(2.6, 0.9, 0.9), CFrame.new(0, -500, 0), rgb(90, 170, 255), M.Neon, "Cyl")
		outer.Transparency = 0.25
		outer.CastShadow = false
		local inner = part(parent, "NitroCore", Vector3.new(1.6, 0.5, 0.5), CFrame.new(0, -500, 0), rgb(235, 250, 255), M.Neon, "Cyl")
		inner.CastShadow = false
		table.insert(list, outer)
		table.insert(list, inner)
		local _ = k
	end
	return list
end

return RaceProps
