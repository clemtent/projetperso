--[[
	FairEat (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FairEat

	🍴 Bras qui TIENT et qui MANGE (v9.9 FAIR99 ; v11 ITEMS11), R15 ET R6.

	v11 — POURQUOI LA GLACE PARTAIT DE TRAVERS (capture 31) :
	Roblox soude la poignée à la main : Handle = Main * C0 * Tool.Grip⁻¹,
	C0 = RightGripAttachment (R15 : (0, -0,15, 0), orientation (-90, 0, 0))
	ou RightGrip C0 = (0, -1, 0) * Angles(-90°, 0, 0) (R6). Le +Y de
	l'aliment = l'AVANT DU BRAS (le trou du poing). Notre Grip sans rotation
	ne donnait donc un aliment debout QUE si le bras est levé à l'horizontale
	(l'animation "toolnone" du script Animate). Or ce bras levé n'est pas
	garanti : bras qui pend (marche / course / packs d'animations de
	priorité Movement, saut, chute, émotes, assis, script Animate
	remplacé...) -> le +Y de l'aliment pointe vers l'AVANT, à l'horizontale :
	la glace sort du poing comme un bâton (capture 31). Calcul (vérifié hors
	jeu, items11/hold_check.luau) : bras pendant = 90° d'écart avec la
	verticale, en R15 comme en R6.
	Correctif : nous ne dépendons plus d'aucune animation. À chaque image,
	pour chaque avatar proche qui tient un aliment (le mien ET les autres),
	une vraie pose de TENUE est calculée à partir de la pose animée du moment
	(C0 d'origine + Transform de l'Animator) :
	  - R15 : épaule + coude (IK à 2 os : bras le long du corps, avant-bras
	    vers l'avant, coude en bas / à l'extérieur), puis le POIGNET met
	    l'aliment exactement debout (léger penché vers le visage), face à
	    l'avant ;
	  - R6 (bras rigide) : épaule (bras vers l'avant, un peu baissé), puis la
	    soudure RightGrip (localement) corrige l'angle restant -> debout.
	Le geste "porter à la bouche" (lécher / croquer / siroter) se mélange
	par-dessus cette tenue. On modifie Motor6D.C0 (= C0 d'origine * rotation
	dans le repère du joint) : l'Animator continue d'écrire Transform, rien
	n'est cassé ; Restore remet tout (C0 d'origine gardés en attribut, jamais
	capturés deux fois).
	FairEat.Solve / SolveHold sont PURS (CFrame seulement) : vérifiés hors jeu.
]]

local FairEat = {}

local UP = Vector3.new(0, 1, 0)
local BASE_ATTR = "FairEatBaseC0"

-- Rotation minimale qui amène le vecteur u sur v (CFrame sans position)
local function fromTo(u: Vector3, v: Vector3): CFrame
	local a, b = u.Unit, v.Unit
	local axis = a:Cross(b)
	local s = axis.Magnitude
	local c = math.clamp(a:Dot(b), -1, 1)
	if s < 1e-6 then
		if c > 0 then
			return CFrame.identity
		end
		-- (opposés : demi-tour autour d'un axe perpendiculaire quelconque)
		local p = if math.abs(a.X) < 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
		return CFrame.fromAxisAngle(a:Cross(p).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, c))
end
FairEat.FromTo = fromTo

-- Rotation (monde) qui amène le repère (up, look) sur (wantUp, wantLook) :
-- d'abord le haut, puis la torsion autour du haut (le devant)
local function alignUpLook(up: Vector3, look: Vector3, wantUp: Vector3, wantLook: Vector3?): CFrame
	local r1 = fromTo(up, wantUp)
	if not wantLook then
		return r1
	end
	local l1 = r1:VectorToWorldSpace(look)
	local u = wantUp.Unit
	local a = l1 - u * l1:Dot(u)
	local b = wantLook - u * wantLook:Dot(u)
	if a.Magnitude < 1e-4 or b.Magnitude < 1e-4 then
		return r1
	end
	return fromTo(a, b) * r1
end

export type Joint = { C0: CFrame, C1: CFrame, X: CFrame }
export type Chain = {
	R15: boolean,
	Torso: CFrame, -- UpperTorso (R15) / Torso (R6)
	Head: CFrame,
	HeadSize: Vector3,
	Shoulder: Joint,
	Elbow: Joint?, -- (R15)
	Wrist: Joint?, -- (R15)
	GripC0: CFrame, -- soudure RightGrip : C0 D'ORIGINE (dans la main / le bras)
	GripC1: CFrame, -- = Tool.Grip
	Reach: number?, -- hauteur (au-dessus du poing) du point amené aux lèvres (1,3)
	Lean: number?, -- (rad) aliment penché vers le visage à la bouche (30°)
	Stand: number?, -- (studs) ce point reste à `Stand` devant la bouche (0,22)
}

local function part1(p0: CFrame, j: Joint, c0: CFrame?): CFrame
	return p0 * (c0 or j.C0) * j.X * j.C1:Inverse()
end

-- Bouche (repère monde) : devant la tête, un peu sous son centre
function FairEat.Mouth(head: CFrame, size: Vector3): Vector3
	return head.Position + head.LookVector * (size.Z * 0.5) - head.UpVector * (size.Y * 0.2)
end

-- Rotation d'un joint (repère du joint) pour une rotation monde W appliquée
-- autour de ce joint
local function inJoint(joint: CFrame, W: CFrame): CFrame
	return joint.Rotation:Inverse() * W * joint.Rotation
end

-- IK R15 à 2 os : le point de prise va en `target`, coude du côté `pole`,
-- puis le poignet amène le haut de l'aliment sur `wantUp` (et son devant
-- sur `wantLook`). wantUp(gripPos) -> Vector3 (calculé au poing final).
local function solveArm(ch: Chain, target: Vector3, pole: Vector3, wantUp: (Vector3) -> Vector3, wantLook: Vector3?): { [string]: CFrame }
	local out: { [string]: CFrame } = {}
	local S = ch.Shoulder
	local E, Wr = ch.Elbow :: Joint, ch.Wrist :: Joint
	local jointS = ch.Torso * S.C0
	local Sp = jointS.Position
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
	local poleP = pole - dir * pole:Dot(dir)
	if poleP.Magnitude < 1e-3 then
		poleP = Vector3.new(0, -1, 0) - dir * (-dir.Y)
		if poleP.Magnitude < 1e-3 then
			poleP = ch.Torso.RightVector
		end
	end
	local E2 = Sp + dir * x + poleP.Unit * h
	local W1 = fromTo(Ep - Sp, E2 - Sp)
	out.Shoulder = inJoint(jointS, W1)
	-- avant-bras : après W1, du coude vers la cible
	local pivot1 = CFrame.new(Sp) * W1 * CFrame.new(-Sp)
	local upper1 = pivot1 * upper
	local G1 = (pivot1 * grip).Position
	local W2 = fromTo(G1 - E2, (Sp + dir * d) - E2)
	local jointE1 = upper1 * E.C0
	out.Elbow = inJoint(jointE1, W2)
	-- poignet : l'aliment dans la bonne direction
	local pivot2 = CFrame.new(E2) * W2 * CFrame.new(-E2)
	local lower2 = pivot2 * (pivot1 * lower)
	local handle2 = pivot2 * pivot1 * grip * ch.GripC1:Inverse()
	local gripPos = (pivot2 * pivot1 * grip).Position
	local W3 = alignUpLook(handle2.UpVector, handle2.LookVector, wantUp(gripPos), wantLook)
	local jointW = lower2 * Wr.C0
	out.Wrist = inJoint(jointW, W3)
	return out
end

-- R6 (ou R15 incomplet) : épaule seule ; le bras vise `dir` (son -Y), avec
-- la torsion qui met l'avant du bras (son -Z) au plus près de `front`
local function solveRigid(ch: Chain, dir: Vector3, front: Vector3): CFrame
	local S = ch.Shoulder
	local jointS = ch.Torso * S.C0
	local arm = part1(ch.Torso, S)
	local r1 = fromTo(-arm.UpVector, dir)
	local f1 = r1:VectorToWorldSpace(arm.LookVector)
	local d = dir.Unit
	local a = f1 - d * f1:Dot(d)
	local b = front - d * front:Dot(d)
	local W = r1
	if a.Magnitude > 1e-4 and b.Magnitude > 1e-4 then
		W = fromTo(a, b) * r1
	end
	return inJoint(jointS, W)
end

-- Tenue R15 / R6 du bras droit (repère de chaque joint), à partir de la pose
-- animée du moment : { Shoulder, Elbow?, Wrist?, Grip? } (Grip = correction
-- locale de la soudure RightGrip, R6 seulement, dans le repère de la prise)
function FairEat.SolveHold(ch: Chain): { [string]: CFrame }
	local T = ch.Torso
	local right, up, look = T.RightVector, T.UpVector, T.LookVector
	-- (léger penché vers le visage et vers l'intérieur : naturel)
	local wantUp = (UP * 1 + look * -0.1 + right * -0.1).Unit
	local flatLook = look - UP * look:Dot(UP)
	if flatLook.Magnitude < 1e-3 then
		flatLook = look
	end
	flatLook = flatLook.Unit
	local S = ch.Shoulder
	local Sp = (T * S.C0).Position
	if ch.R15 and ch.Elbow and ch.Wrist then
		local upper = part1(T, S)
		local Ep = (upper * ch.Elbow.C0).Position
		local lower = part1(upper, ch.Elbow)
		local Gp = (part1(lower, ch.Wrist) * ch.GripC0).Position
		local a = (Ep - Sp).Magnitude
		local b = (Gp - Ep).Magnitude
		-- bras presque vertical (un peu vers l'avant), avant-bras vers l'avant,
		-- légèrement relevé et rentré : le poing devant le ventre / l'estomac
		local elbow = Sp + up * (-0.95 * a) + look * (0.28 * a) + right * (0.05 * a)
		local target = elbow + look * (0.9 * b) + up * (0.22 * b) + right * (-0.36 * b)
		local pole = -up + right * 0.35 - look * 0.25
		return solveArm(ch, target, pole, function()
			return wantUp
		end, flatLook)
	end
	-- R6 : bras vers l'avant, 25° sous l'horizontale, rentré de 12°
	local dir = (flatLook * math.cos(math.rad(25)) - UP * math.sin(math.rad(25)) - right * 0.2).Unit
	local rot = solveRigid(ch, dir, UP)
	local out: { [string]: CFrame } = { Shoulder = rot }
	-- soudure : redresse l'aliment (son +Y) sur la verticale, face à l'avant
	local jointS = T * S.C0
	local arm1 = jointS * rot * S.X * S.C1:Inverse()
	local gripCF = arm1 * ch.GripC0
	local handle = gripCF * ch.GripC1:Inverse()
	local W = alignUpLook(handle.UpVector, handle.LookVector, wantUp, flatLook)
	out.Grip = inJoint(gripCF, W)
	return out
end

-- Geste "à la bouche" (repère de chaque joint) : { Shoulder, Elbow?, Wrist?, Grip? }
function FairEat.Solve(ch: Chain): { [string]: CFrame }
	local reach = ch.Reach or 1.3
	local lean = ch.Lean or math.rad(30)
	local stand = ch.Stand or 0.22
	local mouth = FairEat.Mouth(ch.Head, ch.HeadSize)
	local look, up = ch.Head.LookVector, ch.Head.UpVector
	local lips = mouth + look * stand
	-- le poing sous la bouche, devant : le point visé (penché de `lean`) touche les lèvres
	local target = lips + look * (reach * math.sin(lean)) - up * (reach * math.cos(lean))
	if ch.R15 and ch.Elbow and ch.Wrist then
		local pole = ch.Torso.RightVector * 0.8 - Vector3.new(0, 1, 0) - ch.Torso.LookVector * 0.2
		return solveArm(ch, target, pole, function(gripPos)
			return (lips - gripPos).Unit
		end, look)
	end
	-- R6 (bras rigide) : on vise avec le point de l'aliment, un peu devant la
	-- bouche (le bras ne peut pas se plier) ; la soudure penche l'aliment
	local S = ch.Shoulder
	local jointS = ch.Torso * S.C0
	local Sp = jointS.Position
	local arm = part1(ch.Torso, S)
	local handle = arm * ch.GripC0 * ch.GripC1:Inverse()
	local top = handle * Vector3.new(0, reach * 0.85, 0)
	local aim = lips + look * 0.25
	local W1 = fromTo(top - Sp, aim - Sp)
	local out: { [string]: CFrame } = { Shoulder = inJoint(jointS, W1) }
	local arm1 = CFrame.new(Sp) * W1 * CFrame.new(-Sp) * arm
	local gripCF = arm1 * ch.GripC0
	local h1 = gripCF * ch.GripC1:Inverse()
	local W = alignUpLook(h1.UpVector, h1.LookVector, (lips - gripCF.Position).Unit, look)
	out.Grip = inJoint(gripCF, W)
	return out
end

-- Nouveaux C0 pour un mélange k (0..1)
function FairEat.Blend(base: CFrame, rot: CFrame?, k: number): CFrame
	if not rot or k <= 0 then
		return base
	end
	return base * CFrame.identity:Lerp(rot, k)
end

-- Rotation finale d'un joint : tenue (poids w) puis geste (poids e)
function FairEat.Mix(hold: CFrame?, eat: CFrame?, w: number, e: number): CFrame
	local r = CFrame.identity:Lerp(hold or CFrame.identity, math.clamp(w, 0, 1))
	if eat and e > 0 then
		r = r:Lerp(eat, math.clamp(e, 0, 1))
	end
	return r
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
	Neck: Motor6D?,
	Hand: BasePart,
	Base: { [Instance]: CFrame },
}

local function motor(parent: Instance?, name: string): Motor6D?
	local m = parent and parent:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

-- C0 d'origine d'une articulation : gardé en attribut la 1re fois (jamais
-- recapturé déjà modifié, même si le module redémarre)
local function baseOf(j: Instance): CFrame
	local saved = j:GetAttribute(BASE_ATTR)
	if typeof(saved) == "CFrame" then
		return saved
	end
	local c0 = (j :: any).C0 :: CFrame
	pcall(function()
		j:SetAttribute(BASE_ATTR, c0)
	end)
	return c0
end
FairEat.BaseOf = baseOf

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
			local rig: Rig = { Character = character, R15 = full, Torso = torso, Head = head, Shoulder = s, Elbow = if full then e else nil, Wrist = if full then w else nil, Neck = motor(head, "Neck"), Hand = grip, Base = {} }
			for _, m in ipairs({ s, e, w, rig.Neck } :: { Motor6D? }) do
				if m then
					rig.Base[m] = baseOf(m)
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
		local neck = motor(torso, "Neck")
		local rig: Rig = { Character = character, R15 = false, Torso = torso, Head = head, Shoulder = s, Elbow = nil, Wrist = nil, Neck = neck, Hand = arm, Base = { [s] = baseOf(s) } }
		if neck then
			rig.Base[neck] = baseOf(neck)
		end
		return rig
	end
	return nil
end

-- Soudure RightGrip de l'outil tenu (sous la main R15 / le bras R6)
local function gripWeld(rig: Rig): JointInstance?
	local w = rig.Hand:FindFirstChild("RightGrip")
	return if w and w:IsA("JointInstance") then w else nil
end

local function jointOf(rig: Rig, m: Motor6D?): Joint?
	if not m then
		return nil
	end
	return { C0 = rig.Base[m] or m.C0, C1 = m.C1 or CFrame.identity, X = (m :: any).Transform or CFrame.identity }
end

export type Gesture = { K: number, Reach: number?, Lean: number?, Stand: number?, Nod: number?, Roll: number? }

-- Pose du bras à chaque image : tenue (poids w, 0..1) + geste vers la bouche
-- (g.K, 0..1). Le cou (g.Nod / g.Roll, rad) penche la tête vers l'aliment.
function FairEat.Apply(rig: Rig, w: number, g: Gesture?, tool: Tool?)
	local k = if g then g.K else 0
	if w <= 0.001 and k <= 0.001 then
		FairEat.Restore(rig)
		return
	end
	local weld = gripWeld(rig)
	if weld and not rig.Base[weld] then
		rig.Base[weld] = baseOf(weld)
	end
	local gripC0 = if weld then rig.Base[weld] else (if rig.R15 then CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0) else CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	local gripC1 = if tool then tool.Grip else CFrame.identity
	local chain: Chain = {
		R15 = rig.R15,
		Torso = rig.Torso.CFrame,
		Head = rig.Head.CFrame,
		HeadSize = rig.Head.Size,
		Shoulder = jointOf(rig, rig.Shoulder) :: Joint,
		Elbow = jointOf(rig, rig.Elbow),
		Wrist = jointOf(rig, rig.Wrist),
		GripC0 = gripC0,
		GripC1 = gripC1,
		Reach = g and g.Reach,
		Lean = g and g.Lean,
		Stand = g and g.Stand,
	}
	local ok1, hold = pcall(FairEat.SolveHold, chain)
	if not ok1 then
		return
	end
	local eat: { [string]: CFrame } = {}
	local e = k * k * (3 - 2 * k)
	if e > 0 then
		local ok2, rots = pcall(FairEat.Solve, chain)
		if ok2 then
			eat = rots
		else
			e = 0
		end
	end
	for name, m in pairs({ Shoulder = rig.Shoulder, Elbow = rig.Elbow, Wrist = rig.Wrist } :: { [string]: Motor6D? }) do
		if m and m.Parent then
			m.C0 = rig.Base[m] * FairEat.Mix(hold[name], eat[name], w, e)
		end
	end
	if weld and weld.Parent then
		local r = FairEat.Mix(hold.Grip, eat.Grip, w, e)
		;(weld :: any).C0 = rig.Base[weld] * r
	end
	-- tête : penche vers l'aliment (lécher, croquer)
	local neck = rig.Neck
	if neck and neck.Parent and rig.Base[neck] then
		local nod, roll = (g and g.Nod or 0) * e, (g and g.Roll or 0) * e
		if math.abs(nod) + math.abs(roll) > 1e-4 then
			local jointN = rig.Torso.CFrame * rig.Base[neck]
			local T = rig.Torso.CFrame
			local W = CFrame.fromAxisAngle(T.RightVector, -nod) * CFrame.fromAxisAngle(T.LookVector, roll)
			neck.C0 = rig.Base[neck] * inJoint(jointN, W)
		elseif neck.C0 ~= rig.Base[neck] then
			neck.C0 = rig.Base[neck]
		end
	end
end

function FairEat.Restore(rig: Rig)
	for j, c0 in pairs(rig.Base) do
		if j.Parent and (j :: any).C0 ~= c0 then
			(j :: any).C0 = c0
		end
	end
end

return FairEat
