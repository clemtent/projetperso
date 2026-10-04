--[[
	MusicStageBuild (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MusicStageBuild

	🎵 DÉCOR de la scène musicale de la place (v9.9, MUSIC99), construit par
	chaque client (MusicStage), EN FLUX : un morceau par image (Steps).
	Échelle réelle (avatar ≈ 5,2 studs ≈ 1,75 m -> 1 m ≈ 3 studs) :
	  - scène : plancher en bois sombre (serveur), jupe en tissu plissé,
	    nez de marche blancs, câbles, retours de scène, 3 pieds de micro ;
	  - portique d'éclairage en ALUMINIUM TRIANGULÉ (4 tours + grill),
	    toit à deux pans, bandeau "DOPAMINE LIVE", 6 PAR, 4 lyres
	    motorisées (faisceaux la nuit), rideau de fond plissé, ÉCRAN LED
	    (titre du morceau, égaliseur) ;
	  - sono : 2 piles (caisson + tête) au sol, 2 "line arrays" suspendus ;
	  - 🎹 piano à queue (caisse galbée, couvercle ouvert sur sa béquille,
	    table d'harmonie, cadre doré, cordes, 88 touches, lyre et pédales,
	    banquette capitonnée) ;
	  - 🥁 batterie (grosse caisse et pédale, caisse claire, 2 toms, tom
	    basse, charleston, crash, ride, tabouret, tapis) ;
	  - 🎸 guitare électrique + ampli combo, 🎸 basse + ampli "stack",
	    sur leurs stands ; 🎶 xylophone (37 lames, tubes résonateurs),
	    🎛️ synthé 49 touches sur stand en X ; 🎧 cabine DJ (2 platines,
	    table de mixage, ordinateur, casque, façade LED) ;
	  - 📻 juke-box au pied de la scène (E : morceaux, F : radio).
	Tout est ancré, sans collision (sauf quelques blocs invisibles "Block"
	pour ne pas traverser les instruments, côté client), sans vraie
	lumière (les 2 projecteurs sont côté serveur).

	API :
	  MusicStageBuild.new(stageCF, parent, detail) -> Build
	  build:Step() -> boolean (true = terminé)   un morceau par appel
	  build.H : poignées pour l'animation (touches, fûts, cymbales,
	    instruments portés, platines, écran, lyres, émetteurs de son…)
	  build:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicData = require(ReplicatedStorage.Shared.MusicData)

local MusicStageBuild = {}
MusicStageBuild.__index = MusicStageBuild

local M = Enum.Material
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local rad = math.rad

local BLACK = Color3.fromRGB(24, 24, 28)
local LACQUER = Color3.fromRGB(14, 14, 18)
local FABRIC = Color3.fromRGB(30, 29, 34)
local FABRIC2 = Color3.fromRGB(38, 37, 43)
local CHROME = Color3.fromRGB(212, 214, 222)
local ALU = Color3.fromRGB(190, 194, 202)
local STEEL = Color3.fromRGB(70, 72, 80)
local BRASS = Color3.fromRGB(208, 170, 88)
local GOLD = Color3.fromRGB(214, 176, 96)
local IVORY = Color3.fromRGB(248, 245, 236)
local EBONY = Color3.fromRGB(20, 20, 24)
local WHITE = Color3.fromRGB(255, 255, 255)
local TAPE = Color3.fromRGB(236, 236, 228)
local SPRUCE = Color3.fromRGB(222, 188, 138)
local ROSEWOOD = Color3.fromRGB(74, 44, 34)
local MAPLE = Color3.fromRGB(232, 198, 146)
local SHELL = Color3.fromRGB(38, 76, 168) -- batterie : bleu pailleté
local HEAD = Color3.fromRGB(238, 234, 224)
local BRONZE = Color3.fromRGB(206, 164, 82)
local PINK = Color3.fromRGB(255, 132, 184)
local HOT = Color3.fromRGB(236, 72, 140)
local CYAN = Color3.fromRGB(110, 220, 255)
local LILAC = Color3.fromRGB(186, 150, 246)
local WALNUT = Color3.fromRGB(118, 70, 42)

export type Build = typeof(setmetatable(
	{} :: {
		CF: CFrame,
		Model: Model,
		Detail: string,
		H: any,
		Index: number,
		Group: Instance,
		Count: number,
		Done: boolean,
	},
	MusicStageBuild
))

----------------------------------------------------------------------
-- Fabrique de pièces
----------------------------------------------------------------------

local function newPart(self: any, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		(p :: Part).Shape = shape
	end
	p.Parent = self.Group
	self.Count += 1
	return p
end

-- Pièce en repère local de la scène
local function box(self: any, name: string, size: Vector3, lcf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return newPart(self, name, size, self.CF * lcf, color, material)
end

-- Cylindre entre deux points (monde)
local function rodW(self: any, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?): BasePart
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, rad(90), 0)
	if len < 1e-3 then
		cf = CFrame.new(mid)
	end
	return newPart(self, name, Vector3.new(math.max(len, 0.02), d, d), cf, color, material, CYL)
end

-- Cylindre dont l'axe = `axis` (monde), centre `c`
local function cylW(self: any, name: string, c: Vector3, axis: Vector3, len: number, d: number, color: Color3, material: Enum.Material?): BasePart
	local a = axis.Unit
	local up = math.abs(a.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt(c, c + a, up) * CFrame.Angles(0, rad(90), 0)
	return newPart(self, name, Vector3.new(len, d, d), cf, color, material, CYL)
end

local function ballW(self: any, name: string, c: Vector3, d: number, color: Color3, material: Enum.Material?): BasePart
	return newPart(self, name, Vector3.new(d, d, d), CFrame.new(c), color, material, BALL)
end

-- Triangle rectangle (coin droit R, côtés d1·L1 et d2·L2), épaisseur `t`
-- verticale ; R, d1, d2 dans le repère `frame`
local function tri(self: any, name: string, frame: CFrame, R: Vector3, d1: Vector3, L1: number, d2: Vector3, L2: number, t: number, color: Color3, material: Enum.Material?): BasePart?
	if L1 < 0.02 or L2 < 0.02 then
		return nil
	end
	local y = frame:VectorToWorldSpace(d1.Unit)
	local z = -frame:VectorToWorldSpace(d2.Unit)
	local x = y:Cross(z)
	local center = frame:PointToWorldSpace(R + d1.Unit * (L1 / 2) + d2.Unit * (L2 / 2))
	return newPart(self, name, Vector3.new(t, L1, L2), CFrame.fromMatrix(center, x, y, z), color, material, nil, "WedgePart")
end

local function glow(p: BasePart, color: Color3): BasePart
	p.Color = color
	p:SetAttribute("MusicGlow", true)
	return p
end

local function surface(host: BasePart, face: Enum.NormalId, pps: number, lightInfluence: number?): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pps
	g.LightInfluence = lightInfluence or 0.3
	g.Brightness = 1
	g.MaxDistance = 220
	g.ClipsDescendants = true
	g.Parent = host
	return g
end

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = font or Enum.Font.FredokaOne
	l.TextColor3 = color
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

-- (v11) Agrandit un groupe autour d'un pivot (piano x1,3, batterie x1,25 :
-- échelle Roblox) : positions ET tailles multipliées par k
local function scaleGroup(group: Instance?, pivot: CFrame, k: number)
	if not group then
		return
	end
	for _, d in ipairs(group:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size = d.Size * k
			d.CFrame = pivot * CFrame.new(rel.Position * k) * (rel - rel.Position)
		end
	end
end

local function scaleCF(pivot: CFrame, k: number, cf: CFrame): CFrame
	local rel = pivot:ToObjectSpace(cf)
	return pivot * CFrame.new(rel.Position * k) * (rel - rel.Position)
end

----------------------------------------------------------------------
-- Portique (treillis aluminium)
----------------------------------------------------------------------

-- Poutre treillis carrée de `a` à `b` (repère local), largeur w ; faces
-- triangulées : "all" ou { indices 1..4 } ; pas `s`
local function truss(self: any, a: Vector3, b: Vector3, w: number, faces: { number }, s: number)
	local A, B = self.CF:PointToWorldSpace(a), self.CF:PointToWorldSpace(b)
	local dir = (B - A).Unit
	local len = (B - A).Magnitude
	local u = math.abs(dir.Y) > 0.9 and self.CF.RightVector or self.CF.UpVector
	local v = dir:Cross(u).Unit
	u = v:Cross(dir).Unit
	local h = w / 2 - 0.07
	local corners = { u * h + v * h, -u * h + v * h, -u * h - v * h, u * h - v * h }
	for i, o in ipairs(corners) do
		rodW(self, "Chord" .. i, A + o, B + o, 0.13, ALU, M.Metal)
	end
	local n = math.max(1, math.floor(len / s + 0.5))
	local step = len / n
	for _, f in ipairs(faces) do
		local c1, c2 = corners[f], corners[f % 4 + 1]
		for i = 0, n - 1 do
			local p1 = A + dir * (i * step) + (i % 2 == 0 and c1 or c2)
			local p2 = A + dir * ((i + 1) * step) + (i % 2 == 0 and c2 or c1)
			rodW(self, "Lace", p1, p2, 0.06, ALU, M.Metal)
		end
	end
end

----------------------------------------------------------------------
-- Les étapes de construction
----------------------------------------------------------------------

local STEPS: { { string } } = {}
local BUILDERS: { [string]: (self: any) -> () } = {}

local function step(name: string, fn: (self: any) -> ())
	table.insert(STEPS, { name })
	BUILDERS[name] = fn
end

local D = MusicData.DECK
local TOP = MusicData.DECK_TOP

-- 1. Finitions de la scène : jupe plissée, nez de marche, bandes, câbles
step("Deck", function(self)
	local skirtH = TOP - 0.02 + 0.28 -- (du pavé jusque sous le plancher)
	local y = (TOP - 0.04 + -0.26) / 2
	local fold = self.Detail == "Low" and 2.4 or 1.1
	-- devant (de part et d'autre des marches), côtés, fond
	local function skirt(x0: number, x1: number, z: number, alongX: boolean, outward: number)
		local len = x1 - x0
		local n = math.max(1, math.floor(len / fold + 0.5))
		local w = len / n
		for i = 0, n - 1 do
			local c = x0 + (i + 0.5) * w
			local depth = (i % 2 == 0) and 0.07 or 0.1
			local off = z + outward * (0.03 + depth / 2)
			local color = (i % 2 == 0) and FABRIC or FABRIC2
			if alongX then
				box(self, "Skirt", Vector3.new(w + 0.02, skirtH, depth), CFrame.new(c, y, off), color, M.Fabric)
			else
				box(self, "Skirt", Vector3.new(depth, skirtH, w + 0.02), CFrame.new(off, y, c), color, M.Fabric)
			end
		end
	end
	local sx = MusicData.STEPS.X
	skirt(D.X0, -sx, D.Z0, true, -1)
	skirt(sx, D.X1, D.Z0, true, -1)
	skirt(D.Z0, D.Z1, D.X0, false, -1)
	skirt(D.Z0, D.Z1, D.X1, false, 1)
	-- bande blanche au bord du plancher (sécurité), nez de marche
	box(self, "EdgeTape", Vector3.new(D.X1 - D.X0 - 0.2, 0.06, 0.12), CFrame.new(0, TOP, D.Z0 + 0.12), TAPE, M.Fabric)
	local S = MusicData.STEPS
	for i = 1, S.Count do
		local stepTop = i * S.Rise
		local z0 = D.Z0 - (S.Count - i) * S.Depth - S.Depth
		box(self, "StepNose", Vector3.new(S.X * 2 - 0.2, 0.06, 0.12), CFrame.new(0, stepTop, z0 + 0.1), TAPE, M.Fabric)
		-- contremarche en tissu noir (légèrement devant la marche)
		box(self, "StepRiser", Vector3.new(S.X * 2 - 0.04, S.Rise - 0.06, 0.05), CFrame.new(0, stepTop - S.Rise / 2 - 0.03, z0 - 0.03), FABRIC, M.Fabric)
	end
	-- jupe des praticables + bord blanc
	for name, r in pairs(MusicData.RISERS) do
		local top = TOP + r.H
		local h = r.H - 0.04
		box(self, name .. "RiserSkirt", Vector3.new(r.X1 - r.X0 + 0.02, h, 0.06), CFrame.new((r.X0 + r.X1) / 2, TOP + h / 2 + 0.01, r.Z0 - 0.04), FABRIC, M.Fabric)
		box(self, name .. "RiserTape", Vector3.new(r.X1 - r.X0 - 0.2, 0.05, 0.1), CFrame.new((r.X0 + r.X1) / 2, top, r.Z0 + 0.1), TAPE, M.Fabric)
		if r.X0 > D.X0 + 0.1 then
			box(self, name .. "RiserSide", Vector3.new(0.06, h, r.Z1 - r.Z0 - 0.02), CFrame.new(r.X0 - 0.04, TOP + h / 2 + 0.01, (r.Z0 + r.Z1) / 2), FABRIC, M.Fabric)
		end
		if r.X1 < D.X1 - 0.1 then
			box(self, name .. "RiserSide", Vector3.new(0.06, h, r.Z1 - r.Z0 - 0.02), CFrame.new(r.X1 + 0.04, TOP + h / 2 + 0.01, (r.Z0 + r.Z1) / 2), FABRIC, M.Fabric)
		end
	end
	-- câbles noirs au sol (des instruments vers le boîtier de scène au fond)
	local snake = Vector3.new(-9.2, TOP, 8.4)
	box(self, "SnakeBox", Vector3.new(0.9, 0.5, 0.6), CFrame.new(snake.X, TOP + 0.22, snake.Z), BLACK, M.Metal)
	if self.Detail ~= "Low" then
		for _, p in ipairs({ Vector3.new(-1.6, TOP, -2.2), Vector3.new(4.0, TOP, -2.0), Vector3.new(-0.2, TOP, -2.0), Vector3.new(4.3, TOP, 2.6), Vector3.new(-2.9, TOP, -3.0) }) do
			local mid = Vector3.new(p.X, TOP, 8.0)
			rodW(self, "Cable", self.CF:PointToWorldSpace(p + Vector3.new(0, 0.02, 0)), self.CF:PointToWorldSpace(mid + Vector3.new(0, 0.02, 0)), 0.07, BLACK, M.Rubber)
			rodW(self, "Cable", self.CF:PointToWorldSpace(mid + Vector3.new(0, 0.02, 0)), self.CF:PointToWorldSpace(snake + Vector3.new(0.3, 0.02, -0.2)), 0.07, BLACK, M.Rubber)
		end
	end
	-- petites lampes de rampe (lueur la nuit)
	for _, xf in ipairs({ D.X0 + 1, D.X0 + 4.6, -6.6, 6.6, D.X1 - 4.6, D.X1 - 1 }) do
		do
			local x = xf
			box(self, "FootlightBody", Vector3.new(0.5, 0.26, 0.34), CFrame.new(x, TOP + 0.13, D.Z0 + 0.4) * CFrame.Angles(rad(20), 0, 0), BLACK, M.Metal)
			local lens = box(self, "FootlightLens", Vector3.new(0.38, 0.16, 0.04), CFrame.new(x, TOP + 0.17, D.Z0 + 0.58) * CFrame.Angles(rad(20), 0, 0), Color3.fromRGB(255, 226, 170), M.SmoothPlastic)
			glow(lens, Color3.fromRGB(255, 226, 170))
		end
	end
end)

-- 2. Tours du portique
step("Towers", function(self)
	local w = MusicData.TOWER_SIZE
	local s = self.Detail == "High" and 1.35 or (self.Detail == "Medium" and 1.8 or 2.6)
	local faces = self.Detail == "Low" and { 1, 3 } or { 1, 2, 3, 4 }
	for _, p in ipairs(MusicData.TRUSS_TOWERS) do
		truss(self, Vector3.new(p.X, MusicData.GROUND + 0.12, p.Z), Vector3.new(p.X, MusicData.TRUSS_H, p.Z), w, faces, s)
		-- platine au sol (lestée) et manchon en haut
		box(self, "BasePlate", Vector3.new(1.7, 0.12, 1.7), CFrame.new(p.X, MusicData.GROUND + 0.04, p.Z), STEEL, M.DiamondPlate)
		box(self, "Sleeve", Vector3.new(w + 0.12, 0.9, w + 0.12), CFrame.new(p.X, MusicData.TRUSS_H + 0.45, p.Z), ALU, M.Metal)
	end
end)

-- 3. Grill (poutres hautes) + toit + bandeau
step("Grid", function(self)
	local w = MusicData.TOWER_SIZE
	local y = MusicData.TRUSS_H + 0.45
	local T = MusicData.TRUSS_TOWERS
	local s = self.Detail == "High" and 1.4 or 2
	local faces = self.Detail == "Low" and { 3 } or { 2, 3 }
	local half = w / 2 + 0.06
	truss(self, Vector3.new(T[1].X + half, y, T[1].Z), Vector3.new(T[2].X - half, y, T[2].Z), w, faces, s)
	truss(self, Vector3.new(T[3].X + half, y, T[3].Z), Vector3.new(T[4].X - half, y, T[4].Z), w, faces, s)
	truss(self, Vector3.new(T[1].X, y, T[1].Z + half), Vector3.new(T[3].X, y, T[3].Z - half), w, faces, s)
	truss(self, Vector3.new(T[2].X, y, T[2].Z + half), Vector3.new(T[4].X, y, T[4].Z - half), w, faces, s)
	-- toit à deux pans (membrane grise), bordures
	-- (v11 : dimensions tirées des tours)
	local roofY = MusicData.TRUSS_H + 1.0
	local rise = 1.9
	local roofC = Color3.fromRGB(64, 64, 72)
	local roofW = (T[2].X - T[1].X) + 1.8
	local z0, z1 = T[1].Z - 0.9, T[3].Z + 0.9
	local zm, roofHalf = (z0 + z1) / 2, (z1 - z0) / 2
	newPart(self, "RoofFront", Vector3.new(roofW, rise, roofHalf), self.CF * CFrame.new(0, roofY + rise / 2, z0 + roofHalf / 2), roofC, M.Fabric, nil, "WedgePart")
	newPart(self, "RoofBack", Vector3.new(roofW, rise, roofHalf), self.CF * CFrame.new(0, roofY + rise / 2, z1 - roofHalf / 2) * CFrame.Angles(0, math.pi, 0), roofC, M.Fabric, nil, "WedgePart")
	box(self, "RoofRidge", Vector3.new(roofW + 0.2, 0.16, 0.36), CFrame.new(0, roofY + rise + 0.02, zm), Color3.fromRGB(210, 210, 216), M.Metal)
	box(self, "FasciaFront", Vector3.new(roofW + 0.2, 0.36, 0.12), CFrame.new(0, roofY + 0.1, z0 - 0.07), PINK, M.SmoothPlastic)
	box(self, "FasciaBack", Vector3.new(roofW + 0.2, 0.36, 0.12), CFrame.new(0, roofY + 0.1, z1 + 0.07), PINK, M.SmoothPlastic)
	box(self, "RoofUnder", Vector3.new(roofW - 0.4, 0.1, z1 - z0 - 0.4), CFrame.new(0, roofY - 0.04, zm), Color3.fromRGB(34, 34, 40), M.Fabric)
	-- bandeau "DOPAMINE LIVE" sous le grill avant
	local banner = box(self, "Banner", Vector3.new(16, 1.7, 0.08), CFrame.new(0, MusicData.TRUSS_H - 0.92, T[1].Z - 0.6), BLACK, M.Fabric)
	local g = surface(banner, Enum.NormalId.Front, 40, 0.4)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 16, 30)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(60, 20, 70), Color3.fromRGB(20, 30, 70))
	grad.Parent = bg
	label(bg, "Title", "🎵 DOPAMINE LIVE 🎵", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), Color3.fromRGB(255, 220, 240))
	for _, x in ipairs({ -7, 7 }) do
		rodW(self, "BannerTie", self.CF:PointToWorldSpace(Vector3.new(x, MusicData.TRUSS_H - 0.08, T[1].Z - 0.6)), self.CF:PointToWorldSpace(Vector3.new(x, MusicData.TRUSS_H + 0.05, T[1].Z)), 0.05, BLACK)
	end
	-- bannières verticales sur les tours de devant
	for i, p in ipairs({ T[1], T[2] }) do
		local side = box(self, "TowerBanner", Vector3.new(1.5, 6.4, 0.06), CFrame.new(p.X, 9.4, p.Z - 0.66), HOT, M.Fabric)
		local sg = surface(side, Enum.NormalId.Front, 40, 0.5)
		local fr = Instance.new("Frame")
		fr.Size = UDim2.fromScale(1, 1)
		fr.BackgroundColor3 = HOT
		fr.BorderSizePixel = 0
		fr.Parent = sg
		label(fr, "T", "🎸\n🎹\n🥁", UDim2.fromScale(0.1, 0.05), UDim2.fromScale(0.8, 0.9), WHITE)
	end
end)

-- 4. Rideau de fond plissé + écran LED
step("Backdrop", function(self)
	local h = MusicData.TRUSS_H - 0.2
	local z = D.Z1 + 0.25
	local n = self.Detail == "Low" and 8 or 17
	local w = (D.X1 - D.X0) / n
	for i = 0, n - 1 do
		local depth = (i % 2 == 0) and 0.1 or 0.2
		local front = (i % 2 == 0) and z or z - 0.05
		box(self, "Drape", Vector3.new(w + 0.02, h, depth), CFrame.new(D.X0 + (i + 0.5) * w, 0.02 + h / 2, front + depth / 2), (i % 2 == 0) and FABRIC or FABRIC2, M.Fabric)
	end
	-- écran LED 16:9 (16 x 9) dans un cadre
	local sy = 8.6
	local zf = D.Z1 + 0.12
	box(self, "ScreenFrame", Vector3.new(16.5, 9.5, 0.3), CFrame.new(0, sy, zf), BLACK, M.Metal)
	local panel = box(self, "Screen", Vector3.new(16, 9, 0.05), CFrame.new(0, sy, zf - 0.17), Color3.fromRGB(6, 6, 10), M.Glass)
	for _, x in ipairs({ -7, 7 }) do
		rodW(self, "ScreenHang", self.CF:PointToWorldSpace(Vector3.new(x, sy + 4.75, zf)), self.CF:PointToWorldSpace(Vector3.new(x, MusicData.TRUSS_H + 0.1, MusicData.TRUSS_TOWERS[3].Z)), 0.06, STEEL, M.Metal)
	end
	local g = surface(panel, Enum.NormalId.Front, 40, 0)
	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(12, 8, 26)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Name = "Grad"
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 20, 90)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(20, 16, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 50, 90)),
	})
	grad.Rotation = 30
	grad.Parent = bg
	local title = label(bg, "Title", "🎵 DOPAMINE LIVE", UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.88, 0.2), WHITE)
	local sub = label(bg, "Sub", "", UDim2.fromScale(0.1, 0.32), UDim2.fromScale(0.8, 0.1), Color3.fromRGB(255, 200, 235), Enum.Font.GothamBold)
	local barsHolder = Instance.new("Frame")
	barsHolder.Name = "Bars"
	barsHolder.BackgroundTransparency = 1
	barsHolder.Position = UDim2.fromScale(0.06, 0.46)
	barsHolder.Size = UDim2.fromScale(0.88, 0.42)
	barsHolder.Parent = bg
	local bars = {}
	local count = 24
	for i = 1, count do
		local b = Instance.new("Frame")
		b.Name = "Bar"
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.fromScale((i - 1) / count + 0.006, 1)
		b.Size = UDim2.fromScale(1 / count - 0.012, 0.06)
		b.BorderSizePixel = 0
		b.BackgroundColor3 = Color3.fromHSV(0.85 - 0.5 * (i - 1) / count, 0.6, 1)
		b.Parent = barsHolder
		bars[i] = b
	end
	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.Position = UDim2.fromScale(0.06, 0.92)
	progress.Size = UDim2.fromScale(0, 0.02)
	progress.BorderSizePixel = 0
	progress.BackgroundColor3 = PINK
	progress.Parent = bg
	-- trame des modules LED (fines lignes)
	for i = 1, 7 do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Position = UDim2.fromScale(i / 8, 0)
		line.BackgroundColor3 = Color3.new(0, 0, 0)
		line.BackgroundTransparency = 0.55
		line.BorderSizePixel = 0
		line.Parent = bg
	end
	for i = 1, 3 do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.fromScale(0, i / 4)
		line.BackgroundColor3 = Color3.new(0, 0, 0)
		line.BackgroundTransparency = 0.55
		line.BorderSizePixel = 0
		line.Parent = bg
	end
	self.H.Screen = { Part = panel, Title = title, Sub = sub, Bars = bars, Progress = progress, Grad = grad }
