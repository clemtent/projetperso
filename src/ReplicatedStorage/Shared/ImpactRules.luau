--[[
	ImpactRules (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > ImpactRules

	💥 v10 (PHYS10) : collisions réalistes et "se faire renverser", version
	DESSIN ANIMÉ : on tombe, on voit des étoiles, on se relève. Jamais de mort,
	jamais de perte de vie.

	Module PARTAGÉ (serveur ImpactService + client Knockdown + NPCModels) :
	toutes les règles au même endroit, testables hors Roblox.
	  1. GROUPES DE COLLISION (matrice complète, voir MATRIX) :
	       avatars <-> avatars      : oui
	       avatars <-> voitures     : OUI (v10 ; avant : on traversait les voitures)
	       voitures <-> voitures    : OUI (v10)
	       avatars <-> autos tamponneuses : non (inchangé, la piste a ses rails)
	       "Riders" (qui DESCEND d'une voiture, ~1 s) <-> voitures : non
	         (on ne reste jamais coincé dans la portière)
	       "Ragdoll" (boîtes du corps au sol) : seulement le décor (Default)
	         (ni les voitures, ni les avatars, ni lui-même : pas de coups de
	         pied involontaires, la voiture passe par-dessus)
	  2. SEUILS : une voiture qui touche un piéton à >= 12 studs/s -> il est
	     RENVERSÉ (ragdoll + étoiles + se relève après 2,5 s) ; entre 4,5 et
	     12 -> il TITUBE ; en dessous : simple contact (la collision le pousse).
	     Anti-abus : pas de nouveau renversement moins de 3 s après s'être
	     relevé ; jamais dans une zone sûre (scène de la place, intérieur des
	     boutiques, attribut SafeZone).
	  3. RAGDOLL : échange des Motor6D contre des BallSocket (R15 : charnières
	     pour coudes et genoux ; R6 : épaules et hanches), cou et racine
	     gardés (jamais de mort : la tête reste attachée), boîtes de collision
	     soudées aux membres ; RESTAURATION EXACTE (moteurs, CanCollide,
	     attributs : tout revient comme avant, testé).
	  4. POSES PROCÉDURALES (Motor6D.Transform, comme SitAnimator) : se
	     relever (sur le dos / sur le ventre), tituber. Mêmes fonctions pour
	     l'avatar local et pour les autres joueurs (attributs répliqués).
	  5. PNJ : saut de côté ou bousculade quand une voiture arrive
	     (décalage du corps entier, NPCModels l'applique dans Animate).

	API :
	  ImpactRules.Classify(speed) -> "knock" | "stumble" | nil
	  ImpactRules.Contact(boxCF, boxSize, carVel, charPos, charVel, ahead?)
	      -> (vitesse d'impact | nil, direction horizontale du choc)
	  ImpactRules.Impulse(dir, speed, charVel?) -> (vitesse linéaire, angulaire)
	  ImpactRules.CollectSafeZones(town) / InSafeZone(pos, zones)
	  ImpactRules.Ragdoll(character, { Local = bool }) -> état | nil
	  ImpactRules.Restore(état)
	  ImpactRules.QuietServerRagdoll(character)  (client : neutralise
	      localement le ragdoll du serveur quand on se relève)
	  ImpactRules.RigOf(character) -> rig (Motor6D par clé) | nil
	  ImpactRules.GetUpPose(u, faceUp, pivotH, rig?) / StumblePose(t, lx, lz)
	      (avec le squelette : le corps reste posé sur le sol à chaque instant)
	  ImpactRules.ApplyPose(rig, pose) / ClearPose(rig)
	  ImpactRules.StartNpcReact(model, kind, dir) / NpcReact(model, pivot, now)
]]

local ImpactRules = {}

----------------------------------------------------------------------
-- Groupes de collision
----------------------------------------------------------------------

ImpactRules.WALKER_GROUP = "DopamineWalkers" -- (= CarService.WALKER_GROUP)
ImpactRules.CAR_GROUP = "DopamineCars" -- (= CarService.CAR_GROUP)
ImpactRules.BUMPER_GROUP = "DopamineBumper" -- (= TownFair.BUMPER_GROUP)
ImpactRules.RIDER_GROUP = "DopamineRiders" -- (v10) on descend d'une voiture
ImpactRules.RAGDOLL_GROUP = "DopamineRagdoll" -- (v10) boîtes du corps au sol

-- Paires réglées explicitement (toute autre paire : collision, défaut Roblox)
ImpactRules.MATRIX = {
	{ "DopamineWalkers", "DopamineCars", true },
	{ "DopamineCars", "DopamineCars", true },
	{ "DopamineWalkers", "DopamineBumper", false },
	{ "DopamineBumper", "DopamineBumper", true },
	{ "DopamineRiders", "DopamineCars", false },
	{ "DopamineRiders", "DopamineBumper", false },
	{ "DopamineRagdoll", "DopamineRagdoll", false },
	{ "DopamineRagdoll", "DopamineWalkers", false },
	{ "DopamineRagdoll", "DopamineCars", false },
	{ "DopamineRagdoll", "DopamineRiders", false },
	{ "DopamineRagdoll", "DopamineBumper", false },
}

-- La paire (a, b) entre-t-elle en collision d'après la matrice ?
function ImpactRules.Collides(a: string, b: string): boolean
	for _, row in ipairs(ImpactRules.MATRIX) do
		if (row[1] == a and row[2] == b) or (row[1] == b and row[2] == a) then
			return row[3]
		end
	end
	return true
end

-- (serveur) enregistre les groupes v10 et applique la matrice (sans erreur
-- si un groupe existe déjà)
function ImpactRules.SetupGroups(physics: any)
	for _, name in ipairs({ ImpactRules.WALKER_GROUP, ImpactRules.CAR_GROUP, ImpactRules.BUMPER_GROUP, ImpactRules.RIDER_GROUP, ImpactRules.RAGDOLL_GROUP }) do
		pcall(function()
			if not physics:IsCollisionGroupRegistered(name) then
				physics:RegisterCollisionGroup(name)
			end
		end)
	end
	for _, row in ipairs(ImpactRules.MATRIX) do
		pcall(function()
			physics:CollisionGroupSetCollidable(row[1], row[2], row[3])
		end)
	end
end

----------------------------------------------------------------------
-- Seuils et temps
----------------------------------------------------------------------

ImpactRules.KNOCK_SPEED = 12 -- (studs/s) choc au-delà : renversé
ImpactRules.STUMBLE_SPEED = 4.5 -- (studs/s) choc au-delà : on titube
ImpactRules.KNOCK_TIME = 2.5 -- (s) au sol avant de se relever
ImpactRules.GETUP_TIME = 1.25 -- (s) animation "se relever"
ImpactRules.STUMBLE_TIME = 0.8 -- (s) animation "tituber"
ImpactRules.COOLDOWN = 3 -- (s) après s'être relevé : pas de nouveau renversement
ImpactRules.STUMBLE_COOLDOWN = 1 -- (s) entre deux titubements
ImpactRules.MAX_SPEED = 100 -- (studs/s) au-delà : impossible (rapport client refusé ; autoroute 85)
ImpactRules.FAILSAFE = 6 -- (s) au plus au sol (le serveur relève d'office)
ImpactRules.CHAR_RADIUS = 1.1 -- (studs) rayon de l'avatar (capsule)

function ImpactRules.Classify(speed: number): string?
	if type(speed) ~= "number" or speed ~= speed then
		return nil
	end
	if speed >= ImpactRules.KNOCK_SPEED then
		return "knock"
	elseif speed >= ImpactRules.STUMBLE_SPEED then
		return "stumble"
	end
	return nil
end

-- Contact entre une boîte de voiture (centre boxCF, taille boxSize, avant = -Z)
-- et un avatar (position du HumanoidRootPart). `ahead` : marge d'anticipation
-- (studs) devant la voiture dans le sens de sa vitesse.
-- Renvoie (vitesse d'impact > 0, direction horizontale du choc) ou nil.
function ImpactRules.Contact(boxCF: CFrame, boxSize: Vector3, carVel: Vector3, charPos: Vector3, charVel: Vector3?, ahead: number?): (number?, Vector3?)
	local rel = boxCF:PointToObjectSpace(charPos)
	local hx, hy, hz = boxSize.X / 2, boxSize.Y / 2, boxSize.Z / 2
	local r = ImpactRules.CHAR_RADIUS
	-- hauteur : le corps va de ~3 studs sous le HRP à ~2,5 au-dessus
	if rel.Y < -hy - 2.6 or rel.Y > hy + 3.2 then
		return nil, nil
	end
	local vLocal = boxCF:VectorToObjectSpace(carVel)
	local extra = math.max(0, ahead or 0)
	-- la marge d'anticipation s'ajoute du côté où va la voiture
	local zMin, zMax = -hz - r, hz + r
	if vLocal.Z < 0 then
		zMin -= extra
	else
		zMax += extra
	end
	local xMin, xMax = -hx - r, hx + r
	if vLocal.X < 0 then
		xMin -= extra * 0.5
	else
		xMax += extra * 0.5
	end
	if rel.X < xMin or rel.X > xMax or rel.Z < zMin or rel.Z > zMax then
		return nil, nil
	end
	-- face touchée : la plus proche (en tenant compte des demi-tailles)
	local dx = math.abs(rel.X) - hx
	local dz = math.abs(rel.Z) - hz
	local nLocal: Vector3
	if dz >= dx then
		nLocal = Vector3.new(0, 0, if rel.Z < 0 then -1 else 1)
	else
		nLocal = Vector3.new(if rel.X < 0 then -1 else 1, 0, 0)
	end
	local n = boxCF:VectorToWorldSpace(nLocal)
	n = Vector3.new(n.X, 0, n.Z)
	if n.Magnitude < 1e-3 then
		return nil, nil
	end
	n = n.Unit
	local cv = charVel or Vector3.zero
	local relVel = Vector3.new(carVel.X - cv.X, 0, carVel.Z - cv.Z)
	local closing = relVel:Dot(n)
	if closing <= 0 then
		return nil, nil
	end
	-- direction du vol : surtout le sens de la voiture, un peu vers l'extérieur
	local flat = Vector3.new(carVel.X, 0, carVel.Z)
	local dir = if flat.Magnitude > 0.5 then (flat.Unit * 0.7 + n * 0.3) else n
	if dir.Magnitude < 1e-3 then
		dir = n
	end
	return closing, dir.Unit
end

-- Élan donné au corps renversé : (vitesse linéaire, vitesse angulaire)
function ImpactRules.Impulse(dir: Vector3, speed: number, charVel: Vector3?): (Vector3, Vector3)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local u = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local s = math.clamp(speed, 0, ImpactRules.MAX_SPEED)
	local horizontal = math.clamp(0.9 * s, 10, 38)
	local up = math.clamp(14 + 0.8 * s, 20, 42)
	local base = charVel and Vector3.new(charVel.X, 0, charVel.Z) * 0.3 or Vector3.zero
	local linear = base + u * horizontal + Vector3.new(0, up, 0)
	-- culbute : autour de l'axe horizontal perpendiculaire au choc
	local axis = Vector3.new(0, 1, 0):Cross(u)
	local spin = axis * math.clamp(s * 0.25, 3, 9)
	return linear, spin
end

-- Petit élan d'un titubement
function ImpactRules.StumblePush(dir: Vector3, speed: number): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local u = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	return u * math.clamp(4 + 0.8 * speed, 6, 14) + Vector3.new(0, 7, 0)
end

-- Temps de recharge (état par personnage : KnockAt, UpAt, StumbleAt)
function ImpactRules.CanKnock(st: any, now: number): boolean
	if type(st) ~= "table" then
		return true
	end
	if st.Down then
		return false
	end
	if st.UpAt and now - st.UpAt < ImpactRules.COOLDOWN then
		return false
	end
	if st.KnockAt and now - st.KnockAt < ImpactRules.KNOCK_TIME + ImpactRules.GETUP_TIME + ImpactRules.COOLDOWN and not st.UpAt then
		return false
	end
	return true
end

function ImpactRules.CanStumble(st: any, now: number): boolean
	if type(st) ~= "table" then
		return true
	end
	if st.Down then
		return false
	end
	if st.StumbleAt and now - st.StumbleAt < ImpactRules.STUMBLE_COOLDOWN then
		return false
	end
	if st.UpAt and now - st.UpAt < ImpactRules.GETUP_TIME then
		return false
	end
	return true
end

----------------------------------------------------------------------
-- Zones sûres
----------------------------------------------------------------------

export type Zone = { CF: CFrame, Size: Vector3 }

-- Boîtes (centre, taille) : intérieurs des boutiques (InteriorCF / InteriorSize,
-- repère au sol), scène de musique (StageCF, 24 x 16), et tout ce qui porte
-- l'attribut SafeZone = true (BasePart : sa boîte ; Model : SafeZoneCF /
-- SafeZoneSize, sinon sa boîte englobante).
function ImpactRules.CollectSafeZones(town: Instance?): { Zone }
	local zones: { Zone } = {}
	if not town then
		return zones
	end
	for _, d in ipairs(town:GetDescendants()) do
		local ok = pcall(function()
			local icf = d:GetAttribute("InteriorCF")
			local isize = d:GetAttribute("InteriorSize")
			if typeof(icf) == "CFrame" and typeof(isize) == "Vector3" then
				table.insert(zones, { CF = icf * CFrame.new(0, isize.Y / 2, 0), Size = isize + Vector3.new(1, 2, 1) })
			end
			local stage = d:GetAttribute("StageCF")
			if typeof(stage) == "CFrame" then
				table.insert(zones, { CF = stage * CFrame.new(0, 6, 0), Size = Vector3.new(28, 16, 20) })
			end
			if d:GetAttribute("SafeZone") == true then
				if d:IsA("BasePart") then
					table.insert(zones, { CF = d.CFrame, Size = d.Size })
				elseif d:IsA("Model") then
					local zcf = d:GetAttribute("SafeZoneCF")
					local zsize = d:GetAttribute("SafeZoneSize")
					if typeof(zcf) == "CFrame" and typeof(zsize) == "Vector3" then
						table.insert(zones, { CF = zcf, Size = zsize })
					else
						local cf, size = d:GetBoundingBox()
						table.insert(zones, { CF = cf, Size = size })
					end
				end
			end
		end)
		if not ok then
			continue
		end
	end
	return zones
end

function ImpactRules.InSafeZone(pos: Vector3, zones: { Zone }?): boolean
	for _, z in ipairs(zones or {}) do
		local p = z.CF:PointToObjectSpace(pos)
		if math.abs(p.X) <= z.Size.X / 2 and math.abs(p.Y) <= z.Size.Y / 2 and math.abs(p.Z) <= z.Size.Z / 2 then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Ragdoll (échange des Motor6D) + restauration exacte
----------------------------------------------------------------------

-- Articulations libérées (les autres : racine, cou, accessoires, restent)
-- Ball : cône (UpperAngle) + torsion ; Hinge : charnière autour de X
-- (angle positif = rotation +X : coude qui plie vers l'avant, genou négatif)
ImpactRules.JOINTS = {
	-- R15
	Waist = { Kind = "Ball", Up = 25, TwLo = -20, TwHi = 20 },
	LeftShoulder = { Kind = "Ball", Up = 80, TwLo = -50, TwHi = 50 },
	RightShoulder = { Kind = "Ball", Up = 80, TwLo = -50, TwHi = 50 },
	LeftElbow = { Kind = "Hinge", Lo = -2, Hi = 120 },
	RightElbow = { Kind = "Hinge", Lo = -2, Hi = 120 },
	LeftWrist = { Kind = "Ball", Up = 25, TwLo = -10, TwHi = 10 },
	RightWrist = { Kind = "Ball", Up = 25, TwLo = -10, TwHi = 10 },
	LeftHip = { Kind = "Ball", Up = 50, TwLo = -15, TwHi = 15 },
	RightHip = { Kind = "Ball", Up = 50, TwLo = -15, TwHi = 15 },
	LeftKnee = { Kind = "Hinge", Lo = -120, Hi = 2 },
	RightKnee = { Kind = "Hinge", Lo = -120, Hi = 2 },
	LeftAnkle = { Kind = "Ball", Up = 20, TwLo = -10, TwHi = 10 },
	RightAnkle = { Kind = "Ball", Up = 20, TwLo = -10, TwHi = 10 },
	-- R6
	["Left Shoulder"] = { Kind = "Ball", Up = 85, TwLo = -45, TwHi = 45 },
	["Right Shoulder"] = { Kind = "Ball", Up = 85, TwLo = -45, TwHi = 45 },
	["Left Hip"] = { Kind = "Ball", Up = 55, TwLo = -15, TwHi = 15 },
	["Right Hip"] = { Kind = "Ball", Up = 55, TwLo = -15, TwHi = 15 },
}

ImpactRules.TAG_SERVER = "DopaRagdoll"
ImpactRules.TAG_LOCAL = "DopaRagdollL"

export type RagdollState = {
	Character: Model,
	Tag: string,
	Motors: { { Motor: Motor6D, Enabled: boolean, Attr: any } },
	Created: { Instance },
	Collide: { { Part: BasePart, CanCollide: boolean } },
	Active: boolean,
}

local function isBodyPart(character: Model, part: Instance?): boolean
	return part ~= nil and part:IsA("BasePart") and part.Parent == character and part.Name ~= "HumanoidRootPart"
end

-- Le personnage est-il déjà en ragdoll (moteurs coupés par NOUS ou le serveur) ?
function ImpactRules.IsRagdolled(character: Model?): boolean
	if not character then
		return false
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") and ImpactRules.JOINTS[d.Name] and not d.Enabled then
			return true
		end
	end
	return false
end

function ImpactRules.Ragdoll(character: Model, opts: any?): RagdollState?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local isLocal = type(opts) == "table" and opts.Local == true
	local tag = if isLocal then ImpactRules.TAG_LOCAL else ImpactRules.TAG_SERVER
	local state: RagdollState = { Character = character, Tag = tag, Motors = {}, Created = {}, Collide = {}, Active = true }
	local body: { [BasePart]: boolean } = {}
	local ok, err = pcall(function()
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("Motor6D") then
				local spec = ImpactRules.JOINTS[d.Name]
				local p0, p1 = d.Part0, d.Part1
				if isBodyPart(character, p0) or (p0 and p0.Name == "HumanoidRootPart") then
					if isBodyPart(character, p0) then
						body[p0 :: BasePart] = true
					end
				end
				if isBodyPart(character, p1) then
					body[p1 :: BasePart] = true
				end
				if spec and d.Enabled and p0 and p1 then
					local a0 = Instance.new("Attachment")
					a0.Name = tag
					a0.CFrame = d.C0
					a0.Parent = p0
					local a1 = Instance.new("Attachment")
					a1.Name = tag
					a1.CFrame = d.C1
					a1.Parent = p1
					local c: Constraint
					if spec.Kind == "Hinge" then
						local h = Instance.new("HingeConstraint")
						h.LimitsEnabled = true
						h.LowerAngle = spec.Lo
						h.UpperAngle = spec.Hi
						h.Restitution = 0
						c = h
					else
						local b = Instance.new("BallSocketConstraint")
						b.LimitsEnabled = true
						b.UpperAngle = spec.Up
						b.TwistLimitsEnabled = true
						b.TwistLowerAngle = spec.TwLo
						b.TwistUpperAngle = spec.TwHi
						b.MaxFrictionTorque = 4
						b.Restitution = 0
						c = b
					end
					c.Name = tag
					c.Attachment0 = a0
					c.Attachment1 = a1
					c.Parent = p1
					table.insert(state.Created, c)
					table.insert(state.Created, a0)
					table.insert(state.Created, a1)
					table.insert(state.Motors, { Motor = d, Enabled = d.Enabled, Attr = d:GetAttribute("DopaRagdollOff") })
					if not isLocal then
						d:SetAttribute("DopaRagdollOff", true)
					end
					d.Enabled = false
				end
			end
		end
		-- boîtes de collision du corps (groupe Ragdoll : décor seulement)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(state.Collide, { Part = root, CanCollide = root.CanCollide })
			root.CanCollide = false
		end
		for part in pairs(body) do
			table.insert(state.Collide, { Part = part, CanCollide = part.CanCollide })
			part.CanCollide = false
			local box = Instance.new("Part")
			box.Name = tag
			box.Size = Vector3.new(math.max(0.25, part.Size.X * 0.85), math.max(0.25, part.Size.Y * 0.85), math.max(0.25, part.Size.Z * 0.85))
			box.CFrame = part.CFrame
			box.Transparency = 1
			box.CastShadow = false
			box.CanCollide = true
			box.CanQuery = false
			box.CanTouch = false
			box.Massless = true
			box.Anchored = false
			box:SetAttribute("KeepGroup", true) -- (CarService.tagWalker ne le remet pas en "Walkers")
			pcall(function()
				box.CollisionGroup = ImpactRules.RAGDOLL_GROUP
			end)
			local weld = Instance.new("WeldConstraint")
			weld.Name = tag
			weld.Part0 = part
			weld.Part1 = box
			weld.Parent = box
			box.Parent = part
			table.insert(state.Created, box)
		end
	end)
	if not ok then
		-- (jamais à moitié : tout est remis)
		ImpactRules.Restore(state)
		warn("[ImpactRules] Ragdoll : " .. tostring(err))
		return nil
	end
	return state
end

function ImpactRules.Restore(state: RagdollState?)
	if not state or not state.Active then
		return
	end
	state.Active = false
	for i = #state.Created, 1, -1 do
		local inst = state.Created[i]
		pcall(inst.Destroy, inst)
	end
	table.clear(state.Created)
	for _, m in ipairs(state.Motors) do
		pcall(function()
			m.Motor.Enabled = m.Enabled
			if state.Tag == ImpactRules.TAG_SERVER then
				m.Motor:SetAttribute("DopaRagdollOff", m.Attr)
			end
		end)
	end
	for _, c in ipairs(state.Collide) do
		pcall(function()
			c.Part.CanCollide = c.CanCollide
		end)
	end
end

-- (client) en se relevant avant que le serveur ait fini : on neutralise
-- LOCALEMENT son ragdoll (contraintes et boîtes coupées, moteurs remis) ;
-- le serveur le détruit juste après. Renvoie le nombre de pièces touchées.
function ImpactRules.QuietServerRagdoll(character: Model?): number
	if not character then
		return 0
	end
	local n = 0
	for _, d in ipairs(character:GetDescendants()) do
		if d.Name == ImpactRules.TAG_SERVER then
			if d:IsA("Constraint") then
				d.Enabled = false
				n += 1
			elseif d:IsA("BasePart") then
				d.CanCollide = false
				n += 1
			end
		elseif d:IsA("Motor6D") and d:GetAttribute("DopaRagdollOff") == true and not d.Enabled then
			d.Enabled = true
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- Poses procédurales (Motor6D.Transform)
----------------------------------------------------------------------

-- clé -> { nom R15, nom R6 }
local KEYS = {
	Root = { "Root", "RootJoint" },
	Waist = { "Waist", "" },
	Neck = { "Neck", "Neck" },
	LShoulder = { "LeftShoulder", "Left Shoulder" },
	RShoulder = { "RightShoulder", "Right Shoulder" },
	LElbow = { "LeftElbow", "" },
	RElbow = { "RightElbow", "" },
	LHip = { "LeftHip", "Left Hip" },
	RHip = { "RightHip", "Right Hip" },
	LKnee = { "LeftKnee", "" },
	RKnee = { "RightKnee", "" },
}
ImpactRules.POSE_KEYS = KEYS

export type Link = { Motor: Motor6D, Key: string?, Part0: BasePart, Part1: BasePart, C0: CFrame, C1Inv: CFrame, Half: Vector3 }
export type Rig = {
	R6: boolean,
	Motors: { [string]: Motor6D },
	Rot: { [string]: CFrame },
	Chain: { Link },
	StandY: number, -- centre du HRP au-dessus du sol, debout (d'après le squelette)
	PivotH: number, -- pivot de la racine au-dessus du sol, debout
	Character: Model,
}

-- Moteurs du personnage par clé + chaîne complète (HRP -> membres, pour poser
-- le corps AU SOL quelle que soit la pose) + hauteurs debout
function ImpactRules.RigOf(character: Model?): Rig?
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local byName: { [string]: Motor6D } = {}
	local all: { Motor6D } = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") then
			if not byName[d.Name] then
				byName[d.Name] = d
			end
			table.insert(all, d)
		end
	end
	local motors: { [string]: Motor6D } = {}
	local rot: { [string]: CFrame } = {}
	local keyOf: { [Motor6D]: string } = {}
	for key, names in pairs(KEYS) do
		local name = if r6 then names[2] else names[1]
		local m = name ~= "" and byName[name] or nil
		if m then
			motors[key] = m
			rot[key] = m.C0.Rotation
			keyOf[m] = key
		end
	end
	if not motors.Root then
		return nil
	end
	-- chaîne depuis le HRP (ordre : parent avant enfant), pièces du corps seulement
	local chain: { Link } = {}
	local reached: { [BasePart]: boolean } = { [root :: BasePart] = true }
	for _ = 1, 12 do
		local grew = false
		for _, m in ipairs(all) do
			local p0, p1 = m.Part0, m.Part1
			if p0 and p1 and reached[p0] and not reached[p1] and p1.Parent == character then
				reached[p1] = true
				grew = true
				table.insert(chain, { Motor = m, Key = keyOf[m], Part0 = p0, Part1 = p1, C0 = m.C0, C1Inv = m.C1:Inverse(), Half = p1.Size / 2 })
			end
		end
		if not grew then
			break
		end
	end
	local rig: Rig = { R6 = r6, Motors = motors, Rot = rot, Chain = chain, StandY = 3, PivotH = 2.6, Character = character }
	-- hauteur debout : le point le plus bas du corps au repos touche le sol
	local low = ImpactRules.LowestPoint(rig, nil)
	rig.StandY = if low < -0.5 then -low else (if r6 then 3 else humanoid.HipHeight + root.Size.Y / 2)
	rig.PivotH = math.max(0.8, rig.StandY + (if motors.Root.Part0 == root then motors.Root.C0.Position.Y else 0))
	return rig
end

-- Point le plus bas du corps (repère du HRP, HRP à l'origine) pour une pose
-- (nil = repos). Sert à garder le corps posé sur le sol.
function ImpactRules.LowestPoint(rig: Rig, pose: { [string]: CFrame }?): number
	local frames: { [BasePart]: CFrame } = {}
	local lowest = math.huge
	for _, link in ipairs(rig.Chain) do
		local f0 = frames[link.Part0] or CFrame.identity
		local t = CFrame.identity
		if pose and link.Key and pose[link.Key] then
			t = ImpactRules.ToTransform(rig.Rot[link.Key :: string], pose[link.Key :: string])
		end
		local f1 = f0 * link.C0 * t * link.C1Inv
		frames[link.Part1] = f1
		local h = link.Half
		local y = f1.Position.Y - (math.abs(f1.RightVector.Y) * h.X + math.abs(f1.UpVector.Y) * h.Y + math.abs(f1.LookVector.Y) * h.Z)
		if y < lowest then
			lowest = y
		end
	end
	return if lowest == math.huge then -3 else lowest
end

local rad = math.rad
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Images clés (degrés ; tangage + = rotation +X : pour le corps, tête vers
-- l'ARRIÈRE ; pour un membre qui pend, vers l'AVANT). h = hauteur du pivot :
-- nombre < 0 -> absolu (studs, -h) ; sinon fraction de la hauteur debout.
type Key = { u: number, root: number, h: number, hip: number, knee: number, sh: number, abd: number, elbow: number, waist: number, neck: number }
local GETUP_BACK: { Key } = {
	{ u = 0, root = 90, h = -0.55, hip = 0, knee = 0, sh = 0, abd = 25, elbow = 10, waist = 0, neck = 0 },
	{ u = 0.22, root = 86, h = -0.6, hip = 75, knee = 115, sh = -35, abd = 20, elbow = 20, waist = 0, neck = -25 },
	{ u = 0.5, root = -22, h = 0.42, hip = 105, knee = 125, sh = 45, abd = 12, elbow = 30, waist = -12, neck = -8 },
	{ u = 0.76, root = -9, h = 0.8, hip = 45, knee = 55, sh = 18, abd = 8, elbow = 20, waist = -4, neck = 0 },
	{ u = 1, root = 0, h = 1, hip = 0, knee = 0, sh = 0, abd = 0, elbow = 0, waist = 0, neck = 0 },
}
local GETUP_FRONT: { Key } = {
	{ u = 0, root = -90, h = -0.55, hip = 0, knee = 0, sh = 0, abd = 25, elbow = 10, waist = 0, neck = 0 },
	{ u = 0.25, root = -68, h = -0.95, hip = 0, knee = 0, sh = 68, abd = 10, elbow = 5, waist = 0, neck = 20 },
	{ u = 0.5, root = -32, h = 0.45, hip = 82, knee = 100, sh = 40, abd = 10, elbow = 15, waist = -8, neck = 10 },
	{ u = 0.76, root = -10, h = 0.8, hip = 40, knee = 50, sh = 15, abd = 6, elbow = 12, waist = -3, neck = 0 },
	{ u = 1, root = 0, h = 1, hip = 0, knee = 0, sh = 0, abd = 0, elbow = 0, waist = 0, neck = 0 },
}
ImpactRules.GETUP_BACK = GETUP_BACK
ImpactRules.GETUP_FRONT = GETUP_FRONT

local function keyAt(keys: { Key }, u: number): Key
	u = math.clamp(u, 0, 1)
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if u >= keys[i].u and u <= keys[i + 1].u then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	local k = smooth((u - a.u) / math.max(1e-6, b.u - a.u))
	local out: any = { u = u }
	for name, value in pairs(a :: any) do
		if name ~= "u" then
			local bv = (b :: any)[name]
			out[name] = value + (bv - value) * k
		end
	end
	-- hauteur : absolue et fraction ne se mélangent pas -> on passe par des studs
	return out :: Key
end

export type Pose = { [string]: CFrame }

local function heightOf(h: number, pivotH: number): number
	return if h < 0 then -h else h * pivotH
end

-- Pose "se relever" à l'avancement u (0 = allongé, 1 = debout) ; faceUp = sur
-- le dos ; pivotH = hauteur du pivot de la racine debout. Rotations dans le
-- repère du personnage (voir ApplyPose pour la conversion en Transform).
function ImpactRules.GetUpPose(u: number, faceUp: boolean, pivotH: number, rig: Rig?): Pose
	local keys = if faceUp then GETUP_BACK else GETUP_FRONT
	local k = keyAt(keys, u)
	-- hauteur en studs, interpolée entre les deux clés voisines
	local lo, hi = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if u >= keys[i].u and u <= keys[i + 1].u then
			lo, hi = keys[i], keys[i + 1]
			break
		end
	end
	local kk = smooth((math.clamp(u, 0, 1) - lo.u) / math.max(1e-6, hi.u - lo.u))
	local h = heightOf(lo.h, pivotH) + (heightOf(hi.h, pivotH) - heightOf(lo.h, pivotH)) * kk
	local pose: Pose = {}
	local rootRot = CFrame.Angles(rad(k.root), 0, 0)
	pose.Root = CFrame.new(0, h - pivotH, 0) * rootRot
	pose.Waist = CFrame.Angles(rad(k.waist), 0, 0)
	pose.Neck = CFrame.Angles(rad(k.neck), 0, 0)
	pose.LShoulder = CFrame.Angles(rad(k.sh), 0, rad(-k.abd))
	pose.RShoulder = CFrame.Angles(rad(k.sh), 0, rad(k.abd))
	pose.LElbow = CFrame.Angles(rad(k.elbow), 0, 0)
	pose.RElbow = CFrame.Angles(rad(k.elbow), 0, 0)
	pose.LHip = CFrame.Angles(rad(k.hip), 0, rad(-3 * (1 - math.clamp(u, 0, 1))))
	pose.RHip = CFrame.Angles(rad(k.hip), 0, rad(3 * (1 - math.clamp(u, 0, 1))))
	pose.LKnee = CFrame.Angles(rad(-k.knee), 0, 0)
	pose.RKnee = CFrame.Angles(rad(-k.knee), 0, 0)
	if rig then
		-- (squelette connu) le corps reste POSÉ sur le sol à chaque instant :
		-- le point le plus bas touche le sol (quelle que soit la taille de l'avatar)
		pose.Root = rootRot
		local low = ImpactRules.LowestPoint(rig, pose)
		pose.Root = CFrame.new(0, -(rig.StandY + low), 0) * rootRot
	end
	return pose
end

-- Pose "tituber" à t secondes ; (lx, lz) = direction de la poussée dans le
-- repère du personnage (avant = -Z). Le haut du corps "reste en arrière",
-- les bras battent l'air, puis tout revient (amorti).
function ImpactRules.StumblePose(t: number, lx: number, lz: number): Pose
	local T = ImpactRules.STUMBLE_TIME
	local x = math.clamp(t / T, 0, 1)
	local env = math.sin(math.pi * math.min(1, x * 1.6)) * (1 - smooth((x - 0.5) / 0.5) * 0.9)
	if x >= 1 then
		env = 0
	end
	local wob = math.cos(t * 16) * 0.35 + 0.65
	local amp = rad(22) * env * wob
	local pitch = -lz * amp
	local roll = lx * amp
	local arms = rad(115) * env
	local flap = math.sin(t * 22) * rad(25) * env
	local pose: Pose = {}
	pose.Root = CFrame.Angles(pitch, 0, roll)
	pose.Waist = CFrame.Angles(pitch * 0.4, 0, roll * 0.4)
	pose.Neck = CFrame.Angles(-pitch * 0.5, 0, 0)
	pose.LShoulder = CFrame.Angles(arms * 0.6 + flap, 0, -arms * 0.55)
	pose.RShoulder = CFrame.Angles(arms * 0.6 - flap, 0, arms * 0.55)
	pose.LElbow = CFrame.Angles(rad(40) * env, 0, 0)
	pose.RElbow = CFrame.Angles(rad(40) * env, 0, 0)
	pose.LHip = CFrame.Angles(rad(18) * env, 0, 0)
	pose.RHip = CFrame.Angles(rad(-10) * env, 0, 0)
	pose.LKnee = CFrame.Angles(rad(-25) * env, 0, 0)
	pose.RKnee = CFrame.Angles(rad(-12) * env, 0, 0)
	return pose
end

-- Transform d'un moteur pour une rotation `r` exprimée dans le repère du
-- personnage (au repos, tous les membres sont alignés sur le personnage) :
-- T = rot(C0)⁻¹ · r · rot(C0)  (R15 : C0 sans rotation ; R6 : C0 tournés)
function ImpactRules.ToTransform(rot0: CFrame, r: CFrame): CFrame
	return rot0:Inverse() * r * rot0
end

function ImpactRules.ApplyPose(rig: Rig, pose: Pose)
	for key, value in pairs(pose) do
		local m = rig.Motors[key]
		if m then
			m.Transform = ImpactRules.ToTransform(rig.Rot[key], value)
		end
	end
end

function ImpactRules.ClearPose(rig: Rig)
	for _, m in pairs(rig.Motors) do
		pcall(function()
			m.Transform = CFrame.identity
		end)
	end
end

-- Nouveau repère du HumanoidRootPart pour se relever : debout, à l'endroit où
-- est le bassin, regard vers les pieds (sur le dos) ou vers la tête (ventre).
-- torsoCF : buste (UpperTorso / Torso) ; pivotW : pivot de la racine (monde) ;
-- groundY : sol sous le corps ; c0 : Root.C0 (repère du HRP) ; standY : hauteur
-- du centre du HRP debout. Renvoie (CFrame du HRP, faceUp).
function ImpactRules.StandFrame(torsoCF: CFrame, pivotW: Vector3, groundY: number, c0: CFrame, standY: number): (CFrame, boolean)
	local faceUp = torsoCF.LookVector.Y > 0
	local head = Vector3.new(torsoCF.UpVector.X, 0, torsoCF.UpVector.Z)
	if head.Magnitude < 0.05 then
		-- (buste presque debout : on garde son regard)
		head = -Vector3.new(torsoCF.LookVector.X, 0, torsoCF.LookVector.Z)
		if head.Magnitude < 0.05 then
			head = Vector3.new(0, 0, 1)
		end
	end
	head = head.Unit
	local look = if faceUp then -head else head
	local rotation = CFrame.lookAt(Vector3.zero, look)
	local offset = rotation * Vector3.new(c0.Position.X, 0, c0.Position.Z)
	local pos = Vector3.new(pivotW.X - offset.X, groundY + standY, pivotW.Z - offset.Z)
	return CFrame.new(pos) * rotation, faceUp
end

----------------------------------------------------------------------
-- Circulation : freiner pour les piétons (TownTraffic, LAYOUT10)
----------------------------------------------------------------------

ImpactRules.BRAKE_COMFORT = 12 -- (studs/s²) freinage normal (~0,35 g)
ImpactRules.BRAKE_EMERGENCY = 28 -- (studs/s²) freinage d'urgence (~0,8 g)
ImpactRules.STOP_MARGIN = 3.5 -- (studs) on s'arrête à cette distance du piéton
ImpactRules.REACTION = 0.25 -- (s) temps de réaction du conducteur

-- Distance de détection devant la voiture (studs) : de quoi s'arrêter en
-- freinage normal, plus une marge ; bornée (voie visible)
function ImpactRules.BrakeLookahead(speed: number): number
	local v = math.max(0, speed)
	return math.min(160, 8 + v * ImpactRules.REACTION * 2 + v * v / (2 * ImpactRules.BRAKE_COMFORT))
end

-- `free` = distance libre (pare-chocs -> piéton, studs). Renvoie (vitesse
-- visée, accélération voulue | nil, urgence). La décélération demandée est
-- celle qui arrête la voiture STOP_MARGIN avant le piéton (v² / 2d) : en
-- douceur quand on le voit de loin ; freinage d'URGENCE (borné à
-- BRAKE_EMERGENCY) quand il surgit tout près, ce qui ne suffit pas s'il saute
-- devant la voiture au dernier moment (voulu : on se fait renverser).
-- accélération nil = rien à faire pour lui (la conduite normale décide).
function ImpactRules.BrakeTarget(free: number, speed: number, cruise: number): (number, number?, boolean)
	local room = free - ImpactRules.STOP_MARGIN
	local v = math.max(0, speed)
	if room <= 0.05 then
		return 0, -ImpactRules.BRAKE_EMERGENCY, v > 0.5
	end
	local need = v * v / (2 * room)
	local target = math.min(cruise, math.sqrt(2 * ImpactRules.BRAKE_COMFORT * room))
	if need < ImpactRules.BRAKE_COMFORT * 0.3 then
		-- (encore loin : on ne fait que plafonner la vitesse)
		return target, nil, false
	end
	local urgent = need > ImpactRules.BRAKE_COMFORT
	return target, -math.min(need * 1.1, ImpactRules.BRAKE_EMERGENCY), urgent
end

----------------------------------------------------------------------
-- PNJ : saut de côté / bousculade (décalage appliqué par NPCModels.Animate)
----------------------------------------------------------------------

ImpactRules.NPC_DODGE_TIME = 1.5
ImpactRules.NPC_BUMP_TIME = 2.0

-- (client) déclenche une réaction ; dir = direction du mouvement du PNJ (monde)
function ImpactRules.StartNpcReact(model: Model, kind: string, dir: Vector3, now: number?)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	model:SetAttribute("NpcReactKind", if kind == "bump" then "bump" else "dodge")
	model:SetAttribute("NpcReactDir", flat.Unit)
	model:SetAttribute("NpcReactT", now or os.clock())
end

-- En réaction ? (pour ne pas relancer)
function ImpactRules.NpcReacting(model: Model, now: number): boolean
	local t0 = model:GetAttribute("NpcReactT")
	if type(t0) ~= "number" then
		return false
	end
	local kind = model:GetAttribute("NpcReactKind")
	local T = if kind == "bump" then ImpactRules.NPC_BUMP_TIME else ImpactRules.NPC_DODGE_TIME
	return now - t0 < T + 0.4
end

-- Décalage du corps (repère du pivot), capsule solide ?, anim imposée ?
-- (nil quand il n'y a rien à faire : NPCModels garde sa pose normale)
function ImpactRules.NpcReact(model: Model, pivot: CFrame, now: number): (CFrame?, boolean, string?)
	local t0 = model:GetAttribute("NpcReactT")
	if type(t0) ~= "number" then
		return nil, true, nil
	end
	local t = now - t0
	local kind = model:GetAttribute("NpcReactKind")
	local dirW = model:GetAttribute("NpcReactDir")
	if typeof(dirW) ~= "Vector3" or t < 0 then
		return nil, true, nil
	end
	local v = pivot:VectorToObjectSpace(dirW)
	v = Vector3.new(v.X, 0, v.Z)
	if v.Magnitude < 1e-3 then
		return nil, true, nil
	end
	v = v.Unit
	local axis = Vector3.new(0, 1, 0):Cross(v).Unit
	local d, h, tilt = 0, 0, 0
	local solid = true
	local anim: string? = nil
	if kind == "bump" then
		local T = ImpactRules.NPC_BUMP_TIME
		if t > T then
			return nil, true, nil
		end
		-- poussé (0,25 s), penché en arrière, se rattrape, revient à sa place
		d = 2.4 * smooth(t / 0.25) * (1 - smooth((t - 1.2) / (T - 1.2)))
		h = if t < 0.3 then 0.35 * math.sin(math.pi * t / 0.3) else 0
		tilt = -rad(32) * smooth(t / 0.2) * (1 - smooth((t - 0.35) / 0.9)) * (1 + 0.15 * math.sin(t * 18))
		solid = t > 1.2
		anim = if t < 1.0 then "cheer" else nil
	else
		local T = ImpactRules.NPC_DODGE_TIME
		if t > T then
			return nil, true, nil
		end
		-- saut de côté (0,38 s), attend que la voiture passe, revient
		d = 2.6 * smooth(t / 0.38) * (1 - smooth((t - 0.9) / (T - 0.9)))
		h = if t < 0.38 then 1.0 * math.sin(math.pi * t / 0.38) else 0
		tilt = rad(12) * math.sin(math.pi * math.clamp(t / 0.7, 0, 1))
		anim = if t < 0.8 then "cheer" else nil
	end
	local offset = CFrame.new(v * d + Vector3.new(0, h, 0)) * CFrame.fromAxisAngle(axis, tilt)
	return offset, solid, anim
end

return ImpactRules
