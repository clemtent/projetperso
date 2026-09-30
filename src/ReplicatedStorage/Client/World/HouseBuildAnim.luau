--[[
	HouseBuildAnim (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseBuildAnim

	🏗️ v10 (CONSTRUCT10) : la maison d'un joueur SE CONSTRUIT sous nos yeux
	(~11,5 s, passable), avec les VRAIES pièces de la maison (HouseBuilder) :
	pas de maquette à part, donc la fin tombe EXACTEMENT sur la maison
	normale (aucune double géométrie, aucun z-fight).
	  0,0 s  chantier dégagé (nuage de poussière) ;
	  1,0 s  fondations coulées (elles montent du sol, en onde depuis le centre) ;
	  2,7 s  murs étage par étage : les petites pièces s'empilent comme des
	         briques (bas -> haut, gauche -> droite), les grands panneaux
	         glissent en place ; l'échafaudage monte avec chaque étage ;
	  6,5 s  le toit : chaque pièce arrive du ciel en arc, en tournoyant,
	         depuis la grue, et se pose avec un petit rebond ;
	  8,3 s  fenêtres, portes, volets : ils "poppent" avec des étincelles ;
	         l'intérieur apparaît en fondu ;
	  9,3 s  l'échafaudage redescend, la grue s'en va ;
	  9,6 s  le jardin POUSSE (clôtures, arbres, fleurs grandissent du sol) ;
	 11,4 s  confettis, la maison est prête.
	Tout est interpolé (Out-Back / Out-Cubic / arcs), jamais de saut.

	Comment (sûr) :
	  - masquer = LocalTransparencyModifier (jamais Transparency : HouseBuilder
	    garde la main sur les vitres, lueurs, remplissages) ; Decal / Texture
	    aussi ; SurfaceGui / BillboardGui / lumières / particules / invites
	    coupées puis RENDUES quand leur pièce se pose (seulement si personne
	    ne les a changées entre-temps) ;
	  - bouger = workspace:BulkMoveTo, puis CFrame final EXACT ;
	  - une pièce déplacée par quelqu'un d'autre pendant l'animation (porte qui
	    s'ouvre…) est lâchée : on ne la touche plus ;
	  - CanCollide coupé pendant le vol, rendu à l'atterrissage ;
	  - une pièce ajoutée pendant l'animation (pièce en flux, jardin) est
	    masquée puis apparaît à sa phase ;
	  - phase d'une pièce : attribut "BuildPhase" (HOUSE10) sur la pièce ou un
	    parent (Foundation / Walls / Roof / Openings / Garden / Interior),
	    sinon déduite de la géométrie et du nom ;
	  - attribut "Constructing" = true sur le modèle pendant l'animation ;
	    house:HoldFull(true / false) s'il existe (LOD complet pendant ce temps).

	API :
	  HouseBuildAnim.new(house, opts) -> Anim
	    opts : { Parent: Instance?, Crane: rig?, OnDone: (skipped) -> ()?, Seed: number? }
	  anim:Prepare()    (masque tout de suite : idempotent)
	  anim:Play()       (démarre la frise)
	  anim:Step(dt)     (à chaque image)
	  anim:Finish(skipped?)  (état final immédiat, tout rendu)
	  anim:Progress() -> 0..1 ; anim:PhaseName() -> clé ; anim.Done
	  HouseBuildAnim.DURATION ; HouseBuildAnim.Classify(house, part) (tests)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Kit = require(script.Parent.ConstructionKit)

local HouseBuildAnim = {}
HouseBuildAnim.__index = HouseBuildAnim

HouseBuildAnim.DURATION = 11.6

-- Fenêtres de la frise (secondes depuis Play)
local W = {
	Clear = { 0, 1.2 },
	Foundation = { 1.0, 2.9 },
	Walls = { 2.7, 6.9 },
	Roof = { 6.5, 8.7 },
	Openings = { 8.3, 9.7 },
	Interior = { 8.6, 9.8 },
	ScaffoldDown = { 9.3, 10.4 },
	Garden = { 9.6, 11.3 },
	Finale = 11.4,
}
HouseBuildAnim.Windows = W

local DUR = { Foundation = 0.6, Walls = 0.5, Roof = 0.8, Openings = 0.45, Interior = 0.6, Garden = 0.75 }

-- Clés de nom -> phase (repli si l'attribut BuildPhase manque)
local NAME_RULES = {
	{ "Interior", { "Hall", "Console", "Coat", "Foyer", "Chandelier", "Landing", "Stair", "Tread", "Riser", "Newel", "Nosing", "Runner", "Skirting", "Closet", "Picture", "KeyBowl", "Shoe", "Hat", "Mirror", "Shelf", "Scarf", "Ceiling", "UnderStair", "Fountain" } },
	{ "Roof", { "Roof", "Ridge", "Hip", "Gutter", "Downpipe", "Chimney", "Dormer", "Eave", "Tile", "Slate", "Shingle", "Fascia", "Crest", "Parapet", "Coping", "TowerTop", "TowerCrown", "TowerScallop", "Smoke", "WaterTank", "Tank", "Pediment", "Gable", "Soffit", "Finial", "Spire", "Weathervane" } },
	{ "Openings", { "Window", "Win", "Glass", "Pane", "Mullion", "Sill", "Shutter", "Door", "Knob", "Jamb", "Transom", "Curtain", "Lantern", "Lamp", "Bulb", "Plaque", "NamePlate", "NamePanel", "Sign", "Canopy", "Hood", "Mat", "Glow", "Fill", "Keystone", "FlowerBox", "Awning", "Handle", "Letter", "Number" } },
	{ "Garden", { "Fence", "Picket", "Gate", "Path", "Bush", "Shrub", "Tree", "Trunk", "Leaves", "Bloom", "Flower", "Planter", "Plant", "Hedge", "Lawn", "Driveway", "Mailbox", "MailBox", "Urn", "Garden", "Flamingo", "Gnome", "Bird", "Pond", "Stalk", "Fruit", "Trampoline", "Umbrella", "Parasol", "Bike", "LightPole", "LampPost", "Grass", "Rock", "Stone", "Bench", "Pool" } },
	{ "Foundation", { "Foundation", "Plinth", "Porch", "Step", "Stoop", "Terrace", "Footing", "Base" } },
}

local function namePhase(name: string): string?
	for _, rule in ipairs(NAME_RULES) do
		for _, key in ipairs(rule[2]) do
			if string.find(name, key, 1, true) then
				return rule[1]
			end
		end
	end
	return nil
end

local VALID = { Foundation = true, Walls = true, Roof = true, Openings = true, Garden = true, Interior = true }

local function attrPhase(part: Instance, stop: Instance): string?
	local node: Instance? = part
	while node and node ~= stop do
		local value = node:GetAttribute("BuildPhase")
		if type(value) == "string" and VALID[value] then
			return value
		end
		node = node.Parent
	end
	return nil
end

-- Géométrie de la maison (repère local x, y, d ; d = profondeur vers l'intérieur)
local function geometry(house: any): any
	local size = house.Size
	local dims = WorldLayout.Dims(size)
	return {
		CF = house.HouseCF,
		Left = dims.Left,
		Right = dims.Left + dims.Width,
		Depth = dims.Depth,
		Height = dims.Height,
		Floors = dims.Floors,
		Ground = WorldLayout.GROUND_Y + 0.05,
	}
end

-- Boîte (repère maison) d'une pièce : centre local + demi-étendues
local function localBox(g: any, part: BasePart): (Vector3, Vector3)
	local rel = g.CF:ToObjectSpace(part.CFrame)
	local s = part.Size / 2
	local r = rel.Rotation
	local rx, ry, rz = r.RightVector, r.UpVector, r.LookVector
	local ex = math.abs(rx.X) * s.X + math.abs(ry.X) * s.Y + math.abs(rz.X) * s.Z
	local ey = math.abs(rx.Y) * s.X + math.abs(ry.Y) * s.Y + math.abs(rz.Y) * s.Z
	local ez = math.abs(rx.Z) * s.X + math.abs(ry.Z) * s.Y + math.abs(rz.Z) * s.Z
	-- (d = -z local)
	return Vector3.new(rel.Position.X, rel.Position.Y, -rel.Position.Z), Vector3.new(ex, ey, ez)
end

local function classify(house: any, g: any, part: BasePart): string
	local model = house.Model
	local tagged = attrPhase(part, model)
	if tagged then
		return tagged
	end
	local interiors = house.Interiors
	if interiors and part:IsDescendantOf(interiors) then
		return "Interior"
	end
	local c, e = localBox(g, part)
	local x, y, d = c.X, c.Y, c.Z
	local top, bottom = y + e.Y, y - e.Y
	local inside = x > g.Left - 0.8 and x < g.Right + 0.8 and d > -0.8 and d < g.Depth + 0.8
	local byName = namePhase(part.Name)
	if not inside then
		-- dehors : perron / marches bas près de la façade, jardin plus loin
		local near = x > g.Left - 8 and x < g.Right + 8 and d > -9 and d < g.Depth + 6
		if byName == "Garden" or byName == "Openings" or byName == "Roof" then
			if byName == "Roof" and bottom > WorldLayout.PLINTH + 3 then
				return "Roof"
			end
			if byName == "Openings" and near then
				return "Openings"
			end
			return "Garden"
		end
		if near and top <= WorldLayout.PLINTH + 1.4 then
			return "Foundation"
		end
		if near then
			return "Walls" -- colonnes du porche, garage, balcons
		end
		return "Garden"
	end
	if byName == "Interior" then
		return "Interior"
	end
	if top <= WorldLayout.FloorY(1) + 0.15 then
		return "Foundation"
	end
	if byName == "Roof" or bottom >= g.Height - 0.4 then
		return "Roof"
	end
	if byName == "Openings" then
		return "Openings"
	end
	-- à l'intérieur de l'enveloppe (loin des murs extérieurs) : intérieur
	local envelope = d < 1.8 or d > g.Depth - 1.8 or x < g.Left + 1.8 or x > g.Right - 1.8
	if not envelope and math.max(e.X, e.Z) < 6 then
		return "Interior"
	end
	return "Walls"
end

function HouseBuildAnim.Classify(house: any, part: BasePart): string
	return classify(house, geometry(house), part)
end

----------------------------------------------------------------------
-- Suivi des pièces
----------------------------------------------------------------------

type Track = {
	Part: BasePart,
	Phase: string,
	Final: CFrame,
	Size: Vector3,
	Collide: boolean,
	Start: number,
	Dur: number,
	Motion: string,
	From: CFrame?,
	Arc: number,
	Spin: CFrame?,
	Last: CFrame?,
	State: string, -- "Wait" | "Fly" | "Done" | "Drop"
	Grow: boolean,
	GroundY: number,
	Effects: { { Instance: Instance, Prop: string, Value: any, Set: any } },
	Order: number,
	Late: boolean,
}

local EFFECT_PROPS = {
	SurfaceGui = "Enabled",
	BillboardGui = "Enabled",
	PointLight = "Enabled",
	SpotLight = "Enabled",
	SurfaceLight = "Enabled",
	ParticleEmitter = "Enabled",
	Beam = "Enabled",
	Fire = "Enabled",
	Smoke = "Enabled",
	Sparkles = "Enabled",
	ProximityPrompt = "Enabled",
}

local function easeOutBack(x: number): number
	local c1 = 1.4
	local c3 = c1 + 1
	local u = x - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

local function easeOutCubic(x: number): number
	local u = 1 - x
	return 1 - u * u * u
end

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

export type Anim = typeof(setmetatable({} :: { [string]: any }, HouseBuildAnim))

function HouseBuildAnim.new(house: any, opts: any?): Anim
	local o = opts or {}
	local self = setmetatable({
		House = house,
		Geo = geometry(house),
		Parent = o.Parent or workspace,
		Crane = o.Crane,
		OnDone = o.OnDone,
		Seed = tonumber(o.Seed) or 1,
		Tracks = {} :: { Track },
		LateQueue = {} :: { Track },
		Label = o.Label,
		ByPart = {} :: { [BasePart]: Track },
		Loose = {} :: { { Instance: Instance, Prop: string, Value: any, Set: any } },
		Prepared = false,
		Playing = false,
		Done = false,
		Clock = 0,
		Next = 1,
		Active = {} :: { Track },
		Fx = nil,
		Scaffold = nil,
		Conn = nil,
		Bursts = {},
		PhaseKey = "Clear",
	}, HouseBuildAnim)
	return self
end

-- Coupe un effet (garde la valeur pour la rendre)
local function muteEffect(list: { any }, inst: Instance)
	local prop = EFFECT_PROPS[inst.ClassName]
	if prop then
		local value = (inst :: any)[prop]
		if value == true then
			(inst :: any)[prop] = false
			table.insert(list, { Instance = inst, Prop = prop, Value = value, Set = false })
		end
	elseif inst:IsA("Decal") then
		(inst :: any).LocalTransparencyModifier = 1
		table.insert(list, { Instance = inst, Prop = "LocalTransparencyModifier", Value = 0, Set = 1 })
	end
end

local function restoreEffects(list: { any })
	for _, e in ipairs(list) do
		local inst = e.Instance
		if inst.Parent then
			-- (seulement si personne ne l'a changé entre-temps)
			local ok, current = pcall(function()
				return (inst :: any)[e.Prop]
			end)
			if ok and current == e.Set then
				pcall(function()
					(inst :: any)[e.Prop] = e.Value
				end)
			end
		end
	end
	table.clear(list)
end

function HouseBuildAnim.Track(self: Anim, part: BasePart, late: boolean)
	if self.ByPart[part] then
		return
	end
	local phase = classify(self.House, self.Geo, part)
	local t: Track = {
		Part = part,
		Phase = phase,
		Final = part.CFrame,
		Size = part.Size,
		Collide = part.CanCollide,
		Start = 0,
		Dur = DUR[phase] or 0.5,
		Motion = "Fade",
		From = nil,
		Arc = 0,
		Spin = nil,
		Last = nil,
		State = "Wait",
		Grow = false,
		GroundY = self.Geo.CF.Position.Y + self.Geo.Ground,
		Effects = {},
		Order = 0,
		Late = late,
	}
	part.LocalTransparencyModifier = 1
	part.CanCollide = false
	for _, child in ipairs(part:GetChildren()) do
		muteEffect(t.Effects, child)
		for _, sub in ipairs(child:GetChildren()) do
			muteEffect(t.Effects, sub)
		end
	end
	self.ByPart[part] = t
	if self.Playing then
		-- (pendant la frise : file à part, jamais de tri de toute la liste)
		self:Schedule(t, true)
		table.insert(self.LateQueue, t)
	else
		table.insert(self.Tracks, t)
	end
end

-- Masque tout de suite (la maison est "à construire")
function HouseBuildAnim.Prepare(self: Anim)
	if self.Prepared or self.Done then
		return
	end
	self.Prepared = true
	local house = self.House
	local model: Model = house.Model
	model:SetAttribute("Constructing", true)
	if type(house.HoldFull) == "function" then
		pcall(house.HoldFull, house, true)
	end
	self.Geo = geometry(house)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			self:Track(d, false)
		elseif not d.Parent or not d.Parent:IsA("BasePart") then
			muteEffect(self.Loose, d)
		end
	end
	self.Conn = model.DescendantAdded:Connect(function(d)
		if self.Done then
			return
		end
		if d:IsA("BasePart") then
			self:Track(d, true)
		else
			task.defer(function()
				if self.Done or not d.Parent then
					return
				end
				local parent = d.Parent
				local track = parent and parent:IsA("BasePart") and self.ByPart[parent :: BasePart]
				if track and track.State ~= "Done" and track.State ~= "Drop" then
					muteEffect(track.Effects, d)
				end
			end)
		end
	end)
end

-- Horaire d'une pièce selon sa phase
function HouseBuildAnim.Schedule(self: Anim, t: Track, late: boolean?)
	local g = self.Geo
	local c, e = localBox(g, t.Part)
	local x, y, d = c.X, c.Y, c.Z
	local width = math.max(1, g.Right - g.Left)
	local nx = (x - g.Left) / width
	local jitter = hash(x + self.Seed, y + d)
	local phase = t.Phase
	local w0, w1
	if phase == "Foundation" then
		w0, w1 = W.Foundation[1], W.Foundation[2]
		local cx, cd = (g.Left + g.Right) / 2, g.Depth / 2
		local dist = math.sqrt((x - cx) ^ 2 + (d - cd) ^ 2) / math.max(1, width * 0.7)
		t.Order = math.clamp(dist, 0, 1) * 0.85 + jitter * 0.15
		t.Motion = "Rise"
	elseif phase == "Walls" then
		local floors = math.max(1, g.Floors)
		local bottom = y - e.Y
		local band = math.clamp(math.floor((bottom - WorldLayout.PLINTH) / WorldLayout.STORY), 0, floors - 1)
		local span = (W.Walls[2] - W.Walls[1]) / floors
		w0 = W.Walls[1] + band * span
		w1 = w0 + span + 0.3
		local inBand = math.clamp((bottom - (WorldLayout.PLINTH + band * WorldLayout.STORY)) / WorldLayout.STORY, 0, 1)
		t.Order = inBand * 0.7 + nx * 0.25 + jitter * 0.05
		local long = math.max(t.Size.X, t.Size.Z)
		local thin = math.min(t.Size.X, t.Size.Y, t.Size.Z)
		if long > 9 and thin < 2.5 then
			t.Motion = "Slide"
		else
			t.Motion = "Rise"
		end
	elseif phase == "Roof" then
		w0, w1 = W.Roof[1], W.Roof[2]
		local rel = math.clamp((y - g.Height) / 14, 0, 1)
		t.Order = rel * 0.75 + jitter * 0.25
		t.Motion = "Fly"
	elseif phase == "Openings" then
		w0, w1 = W.Openings[1], W.Openings[2]
		local floor = math.clamp((y - WorldLayout.PLINTH) / math.max(1, g.Height - WorldLayout.PLINTH), 0, 1)
		t.Order = floor * 0.5 + nx * 0.4 + jitter * 0.1
		t.Motion = "Pop"
	elseif phase == "Garden" then
		w0, w1 = W.Garden[1], W.Garden[2]
		local door = Vector3.new((g.Left + g.Right) / 2, 0, -2)
		local dist = (Vector3.new(x, 0, d) - door).Magnitude / 60
		t.Order = math.clamp(dist, 0, 1) * 0.85 + jitter * 0.15
		t.Motion = "Grow"
		local part = t.Part
		t.Grow = (part.ClassName == "Part" or part.ClassName == "WedgePart") and part:FindFirstChildWhichIsA("SurfaceGui") == nil
			and part:FindFirstChildWhichIsA("Decal") == nil and part.Size.Magnitude < 40
	else
		w0, w1 = W.Interior[1], W.Interior[2]
		t.Order = jitter
		t.Motion = "Fade"
	end
	local dur = DUR[phase] or 0.5
	t.Dur = dur
	t.Start = w0 + t.Order * math.max(0, (w1 - w0) - dur)
	if late then
		-- pièce arrivée en cours de route : à sa phase, ou tout de suite si elle est passée
		t.Start = math.max(t.Start, self.Clock + 0.05)
	end
	-- départ du vol
	local final = t.Final
	local extent = e.Y * 2
	if t.Motion == "Rise" then
		t.From = final - Vector3.new(0, extent + 0.8, 0)
	elseif t.Motion == "Slide" then
		-- le long du grand axe horizontal, vers l'extérieur de la maison
		local axis = if t.Size.X >= t.Size.Z then final.RightVector else final.LookVector
		axis = Vector3.new(axis.X, 0, axis.Z)
		if axis.Magnitude < 1e-3 then
			axis = g.CF.RightVector
		end
		axis = axis.Unit
		local outward = final.Position - g.CF * Vector3.new((g.Left + g.Right) / 2, final.Position.Y - g.CF.Position.Y, -g.Depth / 2)
		if axis:Dot(outward) < 0 then
			axis = -axis
		end
		t.From = final + axis * 9 + Vector3.new(0, 1.5, 0)
	elseif t.Motion == "Fly" then
		local lateral = g.CF.RightVector * ((hash(x, d + 3) - 0.5) * 14) + g.CF.LookVector * (6 + hash(d, x) * 8)
		t.From = final + Vector3.new(0, 22 + hash(y, x) * 10, 0) + lateral
		t.Spin = CFrame.Angles((hash(x, 1) - 0.5) * 0.9, (hash(d, 2) - 0.5) * 1.6, (hash(y, 3) - 0.5) * 0.9)
		t.Arc = 6 + hash(x, y) * 5
	elseif t.Motion == "Pop" then
		local outward = final.Position - g.CF * Vector3.new(x, y, -g.Depth / 2)
		outward = Vector3.new(outward.X, 0, outward.Z)
		outward = if outward.Magnitude > 1e-3 then outward.Unit else -g.CF.LookVector
		t.From = final + outward * 1.6
	elseif t.Motion == "Grow" and not t.Grow then
		t.From = final - Vector3.new(0, math.min(extent, 6) + 0.3, 0)
	end
end

----------------------------------------------------------------------
-- Échafaudage + effets
----------------------------------------------------------------------

local function emitter(parent: Instance, name: string, size: Vector3, cf: CFrame, kind: string): (BasePart, ParticleEmitter)
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = size
	anchor.CFrame = cf
	anchor.Parent = parent
	local em = Instance.new("ParticleEmitter")
	em.Rate = 0
	em.LightEmission = 0
	if kind == "Dust" then
		em.Texture = "rbxasset://textures/particles/smoke_main.dds"
		em.Color = ColorSequence.new(Color3.fromRGB(196, 176, 150), Color3.fromRGB(226, 214, 196))
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		em.Lifetime = NumberRange.new(1.2, 2.2)
		em.Speed = NumberRange.new(3, 7)
		em.SpreadAngle = Vector2.new(80, 20)
		em.Acceleration = Vector3.new(0, 1.5, 0)
		em.Drag = 1.5
	elseif kind == "Sparkle" then
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Color = ColorSequence.new(Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 200, 240))
		em.LightEmission = 0.6
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) })
		em.Lifetime = NumberRange.new(0.5, 0.9)
		em.Speed = NumberRange.new(2, 5)
		em.SpreadAngle = Vector2.new(180, 180)
	else -- Confetti
		em.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 160)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 214, 60)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 210, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 110, 255)),
		})
		em.Size = NumberSequence.new(0.5)
		em.Lifetime = NumberRange.new(2.2, 3.2)
		em.Speed = NumberRange.new(22, 36)
		em.SpreadAngle = Vector2.new(55, 55)
		em.Acceleration = Vector3.new(0, -26, 0)
		em.Drag = 1.2
		em.Rotation = NumberRange.new(0, 360)
		em.RotSpeed = NumberRange.new(-260, 260)
		em.EmissionDirection = Enum.NormalId.Top
	end
	em.Parent = anchor
	return anchor, em
