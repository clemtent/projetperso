--[[
	MusicPose (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MusicPose

	🎵 Postures PROCÉDURALES des musiciens de la scène (v9.9, MUSIC99) :
	les animations ne peuvent pas être téléversées, on écrit donc chaque
	image les Motor6D.Transform du personnage (R15 ET R6), comme SitAnimator
	(SEAT98) dont on reprend les outils (IK à deux segments, repères des
	articulations) :
	  - assis SANS siège (piano, batterie) : le bassin descend jusqu'au banc
	    / au tabouret (racine abaissée), cuisses vers l'avant, pieds posés
	    au sol ou sur les pédales (IK des jambes) ;
	  - les MAINS visent des points du monde (touches, fûts, cordes,
	    platines) : IK épaule-coude-poignet ; en R6, le bras pointe vers le
	    point (pas de coude) ;
	  - buste penché, tête qui bat la mesure, pied de grosse caisse.
	Robuste : on n'écrit QUE Transform (jamais C0/C1), dans
	RunService.Stepped (après l'Animator) ; la pose se fond avec celle de
	l'Animator (poids 0..1) ; Release remet tout (l'Animator reprend la main).

	API :
	  MusicPose.Rig(character) -> Rig?
	  MusicPose.Solve(rig, spec, w)  spec = {
	      Seat: number?   (Y monde du dessus du banc ; nil = debout)
	      Feet: { R: Vector3?, L: Vector3? }? (chevilles, monde ; assis)
	      R: Vector3?, L: Vector3? (poignets, monde)
	      RPole: Vector3?, LPole: Vector3? (coudes, repère du buste)
	      Lean: number? (°, buste en avant), Twist: number? (°), Nod: number? (°), Look: number? (°)
	    }
	  MusicPose.Release(rig)
	  MusicPose.Hand(rig, side "R" | "L") -> CFrame? (main, dans le monde)
	  MusicPose.Torso(rig) -> BasePart?
]]

local MusicPose = {}

local IDENTITY = CFrame.identity
local rad = math.rad

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
	C1: CFrame,
	C0r: CFrame,
	C0rInv: CFrame,
	Base: CFrame?,
	Written: CFrame?,
}
type Limb = { P: Vector3, L1: number, L2: number }
export type Rig = {
	Character: Model,
	Humanoid: Humanoid,
	R6: boolean,
	Root: BasePart,
	Joints: { [string]: Joint },
	Arms: { [string]: Limb },
	Legs: { [string]: Limb },
	Scale: number,
	Hands: { [string]: BasePart },
	Torso: BasePart?,
	LegLen: number,
}