end)

-- 5. Sono : piles au sol + line arrays suspendus
step("PA", function(self)
	for i, p in ipairs(MusicData.PA) do
		local s = i == 1 and 1 or -1 -- (tourne un peu vers le centre)
		local base = self.CF * CFrame.new(p.X, MusicData.GROUND, p.Z) * CFrame.Angles(0, rad(-12 * s), 0)
		newPart(self, "Sub", Vector3.new(2.2, 1.9, 1.9), base * CFrame.new(0, 0.95, 0), BLACK, M.Fabric).CastShadow = true
		for k = -1, 1, 2 do
			cylW(self, "Woofer", (base * CFrame.new(k * 0.52, 0.95, -0.95)).Position, base.LookVector, 0.06, 0.86, Color3.fromRGB(44, 44, 50), M.Rubber)
			cylW(self, "Cone", (base * CFrame.new(k * 0.52, 0.95, -0.99)).Position, base.LookVector, 0.04, 0.62, Color3.fromRGB(58, 58, 64), M.SmoothPlastic)
			ballW(self, "DustCap", (base * CFrame.new(k * 0.52, 0.95, -0.99)).Position, 0.22, Color3.fromRGB(30, 30, 34), M.SmoothPlastic)
		end
		local top = base * CFrame.new(0, 1.9 + 1.2 + 0.01, 0.1)
		newPart(self, "Top", Vector3.new(1.6, 2.4, 1.4), top, BLACK, M.Fabric).CastShadow = true
		newPart(self, "Grill", Vector3.new(1.46, 2.26, 0.04), top * CFrame.new(0, 0, -0.71), Color3.fromRGB(40, 40, 46), M.DiamondPlate)
		newPart(self, "Horn", Vector3.new(1.0, 0.5, 0.05), top * CFrame.new(0, 0.62, -0.74), Color3.fromRGB(22, 22, 26), M.SmoothPlastic)
		cylW(self, "TopWoofer", (top * CFrame.new(0, -0.35, -0.74)).Position, base.LookVector, 0.04, 1.0, Color3.fromRGB(28, 28, 32), M.Rubber)
		local logo = newPart(self, "Logo", Vector3.new(0.5, 0.12, 0.03), top * CFrame.new(0, -1.02, -0.745), CHROME, M.Metal)
		logo.Name = "Logo"
	end
	-- line arrays accrochés au grill avant (courbe en J)
	for _, x in ipairs({ -13.6, 13.6 }) do
		local zc = MusicData.TRUSS_TOWERS[1].Z
		local hang = self.CF * CFrame.new(x, MusicData.TRUSS_H - 0.35, zc - 0.15)
		newPart(self, "ArrayFrame", Vector3.new(1.9, 0.14, 1.1), hang, STEEL, M.Metal)
		for k = -1, 1, 2 do
			rodW(self, "ArrayChain", (hang * CFrame.new(k * 0.8, 0, 0)).Position, (self.CF * CFrame.new(x + k * 0.8, MusicData.TRUSS_H, zc)).Position, 0.05, STEEL, M.Metal)
		end
		local cf = hang * CFrame.new(0, -0.1, 0)
		for k = 1, 6 do
			local tilt = rad(2 + 2.6 * k)
			cf = cf * CFrame.Angles(tilt * 0.5, 0, 0) * CFrame.new(0, -0.3, 0)
			local cab = cf * CFrame.new(0, 0, 0.02)
			newPart(self, "ArrayBox", Vector3.new(1.9, 0.55, 1.05), cab, BLACK, M.Fabric)
			newPart(self, "ArrayGrill", Vector3.new(1.8, 0.46, 0.04), cab * CFrame.new(0, 0, -0.53), Color3.fromRGB(42, 42, 48), M.DiamondPlate)
			cf = cf * CFrame.Angles(tilt * 0.5, 0, 0) * CFrame.new(0, -0.3, 0)
		end
	end
	-- émetteur de la radio (centre, en hauteur)
	local radio = newPart(self, "RadioEmitter", Vector3.new(0.4, 0.4, 0.4), self.CF * CFrame.new(0, 9, -4.4), WHITE)
	radio.Transparency = 1
	self.H.Radio = radio
end)

