--[[
	ConstructionKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ConstructionKit

	🏗️ v10 (CONSTRUCT10) : boîte à outils des CHANTIERS, côté client
	(ConstructionSite : parcelle libre ; HouseBuildAnim : maison qui se
	construit). Rien ici ne tourne tout seul : chaque engin articulé renvoie
	un "rig" dont on appelle :Pose(...) (BulkMoveTo, une fois par image au plus).

	Échelle réelle (avatar 5,2 studs ≈ 1,75 m : 1 m ≈ 3 studs) :
	  - grue à tour : mât treillis 3 x 3 de 60 studs (20 m), flèche 45
	    (15 m), contre-flèche lestée, cabine, chariot, moufle et crochet,
	    palette de briques suspendue par des élingues ;
	  - pelleteuse 13 t : chenilles 11,7 x 1,8 (galets, barbotin), tourelle
	    7,5 de large, cabine vitrée à 8,7 studs, flèche 13,8, balancier 7,5,
	    godet à dents, vérins hydrauliques (fût + tige, sans étirement) ;
	  - échafaudage tubulaire : montants, lisses, moises, planchers, plinthes,
	    diagonales, échelle, filet orange ;
	  - clôture de chantier (panneaux grillagés 10,5 x 6 sur plots béton),
	    palissade pleine avec bâches, cônes, palettes de briques, bois,
	    poutrelles, sable, sacs de ciment, bétonnière, toilettes de chantier,
	    bungalow de chantier, chariot à briques, tréteau.
	Toutes les pièces : ancrées, CanTouch = false ; CanQuery = false sauf les
	pièces solides (on ne traverse pas une grue ou un bungalow) ; ombres
	seulement pour les grosses pièces ; aucune lumière, aucun son.
]]

local ConstructionKit = {}

local M = Enum.Material
local rgb = Color3.fromRGB
ConstructionKit.M = M

ConstructionKit.C = {
	Yellow = rgb(248, 190, 28), -- jaune "grue"
	YellowDark = rgb(214, 158, 20),
	Steel = rgb(120, 126, 134),
	SteelDark = rgb(66, 70, 78),
	Concrete = rgb(176, 174, 168),
	ConcreteDark = rgb(140, 138, 132),
	Brick = rgb(178, 86, 62),
	Dirt = rgb(128, 98, 70),
	DirtDark = rgb(96, 72, 52),
	Sand = rgb(222, 196, 140),
	Timber = rgb(198, 156, 104),
	TimberDark = rgb(150, 110, 70),
	Orange = rgb(255, 120, 30),
	White = rgb(245, 245, 242),
	Red = rgb(214, 48, 44),
	Glass = rgb(160, 200, 220),
	Rubber = rgb(34, 34, 36),
	Blue = rgb(40, 110, 200),
	Green = rgb(60, 150, 80),
	Office = rgb(236, 236, 230),
	Pallet = rgb(186, 150, 104),
}
local C = ConstructionKit.C

export type Opts = {
	Shape: string?, -- "Block" | "Cyl" | "Ball" | "Egg" | "Wedge" | "Corner"
	Solid: boolean?,
	Alpha: number?,
	Shadow: boolean?,
	Reflect: number?,
}

-- Compteur global (mesures / rapport)
ConstructionKit.Stats = { Parts = 0 }

-- Pièce de base
function ConstructionKit.Part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	local o = opts or {}
	local shape = o.Shape or "Block"
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "Corner" then
		p = Instance.new("CornerWedgePart")
	else
		local part = Instance.new("Part")
		if shape == "Cyl" then
			part.Shape = Enum.PartType.Cylinder
		elseif shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif shape == "Egg" then
			-- ellipsoïde qui épouse la taille de la pièce
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		p = part
	end
	p.Name = name
	p.Anchored = true
	local solid = o.Solid == true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.Alpha then
		p.Transparency = o.Alpha
	end
	if o.Reflect then
		p.Reflectance = o.Reflect
	end
	local big = size.X * size.Y + size.Y * size.Z + size.X * size.Z > 18
	if o.Shadow ~= nil then
		p.CastShadow = o.Shadow
	else
		p.CastShadow = big
	end
	p.Parent = parent
	ConstructionKit.Stats.Parts += 1
	return p
end
local P = ConstructionKit.Part

