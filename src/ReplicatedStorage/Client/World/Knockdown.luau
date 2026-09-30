--[[
	Knockdown (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > Knockdown

	💥 v10 (PHYS10) : se faire renverser, façon DESSIN ANIMÉ, côté client.
	Règles et chiffres : Shared/ImpactRules ; serveur : ImpactService.

	  1. RENVERSÉ (choc >= 12 studs/s) : ragdoll (Motor6D -> BallSocket /
	     charnières, R15 et R6), élan dans le sens de la voiture + vers le
	     haut, petite culbute ; ⭐ étoiles qui tournent autour de la tête ;
	     après 2,5 s au sol : ANIMATION pour se relever (sur le dos : on
	     ramène les genoux, on s'assoit, on se redresse ; sur le ventre : on
	     pousse sur les bras, à genoux, debout), puis les commandes reviennent.
	     Jamais de mort, jamais de perte de vie.
	  2. TITUBE (choc léger, 4,5 à 12 studs/s) : petite poussée, le buste
	     bascule, les bras battent l'air, on se rattrape.
	  3. CIRCULATION D'AMBIANCE (TownTraffic, locale) : ses voitures
	     deviennent SOLIDES pour nous (boîte racine, groupe "voitures") et
	     on les détecte ici, à chaque image (les voitures des joueurs : le
	     serveur). On tombe tout de suite et on prévient le serveur (ragdoll
	     répliqué + étoiles chez les autres).
	  4. LES AUTRES JOUEURS : leurs étoiles, leur "se relever" et leur
	     titubement sont animés ici aussi (attributs du personnage, heure du
	     serveur), le corps au sol vient de la physique répliquée.
	  5. PNJ : une voiture qui arrive vite -> le passant saute de côté (ou se
	     fait bousculer s'il est trop tard) : ImpactRules.StartNpcReact,
	     appliqué par NPCModels.Animate. Jamais inerte pour de bon.
	  6. DESCENDRE DE VOITURE : on sort par la portière (côté conducteur, ou
	     l'autre côté, ou derrière si c'est bouché) et, ~1 s, on ne cogne pas
	     SA voiture (groupe "Riders") : jamais coincé dans la carrosserie.
	  Robuste : toute erreur -> tout est remis (articulations, groupes,
	  vitesse de marche) ; Stop() remet tout.

	Crochets TownClient :
	  - à l'entrée en ville : Knockdown.Start({ Toast = toast })
	  - à la sortie         : Knockdown.Stop()
	(le module a ses propres Heartbeat / Stepped : rien à appeler en flux)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage.Shared.Net)
local ImpactRules = require(ReplicatedStorage.Shared.ImpactRules)
local Locale = require(ReplicatedStorage.Shared.Locale)

local Knockdown = {}

Knockdown.TRAFFIC_FOLDER = "TownTraffic"
Knockdown.CARS_FOLDER = "DopamineCars"
Knockdown.MOVER_TAG = "DopamineMover"
Knockdown.FX_FOLDER = "DopaKnockFx"
Knockdown.SCAN_INTERVAL = 0.25 -- (s) liste des véhicules / des autres joueurs
Knockdown.NPC_INTERVAL = 0.1 -- (s) réactions des PNJ
Knockdown.NPC_MIN_SPEED = 6 -- (studs/s) un PNJ réagit aux voitures plus rapides
Knockdown.NEAR = 70 -- (studs) véhicules testés pour nous renverser
Knockdown.OTHERS_RADIUS = 120 -- (studs) autres joueurs animés…
Knockdown.OTHERS_MAX = 8 -- …au plus
Knockdown.GRACE_MAX = 3 -- (s) au plus en groupe "Riders" après être descendu

local LocalPlayer = Players.LocalPlayer

type Mover = { Model: Model, Traffic: boolean, Pos: Vector3?, T: number, Vel: Vector3, Solid: boolean }
type Anim = { Kind: string, T0: number, FaceUp: boolean, Lx: number, Lz: number, Rig: any }
type Self = {
	Down: boolean,
	KnockAt: number?,
	UpAt: number?,
	StumbleAt: number?,
	Ragdoll: any,
	Anim: Anim?,
	Lock: { WalkSpeed: number, JumpPower: number, JumpHeight: number }?,
}

local started = false
local disabled = false
local options: any = nil
local connections: { RBXScriptConnection } = {}
local charConnections: { RBXScriptConnection } = {}
local remote: RemoteEvent? = nil
local fxFolder: Folder? = nil
local me: Self = { Down = false }
local movers: { [Model]: Mover } = {}
local moverList: { Mover } = {}
local others: { [Model]: Anim } = {}
local stars: { [Model]: { Gui: BillboardGui, Labels: { TextLabel }, T0: number } } = {}
local scanClock, npcClock = 0, 0
local lastSeat: BasePart? = nil
local grace: { Until: number, Car: Model, Parts: { [BasePart]: string } }? = nil
local pendingExit: Model? = nil
local debugLog: { string } = {}

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function log(text: string)
	table.insert(debugLog, text)
	if #debugLog > 40 then
		table.remove(debugLog, 1)
	end
end

local function toast(text: string)
	if options and type(options.Toast) == "function" then
		pcall(options.Toast, Locale.T(text))
	end
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function charParts(): (Model?, Humanoid?, BasePart?)
	local character = LocalPlayer.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function fire(...)
	local r = remote
	if r then
		local args = table.pack(...)
		pcall(function()
			r:FireServer(table.unpack(args, 1, args.n))
		end)
	end
end

local safeZones: { ImpactRules.Zone } = {}
local zonesClock = -math.huge
local function inSafeZone(pos: Vector3): boolean
	local t = os.clock()
	if t - zonesClock > 5 then
		zonesClock = t
		local ok, list = pcall(ImpactRules.CollectSafeZones, workspace:FindFirstChild("DopamineTown"))
		if ok then
			safeZones = list
		end
	end
	return ImpactRules.InSafeZone(pos, safeZones)
end

-- Boîte (centre, taille) d'un véhicule : attributs du modèle, sinon la racine
local function boxOf(model: Model): (CFrame?, Vector3?)
	local root = model.PrimaryPart
	if not root then
		return nil, nil
	end
	local w = tonumber(model:GetAttribute("Width"))
	local l = tonumber(model:GetAttribute("Length"))
	local h = tonumber(model:GetAttribute("Height"))
	if w and l and h then
		local pivot = model:GetPivot()
		return pivot * CFrame.new(0, h / 2, 0), Vector3.new(w, h, l)
	end
	return root.CFrame, root.Size
end

----------------------------------------------------------------------
-- ⭐ Étoiles autour de la tête
----------------------------------------------------------------------

local STAR_COUNT = 5

local function starsOn(character: Model, t0: number)
	if stars[character] then
		stars[character].T0 = t0
		return
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or not fxFolder then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "KnockStars"
	gui.Adornee = head
	gui.Size = UDim2.fromScale(3.4, 1.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.25, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	local labels = {}
	for i = 1, STAR_COUNT do
		local label = Instance.new("TextLabel")
		label.Name = "Star" .. i
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromScale(0.26, 0.5)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = if i % 2 == 0 then "✨" else "⭐"
		label.TextColor3 = Color3.fromRGB(255, 226, 90)
		label.TextStrokeTransparency = 0.6
		label.TextStrokeColor3 = Color3.fromRGB(150, 90, 20)
		label.Parent = gui
		table.insert(labels, label)
	end
	gui.Parent = fxFolder
	stars[character] = { Gui = gui, Labels = labels, T0 = t0 }
end

local function starsOff(character: Model)
	local s = stars[character]
	if s then
		stars[character] = nil
		pcall(s.Gui.Destroy, s.Gui)
	end
end

-- orbite : ellipse vue de 3/4 (devant = plus gros, derrière = plus petit)
local function stepStars(t: number)
	for character, s in pairs(stars) do
		if not character.Parent or not s.Gui.Parent then
			starsOff(character)
		else
			local age = t - s.T0
			local fade = math.clamp(age / 0.3, 0, 1)
			for i, label in ipairs(s.Labels) do
				local a = age * 3.2 + (i - 1) / STAR_COUNT * math.pi * 2
				local depth = math.sin(a) -- (+1 devant)
				label.Position = UDim2.fromScale(0.5 + 0.4 * math.cos(a), 0.55 + 0.16 * depth)
				local scale = 0.75 + 0.3 * (depth + 1) / 2
				label.Size = UDim2.fromScale(0.26 * scale, 0.5 * scale)
				label.ZIndex = if depth > 0 then 3 else 1
				label.TextTransparency = 1 - fade * (0.55 + 0.45 * (depth + 1) / 2)
				label.Rotation = math.deg(a) * 0.5
			end
		end
	end
end

----------------------------------------------------------------------
-- Moi : renversé, titube, se relève
----------------------------------------------------------------------

local function lockMovement(humanoid: Humanoid)
	if me.Lock then
		return
	end
	me.Lock = { WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower, JumpHeight = humanoid.JumpHeight }
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

-- (on ne remet que ce que personne d'autre n'a changé entre-temps)
local function unlockMovement(humanoid: Humanoid?)
	local lock = me.Lock
	me.Lock = nil
	if not lock or not humanoid then
		return
	end
	if humanoid.WalkSpeed == 0 then
		humanoid.WalkSpeed = lock.WalkSpeed
	end
	if humanoid.JumpPower == 0 then
		humanoid.JumpPower = lock.JumpPower
	end
	if humanoid.JumpHeight == 0 then
		humanoid.JumpHeight = lock.JumpHeight
	end
end

local function canBeHit(humanoid: Humanoid, root: BasePart): boolean
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		return false
	end
	if inSafeZone(root.Position) then
		return false
	end
	return true
end

-- Renversé ! (linear / spin : élan ; report = { Vel, Dir } si c'est la
-- circulation locale : on prévient le serveur)
-- (force : décision du serveur, qui a déjà coupé les articulations : on suit)
local function knockSelf(linear: Vector3, spin: Vector3, report: { Vel: Vector3, Dir: Vector3 }?, force: boolean?): boolean
	local character, humanoid, root = charParts()
	if not character or not humanoid or not root or me.Down then
		return false
	end
	local t = os.clock()
	if not force and (not ImpactRules.CanKnock(me, t) or not canBeHit(humanoid, root)) then
		return false
	end
	me.Down = true
	me.KnockAt = t
	me.UpAt = nil
	me.Anim = nil
	-- (le serveur a peut-être déjà coupé les articulations : pas de doublon)
	if not ImpactRules.IsRagdolled(character) then
		me.Ragdoll = ImpactRules.Ragdoll(character, { Local = true })
	end
	lockMovement(humanoid)
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	for _, d in ipairs(character:GetChildren()) do
		if d:IsA("BasePart") then
			pcall(function()
				d.AssemblyLinearVelocity = linear
				d.AssemblyAngularVelocity = spin
			end)
		end
	end
	starsOn(character, t)
	toast("💫 Ouch! A car knocked you over!")
	if report then
		fire("traffic", "knock", report.Vel, report.Dir)
	end
	log("knock " .. string.format("%.1f", linear.Magnitude))
	return true
end

local function stumbleSelf(push: Vector3, dir: Vector3, report: { Vel: Vector3, Dir: Vector3 }?): boolean
	local character, humanoid, root = charParts()
	if not character or not humanoid or not root then
		return false
	end
	local t = os.clock()
	if not ImpactRules.CanStumble(me, t) or not canBeHit(humanoid, root) then
		return false
	end
	me.StumbleAt = t
	pcall(function()
		root.AssemblyLinearVelocity += push
	end)
	local l = root.CFrame:VectorToObjectSpace(dir)
	local flat = Vector3.new(l.X, 0, l.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	me.Anim = { Kind = "stumble", T0 = t, FaceUp = false, Lx = flat.X, Lz = flat.Z, Rig = ImpactRules.RigOf(character) }
	if report then
		fire("traffic", "stumble", report.Vel, report.Dir)
	end
	log("stumble")
	return true
end

-- Se relever : articulations remises, HRP debout là où est le bassin, puis
-- l'animation procédurale ramène le corps de "allongé" à "debout"
local function beginGetUp()
	local character, humanoid, root = charParts()
	if not character or not humanoid or not root then
		me.Down = false
		return
	end
	ImpactRules.Restore(me.Ragdoll)
	me.Ragdoll = nil
	ImpactRules.QuietServerRagdoll(character)
	local rig = ImpactRules.RigOf(character)
	local faceUp = true
	if rig then
		local rootMotor = rig.Motors.Root
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") and rootMotor.Part0 == root then
			local pivotW = (root.CFrame * rootMotor.C0).Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			local hit = workspace:Raycast(pivotW + Vector3.new(0, 1.5, 0), Vector3.new(0, -8, 0), params)
			local groundY = if hit then hit.Position.Y else pivotW.Y - 0.55
			local standY = if rig.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
			local cf, up = ImpactRules.StandFrame(torso.CFrame, pivotW, groundY, rootMotor.C0, standY)
			faceUp = up
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = cf
		end
	end
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
	me.Down = false
	me.Anim = { Kind = "getup", T0 = os.clock(), FaceUp = faceUp, Lx = 0, Lz = 0, Rig = rig }
	if rig then
		ImpactRules.ApplyPose(rig, ImpactRules.GetUpPose(0, faceUp, rig.PivotH, rig))
	end
	fire("up", faceUp)
	log("getup " .. tostring(faceUp))
end

local function endAnim()
	local anim = me.Anim
	me.Anim = nil
	if anim and anim.Rig then
		ImpactRules.ClearPose(anim.Rig)
	end
	if anim and anim.Kind == "getup" then
		me.UpAt = os.clock()
		local _, humanoid = charParts()
		unlockMovement(humanoid)
		local character = LocalPlayer.Character
		if character then
			starsOff(character)
		end
	end
end

-- Tout remettre tout de suite (sortie de la ville, erreur, nouveau personnage)
local function resetSelf(notify: boolean)
	local wasDown = me.Down
	ImpactRules.Restore(me.Ragdoll)
	me.Ragdoll = nil
	local character = LocalPlayer.Character
	if character then
		pcall(ImpactRules.QuietServerRagdoll, character)
		starsOff(character)
	end
	if me.Anim and me.Anim.Rig then
		pcall(ImpactRules.ClearPose, me.Anim.Rig)
	end
	me.Anim = nil
	local _, humanoid = charParts()
	if wasDown and humanoid then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end
	unlockMovement(humanoid)
	me.Down = false
	if wasDown then
		me.UpAt = os.clock()
		if notify then
			fire("up", true)
		end
	end
end

-- Message du serveur (voiture d'un joueur, voiture IA…)
local function onServer(kind: any, a: any, b: any, c: any)
	if kind == "knock" and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		local ok = knockSelf(a, b, nil, true)
		if not ok then
			log("knock ignoré (déjà au sol)")
		elseif me.Ragdoll == nil then
			-- (le ragdoll du serveur n'est peut-être pas encore arrivé)
			task.delay(0.15, function()
				local character = LocalPlayer.Character
				if me.Down and character and not ImpactRules.IsRagdolled(character) then
					me.Ragdoll = ImpactRules.Ragdoll(character, { Local = true })
				end
			end)
		end
	elseif kind == "stumble" and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		stumbleSelf(a, b, nil)
	end
	local _ = c
end

----------------------------------------------------------------------
-- Véhicules : liste, vitesse, circulation solide, chocs
----------------------------------------------------------------------

local function scanMovers()
	local seen: { [Model]: boolean } = {}
	local function add(model: Instance, traffic: boolean)
		if not model:IsA("Model") or seen[model] then
			return
		end
		seen[model] = true
		local m = movers[model]
		if not m then
			m = { Model = model, Traffic = traffic, Pos = nil, T = 0, Vel = Vector3.zero, Solid = false }
			movers[model] = m
		end
		-- circulation locale : la boîte racine devient solide (groupe voitures :
		-- avatars et voitures s'y cognent, le corps au sol non)
		if traffic and not m.Solid then
			local root = model.PrimaryPart
			if root then
				m.Solid = true
				pcall(function()
					root.CanCollide = true
					root.CollisionGroup = ImpactRules.CAR_GROUP
				end)
			end
		end
	end
	local traffic = workspace:FindFirstChild(Knockdown.TRAFFIC_FOLDER)
	if traffic then
		for _, child in ipairs(traffic:GetChildren()) do
			if child:IsA("Model") and (string.sub(child.Name, 1, 7) == "Traffic" or child:GetAttribute("TrafficMover") == true) then
				add(child, true)
			end
		end
	end
	local cars = workspace:FindFirstChild(Knockdown.CARS_FOLDER)
	if cars then
		for _, child in ipairs(cars:GetChildren()) do
			add(child, false)
		end
	end
	local ok, tagged = pcall(function()
		return CollectionService:GetTagged(Knockdown.MOVER_TAG)
	end)
	if ok and type(tagged) == "table" then
		for _, model in ipairs(tagged) do
			if model:IsA("Model") and model:IsDescendantOf(workspace) then
				add(model, model:GetAttribute("ClientMover") == true)
			end
		end
	end
	table.clear(moverList)
	for model, m in pairs(movers) do
		if seen[model] and model.Parent then
			table.insert(moverList, m)
		else
			movers[model] = nil
		end
	end
end

-- Vitesse de chaque véhicule (physique, sinon dérivée de la position)
local function updateMovers(t: number)
	for _, m in ipairs(moverList) do
		local root = m.Model.PrimaryPart
		if root and root.Parent then
			local pos = m.Model:GetPivot().Position
			if not root.Anchored and not m.Traffic then
				m.Vel = root.AssemblyLinearVelocity
			elseif m.Pos then
				local dt = t - m.T
				if dt > 1e-3 then
					local raw = (pos - m.Pos) / dt
					if raw.Magnitude > 150 then
						raw = Vector3.zero -- (reconstruit / téléporté)
					end
					m.Vel = m.Vel:Lerp(raw, math.clamp(dt * 12, 0.2, 1))
				end
			end
			m.Pos = pos
			m.T = t
		end
	end
end

-- La circulation locale nous touche-t-elle ?
local function checkTraffic()
	if me.Down then
		return
	end
	local _, humanoid, root = charParts()
	if not humanoid or not root then
		return
	end
	local here = root.Position
	for _, m in ipairs(moverList) do
		if m.Traffic and m.Pos and (m.Pos - here).Magnitude < Knockdown.NEAR then
			local speed = Vector3.new(m.Vel.X, 0, m.Vel.Z).Magnitude
			if speed >= ImpactRules.STUMBLE_SPEED then
				local cf, size = boxOf(m.Model)
				if cf and size then
					local impact, dir = ImpactRules.Contact(cf, size, m.Vel, here, root.AssemblyLinearVelocity, speed * 0.05)
					if impact and dir then
						local kind = ImpactRules.Classify(impact)
						local report = { Vel = m.Vel, Dir = dir }
						if kind == "knock" then
							local linear, spin = ImpactRules.Impulse(dir, impact, root.AssemblyLinearVelocity)
							if knockSelf(linear, spin, report) then
								return
							end
						elseif kind == "stumble" then
							stumbleSelf(ImpactRules.StumblePush(dir, impact), dir, report)
						end
					end
				end
			end
		end
	end
end

-- PNJ devant une voiture rapide : saut de côté, ou bousculade s'il est trop tard
local npcOverlap: OverlapParams? = nil
local npcWarned = false
local function checkNpcs()
	local camera = workspace.CurrentCamera
	local center = camera and camera.CFrame.Position
	local _, _, myRoot = charParts()
	local center2 = if myRoot then myRoot.Position else center
	if not center or not center2 then
		return
	end
	local now = os.clock()
	local reactions = 0
	for _, m in ipairs(moverList) do
		local flat = Vector3.new(m.Vel.X, 0, m.Vel.Z)
		local speed = flat.Magnitude
		if m.Pos and speed >= Knockdown.NPC_MIN_SPEED and math.min((m.Pos - center).Magnitude, (m.Pos - center2).Magnitude) < 110 then
			local cf, size = boxOf(m.Model)
			if cf and size then
				local u = flat.Unit
				local frame = CFrame.lookAt(cf.Position, cf.Position + u)
				-- demi-longueur / demi-largeur de la boîte vues dans le sens de la marche
				local half = math.abs(u:Dot(cf.LookVector)) * size.Z / 2 + math.abs(u:Dot(cf.RightVector)) * size.X / 2
				local halfW = math.abs(frame.RightVector:Dot(cf.RightVector)) * size.X / 2 + math.abs(frame.RightVector:Dot(cf.LookVector)) * size.Z / 2
				local reach = math.clamp(speed * 0.9, 4, 30)
				local boxCenter = frame * CFrame.new(0, 0, -(half + reach) / 2)
				local params = npcOverlap
				if not params then
					params = OverlapParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					npcOverlap = params
				end
				local exclude: { Instance } = { m.Model }
				if LocalPlayer.Character then
					table.insert(exclude, LocalPlayer.Character)
				end
				params.FilterDescendantsInstances = exclude
				local ok, parts = pcall(function()
					return workspace:GetPartBoundsInBox(boxCenter, Vector3.new(size.X + 3.4, 8, half + reach), params)
				end)
				if ok and type(parts) == "table" then
					for _, p in ipairs(parts) do
						local npc = p.Parent
						if p.Name == "NpcCollider" and npc and npc:IsA("Model") and not ImpactRules.NpcReacting(npc, now) then
							local rel = frame:PointToObjectSpace(p.Position)
							local ahead = -rel.Z - half
							if math.abs(rel.X) < halfW + 1.8 and ahead > -1.5 then
								local side = if rel.X >= 0 then 1 else -1
								local right = frame.RightVector * side
								if ahead / speed > 0.3 then
									ImpactRules.StartNpcReact(npc, "dodge", right, now)
								else
									ImpactRules.StartNpcReact(npc, "bump", u * 0.8 + right * 0.45, now)
								end
								reactions += 1
								if reactions >= 12 then
									return
								end
							end
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Descendre de voiture : par la portière, sans se coincer
----------------------------------------------------------------------

local function isCarSeat(seat: BasePart?): Model?
	if not seat or not seat:IsA("VehicleSeat") then
		return nil
	end
	local model = seat:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local root = model.PrimaryPart
	if model:GetAttribute("CarId") ~= nil or (root and root.CollisionGroup == ImpactRules.CAR_GROUP) then
		return model
	end
	return nil
end

local function endGrace()
	local g = grace
	grace = nil
	if not g then
		return
	end
	for part, group in pairs(g.Parts) do
		pcall(function()
			if part.Parent and part.CollisionGroup == ImpactRules.RIDER_GROUP then
				part.CollisionGroup = group
			end
		end)
	end
end

local function startGrace(car: Model)
	local character = LocalPlayer.Character
	if not character then
		return
	end
	endGrace()
	local parts: { [BasePart]: string } = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("KeepGroup") ~= true then
			parts[d] = d.CollisionGroup
			pcall(function()
				d.CollisionGroup = ImpactRules.RIDER_GROUP
			end)
		end
	end
	grace = { Until = os.clock() + Knockdown.GRACE_MAX, Car = car, Parts = parts }
end

-- l'avatar touche-t-il encore la boîte de la voiture ?
local function overlapsCar(car: Model, pos: Vector3): boolean
	local root = car.PrimaryPart
	if not root then
		return false
	end
	local rel = root.CFrame:PointToObjectSpace(pos)
	local half = root.Size / 2
	local r = ImpactRules.CHAR_RADIUS + 0.2
	return math.abs(rel.X) < half.X + r and math.abs(rel.Z) < half.Z + r and rel.Y > -half.Y - 3.2 and rel.Y < half.Y + 3
end

-- Place libre à côté de la portière (conducteur, passager, derrière)
local function exitSpot(car: Model, character: Model, humanoid: Humanoid, root: BasePart): CFrame?
	local carRoot = car.PrimaryPart
	if not carRoot then
		return nil
	end
	local seatZ = 0
	local seat = lastSeat
	if seat and seat.Parent then
		seatZ = carRoot.CFrame:PointToObjectSpace(seat.Position).Z
	end
	local hx, hz = carRoot.Size.X / 2, carRoot.Size.Z / 2
	local candidates = {
		Vector3.new(-(hx + 1.7), 0, seatZ),
		Vector3.new(hx + 1.7, 0, seatZ),
		Vector3.new(0, 0, hz + 2),
		Vector3.new(0, 0, -(hz + 2)),
	}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character, car }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character, car }
	overlap.RespectCanCollide = true
	local standY = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
	local flatLook = Vector3.new(carRoot.CFrame.LookVector.X, 0, carRoot.CFrame.LookVector.Z)
	if flatLook.Magnitude < 1e-3 then
		flatLook = Vector3.new(0, 0, -1)
	end
	for _, off in ipairs(candidates) do
		local p = (carRoot.CFrame * CFrame.new(off)).Position
		local hit = workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), rayParams)
		if hit then
			local foot = hit.Position
			local okBox, list = pcall(function()
				return workspace:GetPartBoundsInBox(CFrame.new(foot + Vector3.new(0, 2.9, 0)), Vector3.new(1.8, 4.6, 1.8), overlap)
			end)
			if okBox and type(list) == "table" and #list == 0 then
				local pos = foot + Vector3.new(0, standY, 0)
				return CFrame.lookAt(pos, pos + flatLook.Unit)
			end
		end
	end
	return nil
end

local function stepGrace()
	local car = pendingExit
	if car then
		pendingExit = nil
		local character, humanoid, root = charParts()
		if character and humanoid and root and car.Parent and humanoid.SeatPart == nil and overlapsCar(car, root.Position) then
			local cf = exitSpot(car, character, humanoid, root)
			if cf then
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = cf
			end
		end
	end
	local g = grace
	if not g then
		return
	end
	local _, humanoid, root = charParts()
	if not root or not humanoid or humanoid.SeatPart ~= nil then
		-- (rassis : plus besoin ; parti : on remet)
		endGrace()
		return
	end
	if os.clock() > g.Until or not g.Car.Parent or not overlapsCar(g.Car, root.Position) then
		endGrace()
	end
end

local function onSeated(active: boolean, seat: BasePart?)
	if active then
		lastSeat = seat
		return
	end
	local car = isCarSeat(lastSeat)
	if car then
		startGrace(car)
		pendingExit = car
	end
	-- (lastSeat gardé : exitSpot lit la position du siège)
end

local function watchCharacter(character: Model?)
	for _, c in ipairs(charConnections) do
		c:Disconnect()
	end
	table.clear(charConnections)
	me = { Down = false }
	grace = nil
	pendingExit = nil
	lastSeat = nil
	if not character then
		return
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") and started and LocalPlayer.Character == character then
			table.insert(charConnections, humanoid.Seated:Connect(function(active: boolean, seat: BasePart?)
				local ok, err = pcall(onSeated, active, seat)
				if not ok then
					warn("[Knockdown] " .. tostring(err))
				end
			end))
			if humanoid.SeatPart then
				lastSeat = humanoid.SeatPart
			end
		end
	end)
end

----------------------------------------------------------------------
-- Les autres joueurs (étoiles, se relever, tituber)
----------------------------------------------------------------------

local function scanOthers()
	local _, _, myRoot = charParts()
	local center = if myRoot then myRoot.Position else (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position)
	local t = serverNow()
	local count = 0
	local seen: { [Model]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if player ~= LocalPlayer and character and character.Parent and count < Knockdown.OTHERS_MAX then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and center and (root.Position - center).Magnitude < Knockdown.OTHERS_RADIUS then
				local knockAt = character:GetAttribute("DopaKnockAt")
				local upAt = character:GetAttribute("DopaUpAt")
				local stumbleAt = character:GetAttribute("DopaStumbleAt")
				local down = type(knockAt) == "number" and t - knockAt < ImpactRules.FAILSAFE + 1 and not (type(upAt) == "number" and upAt >= knockAt)
				local rising = type(upAt) == "number" and t - upAt < ImpactRules.GETUP_TIME and t - upAt >= -0.2
				if down or (rising and t - (upAt :: number) < ImpactRules.GETUP_TIME * 0.6) then
					starsOn(character, os.clock() - math.max(0, t - (knockAt or t)))
					seen[character] = true
				end
				local anim = others[character]
				if rising then
					if not anim or anim.Kind ~= "getup" or anim.T0 ~= upAt then
						others[character] = { Kind = "getup", T0 = upAt :: number, FaceUp = character:GetAttribute("DopaUpFace") ~= false, Lx = 0, Lz = 0, Rig = ImpactRules.RigOf(character) }
					end
					count += 1
				elseif type(stumbleAt) == "number" and t - stumbleAt < ImpactRules.STUMBLE_TIME and not down then
					if not anim or anim.Kind ~= "stumble" or anim.T0 ~= stumbleAt then
						local dir = character:GetAttribute("DopaStumbleDir")
						local l = if typeof(dir) == "Vector3" then root.CFrame:VectorToObjectSpace(dir) else Vector3.new(0, 0, -1)
						local flat = Vector3.new(l.X, 0, l.Z)
						flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
						others[character] = { Kind = "stumble", T0 = stumbleAt, FaceUp = false, Lx = flat.X, Lz = flat.Z, Rig = ImpactRules.RigOf(character) }
					end
					count += 1
				end
			end
		end
	end
	-- étoiles des autres qui ne sont plus au sol
	for character in pairs(stars) do
		if character ~= LocalPlayer.Character and not seen[character] then
			starsOff(character)
		end
	end
end

----------------------------------------------------------------------
-- Boucles
----------------------------------------------------------------------

local function poseStep()
	-- moi
	local anim = me.Anim
	local t = os.clock()
	if me.Down and me.KnockAt and t - me.KnockAt >= ImpactRules.KNOCK_TIME then
		beginGetUp()
		anim = me.Anim
	end
	if anim and anim.Rig then
		local age = t - anim.T0
		if anim.Kind == "getup" then
			if age >= ImpactRules.GETUP_TIME then
				endAnim()
			else
				ImpactRules.ApplyPose(anim.Rig, ImpactRules.GetUpPose(age / ImpactRules.GETUP_TIME, anim.FaceUp, anim.Rig.PivotH, anim.Rig))
			end
		elseif anim.Kind == "stumble" then
			if age >= ImpactRules.STUMBLE_TIME or me.Down then
				endAnim()
			else
				ImpactRules.ApplyPose(anim.Rig, ImpactRules.StumblePose(age, anim.Lx, anim.Lz))
			end
		end
	elseif anim and anim.Kind == "getup" and t - anim.T0 >= ImpactRules.GETUP_TIME then
		endAnim()
	end
	-- les autres
	local st = serverNow()
	for character, a in pairs(others) do
		local age = st - a.T0
		local rig = a.Rig
		local limit = if a.Kind == "getup" then ImpactRules.GETUP_TIME else ImpactRules.STUMBLE_TIME
		if not character.Parent or not rig or age >= limit then
			if rig then
				ImpactRules.ClearPose(rig)
			end
			others[character] = nil
		elseif age >= 0 then
			if a.Kind == "getup" then
				ImpactRules.ApplyPose(rig, ImpactRules.GetUpPose(age / limit, a.FaceUp, rig.PivotH, rig))
			else
				ImpactRules.ApplyPose(rig, ImpactRules.StumblePose(age, a.Lx, a.Lz))
			end
		end
	end
end

local function heartbeat(dt: number)
	local t = os.clock()
	scanClock += dt
	npcClock += dt
	if scanClock >= Knockdown.SCAN_INTERVAL then
		scanClock = 0
		scanMovers()
		scanOthers()
	end
	updateMovers(t)
	checkTraffic()
	if npcClock >= Knockdown.NPC_INTERVAL then
		npcClock = 0
		-- (réactions des PNJ : jamais bloquantes pour le reste)
		local okNpc, errNpc = pcall(checkNpcs)
		if not okNpc and not npcWarned then
			npcWarned = true
			warn("[Knockdown] PNJ : " .. tostring(errNpc))
		end
	end
	stepGrace()
	stepStars(t)
end

local function guarded(name: string, fn: (...any) -> ()): (...any) -> ()
	return function(...)
		if disabled then
			return
		end
		local ok, err = pcall(fn, ...)
		if not ok then
			-- (jamais de pose cassée : tout est remis, le module se coupe)
			disabled = true
			warn("[Knockdown] " .. name .. " : " .. tostring(err))
			pcall(resetSelf, true)
			pcall(endGrace)
		end
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function Knockdown.Start(startOptions: any?)
	if started then
		return
	end
	started = true
	disabled = false
	options = startOptions
	local old = workspace:FindFirstChild(Knockdown.FX_FOLDER)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = Knockdown.FX_FOLDER
	f.Parent = workspace
	fxFolder = f
	task.spawn(function()
		local ok, event = pcall(Net.Event, "Impact")
		if ok and event and started then
			remote = event
			table.insert(connections, event.OnClientEvent:Connect(guarded("serveur", onServer)))
		end
	end)
	table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(character: Model)
		pcall(endGrace)
		me = { Down = false }
		watchCharacter(character)
	end))
	watchCharacter(LocalPlayer.Character)
	table.insert(connections, RunService.Heartbeat:Connect(guarded("heartbeat", heartbeat)))
	table.insert(connections, RunService.Stepped:Connect(guarded("poses", function()
		poseStep()
	end)))
	scanMovers()
end

function Knockdown.Stop()
	if not started then
		return
	end
	pcall(resetSelf, true)
	pcall(endGrace)
	started = false
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	for _, c in ipairs(charConnections) do
		c:Disconnect()
	end
	table.clear(charConnections)
	for character, a in pairs(others) do
		if a.Rig then
			pcall(ImpactRules.ClearPose, a.Rig)
		end
		others[character] = nil
	end
	for character in pairs(stars) do
		starsOff(character)
	end
	-- (la circulation garde sa boîte solide : TownTraffic détruit ses modèles)
	table.clear(movers)
	table.clear(moverList)
	remote = nil
	pendingExit = nil
	lastSeat = nil
	if fxFolder then
		fxFolder:Destroy()
		fxFolder = nil
	end
end

function Knockdown.IsDown(): boolean
	return me.Down
end

-- (tests / émulateur)
function Knockdown.Debug(): any
	return {
		Self = function()
			return me
		end,
		Movers = moverList,
		Others = others,
		Stars = stars,
		Grace = function()
			return grace
		end,
		Log = debugLog,
		Knock = knockSelf,
		Stumble = stumbleSelf,
		BeginGetUp = beginGetUp,
		PoseStep = poseStep,
		Heartbeat = heartbeat,
		ScanMovers = scanMovers,
		ScanOthers = scanOthers,
		CheckTraffic = checkTraffic,
		CheckNpcs = checkNpcs,
		OnServer = onServer,
		OnSeated = onSeated,
		StepGrace = stepGrace,
		ExitSpot = exitSpot,
		StepStars = stepStars,
		StarsOn = starsOn,
		Disabled = function()
			return disabled
		end,
	}
end

return Knockdown
