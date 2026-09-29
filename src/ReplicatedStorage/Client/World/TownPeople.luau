--[[
	TownPeople (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownPeople

	🚶 Dopamine Town (v9.8, CITY98) : des PASSANTS dans les rues, côté CLIENT.
	  - des marcheurs sur les chemins publiés par le serveur (DopamineTown >
	    StreetLife, Configuration "Path" : l'anneau du trottoir intérieur du
	    boulevard, le tour de la place, la promenade de l'avenue jusqu'à la
	    porte, les trottoirs de l'avenue et des rues) : ils tiennent leur
	    droite, certains marchent à deux en discutant, d'autres promènent
	    leur CHIEN (laisse), joggent, regardent leur téléphone, portent un
	    café ou un sac de courses ;
	  - des gens ASSIS sur les bancs (place, avenue, arrivée, abribus), aux
	    terrasses de café, aux tables d'échecs ; des gens qui DISCUTENT à
	    deux ; quelqu'un qui attend le bus ; les marchands du petit marché,
	    du kiosque et des étals (emplacements de TownStreetLife).
	DÉTERMINISTE : la position de chacun ne dépend que de l'heure du serveur
	(workspace:GetServerTimeNow) et de sa graine -> tous les joueurs voient
	les mêmes passants aux mêmes endroits. Les personnages (NPCModels) ne
	sont construits que près de l'avatar : 20 au plus (les plus proches, à
	moins de 150 studs), 2 constructions par passe ; ancrés, SANS collision
	(ils ne gênent jamais les joueurs), animés par CFrame (BulkMoveTo) :
	30 Hz près de l'avatar, 10 Hz plus loin. Aucune lumière, aucun son.

	API (TownClient, via optionalModule) :
	  TownPeople.Start()                  à l'entrée en ville
	  TownPeople.Step(position: Vector3)  flux (4 fois / s)
	  TownPeople.Stop()                   à la sortie
	  TownPeople.Positions() -> { Vector3 } passants construits (TownTraffic :
	                                      les voitures s'arrêtent devant eux)
	  TownPeople.Debug() -> table
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NPCModels = require(ReplicatedStorage.Shared.NPCModels)
-- (v9.8, REALISM98) réglage "Graphismes > Détail" : distance x 0,65 / 1 / 1,35 ;
-- "Low" : moitié moins de passants construits
local okGQ, GraphicsQuality = pcall(require, ReplicatedStorage.Shared.GraphicsQuality)
local function quality(): (number, boolean)
	if okGQ and type(GraphicsQuality) == "table" and GraphicsQuality.Get then
		local ok, q = pcall(GraphicsQuality.Get)
		if ok and type(q) == "table" then
			return tonumber(q.DetailScale) or 1, q.Detail == "Low"
		end
	end
	return 1, false
end

local TownPeople = {}

TownPeople.FOLDER_NAME = "TownPeople"
TownPeople.MAX_BUILT = 20
local NEAR_IN, NEAR_OUT = 150, 175
local BUILDS_PER_STEP = 2
local FAST_RANGE = 90 -- (studs) animés à 30 Hz en deçà, 10 Hz au-delà
local FAST_STEP, SLOW_STEP = 1 / 30, 1 / 10

local rgb = Color3.fromRGB

type Path = { Name: string, Points: { Vector3 }, Cum: { number }, Length: number, Loop: boolean }
type Agent = {
	Id: number,
	Kind: string, -- "walk" | "static"
	Style: string,
	Seed: number,
	Prop: string?,
	Path: Path?,
	Speed: number,
	Dir: number,
	Offset: number,
	Lateral: number,
	Along: number, -- (compagnon / chien : décalage le long du chemin)
	Anim: string,
	CF: CFrame?, -- (statiques)
	Phase: number,
	Dog: boolean,
	Model: Model?,
	DogModel: Model?,
	Leash: BasePart?,
	Pos: Vector3,
	Clock: number,
}

local state: any = nil

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and type(t) == "number" and t or os.clock()
end

local function parsePoints(text: string): { Vector3 }
	local pts = {}
	for _, chunk in ipairs(string.split(text, ";")) do
		local c = string.split(chunk, ",")
		local x, y, z = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
		if x and y and z then
			table.insert(pts, Vector3.new(x, y, z))
		end
	end
	return pts
end

local function makePath(name: string, pts: { Vector3 }, loop: boolean): Path?
	if #pts < 2 then
		return nil
	end
	local list = table.clone(pts)
	if loop then
		table.insert(list, pts[1])
	end
	local cum = { 0 }
	for i = 2, #list do
		cum[i] = cum[i - 1] + (list[i] - list[i - 1]).Magnitude
	end
	return { Name = name, Points = list, Cum = cum, Length = cum[#cum], Loop = loop }
end

-- Point du chemin à l'abscisse `s` (bouclé) : position + direction lissée
local function sample(path: Path, s: number): Vector3
	local L = path.Length
	s = s % L
	local cum, pts = path.Cum, path.Points
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = cum[hi] - cum[lo]
	local t = seg > 0 and (s - cum[lo]) / seg or 0
	return pts[lo]:Lerp(pts[hi], t)
end

local UP = Vector3.new(0, 1, 0)

-- Repère d'un marcheur au temps `now` (pieds au sol, regard dans le sens de la marche)
local function walkerCF(a: Agent, now: number): CFrame
	local path = a.Path :: Path
	local s = a.Offset + a.Dir * a.Speed * now + a.Along
	local p = sample(path, s)
	local ahead = sample(path, s + a.Dir * 1.2)
	local behind = sample(path, s - a.Dir * 1.2)
	local fwd = ahead - behind
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	if fwd.Magnitude < 0.01 then
		fwd = Vector3.new(0, 0, -1)
	end
	fwd = fwd.Unit
	local right = fwd:Cross(UP)
	local pos = p + right * a.Lateral
	return CFrame.lookAt(pos, pos + fwd)
end

----------------------------------------------------------------------
-- Chien (13 pièces, ancré) : trot, queue qui remue
----------------------------------------------------------------------

local DOG_COLORS = { rgb(214, 170, 110), rgb(60, 50, 46), rgb(240, 236, 228), rgb(160, 100, 60), rgb(120, 110, 104) }

local function dogPart(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: string?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	p.Parent = m
	return p
end

type Dog = { Model: Model, Parts: { BasePart }, Locals: { CFrame }, Kinds: { number }, Frames: { CFrame } }

local function buildDog(seed: number): Dog
	local m = Instance.new("Model")
	m.Name = "Dog"
	local fur = DOG_COLORS[seed % #DOG_COLORS + 1]
	local dark = fur:Lerp(Color3.new(0, 0, 0), 0.35)
	local d: Dog = { Model = m, Parts = {}, Locals = {}, Kinds = {}, Frames = {} }
	-- kinds : 0 corps, 1 tête, 2 queue, 3..6 pattes (AvG, AvD, ArG, ArD)
	local function add(name: string, size: Vector3, loc: CFrame, color: Color3, kind: number, shape: string?)
		local p = dogPart(m, name, size, loc, color, shape)
		table.insert(d.Parts, p)
		table.insert(d.Locals, loc)
		table.insert(d.Kinds, kind)
		table.insert(d.Frames, loc)
	end
	add("DogBody", Vector3.new(0.9, 0.85, 1.9), CFrame.new(0, 1.35, 0), fur, 0, "Egg")
	add("DogChest", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 1.45, -0.7), fur:Lerp(Color3.new(1, 1, 1), 0.2), 0, "Egg")
	add("DogCollar", Vector3.new(0.62, 0.16, 0.5), CFrame.new(0, 1.75, -0.92), rgb(220, 50, 70), 0)
	add("DogHead", Vector3.new(0.7, 0.72, 0.8), CFrame.new(0, 2.05, -1.2), fur, 1, "Egg")
	add("DogSnout", Vector3.new(0.4, 0.34, 0.5), CFrame.new(0, 1.92, -1.62), fur:Lerp(Color3.new(1, 1, 1), 0.15), 1, "Egg")
	add("DogNose", Vector3.new(0.16, 0.14, 0.12), CFrame.new(0, 2.0, -1.88), rgb(30, 26, 28), 1, "Egg")
	for _, sx in ipairs({ -1, 1 }) do
		add("DogEar", Vector3.new(0.14, 0.45, 0.3), CFrame.new(sx * 0.3, 2.25, -1.08) * CFrame.Angles(0, 0, sx * 0.35), dark, 1, "Egg")
		add("DogEye", Vector3.new(0.1, 0.1, 0.06), CFrame.new(sx * 0.17, 2.18, -1.55), rgb(30, 26, 28), 1, "Egg")
	end
	add("DogTail", Vector3.new(0.14, 0.14, 0.8), CFrame.new(0, 1.75, 1.15) * CFrame.Angles(math.rad(35), 0, 0), fur, 2)
	local legs = { { -0.26, -0.6 }, { 0.26, -0.6 }, { -0.26, 0.6 }, { 0.26, 0.6 } }
	for i, l in ipairs(legs) do
		add("DogLeg", Vector3.new(0.22, 1.05, 0.24), CFrame.new(l[1], 0.55, l[2]), i <= 2 and fur or dark, 2 + i)
	end
	return d
end

local DOG_HIP_Y = 1.05
local NECK = CFrame.new(0, 1.75, -0.95)
local NECK_INV = NECK:Inverse()
local TAIL = CFrame.new(0, 1.6, 0.8)
local TAIL_INV = TAIL:Inverse()

local function animateDog(d: Dog, cf: CFrame, t: number, moving: boolean)
	local w = t * math.pi * 2 * 2.1
	local bob = moving and math.abs(math.sin(w)) * 0.06 or 0
	local root = cf * CFrame.new(0, bob, 0)
	local head = root * NECK * CFrame.Angles(math.sin(t * 1.3) * 0.08, math.sin(t * 0.7) * 0.3, 0) * NECK_INV
	local tail = root * TAIL * CFrame.Angles(0, math.sin(t * 9) * 0.5, 0) * TAIL_INV
	for i = 1, #d.Parts do
		local k = d.Kinds[i]
		local loc = d.Locals[i]
		if k == 1 then
			d.Frames[i] = head * loc
		elseif k == 2 then
			d.Frames[i] = tail * loc
		elseif k >= 3 then
			-- trot : diagonales en phase (AvG + ArD, AvD + ArG)
			local phase = (k == 3 or k == 6) and 0 or math.pi
			local a = moving and math.sin(w + phase) * 0.55 or 0
			local hip = CFrame.new(loc.X, DOG_HIP_Y, loc.Z)
			d.Frames[i] = root * hip * CFrame.Angles(a, 0, 0) * hip:Inverse() * loc
		else
			d.Frames[i] = root * loc
		end
	end
	workspace:BulkMoveTo(d.Parts, d.Frames, Enum.BulkMoveMode.FireCFrameChanged)
end

----------------------------------------------------------------------
-- Population
----------------------------------------------------------------------

-- Nombre de marcheurs par chemin (selon sa longueur) + styles tirés au sort
local WALK_STYLES = { "pedestrian", "pedestrian", "shopper", "pedestrian", "elder", "kid", "jogger", "worker", "shopper", "pedestrian" }
local PROPS = { "none", "phone", "coffee", "none", "bag", "none" }
local SIT_STYLES = { "elder", "pedestrian", "shopper", "pedestrian", "elder" }

local function addAgent(s: any, a: any)
	a.Id = #s.Agents + 1
	a.Pos = Vector3.zero
	a.Clock = 0
	a.Phase = a.Phase or hash(a.Seed, 5) * 10
	table.insert(s.Agents, a)
end

local function populate(s: any)
	local seedBase = 0
	-- marcheurs
	for _, path: Path in ipairs(s.Paths) do
		local n = math.clamp(math.floor(path.Length / 120 + 0.5), 1, 12)
		if path.Name == "PlazaRing" then
			n = 4
		end
		for i = 1, n do
			seedBase += 1
			local seed = seedBase * 13 + 7
			local style = WALK_STYLES[math.floor(hash(seed, 1) * #WALK_STYLES) + 1]
			local dir = hash(seed, 2) < 0.5 and 1 or -1
			local speed = style == "jogger" and 8.5 or (style == "elder" and 2.8 or (3.6 + hash(seed, 3) * 1.0))
			local prop = style == "shopper" and "bag" or PROPS[math.floor(hash(seed, 4) * #PROPS) + 1]
			if style == "jogger" or style == "worker" or style == "kid" then
				prop = "none"
			end
			local offset = (i - 1 + hash(seed, 6) * 0.6) / n * path.Length
			local lateral = (0.55 + hash(seed, 7) * 0.35) * dir
			local dog = (style == "pedestrian" or style == "elder") and hash(seed, 8) < 0.22
			addAgent(s, {
				Kind = "walk",
				Style = style,
				Seed = seed,
				Prop = dog and "none" or prop,
				Path = path,
				Speed = speed,
				Dir = dir,
				Offset = offset,
				Lateral = lateral,
				Along = 0,
				Anim = "walk",
				Dog = dog,
			})
			-- (parfois un compagnon qui marche à côté : on discute en marchant)
			if not dog and style ~= "jogger" and hash(seed, 9) < 0.25 then
				addAgent(s, {
					Kind = "walk",
					Style = hash(seed, 10) < 0.3 and "kid" or "pedestrian",
					Seed = seed + 1000,
					Prop = "none",
					Path = path,
					Speed = speed,
					Dir = dir,
					Offset = offset,
					Lateral = lateral + dir * 1.35,
					Along = -0.3 * dir,
					Anim = "walk",
					Dog = false,
				})
			end
		end
	end
	-- assis sur les bancs (un banc sur deux environ)
	for _, spot in ipairs(s.Anchors.SitBench or {}) do
		local h = hash(spot.Seed, 21)
		if h < 0.5 then
			local side = h < 0.25 and -1 or 1
			local style = SIT_STYLES[math.floor(hash(spot.Seed, 22) * #SIT_STYLES) + 1]
			addAgent(s, {
				Kind = "static",
				Style = style,
				Seed = spot.Seed * 7 + 3,
				Prop = ({ "none", "phone", "coffee", "none" })[math.floor(hash(spot.Seed, 23) * 4) + 1],
				CF = spot.CF * CFrame.new(side * 1.1, 0, 0.3),
				Anim = "sit",
			})
			-- (parfois deux sur le même banc)
			if hash(spot.Seed, 24) < 0.3 then
				addAgent(s, {
					Kind = "static",
					Style = SIT_STYLES[math.floor(hash(spot.Seed, 25) * #SIT_STYLES) + 1],
					Seed = spot.Seed * 7 + 4,
					Prop = "none",
					CF = spot.CF * CFrame.new(-side * 1.2, 0, 0.3),
					Anim = "sit",
				})
			end
		end
	end
	-- terrasses : 3 clients assis (les chaises sont 0,2 plus basses que NPCModels.SitHeight)
	for _, spot in ipairs(s.Anchors.Terrace or {}) do
		for k, c in ipairs({ { -3.2, -1 }, { 0, 1 }, { 3.2, -1 }, { 3.2, 1 } }) do
			if k <= 3 or hash(spot.Seed, 30) < 0.5 then
				local chair = spot.CF * CFrame.new(c[1], -0.2, c[2] * 1.25) * CFrame.Angles(0, c[2] < 0 and math.pi or 0, 0)
				addAgent(s, {
					Kind = "static",
					Style = k % 2 == 0 and "shopper" or "pedestrian",
					Seed = spot.Seed * 11 + k,
					Prop = k == 2 and "coffee" or "none",
					CF = chair * CFrame.new(0, 0, 0.15),
					Anim = "sit",
				})
			end
		end
	end
	-- échecs : 2 joueurs face à face à la première table
	for _, spot in ipairs(s.Anchors.ChessTables or {}) do
		for _, sz in ipairs({ -1, 1 }) do
			local stool = spot.CF * CFrame.new(-3, 0, sz * 2.3) * CFrame.Angles(0, sz < 0 and math.pi or 0, 0)
			addAgent(s, { Kind = "static", Style = "elder", Seed = spot.Seed * 5 + sz, Prop = "none", CF = stool * CFrame.new(0, 0, 0.1), Anim = "sit" })
		end
	end
	-- discussions à deux
	for _, spot in ipairs(s.Anchors.Chat or {}) do
		for _, sx in ipairs({ -1, 1 }) do
			local p = spot.CF * CFrame.new(sx * 1.15, 0, 0)
			addAgent(s, {
				Kind = "static",
				Style = hash(spot.Seed, 40 + sx) < 0.4 and "shopper" or "pedestrian",
				Seed = spot.Seed * 17 + sx,
				Prop = hash(spot.Seed, 42 + sx) < 0.3 and "coffee" or "none",
				CF = CFrame.lookAt(p.Position, (spot.CF * CFrame.new(-sx * 1.15, 0, 0)).Position),
				Anim = sx < 0 and "talk" or "idle",
			})
		end
	end
	-- on attend le bus
	for _, spot in ipairs(s.Anchors.Wait or {}) do
		addAgent(s, { Kind = "static", Style = "pedestrian", Seed = spot.Seed * 3 + 1, Prop = "phone", CF = spot.CF, Anim = "idle" })
	end
	-- marchands : kiosque, étals, petit marché
	for _, spot in ipairs(s.Anchors.Kiosk or {}) do
		addAgent(s, { Kind = "static", Style = "pedestrian", Seed = spot.Seed * 19, Prop = "none", CF = spot.CF * CFrame.new(0, 0, 0.2), Anim = "talk" })
	end
	for _, kind in ipairs({ "FlowerStall", "BookStall" }) do
		for _, spot in ipairs(s.Anchors[kind] or {}) do
			addAgent(s, { Kind = "static", Style = kind == "FlowerStall" and "shopper" or "elder", Seed = spot.Seed * 23, Prop = "none", CF = spot.CF * CFrame.new(0.6, 0, 2.0), Anim = "talk" })
		end
	end
	for _, spot in ipairs(s.Anchors.MarketSquare or {}) do
		local stalls = { { -7, -4, 0 }, { 7, -4, 0 }, { -7, 5, math.pi }, { 7, 5, math.pi } }
		for i, st in ipairs(stalls) do
			local S = spot.CF * CFrame.new(st[1], 0.12, st[2]) * CFrame.Angles(0, st[3], 0)
			addAgent(s, { Kind = "static", Style = i % 2 == 0 and "baker" or "worker", Seed = spot.Seed * 29 + i, Prop = "none", CF = S * CFrame.new(0, 0, 2.0), Anim = i % 2 == 0 and "talk" or "scan" })
			if i <= 2 then
				-- un client devant l'étal
				addAgent(s, { Kind = "static", Style = "shopper", Seed = spot.Seed * 31 + i, Prop = "bag", CF = S * CFrame.new(0.8, 0, -2.6) * CFrame.Angles(0, math.pi, 0), Anim = "idle" })
			end
		end
	end
end

----------------------------------------------------------------------
-- Construction / animation
----------------------------------------------------------------------

local function agentCF(a: Agent, now: number): CFrame
	if a.Kind == "walk" then
		return walkerCF(a, now)
	end
	return a.CF :: CFrame
end

local function buildAgent(s: any, a: Agent)
	local style = a.Style
	-- (les marchands en tablier : NPCModels "baker" = tablier + toque ; au marché on garde la toque)
	local m = NPCModels.Build(style, { Seed = a.Seed, Prop = a.Prop or "none" })
	m.Name = "Person"
	local root = m.PrimaryPart :: BasePart
	root.CFrame = agentCF(a, s.Now)
	m.Parent = s.Folder
	a.Model = m
	if a.Dog then
		local d = buildDog(a.Seed)
		d.Model.Parent = s.Folder
		a.DogModel = d.Model
		;(a :: any).DogRig = d
		local leash = Instance.new("Part")
		leash.Name = "Leash"
		leash.Anchored = true
		leash.CanCollide = false
		leash.CanQuery = false
		leash.CanTouch = false
		leash.CastShadow = false
		leash.Shape = Enum.PartType.Cylinder
		leash.Size = Vector3.new(1, 0.08, 0.08)
		leash.Color = rgb(220, 50, 70)
		leash.Material = Enum.Material.SmoothPlastic
		leash.Parent = s.Folder
		a.Leash = leash
	end
end

local function destroyAgent(a: Agent)
	if a.Model then
		a.Model:Destroy()
	end
	if a.DogModel then
		a.DogModel:Destroy()
	end
	if a.Leash then
		a.Leash:Destroy()
	end
	a.Model, a.DogModel, a.Leash = nil, nil, nil
	;(a :: any).DogRig = nil
end

local function animateAgent(a: Agent, now: number)
	local m = a.Model
	if not m then
		return
	end
	local cf = agentCF(a, now)
	a.Pos = cf.Position
	local root = m.PrimaryPart
	if root then
		root.CFrame = cf
	end
	local t = now + a.Phase
	if a.Kind == "walk" then
		-- (cadence proportionnelle à la vitesse : ~4 studs / s = pas normal)
		NPCModels.Animate(m, "walk", t * (a.Speed / 4))
		local rig = (a :: any).DogRig
		if rig then
			-- le chien trotte un peu devant, côté bordure
			local dogCF = walkerCF({
				Path = a.Path,
				Offset = a.Offset,
				Dir = a.Dir,
				Speed = a.Speed,
				Along = a.Dir * 2.4,
				Lateral = a.Lateral - a.Dir * 1.0,
			} :: any, now)
			animateDog(rig, dogCF, t, true)
			local leash = a.Leash
			if leash then
				local hand = (cf * CFrame.new(-0.9, 2.1, -0.35)).Position
				local collar = (dogCF * CFrame.new(0, 1.78, -0.92)).Position
				local mid = (hand + collar) / 2
				local len = (collar - hand).Magnitude
				leash.Size = Vector3.new(len, 0.08, 0.08)
				leash.CFrame = CFrame.lookAt(mid, collar) * CFrame.Angles(0, math.pi / 2, 0)
			end
		end
	else
		NPCModels.Animate(m, a.Anim, t)
	end
end

----------------------------------------------------------------------
-- Chargement
----------------------------------------------------------------------

local ANCHOR_KINDS = { "SitBench", "Terrace", "ChessTables", "Chat", "Wait", "Kiosk", "FlowerStall", "BookStall", "MarketSquare" }

local function load(s: any): boolean
	local town = workspace:FindFirstChild("DopamineTown")
	local data = town and town:FindFirstChild("StreetLife")
	if not town or not data then
		return false
	end
	local paths: { Path } = {}
	local anchors: { [string]: { { CF: CFrame, Seed: number } } } = {}
	for _, kind in ipairs(ANCHOR_KINDS) do
		anchors[kind] = {}
	end
	for _, child in ipairs(data:GetChildren()) do
		if child.Name == "Path" then
			local pts = child:GetAttribute("Points")
			local name = child:GetAttribute("Name")
			if type(pts) == "string" and type(name) == "string" then
				local path = makePath(name, parsePoints(pts), child:GetAttribute("Loop") == true)
				if path then
					table.insert(paths, path)
				end
			end
		else
			local text = child:GetAttribute("Data")
			if type(text) == "string" then
				for _, line in ipairs(string.split(text, "\n")) do
					local f = string.split(line, ";")
					local list = anchors[f[1]]
					local x, y, z, yaw = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
					if list and x and y and z and yaw then
						table.insert(list, { CF = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), Seed = tonumber(f[6]) or 0 })
					end
				end
			end
		end
	end
	-- (ordre stable : même population sur tous les clients)
	table.sort(paths, function(a, b)
		return a.Name < b.Name
	end)
	for _, list in pairs(anchors) do
		table.sort(list, function(a, b)
			local pa, pb = a.CF.Position, b.CF.Position
			if pa.X ~= pb.X then
				return pa.X < pb.X
			end
			return pa.Z < pb.Z
		end)
	end
	-- le petit tour de la place (autour de la fontaine)
	local plaza = town:GetAttribute("PlazaCF")
	if typeof(plaza) == "CFrame" then
		local ring = {}
		for i = 0, 23 do
			local ang = i / 24 * math.pi * 2
			table.insert(ring, plaza.Position + Vector3.new(math.sin(ang) * 26, 0.08, math.cos(ang) * 26))
		end
		local path = makePath("PlazaRing", ring, true)
		if path then
			table.insert(paths, path)
		end
	end
	s.Paths = paths
	s.Anchors = anchors
	s.Agents = {}
	populate(s)
	local folder = Instance.new("Folder")
	folder.Name = TownPeople.FOLDER_NAME
	folder.Parent = workspace
	s.Folder = folder
	s.Loaded = true
	return true
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function TownPeople.Start()
	if state then
		return
	end
	state = { Agents = {}, Paths = {}, Anchors = {}, Loaded = false, Retry = 0, Now = serverNow(), AccFast = 0, AccSlow = 0, Focus = nil }
	pcall(load, state)
	state.Conn = RunService.Heartbeat:Connect(function(dt: number)
		local s = state
		if not s or not s.Loaded then
			return
		end
		s.AccFast += dt
		s.AccSlow += dt
		local fast = s.AccFast >= FAST_STEP
		local slow = s.AccSlow >= SLOW_STEP
		if not fast then
			return
		end
		s.AccFast = 0
		if slow then
			s.AccSlow = 0
		end
		local now = serverNow()
		s.Now = now
		local focus = s.Focus
		local ok, err = pcall(function()
			for _, a: Agent in ipairs(s.Built) do
				local near = focus == nil or (a.Pos - focus).Magnitude < FAST_RANGE
				if near or slow then
					animateAgent(a, now)
				end
			end
		end)
		if not ok and not s.Warned then
			s.Warned = true
			warn("[TownPeople] " .. tostring(err))
		end
	end)
	state.Built = {}
end

function TownPeople.Step(position: Vector3)
	local s = state
	if not s then
		return
	end
	if not s.Loaded then
		s.Retry -= 1
		if s.Retry <= 0 then
			s.Retry = 4
			pcall(load, s)
		end
		return
	end
	s.Focus = position
	local now = serverNow()
	s.Now = now
	local scale, low = quality()
	local nearIn, nearOut = NEAR_IN * scale, NEAR_OUT * scale
	local maxBuilt = low and math.floor(TownPeople.MAX_BUILT / 2) or TownPeople.MAX_BUILT
	-- distances (tous les passants "existent" ; on ne construit que les plus proches)
	local cands = {}
	for _, a: Agent in ipairs(s.Agents) do
		local p = agentCF(a, now).Position
		a.Pos = p
		local d = (Vector3.new(p.X - position.X, 0, p.Z - position.Z)).Magnitude
		if d < nearOut then
			table.insert(cands, { A = a, D = d })
		end
	end
	table.sort(cands, function(x, y)
		return x.D < y.D
	end)
	local wanted: { [Agent]: boolean } = {}
	for i, c in ipairs(cands) do
		if i > maxBuilt then
			break
		end
		-- (hystérésis : un passant déjà construit reste jusqu'à NEAR_OUT)
		if c.D < nearIn or c.A.Model then
			wanted[c.A] = true
		end
	end
	local built = {}
	for _, a: Agent in ipairs(s.Built) do
		if wanted[a] then
			table.insert(built, a)
		else
			destroyAgent(a)
		end
	end
	local builds = 0
	for _, c in ipairs(cands) do
		local a = c.A
		if wanted[a] and not a.Model and builds < BUILDS_PER_STEP then
			builds += 1
			local ok, err = pcall(buildAgent, s, a)
			if ok then
				table.insert(built, a)
				animateAgent(a, now)
			else
				warn("[TownPeople] " .. tostring(err))
				destroyAgent(a)
			end
		end
	end
	s.Built = built
end

-- (rendus / tests) une image d'animation tout de suite
function TownPeople.Frame(_dt: number?, position: Vector3?)
	local s = state
	if not s or not s.Loaded then
		return
	end
	if position then
		s.Focus = position
	end
	local now = serverNow()
	for _, a: Agent in ipairs(s.Built) do
		animateAgent(a, now)
	end
end

function TownPeople.Positions(): { Vector3 }
	local out = {}
	local s = state
	if s and s.Built then
		for _, a: Agent in ipairs(s.Built) do
			if a.Kind == "walk" then
				table.insert(out, a.Pos)
			end
		end
	end
	return out
end

function TownPeople.Stop()
	local s = state
	state = nil
	if not s then
		return
	end
	if s.Conn then
		s.Conn:Disconnect()
	end
	for _, a in ipairs(s.Agents) do
		destroyAgent(a)
	end
	if s.Folder then
		s.Folder:Destroy()
	end
end

function TownPeople.Debug(): any
	local s = state
	if not s then
		return { Started = false }
	end
	local walkers, statics, parts = 0, 0, 0
	for _, a: Agent in ipairs(s.Agents) do
		if a.Kind == "walk" then
			walkers += 1
		else
			statics += 1
		end
	end
	for _, a: Agent in ipairs(s.Built or {}) do
		if a.Model then
			parts += NPCModels.PartCount(a.Model)
		end
	end
	local names = {}
	for _, p: Path in ipairs(s.Paths) do
		table.insert(names, p.Name .. "=" .. math.floor(p.Length))
	end
	return { Agents = #s.Agents, Walkers = walkers, Statics = statics, Built = s.Built and #s.Built or 0, Parts = parts, Paths = table.concat(names, " ") }
end

return TownPeople
