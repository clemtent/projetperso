--[[
	House3DKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3DKit

	Boîte à outils de la vue 3D (House3D) et du monde : construit les VRAIS
	objets 3D (Parts de taille normale : blocs, boules, cylindres, pentes,
	ovales = Part + SpecialMesh "Sphere", tubes d'un point à un autre, blocs
	arrondis, coussins, formes plates en relief : cœurs, étoiles, triangles,
	chemins de tubes). v9.3 : plus aucun carton découpé (SurfaceGui) pour
	les objets ; seul b.Art (affiches, vue d'une fenêtre) pose un dessin 2D
	sur une face, par-dessus un panneau déjà coloré.

	Repère d'un objet ("unités") : la boîte de dessin 2D de l'objet fait
	100 x 100 unités ; en 3D, 1 unité = K studs (K = taille à l'écran x 0.05
	/ 100). x = vers la droite (-50 .. 50), y = vers le haut depuis le sol
	(0 .. 100 = hauteur de la boîte 2D), z = vers l'avant (vers la caméra
	quand l'objet regarde la pièce). Les dessus des meubles (HouseSurfaces)
	sont à la même hauteur qu'en 2D : ce qui est posé dessus tombe juste.

	Couleurs : la palette d'un objet est lue dans SON dessin 2D (HouseArt :
	les couleurs qui couvrent le plus de surface d'abord), puis passe par la
	variante de couleur de l'objet (HouseTints, si le module existe).

	API :
	  House3DKit.Paint(item, entry, night) -> Painted   (dessin 2D hors écran + palette)
	  House3DKit.Palette(painted) -> { Color3 }
	  House3DKit.Builder(parent, origin, k, mirror, map, palette) -> Builder
	  House3DKit.Triangle / Heart / Star / StarSoft / HeartPoints / StarPoints / Path / Frame (formes)
	  House3DKit.NewPart(className, name, size, cframe, color, material?, transparency?) -> BasePart
	  House3DKit.Surface(part, face, canvasSize, lightInfluence) -> SurfaceGui
	  House3DKit.Separate(parts) -> number   (v9.6 : écarte les faces confondues, anti-scintillement)
	  House3DKit.Wood / Dist / Darken / Lighten / Pick (couleurs)
]]

local HouseArt = require(script.Parent.HouseArt)

local House3DKit = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local BUTTER = Color3.fromRGB(255, 226, 130)
local MIN_SIZE = 0.03 -- (studs) plus petite dimension d'une pièce
local CARD_MARGIN_X = 28 -- marges du carton (unités) : halos, débords
local CARD_MARGIN_TOP = 36
local CARD_MARGIN_BOTTOM = 4
local CARD_MARGIN_WALL = 26
local CARD_RES = 4 -- px de toile par unité
-- (Roblox : une SurfaceGui neuve a MaxDistance = 1000 -> on le fixe nous-mêmes)
House3DKit.MAX_DISTANCE = 3000

export type Painted = {
	Item: any,
	Content: Frame, -- boîte + marges (unités), hors écran
	Wall: boolean,
	UnitsW: number,
	UnitsH: number,
	MarginTop: number,
	MarginBottom: number,
	Glow: Color3?,
	Flat: boolean,
	Colors: { Color3 },
}

export type Top = { X: number, Y: number, Z: number, W: number, D: number }

export type Builder = {
	K: number,
	Mirror: boolean,
	Parts: { BasePart },
	Locals: { CFrame },
	Lights: { Light },
	Glows: { BasePart },
	Tops: { [number]: Top },
	Width: number,
	Depth: number,
	Height: number,
	Pal: { Color3 },
	Painted: Painted?,
	PaintFn: (() -> Painted?)?,
	Item: any?,
	P: (index: number, fallback: Color3) -> Color3,
	Map: (color: Color3) -> Color3,
	Part: (className: string, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material?, name: string?) -> BasePart,
	Box: (x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, material: Enum.Material?) -> BasePart,
	BoxR: (cframe: CFrame, w: number, h: number, d: number, color: Color3, material: Enum.Material?) -> BasePart,
	Ball: (x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?) -> BasePart,
	Cyl: (x: number, y: number, z: number, diameter: number, height: number, color: Color3, material: Enum.Material?) -> BasePart,
	CylX: (x: number, y: number, z: number, diameter: number, length: number, color: Color3, material: Enum.Material?) -> BasePart,
	CylZ: (x: number, y: number, z: number, diameter: number, length: number, color: Color3, material: Enum.Material?) -> BasePart,
	Wedge: (x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, facing: string, material: Enum.Material?) -> BasePart,
	Egg: (x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, material: Enum.Material?) -> BasePart,
	EggR: (cframe: CFrame, w: number, h: number, d: number, color: Color3, material: Enum.Material?) -> BasePart,
	Tube: (x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, diameter: number, color: Color3, material: Enum.Material?) -> BasePart,
	Round: (x: number, y: number, z: number, w: number, h: number, d: number, r: number, color: Color3, material: Enum.Material?) -> BasePart,
	Cushion: (x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, material: Enum.Material?) -> BasePart,
	Seat: (x: number, y: number, z: number, w: number, d: number) -> (),
	SeatAt: { X: number, Y: number, Z: number, W: number, D: number }?,
	Flags: { [string]: any },
	Light: (part: BasePart, color: Color3, range: number, brightness: number) -> (),
	Neon: (part: BasePart) -> (),
	Top: (index: number, x: number, y: number, z: number, w: number, d: number) -> (),
	Footprint: (w: number, d: number, h: number) -> (),
	Art: (x: number, y: number, z: number, w: number, h: number, zoom: number) -> BasePart,
}

----------------------------------------------------------------------
-- Couleurs
----------------------------------------------------------------------

function House3DKit.Darken(color: Color3, amount: number): Color3
	return color:Lerp(BLACK, amount)
end

function House3DKit.Lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

function House3DKit.Dist(a: Color3, b: Color3): number
	local dr, dg, db = a.R - b.R, a.G - b.G, a.B - b.B
	return math.sqrt(dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11)
end

-- Couleur de la palette qui ressemble à du bois (sinon `fallback`)
function House3DKit.Wood(palette: { Color3 }, fallback: Color3): Color3
	for _, color in ipairs(palette) do
		local h, s, v = color:ToHSV()
		if h >= 0.02 and h <= 0.13 and s >= 0.18 and s <= 0.75 and v >= 0.35 and v <= 0.95 then
			return color
		end
	end
	return fallback
end

-- Première couleur de la palette qui vérifie `test`
function House3DKit.Pick(palette: { Color3 }, test: (h: number, s: number, v: number) -> boolean, fallback: Color3): Color3
	for _, color in ipairs(palette) do
		local h, s, v = color:ToHSV()
		if test(h, s, v) then
			return color
		end
	end
	return fallback
end

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

function House3DKit.NewPart(className: string, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material or Enum.Material.SmoothPlastic
	part.Color = color
	part.Transparency = transparency or 0
	part.Size = Vector3.new(math.max(MIN_SIZE, size.X), math.max(MIN_SIZE, size.Y), math.max(MIN_SIZE, size.Z))
	part.CFrame = cframe
	return part
end

-- Toile sur une face (taille fixe en px ; normale, jamais géante)
function House3DKit.Surface(part: BasePart, face: Enum.NormalId, canvasSize: Vector2, lightInfluence: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Canvas" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(math.max(8, math.floor(canvasSize.X + 0.5)), math.max(8, math.floor(canvasSize.Y + 0.5)))
	gui.LightInfluence = lightInfluence
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.MaxDistance = House3DKit.MAX_DISTANCE
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	return gui
end

-- Miroir gauche <-> droite d'une rotation (conjugaison par diag(-1, 1, 1))
local function mirrorCFrame(cf: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

local WEDGE_YAW: { [string]: number } = {
	Back = 0, -- (WedgePart de Roblox : la pente regarde -Z)
	Front = math.pi,
	Right = -math.pi / 2,
	Left = math.pi / 2,
}

-- Constructeur d'un objet : pièces en unités, dans le repère `origin`
function House3DKit.Builder(parent: Instance, origin: CFrame, k: number, mirror: boolean, map: ((Color3) -> Color3)?, palette: { Color3 }?): Builder
	local b = {} :: Builder
	b.K = k
	b.Mirror = mirror
	b.Parts = {}
	b.Locals = {}
	b.Lights = {}
	b.Glows = {}
	b.Tops = {}
	b.Width, b.Depth, b.Height = 100, 60, 100
	local mapper = map or function(color: Color3): Color3
		return color
	end
	b.Map = mapper
	local pal = {}
	for _, color in ipairs(palette or {}) do
		table.insert(pal, mapper(color))
	end
	b.Pal = pal
	b.P = function(index: number, fallback: Color3): Color3
		return pal[index] or mapper(fallback)
	end

	b.Part = function(className: string, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material?, name: string?): BasePart
		local localCF = CFrame.new(cframe.X * k, cframe.Y * k, cframe.Z * k) * cframe.Rotation
		if mirror then
			localCF = mirrorCFrame(localCF)
		end
		local part = House3DKit.NewPart(className, name or "Piece", size * k, origin * localCF, color, material)
		part.Parent = parent
		table.insert(b.Parts, part)
		table.insert(b.Locals, localCF)
		return part
	end
	b.Box = function(x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, material: Enum.Material?): BasePart
		return b.Part("Part", CFrame.new(x, y + h / 2, z), Vector3.new(w, h, d), color, material)
	end
	b.BoxR = function(cframe: CFrame, w: number, h: number, d: number, color: Color3, material: Enum.Material?): BasePart
		return b.Part("Part", cframe, Vector3.new(w, h, d), color, material)
	end
	b.Ball = function(x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
		local part = b.Part("Part", CFrame.new(x, y, z), Vector3.new(diameter, diameter, diameter), color, material, "Boule")
		;(part :: Part).Shape = Enum.PartType.Ball
		return part
	end
	-- Cylindre debout (y = bas)
	b.Cyl = function(x: number, y: number, z: number, diameter: number, height: number, color: Color3, material: Enum.Material?): BasePart
		local part = b.Part("Part", CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(height, diameter, diameter), color, material, "Cylindre")
		;(part :: Part).Shape = Enum.PartType.Cylinder
		return part
	end
	-- Cylindre couché gauche-droite (centre)
	b.CylX = function(x: number, y: number, z: number, diameter: number, length: number, color: Color3, material: Enum.Material?): BasePart
		local part = b.Part("Part", CFrame.new(x, y, z), Vector3.new(length, diameter, diameter), color, material, "Cylindre")
		;(part :: Part).Shape = Enum.PartType.Cylinder
		return part
	end
	-- Cylindre couché avant-arrière (centre)
	b.CylZ = function(x: number, y: number, z: number, diameter: number, length: number, color: Color3, material: Enum.Material?): BasePart
		local part = b.Part("Part", CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(length, diameter, diameter), color, material, "Cylindre")
		;(part :: Part).Shape = Enum.PartType.Cylinder
		return part
	end
	-- Coin en pente (y = bas) ; `facing` = où regarde la pente
	b.Wedge = function(x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, facing: string, material: Enum.Material?): BasePart
		local yaw = WEDGE_YAW[facing] or 0
		local size = (facing == "Left" or facing == "Right") and Vector3.new(d, h, w) or Vector3.new(w, h, d)
		return b.Part("WedgePart", CFrame.new(x, y + h / 2, z) * CFrame.Angles(0, yaw, 0), size, color, material, "Pente")
	end
	-- Ellipsoïde (centre x, y, z) : Part + SpecialMesh "Sphere" (une Ball de
	-- Roblox est toujours ronde : taille uniforme forcée ; le maillage
	-- Sphere, lui, suit la taille de la pièce sur les 3 axes)
	b.EggR = function(cframe: CFrame, w: number, h: number, d: number, color: Color3, material: Enum.Material?): BasePart
		local part = b.Part("Part", cframe, Vector3.new(w, h, d), color, material, "Ovale")
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		return part
	end
	b.Egg = function(x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, material: Enum.Material?): BasePart
		if math.abs(w - h) < 0.01 and math.abs(h - d) < 0.01 then
			return b.Ball(x, y, z, w, color, material)
		end
		return b.EggR(CFrame.new(x, y, z), w, h, d, color, material)
	end
	-- Tube (cylindre) d'un point à un autre (pieds, tiges, anses, bras...)
	b.Tube = function(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
		local a, c = Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
		local delta = c - a
		local length = math.max(0.01, delta.Magnitude)
		local direction = length > 0.01 and delta / length or Vector3.new(0, 1, 0)
		local up = math.abs(direction.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		-- (le cylindre de Roblox est couché sur X : on aligne X sur le tube)
		local cf = CFrame.lookAt((a + c) / 2, (a + c) / 2 + direction, up) * CFrame.Angles(0, math.pi / 2, 0)
		local part = b.Part("Part", cf, Vector3.new(length, diameter, diameter), color, material, "Tube")
		;(part :: Part).Shape = Enum.PartType.Cylinder
		return part
	end
	-- Bloc aux arêtes verticales arrondies (y = bas) : 2 blocs + 4 cylindres
	b.Round = function(x: number, y: number, z: number, w: number, h: number, d: number, r: number, color: Color3, material: Enum.Material?): BasePart
		r = math.clamp(r, 0.2, math.min(w, d) / 2 - 0.05)
		local main = b.Box(x, y, z, w - 2 * r, h, d, color, material)
		b.Box(x, y, z, w, h, d - 2 * r, color, material)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				b.Cyl(x + sx * (w / 2 - r), y, z + sz * (d / 2 - r), 2 * r, h, color, material)
			end
		end
		return main
	end
	-- Coussin moelleux (y = bas) : cœur en bloc + enveloppe ovale
	b.Cushion = function(x: number, y: number, z: number, w: number, h: number, d: number, color: Color3, material: Enum.Material?): BasePart
		local core = b.Box(x, y + h * 0.12, z, w * 0.9, h * 0.72, d * 0.86, color, material or Enum.Material.Fabric)
		b.Egg(x, y + h / 2, z, w, h, d, color, material or Enum.Material.Fabric)
		return core
	end
	-- Place assise (unités, face vers +z) : un personnage peut s'y asseoir (monde)
	b.Seat = function(x: number, y: number, z: number, w: number, d: number)
		b.SeatAt = { X = mirror and -x or x, Y = y, Z = z, W = w, D = d }
	end
	b.Flags = {}
	b.Light = function(part: BasePart, color: Color3, range: number, brightness: number)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = math.clamp(range, 2, 60)
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = part
		table.insert(b.Lights, light)
	end
	-- Pièce lumineuse (abat-jour, ampoule, écran) : Neon, plus fort la nuit
	b.Neon = function(part: BasePart)
		part.Material = Enum.Material.Neon
		part.CastShadow = false
		table.insert(b.Glows, part)
	end
	b.Top = function(index: number, x: number, y: number, z: number, w: number, d: number)
		b.Tops[index] = { X = mirror and -x or x, Y = y, Z = z, W = w, D = d }
	end
	b.Footprint = function(w: number, d: number, h: number)
		b.Width, b.Depth, b.Height = w, d, h
	end
	-- Panneau (y = bas) qui montre le dessin 2D de l'objet sur sa face avant
	-- (vue d'une fenêtre, tableau...) ; `zoom` > 1 = on ne garde que le centre
	local artUsed = false
	b.Art = function(x: number, y: number, z: number, w: number, h: number, zoom: number): BasePart
		local panel = b.Box(x, y, z, w, h, 1, b.P(1, WHITE), Enum.Material.SmoothPlastic)
		panel.CastShadow = false
		local painted = b.Painted
		if not painted and b.PaintFn then
			painted = b.PaintFn()
			b.Painted = painted
		end
		if not painted then
			return panel
		end
		local canvas = Vector2.new(math.max(16, w * CARD_RES), math.max(16, h * CARD_RES))
		local gui = House3DKit.Surface(panel, Enum.NormalId.Back, canvas, 0.5)
		local content = artUsed and painted.Content:Clone() or painted.Content
		artUsed = true
		local scale = CARD_RES * zoom
		local marginX = (painted.UnitsW - 100) / 2
		content.Position = UDim2.fromOffset(canvas.X / 2 - (marginX + 50) * scale, canvas.Y / 2 - (painted.MarginTop + 50) * scale)
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = scale
		uiScale.Parent = content
		content.Parent = gui
		return panel
	end
	return b
end

----------------------------------------------------------------------
-- v9.6 : anti-scintillement (z-fighting). Deux faces de pièces DIFFÉRENTES
-- (couleur / matière / transparence) dans le même plan, du même côté, qui se
-- recouvrent : Roblox les dessine en alternance ("bugs de texture" vus par
-- le joueur). Separate écarte la plus petite des deux de SEP_GAP studs vers
-- l'extérieur (la pièce grandit de ce côté-là, rien ne s'ouvre ni ne flotte).
----------------------------------------------------------------------

local SEP_GAP = 0.035 -- (studs) écart visé entre deux faces du même côté
local SEP_NEAR = 0.025 -- en dessous : faces "confondues"
local SEP_OVERLAP = 0.02 -- (studs²) recouvrement minimal pris en compte

type SepFace = { Part: BasePart, Axis: number, N: Vector3, D: number, U0: number, U1: number, V0: number, V1: number, Area: number }

local function sepBasis(n: Vector3): (Vector3, Vector3)
	local u = n:Cross(math.abs(n.Y) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)).Unit
	return u, n:Cross(u)
end

-- Faces planes d'une pièce (bloc : 6 ; cylindre : 2 disques ; pente : dessous, dos, côtés)
local function sepFaces(part: BasePart, out: { SepFace })
	if part.Transparency >= 0.99 then
		return
	end
	local shape = "Block"
	if part:IsA("WedgePart") then
		shape = "Wedge"
	elseif part:IsA("Part") then
		local partShape = (part :: Part).Shape
		if partShape == Enum.PartType.Ball then
			return
		elseif partShape == Enum.PartType.Cylinder then
			shape = "Cylinder"
		elseif partShape ~= Enum.PartType.Block then
			return
		end
	else
		return
	end
	local cf, size = part.CFrame, part.Size
	local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local half = { size.X / 2, size.Y / 2, size.Z / 2 }
	for axis = 1, 3 do
		for _, sign in ipairs({ 1, -1 }) do
			local keep = true
			if shape == "Cylinder" then
				keep = axis == 1
			elseif shape == "Wedge" then
				keep = (axis == 2 and sign < 0) or (axis == 3 and sign > 0) or axis == 1
			end
			if keep then
				local n = axes[axis] * sign
				local center = cf.Position + n * half[axis]
				local b, c = axis == 1 and 2 or 1, axis == 3 and 2 or 3
				local hb, hc = axes[b] * half[b], axes[c] * half[c]
				if shape == "Cylinder" then
					local r = math.min(size.Y, size.Z) / 2
					hb, hc = axes[2] * r, axes[3] * r
				end
				local u, v = sepBasis(n)
				local u0, u1, v0, v1 = math.huge, -math.huge, math.huge, -math.huge
				for _, corner in ipairs({ center + hb + hc, center + hb - hc, center - hb + hc, center - hb - hc }) do
					local pu, pv = corner:Dot(u), corner:Dot(v)
					u0, u1 = math.min(u0, pu), math.max(u1, pu)
					v0, v1 = math.min(v0, pv), math.max(v1, pv)
				end
				table.insert(out, { Part = part, Axis = axis, N = n, D = n:Dot(center), U0 = u0, U1 = u1, V0 = v0, V1 = v1, Area = (u1 - u0) * (v1 - v0) })
			end
		end
	end
end

local function sepDiffers(a: BasePart, b: BasePart): boolean
	if a.Material ~= b.Material or math.abs(a.Transparency - b.Transparency) > 0.05 then
		return true
	end
	local ca, cb = a.Color, b.Color
	return math.max(math.abs(ca.R - cb.R), math.abs(ca.G - cb.G), math.abs(ca.B - cb.B)) > 3 / 255
end

-- Écarte les faces confondues d'une liste de pièces (un objet, une coque de
-- pièce...) ; renvoie le nombre de faces déplacées
function House3DKit.Separate(parts: { BasePart }, fixed: { [BasePart]: boolean }?): number
	local still = fixed or {}
	local order: { [BasePart]: number } = {}
	for index, part in ipairs(parts) do
		order[part] = index
	end
	local function keyOf(n: Vector3, slot: number): string
		return string.format("%d,%d,%d,%d", math.floor(n.X * 50 + 0.5), math.floor(n.Y * 50 + 0.5), math.floor(n.Z * 50 + 0.5), slot)
	end
	local function overlaps(a: SepFace, b: SepFace, minimum: number): boolean
		local ou = math.min(a.U1, b.U1) - math.max(a.U0, b.U0)
		local ov = math.min(a.V1, b.V1) - math.max(a.V0, b.V0)
		return ou > 0 and ov > 0 and ou * ov > minimum
	end
	local moved = 0
	for _ = 1, 8 do
		local faces: { SepFace } = {}
		for _, part in ipairs(parts) do
			sepFaces(part, faces)
		end
		local buckets: { [string]: { SepFace } } = {}
		local function add(face: SepFace)
			local key = keyOf(face.N, math.floor(face.D / 0.05))
			local list = buckets[key]
			if not list then
				list = {}
				buckets[key] = list
			end
			table.insert(list, face)
		end
		for _, face in ipairs(faces) do
			add(face)
		end
		-- une face voisine (autre pièce, autre couleur) trop près du plan `d` ?
		local function clashes(face: SepFace, d: number): boolean
			for ek = -1, 1 do
				for _, other in ipairs(buckets[keyOf(face.N, math.floor(d / 0.05) + ek)] or {}) do
					if other.Part ~= face.Part and other.N:Dot(face.N) > 0.999 and math.abs(other.D - d) < SEP_NEAR
						and overlaps(other, face, 0) and sepDiffers(other.Part, face.Part) then
						return true
					end
				end
			end
			return false
		end
		local touched: { [BasePart]: boolean } = {}
		local fixes = 0
		for _, a in ipairs(faces) do
			local slot = math.floor(a.D / 0.05)
			for dk = -1, 1 do
				for _, b in ipairs(buckets[keyOf(a.N, slot + dk)] or {}) do
					if b.Part ~= a.Part and not touched[a.Part] and not touched[b.Part] and a.N:Dot(b.N) > 0.999
						and math.abs(a.D - b.D) < SEP_NEAR and overlaps(a, b, SEP_OVERLAP) and sepDiffers(a.Part, b.Part) then
						-- la plus petite face avance (à aire égale : la pièce ajoutée après) ;
						-- une pièce "fixe" (mur, sol...) ne bouge jamais
						local small, large = a, b
						if b.Area < a.Area or (b.Area == a.Area and (order[b.Part] or 0) > (order[a.Part] or 0)) then
							small, large = b, a
						end
						if still[small.Part] then
							small, large = large, small
						end
						if not still[small.Part] then
							-- plan visé : SEP_GAP devant la grande face, loin de toute autre
							-- face voisine (deux corrections ne se recollent pas)
							local target = math.max(small.D, large.D) + SEP_GAP
							for _ = 1, 8 do
								if not clashes(small, target) then
									break
								end
								target += SEP_GAP
							end
							local grow = target - small.D
							local part = small.Part
							local extra = small.Axis == 1 and Vector3.new(grow, 0, 0) or (small.Axis == 2 and Vector3.new(0, grow, 0) or Vector3.new(0, 0, grow))
							part.Size += extra
							part.CFrame = part.CFrame + small.N * (grow / 2)
							touched[part] = true
							fixes += 1
							-- (le nouveau plan compte tout de suite pour les corrections suivantes)
							add({ Part = part, Axis = small.Axis, N = small.N, D = target, U0 = small.U0, U1 = small.U1, V0 = small.V0, V1 = small.V1, Area = small.Area })
						end
					end
				end
			end
		end
		moved += fixes
		if fixes == 0 then
			break
		end
	end
	return moved
end

----------------------------------------------------------------------
-- Formes plates en relief (plan x-y, épaisseur vers +z) : cœurs, étoiles,
-- triangles, et tubes le long d'un chemin (néons, guirlandes, anses...)
----------------------------------------------------------------------

-- Triangle isocèle centré en (cx, cy), pointe vers `angle` (0 = vers le haut)
function House3DKit.Triangle(b: Builder, cx: number, cy: number, z: number, base: number, height: number, angle: number, thick: number, color: Color3, material: Enum.Material?)
	local cf = CFrame.new(cx, cy, z + thick / 2) * CFrame.Angles(0, 0, angle) * CFrame.Angles(0, math.pi / 2, 0)
	local half = base / 2
	b.Part("WedgePart", cf * CFrame.new(0, 0, -half / 2), Vector3.new(thick, height, half), color, material, "Pointe")
	b.Part("WedgePart", cf * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -half / 2), Vector3.new(thick, height, half), color, material, "Pointe")
end

-- Cœur plat : un carré tourné + deux disques (largeur totale `size`)
function House3DKit.Heart(b: Builder, cx: number, cy: number, z: number, size: number, thick: number, color: Color3, material: Enum.Material?)
	local side = size / 1.707
	local oy = cy - side * 0.0735
	b.BoxR(CFrame.new(cx, oy, z + thick / 2) * CFrame.Angles(0, 0, math.pi / 4), side, side, thick, color, material)
	local offset = side / (2 * math.sqrt(2))
	for _, sx in ipairs({ -1, 1 }) do
		b.CylZ(cx + sx * offset, oy + offset, z + thick / 2, side, thick, color, material)
	end
end

-- Étoile plate à 5 branches (rayon extérieur `radius`)
function House3DKit.Star(b: Builder, cx: number, cy: number, z: number, radius: number, thick: number, color: Color3, material: Enum.Material?)
	b.CylZ(cx, cy, z + thick / 2, radius * 0.9, thick, color, material)
	for index = 0, 4 do
		local angle = index * math.pi * 2 / 5
		local d = radius * 0.62
		House3DKit.Triangle(b, cx - math.sin(angle) * d, cy + math.cos(angle) * d, z, radius * 0.62, radius * 0.72, angle, thick, color, material)
	end
end

-- Étoile "douce" (5 branches ovales + cœur rond) : 6 pièces seulement
function House3DKit.StarSoft(b: Builder, cx: number, cy: number, z: number, radius: number, thick: number, color: Color3, material: Enum.Material?): BasePart
	local core = b.CylZ(cx, cy, z + thick / 2, radius * 0.8, thick, color, material)
	for index = 0, 4 do
		local angle = index * math.pi * 2 / 5
		local d = radius * 0.5
		b.EggR(CFrame.new(cx - math.sin(angle) * d, cy + math.cos(angle) * d, z + thick / 2) * CFrame.Angles(0, 0, angle), radius * 0.5, radius, thick, color, material)
	end
	return core
end

-- Points d'un cœur (contour) / d'une étoile (contour), plan x-y
function House3DKit.HeartPoints(cx: number, cy: number, z: number, size: number, count: number): { { number } }
	local points = {}
	for index = 0, count do
		local t = index / count * math.pi * 2
		local x = 16 * math.sin(t) ^ 3
		local y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
		table.insert(points, { cx + x * size / 34, cy + (y + 2) * size / 34, z })
	end
	return points
end
function House3DKit.StarPoints(cx: number, cy: number, z: number, radius: number, inner: number): { { number } }
	local points = {}
	for index = 0, 10 do
		local angle = index * math.pi / 5
		local r = index % 2 == 0 and radius or radius * inner
		table.insert(points, { cx - math.sin(angle) * r, cy + math.cos(angle) * r, z })
	end
	return points
end

-- Tubes le long d'un chemin (+ petites boules aux coudes)
function House3DKit.Path(b: Builder, points: { { number } }, diameter: number, color: Color3, material: Enum.Material?, neon: boolean?, noJoints: boolean?): { BasePart }
	local parts = {}
	for index = 1, #points - 1 do
		local a, c = points[index], points[index + 1]
		local tube = b.Tube(a[1], a[2], a[3], c[1], c[2], c[3], diameter, color, material)
		table.insert(parts, tube)
		if index > 1 and not noJoints then
			table.insert(parts, b.Ball(a[1], a[2], a[3], diameter, color, material))
		end
	end
	if neon then
		for _, part in ipairs(parts) do
			b.Neon(part)
		end
	end
	return parts
end

-- Cadre rectangulaire (4 baguettes), y = bas
function House3DKit.Frame(b: Builder, x: number, y: number, z: number, w: number, h: number, bar: number, depth: number, color: Color3, material: Enum.Material?)
	b.Box(x, y, z, w, bar, depth, color, material)
	b.Box(x, y + h - bar, z, w, bar, depth, color, material)
	b.Box(x - w / 2 + bar / 2, y + bar, z, bar, h - 2 * bar, depth, color, material)
	b.Box(x + w / 2 - bar / 2, y + bar, z, bar, h - 2 * bar, depth, color, material)
end

----------------------------------------------------------------------
-- Dessin 2D hors écran (palette, cartons)
----------------------------------------------------------------------

function House3DKit.Paint(item: any, entry: any, tint: ((root: Instance) -> ())?): Painted
	local wall = item.Placement == "Wall"
	local marginTop = wall and CARD_MARGIN_WALL or CARD_MARGIN_TOP
	local marginBottom = wall and CARD_MARGIN_WALL or CARD_MARGIN_BOTTOM
	local content = Instance.new("Frame")
	content.Name = tostring(item.Id)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromOffset(100 + CARD_MARGIN_X * 2, 100 + marginTop + marginBottom)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(CARD_MARGIN_X, marginTop)
	body.Size = UDim2.fromOffset(100, 100)
	body.ZIndex = 3
	body.Parent = content
	local painted = HouseArt.Paint(body, item, true)
	local detail: HouseArt.Result = painted or {}
	if painted == nil or detail.ShowEmoji == true then
		local emojiScale = detail.EmojiScale or 1
		local emoji = Instance.new("TextLabel")
		emoji.Name = "Emoji"
		emoji.AnchorPoint = Vector2.new(0.5, 0.5)
		emoji.Position = UDim2.fromScale(0.5, detail.EmojiY or (wall and 0.5 or 0.54))
		emoji.Size = UDim2.fromOffset(100 * emojiScale, 100 * emojiScale)
		emoji.BackgroundTransparency = 1
		emoji.Font = Enum.Font.BuilderSansMedium
		emoji.Text = tostring(item.Icon or "")
		emoji.TextColor3 = WHITE
		emoji.TextSize = math.floor(88 * emojiScale)
		emoji.TextYAlignment = wall and Enum.TextYAlignment.Center or Enum.TextYAlignment.Bottom
		emoji.ZIndex = 9
		emoji.Parent = body
	end
	if tint then
		pcall(tint, body)
	end
	if type(entry) == "table" and entry.F == true then
		pcall(HouseArt.Mirror, body, {}, 50)
	end
	local result: Painted = {
		Item = item,
		Content = content,
		Wall = wall,
		UnitsW = 100 + CARD_MARGIN_X * 2,
		UnitsH = 100 + marginTop + marginBottom,
		MarginTop = marginTop,
		MarginBottom = marginBottom,
		Glow = detail.Glow or (item.Category == "Lights" and BUTTER or nil),
		Flat = detail.Flat == true and not wall,
		Colors = {},
	}
	result.Colors = House3DKit.Palette(result)
	return result
end

-- Palette : couleurs du dessin, de la plus grande surface à la plus petite
function House3DKit.Palette(painted: Painted): { Color3 }
	local areas: { [string]: { Color: Color3, Area: number } } = {}
	local body = painted.Content:FindFirstChild("Body")
	if not body then
		return {}
	end
	for _, object in ipairs(body:GetDescendants()) do
		if object:IsA("Frame") and object.BackgroundTransparency < 0.5 and object.Visible then
			local size = object.Size
			local area = math.abs(size.X.Offset * size.Y.Offset)
			if area > 0 then
				local color = object.BackgroundColor3
				local key = string.format("%d_%d_%d", math.floor(color.R * 15 + 0.5), math.floor(color.G * 15 + 0.5), math.floor(color.B * 15 + 0.5))
				local slot = areas[key]
				if slot then
					slot.Area += area
				else
					areas[key] = { Color = color, Area = area }
				end
			end
		end
	end
	local list = {}
	for _, slot in pairs(areas) do
		table.insert(list, slot)
	end
	table.sort(list, function(a, b)
		return a.Area > b.Area
	end)
	local colors = {}
	for index = 1, math.min(8, #list) do
		table.insert(colors, list[index].Color)
	end
	return colors
end

return House3DKit