-- 6. Éclairage : PAR sur le grill avant, lyres motorisées sur le grill arrière
step("Lights", function(self)
	local T = MusicData.TRUSS_TOWERS
	local pars = {}
	local colors = { PINK, CYAN, Color3.fromRGB(255, 214, 120), LILAC, Color3.fromRGB(255, 214, 120), CYAN }
	for i, x in ipairs({ -11, -6.6, -2.2, 2.2, 6.6, 11 }) do
		local clampCF = self.CF * CFrame.new(x, MusicData.TRUSS_H - 0.08, T[1].Z)
		newPart(self, "ParClamp", Vector3.new(0.18, 0.3, 0.3), clampCF, STEEL, M.Metal)
		local aim = clampCF * CFrame.new(0, -0.55, 0) * CFrame.Angles(rad(-35), 0, 0)
		newPart(self, "ParYoke", Vector3.new(0.72, 0.08, 0.1), clampCF * CFrame.new(0, -0.2, 0), STEEL, M.Metal)
		cylW(self, "ParCan", aim.Position, -aim.UpVector, 0.85, 0.5, BLACK, M.Metal)
		local lens = cylW(self, "ParLens", (aim * CFrame.new(0, -0.45, 0)).Position, -aim.UpVector, 0.03, 0.4, colors[i], M.Glass)
		glow(lens, colors[i])
		table.insert(pars, lens)
	end
	self.H.Pars = pars
	local heads = {}
	for i, x in ipairs({ -10.5, -3.5, 3.5, 10.5 }) do
		local baseCF = self.CF * CFrame.new(x, MusicData.TRUSS_H - 0.1, T[3].Z - 0.2)
		newPart(self, "HeadBase", Vector3.new(0.7, 0.3, 0.7), baseCF, BLACK, M.Metal)
		local yoke = newPart(self, "HeadYoke", Vector3.new(0.78, 0.1, 0.24), baseCF * CFrame.new(0, -0.22, 0), BLACK, M.Metal)
		local armL = newPart(self, "HeadArm", Vector3.new(0.08, 0.6, 0.22), baseCF * CFrame.new(-0.36, -0.5, 0), BLACK, M.Metal)
		local armR = newPart(self, "HeadArm", Vector3.new(0.08, 0.6, 0.22), baseCF * CFrame.new(0.36, -0.5, 0), BLACK, M.Metal)
		local head = newPart(self, "Head", Vector3.new(0.62, 0.5, 0.5), baseCF * CFrame.new(0, -0.72, 0), Color3.fromRGB(34, 34, 40), M.Metal)
		local lens = newPart(self, "HeadLens", Vector3.new(0.04, 0.36, 0.36), baseCF * CFrame.new(0, -0.98, 0) * CFrame.Angles(0, 0, rad(90)), colors[i + 1], M.Glass, CYL)
		glow(lens, colors[i + 1])
		-- faisceau (Beam) : visible la nuit quand la musique joue
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamFrom"
		a0.CFrame = CFrame.new()
		a0.Parent = lens
		local target = newPart(self, "BeamTarget", Vector3.new(0.2, 0.2, 0.2), self.CF * CFrame.new(x * 0.6, TOP, 1), WHITE)
		target.Transparency = 1
		local a1 = Instance.new("Attachment")
		a1.Name = "BeamTo"
		a1.CFrame = CFrame.new()
		a1.Parent = target
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 0.35
		beam.Width1 = 2.6
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(colors[i + 1])
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.95) })
		beam.Segments = 1
		beam.Enabled = false
		beam.Parent = lens
		table.insert(heads, { Base = baseCF, Yoke = yoke, Arms = { armL, armR }, Head = head, Lens = lens, Beam = beam, Target = target, X = x, Phase = i * 1.3 })
	end
	self.H.Heads = heads
end)

-- 7. Retours de scène + pieds de micro
local function micStand(self: any, base: Vector3, mouth: Vector3)
	local B = self.CF:PointToWorldSpace(base)
	local hubY = 0.55
	for k = 0, 2 do
		local a = rad(k * 120 + 30)
		rodW(self, "MicLeg", B + Vector3.new(0, hubY, 0), self.CF:PointToWorldSpace(base + Vector3.new(math.cos(a) * 0.55, 0.03, math.sin(a) * 0.55)), 0.05, BLACK, M.Metal)
	end
	local top = base + Vector3.new(0, 3.55, 0)
	rodW(self, "MicPole", B + Vector3.new(0, hubY - 0.05, 0), self.CF:PointToWorldSpace(top), 0.08, BLACK, M.Metal)
	ballW(self, "MicClutch", self.CF:PointToWorldSpace(top), 0.14, BLACK, M.Metal)
	local M0 = self.CF:PointToWorldSpace(mouth)
	local T0 = self.CF:PointToWorldSpace(top)
	local dir = (M0 - T0).Unit
	local tip = M0 - dir * 0.35
	rodW(self, "MicBoom", T0, tip - dir * 0.2, 0.06, BLACK, M.Metal)
	cylW(self, "Mic", tip - dir * 0.02, dir, 0.42, 0.13, BLACK, M.SmoothPlastic)
	ballW(self, "MicGrille", tip + dir * 0.22, 0.22, Color3.fromRGB(178, 180, 188), M.DiamondPlate)
	rodW(self, "MicCable", tip - dir * 0.22, B + Vector3.new(0.05, 0.1, 0.05), 0.035, Color3.fromRGB(16, 16, 18), M.Rubber)
end

step("Monitors", function(self)
	for _, x in ipairs({ -2.9, 1.3, 8.0 }) do
		-- retour "wedge" : la pente regarde les musiciens (+Z)
		local cf = self.CF * CFrame.new(x, TOP + 0.4, -3.6) * CFrame.Angles(0, math.pi, 0)
		newPart(self, "Wedge", Vector3.new(1.4, 0.8, 0.8), cf, BLACK, M.Fabric, nil, "WedgePart")
		newPart(self, "WedgeGrill", Vector3.new(1.2, 0.04, 0.72), cf * CFrame.new(0, 0.025, -0.025) * CFrame.Angles(-math.atan2(0.8, 0.8), 0, 0), Color3.fromRGB(44, 44, 50), M.DiamondPlate)
	end
	micStand(self, Vector3.new(-0.2, TOP, -2.45), Vector3.new(-0.2, TOP + 4.45, -1.6))
	micStand(self, Vector3.new(-1.6, TOP, -2.55), Vector3.new(-1.6, TOP + 4.45, -2.0))
	micStand(self, Vector3.new(5.5, TOP, 0.6), Vector3.new(4.3, TOP + 4.45, 1.2))
end)

-- 8. Juke-box (au sol, devant la scène)
step("Jukebox", function(self)
	local kf = self.CF * MusicData.JUKEBOX * CFrame.new(0, MusicData.GROUND, 0)
	local body = newPart(self, "JukeBody", Vector3.new(2.4, 2.1, 1.2), kf * CFrame.new(0, 1.05, 0), WALNUT, M.Wood)
	body.CastShadow = true
	local arch = newPart(self, "JukeArch", Vector3.new(1.2, 2.4, 2.4), kf * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, rad(90), 0), WALNUT, M.Wood, CYL)
	arch.CastShadow = true
	local window = newPart(self, "JukeWindow", Vector3.new(0.04, 1.7, 1.7), kf * CFrame.new(0, 2.3, -0.68) * CFrame.Angles(0, rad(90), 0), Color3.fromRGB(150, 200, 230), M.Glass, CYL)
	window.Transparency = 0.35
	newPart(self, "JukeRecord", Vector3.new(0.03, 1.0, 1.0), kf * CFrame.new(0, 2.3, -0.615) * CFrame.Angles(0, rad(90), 0), EBONY, M.SmoothPlastic, CYL)
	newPart(self, "JukeLabel", Vector3.new(0.02, 0.34, 0.34), kf * CFrame.new(0, 2.3, -0.645) * CFrame.Angles(0, rad(90), 0), PINK, M.SmoothPlastic, CYL)
	-- tube néon en arc autour de la vitre
	local n = 9
	for i = 0, n - 1 do
		local a0 = rad(180 * i / n)
		local a1 = rad(180 * (i + 1) / n)
		local r = 1.08
		local p0 = (kf * CFrame.new(math.cos(a0) * r, 2.1 + math.sin(a0) * r, -0.69)).Position
		local p1 = (kf * CFrame.new(math.cos(a1) * r, 2.1 + math.sin(a1) * r, -0.69)).Position
		glow(rodW(self, "JukeNeon", p0, p1, 0.1, i % 2 == 0 and PINK or CYAN, M.SmoothPlastic), i % 2 == 0 and PINK or CYAN)
	end
	-- colonnes à bulles
	for _, x in ipairs({ -1.12, 1.12 }) do
		local tube = newPart(self, "JukeTube", Vector3.new(1.9, 0.3, 0.3), kf * CFrame.new(x, 1.05, -0.5) * CFrame.Angles(0, 0, rad(90)), LILAC, M.Glass, CYL)
		tube.Transparency = 0.25
		glow(tube, LILAC)
	end
	-- panneau des choix (texte), grille du haut-parleur, fente à pièces
	local panel = newPart(self, "JukePanel", Vector3.new(1.7, 0.5, 0.06), kf * CFrame.new(0, 1.05, -0.64) * CFrame.Angles(rad(-12), 0, 0), Color3.fromRGB(255, 244, 226), M.SmoothPlastic)
	local g = surface(panel, Enum.NormalId.Front, 60, 0.4)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(255, 244, 226)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local l = label(bg, "Text", "🎵 [E] Songs  ·  📻 [F] Radio", UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), Color3.fromRGB(120, 60, 90))
	l:SetAttribute("LocText", "🎵 [E] Songs  ·  📻 [F] Radio")
	self.H.JukeText = l
	newPart(self, "JukeGrill", Vector3.new(1.8, 0.55, 0.05), kf * CFrame.new(0, 0.45, -0.62), Color3.fromRGB(200, 186, 160), M.DiamondPlate)
	newPart(self, "JukeChrome", Vector3.new(2.3, 0.08, 0.08), kf * CFrame.new(0, 1.38, -0.62), CHROME, M.Metal)
	newPart(self, "JukeBase", Vector3.new(2.5, 0.14, 1.3), kf * CFrame.new(0, 0.04, 0), CHROME, M.Metal)
	self.H.Emitters = self.H.Emitters or {}
end)

----------------------------------------------------------------------
-- 🎹 Piano à queue
----------------------------------------------------------------------

-- Contour du côté droit (aigus, vers le public) de la caisse : (x, z), z vers la queue
local OUTLINE = {
	{ 2.2, -0.6 },
	{ 2.2, -1.9 },
	{ 2.08, -2.55 },
	{ 1.75, -3.2 },
	{ 1.2, -3.85 },
	{ 0.55, -4.45 },
	{ -0.15, -4.95 },
	{ -0.8, -5.35 },
	{ -1.45, -5.58 },
	{ -1.95, -5.62 },
	{ -2.2, -5.45 },
}
local LEFT_X = -2.2
local KW = 3.64 -- clavier de 88 touches
local PITCH = KW / 52

MusicStageBuild.PIANO_KEY_TOP = 2.2

local function isBlack(n: number): boolean
	local pc = n % 12
	return pc == 1 or pc == 3 or pc == 6 or pc == 8 or pc == 10
end
MusicStageBuild.IsBlack = isBlack

-- Nombre de touches blanches strictement sous `n` à partir de `low`
local function whiteIndex(n: number, low: number): number
	local count = 0
	for k = low, n - 1 do
		if not isBlack(k) then
			count += 1
		end
	end
	return count
end

