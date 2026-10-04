--[[
	Reflections (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > Reflections

	v11 (REALISM11) 🪞 MIROIRS ROBUSTES — refaits de zéro.
	Le joueur : "les miroirs sont TOUJOURS complètement cassés". Les v9.8 /
	v9.9 clonaient la géométrie de la pièce (jusqu'à 650 copies, coupées au
	plan, maillages, SurfaceGui, unions...) : trop de cas où une copie se
	retrouvait au mauvais endroit. Et trois pièges du VRAI moteur :
	  - la SurfaceGui (PlayerGui) avait ResetOnSpawn = true : détruite à
	    chaque (ré)apparition du personnage (entrée en ville !) -> écran gris
	    figé, plus jamais de reflet ;
	  - miroirs ovales : CanvasGroup + ViewportFrame (pas sûr d'être dessiné
	    dans Roblox) et disque "elliptique" en Cylinder (un cylindre Roblox
	    est TOUJOURS rond : min(Y, Z)) ;
	  - copie du personnage appariée par l'ORDRE des enfants (un enfant non
	    archivable décalait tout : copie figée à la position réelle, DEVANT
	    la glace = un personnage géant en travers du miroir).
	Nouvelle conception, faite pour qu'aucun artefact ne soit POSSIBLE :
	  1) Ce qu'on voit dans le miroir = UNIQUEMENT
	     a) un DÉCOR SIMPLE construit à partir des mesures de la pièce
	        (5 lancers de rayon depuis le miroir : sol, plafond, murs de côté,
	        mur d'en face ; couleurs / matière des surfaces touchées) : une
	        BOÎTE fermée (sol, plafond, 3 murs, plinthes, corniche, plafonnier)
	        entièrement DERRIÈRE le plan de la glace, plus large que la glace :
	        tout rayon qui entre par la glace touche forcément une face ;
	     b) les PERSONNAGES (le joueur + jusqu'à 3 joueurs proches, devant le
	        miroir) : copies pièce par pièce (table source -> copie, jamais
	        l'ordre des enfants), placées réfléchies AVANT d'entrer dans le
	        monde du reflet ; une pièce dont le centre passe derrière la glace
	        est cachée.
	     Rien d'autre (pas de meubles clonés) : pas de géométrie arbitraire.
	  2) Affichage : une plaque OPAQUE (client, dans la caméra, ni rayons ni
	     collisions) posée 0,04 stud devant la glace, de la forme EXACTE de la
	     glace (rectangle ; ovale = "stade" : bloc + 2 cylindres ronds ; arche
	     = rectangle + demi-disque), et juste devant elle une toile invisible
	     portant la SurfaceGui (ResetOnSpawn = false, reconstruite si elle
	     disparaît). Couches de la SurfaceGui :
	       Glass  : verre "statique" joli (dégradé plafond -> mur -> sol de la
	                pièce) = ce qu'on voit si le reflet vivant est coupé ;
	       Strips : la ViewportFrame du reflet, dans des cadres RECTANGULAIRES
	                (ClipsDescendants, la seule découpe sûre de Roblox) ;
	                rectangle : 1 bande ; ovale / arche : bandes horizontales
	                (2m - 1 / m + 1) qui couvrent la forme intérieure, chaque
	                coin qui dépasse étant caché par le biseau ;
	       Sheen  : reflet de lumière diagonal qui glisse avec l'angle de vue ;
	       Bevel  : biseau chromé (UIStroke sur cadre arrondi) entre la forme
	                intérieure et le bord de la glace (ovale, arche).
	     Aucun pixel du reflet ne peut sortir de la glace (vérifié : tests
	     RealismMirror) et rien n'est jamais entre la caméra du reflet et la
	     glace.
	  3) Mathématiques (inchangées, vérifiées numériquement) :
	     plan : centre M, normale n, axes de la toile u (droite vue de face),
	     v (haut), u x v = n ; réflexion p' = p - 2 ((p - M) . n) n ;
	     réflexion d'un CFrame : position réfléchie, axes (-H X, H Y, H Z),
	     H = I - 2 n nᵀ (rotation PROPRE, axe X local retourné) ;
	     caméra du reflet = position de la VRAIE caméra, qui regarde -n : son
	     plan image est parallèle à la glace, la projection sur la glace est
	     affine ; ViewportFrame centrée sur le pied de la perpendiculaire
	     (cx, cy), demi-taille (|cx| + W/2, |cy| + H/2),
	     FieldOfView = 2 atan(demi-hauteur / D), D = (C - M) . n.
	     STRICT : si la vue ne peut pas couvrir TOUTE la glace (trop près,
	     trop de biais, champ > 118°), on n'affiche pas le reflet vivant : la
	     couche Glass (jolie) reste, jamais un morceau de reflet tronqué.
	  4) Budget : MaxMirrors miroirs vivants (GraphicsQuality : 1, ou 2 en
	     "Tout" + Détail élevé), le plus grand à l'écran, ~30 images / s ;
	     pixels de toutes les bandes d'un miroir ≤ PIXEL_BUDGET ; en pause s'il
	     est caché, derrière un mur, de dos ou à plus de 45 studs. Jusqu'à 4
	     autres miroirs proches en verre "statique" joli (aussi quand Reflets
	     = Aucun : jamais le ciel bleu dans un miroir d'intérieur).
	5) Reflets "Tout" (inchangé) : voile de verre sur les écrans, sols des
	   pièces légèrement brillants.

	Contrat des objets (RECIPES / CATALOG) : une BasePart "Mirror" (bloc
	mince), attributs Mirror = true, MirrorFace = "Front" | "Back" | "Left" |
	"Right" (face qui réfléchit), MirrorShape = "Rect" | "Oval" | "Arch".
	Rect + un cylindre de verre posé sur son bord haut (BigWallMirror) =
	arche détectée automatiquement.

	API :
	  Reflections.Acquire(owner) / Release(owner) / IsActive()
	  Reflections.Live() -> { Display }   Reflections.ForceStep()   Reflections.Counts()
	  Pures (tests) :
	  Reflections.ReflectPoint(p, M, n) ; ReflectCFrame(cf, M, n)
	  Reflections.PlaneOf(part) -> Plane?
	  Reflections.ShapeOf(kind, halfW, halfH) -> Shape
	  Reflections.CanvasPlane(plane, shape) -> Plane
	  Reflections.Strips(shape, pps?) -> { Strip }, inset
	  Reflections.ComputeView(camPos, canvasPlane, pps?, strips?) -> View?
	  Reflections.ProjectToCanvas(view, canvasPlane, worldPoint) -> Vector2?
	  Reflections.BackdropSpecs(canvasPlane, room) -> { { CFrame, Size, Color, Material, Name } }
	  Reflections.ScreenSpecs(plane, shape) -> { { CFrame, Size, Shape } }, canvasCFrame, canvasSize
	Aucun son.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GraphicsQuality = require(ReplicatedStorage.Shared.GraphicsQuality)

local Reflections = {}

