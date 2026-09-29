--[[
	FairKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FairKit

	🎡 Boîte à outils du DÉCOR de la fête (v9.9, FAIR99), partagée par
	FairFx (fête, manèges d'origine), FairAnnexFx (grand huit, bateau
	pirate, train fantôme, trampolines, palais des glaces) et FairCircus
	(chapiteau + spectacle). Pièces LOCALES, ancrées, sans collision par
	défaut (Solid = on marche dessus), sans ombre pour les petites pièces,
	lueurs "NightGlow" (TownAtmosphere : Neon la nuit seulement), aucun son.

	Manèges : un "RideFx" range les pièces MOBILES par groupe
	(FairRides.Pose) ; FairKit.StepRide recalcule la pose à l'heure donnée et
	déplace tout (décor + sièges du serveur) en UN BulkMoveTo par liste.
]]

local FairRides = require(game:GetService("ReplicatedStorage").Shared.FairRides)

local FairKit = {}

local M = Enum.Material
FairKit.M = M
FairKit.UP = Vector3.new(0, 1, 0)
FairKit.VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)
FairKit.BALL = Enum.PartType.Ball
FairKit.CYL = Enum.PartType.Cylinder
FairKit.TAU = math.pi * 2

-- Palette (douce, "mignon-réaliste")
FairKit.C = {
	Pink = Color3.fromRGB(255, 132, 180),
	Hot = Color3.fromRGB(236, 72, 140),
	Cream = Color3.fromRGB(255, 244, 226),
	Gold = Color3.fromRGB(226, 184, 92),
	White = Color3.fromRGB(250, 250, 252),
	Mint = Color3.fromRGB(128, 222, 190),
	Sky = Color3.fromRGB(126, 196, 255),
	Lilac = Color3.fromRGB(186, 150, 246),
	Lemon = Color3.fromRGB(255, 222, 110),
	Steel = Color3.fromRGB(96, 100, 120),
	SteelLight = Color3.fromRGB(196, 200, 214),
	Wood = Color3.fromRGB(186, 134, 90),
	WoodDark = Color3.fromRGB(122, 84, 56),
	Ink = Color3.fromRGB(92, 58, 96),
	Bulb = Color3.fromRGB(255, 232, 180),
	Red = Color3.fromRGB(214, 44, 56),
	Navy = Color3.fromRGB(40, 52, 96),
	Rubber = Color3.fromRGB(40, 40, 46),
}
FairKit.PALETTE = { FairKit.C.Pink, FairKit.C.Sky, FairKit.C.Lemon, FairKit.C.Mint, FairKit.C.Lilac, Color3.fromRGB(255, 170, 120) }

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

function FairKit.Part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
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
	p.Parent = parent
	return p
end

-- Pièce sur laquelle on marche / contre laquelle on bute (localement)
function FairKit.Solid(p: BasePart): BasePart
	p.CanCollide = true
	p.CastShadow = true
	return p
end

-- Ampoule : mate le jour, Neon la nuit (TownAtmosphere, attribut NightGlow)
function FairKit.Glow(p: BasePart): BasePart
	p:SetAttribute("NightGlow", true)
	return p
end

function FairKit.RodCF(a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
end

-- Tube (cylindre) de a à b
function FairKit.Rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?): BasePart
	return FairKit.Part(parent, name, Vector3.new((b - a).Magnitude, d, d), FairKit.RodCF(a, b), color, material or M.Metal, FairKit.CYL)
end

function FairKit.BeamCF(a: Vector3, b: Vector3): CFrame
	local dir = b - a
	if math.abs(dir.Unit.Y) > 0.98 then
		return CFrame.new((a + b) / 2) * CFrame.Angles(math.rad(90), 0, 0)
	end
	return CFrame.lookAt((a + b) / 2, b)
end

-- Poutre (bloc) de a à b, section w x h
function FairKit.Beam(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3, material: Enum.Material?): BasePart
	return FairKit.Part(parent, name, Vector3.new(w, h, (b - a).Magnitude), FairKit.BeamCF(a, b), color, material or M.Metal)
end

-- Triangle rectangle (WedgePart) : angle droit en p0, côtés le long de u (l1) et v (l2)
function FairKit.Tri(p0: Vector3, u: Vector3, v: Vector3, l1: number, l2: number, t: number): (Vector3, CFrame)
	local Z = -v
	local X = u:Cross(Z)
	return Vector3.new(t, l1, l2), CFrame.fromMatrix(p0 + u * (l1 / 2) + v * (l2 / 2), X, u, Z)
end

-- Treillis métallique entre deux points (2 membrures + croisillons en zigzag)
-- `side` = direction de la largeur (perpendiculaire à a->b)
function FairKit.Truss(parent: Instance, name: string, a: Vector3, b: Vector3, side: Vector3, width: number, d: number, color: Color3, bays: number?)
	local half = side.Unit * (width / 2)
	local a1, a2, b1, b2 = a + half, a - half, b + half, b - half
	FairKit.Rod(parent, name, a1, b1, d, color)
	FairKit.Rod(parent, name, a2, b2, d, color)
	local n = bays or math.max(2, math.floor((b - a).Magnitude / (width * 1.3) + 0.5))
	for i = 0, n - 1 do
		local p = a1:Lerp(b1, i / n)
		local q = a2:Lerp(b2, (i + 1) / n)
		local r = a1:Lerp(b1, (i + 1) / n)
		FairKit.Rod(parent, name .. "Lace", p, q, d * 0.6, color)
		FairKit.Rod(parent, name .. "Lace", q, r, d * 0.6, color)
	end
end

