--[[
	FairEat (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FairEat

	🍴 Geste "porter l'aliment à la bouche" (v9.9, FAIR99), R15 ET R6.
	v9.8 : une rotation fixe de l'épaule (bras tendu) : sur R15 la main ne
	pouvait pas atteindre la bouche (bras de ~2 studs pour ~1,3 à parcourir :
	l'aliment traversait la tête), sur R6 l'aliment partait de travers.
	Ici une vraie cinématique inverse, calculée à chaque image à partir de la
	pose ANIMÉE du moment (C0 d'origine + Transform de l'Animator) :
	  - R15 : épaule + coude (2 os, coude vers le bas et l'extérieur), puis le
	    poignet incline l'aliment vers la bouche ;
	  - R6 : épaule seule (le bras vise la bouche).
	La cible : le point de prise (le poing) juste sous et devant la bouche,
	pour que le HAUT de l'aliment arrive aux lèvres.
	On modifie Motor6D.C0 (= C0 d'origine * rotation dans le repère du
	joint), mélangé par k (0 = pose normale, 1 = à la bouche) : l'Animator
	continue d'écrire Transform, rien n'est cassé ; Restore remet les C0.
	FairEat.Solve est PUR (CFrame seulement) : vérifié hors jeu.
]]

local FairEat = {}

-- Rotation minimale qui amène le vecteur u sur v (CFrame sans position)
local function fromTo(u: Vector3, v: Vector3): CFrame
	local a, b = u.Unit, v.Unit
	local axis = a:Cross(b)
	local s = axis.Magnitude
	local c = math.clamp(a:Dot(b), -1, 1)
	if s < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, c))
end
FairEat.FromTo = fromTo

export type Joint = { C0: CFrame, C1: CFrame, X: CFrame }
export type Chain = {
	R15: boolean,
	Torso: CFrame, -- UpperTorso (R15) / Torso (R6)
	Head: CFrame,
	HeadSize: Vector3,
	Shoulder: Joint,
	Elbow: Joint?, -- (R15)
	Wrist: Joint?, -- (R15)
	GripC0: CFrame, -- soudure RightGrip : C0 (dans la main / le bras)
	GripC1: CFrame, -- = Tool.Grip
	Reach: number?, -- hauteur de l'aliment au-dessus du poing (1,3)
}

local function part1(p0: CFrame, j: Joint, c0: CFrame?): CFrame
	return p0 * (c0 or j.C0) * j.X * j.C1:Inverse()
end

-- Bouche (repère monde) : devant la tête, un peu sous son centre
function FairEat.Mouth(head: CFrame, size: Vector3): Vector3
	return head.Position + head.LookVector * (size.Z * 0.5) - head.UpVector * (size.Y * 0.2)
end

-- Renvoie les rotations (repère de chaque joint) à k = 1 : { Shoulder, Elbow?, Wrist? }
function FairEat.Solve(ch: Chain): { [string]: CFrame }
	local out: { [string]: CFrame } = {}
	local reach = ch.Reach or 1.3
	local mouth = FairEat.Mouth(ch.Head, ch.HeadSize)
	local look, up = ch.Head.LookVector, ch.Head.UpVector
	-- le poing sous la bouche, devant : le haut de l'aliment (penché de ~30°) touche les lèvres
	local target = mouth + look * (0.28 + reach * 0.5) - up * (reach * 0.86)
	local S = ch.Shoulder
	local jointS = ch.Torso * S.C0
	local Sp = jointS.Position
	if ch.R15 and ch.Elbow and ch.Wrist then
		local E, Wr = ch.Elbow, ch.Wrist
		local upper = part1(ch.Torso, S)
		local jointE = upper * E.C0
		local Ep = jointE.Position
		local lower = part1(upper, E)
		local hand = part1(lower, Wr)
		local grip = hand * ch.GripC0
		local Gp = grip.Position
		local a = (Ep - Sp).Magnitude
		local b = (Gp - Ep).Magnitude
		local dvec = target - Sp
		local d = math.clamp(dvec.Magnitude, math.abs(a - b) + 0.05, a + b - 0.02)
		local dir = dvec.Unit
		local x = (a * a - b * b + d * d) / (2 * d)
		local h = math.sqrt(math.max(0, a * a - x * x))
		-- coude : vers le bas et vers l'extérieur (côté droit du buste)
		local pole = ch.Torso.RightVector * 0.8 - Vector3.new(0, 1, 0) - ch.Torso.LookVector * 0.2
		local poleP = pole - dir * pole:Dot(dir)
		if poleP.Magnitude < 1e-3 then
			poleP = Vector3.new(0, -1, 0)
		end
		local E2 = Sp + dir * x + poleP.Unit * h
		local W1 = fromTo(Ep - Sp, E2 - Sp)
		out.Shoulder = jointS.Rotation:Inverse() * W1 * jointS.Rotation
		-- avant-bras : après W1, du coude vers la cible
		local pivot1 = CFrame.new(Sp) * W1 * CFrame.new(-Sp)
		local upper1 = pivot1 * upper
		local G1 = (pivot1 * grip).Position
		local W2 = fromTo(G1 - E2, (Sp + dir * d) - E2)
		local jointE1 = upper1 * E.C0
		out.Elbow = jointE1.Rotation:Inverse() * W2 * jointE1.Rotation
		-- poignet : incline le haut de l'aliment vers la bouche
		local pivot2 = CFrame.new(E2) * W2 * CFrame.new(-E2)
		local lower2 = pivot2 * (pivot1 * lower)
		local handle2 = pivot2 * pivot1 * grip * ch.GripC1:Inverse()
		local foodUp = handle2.UpVector
		local want = (mouth - handle2.Position).Unit:Lerp(Vector3.new(0, 1, 0), 0.35).Unit
		local W3 = fromTo(foodUp, want)
		local jointW = lower2 * Wr.C0
		out.Wrist = jointW.Rotation:Inverse() * W3 * jointW.Rotation
	else
		-- R6 (bras rigide) : on vise avec le HAUT de l'aliment, un peu devant
		-- la bouche (le bras ne peut pas se plier)
		local arm = part1(ch.Torso, S)
		local handle = arm * ch.GripC0 * ch.GripC1:Inverse()
		local top = handle * Vector3.new(0, reach * 0.85, 0)
		local aim = mouth + look * 0.45
		local W1 = fromTo(top - Sp, aim - Sp)
		out.Shoulder = jointS.Rotation:Inverse() * W1 * jointS.Rotation
	end
	return out
end

-- Nouveaux C0 pour un mélange k (0..1)
function FairEat.Blend(base: CFrame, rot: CFrame?, k: number): CFrame
	if not rot or k <= 0 then
		return base
	end
	return base * CFrame.identity:Lerp(rot, k)
end

----------------------------------------------------------------------
-- En jeu : rig d'un personnage, application et remise en place
----------------------------------------------------------------------

export type Rig = {
	Character: Model,
	R15: boolean,
	Torso: BasePart,
	Head: BasePart,
	Shoulder: Motor6D,
	Elbow: Motor6D?,
	Wrist: Motor6D?,
	Hand: BasePart,
	Base: { [Motor6D]: CFrame },
}

local function motor(parent: Instance?, name: string): Motor6D?
	local m = parent and parent:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

function FairEat.Rig(character: Model): Rig?
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local upperArm = character:FindFirstChild("RightUpperArm")
	if upperArm then
		local s = motor(upperArm, "RightShoulder")
		local torso = character:FindFirstChild("UpperTorso") or (s and s.Part0)
		local lower = character:FindFirstChild("RightLowerArm")
		local hand = character:FindFirstChild("RightHand")
		local e = motor(lower, "RightElbow")
		local w = motor(hand, "RightWrist")
		local full = e ~= nil and w ~= nil and hand ~= nil and hand:IsA("BasePart")
		-- (rig incomplet / personnalisé : l'épaule seule, comme un R6)
		local grip = if full then hand else upperArm
		if torso and torso:IsA("BasePart") and grip and grip:IsA("BasePart") and s then
			local rig: Rig = { Character = character, R15 = full, Torso = torso, Head = head, Shoulder = s, Elbow = if full then e else nil, Wrist = if full then w else nil, Hand = grip, Base = {} }
			for _, m in ipairs({ s, e, w } :: { Motor6D? }) do
				if m then
					rig.Base[m] = m.C0
				end
			end
			return rig
		end
		return nil
	end
	local torso = character:FindFirstChild("Torso")
	local arm = character:FindFirstChild("Right Arm")
	local s = motor(torso, "Right Shoulder")
	if torso and torso:IsA("BasePart") and arm and arm:IsA("BasePart") and s then
		return { Character = character, R15 = false, Torso = torso, Head = head, Shoulder = s, Elbow = nil, Wrist = nil, Hand = arm, Base = { [s] = s.C0 } }
	end
	return nil
end

-- k (0..1) : applique le geste (à chaque image pendant la bouchée)
function FairEat.Apply(rig: Rig, k: number, tool: Tool?)
	if k <= 0.001 then
		FairEat.Restore(rig)
		return
	end
	local gripWeld = rig.Hand:FindFirstChild("RightGrip")
	local gripC0 = if gripWeld and gripWeld:IsA("JointInstance") then (gripWeld :: any).C0 else (if rig.R15 then CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0) else CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	local gripC1 = if tool then tool.Grip else CFrame.identity
	local function joint(m: Motor6D?): Joint?
		if not m then
			return nil
		end
		return { C0 = rig.Base[m] or m.C0, C1 = m.C1 or CFrame.identity, X = (m :: any).Transform or CFrame.identity }
	end
	local ok, rots = pcall(FairEat.Solve, {
		R15 = rig.R15,
		Torso = rig.Torso.CFrame,
		Head = rig.Head.CFrame,
		HeadSize = rig.Head.Size,
		Shoulder = joint(rig.Shoulder) :: Joint,
		Elbow = joint(rig.Elbow),
		Wrist = joint(rig.Wrist),
		GripC0 = gripC0,
		GripC1 = gripC1,
	})
	if not ok then
		return
	end
	local e = k * k * (3 - 2 * k)
	for name, m in pairs({ Shoulder = rig.Shoulder, Elbow = rig.Elbow, Wrist = rig.Wrist } :: { [string]: Motor6D? }) do
		if m and m.Parent then
			m.C0 = FairEat.Blend(rig.Base[m], rots[name], e)
		end
	end
end

function FairEat.Restore(rig: Rig)
	for m, c0 in pairs(rig.Base) do
		if m.Parent and m.C0 ~= c0 then
			m.C0 = c0
		end
	end
end

return FairEat
