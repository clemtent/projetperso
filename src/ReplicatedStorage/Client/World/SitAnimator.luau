--[[
	SitAnimator (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > SitAnimator

	v9.8 🪑 S'asseoir "pour de vrai" dans Dopamine Town (SEAT98).
	Les animations ne peuvent pas être téléversées : tout est PROCÉDURAL, calculé
	chaque image côté client sur les Motor6D du personnage (R15 ET R6).

	  1. Tirer la chaise (chaises, chaises de bureau, tabourets) : l'invite
	     "S'asseoir" -> la chaise glisse en arrière (~1 stud, moins si un mur
	     est derrière), l'avatar s'avance devant l'assise (Humanoid:MoveTo,
	     court, avec délai max), puis on demande le siège au serveur
	     ("sit", inchangé). Une fois assis, la chaise (et le siège du serveur,
	     localement) revient doucement vers la table avec l'avatar dessus.
	     En se levant : la chaise recule puis se range toute seule.
	     Bureau gamer : seule la chaise bouge (pièces autour de l'assise).
	  2. Transitions douces : en s'asseyant, le corps part de là où il était
	     debout (position, orientation, pose) et descend sur le siège en se
	     penchant un peu en avant ; en se levant, la pose assise se fond dans
	     la pose debout.
	  3. Animations d'attente (après 8 à 15 s assis, puis toutes les 5 à 10 s) :
	     regarder autour, s'étirer, se pencher en arrière (mains derrière la
	     tête), croiser les jambes, balancer les pieds, regarder son téléphone
	     (petit téléphone dans la main), piquer du nez (canapé), dormir
	     (allongé sur un lit, 💤), bras en l'air (manèges). Respiration
	     légère en continu. Au bureau (vu des autres) : mains sur le clavier.
	  4. Les autres joueurs : le serveur met sur son siège "SitKind" et
	     "SitAt" (heure serveur) ; chaque client anime alors les joueurs
	     assis proches (≤ 60 studs, ≤ 6) avec le MÊME tirage (graine =
	     UserId + SitAt) : tout le monde voit à peu près la même chose, sans
	     nouveau remote. Leur chaise se range aussi chez nous.

	Robustesse (jamais de pose cassée) :
	  - on n'écrit que Motor6D.Transform (jamais C0/C1), dans RunService.Stepped
	    (après l'Animator) : l'animation de Roblox reprend la main dès qu'on
	    arrête d'écrire ; la base est relue chaque image (si l'Animator n'a pas
	    réécrit un joint, on repart de la dernière base connue : aucun cumul) ;
	  - arrêt : se lever (saut, bouton, serveur), bouger (le pas reprend le
	    compte à zéro), émote (piste de priorité Action), mode bureau
	    (DeskMode.IsActive / Changed : l'avatar y est masqué), mort, retrait
	    du personnage, sortie de la ville (Stop) ; toute erreur -> tout est
	    remis et le module se coupe (avertissement unique) ;
	  - les chaises reviennent EXACTEMENT à leur place (CFrame d'origine) ; si
	    quelqu'un d'autre a déplacé la chaise entre-temps (mode édition,
	    reconstruction de la pièce), on n'y touche plus.

	API (appelée par TownClient) :
	  SitAnimator.Start()     à l'entrée en ville
	  SitAnimator.Stop()      à la sortie (tout est remis)
	  SitAnimator.Approach(model, seatPart, sit)
	      remplace l'appel direct au serveur dans l'invite "S'asseoir" :
	      tire la chaise, avance l'avatar, puis appelle sit(cf, kind)
	      (cf = même CFrame qu'avant : dessus de la SeatPart ; kind = "chair",
	      "desk", "stool", "sofa", "bed", "bench", "seat")
	  SitAnimator.KindOf(model?, seat?) -> string
	  SitAnimator.Debug() -> état interne (tests)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage.Shared.Locale)

local SitAnimator = {}

----------------------------------------------------------------------
-- Réglages
----------------------------------------------------------------------

local PULL: { [string]: number } = { chair = 1.1, desk = 1.2, stool = 0.6 } -- (studs) chaise tirée
local PULL_TIME = 0.35 -- (s) la chaise recule
local SIT_TIME = 0.6 -- (s) descente sur le siège
local TUCK_DELAY = 0.5 -- (s) après l'assise, la chaise revient…
local TUCK_TIME = 0.55 -- …en tant de temps
local STAND_TIME = 0.4 -- (s) fondu de la pose assise vers la pose debout
local STAND_OUT = 0.3 -- (s) en se levant, la chaise recule…
local STAND_BACK = 0.55 -- …attend…
local STAND_IN = 0.45 -- …et se range
local APPROACH_MAX = 1.6 -- (s) au plus pour s'avancer devant la chaise
local SEAT_WAIT = 3 -- (s) le serveur n'a pas assis l'avatar : on range la chaise
local FIRST_IDLE = { 8, 15 } -- (s) première animation d'attente
local IDLE_GAP = { 5, 10 } -- (s) entre deux animations
local REMOTE_RADIUS = 60 -- (studs) autres joueurs animés…
local REMOTE_MAX = 6 -- …au plus
local SCAN_INTERVAL = 0.35 -- (s) recherche des autres joueurs assis / émotes
local PAUSE_SPEED = 4 -- (1/s) fondu vers / depuis la pause (bureau, émote)
local MOVE_THRESHOLD = 0.1
local TELEPORT = 10 -- (studs) au-delà : pas de glissé depuis la position debout

local KINDS: { [string]: boolean } = { chair = true, desk = true, stool = true, sofa = true, bed = true, bench = true, seat = true, ride = true }

-- Nature d'un meuble d'après son identifiant (premier mot trouvé)
local KIND_RULES: { { string } } = {
	{ "petbed", "sofa" },
	{ "hammock", "bed" },
	{ "bed", "bed" },
	{ "futon", "bed" },
	{ "sofa", "sofa" },
	{ "couch", "sofa" },
	{ "sectional", "sofa" },
	{ "loveseat", "sofa" },
	{ "divan", "sofa" },
	{ "throne", "sofa" },
	{ "armchair", "sofa" },
	{ "recliner", "sofa" },
	{ "eggchair", "sofa" },
	{ "rocking", "sofa" },
	{ "beanbag", "sofa" },
	{ "pouf", "sofa" },
	{ "cushion", "sofa" },
	{ "cinema", "sofa" },
	{ "bench", "bench" },
	{ "stool", "stool" },
	{ "setupdesk", "desk" },
	{ "rig", "seat" },
	{ "cockpit", "seat" },
	{ "chair", "chair" },
}

local IDENTITY = CFrame.identity
local UP = Vector3.new(0, 1, 0)
local rad = math.rad

----------------------------------------------------------------------
-- Petits outils
----------------------------------------------------------------------

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function now(): number
	return os.clock()
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and type(t) == "number" and t or os.clock()
end

-- Générateur pseudo-aléatoire DÉTERMINISTE (même suite sur tous les clients)
local function makeRng(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	for _ = 1, 3 do
		state = (state * 48271) % 2147483647
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

local function sameCF(a: CFrame, b: CFrame): boolean
	local c1 = { a:GetComponents() }
	local c2 = { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(c1[i] - c2[i]) > 1e-4 then
			return false
		end
	end
	return true
end

-- Manette de Roblox (PlayerModule) : vecteur de déplacement même assis
local controlsTried = false
local controls: any = nil
local function moveMagnitude(humanoid: Humanoid?): number
	local magnitude = 0
	if humanoid then
		local direction = humanoid.MoveDirection
		magnitude = typeof(direction) == "Vector3" and direction.Magnitude or 0
	end
	if not controlsTried then
		controlsTried = true
		pcall(function()
			local player = Players.LocalPlayer
			local scripts = player and player:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("PlayerModule")
			if module and module:IsA("ModuleScript") then
				controls = (require(module) :: any):GetControls()
			end
		end)
	end
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			magnitude = math.max(magnitude, vector.Magnitude)
		end
	end
	return magnitude
end

-- 🖥️ DeskMode (DESK98) : chargé paresseusement, en pcall
local deskTried = false
local deskModule: any = nil
local function desk(): any
	if not deskTried then
		deskTried = true
		pcall(function()
			local module = script.Parent:FindFirstChild("DeskMode")
			if module and module:IsA("ModuleScript") then
				local result = require(module) :: any
				if type(result) == "table" then
					deskModule = result
				end
			end
		end)
	end
	return deskModule
end

local function deskActive(): boolean
	local d = desk()
	if not d or type(d.IsActive) ~= "function" then
		return false
	end
	local ok, result = pcall(d.IsActive)
	return ok and result == true
end

----------------------------------------------------------------------
-- Nature du siège
----------------------------------------------------------------------

local function kindFromId(itemId: string): string?
	local id = string.lower(itemId)
	for _, rule in ipairs(KIND_RULES) do
		if string.find(id, rule[1], 1, true) then
			return rule[2]
		end
	end
	return nil
end

function SitAnimator.KindOf(model: Instance?, seat: Instance?): string
	for _, holder in ipairs({ seat, model }) do
		if holder then
			local tagged = holder:GetAttribute("SitKind")
			if type(tagged) == "string" and KINDS[tagged] then
				return tagged
			end
		end
	end
	if model then
		local id = model:GetAttribute("ItemId")
		local kind = type(id) == "string" and kindFromId(id) or nil
		if kind then
			return kind
		end
	end
	if seat and seat:IsA("BasePart") then
		if string.sub(seat.Name, 1, 9) == "TownSeat_" then
			return "seat"
		end
		-- siège d'un manège (FAIR98) : ancêtre nommé comme un manège, ou siège qui bouge
		local node: Instance? = seat.Parent
		for _ = 1, 6 do
			if not node or node == workspace then
				break
			end
			local tagged = node:GetAttribute("SitKind")
			if type(tagged) == "string" and KINDS[tagged] then
				return tagged
			end
			local name = string.lower(node.Name)
			if string.find(name, "ride", 1, true) or string.find(name, "fair", 1, true) or string.find(name, "carousel", 1, true)
				or string.find(name, "wheel", 1, true) or string.find(name, "manege", 1, true) or string.find(name, "swing", 1, true) then
				return "ride"
			end
			node = node.Parent
		end
		if not seat.Anchored then
			return "ride"
		end
		return "bench"
	end
	return "seat"
end

----------------------------------------------------------------------
-- 🪑 Chaises qui glissent (tirer / ranger)
----------------------------------------------------------------------

type Step = { To: number, Dur: number, Wait: number, Started: boolean? }
type Chair = {
	Key: BasePart, -- SeatPart du meuble
	Parts: { BasePart },
	Origins: { CFrame },
	Dir: Vector3, -- vers l'arrière de la chaise (unitaire, horizontal)
	Offset: number,
	From: number,
	Steps: { Step },
	StepT: number,
	Hold: boolean, -- gardée tirée (on attend l'assise)
	Seat: BasePart?, -- siège du serveur déplacé avec la chaise (localement)
	SeatOrigin: CFrame?,
}

local chairs: { [BasePart]: Chair } = {}

local function modelOfSeatPart(seatPart: BasePart): Model?
	local node: Instance? = seatPart.Parent
	for _ = 1, 4 do
		if not node then
			return nil
		end
		if node:IsA("Model") and node:GetAttribute("ItemId") ~= nil then
			return node
		end
		node = node.Parent
	end
	local parent = seatPart.Parent
	return (parent and parent:IsA("Model")) and parent or nil
end

-- Pièces de la chaise : tout le modèle, ou (bureau gamer) seulement celles
-- autour de l'assise (la chaise fait partie du modèle du bureau)
local function chairParts(model: Model, seatPart: BasePart, kind: string): { BasePart }
	local list = {}
	if kind ~= "desk" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end
	local seatCF = seatPart.CFrame
	local radius = math.max(seatPart.Size.X, seatPart.Size.Z) * 0.62 + 0.3
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Root" and d.Name ~= "Hitbox" and d.Name ~= "Screen" then
			local lp = seatCF:PointToObjectSpace(d.Position)
			local flat = math.sqrt(lp.X * lp.X + lp.Z * lp.Z)
			-- (plateau du bureau : large ; chaise : pièces courtes proches de l'assise)
			if flat <= radius and math.max(d.Size.X, d.Size.Z) <= radius * 2.4 and lp.Z > -radius * 0.9 then
				table.insert(list, d)
			end
		end
	end
	return list
end

local function dropChair(chair: Chair)
	if chairs[chair.Key] == chair then
		chairs[chair.Key] = nil
	end
end

-- Place la chaise à `offset` studs vers l'arrière ; false = quelqu'un d'autre
-- l'a bougée (on la laisse tranquille)
local function setOffset(chair: Chair, offset: number): boolean
	local parts, cframes = {}, {}
	local checked = false
	for i, part in ipairs(chair.Parts) do
		if part.Parent then
			local origin = chair.Origins[i]
			if not checked then
				checked = true
				local expected = origin.Position + chair.Dir * chair.Offset
				if (part.Position - expected).Magnitude > 0.08 then
					dropChair(chair)
					return false
				end
			end
			table.insert(parts, part)
			table.insert(cframes, origin + chair.Dir * offset)
		end
	end
	if #parts == 0 then
		dropChair(chair)
		return false
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, part in ipairs(parts) do
			part.CFrame = cframes[i]
		end
	end
	local seat = chair.Seat
	local seatOrigin = chair.SeatOrigin
	if seat and seatOrigin then
		if seat.Parent then
			pcall(function()
				seat.CFrame = seatOrigin + chair.Dir * offset
			end)
		else
			chair.Seat = nil
			chair.SeatOrigin = nil
		end
	end
	chair.Offset = offset
	return true
end

local function chairFor(model: Model?, seatPart: BasePart?, kind: string): Chair?
	if not model or not seatPart or not PULL[kind] or not seatPart.Parent then
		return nil
	end
	local existing = chairs[seatPart]
	if existing then
		return existing
	end
	local look = seatPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		return nil
	end
	local parts = chairParts(model, seatPart, kind)
	if #parts == 0 then
		return nil
	end
	local origins = {}
	for i, part in ipairs(parts) do
		origins[i] = part.CFrame
	end
	local chair: Chair = {
		Key = seatPart,
		Parts = parts,
		Origins = origins,
		Dir = -flat.Unit,
		Offset = 0,
		From = 0,
		Steps = {},
		StepT = 0,
		Hold = false,
		Seat = nil,
		SeatOrigin = nil,
	}
	chairs[seatPart] = chair
	return chair
end

local function chairTo(chair: Chair, to: number, duration: number, wait: number?)
	table.insert(chair.Steps, { To = to, Dur = math.max(0.05, duration), Wait = wait or 0 })
end

-- Place libre derrière la chaise (mur, autre meuble) : on ne recule pas dedans
local function freePull(chair: Chair, seatPart: BasePart, wanted: number, ignore: { Instance }): number
	local ok, result = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignore
		local back = math.max(seatPart.Size.Z, seatPart.Size.X) * 0.5 + 0.35
		local origin = seatPart.Position + UP * 1.2
		local hit = workspace:Raycast(origin, chair.Dir * (back + wanted + 0.3), params)
		if hit then
			return math.clamp((hit.Position - origin).Magnitude - back - 0.3, 0, wanted)
		end
		return wanted
	end)
	return ok and type(result) == "number" and result or wanted
end

local function stepChairs(dt: number)
	for _, chair in pairs(chairs) do
		local step = chair.Steps[1]
		if not step then
			if chair.Offset == 0 and not chair.Hold then
				dropChair(chair)
			end
		else
			chair.StepT += dt
			if chair.StepT >= step.Wait then
				if not step.Started then
					step.Started = true
					chair.From = chair.Offset
				end
				local a = clamp01((chair.StepT - step.Wait) / step.Dur)
				local value = chair.From + (step.To - chair.From) * smooth(a)
				if a >= 1 then
					value = step.To
				end
				if setOffset(chair, value) and a >= 1 then
					table.remove(chair.Steps, 1)
					chair.StepT = 0
				end
			end
		end
	end
end

local function restoreChairs()
	for _, chair in pairs(chairs) do
		chair.Hold = false
		table.clear(chair.Steps)
		if chair.Offset ~= 0 then
			pcall(setOffset, chair, 0)
		end
		dropChair(chair)
	end
	table.clear(chairs)
end

-- Meuble (modèle + SeatPart) sous un siège du serveur, dans les maisons construites ici
local function furnitureAt(position: Vector3): (Model?, BasePart?)
	local ok, parts = pcall(function()
		local params = OverlapParams.new()
		local houses = workspace:FindFirstChild("TownHouses")
		if houses then
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { houses }
		end
		return workspace:GetPartBoundsInRadius(position, 1.6, params)
	end)
	if not ok or type(parts) ~= "table" then
		return nil, nil
	end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, part in ipairs(parts) do
		if part.Name == "SeatPart" then
			local distance = (part.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	if not best then
		return nil, nil
	end
	return modelOfSeatPart(best), best
end

----------------------------------------------------------------------
-- 🦴 Squelette (R15 / R6)
----------------------------------------------------------------------

local R15_JOINTS: { [string]: { string } } = {
	Root = { "LowerTorso", "Root" },
	Waist = { "UpperTorso", "Waist" },
	Neck = { "Head", "Neck" },
	RShoulder = { "RightUpperArm", "RightShoulder" },
	RElbow = { "RightLowerArm", "RightElbow" },
	RWrist = { "RightHand", "RightWrist" },
	LShoulder = { "LeftUpperArm", "LeftShoulder" },
	LElbow = { "LeftLowerArm", "LeftElbow" },
	LWrist = { "LeftHand", "LeftWrist" },
	RHip = { "RightUpperLeg", "RightHip" },
	RKnee = { "RightLowerLeg", "RightKnee" },
	RAnkle = { "RightFoot", "RightAnkle" },
	LHip = { "LeftUpperLeg", "LeftHip" },
	LKnee = { "LeftLowerLeg", "LeftKnee" },
	LAnkle = { "LeftFoot", "LeftAnkle" },
}
local R6_JOINTS: { [string]: { string } } = {
	Root = { "HumanoidRootPart", "RootJoint" },
	Neck = { "Torso", "Neck" },
	RShoulder = { "Torso", "Right Shoulder" },
	LShoulder = { "Torso", "Left Shoulder" },
	RHip = { "Torso", "Right Hip" },
	LHip = { "Torso", "Left Hip" },
}

type Joint = {
	Motor: Motor6D,
	C0: CFrame,
	C0r: CFrame,
	C0rInv: CFrame,
	Base: CFrame?, -- dernière pose de l'Animator
	Written: CFrame?, -- dernière valeur écrite par nous
}

type Limb = { P: Vector3, L1: number, L2: number }

type Rig = {
	R6: boolean,
	Joints: { [string]: Joint },
	Root: BasePart,
	Head: BasePart?,
	Hand: BasePart?, -- main droite (téléphone)
	Scale: number,
	Arms: { [string]: Limb },
	Legs: { [string]: Limb },
	Torso: BasePart?,
}

local function limbOf(joints: { [string]: Joint }, a: string, b: string, c: string?, r6: boolean, scale: number): Limb?
	local j1 = joints[a]
	if not j1 then
		return nil
	end
	local l1, l2 = 1.6 * scale, 0
	if not r6 and c then
		local j2, j3 = joints[b], joints[c]
		if not j2 or not j3 then
			return nil
		end
		l1 = (j1.Motor.C1.Position - j2.C0.Position).Magnitude
		l2 = (j2.Motor.C1.Position - j3.C0.Position).Magnitude
		if l1 < 0.1 or l2 < 0.1 then
			return nil
		end
	end
	return { P = j1.C0.Position, L1 = l1, L2 = l2 }
end

local function rigOf(character: Model, humanoid: Humanoid): Rig?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local joints: { [string]: Joint } = {}
	for key, spec in pairs(r6 and R6_JOINTS or R15_JOINTS) do
		local part = character:FindFirstChild(spec[1])
		local motor = part and part:FindFirstChild(spec[2])
		if motor and motor:IsA("Motor6D") then
			local c0 = motor.C0
			joints[key] = { Motor = motor, C0 = c0, C0r = c0.Rotation, C0rInv = c0.Rotation:Inverse(), Base = nil, Written = nil }
		end
	end
	if not joints.Root then
		return nil
	end
	local torso = character:FindFirstChild(r6 and "Torso" or "UpperTorso")
	local scale = 1
	if torso and torso:IsA("BasePart") then
		scale = math.clamp(torso.Size.Y / (r6 and 2 or 1.6), 0.5, 2)
	end
	local head = character:FindFirstChild("Head")
	local hand = character:FindFirstChild(r6 and "Right Arm" or "RightHand")
	local rig: Rig = {
		R6 = r6,
		Joints = joints,
		Root = root,
		Head = (head and head:IsA("BasePart")) and head or nil,
		Hand = (hand and hand:IsA("BasePart")) and hand or nil,
		Scale = scale,
		Arms = {},
		Legs = {},
		Torso = (torso and torso:IsA("BasePart")) and torso or nil,
	}
	rig.Arms.R = limbOf(joints, "RShoulder", "RElbow", "RWrist", r6, scale) :: any
	rig.Arms.L = limbOf(joints, "LShoulder", "LElbow", "LWrist", r6, scale) :: any
	rig.Legs.R = limbOf(joints, "RHip", "RKnee", "RAnkle", r6, scale) :: any
	rig.Legs.L = limbOf(joints, "LHip", "LKnee", "LAnkle", r6, scale) :: any
	return rig
end

----------------------------------------------------------------------
-- Poses : couches appliquées sur la pose de l'Animator
--   Abs(key, R, w) : orientation du membre (repère du parent) ; Add : rotation
--   ajoutée autour de l'articulation (repère du parent) ; w = poids 0..1
----------------------------------------------------------------------

type Pose = { Rig: Rig, Work: { [string]: CFrame } }

local function abs(pose: Pose, key: string, r: CFrame, w: number)
	local joint = pose.Rig.Joints[key]
	if not joint or w <= 0.001 then
		return
	end
	local current = pose.Work[key] or IDENTITY
	pose.Work[key] = current:Lerp(joint.C0rInv * r * joint.C0r, math.min(w, 1))
end

local function add(pose: Pose, key: string, r: CFrame, w: number)
	if w <= 0.001 then
		return
	end
	local joint = pose.Rig.Joints[key]
	if not joint then
		-- R6 : pas de "Waist" -> le buste entier tourne, les jambes restent
		if key == "Waist" and pose.Rig.R6 then
			add(pose, "Root", r, w)
			local back = r:Inverse()
			add(pose, "RHip", back, w)
			add(pose, "LHip", back, w)
		end
		return
	end
	local weighted = w >= 1 and r or IDENTITY:Lerp(r, w)
	local current = pose.Work[key] or IDENTITY
	pose.Work[key] = (joint.C0rInv * weighted * joint.C0r) * current
end

-- Orientation d'un segment : -Y le long de `dir`, "devant" (-Z) vers `front`
local function frameAlong(dir: Vector3, front: Vector3): CFrame
	local y = -dir.Unit
	local z = -(front - dir.Unit * front:Dot(dir.Unit))
	if z.Magnitude < 1e-3 then
		z = Vector3.new(0, 0, 1)
		z = z - dir.Unit * z:Dot(dir.Unit)
		if z.Magnitude < 1e-3 then
			z = Vector3.new(1, 0, 0)
		end
	end
	z = z.Unit
	local x = y:Cross(z)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

-- IK à deux segments (bras / jambe R15) dans le repère du parent : la main
-- (poignet) ou la cheville vise `target`, le coude / genou part vers `pole`.
-- bend = 1 (bras : le coude plie vers -Z) ou -1 (jambe : le genou plie vers +Z)
local function ik2(limb: Limb, target: Vector3, pole: Vector3, bend: number): (CFrame, number)
	local d = target - limb.P
	local dn = d.Magnitude > 1e-4 and d.Unit or Vector3.new(0, -1, 0)
	local l1, l2 = limb.L1, limb.L2
	local dist = math.clamp(d.Magnitude, math.abs(l1 - l2) + 0.05, l1 + l2 - 0.02)
	local cosA = math.clamp((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)
	local a = math.acos(cosA)
	local perp = pole - dn * pole:Dot(dn)
	if perp.Magnitude < 1e-3 then
		perp = Vector3.new(0, 0, -1) - dn * (-dn.Z)
		if perp.Magnitude < 1e-3 then
			perp = Vector3.new(1, 0, 0)
		end
	end
	perp = perp.Unit
	local u = dn * math.cos(a) + perp * math.sin(a)
	local elbow = limb.P + u * l1
	local f = limb.P + dn * dist - elbow
	f = f.Magnitude > 1e-4 and f.Unit or u
	local flex = math.acos(math.clamp(u:Dot(f), -1, 1))
	local b = f - u * f:Dot(u)
	if b.Magnitude < 1e-3 then
		b = -perp
	else
		b = b.Unit
	end
	local y = -u
	local z = bend > 0 and -b or b
	local x = y:Cross(z)
	return CFrame.fromMatrix(Vector3.zero, x, y, z), flex
end

-- Bras : la main vise `target` (repère du buste, depuis son centre, studs d'un
-- avatar standard, mis à l'échelle), coude vers `pole`
local function reach(pose: Pose, side: string, target: Vector3, pole: Vector3, w: number)
	local rig = pose.Rig
	local limb = rig.Arms[side]
	if not limb or w <= 0.001 then
		return
	end
	local shoulder = side == "R" and "RShoulder" or "LShoulder"
	local t = target * rig.Scale
	if rig.R6 then
		abs(pose, shoulder, frameAlong(t - limb.P, Vector3.new(0, 0, -1)), w)
		return
	end
	local r, flex = ik2(limb, t, pole, 1)
	abs(pose, shoulder, r, w)
	abs(pose, side == "R" and "RElbow" or "LElbow", CFrame.Angles(flex, 0, 0), w)
	abs(pose, side == "R" and "RWrist" or "LWrist", IDENTITY, w)
end

-- Jambe : la cheville vise hanche + `offset` (repère du bassin), genou vers `pole`
local function stride(pose: Pose, side: string, offset: Vector3, pole: Vector3, w: number)
	local rig = pose.Rig
	local limb = rig.Legs[side]
	if not limb or w <= 0.001 then
		return
	end
	local hip = side == "R" and "RHip" or "LHip"
	local t = limb.P + offset * rig.Scale
	if rig.R6 then
		abs(pose, hip, frameAlong(t - limb.P, Vector3.new(0, 0, -1)), w)
		return
	end
	local r, flex = ik2(limb, t, pole, -1)
	abs(pose, hip, r, w)
	abs(pose, side == "R" and "RKnee" or "LKnee", CFrame.Angles(-flex, 0, 0), w)
end

----------------------------------------------------------------------
-- Animations d'attente
----------------------------------------------------------------------

type Anim = any
type Clip = {
	Name: string,
	Duration: number,
	FadeIn: number,
	FadeOut: number,
	Apply: (pose: Pose, t: number, d: number, w: number, anim: Anim) -> (),
}

local function wave(t: number, period: number): number
	return math.sin(2 * math.pi * t / period)
end

local CLIPS: { [string]: Clip } = {}

-- 👀 regarder autour de soi
CLIPS.Look = {
	Name = "Look",
	Duration = 5,
	FadeIn = 0.5,
	FadeOut = 0.6,
	Apply = function(pose, t, d, w)
		local u = t / d
		local yaw = 52 * math.sin(2 * math.pi * u) * smooth(u * 4) * smooth((1 - u) * 4)
		local pitch = 6 * math.sin(4 * math.pi * u)
		add(pose, "Neck", CFrame.Angles(rad(pitch), rad(yaw), 0), w)
		add(pose, "Waist", CFrame.Angles(0, rad(yaw * 0.28), 0), w)
	end,
}

-- 🙆 s'étirer (bras au-dessus de la tête, dos cambré, bâillement)
CLIPS.Stretch = {
	Name = "Stretch",
	Duration = 4.4,
	FadeIn = 0.9,
	FadeOut = 1.1,
	Apply = function(pose, t, _d, w)
		local sway = wave(t, 2.2)
		reach(pose, "R", Vector3.new(0.55 + 0.05 * sway, 3.05, 0.05), Vector3.new(1, 0.2, 0.6), w)
		reach(pose, "L", Vector3.new(-0.55 + 0.05 * sway, 3.05, 0.05), Vector3.new(-1, 0.2, 0.6), w)
		add(pose, "Waist", CFrame.Angles(rad(9), rad(4 * sway), 0), w)
		add(pose, "Neck", CFrame.Angles(rad(20), 0, 0), w)
	end,
}

-- 😌 se pencher en arrière, mains derrière la tête
CLIPS.Lean = {
	Name = "Lean",
	Duration = 7,
	FadeIn = 0.9,
	FadeOut = 0.9,
	Apply = function(pose, t, _d, w, anim)
		local back = anim.Kind == "sofa" and 20 or 13
		add(pose, "Waist", CFrame.Angles(rad(back + 1.5 * wave(t, 3.5)), 0, 0), w)
		add(pose, "Neck", CFrame.Angles(rad(-back * 0.45), rad(6 * wave(t, 5)), 0), w)
		reach(pose, "R", Vector3.new(0.32, 1.35, 0.55), Vector3.new(1, 0.1, -0.2), w)
		reach(pose, "L", Vector3.new(-0.32, 1.35, 0.55), Vector3.new(-1, 0.1, -0.2), w)
	end,
}

-- 🦵 croiser les jambes (la droite sur la gauche)
CLIPS.Cross = {
	Name = "Cross",
	Duration = 8,
	FadeIn = 0.8,
	FadeOut = 0.8,
	Apply = function(pose, t, _d, w)
		local tap = 0.06 * wave(t, 1.3)
		stride(pose, "R", Vector3.new(-0.62, -0.72 + tap, -1.55), Vector3.new(-0.4, 1, -1), w)
		add(pose, "Waist", CFrame.Angles(rad(3), rad(-5), 0), w)
		add(pose, "Neck", CFrame.Angles(0, rad(4), 0), w)
		-- mains posées sur le genou
		reach(pose, "R", Vector3.new(0.05, -1.05, -1.2), Vector3.new(1, -0.4, 0.3), w * 0.8)
		reach(pose, "L", Vector3.new(-0.2, -1.1, -1.15), Vector3.new(-1, -0.4, 0.3), w * 0.8)
	end,
}

-- 🦶 balancer les pieds
CLIPS.Swing = {
	Name = "Swing",
	Duration = 5,
	FadeIn = 0.5,
	FadeOut = 0.6,
	Apply = function(pose, t, _d, w, anim)
		local s = wave(t, 1.1)
		if anim.Rig.R6 then
			add(pose, "RHip", CFrame.Angles(rad(12 * s), 0, 0), w)
			add(pose, "LHip", CFrame.Angles(rad(-12 * s), 0, 0), w)
		else
			add(pose, "RKnee", CFrame.Angles(rad(24 * s), 0, 0), w)
			add(pose, "LKnee", CFrame.Angles(rad(-24 * s), 0, 0), w)
			add(pose, "RAnkle", CFrame.Angles(rad(10 * s), 0, 0), w)
			add(pose, "LAnkle", CFrame.Angles(rad(-10 * s), 0, 0), w)
		end
		add(pose, "Neck", CFrame.Angles(rad(-4), rad(8 * wave(t, 2.6)), 0), w)
	end,
}

-- 📱 regarder son téléphone (petit téléphone dans la main droite)
CLIPS.Phone = {
	Name = "Phone",
	Duration = 8,
	FadeIn = 0.7,
	FadeOut = 0.7,
	Apply = function(pose, t, _d, w, anim)
		local tap = 0.03 * math.max(0, wave(t, 0.45))
		reach(pose, "R", Vector3.new(0.28, -0.05 + tap, -0.85), Vector3.new(0.6, -1, 0.5), w)
		reach(pose, "L", Vector3.new(-0.12, -0.15, -0.8), Vector3.new(-0.6, -1, 0.5), w)
		add(pose, "Neck", CFrame.Angles(rad(-26 + 3 * wave(t, 3.1)), rad(4), 0), w)
		add(pose, "Waist", CFrame.Angles(rad(-4), 0, 0), w)
		anim.WantPhone = w > 0.25
	end,
}

-- 😪 piquer du nez (canapé) : la tête tombe doucement… et se relève d'un coup
CLIPS.Doze = {
	Name = "Doze",
	Duration = 7,
	FadeIn = 0.8,
	FadeOut = 0.4,
	Apply = function(pose, t, d, w, anim)
		local drop = smooth(t / (d - 0.9)) * (1 - smooth((t - (d - 0.9)) / 0.25))
		add(pose, "Neck", CFrame.Angles(rad(-32 * drop), rad(10 * drop), 0), w)
		add(pose, "Waist", CFrame.Angles(rad(6 * drop), 0, 0), w)
		anim.WantZzz = drop > 0.5 and w > 0.5
	end,
}

-- 😴 dormir (lit) : allongé sur le dos, mains sur le ventre, respiration, 💤
CLIPS.Sleep = {
	Name = "Sleep",
	Duration = 24,
	FadeIn = 1.4,
	FadeOut = 1.4,
	Apply = function(pose, t, _d, w, anim)
		local bed = anim.Bed
		local drop = bed and bed.Drop or 0.6
		-- (repère tourné du lit ; la pose de base a déjà tourné et reculé le corps)
		local yaw = CFrame.Angles(0, rad(bed and bed.Yaw or 0), 0)
		local sitShift = CFrame.new(0, 0, bed and bed.SitShift or 0)
		add(pose, "Root", yaw * CFrame.new(0, -drop, bed and bed.Shift or 0) * CFrame.Angles(rad(86), 0, 0) * sitShift:Inverse() * yaw:Inverse(), w)
		abs(pose, "RHip", CFrame.Angles(rad(4), 0, rad(3)), w)
		abs(pose, "LHip", CFrame.Angles(rad(4), 0, rad(-3)), w)
		abs(pose, "RKnee", CFrame.Angles(rad(-5), 0, 0), w)
		abs(pose, "LKnee", CFrame.Angles(rad(-5), 0, 0), w)
		-- bras le long du corps, posés sur le matelas
		local down = anim.Rig.R6 and -1.7 or -0.85
		reach(pose, "R", Vector3.new(1.25, down, -0.12), Vector3.new(1, 0, 1), w)
		reach(pose, "L", Vector3.new(-1.25, down, -0.12), Vector3.new(-1, 0, 1), w)
		add(pose, "Neck", CFrame.Angles(rad(-10), rad(18), 0), w)
		add(pose, "Waist", CFrame.Angles(rad(1.8 * wave(t, 4.2)), 0, 0), w)
		anim.WantZzz = w > 0.6
	end,
}

-- 🙌 bras en l'air (manège)
CLIPS.Hands = {
	Name = "Hands",
	Duration = 3.4,
	FadeIn = 0.4,
	FadeOut = 0.6,
	Apply = function(pose, t, _d, w)
		local s = wave(t, 0.8)
		reach(pose, "R", Vector3.new(1.2 + 0.1 * s, 2.9, -0.3), Vector3.new(1, 0, 0.5), w)
		reach(pose, "L", Vector3.new(-1.2 - 0.1 * s, 2.9, -0.3), Vector3.new(-1, 0, 0.5), w)
		add(pose, "Neck", CFrame.Angles(rad(12), rad(10 * s), 0), w)
	end,
}

-- Programme par nature de siège : { clip, poids }
local PROGRAM: { [string]: { { any } } } = {
	-- (chaise à une table : pas de jambes croisées, le genou passerait dans le plateau)
	chair = { { "Look", 3 }, { "Stretch", 2 }, { "Phone", 3 }, { "Lean", 2 }, { "Swing", 1 } },
	desk = { { "Look", 2 }, { "Stretch", 3 }, { "Lean", 2 }, { "Phone", 1 } },
	stool = { { "Look", 3 }, { "Swing", 3 }, { "Phone", 2 }, { "Stretch", 1 } },
	sofa = { { "Lean", 3 }, { "Cross", 2 }, { "Phone", 3 }, { "Stretch", 2 }, { "Look", 2 }, { "Doze", 2 } },
	bench = { { "Look", 3 }, { "Cross", 2 }, { "Stretch", 2 }, { "Swing", 1 }, { "Phone", 2 }, { "Lean", 1 } },
	bed = { { "Sleep", 5 }, { "Stretch", 2 }, { "Phone", 2 }, { "Look", 1 } },
	ride = { { "Hands", 3 }, { "Look", 2 }, { "Swing", 2 } },
	seat = { { "Look", 3 }, { "Stretch", 2 }, { "Phone", 2 }, { "Cross", 1 } },
}

local function pickClip(kind: string, rng: () -> number, last: string?): Clip
	local list = PROGRAM[kind] or PROGRAM.seat
	local function draw(): string
		local total = 0
		for _, entry in ipairs(list) do
			total += entry[2]
		end
		local x = rng() * total
		for _, entry in ipairs(list) do
			x -= entry[2]
			if x <= 0 then
				return entry[1]
			end
		end
		return list[#list][1]
	end
	local name = draw()
	if name == last and #list > 1 then
		name = draw()
	end
	return CLIPS[name] or CLIPS.Look
end

----------------------------------------------------------------------
-- Personnages animés
----------------------------------------------------------------------

type Sched = { Rng: () -> number, Next: number, Clip: Clip?, Start: number, Stop: number, Last: string?, Kind: string }

local anims: { [Model]: Anim } = {}
local started = false
local failed = false
local connections: { RBXScriptConnection } = {}
local deskConnection: RBXScriptConnection? = nil
local propsFolder: Folder? = nil
local pending: any = nil -- approche en cours (joueur local)
local lastStand: CFrame? = nil -- HRP du joueur local debout (image précédente)
local lastStandT: { [string]: CFrame } = {}
local scanClock = 0

local function newSched(seed: number, from: number, kind: string): Sched
	local rng = makeRng(seed)
	return { Rng = rng, Next = from + FIRST_IDLE[1] + rng() * (FIRST_IDLE[2] - FIRST_IDLE[1]), Clip = nil, Start = 0, Stop = 0, Last = nil, Kind = kind }
end

local function advanceSched(sched: Sched, elapsed: number)
	for _ = 1, 400 do
		local clip = sched.Clip
		if clip and elapsed >= sched.Stop then
			sched.Last = clip.Name
			sched.Clip = nil
			sched.Next = sched.Stop + IDLE_GAP[1] + sched.Rng() * (IDLE_GAP[2] - IDLE_GAP[1])
		elseif not clip and elapsed >= sched.Next then
			local picked = pickClip(sched.Kind, sched.Rng, sched.Last)
			sched.Clip = picked
			sched.Start = sched.Next
			sched.Stop = sched.Next + picked.Duration
		else
			return
		end
	end
end

local function propsParent(): Instance
	local folder = propsFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "SitAnimatorProps"
	created.Parent = workspace
	propsFolder = created
	return created
end

local PHONE_TEXTS = { "❤️ New like!", "💬 New message", "📈 Dopamine +12%", "🎮 Your turn!" }

local function makePhone(anim: Anim): BasePart
	local phone = Instance.new("Part")
	phone.Name = "SitPhone"
	phone.Size = Vector3.new(0.34, 0.62, 0.06)
	phone.Color = Color3.fromRGB(34, 32, 44)
	phone.Material = Enum.Material.SmoothPlastic
	phone.Anchored = true
	phone.CanCollide = false
	phone.CanTouch = false
	phone.CanQuery = false
	phone.CastShadow = false
	local screen = Instance.new("SurfaceGui")
	screen.Name = "Screen"
	screen.Face = Enum.NormalId.Front
	screen.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	screen.PixelsPerStud = 160
	screen.LightInfluence = 0.2
	screen.Brightness = 1
	screen.MaxDistance = 40
	screen.Parent = phone
	local glass = Instance.new("Frame")
	glass.Size = UDim2.new(1, -6, 1, -8)
	glass.Position = UDim2.fromOffset(3, 4)
	glass.BackgroundColor3 = Color3.fromRGB(255, 170, 210)
	glass.BorderSizePixel = 0
	glass.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = glass
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -6, 0.5, 0)
	label.Position = UDim2.new(0, 3, 0.25, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(60, 30, 70)
	label.Text = Locale.T(PHONE_TEXTS[(anim.PhoneN or 0) % #PHONE_TEXTS + 1])
	label.Parent = glass
	phone.Parent = propsParent()
	return phone
end

local function makeZzz(anim: Anim): BillboardGui?
	local head = anim.Rig.Head
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SitZzz"
	gui.Adornee = head
	gui.Size = UDim2.fromScale(1.6, 1.6)
	gui.StudsOffset = Vector3.new(0.9, 1.3, 0)
	gui.MaxDistance = 45
	gui.LightInfluence = 0
	gui.Brightness = 1
	local label = Instance.new("TextLabel")
	label.Name = "Z"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = "💤"
	label.Parent = gui
	gui.Parent = propsParent()
	return gui
end

local function clearProps(anim: Anim)
	if anim.Phone then
		pcall(anim.Phone.Destroy, anim.Phone)
		anim.Phone = nil
	end
	if anim.Zzz then
		pcall(anim.Zzz.Destroy, anim.Zzz)
		anim.Zzz = nil
	end
end

-- Lit : on s'y allonge dans le sens de la longueur, tête vers la tête de lit
local function bedInfo(anim: Anim)
	local seat: BasePart = anim.Seat
	local model: Model? = anim.Model
	local rig: Rig = anim.Rig
	-- Yaw : lacet du corps ; Drop : descente du bassin couché ; SitShift / Shift :
	-- recul du bassin (vers la tête de lit) assis / couché, dans le repère tourné
	local info = { Yaw = 0, Drop = 0.6, SitShift = 0, Shift = 0 }
	-- bassin -> centre de la tête, pose de repos (chaîne Root, Waist, Neck du rig)
	local headDist = 0
	for _, key in ipairs({ "Root", "Waist", "Neck" }) do
		local joint = rig.Joints[key]
		if joint then
			headDist += (key ~= "Root" and math.abs(joint.C0.Y) or 0) + math.abs(joint.Motor.C1.Y)
		end
	end
	headDist = math.clamp(headDist, 1, 5)
	-- hauteur : le dos à ~0,5 stud au-dessus du matelas
	pcall(function()
		local root = rig.Joints.Root
		local pivot = (rig.Root.CFrame * root.C0).Position
		local top = (seat.CFrame * CFrame.new(0, seat.Size.Y / 2, 0)).Position
		info.Drop = math.clamp(pivot.Y - top.Y - 0.55 * rig.Scale, 0, 2.5)
	end)
	if model then
		pcall(function()
			local frame = seat.CFrame
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			local highL, highR, highF, highB = 0, 0, 0, 0
			local parts = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local rel = frame:ToObjectSpace(d.CFrame)
					local p = rel.Position
					minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
					minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
					table.insert(parts, { p, d.Size, rel })
				end
			end
			for _, entry in ipairs(parts) do
				local p: Vector3, size: Vector3 = entry[1], entry[2]
				local top = p.Y + size.Y / 2
				if p.X < minX + (maxX - minX) * 0.25 then
					highL = math.max(highL, top)
				elseif p.X > maxX - (maxX - minX) * 0.25 then
					highR = math.max(highR, top)
				end
				if p.Z < minZ + (maxZ - minZ) * 0.25 then
					highF = math.max(highF, top)
				elseif p.Z > maxZ - (maxZ - minZ) * 0.25 then
					highB = math.max(highB, top)
				end
			end
			if (maxX - minX) > (maxZ - minZ) * 1.15 then
				-- lit "de profil" : tête du côté le plus haut (tête de lit)
				info.Yaw = highR >= highL and 90 or -90
			else
				info.Yaw = highF > highB + 0.3 and 180 or 0
			end
			-- bord du lit côté tête : assis, le dos contre la tête de lit ;
			-- couché, la tête sur l'oreiller (jamais dans la tête de lit)
			local h = CFrame.Angles(0, rad(info.Yaw), 0):VectorToWorldSpace(Vector3.new(0, 0, 1))
			local edge = -math.huge
			for _, entry in ipairs(parts) do
				local p: Vector3, size: Vector3, rel: CFrame = entry[1], entry[2], entry[3]
				-- (demi-épaisseur de la pièce tournée le long de h)
				local half = math.abs(rel.RightVector:Dot(h)) * size.X / 2 + math.abs(rel.UpVector:Dot(h)) * size.Y / 2
					+ math.abs(rel.LookVector:Dot(h)) * size.Z / 2
				edge = math.max(edge, p:Dot(h) + half)
			end
			if edge > -math.huge then
				info.SitShift = math.clamp(edge - 0.5 - 0.65 * rig.Scale, 0, 3)
				info.Shift = math.clamp(edge - 0.5 - 0.7 * rig.Scale - headDist, -4, 3)
			end
		end)
	end
	return info
end

-- Pose de base selon le siège (lit : assis dans le lit, jambes allongées ;
-- bureau vu des autres : mains sur le clavier)
local function applyKindBase(pose: Pose, anim: Anim, w: number, t: number)
	if anim.Kind == "bed" then
		local bed = anim.Bed
		if bed then
			add(pose, "Root", CFrame.Angles(0, rad(bed.Yaw), 0) * CFrame.new(0, 0, bed.SitShift), w)
		end
		abs(pose, "RHip", CFrame.Angles(rad(86), 0, rad(2)), w)
		abs(pose, "LHip", CFrame.Angles(rad(86), 0, rad(-2)), w)
		abs(pose, "RKnee", CFrame.Angles(rad(-6), 0, 0), w)
		abs(pose, "LKnee", CFrame.Angles(rad(-6), 0, 0), w)
		abs(pose, "RAnkle", CFrame.Angles(rad(-20), 0, 0), w)
		abs(pose, "LAnkle", CFrame.Angles(rad(-20), 0, 0), w)
		reach(pose, "R", Vector3.new(0.75, -1.25, -0.75), Vector3.new(1, 0, 0.3), w * 0.9)
		reach(pose, "L", Vector3.new(-0.75, -1.25, -0.75), Vector3.new(-1, 0, 0.3), w * 0.9)
	elseif anim.Kind == "desk" and not anim.Local then
		local k = 0.04 * wave(t, 0.23)
		reach(pose, "R", Vector3.new(0.45, -0.55 + k, -1.45), Vector3.new(1, -1, 0.3), w)
		reach(pose, "L", Vector3.new(-0.45, -0.55 - k, -1.45), Vector3.new(-1, -1, 0.3), w)
		add(pose, "Neck", CFrame.Angles(rad(-6), 0, 0), w)
		add(pose, "Waist", CFrame.Angles(rad(-5), 0, 0), w)
	end
end

local function restoreJoints(anim: Anim)
	local rig: Rig? = anim.Rig
	if not rig then
		return
	end
	for _, joint in pairs(rig.Joints) do
		if joint.Written and joint.Motor.Parent then
			pcall(function()
				joint.Motor.Transform = joint.Base or IDENTITY
			end)
		end
		joint.Written = nil
		joint.Base = nil
	end
end

local function removeAnim(anim: Anim)
	restoreJoints(anim)
	clearProps(anim)
	if anims[anim.Character] == anim then
		anims[anim.Character] = nil
	end
end

local function seedOf(userId: number, seat: Instance): (number, number)
	local at = seat:GetAttribute("SitAt")
	local sitAt = type(at) == "number" and at or serverNow()
	return userId * 7919 + math.floor(sitAt * 10) % 1000003, sitAt
end

-- Le personnage vient de s'asseoir sur `seat`
local function beginSit(character: Model, humanoid: Humanoid, seat: BasePart, isLocal: boolean, player: Player?)
	local old = anims[character]
	if old then
		removeAnim(old)
	end
	local rig = rigOf(character, humanoid)
	if not rig then
		return
	end
	local info = nil
	if isLocal and pending and (pending.CF.Position - seat.Position).Magnitude < 2.5 then
		info = pending
	end
	local model: Model? = info and info.Model or nil
	local seatPart: BasePart? = info and info.SeatPart or nil
	if not model and string.sub(seat.Name, 1, 9) == "TownSeat_" then
		model, seatPart = furnitureAt(seat.Position)
	end
	local kind = info and info.Kind or SitAnimator.KindOf(model, seat)
	if not KINDS[kind] then
		kind = "seat"
	end
	local userId = player and player.UserId or 0
	local seed, sitAt = seedOf(userId, seat)
	local anim: Anim = {
		Character = character,
		Humanoid = humanoid,
		Rig = rig,
		Seat = seat,
		Model = model,
		SeatPart = seatPart,
		Kind = kind,
		Local = isLocal,
		Player = player,
		Phase = "sit",
		PhaseT = 0,
		Start = {},
		From = {},
		SitAt = sitAt,
		Seed = seed,
		Resets = 0,
		Pause = 1,
		PauseTarget = 1,
		TrackClock = 0,
		PhoneN = seed % 4,
		WantPhone = false,
		WantZzz = false,
	}
	-- (tirage depuis l'assise : un client qui arrive plus tard retombe sur le même programme)
	anim.Sched = newSched(seed, 0, kind)
	if kind == "bed" then
		anim.Bed = bedInfo(anim)
	end
	-- pose de départ : celle de l'image précédente (debout)
	for key, joint in pairs(rig.Joints) do
		anim.Start[key] = (isLocal and lastStandT[key]) or joint.Motor.Transform
	end
	-- glissé depuis là où l'on était debout (joueur local)
	local standCF = isLocal and lastStand or nil
	if standCF and (standCF.Position - rig.Root.Position).Magnitude < TELEPORT then
		anim.StandCF = standCF
	end
	anims[character] = anim
	-- 🪑 chaise : glisse vers la table avec l'avatar (siège du serveur déplacé localement)
	local chair: Chair? = info and info.Chair or nil
	if not chair and seatPart and PULL[kind] and model then
		chair = chairFor(model, seatPart, kind)
		if chair and chair.Offset == 0 and #chair.Steps == 0 then
			local pull = freePull(chair, seatPart, PULL[kind], { model, character })
			if pull > 0.15 then
				setOffset(chair, pull)
			end
		end
	end
	if chair and chairs[chair.Key] == chair then
		chair.Hold = false
		table.clear(chair.Steps)
		chair.Seat = seat
		chair.SeatOrigin = seat.CFrame
		if chair.Offset > 0 then
			setOffset(chair, chair.Offset)
			chairTo(chair, 0, TUCK_TIME, TUCK_DELAY)
		end
	end
	anim.Chair = chair
	if info then
		pending = nil
	end
end

-- Le personnage se lève
local function beginStand(anim: Anim)
	if anim.Phase == "stand" then
		return
	end
	anim.Phase = "stand"
	anim.PhaseT = 0
	for key, joint in pairs(anim.Rig.Joints) do
		anim.From[key] = joint.Written or joint.Motor.Transform
	end
	clearProps(anim)
	-- la chaise recule un peu puis se range
	local model, seatPart = anim.Model, anim.SeatPart
	if model and seatPart and PULL[anim.Kind] and seatPart.Parent then
		local chair = chairFor(model, seatPart, anim.Kind)
		if chair then
			chair.Seat = nil
			chair.SeatOrigin = nil
			table.clear(chair.Steps)
			local pull = freePull(chair, seatPart, PULL[anim.Kind] * 0.7, { model, anim.Character })
			if pull > 0.15 then
				chairTo(chair, pull, STAND_OUT, 0)
				chairTo(chair, 0, STAND_IN, STAND_BACK)
			else
				chairTo(chair, 0, 0.2, 0)
			end
		end
	end
end

-- Remet l'horloge des animations d'attente à zéro (le joueur a bougé…)
local function resetIdle(anim: Anim)
	anim.Resets += 1
	local elapsed = math.max(0, serverNow() - anim.SitAt)
	anim.Sched = newSched(anim.Seed + anim.Resets * 104729, elapsed, anim.Kind)
end

-- L'animation d'attente en cours s'efface vite (au lieu de s'arrêter net)
local function fadeCurrent(anim: Anim)
	local clip = anim.Sched.Clip
	if not clip then
		return
	end
	local ct = math.max(0, serverNow() - anim.SitAt) - anim.Sched.Start
	local d = clip.Duration
	anim.Fading = { Clip = clip, T = ct, W = smooth(ct / clip.FadeIn) * smooth((d - ct) / clip.FadeOut) }
end

-- Une émote (piste Action ou plus) joue-t-elle ?
local function emotePlaying(humanoid: Humanoid): boolean
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	local ok, tracks = pcall(function()
		return animator:GetPlayingAnimationTracks()
	end)
	if not ok or type(tracks) ~= "table" then
		return false
	end
	for _, track in ipairs(tracks) do
		local priority = track.Priority
		if priority == Enum.AnimationPriority.Action or priority == Enum.AnimationPriority.Action2
			or priority == Enum.AnimationPriority.Action3 or priority == Enum.AnimationPriority.Action4 then
			if track.IsPlaying and track.WeightCurrent > 0.3 then
				return true
			end
		end
	end
	return false
end

local function updateProps(anim: Anim)
	local rig: Rig = anim.Rig
	-- 📱 téléphone : devant la main droite, écran tourné vers la tête
	if anim.WantPhone and anim.Pause > 0.5 and rig.Hand and rig.Head then
		local phone = anim.Phone
		if not phone or not phone.Parent then
			anim.PhoneN = (anim.PhoneN or 0) + 1
			phone = makePhone(anim)
			anim.Phone = phone
		end
		local hand = rig.Hand
		local handPos = hand.Position
		if rig.R6 then
			handPos = (hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 + 0.2, 0)).Position
		end
		local head = rig.Head.Position
		local look = head - handPos
		if look.Magnitude > 0.1 then
			local at = handPos + look.Unit * 0.22 + UP * 0.12
			phone.CFrame = CFrame.lookAt(at, head, rig.Root.CFrame.UpVector)
		end
	elseif anim.Phone then
		pcall(anim.Phone.Destroy, anim.Phone)
		anim.Phone = nil
	end
	-- 💤 bulle au-dessus de la tête
	if anim.WantZzz and anim.Pause > 0.5 then
		local zzz = anim.Zzz
		if not zzz or not zzz.Parent then
			zzz = makeZzz(anim)
			anim.Zzz = zzz
		end
		if zzz then
			local t = now() % 2.4 / 2.4
			zzz.StudsOffset = Vector3.new(0.9 + 0.2 * t, 1.1 + 1.1 * t, 0)
			local label = zzz:FindFirstChild("Z")
			if label and label:IsA("TextLabel") then
				label.TextTransparency = math.clamp(t * 1.4 - 0.4, 0, 1)
			end
		end
	elseif anim.Zzz then
		pcall(anim.Zzz.Destroy, anim.Zzz)
		anim.Zzz = nil
	end
end

-- Une image d'un personnage animé ; false = terminé (retiré)
local function stepAnim(anim: Anim, dt: number): boolean
	local character: Model = anim.Character
	local humanoid: Humanoid = anim.Humanoid
	local rig: Rig = anim.Rig
	if not character.Parent or not humanoid.Parent or humanoid.Health <= 0 or not rig.Root.Parent then
		removeAnim(anim)
		return false
	end
	anim.PhaseT += dt
	-- toujours assis sur ce siège ?
	if anim.Phase ~= "stand" and (humanoid.SeatPart ~= anim.Seat or not anim.Seat.Parent) then
		beginStand(anim)
	end
	-- pause : bureau (joueur local), émote
	anim.TrackClock -= dt
	if anim.TrackClock <= 0 then
		anim.TrackClock = SCAN_INTERVAL
		anim.Emote = emotePlaying(humanoid)
	end
	local paused = anim.Emote == true or (anim.Local and deskActive())
	anim.PauseTarget = paused and 0 or 1
	if anim.Pause < anim.PauseTarget then
		anim.Pause = math.min(anim.PauseTarget, anim.Pause + dt * PAUSE_SPEED)
	elseif anim.Pause > anim.PauseTarget then
		anim.Pause = math.max(anim.PauseTarget, anim.Pause - dt * PAUSE_SPEED)
	end
	-- bouger (joueur local), pause : l'animation d'attente s'efface, on recompte
	local moved = anim.Local and anim.Phase == "seated" and moveMagnitude(humanoid) > MOVE_THRESHOLD
	if (moved or paused) and (anim.Sched.Clip or moved) then
		fadeCurrent(anim)
		resetIdle(anim)
	end
	-- bases lues sur l'Animator
	local pose: Pose = { Rig = rig, Work = {} }
	for key, joint in pairs(rig.Joints) do
		local current = joint.Motor.Transform
		local base = current
		if joint.Written and joint.Base and sameCF(current, joint.Written) then
			base = joint.Base
		end
		joint.Base = base
		pose.Work[key] = base
	end
	anim.WantPhone = false
	anim.WantZzz = false
	local t = now()
	if anim.Phase == "stand" then
		local a = smooth(anim.PhaseT / STAND_TIME)
		for key, joint in pairs(rig.Joints) do
			local from = anim.From[key]
			if from and a < 1 then
				local value = from:Lerp(pose.Work[key], a)
				joint.Motor.Transform = value
				joint.Written = value
			end
		end
		if anim.PhaseT >= STAND_TIME then
			removeAnim(anim)
			return false
		end
		return true
	end
	local w = anim.Pause
	applyKindBase(pose, anim, w, t)
	-- respiration
	add(pose, "Waist", CFrame.Angles(rad(0.9 * wave(t, 4.1)), 0, 0), w)
	-- animation d'attente (même tirage chez tout le monde)
	local elapsed = math.max(0, serverNow() - anim.SitAt)
	if anim.Phase == "seated" then
		advanceSched(anim.Sched, elapsed)
		local clip = anim.Sched.Clip
		if clip then
			local ct = elapsed - anim.Sched.Start
			local d = clip.Duration
			local env = smooth(ct / clip.FadeIn) * smooth((d - ct) / clip.FadeOut)
			clip.Apply(pose, ct, d, env * w, anim)
		end
		-- animation interrompue (le joueur a bougé, pause) : fondu de sortie rapide
		local fading = anim.Fading
		if fading then
			fading.T += dt
			fading.W -= dt / 0.35
			if fading.W <= 0 or fading.T >= fading.Clip.Duration then
				anim.Fading = nil
			else
				fading.Clip.Apply(pose, fading.T, fading.Clip.Duration, fading.W, anim)
			end
		end
	end
	-- transition d'assise : on part de la pose debout, on se penche en avant en descendant
	if anim.Phase == "sit" then
		local a = anim.PhaseT / SIT_TIME
		local e = smooth(a)
		add(pose, "Waist", CFrame.Angles(rad(-20 * math.sin(math.pi * clamp01(a))), 0, 0), 1)
		reach(pose, "R", Vector3.new(0.9, -0.9, -0.5), Vector3.new(1, -0.5, 0.5), 0.35 * math.sin(math.pi * clamp01(a)))
		reach(pose, "L", Vector3.new(-0.9, -0.9, -0.5), Vector3.new(-1, -0.5, 0.5), 0.35 * math.sin(math.pi * clamp01(a)))
		-- racine : de la position debout vers le siège
		local root = rig.Joints.Root
		local standCF: CFrame? = anim.StandCF
		if standCF and not anim.RootStart then
			local rel = rig.Root.CFrame:Inverse() * standCF
			anim.RootStart = root.C0:Inverse() * rel * root.C0 * (anim.Start.Root or IDENTITY)
		end
		for key, joint in pairs(rig.Joints) do
			local from = (key == "Root" and anim.RootStart) or anim.Start[key]
			local target = pose.Work[key]
			local value = (from and e < 1) and from:Lerp(target, e) or target
			joint.Motor.Transform = value
			joint.Written = value
		end
		if a >= 1 then
			anim.Phase = "seated"
			anim.PhaseT = 0
		end
		updateProps(anim)
		return true
	end
	-- (en pause complète, rien à écrire : l'Animator garde la main)
	local idle = w <= 0 and anim.Fading == nil
	for _, joint in pairs(rig.Joints) do
		if idle then
			joint.Written = nil
		end
	end
	if not idle then
		for key, joint in pairs(rig.Joints) do
			local value = pose.Work[key]
			joint.Motor.Transform = value
			joint.Written = value
		end
	end
	updateProps(anim)
	return true
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function localCharacter(): (Model?, Humanoid?, BasePart?)
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, (root and root:IsA("BasePart")) and root or nil
end

-- (v9.9 PARK99) les sièges des jeux du parc (balançoire, tape-cul, tourniquet,
-- jeux à ressort : attribut ParkPose) sont animés par ParkPlay seul
local function isSittable(seat: Instance?): boolean
	return seat ~= nil and seat:IsA("Seat") and seat:GetAttribute("ParkPose") ~= true
end

----------------------------------------------------------------------
-- (v9.9 REALISM99) Assis : plus AUCUNE invite "S'asseoir"
-- Tant que l'avatar local est sur un siège (Humanoid.SeatPart), toutes les
-- invites de type "s'asseoir / s'allonger / monter" (sièges des maisons,
-- bancs, jeux du parc, sièges du jardin, manèges) sont cachées ; elles
-- reviennent quand il se lève. On NE touche PAS à Enabled (d'autres modules
-- s'en servent : mode édition, manèges, voitures) : on met leur portée
-- (MaxActivationDistance) à 0 et on remet la valeur d'origine ensuite.
-- Reconnues : nom (SitPrompt, ParkPrompt, SeatPrompt, BenchPrompt,
-- GardenSeatPrompt), attribut SitPrompt = true (convention pour les
-- nouveaux sièges), invite de manège (FairPrompt + RideId), ou texte
-- "S'asseoir" / "S'allonger".
----------------------------------------------------------------------

local SIT_PROMPT_NAMES: { [string]: boolean } = {
	SitPrompt = true,
	ParkPrompt = true,
	SeatPrompt = true,
	BenchPrompt = true,
	GardenSeatPrompt = true,
}
local PROMPT_EVERY = 0.2 -- (s) nouvelles invites apparues pendant qu'on est assis
local knownPrompts: { [ProximityPrompt]: boolean } = setmetatable({} :: any, { __mode = "k" })
local hiddenPrompts: { [ProximityPrompt]: number } = {} -- invite -> portée d'origine
local promptsHidden = false
local promptClock = 0
local promptConn: RBXScriptConnection? = nil
local sitTexts: { [string]: boolean }? = nil

local function isSitPrompt(prompt: ProximityPrompt): boolean
	if SIT_PROMPT_NAMES[prompt.Name] or prompt:GetAttribute("SitPrompt") == true then
		return true
	end
	if prompt.Name == "FairPrompt" and prompt:GetAttribute("RideId") ~= nil then
		return true
	end
	if not sitTexts then
		local texts: { [string]: boolean } = { ["Sit"] = true, ["Lie down"] = true, ["S'asseoir"] = true, ["S'allonger"] = true }
		pcall(function()
			texts[Locale.T("Sit")] = true
			texts[Locale.T("Lie down")] = true
		end)
		sitTexts = texts
	end
	return (sitTexts :: { [string]: boolean })[prompt.ActionText] == true
end

local function notePrompt(d: Instance)
	if d:IsA("ProximityPrompt") then
		knownPrompts[d] = true
	end
end

local function hidePrompts()
	for prompt in pairs(knownPrompts) do
		if prompt.Parent == nil then
			knownPrompts[prompt] = nil
		elseif hiddenPrompts[prompt] == nil and isSitPrompt(prompt) then
			local distance = prompt.MaxActivationDistance
			if distance > 0 then
				hiddenPrompts[prompt] = distance
				prompt.MaxActivationDistance = 0
			end
		end
	end
end

local function showPrompts()
	for prompt, distance in pairs(hiddenPrompts) do
		-- (quelqu'un d'autre a changé la portée entre-temps : on la lui laisse)
		if prompt.Parent and prompt.MaxActivationDistance == 0 then
			prompt.MaxActivationDistance = distance
		end
	end
	table.clear(hiddenPrompts)
end

-- Appelé à chaque image : assis -> invites cachées ; debout -> remises
local function stepPrompts(dt: number, seated: boolean)
	if seated then
		promptClock -= dt
		if not promptsHidden or promptClock <= 0 then
			promptsHidden = true
			promptClock = PROMPT_EVERY
			hidePrompts()
		end
	elseif promptsHidden then
		promptsHidden = false
		showPrompts()
	end
end

local function startPrompts()
	if promptConn then
		return
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		notePrompt(d)
	end
	promptConn = workspace.DescendantAdded:Connect(notePrompt)
end

local function stopPrompts()
	if promptConn then
		promptConn:Disconnect()
		promptConn = nil
	end
	promptsHidden = false
	pcall(showPrompts)
	table.clear(knownPrompts)
end

-- (tests) les invites cachées (assis)
function SitAnimator.HiddenPrompts(): { [ProximityPrompt]: number }
	return hiddenPrompts
end

-- Autres joueurs assis près de nous (et fin de ceux qui sont partis)
local function scanRemote()
	local _, _, myRoot = localCharacter()
	local center = myRoot and myRoot.Position
	local count = 0
	for _, anim in pairs(anims) do
		if not anim.Local then
			count += 1
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= Players.LocalPlayer then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and humanoid and root and root:IsA("BasePart") then
				local anim = anims[character]
				local near = center ~= nil and (root.Position - center).Magnitude <= REMOTE_RADIUS
				local seat = humanoid.SeatPart
				if anim then
					if not near and anim.Phase ~= "stand" then
						removeAnim(anim)
						count -= 1
					end
				elseif near and isSittable(seat) and count < REMOTE_MAX and humanoid.Health > 0 then
					beginSit(character, humanoid, seat :: BasePart, false, player)
					local created = anims[character]
					if created then
						-- (chez nous : ni glissé depuis la position debout, ni long fondu)
						created.StandCF = nil
						created.Phase = "sit"
						count += 1
					end
				end
			end
		end
	end
end

local function step(dt: number)
	if not started then
		return
	end
	-- (v9.9) invites "S'asseoir" cachées tant qu'on est assis (même si
	-- l'animation s'est coupée sur une erreur)
	pcall(function()
		local _, humanoid = localCharacter()
		stepPrompts(dt, humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.Health > 0)
	end)
	if failed then
		return
	end
	local ok, err = pcall(function()
		local character, humanoid, root = localCharacter()
		if character and humanoid and root then
			local anim = anims[character]
			local seat = humanoid.SeatPart
			if not anim and isSittable(seat) and humanoid.Health > 0 then
				beginSit(character, humanoid, seat :: BasePart, true, Players.LocalPlayer)
			elseif not seat and not anim then
				-- debout : pose et position retenues pour la prochaine assise
				lastStand = root.CFrame
				for key, spec in pairs(humanoid.RigType == Enum.HumanoidRigType.R6 and R6_JOINTS or R15_JOINTS) do
					local part = character:FindFirstChild(spec[1])
					local motor = part and part:FindFirstChild(spec[2])
					if motor and motor:IsA("Motor6D") then
						lastStandT[key] = motor.Transform
					end
				end
			end
		end
		scanClock -= dt
		if scanClock <= 0 then
			scanClock = SCAN_INTERVAL
			scanRemote()
		end
		for _, anim in pairs(anims) do
			stepAnim(anim, dt)
		end
		stepChairs(dt)
	end)
	if not ok then
		failed = true
		warn("[SitAnimator] " .. tostring(err))
		for _, anim in pairs(anims) do
			pcall(removeAnim, anim)
		end
		table.clear(anims)
		pcall(restoreChairs)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Invite "S'asseoir" : tirer la chaise, s'avancer, puis sit(cf, kind)
function SitAnimator.Approach(model: Model?, seatPart: BasePart, sit: (cf: CFrame, kind: string) -> ())
	local cf = seatPart.CFrame * CFrame.new(0, seatPart.Size.Y / 2, 0)
	local kind = SitAnimator.KindOf(model, seatPart)
	local character, humanoid, root = localCharacter()
	if not started or failed or not character or not humanoid or not root or humanoid.SeatPart ~= nil or not model then
		sit(cf, kind)
		return
	end
	if pending and now() - pending.At < APPROACH_MAX + SEAT_WAIT then
		return -- (déjà en route vers une chaise)
	end
	local chair: Chair? = nil
	local ok = pcall(function()
		chair = chairFor(model, seatPart, kind)
	end)
	if not ok then
		chair = nil
	end
	local look = seatPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local pull = 0
	if chair then
		pull = freePull(chair, seatPart, PULL[kind] or 0, { model, character })
		if pull > 0.15 then
			chair.Hold = true
			table.clear(chair.Steps)
			chairTo(chair, pull, PULL_TIME, 0)
		else
			pull = 0
		end
	end
	local info = { Model = model, SeatPart = seatPart, CF = cf, Kind = kind, Chair = chair, At = now() }
	pending = info
	task.spawn(function()
		-- s'avancer devant l'assise (chaise tirée) : quelques pas au plus
		-- (devant l'assise de la chaise tirée ; la chaise recule vers -flat)
		local front = cf.Position - flat * pull + flat * (math.max(seatPart.Size.Z, 0.6) / 2 + 0.55)
		local target = Vector3.new(front.X, root.Position.Y, front.Z)
		local distance = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude
		local cancelled = false
		if kind ~= "desk" and kind ~= "bed" and distance > 1.2 and distance < 12 then
			pcall(function()
				humanoid:MoveTo(target)
			end)
			local speed = math.max(8, humanoid.WalkSpeed)
			local limit = math.min(APPROACH_MAX, distance / speed + 0.4)
			local t0 = now()
			task.wait(0.05)
			while now() - t0 < limit do
				if pending ~= info or not started then
					cancelled = true
					break
				end
				if humanoid.Health <= 0 or not root.Parent or humanoid.Jump then
					cancelled = true
					break
				end
				if moveMagnitude(nil) > MOVE_THRESHOLD then
					cancelled = true
					break
				end
				local flatPos = Vector3.new(root.Position.X, 0, root.Position.Z)
				if (flatPos - Vector3.new(target.X, 0, target.Z)).Magnitude < 0.8 then
					break
				end
				task.wait(0.05)
			end
		elseif chair and pull > 0 then
			task.wait(PULL_TIME * 0.7)
		end
		if cancelled or pending ~= info or not started then
			if pending == info then
				pending = nil
			end
			if chair and chairs[chair.Key] == chair then
				chair.Hold = false
				chairTo(chair, 0, TUCK_TIME, 0)
			end
			return
		end
		sit(cf, kind)
		-- le serveur a refusé (trop loin…) : on range la chaise
		task.delay(SEAT_WAIT, function()
			if pending == info then
				pending = nil
				if chair and chairs[chair.Key] == chair and chair.Hold then
					chair.Hold = false
					chairTo(chair, 0, TUCK_TIME, 0)
				end
			end
		end)
	end)
end

local function onDeskChanged(active: any)
	if active == true then
		return
	end
	-- sortie du mode bureau encore assis : on recompte
	for _, anim in pairs(anims) do
		if anim.Local then
			resetIdle(anim)
		end
	end
end

function SitAnimator.Start()
	if started then
		return
	end
	started = true
	failed = false
	scanClock = 0
	pcall(startPrompts)
	table.insert(connections, RunService.Stepped:Connect(function(_time: number, dt: number)
		step(dt)
	end))
	local d = desk()
	if d and type(d.Changed) == "table" and deskConnection == nil then
		pcall(function()
			deskConnection = d.Changed:Connect(onDeskChanged)
		end)
	end
	local player = Players.LocalPlayer
	if player then
		table.insert(connections, player.CharacterRemoving:Connect(function(character: Model)
			local anim = anims[character]
			if anim then
				removeAnim(anim)
			end
			lastStand = nil
			table.clear(lastStandT)
			pending = nil
		end))
	end
end

function SitAnimator.Stop()
	if not started then
		return
	end
	started = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	stopPrompts()
	if deskConnection then
		pcall(function()
			(deskConnection :: any):Disconnect()
		end)
		deskConnection = nil
	end
	for _, anim in pairs(anims) do
		pcall(removeAnim, anim)
	end
	table.clear(anims)
	pcall(restoreChairs)
	pending = nil
	lastStand = nil
	table.clear(lastStandT)
	if propsFolder then
		propsFolder:Destroy()
		propsFolder = nil
	end
end

-- (tests) état interne
function SitAnimator.Debug(): any
	return {
		Started = started,
		Failed = failed,
		Anims = anims,
		Chairs = chairs,
		Pending = function()
			return pending
		end,
		Step = step,
		Clips = CLIPS,
		Program = PROGRAM,
		KindFromId = kindFromId,
		Force = function(character: Model, clipName: string, elapsed: number?)
			-- (tests) impose une animation d'attente à un personnage assis
			local anim = anims[character]
			local clip = CLIPS[clipName]
			if anim and clip then
				anim.Phase = "seated"
				local e = elapsed or 0
				local nowElapsed = math.max(0, serverNow() - anim.SitAt)
				anim.Sched.Clip = clip
				anim.Sched.Start = nowElapsed - e
				anim.Sched.Stop = anim.Sched.Start + clip.Duration
			end
		end,
	}
end

return SitAnimator