local MAX_FOV = 118 -- (Camera.FieldOfView ≤ 120)
local MAX_HTAN = math.tan(math.rad(80)) -- demi-champ horizontal ≤ 80°
local MAX_ASPECT = 8
local MAX_CANVAS = 2048
local PIXEL_BUDGET = 2.6e6 -- pixels de toutes les bandes d'un miroir
local BASE_PPS = 56
local MIN_PPS = 6
local MIN_DEPTH = 0.25 -- caméra collée à la glace : verre statique
local LIVE_RANGE = 45
local STATIC_RANGE = 34
local STATIC_MAX = 4
local CHAR_RANGE = 30
local FRAME_RATE = 1 / 30
local SELECT_EVERY = 0.25
local ROOM_EVERY = 6
local GLOSS_EVERY = 0.1
local GLOSS_RANGE = 40
local GLOSS_MAX = 10
local OVAL_BANDS = 5 -- m : bandes par demi-calotte
local SHAPE_MIN_PPS = 28 -- densité minimale d'un reflet vivant ovale / en arche
local SCREEN_GAP = 0.04
local SCREEN_T = 0.02
local CANVAS_GAP = 0.006
local RENDER_NAME = "DopamineMirrors"
local BEVEL_COLOR = Color3.fromRGB(214, 224, 234)
local DEFAULT_WALL = Color3.fromRGB(236, 228, 220)
local DEFAULT_FLOOR = Color3.fromRGB(160, 120, 90)
local DEFAULT_CEILING = Color3.fromRGB(246, 244, 240)

----------------------------------------------------------------------
-- Mathématiques (pures)
----------------------------------------------------------------------

export type Plane = {
	Center: Vector3, -- centre de la face qui réfléchit (ou de la toile)
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
	Foot: Vector2, -- pied de la perpendiculaire (studs, repère de la toile)
}

-- Forme de la glace, repère de la TOILE (origine au centre, y vers le haut)
--   Rect : la toile entière ; Oval : "stade" (rayon des coins = min(CW, CH)) ;
--   Arch : rectangle (bas, hauteur 2 Hr) + demi-disque de rayon CW au-dessus
export type Shape = {
	Kind: string,
	CW: number, -- demi-largeur de la toile
	CH: number, -- demi-hauteur de la toile
	OffV: number, -- centre de la toile = centre de la glace "Mirror" + V * OffV
	Hr: number, -- (Arch) demi-hauteur du rectangle
}

