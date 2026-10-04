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

-- Rotation autour de l'axe `axis` qui amène la projection de u sur celle de v
local function twistAbout(u: Vector3, v: Vector3, axis: Vector3): CFrame
	local n = axis.Unit
	local a = u - n * u:Dot(n)
	local b = v - n * v:Dot(n)
	if a.Magnitude < 1e-5 or b.Magnitude < 1e-5 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(n, math.atan2(a:Cross(b):Dot(n), a:Dot(b)))
end

-- Rotation H (repère de l'aliment -> monde) telle que H * aimLocal = wantDir,
-- et H * secLocal au plus près de secWorld (torsion autour de wantDir)
local function frameAim(aimLocal: Vector3, wantDir: Vector3, secLocal: Vector3, secWorld: Vector3): CFrame
	local r1 = fromTo(aimLocal, wantDir)
	return twistAbout(r1:VectorToWorldSpace(secLocal), secWorld, wantDir) * r1
end
FairEat.FrameAim = frameAim

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
	GripC1: CFrame, -- prise dans le repère du MODÈLE (FoodModels.GRIP ; Tool.Grip
	-- = HandleLocal⁻¹ * GripC1 : la poignée peut être tournée)
	Reach: number?, -- hauteur (au-dessus du poing) du point amené aux lèvres (1,3)
	Lean: number?, -- (rad) aliment penché vers le visage à la bouche (30°)
	Stand: number?, -- (studs) ce point reste à `Stand` devant la bouche (0,22)
	Side: number?, -- part du côté droit dans la direction lèvres -> poing (0,32)
	Aim: Vector3?, -- (v11) point de l'aliment (repère de la poignée) amené aux
	-- lèvres ; défaut (0, Reach, 0). Aliments couchés (taco, hot-dog) : le bout +X
	HoldLook: string?, -- (v11) "front" (défaut) | "left" : le devant de l'aliment
	-- tenu regarde l'avant, ou la gauche (aliments couchés : +X vers l'avant)
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

-- IK R15 à 2 os : le POING (point de prise) va en `target`, coude du côté
-- `pole`, l'aliment a pour haut `wantUp` et pour devant `wantLook`. Le
-- poignet tourne la main autour de SON articulation (le poing est 0,28
-- plus loin) : on vise donc le poignet, calculé depuis l'orientation
-- finale voulue de la main -> le poing tombe exactement sur la cible.
local function solveArm(ch: Chain, target: Vector3, pole: Vector3, H: CFrame): { [string]: CFrame }
	local out: { [string]: CFrame } = {}
	local S = ch.Shoulder
	local E, Wr = ch.Elbow :: Joint, ch.Wrist :: Joint
	-- orientation voulue H de la poignée ; main : poignée = main * GripC0 * GripC1⁻¹
	local handRot = H * (ch.GripC1 * ch.GripC0:Inverse()).Rotation
	local wristT = target + handRot:VectorToWorldSpace(Wr.C1.Position - ch.GripC0.Position)
	local jointS = ch.Torso * S.C0
	local Sp = jointS.Position
	local upper = part1(ch.Torso, S)
	local jointE = upper * E.C0
	local Ep = jointE.Position
	local lower = part1(upper, E)
	local Wp = (lower * Wr.C0).Position
	local a = (Ep - Sp).Magnitude
	local b = (Wp - Ep).Magnitude
	local dvec = wristT - Sp
	local d = math.clamp(dvec.Magnitude, math.abs(a - b) + 0.05, a + b - 0.01)
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
	-- avant-bras : après W1, du coude vers le poignet voulu
	local pivot1 = CFrame.new(Sp) * W1 * CFrame.new(-Sp)
	local upper1 = pivot1 * upper
	local W1p = (pivot1 * (lower * Wr.C0)).Position
	local W2 = fromTo(W1p - E2, (Sp + dir * d) - E2)
	local jointE1 = upper1 * E.C0
	out.Elbow = inJoint(jointE1, W2)
	-- poignet : la main prend l'orientation voulue
	local pivot2 = CFrame.new(E2) * W2 * CFrame.new(-E2)
	local lower2 = pivot2 * (pivot1 * lower)
	local hand2 = part1(lower2, Wr)
	local W3 = handRot * hand2.Rotation:Inverse()
	out.Wrist = inJoint(lower2 * Wr.C0, W3)
	return out