-- Panneau (SurfaceGui sur la face avant d'une pièce) avec un texte
function FairKit.Sign(p: BasePart, text: string, textColor: Color3, bg: Color3?, font: Enum.Font?, face: Enum.NormalId?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.5
	gui.MaxDistance = 260
	gui.Parent = p
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg or FairKit.C.White
	frame.BackgroundTransparency = bg and 0 or 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.04, 0.1)
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Font = font or Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Parent = frame
	return label
end

-- Rangée d'ampoules de a à b (n ampoules, couleurs alternées)
function FairKit.Bulbs(parent: Instance, a: Vector3, b: Vector3, n: number, size: number?, colors: { Color3 }?)
	local list = colors or { FairKit.C.Bulb }
	for i = 0, n - 1 do
		local p = if n == 1 then (a + b) / 2 else a:Lerp(b, i / (n - 1))
		FairKit.Glow(FairKit.Part(parent, "Bulb", Vector3.one * (size or 0.3), CFrame.new(p), list[i % #list + 1], M.SmoothPlastic, FairKit.BALL))
	end
end

----------------------------------------------------------------------
-- Manèges : pièces MOBILES rangées par groupe
----------------------------------------------------------------------

export type RideFx = {
	Def: any,
	Base: CFrame,
	Model: Model,
	Parts: { BasePart },
	Locals: { CFrame },
	Group: { number },
	Frames: { CFrame },
	Groups: { CFrame },
	Seats: { BasePart },
	SeatIndex: { number },
	SeatFrames: { CFrame },
	SeatCheck: number,
	Radius: number,
	Extra: any,
}

function FairKit.NewRide(folder: Instance, def: any, base: CFrame, t: number): RideFx
	local model = Instance.new("Model")
	model.Name = def.Id
	model.Parent = folder
	local r: RideFx = {
		Def = def,
		Base = base,
		Model = model,
		Parts = {},
		Locals = {},
		Group = {},
		Frames = {},
		Groups = {},
		Seats = {},
		SeatIndex = {},
		SeatFrames = {},
		SeatCheck = 0,
		Radius = 30,
		Extra = nil,
	}
	FairRides.Pose(def, t, r.Groups)
	return r
end

-- Pièce fixe du manège (repère de la Base)
function FairKit.Fixed(r: RideFx, name: string, size: Vector3, loc: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
	return FairKit.Part(r.Model, name, size, r.Base * loc, color, material, shape, className)
end

-- Pièce qui suit le groupe `g` (loc = repère du groupe)
function FairKit.Moving(r: RideFx, g: number, name: string, size: Vector3, loc: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
	local world = r.Base * (r.Groups[g] or CFrame.identity) * loc
	local p = FairKit.Part(r.Model, name, size, world, color, material, shape, className)
	table.insert(r.Parts, p)
	table.insert(r.Locals, loc)
	table.insert(r.Group, g)
	table.insert(r.Frames, world)
	return p
end

-- Sièges du serveur (Fair > Rides > <Id> > RideSeat)
function FairKit.FindSeats(r: RideFx, fairFolder: Instance)
	table.clear(r.Seats)
	table.clear(r.SeatIndex)
	table.clear(r.SeatFrames)
	local rides = fairFolder:FindFirstChild("Rides")
	local folder = rides and rides:FindFirstChild(r.Def.Id)
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetChildren()) do
		local index = d:GetAttribute("SeatIndex")
		if d:IsA("Seat") and type(index) == "number" then
			table.insert(r.Seats, d)
			table.insert(r.SeatIndex, index)
		end
	end
end

-- Pose à l'heure t : décor (si `decor`) + sièges du serveur, en 2 BulkMoveTo
function FairKit.StepRide(r: RideFx, t: number, decor: boolean)
	local kind = r.Def.Kind
	if kind == "Bumper" or kind == "Circus" or kind == "Trampolines" or kind == "Mirrors" then
		if decor and r.Extra and r.Extra.Step then
			r.Extra.Step(t)
		end
		return
	end
	local groups = r.Groups
	FairRides.Pose(r.Def, t, groups)
	if decor then
		local frames, locals, group, base = r.Frames, r.Locals, r.Group, r.Base
		for i = 1, #frames do
			frames[i] = base * groups[group[i]] * locals[i]
		end
		if #frames > 0 then
			workspace:BulkMoveTo(r.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		if r.Extra and r.Extra.Step then
			r.Extra.Step(t)
		end
	end
	local seats = r.Seats
	if #seats > 0 then
		local seatFrames, idx, base = r.SeatFrames, r.SeatIndex, r.Base
		for i = 1, #seats do
			seatFrames[i] = base * FairRides.SeatLocal(kind, idx[i], groups)
		end
		workspace:BulkMoveTo(seats, seatFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- Horloge LISSE du serveur : workspace:GetServerTimeNow() est recalée par
-- petits sauts quand la synchro réseau s'affine ; ici l'écart avec
-- os.clock() glisse doucement (≤ 5 % du temps écoulé) -> une pose qui
-- avance sans à-coup d'une image à l'autre, identique sur tous les écrans
-- (à quelques ms près).
----------------------------------------------------------------------

local clockOffset: number? = nil
local lastClock = 0
function FairKit.Now(): number
	local c = os.clock()
	local target = workspace:GetServerTimeNow() - c
	local off = clockOffset
	if off == nil or math.abs(target - off) > 1 then
		off = target -- (premier appel, ou gros écart : on se recale d'un coup)
	else
		local dt = math.clamp(c - lastClock, 0, 0.25)
		local maxStep = dt * 0.05
		off += math.clamp(target - off, -maxStep, maxStep)
	end
	clockOffset = off
	lastClock = c
	return c + (off :: number)
end

return FairKit
