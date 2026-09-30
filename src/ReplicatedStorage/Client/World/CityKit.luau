--[[
	CityKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > CityKit

	🏙️ Dopamine Town (v10, CITY10) : la BOÎTE À OUTILS des kits de la grande
	ville (quartiers, autoroute, parcs), construits côté CLIENT, en flux
	(TownStreetLife). Rien ici n'est placé dans le monde : ce sont des
	fabriques de pièces et un petit moteur d'animation partagé.
	  - fabriques : Part / Wedge / Box / Column / Rod / Egg / Glow / Text ;
	  - hasard déterministe : Hash(a, b) (même formule que TownKit.Hash) ;
	  - personnages : Npc(m, style, seed, cf, prop, solid) (NPCModels) ;
	  - ACTEURS : Actor(model, fn, phase) -> animés à chaque image, et
	    seulement près de la caméra (< ANIM_R), sans création d'instance ;
	    retirés tout seuls quand leur modèle est détruit (flux) ;
	  - compteur de pièces créées (Debug / budget).
	Règles de toutes les pièces : ancrées, CanQuery / CanTouch false, sans
	collision sauf `solid` (l'avatar local s'y cogne : murs, bancs, piliers),
	ombre seulement pour les pièces solides ou assez grandes. Aucune lumière
	(les verres "NightGlow" passent en Neon la nuit via TownAtmosphere),
	aucun son.

	API : voir les fonctions CityKit.* ci-dessous.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local okNpc, NPCModels = pcall(require, ReplicatedStorage.Shared.NPCModels)

local CityKit = {}

local M = Enum.Material
CityKit.M = M
CityKit.rgb = Color3.fromRGB
CityKit.UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)
CityKit.ANIM_R = 150 -- (studs) acteurs animés près de la caméra seulement

local created = 0

-- Hasard déterministe 0..1 (même formule que TownKit.Hash / Greenery.Hash)
function CityKit.Hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Choix déterministe dans une liste
function CityKit.Pick<T>(list: { T }, seed: number, salt: number?): T
	return list[1 + math.floor(CityKit.Hash(seed, salt or 3) * #list) % #list]
end

local function finish(p: BasePart, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?, parent: Instance)
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = solid == true or size.Magnitude > 4
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	created += 1
end

-- Pièce ; shape : nil (bloc) | "Ball" | "Cyl" (axe X) | "Egg" (ellipsoïde)
function CityKit.Part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?, solid: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	finish(p, size, cf, color, material, solid, parent)
	return p
end

function CityKit.Wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	finish(p, size, cf, color, material, solid, parent)
	return p
end

function CityKit.Corner(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("CornerWedgePart")
	p.Name = name
	finish(p, size, cf, color, material, false, parent)
	return p
end

-- Boîte par ses bornes dans le repère F
function CityKit.Box(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return CityKit.Part(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, nil, solid)
end

-- Cylindre debout (x, z) de y0 à y1, diamètre d, dans le repère F
function CityKit.Column(parent: Instance, name: string, F: CFrame, x: number, z: number, y0: number, y1: number, d: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return CityKit.Part(parent, name, Vector3.new(y1 - y0, d, d), F * CFrame.new(x, (y0 + y1) / 2, z) * CityKit.UPRIGHT, color, material, "Cyl", solid)
end

-- Cylindre de a à b (monde), diamètre d
function CityKit.Rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local axis = b - a
	local up = math.abs(axis.Unit.Y) > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	return CityKit.Part(parent, name, Vector3.new(axis.Magnitude, d, d), CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0), color, material, "Cyl", solid)
end

-- Poutre (bloc) de a à b (monde), section w x h (h selon `up`)
function CityKit.Beam(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	local axis = b - a
	local up = math.abs(axis.Unit.Y) > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	return CityKit.Part(parent, name, Vector3.new(w, h, axis.Magnitude), CFrame.lookAt((a + b) / 2, b, up), color, material, nil, solid)
end

function CityKit.Egg(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	return CityKit.Part(parent, name, size, cf, color, material, "Egg")
end

function CityKit.Ball(parent: Instance, name: string, pos: Vector3, d: number, color: Color3, material: Enum.Material?): BasePart
	return CityKit.Part(parent, name, Vector3.new(d, d, d), CFrame.new(pos), color, material, "Ball")
end

-- Verre de lanterne / fenêtre qui s'allume la nuit (TownAtmosphere)
function CityKit.Glow(p: BasePart): BasePart
	p:SetAttribute("NightGlow", true)
	return p
end

-- Texte sur une face (enseignes, panneaux) ; bg = fond plein
function CityKit.Text(host: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, maxDistance: number?, pps: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps or 30
	gui.LightInfluence = 0.7
	gui.MaxDistance = maxDistance or 120
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = bg and 0 or 1
	label.BackgroundColor3 = bg or Color3.new(1, 1, 1)
	label.BorderSizePixel = 0
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBold
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	return label
end

-- Toile SurfaceGui vide (fresques, cartes) ; renvoie le SurfaceGui
function CityKit.Canvas(host: BasePart, face: Enum.NormalId, maxDistance: number?, pps: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Canvas"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps or 12
	gui.LightInfluence = 0.8
	gui.MaxDistance = maxDistance or 160
	gui.ClipsDescendants = true
	gui.Parent = host
	return gui
end

-- Cadre coloré dans une toile (fractions 0..1)
function CityKit.Blob(gui: Instance, x: number, y: number, w: number, h: number, color: Color3, round: number?, rot: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Rotation = rot or 0
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = gui
	return f
end

----------------------------------------------------------------------
-- Personnages (NPCModels) et acteurs animés
----------------------------------------------------------------------

-- Personnage posé (pivot = entre les pieds, regard -Z) ; `solid` : capsule
-- de collision locale (NPCModels) ; nil si NPCModels est absent
function CityKit.Npc(m: Instance, style: string, seed: number, cf: CFrame, prop: string?, solid: boolean?): Model?
	if not okNpc or type(NPCModels) ~= "table" then
		return nil
	end
	local ok, model = pcall(function()
		return NPCModels.Build(style, { Seed = seed, Prop = prop or "none", Solid = solid == true })
	end)
	if not ok or not model then
		return nil
	end
	model.Parent = m
	model:PivotTo(cf)
	return model
end

-- Pose d'un personnage (sans erreur si NPCModels manque)
function CityKit.Animate(model: Model, anim: string, t: number)
	if okNpc and type(NPCModels) == "table" then
		NPCModels.Animate(model, anim, t)
	end
end

type Actor = { Model: Instance, Fn: (t: number, dt: number) -> (), Phase: number, Pos: Vector3 }
local actors: { Actor } = {}

-- Acteur : fn(t, dt) appelée à chaque image quand la caméra est proche ;
-- `model` sert à savoir s'il existe encore (détruit par le flux -> retiré)
function CityKit.Actor(model: Instance?, pos: Vector3, fn: (t: number, dt: number) -> (), phase: number?)
	if model then
		table.insert(actors, { Model = model, Fn = fn, Phase = phase or 0, Pos = pos })
	end
end

-- Personnage animé sur place ("idle", "talk", "wave", "sit", "type"...)
function CityKit.Idle(model: Model?, anim: string, phase: number)
	if model then
		CityKit.Actor(model, model:GetPivot().Position, function(t: number)
			CityKit.Animate(model, anim, t)
		end, phase)
	end
end

-- Budget : au plus MAX_PER_FRAME acteurs par image ; au-delà de HALF_R
-- studs, une image sur deux (le mouvement reste fluide de loin)
local MAX_PER_FRAME = 48
local HALF_R = 70
local frame = 0

function CityKit.Step(dt: number)
	if #actors == 0 then
		return
	end
	frame += 1
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local now = os.clock()
	local done = 0
	for i = #actors, 1, -1 do
		local a = actors[i]
		if not a.Model.Parent then
			table.remove(actors, i)
		else
			local dist = eye and (a.Pos - eye).Magnitude or 0
			if dist < CityKit.ANIM_R and done < MAX_PER_FRAME and (dist < HALF_R or (frame + i) % 2 == 0) then
				done += 1
				local ok = pcall(a.Fn, now + a.Phase, dt * (dist < HALF_R and 1 or 2))
				if not ok then
					table.remove(actors, i)
				end
			end
		end
	end
end

function CityKit.ActorCount(): number
	return #actors
end

function CityKit.Created(): number
	return created
end

----------------------------------------------------------------------
-- Petits éléments communs
----------------------------------------------------------------------

local IRON = Color3.fromRGB(46, 48, 56)
local LAMP = Color3.fromRGB(255, 230, 176)

-- Lampadaire de rue (crosse simple, verre qui s'allume la nuit) ; h = hauteur
function CityKit.StreetLamp(m: Instance, F: CFrame, h: number?, color: Color3?)
	local H = h or 12
	local c = color or IRON
	CityKit.Column(m, "LampFoot", F, 0, 0, -0.05, 0.9, 0.9, c, M.Metal, true)
	CityKit.Column(m, "LampPole", F, 0, 0, 0.85, H + 0.2, 0.34, c, M.Metal, true)
	CityKit.Box(m, "LampArm", F, -0.08, 0.08, H, H + 0.18, -2.2, 0, c, M.Metal)
	CityKit.Box(m, "LampHood", F, -0.62, 0.62, H - 0.1, H + 0.22, -2.9, -1.5, c, M.Metal)
	CityKit.Glow(CityKit.Box(m, "LampGlass", F, -0.42, 0.42, H - 0.45, H - 0.1, -2.7, -1.7, LAMP, M.SmoothPlastic))
end

-- Lanterne de style (village, manoir) : fût, lanterne carrée vitrée
function CityKit.Lantern(m: Instance, F: CFrame, h: number?, color: Color3?)
	local H = h or 9
	local c = color or IRON
	CityKit.Column(m, "LanternFoot", F, 0, 0, -0.05, 1.0, 1.0, c, M.Metal, true)
	CityKit.Column(m, "LanternPole", F, 0, 0, 0.9, H - 1.4, 0.3, c, M.Metal, true)
	CityKit.Column(m, "LanternCollar", F, 0, 0, H - 1.5, H - 1.25, 0.7, c, M.Metal)
	CityKit.Glow(CityKit.Box(m, "LanternGlass", F, -0.42, 0.42, H - 1.25, H - 0.1, -0.42, 0.42, LAMP, M.Glass))
	CityKit.Wedge(m, "LanternCap", Vector3.new(1.1, 0.5, 0.55), F * CFrame.new(0, H + 0.15, 0.275), c, M.Metal)
	CityKit.Wedge(m, "LanternCap", Vector3.new(1.1, 0.5, 0.55), F * CFrame.new(0, H + 0.15, -0.275) * CFrame.Angles(0, math.pi, 0), c, M.Metal)
	CityKit.Ball(m, "LanternFinial", (F * CFrame.new(0, H + 0.5, 0)).Position, 0.24, c, M.Metal)
end

-- Banc de parc (lattes bois, pieds fonte) ; siège à 1,4 (échelle avatar)
function CityKit.Bench(m: Instance, F: CFrame, len: number?)
	local L = len or 5
	local wood = Color3.fromRGB(150, 104, 66)
	for _, x in ipairs({ -L / 2 + 0.4, L / 2 - 0.4 }) do
		CityKit.Box(m, "BenchLeg", F, x - 0.12, x + 0.12, 0, 1.3, -0.7, 0.7, IRON, M.Metal, true)
		CityKit.Box(m, "BenchArm", F, x - 0.12, x + 0.12, 2.0, 2.12, -0.75, 0.55, IRON, M.Metal)
	end
	for i = 0, 2 do
		CityKit.Box(m, "BenchSlat", F, -L / 2, L / 2, 1.3, 1.44, -0.62 + i * 0.44, -0.3 + i * 0.44, wood, M.Wood, i == 1)
	end
	for i = 0, 1 do
		CityKit.Box(m, "BenchBack", F, -L / 2, L / 2, 1.8 + i * 0.5, 2.1 + i * 0.5, 0.62 + i * 0.1, 0.76 + i * 0.1, wood, M.Wood)
	end
end

-- Poubelle municipale
function CityKit.Bin(m: Instance, F: CFrame, color: Color3?)
	local c = color or Color3.fromRGB(38, 78, 62)
	CityKit.Column(m, "BinBody", F, 0, 0, 0, 2.6, 1.5, c, M.Metal, true)
	CityKit.Column(m, "BinRim", F, 0, 0, 2.6, 2.8, 1.62, Color3.fromRGB(52, 54, 60), M.Metal)
end

-- Rangée de haie basse (le long de x, de -len/2 à len/2), buis bosselé
function CityKit.Hedge(m: Instance, F: CFrame, len: number, h: number?, d: number?, seed: number?)
	local H, D = h or 3, d or 2.2
	local green = Color3.fromRGB(62, 118, 58)
	CityKit.Box(m, "Hedge", F, -len / 2, len / 2, 0, H, -D / 2, D / 2, green, M.Grass, true)
	local n = math.max(1, math.floor(len / 3.2))
	for i = 0, n - 1 do
		local x = -len / 2 + (i + 0.5) * len / n
		local k = CityKit.Hash(seed or 1, i)
		CityKit.Egg(m, "HedgeBump", F * CFrame.new(x, H - 0.05, 0), Vector3.new(len / n + 0.4, 0.9 + k * 0.4, D + 0.1), green:Lerp(Color3.fromRGB(88, 146, 70), k * 0.6), M.Grass)
	end
end

return CityKit