end

-- R6 (ou R15 incomplet) : épaule seule ; le bras vise `dir` (son -Y), avec
-- la torsion qui met l'avant du bras (son -Z) au plus près de `front`
local function solveRigid(ch: Chain, dir: Vector3, front: Vector3): CFrame
	local S = ch.Shoulder
	local jointS = ch.Torso * S.C0
	local arm = part1(ch.Torso, S)
	local r1 = fromTo(-arm.UpVector, dir)
	local W = twistAbout(r1:VectorToWorldSpace(arm.LookVector), front, dir) * r1
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
	-- orientation voulue de l'aliment : debout, devant vers l'avant (ou vers
	-- la gauche : le bout +X d'un aliment couché pointe alors vers l'avant)
	local holdLook = if ch.HoldLook == "left" then (flatLook:Cross(UP)).Unit * -1 else flatLook
	local H = frameAim(Vector3.new(0, 1, 0), wantUp, Vector3.new(0, 0, -1), holdLook)
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
		local elbow = Sp + up * (-0.97 * a) + look * (0.2 * a) + right * (0.1 * a)
		local target = elbow + look * (0.93 * b) + up * (-0.08 * b) + right * (-0.2 * b)
		local pole = -up + right * 0.35 - look * 0.25
		return solveArm(ch, target, pole, H)
	end
	-- R6 : bras vers l'avant, 32° sous l'horizontale, à peine rentré
	local dir = (flatLook * math.cos(math.rad(32)) - UP * math.sin(math.rad(32)) - right * 0.08).Unit
	local rot = solveRigid(ch, dir, UP)
	local out: { [string]: CFrame } = { Shoulder = rot }
	-- soudure : redresse l'aliment (son +Y) sur la verticale, face à l'avant
	local jointS = T * S.C0
	local arm1 = jointS * rot * S.X * S.C1:Inverse()
	local gripCF = arm1 * ch.GripC0
	local handle = gripCF * ch.GripC1:Inverse()
	out.Grip = inJoint(gripCF, H * handle.Rotation:Inverse())
	return out
end

-- Geste "à la bouche" (repère de chaque joint) : { Shoulder, Elbow?, Wrist?, Grip? }
-- Point du poing sur la sphère (lèvres, reach), dans le plan (épaule,
-- lèvres, `dir`) : angle θ depuis la direction de l'épaule (θ = 0 : le plus
-- près de l'épaule, π : le plus loin ; la distance croît avec θ). R15
-- (exact = false) : la direction voulue si l'épaule l'atteint (≤ r), sinon
-- le θ le plus proche qui l'atteint ; R6 (exact = true) : le bras est rigide,
-- le poing est À r de l'épaule exactement.
local function reachable(Sp: Vector3, r: number, exact: boolean, lips: Vector3, dir: Vector3, reach: number): Vector3
	local toS = (Sp - lips).Unit
	local perp = dir - toS * dir:Dot(toS)
	if perp.Magnitude < 1e-4 then
		perp = Vector3.new(0, -1, 0) - toS * (-toS.Y)
	end
	perp = perp.Unit
	local function at(theta: number): Vector3
		return lips + (toS * math.cos(theta) + perp * math.sin(theta)) * reach
	end
	local function dist(theta: number): number
		return (at(theta) - Sp).Magnitude
	end
	local want = math.atan2(dir:Dot(perp), dir:Dot(toS))
	local lo, hi = 0, math.pi
	if exact then
		if dist(0) > r then
			return at(0)
		elseif dist(math.pi) < r then
			return at(math.pi)
		end
	else
		if dist(want) <= r then
			return at(want)
		elseif dist(0) > r then
			return at(0)
		end
		hi = want
	end
	for _ = 1, 30 do
		local mid = (lo + hi) / 2
		if dist(mid) <= r then
			lo = mid
		else
			hi = mid
		end
	end
	return at(lo)
