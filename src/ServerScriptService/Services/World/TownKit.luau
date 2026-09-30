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
local CarModels = require(ReplicatedStorage.Shared.CarModels) -- (v9.6, GARAGE96) voitures garées
local VehicleModels = require(ReplicatedStorage.Shared.VehicleModels) -- (v9.7, VEHICLES97) bus, vélos, camions
local Greenery = require(ReplicatedStorage.Shared.Greenery) -- (v9.7, NATURE97) arbres

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

-- (v9.8, CITY98) mobilier de rue + chemins des passants construits côté
-- CLIENT (TownStreetLife / TownPeople) : le serveur ne fait que noter les
-- emplacements (0 pièce), publiés en attributs par TownKit.PublishLife
local life: { Spots: { string }, Paths: { [string]: { Points: { Vector3 }, Loop: boolean } } } = { Spots = {}, Paths = {} }

function TownKit.Reset()
	stats.Parts = 0
	stats.Lights = 0
	life.Spots = {}
	life.Paths = {}
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

-- v9.6 (FIXES96) "flash bang" : plafonds pour TOUTES les lumières de la
-- ville (même si un appelant demande plus) ; lumières "NightOnly" : le
-- client (TownAtmosphere) ne les allume que la nuit
TownKit.MAX_LIGHT_BRIGHTNESS = 1
TownKit.MAX_LIGHT_RANGE = 20

function TownKit.Light(host: BasePart, color: Color3, range: number, brightness: number, kind: string?): Light?
	if stats.Lights >= TownKit.MAX_LIGHTS then
		return nil
	end
	stats.Lights += 1
	local light: Light
	local r = math.min(range, TownKit.MAX_LIGHT_RANGE)
	if kind == "Spot" then
		local spot = Instance.new("SpotLight")
		spot.Angle = 70
		spot.Face = Enum.NormalId.Bottom
		spot.Range = r
		light = spot
	else
		local point = Instance.new("PointLight")
		point.Range = r
		light = point
	end
	light.Color = color
	light.Brightness = math.min(brightness, TownKit.MAX_LIGHT_BRIGHTNESS)
	light.Shadows = false
	light:SetAttribute("NightOnly", true)
	light.Parent = host
	return light
end

-- Verre de lanterne / ampoule : mat (SmoothPlastic) le jour, Neon la nuit
-- (bascule côté client, TownAtmosphere) ; à garder PETIT (≤ ~1 stud)
function TownKit.Glow(p: BasePart): BasePart
	p.Material = M.SmoothPlastic
	p:SetAttribute("NightGlow", true)
	return p
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
	-- (v9.6 : 0.5 par défaut, un panneau n'est plus une boîte lumineuse la nuit)
	gui.LightInfluence = lightInfluence or 0.5
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

-- Arbre (v9.7, NATURE97) : espèces réalistes stylisées de Shared/Greenery
-- (tronc évasé, branches, grappes irrégulières en 2-3 teintes).
-- `kind` : nom d'espèce ("Oak", "Maple", "Cherry", "Birch", "Fir", "Palm",
-- "Poplar", "Fruit", "Willow", "Round") ou ancien numéro v9.4 (1 feuillu
-- au hasard, 2 cerisier, 3 sapin, 4 boule taillée).
-- `opts.Tier` : niveau de détail construit par le SERVEUR (0 = silhouette,
-- défaut ; 1 = arbre "vedette" avec branches) ; le client (TownGreenery)
-- ajoute le niveau 2 aux arbres proches. `opts.Lawn` : sur pelouse (pétales
-- au sol permis).
TownKit.SPECIES = Greenery.SPECIES
-- v9.9 (CITY99, budget du serveur) : l'arbre n'est plus construit ici. Le
-- serveur pose un Model VIDE (0 pièce) qui porte les attributs de l'arbre
-- (TreeBase / TreeSpecies / TreeHeight / TreeSeed / TreeTier / TreeLawn,
-- comme Greenery.Tree) + "TreeClient" = true ; chaque client construit le
-- même arbre (Greenery.Tree : mêmes pièces, même hasard) à l'arrivée en
-- ville (TownStreetLife, les plus proches d'abord) et TownGreenery ajoute
-- toujours le niveau de détail de près. WorldPivot = pied de l'arbre (les
-- ClearSite du supermarché / de la concession le lisent).
function TownKit.Tree(parent: Instance, base: Vector3, height: number, seed: number, kind: any?, opts: { Tier: number?, Lawn: boolean? }?)
	local o = opts or {}
	local species = Greenery.Species(kind or 1, seed)
	local model = Greenery.Tree(parent, base, height, seed, species, -1, 0, { Lawn = o.Lawn == true })
	model:SetAttribute("TreeTier", o.Tier or 0)
	model:SetAttribute("TreeClient", true)
	model.WorldPivot = CFrame.new(base)
	return model