-- bande |x| ≤ A, Y0 ≤ y ≤ Y1 (studs) ; JTop / JBottom : bord sur la jonction
-- rectangle / arche (arrondi vers le BAS de la toile : le rectangle ne
-- dépasse jamais dans l'arche)
export type Strip = { Y0: number, Y1: number, A: number, JTop: boolean?, JBottom: boolean? }

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
	if w < 0.05 or size.Y < 0.05 then
		return nil
	end
	-- axe X de la toile d'une SurfaceGui vue de face : haut x normale
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

function Reflections.ShapeOf(kind: string, halfW: number, halfH: number): Shape
	if kind == "Oval" then
		return { Kind = "Oval", CW = halfW, CH = halfH, OffV = 0, Hr = halfH }
	elseif kind == "Arch" then
		-- toile : du bas du rectangle au sommet de l'arche
		return { Kind = "Arch", CW = halfW, CH = halfH + halfW / 2, OffV = halfW / 2, Hr = halfH }
	end
	return { Kind = "Rect", CW = halfW, CH = halfH, OffV = 0, Hr = halfH }
end

function Reflections.CanvasPlane(plane: Plane, shape: Shape): Plane
	return {
		Center = plane.Center + plane.V * shape.OffV,
		U = plane.U,
		V = plane.V,
		N = plane.N,
		HalfW = shape.CW,
		HalfH = shape.CH,
	}
end

-- Largeur du biseau (studs) : couvre le plus grand dépassement des coins
-- des bandes + 1,5 pixel (arrondis) à la densité MINIMALE du reflet vivant
-- `pps` (géométrie valable pour toute densité ≥ pps). Le biseau est un
-- UIStroke tracé DEHORS (Outer : comportement historique de Roblox, et
-- BorderStrokePosition = Outer quand la propriété existe) : il couvre
-- [rho', rho' + T] = le bord de la glace.
local OVER_K = math.sqrt(1 + 1 / OVAL_BANDS) - 1 -- dépassement / rayon intérieur
local function insetFor(rho: number, pps: number): number
	local margin = 1.5 / math.max(pps, 1)
	-- T = k (rho - T) + marge  ->  T = (k rho + marge) / (1 + k)
	return math.min(rho * 0.4, (OVER_K * rho + margin) / (1 + OVER_K))
end

-- Densité minimale (px / stud) d'un reflet vivant pour cette forme : en
-- dessous, le biseau serait trop large -> verre statique
function Reflections.MinPPS(shape: Shape): number
	if shape.Kind == "Rect" then
		return MIN_PPS
	end
	local rho = if shape.Kind == "Oval" then math.min(shape.CW, shape.CH) else shape.CW
	-- (k rho + 1.5 / pps) / (1 + k) <= 0.3 rho
	local room = rho * (0.3 * (1 + OVER_K) - OVER_K)
	return math.max(SHAPE_MIN_PPS, 1.5 / math.max(room, 1e-6))
end

--[[
	Bandes du reflet vivant (pures). Rect : 1 bande = toute la toile.
	Ovale : forme intérieure = stade (a', b') de rayon rho' = min(a', b'),
	rétrécie du biseau T ; calottes découpées à s_k = rho' sqrt(k / m)
	(pas égaux en s² : chaque bande dépasse au plus de rho' (sqrt(1 + 1/m) - 1)
	à ses coins, sous le biseau) ; bande centrale pleine largeur.
	Arche : rectangle plein + m bandes dans le demi-disque de rayon CW - T.
	-> ({ Strip }, T)
]]
function Reflections.Strips(shape: Shape, pps: number?): ({ Strip }, number)
	local density = pps or BASE_PPS
	local m = OVAL_BANDS
	if shape.Kind == "Oval" then
		local rho = math.min(shape.CW, shape.CH)
		local t = insetFor(rho, density)
		local a, b = shape.CW - t, shape.CH - t
		local r = math.min(a, b)
		local flat = b - r -- demi-hauteur de la partie droite (stade haut)
		local base = a - r -- demi-largeur droite (stade large)
		local strips: { Strip } = {}
		local s1 = r * math.sqrt(1 / m)
		table.insert(strips, { Y0 = -(flat + s1), Y1 = flat + s1, A = a })
		for k = 1, m - 1 do
			local sk = r * math.sqrt(k / m)
			local sn = r * math.sqrt((k + 1) / m)
			local half = base + math.sqrt(math.max(0, r * r - sk * sk))
			table.insert(strips, { Y0 = flat + sk, Y1 = flat + sn, A = half })
			table.insert(strips, { Y0 = -(flat + sn), Y1 = -(flat + sk), A = half })
		end
		return strips, t
	elseif shape.Kind == "Arch" then
		local t = insetFor(shape.CW, density)
		local r = shape.CW - t
		local yj = -shape.CH + 2 * shape.Hr -- jonction rectangle / arche
		local strips: { Strip } = { { Y0 = -shape.CH, Y1 = yj, A = shape.CW, JTop = true } }
		for k = 0, m - 1 do
			local sk = r * math.sqrt(k / m)
			local sn = r * math.sqrt((k + 1) / m)
			table.insert(strips, { Y0 = yj + sk, Y1 = yj + sn, A = math.sqrt(math.max(0, r * r - sk * sk)), JBottom = k == 0 })
		end
		return strips, t
	end
	return { { Y0 = -shape.CH, Y1 = shape.CH, A = shape.CW } }, 0
end

-- Caméra + cadre de la ViewportFrame pour une caméra à `camPos` (STRICT : la
-- vue couvre TOUTE la toile, sinon nil)
function Reflections.ComputeView(camPos: Vector3, plane: Plane, pps: number?, strips: number?, minPPS: number?): View?
	local rel = camPos - plane.Center
	local d = rel:Dot(plane.N)
	if d ~= d or d < MIN_DEPTH then
		return nil -- derrière le miroir, ou collé dessus
	end
	local cx, cy = rel:Dot(plane.U), rel:Dot(plane.V)
	local hx = math.abs(cx) + plane.HalfW
	local hy = math.abs(cy) + plane.HalfH
	if hx / d > MAX_HTAN then
		return nil -- trop de biais
	end
	hy = math.max(hy, hx / MAX_ASPECT)
	local fov = math.deg(2 * math.atan(hy / d))
	if fov > MAX_FOV then
		return nil -- trop près / trop haut : le champ ne couvrirait pas la glace
	end
	local count = math.max(1, strips or 1)
	local density = math.min(pps or BASE_PPS, MAX_CANVAS / (2 * hx), MAX_CANVAS / (2 * hy), math.sqrt(PIXEL_BUDGET / (count * 4 * hx * hy)))
	if density < math.max(MIN_PPS, minPPS or 0) then
		return nil -- trop peu de pixels : verre statique
	end
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

-- Où un point du MONDE RÉFLÉCHI apparaît sur la toile (pixels), d'après la
-- projection de la caméra de la ViewportFrame (champ vertical, rapport du cadre)
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

-- Repère du miroir : (u, v, n) -> monde (n > 0 = côté pièce)
local function frameAt(plane: Plane, u: number, v: number, n: number): CFrame
	local p = plane.Center + plane.U * u + plane.V * v + plane.N * n
	return CFrame.fromMatrix(p, plane.U, plane.V) -- X = U, Y = V, Z = U x V = N
end

-- Plaque opaque (forme exacte de la glace) + toile invisible de la SurfaceGui
-- (pures) -> (pièces { CFrame, Size, Shape }, CFrame de la toile, taille)
function Reflections.ScreenSpecs(plane: Plane, shape: Shape): ({ { CFrame: CFrame, Size: Vector3, Shape: string } }, CFrame, Vector3)
	local cp = Reflections.CanvasPlane(plane, shape)
	local n0 = SCREEN_GAP + SCREEN_T / 2
	local specs = {}
	local function block(u: number, v: number, w: number, h: number, depth: number)
		table.insert(specs, { CFrame = frameAt(cp, u, v, n0 - depth), Size = Vector3.new(w, h, SCREEN_T), Shape = "Block" })
	end
	local function disc(u: number, v: number, diameter: number, depth: number)
		-- cylindre : axe X le long de la normale (face Right/Left = disque)
		local p = cp.Center + cp.U * u + cp.V * v + cp.N * (n0 - depth)
		table.insert(specs, { CFrame = CFrame.fromMatrix(p, cp.N, cp.V), Size = Vector3.new(SCREEN_T, diameter, diameter), Shape = "Cylinder" })
	end
	if shape.Kind == "Oval" then
		local r = math.min(shape.CW, shape.CH)
		if shape.CW - r > 1e-3 then
			block(0, 0, 2 * (shape.CW - r), 2 * shape.CH, 0)
			disc(-(shape.CW - r), 0, 2 * r, 0.004)
			disc(shape.CW - r, 0, 2 * r, 0.006)
		elseif shape.CH - r > 1e-3 then
			block(0, 0, 2 * shape.CW, 2 * (shape.CH - r), 0)
			disc(0, -(shape.CH - r), 2 * r, 0.004)
			disc(0, shape.CH - r, 2 * r, 0.006)
		else
			disc(0, 0, 2 * r, 0)
		end
	elseif shape.Kind == "Arch" then
		block(0, -shape.CH + shape.Hr, 2 * shape.CW, 2 * shape.Hr, 0)
		disc(0, -shape.CH + 2 * shape.Hr, 2 * shape.CW, 0.004)
	else
		block(0, 0, 2 * shape.CW, 2 * shape.CH, 0)
	end
	-- toile : bloc invisible juste devant, face Front = normale, axe X de la
	-- toile = U (RightVector = -U)
	local cpos = cp.Center + cp.N * (SCREEN_GAP + SCREEN_T + CANVAS_GAP)
	local canvasCF = CFrame.fromMatrix(cpos, -cp.U, cp.V, -cp.N)
	return specs, canvasCF, Vector3.new(2 * shape.CW, 2 * shape.CH, 0.01)
end

export type Room = {
	Left: number, -- distances depuis le centre de la toile (studs)
	Right: number,
	Floor: number,
	Ceiling: number,
	Depth: number, -- jusqu'au mur d'en face
	Wall: Color3,
	SideL: Color3,
	SideR: Color3,
	FloorColor: Color3,
	FloorMaterial: Enum.Material,
	CeilingColor: Color3,
}

local function darken(c: Color3, k: number): Color3
	return Color3.new(c.R * (1 - k), c.G * (1 - k), c.B * (1 - k))
end

local function lighten(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

--[[
	Décor du reflet (pur) : la pièce RÉFLÉCHIE, boîte fermée derrière le plan
	(n ≤ 0) : sol, plafond, murs gauche / droit, mur d'en face (= le mur
	derrière le joueur), plinthes, corniche, plafonnier. Dalles de 0,2 stud
	posées DEHORS (leurs faces intérieures = les faces de la boîte) et
	arrêtées à 0,002 stud du plan. -> { { CFrame, Size, Color, Material, Name } }
]]
function Reflections.BackdropSpecs(cp: Plane, room: Room): { { CFrame: CFrame, Size: Vector3, Color: Color3, Material: Enum.Material, Name: string } }
	local t = 0.2
	local L, R = math.max(room.Left, cp.HalfW + 0.3), math.max(room.Right, cp.HalfW + 0.3)
	local F, C = math.max(room.Floor, cp.HalfH + 0.3), math.max(room.Ceiling, cp.HalfH + 0.3)
	local D = math.max(room.Depth, 1)
	local E = 0.002 -- arrêt avant le plan
	local specs = {}
	local function slab(name: string, u0: number, u1: number, v0: number, v1: number, n0: number, n1: number, color: Color3, material: Enum.Material?)
		table.insert(specs, {
			CFrame = frameAt(cp, (u0 + u1) / 2, (v0 + v1) / 2, (n0 + n1) / 2),
			Size = Vector3.new(u1 - u0, v1 - v0, n1 - n0),
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Name = name,
		})
	end
	local back = -D
	-- (n de -D - t à -E)
	slab("Floor", -L - t, R + t, -F - t, -F, back - t, -E, room.FloorColor, room.FloorMaterial)
	slab("Ceiling", -L - t, R + t, C, C + t, back - t, -E, room.CeilingColor)
	slab("WallLeft", -L - t, -L, -F, C, back - t, -E, room.SideL)
	slab("WallRight", R, R + t, -F, C, back - t, -E, room.SideR)
	slab("WallFar", -L, R, -F, C, back - t, back, room.Wall)
	-- plinthes (dans la boîte, adossées aux murs)
	local hb = math.clamp((F + C) * 0.045, 0.25, 0.7)
	local tb = 0.08
	local trim = lighten(room.Wall, 0.55)
	slab("BaseLeft", -L, -L + tb, -F, -F + hb, back, -E, trim)
	slab("BaseRight", R - tb, R, -F, -F + hb, back, -E, trim)
	slab("BaseFar", -L + tb, R - tb, -F, -F + hb, back, back + tb, trim)
	-- corniche
	local hc = hb * 0.6
	slab("CrownLeft", -L, -L + tb, C - hc, C, back, -E, lighten(room.CeilingColor, 0.3))
	slab("CrownRight", R - tb, R, C - hc, C, back, -E, lighten(room.CeilingColor, 0.3))
	slab("CrownFar", -L + tb, R - tb, C - hc, C, back, back + tb, lighten(room.CeilingColor, 0.3))
	-- plafonnier (disque clair au milieu du plafond)
	local lamp = math.clamp(math.min(L + R, D) * 0.12, 0.6, 2.2)
	local mid = (R - L) / 2
	slab("Lamp", mid - lamp / 2, mid + lamp / 2, C - 0.12, C, back / 2 - lamp / 2, back / 2 + lamp / 2, Color3.fromRGB(255, 246, 222), Enum.Material.Neon)
	return specs
end

----------------------------------------------------------------------
-- Registre (miroirs, écrans, sols) : DescendantAdded filtré par nom
----------------------------------------------------------------------

type CharCopy = { Model: Model, Version: number, Count: number, Pairs: { { Src: BasePart, Dst: BasePart, Base: number } }, Built: number }

type StripObj = {
	Spec: Strip,
	Clip: Frame,
	Viewport: ViewportFrame,
	Camera: Camera,
	World: WorldModel,
	Backdrop: Model,
	Chars: { [Model]: CharCopy },
	Px: Vector2, -- coin haut-gauche (pixels de la toile)
}

type Display = {
	Part: BasePart,
	Plane: Plane,
	Canvas: Plane,
	Shape: Shape,
	Live: boolean,
	Screen: Folder,
	CanvasPart: BasePart,
	Gui: SurfaceGui,
	Root: Frame,
	Glass: Frame,
	GlassGradient: UIGradient,
	Strips: { StripObj },
	StripsFrame: Frame,
	Sheen: Frame,
	SheenGradient: UIGradient,
	Bevel: UIStroke?,
	Inset: number,
	MinPPS: number,
	Room: Room?,
	RoomAt: number,
	PPS: number,
	View: View?,
	Shown: boolean,
}

local owners: { [string]: boolean } = {}
local active = false
local mirrors: { [BasePart]: boolean } = {}
local screens: { [BasePart]: boolean } = {}
local floors: { [BasePart]: boolean } = {}
local floorSaved: { [BasePart]: number } = {}
local sheens: { [BasePart]: { Gui: SurfaceGui, Gradient: UIGradient } } = {}
local displays: { [BasePart]: Display } = {}
local addedConn: RBXScriptConnection? = nil
local qualityConn: any = nil
local selectClock = 0
local frameClock = 0
local glossClock = 0
local glossOn = false
local floorsDirty = false
local charVersion: { [Model]: number } = {}
local charConns: { [Model]: { RBXScriptConnection } } = {}
local lastCount = 0

-- SurfaceGui dans le PlayerGui (Adornee = la toile) ; jamais remise à zéro
-- à la réapparition du personnage (ResetOnSpawn = false)
local function guiParent(fallback: Instance): Instance
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	return playerGui or fallback
end

local function quiet(gui: LayerCollector)
	pcall(function()
		(gui :: any).ResetOnSpawn = false
	end)
end

local screenFolder: Instance? = nil
local function screenParent(): Instance
	local cam = workspace.CurrentCamera
	local folder = screenFolder
	if folder and folder.Parent ~= nil and folder.Parent == (cam or workspace) then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "DopamineMirrorScreens"
	f.Parent = cam or workspace
	screenFolder = f
	return f
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
		-- (coque "RoomShell" ; renommée "Room_<n>" par HouseBuilder en ville)
		if parent and (parent.Name == "RoomShell" or string.match(parent.Name, "^Room_%d+$") ~= nil) then
			floors[d] = true
			floorsDirty = true
		end
	end
end

local function scanAll()
	for _, d in ipairs(workspace:GetDescendants()) do
		consider(d)
	end
end

----------------------------------------------------------------------
-- Forme réelle d'un miroir (arche détectée : cylindre de verre sur le haut)
----------------------------------------------------------------------

local function kindOf(part: BasePart, plane: Plane): string
	local shape = part:GetAttribute("MirrorShape")
	-- (arche : le rectangle doit être au moins aussi haut que le rayon de
	-- l'arche, sinon le disque de la plaque opaque dépasserait en bas)
	local archOk = 2 * plane.HalfH >= plane.HalfW
	if shape == "Oval" then
		return shape
	elseif shape == "Arch" then
		return archOk and "Arch" or "Rect"
	end
	if not archOk then
		return "Rect"
	end
	local parent = part.Parent
	if parent then
		local top = plane.Center + plane.V * plane.HalfH
		for _, sibling in ipairs(parent:GetChildren()) do
			if sibling ~= part and sibling:IsA("Part") and sibling.Shape == Enum.PartType.Cylinder
				and (sibling.Material == Enum.Material.Glass or sibling.Reflectance >= 0.3) then
				local axis = sibling.CFrame.RightVector
				local diameter = math.min(sibling.Size.Y, sibling.Size.Z)
				local off = sibling.Position - top
				local inPlane = Vector2.new(off:Dot(plane.U), off:Dot(plane.V))
				if math.abs(axis:Dot(plane.N)) > 0.98 and math.abs(diameter - 2 * plane.HalfW) <= 0.12 * plane.HalfW
					and inPlane.Magnitude <= 0.15 * plane.HalfW and math.abs(off:Dot(plane.N)) <= 0.5 then
					return "Arch"
				end
			end
		end
	end
	return "Rect"
end

----------------------------------------------------------------------
-- Mesure de la pièce (5 lancers de rayon, surfaces assez grandes seulement)
----------------------------------------------------------------------

local function characterOf(inst: Instance): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and inst:IsDescendantOf(character) then
			return true
		end
	end
	return false
end

local function secondLargest(size: Vector3): number
	local a, b, c = size.X, size.Y, size.Z
	if a < b then
		a, b = b, a
	end
	if b < c then
		b = c
	end
	if a < b then
		b = a
	end
	return b
end

local function measureRoom(part: BasePart, cp: Plane): Room
	local origin = cp.Center + cp.N * 0.4
	local exclude: { Instance } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	if part.Parent then
		table.insert(exclude, part.Parent)
	end
	local sf = screenFolder
	if sf then
		table.insert(exclude, sf)
	end
	local weather = workspace:FindFirstChild("DopamineWeather")
	if weather then
		table.insert(exclude, weather)
	end
	local minSize = math.clamp(2 * math.max(cp.HalfW, cp.HalfH), 3, 6)
	local function cast(dir: Vector3, maxDist: number, facing: number): RaycastResult?
		local list = table.clone(exclude)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		for _ = 1, 10 do
			params.FilterDescendantsInstances = list
			local ok, hit = pcall(function()
				return workspace:Raycast(origin, dir * maxDist, params)
			end)
			if not ok or not hit then
				return nil
			end
			local inst = hit.Instance
			local good = inst:IsA("Terrain") and facing > 0.5
			if not good and inst:IsA("BasePart") and inst.Transparency < 0.35 and not characterOf(inst) then
				good = secondLargest(inst.Size) >= minSize and hit.Normal:Dot(-dir) >= facing
			end
			if good then
				return hit
			end
			table.insert(list, inst)
		end
		return nil
	end
	local function colorOf(hit: RaycastResult?, default: Color3): Color3
		if hit and hit.Instance:IsA("BasePart") and not hit.Instance:IsA("Terrain") then
			return (hit.Instance :: BasePart).Color
		end
		if hit and hit.Instance:IsA("Terrain") then
			return Color3.fromRGB(110, 150, 90)
		end
		return default
	end
	local far = cast(cp.N, 80, 0.6)
	local left = cast(-cp.U, 50, 0.6)
	local right = cast(cp.U, 50, 0.6)
	local down = cast(-cp.V, 40, 0.7)
	local up = cast(cp.V, 50, 0.7)
	local floorDist = down and down.Distance or cp.HalfH + 2.5
	local floorMat = Enum.Material.SmoothPlastic
	if down and down.Instance:IsA("BasePart") and not down.Instance:IsA("Terrain") then
		local mat = (down.Instance :: BasePart).Material
		if mat == Enum.Material.Wood or mat == Enum.Material.WoodPlanks or mat == Enum.Material.Marble or mat == Enum.Material.Fabric
			or mat == Enum.Material.Carpet or mat == Enum.Material.Slate or mat == Enum.Material.Granite then
			floorMat = mat
		end
	end
	local wall = colorOf(far, colorOf(left, colorOf(right, DEFAULT_WALL)))
	return {
		Left = math.clamp(left and left.Distance or 9, cp.HalfW + 0.3, 40),
		Right = math.clamp(right and right.Distance or 9, cp.HalfW + 0.3, 40),
		Floor = math.clamp(floorDist, cp.HalfH + 0.3, 30),
		Ceiling = math.clamp(up and up.Distance or math.max(cp.HalfH + 0.3, 13 - floorDist), cp.HalfH + 0.3, 40),
		Depth = math.clamp(far and (far.Distance + 0.4) or 22, 3, 80),
		Wall = wall,
		SideL = colorOf(left, wall),
		SideR = colorOf(right, wall),
		FloorColor = colorOf(down, DEFAULT_FLOOR),
		FloorMaterial = floorMat,
		CeilingColor = colorOf(up, DEFAULT_CEILING),
	}
end

local function sameRoom(a: Room?, b: Room): boolean
	if not a then
		return false
	end
	local function close(x: number, y: number): boolean
		return math.abs(x - y) < 0.25
	end
	return close(a.Left, b.Left) and close(a.Right, b.Right) and close(a.Floor, b.Floor) and close(a.Ceiling, b.Ceiling)
		and close(a.Depth, b.Depth) and a.Wall == b.Wall and a.FloorColor == b.FloorColor and a.CeilingColor == b.CeilingColor
		and a.SideL == b.SideL and a.SideR == b.SideR
end

----------------------------------------------------------------------
-- Copies des personnages (pièce par pièce, table source -> copie)
----------------------------------------------------------------------

local KEEP_CHILD: { [string]: boolean } = {
	SpecialMesh = true,
	BlockMesh = true,
	CylinderMesh = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
}
local KEEP_TOP: { [string]: boolean } = {
	Shirt = true,
	Pants = true,
	ShirtGraphic = true,
	BodyColors = true,
	CharacterMesh = true,
}

local function watchCharacter(model: Model)
	if charConns[model] then
		return
	end
	charVersion[model] = charVersion[model] or 1
	local function bump()
		charVersion[model] = (charVersion[model] or 1) + 1
	end
	charConns[model] = {
		model.DescendantAdded:Connect(bump),
		model.DescendantRemoving:Connect(bump),
		model.AncestryChanged:Connect(function()
			if model.Parent == nil then
				local conns = charConns[model]
				if conns then
					for _, c in ipairs(conns) do
						c:Disconnect()
					end
				end
				charConns[model] = nil
				charVersion[model] = nil
			end
		end),
	}
end

local function unwatchAll()
	for _, conns in pairs(charConns) do
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end
	table.clear(charConns)
	table.clear(charVersion)
end

local function clonePart(part: BasePart): BasePart?
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

-- Une pièce de la source est-elle visible dans le reflet ? (centre devant la glace)
local function inFront(src: BasePart, plane: Plane): boolean
	return (src.Position - plane.Center):Dot(plane.N) > 0.05
end

local function buildCopy(source: Model, world: WorldModel, plane: Plane): CharCopy
	local model = Instance.new("Model")
	model.Name = "Reflet"
	local copy: CharCopy = { Model = model, Version = charVersion[source] or 1, Count = #source:GetDescendants(), Pairs = {}, Built = os.clock() }
	pcall(function()
		local hum = Instance.new("Humanoid")
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.Parent = model
	end)
	for _, child in ipairs(source:GetChildren()) do
		if KEEP_TOP[child.ClassName] then
			local ok, c = pcall(function()
				return child:Clone()
			end)
			if ok and c then
				c.Parent = model
			end
		end
	end
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.98 then
			local size = d.Size
			if math.max(size.X, size.Y, size.Z) <= 14 then
				local c = clonePart(d)
				if c then
					-- placée réfléchie AVANT d'entrer dans le monde du reflet
					c.CFrame = Reflections.ReflectCFrame(d.CFrame, plane.Center, plane.N)
					if not inFront(d, plane) then
						c.Transparency = 1
					end
					c.Parent = model
					table.insert(copy.Pairs, { Src = d, Dst = c, Base = d.Transparency })
				end
			end
		end
	end
	model.Parent = world
	return copy
end

local function moveCopy(copy: CharCopy, plane: Plane, parts: { BasePart }, cframes: { CFrame })
	for _, p in ipairs(copy.Pairs) do
		local src, dst = p.Src, p.Dst
		if src.Parent then
			table.insert(parts, dst)
			table.insert(cframes, Reflections.ReflectCFrame(src.CFrame, plane.Center, plane.N))
			local want = if inFront(src, plane) then src.Transparency else 1
			if dst.Transparency ~= want then
				dst.Transparency = want
			end
		elseif dst.Transparency ~= 1 then
			dst.Transparency = 1
		end
	end
end

-- Personnages à refléter devant ce miroir : le joueur + les plus proches
local function sourcesFor(plane: Plane, maxOthers: number): { Model }
	local list: { Model } = {}
	local others: { { Model: Model, Dist: number } } = {}
	local me = Players.LocalPlayer
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local rel = root.Position - plane.Center
			if rel.Magnitude <= CHAR_RANGE and rel:Dot(plane.N) > 0.3 then
				if player == me then
					table.insert(list, 1, character)
				else
					table.insert(others, { Model = character, Dist = rel.Magnitude })
				end
			end
		end
	end
	table.sort(others, function(a, b)
		return a.Dist < b.Dist
	end)
	for i = 1, math.min(maxOthers, #others) do
		table.insert(list, others[i].Model)
	end
	return list
end

----------------------------------------------------------------------
-- Affichage d'un miroir (plaque opaque + toile + SurfaceGui)
----------------------------------------------------------------------

local function newPart(class: string, name: string): BasePart
	local p = Instance.new(class) :: BasePart
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function glassColors(room: Room?): ColorSequence
	local wall = room and room.Wall or DEFAULT_WALL
	local ceiling = room and room.CeilingColor or DEFAULT_CEILING
	local floor = room and room.FloorColor or DEFAULT_FLOOR
	local tint = Color3.fromRGB(222, 232, 242)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighten(ceiling, 0.1):Lerp(tint, 0.35)),
		ColorSequenceKeypoint.new(0.2, lighten(wall, 0.12):Lerp(tint, 0.3)),
		ColorSequenceKeypoint.new(0.62, wall:Lerp(tint, 0.25)),
		ColorSequenceKeypoint.new(0.74, darken(floor, 0.05):Lerp(tint, 0.2)),
		ColorSequenceKeypoint.new(1, darken(floor, 0.15):Lerp(tint, 0.2)),
	})
end

local function screenColor(room: Room?): Color3
	local wall = room and room.Wall or DEFAULT_WALL
	return wall:Lerp(Color3.fromRGB(222, 232, 242), 0.3)
end

-- Éclairage des ViewportFrames (pas d'ombres ni de lampes : ambiance douce du lieu)
local function lightStrip(s: StripObj, plane: Plane)
	local clock = Lighting.ClockTime
	local night = clock < 6.3 or clock > 18.7
	local k = night and 0.82 or 1
	s.Viewport.Ambient = Color3.new(0.6 * k, 0.6 * k, 0.62 * k)
	s.Viewport.LightColor = Color3.new(0.5 * k, 0.49 * k, 0.46 * k)
	-- du plafond vers le sol, un peu vers le mur d'en face (réfléchi)
	s.Viewport.LightDirection = (-plane.V * 1 - plane.N * 0.35 + plane.U * 0.2).Unit
end

local function buildBackdrop(s: StripObj, cp: Plane, room: Room)
	s.Backdrop:ClearAllChildren()
	for _, spec in ipairs(Reflections.BackdropSpecs(cp, room)) do
		local p = newPart("Part", spec.Name)
		p.Size = spec.Size
		p.CFrame = spec.CFrame
		p.Color = spec.Color
		p.Material = spec.Material
		p.Parent = s.Backdrop
	end
end

local function placeStrips(disp: Display)
	local pps = disp.PPS
	local shape = disp.Shape
	local canvasH = 2 * shape.CH * pps
	for _, s in ipairs(disp.Strips) do
		local spec = s.Spec
		local x0 = math.floor((shape.CW - spec.A) * pps)
		local x1 = math.ceil((shape.CW + spec.A) * pps)
		-- (bords horizontaux arrondis au plus près : deux bandes voisines ont
		-- EXACTEMENT le même bord -> ni fente ni recouvrement)
		local y0 = math.floor((shape.CH - spec.Y1) * pps + 0.5)
		local y1 = math.floor((shape.CH - spec.Y0) * pps + 0.5)
		if spec.JTop then
			y0 = math.ceil((shape.CH - spec.Y1) * pps)
		end
		if spec.JBottom then
			y1 = math.ceil((shape.CH - spec.Y0) * pps)
		end
		if #disp.Strips == 1 then
			y0, y1 = 0, math.ceil(canvasH)
		end
		s.Px = Vector2.new(x0, y0)
		s.Clip.Position = UDim2.fromOffset(x0, y0)
		s.Clip.Size = UDim2.fromOffset(math.max(1, x1 - x0), math.max(1, y1 - y0))
	end
	if disp.Bevel then
		disp.Bevel.Thickness = math.max(1, disp.Inset * pps)
	end
end

local function destroyDisplay(disp: Display)
	pcall(disp.Gui.Destroy, disp.Gui)
	pcall(disp.Screen.Destroy, disp.Screen)
	pcall(disp.CanvasPart.Destroy, disp.CanvasPart)
	displays[disp.Part] = nil
end

local function newStrip(spec: Strip, parent: Instance, index: number): StripObj
	local clip = Instance.new("Frame")
	clip.Name = "Strip" .. index
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.ZIndex = 2
	clip.Parent = parent
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Reflection"
	viewport.BackgroundColor3 = DEFAULT_WALL
	viewport.BackgroundTransparency = 0 -- (opaque : jamais de trou)
	viewport.BorderSizePixel = 0
	viewport.ZIndex = 2
	viewport.ImageColor3 = Color3.fromRGB(238, 243, 248) -- verre légèrement froid
	viewport.Parent = clip
	local camera = Instance.new("Camera")
	camera.Name = "MirrorCamera"
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local world = Instance.new("WorldModel")
	world.Name = "World"
	world.Parent = viewport
	local backdrop = Instance.new("Model")
	backdrop.Name = "Room"
	backdrop.Parent = world
	return { Spec = spec, Clip = clip, Viewport = viewport, Camera = camera, World = world, Backdrop = backdrop, Chars = {}, Px = Vector2.zero }
end

local function newDisplay(part: BasePart, plane: Plane, live: boolean): Display
	local kind = kindOf(part, plane)
	local shape = Reflections.ShapeOf(kind, plane.HalfW, plane.HalfH)
	local cp = Reflections.CanvasPlane(plane, shape)
	local room = measureRoom(part, cp)
	-- plaque opaque (forme exacte) + toile
	local folder = Instance.new("Folder")
	folder.Name = "MirrorScreen"
	local specs, canvasCF, canvasSize = Reflections.ScreenSpecs(plane, shape)
	for i, spec in ipairs(specs) do
		local p = newPart("Part", "Screen" .. i) :: Part
		if spec.Shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Size = spec.Size
		p.CFrame = spec.CFrame
		p.Color = screenColor(room)
		p:SetAttribute("MirrorScreen", true)
		p.Parent = folder
	end
	folder.Parent = screenParent()
	local canvas = newPart("Part", "MirrorCanvas")
	canvas.Size = canvasSize
	canvas.CFrame = canvasCF
	canvas.Transparency = 1
	canvas:SetAttribute("MirrorScreen", true)
	canvas.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DopamineMirror"
	quiet(gui)
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BASE_PPS
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.MaxDistance = LIVE_RANGE + 20
	gui.ZOffset = 0
	pcall(function()
		(gui :: any).ClipsDescendants = true
	end)
	gui.Adornee = canvas
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = gui
	-- forme de la glace en échelle de la toile (Scale : indépendant de la densité)
	local function shaped(name: string, z: number, insetStuds: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.ZIndex = z
		f.BackgroundTransparency = 1
		f.Parent = root
		local a = (shape.CW - insetStuds) / shape.CW
		if kind == "Oval" then
			local b = (shape.CH - insetStuds) / shape.CH
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(0.5, 0.5)
			f.Size = UDim2.fromScale(a, b)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0) -- stade : rayon = moitié du petit côté
			corner.Parent = f
		elseif kind == "Arch" then
			-- rectangle du bas seulement (l'arche a son propre disque)
			f.AnchorPoint = Vector2.new(0.5, 1)
			f.Position = UDim2.fromScale(0.5, 1)
			f.Size = UDim2.fromScale(1, (2 * shape.Hr) / (2 * shape.CH))
		else
			f.Size = UDim2.fromScale(1, 1)
		end
		return f
	end
	local glass = shaped("Glass", 1, 0)
	glass.BackgroundTransparency = 0
	glass.BackgroundColor3 = Color3.new(1, 1, 1)
	local glassGradient = Instance.new("UIGradient")
	glassGradient.Rotation = 90
	glassGradient.Color = glassColors(room)
	glassGradient.Parent = glass
	if kind == "Arch" then
		-- demi-disque de l'arche (cadre coupé à la jonction)
		local top = Instance.new("Frame")
		top.Name = "ArchClip"
		top.BackgroundTransparency = 1
		top.BorderSizePixel = 0
		top.ClipsDescendants = true
		top.Size = UDim2.fromScale(1, (shape.CW) / (2 * shape.CH))
		top.ZIndex = 1
		top.Parent = root
		local disc = Instance.new("Frame")
		disc.Name = "ArchGlass"
		disc.BorderSizePixel = 0
		disc.BackgroundColor3 = Color3.new(1, 1, 1)
		disc.Size = UDim2.fromScale(1, 2)
		disc.ZIndex = 1
		disc.Parent = top
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		local g2 = glassGradient:Clone()
		g2.Parent = disc
	end
	local stripsFrame = Instance.new("Frame")
	stripsFrame.Name = "Strips"
	stripsFrame.Size = UDim2.fromScale(1, 1)
	stripsFrame.BackgroundTransparency = 1
	stripsFrame.BorderSizePixel = 0
	stripsFrame.ZIndex = 2
	stripsFrame.Visible = false
	stripsFrame.Parent = root
	local minPPS = Reflections.MinPPS(shape)
	local stripSpecs, inset = Reflections.Strips(shape, minPPS)
	local strips: { StripObj } = {}
	if live then
		for i, spec in ipairs(stripSpecs) do
			local s = newStrip(spec, stripsFrame, i)
			s.Viewport.BackgroundColor3 = room.Wall
			buildBackdrop(s, cp, room)
			lightStrip(s, cp)
			table.insert(strips, s)
		end
	end
	-- reflet de lumière (diagonale qui glisse)
	local sheen = shaped("Sheen", 4, inset)
	sheen.BackgroundTransparency = 0
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	local sheenGradient = Instance.new("UIGradient")
	sheenGradient.Rotation = 28
	sheenGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.34, 0.97),
		NumberSequenceKeypoint.new(0.45, 0.88),
		NumberSequenceKeypoint.new(0.5, 0.93),
		NumberSequenceKeypoint.new(0.58, 0.96),
		NumberSequenceKeypoint.new(1, 1),
	})
	sheenGradient.Parent = sheen
	-- biseau chromé (ovale : tout autour ; arche : sur l'arc)
	local bevel: UIStroke? = nil
	if kind == "Oval" or kind == "Arch" then
		local holder: Frame
		if kind == "Oval" then
			holder = shaped("Bevel", 5, inset)
		else
			local clipTop = Instance.new("Frame")
			clipTop.Name = "BevelClip"
			clipTop.BackgroundTransparency = 1
			clipTop.BorderSizePixel = 0
			clipTop.ClipsDescendants = true
			clipTop.ZIndex = 5
			clipTop.Size = UDim2.fromScale(1, (shape.CW) / (2 * shape.CH))
			clipTop.Parent = root
			holder = Instance.new("Frame")
			holder.Name = "Bevel"
			holder.BackgroundTransparency = 1
			holder.BorderSizePixel = 0
			holder.ZIndex = 5
			local r = (shape.CW - inset) / shape.CW
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Position = UDim2.fromScale(0.5, 1)
			holder.Size = UDim2.fromScale(r, 2 * r)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = holder
			holder.Parent = clipTop
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = math.max(1, inset * BASE_PPS)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		pcall(function()
			(stroke :: any).BorderStrokePosition = (Enum :: any).BorderStrokePosition.Outer
		end)
		local chrome = Instance.new("UIGradient")
		chrome.Rotation = 45
		chrome.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighten(BEVEL_COLOR, 0.5)),
			ColorSequenceKeypoint.new(0.35, BEVEL_COLOR),
			ColorSequenceKeypoint.new(0.6, darken(BEVEL_COLOR, 0.18)),
			ColorSequenceKeypoint.new(1, lighten(BEVEL_COLOR, 0.3)),
		})
		chrome.Parent = stroke
		stroke.Parent = holder
		bevel = stroke
	end
	gui.Parent = guiParent(canvas)
	local disp: Display = {
		Part = part,
		Plane = plane,
		Canvas = cp,
		Shape = shape,
		Live = live,
		Screen = folder,
		CanvasPart = canvas,
		Gui = gui,
		Root = root,
		Glass = glass,
		GlassGradient = glassGradient,
		Strips = strips,
		StripsFrame = stripsFrame,
		Sheen = sheen,
		SheenGradient = sheenGradient,
		Bevel = bevel,
		Inset = inset,
		MinPPS = minPPS,
		Room = room,
		RoomAt = os.clock(),
		PPS = BASE_PPS,
		View = nil,
		Shown = false,
	}
	gui.PixelsPerStud = disp.PPS
	placeStrips(disp)
	return disp