-- Remplit la forme de la caisse (bord gauche droit, côté droit en courbe)
-- à la hauteur y, épaisseur t, mise à l'échelle (s) autour du centre
local function fillCase(self: any, frame: CFrame, y: number, t: number, s: number, color: Color3, material: Enum.Material, name: string, zCut: number?)
	local cx, cz = 0, -3.1
	local function P(x: number, z: number): (number, number)
		return cx + (x - cx) * s, cz + (z - cz) * s
	end
	local left = cx + (LEFT_X - cx) * s
	for i = 1, #OUTLINE - 1 do
		local x1, z1 = P(OUTLINE[i][1], OUTLINE[i][2])
		local x2, z2 = P(OUTLINE[i + 1][1], OUTLINE[i + 1][2])
		if zCut and z1 > zCut then
			-- (morceau coupé devant : couvercle qui ne couvre pas le clavier)
			if z2 >= zCut then
				continue
			end
			local k = (zCut - z1) / (z2 - z1)
			x1, z1 = x1 + (x2 - x1) * k, zCut
		end
		local xmin = math.min(x1, x2)
		if xmin - left > 0.02 and z1 - z2 > 0.02 then
			newPart(self, name, Vector3.new(xmin - left, t, z1 - z2), frame * CFrame.new((left + xmin) / 2, y, (z1 + z2) / 2), color, material)
		end
		if x1 > x2 then
			tri(self, name, frame, Vector3.new(x2, y, z1), Vector3.new(1, 0, 0), x1 - x2, Vector3.new(0, 0, -1), z1 - z2, t, color, material)
		elseif x2 > x1 then
			tri(self, name, frame, Vector3.new(x1, y, z2), Vector3.new(1, 0, 0), x2 - x1, Vector3.new(0, 0, 1), z1 - z2, t, color, material)
		end
	end
end

step("PianoCase", function(self)
	-- repère du piano : origine au sol sous le bord des touches, -Z = vers la
	-- queue (le pianiste regarde -Z), +X = aigus (vers le public)
	local pfp = MusicData.PIANO_FRAME
	local pf = self.CF * CFrame.new(pfp.X, TOP, pfp.Z) * CFrame.Angles(0, rad(90), 0)
	self.H.Frames.Piano = pf
	local refl = self.Detail == "High" and 0.12 or 0.06
	-- éclisse (bord vertical de la caisse)
	local ring = { { LEFT_X, -0.6 } }
	for i = #OUTLINE, 1, -1 do
		table.insert(ring, OUTLINE[i])
	end
	for i = 1, #ring - 1 do
		local a = Vector3.new(ring[i][1], 2.475, ring[i][2])
		local b = Vector3.new(ring[i + 1][1], 2.475, ring[i + 1][2])
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		local cf = pf * CFrame.lookAt(mid, b)
		local rim = newPart(self, "Rim", Vector3.new(0.14, 0.95, len + 0.02), cf, LACQUER, M.SmoothPlastic)
		rim.Reflectance = refl
		rim.CastShadow = true
		local joint = newPart(self, "RimJoint", Vector3.new(0.95, 0.14, 0.14), pf * CFrame.new(b) * CFrame.Angles(0, 0, rad(90)), LACQUER, M.SmoothPlastic, CYL)
		joint.Reflectance = refl
	end
	-- fond, table d'harmonie (épicéa), cadre doré, cordes
	fillCase(self, pf, 2.04, 0.08, 1, LACQUER, M.SmoothPlastic, "CaseBottom")
	fillCase(self, pf, 2.55, 0.05, 0.955, SPRUCE, M.Wood, "Soundboard")
	fillCase(self, pf, 2.63, 0.05, 0.84, GOLD, M.Metal, "Plate")
	for _, h in ipairs({ { -0.9, -1.6 }, { 0.3, -2.2 }, { -0.5, -3.4 }, { -1.3, -4.3 } }) do
		newPart(self, "PlateHole", Vector3.new(0.04, 0.36, 0.36), pf * CFrame.new(h[1], 2.66, h[2]) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(150, 116, 60), M.Metal, CYL)
	end
	if self.Detail ~= "Low" then
		local n = self.Detail == "High" and 20 or 12
		for i = 0, n - 1 do
			local x = -1.95 + i * (3.6 / (n - 1))
			-- longueur : jusqu'au contour (moins une marge)
			local zEnd = -5.3
			for k = 1, #OUTLINE - 1 do
				local a, b = OUTLINE[k], OUTLINE[k + 1]
				if (x <= a[1] and x >= b[1]) and a[1] ~= b[1] then
					zEnd = a[2] + (b[2] - a[2]) * (a[1] - x) / (a[1] - b[1]) + 0.45
				end
			end
			local z0 = -1.0
			local len = math.max(0.5, z0 - zEnd)
			local copper = i < n * 0.35
			newPart(self, "String", Vector3.new(0.018, 0.018, len), pf * CFrame.new(x, 2.68, z0 - len / 2), copper and Color3.fromRGB(196, 130, 80) or Color3.fromRGB(220, 222, 230), M.Metal)
		end
	end
	-- couvercle ouvert (charnière côté gauche, béquille côté public)
	local angle = rad(34)
	local lidFrame = pf * CFrame.new(LEFT_X, 2.99, 0) * CFrame.Angles(0, 0, angle) * CFrame.new(-LEFT_X, 0, 0)
	fillCase(self, lidFrame, 0, 0.07, 1.0, LACQUER, M.SmoothPlastic, "Lid", -1.25)
	for _, d in ipairs(self.Group:GetChildren()) do
		if d.Name == "Lid" and d:IsA("BasePart") then
			d.Reflectance = refl
			d.CastShadow = true
		end
	end
	local r = 3.25
	local stickTop = Vector3.new(LEFT_X + r * math.cos(angle) + 0.02, 2.99 + r * math.sin(angle) - 0.06, -2.6)
	rodW(self, "LidProp", pf:PointToWorldSpace(Vector3.new(1.95, 2.96, -2.6)), pf:PointToWorldSpace(stickTop), 0.07, LACQUER, M.SmoothPlastic)
	-- pieds (3) avec roulettes laiton, lyre et pédales
	for _, p in ipairs({ { -1.9, -0.95 }, { 1.9, -0.95 }, { -1.25, -4.85 } }) do
		local x, z = p[1], p[2]
		newPart(self, "LegTop", Vector3.new(0.46, 0.22, 0.46), pf * CFrame.new(x, 1.9, z), LACQUER, M.SmoothPlastic)
		newPart(self, "Leg", Vector3.new(0.3, 1.5, 0.3), pf * CFrame.new(x, 1.04, z), LACQUER, M.SmoothPlastic).Reflectance = refl
		newPart(self, "LegFoot", Vector3.new(0.36, 0.14, 0.36), pf * CFrame.new(x, 0.26, z), LACQUER, M.SmoothPlastic)
		newPart(self, "Caster", Vector3.new(0.14, 0.2, 0.2), pf * CFrame.new(x, 0.1, z) * CFrame.Angles(0, rad(90), 0), BRASS, M.Metal, CYL)
	end
	newPart(self, "PedalBox", Vector3.new(1.0, 0.2, 0.36), pf * CFrame.new(0, 0.24, -0.8), LACQUER, M.SmoothPlastic)
	for _, x in ipairs({ -0.3, 0.3 }) do
		newPart(self, "Lyre", Vector3.new(0.08, 1.68, 0.24), pf * CFrame.new(x, 1.18, -0.8), LACQUER, M.SmoothPlastic)
	end
	for _, x in ipairs({ -0.2, 0, 0.2 }) do
		newPart(self, "Pedal", Vector3.new(0.09, 0.05, 0.36), pf * CFrame.new(x, 0.27, -0.45), BRASS, M.Metal)
	end
	-- banquette capitonnée
	local bench = pf * CFrame.new(0, 0, 1.2)
	newPart(self, "BenchSeat", Vector3.new(1.9, 0.22, 0.64), bench * CFrame.new(0, 1.35, 0), BLACK, M.Leather)
	newPart(self, "BenchFrame", Vector3.new(1.98, 0.14, 0.7), bench * CFrame.new(0, 1.17, 0), LACQUER, M.SmoothPlastic)
	for _, x in ipairs({ -0.85, 0.85 }) do
		for _, z in ipairs({ -0.25, 0.25 }) do
			newPart(self, "BenchLeg", Vector3.new(0.12, 1.1, 0.12), bench * CFrame.new(x, 0.55, z), LACQUER, M.SmoothPlastic)
		end
		newPart(self, "BenchKnob", Vector3.new(0.1, 0.2, 0.2), bench * CFrame.new(x * 1.2, 1.17, 0), BRASS, M.Metal, CYL)
	end
	if self.Detail ~= "Low" then
		for _, x in ipairs({ -0.5, 0, 0.5 }) do
			ballW(self, "Tuft", (bench * CFrame.new(x, 1.46, 0)).Position, 0.05, Color3.fromRGB(40, 40, 46), M.Leather)
		end
	end
end)

