--[[
	Reflections (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > Reflections

	v9.8 (REALISM98) 🪞 VRAIS miroirs (reflet plan) + reflets discrets.

	1) Miroirs. Contrat (RECIPES98 / CATALOG98) : dans le modèle d'un objet
	   miroir, une BasePart (bloc mince) nommée "Mirror", attributs
	   Mirror = true, MirrorFace = "Front" (face qui réfléchit ; sa normale
	   = LookVector, vers la pièce), MirrorShape = "Rect" | "Oval". Sa taille
	   X / Y = la surface qui réfléchit. Sans reflets : son verre statique
	   (Reflectance) reste visible = le repli.
	   Reflet "vivant" : une SurfaceGui sur la face du miroir, avec une
	   ViewportFrame qui filme un MONDE RÉFLÉCHI :
	     (SurfaceGui dans le PlayerGui, Adornee = "Mirror" : rien dans le Workspace)
	     - le décor proche (pièces de la pièce / maison, devant le plan du
	       miroir, ≤ 36 studs, ≤ 650 pièces) cloné UNE fois et réfléchi par
	       rapport au plan (mis en cache, reconstruit si la pièce change) ;
	     - une copie légère du personnage local (Humanoid + vêtements, sans
	       scripts ni joints) dont les CFrame sont recopiées réfléchies à
	       chaque image (30 images / s au plus).
	   Mathématiques (vérifiées numériquement, voir le rapport REALISM98) :
	     plan : centre M, normale n, axes de la toile u (vers la droite vue
	     de face) et v (haut), u x v = n ;
	     réflexion d'un point : p' = p - 2 ((p - M) . n) n ;
	     réflexion d'un CFrame : position réfléchie, axes (-H X, H Y, H Z)
	     avec H = I - 2 n nᵀ (on retourne l'axe X local : rotation propre,
	     les blocs / boules / cylindres / pentes sont symétriques en X) ;
	     caméra de la ViewportFrame = position de la VRAIE caméra, qui
	     regarde -n (perpendiculaire au miroir : son plan image est
	     parallèle au miroir, donc la projection sur la face est affine) ;
	     la ViewportFrame est centrée sur le pied de la perpendiculaire
	     (cx, cy) = ((C - M) . u, (C - M) . v), de demi-taille
	     (|cx| + w/2, |cy| + h/2) dans le plan, et
	     FieldOfView = 2 atan(demi-hauteur / D), D = (C - M) . n ;
	     un cadre "Clip" (ClipsDescendants) la découpe à la taille du miroir.
	     Limites : FieldOfView ≤ 110° (très près : seule la partie autour du
	     pied est couverte, c'est aussi la seule visible), toile ≤ 2048 px
	     (densité réduite quand on regarde de très biais), en dessous de
	     6 px / stud le miroir repasse en verre statique.
	   Coût : 1 miroir vivant à la fois (2 en "Tout" + Détail élevé), le
	   plus grand à l'écran ; en pause s'il est caché, derrière un mur, de
	   dos ou à plus de 45 studs.
	2) Reflets "Tout" (Graphismes > Reflets = Tout) :
	   - écrans ("Screen" de House3DSetup / attribut Glossy) : voile de
	     verre discret (dégradé en diagonale qui glisse avec l'angle de vue),
	     10 écrans proches au plus ;
	   - sols des pièces ("Floor" des RoomShell) : Reflectance légère
	     (bois 0,05, marbre / carrelage 0,1), remise à l'arrêt.

	API :
	  Reflections.Acquire(owner) / Reflections.Release(owner)   ("Town", "House3D"...)
	  Reflections.IsActive() -> boolean
	  Reflections.Live() -> { { Part, Gui, Viewport, World, Camera, View } }  (tests)
	  Fonctions pures (tests) :
	  Reflections.ReflectPoint(p, M, n) -> Vector3
	  Reflections.ReflectCFrame(cf, M, n) -> CFrame
	  Reflections.PlaneOf(part) -> Plane?
	  Reflections.ComputeView(cameraPosition, plane, pps) -> View?
	  Reflections.ProjectToCanvas(view, plane, worldPoint) -> Vector2?  (pixel de la toile)
	Aucun son. Rien n'est créé quand les reflets sont coupés.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GraphicsQuality = require(ReplicatedStorage.Shared.GraphicsQuality)

local Reflections = {}

local MAX_FOV = 110
local MAX_CANVAS = 2048
local BASE_PPS = 56
local MIN_PPS = 6
local STATIC_RADIUS = 36
local STATIC_MAX = 650
local LIVE_RANGE = 45
local FRAME_RATE = 1 / 30
local SELECT_EVERY = 0.25
local GLOSS_EVERY = 0.1
local GLOSS_RANGE = 40
local GLOSS_MAX = 10
local RENDER_NAME = "DopamineMirrors"
local GLASS_TINT = Color3.fromRGB(176, 192, 206)
local FACES: { [string]: Enum.NormalId } = {
	Front = Enum.NormalId.Front,
	Back = Enum.NormalId.Back,
	Left = Enum.NormalId.Left,
	Right = Enum.NormalId.Right,
}

----------------------------------------------------------------------
-- Mathématiques (pures)
----------------------------------------------------------------------

export type Plane = {
	Center: Vector3, -- centre de la face qui réfléchit
	U: Vector3, -- axe X de la toile (vers la droite, vu de face)
	V: Vector3, -- axe Y de la toile (vers le haut)
	N: Vector3, -- normale (vers la pièce)
	HalfW: number,
	HalfH: number,
}

export type View = {
	CameraCF: CFrame,
	FieldOfView: number,
	FramePos: Vector2, -- coin haut-gauche de la ViewportFrame (pixels de la toile)
	FrameSize: Vector2, -- taille de la ViewportFrame (pixels)
	PPS: number, -- pixels par stud de la toile
	D: number, -- distance caméra -> plan
	Foot: Vector2, -- pied de la perpendiculaire (studs, repère du miroir)
}

function Reflections.ReflectPoint(p: Vector3, center: Vector3, n: Vector3): Vector3
	return p - n * (2 * (p - center):Dot(n))
end

local function reflectVector(v: Vector3, n: Vector3): Vector3
	return v - n * (2 * v:Dot(n))
end

-- Réflexion d'un CFrame par un plan : rotation PROPRE (axe X local retourné)
function Reflections.ReflectCFrame(cf: CFrame, center: Vector3, n: Vector3): CFrame
	local p = Reflections.ReflectPoint(cf.Position, center, n)
	local x = -reflectVector(cf.RightVector, n)
	local y = reflectVector(cf.UpVector, n)
	local z = reflectVector(-cf.LookVector, n)
	return CFrame.fromMatrix(p, x, y, z)
end

-- Face qui réfléchit d'une pièce "Mirror" (Front par défaut)
function Reflections.PlaneOf(part: BasePart): Plane?
	local face = part:GetAttribute("MirrorFace")
	local cf, size = part.CFrame, part.Size
	local up = cf.UpVector
	local n: Vector3, w: number, offset: number
	if face == nil or face == "Front" then
		n, w, offset = cf.LookVector, size.X, size.Z / 2
	elseif face == "Back" then
		n, w, offset = -cf.LookVector, size.X, size.Z / 2
	elseif face == "Left" then
		n, w, offset = -cf.RightVector, size.Z, size.X / 2
	elseif face == "Right" then
		n, w, offset = cf.RightVector, size.Z, size.X / 2
	else
		return nil
	end
	-- axe X de la toile d'une SurfaceGui sur une face de côté : haut x normale
	local u = up:Cross(n)
	return {
		Center = cf.Position + n * offset,
		U = u,
		V = up,
		N = n,
		HalfW = w / 2,
		HalfH = size.Y / 2,
	}
end

-- Caméra + cadre de la ViewportFrame pour une caméra à `camPos`
function Reflections.ComputeView(camPos: Vector3, plane: Plane, pps: number?): View?
	local rel = camPos - plane.Center
	local d = rel:Dot(plane.N)
	if d < 0.05 then
		return nil -- derrière le miroir (ou collé dessus)
	end
	local cx, cy = rel:Dot(plane.U), rel:Dot(plane.V)
	local hx = math.abs(cx) + plane.HalfW
	local hy = math.abs(cy) + plane.HalfH
	-- champ vertical limité : très près, on ne couvre que l'entour du pied
	local maxHalf = d * math.tan(math.rad(MAX_FOV / 2))
	hy = math.min(hy, maxHalf)
	hx = math.min(hx, maxHalf * 8, hy * 8)
	hy = math.max(hy, hx / 8)
	local density = math.min(pps or BASE_PPS, MAX_CANVAS / (2 * hx), MAX_CANVAS / (2 * hy))
	if density < MIN_PPS then
		return nil -- trop de biais : verre statique
	end
	local fov = math.deg(2 * math.atan(hy / d))
	return {
		CameraCF = CFrame.fromMatrix(camPos, plane.U, plane.V, plane.N),
		FieldOfView = fov,
		FramePos = Vector2.new((cx - hx + plane.HalfW) * density, (plane.HalfH - (cy + hy)) * density),
		FrameSize = Vector2.new(2 * hx * density, 2 * hy * density),
		PPS = density,
		D = d,
		Foot = Vector2.new(cx, cy),
	}
end

-- Où un point du MONDE RÉFLÉCHI (ex. une copie réfléchie) apparaît sur la
-- toile du miroir, d'après la projection de la caméra de la ViewportFrame
-- (même formule que Roblox : champ vertical, rapport largeur / hauteur du cadre)
function Reflections.ProjectToCanvas(view: View, _plane: Plane, worldPoint: Vector3): Vector2?
	local rel = view.CameraCF:PointToObjectSpace(worldPoint)
	local depth = -rel.Z
	if depth <= 1e-6 then
		return nil
	end
	local t = math.tan(math.rad(view.FieldOfView) / 2)
	local aspect = view.FrameSize.X / view.FrameSize.Y
	local ndcX = rel.X / (depth * t * aspect)
	local ndcY = rel.Y / (depth * t)
	return Vector2.new(view.FramePos.X + (ndcX + 1) / 2 * view.FrameSize.X, view.FramePos.Y + (1 - ndcY) / 2 * view.FrameSize.Y)
end

----------------------------------------------------------------------
-- Registre (miroirs, écrans, sols) : DescendantAdded filtré par nom
----------------------------------------------------------------------

type Live = {
	Part: BasePart,
	Plane: Plane,
	Gui: SurfaceGui,
	Clip: GuiObject,
	Viewport: ViewportFrame,
	World: WorldModel,
	Camera: Camera,
	Static: Model,
	StaticBuilt: number,
	StaticDirty: boolean,
	StaticCount: number,
	Scope: Instance?,
	ScopeConns: { RBXScriptConnection },
	CharModel: Model?,
	CharSource: Model?,
	CharPairs: { { Src: BasePart, Dst: BasePart } },
	CharCount: number,
	PPS: number,
	View: View?,
	Visible: boolean,
	LastCam: CFrame?,
}

local owners: { [string]: boolean } = {}
local active = false
local mirrors: { [BasePart]: boolean } = {}
local screens: { [BasePart]: boolean } = {}
local floors: { [BasePart]: boolean } = {}
local floorSaved: { [BasePart]: number } = {}
local sheens: { [BasePart]: { Gui: SurfaceGui, Gradient: UIGradient } } = {}
local lives: { [BasePart]: Live } = {}
local addedConn: RBXScriptConnection? = nil
local qualityConn: any = nil
local selectClock = 0
local frameClock = 0
local glossClock = 0
local glossOn = false
local floorsDirty = false

-- Les SurfaceGui (miroirs, voiles) vont dans le PlayerGui avec Adornee = la
-- pièce (comme LiveProps) : les copies réfléchies ne sont JAMAIS dans le
-- Workspace (ni dans le modèle de l'objet : audits, LiveProps, rayons...)
local function guiParent(part: BasePart): Instance
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	return playerGui or part
end

local function consider(d: Instance)
	if not d:IsA("BasePart") then
		return
	end
	local name = d.Name
	if name == "Mirror" then
		if d:GetAttribute("Mirror") == true then
			mirrors[d] = true
		end
	elseif name == "Screen" or d:GetAttribute("Glossy") == true then
		screens[d] = true
	elseif name == "Floor" then
		local parent = d.Parent
		if parent and parent.Name == "RoomShell" then
			floors[d] = true
			floorsDirty = true -- (pièce construite pendant que les reflets sont actifs)
		end
	end
end

local function scanAll()
	for _, d in ipairs(workspace:GetDescendants()) do
		consider(d)
	end
end

----------------------------------------------------------------------
-- Copies réfléchies
----------------------------------------------------------------------

local KEEP_CHILD: { [string]: boolean } = {
	SpecialMesh = true,
	BlockMesh = true,
	CylinderMesh = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
}

-- Copie d'une pièce : seulement ce qui se voit (maillage, décalque, apparence)
local function cloneVisual(part: BasePart): BasePart?
	local ok, copy = pcall(function()
		return part:Clone()
	end)
	if not ok or copy == nil then
		return nil
	end
	local c = copy :: BasePart
	for _, child in ipairs(c:GetChildren()) do
		if not KEEP_CHILD[child.ClassName] then
			child:Destroy()
		end
	end
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	for name in pairs(c:GetAttributes()) do
		c:SetAttribute(name, nil)
	end
	return c
end

-- Racine de la zone à copier : "Interiors" de la maison, sinon l'enfant du Workspace
local function scopeOf(part: BasePart): Instance?
	local node: Instance? = part.Parent
	local top: Instance? = nil
	while node and node ~= workspace do
		if node.Name == "Interiors" then
			return node
		end
		top = node
		node = node.Parent
	end
	return top
end

local function characterOf(inst: Instance): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and inst:IsDescendantOf(character) then
			return true
		end
	end
	return false
end

-- Distance max, devant le plan, de la boîte d'une pièce (> 0 : dépasse devant)
local function frontExtent(part: BasePart, plane: Plane): number
	local cf, size = part.CFrame, part.Size
	local nLocal = cf:VectorToObjectSpace(plane.N)
	local reach = math.abs(nLocal.X) * size.X / 2 + math.abs(nLocal.Y) * size.Y / 2 + math.abs(nLocal.Z) * size.Z / 2
	return (cf.Position - plane.Center):Dot(plane.N) + reach
end

local function buildStatic(live: Live)
	live.Static:ClearAllChildren()
	local scope = live.Scope
	if not scope or scope.Parent == nil then
		live.StaticCount = 0
		return
	end
	local plane = live.Plane
	local candidates: { { Part: BasePart, Dist: number } } = {}
	local r2 = STATIC_RADIUS * STATIC_RADIUS
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("BasePart") and d ~= live.Part and d.Transparency < 0.98 and d:GetAttribute("Mirror") ~= true then
			local offset = d.Position - plane.Center
			-- (grandes pièces : sol, plafond, murs -> distance au bord de la boîte)
			local size = d.Size
			local radius = math.max(size.X, size.Y, size.Z) / 2
			local dist = math.max(0, offset.Magnitude - radius)
			if dist * dist <= r2 and frontExtent(d, plane) > 0.01 and not characterOf(d) then
				table.insert(candidates, { Part = d, Dist = dist })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.Dist < b.Dist
	end)
	local count = 0
	for _, entry in ipairs(candidates) do
		if count >= STATIC_MAX then
			break
		end
		local copy = cloneVisual(entry.Part)
		if copy then
			copy.CFrame = Reflections.ReflectCFrame(entry.Part.CFrame, plane.Center, plane.N)
			copy.Parent = live.Static
			count += 1
		end
	end
	live.StaticCount = count
	live.StaticBuilt = os.clock()
	live.StaticDirty = false
end

local function watchScope(live: Live)
	for _, conn in ipairs(live.ScopeConns) do
		conn:Disconnect()
	end
	table.clear(live.ScopeConns)
	local scope = live.Scope
	if not scope then
		return
	end
	local function touched(d: Instance)
		if d:IsA("BasePart") and d.Parent ~= nil then
			if (d.Position - live.Plane.Center).Magnitude <= STATIC_RADIUS + 20 then
				live.StaticDirty = true
			end
		elseif d:IsA("BasePart") then
			live.StaticDirty = true
		end
	end
	table.insert(live.ScopeConns, scope.DescendantAdded:Connect(touched))
	table.insert(live.ScopeConns, scope.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then
			live.StaticDirty = true
		end
	end))
end

-- Copie légère du personnage local (Humanoid + vêtements, sans scripts / joints)
local function buildCharacter(live: Live)
	if live.CharModel then
		live.CharModel:Destroy()
		live.CharModel = nil
	end
	table.clear(live.CharPairs)
	live.CharSource = nil
	live.CharCount = 0
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if not character then
		return
	end
	local archivable = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = archivable
	if not ok or copy == nil then
		return
	end
	-- paires source / copie : parcours parallèle AVANT de nettoyer
	local function pair(src: Instance, dst: Instance)
		local a, b = src:GetChildren(), dst:GetChildren()
		if #a ~= #b then
			return
		end
		for i = 1, #a do
			if a[i].Name == b[i].Name then
				if a[i]:IsA("BasePart") and b[i]:IsA("BasePart") then
					table.insert(live.CharPairs, { Src = a[i] :: BasePart, Dst = b[i] :: BasePart })
				end
				pair(a[i], b[i])
			end
		end
	end
	pair(character, copy)
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("JointInstance") or d:IsA("Constraint")
			or d:IsA("WeldConstraint") or d:IsA("Animator") or d:IsA("ForceField") or d:IsA("ProximityPrompt")
			or d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			pcall(d.Destroy, d)
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Humanoid") then
			pcall(function()
				d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end)
		end
	end
	copy.Name = "Reflection"
	copy.Parent = live.World
	live.CharModel = copy
	live.CharSource = character
	live.CharCount = #character:GetDescendants()
end

local function updateCharacter(live: Live)
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local near = root and root:IsA("BasePart") and (root.Position - live.Plane.Center).Magnitude < STATIC_RADIUS
		and (root.Position - live.Plane.Center):Dot(live.Plane.N) > -1
	if not near then
		if live.CharModel then
			live.CharModel:Destroy()
			live.CharModel = nil
			table.clear(live.CharPairs)
		end
		return
	end
	if live.CharSource ~= character or live.CharModel == nil or (character and #character:GetDescendants() ~= live.CharCount) then
		buildCharacter(live)
	end
	local plane = live.Plane
	local parts, cframes = {}, {}
	for _, p in ipairs(live.CharPairs) do
		if p.Src.Parent then
			table.insert(parts, p.Dst)
			table.insert(cframes, Reflections.ReflectCFrame(p.Src.CFrame, plane.Center, plane.N))
		end
	end
	if #parts > 0 then
		local ok = pcall(function()
			live.World:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			for i, part in ipairs(parts) do
				part.CFrame = cframes[i]
			end
		end
	end
end

----------------------------------------------------------------------
-- Miroirs vivants
----------------------------------------------------------------------

local function newLive(part: BasePart, plane: Plane): Live
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DopamineMirror"
	gui.Face = FACES[tostring(part:GetAttribute("MirrorFace") or "Front")] or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BASE_PPS
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.MaxDistance = LIVE_RANGE + 15
	gui.ClipsDescendants = true
	gui.ZOffset = 1
	gui.Adornee = part
	local oval = part:GetAttribute("MirrorShape") == "Oval"
	-- (ovale : un CanvasGroup arrondi découpe la ViewportFrame en ellipse ;
	-- un simple Frame + UICorner ne découpe PAS ses enfants dans Roblox)
	local clip: GuiObject
	if oval then
		clip = Instance.new("CanvasGroup")
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = clip
	else
		clip = Instance.new("Frame")
		clip.ClipsDescendants = true
	end
	clip.Name = "Clip"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundColor3 = GLASS_TINT
	clip.BackgroundTransparency = oval and 1 or 0
	clip.BorderSizePixel = 0
	clip.Parent = gui
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Reflection"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.ImageColor3 = Color3.fromRGB(236, 242, 248) -- verre légèrement froid
	viewport.Parent = clip
	local camera = Instance.new("Camera")
	camera.Name = "MirrorCamera"
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local world = Instance.new("WorldModel")
	world.Name = "World"
	world.Parent = viewport
	local static = Instance.new("Model")
	static.Name = "Static"
	static.Parent = world
	-- voile de verre (reflet diagonal très discret)
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BorderSizePixel = 0
	sheen.ZIndex = 3
	sheen.Parent = clip
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 28
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.34, 0.97),
		NumberSequenceKeypoint.new(0.46, 0.9),
		NumberSequenceKeypoint.new(0.56, 0.95),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = sheen
	gui.Parent = guiParent(part)
	local live: Live = {
		Part = part,
		Plane = plane,
		Gui = gui,
		Clip = clip,
		Viewport = viewport,
		World = world,
		Camera = camera,
		Static = static,
		StaticBuilt = 0,
		StaticDirty = true,
		StaticCount = 0,
		Scope = scopeOf(part),
		ScopeConns = {},
		CharModel = nil,
		CharSource = nil,
		CharPairs = {},
		CharCount = 0,
		PPS = BASE_PPS,
		View = nil,
		Visible = true,
		LastCam = nil,
	}
	watchScope(live)
	return live
end

local function dropLive(live: Live)
	for _, conn in ipairs(live.ScopeConns) do
		conn:Disconnect()
	end
	table.clear(live.ScopeConns)
	pcall(live.Gui.Destroy, live.Gui)
	lives[live.Part] = nil
end

-- Éclairage de la ViewportFrame (pas d'ombres ni de lampes : ambiance du lieu)
local function lightViewport(live: Live)
	local ambient = Lighting.Ambient
	local bright = math.clamp(Lighting.Brightness / 2, 0.35, 1.1)
	local base = Color3.new(math.min(1, ambient.R * 1.7 + 0.28), math.min(1, ambient.G * 1.7 + 0.28), math.min(1, ambient.B * 1.7 + 0.3))
	live.Viewport.Ambient = base
	live.Viewport.LightColor = Color3.new(0.62 * bright, 0.6 * bright, 0.57 * bright)
	live.Viewport.LightDirection = Vector3.new(-0.35, -1, -0.45)
end

local function updateLive(live: Live, camCF: CFrame)
	local part = live.Part
	local plane = Reflections.PlaneOf(part)
	if not plane then
		live.Gui.Enabled = false
		return
	end
	-- (le miroir a bougé : copies à refaire)
	if (plane.Center - live.Plane.Center).Magnitude > 0.01 or plane.N:Dot(live.Plane.N) < 0.9999 then
		live.Plane = plane
		live.StaticDirty = true
	end
	if live.StaticDirty and os.clock() - live.StaticBuilt > 0.5 then
		buildStatic(live)
		lightViewport(live)
	end
	local view = Reflections.ComputeView(camCF.Position, live.Plane, BASE_PPS)
	if not view then
		live.Gui.Enabled = false
		live.View = nil
		return
	end
	-- densité de la toile : par paliers (évite de tout remettre en page à chaque image)
	local pps = view.PPS
	if math.abs(pps - live.PPS) / live.PPS > 0.15 then
		live.PPS = pps
		live.Gui.PixelsPerStud = pps
	end
	-- recalcul avec la densité retenue (cadre en pixels de CETTE toile)
	local fitted = Reflections.ComputeView(camCF.Position, live.Plane, live.PPS)
	if fitted and fitted.PPS < live.PPS - 1e-6 then
		live.PPS = fitted.PPS
		live.Gui.PixelsPerStud = fitted.PPS
	end
	view = fitted or view
	live.View = view
	live.Gui.Enabled = true
	live.Viewport.Position = UDim2.fromOffset(view.FramePos.X, view.FramePos.Y)
	live.Viewport.Size = UDim2.fromOffset(view.FrameSize.X, view.FrameSize.Y)
	live.Camera.FieldOfView = view.FieldOfView
	live.Camera.CFrame = view.CameraCF
	updateCharacter(live)
end

-- Le miroir est-il visible (devant, à l'écran, pas derrière un mur) ?
local function visibleScore(part: BasePart, cam: Camera, occlusion: boolean): number
	if part.Parent == nil then
		return -1
	end
	local plane = Reflections.PlaneOf(part)
	if not plane then
		return -1
	end
	local camPos = cam.CFrame.Position
	local rel = camPos - plane.Center
	local dist = rel.Magnitude
	local d = rel:Dot(plane.N)
	if d < 0.1 or dist > LIVE_RANGE then
		return -1
	end
	local onScreen = false
	for _, corner in ipairs({ Vector2.new(0, 0), Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) }) do
		local p = plane.Center + plane.U * (corner.X * plane.HalfW) + plane.V * (corner.Y * plane.HalfH)
		local ok, screen, inView = pcall(function()
			return cam:WorldToViewportPoint(p)
		end)
		if ok and inView and screen.Z > 0 then
			local size = cam.ViewportSize
			if screen.X >= -20 and screen.Y >= -20 and screen.X <= size.X + 20 and screen.Y <= size.Y + 20 then
				onScreen = true
				break
			end
		end
	end
	if not onScreen then
		return -1
	end
	if occlusion then
		local ok, hit = pcall(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local list: { Instance } = {}
			local character = Players.LocalPlayer and Players.LocalPlayer.Character
			if character then
				table.insert(list, character)
			end
			local item = part.Parent
			if item then
				table.insert(list, item)
			end
			local weather = workspace:FindFirstChild("DopamineWeather")
			if weather then
				table.insert(list, weather)
			end
			params.FilterDescendantsInstances = list
			return workspace:Raycast(camPos, (plane.Center - camPos) * 0.97, params)
		end)
		if ok and hit and hit.Instance:IsA("BasePart") and hit.Instance.Transparency < 0.6 then
			return -1
		end
	end
	-- grand à l'écran = prioritaire
	return (plane.HalfW * plane.HalfH) * (d / dist) / (dist * dist + 1)
end

local function selectMirrors(cam: Camera)
	local q = GraphicsQuality.Get()
	local want: { { Part: BasePart, Score: number } } = {}
	if q.MaxMirrors > 0 then
		for part in pairs(mirrors) do
			if part.Parent == nil then
				mirrors[part] = nil
			else
				local score = visibleScore(part, cam, true)
				if score > 0 then
					table.insert(want, { Part = part, Score = score })
				end
			end
		end
		table.sort(want, function(a, b)
			return a.Score > b.Score
		end)
	end
	local keep: { [BasePart]: boolean } = {}
	for i = 1, math.min(q.MaxMirrors, #want) do
		keep[want[i].Part] = true
	end
	for part, live in pairs(lives) do
		if not keep[part] then
			dropLive(live)
		end
	end
	for part in pairs(keep) do
		if not lives[part] then
			local plane = Reflections.PlaneOf(part)
			if plane then
				local live = newLive(part, plane)
				lives[part] = live
				buildStatic(live)
				lightViewport(live)
			end
		end
	end
end

----------------------------------------------------------------------
-- Reflets "Tout" : écrans (voile de verre) + sols des pièces
----------------------------------------------------------------------

local FLOOR_GLOSS: { [Enum.Material]: number } = {
	[Enum.Material.Wood] = 0.05,
	[Enum.Material.WoodPlanks] = 0.05,
	[Enum.Material.Marble] = 0.1,
	[Enum.Material.Granite] = 0.1,
	[Enum.Material.Slate] = 0.08,
	[Enum.Material.SmoothPlastic] = 0.08,
	[Enum.Material.Plastic] = 0.06,
	[Enum.Material.Glass] = 0.1,
	[Enum.Material.Concrete] = 0.04,
}

local function setFloors(on: boolean)
	if on then
		for part in pairs(floors) do
			if part.Parent == nil then
				floors[part] = nil
			else
				local gloss = FLOOR_GLOSS[part.Material]
				if gloss then
					if floorSaved[part] == nil then
						floorSaved[part] = part.Reflectance
					end
					part.Reflectance = math.max(floorSaved[part], gloss)
				end
			end
		end
	else
		for part, reflectance in pairs(floorSaved) do
			if part.Parent then
				part.Reflectance = reflectance
			end
		end
		table.clear(floorSaved)
	end
end

local function removeSheen(part: BasePart)
	local sheen = sheens[part]
	if sheen then
		pcall(sheen.Gui.Destroy, sheen.Gui)
		sheens[part] = nil
	end
end

local function addSheen(part: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DopamineSheen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.ZOffset = 4
	gui.MaxDistance = GLOSS_RANGE + 10
	gui.Adornee = part
	local frame = Instance.new("Frame")
	frame.Name = "Sheen"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 24
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.97),
		NumberSequenceKeypoint.new(0.42, 0.91),
		NumberSequenceKeypoint.new(0.5, 0.94),
		NumberSequenceKeypoint.new(0.62, 0.985),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	gui.Parent = guiParent(part)
	sheens[part] = { Gui = gui, Gradient = gradient }
end

local function stepGloss(cam: Camera)
	local q = GraphicsQuality.Get()
	local on = q.Reflections == "All"
	if on ~= glossOn then
		glossOn = on
		setFloors(on)
		if not on then
			for part in pairs(sheens) do
				removeSheen(part)
			end
		end
	end
	if not on then
		return
	end
	if floorsDirty then
		floorsDirty = false
		setFloors(true)
	end
	local camCF = cam.CFrame
	local camPos = camCF.Position
	local near: { { Part: BasePart, Dist: number } } = {}
	for part in pairs(screens) do
		if part.Parent == nil then
			screens[part] = nil
			removeSheen(part)
		else
			local rel = camPos - part.Position
			local dist = rel.Magnitude
			if dist < GLOSS_RANGE and rel:Dot(part.CFrame.LookVector) > 0 then
				table.insert(near, { Part = part, Dist = dist })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.Dist < b.Dist
	end)
	local keep: { [BasePart]: boolean } = {}
	for i = 1, math.min(GLOSS_MAX, #near) do
		keep[near[i].Part] = true
	end
	for part in pairs(sheens) do
		if not keep[part] then
			removeSheen(part)
		end
	end
	for part in pairs(keep) do
		if not sheens[part] then
			addSheen(part)
		end
		-- le reflet glisse avec l'angle de vue (parallaxe douce)
		local sheen = sheens[part]
		if sheen then
			local toCam = (camPos - part.Position).Unit
			local side = toCam:Dot(part.CFrame.RightVector)
			local vertical = toCam:Dot(part.CFrame.UpVector)
			sheen.Gradient.Offset = Vector2.new(math.clamp(-side * 0.45, -0.45, 0.45), math.clamp(vertical * 0.25, -0.25, 0.25))
		end
	end
end

----------------------------------------------------------------------
-- Boucle (après la caméra : BindToRenderStep, priorité Last + 5)
----------------------------------------------------------------------

local function step(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	selectClock += dt
	if selectClock >= SELECT_EVERY then
		selectClock = 0
		local ok, err = pcall(selectMirrors, cam)
		if not ok then
			warn("[Reflections] " .. tostring(err))
		end
	end
	glossClock += dt
	if glossClock >= GLOSS_EVERY then
		glossClock = 0
		pcall(stepGloss, cam)
	end
	frameClock += dt
	if frameClock < FRAME_RATE then
		return
	end
	frameClock = 0
	local camCF = cam.CFrame
	for _, live in pairs(lives) do
		if live.Part.Parent == nil then
			dropLive(live)
		else
			local ok, err = pcall(updateLive, live, camCF)
			if not ok then
				warn("[Reflections] " .. tostring(err))
				live.Gui.Enabled = false
			end
		end
	end
end

local function start()
	if active then
		return
	end
	active = true
	selectClock, frameClock, glossClock = SELECT_EVERY, FRAME_RATE, GLOSS_EVERY
	scanAll()
	addedConn = workspace.DescendantAdded:Connect(consider)
	qualityConn = GraphicsQuality.Changed:Connect(function()
		selectClock = SELECT_EVERY
		glossClock = GLOSS_EVERY
	end)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value + 5, step)
end

local function stop()
	if not active then
		return
	end
	active = false
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	if addedConn then
		addedConn:Disconnect()
		addedConn = nil
	end
	if qualityConn then
		qualityConn:Disconnect()
		qualityConn = nil
	end
	for _, live in pairs(lives) do
		dropLive(live)
	end
	for part in pairs(sheens) do
		removeSheen(part)
	end
	setFloors(false)
	glossOn = false
	table.clear(mirrors)
	table.clear(screens)
	table.clear(floors)
end

-- Plusieurs "propriétaires" (la ville, la vue 🧊 3D d'une pièce...) : actif
-- tant qu'au moins un le demande
function Reflections.Acquire(owner: string)
	owners[owner] = true
	start()
end

function Reflections.Release(owner: string)
	owners[owner] = nil
	if next(owners) == nil then
		stop()
	end
end

function Reflections.IsActive(): boolean
	return active
end

-- (tests / rendus) miroirs vivants
function Reflections.Live(): { any }
	local list = {}
	for _, live in pairs(lives) do
		table.insert(list, live)
	end
	return list
end

-- (tests / rendus) une passe complète tout de suite (sélection + images)
function Reflections.ForceStep()
	selectClock, frameClock, glossClock = SELECT_EVERY, FRAME_RATE, GLOSS_EVERY
	step(0)
end

-- (tests) compteurs
function Reflections.Counts(): { [string]: number }
	local n = { Mirrors = 0, Screens = 0, Floors = 0, Live = 0, Sheens = 0, FloorsGlossy = 0 }
	for _ in pairs(mirrors) do
		n.Mirrors += 1
	end
	for _ in pairs(screens) do
		n.Screens += 1
	end
	for _ in pairs(floors) do
		n.Floors += 1
	end
	for _ in pairs(lives) do
		n.Live += 1
	end
	for _ in pairs(sheens) do
		n.Sheens += 1
	end
	for _ in pairs(floorSaved) do
		n.FloorsGlossy += 1
	end
	return n
end

return Reflections