end

-- La forme / la place du miroir a changé ?
local function moved(a: Plane, b: Plane): boolean
	return (a.Center - b.Center).Magnitude > 0.01 or a.N:Dot(b.N) < 0.9999 or a.V:Dot(b.V) < 0.9999
		or math.abs(a.HalfW - b.HalfW) > 0.01 or math.abs(a.HalfH - b.HalfH) > 0.01
end

local function updateSheen(disp: Display, camPos: Vector3)
	local cp = disp.Canvas
	local toCam = camPos - cp.Center
	if toCam.Magnitude < 1e-3 then
		return
	end
	toCam = toCam.Unit
	local side = toCam:Dot(cp.U)
	local vertical = toCam:Dot(cp.V)
	disp.SheenGradient.Offset = Vector2.new(math.clamp(-side * 0.5, -0.5, 0.5), math.clamp(vertical * 0.3, -0.3, 0.3))
end

local function setLiveShown(disp: Display, shown: boolean)
	if disp.Shown ~= shown then
		disp.Shown = shown
		disp.StripsFrame.Visible = shown
	end
end

local function updateChars(disp: Display)
	local plane = disp.Plane
	local sources = sourcesFor(plane, if #disp.Strips > 1 then 1 else 3)
	local want: { [Model]: boolean } = {}
	for _, source in ipairs(sources) do
		want[source] = true
		watchCharacter(source)
	end
	local now = os.clock()
	-- (filet de sécurité si un DescendantAdded manque : nombre de descendants, 2 fois / s)
	local counts: { [Model]: number } = {}
	if now - lastCount > 0.5 then
		lastCount = now
		for _, source in ipairs(sources) do
			counts[source] = #source:GetDescendants()
		end
	end
	for _, s in ipairs(disp.Strips) do
		-- copies périmées / en trop
		for source, copy in pairs(s.Chars) do
			if not want[source] or not source:IsDescendantOf(workspace) then
				copy.Model:Destroy()
				s.Chars[source] = nil
			elseif now - copy.Built > 0.3 and (copy.Version ~= (charVersion[source] or 1) or (counts[source] ~= nil and counts[source] ~= copy.Count)) then
				-- (accessoire / outil ajouté ou retiré : copie refaite)
				copy.Model:Destroy()
				s.Chars[source] = nil
			end
		end
		local parts, cframes = {}, {}
		for _, source in ipairs(sources) do
			local copy = s.Chars[source]
			if not copy then
				copy = buildCopy(source, s.World, plane)
				s.Chars[source] = copy
			end
			moveCopy(copy, plane, parts, cframes)
		end
		if #parts > 0 then
			local ok = pcall(function()
				s.World:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			end)
			if not ok then
				for i, part in ipairs(parts) do
					part.CFrame = cframes[i]
				end
			end
		end
	end
end

local function updateDisplay(disp: Display, camCF: CFrame)
	local part = disp.Part
	local plane = Reflections.PlaneOf(part)
	if not plane or moved(plane, disp.Plane) then
		-- (le miroir a bougé / changé : tout est refait à la prochaine sélection)
		destroyDisplay(disp)
		return
	end
	if disp.Gui.Parent == nil or disp.Screen.Parent == nil then
		destroyDisplay(disp)
		return
	end
	updateSheen(disp, camCF.Position)
	-- pièce re-mesurée de temps en temps (murs repeints, pièce refaite)
	if os.clock() - disp.RoomAt > ROOM_EVERY then
		disp.RoomAt = os.clock()
		local room = measureRoom(part, disp.Canvas)
		if not sameRoom(disp.Room, room) then
			disp.Room = room
			disp.GlassGradient.Color = glassColors(room)
			for _, d in ipairs(disp.Screen:GetChildren()) do
				if d:IsA("BasePart") and d ~= disp.CanvasPart then
					d.Color = screenColor(room)
				end
			end
			for _, s in ipairs(disp.Strips) do
				s.Viewport.BackgroundColor3 = room.Wall
				buildBackdrop(s, disp.Canvas, room)
				lightStrip(s, disp.Canvas)
			end
		end
	end
	if not disp.Live or #disp.Strips == 0 then
		setLiveShown(disp, false)
		return
	end
	local view = Reflections.ComputeView(camCF.Position, disp.Canvas, BASE_PPS, #disp.Strips, disp.MinPPS)
	if not view then
		setLiveShown(disp, false)
		disp.View = nil
		return
	end
	-- densité de la toile par paliers (évite de tout remettre en page à chaque image)
	if math.abs(view.PPS - disp.PPS) / disp.PPS > 0.15 or view.PPS < disp.PPS - 1e-6 then
		disp.PPS = view.PPS
		disp.Gui.PixelsPerStud = view.PPS
		placeStrips(disp)
	end
	local fitted = Reflections.ComputeView(camCF.Position, disp.Canvas, disp.PPS, #disp.Strips, disp.MinPPS)
	if not fitted then
		setLiveShown(disp, false)
		disp.View = nil
		return
	end
	disp.View = fitted
	local fx, fy = math.floor(fitted.FramePos.X + 0.5), math.floor(fitted.FramePos.Y + 0.5)
	local fw, fh = math.max(1, math.floor(fitted.FrameSize.X + 0.5)), math.max(1, math.floor(fitted.FrameSize.Y + 0.5))
	for _, s in ipairs(disp.Strips) do
		s.Viewport.Position = UDim2.fromOffset(fx - s.Px.X, fy - s.Px.Y)
		s.Viewport.Size = UDim2.fromOffset(fw, fh)
		s.Camera.FieldOfView = fitted.FieldOfView
		s.Camera.CFrame = fitted.CameraCF
	end
	updateChars(disp)
	setLiveShown(disp, true)
end

----------------------------------------------------------------------
-- Sélection : miroirs vivants + miroirs "statiques" jolis
----------------------------------------------------------------------

-- Le miroir est-il visible (devant, à l'écran, pas derrière un mur) ?
local function visibleScore(part: BasePart, cam: Camera, range: number): number
	if not part:IsDescendantOf(workspace) then
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
	if d < 0.1 or dist > range then
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
	-- grand à l'écran = prioritaire
	return (plane.HalfW * plane.HalfH) * (d / dist) / (dist * dist + 1)
end

local function selectMirrors(cam: Camera)
	local q = GraphicsQuality.Get()
	local want: { { Part: BasePart, Score: number } } = {}
	for part in pairs(mirrors) do
		if not part:IsDescendantOf(workspace) then
			mirrors[part] = nil
		else
			local score = visibleScore(part, cam, math.max(LIVE_RANGE, STATIC_RANGE))
			if score > 0 then
				table.insert(want, { Part = part, Score = score })
			end
		end
	end
	table.sort(want, function(a, b)
		return a.Score > b.Score
	end)
	local mode: { [BasePart]: boolean } = {} -- true = vivant, false = statique
	local liveLeft = q.MaxMirrors
	local staticLeft = STATIC_MAX
	local camPos = cam.CFrame.Position
	for _, entry in ipairs(want) do
		local dist = (entry.Part.Position - camPos).Magnitude
		if liveLeft > 0 and dist <= LIVE_RANGE then
			liveLeft -= 1
			mode[entry.Part] = true
		elseif staticLeft > 0 and dist <= STATIC_RANGE then
			staticLeft -= 1
			mode[entry.Part] = false
		end
	end
	for part, disp in pairs(displays) do
		local m = mode[part]
		if m == nil or m ~= disp.Live then
			destroyDisplay(disp)
		end
	end
	for part, live in pairs(mode) do
		if not displays[part] then
			local plane = Reflections.PlaneOf(part)
			if plane then
				local ok, result = pcall(newDisplay, part, plane, live)
				if ok and result then
					displays[part] = result
				else
					warn("[Reflections] " .. tostring(result))
				end
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
			if not part:IsDescendantOf(workspace) then
				floors[part] = nil
			else
				local gloss = FLOOR_GLOSS[part.Material]
				if gloss then
					if floorSaved[part] == nil then
						floorSaved[part] = tonumber(part.Reflectance) or 0
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
	quiet(gui)
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
		if not part:IsDescendantOf(workspace) then
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
		if not keep[part] or sheens[part].Gui.Parent == nil then
			removeSheen(part)
		end
	end
	for part in pairs(keep) do
		if not sheens[part] then
			addSheen(part)
		end
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
	for _, disp in pairs(displays) do
		if not disp.Part:IsDescendantOf(workspace) then
			destroyDisplay(disp)
		else
			local ok, err = pcall(updateDisplay, disp, camCF)
			if not ok then
				warn("[Reflections] " .. tostring(err))
				-- (jamais un reflet à moitié à jour : on cache la couche vivante)
				pcall(setLiveShown, disp, false)
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
	for _, disp in pairs(displays) do
		destroyDisplay(disp)
	end
	for part in pairs(sheens) do
		removeSheen(part)
	end
	setFloors(false)
	glossOn = false
	unwatchAll()
	if screenFolder then
		pcall(screenFolder.Destroy, screenFolder)
		screenFolder = nil
	end
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

-- (tests / rendus) miroirs affichés
function Reflections.Live(): { any }
	local list = {}
	for _, disp in pairs(displays) do
		table.insert(list, disp)
	end
	return list
end

-- (tests / rendus) une passe complète tout de suite (sélection + images)
function Reflections.ForceStep()
	selectClock, frameClock, glossClock = SELECT_EVERY, FRAME_RATE, GLOSS_EVERY
	step(0)
end

-- (tests) relit tout le Workspace (miroirs ajoutés sans DescendantAdded)
function Reflections.Rescan()
	if active then
		scanAll()
	end
end

-- (tests) compteurs
function Reflections.Counts(): { [string]: number }
	local n = { Mirrors = 0, Screens = 0, Floors = 0, Live = 0, Static = 0, Sheens = 0, FloorsGlossy = 0, Strips = 0, Copies = 0 }
	for _ in pairs(mirrors) do
		n.Mirrors += 1
	end
	for _ in pairs(screens) do
		n.Screens += 1
	end
	for _ in pairs(floors) do
		n.Floors += 1
	end
	for _, disp in pairs(displays) do
		if disp.Live then
			n.Live += 1
		else
			n.Static += 1
		end
		n.Strips += #disp.Strips
		for _, s in ipairs(disp.Strips) do
			for _ in pairs(s.Chars) do
				n.Copies += 1
			end
		end
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
