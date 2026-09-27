--[[
	GardenBuilder (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > GardenBuilder

	🌻 Dopamine Town : le JARDIN DE DOPAMINE d'un joueur en VRAIE 3D, dans le
	jardin de derrière de sa maison (côté client, comme HouseBuilder).
	  - un parterre surélevé par parterre du jeu (Config.Garden.BasePlots +
	    niveaux de "Flower Beds") : planches de bois, poteaux d'angle, terre,
	    touffes d'herbe, étiquette à la couleur de la fleur ; + un parterre
	    "fantôme" 🔒 quand on peut encore en acheter ;
	  - de VRAIES fleurs 3D (Marguerite, Tulipe, Rose, Tournesol, Lotus doré)
	    qui poussent par stades d'après l'heure du serveur :
	    graine -> pousse -> bouton -> fleur -> prête (scintille, se balance) ;
	  - au-dessus de chaque parterre, une étiquette (BillboardGui) : fleur,
	    minuteur + jauge, "✨ PRÊT !" ;
	  - PROPRIÉTAIRE seulement : invite (ProximityPrompt) + clic
	    (ClickDetector) pour cueillir une fleur prête, planter un parterre
	    vide ; invite "🧺 Tout cueillir" sur le panneau dès 2 fleurs prêtes.
	    Tout passe par la RemoteFunction EXISTANTE "Garden" (GardenService) :
	      ("harvest", index) / ("harvestAll") ; un parterre vide est planté
	      par ("harvest", index) : le serveur répare (sanitize) le jardin et
	      replante AVANT de répondre "ça pousse encore" ;
	  - cueillette : éclat de pétales + étincelles dorées + anneau lumineux
	    + "+X 🧠" qui monte (BillboardGui) ;
	  - VISITEURS : tout est visible (fleurs, minuteurs), rien n'est
	    cliquable (aucune invite, aucun ClickDetector) ;
	  - déco : allée de gravier et pas japonais, panneau en bois (SurfaceGui),
	    deux lanternes (vraie lumière la nuit), arrosoir, buissons, papillons,
	    moulin à vent (si le joueur a le moulin "Pinwheel") dont les pales
	    tournent.
	Performance : pièces ancrées, sans collision sauf les bords des bacs ;
	fleurs reconstruites seulement quand leur stade change (au plus 2
	parterres par image) ; animations à 20 Hz, en pause au-delà de ~110
	studs (les fleurs sont même retirées au-delà de ~150 studs) ; aucune
	allocation d'Instance par image ; AUCUN son.

	API :
	  GardenBuilder.new(parent, originCF, areaSize, isOwner, options?) -> Garden
	      originCF : centre du jardin de derrière au niveau de la pelouse,
	                 LookVector = vers la maison (= plotCF.LookVector) ;
	      areaSize : Vector2 (largeur X, profondeur Z) disponible ;
	      options  : { OwnerName: string?, OnHarvest: ((result) -> ())? }
	  garden:Update(gardenState)   (instantané GardenSnapshot, ou nil)
	  garden:SetFocus(position?)   (facultatif : sinon la caméra sert de repère)
	  garden:Destroy()             (aussi automatique si `parent` est détruit)
	  GardenBuilder.BackyardArea(plotCF) -> (originCF, areaSize)
	  GardenBuilder.BackyardCFrame(plotCF) -> originCF ; GardenBuilder.BACKYARD_SIZE (Vector2)
	  GardenBuilder.BuildFlower(flowerId, stage, scale?) -> Model
	      stage = "Seed" | "Sprout" | "Bud" | "Bloom" | "Ready" (ou 0..4) ;
	      modèle tourné vers -Z, pivot = bas centre (posé sur la terre),
	      PrimaryPart "Root", attributs FlowerId / Stage / TopHeight.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local GardenSnapshot = require(ReplicatedStorage.Shared.GardenSnapshot)

local GardenBuilder = {}
GardenBuilder.__index = GardenBuilder

local M = Enum.Material
local rad = math.rad
local TAU = math.pi * 2

-- Dimensions (studs)
local LAWN_TOP = 0.45 -- dessus de la pelouse de la parcelle (TownMap v9.4)
local BED_W, BED_D, BED_H = 6.2, 3.6, 1.4
local PLANK = 0.4
local BED_GAP = 3.6
local PATH_W = 3.4
local SOIL_TOP = BED_H - 0.12

-- Distances (studs) de la caméra au bord du jardin
local ANIM_RANGE = 110 -- animations
local SHOW_RANGE = 150 -- fleurs construites
local HIDE_RANGE = 175 -- fleurs retirées
local STEP = 1 / 20 -- 20 Hz
local BUILDS_PER_STEP = 2

-- Couleurs
local SOIL = Color3.fromRGB(96, 60, 38)
local SOIL_DARK = Color3.fromRGB(70, 42, 26)
local WOOD = Color3.fromRGB(184, 126, 78)
local WOOD_LIGHT = Color3.fromRGB(214, 160, 106)
local WOOD_DARK = Color3.fromRGB(128, 82, 48)
local STEM = Color3.fromRGB(78, 160, 72)
local LEAF = Color3.fromRGB(98, 186, 86)
local LEAF_DARK = Color3.fromRGB(62, 136, 62)
local GRAVEL = Color3.fromRGB(222, 208, 186)
local STONE = Color3.fromRGB(170, 166, 160)
local GOLD = Color3.fromRGB(255, 204, 64)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(86, 52, 40)

-- Pétales (même teintes que le jardin 2D) + détails de chaque fleur
local FLOWER_STYLE: { [string]: any } = {
	Daisy = { H = 1.7, Stem = 0.12, Tilt = 35, Petal = Color3.fromRGB(255, 252, 244), Center = Color3.fromRGB(255, 196, 40) },
	Tulip = { H = 2.0, Stem = 0.14, Tilt = 8, Petal = Color3.fromRGB(255, 96, 150), Inner = Color3.fromRGB(255, 160, 196) },
	Rose = { H = 2.1, Stem = 0.13, Tilt = 18, Petal = Color3.fromRGB(214, 28, 62), Inner = Color3.fromRGB(150, 14, 40) },
	Sunflower = { H = 3.9, Stem = 0.26, Tilt = 26, Petal = Color3.fromRGB(255, 196, 32), Inner = Color3.fromRGB(240, 160, 20), Center = Color3.fromRGB(104, 62, 26) },
	Lotus = { H = 0.55, Stem = 0.16, Tilt = 0, Petal = Color3.fromRGB(255, 204, 84), Inner = Color3.fromRGB(255, 234, 168), Center = Color3.fromRGB(255, 222, 120) },
}
local DEFAULT_STYLE = FLOWER_STYLE.Daisy
local STAGE_INDEX = { Seed = 0, Sprout = 1, Bud = 2, Bloom = 3, Ready = 4 }
local STAGE_NAMES = { [0] = "Seed", [1] = "Sprout", [2] = "Bud", [3] = "Bloom", [4] = "Ready" }

local flowersById: { [string]: any } = {}
for _, flower in ipairs(Config.Garden and Config.Garden.Flowers or {}) do
	flowersById[flower.Id] = flower
end

----------------------------------------------------------------------
-- Pièces
----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = solid == true
	part.CanQuery = solid == true
	part.CanTouch = false
	part.CastShadow = solid == true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	part.CFrame = cf
	part.Color = color
	part.Material = material or M.SmoothPlastic
	part.Parent = parent
	return part
end

-- Ovale : Part + SpecialMesh "Sphere" (une Ball de Roblox reste ronde)
local function egg(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local part = newPart(parent, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function ball(parent: Instance, name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	local part = newPart(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(position), color, material)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Disque (cylindre) dont l'axe suit le UpVector de `cf`
local function disc(parent: Instance, name: string, diameter: number, thickness: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local part = newPart(parent, name, Vector3.new(thickness, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Tube d'un point à un autre (tiges)
local function tube(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	local delta = b - a
	local length = math.max(0.05, delta.Magnitude)
	local direction = delta.Magnitude > 0.01 and delta.Unit or Vector3.new(0, 1, 0)
	local up = math.abs(direction.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt((a + b) / 2, (a + b) / 2 + direction, up) * CFrame.Angles(0, math.pi / 2, 0)
	local part = newPart(parent, name, Vector3.new(length, diameter, diameter), cf, color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

----------------------------------------------------------------------
-- Fleurs 3D
----------------------------------------------------------------------

-- Feuille ovale accrochée à la tige à la hauteur y, vers `yaw`, relevée de `lift`°
local function leaf(model: Instance, y: number, yaw: number, length: number, width: number, lift: number, color: Color3)
	local cf = CFrame.new(0, y, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, rad(lift)) * CFrame.new(length * 0.46, 0, 0)
	egg(model, "Leaf", Vector3.new(length, 0.06, width), cf, color, M.SmoothPlastic)
end

-- Feuille en lame (tulipe) qui part du pied
local function blade(model: Instance, yaw: number, length: number, width: number, lean: number, color: Color3)
	local cf = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, rad(lean)) * CFrame.new(0, length * 0.48, 0)
	egg(model, "Leaf", Vector3.new(width, length, 0.07), cf, color, M.SmoothPlastic)
end

-- Tête : repère dont le UpVector est la face de la fleur (penchée vers -Z)
local function headFrame(height: number, tilt: number): CFrame
	return CFrame.new(0, height, 0) * CFrame.Angles(-rad(tilt), 0, 0)
end

-- Couronne de pétales : `count` pétales à `radius` du centre, relevés de `lift`°
local function petalRing(model: Instance, head: CFrame, count: number, radius: number, size: Vector3, lift: number, color: Color3, offset: number?, y: number?)
	for i = 1, count do
		local a = (i - 1) / count * TAU + (offset or 0)
		local cf = head * CFrame.Angles(0, a, 0) * CFrame.new(0, y or 0, 0) * CFrame.Angles(0, 0, rad(lift)) * CFrame.new(radius, 0, 0)
		egg(model, "Petal", size, cf, color, M.SmoothPlastic)
	end
end

-- Pétales dressés en coupe (tulipe, rose, lotus) : `tilt`° vers l'extérieur
local function cupRing(model: Instance, head: CFrame, count: number, radius: number, size: Vector3, tilt: number, color: Color3, offset: number?, y: number?)
	for i = 1, count do
		local a = (i - 1) / count * TAU + (offset or 0)
		local cf = head * CFrame.Angles(0, a, 0) * CFrame.new(0, y or 0, -radius) * CFrame.Angles(-rad(tilt), 0, 0) * CFrame.new(0, size.Y * 0.45, 0)
		egg(model, "Petal", size, cf, color, M.SmoothPlastic)
	end
end

local function sparkles(parent: Part, color: Color3, rate: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Sparkle"
	attachment.Parent = parent
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(WHITE, color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.4, 0.32), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(0.4, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.8, 0)
	emitter.Rate = rate
	emitter.Parent = attachment
end

export type FlowerOptions = { Scale: number?, Detail: boolean?, Fx: boolean?, Hero: boolean? }

-- Construit la plante dans le repère du modèle (pied = origine), renvoie la hauteur
local function buildPlant(model: Model, flowerId: string, stage: number, opts: FlowerOptions): number
	local style = FLOWER_STYLE[flowerId] or DEFAULT_STYLE
	local detail = opts.Detail ~= false
	local hero = opts.Hero ~= false
	local s = 1 -- (mise à l'échelle faite à la fin par le modèle)

	-- Lotus : petite mare + nénuphars (pas de tige visible)
	if flowerId == "Lotus" then
		if hero then
			local water = disc(model, "Water", 2.5, 0.06, CFrame.new(0, 0.03, 0), Color3.fromRGB(104, 178, 224), M.Glass)
			water.Transparency = 0.25
			disc(model, "WaterRim", 2.75, 0.04, CFrame.new(0, 0.01, 0), Color3.fromRGB(120, 104, 90), M.Slate)
		end
		local padCount = stage == 0 and 1 or (stage == 1 and 2 or 3)
		for i = 1, padCount do
			local a = i * 2.1 + 0.4
			local r = stage == 0 and 0.3 or 0.62
			local d = (stage == 0 and 0.55 or (stage == 1 and 0.8 or 1.0)) * (hero and 1 or 0.8)
			disc(model, "Pad", d, 0.05, CFrame.new(math.cos(a) * r, 0.09 + i * 0.004, math.sin(a) * r), i % 2 == 0 and LEAF_DARK or LEAF, M.SmoothPlastic)
		end
		if stage == 0 then
			return 0.2
		end
		if stage == 1 then
			-- feuille enroulée qui sort de l'eau
			egg(model, "Curl", Vector3.new(0.16, 0.5, 0.16), CFrame.new(0.1, 0.3, -0.1) * CFrame.Angles(0, 0, rad(12)), LEAF, M.SmoothPlastic)
			return 0.55
		end
		local base = CFrame.new(0, 0.14, -0.05)
		tube(model, "Stem", Vector3.new(0, 0.06, -0.05), Vector3.new(0, 0.18 + (stage >= 3 and style.H or 0.35), -0.05), style.Stem, STEM)
		if stage == 2 then
			local bud = base * CFrame.new(0, 0.55, 0)
			egg(model, "Bud", Vector3.new(0.34, 0.7, 0.34), bud, lerp(style.Petal, Color3.fromRGB(255, 170, 150), 0.25), M.SmoothPlastic)
			egg(model, "BudTip", Vector3.new(0.18, 0.34, 0.18), bud * CFrame.new(0, 0.3, 0), style.Inner, M.SmoothPlastic)
			return 1.2
		end
		local head = base * CFrame.new(0, style.H, 0)
		cupRing(model, head, detail and 9 or 7, 0.16, Vector3.new(0.3, 0.72, 0.1), 62, lerp(style.Petal, WHITE, 0.1), 0, -0.05)
		cupRing(model, head, detail and 8 or 6, 0.1, Vector3.new(0.28, 0.66, 0.1), 36, style.Petal, math.pi / 8, 0)
		cupRing(model, head, detail and 6 or 4, 0.05, Vector3.new(0.22, 0.52, 0.09), 14, style.Inner, 0.3, 0.02)
		local core = egg(model, "Core", Vector3.new(0.3, 0.18, 0.3), head * CFrame.new(0, 0.16, 0), style.Center, stage == 4 and M.Neon or M.SmoothPlastic)
		if stage == 4 and opts.Fx then
			sparkles(core, GOLD, 5)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 214, 120)
			light.Range = 7
			light.Brightness = 1.2
			light.Shadows = false
			light.Parent = core
		end
		return style.H + 0.9
	end

	-- Graine : petite butte + graines
	if stage == 0 then
		egg(model, "Mound", Vector3.new(0.95, 0.34, 0.95), CFrame.new(0, 0.04, 0), SOIL_DARK, M.Ground)
		egg(model, "Seed", Vector3.new(0.16, 0.1, 0.22), CFrame.new(0.12, 0.17, -0.05) * CFrame.Angles(0, 0.6, 0), Color3.fromRGB(226, 196, 140), M.SmoothPlastic)
		if flowerId == "Sunflower" then
			egg(model, "Seed", Vector3.new(0.12, 0.08, 0.24), CFrame.new(-0.14, 0.16, 0.08) * CFrame.Angles(0, -0.4, 0), Color3.fromRGB(60, 46, 36), M.SmoothPlastic)
		end
		egg(model, "Nub", Vector3.new(0.1, 0.18, 0.1), CFrame.new(-0.04, 0.24, 0), LEAF, M.SmoothPlastic)
		return 0.35
	end

	local fullH = style.H * s
	local stemH = stage == 1 and math.max(0.45, fullH * 0.28) or (stage == 2 and fullH * 0.78 or fullH)
	local tilt = stage >= 3 and style.Tilt or style.Tilt * 0.4
	local head = headFrame(stemH, tilt)
	-- tige légèrement courbée : 2 tubes
	local bend = Vector3.new(0, stemH * 0.55, 0.04)
	local top = head.Position
	tube(model, "Stem", Vector3.new(0, 0, 0), bend, style.Stem, STEM)
	tube(model, "Stem", bend, top, style.Stem * 0.9, STEM)
	egg(model, "Base", Vector3.new(0.5, 0.14, 0.5), CFrame.new(0, 0.02, 0), SOIL_DARK, M.Ground)

	if stage == 1 then
		-- pousse : deux cotylédons
		local size = flowerId == "Sunflower" and 0.62 or 0.44
		leaf(model, stemH, 0.3, size, size * 0.5, 20, LEAF)
		leaf(model, stemH, 0.3 + math.pi, size, size * 0.5, 20, LEAF)
		egg(model, "Tip", Vector3.new(0.12, 0.16, 0.12), CFrame.new(0, stemH + 0.05, 0), lerp(LEAF, WHITE, 0.2), M.SmoothPlastic)
		return stemH + 0.2
	end

	-- feuilles
	if flowerId == "Tulip" then
		blade(model, 0.4, fullH * 0.62, 0.3, 14, LEAF)
		blade(model, 0.4 + math.pi, fullH * 0.55, 0.28, 18, LEAF_DARK)
		if detail then
			blade(model, 1.9, fullH * 0.45, 0.26, 22, LEAF)
		end
	elseif flowerId == "Sunflower" then
		local count = detail and 3 or 2
		for i = 1, count do
			local y = stemH * (0.22 + (i - 1) * 0.22)
			local yaw = i * 2.3
			leaf(model, y, yaw, 1.0, 0.78, 12, i % 2 == 0 and LEAF_DARK or LEAF)
			if detail then
				leaf(model, y + 0.1, yaw + math.pi, 0.9, 0.7, 14, LEAF)
			end
		end
	else
		local length = flowerId == "Rose" and 0.5 or 0.42
		leaf(model, stemH * 0.32, 0.5, length, length * 0.55, 24, LEAF)
		leaf(model, stemH * 0.5, 0.5 + math.pi, length, length * 0.55, 24, LEAF_DARK)
		if detail and stage >= 3 then
			leaf(model, stemH * 0.66, 2.2, length * 0.85, length * 0.5, 28, LEAF)
		end
	end

	-- bouton fermé
	if stage == 2 then
		local tipColor = lerp(style.Petal, LEAF, flowerId == "Daisy" and 0.15 or 0.35)
		if flowerId == "Sunflower" then
			disc(model, "BudDisc", 0.7, 0.2, head, LEAF_DARK, M.SmoothPlastic)
			petalRing(model, head, 8, 0.36, Vector3.new(0.3, 0.06, 0.14), 45, LEAF, 0, 0.02)
			egg(model, "BudTip", Vector3.new(0.4, 0.12, 0.4), head * CFrame.new(0, 0.1, 0), lerp(style.Petal, LEAF, 0.6), M.SmoothPlastic)
			return stemH + 0.5
		end
		egg(model, "Sepal", Vector3.new(0.3, 0.3, 0.3), head * CFrame.new(0, 0.08, 0), LEAF_DARK, M.SmoothPlastic)
		egg(model, "Bud", Vector3.new(0.26, 0.44, 0.26), head * CFrame.new(0, 0.3, 0), tipColor, M.SmoothPlastic)
		return stemH + 0.55
	end

	-- fleur ouverte
	if flowerId == "Daisy" then
		egg(model, "Center", Vector3.new(0.42, 0.2, 0.42), head * CFrame.new(0, 0.05, 0), style.Center, M.SmoothPlastic)
		petalRing(model, head, detail and 14 or 9, 0.4, Vector3.new(0.58, 0.06, 0.17), 8, style.Petal)
		if detail then
			petalRing(model, head, 7, 0.34, Vector3.new(0.5, 0.05, 0.15), 14, lerp(style.Petal, style.Center, 0.12), math.pi / 7, -0.02)
		end
		return stemH + 0.5
	elseif flowerId == "Tulip" then
		egg(model, "Sepal", Vector3.new(0.3, 0.18, 0.3), head, LEAF_DARK, M.SmoothPlastic)
		cupRing(model, head, 3, 0.1, Vector3.new(0.38, 0.8, 0.14), 16, style.Petal, 0, 0.02)
		cupRing(model, head, 3, 0.05, Vector3.new(0.34, 0.74, 0.13), 6, style.Inner, math.pi / 3, 0.04)
		egg(model, "Heart", Vector3.new(0.14, 0.26, 0.14), head * CFrame.new(0, 0.3, 0), Color3.fromRGB(255, 226, 120), M.SmoothPlastic)
		return stemH + 0.95
	elseif flowerId == "Rose" then
		petalRing(model, head, 5, 0.18, Vector3.new(0.3, 0.05, 0.1), -30, LEAF_DARK, 0.2, -0.04)
		cupRing(model, head, detail and 7 or 5, 0.2, Vector3.new(0.42, 0.36, 0.12), 58, lerp(style.Petal, WHITE, 0.08), 0, 0.02)
		cupRing(model, head, 5, 0.13, Vector3.new(0.34, 0.38, 0.11), 32, style.Petal, math.pi / 5, 0.06)
		cupRing(model, head, 4, 0.07, Vector3.new(0.26, 0.36, 0.1), 12, lerp(style.Petal, style.Inner, 0.5), 0.5, 0.1)
		egg(model, "Core", Vector3.new(0.2, 0.26, 0.2), head * CFrame.new(0, 0.26, 0), style.Inner, M.SmoothPlastic)
		return stemH + 0.7
	elseif flowerId == "Sunflower" then
		disc(model, "Back", 1.3, 0.16, head, LEAF_DARK, M.SmoothPlastic)
		petalRing(model, head, detail and 16 or 10, 0.82, Vector3.new(0.74, 0.06, 0.28), 6, style.Petal, 0, 0.09)
		if detail then
			petalRing(model, head, 12, 0.74, Vector3.new(0.66, 0.05, 0.26), 12, style.Inner, math.pi / 12, 0.05)
		end
		disc(model, "Disc", 1.06, 0.14, head * CFrame.new(0, 0.12, 0), style.Center, M.SmoothPlastic)
		egg(model, "Seeds", Vector3.new(0.78, 0.16, 0.78), head * CFrame.new(0, 0.19, 0), Color3.fromRGB(62, 36, 16), M.Fabric)
		return stemH + 0.9
	end
	return stemH + 0.5
end

local function stageNumber(stage: any): number
	if type(stage) == "number" then
		return math.clamp(math.floor(stage), 0, 4)
	end
	return STAGE_INDEX[tostring(stage)] or 3
end

-- Modèle d'une fleur (API publique : SETUP3D95 s'en sert pour les pots)
local function makeFlower(flowerId: string, stage: any, opts: FlowerOptions): Model
	local id = FLOWER_STYLE[flowerId] and flowerId or "Daisy"
	local stageN = stageNumber(stage)
	local model = Instance.new("Model")
	model.Name = "Flower_" .. id
	local root = newPart(model, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0.1, 0), WHITE, M.SmoothPlastic)
	root.Transparency = 1
	model.PrimaryPart = root
	local height = buildPlant(model, id, stageN, opts)
	-- balance des fleurs prêtes : plus grandes, étincelles (option Fx)
	local scale = (opts.Scale or 1) * (stageN == 4 and 1.08 or 1)
	if stageN == 4 and opts.Fx and id ~= "Lotus" then
		local head: Part? = nil
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and (child.Name == "Center" or child.Name == "Heart" or child.Name == "Core" or child.Name == "Seeds") then
				head = child
			end
		end
		if head then
			sparkles(head, GOLD, 4)
		end
	end
	if math.abs(scale - 1) > 0.001 then
		-- mise à l'échelle autour du pied (pas de ScaleTo : ça marche partout)
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child ~= root then
				local cf = child.CFrame
				child.Size *= scale
				child.CFrame = CFrame.new(cf.Position * scale) * cf.Rotation
			end
		end
	end
	model.WorldPivot = CFrame.identity
	model:SetAttribute("FlowerId", id)
	model:SetAttribute("Stage", STAGE_NAMES[stageN])
	model:SetAttribute("TopHeight", height * scale)
	return model
end

function GardenBuilder.BuildFlower(flowerId: string, stage: any, scale: number?): Model
	return makeFlower(flowerId, stage, { Scale = scale or 1, Detail = true, Fx = true, Hero = true })
end

----------------------------------------------------------------------
-- Jardin de derrière : où, quelle taille
----------------------------------------------------------------------

function GardenBuilder.BackyardArea(plotCF: CFrame): (CFrame, Vector2)
	-- (repère de la parcelle : LookVector = vers la place ; +Z = vers le fond)
	local front = WorldLayout.HouseFrontOffset()
	local depth = (WorldLayout.DEPTH or 20) + 2 * (WorldLayout.WALL_T or 1)
	local okDims, dims = pcall(WorldLayout.Dims, nil)
	if okDims and type(dims) == "table" and type(dims.Depth) == "number" then
		depth = dims.Depth
	end
	local back = -front + depth + 2.5 -- dos de la maison + un passage
	local edge = WorldLayout.PLOT_D / 2 - 1.5 -- clôture du fond
	if edge - back < 14 then
		back = edge - 14
	end
	local center = (back + edge) / 2
	return plotCF * CFrame.new(0, LAWN_TOP, center), Vector2.new(WorldLayout.PLOT_W - 8, edge - back)
end

-- (noms utilisés par TownClient : même calcul)
function GardenBuilder.BackyardCFrame(plotCF: CFrame): CFrame
	local cf = GardenBuilder.BackyardArea(plotCF)
	return cf
end
local _, backyardSize = GardenBuilder.BackyardArea(CFrame.identity)
GardenBuilder.BACKYARD_SIZE = backyardSize

----------------------------------------------------------------------
-- Heure du serveur, textes
----------------------------------------------------------------------

local function rawServerNow(): number
	local ok, value = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(value) == "number" and value == value then
		return value
	end
	return os.time()
end

local function clockText(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return string.format("%dh%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function flowerLabel(flowerId: string): string
	local flower = flowersById[flowerId]
	if not flower then
		return ""
	end
	return tostring(flower.Icon or "🌸") .. " " .. Locale.T(flower.Name)
end

local function plotsUpgradeName(): string
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		if upgrade.Feature == "GardenPlots" then
			return Locale.T(upgrade.Name)
		end
	end
	return Locale.T("Flower Beds")
end

----------------------------------------------------------------------
-- Objet jardin
----------------------------------------------------------------------

export type Bed = {
	Index: number,
	Kind: string, -- "Plot" | "Ghost" | "Locked"
	CF: CFrame, -- base du bac (pelouse), monde
	Model: Model,
	Plants: Model?,
	Hero: Model?,
	HeroCF: CFrame,
	Tag: BasePart?,
	Hitbox: Part,
	Billboard: BillboardGui,
	Title: TextLabel,
	Timer: TextLabel,
	Bar: Frame,
	Fill: Frame,
	Prompt: ProximityPrompt?,
	Flower: string,
	Key: string,
	Stage: string,
	Dirty: boolean,
	Pending: boolean,
	TopHeight: number,
	Phase: number,
}

export type Garden = typeof(setmetatable({} :: {
	Model: Model,
	Origin: CFrame,
	Area: Vector2,
	IsOwner: boolean,
	Options: any,
	State: any,
	LayoutKey: string,
	Beds: { Bed },
	Layout: Folder?,
	Blades: Model?,
	BladesCF: CFrame,
	Butterflies: { any },
	Lights: { PointLight },
	SignPrompt: ProximityPrompt?,
	SignSub: TextLabel?,
	Connections: { RBXScriptConnection },
	Focus: Vector3?,
	FocusUntil: number,
	Near: boolean,
	Animate: boolean,
	Clock: number,
	Tick: number,
	Slow: number,
	ClockOffset: number,
	HarvestingAll: boolean,
	Destroyed: boolean,
}, GardenBuilder))

function GardenBuilder.new(parent: Instance, originCF: CFrame, areaSize: Vector2, isOwner: boolean, options: any?): Garden
	local self = setmetatable({}, GardenBuilder) :: any
	self.Origin = originCF
	self.Area = areaSize
	self.IsOwner = isOwner == true
	self.Options = type(options) == "table" and options or {}
	self.State = GardenSnapshot.Sanitize(nil)
	self.LayoutKey = ""
	self.Beds = {}
	self.Butterflies = {}
	self.Lights = {}
	self.Connections = {}
	self.BladesCF = CFrame.identity
	self.FocusUntil = 0
	self.Near = true
	self.Animate = true
	self.Clock = 0
	self.Tick = 0
	self.Slow = 0
	self.ClockOffset = 0
	self.HarvestingAll = false
	self.Destroyed = false

	local model = Instance.new("Model")
	model.Name = "DopamineGarden"
	model:SetAttribute("IsOwner", self.IsOwner)
	self.Model = model

	self:_layout()
	model.Parent = parent

	table.insert(self.Connections, RunService.Heartbeat:Connect(function(dt)
		self:_heartbeat(dt)
	end))
	-- la maison (parent) détruite sans nous : on se nettoie
	table.insert(self.Connections, model.Destroying:Connect(function()
		self:Destroy()
	end))
	return self
end

function GardenBuilder._now(self: Garden): number
	return rawServerNow() + self.ClockOffset
end

-- Instantané (GardenSnapshot) -> reconstruit ce qui a changé
function GardenBuilder.Update(self: Garden, gardenState: any)
	if self.Destroyed then
		return
	end
	local state = GardenSnapshot.Sanitize(gardenState)
	self.State = state
	local key = table.concat({ tostring(state.Unlocked), state.Count, state.Max, tostring(state.Windmill) }, "|")
	if key ~= self.LayoutKey then
		self:_layout()
	end
	for _, bed in ipairs(self.Beds) do
		if bed.Kind == "Plot" then
			local plot = state.Plots[bed.Index]
			local flower = plot and plot.Flower or ""
			local plotKey = flower .. "|" .. tostring(plot and plot.PlantedAt or 0)
			if plotKey ~= bed.Key then
				bed.Key = plotKey
				bed.Flower = flower
				bed.Stage = ""
				bed.Dirty = true
				if bed.Tag then
					local style = FLOWER_STYLE[flower]
					bed.Tag.Color = style and style.Petal or WOOD_LIGHT
				end
			end
		end
	end
	self:_refreshStages(true)
end

function GardenBuilder.SetFocus(self: Garden, position: Vector3?)
	self.Focus = position
	self.FocusUntil = os.clock() + 2
end

----------------------------------------------------------------------
-- Construction du jardin (bacs, allée, déco)
----------------------------------------------------------------------

-- Emplacements des bacs (repère du jardin) : 1 rangée jusqu'à 5, sinon 2
-- (de part et d'autre de l'allée ; les fleurs regardent toujours l'allée)
local function bedSlots(total: number, area: Vector2): ({ CFrame }, number, number)
	local slots = {}
	local rows = total <= 5 and 1 or 2
	local perRow = math.ceil(total / rows)
	local pitch = math.min(BED_W + BED_GAP, (area.X - 24) / math.max(1, perRow))
	local rowZ = rows == 1 and { 1.6 } or { -(PATH_W / 2 + 0.9 + BED_D / 2), PATH_W / 2 + 0.9 + BED_D / 2 }
	local pathZ = rows == 1 and (1.6 - BED_D / 2 - 0.9 - PATH_W / 2) or 0
	local index = 0
	for row = 1, rows do
		local count = math.min(perRow, total - index)
		for k = 1, count do
			index += 1
			-- 1er parterre à GAUCHE pour qui regarde le jardin depuis la maison (+X local à gauche)
			local x = ((count + 1) / 2 - k) * pitch
			local facePath = rows == 2 and row == 1 -- rangée côté maison : tournée vers l'allée
			slots[index] = CFrame.new(x, 0, rowZ[row]) * CFrame.Angles(0, facePath and math.pi or 0, 0)
		end
	end
	local halfLength = perRow * pitch / 2
	return slots, pathZ, halfLength
end

local function billboardFor(bed: any, parent: Part)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BedLabel"
	gui.Size = UDim2.fromScale(5, 1.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Adornee = parent
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.98, 0.94)
	card.BackgroundColor3 = Color3.fromRGB(255, 251, 244)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = WOOD
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.06, 0.06)
	title.Size = UDim2.fromScale(0.88, 0.46)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = INK
	title.Text = ""
	title.Parent = card
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0.08, 0.58)
	bar.Size = UDim2.fromScale(0.84, 0.3)
	bar.BackgroundColor3 = Color3.fromRGB(234, 222, 206)
	bar.BorderSizePixel = 0
	bar.Parent = card
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 204, 96)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.BackgroundTransparency = 1
	timer.Position = UDim2.fromScale(0.08, 0.54)
	timer.Size = UDim2.fromScale(0.84, 0.38)
	timer.Font = Enum.Font.GothamBold
	timer.TextScaled = true
	timer.TextColor3 = INK
	timer.TextStrokeColor3 = WHITE
	timer.TextStrokeTransparency = 0.4
	timer.Text = ""
	timer.ZIndex = 2
	timer.Parent = card
	gui.Parent = parent
	bed.Billboard = gui
	bed.Title = title
	bed.Timer = timer
	bed.Bar = bar
	bed.Fill = fill
end

-- Un bac surélevé (planches, poteaux, terre, herbe, étiquette)
function GardenBuilder._buildBed(self: Garden, folder: Instance, index: number, kind: string, localCF: CFrame): any
	local cf = self.Origin * localCF
	local model = Instance.new("Model")
	model.Name = kind == "Plot" and ("Bed_" .. index) or ("Bed_" .. kind)
	local ghost = kind == "Ghost"
	local wood = ghost and Color3.fromRGB(226, 206, 180) or WOOD
	local woodLight = ghost and Color3.fromRGB(236, 222, 200) or WOOD_LIGHT
	local w, d, h = BED_W, BED_D, BED_H
	-- planches (2 rangées par côté : on voit les lattes)
	for row = 1, 2 do
		local y = (row - 0.5) * h / 2
		local shade = row == 1 and wood or lerp(wood, woodLight, 0.35)
		for _, side in ipairs({ -1, 1 }) do
			newPart(model, "Plank", Vector3.new(w, h / 2 - 0.05, PLANK), cf * CFrame.new(0, y, side * (d / 2 - PLANK / 2)), shade, M.WoodPlanks, true)
			newPart(model, "Plank", Vector3.new(PLANK, h / 2 - 0.05, d - 2 * PLANK), cf * CFrame.new(side * (w / 2 - PLANK / 2), y, 0), shade, M.WoodPlanks, true)
		end
	end
	-- rebord (chapeau) et poteaux d'angle
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, "Cap", Vector3.new(w + 0.2, 0.14, 0.6), cf * CFrame.new(0, h + 0.07, side * (d / 2 - 0.2)), woodLight, M.Wood)
		newPart(model, "Cap", Vector3.new(0.6, 0.14, d - 0.8), cf * CFrame.new(side * (w / 2 - 0.2), h + 0.07, 0), woodLight, M.Wood)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			newPart(model, "Post", Vector3.new(0.62, h + 0.36, 0.62), cf * CFrame.new(sx * (w / 2 - 0.2), (h + 0.36) / 2, sz * (d / 2 - 0.2)), WOOD_DARK, M.Wood)
		end
	end
	-- terre
	if not ghost then
		local soil = newPart(model, "Soil", Vector3.new(w - 2 * PLANK, SOIL_TOP, d - 2 * PLANK), cf * CFrame.new(0, SOIL_TOP / 2, 0), SOIL, M.Ground, true)
		soil.CastShadow = false
		-- sillons
		for k = -1, 1 do
			newPart(model, "Furrow", Vector3.new(w - 2 * PLANK - 0.4, 0.06, 0.18), cf * CFrame.new(0, SOIL_TOP + 0.02, k * 0.95), SOIL_DARK, M.Ground)
		end
		-- touffes d'herbe aux coins du fond
		for _, sx in ipairs({ -1, 1 }) do
			egg(model, "Tuft", Vector3.new(0.9, 0.55, 0.7), cf * CFrame.new(sx * (w / 2 - 0.85), SOIL_TOP + 0.12, d / 2 - 0.75), LEAF_DARK, M.Grass)
		end
	else
		local soil = newPart(model, "Soil", Vector3.new(w - 2 * PLANK, 0.3, d - 2 * PLANK), cf * CFrame.new(0, 0.15, 0), Color3.fromRGB(150, 128, 104), M.Ground)
		soil.Transparency = 0.2
	end
	-- étiquette plantée (couleur de la fleur)
	local tag: BasePart? = nil
	if kind == "Plot" then
		local stake = cf * CFrame.new(w / 2 - 0.9, SOIL_TOP, -(d / 2 - 0.75))
		newPart(model, "Stake", Vector3.new(0.12, 1.0, 0.12), stake * CFrame.new(0, 0.3, 0), WOOD_LIGHT, M.Wood)
		tag = newPart(model, "Tag", Vector3.new(0.6, 0.4, 0.08), stake * CFrame.new(0, 0.86, 0) * CFrame.Angles(rad(-15), 0, 0), WOOD_LIGHT, M.SmoothPlastic)
	end
	-- boîte invisible : clic + invite + étiquette flottante
	local hitbox = newPart(model, "Hitbox", Vector3.new(w, h + 3, d), cf * CFrame.new(0, (h + 3) / 2, 0), WHITE, M.SmoothPlastic)
	hitbox.Transparency = 1
	hitbox.CanQuery = self.IsOwner
	model.PrimaryPart = hitbox
	model.Parent = folder

	local bed: any = {
		Index = index,
		Kind = kind,
		CF = cf,
		Model = model,
		HeroCF = cf * CFrame.new(0, SOIL_TOP, 0.15),
		Tag = tag,
		Hitbox = hitbox,
		Flower = "",
		Key = "",
		Stage = "",
		Dirty = kind == "Plot",
		Pending = false,
		TopHeight = 0,
		Phase = index * 1.37,
	}
	billboardFor(bed, hitbox)
	if kind == "Ghost" then
		bed.Title.Text = "🔒 +1 🪴"
		bed.Bar.Visible = false
		bed.Timer.Text = plotsUpgradeName()
		bed.Billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	elseif kind == "Locked" then
		bed.Title.Text = "🔒 " .. Locale.T("Dopamine Garden")
		bed.Bar.Visible = false
		bed.Timer.Text = Locale.T("The garden isn't unlocked yet")
		bed.Billboard.Enabled = index == 2
		bed.Billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	end

	-- propriétaire : invite + clic
	if self.IsOwner and kind == "Plot" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GardenPrompt"
		prompt.ActionText = Locale.T("Harvest")
		prompt.ObjectText = ""
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = hitbox
		table.insert(self.Connections, prompt.Triggered:Connect(function()
			self:_activate(index)
		end))
		bed.Prompt = prompt
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 26
		click.Parent = hitbox
		table.insert(self.Connections, click.MouseClick:Connect(function()
			self:_activate(index)
		end))
	end
	return bed
end

function GardenBuilder._buildDecor(self: Garden, folder: Instance, pathZ: number, halfLength: number, rows: number)
	local O = self.Origin
	local length = halfLength * 2 + 10
	-- allée de gravier + pas japonais
	newPart(folder, "Path", Vector3.new(length, 0.12, PATH_W), O * CFrame.new(0, 0.06, pathZ), GRAVEL, M.Pebble)
	for _, side in ipairs({ -1, 1 }) do
		newPart(folder, "PathEdge", Vector3.new(length, 0.2, 0.22), O * CFrame.new(0, 0.1, pathZ + side * (PATH_W / 2 + 0.1)), Color3.fromRGB(196, 184, 170), M.Slate)
	end
	local stones = math.floor(length / 3.4)
	for k = 1, stones do
		local x = -length / 2 + (k - 0.5) * (length / stones)
		local stone = disc(folder, "Stone", 1.7 + (k % 3) * 0.2, 0.12, O * CFrame.new(x, 0.16, pathZ + ((k % 2) - 0.5) * 0.5), STONE, M.Slate)
		stone.CastShadow = false
	end

	-- panneau en bois (début de l'allée, côté gauche vu de la maison)
	local signX = halfLength + 3.2
	local signCF = O * CFrame.new(signX, 0, pathZ - PATH_W / 2 - 1.4) * CFrame.Angles(0, rad(-12), 0)
	for _, sx in ipairs({ -1, 1 }) do
		newPart(folder, "SignPost", Vector3.new(0.35, 4.2, 0.35), signCF * CFrame.new(sx * 2.4, 2.1, 0), WOOD_DARK, M.Wood, true)
	end
	local board = newPart(folder, "SignBoard", Vector3.new(5.6, 2.4, 0.3), signCF * CFrame.new(0, 3.1, 0), WOOD_LIGHT, M.WoodPlanks, true)
	newPart(folder, "SignRoof", Vector3.new(6.2, 0.22, 0.8), signCF * CFrame.new(0, 4.4, 0), WOOD_DARK, M.Wood)
	for k = 1, 3 do
		egg(folder, "SignFlower", Vector3.new(0.5, 0.5, 0.5), signCF * CFrame.new(-2 + k * 1.0, 4.62, -0.15), ({ Color3.fromRGB(255, 110, 160), GOLD, WHITE })[k], M.SmoothPlastic)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "GardenSign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.4
	gui.MaxDistance = 120
	gui.ResetOnSpawn = false
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.08)
	title.Size = UDim2.fromScale(0.9, 0.5)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(92, 50, 30)
	title.Text = "🌻 " .. Locale.T("Dopamine Garden")
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0.08, 0.6)
	sub.Size = UDim2.fromScale(0.84, 0.3)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(128, 76, 48)
	sub.Text = ""
	sub.Parent = gui
	gui.Parent = board
	self.SignSub = sub
	if self.IsOwner then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HarvestAll"
		prompt.ActionText = Locale.T("🧺 Harvest all (%d)", 2)
		prompt.ObjectText = Locale.T("Dopamine Garden")
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = board
		table.insert(self.Connections, prompt.Triggered:Connect(function()
			self:_harvestAll()
		end))
		self.SignPrompt = prompt
	end

	-- lanternes aux deux bouts de l'allée (allumées la nuit)
	for _, side in ipairs({ -1, 1 }) do
		local p = O * CFrame.new(side * (halfLength + 1.2), 0, pathZ + PATH_W / 2 + 0.9)
		newPart(folder, "LanternPost", Vector3.new(0.3, 3.6, 0.3), p * CFrame.new(0, 1.8, 0), Color3.fromRGB(70, 64, 70), M.Metal, true)
		newPart(folder, "LanternTop", Vector3.new(0.9, 0.18, 0.9), p * CFrame.new(0, 4.25, 0), Color3.fromRGB(70, 64, 70), M.Metal)
		local lamp = newPart(folder, "Lamp", Vector3.new(0.62, 0.7, 0.62), p * CFrame.new(0, 3.8, 0), Color3.fromRGB(255, 226, 160), M.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 214, 150)
		light.Range = 14
		light.Brightness = 1.4
		light.Shadows = false
		light.Enabled = false
		light.Parent = lamp
		table.insert(self.Lights, light)
	end

	-- buissons ronds aux coins, arrosoir près du 1er bac
	local backZ = rows == 1 and (1.6 + BED_D / 2 + 1.6) or (PATH_W / 2 + 0.9 + BED_D + 1.4)
	for _, side in ipairs({ -1, 1 }) do
		local base = O * CFrame.new(side * (halfLength + 2.4), 0, backZ)
		ball(folder, "Bush", 2.6, (base * CFrame.new(0, 1.1, 0)).Position, LEAF_DARK, M.Grass)
		ball(folder, "Bush", 1.9, (base * CFrame.new(side * 1.1, 0.8, -0.8)).Position, LEAF, M.Grass)
		for k = 1, 3 do
			ball(folder, "Berry", 0.36, (base * CFrame.new(math.cos(k * 2.1) * 1.05, 1.5 + (k % 2) * 0.4, -0.95 + math.sin(k) * 0.3)).Position, Color3.fromRGB(255, 120, 170), M.SmoothPlastic)
		end
	end
	local canCF = O * CFrame.new(halfLength - 1.5, 0, pathZ - PATH_W / 2 + 0.2) * CFrame.Angles(0, rad(-30), 0)
	local can = Color3.fromRGB(96, 190, 220)
	local body = newPart(folder, "CanBody", Vector3.new(0.9, 0.9, 0.9), canCF * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), can, M.Metal)
	body.Shape = Enum.PartType.Cylinder
	tube(folder, "CanSpout", (canCF * CFrame.new(0.3, 0.35, 0)).Position, (canCF * CFrame.new(1.1, 0.95, 0)).Position, 0.14, can, M.Metal)
	disc(folder, "CanRose", 0.3, 0.08, canCF * CFrame.new(1.15, 1.0, 0) * CFrame.Angles(0, 0, rad(-50)), lerp(can, WHITE, 0.3), M.Metal)
	tube(folder, "CanHandle", (canCF * CFrame.new(-0.3, 0.9, 0)).Position, (canCF * CFrame.new(0.15, 1.05, 0)).Position, 0.1, lerp(can, Color3.new(0, 0, 0), 0.2), M.Metal)

	-- moulin à vent (le moulin "Pinwheel" du clicker)
	if self.State.Windmill then
		local mill = O * CFrame.new(-(halfLength + 6.5), 0, backZ - 0.5)
		newPart(folder, "MillBase", Vector3.new(3.2, 0.5, 3.2), mill * CFrame.new(0, 0.25, 0), STONE, M.Slate, true)
		newPart(folder, "MillTower", Vector3.new(2.6, 2.6, 2.6), mill * CFrame.new(0, 1.8, 0), Color3.fromRGB(255, 246, 236), M.WoodPlanks, true)
		newPart(folder, "MillTower", Vector3.new(2.1, 2.2, 2.1), mill * CFrame.new(0, 4.2, 0), Color3.fromRGB(255, 236, 226), M.WoodPlanks, true)
		newPart(folder, "MillTower", Vector3.new(1.7, 1.8, 1.7), mill * CFrame.new(0, 6.2, 0), Color3.fromRGB(255, 226, 214), M.WoodPlanks, true)
		local roof = Instance.new("WedgePart")
		roof.Name = "MillRoof"
		roof.Anchored = true
		roof.CanCollide = false
		roof.CanQuery = false
		roof.CanTouch = false
		roof.Size = Vector3.new(2.2, 1.4, 1.1)
		roof.CFrame = mill * CFrame.new(0, 7.8, -0.55)
		roof.Color = Color3.fromRGB(236, 104, 140)
		roof.Material = M.SmoothPlastic
		roof.Parent = folder
		local roof2 = roof:Clone()
		roof2.CFrame = mill * CFrame.new(0, 7.8, 0.55) * CFrame.Angles(0, math.pi, 0)
		roof2.Parent = folder
		newPart(folder, "MillDoor", Vector3.new(0.9, 1.5, 0.1), mill * CFrame.new(0, 1.3, -1.32), WOOD_DARK, M.Wood)
		newPart(folder, "MillWindow", Vector3.new(0.6, 0.6, 0.1), mill * CFrame.new(0, 4.3, -1.07), Color3.fromRGB(170, 216, 255), M.Glass)
		-- pales : un modèle qui tourne autour de l'axe Z (vers la maison)
		local hubCF = mill * CFrame.new(0, 6.4, -1.2)
		local blades = Instance.new("Model")
		blades.Name = "Blades"
		local hub = newPart(blades, "Hub", Vector3.new(0.5, 0.5, 0.5), hubCF, WOOD_DARK, M.Wood)
		hub.Shape = Enum.PartType.Ball
		for k = 0, 3 do
			local arm = hubCF * CFrame.Angles(0, 0, k * math.pi / 2)
			newPart(blades, "Arm", Vector3.new(0.2, 3.2, 0.12), arm * CFrame.new(0, 1.7, 0), WOOD_DARK, M.Wood)
			newPart(blades, "Sail", Vector3.new(0.9, 2.5, 0.06), arm * CFrame.new(0.52, 1.95, 0.02), k % 2 == 0 and Color3.fromRGB(255, 250, 244) or Color3.fromRGB(255, 196, 214), M.Fabric)
		end
		blades.PrimaryPart = hub
		blades.Parent = folder
		self.Blades = blades
		self.BladesCF = hubCF
	end

	-- papillons (visibles quand une fleur est ouverte)
	for k = 1, 2 do
		local fly = Instance.new("Model")
		fly.Name = "Butterfly"
		local color = k == 1 and Color3.fromRGB(255, 150, 200) or Color3.fromRGB(160, 200, 255)
		local bodyPart = egg(fly, "Body", Vector3.new(0.1, 0.1, 0.42), O, Color3.fromRGB(60, 40, 50), M.SmoothPlastic)
		local left = egg(fly, "Wing", Vector3.new(0.5, 0.04, 0.44), O, color, M.SmoothPlastic)
		local right = egg(fly, "Wing", Vector3.new(0.5, 0.04, 0.44), O, color, M.SmoothPlastic)
		fly.Parent = folder
		table.insert(self.Butterflies, { Body = bodyPart, Left = left, Right = right, Phase = k * 2.4, Bed = 0 })
	end
end

function GardenBuilder._layout(self: Garden)
	if self.Layout then
		self.Layout:Destroy()
	end
	table.clear(self.Beds)
	table.clear(self.Butterflies)
	table.clear(self.Lights)
	self.Blades = nil
	self.SignPrompt = nil
	self.SignSub = nil
	-- (les connexions des anciennes invites partent avec leurs Instances)
	local state = self.State
	self.LayoutKey = table.concat({ tostring(state.Unlocked), state.Count, state.Max, tostring(state.Windmill) }, "|")
	local folder = Instance.new("Folder")
	folder.Name = "Layout"
	local kinds = {}
	if state.Unlocked then
		for index = 1, state.Count do
			kinds[index] = "Plot"
		end
		if state.Count < state.Max then
			table.insert(kinds, "Ghost")
		end
	else
		for index = 1, math.max(1, (Config.Garden and Config.Garden.BasePlots) or 3) do
			kinds[index] = "Locked"
		end
	end
	local slots, pathZ, halfLength = bedSlots(#kinds, self.Area)
	local beds = Instance.new("Folder")
	beds.Name = "Beds"
	beds.Parent = folder
	for index, kind in ipairs(kinds) do
		table.insert(self.Beds, self:_buildBed(beds, index, kind, slots[index]))
	end
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder
	self:_buildDecor(decor, pathZ, halfLength, #kinds <= 5 and 1 or 2)
	if self.SignSub then
		local name = self.Options.OwnerName
		if not state.Unlocked then
			self.SignSub.Text = Locale.T("🔒 Unlock the Dopamine Garden")
		elseif type(name) == "string" and name ~= "" then
			self.SignSub.Text = Locale.T("%s's garden", name)
		else
			self.SignSub.Text = "🌷 " .. Locale.T("Dopamine Garden")
		end
	end
	folder.Parent = self.Model
	self.Layout = folder
end

----------------------------------------------------------------------
-- Stades, étiquettes, fleurs
----------------------------------------------------------------------

function GardenBuilder._buildPlants(self: Garden, bed: any)
	if bed.Plants then
		bed.Plants:Destroy()
		bed.Plants = nil
		bed.Hero = nil
	end
	if bed.Flower == "" or not self.Near then
		return
	end
	local stage = bed.Stage
	local plants = Instance.new("Model")
	plants.Name = "Plants"
	local lotus = bed.Flower == "Lotus"
	local hero = makeFlower(bed.Flower, stage, { Scale = lotus and 1.3 or 1.4, Detail = true, Fx = true, Hero = true })
	hero.Name = "Hero"
	hero:PivotTo(bed.HeroCF)
	hero.Parent = plants
	bed.Hero = hero
	bed.TopHeight = tonumber(hero:GetAttribute("TopHeight")) or 1
	-- deux compagnes plus petites (tournées un peu différemment)
	for _, side in ipairs({ -1, 1 }) do
		local mate = makeFlower(bed.Flower, stage, { Scale = lotus and 0.75 or 1.0, Detail = false, Fx = false, Hero = not lotus })
		mate.Name = "Mate"
		mate:PivotTo(bed.CF * CFrame.new(side * BED_W * 0.31, SOIL_TOP, lotus and 0.3 or -0.3) * CFrame.Angles(0, side * rad(22), 0))
		mate.Parent = plants
	end
	-- feuillage bas entre les plantes (la terre ne paraît pas vide)
	if not lotus and stage ~= "Seed" then
		for k, spot in ipairs({ Vector3.new(-0.17, 0, 0.55), Vector3.new(0.17, 0, 0.6), Vector3.new(0, 0, -0.75) }) do
			local size = Vector3.new(1.3, 0.55, 0.85) * (stage == "Sprout" and 0.6 or 1)
			egg(plants, "Foliage", size, bed.CF * CFrame.new(spot.X * BED_W, SOIL_TOP + 0.1, spot.Z * BED_D * 0.5) * CFrame.Angles(0, k * 0.9, 0), k == 2 and LEAF or LEAF_DARK, M.Grass)
		end
	end
	plants.Parent = bed.Model
	bed.Plants = plants
end

-- Met à jour les étiquettes et (si besoin) les stades ; `force` = tout de suite
function GardenBuilder._refreshStages(self: Garden, force: boolean?)
	local now = self:_now()
	local readyCount = 0
	for _, bed in ipairs(self.Beds) do
		if bed.Kind == "Plot" then
			local plot = self.State.Plots[bed.Index]
			local stage = GardenSnapshot.Stage(plot, now)
			if stage ~= bed.Stage then
				bed.Stage = stage
				bed.Dirty = true
			end
			local progress, ready, remaining = GardenSnapshot.Progress(plot, now)
			if ready then
				readyCount += 1
			end
			local label = flowerLabel(bed.Flower)
			if bed.Flower == "" then
				bed.Title.Text = Locale.T("🌱 Empty bed")
				bed.Bar.Visible = false
				bed.Timer.Text = self.IsOwner and Locale.T("Plant") or ""
			elseif ready then
				bed.Title.Text = label
				bed.Bar.Visible = false
				bed.Timer.Text = "✨ " .. Locale.T("READY!")
				bed.Timer.TextColor3 = Color3.fromRGB(214, 140, 0)
			else
				bed.Title.Text = label
				bed.Bar.Visible = true
				bed.Fill.Size = UDim2.fromScale(math.max(0.04, progress), 1)
				bed.Timer.Text = "⏱️ " .. clockText(remaining)
				bed.Timer.TextColor3 = INK
			end
			bed.Billboard.StudsOffsetWorldSpace = Vector3.new(0, SOIL_TOP + math.max(1.2, bed.TopHeight) + 1.3, 0)
			local prompt = bed.Prompt
			if prompt then
				local canAct = (bed.Flower == "" or ready) and not bed.Pending
				prompt.Enabled = canAct
				if bed.Flower == "" then
					prompt.ActionText = Locale.T("Plant")
					prompt.ObjectText = Locale.T("🌱 Empty bed")
				else
					prompt.ActionText = Locale.T("Harvest")
					prompt.ObjectText = label
				end
			end
		end
	end
	if self.SignPrompt then
		self.SignPrompt.Enabled = readyCount >= 2 and not self.HarvestingAll
		self.SignPrompt.ActionText = Locale.T("🧺 Harvest all (%d)", readyCount)
	end
	-- lanternes : la nuit seulement (et quand on est près)
	local clock = Lighting.ClockTime
	local night = clock < 6.3 or clock > 17.7
	for _, light in ipairs(self.Lights) do
		light.Enabled = night and self.Near
	end
	if force then
		self:_buildDirty(#self.Beds)
	end
end

function GardenBuilder._buildDirty(self: Garden, budget: number)
	local built = 0
	for _, bed in ipairs(self.Beds) do
		if built >= budget then
			return
		end
		if bed.Dirty and bed.Kind == "Plot" then
			bed.Dirty = false
			if bed.Stage == "" then
				bed.Stage = GardenSnapshot.Stage(self.State.Plots[bed.Index], self:_now())
			end
			self:_buildPlants(bed)
			built += 1
		end
	end
end

----------------------------------------------------------------------
-- Boucle (20 Hz) : distance, animations
----------------------------------------------------------------------

function GardenBuilder._focus(self: Garden): Vector3?
	if self.Focus and os.clock() < self.FocusUntil then
		return self.Focus
	end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

function GardenBuilder._heartbeat(self: Garden, dt: number)
	if self.Destroyed then
		return
	end
	self.Clock += dt
	if self.Clock < STEP then
		return
	end
	local elapsed = self.Clock
	self.Clock = 0
	self.Tick += elapsed
	self.Slow += elapsed

	-- distance (2 fois / s) : fleurs retirées de loin, animations en pause
	if self.Slow >= 0.5 then
		self.Slow = 0
		local focus = self:_focus()
		if focus then
			local distance = (focus - self.Origin.Position).Magnitude - self.Area.X * 0.25
			self.Animate = distance < ANIM_RANGE
			if self.Near and distance > HIDE_RANGE then
				self.Near = false
				for _, bed in ipairs(self.Beds) do
					if bed.Plants then
						bed.Plants:Destroy()
						bed.Plants = nil
						bed.Hero = nil
					end
					bed.Billboard.Enabled = false
				end
				for _, fly in ipairs(self.Butterflies) do
					fly.Body.Transparency = 1
					fly.Left.Transparency = 1
					fly.Right.Transparency = 1
				end
			elseif not self.Near and distance < SHOW_RANGE then
				self.Near = true
				for _, bed in ipairs(self.Beds) do
					bed.Dirty = bed.Kind == "Plot"
					bed.Billboard.Enabled = bed.Kind ~= "Locked" or bed.Index == 2
				end
			end
		end
		if self.Near then
			self:_refreshStages(false)
		end
	end
	if not self.Near then
		return
	end
	self:_buildDirty(BUILDS_PER_STEP)
	if not self.Animate then
		return
	end
	local t = self.Tick
	-- fleurs prêtes : elles se balancent
	local bloomBed: any = nil
	for _, bed in ipairs(self.Beds) do
		local hero = bed.Hero
		if hero and (bed.Stage == "Ready" or bed.Stage == "Bloom") then
			bloomBed = bloomBed or bed
			if bed.Stage == "Ready" then
				bloomBed = bed
				local p = bed.Phase
				hero:PivotTo(bed.HeroCF * CFrame.Angles(math.sin(t * 1.9 + p) * 0.07, math.sin(t * 0.7 + p) * 0.1, math.sin(t * 1.4 + p * 0.7) * 0.06))
			end
		end
	end
	-- moulin
	local blades = self.Blades
	if blades then
		blades:PivotTo(self.BladesCF * CFrame.Angles(0, 0, -t * 1.6))
	end
	-- papillons autour d'une fleur ouverte
	for k, fly in ipairs(self.Butterflies) do
		if bloomBed then
			local center = bloomBed.HeroCF.Position + Vector3.new(0, bloomBed.TopHeight + 0.4, 0)
			local a = t * 0.9 + fly.Phase
			local pos = center + Vector3.new(math.cos(a) * (1.4 + k * 0.4), math.sin(t * 2.3 + k) * 0.35 + k * 0.3, math.sin(a) * (1.1 + k * 0.3))
			local heading = Vector3.new(-math.sin(a), 0, math.cos(a))
			local body = CFrame.lookAt(pos, pos + heading)
			local flap = math.sin(t * 16 + fly.Phase) * 0.9
			fly.Body.CFrame = body
			fly.Left.CFrame = body * CFrame.Angles(0, 0, flap) * CFrame.new(-0.26, 0, 0)
			fly.Right.CFrame = body * CFrame.Angles(0, 0, -flap) * CFrame.new(0.26, 0, 0)
			fly.Body.Transparency = 0
			fly.Left.Transparency = 0
			fly.Right.Transparency = 0
		elseif fly.Body.Transparency < 1 then
			fly.Body.Transparency = 1
			fly.Left.Transparency = 1
			fly.Right.Transparency = 1
		end
	end
end

----------------------------------------------------------------------
-- Actions du propriétaire (RemoteFunction "Garden" existante)
----------------------------------------------------------------------

-- Texte flottant (BillboardGui) qui monte et s'efface
function GardenBuilder._float(self: Garden, position: Vector3, text: string, color: Color3, big: boolean?)
	if self.Destroyed or not self.Layout then
		return
	end
	local anchor = newPart(self.Layout, "FloatText", Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), WHITE, M.SmoothPlastic)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Name = "Float"
	gui.Size = UDim2.fromOffset(big and 220 or 200, big and 56 or 40)
	gui.StudsOffset = Vector3.new(0, 0.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(80, 40, 20)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = anchor
	TweenService:Create(gui, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.6, function()
		anchor:Destroy()
	end)
end

-- Éclat de la cueillette : pétales + étincelles + anneau + "+X 🧠"
function GardenBuilder._pop(self: Garden, bed: any, flowerId: string, reward: number)
	if self.Destroyed or not self.Layout then
		return
	end
	local style = FLOWER_STYLE[flowerId] or DEFAULT_STYLE
	local head = bed.HeroCF.Position + Vector3.new(0, math.max(0.8, bed.TopHeight * 0.85), 0)
	local anchor = newPart(self.Layout, "HarvestPop", Vector3.new(0.4, 0.4, 0.4), CFrame.new(head), WHITE, M.SmoothPlastic)
	anchor.Transparency = 1
	local petals = Instance.new("ParticleEmitter")
	petals.Name = "Petals"
	petals.Color = ColorSequence.new(style.Petal, style.Inner or style.Petal)
	petals.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34), NumberSequenceKeypoint.new(1, 0.12) })
	petals.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.1), NumberSequenceKeypoint.new(1, 1) })
	petals.Lifetime = NumberRange.new(0.8, 1.3)
	petals.Speed = NumberRange.new(6, 11)
	petals.SpreadAngle = Vector2.new(75, 75)
	petals.Acceleration = Vector3.new(0, -14, 0)
	petals.Drag = 2
	petals.Rotation = NumberRange.new(0, 360)
	petals.RotSpeed = NumberRange.new(-240, 240)
	petals.Rate = 0
	petals.Parent = anchor
	local stars = Instance.new("ParticleEmitter")
	stars.Name = "Stars"
	stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	stars.Color = ColorSequence.new(WHITE, GOLD)
	stars.LightEmission = 1
	stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	stars.Transparency = NumberSequence.new(0, 1)
	stars.Lifetime = NumberRange.new(0.5, 0.9)
	stars.Speed = NumberRange.new(4, 8)
	stars.SpreadAngle = Vector2.new(180, 180)
	stars.Rate = 0
	stars.Parent = anchor
	pcall(function()
		petals:Emit(26)
		stars:Emit(14)
	end)
	-- anneau lumineux qui s'élargit sur la terre
	local ring = disc(self.Layout, "PopRing", 1.2, 0.08, CFrame.new(bed.HeroCF.Position + Vector3.new(0, 0.08, 0)), GOLD, M.Neon)
	ring.Transparency = 0.2
	TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.08, 6.5, 6.5), Transparency = 1 }):Play()
	task.delay(2.2, function()
		anchor:Destroy()
		ring:Destroy()
	end)
	-- la fleur cueillie disparaît dans l'éclat (la nouvelle graine suit)
	if bed.Plants then
		bed.Plants:Destroy()
		bed.Plants = nil
		bed.Hero = nil
	end
	self:_float(head + Vector3.new(0, 0.6, 0), "+" .. NumberFormatter.Format(reward) .. " 🧠", GOLD, style == FLOWER_STYLE.Sunflower or flowerId == "Lotus")
end

-- Heure du serveur (réponse de GardenService) : corrige un décalage net
function GardenBuilder._syncClock(self: Garden, serverNow: any)
	if type(serverNow) == "number" and serverNow == serverNow then
		local offset = serverNow - rawServerNow()
		if math.abs(offset) > 3 then
			self.ClockOffset = offset
		end
	end
end

function GardenBuilder._applyPlots(self: Garden, plots: any)
	if type(plots) ~= "table" or self.Destroyed then
		return
	end
	local state = self.State
	self:Update({ Unlocked = true, Count = math.max(#plots, 1), Max = math.max(state.Max, #plots), Windmill = state.Windmill, Plots = plots })
end

local function invokeGarden(action: string, arg: any): (boolean, any, any)
	return pcall(function()
		return Net.Function("Garden"):InvokeServer(action, arg)
	end)
end

function GardenBuilder._activate(self: Garden, index: number)
	if self.Destroyed or not self.IsOwner then
		return
	end
	local bed = self.Beds[index]
	if not bed or bed.Kind ~= "Plot" or bed.Pending then
		return
	end
	local plot = self.State.Plots[index]
	local now = self:_now()
	local above = bed.HeroCF.Position + Vector3.new(0, math.max(1.2, bed.TopHeight) + 0.8, 0)
	-- parterre vide : ("harvest", index) -> le serveur replante (sanitize) avant de répondre
	if bed.Flower == "" then
		bed.Pending = true
		task.spawn(function()
			local callOk, success, result = invokeGarden("harvest", index)
			bed.Pending = false
			if self.Destroyed then
				return
			end
			if callOk and success == true and type(result) == "table" then
				self:_syncClock(result.Now)
				self:_applyPlots(result.Plots)
			end
			self:_float(above, Locale.T("🌱 Planted!"), Color3.fromRGB(120, 210, 100))
		end)
		return
	end
	local _, ready, remaining = GardenSnapshot.Progress(plot, now)
	if not ready then
		self:_float(above, Locale.T("%s · ready in %s", flowerLabel(bed.Flower), clockText(remaining)), WHITE)
		return
	end
	bed.Pending = true
	if bed.Prompt then
		bed.Prompt.Enabled = false
	end
	task.spawn(function()
		local callOk, success, result = invokeGarden("harvest", index)
		bed.Pending = false
		if self.Destroyed then
			return
		end
		if callOk and success == true and type(result) == "table" then
			self:_syncClock(result.Now)
			self:_pop(bed, tostring(result.Flower or bed.Flower), tonumber(result.Reward) or 0)
			local callback = self.Options.OnHarvest
			if type(callback) == "function" then
				task.spawn(callback, result)
			end
			task.delay(0.35, function()
				self:_applyPlots(result.Plots)
			end)
		else
			local message = (callOk and type(result) == "string") and result or Locale.T("The garden is resting 🌙")
			self:_float(above, message, Color3.fromRGB(255, 130, 130))
			self:_refreshStages(false)
		end
	end)
end

function GardenBuilder._harvestAll(self: Garden)
	if self.Destroyed or not self.IsOwner or self.HarvestingAll then
		return
	end
	self.HarvestingAll = true
	if self.SignPrompt then
		self.SignPrompt.Enabled = false
	end
	task.spawn(function()
		local callOk, success, result = invokeGarden("harvestAll", nil)
		self.HarvestingAll = false
		if self.Destroyed then
			return
		end
		if callOk and success == true and type(result) == "table" and type(result.Harvested) == "table" then
			self:_syncClock(result.Now)
			for order, entry in ipairs(result.Harvested) do
				local bed = type(entry) == "table" and self.Beds[tonumber(entry.Plot) or 0]
				if bed and bed.Kind == "Plot" then
					task.delay((order - 1) * 0.09, function()
						self:_pop(bed, tostring(entry.Flower or bed.Flower), tonumber(entry.Reward) or 0)
					end)
				end
			end
			local callback = self.Options.OnHarvest
			if type(callback) == "function" then
				task.spawn(callback, result)
			end
			task.delay(0.35 + #result.Harvested * 0.09, function()
				self:_applyPlots(result.Plots)
			end)
		else
			local message = (callOk and type(result) == "string") and result or Locale.T("The garden is resting 🌙")
			self:_float(self.Origin.Position + Vector3.new(0, 5, 0), message, Color3.fromRGB(255, 130, 130))
		end
	end)
end

function GardenBuilder.Destroy(self: Garden)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	table.clear(self.Beds)
	table.clear(self.Butterflies)
	table.clear(self.Lights)
	self.Layout = nil
	self.Blades = nil
	pcall(function()
		self.Model:Destroy()
	end)
end

-- (pour les tests / l'émulateur)
GardenBuilder.STAGES = STAGE_NAMES
GardenBuilder.FLOWERS = { "Daisy", "Tulip", "Rose", "Sunflower", "Lotus" }

return GardenBuilder
