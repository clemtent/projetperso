--[[
	ParkPlay (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ParkPlay

	🛝 L'AIRE DE JEUX de Dopamine Town, côté CLIENT (v9.9, PARK99).
	"Rien ne fonctionne" (v9.8) -> ici TOUT se fait pour de vrai, avec une
	animation :
	  - 🎠 3 BALANÇOIRES (portique en acier, vraies chaînes à maillons,
	    sangles en caoutchouc) : E -> on s'assoit, la balançoire part en
	    PENDULE (ω = √(g/L) à l'échelle réelle), l'amplitude monte quand on
	    pompe (jambes tendues à l'aller, repliées au retour), les mains
	    tiennent les chaînes ;
	  - 🛝 TOBOGGAN : E au pied de l'échelle -> l'avatar grimpe barreau par
	    barreau (mains / pieds alternés), s'assoit en haut et GLISSE (vitesse
	    calculée : gravité, frottement, profil courbe), sort en bas et se
	    relève ; mur d'escalade grimpable (TrussPart du serveur) ;
	  - ⚖️ TAPE-CUL (2 places : seul, la bascule se fait avec le poids ; à
	    deux, chacun pousse à son tour) ; 🌀 TOURNIQUET (4 places, il prend de
	    la vitesse et ralentit tout seul) ; 🐴🦆 JEUX À RESSORT (tangage,
	    roulis, rebond ; le ressort se tord) ;
	  - 🐒 BARRES DE SINGE : E à un bout -> on monte, on se suspend, on
	    avance barre après barre (bras alternés, corps qui balance) et on
	    saute à l'autre bout ;
	  - 🏖️ BAC À SABLE : E -> à genoux, la pelle creuse (trou + tas qui
	    grossit, grains qui volent), un château de sable apparaît ;
	  - 🪑 2 bancs des parents (SitAnimator : pose et attentes du banc).
	Les jeux qui bougent le font d'après l'heure du SERVEUR et 4 attributs
	(ParkMotion) : tout le monde voit la même chose. Les sièges du serveur
	(invisibles) sont déplacés localement avec le décor : un avatar assis
	suit sa balançoire sans à-coup (RenderStepped). Les poses (Motor6D
	.Transform, R15 et R6, IK à 2 os pour les bras) sont écrites dans
	Stepped, après l'Animator, pour nous ET pour les autres joueurs proches
	(assis, sur la glissière, sur l'échelle ou suspendus aux barres).

	Construit par TownGreenery quand l'avatar approche (NearDetail
	"Playground") : ParkPlay.Build(g, parent, serverModel). Détruit avec le
	dossier de TownGreenery : tout est remis (pose, PlatformStand).
	Aucun son, aucune lumière, rien sur le serveur.

	API :
	  ParkPlay.Build(g: CFrame, parent: Instance, server: Instance?) -> park
	  ParkPlay.Debug() -> table   (tests / rendus)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage.Shared.Locale)
local ParkMotion = require(ReplicatedStorage.Shared.ParkMotion)

local ParkPlay = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local rad = math.rad
local TAU = math.pi * 2
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local I = CFrame.identity
local UP = Vector3.new(0, 1, 0)

local ANIM_R = 170 -- (studs) jeux animés en deçà
local POSE_R = 90 -- (studs) avatars des autres posés en deçà
local STEP_BUILD = 1 -- morceaux construits par image

-- Couleurs (aire de jeux moderne : acier thermolaqué, PEHD, bois, caoutchouc)
local GREEN = rgb(46, 118, 92)
local GREEN_D = rgb(34, 92, 72)
local RED = rgb(206, 64, 58)
local BLUE = rgb(48, 110, 186)
local BLUE_D = rgb(36, 84, 150)
local YELLOW = rgb(246, 196, 52)
local ORANGE = rgb(244, 138, 52)
local STEEL = rgb(176, 182, 190)
local STEEL_D = rgb(112, 118, 128)
local RUBBER_B = rgb(38, 38, 42)
local WOOD = rgb(168, 118, 76)
local WOOD_L = rgb(196, 150, 104)
local WHITE = rgb(248, 248, 244)
local SAND = rgb(232, 206, 156)
local SAND_D = rgb(200, 172, 124)
local INK = rgb(40, 34, 40)
local IRON = rgb(52, 50, 58)

----------------------------------------------------------------------
-- Petites fabriques (pièces locales, ancrées, sans collision ni requête)
----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, shadow: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = shadow == true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function egg(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = newPart(parent, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function ball(parent: Instance, name: string, center: Vector3, d: number, color: Color3, material: Enum.Material?): Part
	return newPart(parent, name, Vector3.new(d, d, d), CFrame.new(center), color, material, BALL)
end

-- Repère d'un cylindre de a à b (axe X de la pièce = a -> b)
local function rodCF(a: Vector3, b: Vector3): CFrame
	local dir = b - a
	local len = dir.Magnitude
	if len < 1e-4 then
		return CFrame.new(a)
	end
	dir = dir / len
	local up = math.abs(dir.Y) > 0.95 and Vector3.new(1, 0, 0) or UP
	local z = dir:Cross(up).Unit
	local y = z:Cross(dir).Unit
	return CFrame.fromMatrix((a + b) / 2, dir, y, z)
end

local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?, shadow: boolean?): Part
	return newPart(parent, name, Vector3.new((b - a).Magnitude, d, d), rodCF(a, b), color, material or M.Metal, CYL, shadow)
end

-- Disque à axe vertical, dessus à `top` (dans le repère `cf`)
local function disc(parent: Instance, name: string, cf: CFrame, top: number, radius: number, thickness: number, color: Color3, material: Enum.Material?, shadow: boolean?): Part
	return newPart(parent, name, Vector3.new(thickness, radius * 2, radius * 2), cf * CFrame.new(0, top - thickness / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, material, CYL, shadow)
end

-- Bloc entre deux points (section w x h)
local function slab(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3, material: Enum.Material?, shadow: boolean?): Part
	local dir = b - a
	local up = math.abs(dir.Unit.Y) > 0.95 and Vector3.new(1, 0, 0) or UP
	return newPart(parent, name, Vector3.new(w, h, dir.Magnitude), CFrame.lookAt((a + b) / 2, b, up), color, material, nil, shadow)
end

local function label(p: BasePart, text: string, color: Color3, bg: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ParkSign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.MaxDistance = 140
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = frame
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.05, 0.12)
	t.Size = UDim2.fromScale(0.9, 0.76)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.Parent = frame
	gui.Parent = p
end

----------------------------------------------------------------------
-- Groupes mobiles (pièces + décalages figés par rapport au repère du jeu)
----------------------------------------------------------------------

type Group = { Parts: { BasePart }, Locals: { CFrame }, Frames: { CFrame }, Rest: CFrame }

local function newGroup(rest: CFrame): Group
	return { Parts = {}, Locals = {}, Frames = {}, Rest = rest }
end

-- Toutes les pièces de `folder` construites au repos (repère `rest`) -> groupe
local function adopt(group: Group, folder: Instance)
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(group.Parts, d)
			table.insert(group.Locals, group.Rest:ToObjectSpace(d.CFrame))
			table.insert(group.Frames, d.CFrame)
		end
	end
end

local function moveGroup(group: Group, frame: CFrame)
	local frames, locals = group.Frames, group.Locals
	for i = 1, #frames do
		frames[i] = frame * locals[i]
	end
	if #frames > 0 then
		workspace:BulkMoveTo(group.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------

type Piece = {
	Kind: string, -- "Swing" | "Seesaw" | "Merry" | "Spring"
	Index: number,
	Groups: { Group },
	Server: Instance?, -- Model du serveur (attributs On / T0 / A0 / W0 + sièges)
	Seats: { [number]: Seat }, -- siège du serveur par place
	Settled: boolean,
	Extra: any,
}

type Park = {
	G: CFrame,
	Parent: Instance,
	Folder: Model,
	Server: Instance?,
	Queue: { () -> () },
	Pieces: { Piece },
	Prompts: { ProximityPrompt },
	Conns: { RBXScriptConnection },
	Scan: number,
	Sand: { any },
	Dead: boolean,
}

local parks: { Park } = {}
local conns: { RBXScriptConnection } = {}
local running = false
local failed = false
local clock = 0

----------------------------------------------------------------------
-- 🧍 Poses : Motor6D.Transform (R15 / R6), IK à 2 os pour les bras
----------------------------------------------------------------------

local R15: { [string]: { string } } = {
	Root = { "LowerTorso", "Root" }, Waist = { "UpperTorso", "Waist" }, Neck = { "Head", "Neck" },
	RShoulder = { "RightUpperArm", "RightShoulder" }, RElbow = { "RightLowerArm", "RightElbow" }, RWrist = { "RightHand", "RightWrist" },
	LShoulder = { "LeftUpperArm", "LeftShoulder" }, LElbow = { "LeftLowerArm", "LeftElbow" }, LWrist = { "LeftHand", "LeftWrist" },
	RHip = { "RightUpperLeg", "RightHip" }, RKnee = { "RightLowerLeg", "RightKnee" }, RAnkle = { "RightFoot", "RightAnkle" },
	LHip = { "LeftUpperLeg", "LeftHip" }, LKnee = { "LeftLowerLeg", "LeftKnee" }, LAnkle = { "LeftFoot", "LeftAnkle" },
}
local R6: { [string]: { string } } = {
	Root = { "HumanoidRootPart", "RootJoint" }, Neck = { "Torso", "Neck" },
	RShoulder = { "Torso", "Right Shoulder" }, LShoulder = { "Torso", "Left Shoulder" },
	RHip = { "Torso", "Right Hip" }, LHip = { "Torso", "Left Hip" },
}

type Rig = { R6: boolean, M: { [string]: Motor6D }, Root: BasePart, Humanoid: Humanoid, Character: Model }

local rigs: { [Model]: Rig } = {}

local function rigOf(character: Model): Rig?
	local cached = rigs[character]
	if cached and cached.Root.Parent == character and cached.M.Root and cached.M.Root.Parent then
		return cached
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local map = r6 and R6 or R15
	local motors: { [string]: Motor6D } = {}
	for key, spec in pairs(map) do
		local part = character:FindFirstChild(spec[1])
		local m = part and part:FindFirstChild(spec[2])
		if m and m:IsA("Motor6D") then
			motors[key] = m
		end
	end
	if r6 and not motors.Root then
		-- (R6 : RootJoint parfois rangé dans le Torso)
		local torso = character:FindFirstChild("Torso")
		local m = torso and torso:FindFirstChild("RootJoint")
		if m and m:IsA("Motor6D") then
			motors.Root = m
		end
	end
	if not motors.Root or not motors.RShoulder or not motors.LShoulder or not motors.RHip or not motors.LHip then
		return nil
	end
	if not r6 and (not motors.Waist or not motors.RElbow or not motors.LElbow) then
		return nil
	end
	local rig: Rig = { R6 = r6, M = motors, Root = root, Humanoid = humanoid, Character = character }
	rigs[character] = rig
	return rig
end

-- rotation `r` exprimée dans le repère de la pièce parente, au pivot
local function conj(m: Motor6D, r: CFrame): CFrame
	local c = m.C0.Rotation
	return c:Inverse() * r * c
end

-- Repère orthonormé : X = a, Y = partie de f perpendiculaire à a
local function basis(a: Vector3, f: Vector3): CFrame
	local x = a.Unit
	local y = f - x * f:Dot(x)
	if y.Magnitude < 1e-4 then
		y = math.abs(x.Y) < 0.9 and UP - x * x.Y or Vector3.new(0, 0, 1) - x * x.Z
	end
	y = y.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

local FRONT = Vector3.new(0, 0, -1)

-- Bras R15 : épaule + coude pour poser la main en `target` (repère du HRP),
-- coude poussé vers `pole`
local function ik15(sh: Motor6D, el: Motor6D, wr: Motor6D?, parent: CFrame, target: Vector3, pole: Vector3)
	local J = parent * sh.C0
	local S = J.Position
	local ua = el.C0.Position - sh.C1.Position
	local la = (wr and (wr.C0.Position - el.C1.Position) or Vector3.new(0, -0.7, 0)) + Vector3.new(0, -0.14, 0)
	local d1, d2 = ua.Magnitude, la.Magnitude
	local toT = target - S
	local dist = math.clamp(toT.Magnitude, math.abs(d1 - d2) + 0.05, d1 + d2 - 0.02)
	local u = toT.Magnitude > 1e-4 and toT.Unit or Vector3.new(0, -1, 0)
	local p = pole - u * pole:Dot(u)
	if p.Magnitude < 1e-4 then
		p = basis(u, UP).UpVector
	end
	p = p.Unit
	local cosA = math.clamp((d1 * d1 + dist * dist - d2 * d2) / (2 * d1 * dist), -1, 1)
	local sinA = math.sqrt(math.max(0, 1 - cosA * cosA))
	local E = S + u * (d1 * cosA) + p * (d1 * sinA)
	local H = S + u * dist
	local b = (E - S).Unit
	local f2 = (H - E).Unit
	local front = f2 - b * f2:Dot(b)
	if front.Magnitude < 1e-3 then
		front = -p
	end
	local Rua = basis(b, front) * basis(ua.Unit, FRONT):Inverse()
	sh.Transform = J.Rotation:Inverse() * Rua * sh.C1.Rotation
	local UA = J * sh.Transform * sh.C1:Inverse()
	local J2 = UA * el.C0
	local back = -b
	local front2 = back - f2 * back:Dot(f2)
	if front2.Magnitude < 1e-3 then
		front2 = -p
	end
	local Rla = basis(f2, front2) * basis(la.Unit, FRONT):Inverse()
	el.Transform = J2.Rotation:Inverse() * Rla * el.C1.Rotation
	if wr then
		wr.Transform = I
	end
end

-- Bras R6 (une seule pièce) : le bras vise la cible
local function ik6(sh: Motor6D, parent: CFrame, target: Vector3)
	local J = parent * sh.C0
	local v = Vector3.new(0, -0.85, 0) - sh.C1.Position
	local toT = target - J.Position
	if toT.Magnitude < 1e-3 then
		return
	end
	local u = toT.Unit
	local front = Vector3.new(0, -u.Z, u.Y)
	if front.Magnitude < 1e-3 then
		front = FRONT
	end
	local R = basis(u, front) * basis(v.Unit, FRONT):Inverse()
	sh.Transform = J.Rotation:Inverse() * R * sh.C1.Rotation
end

type Pose = {
	Root: CFrame?, -- (repère du HRP : décalage / bascule du bassin)
	Waist: CFrame?,
	Neck: CFrame?,
	RHip: CFrame?,
	LHip: CFrame?,
	RKnee: CFrame?,
	LKnee: CFrame?,
	RAnkle: CFrame?,
	LAnkle: CFrame?,
	RHand: Vector3?, -- cibles des mains (MONDE)
	LHand: Vector3?,
	RPole: Vector3?, -- direction du coude (MONDE)
	LPole: Vector3?,
	RArm: CFrame?, -- sinon : rotation de l'épaule
	LArm: CFrame?,
}

local posed: { [Model]: boolean } = {}

local function applyPose(rig: Rig, pose: Pose)
	local m = rig.M
	local root = rig.Root
	m.Root.Transform = conj(m.Root, pose.Root or I)
	if m.Neck then
		m.Neck.Transform = conj(m.Neck, pose.Neck or I)
	end
	m.RHip.Transform = conj(m.RHip, pose.RHip or I)
	m.LHip.Transform = conj(m.LHip, pose.LHip or I)
	local rootCF = root.CFrame
	if rig.R6 then
		local torso = m.Root.C0 * m.Root.Transform * m.Root.C1:Inverse()
		for _, side in ipairs({ "R", "L" }) do
			local sh = m[side .. "Shoulder"]
			local target: Vector3? = if side == "R" then pose.RHand else pose.LHand
			if target then
				ik6(sh, torso, rootCF:PointToObjectSpace(target))
			else
				sh.Transform = conj(sh, (if side == "R" then pose.RArm else pose.LArm) or I)
			end
		end
	else
		for _, key in ipairs({ "RKnee", "LKnee", "RAnkle", "LAnkle" }) do
			local motor = m[key]
			if motor then
				motor.Transform = conj(motor, (pose :: any)[key] or I)
			end
		end
		m.Waist.Transform = conj(m.Waist, pose.Waist or I)
		local lt = m.Root.C0 * m.Root.Transform * m.Root.C1:Inverse()
		local ut = lt * m.Waist.C0 * m.Waist.Transform * m.Waist.C1:Inverse()
		for _, side in ipairs({ "R", "L" }) do
			local sh, el, wr = m[side .. "Shoulder"], m[side .. "Elbow"], m[side .. "Wrist"]
			local target: Vector3? = if side == "R" then pose.RHand else pose.LHand
			if target then
				local pole: Vector3 = (if side == "R" then pose.RPole else pose.LPole) or (rootCF.RightVector * (side == "R" and 1 or -1) - rootCF.UpVector * 0.4)
				ik15(sh, el, wr, ut, rootCF:PointToObjectSpace(target), rootCF:VectorToObjectSpace(pole))
			else
				sh.Transform = conj(sh, (if side == "R" then pose.RArm else pose.LArm) or I)
				el.Transform = I
				if wr then
					wr.Transform = I
				end
			end
		end
	end
	posed[rig.Character] = true
end

-- Fin de pose : joints remis à zéro (l'Animator reprend la main)
local function releasePose(character: Model)
	posed[character] = nil
	local rig = rigs[character]
	if not rig then
		return
	end
	for _, motor in pairs(rig.M) do
		if motor.Parent then
			motor.Transform = I
		end
	end
end

local function Rx(deg: number): CFrame
	return CFrame.Angles(rad(deg), 0, 0)
end

----------------------------------------------------------------------
-- Poses des jeux
----------------------------------------------------------------------

-- Assis, jambes pendantes (base), avec `hip` / `knee` en degrés
local function seatedLegs(pose: Pose, hip: number, knee: number, splay: number?, ankle: number?)
	local s = splay or 4
	pose.RHip = Rx(hip) * CFrame.Angles(0, 0, rad(-s))
	pose.LHip = Rx(hip) * CFrame.Angles(0, 0, rad(s))
	pose.RKnee = Rx(-knee)
	pose.LKnee = Rx(-knee)
	pose.RAnkle = Rx(ankle or 0)
	pose.LAnkle = Rx(ankle or 0)
end

local function swingPose(seatCF: CFrame, angle: number, phase: number, env: number): Pose
	local pose: Pose = {}
	-- on pompe : jambes tendues en allant vers l'avant, repliées au retour
	local c = math.cos(phase) * env
	seatedLegs(pose, 78 + 14 * c, 70 - 52 * c, 3, 10 * c)
	pose.Waist = Rx(4 + 12 * c)
	pose.Neck = Rx(-6 - 6 * c)
	-- mains sur les chaînes (gaine), un peu au-dessus des épaules
	pose.RHand = (seatCF * CFrame.new(0.9, 2.55, 0.05)).Position
	pose.LHand = (seatCF * CFrame.new(-0.9, 2.55, 0.05)).Position
	pose.RPole = (seatCF.RightVector * 0.6 + seatCF.LookVector * -0.5 - seatCF.UpVector * 0.4)
	pose.LPole = (seatCF.RightVector * -0.6 + seatCF.LookVector * -0.5 - seatCF.UpVector * 0.4)
	local _ = angle
	return pose
end

local function handleBarPose(seatCF: CFrame, grip: Vector3, hip: number, knee: number, lean: number): Pose
	local pose: Pose = {}
	seatedLegs(pose, hip, knee, 6, 0)
	pose.Waist = Rx(-lean)
	pose.Neck = Rx(lean * 0.4)
	pose.RHand = (seatCF * CFrame.new(grip.X, grip.Y, grip.Z)).Position
	pose.LHand = (seatCF * CFrame.new(-grip.X, grip.Y, grip.Z)).Position
	pose.RPole = seatCF.RightVector - seatCF.UpVector * 0.8
	pose.LPole = -seatCF.RightVector - seatCF.UpVector * 0.8
	return pose
end

----------------------------------------------------------------------
-- Construction du décor (un morceau par image)
----------------------------------------------------------------------

local function at(park: Park, x: number, y: number, z: number): Vector3
	return park.G * Vector3.new(x, y, z)
end

-- Clôture en bois peint (poteaux à boule, 2 lisses, lattes) + portillon ouvert
local function buildFence(park: Park)
	local f = Instance.new("Model")
	f.Name = "Fence"
	local g = park.G
	local hw, hd = ParkMotion.W / 2 + 0.6, ParkMotion.D / 2 + 0.6
	local gate = ParkMotion.GATE
	local runs = {
		{ Vector3.new(-hw, 0, hd), Vector3.new(hw, 0, hd) },
		{ Vector3.new(-hw, 0, -hd), Vector3.new(-hw, 0, hd) },
		{ Vector3.new(hw, 0, -hd), Vector3.new(hw, 0, hd) },
		{ Vector3.new(-hw, 0, -hd), Vector3.new(-gate - 0.3, 0, -hd) },
		{ Vector3.new(gate + 0.3, 0, -hd), Vector3.new(hw, 0, -hd) },
	}
	local posts: { [string]: boolean } = {}
	for ri, r in ipairs(runs) do
		local a, b = r[1], r[2]
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local n = math.max(1, math.floor(len / 4.2 + 0.5))
		for k = 0, n do
			local p = a:Lerp(b, k / n)
			local key = string.format("%.1f_%.1f", p.X, p.Z)
			-- (pas de poteau là où se dresse un pilier du portillon)
			local atGate = math.abs(math.abs(p.X) - (gate + 0.3)) < 0.05 and math.abs(p.Z + hd) < 0.05
			if not posts[key] and not atGate then
				posts[key] = true
				newPart(f, "FencePost", Vector3.new(0.36, 2.9, 0.36), g * CFrame.new(p + Vector3.new(0, 1.45, 0)), WHITE, M.Wood, nil, true)
				ball(f, "PostCap", g * (p + Vector3.new(0, 3.0, 0)), 0.42, WHITE, M.SmoothPlastic)
			end
		end
		-- 2 lisses (derrière les lattes, côté intérieur)
		local inward = Vector3.new(-dir.Z, 0, dir.X)
		if (inward):Dot(-a) < 0 then
			inward = -inward
		end
		for _, y in ipairs({ 0.75, 2.05 }) do
			slab(f, "FenceRail", g * (a + inward * 0.16 + Vector3.new(0, y, 0)), g * (b + inward * 0.16 + Vector3.new(0, y, 0)), 0.14, 0.26, rgb(236, 236, 230), M.Wood)
		end
		-- lattes à bout arrondi, régulières entre les poteaux
		local count = math.floor(len / 1.3)
		for k = 1, count do
			local t = (k - 0.5) / count
			local p = a:Lerp(b, t)
			-- (pas de latte dans un poteau)
			local along = t * len
			local spacing = len / n
			local nearPost = math.abs(along - math.floor(along / spacing + 0.5) * spacing) < 0.45
			if not nearPost then
				local cf = g * CFrame.lookAt(p + Vector3.new(0, 1.3, 0), p + Vector3.new(0, 1.3, 0) + inward)
				newPart(f, "Picket", Vector3.new(0.42, 2.3, 0.1), cf, WHITE, M.Wood)
			end
		end
		local _ = ri
	end
	-- piliers du portillon + arche "Aire de jeux"
	for _, sx in ipairs({ -1, 1 }) do
		local p = Vector3.new(sx * (gate + 0.3), 0, -hd)
		newPart(f, "GatePillar", Vector3.new(0.6, 3.6, 0.6), g * CFrame.new(p + Vector3.new(0, 1.8, 0)), BLUE, M.Metal, nil, true)
		ball(f, "GateBall", g * (p + Vector3.new(0, 3.85, 0)), 0.7, YELLOW, M.SmoothPlastic)
		rod(f, "ArchPost", g * (p + Vector3.new(0, 3.6, 0)), g * (p + Vector3.new(0, 6.4, 0)), 0.22, BLUE, M.Metal)
	end
	local board = newPart(f, "GateSign", Vector3.new(gate * 2 + 1.2, 1.3, 0.2), g * CFrame.new(0, 6.1, -hd) * CFrame.Angles(0, math.pi, 0), YELLOW, M.SmoothPlastic, nil, true)
	label(board, "🛝 " .. Locale.T("Playground"), rgb(120, 60, 40), rgb(255, 232, 150))
	-- battant ouvert vers l'extérieur (3 lattes + traverses)
	local hinge = g * CFrame.new(-gate - 0.3, 0, -hd) * CFrame.Angles(0, rad(-100), 0)
	for k = 0, 2 do
		newPart(f, "GateSlat", Vector3.new(0.42, 2.0, 0.1), hinge * CFrame.new(0.5 + k * 0.72, 1.25, 0), WHITE, M.Wood)
	end
	for _, y in ipairs({ 0.65, 1.85 }) do
		newPart(f, "GateBar", Vector3.new(2.1, 0.2, 0.12), hinge * CFrame.new(1.2, y, 0.11), rgb(236, 236, 230), M.Wood)
	end
	f.Parent = park.Folder
end

-- Sol : zones amortissantes en couleurs, marelle, bordure du bac, panneau
local function buildGround(park: Park)
	local f = Instance.new("Model")
	f.Name = "Ground"
	local g = park.G
	local T = ParkMotion.FLOOR_TOP
	-- (chaque dalle à sa hauteur : jamais deux dessus confondus)
	local function mat(name: string, cx: number, cz: number, w: number, d: number, color: Color3, lift: number)
		newPart(f, name, Vector3.new(w, 0.06, d), g * CFrame.new(cx, T + lift - 0.03, cz), color, M.Rubber)
	end
	local S = ParkMotion.SWING
	mat("SwingMat", S.Center.X, S.Center.Z, 11.2, 9.6, rgb(70, 124, 190), 0.035)
	local sd = ParkMotion.SEESAW
	mat("SeesawMat", sd.Center.X, sd.Center.Z, 10.4, 3.6, rgb(120, 180, 90), 0.035)
	local sl = ParkMotion.SLIDE
	mat("SlideMat", sl.Tower.X, sl.Tower.Z + 6.2, 5, 11.6, rgb(236, 170, 70), 0.035)
	local mg = ParkMotion.MERRY
	disc(f, "MerryMat", g * CFrame.new(mg.Center), T + 0.065, mg.Radius + 2.1, 0.06, rgb(96, 170, 140), M.Rubber)
	for i = 1, #ParkMotion.SPRINGS do
		disc(f, "SpringMat", g * ParkMotion.SpringBase(i), T + 0.035, 2.2, 0.06, rgb(186, 120, 200), M.Rubber)
	end
	local mk = ParkMotion.MONKEY
	mat("MonkeyMat", (mk.X0 + mk.X1) / 2, mk.Z, mk.X1 - mk.X0 + 4, 4.2, rgb(214, 96, 96), 0.035)
	-- marelle peinte dans l'allée du portillon (1-2-3, 4|5, 6, 7|8, CIEL)
	local cells = { { 0, -13.6 }, { 0, -12.3 }, { -0.62, -11.0 }, { 0.62, -11.0 }, { 0, -9.7 }, { -0.62, -8.4 }, { 0.62, -8.4 }, { 0, -7.1 } }
	for i, c in ipairs(cells) do
		local w = (c[1] ~= 0) and 1.12 or 1.2
		newPart(f, "Hopscotch", Vector3.new(w, 0.04, 1.2), g * CFrame.new(c[1], T + 0.035, c[2]), i % 2 == 0 and rgb(255, 255, 255) or rgb(255, 214, 90), M.SmoothPlastic)
	end
	disc(f, "HopSky", g * CFrame.new(0, 0, -5.9), T + 0.09, 0.8, 0.04, rgb(130, 200, 255), M.SmoothPlastic)
	f.Parent = park.Folder
end

-- 🎠 portique des balançoires (fixe) + 3 balançoires (mobiles)
local function buildSwings(park: Park)
	local g = park.G
	local S = ParkMotion.SWING
	local c = S.Center
	local f = Instance.new("Model")
	f.Name = "SwingFrame"
	local topY = S.PivotY + 0.3
	local half = 5.3
	rod(f, "SwingBeam", at(park, c.X - half - 0.2, topY, c.Z), at(park, c.X + half + 0.2, topY, c.Z), 0.52, GREEN, M.Metal, true)
	for _, sx in ipairs({ -1, 1 }) do
		local x = c.X + sx * half
		ball(f, "BeamCap", at(park, x + sx * 0.25, topY, c.Z), 0.56, GREEN_D, M.SmoothPlastic)
		newPart(f, "Clamp", Vector3.new(0.7, 0.9, 0.9), g * CFrame.new(x, topY - 0.1, c.Z), GREEN_D, M.Metal, nil, true)
		for _, sz in ipairs({ -1, 1 }) do
			local foot = Vector3.new(x + sx * 0.45, ParkMotion.FLOOR_TOP, c.Z + sz * 2.7)
			rod(f, "SwingLeg", at(park, x, topY - 0.2, c.Z + sz * 0.2), g * foot, 0.42, GREEN, M.Metal, true)
			disc(f, "LegFoot", g * CFrame.new(foot), ParkMotion.FLOOR_TOP + 0.08, 0.36, 0.1, STEEL_D, M.Metal)
		end
		-- entretoise (barre en A)
		rod(f, "SwingBrace", at(park, x + sx * 0.3, 2.6, c.Z - 1.85), at(park, x + sx * 0.3, 2.6, c.Z + 1.85), 0.26, GREEN_D, M.Metal)
	end
	f.Parent = park.Folder
	-- balançoires : chaînes à maillons + sangle
	for i, dx in ipairs(S.Xs) do
		local pivot = g * ParkMotion.SwingPivot(i)
		local m = Instance.new("Model")
		m.Name = "Swing" .. i
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * 0.93
			-- crochet (étrier sous la poutre)
			newPart(m, "Hanger", Vector3.new(0.18, 0.34, 0.3), pivot * CFrame.new(x, 0.12, 0), STEEL_D, M.Metal)
			local links = 11
			local top, bottom = -0.05, -(S.L - 0.28)
			local step = (top - bottom) / links
			for k = 0, links - 1 do
				local y = top - (k + 0.5) * step
				local turn = (k % 2 == 0) and I or CFrame.Angles(0, math.pi / 2, 0)
				egg(m, "ChainLink", pivot * CFrame.new(x, y, 0) * turn, Vector3.new(0.13, step + 0.14, 0.05), STEEL, M.Metal)
			end
			-- gaine plastique là où l'on tient la chaîne
			rod(m, "ChainGrip", (pivot * CFrame.new(x, -S.L + 2.0, 0)).Position, (pivot * CFrame.new(x, -S.L + 3.4, 0)).Position, 0.2, i == 2 and YELLOW or BLUE, M.SmoothPlastic)
			-- attache de la sangle
			newPart(m, "SeatClamp", Vector3.new(0.2, 0.3, 0.36), pivot * CFrame.new(x, -S.L + 0.18, 0), STEEL_D, M.Metal)
		end
		-- sangle en caoutchouc (creux au milieu, bords relevés)
		local seat = pivot * CFrame.new(0, -S.L, 0)
		newPart(m, "BeltSeat", Vector3.new(1.3, 0.14, 0.95), seat * CFrame.new(0, -0.07, 0), RUBBER_B, M.Rubber, nil, true)
		for _, sx in ipairs({ -1, 1 }) do
			newPart(m, "BeltEnd", Vector3.new(0.34, 0.14, 0.92), seat * CFrame.new(sx * 0.78, 0.0, 0) * CFrame.Angles(0, 0, sx * rad(24)), RUBBER_B, M.Rubber)
		end
		m.Parent = park.Folder
		local group = newGroup(pivot)
		adopt(group, m)
		local piece: Piece = { Kind = "Swing", Index = i, Groups = { group }, Server = nil, Seats = {}, Settled = false, Extra = nil }
		table.insert(park.Pieces, piece)
		local _ = dx
	end
end

-- 🛝 tour + toit + échelle + mur d'escalade + glissière
local function buildSlide(park: Park)
	local g = park.G
	local S = ParkMotion.SLIDE
	local tower = g * ParkMotion.SlideTower()
	local f = Instance.new("Model")
	f.Name = "SlideTower"
	local deckTop = S.DeckTop
	local h = S.Deck / 2 - 0.15
	for _, x in ipairs({ -h, h }) do
		for _, z in ipairs({ -h, h }) do
			rod(f, "TowerPost", (tower * CFrame.new(x, ParkMotion.FLOOR_TOP, z)).Position, (tower * CFrame.new(x, 8.7, z)).Position, 0.42, BLUE, M.Metal, true)
			disc(f, "PostFoot", tower * CFrame.new(x, 0, z), ParkMotion.FLOOR_TOP + 0.08, 0.34, 0.1, STEEL_D, M.Metal)
		end
	end
	-- plancher (tôle antidérapante) + palier du mur d'escalade
	newPart(f, "Deck", Vector3.new(S.Deck, 0.24, S.Deck), tower * CFrame.new(0, deckTop - 0.12, 0), rgb(72, 84, 92), M.DiamondPlate, nil, true)
	newPart(f, "Landing", Vector3.new(2.0, 0.22, S.Deck - 0.4), tower * CFrame.new(-S.Deck / 2 - 1.0, deckTop - 0.13, 0), rgb(72, 84, 92), M.DiamondPlate, nil, true)
	newPart(f, "DeckBeam", Vector3.new(S.Deck + 0.1, 0.4, 0.3), tower * CFrame.new(0, deckTop - 0.44, -S.Deck / 2 + 0.15), BLUE_D, M.Metal)
	newPart(f, "DeckBeam", Vector3.new(S.Deck + 0.1, 0.4, 0.3), tower * CFrame.new(0, deckTop - 0.44, S.Deck / 2 - 0.15), BLUE_D, M.Metal)
	-- garde-corps +X : panneau PEHD avec volant de bateau
	local panel = newPart(f, "SidePanel", Vector3.new(0.16, 2.3, S.Deck - 0.6), tower * CFrame.new(h + 0.02, deckTop + 1.25, 0), RED, M.SmoothPlastic, nil, true)
	local wheelCF = tower * CFrame.new(h - 0.2, deckTop + 1.45, 0) * CFrame.Angles(0, 0, 0)
	newPart(f, "WheelRim", Vector3.new(0.12, 1.3, 1.3), wheelCF, YELLOW, M.SmoothPlastic, CYL)
	newPart(f, "WheelInner", Vector3.new(0.1, 0.9, 0.9), wheelCF * CFrame.new(-0.035, 0, 0), RED, M.SmoothPlastic, CYL)
	for k = 0, 2 do
		newPart(f, "WheelSpoke", Vector3.new(0.06, 1.5, 0.12), wheelCF * CFrame.new(-0.14, 0, 0) * CFrame.Angles(rad(k * 60), 0, 0), YELLOW, M.SmoothPlastic)
	end
	ball(f, "WheelHub", (wheelCF * CFrame.new(-0.18, 0, 0)).Position, 0.34, BLUE, M.SmoothPlastic)
	local _ = panel
	-- mains courantes (côté échelle : 2 poignées ; côté glissière : barre d'appui)
	for _, sx in ipairs({ -1, 1 }) do
		rod(f, "LadderGrip", (tower * CFrame.new(sx * 0.8, deckTop, -h - 0.05)).Position, (tower * CFrame.new(sx * 0.8, deckTop + 1.6, -h - 0.05)).Position, 0.16, YELLOW, M.Metal)
		rod(f, "LadderGripTop", (tower * CFrame.new(sx * 0.8, deckTop + 1.6, -h - 0.05)).Position, (tower * CFrame.new(sx * h, deckTop + 1.6, -h + 0.05)).Position, 0.16, YELLOW, M.Metal)
	end
	rod(f, "SlideBar", (tower * CFrame.new(-h, deckTop + 2.2, h - 0.1)).Position, (tower * CFrame.new(h, deckTop + 2.2, h - 0.1)).Position, 0.16, YELLOW, M.Metal)
	-- capot du départ de la glissière
	for _, sx in ipairs({ -1, 1 }) do
		newPart(f, "Hood", Vector3.new(0.14, 1.5, 1.2), tower * CFrame.new(sx * 1.12, deckTop + 0.75, S.Deck / 2 + 0.45), YELLOW, M.SmoothPlastic, nil, true)
	end
	-- toit à deux pans + faîtière
	for _, sz in ipairs({ -1, 1 }) do
		newPart(f, "Roof", Vector3.new(S.Deck + 1.1, 0.16, 2.35), tower * CFrame.new(0, 9.05, sz * 1.02) * CFrame.Angles(sz * rad(26), 0, 0), RED, M.SmoothPlastic, nil, true)
	end
	rod(f, "RoofRidge", (tower * CFrame.new(-S.Deck / 2 - 0.55, 9.6, 0)).Position, (tower * CFrame.new(S.Deck / 2 + 0.55, 9.6, 0)).Position, 0.24, YELLOW, M.SmoothPlastic)
	-- échelle (-Z) inclinée : 2 montants + barreaux ronds
	local lean = math.tan(S.LadderLean)
	local function ladderZ(y: number): number
		return S.LadderZ - (deckTop - y) * lean
	end
	for _, sx in ipairs({ -0.78, 0.78 }) do
		rod(f, "LadderRail", (tower * CFrame.new(sx, ParkMotion.FLOOR_TOP, ladderZ(ParkMotion.FLOOR_TOP))).Position, (tower * CFrame.new(sx, deckTop + 0.05, ladderZ(deckTop))).Position, 0.24, BLUE, M.Metal, true)
	end
	for k = 1, 5 do
		local y = k * 0.85
		rod(f, "LadderRung", (tower * CFrame.new(-0.78, y, ladderZ(y))).Position, (tower * CFrame.new(0.78, y, ladderZ(y))).Position, 0.18, STEEL, M.Metal)
	end
	-- mur d'escalade (-X) : panneau + prises de couleur
	local wx = -S.Deck / 2 - 2.05
	newPart(f, "ClimbWall", Vector3.new(0.2, deckTop - 0.1, S.Deck - 0.4), tower * CFrame.new(wx, (deckTop + ParkMotion.FLOOR_TOP) / 2, 0), YELLOW, M.SmoothPlastic, nil, true)
	local holds = { RED, BLUE, GREEN, ORANGE, rgb(170, 90, 200) }
	for k = 1, 11 do
		local y = 0.7 + (k - 1) * 0.36
		local z = math.sin(k * 2.3) * 1.1
		egg(f, "ClimbHold", tower * CFrame.new(wx - 0.14, y, z) * CFrame.Angles(0, 0, rad(k * 37)), Vector3.new(0.22, 0.34, 0.3), holds[(k - 1) % #holds + 1], M.SmoothPlastic)
	end
	-- glissière : fond + 2 flancs + boudins, segment par segment (profil lissé)
	local samples = { 1.7, 2.3, 2.75, 3.3, 7.3, 8.05, 8.7, 9.4, S.Profile[#S.Profile][1] }
	local chute = rgb(250, 206, 60)
	for k = 1, #samples - 1 do
		local z0, z1 = samples[k], samples[k + 1]
		local y0 = ParkMotion.SlideSurface(z0)
		local y1 = ParkMotion.SlideSurface(z1)
		local a = (tower * CFrame.new(0, y0 - 0.09, z0 - 0.02)).Position
		local b = (tower * CFrame.new(0, y1 - 0.09, z1 + 0.02)).Position
		local bottom = slab(f, "ChuteBed", a, b, 1.9, 0.18, chute, M.SmoothPlastic, true)
		for _, sx in ipairs({ -1, 1 }) do
			local o = bottom.CFrame.RightVector * (sx * 1.03)
			local up = bottom.CFrame.UpVector
			slab(f, "ChuteWall", a + o + up * 0.3, b + o + up * 0.3, 0.16, 0.66, rgb(244, 186, 40), M.SmoothPlastic, true)
			rod(f, "ChuteRim", a + o + up * 0.66, b + o + up * 0.66, 0.24, chute, M.SmoothPlastic)
		end
	end
	local zEnd = S.Profile[#S.Profile][1]
	local yEnd = ParkMotion.SlideSurface(zEnd)
	rod(f, "ChuteLip", (tower * CFrame.new(-1.05, yEnd - 0.12, zEnd + 0.02)).Position, (tower * CFrame.new(1.05, yEnd - 0.12, zEnd + 0.02)).Position, 0.24, chute, M.SmoothPlastic)
	-- pieds de la glissière
	for _, z in ipairs({ 5.6, 9.4 }) do
		local y = ParkMotion.SlideSurface(z)
		for _, sx in ipairs({ -0.7, 0.7 }) do
			rod(f, "ChuteLeg", (tower * CFrame.new(sx, ParkMotion.FLOOR_TOP, z)).Position, (tower * CFrame.new(sx, y - 0.2, z)).Position, 0.22, BLUE, M.Metal)
		end
	end
	f.Parent = park.Folder
end

-- 🌀 tourniquet : socle fixe + plateau mobile (sièges, guidons, mât)
local function buildMerry(park: Park)
	local g = park.G
	local m = ParkMotion.MERRY
	local base = g * CFrame.new(m.Center)
	local fixed = Instance.new("Model")
	fixed.Name = "MerryBase"
	disc(fixed, "MerryBearing", base, m.DeckTop - 0.35, 0.9, m.DeckTop - 0.35 - ParkMotion.FLOOR_TOP + 0.02, STEEL_D, M.Metal)
	fixed.Parent = park.Folder
	local r = Instance.new("Model")
	r.Name = "MerryTop"
	disc(r, "MerryDeck", base, m.DeckTop, m.Radius, 0.3, RED, M.DiamondPlate, true)
	disc(r, "MerryRim", base, m.DeckTop - 0.1, m.Radius + 0.08, 0.14, YELLOW, M.Metal)
	for k = 0, 3 do
		-- secteurs antidérapants (plaques un peu au-dessus du plateau)
		local a = k * math.pi / 2 + math.pi / 4
		newPart(r, "DeckPad", Vector3.new(0.9, 0.05, 1.5), base * CFrame.Angles(0, a, 0) * CFrame.new(0, m.DeckTop + 0.02, 1.35), k % 2 == 0 and BLUE or YELLOW, M.Rubber)
	end
	rod(r, "MerryPole", (base * CFrame.new(0, m.DeckTop, 0)).Position, (base * CFrame.new(0, 3.9, 0)).Position, 0.42, STEEL, M.Metal, true)
	ball(r, "PoleCap", (base * CFrame.new(0, 3.95, 0)).Position, 0.62, YELLOW, M.SmoothPlastic)
	for k = 1, m.Seats do
		local a = (k - 0.5) / m.Seats * TAU
		local seatCF = base * CFrame.Angles(0, a, 0) * CFrame.new(0, m.SeatTop, m.SeatR)
		-- siège moulé (assise + dossier) sur son pied
		newPart(r, "SeatPan", Vector3.new(1.25, 0.2, 1.0), seatCF * CFrame.new(0, -0.1, 0.05), BLUE, M.SmoothPlastic, nil, true)
		newPart(r, "SeatBack", Vector3.new(1.25, 1.1, 0.16), seatCF * CFrame.new(0, 0.5, 0.58) * CFrame.Angles(rad(-10), 0, 0), BLUE, M.SmoothPlastic, nil, true)
		rod(r, "SeatPost", (seatCF * CFrame.new(0, -0.2, 0.05)).Position, (base * CFrame.Angles(0, a, 0) * CFrame.new(0, m.DeckTop, m.SeatR + 0.05)).Position, 0.3, STEEL_D, M.Metal)
		-- guidon en U devant le siège
		local barCF = base * CFrame.Angles(0, a, 0) * CFrame.new(0, m.SeatTop + 1.15, m.SeatR - 0.85)
		rod(r, "HandleBar", (barCF * CFrame.new(-0.62, 0, 0)).Position, (barCF * CFrame.new(0.62, 0, 0)).Position, 0.18, YELLOW, M.Metal)
		for _, sx in ipairs({ -0.62, 0.62 }) do
			rod(r, "HandlePost", (barCF * CFrame.new(sx, 0, 0)).Position, (base * CFrame.Angles(0, a, 0) * CFrame.new(sx, m.DeckTop, m.SeatR - 0.85)).Position, 0.18, YELLOW, M.Metal)
		end
		-- rayon vers le mât
		rod(r, "Spoke", (barCF * CFrame.new(0, 0, 0)).Position, (base * CFrame.new(0, m.SeatTop + 1.15, 0)).Position, 0.14, STEEL, M.Metal)
	end
	r.Parent = park.Folder
	local group = newGroup(base)
	adopt(group, r)
	table.insert(park.Pieces, { Kind = "Merry", Index = 1, Groups = { group }, Server = nil, Seats = {}, Settled = false, Extra = nil })
end

-- ⚖️ tape-cul : chevalet + pneus (fixes), planche + sièges + poignées (mobiles)
local function buildSeesaw(park: Park)
	local g = park.G
	local S = ParkMotion.SEESAW
	local c = S.Center
	local f = Instance.new("Model")
	f.Name = "SeesawBase"
	for _, sz in ipairs({ -1, 1 }) do
		rod(f, "SeesawStand", at(park, c.X - 0.5, ParkMotion.FLOOR_TOP, c.Z + sz * 0.62), at(park, c.X, S.PivotY, c.Z + sz * 0.62), 0.24, GREEN, M.Metal, true)
		rod(f, "SeesawStand", at(park, c.X + 0.5, ParkMotion.FLOOR_TOP, c.Z + sz * 0.62), at(park, c.X, S.PivotY, c.Z + sz * 0.62), 0.24, GREEN, M.Metal, true)
	end
	rod(f, "SeesawAxle", at(park, c.X, S.PivotY, c.Z - 0.78), at(park, c.X, S.PivotY, c.Z + 0.78), 0.28, STEEL, M.Metal)
	newPart(f, "SeesawPlate", Vector3.new(1.4, 0.1, 1.6), g * CFrame.new(c.X, ParkMotion.FLOOR_TOP + 0.04, c.Z), STEEL_D, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		-- demi-pneu enterré sous chaque bout (amortisseur)
		newPart(f, "Tyre", Vector3.new(0.7, 1.1, 1.1), g * CFrame.new(c.X + sx * (S.Half - 0.4), ParkMotion.FLOOR_TOP + 0.02, c.Z) * CFrame.Angles(0, math.pi / 2, 0), RUBBER_B, M.Rubber, CYL)
	end
	f.Parent = park.Folder
	local rest = g * ParkMotion.SeesawPivot(0)
	local m = Instance.new("Model")
	m.Name = "SeesawPlank"
	newPart(m, "Plank", Vector3.new(S.Half * 2, 0.22, 0.8), rest * CFrame.new(0, 0.25, 0), WOOD, M.WoodPlanks, nil, true)
	newPart(m, "PlankHub", Vector3.new(1.0, 0.36, 0.95), rest * CFrame.new(0, 0.1, 0), GREEN_D, M.Metal)
	for k = 1, 2 do
		local sx = k == 1 and -1 or 1
		local seat = rest * CFrame.new(sx * S.SeatX, S.SeatUp, 0)
		newPart(m, "SeesawSeat", Vector3.new(1.2, 0.16, 0.95), seat * CFrame.new(0, -0.08, 0), RED, M.SmoothPlastic, nil, true)
		newPart(m, "SeesawBack", Vector3.new(0.16, 0.6, 0.95), seat * CFrame.new(sx * 0.6, 0.25, 0), RED, M.SmoothPlastic)
		-- poignée en T devant le siège (vers le pivot)
		local hx = sx * (S.SeatX - 0.85)
		rod(m, "HandlePost", (rest * CFrame.new(hx, 0.36, 0)).Position, (rest * CFrame.new(hx, S.SeatUp + 1.0, 0)).Position, 0.2, YELLOW, M.Metal)
		rod(m, "HandleGrip", (rest * CFrame.new(hx, S.SeatUp + 1.0, -0.55)).Position, (rest * CFrame.new(hx, S.SeatUp + 1.0, 0.55)).Position, 0.2, BLUE, M.Rubber)
	end
	m.Parent = park.Folder
	local group = newGroup(rest)
	adopt(group, m)
	table.insert(park.Pieces, { Kind = "Seesaw", Index = 1, Groups = { group }, Server = nil, Seats = {}, Settled = false, Extra = nil })
end

-- 🐴🦆 jeux à ressort : socle (fixe), ressort (tordu à chaque image), animal (mobile)
local function buildSprings(park: Park)
	local g = park.G
	for i, def in ipairs(ParkMotion.SPRINGS) do
		local base = g * ParkMotion.SpringBase(i)
		local f = Instance.new("Model")
		f.Name = "SpringBase" .. i
		disc(f, "SpringPad", base, ParkMotion.SPRING.PivotY, 0.75, 0.32, STEEL_D, M.Metal)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			ball(f, "Bolt", (base * CFrame.new(math.cos(a) * 0.55, ParkMotion.SPRING.PivotY + 0.02, math.sin(a) * 0.55)).Position, 0.12, STEEL, M.Metal)
		end
		f.Parent = park.Folder
		-- ressort : 5 spires en 20 segments (repositionnés à chaque image)
		local coil = Instance.new("Model")
		coil.Name = "Coil" .. i
		local coilParts = {}
		for _ = 1, 20 do
			table.insert(coilParts, newPart(coil, "Coil", Vector3.new(0.5, 0.13, 0.13), base, rgb(236, 90, 70), M.Metal, CYL))
		end
		coil.Parent = park.Folder
		-- animal (repère du corps au repos)
		local rest = g * ParkMotion.SpringBody(i, 0, 0)
		local m = Instance.new("Model")
		m.Name = "Rider" .. i
		if def.Kind == "Horse" then
			local coat = rgb(236, 180, 120)
			local mane = rgb(140, 80, 48)
			egg(m, "Body", rest * CFrame.new(0, 1.0, 0.1), Vector3.new(1.15, 1.2, 2.5), coat, M.SmoothPlastic)
			egg(m, "Neck", rest * CFrame.new(0, 1.62, -0.95) * CFrame.Angles(rad(-35), 0, 0), Vector3.new(0.75, 1.3, 0.8), coat, M.SmoothPlastic)
			egg(m, "Head", rest * CFrame.new(0, 2.2, -1.45) * CFrame.Angles(rad(35), 0, 0), Vector3.new(0.7, 0.72, 1.2), coat, M.SmoothPlastic)
			egg(m, "Muzzle", rest * CFrame.new(0, 2.0, -1.9) * CFrame.Angles(rad(35), 0, 0), Vector3.new(0.58, 0.5, 0.52), rgb(250, 214, 176), M.SmoothPlastic)
			for _, sx in ipairs({ -1, 1 }) do
				egg(m, "Ear", rest * CFrame.new(sx * 0.2, 2.62, -1.3) * CFrame.Angles(rad(-10), 0, sx * rad(-12)), Vector3.new(0.16, 0.42, 0.2), coat, M.SmoothPlastic)
				ball(m, "Eye", (rest * CFrame.new(sx * 0.3, 2.34, -1.6)).Position, 0.2, INK, M.SmoothPlastic)
				ball(m, "EyeShine", (rest * CFrame.new(sx * 0.36, 2.39, -1.66)).Position, 0.07, WHITE, M.SmoothPlastic)
				ball(m, "Nostril", (rest * CFrame.new(sx * 0.13, 1.96, -2.12)).Position, 0.09, rgb(120, 70, 50), M.SmoothPlastic)
				-- repose-pieds
				rod(m, "FootPeg", (rest * CFrame.new(sx * 0.45, 0.62, -0.2)).Position, (rest * CFrame.new(sx * 0.95, 0.62, -0.2)).Position, 0.16, STEEL, M.Metal)
			end
			egg(m, "Mane", rest * CFrame.new(0, 2.0, -0.95) * CFrame.Angles(rad(-35), 0, 0), Vector3.new(0.22, 1.35, 0.7), mane, M.SmoothPlastic)
			egg(m, "Tail", rest * CFrame.new(0, 1.05, 1.35) * CFrame.Angles(rad(35), 0, 0), Vector3.new(0.24, 1.0, 0.3), mane, M.SmoothPlastic)
			egg(m, "Saddle", rest * CFrame.new(0, ParkMotion.SPRING.SeatUp - 0.1, 0.15), Vector3.new(1.05, 0.3, 1.1), RED, M.Leather)
			-- poignées sur l'encolure
			rod(m, "Handle", (rest * CFrame.new(-0.5, 1.9, -0.95)).Position, (rest * CFrame.new(0.5, 1.9, -0.95)).Position, 0.15, YELLOW, M.Metal)
		else
			local fur = rgb(255, 216, 60)
			egg(m, "Body", rest * CFrame.new(0, 1.0, 0.15), Vector3.new(1.3, 1.15, 2.3), fur, M.SmoothPlastic)
			ball(m, "Head", (rest * CFrame.new(0, 2.25, -1.05)).Position, 1.05, fur, M.SmoothPlastic)
			egg(m, "Beak", rest * CFrame.new(0, 2.1, -1.68), Vector3.new(0.5, 0.2, 0.62), ORANGE, M.SmoothPlastic)
			egg(m, "Tail", rest * CFrame.new(0, 1.55, 1.3) * CFrame.Angles(rad(40), 0, 0), Vector3.new(0.5, 0.7, 0.3), fur, M.SmoothPlastic)
			for _, sx in ipairs({ -1, 1 }) do
				egg(m, "Wing", rest * CFrame.new(sx * 0.62, 1.1, 0.25) * CFrame.Angles(0, 0, sx * rad(-12)), Vector3.new(0.22, 0.7, 1.3), rgb(250, 196, 40), M.SmoothPlastic)
				ball(m, "Eye", (rest * CFrame.new(sx * 0.3, 2.42, -1.47)).Position, 0.2, INK, M.SmoothPlastic)
				ball(m, "EyeShine", (rest * CFrame.new(sx * 0.35, 2.47, -1.54)).Position, 0.07, WHITE, M.SmoothPlastic)
				rod(m, "FootPeg", (rest * CFrame.new(sx * 0.5, 0.62, -0.2)).Position, (rest * CFrame.new(sx * 1.0, 0.62, -0.2)).Position, 0.16, STEEL, M.Metal)
			end
			egg(m, "Saddle", rest * CFrame.new(0, ParkMotion.SPRING.SeatUp - 0.1, 0.15), Vector3.new(1.1, 0.3, 1.1), BLUE, M.Leather)
			rod(m, "Handle", (rest * CFrame.new(-0.5, 1.95, -0.62)).Position, (rest * CFrame.new(0.5, 1.95, -0.62)).Position, 0.15, RED, M.Metal)
		end
		m.Parent = park.Folder
		local group = newGroup(rest)
		adopt(group, m)
		table.insert(park.Pieces, { Kind = "Spring", Index = i, Groups = { group }, Server = nil, Seats = {}, Settled = false, Extra = { Coil = coilParts, Base = base } })
	end
end

-- 🐒 barres de singe : 2 échelles aux bouts, 2 longerons, barreaux
local function buildMonkey(park: Park)
	local g = park.G
	local Mk = ParkMotion.MONKEY
	local f = Instance.new("Model")
	f.Name = "MonkeyBars"
	local hw = Mk.Width / 2
	for _, x in ipairs({ Mk.X0, Mk.X1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			rod(f, "MonkeyPost", at(park, x, ParkMotion.FLOOR_TOP, Mk.Z + sz * hw), at(park, x, Mk.BarY + 0.1, Mk.Z + sz * hw), 0.34, ORANGE, M.Metal, true)
			ball(f, "PostCap", at(park, x, Mk.BarY + 0.2, Mk.Z + sz * hw), 0.4, YELLOW, M.SmoothPlastic)
			disc(f, "PostFoot", g * CFrame.new(x, 0, Mk.Z + sz * hw), ParkMotion.FLOOR_TOP + 0.08, 0.3, 0.1, STEEL_D, M.Metal)
		end
		for k = 1, 5 do
			local y = k * 0.95
			rod(f, "EndRung", at(park, x, y, Mk.Z - hw), at(park, x, y, Mk.Z + hw), 0.18, STEEL, M.Metal)
		end
	end
	for _, sz in ipairs({ -1, 1 }) do
		rod(f, "MonkeyRail", at(park, Mk.X0, Mk.BarY, Mk.Z + sz * hw), at(park, Mk.X1, Mk.BarY, Mk.Z + sz * hw), 0.3, ORANGE, M.Metal, true)
	end
	for k = 1, Mk.Rungs do
		local x = Mk.X0 + (Mk.X1 - Mk.X0) * k / (Mk.Rungs + 1)
		rod(f, "MonkeyRung", at(park, x, Mk.BarY + 0.02, Mk.Z - hw), at(park, x, Mk.BarY + 0.02, Mk.Z + hw), 0.2, STEEL, M.Metal)
	end
	f.Parent = park.Folder
end

-- 🏖️ bac à sable : cadre en rondins, sable, jouets
local function buildSandbox(park: Park)
	local g = park.G
	local S = ParkMotion.SAND
	local box = g * CFrame.new(S.Center)
	local f = Instance.new("Model")
	f.Name = "Sandbox"
	local half = S.Inner / 2
	newPart(f, "Sand", Vector3.new(S.Inner, 0.4, S.Inner), box * CFrame.new(0, 0.35, 0), SAND, M.Sand)
	for k = 1, 3 do
		egg(f, "SandBump", box * CFrame.new(math.cos(k * 2.1) * 1.8, 0.52, math.sin(k * 2.1) * 1.6), Vector3.new(1.6, 0.26, 1.2), SAND:Lerp(SAND_D, 0.3), M.Sand)
	end
	for _, s in ipairs({ -1, 1 }) do
		newPart(f, "Border", Vector3.new(S.Inner + 1.0, 0.8, 0.5), box * CFrame.new(0, 0.44, s * (half + 0.25)), WOOD, M.Wood, nil, true)
		newPart(f, "Border", Vector3.new(0.5, 0.78, S.Inner), box * CFrame.new(s * (half + 0.25), 0.43, 0), WOOD, M.Wood, nil, true)
		newPart(f, "BorderCap", Vector3.new(S.Inner + 1.1, 0.12, 0.62), box * CFrame.new(0, 0.9, s * (half + 0.25)), WOOD_L, M.WoodPlanks)
		newPart(f, "BorderCap", Vector3.new(0.62, 0.1, S.Inner - 0.04), box * CFrame.new(s * (half + 0.25), 0.88, 0), WOOD_L, M.WoodPlanks)
	end
	-- jouets : seau + anse, pelle, château, ballon
	local sandTop = 0.55
	local bucket = box * CFrame.new(1.6, sandTop, 1.2)
	newPart(f, "Bucket", Vector3.new(0.8, 0.85, 0.85), bucket * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(236, 72, 90), M.SmoothPlastic, CYL)
	newPart(f, "BucketRim", Vector3.new(0.1, 0.95, 0.95), bucket * CFrame.new(0, 0.84, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(250, 110, 120), M.SmoothPlastic, CYL)
	rod(f, "BucketHandle", (bucket * CFrame.new(-0.44, 0.95, 0)).Position, (bucket * CFrame.new(0, 1.2, 0)).Position, 0.06, INK, M.SmoothPlastic)
	rod(f, "BucketHandle", (bucket * CFrame.new(0, 1.2, 0)).Position, (bucket * CFrame.new(0.44, 0.95, 0)).Position, 0.06, INK, M.SmoothPlastic)
	rod(f, "Spade", (box * CFrame.new(-1.3, sandTop + 0.08, 1.7)).Position, (box * CFrame.new(-0.3, sandTop + 0.8, 1.2)).Position, 0.12, BLUE, M.SmoothPlastic)
	newPart(f, "SpadeBlade", Vector3.new(0.5, 0.06, 0.6), box * CFrame.new(-1.55, sandTop + 0.05, 1.82) * CFrame.Angles(0, rad(25), 0), BLUE, M.SmoothPlastic)
	local castle = box * CFrame.new(-1.2, sandTop, -1.3)
	newPart(f, "Castle", Vector3.new(1.3, 1.5, 1.5), castle * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2), SAND:Lerp(SAND_D, 0.2), M.Sand, CYL)
	for k = 0, 3 do
		local a = k * math.pi / 2
		newPart(f, "Turret", Vector3.new(0.9, 0.5, 0.5), castle * CFrame.new(math.cos(a) * 0.95, 0.45, math.sin(a) * 0.95) * CFrame.Angles(0, 0, math.pi / 2), SAND:Lerp(SAND_D, 0.35), M.Sand, CYL)
	end
	ball(f, "Ball", (g * CFrame.new(7.6, ParkMotion.FLOOR_TOP + 0.62, 3.2)).Position, 1.2, rgb(255, 110, 140), M.SmoothPlastic)
	f.Parent = park.Folder
end

-- 🪑 bancs des parents (fonte + lattes, assise à 1,45)
local function buildBenches(park: Park)
	local g = park.G
	local B = ParkMotion.BENCH
	for b = 1, #ParkMotion.BENCHES do
		local cf = g * ParkMotion.BenchFrame(b)
		local f = Instance.new("Model")
		f.Name = "ParkBench" .. b
		local H = B.SeatTop
		local L = B.Length
		for k = 0, 2 do
			local z = -0.55 + k * 0.5
			newPart(f, "SeatSlat", Vector3.new(L, 0.14, 0.42), cf * CFrame.new(0, H - 0.07, z), WOOD, M.Wood, nil, true)
		end
		local back = cf * CFrame.new(0, H + 0.05, 0.62) * CFrame.Angles(rad(12), 0, 0)
		for _, y in ipairs({ 0.55, 1.15 }) do
			newPart(f, "BackSlat", Vector3.new(L, 0.42, 0.12), back * CFrame.new(0, y, 0), WOOD, M.Wood, nil, true)
		end
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * (L / 2 - 0.35)
			newPart(f, "FrontLeg", Vector3.new(0.18, H + 0.62, 0.18), cf * CFrame.new(x, (H + 0.62) / 2, -0.62), IRON, M.Metal)
			newPart(f, "RearLeg", Vector3.new(0.18, H, 0.18), cf * CFrame.new(x, H / 2, 0.55), IRON, M.Metal)
			newPart(f, "BackPost", Vector3.new(0.16, 1.55, 0.14), back * CFrame.new(x, 0.75, -0.13), IRON, M.Metal)
			newPart(f, "SeatRail", Vector3.new(0.16, 0.16, 1.4), cf * CFrame.new(x, H - 0.22, -0.02), IRON, M.Metal)
			newPart(f, "ArmRest", Vector3.new(0.24, 0.12, 1.3), cf * CFrame.new(sx * (L / 2 - 0.3), H + 0.68, -0.08), IRON, M.Metal)
		end
		f.Parent = park.Folder
	end
end

----------------------------------------------------------------------
-- Sièges du serveur, invites (traduites), activités
----------------------------------------------------------------------

local LOCAL_KINDS = { Slide = true, SlideTop = true, MonkeyA = true, MonkeyB = true, Dig = true }

local startActivity: (park: Park, action: string) -> ()

local function hookServer(park: Park)
	local server = park.Server
	if not server or not server.Parent then
		return
	end
	-- sièges par jeu
	for _, piece in ipairs(park.Pieces) do
		if not piece.Server or not piece.Server.Parent then
			local name = piece.Kind == "Merry" and "Merry" or (piece.Kind == "Seesaw" and "Seesaw" or piece.Kind .. piece.Index)
			local model = server:FindFirstChild(name)
			if model then
				piece.Server = model
				piece.Settled = false
				table.clear(piece.Seats)
				for _, d in ipairs(model:GetChildren()) do
					local slot = d:GetAttribute("ParkSlot")
					if d:IsA("Seat") and type(slot) == "number" then
						piece.Seats[slot] = d
					end
				end
			end
		end
	end
	-- invites : textes traduits ; celles des activités -> ici
	for _, d in ipairs(server:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "ParkPrompt" and not table.find(park.Prompts, d) then
			table.insert(park.Prompts, d)
			local action = d:GetAttribute("LocAction")
			local object = d:GetAttribute("LocObject")
			if type(action) == "string" then
				d.ActionText = Locale.T(action)
			end
			if type(object) == "string" then
				d.ObjectText = Locale.T(object)
			end
			local kind = d:GetAttribute("ParkAction")
			if type(kind) == "string" and LOCAL_KINDS[kind] then
				table.insert(park.Conns, d.Triggered:Connect(function(player: Player)
					if player == Players.LocalPlayer then
						startActivity(park, kind)
					end
				end))
			end
		end
	end
end

----------------------------------------------------------------------
-- Mouvement des jeux (heure du serveur)
----------------------------------------------------------------------

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local seatFrames: { CFrame } = {}
local seatList: { BasePart } = {}

-- Pose courante d'un jeu -> pièces mobiles + sièges du serveur (localement)
local function stepPiece(park: Park, piece: Piece, t: number)
	local s = ParkMotion.StateOf(piece.Server)
	local g = park.G
	local kind = piece.Kind
	if kind == "Merry" then
		local angle, w = ParkMotion.Merry(s, t)
		if not s.On and math.abs(w) < 1e-3 and piece.Settled then
			return
		end
		piece.Settled = not s.On and math.abs(w) < 1e-3
		moveGroup(piece.Groups[1], g * ParkMotion.MerryFrame(angle))
		table.clear(seatFrames)
		table.clear(seatList)
		for k, seat in pairs(piece.Seats) do
			table.insert(seatList, seat)
			table.insert(seatFrames, g * ParkMotion.MerrySeat(k, angle) * CFrame.new(0, -seat.Size.Y / 2, 0))
		end
	else
		local env = ParkMotion.EnvOf(kind, s, t)
		if not s.On and env < 1e-3 and piece.Settled then
			return
		end
		piece.Settled = not s.On and env < 1e-3
		if piece.Settled then
			env = 0
		end
		table.clear(seatFrames)
		table.clear(seatList)
		if kind == "Swing" then
			local angle = ParkMotion.SwingAngle(env, t, piece.Index)
			moveGroup(piece.Groups[1], g * ParkMotion.SwingPivot(piece.Index) * CFrame.Angles(angle, 0, 0))
			local seat = piece.Seats[1]
			if seat then
				table.insert(seatList, seat)
				table.insert(seatFrames, g * ParkMotion.SwingSeat(piece.Index, angle) * CFrame.new(0, -seat.Size.Y / 2, 0))
			end
		elseif kind == "Seesaw" then
			local angle = ParkMotion.SeesawAngle(env, t)
			moveGroup(piece.Groups[1], g * ParkMotion.SeesawPivot(angle))
			for k, seat in pairs(piece.Seats) do
				table.insert(seatList, seat)
				table.insert(seatFrames, g * ParkMotion.SeesawSeat(k, angle) * CFrame.new(0, -seat.Size.Y / 2, 0))
			end
		elseif kind == "Spring" then
			local body = g * ParkMotion.SpringBody(piece.Index, env, t)
			moveGroup(piece.Groups[1], body)
			-- ressort : chaque spire entre le socle et le corps (hélice qui se tord)
			local extra = piece.Extra
			local coil = extra.Coil
			local base: CFrame = extra.Base * CFrame.new(0, ParkMotion.SPRING.PivotY, 0)
			local top: CFrame = body * CFrame.new(0, 0.62, 0)
			local frames = {}
			local n = #coil
			for k = 1, n do
				local u = (k - 1) / n
				local ring = base:Lerp(top, u)
				local a = (k - 1) * TAU / 4
				local p0 = ring * Vector3.new(math.cos(a) * 0.3, 0, math.sin(a) * 0.3)
				local a1 = a + TAU / 4
				local ring1 = base:Lerp(top, u + 1 / n)
				local p1 = ring1 * Vector3.new(math.cos(a1) * 0.3, 0, math.sin(a1) * 0.3)
				frames[k] = rodCF(p0, p1)
			end
			workspace:BulkMoveTo(coil, frames, Enum.BulkMoveMode.FireCFrameChanged)
			local seat = piece.Seats[1]
			if seat then
				table.insert(seatList, seat)
				table.insert(seatFrames, g * ParkMotion.SpringSeat(piece.Index, env, t) * CFrame.new(0, -seat.Size.Y / 2, 0))
			end
		end
	end
	if #seatList > 0 then
		workspace:BulkMoveTo(seatList, seatFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Pose de l'enfant assis sur la place `slot` du jeu `piece`
local function riderPose(park: Park, piece: Piece, slot: number, seat: BasePart, t: number): Pose?
	local s = ParkMotion.StateOf(piece.Server)
	local top = seat.CFrame * CFrame.new(0, seat.Size.Y / 2, 0)
	local kind = piece.Kind
	if kind == "Swing" then
		local env = ParkMotion.EnvOf(kind, s, t)
		local angle, phase = ParkMotion.SwingAngle(env, t, piece.Index)
		return swingPose(top, angle, phase, env)
	elseif kind == "Seesaw" then
		local env = ParkMotion.EnvOf(kind, s, t)
		local angle = ParkMotion.SeesawAngle(env, t)
		-- (bout bas : genoux pliés, pieds au sol ; bout haut : jambes pendantes)
		local low = (slot == 1 and angle > 0 or slot == 2 and angle < 0) and math.abs(angle) / ParkMotion.SEESAW.Tilt or 0
		return handleBarPose(top, Vector3.new(0.42, 1.02, -0.85), 70 + 25 * low, 45 + 55 * low, 4 + 6 * low)
	elseif kind == "Merry" then
		local _, w = ParkMotion.Merry(s, t)
		local p = handleBarPose(top, Vector3.new(0.5, 1.15, -0.85), 84, 92, 6)
		-- (ça tourne : on se penche un peu vers l'extérieur, la tête suit)
		p.Root = CFrame.Angles(0, 0, rad(-6 * math.clamp(w / ParkMotion.MERRY.Wmax, -1, 1)))
		return p
	elseif kind == "Spring" then
		local horse = (ParkMotion.SPRINGS[piece.Index] or ParkMotion.SPRINGS[1]).Kind == "Horse"
		local p = handleBarPose(top, horse and Vector3.new(0.5, 0.45, -1.1) or Vector3.new(0.5, 0.5, -0.77), 62, 72, 8)
		p.RHip = Rx(62) * CFrame.Angles(0, 0, rad(-22))
		p.LHip = Rx(62) * CFrame.Angles(0, 0, rad(22))
		return p
	end
	local _ = park
	return nil
end

----------------------------------------------------------------------
-- 🏃 Activités du joueur local (toboggan, barres de singe, bac à sable)
----------------------------------------------------------------------

type Activity = {
	Kind: string,
	Park: Park,
	Phase: string,
	T: number, -- (s) dans la phase
	Total: number,
	Z: number, -- toboggan : abscisse sur la glissière
	V: number, -- toboggan : vitesse
	From: CFrame?,
	Dir: number, -- barres : sens (+1 / -1)
	Scoops: number,
	Props: { BasePart },
}

local activity: Activity? = nil
local castles = 0

local function localRig(): (Rig?, Humanoid?)
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if not character then
		return nil, nil
	end
	local rig = rigOf(character)
	return rig, rig and rig.Humanoid or nil
end

local function setPrompts(park: Park, on: boolean)
	for _, p in ipairs(park.Prompts) do
		if p.Parent then
			p.Enabled = on
		end
	end
end

local function endActivity()
	local a = activity
	activity = nil
	if not a then
		return
	end
	local rig, humanoid = localRig()
	if rig and humanoid then
		pcall(function()
			if a.Kind ~= "Dig" then
				humanoid.PlatformStand = false
				rig.Root.AssemblyLinearVelocity = Vector3.zero
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
		releasePose(rig.Character)
	end
	for _, p in ipairs(a.Props) do
		if p:GetAttribute("Keep") ~= true then
			p:Destroy()
		end
	end
	setPrompts(a.Park, true)
end

startActivity = function(park: Park, action: string)
	if activity or failed then
		return
	end
	local rig, humanoid = localRig()
	if not rig or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return
	end
	local kind = (action == "Slide" or action == "SlideTop") and "Slide" or ((action == "MonkeyA" or action == "MonkeyB") and "Monkey" or "Dig")
	local a: Activity = {
		Kind = kind,
		Park = park,
		Phase = if action == "SlideTop" then "walk" elseif kind == "Slide" then "approach" elseif kind == "Monkey" then "approach" else "kneel",
		T = 0,
		Total = 0,
		Z = 0,
		V = 0,
		From = rig.Root.CFrame,
		Dir = action == "MonkeyB" and -1 or 1,
		Scoops = 0,
		Props = {},
	}
	if kind ~= "Dig" then
		humanoid.PlatformStand = true
	else
		-- à genoux face au milieu du bac
		local center = park.G * ParkMotion.SAND.Center
		local pos = rig.Root.Position
		local flat = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
		if flat.Magnitude > 0.5 then
			rig.Root.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
		end
	end
	setPrompts(park, false)
	activity = a
end

-- Repères utiles (monde)
local function towerCF(park: Park): CFrame
	return park.G * ParkMotion.SlideTower()
end

local HRP_SIT = 1.5 -- (studs) centre du HRP au-dessus de ce sur quoi on est assis
local HRP_STAND = 3.0 -- … et au-dessus du sol, debout

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Position du HRP pendant l'activité (+ vitesse), et fin éventuelle
local function activityFrame(a: Activity, dt: number): (CFrame?, Vector3)
	local park = a.Park
	local g = park.G
	a.T += dt
	a.Total += dt
	if a.Kind == "Slide" then
		local S = ParkMotion.SLIDE
		local tower = towerCF(park)
		local lean = math.tan(S.LadderLean)
		local footZ = S.LadderZ - (S.DeckTop - 0.2) * lean
		local floorY = ParkMotion.FLOOR_TOP
		local bottom = tower * CFrame.new(0, floorY + HRP_STAND, footZ - 1.05)
		local face = CFrame.Angles(0, math.pi, 0) -- (tourné vers +Z : vers l'échelle / la glissière)
		if a.Phase == "approach" then
			local from = a.From or bottom
			local dur = 0.3 + math.min(0.6, (from.Position - bottom.Position).Magnitude / 12)
			local u = smooth(a.T / dur)
			local cf = from:Lerp(bottom * face, u)
			if a.T >= dur then
				a.Phase, a.T = "climb", 0
			end
			return cf, Vector3.zero
		elseif a.Phase == "climb" then
			-- barreau par barreau (0,85 stud) : petites montées avec pause
			local rungs = 6
			local per = 0.42
			local k = math.min(a.T / per, rungs)
			local whole = math.floor(k)
			local frac = k - whole
			local rise = (whole + smooth(frac * 1.4)) * 0.85
			local y = floorY + HRP_STAND + math.min(rise, S.DeckTop + 0.1 - floorY)
			local z = S.LadderZ - (S.DeckTop - (y - 1.0)) * lean - 1.0
			local cf = tower * CFrame.new(0, y, math.min(z, S.LadderZ - 0.9)) * face
			if k >= rungs then
				a.Phase, a.T = "over", 0
			end
			return cf, Vector3.new(0, 0.85 / per, 0)
		elseif a.Phase == "over" or a.Phase == "walk" then
			-- on passe sur le plancher et on va au départ de la glissière
			local topCF = tower * CFrame.new(0, S.DeckTop + HRP_STAND, -0.4) * face
			local startCF = tower * CFrame.new(0, S.DeckTop + HRP_STAND, 1.2) * face
			if a.Phase == "over" then
				local from = tower * CFrame.new(0, floorY + HRP_STAND + S.DeckTop + 0.1 - floorY, S.LadderZ - 0.9) * face
				local u = smooth(a.T / 0.5)
				if a.T >= 0.5 then
					a.Phase, a.T = "walk", 0
					a.From = topCF
				end
				local cf = from:Lerp(topCF, u)
				return cf + Vector3.new(0, math.sin(u * math.pi) * 0.25, 0), Vector3.zero
			end
			local from = a.From or topCF
			local u = smooth(a.T / 0.6)
			if a.T >= 0.6 then
				a.Phase, a.T = "sitdown", 0
			end
			return from:Lerp(startCF, u), Vector3.zero
		elseif a.Phase == "sitdown" then
			local startCF = tower * CFrame.new(0, S.DeckTop + HRP_STAND, 1.2) * face
			local y0 = ParkMotion.SlideSurface(1.9)
			local seatCF = tower * CFrame.new(0, y0 + HRP_SIT, 1.9) * face
			local u = smooth(a.T / 0.4)
			if a.T >= 0.4 then
				a.Phase, a.T, a.Z, a.V = "slide", 0, 1.9, 1.2
			end
			return startCF:Lerp(seatCF, u), Vector3.zero
		elseif a.Phase == "slide" then
			-- glissade : gravité le long de la pente, frottement, traînée
			local G = ParkMotion.G
			local y, dy = ParkMotion.SlideSurface(a.Z)
			local n = math.sqrt(1 + dy * dy)
			local sinA, cosA = -dy / n, 1 / n
			local acc = G * (sinA - 0.26 * cosA) - 0.03 * a.V * a.V
			a.V = math.max(0.8, a.V + acc * dt)
			a.Z += a.V * cosA * dt
			y, dy = ParkMotion.SlideSurface(a.Z)
			local pitch = -math.atan(dy) * 0.55
			local cf = tower * CFrame.new(0, y + HRP_SIT, a.Z) * face * CFrame.Angles(pitch, 0, 0)
			local vel = tower:VectorToWorldSpace(Vector3.new(0, a.V * dy / n, a.V / n))
			if a.Z >= ParkMotion.SLIDE_END - 0.05 then
				a.Phase, a.T = "out", 0
				a.From = cf
			end
			return cf, vel
		elseif a.Phase == "out" then
			-- sortie : on glisse encore un peu et on se relève
			local zEnd = ParkMotion.SLIDE_END
			local dz = math.min(a.V, 4) * 0.45
			local from = a.From or (tower * CFrame.new(0, 1 + HRP_SIT, zEnd) * face)
			local to = tower * CFrame.new(0, floorY + HRP_STAND, zEnd + 0.9 + dz) * face
			local u = smooth(a.T / 0.55)
			if a.T >= 0.55 then
				return nil, Vector3.zero
			end
			return from:Lerp(to, u), Vector3.zero
		end
	elseif a.Kind == "Monkey" then
		local Mk = ParkMotion.MONKEY
		local x0 = a.Dir > 0 and Mk.X0 or Mk.X1
		local x1 = a.Dir > 0 and Mk.X1 or Mk.X0
		local look = CFrame.Angles(0, a.Dir > 0 and -math.pi / 2 or math.pi / 2, 0) -- (regard vers le bout d'arrivée)
		local hang = Mk.BarY - 2.35
		local first = x0 + (x1 - x0) / (Mk.Rungs + 1)
		if a.Phase == "approach" then
			local stand = g * CFrame.new(x0 - a.Dir * 0.9, ParkMotion.FLOOR_TOP + HRP_STAND, Mk.Z) * look
			local u = smooth(a.T / 0.4)
			if a.T >= 0.4 then
				a.Phase, a.T = "up", 0
			end
			return (a.From or stand):Lerp(stand, u), Vector3.zero
		elseif a.Phase == "up" then
			-- 3 barreaux de l'échelle du bout, puis on attrape la 1re barre
			local stand = g * CFrame.new(x0 - a.Dir * 0.9, ParkMotion.FLOOR_TOP + HRP_STAND, Mk.Z) * look
			local grab = g * CFrame.new(first, hang, Mk.Z) * look
			local u = smooth(a.T / 1.1)
			if a.T >= 1.1 then
				a.Phase, a.T = "cross", 0
			end
			return stand:Lerp(grab, u) + Vector3.new(0, math.sin(u * math.pi) * 0.5, 0), Vector3.zero
		elseif a.Phase == "cross" then
			local per = 0.62
			local spacing = (x1 - x0) / (Mk.Rungs + 1)
			local k = a.T / per
			local n = Mk.Rungs - 1
			if k >= n then
				a.Phase, a.T = "drop", 0
				k = n
			end
			local whole = math.floor(k)
			local frac = k - whole
			local x = first + (whole + smooth(frac)) * spacing
			-- le corps balance d'avant en arrière à chaque prise
			local swing = math.sin(k * math.pi) * rad(10)
			local cf = g * CFrame.new(x, hang - 0.12 * math.sin(frac * math.pi), Mk.Z) * look * CFrame.Angles(swing, 0, 0)
			return cf, Vector3.new(0, 0, 0)
		elseif a.Phase == "drop" then
			local last = x0 + (x1 - x0) * Mk.Rungs / (Mk.Rungs + 1)
			local from = g * CFrame.new(last, hang, Mk.Z) * look
			local land = g * CFrame.new(x1 + a.Dir * 0.9, ParkMotion.FLOOR_TOP + HRP_STAND - 0.35, Mk.Z) * look
			local u = math.clamp(a.T / 0.55, 0, 1)
			if a.T >= 0.75 then
				return nil, Vector3.zero
			end
			local pos = from.Position:Lerp(land.Position, u) + Vector3.new(0, math.sin(u * math.pi) * 0.4 - u * u * 0.0, 0)
			return CFrame.new(pos) * from.Rotation, Vector3.zero
		end
	end
	return nil, Vector3.zero
end

-- Pose de l'activité
local function activityPose(a: Activity, rig: Rig): Pose
	local pose: Pose = {}
	local root = rig.Root.CFrame
	local park = a.Park
	if a.Kind == "Slide" then
		local S = ParkMotion.SLIDE
		local tower = towerCF(park)
		if a.Phase == "climb" or a.Phase == "approach" then
			-- mains sur les barreaux du dessus (en alternance), pieds sur les barreaux
			local lean = math.tan(S.LadderLean)
			local hy = root.Position.Y - tower.Position.Y
			local k = a.T / 0.42
			local function rungAt(y: number): Vector3
				local ry = math.clamp(math.floor(y / 0.85 + 0.5), 1, 7) * 0.85
				return (tower * CFrame.new(0, ry, S.LadderZ - (S.DeckTop - ry) * lean)).Position
			end
			local rOff = (math.floor(k) % 2 == 0) and 0.85 or 0
			pose.RHand = rungAt(hy + 1.2 + rOff) + tower.RightVector * 0.45
			pose.LHand = rungAt(hy + 2.05 - rOff) - tower.RightVector * 0.45
			pose.RPole = -tower.RightVector * -0.8 - tower.LookVector * 0.5 - UP * 0.5
			pose.LPole = tower.RightVector * -0.8 - tower.LookVector * 0.5 - UP * 0.5
			local step = math.sin(k * math.pi)
			pose.RHip = Rx(35 + 30 * step)
			pose.LHip = Rx(35 + 30 * (1 - step))
			pose.RKnee = Rx(-(50 + 30 * step))
			pose.LKnee = Rx(-(50 + 30 * (1 - step)))
			pose.Waist = Rx(-6)
		elseif a.Phase == "sitdown" or a.Phase == "slide" then
			local w = a.Phase == "slide" and 1 or smooth(a.T / 0.4)
			pose.RHip = Rx(84 * w)
			pose.LHip = Rx(84 * w)
			pose.RKnee = Rx(-18 * w)
			pose.LKnee = Rx(-18 * w)
			pose.RAnkle = Rx(20 * w)
			pose.LAnkle = Rx(20 * w)
			pose.Waist = Rx(10 * w)
			pose.Neck = Rx(-12 * w)
			-- mains sur les boudins de la glissière (ou en l'air : youpi !)
			local joy = a.Phase == "slide" and a.V > 5
			if joy then
				pose.RHand = (root * CFrame.new(1.1, 2.9, -0.2)).Position
				pose.LHand = (root * CFrame.new(-1.1, 2.9, -0.2)).Position
			else
				pose.RHand = (root * CFrame.new(1.05, -0.75, -0.25)).Position
				pose.LHand = (root * CFrame.new(-1.05, -0.75, -0.25)).Position
			end
		elseif a.Phase == "out" then
			local w = 1 - smooth(a.T / 0.55)
			pose.RHip = Rx(84 * w)
			pose.LHip = Rx(84 * w)
			pose.RKnee = Rx(-40 * w)
			pose.LKnee = Rx(-40 * w)
			pose.Waist = Rx(-8 * w)
		end
	elseif a.Kind == "Monkey" then
		local Mk = ParkMotion.MONKEY
		local g = park.G
		local x0 = a.Dir > 0 and Mk.X0 or Mk.X1
		local x1 = a.Dir > 0 and Mk.X1 or Mk.X0
		local spacing = (x1 - x0) / (Mk.Rungs + 1)
		local function bar(i: number, side: number): Vector3
			local x = x0 + math.clamp(i, 1, Mk.Rungs) * spacing
			return g * Vector3.new(x, Mk.BarY + 0.02, Mk.Z + side * 0.42)
		end
		if a.Phase == "cross" then
			local k = a.T / 0.62
			local whole = math.floor(k)
			local frac = k - whole
			-- une main tient la barre, l'autre passe à la suivante
			local lead, trail = whole + 2, whole + 1
			local reach = bar(trail, 0):Lerp(bar(lead, 0), smooth(frac)) + Vector3.new(0, math.sin(frac * math.pi) * 0.35, 0)
			local r, l
			if whole % 2 == 0 then
				r, l = reach + (bar(1, 1) - bar(1, 0)), bar(trail, -1)
			else
				r, l = bar(trail, 1), reach + (bar(1, -1) - bar(1, 0))
			end
			pose.RHand, pose.LHand = r, l
			local sway = math.sin(k * math.pi)
			pose.RHip = Rx(12 * sway)
			pose.LHip = Rx(-8 * sway + 10)
			pose.RKnee = Rx(-25)
			pose.LKnee = Rx(-35)
		elseif a.Phase == "up" then
			local u = smooth(a.T / 1.1)
			pose.RHand = (root * CFrame.new(0.45, 1.3 + 1.2 * u, -0.6)).Position:Lerp(bar(1, 1), u)
			pose.LHand = (root * CFrame.new(-0.45, 1.0 + 1.2 * u, -0.6)).Position:Lerp(bar(1, -1), u)
			pose.RHip = Rx(40 * (1 - u))
			pose.LHip = Rx(15 * (1 - u))
			pose.RKnee = Rx(-60 * (1 - u))
			pose.LKnee = Rx(-20 * (1 - u))
		elseif a.Phase == "drop" then
			local u = smooth(a.T / 0.75)
			local crouch = math.sin(math.clamp((a.T - 0.45) / 0.3, 0, 1) * math.pi)
			pose.RHip = Rx(55 * crouch)
			pose.LHip = Rx(55 * crouch)
			pose.RKnee = Rx(-80 * crouch)
			pose.LKnee = Rx(-80 * crouch)
			pose.Root = CFrame.new(0, -0.5 * crouch, 0)
			pose.RArm = CFrame.Angles(0, 0, rad(40 * (1 - u)))
			pose.LArm = CFrame.Angles(0, 0, rad(-40 * (1 - u)))
		end
	elseif a.Kind == "Dig" then
		-- à genoux (genou gauche au sol), la pelle creuse devant
		local w = smooth(a.Total / 0.5)
		pose.Root = CFrame.new(0, -0.8 * w, 0.1 * w)
		pose.RHip = Rx(85 * w)
		pose.RKnee = Rx(-95 * w)
		pose.LHip = Rx(-5 * w)
		pose.LKnee = Rx(-95 * w)
		pose.LAnkle = Rx(40 * w)
		local cyc = (a.Total % 1.2) / 1.2
		local scoop = math.sin(cyc * TAU)
		pose.Waist = Rx(-(22 + 10 * scoop) * w)
		pose.Neck = Rx(-18 * w)
		local sandY = park.G.Position.Y + 0.6
		local front = root * CFrame.new(0.35, 0, -1.7 - 0.3 * scoop)
		local hand = Vector3.new(front.Position.X, sandY + 0.5 + 0.55 * math.max(0, scoop), front.Position.Z)
		pose.RHand = rig.Root.Position:Lerp(hand, w) + (1 - w) * Vector3.new(0, -1, 0)
		pose.LHand = (root * CFrame.new(-0.45, -1.55 * w, -1.0)).Position
	end
	return pose
end

-- Sable qui vole + tas + trou + château (local, discret)
local function stepDig(a: Activity, rig: Rig, dt: number)
	local park = a.Park
	local root = rig.Root.CFrame
	local sandY = park.G.Position.Y + 0.55
	-- pelle dans la main droite
	local spade = a.Props[1]
	if not spade then
		local f = park.Folder
		spade = newPart(f, "HeldSpade", Vector3.new(0.12, 1.1, 0.12), root, BLUE, M.SmoothPlastic)
		local blade = newPart(f, "HeldBlade", Vector3.new(0.5, 0.06, 0.55), root, BLUE, M.SmoothPlastic)
		local hole = newPart(f, "DigHole", Vector3.new(0.05, 1.2, 1.2), CFrame.new(), SAND_D, M.Sand, CYL)
		local heap = egg(f, "DigHeap", CFrame.new(), Vector3.new(0.4, 0.1, 0.4), SAND:Lerp(SAND_D, 0.15), M.Sand)
		table.insert(a.Props, spade)
		table.insert(a.Props, blade)
		table.insert(a.Props, hole)
		table.insert(a.Props, heap)
		local spot = root * CFrame.new(0.35, 0, -1.8)
		hole.CFrame = CFrame.new(spot.Position.X, sandY + 0.02, spot.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
		heap:SetAttribute("Grow", 0)
		heap.CFrame = CFrame.new((root * CFrame.new(1.4, 0, -1.3)).Position.X, sandY, (root * CFrame.new(1.4, 0, -1.3)).Position.Z)
	end
	local hand = rig.Character:FindFirstChild("RightHand") or rig.Character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		local grip = hand.CFrame * CFrame.new(0, hand.Name == "Right Arm" and -0.9 or -0.1, 0)
		local shaft = grip * CFrame.Angles(rad(-70), 0, 0) * CFrame.new(0, -0.4, 0)
		spade.CFrame = shaft
		a.Props[2].CFrame = shaft * CFrame.new(0, -0.62, 0) * CFrame.Angles(rad(15), 0, 0)
	end
	-- chaque pelletée : le tas grossit, quelques grains volent
	local before = a.Scoops
	a.Scoops = math.floor(a.Total / 1.2)
	local heap = a.Props[4]
	if a.Scoops > before and heap then
		local grow = math.min(1, a.Scoops / 6)
		heap.Size = Vector3.new(0.4 + 1.3 * grow, 0.1 + 0.55 * grow, 0.4 + 1.1 * grow)
		local hole = a.Props[3]
		hole.Size = Vector3.new(0.05, 0.6 + 0.9 * grow, 0.6 + 0.9 * grow)
		hole.Color = SAND_D:Lerp(rgb(150, 120, 80), grow * 0.6)
		for k = 1, 4 do
			local grain = ball(park.Folder, "SandGrain", heap.Position + Vector3.new(math.cos(k * 1.7) * 0.3, 0.5 + k * 0.08, math.sin(k * 1.7) * 0.3), 0.14 + (k % 2) * 0.06, SAND, M.Sand)
			grain:SetAttribute("Born", clock)
			table.insert(a.Props, grain)
		end
		-- au bout de 5 pelletées : un petit château de sable (reste, 3 au plus)
		if a.Scoops == 5 and castles < 3 then
			castles += 1
			local c = root * CFrame.new(-1.2, 0, -1.6)
			local base = CFrame.new(c.Position.X, sandY, c.Position.Z)
			local keep = newPart(park.Folder, "SandCastle", Vector3.new(0.9, 1.0, 1.0), base * CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, math.pi / 2), SAND:Lerp(SAND_D, 0.25), M.Sand, CYL)
			keep:SetAttribute("Keep", true)
			for q = 0, 3 do
				local ang = q * math.pi / 2
				local tur = newPart(park.Folder, "SandTurret", Vector3.new(0.6, 0.34, 0.34), base * CFrame.new(math.cos(ang) * 0.62, 0.3, math.sin(ang) * 0.62) * CFrame.Angles(0, 0, math.pi / 2), SAND:Lerp(SAND_D, 0.4), M.Sand, CYL)
				tur:SetAttribute("Keep", true)
			end
		end
	end
	-- grains : montent puis retombent, disparaissent
	for i = #a.Props, 5, -1 do
		local p = a.Props[i]
		local born = p:GetAttribute("Born")
		if type(born) == "number" then
			local age = clock - born
			if age > 0.7 then
				p:Destroy()
				table.remove(a.Props, i)
			else
				p.CFrame = p.CFrame + Vector3.new(0.4 * dt, (1.8 - 9 * age) * dt, 0)
			end
		end
	end
	local _ = dt
end

----------------------------------------------------------------------
-- Autres joueurs : glissière, échelle, barres (pose d'après la position)
----------------------------------------------------------------------

local function remoteActivityPose(park: Park, rig: Rig): Pose?
	local root = rig.Root.CFrame
	local S = ParkMotion.SLIDE
	local lp = towerCF(park):PointToObjectSpace(root.Position)
	if math.abs(lp.X) < 1.2 and lp.Z > 1.6 and lp.Z < ParkMotion.SLIDE_END + 0.3 then
		local y = ParkMotion.SlideSurface(lp.Z)
		if lp.Y - y > 0.9 and lp.Y - y < 2.2 then
			return activityPose({ Kind = "Slide", Park = park, Phase = "slide", T = 1, Total = 1, Z = lp.Z, V = 3, Dir = 1, Scoops = 0, Props = {} }, rig)
		end
	end
	if math.abs(lp.X) < 1.1 and lp.Z < S.LadderZ - 0.4 and lp.Z > S.LadderZ - 2.6 and lp.Y > ParkMotion.FLOOR_TOP + HRP_STAND + 0.4 and lp.Y < S.DeckTop + HRP_STAND then
		return activityPose({ Kind = "Slide", Park = park, Phase = "climb", T = (lp.Y % 0.85) / 0.85 * 0.42 + math.floor(lp.Y / 0.85) * 0.42, Total = 1, Z = 0, V = 0, Dir = 1, Scoops = 0, Props = {} }, rig)
	end
	local Mk = ParkMotion.MONKEY
	local mp = park.G:PointToObjectSpace(root.Position)
	if mp.X > Mk.X0 and mp.X < Mk.X1 and math.abs(mp.Z - Mk.Z) < 1 and mp.Y > Mk.BarY - 3.2 and mp.Y < Mk.BarY - 1.4 then
		local dir = root.LookVector:Dot(park.G.RightVector) < 0 and -1 or 1
		local x0 = dir > 0 and Mk.X0 or Mk.X1
		local spacing = (Mk.X1 - Mk.X0) / (Mk.Rungs + 1)
		local k = math.max(0, (mp.X - x0) * dir / spacing - 1)
		return activityPose({ Kind = "Monkey", Park = park, Phase = "cross", T = k * 0.62, Total = 1, Z = 0, V = 0, Dir = dir, Scoops = 0, Props = {} }, rig)
	end
	return nil
end

----------------------------------------------------------------------
-- Boucles
----------------------------------------------------------------------

local function destroyPark(park: Park)
	park.Dead = true
	for _, c in ipairs(park.Conns) do
		c:Disconnect()
	end
	table.clear(park.Conns)
	if activity and activity.Park == park then
		endActivity()
	end
	-- sièges du serveur : remis à leur place de repos (plus personne ne les bouge)
	for _, piece in ipairs(park.Pieces) do
		for _, seat in pairs(piece.Seats) do
			if seat.Parent then
				pcall(function()
					local slot = seat:GetAttribute("ParkSlot") :: number
					local g = park.G
					local rest: CFrame? = nil
					if piece.Kind == "Swing" then
						rest = g * ParkMotion.SwingSeat(piece.Index, 0)
					elseif piece.Kind == "Seesaw" then
						rest = g * ParkMotion.SeesawSeat(slot, ParkMotion.SeesawAngle(0, 0))
					elseif piece.Kind == "Merry" then
						rest = g * ParkMotion.MerrySeat(slot, 0)
					elseif piece.Kind == "Spring" then
						rest = g * ParkMotion.SpringSeat(piece.Index, 0, 0)
					end
					if rest then
						seat.CFrame = rest * CFrame.new(0, -seat.Size.Y / 2, 0)
					end
				end)
			end
		end
	end
	for character in pairs(posed) do
		releasePose(character)
	end
	local index = table.find(parks, park)
	if index then
		table.remove(parks, index)
	end
end

local function cameraPos(): Vector3?
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

local function renderStep(dt: number)
	clock += dt
	local t = serverNow()
	local camPos = cameraPos()
	for i = #parks, 1, -1 do
		local park = parks[i]
		if not park.Parent.Parent or not park.Folder.Parent then
			destroyPark(park)
		else
			-- construction étalée
			for _ = 1, STEP_BUILD do
				local job = table.remove(park.Queue, 1)
				if job then
					job()
				end
			end
			park.Scan -= dt
			if park.Scan <= 0 then
				park.Scan = 1
				hookServer(park)
			end
			if #park.Queue == 0 and camPos and (camPos - park.G.Position).Magnitude < ANIM_R then
				for _, piece in ipairs(park.Pieces) do
					stepPiece(park, piece, t)
				end
			end
		end
	end
	-- activité du joueur local : position du HRP (image par image)
	local a = activity
	if a then
		local rig, humanoid = localRig()
		if not rig or not humanoid or humanoid.Health <= 0 or a.Park.Dead then
			endActivity()
			return
		end
		if a.Kind == "Dig" then
			a.T += dt
			a.Total += dt
			-- on bouge ou on saute : on se relève
			if a.Total > 0.6 and (humanoid.MoveDirection.Magnitude > 0.1 or humanoid.Jump) then
				endActivity()
				return
			end
			stepDig(a, rig, dt)
		else
			local cf, vel = activityFrame(a, dt)
			if not cf then
				endActivity()
				return
			end
			rig.Root.CFrame = cf
			rig.Root.AssemblyLinearVelocity = vel
			rig.Root.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function stepped(_time: number, _dt: number)
	local t = serverNow()
	local camPos = cameraPos()
	local seen: { [Model]: boolean } = {}
	-- enfants assis sur les jeux (nous et les autres)
	for _, park in ipairs(parks) do
		if #park.Queue == 0 and camPos and (camPos - park.G.Position).Magnitude < POSE_R + 40 then
			for _, piece in ipairs(park.Pieces) do
				for slot, seat in pairs(piece.Seats) do
					local occupant = seat.Occupant
					local character = occupant and occupant.Parent
					if character and character:IsA("Model") and seat:GetAttribute("ParkPose") == true then
						local rig = rigOf(character)
						if rig then
							local pose = riderPose(park, piece, slot, seat, t)
							if pose then
								applyPose(rig, pose)
								seen[character] = true
							end
						end
					end
				end
			end
			-- autres joueurs sur la glissière / l'échelle / les barres
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if player ~= Players.LocalPlayer and character and not seen[character] then
					local rig = rigOf(character)
					if rig and rig.Humanoid.SeatPart == nil and (rig.Root.Position - park.G.Position).Magnitude < 30 then
						local pose = remoteActivityPose(park, rig)
						if pose then
							applyPose(rig, pose)
							seen[character] = true
						end
					end
				end
			end
		end
	end
	-- nous : activité en cours
	local a = activity
	if a then
		local rig = localRig()
		if rig then
			applyPose(rig, activityPose(a, rig))
			seen[rig.Character] = true
		end
	end
	for character in pairs(posed) do
		if not seen[character] then
			releasePose(character)
		end
	end
end

local function guard(fn: (...any) -> ()): (...any) -> ()
	return function(...)
		if failed then
			return
		end
		local ok, err = pcall(fn, ...)
		if not ok then
			failed = true
			warn("[ParkPlay] " .. tostring(err))
			pcall(endActivity)
			for character in pairs(posed) do
				pcall(releasePose, character)
			end
		end
	end
end

local function ensureRunning()
	if running then
		return
	end
	running = true
	table.insert(conns, RunService.RenderStepped:Connect(guard(renderStep)))
	table.insert(conns, RunService.Stepped:Connect(guard(stepped)))
end

local function stopIfIdle()
	if #parks > 0 or not running then
		return
	end
	running = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	for character in pairs(posed) do
		releasePose(character)
	end
	table.clear(rigs)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function ParkPlay.Build(g: CFrame, parent: Instance, server: Instance?): any
	local folder = Instance.new("Model")
	folder.Name = "ParkPlay"
	folder.Parent = parent
	local park: Park = {
		G = g,
		Parent = parent,
		Folder = folder,
		Server = server,
		Queue = {},
		Pieces = {},
		Prompts = {},
		Conns = {},
		Scan = 0,
		Sand = {},
		Dead = false,
	}
	for _, job in ipairs({ buildGround, buildFence, buildSwings, buildSlide, buildMerry, buildSeesaw, buildSprings, buildMonkey, buildSandbox, buildBenches }) do
		table.insert(park.Queue, function()
			job(park)
		end)
	end
	table.insert(park.Queue, function()
		hookServer(park)
	end)
	table.insert(parks, park)
	-- (le parc disparaît avec son parent : la boucle le voit et nettoie)
	table.insert(park.Conns, folder.AncestryChanged:Connect(function()
		if not folder:IsDescendantOf(game) then
			task.defer(function()
				if not park.Dead then
					destroyPark(park)
				end
				stopIfIdle()
			end)
		end
	end))
	failed = false
	ensureRunning()
	return park
end

function ParkPlay.Debug(): any
	local parts, pieces = 0, 0
	for _, park in ipairs(parks) do
		for _, d in ipairs(park.Folder:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		pieces += #park.Pieces
	end
	local a = activity
	return {
		Parks = #parks,
		Parts = parts,
		Pieces = pieces,
		Running = running,
		Failed = failed,
		Activity = a and a.Kind or nil,
		Phase = a and a.Phase or nil,
		ActivityZ = a and a.Z or nil,
		ActivityV = a and a.V or nil,
		Posed = (function()
			local n = 0
			for _ in pairs(posed) do
				n += 1
			end
			return n
		end)(),
		Park = parks[1],
		Start = function(action: string)
			local park = parks[1]
			if park then
				startActivity(park, action)
			end
		end,
		Stop = endActivity,
		PoseOf = riderPose,
	}
end

return ParkPlay