end

-- Buisson : 3-4 boules qui se chevauchent (+ fleurs si `flower`)
function TownKit.Bush(parent: Instance, base: Vector3, size: number, seed: number, flower: Color3?)
	local model = TownKit.Model(parent, "Bush")
	local a = hash(seed, 81) * math.pi * 2
	local green = TownKit.FOLIAGE[1 + math.floor(hash(seed, 82) * 3) % 3]
	local function at(ang: number, r: number, y: number): Vector3
		return base + Vector3.new(math.cos(ang) * r, y, math.sin(ang) * r)
	end
	TownKit.Ball(model, "Bush", at(a, size * 0.06, size * 0.36), size, green, M.Grass, "decoS")
	TownKit.Ball(model, "Bush", at(a + 2.2, size * 0.42, size * 0.26), size * 0.7, green:Lerp(C.White, 0.1), M.Grass, "deco")
	TownKit.Ball(model, "Bush", at(a + 4.1, size * 0.38, size * 0.22), size * 0.62, green:Lerp(Color3.new(0, 0, 0), 0.1), M.Grass, "deco")
	if flower then
		for k = 0, 1 do
			local p = at(a + 1 + k * 2.6, size * 0.4, size * 0.62)
			TownKit.Egg(model, "Blossom", CFrame.new(p), Vector3.new(size * 0.34, size * 0.2, size * 0.34), flower, M.SmoothPlastic, "deco")
		end
	end
	return model
end

-- Ovale (Part + SpecialMesh "Sphere" : une Ball de Roblox reste ronde)
function TownKit.Egg(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, profile: Profile?): BasePart
	local p = part(parent, name, size, cf, color, material or M.Grass, profile or "deco")
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Haie taillée au dessus ARRONDI : corps + boudin (cylindre couché) + bouts
-- arrondis (colonne + boule). `cf` au sol, au milieu, longueur le long de X.
-- 6 pièces ; seul le corps est solide.
TownKit.HEDGE = Color3.fromRGB(78, 146, 76)
function TownKit.Hedge(parent: Instance, cf: CFrame, length: number, width: number, height: number, seed: number?)
	local model = TownKit.Model(parent, "Hedge")
	local w = width
	local L = math.max(length, w + 0.5)
	local body = height - w / 2
	local green = TownKit.HEDGE:Lerp(Color3.fromRGB(96, 160, 84), hash(seed or 1, 83) * 0.6)
	local top = green:Lerp(Color3.fromRGB(150, 200, 110), 0.18)
	part(model, "Hedge", Vector3.new(L - w, body - 0.04, w - 0.04), cf * CFrame.new(0, (body - 0.04) / 2, 0), green, M.Grass, "prop")
	local roll = part(model, "HedgeTop", Vector3.new(L - w - 0.1, w, w), cf * CFrame.new(0, body, 0), top, M.Grass, "decoS")
	;(roll :: Part).Shape = Enum.PartType.Cylinder
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (L - w) / 2
		TownKit.Column(model, "HedgeEnd", (cf * CFrame.new(x, 0, 0)).Position, body - 0.08, w, green, M.Grass, "deco")
		TownKit.Ball(model, "HedgeCap", (cf * CFrame.new(x, body, 0)).Position, w, top, M.Grass, "deco")
	end
	return model
end