end

-- Geste "à la bouche" (repère de chaque joint) : { Shoulder, Elbow?, Wrist?, Grip? }
function FairEat.Solve(ch: Chain): { [string]: CFrame }
	local aim = ch.Aim or Vector3.new(0, ch.Reach or 1.3, 0)
	local lean = ch.Lean or math.rad(30)
	local stand = ch.Stand or 0.22
	local mouth = FairEat.Mouth(ch.Head, ch.HeadSize)
	local look, up = ch.Head.LookVector, ch.Head.UpVector
	local right = ch.Torso.RightVector
	local lips = mouth + look * stand
	-- axe poing -> point visé (repère de la poignée) : poing = poignée * Grip
	local axis = aim - ch.GripC1.Position
	local reach = math.max(0.2, axis.Magnitude)
	-- torsion : aliment debout (axe ~Y) -> son devant vers le visage ;
	-- aliment couché (axe ~X) -> son haut vers le ciel (la garniture en haut)
	local upright = math.abs(axis.Unit.Y) > 0.7
	local secLocal = if upright then Vector3.new(0, 0, -1) else Vector3.new(0, 1, 0)
	local secWorld = if upright then look else UP
	-- le poing sous la bouche, devant et un peu à droite (côté de l'épaule) ;
	-- le point visé (penché de `lean` vers le visage) touche les lèvres. Un
	-- bras de ~1,8 stud n'atteint pas toujours ce poing idéal : on le prend
	-- alors sur la sphère (lèvres, reach) au plus près, à portée de l'épaule
	local side = ch.Side or 0.32
	local dir = (look * math.sin(lean) - up * math.cos(lean) + right * side).Unit
	local S = ch.Shoulder
	local jointS = ch.Torso * S.C0
	local Sp = jointS.Position
	if ch.R15 and ch.Elbow and ch.Wrist then
		local upper = part1(ch.Torso, S)
		local Ep = (upper * ch.Elbow.C0).Position
		local Gp = (part1(part1(upper, ch.Elbow), ch.Wrist) * ch.GripC0).Position
		local maxR = (Ep - Sp).Magnitude + (Gp - Ep).Magnitude - 0.04
		local target = reachable(Sp, maxR, false, lips, dir, reach)
		local pole = ch.Torso.RightVector * 0.8 - Vector3.new(0, 1, 0) - ch.Torso.LookVector * 0.2
		local H = frameAim(axis.Unit, (lips - target).Unit, secLocal, secWorld)
		return solveArm(ch, target, pole, H)
	end
	-- R6 (bras rigide) : le poing est sur une sphère autour de l'épaule ; on
	-- choisit son point, le bras le vise, puis la soudure oriente l'aliment
	local arm = part1(ch.Torso, S)
	local grip0 = (arm * ch.GripC0).Position
	local r = (grip0 - Sp).Magnitude
	local target = reachable(Sp, r, true, lips, dir, reach)
	local W1 = fromTo(grip0 - Sp, target - Sp)
	-- (torsion : l'avant du bras vers le haut, comme une main qui tient)
	W1 = twistAbout(W1:VectorToWorldSpace(arm.LookVector), UP, target - Sp) * W1
	local out: { [string]: CFrame } = { Shoulder = inJoint(jointS, W1) }
	local arm1 = CFrame.new(Sp) * W1 * CFrame.new(-Sp) * arm
	local gripCF = arm1 * ch.GripC0
	local h1 = gripCF * ch.GripC1:Inverse()
	local H = frameAim(axis.Unit, (lips - gripCF.Position).Unit, secLocal, secWorld)
	out.Grip = inJoint(gripCF, H * h1.Rotation:Inverse())
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
	Written: { [Instance]: CFrame }, -- dernier C0 écrit par nous (détecte un C0 refait par le moteur)
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
			local rig: Rig = { Character = character, R15 = full, Torso = torso, Head = head, Shoulder = s, Elbow = if full then e else nil, Wrist = if full then w else nil, Neck = motor(head, "Neck"), Hand = grip, Base = {}, Written = {} }
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
		local rig: Rig = { Character = character, R15 = false, Torso = torso, Head = head, Shoulder = s, Elbow = nil, Wrist = nil, Neck = neck, Hand = arm, Base = { [s] = baseOf(s) }, Written = {} }
		if neck then
			rig.Base[neck] = baseOf(neck)
		end
		return rig
	end
	return nil
end

-- Écrit un C0 (et le retient). Si le C0 actuel n'est ni l'origine ni notre
-- dernière écriture, quelqu'un d'autre l'a refait (mise à l'échelle de
-- l'avatar, rig reconstruit) : c'est la nouvelle origine.
local function write(rig: Rig, j: Instance, rot: CFrame)
	local cur = (j :: any).C0 :: CFrame
	local last = rig.Written[j]
	if last and cur ~= last and cur ~= rig.Base[j] then
		rig.Base[j] = cur
		pcall(function()
			j:SetAttribute(BASE_ATTR, cur)
		end)
	end
	local value = rig.Base[j] * rot
	if cur ~= value then
		(j :: any).C0 = value
	end
	rig.Written[j] = value
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

export type Gesture = { K: number, Reach: number?, Aim: Vector3?, Lean: number?, Stand: number?, Side: number?, Nod: number?, Roll: number?, HoldLook: string? }

-- Pose du bras à chaque image : tenue (poids w, 0..1) + geste vers la bouche
-- (g.K, 0..1). Le cou (g.Nod / g.Roll, rad) penche la tête vers l'aliment.
-- `modelGrip` = la prise dans le repère du MODÈLE de l'aliment (FoodModels.GRIP :
-- Tool.Grip la convertit pour la poignée tournée) : le "haut" visé est celui
-- du modèle, pas celui de la pièce Handle.
function FairEat.Apply(rig: Rig, w: number, g: Gesture?, modelGrip: CFrame?)
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
	local gripC1 = modelGrip or CFrame.identity
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
		Side = g and g.Side,
		Aim = g and g.Aim,
		HoldLook = g and g.HoldLook,
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
			write(rig, m, FairEat.Mix(hold[name], eat[name], w, e))
		end
	end
	if weld and weld.Parent then
		write(rig, weld, FairEat.Mix(hold.Grip, eat.Grip, w, e))
	end
	-- tête : penche vers l'aliment (lécher, croquer)
	local neck = rig.Neck
	if neck and neck.Parent and rig.Base[neck] then
		local nod, roll = (g and g.Nod or 0) * e, (g and g.Roll or 0) * e
		if math.abs(nod) + math.abs(roll) > 1e-4 then
			local jointN = rig.Torso.CFrame * rig.Base[neck]
			local T = rig.Torso.CFrame
			local W = CFrame.fromAxisAngle(T.RightVector, -nod) * CFrame.fromAxisAngle(T.LookVector, roll)
			write(rig, neck, inJoint(jointN, W))
		elseif rig.Written[neck] then
			write(rig, neck, CFrame.identity)
		end
	end
end

function FairEat.Restore(rig: Rig)
	for j, c0 in pairs(rig.Base) do
		local last = rig.Written[j]
		-- (refait entre-temps par le moteur : on n'y touche pas)
		if j.Parent and (j :: any).C0 ~= c0 and (last == nil or (j :: any).C0 == last) then
			(j :: any).C0 = c0
		end
	end
	table.clear(rig.Written)
end

return FairEat
