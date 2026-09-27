--[[
	TownKit (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownKit

	🧱 Boîte à outils du décor de Dopamine Town (v9.4), partagée par
	TownStreets / TownPlaza / TownBuildings / TownEntrance / TownNature :
	  - fabrique de pièces avec des PROFILS de performance :
	      "solid" : on marche dessus / on s'y cogne (sol, murs, troncs) ;
	      "prop"  : petit objet solide, sans ombre ni requête ;
	      "deco"  : décor pur (CanCollide / CanQuery / CanTouch false, sans
	                ombre) : feuillages, lignes de la route, fenêtres... ;
	      "decoS" : décor pur qui garde son ombre (gros volumes) ;
	  - disques, boules, cylindres debout, poutres entre deux points ;
	  - compteur de pièces et BUDGET de vraies lumières (≤ 16 pour la ville) ;
	  - panneaux SurfaceGui (texte clé "LocText" : le client peut traduire) ;
	  - petits objets de rue réutilisés partout (arbres, lampadaires, bancs,
	    poubelles, bornes, jardinières, voitures...).
	Tout est ancré, construit UNE fois au démarrage du serveur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)

local TownKit = {}

local M = Enum.Material
TownKit.M = M

TownKit.MAX_LIGHTS = 16

-- Palette "kawaii réaliste" : matières réelles, teintes douces
TownKit.C = {
	White = Color3.fromRGB(255, 255, 255),
	Cream = Color3.fromRGB(252, 246, 236),
	Grass = Color3.fromRGB(128, 196, 112),
	GrassDark = Color3.fromRGB(104, 172, 96),
	Lawn = Color3.fromRGB(140, 206, 118),
	Asphalt = Color3.fromRGB(78, 80, 92),
	AsphaltDark = Color3.fromRGB(64, 66, 78),
	Walk = Color3.fromRGB(216, 210, 204),
	Curb = Color3.fromRGB(238, 236, 232),
	Line = Color3.fromRGB(250, 250, 246),
	Yellow = Color3.fromRGB(255, 208, 72),
	Paving = Color3.fromRGB(240, 222, 212),
	PavingRose = Color3.fromRGB(226, 170, 178),
	PavingLilac = Color3.fromRGB(200, 186, 226),
	Stone = Color3.fromRGB(226, 220, 212),
	StoneDark = Color3.fromRGB(170, 162, 156),
	Wood = Color3.fromRGB(176, 124, 84),
	WoodLight = Color3.fromRGB(214, 168, 122),
	Bark = Color3.fromRGB(122, 88, 64),
	Metal = Color3.fromRGB(62, 58, 76),
	MetalLight = Color3.fromRGB(150, 150, 164),
	Glass = Color3.fromRGB(168, 214, 240),
	GlassDark = Color3.fromRGB(96, 136, 170),
	Water = Color3.fromRGB(96, 186, 236),
	WaterDeep = Color3.fromRGB(58, 132, 190),
	Sand = Color3.fromRGB(236, 214, 170),
	Pink = Color3.fromRGB(255, 132, 184),
	HotPink = Color3.fromRGB(236, 72, 140),
	Lilac = Color3.fromRGB(186, 150, 246),
	Mint = Color3.fromRGB(128, 222, 190),
	Sky = Color3.fromRGB(126, 196, 255),
	Peach = Color3.fromRGB(255, 190, 150),
	Lemon = Color3.fromRGB(255, 228, 120),
	Glow = Color3.fromRGB(255, 232, 180),
	Ink = Color3.fromRGB(92, 58, 96),
	Plum = Color3.fromRGB(120, 90, 160),
}
local C = TownKit.C

TownKit.FOLIAGE = {
	Color3.fromRGB(96, 170, 92),
	Color3.fromRGB(116, 186, 98),
	Color3.fromRGB(84, 150, 88),
	Color3.fromRGB(255, 182, 206), -- cerisier
	Color3.fromRGB(140, 196, 110),
}
TownKit.FLOWERS = {
	Color3.fromRGB(255, 110, 160),
	Color3.fromRGB(255, 214, 96),
	Color3.fromRGB(186, 140, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 150, 110),
}

----------------------------------------------------------------------
-- Compteurs (pour le budget : pièces, vraies lumières)
----------------------------------------------------------------------

local stats = { Parts = 0, Lights = 0 }
TownKit.Stats = stats

function TownKit.Reset()
	stats.Parts = 0
	stats.Lights = 0
end

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

export type Profile = string -- "solid" | "prop" | "deco" | "decoS"

local function applyProfile(p: BasePart, profile: Profile?)
	if profile == "deco" then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	elseif profile == "decoS" then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	elseif profile == "prop" then
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
	elseif profile == "ghost" then
		-- (mur invisible : bloque sans être vu ni visé)
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
	else
		p.CanTouch = false
	end
end

-- Pièce ancrée ; `className` : "Part" (défaut), "WedgePart", "Seat"...
function TownKit.Part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, profile: Profile?, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	applyProfile(p, profile)
	p.Parent = parent
	stats.Parts += 1
	return p
end
local part = TownKit.Part

function TownKit.Wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, profile: Profile?): BasePart
	return part(parent, name, size, cframe, color, material, profile, "WedgePart")
end

-- Disque plat (cylindre couché), dessus à la hauteur `topY` du point `center`
function TownKit.Disc(parent: Instance, name: string, center: Vector3, radius: number, thickness: number, color: Color3, material: Enum.Material?, profile: Profile?): BasePart
	local p = part(parent, name, Vector3.new(thickness, radius * 2, radius * 2), CFrame.new(center - Vector3.new(0, thickness / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, profile)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

function TownKit.Ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material?, profile: Profile?): BasePart
	local p = part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(center), color, material, profile or "deco")
	;(p :: Part).Shape = Enum.PartType.Ball
	return p
end

-- Boule aplatie / étirée (bloc arrondi = cylindre couché court) : pour les
-- feuillages en couches on garde de vraies boules (plus jolies en jeu)
function TownKit.Column(parent: Instance, name: string, bottom: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, profile: Profile?): BasePart
	local p = part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, profile)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Poutre (bloc) entre deux points, section w x h (h vertical quand c'est possible)
function TownKit.Beam(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3, material: Enum.Material?, profile: Profile?): BasePart
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf
	if math.abs((b - a).Unit.Y) > 0.98 then
		cf = CFrame.new(mid) * CFrame.Angles(math.rad(90), 0, 0)
	else
		cf = CFrame.lookAt(mid, b)
	end
	return part(parent, name, Vector3.new(w, h, len), cf, color, material, profile)
end

-- Tige cylindrique entre deux points
function TownKit.Rod(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?, profile: Profile?): BasePart
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
	local p = part(parent, name, Vector3.new(len, diameter, diameter), cf, color, material, profile or "deco")
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

function TownKit.Model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

----------------------------------------------------------------------
-- Lumières (budget global)
----------------------------------------------------------------------

function TownKit.Light(host: BasePart, color: Color3, range: number, brightness: number, kind: string?): Light?
	if stats.Lights >= TownKit.MAX_LIGHTS then
		return nil
	end
	stats.Lights += 1
	local light: Light
	if kind == "Spot" then
		local spot = Instance.new("SpotLight")
		spot.Angle = 70
		spot.Face = Enum.NormalId.Bottom
		spot.Range = range
		light = spot
	else
		local point = Instance.new("PointLight")
		point.Range = range
		light = point
	end
	light.Color = color
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = host
	return light
end

----------------------------------------------------------------------
-- Panneaux (SurfaceGui)
----------------------------------------------------------------------

function TownKit.Surface(board: BasePart, face: Enum.NormalId, pixelsPerStud: number, background: Color3?, maxDistance: number?, lightInfluence: number?): (SurfaceGui, Frame)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = lightInfluence or 0.2
	gui.MaxDistance = maxDistance or 400
	gui.Parent = board
	local frame = Instance.new("Frame")
	frame.Name = "Body"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = background or C.White
	frame.BackgroundTransparency = background and 0 or 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	return gui, frame
end

-- Texte (clé anglaise en attribut "LocText" : le client la traduit)
function TownKit.Label(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font?, localize: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(x, y)
	l.Size = UDim2.fromScale(w, h)
	l.Font = font or Enum.Font.GothamBold
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	if localize then
		l:SetAttribute("LocText", text)
	end
	l.Parent = parent
	return l
end

function TownKit.Corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

function TownKit.Gradient(parent: Instance, a: Color3, b: Color3, rotation: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation
	g.Parent = parent
end

function TownKit.Stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

----------------------------------------------------------------------
-- Objets de rue
----------------------------------------------------------------------

-- Angle (autour de Y) qui tourne l'axe X local vers `dir` (bras des lampadaires...)
function TownKit.Facing(dir: Vector3): number
	return math.atan2(-dir.Z, dir.X)
end

-- Pseudo-aléatoire stable (même ville à chaque démarrage)
function TownKit.Hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end
local hash = TownKit.Hash

-- Arbre : tronc + feuillage en couches (3 boules) ; `kind` 1 = feuillu,
-- 2 = cerisier, 3 = sapin (cônes en étages), 4 = boule taillée
function TownKit.Tree(parent: Instance, base: Vector3, height: number, seed: number, kind: number?)
	local model = TownKit.Model(parent, "Tree")
	local k = kind or (hash(seed, 3) < 0.18 and 2 or 1)
	local trunkH = height * 0.55
	TownKit.Column(model, "Trunk", base, trunkH, 0.8 + height * 0.04, C.Bark, M.Wood, "prop")
	if k == 3 then
		local green = Color3.fromRGB(70, 138, 96):Lerp(Color3.fromRGB(96, 160, 104), hash(seed, 5))
		for i = 0, 1 do
			local w = height * (0.6 - i * 0.2)
			local h = height * 0.42
			local y = trunkH * 0.45 + i * height * 0.3
			-- (étage de sapin : deux coins croisés = pyramide)
			TownKit.Wedge(model, "Fir", Vector3.new(w, h, w / 2), CFrame.new(base + Vector3.new(0, y + h / 2, 0)) * CFrame.new(0, 0, -w / 4), green, M.Grass, "deco")
			TownKit.Wedge(model, "Fir", Vector3.new(w, h, w / 2), CFrame.new(base + Vector3.new(0, y + h / 2, 0)) * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -w / 4), green, M.Grass, "deco")
		end
		return model
	end
	local greens = { 1, 2, 3, 5 }
	local color = k == 2 and TownKit.FOLIAGE[4] or TownKit.FOLIAGE[greens[1 + math.floor(hash(seed, 7) * 4) % 4]]
	if k == 4 then
		TownKit.Ball(model, "Crown", base + Vector3.new(0, trunkH + height * 0.28, 0), height * 0.62, color, M.Grass, "decoS")
		return model
	end
	local crown = height * 0.62
	local top = base + Vector3.new(0, trunkH + crown * 0.35, 0)
	TownKit.Ball(model, "Crown", top, crown, color, M.Grass, "decoS")
	local a = hash(seed, 11) * math.pi * 2
	TownKit.Ball(model, "Crown2", top + Vector3.new(math.cos(a) * crown * 0.32, -crown * 0.12, math.sin(a) * crown * 0.32), crown * 0.72, color:Lerp(C.White, 0.1), M.Grass, "deco")
	TownKit.Ball(model, "Crown3", top + Vector3.new(-math.cos(a) * crown * 0.28, crown * 0.18, -math.sin(a) * crown * 0.28), crown * 0.66, color:Lerp(Color3.new(0, 0, 0), 0.08), M.Grass, "deco")
	return model
end

-- Lampadaire de ville (fonte + lanterne) ; `light` : vraie lumière si le budget le permet
function TownKit.Lamp(parent: Instance, base: Vector3, facing: number, light: boolean?, double: boolean?)
	local model = TownKit.Model(parent, "Lamp")
	local rot = CFrame.new(base) * CFrame.Angles(0, facing, 0)
	part(model, "Foot", Vector3.new(1.3, 1, 1.3), rot * CFrame.new(0, 0.5, 0), C.Metal, M.Metal, "prop")
	TownKit.Column(model, "Pole", base + Vector3.new(0, 1, 0), 11, 0.45, C.Metal, M.Metal, "prop")
	local arms = double and { -1, 1 } or { 1 }
	local glowPart: BasePart? = nil
	for _, side in ipairs(arms) do
		local armEnd = rot * CFrame.new(side * 2.2, 11.6, 0)
		TownKit.Beam(model, "Arm", (rot * CFrame.new(0, 11.8, 0)).Position, armEnd.Position, 0.22, 0.22, C.Metal, M.Metal, "deco")
		part(model, "Hood", Vector3.new(1.6, 0.35, 1.6), armEnd * CFrame.new(0, -0.1, 0), C.Metal, M.Metal, "deco")
		local glow = part(model, "Glow", Vector3.new(1.1, 1.1, 1.1), armEnd * CFrame.new(0, -0.8, 0), C.Glow, M.Neon, "deco")
		glowPart = glowPart or glow
	end
	part(model, "Cap", Vector3.new(0.7, 0.5, 0.7), rot * CFrame.new(0, 12.2, 0), C.Metal, M.Metal, "deco")
	if light and glowPart then
		TownKit.Light(glowPart, C.Glow, 26, 1.4)
	end
	return model
end

-- Banc public (vrai Seat) : `cf` au sol, le dossier du côté +Z local
function TownKit.Bench(parent: Instance, cf: CFrame)
	local model = TownKit.Model(parent, "Bench")
	local seat = part(model, "Seat", Vector3.new(6, 0.35, 1.9), cf * CFrame.new(0, 1.7, 0), C.WoodLight, M.WoodPlanks, "solid", "Seat")
	seat.CanCollide = true
	part(model, "Back", Vector3.new(6, 1.5, 0.25), cf * CFrame.new(0, 2.9, 0.95) * CFrame.Angles(math.rad(-10), 0, 0), C.WoodLight, M.WoodPlanks, "deco")
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(model, "Leg", Vector3.new(0.3, 1.6, 1.8), cf * CFrame.new(x, 0.8, 0.1), C.Metal, M.Metal, "prop")
		part(model, "ArmRest", Vector3.new(0.3, 0.25, 1.8), cf * CFrame.new(x, 2.35, 0.1), C.Metal, M.Metal, "deco")
	end
	return model
end

-- Poubelle (tri : deux couleurs)
function TownKit.Bin(parent: Instance, base: Vector3, color: Color3?)
	local model = TownKit.Model(parent, "Bin")
	TownKit.Column(model, "Body", base, 2.6, 1.6, color or Color3.fromRGB(96, 150, 110), M.Metal, "prop")
	TownKit.Column(model, "Lid", base + Vector3.new(0, 2.6, 0), 0.3, 1.8, C.Metal, M.Metal, "deco")
	return model
end

-- Borne (potelet)
function TownKit.Bollard(parent: Instance, base: Vector3)
	TownKit.Column(parent, "Bollard", base, 2.2, 0.6, C.Metal, M.Metal, "prop")
end

-- Bouche d'incendie
function TownKit.Hydrant(parent: Instance, base: Vector3)
	local model = TownKit.Model(parent, "Hydrant")
	TownKit.Column(model, "Body", base, 2, 0.8, Color3.fromRGB(226, 64, 72), M.Metal, "prop")
	TownKit.Ball(model, "Top", base + Vector3.new(0, 2, 0), 0.8, Color3.fromRGB(226, 64, 72), M.Metal, "deco")
	part(model, "Nozzle", Vector3.new(1.4, 0.35, 0.35), CFrame.new(base + Vector3.new(0, 1.4, 0)), C.MetalLight, M.Metal, "deco")
	return model
end

-- Jardinière de fleurs (bac en pierre + terre + boules de fleurs)
function TownKit.Planter(parent: Instance, cf: CFrame, length: number, width: number, seed: number)
	local model = TownKit.Model(parent, "Planter")
	part(model, "Box", Vector3.new(length, 1.6, width), cf * CFrame.new(0, 0.8, 0), C.Stone, M.Concrete, "prop")
	part(model, "Soil", Vector3.new(length - 0.6, 0.2, width - 0.6), cf * CFrame.new(0, 1.62, 0), Color3.fromRGB(110, 78, 60), M.Ground, "deco")
	local n = math.max(2, math.floor(length / 2.2))
	TownKit.Beam(model, "Leaves", (cf * CFrame.new(-length / 2 + 0.8, 2, 0)).Position, (cf * CFrame.new(length / 2 - 0.8, 2, 0)).Position, width - 0.9, 0.9, C.GrassDark, M.Grass, "deco")
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * length / n
		TownKit.Ball(model, "Flower", (cf * CFrame.new(x, 2.5, (hash(seed, i) - 0.5) * (width - 1.4))).Position, 1.1, TownKit.FLOWERS[(seed + i) % #TownKit.FLOWERS + 1], M.SmoothPlastic, "deco")
	end
	return model
end

-- Arceau à vélos + un vélo garé
function TownKit.BikeRack(parent: Instance, cf: CFrame, bikes: number)
	local model = TownKit.Model(parent, "BikeRack")
	for i = 0, 2 do
		local x = (i - 1) * 1.6
		part(model, "Hoop", Vector3.new(0.2, 2.2, 0.2), cf * CFrame.new(x, 1.1, -0.9), C.MetalLight, M.Metal, "deco")
		part(model, "Hoop", Vector3.new(0.2, 2.2, 0.2), cf * CFrame.new(x, 1.1, 0.9), C.MetalLight, M.Metal, "deco")
		part(model, "HoopTop", Vector3.new(0.2, 0.2, 2), cf * CFrame.new(x, 2.2, 0), C.MetalLight, M.Metal, "deco")
	end
	for i = 1, bikes do
		local bcf = cf * CFrame.new((i - 2) * 1.6 + 0.4, 0, 0)
		local frame = ({ C.Sky, C.Pink, C.Mint })[i % 3 + 1]
		for _, z in ipairs({ -1.4, 1.4 }) do
			local wheel = part(model, "Wheel", Vector3.new(0.15, 2, 2), bcf * CFrame.new(0, 1, z), C.Metal, M.Rubber, "deco")
			;(wheel :: Part).Shape = Enum.PartType.Cylinder
		end
		part(model, "Frame", Vector3.new(0.18, 0.22, 2.8), bcf * CFrame.new(0, 1.6, 0) * CFrame.Angles(math.rad(8), 0, 0), frame, M.Metal, "deco")
		part(model, "Saddle", Vector3.new(0.4, 0.2, 0.8), bcf * CFrame.new(0, 2.3, 0.7), C.Metal, M.Leather, "deco")
	end
	return model
end

-- Panneau routier (poteau + disque / losange)
function TownKit.RoadSign(parent: Instance, base: Vector3, facing: number, color: Color3, shape: string?)
	local model = TownKit.Model(parent, "RoadSign")
	TownKit.Column(model, "Pole", base, 7, 0.25, C.MetalLight, M.Metal, "prop")
	local cf = CFrame.new(base + Vector3.new(0, 7.2, 0)) * CFrame.Angles(0, facing, 0)
	if shape == "Diamond" then
		part(model, "Plate", Vector3.new(1.8, 1.8, 0.12), cf * CFrame.Angles(0, 0, math.rad(45)), color, M.Metal, "deco")
		part(model, "Inner", Vector3.new(1.3, 1.3, 0.14), cf * CFrame.Angles(0, 0, math.rad(45)), C.White, M.SmoothPlastic, "deco")
	elseif shape == "Rect" then
		part(model, "Plate", Vector3.new(2.6, 1.6, 0.12), cf, color, M.Metal, "deco")
		part(model, "Inner", Vector3.new(2.2, 1.2, 0.14), cf, C.White, M.SmoothPlastic, "deco")
	else
		local plate = part(model, "Plate", Vector3.new(0.12, 2.2, 2.2), cf * CFrame.Angles(0, math.rad(90), 0), color, M.Metal, "deco")
		;(plate :: Part).Shape = Enum.PartType.Cylinder
		part(model, "Bar", Vector3.new(1.4, 0.36, 0.16), cf, C.White, M.SmoothPlastic, "deco")
	end
	return model
end

-- Voiture garée (carrosserie + cabine vitrée + roues + phares) ; `cf` au sol, avant vers -Z
function TownKit.Car(parent: Instance, cf: CFrame, color: Color3, kind: string?)
	local model = TownKit.Model(parent, "Car")
	local long = kind == "Van" and 11 or 9
	local cabinH = kind == "Van" and 3 or 2.1
	part(model, "Body", Vector3.new(4.6, 1.8, long), cf * CFrame.new(0, 1.9, 0), color, M.SmoothPlastic, "solid")
	part(model, "Skirt", Vector3.new(4.7, 0.6, long - 0.4), cf * CFrame.new(0, 1.05, 0), C.Metal, M.SmoothPlastic, "deco")
	local cabinLen = kind == "Van" and long - 2.6 or long * 0.52
	local cabinZ = kind == "Van" and 1.1 or 0.6
	part(model, "Cabin", Vector3.new(4.1, cabinH, cabinLen), cf * CFrame.new(0, 2.8 + cabinH / 2, cabinZ), color:Lerp(C.White, 0.12), M.SmoothPlastic, "deco")
	part(model, "Windows", Vector3.new(4.16, cabinH * 0.62, cabinLen - 0.5), cf * CFrame.new(0, 2.85 + cabinH * 0.55, cabinZ), C.GlassDark, M.Glass, "deco")
	part(model, "Windshield", Vector3.new(3.7, cabinH * 0.7, 0.12), cf * CFrame.new(0, 2.85 + cabinH * 0.5, cabinZ - cabinLen / 2 - 0.02), C.GlassDark, M.Glass, "deco")
	for _, x in ipairs({ -2.1, 2.1 }) do
		for _, z in ipairs({ -long / 2 + 1.7, long / 2 - 1.7 }) do
			local w = part(model, "Wheel", Vector3.new(0.9, 2, 2), cf * CFrame.new(x, 1, z), Color3.fromRGB(40, 40, 46), M.Rubber, "deco")
			;(w :: Part).Shape = Enum.PartType.Cylinder
		end
	end
	for _, x in ipairs({ -1.6, 1.6 }) do
		part(model, "Headlight", Vector3.new(0.9, 0.45, 0.12), cf * CFrame.new(x, 2.2, -long / 2 - 0.02), C.Glow, M.Neon, "deco")
		part(model, "Taillight", Vector3.new(0.8, 0.4, 0.12), cf * CFrame.new(x, 2.3, long / 2 + 0.02), Color3.fromRGB(230, 60, 80), M.Neon, "deco")
	end
	return model
end

----------------------------------------------------------------------
-- Géométrie de la ville (repère : centre de la place = Origin, sol y = 0)
----------------------------------------------------------------------
-- Emplacements 0..m-1 autour de la place (0 = entrée, +Z), boulevard
-- polygonal (un côté droit par emplacement). Repère d'un côté (SideFrame) :
-- x le long de la rue (vers la droite de qui regarde la place), -z vers le
-- centre, +z vers l'extérieur.

export type Geo = {
	Count: number,
	Slots: number,
	Origin: Vector3,
	HalfAngle: number,
	PlotR: number,
	Front: number,
	Road: number,
	Inner: number,
	Gate: number,
	Town: number,
	StreetStart: number,
	SideR: number,
	SideL: number,
	Streets: { number },
	Reserved: { { P: Vector3, R: number } },
	Dir: (angle: number) -> Vector3,
	SlotAngle: (slot: number) -> number,
	At: (angle: number, dist: number, y: number?) -> Vector3,
	SideFrame: (slot: number, dist: number, y: number?) -> CFrame,
	PolyRadius: (p: Vector3) -> number,
	Reserve: (p: Vector3, r: number) -> (),
	IsFree: (p: Vector3, r: number) -> boolean,
}

function TownKit.Geo(count: number): Geo
	local O = WorldLayout.Origin()
	local m = WorldLayout.PlotSlots(count)
	local g = {} :: any
	g.Count = count
	g.Slots = m
	g.Origin = O
	g.HalfAngle = math.pi / m
	g.PlotR = WorldLayout.PlotRadius(count)
	g.Front = WorldLayout.PlotFrontRadius(count)
	g.Road = WorldLayout.RingRoadRadius(count)
	g.Inner = WorldLayout.RingInnerRadius(count)
	g.Gate = WorldLayout.GateDistance(count)
	g.Town = WorldLayout.TownRadius(count)
	-- (les rues commencent après la couronne de boutiques de la place)
	g.StreetStart = WorldLayout.PLAZA_R + 30
	g.SideR = math.max(1, math.floor(m / 4 + 0.5))
	g.SideL = m - g.SideR
	g.Streets = { 0, g.SideR, g.SideL }
	g.Reserved = {}
	function g.Dir(angle: number): Vector3
		return Vector3.new(math.sin(angle), 0, math.cos(angle))
	end
	function g.SlotAngle(slot: number): number
		return slot / m * math.pi * 2
	end
	-- point relatif au centre (y relatif au sol)
	function g.At(angle: number, dist: number, y: number?): Vector3
		return O + g.Dir(angle) * dist + Vector3.new(0, y or 0, 0)
	end
	function g.SideFrame(slot: number, dist: number, y: number?): CFrame
		local d = g.Dir(g.SlotAngle(slot))
		local p = O + d * dist + Vector3.new(0, y or 0, 0)
		return CFrame.lookAt(p, p - d)
	end
	-- "rayon" polygonal d'un point du monde (comparable à Road / Inner / Front)
	function g.PolyRadius(p: Vector3): number
		local rel = p - O
		local best = -math.huge
		for k = 0, m - 1 do
			local d = g.Dir(g.SlotAngle(k))
			best = math.max(best, rel.X * d.X + rel.Z * d.Z)
		end
		return best
	end
	function g.Reserve(p: Vector3, r: number)
		table.insert(g.Reserved, { P = p, R = r })
	end
	-- Place libre pour un objet de rayon r (hors rues, boulevard, place, zones réservées)
	function g.IsFree(p: Vector3, r: number): boolean
		local rel = p - O
		local flat = Vector3.new(rel.X, 0, rel.Z)
		if flat.Magnitude < WorldLayout.PLAZA_R + 26 + r then
			return false
		end
		if g.PolyRadius(p) > g.Inner - 3 - r then
			return false
		end
		for _, slot in ipairs(g.Streets) do
			local d = g.Dir(g.SlotAngle(slot))
			local along = flat:Dot(d)
			local side = math.abs(flat.X * d.Z - flat.Z * d.X)
			local halfW = slot == 0 and 24 or 15
			if along > 0 and side < halfW + r then
				return false
			end
		end
		for _, z in ipairs(g.Reserved) do
			local dz = Vector3.new(p.X - z.P.X, 0, p.Z - z.P.Z)
			if dz.Magnitude < z.R + r then
				return false
			end
		end
		return true
	end
	return g :: Geo
end

return TownKit