-- Massif de fleurs rond : bordure en pierre, terre, touffes de feuilles et
-- VRAIS bouquets (ovales de couleur posés sur les feuilles) ; ~11 pièces
function TownKit.FlowerBed(parent: Instance, center: Vector3, radius: number, seed: number)
	local model = TownKit.Model(parent, "FlowerBed")
	TownKit.Disc(model, "BedEdge", center + Vector3.new(0, 0.45, 0), radius + 0.4, 0.45, C.Stone, M.Cobblestone, "prop")
	TownKit.Disc(model, "BedSoil", center + Vector3.new(0, 0.52, 0), radius, 0.2, Color3.fromRGB(104, 74, 58), M.Ground, "deco")
	local a = hash(seed, 84) * math.pi * 2
	local leaf = Color3.fromRGB(86, 150, 78)
	for k = 0, 2 do
		local ang = a + k * math.pi * 2 / 3
		-- (hauteurs décalées de 0,06 : aucune face de boîte confondue, même pour un détecteur qui ignore le maillage)
		local p = center + Vector3.new(math.cos(ang) * radius * 0.42, 0.62 + k * 0.06, math.sin(ang) * radius * 0.42)
		TownKit.Egg(model, "Leaves", CFrame.new(p) * CFrame.Angles(0, -ang, 0), Vector3.new(radius * 0.95, 1.1, radius * 0.75), leaf:Lerp(C.White, k * 0.06), M.Grass, "deco")
	end
	local n = radius >= 3 and 6 or 4
	for k = 0, n - 1 do
		local ang = a + 0.5 + k * math.pi * 2 / n
		local r = radius * (k % 2 == 0 and 0.62 or 0.36)
		local p = center + Vector3.new(math.cos(ang) * r, 1.1 + (k % 2) * 0.2 + k * 0.05, math.sin(ang) * r)
		local color = TownKit.FLOWERS[(seed + k) % #TownKit.FLOWERS + 1]
		TownKit.Egg(model, "Blooms", CFrame.new(p) * CFrame.Angles(0, ang, 0), Vector3.new(1.5, 0.75, 1.3), color, M.SmoothPlastic, "deco")
	end
	TownKit.Egg(model, "Blooms", CFrame.new(center + Vector3.new(0, 1.55, 0)), Vector3.new(1.6, 1, 1.6), TownKit.FLOWERS[(seed + 2) % #TownKit.FLOWERS + 1], M.SmoothPlastic, "deco")
	return model
end

-- Touffes d'herbe haute (3 ovales fins penchés) dans un rectangle w x d
function TownKit.Tufts(parent: Instance, cf: CFrame, w: number, d: number, seed: number)
	local model = TownKit.Model(parent, "Tufts")
	for k = 0, 2 do
		local x = (hash(seed, 85 + k) - 0.5) * w
		local z = (hash(seed, 88 + k) - 0.5) * d
		local h = 1.2 + hash(seed, 91 + k) * 0.8
		TownKit.Egg(model, "Tuft", cf * CFrame.new(x, h * 0.3, z) * CFrame.Angles(math.rad(8), hash(seed, 94 + k) * 6, math.rad(-6)), Vector3.new(1.3, h, 0.9), Color3.fromRGB(96, 164, 80):Lerp(Color3.fromRGB(150, 196, 96), hash(seed, 97 + k)), M.Grass, "deco")
	end
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
		-- (v9.6 : verre dépoli sous le chapeau, Neon la nuit seulement)
		local glow = part(model, "Glow", Vector3.new(0.9, 0.9, 0.9), armEnd * CFrame.new(0, -0.74, 0), C.Glow, M.SmoothPlastic, "deco")
		TownKit.Glow(glow)
		glowPart = glowPart or glow
	end
	part(model, "Cap", Vector3.new(0.7, 0.5, 0.7), rot * CFrame.new(0, 12.2, 0), C.Metal, M.Metal, "deco")
	if light and glowPart then
		-- (v9.6 : 26 / 1.4 -> 18 / 0.85)
		TownKit.Light(glowPart, C.Glow, 18, 0.85)
	end
	return model
end

-- Banc public (v9.6, refait) : banc de parc réaliste, vrai Seat.
-- `cf` = au sol, milieu du banc ; l'AVANT (LookVector, -Z local) est le côté
-- où l'on s'assoit, le DOSSIER est du côté +Z local. Signature inchangée.
--   - 2 flasques en fonte (pied avant qui monte jusqu'à l'accoudoir, pied
--     arrière qui continue en montant du dossier, accoudoir) : 14 pièces en
--     tout (budget de la ville) ;
--   - 3 lattes d'assise + 2 lattes de dossier en bois, dossier incliné de
--     12° vers l'ARRIÈRE (+Z) ; (v9.4 : incliné vers l'avant, flottant) ;
--   - assise à 1.9 stud (R15) ; le Seat (invisible) est une seule pièce
--     dont le DESSUS = le dessus des lattes et la face avant (-Z) regarde à
--     l'opposé du dossier -> le personnage s'assoit face à l'avant, le dos
--     contre le dossier ;
--   - seul le Seat a CanTouch ; tout est ancré ; lattes / accoudoirs sans
--     collision (pas de petites pièces qui font trébucher).
TownKit.BENCH = {
	Length = 5.4, -- lattes (x)
	SeatTop = 1.45, -- dessus de l'assise (y) ; v9.9 (CITY99, échelle SCALE99) : 1,9 -> 1,45 (~45 cm, assise réelle)
	SeatFront = -0.85, -- bord avant de l'assise (z)
	SeatBack = 0.75, -- bord arrière de l'assise (z)
	Tilt = 12, -- (°) dossier incliné vers l'arrière
}
function TownKit.Bench(parent: Instance, cf: CFrame)
	local B = TownKit.BENCH
	local model = TownKit.Model(parent, "Bench")
	local wood = Color3.fromRGB(196, 140, 92)
	local iron = Color3.fromRGB(58, 54, 66)
	local L, H = B.Length, B.SeatTop
	local SLAT_T = 0.16
	-- Seat : une pièce invisible, dessus = assise visible, avant = -Z ; un
	-- peu reculée (le personnage s'assoit au CENTRE du Seat : le dos vient
	-- contre le dossier, les cuisses sur les lattes avant)
	local zFront, zBack = B.SeatFront, B.SeatBack
	local seatDepth = zBack - zFront
	local seat = part(model, "Seat", Vector3.new(L, 1, seatDepth - 0.25), cf * CFrame.new(0, H - 0.5, (zFront + 0.25 + zBack) / 2), wood, M.Wood, "solid", "Seat")
	seat.Transparency = 1
	seat.CanCollide = true
	seat.CanQuery = true
	seat.CanTouch = true -- (un Seat s'active au contact : SEULE pièce touchable)
	seat.CastShadow = false
	-- 3 lattes d'assise (visibles, sans collision)
	local slatW = (seatDepth - 2 * 0.08) / 3
	for i = 0, 2 do
		local z = zFront + slatW / 2 + i * (slatW + 0.08)
		part(model, "SeatSlat", Vector3.new(L, SLAT_T, slatW), cf * CFrame.new(0, H - SLAT_T / 2, z), wood, M.Wood, "deco").CastShadow = true
	end
	-- dossier : 2 lattes sur un repère incliné (pivot au bord arrière de l'assise)
	local tilt = CFrame.Angles(math.rad(B.Tilt), 0, 0) -- (+X : le haut part vers +Z)
	local pivot = cf * CFrame.new(0, H + 0.05, zBack - 0.05) * tilt
	for i, y in ipairs({ 0.55, 1.2 }) do
		local slat = part(model, "BackSlat", Vector3.new(L, 0.5, 0.14), pivot * CFrame.new(0, y, 0.07), wood, M.Wood, "prop")
		slat.CastShadow = true
		slat.Name = "BackSlat" .. i
	end
	-- 2 flasques en fonte, JUSTE à l'extérieur des lattes
	local fx = L / 2 + 0.13
	local armY = H + 0.72
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * fx
		-- pied avant (du sol jusqu'à l'accoudoir)
		part(model, "FrontLeg", Vector3.new(0.22, armY, 0.22), cf * CFrame.new(x, armY / 2, zFront + 0.2), iron, M.Metal, "prop")
		-- pied arrière (du sol à l'assise), puis montant du dossier (incliné)
		part(model, "RearLeg", Vector3.new(0.22, H, 0.22), cf * CFrame.new(x, H / 2, zBack - 0.12), iron, M.Metal, "prop")
		part(model, "BackPost", Vector3.new(0.22, 1.75, 0.2), pivot * CFrame.new(x, 0.755, -0.02), iron, M.Metal, "deco")
		-- accoudoir
		part(model, "ArmRest", Vector3.new(0.3, 0.14, seatDepth + 0.1), cf * CFrame.new(x, armY + 0.07, (zFront + zBack) / 2 - 0.08), iron, M.Metal, "deco")
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
	-- (v9.7) touffes de feuillage arrondies + bouquets (ovales posés dessus)
	local leaves = math.max(1, math.floor(length / 4 + 0.5))
	for i = 1, leaves do
		local x = -length / 2 + (i - 0.5) * length / leaves
		TownKit.Egg(model, "Leaves", cf * CFrame.new(x, 2 + (i % 2) * 0.06, 0), Vector3.new(length / leaves + 0.6, 1.3, width - 0.46 - (i % 2) * 0.24), C.GrassDark:Lerp(C.White, (i % 2) * 0.08), M.Grass, "deco")
	end
	local n = math.max(2, math.floor(length / 2.2))
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * length / n
		local color = TownKit.FLOWERS[(seed + i) % #TownKit.FLOWERS + 1]
		TownKit.Egg(model, "Flower", cf * CFrame.new(x, 2.55 + (i % 2) * 0.12, (hash(seed, i) - 0.5) * (width - 1.6)) * CFrame.Angles(0, hash(seed, i + 9) * 3, 0), Vector3.new(1.4, 0.7, 1.2), color, M.SmoothPlastic, "deco")
	end
	return model
end

-- Arceau à vélos + un vélo garé
-- (v9.7, VEHICLES97) Place réservée à un véhicule construit côté CLIENT
-- (TownTraffic, en flux : bus complet, vélos, trottinettes, voitures garées
-- en plus...) : une Configuration (0 pièce) dans DopamineTown/VehicleSpots,
-- attributs Kind + CF (au sol, avant vers -Z) + options (Color, Variant...).
-- `collider` (facultatif) : boîte invisible solide côté serveur (1 pièce),
-- pour qu'on ne traverse pas un bus / un camion.
TownKit.SPOTS_FOLDER = "VehicleSpots"
function TownKit.VehicleSpot(parent: Instance, kind: string, cf: CFrame, attrs: { [string]: any }?, collider: { Size: Vector3, CF: CFrame }?): Instance
	local root = parent:FindFirstAncestor("DopamineTown") or parent
	local folder = root:FindFirstChild(TownKit.SPOTS_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TownKit.SPOTS_FOLDER
		folder.Parent = root
	end
	local spot = Instance.new("Configuration")
	spot.Name = kind
	spot:SetAttribute("Kind", kind)
	spot:SetAttribute("CF", cf)
	for key, value in pairs(attrs or {}) do
		spot:SetAttribute(key, value)
	end
	spot.Parent = folder
	if collider then
		part(parent, "VehicleCollider", collider.Size, collider.CF, C.White, M.SmoothPlastic, "ghost")
	end
	return spot
end

-- (v9.8, CITY98) VIE DE LA RUE, construite côté CLIENT (0 pièce serveur) :
--   TownKit.LifeSpot(kind, cf, seed)   un objet de rue (poubelle, abribus,
--       kiosque, feux, panneau publicitaire, moulin...) : `cf` au sol, avant
--       du mobilier vers -Z (seule la rotation autour de Y est gardée) ;
--   TownKit.LifePath(name, points, loop)  un chemin des passants (au sol) ;
--   TownKit.PublishLife(root)          à la fin du Build : dossier
--       "StreetLife" (Configuration par case de 64 studs, attribut "Data" =
--       lignes "kind;x;y;z;yaw;seed[;sx,sy,sz]") + Configuration "Path" (attributs
--       Name, Loop, Points = "x,y,z;x,y,z...").
TownKit.LIFE_FOLDER = "StreetLife"
TownKit.LIFE_CELL = 64

local function r2(v: number): string
	return string.format("%.2f", v)
end

-- `size` (facultatif) : taille d'une pièce simple (peinture au sol : "Paint")
function TownKit.LifeSpot(kind: string, cf: CFrame, seed: number?, size: Vector3?)
	local _, yaw = cf:ToEulerAnglesYXZ()
	local p = cf.Position
	local fields = { kind, r2(p.X), r2(p.Y), r2(p.Z), string.format("%.4f", yaw), tostring(math.floor(seed or 0)) }
	if size then
		table.insert(fields, r2(size.X) .. "," .. r2(size.Y) .. "," .. r2(size.Z))
	end
	table.insert(life.Spots, table.concat(fields, ";"))
end

function TownKit.LifePath(name: string, points: { Vector3 }, loop: boolean)
	life.Paths[name] = { Points = points, Loop = loop }
end

function TownKit.LifeCount(): number
	return #life.Spots
end

function TownKit.PublishLife(root: Instance): Folder
	local old = root:FindFirstChild(TownKit.LIFE_FOLDER)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = TownKit.LIFE_FOLDER
	local cells: { [string]: { string } } = {}
	local order: { string } = {}
	for _, line in ipairs(life.Spots) do
		local fields = string.split(line, ";")
		local cx = math.floor((tonumber(fields[2]) or 0) / TownKit.LIFE_CELL)
		local cz = math.floor((tonumber(fields[4]) or 0) / TownKit.LIFE_CELL)
		local key = cx .. "_" .. cz
		if not cells[key] then
			cells[key] = {}
			table.insert(order, key)
		end
		table.insert(cells[key], line)
	end
	for _, key in ipairs(order) do
		local cell = Instance.new("Configuration")
		cell.Name = "Cell_" .. key
		cell:SetAttribute("Data", table.concat(cells[key], "\n"))
		cell:SetAttribute("Count", #cells[key])
		cell.Parent = folder
	end
	local names = {}
	for name in pairs(life.Paths) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local path = life.Paths[name]
		local pts = {}
		for _, p in ipairs(path.Points) do
			table.insert(pts, r2(p.X) .. "," .. r2(p.Y) .. "," .. r2(p.Z))
		end
		local conf = Instance.new("Configuration")
		conf.Name = "Path"
		conf:SetAttribute("Name", name)
		conf:SetAttribute("Loop", path.Loop)
		conf:SetAttribute("Points", table.concat(pts, ";"))
		conf.Parent = folder
	end
	folder:SetAttribute("Version", 1)
	folder:SetAttribute("Spots", #life.Spots)
	folder.Parent = root
	return folder
end

-- Arceaux à vélos (v9.7, VEHICLES97) : 3 arceaux inox en U (serveur, sans
-- coudes : 10 pièces) + `bikes` vélos réalistes (cadre, roues à rayons,
-- panier...) construits côté client entre les arceaux (TownTraffic).
function TownKit.BikeRack(parent: Instance, cf: CFrame, bikes: number)
	local model = VehicleModels.BikeRack({ Count = 3, Gap = 2.2, Plate = false, Bends = false })
	model:PivotTo(cf)
	model.Parent = parent
	stats.Parts += tonumber(model:GetAttribute("PartCount")) or 0
	local colors = { C.Sky, C.Pink, C.Mint, C.Lemon }
	for i, x in ipairs({ -1.1, 1.1, 3.3, -3.3 }) do
		if i > bikes then
			break
		end
		TownKit.VehicleSpot(parent, "Bike", cf * CFrame.new(x, 0, 0.15), { Variant = if i == 3 then "Kid" else "City", Color = colors[i] })
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
		-- (v9.6 z-fighting : 0.2 d'épaisseur, 0.04 devant / derrière la plaque)
		part(model, "Inner", Vector3.new(1.3, 1.3, 0.2), cf * CFrame.Angles(0, 0, math.rad(45)), C.White, M.SmoothPlastic, "deco")
	elseif shape == "Rect" then
		part(model, "Plate", Vector3.new(2.6, 1.6, 0.12), cf, color, M.Metal, "deco")
		part(model, "Inner", Vector3.new(2.2, 1.2, 0.2), cf, C.White, M.SmoothPlastic, "deco")
	else
		local plate = part(model, "Plate", Vector3.new(0.12, 2.2, 2.2), cf * CFrame.Angles(0, math.rad(90), 0), color, M.Metal, "deco")
		;(plate :: Part).Shape = Enum.PartType.Cylinder
		part(model, "Bar", Vector3.new(1.4, 0.36, 0.22), cf, C.White, M.SmoothPlastic, "deco")
	end
	return model
end

-- Voiture garée (carrosserie + cabine vitrée + roues + phares) ; `cf` au sol, avant vers -Z
-- (v9.6, GARAGE96) vrais modèles de Shared/CarModels, en version "Parked"
-- (~45-55 pièces, sans intérieur) : `kind` = Id de CarModels / Config.Cars
-- (nil = "CityCar") ; "Van" SANS `opts` garde le gabarit v9.4 (camion à
-- tacos de TownNature : 4,7 x 11 studs). `opts` = options de CarModels.Build.
-- Seule la boîte "Root" (invisible) est solide ; aucune lumière, aucun Neon.
function TownKit.Car(parent: Instance, cf: CFrame, color: Color3, kind: string?, opts: any?)
	local options: { [string]: any } = { Detail = "Parked" }
	if type(opts) == "table" then
		for key, value in pairs(opts) do
			options[key] = value
		end
	elseif kind == "Van" then
		options.Scale = Vector3.new(0.78, 0.87, 0.85)
	end
	local model = CarModels.Build(kind or "CityCar", color, options)
	model.Name = "Car"
	model:PivotTo(cf)
	model.Parent = parent
	stats.Parts += tonumber(model:GetAttribute("PartCount")) or 0
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