step("PianoKeys", function(self)
	local pf = self.H.Frames.Piano
	local keys = {}
	local top = MusicStageBuild.PIANO_KEY_TOP
	-- lit du clavier, joues, barre de devant, pupitre et partition
	newPart(self, "KeyBed", Vector3.new(KW, 0.16, 0.62), pf * CFrame.new(0, top - 0.17, -0.31), EBONY, M.SmoothPlastic)
	newPart(self, "KeySlip", Vector3.new(KW + 0.02, 0.14, 0.05), pf * CFrame.new(0, top - 0.12, 0.03), LACQUER, M.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		newPart(self, "Cheek", Vector3.new(0.38, 0.34, 0.66), pf * CFrame.new(s * (KW / 2 + 0.19), top - 0.03, -0.33), LACQUER, M.SmoothPlastic).Reflectance = 0.08
	end
	local fall = newPart(self, "Fallboard", Vector3.new(KW, 0.34, 0.06), pf * CFrame.new(0, top + 0.21, -0.53), LACQUER, M.SmoothPlastic)
	local g = surface(fall, Enum.NormalId.Back, 80, 0.6)
	label(g, "Brand", "Dopamine & Sons", UDim2.fromScale(0.35, 0.3), UDim2.fromScale(0.3, 0.4), GOLD, Enum.Font.Fantasy)
	local desk = pf * CFrame.new(0, top + 0.72, -0.74) * CFrame.Angles(rad(12), 0, 0)
	newPart(self, "MusicDesk", Vector3.new(2.3, 0.76, 0.06), desk, LACQUER, M.SmoothPlastic)
	local sheet = newPart(self, "Sheet", Vector3.new(1.3, 0.56, 0.02), desk * CFrame.new(0, 0.02, 0.045), IVORY, M.SmoothPlastic)
	local sg = surface(sheet, Enum.NormalId.Back, 80, 0.6)
	for i = 1, 4 do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(0.9, 0, 0, 1)
		line.Position = UDim2.fromScale(0.05, i * 0.2)
		line.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		line.BorderSizePixel = 0
		line.Parent = sg
	end
	-- 88 touches (La0 21 .. Do8 108)
	for n = 21, 108 do
		local cf: CFrame
		local part: BasePart
		if isBlack(n) then
			local x = -KW / 2 + whiteIndex(n, 21) * PITCH
			cf = pf * CFrame.new(x, top + 0.01, -0.31)
			part = newPart(self, "Key", Vector3.new(0.04, 0.1, 0.3), cf, EBONY, M.SmoothPlastic)
		else
			local x = -KW / 2 + (whiteIndex(n, 21) + 0.5) * PITCH
			cf = pf * CFrame.new(x, top - 0.045, -0.25)
			part = newPart(self, "Key", Vector3.new(PITCH - 0.007, 0.09, 0.5), cf, IVORY, M.SmoothPlastic)
		end
		keys[n] = { Part = part, CF = cf, Top = (cf * CFrame.new(0, 0.06, 0.1)).Position }
	end
	self.H.Keys.Piano = keys
	local emitter = newPart(self, "PianoEmitter", Vector3.new(0.3, 0.3, 0.3), pf * CFrame.new(0, 3, -2.5), WHITE)
	emitter.Transparency = 1
	self.H.Emitters.Piano = emitter
	-- bloc de collision local (on ne traverse pas le piano)
	local block = newPart(self, "Block", Vector3.new(4.4, 1.3, 5.0), pf * CFrame.new(0, 2.5, -3.1), WHITE)
	block.Transparency = 1
	block.CanCollide = true
	-- (v11) piano à l'échelle Roblox : x1,3 autour du bord du clavier
	local k = MusicData.PIANO_SCALE
	scaleGroup(self.Model:FindFirstChild("PianoCase"), pf, k)
	scaleGroup(self.Group, pf, k)
	for _, key in pairs(keys) do
		key.CF = key.Part.CFrame
		key.Top = MusicData.ScalePoint(pf, k, key.Top)
	end
end)

----------------------------------------------------------------------
-- 🥁 Batterie
----------------------------------------------------------------------

-- Fût : coque + cercles chromés + peaux ; axe = `axis` (monde), `top` =
-- sens de la peau de frappe ; renvoie les pièces (pour la vibration)
local function drum(self: any, name: string, c: Vector3, axis: Vector3, depth: number, dia: number, lugs: number): { BasePart }
	local list = {}
	local a = axis.Unit
	local shell = cylW(self, name .. "Shell", c, a, depth, dia, SHELL, M.SmoothPlastic)
	shell.Reflectance = self.Detail == "High" and 0.16 or 0.08
	table.insert(list, shell)
	for _, s in ipairs({ -1, 1 }) do
		table.insert(list, cylW(self, name .. "Hoop", c + a * s * (depth / 2 + 0.01), a, 0.07, dia + 0.06, CHROME, M.Metal))
		table.insert(list, cylW(self, name .. "Head", c + a * s * (depth / 2 + 0.07), a, 0.012, dia - 0.02, HEAD, M.SmoothPlastic))
	end
	if self.Detail ~= "Low" then
		local up = math.abs(a.Y) > 0.9 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		local u = a:Cross(up).Unit
		local v = a:Cross(u).Unit
		for k = 0, lugs - 1 do
			local ang = (k + 0.5) * math.pi * 2 / lugs
			local dir = u * math.cos(ang) + v * math.sin(ang)
			local p = c + dir * (dia / 2 + 0.025)
			local cf = CFrame.fromMatrix(p, dir, a, dir:Cross(a))
			table.insert(list, newPart(self, name .. "Lug", Vector3.new(0.05, math.min(depth * 0.36, 0.26), 0.07), cf, CHROME, M.Metal))
		end
	end
	return list
end

local function cymbal(self: any, name: string, c: Vector3, normal: Vector3, dia: number, standBase: Vector3?): { BasePart }
	local list = {}
	local n = normal.Unit
	local disc = cylW(self, name, c, n, 0.035, dia, BRONZE, M.Metal)
	disc.Reflectance = 0.22
	table.insert(list, disc)
	table.insert(list, cylW(self, name .. "Bell", c + n * 0.05, n, 0.07, dia * 0.28, BRONZE, M.Metal))
	if standBase then
		rodW(self, name .. "Stand", standBase + Vector3.new(0, 0.5, 0), c - n * 0.05, 0.07, CHROME, M.Metal)
		for k = 0, 2 do
			local ang = rad(k * 120 + 15)
			rodW(self, name .. "Leg", standBase + Vector3.new(0, 0.5, 0), standBase + Vector3.new(math.cos(ang) * 0.6, 0.02, math.sin(ang) * 0.6), 0.05, CHROME, M.Metal)
		end
	end
	return list
end

step("Drums", function(self)
	local y0 = TOP + MusicData.RISERS.Drums.H
	local df = self.CF * CFrame.new(0, y0, 0)
	self.H.Frames.Drums = df
	local W = function(x: number, y: number, z: number): Vector3
		return df:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local fwd = df:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local up = df:VectorToWorldSpace(Vector3.new(0, 1, 0))
	local pieces: { [number]: any } = {}
	-- tapis
	newPart(self, "DrumRug", Vector3.new(5.2, 0.04, 3.8), df * CFrame.new(0.2, 0, 5.4), Color3.fromRGB(128, 44, 58), M.Fabric)
	newPart(self, "DrumRugBorder", Vector3.new(4.8, 0.09, 3.4), df * CFrame.new(0.2, 0, 5.4), Color3.fromRGB(176, 120, 70), M.Fabric)
	newPart(self, "DrumRugCenter", Vector3.new(4.4, 0.14, 3.0), df * CFrame.new(0.2, 0, 5.4), Color3.fromRGB(110, 36, 50), M.Fabric)
	-- grosse caisse (peau avant noire avec logo)
	local kc = W(0.25, 0.86, 4.75)
	local kick = drum(self, "Kick", kc, fwd, 1.2, 1.66, 8)
	local front = cylW(self, "KickLogo", kc + fwd * 0.7, fwd, 0.012, 1.5, EBONY, M.SmoothPlastic)
	local g = surface(front, Enum.NormalId.Right, 60, 0.6)
	local logo = Instance.new("Frame")
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.5)
	logo.Size = UDim2.fromScale(0.62, 0.62)
	logo.BackgroundColor3 = PINK
	logo.BorderSizePixel = 0
	logo.Parent = g
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = logo
	label(logo, "T", "🧠\nDopamine", UDim2.fromScale(0.12, 0.18), UDim2.fromScale(0.76, 0.64), WHITE)
	for _, s in ipairs({ -1, 1 }) do
		rodW(self, "KickSpur", W(0.25 + s * 0.7, 0.35, 4.3), W(0.25 + s * 1.0, 0.02, 4.1), 0.06, CHROME, M.Metal)
	end
	pieces[MusicData.DRUM.Kick] = { Parts = kick, Hit = W(0.25, 0.86, 5.4), Kind = "kick", Axis = fwd }
	-- pédale et batte
	newPart(self, "KickPedal", Vector3.new(0.34, 0.06, 0.9), df * CFrame.new(0.25, 0.1, 5.85) * CFrame.Angles(rad(8), 0, 0), CHROME, M.Metal)
	local beaterPivot = df * CFrame.new(0.25, 0.3, 5.45)
	local beater = newPart(self, "Beater", Vector3.new(0.06, 0.8, 0.06), beaterPivot * CFrame.Angles(rad(-25), 0, 0) * CFrame.new(0, 0.4, 0), CHROME, M.Metal)
	-- caisse claire (sur son pied), toms, tom basse
	local snareC = W(-0.72, 1.72, 5.55)
	local tiltToDrummer = (up * math.cos(rad(8)) - fwd * math.sin(rad(8))).Unit
	local snare = drum(self, "Snare", snareC, tiltToDrummer, 0.42, 1.04, 6)
	snare[1].Color = CHROME
	rodW(self, "SnareStand", W(-0.72, 0.45, 5.55), snareC - tiltToDrummer * 0.25, 0.07, CHROME, M.Metal)
	for k = 0, 2 do
		local ang = rad(k * 120 + 90)
		rodW(self, "SnareLeg", W(-0.72, 0.45, 5.55), W(-0.72 + math.cos(ang) * 0.55, 0.02, 5.55 + math.sin(ang) * 0.55), 0.05, CHROME, M.Metal)
	end
	pieces[MusicData.DRUM.Snare] = { Parts = snare, Hit = snareC + tiltToDrummer * 0.25, Kind = "drum", Axis = tiltToDrummer }
	local tomTilt = (up * math.cos(rad(24)) - fwd * math.sin(rad(24))).Unit
	local tom1C = W(-0.42, 2.55, 4.85)
	local tom2C = W(0.78, 2.6, 4.85)
	pieces[MusicData.DRUM.TomHigh] = { Parts = drum(self, "TomHigh", tom1C, tomTilt, 0.6, 0.78, 6), Hit = tom1C + tomTilt * 0.33, Kind = "drum", Axis = tomTilt }
	pieces[MusicData.DRUM.TomMid] = { Parts = drum(self, "TomMid", tom2C, tomTilt, 0.66, 0.9, 6), Hit = tom2C + tomTilt * 0.36, Kind = "drum", Axis = tomTilt }
	rodW(self, "TomMount", W(0.25, 1.62, 4.75), tom1C - tomTilt * 0.25, 0.07, CHROME, M.Metal)
	rodW(self, "TomMount", W(0.25, 1.62, 4.75), tom2C - tomTilt * 0.25, 0.07, CHROME, M.Metal)
	local floorC = W(1.2, 1.35, 5.9)
	pieces[MusicData.DRUM.TomFloor] = { Parts = drum(self, "TomFloor", floorC, up, 1.1, 1.2, 8), Hit = floorC + up * 0.56, Kind = "drum", Axis = up }
	for k = 0, 2 do
		local ang = rad(k * 120 + 30)
		rodW(self, "FloorLeg", floorC + Vector3.new(0, -0.1, 0) + df:VectorToWorldSpace(Vector3.new(math.cos(ang) * 0.66, 0, math.sin(ang) * 0.66)), W(1.2 + math.cos(ang) * 0.8, 0.02, 5.9 + math.sin(ang) * 0.8), 0.05, CHROME, M.Metal)
	end
	-- charleston, crash, ride
	local hatC = W(-1.5, 2.72, 5.3)
	local hat = cymbal(self, "HatTop", hatC + up * 0.07, up, 1.0, W(-1.5, 0, 5.3))
	for _, p in ipairs(cymbal(self, "HatBottom", hatC - up * 0.02, up, 1.0, nil)) do
		table.insert(hat, p)
	end
	newPart(self, "HatPedal", Vector3.new(0.3, 0.05, 0.7), df * CFrame.new(-1.5, 0.1, 5.8) * CFrame.Angles(rad(10), 0, 0), CHROME, M.Metal)
	pieces[MusicData.DRUM.HatClosed] = { Parts = hat, Hit = hatC + up * 0.1 + df:VectorToWorldSpace(Vector3.new(0.2, 0, 0.35)), Kind = "cymbal", Axis = up }
	pieces[MusicData.DRUM.HatOpen] = pieces[MusicData.DRUM.HatClosed]
	local crashN = (up * math.cos(rad(18)) - fwd * math.sin(rad(18))).Unit
	local crashC = W(-1.3, 3.55, 4.35)
	pieces[MusicData.DRUM.Crash] = { Parts = cymbal(self, "Crash", crashC, crashN, 1.36, W(-1.6, 0, 4.0)), Hit = crashC + df:VectorToWorldSpace(Vector3.new(0.2, 0, 0.5)), Kind = "cymbal", Axis = crashN }
	local rideN = (up * math.cos(rad(12)) - fwd * math.sin(rad(12))).Unit
	local rideC = W(1.75, 3.2, 4.7)
	pieces[MusicData.DRUM.Ride] = { Parts = cymbal(self, "Ride", rideC, rideN, 1.5, W(2.2, 0, 4.4)), Hit = rideC + df:VectorToWorldSpace(Vector3.new(-0.3, 0, 0.45)), Kind = "cymbal", Axis = rideN }
	-- tabouret
	local seatC = W(0, 1.35, 6.45)
	newPart(self, "ThroneSeat", Vector3.new(0.3, 1.1, 1.1), CFrame.new(seatC) * df.Rotation * CFrame.Angles(0, 0, rad(90)), BLACK, M.Leather, CYL)
	rodW(self, "ThronePost", W(0, 0.4, 6.45), W(0, 1.2, 6.45), 0.12, CHROME, M.Metal)
	for k = 0, 2 do
		local ang = rad(k * 120 + 90)
		rodW(self, "ThroneLeg", W(0, 0.4, 6.45), W(math.cos(ang) * 0.6, 0.02, 6.45 + math.sin(ang) * 0.6), 0.06, CHROME, M.Metal)
	end
	-- baguettes (posées sur la caisse claire au repos)
	local sticks = {}
	for i, s in ipairs({ -1, 1 }) do
		local a = snareC + tiltToDrummer * 0.27 + df:VectorToWorldSpace(Vector3.new(s * 0.08 - 0.3, 0, 0.1 * i))
		local b = a + df:VectorToWorldSpace(Vector3.new(0.9, 0, -0.4 + 0.1 * s))
		sticks[s > 0 and "R" or "L"] = rodW(self, "Stick", a, b, 0.05, Color3.fromRGB(226, 196, 140), M.Wood)
	end
	-- (v11) batterie à l'échelle Roblox : x1,25 autour du centre du tapis
	local kit = MusicData.KIT_SCALE
	local kp = MusicData.KIT_PIVOT
	local pivot = df * CFrame.new(kp.X, kp.Y, kp.Z)
	scaleGroup(self.Group, pivot, kit)
	for _, piece in pairs(pieces) do
		piece.Hit = MusicData.ScalePoint(pivot, kit, piece.Hit)
	end
	beaterPivot = scaleCF(pivot, kit, beaterPivot)
	self.H.Beater = { Part = beater, Pivot = beaterPivot }
	self.H.KitPivot = pivot
	for _, piece in pairs(pieces) do
		local cfs = {}
		for i, p in ipairs(piece.Parts) do
			cfs[i] = p.CFrame
		end
		piece.CFs = cfs
		piece.Center = piece.Parts[1].Position
	end
	self.H.Sticks = sticks
	self.H.Drums = pieces
	local emitter = newPart(self, "DrumsEmitter", Vector3.new(0.3, 0.3, 0.3), df * CFrame.new(0, 2.5, 5), WHITE)
	emitter.Transparency = 1
	self.H.Emitters.Drums = emitter
	local block = newPart(self, "Block", Vector3.new(5.2, 3.2, 2.6), df * CFrame.new(0.15, 1.6, 4.35), WHITE)
	block.Transparency = 1
	block.CanCollide = true
end)

----------------------------------------------------------------------
-- 🎸 Guitare, basse (portables), amplis
----------------------------------------------------------------------

