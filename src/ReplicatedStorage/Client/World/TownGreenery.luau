--[[
	TownGreenery (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownGreenery

	🌳 Dopamine Town (v9.7, NATURE97) : les détails "de près" de la nature,
	construits côté CLIENT autour de l'avatar seulement (budget de pièces du
	serveur) :
	  - ARBRES : le serveur construit la silhouette (niveau 0) ou l'arbre
	    "vedette" (niveau 1) avec Shared/Greenery ; ici on ajoute le niveau 2
	    (racines, branche et grappes en plus, fruits, marques du bouleau,
	    noix de coco, pétales tombés) aux arbres à moins de ~150 studs. Même
	    graine -> même arbre pour tout le monde, les pièces ajoutées
	    s'emboîtent sans face confondue (voir Greenery) ;
	  - LAC ("NearDetail" = "Lake") : nénuphars (quelques-uns fleuris),
	    canards et cygnes qui glissent doucement sur l'eau, roseaux et
	    touffes d'herbe en plus sur la rive ;
	  - AIRE DE JEUX ("NearDetail" = "Playground") : v9.9 (PARK99) toute
	    l'aire de jeux réaliste et animée (ParkPlay).
	Tout est ancré, sans collision ni requête, sans ombre pour les petites
	pièces. Construction étalée (quelques arbres par pas), destruction au-delà
	d'une marge (hystérésis) ; seuls les oiseaux bougent (≤ 15 Hz, CFrame),
	et seulement quand le lac est construit.

	API (TownClient, via optionalModule) :
	  TownGreenery.Start()                   à l'entrée en ville
	  TownGreenery.Step(position: Vector3)   flux (4 fois / s)
	  TownGreenery.Stop()                    à la sortie
	  TownGreenery.Debug() -> table          (tests / rendus)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Greenery = require(ReplicatedStorage.Shared.Greenery)

local TownGreenery = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local hash = Greenery.Hash
local LAKE = Greenery.LAKE

local FOLDER_NAME = "TownGreenery"
local TREE_IN, TREE_OUT = 150, 190 -- (studs) construire / détruire
local DETAIL_IN, DETAIL_OUT = 220, 270
-- v9.8 🎨 Graphismes > Détail (REALISM98) : distances de flux ×0,65 / ×1 / ×1,35
local okGQ, GraphicsQuality = pcall(require, game:GetService("ReplicatedStorage").Shared.GraphicsQuality)
local function detailScale(): number
	return okGQ and type(GraphicsQuality) == "table" and GraphicsQuality.DetailScale and GraphicsQuality.DetailScale() or 1
end
local BUILDS_PER_STEP = 5
local BIRD_HZ = 15

type Tree = { Model: Model, Base: Vector3, Near: Model? }
type Detail = { Model: Model, Kind: string, CF: CFrame, R: number, Near: Model?, Birds: { any }?, Seed: number? }

local started = false
local folder: Folder? = nil
local trees: { Tree } = {}
local details: { Detail } = {}
local conns: { RBXScriptConnection } = {}
local rescan = 0
local birdClock = 0
local clock = 0

----------------------------------------------------------------------
-- Petites fabriques (tout en décor : pas de collision, pas de requête)
----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
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
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
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
	local p = newPart(parent, name, Vector3.new(d, d, d), CFrame.new(center), color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- disque à plat (axe vertical), dessus à `top`
local function disc(parent: Instance, name: string, cf: CFrame, top: number, radius: number, thickness: number, color: Color3, material: Enum.Material?): Part
	local p = newPart(parent, name, Vector3.new(thickness, radius * 2, radius * 2), cf * CFrame.new(0, top - thickness / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?): Part
	local axis = (b - a).Unit
	local up = math.abs(axis.Y) > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local p = newPart(parent, name, Vector3.new((b - a).Magnitude, d, d), CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

----------------------------------------------------------------------
-- Oiseaux du lac (un Model par oiseau, pièces placées depuis des décalages figés)
----------------------------------------------------------------------

local function duck(parent: Instance, kind: number): Model
	local m = Instance.new("Model")
	m.Name = "Duck"
	local body = kind == 1 and rgb(150, 126, 104) or (kind == 2 and rgb(255, 255, 255) or rgb(255, 226, 110))
	local head = kind == 1 and rgb(40, 120, 76) or body
	local root = egg(m, "DuckBody", CFrame.new(0, 0.35, 0), Vector3.new(1.1, 0.8, 1.7), body)
	ball(m, "DuckHead", Vector3.new(0, 0.95, -0.62), 0.7, head)
	egg(m, "DuckBeak", CFrame.new(0, 0.9, -1.05), Vector3.new(0.34, 0.16, 0.42), rgb(255, 160, 60))
	egg(m, "DuckTail", CFrame.new(0, 0.62, 0.78) * CFrame.Angles(math.rad(-30), 0, 0), Vector3.new(0.5, 0.3, 0.6), body)
	m.PrimaryPart = root
	m.Parent = parent
	return m
end

local function swan(parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "Swan"
	local white = rgb(252, 252, 255)
	local root = egg(m, "SwanBody", CFrame.new(0, 0.5, 0), Vector3.new(1.7, 1.1, 2.9), white)
	egg(m, "SwanWing", CFrame.new(0, 0.85, 0.35), Vector3.new(1.5, 0.7, 1.9), rgb(240, 242, 248))
	rod(m, "SwanNeck", Vector3.new(0, 0.8, -1.05), Vector3.new(0, 2.3, -1.3), 0.34, white)
	ball(m, "SwanHead", Vector3.new(0, 2.4, -1.42), 0.62, white)
	egg(m, "SwanBeak", CFrame.new(0, 2.32, -1.86), Vector3.new(0.22, 0.2, 0.5), rgb(255, 140, 60))
	m.PrimaryPart = root
	m.Parent = parent
	return m
end

----------------------------------------------------------------------
-- Détails du lac et de l'aire de jeux
----------------------------------------------------------------------

local function buildLake(d: Detail, parent: Model)
	local L, R = d.CF, d.R
	local bx = LAKE.BridgeX * R
	local ix, iz, ir = LAKE.Island[1] * R, LAKE.Island[2] * R, math.max(4.5, LAKE.Island[3] * R)
	local jx, jz = LAKE.Jet[1] * R, LAKE.Jet[2] * R
	local function freeWater(x: number, z: number, margin: number): boolean
		if x * x + z * z > (R - 3 - margin) ^ 2 then
			return false
		end
		if math.abs(x - bx) < LAKE.BridgeHalfW + 2 + margin then
			return false
		end
		if (x - ix) ^ 2 + (z - iz) ^ 2 < (ir + 2 + margin) ^ 2 or (x - jx) ^ 2 + (z - jz) ^ 2 < (3 + margin) ^ 2 then
			return false
		end
		-- (ponton et bateaux : bande le long de +X)
		if x > R * 0.45 and math.abs(z - LAKE.DockZ * R) < 7 + margin then
			return false
		end
		return true
	end
	-- nénuphars (feuilles à plat sur l'eau), quelques-uns fleuris
	local pads = 0
	for k = 1, 30 do
		if pads >= 9 then
			break
		end
		local a = hash(k, 201) * math.pi * 2
		local r = R * (0.3 + hash(k, 202) * 0.62)
		local x, z = math.sin(a) * r, math.cos(a) * r
		if freeWater(x, z, 1.5) then
			pads += 1
			local size = 1.1 + hash(k, 203) * 0.7
			local cf = L * CFrame.new(x, 0, z) * CFrame.Angles(0, hash(k, 204) * 6, 0)
			disc(parent, "LilyPad", cf, LAKE.WaterTop + 0.08 + (pads % 3) * 0.02, size, 0.06, rgb(96, 176, 96):Lerp(rgb(140, 200, 110), hash(k, 205)), M.Grass)
			if pads % 3 == 1 then
				local top = (cf * CFrame.new(0.2, LAKE.WaterTop + 0.34, 0)).Position
				egg(parent, "LilyFlower", CFrame.new(top), Vector3.new(0.8, 0.5, 0.8), rgb(255, 178, 214))
				ball(parent, "LilyHeart", top + Vector3.new(0, 0.2, 0), 0.3, rgb(255, 226, 110))
			end
		end
	end
	-- roseaux + touffes en plus sur la rive
	for k = 0, 7 do
		local a = 0.3 + k * 0.79 + hash(k, 206) * 0.3
		local x, z = math.sin(a) * (R + 0.4), math.cos(a) * (R + 0.4)
		if not (math.abs(x - bx) < 8 and math.abs(z) > R * 0.6) and not (x > R * 0.45 and math.abs(z - LAKE.DockZ * R) < 8) then
			local base = L * CFrame.new(x, 0, z) * CFrame.Angles(0, a, 0)
			egg(parent, "Reeds", base * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-8)), Vector3.new(1, 3.2 + hash(k, 207), 0.8), rgb(110, 164, 86), M.Grass)
			egg(parent, "Reeds", base * CFrame.new(0.8, 1.1, 0.4) * CFrame.Angles(0, 0, math.rad(10)), Vector3.new(0.9, 2.6, 0.7), rgb(128, 176, 92), M.Grass)
			egg(parent, "Tuft", base * CFrame.new(-0.4, 0.4, 1.8), Vector3.new(1.6, 0.9, 1.2), rgb(104, 170, 84), M.Grass)
		end
	end
	-- canards et cygnes : chacun tourne doucement autour de son point
	local birds = {}
	local spots = 0
	for k = 1, 40 do
		if spots >= 6 then
			break
		end
		local a = hash(k, 210) * math.pi * 2
		local r = R * (0.25 + hash(k, 211) * 0.5)
		local x, z = math.sin(a) * r, math.cos(a) * r
		local orbit = 2.5 + hash(k, 212) * 3
		if freeWater(x, z, orbit + 1.5) then
			spots += 1
			local m = spots <= 2 and swan(parent) or duck(parent, spots % 3)
			-- décalages figés par rapport au corps : chaque image repart de ces valeurs exactes
			-- (PivotTo répété accumule des erreurs d'arrondi → dérive puis NaN)
			local offsets = {}
			local rootCF = (m.PrimaryPart :: BasePart).CFrame
			for _, part in ipairs(m:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(offsets, { Part = part, Off = rootCF:ToObjectSpace(part.CFrame) })
				end
			end
			table.insert(birds, {
				Model = m,
				Offsets = offsets,
				Center = Vector3.new(x, 0, z),
				Orbit = orbit,
				Speed = (0.08 + hash(k, 213) * 0.06) * (hash(k, 214) < 0.5 and -1 or 1),
				Phase = hash(k, 215) * math.pi * 2,
				Y = LAKE.WaterTop - 0.15,
			})
		end
	end
	d.Birds = birds
end

-- (v9.9, PARK99) toute l'aire de jeux réaliste QUI MARCHE : ParkPlay
-- (décor, balançoires / tape-cul / tourniquet / jeux à ressort animés,
-- toboggan, barres de singe, bac à sable). Sans ParkPlay : les jouets du
-- bac à sable d'avant (v9.7).
local okPark, ParkPlay = pcall(require, script.Parent:FindFirstChild("ParkPlay") :: any)

local function buildPlayground(d: Detail, parent: Model)
	if okPark and type(ParkPlay) == "table" and type(ParkPlay.Build) == "function" then
		local ok, err = pcall(ParkPlay.Build, d.CF, parent, d.Model)
		if ok then
			return
		end
		warn("[TownGreenery] ParkPlay : " .. tostring(err))
	end
	local g = d.CF
	-- bac à sable (centré en (-8, -7.5), sable dessus à 0,55)
	local box = g * CFrame.new(-8, 0.55, -7.5)
	local bucket = box * CFrame.new(1.4, 0, 1)
	local b = newPart(parent, "Bucket", Vector3.new(0.9, 0.9, 0.9), bucket * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(236, 72, 90))
	b.Shape = Enum.PartType.Cylinder
	rod(parent, "BucketHandle", (bucket * CFrame.new(-0.42, 0.95, 0)).Position, (bucket * CFrame.new(0.42, 0.95, 0)).Position, 0.08, rgb(60, 60, 70))
	rod(parent, "Spade", (box * CFrame.new(-1.2, 0.05, 1.6)).Position, (box * CFrame.new(-0.2, 0.9, 1.1)).Position, 0.14, rgb(80, 150, 230))
	newPart(parent, "SpadeBlade", Vector3.new(0.5, 0.06, 0.6), box * CFrame.new(-1.45, 0.06, 1.75), rgb(80, 150, 230))
	local castle = box * CFrame.new(-1, 0, -1.2)
	local keep = newPart(parent, "Castle", Vector3.new(1.3, 1.6, 1.6), castle * CFrame.new(0, 0.65, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(236, 214, 170), M.Sand)
	keep.Shape = Enum.PartType.Cylinder
	for k = 0, 3 do
		local a = k * math.pi / 2
		local t = newPart(parent, "Turret", Vector3.new(0.9, 0.5, 0.5), castle * CFrame.new(math.cos(a) * 0.95, 0.45, math.sin(a) * 0.95) * CFrame.Angles(0, 0, math.pi / 2), rgb(230, 206, 160), M.Sand)
		t.Shape = Enum.PartType.Cylinder
	end
	ball(parent, "Ball", (g * CFrame.new(4, 0.95, -2)).Position, 1.4, rgb(255, 120, 150))
end

----------------------------------------------------------------------
-- (v11, PARK11) LIEUX DU PARC : terrains où les PNJ jouent (ParkSports),
-- scènes vivantes (ParkScenes : roseraie, kiosque, place de la fontaine,
-- parc à chiens, pique-niques, agrès, bancs occupés). Rayon de flux plus
-- court que le lac (PNJ : ~100 pièces chacun).
----------------------------------------------------------------------

local okSports, ParkSports = pcall(require, script.Parent:FindFirstChild("ParkSports") :: any)
local okScenes, ParkScenes = pcall(require, script.Parent:FindFirstChild("ParkScenes") :: any)
local SCENE_IN, SCENE_OUT = 175, 215
local SPORTS = { Basketball = true, Football = true, Tennis = true, PingPong = true }

local function isScene(kind: string): boolean
	if SPORTS[kind] then
		return true
	end
	return okScenes and type(ParkScenes) == "table" and ParkScenes.BUILDERS[kind] ~= nil
end

local function buildScene(d: Detail, parent: Model)
	local seed = d.Seed or 1
	if SPORTS[d.Kind] then
		if not okSports or type(ParkSports) ~= "table" then
			return
		end
		if d.Kind == "PingPong" then
			-- (deux tables côte à côte)
			ParkSports.PingPong(parent, d.CF * CFrame.new(-8, 0, 0), seed)
			ParkSports.PingPong(parent, d.CF * CFrame.new(8, 0, 0), seed + 1)
		else
			ParkSports[d.Kind](parent, d.CF, seed)
		end
	elseif okScenes and type(ParkScenes) == "table" and ParkScenes.BUILDERS[d.Kind] then
		ParkScenes.BUILDERS[d.Kind](parent, d.CF, seed)
	end
end

----------------------------------------------------------------------
-- Flux
----------------------------------------------------------------------

local function discover()
	table.clear(trees)
	table.clear(details)
	local town = workspace:FindFirstChild("DopamineTown")
	if not town then
		return
	end
	for _, d in ipairs(town:GetDescendants()) do
		if d:IsA("Model") then
			local base = d:GetAttribute("TreeBase")
			if typeof(base) == "Vector3" and type(d:GetAttribute("TreeSpecies")) == "string" then
				table.insert(trees, { Model = d, Base = base })
			else
				local kind = d:GetAttribute("NearDetail")
				local cf = d:GetAttribute("DetailCF")
				if type(kind) == "string" and typeof(cf) == "CFrame" then
					table.insert(details, { Model = d, Kind = kind, CF = cf, R = tonumber(d:GetAttribute("DetailR")) or 20, Seed = tonumber(d:GetAttribute("DetailSeed")) })
				end
			end
		end
	end
end

local function buildTree(t: Tree)
	local m = t.Model
	local tier = tonumber(m:GetAttribute("TreeTier")) or 0
	if tier >= Greenery.NEAR_TIER or not folder then
		return
	end
	local near = Greenery.Tree(folder, t.Base, tonumber(m:GetAttribute("TreeHeight")) or 12, tonumber(m:GetAttribute("TreeSeed")) or 1, m:GetAttribute("TreeSpecies") :: any, Greenery.NEAR_TIER, tier + 1, {
		Lawn = m:GetAttribute("TreeLawn") == true,
		Name = "TreeNear",
	})
	-- (tout en décor côté client)
	for _, p in ipairs(near:GetChildren()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CastShadow = false
		end
	end
	t.Near = near
end

local function buildDetail(d: Detail)
	if not folder then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Near" .. d.Kind
	if d.Kind == "Lake" then
		buildLake(d, m)
	elseif d.Kind == "Playground" then
		buildPlayground(d, m)
	elseif isScene(d.Kind) then
		local ok, err = pcall(buildScene, d, m)
		if not ok then
			warn("[TownGreenery] " .. d.Kind .. " : " .. tostring(err))
		end
	end
	m.Parent = folder
	d.Near = m
end

local function moveBirds(dt: number)
	for _, d in ipairs(details) do
		if d.Near and d.Birds then
			for _, b in ipairs(d.Birds) do
				b.Phase += b.Speed * dt * 2
				local x = b.Center.X + math.cos(b.Phase) * b.Orbit
				local z = b.Center.Z + math.sin(b.Phase) * b.Orbit
				-- (le bec regarde dans le sens de la marche : tangente au cercle)
				local tx, tz = -math.sin(b.Phase) * b.Speed, math.cos(b.Phase) * b.Speed
				local pos = d.CF * Vector3.new(x, b.Y + math.sin(b.Phase * 7) * 0.04, z)
				local ahead = d.CF * Vector3.new(x + tx, b.Y, z + tz)
				if b.Model.Parent and (ahead - pos).Magnitude > 1e-4 then
					local cf = CFrame.lookAt(pos, Vector3.new(ahead.X, pos.Y, ahead.Z))
					for _, o in ipairs(b.Offsets) do
						o.Part.CFrame = cf * o.Off
					end
				end
			end
		end
	end
end

local function heartbeat(dt: number)
	birdClock += dt
	if birdClock >= 1 / BIRD_HZ then
		moveBirds(birdClock)
		birdClock = 0
	end
end

function TownGreenery.Step(position: Vector3?)
	if not started or typeof(position) ~= "Vector3" then
		return
	end
	local pos = position :: Vector3
	clock += 1
	if #trees == 0 and #details == 0 then
		rescan += 1
		if rescan % 8 == 1 then
			discover()
		end
	end
	local k = detailScale()
	local function dist(p: Vector3): number
		return Vector3.new(p.X - pos.X, 0, p.Z - pos.Z).Magnitude
	end
	-- détruire au-delà de la marge, repérer les plus proches à construire
	local want = {}
	for _, t in ipairs(trees) do
		if not t.Model.Parent then
			if t.Near then
				t.Near:Destroy()
				t.Near = nil
			end
		else
			local dd = dist(t.Base)
			if t.Near and dd > TREE_OUT * k then
				t.Near:Destroy()
				t.Near = nil
			elseif not t.Near and dd < TREE_IN * k then
				table.insert(want, { t, dd })
			end
		end
	end
	local built = 0
	for _, d in ipairs(details) do
		local dd = dist(d.CF.Position)
		local scene = isScene(d.Kind)
		local dIn, dOut = scene and SCENE_IN or DETAIL_IN, scene and SCENE_OUT or DETAIL_OUT
		if d.Near and dd > dOut * k then
			d.Near:Destroy()
			d.Near = nil
			d.Birds = nil
		elseif not d.Near and dd < dIn * k and d.Model.Parent and built < 2 then
			-- (2 lieux au plus par pas : pas d'à-coup en arrivant au parc)
			built += 1
			buildDetail(d)
		end
	end
	table.sort(want, function(a, b)
		return a[2] < b[2]
	end)
	for i = 1, math.min(#want, BUILDS_PER_STEP) do
		buildTree(want[i][1])
	end
end

function TownGreenery.Start()
	if started then
		return
	end
	started = true
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	folder = f
	rescan = 0
	discover()
	table.insert(conns, RunService.Heartbeat:Connect(heartbeat))
end

function TownGreenery.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	for _, t in ipairs(trees) do
		t.Near = nil
	end
	for _, d in ipairs(details) do
		d.Near = nil
		d.Birds = nil
	end
	table.clear(trees)
	table.clear(details)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function TownGreenery.Debug()
	local builtTrees, parts = 0, 0
	for _, t in ipairs(trees) do
		if t.Near then
			builtTrees += 1
		end
	end
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
	end
	local birds = 0
	for _, d in ipairs(details) do
		birds += d.Birds and #d.Birds or 0
	end
	return { Trees = #trees, NearTrees = builtTrees, Details = #details, Parts = parts, Birds = birds, Steps = clock }
end

return TownGreenery
