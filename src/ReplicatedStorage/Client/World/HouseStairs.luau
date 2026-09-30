--[[
	HouseStairs (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseStairs

	🚶 Dopamine Town : la CAGE D'ESCALIER / le HALL d'entrée d'une maison 3D
	(dans la travée où la maison 2D dessine l'entrée, WorldLayout.HallSpan).

	(v9.9 HOUSE99 — "l'escalier est au milieu de l'entrée, ça n'a aucun sens,
	il n'y a plus de place") : tout est repensé, pour chaque style et chaque
	étage, manoir compris :
	  - l'escalier LONGE LE MUR DE DROITE de la cage (WorldLayout.StairSpan),
	    une volée droite par étage, empilées ; le COULOIR d'entrée à gauche
	    (WorldLayout.CorridorSpan, ~7,4 studs) va de la porte d'entrée à la
	    porte de derrière sans rien au milieu ;
	  - vrai escalier : 18 marches de 0,72 (giron ~1,06, ~34° ; manoir ~38°),
	    girons avec nez qui dépasse, contremarches, tapis d'escalier (sur le
	    giron ET la contremarche), limon à la française côté couloir, limon de
	    mur, sous-face en plâtre, balustres (2 par marche), main courante,
	    main courante murale sur consoles, poteaux de départ / d'arrivée ;
	    loft : escalier industriel (limons d'acier, marches épaisses en chêne,
	    contremarches ouvertes, garde-corps à lisses) ;
	  - collision : rampe lisse INVISIBLE sur la ligne du milieu des marches
	    (pieds à ± une demi-marche, jamais bloqué) + garde invisible côté vide ;
	  - à chaque étage un PALIER : le couloir mène aux passages des pièces et au
	    départ de la volée suivante ; trémie bordée d'un garde-corps ;
	  - hall d'entrée meublé à la taille des avatars (SCALE99 : table 2,3 à
	    2,8 ; meubles hauts 5,5 à 6,2) : console avec lampe, bouquet et
	    vide-poche, grand miroir, porte-manteau avec manteau / chapeau /
	    parapluie, tapis de couloir, plante, banc, tableau, placard sous
	    l'escalier ; manoir = grand vestibule (lustre, guéridon et bouquet) ;
	  - sols par style : tomettes (chaumière), damier noir et blanc (maison de
	    ville), béton ciré (loft), marbre à cabochons (manoir) ; parquet aux
	    étages ; murs enduit + lambris ; hauteur libre >= 8,5 partout.
	Coût : la COQUE (sols, trémies, murs : toujours là, avec l'extérieur) est
	séparée de l'INTÉRIEUR (escalier, garde-corps, meubles, lampes) qui est
	construit en flux comme les pièces (HouseBuilder : seulement quand on est
	près) -> l'extérieur du manoir reste sous son budget.

	API :
	  HouseStairs.BuildShell(kit, size) -> { Parts }
	  HouseStairs.BuildInterior(kit, size) -> { Ramps: { BasePart }, Parts, Lights }
	  HouseStairs.Build(kit, size, colors?) -> { Ramps, Holes, Parts }  (les deux)
	  HouseStairs.Palette(size) -> Palette (couleurs du hall par style)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)

local HouseStairs = {}

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local BRASS = Color3.fromRGB(214, 172, 96)
local CEILING = Color3.fromRGB(255, 250, 244)
local SKIN = WorldLayout.HALL_SKIN
local RAIL_H = 2.9 -- hauteur de la main courante au-dessus du nez des marches
local GUARD_H = 3.1 -- garde-corps des paliers

export type Palette = {
	Style: string,
	Floor1: Color3,
	Floor1Mat: Enum.Material,
	Tile2: Color3,
	Pattern: string, -- "Grid" | "Checker" | "Diamond" | "Joints"
	Upper: Color3,
	UpperMat: Enum.Material,
	Wall: Color3,
	WallMat: Enum.Material,
	Dado: Color3,
	DadoMat: Enum.Material,
	Trim: Color3,
	Tread: Color3,
	TreadMat: Enum.Material,
	Riser: Color3,
	Runner: Color3?,
	Rail: Color3,
	RailMat: Enum.Material,
	Baluster: Color3,
	BalusterMat: Enum.Material,
	Stringer: Color3,
	StringerMat: Enum.Material,
	Newel: Color3,
	Accent: Color3,
	Open: boolean, -- escalier industriel (contremarches ouvertes, lisses)
}

local PALETTES: { [string]: Palette } = {
	Cottage = {
		Style = "Cottage",
		Floor1 = Color3.fromRGB(204, 124, 92),
		Floor1Mat = M.Slate,
		Tile2 = Color3.fromRGB(246, 232, 214),
		Pattern = "Grid",
		Upper = Color3.fromRGB(206, 158, 114),
		UpperMat = M.WoodPlanks,
		Wall = Color3.fromRGB(255, 246, 232),
		WallMat = M.Plaster,
		Dado = Color3.fromRGB(184, 202, 168),
		DadoMat = M.Wood,
		Trim = Color3.fromRGB(252, 246, 236),
		Tread = Color3.fromRGB(188, 132, 88),
		TreadMat = M.Wood,
		Riser = Color3.fromRGB(252, 246, 236),
		Runner = Color3.fromRGB(206, 118, 132),
		Rail = Color3.fromRGB(160, 106, 70),
		RailMat = M.Wood,
		Baluster = Color3.fromRGB(252, 246, 236),
		BalusterMat = M.SmoothPlastic,
		Stringer = Color3.fromRGB(252, 246, 236),
		StringerMat = M.Wood,
		Newel = Color3.fromRGB(160, 106, 70),
		Accent = BRASS,
		Open = false,
	},
	Townhouse = {
		Style = "Townhouse",
		Floor1 = Color3.fromRGB(242, 240, 236),
		Floor1Mat = M.Marble,
		Tile2 = Color3.fromRGB(44, 42, 50),
		Pattern = "Checker",
		Upper = Color3.fromRGB(168, 116, 80),
		UpperMat = M.WoodPlanks,
		Wall = Color3.fromRGB(226, 238, 230),
		WallMat = M.Plaster,
		Dado = Color3.fromRGB(250, 248, 244),
		DadoMat = M.Wood,
		Trim = Color3.fromRGB(250, 248, 244),
		Tread = Color3.fromRGB(112, 74, 54),
		TreadMat = M.Wood,
		Riser = Color3.fromRGB(250, 248, 244),
		Runner = Color3.fromRGB(46, 60, 108),
		Rail = Color3.fromRGB(96, 60, 44),
		RailMat = M.Wood,
		Baluster = Color3.fromRGB(250, 248, 244),
		BalusterMat = M.SmoothPlastic,
		Stringer = Color3.fromRGB(250, 248, 244),
		StringerMat = M.Wood,
		Newel = Color3.fromRGB(96, 60, 44),
		Accent = BRASS,
		Open = false,
	},
	Loft = {
		Style = "Loft",
		Floor1 = Color3.fromRGB(170, 170, 176),
		Floor1Mat = M.Concrete,
		Tile2 = Color3.fromRGB(120, 120, 128),
		Pattern = "Joints",
		Upper = Color3.fromRGB(186, 140, 98),
		UpperMat = M.WoodPlanks,
		Wall = Color3.fromRGB(184, 104, 88),
		WallMat = M.Brick,
		Dado = Color3.fromRGB(58, 58, 66),
		DadoMat = M.Metal,
		Trim = Color3.fromRGB(46, 46, 54),
		Tread = Color3.fromRGB(198, 150, 104),
		TreadMat = M.Wood,
		Riser = Color3.fromRGB(46, 46, 54),
		Runner = nil,
		Rail = Color3.fromRGB(40, 40, 46),
		RailMat = M.Metal,
		Baluster = Color3.fromRGB(52, 52, 60),
		BalusterMat = M.Metal,
		Stringer = Color3.fromRGB(40, 40, 46),
		StringerMat = M.Metal,
		Newel = Color3.fromRGB(40, 40, 46),
		Accent = Color3.fromRGB(190, 190, 198),
		Open = true,
	},
	Mansion = {
		Style = "Mansion",
		Floor1 = Color3.fromRGB(244, 240, 238),
		Floor1Mat = M.Marble,
		Tile2 = Color3.fromRGB(150, 140, 156),
		Pattern = "Diamond",
		Upper = Color3.fromRGB(178, 118, 80),
		UpperMat = M.WoodPlanks,
		Wall = Color3.fromRGB(255, 236, 240),
		WallMat = M.Plaster,
		Dado = Color3.fromRGB(252, 248, 246),
		DadoMat = M.Wood,
		Trim = Color3.fromRGB(252, 248, 246),
		Tread = Color3.fromRGB(240, 232, 226),
		TreadMat = M.Marble,
		Riser = Color3.fromRGB(252, 248, 246),
		Runner = Color3.fromRGB(176, 38, 74),
		Rail = Color3.fromRGB(112, 50, 42),
		RailMat = M.Wood,
		Baluster = Color3.fromRGB(250, 246, 242),
		BalusterMat = M.Limestone,
		Stringer = Color3.fromRGB(250, 246, 242),
		StringerMat = M.Limestone,
		Newel = Color3.fromRGB(250, 246, 242),
		Accent = Color3.fromRGB(236, 190, 90),
		Open = false,
	},
}

function HouseStairs.Palette(size: any): Palette
	return PALETTES[WorldLayout.StyleOf(size)] or PALETTES.Cottage
end

export type Colors = { Wall: Color3, Trim: Color3, Accent: Color3 }
export type Result = { Ramps: { BasePart }, Holes: { { number } }, Parts: number }
export type InteriorResult = { Ramps: { BasePart }, Parts: number, Lights: number }

local function floorName(floor: number): string
	if floor <= 1 then
		return Locale.T("Ground floor")
	end
	return Locale.T("Floor %s", tostring(floor - 1))
end

-- Géométrie d'une volée (repère local de la maison ; y relatif au sol de l'étage)
type Run = {
	S0: number, -- limon côté couloir (x)
	S1: number, -- face intérieure du mur de droite (x)
	D0: number, -- 1re contremarche (d)
	D1: number, -- dernière contremarche = arrivée (d)
	G: number, -- giron
	R: number, -- hauteur de marche
	N: number, -- contremarches
	Cos: number, -- cosinus de la pente
	Hole0: number, -- début de la trémie du dessus (d)
}

local function runOf(size: any): Run
	local s0, s1 = WorldLayout.StairSpan(size)
	local d0, d1, g, r = WorldLayout.StairRun(size)
	local h0 = WorldLayout.StairHole(size)
	return { S0 = s0, S1 = s1, D0 = d0, D1 = d1, G = g, R = r, N = WorldLayout.STAIR_RISERS, Cos = g / math.sqrt(g * g + r * r), Hole0 = h0 }
end

-- ligne des nez de marche (hauteur au-dessus du sol de l'étage)
local function nosing(run: Run, d: number): number
	return run.R + (d - run.D0) * run.R / run.G
end

----------------------------------------------------------------------
-- COQUE (toujours construite) : sols, trémies, murs, plafond
----------------------------------------------------------------------

-- Motif du dallage du rez-de-chaussée (SurfaceGui sur le dessus : aucune pièce)
local function floorPattern(part: BasePart, w: number, dLen: number, pal: Palette)
	local pps = 16
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Tiles"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 1
	gui.MaxDistance = 90
	gui.Parent = part
	local W, H = w * pps, dLen * pps
	local function rect(x: number, y: number, rw: number, rh: number, color: Color3, transparency: number, rotation: number?)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(rw, rh)
		f.Rotation = rotation or 0
		f.Parent = gui
	end
	local pattern = pal.Pattern
	if pattern == "Checker" then
		-- damier noir et blanc (carreaux de 2 studs) + joints fins
		local t = 2 * pps
		local nx, ny = math.ceil(W / t), math.ceil(H / t)
		for i = 0, nx - 1 do
			for j = 0, ny - 1 do
				if (i + j) % 2 == 1 then
					local cw = math.min(t, W - i * t)
					local ch = math.min(t, H - j * t)
					rect(i * t + cw / 2, j * t + ch / 2, cw, ch, pal.Tile2, 0)
				end
			end
		end
	elseif pattern == "Diamond" then
		-- marbre blanc, joints gris clair, cabochons gris aux croisements (3 studs)
		local t = 3 * pps
		for i = 1, math.floor(W / t) do
			rect(i * t, H / 2, 2, H, pal.Tile2, 0.55)
		end
		for j = 1, math.floor(H / t) do
			rect(W / 2, j * t, W, 2, pal.Tile2, 0.55)
		end
		for i = 0, math.floor(W / t) do
			for j = 0, math.floor(H / t) do
				rect(i * t, j * t, 14, 14, pal.Tile2, 0, 45)
			end
		end
	elseif pattern == "Joints" then
		-- béton ciré : joints sciés tous les 4 studs
		local t = 4 * pps
		for i = 1, math.floor(W / t) do
			rect(i * t, H / 2, 2, H, pal.Tile2, 0.35)
		end
		for j = 1, math.floor(H / t) do
			rect(W / 2, j * t, W, 2, pal.Tile2, 0.35)
		end
	else
		-- tomettes : carreaux de 1,5 stud, joints crème
		local t = 1.5 * pps
		for i = 1, math.floor(W / t) do
			rect(i * t, H / 2, 3, H, pal.Tile2, 0.1)
		end
		for j = 1, math.floor(H / t) do
			rect(W / 2, j * t, W, 3, pal.Tile2, 0.1)
		end
	end
end

-- Plancher de l'étage `floor` dans la cage (trémie si une volée y arrive)
local function shellFloor(kit: any, size: any, floor: number, pal: Palette)
	local h0, h1 = WorldLayout.HallSpan(size)
	local run = runOf(size)
	local y = WorldLayout.FloorY(floor)
	local T = WorldLayout.WALL_T
	local dFront, dBack = T, T + WorldLayout.DEPTH
	if floor == 1 then
		-- soubassement plein + dallage (jusque sous la porte)
		-- (v9.6 z-fighting : commence DERRIÈRE la façade (d = T))
		kit:Box("HallBase", h0, h1, 0, y - 0.2, dFront + 0.05, dBack - 0.05, Color3.fromRGB(226, 214, 222), M.Concrete, { Solid = true, Shadow = false })
		local tiles = kit:Box("HallTiles", h0, h1, y - 0.2, y, dFront, dBack, pal.Floor1, pal.Floor1Mat, { Solid = true, Shadow = false })
		floorPattern(tiles, h1 - h0, dBack - dFront, pal)
		return
	end
	-- morceaux autour de la trémie : couloir (toute la profondeur), bande de
	-- l'escalier devant la trémie et derrière l'arrivée
	local pieces = {
		{ h0, run.S0, dFront, dBack },
		{ run.S0, h1, dFront, run.Hole0 },
		{ run.S0, h1, run.D1 + 0.12, dBack },
	}
	for _, r in ipairs(pieces) do
		kit:Box("HallSlab", r[1], r[2], y - WorldLayout.SLAB, y - 0.2, r[3], r[4], CEILING, M.SmoothPlastic, { Solid = true, Shadow = false })
		kit:Box("HallFloor", r[1], r[2], y - 0.2, y, r[3], r[4], pal.Upper, pal.UpperMat, { Solid = true, Shadow = false })
	end
	-- bandeau du mur le long de la trémie (entre les peaux de deux étages : on
	-- voyait le plancher de la pièce voisine par la fente)
	kit:Box("HoleFascia", h1 - SKIN, h1, y - WorldLayout.SLAB, y, run.Hole0, run.D1 + 0.12, pal.Wall, pal.WallMat, { Shadow = false })
end

-- Murs intérieurs de la cage (peau : enduit + lambris), passages vers les pièces
local function shellWalls(kit: any, size: any, floor: number, pal: Palette)
	local h0, h1 = WorldLayout.HallSpan(size)
	local y = WorldLayout.FloorY(floor)
	local T, D = WorldLayout.WALL_T, WorldLayout.DEPTH
	local dFront, dBack = T, T + D
	local passages = WorldLayout.HallPassages(size)
	for _, side in ipairs({ "Left", "Right" }) do
		local face = if side == "Left" then h0 else h1
		local x0, x1 = if side == "Left" then face else face - SKIN, if side == "Left" then face + SKIN else face
		local span = passages[side]
		local holes = if span then { { span[1], span[2], y, y + WorldLayout.PASS_H } } else {}
		if side == "Right" or pal.Open then
			-- mur de l'escalier (ou loft) : enduit / briques sur toute la hauteur
			kit:WallD("HallWall", x0, x1, y, y + WorldLayout.WALL_H, dFront, dBack, holes, pal.Wall, pal.WallMat, { Solid = false, Shadow = false })
		else
			kit:WallD("HallWall", x0, x1, y + 3.4, y + WorldLayout.WALL_H, dFront, dBack, holes, pal.Wall, pal.WallMat, { Solid = false, Shadow = false })
			kit:WallD("HallDado", x0, x1, y, y + 3.4, dFront, dBack, holes, pal.Dado, pal.DadoMat, { Solid = false, Shadow = false })
		end
	end
end

function HouseStairs.BuildShell(kit: any, size: any): { Parts: number }
	local dims = WorldLayout.Dims(size)
	local pal = HouseStairs.Palette(size)
	local before = kit.Stats.Count
	for floor = 1, dims.Floors do
		shellFloor(kit, size, floor, pal)
		shellWalls(kit, size, floor, pal)
	end
	-- Plafond du dernier étage
	-- (v9.6 / v9.7 z-fighting : descend de 0,1 sous la dalle de toit de la
	-- façade, s'arrête contre la face intérieure des murs du hall)
	local h0, h1 = WorldLayout.HallSpan(size)
	local top = WorldLayout.FloorY(dims.Floors) + WorldLayout.WALL_H
	kit:Box("HallCeiling", h0 + SKIN, h1 - SKIN, top - 0.1, top + 0.5, WorldLayout.WALL_T, WorldLayout.WALL_T + WorldLayout.DEPTH, CEILING, M.SmoothPlastic,
		{ Solid = true, Shadow = false })
	return { Parts = kit.Stats.Count - before }
end

----------------------------------------------------------------------
-- INTÉRIEUR (en flux) : escalier, garde-corps, moulures, meubles, lampes
----------------------------------------------------------------------

-- Une volée : de l'étage `floor` à l'étage `floor + 1`
local function flight(kit: any, size: any, floor: number, pal: Palette, ramps: { BasePart })
	local run = runOf(size)
	local y0 = WorldLayout.FloorY(floor)
	local S0, S1, D0, D1, G, R, N = run.S0, run.S1, run.D0, run.D1, run.G, run.R, run.N
	local STORY = WorldLayout.STORY
	local function nose(d: number): number
		return y0 + nosing(run, d)
	end
	local stringIn = S0 + 0.3 -- face intérieure du limon côté couloir
	local wallIn = S1 - 0.2 -- face du limon de mur
	local open = pal.Open

	-- 1. Rampe de collision (invisible) : ligne du MILIEU des marches (parallèle
	-- aux nez, = WorldLayout.StairHeight), de (D0 - G/2, sol) au milieu de la
	-- dernière marche, prolongée sous le sol ; puis un bout plus raide qui
	-- rejoint le palier AU RAS à l'arrivée (D1), et un petit plat jusqu'au plancher
	local slope = R / G
	local rx0, rx1 = stringIn + 0.05, wallIn - 0.05
	local extra = 0.8
	local knee = D1 - G / 2
	local rampPart = kit:Slab("StairRamp", (rx0 + rx1) / 2, { y0 - extra * slope, D0 - G / 2 - extra }, { y0 + STORY - R, knee }, rx1 - rx0, 1, WHITE,
		M.SmoothPlastic, { Solid = true, Query = true, T = 1, Shadow = false })
	rampPart:SetAttribute("StairFloor", floor)
	table.insert(ramps, rampPart)
	local rampEnd = kit:Slab("StairRamp", (rx0 + rx1) / 2, { y0 + STORY - R, knee }, { y0 + STORY, D1 }, rx1 - rx0, 0.6, WHITE, M.SmoothPlastic,
		{ Solid = true, Query = true, T = 1, Shadow = false })
	table.insert(ramps, rampEnd)
	local flat = kit:Box("StairRampTop", rx0, rx1, y0 + STORY - 0.6, y0 + STORY, D1, D1 + 0.12, WHITE, M.SmoothPlastic,
		{ Solid = true, Query = true, T = 1, Shadow = false })
	table.insert(ramps, flat)
	-- garde invisible côté vide (on ne tombe pas du côté du couloir) :
	-- de 1,5 sous les nez à la hauteur de la main courante
	-- (boîtes verticales de 2 studs : rien ne dépasse sur le palier d'arrivée)
	local g0 = D0 - 0.4
	while g0 < D1 - 0.05 do
		local g1 = math.min(g0 + 2, D1)
		kit:Box("StairGuard", S0, S0 + 0.3, nose(g0) - 1.2, nose(g1) + RAIL_H + 0.2, g0, g1, WHITE, M.SmoothPlastic, { Solid = true, Query = false, T = 1, Shadow = false })
		g0 = g1
	end

	-- 2. Marches visibles (décor, sans collision)
	local tx0, tx1 = stringIn - 0.05, wallIn + 0.05 -- (les bouts entrent dans les limons : aucune face commune)
	local rx = (tx0 + tx1) / 2
	local runnerW = math.min(2.6, (tx1 - tx0) - 1.1)
	local treadT = if open then 0.3 else 0.2
	for i = 1, N do
		local d = D0 + (i - 1) * G
		local top = y0 + i * R
		if not open then
			-- contremarche (posée sur le giron du dessous)
			kit:Box("Riser", tx0, tx1, top - R, top - treadT, d, d + 0.12, pal.Riser, M.SmoothPlastic, { Shadow = false })
			if pal.Runner then
				-- tapis sur la contremarche (devant elle)
				kit:Box("RunnerRiser", rx - runnerW / 2, rx + runnerW / 2, top - R + (if i > 1 then 0.05 else 0), top - treadT, d - 0.05, d, pal.Runner, M.Fabric,
					{ Shadow = false })
			end
		end
		if i < N then
			-- giron : nez de 0,1 devant la contremarche, jusque sous la suivante
			kit:Box("Tread", tx0, tx1, top - treadT, top, d - (if open then 0.05 else 0.1), d + G + (if open then -0.05 else 0.12), pal.Tread, pal.TreadMat,
				{ Shadow = false })
			if pal.Runner then
				kit:Box("Runner", rx - runnerW / 2, rx + runnerW / 2, top, top + 0.05, d - 0.05, d + G, pal.Runner, M.Fabric, { Shadow = false })
			end
		else
			-- nez du palier d'arrivée (le plancher du palier commence à D1 + 0,12)
			kit:Box("Nosing", tx0, tx1, top - treadT, top, d - 0.1, d + 0.12, pal.Tread, pal.TreadMat, { Shadow = false })
		end
	end

	-- 3. Limons + sous-face
	-- limon côté couloir : 0,3 d'épaisseur, 0,35 au-dessus des nez, 1,4 de haut
	local sTop0, sTop1 = nose(D0 - 0.5) + 0.35, y0 + STORY + 0.35
	kit:Slab("Stringer", S0 + 0.15, { sTop0, D0 - 0.5 }, { sTop1, D1 + 0.12 }, 0.3, 1.4 * run.Cos, pal.Stringer, pal.StringerMat, { Shadow = true })
	-- limon de mur (plinthe rampante)
	kit:Slab("WallStringer", S1 - 0.1, { nose(D0 - 0.5) + 0.45, D0 - 0.5 }, { y0 + STORY + 0.45, D1 + 0.12 }, 0.2, 1.2 * run.Cos, pal.Stringer, pal.StringerMat,
		{ Shadow = false })
	if not open then
		-- sous-face (plâtre) : sous les coins des marches (ligne des nez - R)
		kit:Slab("Soffit", (stringIn + wallIn) / 2, { nose(D0) - R - 0.08, D0 }, { y0 + STORY - R - 0.08, D1 + 0.12 }, wallIn - stringIn, 0.3, CEILING,
			M.SmoothPlastic, { Shadow = false })
	end

	-- 4. Garde-corps côté couloir : main courante, balustres (2 par marche),
	-- poteau de départ (boule) et d'arrivée
	local railX = S0 + 0.15
	local rail0, rail1 = D0 - 0.3, D1 - 0.2
	kit:Slab("Handrail", railX, { nose(rail0) + RAIL_H + 0.12, rail0 }, { nose(rail1) + RAIL_H + 0.12, rail1 }, 0.34, 0.24 * run.Cos, pal.Rail, pal.RailMat,
		{ Shadow = false })
	if open then
		-- loft : 3 lisses d'acier parallèles à la main courante + un montant toutes les 3 marches
		for k = 1, 3 do
			local h = RAIL_H * k / 4 + 0.2
			kit:Slab("RailBar", railX, { nose(rail0) + h, rail0 }, { nose(rail1) + h, rail1 }, 0.1, 0.1, pal.Baluster, pal.BalusterMat, { Shadow = false })
		end
		for i = 2, N - 1, 3 do
			local d = D0 + (i - 0.5) * G
			local base = nose(d) + 0.35
			kit:Box("RailPost", railX - 0.07, railX + 0.07, base, nose(d) + RAIL_H, d - 0.07, d + 0.07, pal.Baluster, pal.BalusterMat, { Shadow = false })
		end
	else
		for i = 1, N - 1 do
			for _, f in ipairs({ 0.25, 0.75 }) do
				local d = D0 + (i - 1 + f) * G
				local base = nose(d) + 0.35
				local top = nose(d) + RAIL_H
				if pal.Style == "Mansion" then
					kit:CylY("Baluster", railX, base, d, 0.2, top - base, pal.Baluster, pal.BalusterMat, { Shadow = false })
				else
					kit:Box("Baluster", railX - 0.075, railX + 0.075, base, top, d - 0.075, d + 0.075, pal.Baluster, pal.BalusterMat, { Shadow = false })
				end
			end
		end
	end
	-- poteau de départ (sur le sol, devant la 1re marche) : fût + chapeau + boule
	local nd0, nd1 = D0 - 0.62, D0 - 0.08
	kit:Box("Newel", railX - 0.27, railX + 0.27, y0, y0 + RAIL_H + 0.9, nd0, nd1, pal.Newel, pal.RailMat, { Solid = true, Shadow = false })
	kit:Box("NewelCap", railX - 0.34, railX + 0.34, y0 + RAIL_H + 0.9, y0 + RAIL_H + 1.05, nd0 - 0.07, nd1 + 0.07, pal.Rail, pal.RailMat, { Shadow = false })
	kit:Ball("NewelBall", railX, y0 + RAIL_H + 1.28, (nd0 + nd1) / 2, 0.46, pal.Accent, M.Metal, { Shadow = false })
	-- poteau d'arrivée (sur le palier du dessus, côté couloir)
	local ay = y0 + STORY
	kit:Box("NewelTop", railX - 0.25, railX + 0.25, ay - 0.9, ay + GUARD_H + 0.35, D1 - 0.2, D1 + 0.3, pal.Newel, pal.RailMat, { Solid = true, Shadow = false })
	kit:Box("NewelTopCap", railX - 0.32, railX + 0.32, ay + GUARD_H + 0.35, ay + GUARD_H + 0.5, D1 - 0.27, D1 + 0.37, pal.Rail, pal.RailMat, { Shadow = false })
	-- main courante murale sur 3 consoles (laiton), côté mur
	local wx = S1 - 0.42
	kit:Slab("WallRail", wx, { nose(D0 + 0.6) + RAIL_H, D0 + 0.6 }, { nose(D1 - 0.8) + RAIL_H, D1 - 0.8 }, 0.18, 0.16 * run.Cos, pal.Rail, pal.RailMat, { Shadow = false })
	for _, f in ipairs({ 0.12, 0.5, 0.88 }) do
		local d = D0 + 0.6 + f * (D1 - 0.8 - D0 - 0.6)
		local y = nose(d) + RAIL_H - 0.28
		kit:Box("WallRailBracket", wx + 0.02, S1 - 0.02, y - 0.06, y + 0.06, d - 0.06, d + 0.06, pal.Accent, M.Metal, { Shadow = false })
	end
end

-- Garde-corps du palier de l'étage `floor` autour de la trémie (volée du dessous)
local function landingGuard(kit: any, size: any, floor: number, floors: number, pal: Palette)
	local run = runOf(size)
	local y = WorldLayout.FloorY(floor)
	local x = run.S0 + 0.15
	local a, b = run.Hole0, run.D1 - 0.2
	local above = floor < floors -- une volée monte au-dessus de la trémie
	-- limon de la volée du dessus (repère de cet étage) : dessous à nez - 1,05
	local function limit(d: number): number
		if not above then
			return GUARD_H
		end
		return math.min(GUARD_H, nosing(run, d) + 0.35 - 1.4 - 0.08)
	end
	-- lisse basse (sur le plancher) + collision invisible
	kit:Box("GuardBase", x - 0.13, x + 0.13, y - 0.03, y + 0.22, a, b, pal.Trim, M.Wood, { Solid = true, Shadow = false })
	kit:Box("GuardWall", x - 0.15, x + 0.15, y, y + GUARD_H + 0.2, a, b, WHITE, M.SmoothPlastic, { Solid = true, Query = false, T = 1, Shadow = false })
	-- main courante là où elle passe sous le limon du dessus
	local railStart = a
	if above then
		railStart = run.D0 + (GUARD_H + 0.3 - run.R - 0.35 + 1.4) / run.R * run.G
	end
	if b - railStart > 0.5 then
		kit:Box("GuardRail", x - 0.17, x + 0.17, y + GUARD_H, y + GUARD_H + 0.24, railStart, b, pal.Rail, pal.RailMat, { Solid = true, Shadow = false })
	end
	local count = math.max(2, math.floor((b - a) / 0.75))
	for i = 0, count do
		local d = a + 0.2 + i * (b - a - 0.4) / count
		local top = limit(d)
		if top > 0.6 then
			if pal.Open then
				if i % 3 == 0 then
					kit:Box("GuardBaluster", x - 0.06, x + 0.06, y + 0.22, y + top, d - 0.06, d + 0.06, pal.Baluster, pal.BalusterMat, { Shadow = false })
				end
			elseif pal.Style == "Mansion" then
				kit:CylY("GuardBaluster", x, y + 0.22, d, 0.2, top - 0.22, pal.Baluster, pal.BalusterMat, { Shadow = false })
			else
				kit:Box("GuardBaluster", x - 0.075, x + 0.075, y + 0.22, y + top, d - 0.075, d + 0.075, pal.Baluster, pal.BalusterMat, { Shadow = false })
			end
		end
	end
	if pal.Open and b - railStart > 0.5 then
		for k = 1, 2 do
			local h = GUARD_H * k / 3
			kit:Box("GuardBar", x - 0.05, x + 0.05, y + h - 0.05, y + h + 0.05, math.max(railStart, a), b, pal.Baluster, pal.BalusterMat, { Shadow = false })
		end
	end
	-- poteau au bout de la trémie
	kit:Box("GuardPost", x - 0.25, x + 0.25, y, y + GUARD_H + 0.45, a - 0.25, a + 0.25, pal.Newel, pal.RailMat, { Solid = true, Shadow = false })
	if not above then
		-- dernier étage : garde-corps en travers, au bout de la trémie
		kit:Box("GuardRail", run.S0 + 0.3, run.S1, y + GUARD_H, y + GUARD_H + 0.24, a - 0.17, a + 0.17, pal.Rail, pal.RailMat, { Solid = true, Shadow = false })
		kit:Box("GuardBase", run.S0 + 0.3, run.S1, y - 0.03, y + 0.22, a - 0.12, a + 0.12, pal.Trim, M.Wood, { Solid = true, Shadow = false })
		for i = 1, 4 do
			local bx = run.S0 + 0.3 + i * (run.S1 - run.S0 - 0.3) / 5
			kit:Box("GuardBaluster", bx - 0.075, bx + 0.075, y + 0.22, y + GUARD_H, a - 0.075, a + 0.075, pal.Baluster, pal.BalusterMat, { Shadow = false })
		end
	end
end

-- Moulures de l'étage : cimaise + plinthes (mur de gauche), chambranles des passages
local function trims(kit: any, size: any, floor: number, pal: Palette)
	local h0, h1 = WorldLayout.HallSpan(size)
	local y = WorldLayout.FloorY(floor)
	local T, D = WorldLayout.WALL_T, WorldLayout.DEPTH
	local dFront, dBack = T, T + D
	local passages = WorldLayout.HallPassages(size)
	local run = runOf(size)
	for _, side in ipairs({ "Left", "Right" }) do
		local sx = if side == "Left" then 1 else -1
		local face = if side == "Left" then h0 + SKIN else h1 - SKIN
		local r0, r1 = math.min(face + sx * 0.03, face + sx * 0.28), math.max(face + sx * 0.03, face + sx * 0.28)
		local span = passages[side]
		local holes = if span then { { span[1], span[2], y, y + WorldLayout.PASS_H } } else {}
		if side == "Left" then
			if not pal.Open then
				kit:WallD("ChairRail", r0, r1, y + 3.3, y + 3.55, dFront, dBack, holes, pal.Trim, M.Wood, { Shadow = false })
			end
			kit:WallD("Skirting", r0, r1, y, y + 0.6, dFront, dBack, holes, pal.Trim, M.Wood, { Shadow = false })
		else
			-- mur de l'escalier : plinthe seulement devant la volée et après l'arrivée
			local pieces = { { dFront, run.D0 - 0.6 } }
			if span then
				table.insert(pieces, { run.D1 + 0.2, span[1] - 0.45 })
				table.insert(pieces, { span[2] + 0.45, dBack })
			else
				table.insert(pieces, { run.D1 + 0.2, dBack })
			end
			for _, piece in ipairs(pieces) do
				if piece[2] - piece[1] > 0.3 then
					kit:Box("Skirting", r0, r1, y, y + 0.6, piece[1], piece[2], pal.Trim, M.Wood, { Shadow = false })
				end
			end
		end
		if span then
			-- chambranle du passage (déborde de 0,04 dans l'ouverture)
			kit:Box("PassFrame", r0, r1, y, y + WorldLayout.PASS_H + 0.3, span[1] - 0.4, span[1] + 0.04, pal.Trim, M.Wood, { Shadow = false })
			kit:Box("PassFrame", r0, r1, y, y + WorldLayout.PASS_H + 0.3, span[2] - 0.04, span[2] + 0.4, pal.Trim, M.Wood, { Shadow = false })
			kit:Box("PassFrame", r0, r1, y + WorldLayout.PASS_H - 0.04, y + WorldLayout.PASS_H + 0.45, span[1] - 0.4, span[2] + 0.4, pal.Trim, M.Wood,
				{ Shadow = false })
		end
	end
end

-- Petite plaque GRAVÉE (laiton sur bois) : nom de l'étage + flèches
local function plaque(kit: any, size: any, floor: number, wall: number, p0: number, p1: number)
	local y = WorldLayout.FloorY(floor)
	kit:Box("FloorPlaqueBoard", wall, wall + 0.14, y + 4.35, y + 5.95, p0, p1, Color3.fromRGB(120, 78, 58), M.Wood, { Shadow = false })
	local plate = kit:Box("FloorPlaque", wall + 0.14, wall + 0.2, y + 4.5, y + 5.8, p0 + 0.15, p1 - 0.15, Color3.fromRGB(226, 184, 96), M.Metal, { Shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Engraving"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.MaxDistance = 60
	gui.Parent = plate
	local ink = Color3.fromRGB(78, 50, 32)
	local function line(text: string, y0: number, h: number, font: Enum.Font)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.9, h)
		label.Position = UDim2.fromScale(0.05, y0)
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = ink
		label.TextStrokeColor3 = Color3.fromRGB(255, 236, 190)
		label.TextStrokeTransparency = 0.55
		label.Text = text
		label.Parent = gui
	end
	line(floorName(floor), 0.1, 0.5, Enum.Font.Garamond)
	local hints = {}
	if floor > 1 then
		table.insert(hints, "⬇️ " .. floorName(floor - 1))
	end
	if floor < WorldLayout.Dims(size).Floors then
		table.insert(hints, "⬆️ " .. floorName(floor + 1))
	end
	if #hints > 0 then
		line(table.concat(hints, "   "), 0.62, 0.28, Enum.Font.GothamMedium)
	end
	for _, d in ipairs({ p0 + 0.08, p1 - 0.08 }) do
		kit:Ball("PlaqueScrew", wall + 0.17, y + 5.15, d, 0.12, Color3.fromRGB(246, 196, 84), M.Metal, { Shadow = false })
	end
end

-- Tableau encadré (mur de gauche) : toile peinte (dégradé ciel / collines)
local function painting(kit: any, wall: number, y0: number, y1: number, d0: number, d1: number, frame: Color3, seed: number)
	kit:Box("PictureFrame", wall, wall + 0.16, y0, y1, d0, d1, frame, M.Wood, { Shadow = false })
	local canvas = kit:Box("PictureCanvas", wall + 0.16, wall + 0.2, y0 + 0.3, y1 - 0.3, d0 + 0.3, d1 - 0.3, WHITE, M.SmoothPlastic, { Shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Art"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.MaxDistance = 70
	gui.Parent = canvas
	local skies = {
		{ Color3.fromRGB(255, 196, 170), Color3.fromRGB(150, 196, 240) },
		{ Color3.fromRGB(190, 220, 255), Color3.fromRGB(255, 226, 236) },
		{ Color3.fromRGB(255, 214, 150), Color3.fromRGB(222, 170, 220) },
	}
	local sky = skies[(seed - 1) % #skies + 1]
	local bg = Instance.new("Frame")
	bg.BorderSizePixel = 0
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = WHITE
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(sky[2], sky[1])
	grad.Rotation = 90
	grad.Parent = bg
	-- soleil + collines (cercles aplatis)
	local function blob(x: number, y: number, w: number, h: number, color: Color3)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	blob(0.72, 0.3, 0.16, 0.2, Color3.fromRGB(255, 244, 200))
	blob(0.25, 0.95, 0.9, 0.6, Color3.fromRGB(120, 176, 110))
	blob(0.8, 1.0, 0.9, 0.5, Color3.fromRGB(96, 150, 96))
end

-- Plante en pot haute (pot, terre, feuillage en boules)
local function plant(kit: any, x: number, y: number, d: number, pot: Color3)
	kit:CylY("PlantPot", x, y, d, 1.3, 1.8, pot, M.SmoothPlastic, { Solid = true, Shadow = false })
	kit:CylY("PlantPotRim", x, y + 1.8, d, 1.45, 0.2, pot:Lerp(WHITE, 0.15), M.SmoothPlastic, { Shadow = false })
	kit:CylY("PlantSoil", x, y + 1.72, d, 1.15, 0.2, Color3.fromRGB(96, 70, 52), M.Ground, { Shadow = false })
	kit:CylY("PlantStem", x, y + 1.8, d, 0.16, 2.2, Color3.fromRGB(110, 86, 60), M.Wood, { Shadow = false })
	local leaf = Color3.fromRGB(76, 150, 88)
	for k, spec in ipairs({ { 0, 4.3, 0, 1.9 }, { 0.55, 3.6, 0.3, 1.4 }, { -0.5, 3.4, -0.35, 1.3 }, { 0.2, 5.1, -0.2, 1.2 }, { -0.4, 4.6, 0.45, 1.1 } }) do
		kit:Ball("PlantLeaves", x + spec[1], y + spec[2], d + spec[3], spec[4], leaf:Lerp(Color3.fromRGB(40, 110, 60), (k % 3) * 0.2), M.Grass, { Shadow = false })
	end
end

-- Placard sous la première volée (panneau en pente + petite porte + bout)
local function underStair(kit: any, size: any, pal: Palette)
	local run = runOf(size)
	local y0 = WorldLayout.FloorY(1)
	local x = run.S0 + 0.16
	-- dessous du limon (repère du sol) = nez + 0,35 - 1,4
	local function under(d: number): number
		return nosing(run, d) + 0.35 - 1.4
	end
	local dA = run.D0 + (1.05 - 0.35 + 0.3 - run.R) / run.R * run.G -- là où le dessous du limon est à 0,3
	local dB = run.D0 + (7.2 + 1.05 - run.R) / run.R * run.G -- là où il est à 7,2
	dB = math.min(dB, run.D1 - 3)
	local hA, hB = under(dA), under(dB)
	local panel = if pal.Style == "Mansion" then pal.Trim else pal.Dado
	-- partie rectangulaire (sous hA) + triangle (WedgePart : haut vers le fond)
	kit:Box("UnderStairLow", x - 0.12, x + 0.12, y0, y0 + hA, dA, dB, panel, M.Wood, { Solid = true, Shadow = false })
	local length = dB - dA
	local height = hB - hA
	local center = CFrame.new(x, y0 + hA + height / 2, -(dA + length / 2)) * CFrame.Angles(0, math.pi, 0)
	kit:Part("UnderStair", Vector3.new(0.24, height, length), center, panel, M.Wood, { Solid = true }, "WedgePart")
	-- bout du placard (côté fond), du sol au dessous du limon
	kit:Box("UnderStairEnd", x - 0.12, run.S1 - 0.02, y0, y0 + hB, dB, dB + 0.24, panel, M.Wood, { Solid = true, Shadow = false })
	-- petite porte (décor) + poignée + chambranle
	local door0, door1 = dB - 3.3, dB - 0.7
	local doorTop = math.min(y0 + 5.6, y0 + under(door0) - 0.25)
	kit:Box("ClosetDoor", x - 0.18, x - 0.12, y0 + 0.1, doorTop, door0, door1, panel:Lerp(pal.Trim, 0.5), M.Wood, { Shadow = false })
	kit:Box("ClosetFrame", x - 0.2, x - 0.12, doorTop, doorTop + 0.2, door0 - 0.15, door1 + 0.15, pal.Trim, M.Wood, { Shadow = false })
	kit:Ball("ClosetKnob", x - 0.26, y0 + 2.9, door0 + 0.35, 0.22, pal.Accent, M.Metal, { Shadow = false })
end

-- Hall d'entrée meublé (rez-de-chaussée)
local function foyer(kit: any, size: any, pal: Palette)
	local run = runOf(size)
	local y = WorldLayout.FloorY(1)
	local T = WorldLayout.WALL_T
	local c0, c1 = WorldLayout.CorridorSpan(size)
	local _, h1 = WorldLayout.HallSpan(size)
	local dBack = T + WorldLayout.DEPTH
	local passages = WorldLayout.HallPassages(size)
	local left = passages.Left
	local pass0 = if left then left[1] else dBack
	local wood = if pal.Style == "Loft" then Color3.fromRGB(60, 60, 68) else Color3.fromRGB(128, 84, 58)
	local woodMat = if pal.Style == "Loft" then M.Metal else M.Wood
	local mansion = pal.Style == "Mansion"

	-- paillasson intérieur + tapis de couloir (bordure + centre)
	local door = WorldLayout.DoorX(size)
	kit:Box("DoorMat", door - 2, door + 2, y, y + 0.05, T + 0.4, T + 2, Color3.fromRGB(150, 112, 78), M.Fabric, { Shadow = false })
	local rug = if pal.Runner then pal.Runner else Color3.fromRGB(150, 120, 96)
	local rx0, rx1 = c0 + 2, c1 - 1.1
	kit:Box("HallRugBorder", rx0, rx1, y, y + 0.05, T + 3.2, dBack - 2.8, rug:Lerp(BLACK, 0.25), M.Fabric, { Shadow = false })
	kit:Box("HallRug", rx0 + 0.4, rx1 - 0.4, y + 0.05, y + 0.08, T + 3.6, dBack - 3.2, rug:Lerp(Color3.fromRGB(250, 236, 220), 0.35), M.Fabric, { Shadow = false })
	-- paillasson de la porte de derrière
	local backX = WorldLayout.BackDoorX(size)
	kit:Box("BackDoorMat", backX - 2, backX + 2, y, y + 0.05, dBack - 1.9, dBack - 0.2, Color3.fromRGB(150, 112, 78), M.Fabric, { Shadow = false })

	if mansion then
		-- grand vestibule : guéridon rond + grand bouquet, au milieu du couloir
		local gx, gd = (c0 + c1) / 2, T + 5.2
		kit:CylY("FoyerTableBase", gx, y + 0.08, gd, 1.4, 0.2, pal.Accent, M.Metal, { Solid = true, Shadow = false })
		kit:CylY("FoyerTableLeg", gx, y + 0.28, gd, 0.45, 2.22, Color3.fromRGB(112, 50, 42), M.Wood, { Solid = true, Shadow = false })
		kit:CylY("FoyerTableTop", gx, y + 2.5, gd, 2.4, 0.22, Color3.fromRGB(240, 234, 232), M.Marble, { Solid = true, Shadow = true })
		kit:CylY("FoyerVase", gx, y + 2.72, gd, 0.8, 1.3, Color3.fromRGB(246, 244, 250), M.Glass, { Shadow = false })
		local blooms = { Color3.fromRGB(255, 150, 190), WHITE, Color3.fromRGB(255, 214, 120), Color3.fromRGB(236, 72, 140), Color3.fromRGB(200, 170, 250) }
		for k = 0, 6 do
			local a = k / 7 * math.pi * 2
			local r = if k == 0 then 0 else 0.55
			kit:Ball("FoyerBloom", gx + math.cos(a) * r, y + 4.35 + (k % 2) * 0.25 - (if k == 0 then -0.3 else 0), gd + math.sin(a) * r, 0.62,
				blooms[k % #blooms + 1], M.SmoothPlastic, { Shadow = false })
		end
		kit:Ball("FoyerLeaves", gx, y + 4.1, gd, 1.6, Color3.fromRGB(86, 150, 90), M.Grass, { Shadow = false })
		-- deux grandes urnes de part et d'autre du passage de gauche
		if left then
			for _, d in ipairs({ left[1] - 1.1, left[2] + 1.1 }) do
				kit:CylY("Urn", c0 + 0.9, y, d, 1.1, 2.6, Color3.fromRGB(246, 242, 250), M.Marble, { Solid = true, Shadow = false })
				kit:Ball("UrnPlant", c0 + 0.9, y + 3.2, d, 1.5, Color3.fromRGB(80, 146, 92), M.Grass, { Shadow = false })
			end
		end
	else
		-- console contre le mur de gauche (2,7 de haut) + tiroir + tablette basse
		local k0, k1 = T + 1.6, math.min(T + 6.4, pass0 - 1.1)
		local kx0, kx1 = c0 + 0.32, c0 + 1.55
		local topY = y + 2.7
		kit:Box("ConsoleTop", kx0, kx1 + 0.08, topY - 0.16, topY, k0 - 0.08, k1 + 0.08, wood, woodMat, { Solid = true, Shadow = true })
		kit:Box("ConsoleApron", kx0 + 0.08, kx1 - 0.02, topY - 0.62, topY - 0.16, k0 + 0.1, k1 - 0.1, wood, woodMat, { Solid = true, Shadow = false })
		kit:Box("ConsoleDrawer", kx1 - 0.02, kx1 + 0.02, topY - 0.56, topY - 0.22, k0 + 0.5, k1 - 0.5, wood:Lerp(WHITE, 0.08), woodMat, { Shadow = false })
		for _, d in ipairs({ (k0 * 2 + k1) / 3, (k0 + k1 * 2) / 3 }) do
			kit:Ball("ConsoleKnob", kx1 + 0.06, topY - 0.39, d, 0.14, pal.Accent, M.Metal, { Shadow = false })
		end
		for _, lx in ipairs({ kx0 + 0.2, kx1 - 0.2 }) do
			for _, ld in ipairs({ k0 + 0.2, k1 - 0.2 }) do
				kit:Box("ConsoleLeg", lx - 0.09, lx + 0.09, y, topY - 0.62, ld - 0.09, ld + 0.09, wood, woodMat, { Solid = true, Shadow = false })
			end
		end
		kit:Box("ConsoleShelf", kx0 + 0.1, kx1 - 0.1, y + 0.55, y + 0.67, k0 + 0.12, k1 - 0.12, wood, woodMat, { Shadow = false })
		-- sur la console : lampe (pied, abat-jour, ampoule), bouquet, vide-poche
		local ld = k0 + 0.8
		kit:CylY("ConsoleLampBase", (kx0 + kx1) / 2, topY, ld, 0.55, 0.12, pal.Accent, M.Metal, { Shadow = false })
		kit:CylY("ConsoleLampStem", (kx0 + kx1) / 2, topY + 0.12, ld, 0.12, 1.2, pal.Accent, M.Metal, { Shadow = false })
		kit:CylY("ConsoleLampShade", (kx0 + kx1) / 2, topY + 1.2, ld, 0.95, 0.8, Color3.fromRGB(255, 244, 226), M.Fabric, { Shadow = false })
		kit:Ball("ConsoleLampBulb", (kx0 + kx1) / 2, topY + 1.3, ld, 0.3, Color3.fromRGB(255, 226, 170), M.Neon, { Shadow = false })
		local vd = k1 - 0.8
		kit:CylY("ConsoleVase", (kx0 + kx1) / 2, topY, vd, 0.5, 0.9, Color3.fromRGB(120, 170, 200), M.Glass, { Shadow = false })
		for k, c in ipairs({ Color3.fromRGB(255, 150, 190), Color3.fromRGB(255, 226, 130), WHITE }) do
			kit:Ball("ConsoleBloom", (kx0 + kx1) / 2 + (k - 2) * 0.22, topY + 1.1 + (k % 2) * 0.18, vd + (k - 2) * 0.12, 0.34, c, M.SmoothPlastic, { Shadow = false })
		end
		kit:CylY("KeyBowl", (kx0 + kx1) / 2, topY, (k0 + k1) / 2, 0.7, 0.16, Color3.fromRGB(236, 220, 200), M.SmoothPlastic, { Shadow = false })
		-- grand miroir au-dessus (cadre + verre réfléchissant statique)
		local m0, m1 = k0 + 0.5, k1 - 0.5
		local my0, my1 = topY + 1.4, topY + 5.2
		kit:Box("HallMirrorFrame", c0, c0 + 0.14, my0, my1, m0, m1, pal.Accent, M.Metal, { Shadow = false })
		local glass = kit:Box("HallMirror", c0 + 0.14, c0 + 0.18, my0 + 0.22, my1 - 0.22, m0 + 0.22, m1 - 0.22, Color3.fromRGB(206, 218, 228), M.Glass,
			{ Shadow = false })
		glass.Reflectance = 0.35
	end

	-- porte-manteau (coin avant droit, devant la 1re marche, hors du battant)
	local cx, cd = h1 - SKIN - 1.05, T + 1.35
	if cd + 0.7 < run.D0 - 0.7 then
		kit:CylY("CoatStandBase", cx, y, cd, 1.3, 0.14, wood, woodMat, { Solid = true, Shadow = false })
		kit:CylY("CoatStandPole", cx, y + 0.14, cd, 0.22, 5.6, wood, woodMat, { Solid = true, Shadow = false })
		kit:Ball("CoatStandTop", cx, y + 5.85, cd, 0.36, wood, woodMat, { Shadow = false })
		for k = 0, 3 do
			local a = k / 4 * math.pi * 2 + math.pi / 4
			kit:Box("CoatHook", cx + math.cos(a) * 0.3 - 0.07, cx + math.cos(a) * 0.3 + 0.07, y + 5.05, y + 5.25, cd + math.sin(a) * 0.3 - 0.07,
				cd + math.sin(a) * 0.3 + 0.07, pal.Accent, M.Metal, { Shadow = false })
		end
		-- manteau (épaules + pan), écharpe, chapeau, parapluie
		local coat = if mansion then Color3.fromRGB(150, 40, 70) else Color3.fromRGB(196, 150, 104)
		kit:Box("Coat", cx - 0.55, cx + 0.15, y + 2.4, y + 4.9, cd - 0.62, cd - 0.2, coat, M.Fabric, { Shadow = false })
		kit:Ball("CoatShoulder", cx - 0.2, y + 4.85, cd - 0.41, 0.62, coat, M.Fabric, { Shadow = false })
		kit:Box("Scarf", cx + 0.1, cx + 0.34, y + 3.4, y + 5.1, cd + 0.12, cd + 0.36, Color3.fromRGB(236, 110, 140), M.Fabric, { Shadow = false })
		kit:CylY("HatBrim", cx, y + 5.95, cd, 0.9, 0.06, Color3.fromRGB(70, 60, 64), M.Fabric, { Shadow = false })
		kit:CylY("HatCrown", cx, y + 6.0, cd, 0.56, 0.4, Color3.fromRGB(70, 60, 64), M.Fabric, { Shadow = false })
		kit:Box("Umbrella", cx + 0.3, cx + 0.48, y + 0.14, y + 3.1, cd + 0.3, cd + 0.48, Color3.fromRGB(60, 90, 150), M.Fabric, { Shadow = false })
		kit:Box("UmbrellaHandle", cx + 0.3, cx + 0.48, y + 3.1, y + 3.4, cd + 0.3, cd + 0.66, Color3.fromRGB(90, 60, 44), M.Wood, { Shadow = false })
	end

	-- banc de rangement + coussin (mur de gauche, derrière le passage)
	local b0 = (if left then left[2] else T + 10) + (if mansion then 2.2 else 1.2)
	local b1 = math.min(b0 + 4.4, dBack - 3.4)
	if b1 - b0 > 2.5 and mansion then
		painting(kit, c0, y + 3.9, y + 8.4, b0, b1, pal.Accent, 2)
	elseif b1 - b0 > 2.5 then
		kit:Box("HallBench", c0 + 0.32, c0 + 1.7, y, y + 1.2, b0, b1, wood, woodMat, { Solid = true, Shadow = true })
		kit:Box("HallBenchCushion", c0 + 0.4, c0 + 1.62, y + 1.2, y + 1.45, b0 + 0.1, b1 - 0.1, if pal.Runner then pal.Runner:Lerp(WHITE, 0.45) else Color3.fromRGB(236, 214, 190),
			M.Fabric, { Shadow = false })
		-- deux paires de chaussures sous le banc
		for k = 0, 1 do
			local sd = b0 + 0.8 + k * 1.6
			kit:Box("Shoe", c0 + 0.8, c0 + 1.55, y, y + 0.3, sd - 0.2, sd + 0.2, if k == 0 then Color3.fromRGB(236, 110, 140) else Color3.fromRGB(80, 70, 76), M.Fabric,
				{ Shadow = false })
		end
		painting(kit, c0, y + 4.2, y + 7.6, b0 + 0.2, b1 - 0.2, wood, 1)
	end
	-- plante haute (coin arrière gauche, à côté de la porte de derrière)
	plant(kit, c0 + 1.05, y, dBack - 1.2, if pal.Style == "Loft" then Color3.fromRGB(70, 70, 78) else Color3.fromRGB(236, 226, 214))
	-- placard sous l'escalier (sauf loft : escalier ouvert, un vélo dessous)
	if WorldLayout.Dims(size).Floors >= 2 then
		if pal.Open then
			local bd = run.D0 + 9
			kit:CylX("BikeWheel", run.S0 + 2.1, y + 1.1, bd - 1.4, 2.2, 0.16, Color3.fromRGB(30, 30, 34), M.Rubber, { Shadow = false })
			kit:CylX("BikeWheel", run.S0 + 2.1, y + 1.1, bd + 1.4, 2.2, 0.16, Color3.fromRGB(30, 30, 34), M.Rubber, { Shadow = false })
			kit:Slab("BikeFrame", run.S0 + 2.1, { y + 2.3, bd - 1.3 }, { y + 2.3, bd + 1.2 }, 0.14, 0.14, Color3.fromRGB(236, 110, 90), M.Metal, { Shadow = false })
			kit:Slab("BikeFrame", run.S0 + 2.1, { y + 2.3, bd - 0.4 }, { y + 1.1, bd + 1.4 }, 0.14, 0.14, Color3.fromRGB(236, 110, 90), M.Metal, { Shadow = false })
			kit:Box("BikeSeat", run.S0 + 1.95, run.S0 + 2.25, y + 2.5, y + 2.65, bd - 0.9, bd - 0.2, Color3.fromRGB(30, 30, 34), M.Fabric, { Shadow = false })
		else
			underStair(kit, size, pal)
		end
	end
end

-- Lampe de plafond d'un étage (lanterne / lustre / plafonnier)
local function ceilingLamp(kit: any, size: any, floor: number, pal: Palette, withLight: boolean)
	local c0, c1 = WorldLayout.CorridorSpan(size)
	local y = WorldLayout.FloorY(floor) + WorldLayout.WALL_H
	local x = (c0 + c1) / 2
	local d = if floor == 1 then WorldLayout.WALL_T + 5.4 else WorldLayout.WALL_T + WorldLayout.DEPTH / 2
	local warm = Color3.fromRGB(255, 226, 180)
	local bulb: BasePart
	if pal.Style == "Mansion" and floor == 1 then
		-- lustre : rosace, tige, anneau doré, 6 bougies à ampoule, pampilles
		kit:CylY("ChandelierRose", x, y - 0.2, d, 1.4, 0.2, pal.Trim, M.SmoothPlastic, { Shadow = false })
		kit:Box("ChandelierRod", x - 0.07, x + 0.07, y - 2.4, y - 0.2, d - 0.07, d + 0.07, pal.Accent, M.Metal, { Shadow = false })
		kit:Ball("ChandelierHub", x, y - 2.75, d, 0.7, pal.Accent, M.Metal, { Shadow = false })
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			local bx, bd = x + math.cos(a) * 1.5, d + math.sin(a) * 1.5
			-- bras fin du moyeu à la bougie (plus de disque plein vu d'en dessous)
			kit:Part("ChandelierArm", Vector3.new(1.5, 0.1, 0.1), CFrame.new(x + math.cos(a) * 0.75, y - 2.72, -(d + math.sin(a) * 0.75)) * CFrame.Angles(0, a, 0),
				pal.Accent, M.Metal, { Shadow = false })
			kit:CylY("ChandelierCup", bx, y - 2.75, bd, 0.42, 0.12, pal.Accent, M.Metal, { Shadow = false })
			kit:CylY("ChandelierCandle", bx, y - 2.55, bd, 0.2, 0.45, WHITE, M.SmoothPlastic, { Shadow = false })
			local flame = kit:Ball("ChandelierBulb", bx, y - 1.95, bd, 0.28, Color3.fromRGB(255, 232, 186), M.Neon, { Shadow = false })
			if k == 0 then
				bulb = flame
			end
			kit:Ball("ChandelierCrystal", x + math.cos(a + 0.5) * 1.2, y - 3.15, d + math.sin(a + 0.5) * 1.2, 0.22, Color3.fromRGB(236, 244, 255), M.Glass,
				{ Shadow = false })
		end
		bulb = bulb or kit:Ball("ChandelierBulb", x, y - 2.95, d, 0.3, warm, M.Neon, { Shadow = false })
	elseif floor == 1 then
		-- lanterne suspendue : rosace, chaîne, cage + verre, ampoule
		kit:CylY("LanternRose", x, y - 0.2, d, 1, 0.2, pal.Trim, M.SmoothPlastic, { Shadow = false })
		kit:Box("LanternChain", x - 0.05, x + 0.05, y - 2, y - 0.2, d - 0.05, d + 0.05, pal.Accent, M.Metal, { Shadow = false })
		kit:Box("LanternCap", x - 0.55, x + 0.55, y - 2.25, y - 2, d - 0.55, d + 0.55, pal.Accent, M.Metal, { Shadow = false })
		kit:Box("LanternGlass", x - 0.45, x + 0.45, y - 3.5, y - 2.25, d - 0.45, d + 0.45, Color3.fromRGB(255, 246, 226), M.Glass, { T = 0.45, Shadow = false })
		kit:Box("LanternBottom", x - 0.55, x + 0.55, y - 3.7, y - 3.5, d - 0.55, d + 0.55, pal.Accent, M.Metal, { Shadow = false })
		bulb = kit:Ball("LanternBulb", x, y - 2.85, d, 0.4, warm, M.Neon, { Shadow = false })
	else
		-- plafonnier du palier (vasque en verre dépoli)
		kit:CylY("CeilingRose", x, y - 0.15, d, 1.3, 0.15, pal.Trim, M.SmoothPlastic, { Shadow = false })
		bulb = kit:Ball("LandingLamp", x, y - 0.35, d, 1.1, Color3.fromRGB(255, 240, 214), M.SmoothPlastic, { Shadow = false })
	end
	if withLight then
		kit:Light(bulb, Color3.fromRGB(255, 222, 176), 20, 0.8)
	end
end

function HouseStairs.BuildInterior(kit: any, size: any): InteriorResult
	local dims = WorldLayout.Dims(size)
	local floors = dims.Floors
	local pal = HouseStairs.Palette(size)
	local ramps: { BasePart } = {}
	local before = kit.Stats.Count
	local c0 = WorldLayout.CorridorSpan(size)
	local passages = WorldLayout.HallPassages(size)
	local left = passages.Left
	local T = WorldLayout.WALL_T
	for floor = 1, floors do
		trims(kit, size, floor, pal)
		if floor < floors then
			flight(kit, size, floor, pal, ramps)
		end
		if floor >= 2 then
			landingGuard(kit, size, floor, floors, pal)
		end
		-- plaque gravée aux étages (mur de gauche, derrière le passage : on la
		-- voit en arrivant par l'escalier)
		if floor >= 2 then
			local p0 = (if left then left[2] else T + 12) + 0.8
			plaque(kit, size, floor, c0, p0, p0 + 2.6)
		end
		ceilingLamp(kit, size, floor, pal, floor <= 2)
		if floor >= 2 then
			-- palier : tableau (mur de gauche, devant) + plante (coin du fond) + tapis
			painting(kit, c0, WorldLayout.FloorY(floor) + 4.2, WorldLayout.FloorY(floor) + 7.4, T + 1.6, T + 5.6, if pal.Style == "Mansion" then pal.Accent else pal.Rail,
				floor)
			plant(kit, c0 + 1.05, WorldLayout.FloorY(floor), T + WorldLayout.DEPTH - 1.2, if pal.Style == "Loft" then Color3.fromRGB(70, 70, 78) else Color3.fromRGB(236, 226, 214))
			local cx0, cx1 = WorldLayout.CorridorSpan(size)
			local y = WorldLayout.FloorY(floor)
			local rug = if pal.Runner then pal.Runner else Color3.fromRGB(150, 120, 96)
			kit:Box("LandingRug", cx0 + 1.4, cx1 - 1.2, y, y + 0.05, T + 7, T + WorldLayout.DEPTH - 3, rug:Lerp(Color3.fromRGB(250, 236, 220), 0.3), M.Fabric,
				{ Shadow = false })
		end
	end
	foyer(kit, size, pal)
	return { Ramps = ramps, Parts = kit.Stats.Count - before, Lights = kit.Stats.Lights }
end

-- (compat) coque + intérieur dans le même kit
function HouseStairs.Build(kit: any, size: any, _colors: Colors?): Result
	local before = kit.Stats.Count
	HouseStairs.BuildShell(kit, size)
	local inside = HouseStairs.BuildInterior(kit, size)
	local holes = {}
	local h0, h1 = WorldLayout.StairHole(size)
	for floor = 2, WorldLayout.Dims(size).Floors do
		table.insert(holes, { floor, h0, h1 })
	end
	return { Ramps = inside.Ramps, Holes = holes, Parts = kit.Stats.Count - before }
end

return HouseStairs