-- Construit un instrument à cordes dans son repère (X = vers la tête,
-- Z = face des cordes) ; renvoie { Parts, Rel }
local function stringed(self: any, bass: boolean, idleCF: CFrame): any
	local parts, rel = {}, {}
	local function add(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
		local p = newPart(self, name, size, idleCF * cf, color, material, shape)
		table.insert(parts, p)
		table.insert(rel, cf)
		return p
	end
	local k = bass and 1.12 or 1
	local bodyC = bass and Color3.fromRGB(70, 34, 20) or Color3.fromRGB(196, 30, 46)
	local th = 0.14
	local lower = add("BodyLower", Vector3.new(th, 1.02 * k, 1.02 * k), CFrame.new(-0.3 * k, 0, 0) * CFrame.Angles(0, rad(90), 0), bodyC, M.SmoothPlastic, CYL)
	lower.Reflectance = 0.14
	add("BodyUpper", Vector3.new(th, 0.82 * k, 0.82 * k), CFrame.new(0.25 * k, 0.02, 0) * CFrame.Angles(0, rad(90), 0), bodyC, M.SmoothPlastic, CYL).Reflectance = 0.14
	add("BodyWaist", Vector3.new(0.6 * k, 0.7 * k, th), CFrame.new(0, 0, 0), bodyC, M.SmoothPlastic).Reflectance = 0.14
	add("HornUpper", Vector3.new(th, 0.3, 0.3), CFrame.new(0.66 * k, 0.3 * k, 0) * CFrame.Angles(0, rad(90), 0), bodyC, M.SmoothPlastic, CYL)
	add("HornLower", Vector3.new(th, 0.26, 0.26), CFrame.new(0.56 * k, -0.28 * k, 0) * CFrame.Angles(0, rad(90), 0), bodyC, M.SmoothPlastic, CYL)
	if bass then
		-- dégradé "sunburst" : cœur ambré
		add("Burst", Vector3.new(0.012, 0.7, 0.7), CFrame.new(-0.3 * k, 0, 0.085) * CFrame.Angles(0, rad(90), 0), Color3.fromRGB(206, 120, 44), M.SmoothPlastic, CYL)
	end
	add("Pickguard", Vector3.new(0.012, 0.66, 0.66), CFrame.new(0.02, -0.08, bass and 0.118 or 0.095) * CFrame.Angles(0, rad(90), 0), bass and EBONY or WHITE, M.SmoothPlastic, CYL)
	for i, x in ipairs(bass and { -0.05 } or { -0.12, 0.14 }) do
		add("Pickup" .. i, Vector3.new(0.12, 0.34, 0.04), CFrame.new(x, 0, 0.1), EBONY, M.SmoothPlastic)
	end
	add("Bridge", Vector3.new(0.14, 0.34, 0.05), CFrame.new(-0.45 * k, 0, 0.1), CHROME, M.Metal)
	for i, p in ipairs({ { -0.5, -0.3 }, { -0.32, -0.38 } }) do
		add("Knob" .. i, Vector3.new(0.06, 0.09, 0.09), CFrame.new(p[1] * k, p[2] * k, 0.1) * CFrame.Angles(0, rad(90), 0), CHROME, M.Metal, CYL)
	end
	local neckLen = bass and 1.75 or 1.3
	local n0 = 0.55 * k
	add("Neck", Vector3.new(neckLen, 0.16, 0.1), CFrame.new(n0 + neckLen / 2, 0, 0.02), MAPLE, M.Wood)
	add("Fretboard", Vector3.new(neckLen, 0.17, 0.03), CFrame.new(n0 + neckLen / 2, 0, 0.085), ROSEWOOD, M.Wood)
	if self.Detail ~= "Low" then
		for f = 1, 8 do
			local x = n0 + neckLen * (1 - 0.5 ^ (f / 6)) * 1.25
			if x < n0 + neckLen - 0.03 then
				add("Fret", Vector3.new(0.014, 0.17, 0.034), CFrame.new(x, 0, 0.088), CHROME, M.Metal)
			end
		end
	end
	add("Nut", Vector3.new(0.03, 0.17, 0.05), CFrame.new(n0 + neckLen, 0, 0.09), IVORY, M.SmoothPlastic)
	local head = n0 + neckLen + 0.27
	add("Headstock", Vector3.new(0.52, 0.28, 0.06), CFrame.new(head, 0.03, 0.0), bass and bodyC or MAPLE, M.Wood)
	local tuners = bass and 4 or 6
	for t = 1, tuners do
		add("Tuner", Vector3.new(0.08, 0.06, 0.06), CFrame.new(head - 0.2 + (t - 1) * (0.42 / tuners), 0.14, 0.05) * CFrame.Angles(0, 0, rad(90)), CHROME, M.Metal, CYL)
	end
	local strings = bass and 4 or 6
	local sLen = n0 + neckLen + 0.45 * k
	for s = 1, strings do
		local y = -0.06 + (s - 1) * (0.12 / (strings - 1))
		add("String", Vector3.new(sLen, 0.012, 0.012), CFrame.new(-0.45 * k + sLen / 2, y, 0.115), Color3.fromRGB(226, 226, 232), M.Metal)
	end
	-- sangle (visible quand l'instrument est porté)
	local strapA = newPart(self, "Strap", Vector3.new(0.9, 0.16, 0.03), idleCF, Color3.fromRGB(40, 30, 30), M.Leather)
	strapA.Transparency = 1
	local strapB = newPart(self, "Strap", Vector3.new(0.9, 0.16, 0.03), idleCF, Color3.fromRGB(40, 30, 30), M.Leather)
	strapB.Transparency = 1
	return { Parts = parts, Rel = rel, Idle = idleCF, Straps = { strapA, strapB }, Bass = bass, NeckStart = n0, NeckLen = neckLen, K = k }
end

local function guitarStand(self: any, pos: Vector3)
	local base = self.CF * CFrame.new(pos)
	for _, s in ipairs({ -1, 1 }) do
		rodW(self, "StandLeg", (base * CFrame.new(s * 0.35, 0.02, -0.35)).Position, (base * CFrame.new(0, 0.4, 0)).Position, 0.06, BLACK, M.Metal)
	end
	rodW(self, "StandBack", (base * CFrame.new(0, 0.02, 0.5)).Position, (base * CFrame.new(0, 2.1, 0.12)).Position, 0.06, BLACK, M.Metal)
	newPart(self, "StandCradle", Vector3.new(0.8, 0.08, 0.22), base * CFrame.new(0, 0.34, 0), BLACK, M.Rubber)
	newPart(self, "StandYoke", Vector3.new(0.3, 0.06, 0.12), base * CFrame.new(0, 2.1, 0.12), BLACK, M.Rubber)
end

local function amp(self: any, name: string, cf: CFrame, size: Vector3, face: Color3, panel: boolean)
	local body = newPart(self, name, size, cf, BLACK, M.Leather)
	body.CastShadow = true
	local grill = newPart(self, name .. "Grill", Vector3.new(size.X - 0.2, size.Y - (panel and 0.5 or 0.2), 0.04), cf * CFrame.new(0, panel and -0.15 or 0, -size.Z / 2 - 0.02), face, M.Fabric)
	local g = surface(grill, Enum.NormalId.Front, 50, 0.7)
	label(g, "Logo", "Dopa", UDim2.fromScale(0.3, 0.05), UDim2.fromScale(0.4, 0.2), WHITE, Enum.Font.Fantasy)
	if panel then
		newPart(self, name .. "Panel", Vector3.new(size.X - 0.2, 0.26, 0.04), cf * CFrame.new(0, size.Y / 2 - 0.18, -size.Z / 2 - 0.02), GOLD, M.Metal)
		for i = 0, 5 do
			newPart(self, name .. "Knob", Vector3.new(0.06, 0.1, 0.1), cf * CFrame.new(-0.55 + i * 0.22, size.Y / 2 - 0.18, -size.Z / 2 - 0.06) * CFrame.Angles(0, rad(90), 0), EBONY, M.SmoothPlastic, CYL)
		end
		glow(newPart(self, name .. "Pilot", Vector3.new(0.06, 0.06, 0.03), cf * CFrame.new(size.X / 2 - 0.25, size.Y / 2 - 0.18, -size.Z / 2 - 0.05), Color3.fromRGB(255, 60, 60), M.SmoothPlastic), Color3.fromRGB(255, 60, 60))
	end
	newPart(self, name .. "Handle", Vector3.new(0.7, 0.06, 0.14), cf * CFrame.new(0, size.Y / 2 + 0.03, 0), EBONY, M.Leather)
	if self.Detail == "High" then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				newPart(self, name .. "Corner", Vector3.new(0.18, 0.18, 0.18), cf * CFrame.new(sx * (size.X / 2 - 0.07), sy * (size.Y / 2 - 0.07), -size.Z / 2 + 0.07), CHROME, M.Metal)
			end
		end
	end
end

step("Guitars", function(self)
	-- ampli combo de la guitare, "stack" de la basse (tournés vers le public)
	amp(self, "GuitarAmp", self.CF * CFrame.new(-1.8, TOP + 0.86, 1.8), Vector3.new(2.0, 1.7, 1.0), Color3.fromRGB(84, 74, 64), true)
	amp(self, "BassCab", self.CF * CFrame.new(4.4, TOP + 1.2, 4.25), Vector3.new(2.0, 2.4, 1.1), Color3.fromRGB(46, 46, 52), false)
	amp(self, "BassHead", self.CF * CFrame.new(4.4, TOP + 2.4 + 0.38, 4.3), Vector3.new(2.0, 0.74, 0.95), Color3.fromRGB(46, 46, 52), true)
	-- stands (guitare à droite de son ampli, basse près des toms)
	local gPos = Vector3.new(-0.3, TOP, 1.5)
	local bPos = Vector3.new(2.75, TOP, 1.0)
	guitarStand(self, gPos)
	guitarStand(self, bPos)
	-- instrument debout : tête en haut, face vers le public
	local function idle(pos: Vector3, bass: boolean): CFrame
		local lift = bass and 1.3 or 1.2
		return self.CF * CFrame.fromMatrix(pos + Vector3.new(0, lift, 0), Vector3.new(0, 1, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1))
	end
	self.H.Guitar = stringed(self, false, idle(gPos, false))
	self.H.Bass = stringed(self, true, idle(bPos, true))
	local ge = newPart(self, "GuitarEmitter", Vector3.new(0.3, 0.3, 0.3), self.CF * CFrame.new(-1.8, TOP + 1.2, 1.3), WHITE)
	ge.Transparency = 1
	self.H.Emitters.Guitar = ge
	local be = newPart(self, "BassEmitter", Vector3.new(0.3, 0.3, 0.3), self.CF * CFrame.new(4.4, TOP + 1.5, 3.6), WHITE)
	be.Transparency = 1
	self.H.Emitters.Bass = be
	for _, spec in ipairs({ { Vector3.new(-1.8, TOP + 0.86, 1.8), Vector3.new(2.0, 1.7, 1.0) }, { Vector3.new(4.4, TOP + 1.6, 4.25), Vector3.new(2.0, 3.2, 1.1) } }) do
		local block = newPart(self, "Block", spec[2], self.CF * CFrame.new(spec[1]), WHITE)
		block.Transparency = 1
		block.CanCollide = true
	end
end)

----------------------------------------------------------------------
-- 🎶 Xylophone
----------------------------------------------------------------------

MusicStageBuild.XYLO_LOW = 60
MusicStageBuild.XYLO_HIGH = 96

step("Xylophone", function(self)
	local st = MusicData.STATIONS.Xylophone
	local xf = self.CF * CFrame.new(st.Spot.Position.X, TOP, st.Spot.Position.Z - 1.05)
	self.H.Frames.Xylophone = xf
	local low, high = MusicStageBuild.XYLO_LOW, MusicStageBuild.XYLO_HIGH
	local whites = whiteIndex(high + 1, low)
	local width = 4.1
	local pitch = width / whites
	local keys = {}
	local topY = 2.72
	for n = low, high do
		local black = isBlack(n)
		local u = (n - low) / (high - low)
		local len = 0.95 - 0.4 * u
		local x: number
		local z: number
		local y: number
		if black then
			x = -width / 2 + whiteIndex(n, low) * pitch
			z = -0.62
			y = topY + 0.06
		else
			x = -width / 2 + (whiteIndex(n, low) + 0.5) * pitch
			z = 0.0
			y = topY
		end
		local cf = xf * CFrame.new(x, y - 0.035, z)
		local shade = 0.9 + 0.1 * math.sin(n * 1.7)
		local p = newPart(self, "Bar", Vector3.new(pitch * (black and 0.82 or 0.88), 0.07, len * (black and 0.8 or 1)), cf, Color3.fromRGB(math.floor(150 * shade), math.floor(72 * shade), math.floor(46 * shade)), M.Wood)
		keys[n] = { Part = p, CF = cf, Top = (cf * CFrame.new(0, 0.05, 0)).Position }
		if not black and self.Detail ~= "Low" and (self.Detail == "High" or n % 2 == 0) then
			local tube = 1.35 - 0.95 * u
			newPart(self, "Tube", Vector3.new(tube, 0.13, 0.13), xf * CFrame.new(x, topY - 0.2 - tube / 2, z) * CFrame.Angles(0, 0, rad(90)), ALU, M.Metal, CYL)
		end
	end
	-- rails, flasques, pieds à roulettes, barre
	for _, z in ipairs({ -0.62, 0.0 }) do
		for _, dz in ipairs({ -0.3, 0.3 }) do
			newPart(self, "Rail", Vector3.new(width + 0.3, 0.1, 0.06), xf * CFrame.new(0, topY - 0.12 + (z < 0 and 0.06 or 0), z + dz * (z < 0 and 0.8 or 1)), Color3.fromRGB(60, 40, 30), M.Wood)
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		local x = s * (width / 2 + 0.2)
		newPart(self, "EndBoard", Vector3.new(0.1, 0.34, 1.35), xf * CFrame.new(x, topY - 0.2, -0.3), Color3.fromRGB(60, 40, 30), M.Wood)
		for _, z in ipairs({ -0.85, 0.3 }) do
			newPart(self, "XyloLeg", Vector3.new(0.1, topY - 0.45, 0.1), xf * CFrame.new(x, (topY - 0.45) / 2 + 0.12, z), BLACK, M.Metal)
			ballW(self, "Wheel", (xf * CFrame.new(x, 0.1, z)).Position, 0.2, EBONY, M.Rubber)
		end
		newPart(self, "XyloFoot", Vector3.new(0.12, 0.08, 1.35), xf * CFrame.new(x, 0.26, -0.28), BLACK, M.Metal)
	end
	newPart(self, "XyloBrace", Vector3.new(width + 0.3, 0.08, 0.08), xf * CFrame.new(0, 0.9, -0.28), BLACK, M.Metal)
	-- baguettes (posées sur le bord)
	local mallets = {}
	for _, s in ipairs({ -1, 1 }) do
		local a = (xf * CFrame.new(s * 0.25 + 1.2, topY + 0.04, 0.55)).Position
		local b = (xf * CFrame.new(s * 0.25 + 1.8, topY + 0.04, -0.4)).Position
		local handle = rodW(self, "MalletHandle", a, b, 0.05, Color3.fromRGB(214, 180, 120), M.Wood)
		local headPart = ballW(self, "MalletHead", b, 0.17, s > 0 and PINK or LILAC, M.Fabric)
		mallets[s > 0 and "R" or "L"] = { Handle = handle, Head = headPart }
	end
	self.H.Mallets = mallets
	self.H.Keys.Xylophone = keys
	local emitter = newPart(self, "XyloEmitter", Vector3.new(0.3, 0.3, 0.3), xf * CFrame.new(0, 3, 0), WHITE)
	emitter.Transparency = 1
	self.H.Emitters.Xylophone = emitter
	local block = newPart(self, "Block", Vector3.new(4.6, 2.6, 1.5), xf * CFrame.new(0, 1.3, -0.3), WHITE)
	block.Transparency = 1
	block.CanCollide = true
end)

----------------------------------------------------------------------
-- 🎛️ Synthé
----------------------------------------------------------------------

MusicStageBuild.SYNTH_LOW = 48
MusicStageBuild.SYNTH_HIGH = 96

step("Synth", function(self)
	local st = MusicData.STATIONS.Synth
	local sf = self.CF * CFrame.new(st.Spot.Position.X, TOP, st.Spot.Position.Z - 1.0)
	self.H.Frames.Synth = sf
	local low, high = MusicStageBuild.SYNTH_LOW, MusicStageBuild.SYNTH_HIGH
	local whites = whiteIndex(high + 1, low)
	local pitch = 0.08
	local kw = whites * pitch
	local keyTop = 2.86
	local body = Color3.fromRGB(46, 48, 56)
	local width = kw + 0.75
	local left = -width / 2
	local kx0 = left + 0.55 -- (molettes à gauche)
	newPart(self, "SynthPanel", Vector3.new(width, 0.24, 0.5), sf * CFrame.new(0, keyTop - 0.02, -0.28), body, M.Metal).CastShadow = true
	newPart(self, "SynthBed", Vector3.new(width, 0.12, 0.52), sf * CFrame.new(0, keyTop - 0.15, 0.23), body, M.Metal)
	for _, x in ipairs({ left + 0.1, width / 2 - 0.1 }) do
		newPart(self, "SynthCheek", Vector3.new(0.2, 0.22, 0.52), sf * CFrame.new(x, keyTop - 0.06, 0.23), Color3.fromRGB(150, 100, 70), M.Wood)
	end
	-- molettes (pitch / modulation)
	for i = 0, 1 do
		newPart(self, "Wheel", Vector3.new(0.06, 0.3, 0.3), sf * CFrame.new(left + 0.28 + i * 0.12, keyTop - 0.02, 0.22), EBONY, M.Rubber, CYL)
	end
	-- écran, boutons, curseurs
	local screen = newPart(self, "SynthScreen", Vector3.new(0.6, 0.04, 0.24), sf * CFrame.new(-0.2, keyTop + 0.115, -0.3), Color3.fromRGB(20, 60, 60), M.Glass)
	local g = surface(screen, Enum.NormalId.Top, 100, 0)
	local lcd = Instance.new("Frame")
	lcd.Size = UDim2.fromScale(1, 1)
	lcd.BackgroundColor3 = Color3.fromRGB(40, 200, 190)
	lcd.BorderSizePixel = 0
	lcd.Parent = g
	local lcdText = label(lcd, "Text", "PAD 01", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), Color3.fromRGB(10, 40, 40), Enum.Font.Code)
	self.H.SynthLCD = lcdText
	if self.Detail ~= "Low" then
		for i = 0, 7 do
			newPart(self, "SynthKnob", Vector3.new(0.08, 0.12, 0.12), sf * CFrame.new(0.3 + i * 0.16, keyTop + 0.14, -0.35) * CFrame.Angles(0, 0, rad(90)), i % 3 == 0 and PINK or CHROME, M.SmoothPlastic, CYL)
		end
		for i = 0, 3 do
			newPart(self, "SynthSlider", Vector3.new(0.06, 0.05, 0.14), sf * CFrame.new(-1.0 + i * 0.14, keyTop + 0.11, -0.28 + (i % 2) * 0.05), WHITE, M.SmoothPlastic)
		end
	end
	local keys = {}
	for n = low, high do
		local cf: CFrame
		local part: BasePart
		if isBlack(n) then
			local x = kx0 + whiteIndex(n, low) * pitch
			cf = sf * CFrame.new(x, keyTop + 0.02, 0.14)
			part = newPart(self, "Key", Vector3.new(0.045, 0.09, 0.3), cf, EBONY, M.SmoothPlastic)
		else
			local x = kx0 + (whiteIndex(n, low) + 0.5) * pitch
			cf = sf * CFrame.new(x, keyTop - 0.045, 0.24)
			part = newPart(self, "Key", Vector3.new(pitch - 0.008, 0.09, 0.5), cf, WHITE, M.SmoothPlastic)
		end
		keys[n] = { Part = part, CF = cf, Top = (cf * CFrame.new(0, 0.06, 0.12)).Position }
	end
	self.H.Keys.Synth = keys
	-- stand en X
	for _, x in ipairs({ -0.8, 0.8 }) do
		for _, s in ipairs({ -1, 1 }) do
			rodW(self, "StandTube", (sf * CFrame.new(x, 0.05, s * 0.55)).Position, (sf * CFrame.new(x, keyTop - 0.3, -s * 0.45)).Position, 0.09, BLACK, M.Metal)
		end
		newPart(self, "StandArm", Vector3.new(0.08, 0.08, 1.1), sf * CFrame.new(x, keyTop - 0.26, 0), BLACK, M.Metal)
	end
	newPart(self, "StandBolt", Vector3.new(1.7, 0.08, 0.08), sf * CFrame.new(0, (keyTop - 0.25) / 2, 0.05) * CFrame.Angles(0, 0, 0), CHROME, M.Metal)
	local emitter = newPart(self, "SynthEmitter", Vector3.new(0.3, 0.3, 0.3), sf * CFrame.new(0, 3, 0), WHITE)
	emitter.Transparency = 1
	self.H.Emitters.Synth = emitter
	local block = newPart(self, "Block", Vector3.new(width, 2.9, 1.0), sf * CFrame.new(0, 1.45, 0), WHITE)
	block.Transparency = 1
	block.CanCollide = true
end)

----------------------------------------------------------------------
-- 🎧 Cabine DJ
----------------------------------------------------------------------

step("DJ", function(self)
	local st = MusicData.STATIONS.DJ
	local y0 = TOP + MusicData.RISERS.DJ.H
	local jf = self.CF * CFrame.new(st.Spot.Position.X, y0, st.Spot.Position.Z - 1.75)
	self.H.Frames.DJ = jf
	local top = 2.96
	local facade = newPart(self, "BoothFront", Vector3.new(4.2, top - 0.1, 0.1), jf * CFrame.new(0, (top - 0.1) / 2, -0.55), Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	facade.CastShadow = true
	for _, x in ipairs({ -2.05, 2.05 }) do
		newPart(self, "BoothSide", Vector3.new(0.1, top - 0.1, 1.2), jf * CFrame.new(x, (top - 0.1) / 2, 0), Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	end
	newPart(self, "BoothTop", Vector3.new(4.4, 0.12, 1.3), jf * CFrame.new(0, top - 0.06, 0), Color3.fromRGB(230, 230, 236), M.SmoothPlastic)
	-- façade LED (égaliseur)
	local led = newPart(self, "BoothLED", Vector3.new(3.8, 2.2, 0.04), jf * CFrame.new(0, 1.45, -0.62), Color3.fromRGB(8, 8, 12), M.Glass)
	local g = surface(led, Enum.NormalId.Front, 40, 0)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(10, 8, 20)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local djLabel = label(bg, "Title", "DJ DOPA", UDim2.fromScale(0.1, 0.05), UDim2.fromScale(0.8, 0.28), PINK)
	local bars = {}
	for i = 1, 16 do
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.fromScale((i - 1) / 16 + 0.005, 0.95)
		b.Size = UDim2.fromScale(1 / 16 - 0.01, 0.05)
		b.BorderSizePixel = 0
		b.BackgroundColor3 = Color3.fromHSV(0.55 + 0.3 * (i - 1) / 16, 0.7, 1)
		b.Parent = bg
		bars[i] = b
	end
	-- platines
	local platters = {}
	for i, x in ipairs({ -1.3, 1.3 }) do
		newPart(self, "DeckBase", Vector3.new(1.3, 0.14, 1.0), jf * CFrame.new(x, top + 0.07, 0), Color3.fromRGB(40, 40, 46), M.Metal)
		local center = jf * CFrame.new(x - 0.08, top + 0.17, 0.02)
		newPart(self, "Platter", Vector3.new(0.06, 0.9, 0.9), center * CFrame.Angles(0, 0, rad(90)), CHROME, M.Metal, CYL)
		local record = newPart(self, "Record", Vector3.new(0.02, 0.86, 0.86), center * CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, rad(90)), EBONY, M.SmoothPlastic, CYL)
		local lab = newPart(self, "RecordLabel", Vector3.new(0.03, 0.3, 0.3), center * CFrame.new(0, 0.065, 0) * CFrame.Angles(0, 0, rad(90)), i == 1 and PINK or CYAN, M.SmoothPlastic, CYL)
		local mark = newPart(self, "RecordMark", Vector3.new(0.1, 0.012, 0.04), center * CFrame.new(0.3, 0.062, 0), WHITE, M.SmoothPlastic)
		rodW(self, "Tonearm", (jf * CFrame.new(x + 0.5, top + 0.24, -0.35)).Position, (jf * CFrame.new(x + 0.15, top + 0.24, 0.25)).Position, 0.035, CHROME, M.Metal)
		newPart(self, "Cartridge", Vector3.new(0.08, 0.05, 0.12), jf * CFrame.new(x + 0.13, top + 0.23, 0.29), EBONY, M.SmoothPlastic)
		table.insert(platters, { Parts = { record, lab, mark }, Center = center, CFs = { record.CFrame, lab.CFrame, mark.CFrame }, Angle = 0 })
	end
	-- table de mixage
	newPart(self, "Mixer", Vector3.new(0.9, 0.16, 1.0), jf * CFrame.new(0, top + 0.08, 0), Color3.fromRGB(30, 30, 36), M.Metal)
	for row = 0, 2 do
		for col = 0, 1 do
			newPart(self, "MixKnob", Vector3.new(0.06, 0.08, 0.08), jf * CFrame.new(-0.2 + col * 0.4, top + 0.18, -0.35 + row * 0.18) * CFrame.Angles(0, 0, rad(90)), CHROME, M.SmoothPlastic, CYL)
		end
	end
	local meters = {}
	for col = 0, 1 do
		for k = 0, 5 do
			local c = k < 4 and Color3.fromRGB(90, 230, 120) or (k < 5 and Color3.fromRGB(255, 210, 80) or Color3.fromRGB(255, 70, 70))
			local led2 = newPart(self, "Meter", Vector3.new(0.05, 0.03, 0.05), jf * CFrame.new(-0.06 + col * 0.12, top + 0.175, 0.05 - k * 0.07), Color3.fromRGB(40, 40, 40), M.SmoothPlastic)
			led2:SetAttribute("OnColor", c)
			table.insert(meters, led2)
		end
	end
	local faderCF = jf * CFrame.new(0, top + 0.19, 0.4)
	newPart(self, "FaderSlot", Vector3.new(0.5, 0.012, 0.04), jf * CFrame.new(0, top + 0.162, 0.4), EBONY, M.SmoothPlastic)
	local fader = newPart(self, "Crossfader", Vector3.new(0.08, 0.06, 0.12), faderCF, WHITE, M.SmoothPlastic)
	-- ordinateur portable + casque
	local lap = jf * CFrame.new(0, top + 0.35, -0.45)
	newPart(self, "LaptopStand", Vector3.new(0.5, 0.3, 0.3), jf * CFrame.new(0, top + 0.15, -0.45), CHROME, M.Metal)
	newPart(self, "Laptop", Vector3.new(0.8, 0.03, 0.55), lap, Color3.fromRGB(196, 198, 206), M.Metal)
	local scr = newPart(self, "LaptopScreen", Vector3.new(0.8, 0.52, 0.03), lap * CFrame.new(0, 0.24, -0.3) * CFrame.Angles(rad(-12), 0, 0), Color3.fromRGB(196, 198, 206), M.Metal)
	local sg = surface(scr, Enum.NormalId.Back, 120, 0)
	local wave = Instance.new("Frame")
	wave.Size = UDim2.fromScale(0.94, 0.9)
	wave.Position = UDim2.fromScale(0.03, 0.05)
	wave.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	wave.BorderSizePixel = 0
	wave.Parent = sg
	for i = 1, 2 do
		local w = Instance.new("Frame")
		w.Size = UDim2.fromScale(0.9, 0.12)
		w.Position = UDim2.fromScale(0.05, 0.2 + (i - 1) * 0.4)
		w.BackgroundColor3 = i == 1 and PINK or CYAN
		w.BorderSizePixel = 0
		w.Parent = wave
	end
	local phones = jf * CFrame.new(1.75, top + 0.1, 0.35)
	for _, s in ipairs({ -1, 1 }) do
		newPart(self, "EarCup", Vector3.new(0.1, 0.26, 0.26), phones * CFrame.new(s * 0.18, 0.03, 0) * CFrame.Angles(0, 0, rad(90)), EBONY, M.Leather, CYL)
	end
	newPart(self, "HeadBand", Vector3.new(0.42, 0.04, 0.08), phones * CFrame.new(0, 0.1, 0), EBONY, M.SmoothPlastic)
	self.H.DJ = { Platters = platters, Meters = meters, Fader = fader, FaderCF = faderCF, Bars = bars, Label = djLabel }
	local emitter = newPart(self, "DJEmitter", Vector3.new(0.3, 0.3, 0.3), jf * CFrame.new(0, 3.2, 0), WHITE)
	emitter.Transparency = 1
	self.H.Emitters.DJ = emitter
	local block = newPart(self, "Block", Vector3.new(4.4, 3.0, 1.3), jf * CFrame.new(0, 1.5, 0), WHITE)
	block.Transparency = 1
	block.CanCollide = true
end)

----------------------------------------------------------------------
-- (v11) Ailes : écrans latéraux, nez de scène lumineux
----------------------------------------------------------------------

local function ledScreen(self: any, name: string, part: BasePart, face: Enum.NormalId, bars: number): any
	local g = surface(part, face, 30, 0)
	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(12, 8, 26)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(80, 20, 90), Color3.fromRGB(10, 40, 90))
	grad.Rotation = 90
	grad.Parent = bg
	local icon = label(bg, "Icon", "🎵", UDim2.fromScale(0.1, 0.08), UDim2.fromScale(0.8, 0.34), WHITE)
	local title = label(bg, "Title", "DOPAMINE LIVE", UDim2.fromScale(0.06, 0.44), UDim2.fromScale(0.88, 0.12), WHITE)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0.08, 0.62)
	holder.Size = UDim2.fromScale(0.84, 0.3)
	holder.Parent = bg
	local list = {}
	for i = 1, bars do
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.fromScale((i - 1) / bars + 0.01, 1)
		b.Size = UDim2.fromScale(1 / bars - 0.02, 0.1)
		b.BorderSizePixel = 0
		b.BackgroundColor3 = Color3.fromHSV(0.85 - 0.5 * (i - 1) / bars, 0.6, 1)
		b.Parent = holder
		list[i] = b
	end
	local _ = name
	return { Icon = icon, Title = title, Bars = list }
