--[[
	DistrictMansion (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DistrictMansion

	🏰 Dopamine Town (v10, CITY10) : l'identité de la COLLINE DES MANOIRS,
	construite côté CLIENT, en flux (TownStreetLife ; emplacements calculés
	par CityPlan dans le quartier "Mansion") :
	  - "MnsGate"      : entrée fermée : 2 grands piliers en pierre
	    (bossages, corniche, vases, lanternes), grille en fer forgé à 2
	    vantaux (barreaux à pointes dorées, volutes) qui S'OUVRE en douceur
	    quand l'avatar ou une voiture approche (et se referme ensuite),
	    portillons piétons ouverts, guérite du gardien (fenêtre, toit, le
	    gardien derrière sa vitre), barrière levante rouge et blanche qui se
	    lève aussi, plaque "Les Hauts du Manoir" ;
	  - "MnsWall"      : mur de pierre à chaperon, piliers à boules tous les
	    ~12 studs (longueur spot.Size.X) ;
	  - "MnsCypress"   : rangée de cyprès de Toscane (longueur spot.Size.X) ;
	  - "MnsFountain"  : grande fontaine à 3 vasques dans un parterre à la
	    française (buis taillés, graviers, cônes d'if, bancs), jets d'eau
	    animés ;
	  - "MnsViewpoint" : belvédère (terrasse, balustrade, longue-vue à
	    pièces, table d'orientation, bancs, lanternes, un couple qui admire
	    la vue) ;
	  - "MnsTopiary"   : paire de topiaires dans des bacs en pierre ;
	  - "MnsLantern"   : lanterne double sur colonne.
	Repère F : au sol, au centre de l'emprise, -Z = côté rue (portail :
	-Z = vers l'extérieur du quartier).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locale = require(ReplicatedStorage.Shared.Locale)
local CityKit = require(script.Parent.CityKit)

local DistrictMansion = {}

local M = CityKit.M
local rgb = CityKit.rgb
local Box, Part, Column, Egg, Glow, Text = CityKit.Box, CityKit.Part, CityKit.Column, CityKit.Egg, CityKit.Glow, CityKit.Text
local hash = CityKit.Hash

local STONE = rgb(222, 212, 190)
local STONE_D = rgb(186, 174, 152)
local IRON = rgb(30, 32, 36)
local GOLD = rgb(214, 176, 80)
local BOX = rgb(52, 104, 56)
local CYPRESS = rgb(40, 84, 52)
local GRAVEL = rgb(226, 218, 200)
local WATER = rgb(110, 170, 200)
local WHITE = rgb(250, 250, 248)
local WARM = rgb(255, 230, 180)

DistrictMansion.FOOT = {
	MnsFountain = Vector2.new(40, 40),
	MnsViewpoint = Vector2.new(30, 20),
	MnsTopiary = Vector2.new(12, 4),
}

----------------------------------------------------------------------
-- 🏛️ Pilier, grille, guérite
----------------------------------------------------------------------

local function pillar(m: Model, F: CFrame, x: number, z: number, h: number, big: boolean)
	local s = big and 1.6 or 1.1
	Box(m, "PillarBase", F, x - s - 0.24, x + s + 0.24, 0, 1.4, z - s - 0.24, z + s + 0.24, STONE_D, M.Slate, true)
	Box(m, "Pillar", F, x - s, x + s, 1.4, h, z - s, z + s, STONE, M.Cobblestone, true)
	-- bossages (lits de pierre plus sombres)
	for k = 1, 3 do
		local y = 1.4 + k * (h - 1.4) / 4
		Box(m, "Rustication", F, x - s - 0.08, x + s + 0.08, y - 0.12, y + 0.12, z - s - 0.08, z + s + 0.08, STONE_D, M.Slate)
	end
	Box(m, "PillarCap", F, x - s - 0.4, x + s + 0.4, h, h + 0.6, z - s - 0.4, z + s + 0.4, STONE_D, M.Slate)
	if big then
		-- vase (urne) sur le chapiteau
		Column(m, "UrnFoot", F, x, z, h + 0.6, h + 1.2, 1, STONE, M.Marble)
		Egg(m, "Urn", F * CFrame.new(x, h + 2.1, z), Vector3.new(2.2, 1.9, 2.2), STONE, M.Marble)
		Column(m, "UrnLip", F, x, z, h + 2.9, h + 3.2, 2.1, STONE, M.Marble)
		Egg(m, "UrnPlant", F * CFrame.new(x, h + 3.5, z), Vector3.new(2, 1.3, 2), BOX, M.Grass)
	else
		CityKit.Ball(m, "PillarBall", (F * CFrame.new(x, h + 1.2, z)).Position, 1.3, STONE, M.Marble)
	end
end

-- vantail de grille : repère L à la charnière, s'étend vers +x sur `w`
local function gateLeaf(m: Model, L: CFrame, w: number, h: number): { BasePart }
	local parts = {}
	local function add(p: BasePart)
		table.insert(parts, p)
	end
	add(Box(m, "LeafRailLow", L, 0.2, w, 0.8, 1.05, -0.08, 0.08, IRON, M.Metal))
	add(Box(m, "LeafRailMid", L, 0.2, w, h * 0.45, h * 0.45 + 0.22, -0.08, 0.08, IRON, M.Metal))
	add(Box(m, "LeafStile", L, 0, 0.3, 0.3, h + 0.6, -0.1, 0.1, IRON, M.Metal))
	add(Box(m, "LeafStile", L, w - 0.3, w, 0.3, h, -0.1, 0.1, IRON, M.Metal))
	local n = math.max(3, math.floor(w / 0.75))
	for i = 1, n - 1 do
		local x = i * w / n
		-- barreaux : plus hauts vers la charnière (arc)
		local top = h * 0.82 + math.sin((1 - x / w) * math.pi * 0.5) * h * 0.2
		add(Box(m, "Bar", L, x - 0.06, x + 0.06, 0.8, top, -0.06, 0.06, IRON, M.Metal))
		add(Part(m, "Spike", Vector3.new(0.24, 0.3, 0.24), L * CFrame.new(x, top + 0.15, 0), GOLD, M.Metal, "Ball"))
	end
	-- volute dorée au milieu
	add(Part(m, "Scroll", Vector3.new(0.22, 1.6, 1.6), L * CFrame.new(w / 2, h * 0.3, 0) * CFrame.Angles(0, math.pi / 2, 0), GOLD, M.Metal, "Cyl"))
	return parts
end

local function buildGate(m: Model, F: CFrame, seed: number)
	local ROAD = 8 -- demi-largeur de la chaussée
	local EDGE = 15.6 -- piliers d'angle (hors trottoirs)
	local H = 11
	-- piliers : 2 grands (bords de la chaussée) + 2 d'angle
	pillar(m, F, -ROAD - 1.6, 0, H, true)
	pillar(m, F, ROAD + 1.6, 0, H, true)
	pillar(m, F, -EDGE - 1.1, 0, H - 2.5, false)
	pillar(m, F, EDGE + 1.1, 0, H - 2.5, false)
	-- lanternes accrochées aux grands piliers (côté extérieur)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (ROAD + 1.6)
		Box(m, "LanternBracket", F, x - 0.1, x + 0.1, H - 2.4, H - 2.2, -2.8, -1.6, IRON, M.Metal)
		Glow(Box(m, "Lantern", F, x - 0.45, x + 0.45, H - 3.6, H - 2.4, -3.3, -2.4, WARM, M.Glass))
		Box(m, "LanternTop", F, x - 0.6, x + 0.6, H - 2.4, H - 2.1, -3.45, -2.25, IRON, M.Metal)
	end
	-- grille principale : 2 vantaux (charnières aux grands piliers)
	local hingeL = F * CFrame.new(-ROAD, 0, 0)
	local hingeR = F * CFrame.new(ROAD, 0, 0) * CFrame.Angles(0, math.pi, 0)
	local leafL = gateLeaf(m, hingeL, ROAD, H - 2)
	local leafR = gateLeaf(m, hingeR, ROAD, H - 2)
	-- portillons piétons (ouverts en permanence, rabattus contre le mur)
	gateLeaf(m, F * CFrame.new(-EDGE, 0, 0.3) * CFrame.Angles(0, math.rad(-80), 0), EDGE - ROAD - 3.4, H - 4)
	gateLeaf(m, F * CFrame.new(EDGE, 0, 0.3) * CFrame.Angles(0, math.rad(260), 0), EDGE - ROAD - 3.4, H - 4)
	-- plaque du quartier sur le pilier gauche
	local plaque = Box(m, "Plaque", F, -ROAD - 3, -ROAD - 0.2, 5.6, 7.4, -1.72, -1.62, rgb(30, 50, 40), M.Metal)
	Text(plaque, Enum.NormalId.Front, "🏰 " .. Locale.T("Mansion Hills"), GOLD, nil, Enum.Font.Fantasy, 90)
	-- guérite (à droite, côté intérieur)
	local G = F * CFrame.new(EDGE + 7, 0, 5)
	Box(m, "HutBase", G, -4, 4, 0, 1, -3.5, 3.5, STONE_D, M.Slate, true)
	Box(m, "Hut", G, -3.6, 3.6, 1, 9, -3.2, 3.2, STONE, M.Cobblestone, true)
	Box(m, "HutCornice", G, -4.2, 4.2, 9, 9.6, -3.8, 3.8, STONE_D, M.Slate)
	Box(m, "HutRoof", G, -3.6, 3.6, 9.6, 10.6, -3.2, 3.2, rgb(70, 74, 86), M.Slate)
	Glow(Box(m, "HutWindow", G, -2.6, 2.6, 4, 7.6, -3.28, -3.2, WARM, M.Glass))
	Box(m, "HutWindowBar", G, -0.06, 0.06, 4, 7.6, -3.34, -3.28, IRON, M.Metal)
	Box(m, "HutSill", G, -2.9, 2.9, 3.6, 4, -3.6, -3.2, STONE_D, M.Slate)
	Box(m, "HutDoor", G, -3.66, -3.6, 1, 8, -1.2, 1.4, rgb(60, 50, 40), M.Wood)
	local guard = CityKit.Npc(m, "salesperson", seed * 7 + 3, G * CFrame.new(0, 1, -1.4) * CFrame.Angles(0, math.pi, 0), "none", false)
	CityKit.Idle(guard, "idle", 2)
	-- barrière levante (bras rouge et blanc) côté entrée
	local P = F * CFrame.new(ROAD + 0.2, 0, -5)
	Box(m, "BarrierPost", P, -0.5, 0.5, 0, 3.6, -0.5, 0.5, rgb(240, 240, 240), M.SmoothPlastic, true)
	local armPivot = P * CFrame.new(0, 3.2, 0)
	local arm: { BasePart } = {}
	local armBase: { CFrame } = {}
	for k = 0, 7 do
		local x = -0.4 - k * 1.95
		local p = Part(m, "BarrierArm", Vector3.new(1.95, 0.4, 0.3), armPivot * CFrame.new(x - 0.975, 0, 0), k % 2 == 0 and rgb(220, 40, 40) or WHITE, M.SmoothPlastic)
		table.insert(arm, p)
		table.insert(armBase, armPivot:ToObjectSpace(p.CFrame))
	end
	-- ouverture : l'avatar local (ou sa voiture) à moins de 30 studs
	local all: { BasePart } = {}
	local base: { CFrame } = {}
	local pivots: { CFrame } = {}
	for _, p in ipairs(leafL) do
		table.insert(all, p)
		table.insert(base, hingeL:ToObjectSpace(p.CFrame))
		table.insert(pivots, hingeL)
	end
	for _, p in ipairs(leafR) do
		table.insert(all, p)
		table.insert(base, hingeR:ToObjectSpace(p.CFrame))
		table.insert(pivots, hingeR)
	end
	local nL = #leafL
	local open = 0
	local frames = table.create(#all) :: { CFrame }
	local armFrames = table.create(#arm) :: { CFrame }
	local center = F.Position
	CityKit.Actor(m, center, function(_t: number, dt: number)
		local lp = Players.LocalPlayer
		local ch = lp and lp.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		local want = 0
		if root and (root.Position - center).Magnitude < 34 then
			want = 1
		end
		local step = math.min(1, dt * 0.7)
		local target = open + math.clamp(want - open, -step, step)
		if math.abs(target - open) < 1e-4 and (open == 0 or open == 1) and frames[1] ~= nil then
			return
		end
		open = target
		local e = open * open * (3 - 2 * open)
		local a = e * math.rad(95)
		for i = 1, #all do
			-- les deux vantaux s'ouvrent vers l'intérieur du quartier (+Z)
			local sign = i <= nL and -1 or 1
			frames[i] = pivots[i] * CFrame.Angles(0, sign * a, 0) * base[i]
		end
		workspace:BulkMoveTo(all, frames, Enum.BulkMoveMode.FireCFrameChanged)
		local rot = armPivot * CFrame.Angles(0, 0, -e * math.rad(84))
		for i = 1, #arm do
			armFrames[i] = rot * armBase[i]
		end
		workspace:BulkMoveTo(arm, armFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end, 0)
	-- haies de buis de part et d'autre, côté extérieur (à gauche : la guérite est à droite)
	CityKit.Hedge(m, F * CFrame.new(-(EDGE + 8), 0, -1.8), 10, 3.2, 1.8, seed)
end

----------------------------------------------------------------------
-- Murs de pierre, cyprès, lanternes, topiaires
----------------------------------------------------------------------

local function buildWall(m: Model, F: CFrame, seed: number, spot: any)
	local L = spot and spot.Size and spot.Size.X or 24
	local H = 5
	Box(m, "StoneWall", F, -L / 2, L / 2, 0, H, -0.9, 0.9, STONE, M.Cobblestone, true)
	Box(m, "WallCoping", F, -L / 2, L / 2, H, H + 0.5, -1.15, 1.15, STONE_D, M.Slate)
	Box(m, "WallFooting", F, -L / 2 + 0.05, L / 2 - 0.05, -0.1, 0.8, -1.05, 1.05, STONE_D, M.Slate, true)
	local n = math.max(1, math.floor(L / 12 + 0.5))
	for i = 0, n do
		local x = -L / 2 + i * L / n
		x = math.clamp(x, -L / 2 + 1.25, L / 2 - 1.25)
		Box(m, "WallPier", F, x - 1.2, x + 1.2, 0, H + 1.4, -1.3, 1.3, STONE, M.Cobblestone, true)
		Box(m, "WallPierCap", F, x - 1.45, x + 1.45, H + 1.4, H + 1.8, -1.55, 1.55, STONE_D, M.Slate)
		CityKit.Ball(m, "WallBall", (F * CFrame.new(x, H + 2.5, 0)).Position, 1.3, STONE, M.Marble)
	end
	-- lierre grimpant par endroits
	for i = 0, math.floor(L / 10) - 1 do
		if hash(seed, i) < 0.5 then
			local x = -L / 2 + (i + 0.5) * 10
			Egg(m, "Ivy", F * CFrame.new(x, 3, -0.95), Vector3.new(4.5, 4, 0.5), rgb(60, 110, 60), M.Grass)
		end
	end
end

-- cyprès de Toscane : fuseau étroit (3 ellipsoïdes empilés)
local function cypress(m: Model, F: CFrame, x: number, z: number, h: number, seed: number)
	Column(m, "CypressTrunk", F, x, z, 0, 1.6, 0.6, rgb(96, 70, 50), M.Wood)
	local green = CYPRESS:Lerp(rgb(70, 110, 70), hash(seed, 1) * 0.5)
	Egg(m, "CypressLow", F * CFrame.new(x, h * 0.3, z), Vector3.new(3.2, h * 0.55, 3.2), green, M.Grass)
	Egg(m, "CypressMid", F * CFrame.new(x, h * 0.58, z), Vector3.new(2.6, h * 0.5, 2.6), green:Lerp(Color3.new(0, 0, 0), 0.06), M.Grass)
	Egg(m, "CypressTop", F * CFrame.new(x, h * 0.84, z), Vector3.new(1.5, h * 0.36, 1.5), green, M.Grass)
end

local function buildCypress(m: Model, F: CFrame, seed: number, spot: any)
	local L = spot and spot.Size and spot.Size.X or 24
	local n = math.max(1, math.floor(L / 6))
	for i = 0, n - 1 do
		local x = -L / 2 + (i + 0.5) * L / n
		cypress(m, F, x, 0, 13 + hash(seed, i) * 5, seed + i)
	end
end

local function buildLantern(m: Model, F: CFrame, _seed: number)
	Box(m, "LampPlinth", F, -0.9, 0.9, 0, 1.2, -0.9, 0.9, STONE_D, M.Slate, true)
	Column(m, "LampColumn", F, 0, 0, 1.2, 9, 0.7, IRON, M.Metal, true)
	Box(m, "LampCross", F, -2.2, 2.2, 8.7, 9, -0.12, 0.12, IRON, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		local L = F * CFrame.new(sx * 2.2, 0, 0)
		Glow(Box(m, "LampGlass", L, -0.45, 0.45, 7.6, 8.7, -0.45, 0.45, WARM, M.Glass))
		Box(m, "LampCap", L, -0.6, 0.6, 8.7, 9.1, -0.6, 0.6, IRON, M.Metal)
		CityKit.Ball(m, "LampFinial", (L * CFrame.new(0, 9.35, 0)).Position, 0.3, GOLD, M.Metal)
	end
end

local function buildTopiary(m: Model, F: CFrame, seed: number)
	for _, x in ipairs({ -4, 4 }) do
		Box(m, "Planter", F, x - 1.4, x + 1.4, 0, 2.2, -1.4, 1.4, STONE, M.Marble, true)
		Box(m, "PlanterRim", F, x - 1.6, x + 1.6, 2.2, 2.5, -1.6, 1.6, STONE_D, M.Slate)
		if hash(seed, x) < 0.5 then
			-- spirale (boules décroissantes)
			for k = 0, 3 do
				CityKit.Ball(m, "TopiaryBall", (F * CFrame.new(x, 3.4 + k * 1.5, 0)).Position, 2.4 - k * 0.45, BOX, M.Grass)
			end
		else
			Egg(m, "TopiaryCone", F * CFrame.new(x, 5.2, 0), Vector3.new(2.6, 6, 2.6), BOX, M.Grass)
		end
	end
end

----------------------------------------------------------------------
-- ⛲ Grande fontaine et parterre
----------------------------------------------------------------------

local function buildFountain(m: Model, F: CFrame, seed: number)
	local R = 18
	Box(m, "Gravel", F, -R, R, -0.1, 0.16, -R, R, GRAVEL, M.Pebble, true)
	-- parterre : 4 quarts de buis bas en L autour de la fontaine
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local cx, cz = sx * 11, sz * 11
			Box(m, "BoxHedge", F, cx - 5, cx + 5, 0.16, 1.4, cz - 0.7, cz + 0.7, BOX, M.Grass, true)
			Box(m, "BoxHedge", F, cx - 0.7, cx + 0.7, 0.16, 1.4, cz - 5, cz - 0.7, BOX, M.Grass, true)
			Box(m, "BoxHedge", F, cx - 0.7, cx + 0.7, 0.16, 1.4, cz + 0.7, cz + 5, BOX, M.Grass, true)
			Box(m, "RoseBed", F, cx + sx * 1.2, cx + sx * 4.4, 0.16, 0.5, cz + sz * 1.2, cz + sz * 4.4, rgb(110, 80, 60), M.Ground)
			for k = 0, 2 do
				Egg(m, "Rose", F * CFrame.new(cx + sx * (1.9 + k * 1.1), 0.95, cz + sz * (1.9 + (k % 2) * 1.4)), Vector3.new(1, 0.8, 1), CityKit.Pick({ rgb(230, 50, 70), rgb(255, 170, 200), WHITE }, seed, k + cx), M.SmoothPlastic)
			end
			Egg(m, "YewCone", F * CFrame.new(sx * (R - 1.6), 3.4, sz * (R - 1.6)), Vector3.new(2.4, 6.4, 2.4), CYPRESS, M.Grass)
		end
	end
	-- bassin (3 vasques)
	local B = F * CFrame.new(0, 0.16, 0)
	Column(m, "BasinRim", B, 0, 0, 0, 2.2, 13, STONE, M.Marble, true)
	local w1 = Column(m, "BasinWater", B, 0, 0, 1.6, 2.0, 11.8, WATER, M.Glass)
	w1.Transparency = 0.2
	Column(m, "Stem", B, 0, 0, 2, 6, 1.6, STONE, M.Marble)
	Column(m, "Bowl2", B, 0, 0, 6, 6.8, 6.4, STONE, M.Marble)
	local w2 = Column(m, "Bowl2Water", B, 0, 0, 6.8, 6.95, 5.6, WATER, M.Glass)
	w2.Transparency = 0.25
	Column(m, "Stem2", B, 0, 0, 6.8, 9.6, 0.9, STONE, M.Marble)
	Column(m, "Bowl3", B, 0, 0, 9.6, 10.2, 3, STONE, M.Marble)
	CityKit.Ball(m, "Finial", (B * CFrame.new(0, 10.9, 0)).Position, 1.1, STONE, M.Marble)
	-- nappes d'eau qui tombent des vasques (anneaux transparents) + jets animés
	local sheet1 = Column(m, "Sheet", B, 0, 0, 2.2, 6.2, 6.6, WATER, M.Glass)
	sheet1.Transparency = 0.72
	local sheet2 = Column(m, "Sheet", B, 0, 0, 7.0, 9.8, 3.2, WATER, M.Glass)
	sheet2.Transparency = 0.72
	local jets: { BasePart } = {}
	local jetBase: { CFrame } = {}
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		local p = Part(m, "Jet", Vector3.new(0.4, 0.4, 0.4), B * CFrame.new(math.cos(a) * 4.8, 3, math.sin(a) * 4.8), rgb(200, 236, 255), M.Glass, "Ball")
		p.Transparency = 0.35
		table.insert(jets, p)
		table.insert(jetBase, B * CFrame.new(math.cos(a) * 5.4, 2.0, math.sin(a) * 5.4))
	end
	local frames = table.create(#jets) :: { CFrame }
	CityKit.Actor(m, F.Position, function(t: number)
		for i = 1, #jets do
			-- gouttes en arc (parabole) vers la vasque centrale
			local u = (t * 0.8 + i / #jets) % 1
			local base = jetBase[i]
			local toward = -base.Position + B.Position
			local flat = Vector3.new(toward.X, 0, toward.Z) * (u * 0.55)
			frames[i] = CFrame.new(base.Position + flat + Vector3.new(0, 4 * u * (1 - u) * 3.4, 0))
		end
		workspace:BulkMoveTo(jets, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end, seed)
	-- bancs en pierre aux 4 allées
	for k = 0, 3 do
		local a = k * math.pi / 2
		local S = F * CFrame.new(math.cos(a) * 9.6, 0.16, math.sin(a) * 9.6) * CFrame.Angles(0, -a - math.pi / 2, 0)
		Box(m, "StoneBench", S, -2.4, 2.4, 1.2, 1.5, -0.7, 0.7, STONE, M.Marble, true)
		for _, x in ipairs({ -1.8, 1.8 }) do
			Box(m, "BenchFoot", S, x - 0.3, x + 0.3, 0, 1.2, -0.6, 0.6, STONE_D, M.Slate)
		end
	end
	-- deux promeneurs
	local a1 = CityKit.Npc(m, "elder", seed * 3 + 1, F * CFrame.new(-2, 0.16, -9) * CFrame.Angles(0, 0.3, 0), "cane", true)
	CityKit.Idle(a1, "talk", 0)
	local a2 = CityKit.Npc(m, "shopper", seed * 3 + 2, F * CFrame.new(-0.4, 0.16, -9.4) * CFrame.Angles(0, -0.6, 0), "bag", true)
	CityKit.Idle(a2, "talk", 2)
end

----------------------------------------------------------------------
-- 🔭 Belvédère
----------------------------------------------------------------------

local function buildViewpoint(m: Model, F: CFrame, seed: number)
	local W, D = 28, 16
	-- terrasse (vue vers +Z : l'extérieur de la ville)
	Box(m, "Terrace", F, -W / 2, W / 2, -0.1, 0.6, -D / 2, D / 2, STONE, M.Pavement, true)
	-- balustrade (côté vue et côtés)
	local function balustrade(x0: number, x1: number, z: number, alongX: boolean)
		local len = math.abs(x1 - x0)
		local n = math.floor(len / 1.1)
		for i = 0, n do
			local t = x0 + (x1 - x0) * i / n
			local x, zz = alongX and t or z, alongX and z or t
			Column(m, "Baluster", F, x, zz, 0.6, 3.2, 0.5, STONE, M.Marble)
		end
		if alongX then
			Box(m, "Handrail", F, math.min(x0, x1) - 0.3, math.max(x0, x1) + 0.3, 3.2, 3.7, z - 0.45, z + 0.45, STONE_D, M.Slate, true)
			Box(m, "BaseRail", F, math.min(x0, x1), math.max(x0, x1), 0.6, 0.9, z - 0.4, z + 0.4, STONE_D, M.Slate, true)
		else
			Box(m, "Handrail", F, z - 0.45, z + 0.45, 3.2, 3.7, math.min(x0, x1) - 0.3, math.max(x0, x1) + 0.3, STONE_D, M.Slate, true)
			Box(m, "BaseRail", F, z - 0.4, z + 0.4, 0.6, 0.9, math.min(x0, x1), math.max(x0, x1), STONE_D, M.Slate, true)
		end
	end
	balustrade(-W / 2 + 0.6, W / 2 - 0.6, D / 2 - 0.6, true)
	balustrade(-D / 2 + 3, D / 2 - 1.2, -W / 2 + 0.6, false)
	balustrade(-D / 2 + 3, D / 2 - 1.2, W / 2 - 0.6, false)
	-- longue-vue à pièces
	local T = F * CFrame.new(-5, 0.6, D / 2 - 3)
	Column(m, "ScopePost", T, 0, 0, 0, 3.6, 0.5, rgb(40, 80, 60), M.Metal)
	local scope = Part(m, "Scope", Vector3.new(2.2, 0.8, 0.8), T * CFrame.new(0, 4.2, 0.2) * CFrame.Angles(0, math.pi / 2, math.rad(8)), rgb(40, 80, 60), M.Metal, "Cyl")
	local _ = scope
	Box(m, "ScopeCoin", T, -0.5, 0.5, 3.2, 3.9, -0.5, -0.25, rgb(40, 80, 60), M.Metal)
	for _, sx in ipairs({ -0.35, 0.35 }) do
		Part(m, "Eyepiece", Vector3.new(0.4, 0.3, 0.3), T * CFrame.new(sx, 4.35, -0.95) * CFrame.Angles(0, math.pi / 2, 0), rgb(20, 20, 24), M.Metal, "Cyl")
	end
	-- table d'orientation (disque incliné, texte)
	local O = F * CFrame.new(5, 0.6, D / 2 - 3.4)
	Column(m, "OrientStand", O, 0, 0, 0, 2.8, 1.4, STONE_D, M.Slate)
	local disc = Part(m, "OrientTable", Vector3.new(0.3, 3.2, 3.2), O * CFrame.new(0, 3, 0) * CFrame.Angles(math.rad(-20), 0, 0) * CityKit.UPRIGHT, rgb(200, 170, 110), M.Metal, "Cyl")
	local plate = Part(m, "OrientText", Vector3.new(2.3, 0.02, 2.3), O * CFrame.new(0, 3.17, 0) * CFrame.Angles(math.rad(-20), 0, 0), rgb(200, 170, 110), M.SmoothPlastic)
	plate.Transparency = 1
	Text(plate, Enum.NormalId.Top, "N ↑  " .. Locale.T("Dopamine Town"), rgb(60, 40, 20), nil, Enum.Font.Fantasy, 40)
	local _ = disc
	-- bancs + lanternes
	for _, x in ipairs({ -9, 9 }) do
		CityKit.Bench(m, F * CFrame.new(x, 0.6, -2) * CFrame.Angles(0, math.pi, 0), 5)
	end
	buildLantern(m, F * CFrame.new(-W / 2 + 2, 0.6, -D / 2 + 2), seed)
	buildLantern(m, F * CFrame.new(W / 2 - 2, 0.6, -D / 2 + 2), seed)
	-- un couple qui admire la vue
	local a = CityKit.Npc(m, "pedestrian", seed * 9 + 1, F * CFrame.new(1, 0.6, D / 2 - 2.2) * CFrame.Angles(0, math.pi, 0), "phone", true)
	CityKit.Idle(a, "idle", 0)
	local b = CityKit.Npc(m, "shopper", seed * 9 + 2, F * CFrame.new(2.6, 0.6, D / 2 - 2.4) * CFrame.Angles(0, math.pi, 0), "none", true)
	CityKit.Idle(b, "wave", 2.2)
end

DistrictMansion.BUILDERS = {
	MnsGate = buildGate,
	MnsWall = buildWall,
	MnsCypress = buildCypress,
	MnsFountain = buildFountain,
	MnsViewpoint = buildViewpoint,
	MnsTopiary = buildTopiary,
	MnsLantern = buildLantern,
}
DistrictMansion.BIG = { MnsGate = true, MnsFountain = true, MnsViewpoint = true, MnsCypress = true, MnsWall = true }
DistrictMansion.IMPOSTORS = {
	MnsCypress = function(m: Model, F: CFrame, seed: number, spot: any)
		local L = spot and spot.Size and spot.Size.X or 24
		local n = math.max(1, math.floor(L / 6))
		for i = 0, n - 1 do
			local x = -L / 2 + (i + 0.5) * L / n
			Egg(m, "ImpCypress", F * CFrame.new(x, 7.5, 0), Vector3.new(2.8, 15, 2.8), CYPRESS, M.Grass)
		end
		local _ = seed
	end,
	MnsWall = function(m: Model, F: CFrame, _seed: number, spot: any)
		local L = spot and spot.Size and spot.Size.X or 24
		Box(m, "ImpWall", F, -L / 2, L / 2, 0, 5.5, -1, 1, STONE, M.Cobblestone, true)
	end,
}

return DistrictMansion