-- Cylindre DEBOUT (axe Y) centré en cf
function ConstructionKit.CylY(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	local o: Opts = table.clone(opts or {}) :: any
	o.Shape = "Cyl"
	return P(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color, material, o)
end

-- Barre entre deux points (carrée, ou ronde si round)
function ConstructionKit.Rod(parent: Instance, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?, round: boolean?, opts: Opts?): BasePart
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local look = if length > 1e-4 then CFrame.lookAt(mid, b, if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis) else CFrame.new(mid)
	if round then
		local o: Opts = table.clone(opts or {}) :: any
		o.Shape = "Cyl"
		return P(parent, name, Vector3.new(math.max(length, 0.05), thickness, thickness), look * CFrame.Angles(0, math.pi / 2, 0), color, material, o)
	end
	return P(parent, name, Vector3.new(thickness, thickness, math.max(length, 0.05)), look, color, material, opts)
end

-- CFrame d'une barre entre deux points (pour les rigs : même convention que Rod)
function ConstructionKit.RodCF(a: Vector3, b: Vector3, round: boolean?): CFrame
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	if length < 1e-4 then
		return CFrame.new(mid)
	end
	local look = CFrame.lookAt(mid, b, if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis)
	if round then
		return look * CFrame.Angles(0, math.pi / 2, 0)
	end
	return look
end

-- Boîte par ses bornes dans un repère
function ConstructionKit.Box(parent: Instance, name: string, frame: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	return P(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, opts)
end

-- Pièce de rig : on garde son CFrame dans le repère du pivot
export type Rig = {
	Parts: { BasePart },
	Locals: { CFrame },
	Frames: { CFrame },
	[string]: any,
}

local function newRig(): Rig
	return { Parts = {}, Locals = {}, Frames = {} }
end

local function rigAdd(rig: Rig, part: BasePart, pivot: CFrame)
	table.insert(rig.Parts, part)
	table.insert(rig.Locals, pivot:ToObjectSpace(part.CFrame))
end

local function rigMove(rig: Rig, pivot: CFrame)
	local frames = rig.Frames
	for i, l in ipairs(rig.Locals) do
		frames[i] = pivot * l
	end
	workspace:BulkMoveTo(rig.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end
ConstructionKit.RigMove = rigMove

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
ConstructionKit.Smooth = smooth

-- Interpolation de clés {t, a, b, c...} (t croissants, boucle de période last.t)
local function keyed(keys: { { number } }, t: number): { number }
	local period = keys[#keys][1]
	local u = t % period
	for i = 1, #keys - 1 do
		local k0, k1 = keys[i], keys[i + 1]
		if u >= k0[1] and u <= k1[1] then
			local span = k1[1] - k0[1]
			local s = if span > 0 then smooth((u - k0[1]) / span) else 1
			local out = {}
			for j = 2, #k0 do
				out[j - 1] = k0[j] + (k1[j] - k0[j]) * s
			end
			return out
		end
	end
	local out = {}
	for j = 2, #keys[1] do
		out[j - 1] = keys[1][j]
	end
	return out
end
ConstructionKit.Keyed = keyed

----------------------------------------------------------------------
-- 🏗️ Grue à tour
----------------------------------------------------------------------

export type CraneOpts = {
	Height: number?, -- hauteur du mât (sous la couronne)
	Jib: number?, -- longueur de flèche
	Lite: boolean?, -- version "de loin" : quelques pièces pleines
}

-- Grue posée en baseCF (au sol, Y vers le haut). Renvoie un rig :
--   rig:Pose(angle, radius, drop, loaded)  (angle : rotation autour du mât ;
--   radius : chariot depuis l'axe ; drop : crochet sous la flèche ; loaded :
--   palette suspendue visible)
function ConstructionKit.Crane(parent: Instance, baseCF: CFrame, opts: CraneOpts?): Rig
	local o = opts or {}
	local H = o.Height or 60
	local L = o.Jib or 45
	local model = Instance.new("Model")
	model.Name = "TowerCrane"
	model.Parent = parent
	local rig = newRig()
	rig.Model = model
	rig.Top = baseCF * CFrame.new(0, H, 0)
	rig.Height = H
	rig.Jib = L
	rig.Lite = o.Lite == true
	local yellow, dark = C.Yellow, C.YellowDark
	local w = 3 -- section du mât
	if o.Lite then
		P(model, "Footing", Vector3.new(7, 1.2, 7), baseCF * CFrame.new(0, 0.3, 0), C.Concrete, M.Concrete, { Solid = true })
		P(model, "Mast", Vector3.new(w, H, w), baseCF * CFrame.new(0, H / 2, 0), yellow, M.Metal, { Solid = true, Alpha = 0.25 })
	else
		-- semelle béton + lests
		P(model, "Footing", Vector3.new(8, 1.4, 8), baseCF * CFrame.new(0, 0.35, 0), C.Concrete, M.Concrete, { Solid = true })
		for _, s in ipairs({ { -1, -1 }, { 1, 1 } }) do
			P(model, "Ballast", Vector3.new(2.4, 1.6, 6.6), baseCF * CFrame.new(s[1] * 2.6, 1.8, 0), C.ConcreteDark, M.Concrete, { Solid = true })
		end
		-- mât treillis : 4 membrures + par tronçon 2 entretoises + 4 diagonales
		local half = w / 2 - 0.2
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			P(model, "Chord", Vector3.new(0.4, H - 1, 0.4), baseCF * CFrame.new(c[1] * half, H / 2 + 0.5, c[2] * half), yellow, M.Metal, { Solid = true })
		end
		local sections = math.max(3, math.floor((H - 1) / 7.5))
		local sh = (H - 1) / sections
		for k = 0, sections - 1 do
			local y0 = 1 + k * sh
			local y1 = y0 + sh
			local flip = k % 2 == 0 and 1 or -1
			-- entretoises (avant / arrière)
			for _, z in ipairs({ -half, half }) do
				ConstructionKit.Rod(model, "Brace", (baseCF * CFrame.new(-half, y1, z)).Position, (baseCF * CFrame.new(half, y1, z)).Position, 0.22, yellow, M.Metal)
			end
			-- diagonales (4 faces)
			for _, face in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local a, b
				if face[1] ~= 0 then
					local x = face[1] * half
					a = baseCF * CFrame.new(x, y0, -half * flip)
					b = baseCF * CFrame.new(x, y1, half * flip)
				else
					local z = face[2] * half
					a = baseCF * CFrame.new(-half * flip, y0, z)
					b = baseCF * CFrame.new(half * flip, y1, z)
				end
				ConstructionKit.Rod(model, "Diagonal", a.Position, b.Position, 0.2, yellow, M.Metal)
			end
		end
		-- échelle dans le mât (un montant + barreaux suggérés par une texture de bandes)
		P(model, "Ladder", Vector3.new(0.9, H - 2, 0.12), baseCF * CFrame.new(0, H / 2, half - 0.3), C.SteelDark, M.DiamondPlate)
	end
	-- partie tournante (repère : couronne en haut du mât ; flèche vers -Z)
	local top = rig.Top
	local rot = Instance.new("Model")
	rot.Name = "Slewing"
	rot.Parent = model
	local function add(part: BasePart)
		rigAdd(rig, part, top)
	end
	local jibY = 3.2 -- dessous de la flèche au-dessus de la couronne
	local jibH = 2.6
	if o.Lite then
		add(P(rot, "Cab", Vector3.new(2.6, 2.6, 3), top * CFrame.new(2.4, 1.6, -1.2), C.White, M.SmoothPlastic))
		add(P(rot, "Jib", Vector3.new(2.4, jibH, L), top * CFrame.new(0, jibY + jibH / 2, -L / 2 - 1), yellow, M.Metal, { Alpha = 0.3 }))
		add(P(rot, "CounterJib", Vector3.new(2.4, 1.2, 13), top * CFrame.new(0, jibY + 0.6, 7.5), yellow, M.Metal))
		add(P(rot, "Counterweight", Vector3.new(3.2, 3.4, 2.6), top * CFrame.new(0, jibY - 1.2, 12.4), C.Concrete, M.Concrete))
		add(P(rot, "Apex", Vector3.new(1.6, 8, 1.6), top * CFrame.new(0, jibY + 4, 0), yellow, M.Metal))
		rig.Trolley = nil
	else
		-- couronne, pivot, cabine vitrée
		add(ConstructionKit.CylY(rot, "Turntable", 4.2, 1.6, top * CFrame.new(0, 0.8, 0), dark, M.Metal))
		add(P(rot, "Platform", Vector3.new(3.4, 0.6, 3.4), top * CFrame.new(0, 1.9, 0), yellow, M.Metal))
		local cab = top * CFrame.new(2.9, 2.1, -1.4)
		add(P(rot, "Cab", Vector3.new(2.6, 3, 3.2), cab, C.White, M.SmoothPlastic))
		add(P(rot, "CabGlass", Vector3.new(2.3, 1.7, 0.1), cab * CFrame.new(0, 0.45, -1.63), C.Glass, M.Glass, { Alpha = 0.35, Reflect = 0.1 }))
		add(P(rot, "CabSide", Vector3.new(0.1, 1.5, 2.2), cab * CFrame.new(1.33, 0.45, -0.2), C.Glass, M.Glass, { Alpha = 0.35, Reflect = 0.1 }))
		add(P(rot, "CabRoof", Vector3.new(2.8, 0.2, 3.4), cab * CFrame.new(0, 1.6, 0), yellow, M.Metal))
		-- pointe (A) + tirants
		local apexTop = top * CFrame.new(0, jibY + jibH + 7.5, 0)
		for _, s in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -0.9, 0.9 }) do
				add(ConstructionKit.Rod(rot, "ApexLeg", (top * CFrame.new(s * 1.1, jibY + jibH, z)).Position, (apexTop * CFrame.new(s * 0.2, 0, 0)).Position, 0.35, yellow, M.Metal))
			end
		end
		add(P(rot, "ApexCap", Vector3.new(0.9, 0.5, 0.9), apexTop * CFrame.new(0, 0.2, 0), C.Red, M.SmoothPlastic))
		add(P(rot, "AviationLight", Vector3.new(0.4, 0.4, 0.4), apexTop * CFrame.new(0, 0.65, 0), rgb(255, 60, 50), M.Neon, { Shape = "Ball" }))
		-- flèche : 2 membrures basses + 1 haute + zigzags
		local j0, j1 = -1.2, -1.2 - L
		for _, s in ipairs({ -1, 1 }) do
			add(P(rot, "JibChord", Vector3.new(0.35, 0.35, L), top * CFrame.new(s * 1.1, jibY, (j0 + j1) / 2), yellow, M.Metal))
		end
		add(P(rot, "JibTop", Vector3.new(0.35, 0.35, L - 1), top * CFrame.new(0, jibY + jibH, (j0 + j1) / 2 + 0.5), yellow, M.Metal))
		local bays = math.max(4, math.floor(L / 4))
		local bl = L / bays
		for k = 0, bays - 1 do
			local z0 = j0 - k * bl
			local z1 = z0 - bl
			for _, s in ipairs({ -1, 1 }) do
				add(ConstructionKit.Rod(rot, "JibLace", (top * CFrame.new(s * 1.1, jibY, z0)).Position, (top * CFrame.new(0, jibY + jibH, (z0 + z1) / 2)).Position, 0.18, yellow, M.Metal))
				add(ConstructionKit.Rod(rot, "JibLace", (top * CFrame.new(0, jibY + jibH, (z0 + z1) / 2)).Position, (top * CFrame.new(s * 1.1, jibY, z1)).Position, 0.18, yellow, M.Metal))
			end
			if k % 2 == 0 then
				add(P(rot, "JibTie", Vector3.new(2.2, 0.16, 0.16), top * CFrame.new(0, jibY, z1), yellow, M.Metal))
			end
		end
		-- bout de flèche rouge et blanc
		add(P(rot, "JibTip", Vector3.new(2.6, 0.5, 0.5), top * CFrame.new(0, jibY + 0.2, j1 - 0.1), C.Red, M.SmoothPlastic))
		add(ConstructionKit.Rod(rot, "Pendant", (apexTop).Position, (top * CFrame.new(0, jibY + jibH, j0 - L * 0.62)).Position, 0.16, C.SteelDark, M.Metal))
		-- contre-flèche + passerelle + lests + treuil
		local cL = 14
		for _, s in ipairs({ -1, 1 }) do
			add(P(rot, "CounterChord", Vector3.new(0.4, 0.8, cL), top * CFrame.new(s * 1.1, jibY + 0.4, cL / 2 + 1), yellow, M.Metal))
			add(P(rot, "Railing", Vector3.new(0.12, 0.12, cL - 1), top * CFrame.new(s * 1.3, jibY + 1.8, cL / 2 + 1.5), yellow, M.Metal))
		end
		add(P(rot, "Walkway", Vector3.new(2.3, 0.14, cL), top * CFrame.new(0, jibY + 0.8, cL / 2 + 1), C.SteelDark, M.DiamondPlate))
		add(P(rot, "Winch", Vector3.new(2, 1.6, 2.4), top * CFrame.new(0, jibY + 1.7, 5), C.SteelDark, M.Metal))
		for k = 0, 2 do
			add(P(rot, "Counterweight", Vector3.new(3.4, 3.6, 0.95), top * CFrame.new(0, jibY - 1.1, cL - 1.6 + k * 1.0), C.Concrete, M.Concrete))
		end
		add(ConstructionKit.Rod(rot, "Pendant", apexTop.Position, (top * CFrame.new(0, jibY + 0.8, cL + 0.5)).Position, 0.16, C.SteelDark, M.Metal))
		-- chariot, câbles, moufle, crochet, charge (bougent à part)
		local trolley = Instance.new("Model")
		trolley.Name = "Trolley"
		trolley.Parent = model
		rig.TrolleyParts = {
			Body = P(trolley, "TrolleyBody", Vector3.new(2.6, 0.6, 1.8), CFrame.new(), dark, M.Metal),
			RopeA = P(trolley, "Rope", Vector3.new(0.08, 1, 0.08), CFrame.new(), C.Rubber, M.Metal, { Shadow = false }),
			RopeB = P(trolley, "Rope", Vector3.new(0.08, 1, 0.08), CFrame.new(), C.Rubber, M.Metal, { Shadow = false }),
			Block = P(trolley, "HookBlock", Vector3.new(1.3, 1.1, 0.7), CFrame.new(), yellow, M.Metal),
			Hook = P(trolley, "Hook", Vector3.new(0.3, 0.9, 0.3), CFrame.new(), C.SteelDark, M.Metal, { Shape = "Block" }),
			Pallet = P(trolley, "LoadPallet", Vector3.new(3.4, 0.4, 3.4), CFrame.new(), C.Pallet, M.WoodPlanks),
			Load = P(trolley, "LoadBricks", Vector3.new(3, 2.2, 3), CFrame.new(), C.Brick, M.Brick),
			SlingA = P(trolley, "Sling", Vector3.new(0.1, 3.6, 0.1), CFrame.new(), C.Orange, M.Fabric, { Shadow = false }),
			SlingB = P(trolley, "Sling", Vector3.new(0.1, 3.6, 0.1), CFrame.new(), C.Orange, M.Fabric, { Shadow = false }),
		}
		rig.JibY = jibY
	end
	rig.Pose = function(self: Rig, angle: number, radius: number, drop: number, loaded: boolean)
		local pivot = self.Top * CFrame.Angles(0, angle, 0)
		rigMove(self, pivot)
		local tp = self.TrolleyParts
		if not tp then
			return
		end
		local r = math.clamp(radius, 6, self.Jib - 1)
		local trolleyCF = pivot * CFrame.new(0, self.JibY - 0.45, -1.2 - r)
		local ropeLen = math.max(1, drop)
		local blockCF = trolleyCF * CFrame.new(0, -ropeLen - 0.6, 0)
		local parts = { tp.Body, tp.Block, tp.Hook }
		local frames = { trolleyCF, blockCF, blockCF * CFrame.new(0, -1, 0) }
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		tp.RopeA.Size = Vector3.new(0.08, ropeLen, 0.08)
		tp.RopeB.Size = Vector3.new(0.08, ropeLen, 0.08)
		tp.RopeA.CFrame = trolleyCF * CFrame.new(-0.4, -ropeLen / 2 - 0.3, 0)
		tp.RopeB.CFrame = trolleyCF * CFrame.new(0.4, -ropeLen / 2 - 0.3, 0)
		local hidden = if loaded then 0 else 1
		for _, key in ipairs({ "Pallet", "Load", "SlingA", "SlingB" }) do
			tp[key].LocalTransparencyModifier = hidden
		end
		if loaded then
			local loadCF = blockCF * CFrame.new(0, -4.6, 0)
			tp.Load.CFrame = loadCF * CFrame.new(0, 1.3, 0)
			tp.Pallet.CFrame = loadCF
			tp.SlingA.CFrame = (blockCF * CFrame.new(-0.9, -2.6, 0)) * CFrame.Angles(0, 0, math.rad(-18))
			tp.SlingB.CFrame = (blockCF * CFrame.new(0.9, -2.6, 0)) * CFrame.Angles(0, 0, math.rad(18))
		end
	end
	-- position de départ
	rig:Pose(0, L * 0.5, 10, false)
	return rig
end

-- Cycle de travail de la grue : charge prise en A (angle, rayon, descente),
-- posée en B. t en secondes (période 40 s). Renvoie angle, rayon, descente, chargée.
function ConstructionKit.CraneCycle(t: number, a: { number }, b: { number }, high: number): (number, number, number, boolean)
	-- clés : t, angle, rayon, descente
	local keys = {
		{ 0, a[1], a[2], high },
		{ 4, a[1], a[2], a[3] }, -- descend sur la palette
		{ 5.5, a[1], a[2], a[3] }, -- accroche
		{ 9, a[1], a[2], high }, -- remonte
		{ 19, b[1], b[2], high }, -- pivote vers le chantier
		{ 23, b[1], b[2], b[3] }, -- dépose
		{ 24.5, b[1], b[2], b[3] },
		{ 28, b[1], b[2], high }, -- remonte à vide
		{ 38, a[1], a[2], high }, -- revient
		{ 40, a[1], a[2], high },
	}
	local v = keyed(keys, t)
	local u = t % 40
	return v[1], v[2], v[3], u >= 5.5 and u < 24.5
end

----------------------------------------------------------------------
-- 🚜 Pelleteuse
----------------------------------------------------------------------

-- Pelleteuse posée en baseCF (au sol, avant = -Z). rig:Pose(swing, boom, stick, bucket)
function ConstructionKit.Excavator(parent: Instance, baseCF: CFrame): Rig
	local model = Instance.new("Model")
	model.Name = "Excavator"
	model.Parent = parent
	local rig = newRig()
	rig.Model = model
	rig.Base = baseCF
	local yellow, dark = C.Yellow, C.SteelDark
	-- chenilles (fixes)
	for _, s in ipairs({ -1, 1 }) do
		local x = s * 2.85
		P(model, "Track", Vector3.new(1.8, 1.9, 9.2), baseCF * CFrame.new(x, 1.15, 0), C.Rubber, M.Slate, { Solid = true })
		for _, z in ipairs({ -4.6, 4.6 }) do
			P(model, "TrackEnd", Vector3.new(1.8, 2.3, 2.3), baseCF * CFrame.new(x, 1.15, z) * CFrame.Angles(0, 0, 0), C.Rubber, M.Slate, { Shape = "Cyl", Solid = true })
		end
		P(model, "TrackFrame", Vector3.new(0.5, 1.1, 8.4), baseCF * CFrame.new(x - s * 1.05, 1.4, 0), dark, M.Metal)
		for k = -1, 1 do
			P(model, "Roller", Vector3.new(0.4, 0.9, 0.9), baseCF * CFrame.new(x - s * 1.12, 0.95, k * 2.6), C.SteelDark, M.Metal, { Shape = "Cyl", Shadow = false })
		end
	end
	P(model, "Carbody", Vector3.new(3.8, 1.2, 4.2), baseCF * CFrame.new(0, 1.9, 0), dark, M.Metal, { Solid = true })
	-- tourelle (tourne) : repère = axe de rotation au-dessus des chenilles
	local swingCF = baseCF * CFrame.new(0, 2.6, 0)
	rig.SwingBase = swingCF
	local upper = Instance.new("Model")
	upper.Name = "Upper"
	upper.Parent = model
	local up = {}
	local function addU(part: BasePart)
		table.insert(up, part)
		rigAdd(rig, part, swingCF)
	end
	addU(ConstructionKit.CylY(upper, "SwingRing", 3.6, 0.5, swingCF * CFrame.new(0, 0.25, 0), dark, M.Metal))
	addU(P(upper, "Deck", Vector3.new(7.4, 0.8, 8.6), swingCF * CFrame.new(0, 0.9, 0.8), yellow, M.Metal, { Solid = true }))
	addU(P(upper, "EngineHood", Vector3.new(4.2, 2.3, 4.2), swingCF * CFrame.new(-1.5, 2.45, 2.2), yellow, M.Metal, { Solid = true }))
	addU(P(upper, "Counterweight", Vector3.new(7.2, 2.2, 1.6), swingCF * CFrame.new(0, 2.2, 4.6), C.SteelDark, M.Metal, { Solid = true }))
	addU(P(upper, "CounterweightRound", Vector3.new(7.2, 2.2, 2.2), swingCF * CFrame.new(0, 2.2, 5.1), C.SteelDark, M.Metal, { Shape = "Cyl" }))
	addU(P(upper, "Grille", Vector3.new(2.6, 0.1, 2.4), swingCF * CFrame.new(-1.6, 3.62, 2.3), C.Rubber, M.DiamondPlate))
	addU(ConstructionKit.CylY(upper, "Exhaust", 0.35, 1.6, swingCF * CFrame.new(-2.8, 4.2, 1.2), C.Rubber, M.Metal))
	-- cabine à gauche (vue du conducteur), vitrée
	local cabCF = swingCF * CFrame.new(1.75, 3.9, -1.6)
	rig.CabLocal = swingCF:ToObjectSpace(cabCF)
	addU(P(upper, "CabBack", Vector3.new(3.1, 5.2, 0.3), cabCF * CFrame.new(0, 0, 1.55), yellow, M.Metal))
	addU(P(upper, "CabRoof", Vector3.new(3.3, 0.3, 3.5), cabCF * CFrame.new(0, 2.7, 0), yellow, M.Metal))
	for _, s in ipairs({ -1, 1 }) do
		addU(P(upper, "CabPillar", Vector3.new(0.25, 5.2, 0.25), cabCF * CFrame.new(s * 1.45, 0, -1.6), yellow, M.Metal))
		addU(P(upper, "CabSide", Vector3.new(0.12, 4.4, 2.9), cabCF * CFrame.new(s * 1.5, 0.2, 0), C.Glass, M.Glass, { Alpha = 0.4, Reflect = 0.1 }))
	end
	addU(P(upper, "CabFront", Vector3.new(2.7, 3.6, 0.12), cabCF * CFrame.new(0, 0.6, -1.6), C.Glass, M.Glass, { Alpha = 0.45, Reflect = 0.1 }))
	addU(P(upper, "Seat", Vector3.new(1.4, 0.5, 1.3), cabCF * CFrame.new(0, -1.55, 0.3), C.Rubber, M.Fabric))
	-- flèche / balancier / godet (articulés)
	rig.BoomPivot = CFrame.new(0.3, 1.9, -2.6) -- (repère tourelle)
	local boomL, stickL = 13.8, 7.5
	rig.BoomL, rig.StickL = boomL, stickL
	rig.Boom = {
		P(upper, "Boom", Vector3.new(1.1, 1.5, boomL), CFrame.new(), yellow, M.Metal),
		P(upper, "BoomBend", Vector3.new(1.0, 1.2, 1.6), CFrame.new(), yellow, M.Metal),
	}
	rig.Stick = {
		P(upper, "Stick", Vector3.new(0.9, 1.2, stickL), CFrame.new(), yellow, M.Metal),
	}
	rig.Bucket = {
		P(upper, "BucketBack", Vector3.new(2.4, 1.9, 0.3), CFrame.new(), C.SteelDark, M.Metal),
		P(upper, "BucketFloor", Vector3.new(2.4, 0.3, 1.8), CFrame.new(), C.SteelDark, M.Metal),
		P(upper, "BucketTeeth", Vector3.new(2.3, 0.25, 0.4), CFrame.new(), C.Steel, M.Metal),
		P(upper, "BucketDirt", Vector3.new(2.0, 0.7, 1.2), CFrame.new(), C.Dirt, M.Ground),
	}
	rig.Cyl = {
		P(upper, "BoomRam", Vector3.new(4.2, 0.55, 0.55), CFrame.new(), C.SteelDark, M.Metal, { Shape = "Cyl", Shadow = false }),
		P(upper, "BoomRod", Vector3.new(4.0, 0.3, 0.3), CFrame.new(), C.Steel, M.Metal, { Shape = "Cyl", Shadow = false, Reflect = 0.2 }),
		P(upper, "StickRam", Vector3.new(3.6, 0.5, 0.5), CFrame.new(), C.SteelDark, M.Metal, { Shape = "Cyl", Shadow = false }),
		P(upper, "StickRod", Vector3.new(3.4, 0.28, 0.28), CFrame.new(), C.Steel, M.Metal, { Shape = "Cyl", Shadow = false, Reflect = 0.2 }),
	}
	rig.Pose = function(self: Rig, swing: number, boom: number, stick: number, bucket: number, dirt: boolean)
		local body = self.SwingBase * CFrame.Angles(0, swing, 0)
		rigMove(self, body)
		local bp = body * self.BoomPivot * CFrame.Angles(boom, 0, 0)
		local bL, sL = self.BoomL, self.StickL
		local boomEnd = bp * CFrame.new(0, 0, -bL)
		local sp = boomEnd * CFrame.Angles(stick, 0, 0)
		local stickEnd = sp * CFrame.new(0, 0, -sL)
		local kp = stickEnd * CFrame.Angles(bucket, 0, 0)
		local parts = { self.Boom[1], self.Boom[2], self.Stick[1] }
		local frames = { bp * CFrame.new(0, 0, -bL / 2), boomEnd * CFrame.new(0, 0, 0.3), sp * CFrame.new(0, 0, -sL / 2) }
		-- godet : dos, fond, dents, terre
		table.insert(parts, self.Bucket[1])
		table.insert(frames, kp * CFrame.new(0, -0.95, 0))
		table.insert(parts, self.Bucket[2])
		table.insert(frames, kp * CFrame.new(0, -1.75, 0.75))
		table.insert(parts, self.Bucket[3])
		table.insert(frames, kp * CFrame.new(0, -1.75, 1.75))
		table.insert(parts, self.Bucket[4])
		table.insert(frames, kp * CFrame.new(0, -1.35, 0.8))
		-- vérins (fût accroché en bas, tige vers le haut : jamais étirés)
		local a1 = (body * CFrame.new(0.3, 1.0, -3.2)).Position
		local b1 = (bp * CFrame.new(0, -0.75, -bL * 0.45)).Position
		local a2 = (bp * CFrame.new(0, 0.85, -bL * 0.55)).Position
		local b2 = (sp * CFrame.new(0, 0.7, 0.9)).Position
		local c = self.Cyl
		local dir1 = (b1 - a1).Unit
		local dir2 = (b2 - a2).Unit
		table.insert(parts, c[1])
		table.insert(frames, ConstructionKit.RodCF(a1, a1 + dir1 * 4.2, true))
		table.insert(parts, c[2])
		table.insert(frames, ConstructionKit.RodCF(b1 - dir1 * 4.0, b1, true))
		table.insert(parts, c[3])
		table.insert(frames, ConstructionKit.RodCF(a2, a2 + dir2 * 3.6, true))
		table.insert(parts, c[4])
		table.insert(frames, ConstructionKit.RodCF(b2 - dir2 * 3.4, b2, true))
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		self.Bucket[4].LocalTransparencyModifier = if dirt then 0 else 1
		self.CabCF = body * self.CabLocal
	end
	rig:Pose(0, 0.5, -1.5, -0.2, false)
	return rig
end

-- Cycle de la pelleteuse (période 11 s) : creuse devant, pivote, vide sur le tas
function ConstructionKit.ExcavatorCycle(t: number, dumpSwing: number): (number, number, number, number, boolean)
	local keys = {
		{ 0, 0, 0.45, -1.3, -0.4 },
		{ 2.6, 0, 0.05, -2.2, 1.1 }, -- creuse (flèche basse, balancier rentré, godet fermé)
		{ 4.0, 0, 0.7, -1.9, 1.3 }, -- lève
		{ 6.0, dumpSwing, 0.75, -1.6, 1.3 }, -- pivote vers le tas
		{ 7.2, dumpSwing, 0.7, -1.1, -0.7 }, -- vide
		{ 9.4, 0, 0.45, -1.3, -0.4 }, -- revient
		{ 11, 0, 0.45, -1.3, -0.4 },
	}
	local v = keyed(keys, t)
	local u = t % 11
	return v[1], v[2], v[3], v[4], u >= 2.6 and u < 7.0
end

----------------------------------------------------------------------
-- Échafaudage tubulaire le long d'une façade
----------------------------------------------------------------------

export type ScaffoldOpts = {
	Lifts: number?, -- nombre de planchers
	LiftH: number?, -- hauteur entre planchers
	Bay: number?, -- entraxe des montants
	Net: boolean?, -- filet orange
	Ladder: boolean?,
}

-- frame : origine = pied gauche de la façade (au sol), +X le long du mur,
-- -Z vers l'extérieur (loin du mur). Renvoie la liste des pièces par étage
-- ({ [lift] = { parts } }) pour les animations.
function ConstructionKit.Scaffold(parent: Instance, frame: CFrame, length: number, opts: ScaffoldOpts?): { { BasePart } }
	local o = opts or {}
	local lifts = o.Lifts or 2
	local liftH = o.LiftH or 6.5
	local bay = o.Bay or 8
	local tube = C.Steel
	local byLift: { { BasePart } } = {}
	local bays = math.max(1, math.ceil(length / bay))
	local step = length / bays
	local rows = { -1.2, -4.2 } -- distance au mur (vers l'extérieur)
	for lift = 1, lifts do
		local list = {}
		byLift[lift] = list
		local y0 = (lift - 1) * liftH
		local y1 = lift * liftH
		for k = 0, bays do
			local x = k * step
			for _, z in ipairs(rows) do
				local cf = frame * CFrame.new(x, (y0 + y1) / 2, z)
				table.insert(list, ConstructionKit.CylY(parent, "Standard", 0.3, liftH, cf, tube, M.Metal, { Shadow = false }))
				if lift == 1 then
					table.insert(list, P(parent, "BasePlate", Vector3.new(0.9, 0.12, 0.9), frame * CFrame.new(x, 0.06, z), C.TimberDark, M.Wood, { Shadow = false }))
				end
			end
			-- moise (tube transversal) sous le plancher
			table.insert(list, ConstructionKit.Rod(parent, "Transom", (frame * CFrame.new(x, y1 - 0.25, rows[1] + 0.3)).Position, (frame * CFrame.new(x, y1 - 0.25, rows[2] - 0.3)).Position, 0.24, tube, M.Metal, true, { Shadow = false }))
		end
		-- lisses (le long du mur), plancher, plinthe, garde-corps
		for _, z in ipairs(rows) do
			table.insert(list, ConstructionKit.Rod(parent, "Ledger", (frame * CFrame.new(-0.3, y1 - 0.45, z)).Position, (frame * CFrame.new(length + 0.3, y1 - 0.45, z)).Position, 0.24, tube, M.Metal, true, { Shadow = false }))
		end
		table.insert(list, P(parent, "Boards", Vector3.new(length, 0.22, 2.7), frame * CFrame.new(length / 2, y1 - 0.1, (rows[1] + rows[2]) / 2), C.Timber, M.WoodPlanks, { Solid = false }))
		table.insert(list, P(parent, "ToeBoard", Vector3.new(length, 0.7, 0.12), frame * CFrame.new(length / 2, y1 + 0.35, rows[2] - 0.2), C.Orange, M.WoodPlanks, { Shadow = false }))
		table.insert(list, ConstructionKit.Rod(parent, "Guardrail", (frame * CFrame.new(-0.3, y1 + 3.1, rows[2])).Position, (frame * CFrame.new(length + 0.3, y1 + 3.1, rows[2])).Position, 0.22, C.Yellow, M.Metal, true, { Shadow = false }))
		-- diagonales (une travée sur deux, face extérieure)
		for k = 0, bays - 1, 2 do
			table.insert(list, ConstructionKit.Rod(parent, "Brace", (frame * CFrame.new(k * step, y0 + 0.3, rows[2] - 0.2)).Position, (frame * CFrame.new((k + 1) * step, y1 - 0.5, rows[2] - 0.2)).Position, 0.2, tube, M.Metal, true, { Shadow = false }))
		end
		if o.Net then
			table.insert(list, P(parent, "Net", Vector3.new(length, liftH - 0.4, 0.06), frame * CFrame.new(length / 2, (y0 + y1) / 2 + 0.2, rows[2] - 0.45), C.Orange, M.Fabric, { Alpha = 0.55, Shadow = false }))
		end
	end
	if o.Ladder ~= false then
		local list = byLift[1]
		local x = math.min(length - 1, step * 0.5)
		local h = lifts * liftH
		for _, s in ipairs({ -0.55, 0.55 }) do
			table.insert(list, P(parent, "LadderRail", Vector3.new(0.18, h + 1.5, 0.18), frame * CFrame.new(x + s, (h + 1.5) / 2, -2.7) * CFrame.Angles(math.rad(-12), 0, 0), C.Timber, M.Wood, { Shadow = false }))
		end
		table.insert(list, P(parent, "LadderRungs", Vector3.new(1.0, h + 1, 0.1), frame * CFrame.new(x, (h + 1) / 2, -2.7) * CFrame.Angles(math.rad(-12), 0, 0), C.TimberDark, M.WoodPlanks, { Alpha = 0.2, Shadow = false }))
	end
	return byLift
end

----------------------------------------------------------------------
-- Petits objets du chantier (frame = au sol, avant -Z)
----------------------------------------------------------------------

function ConstructionKit.Cone(parent: Instance, cf: CFrame)
	P(parent, "ConeBase", Vector3.new(1.3, 0.18, 1.3), cf * CFrame.new(0, 0.09, 0), C.Rubber, M.Rubber, { Shadow = false })
	ConstructionKit.CylY(parent, "Cone", 0.95, 0.8, cf * CFrame.new(0, 0.58, 0), C.Orange, M.SmoothPlastic, { Shadow = false })
	ConstructionKit.CylY(parent, "ConeBand", 0.72, 0.5, cf * CFrame.new(0, 1.22, 0), C.White, M.SmoothPlastic, { Shadow = false, Reflect = 0.1 })
	ConstructionKit.CylY(parent, "ConeTip", 0.46, 0.7, cf * CFrame.new(0, 1.8, 0), C.Orange, M.SmoothPlastic, { Shadow = false })
end

function ConstructionKit.Pallet(parent: Instance, cf: CFrame, w: number, d: number): CFrame
	P(parent, "Pallet", Vector3.new(w, 0.25, d), cf * CFrame.new(0, 0.5, 0), C.Pallet, M.WoodPlanks, { Solid = true })
	for _, s in ipairs({ -1, 0, 1 }) do
		P(parent, "PalletSkid", Vector3.new(0.45, 0.38, d), cf * CFrame.new(s * (w / 2 - 0.3), 0.19, 0), C.TimberDark, M.Wood, { Shadow = false })
	end
	return cf * CFrame.new(0, 0.625, 0)
end

function ConstructionKit.BrickPallet(parent: Instance, cf: CFrame, seed: number)
	local top = ConstructionKit.Pallet(parent, cf, 3.4, 3.4)
	local h = 2.2 + (seed % 3) * 0.3
	local color = C.Brick:Lerp(rgb(150, 70, 50), (seed % 5) / 8)
	P(parent, "Bricks", Vector3.new(3.1, h, 3.1), top * CFrame.new(0, h / 2, 0), color, M.Brick, { Solid = true })
	P(parent, "Wrap", Vector3.new(3.2, 0.3, 3.2), top * CFrame.new(0, h - 0.1, 0), rgb(230, 236, 240), M.Glass, { Alpha = 0.55, Shadow = false })
	P(parent, "Strap", Vector3.new(3.18, h + 0.1, 0.12), top * CFrame.new(0, h / 2, 0.6), rgb(40, 80, 180), M.Plastic, { Shadow = false })
end

function ConstructionKit.TimberStack(parent: Instance, cf: CFrame, length: number)
	for layer = 0, 2 do
		local count = 4 - layer
		for k = 0, count - 1 do
			local x = (k - (count - 1) / 2) * 1.05
			P(parent, "Beam", Vector3.new(0.9, 0.9, length), cf * CFrame.new(x, 0.45 + layer * 1.05 + 0.3, 0), C.Timber:Lerp(C.TimberDark, ((k + layer) % 3) / 6), M.Wood, { Solid = layer == 0 })
		end
		P(parent, "Batten", Vector3.new(count * 1.05 + 0.2, 0.15, 0.4), cf * CFrame.new(0, layer * 1.05 + 0.22, length / 2 - 1.2), C.TimberDark, M.Wood, { Shadow = false })
	end
end

function ConstructionKit.SteelBeams(parent: Instance, cf: CFrame, length: number)
	for k = 0, 1 do
		local b = cf * CFrame.new((k - 0.5) * 1.7, 0.2 + 0.75, 0)
		P(parent, "Web", Vector3.new(0.18, 1.2, length), b, rgb(170, 70, 56), M.Metal, { Solid = true })
		P(parent, "Flange", Vector3.new(1.1, 0.16, length), b * CFrame.new(0, 0.68, 0), rgb(170, 70, 56), M.Metal)
		P(parent, "Flange", Vector3.new(1.1, 0.16, length), b * CFrame.new(0, -0.68, 0), rgb(170, 70, 56), M.Metal)
	end
	for _, z in ipairs({ -length / 3, length / 3 }) do
		P(parent, "Chock", Vector3.new(3.6, 0.2, 0.6), cf * CFrame.new(0, 0.1, z), C.TimberDark, M.Wood, { Shadow = false })
	end
end

-- Tas (sable / terre) : dôme ellipsoïde à moitié enterré + un petit dôme de côté
function ConstructionKit.Pile(parent: Instance, cf: CFrame, w: number, h: number, color: Color3, material: Enum.Material)
	P(parent, "Pile", Vector3.new(w, h * 2, w * 0.85), cf, color, material, { Shape = "Egg", Solid = true })
	P(parent, "PileSlump", Vector3.new(w * 0.6, h * 1.1, w * 0.5), cf * CFrame.new(w * 0.32, 0, w * 0.22), color:Lerp(Color3.new(0, 0, 0), 0.06), material, { Shape = "Egg", Solid = true })
end

function ConstructionKit.CementBags(parent: Instance, cf: CFrame)
	local top = ConstructionKit.Pallet(parent, cf, 3.6, 2.8)
	for layer = 0, 1 do
		for k = 0, 2 - layer do
			local x = (k - (2 - layer) / 2) * 1.15
			P(parent, "CementBag", Vector3.new(1.05, 0.55, 2.4), top * CFrame.new(x, 0.3 + layer * 0.55, 0), rgb(214, 206, 188), M.Fabric)
		end
	end
	P(parent, "BagPrint", Vector3.new(1.0, 0.1, 1.2), top * CFrame.new(0, 1.18, 0), rgb(40, 110, 200), M.Fabric, { Shadow = false })
end

-- Bétonnière : renvoie le tambour (tourne) et son repère
function ConstructionKit.Mixer(parent: Instance, cf: CFrame): (BasePart, CFrame)
	P(parent, "MixerFrame", Vector3.new(0.3, 2.4, 3.2), cf * CFrame.new(0, 1.4, 0), C.Red, M.Metal, { Solid = true })
	P(parent, "MixerLeg", Vector3.new(2.6, 0.25, 0.25), cf * CFrame.new(0, 0.3, 1.4), C.Red, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		P(parent, "MixerWheel", Vector3.new(0.4, 1.2, 1.2), cf * CFrame.new(s * 1.3, 0.6, -1.2), C.Rubber, M.Rubber, { Shape = "Cyl" })
	end
	P(parent, "MixerMotor", Vector3.new(1, 0.9, 1.2), cf * CFrame.new(0.7, 1.3, 1.1), C.SteelDark, M.Metal)
	local drumCF = cf * CFrame.new(-0.9, 2.6, 0) * CFrame.Angles(0, 0, math.rad(35))
	local drum = P(parent, "MixerDrum", Vector3.new(2.6, 2.4, 2.4), drumCF, rgb(230, 90, 60), M.Metal, { Shape = "Cyl" })
	P(parent, "MixerMouth", Vector3.new(0.6, 1.5, 1.5), drumCF * CFrame.new(1.5, 0, 0), C.SteelDark, M.Metal, { Shape = "Cyl" })
	return drum, drumCF
end

-- Toilettes de chantier
function ConstructionKit.Portaloo(parent: Instance, cf: CFrame)
	P(parent, "LooBody", Vector3.new(3.4, 7, 3.4), cf * CFrame.new(0, 3.6, 0), C.Blue, M.SmoothPlastic, { Solid = true })
	P(parent, "LooRoof", Vector3.new(3.8, 0.4, 3.8), cf * CFrame.new(0, 7.3, 0), C.White, M.SmoothPlastic)
	P(parent, "LooBase", Vector3.new(3.6, 0.3, 3.6), cf * CFrame.new(0, 0.15, 0), rgb(30, 70, 150), M.SmoothPlastic)
	P(parent, "LooDoor", Vector3.new(2.6, 6.2, 0.12), cf * CFrame.new(0, 3.5, -1.74), rgb(30, 90, 180), M.SmoothPlastic)
	P(parent, "LooLatch", Vector3.new(0.5, 0.3, 0.1), cf * CFrame.new(0.8, 4, -1.84), C.Green, M.SmoothPlastic, { Shadow = false })
	ConstructionKit.CylY(parent, "LooVent", 0.35, 1.3, cf * CFrame.new(1.1, 8.0, 1.1), C.White, M.SmoothPlastic, { Shadow = false })
	local sign = P(parent, "LooSign", Vector3.new(1.2, 0.8, 0.1), cf * CFrame.new(0, 6.1, -1.85), C.White, M.SmoothPlastic, { Shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(120, 80)
	gui.LightInfluence = 1
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "WC"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = rgb(30, 70, 150)
	label.Parent = gui
	gui.Parent = sign
end

-- Chariot à briques (poussé par un ouvrier : poignée à 3,5 studs)
function ConstructionKit.Trolley(parent: Instance, cf: CFrame): { BasePart }
	local list = {}
	table.insert(list, P(parent, "TrolleyDeck", Vector3.new(2.6, 0.2, 3.2), cf * CFrame.new(0, 1.2, 0), C.SteelDark, M.DiamondPlate))
	for _, s in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1.1, 1.1 }) do
			table.insert(list, P(parent, "TrolleyWheel", Vector3.new(0.35, 0.95, 0.95), cf * CFrame.new(s * 1.2, 0.48, z), C.Rubber, M.Rubber, { Shape = "Cyl", Shadow = false }))
		end
		table.insert(list, P(parent, "TrolleyPost", Vector3.new(0.16, 2.3, 0.16), cf * CFrame.new(s * 1.0, 2.35, 1.5), C.Blue, M.Metal, { Shadow = false }))
	end
	table.insert(list, P(parent, "TrolleyHandle", Vector3.new(2.2, 0.18, 0.18), cf * CFrame.new(0, 3.45, 1.5), C.Rubber, M.Rubber, { Shadow = false }))
	table.insert(list, P(parent, "TrolleyBricks", Vector3.new(2.2, 1.1, 2.4), cf * CFrame.new(0, 1.85, -0.2), C.Brick, M.Brick))
	return list
end

-- Tréteau + planche (établi du charpentier)
function ConstructionKit.Sawhorse(parent: Instance, cf: CFrame)
	for _, z in ipairs({ -1.6, 1.6 }) do
		for _, s in ipairs({ -1, 1 }) do
			P(parent, "SawLeg", Vector3.new(0.2, 2.2, 0.2), cf * CFrame.new(s * 0.35, 1.0, z) * CFrame.Angles(0, 0, s * math.rad(12)), C.TimberDark, M.Wood, { Shadow = false })
		end
	end
	P(parent, "SawTop", Vector3.new(0.5, 0.25, 4.2), cf * CFrame.new(0, 2.15, 0), C.Timber, M.Wood)
	P(parent, "Plank", Vector3.new(1.4, 0.2, 5.4), cf * CFrame.new(0, 2.38, 0), C.Timber:Lerp(C.White, 0.2), M.WoodPlanks)
end

-- Bungalow de chantier (18 x 7 x 7,8), porte côté -Z
function ConstructionKit.Office(parent: Instance, cf: CFrame, title: string)
	P(parent, "OfficeBody", Vector3.new(18, 7.2, 7.8), cf * CFrame.new(0, 4.2, 0), C.Office, M.Metal, { Solid = true })
	P(parent, "OfficeRoof", Vector3.new(18.4, 0.4, 8.2), cf * CFrame.new(0, 8.0, 0), C.SteelDark, M.Metal)
	P(parent, "OfficeSkirt", Vector3.new(17.6, 0.6, 7.4), cf * CFrame.new(0, 0.3, 0), C.SteelDark, M.Metal)
	for _, x in ipairs({ -8.6, 8.6 }) do
		P(parent, "OfficeCorner", Vector3.new(0.8, 7.6, 0.4), cf * CFrame.new(x, 4.2, -4.0), C.SteelDark, M.Metal)
	end
	for _, x in ipairs({ -4.5, 4.5 }) do
		P(parent, "OfficeWindow", Vector3.new(3.6, 2.6, 0.1), cf * CFrame.new(x, 5, -3.96), C.Glass, M.Glass, { Alpha = 0.3, Reflect = 0.15 })
		P(parent, "OfficeSill", Vector3.new(3.9, 0.2, 0.3), cf * CFrame.new(x, 3.6, -4.05), C.SteelDark, M.Metal, { Shadow = false })
	end
	P(parent, "OfficeDoor", Vector3.new(2.8, 6, 0.12), cf * CFrame.new(0, 3.6, -3.97), rgb(60, 90, 140), M.Metal)
	P(parent, "OfficeKnob", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(1, 3.6, -4.08), C.Steel, M.Metal, { Shape = "Ball", Shadow = false })
	P(parent, "OfficeStep", Vector3.new(3.8, 0.6, 1.6), cf * CFrame.new(0, 0.3, -4.7), C.SteelDark, M.DiamondPlate, { Solid = true })
	P(parent, "OfficeAC", Vector3.new(2, 1.4, 1), cf * CFrame.new(6.5, 6.6, 4.4), C.White, M.Metal)
	local sign = P(parent, "OfficeSign", Vector3.new(7, 1.4, 0.12), cf * CFrame.new(0, 7.1, -4.0), rgb(255, 214, 40), M.SmoothPlastic, { Shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(500, 100)
	gui.LightInfluence = 1
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = title
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = rgb(40, 34, 30)
	label:SetAttribute("LocText", "Site office")
	label.Parent = gui
	gui.Parent = sign
end

-- Grand panneau "Bientôt ta maison ici !" : texte sur la face -Z
function ConstructionKit.Billboard(parent: Instance, cf: CFrame, title: string, subtitle: string): TextLabel
	for _, s in ipairs({ -1, 1 }) do
		P(parent, "BoardPost", Vector3.new(0.5, 9, 0.5), cf * CFrame.new(s * 5.8, 4.5, 0.35), C.TimberDark, M.Wood, { Solid = true })
	end
	local board = P(parent, "BoardPanel", Vector3.new(13, 6.2, 0.3), cf * CFrame.new(0, 6.4, 0), C.White, M.SmoothPlastic, { Solid = true })
	P(parent, "BoardFrame", Vector3.new(13.4, 0.35, 0.4), cf * CFrame.new(0, 9.6, 0), C.Yellow, M.Metal, { Shadow = false })
	P(parent, "BoardFrame", Vector3.new(13.4, 0.35, 0.4), cf * CFrame.new(0, 3.2, 0), C.Yellow, M.Metal, { Shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(650, 310)
	gui.LightInfluence = 0.8
	gui.MaxDistance = 220
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = rgb(255, 246, 250)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(rgb(255, 250, 238), rgb(255, 222, 238))
	grad.Rotation = 90
	grad.Parent = bg
	-- bandes jaune / noir de chantier (haut et bas)
	for _, y in ipairs({ 0, 0.9 }) do
		local band = Instance.new("Frame")
		band.Size = UDim2.new(1, 0, 0.1, 0)
		band.Position = UDim2.fromScale(0, y)
		band.BackgroundColor3 = rgb(250, 196, 30)
		band.BorderSizePixel = 0
		band.ClipsDescendants = true
		band.Parent = bg
		for k = 0, 12 do
			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(0, 22, 3, 0)
			stripe.AnchorPoint = Vector2.new(0.5, 0.5)
			stripe.Position = UDim2.new(0, k * 56, 0.5, 0)
			stripe.Rotation = 35
			stripe.BackgroundColor3 = rgb(40, 36, 34)
			stripe.BorderSizePixel = 0
			stripe.Parent = band
		end
	end
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.05, 0.14)
	t.Size = UDim2.fromScale(0.9, 0.44)
	t.Text = title
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = rgb(236, 72, 140)
	t.Parent = bg
	local s = Instance.new("TextLabel")
	s.Name = "Subtitle"
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromScale(0.06, 0.6)
	s.Size = UDim2.fromScale(0.88, 0.26)
	s.Text = subtitle
	s.TextScaled = true
	s.Font = Enum.Font.GothamBold
	s.TextColor3 = rgb(70, 50, 80)
	s.Parent = bg
	gui.Parent = board
	return t
end

return ConstructionKit