end

step("Wings", function(self)
	local T = MusicData.TRUSS_TOWERS
	-- écrans "géants" de chaque côté (portrait), suspendus au grill avant
	local sides = {}
	for _, x in ipairs({ -10.3, 10.3 }) do
		local y = 11
		box(self, "SideScreenFrame", Vector3.new(4.4, 7.4, 0.24), CFrame.new(x, y, T[1].Z - 0.35), BLACK, M.Metal)
		local panel = box(self, "SideScreen", Vector3.new(4, 7, 0.05), CFrame.new(x, y, T[1].Z - 0.5), Color3.fromRGB(6, 6, 10), M.Glass)
		for _, dx in ipairs({ -1.6, 1.6 }) do
			rodW(self, "SideScreenHang", self.CF:PointToWorldSpace(Vector3.new(x + dx, y + 3.7, T[1].Z - 0.35)), self.CF:PointToWorldSpace(Vector3.new(x + dx, MusicData.TRUSS_H, T[1].Z)), 0.05, STEEL, M.Metal)
		end
		table.insert(sides, ledScreen(self, "Side", panel, Enum.NormalId.Front, 8))
	end
	self.H.SideScreens = sides
	-- nez de scène : bandeau lumineux sous le bord avant
	local lip = box(self, "StageLip", Vector3.new(D.X1 - D.X0 - 0.4, 0.12, 0.05), CFrame.new(0, TOP - 0.2, D.Z0 - 0.13), PINK, M.SmoothPlastic)
	glow(lip, PINK)
	-- garde-corps à l'arrière et sur les côtés du plancher (on ne tombe pas)
	if self.Detail ~= "Low" then
		for _, x in ipairs({ D.X0 + 0.15, D.X1 - 0.15 }) do
			for _, z in ipairs({ -3.6, 0.6, 4.8, 9.0 }) do
				box(self, "RailPost", Vector3.new(0.14, 3.5, 0.14), CFrame.new(x, TOP + 1.75, z), STEEL, M.Metal)
			end
			box(self, "RailTop", Vector3.new(0.12, 0.12, 12.8), CFrame.new(x, TOP + 3.5, 2.7), ALU, M.Metal)
			box(self, "RailMid", Vector3.new(0.08, 0.08, 12.8), CFrame.new(x, TOP + 1.8, 2.7), ALU, M.Metal)
		end
	end
	-- caisses de matériel ("flight cases") en coulisses
	for i, spec in ipairs({ { -13.2, 7.6 }, { -12.6, 5.9 }, { 12.9, 7.4 }, { 13.4, 1.0 } }) do
		local size = i % 2 == 0 and Vector3.new(1.6, 1.2, 1.2) or Vector3.new(2.2, 1.6, 1.4)
		box(self, "FlightCase", size, CFrame.new(spec[1], TOP + size.Y / 2, spec[2]) * CFrame.Angles(0, rad(8 * i), 0), Color3.fromRGB(30, 30, 34), M.Plastic)
		box(self, "FlightCaseEdge", size + Vector3.new(0.06, -size.Y + 0.08, 0.06), CFrame.new(spec[1], TOP + size.Y + 0.04, spec[2]) * CFrame.Angles(0, rad(8 * i), 0), CHROME, M.Metal)
	end
end)