local function sameCF(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4 and a.LookVector:Dot(b.LookVector) > 0.99999 and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function limbOf(joints: { [string]: Joint }, a: string, b: string, c: string, r6: boolean, scale: number): Limb?
	local j1 = joints[a]
	if not j1 then
		return nil
	end
	if r6 then
		return { P = j1.C0.Position, L1 = 1.6 * scale, L2 = 0 }
	end
	local j2, j3 = joints[b], joints[c]
	if not j2 or not j3 then
		return nil
	end
	local l1 = (j1.C1.Position - j2.C0.Position).Magnitude
	local l2 = (j2.C1.Position - j3.C0.Position).Magnitude
	if l1 < 0.1 or l2 < 0.1 then
		return nil
	end
	return { P = j1.C0.Position, L1 = l1, L2 = l2 }
end

function MusicPose.Rig(character: Model?): Rig?
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local joints: { [string]: Joint } = {}
	for key, spec in pairs(r6 and R6_JOINTS or R15_JOINTS) do
		local holder = character:FindFirstChild(spec[1])
		local motor = holder and holder:FindFirstChild(spec[2])
		if motor and motor:IsA("Motor6D") then
			local c0 = motor.C0
			joints[key] = { Motor = motor, C0 = c0, C1 = motor.C1, C0r = c0.Rotation, C0rInv = c0.Rotation:Inverse(), Base = nil, Written = nil }
		end
	end
	if not joints.Root or not joints.RShoulder or not joints.LShoulder then
		return nil
	end
	local torso = character:FindFirstChild(r6 and "Torso" or "UpperTorso")
	local scale = 1
	if torso and torso:IsA("BasePart") then
		scale = math.clamp(torso.Size.Y / (r6 and 2 or 1.6), 0.5, 2)
	end
	local hands: { [string]: BasePart } = {}
	for side, names in pairs({ R = { "RightHand", "Right Arm" }, L = { "LeftHand", "Left Arm" } }) do
		local hand = character:FindFirstChild(r6 and names[2] or names[1])
		if hand and hand:IsA("BasePart") then
			hands[side] = hand
		end
	end
	local rig: Rig = {
		Character = character,
		Humanoid = humanoid,
		R6 = r6,
		Root = root,
		Joints = joints,
		Arms = {},
		Legs = {},
		Scale = scale,
		Hands = hands,
		Torso = (torso and torso:IsA("BasePart")) and torso or nil,
		LegLen = r6 and 2 * scale or math.max(1, tonumber(humanoid.HipHeight) or 2),
	}
	rig.Arms.R = limbOf(joints, "RShoulder", "RElbow", "RWrist", r6, scale) :: any
	rig.Arms.L = limbOf(joints, "LShoulder", "LElbow", "LWrist", r6, scale) :: any
	rig.Legs.R = limbOf(joints, "RHip", "RKnee", "RAnkle", r6, scale) :: any
	rig.Legs.L = limbOf(joints, "LHip", "LKnee", "LAnkle", r6, scale) :: any
	if r6 then
		-- (jambe R6 : 2 studs, pas de genou)
		if rig.Legs.R then
			rig.Legs.R.L1 = 2 * scale
		end
		if rig.Legs.L then
			rig.Legs.L.L1 = 2 * scale
		end
	end
	return rig
end

----------------------------------------------------------------------
-- Géométrie (outils de SitAnimator)
----------------------------------------------------------------------

-- Orientation d'un segment : -Y le long de `dir`, "devant" (-Z) vers `front`
local function frameAlong(dir: Vector3, front: Vector3): CFrame
	local d = dir.Magnitude > 1e-4 and dir.Unit or Vector3.new(0, -1, 0)
	local y = -d
	local z = -(front - d * front:Dot(d))
	if z.Magnitude < 1e-3 then
		z = Vector3.new(0, 0, 1) - d * d.Z
		if z.Magnitude < 1e-3 then
			z = Vector3.new(1, 0, 0)
		end
	end
	z = z.Unit
	local x = y:Cross(z)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

-- IK à deux segments dans le repère du parent : le bout vise `target`,
-- l'articulation du milieu part vers `pole` ; bend = 1 (bras) ou -1 (jambe)
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

-- Transform d'un joint pour une orientation `r` du membre (repère du parent)
local function absT(joint: Joint, r: CFrame): CFrame
	return joint.C0rInv * r * joint.C0r
end

-- Transform d'une rotation / translation dans le repère "personnage" du parent
local function addT(joint: Joint, r: CFrame): CFrame
	return joint.C0rInv * r * joint.C0r
end

local function part1CF(parentCF: CFrame, joint: Joint, t: CFrame): CFrame
	return parentCF * joint.C0 * t * joint.C1:Inverse()
end

----------------------------------------------------------------------
-- Pose
----------------------------------------------------------------------

function MusicPose.Solve(rig: Rig, spec: any, w: number)
	if w <= 0.001 or not rig.Root.Parent then
		return
	end
	w = math.min(w, 1)
	local J = rig.Joints
	-- bases : pose de l'Animator (sans cumul si l'Animator n'a pas réécrit un joint)
	local base: { [string]: CFrame } = {}
	for key, joint in pairs(J) do
		local current = joint.Motor.Transform
		local b = current
		if joint.Written and joint.Base and sameCF(current, joint.Written) then
			b = joint.Base
		end
		joint.Base = b
		base[key] = b
	end
	local target: { [string]: CFrame } = {}
	local seated = type(spec.Seat) == "number"
	local rootJ = J.Root
	-- 1. assis : racine abaissée pour poser le bassin sur le banc
	if seated then
		local hip = J.RHip or J.LHip
		local standParent = part1CF(rig.Root.CFrame, rootJ, IDENTITY)
		local hipY = hip and (standParent * hip.C0).Position.Y or (rig.Root.Position.Y - rig.LegLen * 0.5)
		local want = spec.Seat + (rig.R6 and 0.5 or 0.36) * rig.Scale
		local drop = math.clamp(hipY - want, 0, 3.2)
		target.Root = addT(rootJ, CFrame.new(0, -drop, 0))
	end
	-- 2. buste / tête
	local lean, twist = spec.Lean or 0, spec.Twist or 0
	if J.Waist then
		target.Waist = addT(J.Waist, CFrame.Angles(rad(-lean), rad(twist), 0))
	elseif rig.R6 and (lean ~= 0 or twist ~= 0) then
		-- (R6 : pas de taille -> le corps entier tourne un peu, sans les jambes)
		local r = CFrame.Angles(rad(-lean * 0.6), rad(twist * 0.6), 0)
		target.Root = (target.Root or base.Root) * addT(rootJ, r)
	end
	if J.Neck then
		target.Neck = addT(J.Neck, CFrame.Angles(rad(-(spec.Nod or 0)), rad(spec.Look or 0), 0))
	end
	-- repères du monde après la racine / la taille (pour viser des points)
	-- (pondération : la racine réellement écrite est base:Lerp(cible, w))
	local rootT = base.Root:Lerp(target.Root or base.Root, w)
	local lowerCF = part1CF(rig.Root.CFrame, rootJ, rootT)
	local armParentCF = lowerCF
	if not rig.R6 and J.Waist then
		local waistT = base.Waist:Lerp(target.Waist or base.Waist, w)
		armParentCF = part1CF(lowerCF, J.Waist, waistT)
	end
	-- 3. jambes (assis) : chevilles vers les pieds voulus
	if seated then
		for _, side in ipairs({ "R", "L" }) do
			local limb = rig.Legs[side]
			local hipKey = side == "R" and "RHip" or "LHip"
			local hip = J[hipKey]
			if limb and hip then
				local foot = spec.Feet and spec.Feet[side]
				local t: Vector3
				if typeof(foot) == "Vector3" then
					t = lowerCF:PointToObjectSpace(foot)
				else
					t = limb.P + Vector3.new(0, -1.1, -1.05) * rig.Scale
				end
				if rig.R6 then
					target[hipKey] = absT(hip, frameAlong(t - limb.P, Vector3.new(0, 0, -1)))
				else
					local r, flex = ik2(limb, t, Vector3.new(side == "R" and 0.15 or -0.15, 1, -1), -1)
					target[hipKey] = absT(hip, r)
					local knee = J[side == "R" and "RKnee" or "LKnee"]
					if knee then
						target[side == "R" and "RKnee" or "LKnee"] = absT(knee, CFrame.Angles(-flex, 0, 0))
					end
					local ankle = J[side == "R" and "RAnkle" or "LAnkle"]
					if ankle then
						target[side == "R" and "RAnkle" or "LAnkle"] = IDENTITY
					end
				end
			end
		end
	end
	-- 4. bras : poignets vers les points voulus
	for _, side in ipairs({ "R", "L" }) do
		local want = spec[side]
		local limb = rig.Arms[side]
		local shoulderKey = side == "R" and "RShoulder" or "LShoulder"
		local shoulder = J[shoulderKey]
		if typeof(want) == "Vector3" and limb and shoulder then
			local t = armParentCF:PointToObjectSpace(want)
			if rig.R6 then
				target[shoulderKey] = absT(shoulder, frameAlong(t - limb.P, Vector3.new(0, 0, -1)))
			else
				local pole = spec[side .. "Pole"] or Vector3.new(side == "R" and 1 or -1, -0.6, 0.5)
				local r, flex = ik2(limb, t, pole, 1)
				target[shoulderKey] = absT(shoulder, r)
				local elbow = J[side == "R" and "RElbow" or "LElbow"]
				if elbow then
					target[side == "R" and "RElbow" or "LElbow"] = absT(elbow, CFrame.Angles(flex, 0, 0))
				end
				local wrist = J[side == "R" and "RWrist" or "LWrist"]
				if wrist then
					target[side == "R" and "RWrist" or "LWrist"] = IDENTITY
				end
			end
		end
	end
	-- 5. écriture (fondu avec la pose de l'Animator)
	for key, value in pairs(target) do
		local joint = J[key]
		if joint then
			local final = w >= 0.999 and value or base[key]:Lerp(value, w)
			joint.Motor.Transform = final
			joint.Written = final
		end
	end
end

function MusicPose.Release(rig: Rig)
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

-- Main dans le monde (R6 : bas du bras)
function MusicPose.Hand(rig: Rig, side: string): CFrame?
	local hand = rig.Hands[side]
	if not hand or not hand.Parent then
		return nil
	end
	if rig.R6 then
		return hand.CFrame * CFrame.new(0, -0.85 * rig.Scale, 0)
	end
	return hand.CFrame
end

function MusicPose.Torso(rig: Rig): BasePart?
	return rig.Torso
end

-- (tests : cinématique directe d'une pose, sans moteur physique)
function MusicPose.Forward(rig: Rig): { [string]: CFrame }
	local out: { [string]: CFrame } = {}
	local J = rig.Joints
	local function cfOf(name: string): CFrame?
		return out[name]
	end
	out.HumanoidRootPart = rig.Root.CFrame
	local order = rig.R6 and { "Root", "Neck", "RShoulder", "LShoulder", "RHip", "LHip" }
		or { "Root", "Waist", "Neck", "RShoulder", "RElbow", "RWrist", "LShoulder", "LElbow", "LWrist", "RHip", "RKnee", "RAnkle", "LHip", "LKnee", "LAnkle" }
	for _, key in ipairs(order) do
		local joint = J[key]
		if joint then
			local motor = joint.Motor
			local p0 = motor.Part0
			local p1 = motor.Part1
			local parentCF = p0 and cfOf(p0.Name)
			if p1 and parentCF then
				out[p1.Name] = part1CF(parentCF, joint, motor.Transform)
			end
		end
	end
	return out
end

return MusicPose