end

local function burst(em: ParticleEmitter?, n: number)
	if em then
		pcall(function()
			em:Emit(n)
		end)
	end
end

function HouseBuildAnim.BuildFx(self: Anim)
	local g = self.Geo
	local fx = Instance.new("Folder")
	fx.Name = "BuildFx_" .. tostring(self.House.UserId or 0)
	fx.Parent = self.Parent
	self.Fx = fx
	local cf = g.CF
	local width = g.Right - g.Left
	local center = cf * CFrame.new((g.Left + g.Right) / 2, g.Ground + 1, -g.Depth / 2)
	local _, dust = emitter(fx, "Dust", Vector3.new(width + 6, 2, g.Depth + 10), center, "Dust")
	self.Dust = dust
	local sparkAnchor, spark = emitter(fx, "Sparkle", Vector3.new(4, 4, 1), center, "Sparkle")
	self.SparkAnchor, self.Spark = sparkAnchor, spark
	local _, confetti = emitter(fx, "Confetti", Vector3.new(width * 0.7, 1, g.Depth * 0.7), cf * CFrame.new((g.Left + g.Right) / 2, g.Height + 4, -g.Depth / 2), "Confetti")
	self.Confetti = confetti
	-- (les autres joueurs) "🏗️ La maison de X se construit !"
	if type(self.Label) == "string" and confetti.Parent then
		local bb = Instance.new("BillboardGui")
		bb.Name = "BuildLabel"
		bb.Size = UDim2.fromScale(26, 4)
		bb.StudsOffset = Vector3.new(0, 6, 0)
		bb.MaxDistance = 320
		bb.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		label.BackgroundTransparency = 0.15
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(236, 72, 140)
		label.Text = self.Label
		label.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.4, 0)
		corner.Parent = label
		bb.Parent = confetti.Parent
	end
	-- échafaudage : façade + 2 côtés, un plancher par étage
	local lifts = math.max(1, g.Floors)
	local liftH = WorldLayout.STORY
	local base = g.Ground
	local faces = {
		{ cf * CFrame.new(g.Right + 1, base, 0.3) * CFrame.Angles(0, math.pi, 0), width + 2 },
		{ cf * CFrame.new(g.Left - 0.3, base, 1) * CFrame.Angles(0, math.pi / 2, 0), g.Depth - 2 },
		{ cf * CFrame.new(g.Right + 0.3, base, -g.Depth + 1) * CFrame.Angles(0, -math.pi / 2, 0), g.Depth - 2 },
	}
	local scaffold = Instance.new("Model")
	scaffold.Name = "Scaffold"
	scaffold.Parent = fx
	local byLift: { { BasePart } } = {}
	for i, face in ipairs(faces) do
		local lists = Kit.Scaffold(scaffold, face[1], face[2], { Lifts = lifts, LiftH = liftH, Bay = 8, Net = i == 1, Ladder = i == 1 })
		for lift, list in ipairs(lists) do
			byLift[lift] = byLift[lift] or {}
			for _, p in ipairs(list) do
				table.insert(byLift[lift], p)
			end
		end
	end
	local sc = { Lifts = {} }
	for lift, list in ipairs(byLift) do
		local finals = {}
		for i, p in ipairs(list) do
			finals[i] = p.CFrame
			p.LocalTransparencyModifier = 1
		end
		local span = (W.Walls[2] - W.Walls[1]) / lifts
		sc.Lifts[lift] = { Parts = list, Finals = finals, Up = W.Walls[1] + (lift - 1) * span - 0.3, Down = W.ScaffoldDown[1] + (lifts - lift) * 0.3 }
	end
	self.Scaffold = sc
	-- grue : celle du chantier, sinon une neuve derrière la maison
	if not self.Crane then
		local x = math.clamp(g.Right - 10, g.Left + 10, g.Right)
		local baseCF = cf * CFrame.new(x, base, -(g.Depth + 10))
		self.Crane = Kit.Crane(fx, baseCF, { Height = math.max(48, g.Height + 22), Jib = 42 })
		self.CraneFresh = true
		for _, d in ipairs(self.Crane.Model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end
	else
		self.Crane.Model.Parent = fx
	end
	local crane = self.Crane
	if crane then
		local craneParts, craneFinals = {}, {}
		for _, d in ipairs(crane.Model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(craneParts, d)
			end
		end
		self.CraneParts = craneParts
		self.CraneFinals = craneFinals
		-- cycle : palette au pied du mât -> sommet de la maison
		local craneBase = crane.Top * CFrame.new(0, -crane.Height, 0)
		local function key(p: Vector3, bottomY: number): { number }
			local rel = craneBase:PointToObjectSpace(p)
			local trolleyY = crane.Height + (crane.JibY or 3.2) - 0.45
			return { math.atan2(-rel.X, -rel.Z), math.sqrt(rel.X * rel.X + rel.Z * rel.Z) - 1.2, trolleyY - 0.6 - (bottomY + 4.8) }
		end
		local pick = (craneBase * CFrame.new(-6, 0, 6)).Position
		local drop = (cf * CFrame.new((g.Left + g.Right) / 2, g.Height + 2, -g.Depth / 2)).Position
		self.CraneKeys = {
			A = key(pick, craneBase:PointToObjectSpace(pick).Y + 0.2),
			B = key(drop, craneBase:PointToObjectSpace(drop).Y),
			High = 7,
		}
	end
end

local function setScaffold(self: Anim, now: number)
	local sc = self.Scaffold
	if not sc then
		return
	end
	for _, lift in ipairs(sc.Lifts) do
		local kUp = math.clamp((now - lift.Up) / 0.5, 0, 1)
		local kDown = math.clamp((now - lift.Down) / 0.5, 0, 1)
		local state = if kDown > 0 then "Down" elseif kUp >= 1 then "Up" elseif kUp > 0 then "Rise" else "Hidden"
		if state ~= lift.State or state == "Rise" or state == "Down" then
			lift.State = state
			local alpha, offset
			if state == "Hidden" then
				alpha, offset = 1, -1.5
			elseif state == "Rise" then
				alpha, offset = 1 - kUp, -1.5 * (1 - easeOutCubic(kUp))
			elseif state == "Up" then
				alpha, offset = 0, 0
			else
				alpha, offset = kDown, -3 * kDown * kDown
			end
			local frames = {}
			for i, p in ipairs(lift.Parts) do
				p.LocalTransparencyModifier = alpha
				frames[i] = lift.Finals[i] + Vector3.new(0, offset, 0)
			end
			workspace:BulkMoveTo(lift.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
end

local function stepCrane(self: Anim, now: number)
	local crane = self.Crane
	if not crane then
		return
	end
	local keys = self.CraneKeys
	-- apparition (grue neuve) / départ
	local leave = W.ScaffoldDown[1] + 0.2
	if now < leave and keys then
		local angle, radius, drop, loaded = Kit.CraneCycle(now * 3.4 + 4, keys.A, keys.B, keys.High)
		crane:Pose(angle, radius, drop, loaded)
		if self.CraneFresh and not self.CraneShown then
			local k = math.clamp(now / 0.8, 0, 1)
			for _, p in ipairs(self.CraneParts or {}) do
				if p.Name ~= "LoadPallet" and p.Name ~= "LoadBricks" and p.Name ~= "Sling" then
					p.LocalTransparencyModifier = 1 - k
				end
			end
			if k >= 1 then
				self.CraneShown = true
			end
		end
	elseif not self.CraneGone then
		if not self.CraneLeaving then
			self.CraneLeaving = true
			self.CraneFinals = {}
			for i, p in ipairs(self.CraneParts or {}) do
				self.CraneFinals[i] = p.CFrame
			end
		end
		local k = math.clamp((now - leave) / 1.1, 0, 1)
		local frames = {}
		for i, p in ipairs(self.CraneParts or {}) do
			frames[i] = self.CraneFinals[i] - Vector3.new(0, 10 * k * k, 0)
			p.LocalTransparencyModifier = math.max(p.LocalTransparencyModifier, k)
		end
		workspace:BulkMoveTo(self.CraneParts or {}, frames, Enum.BulkMoveMode.FireCFrameChanged)
		if k >= 1 then
			self.CraneGone = true
			crane.Model:Destroy()
		end
	end
end

----------------------------------------------------------------------
-- Frise
----------------------------------------------------------------------

function HouseBuildAnim.Play(self: Anim)
	if self.Playing or self.Done then
		return
	end
	self:Prepare()
	self.Playing = true
	self.Clock = 0
	for _, t in ipairs(self.Tracks) do
		self:Schedule(t, false)
	end
	table.sort(self.Tracks, function(a, b)
		return a.Start < b.Start
	end)
	self.Next = 1
	local ok, err = pcall(self.BuildFx, self)
	if not ok then
		warn("[HouseBuildAnim] effets : " .. tostring(err))
	end
	burst(self.Dust, 36)
end

local PHASE_ORDER = { "Clear", "Foundation", "Walls", "Roof", "Openings", "Garden", "Finale" }

function HouseBuildAnim.PhaseName(self: Anim): string
	local now = self.Clock
	if now >= W.Finale then
		return "Finale"
	elseif now >= W.Garden[1] then
		return "Garden"
	elseif now >= W.Openings[1] then
		return "Openings"
	elseif now >= W.Roof[1] then
		return "Roof"
	elseif now >= W.Walls[1] then
		return "Walls"
	elseif now >= W.Foundation[1] then
		return "Foundation"
	end
	return "Clear"
end
HouseBuildAnim.PhaseOrder = PHASE_ORDER

function HouseBuildAnim.Progress(self: Anim): number
	if self.Done then
		return 1
	end
	return math.clamp(self.Clock / W.Finale, 0, 1)
end

-- Pose d'une pièce en vol (k = 0..1)
local function flyFrame(t: Track, k: number): (CFrame, number)
	local final = t.Final
	local from = t.From
	local alpha = 0
	if t.Motion == "Rise" then
		local e = easeOutBack(k)
		alpha = 1 - math.clamp(k * 3, 0, 1)
		return (from :: CFrame):Lerp(final, e), alpha
	elseif t.Motion == "Slide" then
		local e = easeOutCubic(k)
		alpha = 1 - math.clamp(k * 2.5, 0, 1)
		return (from :: CFrame):Lerp(final, e), alpha
	elseif t.Motion == "Fly" then
		-- arc (parabole) + rotation qui se défait, petit rebond à la pose
		local e = if k < 0.85 then Kit.Smooth(k / 0.85) else 1
		local cf = (from :: CFrame):Lerp(final, e)
		local lift = 4 * e * (1 - e) * t.Arc
		local bounce = if k >= 0.85 then math.sin((k - 0.85) / 0.15 * math.pi) * 0.35 else 0
		local spin = (t.Spin :: CFrame):Lerp(CFrame.identity, e)
		alpha = 1 - math.clamp(k * 4, 0, 1)
		return CFrame.new(cf.Position + Vector3.new(0, lift + bounce, 0)) * final.Rotation * spin, alpha
	elseif t.Motion == "Pop" then
		local e = easeOutBack(k)
		alpha = 1 - math.clamp(k * 3.5, 0, 1)
		return (from :: CFrame):Lerp(final, e), alpha
	elseif t.Motion == "Grow" then
		if from then
			local e = easeOutBack(k)
			alpha = 1 - math.clamp(k * 3, 0, 1)
			return from:Lerp(final, e), alpha
		end
		alpha = 1 - math.clamp(k * 4, 0, 1)
		return final, alpha
	end
	-- Fade
	return final, 1 - k
end

local function landed(self: Anim, t: Track)
	local part = t.Part
	if part.Parent then
		if t.State ~= "Drop" then
			part.CFrame = t.Final
		end
		if t.Grow then
			part.Size = t.Size
			if t.State ~= "Drop" then
				part.CFrame = t.Final
			end
		end
		part.LocalTransparencyModifier = 0
		if part.CanCollide == false then
			part.CanCollide = t.Collide
		end
	end
	restoreEffects(t.Effects)
	t.State = if t.State == "Drop" then "Drop" else "Done"
end

-- Une pièce décolle
function HouseBuildAnim.Activate(self: Anim, t: Track)
	if t.State ~= "Wait" then
		return
	end
	if not t.Part.Parent then
		t.State = "Done"
		restoreEffects(t.Effects)
	elseif (t.Part.CFrame.Position - t.Final.Position).Magnitude > 1e-3 then
		-- déplacée par quelqu'un d'autre (porte…) : simple fondu, sans la bouger
		t.Final = t.Part.CFrame
		t.Motion = "Fade"
		t.Grow = false
		t.State = "Fly"
		table.insert(self.Active, t)
	else
		t.State = "Fly"
		table.insert(self.Active, t)
		-- étincelles (une par paquet de fenêtres)
		if t.Phase == "Openings" and self.Spark and self.SparkAnchor then
			local p = t.Final.Position
			local key = math.floor(p.X / 7) .. ":" .. math.floor(p.Y / 7) .. ":" .. math.floor(p.Z / 7)
			if not self.Bursts[key] then
				self.Bursts[key] = true
				self.SparkAnchor.CFrame = t.Final
				burst(self.Spark, 8)
			end
		end
	end
end

function HouseBuildAnim.Step(self: Anim, dt: number)
	if self.Done or not self.Playing then
		return
	end
	local house = self.House
	if house.Alive == false or not house.Model.Parent then
		self:Finish(true)
		return
	end
	self.Clock += math.min(dt, 0.1)
	local now = self.Clock
	self.PhaseKey = self:PhaseName()
	-- nouvelles pièces qui décollent
	local tracks = self.Tracks
	while self.Next <= #tracks and tracks[self.Next].Start <= now do
		local t = tracks[self.Next]
		self.Next += 1
		self:Activate(t)
	end
	if #self.LateQueue > 0 then
		local waiting = {}
		for _, t in ipairs(self.LateQueue) do
			if t.Start <= now then
				self:Activate(t)
			else
				table.insert(waiting, t)
			end
		end
		self.LateQueue = waiting
	end
	-- vols en cours
	local moving, frames = {}, {}
	local keep = {}
	for _, t in ipairs(self.Active) do
		local part = t.Part
		if not part.Parent then
			t.State = "Done"
		elseif t.Last and (part.CFrame.Position - t.Last.Position).Magnitude > 1e-3 then
			-- lâchée (bougée ailleurs) : visible, plus jamais touchée
			t.State = "Drop"
			landed(self, t)
		else
			local k = math.clamp((now - t.Start) / t.Dur, 0, 1)
			if k >= 1 then
				landed(self, t)
			else
				local cf, alpha = flyFrame(t, k)
				part.LocalTransparencyModifier = alpha
				if t.Grow then
					local s = math.max(0.05, easeOutBack(k))
					part.Size = t.Size * s
					local p = t.Final.Position
					cf = CFrame.new(p.X, t.GroundY + (p.Y - t.GroundY) * s, p.Z) * t.Final.Rotation
				end
				if t.Motion ~= "Fade" then
					table.insert(moving, part)
					table.insert(frames, cf)
					t.Last = cf
				end
				table.insert(keep, t)
			end
		end
	end
	self.Active = keep
	if #moving > 0 then
		workspace:BulkMoveTo(moving, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	pcall(setScaffold, self, now)
	pcall(stepCrane, self, now)
	if now >= W.Foundation[1] and not self.DustTwo then
		self.DustTwo = true
		burst(self.Dust, 30)
	end
	if now >= W.Finale then
		burst(self.Confetti, 140)
		self:Finish(false)
	end
end

-- État final immédiat (fin normale ou "Passer") : tout est rendu exactement
function HouseBuildAnim.Finish(self: Anim, skipped: boolean?)
	if self.Done then
		return
	end
	self.Done = true
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
	for _, t in ipairs(self.LateQueue) do
		table.insert(self.Tracks, t)
	end
	self.LateQueue = {}
	for _, t in ipairs(self.Tracks) do
		if t.State ~= "Done" and t.State ~= "Drop" then
			if t.State == "Wait" and t.Part.Parent and (t.Part.CFrame.Position - t.Final.Position).Magnitude > 1e-3 then
				t.State = "Drop" -- (bougée par quelqu'un d'autre : on la laisse où elle est)
			end
			landed(self, t)
		end
	end
	restoreEffects(self.Loose)
	local house = self.House
	pcall(function()
		house.Model:SetAttribute("Constructing", nil)
	end)
	if type(house.HoldFull) == "function" then
		pcall(house.HoldFull, house, false)
	end
	local fx = self.Fx
	if fx then
		if skipped then
			fx:Destroy()
		else
			-- (laisse retomber les confettis puis nettoie)
			if self.Crane and not self.CraneGone and self.Crane.Model then
				self.Crane.Model:Destroy()
			end
			local sc = self.Scaffold
			if sc then
				for _, lift in ipairs(sc.Lifts) do
					for _, p in ipairs(lift.Parts) do
						p:Destroy()
					end
				end
			end
			task.delay(3.5, function()
				fx:Destroy()
			end)
		end
		self.Fx = nil
	elseif self.Crane and self.Crane.Model then
		self.Crane.Model:Destroy()
	end
	self.Playing = false
	local onDone = self.OnDone
	if onDone then
		task.spawn(onDone, skipped == true)
	end
end

return HouseBuildAnim