----------------------------------------------------------------------
-- (v11) La FOSSE du public : piste de danse LED, barrières, tours d'éclairage
----------------------------------------------------------------------

step("Crowd", function(self)
	local C = MusicData.CROWD
	local G = MusicData.GROUND
	local tile = self.Detail == "Low" and 4 or 2
	local nx = math.floor((C.X1 - C.X0) / tile + 0.5)
	local nz = math.floor((C.Z1 - C.Z0) / tile + 0.5)
	local tw = (C.X1 - C.X0) / nx
	local td = (C.Z1 - C.Z0) / nz
	-- cadre alu de la piste (posé sur le pavé, légèrement enfoncé)
	local frameC = Color3.fromRGB(150, 154, 166)
	box(self, "FloorEdge", Vector3.new(C.X1 - C.X0 + 0.6, 0.2, 0.3), CFrame.new((C.X0 + C.X1) / 2, G + 0.06, C.Z0 - 0.15), frameC, M.DiamondPlate)
	box(self, "FloorEdge", Vector3.new(C.X1 - C.X0 + 0.6, 0.2, 0.3), CFrame.new((C.X0 + C.X1) / 2, G + 0.06, C.Z1 + 0.15), frameC, M.DiamondPlate)
	box(self, "FloorEdge", Vector3.new(0.3, 0.2, C.Z1 - C.Z0), CFrame.new(C.X0 - 0.15, G + 0.06, (C.Z0 + C.Z1) / 2), frameC, M.DiamondPlate)
	box(self, "FloorEdge", Vector3.new(0.3, 0.2, C.Z1 - C.Z0), CFrame.new(C.X1 + 0.15, G + 0.06, (C.Z0 + C.Z1) / 2), frameC, M.DiamondPlate)
	local tiles = {}
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x = C.X0 + (i + 0.5) * tw
			local z = C.Z0 + (j + 0.5) * td
			local p = box(self, "DanceTile", Vector3.new(tw - 0.12, 0.14, td - 0.12), CFrame.new(x, G + 0.03, z), Color3.fromRGB(40, 30, 60), M.Glass)
			p.Reflectance = 0.1
			table.insert(tiles, { Part = p, I = i, J = j, U = (i + 0.5) / nx, V = (j + 0.5) / nz })
		end
	end
	-- joints noirs entre les dalles
	box(self, "FloorBase", Vector3.new(C.X1 - C.X0, 0.1, C.Z1 - C.Z0), CFrame.new((C.X0 + C.X1) / 2, G - 0.01, (C.Z0 + C.Z1) / 2), Color3.fromRGB(14, 12, 18), M.SmoothPlastic)
	self.H.DanceFloor = tiles
	-- barrières de sécurité devant la scène (passage libre devant les marches)
	local bz = MusicData.DECK.Z0 - 3.3
	for _, side in ipairs({ -1, 1 }) do
		local xa, xb = side * (MusicData.STEPS.X + 1.4), side * (MusicData.DECK.X1 - 0.6)
		local n = math.max(1, math.floor(math.abs(xb - xa) / 2.6 + 0.5))
		for k = 0, n - 1 do
			local x0 = xa + (xb - xa) * k / n
			local x1 = xa + (xb - xa) * (k + 1) / n
			local xm, len = (x0 + x1) / 2, math.abs(x1 - x0) - 0.1
			local panel = box(self, "BarrierPanel", Vector3.new(len, 2.6, 0.08), CFrame.new(xm, G + 1.5, bz), Color3.fromRGB(120, 124, 136), M.DiamondPlate)
			panel.CanCollide = true
			box(self, "BarrierTop", Vector3.new(len + 0.06, 0.16, 0.3), CFrame.new(xm, G + 3.5 - 0.08, bz), ALU, M.Metal)
			box(self, "BarrierFoot", Vector3.new(len, 0.1, 1.6), CFrame.new(xm, G + 0.03, bz - 0.6), STEEL, M.DiamondPlate)
			box(self, "BarrierLeg", Vector3.new(0.18, 3.3, 0.2), CFrame.new(x0 + side * 0.05, G + 1.65, bz), ALU, M.Metal)
		end
	end
	-- tours d'éclairage de la fosse (avec projecteurs tournés vers la scène)
	local towers = {}
	for _, x in ipairs({ C.X0 - 1.6, C.X1 + 1.6 }) do
		local z = C.Z1 + 0.5
		truss(self, Vector3.new(x, G + 0.1, z), Vector3.new(x, 11, z), 0.8, self.Detail == "Low" and { 1, 3 } or { 1, 2, 3, 4 }, 1.8)
		box(self, "TowerFoot", Vector3.new(1.6, 0.12, 1.6), CFrame.new(x, G + 0.04, z), STEEL, M.DiamondPlate)
		local aim = CFrame.lookAt(self.CF:PointToWorldSpace(Vector3.new(x, 10.6, z)), self.CF:PointToWorldSpace(Vector3.new(0, 4, 2)))
		for k = -1, 1, 2 do
			local can = newPart(self, "FollowSpot", Vector3.new(0.7, 0.7, 1.6), aim * CFrame.new(k * 0.5, 0, -0.4), BLACK, M.Metal)
			local lens = newPart(self, "FollowSpotLens", Vector3.new(0.04, 0.56, 0.56), aim * CFrame.new(k * 0.5, 0, -1.22) * CFrame.Angles(0, rad(90), 0), Color3.fromRGB(255, 236, 200), M.Glass, CYL)
			glow(lens, Color3.fromRGB(255, 236, 200))
			table.insert(towers, can)
		end
		-- bannière verticale
		local flag = box(self, "CrowdBanner", Vector3.new(1.4, 5, 0.06), CFrame.new(x, 6.2, z - 0.5), PINK, M.Fabric)
		local sg = surface(flag, Enum.NormalId.Front, 30, 0.5)
		local fr = Instance.new("Frame")
		fr.Size = UDim2.fromScale(1, 1)
		fr.BackgroundColor3 = PINK
		fr.BorderSizePixel = 0
		fr.Parent = sg
		label(fr, "T", "🎤\nL\nI\nV\nE", UDim2.fromScale(0.1, 0.04), UDim2.fromScale(0.8, 0.92), WHITE)
	end
	-- marquage au sol "DANCE FLOOR" (entre la piste et les barrières)
	local sign = box(self, "FloorSign", Vector3.new(8, 0.04, 1.4), CFrame.new(0, G + 0.005, C.Z1 + 1.1), Color3.fromRGB(30, 26, 40), M.SmoothPlastic)
	local sg = surface(sign, Enum.NormalId.Top, 30, 0.6)
	local fr = Instance.new("Frame")
	fr.Size = UDim2.fromScale(1, 1)
	fr.BackgroundColor3 = Color3.fromRGB(30, 26, 40)
	fr.BorderSizePixel = 0
	fr.Parent = sg
	local l = label(fr, "T", "🪩 DANCE FLOOR 🪩", UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), PINK)
	l.Rotation = 180
end)

----------------------------------------------------------------------
-- Construction pas à pas
----------------------------------------------------------------------

function MusicStageBuild.new(stageCF: CFrame, parent: Instance, detail: string?): Build
	local model = Instance.new("Model")
	model.Name = "MusicStageFx"
	model.Parent = parent
	local self = setmetatable({
		CF = stageCF,
		Model = model,
		Detail = detail or "Medium",
		H = { Keys = {}, Frames = {}, Emitters = {} },
		Index = 0,
		Group = model,
		Count = 0,
		Done = false,
	}, MusicStageBuild)
	return self
end

MusicStageBuild.STEP_NAMES = STEPS

-- Un morceau ; true quand tout est construit
function MusicStageBuild.Step(self: Build): boolean
	if self.Done then
		return true
	end
	self.Index += 1
	local entry = STEPS[self.Index]
	if not entry then
		self.Done = true
		return true
	end
	local group = Instance.new("Model")
	group.Name = entry[1]
	group.Parent = self.Model
	self.Group = group
	local ok, err = pcall(BUILDERS[entry[1]], self)
	if not ok then
		warn("[MusicStage] décor " .. entry[1] .. " : " .. tostring(err))
	end
	if self.Index >= #STEPS then
		self.Done = true
	end
	return self.Done
end

function MusicStageBuild.Destroy(self: Build)
	self.Done = true
	if self.Model then
		self.Model:Destroy()
	end
end

return MusicStageBuild
